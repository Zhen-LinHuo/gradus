#!/bin/sh
# Emit an answer file for one cell of the install matrix on stdout.
#
#   gen-answers.sh FS FW   (FS: ext4|btrfs|xfs — FW: bios|uefi)
#
# The root file system is the whole remaining disk, no swap, no encryption:
# the matrix isolates one variable (the file system) at a time.  The user and
# root share the test password; nothing here is a credential worth keeping.
set -eu
FS=${1:?usage: gen-answers.sh FS FW}
FW=${2:?usage: gen-answers.sh FS FW}

case $FS in ext4|btrfs|xfs) ;; *) echo "unknown FS: $FS" >&2; exit 2 ;; esac
case $FW in
  bios) BL=grub-bios ;;
  uefi) BL=grub-efi ;;
  *) echo "unknown FW: $FW" >&2; exit 2 ;;
esac

HASH='$6$gradus$E.OUWKQUGOUbSw62UztnrDUN6cT1f.bpKcGxEbsc0S5GpSVvJQjCQ3TddUtPSXwjHVXODHhe42/v.39bflx47.'

cat <<EOF
((schema-version . 1)
 (profile . "headless")
 (host-name . "gradus-$FS")
 (timezone . "UTC")
 (locale . "en_US.utf8")
 (storage (mode . simple) (disk . "/dev/vda")
          (esp-size . 1024) (swap-size . 0) (root-size . 0)
          (filesystem . "$FS"))
 (boot (bootloader . $BL) (timeout . 5))
 (network (management . dhcp))
 (users ((name . "tester") (group . "users") (password . "$HASH")))
 (root-password . "$HASH"))
EOF
