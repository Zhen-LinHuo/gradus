;;; gradus/answers.scm — reading and validating the answer file.
;;; Copyright © 2026 Zhen-Lin Huo <zhen-lin.huo@gmx.com>
;;;
;;; This file is part of Gradus.

(define-module (gradus answers)
  #:use-module (ice-9 exceptions)
  #:use-module (ice-9 format)
  #:use-module (ice-9 match)
  #:use-module (gradus fs)
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
  ;; `raise' refuses a compound condition in Guile 3: it has to go through
  ;; `raise-exception', or the caller only sees "wrong type" instead of the
  ;; message we took care to write.
  (raise-exception (condition (&answers-error) (&message (message message)))))

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

(define %terminals
  '(console serial serial_0 serial_1 serial_2 serial_3
    gfxterm vga_text mda_text morse spkmodem
    at_keyboard usb_keyboard))

(define (check-boot answers)
  "Refuse terminal and serial settings GRUB could not honour.  A typo here
would leave a headless machine with no console at boot, which is not something
the operator can repair without physical access."
  (let ((boot (answer-ref answers 'boot)))
    (when boot
      (for-each
       (lambda (key)
         (let ((terminals (answer-ref boot key)))
           (when terminals
             (unless (list? terminals)
               (answers-error (format #f "~a must be a list" key)))
             (for-each (lambda (terminal)
                         (unless (memq terminal %terminals)
                           (answers-error
                            (format #f "unknown terminal in ~a: ~a" key terminal))))
                       terminals))))
       '(terminal-outputs terminal-inputs))
      (for-each
       (lambda (key)
         (let ((value (answer-ref boot key)))
           (when value
             (unless (and (integer? value) (>= value 0))
               (answers-error (format #f "~a must be a non-negative integer" key))))))
       '(serial-unit serial-speed timeout)))))

(define %source-keys '(channels substitute-services))
(define %substitute-kinds '(official mirror builder))

(define (check-source answers)
  "Reject unknown keys and malformed entries under `source'.  A misspelled
substitute key used to sail through validation and quietly leave the daemon
on its default sources — the silent degradation the contract forbids."
  (let ((source (answer-ref answers 'source)))
    (when source
      (unless (and (list? source) (or (null? source) (pair? (car source))))
        (answers-error "source must be an association list"))
      (for-each
       (lambda (entry)
         (unless (member (car entry) %source-keys)
           (answers-error
            (format #f "unknown source key: ~a (expected one of: ~a)"
                    (car entry)
                    (string-join (map symbol->string %source-keys) ", ")))))
       source)
      (let ((services (answer-ref source 'substitute-services)))
        (when services
          (unless (and (list? services) (or (null? services) (pair? (car services))))
            (answers-error "substitute-services must be a list of entries"))
          (for-each
           (lambda (service)
             (unless (and (list? service) (pair? service))
               (answers-error "each substitute service must be an association list"))
             (let ((url (assq-ref service 'url))
                   (kind (assq-ref service 'kind)))
               (unless (non-empty-string? url)
                 (answers-error "a substitute service needs a non-empty url"))
               (when kind
                 (unless (memq kind %substitute-kinds)
                   (answers-error
                    (format #f "unknown substitute kind: ~a (expected one of: ~a)"
                            kind
                            (string-join (map symbol->string %substitute-kinds)
                                         ", ")))))))
           services))))))

(define (check-proxy answers)
  "The proxy is an association list; a bare URL string would make both readers
call `assq-ref' on a string and die during the install."
  (let ((proxy (answer-ref answers 'proxy)))
    (when proxy
      (unless (and (list? proxy) (or (null? proxy) (pair? (car proxy))))
        (answers-error
         "proxy must be an association list with http, https and no-proxy"))
      (for-each
       (lambda (entry)
         (unless (member (car entry) '(http https no-proxy))
           (answers-error (format #f "unknown proxy key: ~a" (car entry)))))
       proxy)
      (for-each
       (lambda (key)
         (let ((value (assq-ref proxy key)))
           (when value
             (if (eq? key 'no-proxy)
                 (unless (and (list? value) (every non-empty-string? value))
                   (answers-error "no-proxy must be a list of host names"))
                 (unless (non-empty-string? value)
                   (answers-error (format #f "proxy ~a must be a string" key)))))))
       '(http https no-proxy)))))

(define (check-storage answers)
  "Refuse storage combinations the installer cannot honour.  The check runs
before anything is written to a disk: finding out after partitioning that the
result would be a plaintext disk or an unbootable declaration is too late."
  (let* ((storage (answer-ref answers 'storage))
         (mode (answer-ref storage 'mode))
         (filesystem (answer-ref storage 'filesystem))
         (encryption (answer-ref storage 'encryption))
         (swap (or (answer-ref storage 'swap-size) 0)))
    (when filesystem
      (unless (and (string? filesystem) (fs-lookup filesystem))
        (answers-error
         (format #f "unknown filesystem: ~a (expected one of: ~a)"
                 filesystem (string-join (fs-names) ", ")))))
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
  (check-boot answers)
  (check-source answers)
  (check-proxy answers)
  answers)
