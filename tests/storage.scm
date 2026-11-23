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
    0 (length (parse-blkid "DEVNAME=/dev/sda1\nTYPE=ext4\n")))

  (test-equal "field order inside a device block does not matter"
    '("ext4" "3cfb4b88-95d2-427d-a420-483f9122a96a")
    (let ((parsed (parse-blkid
                   (string-append "DEVNAME=/dev/dm-0\n"
                                  "LABEL=gradus-root\n"
                                  "TYPE=ext4\n"
                                  "UUID=3cfb4b88-95d2-427d-a420-483f9122a96a\n"))))
      (list (assq-ref (assoc-ref parsed "gradus-root") 'type)
            (assq-ref (assoc-ref parsed "gradus-root") 'uuid))))

  (define lvm-answer
    '((disk . "/dev/vda")
      (volume-group . "vg0")
      (volumes ((name . "root") (size . "100%FREE")))))

  (define commands (lvm-commands lvm-answer))

  (test-equal "the physical volume partition is marked for LVM"
    '("parted" "-s" "/dev/vda" "mklabel" "gpt"
      "mkpart" "ESP" "fat32" "1MiB" "1025MiB"
      "set" "1" "esp" "on"
      "mkpart" "pv" "ext4" "1025MiB" "100%"
      "set" "2" "lvm" "on")
    (list-ref commands 0))

  (test-equal "the volume group is created on the second partition"
    '("vgcreate" "vg0" "/dev/vda2")
    (list-ref commands 5))

  (test-equal "the root volume takes the remaining space"
    '("lvcreate" "-y" "-n" "root" "-l" "100%FREE" "vg0")
    (list-ref commands 6))

  (test-equal "the root volume is formatted by label"
    '("mkfs.ext4" "-L" "gradus-root" "/dev/mapper/vg0-root")
    (list-ref commands 7)))

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
