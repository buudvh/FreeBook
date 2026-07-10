import SwiftUI
import Combine

/// Lightweight wrapper that subscribes **only** to `TTSManager.shared.isPlaying`.
/// Use this instead of observing the full `TTSManager` in views that only need
/// the play/pause icon state – avoids body re-evaluation from unrelated
/// `@Published` properties (paragraphIndex, highlightRange, download progress…).
@MainActor
final class TTSPlayStateReader: ObservableObject {
    @Published var isPlaying: Bool = false
    private var cancellable: AnyCancellable?

    init() {
        isPlaying = TTSManager.shared.isPlaying
        cancellable = TTSManager.shared.$isPlaying
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.isPlaying = value
            }
    }
}
