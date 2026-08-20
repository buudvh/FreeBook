---
generated_by: Antigravity
generator_version: 1.0
generated_at: 2026-07-17T23:26:29+07:00
git_commit: UNKNOWN
source_files: 93
document_version: 7
---

# Bản đồ Sự kiện & Cơ chế Giao tiếp (Event Graph)

Tài liệu này liệt kê các loại sự kiện, luồng truyền tải sự kiện (UI Gestures, Notifications, Combine, AsyncStream, Delegates, MediaPlayer Remote Commands, Timers, Tasks) trong hệ thống FreeBook.

## Ghi chú thủ công (Human Notes)
*Ghi chú thủ công của con người.*

<!-- GENERATED START -->
## TXT import wait-layer handoff events (1.3.223)

* Sự kiện parse hoàn tất chỉ phát thay đổi `pendingImport`; overlay phân tích vẫn che Shelf trong lúc SwiftUI dựng/present sheet. `TXTImportConfirmationSheet.onAppear` là sự kiện duy nhất kết thúc wait layer ở nhánh thành công.
* Danh sách chương xác nhận dùng lazy rendering theo index, nên chỉ các row cần hiển thị được dựng; reanalyze thay `parsed` và lazy list cập nhật theo indices mới.

## Shelf/History translation toggle and filtered-history layout events (1.3.222)

* Đổi `isTranslationEnabled` làm `BookListItemView` render lại title, author và current chapter: author chỉ phiên âm ở trạng thái bật; trạng thái tắt dùng dữ liệu gốc mà không gọi translator.
* Reader checkpoint/background flush phát snapshot với original chapter title; persist mới không đưa display title đã dịch vào `Book.currentChapterTitle`. Action `"Dịch lại tên chương"` chỉ phát cập nhật `titleTrans` cho ChapterStore.
* Trong `ShelfSearchView`, thay đổi query làm `matchingHistory` và `matchingHistoryHeight` tính lại. Không match thì history không chiếm chỗ; 1–4 match co theo row; trên 4 match giữ cửa sổ bốn dòng và bật scroll.

## TTS replacement rule add events (1.3.221)

* Khi người dùng lưu một rule mới từ Reader hoặc màn quản lý TTS, manager so pattern chính xác với danh sách hiện tại. Nếu trùng, mọi bản cũ bị loại trước khi rule mới được append xuống cuối; `@Published rules` phát thay đổi và file JSON được ghi một lần sau trạng thái cuối.
* Reader nhận `AddRuleResult` để phát Toast phân biệt thêm mới/cập nhật. Luồng sửa rule theo ID và import cấu hình không đi qua sự kiện upsert này.

## Reader traditional-to-simplified translation option events (1.3.220)

* Trong `ReaderSettingsView`, chọn `"Phồn thể → giản thể"` ghi `convertTraditionalToSimplified_<bookId>` trong `UserDefaults`; đây là cấu hình độc lập theo từng truyện, không thay đổi tuỳ chọn dịch toàn cục.
* `ReaderView` chuyển giá trị mới cho `ReaderViewModel` và `ReaderChapterListStore`, sau đó debounce `updateCachedTranslatedContent`. Identity cache gồm translation generation, trạng thái dịch và cờ chuyển đổi, nên chương hiện tại được build lại từ text gốc; cache chương/TOC/search cấu hình cũ không được dùng lại.
* Khi cờ bật, `TranslateUtils` dùng ICU transform `Traditional-Simplified` để chuyển đầu vào sang giản thể trước khi tra từ điển. Text chương lưu trữ vẫn giữ nguyên; translation span chỉ dùng khi toạ độ UTF-16 bảo toàn, còn lại `ReaderSelectionMapper` đi qua fallback đã có.
* `TTSManager.prepareSpeaking`/`startSpeaking` đọc cùng key theo truyện và truyền cờ qua `TTSBackgroundProcessor`, prepared snapshot/key, auto-advance và `TTSChapterPrefetcher`. Đổi option khi một phiên TTS đang hoạt động cập nhật cờ session, hủy prefetch và metadata Now Playing cũ; audio/paragraph của chương đã dựng không bị ngắt, chương dựng tiếp theo dùng cấu hình mới.

## Script editor syntax checking and searchable file selection events (1.3.200)

* `ExtensionScriptEditorView`:
  - `validateScriptSyntax` initializes a fully populated `JSExecutor` instance with the extension's `localPath` and injected configs, executing `validateSyntax` without false-positive `ReferenceError` on custom runtime functions like `load()`.
  - Tapping `scriptSelectorHeader` presents `scriptPickerSheetView` with real-time keyword filtering across `displayName` and `fileName`.
  - Switching scripts dynamically reloads content and updates Gutter insets in `CodeEditorTextView`.
* `VisibleWebViewLoader` and `JSExecutor`:
  - `launchAsync`, `waitUrl` (multi-target), `block`, and `urls` events propagate between JS execution thread and `VisibleWebViewController` on the main UI thread.

## TTS sleep timer sheet interaction events (1.3.199)

* `TTSWidgetCapsuleView` opens `TTSQuickTimerSheet` modal sheet (`$showingQuickTimerSheet`).
* Selection of preset chips or custom minutes directly fires `TTSManager.shared.startSleepTimer(minutes:)` or `setStopAtEndOfChapter()`, propagating real-time countdown updates through `TTSWidgetStateReader` and `TTSPlayStateReader`.
* Cancellation triggers immediate state reset and invalidation of background timer objects.

## Extension item parsing and comment UI events (1.3.198)

* `ExtensionManager` parses `description` and `content` into distinct `ExtensionItemResult` properties.
* Comment event flows (`CommentSectionView`, `AllCommentsView`) bind `comment.description` to the header row and `comment.content` to the expandable comment body.

## Extension execution and JS runtime environment events (1.3.197)

* Extension script execution via `JSExecutor` handles all Rhino and VBook Android global functions and objects:
  - `print(...)` and `Log.log(...)` forward directly to `console.log` logging without thrown ReferenceError.
  - `sleep(ms)` pauses the JS execution thread synchronously without blocking WebKit engine loaders.
  - `toast(msg)` and `Toast.show/makeText` route to `AppLogger` and `ToastManager.shared`.
  - `UserAgent` provides desktop and mobile User-Agent strings (`system`, `chrome`, `mobile`, `safari`, `firefox`, `macos`, `windows`, `random`, `get`).
  - `Qt.translate` routes Chinese translation requests to `TranslateUtils` and `TranslationManager` (`"vi"`, `"vp"`, `"hv"`), mapping spans to `{ translateText, segments }`.
  - `Storage`: `localStorage` persists data per-extension in `UserDefaults`, `cacheStorage` caches in-memory, `localConfig` accesses extension configs, `localCookie` manages source cookies.
  - `fetch` provides comprehensive response metadata (`statusText`, `url`, `headers` dictionary & `.get()`, `header()`, `blob()`, `request`) and configurable `options.timeout`.
  - `JSDom` provides `element.attributes()`, `elements.isEmpty()`, and `elements.map(callback)`.
  - `Engine.newBrowser` provides headless browser automation (`launch`, `launchAsync`, `waitUrl`, `html(timeout)`, `callJs`, `block`, `urls`, `getVariable`, `close`).

## TTS widget passthrough and drag event routing (1.3.195)

* Touch routing for the TTS floating widget is handled authoritatively by `FloatingWidgetUIWindow.hitTest`: when a dialog/alert or `TTSSettingsSheet` is presented (`containerViewController?.presentedViewController != nil`), touches dispatch to `super.hitTest` for full modal interaction; otherwise, touches inside `widgetContainerView.bounds` hit the widget/controls, while background touches return `nil` to pass through to underlying Reader/WebView/Shelf views without interference.
* Cử chỉ kéo (drag) được bắt trực tiếp bởi `UIPanGestureRecognizer` gắn trên `widgetContainerView` với `cancelsTouchesInView = true` (không cướp tap khi bấm nhanh nút, nhưng cancel touch khi kéo tay).
* `UITapGestureRecognizer` chỉ được kích hoạt khi ở chế độ `.peeking` để xử lý tap-to-reveal, và bị vô hiệu hóa (`isEnabled = false`) khi ở `.revealed` mode để không xung đột với các nút bấm SwiftUI.
* Menu hẹn giờ, alert nhập số phút và `TTSSettingsSheet` được hiển thị trực tiếp trong `TTSWidgetContentView` bên trong `FloatingWidgetUIWindow`, đảm bảo không làm gián đoạn hay đóng `ReaderView` (`fullScreenCover`) trên cửa sổ chính.
* `FloatingWidgetContainerViewController` listens to `TTSManager.shared.$isPlaying` and `$playingBookId` via Combine to sync `CoverRotationState`. `TimelineView` rotates cover smoothly at 18°/s (20s/vòng), pausing ticks when widget is suppressed (`isWidgetActuallyVisible == false`) or playback is paused.
* Toasts are rendered via `ToastUIWindow` at `windowLevel = .alert` with `hitTest = nil`, presenting non-intrusive status HUDs above all full-screen views without intercepting any user interactions.

## Reader full-screen presentation events (1.3.192)

* All Reader entry points now present via `.fullScreenCover(item:)` instead of a `NavigationLink`/`navigationDestination` push: `ShelfView` (shelf & history rows + the `openCurrentlyPlayingReader` widget route → `readerPresentationRoute`), `ShelfSearchView` (`readerRoute`), and `BookDetailView` (`readerRoute`). Each cover wraps `ReaderView` in its own `NavigationStack`; `ReaderView` no longer calls `.toolbar(.hidden, for: .tabBar)`, so the tab bar is never hidden/shown and cannot reappear late on reader dismissal. `@Environment(\.dismiss)` (reader close button, `onSourceChanged`, `ReaderView+LoadingView`) dismisses the cover.
* `openCurrentlyPlayingReader` (widget) still flows: `MainTabView` switches to `selectedTab = 0`, then `ShelfView` sets `readerPresentationRoute` → cover presents. A reader already open for the book instead receives `navigateReaderToPlayingChapter` as before.
* `sourceChangedNavigateToShelf` is unchanged: `MainTabView` selects the shelf main tab, `ShelfView` selects the sub-tab, and `ReaderView`/`BookDetailView` dismiss (pop the reader cover / detail) after 0.3s.

## Search-history live-suggestion events (1.3.191)

* Typing in `ShelfSearchView` re-renders only the existing history block: `matchingHistory = searchHistory.filter { $0.localizedCaseInsensitiveContains(trimmedQuery) }` (full history when the query is empty), shown above `resultsView` (capped at `maxHeight: 220`). Tapping a suggestion sets `searchQuery = item`, which re-filters both the suggestions and the book results live.
* In `SearchView`, the idle branch re-uses `searchHistoryView`, which now iterates `matchingHistory`; a typed query narrows the shared history to matching entries, and tapping one sets the query and calls `performSearch()`. Web-result branches are unchanged.

## Shelf search and title-translation refresh events (1.3.190)

* Tapping the shelf search toolbar button (`ShelfView`, shown only when `selectedTab != 0`) sets `showingShelfSearch`, and `.navigationDestination(isPresented:)` pushes `ShelfSearchView`.
* Typing in `ShelfSearchView` re-filters `allBooks` (`isOnShelf || isHistory`) through `ShelfBookSearchMatcher.matches(...)` over `title`/`titleTrans`/`author`/`authorTrans` (`localizedCaseInsensitiveContains`, empty/trimmed query matches nothing). An empty query shows the shared `search_history` (decode via `SearchHistoryStore`); the keyboard return (`onCommit`) and the history clear/delete buttons write it back through `SearchHistoryStore.addQuery` (trim, dedup, head-insert, cap 15).
* Tapping a result opens `ReaderView` via a `.fullScreenCover(item: $readerRoute)` Button (was a `NavigationLink` push).
* App launch: `AppLaunchRootView` `.task(id: translationManager.isInitialized)` runs `BookTitleTranslationMigrator.runIfNeeded(container:)` once dictionaries are loaded; it fetches books in a dedicated `ModelContext`, fills empty `titleTrans`/`authorTrans` in batches of 50, and saves.
* Opening a book emits a refresh event: `ReaderView.initializeReaderIfNeeded` (after resolving `localBookSnapshot`) and `BookDetailView` `.task(id: actualBookId)` call `BookTitleTranslationMigrator.refreshTranslations(for:)`; only changed fields are written and `modelContext.save()` runs when needed, so per-session additions or dictionary/custom-dict updates reach the DB immediately.

## Reader duplicated-title removal toggle events (1.3.189)

* Toggling "Loại bỏ tiêu đề chương trùng trong nội dung" in the Reader menu writes `removeDuplicatedTitle_<bookId>` (default ON, shared per book) and triggers `ReaderViewModel.refreshParagraphItems()`; the next chapter build drops the first content line when it matches an active TOC rule.
* The same key is read at TTS prepare/start, next-chapter key construction, auto-advance, worker processing, and settings resume, so TTS and Reader agree on which line IDs exist after the drop.

## NghiTTS empty-output and refill retry events (1.3.147)

* Kết quả tiền xử lý rỗng/chỉ dấu câu phát sinh sự kiện tổng hợp khoảng lặng hợp lệ, không phát lỗi ONNX/eSpeak và không tạm dừng playback khi chuyển từ tên chương sang nội dung.
* Prefetch failure tạm thời phát đúng một `[TTSPerf] PrefetchFailure` với `action=retry_scheduled`, sau cooldown 1 giây mới phát sinh lần thử tiếp theo; callback khác không thể bypass cooldown.
* Lỗi không retry hoặc attempt thứ hai phát `action=blocked_non_retryable`/`blocked_max_retries`; cancellation không log failure và không thay đổi failure state.
* Stop, đổi session và chuyển chương hủy retry task, tăng generation và xóa failure state trước khi sự kiện của phiên mới được xử lý.

## NghiTTS deadline and energy events (1.3.115)

* An audio-finish event with no prepared handoff records `[NghiEnergy] Underrun`. If its index matches active refill, playback awaits that task and records `reusedInFlight=true` instead of submitting duplicate ONNX work.
* Thermal `.serious` cancels only nonessential refill and next-chapter audio; update-window preserves or starts N+1. `.critical` cancels all refill while current-demand synthesis remains available.
* Successful coordinator operations contribute queue wait, inference wall time, PCM duration, aggregate/max RTF, on-demand count, and reuse count to an in-memory summary emitted every 60 seconds or on pause/stop.

## Chapter memory/cancellation events (1.3.114)

* `UIApplication.didReceiveMemoryWarningNotification` reaches `MainTabView`, which asynchronously clears only `ChapterContentRepository`'s reusable normalized-document LRU.
* Reader/TTS task cancellation emits a subscriber-removal event for the matching `ChapterKey`. Remaining subscribers preserve the shared operation; removing the final subscriber cancels its repository-owned task and propagates through the extension executor.
* Stop, replacement start, and a newer TTS chapter-advance event cancel the owned fallback auto-advance task. Its `CancellationError` is classified as cancellation rather than a playback failure.

## TTS presentation energy events (1.3.112)

* Paragraph/playback events update the dynamic Lock Screen timeline immediately after static metadata is cached; they do not emit new translation, local-cover decode, or artwork-construction work.
* A book/chapter/cover/translation-key event cancels the previous metadata task and starts at most one replacement. Dictionary updates invalidate the matching cache and republish if the widget session remains active.
* Widget/root/Reader Combine events cross the main RunLoop before snapshots are reread, because `@Published` emits before assignment; equality checks suppress unchanged view invalidations.
* Selecting Nghi schedules delayed warm-up. Selecting any other engine emits cancellation of the pending warm-up task.

## Reader viewport and serious-buffer events (1.3.111)

* A TTS parent event whose paragraph midpoint remains inside the Reader safe viewport increments `scrollSkippedVisible` and emits no `scrollTarget`; an out-of-band target emits one `.ttsAuto` target and records execution when `ScrollViewProxy.scrollTo` runs.
* Paragraph geometry callbacks with less than 8 points of movement are counted but do not rewrite `ParagraphTracker` frame state.
* Remote TTS prefetch is serialized through `RemoteTTSSynthesisCoordinator` and is not canceled or throttled by thermalState transitions.

## Reader energy diagnostic events (1.3.110)

* Reader render, highlight, geometry, intrinsic-size, and TTS scroll-target events increment main-actor counters only. The diagnostic path emits no per-event file I/O.
* The next render event after approximately 60 seconds emits one `[ReaderEnergy] Summary`. Thermal-state change, app background, and Reader disappearance flush a partial window so Reader activity can be aligned with `[TTSEnergy]` transitions.

## Reader highlight event optimization (1.3.109)

* A TTS chunk highlight event mutates only text-storage color attributes in the matching `ReaderTextView`; it does not clear cached measurements or trigger intrinsic-size invalidation.
* A TTS parent-paragraph transition continues to update `ReaderView.scrollTarget`. `ReaderView` consumes that target through `ScrollViewReader`, making it the single owner of TTS auto-scroll; the embedded UIKit text view no longer emits a second animated content-offset event.
* Tapping the header auto-scroll toggle flips `isAutoScrollDisabled`; when disabled, `requestTTSScrollIfNeeded` and the `.ttsAuto` scroll-target trigger are suppressed immediately even while TTS playback continues.

## Remote TTS energy diagnostic events (1.3.107)

* `UIApplication.didEnterBackgroundNotification` closes the current diagnostic window and switches the coordinator to `background`; `willEnterForegroundNotification` closes it again and switches to `foreground`. Each transition emits one `[TTSEnergy] AppState` line through `AppLogger`.
* `ProcessInfo.thermalStateDidChangeNotification` continues to drive prefetch policy and additionally emits a `[TTSEnergy] ThermalChange` line plus the partial window summary, allowing thermal escalation to be aligned with remote request cadence.
* A completed remote synthesis emits no per-request success log. It only updates actor-owned counters; the next interval boundary, lifecycle transition, thermal transition, or `cancelAll` event flushes one aggregate summary.

## Book storage and deletion events (1.3.34)

* **Deletion Events**: Tapping delete/remove in `ShelfView` or `BookDetailView` triggers database deletion (`BookStorageManager`) and side-effect cancellation (stops playback via `TTSManager.stop` and cancels downloads via `DownloadManager.cancelTasksForBook`).
* **Background Cleanup Events**: A successful DB commit dispatches asynchronous file deletions via a background `Task`. If deletion fails, a failure event enqueues the file path in `UserDefaults` (`failed_file_deletions_queue`).
* **Startup Retry Event**: At app startup, `drainRetryQueue()` is called to process the failed deletion queue, trying up to 3 times before discarding the item.
* **TOC Paging Events**: Scrolling a placeholder list item into view triggers a `loadPageIfNeeded` event in `ReaderChapterListStore` which asynchronously fetches chapter metadata.
* **Cancellation Event**: Task cancellation during download/export propagates cooperative cancellation checks at chapter boundaries, raising a cancellation event that aborts subsequent chapters.

## Reader translation-selection events (1.3.14)

* Invoking “📖 Dịch” sends the current `UITextView.selectedRange` in UTF-16, not selected text plus derived sentence offsets.
* `ParagraphCardView` adds the paragraph id, and `ReaderView` resolves the item inside the matching chapter before opening the existing definition sheet.
* Translation toggle, dictionary edits, and chapter-title visibility rebuild paragraph items and their mappings from original chapter data.

## Reader event updates (1.3.13, supersedes 1.3.11)

* Footer buttons emit relative steps and chapter-list rows emit absolute targets. Horizontal drags no longer emit chapter-navigation events.
* Text selection remains local to `ReaderTextView` until the user invokes lookup/copy/speak actions; selection-activity plumbing used only by the removed swipe gesture is gone.
* A TTS paragraph event requests `.ttsSync` without persistence. A manual jump does not seek TTS; the next TTS paragraph may move the display back when auto-scroll is enabled.
* Reader disappearance cancels navigation debounce, navigation worker, DB debounce, and Reader prefetch while leaving independent TTS playback alive.
* Menu commands use shared handlers: title visibility rebuilds paragraph items from RAM, and reload force-fetches the displayed chapter.
* A downward drag of at least 72 points on the chapter-list header closes the overlay; the sheet no longer follows the finger during slow drags. Tapping the outside backdrop also closes the overlay, while vertical gestures inside the list continue scrolling.
* Starting TTS passes only a short initial queue from Reader. Full chapter-queue refresh is an independent `TTSManager.refreshChaptersQueueInBackground(...)` event and does not depend on Reader staying visible.
* Discovery category paging renders only the selected tab and adjacent tabs with real content; newly selected category loading is debounced briefly so the page-swipe animation is not paired with immediate list loading.

## 1. Bản đồ các Luồng Sự kiện chính (Event Flow Map)

```mermaid
graph TD
    %% Tác nhân bên ngoài
    User["Người dùng (Tương tác UI)"] -->|Tap/Swipe gestures| UIView["SwiftUI Views (Reader, Shelf, Widget)"]
    OS["Hệ điều hành iOS"] -->|Thông báo hệ thống| NotificationCenter["NotificationCenter"]
    Hardware["Phần cứng (Màn hình khóa / Tai nghe)"] -->|Remote Command center| RemoteCommand["MPRemoteCommandCenter"]
    WebNode["Trang web nguồn"] -->|Tải trang ngầm hoàn tất| WebDelegate["WKNavigationDelegate"]
    
    %% Thành phần nhận và xử lý
    UIView -->|Gọi phương thức| ViewModel["ViewModels / Managers"]
    NotificationCenter -->|Combine Publisher / Observer| TTSManager["TTSManager (interruption, route change, reset)"]
    NotificationCenter -->|Combine Publisher| ReaderViewModel["ReaderViewModel (Memory Warning)"]
    RemoteCommand -->|MediaPlayer callbacks| TTSManager
    WebDelegate -->|WebViewLoader callback| JSExecutor["JSExecutor (Web parser)"]
    
    %% Phản hồi và Cập nhật
    TTSManager -->|Cập nhật state| NowPlaying["Now Playing Info (Hệ thống)"]
    TTSManager -->|Cập nhật @Published| WidgetUI["TTSFloatingWidgetView (UI)"]
    ViewModel -->|Cập nhật @Published| ReaderUI["ReaderTextView / Progress bar (UI)"]
```

---

## 2. Chi tiết các Luồng Sự kiện

### 2.1. Sự kiện Tương tác Giao diện (UI Gestures)
*   **Tap "Đọc truyện"** (`BookDetailView.swift`): Kích hoạt chuyển cảnh sang `ReaderView`, khởi tạo `ReaderViewModel` và nạp chương.
*   **Tap nút "TTS Play"** (`ReaderView` / `TTSFloatingWidgetView`): Kích hoạt `TTSManager.shared.startSpeaking(...)`.
*   **Swipe/Scroll vuốt dọc** (`ReaderView`): Kích hoạt sự kiện thay đổi dòng hiển thị, gửi index đoạn văn hiện tại đến `ReaderViewModel.updateProgress(...)`.
*   **Thay đổi thông số TTS** (`TTSSettingsView` / `NghiTTSSettingsView`): Thay đổi `tool`, `speed`, `pitch`, `selectedVoice`. Sự kiện `didSet` của các thuộc tính này kích hoạt cập nhật thông số trực tiếp lên `AVAudioUnitTimePitch` và Now Playing Info.

### 2.2. Thông báo Hệ thống (Notification Center)
*   **`AVAudioSession.interruptionNotification`**:
    *   *Mục đích*: Nhận biết khi có cuộc gọi đến, Siri kích hoạt, hoặc âm thanh bị ngắt bởi app khác.
    *   *Xử lý (`TTSManager.swift`)*: 
        *   Nếu ngắt bắt đầu (`.began`): Tạm dừng phát TTS (`pause()`), ghi nhận cờ `wasPlayingBeforeInterruption = true`.
        *   Nếu ngắt kết thúc (`.ended`): Kiểm tra cờ hồi phục (`.shouldResume`). Nếu có, tự động gọi `resume()` phát tiếp âm thanh.
*   **`AVAudioSession.routeChangeNotification`**:
    *   *Mục đích*: Nhận biết khi tai nghe (Bluetooth/dây) bị rút ra hoặc ngắt kết nối.
    *   *Xử lý (`TTSManager.swift`)*: Kiểm tra nếu lý do ngắt kết nối là rút tai nghe (`.oldDeviceUnavailable`), tự động gọi `pause()` để ngăn việc phát âm thanh ra loa ngoài điện thoại.
*   **`AVAudioSession.mediaServicesWereResetNotification`**:
    *   *Mục đích*: Nhận biết khi dịch vụ âm thanh lõi của iOS bị crash hoặc reset.
    *   *Xử lý (`TTSManager.swift`)*: Giải phóng AudioEngine cũ, khởi tạo lại toàn bộ node graph âm thanh (`setupAudioEngine`) và kích hoạt lại session.
*   **`UIApplication.didReceiveMemoryWarningNotification`**:
    *   *Mục đích*: Hệ điều hành cảnh báo ứng dụng sắp hết bộ nhớ RAM.
    *   *Xử lý (`ReaderViewModel` / `TranslationManager`)*: 
        *   `ReaderViewModel` giải phóng bộ đệm chương truyện `cache.clear()`.
        *   `TranslationManager` giải phóng cache từ điển của sách `clearBookDictCache()`.
*   **`translationDictionariesDidUpdate`**:
    *   *Mục đích*: Đồng bộ chương hiện tại và các chương Reader đã preload sau khi người dùng sửa VP/Name.
    *   *Xử lý (`ReaderView` / `ReaderViewModel`)*: Xóa translation cache, hủy refresh cũ, rồi rebuild tuần tự chương đang hiển thị trước và các chương cache theo khoảng cách. Sự kiện không xóa audio prefetch của phiên TTS đang phát; nội dung mới được dùng khi người dùng bấm đọc lại hoặc khi TTS nạp chương kế tiếp từ repository.
*   **`ttsDidAdvanceToNextChapter`**:
    *   *Mục đích*: Nhận biết khi `TTSManager` tự chuyển sang chương tiếp theo độc lập.
    *   *Xử lý (`ReaderView.swift`)*: Nhận thông báo chứa `bookId` và `chapterIndex` để thực hiện đồng bộ giao diện hiển thị (chuyển tab, cuộn) mà không trigger lệnh phát TTS lặp lại, hỗ trợ đồng bộ ngay cả khi TTS bỏ qua các chương bị lỗi hoặc rỗng.
*   **`sourceChangedNavigateToShelf`**:
    *   *Mục đích*: Sau khi đổi nguồn truyện thành công (`SearchView.executeSourceChange`), điều hướng app về Kệ sách và chọn đúng sub-tab theo vị trí của truyện mới.
    *   *Nguồn phát*: `SearchView.swift` post ngay trước `onSourceChanged?()` với `userInfo: ["shelfTab": createSnapshot.isOnShelf ? 1 : 2]` (truyện mới thừa kế `isOnShelf`/`isHistory` từ truyện cũ).
    *   *Xử lý*: `MainTabView` đặt `selectedTab = 0`; `ShelfView` đặt `selectedTab` theo `shelfTab` (1 = Kệ Sách, 2 = Lịch Sử); `ReaderView.onSourceChanged` thêm `dismiss()` sau 0.3s để đóng Reader (fullScreenCover — cover tự trượt xuống lộ ra kệ sách); `BookDetailView.onSourceChanged` đặt `navigateToChangeSource = false` (SearchView được push qua `NavigationLink(isActive:)` — chỉ gọi `dismiss()` sẽ kẹt push) rồi `dismiss()` sau 0.3s.
*   **Điều hướng Reader độc lập với TTS**:
    *   Next/Previous/Chapter List chỉ tạo request và commit trong `ReaderViewModel`; không phát sự kiện chuyển chương sang `TTSManager`.
    *   `prepareSpeaking(...)` chỉ prewarm cache chương Reader và không thay đổi chương TTS đang phát hoặc đang pause.

### 2.3. Sự kiện Combine (Publishers)
*   **`@Published` Properties**:
    *   `TTSManager` phát trạng thái nguồn; `TTSWidgetStateReader`, `TTSRootPresentationReader` và `ReaderTTSStateReader` chỉ chuyển tiếp snapshot cần render sau equality gate. Settings vẫn quan sát đầy đủ cấu hình tải/model.
    *   `DownloadManager` phát các thay đổi về tiến trình `tasks` lên giao diện `DownloadTrackerView`.
*   **`memoryWarningSubscription`**:
    *   *Định nghĩa*: Đăng ký lắng nghe thông báo bộ nhớ bằng Combine publisher trong `ReaderViewModel.setupSubscriptions()`.
    *   *Giải phóng*: Được hủy tự động qua deinit khi ViewModel bị hủy.

### 2.4. Sự kiện Hệ thống Remote (Remote Command Center)
Đăng ký trong `TTSManager.setupRemoteCommandCenter()` và quản lý trạng thái khả dụng trong `syncRemoteCommandState()` qua thư viện `MediaPlayer`:
*   `playCommand` -> Đăng ký target handler trong `setupRemoteCommandCenter()`, bật khả dụng ban đầu trong `setRemoteCommandsEnabled(_:)` và cập nhật theo trạng thái tạm dừng (`isEnabled = paused`, với `paused = active && !isPlaying`) trong `syncRemoteCommandState()` (Phase J) để iOS MediaRemote UI hiển thị đúng biểu tượng Play/Pause trên Lock Screen.
*   `pauseCommand` -> Đăng ký target handler trong `setupRemoteCommandCenter()`, bật khả dụng ban đầu trong `setRemoteCommandsEnabled(_:)` và cập nhật theo trạng thái đang phát (`isEnabled = playing`, với `playing = active && isPlaying`) trong `syncRemoteCommandState()` (Phase J). Nếu nhận được sự kiện remote `.pause` (từ phụ kiện cũ), `handleRemoteTransportCommandOnMain(.pause)` tiếp tục kích hoạt cơ chế tương thích có phạm vi giới hạn (bounded compatibility fallback) gọi `resume()` khi paused.
*   `togglePlayPauseCommand` -> Bật khả dụng khi active (`isEnabled = active`) trong `setRemoteCommandsEnabled(_:)` và `syncRemoteCommandState()` (Phase J), gọi `pause()` nếu đang phát hoặc `resume()` nếu đang tạm dừng. Đồng thời, khi callback đi vào từ Main Thread (`Thread.isMainThread == true`), `dispatchRemoteTransportCommand` được thực thi đồng bộ via `MainActor.assumeIsolated` trước khi trả về `MPRemoteCommandHandlerStatus` phản ánh chính xác kết quả thực tế (Phase F), kết hợp xuất bản hợp đồng metadata timeline hữu hạn (Phase I) qua `setSystemNowPlayingPlaybackState` (`currentRate: 1.0/0.0`, `defaultRate: speed`, `elapsed`, `duration`, `progress`) và `updateNowPlayingInfo` phản hồi cho MediaRemote.
*   `nextTrackCommand` -> Gọi `TTSManager.skipForward()` (tự chuyển chương qua `advanceToNextChapter` nếu hết đoạn cuối chương).
*   `previousTrackCommand` -> Gọi `TTSManager.skipBackward()` (tua lùi đoạn).
*   `skipForwardCommand` -> Tua tiến đoạn văn (`skipForward()`).
*   `skipBackwardCommand` -> Tua lùi đoạn văn (`skipBackward()`).

### 2.5. Sự kiện Trình duyệt Ngầm (WKNavigationDelegate)
*   **`didFinish navigation`**:
    *   *Định nghĩa*: Tọa lạc tại `WebViewLoader` trong `JSExecutor.swift`.
    *   *Luồng đi*: Khi `WKWebView` tải xong mã HTML của trang web động cào về -> delegate bắt sự kiện hoàn tất -> trích xuất nội dung HTML -> kích hoạt callback chuyển tiếp chuỗi HTML về JS Engine thông qua Semaphore giải tỏa luồng chặn (`semaphore.signal()`).

#### Reader/TTS unified pipeline (2026-07)

- `ChapterTextNormalizer` is the single source for LF newlines, trimmed non-empty lines, compact paragraph IDs, and UTF-16 ranges. `ChapterContentRepository` produces one normalized `ChapterDocument` for both Reader and TTS.
- Reader uses `ReaderLoadState` with bootstrap retry/clamping, typed failures, generation checks, cache-first rendering, and a short opacity crossfade only for newly fetched content. `ReaderRoute.chapterIndex` preserves the selected TOC index through navigation.
- `TTSParagraphBuilder` chunks normalized lines without renumbering parent paragraph IDs; replacement output is checked before synthesis. TTS asynchronous work is guarded by session identity and TTS owns progress while playing.
- `ReadingProgressStore` coalesces RAM snapshots in an actor and flushes from background contexts on checkpoints, dismissal, and app backgrounding. Legacy window/tab Reader, duplicate progress repository, and `TTSSession` mirror are removed.
- Tapping the widget cover emits `openCurrentlyPlayingReader`; Shelf routes to the TTS chapter or sends `navigateReaderToPlayingChapter` to an already visible Reader. Play/pause, next paragraph, close, drag, and auto-hide remain local UI events around `TTSManager`.
- A successful source change emits `sourceChangedNavigateToShelf` (`userInfo.shelfTab` = 1 Kệ Sách / 2 Lịch Sử); MainTabView switches to the shelf main tab and ShelfView selects the matching sub-tab, while ReaderView pops back to the shelf root.
- A chapter request first emits bounded-memory/SwiftData lookup work; extension completion publishes the document to shared memory before a non-cancellable background upsert. Reader dismissal cancels only its waiter (and the underlying load only when it was the final subscriber), while dismissal/background still flushes pending writes.
- Repository-row trash taps open a confirmation alert; confirmation uninstalls owned local extensions and deletes the repository, while horizontal swipes remain owned by the parent paged tab.
- Book deletion taps on `ShelfView` and `BookDetailView` trigger database deletion, stops active TTS playback (`TTSManager.stop`), and cancels active downloads (`DownloadManager.cancelTasksForBook`) before dispatching background file cleanup.
- Physical file deletion failures raise an event to enqueue the path in the `UserDefaults` retry queue, and app launch triggers `drainRetryQueue()` to process failed items.
- Scrolling placeholder rows in the TOC triggers a `loadPageIfNeeded` event in `ReaderChapterListStore` which launches background tasks to fetch metadata for the visible window.
- Task cancellation in `DownloadManager` emits cooperative cancellation events at chapter boundaries to halt execution.

- `ProcessInfo.thermalStateDidChangeNotification` updates Nghi prefetch policy while Remote TTS continues to prefetch up to configured depth.
- For NghiTTS, the same notification cancels next-chapter audio outside `.nominal`; `.serious` narrows refill to N+1, `.critical` cancels refill, and cooling rebuilds the configured window through `updateNghiPrefetchWindow`.
- Pause/stop events cancel remote playback/prefetch waiters and reset the Ext runtime on full cache teardown; URLSession cancellation unblocks the synchronous extension fetch bridge.
- Paragraph-finished events update the depth-three cache window, but scheduler priority—not task creation count—determines execution order.

<!-- GENERATED END -->
