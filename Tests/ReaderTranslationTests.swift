import XCTest
@testable import FreeBook

final class ReaderTranslationTests: XCTestCase {
    func testParagraphBuilderUsesNormalizedOneToOneLines() {
        let originalContent = "Dòng 1\n\nDòng 😀 3\n"
        let normalizedText = ChapterTextNormalizer.normalize(originalContent)

        let result = ReaderParagraphBuilder.build(
            originalTitle: "Tiêu đề",
            normalizedText: normalizedText,
            isTranslationEnabled: false,
            showTitle: true,
            bookId: "paragraph-builder-test"
        )

        XCTAssertEqual(result.translatedContent, "Dòng 1\nDòng 😀 3")
        XCTAssertEqual(result.paragraphItems.map(\.id), [-1, 0, 1])
        XCTAssertEqual(result.paragraphItems.dropFirst().map(\.original), ["Dòng 1", "Dòng 😀 3"])
        XCTAssertEqual(result.paragraphItems.dropFirst().map(\.translated), ["Dòng 1", "Dòng 😀 3"])
    }

    func testParagraphBuilderCanHideTitleWithoutChangingLineIDs() {
        let result = ReaderParagraphBuilder.build(
            originalTitle: "Tiêu đề",
            normalizedText: ChapterTextNormalizer.normalize("Một\nHai"),
            isTranslationEnabled: false,
            showTitle: false,
            bookId: "paragraph-builder-no-title-test"
        )

        XCTAssertEqual(result.paragraphItems.map(\.id), [0, 1])
        XCTAssertFalse(result.paragraphItems.contains(where: { $0.isTitle }))
    }

    func testParagraphItemDecodesLegacyPayloadWithoutTranslationSpans() throws {
        let data = #"{"id":4,"original":"原文","translated":"Bản dịch","isTitle":false}"#.data(using: .utf8)!

        let item = try JSONDecoder().decode(ParagraphItem.self, from: data)

        XCTAssertEqual(item.id, 4)
        XCTAssertEqual(item.original, "原文")
        XCTAssertEqual(item.translated, "Bản dịch")
        XCTAssertTrue(item.translationSpans.isEmpty)
    }

    func testSpanMappingUsesUTF16OffsetsAndSupportsMultipleTokens() {
        let item = ParagraphItem(
            id: 2,
            original: "甲😀乙",
            translated: "mot hai",
            translationSpans: [
                TranslationSpan(
                    originalLocation: 0,
                    originalLength: 1,
                    translatedLocation: 0,
                    translatedLength: 3
                ),
                TranslationSpan(
                    originalLocation: 3,
                    originalLength: 1,
                    translatedLocation: 4,
                    translatedLength: 3
                )
            ]
        )

        XCTAssertEqual(
            ReaderSelectionMapper.mappedRangeUsingSpans(NSRange(location: 4, length: 3), in: item),
            NSRange(location: 3, length: 1)
        )
        XCTAssertEqual(
            ReaderSelectionMapper.mappedRangeUsingSpans(NSRange(location: 0, length: 7), in: item),
            NSRange(location: 0, length: 4)
        )
    }

    func testSpanMappingRejectsSelectionOutsideMappedContent() {
        let item = ParagraphItem(
            id: 0,
            original: "原文",
            translated: "Ban dich",
            translationSpans: [
                TranslationSpan(
                    originalLocation: 0,
                    originalLength: 1,
                    translatedLocation: 0,
                    translatedLength: 3
                )
            ]
        )

        XCTAssertNil(
            ReaderSelectionMapper.mappedRangeUsingSpans(NSRange(location: 4, length: 4), in: item)
        )
    }

    func testSpanMappingDistinguishesRepeatedWordsAndPunctuationAcrossSentences() {
        let item = ParagraphItem(
            id: 1,
            original: "甲。乙！",
            translated: "Mot. Mot!",
            translationSpans: [
                TranslationSpan(originalLocation: 0, originalLength: 1, translatedLocation: 0, translatedLength: 3),
                TranslationSpan(originalLocation: 1, originalLength: 1, translatedLocation: 3, translatedLength: 1),
                TranslationSpan(originalLocation: 2, originalLength: 1, translatedLocation: 5, translatedLength: 3),
                TranslationSpan(originalLocation: 3, originalLength: 1, translatedLocation: 8, translatedLength: 1)
            ]
        )

        XCTAssertEqual(
            ReaderSelectionMapper.mappedRangeUsingSpans(NSRange(location: 5, length: 3), in: item),
            NSRange(location: 2, length: 1)
        )
        XCTAssertEqual(
            ReaderSelectionMapper.mappedRangeUsingSpans(NSRange(location: 3, length: 1), in: item),
            NSRange(location: 1, length: 1)
        )
    }

    func testSelectionFallsBackToHistoricalSentenceTokenMapping() {
        let item = ParagraphItem(
            id: 0,
            original: "alpha beta",
            translated: "alpha  beta",
            translationSpans: []
        )

        let mapped = ReaderSelectionMapper.mapSelection(
            NSRange(location: 7, length: 4),
            in: item,
            isTranslationEnabled: true,
            bookId: "historical-fallback-test"
        )

        XCTAssertEqual(mapped, NSRange(location: 0, length: 10))
    }

    func testTranslationTokensExposeUTF16OriginalRanges() {
        let tokens = TranslateUtils.getTranslationTokens(for: "中😀A", bookId: nil)

        XCTAssertEqual(tokens.first?.originalOffset, 0)
        XCTAssertEqual(tokens.first?.originalLength, 1)
        XCTAssertEqual(tokens.last?.originalOffset, 1)
        XCTAssertEqual(tokens.last?.originalLength, 3)
    }

    func testMappedTranslationKeepsTranslateContentOutput() {
        let input = "Văn bản không cần dịch"
        let result = TranslateUtils.translateContentWithMapping(input, bookId: nil)

        XCTAssertEqual(result.text, TranslateUtils.translateContent(input, bookId: nil))
        XCTAssertEqual(result.spans.first?.originalRange, NSRange(location: 0, length: (input as NSString).length))
        XCTAssertEqual(result.spans.first?.translatedRange, NSRange(location: 0, length: (input as NSString).length))
    }
}
