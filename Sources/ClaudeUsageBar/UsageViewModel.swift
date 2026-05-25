import Foundation
import Combine
import ClaudeUsageCore

/// Drives the menu bar UI from two data sources:
///
///  - The status-line cache file is re-read on a short timer, so updates written
///    while a Claude Code session is open appear almost immediately, for free,
///    with no API calls and no Keychain access.
///  - The OAuth usage endpoint can be polled on a timer to refresh data when no
///    session is open and to add the weekly, per-model, and credit figures the
///    status line omits. This reads the token from the Keychain, which prompts
///    for consent, so it is opt-in and off by default.
@MainActor
final class UsageViewModel: ObservableObject {
    enum RefreshInterval: Int, CaseIterable, Identifiable {
        case off = 0
        case fiveMinutes = 300
        case tenMinutes = 600
        case fifteenMinutes = 900

        var id: Int { rawValue }
        var label: String {
            switch self {
            case .off: return "Off"
            case .fiveMinutes: return "Every 5 min"
            case .tenMinutes: return "Every 10 min"
            case .fifteenMinutes: return "Every 15 min"
            }
        }
    }

    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var statusMessage: String?
    @Published private(set) var isPolling = false

    @Published var showTimeInTitle: Bool {
        didSet { defaults.set(showTimeInTitle, forKey: Keys.showTime) }
    }
    @Published var refreshInterval: RefreshInterval {
        didSet {
            defaults.set(refreshInterval.rawValue, forKey: Keys.interval)
            restartPollTimer()
            // Enabling polling should show fresh data right away rather than after
            // a full interval. This is a deliberate user action, so prompting for
            // Keychain access here is expected.
            if refreshInterval != .off { refreshNow() }
        }
    }

    /// Bumped on a ticking timer so the relative-time labels ("updated 2m ago",
    /// countdowns) keep advancing without needing new data.
    @Published private(set) var clock = Date()

    private enum Keys {
        static let showTime = "showTimeInTitle"
        static let interval = "refreshIntervalSeconds"
    }

    /// How long to wait before the next OAuth poll after various outcomes. The
    /// endpoint punishes frequent calls, so these lean conservative.
    private enum Backoff {
        static let minimum: TimeInterval = 60
        static let afterRateLimit: TimeInterval = 300
        static let afterAuthFailure: TimeInterval = 900
        static let afterError: TimeInterval = 120
    }

    private let cache: UsageCache
    private let client: OAuthUsageClient
    private let defaults: UserDefaults

    private var cacheTimer: Timer?
    private var pollTimer: Timer?
    private var clockTimer: Timer?
    private var nextOAuthAllowed = Date.distantPast

    init(cache: UsageCache = .default, client: OAuthUsageClient = OAuthUsageClient(), defaults: UserDefaults = .standard) {
        self.cache = cache
        self.client = client
        self.defaults = defaults
        self.showTimeInTitle = defaults.object(forKey: Keys.showTime) as? Bool ?? true
        let storedInterval = defaults.object(forKey: Keys.interval) as? Int ?? RefreshInterval.off.rawValue
        self.refreshInterval = RefreshInterval(rawValue: storedInterval) ?? .off

        self.snapshot = cache.load()
        startTimers()
        // Poll once at launch only if the user has opted into API polling.
        Task { await pollIfNeeded(force: false) }
    }

    // MARK: - Title

    var menuBarTitle: String {
        UsageFormatting.menuBarTitle(snapshot, showTime: showTimeInTitle, now: clock)
    }

    // MARK: - Actions

    /// User-initiated refresh: always attempts a poll, bypassing the cadence
    /// timer but still respecting a short backoff after a 429.
    func refreshNow() {
        Task { await pollIfNeeded(force: true) }
    }

    // MARK: - Timers

    private func startTimers() {
        // Re-read the cache file frequently; load() is cheap and Equatable guards
        // against redundant publishes.
        cacheTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reloadCache() }
        }
        clockTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.clock = Date() }
        }
        restartPollTimer()
    }

    private func restartPollTimer() {
        pollTimer?.invalidate()
        pollTimer = nil
        guard refreshInterval != .off else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(refreshInterval.rawValue), repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.pollIfNeeded(force: false) }
        }
    }

    private func reloadCache() {
        guard let latest = cache.load(), latest != snapshot else { return }
        // Don't let an older cache overwrite fresher in-memory data.
        if let current = snapshot, latest.capturedAt < current.capturedAt { return }
        snapshot = latest
    }

    // MARK: - OAuth poll

    private func pollIfNeeded(force: Bool) async {
        // Automatic polls only run when the user has enabled an interval; a forced
        // poll (the Refresh button) always runs.
        if !force && refreshInterval == .off { return }
        if !force && Date() < nextOAuthAllowed { return }
        if isPolling { return }
        isPolling = true
        defer { isPolling = false }

        do {
            let fresh = try await client.fetch()
            try? cache.save(fresh)
            snapshot = fresh
            statusMessage = nil
            backOff(max(TimeInterval(refreshInterval.rawValue), Backoff.minimum))
        } catch let error as OAuthUsageError {
            statusMessage = error.description
            switch error {
            case .rateLimited(let retryAfter):
                backOff(retryAfter ?? Backoff.afterRateLimit)
            case .tokenExpired, .unauthorized:
                // Rely on the status-line feed; back off well past a normal cadence.
                backOff(Backoff.afterAuthFailure)
            default:
                backOff(Backoff.afterError)
            }
        } catch {
            statusMessage = "\(error)"
            backOff(Backoff.afterError)
        }
    }

    private func backOff(_ interval: TimeInterval) {
        nextOAuthAllowed = Date().addingTimeInterval(interval)
    }
}
