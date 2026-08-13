import Foundation

/// Worker 1 chuyên trách nạp trước và chuẩn hóa văn bản DTO chương tiếp theo (Next Chapter Text Worker)
/// Độc lập hoàn toàn với Trình đọc (Reader UI) và luồng tổng hợp âm thanh (TTSAudioSynthesisWorker).
public actor TTSChapterTextWorker {
    private var cachedDTO: ProcessedChapterDTO?
    private var cachedKey: TTSPreparedNextChapterKey?
    private var fetchTask: Task<ProcessedChapterDTO?, Never>?
    private var activeGeneration: UInt64 = 0

    public init() {}

    /// Kiểm tra xem có cần nạp trước văn bản chương hay không dựa trên điều kiện tiến độ nghe
    public func shouldTriggerPrefetch(
        isPlaying: Bool,
        currentParagraphIndex: Int,
        totalParagraphs: Int,
        remainingParentCount: Int,
        nextKey: TTSPreparedNextChapterKey
    ) -> Bool {
        guard isPlaying, totalParagraphs > 0 else { return false }
        if cachedKey == nextKey && (cachedDTO != nil || fetchTask != nil) {
            return false
        }
        
        // Điều kiện kích hoạt: Nghe >= 50% số đoạn HOẶC còn <= 3 đoạn văn cha
        let isPastHalfway = currentParagraphIndex >= totalParagraphs / 2
        let isNearEnd = remainingParentCount <= 3
        
        return isPastHalfway || isNearEnd
    }

    /// Kích hoạt tải ngầm văn bản DTO của chương tiếp theo
    public func startPrefetch(
        key: TTSPreparedNextChapterKey,
        sessionID: UUID,
        generation: Int,
        extensionInfo: TTSExtensionInfo?,
        processor: TTSBackgroundProcessor
    ) {
        if cachedKey == key && (cachedDTO != nil || fetchTask != nil) {
            return
        }

        cancel()
        activeGeneration += 1
        let currentGen = activeGeneration
        cachedKey = key

        fetchTask = Task(priority: .utility) { [weak self] in
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

            if let self = self {
                await self.saveProcessedDTO(processed, for: key, generation: currentGen)
            }
            return processed
        }
    }

    private func saveProcessedDTO(_ dto: ProcessedChapterDTO, for key: TTSPreparedNextChapterKey, generation: UInt64) {
        guard generation == activeGeneration else { return }
        self.cachedDTO = dto
        self.cachedKey = key
    }

    /// Lấy sẵn DTO chương kế đã nạp trước (nếu có)
    public func getReadyDTO(for key: TTSPreparedNextChapterKey) async -> ProcessedChapterDTO? {
        if cachedKey == key, let dto = cachedDTO {
            return dto
        }
        if cachedKey == key, let task = fetchTask {
            return await task.value
        }
        return nil
    }

    /// Hủy tác vụ nạp trước và giải phóng bộ đệm văn bản
    public func cancel() {
        activeGeneration += 1
        fetchTask?.cancel()
        fetchTask = nil
        cachedDTO = nil
        cachedKey = nil
    }
}
