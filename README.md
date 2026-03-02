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

Labels are case-insensitive. Comments start with `//` or `#`.

## Project Structure

```
src/
  lmc/
    lexer.gleam       # Tokeniser
    parser.gleam      # Parser (nibble combinators) → AST
    analyser.gleam    # Semantic analysis → diagnostics & symbol table
    emulator.gleam    # Assembler + virtual machine
  lsp/
    server.gleam      # LSP server (JSON-RPC over stdio)
    lsp_ffi.mjs       # Node.js FFI — stdin/stdout transport
  dap/
    server.gleam      # DAP debug adapter (planned)
  webview/
    app.gleam         # Interactive emulator UI (planned)
vscode-extension/
  client.ts           # VS Code extension host
  package.json
test/
  lexer_test.gleam
  parser_test.gleam
  emulator_test.gleam
```

## Architecture

The extension runs two processes:

1. **VS Code extension host** (`vscode-extension/`) — TypeScript client that starts the language server and relays LSP messages between VS Code and the server.
2. **Language server** (`src/lsp/server.gleam`) — a Gleam/Node.js process that compiles on each document change (`lexer → parser → analyser`) and responds to LSP requests over stdin/stdout.

```
VS Code ←—LSP (stdio)—→ lmc-language-server (Node.js)
                              │
                    lexer → parser → analyser
```

## Development

### Prerequisites

- [Gleam](https://gleam.run) ≥ 1.0
- Node.js ≥ 18

### Build & test

```sh
gleam test        # Run all 48 tests (lexer, parser, emulator)
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
