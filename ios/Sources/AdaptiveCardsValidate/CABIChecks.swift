//
//  CABIChecks.swift
//  AdaptiveCardsValidate — windows-port
//
//  Exercises the AdaptiveCardsCABI surface from Swift. We call the
//  `@_cdecl` exports directly with `UnsafePointer<CChar>` arguments
//  (since they're plain C functions, Swift can invoke them the same way
//  a C host would). Catches signature drift, memory-management
//  regressions, and action-callback round-trip breakage.
//

import Foundation
import AdaptiveCardsCABI

/// Convert a Swift String to an `UnsafeMutablePointer<CChar>` allocated
/// via `strdup` so the test can call `ac_*` functions exactly the way
/// a C host would.
private func cstr(_ s: String) -> UnsafeMutablePointer<CChar>? {
    s.withCString { strdup($0) }
}

func runCABIChecks(_ r: Runner) {
    r.section("AdaptiveCardsCABI C-ABI surface")

    // Lifecycle: create + destroy.
    let cfg = cstr("{}")
    defer { free(cfg) }
    guard let host = ac_host_create(cfg) else {
        r.check(false, "ac_host_create returned NULL")
        return
    }
    r.check(true, "ac_host_create returned non-NULL handle")

    // backend identifier round-trip.
    if let bp = ac_host_backend_identifier(host) {
        let s = String(cString: bp)
        ac_free(bp)
        r.check(!s.isEmpty, "ac_host_backend_identifier returned non-empty: \(s)")
    } else {
        r.check(false, "ac_host_backend_identifier returned NULL")
    }

    // render_json round-trip.
    let cardJSON = """
    {
      "type": "AdaptiveCard",
      "version": "1.6",
      "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
      "body": [
        { "type": "TextBlock", "text": "Hi", "size": "Large", "weight": "Bolder" }
      ],
      "actions": [
        { "type": "Action.Submit", "title": "Send" }
      ]
    }
    """
    let cardPtr = cstr(cardJSON)
    defer { free(cardPtr) }
    if let renderedPtr = ac_host_render_json(host, cardPtr) {
        let rendered = String(cString: renderedPtr)
        ac_free(renderedPtr)
        r.check(rendered.contains("verticalStack"), "render JSON contains a verticalStack root")
        r.check(rendered.contains("\"Hi\""), "render JSON preserves TextBlock content")
        r.check(rendered.contains("\"Send\""), "render JSON preserves action title")
    } else {
        let err = ac_last_error().flatMap { String(cString: $0) } ?? "<no error>"
        r.check(false, "ac_host_render_json returned NULL: \(err)")
    }

    // Bad JSON path -> NULL + ac_last_error populated.
    let badCard = cstr("not valid json")
    defer { free(badCard) }
    let bad = ac_host_render_json(host, badCard)
    if bad == nil {
        let err = ac_last_error().flatMap { String(cString: $0) } ?? ""
        r.check(!err.isEmpty, "bad JSON -> ac_last_error populated: \(err)")
    } else {
        ac_free(bad)
        r.check(false, "bad JSON should have returned NULL")
    }

    // Action callback round-trip via ac_host_fire_action.
    // We use a Box pattern with a global to avoid the closure-state
    // complications of @convention(c) callbacks.
    Box.shared.reset()
    let cb: @convention(c) (Int32, UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void = { kind, payload, _ in
        let p = payload.flatMap { String(cString: $0) } ?? ""
        Box.shared.record(kind: kind, payload: p)
    }
    ac_host_set_action_callback(host, cb, nil)

    let submitPayload = cstr("{\"verb\":\"submit\"}")
    defer { free(submitPayload) }
    ac_host_fire_action(host, 0 /* AC_KIND_SUBMIT */, submitPayload)
    let openUrlPayload = cstr("https://example.com")
    defer { free(openUrlPayload) }
    ac_host_fire_action(host, 1 /* AC_KIND_OPEN_URL */, openUrlPayload)
    ac_host_fire_action(host, 2 /* AC_KIND_SHOW_CARD */, nil)

    r.equal(Box.shared.events.count, 3, "callback fired 3 times")
    if Box.shared.events.count >= 3 {
        r.equal(Box.shared.events[0].kind, 0, "first event is Submit")
        r.equal(Box.shared.events[0].payload, #"{"verb":"submit"}"#, "Submit payload round-trip")
        r.equal(Box.shared.events[1].kind, 1, "second event is OpenUrl")
        r.equal(Box.shared.events[1].payload, "https://example.com", "OpenUrl payload round-trip")
        r.equal(Box.shared.events[2].kind, 2, "third event is ShowCard")
        r.equal(Box.shared.events[2].payload, "", "ShowCard payload nil maps to empty")
    }

    // Clearing the callback should drop further events.
    ac_host_set_action_callback(host, nil, nil)
    ac_host_fire_action(host, 0, submitPayload)
    r.equal(Box.shared.events.count, 3, "no further events after callback cleared")

    ac_host_destroy(host)
    r.check(true, "ac_host_destroy returned")
}

/// Module-global box for the C callback to write into. The Swift
/// validator runs single-threaded so we don't need synchronisation
/// here.
private final class Box {
    static let shared = Box()
    private init() {}

    struct Event { let kind: Int32; let payload: String }
    private(set) var events: [Event] = []

    func reset() { events.removeAll() }
    func record(kind: Int32, payload: String) {
        events.append(Event(kind: kind, payload: payload))
    }
}
