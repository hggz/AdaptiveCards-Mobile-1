// wasm-port: Phase W9 — `AdaptiveCardsWasmCABI` executable target.
//
// Compiles to a WASM module whose exports are a stable, C-ABI surface
// for non-Swift hosts (vanilla JS in W10, TypeScript / React in W11,
// any browser-side language that can call `instance.exports.foo(...)`).
//
// Unlike windows-port's CABI this module does NOT depend on
// AdaptiveCardsWebUI or JavaScriptKit — the JS host owns the DOM walk
// over the returned `RenderingNode` IR JSON. That keeps the WASM
// payload small and the boundary surface trivially auditable.
//
// Export surface (target for the W10 export-verification node script):
//   * `ac_alloc(size: i32) -> i32`
//   * `ac_free(ptr: i32) -> void`
//   * `ac_host_render_json(cardJSONptr: i32) -> i32`
//   * `ac_last_error() -> i32`
//   * `ac_version() -> i32`
//
// Memory contract (mirrors the windows-port CABI):
//   * Strings flowing in and out are NUL-terminated UTF-8.
//   * All pointers returned to JS are produced via `dupString`
//     (malloc-copy); JS MUST release them with `ac_free` exactly once.
//   * `ac_last_error` returns the most recently set error message; the
//     pointer is valid until the next API call that may set/clear it.

import Foundation
import ACCore
import AdaptiveCardsRenderingIR

// MARK: - String marshalling helpers

/// Allocate a NUL-terminated copy of `s` via `malloc`. Caller releases
/// with `free()` / `ac_free`. Returns `nil` only on allocation failure.
private func dupString(_ s: String) -> UnsafeMutablePointer<CChar>? {
    let utf8 = Array(s.utf8) + [0]
    let len = utf8.count
    guard let raw = malloc(len) else { return nil }
    let buf = raw.assumingMemoryBound(to: UInt8.self)
    for i in 0..<len { buf[i] = utf8[i] }
    return raw.assumingMemoryBound(to: CChar.self)
}

// MARK: - Last-error storage

private var lastError: UnsafeMutablePointer<CChar>?

private func setLastError(_ message: String) {
    if let old = lastError { free(old); lastError = nil }
    lastError = dupString(message)
}

private func clearLastError() {
    if let old = lastError { free(old); lastError = nil }
}

// MARK: - C-ABI exports

/// Allocate `size` bytes inside the WASM linear memory and return a
/// pointer. Used by JS hosts to copy card JSON into WASM memory before
/// calling `ac_host_render_json`. Returns `0` (NULL) on failure.
@_cdecl("ac_alloc")
public func ac_alloc(_ size: Int) -> UnsafeMutableRawPointer? {
    return malloc(size)
}

/// Release a pointer previously returned by `ac_alloc` or by any
/// `ac_*` function whose contract says the caller owns the buffer.
@_cdecl("ac_free")
public func ac_free(_ ptr: UnsafeMutableRawPointer?) {
    if let ptr { free(ptr) }
}

/// Return the most recently set error message, or NULL when no error
/// is outstanding. The pointer is owned by the module — DO NOT free it.
@_cdecl("ac_last_error")
public func ac_last_error() -> UnsafePointer<CChar>? {
    if let p = lastError { return UnsafePointer(p) }
    return nil
}

/// Return a static, NUL-terminated version string identifying the
/// `AdaptiveCardsWasmCABI` build the host loaded. The pointer is owned
/// by the module — DO NOT free it.
private let versionString: UnsafeMutablePointer<CChar>? =
    dupString("0.9.0-wasm-port-W9")

@_cdecl("ac_version")
public func ac_version() -> UnsafePointer<CChar>? {
    if let p = versionString { return UnsafePointer(p) }
    return nil
}

/// Parse an Adaptive Card JSON document and return the canonical
/// `RenderingNode` IR encoded as a NUL-terminated UTF-8 JSON string.
/// Callers MUST release the returned pointer via `ac_free` exactly
/// once. On parse / render failure returns NULL and stores the error
/// message under `ac_last_error`.
@_cdecl("ac_host_render_json")
public func ac_host_render_json(
    _ cardJSON: UnsafePointer<CChar>?
) -> UnsafeMutablePointer<CChar>? {
    clearLastError()
    guard let cardJSON else {
        setLastError("ac_host_render_json: card JSON pointer is NULL")
        return nil
    }
    let json = String(cString: cardJSON)
    do {
        let card = try CardParser().parse(json)
        let node = Renderer().render(card: card)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(node)
        guard let str = String(data: data, encoding: .utf8) else {
            setLastError("ac_host_render_json: non-UTF8 output")
            return nil
        }
        return dupString(str)
    } catch {
        setLastError("ac_host_render_json: \(String(describing: error))")
        return nil
    }
}

// MARK: - Reactor-style main
//
// WASI binaries need a `_start` entry; the Swift runtime calls main()
// out of it. For an exports-first "reactor" module we have nothing to
// do — JS calls into the @_cdecl exports above directly. The stub
// keeps swiftpm happy as an executable target while the real surface
// is the exports table.

@main
struct AdaptiveCardsWasmCABIMain {
    static func main() {
        // Touch the version string at startup so the linker doesn't
        // garbage-collect the global behind it; calling `ac_version()`
        // here ensures the symbol survives `--gc-sections`.
        _ = ac_version()
    }
}
