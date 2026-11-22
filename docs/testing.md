# Acceptance tests

A release is not a release until every test below passes on the release
candidate. Tests are listed in the order they should be run: the cheap ones
catch the embarrassing failures.

## T1 — Stranger test

**Question:** can someone who has never heard of this project install a normal
desktop system with it?

Procedure: a person who has not read the source boots the image, installs a
desktop configuration with a wired network and one user, and logs in.

Pass criteria:

- the installation completes without a shell;
- the login session starts and the network works;
- no page, message or artefact mentions a site, a fleet, a vendor or a proper
  noun outside standard system vocabulary.

This test is also a grep: the installer's user-facing strings and documentation
must contain no private identifiers.

## T2 — Unattended test

**Question:** does an answer file produce exactly the system it declares?

Procedure: `guix-system-installer --answers answers.scm --target DEV --erase`,
with no terminal attached.

Pass criteria:

- exit status 0, no prompt, no hang;
- `/etc/config.scm` is byte-identical to the file printed by `--dry-run`;
- `/etc/guix-installer/provenance.scm` records installer version, contract
  version and Guix revision;
- a second run with the same inputs produces the same declaration.

## T3 — Weaning test

**Question:** is the installer generic, or does it secretly depend on a
particular configuration repository?

Procedure: install from a configuration written by hand for the test, with the
preset directory removed from the image.

Pass criteria: installation succeeds. If it does not, the installer has grown a
dependency on a preset and the dependency is the bug.

## T4 — Preservation test

**Question:** can a machine be reinstalled without destroying its data?

Procedure: install with a second disk carrying an existing file system declared
as a data volume with `erase? = #f`; reinstall the system disk.

Pass criteria:

- the data volume's contents are unchanged (compare checksums before and after);
- the installer never writes to it;
- a device carrying a file system is refused as a system disk unless `--erase`
  is given.

## T5 — Refusal test

**Question:** does it stop instead of guessing?

Cases that must fail with the documented exit status and a readable message:

| Case | Expected |
|:--|:--|
| `--target` points at a mounted device | 3 |
| `--target` is the live medium | 3 |
| configuration references a label absent from the target | 2 |
| unknown key in the answer file | 2 |
| `--erase` without `--target` | 1 |
| UEFI bootloader declared, no ESP among the file systems | 2 |

## Matrix

Every release candidate is installed at least once per row.

| Axis | Values |
|:--|:--|
| Firmware | BIOS, UEFI |
| Storage | single disk, LVM, LUKS, separate `/home` |
| Console | graphical, serial (`console=ttyS0`) |
| Network | DHCP wired, static wired, wireless |
| Memory | 2 GiB (floor), 8 GiB |
| Architecture | x86_64 (v0.1+), aarch64, RISC-V (later) |

Firmware and storage are the axes that break installers; they are never skipped
for a release, even a documentation-only one.

## Evidence

An installation counts as tested only when all of the following are attached to
the release notes:

- the installer transcript (`/var/log/guix-installer.log`);
- the installed `/etc/config.scm`;
- `guix system describe` output from the installed system;
- for T4, checksums of the preserved volume before and after.

Screenshots are welcome but are not evidence: they cannot be diffed.

## Environment

Virtual machines use QEMU with OVMF for UEFI and SeaBIOS for legacy boot, KVM
enabled. At least one installation per release is performed on physical
hardware, because firmware quirks and device enumeration are exactly what a VM
does not reproduce.

Builds and VM runs are CPU- and I/O-heavy; run them on a build host, not on a
machine whose availability matters during the test.
