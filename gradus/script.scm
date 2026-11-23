;;; gradus/script.scm — command-line entry point.
;;; Copyright © 2026 Zhen-Lin Huo <zhen-lin.huo@gmx.com>
;;;
;;; This file is part of Gradus.

(define-module (gradus script)
  #:use-module (gradus answers)
  #:use-module (gradus config)
  #:use-module ((gradus install) #:prefix install:)
  #:use-module (gradus render)
  #:use-module (gradus utils)
  #:use-module (guix build utils)
  #:use-module (ice-9 format)
  #:use-module (ice-9 string-fun)
  #:use-module (srfi srfi-1)
  #:use-module (ice-9 match)
  #:export (main
            parse-arguments
            absolute-path
            apply-proxy-environment
            install-answers
            install-config))

(define %version "0.3.0")
(define %contract-version 1)

;; The installation backend moved to (gradus install); the CLI keeps its
;; historical names for the tests and for callers.
(define apply-proxy-environment install:apply-proxy-environment)
(define install-answers install:install-answers)
(define install-config install:install-config)

(define (absolute-path path)
  "Return PATH as an absolute path, resolved against the working directory.
`load' resolves relative names against the load path, so a relative --config
argument must be made absolute before it is loaded."
  (if (string-prefix? "/" path)
      path
      (string-append (getcwd) "/" path)))

(define (usage)
  "Print the command synopsis."
  (display "\
Usage: gradus --tui
       gradus --config FILE [--root DIR] [--dry-run]
       gradus --answers FILE [--root DIR] [--dry-run]
       gradus --version
       gradus --help

Options:
  --tui           interactive installer (console)
  --config FILE   install this operating-system declaration
  --answers FILE  install from an answer file (the target disk is prepared)
  --root DIR      mount point for the target (default: /mnt)
  --dry-run       check and print the plan; write nothing
  --log FILE      also write the transcript to FILE
  --version       print the product and contract versions
  --help          print this text
"))

(define (usage-error fmt . args)
  "Raise a usage error."
  (throw 'gradus-usage (apply format #f fmt args)))

(define (parse-arguments args)
  "Parse command-line ARGS (without the program name) into an alist.  Unknown
options and missing values are usage errors."
  (let loop ((args args) (result '()))
    (match args
      (() (reverse result))
      (("--answers" value . rest)
       (loop rest (acons 'answers value result)))
      (("--config" value . rest)
       (loop rest (acons 'config value result)))
      (("--root" value . rest)
       (loop rest (acons 'root value result)))
      (("--log" value . rest)
       (loop rest (acons 'log value result)))
      (("--tui" . rest)
       (loop rest (acons 'tui? #t result)))
      (("--dry-run" . rest)
       (loop rest (acons 'dry-run? #t result)))
      (("--version" . rest)
       (loop rest (acons 'version? #t result)))
      (("--help" . rest)
       (loop rest (acons 'help? #t result)))
      ((option . _)
       (usage-error "unknown or incomplete option: ~a" option)))))

(define (run opts)
  "Dispatch on parsed options OPTS and return an exit status."
  (cond
   ((assoc-ref opts 'tui?)
    ;; Loaded on demand: the console front-end needs guile-ncurses, and the
    ;; other modes should not pay for it.
    ((module-ref (resolve-module '(gradus tui)) 'run-tui)))
   ((assoc-ref opts 'version?)
    (format #t "gradus ~a (contract ~a)~%" %version %contract-version)
    0)
   ((assoc-ref opts 'help?)
    (usage)
    0)
   ((assoc-ref opts 'log)
    (log-open (assoc-ref opts 'log))
    (run (alist-delete 'log opts)))
   ((assoc-ref opts 'answers)
    (let ((answers-file (absolute-path (assoc-ref opts 'answers)))
          (root (or (assoc-ref opts 'root) "/mnt")))
      (unless (file-exists? answers-file)
        (log-line "no such answer file: ~a" answers-file)
        (exit +exit-validation+))
      (if (assoc-ref opts 'dry-run?)
          (begin
            (display (plan->string
                      (configuration-plan
                       (render-answers
                        (validate-answers (read-answers answers-file))))))
            0)
          (begin
            (unless (zero? (getuid))
              (log-line "must run as root to install")
              (exit +exit-target+))
            (catch 'misc-error
              (lambda () (install-answers answers-file root) 0)
              (lambda (key . args)
                (log-line "answers installation failed: ~a" args)
                (exit +exit-validation+))))))
    )
   ((assoc-ref opts 'config)
    (let ((config (absolute-path (assoc-ref opts 'config)))
          (root (or (assoc-ref opts 'root) "/mnt")))
      (unless (file-exists? config)
        (log-line "no such configuration: ~a" config)
        (exit +exit-validation+))
      (catch 'misc-error
        (lambda ()
          (let ((plan (configuration-plan (load-configuration config))))
            (if (assoc-ref opts 'dry-run?)
                (begin
                  (display (plan->string plan))
                  0)
                (begin
                  (unless (zero? (getuid))
                    (log-line "must run as root to install")
                    (exit +exit-target+))
                  (install-config config root)
                  0))))
        (lambda (key . args)
          (log-line "invalid configuration: ~a" args)
          (exit +exit-validation+)))))
   (else
    (usage)
    +exit-usage+)))

(define (main args)
  "Entry point.  ARGS includes the program name."
  (catch 'gradus-usage
    (lambda ()
      (let ((opts (parse-arguments (cdr args))))
        (exit (run opts))))
    (lambda (key . args)
      (format (current-error-port) "~a~%" (car args))
      (usage)
      +exit-usage+)))

;;; Run when this file is executed rather than imported: the tests import the
;;; module, so the entry point is guarded by the program name.
(if (and (pair? (command-line))
         (string-suffix? "gradus/script.scm" (car (command-line))))
    (exit (main (command-line))))
