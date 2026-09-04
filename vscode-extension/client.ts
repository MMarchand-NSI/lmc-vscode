import * as path from "path";
import { commands, ExtensionContext } from "vscode";
import {
  LanguageClient,
  LanguageClientOptions,
  ServerOptions,
  TransportKind,
} from "vscode-languageclient/node";
import { openEmulatorPanel } from "./webviewPanel";

let client: LanguageClient;

export function activate(context: ExtensionContext): void {
  // The LSP server is a compiled Gleam/Node.js script one level above this
  // extension directory (at the project root).
  const serverEntry = path.join(
    context.extensionPath,
    "..",
    "lsp-server.mjs"
  );

  // `module`, not `command: "node"`. With a module and no explicit runtime,
  // vscode-languageclient forks it with `cp.fork`, which uses
  // `process.execPath` — the Node that ships inside VS Code — after setting
  // ELECTRON_RUN_AS_NODE=1 (see its lib/node/main.js). `command: "node"`
  // instead required a Node on the user's PATH, so the extension simply did
  // not start for anyone who has VS Code but no separate Node install. The
  // docs draw the same line: `command` is for a server already installed as
  // an executable, `module` for one shipped with the extension.
  const serverOptions: ServerOptions = {
    run: { module: serverEntry, transport: TransportKind.stdio },
    debug: { module: serverEntry, transport: TransportKind.stdio },
  };

  const clientOptions: LanguageClientOptions = {
    documentSelector: [{ scheme: "file", language: "lmc" }],
  };

  client = new LanguageClient(
    "lmc-language-server",
    "LMC Language Server",
    serverOptions,
    clientOptions
  );

  client.start();

  context.subscriptions.push(
    commands.registerCommand("lmc.openEmulator", () => openEmulatorPanel(context)),
  );
}

export function deactivate(): Thenable<void> | undefined {
  return client?.stop();
}
