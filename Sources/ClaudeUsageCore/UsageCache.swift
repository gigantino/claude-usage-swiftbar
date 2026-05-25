import Foundation

/// On-disk cache shared between the CLI (writer, via the status line) and the
/// menu bar app (reader + occasional writer via the OAuth poll).
///
/// The file is the single source of truth the UI renders, so writes are atomic
/// to avoid the reader ever seeing a torn JSON document.
public struct UsageCache: Sendable {
    public let url: URL

    public static let `default` = UsageCache()

    public init(url: URL? = nil) {
        if let url {
            self.url = url
        } else {
            let base = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("ClaudeUsageBar", isDirectory: true)
            self.url = base.appendingPathComponent("usage.json")
        }
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Returns the cached snapshot, or `nil` if absent/unreadable.
    public func load() -> UsageSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? Self.decoder.decode(UsageSnapshot.self, from: data)
    }

    /// Atomically persists a snapshot, creating the directory if needed.
    public func save(_ snapshot: UsageSnapshot) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try Self.encoder.encode(snapshot)
        try data.write(to: url, options: .atomic)
    }
}
