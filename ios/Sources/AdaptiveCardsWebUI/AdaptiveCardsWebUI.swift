// wasm-port: cross-platform renderer scaffold for Swift -> WebAssembly +
// browser DOM. Parallel sibling to AdaptiveCardsCrossUI on the windows-port
// branch. Phase W1 stood up the empty module + JavaScriptKit dep. Phase
// W1.5 wires the shared `AdaptiveCardsRenderingIR` target so the
// RenderingNode IR types are visible from here without pulling in any
// platform-specific View code. Walking the IR into actual DOM elements
// lands in Phase W2 onward.
//
// On platforms that do not have JavaScriptKit (i.e. anything other than the
// WASM SDK build), the JS-specific code below compiles down to an empty
// module so the existing iOS / macOS package build remains unaffected.

import AdaptiveCardsRenderingIR

/// Re-export of the shared IR root type so downstream call sites can write
/// `WebUIRenderingNode` without an extra import. The W2 DOM walker will be
/// implemented as an extension on this typealias.
public typealias WebUIRenderingNode = RenderingNode

#if canImport(JavaScriptKit)
import JavaScriptKit
import ACCore

/// Entry point marker for the WebUI renderer. The real renderer (W2 onward)
/// walks a ``RenderingNode`` tree into DOM elements via JavaScriptKit. For
/// W1.5 we only assert the module loads, can see the host JS global, and
/// links cleanly against the shared IR target.
public enum AdaptiveCardsWebUI {
    /// Library version string. Bumped alongside docs/wasm-port.md at each
    /// phase commit so a host can sanity-check what it imported.
    public static let version = "0.5.0-wasm-port-W5"

    /// Smoke-call from a host page: returns the documentURI of the loaded
    /// document. Used by the W8 demo to confirm the module instantiated
    /// correctly under wasi shim + JavaScriptKit.
    public static func hostDocumentURI() -> String {
        let document = JSObject.global.document
        return document.documentURI.string ?? "<unavailable>"
    }
}
#endif
