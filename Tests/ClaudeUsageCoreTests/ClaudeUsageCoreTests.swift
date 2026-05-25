import XCTest
@testable import ClaudeUsageCore

final class ClaudeUsageCoreTests: XCTestCase {

    // MARK: - Status line payload (unix-seconds resets, used_percentage)

    func testStatusLinePayloadParsesRateLimits() throws {
        let json = """
        {
          "model": { "display_name": "Opus 4.7" },
          "context_window": { "used_percentage": 8.0 },
          "rate_limits": {
            "five_hour": { "used_percentage": 23.5, "resets_at": 1738425600 },
            "seven_day": { "used_percentage": 41.2, "resets_at": 1738857600 }
          }
        }
        """
        let payload = try StatusLinePayload(from: Data(json.utf8))
        let snapshot = try XCTUnwrap(payload.usageSnapshot())

        XCTAssertEqual(snapshot.source, .statusLine)
        XCTAssertEqual(snapshot.fiveHour?.utilization, 23.5)
        XCTAssertEqual(snapshot.fiveHour?.resetsAt, Date(timeIntervalSince1970: 1738425600))
        XCTAssertEqual(snapshot.sevenDay?.utilization, 41.2)
        XCTAssertEqual(payload.contextPercentage, 8.0)
    }

    func testStatusLinePayloadWithoutRateLimitsYieldsNil() throws {
        let json = #"{ "context_window": { "used_percentage": 12 } }"#
        let payload = try StatusLinePayload(from: Data(json.utf8))
        XCTAssertNil(payload.usageSnapshot())
        XCTAssertEqual(payload.contextPercentage, 12)
    }

    // MARK: - OAuth response (ISO8601 resets, utilization, extras)

    func testOAuthResponseParsesRealSchema() throws {
        // Verbatim shape from a live /api/oauth/usage response.
        let json = """
        {
          "five_hour": { "utilization": 45.0, "resets_at": "2026-05-25T19:00:00.402962+00:00" },
          "seven_day": { "utilization": 7.0, "resets_at": "2026-06-01T09:00:00.402993+00:00" },
          "seven_day_opus": null,
          "seven_day_sonnet": { "utilization": 0.0, "resets_at": null },
          "extra_usage": {
            "is_enabled": true, "monthly_limit": 8000, "used_credits": 1139.0,
            "utilization": 14.2375, "currency": "USD", "disabled_reason": null
          }
        }
        """
        let response = try JSONDecoder().decode(OAuthUsageResponse.self, from: Data(json.utf8))
        let snapshot = response.usageSnapshot()

        XCTAssertEqual(snapshot.source, .oauthAPI)
        XCTAssertEqual(snapshot.fiveHour?.utilization, 45.0)
        XCTAssertNotNil(snapshot.fiveHour?.resetsAt)
        XCTAssertNil(snapshot.sevenDayOpus)
        XCTAssertEqual(snapshot.sevenDaySonnet?.utilization, 0.0)
        XCTAssertNil(snapshot.sevenDaySonnet?.resetsAt)
        XCTAssertEqual(snapshot.extraUsage?.isEnabled, true)
        XCTAssertEqual(snapshot.extraUsage?.usedCredits, 1139.0)
        XCTAssertEqual(snapshot.extraUsage?.currency, "USD")
    }

    func testISO8601ParsesFractionalAndPlain() {
        XCTAssertNotNil(ISO8601.date(from: "2026-05-25T19:00:00.402962+00:00"))
        XCTAssertNotNil(ISO8601.date(from: "2026-05-25T19:00:00Z"))
        XCTAssertNil(ISO8601.date(from: nil))
        XCTAssertNil(ISO8601.date(from: ""))
    }

    // MARK: - Keychain credential parsing (without touching the real Keychain)

    func testCredentialParsingHandlesMillisecondExpiry() throws {
        let ms = 4_102_444_800_000.0 // year 2100 in ms
        let json = """
        { "claudeAiOauth": { "accessToken": "abc123", "expiresAt": \(Int(ms)) } }
        """
        let creds = try KeychainCredentials.parse(Data(json.utf8))
        XCTAssertEqual(creds.accessToken, "abc123")
        XCTAssertEqual(creds.expiresAt, Date(timeIntervalSince1970: ms / 1000))
        XCTAssertFalse(creds.isExpired())
    }

    func testCredentialExpiryDetection() throws {
        let pastSeconds = Date().addingTimeInterval(-3600).timeIntervalSince1970
        let json = """
        { "claudeAiOauth": { "accessToken": "x", "expiresAt": \(Int(pastSeconds)) } }
        """
        let creds = try KeychainCredentials.parse(Data(json.utf8))
        XCTAssertTrue(creds.isExpired())
    }

    func testMalformedCredentialsThrow() {
        XCTAssertThrowsError(try KeychainCredentials.parse(Data("{}".utf8)))
    }

    func testBestCredentialPicksLatestExpiry() {
        let stale = ClaudeCredentials(accessToken: "old", expiresAt: Date(timeIntervalSince1970: 1_000))
        let live = ClaudeCredentials(accessToken: "new", expiresAt: Date(timeIntervalSince1970: 9_999_999_999))
        let noExpiry = ClaudeCredentials(accessToken: "none", expiresAt: nil)
        XCTAssertEqual(KeychainCredentials.best(from: [stale, live, noExpiry])?.accessToken, "new")
        XCTAssertEqual(KeychainCredentials.best(from: [noExpiry, stale])?.accessToken, "old")
        XCTAssertNil(KeychainCredentials.best(from: []))
    }

    // MARK: - Formatting

    func testCountdownFormatting() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(UsageFormatting.countdown(to: now.addingTimeInterval(72 * 60), now: now), "1h 12m left")
        XCTAssertEqual(UsageFormatting.countdown(to: now.addingTimeInterval(60 * 60), now: now), "1h left")
        XCTAssertEqual(UsageFormatting.countdown(to: now.addingTimeInterval(12 * 60), now: now), "12m left")
        XCTAssertEqual(UsageFormatting.countdown(to: now.addingTimeInterval(30), now: now), "<1m left")
        XCTAssertNil(UsageFormatting.countdown(to: now.addingTimeInterval(-60), now: now))
        XCTAssertNil(UsageFormatting.countdown(to: nil, now: now))
    }

    func testCountdownRollsUpToDays() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        // 159h 53m -> 6d 15h (the weekly-window case that previously read "159h").
        XCTAssertEqual(UsageFormatting.countdown(to: now.addingTimeInterval(159 * 3600 + 53 * 60), now: now), "6d 15h left")
        // Whole days drop the hours.
        XCTAssertEqual(UsageFormatting.countdown(to: now.addingTimeInterval(48 * 3600), now: now), "2d left")
        XCTAssertEqual(UsageFormatting.countdown(to: now.addingTimeInterval(25 * 3600), now: now, style: .short), "1d 1h")
    }

    func testCountdownRejectsImplausiblyFarResets() {
        // Bad data (a reset far in the future) should show no countdown, not "1392d".
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertNil(UsageFormatting.countdown(to: now.addingTimeInterval(400 * 86_400), now: now))
        // A normal weekly reset (under a week) is still fine.
        XCTAssertNotNil(UsageFormatting.countdown(to: now.addingTimeInterval(6 * 86_400), now: now))
    }

    func testCountdownShortStyleDropsSuffix() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(UsageFormatting.countdown(to: now.addingTimeInterval(72 * 60), now: now, style: .short), "1h 12m")
        XCTAssertEqual(UsageFormatting.countdown(to: now.addingTimeInterval(12 * 60), now: now, style: .short), "12m")
    }

    func testMenuBarTitle() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let snapshot = UsageSnapshot(
            fiveHour: UsageWindow(utilization: 45.4, resetsAt: now.addingTimeInterval(72 * 60)),
            source: .oauthAPI,
            capturedAt: now
        )
        XCTAssertEqual(UsageFormatting.menuBarTitle(snapshot, showTime: false, now: now), "45%")
        XCTAssertEqual(UsageFormatting.menuBarTitle(snapshot, showTime: true, now: now), "45% (1h 12m)")
        XCTAssertEqual(UsageFormatting.menuBarTitle(nil, showTime: true, now: now), "—")
    }

    // MARK: - Usage rows (shared presentation, the single source of labels)

    func testUsageRowsLabelsOrderAndModelBrackets() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let reset = now.addingTimeInterval(72 * 60)
        let snapshot = UsageSnapshot(
            fiveHour: UsageWindow(utilization: 52, resetsAt: reset),
            sevenDay: UsageWindow(utilization: 8, resetsAt: reset),
            sevenDayOpus: UsageWindow(utilization: 3, resetsAt: nil),
            sevenDaySonnet: UsageWindow(utilization: 0, resetsAt: nil),
            extraUsage: ExtraUsage(isEnabled: true, utilization: 14, usedCredits: 1139, monthlyLimit: 8000, currency: "USD"),
            source: .oauthAPI,
            capturedAt: now
        )

        let rows = snapshot.rows(now: now)
        XCTAssertEqual(rows.map(\.title), [
            "Session (5h)", "Weekly (7d)", "Weekly (Opus)", "Weekly (Sonnet)", "Usage credits",
        ])
        // The requested change: model name in round brackets, not "Weekly · Sonnet".
        XCTAssertTrue(rows.contains { $0.title == "Weekly (Sonnet)" })
        XCTAssertFalse(rows.contains { $0.title.contains("·") })

        XCTAssertEqual(rows[0].percent, "52%")
        XCTAssertEqual(rows[0].countdown, "1h 12m left")
        // Cents -> dollars: $11.39 spent of an $80 cap (matches Claude's UI).
        XCTAssertEqual(rows.last?.detail, "$11.39 / $80")
    }

    func testUsageRowsOmitMissingWindows() {
        let snapshot = UsageSnapshot(
            fiveHour: UsageWindow(utilization: 10, resetsAt: nil),
            source: .statusLine
        )
        let rows = snapshot.rows()
        XCTAssertEqual(rows.map(\.title), ["Session (5h)"])
        XCTAssertNil(rows[0].countdown)
    }

    func testUsageSourceDisplayName() {
        XCTAssertEqual(UsageSource.statusLine.displayName, "via status line")
        XCTAssertEqual(UsageSource.oauthAPI.displayName, "via usage API")
    }

    // MARK: - Cache round-trip

    func testCacheRoundTrip() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("claude-usage-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let cache = UsageCache(url: tmp)
        XCTAssertNil(cache.load())

        let snapshot = UsageSnapshot(
            fiveHour: UsageWindow(utilization: 50, resetsAt: Date(timeIntervalSince1970: 1_700_000_000)),
            source: .statusLine,
            capturedAt: Date(timeIntervalSince1970: 1_699_999_000)
        )
        try cache.save(snapshot)
        XCTAssertEqual(cache.load(), snapshot)
    }
}
