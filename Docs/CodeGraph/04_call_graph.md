---
generated_by: Antigravity
generator_version: 1.0
generated_at: 2026-07-17T23:26:29+07:00
git_commit: UNKNOWN
source_files: 93
document_version: 6
---

# Đồ thị Lời gọi Hàm (Call Graph)

Tài liệu này mô tả chi tiết đồ thị lời gọi hàm (Call Graph) của các phương thức cốt lõi trong hệ thống FreeBook.

## Ghi chú thủ công (Human Notes)
*Ghi chú thủ công của con người.*

<!-- GENERATED START -->
## Sơ Đồ Luồng Gọi Hàm (Call Graph v4.1/v5.0)

1. **Luồng Khởi Chạy Ứng Dụng & Nhận Sự Kiện Toast**:
   `FreeBookApp.swift` -> `AppLaunchRootView.task`
     ├── Lắng nghe `TTSPresentationEventCenter.shared.events` -> `ToastManager.shared.show(...)`
     └── Lắng nghe `DownloadPresentationEventCenter.shared.events` -> `ToastManager.shared.show(...)`

2. **Luồng Ghi SwiftData qua Transaction Coordinators**:
   - `ShelfView` / `BookDetailView` -> `BookTransactionCoordinator.shared.addBookToShelf(command:in:)` -> `ModelContext.save()`
   - `BookDetailView` -> `BookTransactionCoordinator.shared.updateBookMetadata(...)` / `setCurrentChapterIndex(...)`
   - `RepositoryManagerView` -> `ExtensionTransactionCoordinator.shared.upsertExtension(command:in:)` / `touchRepositoryLastUpdated(...)`

3. **Luồng Phân Trang & Tìm Kiếm Chương Đọc**:
   `ReaderView` -> `ReaderViewModel`
     ├── `ReaderChapterListPageFetcher` -> `BackgroundPagingWorker.fetchPage(bookId:minLogicalIndex:maxLogicalIndex:isTranslationEnabled:)`
     └── `BackgroundSearchWorker.searchChapters(bookId:query:isAscending:searchTrans:)` -> `ChapterStore.shared.searchChapters`
<!-- GENERATED END -->
