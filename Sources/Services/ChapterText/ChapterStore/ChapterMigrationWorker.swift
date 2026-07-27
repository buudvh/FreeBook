import Foundation
import SwiftData

internal final class ChapterMigrationWorker: Sendable {
    internal static let shared = ChapterMigrationWorker()

    private let isRunningState = ManagedAtomicBool(false)

    private init() {}

    internal func startMigrationIfNecessary(container: ModelContainer) {
        guard ChapterStoreConfiguration.enableChapterStoreMigration else { return }
        guard isRunningState.compareExchange(expected: false, new: true) else { return }

        Task.detached(priority: .utility) {
            await self.runMigrationLoop(container: container)
            self.isRunningState.set(false)
        }
    }

    private func runMigrationLoop(container: ModelContainer) async {
        var cursorBookId = UserDefaults.standard.string(forKey: "chapterstore_migration_cursor") ?? ""
        var processedCount = 0
        var failedCount = 0
        var isRescanPass = false

        while !Task.isCancelled {
            let bgContext = ModelContext(container)
            bgContext.autosaveEnabled = false

            let currentCursor = cursorBookId
            let descriptor = FetchDescriptor<Book>(
                predicate: #Predicate<Book> { $0.bookId > currentCursor },
                sortBy: [SortDescriptor(\.bookId, order: .forward)]
            )

            var books: [Book] = []
            do {
                var limitedDescriptor = descriptor
                limitedDescriptor.fetchLimit = 1
                books = try bgContext.fetch(limitedDescriptor)
            } catch {
                AppLogger.shared.log("❌ [ChapterStore Migration] Fetch error code: 101")
                break
            }

            if books.isEmpty {
                if !isRescanPass {
                    // Rescan pass starting from beginning for any unmigrated/failed books
                    cursorBookId = ""
                    isRescanPass = true
                    continue
                } else {
                    AppLogger.shared.log("[ChapterStore Migration] Complete | processed: \(processedCount), failed: \(failedCount) | status: complete")
                    break
                }
            }

            guard let book = books.first else { break }

            let bookId = book.bookId
            let chapters = book.chapters

            // Check if already migrated
            if let statusInfo = try? await ChapterStore.shared.getMigrationStatus(bookId: bookId), statusInfo.status == "migrated" {
                cursorBookId = bookId
                UserDefaults.standard.set(cursorBookId, forKey: "chapterstore_migration_cursor")
                continue
            }

            do {
                let snapshots = chapters.map { ch in
                    StoredChapterSnapshot(
                        id: ch.id,
                        bookId: bookId,
                        title: ch.title,
                        url: ch.url,
                        index: ch.index,
                        host: ch.host,
                        titleTrans: ch.titleTrans,
                        isCached: ch.isCached,
                        offset: ch.offset,
                        length: ch.length
                    )
                }
                let statusInfo = MigrationStatusInfo(
                    bookId: bookId,
                    status: "migrated",
                    schemaVersion: 1,
                    migratedCount: chapters.count
                )

                // Single atomic transaction for entire book (snapshots + status)
                try await ChapterStore.shared.importBookMigration(bookId: bookId, snapshots: snapshots, statusInfo: statusInfo)

                cursorBookId = bookId
                UserDefaults.standard.set(cursorBookId, forKey: "chapterstore_migration_cursor")
                processedCount += 1
                AppLogger.shared.log("[ChapterStore Migration] processed: \(processedCount), failed: \(failedCount) | status: progress")
            } catch {
                failedCount += 1
                try? await ChapterStore.shared.updateMigrationStatus(bookId: bookId, status: "failed", migratedCount: 0)
                // Stop loop on error so failed book is not skipped without retrying next launch
                AppLogger.shared.log("❌ [ChapterStore Migration] Migration failed for book, stopping worker pass.")
                break
            }

            do {
                try await Task.sleep(nanoseconds: 10_000_000)
            } catch {
                break
            }
        }
    }
}

private final class ManagedAtomicBool: @unchecked Sendable {
    private var value: Bool
    private let lock = NSLock()

    init(_ initial: Bool) {
        self.value = initial
    }

    func compareExchange(expected: Bool, new: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if value == expected {
            value = new
            return true
        }
        return false
    }

    func set(_ new: Bool) {
        lock.lock()
        defer { lock.unlock() }
        value = new
    }
}
