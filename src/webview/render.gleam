import gleam/json.{type Json}
import gleam/list
import gleam/option.{None, Some}
import lmc/runner/inspect
import lmc/runner/memory
import lmc/runner/state
import lmc/text/message
import webview/model.{type Model}
import webview/text

// Builds the single JSON payload app_ffi.mjs's render() consumes to update
// the DOM. Kept as its own pure module (like model.gleam) so the view-model
// shape has real test coverage independent of any actual rendering.

pub fn to_json(mdl: Model) -> String {
  json.object([
    #("memory", json_memory(mdl)),
    #("acc", json_or_null(mdl.machine, fn(m) { json.int(m.accumulator) })),
    #("pc", json_or_null(mdl.machine, fn(m) { json.int(m.program_counter) })),
    #("x", json_or_null(mdl.machine, fn(m) { json.int(m.index) })),
    #("lr", json_or_null(mdl.machine, fn(m) { json.int(m.link) })),
    // Le pointeur de pile sert deux fois : à l'afficher, et à savoir dans la
    // grille où commence la pile — tout ce qui est au-dessus de SP a été
    // empilé.
    #("sp", json_or_null(mdl.machine, fn(m) { json.int(m.stack_pointer) })),
    #("status", json_status(mdl)),
    #(
      "output",
      json_or_null(mdl.machine, fn(m) {
        json.array(inspect.output_buffer(m), json.int)
      }),
    ),
    // Seulement les points allumés, pas les 1024 cases : l'affichage repeint
    // le fond puis pose ceux-ci. Un écran vide est donc un tableau vide,
    // pas mille zéros.
    #("screen", json_screen(mdl)),
    #("currentLine", json_option_int(model.current_line(mdl))),
    #("currentAddress", json_option_int(model.current_address(mdl))),
    #("cursorAddress", json_option_int(model.cursor_address(mdl))),
    #("programLength", json.int(model.program_length(mdl))),
    // Les cases réservées par un DAT. Voir model.data_addresses : c'est la
    // provenance du texte, pas une frontière que la machine connaîtrait.
    #("dataAddresses", json.array(model.data_addresses(mdl), json.int)),
    #("cycle", json_cycle(mdl)),
    // Le texte fixe du panneau, dans la langue demandée. `index.html` ne
    // porte plus que des `data-ui` vides : une seule source pour les deux
    // langues, et le compilateur exige la traduction de chacune.
    #("ui", json_ui(mdl)),
    #("locale", json.string(locale_tag(mdl.locale))),
    // Un seul bandeau pour deux échecs possibles. L'erreur de chargement
    // passe devant : c'est celle qui répond à « pourquoi Run ne fait rien ».
    #(
      "loadError",
      json_option_string(
        option.map(option.or(mdl.ram_error, mdl.assembly_error), text.render(
          _,
          mdl.locale,
        )),
      ),
    ),
    // Y a-t-il de quoi produire un fichier objet ? Le bouton Assembler s'en
    // sert pour se désactiver quand le source ne s'assemble pas.
    #("assembled", json.bool(option.is_some(mdl.assembled))),
  ])
  |> json.to_string
}

fn json_screen(mdl: Model) -> Json {
  json.array(model.screen_points(mdl), fn(point) {
    let #(x, y, colour) = point
    json.object([
      #("x", json.int(x)),
      #("y", json.int(y)),
      #("c", json.int(colour)),
    ])
  })
}

/// L'étiquette BCP 47 de la langue rendue, pour l'attribut `lang` du
/// document : la césure et les lecteurs d'écran s'en servent.
fn locale_tag(locale: text.Locale) -> String {
  case locale {
    message.French -> "fr"
    message.English -> "en"
  }
}

fn json_ui(mdl: Model) -> Json {
  json.object(
    text.labels(mdl.locale)
    |> list.map(fn(pair) { #(pair.0, json.string(pair.1)) }),
  )
}

fn json_cycle(mdl: Model) -> Json {
  json.array(model.last_cycle(mdl), fn(phase) {
    json.object([
      #("phase", json.string(text.phase_label(phase.phase, mdl.locale))),
      #(
        "details",
        json.array(phase.details, fn(detail) {
          json.string(text.render(detail, mdl.locale))
        }),
      ),
    ])
  })
}

fn json_memory(mdl: Model) -> Json {
  case mdl.machine {
    None -> json.null()
    Some(m) -> json.array(memory.to_list(m.memory), json.int)
  }
}

fn json_status(mdl: Model) -> Json {
  case mdl.machine {
    None -> json.string("vide")
    // Rien en RAM : la machine n'est pas « en cours », elle n'existe pas
    // encore. Un état à part, pour que la grille vide s'explique d'elle-même.
    Some(m) ->
      json.string(case m.status {
        state.Running -> "running"
        state.WaitingForInput -> "waiting_input"
        state.Halted -> "halted"
        state.ExecutionError(_) -> "error"
      })
  }
}

fn json_or_null(value: option.Option(a), f: fn(a) -> Json) -> Json {
  case value {
    None -> json.null()
    Some(v) -> f(v)
  }
}

fn json_option_int(value: option.Option(Int)) -> Json {
  case value {
    None -> json.null()
    Some(v) -> json.int(v)
  }
}

fn json_option_string(value: option.Option(String)) -> Json {
  case value {
    None -> json.null()
    Some(v) -> json.string(v)
  }
}
