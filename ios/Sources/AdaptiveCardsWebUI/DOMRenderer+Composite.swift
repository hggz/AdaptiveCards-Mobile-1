// wasm-port: Phase W6 — composite display nodes (chart, tabSet,
// compoundButton). All three layer additional structure on top of the
// W2-W5 primitives. `.compoundButton` reuses the same JSClosure click
// dispatch pattern as `.button` via `installClickDispatch`.

#if canImport(JavaScriptKit)
import JavaScriptKit
import AdaptiveCardsRenderingIR

extension DOMRenderer {

    /// `.chart(kind, title, data, showLegend)` -> labelled data table
    /// with one row per datum (label, value, optional color swatch). A
    /// proper SVG visualization per `kind` is a later refinement; the
    /// IR + a11y baselines only care about the label/value/color
    /// tuples, so the table form is fully baseline-equivalent.
    internal func makeChartElement(
        kind: ChartKind,
        title: String?,
        data: [ChartDatum],
        showLegend: Bool
    ) -> JSObject {
        let element = createElement("figure", dataACNode: "chart")
        element.className = JSValue.string("ac-chart ac-chart-\(kind.rawValue)")
        _ = element.setAttribute!("data-ac-chart-kind", kind.rawValue)
        _ = element.setAttribute!(
            "data-ac-show-legend", showLegend ? "true" : "false")

        if let title, !title.isEmpty {
            let caption = document.createElement!("figcaption").object!
            caption.className = JSValue.string("ac-chart-title")
            caption.textContent = JSValue.string(title)
            _ = element.appendChild!(caption)
        }

        let table = document.createElement!("table").object!
        table.className = JSValue.string("ac-chart-table")
        let body = document.createElement!("tbody").object!
        for datum in data {
            let tr = document.createElement!("tr").object!
            tr.className = JSValue.string("ac-chart-datum")

            if let color = datum.color, !color.isEmpty {
                let swatch = document.createElement!("td").object!
                swatch.className = JSValue.string("ac-chart-swatch")
                _ = swatch.setAttribute!("data-ac-chart-color", color)
                if let style = swatch.style.object {
                    style.backgroundColor = JSValue.string(color)
                }
                _ = tr.appendChild!(swatch)
            }

            let labelCell = document.createElement!("td").object!
            labelCell.className = JSValue.string("ac-chart-label")
            labelCell.textContent = JSValue.string(datum.label)
            _ = tr.appendChild!(labelCell)

            let valueCell = document.createElement!("td").object!
            valueCell.className = JSValue.string("ac-chart-value")
            valueCell.textContent = JSValue.string(String(datum.value))
            _ = tr.appendChild!(valueCell)

            _ = body.appendChild!(tr)
        }
        _ = table.appendChild!(body)
        _ = element.appendChild!(table)
        return element
    }

    /// `.tabSet(tabs, selectedTabIndex)` -> ARIA `tablist` + clickable
    /// tab buttons + the selected tab's panel rendered inline. Other
    /// panels are not rendered (live tab switching is deferred).
    internal func makeTabSetElement(
        tabs: [TabItem],
        selectedTabIndex: Int
    ) -> JSObject {
        let element = createElement("div", dataACNode: "tabSet")
        element.className = JSValue.string("ac-tabset")
        _ = element.setAttribute!(
            "data-ac-selected-tab-index", String(selectedTabIndex))

        let tablist = document.createElement!("div").object!
        tablist.className = JSValue.string("ac-tabset-tablist")
        _ = tablist.setAttribute!("role", "tablist")

        let clampedIndex = tabs.indices.contains(selectedTabIndex)
            ? selectedTabIndex
            : 0
        for (idx, tab) in tabs.enumerated() {
            let tabButton = document.createElement!("button").object!
            tabButton.className = JSValue.string(
                "ac-tabset-tab\(idx == clampedIndex ? " ac-tabset-tab-selected" : "")")
            _ = tabButton.setAttribute!("type", "button")
            _ = tabButton.setAttribute!("role", "tab")
            _ = tabButton.setAttribute!("data-ac-tab-id", tab.id)
            _ = tabButton.setAttribute!("data-ac-tab-index", String(idx))
            _ = tabButton.setAttribute!(
                "aria-selected", idx == clampedIndex ? "true" : "false")
            _ = tabButton.setAttribute!(
                "tabindex", idx == clampedIndex ? "0" : "-1")
            tabButton.textContent = JSValue.string(tab.title)
            _ = tablist.appendChild!(tabButton)
        }
        _ = element.appendChild!(tablist)

        if tabs.indices.contains(clampedIndex) {
            let selectedTab = tabs[clampedIndex]
            let panel = document.createElement!("div").object!
            panel.className = JSValue.string("ac-tabset-panel")
            _ = panel.setAttribute!("role", "tabpanel")
            _ = panel.setAttribute!("data-ac-tab-id", selectedTab.id)
            for child in selectedTab.content {
                _ = panel.appendChild!(makeElement(for: child))
            }
            _ = element.appendChild!(panel)
        }
        return element
    }

    /// `.compoundButton(title, subtitle, icon, action)` -> stacked-text
    /// `<button>` with an optional icon `<img>` and the same dispatch
    /// behaviour as `.button`. `action == nil` renders the button
    /// without a click handler (purely informational).
    internal func makeCompoundButtonElement(
        title: String,
        subtitle: String?,
        icon: String?,
        action: RenderingNode.ActionKind?
    ) -> JSObject {
        let element = createElement("button", dataACNode: "compoundButton")
        element.className = JSValue.string("ac-compound-button")
        _ = element.setAttribute!("type", "button")
        if let action {
            _ = element.setAttribute!(
                "data-ac-action-kind", Self.tag(for: action))
        }

        if let icon, !icon.isEmpty {
            let img = document.createElement!("img").object!
            img.className = JSValue.string("ac-compound-button-icon")
            _ = img.setAttribute!("src", icon)
            _ = img.setAttribute!("alt", "")
            _ = element.appendChild!(img)
        }

        let textStack = document.createElement!("span").object!
        textStack.className = JSValue.string("ac-compound-button-text")

        let titleEl = document.createElement!("span").object!
        titleEl.className = JSValue.string("ac-compound-button-title")
        titleEl.textContent = JSValue.string(title)
        _ = textStack.appendChild!(titleEl)

        if let subtitle, !subtitle.isEmpty {
            let subtitleEl = document.createElement!("span").object!
            subtitleEl.className = JSValue.string("ac-compound-button-subtitle")
            subtitleEl.textContent = JSValue.string(subtitle)
            _ = textStack.appendChild!(subtitleEl)
        }
        _ = element.appendChild!(textStack)

        if let action {
            installClickDispatch(on: element, action: action)
        }
        return element
    }
}
#endif
