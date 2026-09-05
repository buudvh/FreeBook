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

    /// `NSCache` chỉ giữ được kiểu class nên phải bọc mảng token.
    private final class Entry {
        let tokens: [String]
        init(_ tokens: [String]) { self.tokens = tokens }
    }

    private let cache: NSCache<NSString, Entry>

    private init() {
        cache = NSCache<NSString, Entry>()
        // Một chương dài cỡ 200–300 dòng; giữ rộng hơn một chương để lượt dựng span dùng lại được
        // kết quả của lượt dịch, nhưng không giữ vô hạn.
        cache.countLimit = 512
    }

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

        let key = "\(generation)|\(bookId ?? "global")|\(isPronounsEnabled ? 1 : 0)\(isLuatNhanEnabled ? 1 : 0)|\(text.md5())" as NSString
        if let hit = cache.object(forKey: key) {
            return hit.tokens
        }

        let value = compute()
        cache.setObject(Entry(value), forKey: key)
        return value
    }

    func clear() {
        cache.removeAllObjects()
    }
}
