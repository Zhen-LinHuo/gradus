# Installation flow

The flow is modelled on two mature installers — YaST/Agama on openSUSE and
Anaconda on AlmaLinux — because their stage boundaries have survived a decade of
hardware and operator habits. What differs is the output: both of them leave a
system, while Gradus leaves a system **and** the declaration that describes it.

## Stages

| # | Stage | Agama (openSUSE) | Anaconda (AlmaLinux) | Gradus |
|:--|:--|:--|:--|:--|
| 0 | Boot the medium | GRUB entry, `inst.` options | GRUB entry, `inst.` options | GRUB entry, kernel command line |
| 1 | Language, keyboard, timezone | separate dialogs | Localisation hub | Localisation page |
| 2 | Registration / product | SUSE Customer Center | Subscription (RHEL family) | *not applicable* — channels instead |
| 3 | Installation source | product repositories | Installation source | Source page: channels, substitutes, proxy |
| 4 | Network | connections, proxy | Network & hostname, proxy | Network page: interface, host name, proxy |
| 5 | Storage | partition proposal, manual | Installation destination | Storage page |
| 6 | Bootloader | reduced set: menu stop, timeout, extra kernel parameters, NVRAM | `bootloader` options: location, append, timeout, disabled | Boot page |
| 7 | Software | patterns and packages | Environment groups, add-ons | Software page: base profile, groups, names, manifest |
| 8 | Users | root, first user | Root password, user creation | Users page |
| 9 | Review | summary | Installation summary hub | Review page: full `config.scm` |
| 10 | Install | progress | progress | Install page |

Two structural notes:

- Both reference installers use a **hub** (a summary screen whose sections can be
  visited in any order), not a strict wizard. The first release is linear
  because linearity is cheaper to get right; the pages are specified as
  independent so a hub can replace the order later without rewriting them.
- Neither reference installer is declarative. Their "summary" is a summary of
  pending actions; ours is a file the operator can read, copy and install again.

## Bootloader

The reference installers expose three things that matter on real hardware and
that the official Guix installer does not ask about at all.

### Optional installation

Anaconda can be told not to install a bootloader at all (`--location=none`,
also `--disabled`). This is not a curiosity: it is required when another
bootloader owns the disk, when the machine is a virtual image, or when the
operator will chain-load the system deliberately.

Gradus therefore treats "no bootloader" as a first-class value, not as an
error. Choosing it:

- leaves the existing bootloader untouched;
- records the decision in `config.scm` (no `bootloader` field);
- prints an explicit warning on the review page: *the machine will not boot on
  its own until a bootloader is configured*.

### Kernel parameters

Anaconda appends extra parameters (`bootloader --append`); Agama exposes
`extraKernelParams`. This is how a headless machine gets `console=ttyS0`, how a
workaround is applied before the first boot, and how an operator passes an
installer-specific option without rebuilding the image.

In Guix terms these are `kernel-arguments` on the `operating-system` record.
The page collects a list, shows the resulting line in full, and never hides
parameters that a previous stage added.

### Menu policy

| Setting | Agama | Anaconda | Gradus |
|:--|:--|:--|:--|
| Wait time | `timeout` | `--timeout` | `timeout` |
| Stop indefinitely | `stopOnBootMenu: true` | `--timeout=-1` equivalent | `timeout: -1` |
| Default entry | — | `--default` | `default-entry` |
| Update firmware NVRAM | `updateNvram` | `--leavebootorder` (inverse) | `update-nvram` |

A machine whose firmware entries are rewritten without being asked is a machine
that may stop booting the operating system the operator wanted. The NVRAM option
exists so that this is a decision, not a side effect.

### Kernel choice

Guix has a decision the reference installers do not: which kernel package.
`linux-libre` is the default; hardware that needs non-free firmware or drivers
requires another kernel from an additional channel. The page offers the kernels
available in the selected channels and states the consequence of each — a change
of trust boundary, not merely of driver support.

## Network and proxy

An installation is a network operation long before the first package is
unpacked: channels are fetched, substitutes are downloaded, and sometimes the
answer file itself is fetched. On networks without direct egress, the operator
needs a proxy **at stage 3 or 4**, before any of that.

The requirements, drawn from what the reference installers allow:

- A proxy may be configured from the boot command line, so that a remote
  unattended installation can reach its answer file.
- Both `http_proxy` and `https_proxy` are settable, and they may differ.
- A `no_proxy` list is mandatory, not optional: a substitute cache on the local
  network usually must **not** go through the proxy that provides external
  access. Getting this wrong turns a fast LAN cache into a timeout.
- The same values are applied to two places: the live environment (so the
  installation can fetch) and the target's Guix daemon (so the installed system
  can fetch). The daemon honours `http_proxy` and `https_proxy` in its
  environment, as documented in the Guix manual's *Proxy Settings*.
- Whether the target's values are declared through the service configuration or
  through a wrapper around the daemon depends on the Guix release in use. v0.3
  settles this against the supported release and proves it with test T6; until
  then the contract states the requirement, not the mechanism.

Credentials in a proxy URL are treated as a secret: they are written to the
target only if the operator keeps them, and never printed on the review page
beyond the host and port.

## Substitute services and third-party caches

The reference installers know about repositories; Guix knows about *substitute
servers*, which are a different thing: a source of pre-built store items,
verified by signature, addressed by hash.

The source page therefore accepts a list, not a single URL:

| Kind | Meaning | Key required |
|:--|:--|:--|
| official | The project's own build farms | Already trusted |
| mirror | Another HTTP endpoint serving the **official** store paths, byte-identical and signed by the original builders | No new key |
| builder | An independent builder, for example `guix publish` on the local network | Yes — its own key |

The distinction matters because it decides whether the operator must supply a
key at all. A mirror that serves official artefacts needs no new trust; a local
cache that builds its own artefacts does. Asking for a key for a mirror teaches
the operator to click through key prompts, which is exactly the habit that makes
signature checking worthless.

Ordering is significant: servers are tried in the order given, so the fastest
reachable source goes first. A miss costs one lookup and falls through; a stale
mirror cannot serve an old artefact, because the request is keyed by hash.

Every key accepted here is written into the target's `guix-configuration` as
well as into the live environment. When `authorize-key?` is true — the default —
the target's `/etc/guix/acl` cannot be edited later, so a key that is only
authorised during installation disappears at the first boot.

## Assembled storage: RAID and LVM

The NAS mode assembles data volumes from disks that change over time. The
design survives that because mount addressing is separated from assembly:

| Layer | What it is | Identity |
|:--|:--|:--|
| assembly | mdadm array, LVM volume group and logical volume | member disks by **disk-level** identity (WWN, serial or GPT partition UUID), the array or volume by its own name and UUID |
| file system | ext4/btrfs on the assembled device | the **file-system UUID**, unchanged when members are replaced |
| declaration | `mapped-devices` plus `file-systems` | only the top two layers appear here |

Consequences that the schema and the renderer must honour:

- A replaced member disk changes the declaration's *assembly* section only.
  The mount section is untouched, because the file-system UUID inside the
  volume did not change.
- Data volumes are **adopted, never created implicitly**: a data-volume entry
  carries the file-system UUID of the existing volume, and the installer
  assembles — but does not format — it.
- Root and boot stay outside the data pool: `gradus-root` and `GRADUS-ESP`
  are independent of whatever happens to the data disks, which is why a
  failing data array cannot take the boot path down.
- `blkid` reports the file system on an assembled device exactly as on a
  partition, so the label-to-UUID device map needs no special case.

Implementation-wise this means: the answer schema's storage section grows
`lvm` and `raid` modes whose members are named by disk identity; the renderer
gains a `mapped-devices` section translated from the assembly; and the
prepare step assembles but never formats data volumes. None of it changes the
mount-addressing rule decided above.

## What the review stage must show

Borrowed from both reference installers: a summary that is complete enough to
catch a mistake before it is written to disk. Ours adds two lines they cannot
show:

1. The full `config.scm`, editable, with a diff against the profile it started
   from.
2. The exact sources that will be used — channels, substitute servers, proxy —
   because those are the decisions that are hardest to notice after the fact.
