import XCTest
@testable import ClipperKit

final class ParsingTests: XCTestCase {
    func testFindsLinkInSharedText() {
        let url = Clipper.firstURL(in: "lol look https://www.instagram.com/reel/Chunk8-jurw/?igsh=abc123 so good")
        XCTAssertEqual(url?.host, "www.instagram.com")
        XCTAssertNil(Clipper.firstURL(in: "no link here"))
    }

    func testRoutesToExtractor() {
        let cases = [
            "https://www.instagram.com/reel/Chunk8-jurw/": "Instagram",
            "https://www.tiktok.com/@scout2015/video/6718335390845095173": "TikTok",
            "https://x.com/user/status/1790637656616943991": "X",
            "https://mobile.twitter.com/user/status/1": "X",
            "https://www.reddit.com/r/videos/comments/6rrwyj/x/": "Reddit",
            "https://v.redd.it/zv89llsvexdz": "Reddit",
            "https://www.facebook.com/reel/1195289147628387": "Facebook",
            "https://streamable.com/moo": "Streamable",
            "https://example.com/video.mp4": "Link",
        ]
        for (string, name) in cases {
            XCTAssertEqual(Clipper.extractor(for: URL(string: string)!).name, name, string)
        }
    }

    func testShortLinks() {
        XCTAssertTrue(Clipper.isShortLink(URL(string: "https://vm.tiktok.com/ZMabc/")!))
        XCTAssertTrue(Clipper.isShortLink(URL(string: "https://www.tiktok.com/t/ZTabc/")!))
        XCTAssertTrue(Clipper.isShortLink(URL(string: "https://t.co/abc")!))
        XCTAssertTrue(Clipper.isShortLink(URL(string: "https://www.reddit.com/r/videos/s/AbC123")!))
        XCTAssertFalse(Clipper.isShortLink(URL(string: "https://v.redd.it/zv89llsvexdz")!))
        XCTAssertFalse(Clipper.isShortLink(URL(string: "https://www.tiktok.com/@a/video/1")!))
    }

    func testInstagramIDs() {
        XCTAssertEqual(Instagram.shortcode(from: URL(string: "https://www.instagram.com/someone/reel/Chunk8-jurw/?x=1")!), "Chunk8-jurw")
        XCTAssertEqual(Instagram.shortcode(from: URL(string: "https://instagram.com/p/BQ0eAlwhDrw")!), "BQ0eAlwhDrw")
        XCTAssertEqual(Instagram.mediaID(fromShortcode: "Chunk8-jurw"), "2913440072144448240")
    }

    func testInstagramCarouselPicksRequestedSlide() {
        let product: [String: Any] = ["carousel_media": [
            ["image_versions2": [:]],
            ["video_versions": [["url": "https://a/low.mp4", "width": 360, "height": 640], ["url": "https://a/hi.mp4", "width": 720, "height": 1280]]],
            ["video_versions": [["url": "https://a/third.mp4", "width": 720, "height": 1280]]],
        ]]
        XCTAssertEqual(Instagram.bestVideo(in: product, slide: nil)?.absoluteString, "https://a/hi.mp4")
        XCTAssertEqual(Instagram.bestVideo(in: product, slide: 3)?.absoluteString, "https://a/third.mp4")
    }

    func testTwitterIDs() {
        let url = URL(string: "https://x.com/someone/status/1790637656616943991/video/2")!
        XCTAssertEqual(Twitter.tweetID(from: url), "1790637656616943991")
        XCTAssertEqual(Twitter.videoIndex(from: url), 2)
        XCTAssertFalse(Twitter.token(for: "1790637656616943991").contains("0"))
    }

    func testTikTokPageParsing() throws {
        let html = #"<script id="__UNIVERSAL_DATA_FOR_REHYDRATION__" type="application/json">{"__DEFAULT_SCOPE__":{"webapp.reflow.video.detail":{"statusCode":0,"itemInfo":{"itemStruct":{"desc":"hi","video":{"playAddr":"https:\/\/v16.tiktok.com\/video.mp4?a=1&b=2"}}}}}}</script>"#
        let media = try TikTok.media(fromPage: html)
        XCTAssertEqual(media.video.absoluteString, "https://v16.tiktok.com/video.mp4?a=1&b=2")
        XCTAssertEqual(media.title, "hi")

        let gone = #"<script id="__UNIVERSAL_DATA_FOR_REHYDRATION__" type="application/json">{"__DEFAULT_SCOPE__":{"webapp.video-detail":{"statusCode":10204}}}</script>"#
        XCTAssertThrowsError(try TikTok.media(fromPage: gone))
    }

    func testDASHManifest() {
        let mpd = """
        <MPD xmlns="urn:mpeg:dash:schema:mpd:2011"><Period>
        <AdaptationSet contentType="video"><Representation height="480" bandwidth="2400000" mimeType="video/mp4"><BaseURL>DASH_2_4_M</BaseURL></Representation>
        <Representation height="240" bandwidth="600000" mimeType="video/mp4"><BaseURL>DASH_600_K</BaseURL></Representation></AdaptationSet>
        <AdaptationSet mimeType="audio/mp4"><Representation bandwidth="128000"><BaseURL>audio</BaseURL></Representation></AdaptationSet>
        </Period></MPD>
        """
        let reps = MPD.representations(in: Data(mpd.utf8))
        XCTAssertEqual(reps.filter(\.isVideo).map(\.baseURL), ["DASH_2_4_M", "DASH_600_K"])
        XCTAssertEqual(reps.filter(\.isAudio).map(\.baseURL), ["audio"])
    }

    func testRedditChallenge() {
        let html = #"<script>(async e=>e+e)("abc123")</script><form hidden method="GET" action="/r/v/comments/x/y/"><input type="hidden" name="solution" /><input type="hidden" name="js_challenge" value="1"/><input type="hidden" name="jsc_token" value="tok"/></form>"#
        let url = Reddit.challengeURL(inPage: html, base: URL(string: "https://www.reddit.com/r/v/comments/x/y/")!)
        let items = URLComponents(url: url!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertTrue(url!.absoluteString.hasPrefix("https://www.reddit.com/r/v/comments/x/y/?"))
        XCTAssertEqual(items.first { $0.name == "solution" }?.value, "abc123abc123")
        XCTAssertEqual(items.first { $0.name == "jsc_token" }?.value, "tok")
        XCTAssertNil(Reddit.challengeURL(inPage: "<html>normal page</html>", base: url!))
    }

    func testMetaAndGenericParsing() {
        let html = #"<meta content="https://cdn.example.com/v.mp4?x=1&amp;y=2" property="og:video"><meta property="og:title" content="Hi">"#
        XCTAssertEqual(html.metaContent("og:video"), "https://cdn.example.com/v.mp4?x=1&y=2")
        XCTAssertNil(html.metaContent("og:video:url"))
        XCTAssertEqual(Generic.videoURL(inPage: #"<video src="/media/clip.mp4">"#, base: URL(string: "https://site.com/post/1")!)?.absoluteString,
                       "https://site.com/media/clip.mp4")
    }
}

/// Hits the real services. Run with `CLIPPER_LIVE=1 swift test --filter LiveTests`.
/// These are the canaries for "Instagram changed something again".
final class LiveTests: XCTestCase {
    static let samples = [
        "https://www.instagram.com/reel/Chunk8-jurw/",
        "https://www.tiktok.com/@scout2015/video/6718335390845095173",
        "https://x.com/i/status/1790637656616943991",
        "https://www.reddit.com/r/videos/comments/6rrwyj/that_small_heart_attack/",
        "https://www.facebook.com/reel/1195289147628387",
        "https://streamable.com/dnd1",
        "https://www.instagram.com/reel/CDUMkliABpa/",
    ]

    func testSamplesDownload() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CLIPPER_LIVE"] != nil, "set CLIPPER_LIVE=1 to hit real services")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("clipper-live-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let clipper = Clipper(outputDirectory: dir)
        for sample in Self.samples {
            do {
                let clip = try await clipper.clip(sample)
                let size = try clip.fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                XCTAssertGreaterThan(size, 50_000, sample)
            } catch {
                XCTFail("\(sample): \(error.localizedDescription)")
            }
        }
    }
}
