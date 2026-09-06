//// Tout ce que le panneau affiche, sous forme de valeur.
////
//// Même partage que dans `lmc_lsp` depuis sa v0.8.0 : aucune couche ne
//// fabrique de phrase. `model.gleam` rend des `Text`, et `render.gleam` —
//// le seul module qui connaisse la langue demandée — les rend en chaînes.
//// Une couche qui écrirait du texte choisirait la langue à l'endroit où
//// elle est justement inconnue.
////
//// Effet de bord voulu, et c'est lui qui paie le refactoring : les tests
//// comparent des valeurs (`FetchRead(0, 5003)`) et non des tournures de
//// phrase, donc reformuler un message n'en casse plus aucun.
////
//// La `Locale` n'est pas redéfinie ici : c'est celle de `lmc_lsp`, pour
//// que le panneau et les diagnostics ne puissent pas diverger, et pour que
//// `message.render` s'appelle avec la même valeur sans conversion.

import gleam/int
import gleam/list
import gleam/string
import lmc/runner/load
import lmc/text/locale.{English, French, Spanish}
import lmc/text/message

/// La `Locale` de `lmc_lsp`, re-exportée : le panneau et les diagnostics
/// doivent répondre au même réglage avec la même valeur, et un second type
/// ici les laisserait diverger.
pub type Locale =
  locale.Locale

/// La langue par défaut, celle de `lmc_lsp` : le français. Un panneau muet
/// est plus probablement une classe qu'un anglophone.
pub const default_locale = locale.default_locale

/// `fr`, `fr-FR`, `en-GB`… La bibliothèque du serveur fait déjà ce travail,
/// et le refaire ici laisserait les deux répondre différemment au même
/// réglage.
pub fn from_tag(tag: String) -> Locale {
  locale.from_tag(tag)
}

/// Les trois phases du cycle, plus la ligne d'erreur qui prend leur place
/// quand la machine s'arrête sur une faute. Les trois premières ne se
/// traduisent pas : « Fetch », « Decode » et « Execute » sont les termes
/// que le cours emploie, en français comme ailleurs.
pub type Phase {
  Fetch
  Decode
  Execute
  Failure
}

/// Ce que la phase Decode dit du circuit engagé. Une valeur par usage, et
/// non une chaîne libre : c'est la seule façon que le compilateur exige
/// une traduction pour chacun.
pub type Circuit {
  ReadingInput
  WritingOutput
  StoppingProcessor
  Addition
  Subtraction
  LoadFromMemory
  StoreToMemory
  RegisterTransfer
  PushRegister
  PopRegister
  SendPixel
  JumpAndLink
  Jump
  JumpIfZero
  JumpIfPositive
}

/// Ce qu'il est advenu du point demandé par `PLT`. L'écran a une taille et
/// une palette que le processeur ignore ; quand le point tombe dehors, on
/// le dit plutôt que de laisser l'écran vide sans explication.
pub type Plotted {
  Drawn
  OffScreen(width: Int, height: Int)
  OffPalette(highest: Int)
}

pub type Text {
  // ── Le cycle ──────────────────────────────────────────────────
  FetchRead(address: Int, word: Int)
  /// Le compteur ordinal avance pendant la lecture, avant le décodage.
  /// C'est ce qui explique qu'une machine arrêtée affiche un `PC` d'un cran
  /// au-delà de l'instruction qui l'a arrêtée.
  FetchIncrement(from: Int, to: Int)

  /// Les quatre formes de la ligne Decode. `word`, `mnemonic` et les
  /// opérandes ne se traduisent pas — ce sont des mots machine, des
  /// mnémoniques et des noms de registres — mais leur assemblage, si.
  DecodedPlain(word: Int, mnemonic: String, circuit: Circuit)
  DecodedWithOperand(
    word: Int,
    mnemonic: String,
    operand: String,
    circuit: Circuit,
  )
  /// `alias` est vide quand l'instruction n'a pas de raccourci historique.
  DecodedMove(
    word: Int,
    destination: String,
    source: String,
    alias: String,
    circuit: Circuit,
  )
  DecodedPlot(word: Int, address: Int, circuit: Circuit)

  InputTaken(value: Int)
  OutputSent(value: Int)
  PixelSent(x: Int, y: Int, colour: Int, outcome: Plotted)
  MemoryWritten(address: Int, value: Int)
  /// `ACC 0 → 12`, `SI`, `SP` : le nom du registre ne se traduit pas, la
  /// ligne n'a donc rien à traduire non plus, mais elle passe par ici pour
  /// que tout le panneau ait la même forme.
  RegisterChanged(register: String, from: Int, to: Int)
  LinkChanged(from: Int, to: Int)
  Jumped(from: Int, to: Int)
  Halted
  WaitingForInput

  // ── Les fautes ────────────────────────────────────────────────
  /// L'erreur d'exécution vient du runner comme valeur : on la rend avec
  /// la même langue, sans la recopier ici.
  RunnerError(reason: message.Message)
  /// L'assemblage a échoué sur des diagnostics : le détail est déjà dans
  /// l'éditeur, inutile de le redire.
  SourceHasErrors
  ProgramTooLong(cells: Int)
  UndefinedLabel(name: String)

  // ── Le fichier objet, tel qu'il revient du disque ─────────────
  /// L'hôte n'a pas trouvé le fichier : il envoie son nom, pas une phrase.
  /// Un shell qui rédigerait le message choisirait la langue là où elle
  /// n'est pas connue.
  NoObjectFile(name: String)
  ObjectFileEmpty
  ObjectFileUnreadableLine(line: String)
  ObjectFileTooLong(cells: Int)
}

/// Seule la quatrième dépend de la langue : les trois autres sont les
/// termes du cours, employés tels quels en français.
pub fn phase_label(phase: Phase, language: Locale) -> String {
  case phase, language {
    Fetch, _ -> "Fetch"
    Decode, _ -> "Decode"
    Execute, _ -> "Execute"
    Failure, French -> "Erreur"
    Failure, English | Failure, Spanish -> "Error"
  }
}

/// L'espagnol est arrivé côté serveur en v0.8.1 et le panneau ne le parle
/// pas encore : il retombe sur l'anglais, message par message, plutôt que de
/// rendre du vide. C'est un état de transition, pas une décision — voir la
/// liste ouverte de CLAUDE.md, « externaliser les catalogues ».
pub fn render(text: Text, language: Locale) -> String {
  case language {
    French -> french(text)
    English | Spanish -> english(text)
  }
}

/// L'échec du chargeur, tel qu'il se dira à l'écran.
///
/// `ProgramTooLong` est **défensif** : `check_length` (semantic/lints.gleam)
/// applique la même règle, `ast.cell_count`, et signale le débordement avant
/// que l'assemblage n'appelle le chargeur, si bien que c'est `SourceHasErrors`
/// qui s'affiche. La branche existe parce que `load.load` rend un `Result`
/// qu'il faut traiter, pas parce qu'on l'a vue.
pub fn load_error(err: load.LoadError) -> Text {
  case err {
    // « cases » et non « lignes » : ce que le chargeur compte, ce sont les
    // mots posés en mémoire. Un seul `lst: DAT` de cent-et-une valeurs
    // tient sur une ligne et déborde quand même. Le champ s'appelait
    // `line_count` et disait déjà des cases ; renommé `cell_count` en
    // v0.5.0, il compile pareil puisque le filtrage est positionnel.
    load.ProgramTooLong(cell_count) -> ProgramTooLong(cell_count)
    load.UndefinedLabel(name) -> UndefinedLabel(name)
  }
}

// ── Français ────────────────────────────────────────────────────────

fn french(text: Text) -> String {
  case text {
    FetchRead(address, word) ->
      "lire mem[" <> int.to_string(address) <> "] → " <> int.to_string(word)
    FetchIncrement(from, to) ->
      "PC "
      <> int.to_string(from)
      <> " → "
      <> int.to_string(to)
      <> " (incrémenté pendant la lecture, avant le décodage)"

    DecodedPlain(word, mnemonic, circuit) ->
      int.to_string(word)
      <> " → "
      <> mnemonic
      <> " ("
      <> french_circuit(circuit)
      <> ")"
    DecodedWithOperand(word, mnemonic, operand, circuit) ->
      int.to_string(word)
      <> " → "
      <> mnemonic
      <> ", "
      <> operand
      <> " ("
      <> french_circuit(circuit)
      <> ")"
    DecodedMove(word, destination, source, alias, circuit) ->
      int.to_string(word)
      <> " → MOV "
      <> destination
      <> ", "
      <> source
      <> shortcut(alias)
      <> " ("
      <> french_circuit(circuit)
      <> ")"
    DecodedPlot(word, address, circuit) ->
      int.to_string(word)
      <> " → PLT, "
      <> three_cells(address)
      <> " → x, y, couleur ("
      <> french_circuit(circuit)
      <> ")"

    InputTaken(value) -> "ACC ← entrée (" <> int.to_string(value) <> ")"
    OutputSent(value) -> "sortie ← ACC (" <> int.to_string(value) <> ")"
    PixelSent(x, y, colour, outcome) ->
      "écran ← point ("
      <> int.to_string(x)
      <> ", "
      <> int.to_string(y)
      <> "), couleur "
      <> int.to_string(colour)
      <> case outcome {
        Drawn -> ""
        OffScreen(width, height) ->
          " — hors écran ("
          <> int.to_string(width)
          <> " × "
          <> int.to_string(height)
          <> ") : rien n'est allumé"
        OffPalette(highest) ->
          " — hors palette (0 à "
          <> int.to_string(highest)
          <> ") : rien n'est allumé"
      }
    MemoryWritten(address, value) ->
      "mem["
      <> int.to_string(address)
      <> "] ← ACC ("
      <> int.to_string(value)
      <> ")"
    RegisterChanged(register, from, to) ->
      register <> " " <> int.to_string(from) <> " → " <> int.to_string(to)
    LinkChanged(from, to) ->
      "LR "
      <> int.to_string(from)
      <> " → "
      <> int.to_string(to)
      <> " (adresse de retour)"
    Jumped(from, to) ->
      "PC "
      <> int.to_string(from)
      <> " → "
      <> int.to_string(to)
      <> " (écriture dans le compteur ordinal)"
    Halted -> "HLT"
    WaitingForInput -> "en attente d'une entrée…"

    RunnerError(reason) -> locale.render(reason, French)
    SourceHasErrors ->
      "le programme contient des erreurs — voir les diagnostics dans l'éditeur"
    ProgramTooLong(cells) ->
      "programme trop long : " <> int.to_string(cells) <> " cases (maximum 100)"
    UndefinedLabel(name) -> "label non défini : " <> name
    NoObjectFile(name) ->
      "pas de fichier objet à charger (" <> name <> ") — assemblez d'abord"
    ObjectFileEmpty -> "le fichier objet est vide"
    ObjectFileUnreadableLine(line) ->
      "le fichier objet contient une ligne illisible : « " <> line <> " »"
    ObjectFileTooLong(cells) ->
      "le fichier objet dépasse les 100 cases de la mémoire ("
      <> int.to_string(cells)
      <> ")"
  }
}

fn french_circuit(circuit: Circuit) -> String {
  "configuration des circuits du processeur pour "
  <> case circuit {
    ReadingInput -> "lecture d'une entrée"
    WritingOutput -> "écriture de la sortie"
    StoppingProcessor -> "arrêt du processeur"
    Addition -> "une addition"
    Subtraction -> "une soustraction"
    LoadFromMemory -> "chargement depuis la mémoire"
    StoreToMemory -> "stockage en mémoire"
    RegisterTransfer -> "un transfert entre registres"
    PushRegister -> "empilement d'un registre"
    PopRegister -> "dépilement vers un registre"
    SendPixel -> "l'envoi d'un point à l'écran"
    JumpAndLink -> "un saut avec mémorisation de l'adresse de retour"
    Jump -> "un saut"
    JumpIfZero -> "un saut conditionnel (si ACC = 0)"
    JumpIfPositive -> "un saut conditionnel (si ACC ≥ 0)"
  }
}

// ── English ─────────────────────────────────────────────────────────
//
// Pas un calque : les tournures qui portent une intention pédagogique la
// gardent, comme le fait `lmc_lsp` pour ses diagnostics.

fn english(text: Text) -> String {
  case text {
    FetchRead(address, word) ->
      "read mem[" <> int.to_string(address) <> "] → " <> int.to_string(word)
    FetchIncrement(from, to) ->
      "PC "
      <> int.to_string(from)
      <> " → "
      <> int.to_string(to)
      <> " (incremented during the read, before decoding)"

    DecodedPlain(word, mnemonic, circuit) ->
      int.to_string(word)
      <> " → "
      <> mnemonic
      <> " ("
      <> english_circuit(circuit)
      <> ")"
    DecodedWithOperand(word, mnemonic, operand, circuit) ->
      int.to_string(word)
      <> " → "
      <> mnemonic
      <> ", "
      <> operand
      <> " ("
      <> english_circuit(circuit)
      <> ")"
    DecodedMove(word, destination, source, alias, circuit) ->
      int.to_string(word)
      <> " → MOV "
      <> destination
      <> ", "
      <> source
      <> shortcut(alias)
      <> " ("
      <> english_circuit(circuit)
      <> ")"
    DecodedPlot(word, address, circuit) ->
      int.to_string(word)
      <> " → PLT, "
      <> three_cells(address)
      <> " → x, y, colour ("
      <> english_circuit(circuit)
      <> ")"

    InputTaken(value) -> "ACC ← input (" <> int.to_string(value) <> ")"
    OutputSent(value) -> "output ← ACC (" <> int.to_string(value) <> ")"
    PixelSent(x, y, colour, outcome) ->
      "screen ← pixel ("
      <> int.to_string(x)
      <> ", "
      <> int.to_string(y)
      <> "), colour "
      <> int.to_string(colour)
      <> case outcome {
        Drawn -> ""
        OffScreen(width, height) ->
          " — off screen ("
          <> int.to_string(width)
          <> " × "
          <> int.to_string(height)
          <> "): nothing is lit"
        OffPalette(highest) ->
          " — outside the palette (0 to "
          <> int.to_string(highest)
          <> "): nothing is lit"
      }
    MemoryWritten(address, value) ->
      "mem["
      <> int.to_string(address)
      <> "] ← ACC ("
      <> int.to_string(value)
      <> ")"
    RegisterChanged(register, from, to) ->
      register <> " " <> int.to_string(from) <> " → " <> int.to_string(to)
    LinkChanged(from, to) ->
      "LR "
      <> int.to_string(from)
      <> " → "
      <> int.to_string(to)
      <> " (return address)"
    Jumped(from, to) ->
      "PC "
      <> int.to_string(from)
      <> " → "
      <> int.to_string(to)
      <> " (writing to the program counter)"
    Halted -> "HLT"
    WaitingForInput -> "waiting for an input…"

    RunnerError(reason) -> locale.render(reason, English)
    SourceHasErrors ->
      "the program has errors — see the diagnostics in the editor"
    ProgramTooLong(cells) ->
      "program too long: " <> int.to_string(cells) <> " cells (maximum 100)"
    UndefinedLabel(name) -> "undefined label: " <> name
    NoObjectFile(name) ->
      "no object file to load (" <> name <> ") — assemble first"
    ObjectFileEmpty -> "the object file is empty"
    ObjectFileUnreadableLine(line) ->
      "the object file has a line that cannot be read: `" <> line <> "`"
    ObjectFileTooLong(cells) ->
      "the object file is larger than the 100 cells of memory ("
      <> int.to_string(cells)
      <> ")"
  }
}

fn english_circuit(circuit: Circuit) -> String {
  "setting up the processor's circuits for "
  <> case circuit {
    ReadingInput -> "reading an input"
    WritingOutput -> "writing the output"
    StoppingProcessor -> "stopping the processor"
    Addition -> "an addition"
    Subtraction -> "a subtraction"
    LoadFromMemory -> "a load from memory"
    StoreToMemory -> "a store to memory"
    RegisterTransfer -> "a register-to-register transfer"
    PushRegister -> "pushing a register"
    PopRegister -> "popping into a register"
    SendPixel -> "sending a pixel to the screen"
    JumpAndLink -> "a jump that remembers the return address"
    Jump -> "a jump"
    JumpIfZero -> "a conditional jump (if ACC = 0)"
    JumpIfPositive -> "a conditional jump (if ACC ≥ 0)"
  }
}

// ── Ce que les deux langues partagent ───────────────────────────────
//
// Des mots machine, des adresses et des noms de registres : rien à
// traduire, et une seule écriture pour que les deux ne divergent pas.

fn shortcut(alias: String) -> String {
  case alias {
    "" -> ""
    _ -> " (alias " <> alias <> ")"
  }
}

fn three_cells(address: Int) -> String {
  ["mem[", "mem[", "mem["]
  |> list.index_map(fn(prefix, offset) {
    prefix <> int.to_string(address + offset) <> "]"
  })
  |> string.join(" ")
}

// ── Le texte fixe du panneau ────────────────────────────────────────
//
// Boutons, titres, légendes et infobulles vivaient dans `index.html`, donc
// dans une seule langue et hors de portée du compilateur. Ils sont ici pour
// la même raison que le reste : un `case` exhaustif exige une traduction
// pour chacun, et `index.html` ne porte plus que des `data-ui` vides que le
// rendu remplit.

pub type Label {
  PageTitle
  ButtonStep
  ButtonRun
  ButtonReset
  ButtonAssemble
  ButtonLoad
  ButtonOk
  TipAssembleTitle
  TipAssembleBody
  TipLoadTitle
  TipLoadBody
  StatusLabel
  TipStatusTitle
  TipStatusBody
  HeadingProcessor
  TipAccTitle
  TipAccBody
  TipPcTitle
  TipPcBody
  TipSiTitle
  TipSiBody
  TipLrTitle
  TipLrBody
  TipSpTitle
  TipSpBody
  HeadingIo
  HeadingInput
  InputValueLabel
  HeadingOutput
  HeadingScreen
  TipScreenTitle
  TipScreenBody
  ScreenAria
  HeadingMemory
  MemoryNote
  LegendProgram
  LegendData
  LegendStack
  LegendFree
  CycleSummary
  CycleHint
}

/// Toutes les étiquettes, prêtes à être posées dans le DOM.
pub fn labels(locale: Locale) -> List(#(String, String)) {
  [
    #("pageTitle", PageTitle),
    #("btnStep", ButtonStep),
    #("btnRun", ButtonRun),
    #("btnReset", ButtonReset),
    #("btnAssemble", ButtonAssemble),
    #("btnLoad", ButtonLoad),
    #("btnOk", ButtonOk),
    #("tipAssembleTitle", TipAssembleTitle),
    #("tipAssembleBody", TipAssembleBody),
    #("tipLoadTitle", TipLoadTitle),
    #("tipLoadBody", TipLoadBody),
    #("statusLabel", StatusLabel),
    #("tipStatusTitle", TipStatusTitle),
    #("tipStatusBody", TipStatusBody),
    #("headingProcessor", HeadingProcessor),
    #("tipAccTitle", TipAccTitle),
    #("tipAccBody", TipAccBody),
    #("tipPcTitle", TipPcTitle),
    #("tipPcBody", TipPcBody),
    #("tipSiTitle", TipSiTitle),
    #("tipSiBody", TipSiBody),
    #("tipLrTitle", TipLrTitle),
    #("tipLrBody", TipLrBody),
    #("tipSpTitle", TipSpTitle),
    #("tipSpBody", TipSpBody),
    #("headingIo", HeadingIo),
    #("headingInput", HeadingInput),
    #("inputValueLabel", InputValueLabel),
    #("headingOutput", HeadingOutput),
    #("headingScreen", HeadingScreen),
    #("tipScreenTitle", TipScreenTitle),
    #("tipScreenBody", TipScreenBody),
    #("screenAria", ScreenAria),
    #("headingMemory", HeadingMemory),
    #("memoryNote", MemoryNote),
    #("legendProgram", LegendProgram),
    #("legendData", LegendData),
    #("legendStack", LegendStack),
    #("legendFree", LegendFree),
    #("cycleSummary", CycleSummary),
    #("cycleHint", CycleHint),
  ]
  |> list.map(fn(pair) { #(pair.0, label(pair.1, locale)) })
}

pub fn label(label: Label, language: Locale) -> String {
  case language {
    French -> french_label(label)
    English | Spanish -> english_label(label)
  }
}

fn french_label(label: Label) -> String {
  case label {
    PageTitle -> "LMC — Émulateur"
    ButtonStep -> "Step"
    ButtonRun -> "Run"
    ButtonReset -> "Reset"
    ButtonAssemble -> "Assembler .lmc"
    ButtonLoad -> "Charger .lmcobj en RAM"
    ButtonOk -> "OK"
    TipAssembleTitle -> "Produire le fichier objet"
    TipAssembleBody ->
      "écrit .lmcobj à côté du source : un mot de quatre chiffres par ligne, sans mnémonique ni label, parce que c'est tout ce que le processeur reçoit. Assembler LDA 42 et MOV ACC, 42 donne deux fois la même ligne. N'exécute rien et ne charge rien."
    TipLoadTitle -> "Charger en RAM"
    TipLoadBody ->
      "relit .lmcobj sur le disque et le dépose en mémoire. C'est bien le fichier qui est chargé : sans lui rien ne s'exécute, et si tu modifies le source sans réassembler, tu charges l'ancien programme. Une vraie chaîne d'outils fait exactement ça."
    StatusLabel -> "État"
    TipStatusTitle -> "État du processeur"
    TipStatusBody ->
      "vide (rien n'est chargé en RAM : assemblez, puis chargez), running (prêt à exécuter), waiting_input (arrêté sur un INP, en attente d'une valeur), halted (arrêté par HLT), error."
    HeadingProcessor -> "Processeur"
    TipAccTitle -> "Accumulator"
    TipAccBody ->
      "l'accumulateur. Toute l'arithmétique et toutes les entrées-sorties passent par lui : ADD, SUB, INP et OUT ne travaillent que sur ACC."
    TipPcTitle -> "Program Counter"
    TipPcBody ->
      "le compteur ordinal : l'adresse de la prochaine instruction à lire. Écrire dedans, c'est sauter, et c'est tout ce que font BRA, BRZ, BRP et RET. Il est incrémenté dès la phase Fetch, comme sur un vrai processeur — à l'arrêt, il pointe donc déjà après la dernière instruction exécutée."
    TipSiTitle -> "Source Index"
    TipSiBody ->
      "le registre d'index, nommé comme le SI du x86, où il joue le même rôle. Le suffixe [SI] ajoute son contenu à l'adresse écrite — lst[SI] désigne la case lst + SI, ce qui permet de parcourir un tableau ou une chaîne avec une seule instruction, quel que soit le rang lu."
    TipLrTitle -> "Link Register"
    TipLrBody ->
      "l'adresse de retour, sous son nom ARM. JSR y écrit l'adresse de l'instruction qui suit l'appel, RET y revient. LR n'en contient qu'une seule : un appel imbriqué l'écrase, et c'est ce qui rend la pile nécessaire."
    TipSpTitle -> "Stack Pointer"
    TipSpBody ->
      "le pointeur de pile : il désigne la prochaine case libre. La pile descend depuis la case 99 ; PSH y range un registre, POP l'en retire. Écrits sans registre, ils travaillent sur ACC."
    HeadingIo -> "Entrées / Sorties"
    HeadingInput -> "Entrée (INP)"
    InputValueLabel -> "Valeur"
    HeadingOutput -> "Sortie (OUT)"
    HeadingScreen -> "Écran (PLT)"
    TipScreenTitle -> "PLT adr"
    TipScreenBody ->
      "allumer un point. L'instruction lit trois cases consécutives à partir de adr : x, y, puis la couleur, un index de palette. Le processeur ne connaît ni la taille de l'écran ni les couleurs : il dit « allume ce point », l'affichage décide du reste. Ici, 32 × 32 points et huit couleurs."
    ScreenAria -> "Écran, 32 sur 32 points"
    HeadingMemory -> "Mémoire"
    MemoryNote ->
      "Une seule mémoire pour le programme et pour les données : c'est le principe de von Neumann, et c'est ce que montrent les marquages ci-dessous."
    LegendProgram -> "Programme"
    LegendData -> "Données (DAT)"
    LegendStack -> "Pile"
    LegendFree -> "Libre"
    CycleSummary -> "Fetch → Decode → Execute"
    CycleHint ->
      "Chaque instruction, quel que soit son mnémonique, passe par les mêmes trois phases. Voici ce qui s'est passé au dernier step :"
  }
}

fn english_label(label: Label) -> String {
  case label {
    PageTitle -> "LMC — Emulator"
    ButtonStep -> "Step"
    ButtonRun -> "Run"
    ButtonReset -> "Reset"
    ButtonAssemble -> "Assemble .lmc"
    ButtonLoad -> "Load .lmcobj into RAM"
    ButtonOk -> "OK"
    TipAssembleTitle -> "Produce the object file"
    TipAssembleBody ->
      "writes .lmcobj next to the source: one four-digit word per line, no mnemonics and no labels, because that is all the processor ever receives. Assembling LDA 42 and MOV ACC, 42 gives the same line twice. Runs nothing and loads nothing."
    TipLoadTitle -> "Load into RAM"
    TipLoadBody ->
      "reads .lmcobj back off the disk and lays it out in memory. It really is the file that gets loaded: without it nothing runs, and if you edit the source without reassembling, you load the old program. A real toolchain behaves exactly like this."
    StatusLabel -> "Status"
    TipStatusTitle -> "Processor status"
    TipStatusBody ->
      "vide (nothing is in RAM: assemble, then load), running (ready to execute), waiting_input (stopped on an INP, waiting for a value), halted (stopped by HLT), error."
    HeadingProcessor -> "Processor"
    TipAccTitle -> "Accumulator"
    TipAccBody ->
      "the accumulator. All arithmetic and all input/output go through it: ADD, SUB, INP and OUT work on ACC and nothing else."
    TipPcTitle -> "Program Counter"
    TipPcBody ->
      "the address of the next instruction to read. Writing to it is jumping, and that is all BRA, BRZ, BRP and RET do. It is incremented during the Fetch phase, as on a real processor — so a stopped machine already points past the last instruction executed."
    TipSiTitle -> "Source Index"
    TipSiBody ->
      "the index register, named after the x86's SI, where it plays the same role. The [SI] suffix adds its contents to the address written — lst[SI] means the cell lst + SI, which is what lets one instruction walk an array or a string whatever the position read."
    TipLrTitle -> "Link Register"
    TipLrBody ->
      "the return address, under its ARM name. JSR writes the address of the instruction after the call into it, RET goes back there. LR holds exactly one: a nested call overwrites it, and that is what makes the stack necessary."
    TipSpTitle -> "Stack Pointer"
    TipSpBody ->
      "points at the next free cell. The stack grows down from cell 99; PSH stores a register there, POP takes it back. Written without a register, both work on ACC."
    HeadingIo -> "Input / Output"
    HeadingInput -> "Input (INP)"
    InputValueLabel -> "Value"
    HeadingOutput -> "Output (OUT)"
    HeadingScreen -> "Screen (PLT)"
    TipScreenTitle -> "PLT addr"
    TipScreenBody ->
      "light a pixel. The instruction reads three consecutive cells starting at addr: x, y, then the colour, a palette index. The processor knows neither the size of the screen nor the colours: it says `light this pixel`, the display decides the rest. Here, 32 × 32 pixels and eight colours."
    ScreenAria -> "Screen, 32 by 32 pixels"
    HeadingMemory -> "Memory"
    MemoryNote ->
      "One memory for the program and for the data: that is von Neumann's principle, and that is what the markings below show."
    LegendProgram -> "Program"
    LegendData -> "Data (DAT)"
    LegendStack -> "Stack"
    LegendFree -> "Free"
    CycleSummary -> "Fetch → Decode → Execute"
    CycleHint ->
      "Every instruction, whatever its mnemonic, goes through the same three phases. Here is what happened on the last step:"
  }
}
