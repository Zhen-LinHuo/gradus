;;; tests/fixtures/answers.scm — an answer file for dry-run checks.
;;; Copyright © 2026 Zhen-Lin Huo <zhen-lin.huo@gmx.com>
;;;
;;; This file is part of Gradus.

((schema-version . 1)
 (profile . "headless")
 (host-name . "gradus-vm")
 (timezone . "Europe/London")
 (locale . "en_GB.utf8")
 (storage (mode . simple) (disk . "/dev/vda"))
 (boot (bootloader . grub-efi) (timeout . 5))
 (network (management . dhcp))
 (users ((name . "tester") (group . "users"))))
