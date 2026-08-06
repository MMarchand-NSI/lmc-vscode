import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import lmc/parse/span
import lmc/runner/event.{type Event}
import lmc/runner/instruction
import lmc/runner/load
import lmc/runner/run
import lmc/runner/state.{type MachineState}
import lmc/semantic/ast
import lmc/semantic/pipeline

// Pure application state for the emulator webview — no FFI, no DOM, fully
// testable with `gleam test`. app.gleam wires this up to the actual webview
// (FFI + rendering); this module never imports it, only the other way
// around.

pub type Model {
  Model(
    source: String,
    parse: Option(pipeline.ParseResult),
    machine: Option(MachineState),
    // Address <-> source line (0-indexed), derived once per `load_source`
    // from `load.address_offsets` — NOT re-derived by assuming address i is
    // ast.lines[i] (blank/comment-only lines don't get an address; see
    // lmc_lsp v0.1.5/v0.1.6). Powers the editor <-> webview sync both ways.
    address_to_line: Dict(Int, Int),
    line_to_address: Dict(Int, Int),
    // Same addressing as address_to_line (derived from the same
    // load.address_offsets call — see build_address_maps), just mapped to
    // the instruction itself instead of the line number. Powers the
    // current-instruction caption; not needed for the editor sync.
    address_to_instruction: Dict(Int, ast.Instruction),
    // Line the host's cursor is currently on — independent of execution
    // state, doesn't get reset by step/run/reset.
    cursor_line: Option(Int),
    load_error: Option(String),
    // Fetch/Decode/Execute events from the *last* step/run_to_halt call —
    // lmc_lsp's runner already produces these per sub-phase, previously
    // just discarded. Powers the collapsible "what actually just
    // happened" panel — the point being to show that every instruction,
    // no matter the mnemonic, goes through the same three phases.
    last_events: List(Event),
  )
}

pub fn init(source: String) -> Model {
  Model(
    source: "",
    parse: None,
    machine: None,
    address_to_line: dict.new(),
    line_to_address: dict.new(),
    address_to_instruction: dict.new(),
    cursor_line: None,
    load_error: None,
    last_events: [],
  )
  |> load_source(source)
}

/// Like load_source, but a no-op if `source` is unchanged from what's
/// already loaded. The webview host resends the source on every editor
/// refocus, not only on real edits (see webviewPanel.ts,
/// onDidChangeActiveTextEditor — it also needs to re-sync the cursor) — so
/// clicking back into the source editor must not blow away step-through
/// progress (PC/ACC/output) just because a SetSource happened to arrive
/// with unchanged text. `reset` goes through `load_source` directly and is
/// unaffected: it must reload even with unchanged text, that's the point
/// of a reset button.
pub fn set_source_if_changed(model: Model, source: String) -> Model {
  case source == model.source {
    True -> model
    False -> load_source(model, source)
  }
}

/// (Re)parse and (re)assemble `source`, resetting execution state. Input is
/// always empty at load time — INP is handled interactively via
/// `provide_input`, never supplied upfront (this is a step-through teaching
/// tool, not a batch runner).
pub fn load_source(model: Model, source: String) -> Model {
  let result = pipeline.parse(source)
  let address_to_line = build_address_to_line(result)
  let line_to_address = invert(address_to_line)
  let address_to_instruction = build_address_to_instruction(result)

  case result.diagnostics {
    [] ->
      case load.load(result, []) {
        Ok(machine) ->
          Model(
            ..model,
            source: source,
            parse: Some(result),
            machine: Some(machine),
            address_to_line: address_to_line,
            line_to_address: line_to_address,
            address_to_instruction: address_to_instruction,
            load_error: None,
            last_events: [],
          )
        Error(err) ->
          Model(
            ..model,
            source: source,
            parse: Some(result),
            machine: None,
            address_to_line: address_to_line,
            line_to_address: line_to_address,
            address_to_instruction: address_to_instruction,
            load_error: Some(load_error_message(err)),
            last_events: [],
          )
      }
    _ ->
      // Des erreurs de syntaxe/résolution existent déjà (visibles dans
      // l'éditeur via les diagnostics LSP) — pas la peine de dupliquer ce
      // signal ici, mais pas d'assemblage possible non plus.
      Model(
        ..model,
        source: source,
        parse: Some(result),
        machine: None,
        address_to_line: address_to_line,
        line_to_address: line_to_address,
        address_to_instruction: address_to_instruction,
        load_error: Some(
          "le programme contient des erreurs — voir les diagnostics dans l'éditeur",
        ),
        last_events: [],
      )
  }
}

pub fn reset(model: Model) -> Model {
  load_source(model, model.source)
}

/// Advance exactly one instruction (fetch/decode/execute), unless the
/// machine is halted, errored, or waiting on input.
pub fn step(model: Model) -> Model {
  case model.machine {
    None -> model
    Some(m) -> {
      let #(next, events) = run.run_n(m, 1)
      Model(
        ..model,
        machine: Some(next),
        last_events: accumulate_events(m, model, events),
      )
    }
  }
}

/// Run until the machine stops progressing on its own — halted, errored, or
/// waiting on INP (not necessarily Halted, see lmc_lsp's own docs on
/// run_to_halt).
pub fn run_to_halt(model: Model) -> Model {
  case model.machine {
    None -> model
    Some(m) -> {
      let #(next, events) = run.run_to_halt(m)
      Model(
        ..model,
        machine: Some(next),
        last_events: accumulate_events(m, model, events),
      )
    }
  }
}

/// Fetch and Decode only ever happen once per instruction, right at the
/// start (phase == Fetch); Execute can then pause (INP with no input) and
/// resume later without repeating them. If the machine we're stepping
/// *from* wasn't sitting at a fresh Fetch, this is a resume — append to
/// last_events instead of replacing it, so the panel shows the whole
/// instruction's cycle in one place (Fetch, Decode, "waiting", then the
/// rest of Execute once input arrives) instead of splitting it across two
/// separate, seemingly out-of-nowhere "Execute only" snapshots.
fn accumulate_events(
  before: MachineState,
  model: Model,
  new_events: List(Event),
) -> List(Event) {
  case before.phase {
    state.Fetch -> new_events
    _ -> list.append(model.last_events, new_events)
  }
}

pub fn provide_input(model: Model, value: Int) -> Model {
  case model.machine {
    None -> model
    Some(m) -> Model(..model, machine: Some(run.resume(m, value)))
  }
}

pub fn set_cursor_line(model: Model, line: Option(Int)) -> Model {
  Model(..model, cursor_line: line)
}

// ── Requêtes dérivées ─────────────────────────────────────────────

/// The mailbox address the machine is on, if any — either about to execute
/// (Running: PC hasn't been fetched from yet) or stuck on (WaitingForInput:
/// lmc_lsp's runner advances the PC during the *fetch* phase, before INP's
/// own execute phase can discover there's no input to consume — by the
/// time we observe WaitingForInput, PC already points one past the
/// instruction that's actually paused). This is what the memory-grid
/// highlight should key off; current_line is derived from it, for the
/// editor side of the sync.
pub fn current_address(model: Model) -> Option(Int) {
  case model.machine {
    None -> None
    Some(m) ->
      Some(case m.status {
        state.WaitingForInput -> m.program_counter - 1
        _ -> m.program_counter
      })
  }
}

/// The source line (0-indexed) for current_address, if that address maps
/// to one (it always should, for any address a real MachineState can be
/// paused/about-to-fetch on).
pub fn current_line(model: Model) -> Option(Int) {
  case current_address(model) {
    None -> None
    Some(addr) -> dict.get(model.address_to_line, addr) |> option.from_result
  }
}

/// The mailbox address corresponding to the host's current cursor line, if
/// that line holds an instruction at all (blank/comment/label-only lines
/// don't).
pub fn cursor_address(model: Model) -> Option(Int) {
  case model.cursor_line {
    None -> None
    Some(line) -> dict.get(model.line_to_address, line) |> option.from_result
  }
}

/// The source line for a given mailbox address, for "click a mailbox ->
/// reveal its source line" — the reverse of current_line/cursor_address.
pub fn line_for_address(model: Model, address: Int) -> Option(Int) {
  dict.get(model.address_to_line, address) |> option.from_result
}

/// Human-readable caption for the instruction at current_address, e.g.
/// "STA dividend — stocker ACC". Deliberately just the instruction as
/// written (mnemonic + operand text) plus a static one-line description of
/// what that mnemonic does — not the *resolved* effect (e.g. not "mem[7] =
/// ACC"), which would need pulling in the symbol table just for a caption.
/// Static and always correct beats dynamic and one more thing to get wrong.
pub fn current_instruction_text(model: Model) -> Option(String) {
  case current_address(model) {
    None -> None
    Some(addr) ->
      dict.get(model.address_to_instruction, addr)
      |> option.from_result
      |> option.map(describe_instruction)
  }
}

/// How many addresses the assembled program actually occupies — i.e. the
/// number of instruction-bearing lines, per load.address_offsets. Always a
/// contiguous range [0, count) since collect_addresses_loop in lmc_lsp
/// assigns addresses sequentially in source order; any address >= this is
/// outside the program (padding memory, always 0 until written). Lets the
/// webview de-emphasize those cells instead of giving all 100 equal visual
/// weight regardless of how short the program is.
pub fn program_length(model: Model) -> Int {
  dict.size(model.address_to_line)
}

/// One entry per *phase* (Fetch, Decode, Execute — never more than three),
/// each carrying the individual events that happened during it. Grouped
/// rather than one flat line per event: Execute alone can produce several
/// events (e.g. INP resuming: "waiting" then "ACC <- input" then "ACC
/// changed") — a flat list would show three lines all prefixed "Execute",
/// which reads as three separate Execute phases and undermines the exact
/// point of this panel (every instruction is Fetch, Decode, Execute — not
/// Fetch, Decode, Execute, Execute, Execute).
pub fn last_cycle(model: Model) -> List(CyclePhase) {
  model.last_events
  |> dedupe_input_accumulator_change
  |> list.map(event_phase_and_detail)
  |> group_consecutive_by_phase
}

/// INP with input available is the only case where the runner emits two
/// events for what reads as one fact: InputConsumed(v) immediately
/// followed by AccumulatorChanged(_, v) with that same value — "ACC <-
/// entrée (123)" then "ACC 0 -> 123" right after, both just saying ACC is
/// now 123. Every other ACC-changing instruction (ADD/SUB/LDA) emits only
/// AccumulatorChanged, so this is INP-specific, not a general pattern to
/// generalize away — drop the redundant AccumulatorChanged, keep
/// InputConsumed (it says *why* ACC changed, not just that it did).
fn dedupe_input_accumulator_change(events: List(Event)) -> List(Event) {
  case events {
    [
      event.InputConsumed(v) as consumed,
      event.AccumulatorChanged(_, new),
      ..rest
    ]
      if new == v
    -> [consumed, ..dedupe_input_accumulator_change(rest)]
    [first, ..rest] -> [first, ..dedupe_input_accumulator_change(rest)]
    [] -> []
  }
}

pub type CyclePhase {
  CyclePhase(name: String, details: List(String))
}

// ── Internals ──────────────────────────────────────────────────────

fn build_address_to_line(result: pipeline.ParseResult) -> Dict(Int, Int) {
  load.address_offsets(result.ast)
  |> list.map(fn(pair) {
    let #(addr, offset) = pair
    let pos = span.to_position(result.line_index, offset)
    #(addr, pos.line)
  })
  |> dict.from_list
}

fn invert(d: Dict(Int, Int)) -> Dict(Int, Int) {
  d
  |> dict.to_list
  |> list.map(fn(pair) { #(pair.1, pair.0) })
  |> dict.from_list
}

/// Same addressing as build_address_to_line (same load.address_offsets
/// call), matched back to the actual ast.Line by character offset — cheap
/// and precise, no need for span.to_position/line_index here since offsets
/// are already exact.
fn build_address_to_instruction(
  result: pipeline.ParseResult,
) -> Dict(Int, ast.Instruction) {
  load.address_offsets(result.ast)
  |> list.filter_map(fn(pair) {
    let #(addr, offset) = pair
    case list.find(result.ast.lines, fn(line) { line.span.start == offset }) {
      Error(_) -> Error(Nil)
      Ok(line) ->
        case line.instruction {
          Some(instr) -> Ok(#(addr, instr))
          None -> Error(Nil)
        }
    }
  })
  |> dict.from_list
}

fn describe_instruction(instr: ast.Instruction) -> String {
  case instr {
    ast.Inp(_) -> "INP — lire une entrée"
    ast.Out(_) -> "OUT — écrire la sortie"
    ast.Hlt(_) -> "HLT — arrêter le programme"
    ast.Add(op, _) -> "ADD " <> operand_text(op) <> " — additionner"
    ast.Sub(op, _) -> "SUB " <> operand_text(op) <> " — soustraire"
    ast.Sta(op, _) -> "STA " <> operand_text(op) <> " — stocker ACC"
    ast.Lda(op, _) -> "LDA " <> operand_text(op) <> " — charger dans ACC"
    ast.Bra(op, _) -> "BRA " <> operand_text(op) <> " — sauter"
    ast.Brz(op, _) -> "BRZ " <> operand_text(op) <> " — sauter si ACC = 0"
    ast.Brp(op, _) -> "BRP " <> operand_text(op) <> " — sauter si ACC ≥ 0"
    ast.Dat(Some(v), _) -> "DAT " <> int.to_string(v)
    ast.Dat(None, _) -> "DAT"
    ast.Invalid(_) -> "?"
  }
}

fn operand_text(op: ast.Operand) -> String {
  case op {
    ast.LabelRef(name, _) -> name
    ast.Immediate(v, _) -> int.to_string(v)
    ast.MissingOperand(_) -> ""
  }
}

/// #(phase, detail) — kept separate rather than pre-joined into one
/// "Phase : detail" string so group_consecutive_by_phase can merge same-
/// phase entries without string-parsing its own output back apart.
fn event_phase_and_detail(evt: Event) -> #(String, String) {
  case evt {
    event.Fetched(address, raw) -> #(
      "Fetch",
      "lire mem[" <> int.to_string(address) <> "] → " <> int.to_string(raw),
    )
    event.Decoded(instr) -> #("Decode", describe_decoded(instr))
    event.InputConsumed(v) -> #(
      "Execute",
      "ACC ← entrée (" <> int.to_string(v) <> ")",
    )
    event.OutputProduced(v) -> #(
      "Execute",
      "sortie ← ACC (" <> int.to_string(v) <> ")",
    )
    event.MemoryWritten(address, v) -> #(
      "Execute",
      "mem[" <> int.to_string(address) <> "] ← ACC (" <> int.to_string(v) <> ")",
    )
    event.AccumulatorChanged(old, new) -> #(
      "Execute",
      "ACC " <> int.to_string(old) <> " → " <> int.to_string(new),
    )
    event.Halted -> #("Execute", "HLT")
    event.InputRequested -> #("Execute", "en attente d'une entrée…")
    event.ErrorOccurred(message) -> #("Erreur", message)
  }
}

/// Merges consecutive same-phase pairs into one CyclePhase each — "merges
/// consecutive" rather than "groups all", since phases can legitimately
/// repeat across accumulated events from *different* instructions (a
/// future improvement might show more than one instruction's cycle at
/// once); today last_events only ever holds one instruction's worth, so in
/// practice this always yields at most one Fetch, one Decode, one Execute.
fn group_consecutive_by_phase(
  pairs: List(#(String, String)),
) -> List(CyclePhase) {
  pairs
  |> list.fold([], fn(acc, pair) {
    let #(phase, detail) = pair
    case acc {
      [CyclePhase(name, details), ..rest] if name == phase -> [
        CyclePhase(name, list.append(details, [detail])),
        ..rest
      ]
      _ -> [CyclePhase(phase, [detail]), ..acc]
    }
  })
  |> list.reverse
}

/// Keeps the raw fetched number visible in the Decode line itself (not
/// just on the Fetch line above it), so "STA, adresse 21" reads as *this
/// number, decoded* rather than as a freestanding line of assembly — which
/// otherwise looks exactly like something you could type ("STA 21" is
/// valid LMC), inviting the (false) idea that decode reconstructs source
/// code. It can't: the label "total" the programmer wrote is long gone by
/// this point, only the numeric address 21 survives — decode only ever
/// recovers *that*, via the same arithmetic split lmc_lsp's own
/// instruction.decode uses (raw / 100 for the opcode, raw % 100 for the
/// address). instruction.encode(instr) reconstructs the raw number here —
/// the exact inverse of decode, so it's always the same value Fetch showed.
fn describe_decoded(instr: instruction.Instruction) -> String {
  let raw = int.to_string(instruction.encode(instr))
  case instr {
    instruction.Inp -> raw <> " → INP"
    instruction.Out -> raw <> " → OUT"
    instruction.Hlt -> raw <> " → HLT"
    instruction.Add(a) -> decoded_with_address(raw, "ADD", a)
    instruction.Sub(a) -> decoded_with_address(raw, "SUB", a)
    instruction.Sta(a) -> decoded_with_address(raw, "STA", a)
    instruction.Lda(a) -> decoded_with_address(raw, "LDA", a)
    instruction.Bra(a) -> decoded_with_address(raw, "BRA", a)
    instruction.Brz(a) -> decoded_with_address(raw, "BRZ", a)
    instruction.Brp(a) -> decoded_with_address(raw, "BRP", a)
  }
}

fn decoded_with_address(raw: String, mnemonic: String, address: Int) -> String {
  raw <> " → " <> mnemonic <> ", adresse " <> int.to_string(address)
}

fn load_error_message(err: load.LoadError) -> String {
  case err {
    load.ProgramTooLong(count) ->
      "programme trop long : "
      <> int.to_string(count)
      <> " lignes (maximum 100)"
    load.UndefinedLabel(name) -> "label non défini : " <> name
  }
}
