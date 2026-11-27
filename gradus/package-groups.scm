;;; gradus/package-groups.scm — reading the package-group manifests.
;;; Copyright © 2026 Zhen-Lin Huo <zhen-lin.huo@gmx.com>
;;;
;;; This file is part of Gradus.

(define-module (gradus package-groups)
  #:use-module (ice-9 match)
  #:use-module (ice-9 rdelim)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:export (package-group-ids
            package-group-description
            package-group-packages))

;; The package groups are plain Guix manifest files under
;; manifests/package-groups; this
;; module only reads them.  The identifier is the file name, the description
;; is the file's first comment line, and the content is the manifest's
;; specification list — the same data 'guix package -m' consumes, so nothing
;; here defines a format of its own.

(define (groups-directory)
  "The manifest directory, located relative to this module rather than the
working directory: the medium runs from an extracted tree, the walkthrough
from a checkout, and --answers from wherever the operator stands."
  (let ((here (module-filename (resolve-module '(gradus package-groups)))))
    (unless here
      (error "cannot locate the group manifests: this module has no source file"))
    (string-append (dirname (dirname here)) "/manifests/package-groups")))

(define (package-group-file id)
  (string-append (groups-directory) "/" (symbol->string id) ".scm"))

(define (directory-entries directory)
  (let ((port (opendir directory)))
    (let loop ((acc '()))
      (let ((entry (readdir port)))
        (if (eof-object? entry)
            (begin (closedir port) (reverse acc))
            (loop (cons entry acc)))))))

(define (package-group-ids)
  "The group identifiers, as symbols, in file-name order."
  (let* ((entries (directory-entries (groups-directory)))
         (files (filter (lambda (entry) (string-suffix? ".scm" entry))
                        entries))
         (names (map (lambda (file) (string-drop-right file 4))
                     (sort files string<?))))
    (map string->symbol names)))

(define (read-package-group id)
  "The manifest form of group ID: (specifications->manifest (list ...))."
  (let ((form (call-with-input-file (package-group-file id) read)))
    (match form
      (('specifications->manifest ('list . names))
       (unless (every string? names)
         (error "group manifest holds a non-string specification" id))
       names)
      (_ (error "not a group manifest" id)))))

(define (package-group-description id)
  "The first comment line of the group's manifest file: the summary the
pattern carried over from openSUSE."
  (let ((line (call-with-input-file (package-group-file id) read-line)))
    (if (and (string? line) (string-prefix? ";;;" line))
        (string-trim-both (substring line 3))
        (symbol->string id))))

(define (package-group-packages id)
  "The package specifications of group ID, in manifest order."
  (read-package-group id))
