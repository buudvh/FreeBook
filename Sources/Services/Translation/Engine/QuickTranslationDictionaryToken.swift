import Foundation

/// Ràng buộc từ điển cho `<ne>` / `<pn>` / `<vp>` / `<w>` / `<hv>`.
///
/// Đây là điểm khác cốt lõi so với reference: reference biên dịch token từ điển thành
/// `([\p{Script=Han}A-Za-z0-9]{min,max})` rồi trả **nguyên văn** capture, nên `<pn>一人` khớp
/// "众人皆知他一人" và nuốt luôn "众人皆知他". Range chỉ giới hạn *độ dài*, không nói *cái gì* được
/// nuốt — nên điều kiện thật phải là "chuỗi tại vị trí capture là một entry của từ điển tương ứng",
/// và range chỉ còn vai trò cắt bớt ứng viên trie.
///
/// `{i}` chèn **nghĩa Việt** lấy từ trie, không giữ chữ Hán: rule quy định thứ tự từ trong câu Việt,
/// để chữ Hán lại cho tokenizer dịch sau sẽ ra thứ tự sai.
public struct QuickTranslationDictionaryToken {
    private let names: TrieDictionary?
    private let customNames: TrieDictionary?
    private let bookNames: TrieDictionary?
    private let pronouns: TrieDictionary?
    private let vietPhrase: TrieDictionary?
    private let customVietPhrase: TrieDictionary?
    private let bookVietPhrase: TrieDictionary?
    private let phienAm: [String: String]

    /// Phân giải một lần cho mỗi lượt rewrite.
    ///
    /// `pronouns` **không** đi theo công tắc `isTranslationPronounsEnabled` (quyết định của chủ dự án,
    /// đổi so với plan §17 #5b): công tắc đó điều khiển việc *tra từ điển đại từ cho từng token* ở
    /// tokenizer, còn ở đây `<pn>` là **ràng buộc của một rule người dùng chủ động viết** — rule
    /// `<pn>一半 = một nửa của {0}` mà im lặng không nổ vì một công tắc ở màn khác là hành vi khó hiểu.
    /// Từ điển `Pronouns` vẫn là optional nên `pronounsDict == nil` vẫn cho `DICT_TOKEN_WITHOUT_DICTIONARY`.
    public static func resolve(bookId: String?) -> QuickTranslationDictionaryToken {
        let manager = TranslationManager.shared

        var bookVP: TrieDictionary? = nil
        var bookNames: TrieDictionary? = nil
        if let bookId = bookId {
            let dictionaries = manager.getBookDictionaries(for: bookId)
            bookVP = dictionaries.vietPhrase
            bookNames = dictionaries.names
        }

        return QuickTranslationDictionaryToken(
            names: manager.namesDict,
            customNames: manager.customNamesDict,
            bookNames: bookNames,
            pronouns: manager.pronounsDict,
            vietPhrase: manager.vietPhraseDict,
            customVietPhrase: manager.customVietPhraseDict,
            bookVietPhrase: bookVP,
            phienAm: manager.phienAmMap
        )
    }

    /// Trạng thái nạp của một nhóm từ điển — nguồn của `DICT_TOKEN_WITHOUT_DICTIONARY`.
    public static func isAvailable(_ kind: QuickTranslationRuleElement.DictionaryKind) -> Bool {
        let manager = TranslationManager.shared
        switch kind {
        case .name:
            return manager.namesDict != nil || manager.customNamesDict != nil
        case .pronoun:
            return manager.pronounsDict != nil
        case .vietPhrase:
            return manager.vietPhraseDict != nil || manager.customVietPhraseDict != nil
        case .hanViet:
            return !manager.phienAmMap.isEmpty
        }
    }

    public func isUsable(_ kind: QuickTranslationRuleElement.DictionaryKind) -> Bool {
        switch kind {
        case .name: return names != nil || customNames != nil || bookNames != nil
        case .pronoun: return pronouns != nil
        case .vietPhrase: return vietPhrase != nil || customVietPhrase != nil || bookVietPhrase != nil
        case .hanViet: return !phienAm.isEmpty
        }
    }

    /// Ứng viên tại một vị trí, **dài → ngắn**. Không dùng `findLongestMatch` một mình: nếu entry dài
    /// nhất làm phần literal phía sau không khớp thì matcher vẫn phải thử entry ngắn hơn.
    ///
    /// - Parameter window: chuỗi bắt đầu **đúng tại** vị trí capture, đã cắt tối đa `maxLength` đơn vị
    ///   UTF-16 để mỗi lời gọi trie không phải quét cả dòng.
    public func candidates(
        kinds: [QuickTranslationRuleElement.DictionaryKind],
        in window: String,
        minLength: Int,
        maxLength: Int
    ) -> [(length: Int, meaning: String)] {
        guard !window.isEmpty else { return [] }
        var byLength: [Int: String] = [:]

        for kind in kinds {
            if kind == .hanViet {
                if minLength <= 1, maxLength >= 1, byLength[1] == nil,
                   let first = window.first, VietPhraseTokenizer.isChineseCharacter(first) {
                    let key = String(first)
                    byLength[1] = phienAm[key] ?? key
                }
                continue
            }

            for dictionary in dictionaries(for: kind) {
                for match in dictionary.findAllPrefixMatches(text: window, startIndex: 0) {
                    guard match.length >= minLength, match.length <= maxLength else { continue }
                    guard byLength[match.length] == nil else { continue }
                    let meaning = TranslateUtils.getFirstMeaning(of: match.value)
                    guard !meaning.isEmpty else { continue }
                    byLength[match.length] = meaning
                }
            }
        }

        return byLength
            .sorted { $0.key > $1.key }
            .map { (length: $0.key, meaning: $0.value) }
    }

    /// Thứ tự tầng giữ đúng theo `TranslateUtils.lookupRawTranslation`: riêng truyện thắng dùng chung.
    private func dictionaries(for kind: QuickTranslationRuleElement.DictionaryKind) -> [TrieDictionary] {
        switch kind {
        case .name:
            return [bookNames, customNames, names].compactMap { $0 }
        case .pronoun:
            return [pronouns].compactMap { $0 }
        case .vietPhrase:
            return [bookVietPhrase, customVietPhrase, vietPhrase].compactMap { $0 }
        case .hanViet:
            return []
        }
    }
}
