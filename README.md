# Clipper

An iMessage app that turns social video links into actual videos. Paste an Instagram, TikTok, X, or Reddit link and the video drops straight into your message, so your friends don't have to open the link to watch it.

Everything runs on the phone: no server, no accounts, no tracking.

## Supported

| Service | Notes |
|---|---|
| Instagram | Reels, video posts, carousels (`?img_index=N` picks the slide) |
| TikTok | Videos (photo slideshows aren't supported) |
| X / Twitter | Videos and GIFs, including quoted posts and `…/video/N` |
| Reddit | v.redd.it videos with audio; link posts are followed to their host |
| Facebook | Public reels and videos |
| Streamable | All public videos |
| Anything else | Direct `.mp4`/`.mov` links and pages that advertise a video via `og:video` (e.g. Imgur) |

Short links (`vm.tiktok.com`, `t.co`, `reddit.com/…/s/…`, `instagram.com/share/…`, `fb.watch`) are resolved automatically, and links can be pasted with surrounding text.

Not yet supported: YouTube, Bluesky, Vimeo, and Threads.

## Using it

1. In Messages, tap **＋ → More → Clipper**.
2. Tap **Paste**, or tap the keyboard button to type a link.
3. The video lands in the message field. Tap send.

The Clipper app itself runs the same flow with a preview and a share sheet, which is useful for saving a video to Photos or sending it somewhere other than Messages.

## How it works

Each service has an extractor in `Packages/ClipperKit/Sources/ClipperKit/Extractors/` that reads the service's public, logged-out web data to find the video file. Clipper then streams the file to disk and hands it to Messages. Reddit serves video and audio separately, so they're merged on-device with AVFoundation (no re-encoding).

```
Clipper/            container app (SwiftUI)
ClipperMessages/    iMessage extension
Packages/ClipperKit/
  ClipperKit        extractors, networking, muxing
  ClipperUI         SwiftUI views shared by app + extension
  clipper-cli       macOS command-line harness for testing extractors
project.yml         XcodeGen spec (the .xcodeproj is generated)
```

## Building

Requires Xcode 26+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
xcodegen
open Clipper.xcodeproj
```

Run the **ClipperMessages** scheme to launch straight into the Messages simulator, or **Clipper** for the standalone app. To run on a device, set `DEVELOPMENT_TEAM` in `project.yml` and regenerate.

### Testing extractors without a simulator

```sh
# offline unit tests
swift test --package-path Packages/ClipperKit

# live checks against the real services
CLIPPER_LIVE=1 swift test --package-path Packages/ClipperKit --filter LiveTests

# download any link to the current directory
swift run --package-path Packages/ClipperKit clipper-cli "https://www.instagram.com/reel/…"
```

## Caveats

These services change their logged-out endpoints regularly, so extractors will break from time to time. The live tests are the canary, and [yt-dlp](https://github.com/yt-dlp/yt-dlp)'s extractors are the reference when something needs fixing.

Please only download and share content you have the right to share.
