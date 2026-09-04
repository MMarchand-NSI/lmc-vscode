import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import lmc/parse/span
import lmc/runner/event.{type Event}
import lmc/runner/instruction
import lmc/runner/load
import lmc/runner/memory
import lmc/runner/run
import lmc/runner/state.{type MachineState}
import lmc/semantic/ast
import lmc/semantic/pipeline

// Pure application state for the emulator webview — no FFI, no DOM, fully
// testable with `gleam test`. app.gleam wires this up to the actual webview
// (FFI + rendering); this module never imports it, only the other way
// around.

pub type Model {
  Model(
    source: String,
    parse: Option(pipeline.ParseResult),
    // Trois états distincts, et c'est tout le sujet : assembler n'est pas
    // charger, et charger n'est pas exécuter.
    //
    //   assembled  le résultat de l'assemblage du source courant. Recalculé
    //              à chaque frappe. Ne sert qu'à produire le fichier objet —
    //              ce n'est PAS la mémoire de la machine.
    //   loaded     l'image chargée en RAM, telle qu'au moment du chargement.
    //              C'est là que revient Reset.
    //   machine    la machine vivante, qui s'éloigne de `loaded` à mesure
    //              qu'on exécute.
    //
    // Les trois peuvent se désaccorder, et doivent pouvoir le faire :
    // modifier le source réassemble sans toucher à la RAM, exactement comme
    // éditer un .c ne change pas le binaire déjà chargé.
    assembled: Option(MachineState),
    loaded: Option(MachineState),
    machine: Option(MachineState),
    // Address <-> source line (0-indexed), derived once per `load_source`
    // from `load.address_offsets` — NOT re-derived by assuming address i is
    // ast.lines[i] (blank/comment-only lines don't get an address; see
    // lmc_lsp v0.1.5/v0.1.6). Powers the editor <-> webview sync both ways.
    address_to_line: Dict(Int, Int),
    line_to_address: Dict(Int, Int),
    // Same addressing as address_to_line (derived from the same
    // load.address_offsets call — see build_address_maps), just mapped to
    // the instruction itself instead of the line number. Powers
    // data_addresses, i.e. the grid's `DAT` marking; not needed for the
    // editor sync.
    address_to_instruction: Dict(Int, ast.Instruction),
    // Line the host's cursor is currently on — independent of execution
    // state, doesn't get reset by step/run/reset.
    cursor_line: Option(Int),
    // Pourquoi le source ne s'assemble pas, s'il ne s'assemble pas.
    assembly_error: Option(String),
    // Pourquoi le dernier chargement en RAM a échoué : fichier objet absent
    // (on n'a pas assemblé), ou illisible. Distinct de assembly_error : un
    // source parfaitement valide peut très bien n'avoir jamais été assemblé.
    ram_error: Option(String),
    // Fetch/Decode/Execute events from the *last* step/run_to_halt call —
    // lmc_lsp's runner already produces these per sub-phase, previously
    // just discarded. Powers the collapsible "what actually just
    // happened" panel — the point being to show that every instruction,
    // no matter the mnemonic, goes through the same three phases.
    last_events: List(Event),
    // Which button led to the current WaitingForInput, if any — True for
    // Run, False for Step. `resume_after_input` reads this to decide what
    // to do once the value arrives: Run should keep running past this INP
    // (to the next halt or the next INP), Step should complete only this
    // one instruction. Without tracking it, providing input always looked
    // like Step regardless of which button was actually clicked (see
    // resume_after_input's doc comment for the bug this fixes).
    run_after_input: Bool,
  )
}

pub fn init(source: String) -> Model {
  Model(
    source: "",
    parse: None,
    assembled: None,
    loaded: None,
    machine: None,
    address_to_line: dict.new(),
    line_to_address: dict.new(),
    address_to_instruction: dict.new(),
    cursor_line: None,
    assembly_error: None,
    ram_error: None,
    last_events: [],
    run_after_input: False,
  )
  |> assemble_source(source)
}

/// Ré-assemble si le source a changé. La webview reçoit le source à chaque
/// reprise de focus de l'éditeur et pas seulement aux vraies modifications
/// (webviewPanel.ts, onDidChangeActiveTextEditor, qui doit aussi
/// resynchroniser le curseur) — sans ce garde-fou, revenir sur l'onglet du
/// programme referait le travail pour rien.
///
/// Ne touche jamais à la RAM : éditer le source ne recharge pas la machine,
/// pas plus qu'éditer un .c ne change le binaire déjà en mémoire. Il faut
/// réassembler puis recharger.
pub fn set_source_if_changed(model: Model, source: String) -> Model {
  case source == model.source {
    True -> model
    False -> assemble_source(model, source)
  }
}

/// Assemble `source` : (re)construit les correspondances adresse <-> ligne
/// et le résultat d'assemblage dont sortira le fichier objet. N'écrit rien
/// en RAM — c'est `load_object_code` qui le fait, depuis le fichier.
pub fn assemble_source(model: Model, source: String) -> Model {
  let result = pipeline.parse(source)
  let base =
    Model(
      ..model,
      source: source,
      parse: Some(result),
      address_to_line: build_address_to_line(result),
      line_to_address: invert(build_address_to_line(result)),
      address_to_instruction: build_address_to_instruction(result),
    )

  case result.diagnostics {
    [] ->
      case load.load(result, []) {
        // L'entrée est toujours vide à l'assemblage : INP est traité
        // interactivement par `provide_input`, jamais fourni d'avance —
        // c'est un outil de pas à pas, pas un exécuteur de lots.
        Ok(assembled) ->
          Model(..base, assembled: Some(assembled), assembly_error: None)
        Error(err) ->
          Model(
            ..base,
            assembled: None,
            assembly_error: Some(load_error_message(err)),
          )
      }
    _ ->
      // Les erreurs de syntaxe et de résolution sont déjà visibles dans
      // l'éditeur via les diagnostics LSP — inutile de dupliquer le détail
      // ici, mais il n'y a pas d'assemblage possible non plus.
      Model(
        ..base,
        assembled: None,
        assembly_error: Some(
          "le programme contient des erreurs — voir les diagnostics dans l'éditeur",
        ),
      )
  }
}

/// Charge un fichier objet en RAM. `content` est le texte du `.lmcobj` tel
/// que l'hôte l'a lu sur le disque — pas les mots que la webview a en
/// mémoire. C'est délibéré : on charge le fichier, donc charger sans avoir
/// assemblé échoue, et modifier le source sans réassembler charge l'ancien
/// programme. Une vraie chaîne d'outils se comporte exactement comme ça.
pub fn load_object_code(model: Model, content: String) -> Model {
  case parse_object_code(content) {
    Error(message) -> Model(..model, ram_error: Some(message), last_events: [])
    Ok(words) -> {
      let image = machine_from_words(words)
      Model(
        ..model,
        loaded: Some(image),
        machine: Some(image),
        ram_error: None,
        last_events: [],
        run_after_input: False,
      )
    }
  }
}

/// Le chargement a échoué côté hôte (fichier objet absent, illisible).
pub fn fail_load(model: Model, message: String) -> Model {
  Model(..model, ram_error: Some(message))
}

/// Un mot par ligne, quatre chiffres, rien d'autre — le format qu'écrit
/// `object_code`. Le vérifier plutôt que de faire confiance : le fichier est
/// sur le disque, quelqu'un a pu l'éditer à la main, et c'est même une chose
/// intéressante à essayer.
fn parse_object_code(content: String) -> Result(List(Int), String) {
  let lines =
    content
    |> string.split("\n")
    |> list.map(string.trim)
    |> list.filter(fn(line) { line != "" })

  case lines {
    [] -> Error("le fichier objet est vide")
    _ ->
      case list.try_map(lines, parse_word) {
        Error(bad) ->
          Error(
            "le fichier objet contient une ligne illisible : « " <> bad <> " »",
          )
        Ok(words) ->
          case list.length(words) > memory.size {
            True ->
              Error("le fichier objet dépasse les 100 cases de la mémoire")
            False -> Ok(words)
          }
      }
  }
}

fn parse_word(line: String) -> Result(Int, String) {
  case int.parse(line) {
    Ok(value) if value >= 0 && value <= 9999 -> Ok(value)
    _ -> Error(line)
  }
}

/// Construit l'état initial de la machine autour d'une image mémoire. Même
/// forme que celle que produit `load.load` dans lmc_lsp — SP en haut de la
/// mémoire, PC à zéro, phase Fetch — mais à partir de mots bruts, puisque
/// c'est un fichier objet qu'on charge et non un source qu'on assemble.
fn machine_from_words(words: List(Int)) -> MachineState {
  let mem =
    list.index_fold(words, memory.new(), fn(m, word, address) {
      memory.write(m, address, word) |> result.unwrap(m)
    })

  state.MachineState(
    memory: mem,
    accumulator: 0,
    index: 0,
    link: 0,
    // La pile part du haut et descend ; SP désigne la prochaine case libre.
    stack_pointer: memory.size - 1,
    // Ce que le chargeur sait du programme : sa longueur. C'est ce qui
    // permet de détecter une pile qui descendrait jusque dans le code.
    program_end: list.length(words),
    program_counter: 0,
    instruction_register: 0,
    current_instruction: instruction.Hlt,
    phase: state.Fetch,
    input: [],
    output: [],
    status: state.Running,
  )
}

/// Remet la machine dans l'état où le chargement l'avait laissée. Ne
/// réassemble pas et ne recharge pas : Reset est un bouton du panneau avant,
/// pas une recompilation. Sans rien en RAM, il n'y a rien à remettre.
pub fn reset(model: Model) -> Model {
  Model(..model, machine: model.loaded, last_events: [], run_after_input: False)
}

/// Advance exactly one instruction (fetch/decode/execute), unless the
/// machine is halted, errored, or waiting on input. Marks any resulting
/// WaitingForInput as Step-originated — see `run_after_input`.
pub fn step(model: Model) -> Model {
  case model.machine {
    None -> model
    Some(m) -> {
      let #(next, events) = run.run_n(m, 1)
      Model(
        ..model,
        machine: Some(next),
        last_events: accumulate_events(m, model, events),
        run_after_input: False,
      )
    }
  }
}

/// Run until the machine stops progressing on its own — halted, errored, or
/// waiting on INP (not necessarily Halted, see lmc_lsp's own docs on
/// run_to_halt). Marks any resulting WaitingForInput as Run-originated —
/// see `run_after_input`.
pub fn run_to_halt(model: Model) -> Model {
  case model.machine {
    None -> model
    Some(m) -> {
      let #(next, events) = run.run_to_halt(m)
      Model(
        ..model,
        machine: Some(next),
        last_events: accumulate_events(m, model, events),
        run_after_input: True,
      )
    }
  }
}

/// Fetch and Decode only ever happen once per instruction, right at the
/// start (phase == Fetch); Execute can then pause (INP with no input) and
/// resume later without repeating them. If the machine we're stepping
/// *from* wasn't sitting at a fresh Fetch, this is a resume — append to
/// last_events instead of replacing it, so the panel shows the whole
/// instruction's cycle in one place (Fetch, Decode, "waiting", then the
/// rest of Execute once input arrives) instead of splitting it across two
/// separate, seemingly out-of-nowhere "Execute only" snapshots.
fn accumulate_events(
  before: MachineState,
  model: Model,
  new_events: List(Event),
) -> List(Event) {
  case before.phase {
    state.Fetch -> new_events
    _ -> list.append(model.last_events, new_events)
  }
}

pub fn provide_input(model: Model, value: Int) -> Model {
  case model.machine {
    None -> model
    Some(m) -> Model(..model, machine: Some(run.resume(m, value)))
  }
}

/// What the input form's submit handler should actually call — `provide_input`
/// only hands the value to the paused machine, it doesn't advance anything
/// on its own; something still has to run the INP's completion afterwards.
/// Which something depends on how the wait was entered: a Run that hit an
/// INP should keep running past it (to the next halt or the next INP), a
/// Step that hit one should complete only that instruction and stop, same
/// as any other step. `run_after_input` is exactly that memory — without
/// it, every input submission looked like Step regardless of which button
/// was clicked, since app.gleam had no way to tell the two apart itself
/// (see run_after_input's doc comment, and the "Step behaves like Run" bug
/// this replaced — this is that fix's mirror image for Run).
pub fn resume_after_input(model: Model, value: Int) -> Model {
  case model.run_after_input {
    True -> model |> provide_input(value) |> run_to_halt
    False -> model |> provide_input(value) |> step
  }
}

pub fn set_cursor_line(model: Model, line: Option(Int)) -> Model {
  Model(..model, cursor_line: line)
}

// ── Requêtes dérivées ─────────────────────────────────────────────

/// The mailbox address the machine is on, if any — either about to execute
/// (Running: PC hasn't been fetched from yet) or the one it stopped on
/// (WaitingForInput, Halted). This is what the memory-grid highlight keys
/// off; current_line is derived from it, for the editor side of the sync.
///
/// The `- 1` for the two stopped states is not a workaround: lmc_lsp's
/// runner increments the PC during the *fetch* phase, which is where a real
/// processor increments it too (Dive Into Systems §5.2; RISC-V's `JAL`
/// stores `pc+4` and ARM A32 reads the PC as "current instruction + 8" for
/// the same reason; on x86, an interrupt resuming after `HLT` finds the
/// saved instruction pointer *past* the `HLT`). So by the time we observe a
/// stopped machine, PC already points one past the instruction that
/// actually stopped it — `INP` with nothing to consume, or the `HLT`.
///
/// Keeping PC's raw value in the register panel and correcting only the
/// highlight is deliberate. The number is true and worth showing; what was
/// false was marking the *next* cell as the current one. On these programs
/// that cell is usually the first `DAT`, so a halted machine claimed it was
/// about to execute its own data — and decorated that source line in the
/// editor.
pub fn current_address(model: Model) -> Option(Int) {
  case model.machine {
    None -> None
    Some(m) ->
      Some(case m.status {
        state.WaitingForInput | state.Halted -> m.program_counter - 1
        _ -> m.program_counter
      })
  }
}

/// The source line (0-indexed) for current_address, if that address maps
/// to one (it always should, for any address a real MachineState can be
/// paused/about-to-fetch on).
pub fn current_line(model: Model) -> Option(Int) {
  case current_address(model) {
    None -> None
    Some(addr) -> dict.get(model.address_to_line, addr) |> option.from_result
  }
}

/// The mailbox address corresponding to the host's current cursor line, if
/// that line holds an instruction at all (blank/comment/label-only lines
/// don't).
pub fn cursor_address(model: Model) -> Option(Int) {
  case model.cursor_line {
    None -> None
    Some(line) -> dict.get(model.line_to_address, line) |> option.from_result
  }
}

/// The source line for a given mailbox address, for "click a mailbox ->
/// reveal its source line" — the reverse of current_line/cursor_address.
pub fn line_for_address(model: Model, address: Int) -> Option(Int) {
  dict.get(model.address_to_line, address) |> option.from_result
}

/// How many addresses the assembled program actually occupies — i.e. the
/// number of instruction-bearing lines, per load.address_offsets. Always a
/// contiguous range [0, count) since collect_addresses_loop in lmc_lsp
/// assigns addresses sequentially in source order; any address >= this is
/// outside the program (padding memory, always 0 until written). Lets the
/// webview de-emphasize those cells instead of giving all 100 equal visual
/// weight regardless of how short the program is.
pub fn program_length(model: Model) -> Int {
  case model.machine {
    None -> 0
    Some(m) -> m.program_end
  }
}

/// Le contenu d'un fichier objet : un mot machine de quatre chiffres par
/// ligne, une ligne par case assemblée, et rien d'autre. Pas de mnémonique,
/// pas de label, pas de commentaire — c'est tout l'intérêt de l'objet. Le
/// processeur ne voit que ces nombres, et `LDA 42` comme `MOV ACC, 42`
/// produisent la même ligne (LANGAGE.md, « MOV, et pourquoi LDA en est un
/// raccourci »).
///
/// Ce sont les mots que l'émulateur a réellement chargés, pas une seconde
/// traduction faite pour l'occasion : ils sortent de la même mémoire que
/// celle qu'affiche la grille, donc le fichier ne peut pas diverger de ce
/// qui tourne. `None` quand le programme n'assemble pas — un assembleur qui
/// rencontre une erreur ne produit pas d'objet.
pub fn object_code(model: Model) -> Option(String) {
  case model.assembled {
    None -> None
    Some(m) ->
      memory.to_list(m.memory)
      |> list.take(m.program_end)
      |> list.map(fn(word) { int.to_string(word) |> string.pad_start(4, "0") })
      |> string.join("\n")
      |> fn(text) { text <> "\n" }
      |> Some
  }
}

/// Les adresses que le source a réservées avec `DAT`, dans l'ordre. Une
/// entrée par *case* et non par ligne : « lst: DAT 12, 4, 86 » en donne
/// trois, « mot: DAT "LMC" » quatre — c'est déjà l'adressage de
/// `load.address_offsets`, dont address_to_instruction est dérivé, donc
/// rien n'est re-dérivé ici.
///
/// Attention à ce que cette information est, et à ce qu'elle n'est pas :
/// c'est de la *provenance*, pas une propriété de la machine. « Une
/// instruction est un nombre comme un autre. Rien ne distingue une case de
/// code d'une case de données : c'est le compteur ordinal qui décide, en
/// s'y arrêtant » (LANGAGE.md). La grille marque donc ce que le texte a
/// écrit, pas une frontière que le processeur connaîtrait — un `STA` qui
/// écrit dans une case de code, ou un `PC` qui tombe dans un `DAT`, ne
/// changent rien à ce marquage. C'est voulu : l'écart entre les deux est
/// précisément ce qu'il y a à comprendre.
pub fn data_addresses(model: Model) -> List(Int) {
  case model.machine {
    None -> []
    Some(_) -> data_addresses_of_source(model)
  }
}

fn data_addresses_of_source(model: Model) -> List(Int) {
  model.address_to_instruction
  |> dict.to_list
  |> list.filter_map(fn(pair) {
    case pair.1 {
      ast.Dat(_, _) -> Ok(pair.0)
      _ -> Error(Nil)
    }
  })
  |> list.sort(int.compare)
}

/// One entry per *phase* (Fetch, Decode, Execute — never more than three),
/// each carrying the individual events that happened during it. Grouped
/// rather than one flat line per event: Execute alone can produce several
/// events (e.g. INP resuming: "waiting" then "ACC <- input" then "ACC
/// changed") — a flat list would show three lines all prefixed "Execute",
/// which reads as three separate Execute phases and undermines the exact
/// point of this panel (every instruction is Fetch, Decode, Execute — not
/// Fetch, Decode, Execute, Execute, Execute).
pub fn last_cycle(model: Model) -> List(CyclePhase) {
  model.last_events
  |> dedupe_input_accumulator_change
  |> list.map(event_phase_and_detail)
  |> group_consecutive_by_phase
}

/// INP with input available is the only case where the runner emits two
/// events for what reads as one fact: InputConsumed(v) immediately
/// followed by AccumulatorChanged(_, v) with that same value — "ACC <-
/// entrée (123)" then "ACC 0 -> 123" right after, both just saying ACC is
/// now 123. Every other ACC-changing instruction (ADD/SUB/LDA) emits only
/// AccumulatorChanged, so this is INP-specific, not a general pattern to
/// generalize away — drop the redundant AccumulatorChanged, keep
/// InputConsumed (it says *why* ACC changed, not just that it did).
fn dedupe_input_accumulator_change(events: List(Event)) -> List(Event) {
  case events {
    [
      event.InputConsumed(v) as consumed,
      event.AccumulatorChanged(_, new),
      ..rest
    ]
      if new == v
    -> [consumed, ..dedupe_input_accumulator_change(rest)]
    [first, ..rest] -> [first, ..dedupe_input_accumulator_change(rest)]
    [] -> []
  }
}

pub type CyclePhase {
  CyclePhase(name: String, details: List(String))
}

// ── Internals ──────────────────────────────────────────────────────

fn build_address_to_line(result: pipeline.ParseResult) -> Dict(Int, Int) {
  load.address_offsets(result.ast)
  |> list.map(fn(pair) {
    let #(addr, offset) = pair
    let pos = span.to_position(result.line_index, offset)
    #(addr, pos.line)
  })
  |> dict.from_list
}

fn invert(d: Dict(Int, Int)) -> Dict(Int, Int) {
  d
  |> dict.to_list
  |> list.map(fn(pair) { #(pair.1, pair.0) })
  |> dict.from_list
}

/// Same addressing as build_address_to_line (same load.address_offsets
/// call), matched back to the actual ast.Line by character offset — cheap
/// and precise, no need for span.to_position/line_index here since offsets
/// are already exact.
fn build_address_to_instruction(
  result: pipeline.ParseResult,
) -> Dict(Int, ast.Instruction) {
  load.address_offsets(result.ast)
  |> list.filter_map(fn(pair) {
    let #(addr, offset) = pair
    case list.find(result.ast.lines, fn(line) { line.span.start == offset }) {
      Error(_) -> Error(Nil)
      Ok(line) ->
        case line.instruction {
          Some(instr) -> Ok(#(addr, instr))
          None -> Error(Nil)
        }
    }
  })
  |> dict.from_list
}

/// #(phase, detail) — kept separate rather than pre-joined into one
/// "Phase : detail" string so group_consecutive_by_phase can merge same-
/// phase entries without string-parsing its own output back apart.
fn event_phase_and_detail(evt: Event) -> #(String, String) {
  case evt {
    event.Fetched(address, raw) -> #(
      "Fetch",
      "lire mem[" <> int.to_string(address) <> "] → " <> int.to_string(raw),
    )
    event.Decoded(instr) -> #("Decode", describe_decoded(instr))
    event.InputConsumed(v) -> #(
      "Execute",
      "ACC ← entrée (" <> int.to_string(v) <> ")",
    )
    event.OutputProduced(v) -> #(
      "Execute",
      "sortie ← ACC (" <> int.to_string(v) <> ")",
    )
    event.MemoryWritten(address, v) -> #(
      "Execute",
      "mem[" <> int.to_string(address) <> "] ← ACC (" <> int.to_string(v) <> ")",
    )
    event.AccumulatorChanged(old, new) -> #(
      "Execute",
      "ACC " <> int.to_string(old) <> " → " <> int.to_string(new),
    )
    event.IndexChanged(old, new) -> #(
      "Execute",
      "X " <> int.to_string(old) <> " → " <> int.to_string(new),
    )
    event.LinkChanged(old, new) -> #(
      "Execute",
      "LR "
        <> int.to_string(old)
        <> " → "
        <> int.to_string(new)
        <> " (adresse de retour)",
    )
    // Un saut est une écriture dans le compteur ordinal, et le dire est tout
    // l'intérêt : « revenir » d'un sous-programme n'est rien d'autre.
    event.StackPointerChanged(old, new) -> #(
      "Execute",
      "SP " <> int.to_string(old) <> " → " <> int.to_string(new),
    )
    event.Jumped(from, to) -> #(
      "Execute",
      "PC "
        <> int.to_string(from)
        <> " → "
        <> int.to_string(to)
        <> " (écriture dans le compteur ordinal)",
    )
    event.Halted -> #("Execute", "HLT")
    event.InputRequested -> #("Execute", "en attente d'une entrée…")
    event.ErrorOccurred(message) -> #("Erreur", message)
  }
}

/// Merges consecutive same-phase pairs into one CyclePhase each — "merges
/// consecutive" rather than "groups all", since phases can legitimately
/// repeat across accumulated events from *different* instructions (a
/// future improvement might show more than one instruction's cycle at
/// once); today last_events only ever holds one instruction's worth, so in
/// practice this always yields at most one Fetch, one Decode, one Execute.
fn group_consecutive_by_phase(
  pairs: List(#(String, String)),
) -> List(CyclePhase) {
  pairs
  |> list.fold([], fn(acc, pair) {
    let #(phase, detail) = pair
    case acc {
      [CyclePhase(name, details), ..rest] if name == phase -> [
        CyclePhase(name, list.append(details, [detail])),
        ..rest
      ]
      _ -> [CyclePhase(phase, [detail]), ..acc]
    }
  })
  |> list.reverse
}

/// Keeps the raw fetched number visible in the Decode line itself (not
/// just on the Fetch line above it), so "STA, adresse 21" reads as *this
/// number, decoded* rather than as a freestanding line of assembly — which
/// otherwise looks exactly like something you could type ("STA 21" is
/// valid LMC), inviting the (false) idea that decode reconstructs source
/// code. It can't: the label "total" the programmer wrote is long gone by
/// this point, only the numeric address 21 survives — decode only ever
/// recovers *that*, via the same arithmetic split lmc_lsp's own
/// instruction.decode uses. The machine word is four digits, O M AA: the
/// opcode is raw / 1000, the addressing mode raw % 1000 / 100 (always 0 for
/// now — indexed and indirect are reserved) and the address raw % 100.
/// instruction.encode(instr) reconstructs the raw number here —
/// the exact inverse of decode, so it's always the same value Fetch showed.
///
/// Also names what decode is *for*: it doesn't do the operation (no
/// memory write, no ACC change happens here — that's Execute's job), it
/// only figures out which of the processor's fixed circuits — the ALU,
/// the memory bus, the program counter — need to be engaged and how, so
/// Execute has something to act on. Spelling that out here is the direct
/// follow-up to the fetch/decode/execute discussion: "decode" can
/// otherwise read as just another arithmetic step alongside Fetch.
fn describe_decoded(instr: instruction.Instruction) -> String {
  let raw = int.to_string(instruction.encode(instr))
  case instr {
    instruction.Inp ->
      raw <> " → INP (" <> circuit_note("lecture d'une entrée") <> ")"
    instruction.Out ->
      raw <> " → OUT (" <> circuit_note("écriture de la sortie") <> ")"
    instruction.Hlt ->
      raw <> " → HLT (" <> circuit_note("arrêt du processeur") <> ")"
    instruction.Add(a, m) ->
      decoded_with_address(raw, "ADD", a, m, circuit_note("une addition"))
    instruction.Sub(a, m) ->
      decoded_with_address(raw, "SUB", a, m, circuit_note("une soustraction"))

    // Un mot comme 5042 peut se lire « LDA 42 » ou « MOV ACC, 42 » : c'est
    // le même mot, il n'y a pas de bonne réponse déductible. On montre la
    // forme générale, avec le raccourci en regard quand il en existe un —
    // l'équivalence est ainsi visible à chaque cycle plutôt qu'à expliquer
    // une fois pour toutes.
    instruction.Load(register, a, m) ->
      decoded_move(
        raw,
        register_name(register),
        memory_text(a, m),
        alias("LDA", register, a, m),
        circuit_note("chargement depuis la mémoire"),
      )
    instruction.Store(register, a, m) ->
      decoded_move(
        raw,
        memory_text(a, m),
        register_name(register),
        alias("STA", register, a, m),
        circuit_note("stockage en mémoire"),
      )
    instruction.Move(destination, source) ->
      decoded_move(
        raw,
        register_name(destination),
        register_name(source),
        "",
        circuit_note("un transfert entre registres"),
      )

    instruction.Push ->
      raw <> " → PSH (" <> circuit_note("empilement de l'accumulateur") <> ")"
    instruction.Pop ->
      raw <> " → POP (" <> circuit_note("dépilement vers l'accumulateur") <> ")"
    instruction.Jsr(a) ->
      decoded_with_address(
        raw,
        "JSR",
        a,
        instruction.Direct,
        circuit_note("un saut avec mémorisation de l'adresse de retour"),
      )
    instruction.Bra(a) ->
      decoded_with_address(
        raw,
        "BRA",
        a,
        instruction.Direct,
        circuit_note("un saut"),
      )
    instruction.Brz(a) ->
      decoded_with_address(
        raw,
        "BRZ",
        a,
        instruction.Direct,
        circuit_note("un saut conditionnel (si ACC = 0)"),
      )
    instruction.Brp(a) ->
      decoded_with_address(
        raw,
        "BRP",
        a,
        instruction.Direct,
        circuit_note("un saut conditionnel (si ACC ≥ 0)"),
      )
  }
}

fn register_name(register: instruction.Register) -> String {
  case register {
    instruction.Acc -> "ACC"
    instruction.X -> "X"
    instruction.Lr -> "LR"
    instruction.Sp -> "SP"
    instruction.Pc -> "PC"
  }
}

/// Notation d'une case en position d'opérande de MOV : « mem[2] », la même
/// que celle déjà employée pour la phase Fetch.
fn memory_text(address: Int, mode: instruction.Addressing) -> String {
  case mode {
    instruction.Direct -> "mem[" <> int.to_string(address) <> "]"
    instruction.Indexed -> "mem[" <> int.to_string(address) <> "+X]"
  }
}

/// Le raccourci historique, quand il en existe un : seules les formes sur
/// l'accumulateur en adressage direct s'écrivaient `LDA` ou `STA`.
fn alias(
  mnemonic: String,
  register: instruction.Register,
  address: Int,
  mode: instruction.Addressing,
) -> String {
  case register, mode {
    instruction.Acc, instruction.Direct ->
      mnemonic <> " " <> int.to_string(address)
    _, _ -> ""
  }
}

fn decoded_move(
  raw: String,
  destination: String,
  source: String,
  alias_text: String,
  note: String,
) -> String {
  let shortcut = case alias_text {
    "" -> ""
    _ -> " (alias " <> alias_text <> ")"
  }
  raw
  <> " → MOV "
  <> destination
  <> ", "
  <> source
  <> shortcut
  <> " ("
  <> note
  <> ")"
}

fn circuit_note(purpose: String) -> String {
  "configuration des circuits du processeur pour " <> purpose
}

fn decoded_with_address(
  raw: String,
  mnemonic: String,
  address: Int,
  mode: instruction.Addressing,
  note: String,
) -> String {
  raw
  <> " → "
  <> mnemonic
  <> ", "
  <> memory_text(address, mode)
  <> " ("
  <> note
  <> ")"
}

fn load_error_message(err: load.LoadError) -> String {
  case err {
    load.ProgramTooLong(count) ->
      "programme trop long : "
      <> int.to_string(count)
      <> " lignes (maximum 100)"
    load.UndefinedLabel(name) -> "label non défini : " <> name
  }
}
