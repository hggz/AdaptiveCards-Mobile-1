// wasm-port: Phase W7 — carousel + list + media. Closes out the
// renderer-side of the windows-port-parity matrix; W8 onwards is the
// demo / examples / CABI / docs / PR work.

#if canImport(JavaScriptKit)
import Foundation
import JavaScriptKit
import AdaptiveCardsRenderingIR

extension DOMRenderer {

    /// `.carousel(pages, selectedPageIndex, autoAdvanceMs)` -> selected
    /// page rendered inline + page-position indicator. When
    /// `autoAdvanceMs != nil`, a WCAG SC 2.2.2 "Pause" button is added.
    /// Live page switching is deferred (matches windows-port behaviour).
    internal func makeCarouselElement(
        pages: [CarouselPageItem],
        selectedPageIndex: Int,
        autoAdvanceMs: Int?
    ) -> JSObject {
        let element = createElement("section", dataACNode: "carousel")
        element.className = JSValue.string("ac-carousel")
        _ = element.setAttribute!(
            "aria-roledescription", "carousel")
        _ = element.setAttribute!(
            "data-ac-selected-page-index", String(selectedPageIndex))
        if let autoAdvanceMs {
            _ = element.setAttribute!(
                "data-ac-auto-advance-ms", String(autoAdvanceMs))
        }

        let clamped = pages.indices.contains(selectedPageIndex)
            ? selectedPageIndex
            : 0

        // Page-position indicator: one dot per page, with the currently-
        // selected page marked. ARIA `tablist` / `tab` semantics mirror
        // the windows-port a11y baseline shape.
        let dots = document.createElement!("div").object!
        dots.className = JSValue.string("ac-carousel-dots")
        _ = dots.setAttribute!("role", "tablist")
        for (idx, page) in pages.enumerated() {
            let dot = document.createElement!("span").object!
            dot.className = JSValue.string(
                "ac-carousel-dot\(idx == clamped ? " ac-carousel-dot-selected" : "")")
            _ = dot.setAttribute!("role", "tab")
            _ = dot.setAttribute!("data-ac-page-id", page.id)
            _ = dot.setAttribute!("data-ac-page-index", String(idx))
            _ = dot.setAttribute!(
                "aria-selected", idx == clamped ? "true" : "false")
            _ = dot.setAttribute!(
                "aria-label", "Page \(idx + 1) of \(pages.count)")
            _ = dots.appendChild!(dot)
        }
        _ = element.appendChild!(dots)

        // WCAG SC 2.2.2: any auto-advancing carousel must offer a way
        // to pause it. Render the button even though live cycling is
        // deferred, so the a11y surface is correct and hosts that wire
        // up live cycling later don't have to re-render the tree.
        if autoAdvanceMs != nil {
            let pause = document.createElement!("button").object!
            pause.className = JSValue.string("ac-carousel-pause")
            _ = pause.setAttribute!("type", "button")
            _ = pause.setAttribute!(
                "aria-label",
                "Pause auto-advancing carousel (WCAG SC 2.2.2)")
            _ = pause.setAttribute!("data-ac-carousel-pause", "true")
            pause.textContent = JSValue.string("⏸")
            _ = element.appendChild!(pause)
        }

        if pages.indices.contains(clamped) {
            let selectedPage = pages[clamped]
            let panel = document.createElement!("div").object!
            panel.className = JSValue.string("ac-carousel-page")
            _ = panel.setAttribute!("role", "tabpanel")
            _ = panel.setAttribute!("data-ac-page-id", selectedPage.id)
            // `selectAction` (page-level click target) is propagated as
            // an attribute marker; full click wiring requires the
            // dispatcher hook and is parked alongside live page nav.
            if let action = selectedPage.selectAction {
                _ = panel.setAttribute!(
                    "data-ac-select-action-kind", Self.tag(for: action))
            }
            for child in selectedPage.content {
                _ = panel.appendChild!(makeElement(for: child))
            }
            _ = element.appendChild!(panel)
        }
        return element
    }

    /// `.list(style, items)` -> <ul> / <ol> / <div> per `ListStyle`.
    /// Distinct from `verticalStack` because screen readers announce
    /// "list, N items" when the element uses a list role.
    internal func makeListElement(
        style: ListStyle, items: [RenderingNode]
    ) -> JSObject {
        let tag: String
        switch style {
        case .bulleted: tag = "ul"
        case .numbered: tag = "ol"
        case .default:  tag = "div"
        }
        let element = createElement(tag, dataACNode: "list")
        element.className = JSValue.string("ac-list ac-list-\(style.rawValue)")
        _ = element.setAttribute!("data-ac-list-style", style.rawValue)

        let isMarkerless = (style == .default)
        for item in items {
            if isMarkerless {
                // `.default` uses no marker -> render directly into the
                // <div> so descendants are first-class children.
                _ = element.appendChild!(makeElement(for: item))
            } else {
                let li = document.createElement!("li").object!
                li.className = JSValue.string("ac-list-item")
                _ = li.appendChild!(makeElement(for: item))
                _ = element.appendChild!(li)
            }
        }
        return element
    }

    /// `.media(sources, posterURL, altText)` -> native <video> or
    /// <audio> element (chosen by mime-type prefix). When no usable
    /// source is available, falls back to a textual summary mirroring
    /// the windows-port view: poster image + alt-text caption + a
    /// list of mime/url rows.
    ///
    /// Missing / empty `altText` is left to the A11yDump to surface as
    /// a WCAG 1.2.1 / 1.2.2 violation — the renderer doesn't shout at
    /// the developer.
    internal func makeMediaElement(
        sources: [MediaSource],
        posterURL: String?,
        altText: String?
    ) -> JSObject {
        let element = createElement("figure", dataACNode: "media")
        element.className = JSValue.string("ac-media")

        let videoSources = sources.filter {
            $0.mimeType.hasPrefix("video/")
        }
        let audioSources = sources.filter {
            $0.mimeType.hasPrefix("audio/")
        }

        if !videoSources.isEmpty {
            let video = document.createElement!("video").object!
            video.className = JSValue.string("ac-media-video")
            _ = video.setAttribute!("controls", "")
            if let posterURL, !posterURL.isEmpty {
                _ = video.setAttribute!("poster", posterURL)
            }
            if let altText, !altText.isEmpty {
                _ = video.setAttribute!("aria-label", altText)
            }
            for source in videoSources {
                let s = document.createElement!("source").object!
                _ = s.setAttribute!("src", source.url)
                _ = s.setAttribute!("type", source.mimeType)
                _ = video.appendChild!(s)
            }
            _ = element.appendChild!(video)
        } else if !audioSources.isEmpty {
            let audio = document.createElement!("audio").object!
            audio.className = JSValue.string("ac-media-audio")
            _ = audio.setAttribute!("controls", "")
            if let altText, !altText.isEmpty {
                _ = audio.setAttribute!("aria-label", altText)
            }
            for source in audioSources {
                let s = document.createElement!("source").object!
                _ = s.setAttribute!("src", source.url)
                _ = s.setAttribute!("type", source.mimeType)
                _ = audio.appendChild!(s)
            }
            _ = element.appendChild!(audio)
        } else {
            // No usable source -> textual summary path.
            if let posterURL, !posterURL.isEmpty {
                let poster = document.createElement!("img").object!
                poster.className = JSValue.string("ac-media-poster")
                _ = poster.setAttribute!("src", posterURL)
                _ = poster.setAttribute!("alt", altText ?? "")
                _ = element.appendChild!(poster)
            }
            for source in sources {
                let row = document.createElement!("div").object!
                row.className = JSValue.string("ac-media-source")
                _ = row.setAttribute!("data-ac-mime", source.mimeType)
                row.textContent = JSValue.string(
                    "\(source.mimeType): \(source.url)")
                _ = element.appendChild!(row)
            }
        }

        if let altText, !altText.isEmpty {
            let caption = document.createElement!("figcaption").object!
            caption.className = JSValue.string("ac-media-caption")
            caption.textContent = JSValue.string(altText)
            _ = element.appendChild!(caption)
        }
        return element
    }
}
#endif
