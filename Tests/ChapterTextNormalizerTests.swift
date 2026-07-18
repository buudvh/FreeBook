import XCTest
@testable import FreeBook

final class ChapterTextNormalizerTests: XCTestCase {
    func testNormalizesNewlinesWhitespaceAndBlankLines() {
        let result = ChapterTextNormalizer.normalize("  Một\r\n\r\n \t\rHai 😀  \n")

        XCTAssertEqual(result.content, "Một\nHai 😀")
        XCTAssertEqual(result.lines.map(\.id), [0, 1])
        XCTAssertEqual(result.lines.map(\.text), ["Một", "Hai 😀"])
        XCTAssertEqual(result.lines[0].utf16Range, NSRange(location: 0, length: 3))
        XCTAssertEqual(result.lines[1].utf16Range, NSRange(location: 4, length: 6))
    }

    func testNormalizationIsIdempotent() {
        let first = ChapterTextNormalizer.normalize(" A \n\n B ")
        let second = ChapterTextNormalizer.normalize(first.content)

        XCTAssertEqual(first, second)
    }

    func testReaderAndTTSKeepTheSameParagraphIDs() {
        let normalized = ChapterTextNormalizer.normalize("Một\n\nHai")
        let reader = ReaderParagraphBuilder.build(
            originalTitle: "Tiêu đề",
            normalizedText: normalized,
            isTranslationEnabled: false,
            showTitle: false,
            bookId: "normalizer-test"
        )
        let tts = TTSParagraphBuilder.build(from: normalized, chunkLength: 200)

        XCTAssertEqual(reader.paragraphItems.map(\.id), [0, 1])
        XCTAssertEqual(tts.map(\.paragraphIndex), [0, 1])
        XCTAssertFalse(tts.contains(where: { $0.text.isEmpty }))
    }

    func testLongTTSChunksKeepParentIDAndUTF16Ranges() {
        let normalized = ChapterTextNormalizer.normalize("😀 alpha beta gamma delta")
        let chunks = TTSParagraphBuilder.build(from: normalized, chunkLength: 10)

        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertEqual(Set(chunks.map(\.paragraphIndex)), Set([0]))
        for chunk in chunks {
            let source = normalized.content as NSString
            XCTAssertEqual(source.substring(with: chunk.range), chunk.text)
        }
    }
}
