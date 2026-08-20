---
generated_by: Antigravity
generator_version: 1.0
generated_at: 2026-07-17T23:26:29+07:00
git_commit: UNKNOWN
source_files: 93
document_version: 4
---

# Đồ thị Kiểu dữ liệu (Type Graph)

Tài liệu này liệt kê chi tiết định nghĩa và mối quan hệ giữa các kiểu dữ liệu (Class, Struct, Enum, Protocol, Actor, Extension) trong dự án FreeBook.

## Ghi chú thủ công (Human Notes)
*Đây là khu vực con người tự viết ghi chú, AI không được phép ghi đè.*

<!-- GENERATED START -->
## Local import and chapter-search type changes (1.3.224)

* `ParserChapter` and `ParsedBook` conform to `Sendable`, allowing immutable parsed TXT data to cross into detached metadata/translation work.
* `ChapterStoreProtocol.searchChapters(bookId:query:)` removes the presentation-derived `searchTrans` argument; implementations now expose one two-column search contract.
* `BookTransactionCoordinator.insertChapterDTO` accepts optional `titleTrans` (default `nil`) so the dormant SwiftData TOC-write path preserves the same imported metadata as ChapterStore.

## Sơ Đồ Kiểu Dữ Liệu & Thực Thể (Type Graph v4.1/v5.0)

Các kiểu dữ liệu chính và mối quan hệ sau refactor:
1. **Command DTOs & Transaction Errors**:
   - `AddBookToShelfCommand`, `UpsertExtensionCommand`, `ExtensionConfigCommand`, `UpdateExtensionFolderCommand` (Immutable value structs).
   - `BookTransactionError`, `ExtensionTransactionError`, `TOCRuleImportError`, `BackgroundPagingError` (Error enums).
2. **Domain Transaction Coordinators**:
   - `BookTransactionCoordinator` (`@MainActor` singleton): Nhận `AddBookToShelfCommand`, `updateBookMetadata`, `setOnShelf`, `setCurrentChapterIndex`, `insertChapterDTO`, `updateChapterTitleTranslations`.
   - `ExtensionTransactionCoordinator` (`@MainActor` singleton): Nhận `UpsertExtensionCommand`, `ExtensionConfigCommand`, `UpdateExtensionFolderCommand`, `touchRepositoryLastUpdated`.
3. **Reader & Extension Components**:
   - `ReaderScrollCoordinator`, `ReaderSelectionCoordinator`: Điều khiển cuộn và menu chọn cho `ReaderView`.
   - `ReaderProgressScheduler`: Lập lịch lưu tiến độ đọc định kỳ cho `ReaderViewModel`.
   - `RepositoryFilterPolicy`: Lọc và sắp xếp danh sách tiện ích trong `RepositoryManagerView`.
   - `BookDetailLoader`: Tải chi tiết và danh sách chương online cho `BookDetailView`.
   - `ExtensionExecutionSnapshot`: Thread-safe copy dữ liệu tiện ích phục vụ thực thi JS cách ly.
4. **Presentation Event Stream Types**:
   - `TTSPresentationEvent`, `DownloadPresentationEvent` (Value enums).
   - `TTSPresentationEventCenter`, `DownloadPresentationEventCenter` (`AsyncStream` publishers).
<!-- GENERATED END -->
