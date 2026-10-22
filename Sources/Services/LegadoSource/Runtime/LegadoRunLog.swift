import Foundation

/// Nơi gom chẩn đoán của mọi phiên engine mà một lời gọi `LegadoSourceRuntime` mở ra (bộ chạy nghiệm thu, màn gỡ
/// lỗi). Truyền `nil` khi không cần — app thường không truyền.
///
/// Chép từ `session.diagnostics` lúc phiên kết thúc, **kể cả khi phiên ném lỗi**: dòng chẩn đoán và vết request
/// (`LegadoEngineRequestRecord` — URL, mã HTTP, bảng mã, kích thước, đoạn đầu thân phản hồi), cộng kết quả **đầu dò bộ
/// chọn** (`LegadoSelectorProbe`) khi một bước danh sách/nội dung ra rỗng. Màn gỡ lỗi từng bước và bộ nghiệm thu tạo
/// **một** log cho mỗi bước để tách vết theo bước. An toàn đa luồng. Không ghi gì ra đĩa.
///
/// Hai cách gắn log vào một lượt chạy:
/// - truyền thẳng tham số `log:` của các luồng `LegadoSourceRuntime` (màn gỡ lỗi);
/// - đặt task-local `LegadoRunLog.$current.withValue(log) { … }` quanh lời gọi facade `SourceRuntime` (bộ nghiệm
///   thu — facade không có tham số log). `runSession` đọc task-local **trong ngữ cảnh async, trước khi** engine nhảy
///   sang thread riêng (closure chạy trên thread engine không thấy task-local).
final class LegadoRunLog: @unchecked Sendable {
    struct Entry: Sendable {
        /// `LegadoEngineDiagnostics.Kind.rawValue`: `unsupported`, `javaScript`, `ruleSyntax`, `network`, `http`, `info`.
        let kind: String
        let message: String
    }

    /// Log của lượt chạy hiện tại khi lời gọi không truyền `log:` (vd qua facade). Mặc định `nil` ⇒ không gom gì.
    @TaskLocal static var current: LegadoRunLog? = nil

    private let lock = NSLock()
    private var storage: [Entry] = []
    private var requestStorage: [LegadoEngineRequestRecord] = []
    private var probeStorage: [LegadoSelectorProbe] = []
    private static let capacity = 1000
    private static let requestCapacity = 200
    private static let probeCapacity = 20

    init() {}

    /// Log tường minh thắng; không có thì lấy task-local. Gọi trong ngữ cảnh async của lời gọi (không phải trên thread
    /// engine).
    static func resolve(_ explicit: LegadoRunLog?) -> LegadoRunLog? {
        explicit ?? current
    }

    func absorb(_ diagnostics: LegadoEngineDiagnostics) {
        let incoming = diagnostics.entries.map { Entry(kind: $0.kind.rawValue, message: $0.message) }
        let incomingRequests = diagnostics.requests
        guard !incoming.isEmpty || !incomingRequests.isEmpty else { return }
        lock.lock()
        let room = max(0, Self.capacity - storage.count)
        storage.append(contentsOf: incoming.prefix(room))
        let requestRoom = max(0, Self.requestCapacity - requestStorage.count)
        requestStorage.append(contentsOf: incomingRequests.prefix(requestRoom))
        lock.unlock()
    }

    /// Ghi kết quả đầu dò bộ chọn (giữ tối đa `probeCapacity` bản đầu).
    func recordProbe(_ probe: LegadoSelectorProbe) {
        lock.lock()
        if probeStorage.count < Self.probeCapacity {
            probeStorage.append(probe)
        }
        lock.unlock()
    }

    var entries: [Entry] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    /// Vết request của mọi phiên đã gom, theo thứ tự phiên kết thúc (trong một phiên: thứ tự gửi).
    var requests: [LegadoEngineRequestRecord] {
        lock.lock()
        defer { lock.unlock() }
        return requestStorage
    }

    /// Kết quả đầu dò bộ chọn theo thứ tự ghi (bản cuối ứng với lần ra rỗng gần nhất).
    var probes: [LegadoSelectorProbe] {
        lock.lock()
        defer { lock.unlock() }
        return probeStorage
    }

    /// Hàm/cú pháp chưa hỗ trợ đã gặp (không trùng, theo thứ tự gặp) — "cú pháp chưa hỗ trợ" của bộ nghiệm thu.
    var unsupportedFeatures: [String] {
        var seen = Set<String>()
        return entries.filter { $0.kind == LegadoEngineDiagnostics.Kind.unsupported.rawValue }
            .map { $0.message }
            .filter { seen.insert($0).inserted }
    }

    func count(ofKind kind: String) -> Int {
        entries.filter { $0.kind == kind }.count
    }

    // MARK: - Gắn log vào phiên engine

    /// Bảng phiên engine đang chạy → log của lượt. Code luồng chạy trên thread engine (không thấy task-local) tra log
    /// qua phiên của nó (`bound(to:)`) — chỉ để ghi đầu dò bộ chọn, và chỉ khi có log (app thường: bảng rỗng).
    final class SessionTable: @unchecked Sendable {
        private let lock = NSLock()
        private var logs: [ObjectIdentifier: LegadoRunLog] = [:]

        func bind(_ log: LegadoRunLog, to session: LegadoEngineSession) {
            lock.lock()
            logs[ObjectIdentifier(session)] = log
            lock.unlock()
        }

        func unbind(_ session: LegadoEngineSession) {
            lock.lock()
            logs.removeValue(forKey: ObjectIdentifier(session))
            lock.unlock()
        }

        func log(for session: LegadoEngineSession) -> LegadoRunLog? {
            lock.lock()
            defer { lock.unlock() }
            return logs[ObjectIdentifier(session)]
        }
    }

    static let sessions = SessionTable()

    /// Log đã gắn với `session` (trong `runSession`), `nil` khi lượt chạy không có log.
    static func bound(to session: LegadoEngineSession) -> LegadoRunLog? {
        sessions.log(for: session)
    }
}
