;;; gradus/fs.scm — the filesystem capability table.
;;; Copyright © 2026 Zhen-Lin Huo <zhen-lin.huo@gmx.com>
;;;
;;; This file is part of Gradus.

(define-module (gradus fs)
  #:use-module (guix records)
  #:use-module (ice-9 match)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-11)
  #:use-module (srfi srfi-13)
  #:use-module (gradus utils)
  #:export (<fs-capability>?
            fs-capability-name
            fs-capability-tool-package
            fs-capability-mkfs
            fs-capability-identify
            fs-capability-mount-source
            fs-capability-settle
            fs-capability-declaration
            fs-capability-boot-notes
            fs-capabilities
            fs-lookup
            fs-names
            fs-default
            fs-mkfs-command
            fs-root-identify
            fs-blkid-map
            parse-blkid
            parse-btrfs-show))

;; One row per supported file system.  Every question the install asks about a
;; file system — which tools, how to create it, how to read it back, how it is
;; settled after the last write, what the declaration and the bootloader need
;; — is answered here, and the storage, install and front-end code reads the
;; row instead of branching on a name.  See docs/architecture.md §4.
(define-record-type* <fs-capability>
  fs-capability make-fs-capability
  fs-capability?
  this-fs-capability
  (name           fs-capability-name)         ;string: menu entry and Guix type
  (tool-package   fs-capability-tool-package) ;package providing the mkfs tool
  (mkfs           fs-capability-mkfs)         ;(tool . extra-args); label flag is uniform
  (identify       fs-capability-identify)     ;'blkid or 'btrfs-show
  (mount-source   fs-capability-mount-source) ;'label-then-uuid
  (settle         fs-capability-settle)       ;command list after the last write, or #f
  (declaration    fs-capability-declaration)  ;the type a Guix file-system carries
  (boot-notes     fs-capability-boot-notes))  ;what the bootloader needs, or #f

;; The label flag and its argument are the same for every row: mkfs tools all
;; take -L LABEL immediately before the device.
(define %ext4
  (fs-capability
   (name "ext4")
   (tool-package "e2fsprogs")
   (mkfs '("mkfs.ext4" "-q" "-F"))
   (identify 'blkid)
   (mount-source 'label-then-uuid)
   (settle '("e2fsck" "-fy"))
   (declaration "ext4")
   (boot-notes #f)))

(define %btrfs
  (fs-capability
   (name "btrfs")
   (tool-package "btrfs-progs")
   (mkfs '("mkfs.btrfs" "-f"))
   (identify 'btrfs-show)
   (mount-source 'label-then-uuid)
   (settle #f)
   (declaration "btrfs")
   (boot-notes #f)))

(define %xfs
  (fs-capability
   (name "xfs")
   (tool-package "xfsprogs")
   (mkfs '("mkfs.xfs" "-f"))
   (identify 'blkid)
   (mount-source 'label-then-uuid)
   (settle #f)
   (declaration "xfs")
   (boot-notes #f)))

;; The capability table, in menu order.
(define fs-capabilities
  (list %ext4 %btrfs %xfs))

(define (fs-lookup name)
  "The row for NAME, or #f when no row carries that name."
  (find (lambda (row) (string=? (fs-capability-name row) name))
        fs-capabilities))

(define (fs-names)
  "The file system names, in menu order."
  (map fs-capability-name fs-capabilities))

(define (fs-default)
  "The file system an unconfigured answer form asks for."
  (fs-capability-name %ext4))

(define (fs-mkfs-command row label device)
  "The full mkfs command for ROW: its tool and arguments, then the uniform
label flag and DEVICE."
  (append (fs-capability-mkfs row) (list "-L" label device)))

;;; Identification.  Each row names the command that can read its own
;;; superblock; the parsers below turn that command's output into the
;;; label-keyed device map the rest of the install consumes.

(define (parse-blkid text)
  "Parse the output of `blkid -o export' into an association list keyed by
file-system label.  Each value is an alist with the device name, the type and
the UUID.  Devices are separated by blank lines, so the order of the fields
inside a block does not matter.  Devices without a label are skipped: they
cannot be addressed by the prepare step."
  (let loop ((lines (string-split text #\newline))
             (current '())
             (result '()))
    (match lines
      (()
       ;; Flush the last block, if any.
       (if (null? current)
           (reverse result)
           (let ((label (assq-ref current 'label)))
             (reverse (if label (acons label current result) result)))))
      ((line . rest)
       (cond ((string-null? line)
              ;; End of one device block.
              (let ((label (assq-ref current 'label)))
                (loop rest '()
                      (if label (acons label current result) result))))
             (else
              (match (string-split line #\=)
                (("DEVNAME" value)
                 (loop rest (acons 'device value current) result))
                (("TYPE" value)
                 (loop rest (acons 'type value current) result))
                (("UUID" value)
                 (loop rest (acons 'uuid value current) result))
                (("LABEL" value)
                 (loop rest (acons 'label value current) result))
                (_ (loop rest current result)))))))))

(define (fs-blkid-map devices)
  "The label-keyed device map for DEVICES, read with blkid."
  (let-values (((status output) (apply run-command
                                       (system-tool "blkid")
                                       "-o" "export" devices)))
    (unless (zero? status)
      (error "blkid failed" devices))
    (parse-blkid output)))

(define (parse-btrfs-show text device label)
  "Parse `btrfs filesystem show DEVICE' into a one-entry device map under
LABEL.  libblkid in the live image predates the block-group-tree superblock
that current btrfs-progs writes, so blkid sees nothing; btrfs's own tools
know the format."
  (let* ((lines (string-split text #\newline))
         (uuid (any (lambda (line)
                      (and (string-contains line "uuid:")
                           (string-trim-both
                            (last (string-split line #\space)))))
                    lines)))
    (list (cons label
                (list (cons 'device device)
                      (cons 'type "btrfs")
                      (cons 'uuid uuid))))))

(define (fs-btrfs-map device label)
  "The device map for a freshly made btrfs DEVICE labelled LABEL."
  (let-values (((status output) (run-command (system-tool "btrfs")
                                             "filesystem" "show" device)))
    (unless (zero? status)
      (error "btrfs filesystem show failed" device))
    (parse-btrfs-show output device label)))

(define (fs-root-identify row device label)
  "The label-keyed device map for the fresh file system ROW made on DEVICE
with LABEL.  blkid reads the label back from the superblock; the btrfs row
keys its entry by LABEL because that is the only name it is given."
  (case (fs-capability-identify row)
    ((blkid) (fs-blkid-map (list device)))
    ((btrfs-show) (fs-btrfs-map device label))
    (else (error "unknown identify style"
                 (fs-capability-identify row)))))
