import Foundation

/// A downloaded video, ready to attach or share.
public struct Clip: Sendable, Equatable {
    public let fileURL: URL
    public let service: String
    public let title: String?
}

/// What an extractor found: where the video (and, for split DASH streams, the audio) lives.
public struct Media: Sendable {
    public var video: URL
    public var audio: URL? = nil
    /// Headers the media CDN needs (usually a Referer).
    public var headers: [String: String] = [:]
    public var title: String? = nil
}

public protocol Extractor: Sendable {
    var name: String { get }
    func matches(_ url: URL) -> Bool
    func extract(_ url: URL, http: HTTP) async throws -> Media
}

public enum ClipperError: LocalizedError, Equatable {
    case noLink
    case unsupported(URL)
    case noVideo(String)
    case loginRequired(String)
    case blocked(String)
    case http(Int)

    public var errorDescription: String? {
        switch self {
        case .noLink: "That doesn't look like a link."
        case .unsupported(let url): "Couldn't find a video at \(url.host ?? url.absoluteString)."
        case .noVideo(let reason), .loginRequired(let reason), .blocked(let reason): reason
        case .http(let code): "The server responded with an error (\(code))."
        }
    }
}

/// Thrown by an extractor when the link is a wrapper around a video hosted elsewhere
/// (e.g. a Reddit post linking to Streamable).
struct FollowLink: Error {
    let url: URL
}

public struct Clipper: Sendable {
    public enum Stage: Sendable, CustomStringConvertible {
        case resolving, extracting(String), downloading(String), merging

        public var description: String {
            switch self {
            case .resolving: "Opening link…"
            case .extracting(let service): "Finding the \(service) video…"
            case .downloading(let service): "Downloading from \(service)…"
            case .merging: "Merging audio…"
            }
        }
    }

    /// Order matters: the first extractor whose `matches` returns true wins; `Generic` catches the rest.
    public static let extractors: [any Extractor] = [
        Instagram(), TikTok(), Twitter(), Reddit(), Facebook(), Streamable(), Generic(),
    ]

    public static var supportedServices: [String] {
        extractors.map(\.name).filter { $0 != Generic().name }
    }

    public let outputDirectory: URL

    public init(outputDirectory: URL = FileManager.default.temporaryDirectory.appendingPathComponent("Clips", isDirectory: true)) {
        self.outputDirectory = outputDirectory
    }

    /// Pulls the first http(s) link out of whatever was pasted (share sheets often add text around it).
    public static func firstURL(in text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        return detector.matches(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed))
            .compactMap(\.url)
            .first { ["http", "https"].contains($0.scheme?.lowercased()) }
    }

    public static func extractor(for url: URL) -> any Extractor {
        extractors.first { $0.matches(url) } ?? Generic()
    }

    /// Redirecting share links whose real target we need to see before picking an extractor.
    static func isShortLink(_ url: URL) -> Bool {
        let parts = url.parts
        return url.hostMatches("t.co", "vm.tiktok.com", "vt.tiktok.com", "fb.watch", "redd.it", "instagr.am")
            && !url.hostMatches("v.redd.it")
            || url.hostMatches("tiktok.com") && parts.first == "t"
            || url.hostMatches("instagram.com") && parts.first == "share"
            || url.hostMatches("reddit.com") && parts.count >= 3 && parts[2] == "s"
            || url.hostMatches("facebook.com") && parts.first == "share"
    }

    public func clip(_ text: String, onStage: @Sendable (Stage) -> Void = { _ in }) async throws -> Clip {
        guard let url = Self.firstURL(in: text) else { throw ClipperError.noLink }
        let http = HTTP()
        onStage(.resolving)
        return try await clip(url, http: http, onStage: onStage, hops: 0)
    }

    private func clip(_ input: URL, http: HTTP, onStage: @Sendable (Stage) -> Void, hops: Int) async throws -> Clip {
        let url = Self.isShortLink(input) ? try await http.resolve(input) : input
        let extractor = Self.extractor(for: url)
        onStage(.extracting(extractor.name))

        let media: Media
        do {
            media = try await extractor.extract(url, http: http)
        } catch let follow as FollowLink where hops < 2 {
            return try await clip(follow.url, http: http, onStage: onStage, hops: hops + 1)
        }

        onStage(.downloading(extractor.name))
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let stem = "\(extractor.name.lowercased())-\(UUID().uuidString.prefix(8))"
        let output = outputDirectory.appendingPathComponent("\(stem).mp4")

        if let audioURL = media.audio {
            let videoFile = outputDirectory.appendingPathComponent("\(stem)-v.mp4")
            let audioFile = outputDirectory.appendingPathComponent("\(stem)-a.mp4")
            defer {
                try? FileManager.default.removeItem(at: videoFile)
                try? FileManager.default.removeItem(at: audioFile)
            }
            async let v: Void = http.download(media.video, headers: media.headers, to: videoFile)
            async let a: Void = http.download(audioURL, headers: media.headers, to: audioFile)
            try await v
            if (try? await a) != nil {
                onStage(.merging)
                try await Muxer.merge(video: videoFile, audio: audioFile, to: output)
            } else {
                // Silent videos have no audio stream; ship the video alone.
                try FileManager.default.moveItem(at: videoFile, to: output)
            }
        } else {
            try await http.download(media.video, headers: media.headers, to: output)
        }

        return Clip(fileURL: output, service: extractor.name, title: media.title)
    }

    /// Deletes clips older than `age` seconds. Recent ones are kept because Messages may
    /// still be holding a just-inserted attachment.
    public func purge(olderThan age: TimeInterval = 3600) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: outputDirectory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let cutoff = Date().addingTimeInterval(-age)
        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if modified < cutoff { try? fm.removeItem(at: file) }
        }
    }
}
