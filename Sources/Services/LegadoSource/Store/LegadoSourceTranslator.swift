import Foundation

/// Dịch QT (VietPhrase) tên nguồn và tên nhóm — chạy **ngoài main**.
///
/// `TranslateUtils.translateMeta` gọi được từ thread nền: từ điển nằm sau lock (`TranslationDictionaryState`) và
/// app đã dịch ngoài main ở chỗ khác (`BookTitleTranslationBackfill`, cầu `Qt` của `JSExecutor`). Hàm này chỉ dịch
/// mỗi chuỗi **một lần** (bỏ trùng), caller giữ bảng kết quả làm cache.
///
/// Tác dụng phụ đã biết: `translateMeta` ghi vào memo dùng chung 1024 mục của tên/meta, nên dịch ~1.400 tên có thể
/// đẩy bản dịch tên truyện trên kệ ra khỏi memo (chỉ tốn dịch lại, không sai kết quả).
enum LegadoSourceTranslator {
    /// Bảng `gốc → dịch`; chuỗi không có chữ Hán giữ nguyên. `nil` khi từ điển chưa nạp (caller thử lại sau).
    static func translate(_ texts: [String]) -> [String: String]? {
        guard TranslationManager.shared.vietPhraseDict != nil else { return nil }
        var memo: [String: String] = [:]
        memo.reserveCapacity(texts.count)
        for text in texts where memo[text] == nil {
            if Task.isCancelled { return nil }
            guard TranslateUtils.containsChinese(text) else {
                memo[text] = text
                continue
            }
            let translated = TranslateUtils.translateMeta(text).trimmingCharacters(in: .whitespacesAndNewlines)
            memo[text] = translated.isEmpty ? text : translated
        }
        return memo
    }
}
