import gleam/int
import gleam/list
import gleam/string

// ---- Types ------------------------------------------------------------------

pub type Token {
  Ident(String)
  // identifiant brut : label, mnémonique, référence
  Number(Int)
  // entier littéral (toute valeur, validation laissée au parser)
  Comment(String)
  // texte après ; ou //
  Newline
  Unknown(String)
  // caractère non reconnu
}

pub type Span {
  Span(line: Int, col_start: Int, col_end: Int)
}

pub type SpannedToken {
  SpannedToken(token: Token, span: Span)
}

// ---- Point d'entrée ---------------------------------------------------------

pub fn tokenize(source: String) -> List(SpannedToken) {
  source
  |> string.split("\n")
  |> list.index_map(fn(line, idx) { tokenize_line(line, idx + 1) })
  |> list.flatten
}

pub fn tokenize_line(line: String, line_no: Int) -> List(SpannedToken) {
  line
  |> string.to_graphemes
  |> scan(line_no, 1, [])
  |> list.reverse
  |> fn(tokens) {
    list.append(tokens, [SpannedToken(Newline, Span(line_no, -1, -1))])
  }
}

// ---- Automate de scan -------------------------------------------------------

fn scan(
  chars: List(String),
  line: Int,
  col: Int,
  acc: List(SpannedToken),
) -> List(SpannedToken) {
  case chars {
    [] -> acc

    [c, ..rest] if c == " " || c == "\t" -> scan(rest, line, col + 1, acc)

    [";", ..rest] -> emit_comment(rest, line, col, acc)

    ["/", "/", ..rest] -> emit_comment(rest, line, col, acc)

    ["/", ..rest] ->
      scan(rest, line, col + 1, [
        SpannedToken(Unknown("/"), Span(line, col, col)),
        ..acc
      ])

    ["-", ..rest] ->
      case rest {
        [c, ..] ->
          case is_digit(c) {
            // nombre négatif, seul cas où le - est valide
            True -> emit_number(chars, line, col, acc)
            False ->
              scan(rest, line, col + 1, [
                SpannedToken(Unknown("-"), Span(line, col, col)),
                ..acc
              ])
          }
        _ ->
          scan(rest, line, col + 1, [
            SpannedToken(Unknown("-"), Span(line, col, col)),
            ..acc
          ])
      }

    [c, ..rest] ->
      case is_digit(c) {
        True -> emit_number(chars, line, col, acc)
        False ->
          case is_ident_start(c) {
            True -> emit_ident(chars, line, col, acc)
            False ->
              scan(rest, line, col + 1, [
                SpannedToken(Unknown(c), Span(line, col, col)),
                ..acc
              ])
          }
      }
  }
}

// ---- Émission des tokens composés -------------------------------------------

fn emit_comment(
  chars: List(String),
  line: Int,
  col: Int,
  acc: List(SpannedToken),
) -> List(SpannedToken) {
  let text = string.join(chars, "")
  let end_col = col + string.length(text)
  [SpannedToken(Comment(string.trim(text)), Span(line, col, end_col)), ..acc]
}

fn emit_number(
  chars: List(String),
  line: Int,
  col: Int,
  acc: List(SpannedToken),
) -> List(SpannedToken) {
  let #(raw_chars, rest) = case chars {
    ["-", ..rest] -> {
      let #(digits, remaining) = take_while(rest, is_digit)
      #(["-", ..digits], remaining)
    }
    _ -> take_while(chars, is_digit)
  }
  let raw = string.join(raw_chars, "")
  let end_col = col + string.length(raw) - 1
  let token = case int.parse(raw) {
    Ok(n) -> Number(n)
    Error(_) -> Unknown(raw)
  }
  scan(rest, line, end_col + 1, [
    SpannedToken(token, Span(line, col, end_col)),
    ..acc
  ])
}

fn emit_ident(
  chars: List(String),
  line: Int,
  col: Int,
  acc: List(SpannedToken),
) -> List(SpannedToken) {
  let #(word_chars, rest) = take_while(chars, is_ident_char)
  let raw = string.join(word_chars, "")
  let end_col = col + string.length(raw) - 1
  scan(rest, line, end_col + 1, [
    SpannedToken(Ident(string.uppercase(raw)), Span(line, col, end_col)),
    ..acc
  ])
}

// ---- Utilitaires ------------------------------------------------------------

fn take_while(
  chars: List(String),
  pred: fn(String) -> Bool,
) -> #(List(String), List(String)) {
  case chars {
    [c, ..rest] ->
      case pred(c) {
        True -> {
          let #(taken, remaining) = take_while(rest, pred)
          #([c, ..taken], remaining)
        }
        False -> #([], chars)
      }
    _ -> #([], chars)
  }
}

fn is_digit(c: String) -> Bool {
  case c {
    "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
    _ -> False
  }
}

fn is_ident_start(c: String) -> Bool {
  is_alpha(c) || c == "_"
}

fn is_ident_char(c: String) -> Bool {
  is_alpha(c) || is_digit(c) || c == "_"
}

fn is_alpha(c: String) -> Bool {
  let code = case string.to_utf_codepoints(c) {
    [cp] -> string.utf_codepoint_to_int(cp)
    _ -> 0
  }
  { code >= 65 && code <= 90 } || { code >= 97 && code <= 122 }
}
