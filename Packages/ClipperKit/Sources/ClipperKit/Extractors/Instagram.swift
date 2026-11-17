import Foundation

/// Logged-out web flow (mirrors yt-dlp's `InstagramIE`):
/// 1. load the homepage for an LSD token + cookies,
/// 2. hit `get_ruling_for_content` so Instagram issues a usable csrftoken,
/// 3. query the `PolarisLoggedOutDesktopWWWPostRootContentQuery` GraphQL doc by media id.
/// Falls back to scraping the post page. If Instagram breaks this, compare against
/// yt-dlp/yt_dlp/extractor/instagram.py — the doc id is the usual culprit.
struct Instagram: Extractor {
    let name = "Instagram"

    static let appID = "936619743392459"
    static let docID = "27130156389949648"
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")

    func matches(_ url: URL) -> Bool { url.hostMatches("instagram.com", "instagr.am") }

    static func shortcode(from url: URL) -> String? {
        let parts = url.parts
        guard let i = parts.firstIndex(where: { ["p", "reel", "reels", "tv"].contains($0) }), i + 1 < parts.count else { return nil }
        return parts[i + 1]
    }

    /// Shortcodes are base64url-encoded media ids; private posts append 28 extra chars.
    static func mediaID(fromShortcode code: String) -> String? {
        let trimmed = code.count > 28 ? String(code.dropLast(28)) : code
        var n: UInt64 = 0
        for c in trimmed {
            guard let digit = alphabet.firstIndex(of: c) else { return nil }
            let (shifted, o1) = n.multipliedReportingOverflow(by: 64)
            let (sum, o2) = shifted.addingReportingOverflow(UInt64(digit))
            if o1 || o2 { return nil }
            n = sum
        }
        return String(n)
    }

    func extract(_ url: URL, http: HTTP) async throws -> Media {
        guard let code = Self.shortcode(from: url), let pk = Self.mediaID(fromShortcode: code) else {
            throw ClipperError.unsupported(url)
        }
        let slide = url.queryValue("img_index").flatMap(Int.init)

        let home = try await http.get(URL(string: "https://www.instagram.com/")!)
        let lsd = home.text.firstMatch(#""LSD",\[\],\{"token":"([^"]+)""#)
            ?? home.text.firstMatch(#"id="__eqmc"[^>]*>\{[^<]*?"l":"([^"]+)""#)
            ?? ""

        let api = [
            "X-IG-App-ID": Self.appID,
            "X-ASBD-ID": "359341",
            "X-IG-WWW-Claim": "0",
            "Origin": "https://www.instagram.com",
            "Accept": "*/*",
        ]
        let ruling = try? await http.get(
            URL(string: "https://www.instagram.com/api/v1/web/get_ruling_for_content/?content_type=MEDIA&target_id=\(pk)")!,
            headers: api)

        var headers = api
        headers["X-FB-Friendly-Name"] = "PolarisLoggedOutDesktopWWWPostRootContentQuery"
        headers["X-FB-LSD"] = lsd
        headers["X-Requested-With"] = "XMLHttpRequest"
        headers["Referer"] = "https://www.instagram.com/p/\(code)/"
        if let csrf = http.cookie(named: "csrftoken") { headers["X-CSRFToken"] = csrf }

        let graphql = try? await http.post(URL(string: "https://www.instagram.com/api/graphql")!, form: [
            ("lsd", lsd),
            ("fb_api_caller_class", "RelayModern"),
            ("fb_api_req_friendly_name", "PolarisLoggedOutDesktopWWWPostRootContentQuery"),
            ("server_timestamps", "true"),
            ("variables", #"{"media_id":"\#(pk)"}"#),
            ("doc_id", Self.docID),
        ], headers: headers)

        let product = JSON.at(try? graphql?.json(), "data", "xig_polaris_media", "if_not_gated_logged_out")
        if let product {
            guard let video = Self.bestVideo(in: product, slide: slide) else {
                throw ClipperError.noVideo("This Instagram post is a photo, not a video.")
            }
            return Media(video: video, headers: ["Referer": "https://www.instagram.com/"],
                         title: JSON.at(product, "caption", "text") as? String)
        }

        // Fallback: the post page sometimes embeds the same data for logged-out viewers.
        let page = try await http.get(URL(string: "https://www.instagram.com/p/\(code)/")!)
        if page.url.path.hasPrefix("/accounts/login") {
            throw ClipperError.loginRequired("Instagram wants a login for this post. It may be private, or Instagram is rate-limiting — try again in a bit.")
        }
        if let raw = page.text.firstMatch(#""video_versions":\[\{[^\]]*?"url":"([^"]+)""#), let video = URL(string: raw.jsonUnescaped) {
            return Media(video: video, headers: ["Referer": "https://www.instagram.com/"])
        }

        let rulingJSON = try? ruling?.json()
        let reason = [JSON.at(rulingJSON, "title"), JSON.at(rulingJSON, "description")]
            .compactMap { $0 as? String }.filter { !$0.isEmpty }.joined(separator: ": ")
        throw ClipperError.loginRequired(reason.isEmpty
            ? "Instagram didn't return this post. It may be private or age-restricted."
            : "Instagram: \(reason)")
    }

    /// Highest-resolution video in the post; for carousels, the requested slide first, then any video slide.
    static func bestVideo(in product: Any, slide: Int?) -> URL? {
        var items = (JSON.at(product, "carousel_media") as? [Any]) ?? [product]
        if let slide, items.indices.contains(slide - 1) { items.insert(items[slide - 1], at: 0) }
        for item in items {
            guard let versions = JSON.at(item, "video_versions") as? [[String: Any]] else { continue }
            let best = versions.max { area($0) < area($1) }
            if let string = best?["url"] as? String, let url = URL(string: string) { return url }
        }
        return nil
    }

    private static func area(_ v: [String: Any]) -> Int {
        ((v["width"] as? Int) ?? 0) * ((v["height"] as? Int) ?? 0)
    }
}
