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
## Đường copy từ điển và đường dựng widget trình duyệt (1.3.244)

* Đường copy (8 tổ hợp, **hai** đích cuối): `DictionaryHubView` (chủ `bookId`) → `DictionaryListView(type:bookId:contextBookId:)` → `DictionaryEntryRow` (Menu) → `onTransfer(destinationType, target)` → `DictionaryListView.copyEntry(_:to:target:)` (`+Transfer`) → `DictionaryEntryTransferAction.copy(...)` → **hoặc** `DictionaryCache.shared.upsertEntry(key:value:type:)` (đích chung custom) **hoặc** `TranslationManager.shared.saveCustomEntry(word:meaning:isName:bookId:)` (đích riêng). Không có cạnh nào tới bộ nạp `.dat` — đường ghi built-in **không tồn tại** trong đồ thị.
* `transferContextBookId` là `bookId ?? contextBookId`: ở danh sách riêng thì chính scope của nó, ở danh sách chung thì sách đang mở màn Từ điển. Khi cả hai `nil` (không thể xác định sách), `DictionaryEntryRow` gọi `onMissingContext()` → `reportMissingTransferContext()` → toast lỗi, **không** phát cạnh nào tới tầng ghi. Không có cạnh nào tới book picker, tới `TTSManager` hay tới "sách mở gần nhất".
* Đường tìm kiếm truyện đích: `BookShareTargetSheet` → `BookSearchBarView` (`@Binding searchQuery`) → computed `filteredBooks` → `ShelfBookSearchMatcher.matches(query:title:titleTrans:author:authorTrans:)`. Cạnh này là *thêm mới* trước `List`, không chen vào đường chọn đích (`dictionaryModeDialog` → callback cũ) — đường chọn đích không đổi chữ nào.
* `ShelfSearchView.searchBarView` nay chỉ còn một cạnh: `→ BookSearchBarView(text:onCommit:)`, với `onCommit` giữ nguyên `SearchHistoryStore.addQuery(_:to:)`.
* Đường mở trình duyệt: `VisibleBrowserTabManager.openTab(...)` → `openContainer(initialActiveId:)` → **rẽ theo `VisibleBrowserSettings.opensMinimized`**: `presentContainerView(initialActiveId:)` (như cũ) hoặc `prepareContainerMinimized()` → `TabbedVisibleBrowserViewController.loadViewIfNeeded()` → `viewDidLoad` → `reloadTabs()` → `displayChildViewController(activeItem.loader.viewController)`. Nhánh thu nhỏ **không** gọi `present(_:animated:)` ở đâu cả. `dismissContainer()` ở nhánh re-present cũng đi qua `openContainer(initialActiveId:)` nên tôn trọng cùng cài đặt.
* Đường nháy: `VisibleBrowserTabManager.notifyStateChanged()` → `stateDidChangeNotification` → `VisibleBrowserPulseMonitor.evaluate()` → `setPulsing(_:)` → `@Published isPulsing` → `VisibleBrowserReopenButton.onChange` → `isDimmed` → `.opacity`. `evaluate()` chỉ tự gọi lại qua **một** `Timer` one-shot hẹn đúng phần thời gian còn thiếu tới 10 s; không có cạnh polling nào.
* Đường hiện/ẩn window widget: cùng notification → `BrowserFloatingWidgetWindowManager.refreshState()` → `showWidget()`/`hideWidget()`; thêm ba cạnh từ `AppLaunchRootView` (`.onAppear`, `onChange(of: translationManager.isInitialized)`, `onChange(of: browserPresentation.snapshot.showReopenButton)`). Cạnh cũ `AppLaunchRootView → VisibleBrowserReopenButton` (trong `ZStack`, `zIndex(9998)`) **đã bị xoá** — widget không còn nằm trong cây view của app.
* Đường kéo/thả: `UIPanGestureRecognizer → BrowserFloatingWidgetContainerViewController.handlePan` → ghi `widgetContainerView.center` trực tiếp (`.changed`), rồi `.ended` → `VisibleBrowserReopenViewModel.handleDragEnd(...)` → `FloatingWidgetGeometry.nearestEdge/clampedCenterY` → `updateLayout(animated: true)`. `UITapGestureRecognizer → handleTap` → `VisibleBrowserTabManager.reopenContainer()`, guard `!viewModel.isDragging`; `shouldRecognizeSimultaneouslyWith` trả `false` nên tap và pan không cùng nổ.
* TTS widget: `FloatingWidgetViewModel.handleDragEnd` và `FloatingWidgetContainerViewController.restingCenter/clampedY` đổi **nội dung** sang gọi `FloatingWidgetGeometry.*`; tập cạnh vào/ra của hai type này không đổi và công thức tương đương từng phép toán.

## Cạnh invalidate bị thiếu giữa `ReaderViewModel` và `ReaderView` (1.3.243)

* Trước 1.3.243 **không có** cạnh nào từ `ReaderViewModel.objectWillChange` về `ReaderView`. `ReaderViewModel` là `ObservableObject` nhưng `ReaderView` giữ nó ở `@State` (`ReaderView.swift:196`), mà `@State` chỉ lưu tham chiếu — nó không subscribe publisher. Vì vậy `pendingNavigationIndex`, `navigationCommit`, `loadState`, `navigationFailure` đổi giá trị mà **không** kích hoạt update pass nào.
* Hệ quả trên đồ thị gọi: `ReaderView.nextChapter/prevChapter → requestChapter → (pendingNavigationIndex = N)` là một nhánh **chết ở giữa** — không dẫn tới `singleChapterReaderView` cho tới khi một nguồn invalidate *khác* nổ: `ttsState` (`@StateObject`) publish, một `@State` khác của `ReaderView` đổi, một trong bốn `.onReceive` NotificationCenter, hoặc `@Query`. Log thiết bị 2026-08-22 đo khoảng chờ đó là 0.6–4.3 s.
* Cùng lý do: `.onChange(of: vm.navigationCommit)` (→ `applyNavigationCommit`) chỉ được so sánh trong một update pass, nên nó cũng chờ chung sự kiện vô can đó. Dòng `[ReaderPerf] NavRealize reason=commit` **không** chứng minh có pass — nó phát từ `ReaderViewModel.commitNavigation` (`ReaderViewModel.swift:672`), không phải từ view.
* Cạnh mới: `ReaderViewModel.objectWillChange → ReaderViewModelInvalidationRelay.objectWillChange → ReaderView` (`@StateObject`). Đăng ký tại `ensureViewModel` ngay sau `viewModel = newViewModel`, huỷ tại `.onDisappear`. Không lọc theo thuộc tính: mọi `@Published` của view model nay đều invalidate Reader, đúng như `@ObservedObject` sẽ làm.
* Không cạnh nào khác đổi: cổng bắt tay skeleton (1.3.242), `scheduleDeepLandingScroll`, nhịp chờ 32 ms, `ReaderScrollCoordinator` giữ nguyên — chúng chỉ *bây giờ mới* chạy đúng nhịp vì đã có pass để chạy.

## Cổng bắt tay skeleton nằm giữa hai subtree chương (1.3.242)

* Cạnh mới trong render gate của `singleChapterReaderView`: `ZStack → ReaderView.isChapterSubtreeRenderable(_:)` (khai ở `ReaderView+LoadingView.swift`). Nhánh `singleChapterScrollView` chỉ được chọn khi hàm này trả `true`; ngược lại đi nhánh `chapterInlineLoadingView`.
* `chapterInlineLoadingView.onAppear` nay có **hai** việc: ghi `skeletonHandshakeIndex = index` (cạnh dữ liệu nuôi cổng ở trên) rồi mới `recordSkeletonPresented(index:)`. `singleChapterScrollView.onAppear` cũng thêm `renderedChapterIndex = chapter.index` trước `recordChapterPresented(index:)`.
* Hai nhánh skeleton cũ (`pendingNavigationIndex != displayedChapterIndex` và fallback "chưa loaded") **gộp thành một** nhánh `else`, mang `.id("chapter-skeleton-\(presentationIndex)")` để đổi chương liên tiếp vẫn tạo cạnh `onAppear` mới.
* Không cạnh nào ở `ReaderViewModel`, `ReaderScrollCoordinator` hay `ReaderEnergyDiagnostics` đổi; nhịp chờ 32 ms và `scheduleDeepLandingScroll` giữ nguyên.

## Next/Prev nhập vào cùng một cửa với danh sách chương (1.3.241)

* Cạnh gọi `stepChapterHonoringTTS → ReaderViewModel.stepChapter` và `→ ReaderViewModel.requestChapter` **không còn**. Thay bằng một cạnh duy nhất: `nextChapter/prevChapter → stepChapterHonoringTTS → ReaderView.requestChapter(at:…) → ReaderViewModel.requestChapter(index:…)`. `ReaderViewModel.stepChapter` đã xoá khỏi `Sources/` (không còn caller nào).
* `ReaderView.requestChapter(at:…)` nay là điểm hợp lưu của **cả bốn** đường: `.nextButton`, `.previousButton`, `.chapterList`, `.ttsSync` (cả notification `navigateReaderToPlayingChapter`). Nó cũng là nơi phát `ReaderEnergyDiagnostics.recordNavigationTap(index:source:)`.
* Cạnh mới ở đường hạ cánh: `applyNavigationCommit → scheduleDeepLandingScroll` (trong `ReaderView+Controls.swift`) → `DispatchQueue.main.asyncAfter(0.15)` → ghi `scrollTarget` → `.onChange(of: scrollTarget)` → `attemptScroll → ReaderScrollCoordinator.attemptScroll`. Coordinator không đổi chữ nào.
* Hai cạnh instrumentation mới: `chapterInlineLoadingView.onAppear → recordSkeletonPresented(index:)` và `singleChapterScrollView.onAppear → recordChapterPresented(index:)`.

## Đường Next/Prev khi TTS đang phát & log `[ReaderPerf]` (1.3.240)

* `nextChapter()`/`prevChapter()` của `ReaderView` không còn gọi `viewModel?.stepChapter(by:)` trực tiếp: cả hai rút về một dòng gọi `stepChapterHonoringTTS(by:source:)` ở `ReaderView+Controls.swift`. Helper clamp chỉ số đích như cũ, nhưng khi chương đích **đúng là chương TTS đang phát của sách này** (`snapshot.isPlaying`, `playingBookId == bookId`, `playingChapterIndex == target`, `currentParentParagraphIndex >= 0`, `!isAutoScrollDisabled`) thì gọi thẳng `viewModel?.requestChapter(index:paragraphIndex:source:persistProgress:)` với đoạn TTS đang đọc; mọi trường hợp còn lại vẫn đi `stepChapter` (tức `paragraphIndex: -1`). `stepChapter` không đổi vì còn phục vụ đường khác.
* Hệ quả trên `ReaderScrollCoordinator.attemptScroll`: target hạ cánh mang `paragraphIndex >= 0` nên nó chọn neo `paragraph-N-P` (`anchor: .center`) ngay lượt dựng đầu tiên, thay vì `chapter-N` (`.top`) rồi vài giây sau bị `requestTTSScrollIfNeeded` bắn thêm một cú `scrollTo` sâu thứ hai.
* Đường commit RAM đổi hình dạng: `requestChapter` → (hit cache) → `memoryCommitTask = Task { @MainActor … await Task.yield() … commitNavigation(request, origin: .memory) }`, tức `commitNavigation` không còn nằm trong stack của cú bấm.
* Bốn call site log mới, tất cả sau cổng cờ đã latch (không đọc `UserDefaults` trên hot path):
  - `ReaderViewModel.commitNavigation` → `[ReaderPerf] Nav index=… paragraph=… origin=… source=… commitMs=…`, mốc bắt đầu đặt ở đầu `requestChapter`.
  - `ReaderViewModel.loadChapterContentFromExtension` → `[ReaderPerf] RepoLoad index=… origin=… ms=…` quanh `ChapterContentRepository.shared.load`.
  - `ReaderScrollCoordinator.attemptScroll` → `ReaderEnergyDiagnostics.recordScrollAttempt` → `[ReaderPerf] Scroll chapter=… paragraph=… reason=… anchor=…`.
  - `.onAppear` của card đoạn trong `ReaderView` → `recordParagraphRealized()`, in ra ở lần commit kế tiếp dưới dạng `[ReaderPerf] NavRealize index=… cards=…`.

## Reader selection/scroll & energy-diagnostics call graph (1.3.239)

* Đường selection (mới): `ReaderUITextView` báo `textViewDidChangeSelection` → nếu `selectedRange.length > 0` thì `Coordinator.setupScrollObservation(for:)` **cài KVO** trên `textView.parentScrollView.contentOffset` rồi `publishSelection(range, minY, maxY, force: true)`; nếu `length == 0` thì `teardownScrollObservation()` + `publishSelection(NSRange(location: NSNotFound, length: 0), nil, nil, force: true)`. `updateUIView` **không còn** gọi `setupScrollObservation` — cạnh `updateUIView → setupScrollObservation` (chạy mỗi paragraph, mỗi lượt cập nhật) đã bị xoá.
* Đường cuộn khi đang có selection: KVO → `handleSelectionOrScrollUpdate()` → `guard selectedRange.length > 0` → `NSMaxRange <= textView.textStorage.length` → `selectionGlobalMinMaxY(textView:textRange:)` → `publishSelection(...)` → (nếu qua dedup 0.5 pt) `parent.onSelectionChange` → `ReaderView.onSelectionChangeInParagraph`. Trước đây mỗi frame cuộn đều tới được `onSelectionChange`; giờ dedup chặn tại `publishSelection` nên `@State` của `ReaderView` chỉ ghi khi vị trí selection thực sự đổi.
* `triggerCustomDefine` cũng đi qua `publishSelection(..., force: true)` để giữ đúng hành vi publish một lần bất kể dedup.
* Huỷ observer: `dismantleUIView` và `Coordinator.deinit` vẫn `offsetObservation?.invalidate()`; thêm đường huỷ chủ động qua `teardownScrollObservation()` từ delegate selection.
* `ReaderEnergyDiagnostics` (file mới `Views/Reader/Components/ReaderEnergyDiagnostics.swift`): `ReaderView.onAppear` → `beginReaderSession()` → đọc `AppLogger.shared.isLoggingEnabled` **một lần** (getter này chạm `UserDefaults`, không được gọi trên hot path). Mọi `record*` (`recordUIViewUpdate`, `recordHighlightMutation`, `recordGeometryRebuild`, `recordThemeRebuild`, `recordExplicitSizeInvalidation`, `recordContentSizeInvalidation`, `recordTTSScrollTarget`, `recordTTSScrollSkippedVisible`, `recordTTSScrollExecuted`, `recordParagraphFrameUpdate`) và `flush(reason:)` mở đầu bằng `guard isEnabled`, nên khi log tắt các cạnh gọi từ `ParagraphTracker.updateFrame`, `ReaderScrollCoordinator`, `ReaderView+LoadingView`, `ReaderTextView.updateUIView` dừng ngay ở một phép so bool. `updateWindow` chỉ đọc `ProcessInfo.systemUptime` mỗi 64 event để kiểm mốc 60 s; `emitSummary` mới đọc trực tiếp và dựng `String(format:)` 24 tham số.
* `completeReaderPositionRestore` không còn cạnh `→ ParagraphTracker.removeAll()`; các call site còn lại của `removeAll()` là `onDisappear`, `onChange(of: chapterIndex)`, đường navigate, `applyNavigationCommit`, `reloadCurrentChapterFromMenu`.

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
