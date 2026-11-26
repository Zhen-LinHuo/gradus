#!/bin/sh
# Drive the wizard of a libvirt domain with synthetic keyboard events.
#
#   DOMAIN=guix-test walk-keys.sh
#
# The domain must run the live medium (make iso) with the wizard visible on
# its VGA console, and the caller needs passwordless sudo over virsh (askpass
# or the libvirt group).  Key events land on the guest's keyboard regardless
# of which console is displayed, but the wizard itself must be on tty1 — the
# live profile sees to that.
#
# One virsh call per key: several keys in one call are deduplicated by the
# hypervisor, so a repeated character would silently vanish.
set -eu
DOMAIN=${DOMAIN:-guix-test}
KEY_DELAY=${KEY_DELAY:-1.2}

k() {
  for key in "$@"; do
    sudo virsh send-key "$DOMAIN" "$key" >/dev/null
    sleep "$KEY_DELAY"
  done
  sleep "$KEY_DELAY"
}

k KEY_ENTER                          # language
k KEY_C                              # locale: accept
k KEY_C                              # storage: accept
k KEY_ENTER                          # plan: use it
k KEY_ENTER                          # source: continue
k KEY_C                              # software: accept
k KEY_C                              # boot: accept
k KEY_C                              # network: accept
k KEY_T KEY_E KEY_S KEY_T KEY_E KEY_R  # users: name
k KEY_ENTER
for _ in 1 2 3 4; do                 # user x2, root x2
  k KEY_P KEY_W KEY_1 KEY_2 KEY_3 KEY_4 KEY_5 KEY_6
  k KEY_ENTER
done
k KEY_ENTER                          # review: install
k KEY_ENTER                          # install: begin
echo "key sequence sent; watch the console for [1/4]…[4/4]"
