import XCTest
@testable import FreeBook

final class NghiUtteranceSegmenterTests: XCTestCase {
    func testSplitsShortParagraphAtSentenceBoundaries() {
        let paragraph = makeParagraph("Mot. Hai? Ba!")

        let result = NghiUtteranceSegmenter.expand([paragraph], maximumLength: 100)

        XCTAssertEqual(result.map(\.text), ["Mot.", "Hai?", "Ba!"])
        XCTAssertEqual(result.map(\.boundaryKind), [.sentenceEnd, .sentenceEnd, .paragraphEnd])
        XCTAssertTrue(result.allSatisfy { $0.paragraphIndex == paragraph.paragraphIndex })
    }

    func testDoesNotSplitDecimalPeriod() {
        let paragraph = makeParagraph("Gia 12.5 dong. Tiep.")

        let result = NghiUtteranceSegmenter.expand([paragraph], maximumLength: 100)

        XCTAssertEqual(result.map(\.text), ["Gia 12.5 dong.", "Tiep."])
    }

    func testKeepsRepeatedSentencePunctuationInOneWAV() {
        let paragraph = makeParagraph("Sao?! Tiep tuc...")

        let result = NghiUtteranceSegmenter.expand([paragraph], maximumLength: 100)

        XCTAssertEqual(result.map(\.text), ["Sao?!", "Tiep tuc..."])
        XCTAssertEqual(result.first?.boundaryKind, .sentenceEnd)
    }

    func testUsesPhraseThenWordFallbackForLongSentence() {
        let phraseParagraph = makeParagraph("alpha beta, gamma delta epsilon.")
        let wordParagraph = makeParagraph("abcdefgh ijklmnop qrstuv")

        let phraseResult = NghiUtteranceSegmenter.expand([phraseParagraph], maximumLength: 18)
        let wordResult = NghiUtteranceSegmenter.expand([wordParagraph], maximumLength: 12)

        XCTAssertEqual(phraseResult.first?.text, "alpha beta,")
        XCTAssertEqual(phraseResult.first?.boundaryKind, .phraseEnd)
        XCTAssertEqual(wordResult.first?.text, "abcdefgh")
        XCTAssertEqual(wordResult.first?.boundaryKind, .technicalChunk)
        XCTAssertTrue((phraseResult + wordResult).allSatisfy { $0.text.utf16.count <= 18 })
        XCTAssertTrue(wordResult.allSatisfy { $0.text.utf16.count <= 12 })
    }

    func testKeepsClosingQuoteWithSentenceAndPreservesRanges() {
        let text = "He said \"Go!\" Then left."
        let paragraph = TTSParagraph(
            text: text,
            range: NSRange(location: 50, length: text.utf16.count),
            paragraphIndex: 7,
            sourceRange: NSRange(location: 100, length: text.utf16.count),
            boundaryKind: .paragraphEnd
        )

        let result = NghiUtteranceSegmenter.expand([paragraph], maximumLength: 100)

        XCTAssertEqual(result.map(\.text), ["He said \"Go!\"", "Then left."])
        XCTAssertEqual(result.first?.boundaryKind, .sentenceEnd)
        XCTAssertEqual(result.first?.range.location, 50)
        XCTAssertEqual(result.first?.sourceRange.location, 100)
        XCTAssertTrue(result.allSatisfy { $0.paragraphIndex == 7 })
        XCTAssertTrue(result.allSatisfy { NSMaxRange($0.range) <= NSMaxRange(paragraph.range) })
        XCTAssertTrue(result.allSatisfy { NSMaxRange($0.sourceRange) <= NSMaxRange(paragraph.sourceRange) })
    }

    func testNewlineUsesExistingNewlinePauseBoundary() {
        let paragraph = makeParagraph("Dong mot\nDong hai")

        let result = NghiUtteranceSegmenter.expand([paragraph], maximumLength: 100)

        XCTAssertEqual(result.map(\.text), ["Dong mot", "Dong hai"])
        XCTAssertEqual(result.map(\.boundaryKind), [.newlineEnd, .paragraphEnd])
    }

    func testWAVDurationReadsGeneratedPCMFile() {
        let sampleRate = 22_050
        let data = WAVEncoder.encodePCM16(
            samples: [Float](repeating: 0, count: sampleRate),
            sampleRate: sampleRate,
            channels: 1
        )

        XCTAssertEqual(WAVEncoder.duration(of: data), 1.0, accuracy: 0.001)
    }

    private func makeParagraph(_ text: String) -> TTSParagraph {
        TTSParagraph(
            text: text,
            range: NSRange(location: 0, length: text.utf16.count),
            paragraphIndex: 3,
            boundaryKind: .paragraphEnd
        )
    }
}
