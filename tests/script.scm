;;; tests/script.scm — unit tests for argument handling and planning.
;;; Copyright © 2026 Zhen-Lin Huo <zhen-lin.huo@gmx.com>
;;;
;;; This file is part of Gradus.

(use-modules (srfi srfi-64)
             (srfi srfi-1)
             (gnu system file-systems)
             (gnu system uuid)
             (gradus script)
             (gradus config))

(define runner (test-runner-simple))
(test-with-runner runner

  (test-begin "arguments")

  (test-equal "absolute paths pass through"
    "/tmp/x.scm"
    (absolute-path "/tmp/x.scm"))

  (test-equal "relative paths resolve against the working directory"
    (string-append (getcwd) "/system.scm")
    (absolute-path "system.scm"))

  (test-equal "version flag"
    '((version? . #t))
    (parse-arguments '("--version")))

  (test-equal "config with root"
    '((config . "system.scm") (root . "/target"))
    (parse-arguments '("--config" "system.scm" "--root" "/target")))

  (test-assert "unknown option is a usage error"
    (catch 'gradus-usage
      (lambda () (parse-arguments '("--nonsense")) #f)
      (lambda args #t)))

  (test-assert "a dangling option is a usage error"
    (catch 'gradus-usage
      (lambda () (parse-arguments '("--config")) #f)
      (lambda args #t)))

  (test-end "arguments")

  (test-begin "file-system-source")

  (test-equal "label becomes LABEL="
    "LABEL=root"
    (file-system-source
     (file-system (mount-point "/") (device (file-system-label "root"))
                  (type "ext4"))))

  (test-equal "UUID object becomes UUID="
    "UUID=12345678-1234-1234-1234-123456789abc"
    (file-system-source
     (file-system (mount-point "/")
                  (device (uuid "12345678-1234-1234-1234-123456789abc"))
                  (type "ext4"))))

  (test-equal "a device path is passed through"
    "/dev/sda2"
    (file-system-source
     (file-system (mount-point "/") (device "/dev/sda2") (type "ext4"))))

  (test-end "file-system-source")

  (test-begin "ordering")

  (let* ((ordered (map file-system-mount-point
                       (order-file-systems
                        (list (file-system (mount-point "/home")
                                           (device "/dev/sda3") (type "ext4"))
                              (file-system (mount-point "/boot/efi")
                                           (device "/dev/sda1") (type "vfat"))
                              (file-system (mount-point "/boot")
                                           (device "/dev/sda4") (type "ext4"))
                              (file-system (mount-point "/")
                                           (device "/dev/sda2") (type "ext4"))))))
         (index-of (lambda (point)
                     (list-index (lambda (p) (string=? p point)) ordered))))
    (test-equal "the root is mounted first" "/" (car ordered))
    (test-assert "a parent is mounted before its child"
      (< (index-of "/boot") (index-of "/boot/efi"))))

  (test-end "ordering"))

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
