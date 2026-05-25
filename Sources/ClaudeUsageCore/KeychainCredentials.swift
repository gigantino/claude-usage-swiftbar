import Foundation
import Security

/// The OAuth credentials Claude Code stores in the macOS login Keychain under the
/// generic-password service `Claude Code-credentials`.
public struct ClaudeCredentials: Sendable {
    public let accessToken: String
    public let expiresAt: Date?

    /// True when we have a concrete expiry that is in the past.
    public func isExpired(now: Date = Date(), leeway: TimeInterval = 60) -> Bool {
        guard let expiresAt else { return false }
        return now.addingTimeInterval(leeway) >= expiresAt
    }
}

public enum KeychainError: Error, CustomStringConvertible {
    case notFound
    case accessDenied(OSStatus)
    case malformed
    case unexpected(OSStatus)

    public var description: String {
        switch self {
        case .notFound: return "Claude Code credentials were not found in the Keychain. Is Claude Code logged in?"
        case .accessDenied(let s): return "Keychain access was denied (OSStatus \(s)). Allow access when prompted."
        case .malformed: return "The stored credentials could not be parsed."
        case .unexpected(let s): return "Unexpected Keychain error (OSStatus \(s))."
        }
    }
}

/// Reads Claude Code's OAuth token from the Keychain. Strictly read only.
///
/// We never write or refresh the token: Claude's refresh tokens rotate, so
/// refreshing here would race Claude Code's own credential store and force a
/// re-login. If the token is expired we simply skip the OAuth poll and let the
/// CLI refresh it during normal use.
public enum KeychainCredentials {
    public static let service = "Claude Code-credentials"

    public static func read(service: String = service) throws -> ClaudeCredentials {
        // Claude Code can leave more than one item under this service (e.g. after
        // reinstalls), and only one holds the live token. Fetch them all and pick
        // the credential with the latest expiry, so a stale duplicate can't win.
        // The legacy login keychain rejects matchLimitAll + returnData together
        // (errSecParam), so fetch item references for every match, then read each
        // item's data individually.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            break
        case errSecItemNotFound:
            throw KeychainError.notFound
        case errSecAuthFailed, errSecInteractionNotAllowed, errSecUserCanceled:
            throw KeychainError.accessDenied(status)
        default:
            throw KeychainError.unexpected(status)
        }

        let refs: [AnyObject]
        if let array = result as? [AnyObject] {
            refs = array
        } else if let single = result {
            refs = [single]
        } else {
            refs = []
        }

        let candidates = refs.compactMap { ref -> ClaudeCredentials? in
            guard let data = readData(forRef: ref) else { return nil }
            return try? parse(data)
        }
        guard let best = best(from: candidates) else { throw KeychainError.malformed }
        return best
    }

    /// Reads the password bytes for a single keychain item reference.
    private static func readData(forRef ref: AnyObject) -> Data? {
        let query: [String: Any] = [
            kSecValueRef as String: ref,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    /// Picks the credential most likely to be live: the one with the furthest-future
    /// expiry. Tokens without a known expiry rank last.
    static func best(from candidates: [ClaudeCredentials]) -> ClaudeCredentials? {
        candidates.max { lhs, rhs in
            (lhs.expiresAt ?? .distantPast) < (rhs.expiresAt ?? .distantPast)
        }
    }

    static func parse(_ data: Data) throws -> ClaudeCredentials {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let oauth = root["claudeAiOauth"] as? [String: Any],
            let token = oauth["accessToken"] as? String,
            !token.isEmpty
        else { throw KeychainError.malformed }

        return ClaudeCredentials(accessToken: token, expiresAt: Self.parseExpiry(oauth["expiresAt"]))
    }

    /// `expiresAt` is stored as a number; accept epoch milliseconds or seconds,
    /// and tolerate a string form.
    private static func parseExpiry(_ value: Any?) -> Date? {
        let raw: Double?
        switch value {
        case let n as Double: raw = n
        case let n as Int: raw = Double(n)
        case let s as String: raw = Double(s)
        default: raw = nil
        }
        guard let raw, raw > 0 else { return nil }
        // Heuristic: values past ~year 2286 in seconds must actually be milliseconds.
        let seconds = raw > 1_000_000_000_000 ? raw / 1000 : raw
        return Date(timeIntervalSince1970: seconds)
    }
}
