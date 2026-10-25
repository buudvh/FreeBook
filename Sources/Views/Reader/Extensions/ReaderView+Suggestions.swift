import SwiftUI

/// Gợi ý nghĩa (chip) cho từ đang chọn ở màn Dịch của Reader.
///
/// Trước đây danh sách này là **computed property** của `ReaderView`, nên ~6 lần `findLongestMatch` cộng một lần
/// tra Hán-Việt chạy lại **mỗi lần body được evaluate** — tức mỗi ký tự người dùng gõ vào ô nghĩa, ngay trên
/// MainActor. Giờ nó là `@State` và chỉ được tính lại đúng hai thời điểm dữ liệu nguồn có thể đổi:
/// khi từ đang chọn đổi (`updateEditorFromSelection`) và khi định nghĩa của chính từ đó bị sửa/xoá.
///
/// Chip dựng **thẳng từ `dictionaryMatches`** — đúng danh sách màn quản lý định nghĩa (⚙) đang hiện — nên màn đó
/// có nghĩa nào thì thanh chip có nghĩa đó. Trước 1.3.601 hàm này tự tra lại từ điển và lệch hai chỗ: bỏ cả mục
/// VietPhrase chung khi nghĩa dài ≥ 100 ký tự, và không tra Xưng hô / Luật nhân ⇒ thanh chỉ còn chip Hán-Việt
/// trong khi hàng token và màn quản lý vẫn có nghĩa.
extension ReaderView {
    /// Tính lại chip cho `rawWord` và ghi vào `@State suggestionChips`.
    func refreshSuggestionChips(for rawWord: String) {
        suggestionChips = Self.buildSuggestionChips(for: rawWord, bookId: bookId)
    }

    nonisolated static func buildSuggestionChips(for rawWord: String, bookId: String) -> [SuggestionChip] {
        let word = rawWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return [] }
        return suggestionChips(from: dictionaryMatches(for: word, bookId: bookId))
    }

    /// Mỗi nguồn tách theo `/` (và `¦`) thành chip, bỏ nghĩa trùng; thứ tự giữ đúng thứ tự nguồn của
    /// `dictionaryMatches` (Names → Xưng hô → Luật nhân → VietPhrase → Phiên âm).
    nonisolated static func suggestionChips(from matches: [DictionaryMatchInfo]) -> [SuggestionChip] {
        var chips: [SuggestionChip] = []
        for match in matches {
            let category = suggestionCategory(forSource: match.source)
            let translation = category == .hanViet ? match.translation.lowercased() : match.translation
            for part in translation.replacingOccurrences(of: "¦", with: "/").components(separatedBy: "/") {
                let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, !chips.contains(where: { $0.text == trimmed }) else { continue }
                chips.append(SuggestionChip(text: trimmed, category: category))
            }
        }
        return chips
    }

    /// Màu chip theo nhãn nguồn — nhãn khai ở `dictionaryMatches(for:bookId:)` (`ReaderView+Selection`):
    /// "Names (…)" viền đỏ, "Phiên âm" viền xám, còn lại (VietPhrase, Xưng hô, Luật nhân) viền xanh.
    private nonisolated static func suggestionCategory(forSource source: String) -> SuggestionChipCategory {
        if source.hasPrefix("Names") { return .name }
        if source == "Phiên âm" { return .hanViet }
        return .vietPhrase
    }
}
