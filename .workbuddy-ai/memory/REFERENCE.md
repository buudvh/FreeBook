# FreeBook — sổ tay chi tiết (chuyển từ MEMORY.md, 2026-10-05)

> File này là **bản chi tiết** của các ghi chú dài hạn. `MEMORY.md` chỉ giữ luật cứng + mục lục trỏ về đây.
> Đọc file này khi cần chi tiết về TTS / từ điển / pipeline dịch / backup / hiệu năng Reader.

## Quy trình bắt buộc sau khi sửa code (push-ci-monitor)
Đọc `AGENTS.md` + `.agents/AGENTS.md`. Rồi: (1) `validate_links.py --explain`; (2) sửa **chỉ trong** `<!-- GENERATED START/END -->`; (3) `--accept <doc>` (**1 doc/lần, phải loop**) hoặc `--no-change-needed <doc>`; (4) `CHANGELOG.md` `[1.3.NNN] - YYYY-MM-DD`, tiêu đề **trùng subject commit**; (5) validator read-only **PASS 100%**; (6) kết thúc bằng `"CodeGraph updated."` hoặc `"No CodeGraph update required."`.

## Bẫy môi trường & công cụ
- **Không build trên Windows** ⇒ không bao giờ nói "đã kiểm chứng biên dịch" (CI xác nhận).
- `Scripts/check_architecture.py` **đỏ sẵn** (baseline 30 violation): so trước/sau, chỉ chịu violation **MỚI**. `[PASS]` của script **không phải bằng chứng** (`strip_comments_and_strings` ăn nhầm code thật khi gặp string interpolation — bỏ sót `try? modelContext.save()` thật ở `ShelfView.swift:757`, `BookDetailView.swift:239`).
- **Giới hạn dòng**: file không có trong `architecture_allowlist.json` ⇒ FAIL nếu > **400** dòng vật lý (`check_architecture.py:129`).
- Grep scope `Sources/` (`Tools/` >4000 file → timeout). `00_index.md` lớn → dùng `offset`/`limit`.
- **`validate_links.py` short-circuit khi cây sạch** ⇒ phải chạy `--explain` khi cây ĐÃ có thay đổi.
- **Bẫy doc**: cú pháp chứa `](` (vd `[Float](repeating:)`, regex `[.,](\d+)`) bị hiểu là markdown link ⇒ `broken link`. Viết lại bằng chữ.

## Ràng buộc kiến trúc
- `Sources/Services/**` **không** `import SwiftUI`, **không** `ToastManager` (dùng event AsyncStream / `Result`). Singleton hướng-SwiftUI ở `Sources/Common/**`.
- File Swift mới ≤ **400 dòng**, **1 type chính** top level (extension không tính là type chính). `Sources/Views/**` không `modelContext.insert/delete/save`.
- **Ratchet-down** (không được TĂNG dòng): `TTSManager.swift` 4024/3470 (code mới → `TTSManager+*.swift`); `TextPreprocessor.swift` **đúng 1121** (mọi edit net ≤0); `TTSSettingsView.swift` ~502/519; `SettingsView.swift` 452/453; `BackupCoordinator.swift` 400; `VieNeuTTSEngine.swift` 395/400; `QuickTranslationRuleEngine.swift` 399/400 (chỉ còn 1 dòng — đừng thêm `private static func`, đưa helper sang file `+Extension`).
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

## Từ điển & gộp từ điển
- **Kiến trúc**: từ điển CHÍNH (Chung) = `VietPhrase.dat`; custom = `CustomVietPhrase.txt` + tombstone `deletedVietPhrase`; ghi/merge qua `TranslationDictionaryWriter.mutate(isName:bookId:)` + `DictionaryTextFileStore.mergedRecords` (`Models/Dictionaries/TextDictionary.swift:65`). **Biên dịch text → `.dat`**: `DoubleArrayTrieBuilder.build(fromEntries:toDatFile:)`.
- **§2.3 GỘP TỪ ĐIỂN — ĐÃ CODE** (commit `c4c8718`, CHANGELOG `[1.3.445]`), hướng D: `VietPhrase.dat` + `CustomVietPhrase.txt` (áp tombstone) → **`VietPhraseMerged.txt`** (ghi `.tmp` + `replaceItemAt`), rồi chọn **Nhập vào VietPhrase** / **Xuất file** / **Bỏ qua** ở mục thông báo ghim. Bước gộp **không** sửa từ điển gốc.
  - `TrieDictionary.allEntries()` — khai ở protocol + **cả 3** conformer. Bản `.dat` là DFS **ngược** `trieMatches` (`FrozenTrieDictionary.swift:69`), chỉ mục con dựng 1 lượt theo `check[slot] > 0`. **Bẫy**: slot kết thúc có `check == parent` nên cũng vào chỉ mục con, nhưng `code == 0` và mã ký tự bắt đầu từ 1 ⇒ `codePointByCode[0] == -1` loại tự nhiên — **đừng "sửa" guard này**. Caller phải tự kiểm `count == wordCount`.
  - `DictionaryMergeTask.applyToVietPhrase()` **sao lưu** `.dat` → `VietPhrase.dat.bak-merge` **trước** `importDictionary` (hàm đó xoá file đích rồi biên dịch lại), rồi xoá custom + reload + notify.
  - Mục thông báo **ghim** nhờ không thuộc `NotificationInboxManager`/`NewChapterInboxManager` ⇒ toolbar "Xoá thông báo đã đọc" không xoá được. Icon nhấp nháy = `symbolEffect(.pulse, options: .repeating)`.
  - **Bẫy SwiftUI**: `Section(header: Text(..)) { } footer: { }` **SAI** — phải `Section { } header: { } footer: { }`.
- Tiến độ: `NotificationInboxManager`/`NewChapterInboxManager` + `NotificationInboxView` (335 dòng, `InboxItem` **private** 2 case `newChapter`/`toast`; toolbar "Xoá thông báo đã đọc" không phải "Xoá tất cả").

## Quét tên riêng (AI name scan)
- Vào từ Reader: quick action `extractNamesAllDownloaded` (`ReaderAIQuickActionChipsView`) → `ReaderAIFullScreenView` mở `ReaderAIBatchPromptSheet`.
- `AINameScanScopeStore` (UserDefaults `FreeBook_AI_NameScanScope_V1`) lưu **per-book** toggle "Từ chương đang đọc" (mặc định bật).
- Luồng: `ReaderAIBatchPromptSheet.onStart(prompt, fromCurrentChapter)` → `beginBatchExtraction` → `startBatchExtraction(fromChapterIndex:)` → `AIRuntimeCoordinator.startBatchExtraction` → `AINameExtractionBatchProcessor.extractNamesFromDownloadedChapters` → `AIBookDataInspector.fetchDownloadedChapters(bookId:fromChapterIndex:)` (lọc `isCached && length > 0`, rồi `index >= from`), gom batch 5 chương, gọi AI, gộp theo `original`.
- `AIBookDataInspector.nameScanScopeSummary(bookId:fromChapterIndex:)` trả `(count, firstTitle)` cho dòng tóm tắt trong sheet.
- `ChapterLimitOption` (struct `RawRepresentable`, `Sources/Services/Download/DownloadManager.swift:8`) = `all(0)` / `50/100/200/500/1000` / `custom(-1)` + `customRange 1...1000`; `limitValue` nil = không giới hạn. Dùng ở `TaskOptionsSheet` ("Số lượng chương") + `DownloadTaskModel.limitRaw`.

## Pipeline dịch (rule + tokenize)
- `performTranslation` (`TranslateUtils.swift:477-509`): rewrite rule → **tokenize lại** → tra từng token → `TranslationPunctuationMapper` → `postProcessText`.
- `VietPhraseTokenizer.swift:248-253`: mỗi chữ Hán không khớp Name/VP = **1 token riêng** ⇒ `joined(separator: " ")` cho ra `唐 三` (không gộp). `TranslationTextPostProcessor` chỉ gộp space lặp, KHÔNG gộp 2 hán tự.
- `resolveTokenMeaning` (`:457-470`): hán tự đơn không khớp từ điển → `phienAm[token] ?? token` (phiên âm Hán-Việt).
- Rule engine auto-space 2 bên `rendered` (`QuickTranslationRuleEngine.swift:323-341`; `needs*Separator` `:362-386` chỉ biết whitespace + dấu câu, **không** biết hán tự). Feature do Antigravity làm ở CHANGELOG `[1.3.405]` / commit `00108c6`. **Từ 1.3.444** có ngoại lệ: `rendered` là **hán tự thuần** (`allSatisfy(VietPhraseTokenizer.isChineseCharacter)`) ⇒ **không** chèn space 2 bên (guard `isHanOnly`). `needsSeparator(between:and:)` (nhắc ở 1.3.403) **không còn tồn tại**.
- Nhận diện hán tự: `VietPhraseTokenizer.isChineseCharacter(_:)` (`:341-346`) và `TranslateUtils.containsChinese` (`:80-85`).

## Tiền xử lý số (`TextPreprocessor`, 1.3.439)
- `formatNumbers` chỉ xoá dấu chấm ngăn cách nghìn khi phần nguyên ≠ 0 (giữ `"0.001"`). Regex `decimal`/`percentageDecimal` nhận `[.,]`. `processDecimals`/`processPercentages` đọc phần thập phân **từng chữ số giữ số 0**. `processDigits` đọc số 0 đầu (`"001"`→"không không một") — **KHÔNG** đặt ở `VietnameseNumberSpeller.spell` (sẽ hỏng ngày `"01/02"`).
- `TextPreprocessor+Numbers.swift` = entry `normalizeVietnameseText` cho engine local.

## Hiệu năng Reader (bẫy đã xác minh)
- Đọc `Docs/Reports/` trước (bài cũ đã trôi). `ChapterCache` không trần, chỉ dọn khi Memory Warning. `TranslationWordToken.id` = `UUID()` trong `init` ⇒ `ForEach` không diff được.
- `ReaderEnergyDiagnostics.isEnabled` chốt 1 lần trong `beginReaderSession()` ⇒ bật `AppLogger.isLoggingEnabled` TRƯỚC khi mở Reader.
- `originalSentence` (panel Dịch) là MỘT ĐOẠN VĂN (9–173 ký tự), không phải cả chương ⇒ đo N thật trước khi "sửa O(N) view".
- `FrozenTrieDictionary`: `dat == nil` (customNames/VietPhrase/bookVP/bookNames sau lần lưu đầu) duyệt `lengths` + cấp phát `Array(text.utf16)` mỗi vị trí ⇒ nguồn đốt CPU lớn nhất của pipeline dịch.

## Tài liệu & CHANGELOG
- **CodeGraph dễ bị bỏ quên**: commit `888d4a7` (UI TTS) đã để **10 doc stale** và **thiếu hẳn CHANGELOG entry** — đã dọn ở `a738baa`. Mỗi lượt sửa code phải chạy `validate_links.py --explain` **rồi** `--update-hashes` (accept mọi doc có GENERATED đã đổi) + kiểm `validate_links.py` PASS.
- `.gitignore` chặn `/Docs/Result`, `/Docs/Plans`, `/Docs/CheckList`, `/Docs/Reports` (artifact local, không commit). `Docs/Plan/` (số ít) được track.
- CHANGELOG giữ ~30 entry (đang drift); **thiếu hẳn 1.3.323–1.3.328** ở cả 2 file — **đừng tự đẩy sang archive khi chưa kiểm chứng**.
- Thêm file Swift mới ⇒ `00_index`, `02_file_graph`, `09_dependency_rules`, `14_complexity_report`, `11_subsystems` cùng stale; sửa `Sources/Common/**` ⇒ `03_type_graph` stale.
- `test/` (3 file WAV ~2,8 MB) là artifact test, **untracked** — đừng `git add -A` (sẽ commit nhầm).

## Plan đang mở (CHƯA code)
- `Docs/Plans/2026-09-30-plan-tts-stutter-overlap-battery.md`: **A** (bỏ `play(atTime:)`) đã làm; **B** (gỡ `.scheduled`/`getScheduledStatus`/`ScheduledStatus`/`onScheduleHandoff`/`handleNghiScheduledHandoff`/`nghiScheduledHandoffTask`) **chưa làm — nhắc user**.
- `Docs/Plans/2026-09-30-plan-dict-merge-tts-ui.md`: §2.1 + §2.2-căn-nút + §6 xong (`888d4a7`/`ecae76c`); §7 + §2.2-đồng-bộ xong (`a738baa`, CI `36672708993` SUCCESS, `[1.3.444]`); §2.3 gộp từ điển xong (`c4c8718`, `[1.3.445]`).
- **Màn thử VieNeu đi cùng đường Reader** (`VieNeuTTSTestView.playSample()`): `applyReplacements` → `NghiUtteranceSegmenter.expand(maximumLength: TTSManager.vieNeuChunkLength)` → `synthesizeWithDuration(boundaryKind:)` từng đoạn → `WAVConcatenator.concatenate` → 1 `AVAudioPlayer`. `TTSManager.vieNeuChunkLength` = `nonisolated static` đọc khoá `vieneuChunk` (mặc định 100) — **đừng** dùng `shared.chunkLength`.
