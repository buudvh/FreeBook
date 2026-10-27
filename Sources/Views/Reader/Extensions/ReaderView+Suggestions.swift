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
    ///
    /// Badge phạm vi: nghĩa có trong **bất kỳ** nguồn Names/VietPhrase "(Riêng)" nào ⇒ `R`; không có mà có trong nguồn
    /// "(Chung)" ⇒ `C`; còn lại không badge. Nghĩa trùng giữ category (màu viền) của lần xuất hiện đầu, chỉ nâng badge.
    nonisolated static func suggestionChips(from matches: [DictionaryMatchInfo]) -> [SuggestionChip] {
        var chips: [SuggestionChip] = []
        for match in matches {
            let category = suggestionCategory(forSource: match.source)
            let scope = suggestionScope(forSource: match.source)
            let translation = category == .hanViet ? match.translation.lowercased() : match.translation
            for part in translation.replacingOccurrences(of: "¦", with: "/").components(separatedBy: "/") {
                let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                if let index = chips.firstIndex(where: { $0.text == trimmed }) {
                    chips[index].scope = strongerScope(chips[index].scope, scope)
                    continue
                }
                chips.append(SuggestionChip(text: trimmed, category: category, scope: scope))
            }
        }
        return chips
    }

    /// Phạm vi suy từ **hậu tố nhãn nguồn** "(Riêng)" / "(Chung)" khai ở `dictionaryMatches(for:bookId:)`
    /// (`ReaderView+Selection`). Đổi nhãn ở đó là badge R/C mất im lặng — sửa cả hai chỗ. Chỉ nguồn Names và
    /// VietPhrase có phạm vi; Xưng hô, Luật nhân, Phiên âm trả `nil`.
    private nonisolated static func suggestionScope(forSource source: String) -> SuggestionChip.Scope? {
        guard source.hasPrefix("Names") || source.hasPrefix("VietPhrase") else { return nil }
        if source.hasSuffix("(Riêng)") { return .book }
        if source.hasSuffix("(Chung)") { return .global }
        return nil
    }

    /// Riêng thắng Chung, Chung thắng không badge.
    private nonisolated static func strongerScope(
        _ lhs: SuggestionChip.Scope?,
        _ rhs: SuggestionChip.Scope?
    ) -> SuggestionChip.Scope? {
        if lhs == .book || rhs == .book { return .book }
        if lhs == .global || rhs == .global { return .global }
        return nil
    }

    /// Màu chip theo nhãn nguồn — nhãn khai ở `dictionaryMatches(for:bookId:)` (`ReaderView+Selection`):
    /// "Names (…)" viền đỏ, "Phiên âm" viền xám, còn lại (VietPhrase, Xưng hô, Luật nhân) viền xanh.
    private nonisolated static func suggestionCategory(forSource source: String) -> SuggestionChipCategory {
        if source.hasPrefix("Names") { return .name }
        if source == "Phiên âm" { return .hanViet }
        return .vietPhrase
    }
}
