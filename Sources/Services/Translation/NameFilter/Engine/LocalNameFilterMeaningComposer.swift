import Foundation

/// Ghép nghĩa cho **một name lẻ** ngoài lượt lọc — đúng `LocalNameFilterMeaningBuilder` của bộ lọc (đường hàng phía LAC:
/// cả từ trong từ điển ⇒ phủ trọn cả từ ⇒ phần riêng + nghĩa đuôi dài nhất của danh sách người dùng ⇒ phần tên riêng).
/// Dùng cho gói tạm tự cập nhật theo danh sách đuôi (`LocalNameFilterDraftRefresher`, plan
/// 2026-11-27-nghia-ten-tay-huyen mục 6).
///
/// Chỉ name **không phải người, không phải họ tộc** (`canRecompose`): nghĩa người cần danh xưng / họ của cả lượt lọc, họ
/// tộc có cách ghép riêng — giữ nguyên nghĩa lúc lọc. Hàng bộ luật địa danh / tổ chức lúc lọc lấy đúng đuôi đã dò; ghép
/// lại ở đây lấy đuôi dài nhất của danh sách — khác nhau chỉ khi danh sách có đuôi dài hơn khớp cuối name.
///
/// Chụp từ điển của truyện một lần lúc tạo (`LocalNameFilterDictionaries.capture`), nhớ kết quả như bộ lọc. **Không khoá**:
/// dùng trên một task.
final class LocalNameFilterMeaningComposer {
    private let builder: LocalNameFilterMeaningBuilder

    /// `nil` ⇒ VietPhrase chưa nạp (không ghép được). `latinModel` khác `nil` ⇒ như bật "Ưu tiên tên Latin" có mô hình.
    init?(bookId: String, suffixes: [LocalNameFilter.Suffix], latinModel: LocalNameFilterLatinModel?) {
        guard let dictionaries = LocalNameFilterDictionaries.capture(bookId: bookId) else { return nil }
        let configuration = LocalNameFilter.Configuration(
            minCount: 1,
            suffixes: suffixes,
            blockedTerms: [],
            prefersLatinNames: latinModel != nil
        )
        let setup = LocalNameFilterSetup(configuration: configuration, dictionaries: dictionaries, rulesV3: true)
        builder = LocalNameFilterMeaningBuilder(
            setup: setup,
            dictionaries: dictionaries,
            properNames: LocalNameFilterProperNames(dictionaries: dictionaries, latinModel: latinModel)
        )
    }

    /// Loại ghép lại được: địa danh, tổ chức (không phải họ tộc), thuật ngữ.
    static func canRecompose(_ kind: LocalNameFilter.Kind) -> Bool {
        switch kind {
        case .place, .sect, .term: return true
        case .person, .family: return false
        }
    }

    /// Nghĩa máy ghép của `term` (chữ Hán) loại `kind`; loại không ghép lại được hoặc chữ rỗng ⇒ `nil`.
    func meaning(term: String, kind: LocalNameFilter.Kind) -> (meaning: String, isGuessed: Bool)? {
        let word = LocalNameFilterWord(term.trimmingCharacters(in: .whitespacesAndNewlines))
        guard Self.canRecompose(kind), !word.isEmpty else { return nil }
        let built = builder.meaning(word: word, kind: kind, titles: [])
        return (built.meaning, built.isGuessed)
    }
}
