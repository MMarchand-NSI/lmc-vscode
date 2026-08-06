# lmc-vscode

A Visual Studio Code extension for the **Little Man Computer (LMC)** assembly language, providing a full language server with syntax-aware editing features.

## Features

- **Diagnostics** — real-time error and warning highlighting:
  - undefined labels
  - duplicate label definitions
  - missing `HLT` instruction
  - programs exceeding 100 instructions
- **Hover** — shows where a label is defined and how many times it is referenced
- **Go to Definition** — jump to the line where a label is defined
- **Find References** — list every line that references a label
- **Completion** — auto-complete LMC mnemonics (with descriptions) and labels defined in the current file
- **Formatting** — canonical reformatting of the whole document

## LMC Instruction Set

| Mnemonic | Operation |
|---|---|
| `ADD addr` | ACC = ACC + mem[addr] |
| `SUB addr` | ACC = ACC − mem[addr] |
| `STA addr` | mem[addr] = ACC |
| `LDA addr` | ACC = mem[addr] |
| `BRA addr` | branch always to addr |
| `BRZ addr` | branch to addr if ACC = 0 |
| `BRP addr` | branch to addr if ACC ≥ 0 |
| `INP` | ACC = next input value |
| `OUT` | output ACC |
| `HLT` | halt execution |
| `DAT [n]` | define data cell (default 0) |

Labels are case-insensitive. Comments start with `//` or `;`.

## Project Structure

```
lsp-server.mjs         # LSP entry point: loads vendor/lmc-lsp.bundle.mjs
examples/              # Opened automatically by the "Run LMC Extension" launch config
  test-pgm.lmc          # (F5) — a valid program and a deliberately broken one, so
  broken.lmc            # there's always something to try without editing anything
scripts/
  fetch-lsp-bundle.mjs # Downloads a tagged lmc_lsp release into vendor/ (gitignored)
src/
  webview/
    app.gleam          # Interactive emulator UI (planned)
vscode-extension/
  client.ts            # VS Code extension host
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
   in its own repo, not here: `lsp-server.mjs` loads a tagged release fetched into
   `vendor/lmc-lsp.bundle.mjs` by `node scripts/fetch-lsp-bundle.mjs` (requires the `gh` CLI,
   authenticated with access to that repo, which is currently private — run the script before first
   use, there is no in-tree fallback).

```
VS Code ←—LSP (stdio)—→ lsp-server.mjs → vendor/lmc-lsp.bundle.mjs (fetched from lmc_lsp releases)
```

The [Emulator API](#emulator-api) is unrelated to the above and to the extension at runtime — it's a
Gleam-only, `gleam.toml`-level dependency on the same `lmc_lsp` package, for programmatic use.

## Development

### Prerequisites

- [Gleam](https://gleam.run) ≥ 1.0 (CI pins 1.14.0) — only needed for the standalone Emulator API,
  not for running the extension
- Node.js ≥ 18
- [`gh`](https://cli.github.com) CLI, authenticated with access to `MMarchand-NSI/lmc_lsp` (currently
  private) — needed both to fetch the language server below, and locally by `gleam deps download`
  (via its git-credential helper) to pull `lmc_lsp` as a Gleam dependency for the Emulator API

### Fetch the language server

```sh
node scripts/fetch-lsp-bundle.mjs        # fetches the latest tagged release into vendor/
node scripts/fetch-lsp-bundle.mjs v0.1.1 # or a specific version
```

Required before the extension will start — there is no in-tree fallback.

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
npx tsc           # Compile TypeScript
npx vsce package  # Package as .vsix
```

## Emulator API

`gleam.toml` depends on [`lmc_lsp`](https://github.com/MMarchand-NSI/lmc_lsp) as a git dependency —
not a copy of its code — for programmatic assembling/running of LMC programs, independently of the
extension:

```gleam
import lmc/semantic/pipeline
import lmc/runner/load
import lmc/runner/run
import lmc/runner/state

// Batch mode — provide all input upfront
let result = pipeline.parse(source)     // -> ParseResult { ast, diagnostics, symbols, ... }
let assert Ok(initial) = load.load(result, [input1, input2])
let #(final, _events) = run.run_to_halt(initial)
// final.output → list of output values
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
