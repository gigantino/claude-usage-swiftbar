import Foundation

/// Decodes the JSON that Claude Code pipes to the `statusLine` command on stdin.
///
/// Only the fields we care about are modeled; everything is optional because the
/// `rate_limits` object appears only for Pro/Max OAuth logins, after the first API
/// response in a session, and each window can be independently absent.
/// Reset timestamps here are Unix epoch *seconds*.
public struct StatusLinePayload: Decodable, Sendable {
    public struct ContextWindow: Decodable, Sendable {
        public let usedPercentage: Double?
        enum CodingKeys: String, CodingKey { case usedPercentage = "used_percentage" }
    }

    public struct Window: Decodable, Sendable {
        public let usedPercentage: Double?
        public let resetsAt: Double?
        enum CodingKeys: String, CodingKey {
            case usedPercentage = "used_percentage"
            case resetsAt = "resets_at"
        }
    }

    public struct RateLimits: Decodable, Sendable {
        public let fiveHour: Window?
        public let sevenDay: Window?
        enum CodingKeys: String, CodingKey {
            case fiveHour = "five_hour"
            case sevenDay = "seven_day"
        }
    }

    public let contextWindow: ContextWindow?
    public let rateLimits: RateLimits?

    enum CodingKeys: String, CodingKey {
        case contextWindow = "context_window"
        case rateLimits = "rate_limits"
    }

    public init(from data: Data) throws {
        self = try JSONDecoder().decode(StatusLinePayload.self, from: data)
    }

    /// Percentage of the context window used (0...100), if present.
    public var contextPercentage: Double? { contextWindow?.usedPercentage }

    /// Maps the payload's rate-limit fields into a normalized snapshot, or `nil`
    /// when no rate-limit data is present (e.g. API-key users or pre-first-response).
    public func usageSnapshot(now: Date = Date()) -> UsageSnapshot? {
        guard let limits = rateLimits else { return nil }

        func window(_ w: StatusLinePayload.Window?) -> UsageWindow? {
            guard let w, let pct = w.usedPercentage else { return nil }
            let reset = w.resetsAt.map { Date(timeIntervalSince1970: $0) }
            return UsageWindow(utilization: pct, resetsAt: reset)
        }

        let five = window(limits.fiveHour)
        let seven = window(limits.sevenDay)
        guard five != nil || seven != nil else { return nil }

        return UsageSnapshot(
            fiveHour: five,
            sevenDay: seven,
            source: .statusLine,
            capturedAt: now
        )
    }
}
