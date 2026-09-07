//
//  ActionRouter.swift
//  AdaptiveCardsWindowsDemo — windows-port
//
//  Bridges `RenderingNode.ActionKind` values fired by the renderer to
//  the host system. The library deliberately stays side-effect-free
//  (it just emits `ActionKind` through the `onAction` closure); this
//  file is where the *demo* decides what to actually do with each
//  kind on Windows.
//
//  Today's coverage:
//    * `.openUrl(url)` -> opens the system default browser via
//      `ShellExecuteW` (the same Win32 call every WinUI / WPF / WinForms
//      app uses for "launch this URL").
//    * everything else -> not handled natively; the caller still gets
//      the transcript line so the action is observable.
//
//  Why not in the library?
//    * Embedding hosts (other WinUI apps, Electron, future Linux/macOS
//      hosts) want to make their own routing choices -- some block
//      external URLs entirely, some route through an in-app browser,
//      some require auth interception. Baking ShellExecuteW into the
//      library would force a policy on those hosts. The cleaner contract
//      is "library emits an enum, host decides".
//

import Foundation
import AdaptiveCardsCrossUI

#if canImport(WinSDK)
import WinSDK
#endif

enum ActionRouter {
    /// Try to handle an action natively. Returns `true` when the host
    /// did something user-visible (e.g. launched the browser) so the
    /// transcript can annotate accordingly. Returning `false` doesn't
    /// indicate failure -- it just means the action kind is one the
    /// router intentionally leaves to the transcript.
    @discardableResult
    static func execute(_ action: RenderingNode.ActionKind) -> Bool {
        switch action {
        case .openUrl(let url):
            return openInDefaultBrowser(url)
        case .submit,
             .showCard,
             .execute,
             .toggleVisibility,
             .popover,
             .runCommands,
             .openUrlDialog,
             .unknown:
            // Submit + Execute payloads are already in `onAction`'s
            // string for the transcript; ShowCard / ToggleVisibility /
            // Popover / RunCommands / OpenUrlDialog would need UI
            // state mutations the demo doesn't track yet, so they're
            // logged-but-not-acted-on (matches Teams' behaviour when
            // the host opts out of those kinds).
            return false
        }
    }

    /// Launch `url` in the system default browser via `ShellExecuteW`.
    /// Returns `true` on success per the documented Win32 contract:
    /// the returned `HINSTANCE` is a fake handle; values > 32 mean OK,
    /// values <= 32 are SE_ERR_* codes.
    /// See: https://learn.microsoft.com/en-us/windows/win32/api/shellapi/nf-shellapi-shellexecutew
    static func openInDefaultBrowser(_ url: String) -> Bool {
        #if canImport(WinSDK)
        // ShellExecuteW expects UTF-16 wide strings. Foundation's
        // String.withCString(encodedAs: UTF16.self) gives us a
        // null-terminated UTF-16 buffer for the duration of the closure.
        return url.withCString(encodedAs: UTF16.self) { wurl in
            "open".withCString(encodedAs: UTF16.self) { wverb in
                guard let h = ShellExecuteW(nil, wverb, wurl, nil, nil, Int32(SW_SHOWNORMAL)) else {
                    return false
                }
                // HINSTANCE returned by ShellExecuteW: pointer values > 32 mean
                // success; values <= 32 are SE_ERR_* error codes packed into
                // the pointer's low bits. Convert via UnsafeRawPointer's
                // bit pattern to compare.
                return Int(bitPattern: UnsafeRawPointer(h)) > 32
            }
        }
        #else
        return false
        #endif
    }
}
