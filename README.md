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
scripts/
  fetch-lsp-bundle.mjs # Downloads a tagged lmc_lsp release into vendor/ (gitignored)
src/
  lmc/
    lexer.gleam        # Tokeniser  ┐
    parser.gleam       # Parser (nibble combinators) → AST  ├─ standalone Emulator API,
    emulator.gleam     # Assembler + virtual machine  ┘        see below — not used by the LSP
  webview/
    app.gleam          # Interactive emulator UI (planned)
vscode-extension/
  client.ts            # VS Code extension host
  package.json
test/
  lexer_test.gleam
  parser_test.gleam
  emulator_test.gleam
```

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

`src/lmc/{lexer,parser,emulator}.gleam` are unrelated to the above — they exist only for the
standalone [Emulator API](#emulator-api), independent of the LSP.

## Development

### Prerequisites

- [Gleam](https://gleam.run) ≥ 1.0 (CI pins 1.14.0) — only needed for the standalone Emulator API,
  not for running the extension
- Node.js ≥ 18
- [`gh`](https://cli.github.com) CLI, authenticated with access to `MMarchand-NSI/lmc_lsp` — needed
  to fetch the language server (see [Architecture](#architecture))

### Fetch the language server

```sh
node scripts/fetch-lsp-bundle.mjs        # fetches the latest tagged release into vendor/
node scripts/fetch-lsp-bundle.mjs v0.1.0 # or a specific version
```

Required before the extension will start — there is no in-tree fallback.

### Build & test the Emulator API

```sh
gleam test        # Run all tests (lexer, parser, emulator)
gleam build       # Compile to build/dev/javascript/
```

### Build the VS Code extension

```sh
cd vscode-extension
npm install
npx tsc           # Compile TypeScript
npx vsce package  # Package as .vsix
```

## Emulator API

The emulator can be used independently of the LSP, in batch or interactive mode:

```gleam
import lmc/lexer
import lmc/parser
import lmc/emulator

// Batch mode — provide all input upfront
let assert Ok(program) = source |> lexer.tokenize |> parser.parse
let assert Ok(state)   = emulator.load(program, [input1, input2])
let assert Ok(final)   = emulator.run(state)
// final.output → list of output values

// Interactive mode — supply input on demand
let assert Ok(emulator.NeedsInput(paused)) = emulator.step(state)
let resumed = emulator.provide_input(paused, 42)
let assert Ok(final) = emulator.run(resumed)
```
