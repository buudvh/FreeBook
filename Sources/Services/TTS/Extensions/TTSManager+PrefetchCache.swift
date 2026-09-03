import Foundation

extension TTSManager {
    public func clearCurrentParagraphPrefetchCache() {
        cancelNghiPlaybackTask()
        cancelNghiRefill()
        cancelClaimedSynthesisTask()
        remotePlaybackTask?.cancel()
        remotePlaybackTask = nil
        cancelRemotePrefetchTasks()
        preloadedData.removeAll()
        preloadedDurations.removeAll()
        nghiAudioPlayerQueue.clearPreparedNext()
    }

    public func clearAllTTSCaches() {
        clearCurrentParagraphPrefetchCache()
        nextChapterPrefetcher.cancel()
        resetNextChapterPrefixCache()
        Task {
            await audioSynthesisWorker.cancelPrefetchTasks()
            await extService.resetRuntime()
        }
    }

    public func clearPrefetchCache() {
        clearAllTTSCaches()
    }

    internal func cancelRemotePrefetchTasks() {
        for task in prefetchTasks.values {
            task.cancel()
        }
        prefetchTasks.removeAll()
        prefetchTaskGenerations.removeAll()
    }

    internal func cancelNghiPlaybackTask() {
        nghiPlaybackTaskGeneration &+= 1
        nghiPlaybackTask?.cancel()
        nghiPlaybackTask = nil
    }
}
