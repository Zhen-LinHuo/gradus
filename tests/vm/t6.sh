#!/bin/sh
# T6: install through the proxy, inside tmux so a daemon restart cannot kill it.
#
# The install runs under `guix repl' rather than a `guix shell' bootstrap: the
# live image already has guix, and a bootstrap would fetch over the direct
# route before the proxy is applied, which would prove nothing about T6.
cd /mnt/repo || exit 1
{
  echo '(use-modules (gradus script))'
  echo '(exit (main (list "gradus" "--answers" "/mnt/repo/tests/fixtures/answers-t6.scm" "--root" "/mnt/target")))'
} | GRADUS_RESTART_DAEMON=1 guix repl -L /mnt/repo > /tmp/t6.log 2>&1
echo "exit=$?" >> /tmp/t6.log
