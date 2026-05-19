// wasm-port: IR -> browser DOM walker. Renders `RenderingNode` trees via
// JavaScriptKit by emitting `<div>`, `<span>`, `<img>`, `<button>`,
// `<input>`, `<select>`, etc. The walker grows one phase at a time:
//
//   W2 — text, richRun, image, verticalStack, horizontalStack
//   W3 — button + ActionDispatcher wiring
//   W4 — input fields + live submit-payload merge                (THIS PHASE)
//   W5 — facts / code / progressBar / spinner / accordion /
//        table / rating (display)
//   W6 — chart / tabSet / compoundButton
//   W7 — carousel / list / media + WCAG pause button
//
// Design rules carried over from windows-port's `AdaptiveCardView.swift`:
//   * The walker NEVER touches the `RenderingNode` IR — it only reads it.
//     The IR is the contract shared with windows-port via the
//     `AdaptiveCardsRenderingIR` target.
//   * Style is applied via stable `ac-*` CSS classes AND minimal inline
//     styles for layout-intrinsic properties. Hosts can override
//     anything via the `data-ac-node` attribute or `ac-*` class
//     selectors.
//   * Action routing lives in `WebActionRouter`. Hosts swap in their own
//     `ActionDispatcher` for non-default policies. Submit payloads are
//     merged with live input values inside the renderer BEFORE the
//     dispatcher sees them, so dispatchers don't need to know anything
//     about the DOM.
//
// JavaScriptKit interop notes (carried forward from earlier phases):
//   * Dynamic methods (`obj.setAttribute(...)`) return Optional<callable>
//     and MUST be force-unwrapped: `obj.setAttribute!("k", "v")`.
//   * `JSClosure` retains itself across the JS/Swift boundary. Closures
//     are stored in `retainedClosures` for the renderer's lifetime; this
//     is acceptable for the single-card model but will get a cleanup
//     hook in a later phase.

#if canImport(JavaScriptKit)
import Foundation
import JavaScriptKit
import AdaptiveCardsRenderingIR

/// IR -> DOM walker. Final-class so the `dispatcher` slot can be rebound
/// without callers having to thread a fresh struct through every API.
public final class DOMRenderer {

    /// The `document` JS object the walker writes into.
    public let document: JSObject

    /// Policy for handling button clicks. `nil` falls back to a no-op
    /// (the click handler still fires; nothing else happens).
    public var dispatcher: (any ActionDispatcher)?

    /// JS-callable closures retained for the renderer's lifetime so the
    /// `JSClosure -> JSValue` bridge survives across the JS event loop.
    private var retainedClosures: [JSClosure] = []

    /// Live input field registry. Populated as inputs are rendered;
    /// drained into the merged JSON payload on `.submit` clicks.
    private var registeredInputs: [RegisteredInput] = []

    /// Strategy record: how to read the live value of one rendered input.
    /// `read` returns nil when the field is empty / unset; `kind` controls
    /// the JSON shape (number vs. string vs. bool vs. array-of-string).
    private struct RegisteredInput {
        let id: String
        let kind: InputKind
        let read: () -> Any?
    }

    private enum InputKind {
        case string
        case number
        case bool
        case stringArray
    }

    /// Construct a renderer bound to the page-global `document`.
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

    /// Construct a renderer bound to an arbitrary `document`-like object.
    public init(document: JSObject, dispatcher: (any ActionDispatcher)? = nil) {
        self.document = document
        self.dispatcher = dispatcher
    }

    /// Render `node` into `parent`, appending the produced element.
    @discardableResult
    public func render(_ node: RenderingNode, into parent: JSObject) -> JSObject {
        let element = makeElement(for: node)
        _ = parent.appendChild!(element)
        return element
    }

    /// Build the DOM subtree for `node` WITHOUT mounting it.
    public func makeElement(for node: RenderingNode) -> JSObject {
        switch node {
        case let .text(s, size, weight, wrap, isSubtle):
            return makeTextElement(
                s, size: size, weight: weight, wrap: wrap, isSubtle: isSubtle)

        case let .richRun(s, size, weight, italic, underline, strikethrough, isSubtle):
            return makeRichRunElement(
                s, size: size, weight: weight,
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

        case let .textField(id, label, placeholder, value, isRequired, isMultiline):
            return makeTextFieldElement(
                id: id, label: label, placeholder: placeholder,
                value: value, isRequired: isRequired, isMultiline: isMultiline)

        case let .numberField(id, label, placeholder, value, isRequired):
            return makeNumberFieldElement(
                id: id, label: label, placeholder: placeholder,
                value: value, isRequired: isRequired)

        case let .toggleField(id, title, label, value, valueOn, valueOff, isRequired):
            return makeToggleFieldElement(
                id: id, title: title, label: label, value: value,
                valueOn: valueOn, valueOff: valueOff, isRequired: isRequired)

        case let .choiceField(id, label, choices, selected, isMultiSelect, isRequired):
            return makeChoiceFieldElement(
                id: id, label: label, choices: choices,
                selected: selected, isMultiSelect: isMultiSelect,
                isRequired: isRequired)

        case let .dateField(id, label, placeholder, value, isRequired):
            return makeDateOrTimeFieldElement(
                id: id, label: label, placeholder: placeholder,
                value: value, isRequired: isRequired, inputType: "date",
                dataACNode: "dateField")

        case let .timeField(id, label, placeholder, value, isRequired):
            return makeDateOrTimeFieldElement(
                id: id, label: label, placeholder: placeholder,
                value: value, isRequired: isRequired, inputType: "time",
                dataACNode: "timeField")

        case let .ratingField(id, label, value, max, isRequired):
            return makeRatingFieldElement(
                id: id, label: label, value: value,
                max: max, isRequired: isRequired)

        default:
            return makeUnsupportedElement(for: node)
        }
    }

    // MARK: - Helpers

    private enum StackDirection: String {
        case vertical, horizontal
        var cssFlexValue: String {
            self == .vertical ? "column" : "row"
        }
    }

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
            if italic { style.fontStyle = JSValue.string("italic") }
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
            guard let self else { return .undefined }
            if case .submit(let dataJSON) = kind {
                let merged = self.mergedSubmitPayload(originalJSON: dataJSON)
                self.dispatcher?.dispatch(.submit(dataJSON: merged))
            } else {
                self.dispatcher?.dispatch(kind)
            }
            return .undefined
        }
        retainedClosures.append(closure)
        element.onclick = JSValue.object(closure)
        return element
    }

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

    private func makeUnsupportedElement(for node: RenderingNode) -> JSObject {
        let element = createElement("div", dataACNode: "unsupported")
        element.className = JSValue.string("ac-unsupported")
        _ = element.setAttribute!(
            "data-ac-unsupported-case", String(reflecting: node))
        element.textContent = JSValue.string("[unsupported node]")
        return element
    }

    // MARK: - Inputs (W4)

    /// Wrap a labelled input row in the canonical
    ///   <div class="ac-input-row ac-input-<kind>"
    ///        data-ac-node="<kind>" data-ac-input-id="<id>">
    ///     <label class="ac-input-label">{label}</label>
    ///     {inputElement}
    ///   </div>
    /// shape, attaching `data-ac-required="true"` when applicable.
    private func wrapInputRow(
        id: String,
        label: String?,
        dataACNode: String,
        isRequired: Bool,
        innerInput: JSObject
    ) -> JSObject {
        let row = createElement("div", dataACNode: dataACNode)
        row.className = JSValue.string("ac-input-row ac-input-\(dataACNode)")
        _ = row.setAttribute!("data-ac-input-id", id)
        if isRequired { _ = row.setAttribute!("data-ac-required", "true") }
        if let label, !label.isEmpty {
            let labelEl = document.createElement!("label").object!
            labelEl.className = JSValue.string("ac-input-label")
            labelEl.textContent = JSValue.string(label)
            _ = labelEl.setAttribute!("for", "ac-input-\(id)")
            _ = row.appendChild!(labelEl)
        }
        _ = row.appendChild!(innerInput)
        return row
    }

    private func makeTextFieldElement(
        id: String, label: String?, placeholder: String?,
        value: String?, isRequired: Bool, isMultiline: Bool
    ) -> JSObject {
        let input: JSObject
        if isMultiline {
            input = document.createElement!("textarea").object!
            input.textContent = JSValue.string(value ?? "")
        } else {
            input = document.createElement!("input").object!
            _ = input.setAttribute!("type", "text")
            if let value { _ = input.setAttribute!("value", value) }
        }
        _ = input.setAttribute!("id", "ac-input-\(id)")
        _ = input.setAttribute!("name", id)
        if let placeholder { _ = input.setAttribute!("placeholder", placeholder) }
        if isRequired      { _ = input.setAttribute!("required", "") }
        input.className = JSValue.string("ac-input ac-input-text")

        registeredInputs.append(RegisteredInput(
            id: id, kind: .string,
            read: { [weak input] in input?.value.string }))

        return wrapInputRow(
            id: id, label: label, dataACNode: "textField",
            isRequired: isRequired, innerInput: input)
    }

    private func makeNumberFieldElement(
        id: String, label: String?, placeholder: String?,
        value: Double?, isRequired: Bool
    ) -> JSObject {
        let input = document.createElement!("input").object!
        _ = input.setAttribute!("type", "number")
        _ = input.setAttribute!("id", "ac-input-\(id)")
        _ = input.setAttribute!("name", id)
        if let value       { _ = input.setAttribute!("value", String(value)) }
        if let placeholder { _ = input.setAttribute!("placeholder", placeholder) }
        if isRequired      { _ = input.setAttribute!("required", "") }
        input.className = JSValue.string("ac-input ac-input-number")

        registeredInputs.append(RegisteredInput(
            id: id, kind: .number,
            read: { [weak input] in
                guard let raw = input?.value.string, !raw.isEmpty else { return nil }
                return Double(raw)
            }))

        return wrapInputRow(
            id: id, label: label, dataACNode: "numberField",
            isRequired: isRequired, innerInput: input)
    }

    private func makeToggleFieldElement(
        id: String, title: String, label: String?, value: Bool,
        valueOn: String, valueOff: String, isRequired: Bool
    ) -> JSObject {
        let input = document.createElement!("input").object!
        _ = input.setAttribute!("type", "checkbox")
        _ = input.setAttribute!("id", "ac-input-\(id)")
        _ = input.setAttribute!("name", id)
        if value      { _ = input.setAttribute!("checked", "") }
        if isRequired { _ = input.setAttribute!("required", "") }
        input.className = JSValue.string("ac-input ac-input-toggle")
        _ = input.setAttribute!("data-ac-value-on", valueOn)
        _ = input.setAttribute!("data-ac-value-off", valueOff)

        registeredInputs.append(RegisteredInput(
            id: id, kind: .string,
            read: { [weak input] in
                let isOn = input?.checked.boolean ?? false
                return isOn ? valueOn : valueOff
            }))

        // Toggle uses an inline title to the right of the checkbox; the
        // `label` field (when set) goes above per ACCore semantics.
        let inline = document.createElement!("span").object!
        inline.className = JSValue.string("ac-input-toggle-title")
        inline.textContent = JSValue.string(title)

        let inputAndTitle = document.createElement!("span").object!
        inputAndTitle.className = JSValue.string("ac-input-toggle-row")
        _ = inputAndTitle.appendChild!(input)
        _ = inputAndTitle.appendChild!(inline)

        return wrapInputRow(
            id: id, label: label, dataACNode: "toggleField",
            isRequired: isRequired, innerInput: inputAndTitle)
    }

    private func makeChoiceFieldElement(
        id: String, label: String?, choices: [ChoiceOption],
        selected: String?, isMultiSelect: Bool, isRequired: Bool
    ) -> JSObject {
        let select = document.createElement!("select").object!
        _ = select.setAttribute!("id", "ac-input-\(id)")
        _ = select.setAttribute!("name", id)
        if isMultiSelect { _ = select.setAttribute!("multiple", "") }
        if isRequired    { _ = select.setAttribute!("required", "") }
        select.className = JSValue.string("ac-input ac-input-choice")

        // ACCore emits a comma-separated string of selected values for
        // multi-select; honour that on the way in.
        let selectedSet: Set<String>
        if isMultiSelect {
            selectedSet = Set((selected ?? "")
                .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        } else if let selected {
            selectedSet = [selected]
        } else {
            selectedSet = []
        }

        for choice in choices {
            let option = document.createElement!("option").object!
            _ = option.setAttribute!("value", choice.value)
            option.textContent = JSValue.string(choice.title)
            if selectedSet.contains(choice.value) {
                _ = option.setAttribute!("selected", "")
            }
            _ = select.appendChild!(option)
        }

        registeredInputs.append(RegisteredInput(
            id: id,
            kind: isMultiSelect ? .stringArray : .string,
            read: { [weak select] in
                guard let select else { return nil }
                if isMultiSelect {
                    // <select multiple> exposes a `selectedOptions`
                    // HTMLCollection; walk it for the values.
                    let opts = select.selectedOptions.object
                    var out: [String] = []
                    let count = Int(opts?.length.number ?? 0)
                    for i in 0..<count {
                        if let opt = opts?[i].object,
                           let v = opt.value.string {
                            out.append(v)
                        }
                    }
                    return out
                }
                return select.value.string
            }))

        return wrapInputRow(
            id: id, label: label, dataACNode: "choiceField",
            isRequired: isRequired, innerInput: select)
    }

    private func makeDateOrTimeFieldElement(
        id: String, label: String?, placeholder: String?,
        value: String?, isRequired: Bool,
        inputType: String, dataACNode: String
    ) -> JSObject {
        let input = document.createElement!("input").object!
        _ = input.setAttribute!("type", inputType)
        _ = input.setAttribute!("id", "ac-input-\(id)")
        _ = input.setAttribute!("name", id)
        if let value       { _ = input.setAttribute!("value", value) }
        if let placeholder { _ = input.setAttribute!("placeholder", placeholder) }
        if isRequired      { _ = input.setAttribute!("required", "") }
        input.className = JSValue.string("ac-input ac-input-\(inputType)")

        registeredInputs.append(RegisteredInput(
            id: id, kind: .string,
            read: { [weak input] in input?.value.string }))

        return wrapInputRow(
            id: id, label: label, dataACNode: dataACNode,
            isRequired: isRequired, innerInput: input)
    }

    private func makeRatingFieldElement(
        id: String, label: String?, value: Double,
        max: Int, isRequired: Bool
    ) -> JSObject {
        // v1 renders rating as a single <input type="range">. The IR
        // comment calls for a row of star buttons; that promotion is a
        // later refinement (closer to W5's display rating). The wire
        // value is identical (a Double in 0...max), so dispatchers and
        // baselines don't care which representation we use here.
        let input = document.createElement!("input").object!
        _ = input.setAttribute!("type", "range")
        _ = input.setAttribute!("id", "ac-input-\(id)")
        _ = input.setAttribute!("name", id)
        _ = input.setAttribute!("min", "0")
        _ = input.setAttribute!("max", String(max))
        _ = input.setAttribute!("step", "1")
        _ = input.setAttribute!("value", String(Int(value.rounded())))
        if isRequired { _ = input.setAttribute!("required", "") }
        input.className = JSValue.string("ac-input ac-input-rating")

        registeredInputs.append(RegisteredInput(
            id: id, kind: .number,
            read: { [weak input] in
                guard let raw = input?.value.string, !raw.isEmpty else { return nil }
                return Double(raw)
            }))

        return wrapInputRow(
            id: id, label: label, dataACNode: "ratingField",
            isRequired: isRequired, innerInput: input)
    }

    // MARK: - Submit payload merge (W4)

    /// Read all registered input live values and merge them into
    /// `originalJSON` (parsed as a JSON object). Inputs override
    /// pre-existing keys; missing inputs are skipped. Returns a JSON
    /// string suitable for `Action.Submit.data` consumption.
    ///
    /// Mirrors the windows-port's `SubmitPayload.merge(...)` semantics
    /// — see `AdaptiveCardsRenderingIR/SubmitPayload.swift`.
    private func mergedSubmitPayload(originalJSON: String?) -> String {
        var merged: [String: Any] = [:]
        if let originalJSON,
           let data = originalJSON.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data),
           let obj = parsed as? [String: Any] {
            merged = obj
        }
        for entry in registeredInputs {
            if let value = entry.read() {
                merged[entry.id] = value
            }
        }
        if let outData = try? JSONSerialization.data(
            withJSONObject: merged, options: [.sortedKeys]),
           let outStr = String(data: outData, encoding: .utf8) {
            return outStr
        }
        return originalJSON ?? "{}"
    }
}
#endif
