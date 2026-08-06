# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A VS Code extension for the **Little Man Computer (LMC)** assembly language: a thin TypeScript
extension host that runs a standalone Gleam/Node.js language server. See [README.md](README.md) for
the LMC instruction set and user-facing features.

## Relationship to the sibling `lmc_lsp` repo

There is a second, separate repo, `lmc_lsp` (typically cloned alongside this one, e.g.
`../lmc_lsp`, currently **private**), which owns the actual language server implementation *and* the
LMC lexer/parser/runner. This repo used to carry its own copies of all of that
(`src/lsp/`, `src/lmc/{lexer,parser,analyser,emulator}.gleam`) — all of it has been **deleted**, not
just deprecated, in favor of depending on `lmc_lsp` directly. Sequence of events, for context:

- This repo (`lmc-vscode`, commits from **2026-03-01/02**) was written first, as one monorepo:
  extension host + hand-rolled Gleam LSP + emulator, all under `src/`.
- `lmc_lsp` (commits from **2026-04-26**, ~2 months later) is a **from-scratch, standalone rewrite** —
  a proper 4-layer architecture (`parse/` → `semantic/` → `features/` → `lsp/`), a CST-preserving
  parser (enables `textDocument/formatting`), byte-correct `Content-Length` framing, and a richer
  event-sourced runner. It builds to a self-contained esbuild bundle published as a downloadable
  asset on tagged GitHub releases (`.github/workflows/release.yml` there).
- **The LSP integration is done, with no fallback.** `lsp-server.mjs` here loads the bundle from
  `vendor/lmc-lsp.bundle.mjs`, fetched by `scripts/fetch-lsp-bundle.mjs` via the `gh` CLI (needed
  because `lmc_lsp` is private). A fallback to the legacy in-tree server existed briefly during the
  migration ("keep it until manually validated"); once validated — and after it turned out to be
  broken anyway, see the git history around "Fix broken Result import in the legacy LSP's FFI layer"
  for a bug that had gone undetected for the fallback's entire existence — it was removed as pure
  complexity with no upside: silently degrading to unmaintained code on a missing vendor file is
  worse than failing loudly and telling you to run the fetch script.
- **The Emulator API now also depends on `lmc_lsp` directly, as a Gleam git dependency** (`gleam.toml`:
  `lmc_lsp = { git = "https://github.com/MMarchand-NSI/lmc_lsp.git", ref = "v0.1.1" }`), instead of
  keeping a second, parallel copy of the lexer/parser/runner in this repo. Verified working: `gleam
  deps download` clones the private repo over the `gh` git-credential helper locally, and CI does the
  same over SSH with a read-only deploy key (see Commands below).

**Keep the two repos separate — do not merge them, and do not resurrect an in-tree LSP or
lexer/parser/runner here.** The reason `lmc_lsp` exists as its own repo is editor independence (VS
Code today, Zed planned) — folding it back in would recreate the coupling it was written to remove.
New LSP/language-core features (diagnostics, definition/references logic, etc.) belong in `lmc_lsp`,
not here.

`lmc_lsp` being private means both `scripts/fetch-lsp-bundle.mjs` and `gleam deps download` need
authenticated access to it — locally via `gh auth login`, in CI via the deploy key described below.
Revisit this whole arrangement if/when a public release (VS Code Marketplace, a Zed extension) makes
a private dependency impractical — the fix at that point is just making `lmc_lsp` public, everything
else keeps working as-is.

## Commands

```sh
node scripts/fetch-lsp-bundle.mjs        # required before the extension will run at all —
                                          # fetches vendor/lmc-lsp.bundle.mjs (gitignored)
```

```sh
gleam deps download                # pulls lmc_lsp itself as a git dependency — needs gh auth
                                    # (see "Relationship to lmc_lsp" above)
gleam test                         # run the Emulator API's tests (test/emulator_test.gleam)
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

CI (`.github/workflows/test.yml`) runs on OTP 28 / gleam 1.14.0: it first configures SSH access to
the private `lmc_lsp` repo (writes the `LMC_LSP_DEPLOY_KEY` secret to a key file, rewrites
`https://github.com/` git URLs to SSH via `git config --global url.insteadOf`), then runs `gleam deps
download`, `gleam test`, `gleam format --check src test`. It doesn't touch the LSP bundle at all —
`vendor/`, `fetch-lsp-bundle.mjs`, and `LMC_LSP_DEPLOY_KEY` are three independent things that happen
to depend on the same private repo for two different reasons (LSP bundle vs. Gleam library).

**`LMC_LSP_DEPLOY_KEY`** is a repo secret on `lmc-vscode` holding an ed25519 private key; the matching
public key is registered as a **read-only** deploy key on `lmc_lsp` (`gh repo deploy-key list --repo
MMarchand-NSI/lmc_lsp`). If it's ever rotated: generate a new keypair, `gh repo deploy-key add` the
public half to `lmc_lsp`, `gh secret set LMC_LSP_DEPLOY_KEY` the private half here, delete the old
deploy key, and don't leave the private key material on disk anywhere once it's uploaded.

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
  `vendor/lmc-lsp.bundle.mjs`. Defaults to `v0.1.1`; pass a version to pin a different tag.

None of the LSP protocol logic (diagnostics, hover, completion, formatting, etc.) lives in this repo
any more — see `lmc_lsp`'s own `CLAUDE.md`/`ARCHI.md` for that.

### The Emulator API — a Gleam dependency, not local code

`gleam.toml` depends on `lmc_lsp` as a **git dependency** for programmatic assembling/running of LMC
programs — see the README's "Emulator API" section for the actual usage (`lmc/semantic/pipeline`,
`lmc/runner/{load,run,state}`). There is no local lexer/parser/emulator in this repo to keep in sync
with `lmc_lsp`'s — `test/emulator_test.gleam` is a smoke test exercising the real dependency, not a
test of local code.

### Planned / stub areas

- **`src/webview/app.gleam`** — interactive emulator webview UI (empty stub, not implemented). A
  webview is inherently VS Code-specific (unlike DAP, which moved to `lmc_lsp` — see its
  `CLAUDE.md`), so this stays here. When work on it starts, it should drive `lmc_lsp`'s
  `runner/` (the same dependency the Emulator API already uses) — there is no local emulator to fall
  back to.

When implementing it, follow the existing pattern used by `lmc_lsp`: Gleam core logic + a small
`@external(javascript, ...)` FFI file colocated with the `.gleam` module for the Node-specific I/O.
