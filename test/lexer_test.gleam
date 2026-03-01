import gleam/list
import gleeunit/should
import lmc/lexer.{Comment, Ident, Minus, Newline, Number, tokenize_line}

/// Extrait uniquement les tokens (sans les spans) d'une ligne.
fn tokens(line: String) {
  tokenize_line(line, 1) |> list.map(fn(t) { t.value })
}

/// Les identifiants sont normalisés en majuscules.
pub fn identifiers_uppercased_test() {
  tokens("add") |> should.equal([Ident("ADD"), Newline])
}

/// Les entiers positifs sont tokenisés en Number.
pub fn number_test() {
  tokens("42") |> should.equal([Number(42), Newline])
}

/// Un commentaire `;` consomme tout jusqu'à la fin de la ligne.
pub fn semicolon_comment_test() {
  tokens("; ceci est un commentaire")
  |> should.equal([Comment("ceci est un commentaire"), Newline])
}

/// Une ligne complète : label, mnémonique, opérande et commentaire `//`.
pub fn full_instruction_line_test() {
  tokens("loop SUB one // décrémenter")
  |> should.equal([
    Ident("LOOP"),
    Ident("SUB"),
    Ident("ONE"),
    Comment("décrémenter"),
    Newline,
  ])
}

/// DAT avec valeur négative : le `-` est un token Minus séparé du nombre.
pub fn dat_negative_test() {
  tokens("DAT -5")
  |> should.equal([Ident("DAT"), Minus, Number(5), Newline])
}
