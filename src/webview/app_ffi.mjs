// Browser-side FFI for the emulator webview — DOM rendering + the VS Code
// webview <-> extension host postMessage bridge. Runs inside the sandboxed
// webview iframe, not Node (contrast with lsp_ffi-style FFI in lmc_lsp,
// which is Node stdio). Declared from src/webview/ffi.gleam.

// ---- Mutable ref (Gleam is purely functional) --------------------------

export function ref(value) {
  return { current: value };
}
export function deref(r) {
  return r.current;
}
export function setRef(r, value) {
  r.current = value;
}

// ---- VS Code webview API -------------------------------------------------

const vscode = acquireVsCodeApi();

export function postToHost(json) {
  vscode.postMessage(JSON.parse(json));
}

export function onHostMessage(handler) {
  window.addEventListener("message", (event) => {
    handler(JSON.stringify(event.data));
  });
}

// ---- Event listeners ------------------------------------------------------

export function onStepClick(handler) {
  document.getElementById("step").addEventListener("click", () => handler());
}

export function onRunClick(handler) {
  document.getElementById("run").addEventListener("click", () => handler());
}

export function onResetClick(handler) {
  document.getElementById("reset").addEventListener("click", () => handler());
}

export function onInputSubmit(handler) {
  const form = document.getElementById("input-form");
  const field = document.getElementById("input-value");
  form.addEventListener("submit", (event) => {
    event.preventDefault();
    const value = parseInt(field.value, 10);
    if (!Number.isNaN(value)) {
      handler(value);
      field.value = "";
    }
  });
}

export function onAssembleClick(handler) {
  document.getElementById("assemble").addEventListener("click", () => handler());
}

export function onLoadClick(handler) {
  document.getElementById("load").addEventListener("click", () => handler());
}

export function onMailboxClick(handler) {
  document.getElementById("memory").addEventListener("click", (event) => {
    const cell = event.target.closest("[data-address]");
    if (cell) handler(parseInt(cell.dataset.address, 10));
  });
}

// ---- Rendering --------------------------------------------------------

let memoryCellsBuilt = false;

export function render(json) {
  const state = JSON.parse(json);
  renderLabels(state);
  renderMemory(state);
  renderRegisters(state);
  renderCycleEvents(state);
  renderOutput(state);
  renderScreen(state);
  renderStatus(state);
  renderInput(state);
  renderError(state);
}

/// Le texte fixe du panneau : boutons, titres, légendes, infobulles. Il
/// n'est plus écrit dans index.html mais rendu par `webview/text.gleam`,
/// dans la langue que l'hôte a réglée — sans quoi il n'y aurait qu'une
/// langue possible, celle du HTML.
///
/// `textContent` et non `innerHTML` : ce sont des phrases, pas du balisage,
/// et le titre en gras d'une infobulle est déjà un <strong> dans le HTML.
function renderLabels(state) {
  const ui = state.ui ?? {};
  for (const el of document.querySelectorAll("[data-ui]")) {
    const value = ui[el.dataset.ui];
    if (value !== undefined) el.textContent = value;
  }
  // L'étiquette d'accessibilité du canvas n'est pas du contenu : elle se
  // pose en attribut.
  for (const el of document.querySelectorAll("[data-ui-aria]")) {
    const value = ui[el.dataset.uiAria];
    if (value !== undefined) el.setAttribute("aria-label", value);
  }
  // La langue du document suit, pour la césure et les lecteurs d'écran.
  if (state.locale) document.documentElement.lang = state.locale;
}

function renderMemory(state) {
  const grid = document.getElementById("memory");
  if (!memoryCellsBuilt) {
    grid.innerHTML = "";
    for (let addr = 0; addr < 100; addr++) {
      const cell = document.createElement("div");
      cell.className = "mailbox";
      cell.dataset.address = String(addr);
      cell.innerHTML =
        `<span class="addr">${addr}</span><span class="value">0</span>`;
      grid.appendChild(cell);
    }
    memoryCellsBuilt = true;
  }

  const memory = state.memory ?? new Array(100).fill(0);
  const programLength = state.programLength ?? 0;
  const dataAddresses = new Set(state.dataAddresses ?? []);
  const cells = grid.children;
  for (let addr = 0; addr < cells.length; addr++) {
    const cell = cells[addr];
    cell.querySelector(".value").textContent = String(memory[addr]);
    // currentAddress: the mailbox the machine is executing/paused on.
    // cursorAddress: where the *editor's* cursor is, independent of
    // execution — a separate, lighter highlight (see style.css).
    cell.classList.toggle("current", addr === state.currentAddress);
    cell.classList.toggle("cursor", addr === state.cursorAddress);
    // Trois zones, qui sont l'image mémoire elle-même : le programme en bas,
    // la pile en haut, et le vide entre les deux. Tout ce qui est au-dessus
    // de SP a été empilé — c'est ce qui rend visible la pile qui descend
    // pendant une récursion.
    const stacked =
      state.sp !== null && state.sp !== undefined && addr > state.sp;
    cell.classList.toggle("stack", stacked);
    // À l'intérieur du programme, les cases réservées par un DAT. Le
    // marquage vient du source, pas de la machine : voir
    // model.data_addresses et le commentaire de .mailbox.data dans
    // style.css. Cédé à la pile en cas de recouvrement — un débordement
    // est ce qu'il faut voir en premier.
    cell.classList.toggle("data", dataAddresses.has(addr) && !stacked);
    // Dim cells the assembled program never touches, so attention goes to
    // the handful that matter instead of all 100 looking equally relevant.
    cell.classList.toggle("unused", addr >= programLength && !stacked);
  }
}

function renderRegisters(state) {
  for (const name of ["acc", "pc", "x", "lr", "sp"]) {
    const value = state[name];
    document.getElementById(name).textContent =
      value === null || value === undefined ? "—" : String(value);
  }
}

// One <li> per *phase* (Fetch, Decode, Execute — never more than three),
// not one per event. A single Execute can produce several events (e.g.
// INP resuming: "waiting", then "ACC <- input", then "ACC changed") — if
// each got its own top-level <li> labeled "Execute", it would read as
// three separate Execute phases and undermine the point of this panel.
// Those go in a nested list under the one "Execute" entry instead.
function renderCycleEvents(state) {
  const list = document.getElementById("cycle-events");
  list.innerHTML = "";
  for (const phase of state.cycle ?? []) {
    const li = document.createElement("li");
    const label = document.createElement("strong");
    label.textContent = phase.phase;
    li.appendChild(label);
    if (phase.details.length <= 1) {
      li.appendChild(document.createTextNode(" — " + (phase.details[0] ?? "")));
    } else {
      const sub = document.createElement("ul");
      for (const detail of phase.details) {
        const subLi = document.createElement("li");
        subLi.textContent = detail;
        sub.appendChild(subLi);
      }
      li.appendChild(sub);
    }
    list.appendChild(li);
  }
}

function renderOutput(state) {
  const list = document.getElementById("output");
  list.innerHTML = "";
  for (const value of state.output ?? []) {
    const li = document.createElement("li");
    li.textContent = String(value);
    list.appendChild(li);
  }
}

// La palette, et le seul endroit où elle existe. model.gleam sait qu'il y a
// huit couleurs et que la 0 est le fond ; ce qu'elles valent en RVB ne le
// regarde pas — un écran est un périphérique. La légende sous le canvas est
// construite à partir de ce même tableau, sinon elle finirait par annoncer
// des couleurs qui ne sont plus peintes.
const PALETTE = [
  "#12121a", // 0 — le fond : allumer un point en 0, c'est l'éteindre
  "#e05252", // 1 — rouge
  "#4caf50", // 2 — vert
  "#4a8cf7", // 3 — bleu
  "#e0c14c", // 4 — jaune
  "#c264d0", // 5 — magenta
  "#4fc3d4", // 6 — cyan
  "#eceff4", // 7 — blanc
];

const PALETTE_NAMES = [
  "fond",
  "rouge",
  "vert",
  "bleu",
  "jaune",
  "magenta",
  "cyan",
  "blanc",
];

let paletteBuilt = false;

function renderScreen(state) {
  const canvas = document.getElementById("screen");
  if (!canvas) return;
  const ctx = canvas.getContext("2d");
  // jsdom n'a pas de canvas 2d sans dépendance native : le reste de la page
  // doit continuer à se rendre pour que smoke-webview.mjs serve à quelque
  // chose. La légende, elle, est du vrai DOM et reste vérifiable.
  if (ctx) {
    ctx.fillStyle = PALETTE[0];
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    for (const point of state.screen ?? []) {
      ctx.fillStyle = PALETTE[point.c] ?? PALETTE[0];
      // Un point du programme est un pixel du canvas ; c'est le CSS qui
      // agrandit, pas nous.
      ctx.fillRect(point.x, point.y, 1, 1);
    }
  }

  if (!paletteBuilt) {
    const legend = document.getElementById("palette");
    if (legend) {
      legend.innerHTML = "";
      PALETTE.forEach((colour, index) => {
        const li = document.createElement("li");
        const swatch = document.createElement("span");
        swatch.className = "pal-swatch";
        swatch.style.background = colour;
        li.appendChild(swatch);
        li.appendChild(document.createTextNode(`${index} ${PALETTE_NAMES[index]}`));
        legend.appendChild(li);
      });
      paletteBuilt = true;
    }
  }
}

function renderStatus(state) {
  const label = document.getElementById("status");
  label.textContent = state.status ?? "—";
  label.className = "status status-" + (state.status ?? "none");
  const canStep = state.status === "running";
  document.getElementById("step").disabled = !canStep;
  document.getElementById("run").disabled = !canStep;
  // Rien en RAM : rien à remettre à zéro non plus.
  document.getElementById("reset").disabled = state.status === "empty";
  // Pas d'assemblage, pas de fichier objet à produire — et rien à charger.
  document.getElementById("assemble").disabled = !state.assembled;
}

function renderInput(state) {
  document.getElementById("input-form").style.display =
    state.status === "waiting_input" ? "flex" : "none";
}

function renderError(state) {
  const banner = document.getElementById("error");
  if (state.loadError) {
    banner.textContent = state.loadError;
    banner.style.display = "block";
  } else {
    banner.style.display = "none";
  }
}
