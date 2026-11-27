;;; tests/selection.scm — the selection models.
;;; Copyright © 2026 Zhen-Lin Huo <zhen-lin.huo@gmx.com>
;;;
;;; This file is part of Gradus.

(use-modules (srfi srfi-64)
             (gradus selection))

(define runner (test-runner-simple))
(test-runner-current runner)

  (define with-substitutes
    '((source
       (substitute-services
        ((url . "https://mirror.example/guix") (kind . mirror))
        ((url . "https://cache.example.net") (kind . builder)
         (key . "/etc/keys/cache.pub"))
        ((url . "https://ci.guix.gnu.org") (kind . official))))))

  (define without-source '())

  (test-equal "the substitute services keep preference order"
    '("https://mirror.example/guix" "https://cache.example.net"
      "https://ci.guix.gnu.org")
    (selection-substitute-urls with-substitutes))

  (test-equal "a missing source section is an empty list"
    '() (selection-substitute-urls without-source))

  (test-equal "only a builder names a signing key"
    '("/etc/keys/cache.pub")
    (selection-signing-keys with-substitutes))

  (test-equal "a full proxy becomes the three daemon variables"
    '(("http_proxy" . "http://proxy.example:3128")
      ("https_proxy" . "http://proxy.example:3128")
      ("no_proxy" . "localhost,cache.example.net"))
    (selection-proxy-environment
     '((proxy (http . "http://proxy.example:3128")
              (https . "http://proxy.example:3128")
              (no-proxy . ("localhost" "cache.example.net"))))))

  (test-equal "an absent variable is omitted, not passed as false"
    '(("http_proxy" . "http://proxy.example:3128"))
    (selection-proxy-environment
     '((proxy (http . "http://proxy.example:3128")))))

  (test-equal "no proxy section is an empty environment"
    '() (selection-proxy-environment without-source))

  (test-equal "kernel arguments default to the empty list"
    '() (selection-kernel-arguments '((boot (bootloader . grub-bios)))))

  (test-equal "kernel arguments come from the boot section"
    '("console=ttyS0,115200")
    (selection-kernel-arguments
     '((boot (bootloader . grub-bios)
             (extra-kernel-arguments "console=ttyS0,115200")))))

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
