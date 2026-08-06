// Entry point for the LMC language server.
//
// Runs the standalone lmc_lsp server (github.com/MMarchand-NSI/lmc_lsp),
// vendored locally by `node scripts/fetch-lsp-bundle.mjs` into
// vendor/lmc-lsp.bundle.mjs (gitignored — run that script to fetch it).
let main;
try {
  ({ main } = await import("./vendor/lmc-lsp.bundle.mjs"));
} catch (err) {
  console.error(
    "Could not load vendor/lmc-lsp.bundle.mjs — run " +
      "`node scripts/fetch-lsp-bundle.mjs` first to fetch it.\n" +
      String(err),
  );
  process.exit(1);
}
main();
