import Foundation

/// Cửa xác nhận vật lý cho ba lệnh nguy hiểm nhất: `draft.install` (ghi đè), `draft.install` của một
/// extension **chưa có trên app** (cài mới), và `draft.rollback`.
///
/// Nó tồn tại vì lệnh đến **từ mạng**, và từ 1.3.305 server không còn ghép nối — nghĩa là ghi đè
/// extension đang cài, hay **thêm** một extension vào thư viện, là việc không được phép xảy ra chỉ vì
/// một message TCP: phải có một lần bấm trên thiết bị, và người bấm phải thấy trước **danh sách file
/// sẽ đổi**.
///
/// Một request tại một thời điểm. Request mới ghi đè request cũ (client chỉ có một, và request cũ nếu
/// còn treo thì đã lỗi thời).
public actor ExtensionDebugInstallGate {
    public static let shared = ExtensionDebugInstallGate()

    public enum Kind: String, Sendable {
        case install
        case installNew
        case rollback
    }

    public struct Request: Sendable, Equatable {
        public let id: UUID
        public let kind: Kind
        public let packageId: String
        public let revision: String
        /// Tên đọc từ `plugin.json` của bản nháp. Chỉ đường **cài mới** cần: người bấm chưa từng thấy
        /// extension này trong thư viện nên một `packageId` trơ trọi là không đủ để quyết định.
        public let displayName: String?
        /// Dòng diff đã sẵn sàng hiển thị (`+ path`, `~ path`, `- path`).
        public let changes: [String]

        public init(
            id: UUID = UUID(),
            kind: Kind,
            packageId: String,
            revision: String,
            displayName: String? = nil,
            changes: [String]
        ) {
            self.id = id
            self.kind = kind
            self.packageId = packageId
            self.revision = revision
            self.displayName = displayName
            self.changes = changes
        }

        public var summary: String {
            switch kind {
            case .install:
                return "Cài bản nháp \(packageId) (\(revision)) — \(changes.count) thay đổi"
            case .installNew:
                let label = displayName.map { "\($0) → \(packageId)" } ?? packageId
                return "Cài MỚI extension \(label) (\(revision)) — \(changes.count) file"
            case .rollback:
                return "Rollback \(packageId) (\(revision)) — \(changes.count) thay đổi"
            }
        }
    }

    public enum Decision: Sendable {
        case approved
        case rejected
        case superseded
    }

    private var pending: Request?
    private var waiters: [UUID: CheckedContinuation<Decision, Never>] = [:]
    private var observers: [UUID: AsyncStream<Request?>.Continuation] = [:]

    public init() {}

    public var currentPending: Request? { pending }

    /// Stream để tầng Views biết có gì đang chờ bấm. Phát `nil` khi không còn gì chờ.
    public func pendingStream() -> AsyncStream<Request?> {
        let (stream, continuation) = AsyncStream<Request?>.makeStream()
        let key = UUID()
        observers[key] = continuation
        continuation.yield(pending)
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeObserver(key) }
        }
        return stream
    }

    private func removeObserver(_ key: UUID) {
        observers.removeValue(forKey: key)
    }

    private func publishPending() {
        for continuation in observers.values {
            continuation.yield(pending)
        }
    }

    /// Treo cho tới khi người dùng bấm. Không có timeout: client có thể `run.cancel`/đóng socket, và
    /// đóng socket sẽ gọi `cancelPending`.
    public func requestApproval(_ request: Request) async -> Decision {
        if let previous = pending, let continuation = waiters.removeValue(forKey: previous.id) {
            continuation.resume(returning: .superseded)
        }
        pending = request
        return await withCheckedContinuation { continuation in
            waiters[request.id] = continuation
            publishPending()
        }
    }

    public func approve(id: UUID) {
        guard pending?.id == id else { return }
        pending = nil
        waiters.removeValue(forKey: id)?.resume(returning: .approved)
        publishPending()
    }

    public func reject(id: UUID) {
        guard pending?.id == id else { return }
        pending = nil
        waiters.removeValue(forKey: id)?.resume(returning: .rejected)
        publishPending()
    }

    /// Client biến mất hoặc server tắt: mọi waiter phải được nhả, nếu không `Task` của router treo mãi.
    public func cancelPending() {
        let ids = Array(waiters.keys)
        pending = nil
        for id in ids {
            waiters.removeValue(forKey: id)?.resume(returning: .rejected)
        }
        publishPending()
    }
}
