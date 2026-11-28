# Gradus Web UI

The web face of the installer: the same core state machine
(`gradus/review.scm`, `gradus/wizard.scm`, `gradus/selection.scm`,
`gradus/fs.scm`) that drives the TUI, rendered by a browser. Per
`architecture.md`, the web frontend is a client of the core — it renders
fields, submits answers, polls progress — and never owns installation state.

## Stack

Deliberately **vanilla**: static HTML + CSS + JS served directly by the
Guile web server alongside the JSON API. No build chain, no npm, no CI node
step — the assets run from the installer environment (live ISO, offline
LAN). Interactivity is `fetch` + DOM; if a screen ever needs heavier
state, a vendored `preact/htm` file can be added without a build step.

```
gradus/web/
  index.html      single-page shell: step nav + view container
  frame.css       layout skeleton (top step rail, form column, footer actions)
  tokens/*.css    one theme per enlisted style (custom properties, light+dark)
  app.js          core API client + field renderer + progress poller
```

## Theming

Tokens follow the enlisted vocabulary convention: each style is one
`tokens/＜style＞.css` of custom properties (`--color-*`, `--font-*`,
`--space-*`, `--radius-*`), light scope on `:root`, dark on
`[data-theme="dark"]`. The frame reads only custom properties, so switching
style = swapping one stylesheet. Dark mode follows `prefers-color-scheme`
with a manual override on `data-theme`.

Initial candidate set (user shortlist): **apple**, **expo**,
**dell-1996**, **opencode**. ibm/coinbase/stripe/notion/revolut/linear/
vercel tokens can be generated the same way at any time.

Offline rule: no webfonts. Each token file names a system/bundled stack;
styles whose identity needs a licensed face (Sohne, Aeonik Pro) fall back
per their substitution table.

## Feature baseline (vs openSUSE TW and Agama)

openSUSE TW's installer is the functional ceiling the user benchmarked;
Agama is the only comparable web installer, weaker than TW. Gradus web must
at minimum match the TW capabilities Gradus already models, and close the
two TUI gaps the user called out.

| Capability | TW | Agama | Gradus web plan |
|---|---|---|---|
| Locale / keyboard / timezone **searchable, fully visible lists** | ✅ | partial | ✅ native browser lists + filter box — **no hidden items, no blind selection** (TUI gap #1 closed at the frontend; the TUI can reuse the same filtered-list core later) |
| Storage: multiple disks, per-disk layout, advanced partitioning | ✅ full expert partitioner | partial | ✅ multi-disk answers (`storage.disks` list → per-disk layout), expert fields (fs per partition, mount points, sizes, encryption per disk) — **TUI gap #2 closed in the schema first, then surfaced** |
| Software selection: patterns/presets | ✅ patterns | ✅ | ✅ package-groups (already in core) rendered as checkbox groups |
| Boot: bootloader device, menu timeout, kernel params, serial console | ✅ | ✅ | ✅ (core already models; web renders fields) |
| Network: NIC selection, DHCP/static, DNS | ✅ | ✅ | ✅ (core models) |
| Users: accounts, groups, SSH keys | ✅ | ✅ | users + keys (keys via web paste — TUI omitted) |
| Install source: mirrors, proxies, substitute order | ✅ | ✅ | ✅ (core selection models) |
| Review: inspect + edit generated config before install | ⚠️ (YaST: yes) | ✅ | ✅ core review state machine (inspect file, hand-edit, re-sync) |
| Unattended answers file | AutoYaST | ✅ | ✅ core `--answers` |
| Rollback-friendly review | n/a | n/a | ✅ generations are a Guix property; review page links the mechanism |

Deliberately out of scope (matching the core contract): KDUMP, security
profiles (SELinux/AppArmor), product-registration flows, atomic-update
presets.

## Storage schema upgrade (prerequisite for gap #2)

The answers schema gains an optional multi-disk shape while staying
backward-compatible:

```scheme
(storage
 (mode . simple)                    ; simple | lvm
 (disks . (                         ; NEW: ≥1 disk; single-disk = current shape
   (disk . "/dev/vda")
   (role . system)                  ; system | data
   (esp-size . 1024) (swap-size . 4096) (root-size . 0)
   (filesystem . ext4)
   (encryption . #f))))
```

Rules carried over unchanged: data volumes are adopted never formatted;
LUKS1 for encrypted roots; unknown keys rejected. The wizard/storage core
gains `storage-disks` validation (roles, per-disk minimums, system-role
required exactly once). TUI backport is optional and may follow.

## Progress streaming

Installation progress (`[1/4] … [4/4]`, substitution hits, daemon log
lines) streams to the browser over a poll of `GET /api/progress`
(no WebSocket dependency in the vanilla stack). Failure renders the typed
condition from the core with the contract's exit-code mapping.

## Endpoints (Guile core already owns the state)

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/wizard` | current step, fields (label/kind/value/options), defaults |
| POST | `/api/wizard/next` · `/api/wizard/back` | step transitions (validation runs core-side) |
| POST | `/api/wizard/values` | field updates for the current step |
| POST | `/api/install/begin` | gate 1 acknowledged → prepare + serialize |
| GET | `/api/review` | summary from the declaration file (hand-edit detection) |
| POST | `/api/install/run` | gate 2 acknowledged → init, progress handle |
| GET | `/api/progress` | poller: stage, log tail, exit state |

## Non-goals

- No build tooling, no framework runtime, no remote registry assets.
- No state on the browser side beyond the current step index — refresh
  resumes from the core.
- No dark-mode toggle persistence beyond `localStorage` (cosmetic).
