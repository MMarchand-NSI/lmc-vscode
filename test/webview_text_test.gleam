import gleam/list
import gleam/string
import lmc/text/locale as server
import lmc/text/message
import webview/text/locale as language
import webview/text/message as text

/// Un exemplaire de chaque variante. Écrit à la main plutôt que dérivé :
/// c'est la liste qu'il faut compléter quand une variante s'ajoute, et
/// l'oublier ne coûte qu'une variante non couverte, jamais un faux succès.
const samples: List(text.Text) = [
  text.CellRead(0, 5003),
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
    assert language.render(sample, server.French) != ""
    assert language.render(sample, server.English) != ""
  })
}

pub fn no_circuit_renders_empty_test() {
  list.each(circuits, fn(circuit) {
    let sample = text.DecodedPlain(0, "HLT", circuit)
    assert string.length(language.render(sample, server.French)) > 12
    assert string.length(language.render(sample, server.English)) > 12
  })
}

pub fn the_two_languages_really_differ_test() {
  // Sans quoi un `English -> french(text)` posé par mégarde passerait tous
  // les autres tests. On ne compare que les variantes qui portent de la
  // prose : « ACC 0 → 12 » est un fait, pas une phrase, et il s'écrit
  // pareil dans les deux langues — c'est voulu, pas un oubli.
  let prose = [
    text.CellRead(0, 5003),
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
    assert language.render(sample, server.French)
      != language.render(sample, server.English)
  })
}

pub fn a_name_written_by_the_user_crosses_untranslated_test() {
  // « ghost » est le label de quelqu'un : il traverse les deux langues tel
  // quel, sans majuscule ajoutée ni traduction tentée.
  assert string.contains(
    language.render(text.UndefinedLabel("ghost"), server.French),
    "ghost",
  )
  assert string.contains(
    language.render(text.UndefinedLabel("ghost"), server.English),
    "ghost",
  )
}

pub fn the_runner_error_is_rendered_in_the_asked_language_test() {
  // L'erreur d'exécution vient de `lmc_lsp` comme valeur : elle doit suivre
  // la même langue que le reste du panneau, pas la sienne.
  let sample = text.RunnerError(message.IllegalInstruction(9999))
  assert language.render(sample, server.French)
    == server.render(message.IllegalInstruction(9999), server.French)
  assert language.render(sample, server.English)
    == server.render(message.IllegalInstruction(9999), server.English)
}

pub fn a_locale_tag_is_read_like_the_server_reads_it_test() {
  // Même fonction que celle du serveur, exprès : deux lectures différentes
  // du même réglage donneraient un panneau et des diagnostics de langues
  // différentes.
  assert language.from_tag("fr-FR") == server.French
  assert language.from_tag("en") == server.English
  // L'allemand n'est pas parlé : c'est le *repli* qui répond, l'anglais.
  // Le défaut du panneau vaut la même chose depuis que `lmc.locale` est
  // passé à `auto`, mais les deux restent deux questions : le repli suit le
  // serveur, le défaut suit ce que l'hôte va envoyer. Ce test les nomme
  // séparément pour que changer l'un n'emporte pas l'autre en silence.
  assert language.from_tag("de-DE") == language.fallback_locale
  assert language.fallback_locale == server.English
  assert language.default_locale == server.English
}

/// Les trois langues que le serveur connaît. Ajouter un fichier de langue
/// sans l'ajouter ici ne coûte rien ; l'inverse, si : la liste force chaque
/// contrôle ci-dessous à passer par toutes.
const languages: List(server.Locale) = [
  server.French,
  server.English,
  server.Spanish,
  server.Japanese,
  server.Korean,
]

pub fn every_language_renders_every_message_test() {
  // Aujourd'hui l'espagnol retombe sur l'anglais ; le jour où il aura son
  // fichier, ce test le couvrira sans être touché.
  list.each(languages, fn(lang) {
    list.each(samples, fn(sample) {
      assert language.render(sample, lang) != ""
    })
  })
}

pub fn every_language_fills_every_label_test() {
  // Le décor entier, pour chaque langue : autant d'étiquettes que de clés,
  // et pas une vide. C'est ce qui manquerait le plus discrètement en
  // ajoutant une langue — une infobulle vide ne ressemble pas à une faute.
  list.each(languages, fn(lang) {
    let labels = language.labels(lang)
    assert list.length(labels) == list.length(text.label_keys())
    list.each(labels, fn(pair) {
      assert pair.1 != ""
    })
  })
}

pub fn every_language_has_a_tag_test() {
  // L'attribut `lang` du document : deux langues ne peuvent pas partager la
  // même étiquette, et aucune ne peut être vide.
  let tags = list.map(languages, language.tag)
  assert list.length(list.unique(tags)) == list.length(languages)
  list.each(tags, fn(tag) {
    assert tag != ""
  })
}
