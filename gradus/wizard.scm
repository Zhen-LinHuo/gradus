;;; gradus/wizard.scm — the interactive page flow, independent of any
;;; front-end.  A TUI, a Web UI or a test driver all drive the same machine.
;;; Copyright © 2026 Zhen-Lin Huo <zhen-lin.huo@gmx.com>
;;;
;;; This file is part of Gradus.

(define-module (gradus wizard)
  #:use-module (ice-9 match)
  #:use-module (srfi srfi-1)
  #:export (%wizard-steps
            firmware-bootloader
            with-defaults
            storage-answers
            make-wizard
            wizard-answers
            wizard-step
            wizard-language
            wizard-set-language
            wizard-next
            wizard-back
            wizard-set
            wizard-complete?))

;; The order a human meets the questions in.  `install' is not a question: it
;; is the gate the operator walks through when every page is answered.
;; The order follows YaST's flow, not Agama's: keyboard and disk come early,
;; the source is chosen before the software that will be fetched from it, and
;; the system-wide settings (timezone, NTP) sit near the end.
(define %wizard-steps
  '(language locale storage source software boot network users review install))

;; A wizard holds three things: the answers collected so far, the current step,
;; and the interface language.  The language is deliberately *not* an answer:
;; the answer file has a closed set of keys and the interface language is not
;; one of them.  Every transition returns a new wizard, which is what makes the
;; flow testable without a terminal.

(define %default-language 1)          ; 0 Chinese, 1 English

;; Keys the pages do not ask about.  They are part of the answer shape, so the
;; wizard owns them rather than any one front-end.
(define (firmware-bootloader)
  "The bootloader this machine can actually boot: EFI where the firmware
provides it, BIOS otherwise."
  (if (file-exists? "/sys/firmware/efi") 'grub-efi 'grub-bios))

(define (%answer-defaults)
  `((schema-version . 1)
    (profile . "headless")
    (host-name . "gradus")
    ;; A machine must be installable without visiting a boot page; the page
    ;; itself arrives later and overrides this.
    (boot . ((bootloader . ,(firmware-bootloader)) (timeout . 5)))))

(define (with-defaults answers)
  "Fill in the keys the wizard does not ask about, without overriding anything
the operator chose."
  (append answers
          (filter (lambda (pair) (not (assq (car pair) answers)))
                  (%answer-defaults))))

(define (storage-answers mode disk)
  "The storage answer for MODE and DISK.  It is an alist, and it is built here
so that a front-end cannot get the shape wrong."
  (append (list (cons 'mode mode) (cons 'disk disk))
          (if (eq? mode 'lvm)
              '((volume-group . "vg0")
                (volumes ((name . "root") (size . "100%FREE"))))
              '())))

(define (make-wizard)
  "A wizard at the first step, with no answers."
  (list '() (car %wizard-steps) %default-language))

(define (wizard-answers wizard)
  "The answers collected so far, as an alist."
  (car wizard))

(define (wizard-step wizard)
  "The current step, one of `%wizard-steps'."
  (cadr wizard))

(define (wizard-language wizard)
  "The interface language index: 0 Chinese, 1 English."
  (caddr wizard))

(define (wizard-set-language wizard language)
  "Record LANGUAGE as the interface language."
  (list (wizard-answers wizard) (wizard-step wizard) language))

(define (wizard-next wizard)
  "Move to the following step; staying put at the last one is not an error."
  (let ((rest (memq (wizard-step wizard) %wizard-steps)))
    (if (and (pair? rest) (pair? (cdr rest)))
        (list (wizard-answers wizard) (cadr rest) (wizard-language wizard))
        wizard)))

(define (wizard-back wizard)
  "Move to the previous step; staying put at the first one is not an error."
  (let loop ((remaining %wizard-steps)
             (previous #f))
    (match remaining
      ((step . rest)
       (if (eq? step (wizard-step wizard))
           (if previous
               (list (wizard-answers wizard) previous (wizard-language wizard))
               wizard)
           (loop rest step)))
      (() wizard))))

(define (alist-remove alist key)
  "ALIST without KEY.  Pure: the wizard never mutates a value it was given."
  (filter (lambda (pair) (not (eq? (car pair) key))) alist))

(define (wizard-set wizard key value)
  "Record KEY as VALUE in the answers, replacing any earlier value."
  (list (acons key value (alist-remove (wizard-answers wizard) key))
        (wizard-step wizard)
        (wizard-language wizard)))

(define (wizard-complete? wizard)
  "Whether every step has been visited and the wizard sits at `install'."
  (eq? (wizard-step wizard) 'install))
