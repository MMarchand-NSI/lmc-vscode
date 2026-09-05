import gleam/option.{Some}
import gleam/string
import webview/model
import webview/render

/// Assemble puis charge, comme les boutons Assembler puis Charger.
fn loaded(source: String) -> model.Model {
  let m = model.init(source)
  let assert Some(code) = model.object_code(m)
  model.load_object_code(m, code)
}

pub fn nothing_loaded_renders_an_empty_machine_test() {
  // À l'ouverture, la RAM est vide : pas de registres, pas de programme,
  // aucune zone marquée dans la grille. L'assemblage, lui, a eu lieu.
  let json = model.init("INP\nOUT\nHLT\n") |> render.to_json
  assert string.contains(json, "\"status\":\"vide\"")
  assert string.contains(json, "\"memory\":null")
  assert string.contains(json, "\"pc\":null")
  assert string.contains(json, "\"programLength\":0")
  assert string.contains(json, "\"dataAddresses\":[]")
  assert string.contains(json, "\"assembled\":true")
}

pub fn valid_program_renders_expected_fields_test() {
  let json = loaded("INP\nOUT\nHLT\n") |> render.to_json
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
  assert string.contains(json, "\"status\":\"vide\"")
  assert string.contains(json, "\"assembled\":false")
  assert string.contains(json, "\"pc\":null")
  assert string.contains(json, "\"sp\":null")
  assert string.contains(json, "\"memory\":null")
  assert string.contains(json, "\"loadError\":\"")
}

pub fn waiting_for_input_status_test() {
  let json = loaded("INP\nOUT\nHLT\n") |> model.run_to_halt |> render.to_json
  assert string.contains(json, "\"status\":\"waiting_input\"")
}

pub fn halted_status_with_output_test() {
  let json =
    loaded("INP\nOUT\nHLT\n")
    |> model.run_to_halt
    |> model.provide_input(7)
    |> model.run_to_halt
    |> render.to_json
  assert string.contains(json, "\"status\":\"halted\"")
  assert string.contains(json, "\"output\":[7]")
}

pub fn cursor_address_reflected_test() {
  let json =
    loaded("INP\nOUT\nHLT\n")
    |> model.set_cursor_line(Some(1))
    |> render.to_json
  assert string.contains(json, "\"cursorAddress\":1")
}

pub fn program_length_reflected_test() {
  let json = loaded("INP\nOUT\nHLT\n") |> render.to_json
  assert string.contains(json, "\"programLength\":3")
}

pub fn cycle_reflected_after_step_test() {
  // Resuming from INP: the events accumulated across the pause (see
  // model.accumulate_events) so the panel shows this instruction's whole
  // Fetch->Decode->Execute cycle in one place — and as exactly one
  // "Execute" phase (not three), its sub-events grouped into that phase's
  // "details" array rather than three separate top-level phase entries.
  let json =
    loaded("INP\nOUT\nHLT\n")
    |> model.run_to_halt
    |> model.provide_input(1)
    |> model.step
    |> render.to_json
  assert string.contains(json, "\"cycle\":[{\"phase\":\"Fetch\"")
  assert string.contains(json, "\"phase\":\"Execute\",\"details\":[")
  assert string.contains(json, "\"ACC ← entrée (1)\"")
}

pub fn cycle_empty_before_any_step_test() {
  let json = loaded("INP\nOUT\nHLT\n") |> render.to_json
  assert string.contains(json, "\"cycle\":[]")
}

pub fn data_addresses_reach_the_payload_test() {
  let json = loaded("HLT\nlst: DAT 12, 4, 86\n") |> render.to_json
  assert string.contains(json, "\"dataAddresses\":[1,2,3]")
}

pub fn data_addresses_is_an_empty_array_not_null_without_dat_test() {
  // Le rendu itère dessus sans le tester : une liste vide, jamais null.
  let json = loaded("INP\nOUT\nHLT\n") |> render.to_json
  assert string.contains(json, "\"dataAddresses\":[]")
}

pub fn an_unlit_screen_renders_as_an_empty_array_test() {
  // Un tableau vide, et non mille zéros : le payload ne porte que les points
  // allumés, l'affichage repeint le fond lui-même.
  let json = loaded("PLT pt\nHLT\npt: DAT 20, 25, 7\n") |> render.to_json
  assert string.contains(json, "\"screen\":[]")
}

pub fn a_lit_point_renders_with_its_colour_test() {
  let json =
    loaded("PLT pt\nHLT\npt: DAT 20, 25, 7\n")
    |> model.step
    |> render.to_json
  assert string.contains(json, "\"screen\":[{\"x\":20,\"y\":25,\"c\":7}]")
}
