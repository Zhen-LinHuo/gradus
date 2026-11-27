;;; tests/fs.scm — the filesystem capability table.
;;; Copyright © 2026 Zhen-Lin Huo <zhen-lin.huo@gmx.com>
;;;
;;; This file is part of Gradus.

(use-modules (srfi srfi-64)
             (gradus fs))

(define runner (test-runner-simple))
(test-runner-current runner)

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

  (test-equal "the btrfs parser keys the entry by the given label"
    '("gradus-root" "btrfs" "/dev/vda3")
    (let ((entry (car (parse-btrfs-show
                       (string-append "Label: gradus-root  uuid: "
                                      "0b5d5f7a-9d5e-4b7a-9a58-4f0c1c6b0d11\n"
                                      "    Total devices: 1 FS bytes used: 128.00KiB\n")
                       "/dev/vda3" "gradus-root"))))
      (list (car entry)
            (assq-ref (cdr entry) 'type)
            (assq-ref (cdr entry) 'device))))

  (test-equal "the table carries one row per supported file system"
    '("ext4" "btrfs" "xfs") (fs-names))

  (test-equal "the default is the first row"
    "ext4" (fs-default))

  (test-assert "an unknown name has no row"
    (not (fs-lookup "zfs")))

  (test-equal "each row builds its own mkfs command"
    '(("mkfs.ext4" "-q" "-F" "-L" "gradus-root" "/dev/vda3")
      ("mkfs.btrfs" "-f" "-L" "gradus-root" "/dev/vda3")
      ("mkfs.xfs" "-f" "-L" "gradus-root" "/dev/vda3"))
    (map (lambda (name)
           (fs-mkfs-command (fs-lookup name) "gradus-root" "/dev/vda3"))
         (fs-names)))

  (test-equal "only ext settles with a check"
    '(("e2fsck" "-fy") #f #f)
    (map (lambda (name) (fs-capability-settle (fs-lookup name)))
         (fs-names)))

  (test-equal "each row names the command that can read its own superblock"
    '(blkid btrfs-show blkid)
    (map (lambda (name) (fs-capability-identify (fs-lookup name)))
         (fs-names)))

  (test-equal "the declaration carries the row's name"
    '("ext4" "btrfs" "xfs")
    (map (lambda (name) (fs-capability-declaration (fs-lookup name)))
         (fs-names)))

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
