//// El panel, en español.
////
//// Los valores están en `webview/text/message.gleam`, el reparto en
//// `webview/text/locale.gleam`. Este archivo solo traduce.
////
//// El vocabulario sigue el del servidor (`lmc/text/spanish.gleam` en
//// `lmc_lsp`): celda, dirección, etiqueta, pila, acumulador, contador de
//// programa. Dos traducciones del mismo término harían leer dos máquinas
//// distintas al alumno.

import gleam/int
import lmc/text/locale
import webview/text/message.{type Circuit, type Label, type Text}

pub fn render(text: Text) -> String {
  case text {
    message.FetchRead(address, word) ->
      "leer mem[" <> int.to_string(address) <> "] → " <> int.to_string(word)
    message.FetchIncrement(from, to) ->
      "PC "
      <> int.to_string(from)
      <> " → "
      <> int.to_string(to)
      <> " (incrementado durante la lectura, antes de la decodificación)"

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
      <> " → x, y, color ("
      <> circuit_text(circuit)
      <> ")"

    message.InputTaken(value) ->
      "ACC ← entrada (" <> int.to_string(value) <> ")"
    message.OutputSent(value) -> "salida ← ACC (" <> int.to_string(value) <> ")"
    message.PixelSent(x, y, colour, outcome) ->
      "pantalla ← punto ("
      <> int.to_string(x)
      <> ", "
      <> int.to_string(y)
      <> "), color "
      <> int.to_string(colour)
      <> case outcome {
        message.Drawn -> ""
        message.OffScreen(width, height) ->
          " — fuera de la pantalla ("
          <> int.to_string(width)
          <> " × "
          <> int.to_string(height)
          <> "): no se enciende nada"
        message.OffPalette(highest) ->
          " — fuera de la paleta (0 a "
          <> int.to_string(highest)
          <> "): no se enciende nada"
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
      <> " (dirección de retorno)"
    message.Jumped(from, to) ->
      "PC "
      <> int.to_string(from)
      <> " → "
      <> int.to_string(to)
      <> " (escritura en el contador de programa)"
    message.Halted -> "HLT"
    message.WaitingForInput -> "esperando una entrada…"

    message.RunnerError(reason) -> locale.render(reason, locale.Spanish)
    message.SourceHasErrors ->
      "el programa tiene errores — mira los diagnósticos en el editor"
    message.ProgramTooLong(cells) ->
      "programa demasiado largo: "
      <> int.to_string(cells)
      <> " celdas (máximo 100)"
    message.UndefinedLabel(name) -> "etiqueta no definida: " <> name
    message.NoObjectFile(name) ->
      "no hay archivo objeto que cargar (" <> name <> ") — ensambla primero"
    message.ObjectFileEmpty -> "el archivo objeto está vacío"
    message.ObjectFileUnreadableLine(line) ->
      "el archivo objeto tiene una línea ilegible: « " <> line <> " »"
    message.ObjectFileTooLong(cells) ->
      "el archivo objeto supera las 100 celdas de la memoria ("
      <> int.to_string(cells)
      <> ")"
  }
}

fn circuit_text(circuit: Circuit) -> String {
  "configuración de los circuitos del procesador para "
  <> case circuit {
    message.ReadingInput -> "leer una entrada"
    message.WritingOutput -> "escribir la salida"
    message.StoppingProcessor -> "detener el procesador"
    message.Addition -> "una suma"
    message.Subtraction -> "una resta"
    message.LoadFromMemory -> "una carga desde la memoria"
    message.StoreToMemory -> "un almacenamiento en memoria"
    message.RegisterTransfer -> "una transferencia entre registros"
    message.PushRegister -> "apilar un registro"
    message.PopRegister -> "desapilar hacia un registro"
    message.SendPixel -> "enviar un punto a la pantalla"
    message.JumpAndLink -> "un salto que guarda la dirección de retorno"
    message.Jump -> "un salto"
    message.JumpIfZero -> "un salto condicional (si ACC = 0)"
    message.JumpIfPositive -> "un salto condicional (si ACC ≥ 0)"
  }
}

pub fn label(label: Label) -> String {
  case label {
    message.PageTitle -> "LMC — Emulador"
    message.ButtonStep -> "Step"
    message.ButtonRun -> "Run"
    message.ButtonReset -> "Reset"
    message.ButtonAssemble -> "Ensamblar .lmc"
    message.ButtonLoad -> "Cargar .lmcobj en RAM"
    message.ButtonOk -> "OK"
    message.TipAssembleTitle -> "Producir el archivo objeto"
    message.TipAssembleBody ->
      "escribe .lmcobj junto al código fuente: una palabra de cuatro dígitos por línea, sin mnemónicos ni etiquetas, porque es todo lo que recibe el procesador. Ensamblar LDA 42 y MOV ACC, 42 da dos veces la misma línea. No ejecuta nada y no carga nada."
    message.TipLoadTitle -> "Cargar en RAM"
    message.TipLoadBody ->
      "vuelve a leer .lmcobj del disco y lo deposita en memoria. Es realmente el archivo lo que se carga: sin él no se ejecuta nada, y si modificas el código fuente sin volver a ensamblar, cargas el programa anterior. Una cadena de herramientas real hace exactamente esto."
    message.StatusLabel -> "Estado"
    message.TipStatusTitle -> "Estado del procesador"
    message.TipStatusBody ->
      "empty (no hay nada en RAM: ensambla y luego carga), running (listo para ejecutar), waiting_input (detenido en un INP, esperando un valor), halted (detenido por HLT), error."
    message.HeadingProcessor -> "Procesador"
    message.TipAccTitle -> "Acumulador"
    message.TipAccBody ->
      "toda la aritmética y todas las entradas y salidas pasan por él: ADD, SUB, INP y OUT solo trabajan sobre ACC."
    message.TipPcTitle -> "Contador de programa"
    message.TipPcBody ->
      "la dirección de la próxima instrucción que se va a leer. Escribir en él es saltar, y es todo lo que hacen BRA, BRZ, BRP y RET. Se incrementa ya en la fase Fetch, como en un procesador real — al detenerse apunta por tanto más allá de la última instrucción ejecutada."
    message.TipSiTitle -> "Registro de índice"
    message.TipSiBody ->
      "llamado SI como en el x86, donde cumple el mismo papel. El sufijo [SI] añade su contenido a la dirección escrita — lst[SI] designa la celda lst + SI, lo que permite recorrer un array o una cadena con una sola instrucción, sea cual sea la posición leída."
    message.TipLrTitle -> "Dirección de retorno"
    message.TipLrBody ->
      "bajo su nombre de ARM, LR. JSR escribe en él la dirección de la instrucción siguiente a la llamada, y RET vuelve allí. LR solo guarda una: una llamada anidada la sobrescribe, y eso es lo que hace necesaria la pila."
    message.TipSpTitle -> "Puntero de pila"
    message.TipSpBody ->
      "señala la próxima celda libre. La pila baja desde la celda 99; PSH guarda allí un registro, POP lo retira. Escritos sin registro, ambos trabajan sobre ACC."
    message.HeadingIo -> "Entradas / Salidas"
    message.HeadingInput -> "Entrada (INP)"
    message.InputValueLabel -> "Valor"
    message.HeadingOutput -> "Salida (OUT)"
    message.HeadingScreen -> "Pantalla (PLT)"
    message.TipScreenTitle -> "PLT dir"
    message.TipScreenBody ->
      "encender un punto. La instrucción lee tres celdas consecutivas a partir de dir: x, y, y después el color, un índice de paleta. El procesador no conoce ni el tamaño de la pantalla ni los colores: dice « enciende este punto », y la pantalla decide el resto. Aquí, 32 × 32 puntos y ocho colores."
    message.ScreenAria -> "Pantalla, 32 por 32 puntos"
    message.HeadingMemory -> "Memoria"
    message.MemoryNote ->
      "Una sola memoria para el programa y para los datos: es el principio de von Neumann, y es lo que muestran las marcas de abajo."
    message.LegendProgram -> "Programa"
    message.LegendData -> "Datos (DAT)"
    message.LegendStack -> "Pila"
    message.LegendFree -> "Libre"
    message.CycleSummary -> "Fetch → Decode → Execute"
    message.CycleHint ->
      "Cada instrucción, sea cual sea su mnemónico, pasa por las mismas tres fases. Esto es lo que ocurrió en el último step:"
  }
}
