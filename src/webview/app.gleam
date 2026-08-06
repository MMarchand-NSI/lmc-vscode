import gleam/dynamic/decode
import gleam/json
import gleam/option.{type Option, None, Some}
import webview/ffi.{type Ref}
import webview/model.{type Model}
import webview/render

// Entry point loaded inside the webview (browser context, not Node — see
// scripts/build-webview.mjs). Wires model.gleam + render.gleam to the DOM
// and to the extension host via ffi.gleam. Not unit-tested itself (it's
// pure FFI wiring, same reasoning as lmc_lsp's lsp/server.gleam `serve`
// loop vs. its testable handlers) — model.gleam and render.gleam carry the
// actual logic and are what's covered by `gleam test`.

pub fn main() -> Nil {
  let cell = ffi.ref(model.init(""))

  ffi.on_host_message(fn(raw) { handle_host_message(cell, raw) })
  ffi.on_step_click(fn() { update(cell, model.step) })
  ffi.on_run_click(fn() { update(cell, model.run_to_halt) })
  ffi.on_reset_click(fn() { update(cell, model.reset) })
  ffi.on_input_submit(fn(value) {
    // Only complete the one INP that was waiting — not run_to_halt. The
    // model can't tell whether the user got here via Step or Run, and
    // resuming straight into run_to_halt made *every* input submission run
    // the rest of the program to completion (or the next INP) regardless,
    // which is exactly "Step behaves like Run" from the user's side.
    // Landing back on Running after exactly this instruction is the
    // uniformly correct choice for both: a Run user just clicks Run again
    // to keep going, at the cost of one extra click.
    update(cell, fn(m) { m |> model.provide_input(value) |> model.step })
  })
  ffi.on_mailbox_click(fn(address) {
    case model.line_for_address(ffi.deref(cell), address) {
      Some(line) -> ffi.post_to_host(reveal_line_message(line))
      None -> Nil
    }
  })

  // Initial render before the host has sent any source — shows the
  // "nothing loaded yet" state rather than a blank screen while waiting.
  render_and_notify(cell)
  ffi.post_to_host(ready_message())
}

fn update(cell: Ref(Model), f: fn(Model) -> Model) -> Nil {
  ffi.set_ref(cell, f(ffi.deref(cell)))
  render_and_notify(cell)
}

/// Re-renders the webview *and* tells the host which source line is
/// current, so it can show a debug-session-style highlight in the editor
/// (see webviewPanel.ts, currentLineDecoration) — not just the memory
/// grid's own highlight. Every state change goes through `update`, so this
/// covers step/run/reset/input/source-change uniformly rather than having
/// to remember to notify at each call site separately.
fn render_and_notify(cell: Ref(Model)) -> Nil {
  let mdl = ffi.deref(cell)
  ffi.render(render.to_json(mdl))
  ffi.post_to_host(current_line_message(model.current_line(mdl)))
}

// ── Messages venant de l'extension host ───────────────────────────

type HostMessage {
  SetSource(source: String)
  CursorLine(line: Option(Int))
  Unrecognized
}

fn handle_host_message(cell: Ref(Model), raw: String) -> Nil {
  case decode_host_message(raw) {
    SetSource(source) ->
      update(cell, fn(m) { model.set_source_if_changed(m, source) })
    CursorLine(line) -> update(cell, fn(m) { model.set_cursor_line(m, line) })
    Unrecognized -> Nil
  }
}

fn decode_host_message(raw: String) -> HostMessage {
  json.parse(raw, host_message_decoder())
  |> option.from_result
  |> option.unwrap(Unrecognized)
}

fn host_message_decoder() -> decode.Decoder(HostMessage) {
  use kind <- decode.field("type", decode.string)
  case kind {
    "setSource" -> {
      use source <- decode.field("source", decode.string)
      decode.success(SetSource(source))
    }
    "cursorLine" -> {
      use line <- decode.field("line", decode.optional(decode.int))
      decode.success(CursorLine(line))
    }
    _ -> decode.success(Unrecognized)
  }
}

// ── Messages vers l'extension host ────────────────────────────────

fn ready_message() -> String {
  json.object([#("type", json.string("ready"))]) |> json.to_string
}

fn reveal_line_message(line: Int) -> String {
  json.object([#("type", json.string("revealLine")), #("line", json.int(line))])
  |> json.to_string
}

fn current_line_message(line: Option(Int)) -> String {
  let line_json = case line {
    Some(l) -> json.int(l)
    None -> json.null()
  }
  json.object([#("type", json.string("currentLine")), #("line", line_json)])
  |> json.to_string
}
