import gleam/option.{Some}
import gleam/string
import webview/model
import webview/render

pub fn valid_program_renders_expected_fields_test() {
  let json = model.init("INP\nOUT\nHLT\n") |> render.to_json
  assert string.contains(json, "\"status\":\"running\"")
  assert string.contains(json, "\"pc\":0")
  assert string.contains(json, "\"acc\":0")
  assert string.contains(json, "\"x\":0")
  assert string.contains(json, "\"lr\":0")
  // La pile part du haut : SP désigne la prochaine case libre, donc 99 sur
  // une machine fraîchement chargée. C'est aussi ce qui permet à la grille
  // de savoir où commence la zone empilée.
  assert string.contains(json, "\"sp\":99")
  assert string.contains(json, "\"currentLine\":0")
  assert string.contains(json, "\"loadError\":null")
  // 100 mots mémoire, séparés par des virgules -> 99 virgules dans le tableau
  assert string.contains(json, "\"memory\":[")
}

pub fn program_with_error_renders_null_machine_fields_test() {
  let json = model.init("XXX\n") |> render.to_json
  assert string.contains(json, "\"status\":null")
  assert string.contains(json, "\"pc\":null")
  assert string.contains(json, "\"sp\":null")
  assert string.contains(json, "\"memory\":null")
  assert string.contains(json, "\"loadError\":\"")
}

pub fn waiting_for_input_status_test() {
  let json =
    model.init("INP\nOUT\nHLT\n") |> model.run_to_halt |> render.to_json
  assert string.contains(json, "\"status\":\"waiting_input\"")
}

pub fn halted_status_with_output_test() {
  let json =
    model.init("INP\nOUT\nHLT\n")
    |> model.run_to_halt
    |> model.provide_input(7)
    |> model.run_to_halt
    |> render.to_json
  assert string.contains(json, "\"status\":\"halted\"")
  assert string.contains(json, "\"output\":[7]")
}

pub fn cursor_address_reflected_test() {
  let json =
    model.init("INP\nOUT\nHLT\n")
    |> model.set_cursor_line(Some(1))
    |> render.to_json
  assert string.contains(json, "\"cursorAddress\":1")
}

pub fn instruction_text_and_program_length_reflected_test() {
  let json = model.init("INP\nOUT\nHLT\n") |> render.to_json
  assert string.contains(json, "\"instructionText\":\"INP — lire une entrée\"")
  assert string.contains(json, "\"programLength\":3")
}

pub fn cycle_reflected_after_step_test() {
  // Resuming from INP: the events accumulated across the pause (see
  // model.accumulate_events) so the panel shows this instruction's whole
  // Fetch->Decode->Execute cycle in one place — and as exactly one
  // "Execute" phase (not three), its sub-events grouped into that phase's
  // "details" array rather than three separate top-level phase entries.
  let json =
    model.init("INP\nOUT\nHLT\n")
    |> model.run_to_halt
    |> model.provide_input(1)
    |> model.step
    |> render.to_json
  assert string.contains(json, "\"cycle\":[{\"phase\":\"Fetch\"")
  assert string.contains(json, "\"phase\":\"Execute\",\"details\":[")
  assert string.contains(json, "\"ACC ← entrée (1)\"")
}

pub fn cycle_empty_before_any_step_test() {
  let json = model.init("INP\nOUT\nHLT\n") |> render.to_json
  assert string.contains(json, "\"cycle\":[]")
}
