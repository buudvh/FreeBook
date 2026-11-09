import Foundation

/// Đếm lỗi phát của từng đoạn TTS (lỗi giải mã khi đang phát, phát kết thúc không thành công) để quyết định **thử lại một
/// lần / bỏ qua đoạn / dừng đọc** — thay cho cách cũ chỉ hạ cờ `isPlaying`: player hỏng vẫn chạy và bắn lỗi liên tục, nút
/// Dừng không ăn (`pause()` thấy `isPlaying == false` thì thoát), còn dữ liệu hỏng nằm lại trong `preloadedData` nên bấm
/// phát là cùng một câu phát lại từ đầu mãi (log 2026-11-09: ~10 lỗi `'!con'`/giây với Google TTS).
///
/// - Engine remote (Google / tiện ích): đoạn lỗi lần đầu ⇒ `.retry` (tổng hợp lại **một** lần); cùng đoạn lỗi lần hai ⇒
///   `.skip`; bỏ qua liền `maxConsecutiveSkippedParagraphs` đoạn ⇒ `.stop` (lỗi đã thành hệ thống, đọc tiếp chỉ lướt qua
///   cả chương). Một đoạn phát trọn ⇒ `recordSuccess()` đếm lại từ đầu.
/// - NghiTTS: đoạn kế (đang chuẩn bị ở player thứ hai) lỗi ⇒ chỉ tổng hợp lại tối đa **một** lần cho mỗi đoạn
///   (`allowNghiRefill`); lần sau để đoạn đó tự tổng hợp khi tới lượt phát.
///
/// Không gắn actor: chỉ `TTSManager` (`@MainActor`) giữ và gọi.
final class TTSPlaybackFailureTracker {
    enum Decision: Equatable {
        case retry
        case skip
        case stop
    }

    struct ParagraphKey: Hashable {
        let sessionID: UUID
        let chapterIndex: Int
        let paragraphIndex: Int
    }

    static let maxConsecutiveSkippedParagraphs = 3
    /// Giới hạn bộ nhớ của tập đoạn Nghi đã tổng hợp lại (một chương dài vài trăm đoạn, lỗi hiếm).
    private static let maxRememberedNghiRefills = 64

    /// Đoạn remote vừa lỗi lần đầu và đang được tổng hợp lại.
    private var retriedKey: ParagraphKey?
    private var consecutiveSkipped = 0
    private var nghiRefilledKeys = Set<ParagraphKey>()

    func recordRemoteFailure(_ key: ParagraphKey) -> Decision {
        guard retriedKey == key else {
            retriedKey = key
            return .retry
        }
        retriedKey = nil
        consecutiveSkipped += 1
        guard consecutiveSkipped < Self.maxConsecutiveSkippedParagraphs else {
            // Dừng xong thì lượt phát tiếp sau (người dùng bấm phát lại) được đếm lại từ đầu.
            consecutiveSkipped = 0
            return .stop
        }
        return .skip
    }

    /// Một đoạn remote phát trọn.
    func recordSuccess() {
        retriedKey = nil
        consecutiveSkipped = 0
    }

    /// `true` ở lần lỗi đầu của đoạn Nghi `key`; cùng đoạn lỗi lần nữa ⇒ `false` (không tổng hợp lại mãi).
    func allowNghiRefill(_ key: ParagraphKey) -> Bool {
        if nghiRefilledKeys.count >= Self.maxRememberedNghiRefills {
            nghiRefilledKeys.removeAll()
        }
        return nghiRefilledKeys.insert(key).inserted
    }
}
