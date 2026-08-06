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
//
// Tracked by document URI, not by a cached TextEditor object. VS Code can
// (and does) hand out a *new* TextEditor instance for the same file when
// you switch tabs away and back — a cached reference from when the panel
// was opened goes stale, silently breaking both sync directions (identity
// checks against it stop matching, and calling .revealRange on a disposed
// editor is a no-op). Resolving the live editor by URI at the moment it's
// actually needed sidesteps that entirely.

let currentPanel: vscode.WebviewPanel | undefined;
let sourceUri: vscode.Uri | undefined;
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
    sourceUri = editor.document.uri;
    currentPanel.reveal(vscode.ViewColumn.Beside);
    sendSource(currentPanel, editor.document);
    return;
  }

  sourceUri = editor.document.uri;
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
      if (!currentPanel || !isSourceDocument(event.textEditor.document)) return;
      const line = event.selections[0]?.active.line ?? null;
      currentPanel.webview.postMessage({ type: "cursorLine", line });
    }),
  );

  disposables.push(
    vscode.workspace.onDidChangeTextDocument((event) => {
      if (!currentPanel || !isSourceDocument(event.document)) return;
      sendSource(currentPanel, event.document);
    }),
  );

  // Selection-change events only fire on an actual selection change, not
  // merely on refocusing a tab whose cursor hadn't moved — without this,
  // switching back to the source file after the cursor already sat
  // somewhere would leave the webview showing a stale cursor highlight
  // until the next actual move. Re-sync (source + cursor) on every switch
  // back to the tracked file instead of waiting for that.
  disposables.push(
    vscode.window.onDidChangeActiveTextEditor((editor) => {
      if (!currentPanel || !editor || !isSourceDocument(editor.document)) return;
      sendSource(currentPanel, editor.document);
      const line = editor.selection.active.line;
      currentPanel.webview.postMessage({ type: "cursorLine", line });
    }),
  );

  currentPanel.onDidDispose(() => {
    currentPanel = undefined;
    sourceUri = undefined;
    disposables.forEach((d) => d.dispose());
    disposables = [];
  });
}

function isSourceDocument(document: vscode.TextDocument): boolean {
  return sourceUri !== undefined && document.uri.toString() === sourceUri.toString();
}

/// The live TextEditor for sourceUri, if that file is currently visible in
/// some pane — never a cached reference from an earlier point in time.
function findLiveEditor(): vscode.TextEditor | undefined {
  return vscode.window.visibleTextEditors.find(
    (e) => sourceUri !== undefined && e.document.uri.toString() === sourceUri.toString(),
  );
}

function handleWebviewMessage(panel: vscode.WebviewPanel, message: any): void {
  switch (message?.type) {
    case "ready":
      if (sourceUri) {
        const editor = findLiveEditor();
        if (editor) sendSource(panel, editor.document);
        else vscode.workspace.openTextDocument(sourceUri).then((doc) => sendSource(panel, doc));
      }
      break;
    case "revealLine":
      revealLine(message.line);
      break;
  }
}

function sendSource(panel: vscode.WebviewPanel, document: vscode.TextDocument): void {
  panel.webview.postMessage({ type: "setSource", source: document.getText() });
}

async function revealLine(line: number): Promise<void> {
  if (typeof line !== "number" || !sourceUri) return;
  const position = new vscode.Position(line, 0);
  const range = new vscode.Range(position, position);

  // Prefer an already-visible editor for the file (don't steal focus into
  // a new pane if the user can already see it); fall back to opening it
  // if the tab was closed entirely, not just backgrounded.
  const editor =
    findLiveEditor() ??
    (await vscode.window.showTextDocument(sourceUri, { preserveFocus: true }));

  editor.selection = new vscode.Selection(position, position);
  editor.revealRange(range, vscode.TextEditorRevealType.InCenterIfOutsideViewport);
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
