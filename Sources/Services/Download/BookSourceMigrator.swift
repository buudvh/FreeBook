import Foundation

/// Quản lý di chuyển dữ liệu (chương đã tải, phiên AI chat, bộ nhớ truyện AI, cấu hình dịch) khi đổi nguồn truyện.
public actor BookSourceMigrator {
    public static let shared = BookSourceMigrator()

    private init() {}

    /// Sao chép các chương đã tải từ nguồn cũ sang nguồn mới nếu chương tương ứng tồn tại theo thứ tự.
    public func migrateCachedChapters(
        oldBookId: String,
        newBookId: String,
        newChapters: [ChapterMetadataSnapshot]
    ) async {
        guard let oldChapters = try? await ChapterStore.shared.fetchOrderedTOC(bookId: oldBookId) else { return }

        for oldChapter in oldChapters where oldChapter.isCached && oldChapter.length > 0 {
            guard oldChapter.index < newChapters.count else { continue }
            guard let content = try? await BookBinManager.shared.readChapterContent(
                bookId: oldBookId,
                offset: oldChapter.offset,
                length: oldChapter.length
            ), !content.isEmpty else {
                continue
            }

            if let (newOffset, newLength) = try? await BookBinManager.shared.writeChapterContent(
                bookId: newBookId,
                content: content
            ) {
                try? await ChapterStore.shared.updateCacheMetadata(
                    bookId: newBookId,
                    index: oldChapter.index,
                    url: newChapters[oldChapter.index].url,
                    isCached: true,
                    offset: newOffset,
                    length: newLength
                )
            }
        }
    }

    /// Di chuyển các file từ điển và cấu hình dịch thuật riêng của truyện dưới `translate/books/<bookId>/`.
    public func migrateTranslationFiles(
        oldBookId: String,
        newBookId: String,
        isPlayingTTS: Bool
    ) {
        let translateDir = TranslationManager.shared.translateDirectory
        let oldDir = translateDir.appendingPathComponent("books").appendingPathComponent(oldBookId)
        let newDir = translateDir.appendingPathComponent("books").appendingPathComponent(newBookId)

        if FileManager.default.fileExists(atPath: oldDir.path) {
            try? FileManager.default.createDirectory(at: newDir, withIntermediateDirectories: true)
            let fileNames = TranslationManager.bookScopedMigrationFiles
            for name in fileNames {
                let oldFile = oldDir.appendingPathComponent(name)
                let newFile = newDir.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: oldFile.path) {
                    try? FileManager.default.removeItem(at: newFile)
                    try? FileManager.default.copyItem(at: oldFile, to: newFile)
                }
            }
            if !isPlayingTTS {
                try? FileManager.default.removeItem(at: oldDir)
            }
            QuickTranslationRuleBookStore.shared.invalidate(bookId: oldBookId)
            QuickTranslationRuleBookStore.shared.invalidate(bookId: newBookId)
            QuickTranslationRuleDisableStore.shared.invalidateCache(for: .book(oldBookId))
            QuickTranslationRuleDisableStore.shared.invalidateCache(for: .book(newBookId))
        }
    }

    /// Di chuyển phiên AI chat, bộ nhớ truyện AI và cấu hình bật/tắt dịch thuật riêng.
    public func migrateMetadataAndSettings(
        oldBookId: String,
        newBookId: String,
        isPlayingTTS: Bool
    ) {
        // 1. AI Chat sessions & Memory
        AIChatHistoryStore.shared.migrateSessions(from: oldBookId, to: newBookId)
        BookAIMemoryStore.shared.migrateMemory(from: oldBookId, to: newBookId)

        // 2. Translation override mode
        let oldOverride = TranslationConfigStore.shared.getBookOverride(bookId: oldBookId)
        if oldOverride != .inherited {
            TranslationConfigStore.shared.setBookOverride(bookId: newBookId, mode: oldOverride)
            if !isPlayingTTS {
                TranslationConfigStore.shared.setBookOverride(bookId: oldBookId, mode: .inherited)
            }
        }
    }

    /// Dọn dẹp dữ liệu lưu trữ vật lý của truyện cũ khi không phát TTS.
    public func cleanupOldBookStorage(oldBookId: String) async {
        try? await ChapterStore.shared.deleteBook(bookId: oldBookId)
        try? await BookBinManager.shared.deleteBinFile(for: oldBookId)
    }
}
