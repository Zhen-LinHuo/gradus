#!/usr/bin/env python3
"""Walk the console wizard under a pty and assert the page sequence.

The wizard runs in validation mode (--tui --dry-run): every page renders,
every check runs, and the final step prints the plan without writing
anything, so the walk exercises the real interface on the real host with no
risk to any disk.

    pty-walk.py            # from the repository root

Exit 0 when every page is reached in order; on the first mismatch the screen
seen so far is printed to stderr.
"""
import os
import pty
import select
import signal
import sys
import time

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# (markers that say this page is up, keys to send when it is)
STEPS = [
    (["Gradus"], "\r"),                       # language: English is the default
    (["Keyboard layout"], "c"),               # locale form: accept
    (["Root filesystem", "Target disk"], "c"),  # storage form: accept defaults
    (["Planned layout"], "\r"),               # plan: use it
    (["Substitute servers"], "\r"),           # source: accept the list
    (["HTTP proxy"], "\r"),                   # source: no proxy; the page continues
    (["Software"], "c"),                   # software: accept
    (["Boot loader"], "c"),                   # boot: accept
    (["Host name"], "c"),                     # network: accept
    (["User name"], "\r"),                    # users: accept the default name
    (["password"], "pw123456\r" * 4),         # user x2, root x2
    (["What next?"], "\r"),                   # review: install
    (["Press Enter to begin"], "\r"),         # install: begin
    (["dry run: nothing was written"], None),  # validation mode did its work
]


def spawn():
    pid, fd = pty.fork()
    if pid == 0:
        os.chdir(REPO)
        os.environ["TERM"] = "linux"
        os.execvp("guix", ["guix", "shell", "-q", "guix", "guile",
                           "guile-ncurses", "--", "guile", "-L", ".", "-s",
                           "gradus/script.scm", "--tui", "--dry-run"])
    return pid, fd


def read_until(fd, markers, timeout):
    """Read until one of MARKERS appears or TIMEOUT passes.  Returns
    (matched marker or None, buffer)."""
    end = time.time() + timeout
    buf = b""
    while time.time() < end:
        ready, _, _ = select.select([fd], [], [], 0.5)
        if ready:
            try:
                data = os.read(fd, 65536)
            except OSError:
                break
            if not data:
                break
            buf += data
            for m in markers:
                if m.encode() in buf:
                    return m, buf
    return None, buf


def main():
    pid, fd = spawn()
    for i, (markers, keys) in enumerate(STEPS):
        hit, buf = read_until(fd, markers, 90 if i == 0 else 45)
        if hit is None:
            sys.stderr.write(f"step {i}: none of {markers} appeared; saw:\n")
            sys.stderr.write(buf.decode("utf-8", "replace") + "\n")
            os.kill(pid, signal.SIGKILL)
            return 1
        if keys:
            for ch in keys:
                os.write(fd, ch.encode())
                time.sleep(0.05)
    os.waitpid(pid, 0)
    print("walkthrough OK: all pages reached, validation mode, nothing written")
    return 0


if __name__ == "__main__":
    sys.exit(main())
