import Foundation

struct Streamable: Extractor {
    let name = "Streamable"

    func matches(_ url: URL) -> Bool { url.hostMatches("streamable.com") }

    func extract(_ url: URL, http: HTTP) async throws -> Media {
        // streamable.com/<id>, /e/<id>, /o/<id>
        guard let id = url.parts.last(where: { !["e", "o", "s"].contains($0) }) else { throw ClipperError.unsupported(url) }
        let json = try? await http.get(URL(string: "https://api.streamable.com/videos/\(id)")!).json()
        guard JSON.at(json, "status") as? Int == 2 else {
            throw ClipperError.noVideo("This Streamable video is missing or still processing.")
        }
        guard var string = (JSON.at(json, "files", "mp4", "url") ?? JSON.at(json, "files", "mp4-mobile", "url")) as? String else {
            throw ClipperError.noVideo("Streamable didn't list an mp4 for this video.")
        }
        if string.hasPrefix("//") { string = "https:" + string }
        guard let video = URL(string: string) else { throw ClipperError.unsupported(url) }
        return Media(video: video, title: JSON.at(json, "title") as? String)
    }
}
