// Entry point for the LMC language server.
//
// Prefers the standalone lmc_lsp server (github.com/MMarchand-NSI/lmc_lsp),
// vendored locally by `node scripts/fetch-lsp-bundle.mjs` into
// vendor/lmc-lsp.bundle.mjs (gitignored — run the script to fetch it).
// Falls back to the legacy in-tree Gleam server (src/lsp/, src/lmc/,
// compiled by `gleam build`) when the vendored bundle hasn't been fetched
// yet, so the extension keeps working during the migration. See CLAUDE.md,
// "Relationship to the sibling lmc_lsp repo".
let main;
try {
  ({ main } = await import("./vendor/lmc-lsp.bundle.mjs"));
} catch {
  ({ main } = await import("./build/dev/javascript/lmc_vscode/lsp/server.mjs"));
}
main();
