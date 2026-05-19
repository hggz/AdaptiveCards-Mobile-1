// wasm-port: cross-platform renderer scaffold for Swift -> WebAssembly +
// browser DOM. Parallel sibling to AdaptiveCardsCrossUI on the windows-port
// branch. Phase W1 is the skeleton only: it declares the module and pins
// the JavaScriptKit DOM bridge as a gated dependency. Walking the
// RenderingNode IR into DOM elements lands in Phase W2.
//
// On platforms that do not have JavaScriptKit (i.e. anything other than the
// WASM SDK build), the target compiles down to an empty module so the
// existing iOS/macOS package build remains unaffected.

#if canImport(JavaScriptKit)
import JavaScriptKit
import ACCore

/// Entry point marker for the WebUI renderer. The real renderer (W2 onward)
/// walks an ACCore parsed AdaptiveCard / RenderingNode IR into DOM
/// elements via JavaScriptKit. For W1 we only assert the module loads and
/// can see the host JS global, which is the minimum signal that the
/// JavaScriptKit bridge is wired correctly end-to-end.
public enum AdaptiveCardsWebUI {
    /// Library version string. Bumped alongside docs/wasm-port.md at each
    /// phase commit so a host can sanity-check what it imported.
    public static let version = "0.1.0-wasm-port-W1"

    /// Smoke-call from a host page: returns the documentURI of the loaded
    /// document. Used by the W1 demo (added in W8) to confirm the module
    /// instantiated correctly under wasi shim + JavaScriptKit.
    public static func hostDocumentURI() -> String {
        let document = JSObject.global.document
        return document.documentURI.string ?? "<unavailable>"
    }
}
#endif
