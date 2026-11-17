import AVKit
import ClipperKit
import ClipperUI
import SwiftUI

/// The container app. The real product is the iMessage extension; this screen runs the same
/// flow with a preview + share sheet, which is handy for testing and for non-Messages use.
@main
struct ClipperApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    @StateObject private var model = ClipperModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                ClipperView(model: model) { clip in
                    VStack(alignment: .leading, spacing: 12) {
                        VideoPlayer(player: AVPlayer(url: clip.fileURL))
                            .frame(height: 360)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        ShareLink(item: clip.fileURL) {
                            Label("Share video", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                Text("To send clips in a chat, open Messages, tap ＋ → More → Clipper.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }
            .navigationTitle("Clipper")
        }
        .onAppear { model.purgeOldClips() }
    }
}
