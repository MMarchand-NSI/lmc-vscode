import gleeunit/should
import lmc/runner/load
import lmc/runner/run
import lmc/runner/state
import lmc/semantic/pipeline

// Smoke test for the standalone Emulator API documented in README.md —
// exercises the real lmc_lsp git dependency (see gleam.toml, CLAUDE.md)
// rather than a local copy of the lexer/parser/runner.

pub fn inp_out_test() {
  let result = pipeline.parse("INP\nOUT\nHLT")
  let assert Ok(initial) = load.load(result, [42])
  let #(final, _events) = run.run_to_halt(initial)

  final.status |> should.equal(state.Halted)
  final.output |> should.equal([42])
}

pub fn undefined_label_test() {
  let result = pipeline.parse("LDA missing\nHLT")
  result.diagnostics |> should.not_equal([])
}
