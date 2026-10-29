import Foundation
import Observation

/// Truyện người dùng **tự đánh dấu** NSFW (hàng "Đánh dấu NSFW" của sheet nhấn giữ `BookActionSheet`), cho các truyện
/// mà nguồn không bị coi là 18+. `RepositoryFilterPolicy.isNsfwBook` gộp dấu này với nguồn NSFW, nên truyện đã đánh
/// dấu bị ẩn ở cùng những chỗ như truyện của nguồn 18+ khi công tắc NSFW tắt.
///
/// - Lưu `UserDefaults` khoá `nsfwMarkedBookIds` (mảng `bookId`): chữ thường, không dấu chấm ⇒ Sao lưu tự gói
///   (`BackupSettingsArchiver`) và `@AppStorage` không vướng lỗi khoá có dấu chấm.
/// - Đọc được từ thread bất kỳ (bộ lọc chạy trong `ShelfBookPartition`, `RepositoryFilterPolicy`): tập `bookId` nằm
///   sau `NSLock`. `revision` là phần `@Observable` — View đọc `isMarked`/`markedBookIds` trong `body` thì vẽ lại ngay
///   khi đánh dấu đổi.
/// - Chỉ đọc khoá lúc khởi tạo: khôi phục bản sao lưu ghi thẳng vào `UserDefaults` ⇒ dấu mới có hiệu lực sau khi mở
///   lại app.
@Observable
final class NsfwBookMarkStore: @unchecked Sendable {
    static let shared = NsfwBookMarkStore()

    static let defaultsKey = "nsfwMarkedBookIds"

    private let lock = NSLock()
    @ObservationIgnored private var bookIds: Set<String>
    /// Tăng mỗi lần đổi dấu — chỉ để Observation báo View vẽ lại.
    private var revision = 0

    private init() {
        bookIds = Set(UserDefaults.standard.stringArray(forKey: Self.defaultsKey) ?? [])
    }

    /// Bản chụp toàn bộ dấu — đọc **một lần** trước vòng lọc thay vì khoá lock từng truyện.
    var markedBookIds: Set<String> {
        _ = revision
        lock.lock()
        defer { lock.unlock() }
        return bookIds
    }

    func isMarked(_ bookId: String) -> Bool {
        _ = revision
        lock.lock()
        defer { lock.unlock() }
        return bookIds.contains(bookId)
    }

    /// Đặt / bỏ dấu một truyện và ghi `UserDefaults` ngay. Gọi từ main (View).
    func setMarked(_ marked: Bool, bookId: String) {
        guard !bookId.isEmpty else { return }
        lock.lock()
        let changed = marked ? bookIds.insert(bookId).inserted : bookIds.remove(bookId) != nil
        let snapshot = Array(bookIds).sorted()
        lock.unlock()
        guard changed else { return }
        UserDefaults.standard.set(snapshot, forKey: Self.defaultsKey)
        revision &+= 1
    }
}
