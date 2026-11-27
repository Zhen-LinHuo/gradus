# The installer contract

This document is the authoritative definition of what the installer accepts,
what it produces, and what it promises. Anything that consumes the installer —
a fleet repository, a CI job, a human with a USB stick — may rely on this file
and on nothing else.

Contract version: **1**. Product version: **0.3.0**.

## 1. Scope

The installer turns *installation decisions* into an installed Guix System and
into the `operating-system` declaration that describes it.

It is not a configuration manager. After installation, the machine is managed
with `guix system reconfigure` and the configuration file the installer left
behind.

## 2. Invocation modes

**Implementation status (v0.2).** Of this section, the following exist today:
`--config FILE` and `--answers FILE`, `--root DIR` (the mount point under which
the target's file systems are mounted; default `/mnt`), `--dry-run`, `--log`,
`--version`.  In `--config` mode the target's file systems must already exist,
carrying the labels or UUIDs that `FILE` names — the installer mounts them and
does not partition.  In `--answers` mode the target disk is prepared from the
answer file.  `--target`, `--erase`, `--proxy`, `--no-proxy` and `--yes` are
specified but not implemented yet.

| Mode | Command shape | What is required | What is written |
|:--|:--|:--|:--|
| Interactive | `gradus` | Nothing | Target disk, only after explicit confirmation |
| From configuration | `gradus --config FILE --target DEV` | `FILE`'s file systems must resolve on the target | Target disk, bootloader |
| Unattended | `gradus --answers FILE --target DEV --erase` | Complete answer file | Everything the answers describe |
| Validation | any of the above plus `--dry-run` | As above | Nothing |

`--dry-run` performs every check, renders the resulting `operating-system`,
prints it to standard output, and exits without touching any device.

### 2.1 Option reference (v1)

| Option | Effect |
|:--|:--|
| `--config FILE` | Install this `operating-system` declaration as written |
| `--answers FILE` | Read installation decisions from `FILE`; render the configuration from them |
| `--target DEV` | Device that receives the bootloader (and, with `--erase`, the system) |
| `--erase` | Permit writing to `DEV`. Without it, a device carrying a file system is refused |
| `--proxy URL` | Use this HTTP/HTTPS proxy for the installation, overriding the answer file |
| `--no-proxy LIST` | Comma-separated hosts that bypass the proxy, overriding the answer file |
| `--dry-run` | Check and print; write nothing |
| `--yes` | Answer confirmation prompts affirmatively (requires `--erase` for destructive modes) |
| `--log FILE` | Write the transcript to `FILE` in addition to the default location |
| `--version` | Print product and contract version, exit 0 |

`--config` and `--answers` are mutually exclusive. `--target` is mandatory in
both non-interactive modes.

## 3. Configuration mode

In `--config` mode the installer does **not** modify the declaration. It:

1. validates the declaration (`guix system build --dry-run` equivalent);
2. checks that every `file-system` device in it resolves on the target — by
   label or UUID, before any mount is attempted;
3. checks that the bootloader target is plausible (UEFI system partition
   present, or BIOS boot area available);
4. mounts the declared file systems under the target root;
5. runs `guix system init` with the declaration;
6. installs the bootloader as the declaration describes.

Device names in the declaration are therefore a caller concern. This mode
deliberately performs no partitioning: a configuration cannot express partition
sizes, so inferring a layout from it would be guesswork.

## 4. Answer-file format

An answer file is an S-expression read with Scheme's `read`. It describes the
*installation*, not the whole system: it carries facts and a small number of
policies, and the renderer fills in everything else from the selected profile.

```scheme
;; answers.scm — schema version 1
((schema-version . 1)
 (profile . "desktop")
 (locale . "en_GB.utf8")
 (timezone . "Europe/London")
 (keyboard . "gb")
 (host-name . "workstation")

 (proxy
  (http . "http://proxy.example.net:3128")
  (https . "http://proxy.example.net:3128")
  (no-proxy . ("localhost" "cache.example.net")))

 (source
  (channels . "channels.scm")
  (substitute-services
   ((name . "official")
    (url . "https://ci.guix.gnu.org")
    (kind . official))
   ((name . "lan-cache")
    (url . "http://cache.example.net")
    (kind . builder)
    (key . "cache.example.net.pub"))))

 (storage
  (mode . simple)                 ; simple | lvm | existing
  (disk . "/dev/nvme0n1")
  (erase . #f)
  (esp-size . 1024)               ; MiB; the ESP (EFI) or BIOS Boot partition
  (swap-size . 0)                 ; MiB; 0 means no swap partition
  (root-size . 0)                 ; MiB; 0 means the rest of the disk
  (encryption (mode . luks)       ; LUKS1 — GRUB must read the root at boot
              (name . "cryptroot")
              (passphrase . "…")) ; never written to the declaration
  (data-volumes . ()))            ; never formatted unless erase? is #t per volume

 (boot
  (bootloader . grub-efi)         ; grub-efi | grub-bios | extlinux | u-boot | none
  (target . "/dev/nvme0n1")
  (kernel . linux-libre)
  (extra-kernel-arguments . ("console=ttyS0,115200"))
  (timeout . 5)                   ; -1 waits indefinitely
  (stop-at-menu . #f)
  (default-entry . 0)
  (update-nvram . #t)
  (keep-generations . 5))

 (network
  (management . dhcp)             ; dhcp | static
  (interface . "eno1"))

 (users
  ((name . "alice")
   (groups . ("wheel" "audio" "video"))
   (ssh-keys . ("ssh-ed25519 AAAA..."))))

 (software
  (package-groups . ())
  (extra-packages . ())
  (manifest . #f)))
```

Rules:

- Unknown keys are an error, not ignored. Silent acceptance of a typo is how an
  unattended install ends up different from what the operator reviewed.
- `software.package-groups` names the installer's bundled package groups.
  Each package group is a Guix manifest file the machine can also consume on
  its own with `guix package -m <file>`; an unknown name is an error, and the
  group's packages are added to the named packages in
  `software.extra-packages`.
- Every key in the example above is optional except `schema-version`, `profile`,
  `storage` and `users`; omitted keys take documented defaults.
- `erase` defaults to `#f`. A data volume is never formatted implicitly; each
  volume carries its own `erase?` flag.
- `bootloader` may be `none`. In that case no bootloader is installed and the
  existing one is left untouched; the renderer omits the field and the review
  stage states plainly that the machine will not boot unaided.
- A substitute service's `kind` decides whether a key is required. `mirror`
  serves official store paths signed by their original builders and needs no new
  key; `builder` signs its own artefacts and must carry one.
- Proxy credentials are secrets. They are never printed in full, and they are
  written to the target only when the operator asks for that.
- Command-line `--proxy` and `--no-proxy` override the corresponding answer-file
  values; the answer file is not rewritten to match.
- The renderer is deterministic: the same answer file and the same profile at
  the same version produce the same declaration.
- Encryption is refused where the installer cannot honour it, before anything
  is written to a disk: with `lvm` storage, and together with a swap partition
  (the swap would be plaintext outside the container). The passphrase is used
  to format the container and is never written to the declaration; the
  declaration carries the container's LUKS UUID, which is the only form GRUB
  can unlock. A declaration without that UUID is not written.

### 4.1 Sources and trust

The installer never adds a source of its own. The source list in the answer file
is used in the order written, both in the live environment and in the target's
`guix-configuration`.

Signature checking is never relaxed. A mirror accelerates; it does not vouch.
The keys authorised for the live environment are the same keys written into the
target, so a key that is only present during installation does not silently
disappear at the first boot.

## 5. Artefacts

On the target, after a successful installation:

| Path | Content |
|:--|:--|
| `/etc/config.scm` | The exact `operating-system` declaration that was installed |
| `/etc/gradus/answers.scm` | The answers used, or a statement that `--config` mode was used |
| `/etc/gradus/provenance.scm` | Installer version, contract version, Guix revision, UTC timestamp |
| `/var/log/gradus-install.log` | Full transcript |

`/etc/config.scm` is byte-identical to the file that was reviewed: no
reformatting, no regeneration after the fact. Provenance exists so that "what is
on this machine" and "what was requested" can be compared without guesswork.

## 6. Guarantees

1. **No implicit destruction.** A device is written only when it is named by
   `--target` *and* erasure is requested (`--erase` in unattended mode, an
   explicit confirmation in interactive mode).
2. **No hidden sources.** Packages are fetched only from the channels and
   substitute URLs declared in the answers or configuration. The installer does
   not add sources of its own.
3. **Dry run is inert.** `--dry-run` creates no mount, no partition, no file.
4. **Refusal over guessing.** If a declared file system does not resolve, if the
   bootloader target is ambiguous, or if the target is mounted or is the live
   medium, the installer stops with a non-zero exit status. It does not pick a
   default device.
5. **Provenance.** A successful installation always leaves the artefacts in §5.
6. **Proxy where it is needed.** A proxy configured for the installation is used
   for every fetch the installation performs, and is configured for the target's
   Guix daemon. A `no_proxy` entry always takes precedence, so a local cache is
   not sent through the proxy that provides external access.

## 7. Exit status

| Code | Meaning |
|:--|:--|
| 0 | Success |
| 1 | Usage error |
| 2 | Validation error in the configuration or answer file |
| 3 | Target unsuitable (mounted, missing, too small, live medium, insufficient privileges) |
| 4 | Installation failed |
| 5 | Interrupted by the operator |

After exit 3 or 4, the installer reports exactly which step failed and what is
currently on the target. It does not attempt an automatic repair.

## 8. Non-guarantees

- No resume of a partially written disk in v1. A failed installation is
  re-attempted from the beginning; the operator is told what state the target is
  in.
- No migration or upgrade of an installed system.
- No post-install configuration. That is `guix system reconfigure`'s job.
- No rollback of an activation performed on a running live system. The installer
  installs; it does not mutate a running system.

## 9. Compatibility and versioning

- **Contract version** changes only when an existing caller would break:
  option removal, answer-file key removal, artefact path change, altered
  guarantee. Product major version follows the contract major version.
- **Product version** is SemVer. Adding a page, an optional answer key or a
  target architecture is a minor bump.
- The answer file declares its own `schema-version`; the installer refuses a
  schema it does not implement rather than ignoring unknown fields.
- Supported Guix System: the current stable release at the time of the product
  release, recorded in `/etc/gradus/provenance.scm`.
