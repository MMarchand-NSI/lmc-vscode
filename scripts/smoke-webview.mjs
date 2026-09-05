#!/usr/bin/env node
// Drives the *built* emulator webview in a real DOM, playing the extension
// host's half of the protocol, and checks what comes out.
//
// Why this exists: every webview bug this project has had lived at the
// impure boundary — a stale TextEditor reference, mutable DOM, a bundle
// built before `gleam build` had copied the FFI across — and `gleam test`
// cannot see any of it. It covers model.gleam and render.gleam, which have
// never had a bug of that kind. This covers the part that has.
//
// It is not a replacement for opening the panel in a real Extension
// Development Host: it stubs `acquireVsCodeApi`, so it says nothing about
// CSP, about webviewPanel.ts's placeholder substitution, or about how any
// of it actually looks. It answers a narrower question — does the bundle
// load, does the assemble/load/execute pipeline still work end to end, and
// is everything still in the frame it belongs to.
//
// Usage: gleam build && node scripts/build-webview.mjs && node scripts/smoke-webview.mjs

import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const webviewDir = join(root, "vscode-extension", "webview");

// jsdom is a devDependency of vscode-extension/, where this project's
// node_modules lives — same arrangement build-webview.mjs uses for esbuild.
let JSDOM;
try {
  const require = createRequire(
    pathToFileURL(join(root, "vscode-extension", "package.json")),
  );
  ({ JSDOM } = require("jsdom"));
} catch {
  console.error(
    "jsdom introuvable. Lancez `npm install` dans vscode-extension/.",
  );
  process.exit(1);
}

// ── Assertions ────────────────────────────────────────────────────

let failures = 0;
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  if (!ok) failures++;
  const shown = ok ? String(actual) : `${actual}   (attendu : ${expected})`;
  console.log(`  ${ok ? "ok  " : "ECHEC"} ${label.padEnd(46)} ${shown}`);
}

// ── Le panneau, et l'hôte simulé ──────────────────────────────────

/// Substitutes index.html's placeholders the way webviewPanel.ts does, loads
/// the built bundle, and returns a driver exposing the two things the host
/// really does: send messages in, and answer the ones that come out.
function openPanel() {
  const html = readFileSync(join(webviewDir, "index.html"), "utf8").replace(
    /\{\{\w+\}\}/g,
    "x",
  );
  const dom = new JSDOM(html, {
    runScripts: "outside-only",
    pretendToBeVisual: true,
  });
  const w = dom.window;
  const posted = [];
  w.acquireVsCodeApi = () => ({
    postMessage: (m) => posted.push(m),
    getState: () => undefined,
    setState: () => {},
  });
  // jsdom n'a pas de contexte 2d sans la dépendance native `canvas`, et sa
  // console virtuelle recrache une trace complète à chaque appel — soit une
  // par rendu, ce qui noierait la sortie de ce script. On rend donc null,
  // ce que la page doit de toute façon savoir encaisser ; la section
  // « Écran » remplace ensuite ce null par un faux contexte qui note ce
  // qu'on lui demande de peindre.
  w.HTMLCanvasElement.prototype.getContext = () => null;
  w.eval(readFileSync(join(webviewDir, "app.bundle.js"), "utf8"));
  w.eval("LmcApp.main();");

  // The object file, as the host would hold it on disk: null until the
  // webview has asked for one to be written. That `null` is what makes
  // "load before assembling" testable at all.
  let disk = null;

  const settle = () => new Promise((r) => setTimeout(r, 40));
  const drain = async () => {
    for (const m of posted.splice(0)) {
      if (m.type === "objectCode") disk = m.content;
      if (m.type === "requestLoad") {
        w.postMessage(
          disk === null
            ? { type: "objectLoadFailed", message: "pas de fichier objet" }
            : { type: "objectLoaded", content: disk },
          "*",
        );
      }
    }
    await settle();
  };

  return {
    window: w,
    document: w.document,
    id: (name) => w.document.getElementById(name),
    text: (name) => w.document.getElementById(name).textContent.trim(),
    async send(message) {
      w.postMessage(message, "*");
      await settle();
      await drain();
    },
    async click(id) {
      w.document.getElementById(id).dispatchEvent(new w.Event("click"));
      await drain();
    },
    get objectFile() {
      return disk;
    },
    set objectFile(content) {
      disk = content;
    },
    cellsWithClass: (cls) =>
      [...w.document.querySelectorAll(".mailbox")].filter((c) =>
        c.classList.contains(cls),
      ).length,
    bannerVisible: () =>
      w.document.getElementById("error").style.display !== "none",
  };
}

// ── Le parcours assembler -> charger -> exécuter ──────────────────

async function pipeline() {
  console.log("\nParcours complet, sur examples/tableau.lmc");
  const p = openPanel();
  const source = readFileSync(join(root, "examples", "tableau.lmc"), "utf8");
  await p.send({ type: "setSource", source });

  check("à l'ouverture, la RAM est vide", p.text("status"), "vide");
  check("aucune case marquée comme programme", p.cellsWithClass("unused"), 100);
  check("Step est désactivé", p.id("step").disabled, true);

  await p.click("load");
  check("charger sans assembler échoue", p.bannerVisible(), true);
  check("et ne remplit rien", p.text("status"), "vide");

  await p.click("assemble");
  const words = p.objectFile.split("\n").filter(Boolean);
  check("assembler écrit le fichier objet", words.length, 28);
  check("quatre chiffres par ligne", words.every((x) => /^\d{4}$/.test(x)), true);
  check("mais ne charge toujours rien", p.text("status"), "vide");

  await p.click("load");
  check("charger remplit la RAM", p.text("status"), "running");
  check("PC au début du programme", p.text("pc"), "0");
  check("le bandeau d'erreur disparaît", p.bannerVisible(), false);

  await p.click("run");
  const output = [...p.document.querySelectorAll("#output li")]
    .map((li) => li.textContent)
    .join(" ");
  check("Run va jusqu'au bout", p.text("status"), "halted");
  check("et produit la bonne sortie", output, "12 4 86 7 109");

  await p.click("reset");
  check("Reset revient à l'image chargée", p.text("pc"), "0");

  // Éditer le source réassemble sans toucher à la RAM : c'est tout le sens
  // du découpage, et la seule chose qu'un test de rendu peut en dire.
  await p.send({ type: "setSource", source: "INP\nOUT\nHLT\n" });
  check("éditer le source ne recharge pas", p.text("status"), "running");
  check("la RAM garde l'ancien programme", p.cellsWithClass("unused"), 72);

  p.objectFile = "5019\ncoucou\n0000\n";
  await p.click("load");
  check("un fichier objet illisible est refusé", p.bannerVisible(), true);
}

// ── Le découpage von Neumann ──────────────────────────────────────

async function frames() {
  console.log("\nDécoupage de l'interface");
  const p = openPanel();
  const frameOf = (name) => {
    const el = p.id(name);
    if (!el) return "(absent du DOM)";
    const unit = el.closest(".unit");
    if (unit) return unit.className.replace("unit ", "");
    if (el.closest(".toolbar")) return "barre";
    return "racine";
  };
  const group = (names) => names.map(frameOf).join(",");

  check("les cinq registres sont dans le processeur",
    group(["acc", "pc", "x", "lr", "sp"]), "cpu,cpu,cpu,cpu,cpu");
  check("l'entrée et la sortie sont ensemble",
    group(["input-form", "input-value", "output"]), "io,io,io");
  check("la mémoire est dans son cadre", frameOf("memory"), "memory-wrap");
  check("les commandes sont hors des cadres",
    group(["step", "run", "reset", "assemble", "load", "status"]),
    "barre,barre,barre,barre,barre,barre");
}

// ── Infobulles et légende ─────────────────────────────────────────

async function annotations() {
  console.log("\nInfobulles et légende");
  const p = openPanel();
  const rows = [...p.document.querySelectorAll(".register")];

  check("chaque ligne de registre a son infobulle",
    rows.filter((r) => r.querySelector(".tip")).length, rows.length);
  // Une infobulle native en plus de la nôtre en afficherait deux.
  check("aucun title= résiduel",
    p.document.querySelectorAll("[title]").length, 0);
  check("chaque bulle développe son sigle",
    rows.every((r) => r.querySelector(".tip strong")), true);
  check("la légende a ses quatre entrées",
    p.document.querySelectorAll(".legend li").length, 4);
  // Les pastilles portent les mêmes classes que les cases : si quelqu'un
  // renomme une zone d'un seul côté, la légende ment. C'est ici que ça se voit.
  check("ses pastilles reprennent les classes des cases",
    [...p.document.querySelectorAll(".legend .swatch")]
      .map((s) => s.className).join(" "),
    "swatch swatch data swatch stack swatch unused");
}

// ── L'écran ───────────────────────────────────────────────────────

async function screen() {
  console.log("\nÉcran (PLT), sur examples/ecran.lmc");
  const p = openPanel();
  const canvas = p.id("screen");

  check("le canvas est une sortie, avec OUT",
    canvas.closest(".unit").className.replace("unit ", ""), "io");
  // 32 pixels réels agrandis par le CSS : un point du programme est un pixel
  // du canvas, sans arithmétique nulle part. Si ces deux nombres bougent
  // sans que model.screen_width suive, l'écran se met à mentir.
  check("32 pixels réels de côté",
    `${canvas.width}x${canvas.height}`, "32x32");
  check("la palette annonce ses huit couleurs",
    p.document.querySelectorAll("#palette li").length, 8);
  check("et dit que l'index 0 est le fond",
    p.document.querySelector("#palette li").textContent, "0 fond");
  check("l'écran a son infobulle",
    !!p.document.querySelector(".screen-part .tip strong"), true);

  // jsdom n'implémente pas le contexte 2d. On en pose un faux, qui note ce
  // qu'on lui demande de peindre : c'est le seul moyen de vérifier que
  // l'écran est repeint pour de bon, et c'est très exactement la frontière
  // impure que ce script existe pour couvrir.
  const painted = [];
  const ctx = {
    fillStyle: "",
    fillRect(x, y, w, h) {
      painted.push({ x, y, w, h, fill: this.fillStyle });
    },
  };
  canvas.getContext = () => ctx;

  const source = readFileSync(join(root, "examples", "ecran.lmc"), "utf8");
  await p.send({ type: "setSource", source });
  await p.click("assemble");
  await p.click("load");
  await p.click("run");
  check("le programme va jusqu'au bout", p.text("status"), "halted");

  // Chaque rendu repeint le fond d'abord — un rectangle de 32 de large —
  // puis pose les points. Le dernier fond commence donc la dernière image.
  const start = painted.map((r) => r.w).lastIndexOf(32);
  const frame = painted.slice(start + 1);
  check("le fond est repeint avant les points", start >= 0, true);
  check("la dernière image allume 32 points", frame.length, 32);
  check("un point est un pixel, pas un carré mis à l'échelle",
    frame.every((r) => r.w === 1 && r.h === 1), true);
  check("la diagonale part de l'origine",
    `${frame[0].x},${frame[0].y}`, "0,0");
  check("la ligne horizontale est posée en y = 20",
    frame.filter((r) => r.y === 20).length, 16);
  check("les deux traits ont deux couleurs",
    new Set(frame.map((r) => r.fill)).size, 2);
}

// ── ─────────────────────────────────────────────────────────────────

await pipeline();
await frames();
await annotations();
await screen();

console.log(
  failures === 0
    ? "\nTout est passé.\n"
    : `\n${failures} vérification(s) en échec.\n`,
);
process.exit(failures === 0 ? 0 : 1);
