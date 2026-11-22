;;; gradus/provenance.scm — artefacts left on the target.
;;; Copyright © 2026 Zhen-Lin Huo <zhen-lin.huo@gmx.com>
;;;
;;; This file is part of Gradus.

(define-module (gradus provenance)
  #:use-module (gradus utils)
  #:use-module (guix build utils)
  #:use-module (ice-9 format)
  #:use-module (ice-9 string-fun)
  #:use-module (srfi srfi-11)
  #:export (write-provenance))

(define %version "0.1.0")
(define %contract-version 1)

(define (write-sexp file sexp)
  "Write SEXP to FILE with a trailing newline."
  (call-with-output-file file
    (lambda (port)
      (write sexp port)
      (newline port))))

(define (write-provenance root config-file mode)
  "Record what was installed under ROOT: the declaration itself, the mode that
produced it, and the versions involved.  CONFIG-FILE is copied byte for byte."
  (let ((directory (string-append root "/etc/gradus")))
    (mkdir-p directory)
    (copy-file config-file (string-append root "/etc/config.scm"))
    (let-values (((status describe) (run-command "guix" "--version")))
      (write-sexp (string-append directory "/provenance.scm")
                  `((installer-version . ,%version)
                    (contract-version . ,%contract-version)
                    (guix . ,(if (zero? status)
                                 (car (string-split describe #\newline))
                                 "unknown"))
                    (mode . ,mode))))
    (write-sexp (string-append directory "/answers.scm")
                `((mode . ,mode)
                  (config . ,config-file)))))
