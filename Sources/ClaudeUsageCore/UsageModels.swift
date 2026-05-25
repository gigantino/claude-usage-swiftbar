import Foundation

/// Where a snapshot came from. The status line is free and real-time but only
/// updates while a Claude Code session is open; the OAuth API works any time but
/// is rate-limited, so we record the origin to reason about freshness.
public enum UsageSource: String, Codable, Sendable {
    case statusLine
    case oauthAPI

    public var displayName: String {
        switch self {
        case .statusLine: return "via status line"
        case .oauthAPI: return "via usage API"
        }
    }
}

/// A single rate-limit window, normalized across both data sources.
public struct UsageWindow: Codable, Sendable, Equatable {
    /// Percentage of the window consumed, 0...100.
    public var utilization: Double
    public var resetsAt: Date?

    public init(utilization: Double, resetsAt: Date?) {
        self.utilization = utilization
        self.resetsAt = resetsAt
    }
}

/// Pay-as-you-go "extra usage" credits, only exposed by the OAuth API.
public struct ExtraUsage: Codable, Sendable, Equatable {
    public var isEnabled: Bool
    public var utilization: Double?
    public var usedCredits: Double?
    public var monthlyLimit: Double?
    public var currency: String?

    public init(isEnabled: Bool, utilization: Double?, usedCredits: Double?, monthlyLimit: Double?, currency: String?) {
        self.isEnabled = isEnabled
        self.utilization = utilization
        self.usedCredits = usedCredits
        self.monthlyLimit = monthlyLimit
        self.currency = currency
    }
}

/// The normalized usage snapshot that the cache stores and the UI renders.
/// Both the status-line payload and the OAuth response are mapped into this.
public struct UsageSnapshot: Codable, Sendable, Equatable {
    public var fiveHour: UsageWindow?
    public var sevenDay: UsageWindow?
    public var sevenDayOpus: UsageWindow?
    public var sevenDaySonnet: UsageWindow?
    public var extraUsage: ExtraUsage?
    public var source: UsageSource
    public var capturedAt: Date

    public init(
        fiveHour: UsageWindow? = nil,
        sevenDay: UsageWindow? = nil,
        sevenDayOpus: UsageWindow? = nil,
        sevenDaySonnet: UsageWindow? = nil,
        extraUsage: ExtraUsage? = nil,
        source: UsageSource,
        capturedAt: Date = Date()
    ) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.sevenDayOpus = sevenDayOpus
        self.sevenDaySonnet = sevenDaySonnet
        self.extraUsage = extraUsage
        self.source = source
        self.capturedAt = capturedAt
    }
}
