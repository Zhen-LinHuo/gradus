;;; gradus/script.scm — command-line entry point.
;;; Copyright © 2026 Zhen-Lin Huo <zhen-lin.huo@gmx.com>
;;;
;;; This file is part of Gradus.

(define-module (gradus script)
  #:use-module (gradus config)
  #:use-module (gradus provenance)
  #:use-module (gradus utils)
  #:use-module (guix build utils)
  #:use-module (ice-9 format)
  #:use-module (ice-9 match)
  #:use-module (srfi srfi-1)
  #:export (main
            parse-arguments
            absolute-path))

(define %version "0.1.0")
(define %contract-version 1)

(define (absolute-path path)
  "Return PATH as an absolute path, resolved against the working directory.
`load' resolves relative names against the load path, so a relative --config
argument must be made absolute before it is loaded."
  (if (string-prefix? "/" path)
      path
      (string-append (getcwd) "/" path)))

(define (usage)
  "Print the command synopsis."
  (format #t "Usage: gradus --config FILE [--root DIR] [--dry-run]~%~
              ~10@*gradus --version~%~
              ~10@*gradus --help~%~
~%Options:~%~
  --config FILE   install this operating-system declaration~%~
  --root DIR      mount point for the target (default: /mnt)~%~
  --dry-run       check and print the plan; write nothing~%~
  --log FILE      also write the transcript to FILE~%~
  --version       print the product and contract versions~%~
  --help          print this text~%"))

(define (usage-error fmt . args)
  "Raise a usage error."
  (throw 'gradus-usage (apply format #f fmt args)))

(define (parse-arguments args)
  "Parse command-line ARGS (without the program name) into an alist.  Unknown
options and missing values are usage errors."
  (let loop ((args args) (result '()))
    (match args
      (() (reverse result))
      (("--config" value . rest)
       (loop rest (acons 'config value result)))
      (("--root" value . rest)
       (loop rest (acons 'root value result)))
      (("--log" value . rest)
       (loop rest (acons 'log value result)))
      (("--dry-run" . rest)
       (loop rest (acons 'dry-run? #t result)))
      (("--version" . rest)
       (loop rest (acons 'version? #t result)))
      (("--help" . rest)
       (loop rest (acons 'help? #t result)))
      ((option . _)
       (usage-error "unknown or incomplete option: ~a" option)))))

(define (mount-plan plan root)
  "Mount every file system in PLAN beneath ROOT, parents first.  Return #t on
success; raise on the first failure."
  (for-each
   (lambda (fs)
     (let* ((point (assoc-ref fs 'mount-point))
            (target (if (string=? point "/")
                        root
                        (string-append root point)))
            (source (assoc-ref fs 'source))
            (type (assoc-ref fs 'type))
            (options (assoc-ref fs 'options)))
       (mkdir-p target)
       (log-line "mounting ~a on ~a (~a)" source target type)
       (let ((args (append (list "mount" "-t" type)
                           (if (and (string? options)
                                    (not (string=? options "")))
                               (list "-o" options)
                               '())
                           (list source target))))
         (unless (zero? (apply run-command/stream args))
           (error "mount failed" source target)))))
   (assoc-ref plan 'file-systems))
  #t)

(define (install-config config-file root)
  "Validate CONFIG-FILE and install it beneath ROOT."
  (log-line "checking ~a" config-file)
  (unless (zero? (run-command/stream "guix" "system" "build"
                                     "--dry-run" "--no-grafts" config-file))
    (exit +exit-validation+))
  (let ((os (load-configuration config-file)))
    (log-line "mounting the target beneath ~a" root)
    (catch 'misc-error
      (lambda () (mount-plan (configuration-plan os) root))
      (lambda (key . args)
        (log-line "cannot prepare the target: ~a" args)
        (exit +exit-target+)))
    (log-line "installing")
    (unless (zero? (run-command/stream "guix" "system" "init" config-file root))
      (exit +exit-install+))
    (write-provenance root config-file "config")
    (log-line "installed; declaration kept at ~a/etc/config.scm" root)))

(define (run opts)
  "Dispatch on parsed options OPTS and return an exit status."
  (cond
   ((assoc-ref opts 'version?)
    (format #t "gradus ~a (contract ~a)~%" %version %contract-version)
    0)
   ((assoc-ref opts 'help?)
    (usage)
    0)
   ((assoc-ref opts 'log)
    (log-open (assoc-ref opts 'log))
    (run (alist-delete 'log opts)))
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
