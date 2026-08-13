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
    private var activeGeneration: UInt64 = 0

    internal init() {}

    /// Kiểm tra xem có cần nạp trước văn bản chương hay không dựa trên điều kiện tiến độ nghe
    internal func shouldTriggerPrefetch(
        isPlaying: Bool,
        currentParagraphIndex: Int,
        totalParagraphs: Int,
        remainingParentCount: Int,
        nextKey: TTSPreparedNextChapterKey
    ) -> Bool {
        guard isPlaying, totalParagraphs > 0 else { return false }
        if cachedKey == nextKey && (cachedResult != nil || fetchTask != nil) {
            return false
        }
        
        let isPastHalfway = currentParagraphIndex >= totalParagraphs / 2
        let isNearEnd = remainingParentCount <= 3
        
        return isPastHalfway || isNearEnd
    }

    /// Kích hoạt tải ngầm văn bản DTO của chương tiếp theo với đo đạc thời gian thực tế
    internal func startPrefetch(
        key: TTSPreparedNextChapterKey,
        sessionID: UUID,
        generation: Int,
        extensionInfo: TTSExtensionInfo?,
        processor: TTSBackgroundProcessor
    ) {
        if cachedKey == key && (cachedResult != nil || fetchTask != nil) {
            return
        }

        cancel()
        activeGeneration += 1
        let currentGen = activeGeneration
        cachedKey = key

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
                includeChapterTitle: key.includeChapterTitle,
                sessionID: sessionID,
                generation: generation
            ), !Task.isCancelled else {
                return nil
            }
            let processEnd = ProcessInfo.processInfo.systemUptime
            let processMs = (processEnd - processStart) * 1000

            let prefetchResult = TextPrefetchResult(dto: processed, loadMs: loadMs, processMs: processMs)

            if let self = self {
                await self.saveProcessedResult(prefetchResult, for: key, generation: currentGen)
            }
            return prefetchResult
        }
    }

    private func saveProcessedResult(_ result: TextPrefetchResult, for key: TTSPreparedNextChapterKey, generation: UInt64) {
        guard generation == activeGeneration else { return }
        self.cachedResult = result
        self.cachedKey = key
    }

    /// Lấy kết quả nạp trước văn bản với thời gian thực tế
    internal func getReadyResult(for key: TTSPreparedNextChapterKey) async -> TextPrefetchResult? {
        if cachedKey == key, let result = cachedResult {
            return result
        }
        if cachedKey == key, let task = fetchTask {
            return await task.value
        }
        return nil
    }

    /// Hủy tác vụ nạp trước và giải phóng bộ đệm văn bản
    internal func cancel() {
        activeGeneration += 1
        fetchTask?.cancel()
        fetchTask = nil
        cachedResult = nil
        cachedKey = nil
    }
}
