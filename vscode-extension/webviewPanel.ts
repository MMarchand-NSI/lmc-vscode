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
//   webview -> host  {"type":"currentLine","line":N|null}
//   webview -> host  {"type":"objectCode","content":"5042\n..."}
//   webview -> host  {"type":"requestLoad"}
//   host -> webview  {"type":"objectLoaded","content":"5042\n..."}
//   host -> webview  {"type":"objectLoadFailed","name":"essai.lmcobj"}
//   host -> webview  {"type":"setLocale","locale":"fr"}
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

// The "next instruction about to execute" highlight — same idea as VS
// Code's own debugger current-line marker, reusing its theme color so it
// looks native rather than inventing a new color. Applied to whichever
// TextEditor instance is currently live (see findLiveEditor): the
// decoration lives on that specific object, and VS Code can hand out a new
// TextEditor instance for the same file after switching tabs away and back
// (see the module doc comment) — so lastCurrentLine is kept separately and
// reapplied to whatever editor object is live, rather than trusting a
// decoration set once to survive.
const currentLineDecoration = vscode.window.createTextEditorDecorationType({
  isWholeLine: true,
  backgroundColor: new vscode.ThemeColor("editor.stackFrameHighlightBackground"),
});
let lastCurrentLine: number | null = null;

export function openEmulatorPanel(context: vscode.ExtensionContext): void {
  const editor = vscode.window.activeTextEditor;
  if (!editor || editor.document.languageId !== "lmc") {
    vscode.window.showWarningMessage(t().openFileFirst);
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
    t().panelTitle,
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

  // Le serveur, lui, redémarre pour changer de langue ; le panneau n'a qu'à
  // recevoir la nouvelle et se repeindre.
  disposables.push(
    vscode.workspace.onDidChangeConfiguration((event) => {
      if (event.affectsConfiguration("lmc.locale")) {
        currentPanel?.webview.postMessage({
          type: "setLocale",
          locale: configuredLocale(),
        });
        // Le titre de l'onglet est posé par l'hôte, pas peint par le
        // webview : il ne suivrait pas tout seul.
        if (currentPanel) currentPanel.title = t().panelTitle;
      }
    }),
  );

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
      // Refocusing can hand back a *different* TextEditor instance for the
      // same file — reapply to it explicitly rather than assuming whatever
      // had the decoration before still does.
      applyCurrentLineDecoration();
    }),
  );

  currentPanel.onDidDispose(() => {
    findLiveEditor()?.setDecorations(currentLineDecoration, []);
    currentPanel = undefined;
    sourceUri = undefined;
    lastCurrentLine = null;
    disposables.forEach((d) => d.dispose());
    disposables = [];
  });
}

function isSourceDocument(document: vscode.TextDocument): boolean {
  return sourceUri !== undefined && document.uri.toString() === sourceUri.toString();
}

/// The live TextEditor for sourceUri, if that file is currently visible in
/// some pane — never a cached reference from an earlier point in time.
/// `visibleTextEditors` only covers panes actually painted on screen: a tab
/// that's open but sitting in the background of its group (not the active
/// tab there) doesn't count as "visible" and won't show up here — see
/// findOpenTabGroupColumn for that case.
function findLiveEditor(): vscode.TextEditor | undefined {
  return vscode.window.visibleTextEditors.find(
    (e) => sourceUri !== undefined && e.document.uri.toString() === sourceUri.toString(),
  );
}

/// The view column of an existing (but currently backgrounded/inactive)
/// tab for sourceUri, if one is open anywhere. Without this,
/// showTextDocument(uri) with no explicit viewColumn defaults to the
/// *active* column — which, when the click driving this came from the
/// webview, is the webview's own column — and opens a redundant second tab
/// there instead of reactivating the existing one.
function findOpenTabGroupColumn(): vscode.ViewColumn | undefined {
  if (!sourceUri) return undefined;
  for (const group of vscode.window.tabGroups.all) {
    for (const tab of group.tabs) {
      if (
        tab.input instanceof vscode.TabInputText &&
        tab.input.uri.toString() === sourceUri.toString()
      ) {
        return group.viewColumn;
      }
    }
  }
  return undefined;
}

/// Le même réglage que celui que `client.ts` envoie au serveur, lu de la
/// même façon : le panneau et les diagnostics doivent parler la même langue,
/// et deux lectures différentes du même réglage les feraient diverger.
function configuredLocale(): string {
  const choice = vscode.workspace.getConfiguration("lmc").get<string>("locale", "fr");
  return choice === "auto" ? vscode.env.language : choice;
}

/// Les trois phrases que l'hôte prononce lui-même. Elles ne peuvent pas
/// venir du catalogue Gleam (`src/webview/text.gleam`) comme tout le reste :
/// une notification VS Code et le titre d'un onglet ne passent pas par le
/// rendu du webview, et le nom du fichier objet n'existe que de ce côté-ci.
/// C'est donc le seul autre endroit du dépôt où une langue se choisit, et
/// c'est assumé plutôt que contourné.
///
/// Le repli suit la règle du serveur (`message.from_tag`) : « en » donne
/// l'anglais, tout le reste le français.
const hostText = {
  fr: {
    openFileFirst:
      "Ouvrez d'abord un fichier .lmc, puis lancez « LMC: Open Emulator ».",
    panelTitle: "LMC — Émulateur",
    assembledInto: (name: string) => `Code assemblé dans ${name}`,
  },
  es: {
    openFileFirst:
      "Abre primero un archivo .lmc y luego ejecuta « LMC: Open Emulator ».",
    panelTitle: "LMC — Emulador",
    assembledInto: (name: string) => `Código ensamblado en ${name}`,
  },
  en: {
    // La commande est citée sous le nom qu'elle porte dans la palette, le
    // même dans les trois langues : les chaînes du manifeste ne suivent pas
    // `lmc.locale` (VS Code ne localise `package.json` que par
    // `package.nls.json`, selon *sa* langue d'affichage), elles sont donc en
    // anglais, comme la page Marketplace. Traduire la citation enverrait
    // chercher une entrée qui n'existe pas.
    openFileFirst:
      "Open an .lmc file first, then run « LMC: Open Emulator ».",
    panelTitle: "LMC — Emulator",
    assembledInto: (name: string) => `Code assembled into ${name}`,
  },
};

/// La sous-étiquette primaire, comme le serveur la lit (`fr-FR` → `fr`), et
/// le même repli : une langue qu'on ne parle pas ici donne le français.
///
/// Ce fut un bogue et pas une omission théorique : `hostText` n'avait que
/// `fr` et `en` quand l'espagnol est arrivé, et un utilisateur réglé sur
/// `es` a eu un panneau espagnol avec un titre d'onglet français.
/// `scripts/check-manifest.mjs` exige désormais que cette table couvre
/// toutes les langues du serveur.
function t(): (typeof hostText)["fr"] {
  const tag = configuredLocale().toLowerCase().split("-")[0];
  return hostText[tag as keyof typeof hostText] ?? hostText.fr;
}

function handleWebviewMessage(panel: vscode.WebviewPanel, message: any): void {
  switch (message?.type) {
    case "ready":
      // La langue d'abord : le panneau se peint dès le premier message, et
      // l'envoyer après le source le ferait clignoter d'une langue à
      // l'autre.
      panel.webview.postMessage({ type: "setLocale", locale: configuredLocale() });
      if (sourceUri) {
        const editor = findLiveEditor();
        if (editor) sendSource(panel, editor.document);
        else vscode.workspace.openTextDocument(sourceUri).then((doc) => sendSource(panel, doc));
      }
      break;
    case "revealLine":
      revealLine(message.line);
      break;
    case "currentLine":
      lastCurrentLine = typeof message.line === "number" ? message.line : null;
      applyCurrentLineDecoration();
      break;
    case "objectCode":
      writeObjectFile(message.content);
      break;
    case "requestLoad":
      sendObjectFile(panel);
      break;
  }
}

/// Writes the assembled words next to the source as `<name>.lmcobj` and
/// opens it. The webview assembles (it already does, on every keystroke)
/// and the host writes: the webview has no filesystem access, and the
/// split keeps the assembling in the tested Gleam core rather than here.
///
/// The point of the file is that it's a real artifact — normally you
/// assemble to a file and *that* is what gets loaded into RAM. The
/// emulator still runs from its own in-memory assembly rather than
/// re-reading this file; the words are identical because both come from
/// the same `load.load` (see model.object_code), so the two cannot drift.
/// The `.lmcobj` sitting next to the source. Derived from sourceUri rather
/// than remembered from the last write: the file on disk is the thing being
/// loaded, and it may well have been written by an earlier session, or not
/// exist at all.
function objectFileUri(): vscode.Uri | undefined {
  if (!sourceUri) return undefined;
  return sourceUri.with({ path: sourceUri.path.replace(/\.lmc$/i, "") + ".lmcobj" });
}

/// Reads the object file and hands its text to the webview, which turns it
/// into RAM. The read really does hit the disk — that is the whole point of
/// having a file: loading fails when nothing has been assembled, and loads
/// a stale program when the source has moved on since. Both are how a real
/// toolchain behaves, and both are worth being able to show.
async function sendObjectFile(panel: vscode.WebviewPanel): Promise<void> {
  const target = objectFileUri();
  if (!target) return;
  try {
    const bytes = await vscode.workspace.fs.readFile(target);
    panel.webview.postMessage({
      type: "objectLoaded",
      content: new TextDecoder().decode(bytes),
    });
  } catch {
    // Le nom du fichier, pas une phrase : c'est le panneau qui écrit, et
    // lui seul sait dans quelle langue.
    panel.webview.postMessage({
      type: "objectLoadFailed",
      name: path.basename(target.fsPath),
    });
  }
}

async function writeObjectFile(content: unknown): Promise<void> {
  if (!sourceUri || typeof content !== "string") return;

  const target = objectFileUri();
  if (!target) return;
  await vscode.workspace.fs.writeFile(target, new TextEncoder().encode(content));

  // A notification rather than opening the file. Assembling happens often
  // while teaching, and opening the object file every time churned the tab
  // strip — the point is that the file now exists, not that you must read
  // it. Open it yourself when you want to look inside.
  vscode.window.showInformationMessage(
    t().assembledInto(path.basename(target.fsPath)),
  );
}

/// Applies (or clears) the current-line highlight on the live editor for
/// sourceUri, if that file happens to be visible right now. Silently does
/// nothing otherwise — unlike revealLine, this never opens or activates a
/// tab just to decorate it; there's nothing worth decorating if the user
/// isn't looking at the file.
function applyCurrentLineDecoration(): void {
  const editor = findLiveEditor();
  if (!editor) return;
  if (lastCurrentLine === null) {
    editor.setDecorations(currentLineDecoration, []);
    return;
  }
  const position = new vscode.Position(lastCurrentLine, 0);
  editor.setDecorations(currentLineDecoration, [new vscode.Range(position, position)]);
}

function sendSource(panel: vscode.WebviewPanel, document: vscode.TextDocument): void {
  panel.webview.postMessage({ type: "setSource", source: document.getText() });
}

async function revealLine(line: number): Promise<void> {
  if (typeof line !== "number" || !sourceUri) return;
  const position = new vscode.Position(line, 0);
  const range = new vscode.Range(position, position);

  // Prefer an already-visible editor for the file; failing that, reactivate
  // its existing (but backgrounded) tab in whichever column it's already
  // open in — passing that column explicitly is what stops
  // showTextDocument from defaulting to the active column (the webview's
  // own) and opening a redundant second tab there. Only if neither exists
  // (the tab was actually closed) does it fall through to opening a new one.
  const editor =
    findLiveEditor() ??
    (await vscode.window.showTextDocument(sourceUri, {
      preserveFocus: true,
      viewColumn: findOpenTabGroupColumn(),
    }));

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
