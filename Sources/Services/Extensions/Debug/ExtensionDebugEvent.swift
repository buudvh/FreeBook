import Foundation

/// Một dòng trace của lượt chạy debug extension — **contract v1**, dùng chung cho màn debug trong app
/// (Phase 1) và cho client WebSocket ở Phase 2.
///
/// Hai bất biến của kiểu này:
/// 1. **Mọi field đã được redact trước khi khởi tạo**, không phải lúc gửi đi. Người tạo event chịu
///    trách nhiệm gọi `ExtensionDebugRedactor`; nhờ vậy không tồn tại đường nào mà một event chưa
///    sạch lại lọt ra socket ở Phase 2.
/// 2. **`sequence` tăng đơn điệu trong phạm vi một `runId`**. Client dùng nó để phát hiện event bị
///    drop, nên không được đánh số theo toàn server.
///
/// Thêm `case` vào `Category` là đổi contract ⇒ phải nâng version của giao thức, không thêm im lặng.
public struct ExtensionDebugEvent: Codable, Identifiable, Sendable, Equatable {
    /// Version của contract event. Đi kèm mọi event để client Phase 2 từ chối bản không hiểu.
    public static let contractVersion = 1

    public enum Level: String, Codable, Sendable {
        case debug
        case info
        case warning
        case error
    }

    public enum Category: String, Codable, Sendable {
        case runStarted
        case compileFailed
        case runFinished
        case cancelled
        case console
        case exception
        case responseValidated
        case responseError
        case fetchStarted
        case fetchFinished
        case fetchFailed
        /// Hub đã bỏ event vì vượt quota của run. Không bao giờ do JS sinh ra.
        case eventsDropped
    }

    public let id: UUID
    public let runId: UUID
    public let sequence: Int
    public let timestamp: Date
    public let packageId: String
    /// Script key của entrypoint (`search`, `detail`, …), không phải tên file.
    public let script: String
    public let sourceRevision: String
    public let level: Level
    public let category: Category
    public let message: String
    public let location: ExtensionDebugSourceLocation?
    /// Số liệu phụ đã redact (`status`, `durationMs`, `bytes`, `method`…). Giữ phẳng `String: String`
    /// để contract JSON không phụ thuộc kiểu động.
    public let details: [String: String]

    public init(
        id: UUID = UUID(),
        runId: UUID,
        sequence: Int,
        timestamp: Date = Date(),
        packageId: String,
        script: String,
        sourceRevision: String,
        level: Level,
        category: Category,
        message: String,
        location: ExtensionDebugSourceLocation? = nil,
        details: [String: String] = [:]
    ) {
        self.id = id
        self.runId = runId
        self.sequence = sequence
        self.timestamp = timestamp
        self.packageId = packageId
        self.script = script
        self.sourceRevision = sourceRevision
        self.level = level
        self.category = category
        self.message = message
        self.location = location
        self.details = details
    }

    /// Nhãn ngắn cho danh sách event trong app.
    public var categoryLabel: String {
        switch category {
        case .runStarted: return "RUN"
        case .compileFailed: return "COMPILE"
        case .runFinished: return "DONE"
        case .cancelled: return "CANCEL"
        case .console: return "LOG"
        case .exception: return "EXC"
        case .responseValidated: return "RESP"
        case .responseError: return "RESP!"
        case .fetchStarted: return "GET→"
        case .fetchFinished: return "GET✓"
        case .fetchFailed: return "GET✗"
        case .eventsDropped: return "DROP"
        }
    }

    /// Các số liệu phụ sắp theo khoá để hiển thị ổn định giữa hai lần render.
    public var sortedDetails: [(key: String, value: String)] {
        details.sorted { $0.key < $1.key }.map { (key: $0.key, value: $0.value) }
    }
}
