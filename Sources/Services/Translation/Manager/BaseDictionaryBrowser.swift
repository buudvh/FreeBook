import Foundation

/// Dữ liệu cho danh sách **từ điển gốc** VietPhrase.dat / Names.dat (thẻ VietPhrase.txt / Name.txt › Sửa —
/// `GlobalBaseDictionaryListView`). Từ điển cỡ triệu mục nên **không** dựng mảng cặp khoá–nghĩa: màn giữ mảng khoá
/// (`keys(of:)`), nghĩa của hàng tra lúc hàng hiện (`baseMeaning`), tìm kiếm duyệt cây một lượt và dừng sớm (`search`).
///
/// "Nghĩa hiệu lực" = từ điển gốc + lớp sửa đổi Chung (`CustomVietPhrase.txt` / `CustomNames.txt`): từ đã sửa lấy nghĩa
/// mới, từ đã xoá (tombstone) ẩn, từ chỉ có ở lớp sửa đổi đứng đầu. Thuần Foundation, chạy được ngoài main thread.
enum BaseDictionaryBrowser {
    /// Trần số kết quả tìm — dòng tổng ghi "500 kết quả đầu".
    static let searchLimit = 500

    /// Cây đã nạp của từ điển gốc (`nil` = chưa có `.dat` / chưa nạp).
    static func loadedDictionary(isName: Bool) -> FrozenTrieDictionary? {
        let manager = TranslationManager.shared
        return (isName ? manager.namesDict : manager.vietPhraseDict)?.frozen()
    }

    /// Mọi khoá của từ điển gốc, theo thứ tự cây (khoá cha trước khoá con). Không giữ nghĩa.
    static func keys(of dictionary: FrozenTrieDictionary) -> [String] {
        dictionary.allKeys()
    }

    /// Nghĩa trong từ điển gốc của **đúng** khoá này (khớp đủ độ dài), `nil` nếu không có.
    static func baseMeaning(of key: String, in dictionary: FrozenTrieDictionary?) -> String? {
        guard let dictionary, !key.isEmpty,
              let match = dictionary.findLongestMatch(text: key, startIndex: 0),
              match.length == key.utf16.count else { return nil }
        return match.value
    }

    struct SearchResult: Sendable {
        let keys: [String]
        /// Chạm trần `searchLimit` — còn kết quả chưa hiện.
        let isCapped: Bool
    }

    /// Tìm theo từ gốc **và** nghĩa hiệu lực (không phân biệt hoa thường ở nghĩa). Lớp sửa đổi trước (theo thứ tự của
    /// nó), rồi duyệt cây gốc — bỏ từ đã xoá và từ đã có ở lớp sửa đổi (nghĩa hiệu lực đã xét ở bước trước). Dừng ở
    /// `searchLimit` kết quả, hoặc khi task bị huỷ (gõ tiếp) — khi đó trả `nil`.
    static func search(
        _ query: String,
        in dictionary: FrozenTrieDictionary?,
        custom: [(key: String, value: String)],
        deleted: Set<String>
    ) -> SearchResult? {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return SearchResult(keys: [], isCapped: false) }
        func matches(_ key: String, _ value: String) -> Bool {
            key.contains(needle) || value.range(of: needle, options: .caseInsensitive) != nil
        }

        var found: [String] = []
        var customKeys = Set<String>()
        for entry in custom {
            customKeys.insert(entry.key)
            guard found.count < searchLimit, matches(entry.key, entry.value) else { continue }
            found.append(entry.key)
        }
        guard found.count < searchLimit else { return SearchResult(keys: found, isCapped: true) }

        var visited = 0
        var cancelled = false
        var capped = false
        dictionary?.walkEntries(decodeValues: true) { key, value in
            visited += 1
            if visited % 4096 == 0, Task.isCancelled {
                cancelled = true
                return false
            }
            guard let value, !deleted.contains(key), !customKeys.contains(key), matches(key, value) else { return true }
            found.append(key)
            if found.count >= searchLimit {
                capped = true
                return false
            }
            return true
        }
        return cancelled ? nil : SearchResult(keys: found, isCapped: capped)
    }
}
