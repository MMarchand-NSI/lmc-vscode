#!/usr/bin/env node
// Vérifie la grammaire TextMate contre le lexer de `lmc_lsp`, avec le vrai
// moteur (vscode-textmate sur Oniguruma), pas avec les expressions
// régulières de JavaScript : la grammaire est écrite pour Oniguruma, et
// c'est lui qui la lira dans VS Code.
//
// La grammaire duplique ce que le serveur sait déjà — la liste des
// mnémoniques, celle des registres, la forme d'un nom. Cette duplication est
// inévitable (VS Code colore avant même de parler au serveur) mais elle
// dérive en silence : la v0.5.0 a admis le souligné et les lettres
// accentuées dans les noms, la grammaire ne le savait pas, et
// « compteur_1: DAT 0 » n'avait plus aucune coloration alors que le serveur
// l'acceptait. Rien ne l'a signalé. Ce script est ce qui manquait.
//
// Demande `gleam build` (pour build/dev/javascript) et `gleam deps download`
// (pour build/packages/lmc_lsp), comme check-examples.mjs.

import { readFileSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { createRequire } from "node:module";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const grammarPath = join(root, "vscode-extension", "syntaxes", "lmc.tmLanguage.json");
const lexerPath = join(root, "build", "packages", "lmc_lsp", "src", "lmc", "parse", "lexer.gleam");
const completionPath = join(root, "build", "packages", "lmc_lsp", "src", "lmc", "features", "completion.gleam");
const js = join(root, "build", "dev", "javascript");

for (const [path, remede] of [
  [lexerPath, "lance `gleam deps download` d'abord"],
  [completionPath, "lance `gleam deps download` d'abord"],
  [js, "lance `gleam build` d'abord"],
]) {
  if (!existsSync(path)) {
    console.error(`${path} absent : ${remede}.`);
    process.exit(1);
  }
}

// jsdom, esbuild et vsce vivent déjà là ; les deux modules du moteur TextMate
// aussi. Voir vscode-extension/package.json.
const require = createRequire(join(root, "vscode-extension", "package.json"));
let oniguruma, textmate;
try {
  oniguruma = require("vscode-oniguruma");
  textmate = require("vscode-textmate");
} catch {
  console.error("vscode-oniguruma / vscode-textmate introuvables. Lancez `npm install` dans vscode-extension/.");
  process.exit(1);
}

const pipeline = await import(join(js, "lmc_lsp/lmc/semantic/pipeline.mjs"));

await oniguruma.loadWASM(readFileSync(require.resolve("vscode-oniguruma/release/onig.wasm")).buffer);
const registry = new textmate.Registry({
  onigLib: Promise.resolve({
    createOnigScanner: (s) => new oniguruma.OnigScanner(s),
    createOnigString: (s) => new oniguruma.OnigString(s),
  }),
  loadGrammar: async () =>
    textmate.parseRawGrammar(readFileSync(grammarPath, "utf8"), grammarPath),
});
const grammar = await registry.loadGrammar("source.lmc");

let failures = 0;
const check = (label, got, want) => {
  const ok = String(got) === String(want);
  if (!ok) failures++;
  console.log(`  ${ok ? "ok  " : "ECHEC"} ${label.padEnd(52)} ${got}`);
};

/// Les portées d'une ligne, dans l'ordre, sans les blancs ni `source.lmc`.
function scopes(line) {
  return grammar
    .tokenizeLine(line, textmate.INITIAL)
    .tokens.map((t) => [line.slice(t.startIndex, t.endIndex), t.scopes.at(-1)])
    .filter(([text]) => text.trim() !== "");
}

const scopeOf = (line, text) =>
  (scopes(line).find(([t]) => t === text) ?? [, "aucune"])[1];

// ── Les mots réservés, lus dans le lexer lui-même ───────────────────
// Le lexer est la référence ; la grammaire n'est qu'une copie. Extraire la
// table plutôt que la retaper est ce qui fait de ce script un contrôle et
// non une seconde copie.

const table = readFileSync(lexerPath, "utf8");
const words = [...table.matchAll(/"([A-Z]{2,3})" -> Kw/g)].map((m) => m[1]);
if (words.length === 0) {
  console.error(`Aucune entrée « "XXX" -> Kw » dans ${lexerPath} : la table a changé de forme, ce script ne vérifie plus rien.`);
  process.exit(1);
}
// Les registres se lisent eux aussi dans la dépendance, et non ici : c'est un
// nom de registre qui vient de changer (IX -> SI en v0.7.0), et une liste
// écrite à la main dans ce fichier aurait fait passer le contrôle au vert
// avec l'ancien nom des deux côtés. Ils vivent dans la liste de complétion de
// `features/completion.gleam`, le seul endroit de `lmc_lsp` qui les nomme
// comme un ensemble. On lit le bloc entier plutôt qu'une ligne : sa mise en
// forme a déjà changé une fois (v0.8.0), le contenu non.
const completionSource = readFileSync(completionPath, "utf8");
const block = completionSource.slice(completionSource.indexOf("const register_completions"));
const registers = [
  ...new Set([...block.slice(0, block.indexOf("\n]")).matchAll(/"([A-Z]{2,3})"/g)].map((m) => m[1])),
];
if (registers.length === 0) {
  console.error(`Aucun registre dans le bloc « register_completions » de ${completionPath} : ce script ne vérifie plus rien.`);
  process.exit(1);
}
const mnemonics = words.filter((w) => !registers.includes(w));

console.log(`\nMots réservés (${mnemonics.length} mnémoniques lus dans lexer.gleam, ${registers.length} registres dans completion.gleam)`);
for (const m of mnemonics) {
  check(`${m} est un mnémonique`, scopeOf(`        ${m}`, m), "keyword.control.lmc");
}
for (const r of registers) {
  check(`${r} est un registre`, scopeOf(`        MOV ${r}, ACC`, r), "variable.language.register.lmc");
}
// Et l'inverse : rien dans la grammaire que le lexer ne connaisse pas.
const listed = (name) =>
  JSON.parse(readFileSync(grammarPath, "utf8"))
    .repository[name].patterns[0].match.match(/\(([A-Z|]+)\)/)[1]
    .split("|");
check("la grammaire ne liste pas d'autre mnémonique",
  listed("keywords").filter((w) => !mnemonics.includes(w)).join(",") || "aucun", "aucun");
check("ni d'autre registre",
  listed("registers").filter((w) => !registers.includes(w)).join(",") || "aucun", "aucun");

// ── La forme d'un nom ───────────────────────────────────────────────
// Pas de liste écrite à la main de ce qui est un nom valide : on demande au
// vrai analyseur, et on exige que la grammaire dise la même chose.

console.log("\nCe que le serveur accepte comme nom, la grammaire le colore");
const candidates = [
  "boucle", "n", "total2", "compteur_1", "_x", "numéro", "numéro",
  "Ç", "2ecart", "INP",
  // Les deux côtés du renommage de la v0.7.0 : SI est réservé, IX ne l'est
  // plus et redevient un nom ordinaire. Une grammaire restée à IX échoue
  // deux fois ici.
  "SI", "IX",
];
for (const name of candidates) {
  const source = `${name}: DAT 1\n        HLT\n`;
  const accepte = pipeline.parse(source).diagnostics.toArray().length === 0;
  const colore = scopeOf(`${name}: DAT 1`, name) === "entity.name.label.lmc";
  check(`${JSON.stringify(name)} : serveur ${accepte ? "oui" : "non"}`, colore, accepte);
}

// ── Le reste de la ligne ────────────────────────────────────────────

console.log("\nLe reste");
check("l'adressage indexé garde ses crochets",
  scopes("        LDA lst[SI]").map(([, s]) => s).join(" "),
  "keyword.control.lmc variable.other.lmc punctuation.section.brackets.lmc variable.language.register.lmc punctuation.section.brackets.lmc");
check("une chaîne est une chaîne", scopeOf('        DAT "ABCD"', '"ABCD"'), "string.quoted.double.lmc");
check("un guillemet non fermé est signalé", scopeOf('        DAT "ABCD', '"ABCD'), "invalid.illegal.unterminated-string.lmc");
check("// ouvre un commentaire", scopeOf("        LDA n // note", "// note"), "comment.line.double-slash.lmc");
check("; n'en ouvre pas", scopeOf("        LDA n ; note", "; note"), "aucune");
check("un mnémonique n'est pas un préfixe", scopeOf("        LDA INPUT", "INPUT"), "variable.other.lmc");

console.log(failures === 0 ? "\nTout est passé.\n" : `\n${failures} problème(s).\n`);
process.exit(failures === 0 ? 0 : 1);
