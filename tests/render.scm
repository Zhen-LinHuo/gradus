;;; tests/render.scm — answers-to-declaration rendering tests.
;;; Copyright © 2026 Zhen-Lin Huo <zhen-lin.huo@gmx.com>
;;;
;;; This file is part of Gradus.

(use-modules (srfi srfi-64)
             (srfi srfi-1)
             (gnu system)
             (gnu system file-systems)
             (gnu system mapped-devices)
             (gnu system uuid)
             (gnu system shadow)
             (gnu bootloader)
             (gnu services)
             (gnu services base)
             (gradus render)
             (gradus wizard))

(define runner (test-runner-simple))
(test-runner-current runner)


  (define answers
    '((schema-version . 1)
      (profile . "headless")
      (host-name . "vm0")
      (timezone . "UTC")
      (locale . "en_US.utf8")
      (storage (mode . simple) (disk . "/dev/vda"))
      (boot (bootloader . grub-efi) (timeout . 3))
      (users ((name . "tester") (group . "users")))))

  (define (with-key key value)
    (append (assq-remove! (copy-tree answers) key)
            (list (cons key value))))

  (define os (render-answers answers))

  (test-assert "the result is an operating-system"
    (operating-system? os))

  (test-equal "the host name comes from the answers"
    "vm0"
    (operating-system-host-name os))

  (test-equal "the account named in the answers is rendered, plus root"
    2
    (length (operating-system-users os)))

  (test-equal "a BIOS bootloader refuses a mount point and uses the disk"
    '("/dev/vdb")
    (bootloader-configuration-targets
     (operating-system-bootloader
      (render-answers
       (list (cons 'schema-version 1)
             (cons 'profile "headless")
             (cons 'storage (storage-answers 'simple "/dev/vdb"))
             (cons 'boot '((bootloader . grub-bios) (target . "/boot/efi")))
             (cons 'users '(((name . "t") (group . "users")))))))))

  (test-assert "root is always present"
    (any (lambda (u) (equal? (user-account-name u) "root"))
         (operating-system-users os)))

  (test-assert "a user password reaches the account"
    (let* ((answers (with-key 'users
                              '(((name . "tester") (group . "users")
                                 (password . "$6$salt$hash")))))
           (users (operating-system-users (render-answers answers))))
      (any (lambda (u) (equal? (user-account-password u) "$6$salt$hash")) users)))

  (test-equal "the file systems are addressed by label"
    '("gradus-root" "GRADUS-ESP")
    (map (lambda (fs)
           (file-system-device->string (file-system-device fs)))
         (operating-system-file-systems os)))

  (test-begin "assembled storage")

  (define nas-answers
    (append answers
            '((assemble ((kind . lvm)
                         (source . "/dev/mapper/cryptdata")
                         (target . "/dev/mapper/vg0"))))))

  (test-equal "an assemble entry becomes a mapped device"
    1
    (length (operating-system-mapped-devices (render-answers nas-answers))))

  (test-equal "the mapped device keeps its source"
    "/dev/mapper/cryptdata"
    (mapped-device-source
     (car (operating-system-mapped-devices (render-answers nas-answers)))))

  (test-assert "mdadm assembly is refused until implemented"
    (catch #t
      (lambda ()
        (render-answers
         (append answers
                 '((assemble ((kind . md)
                              (source . "/dev/disk/by-id/wwn-x")
                              (target . "/dev/md0"))))))
        #f)
      (lambda args #t)))

  (test-assert "a data volume is adopted by its file-system UUID"
    (let* ((nas (with-key 'storage
                          '((mode . simple)
                            (disk . "/dev/vda")
                            (data-volumes ((mount-point . "/srv/data")
                                           (device . "uuid:1454237d-7923-4816-827a-3064eba2b19d")
                                           (type . "ext4"))))))
           (volumes (filter (lambda (fs)
                              (string=? "/srv/data"
                                        (file-system-mount-point fs)))
                            (operating-system-file-systems
                             (render-answers nas)))))
      (and (= 1 (length volumes))
           (uuid? (file-system-device (car volumes))))))

  (test-assert "an encrypted root is declared by its LUKS UUID"
    (let* ((answers (with-key 'storage
                              '((mode . simple) (disk . "/dev/vda")
                                (encryption (mode . luks) (name . "cryptroot")))))
           (device-map '(("GRADUS-ESP" (device . "/dev/vda1") (type . "vfat")
                          (uuid . "34CB-A679"))
                         ("gradus-root" (device . "/dev/mapper/cryptroot")
                          (type . "ext4")
                          (uuid . "1454237d-7923-4816-827a-3064eba2b19d"))
                         ("gradus-crypt" (device . "/dev/vda2")
                          (type . "crypto_LUKS")
                          (uuid . "0b5d5f7a-9d5e-4b7a-9a58-4f0c1c6b0d11"))))
           (mapped (operating-system-mapped-devices
                    (render-answers/devices answers device-map)))
           (root (find (lambda (md) (eq? luks-device-mapping
                                         (mapped-device-type md)))
                       mapped)))
      (and root
           (uuid? (mapped-device-source root))
           (eq? 'luks (uuid-type (mapped-device-source root)))
           (equal? '("cryptroot") (mapped-device-targets root))
           (equal? "/dev/vda2"
                   (assq-ref (assoc-ref device-map "gradus-crypt") 'device)))))

  (test-assert "no mapped device is declared when the LUKS UUID is unknown"
    (let* ((answers (with-key 'storage
                              '((mode . simple) (disk . "/dev/vda")
                                (encryption (mode . luks)))))
           (device-map '(("gradus-crypt" (device . "/dev/vda2")
                          (type . "crypto_LUKS"))))
           (mapped (operating-system-mapped-devices
                    (render-answers/devices answers device-map))))
      ;; A path-sourced LUKS device would produce a declaration GRUB cannot
      ;; unlock, so nothing is declared and the serializer refuses to write it.
      (null? mapped)))

  (test-assert "swap is declared without extra dependencies"
    (let* ((answers (with-key 'storage
                              '((mode . simple) (disk . "/dev/vda")
                                (swap-size . 1024))))
           (swap (car (operating-system-swap-devices
                       (render-answers/devices answers '())))))
      (null? (swap-space-dependencies swap))))

  (test-end "assembled storage")

  (test-begin "sources and proxy")

  (define sourced
    (append (copy-tree answers)
            '((proxy (http . "http://proxy.example.net:3128")
                     (https . "http://proxy.example.net:3128")
                     (no-proxy . ("cache.example.net")))
              (source (substitute-services
                       ((name . "lan-cache")
                        (url . "http://cache.example.net")
                        (kind . builder)))))))

  (define guix-conf
    (service-value
     (find (lambda (service) (eq? (service-kind service) guix-service-type))
           (operating-system-services (render-answers sourced)))))

  (test-equal "the substitute URL reaches the guix service"
    '("http://cache.example.net")
    (guix-configuration-substitute-urls guix-conf))

  (test-assert "the proxy reaches the daemon environment"
    (let ((env (guix-configuration-environment guix-conf)))
      (and (member "http_proxy=http://proxy.example.net:3128" env)
           (member "no_proxy=cache.example.net" env))))

  (test-end "sources and proxy")

  (test-assert "an lvm target declares a volume group"
    (let* ((os (render-answers
                (with-key 'storage '((mode . lvm) (disk . "/dev/vda")
                                     (volume-group . "vg0")
                                     (volumes ((name . "root")
                                               (size . "100%FREE")))))))
           (devices (operating-system-mapped-devices os)))
      (and (= 1 (length devices))
           (equal? '("vg0") (mapped-device-targets (car devices))))))

  (test-equal "an lvm target keeps the root inside the volume group"
    '("/" "/boot/efi")
    (map file-system-mount-point
         (operating-system-file-systems
          (render-answers
           (with-key 'storage '((mode . lvm) (disk . "/dev/vda")
                                (volume-group . "vg0")
                                (volumes ((name . "root")
                                          (size . "100%FREE")))))))))

  (test-assert "storage modes other than simple and lvm are refused"
    (catch #t
      (lambda ()
        (render-answers (with-key 'storage
                                 '((mode . raid) (disk . "/dev/vda"))))
        #f)
      (lambda args #t)))

  (test-assert "bootloader `none' is refused by the renderer for now"
    (catch #t
      (lambda ()
        (render-answers (with-key 'boot '((bootloader . none))))
        #f)
      (lambda args #t)))



  (test-equal "a serial console survives into the bootloader record"
    '((console serial) (serial) 0 115200)
    (let ((config (operating-system-bootloader
                   (render-answers
                    (with-key 'boot
                              '((bootloader . grub-efi) (timeout . 5)
                                (terminal-outputs console serial)
                                (terminal-inputs serial)))))))
      (list (bootloader-configuration-terminal-outputs config)
            (bootloader-configuration-terminal-inputs config)
            (bootloader-configuration-serial-unit config)
            (bootloader-configuration-serial-speed config))))

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
