;; The live medium: a Guix System that boots straight into the installer.
;;
;; Build (from the repository root):
;;
;;   make iso
;;
;; The medium auto-logs in as root on tty1–tty6 (mingetty); the serial console
;; (agetty, tty #f in %base-services) accepts a root login without a password.
;; The installer's source tree is embedded; no network is required to start it.
;;
;; Boot behaviour, decided by the root shell profile:
;;
;; - if a 9p share tagged `repo' is mounted and contains `answers.scm',
;;   the installer runs unattended from that answer file (this is what the
;;   `make vm-install' matrix uses);
;; - otherwise the wizard starts on the console the operator is looking at.

(use-modules (gnu)
             (gnu services)
             (srfi srfi-1)
             (gnu services base)
             (gnu services networking)
             (gnu packages)
             (gnu packages linux))

(define %live-profile
  (plain-file "live-profile"
              "#!/bin/sh
export TERM=linux
export GUILE_LOAD_PATH=/run/current-system/profile/share/guile/site/3.0${GUILE_LOAD_PATH:+:$GUILE_LOAD_PATH}
mkdir -p /tmp/gradus-src && tar xzf /etc/gradus-src.tar.gz -C /tmp/gradus-src
cd /tmp/gradus-src
mkdir -p /repo && mount -t 9p -o trans=virtio,ro repo /repo 2>/dev/null
if mountpoint -q /repo 2>/dev/null && [ -f /repo/answers.scm ]; then
  guile -L . -s gradus/script.scm --answers /repo/answers.scm --root /mnt/target
else
  guile -L . -s gradus/script.scm --tui
fi
echo \"the installer exited with $?\"
sleep 15
"))

(operating-system
  (host-name "gradus-live")
  (timezone "UTC")
  (locale "en_US.utf8")
  (bootloader (bootloader-configuration
               (bootloader grub-bootloader)
               (targets '("/dev/sda"))
               (terminal-outputs '(console serial))
               (serial-unit 0)
               (serial-speed 115200)))
  (file-systems (cons (file-system
                        (mount-point "/")
                        (device "/dev/sda1")
                        (type "ext4"))
                      %base-file-systems))
  (kernel-arguments '("console=ttyS0" "quiet"))
  (packages (append (map specification->package
                         '("parted" "cryptsetup" "dosfstools" "e2fsprogs"
                           "util-linux" "tmux" "guile" "guile-ncurses"
                           "btrfs-progs" "xfsprogs"))
                    %base-packages))
  (services
   (append
    (list (extra-special-file "/etc/gradus-src.tar.gz"
                              (local-file "../.build/gradus-src.tar.gz"))
          (extra-special-file "/root/.bash_profile" %live-profile)
          (service dhcpcd-service-type))
    (modify-services %base-services
            (mingetty-service-type config =>
                               (mingetty-configuration
                                (inherit config)
                                (auto-login "root"))))
)))
