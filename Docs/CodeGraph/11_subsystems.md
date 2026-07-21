---
generated_by: Antigravity
generator_version: 1.0
generated_at: 2026-07-17T23:26:29+07:00
git_commit: UNKNOWN
source_files: 93
document_version: 3
---

# Phân tích các Phân hệ Cốt lõi (Subsystems)

Tài liệu này phân tích chi tiết 14 phân hệ chính cấu thành nên ứng dụng FreeBook, mô tả mục tiêu, API công khai, dependency, quan hệ sở hữu đối tượng, điểm vào/ra, vòng đời và các rủi ro tương ứng cho từng phân hệ.

## Ghi chú thủ công (Human Notes)
*Ghi chú thủ công của con người.*

<!-- GENERATED START -->
## Reader translation subsystem update (1.3.14)

Reader paragraph creation is centralized in `ReaderParagraphBuilder`: original lines are the source of truth, translation is one-to-one, and paragraph ids never depend on translated output. `TranslateUtils` exposes mapped translation results with UTF-16 spans, while `ReaderSelectionMapper` owns exact and historical fallback range conversion. The definition editor continues to operate only on original paragraph text.

## Reader subsystem update (1.3.13, supersedes 1.3.11)

The Reader runtime renders one chapter in one vertical `ScrollView`. Chapter changes come only from footer buttons, chapter list, history restore, or TTS sync. Horizontal drags and reaching the vertical end have no navigation side effect.

`ReaderViewModel` owns the latest-target navigation queue, generation checks, retry state, one-forward prefetch, and progress persistence policy. `ReaderChapterListStore` owns the mounted table-of-contents snapshot and row-level cache state.

Public Reader APIs include `stepChapter`, `requestChapter`, `retryPendingNavigation`, `reloadDisplayedChapter`, and `setSpeculativePrefetchEnabled`.

Reader chrome observes the pending target and immediately shows its title, chapter number, and skeleton rows while keeping the 300 ms input-coalescing delay. The compact metadata block opens the always-mounted table of contents. Its header has a drag handle, compact cover metadata, refresh/sort controls, and no close button; the body exposes TTS as one floating control.

## 1. Phân hệ Trình đọc (Reader Subsystem)
*   **Mục tiêu (Purpose)**: Hiển thị nội dung chương truyện, quản lý vị trí đọc hiện tại, tải trước (prefetch) chương kế tiếp và lưu trữ vị trí đọc của người dùng.
*   **API công khai (Public API)**:
    *   `ReaderViewModel.updateProgress(chapterIndex:paragraphIndex:)`
    *   `ReaderViewModel.fetchChapter(at: Int) -> Chapter?`
    *   `ReaderViewModel.fetchChaptersMetadata(isTranslationEnabled: Bool) -> [TTSChapterInfo]`
    *   `ChapterCache.setScrollParagraph(_:paragraphIndex:)`
    *   `PrefetchManager.prefetchChapter(bookId:chapterIndex:...)`
*   **Dependencies**: SwiftData (`ModelContext`), `ExtensionManager`, `ReadingProgressRepository`, `ChapterCache`, `PrefetchManager`.
*   **Owned Objects**:
    *   `ReaderViewModel` sở hữu `ChapterCache` và `PrefetchManager`.
*   **Điểm bắt đầu (Entry Points)**: `ReaderView.swift` được khởi tạo từ `BookDetailView.swift` khi người dùng nhấn nút "Đọc truyện".
*   **Điểm kết thúc (Exit Points)**: Trình đọc đóng, quay trở lại màn hình chi tiết sách.
*   **Vòng đời (Lifecycle)**: Khởi tạo cùng `ReaderViewModel` -> Thiết lập `.task` tải nội dung -> Theo dõi scroll để cập nhật progress -> Hủy task và lưu progress khi View biến mất (`onDisappear`).
*   **Rủi ro đã biết (Known Risks)**:
    *   Rò rỉ bộ nhớ do `memoryWarningSubscription` trong `ReaderViewModel` lắng nghe `UIApplication.didReceiveMemoryWarningNotification` mà không giải phóng đúng cách (cần đảm bảo deinit chạy thành công).
    *   Lưu DB liên tục gây giật lag UI (đã tối ưu bằng cơ chế debounce 3 giây và chỉ lưu khi dịch chuyển quá 3 đoạn văn).

---

## 2. Phân hệ Giọng đọc (TTS Subsystem)
*   **Mục tiêu (Purpose)**: Chuyển văn bản thành giọng nói (Text-To-Speech) bằng nhiều công cụ (Siri hệ thống, NghiTTS Piper offline, Extension JS), hỗ trợ highlight chữ đang đọc, điều khiển phát nhạc nền, và tự động chuyển tiếp/tải chương mới chạy nền.
*   **API công khai (Public API)**:
    *   `TTSManager.shared.prepareSpeaking(...)`
    *   `TTSManager.shared.startSpeaking(...)`
    *   `TTSManager.shared.pause()`
    *   `TTSManager.shared.resume()`
    *   `TTSManager.shared.stop()`
    *   `TTSManager.shared.updateChapterCache(at:content:)`
    *   `TTSManager.shared.updateChaptersQueue(_:for:)`
*   **Dependencies**: `AVFoundation`, `MediaPlayer` (Now Playing Info & Remote Command Center), SwiftData (`ModelContainer`), `SiriTTSService`, `ExtTTSService`, `PiperTTSService`, `ExtensionManager`, `Chapter`, `TTSBackgroundProcessor` (actor xử lý nền).
*   **Owned Objects**:
    *   `TTSManager` sở hữu `SiriTTSService`, `ExtTTSService`, `PiperTTSService`, `ModelStore`, `NghiTTSClient`.
*   **Điểm bắt đầu (Entry Points)**: Người dùng nhấn nút phát TTS trên thanh widget hoặc trong trình đọc.
*   **Điểm kết thúc (Exit Points)**: Bấm nút stop, thoát ứng dụng, hoặc bị ngắt âm thanh hệ thống (Interruption).
*   **Vòng đời (Lifecycle)**: `TTSManager.shared` là Singleton tồn tại suốt vòng đời app. Bắt đầu phát -> cấu hình AudioSession -> chạy AudioEngine -> phát gối đầu (prefetch WAV) -> dừng giải phóng tài nguyên. Tự động tìm kiếm cache và tải chương kế tiếp qua `advanceToNextChapter(nextIdx:)` khi hết chương.
*   **Rủi ro đã biết (Known Risks)**:
    *   Rò rỉ bộ đệm âm thanh `preloadedWavs` (được khắc phục bằng cách dọn dẹp cửa sổ trượt gối đầu, chỉ giữ lại đoạn N và N+1).
    *   Xung đột đa luồng khi `completionHandler` của `AVAudioPlayerNode.scheduleBuffer` chạy trên thread riêng của AudioEngine, sau đó gọi lại `nextParagraph()` trên MainActor.
    *   Ghost Reference (rò rỉ tham chiếu ngược): Các callbacks (`onChapterFinished`, `onChapterNext`, `onChapterPrev`) của `TTSManager` giữ tham chiếu đến `ReaderView` bị leak khi dismiss (đã fix bằng cách đặt về `nil` trong `.onDisappear` của view).

---

## 3. Phân hệ Tải xuống (Download Subsystem)
*   **Mục tiêu (Purpose)**: Tải truyện offline để đọc không cần mạng và hỗ trợ xuất toàn bộ nội dung sách thành tệp định dạng TXT kèm tùy chọn dịch thuật.
*   **API công khai (Public API)**:
    *   `DownloadManager.shared.initialize(container:)`
    *   `DownloadManager.shared.deleteTask(taskId:)`
    *   `DownloadManager.shared.retryTask(taskId:)`
    *   `DownloadManager.shared.tasks`
*   **Dependencies**: SwiftData (`ModelContainer`, `ModelContext`), `ExtensionManager`, `TranslateUtils`.
*   **Owned Objects**:
    *   `DownloadManager` sở hữu danh sách `DownloadTask` trong RAM và đồng bộ xuống `DownloadTaskModel` trong DB.
*   **Điểm bắt đầu (Entry Points)**: Nhấn nút tải xuống hoặc xuất TXT từ `TaskOptionsSheet.swift` trong giao diện chi tiết sách.
*   **Điểm kết thúc (Exit Points)**: Tác vụ hoàn thành (hoặc xuất file share sheet), thất bại hoặc người dùng nhấn hủy.
*   **Vòng đời (Lifecycle)**: Singleton `DownloadManager.shared`. Khi app start, nạp các tác vụ cũ chưa chạy xong và đánh dấu thất bại. Chạy tuần tự các tác vụ bằng `Task.detached` ở background thread.
*   **Rủi ro đã biết (Known Risks)**:
    *   Lỗi ghi dữ liệu SwiftData đồng thời: Sử dụng `bgContext = ModelContext(container)` riêng cho background thread và truy cập fresh objects tránh xung đột luồng.

---

## 4. Phân hệ Âm thanh (Audio Subsystem)
*   **Mục tiêu (Purpose)**: Cấu hình phiên âm thanh hệ thống (AVAudioSession) chạy nền và kết nối các nút xử lý tín hiệu âm thanh (AVAudioEngine, AVAudioPlayerNode, AVAudioUnitTimePitch).
*   **API công khai (Public API)**:
    *   Các phương thức cấu hình cục bộ trong `TTSManager.swift`.
*   **Dependencies**: `AVFoundation` (`AVAudioSession`, `AVAudioEngine`).
*   **Owned Objects**:
    *   `TTSManager` sở hữu thực thể `AVAudioEngine`, `AVAudioPlayerNode` và `AVAudioUnitTimePitch`.
*   **Điểm bắt đầu (Entry Points)**: Được kích hoạt tự động khi gọi `TTSManager.shared.startSpeaking(...)`.
*   **Điểm kết thúc (Exit Points)**: Giải phóng khi gọi `TTSManager.shared.stop()`.
*   **Vòng đời (Lifecycle)**: Khởi tạo AudioEngine -> Connect Player -> TimePitch -> mainMixer. Cấu hình AudioSession `.playback` mode `.spokenAudio`. Lắng nghe `interruptionNotification` để tạm dừng/phát lại.
*   **Rủi ro đã biết (Known Risks)**:
    *   **Deadlock nghiêm trọng**: Hàm `browserLaunchBlock` dùng `DispatchSemaphore` chờ đồng bộ `WKWebView` trên Main Thread. Nếu được gọi từ Main Thread, app sẽ bị deadlock cứng lập tức.

---

## 5. Phân hệ Tiện ích mở rộng (Extension Subsystem)
*   **Mục tiêu (Purpose)**: Chạy các script JavaScript (VBook extension) để bóc tách thông tin sách, chương, nội dung và thực hiện TTS tùy chỉnh.
*   **API công khai (Public API)**:
    *   `ExtensionManager.shared.search(...)`
    *   `ExtensionManager.shared.detail(...)`
    *   `ExtensionManager.shared.chap(...)`
    *   `ExtensionManager.shared.install(...)`
*   **Dependencies**: `JavaScriptCore`, `ZIPFoundation`, `SwiftSoup` (qua cầu nối `JSDom`), `CryptoKit` (qua cầu nối `JSCrypto`).
*   **Owned Objects**:
    *   `ExtensionManager` tạo ra các instance ngắn hạn của `JSExecutor` để chạy script độc lập.
*   **Điểm bắt đầu (Entry Points)**: Các lời gọi bóc tách dữ liệu từ `SearchView`, `DiscoveryView`, `BookDetailView`, `ReaderViewModel`, `DownloadManager`.
*   **Điểm kết thúc (Exit Points)**: Trả về kết quả JSON đã phân tích hoặc báo lỗi exception.
*   **Vòng đời (Lifecycle)**: Khởi tạo `JSExecutor` mới -> Nạp thư viện bootstrap -> Nạp script extension -> evaluate hàm `execute` -> Giải phóng `JSExecutor`.
*   **Rủi ro đã biết (Known Risks)**:
    *   Overhead hiệu năng: Việc tạo mới `JSContext` cho mỗi lượt chạy JS rất tốn tài nguyên.

---

## 6. Phân hệ Điều hướng (Navigation Subsystem)
*   **Mục tiêu (Purpose)**: Quản lý luồng chuyển màn hình trong ứng dụng thông qua cấu trúc Tab và các Sheet hiển thị chi tiết.
*   **API công khai (Public API)**: SwiftUI state bindings.
*   **Dependencies**: `SwiftUI`.
*   **Owned Objects**: Thuộc tính điều hướng thuộc về `MainTabView`.
*   **Điểm bắt đầu (Entry Points)**: App launch (`FreeBookApp.swift`).
*   **Điểm kết thúc (Exit Points)**: App terminate.
*   **Vòng đời (Lifecycle)**: Khởi tạo `MainTabView` với các Tab chính (Kệ sách, Khám phá, Tìm kiếm, Từ điển, Cài đặt).
*   **Rủi ro đã biết (Known Risks)**:
    *   Hệ thống điều hướng dùng State lồng ghép có thể gây hiện tượng reload view không cần thiết trong SwiftUI.

---

## 7. Phân hệ Widget điều khiển (Widget Subsystem)
*   **Mục tiêu (Purpose)**: Hiển thị bảng điều khiển nổi (Floating Widget) hỗ trợ phát/dừng, tua đoạn, chỉnh tốc độ TTS từ bất kỳ màn hình nào.
*   **API công khai (Public API)**:
    *   `FloatingWidgetViewModel.shared`
*   **Dependencies**: `TTSManager`, `SwiftUI`.
*   **Owned Objects**:
    *   `TTSFloatingWidgetView` tương tác trực tiếp với `FloatingWidgetViewModel` và `TTSManager`.
*   **Điểm bắt đầu (Entry Points)**: Kích hoạt khi `TTSManager.shared.showFloatingWidget = true`.
*   **Điểm kết thúc (Exit Points)**: Ẩn widget khi tắt trình đọc hoặc nhấn nút đóng trên widget.
*   **Vòng đời (Lifecycle)**: Tồn tại đè lên trên các view khác trong `MainTabView`.
*   **Rủi ro đã biết (Known Risks)**:
    *   Rò rỉ trạng thái đồng bộ: Cần đảm bảo `isPlaying` và các thông tin sách khớp chính xác giữa `TTSManager` và UI của widget.

---

## 8. Phân hệ Cơ sở dữ liệu (SwiftData Subsystem)
*   **Mục tiêu (Purpose)**: Lưu trữ lâu dài thông tin sách, chương truyện đã tải, tiện ích mở rộng đã cài đặt và cấu hình hệ thống.
*   **API công khai (Public API)**: SwiftData `@Query` và `ModelContext`.
*   **Dependencies**: `SwiftData`.
*   **Owned Objects**: `ModelContainer` toàn cục đăng ký tại App Level.
*   **Điểm bắt đầu (Entry Points)**: Khởi chạy app (`FreeBookApp.swift`).
*   **Điểm kết thúc (Exit Points)**: Đóng app.
*   **Vòng đời (Lifecycle)**: Khởi tạo `ModelContainer` -> inject vào environment -> Các View truy vấn qua `@Query` -> Các manager cập nhật qua background contexts.
*   **Rủi ro đã biết (Known Risks)**:
    *   **Lỗi Predicate của SwiftData**: Không được dùng bộ lọc chuỗi trên Predicate. Dự án đã áp dụng quy tắc truy vấn toàn bộ rồi filter trên RAM bằng computed properties.

---

## 9. Phân hệ Dịch thuật (Translation Subsystem)
*   **Mục tiêu (Purpose)**: Dịch thuật trực tiếp nội dung truyện chữ (từ tiếng Trung sang Hán Việt/VietPhrase) phục vụ người đọc và xuất bản ebook.
*   **API công khai (Public API)**:
    *   `TranslationManager.shared.getBookDictionaries(for:)`
    *   `TranslateUtils.translateContent(_:bookId:)`
*   **Dependencies**: Các thuật toán tra cứu nhanh (`DoubleArrayTrie`, `TextDictionary`).
*   **Owned Objects**:
    *   `TranslationManager` sở hữu các thực thể từ điển nhị phân `TrieDictionary`.
*   **Điểm bắt đầu (Entry Points)**: Được gọi khi hiển thị chữ trong `ReaderTextView` (nếu bật dịch) hoặc trong tiến trình xuất file TXT.
*   **Điểm kết thúc (Exit Points)**: Trả về chuỗi văn bản đã dịch.
*   **Vòng đời (Lifecycle)**: Singleton `TranslationManager.shared` tải trước các từ điển dùng chung khi khởi chạy app -> Tải thêm từ điển riêng của truyện khi mở trình đọc.
*   **Rủi ro đã biết (Known Risks)**:
    *   Tiêu tốn bộ nhớ: Dung lượng của từ điển VietPhrase và Names rất lớn. Cần giải phóng bộ đệm `bookDicts` kịp thời bằng cách lắng nghe cảnh báo bộ nhớ.

---

## 10. Phân hệ Tìm kiếm (Search Subsystem)
*   **Mục tiêu (Purpose)**: Hỗ trợ tìm kiếm truyện trên nhiều nguồn (Extension) cùng lúc.
*   **API công khai (Public API)**: `SearchView.swift`.
*   **Dependencies**: `ExtensionManager`, SwiftData.
*   **Điểm bắt đầu (Entry Points)**: Tab Tìm kiếm trên tab bar chính.
*   **Điểm kết thúc (Exit Points)**: Người dùng chuyển tab khác.
*   **Rủi ro đã biết (Known Risks)**:
    *   Network request dồn dập khi tìm kiếm đồng thời trên nhiều nguồn: Đã được giới hạn tải từng trang và cho phép bật/tắt nguồn truyện.

---

## 11. Phân hệ Khám phá (Discovery Subsystem)
*   **Mục tiêu (Purpose)**: Duyệt các thư mục truyện, thể loại, truyện hot từ các extension.
*   **API công khai (Public API)**: `DiscoveryView.swift`.
*   **Dependencies**: `ExtensionManager`.
*   **Điểm bắt đầu (Entry Points)**: Tab Khám phá trên tab bar chính.
*   **Điểm kết thúc (Exit Points)**: Chuyển tab.
*   **Rủi ro đã biết (Known Risks)**:
    *   Xử lý bất đồng bộ khi chuyển đổi giữa các extension trong lúc đang load dữ liệu.

---

## 12. Phân hệ Kệ sách (Shelf Subsystem)
*   **Mục tiêu (Purpose)**: Quản lý danh sách sách đang đọc dở, sách yêu thích của người dùng, tích hợp điều phối việc xóa sách và dọn dẹp bộ nhớ đĩa.
*   **API công khai (Public API)**:
    *   `ShelfView.swift`
    *   `BookStorageManager.shared.removeFromShelf(_:context:)`
    *   `BookStorageManager.shared.deleteBooks(bookIds:context:)`
*   **Dependencies**: SwiftData (`Book`), `DownloadManager`, `TranslationManager`, `BookBinManager`, `ImageCacheManager`, `TTSManager`.
*   **Điểm bắt đầu (Entry Points)**: Tab đầu tiên mặc định khi mở ứng dụng.
*   **Vòng đời (Lifecycle)**: Hiển thị danh sách `@Query` sách trên kệ -> Người dùng chọn xóa sách -> Kích hoạt `BookStorageManager` xóa DB -> Lưu context -> Kích hoạt dọn dẹp file vật lý bất đồng bộ ở background thread.
*   **Rủi ro đã biết (Known Risks)**:
    *   Cập nhật tiến độ đọc chưa đồng bộ khi quay lại từ Trình đọc hoặc TTS widget.
    *   Lỗi dọn dẹp file vật lý do thread background chạy độc lập bị OS ngắt (xử lý bằng cách đẩy vào hàng đợi retry trong `UserDefaults` và drain ở khởi động ứng dụng).

---

## 13. Phân hệ Cài đặt (Settings Subsystem)
*   **Mục tiêu (Purpose)**: Cấu hình hệ thống giọng đọc, thay thế từ điển TTS, cài đặt/cập nhật tiện ích và từ điển dịch.
*   **API công khai (Public API)**: `SettingsView.swift` và các view cấu hình TTS/Search engine.
*   **Dependencies**: `TTSManager`, `TranslationManager`, `ExtensionManager`.
*   **Điểm bắt đầu (Entry Points)**: Tab Cài đặt trên tab bar chính.
*   **Rủi ro đã biết (Known Risks)**:
    *   Thay đổi giọng đọc hoặc từ điển TTS khi đang phát có thể gây lỗi nổ âm thanh hoặc treo engine (được giải quyết bằng cách pause/resume an toàn).

---

## 14. Phân hệ Quản lý Từ điển tra cứu (Dictionary Hub Subsystem)
*   **Mục tiêu (Purpose)**: Quản lý, tra cứu nghĩa từ vựng tiếng Trung, quản lý danh sách từ định nghĩa tùy chỉnh của người dùng.
*   **API công khai (Public API)**: `DictionaryHubView.swift`, `DictionaryListView.swift`.
*   **Dependencies**: `TranslationManager`, SwiftData.
*   **Điểm bắt đầu (Entry Points)**: Tab Từ điển trên tab bar chính.
*   **Rủi ro đã biết (Known Risks)**:
    *   Truy vấn danh sách định nghĩa lớn trên main thread gây trễ UI.

#### Reader/TTS unified pipeline (2026-07)

- `ChapterTextNormalizer` is the single source for LF newlines, trimmed non-empty lines, compact paragraph IDs, and UTF-16 ranges. `ChapterContentRepository` produces one normalized `ChapterDocument` for both Reader and TTS.
- Reader uses `ReaderLoadState` with bootstrap retry/clamping, typed failures, generation checks, cache-first rendering, and a short opacity crossfade only for newly fetched content. `ReaderRoute.chapterIndex` preserves the selected TOC index through navigation.
- `TTSParagraphBuilder` chunks normalized lines without renumbering parent paragraph IDs; replacement output is checked before synthesis. TTS asynchronous work is guarded by session identity and TTS owns progress while playing.
- `ReadingProgressStore` coalesces RAM snapshots in an actor and flushes from background contexts on checkpoints, dismissal, and app backgrounding. Legacy window/tab Reader, duplicate progress repository, and `TTSSession` mirror are removed.
- The TTS widget presents a compact horizontal capsule over Reader, with a circular rotating cover, play/pause, fast-forward and close actions. Its edge-peek mode preserves the same playback and placement state and expands on drag.
- The Chapter Text subsystem now includes `ChapterPersistenceStore`: shared Reader/TTS loads use RAM, background SwiftData, then extension, with coalesced in-flight work and cache-preserving TOC reconciliation.
- Extension repository management removes row swipe/toggle behavior in favor of an explicit confirmed delete action compatible with the paged tab gesture.
- `BookStorageManager` coordinates book deletion, ensuring model context changes are committed to the SQLite database before spawning background threads to delete covers and `.bin` files via `ImageCacheManager` and `BookBinManager` under a path safety sandbox validator.
- Failed physical file deletions are stored in a `UserDefaults` queue and drained at app startup through `BookStorageManager.shared.drainRetryQueue()`, up to a limit of 3 retry attempts.
- `ReaderChapterListStore` virtualizes Table of Contents row retrieval dynamically using index-based ForEach loop representation, removing lightweight row arrays from class memory entirely. It uses `BackgroundSearchWorker` actor to search SwiftData off the main thread and `BackgroundPagingWorker` actor to fetch page DTOs off the main thread, keeping search result states separate from active paging state.
- In-flight download and text export tasks support cooperative cancellation by checking `Task.isCancelled` and task state at chapter boundaries.

<!-- GENERATED END -->
