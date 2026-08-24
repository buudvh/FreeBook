import Combine
import Foundation

/// Điều phối viên **duy nhất** của nhật ký toast cho Trung tâm thông báo: giữ trạng thái cho UI và
/// lưu qua [`NotificationInboxStore`](NotificationInboxStore.swift).
///
/// Đặt ở tầng `Common` (không phải `Services`) vì được gọi thẳng từ
/// [`ToastManager`](ToastManager.swift) — luật kiến trúc cấm `Services/**` gọi `ToastManager`.
/// Không `import SwiftUI`; UI observe qua Combine như [`NewChapterInboxManager`](../../Services/NewChapters/NewChapterInboxManager.swift).
@MainActor
final class NotificationInboxManager: ObservableObject {
    static let shared = NotificationInboxManager()

    @Published private(set) var records: [NotificationInboxRecord] = []

    private var didLoad = false

    private init() {}

    /// Số toast chưa đọc — dùng cho badge chuông.
    var unreadCount: Int {
        records.reduce(0) { $0 + ($1.isRead ? 0 : 1) }
    }

    var hasUnread: Bool {
        records.contains { !$0.isRead }
    }

    /// Nạp từ đĩa lần đầu (mở Trung tâm thông báo hoặc lúc khởi động).
    func loadIfNeeded() async {
        guard !didLoad else { return }
        didLoad = true
        records = await NotificationInboxStore.shared.all()
    }

    /// Ghi lại một toast vừa hiện. Gọi từ `ToastManager.show`. Bỏ qua chuỗi rỗng.
    func record(message: String, type: ToastType) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        didLoad = true
        let entry = NotificationInboxRecord(message: trimmed, type: type)
        // Cập nhật RAM ngay để badge phản hồi tức thì; đĩa đồng bộ nền qua actor.
        records.insert(entry, at: 0)
        if records.count > NotificationInboxStore.maxRecords {
            records = Array(records.prefix(NotificationInboxStore.maxRecords))
        }
        Task { _ = await NotificationInboxStore.shared.append(entry) }
    }

    /// Người dùng bấm vào **một** thông báo ⇒ chỉ thông báo đó thành đã đọc. Đã đọc rồi thì
    /// không ghi đĩa lại.
    func markRead(_ record: NotificationInboxRecord) {
        guard let index = records.firstIndex(where: { $0.id == record.id }), !records[index].isRead else { return }
        records[index].isRead = true
        let snapshot = records
        Task { await NotificationInboxStore.shared.replace(with: snapshot) }
    }

    func markAllRead() {
        guard records.contains(where: { !$0.isRead }) else { return }
        records = records.map { record in
            var copy = record
            copy.isRead = true
            return copy
        }
        let snapshot = records
        Task { await NotificationInboxStore.shared.replace(with: snapshot) }
    }

    func delete(_ record: NotificationInboxRecord) {
        records.removeAll { $0.id == record.id }
        let snapshot = records
        Task { await NotificationInboxStore.shared.replace(with: snapshot) }
    }

    /// "Xoá thông báo chưa đọc": chỉ bỏ các toast **chưa** đọc, giữ lại phần đã đọc như nhật ký.
    /// Trả về số dòng đã xoá để View báo lại cho người dùng.
    @discardableResult
    func deleteUnread() -> Int {
        let remaining = records.filter { $0.isRead }
        let removed = records.count - remaining.count
        guard removed > 0 else { return 0 }
        records = remaining
        let snapshot = records
        Task { await NotificationInboxStore.shared.replace(with: snapshot) }
        return removed
    }
}
