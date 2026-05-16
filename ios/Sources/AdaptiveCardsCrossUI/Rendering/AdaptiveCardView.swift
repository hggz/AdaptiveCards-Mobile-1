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
    @State private var ratingValues: [String: Double]

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
        self._ratingValues = State(wrappedValue: seeds.rating)
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
                ratingValues: $ratingValues,
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
        // Ratings serialise as plain numeric strings (no decimals when the
        // value is whole). Whole-number ratings stringify as "3" rather than
        // "3.0" so the submit payload matches what other AC clients emit.
        for (id, value) in ratingValues {
            extraText[id] = value.truncatingRemainder(dividingBy: 1) == 0
                ? String(Int(value))
                : String(value)
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
        time: [String: Date],
        rating: [String: Double]
    ) {
        var text: [String: String] = [:]
        var toggle: [String: Bool] = [:]
        var choice: [String: String?] = [:]
        var date: [String: Date] = [:]
        var time: [String: Date] = [:]
        var rating: [String: Double] = [:]

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
            case let .ratingField(id, _, value, _, _):
                rating[id] = value
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
        return (text, toggle, choice, date, time, rating)
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
    @Binding var ratingValues: [String: Double]

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
                        ratingValues: $ratingValues,
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
                        ratingValues: $ratingValues,
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
                                    ratingValues: $ratingValues,
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
                                        ratingValues: $ratingValues,
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
                                        ratingValues: $ratingValues,
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

        case let .ratingField(id, label, _, max, isRequired):
            // Interactive star bar. Each star is a button: tapping it
            // sets the bound Double to its 1-based index. Filled stars
            // show up to the current value (rounded), hollow stars for
            // the rest. The label sits above the row exactly like the
            // other input fields so screen-reader narration order is
            // consistent.
            let current = ratingValues[id] ?? 0
            let filled = Int(current.rounded())
            VStack(alignment: .leading, spacing: 2) {
                Text(fieldLabel(label, isRequired: isRequired))
                HStack(spacing: 4) {
                    ForEach(Array((1...Swift.max(max, 1)).enumerated()), id: \.offset) { _, star in
                        Button(star <= filled ? "★" : "☆") {
                            var d = ratingValues
                            d[id] = Double(star)
                            ratingValues = d
                        }
                    }
                }
            }

        case let .chart(_, title, data, _):
            // swift-cross-ui has no native chart widget. Render an
            // accessible, text-based summary: title (if any) + one row
            // per datum showing the label, value, and a proportional
            // bar built from filled / empty block characters. This is
            // what screen readers will narrate anyway, and the visual
            // is informative without needing canvas drawing.
            VStack(alignment: .leading, spacing: 2) {
                if let title, !title.isEmpty {
                    Text(title)
                }
                ForEach(Array(data.enumerated()), id: \.offset) { _, datum in
                    Text(chartRow(label: datum.label, value: datum.value, max: chartMax(data)))
                }
            }

        case let .tabSet(tabs, selectedTabIndex):
            // Delegates to a dedicated sub-View that owns the live
            // selection via its own `@State`. The IR's
            // `selectedTabIndex` seeds the initial value; users can
            // switch tabs at runtime by tapping the tab strip.
            TabSetView(
                tabs: tabs,
                initialIndex: selectedTabIndex,
                textValues: $textValues,
                toggleValues: $toggleValues,
                choiceValues: $choiceValues,
                dateValues: $dateValues,
                timeValues: $timeValues,
                ratingValues: $ratingValues,
                onAction: onAction
            )

        case let .carousel(pages, selectedPageIndex, _):
            // Delegates to a dedicated sub-View that owns the live
            // page selection via `@State`. The IR's
            // `selectedPageIndex` seeds the initial value; prev / next
            // buttons let the user navigate. `autoAdvanceMs` is
            // captured in the IR but timer-driven rotation is parked
            // for a follow-up phase (swift-cross-ui's Timer story
            // needs its own design pass).
            CarouselView(
                pages: pages,
                initialIndex: selectedPageIndex,
                textValues: $textValues,
                toggleValues: $toggleValues,
                choiceValues: $choiceValues,
                dateValues: $dateValues,
                timeValues: $timeValues,
                ratingValues: $ratingValues,
                onAction: onAction
            )

        case let .list(style, items):
            // Render items as marker + child rows. `.default` produces
            // an empty marker so it renders the same as a vertical
            // stack; `.bulleted` and `.numbered` produce explicit
            // markers. The marker is a sibling `Text` (not a prefix
            // baked into the child's content) so the child can be any
            // RenderingNode -- a TextBlock, an Image, even a nested
            // Container -- without us having to bake list semantics
            // into every child kind.
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .top, spacing: 6) {
                        let marker = listMarker(style: style, index: idx)
                        if !marker.isEmpty {
                            Text(marker)
                        }
                        AdaptiveNodeView(
                            node: item,
                            textValues: $textValues,
                            toggleValues: $toggleValues,
                            choiceValues: $choiceValues,
                            dateValues: $dateValues,
                            timeValues: $timeValues,
                            ratingValues: $ratingValues,
                            onAction: onAction
                        )
                    }
                }
            }

        case let .media(sources, posterURL, altText):
            // swift-cross-ui has no audio / video widget, so render a
            // textual summary: poster image (if URL parses), the
            // altText caption (or a placeholder when missing), and one
            // line per source listing its mimeType + URL. This is
            // exactly what assistive tech would narrate, and a sighted
            // user gets enough information to copy the URL into a
            // separate player or follow the link.
            VStack(alignment: .leading, spacing: 4) {
                if let posterURL,
                   let posterParsed = URL(string: posterURL),
                   !posterURL.isEmpty {
                    SwiftCrossUI.Image(posterParsed)
                        .resizable()
                        .frame(width: 160, height: 90)
                }
                Text("[Media] " + (altText ?? "(no alt text)"))
                ForEach(Array(sources.enumerated()), id: \.offset) { _, source in
                    Text("  \(source.mimeType): \(source.url)")
                }
                if sources.isEmpty {
                    Text("  (no sources)")
                }
            }

        case let .compoundButton(title, subtitle, _, action):
            // Two-line button (title on top, subtitle below). Wires the
            // attached action through the standard onAction callback so
            // it joins the Submit/OpenUrl flow.
            VStack(alignment: .leading, spacing: 2) {
                Button(title) {
                    if let action { onAction?(action) }
                }
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                }
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

    // MARK: - Chart text rendering

    /// Largest absolute value across the chart's data, used to scale
    /// every bar to a fixed-width column. Returns `1` for empty or
    /// all-zero data so the divisor is always safe.
    private func chartMax(_ data: [ChartDatum]) -> Double {
        let peak = data.map { Swift.abs($0.value) }.max() ?? 0
        return peak > 0 ? peak : 1
    }

    /// Format a single chart datum as a line of text:
    /// `label  ████████░░░░  value`. The bar width is fixed at 12
    /// cells so columns line up even in a proportional font when
    /// rendered via swift-cross-ui's `Text`.
    private func chartRow(label: String, value: Double, max: Double) -> String {
        let width = 12
        let ratio = max > 0 ? Swift.min(1.0, Swift.abs(value) / max) : 0
        let filled = Int((Double(width) * ratio).rounded())
        let bar = String(repeating: "█", count: filled)
                + String(repeating: "░", count: Swift.max(0, width - filled))
        let formattedValue = value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.2f", value)
        return "\(label)  \(bar)  \(formattedValue)"
    }

    // MARK: - Carousel text indicators

    /// "Page 2 of 5" style indicator. 1-based for the user-facing
    /// string so screen-reader narration sounds natural.
    private func carouselPageIndicator(selectedIndex: Int, total: Int) -> String {
        return "Page \(selectedIndex + 1) of \(total)"
    }

    /// Bullet strip: `● ● ◯ ● ●` -- filled bullet on the selected
    /// index, hollow on the others. Provides a quick visual cue of
    /// position + total without expanding to per-page thumbnails.
    private func carouselDotStrip(selectedIndex: Int, total: Int) -> String {
        var parts: [String] = []
        for i in 0..<total {
            parts.append(i == selectedIndex ? "●" : "◯")
        }
        return parts.joined(separator: " ")
    }

    // MARK: - List marker

    /// Marker text prefixed to each `.list` item. The View places the
    /// returned string in a sibling `Text` view next to the child node
    /// so list semantics never need to be baked into the child renderer.
    private func listMarker(style: ListStyle, index: Int) -> String {
        switch style {
        case .default: return ""
        case .bulleted: return "•"
        case .numbered: return "\(index + 1)."
        }
    }
}

// MARK: - TabSetView

/// Live tab-selection View. The IR's `selectedTabIndex` seeds the
/// initial `@State`; tapping a tab button updates the state and
/// re-renders the body so the new tab's children appear.
///
/// Pulled out of `AdaptiveNodeView`'s switch because `@State` only
/// survives across body invocations when it lives on a stable View
/// identity -- the switch's transient widgets don't qualify, so a
/// dedicated wrapper struct gives us per-tabset state.
struct TabSetView: View {
    let tabs: [TabItem]

    @State private var currentIndex: Int

    @Binding var textValues: [String: String]
    @Binding var toggleValues: [String: Bool]
    @Binding var choiceValues: [String: String?]
    @Binding var dateValues: [String: Date]
    @Binding var timeValues: [String: Date]
    @Binding var ratingValues: [String: Double]

    let onAction: (@MainActor @Sendable (RenderingNode.ActionKind) -> Void)?

    init(
        tabs: [TabItem],
        initialIndex: Int,
        textValues: Binding<[String: String]>,
        toggleValues: Binding<[String: Bool]>,
        choiceValues: Binding<[String: String?]>,
        dateValues: Binding<[String: Date]>,
        timeValues: Binding<[String: Date]>,
        ratingValues: Binding<[String: Double]>,
        onAction: (@MainActor @Sendable (RenderingNode.ActionKind) -> Void)?
    ) {
        self.tabs = tabs
        // Clamp into the legal range so a renderer that emits a
        // selectedTabIndex outside [0, tabs.count) doesn't crash the
        // view; we already do this in the renderer for Carousel but
        // TabSet's renderer trusts the resolved index.
        let safe = tabs.indices.contains(initialIndex) ? initialIndex : 0
        self._currentIndex = State(wrappedValue: safe)
        self._textValues = textValues
        self._toggleValues = toggleValues
        self._choiceValues = choiceValues
        self._dateValues = dateValues
        self._timeValues = timeValues
        self._ratingValues = ratingValues
        self.onAction = onAction
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ForEach(Array(tabs.enumerated()), id: \.offset) { idx, tab in
                    Button((idx == currentIndex ? "* " : "  ") + tab.title) {
                        currentIndex = idx
                    }
                }
            }
            Text(String(repeating: "─", count: 24))
            if tabs.indices.contains(currentIndex) {
                ForEach(Array(tabs[currentIndex].content.enumerated()), id: \.offset) { _, child in
                    AdaptiveNodeView(
                        node: child,
                        textValues: $textValues,
                        toggleValues: $toggleValues,
                        choiceValues: $choiceValues,
                        dateValues: $dateValues,
                        timeValues: $timeValues,
                        ratingValues: $ratingValues,
                        onAction: onAction
                    )
                }
            }
        }
    }
}

// MARK: - CarouselView

/// Live carousel-paging View. The IR's `selectedPageIndex` seeds the
/// initial `@State`; explicit Prev / Next buttons (plus the
/// page-level `selectAction`, if present) drive page transitions.
///
/// Timer-driven auto-rotation (`autoAdvanceMs`) is not wired in this
/// phase -- swift-cross-ui's Timer / async-driven mutation story
/// needs its own design pass and the IR already carries the timer
/// value so a future commit can light it up without an IR re-shape.
struct CarouselView: View {
    let pages: [CarouselPageItem]

    @State private var currentIndex: Int

    @Binding var textValues: [String: String]
    @Binding var toggleValues: [String: Bool]
    @Binding var choiceValues: [String: String?]
    @Binding var dateValues: [String: Date]
    @Binding var timeValues: [String: Date]
    @Binding var ratingValues: [String: Double]

    let onAction: (@MainActor @Sendable (RenderingNode.ActionKind) -> Void)?

    init(
        pages: [CarouselPageItem],
        initialIndex: Int,
        textValues: Binding<[String: String]>,
        toggleValues: Binding<[String: Bool]>,
        choiceValues: Binding<[String: String?]>,
        dateValues: Binding<[String: Date]>,
        timeValues: Binding<[String: Date]>,
        ratingValues: Binding<[String: Double]>,
        onAction: (@MainActor @Sendable (RenderingNode.ActionKind) -> Void)?
    ) {
        self.pages = pages
        let safe = pages.indices.contains(initialIndex) ? initialIndex : 0
        self._currentIndex = State(wrappedValue: safe)
        self._textValues = textValues
        self._toggleValues = toggleValues
        self._choiceValues = choiceValues
        self._dateValues = dateValues
        self._timeValues = timeValues
        self._ratingValues = ratingValues
        self.onAction = onAction
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !pages.isEmpty, pages.indices.contains(currentIndex) {
                Text("Page \(currentIndex + 1) of \(pages.count)")
                Text(carouselDotStrip(selectedIndex: currentIndex, total: pages.count))
                HStack(spacing: 6) {
                    Button("◀ Prev") {
                        if currentIndex > 0 { currentIndex -= 1 }
                    }
                    Button("Next ▶") {
                        if currentIndex < pages.count - 1 { currentIndex += 1 }
                    }
                }
                Text(String(repeating: "─", count: 24))
                ForEach(Array(pages[currentIndex].content.enumerated()), id: \.offset) { _, child in
                    AdaptiveNodeView(
                        node: child,
                        textValues: $textValues,
                        toggleValues: $toggleValues,
                        choiceValues: $choiceValues,
                        dateValues: $dateValues,
                        timeValues: $timeValues,
                        ratingValues: $ratingValues,
                        onAction: onAction
                    )
                }
                if let action = pages[currentIndex].selectAction {
                    Button("Open page") {
                        onAction?(action)
                    }
                }
            } else {
                Text("[Carousel: empty]")
            }
        }
    }

    /// Bullet strip: `● ● ◯ ● ●` -- filled bullet on the selected
    /// index, hollow on the others. Duplicated here from
    /// `AdaptiveNodeView`'s helper so this struct stays self-contained.
    private func carouselDotStrip(selectedIndex: Int, total: Int) -> String {
        var parts: [String] = []
        for i in 0..<total {
            parts.append(i == selectedIndex ? "●" : "◯")
        }
        return parts.joined(separator: " ")
    }
}
#endif
