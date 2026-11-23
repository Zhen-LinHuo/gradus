;;; tests/storage.scm — blkid parsing tests.
;;; Copyright © 2026 Zhen-Lin Huo <zhen-lin.huo@gmx.com>
;;;
;;; This file is part of Gradus.

(use-modules (srfi srfi-64)
             (gradus storage))

(define runner (test-runner-simple))
(test-with-runner runner

  (define sample
    (string-append "DEVNAME=/dev/loop0p1\n"
                   "TYPE=vfat\n"
                   "UUID=34CB-A679\n"
                   "LABEL=GRADUS-ESP\n"
                   "\n"
                   "DEVNAME=/dev/loop0p2\n"
                   "TYPE=ext4\n"
                   "UUID=1454237d-7923-4816-827a-3064eba2b19d\n"
                   "LABEL=gradus-root\n"))

  (define parsed (parse-blkid sample))

  (test-equal "two labelled devices are parsed"
    2 (length parsed))

  (test-equal "entries are keyed by label"
    '("GRADUS-ESP" "gradus-root") (map car parsed))

  (test-equal "the type and UUID are kept"
    '("ext4" "1454237d-7923-4816-827a-3064eba2b19d")
    (list (assq-ref (assoc-ref parsed "gradus-root") 'type)
          (assq-ref (assoc-ref parsed "gradus-root") 'uuid)))

  (test-equal "unlabelled devices are skipped"
    0 (length (parse-blkid "DEVNAME=/dev/sda1\nTYPE=ext4\n"))))

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
