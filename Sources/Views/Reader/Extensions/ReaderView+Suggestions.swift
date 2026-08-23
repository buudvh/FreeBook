import SwiftUI

/// Gợi ý nghĩa (chip) cho từ đang chọn ở màn Dịch của Reader.
///
/// Trước đây danh sách này là **computed property** của `ReaderView`, nên ~6 lần `findLongestMatch` cộng một lần
/// tra Hán-Việt chạy lại **mỗi lần body được evaluate** — tức mỗi ký tự người dùng gõ vào ô nghĩa, ngay trên
/// MainActor. Giờ nó là `@State` và chỉ được tính lại đúng hai thời điểm dữ liệu nguồn có thể đổi:
/// khi từ đang chọn đổi (`updateEditorFromSelection`) và khi định nghĩa của chính từ đó bị sửa/xoá.
extension ReaderView {
    /// Tính lại chip cho `rawWord` và ghi vào `@State suggestionChips`.
    func refreshSuggestionChips(for rawWord: String) {
        suggestionChips = Self.buildSuggestionChips(for: rawWord, bookId: bookId)
    }

    /// Thứ tự ưu tiên giữ **y nguyên** bản computed property cũ: Names riêng → Names custom → Names chung →
    /// VietPhrase riêng → VietPhrase custom → VietPhrase chung → phiên âm Hán-Việt.
    static func buildSuggestionChips(for rawWord: String, bookId: String) -> [SuggestionChip] {
        var chips: [SuggestionChip] = []
        let word = rawWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return [] }

        let manager = TranslationManager.shared
        let bookDicts = manager.getBookDictionaries(for: bookId)

        func addTranslation(_ translation: String, category: SuggestionChipCategory) {
            let clean = translation.replacingOccurrences(of: "¦", with: "/")
            let parts = clean.components(separatedBy: "/")
            for part in parts {
                let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    let isDuplicate = chips.contains { existing in
                        existing.text == trimmed
                    }
                    if !isDuplicate {
                        chips.append(SuggestionChip(text: trimmed, category: category))
                    }
                }
            }
        }

        // 1. Book Names
        if let bookNames = bookDicts.names,
           let match = bookNames.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            addTranslation(match.value, category: .name)
        }

        // 1.1 Custom Names (custom.dat)
        var hasCustomName = false
        if let customNames = manager.customNamesDict,
           let match = customNames.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            addTranslation(match.value, category: .name)
            hasCustomName = true
        }

        // 2. Global Names (Names.dat)
        if !hasCustomName,
           !manager.deletedNames.contains(word),
           let names = manager.namesDict,
           let match = names.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            addTranslation(match.value, category: .name)
        }

        // 3. Book VietPhrase
        if let bookVP = bookDicts.vietPhrase,
           let match = bookVP.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            addTranslation(match.value, category: .vietPhrase)
        }

        // 3.1 Custom VietPhrase (custom.dat)
        var hasCustomVP = false
        if let customVP = manager.customVietPhraseDict,
           let match = customVP.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            addTranslation(match.value, category: .vietPhrase)
            hasCustomVP = true
        }

        // 4. Global VietPhrase (VietPhrase.dat)
        if !hasCustomVP,
           !manager.deletedVietPhrase.contains(word),
           let vp = manager.vietPhraseDict,
           let match = vp.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            if match.value.count < 100 {
                addTranslation(match.value, category: .vietPhrase)
            }
        }

        // 5. Phiên âm Hán Việt — gọi thẳng coordinator vì `getHanViet` là private của ReaderView.
        let hv = ReaderSelectionCoordinator.shared.getHanViet(for: word).lowercased()
        if !hv.isEmpty {
            let isDuplicate = chips.contains { existing in
                existing.text == hv
            }
            if !isDuplicate {
                chips.append(SuggestionChip(text: hv, category: .hanViet))
            }
        }

        return chips
    }
}
