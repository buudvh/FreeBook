import SwiftUI

@MainActor
public final class ReaderScrollCoordinator {
    public static let shared = ReaderScrollCoordinator()

    private init() {}

    @discardableResult
    public func attemptScroll(
        to target: ReaderScrollTarget,
        proxy: ScrollViewProxy,
        cache: ChapterCache,
        onComplete: @escaping () -> Void
    ) -> Bool {
        guard cache.get(target.chapterIndex)?.state == .loaded else { return false }

        if target.paragraphIndex >= 0 {
            guard let cached = cache.get(target.chapterIndex), cached.state == .loaded else { return false }
            let hasParagraph = cached.paragraphItems.contains(where: { $0.id == target.paragraphIndex })
            if hasParagraph {
                if target.reason == .ttsAuto {
                    ReaderEnergyDiagnostics.shared.recordTTSScrollExecuted()
                }
                proxy.scrollTo("paragraph-\(target.chapterIndex)-\(target.paragraphIndex)", anchor: .center)
            } else {
                if target.reason == .ttsAuto {
                    ReaderEnergyDiagnostics.shared.recordTTSScrollExecuted()
                }
                proxy.scrollTo("chapter-\(target.chapterIndex)", anchor: .top)
            }
            onComplete()
            return true
        }

        proxy.scrollTo("chapter-\(target.chapterIndex)", anchor: .top)
        onComplete()
        return true
    }
}
