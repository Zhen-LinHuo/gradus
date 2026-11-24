;;; tests/answers.scm — answer-file validation tests.
;;; Copyright © 2026 Zhen-Lin Huo <zhen-lin.huo@gmx.com>
;;;
;;; This file is part of Gradus.

(use-modules (srfi srfi-64)
             (srfi srfi-35)
             (gradus answers))

(define (with-key key value alist)
  "Shadow an existing key so that assq-ref finds the replacement first."
  (acons key value alist))

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

  (test-assert "an unsupported storage mode is rejected"
    (catch #t
      (lambda ()
        (validate-answers
         (append minimal '((storage (mode . raid) (disk . "/dev/vda")))))
        #f)
      (lambda args #t)))

  (test-assert "LVM with encryption is rejected"
    (catch #t
      (lambda ()
        (validate-answers
         (append minimal
                 '((storage (mode . lvm) (disk . "/dev/vda")
                            (encryption (mode . luks) (name . "cryptroot")
                                        (passphrase . "secret"))))))
        #f)
      (lambda args #t)))

  (test-assert "encryption with a swap partition is rejected"
    (catch #t
      (lambda ()
        (validate-answers
         (append minimal
                 '((storage (mode . simple) (disk . "/dev/vda") (swap-size . 1024)
                            (encryption (mode . luks) (name . "cryptroot")
                                        (passphrase . "secret"))))))
        #f)
      (lambda args #t)))

  (test-assert "encryption without a passphrase is rejected"
    (catch #t
      (lambda ()
        (validate-answers
         (append minimal
                 '((storage (mode . simple) (disk . "/dev/vda")
                            (encryption (mode . luks) (name . "cryptroot"))))))
        #f)
      (lambda args #t)))

  (test-assert "an empty users list is rejected"
    (catch #t
      (lambda ()
        (validate-answers
         (append minimal '((users ()))))
        #f)
      (lambda args #t))))


(test-with-runner runner
  (test-assert "a terminal GRUB does not know is refused"
    (catch #t
      (lambda ()
        (validate-answers
         (with-key 'boot '((bootloader . grub-efi)
                           (terminal-outputs console klingon))))
        #f)
      (lambda args #t))))

(test-with-runner runner
  (test-assert "a rejected answer explains itself instead of failing on a struct"
    (let ((message
           (call/cc
            (lambda (k)
              (with-exception-handler
               (lambda (obj)
                 (k (if (message-condition? obj) (condition-message obj) #f)))
               (lambda ()
                 (validate-answers
                  (list (cons 'schema-version 1)
                        (cons 'profile "headless")
                        (cons 'storage '((mode . simple) (disk . "/dev/vda")))
                        (cons 'users '((name . "t") (group . "users")))
                        (cons 'boot '((bootloader . grub-efi)
                                      (terminal-outputs console klingon)))))
                 #f))))))
      (and (string? message)
           (string-contains message "unknown terminal")))))

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
