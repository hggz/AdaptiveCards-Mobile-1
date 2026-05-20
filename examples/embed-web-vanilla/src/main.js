/**
 * wasm-port: vanilla-JS host entry point.
 *
 * Loads `public/ac.wasm`, wires a minimal WASI shim, exposes the
 * `AdaptiveCardsWasmCABI` exports, populates the card-picker dropdown
 * from `public/cards/`, and re-renders into `#ac-card-mount` on each
 * selection change.
 */
import { WASI, File, OpenFile, ConsoleStdout } from "@bjorn3/browser_wasi_shim";
import { renderInto } from "./walker.js";

const CARD_FILES = [
  "simple-text.json",
  "containers.json",
  "input-form.json",
  "all-actions.json",
  "table.json",
  "rating.json",
  "edge-empty-card.json",
  "windows-extras.json",
];

const statusEl = document.getElementById("ac-status");
const pickerEl = document.getElementById("ac-card-picker");
const mountEl = document.getElementById("ac-card-mount");

for (const name of CARD_FILES) {
  const opt = document.createElement("option");
  opt.value = name;
  opt.textContent = name;
  pickerEl.appendChild(opt);
}

/** Per-card render dispatcher (kept module-scoped so picker re-renders
 *  reuse the same instance + exports). */
let instance = null;
const decoder = new TextDecoder();
const encoder = new TextEncoder();

/** Read a NUL-terminated UTF-8 string from WASM linear memory. */
function readCString(ptr) {
  if (!ptr) return null;
  const mem = new Uint8Array(instance.exports.memory.buffer);
  let end = ptr;
  while (mem[end] !== 0) end++;
  return decoder.decode(mem.subarray(ptr, end));
}

/** Write a NUL-terminated UTF-8 string into WASM memory; returns the
 *  pointer (caller must call `ac_free` once done). */
function writeCString(s) {
  const bytes = encoder.encode(s);
  const ptr = instance.exports.ac_alloc(bytes.length + 1);
  if (!ptr) throw new Error("ac_alloc failed");
  const mem = new Uint8Array(instance.exports.memory.buffer);
  mem.set(bytes, ptr);
  mem[ptr + bytes.length] = 0;
  return ptr;
}

/** Call `ac_host_render_json(cardJSON)`, returning the parsed
 *  RenderingNode IR object. Throws on parse / render failure. */
function renderIR(cardJSON) {
  const inPtr = writeCString(cardJSON);
  try {
    const outPtr = instance.exports.ac_host_render_json(inPtr);
    if (!outPtr) {
      const errPtr = instance.exports.ac_last_error();
      const msg = readCString(errPtr) ?? "ac_host_render_json returned NULL";
      throw new Error(msg);
    }
    try {
      const json = readCString(outPtr);
      return JSON.parse(json);
    } finally {
      instance.exports.ac_free(outPtr);
    }
  } finally {
    instance.exports.ac_free(inPtr);
  }
}

async function renderSelectedCard(name) {
  mountEl.replaceChildren();
  statusEl.textContent = `loading ${name}…`;
  try {
    const cardResp = await fetch(`./cards/${name}`);
    if (!cardResp.ok) throw new Error(`${name}: ${cardResp.status}`);
    const cardJSON = await cardResp.text();
    const ir = renderIR(cardJSON);
    renderInto(mountEl, ir);
    statusEl.textContent = `${name} — rendered`;
  } catch (err) {
    statusEl.textContent = `error rendering ${name}: ${err.message}`;
    console.error(err);
  }
}

async function boot() {
  // Minimal WASI shim: stdout / stderr go to the browser console; no
  // filesystem access (the card JSON is fetched separately and passed
  // in via memory).
  const wasi = new WASI(
    [],            // args
    [],            // env
    [
      new OpenFile(new File([])),
      ConsoleStdout.lineBuffered((msg) => console.log("[ac-wasm:stdout]", msg)),
      ConsoleStdout.lineBuffered((msg) => console.warn("[ac-wasm:stderr]", msg)),
    ]
  );
  const { instance: inst } = await WebAssembly.instantiateStreaming(
    fetch("./ac.wasm"),
    { wasi_snapshot_preview1: wasi.wasiImport }
  );
  instance = inst;
  // Reactor-style: `_start` is the WASI entry; calling it runs
  // AdaptiveCardsWasmCABIMain.main() once so the module's static
  // initialisers (version string, etc.) settle before we issue any
  // `ac_*` calls.
  wasi.start({ exports: inst.exports });
  const versionPtr = inst.exports.ac_version();
  statusEl.textContent =
    `wasm loaded (${readCString(versionPtr) ?? "version unknown"}); ` +
    `pick a card`;
  pickerEl.addEventListener("change", (e) =>
    renderSelectedCard(e.target.value)
  );
  // Auto-render the first card so the page isn't empty on first paint.
  renderSelectedCard(pickerEl.value);
}

boot().catch((err) => {
  statusEl.textContent = `boot failure: ${err.message}`;
  console.error(err);
});
