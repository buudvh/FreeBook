import Foundation

extension TranslateUtils {
    public static func getTranslationTokens(for sentence: String, bookId: String?) -> [TranslationWordToken] {
        return TranslationReadContext.withSnapshot(bookId: bookId) {
        let tokens = tokenize(sentence, bookId: bookId)
        var wordTokens: [TranslationWordToken] = []
        let phienAm = TranslationManager.shared.phienAmMap
        
        let nsSentence = sentence as NSString
        var currentUTF16Offset = 0
        let totalUTF16Length = nsSentence.length
        
        for token in tokens {
            if Task.isCancelled { return [] }
            let tokenUTF16Length = (token as NSString).length
            guard currentUTF16Offset + tokenUTF16Length <= totalUTF16Length else { break }
            let originalText = nsSentence.substring(with: NSRange(location: currentUTF16Offset, length: tokenUTF16Length))
            
            let (translatedToken, isMatched) = resolveTokenMeaning(for: token, bookId: bookId, phienAm: phienAm)
            
            let trimmedTrans = translatedToken.trimmingCharacters(in: .whitespacesAndNewlines)
            if isMatched || !trimmedTrans.isEmpty || !originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                wordTokens.append(TranslationWordToken(
                    originalText: originalText,
                    translatedText: isMatched ? trimmedTrans : (trimmedTrans.isEmpty ? originalText : trimmedTrans),
                    originalOffset: currentUTF16Offset,
                    originalLength: tokenUTF16Length
                ))
            }
            
            currentUTF16Offset += tokenUTF16Length
        }
        
        return wordTokens
        }
    }

    /// Token cho thanh chip của panel Dịch: tách **giống trang đọc**, tức áp rule dịch trước rồi mới tách.
    ///
    /// `getTranslationTokens` tách thẳng chuỗi gốc, còn trang đọc (`performTranslation`) chạy rule trước. Ở cụm rule
    /// đã xử lý, tokenizer (chọn mục dài nhất toàn cục) có thể vớ một mục VP vắt qua ranh giới token của rule và bỏ lại
    /// chữ lẻ không có mục riêng ⇒ chip hiện Hán-Việt trong khi trang hiện đúng nghĩa. Vì vậy cụm rule tách theo đúng
    /// các token rule đã nuốt (`Segment.captures`); đoạn không có rule khớp trả nguyên `getTranslationTokens`.
    ///
    /// Offset/độ dài vẫn là UTF-16 trên `sentence`. Span và `mapSelection` **không** dùng hàm này — vẫn đi
    /// `getTranslationTokens` như cũ.
    public static func getRuleAwareTokens(for sentence: String, bookId: String?) -> [TranslationWordToken] {
        return TranslationReadContext.withSnapshot(bookId: bookId) {
            guard let rewrite = QuickTranslationRuleEngine.rewrite(sentence, bookId: bookId), rewrite.didRewrite else {
                return getTranslationTokens(for: sentence, bookId: bookId)
            }
            let nsSentence = sentence as NSString
            let rewritten = rewrite.text as NSString
            var tokens: [TranslationWordToken] = []
            for segment in rewrite.segments {
                if Task.isCancelled { return [] }
                if segment.sourceLine == nil {
                    tokens += dictionaryTokens(in: segment.sourceRange, of: nsSentence, bookId: bookId)
                } else {
                    tokens += ruleSegmentTokens(segment, rewritten: rewritten, sentence: nsSentence, bookId: bookId)
                }
            }
            return tokens
        }
    }

    /// Một cụm rule ⇒ mỗi token rule một chip mang đúng nghĩa trang đang hiện; chữ nằm giữa các token (literal của
    /// mẫu, vd `的`) tách bằng từ điển. Token rỗng hoặc còn chữ Hán (trang sẽ tách lại chữ đó) ⇒ tách chữ gốc bằng
    /// từ điển. Rule không có token nào ⇒ một chip cho cả cụm với kết quả rule.
    private static func ruleSegmentTokens(
        _ segment: QuickTranslationRewriteResult.Segment,
        rewritten: NSString,
        sentence: NSString,
        bookId: String?
    ) -> [TranslationWordToken] {
        let bounds = segment.sourceRange
        guard bounds.length > 0, NSMaxRange(bounds) <= sentence.length else { return [] }

        // Template có thể đảo thứ tự capture ⇒ xếp lại theo vị trí nguồn; bỏ token vắng và token lọt ngoài cụm.
        let captures = segment.captures
            .compactMap { capture -> (range: NSRange, meaning: String)? in
                guard let range = capture.sourceRange, range.length > 0,
                      NSIntersectionRange(range, bounds).length == range.length else { return nil }
                return (range, capture.text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            .sorted { $0.range.location < $1.range.location }

        guard !captures.isEmpty else {
            let rendered = NSMaxRange(segment.outputRange) <= rewritten.length
                ? rewritten.substring(with: segment.outputRange).trimmingCharacters(in: .whitespacesAndNewlines)
                : ""
            guard !rendered.isEmpty, !containsChinese(rendered) else {
                return dictionaryTokens(in: bounds, of: sentence, bookId: bookId)
            }
            return [TranslationWordToken(originalText: sentence.substring(with: bounds), translatedText: rendered,
                                         originalOffset: bounds.location, originalLength: bounds.length)]
        }

        var tokens: [TranslationWordToken] = []
        var cursor = bounds.location
        for capture in captures where capture.range.location >= cursor {
            tokens += dictionaryTokens(in: NSRange(location: cursor, length: capture.range.location - cursor),
                                       of: sentence, bookId: bookId)
            if capture.meaning.isEmpty || containsChinese(capture.meaning) {
                tokens += dictionaryTokens(in: capture.range, of: sentence, bookId: bookId)
            } else {
                tokens.append(TranslationWordToken(
                    originalText: sentence.substring(with: capture.range),
                    translatedText: capture.meaning,
                    originalOffset: capture.range.location,
                    originalLength: capture.range.length
                ))
            }
            cursor = NSMaxRange(capture.range)
        }
        tokens += dictionaryTokens(in: NSRange(location: cursor, length: NSMaxRange(bounds) - cursor),
                                   of: sentence, bookId: bookId)
        return tokens
    }

    /// `getTranslationTokens` trên một khúc của `sentence`, offset dời về hệ toạ độ của cả `sentence`.
    private static func dictionaryTokens(in range: NSRange, of sentence: NSString, bookId: String?) -> [TranslationWordToken] {
        guard range.length > 0, NSMaxRange(range) <= sentence.length else { return [] }
        return getTranslationTokens(for: sentence.substring(with: range), bookId: bookId).map {
            TranslationWordToken(originalText: $0.originalText, translatedText: $0.translatedText,
                                 originalOffset: $0.originalOffset + range.location, originalLength: $0.originalLength)
        }
    }

    public static func getSentenceRanges(in text: String) -> [SentenceRange] {
        var tempText = text
        tempText = tempText.replacingOccurrences(of: "...", with: ",,,")
        tempText = tempText.replacingOccurrences(of: "..", with: ",,")
        
        let pattern = #"[^。！？\n\r.!?]+[。！？\n\r.!?]*"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return [SentenceRange(text: text, range: NSRange(location: 0, length: (text as NSString).length))]
        }
        
        let nsText = text as NSString
        let nsTempText = tempText as NSString
        let matches = regex.matches(in: tempText, options: [], range: NSRange(location: 0, length: nsTempText.length))
        
        return matches.map { match in
            let matchRange = match.range
            let substring = nsText.substring(with: matchRange)
            return SentenceRange(text: substring, range: matchRange)
        }
    }
    
    public static func snapToToken(
        sentence: String,
        selectionOffset: Int,
        selectionLength: Int,
        bookId: String?
    ) -> (offset: Int, length: Int) {
        let tokens = getTranslationTokens(for: sentence, bookId: bookId)
        guard !tokens.isEmpty else { return (selectionOffset, selectionLength) }
        
        let selectionEnd = selectionOffset + selectionLength
        var overlappingTokens: [TranslationWordToken] = []
        
        for token in tokens {
            let tokenEnd = token.originalOffset + token.originalLength
            let maxStart = max(token.originalOffset, selectionOffset)
            let minEnd = min(tokenEnd, selectionEnd)
            if maxStart < minEnd {
                overlappingTokens.append(token)
            }
        }
        
        if let first = overlappingTokens.first, let last = overlappingTokens.last {
            let start = first.originalOffset
            let end = last.originalOffset + last.originalLength
            return (start, end - start)
        }
        
        return (selectionOffset, selectionLength)
    }

    /// Dịch một từ hoặc cụm từ đơn lẻ giữ nguyên bản hoa/thường từ từ điển (không ép viết hoa chữ cái đầu).
    public static func translateTerm(
        _ text: String?,
        bookId: String? = nil,
        shouldConvertTraditionalToSimplified: Bool = false
    ) -> String {
        let translationInput = text.map {
            textForTranslation(
                $0,
                shouldConvertTraditionalToSimplified: shouldConvertTraditionalToSimplified
            )
        }
        guard let text = translationInput, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return text ?? "" }
        guard containsChinese(text) else { return text }
        guard TranslationManager.shared.vietPhraseDict != nil else { return text }

        return TranslationReadContext.withSnapshot(bookId: bookId) {
            performTranslation(text, bookId: bookId, applyingQuickTranslationRules: true, capitalizeFirstLetter: false)
        }
    }
}
