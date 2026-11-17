import Foundation

// MARK: - Loose JSON traversal
//
// Services change their payload shapes constantly, so extractors walk untyped JSON
// (`JSONSerialization` output) instead of decoding brittle Codable models.

public protocol JSONKey {}
extension String: JSONKey {}
extension Int: JSONKey {}

enum JSON {
    static func at(_ root: Any?, _ path: any JSONKey...) -> Any? {
        var current = root
        for key in path {
            switch key {
            case let name as String:
                current = (current as? [String: Any])?[name]
            case let index as Int:
                guard let array = current as? [Any], array.indices.contains(index) else { return nil }
                current = array[index]
            default:
                return nil
            }
        }
        return current is NSNull ? nil : current
    }

    static func parse(_ text: String) -> Any? {
        try? JSONSerialization.jsonObject(with: Data(text.utf8))
    }
}

// MARK: - String scraping

extension String {
    /// First capture group (or whole match for `group: 0`) of `pattern`.
    func firstMatch(_ pattern: String, group: Int = 1, options: NSRegularExpression.Options = []) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options),
              let match = regex.firstMatch(in: self, range: NSRange(startIndex..., in: self)),
              let range = Range(match.range(at: group), in: self) else { return nil }
        return String(self[range])
    }

    /// Decodes a JSON string body scraped out of HTML (`\/`, `&`, …).
    var jsonUnescaped: String {
        (try? JSONDecoder().decode(String.self, from: Data("\"\(self)\"".utf8))) ?? self
    }

    var htmlUnescaped: String {
        [("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&#x27;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&#x2F;", "/")]
            .reduce(self) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    }

    /// Content of `<meta property|name="…" content="…">`, in either attribute order.
    func metaContent(_ property: String) -> String? {
        let p = NSRegularExpression.escapedPattern(for: property)
        return (firstMatch(#"<meta[^>]+(?:property|name)=["']\#(p)["'][^>]*content=["']([^"']+)["']"#, options: .caseInsensitive)
            ?? firstMatch(#"<meta[^>]+content=["']([^"']+)["'][^>]*(?:property|name)=["']\#(p)["']"#, options: .caseInsensitive))?
            .htmlUnescaped
    }
}

extension URL {
    func hostMatches(_ domains: String...) -> Bool {
        let host = host?.lowercased() ?? ""
        return domains.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// Path components without the leading "/".
    var parts: [String] { pathComponents.filter { $0 != "/" } }

    func queryValue(_ name: String) -> String? {
        URLComponents(url: self, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }
}
