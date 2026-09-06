//// パネルの日本語。
////
//// 値は `webview/text/message.gleam`、振り分けは
//// `webview/text/locale.gleam` にあります。このファイルは表示のみです。
////
//// 用語はサーバー(`lmc_lsp` の `lmc/text/japanese.gleam`)に合わせています
//// ― セル、アドレス、ラベル、スタック、アキュムレータ、プログラムカウンタ。
//// 同じ用語を二通りに訳すと、学習者には別の機械に見えてしまいます。
////
//// **母語話者による校正は受けていません。** 授業で使う教材である以上、
//// 校正されるべきです。

import gleam/int
import lmc/text/locale
import webview/text/message.{type Circuit, type Label, type Text}

pub fn render(text: Text) -> String {
  case text {
    message.FetchRead(address, word) ->
      "mem[" <> int.to_string(address) <> "] を読む → " <> int.to_string(word)
    message.FetchIncrement(from, to) ->
      "PC "
      <> int.to_string(from)
      <> " → "
      <> int.to_string(to)
      <> "(読み出し中、デコードの前に加算)"

    message.DecodedPlain(word, mnemonic, circuit) ->
      int.to_string(word)
      <> " → "
      <> mnemonic
      <> "("
      <> circuit_text(circuit)
      <> ")"
    message.DecodedWithOperand(word, mnemonic, operand, circuit) ->
      int.to_string(word)
      <> " → "
      <> mnemonic
      <> ", "
      <> operand
      <> "("
      <> circuit_text(circuit)
      <> ")"
    message.DecodedMove(word, destination, source, alias, circuit) ->
      int.to_string(word)
      <> " → MOV "
      <> destination
      <> ", "
      <> source
      <> message.shortcut(alias)
      <> "("
      <> circuit_text(circuit)
      <> ")"
    message.DecodedPlot(word, address, circuit) ->
      int.to_string(word)
      <> " → PLT, "
      <> message.three_cells(address)
      <> " → x, y, 色("
      <> circuit_text(circuit)
      <> ")"

    message.InputTaken(value) -> "ACC ← 入力(" <> int.to_string(value) <> ")"
    message.OutputSent(value) -> "出力 ← ACC(" <> int.to_string(value) <> ")"
    message.PixelSent(x, y, colour, outcome) ->
      "画面 ← 点("
      <> int.to_string(x)
      <> ", "
      <> int.to_string(y)
      <> ")、色 "
      <> int.to_string(colour)
      <> case outcome {
        message.Drawn -> ""
        message.OffScreen(width, height) ->
          " — 画面の外("
          <> int.to_string(width)
          <> " × "
          <> int.to_string(height)
          <> "):何も点灯しません"
        message.OffPalette(highest) ->
          " — パレットの外(0 から " <> int.to_string(highest) <> "):何も点灯しません"
      }
    message.MemoryWritten(address, value) ->
      "mem["
      <> int.to_string(address)
      <> "] ← ACC("
      <> int.to_string(value)
      <> ")"
    message.RegisterChanged(register, from, to) ->
      register <> " " <> int.to_string(from) <> " → " <> int.to_string(to)
    message.LinkChanged(from, to) ->
      "LR " <> int.to_string(from) <> " → " <> int.to_string(to) <> "(戻りアドレス)"
    message.Jumped(from, to) ->
      "PC "
      <> int.to_string(from)
      <> " → "
      <> int.to_string(to)
      <> "(プログラムカウンタへの書き込み)"
    message.Halted -> "HLT"
    message.WaitingForInput -> "入力を待っています…"

    message.RunnerError(reason) -> locale.render(reason, locale.Japanese)
    message.SourceHasErrors -> "プログラムにエラーがあります — エディタの診断を見てください"
    message.ProgramTooLong(cells) ->
      "プログラムが長すぎます:" <> int.to_string(cells) <> " セル(最大 100)"
    message.UndefinedLabel(name) -> "未定義のラベル:" <> name
    message.NoObjectFile(name) ->
      "読み込むオブジェクトファイルがありません(" <> name <> ")— まずアセンブルしてください"
    message.ObjectFileEmpty -> "オブジェクトファイルが空です"
    message.ObjectFileUnreadableLine(line) ->
      "オブジェクトファイルに読めない行があります:「" <> line <> "」"
    message.ObjectFileTooLong(cells) ->
      "オブジェクトファイルがメモリの 100 セルを超えています(" <> int.to_string(cells) <> ")"
  }
}

fn circuit_text(circuit: Circuit) -> String {
  case circuit {
    message.ReadingInput -> "入力を読むためのプロセッサ回路の設定"
    message.WritingOutput -> "出力を書くためのプロセッサ回路の設定"
    message.StoppingProcessor -> "プロセッサを止めるための回路の設定"
    message.Addition -> "加算のためのプロセッサ回路の設定"
    message.Subtraction -> "減算のためのプロセッサ回路の設定"
    message.LoadFromMemory -> "メモリからの読み込みのためのプロセッサ回路の設定"
    message.StoreToMemory -> "メモリへの書き込みのためのプロセッサ回路の設定"
    message.RegisterTransfer -> "レジスタ間の転送のためのプロセッサ回路の設定"
    message.PushRegister -> "レジスタを積むためのプロセッサ回路の設定"
    message.PopRegister -> "レジスタへ取り出すためのプロセッサ回路の設定"
    message.SendPixel -> "画面へ点を送るためのプロセッサ回路の設定"
    message.JumpAndLink -> "戻りアドレスを記憶する分岐のためのプロセッサ回路の設定"
    message.Jump -> "分岐のためのプロセッサ回路の設定"
    message.JumpIfZero -> "条件分岐(ACC = 0 のとき)のためのプロセッサ回路の設定"
    message.JumpIfPositive -> "条件分岐(ACC ≥ 0 のとき)のためのプロセッサ回路の設定"
  }
}

pub fn label(label: Label) -> String {
  case label {
    message.PageTitle -> "LMC — エミュレータ"
    message.ButtonStep -> "Step"
    message.ButtonRun -> "Run"
    message.ButtonReset -> "Reset"
    message.ButtonAssemble -> ".lmc をアセンブル"
    message.ButtonLoad -> ".lmcobj を RAM に読み込む"
    message.ButtonOk -> "OK"
    message.TipAssembleTitle -> "オブジェクトファイルを作る"
    message.TipAssembleBody ->
      "ソースの隣に .lmcobj を書き出します:1 行に 4 桁の語がひとつ、ニーモニックもラベルもありません。プロセッサが受け取るのはそれだけだからです。LDA 42 と MOV ACC, 42 をアセンブルすると同じ行が二度得られます。実行も読み込みもしません。"
    message.TipLoadTitle -> "RAM に読み込む"
    message.TipLoadBody ->
      "ディスクから .lmcobj を読み直してメモリに置きます。読み込まれるのは確かにファイルです:ファイルがなければ何も実行されず、アセンブルし直さずにソースを変更すれば、前のプログラムが読み込まれます。本物のツールチェーンもまったく同じように振る舞います。"
    message.StatusLabel -> "状態"
    message.TipStatusTitle -> "プロセッサの状態"
    message.TipStatusBody ->
      "empty(RAM に何もありません:アセンブルしてから読み込んでください)、running(実行可能)、waiting_input(INP で停止し、値を待っています)、halted(HLT で停止)、error。"
    message.HeadingProcessor -> "プロセッサ"
    message.TipAccTitle -> "アキュムレータ"
    message.TipAccBody ->
      "すべての算術と、すべての入出力がここを通ります:ADD、SUB、INP、OUT は ACC しか扱いません。"
    message.TipPcTitle -> "プログラムカウンタ"
    message.TipPcBody ->
      "次に読む命令のアドレスです。ここに書き込むことが分岐であり、BRA、BRZ、BRP、RET がしているのはそれだけです。本物のプロセッサと同じく Fetch の段階で加算されるため、停止したときにはすでに、最後に実行した命令の次を指しています。"
    message.TipSiTitle -> "インデックスレジスタ"
    message.TipSiBody ->
      "x86 の SI と同じ役割で、同じ名前です。接尾辞 [SI] は書かれたアドレスにその内容を足します — lst[SI] はセル lst + SI を指し、読む位置がどこであれ、配列や文字列を一命令でたどれます。"
    message.TipLrTitle -> "戻りアドレス"
    message.TipLrBody ->
      "ARM での名前 LR です。JSR は呼び出しの次の命令のアドレスをここに書き、RET はそこへ戻ります。LR が持てるのはひとつだけで、入れ子の呼び出しは上書きします。だからスタックが要るのです。"
    message.TipSpTitle -> "スタックポインタ"
    message.TipSpBody ->
      "次に空いているセルを指します。スタックはセル 99 から下へ伸び、PSH がレジスタを積み、POP が取り出します。レジスタを書かずに使うと、どちらも ACC を扱います。"
    message.HeadingIo -> "入力 / 出力"
    message.HeadingInput -> "入力(INP)"
    message.InputValueLabel -> "値"
    message.HeadingOutput -> "出力(OUT)"
    message.HeadingScreen -> "画面(PLT)"
    message.TipScreenTitle -> "PLT アドレス"
    message.TipScreenBody ->
      "点をひとつ点灯します。命令はアドレスから連続する 3 つのセルを読みます:x、y、そして色(パレットの番号)です。プロセッサは画面の大きさも色も知りません:「この点を点けよ」と言うだけで、あとは表示側が決めます。ここでは 32 × 32 の点と 8 色です。"
    message.ScreenAria -> "画面、32 × 32 の点"
    message.HeadingMemory -> "メモリ"
    message.MemoryNote ->
      "プログラムにもデータにも、メモリはひとつだけです:これがフォン・ノイマンの原理であり、下の印が示しているものです。"
    message.LegendProgram -> "プログラム"
    message.LegendData -> "データ(DAT)"
    message.LegendStack -> "スタック"
    message.LegendFree -> "空き"
    message.CycleSummary -> "Fetch → Decode → Execute"
    message.CycleHint ->
      "どの命令も、ニーモニックが何であれ、同じ 3 つの段階を通ります。直前の step で起きたことは次のとおりです:"
  }
}
