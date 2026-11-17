#!/usr/bin/env python3
"""Generates Clipper.shortcut — a standalone iOS/macOS Shortcut version of Clipper.

The Shortcut mirrors the Swift extractors in Packages/ClipperKit, but Shortcuts can only do
plain HTTP + regex, so each service uses the simplest variant of its flow:

  Instagram   post page -> media id + LSD token -> logged-out GraphQL query -> video_versions url
  TikTok      video page -> playAddr (download relies on Shortcuts keeping the page's cookies)
  X           syndication endpoint -> last (highest-bitrate) mp4 variant
  Reddit      post page (solving the JS interstitial) -> v.redd.it id -> best DASH video (NO AUDIO:
              Shortcuts can't mux the separate audio stream)
  Facebook    page -> playable/browser_native url or og:video
  Streamable  API -> files.mp4.url
  anything    direct .mp4/.mov link, or og:video on the page

Usage:
  python3 Shortcut/build_shortcut.py          # writes + signs Shortcut/Clipper.shortcut
  python3 Shortcut/build_shortcut.py --unsigned
"""

import argparse
import plistlib
import subprocess
import uuid
from pathlib import Path

HERE = Path(__file__).resolve().parent
OBJ = "￼"  # placeholder char for inline variables in Shortcuts text fields
UA = ("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 "
      "(KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1")

IG_APP_ID = "936619743392459"
IG_DOC_ID = "27130156389949648"  # PolarisLoggedOutDesktopWWWPostRootContentQuery; keep in sync with Instagram.swift

# Shortcuts "If" condition codes
CONTAINS, HAS_VALUE, NO_VALUE = 99, 100, 101


# ---------------------------------------------------------------------------
# References to values: action outputs, named variables, or the shortcut input

class Out:
    def __init__(self, uuid_, name):
        self.uuid, self.name = uuid_, name

    def attachment(self):
        return {"OutputUUID": self.uuid, "Type": "ActionOutput", "OutputName": self.name}


class Var:
    def __init__(self, name):
        self.name = name

    def attachment(self):
        return {"Type": "Variable", "VariableName": self.name}


class Input:
    def attachment(self):
        return {"Type": "ExtensionInput"}


def token(ref):
    return {"Value": ref.attachment(), "WFSerializationType": "WFTextTokenAttachment"}


def text(*parts):
    """A Shortcuts text field mixing literal strings and variables."""
    string, attachments = "", {}
    for part in parts:
        if isinstance(part, str):
            string += part
        else:
            # Ranges are UTF-16 offsets; everything here is BMP so len() matches.
            attachments[f"{{{len(string)}, 1}}"] = part.attachment()
            string += OBJ
    return {"Value": {"string": string, "attachmentsByRange": attachments}, "WFSerializationType": "WFTextTokenString"}


def dictionary(pairs):
    items = [{"WFItemType": 0, "WFKey": text(k), "WFValue": text(*(v if isinstance(v, tuple) else (v,)))}
             for k, v in pairs]
    return {"Value": {"WFDictionaryFieldValueItems": items}, "WFSerializationType": "WFDictionaryFieldValue"}


# ---------------------------------------------------------------------------
# Action builders

class Shortcut:
    def __init__(self):
        self.actions = []

    def add(self, ident, params, output=None):
        uid = str(uuid.uuid4()).upper()
        self.actions.append({
            "WFWorkflowActionIdentifier": f"is.workflow.actions.{ident}",
            "WFWorkflowActionParameters": {**params, "UUID": uid},
        })
        return Out(uid, output) if output else None

    # values
    def set_var(self, name, *parts):
        value = self.add("gettext", {"WFTextActionText": text(*parts)}, "Text")
        self.add("setvariable", {"WFVariableName": name, "WFInput": token(value)})
        return Var(name)

    def links_in(self, ref):
        return self.add("detect.link", {"WFInput": token(ref)}, "URLs")

    def first(self, ref):
        return self.add("getitemfromlist", {"WFInput": token(ref), "WFItemSpecifier": "First Item"}, "Item from List")

    def last(self, ref):
        return self.add("getitemfromlist", {"WFInput": token(ref), "WFItemSpecifier": "Last Item"}, "Item from List")

    def replace(self, ref, find, replacement, regex=False):
        return self.add("text.replace", {
            "WFInput": text(ref), "WFReplaceTextFind": find, "WFReplaceTextReplace": replacement,
            "WFReplaceTextRegularExpression": regex, "WFReplaceTextCaseSensitive": True,
        }, "Updated Text")

    def fetch(self, *url_parts, method="GET", headers=(), form=None):
        params = {
            "WFURL": text(*url_parts), "WFHTTPMethod": method, "ShowHeaders": True,
            "WFHTTPHeaders": dictionary([("User-Agent", UA), *headers]),
        }
        if form is not None:
            params.update({"WFHTTPBodyType": "Form", "WFFormValues": dictionary(form)})
        return self.add("downloadurl", params, "Contents of URL")

    def capture(self, pattern, source, var, group=1, pick_last=False):
        """Sets `var` to a regex capture group from `source`, leaving it empty when nothing matches."""
        matches = self.add("text.match", {
            "WFMatchTextPattern": pattern, "text": text(source), "WFMatchTextCaseSensitive": False,
        }, "Matches")
        with self.when(matches, HAS_VALUE):
            groups = self.add("text.match.getgroup", {
                "matches": token(matches), "WFGetGroupType": "Group At Index", "WFGroupIndex": group,
            }, "Group")
            chosen = self.last(groups) if pick_last else self.first(groups)
            self.set_var(var, chosen)
        return Var(var)

    # control flow
    def when(self, ref, condition, value=None, otherwise=None):
        return _If(self, ref, condition, value, otherwise)

    def alert(self, title, message):
        self.add("alert", {"WFAlertActionTitle": title, "WFAlertActionMessage": message,
                           "WFAlertActionCancelButtonShown": False})


class _If:
    """`with sc.when(x, HAS_VALUE): ...` — pass `otherwise=callable` for an Otherwise branch."""

    def __init__(self, sc, ref, condition, value, otherwise):
        self.sc, self.otherwise = sc, otherwise
        self.group = str(uuid.uuid4()).upper()
        params = {"GroupingIdentifier": self.group, "WFControlFlowMode": 0, "WFCondition": condition,
                  "WFInput": {"Type": "Variable", "Variable": token(ref)}}
        if value is not None:
            params["WFConditionalActionString"] = value
        sc.add("conditional", params)

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        if self.otherwise:
            self.sc.add("conditional", {"GroupingIdentifier": self.group, "WFControlFlowMode": 1})
            self.otherwise()
        self.sc.add("conditional", {"GroupingIdentifier": self.group, "WFControlFlowMode": 2})
        return False


# ---------------------------------------------------------------------------
# The shortcut

def build():
    sc = Shortcut()
    media, referer = Var("MediaURL"), Var("Referer")

    # Input: share-sheet URL/text, or the clipboard when run directly.
    links = sc.links_in(Input())
    with sc.when(links, NO_VALUE):
        sc.alert("Clipper", "Copy a video link first, or share one to Clipper from another app.")
        sc.add("exit", {})
    link = sc.set_var("Link", sc.first(links))

    # Each service branch sets MediaURL (+ Referer) when it finds something.
    def service(pattern):
        found = sc.add("text.match", {"WFMatchTextPattern": pattern, "text": text(link),
                                      "WFMatchTextCaseSensitive": False}, "Matches")
        return sc.when(found, HAS_VALUE)

    with service(r"^https?://([^/]+\.)?(instagram\.com|instagr\.am)/"):
        page = sc.fetch(link)
        pk = sc.capture(r"instagram://media\?id=(\d+)", page, "IGMediaID")
        lsd = sc.capture(r'"LSD",\[\],\{"token":"([^"]+)"', page, "IGLSD")
        with sc.when(pk, HAS_VALUE):
            response = sc.fetch(
                "https://www.instagram.com/api/graphql", method="POST",
                headers=[("X-IG-App-ID", IG_APP_ID), ("X-FB-LSD", (lsd,)), ("Origin", "https://www.instagram.com")],
                form=[("lsd", (lsd,)), ("variables", ('{"media_id":"', pk, '"}')), ("doc_id", IG_DOC_ID)])
            sc.capture(r'"video_versions":\[\{[^\]]*?"url":"([^"]+)"', response, "MediaURL")
            sc.set_var("Referer", "https://www.instagram.com/")

    with service(r"^https?://([^/]+\.)?tiktok\.com/"):
        page = sc.fetch(link)
        sc.capture(r'"playAddr":"([^"]+)"', page, "MediaURL")
        sc.set_var("Referer", "https://www.tiktok.com/")

    with service(r"^https?://([^/]+\.)?(twitter|x|fxtwitter|vxtwitter|fixupx|fixvx)\.com/"):
        tweet_id = sc.capture(r"/status(?:es)?/(\d+)", link, "TweetID")
        with sc.when(tweet_id, HAS_VALUE):
            # The token param must be present but isn't validated (see Twitter.swift).
            tweet = sc.fetch("https://cdn.syndication.twimg.com/tweet-result?lang=en&token=a&id=", tweet_id)
            sc.capture(r'"url":"(https://video\.twimg\.com/[^"]+?\.mp4[^"]*)"', tweet, "MediaURL", pick_last=True)
            sc.set_var("Referer", "https://x.com/")

    with service(r"^https?://([^/]+\.)?(reddit\.com|redd\.it)/"):
        page = sc.fetch(link)
        sc.set_var("RedditPage", page)
        challenge = sc.capture(r'\(async\s*\(?(\w+)\)?\s*=>\s*\1\s*\+\s*\1\)\("([^"]+)"\)', page, "RedditToken", group=2)
        with sc.when(challenge, HAS_VALUE):
            action = sc.capture(r'<form[^>]*action="([^"]*)"', page, "RedditAction")
            jsc = sc.capture(r'name="jsc_token" value="([^"]*)"', page, "RedditJSC")
            solved = sc.fetch("https://www.reddit.com", action, "?solution=", challenge, challenge,
                              "&js_challenge=1&jsc_token=", jsc, "&jsc_orig_r=")
            sc.set_var("RedditPage", solved)
        video_id = sc.capture(r"https://v\.redd\.it/([A-Za-z0-9]+)", Var("RedditPage"), "RedditVideoID")
        with sc.when(video_id, HAS_VALUE):
            manifest = sc.fetch("https://v.redd.it/", video_id, "/DASHPlaylist.mpd")
            # Representations are listed best-first.
            best = sc.capture(r"<BaseURL>(DASH_[^<]+)</BaseURL>", manifest, "RedditRep")
            with sc.when(best, HAS_VALUE):
                sc.set_var("MediaURL", "https://v.redd.it/", video_id, "/", best)
                sc.set_var("Referer", "https://www.reddit.com/")

    with service(r"^https?://([^/]+\.)?(facebook\.com|fb\.watch|fb\.com)/"):
        page = sc.fetch(link)
        sc.capture(r'"(?:browser_native_hd_url|playable_url_quality_hd|browser_native_sd_url|playable_url)":"([^"]+)"',
                   page, "MediaURL")
        with sc.when(media, NO_VALUE):
            sc.capture(r'<meta[^>]+property="og:video(?::secure_url|:url)?"[^>]+content="([^"]+)"', page, "MediaURL")
        sc.set_var("Referer", "https://www.facebook.com/")

    with service(r"^https?://([^/]+\.)?streamable\.com/"):
        video_id = sc.capture(r"streamable\.com/(?:[eos]/)?([A-Za-z0-9]+)", link, "StreamableID")
        with sc.when(video_id, HAS_VALUE):
            info = sc.fetch("https://api.streamable.com/videos/", video_id)
            sc.capture(r'"mp4":\s*\{[^}]*?"url":\s*"([^"]+)"', info, "MediaURL")

    # Fallback for anything else (and services above that came up empty): direct file or og:video.
    with sc.when(media, NO_VALUE):
        direct = sc.add("text.match", {"WFMatchTextPattern": r"\.(mp4|mov|m4v)(\?|#|$)", "text": text(link),
                                       "WFMatchTextCaseSensitive": False}, "Matches")

        def scrape_page():
            page = sc.fetch(link)
            sc.capture(r'<meta[^>]+(?:property|name)="(?:og:video:secure_url|og:video:url|og:video|twitter:player:stream)"'
                       r'[^>]+content="([^"]+\.(?:mp4|mov|m4v)[^"]*)"', page, "MediaURL")
            sc.set_var("Referer", link)

        with sc.when(direct, HAS_VALUE, otherwise=scrape_page):
            sc.set_var("MediaURL", link)

    # Download + hand off to the share sheet (Messages, Save Video, …).
    def not_found():
        sc.alert("Clipper", "Couldn't find a video at that link. It may be private, a photo post, "
                            "or from a site Clipper doesn't support yet.")

    with sc.when(media, HAS_VALUE, otherwise=not_found):
        clean = media
        for find, repl in [(r"\/", "/"), (r"&", "&"), (r"/", "/"), (r"%", "%"), ("&amp;", "&")]:
            clean = sc.replace(clean, find, repl)
        clean = sc.replace(clean, "^//", "https://", regex=True)
        video = sc.fetch(clean, headers=[("Referer", (referer,))])
        named = sc.add("setitemname", {"WFInput": token(video), "WFName": "clip.mp4",
                                       "WFDontIncludeFileExtension": False}, "Renamed Item")
        sc.add("share", {"WFInput": token(named)})

    return {
        "WFWorkflowClientVersion": "2605.0.5",
        "WFWorkflowMinimumClientVersion": 900,
        "WFWorkflowMinimumClientVersionString": "900",
        "WFWorkflowIcon": {"WFWorkflowIconStartColor": 4282601983, "WFWorkflowIconGlyphNumber": 61440},
        "WFWorkflowImportQuestions": [],
        "WFWorkflowTypes": ["ActionExtension"],
        "WFWorkflowInputContentItemClasses": ["WFURLContentItem", "WFStringContentItem"],
        "WFWorkflowHasShortcutInputVariables": True,
        "WFWorkflowNoInputBehavior": {"Name": "WFWorkflowNoInputBehaviorGetClipboard", "Parameters": {}},
        "WFWorkflowOutputContentItemClasses": [],
        "WFQuickActionSurfaces": [],
        "WFWorkflowActions": sc.actions,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--unsigned", action="store_true", help="skip `shortcuts sign` (output is importable only on macOS)")
    parser.add_argument("-o", "--output", default=str(HERE / "Clipper.shortcut"))
    args = parser.parse_args()

    output = Path(args.output)
    unsigned = output.with_suffix(".unsigned.shortcut") if not args.unsigned else output
    with open(unsigned, "wb") as f:
        plistlib.dump(build(), f, fmt=plistlib.FMT_BINARY)

    if not args.unsigned:
        subprocess.run(["shortcuts", "sign", "--mode", "anyone", "--input", str(unsigned), "--output", str(output)], check=True)
        unsigned.unlink()
    print(f"wrote {output} ({len(build()['WFWorkflowActions'])} actions)")


if __name__ == "__main__":
    main()
