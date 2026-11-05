import SwiftUI

/// Gợi ý nghĩa (chip) cho từ đang chọn ở màn Dịch của Reader.
///
/// Trước đây danh sách này là **computed property** của `ReaderView`, nên ~6 lần `findLongestMatch` cộng một lần
/// tra Hán-Việt chạy lại **mỗi lần body được evaluate** — tức mỗi ký tự người dùng gõ vào ô nghĩa, ngay trên
/// MainActor. Giờ nó là `@State` và chỉ được tính lại đúng hai thời điểm dữ liệu nguồn có thể đổi:
/// khi từ đang chọn đổi (`updateEditorFromSelection`) và khi định nghĩa của chính từ đó bị sửa/xoá.
///
/// Chip dựng **thẳng từ `dictionaryMatches`** — đúng danh sách màn quản lý định nghĩa (⚙) đang hiện — nên màn đó
/// có nghĩa nào thì thanh chip có nghĩa đó. Trước 1.3.601 hàm này tự tra lại từ điển và bỏ cả mục VietPhrase chung
/// khi nghĩa dài ≥ 100 ký tự.
///
/// Từ 1.3.721 thanh chip chỉ lấy đúng các mục màn quản lý hiện (Name/VP Riêng/Chung, rồi Phiên âm), theo **thứ tự
/// của màn đó**. Trước đó chip còn có Xưng hô / Luật nhân đứng trước VP (kể cả khi công tắc dịch của chúng đang tắt):
/// nghĩa Xưng hô chen lên đầu hàng, rồi nghĩa VP trùng chữ gộp vào và nâng nó lên badge C ⇒ trông như VP Chung xếp
/// nghĩa đó đầu tiên, còn nghĩa chỉ có ở Xưng hô thì nằm giữa hàng mà không có badge.
extension ReaderView {
    /// Tính lại chip cho `rawWord` và ghi vào `@State suggestionChips`.
    func refreshSuggestionChips(for rawWord: String) {
        suggestionChips = Self.buildSuggestionChips(for: rawWord, bookId: bookId)
    }

    nonisolated static func buildSuggestionChips(for rawWord: String, bookId: String?) -> [SuggestionChip] {
        let word = rawWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return [] }
        return suggestionChips(from: dictionaryMatches(for: word, bookId: bookId))
    }

    /// Nguồn được lên chip, theo đúng thứ tự mục của màn Quản lý nghĩa (`ManageDefinitionsView`): bốn mục sửa được
    /// (`ManageDefinitionsDraft.editableSources`) rồi Phiên âm ở cuối. Xưng hô / Luật nhân không lên chip.
    /// Nhãn là hợp đồng với `dictionaryMatches(for:bookId:)` (`ReaderView+Selection`) — đổi nhãn ở đó là chip mất im
    /// lặng, sửa cả hai chỗ.
    private nonisolated static let chipSourceOrder = ManageDefinitionsDraft.editableSources + ["Phiên âm"]

    /// Mỗi nguồn tách theo `/` (và `¦`) thành chip, bỏ nghĩa trùng. Thứ tự theo `chipSourceOrder` chứ **không** theo
    /// thứ tự của `matches` (màn quản lý nối nguồn mới thêm vào cuối danh sách — `mergedMatches`); trong một nguồn,
    /// nghĩa giữ đúng thứ tự đang lưu.
    ///
    /// Badge phạm vi: nghĩa có trong **bất kỳ** nguồn Names/VietPhrase "(Riêng)" nào ⇒ `R`; không có mà có trong nguồn
    /// "(Chung)" ⇒ `C`; Phiên âm không badge. Nghĩa trùng giữ vị trí + category (màu viền) của lần xuất hiện đầu, chỉ
    /// nâng badge.
    nonisolated static func suggestionChips(from matches: [DictionaryMatchInfo]) -> [SuggestionChip] {
        var chips: [SuggestionChip] = []
        let ordered = chipSourceOrder.flatMap { source in matches.filter { $0.source == source } }
        for match in ordered {
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
    /// VietPhrase có phạm vi; Phiên âm trả `nil`.
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
    /// "Names (…)" viền đỏ, "Phiên âm" viền xám, VietPhrase viền xanh.
    private nonisolated static func suggestionCategory(forSource source: String) -> SuggestionChipCategory {
        if source.hasPrefix("Names") { return .name }
        if source == "Phiên âm" { return .hanViet }
        return .vietPhrase
    }
}
