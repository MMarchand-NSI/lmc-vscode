# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A VS Code extension for the **Little Man Computer (LMC)** assembly language: a Gleam-implemented
language server (lexer → parser → analyser) plus a separate emulator, exposed to VS Code through a
thin TypeScript client. See [README.md](README.md) for the LMC instruction set and user-facing features.

## Relationship to the sibling `lmc_lsp` repo

There is a second, separate repo, `lmc_lsp` (typically cloned alongside this one, e.g. `../lmc_lsp`),
that matters for anyone touching the LSP core here. Sequence of events:

- This repo (`lmc-vscode`, commits from **2026-03-01/02**) was written first, as one monorepo:
  extension host + hand-rolled Gleam LSP + emulator, all under `src/`.
- `lmc_lsp` (commits from **2026-04-26**, ~2 months later) is a **from-scratch, standalone rewrite of
  just the LSP server part** — not a fork, a new repo. It supersedes the design of this repo's
  `src/lmc/` + `src/lsp/`: a proper 4-layer architecture (`parse/` → `semantic/` → `features/` →
  `lsp/`), a CST-preserving parser (enables a `textDocument/formatting` feature this repo doesn't
  have), byte-correct `Content-Length` framing (this repo's `lsp_ffi.mjs` framing is char/line based
  and likely mishandles non-ASCII content the same way `lmc_lsp`'s `ARCHI.md` documents as a bug it
  had to fix), and a richer event-sourced runner (the counterpart to `emulator.gleam` here).
  `lmc_lsp` builds to a self-contained esbuild bundle (`dist/lmc-lsp.bundle.mjs`) explicitly meant to
  be dropped into a VS Code extension without needing a Gleam toolchain at install time.
- **`lmc_lsp` has no extension host code of its own** (no `client.ts`, no `package.json` for a VS Code
  extension) — that shell only exists here, in `vscode-extension/`.
- **The integration has not happened yet.** `lsp-server.mjs` (repo root) still imports the old
  in-tree compiled server (`build/dev/javascript/lmc_vscode/lsp/server.mjs`), not `lmc_lsp`'s bundle.

Practical implication: treat `src/lmc/` and `src/lsp/` in *this* repo as the legacy implementation,
likely to be replaced by pointing `lsp-server.mjs` at `lmc_lsp`'s bundle once that integration is
done. Don't invest in fixing framing/architecture issues here that `lmc_lsp` has already solved
differently — check there first. New LSP features (definition/references logic, diagnostics, etc.)
should probably land in `lmc_lsp`, not here, unless the user says otherwise.

**Keep the two repos separate — do not merge them.** The reason to have a standalone LSP server at
all is editor independence: the goal is to also use it from other LSP clients (e.g. Zed), not just
VS Code, so `lmc_lsp` needs to stay usable without any VS Code-specific code around it. Folding it
back into this repo would just recreate the coupling it was written to remove.

What *should* change is how this repo depends on it: right now the only path from `lmc_lsp` to here
is a manual copy of `dist/lmc-lsp.bundle.mjs` between two local clones, which silently goes stale.
`lmc_lsp` now has `.github/workflows/release.yml`, which attaches its built bundle to a GitHub
release whenever a `v*.*.*` tag is pushed there — `lsp-server.mjs` here should be updated to fetch a
specific tagged release's `lmc-lsp.bundle.mjs` (e.g. at extension build/package time) instead of
reading a path into a sibling working directory. A future Zed extension would be a third, similarly
small repo consuming the same tagged releases — the pattern here (`vscode-extension/` as thin
client-specific glue around an externally-built server) is the template for it.

## Commands

```sh
gleam deps download                # fetch dependencies (also done by CI)
gleam test                         # compile + run all Gleam tests (gleeunit, target=javascript/node)
gleam build                        # compile to build/dev/javascript/ — required before running the LSP,
                                    # since lsp-server.mjs imports the compiled output
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

To manually try the extension in VS Code: run `gleam build` first, then launch the
"Run LMC Extension" debug config (`.vscode/launch.json`, `F5`) — it starts an Extension
Development Host with `vscode-extension` as the dev path.

CI (`.github/workflows/test.yml`) runs on OTP 28 / gleam 1.13.0: `gleam deps download`,
`gleam test`, `gleam format --check src test`.

## Architecture

The extension is two separate processes talking LSP over stdio:

```
VS Code ⇄ (LSP over stdio) ⇄ node lsp-server.mjs ⇄ compiled Gleam (lexer → parser → analyser)
```

- **`vscode-extension/client.ts`** — the extension host. On activate, it spawns
  `node <repo-root>/lsp-server.mjs` (one directory above the extension itself) via
  `vscode-languageclient`, scoped to files with language id `lmc`.
- **`lsp-server.mjs`** (repo root) — trivial entry point: imports `main` from
  `build/dev/javascript/lmc_vscode/lsp/server.mjs` (the compiled Gleam output) and calls it.
  This is why `gleam build` must run before the server can start.
- **`src/lsp/server.gleam`** — the actual language server. It is a hand-rolled JSON-RPC
  server (no LSP library): a minimal `Json` union + encoder, a `handle(msg, store, ...)`
  dispatcher that pattern-matches on the LSP `method` string, and an in-memory
  `Dict(uri, Document)` store. `Document` holds the raw text plus the last `analyser.Analysis`.
  Sync is `Full` (`textDocumentSync = 1`) — the *entire* document is re-lexed/parsed/analysed
  on every `didOpen`/`didChange`, there is no incremental analysis.
- **`src/lsp/lsp_ffi.mjs`** — the Node.js I/O layer, wired in via `@external(javascript, ...)`.
  Handles LSP `Content-Length` framing over stdin/stdout (synchronous byte-level reads), plus
  dynamic field accessors (`getStr`/`getInt`/`getNested`/`isDefined`) because Gleam's `Dynamic`
  can't destructure parsed JSON directly.

### Compilation pipeline (`src/lmc/`)

Each document is analysed independently through this pipeline (also usable standalone, see the
"Emulator API" section of the README):

1. **`lexer.gleam`** — tokenizes **line by line** (`nibble/lexer` per line, then a `Newline`
   token appended), which is what lets the parser and diagnostics stay line-oriented. Identifiers
   are uppercased at this stage (labels/mnemonics are case-insensitive). Comments start with `//`
   or `;` (not `#` — note the code, not just the README's prose table, is the source of truth here).
2. **`parser.gleam`** — `nibble` combinator parser producing the AST (`Program` → `Line` →
   `Instruction`). A leading identifier is treated as a label unless it matches a known mnemonic.
3. **`analyser.gleam`** — two-pass semantic analysis over the AST:
   - Pass 1 collects label definitions, flagging duplicates.
   - Pass 2 checks that every operand label resolves and builds the `Symbol` table
     (`name`, `defined_at`, `referenced_at`) that powers hover / go-to-definition / find-references.
   - Plus standalone checks: missing `HLT` (warning) and >100 instructions (error).
   - `find_definition`, `all_symbols`, `diagnostics_by_severity` are the query surface the LSP
     handlers in `server.gleam` call into.
4. **`emulator.gleam`** — a separate assembler + VM, **not currently wired into the LSP** (no
   server handler runs a program). Assembles the AST into 100 three-digit LMC words
   (`opcode * 100 + addr`; addresses assigned by walking lines in source order, with a label on a
   blank line carried forward to the next instruction). Supports both batch execution (`run`,
   input supplied upfront) and interactive stepping (`step` / `NeedsInput` / `provide_input`, for
   a future UI that needs to pause on `INP`).

### Planned / stub areas (empty files, not implemented yet)

- **`src/dap/server.gleam`** — Debug Adapter Protocol server (empty stub).
- **`src/webview/app.gleam`** — interactive emulator webview UI (empty stub).
- **`ffi/transport.mjs`** (repo root) — empty stub, presumably the future DAP counterpart to
  `src/lsp/lsp_ffi.mjs`.
- **`src/lmc_vscode.gleam`** — the default `gleam new` entry point stub (`"Hello from
  lmc_vscode!"`); unrelated to the LSP/extension, not invoked by anything real.

When implementing any of the above, follow the existing pattern: Gleam core logic + a small
`@external(javascript, ...)` FFI file colocated with the `.gleam` module for the Node-specific I/O.
