# Clipper Shortcut

A standalone Shortcut version of Clipper: no app install, shareable by link. Share a video link to it (or copy one and run it) and it opens the share sheet with the video, ready for Messages or Save Video.

`build_shortcut.py` generates the shortcut, so treat it as the source of truth and don't hand-edit the `.shortcut` file.

## Status: untested

The generator runs and produces a ~120-action shortcut, but it hasn't been signed, imported, or run yet. `shortcuts sign` needs a Mac signed into iCloud.

## Signing + testing (macOS, signed into iCloud)

```sh
python3 Shortcut/build_shortcut.py           # writes + signs Shortcut/Clipper.shortcut
open Shortcut/Clipper.shortcut               # click "Add Shortcut"

# run against real links (it reads the clipboard when given no input)
for url in \
  https://www.instagram.com/reel/CDUMkliABpa/ \
  https://www.tiktok.com/@scout2015/video/6718335390845095173 \
  https://x.com/i/status/1790637656616943991 \
  https://www.reddit.com/r/videos/comments/6rrwyj/that_small_heart_attack/ \
  https://www.facebook.com/reel/1195289147628387 \
  https://streamable.com/dnd1; do
  echo "$url" | pbcopy && shortcuts run Clipper
done
```

The last step opens a share sheet; choosing Save confirms the file is a real video.

Things to verify first:

- **TikTok:** the play URL only works with the cookies from the page request. This assumes Shortcuts' "Get Contents of URL" keeps cookies between actions. If TikTok downloads come back tiny or 403, that assumption is wrong.
- **Get Group on empty matches:** every capture is guarded with an If, but double-check that a missing match doesn't stop the run.
- **Condition/parameter keys:** the action plist was written by hand (`WFCondition` codes, `text.match` params, etc.). If something renders as a blank action after import, compare it against a shortcut exported from the Shortcuts app.

## Known limits vs. the app

- Reddit videos are silent, because Shortcuts can't merge Reddit's separate audio stream.
- X uses `token=a`; the syndication endpoint doesn't currently validate it.
- No carousel slide selection on Instagram (first video wins).

## Sharing

Once it's tested, either attach the signed `Clipper.shortcut` to a GitHub release (opening it on iPhone imports it), or share it from the Shortcuts app with **Share → Copy iCloud Link**.
