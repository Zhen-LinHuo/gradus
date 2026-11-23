;;; tests/answers.scm — answer-file validation tests.
;;; Copyright © 2026 Zhen-Lin Huo <zhen-lin.huo@gmx.com>
;;;
;;; This file is part of Gradus.

(use-modules (srfi srfi-64)
             (gradus answers))

(define runner (test-runner-simple))
(test-with-runner runner

  (define minimal
    '((schema-version . 1)
      (profile . "headless")
      (storage (mode . simple) (disk . "/dev/vda"))
      (users ((name . "tester") (group . "users")))))

  (test-assert "a minimal answer file validates"
    (validate-answers (copy-tree minimal)))

  (test-assert "an unknown key is rejected"
    (catch #t
      (lambda ()
        (validate-answers (append minimal '((secrets . "none"))))
        #f)
      (lambda args #t)))

  (test-assert "a missing required key is rejected"
    (catch #t
      (lambda ()
        (validate-answers
         '((schema-version . 1) (profile . "headless")))
        #f)
      (lambda args #t)))

  (test-assert "an unknown profile is rejected"
    (catch #t
      (lambda ()
        (validate-answers
         (append minimal '((profile . "appliance"))))
        #f)
      (lambda args #t)))

  (test-assert "schema-version 0 is rejected"
    (catch #t
      (lambda ()
        (validate-answers
         (append minimal '((schema-version . 0))))
        #f)
      (lambda args #t)))

  (test-assert "an empty users list is rejected"
    (catch #t
      (lambda ()
        (validate-answers
         (append minimal '((users ()))))
        #f)
      (lambda args #t))))

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
