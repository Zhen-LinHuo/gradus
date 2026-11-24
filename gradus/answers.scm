;;; gradus/answers.scm — reading and validating the answer file.
;;; Copyright © 2026 Zhen-Lin Huo <zhen-lin.huo@gmx.com>
;;;
;;; This file is part of Gradus.

(define-module (gradus answers)
  #:use-module (ice-9 format)
  #:use-module (ice-9 match)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-35)
  #:export (read-answers
            validate-answers
            answers-error
            answers-error?))

(define %known-keys
  '(schema-version profile locale timezone keyboard ntp host-name root-password
    proxy source storage assemble boot network users software))

(define %required-keys '(schema-version profile storage users))

(define-condition-type &answers-error &error
  answers-error?)

(define (answers-error message)
  (raise (condition (&answers-error) (&message (message message)))))

(define (read-answers file)
  "Read FILE as a single S-expression and return it.  A missing file or a file
whose first form is not a pair is an answers error."
  (unless (file-exists? file)
    (answers-error (format #f "no such answer file: ~a" file)))
  (let ((value (call-with-input-file file read)))
    (unless (pair? value)
      (answers-error (format #f "~a does not contain an answer form" file)))
    value))

(define (answer-ref alist key)
  (assoc-ref alist key))

(define (non-empty-string? value)
  (and (string? value) (not (string=? value ""))))

(define (check-known-keys answers)
  (for-each
   (lambda (entry)
     (unless (member (car entry) %known-keys)
       (answers-error (format #f "unknown answer key: ~a" (car entry)))))
   answers))

(define (check-required-keys answers)
  (for-each
   (lambda (k)
     (unless (answer-ref answers k)
       (answers-error (format #f "missing required answer key: ~a" k))))
   %required-keys))

(define (check-values answers)
  (let ((version (answer-ref answers 'schema-version)))
    (unless (and (integer? version) (>= version 1))
      (answers-error "schema-version must be an integer of at least 1")))
  (unless (member (answer-ref answers 'profile) '("desktop" "headless" "custom"))
    (answers-error (format #f "unknown profile: ~a" (answer-ref answers 'profile))))
  (for-each
   (lambda (name)
     (let ((value (answer-ref answers name)))
       (when value
         (unless (non-empty-string? value)
           (answers-error (format #f "~a must be a non-empty string" name))))))
   '(locale timezone keyboard host-name))
  (let ((users (answer-ref answers 'users)))
    (unless (and (list? users) (not (null? users)))
      (answers-error "users must be a non-empty list")))
  (let ((storage (answer-ref answers 'storage)))
    (unless (and (pair? storage) (answer-ref storage 'disk))
      (answers-error "storage must name a disk"))))

(define (check-storage answers)
  "Refuse storage combinations the installer cannot honour.  The check runs
before anything is written to a disk: finding out after partitioning that the
result would be a plaintext disk or an unbootable declaration is too late."
  (let* ((storage (answer-ref answers 'storage))
         (mode (answer-ref storage 'mode))
         (encryption (answer-ref storage 'encryption))
         (swap (or (answer-ref storage 'swap-size) 0)))
    (unless (memq mode '(simple lvm))
      (answers-error
       (format #f "storage mode ~a is not implemented; use `simple' or `lvm'"
               mode)))
    (when (and encryption (eq? mode 'lvm))
      (answers-error
       "encryption is not implemented for LVM storage yet; choose `simple' storage or drop the encryption section"))
    (when (and encryption (> swap 0))
      (answers-error
       "an encrypted install cannot use a separate swap partition yet (swap would be plaintext); set swap-size to 0"))
    (when encryption
      (unless (non-empty-string? (answer-ref encryption 'passphrase))
        (answers-error "encrypted storage needs a non-empty passphrase")))))

(define (check-duplicates answers)
  "A repeated top-level key makes the file ambiguous; reject it."
  (let loop ((seen '()) (entries answers))
    (match entries
      (() #t)
      ((((? symbol? k) . _) . rest)
       (when (member k seen)
         (answers-error (format #f "duplicate answer key: ~a" k)))
       (loop (cons k seen) rest))
      (_ (answers-error "the answer form is not an association list")))))

(define (validate-answers answers)
  "Validate an answer form.  Return the form unchanged, or raise an
answers error listing the first problem found."
  (check-duplicates answers)
  (check-known-keys answers)
  (check-required-keys answers)
  (check-values answers)
  (check-storage answers)
  answers)
