import Foundation

/// Talks to a local Hermes daemon over HTTP. The daemon endpoint is
/// configurable; if it is unreachable the client throws
/// `HermesAPIError.notReachable` so the UI can surface offline state.
public final class URLSessionHermesAPIClient: HermesAPIClient, @unchecked Sendable {
    public let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder

    public init(baseURL: URL = URL(string: "http://127.0.0.1:8765")!,
                session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
        self.decoder = JSONDecoder()
    }

    public func health() async throws -> HermesHealth {
        try await get("/health")
    }

    public func version() async throws -> HermesVersion {
        try await get("/version")
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw HermesAPIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 3
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where Self.offlineCodes.contains(error.code) {
            throw HermesAPIError.notReachable
        } catch {
            throw HermesAPIError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw HermesAPIError.transport("Non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw HermesAPIError.http(status: http.statusCode,
                                      body: String(data: data, encoding: .utf8))
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw HermesAPIError.decoding(error.localizedDescription)
        }
    }

    private static let offlineCodes: Set<URLError.Code> = [
        .cannotConnectToHost,
        .networkConnectionLost,
        .notConnectedToInternet,
        .timedOut,
        .cannotFindHost,
        .dnsLookupFailed
    ]
}
