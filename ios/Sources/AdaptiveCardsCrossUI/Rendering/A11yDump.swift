//
//  A11yDump.swift
//  AdaptiveCardsCrossUI — windows-port
//
//  Walks a `RenderingNode` tree and produces a deterministic text
//  description of what assistive technology will perceive when the
//  card is rendered. The format is designed for human review and
//  CI-friendly diffing:
//
//    Heading "Simple Card" [size=large weight=bolder]
//    Text "This is a simple adaptive card..." [wrap]
//      TextField id=name label="Name" required
//        placeholder="Enter your name"
//      Toggle id=subscribe title="Subscribe to newsletter" off
//        valueOn="true" valueOff="false"
//    ActionRow
//      Button "Submit" kind=submit
//
//  Why an IR walk and not a live UI Automation walk? Three reasons:
//
//    1. Cross-platform. The IR is platform-neutral; the dump runs on
//       macOS, Linux, and Windows from the same `AdaptiveCardsValidate`
//       binary. Live UIA is Windows-only and fragile in headless CI.
//
//    2. Semantic, not visual. The dump describes the *role and name*
//       of every focusable element, which is what the accessibility
//       review process actually cares about (per
//       SkypeSpaces/.claude/agents/accessibility-reviewer.md). Live
//       UIA also captures container Pane elements, scroll views, and
//       backend-implementation-detail nodes that obscure the review.
//
//    3. Stable. The IR shape changes only when we change the renderer
//       intentionally; UIA trees can shift between WinUI versions,
//       between debug and release builds, and depending on the
//       window's input focus state at the moment of capture.
//
//  The dump is intentionally line-oriented and 2-space-indented so a
//  human can spot missing labels (a `TextField` without `label=` is a
//  red flag) and a CI diff can highlight any regression.
//

import Foundation

public enum A11yDump {

    /// Render the full a11y description of a `RenderingNode` tree as
    /// a single newline-joined string. Ends with a trailing newline.
    public static func dump(_ root: RenderingNode) -> String {
        var out: [String] = []
        walk(root, indent: 0, into: &out)
        return out.joined(separator: "\n") + "\n"
    }

    private static func walk(
        _ node: RenderingNode,
        indent: Int,
        into out: inout [String]
    ) {
        let pad = String(repeating: "  ", count: indent)

        switch node {
        case let .text(s, size, weight, wrap, isSubtle):
            // Card-level title-like text becomes a screen-reader heading
            // when size is large/extraLarge OR weight is bolder. This is
            // a conservative heuristic; spec compliance is the
            // AdaptiveCards renderer's job, but it's what TalkBack /
            // Narrator / VoiceOver users perceive.
            let isHeading = (size == .large || size == .extraLarge) && weight == .bolder
            let role = isHeading ? "Heading" : "Text"
            var attrs: [String] = []
            if size != .default { attrs.append("size=\(size.rawValue)") }
            if weight != .default { attrs.append("weight=\(weight.rawValue)") }
            if wrap { attrs.append("wrap") }
            if isSubtle { attrs.append("subtle") }
            out.append(line(pad: pad, role: role, name: quote(s), attrs: attrs))

        case let .richRun(s, size, weight, italic, underline, strikethrough, isSubtle):
            var attrs: [String] = []
            if size != .default { attrs.append("size=\(size.rawValue)") }
            if weight != .default { attrs.append("weight=\(weight.rawValue)") }
            if italic { attrs.append("italic") }
            if underline { attrs.append("underline") }
            if strikethrough { attrs.append("strikethrough") }
            if isSubtle { attrs.append("subtle") }
            out.append(line(pad: pad, role: "RichRun", name: quote(s), attrs: attrs))

        case let .image(url, alt, displayHint):
            var attrs: [String] = ["size=\(displayHint.rawValue)"]
            if alt.isEmpty {
                // Missing alt-text on an image is an a11y violation; flag
                // it explicitly so reviewers / CI catch it.
                attrs.insert("MISSING_ALT", at: 0)
                out.append(line(pad: pad, role: "Image", name: quote(url), attrs: attrs))
            } else {
                out.append(line(pad: pad, role: "Image", name: quote(alt), attrs: attrs))
            }

        case let .verticalStack(_, children):
            out.append(pad + "VStack")
            for child in children { walk(child, indent: indent + 1, into: &out) }

        case let .horizontalStack(_, children):
            out.append(pad + "HStack")
            for child in children { walk(child, indent: indent + 1, into: &out) }

        case let .facts(pairs):
            out.append(pad + "FactSet")
            for pair in pairs {
                out.append(
                    "\(pad)  Fact title=\(quote(pair.title)) value=\(quote(pair.value))"
                )
            }

        case let .code(text, language, _):
            let attrs: [String] = language.flatMap { ["language=\($0)"] } ?? []
            // Truncate the code body for the dump — assistive tech reads
            // it linearly, but the dump is for shape review.
            let first = text.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) ?? ""
            let preview = first.count > 60 ? String(first.prefix(60)) + "…" : first
            out.append(line(pad: pad, role: "CodeBlock", name: quote(preview), attrs: attrs))

        case let .textField(id, label, placeholder, value, isRequired, isMultiline):
            var attrs: [String] = ["id=\(id)"]
            if isRequired { attrs.append("required") }
            if isMultiline { attrs.append("multiline") }
            if label == nil || (label ?? "").isEmpty { attrs.append("MISSING_LABEL") }
            var line = "\(pad)TextField"
            if let label = label { line += " label=\(quote(label))" }
            line += " [" + attrs.joined(separator: " ") + "]"
            out.append(line)
            if let placeholder = placeholder, !placeholder.isEmpty {
                out.append("\(pad)  placeholder=\(quote(placeholder))")
            }
            if let value = value, !value.isEmpty {
                out.append("\(pad)  value=\(quote(value))")
            }

        case let .numberField(id, label, placeholder, value, isRequired):
            var attrs: [String] = ["id=\(id)"]
            if isRequired { attrs.append("required") }
            if label == nil || (label ?? "").isEmpty { attrs.append("MISSING_LABEL") }
            var line = "\(pad)NumberField"
            if let label = label { line += " label=\(quote(label))" }
            line += " [" + attrs.joined(separator: " ") + "]"
            out.append(line)
            if let placeholder = placeholder, !placeholder.isEmpty {
                out.append("\(pad)  placeholder=\(quote(placeholder))")
            }
            if let value = value {
                out.append("\(pad)  value=\(value)")
            }

        case let .toggleField(id, title, label, value, valueOn, valueOff, isRequired):
            var attrs: [String] = ["id=\(id)"]
            if isRequired { attrs.append("required") }
            attrs.append(value ? "on" : "off")
            var line = "\(pad)Toggle title=\(quote(title))"
            if let label = label, !label.isEmpty {
                line += " label=\(quote(label))"
            }
            line += " [" + attrs.joined(separator: " ") + "]"
            out.append(line)
            out.append("\(pad)  valueOn=\(quote(valueOn)) valueOff=\(quote(valueOff))")

        case let .choiceField(id, label, choices, selected, isMultiSelect, isRequired):
            var attrs: [String] = ["id=\(id)"]
            attrs.append(isMultiSelect ? "multiSelect" : "singleSelect")
            if isRequired { attrs.append("required") }
            if label == nil || (label ?? "").isEmpty { attrs.append("MISSING_LABEL") }
            var line = "\(pad)ChoiceField"
            if let label = label { line += " label=\(quote(label))" }
            line += " [" + attrs.joined(separator: " ") + "]"
            out.append(line)
            for choice in choices {
                let mark = (selected == choice.value) ? "*" : " "
                out.append(
                    "\(pad)  [\(mark)] title=\(quote(choice.title)) value=\(quote(choice.value))"
                )
            }

        case let .progressBar(value, label):
            var attrs: [String] = [String(format: "value=%.2f", value)]
            if let label = label, !label.isEmpty {
                out.append("\(pad)ProgressBar label=\(quote(label)) [\(attrs.joined(separator: " "))]")
            } else {
                attrs.append("MISSING_LABEL")
                out.append("\(pad)ProgressBar [\(attrs.joined(separator: " "))]")
            }

        case let .spinner(label):
            if let label = label, !label.isEmpty {
                out.append("\(pad)Spinner label=\(quote(label))")
            } else {
                // A spinner with no label tells screen-reader users
                // nothing about what's loading; flag it.
                out.append("\(pad)Spinner [MISSING_LABEL]")
            }

        case let .accordion(panels):
            out.append("\(pad)Accordion")
            for panel in panels {
                let state = panel.isExpanded ? "expanded" : "collapsed"
                out.append("\(pad)  AccordionPanel title=\(quote(panel.title)) [\(state)]")
                for child in panel.content {
                    walk(child, indent: indent + 2, into: &out)
                }
            }

        case let .table(headers, rows):
            out.append("\(pad)Table")
            if let headers = headers {
                out.append("\(pad)  HeaderRow")
                for (idx, cell) in headers.enumerated() {
                    out.append("\(pad)    HeaderCell column=\(idx)")
                    for child in cell {
                        walk(child, indent: indent + 3, into: &out)
                    }
                }
            }
            for (rowIdx, row) in rows.enumerated() {
                out.append("\(pad)  Row index=\(rowIdx)")
                for (cellIdx, cell) in row.enumerated() {
                    out.append("\(pad)    Cell column=\(cellIdx)")
                    for child in cell {
                        walk(child, indent: indent + 3, into: &out)
                    }
                }
            }

        case let .rating(value, max, count):
            var attrs: [String] = [String(format: "value=%.1f", value), "max=\(max)"]
            if let count = count { attrs.append("count=\(count)") }
            // Rating without a programmatically-readable name is opaque
            // to screen readers; we synthesize one for the dump.
            let synthName = String(format: "%.1f out of %d stars", value, max)
            out.append("\(pad)Rating name=\(quote(synthName)) [\(attrs.joined(separator: " "))]")

        case let .dateField(id, label, placeholder, value, isRequired):
            var attrs: [String] = ["id=\(id)"]
            if isRequired { attrs.append("required") }
            if label == nil || (label ?? "").isEmpty { attrs.append("MISSING_LABEL") }
            var line = "\(pad)DateField"
            if let label = label { line += " label=\(quote(label))" }
            line += " [" + attrs.joined(separator: " ") + "]"
            out.append(line)
            if let placeholder = placeholder, !placeholder.isEmpty {
                out.append("\(pad)  placeholder=\(quote(placeholder))")
            }
            if let value = value, !value.isEmpty {
                out.append("\(pad)  value=\(quote(value))")
            }

        case let .timeField(id, label, placeholder, value, isRequired):
            var attrs: [String] = ["id=\(id)"]
            if isRequired { attrs.append("required") }
            if label == nil || (label ?? "").isEmpty { attrs.append("MISSING_LABEL") }
            var line = "\(pad)TimeField"
            if let label = label { line += " label=\(quote(label))" }
            line += " [" + attrs.joined(separator: " ") + "]"
            out.append(line)
            if let placeholder = placeholder, !placeholder.isEmpty {
                out.append("\(pad)  placeholder=\(quote(placeholder))")
            }
            if let value = value, !value.isEmpty {
                out.append("\(pad)  value=\(quote(value))")
            }

        case let .chart(kind, title, data, showLegend):
            // Charts are a known screen-reader weak point: pixel-only
            // visualizations carry no semantic data. Enumerating every
            // (label, value) pair under a `ChartData` group gives
            // assistive tech a verbatim, navigable reading of the same
            // information the sighted user sees. The dump also flags
            // charts without a title since that's the only programmatic
            // name the chart group will expose.
            var attrs: [String] = ["kind=\(kind.rawValue)"]
            attrs.append(showLegend ? "legend" : "noLegend")
            if title == nil || (title ?? "").isEmpty { attrs.append("MISSING_TITLE") }
            var header = "\(pad)Chart"
            if let title = title, !title.isEmpty { header += " title=\(quote(title))" }
            header += " [" + attrs.joined(separator: " ") + "]"
            out.append(header)
            out.append("\(pad)  ChartData count=\(data.count)")
            for datum in data {
                var datumAttrs: [String] = [String(format: "value=%.2f", datum.value)]
                if let color = datum.color, !color.isEmpty {
                    datumAttrs.append("color=\(color)")
                }
                out.append(
                    "\(pad)    Datum label=\(quote(datum.label)) [\(datumAttrs.joined(separator: " "))]"
                )
            }

        case let .tabSet(tabs, selectedTabIndex):
            // Every tab is enumerated so screen-reader users can perceive
            // the full tab strip; the selected one is annotated. Body
            // content is walked only for the selected tab to mirror what
            // the View layer actually renders.
            out.append("\(pad)TabSet selectedIndex=\(selectedTabIndex) count=\(tabs.count)")
            for (idx, tab) in tabs.enumerated() {
                let state = (idx == selectedTabIndex) ? "selected" : "unselected"
                out.append(
                    "\(pad)  Tab id=\(tab.id) title=\(quote(tab.title)) [index=\(idx) \(state)]"
                )
                if idx == selectedTabIndex {
                    for child in tab.content {
                        walk(child, indent: indent + 2, into: &out)
                    }
                }
            }

        case let .compoundButton(title, subtitle, icon, action):
            // Compound buttons combine a title + subtitle + optional icon
            // into one focusable button; the accessible name should be
            // the title alone (screen readers concatenate subtitle as a
            // hint when reading). We attach the wired action's kind
            // so the dump explains what the button does.
            var attrs: [String] = []
            if let action = action {
                attrs.append("action=\(actionKindTag(action))")
            } else {
                attrs.append("NO_ACTION")
            }
            if let icon = icon, !icon.isEmpty { attrs.append("icon=\(icon)") }
            out.append("\(pad)CompoundButton name=\(quote(title)) [\(attrs.joined(separator: " "))]")
            if let subtitle = subtitle, !subtitle.isEmpty {
                out.append("\(pad)  subtitle=\(quote(subtitle))")
            }

        case let .button(title, kind):
            out.append("\(pad)Button name=\(quote(title)) [kind=\(actionKindTag(kind))]")

        case let .unsupported(typeString):
            // Surfaces missing renderer coverage as a flag so reviewers
            // know which spec elements assistive tech won't see at all.
            out.append("\(pad)UnsupportedElement type=\(typeString) [UNRENDERED]")
        }
    }

    private static func line(
        pad: String,
        role: String,
        name: String,
        attrs: [String]
    ) -> String {
        if attrs.isEmpty {
            return "\(pad)\(role) \(name)"
        }
        return "\(pad)\(role) \(name) [\(attrs.joined(separator: " "))]"
    }

    private static func quote(_ s: String) -> String {
        // Round-trip-safe quoting: escape backslash + double-quote, wrap
        // in double quotes. Matches typical Adaptive Cards JSON
        // serialization style.
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    /// Stable, lowercase token for an `ActionKind`, used by both
    /// `.button` and `.compoundButton` dump rows so a11y reviewers see
    /// identical labels regardless of which button shape carries the
    /// action.
    private static func actionKindTag(_ kind: RenderingNode.ActionKind) -> String {
        switch kind {
        case .submit: return "submit"
        case .openUrl: return "openUrl"
        case .showCard: return "showCard"
        case .execute: return "execute"
        case .toggleVisibility: return "toggleVisibility"
        case .popover: return "popover"
        case .runCommands: return "runCommands"
        case .openUrlDialog: return "openUrlDialog"
        case .unknown: return "unknown"
        }
    }
}
