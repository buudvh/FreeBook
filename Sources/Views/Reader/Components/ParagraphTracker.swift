import SwiftUI



@MainActor
public class ParagraphTracker {
    private static let minimumFrameDelta: CGFloat = 8
    private var visibleParagraphs: Set<ReadingContext> = []
    private var frames: [ReadingContext: ParagraphFrame] = [:]

    public init() {}

    public func insert(bookId: String, chapterIndex: Int, paragraphIndex: Int) {
        visibleParagraphs.insert(ReadingContext(bookId: bookId, chapterIndex: chapterIndex, paragraphIndex: paragraphIndex))
    }

    public func updateFrame(bookId: String, chapterIndex: Int, paragraphIndex: Int, minY: CGFloat, maxY: CGFloat) {
        let ctx = ReadingContext(bookId: bookId, chapterIndex: chapterIndex, paragraphIndex: paragraphIndex)
        if let previous = frames[ctx],
           abs(previous.minY - minY) < Self.minimumFrameDelta,
           abs(previous.maxY - maxY) < Self.minimumFrameDelta {
            ReaderEnergyDiagnostics.shared.recordParagraphFrameUpdate(accepted: false)
            return
        }
        visibleParagraphs.insert(ctx)
        frames[ctx] = ParagraphFrame(bookId: bookId, chapterIndex: chapterIndex, paragraphIndex: paragraphIndex, minY: minY, maxY: maxY)
        ReaderEnergyDiagnostics.shared.recordParagraphFrameUpdate(accepted: true)
    }

    public func remove(bookId: String, chapterIndex: Int, paragraphIndex: Int) {
        let ctx = ReadingContext(bookId: bookId, chapterIndex: chapterIndex, paragraphIndex: paragraphIndex)
        visibleParagraphs.remove(ctx)
        frames.removeValue(forKey: ctx)
    }

    public func removeAll() {
        visibleParagraphs.removeAll()
        frames.removeAll()
    }

    public func isParagraphInsideSafeViewport(
        bookId: String,
        chapterIndex: Int,
        paragraphIndex: Int,
        viewportMinY: CGFloat,
        viewportMaxY: CGFloat
    ) -> Bool {
        guard viewportMaxY > viewportMinY else { return false }
        let context = ReadingContext(bookId: bookId, chapterIndex: chapterIndex, paragraphIndex: paragraphIndex)
        guard let frame = frames[context] else { return false }

        let viewportHeight = viewportMaxY - viewportMinY
        let safeInset = min(120, max(60, viewportHeight * 0.15))
        let safeMinY = viewportMinY + safeInset
        let safeMaxY = viewportMaxY - safeInset
        let midpoint = (frame.minY + frame.maxY) / 2
        return midpoint >= safeMinY && midpoint <= safeMaxY
    }

    public func getTopVisible(viewportTopY: CGFloat, currentBookId: String, currentChapterIndex: Int) -> ReadingContext? {
        let candidates = frames.values.filter {
            $0.bookId == currentBookId &&
            $0.chapterIndex == currentChapterIndex &&
            $0.maxY > viewportTopY + 5
        }

        if !candidates.isEmpty {
            let sorted = candidates.sorted {
                if abs($0.minY - $1.minY) < 1.0 {
                    return $0.paragraphIndex < $1.paragraphIndex
                }
                return $0.minY < $1.minY
            }
            if let best = sorted.first {
                return ReadingContext(bookId: best.bookId, chapterIndex: best.chapterIndex, paragraphIndex: best.paragraphIndex)
            }
        }

        return topVisible
    }

    public var topVisible: ReadingContext? {
        visibleParagraphs.sorted {
            if $0.chapterIndex == $1.chapterIndex {
                return $0.paragraphIndex < $1.paragraphIndex
            }
            return $0.chapterIndex < $1.chapterIndex
        }.first
    }
}
