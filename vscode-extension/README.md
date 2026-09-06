# LMC — teaching assembly language

The **LMC** assembly language in VS Code: everything you need to write, understand and run programs
for a machine with a hundred memory cells, in class.

**Available in French, English, Spanish, Japanese and Korean.** Diagnostics, hover, completion and
the emulator panel all follow the `lmc.locale` setting (`fr`, `en`, `es`, `ja`, `ko`, or `auto` to
follow VS Code's display language). French is the default, deliberately: VS Code's display language
stays English for most people whatever their country, so it is a poor guess at the language of a
classroom. A language nobody here speaks falls back to English rather than to blanks.

Only French and English have been read by people who speak them. The other three were written with
care, from the server's own vocabulary, but they have not been reviewed — corrections are welcome.

This is not the original LMC. The machine word is four digits, there are five registers (`ACC`,
`SI`, `LR`, `SP`, `PC`) and seventeen mnemonics, including `MOV`, subroutines (`JSR`/`RET`), a stack
(`PSH`/`POP`) and a screen (`PLT`).

**Bringing a program in from a stock LMC emulator usually costs one edit**: a colon after each
label, `FIRST DAT` becoming `FIRST: DAT`. Checked by running the classic two-input adder and a
classic countdown loop, which both work with nothing else changed. Two things still bite: textbooks
that spell the mnemonics `STO`, `BR` or `COB` (here they are `STA`, `BRA` and `HLT`), and a label
named after a register, since `ACC`, `SI`, `LR`, `SP` and `PC` are reserved words. Going the other
way is another matter: anything using `MOV`, `JSR`, `PSH` or `PLT` has nowhere to run but here.

The language reference is
[LANGAGE.md](https://github.com/MMarchand-NSI/lmc_lsp/blob/master/LANGAGE.md) — in French, like the
example programs that ship with the extension.

## What the extension gives you

- **Diagnostics that explain** rather than merely report: an undefined label, a missing `HLT`, a
  program that outgrows the hundred cells, an address outside 0-99 — that last one because, written
  as is, it would overflow into the mode digit and assemble into *another perfectly valid
  instruction*, silently.
- **Hover, go to definition, find references, completion** on labels and mnemonics.
- **Formatting** of the whole document, to one canonical shape.
- **A step-through emulator**, command "LMC: Open Emulator". This is the centrepiece.

## The emulator

A grid of a hundred cells, the five registers, the input and output trays, and the
**Fetch / Decode / Execute** cycle unfolded at every step — including the program counter being
incremented during the read, which is what explains why a stopped machine shows a `PC` one past the
instruction that stopped it.

The panel and the editor are synced both ways: moving the cursor outlines the matching cell,
clicking a cell reveals its source line. That is the reason for a panel here rather than one of the
many standalone LMC simulators on the web.

The grid marks four things: the stack above `SP`, the cells a `DAT` reserved, the unused middle, and
the code. Those marks say **what the author wrote**, not what the machine does: nothing distinguishes
a code cell from a data cell, and a `STA` writing into code does not change a colour. That gap is
the lesson, not a defect.

**Assemble**, **Load** and **Run** are three separate acts, with three buttons. "Assemble" writes a
`.lmcobj` next to the source: four digits per line, one line per cell, no mnemonics and no labels,
because that is all the processor ever receives. "Load" reads that file back off the disk. Loading
before assembling fails, and editing the source without reassembling loads the old program: that is
how a real toolchain behaves.

## A screen

`PLT` lights a pixel on a 32 × 32 screen in eight colours. Colour 0 is the background, so lighting a
pixel in 0 erases it. A pixel outside the screen or outside the palette is not drawn, and the cycle
panel says so instead of leaving an unexplained blank.

## The code

Written for teaching *Numérique et Sciences Informatiques*, the French high-school computer science
curriculum. The language server lives in a separate repository,
[lmc_lsp](https://github.com/MMarchand-NSI/lmc_lsp), so that it stays editor-independent; the
extension itself is in [lmc-vscode](https://github.com/MMarchand-NSI/lmc-vscode).
