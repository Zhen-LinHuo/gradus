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

(define (uuid-type-for fs-type)
  "Map a file-system type name onto the UUID type that `string->uuid'
understands."
  (match fs-type
    ("vfat" 'fat)
    ("ext2" 'ext2)
    ("ext3" 'ext3)
    ("ext4" 'ext4)
    ("btrfs" 'btrfs)
    (_ 'dce)))

(define (file-system-by-label label type device-map)
  "Return the device for LABEL: a UUID object when DEVICE-MAP has read one
back from the freshly created file system, otherwise the label itself.  The
map is keyed by label strings, so the lookup is by `assoc-ref'."
  (let ((entry (assoc-ref device-map label)))
    (if (and entry (assq-ref entry 'uuid) (assq-ref entry 'type))
        (let* ((fs-type (assq-ref entry 'type))
               (uuid-type (uuid-type-for fs-type))
               (bv (string->uuid (assq-ref entry 'uuid) uuid-type)))
          (if bv
              (bytevector->uuid bv uuid-type)
              (file-system-label label)))
        (file-system-label label))))

(define (simple-file-systems device-map)
  "The file systems for `simple' storage mode: one ext4 root and one EFI
system partition, addressed by UUID when the map knows it, by label otherwise."
  (list (file-system
          (mount-point "/")
          (device (file-system-by-label %root-label "ext4" device-map))
          (type "ext4"))
        (file-system
          (mount-point "/boot/efi")
          (device (file-system-by-label %esp-label "vfat" device-map))
          (type "vfat"))))

(define (render-answers/devices answers device-map)
  "Render a validated answer form into an operating-system declaration.
DEVICE-MAP is the label-keyed map returned by the storage step; labels for
which a UUID is known become UUID devices in the declaration.  The result is a
plain record: nothing is installed by this procedure."
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
      (file-systems (simple-file-systems device-map))
      (services
       (cons* (service openssh-service-type)
              %base-services))
      (users (answer-users users)))))

(define (render-answers answers)
  "Render ANSWERS without a device map: file systems fall back to labels."
  (render-answers/devices answers '()))
