import Foundation

/// Nhật ký chẩn đoán của một phiên engine: lỗi **không** làm hỏng luồng (JS ném lỗi, regex/CSS hỏng, hàm chưa hỗ trợ,
/// request phụ lỗi) vẫn được ghi lại để bộ chạy nghiệm thu phân loại và màn gỡ lỗi hiển thị. Đồng thời ghi `AppLogger`
/// (dòng lỗi có `❌`). An toàn đa luồng; giữ tối đa 300 mục mỗi phiên.
final class LegadoEngineDiagnostics: @unchecked Sendable {
    enum Kind: String {
        /// Hàm/cú pháp chưa hỗ trợ (stub đợt 2/3, URL `data:`, `@put` không đọc được…).
        case unsupported
        case javaScript
        /// Rule lỗi cú pháp: regex không biên dịch, bộ chọn CSS lỗi, `@put` hỏng.
        case ruleSyntax
        case network
        case http
        case info
    }

    struct Entry {
        let kind: Kind
        let message: String
        let date: Date
    }

    private let lock = NSLock()
    private var storage: [Entry] = []
    private let sourceName: String
    private static let capacity = 300

    init(sourceName: String) {
        self.sourceName = sourceName
    }

    func record(_ kind: Kind, _ message: String) {
        let trimmed = message.count > 600 ? String(message.prefix(600)) + "…" : message
        lock.lock()
        let position = storage.count
        if storage.count < Self.capacity {
            storage.append(Entry(kind: kind, message: trimmed, date: Date()))
        }
        lock.unlock()
        // Chỉ 20 mục đầu mỗi phiên được đánh dấu lỗi (luôn ghi file); phần sau chỉ ghi khi bật log, tránh tràn log.
        let marker = kind == .info || position >= 20 ? "" : "❌ "
        AppLogger.shared.log("\(marker)[Legado \(sourceName)] \(kind.rawValue): \(trimmed)")
    }

    var entries: [Entry] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    /// Tên các hàm/cú pháp chưa hỗ trợ đã gặp (không trùng, theo thứ tự gặp).
    var unsupportedFeatures: [String] {
        var seen = Set<String>()
        return entries.filter { $0.kind == .unsupported }.map { $0.message }.filter { seen.insert($0).inserted }
    }

    func count(of kind: Kind) -> Int {
        entries.filter { $0.kind == kind }.count
    }
}
