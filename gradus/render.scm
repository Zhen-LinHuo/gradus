;;; gradus/render.scm — answers to an operating-system declaration.
;;; Copyright © 2026 Zhen-Lin Huo <zhen-lin.huo@gmx.com>
;;;
;;; This file is part of Gradus.

(define-module (gradus render)
  #:use-module (gradus fs)
  #:use-module (gradus package-groups)
  #:use-module (gradus selection)
  #:use-module (gnu)
  #:use-module (gnu bootloader)
  #:use-module (gnu packages linux)
  #:use-module (gnu system)
  #:use-module (gnu system shadow)
  #:use-module (gnu packages)
  #:use-module (gnu system keyboard)
  #:use-module (gnu system mapped-devices)
  #:use-module (gnu system file-systems)
  #:use-module (gnu system file-systems)
  #:use-module (gnu system mapped-devices)
  #:use-module (gnu system uuid)
  #:use-module (gnu services)
  #:use-module (gnu services base)
  #:use-module (gnu services desktop)
  #:use-module (gnu services ssh)
  #:use-module (gnu services xorg)
  #:use-module (gnu services networking)
  #:use-module (ice-9 string-fun)
  #:use-module (gradus answers)
  #:use-module (gradus storage)
  #:use-module (srfi srfi-1)
  #:export (%root-label
            %esp-label
            render-answers
            render-answers/devices
            answer-package-names
            answer-desktop-package-names
            answer-environments
            desktop-environment?
            crypt-container-known?
            proxy-environment))

;;; The labels are the contract between the storage step, which creates them
;;; on the target, and the declaration, which mounts by label.  They are
;;; defined once, here.

(define %root-label "gradus-root")
(define %esp-label "GRADUS-ESP")

(define (encryption answers)
  "The encryption section of the answers, or #f."
  (assq-ref (assq-ref answers 'storage) 'encryption))

(define (crypt-name answers)
  (or (assq-ref (encryption answers) 'name) "cryptroot"))

(define (swap-size answers)
  (or (assq-ref (assq-ref answers 'storage) 'swap-size) 0))

(define (answer-package-names answers)
  "The package specifications the operator asked for: the named packages plus
the packages of every selected package group."
  (let ((software (assq-ref answers 'software)))
    (append (concatenate (map package-group-packages
                              (or (assq-ref software 'package-groups) '())))
            (or (assq-ref software 'extra-packages) '()))))

(define (answer-packages answers)
  "The packages the operator asked for, as package records."
  (map specification->package (answer-package-names answers)))

;; The desktop environments the official Guix installer offers: four arrive
;; as system services, the rest as package sets.  The identifiers are the
;; answer form's; the names are the official ones.
(define (answer-environments answers)
  (let ((desktop (assq-ref answers 'desktop)))
    (if desktop
        (or (assq-ref desktop 'environments) '())
        '())))

(define (desktop-environment? answers)
  (pair? (answer-environments answers)))

(define (environment-service name)
  "The service NAME installs, or #f for the environments that are package
sets rather than services."
  (case name
    ((gnome) (service gnome-desktop-service-type))
    ((xfce) (service xfce-desktop-service-type))
    ((mate) (service mate-desktop-service-type))
    ((plasma) (service plasma-desktop-service-type))
    (else #f)))

(define (environment-packages name)
  "The packages NAME adds beyond its service, or '() for the services."
  (case name
    ((icewm) '("icewm"))
    ((openbox) '("openbox"))
    ((awesome) '("awesome"))
    ((i3) '("i3-wm" "i3status" "dmenu" "st"))
    ((ratpoison) '("ratpoison" "xterm"))
    ((exwm) '("emacs" "emacs-exwm" "emacs-desktop-environment"))
    ((sway) '("sway" "wmenu" "foot"))
    (else '())))

;; What the official installer adds to every desktop: fonts covering the
;; world's scripts, chosen for all locales rather than per-locale.
(define %desktop-font-packages
  '("font-google-noto" "font-google-noto-emoji" "font-sarasa-gothic"))

(define (answer-desktop-package-names answers)
  "The package specifications a desktop adds, as names: the official font
set plus the package sets of the environments that are not services."
  (if (not (desktop-environment? answers))
      '()
      (append %desktop-font-packages
              (append-map environment-packages
                          (answer-environments answers)))))

(define (answer-desktop-packages answers)
  (map specification->package (answer-desktop-package-names answers)))

(define (answer-keyboard answers)
  (and=> (assq-ref answers 'keyboard) keyboard-layout))

(define (boot-serial? boot)
  "True when GRUB is asked to talk on a serial line."
  (any (lambda (key)
         (let ((terminals (assq-ref boot key)))
           (and (pair? terminals) (memq 'serial terminals))))
       '(terminal-outputs terminal-inputs)))

(define (make-bootloader-config bootloader targets timeout boot)
  "Build a bootloader-configuration carrying the terminals and the serial
line settings.  Without them a headless machine can neither see the menu nor
answer the passphrase prompt of an encrypted root."
  (let ((serial? (boot-serial? boot)))
    (bootloader-configuration
     (bootloader bootloader)
     (targets targets)
     (timeout timeout)
     (terminal-outputs (or (assq-ref boot 'terminal-outputs) '()))
     (terminal-inputs (or (assq-ref boot 'terminal-inputs) '()))
     ;; GRUB needs a `serial' command before that terminal can be selected,
     ;; and the command takes the unit and the speed.
     (serial-unit (or (assq-ref boot 'serial-unit) (and serial? 0)))
     (serial-speed (or (assq-ref boot 'serial-speed) (and serial? 115200))))))

(define (boot-record boot disk)
  "Translate the boot section of an answer file into a
bootloader-configuration.  `none' is a deliberate value, but the renderer does
not implement it yet: an operating-system record without a bootloader is a
larger change than this slice."
  (let ((kind (assq-ref boot 'bootloader))
        (timeout (or (assq-ref boot 'timeout) 5)))
    (cond ((eq? kind 'none)
           (answers-error "bootloader `none' is not implemented by the renderer yet"))
          ((eq? kind 'grub-efi)
           (make-bootloader-config grub-efi-bootloader
                                   (list "/boot/efi") timeout boot))
          ((eq? kind 'grub-bios)
           ;; BIOS GRUB is installed into a *device*, never into a directory:
           ;; a target that is not a device path (a mount point, say) would be
           ;; turned into /dev/boot/efi and grub-install would refuse it.  Fall
           ;; back to the disk that holds the system.
           (let ((target (assq-ref boot 'target)))
             (make-bootloader-config
              grub-bootloader
              (list (if (and target (string-prefix? "/dev/" target))
                        target
                        disk))
              timeout boot)))
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
      (home-directory (string-append "/home/" (assq-ref u 'name)))
      (password (assq-ref u 'password))))
   users))

(define (root-account answers)
  "The root account.  Its password comes from the answers when one was given;
otherwise root has no password, which is what an unattended install onto a
machine reachable only by console expects."
  (user-account
   (name "root")
   (group "root")
   (home-directory "/root")
   (password (assq-ref answers 'root-password))))

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

(define (simple-file-systems answers device-map efi?)
  "The file systems for `simple' storage mode: one ext4 root, plus an EFI
system partition on an EFI machine.  A BIOS machine has a BIOS Boot partition
instead, which carries no file system and is not mounted.  Devices are
addressed by UUID when the map knows them, by label otherwise."
  (let ((fs (or (assq-ref (assq-ref answers 'storage) 'filesystem) (fs-default))))
    (append
     (list (file-system
             (mount-point "/")
             (device (if (encryption answers)
                         (string-append "/dev/mapper/" (crypt-name answers))
                         (file-system-by-label %root-label fs device-map)))
             (type fs)))
     (if efi?
         (list (file-system
                 (mount-point "/boot/efi")
                 (device (file-system-by-label %esp-label "vfat" device-map))
                 (type "vfat")))
         '()))))

(define (lvm-root-volume storage)
  "Return the volume named root in STORAGE, or #f."
  (find (lambda (volume) (equal? (assq-ref volume 'name) "root"))
        (or (assq-ref storage 'volumes) '())))

(define (lvm-file-systems storage device-map)
  "The file systems for `lvm' storage mode: the ESP on the disk, and one ext4
root inside the volume group.  Both are addressed by UUID once the storage step
has read them back."
  (let ((label (or (let ((root (lvm-root-volume storage)))
                     (and root (assq-ref root 'label)))
                   %root-label)))
    (list (file-system
            (mount-point "/")
            (device (file-system-by-label label "ext4" device-map))
            (type "ext4"))
          (file-system
            (mount-point "/boot/efi")
            (device (file-system-by-label %esp-label "vfat" device-map))
            (type "vfat")))))

(define (lvm-mapped-devices storage)
  "The volume group that holds the root volume.  Its only physical volume is
the second partition of the target disk; data volumes are assembled separately
and never merged into this one."
  (let ((disk (assq-ref storage 'disk))
        (vg (or (assq-ref storage 'volume-group) "vg0")))
    (list (mapped-device
            (source (list (partition-name disk 2)))
            (targets (list vg))
            (type lvm-device-mapping)))))

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

(define (crypt-source device-map)
  "The source of the root LUKS container: its LUKS UUID when the storage step
read one back.  GRUB only emits a cryptomount command for a UUID source, so a
device path is not a weaker alternative — it is an unbootable declaration.  A
missing entry means nothing has been prepared yet (review, `--dry-run'); the
serializer refuses to write such a declaration rather than guessing."
  (let ((entry (assoc-ref device-map "gradus-crypt")))
    (and entry (assq-ref entry 'uuid)
         (uuid (assq-ref entry 'uuid) 'luks))))

(define (crypt-container-known? device-map)
  "True when DEVICE-MAP carries the LUKS container's UUID."
  (let ((entry (assoc-ref device-map "gradus-crypt")))
    (and entry (assq-ref entry 'uuid))))

(define (root-mapped-device answers device-map)
  "The mapped device that opens the encrypted root described by ANSWERS, using
DEVICE-MAP for the container's identity."
  (mapped-device
   (source (crypt-source device-map))
   (targets (list (crypt-name answers)))
   (type luks-device-mapping)))

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

(define (authorized-keys answers)
  "The signing-key files from the answers, as file-like objects.  A mirror of
official store paths needs none; an independent builder does."
  (map (lambda (path) (local-file path)) (selection-signing-keys answers)))

(define (proxy-environment answers)
  "The declaration's environment field: the proxy from the answers as the
\"NAME=value\" strings a Guix configuration takes.  The model itself lives in
`selection.scm'; this is only its presentation to Guix."
  (map (lambda (pair) (string-append (car pair) "=" (cdr pair)))
       (selection-proxy-environment answers)))

(define (guix-service-for answers)
  "The guix-service-type modification that carries the answers' sources and
proxy into the installed system."
  (let ((urls (selection-substitute-urls answers))
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
        (users (assq-ref answers 'users))
        (mode (assq-ref (assq-ref answers 'storage) 'mode)))
    (unless (memq mode '(simple lvm))
      (answers-error (format #f "storage mode not implemented: ~a" mode)))
    (operating-system
      (host-name (or (assq-ref answers 'host-name) "gradus"))
      (timezone (or (assq-ref answers 'timezone) "UTC"))
      (locale (or (assq-ref answers 'locale) "en_US.utf8"))
      (kernel linux-libre)
      (keyboard-layout (answer-keyboard answers))
      (kernel-arguments (or (assq-ref boot 'extra-kernel-arguments) '()))
      (packages (append (answer-packages answers)
                        (answer-desktop-packages answers)
                        %base-packages))
      (bootloader (boot-record boot (assq-ref storage 'disk)))
      (mapped-devices
       (append (if (eq? mode 'lvm) (lvm-mapped-devices storage) '())
               ;; Only when the container's UUID is known: a mapped device
               ;; without one cannot be unlocked by GRUB, and the serializer
               ;; refuses to write it.
               (if (and (encryption answers)
                        (crypt-container-known? device-map))
                   (list (root-mapped-device answers device-map))
                   '())
               (render-assemble answers)))
      (swap-devices
       (if (> (swap-size answers) 0)
           (list (swap-space
                  (target (file-system-label "gradus-swap"))))
           '()))
      (file-systems (append (if (eq? mode 'lvm)
                                (lvm-file-systems storage device-map)
                                (simple-file-systems
                                 answers device-map
                                 (eq? (assq-ref boot 'bootloader)
                                      'grub-efi)))
                            (data-volume-file-systems storage)))
      (services
       (append (list (service openssh-service-type))
               ;; A desktop brings NetworkManager through %desktop-services;
               ;; two network managers on one host is not a configuration.
               (if (desktop-environment? answers)
                   '()
                   (list (service dhcpcd-service-type)))
               (if (assq-ref answers 'ntp)
                   (list (service ntp-service-type))
                   '())
               (filter-map environment-service (answer-environments answers))
               (if (and (desktop-environment? answers)
                        (answer-keyboard answers))
                   (list (set-xorg-configuration
                          (xorg-configuration
                           (keyboard-layout (answer-keyboard answers)))))
                   '())
               (modify-services (if (desktop-environment? answers)
                                    %desktop-services
                                    %base-services)
                 (guix-service-type config =>
                                    ((guix-service-for answers) config)))))
      ;; No `groups' field: the default (%base-groups) already carries root,
      ;; wheel and users, and replacing it would strip system accounts of
      ;; theirs.
      (users (cons (root-account answers) (answer-users users))))))

(define (render-answers answers)
  "Render ANSWERS without a device map: file systems fall back to labels."
  (render-answers/devices answers '()))
