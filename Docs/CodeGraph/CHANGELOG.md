# CHANGELOG - Nhật ký Thay đổi CodeGraph FreeBook

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **FreeBook**.

## [1.3.492] - 2026-10-09

### perf(chuong, khoi dong): bien dich luat loc rac mot lan, bo luot loc thua, regex cleanHTML tinh, bo parse tu dien trung

Người dùng: *"đừng làm refactor nữa, tôi muốn bạn tra lại code và xem chỗ nào ảnh hưởng hiệu năng app, chỉnh sửa lại cho app mượt hơn, hiệu năng tốt hơn"*. Nguồn: rà toàn app 7 mảng + 2 mảng tác vụ định kỳ, mỗi phát hiện qua một vòng phản biện đối kháng; nhóm này sửa xong lại qua một vòng phản biện nữa (lỗi tìm được đã sửa).

- **Lọc rác**: `filterRawContent` trước đây biên dịch lại regex của **mọi** luật ở mỗi lần gọi và chép cả chương một lần cho mỗi luật. Nay biên dịch một lần khi nạp luật (luật regex lỗi bị bỏ như `try?` cũ), áp theo đúng thứ tự trên một `NSMutableString` — đầu ra giống hệt. Thêm `[ReaderPerf] JunkFilter rules= chars= ms=` (chỉ khi bật log và có luật).
- **Bỏ một lượt lọc thừa khi đọc chương đã lưu**: `ChapterPersistenceStore` đã `normalize` (lọc) nội dung; `ChapterContentRepository.makeDocument` lọc lần nữa. Nhánh persisted nay dựng document bằng `normalizeProcessedContent` (tham số `prefiltered`); nhánh lấy từ extension vẫn `normalize`. Hệ quả có chủ đích: luật **không idempotent** được áp ít hơn một lần (vốn là lỗi áp trùng). `ChapterContentRepository.swift` giữ đúng baseline 455.
- **`cleanHTML`**: 7 regex thành `static let` (cùng pattern, cờ `(?i)`, thứ tự, template) — chạy mỗi lần nạp chương và mỗi hàng mô tả ở Khám phá.
- **Khởi động**: bỏ lượt parse `TextDictionary` thứ hai của Names/VietPhrase tuỳ chỉnh mà `publishCustomRecords` ghi đè ngay sau đó (cờ đã nạp lấy từ state đã publish); thêm `[LaunchPerf] Dictionaries ms=` (chỉ khi bật log). `TranslationManager.swift` 590 → 564.
- **Backfill tên dịch**: chỉ xét truyện thật sự còn gì để điền, chỉ gán khi giá trị mới khác rỗng và khác cũ, `save()` khi `hasChanges` — trước đây truyện có tác giả rỗng bị xử lý lại và `save()` ở **mỗi** lần mở app.
- **Kiểm chứng**: `check_architecture.py` chỉ còn 2 vi phạm nền cũ (`JSDom`, `TTSManager`), 0 mới. **Không build tại chỗ** (Windows) — CI nhánh `refactor/god-objects` xác nhận biên dịch.

## [1.3.491] - 2026-10-09

### perf(dich): nho ket qua span theo chuong, regex tinh, md5 nhanh, tokenizer khong giai ma thua

Người dùng: *"đừng làm refactor nữa, tôi muốn bạn tra lại code và xem chỗ nào ảnh hưởng hiệu năng app, chỉnh sửa lại cho app mượt hơn, hiệu năng tốt hơn"*. Nguồn: rà toàn app 7 mảng + 2 mảng tác vụ định kỳ, mỗi phát hiện qua một vòng phản biện đối kháng; nhóm này sửa xong lại qua một vòng phản biện nữa (lỗi tìm được đã sửa).

- **Reader và TTS không dịch span lại cùng một chương**: `translateContentWithMapping` chỉ cache phần text; span (`translationSpansApplyingRules` — tra 8 trie, hậu xử lý, dò vị trí từng token) bị tính lại cho từng dòng mỗi lần dựng, mà Reader + TTS + prefetch N+1 cùng dựng một chương. Thêm memo kết quả `TranslatedTextResult` (`TranslateUtils+MappingMemo.swift`, 1024 mục / 8 MiB): khoá gồm `cacheGeneration`, `bookId`, cờ phồn→giản, cờ pronouns/luật nhân và md5 dòng; tra **trước** `withSnapshot` (rules.md luật 30); chỉ ghi khi không bị huỷ, từ điển đã nạp và generation chưa đổi (cùng cơ chế ticket với `translateText`). Sửa VP/rule ⇒ generation đổi ⇒ entry cũ tự hết hiệu lực.
- **Regex tĩnh** cho `translateChapterTitle` (4 `try! NSRegularExpression` mỗi lần trượt cache → `static let`, cùng pattern/option). Không đổi cỡ cache tên chương.
- **`md5()`/`sha256()`**: hex bằng bảng tra thay vì 16–32 lần `String(format:)` — kết quả giống từng byte (md5 nằm trong khoá của 3 memo nóng).
- **Tokenizer**: `FrozenTrieDictionary` không còn `subdata` khi đọc số/giải mã nghĩa; thêm `prefixMatchLengths` vào `TrieDictionary` (mặc định = `findAllPrefixMatches(...).map(\.length)`) để tokenizer — chỉ cần độ dài — không giải mã UTF-8 nghĩa của mọi match; lọc `>= 2` và mục đã xoá giữ nguyên.
- **Nạp `.dat` lúc khởi động** (`DoubleArrayTrie.load`, nằm trên cổng chặn UI): dựng `base`/`check` trong một lượt `withUnsafeBytes` vào mảng cục bộ rồi gán một lần, thay vì ghi từng phần tử qua thuộc tính class; mảng kết quả giống từng bit.
- `TranslateUtils.swift` giữ đúng baseline 917 dòng (chỉ đổi dòng tại chỗ).
- **Kiểm chứng**: `check_architecture.py` chỉ còn 2 vi phạm nền cũ (`JSDom`, `TTSManager`), 0 mới. **Không build tại chỗ** (Windows) — CI nhánh `refactor/god-objects` xác nhận biên dịch.

## [1.3.490] - 2026-10-09

### perf(cover): cache anh bia da giai ma, doc dia ngoai main, moi bia tai mot lan

Người dùng: *"đừng làm refactor nữa, tôi muốn bạn tra lại code và xem chỗ nào ảnh hưởng hiệu năng app, chỉnh sửa lại cho app mượt hơn, hiệu năng tốt hơn"*. Nguồn: rà toàn app 7 mảng + 2 mảng tác vụ định kỳ, mỗi phát hiện qua một vòng phản biện đối kháng; nhóm này sửa xong lại qua một vòng phản biện nữa (lỗi tìm được đã sửa).

- **Triệu chứng**: mỗi lần một hàng có ảnh bìa xuất hiện (kệ sách, lịch sử, Khám phá, tìm kiếm…) `BookCoverView` chạy **đồng bộ trên main** ~20 syscall (tính lại thư mục, `resolvingSymlinksInPath`, `fileExists`), 2 lần SHA-256 + regex của bước di trú tên cũ, rồi `UIImage(contentsOfFile:)` giải mã **độ phân giải gốc** ngay lúc vẽ; không có cache RAM nên cuộn qua lại lặp lại toàn bộ. Bìa chưa có trên đĩa còn bị tải 2–3 lần.
- **Sửa**: `CoverThumbnailCache` (mới) — `NSCache` ảnh **đã giải mã**, thu nhỏ bằng ImageIO đúng cỡ hiển thị, khoá `bookId|cỡ`, trần 48 MB. `BookCoverView`: trúng cache thì hiện ngay (không nháy); trượt thì đọc đĩa ngoài main, trong lúc kiểm tra đĩa hiện placeholder — **không** gắn `AsyncImage` trước khi biết đĩa không có (tránh tải mạng bìa đã có). Cỡ khung đổi thì tải lại đúng cỡ.
- **`ImageCacheManager`**: thư mục bìa + gốc canonical tính một lần; di trú tên cũ + kiểm tra đường dẫn ghi nhớ theo `bookId` (một lần mỗi phiên, có khoá); hex SHA-256 bằng bảng tra (tên file **giữ nguyên từng byte**); gộp các lượt tải cùng `bookId` đang bay; ghi `.atomic` (cùng byte).
- **Vô hiệu cache ở mọi chỗ ghi bìa**: `saveCover`, `deleteCover`, tải xong, và khôi phục backup (`BackupCoverArchiver`). Không đổi byte/định dạng/độ phân giải bìa đã lưu (backup phụ thuộc).
- **Kiểm chứng**: `check_architecture.py` chỉ còn 2 vi phạm nền cũ (`JSDom`, `TTSManager`), 0 mới. **Không build tại chỗ** (Windows) — CI nhánh `refactor/god-objects` xác nhận biên dịch.

## [1.3.489] - 2026-10-09

### perf(reader): danh sach chuong an khong ve lai, bo @Published thua, khong dung chuong khi man hinh khoa

Người dùng: *"đừng làm refactor nữa, tôi muốn bạn tra lại code và xem chỗ nào ảnh hưởng hiệu năng app, chỉnh sửa lại cho app mượt hơn, hiệu năng tốt hơn"*. Nguồn: rà toàn app 7 mảng + 2 mảng tác vụ định kỳ, mỗi phát hiện qua một vòng phản biện đối kháng; nhóm này sửa xong lại qua một vòng phản biện nữa (lỗi tìm được đã sửa).

- **Danh sách chương ẩn không vẽ lại**: mở danh sách chương một lần là `ReaderChapterListView` nằm lại trong cây (ẩn bằng opacity) và chạy lại `body` ở **mọi** lần vẽ của `ReaderView` (mỗi bước highlight TTS, mỗi lần lưu tiến độ). Thêm `ReaderChapterListView+Equatable.swift` (so mọi input giá trị, `===` cho `@Model`/store, bỏ qua closure — cùng hợp đồng với `ParagraphCardView`) + `.equatable()`. `ForEach` của danh sách nay sinh đúng một hàng không-optional mỗi phần tử (`store.item(at:)` không bao giờ nil trong khoảng) để `List` không phải dựng mọi hàng.
- **Bỏ 3 `@Published` không ai đọc**: `readingContext`, `currentProgress`, `currentRevision` của `ReaderViewModel` thành `var` thường — mỗi lần ghi trước đây kéo theo một lượt vẽ lại toàn bộ `ReaderView` lúc đang cuộn (grep: không có body/`$` nào đọc).
- **`localBook`/`ext` của VM**: fetch bằng `#Predicate` bằng nhau + `fetchLimit = 1` thay vì đọc **cả bảng** `Book`/`Extension` trên main sau mỗi chương lấy từ extension. `ReaderView` lấy `localBook` một lần cho overlay header/footer.
- **Tìm trong truyện**: bộ so khớp chạy `Task.detached` thay vì trên main (debounce 250 ms giữ nguyên).
- **Không dựng chương khi màn hình khoá**: TTS tự sang chương lúc app ở nền trước đây bắt Reader dựng + dịch chương mới (log 84: `commitMs≈987`, chồng lên lượt tổng hợp đầu chương). Nay chỉ ghi nhớ chương mới nhất; khi app active thì nhảy tới — giữa đường TTS dừng vẫn nhảy tới chương TTS đã đọc tới (như hành vi cũ), đang phát thì đáp đúng đoạn đang đọc; TTS đã sang truyện khác thì bỏ.
- **Kiểm chứng**: `check_architecture.py` chỉ còn 2 vi phạm nền cũ (`JSDom`, `TTSManager`), 0 mới. **Không build tại chỗ** (Windows) — CI nhánh `refactor/god-objects` xác nhận biên dịch.

## [1.3.488] - 2026-10-09

### perf(vieneu): do CPU-time, tat spin luong ORT, cho phep 1 luong (P0+P1+P2)

Người dùng: *"làm cho xong đợt 8, sau đó làm Vieneu TTS tối ưu hóa trước đi, trong nhánh này luôn"*. Nguồn: báo cáo `Docs/Reports/2026-10-09-vieneu-huong-toi-uu-moi.md` (session "Vieneu TTS tối ưu hóa", chỉ điều tra). Gói P0+P1+P2 vào **một bản IPA** để đo A/B trên máy thật.

- **P0 — đo CPU-time (lỗ hổng đo lường §1 của báo cáo)**: mọi số trước đây (`rtf`, `busyPct`) là thời gian **tường**, còn năng lượng/nhiệt tỉ lệ với **CPU-time**. File mới `Sources/Services/TTS/ProcessCPUClock.swift` (`clock_gettime(CLOCK_PROCESS_CPUTIME_ID)` — cả tiến trình, tính cả pool luồng ORT).
  - `[VieNeuPerf]` thêm `cpu=…ms cpuPerAudio=… cores=…` (đo cùng khoảng với `synth=`; `cores` = số lõi bận trung bình).
  - `[NghiEnergy] Summary` (dùng cho mọi engine local) thêm `cpuMs= cpuPerAudioSec= cpuCores=` trên cả cửa sổ 60 s — CPU **cả app** (gồm render), đúng thứ quyết định nóng máy. Mẫu số `cpuPerAudioSec` là `cpuPCMSeconds` — **bỏ** audio của lượt tổng hợp mở cửa sổ (CPU của lượt đó tiêu trước mốc `startedCPUMs`, vì hàm ghi chạy khi lượt xong); `totalPCMSeconds`/`aggregateRTF` giữ nguyên. Trường mới **nối cuối**, các trường cũ giữ thứ tự.
- **P1 — tắt spin pool luồng ORT (F1)**: ORT mặc định cho luồng pool **chờ bận** giữa các op/lượt `Run`. `VieNeuONNXBridge.m` thêm `AddSessionConfigEntry(options, "session.intra_op.allow_spinning", …)` ở **cả hai** chỗ dựng session (4 graph chính + gói graph clone, giá trị lưu ở `context->allowSpinning`). `VieNeuORTCreate`/`VieNeuORTCreateCloneOnly` + 2 init Swift nhận thêm `allowSpinning`. **Mặc định TẮT** (khoá `vieneuOrtAllowSpinning`); cùng phép tính ⇒ **audio không đổi**. Công tắc `VieNeuOrtSpinToggle` trong Cài đặt VieNeu để bật lại khi cần so; dòng `Nạp xong engine` in thêm `spin=on/off`. Desktop (nhiễu tải) đo CPU-s/audio-s 2 luồng: 0,84 → 0,63 khi tắt spin — **phải xác nhận trên iPhone**.
- **P2 — cho chọn 1 luồng (F3)**: kẹp số luồng `2…4` → `1…4` (`VieNeuSynthesisPolicy.threadCount`, setter của service, picker). "Tiết kiệm pin" vẫn ghim 2 luồng và khoá picker (rules.md). Mục đích: đo 1/2/4 luồng bằng P0 — chọn mặc định theo **CPU-s/audio-s**, không theo RTF.
- **Cách đo trên máy**: bật log → **tắt** "Tiết kiệm pin" (để chọn luồng) → nghe VieNeu ~5 phút mỗi cấu hình (đổi luồng/spin xong phải nạp lại engine: đổi engine qua lại hoặc mở lại app) → gửi log. So `cpuPerAudio` của `[VieNeuPerf]` và `cpuPerAudioSec` của `[NghiEnergy] Summary`, kèm `underrun` để chắc không hụt tiếng.
- File: `VieNeuONNXBridge.h/.m`, `VieNeuONNXRuntime.swift`, `VieNeuSynthesisPolicy.swift`, `VieNeuTTSService.swift`, `VieNeuTTSEngine.swift` (396 → 398, dưới trần 400), `VieNeuTTSEngine+Adaptive.swift`, `NghiEnergyTelemetry.swift`, `TTSSettingsView+VieNeu.swift`; mới `ProcessCPUClock.swift`, `VieNeuOrtSpinToggle.swift`.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền cũ, 0 mới. Review đối kháng 2 lượt (biên dịch: 0 lỗi — `CLOCK_PROCESS_CPUTIME_ID` import được qua Darwin, `AddSessionConfigEntry` có từ ORT ~1.7, 16 specifier = 16 tham số; hành vi: 1 lỗi — mẫu số `cpuPerAudioSec` lệch cửa sổ, đã sửa như trên). **Không build tại chỗ** (Windows) — CI nhánh `refactor/god-objects` xác nhận.

## [1.3.487] - 2026-10-09

### refactor: tach TTSAutoAdvancePerfTracker va NghiEnergyTelemetry khoi TTSManager (dot 8 tach god object)

Đợt 8 của `Docs/Plans/2026-10-09-plan-refactor-god-objects.md` — bước 4/5 cắt `TTSManager.swift`. Thuần telemetry, **không đổi hành vi phát**.

- **`TTSAutoAdvancePerfTracker`** (`@MainActor final class`, `Sources/Services/TTS/`, 243 dòng): `TTSAutoAdvancePerfContext` (lồng), `activeTTSAutoAdvancePerf` (`private(set)`), hai mốc `paragraph0*`, tổng kết nạp trước (`activePrefetchPerfSummary`, `finishTTSPrefetchPerfSummary`, `recordPrefetchResult`), 5 hàm cũ của `+Telemetry` (create/updateLoad/updateProcess/finish/ensure), `lastRemoteAudioFinishUptime` + `logRemoteHandoffGap`. Thân hàm **nguyên văn**; khác duy nhất: `recordPrefetchResult` nhận `liveSessionID`/`liveChapterIndex` do façade truyền **lúc gọi** (trước đọc `self.sessionID`/`self.playingChapterIndex`).
- **`NghiEnergyTelemetry`** (`@MainActor final class`, `NghiTTS/`, 145 dòng, kèm `Notification.Name.nghiLocalSynthesisDidComplete`): `Accumulator` (cũ `NghiEnergyAccumulator`), `recordSynthesis`, `recordUnderrun`, `markPlaybackSubmitted()` (thay 2 phép gán `nghiEnergy.lastPlaybackSubmitAt` — giữ **không gate** như cũ), `flush` (giữ reset khi tắt log + cửa sổ 60 s), `thermalStateName`. Thermal state truyền vào từ façade, chỉ để **ghi log** (CLAUDE.md).
- `TTSManager` giữ `let autoAdvancePerf` / `let nghiEnergyTelemetry` (cùng khuôn `NghiAudioPlayerQueue`); `+Telemetry.swift`, `+NghiEnergy.swift` thành forwarder **cùng tên, cùng chữ ký** (~45 chỗ gọi không đổi); `paragraph0*` là computed get/set (`speakCurrent` ghi trực tiếp). Các điểm đánh giá paragraph-0 **không gộp** (để đợt 92).
- **Kết quả**: `TTSManager.swift` **3672 → 3550** (baseline 3470 — còn 80 dòng, đợt 9); format log `[TTSPerf]`/`[NghiEnergy]` giữ nguyên từng byte; `check_architecture.py` 2 violation, 0 mới. Review đối kháng 2 lượt: 0 lỗi. **Không build tại chỗ** (Windows) — CI nhánh `refactor/god-objects` xác nhận.

## [1.3.486] - 2026-10-09

### refactor: tach TTSChunkPositionMapper va TTSSettingsSnapshot khoi TTSManager (dot 7 tach god object)

Đợt 7 của `Docs/Plans/2026-10-09-plan-refactor-god-objects.md` — bước 3/5 cắt `TTSManager.swift`.

- **`TTSChunkPositionMapper`** (`Sources/Services/TTS/`, 106 dòng, enum không case): 3 hàm thuần đổi "vị trí người dùng" → chỉ số chunk, **cố ý giữ 3 ngữ nghĩa riêng** (phản biện khảo sát): `targetChunkIndex` (ưu tiên `resumeIdentity` rồi `sourceRange`; thân `findTargetChunkIndex`, hàm `public` này còn là forwarder), `indexForParagraphPosition` (khớp `paragraphIndex`, nhận tiêu đề qua `first?.paragraphIndex == -1`; từ `updateParagraphPositionWithoutPlaying`), `reanchorAfterSettings` (so **`range`** hiển thị với chunk cũ sau khi dựng lại đoạn, chấp nhận `range.length == 0`; từ `resumeAfterSettings`, cờ tiêu đề do caller tính y như cũ). Force-unwrap và kiểm `NSNotFound` giữ nguyên thứ tự.
- **`TTSSettingsSnapshot`** (`Sources/Services/TTS/`, 62 dòng): struct `Equatable` từ `private` lồng trong `TTSManager` thành top-level + `static capture(...)` đọc `UserDefaults` tại thời điểm gọi (vẫn đúng 2 thời điểm: `prepareForSettings`, `resumeAfterSettings`). Danh sách trường **không đổi** — vẫn cố ý **không** gồm `nghittsSafeCachedTimeThreshold`/`nghittsPrefetchCount`/`vieneu*` (đổi riêng ngưỡng đệm không được phát lại từ đầu). **Không** gộp 4 biến `saved*BeforeSettings` thành `ResumeAnchor` (plan gợi ý tuỳ chọn): `savedChunkIndexBeforeSettings` chỉ ghi không đọc, gộp là đổi cấu trúc không cần cho đợt thuần di chuyển.
- Caller ngoài file không đổi: `TTSSettingsView` (`prepareForSettings`/`resumeAfterSettings`), `ReaderView` (`updateParagraphPositionWithoutPlaying`).
- **Kết quả**: `TTSManager.swift` **3770 → 3672** (baseline 3470 — đợt 8–9 xử lý tiếp); `check_architecture.py` 2 violation, 0 mới. Review đối kháng 2 lượt: xem walkthrough. **Không build tại chỗ** (Windows) — CI nhánh `refactor/god-objects` xác nhận.

## [1.3.485] - 2026-10-09

### refactor: tach TTSRefillFailurePolicy khoi TTSManager (dot 6 tach god object)

Đợt 6 của `Docs/Plans/2026-10-09-plan-refactor-god-objects.md` — bước 2/5 cắt `TTSManager.swift`.

- File mới `Sources/Services/TTS/NghiTTS/TTSRefillFailurePolicy.swift` (83 dòng, 1 enum không case, cạnh `NghiSynthesisPolicy`): `RefillFailureState`, `RefillTaskOutcome` (giữ `Equatable`), `classifyTTSError`, `evaluateRefillError` (giữ `maxAttempts = 2`; `CancellationError` vẫn **không** tính là một attempt), `selectNghiOptionalRefillCandidate` (giữ `blockedIndices = []`), `logPrefetchFailure` (từ `private` thành internal). Thân hàm chuyển **nguyên văn** — script so với `HEAD` sau khi bỏ từ khoá `internal`/`nonisolated internal`: khớp từng byte.
- `TTSManager` giữ `typealias RefillFailureState/RefillTaskOutcome` + forwarder `nonisolated static` **cùng chữ ký và default** ⇒ 5 chỗ gọi ngoài file (`TTSNextChapterPrefixCache` ×4, `TTSManager+NextChapterPrefix:60`) và mọi chỗ trong file **không phải sửa**. `RefillFailureKey` và `nghiRefillFailureStates` **vẫn ở `TTSManager`** (state, không phải policy — đợt 94).
- Luật giữ nguyên: policy là **nguồn duy nhất** cho cả refill Nghi lẫn cache prefix chương kế; điều phối retry vẫn do `TTSManager` sở hữu.
- **Lưu ý codegraph** (ghi vào bẫy #5 ở CLAUDE.md): `codegraph_explore` báo `evaluateRefillError`/`RefillFailureState` chỉ có caller trong `TTSManager.swift`, grep thấy thêm 5 chỗ ở 2 file khác — đúng lý do phải grep chéo trước khi di chuyển.
- **Kết quả**: `TTSManager.swift` **3812 → 3770** (baseline 3470, vi phạm cũ); `check_architecture.py` 2 violation, 0 mới. Review đối kháng 2 lượt: xem walkthrough. **Không build tại chỗ** (Windows) — CI nhánh `refactor/god-objects` xác nhận.

## [1.3.484] - 2026-10-09

### refactor: tach 4 type TTS khoi TTSManager va xoa 3 ham chet (dot 5 tach god object)

Đợt 5 của `Docs/Plans/2026-10-09-plan-refactor-god-objects.md` — bước đầu trong 5 bước đưa `TTSManager.swift` (3956) xuống dưới baseline 3470.

- **4 type top-level** ở đầu `TTSManager.swift` (HEAD dòng 9–86) tách **mỗi type một file** cùng thư mục `Sources/Services/TTS/`: `TTSPreparedChapterKey`, `TTSPreparedChapter`, `TTSPrefetchPerfSummary` (giữ `public` + `public init` — `TTSManager+Telemetry` dùng), `TTSChapterQueueMetadataWorker` (giữ `@available(iOS 17.0, *)`, thêm `import SwiftData` cho `ModelContainer`). Thay đổi ngữ nghĩa **duy nhất**: `private actor` → `actor` (private top-level là phạm vi **file**). `TTSManager.swift` nay còn **đúng một** primary type ⇒ entry `MULTI_PRIMARY_TYPES` của nó trong allowlist đã thừa (không sửa allowlist — chờ người dùng).
- **Xoá 3 hàm `private` chết**, grep toàn `Sources/` (kể cả `#selector`, string literal, `TTSManager+*.swift`) ra **0 caller**: `recordPrefetchRetry` (chỗ duy nhất tăng `retrySuccess`/`retryFailure` ⇒ hai trường này vốn luôn 0 trong log `[TTSPerf] PrefetchSummary`, trước sau không đổi), `isTransientTTSError` (phân loại retry đã nằm ở `evaluateRefillError`/`ExtTTSService.isTransient`/Google inline — đúng luật "retry thuộc một tầng"), `commitParagraphState` (wrapper một dòng; caller thật gọi thẳng `commitAudibleParagraphState`). **Ghi nhận**: `rules.md:1049` còn nhắc tên `commitParagraphState` — không sửa `rules.md` nếu người dùng chưa yêu cầu.
- **Kết quả**: `TTSManager.swift` **3956 → 3812** (còn 342 dòng trên baseline — vi phạm cũ, các đợt 6–9 xử lý tiếp); `check_architecture.py` **2 violation** (`JSDom`, `TTSManager`), 0 mới. Script so từng byte với `HEAD`: phần còn lại = HEAD trừ 3 vùng; 4 thân type khớp (trừ đúng từ `private`). Review đối kháng 2 lượt: 0 lỗi biên dịch/hành vi. **Không build tại chỗ** (Windows) — CI nhánh `refactor/god-objects` xác nhận.

## [1.3.483] - 2026-10-09

### refactor: tach 7 DTO dieu huong + ReaderProgressCoordinator khoi ReaderViewModel (dot 3+4 tach god object)

Đợt 3 và 4 của `Docs/Plans/2026-10-09-plan-refactor-god-objects.md`, gộp một commit vì đợt 3 một mình chưa đưa `ReaderViewModel.swift` xuống dưới baseline 830.

- **Đợt 3a — 7 value type** ở đầu `ReaderViewModel.swift` (HEAD dòng 6–86) tách **mỗi type một file** dưới `Sources/Views/Reader/Navigation/`: `ReaderNavigationSource`, `ReaderNavigationDirection`, `ReaderLoadState`, `ReaderLoadError` (giữ nguyên chuỗi tiếng Việt), `ReaderNavigationCommit`, `ReaderChapterLoadFailure`, `ReaderNavigationRequest`. Chỉ `import Foundation`. Thay đổi **duy nhất** về ngữ nghĩa: `private struct ReaderNavigationRequest` → `struct` (private top-level là phạm vi **file**, chuyển file thì VM không thấy nữa). Script so từng byte với `HEAD`: khớp (trừ đúng từ `private`).
- **Đợt 3b — `CachedChapter.isTranslationFresh(token:enabled:convertTraditional:)`** (`Extensions/CachedChapter+TranslationFreshness.swift`) gom 4 bản copy của cùng một điều kiện (`requestChapter`, `runNavigationWorker` ×2 — một dạng phủ định, `+Translation.updateCachedTranslatedContent`). Chỗ chỉ kiểm riêng token trong `memoryCommitTask` **cố ý giữ nguyên**.
- **Đợt 4 — `ReaderProgressCoordinator`** (`@MainActor final class`, `Coordinators/`, 119 dòng) + `ReaderProgressHost` (protocol, `weak`): sở hữu `lastSavedProgress`, `dbSaveTask`, truy cập `ReadingProgressStore`, `shouldScheduleSave` (≥ 3 đoạn hoặc đổi chương, `ReaderProgressScheduler` `progressToken: 1`), debounce **3 s**, `save(force:)`, `saveImmediately()` (Task `.high`, chụp vị trí theo **giá trị**, giữ coordinator chứ không giữ VM ⇒ flush vẫn xong sau khi Reader đóng), `cancelPendingSave()`, `start(container:)` (`configure` → `claim(.reader)` đúng thứ tự cũ). VM giữ `@Published currentProgress`/`readingContext`, `saveProgressToDatabase`/`saveProgressImmediately` thành forwarder (caller `ReaderView` không đổi).
  - **Hai bẫy đã tránh (theo phản biện khảo sát)**: (1) gắn host bằng `progress.attach(host: self)` **sau** pha 1 của `init` — truyền closure bắt `self` vào constructor là lỗi "self captured before all members initialized"; không dùng `lazy var` vì sẽ seed `lastSavedProgress` sai. (2) Debounce đọc `host?.currentProgress` **lúc nổ**, không chụp lúc đặt lịch — đúng như code cũ đọc `self.currentProgress`.
  - Luật §5.10 giữ nguyên; không thêm hook `.onDisappear`; TTS vẫn là chủ tiến độ khi phát.
- **Kết quả**: `ReaderViewModel.swift` **925 → 779** (baseline 830) ⇒ hết vi phạm; `check_architecture.py` **3 → 2 violation** (còn `JSDom`, `TTSManager`), 0 mới. Review đối kháng 2 lượt (biên dịch + hành vi): xem kết quả ở walkthrough. **Không build tại chỗ** (Windows) — CI nhánh `refactor/god-objects` xác nhận.

## [1.3.482] - 2026-10-09

### refactor: tach 10 DTO/error/state khoi ChapterPersistenceStore sang Persistence/ (dot 2 tach god object)

Đợt 2 của `Docs/Plans/2026-10-09-plan-refactor-god-objects.md` — thuần di chuyển, không đổi hành vi, không đổi tên.

- **Nhánh làm việc**: từ đợt này refactor chạy trên nhánh `refactor/god-objects` (tách từ `sigle_reader` sau đợt 1); `.github/workflows/build-ipa.yml` thêm nhánh vào trigger `push` để CI biên dịch từng đợt. Xong toàn bộ và CI xanh mới merge về `sigle_reader`.
- 10 type top-level ở đầu `ChapterPersistenceStore.swift` (HEAD dòng 4–133) tách thành **mỗi type một file** dưới `Sources/Services/ChapterText/Persistence/`: `ChapterMetadataSnapshot`, `ProtectedTTSChapter`, `LocalTOCRefreshResult` (giữ `public` + `public init` — `TTSManager.applyTOCReconciliation` là `public func`), `BookMetadataSnapshot`, `TOCBookCreateSnapshot`, `TOCReconciliationMode`, `SaveTOCResult`, `PersistedChapterSnapshot`, `ChapterPersistenceError` (giữ nguyên chuỗi `errorDescription` tiếng Việt), `ChapterPersistenceState`. Mỗi file chỉ `import Foundation`.
- Tên type giữ nguyên, phạm vi module ⇒ **12 file tiêu thụ** (`ChapterContentRepository`, `BackupChapterRestorer`, `ExportContentProvider`, `BookDetailView(+Extensions)`, `ReaderChapterListView+Refresh`, `ReaderViewModel`, `ShelfView+BookImport`, `TTSManager`, `ChapterStore*`…) **không phải sửa**. `PersistedChapterSnapshot` là kiểu trả về của `readChapter` — không phải dead code.
- `ChapterPersistenceStore.swift` **915 → 784** dòng (baseline 884) ⇒ hết vi phạm; file còn actor + `ReconciliationPool` (`fileprivate`, sẽ tách ở đợt 18).
- **Kiểm chứng**: script so **từng byte** với `HEAD` — phần tách ra ghép lại bằng đúng dòng 4–133, phần còn lại bằng đúng phần còn lại; `check_architecture.py` **4 → 3 violation**, 0 mới. Review đối kháng 2 lượt: 0 lỗi. **Không build tại chỗ** (Windows) — CI xác nhận.

## [1.3.481] - 2026-10-09

### refactor: tach 7 chuoi JS bootstrap va cleanAndResolveUrl khoi JSExecutor (dot 1 tach god object)

Người dùng: *"refactor toàn dự án luôn"* → chọn **tách hẳn các god object**, làm thẳng **từng đợt một**. Kế hoạch 95 đợt (khảo sát chỉ đọc: 13 đối tượng × bản đồ + phản biện + tổng hợp) ở `Docs/Plans/2026-10-09-plan-refactor-god-objects.md`. Đây là **đợt 1** — thuần di chuyển, không đổi hành vi.

- **7 chuỗi JS bootstrap** (trước là `let xxxBootstrap = """…"""` cục bộ trong `JSExecutor`) chuyển sang `static let` của 6 enum, mỗi file một enum:
  - `Engine/Bootstrap/JSCoreBootstrapScripts.swift` — `response`, `userAgent`
  - `Engine/Bootstrap/JSScriptHttpBootstrapScript.swift`, `JSFetchBootstrapScript.swift`, `JSEngineBootstrapScript.swift` — `source`
  - `Engine/Bridges/JSQtTranslateBridge.swift`, `JSExtensionStorageBridge.swift` — `bootstrap` (hiện chỉ giữ polyfill; block `_native*` vẫn cài trong `JSExecutor`)
- **Giống từng byte**: chuyển bằng script, so giá trị literal sau khi mô phỏng cách Swift bỏ lề `"""` — cả 7 khớp với `HEAD`; hai lượt review độc lập tự tính lại SHA-1 cũng khớp. Literal không có interpolation, không có escape. Mỗi `let xxxBootstrap = Enum.prop` + `context.evaluateScript(...)` **giữ nguyên vị trí và thứ tự** (Engine vẫn nạp cuối).
- **`cleanAndResolveUrl`**: thân hàm chuyển nguyên văn sang `ExtensionURLFormatter.cleanAndResolve` (`Engine/ExtensionURLFormatter.swift`); `JSExecutor.cleanAndResolveUrl` còn là forwarder `public static` một dòng ⇒ 14 caller không phải sửa.
- **Kiểm chứng**: `check_architecture.py` **5 → 4 violation** — `JSExecutor.swift` **1561 → 976** (baseline 1066) hết vi phạm; 0 mới. Review đối kháng 2 lượt (biên dịch + hành vi/luật): 0 lỗi. **Không build tại chỗ** (Windows) — CI xác nhận; `project.yml` glob `Sources` gom cả thư mục con mới. File mới: 34–184 dòng, 1 type, chỉ `import Foundation`.

## [1.3.480] - 2026-10-09

### fix: ke sach da cache rule va tu dien rieng 3 truyen (tra cache dich truoc capture, tach tang ten)

Người dùng: log `app_logs (81–82).txt` — *"bộ rule của 4 truyện khác nhau … được nạp xoay vòng … nhìn có vẻ là bug, tối đa 2 truyện (1 nghe 1 đọc) được dịch chứ sao đến 4 truyện nhỉ"*.

- **Triệu chứng**: `🔤 [QuickTranslateRule] Bộ riêng: nạp … rule` của **4** hash khác nhau lặp xoay vòng 6–7 lần mỗi cụm, ngay trước các khoảng lặng chuyển chương (log 81) và ngay sau khi mở chi tiết truyện (log 82); `gen` lên **366** trong ~1,5 giờ.
- **Nguồn 4 truyện là kệ sách, không phải Reader/TTS**: `ShelfView` trình bày Reader bằng `fullScreenCover` nên vẫn sống bên dưới, `@Query(sort: \Book.lastReadDate)` bắn lại khi tiến độ được lưu (chuyển chương, mở chi tiết); mỗi hàng `BookListItemView` dịch tên bằng `bookId` **của chính truyện đó**.
- **Lỗi gốc**: `TranslateUtils.translateText` gọi `TranslationReadContext.withSnapshot` → `capture` **trước** khi tra cache dịch. `capture` nạp snapshot rule (`QuickTranslationRuleBookStore`, cache 3 truyện) **và** `VietPhrase.txt`/`Names.txt` riêng (`TranslationDictionaryState.book`, cache 3 truyện — phần này **không có log**) ⇒ ≥ 4 truyện là đá cache xoay vòng, đọc + parse lại file trên main thread dù bản dịch đã có trong cache.
- **Sửa** (`TranslateUtils.swift`, chữ ký không đổi, kết quả dịch không đổi):
  - Tính khoá + tra cache **trước** `withSnapshot`; chỉ `capture` khi trượt. Ticket (`epoch`) của `TranslationMemo` lấy sớm hơn ⇒ chỉ chặt hơn, không thể ghi bản dịch cũ.
  - Tầng cache riêng `metaTranslationCache` cho `translateMeta` (tên/tác giả) — dòng nội dung chương của Reader/TTS (mỗi chương ~100–200 mục) không còn đẩy tên trên kệ ra khỏi cache 1024 mục. Xoá ở đúng hai chỗ xoá cache cũ (`invalidateCache(bookId:)`, `clearCache()`).
  - Mảnh tên chương trong `translateChapterTitle` đi tầng nội dung (`translateContent`): `chapterTitleCache` đã giữ cả tên, mục lục dài không còn làm tràn tầng tên. `isMeta` chỉ nằm trong khoá cache, không vào `performTranslation` ⇒ kết quả y hệt.
- **Đã thử và bỏ**: cho hàng Khám phá dịch với `bookId = nil` — review chỉ ra `BookDetailView.resolveBookId` (:759-769) có lúc giữ **link** làm `Book.bookId`, khi đó truyện có từ điển/rule riêng dưới `books/<link>/` ⇒ đổi sang `nil` làm tên ở Khám phá lệch tên trên kệ. Đã hoàn lại.
- **Còn lại (chấp nhận)**: lần **trượt** cache vẫn `capture` từng truyện — sau khi sửa từ điển (đổi `generation` của mọi truyện), lần vẽ đầu sau khi mở app, hoặc khi danh sách bình luận dài (vẫn dùng `translateMeta`) làm tràn tầng tên ⇒ một đợt nạp, không còn ở **mỗi** lần vẽ lại. Giới hạn 3 truyện giữ nguyên.
- **Không phải** liên quan tới commit `1d6c93a4` (miễn trần regex 250 cho rule mục lục mặc định khi khôi phục cấu hình) — commit đó đã có trên `sigle_reader` và còn nguyên.
- **Kiểm chứng**: `check_architecture.py` **5 violation nền cũ, 0 mới**; `TranslateUtils.swift` **911 → 917** (đúng baseline 917 — lần sau đụng file này **phải tách file trước**). Review đối kháng 3 lượt: tương đương hành vi, invalidation đầy đủ, biên dịch (đọc code). **Không build tại chỗ** (Windows). Chưa chứng minh được đây là nguyên nhân khoảng lặng 0,45–2,5 s lúc chuyển chương — cần log sau bản sửa để so.

## [1.3.479] - 2026-10-09

### perf: dedupe O(n), cache lich su tim kiem, tra tu dien khong copy ca chuoi, them log JSPerf

Người dùng: *"bạn tiến hành tối ưu đi"* — thực thi plan `Docs/Plans/2026-10-09-plan-perf-4-hotspots.md` bước 1–4 (bước 5, sửa #1, chờ số đo).

#### #2 + #4 — khử trùng lặp O(n), cache lịch sử tìm kiếm

- **`filterAndDeduplicate`** (`NovelListUtils.swift`): `reduce` + `acc.contains(where:)` gọi `normalizeLink` hai vế ở mọi cặp (O(n²)) ⇒ một vòng với `Set<String>`. Giữ đúng phần tử **đầu tiên** của mỗi khoá và thứ tự gốc; chữ ký không đổi nên 4 caller không phải sửa.
- **`PaginatedNovelLoader`**: trang ≥ 2 so từng mục mới với **toàn bộ** `novels` đã tích luỹ trên `@MainActor` (chậm dần theo số trang đã cuộn) ⇒ dựng `Set` khoá **mỗi trang**. Cố ý **không** giữ `Set` làm state: `reload()` gán thẳng `novels = unique`, một `Set` sống qua lần đó sẽ nuốt im lặng kết quả trùng khoá cũ.
- **Lịch sử tìm kiếm** (`SearchView`, `ShelfSearchView` — dùng chung key `search_history`): getter decode JSON mỗi lần đọc, mà `matchingHistory` bị đọc 3 lần mỗi lần dựng `body`, tức mỗi phím gõ. Nay `@State displayedHistory` cho **hiển thị**, nạp bằng `.onChange(of: searchHistoryJSON, initial: true)` (iOS 17) — bắt luôn lần ghi từ màn kia.
- **Bẫy đã tránh**: đường **ghi** vẫn decode thẳng từ JSON, **không** đọc cache. `SearchView.onAppear` gọi `performSearch` → `saveQueryToHistory` khi mở kèm `initialSearchQuery`, và thứ tự giữa `.onAppear` với `onChange(initial:)` không được SwiftUI đảm bảo — đọc cache rỗng lúc đó là ghi đè mất cả 15 mục lịch sử. Setter gán cache ngay để hiển thị không lệch.
- Lợi ích thật: #2(b) có ý nghĩa khi cuộn nhiều trang; lọc kết quả search (~20–50 mục/nguồn) và lịch sử (trần 15 mục) là dọn dẹp rẻ, gần như không cảm nhận được.
- **Kiểm chứng**: `check_architecture.py` **5 violation nền cũ, 0 mới**. **Không build tại chỗ** (Windows, không có `swiftc`) — CI xác nhận biên dịch. Review đối kháng (state SwiftUI, tương đương khử trùng) không phát hiện lỗi. Ảnh hưởng dòng: `NovelListUtils.swift` **32 → 39** · `PaginatedNovelLoader.swift` **107 → 109** · `SearchView.swift` **858 → 864** (baseline 872) · `ShelfSearchView.swift` **293 → 306**.

#### #3 — tra từ điển không copy cả chuỗi mỗi lời gọi

- **Chỗ O(L²) thật**: `QuickTranslationRuleEngine.scanBookNameOccupiedIndices` (`+NameProtection.swift`) gọi `bookNames.findLongestMatch(text: text, startIndex: cursor)` với **cả dòng** và `cursor` chạy dọc chuỗi; nhánh `entries` của `FrozenTrieDictionary` (từ điển name riêng của truyện) dựng `Array(text.utf16)` **mỗi lời gọi** ⇒ copy toàn dòng ở mọi vị trí. Chạy khi bật rule dịch nhanh và truyện có name riêng; memo 2048 entry phía trên chỉ cứu các lần sau.
- **Sửa** (`FrozenTrieDictionary.swift`, chữ ký **không đổi**, đơn vị vẫn UTF-16 — luật 1.3.339, **không** sửa caller nào, tokenizer giữ `chars: [Character]`):
  - Nhánh `entries`: hàm mới `keyWindow` copy **một cửa sổ** từ `startIndex`, dài bằng khoá dài nhất (`lengths` giảm dần ⇒ `lengths.first`), rồi cắt khoá từ cửa sổ bằng `String(decoding:as:)` như cũ ⇒ lát cắt chẻ đôi cặp surrogate vẫn ra U+FFFD. NameProtection: O(L) → O(độ dài khoá dài nhất) mỗi vị trí.
  - Nhánh `.dat` (`trieMatches`): duyệt `text.utf16` tại chỗ, không cấp mảng.
  - Mỗi lời gọi đổi `startIndex` → index **một** lần. Bản nháp đầu gọi `index(_:offsetBy:)` cho **từng** độ dài khoá — review chỉ ra breadcrumbs của String chỉ dùng cho offset ≥ 64, dưới đó là đi bộ từ đầu chuỗi ⇒ đã bỏ.
- `scanBookNameOccupiedIndices`: bỏ `let units = Array(text.utf16)` vốn chỉ dùng `.count` ⇒ `text.utf16.count`.
- Đường cửa sổ ≤ 20 ký tự (`VietPhraseTokenizer`, `QuickTranslationRuleMatcher`): nhánh `entries` vẫn một mảng nhỏ mỗi lời gọi như cũ, nhánh `.dat` bớt một lần cấp phát — lợi ích hằng số nhỏ, có thể không đo ra.
- **Ghi nhận, KHÔNG sửa (UNKNOWN)**: `VietPhraseTokenizer.swift:89`/`:180` dùng `match.length` (UTF-16) làm số `Character` khi cắt `chars[i..<(i + match.length)]` — chỉ lệch với ký tự ngoài BMP.
- **Kiểm chứng**: `check_architecture.py` **5 violation nền cũ, 0 mới**. **Không build tại chỗ** (Windows, không có `swiftc`) — CI xác nhận biên dịch. Review đối kháng soát tương đương **từng bit** với bản cũ (startIndex ngoài biên, `lengths` rỗng, cặp surrogate bị chẻ, NSString bridge) — không lệch. Ảnh hưởng dòng: `FrozenTrieDictionary.swift` **183 → 202** · `QuickTranslationRuleEngine+NameProtection.swift` **56 → 57**.

#### #1 — chỉ đo: log `[JSPerf]` đếm lời gọi JS đồng bộ chạy cùng lúc

Plan `Docs/Plans/2026-10-09-plan-perf-4-hotspots.md` §1.3 — **chỉ đo, không đổi hành vi**.

- **Chẩn đoán (đã sửa so với bản đầu của plan)**: JS `fetch`/`sleep` **không** chặn main thread. `SearchView` gọi `ExtensionManager.search` trong `group.addTask` (task con không thừa hưởng actor), và `JSExecutor.callAsync` là hàm `async` nonisolated của một class thường ⇒ theo SE-0338 (Swift 5 mode, không bật `NonisolatedNonsendingByDefault`) luôn chạy trên **cooperative pool**. Thứ bị chặn là thread của pool (≈ số core): `runner.call` đồng bộ, suốt lúc `semaphore.wait` của `syncFetchBlock` (tới 15 s), `Thread.sleep` hay chờ browser. Search **tất cả nguồn** (>15 nguồn đang bật) có thể làm cạn pool ⇒ mọi task async khác (TTS remote, dịch) phải xếp hàng.
- File mới `Sources/Services/Extensions/Engine/JSExecutionTelemetry.swift` (**67** dòng, 1 enum): bộ đếm số lời gọi JS đồng bộ đang chạy cùng lúc (khoá `NSLock`, nhả khoá trước khi ghi log), móc ở **một** chỗ — quanh `runner.call`/`function.call` trong `JSExecutor+Async.swift` (`defer` ⇒ cân bằng cả nhánh ném lỗi `-404`). **Không** chạm `JSExecutor.swift` (1561 dòng, baseline 1066).
- Log **chỉ khi có chồng lấn** (Ext TTS từng chunk và tải tuần tự từng chương — một lời gọi mỗi lúc — không sinh dòng nào): `[JSPerf] SyncCall source fn ms concurrent cores` cho lời gọi bắt đầu lúc đã có lời gọi khác chạy; `[JSPerf] SyncBurst peak calls ms cores saturated` khi đợt chồng lấn kết thúc. `saturated=1` ⇔ `peak ≥ activeProcessorCount` ⇒ pool cạn theo định nghĩa. **Không** log `main=`: với `callAsync` nó luôn bằng 0 (xem chẩn đoán trên); JS chạy trên main chỉ có `validateSyntax` ở màn soạn extension — ngoài phạm vi đo này.
- Đọc hậu quả ở log **đã có**: `[TTSPerf] PrefetchSummary` (`waitedHit`/`miss`/`maxWaitMs`). **Không** dùng `RemoteHandoff gapMs` — lúc bàn giao audio đã nằm sẵn trong bộ nhớ (prefetch ≥ 3 đoạn) và lệnh phát chạy trên main, nên pool cạn vài giây không làm gap tăng.
- Cách đo: bật log trong Cài đặt (AppLogger tự tắt mỗi lần mở app), nghe Google TTS, rồi tìm **tất cả nguồn**.
- Ghi nhận, **không** sửa ở đây: `AppLogger.log` không khoá (mỗi lần mở `FileHandle` + `seekToEndOfFile` + `write`), hai thread ghi cùng micro-giây có thể đè dòng của nhau — lỗi có từ trước, toàn app.
- **Kiểm chứng**: `check_architecture.py` **5 violation nền cũ, 0 mới**. **Không build tại chỗ** (Windows, không có `swiftc`) — CI xác nhận biên dịch. `xcodegen generate` do CI chạy (`project.yml` glob `Sources` ⇒ file mới không phải khai). Review đối kháng (biên dịch + cân bằng `begin`/`end` + khoá) không phát hiện lỗi. Ảnh hưởng dòng: `JSExecutor+Async.swift` **63 → 66** · `JSExecutionTelemetry.swift` **67 (mới)**.

## [1.3.478] - 2026-10-08

### fix: thong nhat toc do phat 0.5-5.0x qua AVAudioPlayer, xoa dead code AVAudioEngine va synthesizeStream

Người dùng: *"kiểm tra lại có engine nào phát âm thanh dùng cái khác ngoài avaudioplayer không"* · *"hiện tại tôi điều chỉnh google tts lên 5 nó hoạt động tốt"* · *"tăng lên 5 đi, cả vieneu nữa, Để cho chúng dùng chung AVAudioPlayer.rate với google tts và ext tts vì chúng đều phát bằng AVAudioPlayer"*.

- **Nới trần tốc độ phát 2,0× → 5,0× cho engine local.** `NghiAudioPlayerQueue.clampedRate` tự chặn ở 2,0× trong khi UI cho kéo tới 5,0× ⇒ khoảng 2,0–5,0× là **khoảng chết**: người dùng kéo nhưng tai không nghe thấy gì khác, **không** có cảnh báo nào. Nay dải lấy từ **một nguồn sự thật** — file mới `Sources/Services/TTS/TTSSpeedPolicy.swift` (**31** dòng, 1 enum) — dùng chung cho cả `clampedRate` lẫn `TTSSettingsView+Voice` (`:41`, `:49`) nên hai bên **không thể** lệch nhau lần nữa. Sàn 0,5 giữ nguyên (`AVAudioPlayer.rate` phải `> 0`; `calculateNghiCachedTime` và `preparedNextDuration` đều chia cho `rate`).
- **Vì sao 5,0× hợp lệ.** Tài liệu Apple cho `AVAudioPlayer.rate` chỉ *mô tả* dải 0,5–2,0 là dải được hỗ trợ, **không** nói giá trị ngoài dải bị kẹp. Anh Bửu đo trên máy thật: `rate = 5.0` chạy đúng, nhanh hơn thật, **cao độ bình thường**. Trần 2,0 trước đây là do repo tự đặt, không phải giới hạn nền tảng. Ghi chú cũ trong chính CHANGELOG này (`AVAudioPlayer.rate` là *"varispeed, đổi cả cao độ"*) là **sai** — tài liệu Apple ghi rõ *"Adjusting the audio's playback rate doesn't alter its pitch"*.
- **Ràng buộc kèm theo, ghi vào doc của `TTSSpeedPolicy`.** Engine local chỉ bền vững khi `r ≤ 1/RTF` (RTF đo được của VieNeu: 0,29–0,37 ⇒ trần thật ~2,7–3,4×). **Tốc độ tổng hợp không nâng được trần này** — bất đẳng thức rút gọn còn `RTF ≤ 1/r`, `s` triệt tiêu; nó chỉ giảm tổng tính toán cho cùng tốc độ nghe. Chủ dự án chốt **vẫn để 5,0×** cho mọi engine và chấp nhận; muốn nghe rất nhanh mà không hụt thì dùng tổ hợp `tốc độ tổng hợp 2,0 × tốc độ phát 2,5`.
- **Xoá dead code `AVAudioEngine`**: xoá file `TTSAudioEngineController.swift` (**77** dòng) + 4 stored property + `setupAudioEngine()` + 2 subscription `.AVAudioEngineConfigurationChange` + `handleEngineConfigChange()`. Grep toàn `Sources/`: `audioEngineController.play()/pause()/stop()` **không có caller**, `playerNode` **không** có `scheduleBuffer` — graph được dựng nhưng **chưa từng phát tiếng** (audit doc-sync cũ đã ghi nhận điều này). Vì `audioEngine` chỉ còn dùng để subscribe nên `handleEngineConfigChange` trên thực tế là no-op. **Giữ** `TTSAudioSessionController`.
- **Xoá đường `synthesizeStream` chết**: protocol requirement ở `LocalTTSEngine` + 2 implementation + `ONNXPiperEngine.synthesizeStream` + `buildSilenceStreamingPayload` + `SilenceStreamingPayload` + `PiperSynthesisCoordinator.enqueue`. Grep xác nhận **0 caller** — đường phát thật (`playNghiTTS`) dùng `synthesizeWithDuration`. Kéo theo: `TTSPCMChunkPayload`, `ChunkPayloadHandler`, tham số `onChunkPayload` của `synthesizeInternal` + nhánh dùng nó, nhãn `streaming` trong `makeDefaultSynthesisKey` (khoá cache **không đổi** vì đường không-stream vốn đã dùng `engine: "nghitts"`), và field `VieNeuTTSEngine.Output.samples` (chỉ tồn tại cho stream ⇒ nay không còn giữ một mảng `[Float]` lớn mỗi lượt tổng hợp). **Giữ** `cachedSilence` + `SilenceSpec` — `makeSilenceSpec` còn dùng.
- **Sửa `resume()` mất vị trí của engine remote.** Bỏ luật *"pause quá 5 giây thì đọc lại từ đầu đoạn"* — luật này ra đời cho `AVAudioPlayerNode` (lý do ghi trong `CHANGELOG.archive.md`: *"OS giải phóng bộ đệm của `AVAudioPlayerNode` trong nền"*), tức cái bẫy **chỉ có ở player node**. Nay `play()` tiếp đúng vị trí nên người dùng không phải nghe lại tới ~17 giây. **Bù lại** thêm `verifyRemoteResumeProgress` (`TTSManager+Playback.swift`): sau `play()` trả `true`, chờ 250 ms rồi kiểm `currentTime` có tiến; không tiến ⇒ rơi về `speakCurrent()`, chặn đúng failure mode "`play()` trả true nhưng không ra tiếng". Bỏ luôn `lastPausedTime` (không còn chỗ đọc).
- **Thêm log đo gap remote**: `[TTSPerf] RemoteHandoff engine=… index=… gapMs=…`, mốc lấy ở `audioPlayerDidFinishPlaying`; tương ứng mốc `🔊 [TTSPerf] NghiHandoff` đã có cho local. **Chưa** làm `prepareNext` cho remote — phải có số đo trước (plan §6).
- **Nợ nhỏ**: `speakCurrent` và **3 chỗ nữa** cùng khuôn (`scheduleNghiWarmUp`, `playbackParagraphs`, `updatePlaybackParams`) đổi từ viết thẳng `tool == "nghitts" || tool == "vieneu"` sang `TTSManager.isLocalEngine(tool)` — đúng quy ước ở `TTSManager+VieNeu.swift:43-44`; `stopPlayback` bỏ 2 cặp lệnh gọi trùng (`clearPrefetchCache()`, `siriService.stop()`).
- **Kiểm chứng**: `check_architecture.py` **5 violation nền cũ, 0 mới**. **Không build tại chỗ** (Windows, không có `swiftc`) — CI xác nhận biên dịch. `xcodegen generate` do CI chạy; `project.yml` dùng glob `- path: Sources` nên không phải sửa.
- Ảnh hưởng dòng: `TTSManager.swift` **3970 → 3956** · `PiperTTSService.swift` **356 → 255** · `VieNeuTTSService.swift` **398 → 323** · `ONNXPiperEngine.swift` **469 → 425** · `VieNeuTTSEngine.swift` **400 → 396** · `PiperSynthesisCoordinator.swift` **339 → 322** · `TTSManager+Interruption.swift` **116 → 88** · `TTSManager+Playback.swift` **284 → 328** · `LocalTTSEngine.swift` **81 → 71** · `NghiAudioPlayerQueue.swift` **288 → 291** · `TTSSettingsView+Voice.swift` **90 → 93** · `TTSAudioEngineController.swift` **xoá (77)** · `TTSSpeedPolicy.swift` **31 (mới)**.

## [1.3.477] - 2026-10-07

### chore: nghỉ hưu tài liệu đồ thị cấu trúc CodeGraph, chuyển sang công cụ codegraph MCP

- Xoá 9 tài liệu đồ thị cấu trúc (`00_index`, `02_file_graph`, `03_type_graph`, `04_call_graph`, `09_dependency_rules`, `11_subsystems`, `12_ownership_graph`, `13_resource_lifecycle`, `14_complexity_report`), 3 file validator (`validate_links.py`, `manifest.json`, `codegraph.schema.json`) và 6 tài liệu prose hành vi (`01_project`, `05_state_graph`, `06_event_graph`, `07_dataflow`, `08_lifecycle`, `10_risk_report`) trong `Docs/CodeGraph/`. Giữ lại `rules.md` (quy chuẩn kỹ thuật) và `CHANGELOG.md`/`CHANGELOG.archive.md` (audit trail).
- Thay thế bằng công cụ **`codegraph`** (Rust/Node, 100% local, MCP `codegraph serve --mcp`): `codegraph init` build index `.codegraph/` (670 file, 13.331 nodes, 27.880 edges). Truy vấn cấu trúc qua `codegraph_explore` MCP hoặc CLI `codegraph explore` — một lần gọi thay vì đọc doc MB. MCP đã wire cho WorkBuddy (`~/.workbuddy-ai/mcp.json`), Claude Code, Codex và Antigravity (`codegraph install --target=claude,codex,antigravity`).
- Cập nhật `AGENTS.md`, `CLAUDE.md`, `.agents/AGENTS.md` bỏ cổng `validate_links.py`, ưu tiên `codegraph` cho mọi truy vấn cấu trúc; giữ kỷ luật `CHANGELOG.md [1.3.NNN]` và cụm kết thúc `"CodeGraph updated."` / `"No CodeGraph update required."`.
- Đảm bảo mang sang máy mới: commit `codegraph.json` (`exclude`/`deprioritize`) vào repo để clone có config index; thêm mục 'Thiết lập trên máy mới / checkout mới' vào `AGENTS.md`/`CLAUDE.md`/`.agents/AGENTS.md` — codegraph **không** tự build index (phải `codegraph init` thủ công, agent không tự chạy); `codegraph install` không hỗ trợ WorkBuddy nên tự tạo `~/.workbuddy-ai/mcp.json` dùng `"codegraph"` qua PATH thay absolute path.
- **Kiểm chứng**: `check_architecture.py` giữ **5 violation nền cũ, 0 mới** (script không đọc doc). `codegraph explore "how does TTSManager initialize?"` trả 82 symbols / 8 files + source verbatim.

## [1.3.476] - 2026-10-07

### feat: cover ghep host qua cleanAndResolveUrl, widget trinh duyet thanh nut tron, metadata plugin.json vao man cau hinh ext

Người dùng: 3 nhóm yêu cầu (chốt qua grill-me, 6 câu hỏi + 3 vòng mockup).

- **R1 — cover thiếu host dùng `cleanAndResolveUrl`**: `ExtensionManager` đọc `cover` **nguyên văn** ở ba chỗ — `search` (`:375`), `detail` (`:420`), `executeCustomScript` (`:737`) — trong khi URL trang thì có ghép host (`:397`). Cover tương đối (`/uploads/1.jpg`) vào DB dạng thô rồi `ImageCacheManager.downloadAndSaveCover` fail vì `URL(string:)` không có host. Nay cả ba đi qua `JSExecutor.cleanAndResolveUrl(cover, host: dict["host"])`. Chọn `host` do **JS trả về** (không phải `metadata.source`) vì `search`/`executeCustomScript` **không có** tham số host nào khác trong chữ ký. Ba call site đổi **tại chỗ** (`ExtensionManager` **1015 → 1018**, trần ratchet 1022) — không file mới, không tham số mới. Không backfill truyện đã có trong DB: truyện cũ tự lành khi mở lại màn chi tiết (chỗ đó ghi đè `coverUrl`).
- **R2 — widget trình duyệt thành nút tròn 36px**: pill `safari` + "N tab" (cao 38, rộng 74–240 theo `sizeThatFits`, **không** có trạng thái thu gọn) → nút tròn đúng khuôn `NotificationFloatingWidgetButton`: bung = badge **số tab** (`> 99` ⇒ `99+`), dán mép = **chấm đỏ 9px**, badge **lật phía** theo mép, kéo + snap cạnh gần nhất, **tự thu sau 3 giây**. Giữ nguyên hai key UserDefaults cũ (`visibleBrowserReopenVerticalRatio`/`visibleBrowserReopenEdge`) nên vị trí đã lưu không nhảy. Giữ nhịp nháy đỏ khi tab thu nhỏ quá 10 giây — thể hiện bằng **màu** (nội suy đỏ sẫm ↔ đỏ tươi, alpha luôn 1) vì `BrowserFloatingWidgetUIWindow.hitTest` có guard `alpha > 0.01`. Level cửa sổ giữ `alert - 2`, `BrowserFloatingWidgetWindowManager` **không đổi**.
- **R3 — metadata `plugin.json` vào màn cấu hình ext, sửa là áp dụng ngay**: file mới `ExtensionMetadataSection` (**284** dòng) hiện **9 trường** của `metadata`; sửa được **6** (`name`, `source`, `regexp`, `description`, `locale`, `type`), chỉ đọc **3** (`author`, `version`, `language`). `locale`/`type` là Picker với bộ **2** giá trị theo yêu cầu (`vi_VN`/`zh_CN`, `novel`/`chinese_novel`) **cộng** giá trị đang có trong file nếu nó ngoài bộ (`tts`, `comic`, `en_US`) — thiếu nhánh này là lần lưu kế tiếp ghi đè mất giá trị thật. `description` là ô rộng nhiều dòng (`axis: .vertical`).
- **"Áp dụng ngay" gồm ba việc, không một**: (1) ghi `plugin.json` qua `ExtensionMetadataEditor` (mới, **135** dòng) — **merge** đúng các khoá đổi, giữ nguyên `config` và khoá script, và theo đúng luật `json["metadata"] ?? json` nên file phẳng thì sửa ở gốc; (2) cập nhật hàng `Extension` qua `ExtensionTransactionCoordinator.updateExtensionMetadata` (mới, **289 → 327**) với `UpdateExtensionMetadataCommand` (mới, **40** dòng) — để lưới home trình duyệt (`ext.sourceUrl`), danh sách Tiện Ích và bộ lọc đổi ngay; (3) **xoá `BypassWebView.regexpCache`** khi `regexp` đổi (`BypassWebView` **378 → 388**) — cache đó là `private static` khoá theo `localPath` và **không có đường xoá** trước lượt này, nên thiếu bước 3 là regexp mới chỉ có hiệu lực sau khi mở lại app.
- **Vì sao có command riêng**: nhánh cập nhật của `UpsertExtensionCommand` gán `existing.version = command.version` **vô điều kiện** và bỏ qua **mọi** giá trị rỗng ⇒ dùng lại là phải truyền kèm `version`/`downloadUrl` hiện tại để khỏi ghi đè, và **không xoá được** `source`/`desc`.
- **Ô chữ debounce 0,4 giây, Picker lưu ngay**: ghi `plugin.json` mỗi phím gõ là I/O đĩa trên luồng chính từng ký tự, và một lượt chạy JS xen vào sẽ đọc phải giá trị đang gõ dở. Chỉ ghi khi giá trị **thật sự** khác bản đã nạp — nếu không, lượt `onChange` do `load()` bắn ra sẽ biến `language: "javascript"` thành `locale: "javascript"` (vì `read` có nhánh dự phòng `metadata.language`, đúng luật 4 reader khác).
- **Nhãn về một chỗ**: `FilterSheet` **97 → 79** bỏ `translateType`/`translateLocale`, dùng `ExtensionDisplayCatalog` (mới, **49** dòng). Bản `translateType` ở `RepositoryManagerView+Actions:177` **giữ nguyên** vì nhãn của nó ngắn hơn có chủ ý ("Truyện chữ" thay vì "Truyện chữ (Novel)") cho chip cỡ 9pt.
- **Kiểm chứng**: `check_architecture.py` **5 violation nền cũ, 0 vi phạm mới**; `validate_links.py` PASS 100% sau khi accept 9 doc. **Không build tại chỗ** (Windows) — `swiftc -parse` sạch trên cả 12 file; CI xác nhận biên dịch.
- Ảnh hưởng dòng: `ExtensionManager` **1015 → 1018** · `ExtensionTransactionCoordinator` **289 → 327** · `BypassWebView` **378 → 388** · `ExtensionConfigView` **278 → 282** · `FilterSheet` **97 → 79** · `VisibleBrowserReopenViewModel` **61 → 129** · `VisibleBrowserReopenView` **80 → 121** · `BrowserFloatingWidgetContainerViewController` **199 → 251** · `ExtensionMetadataSection` **284** (mới) · `ExtensionMetadataEditor` **135** (mới) · `ExtensionDisplayCatalog` **49** (mới) · `UpdateExtensionMetadataCommand` **40** (mới).

## [1.3.475] - 2026-10-07

### feat: man Khoi phuc hien ngay khi cham nut bang khung xuong, doc file o nen

Người dùng: *"khi bấm nút khôi phục màn hình khôi phục hiển thị quá chậm, hãy hiển thị ngay khi bấm nút bằng skeleton view và tiến hành logic ở background, xong thì hiển thị ra"*.

- **Vấn đề**: `BackupHubView.startRestore` chỉ đặt `showingRestoreOptions = true` **sau khi** `await coordinator.prepareRestore(...)` xong — mà việc đó giải nén archive rồi đọc `manifest.json` (vài trăm ms tới vài giây với file lớn). Suốt khoảng ấy người dùng không thấy gì ngoài cú chạm ⇒ nút như không phản hồi. Việc nặng **đã** ở nền từ trước (`BackupRestoreWorker.prepare` chạy trong `Task.detached`); lỗi nằm ở **thời điểm trình bày**, không phải thiếu background.
- **File mới** `Sources/Views/Settings/Backup/RestoreSkeletonView.swift` (**99** dòng): khung xương **sao đúng bố cục** `RestoreOptionsSheet` — một hàng "Tên file" hiện **dữ liệu thật** (đã biết trước nên không cần để xương) + 8 hàng xương, 6 hàng nhóm khôi phục, 2 hàng toggle — nên lúc nội dung thật tới thì chỉ có **chữ hiện ra**, không khung nhảy. Tái dùng `SkeletonView` ở `Views/Common/`.
- **Đổi ở `BackupHubView`** (**221 → 243**): bật sheet ngay từ cú chạm; `restoreSheet` chọn `RestoreOptionsSheet` khi đã có `preparedRestore`, ngược lại vẽ khung xương (thay `ProgressView` trần).
- **Ba nhánh mới, phát sinh vì sheet nay đóng được giữa chừng** (trước đây không thể): (1) người dùng đóng sheet trong lúc đọc file ⇒ `startRestore` gọi `cancelPreparedRestore()` sau khi `prepareRestore` trả về, nếu không thư mục tạm nằm lại tới lượt khôi phục sau; (2) `prepareRestore` lỗi ⇒ đóng khung xương, không để người dùng ngồi nhìn skeleton vĩnh viễn (toast lỗi đã do `MainTabView` lo); (3) `guard !coordinator.isBusy` ở đầu `startRestore` để tránh sheet nháy mở-rồi-đóng khi `prepareRestore` thoát sớm.
- **Nút "Huỷ" vẫn hoạt động** trong lúc đọc file — cố ý: khoá người dùng trong một màn chỉ có khung xương là đúng thứ lượt này đang sửa.
- **Kiểm chứng**: `check_architecture.py` **5 violation nền cũ, 0 vi phạm mới**; `validate_links.py` PASS 100% sau khi accept 5 doc. **Không build tại chỗ** (Windows) — `swiftc -parse` sạch; CI xác nhận biên dịch.
- Ảnh hưởng dòng: `BackupHubView` **221 → 243** · `RestoreSkeletonView` **99** (mới).

## [1.3.474] - 2026-10-07

### fix: rule muc luc mac dinh vuot tran regex 250 cua chinh no (khoi phuc cau hinh bao loi sai)

Người dùng: *"Khôi phục xong nhưng có 1 lỗi: Quy tắc mục lục: Biểu thức chính quy không hợp lệ cho 'Quy tắc mở rộng nâng cao': Độ dài Regex không được vượt quá 250 ký tự.."*.

- **Nguyên nhân (lỗi có từ trước, không liên quan 1.3.472)**: `TranslateUtils.defaultTOCRules.rule21` — tên "Quy tắc mở rộng nâng cao" — có pattern dài **254** ký tự, còn `validateTOCRulePattern` (`TranslateUtils.swift:700` trước lượt này) chặn mọi pattern **> 250**. Tức app tự ship một quy tắc mặc định **vi phạm chính bộ kiểm tra của nó**. Kiểm lịch sử: trần 250 ra đời `5d99d67` (2026-07-28), rule21 được thêm `c3f83ba` (2026-07-30) — vượt đúng **4 ký tự**, và không ai phát hiện vì thêm rule mặc định thì không chạy validator.
- **Đường ra lỗi**: `BackupConfigArchiver.restoreTOCRules` (`:164`) → `TranslateUtils.validateImportedTOCRules` (`:744`) → `validateTOCRulePattern` từng rule → `.failure(.invalidRegex(ruleName:reason:))` → `report.errors.append("Quy tắc mục lục: …")`. Cùng lỗi đó cũng chặn đường **nhập file `toc_rules.json`** và khiến rule21 hiện **"không hợp lệ"** ở màn Quy tắc mục lục (`TOCRulesConfigView:258,276`).
- **Chữa**: rule mặc định được **miễn** trần độ dài. So khớp theo **pattern y hệt** (`isBuiltInTOCRulePattern`), **không** theo `id` — người dùng sửa pattern của rule21 thì bản sửa là dữ liệu người dùng và phải chịu đúng trần 250 như mọi pattern khác. Ngoại lệ đặt ngay trong `validateTOCRulePattern`, là **cửa kiểm tra duy nhất** của cả ba đường, nên không phải vá riêng từng chỗ và các rule mặc định thêm sau này cũng tự được miễn.
- **Không** rút ngắn pattern rule21 (đã cân nhắc và loại): regex đó đang chạy thật để tách mục lục, sửa nó là đổi hành vi tách chương của mọi người dùng — đổi một hằng số an toàn hơn nhiều so với sửa regex đang chạy.
- **File mới**: `Sources/Services/Translation/Utils/TranslateUtils+TOCRuleValidation.swift` (**58** dòng) chứa `isBuiltInTOCRulePattern` + `validateTOCRulePattern`. Bắt buộc tách vì `TranslateUtils.swift` đang ở **916/917** dòng (trần ratchet, chỉ dư một dòng) — sau khi tách còn **911**, đúng chiều ratchet-down. `defaultTOCRules` đổi `private` → `internal` (cùng module) để file extension đọc được, kèm doc ghi rõ vì sao `rule21` dài 254 ký tự là **chủ ý đã chấp nhận**.
- **Kiểm chứng**: `check_architecture.py` **5 violation nền cũ, 0 vi phạm mới**; `validate_links.py` PASS 100% sau khi accept 6 doc. **Không build tại chỗ** (Windows) — `swiftc -parse` sạch; CI xác nhận biên dịch.
- Ảnh hưởng dòng: `TranslateUtils.swift` **916 → 911** · `TranslateUtils+TOCRuleValidation.swift` **58** (mới).

## [1.3.473] - 2026-10-07

### fix: sheet man Thong bao tu widget noi khong nhan duoc cham (thieu nhanh hitTest cho view controller duoc trinh bay)

Người dùng: *"lỗi mở thông báo từ widget không đóng được và bấm vào dropdown không hoạt động"*.

- **Nguyên nhân**: `NotificationFloatingWidgetUIWindow.hitTest` trả `nil` cho **mọi** điểm ngoài `widgetContainerView`. Sheet màn Thông báo được trình bày **từ chính cửa sổ đó** nên view của nó nằm trong cây của cửa sổ, mà lúc sheet mở thì `widgetContainerView` bị `isHidden = true` (trong `setSheetPresented`) ⇒ guard thất bại ⇒ mọi cú chạm trên sheet **rơi xuống app phía dưới**: không bấm được "Đóng", không mở được menu ở góc phải, không vuốt xuống được. Hai triệu chứng người dùng báo là **cùng một** nguyên nhân.
- **Sửa**: thêm nhánh short-circuit `if containerViewController?.presentedViewController != nil { return super.hitTest(point, with: event) }` — đúng khuôn `FloatingWidgetUIWindow` của widget TTS (đã chạy production cho sheet cài đặt TTS).
- **Lỗi thứ hai phát hiện khi rà lại**: `isSheetPresented` chỉ được hạ ở hai đường (vuốt xuống qua `presentationControllerDidDismiss`, và mở truyện qua `openReader`). Nút "Đóng" của màn Thông báo gọi `@Environment(\.dismiss)` — đường lập trình, **không** có callback nào của UIKit ⇒ cờ kẹt ở `true` ⇒ nút nổi **biến mất vĩnh viễn** sau lần đầu đóng sheet bằng nút. Thêm `.onDisappear` trên nội dung sheet làm móc bắt mọi đường đóng; `setSheetPresented` idempotent nên hai cơ chế chồng nhau là an toàn.
- **Kiểm chứng**: `check_architecture.py` **5 violation nền cũ, 0 vi phạm mới**; `validate_links.py` PASS 100% sau khi accept `11_subsystems.md`. **Không build tại chỗ** (Windows) — `swiftc -parse` sạch trên cả hai file; CI xác nhận biên dịch.
- Ảnh hưởng dòng: `NotificationFloatingWidgetUIWindow` **29 → 40** · `NotificationFloatingWidgetContainerViewController` **325 → 333**.

## [1.3.472] - 2026-10-07

### feat: tien do sao luu/khoi phuc va tai model o man Thong bao, widget thong bao noi, bo chan TTS khi khoi phuc

Người dùng: 5 nhóm yêu cầu qua 3 lượt nhắn (chốt qua grill-me, 15 câu hỏi + 2 vòng mockup).

- **R1 — Khối tiến độ ghim ở đầu màn Thông báo**: file mới `Sources/Views/Shelf/ShelfMain/NotificationInboxView+Activity.swift` (**174** dòng) — `extension NotificationInboxView` với `hasActivity` + `activityRows()`, và 4 struct **lồng** (`ActivityRows`, `BackupActivityRow`, `DownloadActivityRow`, `ActivityDismissButton`). Một hàng cho sao lưu **hoặc** khôi phục (chung `BackupCoordinator.progress`, nhãn phân biệt bằng `progress.isRestore`) và một hàng cho **mỗi** lượt tải model. `NotificationInboxView` **393 → 397** dòng: chỉ thêm `activityRows()` vào đầu `List` và đổi `if isEmpty` thành `if isEmpty && !hasActivity` — **không** thêm case vào enum `InboxItem`, vì file đang sát trần 400. Dòng kết quả giữ lại kèm nút "Bỏ qua" (`BackupProgress.isInboxVisible = phase != .idle`, `BackupCoordinator.dismissProgress()`), chỉ sống trong phiên (RAM).
- **R2 — Toast kết quả chuyển lên `MainTabView`**: `MainTabView` **161 → 193** observe `BackupCoordinator.lastMessage` / `lastError` và `ModelDownloadCenter.lastNotice`; `BackupHubView` gỡ hai `onChange` của nó để một lượt không hiện hai toast. Gốc lỗi đã xác minh: `GoogleDriveBackupListView` **chưa bao giờ** observe `lastMessage` nên khôi phục một-chạm từ Drive không có toast, và rời màn giữa chừng cũng mất toast.
- **R3 — Bỏ chặn TTS khi khôi phục**: xoá toàn bộ guard/`.disabled` ở 4 lối vào — `BackupHubView` **235 → 221** (bỏ `@StateObject ttsState`, guard `startRestore`, nhánh footer theo `isPlaying`), `RestoreOptionsSheet` **134 → 121** (bỏ tham số `isTTSPlaying` + khối cảnh báo + `.disabled`), `GoogleDriveBackupListView` **211 → 208**, `LocalBackupListView` **181 → 180**. Đánh đổi đã chấp nhận: khôi phục ghi vào đúng hàng SwiftData mà TTS đang giữ tiến độ; **không** tự dừng TTS.
- **R4 — `ModelDownloadCenter` (mới, `Sources/Services/TTS/`, 276 dòng)**: singleton `@MainActor` **sở hữu `Task`** tải model, chặn lượt trùng bằng `guard tasks[id] == nil`, phát `@Published entries` + `lastNotice`. Chỉ `import Foundation` + `Combine` (không `SwiftUI`, không `ToastManager`). Ba màn tải chỉ còn là người vẽ: `TTSModelManagerView` **478 → 469** (bỏ `downloadingStatus`/`downloadingMessages` + toàn bộ `DispatchQueue.main.async` toast; theo dõi `isBusy` chứ không `entries` để không đọc lại dung lượng 20 giọng mỗi nhịp), `VieNeuTTSTestView` **385 → 369**, `VieNeuVoiceLibraryView` **385 → 368**. Đây là fix cho lỗi "tải chưa xong thoát ra vào lại thì mất thanh tiến độ": `Task {}` trong thân hàm View **không** bị huỷ khi rời màn (chỉ `.task {}` mới bị), nên trạng thái cục bộ mất trong khi việc tải vẫn chạy.
- **R5 — Widget thông báo nổi** (6 file mới ở `Sources/Views/Common/`, lớn nhất `…ContainerViewController` **325** dòng): nút chuông **36px** một cỡ cho cả hai trạng thái, glyph 17pt đúng cỡ chuông toolbar Kệ Sách; bung thì badge **số** (`> 99` → `99+`), dán mép thì badge thu thành **chấm đỏ** và badge **lật phía** theo mép. Kéo tự do, snap cạnh gần nhất, tự thu về peek sau 3 giây, nhớ vị trí qua key riêng (`notificationWidgetVerticalRatio`/`notificationWidgetEdge` — **không** tái dùng `FloatingWidgetViewModel` vì nó hard-code key của TTS). Level cửa sổ `alert - 3` (dưới TTS `alert - 1` và trình duyệt `alert - 2`). Hiện ở mọi màn **trừ tab Kệ Sách** (kể cả Lịch sử / Tải về / Bộ sưu tập), và chỉ khi **có thông báo chưa đọc** hoặc **đang có tác vụ chạy**. Bắt buộc dùng `UIWindow` riêng vì Reader là `fullScreenCover`. Chạm nút ⇒ mở màn Thông báo (`.modelContainer` gắn từ `AppLaunchRootView`); chạm một truyện ⇒ `Notification.Name.openReaderFromNotification` ⇒ `ShelfView` (**859 → 875**) đổi sang tab Kệ Sách và mở Reader. Thêm `Notification.Name.appTabDidChange` để widget biết tab hiện tại.
- **Kiểm chứng**: `check_architecture.py` **5 violation nền cũ, 0 vi phạm mới** (không thêm entry allowlist, không nới baseline nào). `validate_links.py` PASS 100% sau khi accept 13 doc stale. Validator đếm **643 → 651** file Swift. **Không build tại chỗ** (host Windows, `xcodebuild` chỉ chạy trên macOS) — chỉ parse cú pháp bằng `swiftc -parse` trên cả 23 file; CI xác nhận biên dịch.
- Ảnh hưởng dòng: `NotificationInboxView` **393 → 397** · `MainTabView` **161 → 193** · `ShelfView` **859 → 875** · `FreeBookApp` **116 → 122** · `BackupHubView` **235 → 221** · `RestoreOptionsSheet` **134 → 121** · `GoogleDriveBackupListView` **211 → 208** · `LocalBackupListView` **181 → 180** · `BackupProgress` **83 → 113** · `BackupCoordinator` **361 → 371** · `TTSModelManagerView` **478 → 469** · `VieNeuTTSTestView` **385 → 369** · `VieNeuTTSTestView+Sections` **270 → 271** · `VieNeuVoiceLibraryView` **385 → 368** · `VieNeuVoiceLibraryView+Sections` **208 → 209**.

## [1.3.471] - 2026-10-05

### feat: muc so chuong cho pham vi quet ten rieng, component chon so chuong dung chung

Người dùng: *"thêm option chọn số chương vào lọc tên riêng tất cả chương đã tải, tương tự option chọn số chương của tải truyện"* (chốt qua grill-me, 10 câu hỏi).

- **R1 — Component chọn số chương dùng chung**: file mới `Sources/Views/Common/ChapterLimitPickerRows.swift` (**80** dòng) chứa `enum ChapterLimitPicker` với 2 hàm rời `optionPicker(option:)` (picker "Số lượng chương") và `customRow(customLimit:)` (hàng thanh kéo "Tuỳ chọn" 1…1000 kèm nút `-`/`+`), cùng `extension ChapterLimitOption.clampCustom(_:)`. Cố ý để **hai hàm rời** và gọi thẳng trong builder của `Form`, kèm điều kiện `if limitOption == .custom` ở call site, vì `Form`/`List` chỉ tách hàng cho view nằm **trực tiếp** trong builder — gói hai hàng vào một view sẽ dồn picker và thanh kéo vào cùng một ô.
- **R2 — `TaskOptionsSheet` gọi lại component chung**: xoá 4 helper private (`customLimitRow`, `customSliderRange`, `stepButton`, `clampCustomLimit`), file **278 → 217** dòng. Giao diện và hành vi tải/xuất **không đổi** (giữ nguyên thứ tự mốc picker và `.tint(.white)` của Slider).
- **R3 — Sheet quét tên riêng có mục "Số lượng chương"**: `ReaderAIBatchPromptSheet` thêm `@State limitOption` (mặc định `.all`) + `@State customLimit = 100`, đặt trong section "Phạm vi quét" ngay dưới toggle. Giới hạn áp cho **cả hai** chế độ — lấy N chương **đầu tiên** của phạm vi đang chọn. **Không** ghi nhớ giữa các lần mở sheet (toggle vẫn lưu theo `bookId` ở `AINameScanScopeStore`).
- **R4 — Dòng phụ hiện số sau giới hạn**: `effectiveCount = min(limit, available)`; số chương có sẵn vẫn nạp một lần trong `.task` (`nameScanScopeSummary` **không** đổi chữ ký) nên kéo thanh kéo không đọc lại mục lục. Giới hạn lớn hơn số có sẵn ⇒ kẹp, không lỗi, không quét rỗng.
- **R5 — Đường truyền số chương**: `onStart` `(String, Bool)` → `(String, Bool, Int?)` → `beginBatchExtraction(with:fromCurrentChapter:limit:)` → `startBatchExtraction(promptOverride:fromChapterIndex:limit:)` → `AIRuntimeCoordinator.startBatchExtraction(limit:)` → `AINameExtractionBatchProcessor.extractNamesFromDownloadedChapters(limit:)` → `AIBookDataInspector.fetchDownloadedChapters(limit:)` cắt `prefix(limit)` sau khi lọc `from`. Mọi tham số mới đều có giá trị mặc định `nil` ⇒ không vỡ call site cũ.
- **R6 — Nhãn & tên gọi**: tin nhắn timeline ghi số chương (`Quét tên riêng 100 chương đã tải` / `… 100 chương từ chương đang đọc`); không giới hạn thì giữ câu cũ. Tiêu đề sheet → "Quét tên riêng theo phạm vi"; chip `ReaderAIQuickActionChipsView` → "Lọc name nhiều chương".
- **Kiểm chứng**: `check_architecture.py` **5 violation nền cũ, 0 vi phạm mới**; `validate_links.py` PASS 100% sau khi accept 7 doc stale (`00_index`, `02_file_graph`, `04_call_graph`, `09_dependency_rules`, `11_subsystems`, `13_resource_lifecycle`, `14_complexity_report`). Validator đếm **643** file Swift.
- Ảnh hưởng dòng: `ReaderAIBatchPromptSheet` **190 → 227** · `ReaderAIFullScreenView+Actions` **273 → 286** · `AIBookDataInspector` **179 → 189** · `AINameExtractionBatchProcessor` **140 → 143** · `AIRuntimeCoordinator` **322 → 324** · `TaskOptionsSheet` **278 → 217**; `ReaderAIFullScreenView` giữ **384**, `ReaderAIQuickActionChipsView` giữ **52**, `DownloadManager.swift` giữ **467**.

## [1.3.470] - 2026-10-04

### feat: toggle pham vi quet ten rieng tu chuong dang doc, nho theo tung truyen

Người dùng: *"thêm option lọc tên từ chương đang đọc/lọc từ đầu (dùng bật tắt) cho lọc tên truyện các chương đã tải"*

- **R1 — Sheet quét tên riêng có Section "Phạm vi quét"**: `ReaderAIBatchPromptSheet` thêm `Toggle("Từ chương đang đọc")` đặt **trên** Section "Nguồn prompt". Bật ⇒ chỉ quét các chương đã tải có `index >= chapterIndex` trở đi; tắt ⇒ quét toàn bộ chương đã tải (hành vi cũ). `onStart` đổi từ `(String)` sang `(String, Bool)`.
- **R2 — Dòng phụ biết trước phạm vi**: `AIBookDataInspector.nameScanScopeSummary(bookId:fromChapterIndex:)` đếm số chương và lấy tên chương đầu; sheet chạy hai lượt bằng `async let` trong `.task`. Dòng phụ hiện `42 chương — từ ch.108: …` hoặc `Toàn bộ 150 chương đã tải`.
- **R3 — Rỗng thì khoá, không gọi AI**: nếu phạm vi đang chọn không có chương nào đã tải, dòng phụ chuyển đỏ (`Không có chương đã tải từ ch.108 trở đi`) và nút "Bắt đầu quét" bị `.disabled` ⇒ không tốn token cho lượt quét chắc chắn rỗng.
- **R4 — Nhớ theo từng truyện, mặc định bật**: file mới `Services/AI/AINameScanScopeStore.swift` (28 dòng) lưu `[bookId: Bool]` tại UserDefaults `FreeBook_AI_NameScanScope_V1`, mặc định **bật**. Tách khỏi `AISettingsStore` vì `AIConfiguration` là bản ghi chung cho mọi truyện.
- **R5 — Đường truyền tham số**: `beginBatchExtraction(with:fromCurrentChapter:)` → `startBatchExtraction(promptOverride:fromChapterIndex:)` → `AIRuntimeCoordinator.startBatchExtraction` → `AINameExtractionBatchProcessor.extractNamesFromDownloadedChapters(fromChapterIndex:)` → `AIBookDataInspector.fetchDownloadedChapters(fromChapterIndex:)`. Ba hàm có tham số mới **kèm giá trị mặc định** ⇒ không vỡ call site cũ. Tin nhắn timeline đổi theo phạm vi.
- Ảnh hưởng dòng: `AINameExtractionBatchProcessor` **135 → 140** · `AIBookDataInspector` **167 → 179** · `AIRuntimeCoordinator` **320 → 322** · `ReaderAIBatchPromptSheet` **123 → 190** · `ReaderAIFullScreenView+Actions` **271 → 273** · `ReaderAIFullScreenView` **382 → 384**; tổng **642** file Swift. `check_architecture.py`: 5 violation nền, **0 vi phạm mới**.

## [1.3.469] - 2026-10-03

### feat: luu tat ca o man them phien am, nut luu goc phai cho duyet ten rieng va fix thanh tien trinh quet

Người dùng: *"Thêm một option lưu tất cả ở màn hình thêm phiên âm · sửa 2 nút lưu name riêng/lưu vp riêng thành nút lưu ở góc phải gồm 2 option (tương tự màn hình thêm phiên âm) · fix lỗi sau khi quét tên riêng tất cả chương đã tải xong phần hiển thị tiến độ không tự tắt đi."*

- **R1 — `AddWordSheet` Menu Lưu 3 mục ở MỌI chế độ mở sheet**: `Lưu vào NghiTTS` / `Lưu vào VieNeu-TTS` / **`Lưu tất cả`** (ghi cùng một mục vào cả hai từ điển). Trước đây chỉ chế độ mở-từ-Reader mới có Menu 2 mục; hai màn từ điển là `Button` một đích.
- **R2 — nút Lưu của sheet duyệt tên riêng lên thanh điều hướng**: `Menu("Lưu")` 2 mục ở `.confirmationAction` (khuôn `AddWordSheet`), `.disabled(selectedCount == 0)`; dialog **Gộp / Thay thế hoàn toàn** chuyển từ card lên sheet. `ReaderAINameReviewCardView` **327 → 234** dòng, bỏ 2 nút đáy + `onSave` + banner xác nhận (banner chưa bao giờ hiện được vì sheet đóng ngay sau `onSave`).
- **R3 — sửa lỗi thanh tiến trình quét không tự tắt**: `AIRuntimeCoordinator.startBatchExtraction` chỉ hạ `isRunning` mà **không** xoá `batchProgress`; `@Published` phát lại giá trị hiện tại cho subscriber mới nên `(total, total)` sống dậy ở mỗi lần dựng lại màn AI. Nay `batchProgress = nil` ở **cả** nhánh thành công lẫn nhánh lỗi, và `ReaderAIFullScreenView+Actions.onComplete` cũng xoá `batchProgress` cục bộ.
- **File mới `Services/TTS/Preprocessing/PhoneticDictionaryWriter.swift`** (**74** dòng) — một đường ghi phiên âm dùng chung cho cả ba màn (đúng `rules.md` Luật 18). `AddWordSheet.onAdd` đổi tham số thứ 3 `Target` → `PhoneticDictionaryWriter.Destination` ⇒ 3 call site sửa cùng lượt.
- **`ReaderView.swift` 2049 → 2043** (baseline 2053 — chỉ còn 4 dòng dư, nên closure `.sheet` **bắt buộc** ngắn hơn: đây là lý do tách service thay vì chép logic ghi).
- **CodeGraph**: 10 doc cập nhật + `--accept`; `rules.md` thêm **Luật 22** (trạng thái "đang chạy" phải trả về `nil`, không chỉ hạ cờ).
- Cổng: `check_architecture.py` **5 nền / 0 mới**; `validate_links.py` **PASS 100%** (16 doc, 641 file).

---

## [1.3.468] - 2026-10-03

### feat: popup chon prompt cho quet ten rieng toan bo chuong da tai va bo nhanh JSON

Người dùng: *"Giúp tôi sửa lại Quét tên riêng toàn bộ chương đã tải theo đúng dạng prompt, ngoài ra khi bấm vào … hãy popup hỏi người dùng là dùng prompt mặc định hay tự nhập prompt."*

- **Gốc rễ**: `AIConfiguration.defaultNameExtractionPrompt` đã đổi sang dạng `Tên gốc=Nghĩa`, nhưng batch dùng `config.nameExtractionPrompt` — bản **lưu trong UserDefaults** (`AISettingsStore.loadConfiguration`) ⇒ máy từng mở Settings AI vẫn chạy prompt JSON cũ. Tiền lệ di trú: `BookAIMemoryStore.loadGlobalMemory()`.
- **Sheet chọn prompt**: thêm `Views/Reader/AI/ReaderAIBatchPromptSheet.swift` (**123** dòng). Chip "Lọc name cả bộ tải" giờ mở sheet: *Dùng prompt trong Cài đặt* hoặc *Tự nhập prompt* (điền sẵn prompt đang lưu để sửa nhanh). Prompt tự nhập **chỉ dùng cho lần quét đó**, không ghi vào Cài đặt.
- **Di trú prompt**: `AISettingsStore.loadConfiguration()` gọi `migrateLegacyNamePromptIfNeeded(_:)`; chỉ thay khi `AIConfiguration.looksLikeLegacyJSONNameExtractionPrompt` khớp (marker `suggestedMeaning` / `extracted_names` / `JSON hợp lệ`); ghi thẳng UserDefaults, **không** phát notification (tránh tái nhập).
- **Bỏ hẳn nhánh JSON**: `parseNamesFromJSONString` → `parseNamesFromText` (chỉ nhận dòng có dấu `=`); xoá `extractMarkdownBlock` / `cleanTrailingCommas` / `tryParseJSON` ⇒ `AINameExtractionBatchProcessor.swift` **277 → 135**.
- **Dọn nợ**: xoá `ReaderAIFullScreenView.migrateLegacyJSONMessagesIfNeeded()` và dead code `AIRuntimeCoordinator.startExtractNamesCurrentChapter` (0 call site) ⇒ `AIRuntimeCoordinator.swift` **372 → 315**.
- **CodeGraph**: 11 doc cập nhật + `--accept`; lượt này cũng xử lý nợ stale còn lại từ `89dc5f1e`.
- Cổng: `check_architecture.py` **5 nền / 0 mới**; `validate_links.py` **PASS 100%** (16 doc, 640 file).

---

## [1.3.467] - 2026-10-03

### chore: them chunkLen vao log [VieNeuPerf] de do chunkLength ↔ CPU

Thêm `chunkLen=` vào `[VieNeuPerf]` (`VieNeuTTSEngine+Adaptive.logSynthesisPerf`) — số đo còn thiếu để đối chiếu **chunkLength** với CPU/nhiệt/pin/độ mượt. Đọc `TTSManager.vieNeuChunkLength` (`nonisolated static`, không nhảy actor). `[NghiEnergy] Summary` đã có sẵn `busyPct`/`underrun`/`aggregateRTF`; `[TTSEnergy]` đã có `thermal`. Kèm 2 báo cáo trong `Docs/Reports/`: `…-chunklength-cpu-analysis.md` + `…-chunklength-measurement-protocol.md`.

- Cổng: `check_architecture.py` **5 nền / 0 mới**.

---

## [1.3.466] - 2026-10-03

### revert: dua toan bo repo ve moc truoc khi them CoreML + build-ipa chi chay khi Sources/project.yml doi

Revert **toàn bộ** đợt CoreML (bucket tĩnh, thử nghiệm) về đúng mốc `ee3d24fa` — commit ngay trước CoreML đầu tiên. Giữ lịch sử (1 commit revert, không force-push).

- Xoá 12 file `Sources/` + 4 `Scripts/coreml_*.py` + `.github/workflows/convert-coreml.yml`; hoàn nguyên 11 file `Sources/` + `Docs/CodeGraph/`.
- `.github/workflows/build-ipa.yml`: `paths` chỉ còn **`Sources/**` + `project.yml`** (bỏ `.github/workflows/**`) ⇒ CI không build khi chỉ đổi docs/script.
- Bộ máy VieNeu về **ORT duy nhất**; UI về trước CoreML (bỏ toggle "Dùng Core ML" + nav "Model VieNeu"; đường tải model ONNX về `VieNeuTTSTestView`).
- Backup code CoreML ở nhánh **`coreml-bucket-tinh-backup`**.
- Cổng: `check_architecture.py` **5 nền / 0 mới**.

---

## [1.3.465] - 2026-10-02

### feat: them thanh Toc do tong hop cho VieNeu-TTS de giam tai CPU va giam nhiet

Người dùng: *"Tôi muốn tối ưu thêm VieuNeu-TTS để giảm nhiệt, giảm lag"* (ràng buộc cứng: **không ảnh hưởng độ mượt khi nghe**).

- **Gốc rễ tìm được: không engine local nào dùng tốc độ gốc của model.** `TTSManager.swift:2903`/`:3596` và `TTSNextChapterPrefixSynthesizer` đều truyền `speed: 1.0`; tốc độ chỉ áp bằng `AVAudioPlayer.rate` (`NghiAudioPlayerQueue.swift:186`, `enableRate = true` ⇒ varispeed, **đổi cả cao độ**). Trong khi VieNeu có sẵn `secs = exp(log_s)/speed` (`VieNeuTTSEngine.swift:336`) và Piper có `lengthScale = 1/speed`.
- **Vì sao đây là đòn bẩy duy nhất thoả ràng buộc**: lượng tính toán tỷ lệ thuận với thời lượng audio sinh ra, nên tổng hợp ở 1,8× rồi phát 1,0× cho cùng tốc độ nghe mà tốn ít hơn ~45 % tính toán (duty cycle 79 % → ~44 %). Hạ luồng ORT / hạ QoS / tự động theo nhiệt đều là **làm chậm** tổng hợp ⇒ sinh đứt đoạn.
- **Thanh mới "Tốc độ tổng hợp (VieNeu)"** (1,0–2,0, bước 0,1, mặc định 1,0 = hành vi cũ) đặt cạnh thanh Tốc độ trong section *Cấu hình giọng nói*; hiện luôn **tốc độ nghe thực tế** (= tích hai thanh) và đổi màu khi > 2,0×. Màn "Nghe thử" dùng chung cài đặt.
- **Khoá cache**: `TTSSynthesisIdentity.computeKey` nhận thêm `synthesisSpeed` — thiếu thì audio tốc độ cũ được trả cho yêu cầu tốc độ mới.
- **Đổi lúc đang đọc**: phát nốt đoạn hiện tại (`invalidateVieNeuSynthesisSpeed()` huỷ nạp trước, lọc `preloadedData`, `clearPreparedNext()`), áp từ đoạn kế ⇒ không khựng.
- **Trần dòng**: `TTSSettingsView.swift` kẹt **519/519** ⇒ Section 4 chuyển nguyên sang file mới `TTSSettingsView+Voice.swift` (**90**), file chính **519 → 458**. `TTSManager.swift` giữ **3970** (gộp hai dòng tham số để bù).

## [1.3.464] - 2026-10-01

### feat: dat hop thoai Tron/Thay the vao nut nhap vao tu dien sau phien am lai, revert duong nhap tu file va ve lai UI danh sach tron

Người dùng: *"ý tôi là sau khi bấm vào nhấp vào từ điển sau khi phiên âm lại từ điển xong thì hiển thị trộn và thay thế, bạn làm cho chức năng nhập từ file làm gì, ngoài ra UI quá xấu. mocup lại UI phần danh sách trộn"* + *"Đường nhập từ file revert lại ver cũ đi"*.

- **Sửa hiểu nhầm của 1.3.462/463.** Hộp thoại *Trộn / Thay thế toàn bộ* từng gắn vào **đường nhập từ điển từ file**; ý người dùng là nó thuộc **bước áp kết quả phiên âm lại** — tức nút **"Nhập vào từ điển"** ở card màn Thông báo và ở banner màn từ điển.
- **Nút áp dùng chung.** File mới `RephoneticizeApplyButton.swift` (**122**): vẽ nút "Nhập vào từ điển" + `confirmationDialog` hai nhánh; *Thay thế toàn bộ* gọi `RephoneticizeTask.apply()` (hành vi cũ, có `.bak-rephoneticize`), *Trộn* mở `DictionaryImportConflictView`. Một nút cho cả hai chỗ để không bên nào quên bước sao lưu.
- **`RephoneticizeTask.applyMerged(_:)`** — đường áp kiểu trộn. `apply()` và nó cùng đi qua một helper `write(_:)` ⇒ hai đường không thể lệch ở bước sao lưu hay bước dọn file kết quả + meta. `RephoneticizeService.normalizedKey(_:target:)` và `currentWords(for:)` hạ `private` → `internal`.
- **Màn danh sách trộn vẽ lại (hướng C).** Mỗi dòng hai tầng — `khoá` đậm, rồi `cách đọc hiện tại → cách đọc mới` trên **cùng một dòng**; **chạm cả dòng** để chọn/bỏ (bỏ `Toggle`); chip `N trùng · M thêm mới · K giữ nguyên`; ô tìm kiếm + `Chọn hết` / `Bỏ chọn hết`. Màn **tự đọc** từ điển đang dùng trong `Task.detached` (không nhận ảnh chụp từ caller) để mục bị bỏ chọn không bị ghi đè bằng giá trị cũ.
- **Revert 100% đường nhập từ file** về code trước 1.3.462: VieNeu **trộn** (bản nhập thắng), NghiTTS **ghi đè toàn bộ** (ghi plist trực tiếp + `loadResources()`, **không** backup, có lại `parseCSV` riêng). **Xoá** `DictionaryImportFlowModifier.swift`; giữ `DictionaryImportParser` + `DictionaryImportDiff` vì màn trộn dùng.

## [1.3.463] - 2026-10-01

### fix: hop thoai Tron/Thay the toan bo khong hien, chi hien card da phien am lai va banner tien do o man tu dien

Người dùng: *"vì sao nhập từ điển không có 2 option Trộn / Thay thế toàn bộ; bạn đang hiểu nhầm gì không đấy"* + *"ở thông báo từ điển nào phiên âm lại mới hiển thị ra, từ điển không phiên âm hiển thị làm gì"*.

- **Hộp thoại *Trộn / Thay thế toàn bộ* không hiện — lỗi presentation.** 1.3.462 mở hộp thoại bằng `.onChange(of: fileURL)`, tức bật cờ **ngay trong `onPick`**; mà `onPick` của `DocumentPicker` chạy trong **completion của lượt dismiss** sheet chọn file ⇒ presentation bắt đầu giữa lượt dismiss modal bị UIKit/SwiftUI **nuốt im lặng**. Tệ hơn: `fileURL` vẫn còn giá trị nên `.onChange` không thấy đổi ⇒ chọn lại **đúng file đó** cũng không kích hoạt lại. Nay cờ `isModeDialogPresented` do **View gọi sở hữu** và bật trong `onDismiss` của sheet chọn file — hook này chỉ chạy **sau khi** animation đóng xong.
- **Chỉ hiện card của từ điển đã phiên âm lại.** `rephoneticizeRow()` vẽ **cả hai** card vô điều kiện ⇒ từ điển chưa chạy vẫn hiện một dòng "Chưa phiên âm lại" vô nghĩa. Nay mỗi card chỉ vẽ khi `task.isVisible`.
- **Chặn nhầm file hợp lệ ở màn NghiTTS.** Kiểm tra kích thước `resourceValues(forKeys: [.fileSizeKey])` thêm ở 1.3.462 nhưng đọc **ngoài** security scope ⇒ file từ provider (iCloud/Files) ném lỗi, `fileSize` ra 0, chặn nhầm file hợp lệ. Nay bọc trong `startAccessingSecurityScopedResource()` / `stopAccessing`.
- **Banner tiến độ ngay trên màn từ điển.** User: *"hiển thị cả tiến độ phiên âm lại ở màn hình từ điển phiên âm nữa, tương tự màn hình thông báo"*. Thêm `RephoneticizeProgressBanner` — `ViewModifier` gắn qua `.safeAreaInset(edge: .top)`: tiêu đề + `statusText`, `ProgressView(value:)` khi đang chạy, và khi có kết quả thì nút **Nhập vào từ điển** / **Bỏ qua** (nút **Xuất file** để ở màn Thông báo cho banner khỏi che danh sách). Là modifier chứ không viết thẳng vì `VieNeuJapaneseDictionaryView.swift` đang **397/400**; mỗi màn chỉ thêm **một dòng**.
- **File mới**: `Views/Settings/TTS/RephoneticizeProgressBanner.swift` (**127**) · `Views/Settings/TTS/VieNeuJapaneseDictionaryView+Status.swift` (**36** — tách `statusSection` + `JapaneseFlags` khỏi file chính khi nó chỉ còn **1** dòng biên so với trần 400).
- **File sửa**: `DictionaryImportFlowModifier.swift` 144 → **158** (bỏ `.onChange`, `@State showingModeDialog` → `@Binding isModeDialogPresented`), `TTSDictionaryEditView.swift` 518 → **532**, `VieNeuJapaneseDictionaryView.swift` 389 → **374** sau khi tách, `NotificationInboxView+Rephoneticize.swift` 219 → **226**.
- **Ràng buộc đã đo**: `check_architecture.py` **5 violation nền / 0 mới**; `validate_links.py` **PASS 100% (16 doc, 636 file Swift)**. Không build được trên Windows.
- **Tài liệu CodeGraph**: `11_subsystems.md` thêm mục 1.3.463 — **accept**.

---
