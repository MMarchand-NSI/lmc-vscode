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
  renderMemory(state);
  renderRegisters(state);
  renderInstruction(state);
  renderCycleEvents(state);
  renderOutput(state);
  renderStatus(state);
  renderInput(state);
  renderError(state);
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
  const cells = grid.children;
  for (let addr = 0; addr < cells.length; addr++) {
    const cell = cells[addr];
    cell.querySelector(".value").textContent = String(memory[addr]);
    // currentAddress: the mailbox the machine is executing/paused on.
    // cursorAddress: where the *editor's* cursor is, independent of
    // execution — a separate, lighter highlight (see style.css).
    cell.classList.toggle("current", addr === state.currentAddress);
    cell.classList.toggle("cursor", addr === state.cursorAddress);
    // Dim cells the assembled program never touches, so attention goes to
    // the handful that matter instead of all 100 looking equally relevant.
    cell.classList.toggle("unused", addr >= programLength);
  }
}

function renderRegisters(state) {
  document.getElementById("acc").textContent =
    state.acc === null || state.acc === undefined ? "—" : String(state.acc);
  document.getElementById("pc").textContent =
    state.pc === null || state.pc === undefined ? "—" : String(state.pc);
}

function renderInstruction(state) {
  document.getElementById("instruction").textContent = state.instructionText ?? "—";
}

function renderCycleEvents(state) {
  const list = document.getElementById("cycle-events");
  list.innerHTML = "";
  for (const line of state.events ?? []) {
    const li = document.createElement("li");
    li.textContent = line;
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

function renderStatus(state) {
  const label = document.getElementById("status");
  label.textContent = state.status ?? "—";
  label.className = "status status-" + (state.status ?? "none");
  const canStep = state.status === "running";
  document.getElementById("step").disabled = !canStep;
  document.getElementById("run").disabled = !canStep;
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
