;;; tests/wizard-set.scm — wizard-set, exercised without the SRFI-64 runner.
;;; Copyright © 2026 Zhen-Lin Huo <zhen-lin.huo@gmx.com>
;;;
;;; This file is part of Gradus.

(use-modules (gradus answers)
             (gradus wizard))

(define (check name expected actual)
  (if (equal? expected actual)
      (begin (display "* PASS: ") (display name) (newline))
      (begin (display "* FAIL: ") (display name)
             (display " expected ") (write expected)
             (display " got ") (write actual) (newline)
             (exit 1))))

(check "set records an answer"
       '((host-name . "vm0"))
       (wizard-answers (wizard-set (make-wizard) 'host-name "vm0")))

(check "set replaces an earlier value"
       '((host-name . "vm1"))
       (wizard-answers
        (wizard-set (wizard-set (make-wizard) 'host-name "vm0")
                    'host-name "vm1")))

(check "set keeps the step"
       'locale
       (wizard-step (wizard-set (wizard-next (make-wizard)) 'host-name "vm0")))

(display "* PASS: wizard-set\n")
