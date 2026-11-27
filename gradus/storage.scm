;;; gradus/storage.scm — device discovery for the storage step.
;;; Copyright © 2026 Zhen-Lin Huo <zhen-lin.huo@gmx.com>
;;;
;;; This file is part of Gradus.

(define-module (gradus storage)
  #:use-module (gradus utils)
  #:use-module (gradus fs)
  #:use-module (ice-9 match)
  #:use-module (ice-9 string-fun)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:use-module (ice-9 rdelim)
  #:use-module (srfi srfi-11)
  #:export (simple-layout
            parted-arguments
            disk-busy?
            partition-name
            lvm-commands
            prepare-target
            prepare-simple))

(define (partition-name disk number)
  "Return the device name of partition NUMBER on DISK.  Disks whose name ends
in a digit (loop0, nvme0n1) use a p separator; classical names do not."
  (if (char-numeric? (string-ref disk (- (string-length disk) 1)))
      (string-append disk "p" (number->string number))
      (string-append disk (number->string number))))

(define (disk-busy? disk)
  "Whether DISK, or any of its partitions, is mounted or holds the live medium.
Installing onto the medium the installer is running from destroys the session
and is always a mistake, so this is checked before anything is written."
  (let* ((name (car (last-pair (string-split disk #\/))))
         (mounts (call-with-input-file "/proc/mounts" (lambda (port) (read-string port))))
         (cmdline (if (file-exists? "/proc/cmdline")
                      (call-with-input-file "/proc/cmdline" read-string)
                      "")))
    (or (string-contains mounts disk)
        (string-contains mounts (string-append "/dev/" name))
        (string-contains cmdline (string-append "root=/dev/" name))
        ;; A live medium booted from a device appears in /proc/cmdline as a
        ;; label or UUID; the disk being removable is a second hint.
        (let ((removable (format #f "/sys/block/~a/removable" name)))
          (and (file-exists? removable)
               (equal? (string-trim-both
                        (call-with-input-file removable read-line))
                       "1"))))))

(define (storage-option answers key default)
  "An option from the storage section of ANSWERS, or DEFAULT."
  (or (assq-ref (assq-ref answers 'storage) key) default))

(define (parted-size n)
  "A size for parted, in MiB."
  (format #f "~aMiB" n))

(define (simple-layout answers)
  "The partitions to create, as (name type start end).  The layout follows the
bootloader and the sizes the operator chose; END is `100%' for a root that
takes the rest of the disk."
  (let* ((efi? (eq? (assq-ref (assq-ref answers 'boot) 'bootloader) 'grub-efi))
         (esp (if efi? (storage-option answers 'esp-size 1024) 0))
         (swap (storage-option answers 'swap-size 0))
         (root (storage-option answers 'root-size 0))
         (after-first (if efi? (+ 1 esp) 2)))
    (append
     (if efi?
         (list (list "ESP" "fat32" 1 (+ 1 esp)))
         (list (list "biosboot" #f 1 2)))
     (if (> swap 0)
         (list (list "swap" "linux-swap" after-first (+ after-first swap)))
         '())
     (let ((root-start (+ after-first (if (> swap 0) swap 0))))
       (list (list "root" "ext4" root-start
                   (if (> root 0) (+ root-start root) "100%")))))))

(define (parted-arguments disk layout)
  "The parted invocation that creates LAYOUT on DISK."
  (append
   (list "-s" disk "mklabel" "gpt")
   (append-map
    (lambda (partition)
      (let ((name (first partition))
            (type (second partition))
            (start (third partition))
            (end (fourth partition)))
        (append
         (if type
             (list "mkpart" name type (parted-size start)
                   (if (equal? end "100%") "100%" (parted-size end)))
             (list "mkpart" name (parted-size start) (parted-size end)))
         (cond ((string=? name "ESP") (list "set" "1" "esp" "on"))
               ((string=? name "biosboot") (list "set" "1" "bios_grub" "on"))
               (else '())))))
    layout)))

(define (prepare-simple answers)
  "Partition and format the target described by a `simple' storage answer,
then return the label-keyed device map of what was created.  The layout
follows the bootloader; the sizes follow the answers; encryption, when asked
for, is LUKS1 because GRUB has to read the root file system at boot."
  (let* ((storage (assq-ref answers 'storage))
         (disk (assq-ref storage 'disk))
         (efi? (eq? (assq-ref (assq-ref answers 'boot) 'bootloader) 'grub-efi))
         (swap (storage-option answers 'swap-size 0))
         (encryption (assq-ref storage 'encryption))
         (layout (simple-layout answers))
         (partitions (map (lambda (p) (first p)) layout))
         (index-of (lambda (name)
                     (+ 1 (list-index (lambda (p) (string=? p name)) partitions))))
         (root-part (partition-name disk (index-of "root")))
         (swap-part (and (> swap 0)
                         (partition-name disk (index-of "swap"))))
         (first-part (partition-name disk 1)))
    (when (disk-busy? disk)
      (error "the target disk is in use and will not be written to" disk))
    (unless (zero? (apply run-command/stream "parted"
                          (parted-arguments disk layout)))
      (error "partitioning failed" disk))
    (run-command/stream "partprobe" disk)
    (run-command/stream "udevadm" "settle")
    (when efi?
      (unless (zero? (run-command/stream "mkfs.vfat" "-n" "GRADUS-ESP" first-part))
        (error "mkfs.vfat failed" first-part)))
    (when swap-part
      (unless (zero? (run-command/stream "mkswap" "-L" "gradus-swap" swap-part))
        (error "mkswap failed" swap-part)))
    (let* ((fs (or (assq-ref storage 'filesystem) (fs-default)))
           (row (or (fs-lookup fs) (error "unknown file system" fs)))
           (root-device
            (if encryption
               (let* ((name (or (assq-ref encryption 'name) "cryptroot"))
                      (mapper (string-append "/dev/mapper/" name))
                      (passphrase (or (assq-ref encryption 'passphrase) "")))
                 (with-secret-file
                  passphrase
                  (lambda (key-file)
                    (unless (zero? (run-command/stream
                                    "cryptsetup" "luksFormat" "--type" "luks1"
                                    "--batch-mode" "--key-file" key-file
                                    root-part))
                      (error "cryptsetup luksFormat failed" root-part))
                    (unless (zero? (run-command/stream
                                    "cryptsetup" "open" "--key-file" key-file
                                    root-part name))
                      (error "cryptsetup open failed" root-part))))
                 mapper)
               root-part)))
      (let* ((tool (car (fs-capability-mkfs row)))
             (_ (unless (zero? (status:exit-val
                                (system* "sh" "-c"
                                         (format #f "command -v ~a" tool))))
                  (error (format #f
                                 "~a is not installed on this system; choose another filesystem or add its package to the image"
                                 tool))))
             (command (fs-mkfs-command row "gradus-root" root-device)))
        (unless (zero? (apply run-command/stream command))
          (error (format #f "~a failed" (car command)) root-device)))
      (append
       (fs-blkid-map (append (if efi? (list first-part) '())
                             (if swap-part (list swap-part) '())))
       (fs-root-identify row root-device "gradus-root")
       ;; render needs the underlying partition for mapped-device, which blkid
       ;; cannot tell from the mapper's own label.
       (if encryption
           (let-values (((status output)
                         (run-command "cryptsetup" "luksUUID" root-part)))
             (unless (zero? status)
               (error "cryptsetup luksUUID failed" root-part))
             (list (cons "gradus-crypt"
                         (list (cons 'device root-part)
                               (cons 'type "crypto_LUKS")
                               (cons 'uuid (string-trim-both output))))))
           '())))))

(define (volume-group storage)
  "Return the volume group named by STORAGE, defaulting to \"vg0\"."
  (or (assq-ref storage 'volume-group) "vg0"))

(define (lvm-commands storage)
  "Return the list of commands that prepare an LVM target described by STORAGE.
The disk gets an ESP and one physical-volume partition; the root volume is
formatted inside the volume group.  Nothing here touches a data volume: those
are adopted by the declaration, never created."
  (let* ((disk (assq-ref storage 'disk))
         (vg (volume-group storage))
         (esp (partition-name disk 1))
         (pv (partition-name disk 2))
         (volumes (or (assq-ref storage 'volumes) '()))
         (root (or (find (lambda (v) (equal? (assq-ref v 'name) "root")) volumes)
                   (error "an LVM target needs a volume named root"))))
    (append
     (list (list "parted" "-s" disk "mklabel" "gpt"
                 "mkpart" "ESP" "fat32" "1MiB" "1025MiB"
                 "set" "1" "esp" "on"
                 "mkpart" "pv" "ext4" "1025MiB" "100%"
                 "set" "2" "lvm" "on")
           (list "partprobe" disk)
           (list "udevadm" "settle")
           (list "mkfs.vfat" "-n" "GRADUS-ESP" esp)
           (list "pvcreate" "-y" pv)
           (list "vgcreate" vg pv))
     (map (lambda (volume)
            (list "lvcreate" "-y" "-n" (assq-ref volume 'name)
                  "-L" (or (assq-ref volume 'size) "100%FREE") vg))
          (remove (lambda (v) (equal? (assq-ref v 'name) "root")) volumes))
     (list (list "lvcreate" "-y" "-n" "root"
                 "-l" "100%FREE" vg)
           (list (string-append "mkfs." (or (assq-ref root 'type) "ext4"))
                 "-L" (or (assq-ref root 'label) "gradus-root")
                 (string-append "/dev/mapper/" vg "-root"))))))

(define (prepare-lvm answers)
  "Prepare the LVM target described by ANSWERS and return its device map."
  (let* ((storage (assq-ref answers 'storage))
         (disk (assq-ref storage 'disk))
         (vg (volume-group storage))
         (esp (partition-name disk 1))
         (root (string-append "/dev/mapper/" vg "-root")))
    (when (disk-busy? disk)
      (error "the target disk is in use and will not be written to" disk))
    (for-each (lambda (command)
                (unless (zero? (apply run-command/stream command))
                  (error "storage command failed" command)))
              (lvm-commands storage))
    (fs-blkid-map (list esp root))))

(define (prepare-target answers)
  "Prepare the target described by ANSWERS and return its device map.  The
storage mode decides how the target is laid out; data volumes are adopted, not
created."
  (let ((mode (assq-ref (assq-ref answers 'storage) 'mode)))
    (cond
     ((eq? mode 'simple) (prepare-simple answers))
     ((eq? mode 'lvm) (prepare-lvm answers))
     (else (error "unsupported storage mode" mode)))))
