---
generated_by: Antigravity
generator_version: 1.0
generated_at: 2026-08-21T10:30:00+07:00
git_commit: UNKNOWN
source_files: 230
document_version: 6
---

# Máy Trạng thái (State Graph)

Tài liệu này phân tích chi tiết các máy trạng thái (State Machine) đang vận hành trong dự án FreeBook.

## Ghi chú thủ công (Human Notes)
*Ghi chú thủ công của con người.*

<!-- GENERATED START -->
## Trạng thái navigation của Reader: commit RAM hoãn một turn (1.3.240)

* `ReaderLoadState` không thêm case nào, nhưng **thứ tự thời gian** đổi ở đường cache-hit: trước đây `requestChapter` set `.loading(chapterIndex:)` + `pendingNavigationIndex = N` rồi gọi `commitNavigation` **đồng bộ trong cùng turn main actor**, nên `.loading` → `.ready` và `pendingNavigationIndex` N → `nil` xảy ra trước khi SwiftUI kịp present frame nào. Từ 1.3.240 commit đó chạy trong `memoryCommitTask` (`Task { @MainActor }` + `await Task.yield()`) và guard theo `navigationGeneration`, nên tồn tại đúng một frame ở trạng thái `(pending = N, .loading)`.
* Cổng render của `singleChapterReaderView` đọc đúng trạng thái đó: nhánh mới `pending != displayedChapterIndex` → `chapterInlineLoadingView(index: pending)` đặt **trước** nhánh `cache.get(presentationIndex)?.state == .loaded`. Vì `ChapterCache` thực tế không evict (`queueRelease*` không có caller) và N+1 được prefetch, chương đích gần như luôn `.loaded`; không có nhánh này thì skeleton không bao giờ được vẽ khi Next/Prev. Reload cùng chương (`pending == displayedChapterIndex`) vẫn đi nhánh cũ nên không nháy skeleton.
* `memoryCommitTask` bị cancel ở đúng ba chỗ đang cancel `navigationWorkerTask`: đầu `requestChapter`, `failBootstrap`, `shutdown(saveProgress:)`. Bấm Next/Prev liên tiếp vì vậy chỉ commit lần cuối — generation cũ bị guard chặn.
* Cờ `isRestoringReaderPosition` hết đường kẹt: nhánh thoát sớm `guard !chapter.isPositionRestored` của `restoreReaderPositionIfNeeded` nay gọi `completeReaderPositionRestore()` trước khi return. Trước đó, một chương từng restore rồi cộng với `scrollTarget` đã tiêu thụ sẽ để cờ ở `true` hết session, làm `requestTTSScrollIfNeeded` và `updateScrollReadingProgress` (cả hai mở đầu bằng `guard !isRestoringReaderPosition`) chết im lặng.

## Next-chapter prefix cache state (1.3.234)

* `TTSNextChapterPrefixCache` giữ trạng thái phẳng, không phải máy trạng thái enum như `TTSChapterPrefetcher`: `activeKey: TTSPreparedNextChapterKey?`, `chunks: [Int: PreparedChunk]` (audio + `finalText` đã đọc), `durations: [Int: Double]`, `tasks: [Int: Task<Void, Never>]`, `taskTokens: [Int: UInt64]`, `failureStates: [Int: TTSManager.RefillFailureState]`, `nextTaskToken`/`generation: UInt64`.
* `durations` được ghi cùng lúc với `chunks` (qua `WAVEncoder.duration`) và là dữ liệu duy nhất mà watermark cached-time của NghiTTS đọc: `contiguousDuration(matching:from:)` cộng dồn chuỗi index liên tục và dừng ở khe trống đầu tiên; key không trùng trả `0`. Với Google/Ext, `WAVEncoder.duration` trả `0` cho MP3 nên trường này vô hại (không consumer nào dùng).
* Chuyển trạng thái:
  - `request(key:…)` với key khác `activeKey` → `reset()` rồi nhận key mới. Cùng key → `trim(toCapacity:)` rồi mở task cho các index còn thiếu trong `1..<min(paragraphs.count, capacity + 1)`.
  - `capacity == 0` (giữa chương với Google/Ext, hoặc chương hiện tại còn ứng viên optional-reserve với Nghi) → `trim(toCapacity: 0)` thu hồi toàn bộ, không mở task mới.
  - Nghi khi `cachedTime >= nghittsSafeCachedTimeThreshold` → **không gọi `request` nữa**, nên không thu hồi và cũng không nạp thêm: state đóng băng cho tới sự kiện kế tiếp.
  - Task xong → `finishSynthesis` ghi vào `chunks` **chỉ khi** `generation`, `activeKey` và `taskTokens[index]` còn khớp; thành công thì xóa `failureStates[index]`.
  - Lỗi → `TTSManager.evaluateRefillError(maxAttempts: 2)` quyết định `failureStates[index]`: `.blocked` (non-retryable / hết attempt / audio rỗng) khiến index bị bỏ qua ở mọi `request` tiếp theo; `.retryScheduled` chỉ tăng attempt và để lần đánh giá cửa sổ sau thử lại; `.cancelled` không đổi state.
  - `cancelPendingWork()` (pause) tăng `generation`, hủy `tasks`, **giữ** `chunks`.
  - `reset()` / `consume(matching:)` tăng `generation`, hủy `tasks`, xóa `chunks`, bỏ `activeKey`.
* Ba lớp chống ghi trễ: `generation` (toàn cục), `activeKey` (chương/cấu hình) và `taskTokens[index]` (đúng task của index). `failureStates` dùng lại kiểu `TTSManager.RefillFailureState` của `nghiRefillFailureStates` nhưng khoá theo index và có vòng đời bằng `activeKey`.
* Trạng thái này độc lập với `TTSNextChapterState`; hai bên chỉ giao nhau ở điều kiện đọc (`.synthesizingAudio`/`.audioReady`) và ở thời điểm `applyNextChapter` tiêu thụ cả hai.

## Sơ Đồ Quản Lý Trạng Thái & Sự Kiện (State Graph v4.1/v5.0)

1. **Luồng Sự Kiện Presentation Bất Đồng Bộ**:
   `Services` (`TTSManager`, `DownloadManager`)
     └── Phát event -> `AsyncStream.Continuation`
           └── `AppLaunchRootView` (`AsyncStream` Consumer)
                 └── `@State` Toast presentation trong UI root context

2. **Trạng Thái Giao Dịch Dữ Liệu Khách (Coordinator Ownership)**:
   - Client Action (UI Event) -> Khởi tạo Command DTO bất biến -> Chuyển giao cho Coordinator (`BookTransactionCoordinator` / `ExtensionTransactionCoordinator`).
   - Coordinator thực hiện fetch/validate/mutate/save trên `ModelContext` -> Trả về `Result<T, Error>`.
   - View nhận `Result`: Hiển thị thành công hoặc cập nhật `@State errorMessage` mà không bao giờ thay đổi trực tiếp đối tượng `@Model`.

3. **Máy trạng thái lỗi NghiTTS refill (1.3.147)**:
   - `idle` -> tổng hợp prefetch -> `success`: xóa failure state và tiếp tục cập nhật cửa sổ đệm.
   - Lỗi tạm thời lần đầu -> `retryScheduled(attempt: 1)`: khóa scheduler, chờ 1 giây, xác thực session/chapter/generation rồi thử lại.
   - Lỗi tạm thời lần hai hoặc lỗi không retry -> `blocked`: bỏ qua paragraph index đó trong các lần chọn prefetch tiếp theo.
   - `CancellationError`, stop, đổi session hoặc chuyển chương -> `cancelled/reset`: hủy retry task và xóa toàn bộ state liên quan, không ghi lại state từ task cũ.
<!-- GENERATED END -->
