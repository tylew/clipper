import Foundation

/// Fallback for everything else: direct video links, or pages that advertise an mp4 via
/// Open Graph / Twitter Card tags or a `<video>` element (Imgur, many news sites, …).
struct Generic: Extractor {
    let name = "Link"

    private static let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]

    func matches(_ url: URL) -> Bool { true }

    func extract(_ url: URL, http: HTTP) async throws -> Media {
        if Self.videoExtensions.contains(url.pathExtension.lowercased()) { return Media(video: url) }

        let page = try await http.get(url)
        if let type = page.http.value(forHTTPHeaderField: "Content-Type"), type.hasPrefix("video/") {
            return Media(video: page.url)
        }
        guard let video = Self.videoURL(inPage: page.text, base: page.url) else { throw ClipperError.unsupported(url) }
        return Media(video: video, headers: ["Referer": page.url.absoluteString], title: page.text.metaContent("og:title"))
    }

    static func videoURL(inPage html: String, base: URL) -> URL? {
        let candidates = ["og:video:secure_url", "og:video:url", "og:video", "twitter:player:stream"].compactMap(html.metaContent)
            + [html.firstMatch(#"<(?:video|source)[^>]+src=["']([^"']+\.(?:mp4|mov|m4v)[^"']*)["']"#, options: .caseInsensitive)?.htmlUnescaped].compactMap { $0 }
        return candidates
            .compactMap { URL(string: $0, relativeTo: base)?.absoluteURL }
            .first { Self.videoExtensions.contains($0.pathExtension.lowercased()) || !$0.absoluteString.contains(".m3u8") }
    }
}
