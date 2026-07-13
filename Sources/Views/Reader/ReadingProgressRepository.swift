import SwiftData
import Foundation

@available(iOS 17.0, *)
actor ReadingProgressRepository: ModelActor {
    nonisolated let modelContainer: ModelContainer
    nonisolated let modelExecutor: any ModelExecutor
    
    init(container: ModelContainer) {
        self.modelContainer = container
        let context = ModelContext(container)
        context.autosaveEnabled = false
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: context)
    }
    
    // Ghi tiến trình đọc chạy ngầm hoàn toàn trên Background Thread của ModelActor
    func saveProgress(bookId: String, progress: ReadingProgress) async throws {
        let context = modelContext
        let predicate = #Predicate<Book> { $0.bookId == bookId }
        let descriptor = FetchDescriptor<Book>(predicate: predicate)
        
        if let book = try context.fetch(descriptor).first {
            book.currentChapterIndex = progress.chapterIndex
            book.currentChapterPage = progress.paragraphIndex
            book.lastReadDate = Date()
            book.isHistory = true
            
            // Tìm tiêu đề chương tương ứng
            if let chapter = book.chapters.first(where: { $0.index == progress.chapterIndex }) {
                book.currentChapterTitle = chapter.title
            }
            
            try context.save()
            #if DEBUG
            AppLogger.shared.log("💾 [ReadingProgressRepository] Đã ghi bền vững: Chương \(progress.chapterIndex), Đoạn \(progress.paragraphIndex)")
            #endif
        }
    }
}
