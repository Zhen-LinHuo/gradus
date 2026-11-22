;;; gradus/config.scm — loading and planning from an operating-system declaration.
;;; Copyright © 2026 Zhen-Lin Huo <zhen-lin.huo@gmx.com>
;;;
;;; This file is part of Gradus.

(define-module (gradus config)
  #:declarative? #f
  #:use-module (gnu system)
  #:use-module (gnu system file-systems)
  #:use-module (gnu system uuid)
  #:use-module (ice-9 format)
  #:use-module (ice-9 match)
  #:use-module (srfi srfi-1)
  #:export (load-configuration
            file-system-source
            order-file-systems
            configuration-plan
            plan->string))

(define (load-configuration file)
  "Load FILE in a fresh module and return the operating-system declaration it
ends with.  Raise an error if it does not produce one."
  (let ((module (make-fresh-user-module)))
    (save-module-excursion
     (lambda ()
       (set-current-module module)
       (let ((value (load file)))
         (unless (operating-system? value)
           (error "configuration does not evaluate to an operating-system"
                  file))
         value)))))

(define (file-system-source fs)
  "Return the device specification of FS as a string accepted by mount(8):
a device path unchanged, or LABEL=/UUID= for a label or UUID object."
  (let ((device (file-system-device fs)))
    (cond ((file-system-label? device)
           (string-append "LABEL=" (file-system-label->string device)))
          ((uuid? device)
           (string-append "UUID=" (uuid->string device)))
          (else
           (file-system-device->string device)))))

(define (mount-depth fs)
  "Return the nesting depth of FS's mount point, so that parents are mounted
before children."
  (let ((point (file-system-mount-point fs)))
    (if (string=? point "/")
        0
        (let loop ((chars (string->list point)) (depth 0))
          (if (null? chars)
              depth
              (loop (cdr chars)
                    (if (char=? (car chars) #\/) (+ depth 1) depth)))))))

(define (order-file-systems file-systems)
  "Return FILE-SYSTEMS sorted so that parents are mounted before children."
  (sort file-systems
        (lambda (a b) (< (mount-depth a) (mount-depth b)))))

(define (configuration-plan os)
  "Return a plan for OS: an alist describing the host and an ordered list of
file systems.  The order is the order in which they must be mounted."
  (let* ((file-systems (operating-system-file-systems os))
         (sorted (order-file-systems file-systems)))
    `((host-name . ,(operating-system-host-name os))
      (file-systems
       . ,(map (lambda (fs)
                 `((mount-point . ,(file-system-mount-point fs))
                   (source . ,(file-system-source fs))
                   (type . ,(file-system-type fs))
                   (options . ,(file-system-options fs))
                   (needed-for-boot? . ,(file-system-needed-for-boot? fs))))
               sorted)))))

(define (plan->string plan)
  "Render PLAN as human-readable text for the review and dry-run output."
  (format #f "host: ~a~%~:{  ~a -> ~a (~a)~%~}"
          (assoc-ref plan 'host-name)
          (map (lambda (fs)
                 (list (assoc-ref fs 'source)
                       (assoc-ref fs 'mount-point)
                       (assoc-ref fs 'type)))
               (assoc-ref plan 'file-systems))))
