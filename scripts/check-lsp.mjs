#!/usr/bin/env node
// Fait passer au bundle construit ici la suite d'intégration de `lmc_lsp`
// elle-même (`test_lsp.mjs`, une cinquantaine d'assertions sur toute la
// surface du protocole), et non une suite écrite de ce côté-ci.
//
// C'est ce qui rend acceptable d'avoir cessé de télécharger l'asset publié
// (voir build-lsp-bundle.mjs) : l'artefact n'est plus celui que la CI d'en
// face a testé, alors on lui fait passer le même examen ici. Écrire nos
// propres assertions aurait vérifié notre idée du protocole, pas le sien.
//
// `test_lsp.mjs` charge « ./dist/lmc-lsp.bundle.mjs », relatif au répertoire
// courant : on lui en fabrique donc un qui pointe sur notre bundle.

import { existsSync, mkdtempSync, mkdirSync, symlinkSync, rmSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { tmpdir } from "node:os";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const bundle = join(root, "vscode-extension", "vendor", "lmc-lsp.bundle.mjs");
const suite = join(root, "build", "packages", "lmc_lsp", "test_lsp.mjs");

for (const [path, remede] of [
  [bundle, "lance `node scripts/build-lsp-bundle.mjs` d'abord"],
  [suite, "lance `gleam deps download` d'abord"],
]) {
  if (!existsSync(path)) {
    console.error(`${path} absent : ${remede}.`);
    process.exit(1);
  }
}

const dir = mkdtempSync(join(tmpdir(), "lmc-check-lsp-"));
try {
  mkdirSync(join(dir, "dist"));
  symlinkSync(bundle, join(dir, "dist", "lmc-lsp.bundle.mjs"));
  execFileSync(process.execPath, [suite, "--bundle"], { cwd: dir, stdio: "inherit" });
} catch (err) {
  process.exit(err.status ?? 1);
} finally {
  rmSync(dir, { recursive: true, force: true });
}
