import Foundation

internal struct TextPrefetchResult: Sendable {
    internal let dto: ProcessedChapterDTO
    internal let loadMs: Double
    internal let processMs: Double
}

/// Worker 1 chuyên trách nạp trước và chuẩn hóa văn bản DTO chương tiếp theo (Next Chapter Text Worker)
/// Độc lập hoàn toàn với Trình đọc (Reader UI) và luồng tổng hợp âm thanh (TTSAudioSynthesisWorker).
internal actor TTSChapterTextWorker {
    private var cachedResult: TextPrefetchResult?
    private var cachedKey: TTSPreparedNextChapterKey?
    private var fetchTask: Task<TextPrefetchResult?, Never>?
    private var ownerGeneration: UInt64 = 0

    internal init() {}

    /// Kích hoạt tải ngầm văn bản DTO của chương tiếp theo với ownerGeneration do TTSChapterPrefetcher làm chủ
    internal func replacePrefetch(
        ownerGeneration: UInt64,
        key: TTSPreparedNextChapterKey,
        sessionID: UUID,
        generation: Int,
        extensionInfo: TTSExtensionInfo?,
        processor: TTSBackgroundProcessor
    ) {
        if self.ownerGeneration == ownerGeneration && cachedKey == key && (cachedResult != nil || fetchTask != nil) {
            return
        }

        cancelInternal()
        self.ownerGeneration = ownerGeneration
        self.cachedKey = key

        fetchTask = Task(priority: .utility) { [weak self] in
            let loadStart = ProcessInfo.processInfo.systemUptime
            let request = ChapterContentRequest(
                bookId: key.bookId,
                chapterIndex: key.chapterIndex,
                title: key.chapterTitle,
                url: key.chapterUrl,
                host: key.chapterHost,
                bookMetadata: nil,
                extensionInfo: extensionInfo,
                forceRefresh: false
            )

            guard let result = try? await ChapterContentRepository.shared.load(request), !Task.isCancelled else {
                return nil
            }
            let loadEnd = ProcessInfo.processInfo.systemUptime
            let loadMs = (loadEnd - loadStart) * 1000

            let processStart = ProcessInfo.processInfo.systemUptime
            guard let processed = try? await processor.processChapter(
                bookId: key.bookId,
                chapterIndex: key.chapterIndex,
                chapterTitle: key.chapterTitle,
                rawContent: result.document.text.content,
                chunkLength: key.chunkLength,
                shouldTranslateRawContent: key.isTranslationEnabled,
                shouldConvertTraditionalToSimplified: key.shouldConvertTraditionalToSimplified,
                includeChapterTitle: key.includeChapterTitle,
                removeDuplicatedTitle: key.removeDuplicatedTitle,
                sessionID: sessionID,
                generation: generation
            ), !Task.isCancelled else {
                return nil
            }
            let processEnd = ProcessInfo.processInfo.systemUptime
            let processMs = (processEnd - processStart) * 1000

            let prefetchResult = TextPrefetchResult(dto: processed, loadMs: loadMs, processMs: processMs)

            if let self = self {
                await self.saveProcessedResult(prefetchResult, for: key, ownerGeneration: ownerGeneration)
            }
            return prefetchResult
        }
    }

    private func saveProcessedResult(_ result: TextPrefetchResult, for key: TTSPreparedNextChapterKey, ownerGeneration: UInt64) {
        guard self.ownerGeneration == ownerGeneration, self.cachedKey == key else { return }
        self.cachedResult = result
    }

    /// Lấy kết quả nạp trước văn bản với thời gian thực tế
    internal func getReadyResult(for key: TTSPreparedNextChapterKey, ownerGeneration: UInt64) async -> TextPrefetchResult? {
        guard self.ownerGeneration == ownerGeneration, self.cachedKey == key else { return nil }
        if let result = cachedResult {
            return result
        }
        if let task = fetchTask {
            return await task.value
        }
        return nil
    }

    /// Hủy tác vụ nạp trước và giải phóng bộ đệm văn bản (kiểm tra ownerGeneration token va key)
    internal func cancel(ownerGeneration: UInt64, key: TTSPreparedNextChapterKey? = nil) {
        guard self.ownerGeneration == ownerGeneration else { return }
        if let key = key, cachedKey != key {
            return
        }
        cancelInternal()
    }

    private func cancelInternal() {
        ownerGeneration = 0
        fetchTask?.cancel()
        fetchTask = nil
        cachedResult = nil
        cachedKey = nil
    }
}
