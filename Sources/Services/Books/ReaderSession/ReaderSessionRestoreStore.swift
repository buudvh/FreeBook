import Foundation

/// Mở lại mục đọc/xem gần nhất lúc khởi động (1.3.716, phạm vi đổi ở 1.3.718 — Cài đặt › Đọc & Nghe › Mở lại truyện
/// đọc gần nhất).
///
/// Giữ danh sách `bookId` **mở gần nhất** (mới nhất đứng đầu, tối đa `maxRecentCount`): ghi mỗi khi màn đọc hiện
/// (`BookContentDestination`, đủ cả chữ, truyện tranh, phim). Không dựa `Book.lastReadDate` vì thêm/bỏ khỏi kệ, chọn
/// chương ở Chi tiết hay tạo bản ghi mới cũng đẩy nó lên. Lúc mở app, Kệ duyệt danh sách và mở mục đầu tiên còn trên
/// máy, không phải 18+ (`ShelfView+LaunchRestore`).
///
/// Chống vòng lặp crash: ngay trước khi mở lại, bật cờ "đang thử"; cờ xoá khi màn sống đủ 10 s hoặc khi app rời trạng
/// thái active. Mở app mà cờ còn ⇒ lần mở lại trước chết sớm ⇒ lần này bỏ qua. `UserDefaults` gửi giá trị sang tiến trình
/// `cfprefsd` ngay khi `set`, nên app crash vẫn giữ được cờ.
enum ReaderSessionRestoreStore {
    /// Khoá công tắc ở Cài đặt (không dấu chấm). `@AppStorage` không ghi giá trị mặc định xuống đĩa ⇒ mọi chỗ ngoài View
    /// đọc qua `isEnabled` (khoá chưa ghi = bật).
    static let enabledKey = "restoreReaderOnLaunch"
    static let defaultEnabled = true
    /// Danh sách `bookId` mở gần nhất, mới nhất đứng đầu.
    private static let recentBookIdsKey = "readerSessionRecentBookIds"
    /// Khoá dấu "đang ở màn đọc" của bản 1.3.716 (đã bỏ) — xoá lúc khởi động.
    private static let legacyOpenBookKey = "readerSessionOpenBookId"
    /// `bookId` đang được thử mở lại mà chưa qua mốc an toàn (khoá có mặt = đang thử). Trạng thái riêng của một lần
    /// chạy ⇒ `BackupSettingsArchiver` không sao lưu khoá này.
    static let pendingAttemptKey = "readerSessionRestorePending"
    /// Đủ để bỏ qua một loạt mục 18+ / đã xoá liền nhau mà vẫn tìm được mục để mở.
    static let maxRecentCount = 20
    /// Màn đọc mở lại sống được chừng này thì không còn coi là vòng lặp crash.
    static let survivalDelayNanoseconds: UInt64 = 10_000_000_000

    @MainActor private static var didTakeLaunchCandidates = false
    /// Phim đang được mở lại: trình phát dừng sẵn ở giây đã lưu thay vì tự phát (`consumePausedVideoStart`).
    @MainActor private static var pausedVideoBookId: String?

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? defaultEnabled
    }

    /// Màn đọc vừa hiện ⇒ đưa truyện lên đầu danh sách. Gọi lại vô hại (cover phủ lên rồi đóng, Chi tiết đẩy vào rồi
    /// quay lại): truyện đã đứng đầu thì không ghi.
    static func recordOpened(bookId: String) {
        guard !bookId.isEmpty else { return }
        let defaults = UserDefaults.standard
        var ids = defaults.stringArray(forKey: recentBookIdsKey) ?? []
        guard ids.first != bookId else { return }
        ids.removeAll { $0 == bookId }
        ids.insert(bookId, at: 0)
        defaults.set(Array(ids.prefix(maxRecentCount)), forKey: recentBookIdsKey)
    }

    /// Các truyện mở gần nhất, mới nhất trước, để Kệ chọn mục mở lại. Chỉ lượt gọi **đầu tiên** của tiến trình có kết quả
    /// (Kệ tạo lại qua `.id` thì không mở lần nữa).
    /// - `nil`: không mở lại — công tắc tắt, lần mở lại trước chết sớm, hoặc còn đổi nguồn dở.
    /// - mảng rỗng: chưa có danh sách (lần đầu sau khi cài bản có tính năng) ⇒ Kệ dự phòng theo Lịch sử đọc.
    @MainActor
    static func takeLaunchCandidates() -> [String]? {
        guard !didTakeLaunchCandidates else { return nil }
        didTakeLaunchCandidates = true
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: legacyOpenBookKey)
        guard isEnabled else { return nil }
        if defaults.object(forKey: pendingAttemptKey) != nil {
            defaults.removeObject(forKey: pendingAttemptKey)
            AppLogger.shared.log("❌ [ReaderRestore] Lần mở lại trước bị tắt trong 10 s đầu ⇒ bỏ qua để tránh vòng lặp crash")
            return nil
        }
        // Đổi nguồn dở: truyện gần nhất có thể sắp bị xoá (lùi lại / dọn truyện cũ) ⇒ không mở.
        if BookSourceChangeJournal.load() != nil {
            AppLogger.shared.log("↩️ [ReaderRestore] Còn lượt đổi nguồn dở ⇒ không mở lại màn đọc")
            return nil
        }
        return defaults.stringArray(forKey: recentBookIdsKey) ?? []
    }

    /// Ngay trước khi Kệ mở lại màn đọc.
    @MainActor
    static func beginRestoreAttempt(bookId: String) {
        UserDefaults.standard.set(bookId, forKey: pendingAttemptKey)
        pausedVideoBookId = bookId
    }

    /// Truyện đang được mở lại (trong 10 s đầu): lượt tự chuyển truyện mất nguồn (`MissingSourceRebindRunner`) coi như
    /// đang mở — dải báo chạy cùng lúc ở trang gốc Kệ, còn màn truyện tranh / phim không đặt `ReaderView.activeBookId`.
    static func isRestoring(bookId: String) -> Bool {
        UserDefaults.standard.string(forKey: pendingAttemptKey) == bookId
    }

    /// Lần mở lại đã qua mốc an toàn (app rời trạng thái active) — gọi lại vô hại.
    static func confirmRestoreSurvived() {
        UserDefaults.standard.removeObject(forKey: pendingAttemptKey)
    }

    /// Hết lượt mở lại (sống đủ 10 s, hoặc người dùng đã kịp mở thứ khác): bỏ cả lệnh dừng sẵn phim — phim mở sau đó
    /// trong phiên này tự phát như thường.
    @MainActor
    static func finishRestoreAttempt() {
        confirmRestoreSurvived()
        pausedVideoBookId = nil
    }

    /// Trình phát hỏi khi item sẵn sàng: `true` (một lần) = phim đang được mở lại lúc khởi động ⇒ dừng sẵn.
    @MainActor
    static func consumePausedVideoStart(bookId: String) -> Bool {
        guard let paused = pausedVideoBookId, paused == bookId else { return false }
        pausedVideoBookId = nil
        return true
    }
}
