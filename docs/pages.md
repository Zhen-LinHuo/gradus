# Page specification

The interactive installer is a sequence of pages over the generic configuration
surface of a Guix System. This document defines what each page collects, what it
defaults to, and which rule keeps it generic.

Rule 0: **no page may mention a fleet, a role, a vendor or a site.** Pages know
about disks, interfaces, packages and bootloaders. If a page would need a proper
noun that is not a standard system concept, it is a preset, not a page.

Rule 1: **every page is skippable.** If the value is supplied by `--config` or
by an answer file, the page is not shown. Interactive mode is the union of pages
whose values are still unknown.

Rule 2: **the last page is always the configuration.** There is no "apply" that
the operator cannot inspect first.

## Page sequence

| # | Page | Collects | Defaults | v0.1 |
|:--|:--|:--|:--|:--|
| 1 | Localisation | language, territory, keyboard, timezone | live environment's locale | — |
| 2 | Source | channels file, substitute URLs, signing keys | official channels, official substitutes | — |
| 3 | Storage | disk, scheme (simple/LVM), encryption, swap, data volumes, erase consent | no disk selected; erase off | — |
| 4 | Boot | bootloader, target, timeout, default entry, serial console, generations kept | GRUB EFI on the ESP, timeout 5 | — |
| 5 | Software | base profile, environment groups, extra packages, manifest file | headless base | — |
| 6 | Network | host name, management interface, DHCP or static, wireless | DHCP on the first wired interface | — |
| 7 | Users | root policy, user accounts, groups, SSH keys | one administrative user, no root login | — |
| 8 | Review | full `config.scm`, diff against the starting profile, save to removable media | — | — |
| 9 | Install | confirmation, progress, transcript | — | — |

`--config` mode replaces pages 1–8 with a single validation step and goes
straight to page 9.

## Page details

### 1. Localisation

Locale, timezone and keyboard layout. These affect the live environment *and*
the target; they are written to the configuration, not only to the live session.
Nothing here is inferred from the network: a wrong timezone is cheap to fix,
but a silently guessed one is hard to notice.

### 2. Source

The page the official installer lacks. It collects:

- a channels file (path or URL), defaulting to the distribution's own;
- an ordered list of substitute URLs;
- signing keys for those substitutes, by file, by URL, or from a key shipped
  with the installation image.

The same values must reach two places, and the page must show both:

1. the **live** environment, so the installation itself can use substitutes;
2. the **target's** `guix-configuration`, so the installed system keeps using
   them. When `authorize-key?` is true — the default — the target's
   `/etc/guix/acl` cannot be edited after the fact; the key must be in the
   declaration from the start.

One input, two destinations, never two lists.

### 3. Storage

Disk selection, partitioning scheme, encryption, swap and data volumes.

Non-negotiable behaviours:

- A disk is written only after an explicit confirmation that names it.
- A device already carrying a file system is shown as such and is **not**
  formatted unless erasure is requested for that device.
- A data volume with `erase? = #f` is mounted, never prepared. This is how a
  reinstall preserves data.
- Encryption is offered, never assumed.

The page produces file systems by UUID (not kernel device names), because the
declaration outlives the enumeration order.

### 4. Boot

Bootloader family and target, menu timeout, default entry, serial console, and
how many previous generations to keep.

These are ordinary fields of `bootloader-configuration`. The official installer
asks none of them, which is why a headless machine cannot be given a serial
console at install time. A timeout of `-1` (wait indefinitely) and a serial
console are the two settings that most often decide whether a remote machine is
recoverable.

### 5. Software

A base profile plus environment groups plus free-form package names plus an
optional manifest. It is deliberately **not** a catalogue browser: Guix has tens
of thousands of packages, and a picker that pretends to rank them is worse than
a text field with completion.

Selecting a base profile is choosing a starting configuration, not entering a
code path. The resulting `operating-system` is shown on the review page, and a
profile that cannot be expressed as a configuration is a bug in the profile.

### 6. Network

Host name, management interface, addressing and wireless credentials. Static
configuration is offered but not required; DHCP is the default on the first
wired interface.

Wireless credentials are the one secret the installer must accept. They are
written to the target configuration only if the operator asks for them to be
kept there; otherwise they are used for the live session and discarded.

### 7. Users

One administrative account is created. Root login is disabled by default.
Authorised SSH keys are collected as text or from a file; an empty list is
allowed and leaves password authentication as the only route, which the page
states plainly.

### 8. Review

The complete declaration, a diff against the profile it started from, and a
"save to removable media" action. The operator may edit the text directly: the
review page is the escape hatch for everything the other pages do not model.

Editing here does not bypass validation. The edited file is built before the
installation starts.

### 9. Install

A summary of what will be written where, one final confirmation, then progress
with a transcript. The installer reports the step it is in, and on failure the
state of the target as it actually is, not as it was intended to be.

## What is deliberately absent

- A package catalogue browser.
- Service configuration pages beyond enable/disable and the fields a service
  exposes as ordinary values. Services are configured in the declaration; a
  general-purpose form generator over arbitrary Scheme records is a different
  project and a worse one.
- Any page whose content depends on a site, a fleet or a vendor.
