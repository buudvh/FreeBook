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
     ├── `ReaderChapterListStore.fetchPageData` -> `BackgroundPagingWorker.fetchPage(bookId:minLogicalIndex:maxLogicalIndex:isTranslationEnabled:)`
     └── `BackgroundSearchWorker.searchChapters(bookId:query:isAscending:searchTrans:)` -> `ChapterStore.shared.searchChapters`

4. **Luồng NghiTTS khi đoạn sau tiền xử lý không thể đọc**:
   `TTSManager.scheduleNghiRefill()` -> `PiperTTSService.synthesizeWithDuration(...)` -> `TextPreprocessor.preprocess(...)`
     ├── Có nội dung đọc được -> `ONNXPiperEngine.synthesizeWithDuration(...)`
     └── Rỗng/chỉ dấu câu -> `PiperTTSService.makeSilenceSpec(...)` -> `WAVEncoder.encodePCM16(...)`
   - Lỗi prefetch tạm thời -> `evaluateRefillError(...)` -> task cooldown 1 giây -> `updateNghiPrefetchWindow()`.
   - Lỗi không retry hoặc đủ hai attempt -> đánh dấu index bị block -> chọn ứng viên prefetch khác.

5. **Luồng mở Reader/Detail từ root presentation hub (DetailRouter/ReaderRouter)**:
   `ShelfView` / `ShelfSearchView` / `BookDetailView+TOCPreparation` -> set `readerRouter.route` (`@EnvironmentObject`)
   └── `AppLaunchRootView.fullScreenCover(item: $readerRouter.route)` -> `NavigationStack { ReaderView.id(route.id) }` (root-level cover)
   - Đóng reader: `ReaderView.closeReader()` -> fallback `dismiss()` -> `fullScreenCover(item:)` tự set `readerRouter.route = nil`.
   - Mở Detail: `ShelfView` / `SearchView` / `DiscoveryView` / `CategoryNovelsListView` / `SuggestRowView` / `ReaderView` / `ReaderChapterListView` / `BookDetailView` -> set `detailRouter.route` -> `AppLaunchRootView.fullScreenCover(item: $detailRouter.route)` -> `NavigationStack { BookDetailView }`.
   - Reader và Detail present từ CÙNG presenter (AppLaunchRootView) nên cover xếp chồng đúng — back từ Reader quay về Detail, không thoát hẳn.
<!-- GENERATED END -->
