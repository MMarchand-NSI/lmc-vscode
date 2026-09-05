#!/usr/bin/env node
// Vérifie les exemples `examples/unit-*.lmc` contre ce que leur en-tête
// promet. Chaque fichier annonce ses cas sous la forme
//
//     // Entrée : 3 8          Sortie : 8 3
//
// et ce script les exécute vraiment, via la dépendance `lmc_lsp` compilée.
// Les commentaires d'un exemple pédagogique sont ce que l'élève lit en
// premier ; s'ils mentent, l'exemple nuit au lieu d'aider. Les tenir à la
// main ne tient pas : les faire exécuter, si.
//
// Vérifie aussi que le formateur ne changerait rien au fichier, pour qu'un
// « Format Document » malencontreux ne réindente pas un support de cours.
//
// Demande `gleam build` d'abord (il lit build/dev/javascript, comme
// build-webview.mjs).

import { readFileSync, readdirSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const js = join(root, "build", "dev", "javascript");
if (!existsSync(js)) {
  console.error("build/dev/javascript absent : lance `gleam build` d'abord.");
  process.exit(1);
}

const pipeline = await import(join(js, "lmc_lsp/lmc/semantic/pipeline.mjs"));
const load = await import(join(js, "lmc_lsp/lmc/runner/load.mjs"));
const run = await import(join(js, "lmc_lsp/lmc/runner/run.mjs"));
const format = await import(join(js, "lmc_lsp/lmc/features/format.mjs"));
const prelude = await import(join(js, "prelude.mjs"));

const dir = join(root, "examples");
const files = readdirSync(dir)
  .filter((f) => f.startsWith("unit-") && f.endsWith(".lmc"))
  .sort();

let failures = 0;
const fail = (message) => {
  failures++;
  console.log("  ECHEC " + message);
};

for (const name of files) {
  const source = readFileSync(join(dir, name), "utf8");
  const parsed = pipeline.parse(source);

  const diagnostics = parsed.diagnostics.toArray();
  if (diagnostics.length) {
    fail(`${name} : ${diagnostics.map((d) => d.message).join(" ; ")}`);
    continue;
  }

  if (format.format(parsed.cst, format.default_options()) !== source) {
    fail(`${name} : le formateur changerait le fichier`);
  }

  // « Entrée : … » puis au moins deux espaces puis « Sortie : … ». Les deux
  // espaces séparent les colonnes de l'en-tête ; ce qui suit la sortie (une
  // remarque entre parenthèses) n'est pas repris.
  const cases = [
    ...source.matchAll(/Entrée\s*:\s*([\d ]*?)\s{2,}Sortie\s*:\s*([\d ]*)/g),
  ];
  if (cases.length === 0) {
    fail(`${name} : aucun cas « Entrée / Sortie » dans l'en-tête`);
    continue;
  }

  for (const [, given, wanted] of cases) {
    const inputs = given.trim() ? given.trim().split(/\s+/).map(Number) : [];
    const expected = wanted.trim() ? wanted.trim().split(/\s+/).map(Number) : [];

    const loaded = load.load(parsed, prelude.toList(inputs));
    if (!loaded.isOk()) {
      fail(`${name} [${inputs}] : chargement impossible`);
      continue;
    }
    const [final] = run.run_to_halt(loaded[0]);
    const output = final.output.toArray();

    if (final.status.constructor.name !== "Halted") {
      fail(`${name} [${inputs}] : ${final.status.constructor.name}`);
    } else if (String(output) !== String(expected)) {
      fail(`${name} [${inputs}] : [${output}] au lieu de [${expected}]`);
    } else {
      console.log(`  ok    ${name} [${inputs}] → [${output}]`);
    }
  }
}

console.log(
  failures === 0
    ? `\n${files.length} exemples, tout est passé.\n`
    : `\n${failures} problème(s).\n`,
);
process.exit(failures === 0 ? 0 : 1);
