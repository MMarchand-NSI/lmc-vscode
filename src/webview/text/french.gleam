//// Le panneau en français.
////
//// Les valeurs sont dans `webview/text/message.gleam`, la répartition dans
//// `webview/text/locale.gleam`. Ce fichier ne fait que rendre.

import gleam/int
import lmc/text/locale
import webview/text/message.{type Circuit, type Label, type Text}

pub fn render(text: Text) -> String {
  case text {
    message.CellRead(address, word) ->
      "lire mem[" <> int.to_string(address) <> "] → " <> int.to_string(word)
    message.FetchIncrement(from, to) ->
      "PC "
      <> int.to_string(from)
      <> " → "
      <> int.to_string(to)
      <> " (incrémenté pendant la lecture, avant le décodage)"

    message.DecodedPlain(word, mnemonic, circuit) ->
      int.to_string(word)
      <> " → "
      <> mnemonic
      <> " ("
      <> circuit_text(circuit)
      <> ")"
    message.DecodedWithOperand(word, mnemonic, operand, circuit) ->
      int.to_string(word)
      <> " → "
      <> mnemonic
      <> ", "
      <> operand
      <> " ("
      <> circuit_text(circuit)
      <> ")"
    message.DecodedMove(word, destination, source, alias, circuit) ->
      int.to_string(word)
      <> " → MOV "
      <> destination
      <> ", "
      <> source
      <> message.shortcut(alias)
      <> " ("
      <> circuit_text(circuit)
      <> ")"
    message.DecodedPlot(word, address, circuit) ->
      int.to_string(word)
      <> " → PLT, "
      <> message.three_cells(address)
      <> " → x, y, couleur ("
      <> circuit_text(circuit)
      <> ")"

    message.InputTaken(value) -> "ACC ← entrée (" <> int.to_string(value) <> ")"
    message.OutputSent(value) -> "sortie ← ACC (" <> int.to_string(value) <> ")"
    message.PixelSent(x, y, colour, outcome) ->
      "écran ← point ("
      <> int.to_string(x)
      <> ", "
      <> int.to_string(y)
      <> "), couleur "
      <> int.to_string(colour)
      <> case outcome {
        message.Drawn -> ""
        message.OffScreen(width, height) ->
          " — hors écran ("
          <> int.to_string(width)
          <> " × "
          <> int.to_string(height)
          <> ") : rien n'est allumé"
        message.OffPalette(highest) ->
          " — hors palette (0 à "
          <> int.to_string(highest)
          <> ") : rien n'est allumé"
      }
    message.MemoryWritten(address, value) ->
      "mem["
      <> int.to_string(address)
      <> "] ← ACC ("
      <> int.to_string(value)
      <> ")"
    message.RegisterChanged(register, from, to) ->
      register <> " " <> int.to_string(from) <> " → " <> int.to_string(to)
    message.LinkChanged(from, to) ->
      "LR "
      <> int.to_string(from)
      <> " → "
      <> int.to_string(to)
      <> " (adresse de retour)"
    message.Jumped(from, to) ->
      "PC "
      <> int.to_string(from)
      <> " → "
      <> int.to_string(to)
      <> " (écriture dans le compteur ordinal)"
    message.Halted -> "HLT"
    message.WaitingForInput -> "en attente d'une entrée…"

    message.RunnerError(reason) -> locale.render(reason, locale.French)
    message.SourceHasErrors ->
      "le programme contient des erreurs — voir les diagnostics dans l'éditeur"
    message.ProgramTooLong(cells) ->
      "programme trop long : " <> int.to_string(cells) <> " cases (maximum 100)"
    message.UndefinedLabel(name) -> "label non défini : " <> name
    message.NoObjectFile(name) ->
      "pas de fichier objet à charger (" <> name <> ") — assemblez d'abord"
    message.ObjectFileEmpty -> "le fichier objet est vide"
    message.ObjectFileUnreadableLine(line) ->
      "le fichier objet contient une ligne illisible : « " <> line <> " »"
    message.ObjectFileTooLong(cells) ->
      "le fichier objet dépasse les 100 cases de la mémoire ("
      <> int.to_string(cells)
      <> ")"
  }
}

fn circuit_text(circuit: Circuit) -> String {
  "configuration des circuits du processeur pour "
  <> case circuit {
    message.ReadingInput -> "lecture d'une entrée"
    message.WritingOutput -> "écriture de la sortie"
    message.StoppingProcessor -> "arrêt du processeur"
    message.Addition -> "une addition"
    message.Subtraction -> "une soustraction"
    message.LoadFromMemory -> "chargement depuis la mémoire"
    message.StoreToMemory -> "stockage en mémoire"
    message.RegisterTransfer -> "un transfert entre registres"
    message.PushRegister -> "empilement d'un registre"
    message.PopRegister -> "dépilement vers un registre"
    message.SendPixel -> "l'envoi d'un point à l'écran"
    message.JumpAndLink -> "un saut avec mémorisation de l'adresse de retour"
    message.Jump -> "un saut"
    message.JumpIfZero -> "un saut conditionnel (si ACC = 0)"
    message.JumpIfPositive -> "un saut conditionnel (si ACC ≥ 0)"
  }
}

pub fn label(label: Label) -> String {
  case label {
    message.PageTitle -> "LMC — Émulateur"
    message.ButtonStep -> "Step"
    message.ButtonRun -> "Run"
    message.ButtonReset -> "Reset"
    message.ButtonAssemble -> "Assembler .lmc"
    message.ButtonLoad -> "Charger .lmcobj en RAM"
    message.ButtonOk -> "OK"
    message.TipAssembleTitle -> "Produire le fichier objet"
    message.TipAssembleBody ->
      "écrit .lmcobj à côté du source : un mot de quatre chiffres par ligne, sans mnémonique ni label, parce que c'est tout ce que le processeur reçoit. Assembler LDA 42 et MOV ACC, 42 donne deux fois la même ligne. N'exécute rien et ne charge rien."
    message.TipLoadTitle -> "Charger en RAM"
    message.TipLoadBody ->
      "relit .lmcobj sur le disque et le dépose en mémoire. C'est bien le fichier qui est chargé : sans lui rien ne s'exécute, et si tu modifies le source sans réassembler, tu charges l'ancien programme. Une vraie chaîne d'outils fait exactement ça."
    message.StatusLabel -> "État"
    message.TipStatusTitle -> "État du processeur"
    message.TipStatusBody ->
      "empty (rien n'est chargé en RAM : assemblez, puis chargez), running (prêt à exécuter), waiting_input (arrêté sur un INP, en attente d'une valeur), halted (arrêté par HLT), error."
    message.HeadingProcessor -> "Processeur"
    message.TipAccTitle -> "Accumulator"
    message.TipAccBody ->
      "l'accumulateur. Toute l'arithmétique et toutes les entrées-sorties passent par lui : ADD, SUB, INP et OUT ne travaillent que sur ACC."
    message.TipPcTitle -> "Program Counter"
    message.TipPcBody ->
      "le compteur ordinal : l'adresse de la prochaine instruction à lire. Écrire dedans, c'est sauter, et c'est tout ce que font BRA, BRZ, BRP et RET. Il est incrémenté dès la phase Fetch, comme sur un vrai processeur — à l'arrêt, il pointe donc déjà après la dernière instruction exécutée."
    message.TipSiTitle -> "Source Index"
    message.TipSiBody ->
      "le registre d'index, nommé comme le SI du x86, où il joue le même rôle. Le suffixe [SI] ajoute son contenu à l'adresse écrite — lst[SI] désigne la case lst + SI, ce qui permet de parcourir un tableau ou une chaîne avec une seule instruction, quel que soit le rang lu."
    message.TipLrTitle -> "Link Register"
    message.TipLrBody ->
      "l'adresse de retour, sous son nom ARM. JSR y écrit l'adresse de l'instruction qui suit l'appel, RET y revient. LR n'en contient qu'une seule : un appel imbriqué l'écrase, et c'est ce qui rend la pile nécessaire."
    message.TipSpTitle -> "Stack Pointer"
    message.TipSpBody ->
      "le pointeur de pile : il désigne la prochaine case libre. La pile descend depuis la case 99 ; PSH y range un registre, POP l'en retire. Écrits sans registre, ils travaillent sur ACC."
    message.HeadingIo -> "Entrées / Sorties"
    message.HeadingInput -> "Entrée (INP)"
    message.InputValueLabel -> "Valeur"
    message.HeadingOutput -> "Sortie (OUT)"
    message.HeadingScreen -> "Écran (PLT)"
    message.TipScreenTitle -> "PLT adr"
    message.TipScreenBody ->
      "allumer un point. L'instruction lit trois cases consécutives à partir de adr : x, y, puis la couleur, un index de palette. Le processeur ne connaît ni la taille de l'écran ni les couleurs : il dit « allume ce point », l'affichage décide du reste. Ici, 32 × 32 points et huit couleurs."
    message.ScreenAria -> "Écran, 32 sur 32 points"
    message.HeadingMemory -> "Mémoire"
    message.MemoryNote ->
      "Une seule mémoire pour le programme et pour les données : c'est le principe de von Neumann, et c'est ce que montrent les marquages ci-dessous."
    message.LegendProgram -> "Programme"
    message.LegendData -> "Données (DAT)"
    message.LegendStack -> "Pile"
    message.LegendFree -> "Libre"
    message.CycleSummary -> "Fetch → Decode → Execute"
    message.CycleHint ->
      "Chaque instruction, quel que soit son mnémonique, passe par les mêmes trois phases. Voici ce qui s'est passé au dernier step :"
  }
}
//
// Des mots machine, des adresses et des noms de registres : rien à
// traduire, et une seule écriture pour que les deux ne divergent pas.
