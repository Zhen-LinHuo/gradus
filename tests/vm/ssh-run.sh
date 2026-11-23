#!/bin/sh
# tests/vm/ssh-run.sh — drive the acceptance install through SSH.
#
# The guest runs the install inside tmux, so restarting guix-daemon (which the
# proxy path does) cannot take the session down.  The serial console stays as a
# fallback for diagnosis.
#
# Usage: ssh-run.sh PORT
set -eu

PORT=${1:-2223}
SSH="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -p $PORT"

$SSH root@localhost '
  mkdir -p /mnt/repo /mnt/target &&
  mountpoint -q /mnt/repo || mount -t 9p -o trans=virtio repo /mnt/repo
  tmux kill-session -t t6 2>/dev/null || true
  tmux new -d -s t6 sh /mnt/repo/tests/vm/t6.sh
  echo STARTED'

for i in $(seq 1 180); do
  sleep 10
  STATE=$($SSH root@localhost 'tail -c 400 /tmp/t6.log 2>/dev/null | tr "\n" " "' 2>/dev/null || true)
  case "$STATE" in
    *"installed; declaration kept"*) echo "PASS: $STATE"; exit 0 ;;
    *"exit="*) echo "FAIL: $STATE"; exit 1 ;;
  esac
done

echo "TIMEOUT"
exit 1
