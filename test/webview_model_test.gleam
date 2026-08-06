import gleam/option.{None, Some}
import lmc/runner/state
import webview/model

// ── Chargement / assemblage ───────────────────────────────────────

pub fn init_valid_program_test() {
  let m = model.init("INP\nOUT\nHLT\n")
  assert m.load_error == None
  let assert Some(machine) = m.machine
  assert machine.status == state.Running
}

pub fn init_program_with_syntax_error_test() {
  let m = model.init("XXX\n")
  assert m.machine == None
  assert m.load_error != None
}

pub fn init_program_with_undefined_label_test() {
  // Erreur de résolution, pas de syntaxe — même chemin "diagnostics non
  // vides" côté pipeline, donc même message générique côté webview (les
  // diagnostics détaillés vivent déjà dans l'éditeur via le LSP).
  let m = model.init("LDA ghost\nHLT\n")
  assert m.machine == None
  assert m.load_error != None
}

// ── Step / run ────────────────────────────────────────────────────

pub fn step_advances_one_instruction_test() {
  let m = model.init("INP\nOUT\nHLT\n") |> model.step
  let assert Some(machine) = m.machine
  assert machine.status == state.WaitingForInput
}

pub fn step_on_unloaded_program_is_a_no_op_test() {
  let m = model.init("XXX\n") |> model.step
  assert m.machine == None
}

pub fn run_to_halt_runs_until_input_needed_test() {
  let m = model.init("INP\nOUT\nHLT\n") |> model.run_to_halt
  let assert Some(machine) = m.machine
  assert machine.status == state.WaitingForInput
}

pub fn provide_input_then_run_halts_test() {
  let m =
    model.init("INP\nOUT\nHLT\n")
    |> model.run_to_halt
    |> model.provide_input(42)
    |> model.run_to_halt
  let assert Some(machine) = m.machine
  assert machine.status == state.Halted
  assert machine.output == [42]
}

pub fn reset_reruns_from_scratch_test() {
  // reset() reloads to the freshly-assembled state — it does not
  // auto-run up to the first INP the way a fresh model.init would look
  // right after (both land on the same thing: Running, PC at the start).
  let m =
    model.init("INP\nOUT\nHLT\n")
    |> model.run_to_halt
    |> model.provide_input(1)
    |> model.run_to_halt
    |> model.reset
  let assert Some(machine) = m.machine
  assert machine.status == state.Running
  assert machine.program_counter == 0
  assert machine.output == []
}

// ── Correspondance adresse <-> ligne ──────────────────────────────

pub fn current_line_tracks_program_counter_test() {
  let m = model.init("INP\nOUT\nHLT\n")
  // PC=0 avant la première instruction -> ligne 0
  assert model.current_line(m) == Some(0)

  let m2 = model.step(m)
  // Après INP (en attente d'input, PC pas encore avancé) -> toujours ligne 0
  assert model.current_line(m2) == Some(0)
}

pub fn current_line_advances_after_input_provided_test() {
  let m =
    model.init("INP\nOUT\nHLT\n")
    |> model.run_to_halt
    |> model.provide_input(5)
    |> model.step
  // INP consommé -> PC=1 -> ligne 1 (OUT)
  assert model.current_line(m) == Some(1)
}

pub fn line_for_address_and_cursor_address_are_inverse_test() {
  let m = model.init("INP\nOUT\nHLT\n")
  assert model.line_for_address(m, 1) == Some(1)

  let m2 = model.set_cursor_line(m, Some(1))
  assert model.cursor_address(m2) == Some(1)
}

pub fn cursor_line_on_blank_line_has_no_address_test() {
  let m =
    model.init("INP\n\nOUT\nHLT\n")
    |> model.set_cursor_line(Some(1))
  // ligne 1 = ligne vide, pas d'instruction dessus
  assert model.cursor_address(m) == None
}

pub fn labels_dont_shift_the_address_line_map_test() {
  // Un label sur sa propre ligne (ADS: pas d'instruction) décale les
  // adresses par rapport aux numéros de ligne — vérifie que le mapping
  // suit bien les *lignes*, pas un compteur d'instructions naïf.
  let m = model.init("start INP\nOUT\nHLT\n")
  assert model.line_for_address(m, 0) == Some(0)
  assert model.line_for_address(m, 1) == Some(1)
  assert model.line_for_address(m, 2) == Some(2)
}
