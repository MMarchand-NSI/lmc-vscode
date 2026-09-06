import gleam/list
import gleam/string
import lmc/text/locale
import lmc/text/message
import webview/text

/// Un exemplaire de chaque variante. Écrit à la main plutôt que dérivé :
/// c'est la liste qu'il faut compléter quand une variante s'ajoute, et
/// l'oublier ne coûte qu'une variante non couverte, jamais un faux succès.
const samples: List(text.Text) = [
  text.FetchRead(0, 5003),
  text.FetchIncrement(0, 1),
  text.DecodedPlain(9001, "INP", text.ReadingInput),
  text.DecodedWithOperand(1002, "ADD", "mem[2]", text.Addition),
  text.DecodedMove(5002, "ACC", "mem[2]", "LDA 2", text.LoadFromMemory),
  text.DecodedPlot(9500, 20, text.SendPixel),
  text.InputTaken(9),
  text.OutputSent(9),
  text.PixelSent(1, 2, 3, text.Drawn),
  text.PixelSent(40, 2, 3, text.OffScreen(32, 32)),
  text.PixelSent(1, 2, 9, text.OffPalette(7)),
  text.MemoryWritten(4, 12),
  text.RegisterChanged("ACC", 0, 12),
  text.LinkChanged(0, 3),
  text.Jumped(3, 0),
  text.Halted,
  text.WaitingForInput,
  text.RunnerError(message.IllegalInstruction(9999)),
  text.SourceHasErrors,
  text.ProgramTooLong(102),
  text.UndefinedLabel("ghost"),
  text.NoObjectFile("essai.lmcobj"),
  text.ObjectFileEmpty,
  text.ObjectFileUnreadableLine("douze"),
  text.ObjectFileTooLong(101),
]

/// Les quinze circuits, dans une instruction chacun.
const circuits: List(text.Circuit) = [
  text.ReadingInput,
  text.WritingOutput,
  text.StoppingProcessor,
  text.Addition,
  text.Subtraction,
  text.LoadFromMemory,
  text.StoreToMemory,
  text.RegisterTransfer,
  text.PushRegister,
  text.PopRegister,
  text.SendPixel,
  text.JumpAndLink,
  text.Jump,
  text.JumpIfZero,
  text.JumpIfPositive,
]

pub fn nothing_renders_empty_test() {
  // Ce qu'un `-> ""` posé par mégarde laisserait passer : une ligne vide
  // dans le panneau, qui ne ressemble pas à une faute.
  list.each(samples, fn(sample) {
    assert text.render(sample, locale.French) != ""
    assert text.render(sample, locale.English) != ""
  })
}

pub fn no_circuit_renders_empty_test() {
  list.each(circuits, fn(circuit) {
    let sample = text.DecodedPlain(0, "HLT", circuit)
    assert string.length(text.render(sample, locale.French)) > 12
    assert string.length(text.render(sample, locale.English)) > 12
  })
}

pub fn the_two_languages_really_differ_test() {
  // Sans quoi un `English -> french(text)` posé par mégarde passerait tous
  // les autres tests. On ne compare que les variantes qui portent de la
  // prose : « ACC 0 → 12 » est un fait, pas une phrase, et il s'écrit
  // pareil dans les deux langues — c'est voulu, pas un oubli.
  let prose = [
    text.FetchRead(0, 5003),
    text.FetchIncrement(0, 1),
    text.DecodedPlain(9001, "INP", text.ReadingInput),
    text.InputTaken(9),
    text.OutputSent(9),
    text.PixelSent(1, 2, 3, text.Drawn),
    text.SourceHasErrors,
    text.UndefinedLabel("ghost"),
    text.NoObjectFile("essai.lmcobj"),
  ]
  list.each(prose, fn(sample) {
    assert text.render(sample, locale.French)
      != text.render(sample, locale.English)
  })
}

pub fn a_name_written_by_the_user_crosses_untranslated_test() {
  // « ghost » est le label de quelqu'un : il traverse les deux langues tel
  // quel, sans majuscule ajoutée ni traduction tentée.
  assert string.contains(
    text.render(text.UndefinedLabel("ghost"), locale.French),
    "ghost",
  )
  assert string.contains(
    text.render(text.UndefinedLabel("ghost"), locale.English),
    "ghost",
  )
}

pub fn the_runner_error_is_rendered_in_the_asked_language_test() {
  // L'erreur d'exécution vient de `lmc_lsp` comme valeur : elle doit suivre
  // la même langue que le reste du panneau, pas la sienne.
  let sample = text.RunnerError(message.IllegalInstruction(9999))
  assert text.render(sample, locale.French)
    == locale.render(message.IllegalInstruction(9999), locale.French)
  assert text.render(sample, locale.English)
    == locale.render(message.IllegalInstruction(9999), locale.English)
}

pub fn a_locale_tag_is_read_like_the_server_reads_it_test() {
  // Même fonction que celle du serveur, exprès : deux lectures différentes
  // du même réglage donneraient un panneau et des diagnostics de langues
  // différentes.
  assert text.from_tag("fr-FR") == locale.French
  assert text.from_tag("en") == locale.English
  assert text.from_tag("de-DE") == text.default_locale
}
