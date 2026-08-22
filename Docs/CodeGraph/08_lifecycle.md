---
generated_by: Antigravity
generator_version: 1.0
generated_at: 2026-08-21T10:30:00+07:00
git_commit: UNKNOWN
source_files: 230
document_version: 5
---

# Vòng đời các SwiftUI View (SwiftUI View Lifecycle)

Tài liệu này phân tích chi tiết cơ chế quản lý vòng đời của các màn hình chính trong ứng dụng FreeBook, bao gồm việc nạp trạng thái ban đầu (`onAppear`, `.task`), dọn dẹp khi đóng (`onDisappear`), theo dõi trạng thái ứng dụng (`scenePhase`), hủy task chạy ngầm và gỡ bỏ các observer.

## Ghi chú thủ công (Human Notes)
*Ghi chú thủ công của con người.*

<!-- GENERATED START -->
## Vòng đời chuyển chương: ai đánh thức SwiftUI (1.3.243)

Chuỗi 1.3.241/1.3.242 bên dưới mô tả *đúng* thứ tự các bước, nhưng thiếu một điều kiện: mỗi bước chỉ chạy khi SwiftUI thực sự chạy một update pass. Từ 1.3.243, nguồn đánh thức là `ReaderViewModelInvalidationRelay`, nên chuỗi đó mới chạy theo nhịp của chính cú bấm:

1. `t=0` — người dùng bấm Next/Prev. `requestChapter` set `pendingNavigationIndex = N`, `loadState = .loading` ⇒ `objectWillChange` ⇒ relay invalidate `ReaderView`.
2. `t≈1 frame` — pass đầu: cổng thấy `pendingNavigationIndex != displayedChapterIndex` → skeleton; `onAppear` ghi `skeletonHandshakeIndex = N` và log `[ReaderPerf] Skeleton`.
3. `t≈32 ms` — `memoryCommitTask` (đường RAM) hoặc worker commit: `pendingNavigationIndex = nil`, `displayedChapterIndex = N`, `navigationCommit` ⇒ relay invalidate lần hai.
4. `t≈32 ms + 1 frame` — pass thứ hai: cổng mở (`skeletonHandshakeIndex == N`) → dựng `singleChapterScrollView`; `.onChange(of: navigationCommit)` chạy `applyNavigationCommit` → `scrollTarget`, `paragraphTracker.removeAll()`, `scheduleDeepLandingScroll`.
5. `t+0.25 s` — `completeReaderPositionRestore` nhả `isRestoringReaderPosition`; auto-scroll TTS trở lại bình thường.

Trước 1.3.243, bước 2 và 4 **không có mốc thời gian riêng**: cả hai cùng chờ sự kiện invalidate vô can kế tiếp rồi chạy dồn trong một lần drain (log thiết bị: `Skeleton` và `Present` cách nhau 15–30 ms, nhưng cách cú bấm 0.6–4.3 s). Đó là lý do ba lần sửa trước (yield → sleep 32 ms → cổng bắt tay) đều không đổi được cảm giác đơ: chúng sắp lại thứ tự trong một pass mà chưa ai kích hoạt.

Đường chọn chương từ danh sách vốn không bị vì việc đóng sheet tự sinh một chuỗi pass; đường `ttsSync` từ widget có skeleton sớm (notification handler ghi `@State`) nhưng nội dung vẫn phải chờ — cả hai nay đi cùng một nhịp với Next/Prev.

## Vòng đời chuyển chương: skeleton là bước bắt buộc, không còn là bước may mắn (1.3.242)

Bổ sung cho chuỗi 1.3.241 bên dưới: bước 2 (skeleton) trước đây chỉ *có thể* xảy ra nếu SwiftUI kịp chạy một update pass trong nhịp 32 ms. Log thiết bị 2026-08-22 cho thấy khi chương đích đã nằm trong `ChapterCache` (`origin=memory`, `commitMs≈41`) thì pass đó thường không kịp: không có dòng `[ReaderPerf] Skeleton`, và `[ReaderPerf] Present` cách cú bấm 1.6–3.5 s. Ngược lại, mọi lượt *có* dòng `Skeleton` đều present sau commit ~20 ms.

Vòng đời từ 1.3.242:

1. Cú bấm → `ReaderView.requestChapter(at:…)` (log `Tap`), `pendingNavigationIndex = index`.
2. Update pass kế tiếp: cổng `isChapterSubtreeRenderable` chưa cho dựng chương mới → **luôn** vẽ `chapterInlineLoadingView` (log `Skeleton`), `onAppear` ghi `skeletonHandshakeIndex = index`.
3. `commitNavigation` (sau nhịp 32 ms, giữ nguyên) → `applyNavigationCommit`: `chapterIndex`, `scrollTarget` đầu chương.
4. Update pass sau khi bắt tay xong: dựng `singleChapterScrollView`, `onAppear` ghi `renderedChapterIndex` (log `Present`) rồi `restoreSingleChapterPosition`.
5. `scheduleDeepLandingScroll` sau 0.15 s: pha hai tới đoạn TTS (không đổi).

Điểm mấu chốt của bước 2–4: subtree TextKit-1 của chương cũ được tháo trong pass vẽ skeleton, còn subtree chương mới được dựng trong pass sau — hai việc này không bao giờ còn nằm trong **cùng một** update pass. Trường hợp reload đúng chương đang hiển thị không đi qua bước 2 (không nháy skeleton).

## Vòng đời chuyển chương: một frame skeleton, rồi mới neo sâu (1.3.241)

Thứ tự mới cho một lượt Next/Prev (cả khi chương đích là chương TTS đang phát):

1. Cú bấm → `stepChapterHonoringTTS` → `ReaderView.requestChapter(at:…)`: đặt `isRestoringReaderPosition = true`, `paragraphTracker.removeAll()`, log `[ReaderPerf] Tap`.
2. `ReaderViewModel.requestChapter`: `pendingNavigationIndex = index`, `loadState = .loading` → render gate vẽ skeleton (`[ReaderPerf] Skeleton sinceTapMs=`).
3. Nhịp chờ một frame **bằng `Task.sleep(32 ms)`**, không phải `Task.yield()`: yield chỉ đưa continuation về cuối hàng đợi main actor và run loop drain hết hàng đợi *trước* khi CoreAnimation commit, nên trước 1.3.241 không có frame skeleton nào được present. Áp cho cả đường RAM (`memoryCommitTask`) và đường worker (`startNavigationWorkerIfNeeded`).
4. `commitNavigation` → `applyNavigationCommit`: hạ cánh **đầu chương** (`paragraphIndex: -1`). Layout pass dựng chương vì vậy không phải realize/đo các card trung gian để giải neo sâu.
5. `singleChapterScrollView.onAppear` → `[ReaderPerf] Present sinceTapMs=` → `restoreSingleChapterPosition` tiêu thụ target đầu chương.
6. +0.15 s (timer chỉ nổ khi main thread rảnh, tức sau khi chương đã present): `scheduleDeepLandingScroll` đặt target sâu `reason: .initialRestore` → cuộn tới đoạn TTS đang đọc. Cờ restore được đặt lại `true` trước cú cuộn này.

Ba dòng log `Tap → Skeleton → Present` là cách phân biệt "main thread bị chiếm" (Skeleton muộn/không có) với "chương load lâu nhưng UI vẫn phản hồi" (Skeleton ~0 ms, Present muộn). Chi phí thêm cố định: 32 ms mỗi lượt điều hướng.

## Vòng đời một lượt chuyển chương của Reader (1.3.240)

* Chuỗi khi bấm Next/Prev với chương đích đã nằm trong RAM: turn 1 = `requestChapter` set `pendingNavigationIndex`/`.loading` và tạo `memoryCommitTask`; frame 1 = SwiftUI vẽ `chapterInlineLoadingView`; turn 2 = `commitNavigation` → `navigationCommit` → `.onChange` → `applyNavigationCommit` (set `isRestoringReaderPosition = true`, `paragraphTracker.removeAll()`, `scrollTarget`); frame 2 = subtree `singleChapterScrollView` mới (`.id("single-chapter-N")`) được dựng, `onAppear` → `restoreSingleChapterPosition` → `attemptScroll`; +0.25 s = `completeReaderPositionRestore` nhả cờ.
* Việc dựng subtree (teardown chương cũ, `ForEach` vài trăm `ParagraphItem`, tạo + layout `UITextView` TextKit 1, giải neo `LazyVStack`) vẫn nằm trong một turn — thay đổi này **không làm nó nhanh hơn**, chỉ đảm bảo có một frame skeleton trước nó nên UI không còn đứng im không phản hồi.
* Task mới `memoryCommitTask` thuộc cùng nhóm vòng đời với `navigationWorkerTask`/`navigationDebounceTask`/`settledPrefetchTask`: tạo trong `requestChapter`, cancel ở `requestChapter` kế tiếp, `failBootstrap` và `shutdown(saveProgress:)`. Không có timer hay observer mới.
* `ReaderEnergyDiagnostics` thêm hai mốc theo vòng đời session: `beginReaderSession()` reset bộ đếm card realize và `lastNavigationIndex`; `flush(reason:)` xả nốt dòng `[ReaderPerf] NavRealize` của chương cuối trước khi in `Summary` rồi bỏ window.

## Next-chapter prefix audio lifecycle (1.3.234)

* `TTSNextChapterPrefixCache.shared` sống suốt vòng đời app (singleton `@MainActor`), nhưng dữ liệu bên trong chỉ sống theo một `TTSPreparedNextChapterKey`: key mới là reset, `consume` là reset, stop/đổi engine/đổi giọng là reset.
* Vòng đời một chunk prefix: `request` mở `Task(priority: mặc định của Task {} trên MainActor)` → coordinator của engine xếp hàng ở mức ưu tiên thấp nhất → `finishSynthesis` ghi vào `chunks` nếu `generation`/`activeKey` còn khớp → `applyNextChapter` chuyển nó thành `preloadedData[index]` của chương mới, từ đó nó tuân theo đúng vòng đời cửa sổ trượt đã có (`cacheKeepIndices`, `clearCurrentParagraphPrefetchCache`).
* Pause chỉ hủy phần đang bay (`cancelPendingWork`), giữ chunk đã tổng hợp — cùng triết lý với `PiperSynthesisCoordinator.cancelPendingOptionalReserveRequests()` (cho phép inference đang chạy hoàn tất và cache lại).
* Không có timer, observer hay `Task.sleep` nào thuộc bộ đệm này; mọi lần đánh giá đều do sự kiện chuyển đoạn/chuyển chương/resume đẩy tới, nên nó không tạo tải nền khi app ở background ngoài chính phần tổng hợp âm thanh.

## Tạm ngưng Reader TTS auto-scroll khi ứng dụng không hiển thị (1.3.233)

* Reader sử dụng trạng thái `@State internal var isSceneActive` (đồng bộ tại `onAppear` và `.onChange(of: scenePhase)`) và số thế hệ `ttsAutoScrollGeneration` tăng dần mỗi khi đổi `scenePhase` để quản lý an toàn luồng auto-scroll mà không bị ảnh hưởng bởi struct snapshot capture của SwiftUI.
* Khi `isSceneActive == false`, mọi entry point auto-scroll TTS (`onChange` parent paragraph, `requestTTSScrollIfNeeded`, và `scrollToTTSHighlightIfNeeded` kể cả bên trong closure `DispatchQueue.main.asyncAfter` kiểm tra token `ttsAutoScrollGeneration == currentGen`) bị chặn hoàn toàn.
* Khi `scenePhase` chuyển sang inactive/background, `ttsAutoScrollGeneration` tăng lên làm vô hiệu hóa lập tức mọi callback `asyncAfter` đang chờ, đồng thời Reader tự động hủy `scrollTarget` có `reason == .ttsAuto`; các target navigation/manual/initial-restore vẫn được bảo toàn.
* Ngay tại đường thực thi `proxy.scrollTo` (`attemptScroll` & `onChange(of: scrollTarget)`), bất kỳ target `.ttsAuto` dư thừa nào nếu phát sinh khi `isSceneActive == false` sẽ lập tức bị hủy mà không thực thi.
* Khi ứng dụng trở lại `scenePhase == .active`, `ttsAutoScrollGeneration` tiếp tục tăng để loại bỏ các callback cũ, và lên lịch resync 1-shot duy nhất (`scrollToTTSHighlightIfNeeded`) khớp với thế hệ mới nhất để cuộn về vị trí câu TTS hiện tại mà không replay lịch sử scroll ngầm.

## Local TXT confirmation/import lifecycle (1.3.224)

* Confirmation preview owns only a derived six-index list (plus an omitted-count row) and recomputes it whenever reanalysis replaces `parsed`; it never mounts the full chapter list.
* On confirmation, `isImporting` remains active while detached title translation/metadata creation runs. The existing success lifecycle removes the temp file and selects Shelf; the existing error lifecycle removes the temp file, closes the wait layer, and reports failure.
* Only newly imported local books receive `titleTrans` automatically. Previously imported books retain their stored state until the existing manual `Dịch lại tên chương` action is used.

## TXT parsing overlay and confirmation-sheet lifecycle (1.3.223)

* `isParsingTXT` bắt đầu trước tác vụ parse nền. Thành công giữ overlay sống qua thời điểm tạo `pendingImport` và chỉ giải phóng khi confirmation sheet `onAppear`; lỗi giải phóng ngay sau cleanup file tạm.
* Hủy sheet vẫn xóa file tạm và clear `pendingImport`; xác nhận vẫn clear pending rồi chuyển sang lifecycle `isImporting`. Không thay đổi ownership của file tạm.

## Original chapter-title progress lifecycle (1.3.222)

* Trong Reader session, cache giữ đồng thời `originalTitle` và display `title`; mọi checkpoint định kỳ, flush khi background và checkpoint khi đóng Reader lấy `originalTitle` qua `originalChapterTitle(at:)`.
* `ReadingProgressStore.persist` ghi title gốc không rỗng vào `Book.currentChapterTitle`, fallback sang TOC gốc khi snapshot không có title. Không có startup migration cho record cũ theo phạm vi 1.3.222; record cũ chỉ đổi khi một progress mới hợp lệ được persist.

## Reader per-book traditional-to-simplified translation lifecycle (1.3.220)

* Reader bootstrap khôi phục `convertTraditionalToSimplified_<bookId>` trước khi tạo `ReaderViewModel`/`ReaderChapterListStore`. Cờ này đi cùng lifecycle của Reader session nhưng được lưu lâu dài theo sách.
* Đổi cờ hủy refresh bản dịch trước đó qua revision hiện có, build lại chương hiện tại từ `originalTitle`/`originalContent`, và gắn cờ vào `CachedChapter`. Cache của chương khác cùng cache TOC/search được invalidation, nên không có bản dịch từ cấu hình cũ được commit khi điều hướng.
* TTS capture cờ này vào session khi bắt đầu phát và đưa nó vào identity của prepared/current/next chapter. Nếu đổi option trong lúc phát, manager giữ audio chương hiện tại để không giật/ngắt tiếng, nhưng hủy prefetch và metadata cũ; lần dựng chương tiếp theo dùng cờ mới.

## TTS floating widget and Toast window lifecycle (1.3.195)

* `TTSFloatingWidgetWindowManager` binds `FloatingWidgetUIWindow` to the active `UIWindowScene` on scene activation or app foreground. The window is non-key at all times, with visibility controlled strictly via `isHidden = false/true`. The app's `ModelContainer` is injected into the window's hosting controller and sheets, enabling SwiftData queries.
* `ToastManager` dynamically attaches `ToastUIWindow` (`windowLevel = .alert`) on demand when a toast is shown, and sets `isHidden = true` when the auto-hide animation completes after 3 seconds.
* `FloatingWidgetViewModel` remains the single source of truth for the 3-second auto-hide task and state persistence (`UserDefaults`), ensuring no duplicate or competing timers.

## Reader presentation lifecycle (1.3.192)

* Reader is presented with `.fullScreenCover(item:)` (own `NavigationStack`) from `ShelfView`, `ShelfSearchView`, and `BookDetailView` instead of a navigation push. The main `TabView` is never re-laid-out and the tab bar is never hidden (`.toolbar(.hidden, for: .tabBar)` removed from `ReaderView`), so dismissing the reader reveals the tabs instantly without the delayed tab-bar restore.
* Reader lifecycle callbacks are unchanged: `onAppear` scopes TTS state and starts the energy window, `onDisappear` runs `ReaderViewModel.shutdown(saveProgress:)` and flushes chapter persistence. `ReaderView`'s hidden `NavigationLink`s (BookDetail / change source) push onto the cover's own `NavigationStack`; `dismiss()` closes the cover.

## Shared chapter lifecycle update (1.3.114)

* `ChapterContentRepository.shared` retains at most 12 normalized documents and 12 MiB estimated content cost across Reader lifecycles. MainTab memory-warning handling releases that reusable LRU without touching caller-owned snapshots or persistence.
* An in-flight load exists only while at least one UUID waiter remains. Reader shutdown removes its waiter immediately; shared work survives only when TTS/another consumer still awaits the same key, and final-waiter cancellation reaches the extension operation.
* `TTSManager` owns one fallback auto-advance task. Start replacement, stop, and a newer advance cancel it; a generation-matched defer releases the finished task reference without clearing a newer task.

## TTS presentation energy lifecycle (1.3.112)

* The floating cover owns no playback animation clock; it renders a static image and releases the prior 30 FPS `TimelineView` lifecycle entirely. `TTSFloatingWidgetView` owns one `TTSCoverImageLoader`, so switching between expanded and peeking replaces only presentation children and retains the decoded image/load identity.
* Root, widget, and Reader projection readers own narrow Combine subscriptions for their view lifetime. They read after the publishing RunLoop turn, deduplicate snapshots, and release subscriptions with their `StateObject`.
* `ReaderTTSStateReader.scope(to:)` activates book filtering on Reader appearance. Paragraph/highlight events from another book remain an unchanged inactive projection.
* `TTSManager` owns one cancelable Now Playing static-metadata task and one cached artwork record. Stop clears both; a new identity/dictionary generation replaces them.
* Nghi warm-up has no app-wide eager lifecycle: it begins only for the selected Nghi engine and is canceled when another engine is selected.

## Viewport-gated Reader lifecycle (1.3.111)

* The root Reader geometry maintains global viewport bounds. Mounted paragraph frames remain owned by `ParagraphTracker`; sub-8-point changes are discarded and all state is cleared at chapter/lifecycle boundaries as before.
* TTS highlighting may advance repeatedly without scrolling while the target remains in the safe viewport. A scroll is created only at the boundary, reducing LazyVStack mount/unmount and frame-update cycles.

## Reader energy diagnostic lifecycle (1.3.110)

* `ReaderView.onAppear` starts a fresh `ReaderEnergyDiagnostics` window. Interval summaries reset the window while the Reader remains visible.
* A thermal transition or app background flushes and clears the partial window; Reader disappearance performs a final flush. The singleton retains counters only for the active window and owns no timer, observer, view, or task.

## Reader highlight layout lifecycle (1.3.109)

* Highlight-only updates preserve `ReaderTextView`'s cached width and height. Measurement is invalidated only when text or layout-affecting configuration changes, while theme-only recoloring retains geometry.
* `AutoSizingTextView` suppresses repeated intrinsic-size invalidation while `contentSize` remains effectively unchanged (within 0.5 point).
* TTS auto-scroll is owned by `ReaderView` for the duration of the Reader lifecycle; `ReaderTextView` performs no independent parent-scroll animation and still releases its observation in `dismantleUIView`.
* The header toolbar (`ReaderHeaderFooterOverlayView`) exposes a persistent toggle (icon `scroll`/`scroll.fill`) next to the reload button that flips `ReaderView.isAutoScrollDisabled` immediately. The per-book value is restored from UserDefaults key `disableAutoScroll_\(bookId)` at Reader bootstrap and takes effect without restarting playback.

## Reader paragraph lifecycle (1.3.14)

* Chapter load, translation toggle, dictionary refresh, and title-visibility refresh rebuild paragraph items from immutable original title/content and replace the RAM cache atomically on the main actor.
* Selection ranges are read only when the custom menu action is invoked; `ReaderTextView` keeps no additional selection lifecycle or paragraph ownership state.
* Translation spans are discarded with their `CachedChapter`/`LoadedChapter` paragraph items and require no persistent cleanup.

## Reader lifecycle updates (1.3.13, supersedes 1.3.11)

* `ReaderView.onAppear` creates `ReaderChapterListStore` and mounts `ReaderChapterListView` once. Closing the overlay changes offset, opacity, hit testing, and accessibility visibility; slow downward drags no longer mutate a per-frame sheet offset.
* The initial navigation request restores caller-provided history and never replaces it with a TTS snapshot.
* The chapter list keeps search, order, scroll position, and row objects until Reader disappears.
* The mounted chapter list closes through its header drag gesture, outside-backdrop tap, or Accessibility Escape; list scrolling does not alter presentation state.
* TTS queue refresh lifecycle is owned by `TTSManager`, not `ReaderView`. Reader dismissal does not cancel TTS auto-fetch; only stopping or replacing the TTS session cancels the queue refresh task.
* `ReaderView.onDisappear` calls `ReaderViewModel.shutdown(saveProgress:)`, canceling navigation debounce/worker, DB debounce, and prefetch.
* `ReaderTextView.dismantleUIView` clears delegate ownership; no Reader-level selection-activity state remains after horizontal navigation is removed.
* `TTSFloatingWidgetView` lays out only its compact widget bounds (174x56 when expanded, 52x52 when peeking), snaps the expanded capsule flush to the chosen horizontal edge, and keeps the full-screen Reader outside the overlay hit-test region.

## 1. Bản đồ Vòng đời của Trình đọc (`ReaderView.swift`)

Màn hình đọc truyện `ReaderView` quản lý các tài nguyên bao gồm ViewModel, Prefetcher và kết nối trực tiếp với TTS Widget.

```mermaid
sequenceDiagram
    participant User as Người dùng
    participant View as ReaderView (UI)
    participant VM as ReaderViewModel
    participant TTS as TTSManager.shared
    
    User->>View: Bấm mở truyện
    activate View
    View->>View: onAppear() kích hoạt
    View->>VM: Khởi tạo ReaderViewModel
    activate VM
    View->>TTS: Đăng ký callbacks
    
    Note over View, VM: Người dùng cuộn trang & đọc sách
    
    User->>View: Bấm đóng / Quay lại
    View->>View: onDisappear() kích hoạt
    View->>VM: Gọi shutdown(saveProgress: !ttsOwnsProgress)
    VM->>VM: Hủy dbSaveTask/navigation/prefetch, lưu vị trí đọc xuống SQLite (nếu không do TTS sở hữu)
    View->>View: flush ChapterContentRepository(bookId:) + hủy metadata/work items
    deactivate VM
    deactivate View
    
    Note over View, OS: Khi App chuyển sang chạy nền
    OS->>View: Thay đổi scenePhase == .background
    View->>VM: Gọi saveProgressImmediately() (Lưu khẩn cấp vị trí)
```

---

## 2. Phân tích chi tiết vòng đời từng View chính

### 2.1. Trình đọc Truyện chữ (`ReaderView.swift`)
*   **Khi xuất hiện (`onAppear`)**:
    *   Đọc cấu hình hệ thống từ `UserDefaults`.
    *   Khởi tạo `ReaderViewModel` và nạp vị trí đọc được lưu từ phiên trước.
    *   Đăng ký callback chuyển chương cho `TTSManager.shared`: chỉ còn **một** callback `onChapterFinished` (hai callback cũ `onChapterNext`/`onChapterPrev` đã bị xóa).
*   **Vòng đời điều hướng Reader và TTS độc lập**:
    1. Next/Prev hoặc mục lục chỉ yêu cầu `ReaderViewModel` tải và commit chương Reader.
    2. Reader có thể prewarm nội dung chương đang hiển thị vào cache TTS, nhưng thao tác này không đổi trạng thái/chương của phiên TTS.
    3. TTS chỉ đổi chương khi người dùng chủ động bấm phát tại chương Reader hiện tại, hoặc khi TTS tự đọc hết chương và gọi `advanceToNextChapter`.
    4. Khi bấm phát, Reader chỉ truy vấn metadata chương hiện tại và chương kế; queue đầy đủ được cập nhật trễ qua `updateChaptersQueue(_:for:)` sau khi `isPlaying` để không chặn âm thanh đầu tiên.
*   **Khi biến mất (`onDisappear`)** (theo `ReaderView.swift:896-913`):
    *   Flush diagnostics (`ReaderEnergyDiagnostics.shared.flush(reason: "reader_disappear")`).
    *   Hủy các task/work item đang chạy: `metadataTask`, `updateProgressWorkItem`, `updateTTSPositionWorkItem`, `prepareTTSTask`.
    *   Reset biến tĩnh `ReaderView.activeBookId = nil` (chỉ khi còn khớp `bookId`) và `paragraphTracker.removeAll()`.
    *   Gọi `viewModel.shutdown(saveProgress: !ttsOwnsProgress)` rồi `ChapterContentRepository.shared.flush(bookId:)` trong một `Task`; `ttsOwnsProgress` đúng khi TTS đang phát chính `bookId` này (khi đó TTS sở hữu tiến độ nên Reader **không** lưu đè).
    *   **Lưu ý**: `onDisappear` **không** gọi `saveProgressImmediately()` — lưu tức thời chỉ thuộc nhánh `scenePhase == .background`.
*   **Khi chuyển xuống chạy ngầm (`scenePhase == .background`)**:
    *   Flush diagnostics với lý do `"app_background"`, và nếu TTS **không** đang phát chính sách này thì gọi `viewModel?.saveProgressImmediately()` để tránh iOS chấm dứt ứng dụng đột ngột làm mất bookmark.

### 2.2. Kệ sách (`ShelfView.swift`)
*   **Khi xuất hiện (`onAppear`)**:
    *   Kích hoạt nạp lại trạng thái sách từ database (sắp xếp theo thời gian đọc gần nhất).
    *   Đồng bộ trạng thái tải xuống với `DownloadManager` nếu có sự thay đổi.

### 2.3. Bảng điều khiển giọng đọc (`TTSFloatingWidgetView.swift`)
*   **Khi biến mất (`onDisappear`)**:
    *   Lưu trạng thái đóng/mở của widget nổi vào bộ nhớ đệm hệ thống.
    *   Nếu người dùng đóng widget bằng nút Close, nó sẽ giải phóng liên kết UI nhưng không dừng AVAudioPlayerNode ngầm nếu nhạc đang phát.

### 2.4. Trình duyệt ngầm Bypass Cloudflare (`BypassWebView.swift`)
*   **Khi xuất hiện (`onAppear`)**:
    *   Khởi tạo và thiết lập các tham số cho `WKWebView`.
    *   Gửi cookie giả lập trình duyệt để cào mã nguồn HTML.
*   **Khi biến mất (`onDisappear`)**:
    *   Hủy toàn bộ các tiến trình tải trang web ngầm.
    *   Gỡ bỏ delegate `WKNavigationDelegate` để tránh rò rỉ bộ nhớ.

---

## 3. Quản lý Hủy Task & Gỡ bỏ Observer

### 3.1. Hủy Task chạy ngầm (Task Cancellation)
*   **`ReaderViewModel`**:
    *   Khi người dùng scroll liên tục, `updateProgress` liên tục tạo ra task debounce lưu vị trí mới. Task cũ sẽ được hủy ngay lập tức qua `dbSaveTask?.cancel()` để ngăn việc ghi đĩa trùng lặp liên tục.
*   **`DownloadManager`**:
    *   Background task chạy trong `Task.detached` thường xuyên kiểm tra cờ `isCancelled`. Nếu người dùng bấm hủy tác vụ, task nền sẽ bắt được cờ hủy này, thoát khỏi vòng lặp tải và đóng kết nối context an toàn.

### 3.2. Gỡ bỏ Observer (Notification/Observer Removal)
*   **`ReaderViewModel`**: Lắng nghe `didReceiveMemoryWarningNotification` qua Combine. Khi ViewModel deinit, subscription này tự động giải phóng thông qua cơ chế tự hủy của biến `AnyCancellable` lưu trong class.
*   **`TTSManager`**: Đăng ký các observer của `AVAudioSession` thông qua Combine publishers lưu trong một Set `cancellables`. Khi `TTSManager` tồn tại suốt vòng đời app, các observer này được duy trì vĩnh viễn và chỉ được giải phóng khi ứng dụng bị tắt hoàn toàn.

#### Reader/TTS unified pipeline (2026-07)

- `ChapterTextNormalizer` is the single source for LF newlines, trimmed non-empty lines, **sparse paragraph IDs (`ChapterTextLine.id` is the raw line index and counts blank lines, so IDs are not array offsets and must be looked up by `id`, never used as an array index)**, and UTF-16 ranges. Because those ranges are computed before blank lines are dropped, `ChapterTextLine.utf16Range` must not be used to slice `NormalizedChapterText.content`. `ChapterContentRepository` produces one normalized `ChapterDocument` for both Reader and TTS.
- Reader uses `ReaderLoadState` with bootstrap retry/clamping, typed failures, generation checks, cache-first rendering, and a short opacity crossfade only for newly fetched content. `ReaderRoute.chapterIndex` preserves the selected TOC index through navigation.
- `TTSParagraphBuilder` chunks normalized lines without renumbering parent paragraph IDs; replacement output is checked before synthesis. TTS asynchronous work is guarded by session identity and TTS owns progress while playing.
- `ReadingProgressStore` coalesces RAM snapshots in an actor and flushes from background contexts on checkpoints, dismissal, and app backgrounding. Legacy window/tab Reader, duplicate progress repository, and `TTSSession` mirror are removed.
- `TTSFloatingWidgetView` owns a cancellable auto-hide task through `FloatingWidgetViewModel`; its cover is static during sustained playback. Stopping TTS removes the overlay through `TTSManager.showFloatingWidget`.
- The floating widget has a bounded layout equal to its capsule/peek bounds and uses an offset for screen placement; it no longer mounts a full-screen interactive `GeometryReader` over Reader.
- `ReaderViewModel.shutdown` releases UI chapter cache and its repository waiter. Bounded shared memory survives until LRU/memory-warning eviction, while an in-flight load survives only for another subscriber; Reader disappearance flushes pending writes, and app inactive/background flushes all chapter persistence alongside reading progress.
- A Reader only prepares or updates paused TTS when both book IDs match, so a TTS session outlives dismissal and unrelated Reader lifecycles.

<!-- GENERATED END -->
