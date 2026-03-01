import gleam/list
import gleeunit/should
import lmc/emulator
import lmc/lexer
import lmc/parser

// ---- Helpers ----------------------------------------------------------------

fn run(source: String, input: List(Int)) -> List(Int) {
  let assert Ok(program) = source |> lexer.tokenize |> parser.parse
  let assert Ok(state) = emulator.load(program, input)
  let assert Ok(final) = emulator.run(state)
  final.output
}

fn run_error(source: String, input: List(Int)) -> emulator.EmulatorError {
  let assert Ok(program) = source |> lexer.tokenize |> parser.parse
  let assert Ok(state) = emulator.load(program, input)
  let assert Error(e) = emulator.run(state)
  e
}

fn load_error(source: String) -> emulator.EmulatorError {
  let assert Ok(program) = source |> lexer.tokenize |> parser.parse
  let assert Error(e) = emulator.load(program, [])
  e
}

// ---- INP / OUT / HLT --------------------------------------------------------

pub fn inp_out_test() {
  run("INP\nOUT\nHLT", [42])
  |> should.equal([42])
}

pub fn multiple_outputs_test() {
  run("INP\nOUT\nINP\nOUT\nHLT", [7, 13])
  |> should.equal([7, 13])
}

// ---- STA / LDA --------------------------------------------------------------

pub fn sta_lda_test() {
  "INP
STA x
LDA x
OUT
HLT
x DAT"
  |> run([99])
  |> should.equal([99])
}

// ---- ADD / SUB --------------------------------------------------------------

pub fn add_test() {
  "INP
STA a
INP
ADD a
OUT
HLT
a DAT"
  |> run([3, 5])
  |> should.equal([8])
}

pub fn sub_test() {
  "INP
STA a
INP
STA b
LDA a
SUB b
OUT
HLT
a DAT
b DAT"
  |> run([10, 3])
  |> should.equal([7])
}

// ---- BRA --------------------------------------------------------------------

/// BRA doit sauter inconditionnellement — le OUT ne doit pas être exécuté.
pub fn bra_skips_test() {
  "INP
BRA skip
OUT
skip HLT"
  |> run([99])
  |> should.equal([])
}

// ---- BRZ --------------------------------------------------------------------

pub fn brz_taken_test() {
  "INP
BRZ end
OUT
end HLT"
  |> run([0])
  |> should.equal([])
}

pub fn brz_not_taken_test() {
  "INP
BRZ end
OUT
end HLT"
  |> run([5])
  |> should.equal([5])
}

// ---- BRP --------------------------------------------------------------------

/// BRP branch si l'accumulateur est >= 0 (flag négatif = False).
pub fn brp_taken_test() {
  "INP
BRP pos
OUT
pos HLT"
  |> run([5])
  |> should.equal([])
}

pub fn brp_not_taken_test() {
  "INP
BRP pos
OUT
pos HLT"
  |> run([-1])
  |> should.equal([-1])
}

// ---- DAT --------------------------------------------------------------------

pub fn dat_initial_value_test() {
  "LDA k
OUT
HLT
k DAT 42"
  |> run([])
  |> should.equal([42])
}

pub fn dat_default_zero_test() {
  "LDA x
OUT
HLT
x DAT"
  |> run([])
  |> should.equal([0])
}

// ---- Boucle comptée ---------------------------------------------------------

/// Décompte de n jusqu'à 1, en sortant chaque valeur.
pub fn countdown_test() {
  "INP
loop OUT
SUB one
BRZ end
BRP loop
end HLT
one DAT 1"
  |> run([3])
  |> should.equal([3, 2, 1])
}

// ---- Programme complet : division entière -----------------------------------

pub fn division_test() {
  "start INP
  STA dividend
  INP
  STA divisor
  LDA zero
  STA answer
  LDA dividend
loop SUB divisor
  STA dividend
  BRP greater
  LDA answer
  OUT
  HLT
greater LDA answer
  ADD one
  STA answer
  LDA dividend
  BRA loop
zero    DAT 0
one     DAT 1
answer  DAT
dividend DAT
divisor  DAT"
  |> run([10, 3])
  |> should.equal([3])
}

pub fn division_exact_test() {
  "start INP
  STA dividend
  INP
  STA divisor
  LDA zero
  STA answer
  LDA dividend
loop SUB divisor
  STA dividend
  BRP greater
  LDA answer
  OUT
  HLT
greater LDA answer
  ADD one
  STA answer
  LDA dividend
  BRA loop
zero    DAT 0
one     DAT 1
answer  DAT
dividend DAT
divisor  DAT"
  |> run([9, 3])
  |> should.equal([3])
}

// ---- Erreurs ----------------------------------------------------------------

pub fn no_input_error_test() {
  run_error("INP\nHLT", [])
  |> should.equal(emulator.NoInput)
}

pub fn undefined_label_error_test() {
  load_error("ADD missing\nHLT")
  |> should.equal(emulator.UndefinedLabel("MISSING"))
}

pub fn program_too_long_error_test() {
  // 101 instructions INP dépasse la limite de 100 cellules
  let source =
    list.repeat("INP", 101)
    |> list.fold("", fn(acc, line) { acc <> line <> "\n" })
  load_error(source)
  |> should.equal(emulator.ProgramTooLong)
}
