import Foundation
import Combine

/// Xây lại toàn bộ chỉ mục tìm toàn văn từ các chương **đã cache** trong `.bin`.
///
/// Chỉ mục là dữ liệu phái sinh nên không có migration: bật tính năng lên thì phải xây lại một
/// lượt, và mọi lần đổi tokenizer/schema sau này cũng chỉ cần xây lại. Danh sách truyện do tầng
/// View truyền vào (`Target`) — tầng Services không được đọc SwiftData bằng `@Query`, và bơm
/// `ModelContainer` vào đây chỉ để lấy `bookId` là thừa.
///
/// `ObservableObject` ở tầng Services là hợp lệ (tiền lệ `NewChapterInboxManager`) miễn không
/// `import SwiftUI` và không gọi `ToastManager`.
@MainActor
internal final class ChapterSearchIndexBuilder: ObservableObject {
    /// Một truyện cần xây chỉ mục. `title` chỉ để hiện tiến độ.
    internal struct Target: Sendable {
        internal let bookId: String
        internal let title: String

        internal init(bookId: String, title: String) {
            self.bookId = bookId
            self.title = title
        }
    }

    /// Kết quả một lượt xây chỉ mục.
    internal struct Summary: Sendable {
        internal let indexedChapters: Int
        internal let skippedChapters: Int
        internal let wasCancelled: Bool
    }

    internal static let shared = ChapterSearchIndexBuilder()

    @Published internal private(set) var isRunning = false
    @Published internal private(set) var totalChapters = 0
    @Published internal private(set) var processedChapters = 0
    @Published internal private(set) var currentBookTitle = ""
    @Published internal private(set) var lastSummary: Summary?

    private var task: Task<Void, Never>?

    private init() {}

    internal var progressFraction: Double {
        guard totalChapters > 0 else { return 0 }
        return min(1.0, Double(processedChapters) / Double(totalChapters))
    }

    /// Xây lại chỉ mục từ đầu: xoá sạch rồi nạp lại mọi chương đã cache. Gọi lại khi đang chạy thì
    /// bị bỏ qua.
    internal func rebuild(targets: [Target]) {
        guard !isRunning else { return }
        isRunning = true
        totalChapters = 0
        processedChapters = 0
        currentBookTitle = ""
        lastSummary = nil

        task = Task { [self] in
            let summary = await Self.run(
                targets: targets,
                onTotal: { total in await self.applyTotal(total) },
                onProgress: { processed, title in await self.applyProgress(processed, title: title) }
            )
            finish(with: summary)
        }
    }

    internal func cancel() {
        task?.cancel()
    }

    private func applyTotal(_ total: Int) {
        totalChapters = total
    }

    private func applyProgress(_ processed: Int, title: String) {
        processedChapters = processed
        currentBookTitle = title
    }

    private func finish(with summary: Summary) {
        lastSummary = summary
        isRunning = false
        currentBookTitle = ""
        task = nil
    }

    /// Phần chạy nền thuần: `nonisolated` để vòng lặp không chạy trên Main Thread, và không chạm
    /// `@Published` — chỉ báo ngược qua hai closure.
    private nonisolated static func run(
        targets: [Target],
        onTotal: @Sendable (Int) async -> Void,
        onProgress: @Sendable (Int, String) async -> Void
    ) async -> Summary {
        await ChapterSearchIndex.shared.clear()

        // Lượt 1: đếm để có tổng thật, tránh thanh tiến độ nhảy giật.
        var plan: [(target: Target, chapters: [StoredChapterSnapshot])] = []
        var total = 0
        for target in targets {
            if Task.isCancelled { break }
            let toc = (try? await ChapterStore.shared.fetchOrderedTOC(bookId: target.bookId)) ?? []
            let cached = toc.filter { $0.isCached && $0.length > 0 }
            guard !cached.isEmpty else { continue }
            plan.append((target, cached))
            total += cached.count
        }
        await onTotal(total)

        var indexed = 0
        var skipped = 0
        var processed = 0
        for entry in plan {
            if Task.isCancelled { break }
            for chapter in entry.chapters {
                if Task.isCancelled { break }
                do {
                    let content = try await BookBinManager.shared.readChapterContent(
                        bookId: chapter.bookId,
                        offset: chapter.offset,
                        length: chapter.length
                    )
                    if content.isEmpty {
                        skipped += 1
                    } else {
                        await ChapterSearchIndex.shared.indexChapter(
                            bookId: chapter.bookId,
                            chapterIndex: chapter.index,
                            chapterUrl: chapter.url,
                            chapterTitle: chapter.title,
                            content: content
                        )
                        indexed += 1
                    }
                } catch {
                    skipped += 1
                }
                processed += 1
                if processed % ChapterSearchPolicy.builderYieldInterval == 0 {
                    await onProgress(processed, entry.target.title)
                    try? await Task.sleep(nanoseconds: 1_000_000)
                }
            }
            await onProgress(processed, entry.target.title)
        }

        return Summary(indexedChapters: indexed, skippedChapters: skipped, wasCancelled: Task.isCancelled)
    }
}
