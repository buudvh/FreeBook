import Foundation

/// Sink của **một** lượt chạy: giữ định danh run và cấp số thứ tự, rồi bàn event cho
/// `ExtensionDebugEventHub`.
///
/// **Cố ý lệch plan (plan viết "ExtensionDebugSession actor").** Sink bị gọi đồng bộ từ trong
/// `@convention(block)` của JavaScriptCore và từ callback `URLSession`; `actor` sẽ buộc `await` ở
/// đúng những chỗ không được phép `await`, và nếu bọc bằng `Task` tại call site thì thứ tự event
/// không còn bảo đảm. Nên: `final class` + `NSLock` cho bộ đếm (giữ thứ tự), còn phần buffer/quota —
/// state chia sẻ giữa nhiều run — vẫn nằm trong actor hub.
///
/// Khoá chỉ bảo vệ đúng một `Int` và không bao giờ được giữ qua một lời gọi khác.
public final class ExtensionDebugSession: ExtensionDebugEventSink, @unchecked Sendable {
    public let runId: UUID
    public let packageId: String
    /// Script key của entrypoint (`search`, `detail`…) — đi vào `ExtensionDebugEvent.script`.
    public let script: String
    /// Đường dẫn **tương đối so với gốc extension** (`search.js`, `src/search.js`) — đi vào
    /// `ExtensionDebugSourceLocation.script`. Hai thứ này khác nhau và không được trộn: client Phase 2
    /// mở file theo path, còn nhóm/lọc trace theo key.
    public let scriptPath: String
    public let sourceRevision: String

    private let hub: ExtensionDebugEventHub
    private let lock = NSLock()
    private var nextSequence = 0

    public init(
        runId: UUID = UUID(),
        packageId: String,
        script: String,
        scriptPath: String,
        sourceRevision: String,
        hub: ExtensionDebugEventHub = .shared
    ) {
        self.runId = runId
        self.packageId = packageId
        self.script = script
        self.scriptPath = scriptPath
        self.sourceRevision = sourceRevision
        self.hub = hub
    }

    public func emit(
        _ category: ExtensionDebugEvent.Category,
        level: ExtensionDebugEvent.Level,
        message: String,
        location: ExtensionDebugSourceLocation?,
        details: [String: String]
    ) {
        lock.lock()
        let sequence = nextSequence
        nextSequence += 1
        lock.unlock()

        let event = ExtensionDebugEvent(
            runId: runId,
            sequence: sequence,
            packageId: packageId,
            script: script,
            sourceRevision: sourceRevision,
            level: level,
            category: category,
            message: ExtensionDebugRedactor.message(message),
            location: location,
            details: details
        )
        Task { await hub.append(event) }
    }
}
