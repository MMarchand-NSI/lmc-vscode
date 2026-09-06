// Entry point for the LMC language server.
//
// Runs the standalone lmc_lsp server (github.com/MMarchand-NSI/lmc_lsp),
// built by `node scripts/build-lsp-bundle.mjs` into vendor/lmc-lsp.bundle.mjs
// next to this file (gitignored — run that script to build it).
//
// This file and vendor/ live inside vscode-extension/ rather than at the
// repo root so that `vsce package` puts them in the .vsix: an installed
// extension has no repo around it, so anything it needs has to be in the
// archive.
let main;
try {
  ({ main } = await import("./vendor/lmc-lsp.bundle.mjs"));
} catch (err) {
  console.error(
    "Could not load vendor/lmc-lsp.bundle.mjs — run " +
      "`gleam build && node scripts/build-lsp-bundle.mjs` first to build it.\n" +
      String(err),
  );
  process.exit(1);
}
main();
