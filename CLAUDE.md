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
  `lmc_lsp = { git = "https://github.com/MMarchand-NSI/lmc_lsp.git", ref = "v0.1.6" }`), instead of
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
gleam build && node scripts/build-webview.mjs  # required before "LMC: Open Emulator" shows
                                                # anything — bundles src/webview/ for the browser
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
Development Host with `vscode-extension` as the dev path, with `examples/` (a valid program and a
deliberately broken one) opened automatically so there's always something to test against without
manually opening a folder each time. `vscode-extension/.vscode/launch.json` has an equivalent "Run
Extension" config for when `vscode-extension/` itself is the open workspace instead of the repo root
(it used to be misnamed `lauch.json` and silently invisible to VS Code — fixed).

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
  `vendor/lmc-lsp.bundle.mjs`. Defaults to `v0.1.6`; pass a version to pin a different tag.

None of the LSP protocol logic (diagnostics, hover, completion, formatting, etc.) lives in this repo
any more — see `lmc_lsp`'s own `CLAUDE.md`/`ARCHI.md` for that.

### The Emulator API — a Gleam dependency, not local code

`gleam.toml` depends on `lmc_lsp` as a **git dependency** for programmatic assembling/running of LMC
programs — see the README's "Emulator API" section for the actual usage (`lmc/semantic/pipeline`,
`lmc/runner/{load,run,state}`). There is no local lexer/parser/emulator in this repo to keep in sync
with `lmc_lsp`'s — `test/emulator_test.gleam` is a smoke test exercising the real dependency, not a
test of local code.

### Emulator webview (`src/webview/`, `vscode-extension/webviewPanel.ts`)

Runs **in the browser, inside the webview** — not round-tripped through the extension host on every
step. `src/webview/*.gleam` compiles to JS (same as any other Gleam module here) and gets bundled for
the browser by `scripts/build-webview.mjs` (esbuild, `--platform=browser`, `--global-name=LmcApp` since
Gleam's `main()` is just an export — nothing calls it on its own; `index.html` does
`LmcApp.main()` after loading the bundle).

- **`webview/model.gleam`** — pure state/transitions, no FFI, `gleam test`-covered. Wraps `lmc_lsp`'s
  `runner` (`load`/`run`/`state`) directly, same as the Emulator API — no local emulator. Also owns
  `address_to_line`/`line_to_address` (built from `load.address_offsets`, **not** re-derived by
  assuming address == line index — that assumption is exactly the v0.1.5 bug in `lmc_lsp`, see its
  ARCHI.md) for the editor <-> webview sync, and `current_address`/`current_line`, which account for
  a real runner quirk: PC advances during the *fetch* phase, before `INP`'s execute phase can
  discover there's no input — so when `WaitingForInput`, PC already points one past the instruction
  actually paused on.
- **`webview/render.gleam`** — `Model` -> single JSON payload (`gleam_json`), also `gleam test`-covered.
  One `ffi.render(json)` call re-renders the whole memory grid each time; 100 cells is cheap enough
  that a diffing renderer isn't worth the complexity.
- **`webview/app.gleam`** — entry point, wires `model`+`render` to `ffi.gleam`. Not unit-tested itself
  (pure FFI wiring), same reasoning as `lmc_lsp`'s `lsp/server.gleam` `serve` loop vs. its testable
  handlers.
- **`webview/ffi.gleam` + `app_ffi.mjs`** — DOM + `acquireVsCodeApi().postMessage` bridge, same
  `ref`/`deref`/`setRef` mutable-cell pattern `lmc_lsp`'s `lsp/ffi.gleam` uses for server state
  (reimplemented here, not shared — the two repos stay independent). Browser FFI, not Node FFI —
  don't reach for `node:*` imports in this file.
- **`vscode-extension/webviewPanel.ts`** — creates the panel (`retainContextWhenHidden: true`, so
  stepping progress survives switching tabs), fills in `webview/index.html`'s `{{cspSource}}` /
  `{{styleUri}}` / `{{scriptUri}}` / `{{nonce}}` placeholders, and relays exactly two message
  directions: host->webview (`setSource`, `cursorLine`) and webview->host (`ready`, `revealLine`).
  Command `lmc.openEmulator` ("LMC: Open Emulator") is registered in `client.ts`.

**Editor <-> webview sync is the actual point of this being a webview** instead of embedding an
existing standalone LMC simulator (plenty exist as plain websites) — moving the cursor in the editor
outlines the corresponding mailbox; clicking a mailbox reveals its source line. Don't regress this in
future work on the webview; it's the reason to have one.

Not covered by any GUI-free test — verified so far by (a) `gleam test` on `model.gleam`/`render.gleam`,
and (b) manually driving the built bundle inside a minimal `node:vm`-stubbed DOM (see chat history /
git history for the throwaway scripts; not committed). Actually opening the panel in a real Extension
Development Host has not been done by an agent in this repo — see "Status" below, it's the top item.

## Status: where things stand, what's left

Done and working, each verified by actually running it (`gleam test`, or driving the built bundle —
never just code review):

- LSP integration (`lsp-server.mjs` → `vendor/lmc-lsp.bundle.mjs`), no fallback.
- Emulator API as an `lmc_lsp` git dependency; CI pulls it over the `LMC_LSP_DEPLOY_KEY` deploy key.
- `lmc_lsp`'s own release pipeline, publishing tagged bundles — this repo currently pinned to `v0.1.6`.
- Emulator webview MVP: memory grid, registers, I/O tray, step/run/reset, a collapsible Fetch/Decode/
  Execute panel, bidirectional editor↔webview sync (cursor→highlight, click→reveal line, debug-
  session-style current-line decoration).
- A long list of real bugs caught by actually exercising the extension/webview, not by guessing:
  hover-on-operand, missing HLT/length diagnostics, a confusing mnemonic error message, blank lines
  silently becoming an implicit HLT (`lmc_lsp`, the most serious one), a stale `TextEditor` reference
  breaking sync across tab switches, mailbox clicks opening a new tab instead of reusing an existing
  one, Step behaving like Run, Run collapsing into Step after providing input, PC/ACC resetting on
  refocus, Fetch/Decode/Execute events splitting across an input pause, a redundant post-INP
  accumulator-changed event, and the Decode line reading like reconstructed source code.

Still open, roughly in the order it's worth tackling them:

1. **The webview has never been opened in a real Extension Development Host by an agent here.**
   Every fix above was validated with `gleam test` plus a throwaway `node:vm`-stubbed-DOM script
   driving the *built bundle*, never VS Code itself — so `webviewPanel.ts`'s placeholder
   substitution and the actual panel chrome (`{{cspSource}}` / `{{styleUri}}` / `{{scriptUri}}` /
   `{{nonce}}` in `webview/index.html`) are unverified. Do this before trusting the UI wiring itself,
   independent of how solid the model/render logic underneath now is.
2. **No committed smoke-test script.** The `node:vm` scripts that caught the Step/Run/reset/decode-
   text bugs above only ever lived in a session's scratchpad — worth promoting one into a committed
   `scripts/` tool so the next round of webview work doesn't start from zero.
3. **`lmc_lsp` is still private**, so `fetch-lsp-bundle.mjs` and `gleam deps download` both need `gh
   auth`/the deploy key — fine for solo development, but blocks any real distribution. No public-
   release work (Marketplace listing, making `lmc_lsp` public) has started.
4. **No Zed extension exists yet.** Editor independence via `lmc_lsp` was the explicit reason to keep
   the two repos separate (see "Relationship to lmc_lsp" above) — today `lmc_lsp` only has this one
   VS Code client using it.
5. **The VS Code extension itself isn't packaged/published anywhere** — `npx vsce package` works
   locally, but there's no CI job building a `.vsix`, let alone a Marketplace listing.
