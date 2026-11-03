import Foundation

// Cache tĩnh cho đường nóng `translateContentWithMapping` của `TranslateUtils`. Tách file riêng vì
// `TranslateUtils.swift` đã chạm baseline dòng: ở đó chỉ thay dòng tại chỗ để gọi vào đây.
// (Bốn regex tên chương từng nằm ở đây đã bỏ ở 1.3.681: tên chương dịch y như nội dung.)
extension TranslateUtils {

    // MARK: - Memo kết quả `translateContentWithMapping`

    /// Reader và TTS dựng **cùng** một chương với cùng input từng dòng; text đã có `translationCache` nhưng
    /// span thì lần nào cũng tính lại (tra trie + hậu xử lý + dò range cho từng token). Memo này giữ nguyên
    /// `TranslatedTextResult` (kể cả `spans` rỗng — vẫn là kết quả xác định của cùng input).
    ///
    /// Khoá có `cacheGeneration` nên không cần ai gọi `invalidate`: sửa từ điển/rule/cài đặt là đổi
    /// generation ⇒ khoá khác ⇒ entry cũ chỉ còn chờ bị LRU đẩy ra (giống `TokenizeMemo`).
    static let mappingResultCache = TranslationMemo<TranslatedTextResult>(maxEntries: 1024, maxCost: 8 * 1024 * 1024)

    /// Tra memo **trước** `withSnapshot` (luật 30), chỉ chạy `compute` khi miss. Chỉ lưu khi task chưa huỷ
    /// (`getTranslationTokens` trả `[]` lúc huỷ), từ điển VietPhrase đã nạp, và generation vẫn khớp — cùng
    /// điều kiện + ticket như `translateText`.
    static func mappingMemo(
        _ original: String,
        bookId: String?,
        convert: Bool,
        compute: () -> TranslatedTextResult
    ) -> TranslatedTextResult {
        guard !original.isEmpty else { return compute() }

        // Hai cờ đọc đúng nguồn mà `compute` sẽ thấy: snapshot đang mở cho cùng `bookId` (được `withSnapshot`
        // dùng lại), không thì `UserDefaults` (thứ `capture` sẽ đọc).
        let context = TranslationReadContext.current.flatMap { $0.bookId == bookId ? $0 : nil }
        let isPronounsEnabled = context?.pronounsEnabled ?? UserDefaults.standard.bool(forKey: "isTranslationPronounsEnabled")
        let isLuatNhanEnabled = context?.luatNhanEnabled ?? UserDefaults.standard.bool(forKey: "isTranslationLuatNhanEnabled")
        let generation = TranslationReadContext.cacheGeneration(for: bookId)
        // Cờ bộ rule tên chương: đường này là nội dung nên cờ luôn tắt, nhưng có trong khoá thì không bao giờ lẫn kết quả.
        let titleRules = TranslationReadContext.appliesChapterTitleRules ? 1 : 0
        let key = "\(generation)|\(bookId ?? "global")|\(convert ? 1 : 0)|\(isPronounsEnabled ? 1 : 0)\(isLuatNhanEnabled ? 1 : 0)\(titleRules)|\(original.md5())"
        let lookup = mappingResultCache.lookup(key)
        if let cached = lookup.value { return cached }

        let result = compute()
        if !Task.isCancelled,
           TranslationManager.shared.vietPhraseDict != nil,
           generation == translationGenerationToken(for: bookId) {
            mappingResultCache.insert(result, key: key, bookId: bookId,
                                      cost: result.text.utf16.count * 2 + result.spans.count * 32,
                                      ticket: lookup.ticket)
        }
        return result
    }
}
