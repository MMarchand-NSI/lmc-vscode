import gleam/json.{type Json}
import gleam/option.{None, Some}
import lmc/runner/memory
import lmc/runner/state
import webview/model.{type Model}

// Builds the single JSON payload app_ffi.mjs's render() consumes to update
// the DOM. Kept as its own pure module (like model.gleam) so the view-model
// shape has real test coverage independent of any actual rendering.

pub fn to_json(mdl: Model) -> String {
  json.object([
    #("memory", json_memory(mdl)),
    #("acc", json_or_null(mdl.machine, fn(m) { json.int(m.accumulator) })),
    #("pc", json_or_null(mdl.machine, fn(m) { json.int(m.program_counter) })),
    #("status", json_status(mdl)),
    #(
      "output",
      json_or_null(mdl.machine, fn(m) { json.array(m.output, json.int) }),
    ),
    #("currentLine", json_option_int(model.current_line(mdl))),
    #("currentAddress", json_option_int(model.current_address(mdl))),
    #("cursorAddress", json_option_int(model.cursor_address(mdl))),
    #(
      "instructionText",
      json_option_string(model.current_instruction_text(mdl)),
    ),
    #("programLength", json.int(model.program_length(mdl))),
    #("loadError", json_option_string(mdl.load_error)),
  ])
  |> json.to_string
}

fn json_memory(mdl: Model) -> Json {
  case mdl.machine {
    None -> json.null()
    Some(m) -> json.array(memory.to_list(m.memory), json.int)
  }
}

fn json_status(mdl: Model) -> Json {
  case mdl.machine {
    None -> json.null()
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
