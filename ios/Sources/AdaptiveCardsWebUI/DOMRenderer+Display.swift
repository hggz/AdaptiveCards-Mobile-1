// wasm-port: Phase W5 — display-only IR cases (facts, code, progressBar,
// spinner, accordion, table, rating). All seven render as static DOM
// trees with no interactivity beyond `<details>` open/close on accordion
// (which is browser-native and doesn't need a JSClosure).
//
// These all live as an extension on `DOMRenderer` so the switch in
// `DOMRenderer.swift` stays the canonical dispatch site while the
// helpers are scoped to their own file.

#if canImport(JavaScriptKit)
import JavaScriptKit
import AdaptiveCardsRenderingIR

extension DOMRenderer {

    /// `.facts(pairs)` -> <dl class="ac-facts"> with paired <dt>/<dd>.
    /// The HTML `<dl>` semantic is the closest DOM analogue to a
    /// FactSet's (title, value) shape and gets free a11y for screen
    /// readers ("description list, N items").
    internal func makeFactsElement(
        pairs: [(title: String, value: String)]
    ) -> JSObject {
        let element = createElement("dl", dataACNode: "facts")
        element.className = JSValue.string("ac-facts")
        for pair in pairs {
            let dt = document.createElement!("dt").object!
            dt.className = JSValue.string("ac-fact-title")
            dt.textContent = JSValue.string(pair.title)
            _ = element.appendChild!(dt)

            let dd = document.createElement!("dd").object!
            dd.className = JSValue.string("ac-fact-value")
            dd.textContent = JSValue.string(pair.value)
            _ = element.appendChild!(dd)
        }
        return element
    }

    /// `.code(text, language, wrap)` -> <pre><code class="language-X">...
    /// `wrap=true` flips white-space to `pre-wrap` so long lines don't
    /// horizontal-scroll. `language=nil` omits the language class so
    /// downstream syntax highlighters (e.g. host-side highlight.js) can
    /// fall back to no-op.
    internal func makeCodeElement(
        text: String, language: String?, wrap: Bool
    ) -> JSObject {
        let pre = createElement("pre", dataACNode: "code")
        pre.className = JSValue.string("ac-code")
        if let style = pre.style.object {
            style.whiteSpace = JSValue.string(wrap ? "pre-wrap" : "pre")
        }
        let code = document.createElement!("code").object!
        if let lang = language, !lang.isEmpty {
            code.className = JSValue.string("language-\(lang)")
            _ = code.setAttribute!("data-ac-language", lang)
        }
        code.textContent = JSValue.string(text)
        _ = pre.appendChild!(code)
        return pre
    }

    /// `.progressBar(value 0...1, label)` -> labelled <progress max=1
    /// value=N>. Browsers render <progress> natively, including with
    /// indeterminate styling when no `value` is set.
    internal func makeProgressBarElement(
        value: Double, label: String?
    ) -> JSObject {
        let row = createElement("div", dataACNode: "progressBar")
        row.className = JSValue.string("ac-progressbar-row")
        if let label, !label.isEmpty {
            let labelEl = document.createElement!("span").object!
            labelEl.className = JSValue.string("ac-progressbar-label")
            labelEl.textContent = JSValue.string(label)
            _ = row.appendChild!(labelEl)
        }
        let progress = document.createElement!("progress").object!
        progress.className = JSValue.string("ac-progressbar")
        _ = progress.setAttribute!("max", "1")
        _ = progress.setAttribute!("value", String(value))
        if let label, !label.isEmpty {
            _ = progress.setAttribute!("aria-label", label)
        }
        _ = row.appendChild!(progress)
        return row
    }

    /// `.spinner(label)` -> labelled `<div role="status">` with a CSS
    /// hook so hosts can attach their own keyframe animation. Browsers
    /// don't ship an indeterminate-spinner primitive; CSS is the
    /// universally-portable approach.
    internal func makeSpinnerElement(label: String?) -> JSObject {
        let element = createElement("div", dataACNode: "spinner")
        element.className = JSValue.string("ac-spinner")
        _ = element.setAttribute!("role", "status")
        if let label, !label.isEmpty {
            _ = element.setAttribute!("aria-label", label)
            // Visually-hidden text node so screen readers still announce
            // even when the host stylesheet hides the textual label.
            let sr = document.createElement!("span").object!
            sr.className = JSValue.string("ac-spinner-label")
            sr.textContent = JSValue.string(label)
            _ = element.appendChild!(sr)
        }
        return element
    }

    /// `.accordion(panels)` -> `<div class="ac-accordion">` containing
    /// one `<details>`/`<summary>` per panel. Native `<details>` gives
    /// us keyboard / a11y / open-state for free; `isExpanded` becomes
    /// the `open` attribute.
    internal func makeAccordionElement(panels: [AccordionPanel]) -> JSObject {
        let element = createElement("div", dataACNode: "accordion")
        element.className = JSValue.string("ac-accordion")
        for panel in panels {
            let details = document.createElement!("details").object!
            details.className = JSValue.string("ac-accordion-panel")
            if panel.isExpanded {
                _ = details.setAttribute!("open", "")
            }
            let summary = document.createElement!("summary").object!
            summary.className = JSValue.string("ac-accordion-summary")
            summary.textContent = JSValue.string(panel.title)
            _ = details.appendChild!(summary)
            for child in panel.content {
                _ = details.appendChild!(makeElement(for: child))
            }
            _ = element.appendChild!(details)
        }
        return element
    }

    /// `.table(headers, rows)` -> proper `<table>` with `<thead>` /
    /// `<tbody>` / `<tr>` / `<th>` / `<td>`. Each cell recursively
    /// renders its `RenderingNode` content (cells can carry anything,
    /// including nested stacks and inputs).
    internal func makeTableElement(
        headers: [[RenderingNode]]?,
        rows: [[[RenderingNode]]]
    ) -> JSObject {
        let element = createElement("table", dataACNode: "table")
        element.className = JSValue.string("ac-table")
        if let headers, !headers.isEmpty {
            let thead = document.createElement!("thead").object!
            let headRow = document.createElement!("tr").object!
            for cell in headers {
                let th = document.createElement!("th").object!
                th.className = JSValue.string("ac-table-header")
                _ = th.setAttribute!("scope", "col")
                for child in cell {
                    _ = th.appendChild!(makeElement(for: child))
                }
                _ = headRow.appendChild!(th)
            }
            _ = thead.appendChild!(headRow)
            _ = element.appendChild!(thead)
        }
        let tbody = document.createElement!("tbody").object!
        for row in rows {
            let tr = document.createElement!("tr").object!
            for cell in row {
                let td = document.createElement!("td").object!
                td.className = JSValue.string("ac-table-cell")
                for child in cell {
                    _ = td.appendChild!(makeElement(for: child))
                }
                _ = tr.appendChild!(td)
            }
            _ = tbody.appendChild!(tr)
        }
        _ = element.appendChild!(tbody)
        return element
    }

    /// `.rating(value, max, count)` -> a row of filled / empty star
    /// glyphs and an optional `(count)` text. Read-only — interactive
    /// rating lives in `.ratingField` (W4).
    ///
    /// Glyphs:
    ///   filled  -> U+2605 BLACK STAR ★
    ///   empty   -> U+2606 WHITE STAR ☆
    /// A11y `aria-label="N of M"` carries the score for screen readers
    /// without depending on glyph recognition.
    internal func makeRatingDisplayElement(
        value: Double, max: Int, count: Int?
    ) -> JSObject {
        let element = createElement("div", dataACNode: "rating")
        element.className = JSValue.string("ac-rating-display")
        _ = element.setAttribute!("role", "img")
        _ = element.setAttribute!(
            "aria-label",
            "\(value) of \(max)\(count.map { ", \($0) ratings" } ?? "")")
        _ = element.setAttribute!("data-ac-rating-value", String(value))
        _ = element.setAttribute!("data-ac-rating-max", String(max))

        let filled = Int(value.rounded())
        var glyphs = ""
        for i in 0..<max {
            glyphs.append(i < filled ? "★" : "☆")
        }
        let glyphSpan = document.createElement!("span").object!
        glyphSpan.className = JSValue.string("ac-rating-glyphs")
        glyphSpan.textContent = JSValue.string(glyphs)
        _ = element.appendChild!(glyphSpan)

        if let count {
            let countSpan = document.createElement!("span").object!
            countSpan.className = JSValue.string("ac-rating-count")
            countSpan.textContent = JSValue.string(" (\(count))")
            _ = element.appendChild!(countSpan)
        }
        return element
    }
}
#endif
