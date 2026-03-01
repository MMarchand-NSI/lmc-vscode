import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import lmc/analyser
import lmc/lexer
import lmc/parser

// ---- FFI (Node.js) ----------------------------------------------------------
// Implémentée dans lsp_ffi.mjs (même répertoire que server.gleam) :
//   readRequest()    – lit un message JSON-RPC complet depuis stdin
//   sendResponse(s)  – écrit un message JSON-RPC vers stdout (avec Content-Length)
//   sendNotification(s) – idem, sans attendre de réponse
//   getStr(d, k)     – accès dynamique à un champ String
//   getInt(d, k)     – accès dynamique à un champ Int
//   getNested(d, k)  – accès à un sous-objet dynamique
//   isDefined(d)     – teste si une valeur dynamic est non-null/undefined

@external(javascript, "./lsp_ffi.mjs", "readRequest")
fn read_request() -> Result(Dynamic, Nil)

@external(javascript, "./lsp_ffi.mjs", "sendResponse")
fn send_response(json: String) -> Nil

@external(javascript, "./lsp_ffi.mjs", "sendNotification")
fn send_notification(json: String) -> Nil

@external(javascript, "./lsp_ffi.mjs", "getStr")
fn get_str(obj: Dynamic, key: String) -> Result(String, Nil)

@external(javascript, "./lsp_ffi.mjs", "getInt")
fn get_int(obj: Dynamic, key: String) -> Result(Int, Nil)

@external(javascript, "./lsp_ffi.mjs", "getNested")
fn get_nested(obj: Dynamic, key: String) -> Result(Dynamic, Nil)

@external(javascript, "./lsp_ffi.mjs", "isDefined")
fn is_defined(obj: Dynamic) -> Bool

// ---- JSON encoder -----------------------------------------------------------

type Json {
  JNull
  JBool(Bool)
  JInt(Int)
  JString(String)
  JArray(List(Json))
  JObject(List(#(String, Json)))
}

fn to_json(j: Json) -> String {
  case j {
    JNull -> "null"
    JBool(True) -> "true"
    JBool(False) -> "false"
    JInt(n) -> int.to_string(n)
    JString(s) ->
      "\"" <> string.replace(s, "\"", "\\\"") |> string.replace("\n", "\\n") <> "\""
    JArray(items) ->
      "[" <> string.join(list.map(items, to_json), ",") <> "]"
    JObject(pairs) ->
      "{"
      <> string.join(
        list.map(pairs, fn(p) { "\"" <> p.0 <> "\":" <> to_json(p.1) }),
        ",",
      )
      <> "}"
  }
}

// ---- LSP types --------------------------------------------------------------

type Position {
  Position(line: Int, character: Int)
}

type Range {
  Range(start: Position, end: Position)
}

// ---- Document store ---------------------------------------------------------

type Document {
  Document(text: String, analysis: Option(analyser.Analysis))
}

type Store =
  Dict(String, Document)

// ---- Entry point ------------------------------------------------------------

pub fn main() -> Nil {
  serve(dict.new(), False)
}

fn serve(store: Store, shutdown_requested: Bool) -> Nil {
  case read_request() {
    Error(_) -> Nil
    Ok(msg) -> {
      let #(new_store, should_exit) = handle(msg, store, shutdown_requested)
      case should_exit {
        True -> Nil
        False -> serve(new_store, shutdown_requested)
      }
    }
  }
}

// ---- Message dispatcher -----------------------------------------------------

fn handle(
  msg: Dynamic,
  store: Store,
  _shutdown: Bool,
) -> #(Store, Bool) {
  let method = get_str(msg, "method") |> result.unwrap("")
  let id = get_int(msg, "id")
  let params = get_nested(msg, "params") |> result.unwrap(msg)

  case method {
    "initialize" -> {
      send_response(response(id, capabilities()))
      #(store, False)
    }

    "initialized" -> #(store, False)

    "shutdown" -> {
      send_response(response(id, JNull))
      #(store, False)
    }

    "exit" -> {
      #(store, True)
    }

    "textDocument/didOpen" -> {
      let new_store = case get_nested(params, "textDocument") {
        Error(_) -> store
        Ok(td) -> {
          let uri = get_str(td, "uri") |> result.unwrap("")
          let text = get_str(td, "text") |> result.unwrap("")
          let doc = analyse_doc(text)
          let s = dict.insert(store, uri, doc)
          publish_diagnostics(uri, doc)
          s
        }
      }
      #(new_store, False)
    }

    "textDocument/didChange" -> {
      let new_store = case get_nested(params, "textDocument") {
        Error(_) -> store
        Ok(td) -> {
          let uri = get_str(td, "uri") |> result.unwrap("")
          let text =
            get_nested(params, "contentChanges")
            |> result.try(fn(changes) { get_str(changes, "text") })
            |> result.unwrap(
              dict.get(store, uri)
              |> result.map(fn(d) { d.text })
              |> result.unwrap(""),
            )
          let doc = analyse_doc(text)
          let s = dict.insert(store, uri, doc)
          publish_diagnostics(uri, doc)
          s
        }
      }
      #(new_store, False)
    }

    "textDocument/didClose" -> {
      let uri =
        get_nested(params, "textDocument")
        |> result.try(fn(td) { get_str(td, "uri") })
        |> result.unwrap("")
      #(dict.delete(store, uri), False)
    }

    "textDocument/definition" -> {
      let loc = case get_nested(params, "textDocument"), get_nested(params, "position") {
        Ok(td), Ok(pos) -> {
          let uri = get_str(td, "uri") |> result.unwrap("")
          let line = get_int(pos, "line") |> result.unwrap(0)
          let char = get_int(pos, "character") |> result.unwrap(0)
          handle_definition(store, uri, Position(line, char))
        }
        _, _ -> JNull
      }
      send_response(response(id, loc))
      #(store, False)
    }

    "textDocument/hover" -> {
      let hov = case get_nested(params, "textDocument"), get_nested(params, "position") {
        Ok(td), Ok(pos) -> {
          let uri = get_str(td, "uri") |> result.unwrap("")
          let line = get_int(pos, "line") |> result.unwrap(0)
          let char = get_int(pos, "character") |> result.unwrap(0)
          handle_hover(store, uri, Position(line, char))
        }
        _, _ -> JNull
      }
      send_response(response(id, hov))
      #(store, False)
    }

    "textDocument/references" -> {
      let locs = case get_nested(params, "textDocument"), get_nested(params, "position") {
        Ok(td), Ok(pos) -> {
          let uri = get_str(td, "uri") |> result.unwrap("")
          let line = get_int(pos, "line") |> result.unwrap(0)
          let char = get_int(pos, "character") |> result.unwrap(0)
          handle_references(store, uri, Position(line, char))
        }
        _, _ -> JArray([])
      }
      send_response(response(id, locs))
      #(store, False)
    }

    "textDocument/completion" -> {
      let items = case get_nested(params, "textDocument") {
        Ok(td) -> {
          let uri = get_str(td, "uri") |> result.unwrap("")
          handle_completion(store, uri)
        }
        _ -> JArray([])
      }
      send_response(response(id, items))
      #(store, False)
    }

    _ ->
      // Unknown method — send error only if it had an id (request, not notif)
      case is_defined(msg) {
        True -> {
          send_response(error_response(id, -32_601, "Method not found: " <> method))
          #(store, False)
        }
        False -> #(store, False)
      }
  }
}

// ---- LSP handlers -----------------------------------------------------------

fn handle_definition(store: Store, uri: String, pos: Position) -> Json {
  case dict.get(store, uri) {
    Error(_) -> JNull
    Ok(Document(_, None)) -> JNull
    Ok(Document(_, Some(analysis))) ->
      case find_label_at(store, uri, pos) {
        None -> JNull
        Some(lbl) ->
          case analyser.find_definition(analysis, lbl) {
            None -> JNull
            Some(sym) ->
              encode_location(uri, full_line_range(sym.defined_at - 1))
          }
      }
  }
}

fn handle_hover(store: Store, uri: String, pos: Position) -> Json {
  case dict.get(store, uri) {
    Error(_) -> JNull
    Ok(Document(_, None)) -> JNull
    Ok(Document(_, Some(analysis))) ->
      case find_label_at(store, uri, pos) {
        None -> JNull
        Some(lbl) ->
          case analyser.find_definition(analysis, lbl) {
            None -> JNull
            Some(sym) -> {
              let ref_count = list.length(sym.referenced_at)
              let md =
                "**"
                <> sym.name
                <> "**"
                <> "  \nDefined at line "
                <> int.to_string(sym.defined_at)
                <> "  \nReferenced "
                <> int.to_string(ref_count)
                <> " time(s)"
              JObject([
                #("contents", JObject([
                  #("kind", JString("markdown")),
                  #("value", JString(md)),
                ])),
              ])
            }
          }
      }
  }
}

fn handle_references(store: Store, uri: String, pos: Position) -> Json {
  case dict.get(store, uri) {
    Error(_) -> JArray([])
    Ok(Document(_, None)) -> JArray([])
    Ok(Document(_, Some(analysis))) ->
      case find_label_at(store, uri, pos) {
        None -> JArray([])
        Some(lbl) ->
          case analyser.find_definition(analysis, lbl) {
            None -> JArray([])
            Some(sym) ->
              JArray(list.map(sym.referenced_at, fn(line) {
                encode_location(uri, full_line_range(line - 1))
              }))
          }
      }
  }
}

fn handle_completion(store: Store, uri: String) -> Json {
  let mnemonic_items =
    list.map(mnemonics(), fn(m) {
      JObject([
        #("label", JString(m.0)),
        #("kind", JInt(14)),
        // Keyword
        #("detail", JString(m.1)),
      ])
    })

  let label_items = case dict.get(store, uri) {
    Error(_) -> []
    Ok(Document(_, None)) -> []
    Ok(Document(_, Some(analysis))) ->
      list.map(analyser.all_symbols(analysis), fn(sym) {
        JObject([
          #("label", JString(sym.name)),
          #("kind", JInt(6)),
          // Variable
          #("detail", JString("label at line " <> int.to_string(sym.defined_at))),
        ])
      })
  }

  JArray(list.append(mnemonic_items, label_items))
}

// ---- Diagnostics (notification) ---------------------------------------------

fn publish_diagnostics(uri: String, doc: Document) -> Nil {
  let diags = case doc.analysis {
    None -> JArray([])
    Some(analysis) ->
      JArray(list.map(analysis.diagnostics, encode_diagnostic))
  }
  let notif =
    JObject([
      #("jsonrpc", JString("2.0")),
      #("method", JString("textDocument/publishDiagnostics")),
      #("params", JObject([
        #("uri", JString(uri)),
        #("diagnostics", diags),
      ])),
    ])
  send_notification(to_json(notif))
}

fn encode_diagnostic(d: analyser.Diagnostic) -> Json {
  let sev = case d.severity {
    analyser.SevError -> 1
    analyser.SevWarning -> 2
  }
  JObject([
    #("range", encode_range(full_line_range(int.max(0, d.line - 1)))),
    #("severity", JInt(sev)),
    #("message", JString(d.message)),
    #("source", JString("lmc")),
  ])
}

// ---- Document analysis ------------------------------------------------------

fn analyse_doc(text: String) -> Document {
  let tokens = lexer.tokenize(text)
  case parser.parse(tokens) {
    Error(_) -> Document(text: text, analysis: None)
    Ok(program) ->
      Document(text: text, analysis: Some(analyser.analyse(program)))
  }
}

// ---- Label lookup at cursor position ----------------------------------------

fn find_label_at(store: Store, uri: String, pos: Position) -> Option(String) {
  use doc <- option_get(store, uri)
  use analysis <- option.then(doc.analysis)
  let line_no = pos.line + 1
  // line_no is 1-based

  // Check label definitions first, then references
  let from_def =
    analyser.all_symbols(analysis)
    |> list.find_map(fn(sym) {
      case sym.defined_at == line_no {
        True -> Ok(sym.name)
        False -> Error(Nil)
      }
    })

  let from_ref =
    analyser.all_symbols(analysis)
    |> list.find_map(fn(sym) {
      case list.contains(sym.referenced_at, line_no) {
        True -> Ok(sym.name)
        False -> Error(Nil)
      }
    })

  case from_def {
    Ok(lbl) -> Some(lbl)
    Error(_) ->
      case from_ref {
        Ok(lbl) -> Some(lbl)
        Error(_) -> None
      }
  }
}

// ---- JSON helpers -----------------------------------------------------------

fn response(id: Result(Int, Nil), result: Json) -> String {
  to_json(JObject([
    #("jsonrpc", JString("2.0")),
    #("id", case id {
      Ok(n) -> JInt(n)
      Error(_) -> JNull
    }),
    #("result", result),
  ]))
}

fn error_response(id: Result(Int, Nil), code: Int, message: String) -> String {
  to_json(JObject([
    #("jsonrpc", JString("2.0")),
    #("id", case id {
      Ok(n) -> JInt(n)
      Error(_) -> JNull
    }),
    #("error", JObject([
      #("code", JInt(code)),
      #("message", JString(message)),
    ])),
  ]))
}

fn capabilities() -> Json {
  JObject([
    #("capabilities", JObject([
      #("textDocumentSync", JInt(1)),
      // Full sync
      #("hoverProvider", JBool(True)),
      #("definitionProvider", JBool(True)),
      #("referencesProvider", JBool(True)),
      #("completionProvider", JObject([
        #("triggerCharacters", JArray([])),
      ])),
    ])),
    #("serverInfo", JObject([
      #("name", JString("lmc-language-server")),
      #("version", JString("1.0.0")),
    ])),
  ])
}

fn encode_location(uri: String, range: Range) -> Json {
  JObject([#("uri", JString(uri)), #("range", encode_range(range))])
}

fn encode_range(r: Range) -> Json {
  JObject([
    #("start", encode_position(r.start)),
    #("end", encode_position(r.end)),
  ])
}

fn encode_position(p: Position) -> Json {
  JObject([#("line", JInt(p.line)), #("character", JInt(p.character))])
}

fn full_line_range(line: Int) -> Range {
  Range(
    start: Position(line: line, character: 0),
    end: Position(line: line, character: 999),
  )
}

fn option_get(
  store: Store,
  uri: String,
  f: fn(Document) -> Option(a),
) -> Option(a) {
  case dict.get(store, uri) {
    Error(_) -> None
    Ok(doc) -> f(doc)
  }
}

// ---- LMC instruction table --------------------------------------------------

fn mnemonics() -> List(#(String, String)) {
  [
    #("ADD", "ACC = ACC + mem[addr]"),
    #("SUB", "ACC = ACC − mem[addr]"),
    #("STA", "mem[addr] = ACC"),
    #("LDA", "ACC = mem[addr]"),
    #("BRA", "PC = addr  (branch always)"),
    #("BRZ", "if ACC = 0 then PC = addr"),
    #("BRP", "if ACC ≥ 0 then PC = addr"),
    #("INP", "ACC = next input"),
    #("OUT", "output ACC"),
    #("HLT", "stop execution"),
    #("DAT", "define data cell"),
  ]
}
