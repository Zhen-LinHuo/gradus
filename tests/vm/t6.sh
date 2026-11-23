#!/bin/sh
# T6: install through the proxy, inside tmux so a daemon restart cannot kill it.
cd /mnt/repo || exit 1
GRADUS_RESTART_DAEMON=1 guix shell -q guix guile -- \
  guile -L . gradus/main.scm \
  --answers /mnt/repo/tests/fixtures/answers-t6.scm \
  --root /mnt/target > /tmp/t6.log 2>&1
echo "exit=$?" >> /tmp/t6.log
