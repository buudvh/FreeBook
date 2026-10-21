import Foundation
import SwiftData

/// Lượt dọn **sidecar trạng thái truyện mồ côi** của nguồn Legado — chạy một lần mỗi lần mở app, trên nền.
///
/// `legado_state/<sha256(bookId)>.json` (`LegadoBookStateStore`) bình thường bị xoá cùng sách qua `BookStorageManager`
/// → `LegadoBookStateStore.deleteState`; sách mất bằng đường khác (bản app cũ, lỗi giữa chừng…) để lại file không còn
/// chủ. Lượt này lấy toàn bộ `Book.bookId` trên `ModelContext` **riêng** rồi nhờ kho xoá các file sidecar không thuộc
/// sách nào — chỉ file đúng mẫu tên ở gốc `legado_state/`, không đụng `sources/`, `files/`, `jslib/`, `device.json`.
///
/// An toàn:
/// - đọc danh sách sách lỗi ⇒ bỏ lượt này;
/// - danh sách **rỗng** ⇒ bỏ lượt này (không bao giờ xoá sạch chỉ vì thư viện trống/DB mới);
/// - chỉ xoá file sửa lần cuối **trước** lúc bắt đầu lượt: sách thêm ngay sau khi mở app (sau lúc lấy danh sách) vẫn giữ
///   sidecar vừa ghi.
@MainActor
enum LegadoOrphanStateSweeper {
    private static var didStart = false

    /// Chỉ chạy lượt đầu tiên trong tiến trình; các lần gọi sau (view gốc xuất hiện lại) bỏ qua.
    static func startOnce(container: ModelContainer) {
        guard !didStart else { return }
        didStart = true
        let startedAt = Date()
        Task.detached(priority: .utility) {
            Self.run(container: container, startedAt: startedAt)
        }
    }

    private nonisolated static func run(container: ModelContainer, startedAt: Date) {
        let bookIds: Set<String>
        do {
            let context = ModelContext(container)
            context.autosaveEnabled = false
            bookIds = try Set(context.fetch(FetchDescriptor<Book>()).map { $0.bookId })
        } catch {
            AppLogger.shared.log("❌ 🧹 [LegadoStateSweep] Không đọc được danh sách sách — bỏ lượt dọn: \(error.localizedDescription)")
            return
        }
        guard !bookIds.isEmpty else { return }
        let result = LegadoBookStateStore.shared.removeOrphanFiles(keepingBookIds: bookIds, modifiedBefore: startedAt)
        guard result.removed + result.failed > 0 else { return }
        if result.failed > 0 {
            AppLogger.shared.log("❌ 🧹 [LegadoStateSweep] Đã xoá \(result.removed) sidecar truyện mồ côi, \(result.failed) file xoá lỗi")
        } else {
            AppLogger.shared.log("🧹 [LegadoStateSweep] Đã xoá \(result.removed) sidecar truyện mồ côi")
        }
    }
}
