;;; tests/wizard.scm — the page flow, independent of any front-end.
;;; Copyright © 2026 Zhen-Lin Huo <zhen-lin.huo@gmx.com>
;;;
;;; This file is part of Gradus.

(use-modules (srfi srfi-1)
             (srfi srfi-64)
             (gradus answers)
             (gradus wizard))

(define runner (test-runner-simple))
(test-runner-current runner)

(define w (make-wizard))

(test-equal "the first step is language"
  'language (wizard-step w))

(test-equal "a fresh wizard has no answers"
  0 (length (wizard-answers w)))

(test-equal "next moves through the steps in order"
  '(review users network software boot storage source locale language)
  (let loop ((current w) (seen '()))
    (if (wizard-complete? current)
        seen
        (loop (wizard-next current) (cons (wizard-step current) seen)))))

(test-equal "back moves one step up"
  'locale (wizard-step (wizard-back (wizard-next (wizard-next w)))))

(test-assert "back at the first step stays there"
  (eq? 'language (wizard-step (wizard-back w))))

(test-assert "next at the last step stays there"
  (let ((at-end (wizard-next (wizard-next (wizard-next (wizard-next
                   (wizard-next (wizard-next (wizard-next (wizard-next
                     (wizard-next (wizard-next w))))))))))))
    (and (wizard-complete? at-end) (eq? at-end (wizard-next at-end)))))

(test-equal "set records the answer"
  '((host-name . "vm0"))
  (wizard-answers (wizard-set (make-wizard) 'host-name "vm0")))

(test-equal "set replaces an earlier answer"
  '((host-name . "vm1"))
  (wizard-answers (wizard-set (wizard-set (make-wizard) 'host-name "vm0")
                              'host-name "vm1")))

(test-assert "the interface language is state, not an answer"
  (not (assq 'ui-language (wizard-answers (wizard-set-language (make-wizard) 0)))))

(test-equal "the language survives navigation"
  0 (wizard-language (wizard-next (wizard-set-language (make-wizard) 0))))

(test-equal "the storage answer names its disk"
  "/dev/vdb"
  (assq-ref (storage-answers 'simple "/dev/vdb") 'disk))

(test-equal "an lvm storage answer carries a volume group"
  "vg0"
  (assq-ref (storage-answers 'lvm "/dev/vdb") 'volume-group))

(test-assert "the answers the wizard collects validate"
  (let* ((wizard (wizard-set (wizard-set (make-wizard)
                                         'storage
                                         '((mode . simple) (disk . "/dev/vda")))
                             'users
                             '(((name . "user") (group . "users")))))
         (answers (with-defaults (wizard-answers wizard))))
    (validate-answers answers)
    #t))

(test-equal "the default bootloader follows the firmware"
  (if (file-exists? "/sys/firmware/efi") 'grub-efi 'grub-bios)
  (firmware-bootloader))

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
