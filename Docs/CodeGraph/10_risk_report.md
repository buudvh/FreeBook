---
generated_by: Antigravity
generator_version: 1.0
generated_at: 2026-07-14T09:15:00+07:00
git_commit: UNKNOWN
source_files: 87
document_version: 1
---

# Báo cáo Rủi ro Kỹ thuật (Technical Risk Report)

Tài liệu này báo cáo chi tiết các rủi ro kỹ thuật tiềm ẩn hoặc hiện hữu được phát hiện trong mã nguồn dự án FreeBook, phân loại theo mức độ nghiêm trọng (Severity) và khả năng xảy ra (Likelihood), đi kèm với nguyên nhân và giải pháp khắc phục.

## Ghi chú thủ công (Human Notes)
*Ghi chú thủ công của con người.*

<!-- GENERATED START -->
## Reader risks mitigated in 1.3.10

* **Mitigated - stale rendered window:** the vertical reader now advances `stableIndexes` together with the active chapter window, preventing a permanent stop at the initial `n+2` boundary.
* **Mitigated - cancellation-insensitive extension fetches:** canceled tasks remain active until completion, and `ReaderPrefetchGate` enforces one global two-request cap across Reader instances. Requests from a dismissed Reader therefore cannot overlap an unbounded new batch after Discovery -> Read Now navigation.
* **Mitigated - hidden overlay work:** chapter-list queries and eager full-list title translation no longer run throughout ordinary reading and TTS updates. TTS full-queue metadata refresh is owned by `TTSManager` and uses background SwiftData for local books.
* **Mitigated - large TOC jump latency:** opening the chapter list positions directly at the current row without animating through all preceding chapters and reuses Reader-owned SwiftData objects.
* **Mitigated - shelf/discovery tab swipe jank:** Shelf rows no longer scan chapter relationships while rendering, and Discovery keeps only the selected category page plus adjacent pages fully mounted during horizontal paging.
* **Mitigated - anti-bot request burst:** a jump loads only its target; speculative next-chapter loading waits for target completion and a stable selection. Rapid updates coalesce pending chapters.

## 1. Bảng Tổng hợp Rủi ro (Risk Summary Table)

| ID | Loại Rủi ro | Vị trí (Source File) | Severity | Likelihood | Related Documents |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **R-01** | **Deadlock cứng hệ thống** | [JSExecutor.swift](../../Sources/Services/Extensions/Engine/JSExecutor.swift#L442-L458) | **Critical** | **Medium** | [13_resource_lifecycle.md](13_resource_lifecycle.md), [11_subsystems.md](11_subsystems.md) |
| **R-02** | **Rò rỉ tài nguyên ngầm** | [JSExecutor.swift](../../Sources/Services/Extensions/Engine/JSExecutor.swift#L9) | **High** | **High** | [12_ownership_graph.md](12_ownership_graph.md), [13_resource_lifecycle.md](13_resource_lifecycle.md) |
| **R-03** | **Lỗi Concurrency SwiftData** | Các ViewModel & Manager | **High** | **Medium** | [09_dependency_rules.md](09_dependency_rules.md), [13_resource_lifecycle.md](13_resource_lifecycle.md) |
| **R-04** | **Lỗi hồi phục AVAudioSession** | [TTSManager.swift](../../Sources/Services/TTS/TTSManager.swift#L1458) | **Medium** | **Medium** | [13_resource_lifecycle.md](13_resource_lifecycle.md), [11_subsystems.md](11_subsystems.md) |
| **R-05** | **Strong Reference Cycle trong Audio** | [TTSManager.swift](../../Sources/Services/TTS/TTSManager.swift#L986-L999) | **Medium** | **Low** | [12_ownership_graph.md](12_ownership_graph.md), [04_call_graph.md](04_call_graph.md) |
| **R-06** | **Rò rỉ subscription cảnh báo** | [ReaderViewModel.swift](../../Sources/Views/Reader/ReaderViewModel.swift#L115) | **Low** | **Low** | [08_lifecycle.md](08_lifecycle.md) |
| **R-07** | **Race Condition xử lý nền TTS** | [TTSBackgroundProcessor.swift](../../Sources/Services/TTS/TTSBackgroundProcessor.swift#L13) | **Medium** | **Low** | [05_state_graph.md](05_state_graph.md), [07_dataflow.md](07_dataflow.md) |

---

## 2. Chi tiết các Rủi ro kỹ thuật

### R-01: Nguy cơ Deadlock hệ thống khi khởi chạy Trình duyệt ngầm
*   **Vị trí**: [JSExecutor.swift](../../Sources/Services/Extensions/Engine/JSExecutor.swift#L442-L458) bên trong `browserLaunchBlock`.
*   **Mức độ nghiêm trọng (Severity)**: **Critical** (Khiến ứng dụng bị đóng băng hoàn toàn và bị hệ điều hành iOS kill sau vài giây).
*   **Khả năng xảy ra (Likelihood)**: **Medium** (Xảy ra bất cứ khi nào mã JavaScript của Extension gọi phương thức `Engine.newBrowser().launch(...)` trên Main Thread).
*   **Nguyên nhân**:
    *   `browserLaunchBlock` sử dụng `DispatchSemaphore` để chặn luồng hiện tại và chờ kết quả tải trang HTML.
    *   Đồng thời, nó đẩy tác vụ tải trang WebView lên Main Thread bằng `DispatchQueue.main.async`.
    *   Nếu bản thân khối `browserLaunchBlock` được gọi từ Main Thread, Main Thread sẽ bị Semaphore khóa cứng. Khi đó, khối load WebView trong `DispatchQueue.main.async` không bao giờ được thực thi, dẫn đến hiện tượng **Deadlock vĩnh viễn**.
*   **Giải pháp (Mitigation)**:
    *   Không được dùng `DispatchQueue.main.async` kết hợp chặn đồng bộ bằng Semaphore.
    *   Chuyển hoàn toàn việc tương tác này sang cơ chế `async/await` phi chặn (non-blocking) bằng cách chạy JS Engine trên một background thread chuyên biệt hoặc sử dụng `withCheckedContinuation` không dùng Semaphore.

---

### R-02: Rò rỉ bộ nhớ WKWebView (Resource Leak) do JavaScript crash
*   **Vị trí**: Từ điển `activeBrowsers` trong [JSExecutor.swift](../../Sources/Services/Extensions/Engine/JSExecutor.swift#L9).
*   **Mức độ nghiêm trọng (Severity)**: **High** (WKWebView tiêu tốn rất nhiều tài nguyên RAM, gây crash app do cạn bộ nhớ - Out Of Memory).
*   **Khả năng xảy ra (Likelihood)**: **High** (Do các Extension JS của bên thứ ba viết thường phát sinh lỗi ngoại lệ hoặc crash giữa chừng và không gọi hàm `close()`).
*   **Nguyên nhân**:
    *   Khi JS khởi tạo browser qua `Engine.newBrowser()`, một `WebViewLoader` được lưu vào từ điển `activeBrowsers`.
    *   Nếu đoạn mã JavaScript gặp lỗi giữa chừng và dừng thực thi trước khi gọi `browser.close()`, phần tử trong `activeBrowsers` sẽ không bao giờ được xóa, khiến thực thể `WKWebView` bị treo vĩnh viễn trong RAM.
*   **Giải pháp (Mitigation)**:
    *   Bổ sung cơ chế tự hủy (Timeout) cho `WebViewLoader`. Nếu sau một khoảng thời gian (ví dụ: 60 giây) không có hoạt động, tự động đóng và giải phóng WebView.
    *   Đảm bảo giải phóng toàn bộ `activeBrowsers` trong hàm `deinit` của `JSExecutor`.

---

### R-03: Tranh chấp dữ liệu (Data Race) & Lỗi Context của SwiftData
*   **Vị trí**: Tiến trình ghi đĩa đồng thời trong `DownloadManager` và `ReaderViewModel`.
*   **Mức độ nghiêm trọng (Severity)**: **High** (Gây crash ứng dụng khi ghi đĩa hoặc đọc thực thể từ thread sai).
*   **Khả năng xảy ra (Likelihood)**: **Medium**.
*   **Nguyên nhân**:
    *   SwiftData yêu cầu các thực thể `@Model` (như `Book`, `Chapter`) chỉ được truy cập trên đúng luồng của `ModelContext` đã fetch chúng.
    *   Nếu background thread của `DownloadManager` tải truyện xong và lưu vào DB, nhưng Main Thread cùng lúc đang đọc để hiển thị, hoặc nếu ta truyền thực thể `@Model` qua lại giữa các luồng, SwiftData sẽ ném ngoại lệ crash.
*   **Giải pháp (Mitigation)**:
    *   Luôn tạo `ModelContext` riêng cho background thread.
    *   Khi cần truyền thực thể, chỉ truyền `bookId` hoặc `chapterId` (PersistentIdentifier) và fetch lại trên thread đích, tuyệt đối không truyền instance thực thể.

---

### R-04: Thất bại khi kích hoạt lại AVAudioSession sau cuộc gọi (Interruption)
*   **Vị trí**: Lắng nghe sự kiện ngắt tại [TTSManager.swift](../../Sources/Services/TTS/TTSManager.swift#L1458).
*   **Mức độ nghiêm trọng (Severity)**: **Medium** (Giao diện hiển thị đang phát nhưng không có tiếng ra loa).
*   **Khả năng xảy ra (Likelihood)**: **Medium** (Phổ biến khi người dùng nghe truyện bằng tai nghe Bluetooth và nhận cuộc gọi).
*   **Nguyên nhân**:
    *   Khi cuộc gọi kết thúc, hệ thống gửi thông báo kết thúc ngắt (`.ended`). Tuy nhiên, tại thời điểm này, hệ điều hành iOS có thể chưa hoàn toàn trả lại tài nguyên âm thanh.
    *   Việc gọi ngay lập tức `AVAudioSession.sharedInstance().setActive(true)` có thể thất bại, khiến AudioEngine không thể start lại.
*   **Giải pháp (Mitigation)**:
    *   Thực hiện thử lại (Retry) với độ trễ ngắn (ví dụ: trì hoãn 0.5 giây trước khi setActive lại).
    *   Kiểm tra kỹ kết quả trả về của hàm `setActive`.

---

### R-05: Strong Reference Cycle trong AVAudioPlayerNode completionHandler
*   **Vị trí**: Khối lập lịch phát [TTSManager.swift](../../Sources/Services/TTS/TTSManager.swift#L986-L999).
*   **Mức độ nghiêm trọng (Severity)**: **Medium** (Rò rỉ bộ nhớ của TTSManager).
*   **Khả năng xảy ra (Likelihood)**: **Low** (Do đã được giảm thiểu).
*   **Nguyên nhân**:
    *   Completion handler của `player.scheduleBuffer` chạy trên thread nền của AudioEngine.
    *   Mặc dù closure ngoài dùng `[weak self]`, nhưng bên trong có gọi `DispatchQueue.main.async` mà không capture `[weak self]` lần nữa, có thể vô tình giữ chặt `self` trong hàng đợi Main Queue nếu ViewModel bị hủy trước đó.
*   **Giải pháp (Mitigation)**:
    *   Đảm bảo capture `[weak self]` ở cả block `DispatchQueue.main.async` lồng bên trong.

### R-07: Race Condition khi xử lý chuẩn hóa và dịch văn bản chạy nền
*   **Vị trí**: [TTSBackgroundProcessor.swift](../../Sources/Services/TTS/TTSBackgroundProcessor.swift#L13), [TTSManager.swift](../../Sources/Services/TTS/TTSManager.swift#L318)
*   **Mức độ nghiêm trọng (Severity)**: **Medium** (Có thể phát sai chương hoặc lỗi hiển thị).
*   **Khả năng xảy ra (Likelihood)**: **Low** (Do đã được giảm thiểu).
*   **Nguyên nhân**:
    *   Các tác vụ CPU-heavy (dịch Vietphrase, tách đoạn) được đẩy xuống actor chạy nền `TTSBackgroundProcessor` bất đồng bộ.
    *   Prewarm và thao tác Start có thể chồng lấp nếu người dùng bấm phát đúng lúc Reader đang chuẩn bị nội dung.
    *   Tác vụ cũ hoàn thành trễ hơn có thể đè đè dữ liệu mới nếu không được kiểm tra.
*   **Giải pháp (Mitigation)**:
    *   Mỗi request dùng một processor riêng thay vì chờ hàng đợi actor singleton; task cũ được hủy và processor kiểm tra cancellation giữa các giai đoạn.
    *   Cache prewarm có key gồm sách, chương, nội dung, chunk length và cấu hình tiêu đề; kết quả stale bị loại bằng generation/session guard.

---

#### Reader/TTS unified pipeline (2026-07)

- `ChapterTextNormalizer` is the single source for LF newlines, trimmed non-empty lines, compact paragraph IDs, and UTF-16 ranges. `ChapterContentRepository` produces one normalized `ChapterDocument` for both Reader and TTS.
- Reader uses `ReaderLoadState` with bootstrap retry/clamping, typed failures, generation checks, cache-first rendering, and a short opacity crossfade only for newly fetched content. `ReaderRoute.chapterIndex` preserves the selected TOC index through navigation.
- `TTSParagraphBuilder` chunks normalized lines without renumbering parent paragraph IDs; replacement output is checked before synthesis. TTS asynchronous work is guarded by session identity and TTS owns progress while playing.
- `ReadingProgressStore` coalesces RAM snapshots in an actor and flushes from background contexts on checkpoints, dismissal, and app backgrounding. Legacy window/tab Reader, duplicate progress repository, and `TTSSession` mirror are removed.

<!-- GENERATED END -->
