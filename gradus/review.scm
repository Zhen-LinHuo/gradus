;;; gradus/review.scm — the review workflow: inspect, edit, confirm.
;;; Copyright © 2026 Zhen-Lin Huo <zhen-lin.huo@gmx.com>
;;;
;;; This file is part of Gradus.
;;;
;;; The review phase sits between collecting the answers and committing them.
;;; It has two states: before the target is prepared the review is a summary
;;; of the answers; after it, the declaration file is the truth — the summary
;;; is read back from the file, a hand edit is visible immediately, and a
;;; change to the settings re-renders the file.  This module owns that state
;;; machine; a front end only renders it and sends events back.

(define-module (gradus review)
  #:use-module (ice-9 textual-ports)
  #:use-module (gradus install)
  #:use-module (gradus render)
  #:use-module (gradus serialize)
  #:use-module (guix records)
  #:use-module (srfi srfi-1)
  #:export (<review>?
            review-answers
            review-prepare
            review-attach
            review-initial
            review-prepared?
            review-declaration
            review-sync
            review-summary
            review-hand-edited?
            review-declaration-text
            review-check
            review-install))

(define-record-type* <review>
  review make-review review?
  this-review
  (answers      review-answers)       ;the answers the declaration was rendered from, or #f
  (declaration  review-declaration)   ;the declaration path, or #f
  (device-map   review-device-map)    ;the prepare step's read-back, for re-rendering
  (root         review-root)          ;where the system is installed
  (answers-file review-answers-file)  ;where the answers are recorded
  (last-content review-last-content)) ;what we last wrote to the declaration

(define (file-content path)
  (call-with-input-file path get-string-all))

(define (review-initial root answers-file)
  "A review with nothing prepared yet: the summary comes from the answers."
  (make-review #f #f #f root answers-file ""))

(define (review-prepared? state)
  "Whether the target is prepared and a declaration exists."
  (and state (pair? (review-answers state)) (review-declaration state)))

(define (review-prepare answers answers-file root)
  "Prepare the target beneath ROOT and render ANSWERS into a declaration.
Returns the prepared review; the prepare step's console output is the
caller's business (a terminal front end suspends itself first)."
  (call-with-values
      (lambda () (prepare-answers/alist answers answers-file root))
    (lambda (declaration device-map)
      (make-review answers declaration device-map root answers-file
                   (file-content declaration)))))

(define (review-attach answers declaration device-map root answers-file)
  "A prepared review around an existing DECLARATION: the state a resumed
session or a test starts from.  The file on disk is read as it is."
  (make-review answers declaration device-map root answers-file
               (file-content declaration)))

(define (review-sync state answers)
  "Bring STATE in line with ANSWERS after the operator comes back from a
page.  A storage change invalidates the prepared target — the partitioning
no longer matches, and the next install prepares again.  Any other change
re-renders the declaration with the device map the prepare step read back.
An unchanged state is returned as it is."
  (cond
   ((not (review-prepared? state))
    state)
   ((not (equal? (assq-ref answers 'storage)
                 (assq-ref (review-answers state) 'storage)))
    (review-initial (review-root state) (review-answers-file state)))
   ((not (equal? answers (review-answers state)))
    (serialize-to-file (review-declaration state) answers
                       (review-device-map state))
    (make-review answers (review-declaration state) (review-device-map state)
                 (review-root state) (review-answers-file state)
                 (file-content (review-declaration state))))
   (else state)))

(define (review-hand-edited? state)
  "Whether the declaration no longer matches what this review wrote: the
operator edited the file itself."
  (and (review-prepared? state)
       (not (equal? (file-content (review-declaration state))
                    (review-last-content state)))))

(define (declaration-rows answers declaration)
  "The summary rows as (key . value) pairs, read from the DECLARATION file
where it carries the fact and taken from ANSWERS where only the answers know
it.  Keys: host-name, disk, layout, bootloader, substitute-urls, packages,
accounts, system."
  (let* ((from-file (and declaration (declaration-summary declaration)))
         (file-ref (lambda (key)
                     (let ((cell (and from-file (assq key from-file))))
                       (and cell (cdr cell)))))
         (storage (assq-ref answers 'storage))
         (boot (assq-ref answers 'boot))
         (users (assq-ref answers 'users))
         (serial? (and boot (assq-ref boot 'terminal-outputs))))
    (append
     (let ((value (or (file-ref 'host-name) (assq-ref answers 'host-name))))
       (list (cons 'host-name (or value "gradus"))))
     (list (cons 'disk (format #f "~a (~a)"
                               (assq-ref storage 'disk)
                               (or (assq-ref storage 'filesystem) "ext4"))))
     (list (cons 'layout (format #f "~a, swap ~a MiB"
                                 (assq-ref storage 'mode)
                                 (or (assq-ref storage 'swap-size) 0))))
     (let ((value (or (file-ref 'bootloader)
                      (let ((b (and boot (assq-ref boot 'bootloader))))
                        (and b (symbol->string b))))))
       (list (cons 'bootloader
                   (string-append (or value "?")
                                  (if serial? " (serial)" "")))))
     (let ((urls (file-ref 'substitute-urls)))
       (list (cons 'substitute-urls
                   (or urls
                       (let ((services (assq-ref (assq-ref answers 'source)
                                                 'substitute-services)))
                         (filter-map (lambda (s) (assq-ref s 'url))
                                     (or services '())))))))
     (let ((names (or (file-ref 'packages) (answer-package-names answers))))
       (list (cons 'packages names)))
     (let ((names (or (file-ref 'users)
                      (map (lambda (u) (assq-ref u 'name)) (or users '())))))
       (list (cons 'accounts names)))
     (list (cons 'desktop
                 (let ((envs (or (file-ref 'environments)
                                 (let ((desktop (assq-ref answers 'desktop)))
                                   (and (list? desktop)
                                        (every pair? desktop)
                                        (let ((cell (assq 'environments
                                                          desktop)))
                                          (and cell (cdr cell)))))
                                 '())))
                   (if (null? envs)
                       "headless"
                       (string-join (map symbol->string envs) " ")))))
     (list (cons 'system
                 (format #f "~a, ~a, keyboard ~a, ntp ~a"
                         (or (file-ref 'timezone) (assq-ref answers 'timezone) "?")
                         (or (file-ref 'locale) (assq-ref answers 'locale) "?")
                         (or (file-ref 'keyboard)
                             (let ((k (assq-ref answers 'keyboard)))
                               (and k (assq-ref k 'layout)))
                             "?")
                         (if (assq-ref answers 'ntp) "on" "off")))))))

(define (review-summary state answers)
  "The summary rows for the current state as (key . value) pairs.  The
prepared state reads the declaration file; the initial state reads ANSWERS."
  (declaration-rows answers (and (review-prepared? state)
                                 (review-declaration state))))

(define (review-declaration-text state)
  "The declaration of STATE as text, or #f when nothing is prepared.  The
view and the editor both read this, so what is shown is what is on disk."
  (and (review-prepared? state)
       (file-content (review-declaration state))))

(define (review-check state)
  "Read the declaration as a whole: #f when it is a system declaration this
installer can install, otherwise a message naming what is wrong.  Run after
a hand edit, before the install is confirmed."
  (if (not (review-prepared? state))
      "no declaration has been prepared"
      (catch #t
        (lambda ()
          (declaration-summary (review-declaration state))
          #f)
        (lambda (key . args)
          (format #f "~a" args)))))

(define (review-install state)
  "Install the declaration of STATE beneath its root.  The file is what gets
installed, so a hand edit is part of the system, not the answers."
  (install-declaration! (review-answers state)
                        (review-answers-file state)
                        (review-root state)
                        (review-declaration state)))
