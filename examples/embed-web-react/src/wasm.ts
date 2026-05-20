/**
 * wasm-port: shared WASM-module loader for the React example.
 * One singleton instance per page; AdaptiveCard components share it.
 */
import { WASI, File, OpenFile, ConsoleStdout } from "@bjorn3/browser_wasi_shim";

interface CABIExports {
  memory: WebAssembly.Memory;
  ac_alloc(size: number): number;
  ac_free(ptr: number): void;
  ac_host_render_json(ptr: number): number;
  ac_last_error(): number;
  ac_version(): number;
}

let modulePromise: Promise<WebAssembly.Instance> | null = null;

function readCString(mem: ArrayBuffer, ptr: number): string | null {
  if (!ptr) return null;
  const view = new Uint8Array(mem);
  let end = ptr;
  while (view[end] !== 0) end++;
  return new TextDecoder().decode(view.subarray(ptr, end));
}

function writeCString(exports: CABIExports, s: string): number {
  const bytes = new TextEncoder().encode(s);
  const ptr = exports.ac_alloc(bytes.length + 1);
  if (!ptr) throw new Error("ac_alloc failed");
  const view = new Uint8Array(exports.memory.buffer);
  view.set(bytes, ptr);
  view[ptr + bytes.length] = 0;
  return ptr;
}

async function loadOnce(): Promise<WebAssembly.Instance> {
  const wasi = new WASI(
    [], [],
    [
      new OpenFile(new File([])),
      ConsoleStdout.lineBuffered((m) => console.log("[ac-wasm:stdout]", m)),
      ConsoleStdout.lineBuffered((m) => console.warn("[ac-wasm:stderr]", m)),
    ]
  );
  const { instance } = await WebAssembly.instantiateStreaming(
    fetch("/ac.wasm"),
    { wasi_snapshot_preview1: wasi.wasiImport }
  );
  // Reactor-style entry; runs static initialisers.
  wasi.start({ exports: instance.exports as unknown as Record<string, unknown> });
  return instance;
}

export function getModule(): Promise<WebAssembly.Instance> {
  if (!modulePromise) modulePromise = loadOnce();
  return modulePromise;
}

/**
 * Render an Adaptive Card JSON document into a parsed `RenderingNode`
 * IR object. Throws on `ac_host_render_json` failure with the message
 * stored under `ac_last_error`.
 */
export async function renderIR(cardJSON: string): Promise<unknown> {
  const instance = await getModule();
  const exports = instance.exports as unknown as CABIExports;
  const inPtr = writeCString(exports, cardJSON);
  try {
    const outPtr = exports.ac_host_render_json(inPtr);
    if (!outPtr) {
      const errPtr = exports.ac_last_error();
      const msg =
        readCString(exports.memory.buffer, errPtr) ??
        "ac_host_render_json returned NULL";
      throw new Error(msg);
    }
    try {
      const json = readCString(exports.memory.buffer, outPtr);
      if (!json) throw new Error("empty IR JSON");
      return JSON.parse(json);
    } finally {
      exports.ac_free(outPtr);
    }
  } finally {
    exports.ac_free(inPtr);
  }
}

export async function versionString(): Promise<string> {
  const instance = await getModule();
  const exports = instance.exports as unknown as CABIExports;
  return readCString(exports.memory.buffer, exports.ac_version()) ?? "unknown";
}
