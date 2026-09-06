# lmc-vscode

A Visual Studio Code extension for the **Little Man Computer (LMC)** assembly language, providing a full language server with syntax-aware editing features.

## Features

- **Diagnostics** — real-time error and warning highlighting:
  - undefined labels
  - duplicate label definitions
  - missing `HLT` instruction
  - programs whose code and data exceed the 100 memory cells
  - addresses outside 0-99, which would otherwise assemble into a different instruction entirely
- **Hover** — shows where a label is defined and how many times it is referenced
- **Go to Definition** — jump to the line where a label is defined
- **Find References** — list every line that references a label
- **Completion** — auto-complete LMC mnemonics (with descriptions) and labels defined in the current file
- **Formatting** — canonical reformatting of the whole document
- **Emulator webview** — "LMC: Open Emulator" command: a step-through visual emulator (memory grid,
  registers, input/output trays) synced bidirectionally with the source editor — see
  [Emulator webview](#emulator-webview)

## The LMC language

The language reference — instructions, registers, addressing, encoding, diagnostics — lives with
the language itself, in
[lmc_lsp/LANGAGE.md](https://github.com/MMarchand-NSI/lmc_lsp/blob/master/LANGAGE.md) (in French).
It is deliberately not duplicated here: this README used to carry its own instruction table, and
that table drifted into claiming things that were false — that labels were case-insensitive, and
that `;` opened a comment. One source of truth is worth the extra click.

In short: this variant extends the classic LMC. The machine word is four digits rather than three,
there are five registers (`ACC`, `SI`, `LR`, `SP`, `PC`) and seventeen mnemonics, including `MOV`,
subroutines (`JSR`/`RET`), a stack (`PSH`/`POP`) and a screen (`PLT`). Programs written for a stock LMC emulator will
not run here, and the reverse is also true.

## Examples

`examples/` is what the F5 launch config opens, so there is always something to run. The comments
are in French, like the language reference.

| | |
|---|---|
| `test-pgm.lmc`, `fibo.lmc` | integer division and Fibonacci — the eleven classic mnemonics only |
| `broken.lmc` | deliberately invalid, to see the diagnostics |
| `tableau.lmc` | an array walked with `lst[SI]` |
| `affiche_tab.lmc` | the same walk, one instruction shorter: `MOV SI, i` loads a cell straight into `SI` |
| `chaine.lmc` | a string walked to its terminal zero |
| `double-boucle.lmc` | nested loops: a multiplication table, since the language has no multiply |
| `ecran.lmc` | `PLT` — a diagonal and a line, on the 32 × 32 screen |
| `sous-programme.lmc` | `JSR`/`RET` — enough as long as calls are not nested |
| `appel-imbrique-casse.lmc` | a nested call overwrites `LR`: the program loops, on purpose |
| `appel-imbrique-pile.lmc` | the same program, fixed by saving `LR` with `PSH`/`POP` |
| `recursion.lmc` | `somme(n) = n + somme(n-1)`, one stack frame per call |
| `unit-01` … `unit-13` | a progressive series, one new thing per file, from `INP`/`OUT` to the loops |

The last three are a progression, in that order: `JSR` alone, the breakage it cannot survive, and
the stack that repairs it. That order is the one argued for in `lmc_lsp`'s ARCHI.md — the stack is
introduced because you have just hit the wall that needs it, not because it exists.

Every one of them is run before being committed; none is a program that only looks plausible. For
the `unit-*` series that is not a promise but a script: each file states its own cases in its header
(`Entrée : … Sortie : …`), and `node scripts/check-examples.mjs` runs every one of them against the
real `lmc_lsp` dependency. That script also holds *every* example, series or not, to two rules: it
parses without a diagnostic (except `broken.lmc`, which is invalid on purpose) and it comes back
byte for byte unchanged from the formatter, so that an accidental Format Document cannot reindent a
course handout.

## Project Structure

```
examples/              # Opened automatically by the "Run LMC Extension" launch
  test-pgm.lmc          # config (F5) — see "Examples" below
  fibo.lmc
  broken.lmc
  tableau.lmc
  affiche_tab.lmc
  chaine.lmc
  double-boucle.lmc
  sous-programme.lmc
  appel-imbrique-casse.lmc
  appel-imbrique-pile.lmc
  recursion.lmc
  ecran.lmc
  unit-01-inp-out.lmc … unit-13-boucle-somme.lmc
scripts/
  build-lsp-bundle.mjs # Bundles lmc_lsp into vscode-extension/vendor/ (needs gleam build)
  check-lsp.mjs        # Runs lmc_lsp's own LSP integration suite against that bundle
  build-webview.mjs    # Bundles src/webview/ for the browser into vscode-extension/webview/
  smoke-webview.mjs    # Drives that bundle in jsdom, playing the extension host's half
  check-examples.mjs   # Every *.lmc parses clean and is already formatted; unit-* also runs
                       #   the cases in its own header
  check-grammar.mjs    # Checks the TextMate grammar against lmc_lsp's lexer, with Oniguruma
src/
  webview/              # Emulator webview — see "Emulator webview" below
    model.gleam          # Pure state/transitions (gleam test-covered)
    render.gleam          # Model -> view-model JSON (gleam test-covered)
    app.gleam              # Entry point: wires model+render to ffi.gleam
    ffi.gleam                # External declarations, implemented in app_ffi.mjs
    app_ffi.mjs                # DOM + VS Code webview postMessage bridge
vscode-extension/      # Everything in here ships in the .vsix
  lsp-server.mjs       # LSP entry point: loads vendor/lmc-lsp.bundle.mjs
  vendor/
    lmc-lsp.bundle.mjs  # Built by build-lsp-bundle.mjs (gitignored)
  client.ts            # VS Code extension host
  webviewPanel.ts       # Creates/manages the emulator panel, editor <-> webview sync
  webview/
    index.html            # Static shell (placeholders filled in by webviewPanel.ts)
    style.css
    app.bundle.js          # Built by build-webview.mjs (gitignored)
  package.json
test/
  emulator_test.gleam  # Smoke test for the Emulator API, see below
```

There is no local lexer/parser/emulator anymore — the Emulator API is the `lmc_lsp` Gleam package
itself, pulled in as a git dependency (see `gleam.toml`), not copied files.

## Architecture

The extension runs two processes:

1. **VS Code extension host** (`vscode-extension/`) — TypeScript client that starts the language
   server and relays LSP messages between VS Code and the server.
2. **Language server** — [`lmc_lsp`](https://github.com/MMarchand-NSI/lmc_lsp), a standalone,
   editor-agnostic Gleam/Node.js LSP server that also targets other LSP clients (e.g. Zed). It lives
   in its own repo, not here: `vscode-extension/lsp-server.mjs` loads a tagged release fetched into
   `vscode-extension/vendor/lmc-lsp.bundle.mjs` by `node scripts/build-lsp-bundle.mjs`, out of the
   same clone `gleam deps download` makes (requires the `gh` CLI, authenticated with access to that
   repo, which is currently private — run both before first use, there is no in-tree fallback).

```
VS Code ←—LSP (stdio)—→ vscode-extension/lsp-server.mjs → vendor/lmc-lsp.bundle.mjs (built from the lmc_lsp dep)
```

The [Emulator API](#emulator-api) is unrelated to the above and to the extension at runtime — it's a
Gleam-only, `gleam.toml`-level dependency on the same `lmc_lsp` package, for programmatic use.

## Development

### Prerequisites

- [Gleam](https://gleam.run) ≥ 1.18 (`gleam.toml` sets the floor; CI installs 1.18.1) — only needed for the standalone Emulator API,
  not for running the extension
- Node.js ≥ 18
- [`gh`](https://cli.github.com) CLI, authenticated with access to `MMarchand-NSI/lmc_lsp` (currently
  private) — used by `gleam deps download`, via its git-credential helper, to clone `lmc_lsp` as a
  Gleam dependency. That one clone is the whole of what this repo takes from it: the language
  server, the emulator and the Gleam library all come out of it

### Build the language server

```sh
gleam deps download                  # clones lmc_lsp at the tag in gleam.toml
gleam build                          # compiles it (and this project) to build/dev/javascript/
node scripts/build-lsp-bundle.mjs    # bundles it into vscode-extension/vendor/lmc-lsp.bundle.mjs
node scripts/check-lsp.mjs           # runs lmc_lsp's own integration suite against that bundle
```

Required before the extension will start — there is no in-tree fallback. The bundle used to be
downloaded from a tagged release instead; it is built here now, so that the version lives in
`gleam.toml` and nowhere else. `build-lsp-bundle.mjs` takes its esbuild options from `lmc_lsp`'s own
`package.json` rather than repeating them, and `check-lsp.mjs` makes the artefact face the same
48-assertion suite the upstream CI runs, which is what the published bundle had going for it.

### Build & test the Emulator API

```sh
gleam deps download # pulls lmc_lsp itself as a git dependency (see gleam.toml) — needs gh auth,
                     # same as above
gleam test           # Run all tests
gleam build          # Compile to build/dev/javascript/
```

### Build the VS Code extension

```sh
cd vscode-extension
npm install
npm run compile   # Compile TypeScript — not `npx tsc`, which fetches an unrelated
                  #   registry package named `tsc` when the local one is out of reach
npx vsce package  # Package as .vsix
```

The `.vsix` is self-contained: `lsp-server.mjs` and `vendor/lmc-lsp.bundle.mjs` live inside
`vscode-extension/` precisely so that they end up in the archive, along with the compiled
`out/client.js`, the webview bundle and the one runtime dependency (`vscode-languageclient`). An
installed extension has no repo around it. Run `node scripts/build-lsp-bundle.mjs`,
`node scripts/build-webview.mjs` and `npm run compile` before packaging, or the archive will be
missing one of the three.

`@types/vscode` is pinned exactly to `1.80.0` to match `engines.vscode`: `vsce` refuses to package
when the types are newer than the oldest VS Code the extension claims to support, and `^1.80.0`
resolves to whatever the latest minor is.

### Build the emulator webview

```sh
gleam build                    # compiles src/webview/*.gleam
node scripts/build-webview.mjs # bundles them for the browser into vscode-extension/webview/app.bundle.js
```

Required before "LMC: Open Emulator" will show anything — `app.bundle.js` is gitignored, same
reasoning as `vendor/lmc-lsp.bundle.mjs`. Re-run after any change under `src/webview/`.

## Emulator API

`gleam.toml` depends on [`lmc_lsp`](https://github.com/MMarchand-NSI/lmc_lsp) as a git dependency —
not a copy of its code — for programmatic assembling/running of LMC programs, independently of the
extension:

```gleam
import lmc/semantic/pipeline
import lmc/runner/inspect
import lmc/runner/load
import lmc/runner/run
import lmc/runner/state

// Batch mode — provide all input upfront
let result = pipeline.parse(source)     // -> ParseResult { ast, diagnostics, symbols, ... }
let assert Ok(initial) = load.load(result, [input1, input2])
let #(final, _events) = run.run_to_halt(initial)
// inspect.output_buffer(final) → list of output values, oldest first.
//   The field itself is `output_reversed`, kept newest-first so that OUT
//   costs a cons instead of copying the buffer; output_buffer reverses once.
// final.status → state.Halted (or state.ExecutionError(_) on a runtime error)

// Interactive mode — supply input on demand
let #(paused, _events) = run.run_to_halt(initial)
// paused.status == state.WaitingForInput
let resumed = run.resume(paused, 42)
let #(final, _events) = run.run_to_halt(resumed)
```

`run_to_halt` actually runs until the machine *stops progressing* — halted, errored, or waiting on
`INP` — not necessarily until `Halted`; check `.status` to tell which. `_events` is the list of
`Fetched`/`Decoded`/`InputConsumed`/`OutputProduced`/... events the interpreter produced along the
way, useful for tracing/debugging. See `lmc_lsp`'s own `CLAUDE.md`/`ARCHI.md` for the full API.

## Emulator webview

"LMC: Open Emulator" (editor title bar icon, or the command palette, on an open `.lmc` file) opens a
step-through visual emulator beside the editor: a 100-mailbox memory grid, ACC/PC/status, an output
tray, and an inline prompt when the program hits `INP`.

It runs **inside the webview, in the browser, not through the extension host on every step** —
`src/webview/*.gleam` compiles to JS and gets bundled for the browser
(`scripts/build-webview.mjs`), using the same `lmc_lsp` runner as the [Emulator API](#emulator-api)
above. The extension host (`vscode-extension/webviewPanel.ts`) only creates the panel and relays two
kinds of messages — the source text, and cursor/click position — so the machine steps instantly
without a round trip for every click.

**Editor sync, in both directions**: moving the cursor in the editor outlines the corresponding
mailbox; clicking a mailbox reveals its source line in the editor. This only works because it's a
real webview next to a real editor — a standalone web-based LMC simulator can't do this, which is
the reason this exists as a webview instead of just linking out to one.
