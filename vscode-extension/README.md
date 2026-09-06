# LMC — teaching assembly language

The **LMC** assembly language in VS Code: everything you need to write, understand and run programs
for a machine with a hundred memory cells, in class.

**Available in French, English, Spanish, Japanese and Korean.** Diagnostics, hover, completion and
the emulator panel all follow one setting, `lmc.locale` (`fr`, `en`, `es`, `ja`, `ko`, or `auto`).
It is `auto` by default, which follows VS Code's display language. **Set it explicitly if you teach
in a language other than the one your editor is in**, which is the common case: a display language
stays English for most people whatever their country, because nobody changes it. A language this
extension does not speak falls back to English rather than to blanks.

The Spanish, Japanese and Korean have not been read by anyone who speaks them. Corrections are very
welcome — an awkward turn of phrase in a teaching tool costs more than in most software.

This is not the original LMC. The machine word is four digits, there are five registers (`ACC`,
`SI`, `LR`, `SP`, `PC`) and seventeen mnemonics, including `MOV`, subroutines (`JSR`/`RET`), a stack
(`PSH`/`POP`) and a screen (`PLT`).

**Bringing a program in from a stock LMC emulator usually costs one edit**: a colon after each
label, `FIRST DAT` becoming `FIRST: DAT`. Checked by running the classic two-input adder and a
classic countdown loop, which both work with nothing else changed. Two things still bite: textbooks
that spell the mnemonics `STO`, `BR` or `COB` (here they are `STA`, `BRA` and `HLT`), and a label
named after a register, since `ACC`, `SI`, `LR`, `SP` and `PC` are reserved words. Going the other
way is another matter: anything using `MOV`, `JSR`, `PSH` or `PLT` has nowhere to run but here.

## The instruction set

Seventeen mnemonics. Hovering over any of them in the editor gives this same text, in your language,
with the details this table leaves out.

| | |
|---|---|
| `INP` | read a value from the input into the accumulator |
| `OUT` | write the accumulator to the output |
| `HLT` | stop the program |
| `ADD addr` | add the value at the address to the accumulator |
| `SUB addr` | subtract the value at the address from the accumulator |
| `LDA addr` | load the value at the address into the accumulator |
| `STA addr` | store the accumulator at the address |
| `MOV dst, src` | the general form of both: `LDA n` is `MOV ACC, n`, `STA n` is `MOV n, ACC` |
| `BRA addr` | unconditional jump |
| `BRZ addr` | jump if accumulator = 0 |
| `BRP addr` | jump if accumulator >= 0 |
| `JSR sub` | call a subroutine, recording the return address in `LR` |
| `RET` | return to the last caller: jumps to `LR`, also written `MOV PC, LR` |
| `PSH reg` | push a register onto the stack; with none written, `ACC` |
| `POP reg` | pop the top of the stack into a register; with none written, `ACC` |
| `PLT addr` | light a pixel, reading `x`, `y` and the colour from three cells at `addr` |
| `DAT n, ...` | reserve one or more memory cells |

A label ends with a colon (`total: DAT 0`), and `lst[SI]` addresses the cell `lst + SI`, which is
what lets one instruction walk an array. Branches and `PLT` cannot be indexed.

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

At every step, the cells the instruction touched pulse: **teal for a cell that was read, pink for
one that was written**. Reading changes nothing, writing changes the machine, and the grid says
which just happened.

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
curriculum. The extension is open source, MIT, at
[lmc-vscode](https://github.com/MMarchand-NSI/lmc-vscode); issues and corrections are welcome there,
including on the translations. The language server it drives is a separate, private repository, kept
apart so that it stays editor-independent rather than tied to VS Code; it ships inside this
extension, so nothing else is needed to install and use it.
