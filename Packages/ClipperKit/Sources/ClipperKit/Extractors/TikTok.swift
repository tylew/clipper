import Foundation

/// Scrapes the `__UNIVERSAL_DATA_FOR_REHYDRATION__` blob from the video page. With an iPhone UA
/// TikTok serves the "reflow" page (`webapp.reflow.video.detail`); desktop uses `webapp.video-detail`.
/// The play URL only works with the cookies from that page fetch plus a tiktok.com Referer.
struct TikTok: Extractor {
    let name = "TikTok"

    func matches(_ url: URL) -> Bool { url.hostMatches("tiktok.com") }

    func extract(_ url: URL, http: HTTP) async throws -> Media {
        let page = try await http.get(url)
        return try Self.media(fromPage: page.text)
    }

    static func media(fromPage html: String) throws -> Media {
        guard let raw = html.firstMatch(#"<script[^>]+id="__UNIVERSAL_DATA_FOR_REHYDRATION__"[^>]*>(.*?)</script>"#, options: .dotMatchesLineSeparators),
              let scope = JSON.at(JSON.parse(raw), "__DEFAULT_SCOPE__"),
              let detail = JSON.at(scope, "webapp.video-detail") ?? JSON.at(scope, "webapp.reflow.video.detail")
        else { throw ClipperError.blocked("TikTok didn't return the video page. Try again in a moment.") }

        if let status = JSON.at(detail, "statusCode") as? Int, status != 0 {
            throw ClipperError.noVideo("TikTok says this video is unavailable (it may be private or deleted).")
        }
        let item = JSON.at(detail, "itemInfo", "itemStruct")
        if JSON.at(item, "imagePost") != nil {
            throw ClipperError.noVideo("This TikTok is a photo slideshow, not a video.")
        }

        let video = JSON.at(item, "video")
        let bitrates = (JSON.at(video, "bitrateInfo") as? [Any] ?? [])
            .sorted { (JSON.at($0, "Bitrate") as? Int ?? 0) > (JSON.at($1, "Bitrate") as? Int ?? 0) }
            .compactMap { JSON.at($0, "PlayAddr", "UrlList", 0) as? String }
        let candidates = [JSON.at(video, "playAddr") as? String] + bitrates + [JSON.at(video, "downloadAddr") as? String]

        guard let url = candidates.compactMap({ $0 }).filter({ !$0.isEmpty }).compactMap(URL.init(string:)).first else {
            throw ClipperError.noVideo("Couldn't find a playable stream for this TikTok.")
        }
        return Media(video: url, headers: ["Referer": "https://www.tiktok.com/"], title: JSON.at(item, "desc") as? String)
    }
}
