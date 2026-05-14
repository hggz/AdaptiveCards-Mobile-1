//
//  Renderer.swift
//  AdaptiveCardsCrossUI — windows-port
//
//  Pure, platform-neutral mapping from an `ACCore.AdaptiveCard` to a
//  `RenderingNode` tree. Contains no swift-cross-ui imports — runs on
//  every platform Swift supports and is fully unit-testable headlessly.
//
//  The swift-cross-ui wrapper that turns the tree into actual native
//  widgets lives in `AdaptiveCardView.swift`.
//
//  Renderer coverage as of windows-port step 2:
//    * AdaptiveCard.body, AdaptiveCard.actions
//    * TextBlock (size, weight, wrap, isSubtle)
//    * Image (url, altText, size)
//    * Container (items)
//    * ColumnSet (columns -> horizontal stack)
//    * FactSet
//    * ActionSet (delegated to Action rendering)
//    * Action.Submit, Action.OpenUrl
//
//  Anything else maps to `.unsupported(typeString:)` so the demo window
//  shows a labelled placeholder rather than silently dropping content.
//

import Foundation
import ACCore

public struct Renderer {

    /// Default vertical spacing between elements at the card body level,
    /// matching the Adaptive Cards spec's "default" spacing token.
    public static let defaultBodySpacing: Int = 8

    public init() {}

    /// Renders an entire parsed Adaptive Card into a `RenderingNode` tree.
    ///
    /// Top-level shape:
    /// ```
    /// verticalStack(
    ///   children: [body elements...]
    ///          + [horizontalStack of action buttons (if any)]
    /// )
    /// ```
    public func render(card: AdaptiveCard) -> RenderingNode {
        var children: [RenderingNode] = []

        for element in (card.body ?? []) where element.isVisible {
            children.append(render(element: element))
        }

        if let actions = card.actions, !actions.isEmpty {
            let buttons = actions.map { render(action: $0) }
            children.append(.horizontalStack(spacing: 8, children: buttons))
        }

        return .verticalStack(spacing: Self.defaultBodySpacing, children: children)
    }

    // MARK: - Elements

    public func render(element: CardElement) -> RenderingNode {
        switch element {
        case .textBlock(let tb):
            return .text(
                tb.text,
                size: mapSize(tb.size),
                weight: mapWeight(tb.weight),
                wrap: tb.wrap ?? false,
                isSubtle: tb.isSubtle ?? false
            )

        case .image(let img):
            return .image(
                url: img.url,
                alt: img.altText ?? "",
                displayHint: mapImageSize(img.size)
            )

        case .container(let c):
            let items = (c.items ?? []).filter(\.isVisible).map { render(element: $0) }
            return .verticalStack(spacing: Self.defaultBodySpacing, children: items)

        case .columnSet(let cs):
            // Each column becomes its own verticalStack of its items, then
            // all columns are arranged horizontally.
            let columns: [RenderingNode] = cs.columns
                .filter { $0.isVisible ?? true }
                .map { col in
                    let items = (col.items ?? []).filter(\.isVisible).map { render(element: $0) }
                    return .verticalStack(spacing: Self.defaultBodySpacing, children: items)
                }
            return .horizontalStack(spacing: Self.defaultBodySpacing, children: columns)

        case .factSet(let fs):
            return .facts(fs.facts.map { (title: $0.title, value: $0.value) })

        case .actionSet(let aset):
            let buttons = aset.actions.map { render(action: $0) }
            return .horizontalStack(spacing: 8, children: buttons)

        case .richTextBlock(let rtb):
            let runs: [RenderingNode] = rtb.inlines.map { run in
                .richRun(
                    run.text,
                    size: mapSize(run.size),
                    weight: mapWeight(run.weight),
                    italic: run.italic ?? false,
                    underline: run.underline ?? false,
                    strikethrough: run.strikethrough ?? false,
                    isSubtle: run.isSubtle ?? false
                )
            }
            // RichTextBlock is conceptually a single paragraph; render each
            // run on its own line for v1 (no inline flow yet).
            return .verticalStack(spacing: 0, children: runs)

        case .imageSet(let iset):
            let images: [RenderingNode] = iset.images.map { img in
                .image(
                    url: img.url,
                    alt: img.altText ?? "",
                    displayHint: mapImageSize(iset.imageSize ?? img.size)
                )
            }
            return .horizontalStack(spacing: Self.defaultBodySpacing, children: images)

        case .codeBlock(let cb):
            return .code(text: cb.code, language: cb.language, wrap: cb.wrap ?? true)

        case .textInput(let ti):
            return .textField(
                id: ti.id,
                label: ti.label,
                placeholder: ti.placeholder,
                value: ti.value,
                isRequired: ti.isRequired ?? false,
                isMultiline: ti.isMultiline ?? false
            )

        case .numberInput(let ni):
            return .numberField(
                id: ni.id,
                label: ni.label,
                placeholder: ni.placeholder,
                value: ni.value,
                isRequired: ni.isRequired ?? false
            )

        case .toggleInput(let toggle):
            let on = (toggle.valueOn ?? "true")
            let off = (toggle.valueOff ?? "false")
            let current = (toggle.value ?? off)
            return .toggleField(
                id: toggle.id,
                title: toggle.title,
                label: toggle.label,
                value: current == on,
                valueOn: on,
                valueOff: off,
                isRequired: false
            )

        case .choiceSetInput(let cs):
            return .choiceField(
                id: cs.id,
                label: cs.label,
                choices: cs.choices.map { ChoiceOption(title: $0.title, value: $0.value) },
                selected: cs.value,
                isMultiSelect: cs.isMultiSelect ?? false,
                isRequired: cs.isRequired ?? false
            )

        case .progressBar(let pb):
            // Adaptive Cards spec uses 0..1 for ProgressBar.value in this
            // SwiftUI fork. Clamp defensively in case a payload supplies
            // 0..100 or out-of-range numbers.
            let clamped = max(0, min(1, pb.value))
            return .progressBar(value: clamped, label: pb.label)

        case .spinner(let sp):
            return .spinner(label: sp.label)

        case .accordion(let acc):
            let panels: [AccordionPanel] = acc.panels.map { panel in
                let body: [RenderingNode] = panel.content
                    .filter(\.isVisible)
                    .map { render(element: $0) }
                return AccordionPanel(
                    title: panel.title,
                    content: body,
                    isExpanded: panel.isExpanded ?? false
                )
            }
            return .accordion(panels: panels)

        case .table(let t):
            // Render each cell as the renderer tree of its items so the
            // table can host arbitrary card elements per cell.
            let cellsPerRow: [[[RenderingNode]]] = t.rows.map { row in
                row.cells.map { cell in
                    (cell.items ?? []).filter(\.isVisible).map { render(element: $0) }
                }
            }
            if (t.firstRowAsHeaders ?? true), let header = cellsPerRow.first {
                return .table(headers: header, rows: Array(cellsPerRow.dropFirst()))
            }
            return .table(headers: nil, rows: cellsPerRow)

        case .ratingDisplay(let r):
            return .rating(
                value: r.value,
                max: r.max ?? 5,
                count: r.count
            )

        case .dateInput(let di):
            return .dateField(
                id: di.id,
                label: di.label,
                placeholder: di.placeholder,
                value: di.value,
                isRequired: di.isRequired ?? false
            )

        case .timeInput(let ti):
            return .timeField(
                id: ti.id,
                label: ti.label,
                placeholder: ti.placeholder,
                value: ti.value,
                isRequired: ti.isRequired ?? false
            )

        // Everything else: deliberate placeholder so the demo visually shows
        // what's still missing rather than silently dropping content.
        case .media,
             .carousel,
             .ratingInput,
             .tabSet, .list, .compoundButton,
             .donutChart, .barChart, .lineChart, .pieChart,
             .unknown:
            return .unsupported(typeString: element.typeString)
        }
    }

    // MARK: - Actions

    public func render(action: CardAction) -> RenderingNode {
        switch action {
        case .submit(let a):
            return .button(
                title: a.title ?? "Submit",
                kind: .submit(dataJSON: encodeData(a.data))
            )
        case .openUrl(let a):
            return .button(title: a.title ?? "Open", kind: .openUrl(a.url))
        case .showCard(let a):
            return .button(title: a.title ?? "Show Card", kind: .showCard)
        case .execute(let a):
            return .button(title: a.title ?? "Execute", kind: .execute)
        case .toggleVisibility(let a):
            return .button(title: a.title ?? "Toggle", kind: .toggleVisibility)
        case .popover(let a):
            return .button(title: a.title ?? "More", kind: .popover)
        case .runCommands(let a):
            return .button(title: a.title ?? "Run", kind: .runCommands)
        case .openUrlDialog(let a):
            return .button(title: a.title ?? "Open Dialog", kind: .openUrlDialog)
        }
    }

    // MARK: - Mapping helpers

    private func mapSize(_ size: FontSize?) -> RenderingNode.TextSize {
        switch size {
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .extraLarge: return .extraLarge
        case .none, .default: return .default
        }
    }

    private func mapWeight(_ w: FontWeight?) -> RenderingNode.TextWeight {
        switch w {
        case .lighter: return .lighter
        case .bolder: return .bolder
        case .none, .default: return .default
        }
    }

    private func mapImageSize(_ s: ImageSize?) -> RenderingNode.ImageDisplayHint {
        switch s {
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .stretch: return .stretch
        case .none, .auto: return .medium
        }
    }

    private func encodeData(_ data: AnyCodable?) -> String? {
        guard let data else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let bytes = try? encoder.encode(data),
              let str = String(data: bytes, encoding: .utf8) else { return nil }
        return str
    }
}
