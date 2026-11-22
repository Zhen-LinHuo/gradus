# tests/vm — installation tests in a virtual machine

Status: the procedure below was executed by hand and is what validated the
v0.1 acceptance run. A scripted version (serial-console automation) is planned
but does not exist yet; until it does, treat this file as a runbook, not as an
executable test.

## Requirements

- a build host with KVM (the QEMU binary may live in the host distribution)
- a Guix System install ISO for the release under test
- the repository checked out on the host, to be shared into the VM

## Procedure used for v0.1

1. **Prepare a target.** A loop-backed image was used instead of a VM disk, so
   that the same steps also serve the refusal test:

   ```sh
   truncate -s 20G /var/lib/gradus-test/disk.img
   losetup --find --show -P /var/lib/gradus-test/disk.img
   parted -s /dev/loop0 mklabel gpt \
     mkpart ESP fat32 1MiB 513MiB set 1 esp on \
     mkpart root ext4 513MiB 100%
   mkfs.vfat -n GRADUS-ESP /dev/loop0p1
   mkfs.ext4 -L gradus-root /dev/loop0p2
   ```

2. **Refusal check (T5, partially).** Run `gradus --config
   tests/fixtures/example.scm --root /mnt/gradus-empty` against an empty
   directory: the mount of `LABEL=gradus-root` must fail and the exit status
   must be 3, with nothing written.

3. **Boot the ISO with the repository shared in:**

   ```sh
   qemu-system-x86_64 -enable-kvm -m 4096 -nographic \
     -cdrom guix-system-install-1.5.0.x86_64-linux.iso \
     -drive file=target.qcow2,if=virtio \
     -virtfs local,path=$HOME/src/gradus,mount_tag=repo,security_model=none
   ```

   The live system runs as root, which is what the installer requires.

4. **Inside the live system**, mount the share, prepare the target if needed,
   and run the installer:

   ```sh
   mount -t 9p -o trans=virtio repo /mnt/repo
   gradus --config /mnt/repo/tests/fixtures/example.scm --root /mnt/target
   ```

5. **Verify the artefacts** (T2): `/etc/config.scm` byte-identical to the
   fixture, `/etc/gradus/provenance.scm` recording the installer version and
   the Guix revision, `/etc/gradus/answers.scm` naming the mode.

6. **Clean up**: unmount, detach the loop device, remove the image and every
   temporary credential file created for the run.

## Notes learned the hard way

- `guix shell --pure` removes the host PATH; the installer shells out to
  `mount`, so run it without `--pure` or restore `/usr/sbin`.
- After `losetup -P`, the partition labels are not visible to `mount LABEL=`
  until `partprobe` and `udevadm settle` have run.
- `guix system init` downloads the full system closure; budget ten to thirty
  minutes depending on the network.

## What the scripted version must add

- unattended boot (serial console + automated input, or a pre-seeded answer
  file fetched over the network);
- a hard timeout and a transcript capture for every run;
- the matrix rows from `docs/testing.md` (BIOS/UEFI, LVM, LUKS, serial).
