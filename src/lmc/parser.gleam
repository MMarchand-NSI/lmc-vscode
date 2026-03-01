import gleam/option.{type Option, None, Some}
import lmc/lexer.{type Token, Comment, Ident, Minus, Newline, Number}
import nibble
import nibble/lexer as nlexer

// ---- AST --------------------------------------------------------------------

pub type Program {
  Program(lines: List(Line))
}

pub type Line {
  Line(
    label: Option(String),
    instruction: Option(Instruction),
    comment: Option(String),
  )
}

pub type Instruction {
  Add(String)
  Sub(String)
  Sta(String)
  Lda(String)
  Bra(String)
  Brz(String)
  Brp(String)
  Inp
  Out
  Hlt
  Dat(Int)
}

// ---- Entry point ------------------------------------------------------------

pub fn parse(
  tokens: List(nlexer.Token(Token)),
) -> Result(Program, List(nibble.DeadEnd(Token, Nil))) {
  nibble.run(tokens, program_parser())
}

// ---- Parsers ----------------------------------------------------------------

fn program_parser() -> nibble.Parser(Program, Token, Nil) {
  use lines <- nibble.do(nibble.many(line_parser()))
  use _ <- nibble.do(nibble.eof())
  nibble.return(Program(lines))
}

fn line_parser() -> nibble.Parser(Line, Token, Nil) {
  use label <- nibble.do(nibble.optional(label_parser()))
  use instr <- nibble.do(nibble.optional(instruction_parser()))
  use comment <- nibble.do(nibble.optional(comment_parser()))
  use _ <- nibble.do(nibble.token(Newline))
  nibble.return(Line(label, instr, comment))
}

fn label_parser() -> nibble.Parser(String, Token, Nil) {
  nibble.take_map("label", fn(tok) {
    case tok {
      Ident(s) ->
        case is_mnemonic(s) {
          False -> Some(s)
          True -> None
        }
      _ -> None
    }
  })
}

fn comment_parser() -> nibble.Parser(String, Token, Nil) {
  nibble.take_map("comment", fn(tok) {
    case tok {
      Comment(s) -> Some(s)
      _ -> None
    }
  })
}

fn instruction_parser() -> nibble.Parser(Instruction, Token, Nil) {
  use mnemonic <- nibble.do(nibble.take_map("mnemonic", fn(tok) {
    case tok {
      Ident(s) ->
        case is_mnemonic(s) {
          True -> Some(s)
          False -> None
        }
      _ -> None
    }
  }))
  case mnemonic {
    "ADD" -> addr_operand() |> nibble.map(Add)
    "SUB" -> addr_operand() |> nibble.map(Sub)
    "STA" -> addr_operand() |> nibble.map(Sta)
    "LDA" -> addr_operand() |> nibble.map(Lda)
    "BRA" -> addr_operand() |> nibble.map(Bra)
    "BRZ" -> addr_operand() |> nibble.map(Brz)
    "BRP" -> addr_operand() |> nibble.map(Brp)
    "INP" -> nibble.return(Inp)
    "OUT" -> nibble.return(Out)
    "HLT" -> nibble.return(Hlt)
    _ -> dat_operand()
    // "DAT"
  }
}

fn addr_operand() -> nibble.Parser(String, Token, Nil) {
  nibble.take_map("address", fn(tok) {
    case tok {
      Ident(s) -> Some(s)
      _ -> None
    }
  })
}

fn dat_operand() -> nibble.Parser(Instruction, Token, Nil) {
  nibble.one_of([
    {
      use _ <- nibble.do(nibble.token(Minus))
      use n <- nibble.do(nibble.take_map("number", fn(tok) {
        case tok {
          Number(n) -> Some(n)
          _ -> None
        }
      }))
      nibble.return(Dat(-n))
    },
    nibble.take_map("number", fn(tok) {
      case tok {
        Number(n) -> Some(Dat(n))
        _ -> None
      }
    }),
    nibble.return(Dat(0)),
  ])
}

fn is_mnemonic(s: String) -> Bool {
  case s {
    "ADD" | "SUB" | "STA" | "LDA" | "BRA" | "BRZ" | "BRP" | "INP" | "OUT"
    | "HLT" | "DAT" -> True
    _ -> False
  }
}
