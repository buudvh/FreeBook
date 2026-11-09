import Foundation

/// Kênh sự kiện từ tầng phát media (phim, nhạc) lên UI — cùng khuôn `TTSPresentationEventCenter` /
/// `DownloadPresentationEventCenter`: Services không gọi `ToastManager`, `AppLaunchRootView` (`FreeBookApp.swift`) là
/// subscriber duy nhất. Không chạm `VideoPlaybackSession` / `AudioPlaybackSession` (chạm là dựng `AVPlayer`).
public final class MediaPresentationEventCenter: Sendable {
    public static let shared = MediaPresentationEventCenter()

    private let lock = NSLock()
    private nonisolated(unsafe) var continuation: AsyncStream<MediaPresentationEvent>.Continuation?
    public let stream: AsyncStream<MediaPresentationEvent>

    private init() {
        let (stream, continuation) = AsyncStream<MediaPresentationEvent>.makeStream()
        self.stream = stream
        self.continuation = continuation
    }

    public func send(_ event: MediaPresentationEvent) {
        lock.lock()
        let cont = continuation
        lock.unlock()
        cont?.yield(event)
    }
}
