# Changelog

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
