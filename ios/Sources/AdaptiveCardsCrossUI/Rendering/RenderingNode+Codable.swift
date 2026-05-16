//
//  RenderingNode+Codable.swift
//  AdaptiveCardsCrossUI — windows-port
//
//  Stable JSON encoding for `RenderingNode` so the snapshot harness can
//  commit baselines to disk and diff fresh renders against them on every
//  CI run. The encoding is deliberately verbose ("type" + payload object)
//  to keep diffs readable.
//

import Foundation

extension AccordionPanel: Codable {
    private enum Key: String, CodingKey { case title, content, isExpanded }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        self.title = try c.decode(String.self, forKey: .title)
        self.content = try c.decode([RenderingNode].self, forKey: .content)
        self.isExpanded = try c.decode(Bool.self, forKey: .isExpanded)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        try c.encode(title, forKey: .title)
        try c.encode(content, forKey: .content)
        try c.encode(isExpanded, forKey: .isExpanded)
    }
}

extension RenderingNode: Codable {

    private enum Discriminator: String, Codable {
        case text
        case richRun
        case image
        case verticalStack
        case horizontalStack
        case facts
        case code
        case textField
        case numberField
        case toggleField
        case choiceField
        case progressBar
        case spinner
        case accordion
        case table
        case rating
        case dateField
        case timeField
        case ratingField
        case chart
        case tabSet
        case carousel
        case list
        case media
        case compoundButton
        case button
        case unsupported
    }

    private enum Key: String, CodingKey {
        case type
        case string, size, weight, wrap, isSubtle
        case italic, underline, strikethrough
        case url, alt, displayHint
        case spacing, children
        case pairs, title, value
        case text, language
        case id, label, placeholder, isRequired, isMultiline
        case valueOn, valueOff
        case isMultiSelect, choices, selected
        case panels
        case headers, rows
        case max, count
        case kind
        case typeString
        case data, showLegend
        case tabs, selectedTabIndex
        case pages, selectedPageIndex, autoAdvanceMs, selectAction
        case style, items
        case sources, posterURL, altText
        case subtitle, icon, action
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        let type = try c.decode(Discriminator.self, forKey: .type)
        switch type {
        case .text:
            self = .text(
                try c.decode(String.self, forKey: .string),
                size: try c.decode(TextSize.self, forKey: .size),
                weight: try c.decode(TextWeight.self, forKey: .weight),
                wrap: try c.decode(Bool.self, forKey: .wrap),
                isSubtle: try c.decode(Bool.self, forKey: .isSubtle)
            )
        case .richRun:
            self = .richRun(
                try c.decode(String.self, forKey: .string),
                size: try c.decode(TextSize.self, forKey: .size),
                weight: try c.decode(TextWeight.self, forKey: .weight),
                italic: try c.decode(Bool.self, forKey: .italic),
                underline: try c.decode(Bool.self, forKey: .underline),
                strikethrough: try c.decode(Bool.self, forKey: .strikethrough),
                isSubtle: try c.decode(Bool.self, forKey: .isSubtle)
            )
        case .image:
            self = .image(
                url: try c.decode(String.self, forKey: .url),
                alt: try c.decode(String.self, forKey: .alt),
                displayHint: try c.decode(ImageDisplayHint.self, forKey: .displayHint)
            )
        case .verticalStack:
            self = .verticalStack(
                spacing: try c.decode(Int.self, forKey: .spacing),
                children: try c.decode([RenderingNode].self, forKey: .children)
            )
        case .horizontalStack:
            self = .horizontalStack(
                spacing: try c.decode(Int.self, forKey: .spacing),
                children: try c.decode([RenderingNode].self, forKey: .children)
            )
        case .facts:
            struct Pair: Codable { let title: String; let value: String }
            let pairs = try c.decode([Pair].self, forKey: .pairs)
            self = .facts(pairs.map { (title: $0.title, value: $0.value) })
        case .code:
            self = .code(
                text: try c.decode(String.self, forKey: .text),
                language: try c.decodeIfPresent(String.self, forKey: .language),
                wrap: try c.decode(Bool.self, forKey: .wrap)
            )
        case .textField:
            self = .textField(
                id: try c.decode(String.self, forKey: .id),
                label: try c.decodeIfPresent(String.self, forKey: .label),
                placeholder: try c.decodeIfPresent(String.self, forKey: .placeholder),
                value: try c.decodeIfPresent(String.self, forKey: .value),
                isRequired: try c.decode(Bool.self, forKey: .isRequired),
                isMultiline: try c.decode(Bool.self, forKey: .isMultiline)
            )
        case .numberField:
            self = .numberField(
                id: try c.decode(String.self, forKey: .id),
                label: try c.decodeIfPresent(String.self, forKey: .label),
                placeholder: try c.decodeIfPresent(String.self, forKey: .placeholder),
                value: try c.decodeIfPresent(Double.self, forKey: .value),
                isRequired: try c.decode(Bool.self, forKey: .isRequired)
            )
        case .toggleField:
            self = .toggleField(
                id: try c.decode(String.self, forKey: .id),
                title: try c.decode(String.self, forKey: .title),
                label: try c.decodeIfPresent(String.self, forKey: .label),
                value: try c.decode(Bool.self, forKey: .value),
                valueOn: try c.decode(String.self, forKey: .valueOn),
                valueOff: try c.decode(String.self, forKey: .valueOff),
                isRequired: try c.decode(Bool.self, forKey: .isRequired)
            )
        case .choiceField:
            self = .choiceField(
                id: try c.decode(String.self, forKey: .id),
                label: try c.decodeIfPresent(String.self, forKey: .label),
                choices: try c.decode([ChoiceOption].self, forKey: .choices),
                selected: try c.decodeIfPresent(String.self, forKey: .selected),
                isMultiSelect: try c.decode(Bool.self, forKey: .isMultiSelect),
                isRequired: try c.decode(Bool.self, forKey: .isRequired)
            )
        case .progressBar:
            self = .progressBar(
                value: try c.decode(Double.self, forKey: .value),
                label: try c.decodeIfPresent(String.self, forKey: .label)
            )
        case .spinner:
            self = .spinner(label: try c.decodeIfPresent(String.self, forKey: .label))
        case .accordion:
            self = .accordion(panels: try c.decode([AccordionPanel].self, forKey: .panels))
        case .table:
            self = .table(
                headers: try c.decodeIfPresent([[RenderingNode]].self, forKey: .headers),
                rows: try c.decode([[[RenderingNode]]].self, forKey: .rows)
            )
        case .rating:
            self = .rating(
                value: try c.decode(Double.self, forKey: .value),
                max: try c.decode(Int.self, forKey: .max),
                count: try c.decodeIfPresent(Int.self, forKey: .count)
            )
        case .dateField:
            self = .dateField(
                id: try c.decode(String.self, forKey: .id),
                label: try c.decodeIfPresent(String.self, forKey: .label),
                placeholder: try c.decodeIfPresent(String.self, forKey: .placeholder),
                value: try c.decodeIfPresent(String.self, forKey: .value),
                isRequired: try c.decode(Bool.self, forKey: .isRequired)
            )
        case .timeField:
            self = .timeField(
                id: try c.decode(String.self, forKey: .id),
                label: try c.decodeIfPresent(String.self, forKey: .label),
                placeholder: try c.decodeIfPresent(String.self, forKey: .placeholder),
                value: try c.decodeIfPresent(String.self, forKey: .value),
                isRequired: try c.decode(Bool.self, forKey: .isRequired)
            )
        case .ratingField:
            self = .ratingField(
                id: try c.decode(String.self, forKey: .id),
                label: try c.decodeIfPresent(String.self, forKey: .label),
                value: try c.decode(Double.self, forKey: .value),
                max: try c.decode(Int.self, forKey: .max),
                isRequired: try c.decode(Bool.self, forKey: .isRequired)
            )
        case .chart:
            self = .chart(
                kind: try c.decode(ChartKind.self, forKey: .kind),
                title: try c.decodeIfPresent(String.self, forKey: .title),
                data: try c.decode([ChartDatum].self, forKey: .data),
                showLegend: try c.decode(Bool.self, forKey: .showLegend)
            )
        case .tabSet:
            struct Item: Codable {
                let id: String
                let title: String
                let content: [RenderingNode]
            }
            let raw = try c.decode([Item].self, forKey: .tabs)
            self = .tabSet(
                tabs: raw.map { TabItem(id: $0.id, title: $0.title, content: $0.content) },
                selectedTabIndex: try c.decode(Int.self, forKey: .selectedTabIndex)
            )
        case .carousel:
            struct Page: Codable {
                let id: String
                let content: [RenderingNode]
                let selectAction: ActionKind?
            }
            let raw = try c.decode([Page].self, forKey: .pages)
            self = .carousel(
                pages: raw.map {
                    CarouselPageItem(id: $0.id, content: $0.content, selectAction: $0.selectAction)
                },
                selectedPageIndex: try c.decode(Int.self, forKey: .selectedPageIndex),
                autoAdvanceMs: try c.decodeIfPresent(Int.self, forKey: .autoAdvanceMs)
            )
        case .list:
            self = .list(
                style: try c.decode(ListStyle.self, forKey: .style),
                items: try c.decode([RenderingNode].self, forKey: .items)
            )
        case .media:
            self = .media(
                sources: try c.decode([MediaSource].self, forKey: .sources),
                posterURL: try c.decodeIfPresent(String.self, forKey: .posterURL),
                altText: try c.decodeIfPresent(String.self, forKey: .altText)
            )
        case .compoundButton:
            self = .compoundButton(
                title: try c.decode(String.self, forKey: .title),
                subtitle: try c.decodeIfPresent(String.self, forKey: .subtitle),
                icon: try c.decodeIfPresent(String.self, forKey: .icon),
                action: try c.decodeIfPresent(ActionKind.self, forKey: .action)
            )
        case .button:
            self = .button(
                title: try c.decode(String.self, forKey: .title),
                kind: try c.decode(ActionKind.self, forKey: .kind)
            )
        case .unsupported:
            self = .unsupported(typeString: try c.decode(String.self, forKey: .typeString))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        switch self {
        case let .text(string, size, weight, wrap, isSubtle):
            try c.encode(Discriminator.text, forKey: .type)
            try c.encode(string, forKey: .string)
            try c.encode(size, forKey: .size)
            try c.encode(weight, forKey: .weight)
            try c.encode(wrap, forKey: .wrap)
            try c.encode(isSubtle, forKey: .isSubtle)

        case let .richRun(string, size, weight, italic, underline, strikethrough, isSubtle):
            try c.encode(Discriminator.richRun, forKey: .type)
            try c.encode(string, forKey: .string)
            try c.encode(size, forKey: .size)
            try c.encode(weight, forKey: .weight)
            try c.encode(italic, forKey: .italic)
            try c.encode(underline, forKey: .underline)
            try c.encode(strikethrough, forKey: .strikethrough)
            try c.encode(isSubtle, forKey: .isSubtle)

        case let .image(url, alt, displayHint):
            try c.encode(Discriminator.image, forKey: .type)
            try c.encode(url, forKey: .url)
            try c.encode(alt, forKey: .alt)
            try c.encode(displayHint, forKey: .displayHint)

        case let .verticalStack(spacing, children):
            try c.encode(Discriminator.verticalStack, forKey: .type)
            try c.encode(spacing, forKey: .spacing)
            try c.encode(children, forKey: .children)

        case let .horizontalStack(spacing, children):
            try c.encode(Discriminator.horizontalStack, forKey: .type)
            try c.encode(spacing, forKey: .spacing)
            try c.encode(children, forKey: .children)

        case let .facts(pairs):
            struct Pair: Codable { let title: String; let value: String }
            try c.encode(Discriminator.facts, forKey: .type)
            try c.encode(pairs.map { Pair(title: $0.title, value: $0.value) }, forKey: .pairs)

        case let .code(text, language, wrap):
            try c.encode(Discriminator.code, forKey: .type)
            try c.encode(text, forKey: .text)
            try c.encodeIfPresent(language, forKey: .language)
            try c.encode(wrap, forKey: .wrap)

        case let .textField(id, label, placeholder, value, isRequired, isMultiline):
            try c.encode(Discriminator.textField, forKey: .type)
            try c.encode(id, forKey: .id)
            try c.encodeIfPresent(label, forKey: .label)
            try c.encodeIfPresent(placeholder, forKey: .placeholder)
            try c.encodeIfPresent(value, forKey: .value)
            try c.encode(isRequired, forKey: .isRequired)
            try c.encode(isMultiline, forKey: .isMultiline)

        case let .numberField(id, label, placeholder, value, isRequired):
            try c.encode(Discriminator.numberField, forKey: .type)
            try c.encode(id, forKey: .id)
            try c.encodeIfPresent(label, forKey: .label)
            try c.encodeIfPresent(placeholder, forKey: .placeholder)
            try c.encodeIfPresent(value, forKey: .value)
            try c.encode(isRequired, forKey: .isRequired)

        case let .toggleField(id, title, label, value, valueOn, valueOff, isRequired):
            try c.encode(Discriminator.toggleField, forKey: .type)
            try c.encode(id, forKey: .id)
            try c.encode(title, forKey: .title)
            try c.encodeIfPresent(label, forKey: .label)
            try c.encode(value, forKey: .value)
            try c.encode(valueOn, forKey: .valueOn)
            try c.encode(valueOff, forKey: .valueOff)
            try c.encode(isRequired, forKey: .isRequired)

        case let .choiceField(id, label, choices, selected, isMultiSelect, isRequired):
            try c.encode(Discriminator.choiceField, forKey: .type)
            try c.encode(id, forKey: .id)
            try c.encodeIfPresent(label, forKey: .label)
            try c.encode(choices, forKey: .choices)
            try c.encodeIfPresent(selected, forKey: .selected)
            try c.encode(isMultiSelect, forKey: .isMultiSelect)
            try c.encode(isRequired, forKey: .isRequired)

        case let .progressBar(value, label):
            try c.encode(Discriminator.progressBar, forKey: .type)
            try c.encode(value, forKey: .value)
            try c.encodeIfPresent(label, forKey: .label)

        case let .spinner(label):
            try c.encode(Discriminator.spinner, forKey: .type)
            try c.encodeIfPresent(label, forKey: .label)

        case let .accordion(panels):
            try c.encode(Discriminator.accordion, forKey: .type)
            try c.encode(panels, forKey: .panels)

        case let .table(headers, rows):
            try c.encode(Discriminator.table, forKey: .type)
            try c.encodeIfPresent(headers, forKey: .headers)
            try c.encode(rows, forKey: .rows)

        case let .rating(value, max, count):
            try c.encode(Discriminator.rating, forKey: .type)
            try c.encode(value, forKey: .value)
            try c.encode(max, forKey: .max)
            try c.encodeIfPresent(count, forKey: .count)

        case let .dateField(id, label, placeholder, value, isRequired):
            try c.encode(Discriminator.dateField, forKey: .type)
            try c.encode(id, forKey: .id)
            try c.encodeIfPresent(label, forKey: .label)
            try c.encodeIfPresent(placeholder, forKey: .placeholder)
            try c.encodeIfPresent(value, forKey: .value)
            try c.encode(isRequired, forKey: .isRequired)

        case let .timeField(id, label, placeholder, value, isRequired):
            try c.encode(Discriminator.timeField, forKey: .type)
            try c.encode(id, forKey: .id)
            try c.encodeIfPresent(label, forKey: .label)
            try c.encodeIfPresent(placeholder, forKey: .placeholder)
            try c.encodeIfPresent(value, forKey: .value)
            try c.encode(isRequired, forKey: .isRequired)

        case let .ratingField(id, label, value, max, isRequired):
            try c.encode(Discriminator.ratingField, forKey: .type)
            try c.encode(id, forKey: .id)
            try c.encodeIfPresent(label, forKey: .label)
            try c.encode(value, forKey: .value)
            try c.encode(max, forKey: .max)
            try c.encode(isRequired, forKey: .isRequired)

        case let .chart(kind, title, data, showLegend):
            try c.encode(Discriminator.chart, forKey: .type)
            try c.encode(kind, forKey: .kind)
            try c.encodeIfPresent(title, forKey: .title)
            try c.encode(data, forKey: .data)
            try c.encode(showLegend, forKey: .showLegend)

        case let .tabSet(tabs, selectedTabIndex):
            struct Item: Codable {
                let id: String
                let title: String
                let content: [RenderingNode]
            }
            try c.encode(Discriminator.tabSet, forKey: .type)
            try c.encode(tabs.map { Item(id: $0.id, title: $0.title, content: $0.content) }, forKey: .tabs)
            try c.encode(selectedTabIndex, forKey: .selectedTabIndex)

        case let .carousel(pages, selectedPageIndex, autoAdvanceMs):
            struct Page: Codable {
                let id: String
                let content: [RenderingNode]
                let selectAction: ActionKind?
            }
            try c.encode(Discriminator.carousel, forKey: .type)
            try c.encode(
                pages.map { Page(id: $0.id, content: $0.content, selectAction: $0.selectAction) },
                forKey: .pages
            )
            try c.encode(selectedPageIndex, forKey: .selectedPageIndex)
            try c.encodeIfPresent(autoAdvanceMs, forKey: .autoAdvanceMs)

        case let .list(style, items):
            try c.encode(Discriminator.list, forKey: .type)
            try c.encode(style, forKey: .style)
            try c.encode(items, forKey: .items)

        case let .media(sources, posterURL, altText):
            try c.encode(Discriminator.media, forKey: .type)
            try c.encode(sources, forKey: .sources)
            try c.encodeIfPresent(posterURL, forKey: .posterURL)
            try c.encodeIfPresent(altText, forKey: .altText)

        case let .compoundButton(title, subtitle, icon, action):
            try c.encode(Discriminator.compoundButton, forKey: .type)
            try c.encode(title, forKey: .title)
            try c.encodeIfPresent(subtitle, forKey: .subtitle)
            try c.encodeIfPresent(icon, forKey: .icon)
            try c.encodeIfPresent(action, forKey: .action)

        case let .button(title, kind):
            try c.encode(Discriminator.button, forKey: .type)
            try c.encode(title, forKey: .title)
            try c.encode(kind, forKey: .kind)

        case let .unsupported(typeString):
            try c.encode(Discriminator.unsupported, forKey: .type)
            try c.encode(typeString, forKey: .typeString)
        }
    }
}

extension RenderingNode.ActionKind: Codable {
    private enum Discriminator: String, Codable {
        case submit, openUrl, showCard, execute, toggleVisibility
        case popover, runCommands, openUrlDialog, unknown
    }
    private enum Key: String, CodingKey { case type, payload }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        let kind = try c.decode(Discriminator.self, forKey: .type)
        switch kind {
        case .submit: self = .submit(dataJSON: try c.decodeIfPresent(String.self, forKey: .payload))
        case .openUrl: self = .openUrl(try c.decode(String.self, forKey: .payload))
        case .showCard: self = .showCard
        case .execute: self = .execute
        case .toggleVisibility: self = .toggleVisibility
        case .popover: self = .popover
        case .runCommands: self = .runCommands
        case .openUrlDialog: self = .openUrlDialog
        case .unknown: self = .unknown(try c.decode(String.self, forKey: .payload))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        switch self {
        case let .submit(data):
            try c.encode(Discriminator.submit, forKey: .type)
            try c.encodeIfPresent(data, forKey: .payload)
        case let .openUrl(url):
            try c.encode(Discriminator.openUrl, forKey: .type)
            try c.encode(url, forKey: .payload)
        case .showCard: try c.encode(Discriminator.showCard, forKey: .type)
        case .execute: try c.encode(Discriminator.execute, forKey: .type)
        case .toggleVisibility: try c.encode(Discriminator.toggleVisibility, forKey: .type)
        case .popover: try c.encode(Discriminator.popover, forKey: .type)
        case .runCommands: try c.encode(Discriminator.runCommands, forKey: .type)
        case .openUrlDialog: try c.encode(Discriminator.openUrlDialog, forKey: .type)
        case let .unknown(s):
            try c.encode(Discriminator.unknown, forKey: .type)
            try c.encode(s, forKey: .payload)
        }
    }
}

extension RenderingNode.TextSize: Codable {}
extension RenderingNode.TextWeight: Codable {}
extension RenderingNode.ImageDisplayHint: Codable {}

// MARK: - Snapshot helpers

public extension RenderingNode {
    /// Encode this rendering node as pretty-printed, sorted-key JSON.
    func snapshotJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let bytes = try encoder.encode(self)
        return String(data: bytes, encoding: .utf8) ?? ""
    }
}
