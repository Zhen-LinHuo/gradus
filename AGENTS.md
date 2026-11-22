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
- Every commit is signed. The repository-local identity is recorded in
  `AGENTS.local.md`, which is not tracked.

## Branches and review

- `main` is always installable and always matches `docs/contract.md`.
- Work happens on `feat/<topic>`, `fix/<topic>` or `docs/<topic>`.
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
- Any change to storage, boot, source or answer-file handling requires T2 and
  T5 from `docs/testing.md` on the release candidate, and T1 before the first
  public release.
- Test evidence is a transcript and a diffable artefact, never a screenshot.

## Confidentiality gate

This repository is public. Before every commit, run the confidentiality gate:

```sh
test -f .private-patterns || { echo "no pattern file"; exit 1; }
grep -RInEf .private-patterns --exclude-dir=.git --exclude=AGENTS.local.md .
```

`.private-patterns` holds this project's forbidden identifiers and is **not**
tracked; the list itself is documented in `AGENTS.local.md`. The output must be
empty. A hit is either removed or generalised; it is never explained away.

## Identity

Commits in this repository use the public identity recorded in
`AGENTS.local.md`. Do not commit with a machine's default identity; check
`git log -1 --format='%an <%ae>'` before the first commit of a session.

## Scope discipline

The installer does not manage an installed system and does not know about
fleets, roles or sites. A patch that adds a proper noun outside standard system
vocabulary is rejected, however convenient it is.
