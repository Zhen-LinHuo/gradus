;;; gradus/serialize.scm — a standalone declaration from the answers.
;;; Copyright © 2026 Zhen-Lin Huo <zhen-lin.huo@gmx.com>
;;;
;;; This file is part of Gradus.
;;;
;;; The rendered operating-system is an in-memory record; `guix system init'
;;; needs a file, and that file must stand on its own after the installer is
;;; gone.  This module writes such a file from the answers and the device map.
;;; It covers the simple storage mode: identity, users, file systems with their
;;; UUIDs, the bootloader, and the Guix service with substitute URLs and proxy
;;; environment.  Signing keys are added with the source-page slice.

(define-module (gradus serialize)
  #:use-module (ice-9 format)
  #:use-module (ice-9 string-fun)
  #:use-module (gnu system)
  #:use-module (gnu system file-systems)
  #:use-module (gnu system uuid)
  #:use-module (gnu bootloader)
  #:use-module (gnu system mapped-devices)
  #:use-module (gradus answers)
  #:use-module (gradus render)
  #:use-module (gradus selection)
  #:use-module (srfi srfi-1)
  #:export (serialize-answers
            serialize-to-file
            declaration-summary))

;; The summary reader walks the written form, not the answers: after an edit
;; the file is the truth, and a display that keeps showing the answers would
;; show a system nobody is about to install.

(define (form-ref tree key)
  "The first (KEY ...) form anywhere in TREE, or #f."
  (cond ((pair? tree)
         (if (and (pair? (car tree)) (eq? (caar tree) key))
             (car tree)
             (or (form-ref (car tree) key)
                 (form-ref (cdr tree) key))))
        (else #f)))

(define (forms-ref tree key)
  "Every (KEY ...) form anywhere in TREE, in document order."
  (cond ((pair? tree)
         (append (if (and (pair? (car tree)) (eq? (caar tree) key))
                     (list (car tree))
                     '())
                 (forms-ref (car tree) key)
                 (forms-ref (cdr tree) key)))
        (else '())))

(define (quoted-value form)
  "The value of a (key 'value) form, unwrapping the quote."
  (let ((value (cadr form)))
    (if (and (pair? value) (eq? (car value) 'quote))
        (cadr value)
        value)))

(define (declaration-summary path)
  "Read the declaration at PATH and return its identity as an alist:
host-name, timezone, locale, keyboard, bootloader, users, packages and
substitute-urls.  Values are strings, except users, packages and
substitute-urls, which are lists of strings.  A field the file does not
carry is absent from the alist; a file that is not a declaration raises."
  (let* ((forms (call-with-input-file path
                   (lambda (port)
                     (let loop ((acc (quote ())))
                       (let ((form (read port)))
                         (if (eof-object? form)
                             (reverse acc)
                             (loop (cons form acc))))))))
         (form (find (lambda (candidate)
                       (and (pair? candidate)
                            (eq? (car candidate) (quote operating-system))))
                     forms)))
    (unless form
      (error "not a system declaration" path))
    (let* ((body (cdr form))
           (top (lambda (key)
                  (let ((cell (assq key body)))
                    (and cell (pair? (cdr cell)) (cadr cell)))))
           (account-names (lambda (key)
                            (let ((cell (assq key body)))
                              (if cell
                                  (filter-map
                                   (lambda (sub)
                                     (let ((name (form-ref sub (quote name))))
                                       (and name (cadr name))))
                                   (cdr cell))
                                  (quote ())))))
           (keyboard-value
            (let ((outer (form-ref body (quote keyboard-layout))))
              (let ((inner (and outer (pair? (cdr outer)) (cadr outer))))
                (cond ((and (pair? inner)
                            (eq? (car inner) (quote xkb-layout))
                            (pair? (cdr inner)))
                       (cadr inner))
                      ((and (pair? inner)
                            (eq? (car inner) (quote keyboard-layout))
                            (pair? (cdr inner))
                            (pair? (cadr inner)))
                       (let ((entry (assq (quote layout) (cadr inner))))
                         (and entry (cdr entry))))
                      (else #f)))))
           (bootloader-name
            (let ((value (top (quote bootloader))))
              (cond ((symbol? value) value)
                    ((pair? value)
                     (let ((inner (form-ref value (quote bootloader))))
                       (and inner (pair? (cdr inner)) (cadr inner)))))))
           (packages-tree (let ((cell (assq (quote packages) body)))
                            (and cell (cdr cell))))
           (direct-packages
            (filter-map (lambda (form)
                          (and (pair? (cdr form)) (string? (cadr form))
                               (cadr form)))
                        (forms-ref packages-tree
                                   (quote specification->package))))
           (quoted-packages
            (find (lambda (form)
                    (and (pair? (cdr form))
                         (pair? (cadr form))
                         (every string? (cadr form))))
                  (forms-ref packages-tree (quote quote))))
           (urls (form-ref body (quote substitute-urls))))
      (append
       (let ((value (top (quote host-name))))
         (if value (list (cons (quote host-name) value)) (quote ())))
       (let ((value (top (quote timezone))))
         (if value (list (cons (quote timezone) value)) (quote ())))
       (let ((value (top (quote locale))))
         (if value (list (cons (quote locale) value)) (quote ())))
       (if keyboard-value
           (list (cons (quote keyboard) keyboard-value))
           (quote ()))
       (if bootloader-name
           (list (cons (quote bootloader) (symbol->string bootloader-name)))
           (quote ()))
       (list (cons (quote users) (account-names (quote users))))
       (list (cons (quote packages)
                   (append direct-packages
                           (if quoted-packages
                               (cadr quoted-packages)
                               (quote ())))))
       (list (cons (quote substitute-urls)
                   (if urls (quoted-value urls) (quote ()))))
       (list (cons (quote environments) (declaration-environments body)))))))


;; The environments the declaration installs: the four service types by
;; their service call, the package sets by each set's marker package.
(define %service-environments
  '((gnome-desktop-service-type . gnome)
    (xfce-desktop-service-type . xfce)
    (mate-desktop-service-type . mate)
    (plasma-desktop-service-type . plasma)))

(define %package-set-markers
  '(("icewm" . icewm) ("openbox" . openbox) ("awesome" . awesome)
    ("i3-wm" . i3) ("ratpoison" . ratpoison)
    ("emacs-exwm" . exwm) ("sway" . sway)))

(define (declaration-environments body)
  "The desktop environments installed by the declaration BODY, as symbols."
  (let* ((services (form-ref body 'services))
         (from-services
          (filter-map
           (lambda (call)
             (and (pair? call)
                  (eq? (car call) 'service)
                  (pair? (cdr call))
                  (assq-ref %service-environments (cadr call))))
           (forms-ref services 'service)))
         (names (let* ((cell (assq 'packages body))
                       (tree (and cell (cdr cell))))
                  (let ((quoted (find (lambda (form)
                                        (and (pair? (cdr form))
                                             (pair? (cadr form))
                                             (every string? (cadr form))))
                                      (forms-ref tree 'quote))))
                    (if quoted (cadr quoted) '()))))
         (from-packages
          (filter-map
           (lambda (marker)
             (and (member (car marker) names) (cdr marker)))
           %package-set-markers)))
    (delete-duplicates (append from-services from-packages))))

(define (emit-user port user)
  (format port "    (user-account~%")
  (format port "      (name ~s)~%" (assq-ref user (quote name)))
  (format port "      (group ~s)~%" (or (assq-ref user (quote group)) "users"))
  (format port "      (supplementary-groups (quote ~s))~%"
          (or (assq-ref user (quote groups)) (list "wheel")))
  (format port "      (home-directory ~s)~%"
          (string-append "/home/" (assq-ref user (quote name))))
  ;; The password is already a crypt hash; without it the account is
  ;; locked, so the field is only emitted when an answer provides one.
  (when (assq-ref user (quote password))
    (format port "      (password ~s)~%" (assq-ref user (quote password))))
  (format port "      )~%"))

(define (emit-file-system port fs)
  (let ((device (file-system-device fs)))
    (format port "    (file-system~%")
    (format port "      (mount-point ~s)~%" (file-system-mount-point fs))
    (cond ((uuid? device)
           (format port "      (device (uuid ~s '~a))~%"
                   (uuid->string device) (uuid-type device)))
          ((file-system-label? device)
           (format port "      (device (file-system-label ~s))~%"
                   (file-system-label->string device)))
          (else
           (format port "      (device ~s)~%"
                   (file-system-device->string device))))
    (format port "      (type ~s))~%" (file-system-type fs))))

(define (emit-services port answers)
  (let ((urls (selection-substitute-urls answers))
        (environment (proxy-environment answers)))
    (format port "  (services~%")
    (format port "   (append~%")
    (let* ((network (or (assq-ref answers 'network) '()))
           (static? (eq? (assq-ref network 'management) 'static))
           (desktop? (desktop-environment? answers))
           (keyboard (assq-ref answers 'keyboard)))
      (format port "    (list (service openssh-service-type)~%")
      ;; A desktop leaves networking to NetworkManager, which comes with
      ;; %desktop-services: neither dhcpcd nor static-networking joins it.
      (unless desktop?
        (if static?
            (format port "          (service static-networking-service-type~%           (list (static-networking~%                   (addresses (list (network-address~%                                 (device ~s)~%                                 (value ~s))))~%                   (routes (list (network-route~%                                  (destination \"default\")~%                                  (gateway ~s))))~%                   (name-servers '~s))))~%"
                    (assq-ref network 'interface)
                    (assq-ref network 'address)
                    (assq-ref network 'gateway)
                    (or (assq-ref network 'name-servers) '()))
            (format port "          (service dhcpcd-service-type)~%")))
      (when (assq-ref answers 'ntp)
        (format port "          (service ntp-service-type)~%"))
      ;; The environments that are services, spelled the way render.scm
      ;; builds them (keep the two lists in step).
      (for-each
       (lambda (environment)
         (let ((type (case environment
                       ((gnome) "gnome-desktop-service-type")
                       ((xfce) "xfce-desktop-service-type")
                       ((mate) "mate-desktop-service-type")
                       ((plasma) "plasma-desktop-service-type")
                       (else #f))))
           (when type
             (format port "          (service ~a)~%" type))))
       (answer-environments answers))
      (when (and desktop? keyboard)
        (format port "          (set-xorg-configuration~%")
        (format port "            (xorg-configuration (keyboard-layout ~s)))~%"
                keyboard)))
    (format port "    )~%")
    (format port "    (modify-services ~a~%"
            (if (desktop-environment? answers) "%desktop-services" "%base-services"))
    (format port "      (guix-service-type config =>~%")
    (format port "        (guix-configuration~%")
    (format port "         (inherit config)~%")
    (format port "         (substitute-urls '~s)~%" urls)
    (format port "         (environment '~s))))))~%" environment)))

(define (emit-mapped-type port type)
  "Write the TYPE of a mapped device as the variable that names it in Guix."
  (format port "      (type ~a))~%"
          (cond ((eq? type luks-device-mapping) "luks-device-mapping")
                ((eq? type lvm-device-mapping) "lvm-device-mapping")
                (else (error "unknown mapped-device type" type)))))

(define (emit-mapped-source port source)
  "Write a mapped-device SOURCE.  A UUID object is not readable when printed
with ~s, so LUKS containers are emitted as `(uuid STRING 'luks)' — the only
form GRUB can unlock by, and the form `crypt-source' produces."
  (if (uuid? source)
      (format port "      (source (uuid ~s '~a))~%"
              (uuid->string source) (uuid-type source))
      (format port "      (source ~s)~%" source)))

(define (serialize-answers answers device-map)
  "Return the text of a self-contained operating-system declaration.  Refuse to
write an encrypted declaration whose container UUID is unknown: the result would
carry no `cryptomount' line and the machine could not boot."
  (let ((os (render-answers/devices answers device-map))
        (boot (assq-ref answers 'boot))
        (users (assq-ref answers 'users)))
    (when (and (assq-ref (assq-ref answers 'storage) 'encryption)
               (not (crypt-container-known? device-map)))
      (answers-error
       "refusing to write an encrypted declaration without the container's LUKS UUID"))
    (call-with-output-string
     (lambda (port)
       (format port ";;; generated by gradus -- edit the answers file, not this file~%")
       (format port "(use-modules (gnu) (gnu packages linux) (gnu system)~%")
       (format port "             (gnu system file-systems) (gnu system uuid)~%")
       (format port "             (gnu bootloader) (gnu services) (gnu system keyboard)
             (gnu system mapped-devices)
             (gnu packages)~%")
       (format port "             (gnu services base) (gnu services ssh) (gnu services networking)~%")
       (format port "             (gnu services desktop) (gnu services xorg))~%~%")
       (format port "(operating-system~%")
       (format port "  (host-name ~s)~%" (operating-system-host-name os))
       (format port "  (timezone ~s)~%" (operating-system-timezone os))
       (format port "  (locale ~s)~%" (operating-system-locale os))
       (format port "  (kernel linux-libre)~%")
       (let ((keyboard (assq-ref answers 'keyboard)))
         (when keyboard
           (format port "  (keyboard-layout (keyboard-layout ~s))~%" keyboard)))
       (let ((arguments (selection-kernel-arguments answers)))
         (when (pair? arguments)
           (format port "  (kernel-arguments '~s)~%" arguments)))
       (let ((extra (append (answer-package-names answers)
                            (answer-desktop-package-names answers))))
         (if (null? extra)
             (format port "  (packages %base-packages)~%")
             (format port "  (packages (append (map specification->package '~s) %base-packages))~%"
                     extra)))
       (format port "  (bootloader~%")
       (format port "   (bootloader-configuration~%")
       (format port "    (bootloader ~a)~%"
               (if (eq? (assq-ref boot 'bootloader) 'grub-bios)
                   "grub-bootloader" "grub-efi-bootloader"))
       (format port "    (targets '(~a))~%"
               (string-join
                (map (lambda (target)
                       ;; A mount-point target only makes sense for EFI; a BIOS
                       ;; bootloader is installed on the storage disk.
                       (format #f "\"~a\""
                               (if (or (string-prefix? "/dev/" target)
                                       (eq? (assq-ref boot 'bootloader)
                                            'grub-efi))
                                   ;; EFI installs into the mounted ESP, so a
                                   ;; mount point is the correct target there.
                                   target
                                   (assq-ref (assq-ref answers 'storage)
                                             'disk))))
                     (bootloader-configuration-targets
                      (operating-system-bootloader os)))
                " "))
       (format port "    (timeout ~a)~%" (or (assq-ref boot 'timeout) 5))
       ;; A headless machine reads the menu and answers the passphrase prompt
       ;; on the serial line, so the terminals have to survive serialisation.
       (let* ((outputs (or (assq-ref boot 'terminal-outputs) '()))
              (inputs (or (assq-ref boot 'terminal-inputs) '()))
              (serial? (or (memq 'serial outputs) (memq 'serial inputs))))
         (when (pair? outputs)
           (format port "    (terminal-outputs '~s)~%" outputs))
         (when (pair? inputs)
           (format port "    (terminal-inputs '~s)~%" inputs))
         (when serial?
           (format port "    (serial-unit ~a)~%"
                   (or (assq-ref boot 'serial-unit) 0))
           (format port "    (serial-speed ~a)~%"
                   (or (assq-ref boot 'serial-speed) 115200))))
       (format port "    ))~%")
       (format port "  (file-systems~%")
       (format port "   (list~%")
       (for-each (lambda (fs) (emit-file-system port fs))
                 (operating-system-file-systems os))
       (format port "   ))~%")
       (let ((mapped (operating-system-mapped-devices os)))
         (when (pair? mapped)
           (format port "  (mapped-devices~%")
           (format port "   (list~%")
           (for-each
            (lambda (device)
              (format port "    (mapped-device~%")
              (emit-mapped-source port (mapped-device-source device))
              (format port "      (targets '~s)~%"
                      (mapped-device-targets device))
              (emit-mapped-type port (mapped-device-type device)))
            mapped)
           (format port "   ))~%")))
       (let ((swaps (operating-system-swap-devices os)))
         (when (pair? swaps)
           (format port "  (swap-devices~%")
           (format port "   (list~%")
           (for-each
            (lambda (swap)
              (format port "    (swap-space~%")
              (format port "      (target (file-system-label ~s)))~%"
                      (file-system-label->string (swap-space-target swap))))
            swaps)
           (format port "   ))~%")))
       (format port "  (users~%")
       (format port "   (list~%")
       (for-each (lambda (user) (emit-user port user)) users)
       (format port "   ))~%")
       (emit-services port answers)
       (format port ")~%")))))

(define (serialize-to-file file answers device-map)
  "Write the declaration for ANSWERS to FILE."
  (call-with-output-file file
    (lambda (port)
      (display (serialize-answers answers device-map) port))))
