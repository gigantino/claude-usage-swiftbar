import Foundation

/// Presentation helpers shared by the CLI and the menu bar app, so both render
/// percentages and reset countdowns identically.
public enum UsageFormatting {
    /// How a countdown is phrased.
    public enum CountdownStyle {
        /// Long form like "1h 12m left", used in standalone rows.
        case long
        /// Short form like "1h 12m", used in the menu bar title.
        case short
    }

    /// Rounds to a whole percent, like "45%".
    public static func percent(_ value: Double?) -> String? {
        guard let value else { return nil }
        return "\(Int(value.rounded()))%"
    }

    /// "1h 12m left", "12m left", or "<1m left" relative to `now`. Returns nil if
    /// the reset time is unknown or already in the past.
    public static func countdown(to resetsAt: Date?, now: Date = Date(), style: CountdownStyle = .long) -> String? {
        guard let resetsAt else { return nil }
        let seconds = Int(resetsAt.timeIntervalSince(now))
        guard seconds > 0 else { return nil }
        // The windows we track reset within a week. Treat anything well beyond that
        // as bad data and show no countdown rather than an absurd one.
        guard seconds <= 8 * 86_400 else { return nil }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3600
        let minutes = (seconds % 3600) / 60

        // Roll up to the two largest non-zero units (e.g. "6d 15h", "1h 12m").
        let magnitude: String
        if days > 0 { magnitude = hours > 0 ? "\(days)d \(hours)h" : "\(days)d" }
        else if hours > 0 { magnitude = minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
        else if minutes > 0 { magnitude = "\(minutes)m" }
        else { magnitude = "<1m" }

        switch style {
        case .long: return "\(magnitude) left"
        case .short: return magnitude
        }
    }

    /// The compact menu bar title, like "45%" or "45% (1h 12m)".
    public static func menuBarTitle(_ snapshot: UsageSnapshot?, showTime: Bool, now: Date = Date()) -> String {
        guard let window = snapshot?.fiveHour, let pct = percent(window.utilization) else {
            return "—"
        }
        if showTime, let cd = countdown(to: window.resetsAt, now: now, style: .short) {
            return "\(pct) (\(cd))"
        }
        return pct
    }

    /// How stale a snapshot is, in human terms, e.g. "updated 2m ago".
    public static func freshness(_ snapshot: UsageSnapshot?, now: Date = Date()) -> String? {
        guard let snapshot else { return nil }
        let seconds = Int(now.timeIntervalSince(snapshot.capturedAt))
        let phrase: String
        switch seconds {
        case ..<10: phrase = "just now"
        case ..<60: phrase = "\(seconds)s ago"
        case ..<3600: phrase = "\(seconds / 60)m ago"
        default: phrase = "\(seconds / 3600)h ago"
        }
        return "updated \(phrase)"
    }
}
