import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import lmc/parse/span
import lmc/runner/load
import lmc/runner/run
import lmc/runner/state.{type MachineState}
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
    // Line the host's cursor is currently on — independent of execution
    // state, doesn't get reset by step/run/reset.
    cursor_line: Option(Int),
    load_error: Option(String),
  )
}

pub fn init(source: String) -> Model {
  Model(
    source: "",
    parse: None,
    machine: None,
    address_to_line: dict.new(),
    line_to_address: dict.new(),
    cursor_line: None,
    load_error: None,
  )
  |> load_source(source)
}

/// (Re)parse and (re)assemble `source`, resetting execution state. Input is
/// always empty at load time — INP is handled interactively via
/// `provide_input`, never supplied upfront (this is a step-through teaching
/// tool, not a batch runner).
pub fn load_source(model: Model, source: String) -> Model {
  let result = pipeline.parse(source)
  let address_to_line = build_address_to_line(result)
  let line_to_address = invert(address_to_line)

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
            load_error: None,
          )
        Error(err) ->
          Model(
            ..model,
            source: source,
            parse: Some(result),
            machine: None,
            address_to_line: address_to_line,
            line_to_address: line_to_address,
            load_error: Some(load_error_message(err)),
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
        load_error: Some(
          "le programme contient des erreurs — voir les diagnostics dans l'éditeur",
        ),
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
      let #(next, _events) = run.run_n(m, 1)
      Model(..model, machine: Some(next))
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
      let #(next, _events) = run.run_to_halt(m)
      Model(..model, machine: Some(next))
    }
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

fn load_error_message(err: load.LoadError) -> String {
  case err {
    load.ProgramTooLong(count) ->
      "programme trop long : "
      <> int.to_string(count)
      <> " lignes (maximum 100)"
    load.UndefinedLabel(name) -> "label non défini : " <> name
  }
}
