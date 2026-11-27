;;; tests/review.scm — the review workflow state machine.
;;; Copyright © 2026 Zhen-Lin Huo <zhen-lin.huo@gmx.com>
;;;
;;; This file is part of Gradus.

(use-modules (ice-9 format)
             (ice-9 textual-ports)
             (srfi srfi-1)
             (srfi srfi-64)
             (gradus review)
             (gradus serialize))

(define runner (test-runner-simple))
(test-runner-current runner)

  (define %answers
    '((schema-version . 1)
      (profile . "headless")
      (host-name . "box0")
      (timezone . "UTC")
      (locale . "en_US.utf8")
      (keyboard (layout . "us"))
      (storage (mode . simple) (disk . "/dev/vda") (filesystem . "ext4"))
      (boot (bootloader . grub-bios) (timeout . 5))
      (users ((name . "alice") (group . "users")))))

  (define %declaration "/tmp/gradus-review-test.scm")

  (define (slurp path)
    (call-with-input-file path get-string-all))

  (define (summary-ref summary key)
    (let ((cell (assq key summary)))
      (and cell (cdr cell))))

  (define (fresh)
    (serialize-to-file %declaration %answers '())
    (review-attach %answers %declaration '() "/tmp/target"
                   "/tmp/gradus-review-answers.scm"))

  (define (with-answer key value)
    (cons (cons key value)
          (filter (lambda (pair) (not (eq? (car pair) key))) %answers)))

  (test-assert "an initial review is not prepared"
    (not (review-prepared? (review-initial "/tmp/target"
                                           "/tmp/gradus-answers.scm"))))

  (test-equal "an unprepared summary comes from the answers"
    "box0"
    (summary-ref (review-summary (review-initial "/tmp/target"
                                                 "/tmp/gradus-answers.scm")
                                 %answers)
                 'host-name))

  (test-assert "an attached declaration prepares the review"
    (review-prepared? (fresh)))

  (test-assert "a well-formed declaration passes the check"
    (not (review-check (fresh))))

  (test-assert "an unchanged review syncs to itself"
    (let* ((state (fresh))
           (after (review-sync state %answers)))
      (equal? (review-answers after) %answers)))

  (test-equal "a settings change re-renders the declaration"
    "renamed"
    (let ((state (fresh)))
      (review-sync state (with-answer 'host-name "renamed"))
      (summary-ref (declaration-summary %declaration) 'host-name)))

  (test-assert "a storage change un-prepares the review"
    (let ((state (fresh)))
      (not (review-prepared?
            (review-sync state
                         (with-answer 'storage
                                      '((mode . simple)
                                        (disk . "/dev/vdb")
                                        (filesystem . "ext4"))))))))

  (test-assert "a hand-edited declaration is noticed"
    (let ((state (fresh)))
      (call-with-output-file %declaration
        (lambda (port)
          (display (slurp %declaration) port)
          (format port "~%;; hand edit~%")))
      (review-hand-edited? state)))

  (test-equal "the summary after a hand edit reads the file"
    "other"
    (let ((state (fresh)))
      ;; The file now says what an edit made it say; the answers still say
      ;; box0, and the file wins.
      (serialize-to-file %declaration (with-answer 'host-name "other") '())
      (summary-ref (review-summary state %answers) 'host-name)))

  (test-assert "a broken declaration fails the check with a message"
    (let ((state (fresh)))
      (call-with-output-file %declaration
        (lambda (port) (format port "(operating-system~%")))
      (let ((problem (review-check state)))
        (and (string? problem)
             (positive? (string-length problem))))))

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
