//
//  CABI.swift
//  AdaptiveCardsCABI — windows-port
//
//  C-callable surface for hosting Adaptive Cards from non-Swift apps
//  (Win32 / WinUI / any language with C FFI). Every public function
//  here is annotated `@_cdecl` so the symbol lands in the produced
//  static library with a stable, C-friendly name and no name
//  mangling.
//
//  Memory contract:
//    * `ac_host_create` returns an opaque `OpaquePointer` (treat as
//      `void*` from C). The caller MUST call `ac_host_destroy` once
//      and exactly once per create.
//    * Functions returning `UnsafeMutablePointer<CChar>?` allocate
//      with `strdup`. The caller MUST `ac_free` the returned pointer.
//    * Strings flowing through the boundary are UTF-8.
//    * Action callbacks fire on the same thread that produced them.
//      The host is responsible for marshalling to its UI thread if
//      required.
//
//  The header that hosts include is in
//  `examples/embed-windows/c_abi/adaptive_cards.h`. Keep that file
//  in lock-step with the signatures here.
//

import Foundation
import ACCore
import AdaptiveCardsCrossUI
import AdaptiveCardsWindowsEmbedded

// MARK: - Action-kind C enum mirror
//
// Constants match the `ACActionKind` enum in adaptive_cards.h. Bump
// both sides together if you add a new case.

private let AC_KIND_SUBMIT: Int32             = 0
private let AC_KIND_OPEN_URL: Int32           = 1
private let AC_KIND_SHOW_CARD: Int32          = 2
private let AC_KIND_EXECUTE: Int32            = 3
private let AC_KIND_TOGGLE_VISIBILITY: Int32  = 4
private let AC_KIND_POPOVER: Int32            = 5
private let AC_KIND_RUN_COMMANDS: Int32       = 6
private let AC_KIND_OPEN_URL_DIALOG: Int32    = 7
private let AC_KIND_UNKNOWN: Int32            = 99

private func cKind(for action: RenderingNode.ActionKind) -> (Int32, String?) {
    switch action {
    case let .submit(data):    return (AC_KIND_SUBMIT, data)
    case let .openUrl(url):    return (AC_KIND_OPEN_URL, url)
    case .showCard:            return (AC_KIND_SHOW_CARD, nil)
    case .execute:             return (AC_KIND_EXECUTE, nil)
    case .toggleVisibility:    return (AC_KIND_TOGGLE_VISIBILITY, nil)
    case .popover:             return (AC_KIND_POPOVER, nil)
    case .runCommands:         return (AC_KIND_RUN_COMMANDS, nil)
    case .openUrlDialog:       return (AC_KIND_OPEN_URL_DIALOG, nil)
    case let .unknown(s):      return (AC_KIND_UNKNOWN, s)
    }
}

// MARK: - C string helpers
//
// `strdup` on Windows lives in ucrt.lib under the legacy POSIX name
// `_strdup`. Swift declares it via @_silgen_name("strdup") which fails
// to resolve at C-host link time unless OLDNAMES.lib is on the link
// command. Avoid the symbol-naming dance entirely by allocating with
// `malloc` and copying the bytes ourselves; this is what swift-foundation
// does internally on Windows.
private func dupString(_ s: String) -> UnsafeMutablePointer<CChar>? {
    let utf8 = Array(s.utf8) + [0]
    let len = utf8.count
    guard let raw = malloc(len) else { return nil }
    let buf = raw.assumingMemoryBound(to: UInt8.self)
    for i in 0..<len { buf[i] = utf8[i] }
    return raw.assumingMemoryBound(to: CChar.self)
}

// MARK: - Last-error storage
//
// `ac_last_error` returns a process-global pointer to the most recent
// error message, modelled after libcurl's `curl_easy_strerror`. The
// pointer is valid until the next API call that may produce an error.

private let errorLock = NSLock()
private var lastError: UnsafeMutablePointer<CChar>?

private func setLastError(_ message: String) {
    errorLock.lock()
    defer { errorLock.unlock() }
    if let old = lastError { free(old) }
    lastError = dupString(message)
}

private func clearLastError() {
    errorLock.lock()
    defer { errorLock.unlock() }
    if let old = lastError { free(old) }
    lastError = nil
}

@_cdecl("ac_last_error")
public func ac_last_error() -> UnsafePointer<CChar>? {
    errorLock.lock()
    defer { errorLock.unlock() }
    if let p = lastError {
        return UnsafePointer(p)
    }
    return nil
}

// MARK: - Host lifecycle

@_cdecl("ac_host_create")
public func ac_host_create(_ hostConfigJSON: UnsafePointer<CChar>?) -> OpaquePointer? {
    clearLastError()
    let json = hostConfigJSON.flatMap { String(cString: $0) } ?? "{}"
    let host = AdaptiveCardHost(hostConfigJSON: json)
    let unmanaged = Unmanaged.passRetained(host)
    return OpaquePointer(unmanaged.toOpaque())
}

@_cdecl("ac_host_destroy")
public func ac_host_destroy(_ handle: OpaquePointer?) {
    guard let handle = handle else { return }
    let raw = UnsafeRawPointer(handle)
    Unmanaged<AdaptiveCardHost>.fromOpaque(raw).release()
}

// MARK: - Rendering

/// Render an Adaptive Card JSON document into the canonical
/// `RenderingNode` JSON. Returns a `strdup`-allocated UTF-8 string the
/// caller must release with `ac_free`. On parse/render failure returns
/// `NULL` and stores the error message under `ac_last_error`.
@_cdecl("ac_host_render_json")
public func ac_host_render_json(
    _ handle: OpaquePointer?,
    _ cardJSON: UnsafePointer<CChar>?
) -> UnsafeMutablePointer<CChar>? {
    clearLastError()
    guard let handle = handle, let cardJSON = cardJSON else {
        setLastError("ac_host_render_json: handle or card JSON is NULL")
        return nil
    }
    let host = Unmanaged<AdaptiveCardHost>
        .fromOpaque(UnsafeRawPointer(handle))
        .takeUnretainedValue()
    let json = String(cString: cardJSON)
    do {
        let rendered = try host.renderJSON(json: json)
        return dupString(rendered)
    } catch {
        setLastError("ac_host_render_json: \(error.localizedDescription)")
        return nil
    }
}

/// Release a string returned by `ac_host_render_json` or
/// `ac_host_backend_identifier`.
@_cdecl("ac_free")
public func ac_free(_ pointer: UnsafeMutablePointer<CChar>?) {
    if let p = pointer { free(p) }
}

/// Returns a freshly-allocated UTF-8 identifier for the active rendering
/// backend ("winui", "appkit", "uikit", "gtk", "unknown"). Caller frees
/// with `ac_free`.
@_cdecl("ac_host_backend_identifier")
public func ac_host_backend_identifier(_ handle: OpaquePointer?) -> UnsafeMutablePointer<CChar>? {
    guard let handle = handle else { return dupString("unknown") }
    let host = Unmanaged<AdaptiveCardHost>
        .fromOpaque(UnsafeRawPointer(handle))
        .takeUnretainedValue()
    return dupString(host.backendIdentifier)
}

// MARK: - Action callback

public typealias ACActionCallbackC = @convention(c) (
    _ kind: Int32,
    _ payloadUTF8: UnsafePointer<CChar>?,
    _ userdata: UnsafeMutableRawPointer?
) -> Void

@_cdecl("ac_host_set_action_callback")
public func ac_host_set_action_callback(
    _ handle: OpaquePointer?,
    _ callback: ACActionCallbackC?,
    _ userdata: UnsafeMutableRawPointer?
) {
    guard let handle = handle else { return }
    let host = Unmanaged<AdaptiveCardHost>
        .fromOpaque(UnsafeRawPointer(handle))
        .takeUnretainedValue()
    guard let callback = callback else {
        host.onAction = nil
        return
    }
    host.onAction = { actionKind in
        let (kindCode, payload) = cKind(for: actionKind)
        if let payload = payload {
            payload.withCString { cstr in
                callback(kindCode, cstr, userdata)
            }
        } else {
            callback(kindCode, nil, userdata)
        }
    }
}

/// Synthesise an action firing from C, for cases where the host has its
/// own UI and wants to invoke the registered `onAction` callback
/// directly (e.g. wiring up a host-side Submit button). The `payload`
/// argument is interpreted as JSON data for the Submit case and as a
/// URL for OpenUrl; other kinds ignore it.
@_cdecl("ac_host_fire_action")
public func ac_host_fire_action(
    _ handle: OpaquePointer?,
    _ kind: Int32,
    _ payloadUTF8: UnsafePointer<CChar>?
) {
    guard let handle = handle else { return }
    let host = Unmanaged<AdaptiveCardHost>
        .fromOpaque(UnsafeRawPointer(handle))
        .takeUnretainedValue()
    guard let callback = host.onAction else { return }
    let payload = payloadUTF8.flatMap { String(cString: $0) }
    let action: RenderingNode.ActionKind
    switch kind {
    case AC_KIND_SUBMIT:            action = .submit(dataJSON: payload)
    case AC_KIND_OPEN_URL:          action = .openUrl(payload ?? "")
    case AC_KIND_SHOW_CARD:         action = .showCard
    case AC_KIND_EXECUTE:           action = .execute
    case AC_KIND_TOGGLE_VISIBILITY: action = .toggleVisibility
    case AC_KIND_POPOVER:           action = .popover
    case AC_KIND_RUN_COMMANDS:      action = .runCommands
    case AC_KIND_OPEN_URL_DIALOG:   action = .openUrlDialog
    default:                        action = .unknown(payload ?? "")
    }
    callback(action)
}
