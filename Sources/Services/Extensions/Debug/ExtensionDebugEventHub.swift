import Foundation

/// Bộ đệm trace dùng chung, có quota, và là nơi phát event cho mọi subscriber.
///
/// Là `actor` vì nó có **state chia sẻ giữa nhiều run**; ngược lại `ExtensionDebugSession` (sink) cố ý
/// **không** phải actor để `JSExecutor` gọi được đồng bộ — xem doc ở đó.
///
/// Quota là bắt buộc, không phải tối ưu: một script lặp `console.log` trong vòng while sẽ sinh event
/// nhanh hơn UI vẽ. Khi vượt trần của một run, event mới bị **bỏ** (không phải bỏ event cũ của run
/// đó — giữ phần đầu quan trọng hơn, vì lỗi thường nằm ở những dòng đầu), và một event
/// `eventsDropped` được chèn **một lần** để người đọc biết trace không đầy đủ.
public actor ExtensionDebugEventHub {
    public static let shared = ExtensionDebugEventHub()

    /// Trần tổng: vượt thì bỏ event **cũ nhất** của toàn hub (ring buffer).
    public static let maxTotalEvents = 2000
    /// Trần mỗi run: vượt thì bỏ event **mới** của đúng run đó.
    public static let maxEventsPerRun = 600

    private var buffer: [ExtensionDebugEvent] = []
    private var countByRun: [UUID: Int] = [:]
    private var droppedByRun: [UUID: Int] = [:]
    private var continuations: [UUID: AsyncStream<ExtensionDebugEvent>.Continuation] = [:]

    public init() {}

    public func append(_ event: ExtensionDebugEvent) {
        let count = countByRun[event.runId] ?? 0
        if count >= Self.maxEventsPerRun {
            let dropped = (droppedByRun[event.runId] ?? 0) + 1
            droppedByRun[event.runId] = dropped
            guard dropped == 1 else { return }
            // Event thông báo drop đi thẳng vào buffer, không tính vào quota — nếu nó cũng bị quota
            // chặn thì người đọc sẽ không bao giờ biết trace bị cắt.
            store(
                ExtensionDebugEvent(
                    runId: event.runId,
                    sequence: event.sequence,
                    packageId: event.packageId,
                    script: event.script,
                    sourceRevision: event.sourceRevision,
                    level: .warning,
                    category: .eventsDropped,
                    message: "Vượt trần \(Self.maxEventsPerRun) event mỗi run — các event sau bị bỏ",
                    details: ["limit": String(Self.maxEventsPerRun)]
                )
            )
            return
        }
        countByRun[event.runId] = count + 1
        store(event)
    }

    private func store(_ event: ExtensionDebugEvent) {
        buffer.append(event)
        if buffer.count > Self.maxTotalEvents {
            let overflow = buffer.count - Self.maxTotalEvents
            let evicted = buffer.prefix(overflow)
            for item in evicted {
                if let current = countByRun[item.runId] {
                    if current <= 1 {
                        countByRun.removeValue(forKey: item.runId)
                    } else {
                        countByRun[item.runId] = current - 1
                    }
                }
            }
            buffer.removeFirst(overflow)
        }
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    /// Snapshot để UI dựng lần đầu; `nil` là lấy tất cả run còn trong buffer.
    public func events(for runId: UUID? = nil) -> [ExtensionDebugEvent] {
        guard let runId else { return buffer }
        return buffer.filter { $0.runId == runId }
    }

    public func droppedCount(for runId: UUID) -> Int {
        droppedByRun[runId] ?? 0
    }

    /// Mỗi subscriber một stream riêng; huỷ stream tự gỡ continuation nên không rò.
    public func stream() -> AsyncStream<ExtensionDebugEvent> {
        let (stream, continuation) = AsyncStream<ExtensionDebugEvent>.makeStream()
        let key = UUID()
        continuations[key] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeContinuation(key) }
        }
        return stream
    }

    private func removeContinuation(_ key: UUID) {
        continuations.removeValue(forKey: key)
    }

    public func clear() {
        buffer.removeAll()
        countByRun.removeAll()
        droppedByRun.removeAll()
    }
}
