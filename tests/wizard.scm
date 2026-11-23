;;; tests/wizard.scm — the page flow, independent of any front-end.
;;; Copyright © 2026 Zhen-Lin Huo <zhen-lin.huo@gmx.com>
;;;
;;; This file is part of Gradus.

(use-modules (srfi srfi-64)
             (gradus answers)
             (gradus wizard))

(define runner (test-runner-simple))
(test-with-runner runner

  (define w (make-wizard))

  (test-equal "the first step is language"
    'language (wizard-step w))

  (test-equal "a fresh wizard has no answers"
    0 (length (wizard-answers w)))

  (test-equal "next moves through the steps in order"
    '(review users storage source language)
    (let loop ((w w) (seen '()))
      (if (wizard-complete? w)
          seen
          (loop (wizard-next w) (cons (wizard-step w) seen)))))

  (test-equal "back moves one step up"
    'source (wizard-step (wizard-back (wizard-next (wizard-next w)))))

  (test-assert "back at the first step stays there"
    (eq? 'language (wizard-step (wizard-back w))))

  (test-assert "next at the last step stays there"
    (wizard-complete? (wizard-next (wizard-next (wizard-next
                            (wizard-next (wizard-next
                              (wizard-next (wizard-next w)))))))))

  (test-equal "set records the answer"
    "vm0" (assq-ref (wizard-answers (wizard-set w 'host-name "vm0"))
                    'host-name))

  (test-equal "set replaces an earlier answer"
    1
    (length (filter (lambda (pair) (eq? (car pair) 'host-name))
                    (wizard-answers
                     (wizard-set (wizard-set w 'host-name "vm0")
                                 'host-name "vm1")))))

  (test-assert "the answers the wizard collects validate"
    (let* ((w (wizard-set (wizard-set (make-wizard)
                                      'storage
                                      '((mode . simple) (disk . "/dev/vda")))
                          'users
                          '(((name . "user") (group . "users")))))
           (answers (with-defaults (wizard-answers w))))
      (validate-answers answers)
      #t))

  (test-equal "set keeps the newest value"
    "vm1"
    (assq-ref (wizard-answers
               (wizard-set (wizard-set w 'host-name "vm0")
                           'host-name "vm1"))
              'host-name)))

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
