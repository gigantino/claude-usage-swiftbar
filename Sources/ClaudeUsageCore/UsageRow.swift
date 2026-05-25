import Foundation

/// One presentable line of usage, the unit both the CLI and the menu bar render.
///
/// Centralizing the row list here keeps the labels (like `Weekly (Sonnet)`) in a
/// single place, so the two UIs can never drift apart.
public struct UsageRow: Sendable, Equatable, Identifiable {
    /// Display label, with any model name in round brackets.
    public let title: String
    public let percent: String
    /// Reset countdown like "1h 12m left", or `nil` when unknown or past.
    public let countdown: String?
    /// Supplementary detail, like the credit balance "$11.39 / $80".
    public let detail: String?

    public var id: String { title }

    public init(title: String, percent: String, countdown: String? = nil, detail: String? = nil) {
        self.title = title
        self.percent = percent
        self.countdown = countdown
        self.detail = detail
    }
}

public extension UsageSnapshot {
    /// The ordered rows to display for this snapshot. Windows without a usable
    /// percentage are omitted.
    func rows(now: Date = Date()) -> [UsageRow] {
        var rows: [UsageRow] = []

        func append(_ title: String, _ window: UsageWindow?) {
            guard let window, let percent = UsageFormatting.percent(window.utilization) else { return }
            rows.append(UsageRow(
                title: title,
                percent: percent,
                countdown: UsageFormatting.countdown(to: window.resetsAt, now: now)
            ))
        }

        append("Session (5h)", fiveHour)
        append("Weekly (7d)", sevenDay)
        append("Weekly (Opus)", sevenDayOpus)
        append("Weekly (Sonnet)", sevenDaySonnet)

        if let extra = extraUsage, extra.isEnabled, let percent = UsageFormatting.percent(extra.utilization) {
            // Claude calls this "Usage credits" in its own UI; match that wording.
            rows.append(UsageRow(title: "Usage credits", percent: percent, detail: Self.creditDetail(extra)))
        }

        return rows
    }

    /// Formats spend as "$11.39 / $80". The API gives these as integer cents.
    private static func creditDetail(_ extra: ExtraUsage) -> String? {
        guard let used = extra.usedCredits, let limit = extra.monthlyLimit else { return nil }
        return "\(money(cents: used, currency: extra.currency)) / \(money(cents: limit, currency: extra.currency))"
    }

    private static func money(cents: Double, currency: String?) -> String {
        let amount = cents / 100
        // Trailing-zero cents read as whole dollars, matching Claude's "$80".
        let value = amount == amount.rounded() ? String(format: "%.0f", amount) : String(format: "%.2f", amount)
        switch currency {
        case "USD", nil: return "$\(value)"
        case let code?: return "\(value) \(code)"
        }
    }
}
