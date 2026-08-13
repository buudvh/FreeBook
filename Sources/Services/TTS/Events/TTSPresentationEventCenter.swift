import Foundation

public final class TTSPresentationEventCenter: Sendable {
    public static let shared = TTSPresentationEventCenter()

    private let lock = NSLock()
    private nonisolated(unsafe) var continuation: AsyncStream<TTSPresentationEvent>.Continuation?
    public let stream: AsyncStream<TTSPresentationEvent>

    private init() {
        let (stream, continuation) = AsyncStream<TTSPresentationEvent>.makeStream()
        self.stream = stream
        self.continuation = continuation
    }

    public func send(_ event: TTSPresentationEvent) {
        lock.lock()
        let cont = continuation
        lock.unlock()
        cont?.yield(event)
    }
}
