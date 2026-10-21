import Foundation

/// Nơi gom chẩn đoán của mọi phiên engine mà một lời gọi `LegadoSourceRuntime` mở ra (bộ chạy nghiệm thu, màn gỡ
/// lỗi). Truyền `nil` khi không cần — app thường không truyền.
///
/// Chép từ `session.diagnostics` lúc phiên kết thúc, **kể cả khi phiên ném lỗi**. An toàn đa luồng.
final class LegadoRunLog: @unchecked Sendable {
    struct Entry: Sendable {
        /// `LegadoEngineDiagnostics.Kind.rawValue`: `unsupported`, `javaScript`, `ruleSyntax`, `network`, `http`, `info`.
        let kind: String
        let message: String
    }

    private let lock = NSLock()
    private var storage: [Entry] = []
    private static let capacity = 1000

    init() {}

    func absorb(_ diagnostics: LegadoEngineDiagnostics) {
        let incoming = diagnostics.entries.map { Entry(kind: $0.kind.rawValue, message: $0.message) }
        guard !incoming.isEmpty else { return }
        lock.lock()
        let room = max(0, Self.capacity - storage.count)
        storage.append(contentsOf: incoming.prefix(room))
        lock.unlock()
    }

    var entries: [Entry] {
        lock.lock()
        defer { lock.unlock() }
        return storage
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
