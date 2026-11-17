import Foundation

/// Uses the public embed ("syndication") endpoint, which needs no auth and returns mp4 variants.
struct Twitter: Extractor {
    let name = "X"

    func matches(_ url: URL) -> Bool {
        url.hostMatches("twitter.com", "x.com", "fxtwitter.com", "vxtwitter.com", "fixupx.com", "fixvx.com")
    }

    static func tweetID(from url: URL) -> String? {
        let parts = url.parts
        guard let i = parts.firstIndex(where: { $0 == "status" || $0 == "statuses" }), i + 1 < parts.count,
              parts[i + 1].allSatisfy(\.isNumber) else { return nil }
        return parts[i + 1]
    }

    /// `.../video/2` selects the second video in a multi-video post.
    static func videoIndex(from url: URL) -> Int? {
        let parts = url.parts
        guard let i = parts.firstIndex(of: "video"), i + 1 < parts.count else { return nil }
        return Int(parts[i + 1])
    }

    /// Port of the embed widget's `((id / 1e15) * Math.PI).toString(36).replace(/(0+|\.)/g, '')`.
    /// The endpoint currently doesn't validate it, so an approximation of JS's float formatting is fine.
    static func token(for id: String) -> String {
        guard let n = Double(id) else { return "0" }
        let value = n / 1e15 * Double.pi
        let digits = Array("0123456789abcdefghijklmnopqrstuvwxyz")
        var whole = floor(value), fraction = value - whole
        var integer = ""
        repeat {
            integer.insert(digits[Int(whole.truncatingRemainder(dividingBy: 36))], at: integer.startIndex)
            whole = floor(whole / 36)
        } while whole > 0
        var decimals = ""
        for _ in 0..<10 where fraction > 0 {
            fraction *= 36
            let d = Int(fraction)
            decimals.append(digits[d])
            fraction -= Double(d)
        }
        return (integer + decimals).replacingOccurrences(of: "0", with: "")
    }

    func extract(_ url: URL, http: HTTP) async throws -> Media {
        guard let id = Self.tweetID(from: url) else { throw ClipperError.unsupported(url) }
        let response = try await http.get(URL(string: "https://cdn.syndication.twimg.com/tweet-result?id=\(id)&lang=en&token=\(Self.token(for: id))")!)
        guard response.status == 200, let tweet = try? response.json() as? [String: Any], !tweet.isEmpty else {
            throw ClipperError.noVideo("X didn't return this post. It may be deleted, private, or age-restricted.")
        }
        if tweet["__typename"] as? String == "TweetTombstone" {
            throw ClipperError.loginRequired("X hides this post from logged-out viewers (often age-restricted).")
        }

        let details = (tweet["mediaDetails"] as? [Any] ?? []) + (JSON.at(tweet, "quoted_tweet", "mediaDetails") as? [Any] ?? [])
        let videos = details.filter { ["video", "animated_gif"].contains(JSON.at($0, "type") as? String) }
        let index = (Self.videoIndex(from: url) ?? 1) - 1
        guard let chosen = videos.indices.contains(index) ? videos[index] : videos.first else {
            throw ClipperError.noVideo("This X post doesn't have a video.")
        }

        let best = (JSON.at(chosen, "video_info", "variants") as? [Any] ?? [])
            .filter { JSON.at($0, "content_type") as? String == "video/mp4" }
            .max { (JSON.at($0, "bitrate") as? Int ?? 0) < (JSON.at($1, "bitrate") as? Int ?? 0) }
        guard let string = JSON.at(best, "url") as? String, let video = URL(string: string) else {
            throw ClipperError.noVideo("Couldn't find an mp4 for this X video.")
        }
        return Media(video: video, title: tweet["text"] as? String)
    }
}
