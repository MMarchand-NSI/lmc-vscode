import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import lmc/parser.{
  type Instruction, type Program, Add, Bra, Brp, Brz, Hlt, Lda, Sta, Sub,
}

// ---- Types ------------------------------------------------------------------

pub type Severity {
  SevError
  SevWarning
}

pub type Diagnostic {
  Diagnostic(line: Int, severity: Severity, message: String)
}

/// Un symbole représente un label : où il est défini et sur quelles lignes il
/// est référencé. Utilisé par le LSP pour go-to-definition, find-references
/// et hover.
pub type Symbol {
  Symbol(name: String, defined_at: Int, referenced_at: List(Int))
}

pub type Analysis {
  Analysis(diagnostics: List(Diagnostic), symbols: Dict(String, Symbol))
}

// ---- Entry point ------------------------------------------------------------

pub fn analyse(program: Program) -> Analysis {
  let indexed = list.index_map(program.lines, fn(line, i) { #(i + 1, line) })

  let #(defs, dup_diags) = collect_definitions(indexed)
  let #(ref_diags, symbols) = check_references(indexed, defs)
  let hlt_diags = check_hlt(indexed)
  let len_diags = check_length(indexed)

  let diagnostics =
    list.flatten([dup_diags, ref_diags, hlt_diags, len_diags])
    |> list.sort(fn(a, b) { int.compare(a.line, b.line) })

  Analysis(diagnostics: diagnostics, symbols: symbols)
}

// ---- Pass 1 : collecte des définitions de labels ----------------------------

fn collect_definitions(
  indexed: List(#(Int, parser.Line)),
) -> #(Dict(String, Int), List(Diagnostic)) {
  list.fold(indexed, #(dict.new(), []), fn(acc, item) {
    let #(defs, diags) = acc
    let #(line_no, parser.Line(label, _, _)) = item
    case label {
      None -> acc
      Some(name) ->
        case dict.get(defs, name) {
          Ok(prev) -> #(defs, [
            Diagnostic(
              line: line_no,
              severity: SevError,
              message: "Label \""
                <> name
                <> "\" already defined at line "
                <> int.to_string(prev),
            ),
            ..diags
          ])
          Error(_) -> #(dict.insert(defs, name, line_no), diags)
        }
    }
  })
}

// ---- Pass 2 : vérification des références -----------------------------------

fn check_references(
  indexed: List(#(Int, parser.Line)),
  defs: Dict(String, Int),
) -> #(List(Diagnostic), Dict(String, Symbol)) {
  // Initialise la table des symboles à partir des définitions connues.
  let init_symbols =
    dict.map_values(defs, fn(name, line_no) {
      Symbol(name: name, defined_at: line_no, referenced_at: [])
    })

  list.fold(indexed, #([], init_symbols), fn(acc, item) {
    let #(diags, symbols) = acc
    let #(line_no, parser.Line(_, instr, _)) = item
    case instr {
      None -> acc
      Some(i) ->
        case operand_label(i) {
          None -> acc
          Some(lbl) ->
            case dict.get(defs, lbl) {
              Error(_) -> #(
                [
                  Diagnostic(
                    line: line_no,
                    severity: SevError,
                    message: "Label \"" <> lbl <> "\" is not defined",
                  ),
                  ..diags
                ],
                symbols,
              )
              Ok(_) -> {
                let sym = case dict.get(symbols, lbl) {
                  Ok(s) ->
                    Symbol(..s, referenced_at: [line_no, ..s.referenced_at])
                  Error(_) ->
                    Symbol(name: lbl, defined_at: 0, referenced_at: [line_no])
                }
                #(diags, dict.insert(symbols, lbl, sym))
              }
            }
        }
    }
  })
}

/// Extrait le label opérande d'une instruction qui en a un.
fn operand_label(instr: Instruction) -> Option(String) {
  case instr {
    Add(lbl) | Sub(lbl) | Sta(lbl) | Lda(lbl) | Bra(lbl) | Brz(lbl) | Brp(lbl) ->
      Some(lbl)
    _ -> None
  }
}

// ---- Vérification HLT -------------------------------------------------------

fn check_hlt(indexed: List(#(Int, parser.Line))) -> List(Diagnostic) {
  let has_hlt =
    list.any(indexed, fn(item) {
      let #(_, parser.Line(_, instr, _)) = item
      instr == Some(Hlt)
    })
  case has_hlt {
    True -> []
    False -> [
      Diagnostic(
        line: 0,
        severity: SevWarning,
        message: "No HLT instruction — the program may run indefinitely",
      ),
    ]
  }
}

// ---- Vérification longueur --------------------------------------------------

fn check_length(indexed: List(#(Int, parser.Line))) -> List(Diagnostic) {
  let count =
    list.filter(indexed, fn(item) {
      let #(_, parser.Line(_, instr, _)) = item
      instr != None
    })
    |> list.length
  case count > 100 {
    False -> []
    True -> [
      Diagnostic(
        line: 0,
        severity: SevError,
        message: "Program has "
          <> int.to_string(count)
          <> " instructions; maximum is 100",
      ),
    ]
  }
}

// ---- Requêtes utilitaires (pour le LSP) -------------------------------------

/// Retourne le symbole défini sous ce label, s'il existe.
pub fn find_definition(analysis: Analysis, label: String) -> Option(Symbol) {
  dict.get(analysis.symbols, label) |> option.from_result
}

/// Retourne tous les symboles définis dans le programme.
pub fn all_symbols(analysis: Analysis) -> List(Symbol) {
  dict.values(analysis.symbols)
}

/// Retourne uniquement les diagnostics d'une sévérité donnée.
pub fn diagnostics_by_severity(
  analysis: Analysis,
  severity: Severity,
) -> List(Diagnostic) {
  list.filter(analysis.diagnostics, fn(d) { d.severity == severity })
}
