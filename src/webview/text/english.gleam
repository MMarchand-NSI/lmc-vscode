//// The panel, in English.
////
//// Les valeurs sont dans `webview/text/message.gleam`, la répartition dans
//// `webview/text/locale.gleam`. Ce fichier ne fait que rendre.

import gleam/int
import lmc/text/locale
import webview/text/message.{type Circuit, type Label, type Text}

// gardent, comme le fait `lmc_lsp` pour ses diagnostics.

pub fn render(text: Text) -> String {
  case text {
    message.FetchRead(address, word) ->
      "read mem[" <> int.to_string(address) <> "] → " <> int.to_string(word)
    message.FetchIncrement(from, to) ->
      "PC "
      <> int.to_string(from)
      <> " → "
      <> int.to_string(to)
      <> " (incremented during the read, before decoding)"

    message.DecodedPlain(word, mnemonic, circuit) ->
      int.to_string(word)
      <> " → "
      <> mnemonic
      <> " ("
      <> circuit_text(circuit)
      <> ")"
    message.DecodedWithOperand(word, mnemonic, operand, circuit) ->
      int.to_string(word)
      <> " → "
      <> mnemonic
      <> ", "
      <> operand
      <> " ("
      <> circuit_text(circuit)
      <> ")"
    message.DecodedMove(word, destination, source, alias, circuit) ->
      int.to_string(word)
      <> " → MOV "
      <> destination
      <> ", "
      <> source
      <> message.shortcut(alias)
      <> " ("
      <> circuit_text(circuit)
      <> ")"
    message.DecodedPlot(word, address, circuit) ->
      int.to_string(word)
      <> " → PLT, "
      <> message.three_cells(address)
      <> " → x, y, colour ("
      <> circuit_text(circuit)
      <> ")"

    message.InputTaken(value) -> "ACC ← input (" <> int.to_string(value) <> ")"
    message.OutputSent(value) -> "output ← ACC (" <> int.to_string(value) <> ")"
    message.PixelSent(x, y, colour, outcome) ->
      "screen ← pixel ("
      <> int.to_string(x)
      <> ", "
      <> int.to_string(y)
      <> "), colour "
      <> int.to_string(colour)
      <> case outcome {
        message.Drawn -> ""
        message.OffScreen(width, height) ->
          " — off screen ("
          <> int.to_string(width)
          <> " × "
          <> int.to_string(height)
          <> "): nothing is lit"
        message.OffPalette(highest) ->
          " — outside the palette (0 to "
          <> int.to_string(highest)
          <> "): nothing is lit"
      }
    message.MemoryWritten(address, value) ->
      "mem["
      <> int.to_string(address)
      <> "] ← ACC ("
      <> int.to_string(value)
      <> ")"
    message.RegisterChanged(register, from, to) ->
      register <> " " <> int.to_string(from) <> " → " <> int.to_string(to)
    message.LinkChanged(from, to) ->
      "LR "
      <> int.to_string(from)
      <> " → "
      <> int.to_string(to)
      <> " (return address)"
    message.Jumped(from, to) ->
      "PC "
      <> int.to_string(from)
      <> " → "
      <> int.to_string(to)
      <> " (writing to the program counter)"
    message.Halted -> "HLT"
    message.WaitingForInput -> "waiting for an input…"

    message.RunnerError(reason) -> locale.render(reason, locale.English)
    message.SourceHasErrors ->
      "the program has errors — see the diagnostics in the editor"
    message.ProgramTooLong(cells) ->
      "program too long: " <> int.to_string(cells) <> " cells (maximum 100)"
    message.UndefinedLabel(name) -> "undefined label: " <> name
    message.NoObjectFile(name) ->
      "no object file to load (" <> name <> ") — assemble first"
    message.ObjectFileEmpty -> "the object file is empty"
    message.ObjectFileUnreadableLine(line) ->
      "the object file has a line that cannot be read: `" <> line <> "`"
    message.ObjectFileTooLong(cells) ->
      "the object file is larger than the 100 cells of memory ("
      <> int.to_string(cells)
      <> ")"
  }
}

fn circuit_text(circuit: Circuit) -> String {
  "setting up the processor's circuits for "
  <> case circuit {
    message.ReadingInput -> "reading an input"
    message.WritingOutput -> "writing the output"
    message.StoppingProcessor -> "stopping the processor"
    message.Addition -> "an addition"
    message.Subtraction -> "a subtraction"
    message.LoadFromMemory -> "a load from memory"
    message.StoreToMemory -> "a store to memory"
    message.RegisterTransfer -> "a register-to-register transfer"
    message.PushRegister -> "pushing a register"
    message.PopRegister -> "popping into a register"
    message.SendPixel -> "sending a pixel to the screen"
    message.JumpAndLink -> "a jump that remembers the return address"
    message.Jump -> "a jump"
    message.JumpIfZero -> "a conditional jump (if ACC = 0)"
    message.JumpIfPositive -> "a conditional jump (if ACC ≥ 0)"
  }
}

pub fn label(label: Label) -> String {
  case label {
    message.PageTitle -> "LMC — Emulator"
    message.ButtonStep -> "Step"
    message.ButtonRun -> "Run"
    message.ButtonReset -> "Reset"
    message.ButtonAssemble -> "Assemble .lmc"
    message.ButtonLoad -> "Load .lmcobj into RAM"
    message.ButtonOk -> "OK"
    message.TipAssembleTitle -> "Produce the object file"
    message.TipAssembleBody ->
      "writes .lmcobj next to the source: one four-digit word per line, no mnemonics and no labels, because that is all the processor ever receives. Assembling LDA 42 and MOV ACC, 42 gives the same line twice. Runs nothing and loads nothing."
    message.TipLoadTitle -> "Load into RAM"
    message.TipLoadBody ->
      "reads .lmcobj back off the disk and lays it out in memory. It really is the file that gets loaded: without it nothing runs, and if you edit the source without reassembling, you load the old program. A real toolchain behaves exactly like this."
    message.StatusLabel -> "Status"
    message.TipStatusTitle -> "Processor status"
    message.TipStatusBody ->
      "empty (nothing is in RAM: assemble, then load), running (ready to execute), waiting_input (stopped on an INP, waiting for a value), halted (stopped by HLT), error."
    message.HeadingProcessor -> "Processor"
    message.TipAccTitle -> "Accumulator"
    message.TipAccBody ->
      "the accumulator. All arithmetic and all input/output go through it: ADD, SUB, INP and OUT work on ACC and nothing else."
    message.TipPcTitle -> "Program Counter"
    message.TipPcBody ->
      "the address of the next instruction to read. Writing to it is jumping, and that is all BRA, BRZ, BRP and RET do. It is incremented during the Fetch phase, as on a real processor — so a stopped machine already points past the last instruction executed."
    message.TipSiTitle -> "Source Index"
    message.TipSiBody ->
      "the index register, named after the x86's SI, where it plays the same role. The [SI] suffix adds its contents to the address written — lst[SI] means the cell lst + SI, which is what lets one instruction walk an array or a string whatever the position read."
    message.TipLrTitle -> "Link Register"
    message.TipLrBody ->
      "the return address, under its ARM name. JSR writes the address of the instruction after the call into it, RET goes back there. LR holds exactly one: a nested call overwrites it, and that is what makes the stack necessary."
    message.TipSpTitle -> "Stack Pointer"
    message.TipSpBody ->
      "points at the next free cell. The stack grows down from cell 99; PSH stores a register there, POP takes it back. Written without a register, both work on ACC."
    message.HeadingIo -> "Input / Output"
    message.HeadingInput -> "Input (INP)"
    message.InputValueLabel -> "Value"
    message.HeadingOutput -> "Output (OUT)"
    message.HeadingScreen -> "Screen (PLT)"
    message.TipScreenTitle -> "PLT addr"
    message.TipScreenBody ->
      "light a pixel. The instruction reads three consecutive cells starting at addr: x, y, then the colour, a palette index. The processor knows neither the size of the screen nor the colours: it says `light this pixel`, the display decides the rest. Here, 32 × 32 pixels and eight colours."
    message.ScreenAria -> "Screen, 32 by 32 pixels"
    message.HeadingMemory -> "Memory"
    message.MemoryNote ->
      "One memory for the program and for the data: that is von Neumann's principle, and that is what the markings below show."
    message.LegendProgram -> "Program"
    message.LegendData -> "Data (DAT)"
    message.LegendStack -> "Stack"
    message.LegendFree -> "Free"
    message.CycleSummary -> "Fetch → Decode → Execute"
    message.CycleHint ->
      "Every instruction, whatever its mnemonic, goes through the same three phases. Here is what happened on the last step:"
  }
}
//
// Des mots machine, des adresses et des noms de registres : rien à
// traduire, et une seule écriture pour que les deux ne divergent pas.
