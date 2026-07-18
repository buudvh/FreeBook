import Foundation

struct ReaderParagraphBuildResult: Equatable, Sendable {
    let translatedTitle: String
    let translatedContent: String
    let paragraphItems: [ParagraphItem]
}

enum ReaderParagraphBuilder {
    static func build(
        originalTitle: String,
        normalizedText: NormalizedChapterText,
        isTranslationEnabled: Bool,
        showTitle: Bool,
        bookId: String
    ) -> ReaderParagraphBuildResult {
        let titleResult: TranslatedTextResult
        if isTranslationEnabled && TranslateUtils.containsChinese(originalTitle) {
            titleResult = TranslateUtils.translateChapterTitleWithMapping(originalTitle, bookId: bookId)
        } else {
            titleResult = TranslateUtils.untranslatedTextResult(originalTitle)
        }

        let translatedLines = normalizedText.lines.map { line -> TranslatedTextResult in
            guard isTranslationEnabled && TranslateUtils.containsChinese(line.text) else {
                return TranslateUtils.untranslatedTextResult(line.text)
            }
            return TranslateUtils.translateContentWithMapping(line.text, bookId: bookId)
        }

        var items: [ParagraphItem] = []
        if showTitle {
            items.append(ParagraphItem(
                id: -1,
                original: originalTitle,
                translated: titleResult.text,
                isTitle: true,
                translationSpans: titleResult.spans
            ))
        }

        items.append(contentsOf: normalizedText.lines.indices.map { index in
            let originalLine = normalizedText.lines[index]
            let translatedLine = translatedLines[index]
            return ParagraphItem(
                id: originalLine.id,
                original: originalLine.text,
                translated: translatedLine.text,
                isTitle: false,
                translationSpans: translatedLine.spans
            )
        })

        return ReaderParagraphBuildResult(
            translatedTitle: titleResult.text,
            translatedContent: translatedLines.map(\.text).joined(separator: "\n"),
            paragraphItems: items
        )
    }
}
