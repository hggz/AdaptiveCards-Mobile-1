// wasm-port: Phase W2 — first IR -> DOM walker. Renders the five
// foundational `RenderingNode` cases (`.text`, `.richRun`, `.image`,
// `.verticalStack`, `.horizontalStack`) via JavaScriptKit's binding to
// `document.createElement` and friends. Every other case currently
// produces a placeholder `<div class="ac-unsupported" data-ac-node="…">`
// that subsequent phases (W3–W7) will replace with real renderings.
//
// Design rules carried over from windows-port's `AdaptiveCardView.swift`:
//   * The walker NEVER touches the `RenderingNode` IR — it only reads it.
//     The IR is the contract shared with windows-port via the
//     `AdaptiveCardsRenderingIR` target.
//   * Style is applied via CSS classes (`ac-*`) AND inline styles for the
//     handful of properties (`white-space`, `display: flex`, `gap`) that
//     are intrinsic to the layout semantics. Hosts can override anything
//     via their own stylesheet using the `data-ac-node` attribute and
//     `ac-*` class selectors.
//   * Action routing is NOT done here. Phase W3 introduces an
//     ``ActionDispatcher`` protocol; demos and host adapters supply the
//     concrete behaviour (the windows-port equivalent is
//     `ShellExecuteW` for `Action.OpenUrl`).
//
// JavaScriptKit interop notes:
//   * Every JS call returns a `JSValue` whose `.object` getter unwraps
//     to a `JSObject`. We force-unwrap with `!` only on calls whose JS
//     contract guarantees a non-null result (e.g. `document.createElement`).
//   * Properties set via dynamic member assignment (`element.className = …`)
//     are coerced through ``ConvertibleToJSValue``; plain `String` works.
//   * Method calls go through the function-call subscript on `JSObject`
//     (`element.setAttribute("k", "v")`); the return value is discarded.

#if canImport(JavaScriptKit)
import JavaScriptKit
import AdaptiveCardsRenderingIR

/// IR -> DOM walker. Stateless aside from the cached `document` reference
/// so the walker is safe to reuse across many cards within a single page.
public struct DOMRenderer {

    /// The `document` JS object the walker writes into. Defaults to the
    /// page-global `document`; tests may inject a `JSDOM`-style stub.
    public let document: JSObject

    /// Construct a renderer bound to the page-global `document`. Equivalent
    /// to ``init(document:)`` with the default value.
    public init() {
        self.document = JSObject.global.document.object!
    }

    /// Construct a renderer bound to an arbitrary `document`-like object.
    /// Used by the host-side embed examples (W10 / W11) that want to mount
    /// cards into a detached `DocumentFragment`.
    public init(document: JSObject) {
        self.document = document
    }

    /// Render `node` into `parent`, appending the produced element as
    /// `parent`'s last child. Returns the created root element so callers
    /// can hold on to it (e.g. to detach it later).
    @discardableResult
    public func render(_ node: RenderingNode, into parent: JSObject) -> JSObject {
        let element = makeElement(for: node)
        _ = parent.appendChild!(element)
        return element
    }

    /// Build the DOM subtree for `node` WITHOUT mounting it. Useful for
    /// tests that want to inspect the element shape before insertion.
    public func makeElement(for node: RenderingNode) -> JSObject {
        switch node {
        case let .text(s, size, weight, wrap, isSubtle):
            return makeTextElement(
                s, size: size, weight: weight, wrap: wrap, isSubtle: isSubtle)

        case let .richRun(s, size, weight, italic, underline, strikethrough, isSubtle):
            return makeRichRunElement(
                s,
                size: size, weight: weight,
                italic: italic, underline: underline,
                strikethrough: strikethrough, isSubtle: isSubtle)

        case let .image(url, alt, displayHint):
            return makeImageElement(url: url, alt: alt, displayHint: displayHint)

        case let .verticalStack(spacing, children):
            return makeStackElement(
                direction: .vertical, spacing: spacing, children: children)

        case let .horizontalStack(spacing, children):
            return makeStackElement(
                direction: .horizontal, spacing: spacing, children: children)

        default:
            return makeUnsupportedElement(for: node)
        }
    }

    // MARK: - Internals

    private enum StackDirection: String {
        case vertical
        case horizontal
        var cssFlexValue: String {
            switch self {
            case .vertical:   return "column"
            case .horizontal: return "row"
            }
        }
    }

    /// Create a bare element of the given tag, applying the standard
    /// `data-ac-node` attribute so downstream tests + host stylesheets
    /// have a single, stable selector for every IR case.
    private func createElement(_ tag: String, dataACNode: String) -> JSObject {
        let element = document.createElement!(tag).object!
        _ = element.setAttribute!("data-ac-node", dataACNode)
        return element
    }

    private func makeTextElement(
        _ text: String,
        size: RenderingNode.TextSize,
        weight: RenderingNode.TextWeight,
        wrap: Bool,
        isSubtle: Bool
    ) -> JSObject {
        let element = createElement("div", dataACNode: "text")
        var classes = ["ac-text",
                       "ac-text-size-\(size.rawValue)",
                       "ac-text-weight-\(weight.rawValue)"]
        if isSubtle { classes.append("ac-text-subtle") }
        element.className = JSValue.string(classes.joined(separator: " "))
        element.textContent = JSValue.string(text)
        // `whiteSpace` is the JS DOM camelCase form of CSS `white-space`.
        if let style = element.style.object {
            style.whiteSpace = JSValue.string(wrap ? "pre-wrap" : "nowrap")
        }
        return element
    }

    private func makeRichRunElement(
        _ text: String,
        size: RenderingNode.TextSize,
        weight: RenderingNode.TextWeight,
        italic: Bool,
        underline: Bool,
        strikethrough: Bool,
        isSubtle: Bool
    ) -> JSObject {
        let element = createElement("span", dataACNode: "richRun")
        var classes = ["ac-rich-run",
                       "ac-text-size-\(size.rawValue)",
                       "ac-text-weight-\(weight.rawValue)"]
        if isSubtle { classes.append("ac-text-subtle") }
        element.className = JSValue.string(classes.joined(separator: " "))
        element.textContent = JSValue.string(text)
        if let style = element.style.object {
            if italic {
                style.fontStyle = JSValue.string("italic")
            }
            var decorations: [String] = []
            if underline { decorations.append("underline") }
            if strikethrough { decorations.append("line-through") }
            if !decorations.isEmpty {
                style.textDecoration = JSValue.string(
                    decorations.joined(separator: " "))
            }
        }
        return element
    }

    private func makeImageElement(
        url: String,
        alt: String,
        displayHint: RenderingNode.ImageDisplayHint
    ) -> JSObject {
        let element = createElement("img", dataACNode: "image")
        _ = element.setAttribute!("src", url)
        _ = element.setAttribute!("alt", alt)
        element.className = JSValue.string(
            "ac-image ac-image-\(displayHint.rawValue)")
        return element
    }

    private func makeStackElement(
        direction: StackDirection,
        spacing: Int,
        children: [RenderingNode]
    ) -> JSObject {
        let element = createElement(
            "div", dataACNode: "\(direction.rawValue)Stack")
        element.className = JSValue.string(
            "ac-stack ac-\(direction.rawValue)-stack ac-spacing-\(spacing)")
        if let style = element.style.object {
            style.display = JSValue.string("flex")
            style.flexDirection = JSValue.string(direction.cssFlexValue)
            style.gap = JSValue.string("\(spacing)px")
        }
        for child in children {
            _ = element.appendChild!(makeElement(for: child))
        }
        return element
    }

    /// Catch-all for IR cases not yet implemented. The placeholder element
    /// carries enough metadata for the W10 Playwright gate to flag missing
    /// renderings, while still keeping the parent stack layout intact.
    private func makeUnsupportedElement(for node: RenderingNode) -> JSObject {
        let element = createElement("div", dataACNode: "unsupported")
        element.className = JSValue.string("ac-unsupported")
        // `String(reflecting:)` produces a stable, debuggable description
        // (e.g. "AdaptiveCardsRenderingIR.RenderingNode.facts(...)") that
        // surfaces nicely in DevTools.
        _ = element.setAttribute!(
            "data-ac-unsupported-case", String(reflecting: node))
        element.textContent = JSValue.string("[unsupported node]")
        return element
    }
}
#endif
