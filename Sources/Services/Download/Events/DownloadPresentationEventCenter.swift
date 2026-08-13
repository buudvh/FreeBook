import Foundation

public final class DownloadPresentationEventCenter: Sendable {
    public static let shared = DownloadPresentationEventCenter()

    private let lock = NSLock()
    private nonisolated(unsafe) var continuation: AsyncStream<DownloadPresentationEvent>.Continuation?
    public let stream: AsyncStream<DownloadPresentationEvent>

    private init() {
        let (stream, continuation) = AsyncStream<DownloadPresentationEvent>.makeStream()
        self.stream = stream
        self.continuation = continuation
    }

    public func send(_ event: DownloadPresentationEvent) {
        lock.lock()
        let cont = continuation
        lock.unlock()
        cont?.yield(event)
    }
}
