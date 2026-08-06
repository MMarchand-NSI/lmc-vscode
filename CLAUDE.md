# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A VS Code extension for the **Little Man Computer (LMC)** assembly language: a thin TypeScript
extension host that runs a standalone Gleam/Node.js language server, plus an independent Gleam
Emulator API for programmatic use. See [README.md](README.md) for the LMC instruction set and
user-facing features.

## Relationship to the sibling `lmc_lsp` repo

There is a second, separate repo, `lmc_lsp` (typically cloned alongside this one, e.g.
`../lmc_lsp`, currently **private**), which owns the actual language server implementation. This
repo used to carry its own hand-rolled LSP server (`src/lsp/`, `src/lmc/analyser.gleam`) — that code
has been **deleted**, not just deprecated, in favor of `lmc_lsp`. Sequence of events, for context:

- This repo (`lmc-vscode`, commits from **2026-03-01/02**) was written first, as one monorepo:
  extension host + hand-rolled Gleam LSP + emulator, all under `src/`.
- `lmc_lsp` (commits from **2026-04-26**, ~2 months later) is a **from-scratch, standalone rewrite of
  just the LSP server** — a proper 4-layer architecture (`parse/` → `semantic/` → `features/` →
  `lsp/`), a CST-preserving parser (enables `textDocument/formatting`), byte-correct
  `Content-Length` framing, and a richer event-sourced runner. It builds to a self-contained esbuild
  bundle and publishes it as a downloadable asset on tagged GitHub releases
  (`.github/workflows/release.yml` there).
- The integration is done: `lsp-server.mjs` here loads that bundle from `vendor/lmc-lsp.bundle.mjs`,
  fetched by `scripts/fetch-lsp-bundle.mjs` via the `gh` CLI (needed because `lmc_lsp` is private).
  There is **no fallback** — this repo no longer contains an LSP implementation of its own. A
  fallback existed briefly during the migration (kept "until manually validated"); once validated —
  and after it turned out to be broken anyway (see the git history around "Fix broken Result import
  in the legacy LSP's FFI layer" for the bug that had gone undetected) — it was removed as pure
  complexity with no upside: silently degrading to unmaintained code on a missing vendor file is
  worse than failing loudly and telling you to run the fetch script.

**Keep the two repos separate — do not merge them, and do not resurrect an in-tree LSP server here.**
The reason `lmc_lsp` exists as its own repo is editor independence (VS Code today, Zed planned) —
folding it back in would recreate the coupling it was written to remove. New LSP/language-core
features (diagnostics, definition/references logic, etc.) belong in `lmc_lsp`, not here.

`lmc_lsp` being private means anyone building this extension needs `gh` authenticated with access to
it (see README prerequisites) — revisit if/when a public release (VS Code Marketplace, a Zed
extension) makes that impractical.

## Commands

```sh
node scripts/fetch-lsp-bundle.mjs        # required before the extension will run at all —
                                          # fetches vendor/lmc-lsp.bundle.mjs (gitignored)
```

```sh
gleam test                         # run the Emulator API's tests (lexer, parser, emulator) —
                                    # unrelated to the LSP, see Architecture below
gleam build                        # compile the Emulator API to build/dev/javascript/
gleam format src test              # auto-format
gleam format --check src test      # what CI runs; do this before committing
```

There is no built-in `gleam test` flag to run a single test by name — `gleeunit` discovers every
`*_test` function under `test/` and runs them all (currently fast, well under a second). To isolate
one test while debugging, comment out the others temporarily.

VS Code extension (separate npm project in `vscode-extension/`):

```sh
cd vscode-extension
npm install
npx tsc              # or `npm run compile` — compiles client.ts to out/client.js
npx vsce package      # package as .vsix
```

To manually try the extension in VS Code: run `node scripts/fetch-lsp-bundle.mjs` first, then launch
the "Run LMC Extension" debug config (`.vscode/launch.json`, `F5`) — it starts an Extension
Development Host with `vscode-extension` as the dev path.

CI (`.github/workflows/test.yml`) runs on OTP 28 / gleam 1.14.0: `gleam deps download`, `gleam test`,
`gleam format --check src test`. It only exercises the Emulator API — it doesn't fetch or touch the
LSP bundle at all.

## Architecture

```
VS Code ←—LSP (stdio)—→ lsp-server.mjs → vendor/lmc-lsp.bundle.mjs (fetched from lmc_lsp releases)
```

- **`vscode-extension/client.ts`** — the extension host. On activate, it spawns
  `node <repo-root>/lsp-server.mjs` (one directory above the extension itself) via
  `vscode-languageclient`, scoped to files with language id `lmc`.
- **`lsp-server.mjs`** (repo root) — imports `main` from `./vendor/lmc-lsp.bundle.mjs` and calls it.
  Exits with a clear error (not a silent fallback) if that file is missing — run
  `scripts/fetch-lsp-bundle.mjs` first.
- **`scripts/fetch-lsp-bundle.mjs`** — downloads a tagged `lmc_lsp` release asset via `gh release
  download` (plain `fetch()` won't work, the repo is private — see the script's own comments) into
  `vendor/lmc-lsp.bundle.mjs`. Defaults to `v0.1.0`; pass a version to pin a different tag.

None of the LSP protocol logic (diagnostics, hover, completion, formatting, etc.) lives in this repo
any more — see `lmc_lsp`'s own `CLAUDE.md`/`ARCHI.md` for that.

### The Emulator API (`src/lmc/`) — unrelated to the LSP

`src/lmc/{lexer,parser,emulator}.gleam` is a **separate, standalone concern**: a small Gleam library
for assembling and running LMC programs programmatically (see the README's "Emulator API" section),
not used by the extension or the language server at all. It exists here — rather than depending on
`lmc_lsp`'s own, more capable `parse/`/`runner/` layers — because reusing those would mean either a
Gleam git dependency on a private repo (works locally via the `gh` git-credential helper, but needs
a deploy key or PAT wired into this repo's CI as a secret) or waiting for `lmc_lsp` to publish to
Hex; neither has been done. If that changes, this local copy plus its tests
(`test/lexer_test.gleam`, `test/parser_test.gleam`, `test/emulator_test.gleam`) and the
`nibble`/`gleam_regexp` dependencies they pull in should be replaced by depending on `lmc_lsp`
directly rather than maintaining two parallel Gleam implementations of the same lexer/parser.

1. **`lexer.gleam`** — tokenizes **line by line** (`nibble/lexer` per line, then a `Newline` token
   appended). Identifiers are uppercased (labels/mnemonics are case-insensitive). Comments start
   with `//` or `;` (not `#` — the code, not just the README's prose table, is the source of truth
   here).
2. **`parser.gleam`** — `nibble` combinator parser producing the AST (`Program` → `Line` →
   `Instruction`). A leading identifier is treated as a label unless it matches a known mnemonic.
3. **`emulator.gleam`** — assembler + VM. Assembles the AST into 100 three-digit LMC words
   (`opcode * 100 + addr`; addresses assigned by walking lines in source order, with a label on a
   blank line carried forward to the next instruction). Supports both batch execution (`run`, input
   supplied upfront) and interactive stepping (`step` / `NeedsInput` / `provide_input`, for a future
   UI that needs to pause on `INP` — see `src/webview/app.gleam` below).

### Planned / stub areas

- **`src/webview/app.gleam`** — interactive emulator webview UI (empty stub, not implemented). A
  webview is inherently VS Code-specific (unlike DAP, which moved to `lmc_lsp` — see its
  `CLAUDE.md`), so this stays here. When work on it starts, decide then whether it should drive
  `src/lmc/emulator.gleam` (current local copy) or `lmc_lsp`'s runner (see the Emulator API note
  above) — don't assume the former just because it's already in this repo.

When implementing it, follow the existing pattern used by `lmc_lsp`: Gleam core logic + a small
`@external(javascript, ...)` FFI file colocated with the `.gleam` module for the Node-specific I/O.
