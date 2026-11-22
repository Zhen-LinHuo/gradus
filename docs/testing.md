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

Procedure: install with `http_proxy`/`https_proxy` set to a proxy that is the
only route out, and with a `no_proxy` entry covering the local substitute cache.

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
[`tests/vm/README.md`](../tests/vm/README.md).

Virtual machines use QEMU with OVMF for UEFI and SeaBIOS for legacy boot, KVM
enabled. At least one installation per release is performed on physical
hardware, because firmware quirks and device enumeration are exactly what a VM
does not reproduce.

Builds and VM runs are CPU- and I/O-heavy. They belong on a dedicated build host
with KVM enabled, at least eight virtual CPUs and enough memory to hold two
Guix System builds and a VM at once (16 GiB is a practical floor). Which host
that is, in any given setup, is a matter for the operator's local notes; this
tree does not name private machines.
