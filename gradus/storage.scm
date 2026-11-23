;;; gradus/storage.scm — device discovery for the storage step.
;;; Copyright © 2026 Zhen-Lin Huo <zhen-lin.huo@gmx.com>
;;;
;;; This file is part of Gradus.

(define-module (gradus storage)
  #:use-module (gradus utils)
  #:use-module (ice-9 match)
  #:use-module (ice-9 string-fun)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-11)
  #:export (parse-blkid
            read-device-map
            partition-name
            prepare-target))

(define (parse-blkid text)
  "Parse the output of `blkid -o export' into an association list keyed by
file-system label.  Each value is an alist with the device name, the type and
the UUID.  Devices without a label are skipped: they cannot be addressed by the
prepare step."
  (let loop ((lines (string-split text #\newline))
             (current '())
             (result '()))
    (match lines
      (() (reverse (if (null? current) result (cons current result))))
      ((line . rest)
       (match (string-split line #\=)
         (("DEVNAME" value)
          (loop rest `((device . ,value)) result))
         (("TYPE" value)
          (loop rest (acons 'type value current) result))
         (("UUID" value)
          (loop rest (acons 'uuid value current) result))
         (("LABEL" value)
          (loop rest (acons 'label value current)
                (acons value current result)))
         (_ (loop rest current result)))))))

(define (read-device-map devices)
  "Return the label-keyed device map for the given device names, by running
blkid on them.  DEVICES is a list of paths such as \"/dev/loop0p2\"."
  (let-values (((status output) (apply run-command
                                       "blkid" "-o" "export" devices)))
    (unless (zero? status)
      (error "blkid failed" devices))
    (parse-blkid output)))

(define (partition-name disk number)
  "Return the device name of partition NUMBER on DISK.  Disks whose name ends
in a digit (loop0, nvme0n1) use a p separator; classical names do not."
  (if (char-numeric? (string-ref disk (- (string-length disk) 1)))
      (string-append disk "p" (number->string number))
      (string-append disk (number->string number))))

(define (prepare-target answers)
  "Partition and format the target described by a `simple' storage answer,
then return the label-keyed device map of what was created.  Data volumes are
never touched: this function only creates the system's ESP and root."
  (let* ((storage (assq-ref answers 'storage))
         (disk (assq-ref storage 'disk))
         (esp (partition-name disk 1))
         (root (partition-name disk 2)))
    (unless (eq? (assq-ref storage 'mode) 'simple)
      (error "prepare-target only implements the simple storage mode"))
    (unless (zero? (run-command/stream
                    "parted" "-s" disk "mklabel" "gpt"
                    "mkpart" "ESP" "fat32" "1MiB" "513MiB"
                    "set" "1" "esp" "on"
                    "mkpart" "root" "ext4" "513MiB" "100%"))
      (error "partitioning failed" disk))
    (run-command/stream "partprobe" disk)
    (run-command/stream "udevadm" "settle")
    (unless (zero? (run-command/stream "mkfs.vfat" "-n" "GRADUS-ESP" esp))
      (error "mkfs.vfat failed" esp))
    (unless (zero? (run-command/stream "mkfs.ext4" "-q" "-F"
                                       "-L" "gradus-root" root))
      (error "mkfs.ext4 failed" root))
    (read-device-map (list esp root))))
