#!/bin/sh
# tests/vm/clean.sh — return the guest to a state where a run can start.
# Sent over SSH on stdin, so it must not assume anything about the caller.

pkill -f 'guix repl' 2>/dev/null
pkill -f 't6.sh' 2>/dev/null
sleep 1

for d in $(mount | awk '/\/mnt\/target/ {print $3}' | sort -r); do
  umount -f -l "$d" 2>/dev/null
done
sleep 1

wipefs -a /dev/vda >/dev/null 2>&1
printf 'mountpoints: '
lsblk -no MOUNTPOINT /dev/vda | tr '\n' ' '
echo
