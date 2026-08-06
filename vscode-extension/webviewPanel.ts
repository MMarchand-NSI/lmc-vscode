import * as crypto from "crypto";
import * as fs from "fs";
import * as path from "path";
import * as vscode from "vscode";

// Manages the (single, for this MVP) emulator webview panel: creates it,
// loads webview/index.html with its placeholders substituted, and bridges
// postMessage both ways — including the editor <-> webview sync that's the
// actual point of doing this as a VS Code webview rather than embedding an
// existing standalone LMC simulator. Protocol (see also
// src/webview/app.gleam, which owns the Gleam-side half of this):
//
//   webview -> host  {"type":"ready"}
//   webview -> host  {"type":"revealLine","line":N}
//   host -> webview  {"type":"setSource","source":"..."}
//   host -> webview  {"type":"cursorLine","line":N|null}

let currentPanel: vscode.WebviewPanel | undefined;
let currentEditor: vscode.TextEditor | undefined;
let disposables: vscode.Disposable[] = [];

export function openEmulatorPanel(context: vscode.ExtensionContext): void {
  const editor = vscode.window.activeTextEditor;
  if (!editor || editor.document.languageId !== "lmc") {
    vscode.window.showWarningMessage(
      "Open an .lmc file first, then run “LMC: Open Emulator”.",
    );
    return;
  }

  if (currentPanel) {
    currentEditor = editor;
    currentPanel.reveal(vscode.ViewColumn.Beside);
    sendSource(currentPanel, editor.document);
    return;
  }

  currentEditor = editor;
  const webviewDir = path.join(context.extensionPath, "webview");

  currentPanel = vscode.window.createWebviewPanel(
    "lmcEmulator",
    "LMC — Émulateur",
    vscode.ViewColumn.Beside,
    {
      enableScripts: true,
      // Keep the machine state alive when the panel is hidden (switching
      // tabs) instead of destroying and rebuilding the whole webview —
      // losing your step-through progress every time you glance at
      // another file would defeat the point of a step-through tool.
      retainContextWhenHidden: true,
      localResourceRoots: [vscode.Uri.file(webviewDir)],
    },
  );

  currentPanel.webview.html = renderHtml(currentPanel.webview, webviewDir);

  currentPanel.webview.onDidReceiveMessage(
    (message) => handleWebviewMessage(currentPanel!, message),
    undefined,
    disposables,
  );

  disposables.push(
    vscode.window.onDidChangeTextEditorSelection((event) => {
      if (!currentPanel || event.textEditor !== currentEditor) return;
      const line = event.selections[0]?.active.line ?? null;
      currentPanel.webview.postMessage({ type: "cursorLine", line });
    }),
  );

  disposables.push(
    vscode.workspace.onDidChangeTextDocument((event) => {
      if (!currentPanel || !currentEditor) return;
      if (event.document !== currentEditor.document) return;
      sendSource(currentPanel, event.document);
    }),
  );

  currentPanel.onDidDispose(() => {
    currentPanel = undefined;
    currentEditor = undefined;
    disposables.forEach((d) => d.dispose());
    disposables = [];
  });
}

function handleWebviewMessage(panel: vscode.WebviewPanel, message: any): void {
  switch (message?.type) {
    case "ready":
      if (currentEditor) sendSource(panel, currentEditor.document);
      break;
    case "revealLine":
      revealLine(message.line);
      break;
  }
}

function sendSource(panel: vscode.WebviewPanel, document: vscode.TextDocument): void {
  panel.webview.postMessage({ type: "setSource", source: document.getText() });
}

function revealLine(line: number): void {
  if (typeof line !== "number" || !currentEditor) return;
  const position = new vscode.Position(line, 0);
  const range = new vscode.Range(position, position);
  currentEditor.selection = new vscode.Selection(position, position);
  currentEditor.revealRange(range, vscode.TextEditorRevealType.InCenterIfOutsideViewport);
}

function renderHtml(webview: vscode.Webview, webviewDir: string): string {
  const template = fs.readFileSync(path.join(webviewDir, "index.html"), "utf8");
  const styleUri = webview.asWebviewUri(vscode.Uri.file(path.join(webviewDir, "style.css")));
  const scriptUri = webview.asWebviewUri(vscode.Uri.file(path.join(webviewDir, "app.bundle.js")));
  const nonce = crypto.randomBytes(16).toString("base64");

  return template
    .replaceAll("{{cspSource}}", webview.cspSource)
    .replaceAll("{{styleUri}}", styleUri.toString())
    .replaceAll("{{scriptUri}}", scriptUri.toString())
    .replaceAll("{{nonce}}", nonce);
}
