// wasm-port: IR -> browser DOM walker. Renders `RenderingNode` trees via
// JavaScriptKit by emitting `<div>`, `<span>`, `<img>`, `<button>`, etc.
// The walker grows one phase at a time:
//
//   W2  — text, richRun, image, verticalStack, horizontalStack
//   W3  — button + ActionDispatcher wiring                     (THIS PHASE)
//   W4  — input fields + submit payload                        (next)
//   W5  — facts / code / progressBar / spinner / accordion /
//         table / rating (display)
//   W6  — chart / tabSet / compoundButton
//   W7  — carousel / list / media + WCAG pause button
//
// Design rules carried over from windows-port's `AdaptiveCardView.swift`:
//   * The walker NEVER touches the `RenderingNode` IR — it only reads it.
//     The IR is the contract shared with windows-port via the
//     `AdaptiveCardsRenderingIR` target.
//   * Style is applied via stable `ac-*` CSS classes AND minimal inline
//     styles for layout-intrinsic properties. Hosts can override anything
//     via the `data-ac-node` attribute or `ac-*` class selectors.
//   * Action routing lives in `WebActionRouter`. Hosts swap in their own
//     `ActionDispatcher` for non-default policies.
//
// JavaScriptKit interop notes:
//   * Every JS call returns a `JSValue` whose `.object` getter unwraps
//     to a `JSObject`. We force-unwrap with `!` only on calls whose JS
//     contract guarantees a non-null result (e.g. `document.createElement`).
//   * Dynamic methods (`obj.setAttribute(...)`) return
//     `Optional<callable>` from the dynamic-member lookup and MUST be
//     force-unwrapped before call: `obj.setAttribute!("k", "v")`.
//   * `JSClosure` retains itself across the JS/Swift boundary. Until W7
//     adds a renderer-scoped closure pool, button click handlers leak;
//     this is acceptable for the current single-card lifetime model.

#if canImport(JavaScriptKit)
import JavaScriptKit
import AdaptiveCardsRenderingIR

/// IR -> DOM walker. Final-class so the `dispatcher` slot can be rebound
/// without callers having to thread a fresh struct through every API.
/// Stateless aside from the cached `document` reference + the dispatcher,
/// so a single renderer is safe to reuse across many cards within a page.
public final class DOMRenderer {

    /// The `document` JS object the walker writes into. Defaults to the
    /// page-global `document`; tests may inject a `JSDOM`-style stub.
    public let document: JSObject

    /// Policy for handling button clicks. `nil` falls back to a no-op:
    /// click handlers are still attached so callers can observe via
    /// DevTools, but nothing else fires.
    public var dispatcher: (any ActionDispatcher)?

    /// Closure pool. JS-callable closures created by the walker are
    /// retained here so the `JSClosure -> JSValue` bridge survives until
    /// the renderer itself is released. W2 didn't need this; W3 onwards
    /// does once we attach `onclick` handlers.
    private var retainedClosures: [JSClosure] = []

    /// Construct a renderer bound to the page-global `document`, with no
    /// dispatcher attached.
    public init() {
        self.document = JSObject.global.document.object!
        self.dispatcher = nil
    }

    /// Construct a renderer bound to the page-global `document` and a
    /// caller-supplied dispatcher.
    public convenience init(dispatcher: any ActionDispatcher) {
        self.init()
        self.dispatcher = dispatcher
    }

    /// Construct a renderer bound to an arbitrary `document`-like object
    /// (used by host embed examples that render into a detached
    /// `DocumentFragment`).
    public init(document: JSObject, dispatcher: (any ActionDispatcher)? = nil) {
        self.document = document
        self.dispatcher = dispatcher
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

        case let .button(title, kind):
            return makeButtonElement(title: title, kind: kind)

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
    fileprivate func createElement(_ tag: String, dataACNode: String) -> JSObject {
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

    /// `.button(title, kind)` -> `<button data-ac-node="button">title</button>`
    /// with a click handler that funnels the `ActionKind` through the
    /// renderer's `dispatcher`. The action-kind tag is mirrored to a
    /// `data-ac-action-kind` attribute so end-to-end tests can assert on
    /// it without needing a live `dispatcher`.
    private func makeButtonElement(
        title: String,
        kind: RenderingNode.ActionKind
    ) -> JSObject {
        let element = createElement("button", dataACNode: "button")
        element.className = JSValue.string(
            "ac-button ac-action-\(Self.tag(for: kind))")
        _ = element.setAttribute!("type", "button")
        _ = element.setAttribute!("data-ac-action-kind", Self.tag(for: kind))
        element.textContent = JSValue.string(title)

        let closure = JSClosure { [weak self] _ in
            self?.dispatcher?.dispatch(kind)
            return .undefined
        }
        retainedClosures.append(closure)
        element.onclick = JSValue.object(closure)
        return element
    }

    /// Stable, lowercase tag string for an `ActionKind`. Mirrors the
    /// shape windows-port emits in `A11yBaselines/*.a11y.txt` so the
    /// shared baselines stay portable. Surfaced as a `data-ac-action-kind`
    /// attribute on every button so tests have a deterministic selector.
    fileprivate static func tag(for kind: RenderingNode.ActionKind) -> String {
        switch kind {
        case .submit:           return "submit"
        case .openUrl:          return "openUrl"
        case .showCard:         return "showCard"
        case .execute:          return "execute"
        case .toggleVisibility: return "toggleVisibility"
        case .popover:          return "popover"
        case .runCommands:      return "runCommands"
        case .openUrlDialog:    return "openUrlDialog"
        case .unknown:          return "unknown"
        }
    }

    /// Catch-all for IR cases not yet implemented. The placeholder element
    /// carries enough metadata for the W10 Playwright gate to flag missing
    /// renderings, while still keeping the parent stack layout intact.
    private func makeUnsupportedElement(for node: RenderingNode) -> JSObject {
        let element = createElement("div", dataACNode: "unsupported")
        element.className = JSValue.string("ac-unsupported")
        _ = element.setAttribute!(
            "data-ac-unsupported-case", String(reflecting: node))
        element.textContent = JSValue.string("[unsupported node]")
        return element
    }
}
#endif
