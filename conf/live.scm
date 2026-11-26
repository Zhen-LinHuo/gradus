;; The live medium: a Guix System that boots straight into the installer.
;;
;; Build (from the repository root):
;;
;;   make iso                          # interactive medium
;;   GRADUS_ANSWERS=path make iso      # medium with the answers baked in
;;
;; Every console auto-logs in as root (mingetty on tty1–tty6, agetty on the
;; serial console) and runs /root/.bash_profile, which picks an entry point:
;;
;; - if a 9p share tagged `repo' carries answers.scm, or the medium was
;;   built with GRADUS_ANSWERS (both are read, 9p first), and the login
;;   happened on the serial console, the installer runs unattended;
;; - otherwise the wizard starts on the console the operator is looking at.
;;
;; Diagnostics go to /dev/console (the kernel console, ttyS0 here) so they
;; are captured by the serial log whatever console the login happened on.

(use-modules (gnu)
             (gnu services)
             (srfi srfi-1)
             (gnu services base)
             (gnu services networking)
             (gnu packages)
             (gnu packages linux))

;; Answers baked into the medium at build time; absent for the interactive one.
(define %baked-answers
  (let ((path (getenv "GRADUS_ANSWERS")))
    (if path
        (list (extra-special-file "/etc/answers.scm" (local-file path)))
        '())))

(define %live-profile
  (plain-file "live-profile"
              "#!/bin/sh
export TERM=linux
export GUILE_LOAD_PATH=/run/current-system/profile/share/guile/site/3.0${GUILE_LOAD_PATH:+:$GUILE_LOAD_PATH}
CONS=$(tty 2>/dev/null || echo unknown)
echo gradus-login-on-$CONS >/dev/console
D=/tmp/gradus-src-$(echo $CONS | tr -c a-zA-Z0-9 _)
mkdir -p $D && tar xzf /etc/gradus-src.tar.gz -C $D
cd $D
A=
mkdir -p /repo
if mount -t 9p -o trans=virtio,ro repo /repo >/tmp/gradus-9p.out 2>&1 && test -f /repo/answers.scm; then
  A=/repo/answers.scm
  echo gradus-answers-from-9p >/dev/console
elif test -f /etc/answers.scm; then
  A=/etc/answers.scm
  echo gradus-answers-baked >/dev/console
else
  echo gradus-no-answers-found >/dev/console
fi
if test -n \"$A\" && test \"$CONS\" = /dev/ttyS0; then
  guile -L . -s gradus/script.scm --answers $A --root /mnt/target
else
  test -n \"$A\" && echo gradus-answers-ignored-not-serial >/dev/console
  guile -L . -s gradus/script.scm --tui
fi
echo gradus-installer-exit-$? >/dev/console
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
    %baked-answers
    (modify-services %base-services
            (mingetty-service-type config =>
                               (mingetty-configuration
                                (inherit config)
                                (auto-login "root")))
            (agetty-service-type config =>
                               (agetty-configuration
                                (inherit config)
                                (auto-login "root")))))))
