# Repository conventions

These rules apply to humans and to automated contributors alike.

## Language

British English in documentation, comments and user-facing strings (`-ise`,
`-our`, `-re`, `-ence`). The installer's messages are part of the product's
surface: write them as sentences, not as codes.

## Documentation first

The contract (`docs/contract.md`) is authoritative. A change in behaviour that
is not reflected there is incomplete, regardless of whether the code works.

Promote a feature to the roadmap in `README.md` only after its page or option is
specified in `docs/`. Specifications describe observable behaviour; they do not
describe implementation.

## Commits

- Conventional Commits: `feat:`, `fix:`, `docs:`, `test:`, `refactor:`,
  `chore:`.
- Imperative mood, no trailing full stop, subject at most 72 characters.
- The body explains *why*; the diff already explains *what*.
- Every commit is signed.
- This section governs commits in **this** repository. A patch destined for Guix
  follows Guix's rules instead: ChangeLog-format log, `Signed-off-by` trailer,
  `git format-patch --base`. See `docs/implementation.md`.

## Language and upstream patches

- The implementation language is Guile Scheme. Coding conventions are in
  `docs/implementation.md`; they are Guix's conventions on purpose.
- Do not copy code from this AGPL-3.0-or-later repository into a Guix patch.
  Upstream patches are written for Guix and offered under Guix's licence.
- A patch that cannot be sent upstream without mentioning a private machine,
  domain or fleet is not upstreamable; keep it here and say so in the commit.

## Branches and review

The model is `feat/* → development → main`:

```
docs/* · feat/* · fix/* ──merge──▶ development ──pull request──▶ main ──tag──▶ release
   short-lived                     integration                    release line
```

- `main` is the release line. It is protected by a repository ruleset: no direct
  push, no deletion, no force push, linear history only, signed commits only, and
  every change arrives through a pull request. Feature work never lands on
  `main` directly.
- `development` is the integration line. Direct pushes are allowed; deletion and
  force pushes are not.
- Work happens on `feat/<topic>`, `fix/<topic>` or `docs/<topic>`, cut from
  `development` and merged back into it.
- `development` reaches `main` by pull request, squash-merged so that `main`
  stays linear. `main` is then merged back into `development`, so the
  integration line includes the release commit; force pushes are never used.
- Tags are created on `main` only.
- A change to the contract needs its own commit and an explicit version
  decision (see below).

## Versioning

- `VERSION` holds the product version, plain SemVer without build metadata.
- The contract version lives in `docs/contract.md` and changes only on a
  breaking change to an existing caller.
- Product major version never runs ahead of contract major version.
- Releases are tagged `vX.Y.Z` on `main`, signed, with the acceptance-test
  evidence from `docs/testing.md` in the release notes.

## Testing

- Documentation-only changes need no installation test.
- Any change to storage, boot, source or answer-file handling requires the tests
  in `docs/testing.md` that cover that area, on the release candidate; T2 and T5
  are the minimum, and T6–T8 apply when the change touches proxy, substitute
  services or bootloader selection. T1 is required before the first public
  release.
- Test evidence is a transcript and a diffable artefact, never a screenshot.
- Heavy builds and VM runs happen on a dedicated build host with KVM enabled,
  never on a machine whose availability matters during the test.

## Confidentiality gate

This repository is public. Before every commit, check the staged diff for
private identifiers: fleet names, internal domains, host names, private cache
URLs, IP addresses of machines that are not part of the product. A hit is
removed or generalised; it is never explained away.

A stronger version of this gate exists on the maintainer's machine, driven by an
untracked pattern file. That list is local and is not part of this tree; a
contributor must not need it.

## Identity

Commits use the identity configured for this repository, never a machine's
default. Automated contributors must check
`git log -1 --format='%an <%ae>'` before the first commit of a session.

## Local notes

An untracked `AGENTS.local.md` may exist on the maintainer's machine. It holds
machine-local facts — the signing identity, the build host, the private pattern
list — and it is never referenced by tracked documentation, never referenced by
code, and never committed. Everything a contributor needs is in this file.

## Scope discipline

The installer does not manage an installed system and does not know about
fleets, roles or sites. A patch that adds a proper noun outside standard system
vocabulary is rejected, however convenient it is.
