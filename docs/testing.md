# Acceptance tests

A release is not a release until every test below passes on the release
candidate. Tests are listed in the order they should be run: the cheap ones
catch the embarrassing failures.

## T1 — Stranger test

**Question:** can someone who has never heard of this project install a normal
desktop system with it?

T1 depends on the interactive pages and cannot be fully performed until the
milestone that ships them. It is therefore staged:

- **T1-u (from v0.1):** an operator who has read only this repository's README
  and `docs/contract.md` installs a system unattended from a configuration they
  wrote themselves, using `--config`, and finds the installed declaration where
  the contract says it is. No private identifiers anywhere in the output.
- **T1-i (from the pages milestone):** the full stranger walk-through of the
  interactive installer, as described below.

Procedure (T1-i): a person who has not read the source boots the image,
installs a desktop configuration with a wired network and one user, and logs
in.

Pass criteria:

- the installation completes without a shell;
- the login session starts and the network works;
- no page, message or artefact mentions a site, a fleet, a vendor or a proper
  noun outside standard system vocabulary.

This test is also a grep: the installer's user-facing strings and documentation
must contain no private identifiers.

## T2 — Unattended test

**Question:** does an answer file produce exactly the system it declares?

Procedure: `gradus --answers answers.scm --target DEV --erase`,
with no terminal attached.

Pass criteria:

- exit status 0, no prompt, no hang;
- `/etc/config.scm` is byte-identical to the file printed by `--dry-run`;
- `/etc/gradus/provenance.scm` records installer version, contract
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

## T6 — Proxy test

**Question:** can an installation complete on a network with no direct egress,
and does the installed system keep using the proxy?

**Where it must run.** In the Guix System live environment, not on a foreign
distribution.  Applying the proxy to substitutes means restarting the Guix
daemon, and the installer does that through Shepherd (`herd`), which only exists
on Guix System.  A host running Guix on top of another distribution cannot
exercise this path; the VM runbook in `tests/vm/` is the place for it.

**Status:** not yet run end to end.  The proxy environment itself reaches the
Guix daemon in a live system; completing the installation inside the test VM is
blocked by the rig, not by the installer.

**Rig notes.** Three things cost time and should be settled before a run:

- A serial console backed by a file gives the guest's login shell EOF, so the
  shell exits and typed input lands on the login prompt.  Use a pty and keep it
  open for the life of the VM.
- The VM must hold a DHCP lease before `hostfwd` to port 22 can work; a refused
  connection usually means no address, not a missing sshd.
- Before booting an image that is supposed to act on its own, confirm the
  service or special file is present in the *built system* — a declaration that
  builds is not proof that the activation ran.

Procedure: install with `http_proxy`/`https_proxy` set to a proxy that is the
only route out, and with a `no_proxy` entry covering the local substitute cache.
A logging CONNECT proxy is enough to prove the route: the installation must
appear in its log.

Pass criteria:

- channels and substitutes are fetched through the proxy;
- the local cache is contacted **directly** (its access log shows the
  installation, the proxy's log does not);
- after the first boot, `guix build` on the installed system still reaches the
  network without the operator exporting variables by hand;
- proxy credentials do not appear in the transcript or in
  `/etc/gradus/provenance.scm`.

## T7 — Self-hosted cache test

**Question:** does a substitute service on the local network work during the
installation and afterwards?

Procedure: run `guix publish` on a second machine; declare it as a `builder`
with its signing key; install with external substitutes disabled.

Pass criteria:

- the installation fetches store items from the cache (proof: the cache's access
  log, not the installer's claim);
- the key is authorised in the live environment **and** present in the target's
  `guix-configuration`;
- after the first boot, `guix build` uses the cache without further setup;
- removing the key from the answer file makes the installation fail loudly
  rather than fall back to an unsigned source.

## T8 — No bootloader test

**Question:** is "do not install a bootloader" a real option rather than a
refusal?

Procedure: install onto a disk that already carries a bootloader, with
`bootloader = none`.

Pass criteria:

- the installation completes;
- the existing bootloader is byte-identical afterwards (compare the relevant
  partition or checksum);
- the review stage warned that the machine will not boot unaided;
- the resulting `/etc/config.scm` contains no `bootloader` field.

## Matrix

Every release candidate is installed at least once per row.

| Axis | Values |
|:--|:--|
| Firmware | BIOS, UEFI |
| Bootloader | installed, `none` |
| Storage | single disk, LVM, LUKS, separate `/home` |
| Console | graphical, serial (`console=ttyS0`) |
| Network | DHCP wired, static wired, wireless |
| Egress | direct, HTTP proxy, proxy with a `no_proxy` exception |
| Substitutes | official only, LAN mirror, LAN builder (`guix publish`) |
| Memory | 2 GiB (floor), 8 GiB |
| Architecture | x86_64 (v0.1+), aarch64, RISC-V (later) |

Firmware and storage are the axes that break installers; they are never skipped
for a release, even a documentation-only one.

## T9 — Encrypted root boots

**Question:** after an encrypted install, does the machine actually come up?

An encrypted root has two failure modes that no unit test can see: GRUB only
learns the passphrase when the mapped device's source is a LUKS **UUID** (a
device path is dropped with a warning), and the bootloader only speaks on the
serial line when the terminals are configured. Either mistake produces a
machine that installs perfectly and then does not start.

Procedure: install unattended with `(encryption (mode . luks))` and
`swap-size 0` (a separate swap partition would sit in plaintext outside the
container), then boot the disk with no installation medium attached.

Pass criteria:

- GRUB asks for the passphrase on the configured console;
- the kernel starts and the root is mounted from `/dev/mapper/<name>`;
- the account created in the answers can log in;
- `/etc/gradus/provenance.scm` names `mode answers` and the Guix that built it.

Last run (BIOS, LUKS1, serial console):

```
Enter passphrase for hd0,gpt2 (a0a35a9e-…):
NAME          FSTYPE      LABEL TYPE
└─vda2        crypto_LUKS       part
  └─cryptroot                   crypt
findmnt -no SOURCE /   →  /dev/mapper/cryptroot
```

Two rig notes, learned the hard way: a passphrase written to the console in one
go is swallowed (type it a character at a time), and `cryptsetup
open --test-passphrase` against the disk is the quickest way to separate "wrong
passphrase" from "input not reaching GRUB".

## T10 — The console front-end installs, end to end

**Claim:** an operator who never opens a shell can install the system from the
console front-end, and the installed system boots and accepts its login.

**Procedure.** The live medium is booted in a VM with the wizard on the virtual
console; the walkthrough below was driven with `virsh send-key` (one keycode per
call -- consecutive identical keys in a single call are coalesced by the guest,
which silently corrupted names). Defaults were accepted everywhere except the
account.

1. Language page: Enter.
2. Localisation, storage, software, boot, network: `c` accepts each form.
3. Storage: the plan screen is accepted; the filesystem was ext4 (btrfs was
   verified separately, T9's medium had btrfs-progs).
4. Users: name and passwords typed on the forms.
5. Review: Enter on install; the log shows the four stages and ends with
   `[4/4] installed; declaration kept at /mnt/target/etc/config.scm`.

**Evidence.** After ejecting the medium the VM boots from disk to
`gradus login:` (the host name comes from the answers), and `root` with the
password entered in step 4 reaches `root@gradus ~#`.

## Evidence

An installation counts as tested only when all of the following are attached to
the release notes:

- the installer transcript (`/var/log/gradus-install.log`);
- the installed `/etc/config.scm`;
- `guix system describe` output from the installed system;
- for T4, checksums of the preserved volume before and after.

Screenshots are welcome but are not evidence: they cannot be diffed.

## Environment

The runbook for the virtual-machine procedure is
[`tests/vm/README.md`](https://github.com/Zhen-LinHuo/gradus/blob/main/tests/vm/README.md).

Virtual machines use QEMU with OVMF for UEFI and SeaBIOS for legacy boot, KVM
enabled. At least one installation per release is performed on physical
hardware, because firmware quirks and device enumeration are exactly what a VM
does not reproduce.

Builds and VM runs are CPU- and I/O-heavy. They belong on a dedicated build host
with KVM enabled, at least eight virtual CPUs and enough memory to hold two
Guix System builds and a VM at once (16 GiB is a practical floor). Which host
that is, in any given setup, is a matter for the operator's local notes; this
tree does not name private machines.
