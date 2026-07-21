---
generated_by: Antigravity
generator_version: 1.0
generated_at: 2026-07-17T23:26:29+07:00
git_commit: UNKNOWN
source_files: 93
document_version: 3
---

# Đồ thị Lời gọi Hàm (Call Graph)

Tài liệu này mô tả chi tiết đồ thị lời gọi hàm (Call Graph) của các phương thức cốt lõi trong hệ thống FreeBook.

## Ghi chú thủ công (Human Notes)
*Ghi chú thủ công của con người.*

<!-- GENERATED START -->
## Book storage and deletion calls (1.3.34)

* `BookStorageManager.removeFromShelf` and `removeFromHistory` invoke `deleteBookComplete` if the book has no historical/shelf references left.
* `deleteBookComplete` calls `deleteBooks(bookIds:context:)` which fetches local `Book` instances, cancels active download tasks (`DownloadManager.cancelTasksForBook`), stops active playback (`TTSManager.stop`), deletes database objects, and commits (`context.save()`).
* Upon successful DB save, `deleteBooks` launches a detached background `Task` to delete physical `.bin` files (`BookBinManager.deleteBinFile`) and cover images (`ImageCacheManager.deleteCover`).
* Physical file deletion failures are queued via `enqueueFailedDeletion` and retried at launch through `drainRetryQueue` called from `FreeBookApp` startup view.

## Reader paragraph and selection calls (1.3.14)

* `ReaderViewModel.processAndSaveChapter` and the legacy Reader path both call `ReaderParagraphBuilder.build`, which translates each original line independently and returns aligned paragraph items.
* `translateContentWithMapping` preserves `translateContent` output, then aligns translation tokens against the post-processed output to create UTF-16 spans; an incomplete alignment returns no spans.
* The custom “📖 Dịch” action emits `NSRange` to `ParagraphCardView`, which adds `item.id`; `ReaderView` looks up that id in the requested chapter and calls `ReaderSelectionMapper`.
* `ReaderSelectionMapper` prefers stored spans, then uses the sentence/token algorithm from commit `3312841`; the definition editor always receives the full `item.original` and an original-text range.

## Reader navigation calls (1.3.13, supersedes 1.3.11)

* `ReaderView` routes footer buttons, chapter-list jumps, history restore, and TTS sync through `ReaderViewModel.requestChapter(...)` or `stepChapter(...)`; horizontal drags have no navigation call.
* `requestChapter` coalesces manual targets for 300 ms. `runNavigationWorker` executes one target at a time, rejects stale generations, and calls either `commitNavigation` or `failNavigation`.
* While a request is pending, the reading surface and chrome derive their presentation target from `pendingNavigationIndex` and render skeleton content instead of the previously displayed chapter.
* `reloadDisplayedChapter` bypasses RAM and SwiftData chapter content; `retryPendingNavigation` repeats the failed request with its original paragraph and persistence policy.
* A successful persistent save invokes `onChapterCached(index)`, which calls `ReaderChapterListStore.markCached(index:)`.

## Chi tiết Đồ thị Lời gọi các Hàm Cốt lõi

### 1. `ReaderViewModel.updateProgress(chapterIndex:paragraphIndex:)`
*   **Confidence**: High
*   **Khai báo**: `@MainActor func updateProgress(chapterIndex: Int, paragraphIndex: Int)`
*   **Được gọi bởi (Called by)**:
    *   `ReaderTextView.swift` (Cuộn qua các dòng chữ).
*   **Gọi đến (Calls)**:
    *   `ChapterCache.setScrollParagraph(_:paragraphIndex:)`
    *   `ReaderViewModel.triggerDebounceDBSave()`
*   **Side Effects**: Thay đổi vị trí đọc hiện tại trên RAM, lên lịch tự động lưu dữ liệu sau 3 giây.
*   **Async**: No
*   **Throws**: No
*   **MainActor**: Yes

---

### 2. `ReaderViewModel.triggerDebounceDBSave()`
*   **Confidence**: High
*   **Khai báo**: `private func triggerDebounceDBSave()`
*   **Được gọi bởi (Called by)**:
    *   `ReaderViewModel.updateProgress(chapterIndex:paragraphIndex:)`
*   **Gọi đến (Calls)**:
    *   `ReadingProgressRepository.saveProgress(bookId:progress:)` (Chạy bất đồng bộ bên trong Task).
*   **Side Effects**: Thực hiện ghi đĩa (SwiftData context save) vị trí đọc mới nhất của sách.
*   **Async**: Chạy bất đồng bộ qua `Task` với debounce 3 giây (`Task.sleep`).
*   **Throws**: No
*   **MainActor**: Yes

---

### 3. `TTSManager.shared.startSpeaking(...)`
*   **Confidence**: High
*   **Khai báo**: `public func startSpeaking(bookId:chapters:currentIndex:chapterContent:startParagraphIndex:bookTitle:coverUrl:extensionInfo:)`
*   **Được gọi bởi (Called by)**:
    *   `ReaderView.swift` (Nút play chỉ truyền metadata chương hiện tại và chương kế; toàn bộ queue được nạp trễ sau khi âm thanh đã bắt đầu).
    *   `TTSFloatingWidgetView.swift` (Nút play trên floating widget).
*   **Gọi đến (Calls)**:
    *   `TTSManager.stopCurrentPlayback()`
    *   `TTSManager.configureAudioSession()`
    *   `TTSManager.setRemoteCommandsEnabled(true)`
    *   `TTSManager.clearPrefetchCache()`
    *   Đọc `preparedChapter` nếu Reader đã prewarm đúng chương; nếu cache miss mới gọi `TTSBackgroundProcessor.processChapter(...)` bằng processor riêng.
    *   `TTSManager.continueStartSpeaking(startParagraphIndex:)` (Cập nhật kết quả lên MainActor)
    *   `TTSManager.updateChaptersQueue(_:for:)` được Reader gọi trễ để bật auto-advance/prefetch mà không chặn nút Play.
*   **Side Effects**: Thiết lập phiên âm thanh nền, cập nhật trạng thái UI widget hiển thị.
*   **Async**: Yes (Chạy xử lý đoạn văn ngầm bất đồng bộ)
*   **Throws**: No
*   **MainActor**: Yes

---

### 3a. `TTSManager.shared.prepareSpeaking(...)`
*   **Confidence**: High
*   **Khai báo**: `public func prepareSpeaking(bookId:chapters:currentIndex:chapterContent:...)`
*   **Được gọi bởi (Called by)**:
    *   `ReaderView.swift` (Prewarm chương đang hiển thị sau khi Reader ổn định vị trí).
*   **Gọi đến (Calls)**:
    *   `TTSBackgroundProcessor.processChapter(...)` bằng actor riêng có thể hủy.
*   **Side Effects**: Chỉ cập nhật cache chuẩn bị; không đổi `playingChapterIndex`, `isPlaying` hay phiên TTS đang pause.
*   **MainActor**: Yes

---

### 4. `TTSManager.shared.speakCurrent()`
*   **Confidence**: High
*   **Khai báo**: `private func speakCurrent()`
*   **Được gọi bởi (Called by)**:
    *   `TTSManager.continueStartSpeaking(startParagraphIndex:)`
    *   `TTSManager.nextParagraph()`
    *   `TTSManager.skipForward()`
    *   `TTSManager.skipBackward()`
    *   `TTSManager.restartCurrentParagraph()`
*   **Gọi đến (Calls)**:
    *   `TTSReplacementManager.shared.applyReplacements(to:)`
    *   `TTSManager.saveTTSProgressToDatabase(...)`
    *   `TTSManager.playSystemTTS(_:)` (Nếu tool == "system")
    *   `TTSManager.playNghiTTS(_:)` (Nếu tool == "nghitts")
    *   `TTSManager.playExtensionTTS(_:)` (Nếu tool == "extension")
*   **Side Effects**: Cập nhật chỉ số đoạn văn bôi đen trên giao diện, cập nhật vị trí đọc của Audio book xuống SwiftData.
*   **Async**: No
*   **Throws**: No
*   **MainActor**: Yes

---

### 5. `TTSManager.shared.playAudioBuffer(_:withId:)`
*   **Confidence**: Medium
*   **Khai báo**: `private func playAudioBuffer(_ buffer: AVAudioPCMBuffer, withId customId: String? = nil)`
*   **Được gọi bởi (Called by)**:
    *   `TTSManager.playNghiTTS(_:)`
    *   `TTSManager.playExtensionTTS(_:)`
*   **Gọi đến (Calls)**:
    *   `AVAudioPlayerNode.stop()`
    *   `AVAudioEngine.connect(_:to:format:)` (Chỉ rebuild node khi định dạng thay đổi)
    *   `AVAudioEngine.start()` (Khởi động engine nếu chưa chạy)
    *   `AVAudioPlayerNode.scheduleBuffer(_:at:options:completionHandler:)`
    *   `AVAudioPlayerNode.play()`
    *   `TTSManager.updateNowPlayingInfo()`
*   **Dynamic Dispatch (Confidence: UNKNOWN)**:
    *   `scheduleBuffer` nhận một `completionHandler` callback chạy bất đồng bộ từ luồng âm thanh ngầm của hệ thống.
    *   **Side Effect**: Khi completionHandler kết thúc phát đoạn nhạc, nó đẩy một task bất đồng bộ về Main Queue (`DispatchQueue.main.async`) để gọi `nextParagraph()`.
*   **Async**: No
*   **Throws**: No
*   **MainActor**: Yes

---

### 6. `DownloadManager.shared.executeTask(_:container:)`
*   **Confidence**: High
*   **Khai báo**: `private func executeTask(_ task: DownloadTask, container: ModelContainer) async`
*   **Được gọi bởi (Called by)**:
    *   `DownloadManager.runNextTaskIfNeeded(container:)` thông qua một `Task.detached` chạy nền.
*   **Gọi đến (Calls)**:
    *   `ExtensionManager.shared.chap(...)`
    *   `TranslateUtils.translateContent(...)`
    *   `ModelContext.save()` (Background context save)
    *   `DownloadManager.updateProgress(...)` (Chuyển tiếp về MainActor)
    *   `DownloadManager.markCompleted(...)` (Chuyển tiếp về MainActor)
    *   `DownloadManager.markFailed(...)` (Chuyển tiếp về MainActor)
*   **Side Effects**: Tải nội dung chương về lưu DB offline, hoặc ghi tệp TXT tạm thời và mở Share Sheet.
*   **Async**: Yes
*   **Throws**: No
*   **MainActor**: No

---

### 7. `ExtensionManager.shared.chap(...)`
*   **Confidence**: High
*   **Khai báo**: `public func chap(localPath: String, downloadUrl: String, url: String, configJson: String) async throws -> String`
*   **Được gọi bởi (Called by)**:
    *   `DownloadManager.shared.executeTask(_:container:)`
    *   `ReaderViewModel.loadChapterOnline(...)`
*   **Gọi đến (Calls)**:
    *   `JSExecutor.runAsync(scriptContent:functionName:arguments:)`
*   **Side Effects**: Khởi tạo engine JS ngắn hạn để bóc tách chương.
*   **Async**: Yes
*   **Throws**: Yes
*   **MainActor**: No

---

### 8. `JSExecutor.runAsync(...)`
*   **Confidence**: Medium
*   **Khai báo**: `public func runAsync(scriptContent: String, functionName: String, arguments: [Any]) async throws -> JSValue`
*   **Được gọi bởi (Called by)**:
    *   `ExtensionManager` (Hành động chạy bóc tách).
*   **Gọi đến (Calls)**:
    *   `JSContext.evaluateScript(_:)`
    *   `JSValue.call(withArguments:)`
*   **Dynamic Dispatch (Confidence: UNKNOWN)**:
    *   Nếu kết quả của hàm JS trả về là một JS Promise (`thenable`), hàm này sử dụng `withCheckedThrowingContinuation` để chờ đợi bất đồng bộ.
    *   Đăng ký callback `onResolve` và `onReject` vào Promise của JS.
*   **Async**: Yes
*   **Throws**: Yes
*   **MainActor**: No

---

### 9. `TranslationManager.shared.getBookDictionaries(for:)`
*   **Confidence**: High
*   **Khai báo**: `public func getBookDictionaries(for bookId: String) -> (vietPhrase: TrieDictionary?, names: TrieDictionary?)`
*   **Được gọi bởi (Called by)**:
    *   `TranslateUtils.translateContent(_:bookId:)`
    *   `TranslateUtils.translateChapterTitle(_:bookId:)`
*   **Gọi đến (Calls)**:
    *   `DoubleArrayTrieBuilder.build(fromTxtFile:toDatFile:)`
    *   `DoubleArrayTrie.load(from:)`
*   **Side Effects**: Nạp các từ điển VietPhrase/Names riêng của sách vào RAM cache `bookDicts`.
*   **Async**: No
*   **Throws**: No
*   **MainActor**: No

---

## 3. Các cuộc gọi động hoàn toàn (Confidence: UNKNOWN / RUNTIME ONLY)

### 3.1. Sự kiện tương tác UI qua SwiftUI Modifiers
*   **Cuộc gọi**: Các sự kiện nút nhấn được gắn kết qua SwiftUI closure:
    ```swift
    Button(action: { TTSManager.shared.pause() }) { ... }
    ```
*   **Phân tích tĩnh**: **UNKNOWN**. Luồng chạy hoàn toàn phụ thuộc vào tương tác của người dùng trên màn hình cảm ứng của thiết bị iOS.

### 3.2. Sự kiện Remote Command Center
*   **Cuộc gọi**: Các sự kiện bấm nút trên màn hình khóa hoặc tai nghe (Play/Pause/Next/Prev) được đăng ký qua `MPRemoteCommandCenter`.
*   **Phân tích tĩnh**: **UNKNOWN**. Hệ điều hành iOS tiếp nhận lệnh phần cứng rồi dispatch vào closure đăng ký trong `TTSManager.setupRemoteCommandCenter()`.

### 3.3. Các thông báo hệ thống (Notification Center)
*   **Cuộc gọi**: `AVAudioSession.interruptionNotification`, `routeChangeNotification`, `mediaServicesWereResetNotification`.
*   **Phân tích tĩnh**: **UNKNOWN**. Đăng ký lắng nghe qua Combine publishers. Hệ điều hành phát thông báo và kích hoạt callback thực thi trong `TTSManager`.

#### Reader/TTS unified pipeline (2026-07)

- `ChapterTextNormalizer` is the single source for LF newlines, trimmed non-empty lines, compact paragraph IDs, and UTF-16 ranges. `ChapterContentRepository` produces one normalized `ChapterDocument` for both Reader and TTS.
- Reader uses `ReaderLoadState` with bootstrap retry/clamping, typed failures, generation checks, cache-first rendering, and a short opacity crossfade only for newly fetched content. `ReaderRoute.chapterIndex` preserves the selected TOC index through navigation.
- `TTSParagraphBuilder` chunks normalized lines without renumbering parent paragraph IDs; replacement output is checked before synthesis. TTS asynchronous work is guarded by session identity and TTS owns progress while playing.
- `ReadingProgressStore` coalesces RAM snapshots in an actor and flushes from background contexts on checkpoints, dismissal, and app backgrounding. Legacy window/tab Reader, duplicate progress repository, and `TTSSession` mirror are removed.
- Widget actions call `TTSManager.pause/resume/skipForward/stop`; `skipForward` also advances the selected paragraph while paused, and Reader recovery uses the `navigateReaderToPlayingChapter` notification when the book is already visible.
- Reader/TTS call `ChapterContentRepository.load`; it coalesces by `ChapterKey`, calls `ChapterPersistenceStore.readChapter`, falls back to the extension, then enqueues `upsert` without blocking MainActor.
- Reader dismissal and app background call repository flush APIs. Repository deletion calls extension uninstall only after confirmation and rejects deletion while that repository owns the visible TTS session.
- Deletion requests on `ShelfView` and `BookDetailView` invoke database deletion and side-effect cancellation (TTS, downloads) before dispatching background file cleanup events.
- Physical file deletion failures emit path details to the `UserDefaults` retry queue, and app startup triggers a queue drain event (`drainRetryQueue()`) to retry up to 3 times.
- `ReaderChapterListStore` paging actions trigger asynchronous metadata loading events using `fetchPage` inside background tasks, updating the visible list rows.
- `DownloadManager` tasks check `Task.isCancelled` at chapter boundaries during download or export tasks to support cooperative cancellation.

<!-- GENERATED END -->
