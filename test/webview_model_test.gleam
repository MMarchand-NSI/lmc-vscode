import gleam/list
import gleam/option.{None, Some}
import gleam/string
import lmc/runner/inspect
import lmc/runner/state
import webview/model
import webview/text/message as text

/// Assemble puis charge en RAM, comme le feraient les boutons Assembler
/// puis Charger. Passe par le vrai aller-retour : le texte du fichier objet
/// est produit puis relu, donc ce raccourci exerce aussi ce chemin-là.
fn loaded(source: String) -> model.Model {
  let m = model.init(source)
  let assert Some(code) = model.object_code(m)
  model.load_object_code(m, code)
}

// ── Assemblage ────────────────────────────────────────────────────

pub fn init_assembles_but_does_not_load_test() {
  // Assembler n'est pas charger : après l'ouverture, la RAM est vide et il
  // y a seulement de quoi produire un fichier objet.
  let m = model.init("INP\nOUT\nHLT\n")
  assert m.assembly_error == None
  assert m.assembled != None
  assert m.machine == None
  assert model.program_length(m) == 0
}

pub fn loading_fills_the_ram_test() {
  let m = loaded("INP\nOUT\nHLT\n")
  let assert Some(machine) = m.machine
  assert machine.status == state.Running
  assert machine.program_counter == 0
  assert model.program_length(m) == 3
}

pub fn init_program_with_syntax_error_test() {
  let m = model.init("XXX\n")
  assert m.assembled == None
  assert m.assembly_error != None
}

pub fn init_program_with_undefined_label_test() {
  // Erreur de résolution, pas de syntaxe — même chemin "diagnostics non
  // vides" côté pipeline, donc même message générique côté webview (les
  // diagnostics détaillés vivent déjà dans l'éditeur via le LSP).
  let m = model.init("LDA ghost\nHLT\n")
  assert m.assembled == None
  assert m.assembly_error != None
}

pub fn a_program_too_long_does_not_assemble_test() {
  // Cent-et-une valeurs sur une seule ligne : ce qui déborde, ce sont les
  // cases mémoire, pas les lignes du fichier. Le message vient de la couche
  // sémantique, qui applique la même règle (`ast.cell_count`) que le
  // chargeur ; c'est pourquoi la branche `ProgramTooLong` de
  // `load_error_message` n'est jamais atteinte par ce chemin.
  let source = "        HLT\nlst:    DAT " <> string.repeat("1, ", 100) <> "1\n"
  let m = model.init(source)

  assert m.assembled == None
  assert m.assembly_error == Some(text.SourceHasErrors)
}

pub fn a_step_reports_the_cells_it_touched_test() {
  // Le pas à pas fait pulser en rose la case touchée. Le modèle ne dit que
  // ce que le runner a rapporté : la lecture de l'instruction elle-même, et
  // l'écriture d'un STA.
  let m =
    loaded(
      "        LDA n\n        STA m\n        HLT\nn:      DAT 7\nm:      DAT\n",
    )
  let first = model.step(m)
  // Deux lectures : l'instruction elle-même, puis la donnée que LDA va
  // chercher. La seconde n'existait pas avant lmc_lsp v0.8.3.
  assert model.memory_accesses(first) == [#(0, model.Read), #(3, model.Read)]

  let second = model.step(first)
  assert model.memory_accesses(second)
    == [#(1, model.Read), #(4, model.Written)]
}

pub fn an_operand_read_is_reported_test() {
  // `LDA n` lit mem[2], et cette lecture apparaît depuis lmc_lsp v0.8.3.
  // Ce test disait l'absence, il dit maintenant la présence — sans que rien
  // n'ait été reconstruit ici : c'est le runner qui la rapporte, lui seul
  // connaissant l'adresse effective d'un accès indexé.
  let m =
    loaded("        LDA n\n        HLT\nn:      DAT 7\n")
    |> model.step
  assert model.memory_accesses(m) == [#(0, model.Read), #(2, model.Read)]
}

pub fn set_source_if_changed_is_a_noop_when_unchanged_test() {
  // Regression: webviewPanel.ts resends the source on every editor
  // refocus (onDidChangeActiveTextEditor), not only on real edits —
  // clicking back into the source editor while stepping through a
  // program must not reset PC/ACC/output just because the (unchanged)
  // source arrived again.
  let m =
    loaded("INP\nOUT\nHLT\n")
    |> model.run_to_halt
    |> model.provide_input(9)
    |> model.step
  let assert Some(before) = m.machine

  let m2 = model.set_source_if_changed(m, "INP\nOUT\nHLT\n")
  let assert Some(after) = m2.machine
  assert after.program_counter == before.program_counter
  assert after.accumulator == before.accumulator
}

pub fn editing_the_source_reassembles_without_touching_the_ram_test() {
  // Le point de tout le découpage : modifier le source réassemble, mais la
  // machine continue de tourner sur ce qui a été chargé. Éditer un .c ne
  // change pas le binaire déjà en mémoire.
  let m =
    loaded("INP\nOUT\nHLT\n")
    |> model.run_to_halt
    |> model.provide_input(9)
    |> model.step
  let assert Some(before) = m.machine

  let m2 = model.set_source_if_changed(m, "INP\nHLT\n")
  let assert Some(machine) = m2.machine
  assert machine.program_counter == before.program_counter
  assert machine.accumulator == before.accumulator
  // Le nouvel assemblage, lui, a bien changé : deux cases au lieu de trois.
  assert model.object_code(m2) == Some("9001\n0000\n")
}

// ── Step / run ────────────────────────────────────────────────────

pub fn step_advances_one_instruction_test() {
  let m = loaded("INP\nOUT\nHLT\n") |> model.step
  let assert Some(machine) = m.machine
  assert machine.status == state.WaitingForInput
}

pub fn step_before_loading_is_a_no_op_test() {
  // Il faut charger avant d'exécuter : sans RAM, Step ne peut rien faire.
  let m = model.init("INP\nOUT\nHLT\n") |> model.step
  assert m.machine == None
}

pub fn run_to_halt_runs_until_input_needed_test() {
  let m = loaded("INP\nOUT\nHLT\n") |> model.run_to_halt
  let assert Some(machine) = m.machine
  assert machine.status == state.WaitingForInput
}

pub fn provide_input_then_run_halts_test() {
  let m =
    loaded("INP\nOUT\nHLT\n")
    |> model.run_to_halt
    |> model.provide_input(42)
    |> model.run_to_halt
  let assert Some(machine) = m.machine
  assert machine.status == state.Halted
  assert inspect.output_buffer(machine) == [42]
}

pub fn resume_after_input_keeps_running_when_run_triggered_the_wait_test() {
  // Regression: the input form's submit handler used to always complete
  // just the one paused instruction (Step-like), regardless of whether Run
  // or Step led to the wait — so clicking Run and then answering the INP
  // prompt looked like Step, stopping right after instead of continuing to
  // the next halt. run_to_halt marks the wait as Run-originated
  // (run_after_input); resume_after_input must honour that and keep going
  // past the INP it paused on, all the way to HLT here.
  let m =
    loaded("INP\nOUT\nHLT\n")
    |> model.run_to_halt
    |> model.resume_after_input(9)
  let assert Some(machine) = m.machine
  assert machine.status == state.Halted
  assert inspect.output_buffer(machine) == [9]
}

pub fn resume_after_input_completes_only_the_instruction_when_step_triggered_the_wait_test() {
  // Mirror image: a Step that pauses on INP must still behave like Step
  // once input arrives — complete only that instruction, not run to
  // completion.
  let m =
    loaded("INP\nOUT\nHLT\n")
    |> model.step
    |> model.resume_after_input(9)
  let assert Some(machine) = m.machine
  assert machine.status == state.Running
  assert machine.program_counter == 1
  assert machine.accumulator == 9
  assert inspect.output_buffer(machine) == []
}

pub fn reset_reruns_from_scratch_test() {
  // reset() reloads to the freshly-assembled state — it does not
  // auto-run up to the first INP the way a fresh model.init would look
  // right after (both land on the same thing: Running, PC at the start).
  let m =
    loaded("INP\nOUT\nHLT\n")
    |> model.run_to_halt
    |> model.provide_input(1)
    |> model.run_to_halt
    |> model.reset
  let assert Some(machine) = m.machine
  assert machine.status == state.Running
  assert machine.program_counter == 0
  assert inspect.output_buffer(machine) == []
}

// ── Correspondance adresse <-> ligne ──────────────────────────────

pub fn current_line_tracks_program_counter_test() {
  let m = loaded("INP\nOUT\nHLT\n")
  // PC=0 avant la première instruction -> ligne 0
  assert model.current_line(m) == Some(0)

  let m2 = model.step(m)
  // Après INP (en attente d'input, PC pas encore avancé) -> toujours ligne 0
  assert model.current_line(m2) == Some(0)
}

pub fn current_line_advances_after_input_provided_test() {
  let m =
    loaded("INP\nOUT\nHLT\n")
    |> model.run_to_halt
    |> model.provide_input(5)
    |> model.step
  // INP consommé -> PC=1 -> ligne 1 (OUT)
  assert model.current_line(m) == Some(1)
}

pub fn line_for_address_and_cursor_address_are_inverse_test() {
  let m = loaded("INP\nOUT\nHLT\n")
  assert model.line_for_address(m, 1) == Some(1)

  let m2 = model.set_cursor_line(m, Some(1))
  assert model.cursor_address(m2) == Some(1)
}

pub fn cursor_line_on_blank_line_has_no_address_test() {
  let m =
    model.init("INP\n\nOUT\nHLT\n")
    |> model.set_cursor_line(Some(1))
  // ligne 1 = ligne vide, pas d'instruction dessus
  assert model.cursor_address(m) == None
}

pub fn labels_dont_shift_the_address_line_map_test() {
  // Un label décale la colonne mais pas les adresses — vérifie que le
  // mapping suit bien les *lignes*, pas un compteur d'instructions naïf.
  let m = loaded("start: INP\nOUT\nHLT\n")
  assert model.line_for_address(m, 0) == Some(0)
  assert model.line_for_address(m, 1) == Some(1)
  assert model.line_for_address(m, 2) == Some(2)
}

// ── Légende d'instruction / longueur du programme ─────────────────

pub fn program_length_counts_instructions_test() {
  // Lignes vides comprises dans le source, pas dans le compte — même
  // logique que load.address_offsets côté lmc_lsp.
  let m = loaded("INP\n\nOUT\nHLT\n")
  assert model.program_length(m) == 3
}

pub fn program_length_is_zero_until_something_is_loaded_test() {
  // program_length décrit la RAM, pas le source : c'est lui qui dit à la
  // grille où s'arrête le programme chargé. Sans chargement, rien.
  let m = model.init("INP\nOUT\nHLT\n")
  assert model.program_length(m) == 0
  assert model.program_length(loaded("INP\nOUT\nHLT\n")) == 3
}

// ── Cycle Fetch → Decode → Execute ────────────────────────────────

pub fn no_events_before_any_step_test() {
  let m = loaded("INP\nOUT\nHLT\n")
  assert model.last_cycle(m) == []
}

pub fn step_produces_one_entry_per_phase_test() {
  // OUT (nullaire) : le cas le plus simple pour vérifier les 3 phases sans
  // le cas particulier de INP qui bloque avant l'Execute.
  let m =
    loaded("INP\nOUT\nHLT\n")
    |> model.run_to_halt
    |> model.provide_input(9)
    |> model.step
    |> model.step
  let cycle = model.last_cycle(m)
  let assert [fetch, decode, execute] = cycle
  assert fetch.phase == text.Fetch
  assert decode.phase == text.Decode
  assert execute.phase == text.Execute
  assert execute.details == [text.OutputSent(9)]
}

pub fn fetch_shows_the_program_counter_moving_test() {
  // Lire le mot et avancer le compteur ordinal sont deux actes de la phase
  // Fetch, et le second manquait. C'est pourtant lui qui explique le décalage
  // que le panneau des registres affiche sans le justifier : une machine
  // arrêtée montre un PC déjà passé à l'instruction suivante.
  let m = loaded("LDA n\nADD n\nHLT\nn: DAT 5\n") |> model.step
  let assert [fetch, _decode, _execute] = model.last_cycle(m)
  assert fetch.details == [text.CellRead(0, 5003), text.FetchIncrement(0, 1)]
}

pub fn the_program_counter_line_follows_the_instruction_test() {
  // Deuxième instruction : la ligne suit l'adresse lue, elle n'est pas figée
  // sur 0 → 1.
  let m = loaded("LDA n\nADD n\nHLT\nn: DAT 5\n") |> model.step |> model.step
  let assert [fetch, ..] = model.last_cycle(m)
  assert list.contains(fetch.details, text.FetchIncrement(1, 2))
}

pub fn the_program_counter_line_stays_inside_the_fetch_phase_test() {
  // Deux détails sous Fetch, pas une quatrième phase : le cycle reste
  // Fetch → Decode → Execute, ce qui est tout l'intérêt du panneau.
  let m = loaded("LDA n\nADD n\nHLT\nn: DAT 5\n") |> model.step
  let cycle = model.last_cycle(m)
  assert list.map(cycle, fn(p) { p.phase })
    == [text.Fetch, text.Decode, text.Execute]
}

pub fn the_index_register_is_named_si_test() {
  // Deuxième renommage de ce registre : X devenu IX en v0.4.0, IX devenu
  // SI en v0.7.0. Le nom
  // apparaît dans deux phrases différentes du panneau du cycle, décodage et
  // exécution, et rien ne les reliait au type `Register` de `lmc_lsp` : un
  // renommage pouvait donc n'être fait qu'à moitié sans que rien n'échoue.
  let m =
    loaded("        MOV SI, n\n        HLT\nn:      DAT 5\n")
    |> model.step
  let assert [_fetch, decode, execute] = model.last_cycle(m)

  assert decode.details
    == [text.DecodedMove(5102, "SI", "mem[2]", "", text.LoadFromMemory)]
  // La lecture précède le changement de registre, et se dit comme celle du
  // Fetch : c'est le même fait, dans une autre phase.
  assert execute.details
    == [text.CellRead(2, 5), text.RegisterChanged("SI", 0, 5)]
}

pub fn decode_shows_the_raw_number_not_just_the_mnemonic_test() {
  // "STA, adresse 21" alone would read exactly like a line of source code
  // (STA 21 is valid LMC) and invite the false idea that decode
  // reconstructs it — the raw number decode actually works from (902 for
  // OUT here) must stay visible, tying the derived mnemonic back to *a
  // number*, not to the student's original ("total") label, long gone by
  // this point.
  let m =
    loaded("INP\nOUT\nHLT\n")
    |> model.run_to_halt
    |> model.provide_input(9)
    |> model.step
    |> model.step
  let assert [_fetch, decode, _execute] = model.last_cycle(m)
  assert decode.details == [text.DecodedPlain(9002, "OUT", text.WritingOutput)]
}

pub fn decode_shows_the_raw_number_with_an_address_test() {
  // "total" est à l'adresse 2 (ligne 2) — l'assembleur a résolu le label
  // vers ce numéro, le nom "total" lui-même n'existe plus dans le mot
  // mémoire assemblé (3002 = 3·1000 + 2, soit opcode 3, mode direct,
  // adresse 02). Le décodage montre la forme générale MOV avec, en regard,
  // le raccourci STA qui s'assemble vers ce même mot.
  let m = loaded("STA total\nHLT\ntotal: DAT 0\n") |> model.step
  let assert [_fetch, decode, _execute] = model.last_cycle(m)
  assert decode.details
    == [text.DecodedMove(3002, "mem[2]", "ACC", "STA 2", text.StoreToMemory)]
}

pub fn events_accumulate_across_an_input_pause_test() {
  // The whole point: Fetch and Decode only happen once, right before the
  // machine discovers it needs input and pauses mid-Execute — the events
  // from *before* the pause must not be lost once input is provided and
  // Execute actually finishes, or the panel would misleadingly look like
  // this instruction skipped straight to Execute.
  let m =
    loaded("INP\nOUT\nHLT\n")
    |> model.run_to_halt
    |> model.provide_input(9)
    |> model.step
  let cycle = model.last_cycle(m)
  let assert [fetch, decode, execute] = cycle
  assert fetch.phase == text.Fetch
  assert decode.phase == text.Decode
  // Une seule entrée "Execute", pas trois — c'est tout l'enjeu : ses
  // sous-actions restent groupées dans .details, pas éclatées en plusieurs
  // phases qui donneraient l'impression que Fetch→Decode→Execute se répète.
  // Seulement 2 sous-actions, pas 3 : "ACC 0 → 9" est déduplié, il ne dit
  // rien de plus que "ACC ← entrée (9)" (voir dedupe_input_accumulator_change).
  assert execute.phase == text.Execute
  assert execute.details == [text.WaitingForInput, text.InputTaken(9)]
}

pub fn add_accumulator_change_is_not_deduped_test() {
  // Le dédoublonnage est spécifique à INP (seul cas où deux événements
  // décrivent le même fait) — ADD n'émet qu'un seul AccumulatorChanged, il
  // ne doit surtout pas être filtré par erreur.
  let m =
    loaded("LDA n\nADD n\nHLT\nn: DAT 5\n")
    |> model.step
    |> model.step
  let assert [_fetch, _decode, execute] = model.last_cycle(m)
  assert execute.details
    == [text.CellRead(3, 5), text.RegisterChanged("ACC", 5, 10)]
}

pub fn events_clear_on_reset_test() {
  let m =
    loaded("INP\nOUT\nHLT\n")
    |> model.run_to_halt
    |> model.provide_input(9)
    |> model.step
    |> model.reset
  assert model.last_cycle(m) == []
}

// ── Zone de données (DAT) ─────────────────────────────────────────

pub fn data_addresses_marks_only_the_dat_cells_test() {
  // "n" est en case 3, après les trois instructions.
  let m = loaded("INP\nSTA n\nHLT\nn: DAT 0\n")
  assert model.data_addresses(m) == [3]
}

pub fn data_addresses_covers_every_cell_of_a_multi_value_dat_test() {
  // Une ligne, trois cases : le marquage suit les cases, pas les lignes.
  let m = loaded("HLT\nlst: DAT 12, 4, 86\n")
  assert model.data_addresses(m) == [1, 2, 3]
}

pub fn data_addresses_includes_a_strings_terminating_zero_test() {
  // « LMC » fait quatre cases : 76, 77, 67, puis le zéro terminal, qui est
  // une case réservée par le DAT comme les autres.
  let m = loaded("HLT\nmot: DAT \"LMC\"\n")
  assert model.data_addresses(m) == [1, 2, 3, 4]
}

pub fn data_addresses_is_not_a_region_but_a_set_of_cells_test() {
  // Un DAT peut se trouver au milieu du code, et le marquage doit le
  // suivre case par case — ce n'est pas « tout ce qui est après la
  // dernière instruction ». Ici les données sont en 2 et en 5.
  let m = loaded("LDA a\nOUT\na: DAT 42\nLDA b\nOUT\nb: DAT 7\nHLT\n")
  assert model.data_addresses(m) == [2, 5]
}

pub fn data_addresses_empty_when_the_program_has_no_dat_test() {
  let m = loaded("INP\nOUT\nHLT\n")
  assert model.data_addresses(m) == []
}

// ── Surbrillance à l'arrêt ────────────────────────────────────────

pub fn halted_highlights_the_hlt_not_the_cell_after_it_test() {
  // Le HLT est en case 2. Le PC vaut 3 à l'arrêt — c'est correct, et c'est
  // ce que fait un vrai processeur, qui incrémente pendant la phase Fetch.
  // Mais la case *courante* est celle qui a arrêté la machine, pas la
  // suivante.
  let m =
    loaded("INP\nOUT\nHLT\n")
    |> model.run_to_halt
    |> model.provide_input(42)
    |> model.run_to_halt
  let assert Some(machine) = m.machine
  assert machine.status == state.Halted
  assert machine.program_counter == 3
  assert model.current_address(m) == Some(2)
}

pub fn halted_does_not_highlight_the_first_dat_test() {
  // Le cas qui a fait remonter le défaut : les données suivent le HLT, donc
  // la case d'après est un DAT. L'émulateur annonçait une machine arrêtée
  // sur le point d'exécuter ses propres données, et l'éditeur décorait la
  // ligne du DAT.
  let source = "LDA n\nOUT\nHLT\nn: DAT 7\n"
  let m = loaded(source) |> model.run_to_halt
  let assert Some(machine) = m.machine
  assert machine.program_counter == 3
  assert model.data_addresses(m) == [3]
  assert model.current_address(m) == Some(2)
  assert model.current_line(m) == Some(2)
}

pub fn halting_on_a_dat_cell_still_points_at_that_cell_test() {
  // Cas inverse, et c'est pourquoi « pc - 1 » est le bon correctif plutôt
  // que « ne rien surligner » : ici le flux d'exécution tombe *dans* les
  // données. 42 vaut moins de 1000, donc opcode 0, donc HLT (LANGAGE.md).
  // La case qui a arrêté la machine est bien la case de données, et c'est
  // exactement ce qu'il faut montrer.
  let m = loaded("LDA a\nOUT\na: DAT 42\nHLT\n") |> model.run_to_halt
  let assert Some(machine) = m.machine
  assert machine.status == state.Halted
  assert model.data_addresses(m) == [2]
  assert model.current_address(m) == Some(2)
}

pub fn running_still_points_at_the_instruction_about_to_execute_test() {
  // Non-régression : hors des états d'arrêt, PC n'a pas encore servi au
  // fetch, donc aucune correction.
  let m = loaded("INP\nOUT\nHLT\n")
  assert model.current_address(m) == Some(0)
}

// ── Fichier objet ─────────────────────────────────────────────────

pub fn object_code_is_one_four_digit_word_per_cell_test() {
  let m = model.init("INP\nOUT\nHLT\n")
  assert model.object_code(m) == Some("9001\n9002\n0000\n")
}

pub fn object_code_covers_every_cell_of_a_multi_value_dat_test() {
  // Une ligne source, trois lignes de fichier objet : l'objet compte en
  // cases, pas en lignes.
  let m = model.init("HLT\nlst: DAT 12, 4, 86\n")
  assert model.object_code(m) == Some("0000\n0012\n0004\n0086\n")
}

pub fn object_code_stops_at_the_end_of_the_program_test() {
  // Les 100 cases de la mémoire existent, mais l'objet ne contient que le
  // programme : le reste n'a pas été assemblé, il a seulement été mis à 0.
  let m = model.init("INP\nOUT\nHLT\n")
  let assert Some(code) = model.object_code(m)
  assert string.split(code, "\n") |> list.length == 4
}

pub fn lda_and_mov_acc_produce_the_same_object_file_test() {
  // La promesse affichée dans l'infobulle du bouton « Assembler », et la
  // raison pour laquelle LANGAGE.md dit que LDA est un *raccourci* de MOV
  // et pas une seconde instruction : le fichier objet est identique.
  let with_lda = model.init("LDA n\nHLT\nn: DAT 42\n")
  let with_mov = model.init("MOV ACC, n\nHLT\nn: DAT 42\n")
  assert model.object_code(with_lda) == model.object_code(with_mov)
  assert model.object_code(with_lda) == Some("5002\n0000\n0042\n")
}

pub fn object_code_none_when_the_program_does_not_assemble_test() {
  // Un assembleur qui rencontre une erreur ne produit pas d'objet.
  let m = model.init("LDA ghost\nHLT\n")
  assert m.machine == None
  assert model.object_code(m) == None
}

// ── Écran (PLT) ───────────────────────────────────────────────────

/// Un point unique, allumé puis la machine s'arrête. `pt` est en case 2,
/// donc `PLT pt` s'assemble en 9202.
const one_point = "PLT pt\nHLT\npt: DAT 20, 25, 7\n"

pub fn nothing_is_lit_before_anything_runs_test() {
  // La RAM est chargée, rien n'a été exécuté : l'écran est vide. Ce n'est
  // pas le programme qui allume des points, c'est son exécution.
  let m = loaded(one_point)
  assert model.screen_points(m) == []
}

pub fn plt_lights_one_point_test() {
  let m = loaded(one_point) |> model.step
  assert model.screen_points(m) == [#(20, 25, 7)]
}

pub fn points_accumulate_across_steps_test() {
  // L'écran garde ce qui a été allumé : le runner, lui, émet l'événement et
  // l'oublie. C'est ce qui distingue l'écran de `last_events`.
  let m = loaded("PLT a\nPLT b\nHLT\na: DAT 1, 2, 3\nb: DAT 4, 5, 6\n")
  let m = m |> model.step |> model.step
  assert model.screen_points(m) == [#(1, 2, 3), #(4, 5, 6)]
}

pub fn colour_zero_erases_a_point_test() {
  // 0 est le fond : rallumer un point en 0, c'est l'éteindre, et aucune
  // instruction supplémentaire n'est nécessaire pour effacer.
  let source =
    "PLT a\nLDA zero\nSTA c\nPLT a\nHLT\n"
    <> "a: DAT 3, 4\nc: DAT 5\nzero: DAT 0\n"
  // `a` est en case 5, donc a+2 est `c` : c'est bien la couleur du même
  // point qu'on remet à 0. Le voir allumé d'abord est indispensable — sans
  // cette première assertion, le test passerait aussi si `PLT` n'allumait
  // jamais rien.
  let lit = loaded(source) |> model.step
  assert model.screen_points(lit) == [#(3, 4, 5)]
  assert model.screen_points(model.run_to_halt(lit)) == []
}

pub fn a_point_outside_the_screen_is_not_lit_test() {
  // Le processeur ne connaît pas la taille de l'écran et n'a donc rien fait
  // de mal ; c'est l'affichage qui ne suit pas. Il le dit, plutôt que de
  // laisser un écran vide sans explication.
  let m = loaded("PLT pt\nHLT\npt: DAT 40, 3, 5\n") |> model.step
  assert model.screen_points(m) == []
  assert m
    |> model.last_cycle
    |> list.any(fn(phase) {
      list.any(phase.details, fn(detail) {
        case detail {
          text.PixelSent(_, _, _, text.OffScreen(_, _)) -> True
          _ -> False
        }
      })
    })
}

pub fn a_colour_outside_the_palette_is_not_lit_test() {
  let m = loaded("PLT pt\nHLT\npt: DAT 3, 4, 9\n") |> model.step
  assert model.screen_points(m) == []
  assert m
    |> model.last_cycle
    |> list.any(fn(phase) {
      list.any(phase.details, fn(detail) {
        case detail {
          text.PixelSent(_, _, _, text.OffPalette(_)) -> True
          _ -> False
        }
      })
    })
}

pub fn reset_clears_the_screen_test() {
  // Sans ça, la seconde exécution dessinerait par-dessus les points de la
  // première, et un écran ne se lirait plus.
  let m = loaded(one_point) |> model.step
  assert model.screen_points(m) == [#(20, 25, 7)]
  assert model.screen_points(model.reset(m)) == []
}

pub fn loading_clears_the_screen_test() {
  let m = loaded(one_point) |> model.step
  let assert Some(code) = model.object_code(m)
  assert model.screen_points(model.load_object_code(m, code)) == []
}

pub fn points_are_returned_in_screen_order_test() {
  // L'ordre est celui du balayage — ligne par ligne, de gauche à droite —
  // et pas celui dans lequel le programme les a allumés : l'écran est un
  // état, pas un journal.
  let m =
    loaded("PLT a\nPLT b\nHLT\na: DAT 9, 9, 1\nb: DAT 0, 0, 2\n")
    |> model.run_to_halt
  assert model.screen_points(m) == [#(0, 0, 2), #(9, 9, 1)]
}

pub fn a_point_survives_an_input_pause_test() {
  // Une entrée coupe l'exécution en deux appels, et `last_events`
  // s'accumule de l'un à l'autre. L'écran, lui, doit rester intact : ni
  // perdu ni remis à zéro par la reprise. (Il ne peut pas être *dupliqué* :
  // les points sont un dictionnaire, réallumer le même point au même
  // endroit ne se voit pas — ce n'est donc pas ce que ce test montre.)
  let m =
    loaded("PLT pt\nINP\nHLT\npt: DAT 2, 3, 4\n")
    |> model.run_to_halt
    |> model.resume_after_input(7)
  assert model.screen_points(m) == [#(2, 3, 4)]
}
