;;; gradus/install.scm — the installation backend shared by every front-end.
;;; Copyright © 2026 Zhen-Lin Huo <zhen-lin.huo@gmx.com>
;;;
;;; This file is part of Gradus.

(define-module (gradus install)
  #:use-module (ice-9 popen)
  #:use-module (ice-9 rdelim)
  #:use-module (gradus utils)
  #:use-module (gradus storage)
  #:use-module (gradus render)
  #:use-module (gradus serialize)
  #:use-module (gradus answers)
  #:use-module (gradus config)
  #:use-module (gradus provenance)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:use-module (ice-9 format)
  #:use-module (guix build utils)
  #:export (mount-plan
            resolve-source
            install-config
            install-answers
            install-answers/alist
            apply-proxy-environment
            restart-guix-daemon))


(define (resolve-source source)
  "Turn LABEL=... into a device path: mount would resolve it through
/dev/disk/by-label, which only exists once udev has noticed the new
filesystem -- and an installer mounts seconds after mkfs.  findfs scans the
devices directly and needs no udev."
  (if (and (string? source) (string-prefix? "LABEL=" source))
      (let* ((port (open-input-pipe (string-append "findfs " source)))
             (line (read-line port))
             (status (close-pipe port)))
        (if (and (string? line) (string-prefix? "/dev/" line))
            line
            source))
      source))

(define (mount-plan plan root)
  "Mount every file system in PLAN beneath ROOT, parents first.  Return #t on
success; raise on the first failure."
  (for-each
   (lambda (fs)
     (let* ((point (assoc-ref fs 'mount-point))
            (target (if (string=? point "/")
                        root
                        (string-append root point)))
            (source (resolve-source (assoc-ref fs 'source)))
            (type (assoc-ref fs 'type))
            (options (assoc-ref fs 'options)))
       (mkdir-p target)
       (log-line "mounting ~a on ~a (~a)" source target type)
       (let ((args (append (list "mount" "-t" type)
                           (if (and (string? options)
                                    (not (string=? options "")))
                               (list "-o" options)
                               '())
                           (list source target))))
         (unless (zero? (apply run-command/stream args))
           (error "mount failed" source target)))))
   (assoc-ref plan 'file-systems))
  #t)

(define (install-config config-file root)
  "Validate CONFIG-FILE and install it beneath ROOT."
  (log-line "==> [1/4] checking the declaration: ~a" config-file)
  (unless (zero? (run-command/stream "guix" "system" "build"
                                     "--dry-run" "--no-grafts" config-file))
    (exit +exit-validation+))
  (let ((os (load-configuration config-file)))
    ;; A previous attempt may have left the target mounted, or files behind in
    ;; it; guix's mount refuses a non-empty directory, and an installer must be
    ;; safe to run twice.
    (log-line "==> [2/4] clearing ~a" root)
    (system* "sh" "-c" (string-append "umount -R " root " 2>/dev/null || true"))
    (when (zero? (status:exit-val (system* "mountpoint" "-q" root)))
      (error "the target is still mounted; unmount it first" root))
    (when (file-exists? root)
      (unless (zero? (status:exit-val
                      (system* "sh" "-c"
                               (string-append "find " root
                                              " -mindepth 1 -maxdepth 1 -exec rm -rf {} +"))))
        (error "cannot empty the target directory" root)))
    ;; mkfs has just written a label; the /dev/disk/by-label link appears once
    ;; udev has looked at the device.  Without this, mounting by label fails
    ;; with "can't find LABEL=...".
    (system* "sh" "-c" "udevadm trigger --settle 2>/dev/null || true")
    (log-line "==> [2/4] mounting the target beneath ~a" root)
    (catch #t
      (lambda () (mount-plan (configuration-plan os) root))
      (lambda (key . args)
        (log-line "cannot prepare the target: ~a" args)
        (exit +exit-target+)))
    (log-line "==> [3/4] installing the system (downloads may take 10-30 minutes)")
    (unless (zero? (run-command/stream "guix" "system" "init" config-file root))
      (exit +exit-install+))
    (write-provenance root config-file "config")
    (log-line "==> [4/4] installed; declaration kept at ~a/etc/config.scm" root)))

(define (substitute-urls answers)
  "The substitute URLs declared in ANSWERS, in the order written."
  (filter-map (lambda (service) (assq-ref service 'url))
              (or (assq-ref (assq-ref answers 'source) 'substitute-services) '())))

(define (authorize-declared-keys answers)
  "Authorise the signing keys the answers name, when they are readable.  A
failure is reported, not fatal: an unauthorised builder simply will not be
used, and the installation falls back to the sources it can trust."
  (for-each
   (lambda (service)
     (let ((key (assq-ref service 'key)))
       (when (and key (file-exists? key))
         (unless (zero? (run-command/stream
                         "sh" "-c"
                         (format #f "guix archive --authorize < ~a" key)))
           (log-line "could not authorise ~a; its substitutes will be refused" key)))))
   (or (assq-ref (assq-ref answers 'source) 'substitute-services) '())))

(define (apply-proxy-environment answers)
  "Put the proxy from the answers into this process's environment: channel
fetches and any HTTP the installer performs itself read these variables."
  (let ((proxy (assq-ref answers 'proxy)))
    (when proxy
      (let ((http (assq-ref proxy 'http))
            (https (assq-ref proxy 'https))
            (no-proxy (assq-ref proxy 'no-proxy)))
        (when http (setenv "http_proxy" http))
        (when https (setenv "https_proxy" https))
        (when no-proxy
          (setenv "no_proxy" (string-join no-proxy ",")))
        (log-line "proxy: http=~a https=~a no_proxy=~a"
                  (or http "-") (or https "-")
                  (if no-proxy (string-join no-proxy ",") "-"))))))

(define (restart-daemon-requested?)
  ;; Kept for operators who run the installer on a machine they do not own:
  ;; GRADUS_NO_DAEMON_RESTART=1 leaves the running daemon alone.
  "Whether the operator asked for the daemon restart that makes substitutes
follow the proxy.  It is opt-in because restarting the daemon interrupts any
other build on the machine."
  (and=> (getenv "GRADUS_RESTART_DAEMON")
         (lambda (value) (string=? value "1"))))

(define (wait-for-daemon-socket attempts)
  "Wait for the guix-daemon socket, up to ATTEMPTS seconds."
  (cond ((file-exists? "/var/guix/daemon-socket/socket") #t)
        ((zero? attempts) #f)
        (else (sleep 1) (wait-for-daemon-socket (- attempts 1)))))

(define (restart-guix-daemon answers)
  "Restart guix-daemon so that it inherits the proxy environment.  Substitutes
are fetched by the daemon, so exporting the variables in this process does not
reach them.  Only runs when the answers declare a proxy and the operator opted
in: stopping the daemon interrupts any other build on the machine."
  (when (not (getenv "GRADUS_NO_DAEMON_RESTART"))
    (if #f #f
        (begin
          (log-line "restarting guix-daemon to apply the proxy")
          (unless (zero? (run-command/stream "herd" "stop" "guix-daemon"))
            (log-line "could not stop guix-daemon")
            (exit +exit-install+))
          ;; A rerun must not leave a previous daemon competing for the store
          ;; locks; the restart owns the daemon from here on.
          (run-command/stream "pkill" "-x" "guix-daemon")
          (sleep 1)
          (let* ((urls (filter-map
                        (lambda (service) (assq-ref service 'url))
                        (or (assq-ref (assq-ref answers 'source)
                                      'substitute-services)
                            '())))
                 (url-option (if (pair? urls)
                                 (string-append " --substitute-urls='"
                                                (string-join urls " ") "'")
                                 "")))
            (unless (zero? (run-command/stream
                            "sh" "-c"
                            (string-append
                             "guix-daemon --build-users-group=guixbuild"
                             url-option
                             " >/var/log/gradus-daemon.log 2>&1 &")))
              (log-line "could not start guix-daemon")
              (exit +exit-install+)))
          (unless (wait-for-daemon-socket 20)
            (log-line "the daemon socket did not appear; restore it with 'herd start guix-daemon'")
            (exit +exit-install+))))))

(define (install-answers/alist answers answers-file root)
  "Prepare the target from the ANSWERS alist, render, mount and install.
ANSWERS-FILE is where the answers are (or will be) recorded for provenance."
  (let* ((answers (validate-answers answers))
         (device-map (prepare-target answers))
         (os (render-answers/devices answers device-map))
         (declaration "/tmp/gradus-declaration.scm"))
    (apply-proxy-environment answers)
    (restart-guix-daemon answers)
    (serialize-to-file declaration answers device-map)
    (log-line "mounting the target beneath ~a" root)
    (catch #t
      (lambda () (mount-plan (configuration-plan os) root))
      (lambda (key . args)
        (log-line "cannot prepare the target: ~a" args)
        (exit +exit-target+)))
    (authorize-declared-keys answers)
    (log-line "installing")
    (let* ((urls (substitute-urls answers))
           (options (if (null? urls) '()
                        (list (string-append "--substitute-urls="
                                             (string-join urls " "))))))
      (when (pair? urls)
        (log-line "substitutes: ~a" (string-join urls " ")))
      (unless (zero? (apply run-command/stream
                            (append (list "guix" "system" "init")
                                    options
                                    (list declaration root))))
        (exit +exit-install+)))
    (write-provenance root declaration "answers")
    (log-line "installed; declaration kept at ~a/etc/config.scm" root)))

(define (install-answers answers-file root)
  "Read ANSWERS-FILE and install the system it describes beneath ROOT."
  (install-answers/alist (read-answers answers-file) answers-file root))
