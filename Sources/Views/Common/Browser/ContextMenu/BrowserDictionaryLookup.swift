import Foundation

/// Kết quả tra cho sheet Tra từ điển của trình duyệt: câu chứa từ, token của câu, từ đang tra và các nhóm nghĩa.
///
/// Mọi hàm là thuần, không gắn actor — sheet gọi trong `Task.detached` (tra trie + tách token không chạy trên main).
/// Trình duyệt không gắn với truyện nào ⇒ chỉ từ điển chung (`bookId: nil`, badge C). Chỉ tra, không sửa nghĩa.
///
/// Nguồn nghĩa dùng chung với Reader: `ReaderView.dictionaryMatches(for:bookId:)` + `ReaderView.suggestionChips(from:)`
/// (chip `.vietPhrase` gồm VietPhrase, Xưng hô, Luật nhân; `.name` = Names). Hán Việt lấy riêng từ
/// `ReaderSelectionCoordinator.hanViet(for:)` nên chip `.hanViet` (Phiên âm) không lặp lại ở nhóm VietPhrase.
struct BrowserDictionaryLookup: Sendable {
    /// Câu dài hơn trần này thì cắt cửa sổ quanh từ đang tra.
    static let maxSentenceLength = 240

    let sentence: String
    /// Token có chữ/số của câu (bỏ token chỉ là dấu câu/khoảng trắng). Offset UTF-16 tính trên `sentence`.
    let tokens: [TranslationWordToken]
    let word: String
    /// Vị trí UTF-16 của `word` trong `sentence`; `nil` khi từ không nằm trong câu (so token theo chữ).
    let wordStart: Int?
    let wordLength: Int
    /// `nil` = từ không có chữ Hán ⇒ "Không có".
    let hanViet: String?
    let vietPhrase: [SuggestionChip]
    let names: [SuggestionChip]

    /// Token đang tra (viền sáng): giao với vùng của từ, hoặc trùng chữ khi không biết vị trí.
    func isFocused(_ token: TranslationWordToken) -> Bool {
        guard let wordStart else { return token.originalText == word }
        let wordEnd = wordStart + wordLength
        return token.originalOffset < wordEnd && token.originalOffset + token.originalLength > wordStart
    }

    /// Tra token khác của cùng câu (chạm token).
    func focusing(_ token: TranslationWordToken) -> BrowserDictionaryLookup {
        let word = token.originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        let leading = token.originalText.prefix { $0.isWhitespace }.utf16.count
        return Self.make(
            sentence: sentence, tokens: tokens, word: word,
            start: token.originalOffset + leading, length: word.utf16.count
        )
    }

    // MARK: - Dựng từ yêu cầu

    /// `nil` khi ngữ cảnh rỗng hoặc không tách được token nào.
    static func resolve(_ request: BrowserLookupRequest) -> BrowserDictionaryLookup? {
        let context = request.context as NSString
        guard context.length > 0 else { return nil }
        let word = request.word.trimmingCharacters(in: .whitespacesAndNewlines)
        let wordRange = locate(word: word, rawWord: request.word, offset: request.wordOffset, in: context)

        if !word.isEmpty, wordRange == nil {
            // Từ không nằm trong ngữ cảnh (JS lùi về chuỗi chọn): tra riêng từ đó.
            let tokens = displayTokens(TranslateUtils.getTranslationTokens(for: word, bookId: nil))
            return make(sentence: word, tokens: tokens, word: word, start: 0, length: word.utf16.count)
        }

        var range = sentenceRange(in: request.context, length: context.length, around: wordRange)
        range = clamp(range, around: wordRange, in: context)
        range = trimWhitespace(range, in: context)
        guard range.length > 0 else { return nil }
        let sentence = context.substring(with: range)
        let tokens = displayTokens(TranslateUtils.getTranslationTokens(for: sentence, bookId: nil))

        if let wordRange {
            let start = wordRange.location - range.location
            if start >= 0, start + wordRange.length <= (sentence as NSString).length {
                return make(sentence: sentence, tokens: tokens, word: word, start: start, length: wordRange.length)
            }
            return make(sentence: sentence, tokens: tokens, word: word, start: nil, length: wordRange.length)
        }
        // Không có từ (trang đã dịch / nút của sheet Dịch QT): token có chữ Hán đầu tiên.
        guard let token = tokens.first(where: { TranslateUtils.containsChinese($0.originalText) }) ?? tokens.first else {
            return nil
        }
        return BrowserDictionaryLookup(
            sentence: sentence, tokens: tokens, word: "", wordStart: nil, wordLength: 0,
            hanViet: nil, vietPhrase: [], names: []
        ).focusing(token)
    }

    // MARK: - Nội bộ

    private static func make(
        sentence: String,
        tokens: [TranslationWordToken],
        word: String,
        start: Int?,
        length: Int
    ) -> BrowserDictionaryLookup {
        let chips = word.isEmpty ? [] : ReaderView.suggestionChips(from: ReaderView.dictionaryMatches(for: word, bookId: nil))
        let hanViet = TranslateUtils.containsChinese(word)
            ? ReaderSelectionCoordinator.hanViet(for: word).lowercased()
            : nil
        return BrowserDictionaryLookup(
            sentence: sentence,
            tokens: tokens,
            word: word,
            wordStart: start,
            wordLength: length,
            hanViet: hanViet,
            vietPhrase: chips.filter { $0.category == .vietPhrase },
            names: chips.filter { $0.category == .name }
        )
    }

    /// Vị trí của từ (đã bỏ khoảng trắng hai đầu) trong ngữ cảnh: ưu tiên `offset` do JS gửi, lệch thì tìm lần đầu.
    private static func locate(word: String, rawWord: String, offset: Int?, in context: NSString) -> NSRange? {
        guard !word.isEmpty else { return nil }
        let length = (word as NSString).length
        if let offset {
            let leading = rawWord.prefix { $0.isWhitespace }.utf16.count
            let candidate = NSRange(location: offset + leading, length: length)
            if candidate.location >= 0, NSMaxRange(candidate) <= context.length,
               context.substring(with: candidate) == word {
                return candidate
            }
        }
        let found = context.range(of: word)
        return found.location == NSNotFound ? nil : found
    }

    /// Hợp các câu giao với từ; không có từ ⇒ câu có chữ Hán đầu tiên; không tách được ⇒ cả ngữ cảnh.
    private static func sentenceRange(in context: String, length: Int, around focus: NSRange?) -> NSRange {
        let full = NSRange(location: 0, length: length)
        let sentences = TranslateUtils.getSentenceRanges(in: context)
        if let focus {
            let hits = sentences.filter { NSIntersectionRange($0.range, focus).length > 0 }
            guard let first = hits.first, let last = hits.last else { return full }
            return NSUnionRange(NSUnionRange(first.range, last.range), focus)
        }
        return sentences.first { TranslateUtils.containsChinese($0.text) }?.range ?? sentences.first?.range ?? full
    }

    /// Câu quá dài ⇒ cửa sổ `maxSentenceLength` quanh từ (luôn chứa trọn từ), không cắt giữa ký tự ghép.
    private static func clamp(_ range: NSRange, around focus: NSRange?, in context: NSString) -> NSRange {
        guard range.length > maxSentenceLength else { return range }
        let focus = focus ?? NSRange(location: range.location, length: 0)
        let span = max(maxSentenceLength, focus.length)
        var start = focus.location + focus.length / 2 - span / 2
        start = min(max(start, range.location), NSMaxRange(range) - span)
        return context.rangeOfComposedCharacterSequences(for: NSRange(location: start, length: span))
    }

    private static func trimWhitespace(_ range: NSRange, in context: NSString) -> NSRange {
        var start = range.location
        var end = NSMaxRange(range)
        let whitespace = CharacterSet.whitespacesAndNewlines
        while start < end, let scalar = UnicodeScalar(context.character(at: start)), whitespace.contains(scalar) {
            start += 1
        }
        while end > start, let scalar = UnicodeScalar(context.character(at: end - 1)), whitespace.contains(scalar) {
            end -= 1
        }
        return NSRange(location: start, length: end - start)
    }

    private static func displayTokens(_ tokens: [TranslationWordToken]) -> [TranslationWordToken] {
        tokens.filter { token in
            token.originalText.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
        }
    }
}
