import Foundation

/// Memo cho `VietPhraseTokenizer.tokenize`.
///
/// Vì sao cần: một lần dựng lại chương tokenize **mỗi dòng hai lần** — một lần ở
/// `TranslateUtils.translateContent`, một lần nữa ở `getTranslationTokens` khi dựng span. Chương ~200
/// dòng ⇒ ~400 lượt, mà mỗi lượt là O(số ký tự × số từ điển): tokenizer quét **từng vị trí** và tra
/// tới 5 trie tên riêng rồi tới 3 trie VietPhrase. Trước 1.3.339 không có tầng nào ghi nhớ kết quả,
/// nên mỗi lần sửa một mục VP hoặc một rule trong Reader đều trả lại toàn bộ chi phí đó.
///
/// Khoá gồm `generation` của `TranslateUtils.translationGenerationToken(for:)` nên **không cần** ai
/// gọi `clear()`: sửa từ điển/rule là đổi generation ⇒ khoá khác ⇒ entry cũ tự rụng khỏi `NSCache`.
/// `clear()` chỉ để dùng khi muốn thu hồi bộ nhớ ngay.
///
/// `NSCache` an toàn đa luồng — bắt buộc, vì `tokenize` chạy off-main trong
/// `performChapterTranslationOffMainActor`.
final class TokenizeMemo {
    static let shared = TokenizeMemo()

    private let cache = TranslationMemo<[String]>(maxEntries: 512, maxCost: 4 * 1024 * 1024)
    private init() {}

    /// `compute` chỉ chạy khi chưa có trong memo.
    ///
    /// Hai cờ đại từ / luật nhân hoá vào khoá tường minh dù `generation` thường đã phủ chúng: chúng
    /// được đọc thẳng từ `UserDefaults` trong tokenizer, nên nếu có đường nào đổi cờ mà không bump
    /// generation thì khoá vẫn đúng.
    func tokens(
        text: String,
        bookId: String?,
        isPronounsEnabled: Bool,
        isLuatNhanEnabled: Bool,
        generation: Int,
        compute: () -> [String]
    ) -> [String] {
        guard !text.isEmpty else { return [] }

        let key = "\(generation)|\(bookId ?? "global")|\(isPronounsEnabled ? 1 : 0)\(isLuatNhanEnabled ? 1 : 0)|\(text.md5())"
        let lookup = cache.lookup(key)
        if let hit = lookup.value { return hit }
        let value = compute()
        if !Task.isCancelled, generation == TranslateUtils.translationGenerationToken(for: bookId) {
            cache.insert(value, key: key, bookId: bookId,
                         cost: value.reduce(0) { $0 + $1.utf16.count * 2 + 32 }, ticket: lookup.ticket)
        }
        return value
    }

    func clear(bookId: String? = nil) {
        cache.invalidate(bookId: bookId)
    }
}
