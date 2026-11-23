#!/usr/bin/env python3
"""Drive a headless Guix VM over its serial console.

Runs the T6 acceptance test: mount the repository share, start the install
inside a tmux session (so the daemon restart cannot kill it), and wait for the
outcome.

Usage:
  drive.py --iso ISO --disk IMG --repo DIR --answers FILE [--log FILE]
"""
import argparse
import os
import pty
import re
import select
import subprocess
import sys
import time

ap = argparse.ArgumentParser()
ap.add_argument("--iso", required=True)
ap.add_argument("--disk", required=True)
ap.add_argument("--repo", required=True)
ap.add_argument("--answers", required=True)
ap.add_argument("--log", default="/tmp/vm-serial.log")
ap.add_argument("--timeout", type=int, default=1800)
ap.add_argument("--memory", default="4096")
args = ap.parse_args()

master, slave = pty.openpty()
cmd = [
    "qemu-system-x86_64", "-enable-kvm", "-m", args.memory, "-smp", "4",
    "-cdrom", args.iso,
    "-drive", "file=%s,if=virtio,format=raw" % args.disk,
    "-virtfs", "local,path=%s,mount_tag=repo,security_model=none" % args.repo,
    "-netdev", "user,id=n0", "-device", "virtio-net-pci,netdev=n0",
    "-display", "none", "-serial", "mon:stdio", "-no-reboot",
]
proc = subprocess.Popen(cmd, stdin=slave, stdout=slave, stderr=slave,
                        preexec_fn=os.setsid, close_fds=True)
os.close(slave)

buffer = bytearray()
log = open(args.log, "wb", buffering=0)


def pump(timeout=1.0):
    r, _, _ = select.select([master], [], [], timeout)
    if not r:
        return b""
    try:
        data = os.read(master, 65536)
    except OSError:
        return b""
    buffer.extend(data)
    log.write(data)
    return data


def wait_for(pattern, timeout):
    deadline = time.time() + timeout
    rx = re.compile(pattern.encode())
    while time.time() < deadline:
        pump(1.0)
        if rx.search(bytes(buffer)):
            return True
    return False


def send(line, settle=1.0):
    os.write(master, line.encode() + b"\n")
    time.sleep(settle)
    pump(0.5)


def main():
    print("waiting for the serial console", flush=True)
    if not wait_for(r"login:|#|gradus-t6", args.timeout):
        print("FAIL: no console prompt", flush=True)
        return 1
    send("mkdir -p /mnt/repo && mount -t 9p -o trans=virtio repo /mnt/repo && echo MOUNT-OK")
    if not wait_for(r"MOUNT-OK", 120):
        print("FAIL: repository share did not mount", flush=True)
        return 1
    send("mkdir -p /mnt/target")
    send("cd /mnt/repo && tmux new -d -s t6 "
         "'GRADUS_RESTART_DAEMON=1 guix shell -q guix guile -- "
         "guile -L . gradus/main.scm --answers %s --root /mnt/target "
         "> /tmp/t6.log 2>&1'" % args.answers)
    print("install started in tmux; polling", flush=True)
    deadline = time.time() + args.timeout
    while time.time() < deadline:
        send("echo T6LOG; tail -c 400 /tmp/t6.log 2>/dev/null | tr '\\n' ' '; echo ENDLOG", settle=0.5)
        pump(4.0)
        text = bytes(buffer).decode("utf-8", "replace")
        segment = text.split("T6LOG")[-1].split("ENDLOG")[0] if "T6LOG" in text else ""
        if "installed; declaration kept" in segment:
            print("PASS: install finished", flush=True)
            print(segment[-400:], flush=True)
            return 0
        if re.search(r"gradus: |error:|cannot prepare|guix system: error", segment):
            print("FAIL: installer reported an error", flush=True)
            print(segment[-800:], flush=True)
            return 1
        time.sleep(10)
    print("TIMEOUT", flush=True)
    return 1


try:
    sys.exit(main())
finally:
    try:
        os.killpg(os.getpgid(proc.pid), 15)
    except OSError:
        pass
