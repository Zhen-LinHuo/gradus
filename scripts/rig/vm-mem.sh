#!/bin/sh
# Raise a libvirt domain's memory (the live installer's /gnu/store lives in
# RAM; a small domain runs out while downloading substitutes).
#
#   DOMAIN=guix-test MIB=8192 vm-mem.sh
set -eu
DOMAIN=${DOMAIN:?usage: DOMAIN=name MIB=8192 vm-mem.sh}
MIB=${MIB:?usage: DOMAIN=name MIB=8192 vm-mem.sh}
KIB=$(( MIB * 1024 ))
XML="/tmp/$DOMAIN.xml"

sudo virsh destroy "$DOMAIN" 2>/dev/null || true
sudo virsh dumpxml "$DOMAIN" > "$XML"
sed -i -E "s|<memory unit='KiB'>[0-9]+</memory>|<memory unit='KiB'>$KIB</memory>|" "$XML"
sed -i -E "s|<currentMemory unit='KiB'>[0-9]+</currentMemory>|<currentMemory unit='KiB'>$KIB</currentMemory>|" "$XML"
sudo virsh define "$XML" | tail -1
sudo virsh start "$DOMAIN" | tail -1
