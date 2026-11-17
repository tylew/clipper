import Foundation

/// A per-clip HTTP session. Cookies live only as long as the instance — several services
/// (TikTok, Instagram) hand out cookies on the page fetch that the media request then needs.
public final class HTTP: @unchecked Sendable {
    public static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    public struct Response {
        public let data: Data
        public let http: HTTPURLResponse
        public var status: Int { http.statusCode }
        public var url: URL { http.url ?? URL(string: "about:blank")! }
        public var text: String { String(decoding: data, as: UTF8.self) }
        public func json() throws -> Any { try JSONSerialization.jsonObject(with: data) }
    }

    let session: URLSession

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        session = URLSession(configuration: config)
    }

    deinit { session.invalidateAndCancel() }

    public func get(_ url: URL, headers: [String: String] = [:]) async throws -> Response {
        try await send(request(url, headers: headers))
    }

    public func post(_ url: URL, form: [(String, String)], headers: [String: String] = [:]) async throws -> Response {
        var req = request(url, headers: headers)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = form.map { "\(Self.formEncode($0))=\(Self.formEncode($1))" }.joined(separator: "&").data(using: .utf8)
        return try await send(req)
    }

    /// Follows redirects (short links like t.co, vm.tiktok.com) and returns where they land.
    public func resolve(_ url: URL) async throws -> URL {
        try await get(url).url
    }

    public func cookie(named name: String) -> String? {
        session.configuration.httpCookieStorage?.cookies?.first { $0.name == name }?.value
    }

    /// Streams a media file to disk. Throws if the server answers with a web page instead of media,
    /// which is how most CDNs signal a missing referer/cookie.
    public func download(_ url: URL, headers: [String: String] = [:], to destination: URL) async throws {
        let (tmp, response) = try await session.download(for: request(url, headers: headers))
        guard let http = response as? HTTPURLResponse else { throw ClipperError.http(0) }
        guard (200..<300).contains(http.statusCode) else { throw ClipperError.http(http.statusCode) }
        if let type = http.value(forHTTPHeaderField: "Content-Type"), type.hasPrefix("text/") {
            throw ClipperError.blocked("The video host sent back a web page instead of the video.")
        }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tmp, to: destination)
    }

    private func request(_ url: URL, headers: [String: String]) -> URLRequest {
        var req = URLRequest(url: url)
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        for (key, value) in headers { req.setValue(value, forHTTPHeaderField: key) }
        return req
    }

    private func send(_ req: URLRequest) async throws -> Response {
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw ClipperError.http(0) }
        return Response(data: data, http: http)
    }

    private static let formAllowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
    private static func formEncode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: formAllowed) ?? s
    }
}
