#!/bin/sh
# tests/vm/loop-test.sh — exercise configuration mode against a loop-backed
# target.  This is the scripted form of the runbook in tests/vm/README.md; the
# QEMU/serial variant is still manual.
#
# Usage: as root (or through sudo), with GRADUS_REPO pointing at a checkout:
#   GRADUS_REPO=/home/me/src/gradus tests/vm/loop-test.sh
#
# Checks performed:
#   T5 (partial)  an unmounted, unlabelled target is refused with status 3
#   T2            a full install with byte-identical artefacts
#
# No network isolation yet: substitutes are fetched from the configured servers.

set -eu

: "${GRADUS_REPO:?set GRADUS_REPO to the checkout directory}"
LABEL_ROOT=${LABEL_ROOT:-gradus-root}
LABEL_ESP=${LABEL_ESP:-GRADUS-ESP}

run_gradus() {
  (cd "$GRADUS_REPO" && \
   guix shell -q guix guile -- guile -L . gradus/main.scm "$@")
}

WORK=$(mktemp -d /var/tmp/gradus-test.XXXXXX)
ROOT=/mnt/gradus-test
LOOP=
cleanup() {
  set +e
  umount "$ROOT/boot/efi" "$ROOT" 2>/dev/null
  [ -n "$LOOP" ] && losetup -d "$LOOP"
  rm -rf "$WORK" "$ROOT" /mnt/gradus-empty
}
trap cleanup EXIT INT TERM

echo "== preparation"
mkdir -p "$ROOT" /mnt/gradus-empty
truncate -s 20G "$WORK/disk.img"
LOOP=$(losetup --find --show -P "$WORK/disk.img")
parted -s "$LOOP" mklabel gpt \
  mkpart ESP fat32 1MiB 513MiB set 1 esp on \
  mkpart root ext4 513MiB 100%
partprobe "$LOOP"
udevadm settle

echo "== T5: refusal before the target exists"
set +e
run_gradus --config "$GRADUS_REPO/tests/fixtures/example.scm" \
  --root /mnt/gradus-empty
status=$?
set -e
if [ "$status" -ne 3 ]; then
  echo "FAIL: expected exit 3, got $status" >&2
  exit 1
fi
echo "T5 passed (exit 3, nothing written)"

echo "== preparation of the target"
mkfs.vfat -n "$LABEL_ESP" "${LOOP}p1" >/dev/null
mkfs.ext4 -q -F -L "$LABEL_ROOT" "${LOOP}p2"

echo "== T2: installation"
run_gradus --config "$GRADUS_REPO/tests/fixtures/example.scm" \
  --root "$ROOT"

echo "== T2 verification"
test -f "$ROOT/etc/config.scm"
grep -q "installer-version" "$ROOT/etc/gradus/provenance.scm"
grep -q "mode" "$ROOT/etc/gradus/answers.scm"
if cmp -s "$GRADUS_REPO/tests/fixtures/example.scm" "$ROOT/etc/config.scm"; then
  echo "T2 passed: declaration kept byte-identical"
else
  echo "FAIL: /etc/config.scm differs from the source declaration" >&2
  exit 1
fi
