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
  `lmc_lsp = { git = "https://github.com/MMarchand-NSI/lmc_lsp.git", ref = "v0.8.3" }`), instead of
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

CI is two workflows. `release.yml` publishes to the Marketplace on a `v*` tag; see the release
entry under Status for what it guards against and why the token is a secret.
`.github/workflows/test.yml` runs on gleam 1.18.1 and node 20, with no Erlang at all (the
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

## Skills

`.claude/skills/add-language/` — **ajouter une langue d'interface**. Sept endroits, dont un
prérequis dans `lmc_lsp` (le type `Locale` est le sien) et trois que rien ne réclamerait tout seul :
la table `hostText` de `webviewPanel.ts`, l'`enum` de `lmc.locale`, et la liste `languages` des
tests. Écrite après que les deux premiers ont effectivement été oubliés en ajoutant l'espagnol.

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
  - `french.gleam`, `english.gleam`, `spanish.gleam` — one language per file, `render` and
    `label`, nothing else. The Spanish follows the server's own vocabulary (`celda`, `dirección`,
    `etiqueta`, `pila`, `acumulador`, `contador de programa`) rather than picking its own: two
    translations of the same term would have a student reading about two different machines. It
    has **not been read by a native speaker**, and for course material it should be.
  - `locale.gleam` — the dispatch, and the only place to touch to add a language. It does **not**
    redefine `Locale`: that is `lmc_lsp`'s, imported `as server`, so the panel and the diagnostics
    cannot answer the same setting differently and a runner error (`message.Message`) renders in
    the same language without being copied here.
  No layer builds a sentence: `model.gleam` returns values, and only `locale.gleam` knows the
  language. What that bought, exactly as upstream: the model tests compare values
  (`message.FetchRead(0, 5003)`), so rephrasing breaks none of them — and the per-language tests
  loop over every locale the server knows, so Spanish is already covered the day it gets its file.
  One thing the translation made visible: the panel's status was `vide` among `running`,
  `waiting_input`, `halted` and `error`. That word is a **machine token**, not prose —
  `app_ffi.mjs` branches on it — so it is not translated and never should be; it is now `empty`,
  like its four siblings.
  Data files were the planned next step, and they are **refused** (open item 3, settled
  2026-09-06): the split into one module per language already bought what mattered, and JSON only
  pays off for a translator who does not write Gleam, of whom there is none. So this is the final
  shape, not a transition state.
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
  file first" warning, the emulator tab's title, and the "code assembled into X" notification.
  That table was left at two languages when Spanish arrived, so a reader set to `es` got a Spanish
  panel with a French tab title; `scripts/check-manifest.mjs` now requires it to cover every
  language the server speaks, and the primary-subtag lookup matches the server's own. A
  VS Code notification and a tab title do not go through the webview's rendering, and the object
  file's name only exists host-side, so they live in `webviewPanel.ts`'s `hostText` — the one other
  place in this repo where a language is chosen. Its fallback copies the server's rule: a language
  it does not speak gets **English** (`locale.fallback_locale`, since the server's v0.8.2). It said
  French until 2026-09-06, which cost nothing while `lmc.locale` defaulted to `fr`; the default is
  `auto` now, so a German or Italian VS Code reaches that fallback routinely, and would have had an
  English panel under a French tab title. Exactly the Spanish bug again, caught before shipping.
  **What `lmc.locale` cannot reach at all**: the manifest strings — the extension's name, its
  description, the command title, the setting's own description. VS Code localizes `package.json`
  only through `package.nls.json`, keyed on **its** display language, which is the very thing this
  setting exists to stop deferring to. Since they can only be one language, they are **English**,
  the same call as the Marketplace page: a string that cannot follow the reader should carry the
  furthest. So the palette reads `LMC: Open Emulator` whatever the setting, and all three
  `hostText` languages quote it under that name rather than sending someone after an entry that
  does not exist.
- **The `lmc.locale` setting** (`package.json`'s `contributes.configuration`, read by `client.ts`)
  — `fr`, `en`, `es`, `ja`, `ko`, or `auto`, and **`auto` is the default since 2026-09-06**.
  `client.ts` subclasses `LanguageClient` to override `getLocale()`, which is what the library
  sends as `initialize`'s `locale` and the only entry point: the field is not exposed in the
  options, and the server reads `params.locale`, not `initializationOptions`. The client restarts
  the server when the setting changes, since the language is announced once at startup — without
  that, changing the setting would silently do nothing and read as a broken feature.
  **The default was `fr`, and the reason it moved is worth keeping, because the old reason was
  right too.** `auto` is `vscode.env.language`, which stays English for most people whatever their
  country, because nobody changes it; while the only audience was a French classroom, defaulting to
  it would have handed English diagnostics to a French course, the opposite of the service. The
  Marketplace release flips the population, not the argument: the same reasoning now says that
  imposing French on someone installing from Osaka is the same wrong, and more often. A default
  cannot guess a classroom. It can follow the editor, and the setting is what contradicts it in one
  click — which the README says in its second paragraph, in bold, since that is the case that
  matters. **The author's own machine is in that population**: working on this repo now needs
  `"lmc.locale": "fr"` in user settings, or the diagnostics come back English.
  Three things had to follow, and each was a place where French was written down as *the* default
  rather than as *the setting's* default: `hostText`'s fallback (above), the panel's first-frame
  `default_locale` (`src/webview/text/locale.gleam`, now English, so the first paint matches what
  the host sends a millisecond later instead of flashing), and the tests that pinned French in
  `webview_render_test.gleam` and `scripts/smoke-webview.mjs`. Those tests are why the cascade was
  found at all: two of them failed the moment the constant moved, and the smoke test named the
  other three. They now assert the English default *and* that asking for French still renders
  French, which is the half that actually matters to the classroom.
  This is the one piece of *logic* in a file otherwise described as mechanical wiring, and it is
  not covered by any test: it needs a real VS Code. Same gap as open item 1.
- **`vscode-extension/README.md`** — the **Marketplace page**, and the reason it is a second README:
  the one at the repo root is developer documentation, this one is what someone installing the
  extension reads. Both are in **English**. It was French at first, when the extension only spoke
  French; now that it speaks three languages, the shop window is the one place where the widest
  reach wins, and it says in its second paragraph which languages the extension offers and how to
  choose one. What stays French is stated there too: the example programs and the language
  reference. `vsce` renames it to `extension/readme.md` in the archive; CI asserts it is
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
- Emulator webview MVP: memory grid, registers, I/O tray, step/run/reset, an always-open
  Fetch/Decode/Execute panel, bidirectional editor↔webview sync (cursor→highlight, click→reveal
  line, debug-session-style current-line decoration).
  That panel was a collapsed `<details>` at first, on the argument that it should not compete with
  the step-by-step highlight. Use settled the opposite way: what the processor does at each step is
  what the panel is *for*, and folding it hid the lesson. It is a plain section now, stretching to
  the bottom of the window and scrolling inside itself — it is the only block whose content grows
  from one step to the next.
  The block above it (processor, memory, I/O) is deliberately **not** a scroll box. Making it one
  produced a scrollbar with nothing to scroll: the block came out taller than the three frames it
  holds. It keeps its content height, and a window too short for everything scrolls the page — one
  scrollbar rather than two nested.
  **No test covers the layout**: jsdom does no layout, so the smoke test can only assert that
  nothing is collapsible any more. Heights and scrollbars are checked by the author in a real
  panel, on `F5`, which is what open item 1 is about: hand-checked, not automated.
- **La case touchée pulse : teal si elle a été lue, rose si elle a été écrite.** Deux couleurs et
  non une, parce que c'est la distinction que la grille doit enseigner — lire ne change rien,
  écrire change la machine — et la couleur chaude va au geste qui modifie.
  `model.memory_accesses` rend ce que le dernier pas a lu ou écrit, `render.gleam` l'envoie sous `accesses`, et `app_ffi.mjs` pose une classe que le CSS
  anime — retirée puis reposée après un reflow, sans quoi une case lue deux fois de suite ne
  clignoterait qu'une fois, ce qui est précisément le cas du pas à pas.
  **Trois événements, tous rapportés par le runner** : `Fetched` (toute instruction lit sa propre
  case), `MemoryRead` — arrivé en v0.8.3, c'est lui qui allume la case de la donnée que `LDA n` va
  chercher — et `MemoryWritten`. Rien n'est reconstruit ici : l'adresse effective d'un accès
  indexé n'est connue que du runner, et la recalculer serait la duplication qui a produit le bug
  v0.1.5. La demande faite en amont plutôt que contournée ici, c'est le motif de tout ce dépôt.
  Une même phrase sert la lecture du Fetch et celle de l'opérande (`message.CellRead`) : c'est le
  même fait, une case lue et ce qu'elle contenait, et seule la phase diffère.
  `prefers-reduced-motion` désactive le clignotement et laisse la case allumée : l'information ne
  dépend pas de l'animation.
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
  **What that opened, and how it was closed**: `vscode-languageclient` sends `vscode.env.language`
  as the locale, so a VS Code running in English would have got English diagnostics while
  everything else was French. The answer is the `lmc.locale` setting described above, whose
  default is `fr` and explicitly **not** `auto`, for exactly that reason.
- **`lmc_lsp` v0.8.1: one file per language, and Spanish.** `Locale` moved out of
  `text/message.gleam` into its own `text/locale.gleam` and gained a third variant, so
  `webview/text.gleam` follows: it imports `lmc/text/locale` and re-exports the type, because a
  second `Locale` here would let the panel and the diagnostics answer the same setting
  differently.
  **The panel did not speak Spanish on the day of the bump** and fell back to English, message by
  message, rather than rendering blanks. That state is over: `spanish.gleam` landed the same day,
  and Japanese and Korean followed at v0.8.2.
  What was a real gap and is fixed: `lmc.locale` offered `fr`, `en`, `auto` and **not `es`**, so a
  Spanish-speaking teacher could not choose the language the server was perfectly able to speak.
  The manifest is a data file — nothing compiles it, nothing tied it to the server — so
  `scripts/check-manifest.mjs` now reads the tags `from_tag` recognises straight out of
  `locale.gleam` and requires the setting to offer exactly those. Verified by breaking it: dropping
  `es` from the enum fails and exits non-zero.
- **`lmc_lsp` v0.8.2: five languages, and the fallback becomes English.** Japanese and Korean
  landed upstream, the server now negotiates (`locale.negotiate([announced, system_locale()])`),
  and `default_locale` moved from French to **English**. Taken up here in the shape the split was
  made for: two new files, `japanese.gleam` and `korean.gleam`, plus arms the compiler demanded in
  `render`, `label`, `phase_label` and `tag`.
  **A default and a fallback stopped coinciding, and the code now says so.**
  `webview/text/locale.gleam` exposes both: `default_locale` is French — what the panel paints on
  its very first frame, because that is what `lmc.locale` will send a millisecond later, and
  taking the server's fallback there would flash English before the first `setLocale` —
  and `fallback_locale` is the server's English, what answers "I do not speak what you asked".
  Three render tests caught the change on their own, which is why they existed.
  `lmc.locale` and `hostText` grew `ja` and `ko`; `check-manifest.mjs` demanded both, as designed.
  **Spanish, Japanese and Korean have not been read by anyone who speaks them.** The criterion is
  not who wrote a translation — everything here was — but **who can catch a mistake**: a clumsy
  French or English sentence gets corrected in the loop where the work happens, and nothing in that
  loop can see a wrong politeness register in Japanese or Korean. Each of those files says so in
  its own header, and the Marketplace page asks for corrections.
- **`lmc_lsp` v0.8.3: `MemoryRead`, asked for and granted.** The pink pulse landed one release
  earlier with a hole in it: `LDA n` lit the instruction's cell and not the data's, because the
  runner reported writes and not reads. Rather than recompute the effective address here — indexed
  mode, `SI` at the right instant, all of it already implemented over there — the gap was written
  down as an open item and the event asked for. It exists now, deliberately not emitted for the
  fetch (`Fetched` already says it), and this side gained exactly one arm in
  `model.memory_accesses` plus one in the cycle panel.
  The Execute line now reads `lire mem[3] → 5` before `ACC 5 → 10`, using the **same** text value
  as the Fetch line (`message.CellRead`, renamed from `FetchRead`): one fact, one sentence, five
  languages unchanged. Four model tests failed on the bump without being touched, including the one
  that pinned the absence — it now pins the presence.
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
  There was a legend of the eight colours under the canvas; it is gone. The screen reads without
  it, and it named its colours in French only, in a panel that speaks five languages. `PALETTE`
  itself stays in `app_ffi.mjs` — it is what paints.
- A long list of real bugs caught by actually exercising the extension/webview, not by guessing:
  hover-on-operand, missing HLT/length diagnostics, a confusing mnemonic error message, blank lines
  silently becoming an implicit HLT (`lmc_lsp`, the most serious one), a stale `TextEditor` reference
  breaking sync across tab switches, mailbox clicks opening a new tab instead of reusing an existing
  one, Step behaving like Run, Run collapsing into Step after providing input, PC/ACC resetting on
  refocus, Fetch/Decode/Execute events splitting across an input pause, a redundant post-INP
  accumulator-changed event, and the Decode line reading like reconstructed source code.
- **The first public release, 2026-09-06.** The priority changed that day: publish something on the
  Marketplace that looks solid, rather than keep polishing. What that took, beyond what was already
  built, and what each thing is for rather than merely that it exists:
  - **`publisher: "mmarchand"`** (it was the placeholder `lmc-vscode`). The published identity is
    `<publisher>.<name>`, and it does not change afterwards.
  - **MIT**, at the repo root and in `vscode-extension/` so it ships. `vsce` warned about its
    absence on every package, and "License: none" on the store page is the single cheapest thing to
    fix.
  - **`icon.png`, 128 × 128, produced by `scripts/build-icon.py`** and not drawn by hand. It is the
    memory grid with two cells lit, in the panel's own two colours (teal for a read, pink for a
    write, the values read off `style.css`), so the icon cannot drift away from the product: if the
    palette moves there, it moves here. No lettering, because three letters at 42 px, the size of a
    row in the extensions list, is a smudge. Checked at both sizes, by looking at it.
  - **`CHANGELOG.md`**, the store's second tab, and `categories`/`keywords`/`galleryBanner`.
    `Education` was added; **`Debuggers` was considered and dropped** — the extension registers no
    debug adapter, and a category is a claim.
  - **`MMarchand-NSI/lmc-vscode` is now a public GitHub repo.** It had to be: the manifest's
    `repository` and the README's links pointed at it, and a store page whose every link 404s is
    the opposite of solid. Scanned all 104 commits for key material before flipping it; the deploy
    key lives in Actions secrets, not in the tree. `lmc_lsp` stays private, see open item 5.
  - **The Marketplace page lost its two dead links and gained the instruction table.** It pointed
    at `lmc_lsp`'s `LANGAGE.md` for the language reference, which no reader can open. The
    seventeen mnemonics are now in the page, and their one-line descriptions are **the server's
    own** (`text/english.gleam`'s `mnemonic_doc_en`, the same text hover shows), copied from the
    dependency rather than rewritten, so the page and the editor cannot say two different things.
  - **`lmc.locale` defaults to `auto`**, with the cascade that followed; see the setting's own
    entry above, which is where the reasoning lives.
  Verified by running, not by reading a file list: the `.vsix` was unzipped and its
  `extension/lsp-server.mjs` driven over stdio — `initialize` answers, `hoverProvider` is true, and
  `STA nulle_part` comes back as « label non défini : nulle_part ». The five check scripts and
  `gleam test` (87) pass.
  - **Publishing is a workflow, not a command on someone's laptop**
    (`.github/workflows/release.yml`, added the same day at the author's request). Pushing a tag
    `v*` runs the whole suite again, packages, and publishes with `vsce publish --packagePath` —
    the archive that was just checked, not a second one built after the checks. It then attaches
    the `.vsix` to a GitHub release. Two guards run before anything is spent: the tag must equal
    `vscode-extension/package.json`'s `version` (the Marketplace believes the manifest, not the
    tag, so `v0.2.0` on a manifest left at `0.1.0` would silently publish `0.1.0` and burn that
    number for ever), and `VSCE_PAT` must be non-empty.
    Why a secret rather than `vsce login`: **measured, not assumed** — `keytar` cannot open a
    credential store under WSL here (`dbus-launch: No such file or directory`), so `vsce login`
    falls back to writing the token in clear text to `~/.vsce`. A repo secret is not readable
    back, is masked in logs, and is unavailable to pull requests from forks, which now matters
    since the repo is public. The secret is passed through `env:` and never interpolated into a
    `run:` line.
    **The token has a deadline that is not its own, and it is close.** VS Code's publishing doc
    has you create the PAT with *All accessible organizations*, which makes it a **global** PAT,
    and Microsoft is removing those: creation blocked and full decommissioning announced for
    **2026-12-01** ([Azure DevOps
    blog](https://devblogs.microsoft.com/devops/retirement-of-global-personal-access-tokens-in-azure-devops/),
    read 2026-09-06). Two honest caveats, both from that post: it carries a revision note on the
    blocking date, so whether a global PAT can still be minted today is untested; and **it says
    nothing about extension publishing** — a commenter asked, nobody answered. So the day the
    `Publish` step fails on authentication, suspect this before suspecting the secret. The
    replacement is `vsce publish --azure-credential` (Entra rather than a stored token), already
    present in the vsce version used here.
    Getting the token at all was its own obstacle, worth recording since it will recur on any
    rotation: signing in through `dev.azure.com` lands a personal Microsoft account in the
    "Microsoft Services" tenant, which has no directory behind it, and the sign-in loops. The
    documented way round is to sign out of everything, use a private window, and mint the token
    from the **Marketplace publisher portal** (`marketplace.visualstudio.com/manage` → Security →
    Personal Access Tokens) with one account used consistently — Azure DevOps also accepts a
    **GitHub** sign-in, which avoids the tenant question entirely.
  **What is not done and needs the author**: creating the `mmarchand` publisher on the
  Marketplace, generating a PAT (Azure DevOps, *All accessible organizations* + *Marketplace →
  Manage*, 30 days by default), and storing it as the `VSCE_PAT` repo secret. An agent cannot and
  should not do that part. After that, releasing is `git tag v0.1.0 && git push origin v0.1.0`.

Still open, roughly in the order it's worth tackling them. As of 2026-09-06 that list is
**short**, and nothing on it is a missing feature: item 1 is a gap in *automation*, not in
checking (the author checks by hand constantly), item 9 is deferred by choice, and items 2, 3, 5,
6, 8 and 10 are decisions taken, kept here so they are not re-proposed:

1. **Nothing automated covers the panel as VS Code actually renders it.** This item used to say the
   webview had "never been opened in a real Extension Development Host", which was misleading, and
   the author corrected it on 2026-09-06: **they press `F5` and look at the panel on essentially
   every change, whether or not they mention it in the conversation.** So the panel is exercised
   for real, continuously, and a blank panel, a broken CSP or a botched placeholder substitution
   in `webviewPanel.ts` would not survive a session. What is true, and all that is true:
   - **No agent working in this repo has ever seen the panel**, and none can: it needs a graphical
     VS Code. So an agent must never write "verified" about a visual fact here, only "the author
     confirmed it" or "unchecked". `gleam test` and `scripts/smoke-webview.mjs` say nothing about
     CSP, about `webviewPanel.ts`'s `{{cspSource}}` / `{{styleUri}}` / `{{scriptUri}}` /
     `{{nonce}}` substitution, or about layout, since jsdom does no layout and stubs
     `acquireVsCodeApi`.
   - **No check in CI covers any of that either**, so the safety net is the author noticing, which
     catches what they happen to look at that day and not what they do not. That is a real
     difference from the rest of the suite, and the reason this item stays on the list rather than
     being struck through.
   What would close it is an automated check in a real VS Code (`@vscode/test-electron` drives an
   Extension Development Host headlessly). **Decided 2026-09-06: envisagé, pas fait.** The author's
   call, taken while shipping the first public release: the panel is looked at constantly, and a
   headless VS Code in CI is a dependency, a runner and minutes of CI time to automate what is
   already being done. It stays written down here so that the day a regression does slip through,
   the answer is already designed rather than improvised.
2. ~~**`// @locale fr-FR` at the top of a file.**~~ **Settled, 2026-09-06: it will not be done.**
   The author's decision, and the reason is that the case it was meant to cover is already
   covered: `lmc.locale` is a setting now, with five languages and `es`/`ja`/`ko` in the enum, so
   choosing the language no longer requires touching a file. The per-file grain would have bought
   one thing the setting does not, a handout carrying its own language onto someone else's
   machine, and that is not worth a lexer, parser and semantic change in `lmc_lsp` plus a grammar
   rule and a header line in every example here. Checked before recording this: `lmc_lsp`'s own
   "Envisagé, pas fait" section does not list the directive either, so nothing upstream is waiting
   on it. Consequences that stay as they are: `model.gleam`'s `ErrorOccurred` branch renders in
   the locale the panel was told, and the examples carry no language header.
3. ~~**Externalise the message catalogues into per-language files (JSON).**~~ **Settled,
   2026-09-06: it will not be done.** Half of what this item asked for happened anyway, in a
   better shape: `lmc_lsp` v0.8.1 split its catalogue into one Gleam module per language and this
   repo followed (`src/webview/text/{french,english,spanish,japanese,korean}.gleam`), so adding a
   language is already one file and one arm, with no existing translation touched, and five
   languages ship. What is refused is the remaining step, turning those modules into JSON data
   read at build time. Its only real gain is letting someone who does not write Gleam translate,
   and there is no such translator: one author, a private server repo, no distribution. The cost
   is what the compiler stops guaranteeing, which the item itself listed: a test walking every
   variant x every language, a placeholder check, a per-message fallback, all of it work to buy
   back what exhaustive `case` gives for free today.
   The argument this item made about **the 26 examples and `LANGAGE.md` being French** does not
   apply either: `examples/` sits at the repo root and `vsce` archives `vscode-extension/` and
   nothing above it, so the examples are **not shipped in the `.vsix`** at all, today. They are
   development material, opened by the `F5` launch config. If they are ever shipped, their
   language becomes a question again; until then it is not one.
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
   removed, they are the arrangement. Do not re-propose making it public.
   **One half of the reasoning did expire the same day, and only that half.** This entry used to
   add "there is no audience to distribute to" and "no public release is planned"; the extension is
   now published on the Marketplace and `lmc-vscode` itself is a public GitHub repo. It changed
   nothing about the dependency, because the `.vsix` ships the **built bundle**, not the source: a
   private server can be distributed publicly in compiled form, and is. What it does change is that
   the passage under "Relationship to `lmc_lsp`" about revisiting this if a public release makes a
   private dependency impractical is now live rather than hypothetical, and the answer, tested by
   actually publishing, is that it does not.
6. **No Zed extension exists yet, and it is not work for this repo.** Settled, 2026-09-06: it is
   a separate chantier, in its own repo, consuming `lmc_lsp` the way this one does. Editor
   independence was the explicit reason to keep the two repos separate (see "Relationship to
   `lmc_lsp`" above), and this is what that independence is for. Private does not prevent it: a
   Zed extension would fetch the bundle the same authenticated way this one does. Nothing here
   blocks it and nothing here has to change for it, which is the point.
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
8. ~~**Renaming the language itself** (`LMC` → ?).~~ **Settled, 2026-09-06: it stays `LMC`.** The
   author's decision. So nothing changes here — `.lmc`, `.lmcobj`, the `lmc` language id, the
   `source.lmc` grammar scope and the 26 example programs all stand, and the "file extension goes
   first or never" ordering rule is moot: it is never.
   Two things worth keeping from the analysis, which lives in `lmc_lsp`'s CLAUDE.md. The
   compatibility argument for keeping the name got **stronger**, not weaker, after it was measured
   here: a classic LMC program comes in for the price of a colon after each label, so the shared
   name still buys something real (see the READMEs). And if only the "Man" ever grates, there is a
   zero-file option that was already noted there: keep `LMC` and change what it expands to, in
   French — « Le Mini-Calculateur ».
   The other three planned language changes are long done: `X` → `IX` then `IX` → `SI`, opcode 9 in
   families with `PSH`/`POP` on a register, and the screen instruction, shipped as **`PLT`** rather
   than `PIX` — the verb names the action and lets the data be called what it likes, the same split
   as `STA total`.
9. **Spanish, Japanese and Korean have not been read by anyone who speaks them.** Deferred, not
   refused: 2026-09-06 the author's answer was "plus tard". Each of the three files says so in its
   own header and the Marketplace page asks for corrections, so the gap is visible where it
   matters rather than only here. Nothing else waits on it: the languages ship, and a correction
   is one file and no interface change.
10. ~~**Colour every name a `DAT` declares, via semantic tokens.**~~ **Settled, 2026-09-06: it will
   not be done.** `lmc_lsp` had it under "Envisagé, pas fait" (it would be `semanticTokensProvider`
   plus a `features/semantic_tokens.gleam` there, and strictly nothing here, since
   `vscode-languageclient` handles the tokens as soon as the server announces them). The author's
   decision covers both sides. The analysis stays in `lmc_lsp`'s CLAUDE.md if it ever comes back;
   the reservation worth remembering is that such a colour would be **provenance, not machine
   state**, the same status as the dotted `DAT` marking in the memory grid.
