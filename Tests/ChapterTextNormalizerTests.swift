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

    // MARK: - Ánh xạ highlight TTS sang hệ tọa độ text đang hiển thị

    /// Nguyên bản 6 ký tự, bản dịch dài hơn hẳn — kiểu dữ liệu điển hình của truyện convert.
    private func makeTranslatedItem() -> ParagraphItem {
        // original:   "甲，乙。"        (0..<4)
        // translated: "Giáp, Ất."     (0..<9)
        ParagraphItem(
            id: 0,
            original: "甲，乙。",
            translated: "Giáp, Ất.",
            isTitle: false,
            translationSpans: [
                TranslationSpan(originalLocation: 0, originalLength: 1, translatedLocation: 0, translatedLength: 4),
                TranslationSpan(originalLocation: 1, originalLength: 1, translatedLocation: 4, translatedLength: 2),
                TranslationSpan(originalLocation: 2, originalLength: 1, translatedLocation: 6, translatedLength: 2),
                TranslationSpan(originalLocation: 3, originalLength: 1, translatedLocation: 8, translatedLength: 1)
            ]
        )
    }

    func testHighlightMapsToTranslatedCoordinates() {
        let item = makeTranslatedItem()

        // Chunk đầu "甲，" ở tọa độ gốc 0..<2 phải phủ "Giáp, " trong bản dịch.
        let mapped = ReaderSelectionMapper.mapHighlight(
            NSRange(location: 0, length: 2),
            in: item,
            displayText: item.translated
        )

        XCTAssertEqual(mapped, NSRange(location: 0, length: 6))

        // Chunk cuối "乙。" ở tọa độ gốc 2..<4 phải phủ "Ất." — nơi độ lệch tích lũy lớn nhất.
        let mappedTail = ReaderSelectionMapper.mapHighlight(
            NSRange(location: 2, length: 2),
            in: item,
            displayText: item.translated
        )

        XCTAssertEqual(mappedTail, NSRange(location: 6, length: 3))
    }

    func testHighlightPassthroughWhenTranslationDisabled() {
        let item = makeTranslatedItem()
        let originalRange = NSRange(location: 2, length: 2)

        // displayText chính là nguyên bản → không được dịch chuyển range.
        let mapped = ReaderSelectionMapper.mapHighlight(
            originalRange,
            in: item,
            displayText: item.original
        )

        XCTAssertEqual(mapped, originalRange)
    }

    func testHighlightFallbackWhenSpansEmpty() {
        // buildTranslationSpans trả [] khi có token không dò được trong chuỗi dịch.
        let item = ParagraphItem(
            id: 0,
            original: "甲，乙。",
            translated: "Giáp, Ất.",
            isTitle: false,
            translationSpans: []
        )

        let mapped = ReaderSelectionMapper.mapHighlight(
            NSRange(location: 2, length: 2),
            in: item,
            displayText: item.translated
        )

        let translatedLength = (item.translated as NSString).length
        XCTAssertNotNil(mapped)
        XCTAssertGreaterThanOrEqual(mapped!.location, 0)
        XCTAssertLessThanOrEqual(NSMaxRange(mapped!), translatedLength)
        XCTAssertGreaterThan(mapped!.length, 0)
    }

    func testHighlightUsesFallbackWhenDisplayTextDiffersFromStoredTranslation() {
        let item = makeTranslatedItem()
        // Từ điển vừa đổi: chuỗi đang render khác item.translated nên span đã cũ, không được dùng.
        let liveDisplayText = "Giáp Ất Bính Đinh."

        let mapped = ReaderSelectionMapper.mapHighlight(
            NSRange(location: 2, length: 2),
            in: item,
            displayText: liveDisplayText
        )

        XCTAssertNotNil(mapped)
        XCTAssertLessThanOrEqual(NSMaxRange(mapped!), (liveDisplayText as NSString).length)
    }

    func testMultiPunctuationChunksStayInBoundsAndAdvance() {
        let original = "甲，乙；丙。丁！戊？己…"
        let translated = "Giáp, Ất; Bính. Đinh! Mậu? Kỷ…"
        let originalNS = original as NSString

        // Span đồng nhất theo từng ký tự gốc, chia đều trên chuỗi dịch — đủ để kiểm tra tính đơn điệu.
        let translatedNS = translated as NSString
        let ratio = Double(translatedNS.length) / Double(originalNS.length)
        var spans: [TranslationSpan] = []
        for index in 0..<originalNS.length {
            let start = min(translatedNS.length - 1, Int((Double(index) * ratio).rounded()))
            let end = min(translatedNS.length, Int((Double(index + 1) * ratio).rounded()))
            spans.append(TranslationSpan(
                originalLocation: index,
                originalLength: 1,
                translatedLocation: start,
                translatedLength: max(1, end - start)
            ))
        }

        let item = ParagraphItem(
            id: 0,
            original: original,
            translated: translated,
            isTitle: false,
            translationSpans: spans
        )

        let normalized = ChapterTextNormalizer.normalize(original)
        let chunks = TTSParagraphBuilder.build(from: normalized, chunkLength: 6)
        XCTAssertGreaterThan(chunks.count, 1, "Đoạn nhiều dấu câu phải bị cắt thành nhiều chunk")

        var previousLocation = -1
        for chunk in chunks {
            guard let mapped = ReaderSelectionMapper.mapHighlight(
                chunk.range,
                in: item,
                displayText: translated
            ) else {
                XCTFail("Chunk \(chunk.text) không ánh xạ được sang tọa độ hiển thị")
                continue
            }

            XCTAssertLessThanOrEqual(
                NSMaxRange(mapped),
                translatedNS.length,
                "Chunk '\(chunk.text)' vượt biên chuỗi hiển thị"
            )
            XCTAssertGreaterThan(
                mapped.location,
                previousLocation,
                "Highlight phải tiến về phía trước theo thứ tự chunk"
            )
            previousLocation = mapped.location
        }
    }
}
