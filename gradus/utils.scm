;;; gradus/utils.scm — process and logging helpers.
;;; Copyright © 2026 Zhen-Lin Huo <zhen-lin.huo@gmx.com>
;;;
;;; This file is part of Gradus.

(define-module (gradus utils)
  #:use-module (ice-9 format)
  #:use-module (ice-9 popen)
  #:use-module (ice-9 rdelim)
  #:export (+exit-usage+
            +exit-validation+
            +exit-target+
            +exit-install+
            +exit-interrupted+
            log-line
            log-open
            run-command
            run-command/stream))

;;; Exit statuses, as documented in docs/contract.md §7.

(define +exit-usage+ 1)
(define +exit-validation+ 2)
(define +exit-target+ 3)
(define +exit-install+ 4)
(define +exit-interrupted+ 5)

(define %log-port #f)

(define (log-open file)
  "Append the transcript to FILE as well as standard error."
  (set! %log-port (open-output-file file)))

(define* (log-line fmt #:rest args)
  "Write one line to the transcript and to standard error.  FMT and ARGS are
passed to `format'."
  (let ((line (apply format #f fmt args)))
    (format (current-error-port) "~a~%" line)
    (when %log-port
      (format %log-port "~a~%" line)
      (force-output %log-port))))

(define (run-command program . args)
  "Run PROGRAM with ARGS, capturing standard output.  Return two values: the
exit status and the output as a string."
  (let* ((port (apply open-pipe* OPEN_READ program args))
         (output (let loop ((lines '()))
                   (let ((line (read-line port)))
                     (if (eof-object? line)
                         (apply string-append
                                (map (lambda (l) (string-append l "\n"))
                                     (reverse lines)))
                         (loop (cons line lines))))))
         (status (close-pipe port)))
    (values (status:exit-val status) output)))

(define (run-command/stream program . args)
  "Run PROGRAM with ARGS, inheriting standard output and error.  Return the
exit status."
  (status:exit-val (apply system* program args)))
