import * as path from "path";
import { commands, env, ExtensionContext, workspace } from "vscode";
import {
  LanguageClient,
  LanguageClientOptions,
  ServerOptions,
  TransportKind,
} from "vscode-languageclient/node";
import { openEmulatorPanel } from "./webviewPanel";

let client: LmcLanguageClient;

/// La langue que le serveur doit parler, telle que le réglage `lmc.locale`
/// la demande.
///
/// Le défaut est le français, et « auto » n'est *pas* le défaut : la langue
/// d'affichage de VS Code reste l'anglais chez la plupart des gens, quel que
/// soit leur pays, parce qu'on ne la change pas. La prendre pour la langue de
/// la classe rendrait des diagnostics anglais à un cours français, ce qui est
/// précisément le contraire du service rendu.
function configuredLocale(): string {
  const choice = workspace.getConfiguration("lmc").get<string>("locale", "fr");
  return choice === "auto" ? env.language : choice;
}

/// `getLocale()` est ce que la bibliothèque envoie dans le `locale` de
/// `initialize`, et sa valeur par défaut est `env.language`. La surcharger
/// est le seul point d'entrée : le champ n'est pas exposé dans les options,
/// et le serveur lit `params.locale`, pas les `initializationOptions`.
class LmcLanguageClient extends LanguageClient {
  protected getLocale(): string {
    return configuredLocale();
  }
}

export function activate(context: ExtensionContext): void {
  // The LSP server ships *inside* the extension: lsp-server.mjs and the
  // vendor/ bundle it loads are packaged into the .vsix, so an installed
  // extension is self-contained and needs nothing from the repo around it.
  // It used to live one directory above (at the project root), which worked
  // under F5 and would have shipped a .vsix with no server in it at all.
  const serverEntry = path.join(context.extensionPath, "lsp-server.mjs");

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

  client = new LmcLanguageClient(
    "lmc-language-server",
    "LMC Language Server",
    serverOptions,
    clientOptions
  );

  client.start();

  context.subscriptions.push(
    commands.registerCommand("lmc.openEmulator", () => openEmulatorPanel(context)),
    // La langue n'est annoncée qu'une fois, dans `initialize` : changer le
    // réglage sans redémarrer le serveur ne changerait rien, et laisserait
    // croire que le réglage ne marche pas.
    workspace.onDidChangeConfiguration((event) => {
      if (event.affectsConfiguration("lmc.locale")) {
        client.restart();
      }
    }),
  );
}

export function deactivate(): Thenable<void> | undefined {
  return client?.stop();
}
