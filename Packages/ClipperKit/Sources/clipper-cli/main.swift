import ClipperKit
import Foundation

// Debug harness for the extractors: `swift run clipper-cli <url> [<url>…]`
// Downloads each clip into the current directory using the exact code path the apps use.

let inputs = CommandLine.arguments.dropFirst()
guard !inputs.isEmpty else {
    print("usage: clipper-cli <url> [<url>…]")
    print("services: \(Clipper.supportedServices.joined(separator: ", ")) + direct/og:video links")
    exit(2)
}

let clipper = Clipper(outputDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
var failures = 0
for input in inputs {
    print("→ \(input)")
    do {
        let clip = try await clipper.clip(input) { print("  … \($0)") }
        let size = (try? clip.fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        print("  ✓ \(clip.service): \(clip.fileURL.lastPathComponent) (\(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)))")
    } catch {
        failures += 1
        print("  ✗ \(error.localizedDescription)")
    }
}
exit(failures == 0 ? 0 : 1)
