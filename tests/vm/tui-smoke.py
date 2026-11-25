#!/usr/bin/env python3
"""Drive the TUI from a pty: pages, editing, Esc back, Ctrl-C quit.

The console front-end cannot be covered by the unit tests, and two real bugs
(the full-width operators and the character/integer key comparison) reached
the branch because of it.  Run from the repository root:

    python3 tests/vm/tui-smoke.py

It needs guix, guile and guile-ncurses, which `guix shell` provides.
"""
import os, pty, select, subprocess, sys, time, fcntl, termios, tempfile

LOG = os.path.join(tempfile.gettempdir(), "gradus-tui-smoke.log")
logf = open(LOG, "wb", buffering=0)
cmd = ["guix", "shell", "-q", "guix", "guile", "guile-ncurses", "--",
       "./bin/gradus", "--tui"]
master, slave = pty.openpty()

def ctty():
    os.setsid(); fcntl.ioctl(0, termios.TIOCSCTTY, 0)

env = dict(os.environ); env["TERM"] = "xterm"; env["LANG"] = "C.UTF-8"
proc = subprocess.Popen(cmd, stdin=slave, stdout=slave, stderr=slave,
                        env=env, preexec_fn=ctty, close_fds=True)
os.close(slave)

def pump(seconds=0.4):
    end = time.time() + seconds
    while time.time() < end:
        r, _, _ = select.select([master], [], [], 0.2)
        if r:
            try: d = os.read(master, 4096)
            except OSError: return
            if not d: return
            logf.write(d)

def screen():
    return open(LOG, "rb").read()

def wait_for(needle, timeout=40, nth=1):
    end = time.time() + timeout
    while time.time() < end:
        pump(0.3)
        if screen().count(needle) >= nth:
            return True
    return False

def send(keys, pause=0.35):
    os.write(master, keys); pump(pause)

ok = True
def check(name, cond):
    global ok
    ok = ok and cond
    print(("PASS " if cond else "FAIL ") + name)

check("welcome page", wait_for(b"This installer runs in English"))
send(b"\r")
check("locale page", wait_for(b"Keyboard layout"))
for _ in range(4):                      # keyboard, timezone, locale, ntp
    send(b"\r"); pump(0.6)
check("storage page", wait_for(b"Disks found"))
send(b"\x1b")                           # Esc
check("Esc returns to the previous page", wait_for(b"Keyboard layout", 15, nth=2))
send(b"\x03")                           # Ctrl-C
check("Ctrl-C quits cleanly", wait_for(b"Aborted", 15))
proc.kill()
print("ALL-OK" if ok else "SOME-FAILED")
sys.exit(0 if ok else 1)
