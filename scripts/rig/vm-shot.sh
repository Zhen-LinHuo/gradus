#!/bin/sh
# Take a PNG screenshot of a libvirt domain's console (the wizard draws on
# tty1, so this is what an operator watching virt-manager would see).
#
#   DOMAIN=guix-test vm-shot.sh [out.png]
set -eu
DOMAIN=${DOMAIN:?usage: DOMAIN=name vm-shot.sh [out.png]}
OUT=${1:-${DOMAIN}.png}
sudo virsh screenshot "$DOMAIN" "$OUT" >/dev/null
echo "$OUT"
