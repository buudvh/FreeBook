# CHANGELOG - Nhật ký Thay đổi CodeGraph FreeBook

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **FreeBook**.

> Chỉ giữ các version gần đây. Lịch sử cũ hơn (≤ 1.3.200) nằm ở [CHANGELOG.archive.md](CHANGELOG.archive.md).

## [1.3.239] - 2026-08-21

### Tối ưu năng lượng Reader khi TTS: bỏ xử lý dư thừa trên đường cuộn

Người dùng báo Reader nóng máy / tụt pin / lag khi TTS đang đọc, và chốt rõ là **giữ nguyên cảm giác** của highlight + auto-scroll, chỉ bỏ phần xử lý dư thừa. Đọc code cho thấy chi phí **không** nằm ở nhịp highlight (chunk 200 ký tự + dedup snapshot ⇒ ~1 tick/10 giây) mà nằm ở đường cuộn: mỗi lần `contentOffset` đổi (60–120 Hz) thì *mọi* paragraph đang realized đều chạy việc thừa.

* **`ReaderTextView.swift`** — KVO `contentOffset` chuyển từ *cài vô điều kiện trong `updateUIView`* sang *cài lazy khi có selection thật*. Trước đây mỗi paragraph cài một observer trên **cùng một** `UIScrollView`, nên với ~40 đoạn realized × 120 Hz là ~4.800 callback/giây chỉ để phục vụ *một* selection thường không tồn tại. Nay `setupScrollObservation` chỉ gọi từ `textViewDidChangeSelection` khi `selectedRange.length > 0`, và `teardownScrollObservation()` chạy ngay khi selection về rỗng ⇒ trạng thái thường ngày là **0 observer**.
* **`ReaderTextView.swift`** — `handleSelectionOrScrollUpdate` `guard nsRange.length > 0` **trước** khi đo độ dài text, và dùng `textView.textStorage.length` (O(1), đã là UTF-16) thay cho `((textView.text ?? "") as NSString).length` (một vòng bridging Swift↔ObjC mỗi callback). Thêm dedup `lastPublishedSelection`: bỏ qua `onSelectionChange` khi range không đổi và minY/maxY lệch < 0.5 pt — đây là chỗ chặn `onSelectionChangeInParagraph` ghi 8 `@State`, tức invalidate toàn bộ `ReaderView.body`, mỗi frame khi vừa có selection vừa cuộn. `triggerCustomDefine` publish với `force: true` nên hành vi tra từ không đổi.
* **File mới `Sources/Views/Reader/Components/ReaderEnergyDiagnostics.swift`** (258 dòng) — instrumentation tách khỏi `ReaderTextView.swift` (647 → **450 dòng**) và nay **miễn phí khi log tắt**: cờ `isEnabled` chốt một lần trong `beginReaderSession()` từ `AppLogger.shared.isLoggingEnabled` (getter đó chạm `UserDefaults`, không được gọi mỗi event), mọi `record*`/`flush` mở đầu bằng `guard isEnabled`. Vì `AppLogger.init` set `isLoggingEnabled = false` mỗi lần khởi chạy, production ⇒ toàn bộ đo đếm rút về một phép so bool. `Window` đổi từ `struct` sang `final class` để mutate in-place (bản struct chứa `Set<ObjectIdentifier>` bị copy-on-write **toàn bộ Set** mỗi lần `recordUIViewUpdate` qua `var snapshot = window … window = snapshot`), và `ProcessInfo.systemUptime` chỉ đọc mỗi 64 event thay vì mỗi event.
  * Đánh đổi có chủ ý: **bật/tắt log trong Settings giữa lúc Reader đang mở chỉ có hiệu lực từ lần mở Reader kế tiếp**, và số liệu `[ReaderEnergy] Summary` chỉ tồn tại khi log được bật *trước* khi mở Reader.
* **`ParagraphTracker.swift`** — chỉ thêm comment: ghi rõ nhánh bị lọc trong `updateFrame` là hot path (mỗi paragraph, mỗi frame cuộn) và **không được nới** `minimumFrameDelta = 8`, vì ngưỡng này quyết định phán quyết của `isParagraphInsideSafeViewport` — nới nó là đổi hành vi auto-scroll, không phải tối ưu. Logic không đổi.
* **`ReaderView.swift` + `ParagraphCardView.swift`** — xoá `translationRefreshToken` (dead code: `@State` không hề được ghi ở đâu; refresh bản dịch thực chất đi qua `viewModel?.updateCachedTranslatedContent` làm `paragraphItems` đổi). Bớt một field trong struct và một phép so trong `==` trên mỗi paragraph mỗi lượt dựng `ForEach`.
* **`ReaderView+Controls.swift`** — `completeReaderPositionRestore` không còn `paragraphTracker.removeAll()`. Các đoạn đang hiển thị không `onAppear` lại nên map frame rỗng làm tick TTS đầu tiên sau restore luôn thấy "ngoài viewport" ⇒ một cú `scrollTo` thừa (một cú nhảy + một layout pass); `isRestoringReaderPosition` đã tự chặn mọi consumer trong lúc restore. **Đây là item duy nhất có thay đổi thấy được** (mất một cú nhảy thừa ngay sau khi mở chương), đã nêu rõ trong plan và được người dùng chấp thuận. Các `removeAll()` khác (`onDisappear`, `onChange(of: chapterIndex)`, đường navigate, `applyNavigationCommit`, `reloadCurrentChapterFromMenu`) giữ nguyên.
* **Không đổi**: đường highlight (`ttsState.snapshot.highlightRange` vẫn truyền thẳng, không ánh xạ), anchor `.center`, việc bám theo `currentParentParagraphIndex`, hành vi cuộn tay, `minimumFrameDelta`, hệ toạ độ `frame(in: .global)`.
* Tổng file Swift 230 → 231. `check_architecture.py` giữ **18 violation**, tập vi phạm giống hệt trước thay đổi (phép tách file là để *tránh* violation mới: `ReaderTextView.swift` từng lên 707 dòng > baseline 651 trước khi tách). `validate_links.py`: 7 doc bị stale do thay đổi này đã cập nhật + `--accept`; **4 doc còn stale từ trước** (`05_state_graph.md`, `08_lifecycle.md`, `10_risk_report.md`, `rules.md`) không thuộc phạm vi thay đổi này nên không bless.
* **Chưa biên dịch**: host là Windows, `xcodebuild` chỉ chạy trên macOS. Xác minh ở đây chỉ gồm đọc code, đối chiếu mọi đường tạo/huỷ `offsetObservation`, và hai script Python.

## [1.3.238] - 2026-08-21

### Sửa caption Telegram vượt 1024 ký tự và mô tả đường dẫn log trong Settings

Hai sửa nhỏ, không đổi logic runtime nào.

* **`.github/workflows/build-ipa.yml`** — bug hạ tầng phát hiện từ log CI thật: caption của `sendDocument` bị Telegram giới hạn **1024 ký tự**, nhưng workflow dựng caption từ *toàn bộ* commit message (`%B`). Với commit message nhiều đoạn, Telegram trả `400 Bad Request: message caption is too long` và **IPA không tới được Telegram** — trong khi `curl` vẫn exit 0 nên step `Send IPA to Telegram` vẫn báo success và CI vẫn xanh. Nay caption chỉ dùng **subject một dòng** (`%s` qua biến mới `COMMIT_SUBJECT`); `COMMIT_MSG` (`%B`) giữ nguyên cho hai nhánh `sendMessage` vì giới hạn ở đó là 4096 ký tự. Toàn bộ message vẫn tra được bằng `git log`.
* **`Sources/Views/Settings/Main/SettingsView.swift`** — sửa mô tả nút "Ghi log hệ thống": bỏ giới hạn sai "của các VBook extension" (log phủ toàn app, không riêng extension) và ghi đúng đường dẫn `applicationSupportDirectory/app_logs.txt` thay vì `app_logs.txt`, khớp với thực tế `AppLogger` và với `rules.md` §5.9.
* Hệ quả cần biết: các build đã push trước đó với commit message dài (`511e1b5`, `60937fd`) rất có thể **chưa từng gửi được IPA sang Telegram** dù CI xanh; run kế tiếp là lần đầu caption đủ ngắn.

## [1.3.237] - 2026-08-21

### Sửa lỗi biên dịch của phép tách file: batchSize fileprivate xuyên file

CI của `6357674` fail ở step `Build and Archive App (Unsigned)`. Nguyên nhân là hệ quả trực tiếp của phép tách ở 1.3.236: `BookTitleTranslationMigrator.batchSize` được khai `fileprivate static let`, mà `fileprivate` trong Swift là **phạm vi file**, nên sau khi `BookTitleTranslationBackfill` rời sang file riêng thì `BookTitleTranslationMigrator.batchSize` không còn truy cập được.

* **`BookTitleTranslationMigrator.swift`**: xoá `fileprivate static let batchSize = 50` (không còn ai trong file dùng).
* **`BookTitleTranslationBackfill.swift`**: thêm `private static let batchSize = 50` (kèm doc comment nêu mục đích: giới hạn số sách mỗi lần `save()`), và đổi call site `BookTitleTranslationMigrator.batchSize` → `Self.batchSize`. Hằng nay nằm đúng chỗ actor thực sự dùng nó, phạm vi hẹp hơn trước.
* Giá trị 50 và hành vi batch không đổi.
* **Kiểm tra bổ sung sau sự cố** (để không lặp lại cùng loại lỗi ở 13 phép tách còn lại): quét chéo mọi khai báo `private`/`fileprivate` giữa từng cặp file-gốc ↔ file-mới → chỉ còn 3 kết quả và cả 3 là trùng tên vô hại (`container` là tham số, `pillHeight` là tham số, `containerViewController` do mỗi type tự khai); quét trùng khai báo type top-level toàn `Sources/` → 0; quét identifier chưa resolve trong 14 file mới → không thiếu `import` nào.
* `check_architecture.py` giữ **18 violation** (không đổi). `validate_links.py` PASS.

## [1.3.236] - 2026-08-21

### Tách file theo luật một-primary-type, hết MULTI_PRIMARY_TYPES và NEW_FILE_TOO_LARGE

Phase 3 phần cơ học của kế hoạch dọn nợ kiến trúc: tách type, **không đổi một dòng logic nào**. Mọi tham chiếu vẫn trong cùng module nên đây chỉ là dịch chuyển khai báo.

* **8 file vi phạm `MULTI_PRIMARY_TYPES` → 14 file mới**, mỗi file đúng một type top-level: `TextEncodingOption` ← `TextEncodingDecoder.swift`; `BookListItemStyle` ← `BookListItemView.swift`; `VisibleBrowserPresentationReader`/`VisibleBrowserReopenViewModel`/`SizeReader` ← `VisibleBrowserReopenView.swift`; `CodeEditorTextView` ← `HighlightingCodeEditor.swift`; `ShelfBookSearchMatcher` ← `ShelfSearchView.swift`; `FloatingWidgetUIWindow`/`FloatingWidgetContainerViewController` ← `TTSFloatingWidgetWindowManager.swift`; `BookTitleTranslationBackfill` ← `BookTitleTranslationMigrator.swift`; `DictionaryInvalidationScope` ← `TranslationManager.swift`; `VisibleWebViewController` ← `VisibleWebViewLoader.swift`; `VisibleBrowserTabItem`/`TabbedVisibleBrowserViewController` ← `VisibleBrowserTabManager.swift`.
* **Cả 2 `NEW_FILE_TOO_LARGE` cũng hết** nhờ chính phép tách đó: `VisibleBrowserTabManager.swift` 448 → 234, `VisibleWebViewLoader.swift` 404 → 285.
* **Hai type nâng access level** vì `private` ở Swift là phạm vi file: `SizeReader` (`private struct` → internal), `BookTitleTranslationBackfill` (`private actor` → `internal actor`). Không type nào thành `public`.
* Type lồng đi cùng type cha (`Layout`, `Snapshot`, `Coordinator`); protocol `BookDisplayable` ở lại `BookListItemView.swift` vì luật không tính protocol.
* Không file mới nào dưới `Sources/Services/**` import SwiftUI, nên miễn trừ `SERVICE_SWIFTUI_IMPORT` cho `*WebViewLoader.swift` không bị nới rộng.
* **Sự cố đã sửa trong lúc làm**: lần ghi file đầu dùng `newline=CRLF` trên nội dung vốn đã CRLF nên sinh `\r\r\n`, khiến gate đọc `TabbedVisibleBrowserViewController.swift` thành 402 dòng (gấp đôi 201 thật). Đã chuẩn hoá cả 14 file về LF cho khớp phần còn lại của repo.
* **Kết quả gate**: `check_architecture.py` **28 → 18 violation**. Tổng file Swift 216 → 230.
* **Còn nợ, chưa làm trong lần này**: 16 `LINE_LIMIT_EXCEEDED` (không giải được bằng tách type vì các file đó chỉ có 1 type — phải tách *thành viên* sang `X+Feature.swift`; nợ lớn nhất `TTSManager.swift` −533 dòng, `JSExecutor.swift` −448, `ReaderView.swift` −197) và 2 `VIEW_SWIFTDATA_MUTATION` thật ở `DiscoveryView.swift`/`ReaderView.swift` (phải chuyển ghi qua transaction coordinator — đổi quyền sở hữu transaction, không phải dọn cơ học).
* **Chưa biên dịch cục bộ**: máy Windows. Cần `xcodegen generate` + build trên macOS; CI là bước xác minh compile.

## [1.3.235] - 2026-08-21

### Xoá tầng test, dọn code chết và scaffolding chẩn đoán

Theo yêu cầu trực tiếp của người dùng (Phase 0 = xoá `Tests/`), tầng test bị loại bỏ hoàn toàn; nhờ đó mọi symbol không có tham chiếu trong `Sources/` mới kết luận được là code chết thật (trước đây không thể vì `Tests/` có thể đang dùng). Đây là thay đổi rộng nhất từ trước tới nay về số file bị đụng nhưng **không đổi hành vi runtime nào**.

* **Phase 0 — bỏ tầng test**: `git rm -r Tests` (20 file, vẫn phục hồi được từ git history) và bỏ target `FreeBookTests` khỏi `project.yml`. Từ đây chỉ còn một target biên dịch (`FreeBook`, `sources: Sources`). Quy chuẩn tương ứng trong `rules.md` đổi từ "Test Lock Rule" sang **"Test Layer Removed"**: không tạo lại `Tests/` hay target test khi chưa được yêu cầu; xác minh dựa trên đọc code + build macOS + hai script tĩnh.
* **Phase 1 — rác không phải symbol**: bỏ `import Foundation` trùng ở `NghiSynthesisPolicy.swift`; bỏ hai biến chết `startRange`/`endRange` cùng hai dòng `let _ = … // suppress unused warning` trong `ReaderTextView.selectionGlobalMinMaxY` (guard rút về đúng `end` là giá trị thực sự dùng); **xoá scaffolding `logRemoteTrace`** mà chính tác giả đã đánh dấu `REMOVE_AFTER_TTS_REMOTE_DIAGNOSIS` — gồm `remoteTraceSequenceCount`, hàm `logRemoteTrace` và 7 call site (đều nằm trong `#if DEBUG` nên vô hiệu trên LiveContainer), kéo theo 3 tham số `entryUptime`/`isMain`/`eventId` của `dispatchRemoteTransportCommand` chỉ tồn tại để nuôi nó.
* **Phase 2A — xoá 4 file chết**: `Services/TTS/Helpers/{TTSHighlightCalculator,TTSParagraphSplitter,TTSVoiceResolver}.swift` (thư mục `Helpers/` không còn) và `Views/Reader/ReaderViewModelObserver.swift`. `Views/Reader/ReaderParagraphBuilder.swift` được đổi tên thành `ReaderParagraphBuildResult.swift` sau khi xoá enum builder — DTO `ReaderParagraphBuildResult` vẫn được `ReaderViewModel+Translation` dùng, nên chỉ còn **một** đường dựng `[ParagraphItem]`.
* **Phase 2B — xoá ~30 symbol chết** ở 20 file: `TTSManager.{clearPreparedChapterCache,restartCurrentParagraph,downloadNghiTTSModel,nghiWatermarks}`, `TTSChapterPrefetcher.awaitTextWorkerResult`, `TTSChapterTextWorker.shouldTriggerPrefetch` (bản song song của điều kiện đã inline trong `triggerNextChapterPrefetch`), `TTSNowPlayingController.clearNowPlayingInfo`, `TTSParagraphBuilder.build(from:chunkLength:)`, `ModelStore.{cacheSummary,readCachedVoices,writeCachedVoices,voicesCacheURL}` + `CacheSummary`, `NghiTTSClient.{fetchVietnameseVoices,getModelList}` + `ModelsResponse`, `UnavailablePiperEngine`, `TranslationManager.{addDeletedWords,deleteDictionary}`, `TranslateUtils.resetTOCRulesToDefault`, `DoubleArrayTrie.allEntries`, `BookTransactionCoordinator.updateCurrentChapterTitle`, `ExtensionTransactionCoordinator.deleteExtension`, `JunkFilterManager.toggleRule`, `ImageCacheManager.hasLocalCover`, `DisplayTextFormatter.titleCaseOrNil`, `ExtensionManager.hasConfig`, `ReaderChapterListStore.loadPageIfNeeded` (bị `loadVisiblePageIfNeeded` thay thế), `SearchBar`, hai typealias `SearchNovelResult`/`TTSProcessedChapter`, và abstraction rỗng `GlobalToastModifier`/`globalToast()` cùng 2 call site.
* **Không xoá false positive**: toàn bộ `Services/Extensions/Engine/JS*` (API mà extension JavaScript gọi theo tên), conformance delegate (`speechSynthesizer`, `callObserver`, `scrollViewDidScroll`, `textViewDidChange`, `placeSubviews`) và hàm truyền dạng function reference đều được giữ. Đã kiểm tra không symbol nào bị xoá là protocol requirement.
* **Kết quả gate**: `check_architecture.py` **30 → 28 violation** — hết `NEW_FILE_TOO_LARGE` của `TTSChapterPrefetcher.swift` (402 → 375) và hết `LINE_LIMIT_EXCEEDED` của `TranslationManager.swift`. `TTSManager.swift` 4097 → **4003**; `ExtensionManager.swift` 1066 → 1049; `TranslateUtils.swift` 1046 → 1041. Tổng file Swift 220 → 216.
* **Chưa biên dịch được**: thay đổi viết trên Windows. Bắt buộc `xcodegen generate` (có file bị xoá/đổi tên) rồi build trên macOS trước khi coi là đã xác minh.

## [1.3.234] - 2026-08-21

### Lấp buffer nghèo ở biên chương bằng prefix audio chương kế cho Google/Ext và NghiTTS

Trước thay đổi này, cửa sổ prefetch đoạn văn bị chặn cứng ở biên chương (`idx < paragraphs.count`), nên càng gần cuối chương buffer càng co lại, và ngay sau khi chuyển chương chỉ có đúng chunk 0 sẵn sàng — chunk 1 phải chờ tổng hợp trong khi coordinator chỉ chạy 1 operation. Đây là điểm nghèo buffer nhất của cả phiên nghe. Chương kế **vẫn không** được coi là chunk nối tiếp của chương hiện tại (không đổi không gian index `preloadedData`); thay vào đó phần thiếu được lấp bằng prefix của chương kế trong đúng số slot đang trống.

* **File mới `Sources/Services/TTS/TTSNextChapterPrefixCache.swift`** (380 dòng, `@MainActor`, singleton `.shared`): nạp trước các chunk **index >= 1** đầu chương kế cho cả `nghitts`, `google` và extension TTS (`system` bị loại). Giữ `activeKey`/`chunks`/`durations`/`tasks`/`generation`; `request(key:playbackParagraphs:capacity:…)` mở task cho index còn thiếu trong `1..<min(count, capacity + 1)`, `trim(toCapacity:)` thu hồi khi capacity co lại, `consume(matching:)` chỉ trả dữ liệu khi key trùng tuyệt đối, `contiguousDuration(matching:from:)` trả thời lượng chuỗi chunk liên tục cho watermark của Nghi, `cancelPendingWork()` hủy task nhưng giữ chunk đã xong, `reset()` giải phóng toàn bộ. Tổng hợp đi qua `PiperTTSService.synthesize(priority: .optionalReserve)` (Nghi) hoặc `TTSAudioSynthesisWorker.synthesizeParagraph(priority: .nextChapter, offset: index, prefetchDelayMs: prefetchDelayMs)` (Google/Ext) — đều là mức ưu tiên thấp nhất của engine, không có retry riêng. Nhánh remote đi qua đúng bước giãn `sleep(offset × max(300, prefetchDelayMs))` của worker nên tôn trọng cấu hình `prefetchDelayMs`/`extPrefetchDelay_<tool>`; số ký tự mỗi phân đoạn đã nằm trong `key.chunkLength` (`max_length` với extension). Chunk 0 chương kế vẫn giữ `offset: 0, prefetchDelayMs: 0` vì là slot bắt buộc.
* **File mới `Sources/Services/TTS/Extensions/TTSManager+NextChapterPrefix.swift`** (130 dòng): `nextChapterPrefixContext()` chỉ trả bối cảnh khi `nextChapterPrefetcher.currentState` là `.synthesizingAudio`/`.audioReady` (bảo đảm chunk 0 vào hàng đợi trước) và chunk hoá theo `key.chunkLength`; `mergeNextChapterPrefixAudio(for:)` dựng lại key từ `TTSChapterInfo` rồi nhồi vào `preloadedData`/`preloadedDurations`; `nextChapterPrefixContiguousDuration(matching:)`; `cancelNextChapterPrefixWork()`/`resetNextChapterPrefixCache()`.
* **Google/Ext — độ sâu buffer theo `preload_size`/`googlePrefetchCount`**: `requestRemoteNextChapterPrefixIfNeeded(windowCount:inChapterTargetCount:)` dùng `capacity = max(0, count - inChapterTargetCount - 1)`. Vì `inChapterTargetCount + 1 (chunk 0) + capacity == count`, độ sâu phía trước **luôn bằng đúng `count` chunk kể cả khi đi qua biên chương** — giữa chương capacity = 0, càng gần cuối chương capacity càng lớn.
* **NghiTTS — kéo dài watermark 8s qua biên chương**: `calculateNghiCachedTime()` cộng thêm chuỗi chunk prefix **liên tục ngay sau chunk 0** chương kế, nên `cachedTime` đo được chuỗi phát vượt biên chương. `requestNghiNextChapterPrefixIfNeeded` chỉ nạp khi chương hiện tại đã hết ứng viên **và** `cachedTime < nghittsSafeCachedTimeThreshold`, với `capacity = max(0, NghiSynthesisPolicy.maxTotalAudioPayloads - heldPayloads)`; đủ ngưỡng thì dừng nạp và giữ nguyên chunk đã có. Hằng mới `NghiSynthesisPolicy.maxTotalAudioPayloads = 5` giữ đúng trần payload đã ghi trong quy chuẩn (policy vẫn là single source cho mọi hằng năng lượng của Nghi).
* **`TTSManager.swift`** (+4 dòng, 4097 → 4101): `pause()` gọi `cancelNextChapterPrefixWork()`; `applyNextChapter` gọi `mergeNextChapterPrefixAudio(for: chapter)` sau khi gán `preloadedData[0]`; `updatePrefetchWindow()` gọi `requestRemoteNextChapterPrefixIfNeeded(...)`; `updateNghiPrefetchWindow()` gọi `requestNghiNextChapterPrefixIfNeeded(...)` sau `promoteAudioIfNeeded`. Nhánh chương kế trong `calculateNghiCachedTime()` cộng thêm `nextChapterPrefixContiguousDuration(matching: key)` (net 0 dòng). Ngoài ra `nghiTTSService` và `makeNextChapterKey(for:)` đổi `private` → `internal` để extension ở file khác dùng được (0 dòng thay đổi).
* **`TTSManager+PrefetchCache.swift`** (+1 dòng): `clearAllTTSCaches()` gọi `resetNextChapterPrefixCache()`, nhờ đó stop, đổi `tool` và đổi `selectedVoice` (đều đi qua `clearPrefetchCache()`) đều giải phóng bộ đệm.
* **Highlight của chunk prefix hoạt động y hệt chunk thường**: nó do `commitAudibleParagraphState` phát từ `paragraphs[index]` của chương đã áp dụng, không phụ thuộc nguồn gốc byte audio. Để index↔text không thể lệch, `chunks` lưu `PreparedChunk { data, finalText }` và `mergeNextChapterPrefixAudio` so `finalText` với `applyReplacements(paragraphs[index].text)` trước khi nhồi; không khớp thì bỏ chunk và log `textMismatch=M`. Lớp này phủ cả trường hợp DTO chương kế bị dựng lại mà key không đổi.
* **Dùng lại đúng cơ chế của cửa sổ đoạn văn**: token theo index cho mỗi task (tương ứng `removePrefetchTask(for:taskGen:)`), và phân loại lỗi bằng chính `TTSManager.evaluateRefillError(_:currentAttempts:maxAttempts: 2)` + `TTSManager.RefillFailureState` nên index non-retryable/hết attempt/audio rỗng bị block tới khi `reset()`. Prefix không có retry task/backoff riêng. Hai sai lệch có chủ ý so với refill trong chương (Nghi xếp hàng nhiều task thay vì 1-in-flight; identity không gồm `sessionID` — dùng chung tính chất với `TTSChapterPrefetcher`) được ghi ở `10_risk_report.md`.
* **Trần bộ nhớ không đổi** — đây là *tái phân bổ*, không phải nới trần: remote vẫn `<= count + 1` payload, Nghi vẫn `<= NghiSynthesisPolicy.maxTotalAudioPayloads` (5). Phép đếm payload của Nghi cố ý thiên về bảo thủ (có thể đếm trùng `hasPreparedNext` với `preloadedData`) để không bao giờ vượt trần. Bất biến mới ghi ở `rules.md`.
* **Chưa biên dịch được**: thay đổi viết trên Windows, `xcodebuild` chỉ chạy trên macOS. Sau khi thêm file mới phải chạy `xcodegen generate` rồi build; `check_architecture.py` trước/sau đều 30 violation, không có violation mới.

## [1.3.233] - 2026-08-21

### Tạm ngưng Reader TTS auto-scroll khi ứng dụng không hiển thị (scenePhase != .active)

* **`ReaderView.swift` & `ReaderView+LoadingView.swift`**:
  - Quản lý trạng thái hiển thị qua `@State internal var isSceneActive` (đồng bộ tại `onAppear` và `.onChange(of: scenePhase)`) và số thế hệ `ttsAutoScrollGeneration` tăng dần mỗi lần chuyển phase, tránh việc SwiftUI closure capture snapshot struct `self.scenePhase` cũ.
  - Chặn mọi entry point TTS auto-scroll khi `isSceneActive == false`, bao gồm callback `.onChange(of: currentParentParagraphIndex)`, `requestTTSScrollIfNeeded`, và callback delayed `scrollToTTSHighlightIfNeeded` (closure `asyncAfter` kiểm tra cờ `isSceneActive` và token `ttsAutoScrollGeneration == currentGen`).
  - Khi `scenePhase` chuyển sang inactive/background, `ttsAutoScrollGeneration` tăng lên làm hủy lập tức mọi callback `asyncAfter` đang chờ, đồng thời tự động hủy `scrollTarget` pending có `reason == .ttsAuto`, không ảnh hưởng đến các target navigation/manual/initial-restore.
  - Thêm kiểm tra phòng thủ (defense-in-depth) tại `attemptScroll` và `.onChange(of: scrollTarget)` để hủy lập tức bất kỳ `.ttsAuto` target nào phát sinh khi `!isSceneActive` mà không thực thi.
  - Khi `scenePhase` trở lại `.active`, kích hoạt resync 1-shot duy nhất (`scrollToTTSHighlightIfNeeded`) khớp với token mới nhất sau 0.1s defer để đồng bộ về câu TTS hiện tại mà không replay backlog scroll ngầm.
  - Giữ nguyên trạng thái hiển thị highlight, audio TTS, tiến độ logic, prefetch, và background chapter sync.

## [1.3.232] - 2026-08-21

### Đưa cơ chế staleness mới tới Codex/agent khác: sửa .agents/AGENTS.md, bỏ gitignore AGENTS.md

Chỉ sửa hạ tầng tài liệu/quy trình; không đụng `Sources/`, `Tests/`, hay vùng ngoài `GENERATED` của doc nào. Vá lỗ hổng: cơ chế routing per-doc (1.3.230) chỉ nằm ở `rules.md` + `CLAUDE.md`, còn hai kênh mà agent khác thật sự đọc thì lệch — `.agents/AGENTS.md` (tài liệu bước-1 bắt buộc) vẫn mô tả quy trình cũ, và bản mirror `AGENTS.md` cho Codex bị gitignore nên không tới được agent nào clone repo.

* **`.agents/AGENTS.md`** (sửa theo yêu cầu trực tiếp của người dùng, đúng §7): bước 6 đổi từ "tính lại `sourceHash`/`generatedHash` thủ công" sang chạy `--explain` rồi ghi nhận từng doc bằng `--accept`/`--no-change-needed` (validator tự ghi 3 hash + `reviewMode`, không sửa tay); bước 7 nêu rõ read-only phải PASS gồm cả điều kiện "không doc nào còn stale"; §5 thêm ghi chú validator tự phát hiện trigger qua `sourcePatterns`/`staleOn`; §6 Completion Criteria mục 3-4 cập nhật theo audit trail + luật xoay CHANGELOG. Mọi chi tiết luật vẫn trỏ về `rules.md` §6.2, không nhân bản.
* **`.gitignore`**: bỏ dòng `/AGENTS.md`. Bản mirror `AGENTS.md` (đích cho Codex, đúng ghi chú đầu `CLAUDE.md`) trước đây bị ignore nên chỉ tồn tại cục bộ; giờ được track để commit và tới được agent khác. Regenerate mirror từ `CLAUDE.md`, `diff` từ dòng 4 = khớp.
* Không entry nào trong 16 doc CodeGraph bị stale (thay đổi không chạm `Sources/**`); `validate_links.py` read-only vẫn PASS.

## [1.3.231] - 2026-08-21

### Xoay CHANGELOG: tách lịch sử cũ sang CHANGELOG.archive.md

Chỉ sửa hạ tầng tài liệu; không đụng `Sources/` hay `Tests/`. `CHANGELOG.md` đã phình tới ~95K token / 2986 dòng (222 entry ≤ 1.3.200), lớn hơn nửa mã nguồn và không ai được lệnh *đọc* — thuần chi phí ghi, đi ngược mục tiêu tiết kiệm token của CodeGraph.

* **Tách file**: giữ 18 version gần nhất (1.3.213 → 1.3.231, ~6.9K token) trong `CHANGELOG.md`; chuyển toàn bộ entry ≤ 1.3.200 sang `CHANGELOG.archive.md` (~88K token, chỉ để tra cứu). 3 link `../../Sources/*.swift` trong phần cũ vẫn resolve vì archive nằm cùng thư mục.
* **Luật xoay (`CLAUDE.md` / `AGENTS.md`)**: khi `CHANGELOG.md` vượt ~30 entry, đẩy phần cũ nhất sang `CHANGELOG.archive.md`; luôn thêm entry mới vào `CHANGELOG.md`, không bao giờ vào archive.
* `validate_links.py` vẫn PASS 16 documents / 218 Swift files (nó kiểm link mọi `*.md` trong `Docs/CodeGraph`, gồm cả archive mới).

## [1.3.230] - 2026-08-21

### Định tuyến staleness theo từng doc: sourcePatterns, --explain, --accept/--no-change-needed

Chỉ sửa hạ tầng tài liệu (`Docs/CodeGraph/`, `CLAUDE.md`, `AGENTS.md`); không đụng `Sources/` hay `Tests/`. Trước bản này, `manifest.json` lưu **cùng một danh sách 205 file** cho cả 16 doc và `--update-hashes` tính lại mọi hash vô điều kiện, nên đổi logic hay thêm file chỉ làm `manifest.json` + `CHANGELOG.md` đổi còn doc không bao giờ bị chỉ ra là stale.

* **`manifest.json` → `schemaVersion: 2`**: mỗi doc khai `sourcePatterns` (glob tương đối gốc repo) thay cho danh sách file nhân bản, cộng `staleOn` (`structure` cho `00_index`, `02`, `09`, `14`; `content` cho `01`, `03`–`08`, `10`–`13`, `rules.md`), `structureHash` (băm *tập đường dẫn*), và audit trail `reviewedAt` / `reviewedCommit` / `reviewMode`. `sourceFiles` giờ do script tự ghi từ pattern.
* **`codegraph.schema.json`**: khai 6 field mới và đưa vào `required`.
* **`validate_links.py`**: viết lại phần manifest — `structureHash` bắt thêm/xoá/đổi tên file, `sourceHash` bắt sửa nội dung trong phạm vi doc; thêm **Coverage Rule** hai điều kiện (mọi `Sources/**/*.swift` phải khớp pattern của ít nhất một doc, **và** phải được ít nhất một doc `content` phủ — nếu chỉ doc `structure` phủ thì sửa nội dung không làm doc nào stale), FAIL kèm tên file nếu vi phạm; thêm `--explain [--since REF]` liệt kê doc stale + lý do + file Swift đã đổi; thêm `--accept DOC…` (từ chối nếu vùng GENERATED không đổi) và `--no-change-needed DOC…` (ghi nhận "đã xem, vẫn đúng"); `--update-hashes` chỉ accept doc đã sửa rồi **FAIL nếu còn doc stale**; `--bootstrap` dành riêng cho lần đổi `sourcePatterns`. Tên doc nhận `08`, `08_lifecycle.md` hoặc đường dẫn đầy đủ; output ép UTF-8 để chạy được trên console Windows.
* **Phạm vi `11_subsystems.md`** mở rộng thành `Sources/Services/**` + `Sources/Views/**` + `Sources/Models/Extensions/*` để 218/218 file đều có doc content-mode phụ trách (trước đó 49 file Views chỉ được doc structure phủ, và 12 file chưa từng nằm trong `sourceFiles` của doc nào).
* **`rules.md` §6.2 + §7**: thêm Doc Routing Policy / Doc Review Policy / Coverage Rule, viết lại Manifest Hash Policy theo 3 hash, và bỏ thói quen `--update-hashes` vô điều kiện khỏi checklist.
* **`CLAUDE.md` / `AGENTS.md`**: mục Commands liệt kê 5 chế độ validator và nêu rõ không có hook/CI nào chạy nó — đây là cổng chạy tay.
* Cổng đã được tự kiểm chứng bằng cách giả lập stale trong `manifest.json` (không sửa `Sources/`): read-only FAIL đúng tên doc → `--update-hashes` từ chối bless → `--accept` bị chặn vì GENERATED không đổi → `--no-change-needed` xoá stale; trường hợp "thêm file mới" cũng báo đúng tên file thêm vào.

## [1.3.229] - 2026-08-21

### Cập nhật tài liệu CodeGraph khớp code: highlight TTS, thermal, cache prefetch, số liệu file

Sửa **tài liệu** (không đụng `Sources/` hay `Tests/`) tại 22 điểm đã trôi so với code hiện tại. Toàn bộ nội dung nằm trong vùng `<!-- GENERATED START/END -->` và YAML front matter; không đụng "Ghi chú thủ công".

* **Highlight & selection (`rules.md`, `CLAUDE.md`, `AGENTS.md`)**: `TTSParagraph.range` là offset UTF-16 trên chuỗi **đang hiển thị** và **tương đối dòng cha**, `sourceRange` mới ánh xạ về text gốc. `ReaderSelectionMapper.mapHighlight`/`mappedRangeUsingOriginalSpans`/`proportionalHighlightFallback` đã xoá ở 1.3.81 — bỏ yêu cầu map highlight; `ReaderSelectionMapper` chỉ còn `mapSelection`.
* **Thermal (`rules.md`, `00_index`, `06`, `10`, `13`)**: bỏ mọi mô tả gating theo `.serious`/`.critical` cho Nghi/Remote refill và next-chapter audio. Thermal chỉ là telemetry/diagnostic (`TTSManager.currentThermalState` + energy log). `NghiSynthesisPolicy` chỉ giữ watermark (`defaultSafeCachedTimeThreshold = 8.0`, dải `4.0...20.0`) và `maxOptionalReserveItems = 2`, không cooldown/thermal eligibility; retry refill là backoff 1s (tối đa 2 lần) do `TTSManager` sở hữu.
* **Cache prefetch (`rules.md`, `CLAUDE.md`, `AGENTS.md`)**: `preloadedWavs` → `preloadedData`/`preloadedDurations`; cửa sổ đúng là Remote `[N, N+count]` (count clamp 1…10), Nghi `N` + `N+1` bắt buộc + ≤2 optional reserve.
* **Audio playback (`13`, `10` R-05/R-15)**: node graph `AVAudioEngine` được dựng nhưng **không phát** (`TTSAudioEngineController.play()` không caller, không `scheduleBuffer`); phát thật qua `AVAudioPlayer` (`NghiAudioPlayerQueue` double-buffer cho nghitts, `TTSManager.audioPlayer` cho google/ext) và `AVSpeechSynthesizer` cho `system`. Retain-cycle risk chuyển về callback delegate `AVAudioPlayer`.
* **Lifecycle & callbacks (`08`, `13`)**: chỉ còn callback `onChapterFinished` (bỏ `onChapterNext`/`onChapterPrev`); Reader không nil callback trong `onDisappear`. `onDisappear` chạy `shutdown(saveProgress: !ttsOwnsProgress)` + `ChapterContentRepository.flush(bookId:)`; `saveProgressImmediately()` thuộc nhánh `scenePhase == .background`.
* **Logging (`rules.md`, `CLAUDE.md`, `AGENTS.md`)**: `app_logs.txt` ở `applicationSupportDirectory`, không phải `Documents`; `AppLogger.init` set `isLoggingEnabled = false` mỗi lần khởi chạy, tự xoá khi >5 MB.
* **Model schema (`rules.md`)**: thêm `DownloadTaskModel` (schema có 5 `@Model`).
* **Sai lệch tên/đường dẫn**: `TTSPresentationEventCenter.shared.events` → `.stream` (`04`); `DisplayTextFormatter.swift` ở `Common/Extensions/` (`02`); `ReaderSelectionCoordinator` là misnomer, chỉ có `getHanViet`+`formatMeaning` (`03`); miễn trừ SwiftUI khớp hậu tố `*WebViewLoader.swift`, hiện không file Services nào import SwiftUI (`09`, `rules.md`).
* **Sparse paragraph IDs**: sửa cùng một câu ở `00_index`, `06`, `08`, `10`, `13`, `14` — `ChapterTextLine.id` là chỉ số dòng thô (tính cả dòng trống), không phải array index; `utf16Range` không dùng để cắt `content`.
* **Số liệu (`14`, `00_index`, `02`, front matter 16 file)**: `source_files` → `218`; §1.1/§1.2 dựng lại theo `wc -l` và công thức CC của doc; §1.3 đổi nhãn thành "Max Brace Nesting Depth" (giá trị thật 10–18). `ReaderParagraphBuilder`/`TTSParagraphBuilder.build(from:)` chỉ test dùng, không caller production (`00_index`).

## [1.3.228] - 2026-08-21

### Khắc phục lỗi pop Chi tiết truyện khi vuốt tab Home Khám phá

* **`Sources/Views/Discovery/DiscoveryView.swift`**: Khai báo `DiscoveryDetailRoute` tuân thủ `Identifiable, Hashable` giữ các thuộc tính bất biến (`bookId`, `extensionPackageId`, `initialDetailUrl`, `sourceName`, `initialHost`); di chuyển `@State selectedDetailRoute` và `.navigationDestination(item: $selectedDetailRoute)` từ `DiscoveryCategoryTabView` lên root `NavigationStack` trong `DiscoveryView`.
* **`DiscoveryCategoryTabView`**: Bỏ `@State selectedNovel` và `.navigationDestination` cục bộ, nhận callback `onSelectNovel: (ExtensionItemResult) -> Void` từ view cha khi bấm vào một hàng truyện.
* Bảo toàn route state không bị reset hay tháo gỡ khi swiping tab Home trong `TabView`; cập nhật CodeGraph tại `00_index.md`, `06_event_graph.md`, và `12_ownership_graph.md`.

## [1.3.227] - 2026-08-20

### Mở rộng vùng bấm lịch sử tìm kiếm

* **`ShelfSearchView.historyView` / `SearchView.searchHistoryView`**: label nút chọn lịch sử chiếm toàn bộ chiều rộng còn lại và dùng `Rectangle` cho hit testing, nên vùng trống trước nút `x` có thể bấm được.
* Giữ nút xóa độc lập và không đổi action chọn lịch sử, layout row, scroll hay logic lọc; cập nhật CodeGraph tại `00_index.md` và `06_event_graph.md`.

## [1.3.226] - 2026-08-20

### Chuẩn hóa hằng số Extension.type

* **`Sources/Models/Extensions/ExtensionType.swift`**: thêm namespace public với các giá trị chuẩn `novel`, `chineseNovel`, `comic`, và `tts`.
* Thay literal biểu diễn `Extension.type` trong model command, metadata import, repository policy, Search, Discovery, TTS Settings và UI quản lý extension; giữ nguyên script key/action TTS, sentinel `"all"`, schema `String` và dữ liệu hiện có.
* Không migration, không đổi public API shape và không khóa type lạ; cập nhật CodeGraph tại `00_index.md`, `02_file_graph.md`, `03_type_graph.md`, `09_dependency_rules.md`, và `11_subsystems.md`.

## [1.3.225] - 2026-08-20

### Loại nguồn TTS khỏi tìm kiếm tất cả truyện

* **`Sources/Views/Search/SearchView.swift`**: thêm `searchableExtensions = activeExtensions.filter { $0.type != "tts" }`; chế độ tất cả nguồn dùng tập này cho task search, source state, render kết quả và `Xem thêm`.
* Không đổi tìm một nguồn cụ thể, public API, model hay chính sách lọc của caller; cập nhật CodeGraph tại `00_index.md`, `04_call_graph.md`, `06_event_graph.md`, và `07_dataflow.md`.

## [1.3.224] - 2026-08-20

### Persist titleTrans cho local TXT, preview bounded và search hai cột

* **TXT import**: `ParserChapter`/`ParsedBook` trở thành `Sendable`; `ShelfView.performImport` dịch title và dựng toàn bộ metadata trong `Task.detached`, persist `titleTrans` cùng title gốc và tái sử dụng snapshot khi ghi cache. `BookTransactionCoordinator.insertChapterDTO` nhận thêm `titleTrans` optional cho nhánh SwiftData dự phòng.
* **Confirmation sheet**: tối đa sáu chương hiển thị toàn bộ; trên sáu chương chỉ render ba đầu, một dòng số chương bị lược và ba cuối. Reanalyze dùng cùng preview.
* **Chapter search**: bỏ `searchTrans` khỏi ChapterStore API; SQLite và các bộ lọc local BookDetail luôn OR `title`/`titleTrans`, còn toggle dịch chỉ điều khiển presentation. Không migration localBook cũ.
* Không thay đổi parser, DocumentPicker, nội dung chương hay TOC online; cập nhật CodeGraph tại `00_index.md`, `03_type_graph.md`, `04_call_graph.md`, `06_event_graph.md`, `07_dataflow.md`, và `08_lifecycle.md`.

## [1.3.223] - 2026-08-20

### Không còn khoảng trống giữa wait layer parse TXT và sheet xác nhận

* **`Sources/Views/Shelf/ShelfMain/ShelfView.swift`**: nhánh parse thành công giữ `isParsingTXT` bật sau khi gán `pendingImport`; chỉ tắt khi `TXTImportConfirmationSheet.onAppear`. Nhánh lỗi và cleanup Hủy/Nhập giữ nguyên.
* **`Sources/Views/Shelf/ShelfMain/TXTImportConfirmationSheet.swift`**: danh sách chương dùng `LazyVStack` và duyệt trực tiếp `parsed.chapters.indices`, tránh dựng/copy toàn bộ row trước khi sheet xuất hiện.
* Không đổi DocumentPicker, parser, reanalyze hay database import; cập nhật CodeGraph tại `00_index.md`, `04_call_graph.md`, `06_event_graph.md`, và `08_lifecycle.md`.

## [1.3.222] - 2026-08-20

### Toggle dịch đúng cho tác giả/tên chương và history ShelfSearch tự co chiều cao

* **`Sources/Views/Common/BookListItemView.swift`**: tác giả chỉ phiên âm Hán-Việt khi `isTranslationEnabled` bật; khi tắt hiển thị author gốc trên mọi row dùng chung của Shelf/History/ShelfSearch.
* **`Sources/Views/Reader/ReaderViewModel.swift` / `Sources/Services/ReadingProgress/ReadingProgressStore.swift`**: thêm đường lấy original chapter title riêng cho progress, không persist `CachedChapter.title` đã dịch; snapshot title rỗng được bỏ qua để fallback sang TOC gốc.
* **`Sources/Views/Shelf/ShelfMain/ShelfView.swift`**: `"Dịch lại tên chương"` chỉ cập nhật `titleTrans`, bỏ ghi bản dịch vào `Book.currentChapterTitle`. Không triển khai migration phục hồi dữ liệu cũ theo yêu cầu người dùng.
* **`Sources/Views/Shelf/ShelfMain/ShelfSearchView.swift`**: history khớp query co theo tối đa bốn row, không giữ khoảng trống khi không match và chỉ scroll khi vượt bốn kết quả.
* Không đổi quy chuẩn trong `rules.md`; cập nhật CodeGraph tại `00_index.md`, `04_call_graph.md`, `06_event_graph.md`, và `08_lifecycle.md`.

## [1.3.221] - 2026-08-20

### Upsert rule thay thế TTS khi thêm trùng pattern

* **`Sources/Services/TTS/Preprocessing/TTSReplacementManager.swift`**: `addRule(_:)` xóa toàn bộ rule cũ có cùng pattern chính xác rồi append rule mới xuống cuối và chỉ `saveRules()` một lần; trả `AddRuleResult.added/replaced` với `@discardableResult` để giữ tương thích caller hiện có.
* **`Sources/Views/Reader/ReaderView.swift`**: dùng kết quả từ manager để Toast phân biệt `"Đã thêm"` và `"Đã cập nhật"` thay thế TTS.
* Không đổi `updateRule(_:)`, import JSON hay quy chuẩn kiến trúc trong `rules.md`; cập nhật CodeGraph liên quan ở `00_index.md`, `04_call_graph.md`, `06_event_graph.md`, và `11_subsystems.md`.

## [1.3.220] - 2026-08-20

### Đồng bộ Download/Detail và chuyển Phồn thể → Giản thể theo truyện

* **`Sources/Views/Download/DownloadTrackerView.swift`**: task row dùng cover 50x70 và title 14.5pt semibold, tối đa 2 dòng — cùng style cover/title với Shelf và History.
* **`Sources/Views/BookDetail/BookDetailHeaderView.swift`**: title được cố định theo chiều dọc để không cắt tên truyện dài trong cột bên cạnh cover.
* **`Sources/Views/Reader/ReaderSettingsView.swift` / `ReaderView.swift`**: thêm Picker `"Văn bản trước khi dịch"`, lưu `convertTraditionalToSimplified_<bookId>` và làm mới bản dịch khi đổi lựa chọn.
* **`Sources/Services/Translation/Utils/TranslateUtils.swift`** và pipeline Reader: khi bật, dùng ICU transform `StringTransform("Traditional-Simplified")` để chuẩn hoá phồn thể sang giản thể trước tra từ điển; text lưu trữ không đổi và translation spans chỉ dùng khi bảo toàn UTF-16. Cờ cấu hình trở thành một phần identity của `CachedChapter`; TOC paging/search và popup dịch từ/câu cũng dùng cùng cấu hình.
* **Pipeline TTS (`TTSManager`, `TTSBackgroundProcessor`, prepared models/prefetch workers)**: áp dụng cùng option cho title/nội dung TTS của chương hiện tại, auto-advance, text/audio prefetch chương kế và metadata Now Playing. Key/snapshot mang cờ chuyển đổi để loại cache khác cấu hình; đổi option giữa phiên hủy prefetch cũ nhưng không ngắt audio chương đã dựng.
* Không đổi quy chuẩn kiến trúc trong `rules.md`; các cập nhật CodeGraph liên quan nằm trong `00_index.md`, `06_event_graph.md`, và `08_lifecycle.md`.

## [1.3.219] - 2026-08-20

### Revert dùng BookListItemView trong DownloadTrackerView, chuẩn hoá BookListItemView 2 style và bỏ chevron NavigationLink

* **`Sources/Views/Download/DownloadTrackerView.swift`**: revert `taskRow` về HStack cover+title custom gốc (cover 44x60, title `.headline` lineLimit(1), badge taskType, `statusBadge`, ProgressView, nút cancel/share/retry, contextMenu). Bỏ `extension DownloadTask: BookDisplayable`; `taskRow` dịch title nội bộ qua `@AppStorage("isTranslationEnabled")` + `TranslateUtils.translateMeta`. Giữ `.contentShape(Rectangle())` và Toast `exportFromCached`.
* **`Sources/Views/Common/BookListItemView.swift`**: thêm `enum BookListItemStyle { case shelfOrHistory, discovery }`. `.shelfOrHistory` default `showChapter=true`/`showDescription=false`; `.discovery` default `showChapter=false`/`showDescription=true`. Init nhận `showChapter`/`showDescription` dạng `Bool?` (nil → theo style). Cover 50x70 + title `.system(size:14.5, weight:.semibold)` lineLimit(2) đồng bộ mọi style; HStack author/source chỉ render khi `hasAuthor || hasSource`.
* **`Sources/Views/Common/CategoryNovelsListView.swift`**: `BookListItemView(item: novel, style: .discovery)` (bỏ override cover 60x80); đổi `NavigationLink` → `Button` + `@State selectedNovel` + `.navigationDestination(item:)` để bỏ chevron.
* **`Sources/Views/Discovery/DiscoveryView.swift`**: `DiscoveryCategoryTabView` dùng `BookListItemView(item: novel, style: .discovery)`; đổi `NavigationLink` → `Button` + `selectedNovel` + `.navigationDestination(item:)`.
* **`Sources/Views/Shelf/ShelfMain/ShelfView.swift`**: dời 3 overlay chờ (`isParsingTXT`/`isImporting`/`isProcessingDeletion`) ra khỏi closure `.sheet(item: $pendingImport)` thành sibling của `VStack` trong `ZStack` — fix không hiển thị khi `pendingImport == nil`. Sheet content chỉ còn `TXTImportConfirmationSheet`.
* **`Sources/Services/Extensions/Manager/ExtensionManager.swift`**: `ExtensionItemResult` thêm conformance `Hashable` (dùng làm item của `.navigationDestination(item:)`).
* `ShelfView`, `ShelfSearchView`, `BookShareTargetSheet` dùng default `.shelfOrHistory` (BookShareTargetSheet override `showChapter: false`) — không đổi API. Không cần cập nhật `rules.md`.

## [1.3.218] - 2026-08-20

### Tái sử dụng BookListItemView trong DownloadTrackerView và bỏ chevron NavigationLink

* **`Sources/Views/Download/DownloadTrackerView.swift`**: thêm `extension DownloadTask: BookDisplayable` (title→`bookTitle`, coverUrl→`bookCoverUrl`, còn lại rỗng/0; `bookId` có sẵn). `taskRow` bỏ HStack cover+title custom → `BookListItemView(item: task, showChapter: false)`; badge taskType, statusBadge, ProgressView, nút cancel/share/retry + contextMenu chuyển xuống dưới row truyện trong `VStack`. Bỏ dịch title thủ công trong taskRow (BookListItemView tự dịch nội bộ qua `@AppStorage`); giữ `@AppStorage("isTranslationEnabled")` để dùng trong Toast `exportFromCached` (bọc `TranslateUtils.translateBookTitleIfNeeded`).
* **`Sources/Views/Common/CategoryNovelsListView.swift`**: thêm `.buttonStyle(.plain)` lên NavigationLink → bỏ chevron `>` mặc định, giữ tap đi chi tiết.
* **`Sources/Views/Discovery/DiscoveryView.swift`**: thêm `.buttonStyle(.plain)` lên NavigationLink → bỏ chevron `>` mặc định ở `DiscoveryCategoryTabView` (home tabs).
* Không đổi public API Service/Manager, không đổi dependency tầng logic; không cần cập nhật `rules.md`.

## [1.3.217] - 2026-08-20

### Import TXT: bảng mã giải mã đa dạng, xác nhận trước khi nhập, overlay Material

* File mới `Sources/Common/Utils/TextEncodingDecoder.swift`: helper giải mã `Data → String` thử tuần tự 20 bảng mã (UTF-8/BOM, UTF-16LE/BE, UTF-32LE/BOM/BE, GB18030, GBK, Big5-HKSCS, Big5, EUC-JP, windowsVietnamese/CP1258, VSCII/TCVN3, ISO-8859-1, windows-1250/1251/1252/1253/1254, ASCII). Mã đơn byte đặt cuối để tránh nuốt nhầm file tiếng Trung.
* `JSExecutor.decodeData` dùng chung `TextEncodingDecoder.decode(data)` thay cho logic tự viết.
* `ShelfView` tách import TXT thành 3 giai đoạn: `importTxtBook(from:)` (copy + decode + parse → hiện sheet xác nhận, giữ file tạm), `performImport()` (tạo Book + ghi chương + progress, xóa temp), `cancelImport()` (xóa temp). Thêm `PendingImport` struct + state `pendingImport`/`showImportConfirmation`/`importIsIndeterminate`.
* Sheet mới `Sources/Views/Shelf/ShelfMain/TXTImportConfirmationSheet.swift`: hiện tên truyện, số chương, tên file và danh sách toàn bộ chương trước khi nhập; nút Hủy/Nhập.
* Overlay import + overlay xóa sách bọc trong ZStack riêng (fix lệch giữa), card `.ultraThinMaterial`, spinner khi indeterminate, thanh linear + % khi ghi chương.

## [1.3.216] - 2026-08-20

### Đồng bộ badge nguồn sách thành capsule xám giữa detail, BookListItemView và ReaderChapterListView

* **Phạm vi**: 3 badge hiển thị tên nguồn/extension (và "Local") đồng nhất style capsule xám trung tính, thay thế pill xanh.
* **Style mới**: icon extension + chữ `.caption2` medium `.secondary`, nền `Color.secondary.opacity(0.12)` bo `Capsule()`, padding `(6, 2)`. Font size không đổi.
* **`Sources/Views/BookDetail/BookDetailHeaderView.swift`**: badge nguồn bỏ trạng thái chỉ icon+chữ → bọc thêm nền capsule; fallback `puzzlepiece.extension` giảm 16→14pt.
* **`Sources/Views/Common/BookListItemView.swift`**: protocol `BookDisplayable` thêm `extensionLocalPath: String` (default `""`) và `extensionIconUrl: String?` (default `nil`) qua `extension BookDisplayable`; `BookListItemView` thêm 2 init param `extensionLocalPath`/`extensionIconUrl`; badge thay 2 nhánh pill xanh (`Local`/`sourceName`) bằng helper `sourceBadge(text:)` (icon + chữ trong capsule). `Book` conformance giữ default.
* **`Sources/Views/Shelf/ShelfMain/ShelfView.swift`**: `bookItemView` resolve `allExtensions.first(where: { $0.packageId == book.extensionPackageId })` và truyền `localPath`/`iconUrl` vào `BookListItemView`.
* **`Sources/Views/Shelf/ShelfMain/ShelfSearchView.swift`**: thêm `@Query private var allExtensions: [Extension]`; resolve extension và truyền icon.
* **`Sources/Views/Dictionary/BookShareTargetSheet.swift`**: thêm `@Query private var allExtensions: [Extension]`; resolve extension và truyền icon.
* **`Sources/Views/Reader/ReaderChapterListView.swift`**: badge `Local`/`ext.name` đổi từ pill xanh sang capsule xám; dùng sẵn đối tượng `ext` để lấy `localPath`/`iconUrl`; không đổi API view.
* Không đổi public API Service/Manager, không đổi font size; không cần cập nhật `rules.md`.

## [1.3.215] - 2026-08-20

### Giảm cỡ chữ toàn bộ BookListItemView và BookDetailHeaderView

* **Phạm vi**: Thu nhỏ font theo tỉ lệ ~×0.85 (floor 11pt) cho mọi thành phần text của 2 view hiển thị title sách, giữ title luôn là phần lớn nhất; bỏ giới hạn số dòng title ở detail.
* **`Sources/Views/Common/BookListItemView.swift`**: title `.headline` (17pt semibold) → `.system(size: 14.5, weight: .semibold)`; author `.subheadline` (15pt) → `.system(size: 13)`; dòng "Đang đọc" `.caption` (12pt) → `.caption2` (11pt). Badge nguồn/Local và description giữ `.caption2`.
* **`Sources/Views/BookDetail/BookDetailHeaderView.swift`**: title `.title3.bold` (20pt bold) + `lineLimit(3)` → `.headline` (17pt semibold) không còn `lineLimit`; section "Thể loại"/"Giới thiệu" `.headline` (17pt) → `.system(size: 14.5, weight: .semibold)`; author `.subheadline` (15pt) → `.system(size: 13)`; tên nguồn `.caption.medium` (12pt) → `.caption2.medium` (11pt); giới thiệu (ExpandableTextView) `.body` (17pt) → `.system(size: 14.5)`. Metadata `caption2` và genre tags giữ nguyên.
* Không đổi public API, protocol `BookDisplayable` hay dependency; không cần cập nhật `rules.md`.

## [1.3.214] - 2026-08-19

### Badge tên nguồn (extension / Local) trong Reader danh sách chương và BookListItemView

* **Phạm vi**: 2 view hiển thị pill nguồn sách được bổ sung nhánh badge "Local" và chuẩn hoá hiển thị tên extension.
* **`Sources/Views/Reader/ReaderChapterListView.swift`**: Trong `header`, bọc text `"\(store.totalCount) chương"` vào `HStack(spacing: 6)` và thêm badge pill bên cạnh — nếu `isLocalTXTBook == true` hiển thị `"Local"`, ngược lại nếu `ext != nil` (và `ext.name` không rỗng) hiển thị `ext.name`. Style pill xanh: `.caption2`, `.lineLimit(1)`, `.padding(.horizontal, 6)` / `.padding(.vertical, 2)`, `.background(Color.blue.opacity(0.1))`, `.foregroundColor(.blue)`, `.cornerRadius(4)`. Giữ nguyên `Spacer(minLength: 4)` và nút refresh/sort; không đổi API của view.
* **`Sources/Views/Common/BookListItemView.swift`**: Thêm `isLocalBook: Bool` vào protocol `BookDisplayable` (default `false` qua `extension BookDisplayable`); `Book` thoả mãn sẵn qua computed property `Book.isLocalBook` (dựa trên `extensionPackageId`/`detailUrl`/`sourceUrl`/`sourceName` local), `ExtensionItemResult` dùng default. Khối pill nguồn thay bằng nhánh: `item.isLocalBook == true` → pill `"Local"`, ngược lại `!item.sourceName.isEmpty` → pill `sourceName` (giữ nguyên hành vi cũ cho sách online).

## [1.3.213] - 2026-08-19

### Revert toàn bộ về c78d042, giữ lại các tính năng logic (trừ hiển thị Detail và danh sách chương từ Reader)

* **Phạm vi**: Đưa toàn bộ mã nguồn về trạng thái commit `c78d042`, sau đó thêm lại các tính năng không thuộc 2 nhóm bị loại.
* **Loại bỏ (trình bày Detail)**: `BookDetailRoute`/`DetailRouter`, root presentation hub `ReaderRouter`/`DetailRouter` (2 `.fullScreenCover` root trong `AppLaunchRootView`), `BookDetailRoute` rải khắp 9 view (ShelfView, SearchView, DiscoveryView, CategoryNovelsListView, SuggestRowView, ReaderChapterListView, ReaderView, BookDetailView import), fix crash env injection (1.3.212). Detail quay lại mở bằng `NavigationLink` push trong NavigationStack của tab (tab bar hiện).
* **Loại bỏ (danh sách chương từ Reader)**: Bottom Sheet `presentationDetents` (978f200), badge nguồn, prefetch & giảm skeleton, fix skeleton forever, refactor single source of truth (82af6f8) và việc xoá `ReaderChapterListPageFetcher.swift`/`Tests/ReaderViewModelTests.swift`. Danh sách chương quay lại overlay custom (`readerChapterListOverlay` + Capsule + `dismissGesture`).
* **Loại bỏ (trình bày Reader)**: root ReaderRouter, fix re-creation loop (8e53471/144feb4), ẩn nav bar detail khi reader mở (3d090af), gỡ ignoresSafeArea (8978405), diagnostics (99d5fb3). Reader mở bằng `.fullScreenCover(item: $readerRoute)` cục bộ trong `BookDetailView` như c78d042.
* **Thêm lại (Nhóm C)**: `VietPhraseTokenizer` (tiếng Việt có dấu, số thập phân, gom cụm Latin/ASCII), `TranslateUtils` gom token tên tác giả, `ExpandableTextView` (căn lề 2 bên Description, layout-safe, fix "Xem thêm", fix comment, `WrappingLabel` public) + `Tests/ExpandableTextViewTests.swift`, `TTSManager` khôi phục chính xác chunk TTS, `TTSQuickTimerSheet` (spacing, nút gearshape, detents 0.85), tối ưu `BookListItemView`/`BookDetailHeaderView`, cải tiến Lịch Sử Đọc trong `ShelfView` (sort theo `lastReadDate`, `removeFromHistory` thông minh), toast thông minh cập nhật mục lục trong `ReaderChapterListView+Refresh`.
* **File mới/xoá**: xoá `Sources/Views/Reader/ReaderRouter.swift`; khôi phục `Sources/Services/ChapterText/Workers/ReaderChapterListPageFetcher.swift` và `Tests/ReaderViewModelTests.swift`; thêm `Tests/ExpandableTextViewTests.swift`.
