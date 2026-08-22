---
generated_by: Antigravity
generator_version: 1.0
generated_at: 2026-08-21T10:30:00+07:00
git_commit: UNKNOWN
source_files: 230
document_version: 6
---

# Vòng đời Tài nguyên Hệ thống (Resource Lifecycle)

Tài liệu này chi tiết hóa vòng đời (khởi tạo, phân bổ, sử dụng, thu hồi và giải phóng) của các tài nguyên hệ thống đặc biệt trong dự án FreeBook: Phiên âm thanh (`AVAudioSession` cùng đường phát thật `AVAudioPlayer`/`AVSpeechSynthesizer`; đồ thị `AVAudioEngine` được dựng nhưng không tham gia phát), các tác vụ nền (`Task`), thông báo hệ thống (`NotificationCenter`), ngữ cảnh cơ sở dữ liệu (`ModelContext` của SwiftData) và trình duyệt ngầm (`WKWebView`).

## Ghi chú thủ công (Human Notes)
*Ghi chú thủ công của con người.*

<!-- GENERATED START -->
## Vòng đời `memoryCommitTask` và bộ đếm card realize (1.3.240)

* `ReaderViewModel.memoryCommitTask` là task duy nhất được thêm: sống đúng một turn main actor (`await Task.yield()` rồi commit), không giữ tài nguyên nào ngoài `[weak self]`. Cancel ở đầu `requestChapter`, `failBootstrap` và `shutdown(saveProgress:)` — cùng bộ ba đang cancel `navigationWorkerTask`, nên không có đường nào để nó sống quá vòng đời Reader.
* `navigationStartUptime` là mốc `TimeInterval` dùng-một-lần: đặt ở đầu `requestChapter` **chỉ khi** log đang bật (`0` nghĩa là tắt, không đọc đồng hồ hệ thống), tiêu thụ và reset về `0` ở cuối `commitNavigation`. Nếu một request thất bại (`failNavigation`) thì mốc đó bị request kế tiếp ghi đè — không rò rỉ gì ngoài một dòng log thiếu.
* Bộ đếm `paragraphsRealizedSinceNavigation` của `ReaderEnergyDiagnostics` chỉ là số nguyên trong window: reset ở `beginReaderSession()` và mỗi lần `recordNavigationCommit(index:)`, xả nốt lần cuối ở `flush(reason:)`. Nó không giữ reference tới card nào nên không có nguy cơ giữ sống view.

## Vòng đời KVO `contentOffset` và cửa sổ đo năng lượng của Reader (1.3.239)

* Tài nguyên được quản lý: một `NSKeyValueObservation` (`Coordinator.offsetObservation`) trên `contentOffset` của `UIScrollView` bao ngoài Reader, và một `Window` (class) của `ReaderEnergyDiagnostics` giữ bộ đếm + `Set<ObjectIdentifier>`.
* **Cấp phát observer nay theo selection, không theo vòng đời view**: `setupScrollObservation(for:)` chỉ được gọi từ `textViewDidChangeSelection` khi `selectedRange.length > 0` và tự guard `offsetObservation == nil` nên không bao giờ cài trùng. Trước đây `updateUIView` gọi vô điều kiện ⇒ số observer bằng số paragraph đang realized; giờ trần là **1 observer cho toàn Reader** (chỉ text view đang có selection giữ observer).
* Ba đường thu hồi, không đường nào rò: `teardownScrollObservation()` khi selection về rỗng (gồm cả nhánh deselect/tap ra ngoài), `dismantleUIView` khi SwiftUI tháo view, và `Coordinator.deinit`. Cả ba đều `invalidate()` rồi set `nil`. Closure KVO bắt `[weak self]` nên không tạo chu trình giữ Coordinator.
* `lastPublishedSelection` là cache giá trị thuần (`NSRange` + hai `CGFloat?`), không giữ tham chiếu đối tượng; nó bị ghi đè ở mỗi publish và biến mất cùng Coordinator.
* Vòng đời `Window`: tạo ở `beginReaderSession()` **chỉ khi log bật**, thay mới sau mỗi lần `emitSummary(resetWindow: true)` (mốc 60 giây), giải phóng (`window = nil`) ở `flush(reason:)` và ở `beginReaderSession()` khi log tắt. Vì `Window` là `final class`, mọi `record*` mutate in-place — hết chuỗi copy-on-write toàn bộ `Set<ObjectIdentifier>` mà bản struct cũ gây ra ở mỗi event.
* Chi phí syscall: `ProcessInfo.systemUptime` chỉ được đọc ở `beginReaderSession`, ở `emitSummary`, và mỗi 64 event (`clockSampleStride`) trong `updateWindow`. `AppLogger.shared.isLoggingEnabled` (getter chạm `UserDefaults`) chỉ đọc **một lần mỗi session Reader**.
* `ParagraphTracker.frames`/`visibleParagraphs` giữ nguyên vòng đời cũ trừ một điểm: `completeReaderPositionRestore` không còn `removeAll()`, nên frame map của các đoạn đang hiển thị (những đoạn không `onAppear` lại) được giữ qua bước restore vị trí. Các điểm thu hồi còn lại vẫn là `onDisappear`, `onChange(of: chapterIndex)`, đường navigate, `applyNavigationCommit`, `reloadCurrentChapterFromMenu`.

## Next-chapter prefix audio resource lifecycle (1.3.234)

* Tài nguyên được quản lý: các `Data` audio (WAV cho Nghi, MP3/nhị phân cho remote) của chunk đầu chương kế, thời lượng tương ứng (`durations`), cộng một `Task<Void, Never>` cho mỗi chunk đang tổng hợp.
* **Trần chiếm dụng**: `chunks.count + tasks.count <= capacity` do caller truyền vào — Google/Ext `max(0, count - inChapterTargetCount - 1)` (giữ độ sâu phía trước đúng bằng `count`); NghiTTS `max(0, NghiSynthesisPolicy.maxTotalAudioPayloads - heldPayloads)` và chỉ khi `cachedTime` chưa đạt ngưỡng. Vì vậy tổng payload audio trong RAM giữ nguyên trần cũ (`count + 1` cho remote; 5 payload logic cho Nghi).
* `trim(toCapacity:)` là điểm thu hồi duy nhất khi capacity co lại: hủy task và xóa `chunks` + `durations` có index vượt trần, snapshot khoá bằng `Array(...)` trước khi mutate dictionary.
* Giải phóng: `consume(matching:)` (chuyển quyền sở hữu sang `preloadedData`), `reset()` (stop/đổi engine/đổi giọng/key khác), `cancelPendingWork()` (pause — chỉ giải phóng task, giữ `Data`).
* Sau khi được nhồi vào `preloadedData`, các `Data` này chịu đúng cơ chế thu hồi cũ: `cacheKeepIndices` của `updatePrefetchWindow` (remote) và `clearCurrentParagraphPrefetchCache()` ở mỗi lần chuyển chương/stop. Không có đường nào giữ tham chiếu kép.
* Không có file tạm nào được tạo bởi bộ đệm này; với extension TTS, việc dọn file tạm vẫn thuộc `extService.cleanupAllTempFiles()` như trước.

## NghiTTS refill failure lifecycle (1.3.147)

* Mỗi lỗi refill được sở hữu bởi khóa `sessionID + chapterIndex + paragraphIndex`; success xóa state, lỗi không retry hoặc attempt thứ hai chuyển state sang blocked.
* Lần retry duy nhất được giữ bởi `nghiRefillRetryTask`. Trong cooldown 1 giây, scheduler không tạo refill mới; task sở hữu generation xóa reference của chính nó trước khi gọi lại cửa sổ prefetch.
* `cancelNghiRefill()` tăng refill generation, hủy synthesis/retry task và xóa failure states khi cache/session/chapter bị thay thế. Cancellation path không mutate dictionary và stale context bị loại trước khi ghi state.
* Audio khoảng lặng dùng dữ liệu WAV/PCM thông thường và không tạo thêm engine hoặc tài nguyên phát riêng.

## NghiTTS safeCachedTimeThreshold task lifecycle (1.3.141)

* Refill tasks allocate single paragraph requests when `cachedTime < threshold` and optional reserve items < 2 (max 5 logical payloads total). When `cachedTime >= threshold`, `nghiWakeTask` holds a cancellable deadline sleep task ($\Delta t = \text{cachedTime} - \text{threshold}$).
* Pause releases `nghiWakeTask` and queued optional requests in `PiperSynthesisCoordinator.cancelPendingRequests()`. Active ONNX inference completes and caches into `preloadedData[index]`.
* Settings lifecycle: `prepareForSettings` captures `TTSSettingsSnapshot`. If only `nghittsSafeCachedTimeThreshold` changes, `resumeAfterSettings` restores `wasPlaying` state without clearing audio buffers or restarting audio.

## Chapter repository resource lifecycle (1.3.114)

* Shared normalized documents are held by a dual-limit LRU (12 entries and 12 MiB estimated cost). Least-recent entries are released on insertion pressure; all reusable entries are released on memory warning, while active consumer values and persistent storage remain intact.
* Each repository-owned in-flight task retains only active UUID waiters. Canceling a waiter resumes it with `CancellationError`; zero remaining waiters cancel and release the task. Completion/failure resumes all remaining waiters exactly once and removes the entry.
* `chapterAdvanceTask` is retained by `TTSManager` only for fallback next-chapter loading/processing. A monotonic generation prevents an older task's cleanup from releasing a newer task reference.

## TTS presentation resource lifecycle (1.3.112)

* The floating cover allocates no recurring timeline/display-rate resource during playback. Its parent-owned loader retains one decoded `UIImage` and a book/URL key; expanded/peeking transitions reuse them and only a true cover-identity change initiates local/remote loading.
* Projection readers own only selected Combine subscriptions and one small Equatable snapshot. Reader book scoping prevents another session's paragraph/highlight stream from producing view publications.
* Now Playing owns at most one static metadata task and one cached `MPMediaItemArtwork`. A matching key reuses both; replacement, stop, or dictionary invalidation cancels/clears them. Cover download is requested at most once per static key and a successful save rebuilds the cache.
* Nghi model warm-up is delayed and cancelable. App initialization schedules it only when Nghi is already selected; switching to Siri/Google/Ext cancels pending preparation.

## Web-extension DOM ready polling resource lifecycle (1.3.39)

* **Exactly-once completion**: Polling registers a `DispatchQueue.main.asyncAfter` work item. Closing the browser or launching a new wait cancels any pending polling timer and resolves the wait immediately (exactly-once callback).
* **Single wait constraint**: A browser instance supports a single active wait constraint; any new wait request automatically cancels the previous wait task.

## Book storage and pagination resource lifecycle (1.3.34)

* **Background Deletion Tasks**: Deleting a book commits model context changes first. Upon successful database saving, physical file cleanup (covers/bin) is spawned inside a detached background `Task`. If deletion fails, resources enter the `UserDefaults` queue, surviving application restarts.
* **Retry Queue Persistence**: At launch in `FreeBookApp` startup, `drainRetryQueue()` is executed to process the failed deletion queue. It retries physical deletion of each path up to 3 times before discarding to prevent resource leaks.
* **Paged Rows Memory Lifecycle**: Memory for the table of contents is bounded: only 3 pages (300 rows) are kept loaded at any time in `loadedRowStates`. When a new page is loaded, the page outside the sliding window is evicted, freeing its memory, while placeholder metadata (`ChapterRowItem`) remains lightweight.

## Reader resource lifecycle update (1.3.11, supersedes 1.3.10)

The navigation debounce holds only the newest manual target for 300 ms. One navigation worker waits for any started extension fetch to return, then checks generation before committing. Shutdown cancels both tasks and clears queued navigation.

Speculative loading owns a separate 750 ms settled timer and requests only N+1. It is canceled by navigation, Reader shutdown, or same-book TTS playback. `PrefetchManager` retains concurrency slots until cancellation-insensitive extension work actually returns.

The chapter-list store and its lazy list stay allocated while Reader is alive, then release together. Individual cache icon updates mutate one row object and allocate no replacement list.

## 1. Vòng đời phát âm thanh & AVAudioSession (Âm thanh nền)

FreeBook phát TTS ổn định dưới nền. **Lưu ý quan trọng**: đường phát thực tế **không** dùng `AVAudioEngine` node-streaming. `TTSManager` khởi tạo một `TTSAudioEngineController` và gọi `configureEngine(...)` để dựng đồ thị node (`audioEngine`/`playerNode`/`timePitchNode`/`eqNode`), nhưng `audioEngineController.play()` (chứa `engine.start()` + `player.play()` + `scheduleBuffer`) **không có caller nào** — đồ thị node được dựng rồi bỏ không, và trong repo hiện tại **không tồn tại lệnh `scheduleBuffer`** nào. Âm thanh thật được phát qua:

| `tool` | Cơ chế phát thật |
|---|---|
| `nghitts` | `AVAudioPlayer` double-buffer qua `NghiAudioPlayerQueue` |
| `google` / *(ext)* | `AVAudioPlayer` (`TTSManager.audioPlayer`, delegate `audioPlayerDidFinishPlaying`) |
| `system` | `AVSpeechSynthesizer` (`SiriTTSService`) |

```mermaid
stateDiagram-v2
    [*] --> Uninitialized : App Start
    Uninitialized --> Configured : setupAudioEngine() / configureEngine() dựng node graph (không phát)

    Configured --> Active : startSpeaking() / setActive(true) & configureAudioSession()
    Active --> Playing : AVAudioPlayer.play() (nghitts/google/ext) hoặc AVSpeechSynthesizer.speak() (system)

    Playing --> Interrupted : Interruption began (Cuộc gọi đến) / audioPlayer.pause()
    Interrupted --> Playing : Interruption ended / audioPlayer.play()

    Playing --> Stopped : stopPlayback() / audioPlayer.stop() & audioPlayer = nil
    Stopped --> Inactive : setActive(false) / Giải phóng session hệ thống
    Inactive --> [*] : Hủy app
```

### Chi tiết các bước vòng đời:
1.  **Khởi tạo (Initialization)**: `setupAudioEngine()` gọi `audioEngineController.configureEngine(...)` để dựng và kết nối `audioEngine`/`playerNode`/`timePitchNode`/`eqNode` một lần. Đồ thị này hiện **không tham gia phát**; nó chỉ tồn tại như hạ tầng dự phòng.
2.  **Kích hoạt Session (Activation)**: `configureAudioSession()` cấu hình category `.playback`, mode `.spokenAudio` với options `.duckOthers` + `.allowBluetoothA2DP` và gọi `setActive(true)`. Ghi chú (1.3.180): option `.allowBluetooth` (HFP) đã được bỏ vì không hợp lệ với category `.playback` — kết hợp này khiến `setCategory` ném `OSStatus -50` (`AVAudioSessionErrorCodeBadParam`), làm `setActive(true)` không bao giờ chạy.
3.  **Phát (Playback)**:
    *   Buffer WAV/MP3 đã tổng hợp được nạp vào RAM cache `preloadedData` (kèm `preloadedDurations`).
    *   Với `nghitts`/`google`/ext: khởi tạo `AVAudioPlayer` từ dữ liệu preloaded rồi gọi `player.play()`; `nghitts` xoay vòng hai player qua `NghiAudioPlayerQueue`.
    *   Với `system`: đẩy `AVSpeechUtterance` vào `AVSpeechSynthesizer`.
4.  **Chuyển đoạn (Advance)**: `audioPlayerDidFinishPlaying` (delegate `AVAudioPlayer`) hoặc callback tương ứng của `AVSpeechSynthesizer` kích hoạt đoạn kế; không có bước `disconnectNodeOutput`/`connect` lại node vì đường node-streaming không được dùng.
5.  **Dừng & Thu hồi (Deactivation)**: Khi dừng phát hoàn toàn (`stopPlayback` với `keepWidget = false`), hệ thống gọi `audioPlayer?.stop()`, giải phóng `audioPlayer = nil`, rồi trả kênh âm thanh cho hệ thống qua `AVAudioSession.sharedInstance().setActive(false)`.

---

## 2. Vòng đời của Task chạy ngầm (Asynchronous Tasks)

FreeBook quản lý nhiều tác vụ bất đồng bộ thông qua mô hình Structured Concurrency của Swift:

1.  **Debounce DB Save Task (`dbSaveTask`)**:
    *   *Khởi tạo*: Tạo mới trong `ReaderViewModel.updateProgress` khi vị trí đọc thay đổi.
    *   *Trì hoãn*: Thực thi `try await Task.sleep` chờ 3 giây.
    *   *Hủy bỏ*: Nếu người dùng cuộn tiếp trước khi hết 3 giây, task cũ bị hủy lập tức qua `dbSaveTask?.cancel()`.
2.  **Download Tasks (Tác vụ tải nền)**:
    *   *Khởi tạo*: Kích hoạt qua `Task.detached(priority: .background)` để đẩy hoàn toàn tác vụ I/O và mạng ra khỏi Main Thread.
    *   *Giám sát*: Vòng lặp tải chương thường xuyên kiểm tra cờ `Task.isCancelled` hoặc `isCancelled` từ `DownloadManager`.
    *   *Hủy bỏ*: Khi phát hiện cờ hủy, task tự giải phóng các đối tượng kết nối và thoát vòng lặp an toàn.

---

## 3. Vòng đời của Ngữ cảnh Cơ sở dữ liệu (ModelContext)

Để tránh lỗi tranh chấp dữ liệu (Data Race) trong SwiftData, việc quản lý vòng đời `ModelContext` được tách biệt:

*   **Main Thread Context**: `@Query` và `modelContext` trong `ReaderViewModel` được gắn với Main Actor để phục vụ hiển thị trực tiếp lên giao diện SwiftUI. Tự động lưu qua hệ thống quản lý của SwiftUI.
*   **Background Context**:
    *   *Khởi tạo*: Trong các background task, một context mới được tạo: `let bgContext = ModelContext(container)`.
    *   *Sử dụng*: Mọi thao tác truy vấn, cập nhật nội dung chương, hoặc tạo mới book được thực hiện trên `bgContext`.
    *   *Ghi đĩa*: Gọi `try? bgContext.save()` để ghi xuống file SQLite ngầm.
    *   *Giải phóng*: Context bị hủy và giải phóng hoàn toàn sau khi hàm kết thúc.

---

## 4. Vòng đời Trình duyệt Ngầm (WKWebView)

WKWebView được sử dụng để tải các trang web chứa mã bảo vệ Cloudflare hoặc nội dung động.

*   **Khởi tạo**: Khởi tạo `WebViewLoader()` bên trong `JSExecutor.browserNewBlock` (luôn ép buộc chạy trên Main Thread thông qua `DispatchQueue.main.sync` hoặc `DispatchQueue.main.async`).
*   **Tải trang**: Gọi `loader.load(...)` và chặn luồng gọi bằng `DispatchSemaphore` cho đến khi delegate `didFinish navigation` báo hoàn thành.
*   **Thu hồi**: Được giải phóng trong `WebViewLoader.deinit`. Để tránh crash bộ nhớ trên iOS, việc hủy `WKWebView` được chuyển tiếp an toàn về Main Thread:
    ```swift
    deinit {
        let wv = self.webView
        DispatchQueue.main.async {
            wv.configuration.userContentController.removeAllUserScripts()
            wv.navigationDelegate = nil
        }
    }
    ```

---

## 5. Vòng đời của các Callbacks/Closures trên Singleton (Tránh rò rỉ tham chiếu)
*   **Vấn đề**: Khi một View đăng ký lắng nghe callbacks từ một dịch vụ Singleton (như `TTSManager.shared.onChapterFinished = { ... }`), dịch vụ Singleton sẽ giữ chặt tham chiếu đến View (thông qua closure gán). Điều này dẫn đến việc View không thể deinit (bị rò rỉ bộ nhớ dưới dạng Ghost Reference) ngay cả khi đã bị đóng/dismiss khỏi UI.
*   **Giải pháp trong FreeBook**:
    *   *Khởi tạo*: View (như `ReaderView.swift`) đăng ký callbacks cho `TTSManager` khi xuất hiện (`.onAppear` hoặc khi khởi chạy TTS).
    *   *Giải phóng*: `TTSManager` giờ chỉ còn **một** callback do View gán là `onChapterFinished`; hai callback cũ `onChapterNext`/`onChapterPrev` đã bị xóa. Reader không nil hóa callback trong `.onDisappear` nữa vì phiên TTS được thiết kế sống lâu hơn vòng đời Reader:
        ```swift
        ttsManager.onChapterFinished = { ... } // đăng ký khi bắt đầu phát
        ```
    *   *Độc lập hóa nghiệp vụ*: Trình quản lý singleton (`TTSManager`) tự động hóa các tiến trình nội bộ (như tự chuyển chương qua `advanceToNextChapter` mà không cần callbacks trung gian điều khiển từ View).

#### Reader/TTS unified pipeline (2026-07)

- `ChapterTextNormalizer` is the single source for LF newlines, trimmed non-empty lines, **sparse paragraph IDs (`ChapterTextLine.id` is the raw line index and counts blank lines, so IDs are not array offsets and must be looked up by `id`, never used as an array index)**, and UTF-16 ranges. Because those ranges are computed before blank lines are dropped, `ChapterTextLine.utf16Range` must not be used to slice `NormalizedChapterText.content`. `ChapterContentRepository` produces one normalized `ChapterDocument` for both Reader and TTS.
- Reader uses `ReaderLoadState` with bootstrap retry/clamping, typed failures, generation checks, cache-first rendering, and a short opacity crossfade only for newly fetched content. `ReaderRoute.chapterIndex` preserves the selected TOC index through navigation.
- `TTSParagraphBuilder` chunks normalized lines without renumbering parent paragraph IDs; replacement output is checked before synthesis. TTS asynchronous work is guarded by session identity and TTS owns progress while playing.
- `ReadingProgressStore` coalesces RAM snapshots in an actor and flushes from background contexts on checkpoints, dismissal, and app backgrounding. Legacy window/tab Reader, duplicate progress repository, and `TTSSession` mirror are removed.
- Shared chapter fetch tasks are repository-owned and subscriber-aware. Reader cancellation removes only its waiter, so a TTS waiter preserves the load; when the final waiter leaves, the underlying task is canceled. Force refresh cancels the superseded load and resumes all of its prior waiters with cancellation.
- `ReaderViewModel.translationRefreshTask` owns dictionary-driven chapter rebuilds. A newer dictionary update cancels the previous refresh, loaded chapter snapshots are processed sequentially with the displayed chapter first, and deinit cancels the remaining work. Live TTS audio-prefetch tasks are not canceled by this Reader event.
- Pending SwiftData writes retry up to three times, survive Reader dismissal, and are flushed by Reader/app lifecycle checkpoints. Cached chapter models survive TOC reconciliation when their URL remains present.
- Book deletion database context changes commit first, spawning a background task (`Task.detached`) for physical file cleanup. Physical file cleanup failures enter a persistent retry queue in `UserDefaults` and undergo retry cycles at app launch up to 3 times before discard.
- TOC pagination bounds the memory lifecycle: only 3 pages (300 rows) are kept loaded at any time in `loadedRowStates`. When a new page is loaded, pages outside the active window are evicted and their state objects are destroyed, freeing memory.

- Remote TTS jobs enter a single priority queue owned by `RemoteTTSSynthesisCoordinator`. A job owns its service operation until completion; duplicate callers own only continuations. Retry (max 2 attempts) lives inside the coordinator, not `TTSManager`. Pause or stop cancels the applicable remaining continuations/tasks. Thermal state is telemetry-only: `.serious`/`.critical` do not release or throttle distant/next-chapter work.
- `ExtTTSRuntime` keeps its `JSExecutor` across chunks of the same extension/config. It cancels registered network tasks and releases the context when identity changes, an execution fails, or full TTS cache cleanup requests reset.
- Native sync fetch registers each `URLSessionDataTask`, cancels it on Swift task cancellation/timeout, and waits a bounded interval for its completion callback before returning from the JS bridge.
- The cached NghiTTS ORT session keeps one worker for its lifetime and prefers XNNPACK when available. The prefetch window keeps the current paragraph `N` and mandatory next `N+1`, plus up to `NghiSynthesisPolicy.maxOptionalReserveItems` (2) optional reserve items from `N+2` gated by the cached-time watermark (`defaultSafeCachedTimeThreshold = 8.0`s); reserve items are dropped under memory pressure. Thermal state is diagnostic-only and never cancels or gates refill; `TTSManager` owns the refill retry (max 2 attempts, 1 s backoff).

<!-- GENERATED END -->
