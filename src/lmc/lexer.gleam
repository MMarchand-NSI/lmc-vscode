import gleam/int
import gleam/list
import gleam/regexp
import gleam/set
import gleam/string
import nibble/lexer

// ---- Types ------------------------------------------------------------------

pub type Token {
  Ident(String)
  // identifiant brut : label, mnémonique, référence
  Number(Int)
  // entier positif, validation laissée au parser
  Minus
  // '-' isolé, pour DAT -5
  Comment(String)
  // texte après ; ou //
  Newline
  Unknown(String)
  // caractère non reconnu
}

// ---- Point d'entrée ---------------------------------------------------------

pub fn tokenize(source: String) -> List(lexer.Token(Token)) {
  source
  |> string.split("\n")
  |> list.index_map(fn(line, idx) { tokenize_line(line, idx + 1) })
  |> list.flatten
}

pub fn tokenize_line(line: String, line_no: Int) -> List(lexer.Token(Token)) {
  let tokens = case lexer.run(line, line_lexer()) {
    Ok(tokens) -> tokens
    Error(_) -> []
  }
  list.append(tokens, [
    lexer.Token(lexer.Span(line_no, -1, line_no, -1), "", Newline),
  ])
}

// ---- Règles de tokenisation -------------------------------------------------

fn line_lexer() -> lexer.Lexer(Token, Nil) {
  lexer.simple([
    comment_matcher("//"),
    comment_matcher(";"),
    lexer.identifier("[a-zA-Z_]", "[a-zA-Z0-9_]", set.new(), fn(name) {
      Ident(string.uppercase(name))
    }),
    positive_int(),
    lexer.token("-", Minus),
    lexer.whitespace(Nil) |> lexer.ignore,
    lexer.keep(fn(lexeme, lookahead) {
      let assert Ok(any) = regexp.from_string("^.$")
      let assert Ok(alnum) = regexp.from_string("[a-zA-Z0-9_\\-]")
      case
        regexp.check(any, lexeme)
        && !regexp.check(alnum, lookahead)
        || lookahead == ""
      {
        True -> Ok(Unknown(lexeme))
        False -> Error(Nil)
      }
    }),
  ])
}

// ---- Matcher pour les entiers positifs --------------------------------------

fn positive_int() -> lexer.Matcher(Token, Nil) {
  let assert Ok(digits) = regexp.from_string("^[0-9]+$")
  let assert Ok(digit) = regexp.from_string("^[0-9]$")
  lexer.keep(fn(lexeme, lookahead) {
    case regexp.check(digits, lexeme) && !regexp.check(digit, lookahead) {
      True ->
        case int.parse(lexeme) {
          Ok(n) -> Ok(Number(n))
          Error(_) -> Error(Nil)
        }
      False -> Error(Nil)
    }
  })
}

// ---- Matcher pour les commentaires ------------------------------------------

fn comment_matcher(prefix: String) -> lexer.Matcher(Token, Nil) {
  let prefix_len = string.length(prefix)
  lexer.custom(fn(_, lexeme, next) {
    case string.starts_with(prefix, lexeme) && lexeme != prefix {
      True -> lexer.Skip
      False ->
        case string.starts_with(lexeme, prefix) {
          False -> lexer.NoMatch
          True ->
            case next {
              "" ->
                lexer.Keep(
                  Comment(string.trim(string.drop_start(lexeme, prefix_len))),
                  Nil,
                )
              _ -> lexer.Skip
            }
        }
    }
  })
}
