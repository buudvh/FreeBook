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
## TXT import confirmation handoff call graph (1.3.223)

* Parse nền thành công → `MainActor` gán `pendingImport` trong khi `isParsingTXT` vẫn bật → SwiftUI trình bày `TXTImportConfirmationSheet` → sheet `onAppear` đặt `isParsingTXT = false`.
* Parse thất bại → xóa file tạm → `MainActor` tắt `isParsingTXT` → log file + Toast. Hủy/xác nhận sheet tiếp tục đi qua `cancelImport`/`performImport` hiện có.

## Shelf/History translation and original chapter progress call graph (1.3.222)

* Author row: `BookListItemView.body` → `displayedAuthor` → toggle tắt trả `item.author`; toggle bật gọi `TranslateUtils.translateAuthorHanViet(item.author)`.
* Reader progress: `progressSnapshot` → `originalChapterTitle(at:)` → `CachedChapter.originalTitle` / `onlineChapters[index].name` → `ReadingProgressStore.persist` → `Book.currentChapterTitle`. `chapterTitle(at:)`/`CachedChapter.title` vẫn chỉ thuộc đường hiển thị.
* Dịch lại TOC: `ShelfView.retranslateChapterTitles` → dịch từ `StoredChapterSnapshot.title` → `ChapterStore.updateTitleTranslations`; không còn gọi `BookTransactionCoordinator.updateCurrentChapterTitle`.

## TTS replacement rule add/upsert call graph (1.3.221)

* `ReaderView.AddTTSReplacementSheet.onAdd` hoặc `TTSReplacementManagerView.saveRule` (nhánh thêm) → tạo `TTSReplacementRule` → `TTSReplacementManager.addRule(_:)` → tạo bản sao danh sách → `removeAll(pattern == newRule.pattern)` → `append(newRule)` → publish danh sách cuối → `saveRules()`.
* `addRule(_:)` trả `.replaced` nếu ít nhất một rule cũ bị xóa, ngược lại trả `.added`; Reader dùng kết quả để chọn nội dung Toast, còn màn quản lý bỏ qua kết quả nhờ `@discardableResult`.

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

4. **Luồng NghiTTS khi đoạn sau tiền xử lý không thể đọc**:
   `TTSManager.scheduleNghiRefill()` -> `PiperTTSService.synthesizeWithDuration(...)` -> `TextPreprocessor.preprocess(...)`
     ├── Có nội dung đọc được -> `ONNXPiperEngine.synthesizeWithDuration(...)`
     └── Rỗng/chỉ dấu câu -> `PiperTTSService.makeSilenceSpec(...)` -> `WAVEncoder.encodePCM16(...)`
   - Lỗi prefetch tạm thời -> `evaluateRefillError(...)` -> task cooldown 1 giây -> `updateNghiPrefetchWindow()`.
   - Lỗi không retry hoặc đủ hai attempt -> đánh dấu index bị block -> chọn ứng viên prefetch khác.
<!-- GENERATED END -->
