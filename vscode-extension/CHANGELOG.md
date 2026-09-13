# Changelog

## 0.2.0

- **`.lmc` and `.lmcobj` files have their own icons** in the explorer and in tabs: three lines of
  code for the source, a grid of memory cells for the object file. They show with the default icon
  theme; an icon theme that already has an icon for these files keeps its own. The emulator tab
  has one too: the memory grid, with one cell read and one written.
- **The emulator page says what the model simplifies**: no `MAR`, `MBR` or `IR`, and what "reading"
  a register means when its value is always present on its outputs.
- **The Fetch phase now says where its address comes from**: `read PC → 0` comes before
  `read mem[0] → 5003`. The processor reads the program counter to know which cell to fetch,
  and that read was not shown.
- **The emulator tab is named after the file it runs**: `LMC - fibo` for `fibo.lmc`, instead of
  `LMC — Emulator`. With several programs open, the tab says which one the panel is tied to.
- **Fix: after Run, the Fetch / Decode / Execute panel ran off the bottom of the window.** It was
  meant to scroll inside itself, but nothing bounded its height, so a long trace pushed it past
  the screen. It now takes the space left and gets its own vertical scrollbar.
- **The colours of a step stay put, and now cover the registers too.** The cells an instruction
  read or wrote used to flash for 600 ms; by the time you looked up from the code at the grid, it
  was over. They now keep their colour until the next instruction runs. The registers carry the
  same two colours: a step does two things, one to memory and one to the processor, and only the
  first was visible. A register both read and written in one step is pink, the warm colour going
  to the act that changes the machine.
- **The Execute lines now name the implicit operand.** `ADD b` used to read `read mem[4] → 7` then
  `ACC 5 → 12`, and the 5 came from nowhere; it now says `read ACC → 5` in between. That is the
  whole point of an accumulator machine — one of the two operands is always implicit — and the
  trace was the one place it could be seen. `OUT`, `STA`, `MOV`, `PSH`, `POP`, `JSR` and the
  conditional branches say their reads too, including a `BRZ` that does not jump, whose only
  observable act is having read the accumulator.

## 0.1.3

- **Fix: putting the cursor on a `DAT` line holding several values outlined the wrong cell.**
  `lst: DAT 12, 5, 89, 4` is one line and four cells; the panel now outlines the first of them,
  the one `lst` names, instead of an arbitrary later one.

## 0.1.2

- **Requires VS Code 1.105.0 or later** (it declared 1.80.0). Older versions will no longer offer
  the extension.

## 0.1.1

- **Fix: the Fetch / Decode / Execute lines could render in a serif font.** They use the editor's
  font, and a font stack naming only fonts that are missing from the machine, with no generic
  family at the end, falls back to the browser default — which is serif. The stack now ends in
  `monospace`, so no font setting can do that again. Same fix for the inline code in tooltips.

## 0.1.0

First public release.

- The **LMC** language: seventeen mnemonics, five registers (`ACC`, `SI`, `LR`, `SP`, `PC`), a
  hundred memory cells, four-digit machine words. Subroutines (`JSR`/`RET`), a stack (`PSH`/`POP`),
  indexed addressing (`lst[SI]`) and a screen (`PLT`).
- **Diagnostics that explain**: an undefined label, a missing `HLT`, a program that outgrows the
  hundred cells, an address outside 0-99 that would otherwise assemble silently into another
  perfectly valid instruction.
- **Hover, go to definition, find references, completion** on labels and mnemonics, and
  **formatting** of the whole document.
- **A step-through emulator** (command "LMC: Open Emulator"): the memory grid, the registers, the
  input and output trays, and the Fetch / Decode / Execute cycle unfolded at every step. The cells
  an instruction touched pulse, teal for a read and pink for a write. Panel and editor are synced
  both ways.
- **Assemble, Load and Run are three separate acts**: "Assemble" writes a `.lmcobj` next to the
  source, "Load" reads that file back off the disk. Loading before assembling fails, and editing
  the source without reassembling loads the old program, as a real toolchain does.
- **Five interface languages** — French, English, Spanish, Japanese, Korean — chosen with the
  `lmc.locale` setting, which the diagnostics and the panel both follow. The Spanish, Japanese and
  Korean have not yet been read by anyone who speaks them: corrections are welcome.
