// wasm-port: Phase W3 — `.button` rendering + action dispatch protocol.
// Action.OpenUrl routes to `window.open(url, "_blank")`, the documented
// web analogue of the windows-port's `ShellExecuteW`. Other action kinds
// (Submit / ShowCard / Execute / ToggleVisibility / Popover / RunCommands
// / OpenUrlDialog) call into a host-supplied closure when available and
// log a structured "ac:action-unsupported" record to `console.warn`
// otherwise — same posture as the windows-port's ActionRouter.swift.
//
// The protocol stays explicit (rather than baking the policy into
// `DOMRenderer`) so example hosts in W10 / W11 can swap in their own
// dispatchers — e.g. a React host that wires Submit into a `fetch()`
// call, or a vanilla-JS host that just postMessages back to the page.

#if canImport(JavaScriptKit)
import JavaScriptKit
import AdaptiveCardsRenderingIR

/// Policy hook invoked by the DOM renderer when a `.button` (or, in W6,
/// a `.compoundButton`) is clicked. Hosts implement this to route
/// `Action.Submit` payloads, `Action.OpenUrl` URLs, and the rest of the
/// `ActionKind` family into their own runtime.
public protocol ActionDispatcher {
    /// Called from the click handler of a rendered button. Implementers
    /// must be safe to call from the JS event loop; in WASM browser hosts
    /// that means the call is single-threaded but may be invoked between
    /// other DOM events.
    func dispatch(_ kind: RenderingNode.ActionKind)
}

/// Default browser-side dispatcher. Opens URLs via `window.open`, hands
/// submit payloads to an injected closure, and logs everything else as
/// `console.warn`. Hosts that want a different policy should implement
/// `ActionDispatcher` directly rather than subclassing this one.
public final class WebActionRouter: ActionDispatcher {

    /// Closure invoked on `Action.Submit`. The `dataJSON` value is the
    /// pre-encoded payload string the renderer assembled (see W4 for the
    /// input-field collection logic that feeds it).
    public typealias SubmitHandler = (_ dataJSON: String?) -> Void

    private let submitHandler: SubmitHandler?

    /// Construct a router with an optional submit handler. Pass `nil` if
    /// the host only cares about OpenUrl; submits will still be logged
    /// to `console.warn` so they are visible in DevTools.
    public init(onSubmit submitHandler: SubmitHandler? = nil) {
        self.submitHandler = submitHandler
    }

    public func dispatch(_ kind: RenderingNode.ActionKind) {
        switch kind {
        case .openUrl(let urlString):
            // `_blank` matches windows-port's ShellExecuteW behaviour:
            // launch into the system browser. Hosts that want in-app
            // navigation can short-circuit this by implementing
            // ActionDispatcher themselves.
            let window = JSObject.global.window.object
            _ = window?.open!(urlString, "_blank")

        case .submit(let dataJSON):
            if let handler = submitHandler {
                handler(dataJSON)
            } else {
                logWarn("ac:submit", dataJSON ?? "<no-payload>")
            }

        case .showCard, .execute, .toggleVisibility,
             .popover, .runCommands, .openUrlDialog:
            logWarn("ac:action-unsupported", String(reflecting: kind))

        case .unknown(let raw):
            logWarn("ac:action-unknown", raw)
        }
    }

    private func logWarn(_ tag: String, _ detail: String) {
        let console = JSObject.global.console.object
        _ = console?.warn!(tag, detail)
    }
}
#endif
