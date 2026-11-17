import ClipperKit
import ClipperUI
import Messages
import SwiftUI

final class MessagesViewController: MSMessagesAppViewController {
    private let model = ClipperModel()
    private let presentation = PresentationState()

    override func viewDidLoad() {
        super.viewDidLoad()
        model.onClip = { [weak self] clip in self?.insert(clip) }

        let root = MessagesRoot(model: model, presentation: presentation) { [weak self] in
            self?.requestPresentationStyle(.expanded)
        }
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(host)
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
    }

    override func willBecomeActive(with conversation: MSConversation) {
        super.willBecomeActive(with: conversation)
        presentation.isCompact = presentationStyle == .compact
        model.purgeOldClips()
    }

    override func willTransition(to presentationStyle: MSMessagesAppPresentationStyle) {
        super.willTransition(to: presentationStyle)
        presentation.isCompact = presentationStyle == .compact
    }

    /// Drops the video into the message field; the user still taps send.
    private func insert(_ clip: Clip) {
        guard let conversation = activeConversation else {
            model.fail("Couldn't reach the conversation. Close and reopen Clipper.")
            return
        }
        conversation.insertAttachment(clip.fileURL, withAlternateFilename: "\(clip.service)-clip.mp4") { [weak self] error in
            DispatchQueue.main.async {
                if let error {
                    self?.model.fail(error.localizedDescription)
                } else {
                    self?.requestPresentationStyle(.compact)
                }
            }
        }
    }
}

final class PresentationState: ObservableObject {
    @Published var isCompact = true
}

private struct MessagesRoot: View {
    @ObservedObject var model: ClipperModel
    @ObservedObject var presentation: PresentationState
    var expand: () -> Void

    var body: some View {
        ClipperView(model: model, compact: presentation.isCompact, onRequestKeyboard: expand) { _ in
            Label("Added to your message — tap send.", systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.green)
        }
    }
}
