# Product or upstream?

This project exists because Guix's installer does not cover the whole
configuration surface. That is a gap in Guix, not a reason to build a parallel
universe. The rule is therefore:

> If a feature can be proposed to Guix as a self-contained patch, propose it.
> Keep here only what needs a product: the end-to-end flow, the unattended
> contract, and the disk-writing experience.

## Candidates for upstream

| Feature | Why it is generic | Shape of the patch |
|:--|:--|:--|
| Substitute URL and signing-key page | Every installation needs it; the current installer only toggles local discovery | A page plus a field in the installer's configuration record |
| Bootloader options page | `bootloader-configuration` already models timeout, default entry, serial console | A page over existing fields |
| Configuration import (`--config`) | Any operator with an existing declaration benefits | Larger; requires an installer entry point that skips the wizard |
| Package selection beyond desktop environments | Every distribution's installer has it | Needs agreement on where the package list comes from |

The first two are small, self-contained and useful to everyone. They should be
offered upstream before this project grows its own versions of them.

## Stays here

- The unattended answer-file contract (`docs/contract.md`). It is a product
  interface, not a Guix interface.
- The storage flow, including the refusal rules and the preservation semantics.
- Provenance artefacts on the target.
- The release process, the VM matrix and the acceptance tests.

## Channels, and the nonguix question

A channel that ships non-free software (nonguix is the usual one) is a
legitimate thing for an *operator* to choose and a thing the Guix project will
never ship itself.  The boundary that keeps both true:

- **The installer is channel-agnostic.** Its source step accepts a list of
  channels — name, URL, commit — and nothing in the code knows what nonguix is.
  That mechanism is generic and upstreamable.
- **The nonguix profile is data, not a code path.** It lives with the other
  presets as a starting configuration, discloses that it adds non-free software
  and changes the kernel, and is never selected by default.
- **Never in an upstream patch.** A patch that mentions nonguix by name would be
  rejected, correctly.  Patches carry the generic channel mechanism only; the
  preset stays in this repository.
- **The review step shows the channel list.** An operator who ends up with a
  non-free kernel should be able to see the line that put it there.

This also answers the practical objection: people install nonguix anyway, by
hand, after the installer has finished.  Offering it as a disclosed preset is
more honest than leaving them to copy snippets from a wiki.

## Rules for patches

1. **No private identifiers.** A patch containing a hostname, a domain, a
   private cache URL or a fleet convention is rejected before it is sent. Run
   the grep from T1 over the diff.
2. **No product-specific options.** An upstream patch may not add a flag that
   exists only for this installer's flow.
3. **Behaviour first, page second.** If upstream accepts the behaviour (for
   example, importing a signing key at install time), the page follows the
   accepted design rather than the reverse.
4. **Track what diverges.** When a feature exists both upstream and here, record
   the divergence and the reason in the release notes. A silent fork becomes a
   compatibility trap.

## Cadence

The installer targets the current Guix System stable release. Upstream changes
to the installer's internals are expected; this project's own surface is
deliberately thinner than a fork, so the rebase cost stays bounded.
