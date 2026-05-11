import Foundation

/// Pulls the ephemeral session token from a running Hermes dashboard's
/// SPA HTML at `GET /`.
///
/// Per Phase 0.5 REALITY.md and `hermes_cli/web_server.py:74`, the dashboard
/// generates a fresh `secrets.token_urlsafe(32)` on every process start.
/// The token is embedded in the SPA HTML as:
///
///     <script>window.__HERMES_SESSION_TOKEN__="<token>";...</script>
///
/// It is **not** configurable, **not** persisted, and **not** discoverable
/// by any other means — Diak has to scrape it from the HTML. After a
/// dashboard restart the new HTML carries a new token; the old one returns
/// 401 from `/api/*`. So the supervisor calls `scrapeToken` every start.
///
/// `fetcher` is closure-injectable so unit tests can supply canned HTML
/// without hitting the network.
public struct DashboardTokenScraper: Sendable {

    /// Reasons `scrapeToken` may give up.
    public enum FailureReason: Sendable, Equatable {
        /// Deadline elapsed without a token. Inner `lastObserved` captures
        /// whatever the last fetch attempt produced for diagnostics.
        case timedOut
        /// The dashboard responded with HTML but the token marker was not
        /// found in it. Could indicate Hermes version drift.
        case tokenNotFound
        /// The dashboard responded but the body could not be decoded as
        /// UTF-8.
        case nonUTF8Body
        /// The fetch itself failed (network, DNS, refused, etc.). The
        /// inner string is a human-readable description for logs.
        case fetchFailed(String)
    }

    /// Boxed error so tests can pattern-match cleanly.
    public struct Failure: Error, Equatable {
        public let reason: FailureReason
        public init(reason: FailureReason) {
            self.reason = reason
        }
    }

    /// Closure that fetches the HTML body at `url`. Returns the response
    /// data and the HTTP status code. The default implementation uses
    /// `URLSession.shared.data(from:)`.
    public typealias HTMLFetcher = @Sendable (URL) async throws -> (Data, Int)

    /// How long to wait between retry attempts when a fetch fails or the
    /// token isn't yet in the HTML.
    public let retryInterval: TimeInterval

    private let fetcher: HTMLFetcher

    public init(
        fetcher: @escaping HTMLFetcher = DashboardTokenScraper.defaultFetcher,
        retryInterval: TimeInterval = 0.25
    ) {
        self.fetcher = fetcher
        self.retryInterval = retryInterval
    }

    /// Default production fetcher. Goes through `URLSession.shared`.
    public static let defaultFetcher: HTMLFetcher = { url in
        var request = URLRequest(url: url)
        // Short per-attempt timeout. The caller's overall deadline drives
        // total wait time.
        request.timeoutInterval = 2
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        return (data, status)
    }

    /// Repeatedly fetches `baseURL` until either the dashboard returns 200
    /// with an HTML body containing `__HERMES_SESSION_TOKEN__`, or the
    /// caller's `timeout` elapses. Returns the token on success.
    public func scrapeToken(from baseURL: URL, timeout: TimeInterval) async throws -> String {
        let deadline = Date().addingTimeInterval(timeout)
        var lastFailure: FailureReason = .timedOut

        while Date() < deadline {
            do {
                let (data, status) = try await fetcher(baseURL)
                if status != 200 {
                    lastFailure = .fetchFailed("HTTP \(status)")
                } else if let html = String(data: data, encoding: .utf8) {
                    if let token = Self.extractToken(from: html) {
                        return token
                    }
                    lastFailure = .tokenNotFound
                } else {
                    lastFailure = .nonUTF8Body
                }
            } catch {
                lastFailure = .fetchFailed(String(describing: error))
            }

            try? await Self.sleep(seconds: retryInterval)
        }

        throw Failure(reason: lastFailure)
    }

    /// Pulls the token value out of a SPA index.html. Public + static so
    /// unit tests can exercise the regex independently of any I/O.
    public static func extractToken(from html: String) -> String? {
        // Hermes' server emits the assignment as:
        //   window.__HERMES_SESSION_TOKEN__="<urlsafe-base64>"
        // The token alphabet is base64url (RFC 4648 §5): A-Z a-z 0-9 - _.
        // Allow optional whitespace around `=` to be forgiving of future
        // Hermes builds that pretty-print the SPA.
        let pattern = #"__HERMES_SESSION_TOKEN__\s*=\s*"([A-Za-z0-9_-]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(html.startIndex..., in: html)
        guard
            let match = regex.firstMatch(in: html, range: range),
            match.numberOfRanges >= 2,
            let tokenRange = Range(match.range(at: 1), in: html)
        else {
            return nil
        }
        return String(html[tokenRange])
    }

    private static func sleep(seconds: TimeInterval) async throws {
        let nanos = UInt64(max(0, seconds) * 1_000_000_000)
        try await Task.sleep(nanoseconds: nanos)
    }
}
