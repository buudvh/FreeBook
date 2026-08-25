import Foundation

extension TranslateUtils {

    // MARK: - Span khi có rule dịch

    /// Dựng `TranslationSpan` cho một chuỗi **đã đi qua rule dịch**.
    ///
    /// Không dùng lại `buildTranslationSpans(original:translated:)` cho vùng đã rewrite: hàm đó dò
    /// token của chuỗi *gốc* trong chuỗi *đã dịch*, nên với vùng rule vừa xử lý nó chỉ `continue` và
    /// bỏ span — Reader mất tra từ điển đúng ở chính những vùng đó, hoặc tệ hơn là khớp bừa vào một
    /// vị trí khác. Ở đây token được lấy trên chuỗi **sau rewrite** rồi rebase về nguồn qua bản đồ
    /// đoạn của engine.
    static func translationSpansApplyingRules(
        source: String,
        translated: String,
        bookId: String?
    ) -> [TranslationSpan] {
        guard let rewrite = QuickTranslationRuleEngine.rewrite(source, bookId: bookId),
              rewrite.didRewrite else {
            return buildTranslationSpans(original: source, translated: translated, bookId: bookId)
        }

        guard !source.isEmpty, !translated.isEmpty else { return [] }

        let translatedNSString = translated as NSString
        let tokens = getTranslationTokens(for: rewrite.text, bookId: bookId)
        var cursor = 0
        var spans: [TranslationSpan] = []

        for token in tokens {
            let candidate = postProcessText(token.translatedText)
            guard !candidate.isEmpty, cursor <= translatedNSString.length else { continue }

            // Đoạn nào không chứng minh được mapping thì bỏ span **của riêng đoạn đó**, không bịa
            // range theo tỉ lệ và không xoá trace của đoạn khác.
            guard let sourceRange = rewrite.sourceRange(forOutputRange: NSRange(
                location: token.originalOffset,
                length: token.originalLength
            )) else { continue }

            let searchRange = NSRange(location: cursor, length: translatedNSString.length - cursor)
            guard let translatedRange = findTranslatedTokenRange(
                candidate,
                in: translated,
                searchRange: searchRange
            ) else { continue }

            spans.append(TranslationSpan(
                originalLocation: sourceRange.location,
                originalLength: sourceRange.length,
                translatedLocation: translatedRange.location,
                translatedLength: translatedRange.length
            ))
            cursor = NSMaxRange(translatedRange)
        }

        return spans
    }

    // MARK: - Span khi không có rule (đường cũ, giữ nguyên hành vi)

    public static func buildTranslationSpans(
        original: String,
        translated: String,
        bookId: String? = nil
    ) -> [TranslationSpan] {
        guard !original.isEmpty, !translated.isEmpty else { return [] }
        if original == translated {
            return untranslatedTextResult(original).spans
        }

        let translatedNSString = translated as NSString
        let tokens = getTranslationTokens(for: original, bookId: bookId)
        var cursor = 0
        var spans: [TranslationSpan] = []

        for token in tokens {
            let candidate = postProcessText(token.translatedText)
            guard !candidate.isEmpty, cursor <= translatedNSString.length else { continue }

            let searchRange = NSRange(location: cursor, length: translatedNSString.length - cursor)
            guard let translatedRange = findTranslatedTokenRange(
                candidate,
                in: translated,
                searchRange: searchRange
            ) else {
                continue
            }

            spans.append(TranslationSpan(
                originalLocation: token.originalOffset,
                originalLength: token.originalLength,
                translatedLocation: translatedRange.location,
                translatedLength: translatedRange.length
            ))
            cursor = NSMaxRange(translatedRange)
        }

        return spans
    }

    static func findTranslatedTokenRange(
        _ tokenText: String,
        in translated: String,
        searchRange: NSRange
    ) -> NSRange? {
        let translatedNSString = translated as NSString
        let literalRange = translatedNSString.range(
            of: tokenText,
            options: [.caseInsensitive],
            range: searchRange
        )
        if literalRange.location != NSNotFound {
            return literalRange
        }

        let parts = tokenText
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }

        let pattern = parts
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: #"\s+"#)
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        return regex.firstMatch(in: translated, options: [], range: searchRange)?.range
    }
}
