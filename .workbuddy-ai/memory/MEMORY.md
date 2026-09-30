# FreeBook — ghi chú dài hạn (đã nén 2026-09-30)

## Quy ước với người dùng
- **LUẬT CỨNG**: mọi yêu cầu **thêm / sửa / xoá chức năng PHẢI lập plan trước, chờ user "duyệt" rồi mới sửa code** (`grill-me` → `Docs/Plans/YYYY-MM-DD-plan-<slug>.md`). **Ngoại lệ duy nhất**: yêu cầu **"điều tra"** thuần (chỉ đọc/phân tích, không đổi hành vi) làm ngay.
- Trả lời **tiếng Việt**, thuật ngữ kỹ thuật tiếng Anh inline. Không đoán UI: đọc code view thật; mọi khẳng định cấu trúc phải dẫn `file:line` (từng sai 2 lần vì grep đầu file rồi kết luận cả file).
- Plan → `Docs/Plans/`; báo cáo → `Docs/Reports/`; **không** ghi vào `Docs/CodeGraph/`.
- `grill-me` có **3 bản** (`.claude/`, `.workbuddy/`, `~/.workbuddy-ai/`) — sửa 1 phải copy 2 bản kia.

## Quy trình bắt buộc sau khi sửa code (push-ci-monitor)
Đọc `AGENTS.md` + `.agents/AGENTS.md`. Rồi: (1) `validate_links.py --explain`; (2) sửa **chỉ trong** `<!-- GENERATED START/END -->`; (3) `--accept <doc>` (**1 doc/lần, phải loop**) hoặc `--no-change-needed <doc>`; (4) `CHANGELOG.md` `[1.3.NNN] - YYYY-MM-DD`, tiêu đề **trùng subject commit**; (5) validator read-only **PASS 100%**; (6) kết thúc bằng `"CodeGraph updated."` hoặc `"No CodeGraph update required."`.

## Bẫy môi trường & công cụ
- **Không build trên Windows** ⇒ không bao giờ nói "đã kiểm chứng biên dịch" (CI xác nhận).
- `Scripts/check_architecture.py` **đỏ sẵn** (baseline 30 violation): so trước/sau, chỉ chịu violation **MỚI**. `[PASS]` của script **không phải bằng chứng** (`strip_comments_and_strings` ăn nhầm code thật khi gặp string interpolation — bỏ sót `try? modelContext.save()` thật ở `ShelfView.swift:757`, `BookDetailView.swift:239`).
- **Giới hạn dòng**: file không có trong `architecture_allowlist.json` ⇒ FAIL nếu > **400** dòng vật lý (`check_architecture.py:129`). File đang sát trần: `QuickTranslationRuleEngine.swift` **398/400** (chỉ thêm được ≤2 dòng) — nên đặt helper ở file `+Extension` khác hoặc inline.
- Grep scope `Sources/` (`Tools/` >4000 file → timeout). `00_index.md` lớn → dùng `offset`/`limit`.
- **`validate_links.py` short-circuit khi cây sạch** ⇒ phải chạy `--explain` khi cây ĐÃ có thay đổi.
- **Bẫy doc**: cú pháp chứa `](` (vd `[Float](repeating:)`, regex `[.,](\d+)`) bị hiểu là markdown link ⇒ `broken link`. Viết lại bằng chữ.

## Ràng buộc kiến trúc
- `Sources/Services/**` **không** `import SwiftUI`, **không** `ToastManager` (dùng event AsyncStream / `Result`). Singleton hướng-SwiftUI ở `Sources/Common/**`.
- File Swift mới ≤ **400 dòng**, **1 type chính** top level (extension không tính là type chính). `Sources/Views/**` không `modelContext.insert/delete/save`.
- **Ratchet-down** (không được TĂNG dòng): `TTSManager.swift` 4024/3470 (code mới → `TTSManager+*.swift`); `TextPreprocessor.swift` **đúng 1121** (mọi edit net ≤0); `TTSSettingsView.swift` ~502/519; `SettingsView.swift` 452/453; `BackupCoordinator.swift` 400; `VieNeuTTSEngine.swift` 395/400; `QuickTranslationRuleEngine.swift` 398/400.
- Gốc skill: `.agents/skills/` = Antigravity; `.claude/skills/` = Claude Code (gitignored). **WorkBuddy đọc**: `~/.workbuddy-ai/skills/` (user) + `<ws>/.workbuddy/skills/` (project). `<ws>/.workbuddy-ai/skills/` **KHÔNG** được quét.

## Điều hướng app
- **4 tab**: Kệ Sách / Khám Phá / Tiện Ích / Cài Đặt (`MainTabView.swift:12-37`). Không có tab Tìm kiếm.
- Khám Phá ẩn nav bar (`DiscoveryView.swift:346`). BookDetail/RepositoryManager/Shelf/Discovery dùng `TabView(.page)` + cổng `renderedTab` + `asyncAfter(0.15s)` — **không đụng** khi sửa UI.

## Phân hệ Backup
- Bản sao lưu local là bản **tạm**: upload xoá local sau khi đích xác nhận. Bấm tay = 1 archive → 1 đích (muốn cả Drive+Telegram dùng `+AutoDrive`).
- Hai hàng rào xoá khác nhau, đừng "thống nhất": `BackupPaths.isAutoBackupFileName` chặn dọn ngầm; `LocalBackupStore.deleteAll()` cố ý không lọc. `backups/` chứa file tạm worker ⇒ **không xoá cả thư mục**.

## Phân hệ TTS
- Engine = chuỗi `TTSManager.tool` ∈ {`system`, `nghitts` (Piper), `vieneu`, `google`, `<pkg extension>`}.
- **`isLocalEngine` (nghitts‖vieneu) ≠ `isExtensionTool` (user cài)** — đừng gộp. Quên `isLocalEngine` ⇒ **im lặng**; quên `isExtensionTool` ⇒ **UI kiểu extension**. Bug "phủ định 3 nhánh" đã xuất hiện ≥3 lần ⇒ thêm engine phải grep MỌI danh sách tên engine (gồm `loadParamsForCurrentTool`, `TTSManager.init`, `TTSManager+TranslationIdentity`).
- `playAudioData` **bắt buộc** route engine local → `playNghiAudioData`; đi nhầm nhánh `AVAudioPlayer` ⇒ **không tiếng, không lỗi**.
- Guard danh tính (`isIdentityValid`/`isContextValid`) đặt SAU tổng hợp là bẫy tệ nhất: trả tiền CPU rồi vứt kết quả. `makePlaybackContext(engine:)` phải truyền `tool` (không literal); synthesis key không hardcode engine.
- `chunkLength` dùng cho MỌI engine local (`playbackParagraphs` → `NghiUtteranceSegmenter.expand`); `prefetchDelayMs` remote-only; `nghittsPrefetchDelay` Piper-only (đổi sang `isLocalEngine` gây hồi quy).
- **Pitch = no-op với mọi engine local** (task #9, cố ý bỏ). **Speed là playback-only** (`speed.didSet → updatePlaybackParams` chỉ `updateRate(speed)`, KHÔNG kích prefetch/wake — 1.3.439).
- **Đệm nóng**: `continueStartSpeaking` (điểm chung fresh start + `applyNextChapter`) → `warmNghiRefillForPlaybackStart()` → `fillNghiRefillUpToCapacity()`; nạp `N+1..N+3` song song đoạn hiện tại.
- **Prefetch pool cần generation đúng (1.3.440)**: `nghiRefillGeneration` CHỈ bump ở `cancelNghiRefill`, **KHÔNG** bump trong `scheduleNghiRefill` (bump mỗi lần ⇒ task cùng batch vô hiệu hoá nhau + rò rỉ ⇒ pool chết âm thầm ⇒ gap đầu phát/biên chương).
- **AVAudioEngine ĐÃ BỊ BỎ — đừng quay lại** (tra git 2026-09-30): bỏ ở commit `423787c` vì chất âm Bluetooth + `AVAudioSession OSStatus -50` + rè âm. Hiện MỌI engine phát qua `AVAudioPlayer` (`NghiAudioPlayerQueue`). Chồng tiếng do pre-schedule `play(atTime:)` — fix = bỏ pre-schedule, KHÔNG quay lại AVAudioEngine.
- **VieNeu mặc định user chốt**: 3 đoạn tải trước / 100 ký tự phân đoạn / ngưỡng đệm 10s / mode `fast` (8 bước) / 2 luồng ORT. "Tiết kiệm pin" = overlay: ON ⇒ fast + 2 luồng + **disable** picker chế độ/luồng + thuyết minh.
- Đường nạp lại/wake còn gate `tool == "nghitts"` ~15 chỗ (1.3.435 đã mở phần lớn qua `currentSafeCachedTimeThreshold`). Extension không thêm được stored property.

## Plan đang mở (CHƯA code)
- `Docs/Plans/2026-09-30-plan-tts-stutter-overlap-battery.md`: **A** (bỏ `play(atTime:)`) đã làm; **B** (gỡ `.scheduled`/`getScheduledStatus`/`ScheduledStatus`/`onScheduleHandoff`/`handleNghiScheduledHandoff`/`nghiScheduledHandoffTask`) **chưa làm — nhắc user**.
- `Docs/Plans/2026-09-30-plan-dict-merge-tts-ui.md`: §2.3b gộp VietPhrase + §6 rename/xoá Debug Extension + **§7 rule dịch trả về hán tự thuần ⇒ không tự gắn space** (`assemble` `:323-340`, chỉ +1 dòng, không tạo file mới).
- **Kiến trúc từ điển**: từ điển CHÍNH (Chung) = `VietPhrase.dat` (**DoubleArrayTrie đã biên dịch**); custom = `CustomVietPhrase.txt` + tombstone `deletedVietPhrase`; ghi/merge qua `TranslationDictionaryWriter.mutate(isName:bookId:)` + `DictionaryTextFileStore.mergedRecords` (`Models/Dictionaries/TextDictionary.swift:65`). ⇒ Gộp = hợp nhất records rồi **tái biên dịch `.dat`** — **BẮT BUỘC backup + atomic**, dễ mất từ điển nếu sai. **Còn phải đọc** `TranslationDictionaryWriter.mutate` + `publishCustomRecords`. Tiến độ: `NotificationInboxManager`/`NewChapterInboxManager` + `NotificationInboxView` (thêm `InboxItem` case, nhấp nháy, cờ `isPinned` bỏ qua "Xoá tất cả").

## Pipeline dịch (rule + tokenize)
- `performTranslation` (`TranslateUtils.swift:477-509`): rewrite rule → **tokenize lại** → tra từng token → `TranslationPunctuationMapper` → `postProcessText`.
- `VietPhraseTokenizer.swift:248-253`: mỗi chữ Hán không khớp Name/VP = **1 token riêng** ⇒ `joined(separator: " ")` cho ra `唐 三` (không gộp). `TranslationTextPostProcessor` chỉ gộp space lặp, KHÔNG gộp 2 hán tự.
- `resolveTokenMeaning` (`:457-470`): hán tự đơn không khớp từ điển → `phienAm[token] ?? token` (phiên âm Hán-Việt).
- Rule engine auto-space 2 bên `rendered` (`QuickTranslationRuleEngine.swift:323-340`; `needs*Separator` `:361-385` chỉ biết whitespace + dấu câu, **không** biết hán tự). Feature này do Antigravity làm ở CHANGELOG `[1.3.405]` / commit `00108c6`. `needsSeparator(between:and:)` (nhắc ở 1.3.403) **không còn tồn tại**.
- Hàm nhận diện hán tự: `VietPhraseTokenizer.isChineseCharacter(_:)` (`:341-346`) và `TranslateUtils.containsChinese` (`:80-85`).

## Tiền xử lý số (`TextPreprocessor`, 1.3.439)
- `formatNumbers` chỉ xoá dấu chấm ngăn cách nghìn khi phần nguyên ≠ 0 (giữ `"0.001"`). Regex `decimal`/`percentageDecimal` nhận `[.,]`. `processDecimals`/`processPercentages` đọc phần thập phân **từng chữ số giữ số 0**. `processDigits` đọc số 0 đầu (`"001"`→"không không một") — **KHÔNG** đặt ở `VietnameseNumberSpeller.spell` (sẽ hỏng ngày `"01/02"`).
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
