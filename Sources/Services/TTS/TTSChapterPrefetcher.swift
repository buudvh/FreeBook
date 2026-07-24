import Foundation

@MainActor
public final class TTSChapterPrefetcher {
    private var preloadedWavs: [Int: URL] = [:]
    private var currentChapterIndex: Int = -1

    public init() {}

    public func getPreloadedWav(for index: Int) -> URL? {
        return preloadedWavs[index]
    }

    public func setPreloadedWav(_ url: URL, for index: Int) {
        preloadedWavs[index] = url
    }

    public func updateSlidingWindow(currentIndex: Int) {
        self.currentChapterIndex = currentIndex
        // Retain only current index N and next index N+1 (Sliding Window [N, N+1])
        let allowed = Set([currentIndex, currentIndex + 1])
        let keysToRemove = preloadedWavs.keys.filter { !allowed.contains($0) }

        for key in keysToRemove {
            if let fileUrl = preloadedWavs.removeValue(forKey: key) {
                try? FileManager.default.removeItem(at: fileUrl)
            }
        }
    }

    public func clearAllCache() {
        for (_, fileUrl) in preloadedWavs {
            try? FileManager.default.removeItem(at: fileUrl)
        }
        preloadedWavs.removeAll()
        currentChapterIndex = -1
    }
}
