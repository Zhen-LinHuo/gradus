# Implementation

Product version: 0.3.0. Contract version: 1.

## Language: Guile Scheme

The installer is written in Guile Scheme, the language of Guix itself.

The decision is not sentimental. Three properties follow from it:

1. **One configuration model.** The artefact is a Scheme program. Generating it
   in the same language that evaluates it means there is no second, approximate
   model of `operating-system`, services or gexps to keep in step.
2. **Errors come from the same evaluator.** A malformed declaration fails in
   the same place, with the same message, whether it was written by hand or
   rendered from answers.
3. **The upstream path stays open.** Guix's own installer lives in
   `gnu/installer/`. A Scheme implementation can contribute pages there as
   patches; an implementation in another language can only contribute ideas.

Two practical consequences reinforce the choice: the installation image already
contains Guile and Guix, so there is no extra runtime closure to ship, and the
project can be packaged as an ordinary Guix package.

### Alternatives considered

| Language | Attraction | Why not (for now) |
|:--|:--|:--|
| Rust | Static binary, strong TUI and testing ecosystem; a working third-party Guix installer already exists in Rust | The configuration model would be rebuilt in a second language or reduced to text templates, and nothing could be offered upstream |
| Python | Fastest to write | Adds a runtime and a dependency surface to the image, and still rebuilds the model |
| Go | Single binary, simple deployment | Same model problem as Rust, with a smaller Guix-adjacent community |

A non-Scheme implementation is not impossible; it is a different product
strategy. This repository has chosen the one described above.

## Boundary with Guix

Use Guix's modules to **construct and inspect** declarations. Use the `guix`
command as a **subprocess** to build, validate and install.

The reason for the split is ABI discipline. Guix's internal modules change
between releases; the command-line interface is a documented contract. Anything
that must match the installed Guix exactly — resolving derivations, building
the system, running `guix system init` — goes through the command line. Record
construction and answer validation use the modules, where a version mismatch is
a build error rather than a silent difference in behaviour.

## Module layout

```
gradus/
  answers.scm      answer-file records, defaults, validation
  wizard.scm       page and field state machine (fields are plain data)
  render.scm       answers -＞ operating-system
  serialize.scm    answers and device map -＞ self-contained config.scm text
  storage.scm      partitioning, formatting, mounting, preservation rules
  install.scm      mount plan, guix system init, daemon lifecycle, logging
  utils.scm        subprocess handling, exit codes, secret files
  tui.scm          ncurses frontend (renders the wizard page model)
  script.scm       command-line entry point (--config / --answers / --tui)
tests/             SRFI-64 tests, one file per module
```

The layering contract — which module may import which, and the data contracts
between core and frontends — is defined in `docs/architecture.md`. Modules
live in the `(gradus …)` namespace. A module offered upstream moves to
`(gnu installer …)` and follows the rules of that tree; a module in this
repository never claims the `(gnu …)` namespace.

## Dependencies

| Dependency | Use |
|:--|:--|
| Guile 3.x | Language runtime |
| Guix | Record types and the `guix` command |
| guile-ncurses | Terminal pages |
| SRFI-64 | Tests |

No dependency is added to the installation image that Guix does not already
carry, with the exception of the UI library.

## Coding conventions

The code follows the GNU Coding Standards and Guix's *Coding Style*, because
part of it is intended to be offered upstream. The rules that actually change
what a reviewer sees:

- **Pure functional style**, except for input/output and low-level procedures.
- **Records, not lists.** Use `define-record-type*` for data structures and
  `(ice-9 match)` for destructuring. Browsing lists with `car`/`cdr` is a
  review rejection.
- **Docstrings on every top-level procedure.** Private procedures in a
  build-side module may omit them.
- **At most four positional parameters.** More than that becomes keyword
  arguments.
- **Formatting** follows Riastradh's Lisp Style Rules; the tree will carry a
  `.dir-locals.el` from the first code commit so that editors indent
  consistently. Indentation is not a matter of taste in a tree that takes
  patches by mail.
- **Module boundaries:** build-side code in `(guix build …)` must not refer to
  other Guix or GNU modules; host-side code may use build-side modules.

### Language of prose

The repository's own documentation and messages are in British English (see
`AGENTS.md`). A patch written for Guix follows Guix's conventions, including its
spelling and terminology. Do not "improve" an upstream patch to match this
repository's voice; the patch belongs to the tree that will carry it.

## Upstream contributions

- **Commit logs.** Guix requires ChangeLog-format logs: a one-line subject such
  as `gnu: foo: Fix bar.`, a blank line, then entries of the form
  `* path/to/file (symbol): what changed.`  A body that only explains the
  motivation is not sufficient.
- **Sign-off.** Every commit carries `Signed-off-by: Name <email>`, certifying
  the Developer Certificate of Origin. A patch without it is not merged.
- **Submission.** Patches are produced with `git format-patch --base` and sent
  to `guix-patches@gnu.org`; each message becomes a Debbugs issue.
- **Checks.** `guix lint` for package changes, `make check` for code, and
  `./pre-inst-env` to run the tree's own commands. A patch that has not been
  built in the target tree has not been tested.
- **Licence.** Guix is GPL-3.0-or-later. Code is **not** copied from this
  AGPL-3.0-or-later repository into an upstream patch: the patch is written for
  Guix and offered under Guix's licence. Confirm the current policy on
  `guix-devel` before sending anything non-trivial.

## Build and test

```sh
# In this repository
guix shell -D -f guix.scm -- make check

# Against a Guix checkout, for upstream work
./pre-inst-env guix system --help
```

A caution that cost a real debugging session: `guix shell --pure` strips the
host PATH, so a driver that shells out to `mount`, `losetup` or `partprobe`
will fail with `execvp: No such file or directory`. Run the installer either
without `--pure`, or with the needed host directories restored explicitly.

`guix.scm` is added with the first code commit. Until then this document is the
specification the code must satisfy.
