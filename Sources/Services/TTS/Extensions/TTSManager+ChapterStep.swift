import Foundation

/// Nút **chương trước / chương kế** của sheet điều khiển nhanh TTS (anh Bửu duyệt mockup 2026-11-11): nhảy tới chương liền
/// trước / liền sau trong `chaptersQueue` rồi đọc từ đầu chương qua `jumpToChapter(at:)` (toast "Đang chuyển sang …", như
/// chọn chương ở mục lục của sheet Hẹn giờ).
///
/// Chỉ số chương có thể thưa ⇒ tra theo `index`, không theo vị trí mảng — cùng luật `nextChapterIndex(after:)` của lượt tự
/// sang chương. Lúc vừa bắt đầu đọc từ Reader, hàng đợi chỉ có vài chương từ chương đang đọc trở đi cho tới khi
/// `refreshChaptersQueueInBackground` nạp đủ (~1 s) ⇒ trong lúc đó không có "chương trước".
extension TTSManager {
    /// Chỉ số chương liền trước `index` trong hàng đợi; `nil` ⇒ không có.
    func previousChapterIndex(before index: Int) -> Int? {
        chaptersQueue
            .map(\.index)
            .filter { $0 < index }
            .max()
    }

    /// `forward == true` ⇒ chương kế, ngược lại chương trước. Không có chương đó trong hàng đợi ⇒ không làm gì.
    public func jumpToAdjacentChapter(forward: Bool) {
        let current = playingChapterIndex
        guard !playingBookId.isEmpty, current >= 0 else { return }
        let target = forward ? nextChapterIndex(after: current) : previousChapterIndex(before: current)
        guard let target else { return }
        AppLogger.shared.log("[TTSManager] Sheet điều khiển nhanh: sang chương \(forward ? "kế" : "trước") (\(current) → \(target))")
        jumpToChapter(at: target)
    }
}
