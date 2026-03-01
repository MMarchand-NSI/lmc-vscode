import gleam/option.{None, Some}
import gleeunit/should
import lmc/lexer
import lmc/parser.{
  Add, Bra, Brp, Brz, Dat, Hlt, Inp, Lda, Line, Out, Program, Sta, Sub,
}

/// Parse a source string and return the list of lines (unwrapping Ok).
fn parse(source: String) -> List(parser.Line) {
  let assert Ok(Program(lines)) =
    source
    |> lexer.tokenize
    |> parser.parse
  lines
}

/// Parse a single instruction line (no label, no comment).
fn instr(source: String) -> parser.Instruction {
  let assert [Line(None, Some(i), None)] = parse(source)
  i
}

// ---- Instructions with address operand --------------------------------------

pub fn add_test() {
  instr("ADD foo") |> should.equal(Add("FOO"))
}

pub fn sub_test() {
  instr("SUB bar") |> should.equal(Sub("BAR"))
}

pub fn sta_test() {
  instr("STA result") |> should.equal(Sta("RESULT"))
}

pub fn lda_test() {
  instr("LDA val") |> should.equal(Lda("VAL"))
}

pub fn bra_test() {
  instr("BRA loop") |> should.equal(Bra("LOOP"))
}

pub fn brz_test() {
  instr("BRZ end") |> should.equal(Brz("END"))
}

pub fn brp_test() {
  instr("BRP greater") |> should.equal(Brp("GREATER"))
}

// ---- Instructions with no operand -------------------------------------------

pub fn inp_test() {
  instr("INP") |> should.equal(Inp)
}

pub fn out_test() {
  instr("OUT") |> should.equal(Out)
}

pub fn hlt_test() {
  instr("HLT") |> should.equal(Hlt)
}

// ---- DAT variants -----------------------------------------------------------

pub fn dat_zero_test() {
  instr("DAT 0") |> should.equal(Dat(0))
}

pub fn dat_positive_test() {
  instr("DAT 42") |> should.equal(Dat(42))
}

pub fn dat_negative_test() {
  instr("DAT -5") |> should.equal(Dat(-5))
}

pub fn dat_no_value_test() {
  instr("DAT") |> should.equal(Dat(0))
}

// ---- Labels -----------------------------------------------------------------

pub fn label_test() {
  let assert [Line(Some("START"), Some(Inp), None)] = parse("start INP")
  Nil
}

pub fn label_with_operand_test() {
  let assert [Line(Some("LOOP"), Some(Sub("ONE")), None)] =
    parse("loop SUB one")
  Nil
}

// ---- Comments ---------------------------------------------------------------

pub fn comment_only_test() {
  let assert [Line(None, None, Some("un commentaire"))] =
    parse("; un commentaire")
  Nil
}

pub fn inline_comment_test() {
  let assert [Line(None, Some(Inp), Some("lire entrée"))] =
    parse("INP // lire entrée")
  Nil
}

pub fn label_instr_comment_test() {
  let assert [Line(Some("LOOP"), Some(Sub("ONE")), Some("décrémenter"))] =
    parse("loop SUB one // décrémenter")
  Nil
}

// ---- Empty and multi-line ---------------------------------------------------

pub fn empty_line_test() {
  parse("") |> should.equal([Line(None, None, None)])
}

pub fn multi_line_test() {
  parse("INP\nSTA result\nHLT")
  |> should.equal([
    Line(None, Some(Inp), None),
    Line(None, Some(Sta("RESULT")), None),
    Line(None, Some(Hlt), None),
  ])
}

pub fn full_program_test() {
  "start INP
	STA dividend
	INP
	STA divisor
	HLT
zero	DAT 0
answer	DAT"
  |> parse
  |> should.equal([
    Line(Some("START"), Some(Inp), None),
    Line(None, Some(Sta("DIVIDEND")), None),
    Line(None, Some(Inp), None),
    Line(None, Some(Sta("DIVISOR")), None),
    Line(None, Some(Hlt), None),
    Line(Some("ZERO"), Some(Dat(0)), None),
    Line(Some("ANSWER"), Some(Dat(0)), None),
  ])
}
