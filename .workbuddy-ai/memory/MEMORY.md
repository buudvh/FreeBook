# FreeBook — ghi chú dài hạn (đã nén)

## Quy ước với người dùng
- **LUẬT CỨNG (user chốt 2026-09-30, "từ nay về sau")**: **mọi yêu cầu thêm / sửa / xoá chức năng PHẢI lập plan trước, chờ user "duyệt" rồi mới sửa code** (dùng `grill-me` → ghi `Docs/Plans/YYYY-MM-DD-plan-<slug>.md`). **Ngoại lệ duy nhất**: yêu cầu **"điều tra"** thuần (chỉ đọc/phân tích, không đổi hành vi) thì được làm ngay. Không tự code khi chưa duyệt.
- Trả lời **tiếng Việt**, thuật ngữ kỹ thuật tiếng Anh inline. Không đoán UI: đọc code view thật, mọi khẳng định cấu trúc dẫn `file:line` (đã sai 2 lần do grep đầu file rồi kết luận cả file).
- Plan → `Docs/Plans/YYYY-MM-DD-plan-<slug>.md`; báo cáo → `Docs/Reports/YYYY-MM-DD-<topic>.md`. **Không** ghi vào `Docs/CodeGraph/`.
- `grill-me`: hỏi từng câu, tự đọc code trước, **KHÔNG code** tới khi user "duyệt"; tự ghi plan. Có **3 bản** (`.claude/`, `.workbuddy/`, `~/.workbuddy-ai/`) — sửa 1 phải copy 2 bản kia.

## Quy trình bắt buộc sau khi sửa code (push-ci-monitor)
Đọc `AGENTS.md` + `.agents/AGENTS.md`. Rồi: (1) `validate_links.py --explain`; (2) sửa **chỉ trong** `<!-- GENERATED START/END -->`; (3) `--accept <doc>` (**1 doc/lần, phải loop**) / `--no-change-needed <doc>`; (4) `CHANGELOG.md` `[1.3.NNN] - YYYY-MM-DD`, tiêu đề **trùng subject commit**; (5) validator read-only **PASS 100%**; (6) kết thúc `"CodeGraph updated."` / `"No CodeGraph update required."`.

## Bẫy môi trường & công cụ
- **Không build trên Windows** ⇒ không bao giờ nói "đã kiểm chứng biên dịch" (CI xác nhận).
- `Scripts/check_architecture.py` **đỏ sẵn** (5 violation nền: `TTSManager`, `ReaderViewModel`, `JSExecutor`, `JSDom`, `ChapterPersistenceStore`): so trước/sau, chỉ chịu violation **MỚI**. `[PASS]` của script **không phải bằng chứng** (`strip_comments_and_strings` ăn nhầm code thật khi gặp string interpolation).
- Grep scope `Sources/` (`Tools/` >4000 file → timeout). `00_index.md` lớn → dùng `offset`/`limit`.
- **`validate_links.py` short-circuit khi cây sạch** ⇒ phải chạy `--explain` khi cây ĐÃ có thay đổi.
- **Bẫy doc**: cú pháp có `](` (vd `[Float](repeating:)` hay regex `[.,](\d+)`) bị hiểu là markdown link ⇒ `broken link`. Viết lại bằng chữ.

## Ràng buộc kiến trúc
- `Sources/Services/**` **không** `import SwiftUI`, **không** `ToastManager` (dùng event AsyncStream / `Result`). Singleton hướng-SwiftUI ở `Sources/Common/**`.
- File Swift mới ≤ **400 dòng**, **1 type chính** top level. `Sources/Views/**` không `modelContext.insert/delete/save`.
- **Ratchet-down** (không được TĂNG dòng): `TTSManager.swift` 4024/3470 (code mới → `TTSManager+*.swift`); `TextPreprocessor.swift` **đúng 1121** (mọi edit phải net ≤0 — từng vượt 1123 và bị revert); `TTSSettingsView.swift` ~502/519; `SettingsView.swift` 452/453; `BackupCoordinator.swift` 400 (extension không ghi được `private(set)` `isBusy`/`progress` trừ khi mở setter); `VieNeuTTSEngine.swift` 395/400.
- Gốc skill: `.agents/skills/` = Antigravity đọc; `.claude/skills/` = Claude Code (`.claude/` gitignored). **WorkBuddy đọc**: `~/.workbuddy-ai/skills/` (user) + `<ws>/.workbuddy/skills/` (project). `<ws>/.workbuddy-ai/skills/` **KHÔNG** được quét.

## Điều hướng app
- **4 tab**: Kệ Sách / Khám Phá / Tiện Ích / Cài Đặt (`MainTabView.swift:12-37`). Không có tab Tìm kiếm.
- Khám Phá ẩn nav bar (`DiscoveryView.swift:346`). BookDetail/RepositoryManager/Shelf/Discovery dùng `TabView(.page)` + cổng `renderedTab` + `asyncAfter(0.15s)` — **không đụng** khi sửa UI.

## Phân hệ Backup
- Bản sao lưu local là bản **tạm**: upload xoá local sau khi đích xác nhận. Bấm tay = 1 archive → 1 đích (muốn cả Drive+Telegram dùng `+AutoDrive`).
- Hai hàng rào xoá khác nhau, đừng "thống nhất": `BackupPaths.isAutoBackupFileName` chặn dọn ngầm; `LocalBackupStore.deleteAll()` cố ý không lọc. `backups/` chứa file tạm worker ⇒ **không xoá cả thư mục**.

## Phân hệ TTS
- Engine = chuỗi `TTSManager.tool` ∈ {`system`, `nghitts` (Piper), `vieneu` (VieNeu Nano), `google`, `<pkg extension>`}.
- **`isLocalEngine` vs `isExtensionTool` khác câu hỏi, đừng gộp**: local = `nghitts || vieneu`; extension = user cài. Quên `isLocalEngine` ⇒ **im lặng**; quên `isExtensionTool` ⇒ **UI kiểu extension**. Bug "phủ định 3 nhánh" đã xuất hiện ≥3 lần ⇒ thêm engine phải grep MỌI danh sách tên engine (gồm `loadParamsForCurrentTool`, `TTSManager.init`, `TTSManager+TranslationIdentity`).
- `playAudioData` **bắt buộc** route engine local → `playNghiAudioData`; đi nhầm nhánh `AVAudioPlayer` ⇒ **không tiếng, không lỗi**.
- Guard danh tính (`isIdentityValid`/`isContextValid`) đặt SAU tổng hợp là bẫy tệ nhất: trả tiền CPU rồi vứt kết quả. `makePlaybackContext(engine:)` phải truyền `tool` (không literal). Synthesis key không hardcode engine.
- `chunkLength` CÓ dùng cho mọi engine local (`playbackParagraphs` → `NghiUtteranceSegmenter.expand`); `prefetchDelayMs` remote-only. `nghittsPrefetchDelay` là Piper-only (đổi sang `isLocalEngine` gây hồi quy).
- **Pitch = no-op với mọi engine local** (task #9, cố ý bỏ): `NghiAudioPlayerQueue` chỉ `updateRate(_:)`; `AVAudioUnitTimePitch` chỉ ở đường `AVAudioEngine`. `disablePitch` phủ engine local.
- **Speed là playback-only** (tổng hợp x1.0): `speed.didSet → updatePlaybackParams` chỉ `updateRate(speed)`, **không** `updateNghiPrefetchWindow`/`cancelNghiWakeTask` (1.3.439 — kéo slider trước đây kích tổng hợp đoạn kế + chương sau).
- **Đệm nóng**: `continueStartSpeaking` (điểm chung fresh start + `applyNextChapter`) → `warmNghiRefillForPlaybackStart()` → `fillNghiRefillUpToCapacity()`; nạp `N+1..N+3` song song đoạn hiện tại.
- **Prefetch pool cần generation đúng (1.3.440)**: `nghiRefillGeneration` CHỈ bump ở `cancelNghiRefill` (đổi ngữ cảnh), **KHÔNG** bump trong `scheduleNghiRefill` — guard `isValidNghiRefillContext` đòi bằng ĐÚNG nên bump mỗi lần làm task cùng batch vô hiệu hoá nhau + rò rỉ (`defer` chỉ dọn khi gen khớp) ⇒ pool chết âm thầm ⇒ gap ở đầu phát/biên chương. Triệu chứng: pool "có vẻ chạy" mà đệm không bao giờ đầy lúc cold start.
- **AVAudioEngine ĐÃ BỊ BỎ — đừng quay lại (tra git 2026-09-30)**: trước 1.3.59 app phát bằng `AVAudioEngine` + `AVAudioPlayerNode.scheduleBuffer`; bỏ ở commit **`423787c`** vì chất âm qua tai nghe Bluetooth + `AVAudioSession OSStatus -50` (mất điều khiển màn hình khoá/Control Center — `9befe9e`/`efbe555`) + rè âm (`bd887df`/`77a3004`). Hiện MỌI engine phát qua `AVAudioPlayer` (`NghiAudioPlayerQueue`). Chồng tiếng hiện do pre-schedule `play(atTime:)` (duration/deviceCurrentTime lệch) — fix = bỏ pre-schedule, KHÔNG quay lại AVAudioEngine.
- **VieNeu mặc định user chốt (2026-09-30)**: **3 đoạn tải trước / 100 ký tự phân đoạn / ngưỡng đệm 10s / mode `fast` (8 bước) / 2 luồng ORT**. "Tiết kiệm pin" = overlay (không ghi đè lựa chọn user): ON ⇒ fast + 2 luồng + **disable** picker chế độ/luồng + thuyết minh. (Kế hoạch trong `Docs/Plans/2026-09-30-plan-tts-stutter-overlap-battery.md` §7.)
- **TTS chồng tiếng/nói lắp — plan CHƯA code (1.3.441)**: `Docs/Plans/2026-09-30-plan-tts-stutter-overlap-battery.md`. `play(atTime:)` + máy móc `.scheduled` là **offline-only** (`NghiAudioPlayerQueue`). **A** (làm trước) = bỏ `play(atTime:)` trong `scheduleNextIfPossible`, **giữ** máy móc. **B** (làm sau khi A ổn) = gỡ `.scheduled`/`getScheduledStatus`/`ScheduledStatus`/`onScheduleHandoff`/`handleNghiScheduledHandoff`/`nghiScheduledHandoffTask`. **NHẮC USER VỀ B.**
- Đường nạp lại/wake còn gate `tool == "nghitts"` ~15 chỗ (1.3.435 đã mở phần lớn qua `currentSafeCachedTimeThreshold`). Extension không thêm được stored property.

## Tiền xử lý số (`TextPreprocessor`, 1.3.439)
- `formatNumbers` chỉ xóa dấu chấm ngăn cách nghìn khi phần nguyên ≠ 0 (giữ `"0.001"`). Regex `decimal`/`percentageDecimal` nhận `[.,]`. `processDecimals`/`processPercentages` đọc phần thập phân **từng chữ số giữ số 0**. `processDigits` đọc số 0 đầu (`"001"`→"không không một") — **KHÔNG** đặt ở `VietnameseNumberSpeller.spell` (sẽ hỏng ngày `"01/02"`).
- `TextPreprocessor+Numbers.swift` = entry `normalizeVietnameseText` cho engine local.

## Hiệu năng Reader (bẫy đã xác minh)
- Đọc `Docs/Reports/` trước (bài cũ đã trôi). `ChapterCache` không trần, chỉ dọn khi Memory Warning. `TranslationWordToken.id` = `UUID()` trong `init` ⇒ `ForEach` không diff được.
- `ReaderEnergyDiagnostics.isEnabled` chốt 1 lần trong `beginReaderSession()` ⇒ bật `AppLogger.isLoggingEnabled` TRƯỚC khi mở Reader.
- `originalSentence` (panel Dịch) là MỘT ĐOẠN VĂN (9–173 ký tự), không phải cả chương ⇒ đo N thật trước khi "sửa O(N) view".
- `FrozenTrieDictionary`: `dat == nil` (customNames/VietPhrase/bookVP/bookNames sau lần lưu đầu) duyệt `lengths` + cấp phát `Array(text.utf16)` mỗi vị trí ⇒ nguồn đốt CPU lớn nhất của pipeline dịch.

## Tài liệu & CHANGELOG
- `.gitignore` chặn `/Docs/Result`, `/Docs/Plans`, `/Docs/CheckList`, `/Docs/Reports` (artifact local, không commit). `Docs/Plan/` (số ít) được track.
- CHANGELOG giữ ~30 entry (đang drift 43+); **thiếu hẳn 1.3.323–1.3.328** ở cả 2 file — **đừng tự đẩy sang archive khi chưa kiểm chứng**.
- Thêm file Swift mới ⇒ `00_index`, `02_file_graph`, `09_dependency_rules`, `14_complexity_report`, `11_subsystems` cùng stale; sửa `Sources/Common/**` ⇒ `03_type_graph` stale.
