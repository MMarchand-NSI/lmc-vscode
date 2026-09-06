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
- **The LSP integration is done, with no fallback.** `vscode-extension/lsp-server.mjs` loads the
  bundle from `vscode-extension/vendor/lmc-lsp.bundle.mjs`, **built** by
  `scripts/build-lsp-bundle.mjs` out of the Gleam dependency below. It used to be *downloaded* from
  a tagged release instead, which is what made this repo carry the same version twice; see the
  "one dependency, one pin" entry in the done list. A fallback to the legacy in-tree server existed briefly during the
  migration ("keep it until manually validated"); once validated — and after it turned out to be
  broken anyway, see the git history around "Fix broken Result import in the legacy LSP's FFI layer"
  for a bug that had gone undetected for the fallback's entire existence — it was removed as pure
  complexity with no upside: silently degrading to unmaintained code on a missing vendor file is
  worse than failing loudly and telling you to run the build script.
- **The Emulator API now also depends on `lmc_lsp` directly, as a Gleam git dependency** (`gleam.toml`:
  `lmc_lsp = { git = "https://github.com/MMarchand-NSI/lmc_lsp.git", ref = "v0.8.1" }`), instead of
  keeping a second, parallel copy of the lexer/parser/runner in this repo. Verified working: `gleam
  deps download` clones the private repo over the `gh` git-credential helper locally, and CI does the
  same over SSH with a read-only deploy key (see Commands below).

**Keep the two repos separate — do not merge them, and do not resurrect an in-tree LSP or
lexer/parser/runner here.** The reason `lmc_lsp` exists as its own repo is editor independence (VS
Code today, Zed planned) — folding it back in would recreate the coupling it was written to remove.
New LSP/language-core features (diagnostics, definition/references logic, etc.) belong in `lmc_lsp`,
not here.

`lmc_lsp` being private means `gleam deps download` needs authenticated access to it — locally via
`gh auth login` (its git-credential helper), in CI via the deploy key described below. That single
clone is now the only thing this repo takes from that one.
Revisit this whole arrangement if/when a public release (VS Code Marketplace, a Zed extension) makes
a private dependency impractical — the fix at that point is just making `lmc_lsp` public, everything
else keeps working as-is.

## Commands

```sh
gleam build && node scripts/build-lsp-bundle.mjs  # required before the extension will run at all
                                          # — bundles the lmc_lsp dependency into
                                          # vscode-extension/vendor/lmc-lsp.bundle.mjs
node scripts/check-lsp.mjs               # runs lmc_lsp's own 48-assertion LSP integration suite
                                          # against that bundle (needs `gleam deps download`)
gleam build && node scripts/build-webview.mjs  # required before "LMC: Open Emulator" shows
                                                # anything — bundles src/webview/ for the browser
node scripts/smoke-webview.mjs           # drives that built bundle in a real DOM, playing the
                                          # host's half of the protocol — run it after touching
                                          # the webview, and after build-webview.mjs, not before
node scripts/check-examples.mjs          # every examples/*.lmc parses clean (except broken.lmc)
                                          # and comes back unchanged from the formatter; the
                                          # unit-* series also runs the "Entrée : … Sortie : …"
                                          # cases in its own header
                                          # (needs `gleam build` first, like build-webview.mjs)
node scripts/check-manifest.mjs          # checks the extension manifest against what is true
                                          # elsewhere — today, that lmc.locale offers exactly the
                                          # languages lmc_lsp speaks
node scripts/check-grammar.mjs           # tokenizes with the real Oniguruma engine and checks the
                                          # TextMate grammar against lmc_lsp's lexer — the mnemonic
                                          # and register tables, and what counts as a name
                                          # (needs `gleam build` *and* `gleam deps download`)
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
npm run compile      # compiles client.ts to out/client.js — prefer this over `npx tsc`,
                     #   which downloads and runs an unrelated registry package named
                     #   `tsc` if the local typescript isn't resolvable from the cwd
npx vsce package      # package as .vsix
```

To manually try the extension in VS Code: run `node scripts/build-lsp-bundle.mjs` first, then launch
the "Run LMC Extension" debug config (`.vscode/launch.json`, `F5`) — it starts an Extension
Development Host with `vscode-extension` as the dev path, with `examples/` (a valid program and a
deliberately broken one) opened automatically so there's always something to test against without
manually opening a folder each time. `vscode-extension/.vscode/launch.json` has an equivalent "Run
Extension" config for when `vscode-extension/` itself is the open workspace instead of the repo root
(it used to be misnamed `lauch.json` and silently invisible to VS Code — fixed).

That config passes `--disable-extension=GitHub.copilot-chat`, and the reason is a crash, not a
preference. The Extension Development Host inherits the user's extensions, and VS Code's built-in
Copilot activates itself there (`activationEvent: 'onChatSession:copilotcli'`, 144 ms after the host
starts) and completes as you type without being asked. On 2026-09-05 its `TikToken worker` thread
took a fatal signal 5 twice, at 06:08:59 and 06:25:51 (`dmesg`: `trap int3 ... in node`, no OOM, 21
GiB free), which kills the whole extension host process. Under `F5` that process is the debuggee, so
its death closes the development window, mid-edit, with no error dialog. Both crashed hosts are the
ones that had activated `lmc-vscode.lmc-vscode`; the LMC extension itself is not implicated (its
language server is a separate forked process, plain JS, no native module). Why the tokenizer aborts
is unknown, and the flag does not answer it, it only keeps it out of this window. If a development
window dies again, `dmesg | grep CaptureCrash` says in one line whether it is the same cause.

CI (`.github/workflows/test.yml`) runs on gleam 1.18.1 and node 20, with no Erlang at all (the
gleam binary is standalone and this project targets JavaScript): it first configures SSH access to
the private `lmc_lsp` repo (writes the `LMC_LSP_DEPLOY_KEY` secret to a key file, rewrites
`https://github.com/` git URLs to SSH via `git config --global url.insteadOf`), then runs `gleam deps
download`, `gleam test`, `gleam format --check src test`, **then the five checks and the packaging
chain**: `build-lsp-bundle` + `check-lsp`, `check-examples`, `check-grammar`, `check-manifest`,
`build-webview` +
`smoke-webview`, then `npm run compile` + `npx vsce package` with a `unzip -l` that asserts the
archive really carries `lsp-server.mjs` and the bundle. That last part is there because `vsce
package` had already been broken twice with nothing to notice it. The `npm ci` those need is the
only slow step. It doesn't touch a downloaded bundle at all —
the LSP bundle and the Gleam library both come out of the one clone that `gleam deps download`
makes, so `LMC_LSP_DEPLOY_KEY` is what gives CI access to all of it.

**`LMC_LSP_DEPLOY_KEY`** is a repo secret on `lmc-vscode` holding an ed25519 private key; the matching
public key is registered as a **read-only** deploy key on `lmc_lsp` (`gh repo deploy-key list --repo
MMarchand-NSI/lmc_lsp`). If it's ever rotated: generate a new keypair, `gh repo deploy-key add` the
public half to `lmc_lsp`, `gh secret set LMC_LSP_DEPLOY_KEY` the private half here, delete the old
deploy key, and don't leave the private key material on disk anywhere once it's uploaded.

## Architecture

```
VS Code ←—LSP (stdio)—→ vscode-extension/lsp-server.mjs → vendor/lmc-lsp.bundle.mjs (from lmc_lsp releases)
```

- **`vscode-extension/client.ts`** — the extension host. On activate, it hands
  `<extensionPath>/lsp-server.mjs` (inside the extension, so that it ships in the `.vsix`) to
  `vscode-languageclient` as a `module`, scoped to files with language id `lmc`. `module` and not
  `command: "node"`: the library then forks it with `cp.fork`, i.e. `process.execPath` under
  `ELECTRON_RUN_AS_NODE=1` — **the Node inside VS Code**. Spawning `"node"` required one on the
  user's PATH, so the extension did not start at all for anyone who has VS Code but no separate
  Node install.
- **`vscode-extension/lsp-server.mjs`** — imports `main` from `./vendor/lmc-lsp.bundle.mjs` and
  calls it. It sits inside the extension, not at the repo root where it used to, because an
  installed extension has no repo around it: `vsce package` archives `vscode-extension/` and
  nothing else, so a server one directory above would simply not be in the `.vsix`.
  Exits with a clear error (not a silent fallback) if that file is missing — run
  `scripts/build-lsp-bundle.mjs` first.
- **`scripts/build-lsp-bundle.mjs`** — esbuild over `build/dev/javascript/lmc_lsp/main.mjs`, the
  dependency as `gleam build` compiled it, into `vscode-extension/vendor/lmc-lsp.bundle.mjs`. It
  does not repeat the esbuild options: it reads them out of the dependency's own `package.json`
  (`build:minify`) and fails loudly if that script stops having the expected shape. **There is one
  pin now, `gleam.toml`'s `ref`.**
- **`scripts/check-lsp.mjs`** — runs `lmc_lsp`'s own `test_lsp.mjs --bundle` against that bundle,
  48 assertions over the whole protocol surface. It exists because the bundle is no longer the
  artefact upstream CI tested; making it face the same suite is what replaces that guarantee.
  `test_lsp.mjs` loads `./dist/lmc-lsp.bundle.mjs` relative to the cwd, so the script builds a
  throwaway directory with that symlink.

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
  ARCHI.md) for the editor <-> webview sync, and `current_address`/`current_line`, which subtract 1
  when the machine is stopped (`WaitingForInput` **or** `Halted`): the runner increments PC during
  the *fetch* phase — which is where real hardware increments it too, and is why `JSR` can save `LR`
  by copying PC with no arithmetic — so a stopped machine's PC already points one past the
  instruction that stopped it. The register panel still shows PC's raw value, deliberately: the
  number is true (an x86 resuming from `HLT` finds its saved IP past the `HLT` as well); what was
  wrong was marking the *next* cell as the current one. Since these programs put their `DAT`s after
  the `HLT`, a halted machine used to claim it was about to execute its own data, and decorated that
  line in the editor. `Halted` was missed when `WaitingForInput`
  was fixed; the reverse case — execution falling *into* a `DAT`, which halts because opcode 0 is
  `HLT` — is what makes `pc - 1` the right correction rather than blanking the highlight, and has
  its own test. **The Fetch phase of the cycle panel says that increment out loud**, as a second
  line under Fetch (`"PC 0 → 1 (incrémenté pendant la lecture, avant le décodage)"`, rendered as a
  sub-list exactly as Execute already is when it carries several actions): reading the word and
  advancing the counter are two acts of one phase, and naming the second is what makes the register
  panel's off-by-one legible instead of mysterious. That line is *derived*, not reported: the runner
  emits no event for the increment, so `event_phase_details` computes `address + 1` from
  `Fetched(address, raw)`. Safe because `do_fetch` in `lmc_lsp`'s `runner/step_phase.gleam` is the
  only place that emits `Fetched`, and it always sets `program_counter + 1`; if that ever stops
  being 1, this is the single place to fix. It also owns **the screen**
  (`screen_width`/`screen_height`/`palette_size` = 32, 32,
  8, and the lit points): `lmc_lsp`'s runner emits `PixelPlotted(x, y, colour)` and checks no bound
  at all, deliberately — a screen is a device, so its size is the display's business, exactly as
  `OUT` does not check the width of the terminal. A point outside the screen or outside the palette
  is not drawn, and the Execute line of the cycle panel says so rather than leaving an unexplained
  blank; colour 0 is the background, so lighting a point in 0 erases it, no extra instruction
  needed. The points live in the `Model` and not in `MachineState` because the runner does not keep
  them — `OUT`'s output accumulates in the machine, `PLT`'s does not. Reset and load clear the
  screen; the RGB values themselves are in `app_ffi.mjs`, the only module that paints.
- **`webview/text/`** — **tout ce que le panneau affiche**, split exactly the way `lmc_lsp` splits
  its own since v0.8.1, and for the same reason: adding a language becomes one more file and one
  more arm, with no existing translation touched.
  - `message.gleam` — the **values** and nothing else. `Text` for what the machine does (the
    Fetch/Decode/Execute lines, the load and assembly failures) and `Label` for the panel's
    furniture (buttons, headings, legend, tooltips), which used to live in `index.html` and
    therefore in one language, out of the compiler's reach — `index.html` now carries `data-ui`
    attributes and no prose at all. It also holds the fragments that are **not** prose
    (`shortcut`, `three_cells`): machine words and addresses, written once so two languages cannot
    drift on a fact.
  - `french.gleam`, `english.gleam` — one language per file, `render` and `label`, nothing else.
  - `locale.gleam` — the dispatch, and the only place to touch to add a language. It does **not**
    redefine `Locale`: that is `lmc_lsp`'s, imported `as server`, so the panel and the diagnostics
    cannot answer the same setting differently and a runner error (`message.Message`) renders in
    the same language without being copied here.
  No layer builds a sentence: `model.gleam` returns values, and only `locale.gleam` knows the
  language. What that bought, exactly as upstream: the model tests compare values
  (`message.FetchRead(0, 5003)`), so rephrasing breaks none of them — and the per-language tests
  loop over every locale the server knows, so Spanish is already covered the day it gets its file.
  **The next step is data files**, and this split is what makes it cheap: only the language modules
  get replaced, the types and every caller stay put. See the open list.
- **`webview/render.gleam`** — `Model` -> single JSON payload (`gleam_json`), also `gleam test`-covered.
  One `ffi.render(json)` call re-renders the whole memory grid each time; 100 cells is cheap enough
  that a diffing renderer isn't worth the complexity. The screen is the one thing sent
  *sparsely* — only the lit points, not 1024 cells — because the canvas repaints its own
  background first; an unlit screen is an empty array, not a thousand zeroes.
- **`webview/app.gleam`** — entry point, wires `model`+`render` to `ffi.gleam`. Not unit-tested itself
  (pure FFI wiring), same reasoning as `lmc_lsp`'s `lsp/server.gleam` `serve` loop vs. its testable
  handlers.
- **`webview/ffi.gleam` + `app_ffi.mjs`** — DOM + `acquireVsCodeApi().postMessage` bridge, same
  `ref`/`deref`/`setRef` mutable-cell pattern `lmc_lsp`'s `lsp/ffi.gleam` uses for server state
  (reimplemented here, not shared — the two repos stay independent). Browser FFI, not Node FFI —
  don't reach for `node:*` imports in this file.
- **The panel follows the same `lmc.locale` setting as the server.** `webviewPanel.ts` reads it the
  same way `client.ts` does and posts `setLocale` — on `ready`, before the source, so the panel
  never flashes one language then the other, and again whenever the setting changes. The server
  restarts to change language; the panel only has to repaint.
  The host sends **facts, not prose**: `objectLoadFailed` carries the file's `name`, and the panel
  writes the sentence. A shell that phrased it would be choosing the language where it is not
  known.
  **Three sentences escape that rule and it is assumed, not worked around**: the "open an .lmc
  file first" warning, the emulator tab's title, and the "code assembled into X" notification. A
  VS Code notification and a tab title do not go through the webview's rendering, and the object
  file's name only exists host-side, so they live in `webviewPanel.ts`'s `hostText` — the one other
  place in this repo where a language is chosen. Its fallback copies the server's rule: `en` gets
  English, everything else French.
  **What `lmc.locale` cannot reach at all**: the manifest strings — the extension's name, its
  description, the command title, the setting's own description. VS Code localizes `package.json`
  only through `package.nls.json`, keyed on **its** display language, which is the very thing this
  setting exists to stop deferring to. So the command palette says `LMC : ouvrir l'émulateur`
  whatever the setting, and the English warning above quotes it under that name rather than
  sending someone to look for an entry that does not exist.
- **The `lmc.locale` setting** (`package.json`'s `contributes.configuration`, read by `client.ts`)
  — `fr` (default), `en`, or `auto`. `client.ts` subclasses `LanguageClient` to override
  `getLocale()`, which is what the library sends as `initialize`'s `locale` and the only entry
  point: the field is not exposed in the options, and the server reads `params.locale`, not
  `initializationOptions`. **`auto` is deliberately not the default.** Its value is
  `vscode.env.language`, and that stays English for most people whatever their country, because
  nobody changes it; taking it for the language of the classroom would hand English diagnostics to
  a French course, which is the opposite of the service. The client restarts the server when the
  setting changes, since the language is announced once at startup — without that, changing the
  setting would silently do nothing and read as a broken feature.
  This is the one piece of *logic* in a file otherwise described as mechanical wiring, and it is
  not covered by any test: it needs a real VS Code. Same gap as open item 1.
- **`vscode-extension/README.md`** — the **Marketplace page**, and the reason it is a second README:
  the one at the repo root is developer documentation and stays in English, this one is what someone
  installing the extension reads. It is in **French**, like everything the extension says, with an
  English paragraph at the top so a visitor who does not read French knows that in one line rather
  than after installing. `vsce` renames it to `extension/readme.md` in the archive; CI asserts it is
  there, because it was missing at first with nothing to say so.
- **`vscode-extension/webviewPanel.ts`** — creates the panel (`retainContextWhenHidden: true`, so
  stepping progress survives switching tabs), fills in `webview/index.html`'s `{{cspSource}}` /
  `{{styleUri}}` / `{{scriptUri}}` / `{{nonce}}` placeholders, and relays messages both ways:
  host->webview (`setSource`, `cursorLine`) and webview->host (`ready`, `revealLine`,
  `currentLine`, `objectCode`). `objectCode` is the one that does more than relay — it writes the
  file — and it is deliberately the *only* one: see the object-file note below.
  Command `lmc.openEmulator` ("LMC: Open Emulator") is registered in `client.ts`.

**Editor <-> webview sync is the actual point of this being a webview** instead of embedding an
existing standalone LMC simulator (plenty exist as plain websites) — moving the cursor in the editor
outlines the corresponding mailbox; clicking a mailbox reveals its source line. Don't regress this in
future work on the webview; it's the reason to have one.

Verified by (a) `gleam test` on `model.gleam`/`render.gleam` and (b) `scripts/smoke-webview.mjs`,
which drives the built bundle in jsdom and plays the host's half of the protocol — 44 checks, run by
CI. Neither says anything about the panel as VS Code actually renders it: `acquireVsCodeApi` is
stubbed, so CSP, `webviewPanel.ts`'s placeholder substitution and the look of the thing are still
unverified. Actually opening the panel in a real Extension Development Host has not been done by an
agent in this repo — see "Status" below, it's the top item.

## Design note: the functional core is why the tests are trustworthy — not why the code is bug-free

Worth being precise about what Gleam's guarantees actually bought this codebase, because it should
guide where new logic goes, not just serve as a general endorsement of "functional is better."

**What immutability + a pure functional core actually bought:**
- `webview/model.gleam`'s `Model` is fully immutable; every transition (`step`, `run_to_halt`,
  `resume_after_input`, `set_source_if_changed`, ...) is a pure function returning a new `Model`. That's
  what makes the 56 `gleam test`s in `test/webview_model_test.gleam` cheap to write and trustworthy to
  run — no setup/teardown, no mocking, fully deterministic, sub-second. That fast, reliable feedback
  loop is the actual reason bugs like "Step behaves like Run" got caught, fixed, *and* pinned down with
  a regression test in the same session instead of lingering.
- Gleam's exhaustive `case` on sum types (the 11 `Instruction` variants, the `Event` variants) means the
  compiler itself flags every unhandled branch whenever a variant is added — a whole category of
  "forgot to handle this case" bugs never had the chance to exist here.
- `Option`/`Result` used throughout (`m.machine: Option(MachineState)`, `load_error: Option(String)`)
  ruled out null-pointer-style bugs entirely — none showed up anywhere in this codebase.

**What it did *not* buy:** every real bug found while actually testing this extension — blank lines
silently becoming an implicit HLT (`lmc_lsp`'s `load.gleam`), the hover span pointing at the wrong
token, Step behaving like Run, Run collapsing into Step after providing input — was a **domain-modeling
gap**: a missing field, a wrong address computation, a wrong span capture. No type system, functional or
not, invents the test case you haven't thought of yet. Purity made these cheap to *fix* once understood
(add the field, write the one test that pins it down), not less likely to occur in the first place.

**The tell**: almost every bug that took real effort to track down lived at the *impure* boundary, not
in the pure core — `webviewPanel.ts` (a stale cached `TextEditor` reference, `visibleTextEditors` vs.
`tabGroups` API misuse), `app_ffi.mjs` (mutable DOM), or the legacy LSP's FFI layer (`Result$Ok`/
`Result$Error` — names that don't exist in the compiled prelude, undetected for the fallback's entire
existence). `model.gleam`/`render.gleam` — the pure core — has never had a mutation bug, a null bug, or
a missed-case bug; only domain-logic bugs, all of which are now pinned down by a test. Keep that split
in mind when deciding where new logic belongs: push it into the pure Gleam core (`model.gleam`,
`lmc_lsp`'s own layers) whenever possible, and treat any code that has to touch the VS Code API or the
DOM directly (`webviewPanel.ts`, `client.ts`, `app_ffi.mjs`) as inherently higher-risk regardless of how
solid the core underneath it is.

### This split has a name: functional core, imperative shell (Gary Bernhardt)

The architecture above isn't an accident, and it isn't specific to this codebase — it's a recognized
pattern: keep all decision-making in a pure, deterministic **core**, and reduce the **shell** (anything
that has to touch an external, mutable, someone-else's-API system) to the smallest possible surface that
does no more than relay — no branching, no state, nothing worth writing a test for because there's
nothing in it to get wrong. This repo already follows it without ever having named it:

- **Core**: `webview/model.gleam` + `webview/render.gleam` here, and `lmc_lsp`'s `parse/` →
  `semantic/` → `runner/` layers on the other side of the git dependency. Pure, immutable,
  `gleam test`-covered — see the design note above for why that pays off.
- **Shell**: `webviewPanel.ts`, `client.ts`, `app_ffi.mjs`, and the FFI declarations in `ffi.gleam` —
  mechanical wiring only (`postMessage`, `addEventListener`, `createWebviewPanel`, `onDidChange...`).
  `webview/app.gleam` is the seam between the two: it's the one place allowed to call both sides, and
  even it stays a thin `update(cell, f)` loop — pull the model out, apply a pure transition, push the
  render back out. That shape is structurally the same as *The Elm Architecture* (Model → update →
  Cmd/render), not a coincidence — TEA is the same pattern under a different name.

**Why the shell can't shrink to nothing**: `vscode.window.createWebviewPanel(...)` and
`document.getElementById(...).addEventListener(...)` are calls into systems VS Code and the browser own
and mutate, not functions — the moment they run, something observable happens outside the program. That
*is* what "impure" means; no language changes it. Even Haskell's `IO` monad doesn't make these calls
pure, it just catalogs and defers them to a single runtime that, underneath, still executes them
imperatively at `main`. The pattern isn't about eliminating the shell, it's about shrinking it and
banning logic from it — which this repo already does.

**The actionable ceiling, if it's ever worth it**: since Gleam targets JS, `client.ts` and
`webviewPanel.ts` could in principle move into Gleam too, using the same `ref`/`deref`/`setRef` FFI-cell
pattern `ffi.gleam`/`app_ffi.mjs` already use, shrinking the TypeScript down to bare literal API calls.
Low priority — those files are already thin and mechanical (see their descriptions under "Architecture"
above), so there's little latent risk left to remove; the win would be mostly consistency, not safety.

## Status: where things stand, what's left

Done and working, each verified by actually running it (`gleam test`, or driving the built bundle —
never just code review):

- LSP integration (`vscode-extension/lsp-server.mjs` → `vendor/lmc-lsp.bundle.mjs`), no fallback.
- Emulator API as an `lmc_lsp` git dependency; CI pulls it over the `LMC_LSP_DEPLOY_KEY` deploy key.
- **One dependency, one pin.** The bundle is no longer downloaded from a tagged release: it is
  built here, by `scripts/build-lsp-bundle.mjs`, out of the very clone `gleam deps download`
  already makes. So the version lives in `gleam.toml` and nowhere else, and the "double pin that
  must always move together" — the standing hazard of every bump above — is gone rather than
  merely documented. Two things make the substitution honest rather than assumed. The esbuild
  options are not retyped: they are read out of `lmc_lsp`'s own `package.json` (`build:minify`),
  and an unrecognised script is a loud failure. And the bundle no longer being the artefact
  upstream CI tested, `scripts/check-lsp.mjs` runs upstream's **own** `test_lsp.mjs` against it,
  48 assertions over the whole protocol surface. Verified by breaking it: a bundle with
  `hoverProvider` renamed fails one assertion and exits non-zero. Measured, for the record: 77 440
  bytes locally against 77 829 for the published asset, same flags, and both answer `initialize`,
  diagnostics and hover identically.
- Emulator webview MVP: memory grid, registers, I/O tray, step/run/reset, a collapsible Fetch/Decode/
  Execute panel, bidirectional editor↔webview sync (cursor→highlight, click→reveal line, debug-
  session-style current-line decoration).
- All five registers are shown (`ACC`, `PC`, then `SI`, `LR`, `SP` more discreetly, since they only
  come into play with arrays, subroutines and the stack), and the memory grid marks four things —
  the stack above `SP` (dashed orange), the cells a `DAT` reserved (dotted blue), the unused middle
  dimmed, and code left unmarked as the default case. Watching the stack grow cell by cell during a
  recursion is the point of the first: a stack you cannot see is a stack you cannot teach.
- **Assemble -> load -> execute are three separate acts, and the model has three separate
  states for them.** `Model` carries `assembled` (the result of assembling the current source,
  recomputed on every keystroke, used *only* to produce the object file), `loaded` (the RAM image
  as it was at load time — where Reset returns to) and `machine` (the live machine, which drifts
  from `loaded` as you execute). The panel opens with an empty memory: `machine` is `None` until
  something is loaded, `program_length` reads `machine.program_end` rather than the source, and the
  grid dims all 100 cells.
  - **"Assembler"** writes `<name>.lmcobj` next to the source: four digits per line, one line per
    cell, no mnemonics and no labels, because that is all the processor ever receives.
    `lda_and_mov_acc_produce_the_same_object_file_test` pins the claim the button's tooltip makes.
  - **"Charger"** asks the host to *actually read that file off disk* (`requestLoad` ->
    `objectLoaded`/`objectLoadFailed`) and turns its words into RAM via `model.machine_from_words`.
    Loading a file rather than the in-memory copy is the whole point, and the two consequences are
    deliberate, not accidents to be smoothed away: loading before assembling fails, and editing the
    source without reassembling loads the **old** program. Both are how a real toolchain behaves.
  - The cost, accepted knowingly: `address_to_line` and `data_addresses` are derived from the
    *source*, so after an edit they describe something other than what is in RAM. That is exactly
    what debug information is, and why a stale binary confuses a debugger. Do not "fix" it by
    deriving the mapping from the object file — the file does not contain it; that is the point.
  The `DAT` marking (`model.data_addresses`) is deliberately **provenance, not machine state** —
  "rien ne distingue une case de code d'une case de données" (LANGAGE.md), so it never changes when
  a `STA` writes into code or a `PC` runs into a `DAT` and halts on it. That gap is the lesson, not
  a bug to fix by making the marking follow execution.
- **The `lmc_lsp` v0.4.0 migration**, taken in one block: the double pin, `X` -> `IX` everywhere
  (TextMate grammar, register tooltip, `tableau.lmc`/`chaine.lmc`, README), `PSH`/`POP` carrying a
  register in the Decode line, and `PLT` — a seventeenth mnemonic the grammar was missing. The three
  `.lmcobj` files sitting in `examples/` were re-checked rather than assumed: reassembling every
  example under v0.4.0 produces them byte for byte (none contained `9003`/`9004`, `PSH`/`POP`'s old
  machine words). They are **gitignored artefacts of the Assembler button**, not tracked files —
  `git ls-files examples/` lists no `.lmcobj` at all — so a stale one on someone's disk is a local
  matter, and re-clicking Assembler is the whole fix.
- **The `lmc_lsp` v0.5.0 → v0.6.1 migration**, three releases in one step (v0.5.0 and v0.6.0 carry four
  full-layer reviews — `parse/`, `runner/`, `features/`, `semantic/`). The **double pin** moved as
  it then had to, `gleam.toml` and `scripts/fetch-lsp-bundle.mjs` together (that script is gone
  now, see "One dependency, one pin" above). What it cost here:
  - `MachineState.output` became `output_reversed` (newest-first, so `OUT` costs a cons) and is
    read through `inspect.output_buffer`. Six call sites, not the two the plan had found:
    `render.gleam`, `model.gleam`'s `machine_from_words`, **both** test modules,
    `scripts/check-examples.mjs`, and the README's Emulator API snippet. The JSON key stays
    `"output"`, so `app_ffi.mjs` was untouched.
  - `ProgramTooLong`'s field, misnamed `line_count`, is now `cell_count`; the message says "cases".
    But the claim that it "had been reporting lignes this whole time" is **wrong**, checked rather
    than repeated: `semantic/lints.gleam`'s `check_length` applies the same rule (`ast.cell_count`)
    and fires first, so the webview shows its generic "voir les diagnostics" message and that
    branch of `load_error_message` is never reached. It is defensive code, and now says so.
  - **The TextMate grammar had drifted, and nothing was watching.** v0.5.0 let a name start with
    `_` or a Latin letter up to U+017F and continue with combining diacritics; the grammar still
    said `[A-Za-z][A-Za-z0-9]*`, so `compteur_1: DAT 0` and `numéro: DAT 0` got **no colouring at
    all** while the server accepted them. This is exactly the duplication the grammar's own header
    comment warns about. Fixed, and pinned down by **`scripts/check-grammar.mjs`**, which
    tokenizes with the real Oniguruma engine VS Code uses (`vscode-textmate` +
    `vscode-oniguruma`, two new devDependencies of `vscode-extension/`) rather than with
    JavaScript's regexes, reads the mnemonic and register tables **out of `lexer.gleam` itself**
    instead of retyping them, and settles "is this a valid name?" by asking the real pipeline and
    demanding the grammar agree. Verified by breaking it: with the old pattern restored it fails
    on five names and exits non-zero.
  What the bump buys was exercised, not assumed: an address outside 0-99 is now a diagnostic
  instead of silently assembling to a different valid instruction (`STA 900`), a CRLF file gets no
  bogus diagnostics (Format Document normalises it to LF, which is not the same thing as
  destroying it), the formatter no longer eats a trailing comment on a `DAT` line nor inserts a
  comma nobody typed, hover on an operand says "Adresse", and `OUT` in a loop is no longer slow
  (300 outputs in 10 ms). The whole path was driven for real: `lsp-server.mjs` started over stdio
  with a hand-written client, `initialize` answered, diagnostics and hover came back. All 26
  tracked examples still parse clean except `broken.lmc`, which is broken on purpose.
  **`v0.6.1` followed the same day**, and `v0.7.0` after it (see the entry below). No API moved, so it was
  a pin bump and a re-run of the suite, not a migration: `Int` is a JS float, so beyond fifteen
  digits `int.parse` rounded and beyond about three hundred it returned `Infinity` — a `DAT` of
  four hundred `9`s stored `NaN` and the program died further on with "instruction illégale: NaN",
  nothing having named the cause. Such a literal is now an error, reported where it is written,
  and `DAT 00042` still assembles (leading zeros are not significant digits).
  It did break one thing here, and the smoke test is what caught it: the new
  `parse/integer_literal` calls `string.drop_start`, so **every** integer literal now goes through
  the Gleam stdlib's `byte_size`, which needs `TextEncoder`. jsdom does not put `TextEncoder` in
  its `window`; a Chromium-based VS Code webview always has it, so the gap was the harness's, and
  `scripts/smoke-webview.mjs` now fills it rather than the page working around it. Nothing else in
  the suite noticed — the gap only exists where a browser is being faked.
- **`lmc_lsp` v0.7.0: the index register is `SI`.** Second rename of the same register (`X` in
  v0.4.0, `IX` until now); `SI` is *source index*, the name it carries on x86 where it plays the
  same role. **The encoding does not move** — `register_number(Si)` is still 1 — so no `.lmcobj`
  changes and no machine word does either; what changes is every place the name is written.
  Here that was: `model.gleam` (`register_name`, the `IndexChanged` line, and `mem[n+SI]`), the
  grammar's register rule, the register panel's label and tooltip in `index.html`, four examples
  (`tableau`, `chaine`, `affiche_tab`, `ecran`), and the README. The internal `id="x"` and JSON key
  `"x"` were left alone, as in v0.4.0: they are never displayed.
  Two things are worth keeping in mind for the next rename, because both were near-misses.
  `scripts/check-grammar.mjs` **hardcoded** `["ACC", "IX", "LR", "SP", "PC"]`, so it would have
  gone green with the old name on both sides — exactly the failure it exists to prevent. It now
  reads the register names out of `features/completion.gleam`, the one place in `lmc_lsp` that
  names them as a set, the way it already read the mnemonics out of `lexer.gleam`. And nothing
  covered `register_name` at all, so half a rename would have compiled and passed: a model test now
  pins both sentences the cycle panel builds from it.
- **`lmc_lsp` v0.8.0: the server is bilingual, and no layer builds a sentence any more.** Every
  user-visible string is now a `text/message.Message` value that only `lsp/server.gleam` renders,
  in the language the client announced in `initialize`'s `locale` (French by default, English for
  `en`, French for anything else). Two things followed here.
  `event.ErrorOccurred` carries a `Message` rather than a `String`, so `model.gleam` renders it —
  `message.render(reason, message.French)`, because the webview is French; see "one language"
  below.
  And `check-grammar.mjs` **failed loudly**, exactly as designed: `features/completion.gleam`'s
  register list changed shape, so the pattern it read the names with matched nothing and the script
  refused to pretend it had checked anything. It now reads the whole `register_completions` block
  instead of one line, since the formatting has moved once and the contents have not.
  **What this repo has NOT decided**: `vscode-languageclient` sends `vscode.env.language` as the
  locale, so a VS Code running in English now gets English diagnostics — while the panel, the
  manifest, the 26 examples and the Marketplace page are French. That split is real and open; see
  the open list.
- **`lmc_lsp` v0.8.1: one file per language, and Spanish.** `Locale` moved out of
  `text/message.gleam` into its own `text/locale.gleam` and gained a third variant, so
  `webview/text.gleam` follows: it imports `lmc/text/locale` and re-exports the type, because a
  second `Locale` here would let the panel and the diagnostics answer the same setting
  differently.
  **The panel does not speak Spanish yet** and falls back to English, message by message, rather
  than rendering blanks — a transition state, marked as such in the code, waiting on the
  externalisation in the open list rather than tripling an in-code catalogue days before it
  becomes files.
  What was a real gap and is fixed: `lmc.locale` offered `fr`, `en`, `auto` and **not `es`**, so a
  Spanish-speaking teacher could not choose the language the server was perfectly able to speak.
  The manifest is a data file — nothing compiles it, nothing tied it to the server — so
  `scripts/check-manifest.mjs` now reads the tags `from_tag` recognises straight out of
  `locale.gleam` and requires the setting to offer exactly those. Verified by breaking it: dropping
  `es` from the enum fails and exits non-zero.
- **A progressive `examples/unit-*.lmc` series**, thirteen files, one new thing each: `INP`/`OUT`,
  the input queue, `STA`/`LDA` on numbered cells, `ADD`, `SUB`, then `DAT` as *naming* (files 1 to 5
  use no `DAT` at all and address cells as `50`, which is the point: `DAT` is a convenience for the
  writer, and the machine never sees it), `DAT` with an initial value, `BRA`, `BRZ`, `BRP`, a full
  if/else, and the two loops. Each header carries its own `Entrée : … Sortie : …` cases, and those
  are not decoration: `scripts/check-examples.mjs` runs all 22 of them against the real dependency
  on every push, and the three "remove this line and see" claims the comments make were checked once
  by hand. The headers avoid a trailing
  comment on any `DAT` line, which was a workaround: `lmc_lsp`'s formatter used to eat them. It no
  longer does (v0.6.0, checked by running the formatter on `n: DAT 5  // cinq`), so the constraint
  is lifted — the files were left as they are because nothing in them wants such a comment, not
  because one would be destroyed. What the series does *not* cover, and where the older examples
  take over: `SI` and indexed addressing, `MOV`, `JSR`/`RET`, `PSH`/`POP`, `PLT`.
- **A screen, 32 x 32, eight colours** (`examples/ecran.lmc` draws a diagonal and a line on it).
  Size and palette were `lmc_lsp`'s two deliberately-unmade decisions — the runner emits
  `PixelPlotted` and paints nothing — and they were made here, where a device belongs. See the
  `model.gleam` bullet above for what follows from that.
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
2. **`// @locale fr-FR` at the top of a file, decided but not implemented.** The setting above is
   per user; the directive would be per *file*, which is the right grain for teaching material —
   a handout carries its own language and keeps it on someone else's machine. It is `lmc_lsp`'s
   work (lexer, parser, semantic), not this repo's. Three things need deciding there before a line
   is written, and they are recorded here because they are what would otherwise get decided by
   accident:
   - **A file with no directive**: follows the client's `locale` (so `lmc.locale` above), which is
     what happens today. The author asked for English on an *unimplemented* locale; that is not
     the same case as an absent directive.
   - **Precedence**: the file's directive over the client's `locale`. The obvious reading, worth
     writing down anyway.
   - **The directive must survive a broken file and the formatter.** It will be read while the
     file is half-typed and full of errors, and Format Document has eaten comments before (the
     `DAT` line bug). Both paths need a test.
   What comes back here once it exists: the webview reads the same directive instead of asking for
   `message.French` outright (`model.gleam`'s `ErrorOccurred` branch), the grammar colours the
   directive as something other than a plain comment, and the 26 examples get a header line.
3. **Externalise the message catalogues into per-language files.** Decided 2026-09-06: many
   languages, to take the cognitive load off students from different countries. That kills the
   in-code catalogue, which only paid off for two languages and one author — nobody outside can
   translate a Gleam `case`, and each new language would touch both repos.
   **`lmc_lsp` goes first, and its author is handling it**: its `Locale` is a closed
   `French | English`, and this repo reuses that type, so nothing here can name a language the
   server does not know. Do not start on this side before that lands.
   What survives the migration, and what makes it cheap: **call sites already build values**
   (`text.FetchRead(0, 5003)`), never sentences. The sum type stays the message's identity; only
   the rendering becomes data.
   What has to be rebuilt, because the compiler stops guaranteeing it: a test walking every variant
   × every shipped language for a present, non-empty string; a check that no placeholder is left
   unsubstituted and none is unknown; and a per-message fallback so a half-translated language
   stays usable.
   Agreed defaults, unless the `lmc_lsp` side decides otherwise: **fallback** requested → English →
   never empty, while the **default** for a silent client stays French (they are different
   things); **plurals** — the format allows a value to be a string *or* an object of plural forms,
   only the string path is implemented, and no message is phrased so that it depends on a number,
   which keeps Polish and Arabic open without writing ICU in Gleam today; **format** one JSON per
   language in-repo, PRs to contribute, a translation platform later if translators should not
   have to touch git.
   Three things on this side when the time comes: `src/webview/text.gleam`'s two catalogues,
   `webviewPanel.ts`'s `hostText`, and the fact that catalogues are **build-time** data — the
   webview has no disk access and the server is a single bundled file, so translators edit files
   and the build embeds them.
   Not covered by any of this, and the larger half of the actual load: the 26 examples carry French
   comments and `LANGAGE.md` is French. Diagnostics in Spanish with course material in French only
   removes part of what this is for.
4. ~~**No committed smoke-test script.**~~ Done: `scripts/smoke-webview.mjs`. It loads
   `webview/index.html` with its placeholders substituted, runs the built bundle in jsdom, and plays
   the extension host's half of the protocol — including the object file, which it holds as a
   variable that starts `null`, which is what makes "load before assembling" testable at all. 55
   checks over the assemble/load/execute pipeline, the von Neumann frame grouping, the tooltips
   and legend, the screen, the Fetch/Decode/Execute panel (that the three phases are three, and
   that Fetch carries both the read and the PC increment), and **the language**: that no `data-ui`
   slot is left empty (a key written on one side only), that `setLocale` switches the buttons, the
   headings, the tooltips, the `lang` attribute and the cycle lines, and that an untranslated
   language falls back rather than blanking. Verified by breaking it: dropping one label from the
   catalogue names the empty slot and exits non-zero. jsdom has no 2d context, so the script installs one of its own that
   records what it is asked to paint — which is how the screen's rendering gets covered at all, and
   it is exactly the impure boundary this script exists for. It fails and exits non-zero when any
   of it breaks — verified by breaking it.
   It does **not** replace opening the panel for real: `acquireVsCodeApi` is stubbed, so it says
   nothing about CSP, about webviewPanel.ts's placeholder substitution, or about how any of it
   looks.
5. ~~**`lmc_lsp` is still private.**~~ **Settled, 2026-09-06: it stays private.** The author's
   decision, in their words: "il est hors de question de rendre le lmc_lsp public, tout ne sert
   qu'à moi." So `gh auth` locally and the deploy key in CI are not a temporary arrangement to be
   removed, they are the arrangement. Do not re-propose making it public, and do not treat "blocks
   distribution" as a problem: there is no audience to distribute to. The passage under
   "Relationship to lmc_lsp" that says to revisit this if a public release makes it impractical is
   answered — no public release is planned.
6. **No Zed extension exists yet.** Editor independence via `lmc_lsp` was the explicit reason to keep
   the two repos separate (see "Relationship to lmc_lsp" above) — today `lmc_lsp` only has this one
   VS Code client using it. Private does not prevent this: a Zed extension would fetch the bundle
   the same authenticated way this one does.
7. ~~**The VS Code extension isn't packaged as a `.vsix`.**~~ Done: `npx vsce package` produces a
   **self-contained** archive. Two things had to change first, and neither was cosmetic.
   `lsp-server.mjs` and `vendor/` moved from the repo root **into `vscode-extension/`**, because
   `vsce` archives that directory and nothing above it: the old layout worked under `F5` and would
   have shipped a `.vsix` with no language server in it at all. And `@types/vscode` is now pinned
   *exactly* to `1.80.0` — `vsce` refuses to package when the types are newer than
   `engines.vscode`, and `^1.80.0` resolves to the latest minor, so the caret was the bug.
   Verified by running, not by reading the file list: the archive was unzipped and its
   `extension/lsp-server.mjs` driven over stdio, `initialize` answered, diagnostics and hover came
   back. `.vscodeignore` keeps the TypeScript sources out; `node_modules` is deliberately *not*
   listed there, since `vsce` already ships production dependencies only (`vscode-languageclient`)
   and dropping it would remove the one dependency the extension needs at runtime.
   What is still untested is the installed extension inside VS Code itself — same gap as item 1.
   Rebuild order before packaging: `build-lsp-bundle.mjs`, `build-webview.mjs`, `npm run compile`.
8. **One language change is still open: renaming the language itself** (`LMC` → ?). The other
   three that were planned — `X` → `IX` (and `IX` → `SI` in v0.7.0, see the done list), opcode 9
   in families with `PSH`/`POP` on a register, and
   the screen instruction (shipped as **`PLT`**, not `PIX`: the verb names the action and lets the
   data be called what it likes, the same split as `STA total`) — landed in `lmc_lsp` `v0.4.0` and
   are taken up here; see the done list above. The rename is undecided and independent; the plan
   and the reasoning live in `lmc_lsp`'s CLAUDE.md, the language being its business. Only the
   ordering concerns this repo: the **file extension goes first or never**, since every `.lmc`
   written meanwhile is one more file to rename, and this repo owns `.lmc`, `.lmcobj`, the `lmc`
   language id, the `source.lmc` grammar scope and 26 example programs (the count here has been
   wrong twice already, first at nine and then at twelve — `ls examples/*.lmc | wc -l` settles it,
   and the `unit-*` series doubled it). It ends, like every
   language change, with an `lmc_lsp` release and, here, the single `ref` in `gleam.toml`.
