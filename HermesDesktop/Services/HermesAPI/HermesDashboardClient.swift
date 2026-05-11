import Foundation

/// HTTP client for the real Hermes dashboard at port 9119 (default).
///
/// Distinct from the legacy `URLSessionHermesAPIClient` (which speaks the
/// Python bridge's contract at port 8765, removed from the runtime path
/// in Work Unit 6). This client speaks the real Hermes contract documented
/// in `Docs/Phases/Phase1/REALITY.md` — `/api/*` paths, JSON bodies, with
/// auth via `Authorization: Bearer <ephemeral-session-token>` injected on
/// every request.
///
/// Token resolution is closure-injected. In production the closure pulls
/// the current token from `HermesProcessSupervisor.health` (a `.running`
/// case carries the token). Tests inject a canned closure. The closure
/// signature accepts a `forceRefresh` hint that the 401-recovery path
/// uses to ask for a freshly-read token after the dashboard restarted
/// and rotated the token — the supervisor's contract guarantees a fresh
/// token on every dashboard process start per Phase 0.5 REALITY.md
/// ("Token rotation on restart: verified").
public final class HermesDashboardClient: @unchecked Sendable {

    /// Closure that returns the current Hermes dashboard session token,
    /// optionally forcing a re-read after a 401 response indicates the
    /// previous token went stale (dashboard restart).
    public typealias TokenProvider = @Sendable (_ forceRefresh: Bool) async throws -> String

    // MARK: Configuration

    public let baseURL: URL
    /// Per-request timeout. The dashboard's own responses are fast but
    /// startup may take a few seconds; matches Phase 0's
    /// `HermesAPIEndpointConfig.requestTimeout` convention.
    public let requestTimeout: TimeInterval

    // MARK: Errors

    public enum ClientError: Error, Equatable {
        /// Token provider threw or the supervisor isn't `.running`.
        case notAuthenticated(reason: String)
        /// Dashboard returned 401 even after a forced token refresh.
        case authFailedAfterRefresh
        /// HTTP non-2xx response with status code and body preview.
        case httpStatus(code: Int, body: String)
        /// Response body could not be decoded into the expected shape.
        case decoding(String)
        /// Network call failed (timeout, refused, DNS, etc.).
        case transport(String)
    }

    // MARK: Internals

    private let tokenProvider: TokenProvider
    private let session: URLSession
    private let decoder: JSONDecoder

    public static let defaultBaseURL: URL = URL(string: "http://127.0.0.1:9119")!

    public init(
        baseURL: URL = HermesDashboardClient.defaultBaseURL,
        requestTimeout: TimeInterval = 8,
        tokenProvider: @escaping TokenProvider,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.requestTimeout = requestTimeout
        self.tokenProvider = tokenProvider
        self.session = session

        let decoder = JSONDecoder()
        // Hermes wire format is snake_case throughout. Same convention as
        // Phase 0's URLSessionHermesAPIClient. Preserved per SCOPE.md WU3.
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            // Hermes mixes ISO 8601 strings and Unix timestamps. Accept
            // both; the message timestamp field is sometimes a Double
            // (Unix epoch) while session timestamps are ISO strings.
            if let s = try? container.decode(String.self),
               let date = HermesDashboardDateParser.parse(s) {
                return date
            }
            if let n = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: n)
            }
            if let i = try? container.decode(Int.self) {
                return Date(timeIntervalSince1970: TimeInterval(i))
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognized date format"
            )
        }
        self.decoder = decoder
    }

    // MARK: Public surface — endpoints required by SCOPE.md WU3 acceptance

    /// `GET /api/status` — verified live during Phase 0.5.
    public func status() async throws -> HermesDashboardStatus {
        try await get("/api/status")
    }

    /// `GET /api/sessions` — paginated.
    public func sessions(limit: Int? = nil, offset: Int? = nil) async throws -> HermesDashboardSessionList {
        var queryItems: [URLQueryItem] = []
        if let limit { queryItems.append(URLQueryItem(name: "limit", value: String(limit))) }
        if let offset { queryItems.append(URLQueryItem(name: "offset", value: String(offset))) }
        return try await get("/api/sessions", queryItems: queryItems)
    }

    /// `GET /api/sessions/{id}`.
    public func session(id: String) async throws -> HermesDashboardSession {
        try await get("/api/sessions/\(percentEscape(id))")
    }

    /// `GET /api/sessions/{id}/messages`.
    public func messages(sessionID: String) async throws -> HermesDashboardMessagesResponse {
        try await get("/api/sessions/\(percentEscape(sessionID))/messages")
    }

    /// `GET /api/skills` — flat array.
    public func skills() async throws -> [HermesDashboardSkill] {
        try await get("/api/skills")
    }

    /// `GET /api/config`.
    public func config() async throws -> HermesDashboardConfig {
        try await get("/api/config")
    }

    /// `GET /api/cron/jobs` — flat array.
    public func cronJobs() async throws -> [HermesDashboardCronJob] {
        try await get("/api/cron/jobs")
    }

    /// `GET /api/profiles` — wrapped.
    public func profiles() async throws -> HermesDashboardProfilesResponse {
        try await get("/api/profiles")
    }

    /// `GET /api/model/info`.
    public func modelInfo() async throws -> HermesDashboardModelInfo {
        try await get("/api/model/info")
    }

    /// `GET /api/providers/oauth`. Inference-provider OAuth catalog only —
    /// Composio connectors live elsewhere and are a Phase 4 concern.
    public func oauthProviders() async throws -> HermesDashboardOAuthProvidersResponse {
        try await get("/api/providers/oauth")
    }

    // MARK: Internals — request pipeline

    private func get<T: Decodable>(_ path: String,
                                   queryItems: [URLQueryItem] = []) async throws -> T {
        let url = buildURL(path: path, queryItems: queryItems)

        // Attempt 1 — use the currently-cached token.
        let firstToken = try await fetchToken(forceRefresh: false)
        let (data1, http1) = try await fetch(url: url, token: firstToken)

        if http1.statusCode != 401 {
            return try decodeOrThrow(data: data1, http: http1)
        }

        // 401 → re-read the supervisor's token. If it rotated, the
        // dashboard restarted between our requests; retry with the new
        // token. If it didn't rotate, auth is genuinely broken.
        let refreshedToken = try await fetchToken(forceRefresh: true)
        if refreshedToken == firstToken {
            throw ClientError.authFailedAfterRefresh
        }
        let (data2, http2) = try await fetch(url: url, token: refreshedToken)
        if http2.statusCode == 401 {
            throw ClientError.authFailedAfterRefresh
        }
        return try decodeOrThrow(data: data2, http: http2)
    }

    private func buildURL(path: String, queryItems: [URLQueryItem]) -> URL {
        var url = baseURL.appendingPathComponent(path)
        guard !queryItems.isEmpty else { return url }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems
        if let resolved = components?.url { url = resolved }
        return url
    }

    private func fetch(url: URL, token: String) async throws -> (Data, HTTPURLResponse) {
        let request = buildRequest(url: url, token: token)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ClientError.transport(String(describing: error))
        }
        guard let http = response as? HTTPURLResponse else {
            throw ClientError.transport("Non-HTTP response")
        }
        return (data, http)
    }

    private func decodeOrThrow<T: Decodable>(data: Data, http: HTTPURLResponse) throws -> T {
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ClientError.httpStatus(code: http.statusCode, body: body)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw ClientError.decoding(String(describing: error))
        }
    }

    private func buildRequest(url: URL, token: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func fetchToken(forceRefresh: Bool) async throws -> String {
        do {
            return try await tokenProvider(forceRefresh)
        } catch {
            throw ClientError.notAuthenticated(reason: String(describing: error))
        }
    }

    private func percentEscape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }
}

/// Date parsing helper for Hermes' ISO 8601 string format. Tolerant of
/// fractional and whole-second forms, mirroring Phase 0's
/// `HermesISO8601` helper.
enum HermesDashboardDateParser {
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

    static func parse(_ s: String) -> Date? {
        if let d = withFractional.date(from: s) { return d }
        if let d = plain.date(from: s) { return d }
        return nil
    }
}
