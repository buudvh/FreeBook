import Foundation

/// Các phép tra của màn Sửa từ VP/Name (`DictEntryEditSheet`). Hàm thuần, không gắn actor — màn gọi trong
/// `Task.detached` (tra trie + tách token không chạy trên main), cùng kiểu `BrowserDictionaryLookup`.
///
/// Dùng **đúng** các API mà panel Dịch của Reader dùng (`ReaderDefinitionWorker`), để hai màn luôn ra cùng kết quả:
/// - token của từ gốc: `TranslateUtils.getTranslationTokens(for:bookId:)`;
/// - nghĩa gợi ý của cụm đang chọn: `TranslateUtils.translateTerm(_:bookId:)`;
/// - chip nghĩa: `ReaderView.dictionaryMatches(for:bookId:)` + `ReaderView.suggestionChips(from:)` — đúng thân của
///   `ReaderView.buildSuggestionChips(for:bookId:)`, chỉ giữ lại `matches` để mở màn quản lý nghĩa (⚙) mà không tra lại.
enum DictEntryEditLookup {
    struct Selection: Sendable {
        let matches: [DictionaryMatchInfo]
        let chips: [SuggestionChip]
        /// `nil` khi không cần tra nghĩa: vùng chọn là cả từ gốc, hoặc cụm đã có sẵn trong danh sách.
        let meaning: String?
    }

    /// Token của từ gốc. `bookId` = truyện của danh sách Riêng; danh sách Chung truyền `nil` (chỉ từ điển chung).
    static func tokens(for key: String, bookId: String?) -> [TranslationWordToken] {
        guard !key.isEmpty else { return [] }
        return TranslateUtils.getTranslationTokens(for: key, bookId: bookId)
    }

    /// Chip (và `matches` cho màn ⚙) tra theo `chipBookId` — như sheet Sửa từ cũ: danh sách Riêng ⇒ chính truyện đó,
    /// danh sách Chung ⇒ truyện đang mở màn Từ điển. Nghĩa gợi ý tra theo phạm vi của danh sách (`meaningBookId`), vì
    /// mục mới sẽ được lưu vào đúng phạm vi đó.
    static func selection(
        word: String,
        meaningBookId: String?,
        chipBookId: String?,
        needsMeaning: Bool
    ) -> Selection {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Selection(matches: [], chips: [], meaning: needsMeaning ? "" : nil)
        }
        let matches = ReaderView.dictionaryMatches(for: trimmed, bookId: chipBookId)
        let meaning = needsMeaning ? TranslateUtils.translateTerm(trimmed, bookId: meaningBookId) : nil
        return Selection(matches: matches, chips: ReaderView.suggestionChips(from: matches), meaning: meaning)
    }

    /// URL tra cứu nhanh — chép đúng luật của `ReaderView.performQuickLookup(using:query:)`: thay `%s`, mã hoá
    /// `.urlQueryAllowed`, chỉ nhận http/https. `nil` = không mở gì.
    static func lookupURLString(engine: SearchEngine, query: String) -> String? {
        let word = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return nil }
        let rawUrl = engine.urlTemplate.replacingOccurrences(of: "%s", with: word)
        guard let encoded = rawUrl.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: encoded),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        return url.absoluteString
    }
}
