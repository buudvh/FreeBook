import Foundation

/// Mở lại màn đọc lúc khởi động (1.3.716 — Cài đặt › Đọc & Nghe › Mở lại truyện đang đọc).
///
/// Một **dấu** (`bookId`) trong `UserDefaults` ghi mỗi khi màn đọc hiện (`BookContentDestination`, đủ cả chữ, truyện
/// tranh, phim) và chỉ xoá khi màn đọc **thật sự đóng** (`onDismiss` của nơi mở cover — không dùng `onDisappear`: Chi
/// tiết đẩy vào hay màn AI phủ lên cũng làm màn đọc biến mất). Tắt app lúc dấu còn ⇒ lần mở sau Kệ mở lại truyện đó như
/// khi bấm trên Kệ (chương + vị trí đã lưu), xem `ShelfView+LaunchRestore`.
///
/// Chống vòng lặp crash: ngay trước khi mở lại, bật cờ "đang thử"; cờ xoá khi màn sống đủ 10 s, khi app rời trạng thái
/// active, hoặc khi người dùng đóng màn đọc. Mở app mà cờ còn ⇒ lần mở lại trước chết sớm ⇒ lần này bỏ qua.
/// `UserDefaults` gửi giá trị sang tiến trình `cfprefsd` ngay khi `set`, nên app crash vẫn giữ được cờ.
enum ReaderSessionRestoreStore {
    /// Khoá công tắc ở Cài đặt (không dấu chấm). `@AppStorage` không ghi giá trị mặc định xuống đĩa ⇒ mọi chỗ ngoài View
    /// đọc qua `isEnabled` (khoá chưa ghi = bật).
    static let enabledKey = "restoreReaderOnLaunch"
    static let defaultEnabled = true
    /// `bookId` của màn đọc đang mở. Còn lúc mở app = lần trước app bị tắt khi đang ở màn đọc.
    private static let openBookKey = "readerSessionOpenBookId"
    /// Đang thử mở lại mà chưa qua mốc an toàn.
    private static let pendingAttemptKey = "readerSessionRestorePending"
    /// Màn đọc mở lại sống được chừng này thì không còn coi là vòng lặp crash.
    static let survivalDelayNanoseconds: UInt64 = 10_000_000_000

    @MainActor private static var didTakeLaunchCandidate = false
    /// Phim đang được mở lại: trình phát dừng sẵn ở giây đã lưu thay vì tự phát (`consumePausedVideoStart`).
    @MainActor private static var pausedVideoBookId: String?

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? defaultEnabled
    }

    /// Truyện đang mang dấu — `HistoryOrphanBookSweeper` không được xoá nó (đang đọc hoặc sắp được mở lại).
    static var markedBookId: String? {
        guard let bookId = UserDefaults.standard.string(forKey: openBookKey), !bookId.isEmpty else { return nil }
        return bookId
    }

    /// Màn đọc vừa hiện (gọi lại vô hại: cover phủ lên rồi đóng, Chi tiết đẩy vào rồi quay lại).
    static func markOpened(bookId: String) {
        guard !bookId.isEmpty, markedBookId != bookId else { return }
        UserDefaults.standard.set(bookId, forKey: openBookKey)
    }

    /// Màn đọc đã đóng hẳn (hoặc quyết định không mở lại): bỏ dấu, cờ đang thử và lệnh dừng sẵn phim.
    @MainActor
    static func markClosed() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: openBookKey)
        defaults.removeObject(forKey: pendingAttemptKey)
        pausedVideoBookId = nil
    }

    /// Truyện cần mở lại lúc khởi động. Chỉ lượt gọi **đầu tiên** của tiến trình có kết quả (Kệ tạo lại qua `.id` thì
    /// không mở lần nữa). Kệ còn tự kiểm truyện còn trên máy và không phải 18+.
    @MainActor
    static func takeLaunchCandidate() -> String? {
        guard !didTakeLaunchCandidate else { return nil }
        didTakeLaunchCandidate = true
        guard let bookId = markedBookId else { return nil }
        guard isEnabled else {
            markClosed()
            return nil
        }
        if UserDefaults.standard.bool(forKey: pendingAttemptKey) {
            AppLogger.shared.log("❌ [ReaderRestore] Lần mở lại trước bị tắt trong 10 s đầu ⇒ bỏ qua để tránh vòng lặp crash")
            markClosed()
            return nil
        }
        // Đổi nguồn dở: truyện mang dấu có thể sắp bị xoá (lùi lại / dọn truyện cũ) ⇒ không mở.
        if BookSourceChangeJournal.load() != nil {
            AppLogger.shared.log("↩️ [ReaderRestore] Còn lượt đổi nguồn dở ⇒ không mở lại màn đọc")
            markClosed()
            return nil
        }
        return bookId
    }

    /// Ngay trước khi Kệ mở lại màn đọc.
    @MainActor
    static func beginRestoreAttempt(bookId: String) {
        UserDefaults.standard.set(true, forKey: pendingAttemptKey)
        pausedVideoBookId = bookId
    }

    /// Lần mở lại đã qua mốc an toàn (sống đủ 10 s, hoặc app rời trạng thái active) — gọi lại vô hại.
    static func confirmRestoreSurvived() {
        UserDefaults.standard.removeObject(forKey: pendingAttemptKey)
    }

    /// Trình phát hỏi khi item sẵn sàng: `true` (một lần) = phim đang được mở lại lúc khởi động ⇒ dừng sẵn.
    @MainActor
    static func consumePausedVideoStart(bookId: String) -> Bool {
        guard let paused = pausedVideoBookId, paused == bookId else { return false }
        pausedVideoBookId = nil
        return true
    }
}
