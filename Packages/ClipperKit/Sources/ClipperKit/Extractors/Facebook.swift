import Foundation

/// Best effort: with an iPhone UA, public reels/videos expose an mp4 in `og:video` or in
/// inline JSON (`browser_native_hd_url`, `playable_url`, …).
struct Facebook: Extractor {
    let name = "Facebook"

    func matches(_ url: URL) -> Bool { url.hostMatches("facebook.com", "fb.watch", "fb.com") }

    func extract(_ url: URL, http: HTTP) async throws -> Media {
        let page = try await http.get(url)
        if page.url.path.contains("/login") {
            throw ClipperError.loginRequired("Facebook wants a login for this video — it's probably not public.")
        }
        guard let video = Self.videoURL(inPage: page.text) else {
            throw ClipperError.noVideo("Couldn't find a public video on that Facebook page.")
        }
        return Media(video: video, headers: ["Referer": "https://www.facebook.com/"], title: page.text.metaContent("og:title"))
    }

    static func videoURL(inPage html: String) -> URL? {
        let keys = ["browser_native_hd_url", "playable_url_quality_hd", "hd_src", "browser_native_sd_url", "playable_url", "sd_src"]
        for key in keys {
            if let raw = html.firstMatch(#""\#(key)":"([^"]+)""#), let url = URL(string: raw.jsonUnescaped) { return url }
        }
        for property in ["og:video:secure_url", "og:video:url", "og:video"] {
            if let content = html.metaContent(property), let url = URL(string: content) { return url }
        }
        return nil
    }
}
