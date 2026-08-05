import Foundation

enum ReaderSelectionMapper {
    static func mapSelection(
        _ selectionRange: NSRange,
        in item: ParagraphItem,
        isTranslationEnabled: Bool,
        bookId: String
    ) -> NSRange? {
        let displayedText = isTranslationEnabled ? item.translated : item.original
        guard isValid(selectionRange, in: displayedText), !item.original.isEmpty else { return nil }

        if !isTranslationEnabled {
            return snap(selectionRange, in: item.original, bookId: bookId)
        }

        if item.original == item.translated {
            return snap(selectionRange, in: item.original, bookId: bookId)
        }

        if let mappedRange = mappedRangeUsingSpans(selectionRange, in: item) {
            return snap(mappedRange, in: item.original, bookId: bookId)
        }

        return mapUsingHistoricalSentenceFallback(selectionRange, in: item, bookId: bookId)
    }

    static func mappedRangeUsingSpans(_ selectionRange: NSRange, in item: ParagraphItem) -> NSRange? {
        guard isValid(selectionRange, in: item.translated) else { return nil }

        let overlappingSpans = item.translationSpans.filter {
            NSIntersectionRange($0.translatedRange, selectionRange).length > 0
        }
        guard !overlappingSpans.isEmpty,
              selectionIsCovered(selectionRange, in: item.translated, by: overlappingSpans) else {
            return nil
        }

        let start = overlappingSpans.map(\.originalLocation).min() ?? 0
        let end = overlappingSpans.map { $0.originalLocation + $0.originalLength }.max() ?? start
        let mappedRange = NSRange(location: start, length: max(0, end - start))
        return isValid(mappedRange, in: item.original) ? mappedRange : nil
    }

    private static func mapUsingHistoricalSentenceFallback(
        _ selectionRange: NSRange,
        in item: ParagraphItem,
        bookId: String
    ) -> NSRange? {
        let translatedSentences = TranslateUtils.getSentenceRanges(in: item.translated)
        let originalSentences = TranslateUtils.getSentenceRanges(in: item.original)
        guard !translatedSentences.isEmpty, !originalSentences.isEmpty else { return nil }

        let translatedSentenceIndex = translatedSentences.firstIndex {
            $0.range.location <= selectionRange.location && selectionRange.location < NSMaxRange($0.range)
        }

        let targetOriginalIndex: Int
        let translatedSentence: SentenceRange
        if let translatedSentenceIndex, translatedSentenceIndex < originalSentences.count {
            targetOriginalIndex = translatedSentenceIndex
            translatedSentence = translatedSentences[translatedSentenceIndex]
        } else {
            let translatedLength = max(1, (item.translated as NSString).length)
            let relativePosition = Double(selectionRange.location) / Double(translatedLength)
            targetOriginalIndex = originalSentences.indices.min { lhs, rhs in
                relativeDistance(of: originalSentences[lhs].range, totalLength: (item.original as NSString).length, to: relativePosition)
                    < relativeDistance(of: originalSentences[rhs].range, totalLength: (item.original as NSString).length, to: relativePosition)
            } ?? 0
            translatedSentence = translatedSentences[min(targetOriginalIndex, translatedSentences.count - 1)]
        }

        let originalSentence = originalSentences[targetOriginalIndex]
        let tokens = TranslateUtils.getTranslationTokens(for: originalSentence.text, bookId: bookId)
        let relativeSelection = NSRange(
            location: max(0, selectionRange.location - translatedSentence.range.location),
            length: selectionRange.length
        )

        var reconstructedTranslation = ""
        var translatedTokenRanges: [NSRange] = []
        for token in tokens {
            let start = (reconstructedTranslation as NSString).length
            reconstructedTranslation.append(token.translatedText)
            let end = (reconstructedTranslation as NSString).length
            translatedTokenRanges.append(NSRange(location: start, length: end - start))
            reconstructedTranslation.append(" ")
        }

        let overlappingTokenIndexes = translatedTokenRanges.indices.filter {
            NSIntersectionRange(translatedTokenRanges[$0], relativeSelection).length > 0
        }

        let rangeInOriginalSentence: NSRange
        if let first = overlappingTokenIndexes.first, let last = overlappingTokenIndexes.last {
            let start = tokens[first].originalOffset
            let end = tokens[last].originalOffset + tokens[last].originalLength
            rangeInOriginalSentence = NSRange(location: start, length: max(1, end - start))
        } else {
            let translatedLength = max(1, translatedSentence.range.length)
            let originalLength = max(1, originalSentence.range.length)
            let ratio = Double(relativeSelection.location) / Double(translatedLength)
            let location = min(Int((ratio * Double(originalLength)).rounded()), originalLength - 1)
            rangeInOriginalSentence = NSRange(location: location, length: 1)
        }

        let paragraphRange = NSRange(
            location: originalSentence.range.location + rangeInOriginalSentence.location,
            length: rangeInOriginalSentence.length
        )
        return snap(paragraphRange, in: item.original, bookId: bookId)
    }

    private static func snap(_ range: NSRange, in original: String, bookId: String) -> NSRange? {
        guard isValid(range, in: original) else { return nil }
        let snapped = TranslateUtils.snapToToken(
            sentence: original,
            selectionOffset: range.location,
            selectionLength: range.length,
            bookId: bookId
        )
        let snappedRange = NSRange(location: snapped.offset, length: snapped.length)
        return isValid(snappedRange, in: original) ? snappedRange : range
    }

    private static func selectionIsCovered(
        _ selectionRange: NSRange,
        in translated: String,
        by spans: [TranslationSpan]
    ) -> Bool {
        let text = translated as NSString
        for index in selectionRange.location..<NSMaxRange(selectionRange) {
            let character = text.character(at: index)
            if let scalar = UnicodeScalar(character), CharacterSet.whitespacesAndNewlines.contains(scalar) {
                continue
            }
            if !spans.contains(where: { NSLocationInRange(index, $0.translatedRange) }) {
                return false
            }
        }
        return true
    }

    private static func relativeDistance(of range: NSRange, totalLength: Int, to position: Double) -> Double {
        guard totalLength > 0 else { return position }
        let center = Double(range.location) + Double(range.length) / 2
        return abs(center / Double(totalLength) - position)
    }

    private static func isValid(_ range: NSRange, in text: String) -> Bool {
        range.location != NSNotFound &&
            range.location >= 0 &&
            range.length > 0 &&
            NSMaxRange(range) <= (text as NSString).length
    }
}
