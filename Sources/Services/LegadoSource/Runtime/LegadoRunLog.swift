import Foundation

/// Nơi gom chẩn đoán của mọi phiên engine mà một lời gọi `LegadoSourceRuntime` mở ra (bộ chạy nghiệm thu, màn gỡ
/// lỗi). Truyền `nil` khi không cần — app thường không truyền.
///
/// Chép từ `session.diagnostics` lúc phiên kết thúc, **kể cả khi phiên ném lỗi**: dòng chẩn đoán và vết request
/// (`LegadoEngineRequestRecord` — URL, mã HTTP, bảng mã, kích thước, đoạn đầu thân phản hồi). Màn gỡ lỗi từng bước tạo
/// **một** log cho mỗi bước để tách vết theo bước. An toàn đa luồng. Không ghi gì ra đĩa.
final class LegadoRunLog: @unchecked Sendable {
    struct Entry: Sendable {
        /// `LegadoEngineDiagnostics.Kind.rawValue`: `unsupported`, `javaScript`, `ruleSyntax`, `network`, `http`, `info`.
        let kind: String
        let message: String
    }

    private let lock = NSLock()
    private var storage: [Entry] = []
    private var requestStorage: [LegadoEngineRequestRecord] = []
    private static let capacity = 1000
    private static let requestCapacity = 200

    init() {}

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
}
