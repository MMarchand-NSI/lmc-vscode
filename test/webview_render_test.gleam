import gleam/option.{Some}
import gleam/string
import webview/model
import webview/render

pub fn valid_program_renders_expected_fields_test() {
  let json = model.init("INP\nOUT\nHLT\n") |> render.to_json
  assert string.contains(json, "\"status\":\"running\"")
  assert string.contains(json, "\"pc\":0")
  assert string.contains(json, "\"acc\":0")
  assert string.contains(json, "\"currentLine\":0")
  assert string.contains(json, "\"loadError\":null")
  // 100 mots mémoire, séparés par des virgules -> 99 virgules dans le tableau
  assert string.contains(json, "\"memory\":[")
}

pub fn program_with_error_renders_null_machine_fields_test() {
  let json = model.init("XXX\n") |> render.to_json
  assert string.contains(json, "\"status\":null")
  assert string.contains(json, "\"pc\":null")
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
