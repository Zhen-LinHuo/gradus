;;; gradus/storage.scm — device discovery for the storage step.
;;; Copyright © 2026 Zhen-Lin Huo <zhen-lin.huo@gmx.com>
;;;
;;; This file is part of Gradus.

(define-module (gradus storage)
  #:use-module (gradus utils)
  #:use-module (ice-9 match)
  #:use-module (srfi srfi-1)
  #:export (parse-blkid
            read-device-map))

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
