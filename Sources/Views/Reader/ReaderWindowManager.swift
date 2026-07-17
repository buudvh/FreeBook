import Foundation

struct ReaderWindowManager {
    let totalChaptersCount: Int
    let previousCount: Int
    let nextCount: Int

    init(totalChaptersCount: Int, previousCount: Int = 1, nextCount: Int = 2) {
        self.totalChaptersCount = totalChaptersCount
        self.previousCount = previousCount
        self.nextCount = nextCount
    }

    func open(center: Int) -> Set<Int> {
        replaceWindow(center: center)
    }

    func slide(toAdjacent center: Int) -> Set<Int> {
        replaceWindow(center: center)
    }

    func replaceWindow(center: Int) -> Set<Int> {
        guard totalChaptersCount > 0 else { return [] }
        let safeCenter = min(max(0, center), totalChaptersCount - 1)
        let lower = max(0, safeCenter - previousCount)
        let upper = min(totalChaptersCount - 1, safeCenter + nextCount)
        guard lower <= upper else { return [] }
        return Set(lower...upper)
    }
}
