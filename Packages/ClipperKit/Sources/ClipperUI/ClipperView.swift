#if canImport(UIKit)
import ClipperKit
import SwiftUI
import UniformTypeIdentifiers

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
                pasteButton.labelStyle(.iconOnly)
            }
        }
        .disabled(model.isWorking)
    }

    private var pasteButton: some View {
        PasteButton(supportedContentTypes: [.url, .plainText]) { providers in
            Task {
                if let text = await Self.loadText(from: providers) { model.submit(text) }
            }
        }
        .buttonBorderShape(.capsule)
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

    /// Share sheets put either a URL or plain text on the pasteboard; accept both.
    private static func loadText(from providers: [NSItemProvider]) async -> String? {
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self),
               let url: URL = await load(URL.self, from: provider) {
                return url.absoluteString
            }
            if provider.canLoadObject(ofClass: String.self),
               let text: String = await load(String.self, from: provider) {
                return text
            }
        }
        return nil
    }

    private static func load<T: _ObjectiveCBridgeable>(_ type: T.Type, from provider: NSItemProvider) async -> T?
    where T._ObjectiveCType: NSItemProviderReading {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: type) { value, _ in continuation.resume(returning: value) }
        }
    }
}
#endif
