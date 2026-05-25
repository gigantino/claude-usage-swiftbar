import Foundation

public enum OAuthUsageError: Error, CustomStringConvertible {
    case tokenExpired
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case invalidResponse
    case http(status: Int)
    case decoding(Error)
    case transport(Error)

    public var description: String {
        switch self {
        case .tokenExpired: return "OAuth token expired; skipping poll until Claude Code refreshes it."
        case .unauthorized: return "OAuth request was unauthorized (401)."
        case .rateLimited(let r): return "OAuth usage endpoint rate-limited (429)" + (r.map { ", retry after \(Int($0))s." } ?? ".")
        case .invalidResponse: return "OAuth usage endpoint returned a non-HTTP response."
        case .http(let s): return "OAuth usage request failed with HTTP \(s)."
        case .decoding(let e): return "Failed to decode OAuth usage response: \(e)"
        case .transport(let e): return "Network error contacting OAuth usage endpoint: \(e)"
        }
    }
}

/// Fetches usage from `GET https://api.anthropic.com/api/oauth/usage`.
///
/// This endpoint rate-limits aggressively (HTTP 429) and recovers slowly, so the
/// caller must poll infrequently and back off. The client does no retrying of its
/// own; it surfaces a structured error and lets the poller decide what to do.
public struct OAuthUsageClient: Sendable {
    public let endpoint: URL
    public let session: URLSession

    public init(
        endpoint: URL = URL(string: "https://api.anthropic.com/api/oauth/usage")!,
        session: URLSession = .shared
    ) {
        self.endpoint = endpoint
        self.session = session
    }

    public func fetch(now: Date = Date()) async throws -> UsageSnapshot {
        let credentials = try KeychainCredentials.read()
        guard !credentials.isExpired(now: now) else { throw OAuthUsageError.tokenExpired }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw OAuthUsageError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw OAuthUsageError.invalidResponse
        }

        switch http.statusCode {
        case 200:
            do {
                // Stamp capturedAt when the response arrives, not when the request
                // started, so freshness reflects the data's real age.
                return try JSONDecoder().decode(OAuthUsageResponse.self, from: data).usageSnapshot(now: Date())
            } catch {
                throw OAuthUsageError.decoding(error)
            }
        case 401:
            throw OAuthUsageError.unauthorized
        case 429:
            let retryAfter = (http.value(forHTTPHeaderField: "retry-after")).flatMap(TimeInterval.init)
            throw OAuthUsageError.rateLimited(retryAfter: retryAfter)
        default:
            throw OAuthUsageError.http(status: http.statusCode)
        }
    }
}
