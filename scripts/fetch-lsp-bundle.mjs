#!/usr/bin/env node
// Downloads a tagged release of the standalone lmc_lsp server
// (https://github.com/MMarchand-NSI/lmc_lsp) and vendors it locally, so
// lsp-server.mjs can run it instead of the legacy in-tree Gleam server.
//
// Usage:
//   node scripts/fetch-lsp-bundle.mjs [version]
//
// `version` defaults to the LMC_LSP_VERSION env var, or v0.3.1 if unset.
// The result is written to vendor/lmc-lsp.bundle.mjs (gitignored — re-run
// this script to pick it up, it is not committed).
//
// lmc_lsp is currently a PRIVATE repo, so downloading its release assets
// requires GitHub auth — this shells out to the `gh` CLI (must be logged in
// via `gh auth login`) rather than doing a plain, unauthenticated fetch.
// If lmc_lsp is ever made public, this can go back to a plain `fetch()`.

import { execFile } from "node:child_process";
import { mkdir } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

const run = promisify(execFile);

const REPO = "MMarchand-NSI/lmc_lsp";
const ASSET = "lmc-lsp.bundle.mjs";

const version = process.argv[2] ?? process.env.LMC_LSP_VERSION ?? "v0.3.1";
const here = dirname(fileURLToPath(import.meta.url));
const destDir = join(here, "..", "vendor");

console.log(`Fetching lmc_lsp ${version} (${ASSET}) from ${REPO} via gh CLI...`);
await mkdir(destDir, { recursive: true });

try {
  await run("gh", [
    "release",
    "download",
    version,
    "--repo",
    REPO,
    "--pattern",
    ASSET,
    "--dir",
    destDir,
    "--clobber",
  ]);
} catch (err) {
  console.error(err.stderr?.trim() || err.message);
  console.error(
    "\nMake sure `gh` is installed and authenticated (`gh auth login`) with " +
      `access to the private ${REPO} repo.`,
  );
  process.exit(1);
}

console.log(`Wrote ${join(destDir, ASSET)}`);
