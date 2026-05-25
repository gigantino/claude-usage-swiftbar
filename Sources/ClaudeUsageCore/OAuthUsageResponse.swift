import Foundation

/// Decodes the response from `GET https://api.anthropic.com/api/oauth/usage`.
///
/// Schema confirmed against a live response: each window uses `utilization`
/// (0...100) and an ISO8601 `resets_at` *string* (note: different field names and
/// date format from the status-line payload). Many sibling windows exist and may
/// be `null`; only the ones we surface are modeled.
struct OAuthUsageResponse: Decodable {
    struct Window: Decodable {
        let utilization: Double?
        let resetsAt: String?
        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }
    }

    struct Extra: Decodable {
        let isEnabled: Bool?
        let monthlyLimit: Double?
        let usedCredits: Double?
        let utilization: Double?
        let currency: String?
        enum CodingKeys: String, CodingKey {
            case isEnabled = "is_enabled"
            case monthlyLimit = "monthly_limit"
            case usedCredits = "used_credits"
            case utilization
            case currency
        }
    }

    let fiveHour: Window?
    let sevenDay: Window?
    let sevenDayOpus: Window?
    let sevenDaySonnet: Window?
    let extraUsage: Extra?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
        case extraUsage = "extra_usage"
    }

    func usageSnapshot(now: Date = Date()) -> UsageSnapshot {
        func window(_ w: Window?) -> UsageWindow? {
            guard let w, let util = w.utilization else { return nil }
            return UsageWindow(utilization: util, resetsAt: ISO8601.date(from: w.resetsAt))
        }

        var extra: ExtraUsage?
        if let e = extraUsage {
            extra = ExtraUsage(
                isEnabled: e.isEnabled ?? false,
                utilization: e.utilization,
                usedCredits: e.usedCredits,
                monthlyLimit: e.monthlyLimit,
                currency: e.currency
            )
        }

        return UsageSnapshot(
            fiveHour: window(fiveHour),
            sevenDay: window(sevenDay),
            sevenDayOpus: window(sevenDayOpus),
            sevenDaySonnet: window(sevenDaySonnet),
            extraUsage: extra,
            source: .oauthAPI,
            capturedAt: now
        )
    }
}

/// Tolerant ISO8601 parsing. The API emits fractional seconds with a numeric
/// timezone offset (e.g. `2026-05-25T19:00:00.402962+00:00`); fall back to the
/// non-fractional form for safety.
enum ISO8601 {
    private static let withFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func date(from string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        return withFractional.date(from: string) ?? plain.date(from: string)
    }
}
