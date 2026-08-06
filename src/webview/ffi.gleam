// FFI declarations for the webview's browser-side glue (DOM, VS Code
// webview postMessage bridge). Implemented in app_ffi.mjs, colocated with
// this module — same pattern lmc_lsp uses for its Node-side FFI
// (lsp/ffi.gleam + ffi_impl.mjs), just browser APIs instead of Node's.

/// Opaque mutable cell — Gleam has no mutable state of its own, but the
/// webview needs one persistent Model that DOM event handlers close over
/// and update. Same minimal ref/deref/set_ref shape lmc_lsp's lsp/ffi.gleam
/// uses for its own server state, reimplemented here rather than shared
/// across repos (lmc-vscode and lmc_lsp are meant to stay independent).
pub type Ref(a)

@external(javascript, "./app_ffi.mjs", "ref")
pub fn ref(value: a) -> Ref(a)

@external(javascript, "./app_ffi.mjs", "deref")
pub fn deref(r: Ref(a)) -> a

@external(javascript, "./app_ffi.mjs", "setRef")
pub fn set_ref(r: Ref(a), value: a) -> Nil

/// Push the current view-model JSON (see render.gleam) to the DOM. One
/// entry point, full re-render each time — the memory grid is 100 cells,
/// re-rendering all of them on every step is cheap enough that a
/// virtual-dom-style diff isn't worth the complexity here.
@external(javascript, "./app_ffi.mjs", "render")
pub fn render(json: String) -> Nil

@external(javascript, "./app_ffi.mjs", "onStepClick")
pub fn on_step_click(handler: fn() -> Nil) -> Nil

@external(javascript, "./app_ffi.mjs", "onRunClick")
pub fn on_run_click(handler: fn() -> Nil) -> Nil

@external(javascript, "./app_ffi.mjs", "onResetClick")
pub fn on_reset_click(handler: fn() -> Nil) -> Nil

@external(javascript, "./app_ffi.mjs", "onInputSubmit")
pub fn on_input_submit(handler: fn(Int) -> Nil) -> Nil

/// User clicked mailbox `address` — used to ask the extension host to
/// reveal/select the corresponding source line (editor sync).
@external(javascript, "./app_ffi.mjs", "onMailboxClick")
pub fn on_mailbox_click(handler: fn(Int) -> Nil) -> Nil

/// Raw JSON string of a message from the extension host (setSource,
/// cursorLine — see webviewPanel.ts for the protocol). Passed as a raw
/// string rather than decoded here: app.gleam owns the decode, ffi.gleam
/// stays a thin, decode-agnostic boundary.
@external(javascript, "./app_ffi.mjs", "onHostMessage")
pub fn on_host_message(handler: fn(String) -> Nil) -> Nil

/// Send a JSON string to the extension host via
/// `acquireVsCodeApi().postMessage`.
@external(javascript, "./app_ffi.mjs", "postToHost")
pub fn post_to_host(json: String) -> Nil
