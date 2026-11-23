;;; gradus/wizard.scm — the interactive page flow, independent of any
;;; front-end.  A TUI, a Web UI or a test driver all drive the same machine.
;;; Copyright © 2026 Zhen-Lin Huo <zhen-lin.huo@gmx.com>
;;;
;;; This file is part of Gradus.

(define-module (gradus wizard)
  #:use-module (ice-9 match)
  #:use-module (srfi srfi-1)
  #:export (%wizard-steps
            make-wizard
            wizard-answers
            wizard-step
            wizard-next
            wizard-back
            wizard-set
            wizard-complete?))

;; The order a human meets the questions in.  `install' is not a question: it
;; is the gate the operator walks through when every page is answered.
(define %wizard-steps
  '(language source storage users review install))

;; A wizard is a pair: the answers collected so far, and the current step.
;; It is an immutable value: every transition returns a new wizard, which is
;; what makes the flow testable without a terminal.

(define (make-wizard)
  "A wizard at the first step, with no answers."
  (cons '() (car %wizard-steps)))

(define (wizard-answers wizard)
  "The answers collected so far, as an alist."
  (car wizard))

(define (wizard-step wizard)
  "The current step, one of `%wizard-steps'."
  (cdr wizard))

(define (wizard-next wizard)
  "Move to the following step; staying put at the last one is not an error."
  (let ((rest (memq (wizard-step wizard) %wizard-steps)))
    (if (and (pair? rest) (pair? (cdr rest)))
        (cons (car wizard) (cadr rest))
        wizard)))

(define (wizard-back wizard)
  "Move to the previous step; staying put at the first one is not an error."
  (let loop ((seen '())
             (remaining %wizard-steps))
    (match remaining
      ((step . rest)
       (if (and (pair? rest) (eq? (car rest) (wizard-step wizard)))
           (cons (car wizard) step)
           (loop (cons step seen) rest)))
      (() wizard))))

(define (wizard-set wizard key value)
  "Record KEY as VALUE in the answers, replacing any earlier value."
  (cons (acons key value (assq-remove! (car wizard) key))
        (cdr wizard)))

(define (wizard-complete? wizard)
  "Whether every step has been visited and the wizard sits at `install'."
  (eq? (wizard-step wizard) 'install))
