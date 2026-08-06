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
- **Formatting** — canonical reformatting of the whole document (only available when running against the standalone `lmc_lsp` server — see [Architecture](#architecture))

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
lsp-server.mjs         # LSP entry point: prefers vendor/lmc-lsp.bundle.mjs, falls back to
                       # the in-tree server below
scripts/
  fetch-lsp-bundle.mjs # Downloads a tagged lmc_lsp release into vendor/ (gitignored)
src/
  lmc/
    lexer.gleam        # Tokeniser
    parser.gleam       # Parser (nibble combinators) → AST
    analyser.gleam     # Semantic analysis → diagnostics & symbol table
    emulator.gleam     # Assembler + virtual machine
  lsp/
    server.gleam       # Legacy in-tree LSP server (JSON-RPC over stdio) — fallback only
    lsp_ffi.mjs       # Node.js FFI — stdin/stdout transport
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

1. **VS Code extension host** (`vscode-extension/`) — TypeScript client that starts the language server and relays LSP messages between VS Code and the server.
2. **Language server** — `lsp-server.mjs` picks between two, in order:
   - **Preferred**: [`lmc_lsp`](https://github.com/MMarchand-NSI/lmc_lsp), a standalone, editor-agnostic
     rewrite of the server (adds formatting, byte-correct LSP framing, and is meant to also work with
     other LSP clients such as Zed). It lives in its own repo, not here — fetch a tagged release into
     `vendor/lmc-lsp.bundle.mjs` with `node scripts/fetch-lsp-bundle.mjs` (requires the `gh` CLI,
     authenticated with access to that repo, which is currently private).
   - **Fallback**: this repo's own `src/lsp/server.gleam` + `src/lmc/*` (`lexer → parser → analyser`),
     compiled locally with `gleam build`. Used automatically whenever the vendored bundle hasn't been
     fetched, so the extension still works without the extra step above.

```
                                              ┌─ vendor/lmc-lsp.bundle.mjs             (preferred,
                                              │    fetched from lmc_lsp releases)
VS Code ←—LSP (stdio)—→ lsp-server.mjs ──────┤
                                              └─ build/.../lmc_vscode/lsp/server.mjs   (fallback,
                                                   lexer → parser → analyser)
```

## Development

### Prerequisites

- [Gleam](https://gleam.run) ≥ 1.0 (CI pins 1.14.0)
- Node.js ≥ 18
- [`gh`](https://cli.github.com) CLI, authenticated with access to `MMarchand-NSI/lmc_lsp` — only
  needed to fetch the preferred language server (see [Architecture](#architecture)); everything else
  works without it, using the fallback server

### Build & test

```sh
gleam test        # Run all tests (lexer, parser, emulator)
gleam build       # Compile the fallback server to build/dev/javascript/
```

### Use the standalone `lmc_lsp` server (recommended)

```sh
node scripts/fetch-lsp-bundle.mjs        # fetches the latest tagged release into vendor/
node scripts/fetch-lsp-bundle.mjs v0.1.0 # or a specific version
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
