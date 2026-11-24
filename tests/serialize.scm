;;; tests/serialize.scm — the generated declaration must stand on its own.
;;; Copyright © 2026 Zhen-Lin Huo <zhen-lin.huo@gmx.com>
;;;
;;; This file is part of Gradus.

(use-modules (srfi srfi-64)
             (gnu bootloader)
             (gnu system shadow)
             (gnu system)
             (gradus serialize))

(define runner (test-runner-simple))
(test-with-runner runner

  (define answers
    '((schema-version . 1)
      (profile . "headless")
      (host-name . "vm0")
      (timezone . "UTC")
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

  (test-equal "one user is present" 1
    (length (operating-system-users os)))

  (test-equal "the bootloader target is the storage disk, not a mount point"
    '("/dev/vda")
    (bootloader-configuration-targets (operating-system-bootloader os)))

  (test-equal "the account password survives serialization"
    "$6$abcdefgh$3rj1vTLX64btReFsM4MQ22otcD40l7vbtw7qCyr0dxc4kxNmgx53xVM8gWiLYbCqTHTbXFaVFU7ZT28pnvdyu0"
    (user-account-password (car (operating-system-users os))))

  (test-assert "the groups the accounts refer to are declared"
    (let ((names (map user-group-name (operating-system-groups os))))
      (and (member "root" names) (member "wheel" names)
           (member "users" names)
           ;; %base-groups must survive, or system accounts lose theirs.
           (member "kvm" names)))))

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
