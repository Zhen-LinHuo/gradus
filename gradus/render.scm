;;; gradus/render.scm — answers to an operating-system declaration.
;;; Copyright © 2026 Zhen-Lin Huo <zhen-lin.huo@gmx.com>
;;;
;;; This file is part of Gradus.

(define-module (gradus render)
  #:use-module (gnu)
  #:use-module (gnu bootloader)
  #:use-module (gnu packages linux)
  #:use-module (gnu system)
  #:use-module (gnu system file-systems)
  #:use-module (gnu services ssh)
  #:use-module (gradus answers)
  #:use-module (srfi srfi-1)
  #:export (%root-label
            %esp-label
            render-answers))

;;; The labels are the contract between the storage step, which creates them
;;; on the target, and the declaration, which mounts by label.  They are
;;; defined once, here.

(define %root-label "gradus-root")
(define %esp-label "GRADUS-ESP")

(define (boot-record boot)
  "Translate the boot section of an answer file into a
bootloader-configuration.  `none' is a deliberate value, but the renderer does
not implement it yet: an operating-system record without a bootloader is a
larger change than this slice."
  (let ((kind (assq-ref boot 'bootloader))
        (timeout (or (assq-ref boot 'timeout) 5)))
    (cond ((eq? kind 'none)
           (answers-error "bootloader `none' is not implemented by the renderer yet"))
          ((eq? kind 'grub-efi)
           (bootloader-configuration
            (bootloader grub-efi-bootloader)
            (targets (list "/boot/efi"))
            (timeout timeout)))
          ((eq? kind 'grub-bios)
           (bootloader-configuration
            (bootloader grub-bootloader)
            (targets (list (assq-ref boot 'target)))
            (timeout timeout)))
          (else
           (answers-error (format #f "unsupported bootloader: ~a" kind))))))

(define (answer-users users)
  "Map the answer users onto user-account records.  Every user gets the
`users' group and a home directory; the administrative group is added by the
caller when the answers name it."
  (map
   (lambda (u)
     (user-account
      (name (assq-ref u 'name))
      (group (or (assq-ref u 'group) "users"))
      (supplementary-groups
       (or (assq-ref u 'groups) '("wheel")))
      (home-directory (string-append "/home/" (assq-ref u 'name)))))
   users))

(define (simple-file-systems)
  "The file systems for `simple' storage mode: one ext4 root and one EFI
system partition, both addressed by label."
  (list (file-system
          (mount-point "/")
          (device (file-system-label %root-label))
          (type "ext4"))
        (file-system
          (mount-point "/boot/efi")
          (device (file-system-label %esp-label))
          (type "vfat"))))

(define (render-answers answers)
  "Render a validated answer form into an operating-system declaration.  The
result is a plain record: nothing is installed by this procedure."
  (let ((boot (assq-ref answers 'boot))
        (storage (assq-ref answers 'storage))
        (users (assq-ref answers 'users)))
    (unless (eq? (assq-ref storage 'mode) 'simple)
      (answers-error (format #f "storage mode not implemented: ~a"
                             (assq-ref storage 'mode))))
    (operating-system
      (host-name (or (assq-ref answers 'host-name) "gradus"))
      (timezone (or (assq-ref answers 'timezone) "UTC"))
      (locale (or (assq-ref answers 'locale) "en_US.utf8"))
      (kernel linux-libre)
      (bootloader (boot-record boot))
      (file-systems (simple-file-systems))
      (services
       (cons* (service openssh-service-type)
              %base-services))
      (users (answer-users users)))))
