import Foundation

struct ReaderParagraphBuildResult: Equatable, Sendable {
    let translatedTitle: String
    let translatedContent: String
    let paragraphItems: [ParagraphItem]
}

enum ReaderParagraphBuilder {
    static func build(
        originalTitle: String,
        originalContent: String,
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

        let originalLines = originalContent.components(separatedBy: "\n")
        let translatedLines = originalLines.map { line -> TranslatedTextResult in
            guard isTranslationEnabled && TranslateUtils.containsChinese(line) else {
                return TranslateUtils.untranslatedTextResult(line)
            }
            return TranslateUtils.translateContentWithMapping(line, bookId: bookId)
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

        items.append(contentsOf: originalLines.indices.map { index in
            let translatedLine = translatedLines[index]
            return ParagraphItem(
                id: index,
                original: originalLines[index],
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
