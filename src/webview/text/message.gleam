//// Tout ce que le panneau affiche, sous forme de valeur.
////
//// Même partage que dans `lmc_lsp` depuis sa v0.8.0 : aucune couche ne
//// fabrique de phrase. `model.gleam` rend des `Text`, et
//// `webview/text/locale.gleam` — le seul module qui connaisse la langue
//// demandée — les rend en chaînes.
//// Une couche qui écrirait du texte choisirait la langue à l'endroit où
//// elle est justement inconnue.
////
//// Effet de bord voulu, et c'est lui qui paie le refactoring : les tests
//// comparent des valeurs (`CellRead(0, 5003)`) et non des tournures de
//// phrase, donc reformuler un message n'en casse plus aucun.
////
//// Ce module ne porte que les **valeurs**. Chaque langue a son fichier
//// (`french.gleam`, `english.gleam`) et `locale.gleam` choisit entre eux :
//// même découpage que `lmc_lsp` depuis sa v0.8.1, et pour la même raison —
//// ajouter une langue devient un fichier de plus et un bras de plus, sans
//// toucher à une traduction existante.
////
//// Le découpage est aussi ce qui rend possible le passage à des catalogues
//// en fichiers de données : il ne restera qu'à remplacer les modules de
//// langue, les types et les appelants ne bougeront pas.

import gleam/int
import gleam/list
import gleam/string
import lmc/runner/load
import lmc/text/message

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
  /// « lire mem[3] → 7 ». La même phrase sert à la lecture de l'instruction
  /// par le Fetch et à celle d'un opérande par l'Execute, parce que c'est le
  /// même fait : une case lue, et ce qu'elle contenait. Seule la phase
  /// diffère, et c'est le panneau qui la porte.
  CellRead(address: Int, word: Int)
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

/// La correspondance entre les clés `data-ui` du HTML et les étiquettes.
/// Sans langue : c'est `locale.labels` qui les rend.
pub fn label_keys() -> List(#(String, Label)) {
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
}

// ── Ce que toutes les langues partagent ─────────────────────────────
//
// Des mots machine, des adresses et des noms de registres : rien à
// traduire, et une seule écriture pour que les langues ne divergent pas
// sur un fait.

pub fn shortcut(alias: String) -> String {
  case alias {
    "" -> ""
    _ -> " (alias " <> alias <> ")"
  }
}

pub fn three_cells(address: Int) -> String {
  ["mem[", "mem[", "mem["]
  |> list.index_map(fn(prefix, offset) {
    prefix <> int.to_string(address + offset) <> "]"
  })
  |> string.join(" ")
}
