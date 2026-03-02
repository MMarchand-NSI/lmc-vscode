// Entry point for the LMC language server.
// Imports the compiled Gleam module and calls its main function.
import { main } from "./build/dev/javascript/lmc_vscode/lsp/server.mjs";
main();
