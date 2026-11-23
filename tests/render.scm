;;; tests/render.scm — answers-to-declaration rendering tests.
;;; Copyright © 2026 Zhen-Lin Huo <zhen-lin.huo@gmx.com>
;;;
;;; This file is part of Gradus.

(use-modules (srfi srfi-64)
             (gnu system)
             (gnu system file-systems)
             (gradus render))

(define runner (test-runner-simple))
(test-with-runner runner

  (define answers
    '((schema-version . 1)
      (profile . "headless")
      (host-name . "vm0")
      (timezone . "UTC")
      (locale . "en_US.utf8")
      (storage (mode . simple) (disk . "/dev/vda"))
      (boot (bootloader . grub-efi) (timeout . 3))
      (users ((name . "tester") (group . "users")))))

  (define (with-key key value)
    (append (assq-remove! (copy-tree answers) key)
            (list (cons key value))))

  (define os (render-answers answers))

  (test-assert "the result is an operating-system"
    (operating-system? os))

  (test-equal "the host name comes from the answers"
    "vm0"
    (operating-system-host-name os))

  (test-equal "one user is rendered"
    1
    (length (operating-system-users os)))

  (test-equal "the file systems are addressed by label"
    '("gradus-root" "GRADUS-ESP")
    (map (lambda (fs)
           (file-system-device->string (file-system-device fs)))
         (operating-system-file-systems os)))

  (test-assert "storage modes other than simple are refused"
    (catch #t
      (lambda ()
        (render-answers (with-key 'storage
                                 '((mode . lvm) (disk . "/dev/vda"))))
        #f)
      (lambda args #t)))

  (test-assert "bootloader `none' is refused by the renderer for now"
    (catch #t
      (lambda ()
        (render-answers (with-key 'boot '((bootloader . none))))
        #f)
      (lambda args #t))))

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
