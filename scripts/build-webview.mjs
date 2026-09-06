#!/usr/bin/env node
// Bundles the compiled webview/app.gleam (browser-side emulator UI) into a
// single script the webview panel can load directly. Mirrors
// build-lsp-bundle.mjs's role for the LSP bundle: turns a `gleam build`
// output tree with relative imports into one self-contained file — except
// this one is built locally (`gleam build` in this repo), not fetched from
// a release, and targets the browser (--platform=browser / no Node
// built-ins), not Node.
//
// Usage: gleam build && node scripts/build-webview.mjs

import { execFile } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

const run = promisify(execFile);
const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..");

const entry = join(
  root,
  "build/dev/javascript/lmc_vscode/webview/app.mjs",
);
const outfile = join(root, "vscode-extension/webview/app.bundle.js");

try {
  await run("npx", [
    "esbuild",
    entry,
    "--bundle",
    "--platform=browser",
    "--format=iife",
    // Gleam's `pub fn main()` is just an export, nothing calls it on its
    // own — expose it as window.LmcApp.main so index.html's bootstrap
    // script can. Without --global-name the IIFE wrapper exposes nothing
    // at all.
    "--global-name=LmcApp",
    `--outfile=${outfile}`,
  ], { cwd: join(root, "vscode-extension") });
} catch (err) {
  console.error(err.stderr || err.message);
  console.error(
    "\nMake sure `gleam build` has been run first (needed for " +
      entry +
      " to exist), and that esbuild is installed (`npm install` in vscode-extension/).",
  );
  process.exit(1);
}

console.log(`Wrote ${outfile}`);
