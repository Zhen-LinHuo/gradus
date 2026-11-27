;;; tests/serialize.scm — the generated declaration must stand on its own.
;;; Copyright © 2026 Zhen-Lin Huo <zhen-lin.huo@gmx.com>
;;;
;;; This file is part of Gradus.

(use-modules (srfi srfi-64)
             (gnu bootloader)
             (gnu system keyboard)
             (gnu services)
             (gnu services networking)
             (gnu system shadow)
             (gnu system)
             (gnu system mapped-devices)
             (gnu system uuid)
             (gradus serialize))

(define runner (test-runner-simple))
(test-runner-current runner)

(define answers
  '((schema-version . 1)
    (profile . "headless")
    (host-name . "vm0")
    (timezone . "UTC")
    (keyboard . "us")
    (ntp . #t)
    (locale . "en_US.utf8")
    (storage (mode . simple) (disk . "/dev/vda"))
    (boot (bootloader . grub-efi) (timeout . 5))
    (users ((name . "tester") (group . "users")
            (password . "$6$abcdefgh$3rj1vTLX64btReFsM4MQ22otcD40l7vbtw7qCyr0dxc4kxNmgx53xVM8gWiLYbCqTHTbXFaVFU7ZT28pnvdyu0")))))

(define device-map
  '(("gradus-root" (device . "/dev/vda2") (type . "ext4")
                   (uuid . "1454237d-7923-4816-827a-3064eba2b19d"))
    ("GRADUS-ESP" (device . "/dev/vda1") (type . "vfat")
                  (uuid . "34CB-A679"))))

(define file (string-append (or (getenv "TMPDIR") "/tmp")
                            "/gradus-serialized.scm"))
(serialize-to-file file answers device-map)
(define os (load file))

(test-assert "the generated file is a declaration"
  (operating-system? os))

(test-equal "the host name survives" "vm0"
  (operating-system-host-name os))

(test-equal "both file systems are present" 2
  (length (operating-system-file-systems os)))

(test-equal "the keyboard layout is rendered"
  "us"
  (keyboard-layout-name (operating-system-keyboard-layout os)))

(test-assert "NTP is rendered when the answers ask for it"
  (memq 'ntp (map (lambda (service)
                    (service-type-name (service-kind service)))
                  (operating-system-services os))))

(test-equal "one user is present" 1
  (length (operating-system-users os)))

(test-equal "an EFI bootloader targets the mounted ESP"
  '("/boot/efi")
  (bootloader-configuration-targets (operating-system-bootloader os)))

(test-equal "the account password survives serialization"
  "$6$abcdefgh$3rj1vTLX64btReFsM4MQ22otcD40l7vbtw7qCyr0dxc4kxNmgx53xVM8gWiLYbCqTHTbXFaVFU7ZT28pnvdyu0"
  (user-account-password (car (operating-system-users os))))

(test-assert "the groups the accounts refer to are declared"
  (let ((names (map user-group-name (operating-system-groups os))))
    (and (member "root" names) (member "wheel" names)
         (member "users" names)
         ;; %base-groups must survive, or system accounts lose theirs.
         (member "kvm" names))))

;; An encrypted root: the written file must carry the LUKS UUID form, not an
;; opaque `#<uuid ...>' object that Guix would refuse to read back.
(let* ((encrypted
        (append (assq-remove! (copy-tree answers) 'storage)
                '((storage (mode . simple) (disk . "/dev/vda")
                           (encryption (mode . luks) (name . "cryptroot"))))))
       (crypt-map
        (append (copy-tree device-map)
                '(("gradus-crypt" (device . "/dev/vda2")
                                  (type . "crypto_LUKS")
                                  (uuid . "0b5d5f7a-9d5e-4b7a-9a58-4f0c1c6b0d11")))))
       (crypt-file (string-append (or (getenv "TMPDIR") "/tmp")
                                  "/gradus-serialized-luks.scm")))
  (serialize-to-file crypt-file encrypted crypt-map)
  (define text (call-with-input-file crypt-file
                 (lambda (port)
                   (let loop ((chars '()))
                     (let ((c (read-char port)))
                       (if (eof-object? c)
                           (list->string (reverse chars))
                           (loop (cons c chars))))))))
  (define os (load crypt-file))

  (test-assert "the LUKS source is written as a readable uuid form"
    (string-contains text "(source (uuid \"0b5d5f7a-9d5e-4b7a-9a58-4f0c1c6b0d11\" 'luks))"))

  (test-assert "the reloaded declaration keeps the LUKS mapped device"
    (let ((mapped (operating-system-mapped-devices os)))
      (and (= 1 (length mapped))
           (eq? 'luks (uuid-type (mapped-device-source (car mapped))))
           (equal? '("cryptroot") (mapped-device-targets (car mapped)))))))

  (test-assert "the serializer refuses an encrypted declaration without a UUID"
    (not (false-if-exception
          (serialize-to-file
           (string-append (or (getenv "TMPDIR") "/tmp")
                          "/gradus-refused.scm")
           encrypted (copy-tree device-map)))))


(define serial-answers
  (acons 'boot '((bootloader . grub-efi) (timeout . 5)
                 (terminal-outputs console serial)
                 (terminal-inputs serial))
         answers))

(define serial-file (string-append (or (getenv "TMPDIR") "/tmp")
                                   "/gradus-serialized-serial.scm"))
(serialize-to-file serial-file serial-answers device-map)
(define serial-os (load serial-file))

(define (slurp file)
  (call-with-input-file file
    (lambda (port)
      (let loop ((chars '()))
        (let ((c (read-char port)))
          (if (eof-object? c)
              (list->string (reverse chars))
              (loop (cons c chars))))))))

(test-assert "the serial terminals reach the generated declaration"
  (string-contains (slurp serial-file)
                   "(terminal-outputs '(console serial))"))

(test-equal "the generated declaration speaks serial at 115200"
  '(0 115200)
  (let ((config (operating-system-bootloader serial-os)))
    (list (bootloader-configuration-serial-unit config)
          (bootloader-configuration-serial-speed config))))


  (test-equal "a headless declaration reports no environments"
    '()
    (let ((path (string-append (or (getenv "TMPDIR") "/tmp")
                               "/gradus-no-desktop.scm")))
      (serialize-to-file path answers device-map)
      (assq-ref (declaration-summary path) 'environments)))

  (test-equal "the declaration reports the environments it installs"
    '(gnome sway)
    (let ((path (string-append (or (getenv "TMPDIR") "/tmp")
                               "/gradus-desktop.scm")))
      (serialize-to-file path
                         (acons 'desktop '((environments . (gnome sway)))
                                answers)
                         device-map)
      (assq-ref (declaration-summary path) 'environments)))

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
