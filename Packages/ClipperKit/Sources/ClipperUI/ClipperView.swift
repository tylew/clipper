#if canImport(UIKit)
import ClipperKit
import SwiftUI

/// Paste-a-link UI shared by the app and the iMessage extension.
/// `compact` hides the text field (the Messages drawer can't show a keyboard in compact mode);
/// `onRequestKeyboard` lets the host expand itself so the user can type instead.
public struct ClipperView<ReadyContent: View>: View {
    @ObservedObject var model: ClipperModel
    var compact: Bool
    var onRequestKeyboard: (() -> Void)?
    var readyContent: (Clip) -> ReadyContent

    public init(model: ClipperModel, compact: Bool = false, onRequestKeyboard: (() -> Void)? = nil,
                @ViewBuilder readyContent: @escaping (Clip) -> ReadyContent) {
        self.model = model
        self.compact = compact
        self.onRequestKeyboard = onRequestKeyboard
        self.readyContent = readyContent
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            inputRow
            status
            Spacer(minLength: 0)
        }
        .padding()
        .animation(.default, value: model.phase)
    }

    private var inputRow: some View {
        HStack(spacing: 10) {
            if compact {
                pasteButton
                    .labelStyle(.titleAndIcon)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let onRequestKeyboard {
                    Button(action: onRequestKeyboard) { Image(systemName: "keyboard") }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Type a link")
                }
            } else {
                TextField("Paste a video link", text: $model.text)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit { model.submit() }
                    .onChange(of: model.text) { old, new in
                        // A paste (vs. typing) lands many characters at once; start right away.
                        if new.count - old.count > 8, Clipper.firstURL(in: new) != nil { model.submit() }
                    }
                pasteButton.labelStyle(.iconOnly)
            }
        }
        .disabled(model.isWorking)
    }

    /// A plain button that reads `UIPasteboard` (iOS shows its "Allow Paste" prompt).
    /// SwiftUI's `PasteButton` stays disabled inside the Messages extension, so it isn't used.
    private var pasteButton: some View {
        Button(action: pasteFromClipboard) {
            Label("Paste link", systemImage: "doc.on.clipboard")
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
    }

    private func pasteFromClipboard() {
        let pasteboard = UIPasteboard.general
        // `has…` checks don't trigger the paste prompt; only one actual read happens below.
        if pasteboard.hasURLs, let url = pasteboard.url {
            model.submit(url.absoluteString)
        } else if pasteboard.hasStrings, let text = pasteboard.string, Clipper.firstURL(in: text) != nil {
            model.submit(text)
        } else {
            model.fail("Copy a video link first, then tap Paste link.")
        }
    }

    @ViewBuilder private var status: some View {
        switch model.phase {
        case .idle:
            Text("Paste a link from \(ListFormatter.localizedString(byJoining: Clipper.supportedServices)), or any page with a video.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .working(let message):
            HStack(spacing: 10) {
                ProgressView()
                Text(message).font(.callout)
                Spacer()
                Button("Cancel", role: .cancel) { model.reset() }.font(.callout)
            }
        case .ready(let clip):
            VStack(alignment: .leading, spacing: 10) {
                readyContent(clip)
                Button("Clip another") { model.reset() }.font(.callout)
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                Button("Try again") { model.submit() }.font(.callout)
            }
        }
    }
}
#endif
