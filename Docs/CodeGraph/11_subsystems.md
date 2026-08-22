---
generated_by: Antigravity
generator_version: 1.0
generated_at: 2026-08-21T10:30:00+07:00
git_commit: UNKNOWN
source_files: 230
document_version: 6
---

# Phân tích các Phân hệ Cốt lõi (Subsystems)

Tài liệu này phân tích chi tiết 14 phân hệ chính cấu thành nên ứng dụng FreeBook, mô tả mục tiêu, API công khai, dependency, quan hệ sở hữu đối tượng, điểm vào/ra, vòng đời và các rủi ro tương ứng cho từng phân hệ.

## Ghi chú thủ công (Human Notes)
*Ghi chú thủ công của con người.*

<!-- GENERATED START -->
## Phân hệ Reader: quan sát view model là trách nhiệm của một relay riêng (1.3.243)

* Phân hệ Reader có thành viên mới: `Components/ReaderViewModelInvalidationRelay.swift` (40 dòng, 1 primary type) — `ObservableObject` duy nhất có nhiệm vụ forward `ReaderViewModel.objectWillChange` sang `ReaderView`. Nó tồn tại vì `ReaderViewModel` chỉ có sau khi bootstrap mục lục nên phải ở `@State`, mà `@State` không subscribe gì cả.
* Ranh giới: relay **không** đọc, không lọc, không sửa state — không có API nào ngoài `observe(_:)`. Nó không biết `pendingNavigationIndex` hay `navigationCommit` là gì; quyết định render vẫn nằm nguyên ở cổng `isChapterSubtreeRenderable(_:)` của `ReaderView+LoadingView` (1.3.242) và ở `ReaderScrollCoordinator`.
* Mẫu này khớp với phân hệ TTS Widget, nơi `FloatingWidgetViewModel` được giữ bằng `@ObservedObject`. `ReaderViewModel` là view model duy nhất còn lại nằm trong `@State`, nên đây là chỗ duy nhất cần relay. Nếu sau này Reader dựng được view model ngay lúc `init` thì relay nên bị xoá thay vì giữ song song.
* `ReaderViewModel` **không đổi public API** và vẫn là `ObservableObject` với 15 `@Published`. `ReaderView.swift` 2263 → 2268 dòng (thêm một `@StateObject`, hai lời gọi `observe`), vẫn là `LINE_LIMIT_EXCEEDED` cũ. Tổng file Swift 231 → 232.
* Không phân hệ nào khác đổi ranh giới: TTS, Translation, Extension giữ nguyên; quyền sở hữu tiến độ khi TTS đang phát và đường highlight không đụng tới.

## Phân hệ Reader: render gate thuộc về `ReaderView+LoadingView` (1.3.242)

* `Extensions/ReaderView+LoadingView.swift` (112 dòng) nhận thêm một trách nhiệm ngoài việc dựng skeleton: nó sở hữu **luật mở cổng** dựng subtree chương — `isChapterSubtreeRenderable(_:)`. `ReaderView.swift` (2263 dòng) chỉ còn *áp dụng* luật đó trong `singleChapterReaderView` và khai hai `@State` mà luật đọc (`renderedChapterIndex`, `skeletonHandshakeIndex`).
* Ranh giới quan trọng: cổng này là chuyện **thứ tự render**, không phải chuyện điều hướng. `ReaderViewModel` không biết tới nó, không type nào ở tầng dưới đổi API, và `ReaderScrollCoordinator` vẫn là nơi duy nhất chọn neo.
* `ReaderEnergyDiagnostics` (338 dòng) không đổi: ba mốc `Tap → Skeleton → Present` giữ nguyên ngữ nghĩa, nhưng từ 1.3.242 dòng `Skeleton` phải có mặt ở **mọi** lượt đổi chương — thiếu nó là dấu hiệu cổng bị bỏ qua.
* `ReaderView.swift` và `ReaderViewModel.swift` vẫn là hai `LINE_LIMIT_EXCEEDED` cũ (2263 / 933), không phải violation mới.

## Phân hệ Reader: một cửa điều hướng duy nhất (1.3.241)

* Ranh giới điều hướng của phân hệ Reader thu về **một cửa**: `ReaderView.requestChapter(at:paragraphIndex:source:persistProgress:)` (đổi từ `private` sang `internal`). `ReaderViewModel.stepChapter` đã xoá — public API của view model giảm đúng một hàm, không thêm gì.
* `Extensions/ReaderView+Controls.swift` (211 dòng) nhận thêm owner của pha hai hạ cánh: `scheduleDeepLandingScroll(_:)`. `ReaderView.swift` (2252 dòng) chỉ giữ quyết định "hạ cánh đầu chương trước" trong `applyNavigationCommit`; `ReaderScrollCoordinator` không đổi — nó vẫn là nơi duy nhất chọn neo `paragraph-N-P`/`chapter-N`.
* `Components/ReaderEnergyDiagnostics.swift` (338 dòng) mở rộng vai trò instrumentation: ngoài `Summary`/`NavRealize`/`Scroll`, nay sở hữu ba mốc `[ReaderPerf] Tap` → `Skeleton` → `Present` (ms kể từ cú bấm). Cả ba vẫn sau cờ `isEnabled` latch một lần ở `beginReaderSession()`.
* Cả hai file `LINE_LIMIT_EXCEEDED` cũ vẫn là violation cũ, không phải mới: `ReaderView.swift` 2252 (+6), `ReaderViewModel.swift` 931 (−12).
* Không phân hệ nào khác đổi ranh giới: TTS, Translation, Extension giữ nguyên; quyền sở hữu tiến độ khi TTS đang phát và đường highlight không đụng tới.

## Phân hệ Reader: instrumentation nay phủ cả navigation (1.3.240)

* `Components/ReaderEnergyDiagnostics.swift` (306 dòng) mở rộng vai trò: ngoài cửa sổ đo 60 giây và dòng `[ReaderEnergy] Summary`, nó là owner duy nhất của bộ đếm card realize (`recordParagraphRealized`, cột `paragraphRealized` trong `Summary`, dòng `[ReaderPerf] NavRealize`) và của dòng `[ReaderPerf] Scroll`. Mọi API vẫn thoát ngay bằng `guard isEnabled` với cờ latch một lần ở `beginReaderSession()`.
* `Coordinators/ReaderScrollCoordinator.swift` không quyết định gì thêm — chỉ báo cáo neo đã chọn (`paragraph` / `chapterFallback` / `chapterTop`) cho diagnostics. Cố ý **không** đo ms quanh `proxy.scrollTo`: hàm đó chỉ ghi nhận neo, còn phần đắt (realize + đo card trung gian của `LazyVStack`) xảy ra ở layout pass sau đó, nên ms tại chỗ sẽ gần 0 và gây hiểu sai.
* Ranh giới trách nhiệm Next/Prev dịch sang `Extensions/ReaderView+Controls.swift` (192 dòng): `stepChapterHonoringTTS` là nơi duy nhất biết luật "hạ cánh thẳng vào đoạn TTS đang đọc". `ReaderView.swift` còn 2246 dòng, `ReaderViewModel.swift` tăng lên 943 dòng — cả hai vẫn là `LINE_LIMIT_EXCEEDED` cũ, không phải violation mới.
* Không phân hệ nào đổi public API. `ReaderViewModel` thêm một private task (`memoryCommitTask`) và một mốc đo (`navigationStartUptime`); đường highlight, `ParagraphTracker.minimumFrameDelta`, và quyền sở hữu tiến độ khi TTS đang phát đều giữ nguyên.

## Phân hệ Reader: đo đếm năng lượng tách khỏi bridge UIKit (1.3.239)

* Phân hệ **Reader** nay có ranh giới rõ giữa *bridge UIKit* và *instrumentation*: `ReaderTextView.swift` (450 dòng) chỉ còn `UIViewRepresentable` + `ReaderUITextView`/`AutoSizingTextView`, còn `Components/ReaderEnergyDiagnostics.swift` (258 dòng) là owner duy nhất của cửa sổ đo 60 giây và dòng log `[ReaderEnergy] Summary`.
* Instrumentation của Reader nay **tắt hoàn toàn theo mặc định**: `AppLogger.init` set `isLoggingEnabled = false` mỗi lần khởi chạy, `beginReaderSession()` chốt cờ đó một lần, và mọi `record*` thoát ngay bằng `guard isEnabled`. Nghĩa là số liệu `[ReaderEnergy]` chỉ tồn tại khi người dùng bật log trong Settings **trước** khi mở Reader — đúng chủ ý, không phải mất log.
* Đường selection của Reader (bôi đen → `FloatingSelectionMenu`) nay là consumer duy nhất của KVO `contentOffset`. Trước đây mỗi `ParagraphCardView` đang realized đều cài một observer trên cùng `UIScrollView` để phục vụ một selection thường không tồn tại; giờ observer chỉ tồn tại trên đúng text view đang có selection. Cảm giác của menu bám theo chữ khi cuộn giữ nguyên, chỉ thêm dedup 0.5 pt để không ghi lại `@State` khi vị trí chưa đổi.
* `ParagraphTracker` giữ nguyên vai trò và ngưỡng `minimumFrameDelta = 8` — đây là ngưỡng quyết định phán quyết `isParagraphInsideSafeViewport`, nên nới nó là đổi hành vi auto-scroll, không phải tối ưu.
* Đường highlight TTS **không đổi**: `ttsState.snapshot.highlightRange` vẫn truyền thẳng xuống `ParagraphCardView` → `ReaderTextView`, vẫn guard theo `playingBookId`/`playingChapterIndex`/`currentParentParagraphIndex`, `updateUIView` vẫn chỉ sửa attribute background trên `textStorage` khi chỉ đổi highlight.

## Phân hệ sau phép tách file (1.3.236)

* Phân hệ **TTS Widget** nay có ba file thay vì một: `TTSFloatingWidgetWindowManager.swift` (chỉ còn điều phối UIWindow, 112 dòng), `FloatingWidgetUIWindow.swift` (ranh giới hit-testing), `FloatingWidgetContainerViewController.swift` (layout/gesture/animation). Ba trách nhiệm vốn đã tách trong code nay tách cả ở mức file.
* Phân hệ **Visible Browser** (`Services/Extensions/Engine/`) tách thành: `VisibleBrowserTabManager.swift` (state tab), `VisibleBrowserTabItem.swift` (DTO), `TabbedVisibleBrowserViewController.swift` (UI tab), `VisibleWebViewLoader.swift` (bridge JS), `VisibleWebViewController.swift` (WKWebView host).
* Phân hệ **Translation**: `DictionaryInvalidationScope` (DTO phạm vi invalidation) và `BookTitleTranslationBackfill` (actor chạy nền) rời khỏi file manager/migrator tương ứng.
* Không phân hệ nào đổi ranh giới trách nhiệm hay public API; đây là thay đổi tổ chức file thuần.

## Phân hệ mất thư mục Helpers và tầng test (1.3.235)

* Phân hệ TTS không còn thư mục `Services/TTS/Helpers/`: cả `TTSHighlightCalculator`, `TTSParagraphSplitter`, `TTSVoiceResolver` đều không có consumer nào trong `Sources/`. Chức năng tương ứng thực tế nằm ở `TTSParagraphBuilder`/`TTSBackgroundProcessor` (chunk hoá) và `TTSManager`/`NghiTTSClient` (chọn giọng); highlight do `commitAudibleParagraphState` phát từ `paragraphs[index]`.
* `TTSParagraphBuilder` còn đúng **một** API dựng chunk: `buildFromEntries(_:chunkLength:)`. Overload `build(from:chunkLength:)` đã xoá, nên không còn hai bản logic dựng chunk song song.
* Reader còn đúng **một** đường dựng `[ParagraphItem]`: `ReaderViewModel+Translation`. Bản song song `ReaderParagraphBuilder` đã xoá.
* Phân hệ test không còn tồn tại: `Tests/` và target `FreeBookTests` bị xoá; xác minh từ nay dựa trên đọc code, build trên macOS và hai script tĩnh.

## Phân hệ TTS: prefix audio chương kế (1.3.234)

* Phân hệ TTS nay có **ba** owner audio thay vì hai: (1) cửa sổ đoạn văn của chương đang phát (`preloadedData`/`preloadedDurations` + `prefetchTasks`/`nghiRefillTask`), (2) `TTSChapterPrefetcher` cho DTO văn bản + chunk 0 chương kế, (3) `TTSNextChapterPrefixCache` cho các chunk `>= 1` đầu chương kế.
* Owner thứ ba dùng chung cho cả ba engine tổng hợp (`nghitts`, `google`, extension); `system` (Siri) bị loại tường minh vì không có payload audio để đệm.
* Điểm nối duy nhất với phần còn lại của phân hệ là `TTSManager+NextChapterPrefix.swift`; nó quyết định capacity theo engine và là nơi duy nhất chuyển chunk prefix vào cửa sổ đoạn văn.
* Mục tiêu phân hệ: xoá vùng nghèo buffer ở biên chương (trước đây cuối chương chỉ còn 1 chunk sẵn sàng, và ngay sau khi chuyển chương phải tổng hợp lại từ chunk 1) mà **không** nâng trần bộ nhớ audio. Mỗi engine giữ đúng đơn vị đo cấu hình của nó: Google/Ext theo số chunk (`preload_size`/`googlePrefetchCount`), NghiTTS theo thời lượng (`nghittsSafeCachedTimeThreshold`) — watermark của Nghi nay đo chuỗi phát liên tục vượt qua biên chương.

## Extension type vocabulary (1.3.226)

* Extension subsystem dùng `ExtensionType` làm nguồn duy nhất cho bốn giá trị type chuẩn khi parse metadata, upsert, lọc repository và chọn UI theo type.
* Discovery/Search chỉ nhận diện nguồn đọc qua `novel`/`chineseNovel` và loại `tts` khỏi search-all; TTS Settings nhận diện extension giọng đọc qua `tts`; comic tiếp tục bị repository policy ẩn. Unknown type vẫn đi qua nhánh mặc định.

## TTS replacement manager public API (1.3.221)

* `TTSReplacementManager` sở hữu danh sách có thứ tự `[TTSReplacementRule]` và persistence `character_replacements.json`. `addRule(_:) -> AddRuleResult` bảo đảm thao tác thêm không để lại pattern trùng: xóa mọi match chính xác rồi append rule mới để giữ đúng ưu tiên áp dụng tuần tự.
* `AddRuleResult` gồm `.added` và `.replaced`; `@discardableResult` giữ tương thích với caller không cần phản hồi. `updateRule(_:)`, `deleteRule(id:)`, reorder và import/export giữ hợp đồng hiện có.

## Thành Phần & Phân Hệ Kiến Trúc (Subsystems v4.1/v5.0)

1. **Phân Hệ Quản Lý Giao Dịch Dữ Liệu (Transaction System)**:
   - `BookTransactionCoordinator`: Sở hữu mọi thao tác thêm, cập nhật metadata, thiết lập chương hiện tại, xóa sách.
   - `ExtensionTransactionCoordinator`: Sở hữu mọi thao tác thêm repo, upsert extension, lưu config, touch lastUpdated.

2. **Phân Hệ Trình Đọc & Tải Nền (Reader Subsystem)**:
   - `ReaderView`, `ReaderViewModel`, `ReaderScrollCoordinator`, `ReaderSelectionCoordinator`, `ReaderProgressScheduler`, `BackgroundPagingWorker`, `BackgroundSearchWorker`, `ReaderChapterListPageFetcher`.

3. **Phân Hệ TTS & Audio Engine (TTS Subsystem)**:
   - `TTSManager`, `TTSAudioEngineController`, `TTSPresentationEventCenter`, `DisplayTextFormatter`, `ONNXPiperEngine`.

4. **Phân Hệ Quản Lý Tiện Ích & Bóc Tách (Extension Subsystem)**:
   - `ExtensionManager`, `JSExecutor`, `JSExecutor+Async`, `BookDetailLoader`, `RepositoryFilterPolicy`.
<!-- GENERATED END -->
