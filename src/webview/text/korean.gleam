//// 패널의 한국어.
////
//// 값은 `webview/text/message.gleam`에, 분배는
//// `webview/text/locale.gleam`에 있습니다. 이 파일은 표시만 합니다.
////
//// 용어는 서버(`lmc_lsp`의 `lmc/text/korean.gleam`)를 따릅니다 — 셀, 주소,
//// 레이블, 스택, 누산기, 프로그램 카운터. 같은 용어를 두 가지로 번역하면
//// 학생은 서로 다른 기계를 읽게 됩니다.
////
//// **원어민의 검토를 받지 않았습니다.** 수업 자료인 만큼 검토가 필요합니다.

import gleam/int
import lmc/text/locale
import webview/text/message.{type Circuit, type Label, type Text}

pub fn render(text: Text) -> String {
  case text {
    message.FetchRead(address, word) ->
      "mem[" <> int.to_string(address) <> "] 읽기 → " <> int.to_string(word)
    message.FetchIncrement(from, to) ->
      "PC "
      <> int.to_string(from)
      <> " → "
      <> int.to_string(to)
      <> " (읽는 동안, 해독 전에 증가)"

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
      <> " → x, y, 색 ("
      <> circuit_text(circuit)
      <> ")"

    message.InputTaken(value) -> "ACC ← 입력 (" <> int.to_string(value) <> ")"
    message.OutputSent(value) -> "출력 ← ACC (" <> int.to_string(value) <> ")"
    message.PixelSent(x, y, colour, outcome) ->
      "화면 ← 점 ("
      <> int.to_string(x)
      <> ", "
      <> int.to_string(y)
      <> "), 색 "
      <> int.to_string(colour)
      <> case outcome {
        message.Drawn -> ""
        message.OffScreen(width, height) ->
          " — 화면 밖 ("
          <> int.to_string(width)
          <> " × "
          <> int.to_string(height)
          <> "): 아무것도 켜지지 않습니다"
        message.OffPalette(highest) ->
          " — 팔레트 밖 (0부터 " <> int.to_string(highest) <> "까지): 아무것도 켜지지 않습니다"
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
      "LR " <> int.to_string(from) <> " → " <> int.to_string(to) <> " (복귀 주소)"
    message.Jumped(from, to) ->
      "PC "
      <> int.to_string(from)
      <> " → "
      <> int.to_string(to)
      <> " (프로그램 카운터에 쓰기)"
    message.Halted -> "HLT"
    message.WaitingForInput -> "입력을 기다리는 중…"

    message.RunnerError(reason) -> locale.render(reason, locale.Korean)
    message.SourceHasErrors -> "프로그램에 오류가 있습니다 — 편집기의 진단을 보세요"
    message.ProgramTooLong(cells) ->
      "프로그램이 너무 깁니다: " <> int.to_string(cells) <> " 셀 (최대 100)"
    message.UndefinedLabel(name) -> "정의되지 않은 레이블: " <> name
    message.NoObjectFile(name) ->
      "불러올 오브젝트 파일이 없습니다 (" <> name <> ") — 먼저 어셈블하세요"
    message.ObjectFileEmpty -> "오브젝트 파일이 비어 있습니다"
    message.ObjectFileUnreadableLine(line) ->
      "오브젝트 파일에 읽을 수 없는 줄이 있습니다: 「" <> line <> "」"
    message.ObjectFileTooLong(cells) ->
      "오브젝트 파일이 메모리의 100 셀을 넘습니다 (" <> int.to_string(cells) <> ")"
  }
}

fn circuit_text(circuit: Circuit) -> String {
  "프로세서 회로 설정: "
  <> case circuit {
    message.ReadingInput -> "입력 읽기"
    message.WritingOutput -> "출력 쓰기"
    message.StoppingProcessor -> "프로세서 정지"
    message.Addition -> "덧셈"
    message.Subtraction -> "뺄셈"
    message.LoadFromMemory -> "메모리에서 불러오기"
    message.StoreToMemory -> "메모리에 저장하기"
    message.RegisterTransfer -> "레지스터 간 전송"
    message.PushRegister -> "레지스터 넣기"
    message.PopRegister -> "레지스터로 꺼내기"
    message.SendPixel -> "화면으로 점 보내기"
    message.JumpAndLink -> "복귀 주소를 기억하는 분기"
    message.Jump -> "분기"
    message.JumpIfZero -> "조건 분기 (ACC = 0일 때)"
    message.JumpIfPositive -> "조건 분기 (ACC ≥ 0일 때)"
  }
}

pub fn label(label: Label) -> String {
  case label {
    message.PageTitle -> "LMC — 에뮬레이터"
    message.ButtonStep -> "Step"
    message.ButtonRun -> "Run"
    message.ButtonReset -> "Reset"
    message.ButtonAssemble -> ".lmc 어셈블"
    message.ButtonLoad -> ".lmcobj를 RAM에 불러오기"
    message.ButtonOk -> "확인"
    message.TipAssembleTitle -> "오브젝트 파일 만들기"
    message.TipAssembleBody ->
      "소스 옆에 .lmcobj를 씁니다: 한 줄에 네 자리 워드 하나, 니모닉도 레이블도 없습니다. 프로세서가 받는 것이 그것뿐이기 때문입니다. LDA 42와 MOV ACC, 42를 어셈블하면 같은 줄이 두 번 나옵니다. 실행하지도, 불러오지도 않습니다."
    message.TipLoadTitle -> "RAM에 불러오기"
    message.TipLoadBody ->
      "디스크에서 .lmcobj를 다시 읽어 메모리에 놓습니다. 불러오는 것은 정말로 파일입니다: 파일이 없으면 아무것도 실행되지 않고, 다시 어셈블하지 않은 채 소스를 고치면 이전 프로그램을 불러오게 됩니다. 실제 툴체인도 바로 이렇게 동작합니다."
    message.StatusLabel -> "상태"
    message.TipStatusTitle -> "프로세서 상태"
    message.TipStatusBody ->
      "empty (RAM에 아무것도 없음: 어셈블한 다음 불러오세요), running (실행 준비됨), waiting_input (INP에서 멈춰 값을 기다리는 중), halted (HLT로 멈춤), error."
    message.HeadingProcessor -> "프로세서"
    message.TipAccTitle -> "누산기"
    message.TipAccBody ->
      "모든 산술과 모든 입출력이 이곳을 지납니다: ADD, SUB, INP, OUT은 ACC만 다룹니다."
    message.TipPcTitle -> "프로그램 카운터"
    message.TipPcBody ->
      "다음에 읽을 명령의 주소입니다. 여기에 쓰는 것이 곧 분기이며, BRA, BRZ, BRP, RET가 하는 일이 그것뿐입니다. 실제 프로세서처럼 Fetch 단계에서 이미 증가하므로, 멈춘 기계는 마지막으로 실행한 명령의 다음을 가리킵니다."
    message.TipSiTitle -> "인덱스 레지스터"
    message.TipSiBody ->
      "x86의 SI와 같은 역할을 하며 이름도 같습니다. 접미사 [SI]는 적힌 주소에 그 내용을 더합니다 — lst[SI]는 셀 lst + SI를 가리키며, 어느 자리를 읽든 배열이나 문자열을 명령 하나로 훑을 수 있습니다."
    message.TipLrTitle -> "복귀 주소"
    message.TipLrBody ->
      "ARM에서 쓰는 이름 LR입니다. JSR은 호출 다음 명령의 주소를 여기에 쓰고, RET은 그곳으로 돌아갑니다. LR은 하나만 담을 수 있어 중첩 호출이 덮어씁니다. 그래서 스택이 필요합니다."
    message.TipSpTitle -> "스택 포인터"
    message.TipSpBody ->
      "다음 빈 셀을 가리킵니다. 스택은 셀 99에서 아래로 자라며, PSH가 레지스터를 넣고 POP이 꺼냅니다. 레지스터 없이 쓰면 둘 다 ACC를 다룹니다."
    message.HeadingIo -> "입력 / 출력"
    message.HeadingInput -> "입력 (INP)"
    message.InputValueLabel -> "값"
    message.HeadingOutput -> "출력 (OUT)"
    message.HeadingScreen -> "화면 (PLT)"
    message.TipScreenTitle -> "PLT 주소"
    message.TipScreenBody ->
      "점 하나를 켭니다. 명령은 주소부터 연속된 세 셀을 읽습니다: x, y, 그리고 색(팔레트 번호)입니다. 프로세서는 화면의 크기도 색도 모릅니다: 「이 점을 켜라」고 말할 뿐, 나머지는 화면이 정합니다. 여기서는 32 × 32 점과 여덟 가지 색입니다."
    message.ScreenAria -> "화면, 32 × 32 점"
    message.HeadingMemory -> "메모리"
    message.MemoryNote ->
      "프로그램에도 데이터에도 메모리는 하나뿐입니다: 이것이 폰 노이만의 원리이고, 아래 표시가 보여 주는 것입니다."
    message.LegendProgram -> "프로그램"
    message.LegendData -> "데이터 (DAT)"
    message.LegendStack -> "스택"
    message.LegendFree -> "빈 공간"
    message.CycleSummary -> "Fetch → Decode → Execute"
    message.CycleHint ->
      "니모닉이 무엇이든 모든 명령은 같은 세 단계를 지납니다. 마지막 step에서 일어난 일은 다음과 같습니다:"
  }
}
