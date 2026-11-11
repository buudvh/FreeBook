import Foundation
import Observation

/// Trạng thái "đang dịch bằng QT thay thế" theo từng chương (`TranslationFallbackStatus`): tiện ích dịch lỗi ở một số
/// dòng ⇒ dòng có chữ Hán dịch bằng QT, dòng khác giữ chữ gốc. Reader ghi (khi dựng chương), giao diện đọc: dải báo
/// đầu chương, chấm cam trên nút dịch, hàng báo trong popup dịch.
///
/// "Thử lại" ở giao diện gọi `requestRetry` ⇒ xoá cache dịch của truyện + `retryRequest` đổi ⇒ Reader của truyện đó
/// dựng lại chương, TTS đang đọc đúng chương đó đọc lại (`TTSExtensionTranslationObserver`). Chỉ giữ trong RAM, tối đa
/// `maxEntries` chương.
@MainActor
@Observable
final class TranslationFallbackStatusStore {
    static let shared = TranslationFallbackStatusStore()

    struct RetryRequest: Equatable, Sendable {
        let bookId: String
        let chapterIndex: Int
        let id: UUID
    }

    private struct Key: Hashable {
        let bookId: String
        let chapterIndex: Int
    }

    private static let maxEntries = 64

    private var statuses: [Key: TranslationFallbackStatus] = [:]
    private var order: [Key] = []
    private(set) var retryRequest: RetryRequest?

    private init() {}

    func status(bookId: String, chapterIndex: Int) -> TranslationFallbackStatus? {
        statuses[Key(bookId: bookId, chapterIndex: chapterIndex)]
    }

    /// `nil` = chương dịch đủ bằng tiện ích (hoặc không dùng tiện ích) ⇒ xoá báo.
    func record(_ status: TranslationFallbackStatus?, bookId: String, chapterIndex: Int) {
        let key = Key(bookId: bookId, chapterIndex: chapterIndex)
        guard statuses[key] != status else { return }
        order.removeAll { $0 == key }
        guard let status else {
            statuses[key] = nil
            return
        }
        statuses[key] = status
        order.append(key)
        while order.count > Self.maxEntries {
            statuses[order.removeFirst()] = nil
        }
    }

    /// Xoá mọi báo của một truyện (đổi bộ dịch, tắt dịch).
    func clear(bookId: String) {
        let keys = statuses.keys.filter { $0.bookId == bookId }
        guard !keys.isEmpty else { return }
        for key in keys { statuses[key] = nil }
        order.removeAll { $0.bookId == bookId }
    }

    /// Xin Reader (và TTS đang đọc chương đó) dựng lại chương. Cache theo dòng nhớ cả lỗi gần đây nên phải xoá cache của
    /// truyện **ngay tại đây**, đồng bộ, trước khi bên nào nghe `retryRequest` kịp dịch lại — xoá ở từng bên nghe thì bên
    /// chạy trước có thể vẫn trúng lỗi cũ (lùi QT) trong khi bên sau gọi được tiện ích ⇒ Reader và TTS ra hai chữ khác.
    func requestRetry(bookId: String, chapterIndex: Int) {
        TranslationExtensionLineCache.shared.invalidate(bookId: bookId)
        retryRequest = RetryRequest(bookId: bookId, chapterIndex: chapterIndex, id: UUID())
    }
}
