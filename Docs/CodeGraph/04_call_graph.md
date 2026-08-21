---
generated_by: Antigravity
generator_version: 1.0
generated_at: 2026-08-21T10:30:00+07:00
git_commit: UNKNOWN
source_files: 230
document_version: 7
---

# Đồ thị Lời gọi Hàm (Call Graph)

Tài liệu này mô tả chi tiết đồ thị lời gọi hàm (Call Graph) của các phương thức cốt lõi trong hệ thống FreeBook.

## Ghi chú thủ công (Human Notes)
*Ghi chú thủ công của con người.*

<!-- GENERATED START -->
## Next-chapter prefix audio call graph (1.3.234)

* `TTSManager.updatePrefetchWindow()` → `requestRemoteNextChapterPrefixIfNeeded(windowCount:inChapterTargetCount:)` → `requestNextChapterPrefix(capacity:)` → `TTSNextChapterPrefixCache.request(...)` (chỉ nhánh Google/Ext; guard `tool != "system"`, `tool != "nghitts"`).
* `TTSManager.updateNghiPrefetchWindow()` → `requestNghiNextChapterPrefixIfNeeded(currentIndex:blockedIndices:)` → `TTSManager.selectNghiOptionalRefillCandidate(...)` → `calculateNghiCachedTime()` → `requestNextChapterPrefix(capacity:)`. Được gọi **sau** nhánh `return` của slot bắt buộc `N+1` và sau `nextChapterPrefetcher.promoteAudioIfNeeded(...)`. Capacity = `maxTotalAudioPayloads - heldPayloads`, chỉ khi `cachedTime` chưa đủ ngưỡng.
* `TTSManager.calculateNghiCachedTime()` → `nextChapterPrefixContiguousDuration(matching:)` → `TTSNextChapterPrefixCache.contiguousDuration(matching:from:)`. Đây là cạnh khiến watermark cached-time đo được chuỗi phát **vượt biên chương**; nó chỉ cộng khi chunk 0 chương kế đã `.audioReady` (chuỗi liên tục) và key trùng tuyệt đối.
* `requestNextChapterPrefix(capacity:)` → `nextChapterPrefixContext()` đọc `nextChapterPrefetcher.currentState`; chỉ trả bối cảnh ở `.synthesizingAudio`/`.audioReady`, và với `nghitts` thì chunk hoá qua `NghiUtteranceSegmenter.expand(_:maximumLength: key.chunkLength)`.
* `TTSNextChapterPrefixCache.request` → `startSynthesis` → `TTSNextChapterPrefixCache.synthesize` (nonisolated static) → một trong ba: `PiperTTSService.synthesize(priority: .optionalReserve)` | `TTSAudioSynthesisWorker.synthesizeParagraph(priority: .nextChapter, offset: index, prefetchDelayMs: prefetchDelayMs)` → `GoogleTTSService.synthesize` | `... → ExtTTSService.synthesizeData`. Nhánh remote đi qua đúng bước `sleep(offset × max(300, prefetchDelayMs))` của worker nên tôn trọng cấu hình giãn request; nhánh Nghi không có bước này. Kết thúc quay về `finishSynthesis` trên MainActor (guard `generation` + `activeKey` + token theo index). Nhánh lỗi gọi `TTSManager.evaluateRefillError(_:currentAttempts:maxAttempts: 2)` để quyết định block/thử lại — dùng chung `classifyTTSError` với refill NghiTTS, không có retry task riêng.
* `TTSManager.applyNextChapter(...)` → `mergeNextChapterPrefixAudio(for:)` → `makeNextChapterKey(for:)` + `TTSNextChapterPrefixCache.consume(matching:)` → so `PreparedChunk.finalText` với `TTSReplacementManager.applyReplacements(paragraphs[index].text)` → ghi `preloadedData`/`preloadedDurations` (bỏ qua index đã có, `>= paragraphs.count`, hoặc text không khớp). Sau đó đường phát bình thường (`playAudioData` → `commitAudibleParagraphState`, hoặc `NghiAudioPlayerQueue.onTransition` → `commitAudibleParagraphState`) phát highlight từ `paragraphs[index]` như mọi chunk khác. Chạy **sau** `clearCurrentParagraphPrefetchCache()` và sau khi `preloadedData[0]` được gán, **trước** `continueStartSpeaking`.
* `TTSManager.pause()` → `cancelNextChapterPrefixWork()` → `cancelPendingWork()` (hủy task, giữ chunk đã xong).
* `TTSManager.clearAllTTSCaches()` → `resetNextChapterPrefixCache()` → `reset()`; đường này được `stopPlayback`, `tool.didSet` và `selectedVoice.didSet` dùng chung qua `clearPrefetchCache()`.

## All-source novel-search filtering call graph (1.3.225)

* `SearchView.performSearch` (all sources) → `searchableExtensions` (`activeExtensions.filter(type != "tts")`) → initialize `sourceStates` → task group calls `ExtensionManager.search` only for non-TTS extensions.
* `searchAllSourcesResultsView` and each `Xem thêm` destination consume the same filtered collection, preventing a TTS group or nested TTS search from being created.

## Local TXT translation and chapter-search call graph (1.3.224)

* Confirm import → `ShelfView.performImport` creates the Book on MainActor → detached task maps `ParserChapter` to `ChapterMetadataSnapshot(title,titleTrans,...)` → `ChapterStore.replaceFullTOC` persists both titles → per-chapter cache writes reuse the same snapshots.
* Reader chapter search → `BackgroundSearchWorker.searchChapters` → `ChapterStore.searchChapters(bookId:query:)` → SQLite OR-matches original and translated title; `isTranslationEnabled` is consulted only after matching to choose the displayed title.
* BookDetail local TOC search OR-matches `StoredChapterSnapshot.title/titleTrans` (and the SwiftData fallback matches `Chapter.title/titleTrans`) without consulting the translation toggle.

## TXT import confirmation handoff call graph (1.3.223)

* Parse nền thành công → `MainActor` gán `pendingImport` trong khi `isParsingTXT` vẫn bật → SwiftUI trình bày `TXTImportConfirmationSheet` → sheet `onAppear` đặt `isParsingTXT = false`.
* Parse thất bại → xóa file tạm → `MainActor` tắt `isParsingTXT` → log file + Toast. Hủy/xác nhận sheet tiếp tục đi qua `cancelImport`/`performImport` hiện có.

## Shelf/History translation and original chapter progress call graph (1.3.222)

* Author row: `BookListItemView.body` → `displayedAuthor` → toggle tắt trả `item.author`; toggle bật gọi `TranslateUtils.translateAuthorHanViet(item.author)`.
* Reader progress: `progressSnapshot` → `originalChapterTitle(at:)` → `CachedChapter.originalTitle` / `onlineChapters[index].name` → `ReadingProgressStore.persist` → `Book.currentChapterTitle`. `chapterTitle(at:)`/`CachedChapter.title` vẫn chỉ thuộc đường hiển thị.
* Dịch lại TOC: `ShelfView.retranslateChapterTitles` → dịch từ `StoredChapterSnapshot.title` → `ChapterStore.updateTitleTranslations`; không còn gọi `BookTransactionCoordinator.updateCurrentChapterTitle` — hàm này sau đó hết caller và đã bị xoá ở 1.3.235.

## TTS replacement rule add/upsert call graph (1.3.221)

* `ReaderView.AddTTSReplacementSheet.onAdd` hoặc `TTSReplacementManagerView.saveRule` (nhánh thêm) → tạo `TTSReplacementRule` → `TTSReplacementManager.addRule(_:)` → tạo bản sao danh sách → `removeAll(pattern == newRule.pattern)` → `append(newRule)` → publish danh sách cuối → `saveRules()`.
* `addRule(_:)` trả `.replaced` nếu ít nhất một rule cũ bị xóa, ngược lại trả `.added`; Reader dùng kết quả để chọn nội dung Toast, còn màn quản lý bỏ qua kết quả nhờ `@discardableResult`.

## Sơ Đồ Luồng Gọi Hàm (Call Graph v4.1/v5.0)

1. **Luồng Khởi Chạy Ứng Dụng & Nhận Sự Kiện Toast**:
   `FreeBookApp.swift` -> `AppLaunchRootView.task`
     ├── Lắng nghe `TTSPresentationEventCenter.shared.stream` -> `ToastManager.shared.show(...)`
     └── Lắng nghe `DownloadPresentationEventCenter.shared.stream` -> `ToastManager.shared.show(...)`

2. **Luồng Ghi SwiftData qua Transaction Coordinators**:
   - `ShelfView` / `BookDetailView` -> `BookTransactionCoordinator.shared.addBookToShelf(command:in:)` -> `ModelContext.save()`
   - `BookDetailView` -> `BookTransactionCoordinator.shared.updateBookMetadata(...)` / `setCurrentChapterIndex(...)`
   - `RepositoryManagerView` -> `ExtensionTransactionCoordinator.shared.upsertExtension(command:in:)` / `touchRepositoryLastUpdated(...)`

3. **Luồng Phân Trang & Tìm Kiếm Chương Đọc**:
   `ReaderView` -> `ReaderViewModel`
     ├── `ReaderChapterListPageFetcher` -> `BackgroundPagingWorker.fetchPage(bookId:minLogicalIndex:maxLogicalIndex:isTranslationEnabled:)`
     └── `BackgroundSearchWorker.searchChapters(bookId:query:isAscending:isTranslationEnabled:)` -> `ChapterStore.shared.searchChapters(bookId:query:)`

4. **Luồng NghiTTS khi đoạn sau tiền xử lý không thể đọc**:
   `TTSManager.scheduleNghiRefill()` -> `PiperTTSService.synthesizeWithDuration(...)` -> `TextPreprocessor.preprocess(...)`
     ├── Có nội dung đọc được -> `ONNXPiperEngine.synthesizeWithDuration(...)`
     └── Rỗng/chỉ dấu câu -> `PiperTTSService.makeSilenceSpec(...)` -> `WAVEncoder.encodePCM16(...)`
   - Lỗi prefetch tạm thời -> `evaluateRefillError(...)` -> retry backoff 1 giây (`Task.sleep`, tối đa 2 lần) -> `updateNghiPrefetchWindow()`.
   - Lỗi không retry hoặc đủ hai attempt -> đánh dấu index bị block -> chọn ứng viên prefetch khác.
<!-- GENERATED END -->
