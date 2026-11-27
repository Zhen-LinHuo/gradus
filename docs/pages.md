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
| 2 | Source | channels file, substitute services (name, URL, kind, key), proxy | official channels, official substitutes, no proxy | — |
| 3 | Storage | disk, scheme (simple/LVM), encryption, swap, data volumes, erase consent | no disk selected; erase off | — |
| 4 | Boot | bootloader (including `none`), target, kernel, extra kernel arguments, menu policy, NVRAM, generations kept | GRUB EFI on the ESP, timeout 5 | — |
| 5 | Software | base profile, package groups, extra packages, manifest file | headless base | — |
| 6 | Network | host name, management interface, DHCP or static, wireless, proxy and `no_proxy` | DHCP on the first wired interface | — |
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
- an ordered list of **substitute services**, each with a name, a URL, a kind
  (`official`, `mirror` or `builder`) and, for a builder, a signing key;
- a proxy, with `http`, `https` and `no_proxy` values.

The same values must reach two places, and the page must show both:

1. the **live** environment, so the installation itself can use substitutes;
2. the **target's** `guix-configuration`, so the installed system keeps using
   them. When `authorize-key?` is true — the default — the target's
   `/etc/guix/acl` cannot be edited after the fact; the key must be in the
   declaration from the start.

One input, two destinations, never two lists.

The list is edited in place: add, remove, reorder. Order is visible because
order is the policy — the fastest reachable source goes first. A "test this
source" action fetches one narinfo through the configured proxy, so that a
mistyped cache is discovered here and not twenty minutes into an installation.

The `kind` distinction is shown, not hidden: a mirror needs no key, a builder
does. Presenting both as "substitute server" would teach the operator to accept
key prompts without reading them.

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

Bootloader family, target and policy, the kernel package, extra kernel
arguments, menu behaviour and how many previous generations to keep.

Non-negotiable behaviours:

- **`none` is a value.** Choosing it installs no bootloader and leaves the
  existing one untouched. The page states that the machine will not boot
  unaided; it does not refuse the choice.
- **Extra kernel arguments are listed, not concatenated silently.** A headless
  machine needs `console=ttyS0`; a workaround may need one more parameter. The
  full resulting line is shown on the review page.
- **Menu behaviour is explicit**: wait time, stop-at-menu (the equivalent of an
  indefinite wait), default entry, and whether the firmware's NVRAM is updated.
  Rewriting NVRAM without being asked can stop a machine booting the system the
  operator wanted.
- **The kernel package is chosen here.** `linux-libre` is the default; another
  kernel from a selected channel changes the trust boundary, and the page says
  so rather than presenting it as a driver choice.

The official installer asks none of this, which is why a headless machine
cannot be given a serial console at install time.

### 5. Software

A base profile plus package groups plus free-form package names plus an
optional manifest. It is deliberately **not** a catalogue browser: Guix has tens
of thousands of packages, and a picker that pretends to rank them is worse than
a text field with completion.

Selecting a base profile is choosing a starting configuration, not entering a
code path. The resulting `operating-system` is shown on the review page, and a
profile that cannot be expressed as a configuration is a bug in the profile.

### 6. Network

Host name, management interface, addressing, wireless credentials and proxy.

Static configuration is offered but not required; DHCP is the default on the
first wired interface.

Proxy settings are collected here because everything after this page may need
them: channels, substitutes, and a remote answer file. `http_proxy` and
`https_proxy` may differ. The `no_proxy` list is a first-class field, not an
advanced option — a local substitute cache normally must bypass the proxy that
provides external access, and sending it through the proxy turns a fast cache
into a timeout.

Wireless credentials and proxy credentials are the two secrets the installer
must accept. Both are written to the target configuration only if the operator
asks for them to be kept there; otherwise they are used for the live session and
discarded.

### 7. Users

One administrative account is created. Root login is disabled by default.
Authorised SSH keys are collected as text or from a file; an empty list is
allowed and leaves password authentication as the only route, which the page
states plainly.

### 8. Review

The review page shows what will be installed: host name, target, layout,
bootloader, substitutes, packages, accounts and the system identity. Before
the target is prepared the summary comes from the answers, and every
"change …" entry jumps into the page that owns the value and returns here.

Choosing install asks for the erase consent — the default answer is no — and
prepares the target. From that point the declaration file is the truth: the
summary is read back from `config.scm`, so a text edit is what the page
shows. "view declaration" scrolls the whole file; "edit declaration" hands
it to an editor on the console. Changing a setting afterwards re-renders the
file, which discards a hand edit — the page says so while one is present.
A file that no longer reads as a system declaration is reported on the page
and again at the install confirmation, and cannot be installed.

The complete declaration may also be saved to removable media, and a diff
against the profile it started from shows what the answers changed.

### 9. Install

A second, explicit confirmation — the default answer is no — names the disk
one last time. From there the console belongs to the install log: the
declaration is built and installed, with progress and a transcript. Because
the build happens before the target is written, a declaration that does not
build stops the install before it reaches the system. On failure the report
is the state of the target as it actually is, not as it was intended to be.

## What is deliberately absent

- A package catalogue browser.
- Service configuration pages beyond enable/disable and the fields a service
  exposes as ordinary values. Services are configured in the declaration; a
  general-purpose form generator over arbitrary Scheme records is a different
  project and a worse one.
- Any page whose content depends on a site, a fleet or a vendor.

## Comparison with Anaconda and Agama

Checked against Anaconda's Installation Summary spokes (AlmaLinux/RHEL) and
Agama/YaST (openSUSE Tumbleweed).  What the two reference installers have that
this page set must also have, or must refuse explicitly:

| Concern | Anaconda | Agama/YaST | Gradus |
| --- | --- | --- | --- |
| Keyboard layout | spoke | yes | **missing — goes on the locale page** |
| NTP on/off | with Time & Date | implicit | **missing — goes on the locale page** |
| Timezone | spoke | yes | yes |
| Installation source | media / network | product + registration | substitutes + channels (Guix is network-first; no local media) |
| Software selection | base environment + add-ons | patterns | base + free-form packages; profiles *(planned)* |
| Partition **sizes** | custom partitioning | limited (a known Agama gap) | **must be explicit** — ESP default 1 GiB is overridable, root is a size or the remainder |
| LUKS encryption | yes | yes | yes (LUKS1, root only — GRUB unlocks by UUID; LVM and swap combinations refused) |
| Swap | automatic | yes | an explicit size, defaulting to the machine's memory (1–8 GiB); refused with encryption |
| Network interface choice, static addressing | spoke | yes | DHCP only today; static + interface **planned** |
| Root password / lock | spoke | yes | yes |
| User + "make administrator" | spoke | yes | yes (wheel) |
| KDUMP | spoke | yes | **refused** — not part of a headless contract |
| Security policy | RHEL only | no | **refused** — vendor concept |
| Bootloader page (menu, NVRAM update) | implicit | YaST yes | timeout + kernel arguments; NVRAM update *(planned)* |
| "Test this source" | no | no | specified, not yet implemented |

The two refusals follow from the contract: Gradus installs headless machines
for this fleet, and a vendor security policy or a crash-dump daemon is a
distribution decision, not an installer page.
