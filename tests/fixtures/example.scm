;;; tests/fixtures/example.scm — a complete declaration for dry-run checks.
;;; Copyright © 2026 Zhen-Lin Huo <zhen-lin.huo@gmx.com>
;;;
;;; This file is part of Gradus.

(use-modules (gnu)
             (gnu packages linux)
             (gnu system)
             (gnu system file-systems)
             (gnu bootloader))

(operating-system
  (host-name "gradus-test")
  (timezone "Europe/London")
  (locale "en_GB.utf8")
  (kernel linux-libre)
  (bootloader (bootloader-configuration
                (bootloader grub-efi-bootloader)
                (targets '("/boot/efi"))
                (timeout 5)))
  (file-systems (list (file-system
                        (mount-point "/")
                        (device (file-system-label "gradus-root"))
                        (type "ext4"))
                      (file-system
                        (mount-point "/boot/efi")
                        (device (file-system-label "GRADUS-ESP"))
                        (type "vfat"))))
  (users (list (user-account
                (name "tester")
                (group "users")
                (home-directory "/home/tester")))))
