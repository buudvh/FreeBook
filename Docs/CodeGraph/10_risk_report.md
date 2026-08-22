---
generated_by: Antigravity
generator_version: 1.0
generated_at: 2026-08-21T10:30:00+07:00
git_commit: UNKNOWN
source_files: 230
document_version: 4
---

# Báo cáo Rủi ro Kỹ thuật (Technical Risk Report)

Tài liệu này báo cáo chi tiết các rủi ro kỹ thuật tiềm ẩn hoặc hiện hữu được phát hiện trong mã nguồn dự án FreeBook, phân loại theo mức độ nghiêm trọng (Severity) và khả năng xảy ra (Likelihood), đi kèm với nguyên nhân và giải pháp khắc phục.

## Ghi chú thủ công (Human Notes)
*Ghi chú thủ công của con người.*

<!-- GENERATED START -->
## Rủi ro của cổng bắt tay skeleton (1.3.242)

* **Chưa biên dịch**: viết trên Windows, không có `xcodebuild`. Hai cổng tĩnh giữ nguyên (`check_architecture.py`: đúng 18 violation cũ; `validate_links.py`: PASS). CI xanh chỉ chứng minh *biên dịch được*.
* **Nguy cơ treo cổng nếu `onAppear` của skeleton không nổ**: cổng chỉ mở khi `skeletonHandshakeIndex == N`. Nếu skeleton đang hiển thị mà người dùng bấm tiếp sang chương khác, SwiftUI sẽ **không** chạy lại `onAppear` cho cùng một view — vì vậy nhánh skeleton mang `.id("chapter-skeleton-\(presentationIndex)")` để đổi chương là đổi identity. Đây là mắt yếu nhất của thiết kế: bỏ `.id` đó là mở lại đường treo ở chương cũ.
* **Thêm một frame trễ**: mỗi lượt đổi chương nay tốn thêm đúng một update pass (~16 ms) cho skeleton, cộng với nhịp 32 ms sẵn có. Đánh đổi có chủ ý: đổi tổng thời gian dài hơn một chút để lấy phản hồi tức thì.
* **Chỉ chữa cảm giác đơ, không chữa nguyên nhân của pass gộp**: chưa xác định được vì sao một pass vừa tháo vừa dựng hai subtree TextKit-1 lại tốn 1.6–3.5 s (giả thuyết: hai cây `UITextView` cùng sống trong một transition `.opacity` bọc bởi `withAnimation(.easeOut(0.12))`, cùng `contentSizeInvalidation=174`/`sizeInvalidationRPM=498.6` trong `[ReaderEnergy] Summary`). 1.3.242 chỉ bảo đảm pass gộp đó không còn xảy ra. `prediction=reader_layout_churn_likely` vẫn đúng và vẫn chưa xử lý.
* **Không đụng prefetch khi TTS sở hữu sách**: `setSpeculativePrefetchEnabled(false)` vẫn tắt N+1 của Reader, nên lượt tải lạnh thật (log có `RepoLoad origin=extensionFetch ms=2041`) vẫn dài như trước — chỉ khác là có skeleton suốt thời gian đó.

## Rủi ro còn lại sau lần sửa hạ cánh hai pha (1.3.241)

* **Chưa biên dịch**: thay đổi 1.3.241 viết trên Windows, không có `xcodebuild`. Chỉ hai cổng tĩnh chạy được (`check_architecture.py` giữ đúng 18 violation cũ, `validate_links.py`). CI xanh cũng chỉ chứng minh *biên dịch được*.
* **Giả định về timer 0.15 s**: pha hai (cuộn tới đoạn TTS) dựa vào việc `DispatchQueue.main.asyncAfter` không thể nổ khi main thread còn bận, nên nó luôn chạy *sau* khi chương đã present. Nếu một lượt dựng chương nào đó dài hơn và `onAppear` chưa kịp tiêu thụ target đầu chương, target sâu sẽ ghi đè và neo sâu lại được giải trong cùng layout pass — đúng hành vi cũ, không tệ hơn, nhưng cũng không được lợi.
* **Cửa sổ nhả cờ chồng nhau**: cú cuộn pha một hẹn nhả `isRestoringReaderPosition` sau 0.25 s, pha hai đặt lại cờ ở 0.15 s rồi hẹn nhả tiếp. Có ~0.1 s cờ bị nhả sớm giữa hai cú cuộn; hệ quả xấu nhất là một tick auto-scroll TTS trỏ đúng vào đoạn đang được cuộn tới, tức vô hại.
* **Chi phí cố định 32 ms/lượt điều hướng** (nhịp chờ frame) — đánh đổi lấy việc skeleton chắc chắn được present.
* **Không sửa nguyên nhân thời gian tải thật**: khi TTS sở hữu sách, `setSpeculativePrefetchEnabled(false)` tắt prefetch N+1 của Reader, nên Next/Prev lúc đang phát gần như luôn đi đường worker qua `ChapterContentRepository` (actor dùng chung với TTS). 1.3.241 làm chờ đợi đó *có phản hồi* (skeleton), **không** làm nó ngắn hơn. Nới điều kiện prefetch khi đang phát là quyết định năng lượng, chưa làm.

## Rủi ro của lần sửa đơ Next/Prev khi TTS đang phát (1.3.240)

* **Đã sửa, là bug thật chứ không phải tối ưu**: `restoreReaderPositionIfNeeded` thoát sớm mà không nhả `isRestoringReaderPosition`, khiến auto-scroll TTS và lưu tiến độ theo cuộn có thể chết im lặng tới hết session. Dạng lỗi không log, không crash, chỉ "tự nhiên không chạy nữa".
* **Rủi ro mới, mức thấp**: nay có thêm một frame skeleton chen giữa mọi lượt Next/Prev, kể cả khi nội dung đã ở RAM. Khi người dùng bấm rất nhanh, mỗi cú bấm huỷ `memoryCommitTask` trước đó nên chỉ chương cuối được commit — hành vi này dựa vào guard `request.generation == navigationGeneration`; sai guard là quay lại cảnh commit chồng.
* **Rủi ro còn nguyên, chỉ được đo chứ chưa sửa**: `ChapterContentRepository.shared` là một actor dùng chung giữa Reader và TTS, nên khi chương đích chưa cache, `load` của Reader có thể xếp hàng sau một lượt fetch chương của TTS. Log `[ReaderPerf] RepoLoad` thêm vào để lượng hoá đúng đường này; đường đó **có** skeleton nên nó không phải triệu chứng đang báo.
* **Không đo được tại chỗ**: host là Windows, `xcodebuild` chỉ chạy trên macOS. Mọi kết luận ở trên là đọc code cộng `check_architecture.py` (giữ đúng 18 violation, tập vi phạm y hệt), không phải profiling.

## Rủi ro của phép tách file (1.3.236)

| Rủi ro | Severity | Likelihood | Ghi chú |
|---|---|---|---|
| Type `private` rời file gốc làm rộng phạm vi truy cập ngoài dự kiến | Low | — | Chỉ 2 trường hợp (`SizeReader`, `BookTitleTranslationBackfill`), cả hai lên internal (trong module) chứ không public. Không có consumer mới nào được thêm. |
| Tách sai biên khối làm mất/nhân đôi code | High | **Low** | Cắt bằng brace-matching có bỏ qua string/comment, sau đó đối chiếu cân bằng ngoặc của 10 file gốc với `HEAD`: giống nhau tuyệt đối. 14 file mới đều cân bằng 0. |
| Line-ending sai ở file mới | Medium | — | **Đã xảy ra và đã sửa**: lần ghi đầu dùng `newline=CRLF` trên nội dung vốn đã CRLF nên thành `\r\r\n`, khiến gate đọc `TabbedVisibleBrowserViewController.swift` thành 402 dòng (gấp đôi 201). Đã chuẩn hoá toàn bộ 14 file về LF cho khớp phần còn lại của repo. |
| Còn 16 `LINE_LIMIT_EXCEEDED` chưa xử lý | Medium | — | Không giải được bằng tách type (các file này chỉ có 1 type); cần tách **thành viên** sang file `X+Feature.swift`. Nợ lớn nhất: `TTSManager.swift` (4003, cần ≤3470), `JSExecutor.swift` (1514, cần ≤1066), `ReaderView.swift` (2250, cần ≤2053). |
| 2 `VIEW_SWIFTDATA_MUTATION` thật vẫn còn | Medium | — | `DiscoveryView.swift`, `ReaderView.swift`. Sửa đúng cách phải chuyển ghi qua `BookTransactionCoordinator`/`ExtensionTransactionCoordinator` — đổi quyền sở hữu transaction, không phải dọn dẹp cơ học, nên tách thành quyết định riêng. |
| Chưa biên dịch cục bộ | Medium | — | Máy Windows; xác minh compile dựa vào CI trên macOS. 14 file mới + 10 file sửa đều chưa qua compiler tại thời điểm commit. |

## Rủi ro của lần dọn code chết (1.3.235)

| Rủi ro | Severity | Likelihood | Ghi chú |
|---|---|---|---|
| Xoá symbol mà một đường gọi động (JS bridge, `#selector`, delegate) vẫn cần | High | Low | Đã loại trừ có phương pháp: bỏ qua toàn bộ `Services/Extensions/Engine/JS*` (API mà extension JavaScript gọi theo tên), bỏ qua conformance delegate, và đếm tham chiếu theo **tên trần** nên hàm truyền dạng closure/`#selector` vẫn được tính. Đã kiểm tra không symbol nào là protocol requirement. |
| Mất vĩnh viễn 20 file test | Medium | — | Xoá bằng `git rm` nên phục hồi được từ git history; đây là quyết định trực tiếp của người dùng, không phải suy đoán. |
| Còn code chết dây chuyền sau khi xoá | Low | Low | Đã quét lại sau khi dọn: 0 hàm `public`/`internal` không tham chiếu (đợt hai đã xoá thêm `ModelStore.readCachedVoices`/`writeCachedVoices`/`voicesCacheURL` vốn chỉ phục vụ hàm vừa xoá). Type duy nhất còn báo là `FreeBookApp` (`@main`, false positive). |
| Chưa kiểm chứng bằng biên dịch | **High** | — | Đây là lần thay đổi rộng nhất (5 file xoá, 1 đổi tên, ~30 symbol, 20 file source đụng tới) và vẫn **chưa build được** vì máy là Windows. Bắt buộc `xcodegen generate` + build trên macOS trước khi coi là xong. |

## Next-chapter prefix audio risks (1.3.234)

| Rủi ro | Severity | Likelihood | Ghi chú |
|---|---|---|---|
| Lệch index giữa chunk prefix và `paragraphs` ⇒ audio và highlight desync | High | **Very Low** | Chặn hai lớp: `consume(matching:)` yêu cầu key trùng tuyệt đối, **và** `mergeNextChapterPrefixAudio` so `PreparedChunk.finalText` với `applyReplacements(paragraphs[index].text)`. Không khớp ⇒ **bỏ** chunk (log `textMismatch=M`) chứ không bao giờ phát sai đoạn. Lớp thứ hai phủ cả trường hợp DTO bị dựng lại với key không đổi (fallback load / force-refresh nội dung chương kế). |
| Tổng hợp đầu cơ tốn request/pin khi người dùng dừng ngay sau đó | Medium | Medium | Prefix luôn ở mức ưu tiên thấp nhất, tuần tự 1 operation; `pause()` hủy phần đang bay, `stop` giải phóng toàn bộ. Với `googlePrefetchCount` lớn (tối đa 10), capacity ở chunk cuối chương có thể lên tới `count - 1` request. |
| Chunk prefix cũ lưu lại sau khi đổi `pitch` của Google (đường `pitch.didSet` không gọi `clearPrefetchCache`) | Low | Medium | Chỉ là RAM tạm (tối đa `count - 1` payload); dữ liệu bị loại ở `request` kế tiếp hoặc `consume` do key khác. Không có nguy cơ phát sai pitch. |
| NghiTTS đếm payload thiên về bảo thủ (`preloadedData.count + hasPreparedNext + reservesNghiAudioSlot`) nên có thể đếm trùng một payload và cấp capacity nhỏ hơn thực tế | Low | Medium | Cố ý: sai theo chiều **không vượt** `maxTotalAudioPayloads = 5`. Hệ quả xấu nhất là prefix ít hơn 1 chunk ở một vài nhịp; watermark tự đánh giá lại ở sự kiện kế tiếp. |
| Watermark 8s có thể vẫn không đạt nếu trần 5 payload hết chỗ (chunk quá ngắn) | Low | Low | Đây là giới hạn thiết kế đã chọn (không nới trần RAM). Muốn đảm bảo đủ 8s trong mọi trường hợp thì phải nâng `NghiSynthesisPolicy.maxTotalAudioPayloads` — là thay đổi quy chuẩn, cần quyết định riêng. |
| Prefix của NghiTTS xếp hàng nhiều task cùng lúc (tối đa `capacity`), khác `canScheduleNghiRefill` "một refill in-flight" của cửa sổ đoạn văn | Low | Medium | **Sai lệch có chủ ý**: `PiperSynthesisCoordinator` vẫn chỉ chạy 1 inference tại một thời điểm và prefix ở mức `.optionalReserve` (thấp nhất), nên đây là độ sâu hàng đợi chứ không phải song song hoá. Đổi sang 1-in-flight sẽ khiến buffer chỉ lấp được 1 chunk mỗi nhịp chuyển đoạn — quá chậm ở 1-2 chunk cuối chương. |
| `sessionID`/`ttsProcessingGeneration` không nằm trong identity của prefix (chỉ có `TTSPreparedNextChapterKey`) | Low | Low | **Tính chất dùng chung với `TTSChapterPrefetcher`** (chunk 0 cũng vậy) nên không phải sai lệch riêng của thay đổi này. Cùng book/chapter/url/cấu hình ⇒ audio giống nhau, và `stopPlayback`/đổi engine/đổi giọng đều đi qua `clearAllTTSCaches`. Muốn siết thì phải siết cả hai owner cùng lúc — chưa làm. |
| Chưa kiểm chứng bằng biên dịch | Medium | — | Thay đổi được viết trên Windows; `xcodebuild` chỉ chạy trên macOS. Cần build + kịch bản nghe qua biên chương trên máy thật trước khi coi là đã xác minh. |

## Search-history live-suggestion risks (1.3.191)

* **Residual - UI only, no logic change:** the live-filtered history suggestions reuse the existing history row UI in `ShelfSearchView`/`SearchView`; no shared-store or search logic changed, so risk is limited to layout. In `ShelfSearchView` the suggestion block is capped at 220pt to avoid starving the results list height.
* **Residual - Windows cannot build/test at the moment; iOS build and XCTest verification happens via CI or a Mac.**

## Shelf search & title-translation backfill/refresh risks (1.3.190)

* **Mitigated - stale/empty translated names:** `Book.titleTrans`/`authorTrans` are backfilled at app launch once dictionaries are loaded and refreshed every time a book is opened (`ReaderView` bootstrap and `BookDetailView` `.task`); per-session additions and dictionary/custom-dict changes reach the DB without waiting for the next launch, and refresh only writes when the value changes (no redundant save churn).
* **Residual - dictionaries not ready at launch:** `runIfNeeded` guards on `TranslationManager.shared.isVietPhraseLoaded` and skips silently when dictionaries are not yet loaded; the refresh-on-open path covers those books when first opened, and the backfill retries on the next launch.
* **Residual - Windows cannot build/test at the moment; iOS build and XCTest verification happens via CI or a Mac.**

## removeDuplicatedTitle config risks mitigated in 1.3.189

* **Mitigated - Reader/TTS drift on duplicated chapter title:** per-book toggle `removeDuplicatedTitle_<bookId>` (default ON, shared by Reader + TTS) drops the first content line only when it matches an active TOC rule via the same `TranslateUtils.isChapterHeaderLine` used by TXT import; both sides keep the same stable line IDs after the drop so highlight/TTS sync stays aligned.
* **Residual - detection depends on active TOC rules:** if no TOC rule matches (or rules are disabled), the duplicated title is kept; the toggle is a display convenience, not a guaranteed dedupe.
* **Residual - Windows cannot build/test at the moment; iOS build and XCTest verification happens via CI or a Mac.**

## AVAudioSession -50 (BadParam) resolved in 1.3.180

* **Resolved - invalid category/option combination:** `TTSAudioSessionController.configureAudioSession()` called `setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .allowBluetooth, .allowBluetoothA2DP])`. `.allowBluetooth` (HFP) is documented valid only with `.record`/`.playAndRecord`/`.multiRoute`, so `setCategory` threw `OSStatus -50` (`AVAudioSessionErrorCodeBadParam`). The subsequent `setActive(true)` in the same `do` block never ran, `isAudioSessionConfigured` stayed `false`, and the error was re-logged on every paragraph/chapter play (observed during Google TTS auto-advance to chapter 2).
* **Fix:** removed `.allowBluetooth`, keeping `.duckOthers` + `.allowBluetoothA2DP` (both valid with `.playback`). The log now also records the underlying OSStatus code for future diagnosis.
* **Residual:** playback still worked while the bug existed because `AVAudioPlayer.play()` implicitly activates the session, but the intended `.playback`/`.spokenAudio` configuration (background playback, ducking, Bluetooth A2DP routing) was not applied.

## NghiTTS chapter-transition crash risks mitigated in 1.3.147

* **Mitigated - empty preprocessor output:** Piper kiểm tra cả input và output tiền xử lý; output không thể đọc được chuyển thành WAV khoảng lặng hợp lệ thay vì làm eSpeak/ONNX ném lỗi.
* **Mitigated - refill failure feedback loop:** failure state được khóa theo session/chapter/paragraph, tối đa hai attempt và cooldown 1 giây; scheduler không thể thử lại sớm qua callback khác.
* **Mitigated - stale cancellation state:** cancellation tách khỏi generic failure path, context/generation được kiểm tra trước mutation và reset hủy retry task nên task cũ không thể hồi sinh state đã xóa.
* **Residual risk:** Windows chỉ xác nhận parser/static checks; iOS build và XCTest đầy đủ vẫn cần macOS/Xcode hoặc CI trước khi phát hành.

## NghiTTS safeCachedTimeThreshold prefetch risks mitigated in 1.3.141

* **Mitigated - cancel/re-synthesize feedback loop:** `PiperSynthesisCoordinator` deduplicates exact `synthesisKey` requests and appends waiters. Detaching one waiter or pausing does not cancel an active ONNX inference.
* **Mitigated - non-contiguous cache undercount:** `calculateNghiCachedTime()` measures contiguous playable duration stopping at the first missing gap, preventing excess synthesis while correctly accounting for prepared $N+1$ items.
* **Mitigated - Settings resume work loss:** opening/closing Settings with snapshot equality (`onlyThresholdChanged = true`) resumes playback without stopping or clearing valid preloaded audio.
* **Mitigated - thermal prefetch cancellation:** thermal state remains diagnostic/logging telemetry only and does not cancel audio refills.

## Chapter memory and obsolete-work risks mitigated in 1.3.114

* **Mitigated - app-lifetime normalized chapter growth:** shared repository RAM is bounded by both 12 entries and 12 MiB estimated cost, with immediate memory-warning trimming and oversized-document bypass.
* **Mitigated - cancellation-insensitive shared waiters:** Reader/TTS retain per-consumer continuations. Canceling one no longer blocks that caller until unrelated shared work completes, while final-subscriber cancellation reaches the extension task.
* **Mitigated - orphaned fallback auto-advance:** TTS now owns and generation-guards the load/process task; stop/session replacement/newer advance cancels it and cancellation cannot be misreported as a fatal playback load error.

## TTS foreground energy risks mitigated in 1.3.112

* **Mitigated - widget display-rate work:** the global floating cover no longer drives a 30 FPS SwiftUI timeline while playback continues across Reader/Discovery/Shelf.
* **Mitigated - broad TTS view invalidation:** app root, Shelf, widget, and Reader no longer observe every published manager field. Deduplicated projections suppress unrelated paragraph/highlight/download/timer updates; another book's highlights cannot invalidate the visible Reader.
* **Mitigated - repeated Lock Screen static work:** translated titles, local cover decode, and artwork construction are cached per static identity and coalesced behind one cancelable task. Paragraph transitions update only dynamic timeline fields.
* **Mitigated - unconditional Nghi warm-up:** Siri/Google/Ext app launches no longer prepare the Piper model; Nghi selection owns the lazy warm-up lifecycle.

## Web-extension engine risks mitigated in 1.3.39

* **Deadlock mitigation**: The `waitForReady` JS bridge checks `Thread.isMainThread` and returns a failed JSON readiness DTO immediately instead of waiting on the semaphore, preventing application deadlock.
* **WKWebView Cookie privacy limitation**: Since WKWebView Loader uses the default configuration, cookies are persistent and shared within the app's default WKWebsiteDataStore, representing a privacy constraint due to lack of per-extension/session isolation.

## Reader risks mitigated in 1.3.10

* **Mitigated - stale rendered window:** the vertical reader now advances `stableIndexes` together with the active chapter window, preventing a permanent stop at the initial `n+2` boundary.
* **Mitigated - extension fetch overlap:** `ReaderPrefetchGate` enforces one global two-request cap across Reader instances. Repository waiters now leave immediately on cancellation and cancel the underlying extension task when no Reader/TTS consumer remains, while a still-shared operation retains its gate slot until completion.
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
| **R-04** | **Lỗi hồi phục AVAudioSession** | [TTSManager.swift](../../Sources/Services/TTS/TTSManager.swift#L3939) | **Medium** | **Medium** | [13_resource_lifecycle.md](13_resource_lifecycle.md), [11_subsystems.md](11_subsystems.md) |
| **R-05** | **Strong Reference Cycle trong callback AVAudioPlayer** | [TTSManager.swift](../../Sources/Services/TTS/TTSManager.swift#L986) | **Medium** | **Low** | [12_ownership_graph.md](12_ownership_graph.md), [04_call_graph.md](04_call_graph.md) |
| **R-06** | **Rò rỉ subscription cảnh báo** | [ReaderViewModel.swift](../../Sources/Views/Reader/ReaderViewModel.swift#L125) | **Low** | **Low** | [08_lifecycle.md](08_lifecycle.md) |
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
*   **Vị trí**: Lắng nghe sự kiện ngắt tại [TTSManager.swift](../../Sources/Services/TTS/TTSManager.swift#L3939) (`setupInterruptionObserver`).
*   **Mức độ nghiêm trọng (Severity)**: **Medium** (Giao diện hiển thị đang phát nhưng không có tiếng ra loa).
*   **Khả năng xảy ra (Likelihood)**: **Medium** (Phổ biến khi người dùng nghe truyện bằng tai nghe Bluetooth và nhận cuộc gọi).
*   **Nguyên nhân**:
    *   Khi cuộc gọi kết thúc, hệ thống gửi thông báo kết thúc ngắt (`.ended`). Tuy nhiên, tại thời điểm này, hệ điều hành iOS có thể chưa hoàn toàn trả lại tài nguyên âm thanh.
    *   Việc gọi ngay lập tức `AVAudioSession.sharedInstance().setActive(true)` có thể thất bại, khiến AudioEngine không thể start lại.
*   **Giải pháp (Mitigation)**:
    *   Thực hiện thử lại (Retry) với độ trễ ngắn (ví dụ: trì hoãn 0.5 giây trước khi setActive lại).
    *   Kiểm tra kỹ kết quả trả về của hàm `setActive`.

---

### R-05: Strong Reference Cycle trong callback của AVAudioPlayer
*   **Vị trí**: Wiring callback phát audio [TTSManager.swift](../../Sources/Services/TTS/TTSManager.swift#L986) (`configureNghiAudioPlayerQueueCallbacks`) và delegate `audioPlayerDidFinishPlaying`.
*   **Mức độ nghiêm trọng (Severity)**: **Medium** (Rò rỉ bộ nhớ của TTSManager).
*   **Khả năng xảy ra (Likelihood)**: **Low** (Do đã được giảm thiểu).
*   **Ghi chú cập nhật**: Đường phát **không** dùng `AVAudioPlayerNode.scheduleBuffer` — repo hiện không có lệnh `scheduleBuffer` nào và `TTSAudioEngineController.play()` không có caller. Rủi ro retain cycle thực tế nằm ở các closure callback của `AVAudioPlayer`/`NghiAudioPlayerQueue` và block `DispatchQueue.main.async` lồng bên trong.
*   **Nguyên nhân**:
    *   Callback hoàn tất phát (`audioPlayerDidFinishPlaying`) và các completion closure của `NghiAudioPlayerQueue` chạy ngoài Main Actor.
    *   Nếu closure lồng `DispatchQueue.main.async` mà không capture lại `[weak self]`, có thể vô tình giữ chặt `self` trong Main Queue khi manager/session bị thay thế.
*   **Giải pháp (Mitigation)**:
    *   Đảm bảo capture `[weak self]` ở cả callback ngoài lẫn block `DispatchQueue.main.async` lồng bên trong; giải phóng `audioPlayer = nil` khi stop.

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

- `ChapterTextNormalizer` is the single source for LF newlines, trimmed non-empty lines, **sparse paragraph IDs (`ChapterTextLine.id` is the raw line index and counts blank lines, so IDs are not array offsets and must be looked up by `id`, never used as an array index)**, and UTF-16 ranges. Because those ranges are computed before blank lines are dropped, `ChapterTextLine.utf16Range` must not be used to slice `NormalizedChapterText.content`. `ChapterContentRepository` produces one normalized `ChapterDocument` for both Reader and TTS.
- Reader uses `ReaderLoadState` with bootstrap retry/clamping, typed failures, generation checks, cache-first rendering, and a short opacity crossfade only for newly fetched content. `ReaderRoute.chapterIndex` preserves the selected TOC index through navigation.
- `TTSParagraphBuilder` chunks normalized lines without renumbering parent paragraph IDs; replacement output is checked before synthesis. TTS asynchronous work is guarded by session identity and TTS owns progress while playing.
- `ReadingProgressStore` coalesces RAM snapshots in an actor and flushes from background contexts on checkpoints, dismissal, and app backgrounding. Legacy window/tab Reader, duplicate progress repository, and `TTSSession` mirror are removed.
- **R-08: Main Thread Deadlock in WebView Native Bridge**: If browser wait/load operations are called on the Main Actor, `semaphore.wait()` blocks the Main Thread, preventing WKWebView from executing scripts and causing an instant deadlock. Mitigated by fail-fast thread check (`Thread.isMainThread`) returning a failed JSON readiness DTO immediately, exclusively on the new `waitForReady` bridge, while legacy synchronous `launch`/`callJs` API bridges remain unmitigated.
- **R-09: WKWebView Shared Cookie Persistence Limitation**: Default `WKWebViewConfiguration` shares cookie persistence via the default data store at the application configuration level (WKWebsiteDataStore persistence), which remains a limitation with no per-extension or per-session isolation; the `waitForReady` DTO design only limits what readiness data crosses the bridge and is unrelated to cookie isolation.

- **R-10: Remote TTS thermal/CPU burst (Partially mitigated)**: A depth-three window previously created independent Google/Ext tasks with no concurrency cap and nested retry. Mitigation is one priority coordinator (`RemoteTTSSynthesisCoordinator`), service-owned retry capped at two attempts, and delayed next-chapter audio. Thermal state is telemetry-only, so heat is **not** actively throttled — sustained remote synthesis on a warm device remains a residual risk.
- **R-11: Persistent Ext TTS JS state (Mitigated)**: Reusing JavaScriptCore can retain extension globals. The runtime is isolated to TTS, serialized, keyed by exact script/config identity, reset on error/full cache teardown, and never shared with search/detail/toc/chap execution.
- **R-12: Sustained NghiTTS on-device inference heat (Unmitigated for heat)**: Piper remains one-worker and serialized; the prefetch window keeps `N` + mandatory `N+1` plus up to two optional reserve items from `N+2` gated by the cached-time watermark, and matching in-flight work is reused to prevent duplicate synthesis. There is **no** thermal gating: `.serious`/`.critical` are logged only and never cancel or throttle refill, and there is no cooldown throttle. Very long sessions and measured RTF >= 1 therefore still generate unbounded heat and require a lighter model or another engine for guaranteed gapless playback.
- **Residual risk**: The VBook-compatible synchronous `fetch` API still waits on a worker semaphore. Registered URLSession tasks are now cancellable and binary payload text decoding is skipped, but changing the public JS API to mandatory Promise semantics remains incompatible with existing extensions.

<!-- GENERATED END -->
