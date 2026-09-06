#!/usr/bin/env node
// Construit le serveur de langage à partir du code de `lmc_lsp` déjà présent,
// vers vscode-extension/vendor/lmc-lsp.bundle.mjs.
//
// Ce script a remplacé un `gh release download` de l'asset publié. La raison
// est le **double épinglage** : tant que le bundle venait d'une release et la
// bibliothèque d'une dépendance git, ce dépôt portait la même version à deux
// endroits, et les tenir ensemble était une consigne, pas un mécanisme. Or
// `gleam deps download` ramène déjà tout le code, FFI comprise, et
// `gleam build` le compile : le bundle n'a plus qu'à être assemblé. Une seule
// source, un seul épinglage, `gleam.toml`.
//
// Ce qu'on perd et comment on le regagne : le bundle publié est l'artefact que
// la CI de `lmc_lsp` teste, celui-ci ne l'est pas. D'où `scripts/check-lsp.mjs`,
// qui lance sur ce bundle-ci la suite d'intégration de `lmc_lsp` elle-même.
//
// Demande `gleam build` d'abord, comme build-webview.mjs.

import { existsSync, readFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const entry = join(root, "build", "dev", "javascript", "lmc_lsp", "main.mjs");
const outfile = join(root, "vscode-extension", "vendor", "lmc-lsp.bundle.mjs");
const depPackage = join(root, "build", "packages", "lmc_lsp", "package.json");
const esbuild = join(root, "vscode-extension", "node_modules", ".bin", "esbuild");

for (const [path, remede] of [
  [entry, "lance `gleam deps download` puis `gleam build` d'abord"],
  [depPackage, "lance `gleam deps download` d'abord"],
  [esbuild, "lance `npm install` dans vscode-extension/"],
]) {
  if (!existsSync(path)) {
    console.error(`${path} absent : ${remede}.`);
    process.exit(1);
  }
}

// Les options ne sont pas retapées ici : elles se lisent dans le package.json
// de `lmc_lsp`, qui est la référence de la façon dont ce bundle se construit.
// Retaper aurait fait une seconde copie à tenir à jour, c'est-à-dire le
// problème qu'on vient de supprimer.
const script = JSON.parse(readFileSync(depPackage, "utf8")).scripts?.["build:minify"];
const prefix = "gleam build && esbuild ";
if (typeof script !== "string" || !script.startsWith(prefix)) {
  console.error(
    `Le script « build:minify » de ${depPackage} n'a plus la forme attendue :\n  ${script}\n` +
      "Reprendre ses options à la main plutôt que de deviner.",
  );
  process.exit(1);
}

const args = script
  .slice(prefix.length)
  .split(/\s+/)
  .filter((a) => !a.startsWith("--outfile="))
  .map((a) => (a.endsWith("main.mjs") ? entry : a));

execFileSync(esbuild, [...args, `--outfile=${outfile}`], { stdio: "inherit" });
console.log(`Wrote ${outfile}`);
