# Gradus

## A generic installer for GNU Guix System

[![License](https://img.shields.io/badge/license-AGPL--3.0--or--later-blue.svg)](LICENSE)
[![GitHub stars](https://img.shields.io/github/stars/Zhen-LinHuo/gradus)](https://github.com/Zhen-LinHuo/gradus)
[![GitHub last commit](https://img.shields.io/github/last-commit/Zhen-LinHuo/gradus)](https://github.com/Zhen-LinHuo/gradus)

An unofficial project, not affiliated with or endorsed by the GNU Guix project.

You get the same thing every other distribution's installer gives you — language,
disk layout, bootloader, software selection, users — plus one thing they cannot
give you: **the installer's output is a `config.scm`**, not an opaque system
state. The machine is installed *from* that file, and the file is kept on the
machine afterwards.

> **Status: working, early.** An installation runs end to end on both
> firmwares — BIOS (GRUB on the disk) and UEFI (GRUB in the ESP, boot entry in
> NVRAM) — with partitioning, users and passwords, substitutes, and the
> artefacts the contract promises.  A console wizard drives it; the graphical
> and web front-ends do not exist yet.  Options the software does not implement
> are marked *(planned)* below and in `gradus --help`.

## Running from a checkout

Gradus is not packaged yet; you run it straight from a clone. You need Guix
(`guix shell` drives everything, and the target is installed with
`guix system init`).

```sh
git clone https://github.com/Zhen-LinHuo/gradus && cd gradus

# The interactive installer (needs guile-ncurses; in a live environment you are
# already root, on a foreign distribution use sudo for the write to the disk):
guix shell -q guix guile guile-ncurses -- ./bin/gradus --tui

# See what an install would do, touching nothing:
guix shell -q guix guile -- ./bin/gradus \
    --config my-config.scm --root /mnt/target --dry-run

# Install (the target's file systems must already exist, with the labels or
# UUIDs your config names; --config mode does not partition):
guix shell -q guix guile -- sudo ./bin/gradus \
    --config my-config.scm --root /mnt/target

# Or let an answer file describe the target, including its disk layout:
guix shell -q guix guile -- sudo ./bin/gradus \
    --answers my-answers.scm --root /mnt/target
```

`bin/gradus` is a two-line shell launcher; nothing needs to know how Guile
takes its arguments.

After a successful run, the target carries `/etc/config.scm` (the declaration
that was installed) and `/etc/gradus/provenance.scm` (which installer, contract
and Guix revision produced it).

## The name

*Gradus* is Latin for a step: the step at a threshold, and also a degree — one of
the steps of a course. An installer is exactly that. It establishes the ground
the system stands on, and then it is finished.

The companion a running system needs — the manager that keeps services, storage
and updates in order — is **Magister**: the rank reached at the top of the
*gradus*. In Latin, *gradus magistri* is the degree of master. One ascent with
two ends: the step, and the household.

## Why another installer

The official Guix installer is a text-based wizard. It is a good wizard, but it
only covers a fraction of the system configuration surface: it cannot enter a
substitute server URL or import its signing key, it asks nothing about boot
menu entries or serial consoles, and its software selection is limited to a
desktop environment plus a few service checkboxes.

This project fills that gap **without** coupling the installer to any fleet,
role or vendor. It is a generic instrument: it knows about disks, networks,
bootloaders and packages — not about "routers" or "NAS boxes".

## Design principles

1. **`config.scm` is the artefact.** Every path through the installer ends with
   a complete, human-readable `operating-system` declaration. The installation
   is `guix system init` applied to that file. Nothing is configured by
   side effect.
2. **Generic surface, presets as data.** Roles (desktop, server, appliance) are
   starting configurations, not code paths. Adding one never changes the
   installer.
3. **Provenance is two-way.** The configuration reviewed before installation is
   byte-identical to the one stored on the target, together with the answers
   that produced it and the Guix revision used.
4. **Nothing destructive by default.** A device is only written when it is
   named and erasure is explicitly requested. An existing file system is left
   alone unless the operator says otherwise.
5. **Upstreamable, or it does not belong here.** A feature that cannot be
   proposed to the Guix project because it mentions this project's private
   infrastructure is a feature that belongs somewhere else.

## Invocations

The CLI below is the contract; options marked *(planned)* are specified in
[`docs/contract.md`](docs/contract.md) but not implemented yet.

```sh
# Interactive, generic wizard (planned)
gradus

# Install an existing configuration as-is; the target's file systems must
# already exist with the labels/UUIDs the config names, and are mounted
# beneath --root
gradus --config config.scm --root /mnt/target

# Unattended: the answer file supplies the facts *and* the disk layout, the
# target disk is prepared for you (--target/--erase/--yes are planned)
gradus --answers answers.scm --root /mnt/target

# Validate everything, write nothing
gradus --answers answers.scm --dry-run
```

See [`docs/contract.md`](docs/contract.md) for the authoritative definition of
each mode, the answer-file format, the artefacts left on the target, and the
guarantees the installer makes.

## Documentation

| Document | Purpose |
|:--|:--|
| [`docs/contract.md`](docs/contract.md) | The shared contract: CLI, answer file, artefacts, guarantees, versioning |
| [`docs/pages.md`](docs/pages.md) | Page-by-page specification of the interactive installer |
| [`docs/install-flow.md`](docs/install-flow.md) | Stage-by-stage flow, and what is taken from YaST/Agama and Anaconda |
| [`docs/implementation.md`](docs/implementation.md) | Language, module layout, Guix boundary, upstream coding conventions |
| [`docs/testing.md`](docs/testing.md) | Acceptance tests and the VM/hardware matrix every release must pass |
| [`docs/upstream.md`](docs/upstream.md) | What belongs in this project and what belongs in Guix itself |

## Implementation

Guile Scheme. The reasons, the module layout and the boundary with Guix are in
[`docs/implementation.md`](docs/implementation.md). The short version: the
artefact is a Scheme program, so it is generated and validated in the language
that evaluates it, and pages can still be offered upstream.

## Roadmap

The installer has one core — the page flow and the answer file it produces —
and several front-ends over it.  Which front-end matters depends on the
machine: a desktop gets a graphical installation; a router or a NAS usually has
no display output at all, so for those the order of preference is unattended
installation, then remote installation, and only then a console.

- [x] v0.1 — `--config` mode: mount a prepared target, install a given
      `operating-system`, keep provenance.
- [x] v0.2 — storage: `simple` and `lvm` targets prepared and declared; data
      volumes adopted, never created.
- [ ] v0.3 — **installer core and TUI**: the page flow (language, source with
      proxy/mirror/self-hosted cache, storage, users, review, install) driven
      by one core, with a console front-end that also works over a serial line
      (the only front-end a board without display output can always fall back
      to).  Interface language includes Simplified Chinese.
- [ ] v0.4 — **ISO integration and unattended installs**: the wizard boots
      straight from the official-style ISO; `--target`, `--erase`, `--yes` and
      the boot page land, making the answer file the unattended path for
      headless machines.
- [ ] v0.5 — **Web front-end**: a graphical installation for desktops, and
      remote installation for headless machines, served by the same core (the
      Agama shape: one service, front-ends as clients).
- [ ] v0.6 — arm64 and RISC-V targets.

## Non-goals

- Not a distribution. The packages and the configuration language are Guix's.
- Not a package-manager GUI.
- Not a fleet configuration system. Fleet reproducibility belongs to the
  configuration repository that consumes this installer, never to the installer.
- Not a replacement for `guix system reconfigure`; once installed, the machine
  is managed with Guix's own tools.

## Licence and disclaimer

AGPL-3.0-or-later. See [`LICENSE`](LICENSE).

This is an independent project. It is not affiliated with or endorsed by the GNU
Guix project. "Guix" refers to the GNU Guix package manager and GNU Guix System.
