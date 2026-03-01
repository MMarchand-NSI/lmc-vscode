import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import lmc/parser.{
  type Instruction, type Line, type Program, Add, Bra, Brp, Brz, Dat, Hlt,
  Inp, Lda, Line, Out, Sta, Sub,
}

pub const memory_size: Int = 100

// ---- Types ------------------------------------------------------------------

pub type State {
  State(
    memory: List(Int),
    acc: Int,
    pc: Int,
    negative: Bool,
    input: List(Int),
    output: List(Int),
  )
}

pub type StepResult {
  Running(State)
  Halted(State)
}

pub type EmulatorError {
  UndefinedLabel(String)
  ProgramTooLong
  InvalidAddress(Int)
  NoInput
}

// ---- Public API -------------------------------------------------------------

/// Assemble a parsed program and initialise the machine with the given input.
pub fn load(
  program: Program,
  input: List(Int),
) -> Result(State, EmulatorError) {
  use memory <- result.try(assemble(program))
  Ok(State(
    memory: memory,
    acc: 0,
    pc: 0,
    negative: False,
    input: input,
    output: [],
  ))
}

/// Execute one instruction cycle.
pub fn step(state: State) -> Result(StepResult, EmulatorError) {
  use word <- result.try(mem_get(state.memory, state.pc))
  execute(decode(word), state)
}

/// Run until the machine halts or an error occurs.
pub fn run(state: State) -> Result(State, EmulatorError) {
  case step(state) {
    Error(e) -> Error(e)
    Ok(Halted(s)) -> Ok(s)
    Ok(Running(s)) -> run(s)
  }
}

// ---- Assembler --------------------------------------------------------------

fn assemble(program: Program) -> Result(List(Int), EmulatorError) {
  let #(labels, instrs) = collect(program.lines, dict.new(), [], 0, None)
  use encoded <- result.try(list.try_map(instrs, encode(_, labels)))
  case list.length(encoded) > memory_size {
    True -> Error(ProgramTooLong)
    False ->
      Ok(list.append(encoded, list.repeat(0, memory_size - list.length(encoded))))
  }
}

/// Walk lines in order, assigning addresses to instructions and collecting
/// labels. A label on an instruction-less line is carried forward to the next
/// instruction.
fn collect(
  lines: List(Line),
  labels: Dict(String, Int),
  instrs: List(Instruction),
  addr: Int,
  pending: Option(String),
) -> #(Dict(String, Int), List(Instruction)) {
  case lines {
    [] -> #(labels, list.reverse(instrs))
    [Line(label, instr, _), ..rest] -> {
      let effective = case label {
        Some(_) -> label
        None -> pending
      }
      case instr {
        None -> collect(rest, labels, instrs, addr, effective)
        Some(i) -> {
          let updated_labels = case effective {
            None -> labels
            Some(name) -> dict.insert(labels, name, addr)
          }
          collect(rest, updated_labels, [i, ..instrs], addr + 1, None)
        }
      }
    }
  }
}

fn encode(
  instr: Instruction,
  labels: Dict(String, Int),
) -> Result(Int, EmulatorError) {
  case instr {
    Hlt -> Ok(0)
    Inp -> Ok(901)
    Out -> Ok(902)
    Dat(n) -> Ok(n)
    Add(lbl) -> resolve(lbl, labels) |> result.map(fn(a) { 100 + a })
    Sub(lbl) -> resolve(lbl, labels) |> result.map(fn(a) { 200 + a })
    Sta(lbl) -> resolve(lbl, labels) |> result.map(fn(a) { 300 + a })
    Lda(lbl) -> resolve(lbl, labels) |> result.map(fn(a) { 500 + a })
    Bra(lbl) -> resolve(lbl, labels) |> result.map(fn(a) { 600 + a })
    Brz(lbl) -> resolve(lbl, labels) |> result.map(fn(a) { 700 + a })
    Brp(lbl) -> resolve(lbl, labels) |> result.map(fn(a) { 800 + a })
  }
}

fn resolve(
  label: String,
  labels: Dict(String, Int),
) -> Result(Int, EmulatorError) {
  dict.get(labels, label)
  |> result.map_error(fn(_) { UndefinedLabel(label) })
}

// ---- Decode -----------------------------------------------------------------

type DecodedInstr {
  DHlt
  DAdd(Int)
  DSub(Int)
  DSta(Int)
  DLda(Int)
  DBra(Int)
  DBrz(Int)
  DBrp(Int)
  DInp
  DOut
}

fn decode(word: Int) -> DecodedInstr {
  let addr = word % 100
  case word / 100 {
    0 -> DHlt
    1 -> DAdd(addr)
    2 -> DSub(addr)
    3 -> DSta(addr)
    5 -> DLda(addr)
    6 -> DBra(addr)
    7 -> DBrz(addr)
    8 -> DBrp(addr)
    9 ->
      case word {
        901 -> DInp
        902 -> DOut
        _ -> DHlt
      }
    _ -> DHlt
  }
}

// ---- Execute ----------------------------------------------------------------

fn execute(
  instr: DecodedInstr,
  state: State,
) -> Result(StepResult, EmulatorError) {
  let pc = state.pc + 1
  case instr {
    DHlt -> Ok(Halted(state))

    DAdd(addr) -> {
      use val <- result.try(mem_get(state.memory, addr))
      let acc = state.acc + val
      Ok(Running(State(..state, acc: acc, negative: acc < 0, pc: pc)))
    }

    DSub(addr) -> {
      use val <- result.try(mem_get(state.memory, addr))
      let acc = state.acc - val
      Ok(Running(State(..state, acc: acc, negative: acc < 0, pc: pc)))
    }

    DSta(addr) -> {
      use memory <- result.try(mem_set(state.memory, addr, state.acc))
      Ok(Running(State(..state, memory: memory, pc: pc)))
    }

    DLda(addr) -> {
      use val <- result.try(mem_get(state.memory, addr))
      Ok(Running(State(..state, acc: val, negative: val < 0, pc: pc)))
    }

    DBra(addr) -> Ok(Running(State(..state, pc: addr)))

    DBrz(addr) -> {
      let next_pc = case state.acc == 0 {
        True -> addr
        False -> pc
      }
      Ok(Running(State(..state, pc: next_pc)))
    }

    DBrp(addr) -> {
      let next_pc = case state.negative {
        False -> addr
        True -> pc
      }
      Ok(Running(State(..state, pc: next_pc)))
    }

    DInp ->
      case state.input {
        [] -> Error(NoInput)
        [val, ..rest] ->
          Ok(Running(State(
            ..state,
            acc: val,
            negative: val < 0,
            input: rest,
            pc: pc,
          )))
      }

    DOut ->
      Ok(Running(State(
        ..state,
        output: list.append(state.output, [state.acc]),
        pc: pc,
      )))
  }
}

// ---- Memory helpers ---------------------------------------------------------

fn mem_get(memory: List(Int), addr: Int) -> Result(Int, EmulatorError) {
  case addr >= 0 && addr < memory_size {
    False -> Error(InvalidAddress(addr))
    True ->
      case list.drop(memory, addr) {
        [val, ..] -> Ok(val)
        [] -> Error(InvalidAddress(addr))
      }
  }
}

fn mem_set(
  memory: List(Int),
  addr: Int,
  val: Int,
) -> Result(List(Int), EmulatorError) {
  case addr >= 0 && addr < memory_size {
    False -> Error(InvalidAddress(addr))
    True ->
      memory
      |> list.index_map(fn(cell, i) {
        case i == addr {
          True -> val
          False -> cell
        }
      })
      |> Ok
  }
}
