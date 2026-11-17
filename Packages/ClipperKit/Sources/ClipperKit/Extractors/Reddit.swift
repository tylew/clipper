import Foundation

/// Reddit's JSON API blocks anonymous clients, but the post page still names the v.redd.it id.
/// v.redd.it serves video and audio as separate DASH files, listed in `DASHPlaylist.mpd`;
/// `Clipper` downloads both and muxes them.
struct Reddit: Extractor {
    let name = "Reddit"

    /// Cap so clips stay a reasonable size for iMessage.
    static let maxHeight = 1080

    func matches(_ url: URL) -> Bool { url.hostMatches("reddit.com", "redd.it") }

    func extract(_ url: URL, http: HTTP) async throws -> Media {
        let id: String
        if url.hostMatches("v.redd.it"), let first = url.parts.first {
            id = first
        } else {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            components.host = "www.reddit.com"
            var page = try await http.get(components.url ?? url)
            if let challenge = Self.challengeURL(inPage: page.text, base: page.url) {
                page = try await http.get(challenge)
            }
            if let found = Self.videoID(inPage: page.text) {
                id = found
            } else if let external = Self.externalLink(inPage: page.text) {
                throw FollowLink(url: external)
            } else {
                throw ClipperError.noVideo("This Reddit post doesn't have a video.")
            }
        }

        let base = URL(string: "https://v.redd.it/\(id)/")!
        let manifest = try await http.get(base.appendingPathComponent("DASHPlaylist.mpd"))
        guard manifest.status == 200 else { throw ClipperError.noVideo("Reddit's video manifest is unavailable.") }
        let reps = MPD.representations(in: manifest.data)

        let videos = reps.filter(\.isVideo)
        let video = videos.filter { $0.height <= Self.maxHeight }.max { ($0.height, $0.bandwidth) < ($1.height, $1.bandwidth) }
            ?? videos.min { $0.height < $1.height }
        guard let video, let videoURL = URL(string: video.baseURL, relativeTo: base) else {
            throw ClipperError.noVideo("Reddit's manifest has no video stream.")
        }
        let audio = reps.filter(\.isAudio).max { $0.bandwidth < $1.bandwidth }
        return Media(video: videoURL.absoluteURL, audio: audio.flatMap { URL(string: $0.baseURL, relativeTo: base)?.absoluteURL })
    }

    static func videoID(inPage html: String) -> String? {
        html.firstMatch(#"content-href="https://v\.redd\.it/([A-Za-z0-9]+)"#)
            ?? html.firstMatch(#"https://v\.redd\.it/([A-Za-z0-9]+)"#)
    }

    /// Fresh sessions get a JS interstitial: a hidden GET form whose `solution` field is filled by
    /// `(async e=>e+e)("<token>")` — i.e. the token doubled. Builds the URL that form would submit.
    /// Returns nil if the page isn't the challenge or the puzzle has changed shape.
    static func challengeURL(inPage html: String, base: URL) -> URL? {
        guard html.contains(#"name="js_challenge""#),
              let token = html.firstMatch(#"\(async\s*\(?(\w+)\)?\s*=>\s*\1\s*\+\s*\1\)\("([^"]+)"\)"#, group: 2),
              let action = html.firstMatch(#"<form[^>]*action="([^"]*)""#)?.htmlUnescaped,
              var components = URLComponents(url: URL(string: action, relativeTo: base)?.absoluteURL ?? base, resolvingAgainstBaseURL: false)
        else { return nil }

        var items = [URLQueryItem(name: "solution", value: token + token)]
        let inputs = try? NSRegularExpression(pattern: #"<input[^>]+name="([^"]+)"[^>]+value="([^"]*)""#)
        for match in inputs?.matches(in: html, range: NSRange(html.startIndex..., in: html)) ?? [] {
            guard let name = Range(match.range(at: 1), in: html), let value = Range(match.range(at: 2), in: html) else { continue }
            items.append(URLQueryItem(name: String(html[name]), value: String(html[value]).htmlUnescaped))
        }
        components.queryItems = items
        return components.url
    }

    /// Link posts that point at another video host (Streamable, Imgur, X, …).
    static func externalLink(inPage html: String) -> URL? {
        guard let href = html.firstMatch(#"<shreddit-post[^>]+content-href="(https?://[^"]+)""#)?.htmlUnescaped,
              let url = URL(string: href), !url.hostMatches("reddit.com", "redd.it", "redditmedia.com")
        else { return nil }
        return url
    }
}

/// Minimal DASH manifest reader: flattens Representations with their BaseURL.
enum MPD {
    struct Representation {
        var mimeType: String
        var height: Int
        var bandwidth: Int
        var baseURL: String
        var isVideo: Bool { mimeType.hasPrefix("video") }
        var isAudio: Bool { mimeType.hasPrefix("audio") }
    }

    static func representations(in data: Data) -> [Representation] {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.reps
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var reps: [Representation] = []
        private var setMime = ""
        private var current: Representation?
        private var text = ""
        private var inBaseURL = false

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            switch name {
            case "AdaptationSet":
                setMime = attributes["mimeType"] ?? attributes["contentType"] ?? ""
            case "Representation":
                current = Representation(
                    mimeType: attributes["mimeType"] ?? setMime,
                    height: Int(attributes["height"] ?? "") ?? 0,
                    bandwidth: Int(attributes["bandwidth"] ?? "") ?? 0,
                    baseURL: "")
            case "BaseURL":
                text = ""
                inBaseURL = true
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inBaseURL { text += string }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            switch name {
            case "BaseURL":
                current?.baseURL = text.trimmingCharacters(in: .whitespacesAndNewlines)
                inBaseURL = false
            case "Representation":
                if let rep = current, !rep.baseURL.isEmpty { reps.append(rep) }
                current = nil
            default:
                break
            }
        }
    }
}
