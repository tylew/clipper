import ClipperKit
import Foundation

@MainActor
public final class ClipperModel: ObservableObject {
    public enum Phase: Equatable {
        case idle
        case working(String)
        case ready(Clip)
        case failed(String)
    }

    @Published public var phase: Phase = .idle
    @Published public var text = ""

    /// Called once a clip has finished downloading.
    public var onClip: ((Clip) -> Void)?

    private let clipper: Clipper
    private var task: Task<Void, Never>?

    public init(clipper: Clipper = Clipper()) {
        self.clipper = clipper
    }

    public var isWorking: Bool {
        if case .working = phase { return true }
        return false
    }

    public func submit(_ input: String? = nil) {
        if let input { text = input }
        let link = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !link.isEmpty else { return }

        task?.cancel()
        phase = .working(Clipper.Stage.resolving.description)
        task = Task { [clipper] in
            do {
                let clip = try await clipper.clip(link) { stage in
                    Task { @MainActor [weak self] in
                        guard let self, self.isWorking else { return }
                        self.phase = .working(stage.description)
                    }
                }
                guard !Task.isCancelled else { return }
                phase = .ready(clip)
                onClip?(clip)
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed(error.localizedDescription)
            }
        }
    }

    public func reset() {
        task?.cancel()
        task = nil
        phase = .idle
        text = ""
    }

    public func fail(_ message: String) {
        phase = .failed(message)
    }

    /// Clears out downloads from earlier sessions.
    public func purgeOldClips() {
        clipper.purge()
    }
}
