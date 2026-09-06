#!/usr/bin/env node
// Vérifie le manifeste de l'extension contre ce qui est vrai ailleurs.
//
// Le manifeste est un fichier de données : rien ne le compile, rien ne le
// relie au reste. Deux de ses affirmations ont déjà dérivé ou pouvaient le
// faire :
//
//   - la liste des langues de `lmc.locale`, qui doit être celle que le
//     serveur sait parler. La v0.8.1 de `lmc_lsp` a ajouté l'espagnol et le
//     réglage ne le proposait toujours pas : un enseignant hispanophone ne
//     pouvait pas le choisir, alors que le serveur l'aurait rendu.
//   - la même liste vue de `client.ts`, qui traduit le réglage en `locale`
//     LSP : une valeur offerte ici et inconnue là-bas partirait telle quelle
//     au serveur, qui retomberait silencieusement sur le français.
//
// Demande `gleam deps download` (il lit les sources de la dépendance).

import { readFileSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const manifestPath = join(root, "vscode-extension", "package.json");
const clientPath = join(root, "vscode-extension", "client.ts");
const localePath = join(root, "build", "packages", "lmc_lsp", "src", "lmc", "text", "locale.gleam");

if (!existsSync(localePath)) {
  console.error(`${localePath} absent : lance \`gleam deps download\` d'abord.`);
  process.exit(1);
}

let failures = 0;
const check = (label, got, want) => {
  const ok = String(got) === String(want);
  if (!ok) failures++;
  console.log(`  ${ok ? "ok  " : "ECHEC"} ${label.padEnd(52)} ${got}`);
};

// Les étiquettes que `from_tag` reconnaît, lues dans le serveur lui-même.
const source = readFileSync(localePath, "utf8");
const spoken = [...source.matchAll(/"([a-z]{2})" -> [A-Z]/g)].map((m) => m[1]);
if (spoken.length === 0) {
  console.error(`Aucune étiquette « "xx" -> Langue » dans ${localePath} : ce script ne vérifie plus rien.`);
  process.exit(1);
}

const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
const setting = manifest.contributes.configuration.properties["lmc.locale"];
// « auto » n'est pas une langue, c'est « suis VS Code ».
const offered = setting.enum.filter((v) => v !== "auto");

console.log(`\nLe réglage lmc.locale (${spoken.length} langues côté serveur)`);
check("offre exactement les langues du serveur", offered.sort().join(","), spoken.sort().join(","));
check("et décrit chacune", setting.enumDescriptions.length, setting.enum.length);
check("son défaut est une langue offerte", setting.enum.includes(setting.default), true);

// `client.ts` ne connaît qu'« auto » ; tout le reste part tel quel au
// serveur, ce qui n'est correct que si ce sont des étiquettes qu'il lit.
const client = readFileSync(clientPath, "utf8");
check("client.ts traite « auto » à part", client.includes('choice === "auto"'), true);

console.log(failures === 0 ? "\nTout est passé.\n" : `\n${failures} problème(s).\n`);
process.exit(failures === 0 ? 0 : 1);
