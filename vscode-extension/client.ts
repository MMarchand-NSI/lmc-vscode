import * as path from "path";
import { ExtensionContext } from "vscode";
import {
  LanguageClient,
  LanguageClientOptions,
  ServerOptions,
  TransportKind,
} from "vscode-languageclient/node";

let client: LanguageClient;

export function activate(context: ExtensionContext): void {
  // The LSP server is a compiled Gleam/Node.js script one level above this
  // extension directory (at the project root).
  const serverEntry = path.join(
    context.extensionPath,
    "..",
    "lsp-server.mjs"
  );

  const serverOptions: ServerOptions = {
    run:   { command: "node", args: [serverEntry], transport: TransportKind.stdio },
    debug: { command: "node", args: [serverEntry], transport: TransportKind.stdio },
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
}

export function deactivate(): Thenable<void> | undefined {
  return client?.stop();
}
