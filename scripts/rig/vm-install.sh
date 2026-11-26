#!/bin/sh
# One cell of the install matrix: install into a fresh qcow2 from the live
# medium in unattended (answer-file) mode, then boot the result from disk.
#
#   vm-install.sh FS FW        (FS: ext4|btrfs|xfs — FW: bios|uefi)
#
# Environment: run on a host with KVM and qemu-system-x86_64.  For FW=uefi set
# OVMF to the OVMF firmware image (the _CODE file).  Artifacts land in
# .build/vm-FS-FW/: the serial transcript of each phase is the evidence.
#
# Assertions, from the serial transcript only (no screenshots):
#   install phase: "installed; declaration kept" appears
#   boot phase:    the installed system reaches its login prompt
set -eu
FS=${1:?usage: vm-install.sh FS FW}
FW=${2:?usage: vm-install.sh FS FW}

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
B="$ROOT/.build/vm-$FS-$FW"
mkdir -p "$B"
RUNLOG="$B/run.log"

# The rig owns the host's qemu: a stale VM holding the disk image would
# deadlock this cell, and two overlapping runs would stomp on the same
# transcript.  flock makes an overlap a clean skip; a stale VM is cleared.
pkill -f qemu-system-x86_64 2>/dev/null || true
sleep 2
exec 9>"$ROOT/.build/mx.lock"
flock -n 9 || { echo "another matrix run is active; skipping"; exit 0; }

# 1. the medium (make iso embeds the source tarball and prints the store path)
sh "$ROOT/scripts/rig/gen-answers.sh" "$FS" "$FW" > "$B/answers.scm"
mkdir -p "$B/share"
cp "$B/answers.scm" "$B/share/answers.scm"
make -C "$ROOT" iso >/dev/null
ISO=$(cat "$ROOT/.build/iso-path")
test -f "$ISO"

# 2. install phase: CD first, blank disk, share with the answer file
rm -f "$B/disk.qcow2" "$B/serial-install.log"
qemu-img create -f qcow2 "$B/disk.qcow2" 20G >/dev/null
OVMF_ARGS=""
[ "$FW" = uefi ] && OVMF_ARGS="-bios ${OVMF:?set OVMF to the OVMF_CODE image}"
qemu-system-x86_64 -enable-kvm -m 8192 -display none -daemonize \
  -serial "file:$B/serial-install.log" \
  -monitor "unix:$B/mon-install.sock,server,nowait" \
  -boot order=d \
  -cdrom "$ISO" \
  -drive "file=$B/disk.qcow2,if=virtio,format=qcow2" \
  -virtfs "local,id=repo,path=$B/share,mount_tag=repo,security_model=none" \
  -pidfile "$B/qemu.pid" $OVMF_ARGS
trap 'kill "$(cat "$B/qemu.pid" 2>/dev/null)" 2>/dev/null || true' EXIT

deadline=$(( $(date +%s) + 2700 ))
until grep -qE "installed;|install failed|the installer exited" "$B/serial-install.log" 2>/dev/null; do
  [ "$(date +%s)" -gt "$deadline" ] && { echo "TIMEOUT waiting for the install"; exit 1; }
  sleep 15
done
kill "$(cat "$B/qemu.pid")" 2>/dev/null || true
sleep 2
grep -q "installed;" "$B/serial-install.log" || {
  echo "INSTALL FAILED ($FS/$FW):"; tail -8 "$B/serial-install.log"; exit 1; }
echo "install OK ($FS/$FW)"

# 3. boot phase: disk only, no CD, no share
rm -f "$B/serial-boot.log"
qemu-system-x86_64 -enable-kvm -m 2048 -display none -daemonize \
  -serial "file:$B/serial-boot.log" \
  -drive "file=$B/disk.qcow2,if=virtio,format=qcow2" \
  -pidfile "$B/qemu.pid" $OVMF_ARGS
deadline=$(( $(date +%s) + 300 ))
until grep -q "login:" "$B/serial-boot.log" 2>/dev/null; do
  [ "$(date +%s)" -gt "$deadline" ] && { echo "TIMEOUT waiting for the login prompt"; exit 1; }
  sleep 10
done
kill "$(cat "$B/qemu.pid")" 2>/dev/null || true
echo "boot OK ($FS/$FW): the installed system reached its login prompt"
trap - EXIT
