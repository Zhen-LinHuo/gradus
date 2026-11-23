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
  #:use-module (gnu system mapped-devices)
  #:use-module (gnu system uuid)
  #:use-module (gnu services)
  #:use-module (gnu services base)
  #:use-module (gnu services ssh)
  #:use-module (gnu services networking)
  #:use-module (ice-9 string-fun)
  #:use-module (gradus answers)
  #:use-module (srfi srfi-1)
  #:export (%root-label
            %esp-label
            render-answers
            render-answers/devices
            proxy-environment))

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
  (cond ((string=? fs-type "vfat") 'fat)
        ((string=? fs-type "ext2") 'ext2)
        ((string=? fs-type "ext3") 'ext3)
        ((string=? fs-type "ext4") 'ext4)
        ((string=? fs-type "btrfs") 'btrfs)
        (else 'dce)))

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

(define (render-assemble answers)
  "Translate the `assemble' section into mapped-device records.  Every entry
names the assembly by its own name and source; member disks are identified at
disk level by the caller.  mdadm arrays are not implemented yet: Guix has no
native declarative mdadm assembly, and the honest answer until one exists is
an explicit error."
  (map
   (lambda (entry)
     (let ((kind (assq-ref entry 'kind))
           (source (assq-ref entry 'source))
           (target (assq-ref entry 'target)))
       (unless (and source target)
         (answers-error "assemble entries need a source and a target"))
       (cond ((eq? kind 'luks)
              (mapped-device
               (source source)
               (targets (list target))
               (type luks-device-mapping)))
             ((eq? kind 'lvm)
              (mapped-device
               (source source)
               (targets (list target))
               (type lvm-device-mapping)))
             ((eq? kind 'md)
              (answers-error "mdadm assembly is not implemented yet; use btrfs RAID or wait for a declarative mdadm service"))
             (else
              (answers-error (format #f "unknown assembly kind: ~a" kind))))))
   (or (assq-ref answers 'assemble) '())))

(define (data-volume-device spec fs-type)
  "Turn a data-volume device specification into a file-system device.  The
spec is `uuid:STRING' or `label:STRING'; a UUID is preferred because a label
survives reformatting and a UUID does not."
  (cond ((string-prefix? "uuid:" spec)
         (let* ((uuid-string (string-drop spec 5))
                (uuid-type (uuid-type-for fs-type))
                (bv (string->uuid uuid-string uuid-type)))
           (if bv
               (bytevector->uuid bv uuid-type)
               (answers-error (format #f "invalid UUID: ~a" uuid-string)))))
        ((string-prefix? "label:" spec)
         (file-system-label (string-drop spec 6)))
        (else
         (answers-error
          (format #f "data volumes must be addressed as uuid: or label:, not ~a"
                  spec)))))

(define (data-volume-file-systems storage)
  "Adopt the data volumes named in STORAGE: they are mounted, never created.
A volume names its device as uuid:STRING (preferred) or label:STRING."
  (map
   (lambda (volume)
     (let* ((type (assq-ref volume 'type))
            (mount-point (assq-ref volume 'mount-point))
            (spec (assq-ref volume 'device)))
       (unless (and mount-point type spec)
         (answers-error "data volumes need a mount-point, a type and a device"))
       (file-system
         (mount-point mount-point)
         (device (data-volume-device spec type))
         (type type)
         (needed-for-boot? #f)
         (create-mount-point? #t))))
   (or (assq-ref storage 'data-volumes) '())))

(define (substitute-service-list answers)
  "The substitute services declared in the answers, or the empty list."
  (or (assq-ref (assq-ref answers 'source) 'substitute-services) '()))

(define (substitute-urls answers)
  "The ordered substitute URLs from the answers."
  (filter-map (lambda (service) (assq-ref service 'url))
              (substitute-service-list answers)))

(define (authorized-keys answers)
  "The signing-key files from the answers, as file-like objects.  A mirror of
official store paths needs none; an independent builder does."
  (filter-map (lambda (service)
                (let ((key (assq-ref service 'key)))
                  (and key (local-file key))))
              (substitute-service-list answers)))

(define (proxy-environment answers)
  "The daemon environment entries for the proxy in the answers.  The Guix
daemon honours http_proxy, https_proxy and no_proxy, and a local cache must be
reachable directly, hence the explicit no_proxy list."
  (let ((proxy (assq-ref answers 'proxy)))
    (if proxy
        (filter-map
         (lambda (entry)
           (let ((name (car entry)) (value (cdr entry)))
             (and value (string-append name "=" value))))
         `(("http_proxy" . ,(assq-ref proxy 'http))
           ("https_proxy" . ,(assq-ref proxy 'https))
           ("no_proxy" . ,(and=> (assq-ref proxy 'no-proxy)
                                 (lambda (hosts)
                                   (string-join hosts ","))))))
        '())))

(define (guix-service-for answers)
  "The guix-service-type modification that carries the answers' sources and
proxy into the installed system."
  (let ((urls (substitute-urls answers))
        (keys (authorized-keys answers))
        (environment (proxy-environment answers)))
    (lambda (config)
      (guix-configuration
       (inherit config)
       (substitute-urls (if (null? urls)
                            (guix-configuration-substitute-urls config)
                            urls))
       (authorized-keys (if (null? keys)
                            (guix-configuration-authorized-keys config)
                            keys))
       (environment (append environment
                            (guix-configuration-environment config)))))))

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
      (mapped-devices (render-assemble answers))
      (file-systems (append (simple-file-systems device-map)
                            (data-volume-file-systems storage)))
      (services
       (cons* (service openssh-service-type)
              (service dhcpcd-service-type)
              (modify-services %base-services
                (guix-service-type config =>
                                   ((guix-service-for answers) config)))))
      (users (answer-users users)))))

(define (render-answers answers)
  "Render ANSWERS without a device map: file systems fall back to labels."
  (render-answers/devices answers '()))
