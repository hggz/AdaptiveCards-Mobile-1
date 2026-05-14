//
//  SubmitPayload.swift
//  AdaptiveCardsCrossUI — windows-port
//
//  Pure-Swift, swift-cross-ui-free helper that builds the JSON object
//  produced by `Action.Submit` in this fork's runtime. Lifted out of
//  `AdaptiveCardView` so it can be unit-tested headlessly on every
//  platform — including in the `AdaptiveCardsValidate` harness on
//  Windows where the View layer can't be exercised directly without a
//  running event loop.
//

import Foundation

public enum SubmitPayload {

    /// Merges the static `data` blob attached to an `Action.Submit` with
    /// the live values of every input on the card.
    ///
    /// - Parameters:
    ///   - staticJSON: The pre-encoded JSON object literal from
    ///     `Action.Submit.data` (or `nil` if the action carried no data).
    ///   - textValues: Live values keyed by input.id for `Input.Text` and
    ///     `Input.Number`.
    ///   - toggleValues: Live booleans keyed by input.id for
    ///     `Input.Toggle`. The renderer is expected to convert these to
    ///     `valueOn` / `valueOff` strings; pass the resolved strings here
    ///     for spec parity.
    ///   - choiceValues: Live wire-values for `Input.ChoiceSet`.
    /// - Returns: A canonical (sorted-keys) JSON object string, or
    ///   `staticJSON` if there is nothing to merge.
    public static func merge(
        staticJSON: String?,
        textValues: [String: String] = [:],
        toggleValues: [String: String] = [:],
        choiceValues: [String: String?] = [:]
    ) -> String? {
        var bag: [String: Any] = [:]

        if let staticJSON,
           let bytes = staticJSON.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: bytes),
           let obj = parsed as? [String: Any] {
            for (k, v) in obj { bag[k] = v }
        }

        for (id, value) in textValues { bag[id] = value }
        for (id, value) in toggleValues { bag[id] = value }
        for (id, value) in choiceValues {
            if let value = value { bag[id] = value }
        }

        if bag.isEmpty { return staticJSON }

        guard let encoded = try? JSONSerialization.data(
            withJSONObject: bag,
            options: [.sortedKeys]
        ) else { return staticJSON }
        return String(data: encoded, encoding: .utf8)
    }

    // MARK: - Date/Time formatting helpers
    //
    // `Input.Date` carries an ISO-8601 calendar date string ("YYYY-MM-DD")
    // and `Input.Time` carries "HH:MM". These helpers parse and emit
    // those exact wire formats, deliberately using fixed Calendar +
    // TimeZone so the strings round-trip identically on every platform.

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Parse an Adaptive Cards `Input.Date` value (e.g. `"2025-01-01"`)
    /// into a `Date`. Returns `nil` when the input is missing or malformed.
    public static func parseDate(_ string: String?) -> Date? {
        guard let s = string, !s.isEmpty else { return nil }
        return dateFormatter.date(from: s)
    }

    /// Parse an Adaptive Cards `Input.Time` value (e.g. `"13:45"`).
    public static func parseTime(_ string: String?) -> Date? {
        guard let s = string, !s.isEmpty else { return nil }
        return timeFormatter.date(from: s)
    }

    /// Format a `Date` as ISO-8601 `"YYYY-MM-DD"`.
    public static func iso8601DateString(from date: Date) -> String {
        dateFormatter.string(from: date)
    }

    /// Format a `Date` as `"HH:MM"`.
    public static func iso8601TimeString(from date: Date) -> String {
        timeFormatter.string(from: date)
    }
}
