//
//  AdaptiveCardView.swift
//  AdaptiveCardsCrossUI — windows-port
//
//  Thin walker that turns a `RenderingNode` tree into a swift-cross-ui
//  view hierarchy. All element-by-element semantics live in `Renderer`;
//  this file only knows how to draw a `RenderingNode` and to thread
//  interactive input state through to the `Action.Submit` payload.
//
//  The view owns three `@State` dictionaries (text, toggle, choice)
//  keyed by Adaptive Cards input `id`. On every render the live values
//  are read back through `Binding`s; on every `Action.Submit` press the
//  collected state is merged with the action's static `data` and emitted
//  through `onAction` as canonical JSON.
//

import Foundation
import ACCore

#if canImport(SwiftCrossUI)
import SwiftCrossUI

/// Top-level view that renders a parsed `AdaptiveCard`.
///
/// Usage from a swift-cross-ui `App`:
/// ```swift
/// WindowGroup("Adaptive Cards") {
///     AdaptiveCardView(card: parsedCard) { action in
///         if case let .submit(json) = action { print(json ?? "<nil>") }
///     }
/// }
/// ```
public struct AdaptiveCardView: View {
    private let tree: RenderingNode
    private let onAction: (@MainActor @Sendable (RenderingNode.ActionKind) -> Void)?

    // Live form state. Keyed by Adaptive Cards input `id`.
    @State private var textValues: [String: String]
    @State private var toggleValues: [String: Bool]
    @State private var choiceValues: [String: String?]
    @State private var dateValues: [String: Date]
    @State private var timeValues: [String: Date]

    /// Renders an already-parsed `AdaptiveCard`.
    public init(
        card: AdaptiveCard,
        onAction: (@MainActor @Sendable (RenderingNode.ActionKind) -> Void)? = nil
    ) {
        let tree = Renderer().render(card: card)
        self.init(tree: tree, onAction: onAction)
    }

    /// Renders directly from a pre-built `RenderingNode` tree.
    public init(
        tree: RenderingNode,
        onAction: (@MainActor @Sendable (RenderingNode.ActionKind) -> Void)? = nil
    ) {
        self.tree = tree
        self.onAction = onAction

        // Seed state from IR defaults.
        let seeds = AdaptiveCardView.collectInitialFormState(tree)
        self._textValues = State(wrappedValue: seeds.text)
        self._toggleValues = State(wrappedValue: seeds.toggle)
        self._choiceValues = State(wrappedValue: seeds.choice)
        self._dateValues = State(wrappedValue: seeds.date)
        self._timeValues = State(wrappedValue: seeds.time)
    }

    public var body: some View {
        ScrollView {
            AdaptiveNodeView(
                node: tree,
                textValues: $textValues,
                toggleValues: $toggleValues,
                choiceValues: $choiceValues,
                dateValues: $dateValues,
                timeValues: $timeValues,
                onAction: { dispatch($0) }
            )
            .padding(16)
        }
    }

    /// Merges static action data with the current form state and forwards
    /// the result. Only `.submit` is enriched; other action kinds pass
    /// through untouched.
    private func dispatch(_ kind: RenderingNode.ActionKind) {
        guard case let .submit(staticJSON) = kind else {
            onAction?(kind)
            return
        }
        let mergedJSON = mergeStaticDataWithFormState(staticJSON: staticJSON)
        onAction?(.submit(dataJSON: mergedJSON))
    }

    /// Build the JSON object that Action.Submit conventionally produces:
    /// merge any static `data` from the action with the current values of
    /// every Input.* in the card. Delegates to the pure helper in
    /// `SubmitPayload` so the merge is independently testable.
    private func mergeStaticDataWithFormState(staticJSON: String?) -> String? {
        // Resolve toggles to their `valueOn` / `valueOff` strings via the
        // IR; the view's `@State` only stores the booleans so the renderer
        // owns the spec-correct wire mapping.
        var resolvedToggles: [String: String] = [:]
        AdaptiveCardView.collectToggleResolutions(tree) { id, on, off in
            if let live = toggleValues[id] {
                resolvedToggles[id] = live ? on : off
            }
        }
        // Dates and times serialise as ISO-8601 calendar strings, matching
        // the Adaptive Cards spec wire format ("YYYY-MM-DD" for date,
        // "HH:MM" for time).
        var extraText: [String: String] = textValues
        for (id, date) in dateValues {
            extraText[id] = SubmitPayload.iso8601DateString(from: date)
        }
        for (id, date) in timeValues {
            extraText[id] = SubmitPayload.iso8601TimeString(from: date)
        }
        return SubmitPayload.merge(
            staticJSON: staticJSON,
            textValues: extraText,
            toggleValues: resolvedToggles,
            choiceValues: choiceValues
        )
    }

    /// Walks the tree and invokes `visit` for every `.toggleField` so the
    /// view layer can map live `Bool` state back to `valueOn`/`valueOff`
    /// strings for the submit payload.
    static func collectToggleResolutions(
        _ node: RenderingNode,
        visit: (String, String, String) -> Void
    ) {
        switch node {
        case let .toggleField(id, _, _, _, on, off, _):
            visit(id, on, off)
        case let .verticalStack(_, children),
             let .horizontalStack(_, children):
            children.forEach { collectToggleResolutions($0, visit: visit) }
        case let .accordion(panels):
            panels.forEach { panel in
                panel.content.forEach { collectToggleResolutions($0, visit: visit) }
            }
        default:
            break
        }
    }

    /// Walk the tree once to find every input node and seed the initial
    /// `@State` dictionaries.
    static func collectInitialFormState(
        _ node: RenderingNode
    ) -> (
        text: [String: String],
        toggle: [String: Bool],
        choice: [String: String?],
        date: [String: Date],
        time: [String: Date]
    ) {
        var text: [String: String] = [:]
        var toggle: [String: Bool] = [:]
        var choice: [String: String?] = [:]
        var date: [String: Date] = [:]
        var time: [String: Date] = [:]

        func visit(_ n: RenderingNode) {
            switch n {
            case let .textField(id, _, _, value, _, _):
                text[id] = value ?? ""
            case let .numberField(id, _, _, value, _):
                text[id] = value.map { String($0) } ?? ""
            case let .toggleField(id, _, _, value, _, _, _):
                toggle[id] = value
            case let .choiceField(id, _, _, selected, _, _):
                choice[id] = selected
            case let .dateField(id, _, _, value, _):
                date[id] = SubmitPayload.parseDate(value) ?? Date()
            case let .timeField(id, _, _, value, _):
                time[id] = SubmitPayload.parseTime(value) ?? Date()
            case let .verticalStack(_, children),
                 let .horizontalStack(_, children):
                children.forEach(visit)
            case let .accordion(panels):
                panels.forEach { panel in panel.content.forEach(visit) }
            default:
                break
            }
        }
        visit(node)
        return (text, toggle, choice, date, time)
    }
}

/// Internal recursive renderer. One case per `RenderingNode` case.
struct AdaptiveNodeView: View {
    let node: RenderingNode

    @Binding var textValues: [String: String]
    @Binding var toggleValues: [String: Bool]
    @Binding var choiceValues: [String: String?]
    @Binding var dateValues: [String: Date]
    @Binding var timeValues: [String: Date]

    let onAction: (@MainActor @Sendable (RenderingNode.ActionKind) -> Void)?

    var body: some View {
        switch node {
        case let .text(string, size, weight, _, isSubtle):
            Text(prefix(size: size, weight: weight, isSubtle: isSubtle) + string)

        case let .richRun(string, size, weight, italic, underline, strikethrough, isSubtle):
            Text(richRunDisplay(
                string,
                size: size,
                weight: weight,
                italic: italic,
                underline: underline,
                strikethrough: strikethrough,
                isSubtle: isSubtle
            ))

        case let .image(url, alt, displayHint):
            // swift-cross-ui's `Image(URL)` does its own synchronous
            // `Data(contentsOf:)` fetch, which works for both `file://`
            // and `http(s)://`. We only fall back to a text label when
            // the URL string isn't a parseable URL at all, so a real
            // image is shown in 99% of cases. Sizing comes from
            // `displayHint`; see imageDimension(for:).
            //
            // Note: PrintWindow-based screenshot tools can't always
            // capture WinUI's DirectComposition image surface, so when
            // an alt-text is present we also render it as a caption.
            // That doubles as a graceful fallback if the image load
            // fails on the client.
            if let parsed = URL(string: url), !url.isEmpty {
                let dim = imageDimension(for: displayHint)
                VStack(alignment: .leading, spacing: 2) {
                    SwiftCrossUI.Image(parsed)
                        .resizable()
                        .frame(width: dim.width, height: dim.height)
                    if !alt.isEmpty {
                        Text(alt)
                    }
                }
            } else {
                Text("[Image: \(alt.isEmpty ? url : alt)]")
            }

        case let .verticalStack(spacing, children):
            VStack(alignment: .leading, spacing: spacing) {
                ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                    AdaptiveNodeView(
                        node: child,
                        textValues: $textValues,
                        toggleValues: $toggleValues,
                        choiceValues: $choiceValues,
                        dateValues: $dateValues,
                        timeValues: $timeValues,
                        onAction: onAction
                    )
                }
            }

        case let .horizontalStack(spacing, children):
            HStack(alignment: .top, spacing: spacing) {
                ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                    AdaptiveNodeView(
                        node: child,
                        textValues: $textValues,
                        toggleValues: $toggleValues,
                        choiceValues: $choiceValues,
                        dateValues: $dateValues,
                        timeValues: $timeValues,
                        onAction: onAction
                    )
                }
            }

        case let .facts(pairs):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                    HStack(spacing: 8) {
                        Text(pair.title + ":")
                        Text(pair.value)
                    }
                }
            }

        case let .code(text, language, _):
            VStack(alignment: .leading, spacing: 2) {
                if let language, !language.isEmpty {
                    Text("```\(language)")
                }
                Text(text)
                Text("```")
            }

        case let .textField(id, label, placeholder, _, isRequired, _):
            VStack(alignment: .leading, spacing: 2) {
                Text(fieldLabel(label, isRequired: isRequired))
                TextField(placeholder ?? "", text: textBinding(for: id))
            }

        case let .numberField(id, label, placeholder, _, isRequired):
            VStack(alignment: .leading, spacing: 2) {
                Text(fieldLabel(label, isRequired: isRequired))
                TextField(placeholder ?? "0", text: textBinding(for: id))
            }

        case let .toggleField(id, title, label, _, _, _, isRequired):
            VStack(alignment: .leading, spacing: 2) {
                if let label, !label.isEmpty {
                    Text(fieldLabel(label, isRequired: isRequired))
                }
                Toggle(title, isOn: toggleBinding(for: id))
            }

        case let .choiceField(id, label, choices, _, _, isRequired):
            VStack(alignment: .leading, spacing: 2) {
                Text(fieldLabel(label ?? "Choice", isRequired: isRequired))
                Picker(
                    of: choices.map(\.value),
                    selection: choiceBinding(for: id)
                )
            }

        case let .progressBar(value, label):
            VStack(alignment: .leading, spacing: 2) {
                if let label, !label.isEmpty {
                    Text(label)
                }
                ProgressView(value: value)
            }

        case let .spinner(label):
            HStack(spacing: 8) {
                ProgressView()
                if let label, !label.isEmpty {
                    Text(label)
                }
            }

        case let .accordion(panels):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(panels.enumerated()), id: \.offset) { _, panel in
                    VStack(alignment: .leading, spacing: 2) {
                        Text((panel.isExpanded ? "▼ " : "▶ ") + panel.title)
                        if panel.isExpanded {
                            ForEach(Array(panel.content.enumerated()), id: \.offset) { _, child in
                                AdaptiveNodeView(
                                    node: child,
                                    textValues: $textValues,
                                    toggleValues: $toggleValues,
                                    choiceValues: $choiceValues,
                                    dateValues: $dateValues,
                                    timeValues: $timeValues,
                                    onAction: onAction
                                )
                            }
                        }
                    }
                }
            }

        case let .table(headers, rows):
            VStack(alignment: .leading, spacing: 2) {
                if let headers = headers {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(Array(headers.enumerated()), id: \.offset) { _, cell in
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(cell.enumerated()), id: \.offset) { _, child in
                                    AdaptiveNodeView(
                                        node: child,
                                        textValues: $textValues,
                                        toggleValues: $toggleValues,
                                        choiceValues: $choiceValues,
                                        dateValues: $dateValues,
                                        timeValues: $timeValues,
                                        onAction: onAction
                                    )
                                }
                            }
                        }
                    }
                    Text(String(repeating: "─", count: 24))
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(cell.enumerated()), id: \.offset) { _, child in
                                    AdaptiveNodeView(
                                        node: child,
                                        textValues: $textValues,
                                        toggleValues: $toggleValues,
                                        choiceValues: $choiceValues,
                                        dateValues: $dateValues,
                                        timeValues: $timeValues,
                                        onAction: onAction
                                    )
                                }
                            }
                        }
                    }
                }
            }

        case let .rating(value, max, count):
            // Render as filled / empty stars. Half-stars are rounded to
            // the nearest whole filled star for v1; sub-star precision
            // is doable via a custom Path later.
            let filled = Int(value.rounded())
            let stars = String(repeating: "★", count: filled)
                       + String(repeating: "☆", count: Swift.max(0, max - filled))
            if let count = count {
                Text("\(stars)  (\(count))")
            } else {
                Text(stars)
            }

        case let .dateField(id, label, _, _, isRequired):
            // Native swift-cross-ui date picker. Live binding goes
            // straight into `dateValues`; the submit serialiser formats
            // the Date back to ISO-8601 "YYYY-MM-DD" for the payload.
            VStack(alignment: .leading, spacing: 2) {
                Text(fieldLabel(label, isRequired: isRequired))
                DatePicker(
                    selection: dateBinding(for: id),
                    displayedComponents: .date
                ) { Text("") }
            }

        case let .timeField(id, label, _, _, isRequired):
            // Reuses the same DatePicker widget but with only the
            // hour+minute components visible. Submit serialiser formats
            // back to "HH:MM".
            VStack(alignment: .leading, spacing: 2) {
                Text(fieldLabel(label, isRequired: isRequired))
                DatePicker(
                    selection: timeBinding(for: id),
                    displayedComponents: .hourAndMinute
                ) { Text("") }
            }

        case let .button(title, kind):
            Button(title) {
                onAction?(kind)
            }

        case let .unsupported(typeString):
            Text("[Unsupported element: \(typeString)]")
        }
    }

    // MARK: - Binding helpers

    private func textBinding(for id: String) -> Binding<String> {
        Binding(
            get: { textValues[id] ?? "" },
            set: { newValue in
                var d = textValues
                d[id] = newValue
                textValues = d
            }
        )
    }

    private func toggleBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { toggleValues[id] ?? false },
            set: { newValue in
                var d = toggleValues
                d[id] = newValue
                toggleValues = d
            }
        )
    }

    private func choiceBinding(for id: String) -> Binding<String?> {
        Binding(
            get: { choiceValues[id] ?? nil },
            set: { newValue in
                var d = choiceValues
                d[id] = newValue
                choiceValues = d
            }
        )
    }

    private func dateBinding(for id: String) -> Binding<Date> {
        Binding(
            get: { dateValues[id] ?? Date() },
            set: { newValue in
                var d = dateValues
                d[id] = newValue
                dateValues = d
            }
        )
    }

    private func timeBinding(for id: String) -> Binding<Date> {
        Binding(
            get: { timeValues[id] ?? Date() },
            set: { newValue in
                var d = timeValues
                d[id] = newValue
                timeValues = d
            }
        )
    }

    // MARK: - Text formatting helpers

    private func fieldLabel(_ raw: String?, isRequired: Bool) -> String {
        let base = raw ?? ""
        if isRequired { return base + " *" }
        return base
    }

    private func prefix(
        size: RenderingNode.TextSize,
        weight: RenderingNode.TextWeight,
        isSubtle: Bool
    ) -> String {
        var marker = ""
        switch size {
        case .extraLarge: marker += "■■ "
        case .large: marker += "■ "
        case .medium: marker += ""
        case .small: marker += "· "
        case .default: marker += ""
        }
        if weight == .bolder { marker += "*" }
        if isSubtle { marker += "~" }
        return marker
    }

    private func richRunDisplay(
        _ string: String,
        size: RenderingNode.TextSize,
        weight: RenderingNode.TextWeight,
        italic: Bool,
        underline: Bool,
        strikethrough: Bool,
        isSubtle: Bool
    ) -> String {
        var marker = prefix(size: size, weight: weight, isSubtle: isSubtle)
        if italic { marker += "/" }
        if underline { marker += "_" }
        if strikethrough { marker += "-" }
        return marker + string
    }

    /// Map an Adaptive Cards `Image.size` token to a concrete pixel
    /// dimension for the swift-cross-ui `.frame(width:height:)` modifier.
    /// `nil` means "let the image use its natural size".
    private func imageDimension(
        for hint: RenderingNode.ImageDisplayHint
    ) -> (width: Int?, height: Int?) {
        switch hint {
        case .small: return (40, 40)
        case .medium: return (80, 80)
        case .large: return (160, 160)
        case .stretch: return (nil, nil)
        }
    }
}
#endif
