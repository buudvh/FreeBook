# CHANGELOG - Nhật ký Thay đổi CodeGraph FreeBook

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **FreeBook**.

## [1.3.449] - 2026-09-30

### feat: VieNeu thêm chế độ "Thấp" (4 bước) giảm nhiệt

Sửa **5** file (4 Swift + 1 plan):

- **Đòn bẩy thật là SỐ BƯỚC, không phải độ lớn CFG**: `VieNeuTTSEngine.runChunk` hỏi `if tuning.cfg > 0` — **điều kiện nhị phân**, không theo tỉ lệ ⇒ `cfg = 3.0 → 1.5` tiết kiệm **0%**. Mỗi bước vẫn gọi `vector_estimator` **2 lần** khi có CFG ⇒ số lượt/đoạn: `.high` **32**, `.fast` **16**, `.low` **8**. Vòng Euler chiếm ~98% thời gian (`vector 7,60 s | khác 0,14 s` trên 28,01 s audio).
- **`VieNeuSynthesisPolicy`** (122 → **137**): `Mode` thêm case `low`; `tuning(for:)` thêm `Tuning(steps: 4, sway: -1.0, cfg: 3.0)`; `nextMode` thêm `case .low: return nil` (giữ hợp đồng "switch không có `default`", chặn bộ thích nghi tự nâng lên). Doc đầu file "hai chế độ" → "ba chế độ".
- **`VieNeuTTSTestView+Sections`** (218 → **222**): `displayName` thêm `case .low: return "Thấp"`; sửa footer lỗi thời (nêu đủ 32/16/8 lượt, **bỏ** câu về mục "Nhanh nhất" đã bị gỡ từ lâu).
- **`TTSSettingsView+VieNeu`** (179): dòng giải thích thêm một câu về chế độ "Thấp". Picker "Chế độ tạo audio" **không sửa vòng lặp** — `ForEach(Mode.allCases)` tự có case mới.
- **Sửa 3 comment sai `12 → 10`** (việc sửa tài liệu, **không** đổi hành vi): `TTSManager.swift:742`, `TTSManager+NghiPrefetchConcurrency.swift:15`, `Docs/Plans/2026-09-30-plan-tts-stutter-overlap-battery.md:47`. Giá trị 12 chỉ là **placeholder khởi tạo**, bị `applyVieNeuParamsIfNeeded` ghi đè bằng `bufferedSecondsTarget` = **10.0** khi khởi động.
- **Cố ý không làm**: **không** cắt `maxConcurrentNghiRefills` 3→1–2, **không** cắt `optionalCap` 4→2 (hai số này sinh từ chính báo cáo lỗi "đoạn 1→2→3 phải chờ" của người dùng ở `[1.3.438]` — cắt là mở lại lỗi cũ); **không** đụng `VieNeuTTSEngine.swift` (đang đúng trần **400/400**). Toggle "Tiết kiệm pin" giữ nguyên (vẫn ép `.fast`).
- Cổng: `check_architecture.py` **5 violation nền/0 mới**; `validate_links.py` **PASS 100% (16 doc, 614 file Swift)**. **Không build trên Windows** ⇒ CI xác nhận biên dịch.

---

## [1.3.448] - 2026-09-30

### fix: gộp VietPhrase ghi số liệu ra file meta kèm theo, không đọc lại file gộp

Sửa **3** file Swift:

- **Nguyên nhân**: mục gộp ở màn Thông báo đọc `DictionaryMergeTask.resultRecordCount` + `displayDate` **trực tiếp trong `body`**. Sau restart (`lastOutcome` chỉ sống trong RAM), `resultRecordCount` rơi xuống `DictionaryTextFileStore.loadCount(from:)` → `parseRecords` — **đọc cả `VietPhraseMerged.txt` (~1,4 triệu dòng) thành `String`, cắt mảng, dựng `Set<String>`** chỉ để lấy `.count`, **trên main thread** ⇒ đơ app, nghẽn luôn TTS (TTS cần main thread cập nhật highlight). `DictionaryMergeTask.init()` → `refreshFromDisk()` chặn main **ngay lúc mở app**.
- **`DictionaryMergeService`** (123 → **210**): thêm `Meta` (`Codable`, `version` + 4 số + `createdAt`), `mergedMetaFileName` (dẫn xuất từ `mergedFileName`), `mergedMetaURL()`, `writeMeta(_:)` / `loadMeta()` / `deleteMeta()`. `merge(progress:)` ghi meta **sau** khi ghi `.txt`, cùng khuôn nguyên tử `tmp` + `replaceItemAt`. `loadMeta` trả `nil` khi thiếu file / decode lỗi / `version` lạ.
- **`DictionaryMergeTask`** (236 → **216**): thêm `@Published private(set) var meta` + `isMetaMissing`. `summaryCounts`/`resultRecordCount`/`displayDate` nay **thuần RAM** (bỏ hẳn `loadCount` và `attributesOfItem`). `refreshFromDisk` chỉ `loadMeta()` ⇒ chạy thẳng trên `MainActor` an toàn. `finish` đọc lại meta. `applyToVietPhrase` + `discardResult` gọi `deleteMeta()` cùng lượt. **Xoá** `MergeSummary`, `summaryKey`, `persistSummary`, `clearSummary` (bản 1.3.446) + dọn khoá `UserDefaults` cũ trong `init`.
- **`NotificationInboxView+Merge`** (186 → **188**): thêm nhánh `isMetaMissing` hiện *"Số liệu chưa có — gộp lại để cập nhật."* khi có file `.txt` nhưng không có meta (file sinh từ bản app cũ) — **không** parse bù.
- **Cố ý không làm**: cache `hasResult` khỏi `fileExists` — chỉ là syscall `stat` cỡ µs, không phải nguyên nhân, mà cache đòi tự cập nhật ở 5 nơi.
- Cổng: `check_architecture.py` **5 violation nền/0 mới**; `validate_links.py` **PASS 100% (16 doc, 614 file Swift)**. **Không build trên Windows** ⇒ CI xác nhận biên dịch.

---

## [1.3.447] - 2026-09-30

### fix: nút "Nhập vào VietPhrase" mất chữ ở dark mode

Sửa **1** file Swift (`Sources/Views/Shelf/ShelfMain/NotificationInboxView+Merge.swift`):

- **Nguyên nhân**: lượt `1.3.446` để nút ở `.buttonStyle(.borderedProminent)` + `.tint(Color.primary)`. `borderedProminent` **không** tự đảo màu chữ theo tint — nó lấy nền từ tint và luôn đặt chữ theo một sắc sáng cố định (giả định tint là màu đậm/bão hoà). `Color.primary` ở **dark mode** = trắng ⇒ nền trắng + chữ sáng ⇒ **nút rỗng** (ảnh user gửi). `.foregroundStyle(Color(uiColor: .systemBackground))` đặt *bên trong* label không cứu được vì `.buttonStyle` ở ngoài ghi đè.
- **Không thể** chỉ gỡ `.tint(Color.primary)`: `MainTabView` đặt `.tint(.white)` toàn cục nên tint mặc định cũng là trắng, vẫn trắng-trên-trắng.
- **Cách sửa**: bỏ cả hai modifier sai, dùng `.tint` **xanh lá đậm literal** (`Color(red: 0.204, green: 0.780, blue: 0.349)`) + chữ `.foregroundColor(.white)` — theo khuôn tint đậm có sẵn trong repo (`ReaderAINameReviewCardView.swift`), đọc được ở mọi theme, không phụ thuộc tint hệ thống.

---

## [1.3.446] - 2026-09-30

### feat: TTS thay thế từ có tầng riêng theo truyện + làm lại UI mục gộp VietPhrase

Thêm **4** file Swift mới, sửa **17** file Swift trong `Sources/Services/` và `Sources/Views/`:

- **Tầng rule thay thế TTS riêng theo truyện** (`translate/books/<bookId>/character_replacements.json`):
  - **Luật gộp**: rule riêng **đè** rule chung theo `pattern` và đứng trước; rule riêng đang **tắt** vẫn **chặn** rule chung cùng `pattern` (kiểu tombstone) ⇒ tập `pattern` để chặn tính trên **toàn bộ** rule riêng, còn `compile` vẫn lọc `isEnabled`.
  - `applyReplacements(to:bookId:)` — `bookId` có default `nil` nên 8 call site cũ vẫn biên dịch; đã truyền `bookId` thật ở **cả 8** (`playingBookId` cho `TTSManager*`, `key.bookId` cho `TTSChapterPrefetcher` / `TTSNextChapterPrefixCache` / `+GoogleBatch`). `VieNeuTTSTestView` cố ý để `nil` (màn thử không có ngữ cảnh truyện).
  - **Tách file vì trần dòng**: `TTSReplacementManager.swift` 391 → **352** (đưa `compile`/`compileCharacterRun` sang `+PlanCompile.swift`, tầng riêng sang `+BookScope.swift`); `TTSReplacementManagerView.swift` 390 → **362** (đưa định tuyến theo tầng + `ruleRow` sang `+Layer.swift`). Hạ `private` → `internal` cho `ReplacementStep`, `planLock`, `compile`, `ruleRow`, `alertMessage`, `prepareForEdit`.
  - **Cache**: `bookRulesCache` (lock riêng) + `bookPlansCache` (dùng chung `planLock`); đổi rule **chung** ⇒ `rebuildReplacementPlan` gọi `invalidateBookPlans()` để mọi kế hoạch theo truyện dựng lại.
  - **UI**: `TTSReplacementManagerView` nhận `bookId`/`bookName`, tầng riêng **ẩn** "Khôi phục mặc định", thêm section **"Rule chung — lấy vào riêng"** + vuốt "Sang chung"; hub theo truyện thêm section **"Thay thế từ (TTS)"** (mở từ BookDetail và Reader).
  - **Backup/đổi nguồn**: `bookScopedTTSFiles` vào `bookScopedMigrationFiles` (đi theo truyện khi đổi nguồn); `BackupPaths.bookTTSFiles` đi cùng nhóm `dict/books/<slug>/`; khôi phục **tái dùng** `mergeReplacementRules` (hàm gộp JSON đã có). **Không** thêm `BackupScope`.
- **Sheet "Thêm thay thế TTS" khi bôi đen** (`AddTTSReplacementSheet.swift` 79 → **184**):
  - Ô **chuỗi thay thế luôn rỗng** khi mở — bỏ auto-fill ở `init` **và** `onChange(of: pattern)` (đổi hành vi cũ: trước đây điền sẵn từ rule trùng).
  - **Chip gợi ý** cho đúng chuỗi gốc, lấy từ **cả 2 tầng**, badge **R**/**C**, tầng riêng trước; bấm chip ⇒ nhập chuỗi thay thế + đặt công tắc theo rule đó; rule đang **tắt** ⇒ chip **mờ**.
  - **Lưu** = menu **2 mục** (riêng truyện / chung). Closure xử lý đặt ở `ReaderView+RuleTools.swift` vì `ReaderView.swift` ở đúng baseline **2053**.
- **Mục gộp VietPhrase ở màn Thông báo** làm lại theo mockup: nút **Nhập vào VietPhrase** full-width nổi bật, **Xuất file** / **Bỏ qua** ngang hàng, **3 chip** `gốc/sửa/xoá`, giờ ở góc phải, chú thích dài gộp còn 1 dòng; số liệu lưu `UserDefaults` (`vietPhraseMergeSummary`) để chip còn sau khi khởi động lại. `timeLabel` ở `NotificationInboxView` hạ `private` → `internal`.
- Cổng: `check_architecture.py` **5 violation nền/0 mới** (đã bắt 1 violation mới ở `ReaderView.swift` và sửa bằng cách rút closure ra extension); `validate_links.py` **PASS**. **Không build trên Windows** ⇒ CI xác nhận biên dịch.
- Đồng bộ tài liệu cho commit `e85b0b4` trước đó (`DictionaryMergeTask.swift`, `NotificationInboxView.swift`) mà CodeGraph chưa accept.

---

## [1.3.445] - 2026-09-30

### feat: gộp VietPhrase ra file text mới rồi nhập/xuất theo lựa chọn

Thêm **3** file Swift mới, sửa **5** file Swift trong `Sources/Models/`, `Sources/Services/`, `Sources/Views/`:

- **API duyệt từ điển (`TrieDictionary.allEntries()`, `FrozenTrieDictionary.swift` 86 → 183)**:
  - `VietPhrase.dat` là DoubleArrayTrie nhị phân và `TranslationManager.loadAllDictionaries` **xoá** `VietPhrase.txt` sau lần biên dịch đầu ⇒ không còn nguồn text nào để đọc từ điển gốc. Thêm `allEntries()`, khai ở **cả 3** conformer.
  - Kho `.dat` duyệt DFS theo **đúng** phép tính chỉ số của `trieMatches` nhưng chiều ngược; chỉ mục con dựng **một lượt** (gom slot theo `check[slot] > 0`) vì quét `charMap` mỗi nút là O(nút × số ký tự). Slot kết thúc có `code == 0` nên bị loại tự nhiên (mã ký tự bắt đầu từ 1).
- **Gộp ra file text mới (`DictionaryMergeService.swift`, file mới 123 dòng)**:
  - `VietPhrase.dat` + `CustomVietPhrase.txt` (áp tombstone) → **`VietPhraseMerged.txt`**, ghi qua `.tmp` + `replaceItemAt`. **Không** đụng từ điển gốc ⇒ một lỗi ở bước gộp chỉ tạo file sai mà người dùng vẫn xem được trước khi áp.
  - **Tự kiểm** `allEntries().count == wordCount`; lệch ⇒ `enumerationMismatch`, dừng và **không** tạo file.
- **Mục thông báo ghim (`DictionaryMergeTask.swift` 183 dòng + `NotificationInboxView+Merge.swift` 127 dòng)**:
  - Trạng thái lấy từ **file trên đĩa** ⇒ mục còn nguyên sau khi tắt app. Icon `symbolEffect(.pulse, options: .repeating)` khi đang gộp.
  - 3 hành động khi xong: **Nhập vào VietPhrase** (sao lưu `.dat` → `VietPhrase.dat.bak-merge` → `importDictionary` → xoá custom + tombstone), **Xuất file** (`ShareLink`), **Bỏ qua**.
  - Mục **ghim**: không thuộc `NotificationInboxManager` lẫn `NewChapterInboxManager` nên hai hành động toolbar ("Đánh dấu đã đọc hết" / "Xoá thông báo đã đọc") **không** xoá được nó.
- Cổng: `check_architecture.py` **5 violation nền/0 mới**; `validate_links.py` **PASS**. **Không build trên Windows** ⇒ CI xác nhận biên dịch.
- Đồng bộ tài liệu cho commit "Tiết kiệm pin" trước đó (`TTSSettingsView+VieNeu.swift`, `TTSSettingsView.swift`) mà CodeGraph chưa accept.

---

## [1.3.444] - 2026-09-30

### fix: rule dịch hán tự thuần không tự gắn space + màn thử VieNeu đi cùng đường Reader

Thêm **1** file Swift mới, sửa **5** file Swift trong `Sources/Services/` và `Sources/Views/`:

- **Rule dịch không tự gắn khoảng trắng cho hán tự thuần (`QuickTranslationRuleEngine.swift`)**:
  - `assemble` miễn auto-space 2 bên khi `rendered` là **hán tự thuần** (`!rendered.isEmpty && rendered.allSatisfy(VietPhraseTokenizer.isChineseCharacter)`). Rule dạng `唐三=唐三` cho ra đúng `唐三`, không còn ` 唐三 `.
  - Hán tự lẫn dấu câu/space/số/latin ⇒ **vẫn** chèn như cũ, nên `我买了四个苹果` + rule `<n>个 = 4 cái` giữ nguyên `我买了 4 cái 苹果`.
  - File **398 → 399/400** dòng (không có trong `architecture_allowlist.json`) — chỉ còn **1** dòng headroom.
- **Màn thử VieNeu đi cùng đường Reader (`VieNeuTTSTestView.swift` + 2 file extension + `TTSManager+VieNeu.swift`)**:
  - `playSample()` nay chạy đủ ba bước của Reader: `TTSReplacementManager.applyReplacements` → `NghiUtteranceSegmenter.expand(…, maximumLength:)` → `synthesizeWithDuration(boundaryKind:)` cho **từng** đoạn (trước đây gọi một lượt cho cả ô chữ với `boundaryKind` mặc định).
  - `TTSManager.vieNeuChunkLength` (mới, `nonisolated static`): đọc khoá `vieneuChunk` (mặc định 100) — cố ý **không** dùng `shared.chunkLength` vì đó là giá trị của engine đang chọn.
  - Báo cáo RTF **cộng dồn** qua các đoạn; chẩn đoán tách `đoạn` (NghiUtteranceSegmenter) khỏi `chunk engine` (`lastChunkCount`).
  - Footer mục "Kết quả" sửa lại cho đúng đường đi (trước đây mô tả sai).
- **Ghép WAV (`WAVConcatenator.swift`, file mới 56 dòng)**: nối N file WAV PCM16 cùng định dạng thành một file — cắt 44 byte header, nối payload, dựng lại header; kiểm 4 mốc `RIFF`/`WAVE`/`fmt `/`data` và trả `nil` khi lệch khuôn.
- Cổng: `check_architecture.py` **5 violation nền/0 mới**; `validate_links.py` **PASS**. **Không build trên Windows** ⇒ CI xác nhận biên dịch.
- Đồng bộ tài liệu cho thay đổi UI TTS của commit trước (`AISettingsSection.swift`, `TTSSettingsSection.swift`) mà CodeGraph chưa accept.

---

## [1.3.443] - 2026-09-30

### feat: đổi tên "Cài đặt VieNeu TTS" + xoá màn Debug Extension

- **Đổi tên**: nav row ở tab Cài đặt (`TTSSettingsSection.swift`) "Thử giọng VieNeu-TTS" → **"Cài đặt VieNeu TTS"**; `navigationTitle` của `VieNeuTTSTestView` cũng → **"Cài đặt VieNeu TTS"**.
- **Xoá màn Debug Extension**: gỡ nav row (`DeveloperSettingsSection.swift`); xoá **3 file** `ExtensionDebugConsoleView.swift` + `ExtensionDebugEventRow.swift` + `ExtensionDebugTraceReader.swift` (chỉ console dùng). **Giữ** `ExtensionDebugServerView` (row riêng) + `ExtensionDebugEventHub`/`ExtensionDebugEvent` (còn dùng bởi `JSExecutor` + editor toolbar).
- Cập nhật footer Section "Nhà Phát Triển" (bỏ tham chiếu console).
- Cổng: `check_architecture.py` **5 violation nền/0 mới**; `validate_links.py` **PASS**. **Không build trên Windows** ⇒ CI xác nhận biên dịch.

---

## [1.3.442] - 2026-09-30

### feat: mặc định Tiết kiệm pin + đổi tên mode/nhãn UI + gỡ máy móc pre-schedule (B)

Theo yêu cầu user (config hiện tại làm mặc định + sửa UI + làm "B").

### 1) Mặc định mới cho VieNeu
- Ngưỡng nạp bộ đệm **12 → 10 s** (`VieNeuSynthesisPolicy.bufferedSecondsTarget`).
- Số luồng ORT **4 → 2** (`VieNeuSynthesisPolicy.defaultThreadCount`).
- Độ dài phân đoạn **200 → 100 ký tự** (`applyVieNeuParamsIfNeeded` + `resetPrefetchSettings`).
- Số đoạn tải trước giữ 3; chế độ mặc định `.fast`.

### 2) "Tiết kiệm pin" thành overlay + mặc định BẬT
- `VieNeuSynthesisPolicy.isPowerSaving` mặc định **true** khi chưa có khoá; thêm `effectiveThreadCount(from:)` (ON ⇒ 2 luồng).
- ON ⇒ `engine.setRequestedMode(.fast)` + khoá 2 picker; OFF ⇒ `setRequestedMode(nil)` ("Tự động"). Không ghi đè `vieneuPreferredMode`/`vieneuThreadCount`.
- UI `vieNeuReaderSection`: Toggle **lên trên** → Picker **"Chế độ tạo audio"** → Picker **"Số luồng tổng hợp" (2/3/4, không ngoặc)** → dòng giải thích **luôn hiển thị** (kèm thuyết minh khi bật).

### 3) Đổi tên mode
`VieNeuTTSTestView+Sections.swift` `displayName`: **Tự động / Chất lượng cao / Cân bằng** (bỏ "· 16/8 bước").

### 4) Làm "B" — gỡ cụm máy móc pre-schedule
- Queue: xoá `.scheduled`, `getScheduledStatus`, `ScheduledStatus`, `onScheduleHandoff`.
- `TTSManager`: xoá wiring `onScheduleHandoff`, `handleNghiScheduledHandoff`, `nghiScheduledHandoffTask`.
- `TTSManager.swift` **4024 → 3957**; `NghiAudioPlayerQueue.swift` **324 → 288**.

### Số dòng & cổng
`TTSManager.swift` 3957; `NghiAudioPlayerQueue.swift` 288; `VieNeuTTSEngine.swift` 400/400; `TTSSettingsView.swift` 513/519; `VieNeuSynthesisPolicy.swift` ~118.
Cổng: `check_architecture.py` **5 violation nền, 0 mới**; `validate_links.py` **PASS** (04/10/11/rules `--accept`; 03/05/06/08/13 `--no-change-needed`). **Không build trên Windows** ⇒ CI xác nhận biên dịch.

**Còn sót nhỏ**: cờ `nextIsScheduled` trong `NghiAudioPlayerQueue` (luôn `false`) — dọn ở lượt sau nếu cần.

---

## [1.3.441] - 2026-09-30

### feat: bỏ pre-schedule hết chồng tiếng/nói lắp + log phoneme + ưu tiên fast/tiết kiệm pin

Ba lỗi TTS (grill-me chốt phương án): (1) nói lắp "chân tướng" → "chân chân tướng"; (2) chồng tiếng (2 đoạn song song); (3) VieNeu nóng máy/nhanh hết pin.

### 1) Bỏ pre-schedule `play(atTime:)` — hết chồng tiếng + nói lắp
- **Root cause**: `NghiAudioPlayerQueue.scheduleNextIfPossible` lập lịch đoạn kế bằng `nextPlayer.play(atTime: deviceCurrentTime + (duration - currentTime)/rate)`. `duration`/`deviceCurrentTime` ước lượng lệch ⇒ đoạn kế chạy **sớm**, đuôi âm tiết cuối chồng lên đầu đoạn kế.
- **Mô phỏng xác nhận**: cắt chunk **không** nhân đôi text (biên rơi giữa "chân" và "tướng" nhưng tái dựng khớp 100%) ⇒ lỗi ở **tầng phát audio tại biên**.
- **Sửa**: `scheduleNextIfPossible` → rỗng; giữ `nextPlayer` ở `prepareToPlay()`, bàn giao qua `audioPlayerDidFinishPlaying` → `promoteNextAfterCurrentFinished` → `play()`. `NghiAudioPlayerQueue` **368 → 324** dòng. (Cụm `.scheduled`/`onScheduleHandoff`/`handleNghiScheduledHandoff` là dead code — gỡ ở lượt "B", chưa làm.)

### 2) Log chẩn đoán
- `handleNghiAudioTransition`: `[TTSPerf] NghiHandoff prevTail=… nextHead=…` (text ở biên).
- `VieNeuTTSEngine.synthesize` → `logChunkPhonemes` (ở `+Adaptive`): `[VieNeuChunk] i=… text=… phonemes=…` (đường Reader trước đây không log phoneme).

### 3) VieNeu nóng máy/pin
- **Ưu tiên `fast`**: `VieNeuTTSEngine.mode` mặc định `.high` → `.fast`; `upshiftRTF` 0.45 → 0.30 (giảm ~2× tính toán ⇒ mát/pin hơn, chất lượng thấp hơn).
- **"Tiết kiệm pin" (opt-in)** + **số luồng ORT**: `VieNeuTTSService.powerSaving`/`threadCount`; `VieNeuSynthesisPolicy.threadCount(from:)` (giữ type thuần); UI toggle + Picker ở `vieNeuReaderSection` kèm hướng dẫn. `threadCount` áp dụng sau khi **nạp lại engine**.

### Số dòng & cổng
`NghiAudioPlayerQueue.swift` 368 → 324; `TTSManager.swift` net 0 (4024); `VieNeuTTSEngine.swift` 400/400 (đúng trần); `VieNeuSynthesisPolicy.swift` 94 → 114; `VieNeuTTSService.swift` 345; `TTSSettingsView.swift` 513/519.
Cổng: `check_architecture.py` **5 violation nền, 0 mới**; `validate_links.py` **PASS** (04/10/11/rules `--accept`; 03/05/06/08/13 `--no-change-needed`). **Không build trên Windows** ⇒ CI xác nhận biên dịch.

**Cần kiểm chứng máy thật (IPA):** hết chồng tiếng; 1→2→3 liền mạch; gap do bỏ pre-schedule không đáng kể; "Tiết kiệm pin" mát hơn rõ rệt. **Còn nợ "B"**: gỡ cụm `.scheduled`.

---

## [1.3.440] - 2026-09-29

### fix: bump generation mỗi lần schedule làm vô hiệu hoá task nạp trước cùng batch

Người dùng báo 1.3.439 **không sửa được** 2 lỗi: (a) đầu phát chờ giữa đoạn 1→2→3; (b) sang chương chờ giữa tên chương và đoạn 1 (kèm báo thêm: 2 đoạn phát song song).

### Root cause (bug logic xác định, không phải timing)
`scheduleNghiRefill()` bump `nghiRefillGeneration &+= 1` **mỗi lần** gọi (`TTSManager.swift:2835`), nhưng guard `isValidNghiRefillContext` đòi `nghiRefillGeneration == refillGeneration` **bằng ĐÚNG** (`:2745`). `fillNghiRefillUpToCapacity()` lập **3 task cùng batch** (`N+1`, `N+2`, `N+3`) → gen `G+1/G+2/G+3`. Khi task chạy, gen hiện tại đã là `G+3` ⇒ **2 task đầu bị vô hiệu** (guard fail ngay trước bước tổng hợp), chỉ task cuối sống. Tệ hơn, `defer` chỉ dọn khi gen khớp (`:2855`) nên 2 task bị vô hiệu **rò rỉ** trong `nghiRefillTasks`/`nghiRefillInFlightIndices` ⇒ `fillNghiRefillUpToCapacity` dần hết chỗ ⇒ **pool nạp trước nghẽn rồi tắt**. Đây là lý do đệm nóng 1.3.439 (dựa vào pool) không có tác dụng: pool không chạy thật.

Bug lộ ra từ 1.3.438: lượt đó thêm pool đa luồng nhưng để lại bump per-schedule — vốn vô hại khi chỉ có **1** refill (`nghiRefillTask: Task?`), nhưng phá khi có **nhiều** task cùng batch.

### Sửa
Bỏ `nghiRefillGeneration &+= 1` khỏi `scheduleNghiRefill()`. Chỉ `cancelNghiRefill()` (đổi chương/session/seek/engine — gọi từ `clearCurrentParagraphPrefetchCache`) mới bump. Cả batch dùng chung gen ⇒ 3 task đều sống + `defer` dọn đúng ⇒ pool hoạt động.

### Số dòng & cổng
`TTSManager.swift` **4024 → 4024** (net 0: bỏ 1 dòng bump, thêm 1 dòng comment).
Cổng: `check_architecture.py` **5 violation nền, 0 mới**; `validate_links.py` **PASS** (04/10/11/rules `--accept`, 05/06/08/13 `--no-change-needed`). **Không build được trên Windows** ⇒ CI xác nhận biên dịch.

**Cần kiểm chứng lúc chạy:** đầu phát 1→2→3 liền mạch; biên chương tên chương → đoạn 1 liền mạch; chồng tiếng (nếu còn → cần log `[NghiAudioPlayerQueue] schedule` từ máy thật).

---

## [1.3.439] - 2026-09-29

### fix: đọc số thập phân/0 đầu, đệm nóng đầu phát & biên chương, tách speed khỏi prefetch

Bốn lỗi TTS người dùng báo, đã grill-me chốt phương án trước khi code: (A) `0.001` đọc thành `1`, `001` cần đọc `không không một`, `0, 001` (có space) ≠ `0,001`; (B) bắt đầu nghe / giữa đoạn 1→2→3 bị chờ; (C) sang chương mới tên chương đọc ngay nhưng gap trước đoạn đầu; (D) đổi tốc độ phát lại "tạo âm thanh lại".

### 1) Đọc số thập phân & số có số 0 đầu (`TextPreprocessor.swift`)
- **Root cause `0.001` → `1`**: `formatNumbers` dùng `thousandsSeparatedNumber = (\d{1,3}(?:\.\d{3})+)` để xóa dấu chấm (ngăn cách nghìn) ⇒ `"0.001"` khớp → `"0001"` → `spell` → `"1"`. Nay **chỉ xóa chấm khi phần nguyên trước chấm đầu ≠ `0`**; `"0.xxx"` giữ nguyên để rơi vào `processDecimals`.
- Regex `decimal` và `percentageDecimal`: thay dấu phẩy cố định bằng lớp ký tự chấm-hoặc-phẩy để nhận **cả chấm và phẩy**; vẫn space-sensitive ⇒ `"0, 001"` không khớp (giữ thành danh sách).
- `processDecimals` / `processPercentages`: bỏ cắt `^0+` ở phần thập phân, đọc **từng chữ số giữ số 0** ⇒ `"0,001"` → "không phẩy không không một".
- `processDigits`: số có số 0 đầu (vd `"001"`) đọc từng chữ số → "không không một". **Cố ý KHÔNG đặt ở `VietnameseNumberSpeller.spell`** vì `processDates` gọi `spell("01")` cho ngày ⇒ `"01/02"` sẽ thành "không một tháng hai".

### 2) Đệm nóng đầu phát & biên chương
- Thêm `warmNghiRefillForPlaybackStart()` (`TTSManager+NghiPrefetchConcurrency.swift`, ratchet-down) gọi `fillNghiRefillUpToCapacity()`; chèn 1 dòng tại `continueStartSpeaking` (`TTSManager.swift`).
- `continueStartSpeaking` là điểm vào **chung** của fresh start (`startSpeaking`) lẫn sang chương mới (`applyNextChapter`) ⇒ một call site phủ cả hai: tổng hợp trước `N+1..N+3` song song với đoạn hiện tại (đoạn đầu thường lạnh) ⇒ 1→2→3 liền mạch, hết gap ở đầu phát và ở biên chương.

### 3) Tách tốc độ khỏi nạp trước
- Điều tra **cả 4 engine**: **không engine nào tái tổng hợp audio đang phát khi đổi tốc độ** — nghitts/vieneu `updateRate` playback-only (tổng hợp x1.0); system per-utterance; google tổng hợp `speed: 1.0` (`TTSManager+Playback.swift:58`); extension synthesisKey không chứa speed.
- Điểm thừa duy nhất: `updatePlaybackParams` (`:1122`) mỗi nấc kéo slider còn gọi `cancelNghiWakeTask()` + `updateNghiPrefetchWindow()` ⇒ kích tổng hợp đoạn kế + chương sau. Nay nhánh local **chỉ** `nghiAudioPlayerQueue.updateRate(speed)`; vòng `nghiWakeTask` tự hiệu chỉnh đệm theo tốc độ mới.

### 4) Pitch local (task #9) — bỏ
Quyết định grill: giữ **no-op** cho engine local (không thêm `AVAudioUnitTimePitch` vào `NghiAudioPlayerQueue`), giữ `disablePitch` trong UI. Không code.

### Số dòng & cổng
`TextPreprocessor.swift` **1121 → 1120** (net −1: viết lại 4 hàm gọn + ternary 1 dòng để không vượt baseline 1121); `TTSManager.swift` **4024 → 4024** (net 0: +1 call site warmup, −1 dòng ở `updatePlaybackParams`); `TTSManager+NghiPrefetchConcurrency.swift` 46 → 58 (thêm `warmNghiRefillForPlaybackStart`).
Cổng: `check_architecture.py` **5 violation nền, 0 mới**; `validate_links.py` **PASS** (04/10/11/rules `--accept`, 05/06/08/13 `--no-change-needed`). **Không build được trên Windows** ⇒ CI xác nhận biên dịch.

**Cần kiểm chứng lúc chạy (IPA máy thật):** đệm nóng D/F thực sự liền mạch và không trùng tiếng; đổi tốc độ không kích tổng hợp.

---

## [1.3.438] - 2026-09-29

### fix: nạp trước đồng thời VieNeu + safe-window 150ms (chống đứt đoạn ngắn / chồng tiếng)

Người dùng báo: **đoạn văn ngắn đọc xong → đoạn kế không kịp tổng hợp → phải chờ lâu mới nghe tiếp**. Nguyên nhân gốc nằm ở cơ chế nạp trước, không phải engine.

### 1) Đứt đoạn ngắn — root cause: nạp trước BẮT BUỘC tuần tự 1 đoạn
`canScheduleNghiRefill(hasRefillTask:hasRetryTask:)` trả `!hasRefillTask && !hasRetryTask` ⇒ **chỉ 1 lượt refill được phép bay cùng lúc** — nghiêm ngặt tuần tự. VieNeu tổng hợp đắt (`VieNeuSynthesisPolicy.bufferedSecondsTarget = 12`, RTF ~0,29 + chi phí cố định theo chunk) nên một lần nạp trước tuần tự **không bao giờ đi trước kịp** một đoạn ngắn có thời lượng audio ≤ 1 lần tổng hợp ⇒ đúng lỗi người dùng báo. NghiTTS (Piper) tổng hợp gần tức thì nên giữ 1 luồng.

**Sửa (chung cho đường local NghiTTS/VieNeu):**
- Đổi stored prop đơn thành **pool**: `nghiRefillTask: Task?` → `nghiRefillTasks: [Int: Task]`; `nghiRefillInFlightIndex: Int?` → `nghiRefillInFlightIndices: Set<Int>`. `cancelNghiRefill()` lặp huỷ mọi task + xoá cả hai tập.
- `maxConcurrentNghiRefills`: **3** cho `vieneu`, **1** cho `nghitts` (giữ nguyên behaviour Piper).
- File mới **`TTSManager+NghiPrefetchConcurrency.swift`** (46 dòng, ratchet-down): `fillNghiRefillUpToCapacity()` lập lịch tới khi đầy luồng hoặc hết ứng viên (safety counter 32, mỗi task xong `defer` gọi lại `updateNghiPrefetchWindow` nên pipeline tự duy trì).
- `nghiRefillCandidate` thêm bỏ qua chỉ mục **đang bay** (`!nghiRefillInFlightIndices.contains(...)`) + cap optional reserve **4 (vieu) / 2 (nghitts)**.
- Xoá `static func canScheduleNghiRefill` cũ. `scheduleNghiRefill()` → `internal func scheduleNghiRefill() -> Bool` có guard `nghiRefillRetryTask == nil` + in-flight + `nghiRefillTasks.count < maxConcurrentNghiRefills`; đường reuse trong `playNghiTTS` dùng `nghiRefillTasks[index]`.
- `updateNghiPrefetchWindow()` thay khối "nạp 1 rồi return" bằng `fillNghiRefillUpToCapacity()` (cả nhánh đầu và nhánh `cachedTime < threshold`).

### 2) Nâng ngưỡng mặc định VieNeu 8s → 12s
`vieneuSafeCachedTimeThreshold` default `NghiSynthesisPolicy.defaultSafeCachedTimeThreshold` (8) → **12.0**; `applyVieNeuParamsIfNeeded()` fallback khi chưa có `UserDefaults` cũng về `VieNeuSynthesisPolicy.bufferedSecondsTarget` (12) thay vì 8. (Ngưỡng này đã có nơi đọc từ 1.3.435 qua `currentSafeCachedTimeThreshold`.)

### 3) Safe-window 50 → 150ms (chống chồng tiếng)
`NghiAudioPlayerQueue.prepareNextNghiAudioIfPossible` (task #8): `guard wallClockRemaining > 0.050` → `> 0.150`. Lý do: `AVAudioPlayer.duration` có thể ước lượng ngắn hơn thực tế vài ms ⇒ một `startTime` tính sát đích rất dễ rơi **trước** khi đoạn hiện tại kết thúc ⇒ hai đoạn phát song song. Đánh đổi một khoảng nghỉ cực nhỏ lấy việc chắc chắn không bao giờ schedule sớm.

### Số dòng & cổng
`TTSManager.swift` **4028 → 4024** (net −4, nhờ xoá `canScheduleNghiRefill` + gom comment); file mới `TTSManager+NghiPrefetchConcurrency.swift` (46); `TTSManager+VieNeu.swift` (fallback 12s); `NghiAudioPlayerQueue.swift` (comment + guard, ~+2 dòng).
Cổng: `check_architecture.py` **5 violation nền, 0 mới** (`TTSManager` giảm 4 dòng ⇒ an toàn); `validate_links.py` **PASS 16 documents / 609 Swift files** (13 doc được `--accept` bắt kịp luôn nợ cũ từ 1.3.437). **Không build được trên Windows** ⇒ CI xác nhận biên dịch.

**Còn lại (treo):** `vieneuPitch` vẫn no-op — `NghiAudioPlayerQueue` chỉ có `updateRate`, chưa có `AVAudioUnitTimePitch` (task #9); clone giọng (overlay `VieNeuVoiceCatalog` + script Python trích `speaker_encoder/codec_encoder/reference_encoder`, task #10/#11).

---

## [1.3.437] - 2026-09-29

### refactor: gom tien xu ly so VieNeu len service chung

Theo ý người dùng "chỉ dùng tiền xử lý chung (thay thế ký tự Tts)", chuyển mở rộng số/ngày/tháng của VieNeu từ engine lên tầng service để đồng nhất với NghiTTS (Piper).

- **Phát hiện**: cả Piper và VieNeu đều xử lý số qua cùng hàm chung `TextPreprocessor.processVietnameseText`. Piper gọi nó bên trong `preprocess` (tại `PiperTTSService.synthesize`, :195/:341); VieNeu gọi bản mỏng `normalizingForVieNeu` (= `processVietnameseText`, bỏ espeak vì `sea_g2p.bin` không có IPA) ngay trong `VieNeuTTSEngine.synthesize`. `applyReplacements` (thay thế ký tự chung) không xử lý số.
- **Đổi**: xoá lớp gọi riêng trong engine; gọi `TextPreprocessor.normalizeVietnameseText` (đổi tên trung lập, vẫn = `processVietnameseText` không espeak) tại `VieNeuTTSService.executeInternalSynthesis` và `…Stream`. Mọi đường (Reader, prefetch, next-chapter-prefix, thử giọng) đều qua `VieNeuTTSService.shared` nên bao phủ đủ.
- **Tác dụng**: engine VieNeu không còn tự tiền xử lý, đồng nhất với Piper; số/ngày vẫn đọc đúng (bắt buộc vì vocab thiếu chữ số).
- **File**: `TextPreprocessor+Numbers.swift` (đổi tên hàm), `VieNeuTTSEngine.swift` (xoá gọi, net ~-5 dòng, trần 400 an toàn), `VieNeuTTSService.swift` (thêm gọi 2 chỗ).

## [1.3.436] - 2026-09-29

### fix: VieNeu ton trong boundaryKind + sua 4 loi hau kiem dinh

Người dùng cài IPA của 1.3.435 và xác nhận **đã có âm thanh** (hai nguyên nhân gốc đã đúng), rồi báo tiếp 4 vấn đề.

- **"Chọn tốc độ tạo audio không đổi ngay" — lỗi UI, không phải engine.** `Picker` buộc vào một `Binding` đọc thẳng `VieNeuTTSService.preferredMode`; `VieNeuTTSService` là class thường (**không** `@Observable`) nên SwiftUI **không thấy** nó đổi. Setter của `preferredMode` **đã** gọi `engine.setRequestedMode(...)` từ trước, tức engine luôn đúng — chỉ UI stale. Đây là **lần thứ hai** đúng lỗi này (lần đầu ở `VieNeuTTSTestView`, đã ghi vào `rules.md` ở 1.3.421). Sửa theo khuôn đã ghi: `@State var vieNeuSelectedMode` khai ở `TTSSettingsView` (extension không thêm được stored property) + `.onChange` đẩy xuống service; xoá `vieNeuModeBinding`.
- **"Âm thanh đọc dễ mất chữ" — VieNeu bỏ qua `boundaryKind`.** `ONNXPiperEngine` **có** `pauseDuration(for:)` và nối khoảng lặng đuôi vào cuối mỗi utterance (`:436`). `VieNeuTTSService` nhận `boundaryKind` trong chữ ký (`:137`, `:156`) nhưng **chưa bao giờ dùng**. Mà `joinChunks` chỉ chèn khoảng lặng **giữa các chunk nội bộ**, **không bao giờ** cho chunk cuối; mỗi payload lại đã bị `trimAndFade` cắt còn ~40 ms đệm ⇒ phoneme cuối utterance N dính thẳng vào phoneme đầu utterance N+1 ⇒ nghe như **mất chữ**.
  * Thêm `VieNeuTTSEngine.pauseSeconds(for boundaryKind:)` — **bản sao ánh xạ của Piper, đọc cùng khoá `UserDefaults`** (`paragraphPauseDuration` / `sentencePauseDuration` / `phrasePauseDuration` / `bracketPauseDuration` / `newlinePauseDuration`) nên một cài đặt điều khiển cả hai engine.
  * Khoảng lặng chèn thêm **không phải lời đọc** ⇒ cộng vào `insertedPauseSeconds`, nếu không `speechDuration` bị thổi lên và RTF theo lời nói sai.
  * `boundaryKind` cũng vào `makeDefaultSynthesisKey`: nó đổi audio, nên hai lượt cùng văn bản khác ranh giới **không được** gộp (`PiperSynthesisCoordinator` coalesce theo khoá; Piper cũng đưa `boundary=` vào khoá).
  * **Vì sao không lộ ở màn thử giọng**: màn đó đưa **cả đoạn** vào một lượt gọi nên `joinChunks` tự chèn khoảng lặng theo dấu câu. Chỉ đường Reader (cắt trước rồi gọi từng mảnh) mới lộ — đúng lý do người dùng thấy "chất lượng kém hơn hẳn".
- **"Chất lượng kém hơn hẳn màn thử giọng" — nay có số để trả lời, trước đó thì không.** Màn thử giọng hiện mode/chunk/dropped **trên UI**; đường Reader **không có gì** — engine chỉ log **lúc đổi** chế độ và **một lần cho cả vòng đời** cho phoneme bị bỏ. Thêm `logSynthesisPerf` (`+Adaptive`, để `VieNeuTTSEngine.swift` không vượt trần 400) ghi **mỗi lượt**: `mode`, `chunks`, `dropped`, `chars`, `pcm`, `speech`, `synth`, `rtf`, `boundary`. Hai giả thuyết cần số này phân định: (a) bộ thích nghi **hạ xuống `fast`** vì đường Reader có nhiều payload nhỏ ⇒ RTF cao hơn; (b) **cắt hai tầng** — engine tự cắt ở `VieNeuConfig.maxChunkCharacters` = **140**, Reader cắt trước ở `vieneuChunk` (mặc định 200).
- **"Đoạn này chưa đọc xong thì đoạn khác đã đọc song song" — thêm chẩn đoán, KHÔNG đoán bừa.** Cơ chế `play(atTime:)` + `deviceCurrentTime` của `NghiAudioPlayerQueue` rất nhạy thời điểm và **không thể suy ra nguyên nhân chỉ bằng đọc mã**. Lượt này cố ý không đổi hành vi: thêm log `[NghiAudioPlayerQueue] schedule next=… cur=… mediaRemaining=… rate=… wallRemaining=… duration=… currentTime=…` (đủ để thấy `wallRemaining` có bị tính nhỏ đi không ⇒ `nextPlayer` bắt đầu trước khi `currentPlayer` kết thúc), cộng **một chốt an toàn** trong `prepareNextNghiAudioIfPossible`: không nạp lại đoạn mà queue **đang phát** (`currentItem`), vì `currentParagraphIndex` có thể chưa kịp nhảy do bàn giao chạy nền ⇒ `nextIndex` trỏ vào chính đoạn đang phát ⇒ đoạn đó phát **lần thứ hai**.
- **File**: `VieNeuTTSEngine.swift` 370 → **395**, `VieNeuTTSEngine+Chunking.swift` 294 → **323**, `VieNeuTTSEngine+Adaptive.swift` 56 → **84**, `VieNeuTTSService.swift` 282 → **319**, `NghiAudioPlayerQueue.swift` 351 → **364**, `TTSSettingsView.swift` 502 → **509**, `TTSSettingsView+VieNeu.swift` 157 → **151** (xoá `vieNeuModeBinding`), `TTSManager.swift` **4028** (net 0).
- **Ràng buộc đã đo**: `check_architecture.py` giữ nguyên **5** violation nền và **0** vi phạm mới; `validate_links.py` PASS. Không build được trên Windows.
- **Còn lại**: nguyên nhân **chồng tiếng** chưa xác định — cần log từ máy thật. `vieneuPitch` vẫn chưa nghe thấy (queue không có pitch).

## [1.3.435] - 2026-09-29

### fix: mo gate engine local + sua 2 nguyen nhan goc lam VieNeu khong ra tieng

Người dùng báo *"VieNeu tts vẫn không tạo được âm thanh, tôi thấy nó hoàn toàn không tạo ra được wav"* kèm log `app_logs (54).txt`, và ba câu hỏi về UI (2 chỗ config số đoạn tải trước; thời gian dãn tiến trình nạp trước có dùng không; độ dài đoạn văn có dùng không / vì sao hiển thị ra đây).

- **Log là bằng chứng quyết định**: có `[NghiEnergy] Underrun chapter=124 index=12` (chứng tỏ **đã vào** `playNghiTTS`) nhưng **không có** dòng `[TTSRoute] playAudioData …` nào ⇒ audio bị vứt bỏ **sau khi tổng hợp xong**, không lỗi, không toast.
- **Nguyên nhân gốc A — guard danh tính sai.** `isIdentityValid()` trong `playNghiTTS` (`TTSManager.swift:3638`) kết bằng `self.tool == "nghitts"`. Với VieNeu, `service.synthesizeWithDuration(...)` chạy **thật** (vài giây CPU, máy nóng) rồi `guard isIdentityValid() else { return }` (`:3659`) trả `false` ⇒ **vứt bỏ audio vừa tổng hợp**. Sửa: `TTSManager.isLocalEngine(self.tool)`.
- **Nguyên nhân gốc B — context so với literal.** `isContextValid` (`:3120`) đòi `tool == context.engine`, nhưng context dựng bằng `engine: "nghitts"` hardcode ở `:3191` và `:3348` ⇒ luôn `false` với VieNeu. Sửa: `engine: tool` ở cả hai chỗ, và `TTSManager.isLocalEngine(context.engine)` cho nhánh kiểm tra thành viên hàng đợi (`:3124`).
- **Mở ~28 gate `tool == "nghitts"` còn lại sang `isLocalEngine`.** Đáng chú ý:
  * `:99` (`tool.didSet`) — VieNeu **không bao giờ được warm-up** vì nhánh `else` huỷ task trước khi `scheduleNghiWarmUp()` kịp tự guard.
  * `:1448` / `:1481` / `:1525` — `pause()`/`resume()` không tác động lên `nghiAudioPlayerQueue` mà VieNeu đang phát.
  * `:1762` / `:1810` — `nextParagraph`/`previousParagraph` nhảy theo **đoạn văn cha** (`paragraphs[i].paragraphIndex`), không phải utterance; VieNeu cũng đi qua `NghiUtteranceSegmenter` nên cần đúng quy tắc này.
  * `:2491` — `updatePrefetchWindow()` đẩy VieNeu sang **đường remote** (`dispatchRemotePrefetch`).
  * `:3338` — `handleNghiAudioTransition` khi guard sai còn gọi `nghiAudioPlayerQueue.stop()` ⇒ **cắt tiếng giữa chừng** (guard có tác dụng phụ phá hoại).
  * `:2592` `calculateNghiCachedTime`, `:2648` `updateNghiPrefetchWindow`, `:2731`/`:2803`/`:2860`/`:2865`/`:2963`/`:2987` (refill), `:3190` handoff, `:3248` `prepareNextNghiAudioIfPossible`, `:3358` `handleNghiAudioFinished`.
- **Ngưỡng nạp bộ đệm theo engine nay CÓ nơi đọc.** Thêm computed `currentSafeCachedTimeThreshold`, dùng ở `:2674`, `:2714`, `TTSManager+NextChapterPrefix.swift:73`. ⇒ `vieneuSafeCachedTimeThreshold` **có hiệu lực thật** (trước 1.3.435 chỉ được lưu/hiển thị).
- **Synthesis key hardcode `engine: "nghitts"`** ở `:2840` và `:3606` → `engine: tool`. Trước đó khoá tổng hợp của VieNeu và NghiTTS **giống hệt nhau** nếu cùng chương/đoạn/giọng, mà `PiperSynthesisCoordinator` gộp request theo khoá.
- **`TTSManager+NextChapterPrefix.swift`**: `nextChapterPrefixContext()` phải cho **mọi** engine local đi qua `NghiUtteranceSegmenter.expand(..., maximumLength: chunkLength)` — trước đó VieNeu **không** expand nên **lệch chỉ số đoạn văn** giữa chương hiện tại và prefix chương kế; `requestRemoteNextChapterPrefixIfNeeded` phải **loại** engine local (VieNeu từng lọt vào đường remote); `requestNghiNextChapterPrefixIfNeeded` 1 gate. Thêm 1 gate ở `TTSNextChapterPrefixSynthesizer` và 1 ở `TTSNextChapterPrefixCache`.
- **Tham số lúc khởi động**: `TTSManager.init` nạp tham số **trước `super.init()`** (`:953`) nên không gọi được instance method, và chuỗi `if/else` ở đó **thiếu nhánh `vieneu`** ⇒ khởi động app khi đang chọn VieNeu nạp nhầm `extRate_vieneu`/`extPitch_vieneu`/`extVoice_vieneu`. Sửa bằng **một dòng** `applyVieNeuParamsIfNeeded()` trong `initialize(container:)` (gọi từ `MainTabView.swift:57`, trước mọi lượt đọc) — dùng lại **một nguồn sự thật** thay vì chép danh sách khoá lần thứ ba.
- **`TTSManager+TranslationIdentity.swift:8`**: `tool == "system" || tool == "nghitts" || tool == "google"` là **cùng loại bug "phủ định 3 nhánh"** như `isExtensionTool` — VieNeu bị tính `extFingerprint` từ extension rỗng. Sửa thành `!TTSManager.isExtensionTool(tool)`.
- **UI — Picker**: VieNeu lên **vị trí thứ 3** (Siri → NghiTTS → **VieNeu** → Google → extension).
- **UI — hết trùng lặp "số đoạn tải trước"**: Section 3 (`vieNeuReaderSection`) nay **chỉ còn chế độ chất lượng**; số đoạn tải trước / độ dài phân đoạn / ngưỡng nạp bộ đệm dồn về Section 5 qua `vieNeuPrefetchSection`. Trước đó số đoạn tải trước có ở **2 chỗ**, và chỗ ở Section 5 trỏ nhầm `extPrefetchCount` với nhãn *"(Extension TTS)"* vì VieNeu rơi vào nhánh `else` (nhánh extension).
- **UI — trả lời "độ dài đoạn văn có dùng không"**: **CÓ**. `TTSManager.playbackParagraphs` cho `vieneu` đi qua `NghiUtteranceSegmenter.expand(baseParagraphs, maximumLength: chunkLength)` giống Piper; nay nhãn đúng *"Độ dài phân đoạn (VieNeu)"* và khoá `vieneuChunk`.
- **UI — trả lời "thời gian dãn tiến trình nạp trước có dùng không"**: **KHÔNG** với engine local. `prefetchDelayMs` chỉ được tiêu thụ ở `TTSAudioSynthesisWorker` (đường Google/extension); `TTSNextChapterPrefixSynthesizer.one` trả sớm cho engine local bằng `localService.synthesize(...)` **không truyền** tham số này. Stepper nay **ẩn với engine local** (nó đã chết với NghiTTS từ trước).
- **UI — pitch**: engine local phát qua `NghiAudioPlayerQueue` chỉ có `updateRate(_:)`, không có `AVAudioUnitTimePitch` ⇒ pitch là **no-op** với cả NghiTTS và VieNeu. `disablePitch` nay phủ cả VieNeu kèm dòng giải thích (trước đó VieNeu hiện slider bật nhưng bấm không có tác dụng và **không có** dòng giải thích nào).
- **UI — nút "Đặt lại"**: chuỗi `if/else` cũ **thiếu nhánh `vieneu`** nên bấm khi đang chọn VieNeu sẽ ghi vào `extPrefetchCount` và `nghittsPrefetchDelay`. Gom thành `TTSManager.resetPrefetchSettings()`.
- **File**: `TTSManager.swift` 4025 → **4028**, `TTSSettingsView.swift` 517 → **502**, `TTSManager+VieNeu.swift` 183 → **227**, `TTSSettingsView+VieNeu.swift` 128 → **157**, `TTSManager+NextChapterPrefix.swift` 130 (không đổi), `TTSNextChapterPrefixSynthesizer.swift` 113 (không đổi), `TTSNextChapterPrefixCache.swift` 339 (không đổi), `TTSManager+TranslationIdentity.swift` 26 (không đổi).
- **Ràng buộc đã đo**: `check_architecture.py` giữ nguyên **5** violation nền và **0** vi phạm mới; `validate_links.py` PASS. Không build được trên Windows — CI sẽ xác nhận biên dịch.
- **Hạn chế còn lại**: `vieneuPitch` vẫn chưa nghe thấy (queue không có pitch). **Chưa kiểm chứng hành vi lúc chạy** — toàn bộ ~28 gate vừa mở dựa trên suy luận từ việc đọc `nghiAudioPlayerQueue`/`preloadedData` là tài nguyên dùng chung; cần cài IPA lên máy thật để xác nhận audio phát, tự chuyển đoạn, và NghiTTS không hồi quy.

## [1.3.434] - 2026-09-29

### fix: noi VieNeu vao duong phat local + tach khoa tham so theo engine

Người dùng báo *"ipa mới chọn vieneu nhưng nó không hoạt động, không tạo ra được âm thanh. Phần quản lý riêng của trình đọc không có gì cả"*, kèm hai yêu cầu: *"config cao độ, tốc độ, tải trước dữ liệu phải lưu key khác nghitts"* và *"thiếu config fast và high"*.

- **Lỗi mất tiếng — định tuyến phát.** `playAudioData` chỉ định tuyến `tool == "nghitts"` sang `playNghiAudioData`; VieNeu rơi xuống nhánh `AVAudioPlayer` chung, trong khi `updatePlaybackParams()` đặt `rate` lên `nghiAudioPlayerQueue`. Hai bên lệch nhau nên **không có tiếng** và **không có lỗi nào được ném ra**.
  * Sửa: thêm `TTSManager.isLocalEngine(_:)` (`nghitts || vieneu`) và thay **9** predicate trong `TTSManager.swift` + **2** trong `TTSChapterPrefetcher.swift`.
  * **Quy ước mới**: hỏi *"engine local?"* → `isLocalEngine`; hỏi *"Piper?"* (`chunkLength`, `NghiUtteranceSegmenter`) → **giữ** `== "nghitts"`. `isLocalEngine` và `isExtensionTool` là cặp sinh đôi, **không** gộp.
- **Lỗi tham số bị ghi đè im lặng.** `loadParamsForCurrentTool()` gọi `applyVieNeuParamsIfNeeded()` ở **dòng đầu** nhánh `else` (nhánh extension) rồi **ghi đè ngay** `speed`/`pitch`/`selectedVoice` bằng `extRate_vieneu`/`extPitch_vieneu`/`extVoice_vieneu`. Sửa: nhánh `else if tool == "vieneu"` riêng.
- **Lỗi giọng không nhớ.** `selectedVoice.didSet` ghi `extVoice_vieneu` nhưng loader **đọc** `vieneuVoice` ⇒ chọn giọng xong thoát ra vào lại là mất. Sửa: `persistVoice(_:)` dùng **cùng** khoá mà loader đọc.
- **Khoá `vieneu*` tách hẳn `nghitts*`** (yêu cầu trực tiếp của người dùng): `vieneuVoice`, `vieneuRate`, `vieneuPitch`, `vieneuPrefetchCount`, `vieneuSafeCachedTimeThreshold`. `vieneuPrefetchCount`/`vieneuSafeCachedTimeThreshold` trước đây là `@Published` trần **không lưu gì** ⇒ nay có `didSet` / `setVieNeuSafeCachedTimeThreshold(_:)` (clamp 4…20, dựng lại cửa sổ tải trước khi đang phát). Lý do tách: VieNeu cần đệm sâu hơn (`bufferedSecondsTarget` 12 s so với 8 s của Piper) nên dùng chung ngưỡng là sai cho cả hai.
- **Giữ ratchet-down — gom `didSet` ra extension.** `TTSManager.swift` ở **4029/3470** nên không được dài thêm. Ba chuỗi `if/else` trong `didSet` của `speed`/`pitch`/`selectedVoice` được gom thành `persistSpeed(_:)`/`persistPitch(_:)`/`persistVoice(_:)` trong `TTSManager+VieNeu.swift` ⇒ thêm **1 engine + 6 khoá** mà file legacy **ngắn hơn 4 dòng**. Lưu ý: extension **không** thêm được stored property nên khai báo `vieneu*` vẫn phải nằm ở file legacy.
- **Thiếu config fast/high — nay có.** `vieNeuReaderSection` (`TTSSettingsView+VieNeu.swift`): Picker chế độ `Tự động (theo tốc độ máy)` / `Chất lượng cao · 16 bước` / `Nhanh · 8 bước`, Stepper số đoạn tải trước (2…10), Stepper ngưỡng nạp bộ đệm (4…20). Nối bằng `vieNeuModeBinding` đọc/ghi thẳng `VieNeuTTSService.preferredMode` (không dùng `@AppStorage` được vì extension không thêm được stored property) — dùng **chung** khoá `vieneuPreferredMode` với màn thử giọng.
- **Thêm `persistChunkLength(_:)`** và **nạp `chunkLength` cho VieNeu**. Đây là chỗ sửa một khẳng định **sai** của lượt trước: comment cũ ghi *"VieNeu không dùng chunkLength của Piper"*, nhưng `TTSManager.playbackParagraphs` (`:801-803`) cho `vieneu` đi qua `NghiUtteranceSegmenter.expand(baseParagraphs, maximumLength: chunkLength)` giống Piper ⇒ VieNeu **có** dùng `chunkLength`, và trước lượt này nó thừa hưởng giá trị còn sót của engine trước đó. Nay nạp từ khoá riêng `vieneuChunk` (khai báo trong `VieNeuSettingsKey.chunk`).
- **Sửa một hồi quy tự gây ra trong lúc làm.** Ban đầu tôi đổi cả `prefetchDelayMs.didSet` sang `isLocalEngine`, nhưng nhánh đó ghi khoá **của Piper** (`nghittsPrefetchDelay`). Vì `applyVieNeuParamsIfNeeded()` luôn đặt `prefetchDelayMs = 500`, mỗi lần chuyển sang VieNeu sẽ ghi đè `nghittsPrefetchDelay` bằng 500 ⇒ người dùng **mất độ trễ đã chỉnh cho NghiTTS**. Đã trả về `== "nghitts"` kèm comment giải thích.
- **Thêm log `[TTSRoute]`** (`AppLogger.shared.log`): đổi engine, nạp tham số VieNeu, và **đường phát được chọn** (hàng đợi local vs `AVAudioPlayer`). Đây chính là thứ lẽ ra đã chỉ ra lỗi mất tiếng ngay từ đầu. `persistSpeed`/`persistPitch`/`persistVoice`/`persistChunkLength` dùng `logTTSVerbose` để slider không làm ngập log.
- **File sửa**: `TTSManager.swift` 4029 → **4025** (giảm 4 dòng so với đầu lượt nhờ thêm `persistChunkLength`), `TTSManager+VieNeu.swift` 67 → **183**, `TTSSettingsView+VieNeu.swift` 73 → **128**, `TTSSettingsView.swift` 519 → **517** (gộp hai khối `Image`+`Text` thành `Label` để lấy lại dòng), `TTSChapterPrefetcher.swift` **375** (đổi predicate, không đổi số dòng).
- **Hạn chế đã biết (CHƯA sửa — quan trọng)**: **hai Stepper mới chưa có tác dụng thật.** Toàn bộ máy nạp lại / cửa sổ wake của NghiTTS vẫn gate bằng `tool == "nghitts"` ở **~15 chỗ** — `updateNghiPrefetchWindow` (`:2652`), `prepareNextNghiAudioIfPossible` (`:3252`), `calculateNghiCachedTime` (`:2596`), `handleNghiAudioFinished` (`:3362`), `startPrefetchTask(for:)` (`:2991`), `handleNghiScheduledHandoff` (`:3194`)… Hệ quả: `calculateNghiCachedTime()` trả **0.0** cho VieNeu nên `vieneuSafeCachedTimeThreshold` **không bao giờ được đọc** (các nơi tiêu thụ — `TTSManager+NextChapterPrefix.swift:73`, `TTSManager.swift:2674`, `:2714` — đều đọc `nghittsSafeCachedTimeThreshold` và nằm trong code đã gate); `vieneuPrefetchCount` chỉ được đọc ở `currentPrefetchCount` mà nơi dùng duy nhất là `updatePrefetchWindow()` (`:2488`) — đường **remote**. Hai giá trị vẫn được lưu/nạp đúng (đúng yêu cầu "lưu key khác nghitts") và sẽ có tác dụng ngay khi mở máy nạp lại cho engine local, nhưng **hiện tại chỉnh không thấy khác gì**. Chế độ `fast`/`high` **có** tác dụng thật vì nó đi thẳng vào engine.
- **Hạn chế đã biết (chưa sửa)**: `NghiAudioPlayerQueue` chỉ có `updateRate(_:)`, **không** có pitch; `AVAudioUnitTimePitch` chỉ nằm trên đường `AVAudioEngine`. Nên `vieneuPitch` **được lưu/nạp nhưng chưa nghe thấy được** — muốn có pitch thật phải thêm xử lý pitch vào queue (việc riêng).
- **Ràng buộc đã đo**: `check_architecture.py` giữ nguyên **5** violation nền cũ và **0** vi phạm mới (so trước/sau bằng `git stash`); `validate_links.py` PASS (16 documents, 608 Swift files). Không build được trên Windows.
- **Tài liệu CodeGraph**: `rules.md` thêm mục **TTS Engine Routing Invariants** (9 luật); `11_subsystems.md`, `03_type_graph.md`, `04_call_graph.md`, `05_state_graph.md`, `06_event_graph.md`, `08_lifecycle.md`, `10_risk_report.md`, `13_resource_lifecycle.md` mỗi file thêm mục 1.3.434; sửa một khẳng định **sai** trong `06_event_graph.md` (tài liệu cũ nói `didSet` của `speed`/`pitch` cập nhật `AVAudioUnitTimePitch`, nhưng engine local không đi đường đó).

## [1.3.433] - 2026-09-29

### fix: hien danh sach giong dung theo engine dang chon

Người dùng cài IPA và báo **hai** lỗi liên quan, cùng một gốc là "engine thứ hai dùng chung đường với NghiTTS".

- **Lỗi 1 — VieNeu bị xếp nhầm vào nhánh extension.** Picker đã có mục "VieNeu-TTS v3 Nano (Offline)" ✓ nhưng mục **GIỌNG ĐỌC** hiện "Không có giọng đọc nào" ✗, kèm dòng *"Extension TTS không hỗ trợ chỉnh cao độ"*.
  * Predicate nhận diện extension — `tool != "system" && tool != "nghitts" && tool != "google"` — nằm ở **6 chỗ** (**4** trong `TTSSettingsView`, **2** trong `TTSManager`). Thêm `vieneu` mà không sửa cả 6 ⇒ VieNeu rơi vào nhánh **extension** ⇒ màn Cài đặt dùng `extensionVoices` (rỗng) thay vì `availableVoices`.
  * `loadExtensionVoices(packageId: "vieneu")` **thoát sớm** vì không có extension trùng tên, nên nó không xoá `availableVoices` — lỗi nằm ở **UI chọn nhánh**, không phải ở dữ liệu.
  * Sửa: gom thành **một** `TTSManager.isExtensionTool(_:)` (static) và thay cả 6 chỗ ⇒ **net 0 dòng**. Thêm nhánh `vieNeuVoicePicker` (đặt trong `TTSSettingsView+VieNeu.swift` để không vượt baseline **519**).
  * Nhánh giọng của VieNeu **cố ý không lọc `isModelDownloaded`** như NghiTTS: 11 giọng nằm chung trong `voices_v3_nano.json`, không phải file rời từng giọng.
- **Lỗi 2 — đổi từ VieNeu sang NghiTTS thì NghiTTS báo "chưa tải model".** Gốc: `onChange(of: ttsManager.tool)` **không** nạp lại giọng cho engine có sẵn. Lỗi **có sẵn từ trước** nhưng chỉ lộ ra khi có engine thứ hai cùng dùng `availableVoices`: đổi engine giữ nguyên tên giọng của engine cũ, rồi nhánh NghiTTS lọc `isModelDownloaded` trên **tên giọng của VieNeu** ⇒ "Chưa tải giọng đọc NghiTTS nào" dù model đã có. Sửa: `Task { await loadVoicesForCurrentTool() }` trong nhánh `else` của `onChange` (**+1 dòng**).
- **File sửa**: `TTSSettingsView.swift` **519** (đúng baseline), `TTSSettingsView+VieNeu.swift` 47 → **77**, `TTSManager+VieNeu.swift` 55 → **67**, `TTSManager.swift` **4029** (không đổi).
- **Ràng buộc đã đo**: `check_architecture.py` giữ nguyên **5** violation nền cũ và **0** vi phạm mới; `validate_links.py` PASS. Không build được trên Windows.
- **Tài liệu CodeGraph**: `rules.md` thêm 2 luật (predicate `isExtensionTool` ở 6 chỗ; engine có sẵn cần nhánh giọng riêng); `11_subsystems.md` thêm mục về hai lỗi này.

## [1.3.432] - 2026-09-29

### feat: noi engine VieNeu-TTS vao Picker Trinh doc

Thực thi plan 2b đã duyệt (phiên grill-me). **Phần lõi xong**; màn cấu hình riêng cho VieNeu còn lại.

- **`LocalTTSEngine.swift` (mới, 52 dòng)** — protocol chung cho hai engine local. `PiperTTSService` và `VieNeuTTSService` cùng conform; VieNeu được thêm `boundaryKind` cho khớp chữ ký nhưng **bỏ qua** (nó tự phân loại ranh giới theo dấu câu).
- **`TTSManager+VieNeu.swift` (mới, 60 dòng)** — computed `localEngine` trả `nghiTTSService` cho **mọi** tool trừ `vieneu` ⇒ **đường NghiTTS không đổi một bit nào**; cùng `applyVieNeuParamsIfNeeded` và khoá `vieneu*`.
- **`TTSSettingsView+VieNeu.swift` (mới, 47 dòng)** — mục Picker của VieNeu **chỉ hiện khi model đã tải** (quyết định grill #2: chặn ở Picker), lối tải model khi còn thiếu, và nạp giọng theo engine.
- **Sửa `TTSManager.swift`**: dispatch `:2453` và guard warm-up `:779` thêm `vieneu`; `playbackParagraphs:807` cũng thêm (quyết định grill #3 — chia nhỏ đơn vị đọc); `updatePlaybackParams:1133` thêm `vieneu` vào nhánh áp tốc độ tay; 5 call site đổi `nghiTTSService` → `localEngine`.
- **Đổi kiểu tham số prefetch** `nghiService: PiperTTSService?` → `localService: (any LocalTTSEngine)?` ở **6 file** — plan chỉ liệt kê 3, thực tế còn `TTSNextChapterPrefixCache` (+ extension GoogleBatch) và `TTSManager+NextChapterPrefix`.
- **Hai kết luận từ đọc code làm giảm công việc so với plan**: (1) `VieNeuTTSService` **đã** đi qua `PiperSynthesisCoordinator.shared` ⇒ rủi ro "tải trước chặn phát" trong plan §6 **không tồn tại**; (2) kiến trúc app **đã** làm "tổng hợp ở 1.0, tốc độ ở tầng phát" (cả hai call site NghiTTS truyền `speed: 1.0`) ⇒ không cần sửa khoá cache.
- **Lệch so với plan**: `TTSManager.swift` **4026 → 4029** (+3), plan ghi "+1 dòng". Hai stored property cho thông số đệm bắt buộc ở file chính (extension không thêm được stored property); đã cắt hết comment để giảm từ +7 xuống +3. `check_architecture.py` vẫn **5** vi phạm nền, **0** mới.
- **Ràng buộc đã đo**: `check_architecture.py` giữ nguyên **5** violation nền cũ và **0** vi phạm mới; `validate_links.py` PASS. Không build được trên Windows.
- **CÒN LẠI của 2b**: màn cấu hình riêng cho VieNeu (quyết định grill #4) và cho logic đệm đọc đúng khoá `vieneu*` theo tool.

## [1.3.431] - 2026-09-29

### fix: khop am luong giua chunk va gom nut phat dung vao hang icon

Người dùng: **"chỗ đến năm giảm âm lượng đột ngột"**, **"đọc số năm bị lắp bắp"**, **"đem nút phát, dừng lên chỗ bên phải thanh chứa sao chép, clear, paste (hiển thị icon thôi)"**.

- **Tụt âm lượng ở ranh giới chunk — đã kiểm bản tham chiếu trước khi sửa**: `join_audio_chunks` giữ **nguyên** audio từng chunk rồi chỉ chèn zeros, và `grep` trong `core_utils.py` **không có** hàm `normalize`/`peak`/`rms`/`gain` nào ⇒ chênh mức giữa các chunk là hành vi **cố hữu của bản tham chiếu**, không phải lỗi port. Nguyên nhân hợp lý: model sinh mỗi chunk độc lập nên chunk toàn số đọc đều đều **nhỏ hơn** chunk kể chuyện.
  * **Cách xử lý (mở rộng có chủ ý, dè dặt)**: `joinChunks` kéo mỗi chunk về **trung vị** RMS, kẹp hệ số trong **[0,6 … 1,6]** (±4 dB) — kẹp để **không** san bằng khác biệt có ý nghĩa (câu thì thầm, câu nhấn mạnh).
  * Đã ghi vào `rules.md` rằng đây là **mở rộng**, để sau này không ai "sửa" ngược về cho khớp bản tham chiếu.
- **"Lắp bắp" khi đọc số năm**: phoneme của chunk đó **đúng** (`nˈam mˈo6t̪ ŋˈi2n tʃˈiɜn tʃˈam tʃˈiɜn mˈyəj,` = "năm một nghìn chín trăm chín mươi,") ⇒ đây là **hiện tượng của model** khi gặp chuỗi âm tiết lặp, không phải lỗi tầng chữ. Không sửa được ở tầng này.
- **UI**: nút **Phát / Dừng** chuyển lên **cùng hàng** với xoá–sao chép–dán ở ô nhập chữ, tất cả **chỉ icon**; khối dưới còn trạng thái + nút chia sẻ audio.
- **Tách file**: `VieNeuTTSEngine+Audio.swift` lên **432/400** sau khi thêm khớp âm lượng ⇒ tách theo ranh giới *chữ* vs *mẫu*: phần tách chunk sang `VieNeuTTSEngine+Chunking.swift` (**294**), `+Audio` còn **148**.
- **File sửa**: `VieNeuTTSEngine.swift` **370**, `VieNeuTTSEngine+Chunking.swift` **294** (mới), `VieNeuTTSEngine+Audio.swift` 368 → **148**, `VieNeuTTSTestView+Sections.swift` 210 → **217**.
- **Ràng buộc đã đo**: `check_architecture.py` giữ nguyên **5** violation nền cũ và **0** vi phạm mới; `validate_links.py` PASS. Không build được trên Windows.
- **Tài liệu CodeGraph**: `rules.md` thêm 2 luật (khớp âm lượng là mở rộng có chủ ý; tách `+Audio` theo ranh giới chữ/mẫu); `00_index`, `02_file_graph`, `09_dependency_rules`, `11_subsystems`, `14_complexity_report` cập nhật.

## [1.3.430] - 2026-09-29

### fix: mo rong hang rao con so theo tu dan so

Báo cáo sau 1.3.429 trả lời gọn cả hai câu hỏi.

- **`chậm ở đâu  vector 7,60 s | khác 0,14 s`** trên 28,01 s audio ⇒ **vòng Euler chiếm 98%** thời gian, chi phí cố định theo chunk chỉ 0,14 s ⇒ **giảm số chunk không giúp gì** — loại hẳn một hướng tối ưu tôi định thử.
- **Nâng lên 4 luồng đã có tác dụng**: `RTF thật` 0,37 → **0,29** (−22%). Giữ 4 luồng; đã ghi **kết quả đo** vào doc của `threadCount` để lần sau không đo lại.
- **Còn lại hai đòn bẩy, cả hai đã chạm sàn**: số bước (8 là mức thấp nhất còn dùng được) và CFG (tắt đi thì người dùng nghe "quá dở") ⇒ **engine đã gần mức sàn thực tế**.
- **Lỗi còn lại: "tháng sáu" bị chẻ đôi.** Phoneme từng chunk chỉ ra đúng chỗ: `[0] … tˈaːɜŋ.` rồi `[1] sˈaɜw nˈam …`. Hàng rào của bản tham chiếu chỉ chặn cắt giữa **hai từ số**, mà "tháng" không phải từ số ⇒ lọt. Nay thêm `numberIntroducers` (tháng ngày giờ phút giây tuổi khoảng độ số trang chương phần quyển tập mục điều quãng hồi chặng) chặn cắt **ngay sau** chúng khi từ kế là số.
  * **Đã xác minh**: hàng rào cũ → `…từ khoảng tháng | nghìn chín trăm…`; mới → `…từ khoảng | nghìn chín trăm…` ✓.
  * Đây là **mở rộng** so với bản tham chiếu, nhưng chính nó ghi rằng chặn thừa một chút còn hơn xẻ đôi một năm ⇒ đúng tinh thần của nó.
- **File sửa**: `VieNeuTTSEngine+Audio.swift` 355 → **368**, `VieNeuSynthesisPolicy.swift` **93** (chỉ đổi doc).
- **Ràng buộc đã đo**: `check_architecture.py` giữ nguyên **5** violation nền cũ và **0** vi phạm mới; `validate_links.py` PASS. Không build được trên Windows.
- **Tài liệu CodeGraph**: `rules.md` thêm 2 luật (kết quả đo: Euler 98% ⇒ giảm chunk vô ích, 4 luồng có tác dụng; từ dẫn số cũng chặn cắt); `11_subsystems.md` thêm mục về lượt này.

## [1.3.429] - 2026-09-29

### perf: them so do thoi gian va in phoneme moi chunk

Người dùng: **"Cả đoạn mà phoneme bạn in ra chỉ có 1 câu"** và **"thời gian tổng hợp quá dài: hơn 10s cho 28s audio, cũ là 4s… cần thiết sửa để tăng tốc độ"**.

- **Phoneme in MỌI chunk, mỗi chunk một dòng** (`[0] …`, `[1] …`). Bản trước chỉ in 700 ký tự của chunk 0 — mà chunk 0 chỉ là một câu, nên không soi được chunk nào đọc sai.
- **Số đo tách nhóm việc thay vì đoán**: `VieNeuTTSEngine.Timing` cộng dồn `vectorMs` (vòng Euler) và `otherMs` (phần còn lại của chunk); báo cáo thêm dòng `chậm ở đâu vector X s | khác Y s`. Đây là bước **đo trước khi sửa** — nếu `vector` chiếm gần hết thì đòn bẩy là số bước / CFG / số luồng; nếu `khác` đáng kể thì đó là chi phí cố định theo chunk và cách giảm là giảm số chunk.
  * **Bẫy đã mắc và đã sửa**: bản đầu dùng hai `defer` — cái ngoài đo **cả chunk** (gồm cả vòng lặp) nên phần vector bị **đếm hai lần**. Sửa thành `otherMs += max(0, chunkMs - vectorMs)`. **Số đo sai còn tệ hơn không đo** vì nó đẩy lần sửa sau đi sai hướng.
- **Nâng `threadCount` 2 → 4**: sau khi đã ở 8 bước + CFG thì số luồng là **đòn bẩy còn lại duy nhất**, đổi lại máy nóng hơn. Ghi rõ trong code: nếu lần sau RTF không giảm mà `vector` vẫn chiếm gần hết thì **trả về 2**.
- **Phân tích số của người dùng**: 10,15 s cho 28,13 s audio; `RTF thật` 0,37 so với 0,26–0,30 trước đó ⇒ **chậm đi thật ~25%**, không phải artefact. Phần lớn là do văn bản **dài ra thật** (số được đọc thành chữ: 20,71 → 28,13 s audio) cộng +20% số chunk.
- **`VieNeuTTSEngine` chạm 399/400 dòng** khi thêm số đo ⇒ dời `Chunk`/`Gap` sang `+Audio.swift`, `Timing` sang `+Adaptive.swift` ⇒ engine còn **370**.
- **File sửa**: `VieNeuTTSEngine.swift` 372 → **370**, `VieNeuTTSEngine+Audio.swift` 336 → **355**, `VieNeuTTSEngine+Adaptive.swift` 46 → **56**, `VieNeuTTSService.swift` 272 → **279**, `VieNeuSynthesisPolicy.swift` 87 → **93**, `VieNeuTTSTestView.swift` 290 → **291**.
- **Ràng buộc đã đo**: `check_architecture.py` giữ nguyên **5** violation nền cũ và **0** vi phạm mới; `validate_links.py` PASS. Không build được trên Windows.
- **Tài liệu CodeGraph**: `rules.md` thêm 3 luật (đo trước khi tối ưu và đừng để số đo đếm hai lần; chẩn đoán phải in mọi đơn vị chứ không chỉ cái đầu; nested type nên nằm ở file extension khi file chính chật); `11_subsystems.md` thêm mục về lượt này.

## [1.3.428] - 2026-09-29

### fix: khong cat giua con so va bao cao rtf tru khoang nghi

Người dùng: **"ngắt nghỉ bất thường khi đang đọc số, thời gian"**, **"phoneme nên in đủ đoạn mới thấy được"**, **"xử lý thời gian tăng quá nhiều"**.

- **Lỗi thật: cắt chunk xẻ đôi một con số.** Sau khi bật lớp đọc số (1.3.426), `1990` thành "một nghìn chín trăm chín mươi" — một chuỗi nhiều từ — và bộ cắt theo từ **cắt ngay giữa chuỗi đó** ⇒ nghe thành khoảng nghỉ giữa con số. Bản tham chiếu có sẵn ba bảng: `_NUMBER_WORDS`, `_CONN_WORDS`, `_CONN_PAIRS`; `_balanced_cut` chỉ nhận điểm cắt khi **không** lọt giữa cặp từ nối và **không** nằm giữa hai từ số.
  * Đã port và **xác minh**: văn bản 262 ký tự → 3 mảnh **85/90/85**, **0** chỗ xẻ đôi số, **0** chỗ cắt giữa cặp, nối lại khớp gốc từng ký tự.
- **`_split_long_part` chia ĐỀU** (`k = ceil(rest/max_chars)`, mỗi mảnh nhắm `rest/k`), không greedy — bản tham chiếu ghi rõ greedy để 304 ký tự thành 251 + 53 và điểm cắt "gần trần" trúng chỗ tệ. Thêm `min_left = max_chars // 3` để điểm cắt ở từ nối vẫn phải để lại một mệnh đề thật.
- **"RTF tăng quá nhiều" — một nửa là artefact**: khoảng nghỉ chèn **không tốn** thời gian suy luận nhưng **thổi phồng** `pcmDuration`, nên `synthesisMs/pcmDuration` **thấp giả**, càng nhiều chunk càng thấp giả. Thêm `Output.speechDuration` (audio trừ khoảng nghỉ); báo cáo hiện **cả hai** RTF để tách bạch "engine chậm đi" với "văn bản dài ra".
- **Mẫu phoneme in đủ 700 ký tự** (trước 120) — 120 không đủ thấy chỗ sai ở giữa đoạn.
- **Ghi nhận**: `phoneme bỏ: 3` ở báo cáo người dùng là `[`, `]` (chú thích `[a]`) và `"` — không phải chữ, vô hại; phần chữ số đã hết bị bỏ (trước là 11).
- **File sửa**: `VieNeuTTSEngine+Audio.swift` 252 → **336**, `VieNeuTTSEngine.swift` 363 → **372**, `VieNeuTTSService.swift` 267 → **272**, `VieNeuTTSTestView.swift` 285 → **290**.
- **Ràng buộc đã đo**: `check_architecture.py` giữ nguyên **5** violation nền cũ và **0** vi phạm mới; `validate_links.py` PASS. Không build được trên Windows.
- **Tài liệu CodeGraph**: `rules.md` thêm 3 luật (không xẻ đôi số / không cắt giữa cặp từ nối; chia đều không greedy; RTF phải tính trên audio thật); `11_subsystems.md` thêm mục về lượt này.

## [1.3.427] - 2026-09-29

### fix: tach chunk theo cau nhu ban tham chieu de khong cat giua cau

Người dùng báo **"vẫn còn tình trạng cắt chunk giữa đường gây ngắt nghỉ khó chịu"**. Nguyên nhân: **tôi chưa hề đọc bộ tách chunk của bản tham chiếu mà tự viết** — và đã viết sai hai lần.

- **Bản tham chiếu gói theo CÂU**: `normalize_to_chunks_v3_with_gaps` → `pack_sentences_into_chunks(sentences, max_chars)`, tách câu bằng `RE_SENTENCE_FINDALL = r'[^.!?]+[.!?]*|[.!?]+'`, chia đoạn theo `\n`. Ranh giới chunk vì thế **luôn** rơi vào ranh giới câu; chỉ khi một câu **đơn** dài hơn trần mới phải cắt phụ — **trước theo dấu ngắt trong câu** (`RE_MINOR_PUNCT = r'(?<=[,;:\-–—])\s+'`), sau cùng mới theo từ.
- **Bản 1.3.424 gói theo từ** ⇒ hết chẻ đôi *từ* nhưng vẫn cắt **giữa câu** ⇒ chỗ nối thành khoảng nghỉ giữa câu, đúng lời người dùng.
- **`_classify_gap` phân loại ranh giới theo dấu câu cuối chunk**: `.!?` → `"sentence"`, còn lại (`,;:` hoặc cắt cưỡng bức) → `"minor"`; `"para"` cho ranh giới `\n`. Bản tham chiếu dùng `V3_GAP_SILENCE = {"para": 0.70, "sentence": 0.50, "minor": 0.30}`; FreeBook ánh xạ sang **khoá `UserDefaults` sẵn có** (`paragraphPauseDuration` 0.5 / `sentencePauseDuration` 0.3 / `phrasePauseDuration` 0.15) để một chỗ chỉnh là **cả hai engine** cùng đổi.
- **`_fits` có "tail slack"**: câu vừa trần, **hoặc** ngắn hơn `min(15, max_chars/8)` và tổng vẫn trong `max_chars + slack` — thiếu luật này thì sinh mảnh vụn kiểu `"phương."` đứng riêng rồi bị dán sang câu sau.
- **Đã mô phỏng lại trên đúng đoạn 450 ký tự của người dùng**: 5 chunk, **mọi chỗ cắt đều ở dấu phẩy hoặc hết câu**, nối lại **khớp từng ký tự** với văn bản gốc.
- **Type mới**: `VieNeuTTSEngine.Chunk` + `Chunk.Gap` (`.paragraph` / `.sentence` / `.minor`) — bản port của `_classify_gap`.
- **File sửa**: `VieNeuTTSEngine+Audio.swift` 171 → **252**, `VieNeuTTSEngine.swift` 344 → **363**.
- **Ràng buộc đã đo**: `check_architecture.py` giữ nguyên **5** violation nền cũ và **0** vi phạm mới; `validate_links.py` PASS. Không build được trên Windows.
- **Tài liệu CodeGraph**: `rules.md` thêm 3 luật (gói theo câu; phân loại gap theo dấu câu; tail slack); `11_subsystems.md` thêm mục về lượt này.

## [1.3.426] - 2026-09-29

### fix: doc so va ngay thang cho engine VieNeu bang lop tien xu ly cua app

Người dùng báo **"đọc số và thứ ngày tháng bị nuốt chữ"** kèm `phoneme bỏ: 10` và dòng `phoneme:` (thêm ở 1.3.425 — và nó trả lời được ngay trong một lượt).

- **Nguyên nhân: `sea_g2p.bin` không có chữ số nào.** Tra thẳng từ điển: `8`, `1999`, `74`, `3`, `2002` đều **không có** ⇒ chúng rơi vào đường **đánh vần từng ký tự**, mà vocab của model chỉ có `1 2 4 5 6 7` ⇒ `0 3 8 9` bị nuốt. `8/1999` + `3/11/2002` mất đúng **10** ký tự (7 chữ số + 3 dấu `/`) — khớp chính xác `phoneme bỏ: 10`.
- **Đảo quyết định plan §2** ("không chạy lớp tiền xử lý nào"): thực tế cho thấy bộ G2P của model **không tự lo được số và ngày tháng**. Nay engine gọi `TextPreprocessor.normalizingForVieNeu(text)` **một lần cho cả đoạn, trước khi tách chunk** — phần đọc số làm văn bản dài ra nên phải xong trước khi biết cắt ở đâu.
- **Lớp dùng là `processVietnameseText`, KHÔNG phải `preprocess(_:)`**: hàm sau còn chạy `EnglishTransliterator`/`JapaneseTransliterator`, tức chèn **IPA của espeak** — một bảng ký hiệu khác sẽ bị `encode` bỏ im lặng. Dùng đúng `processVietnameseText` nên vẫn có toàn bộ logic sẵn có: đọc số, ngày tháng, khoảng năm, thời gian, đơn vị, số La Mã, chuẩn hoá NFC, gạch ngang/nháy/ellipsis.
- **Cờ `preprocessorNumericNormalizationEnabled`** (mặc định `true`) được `processVietnameseText` tự kiểm ⇒ tắt "Chuẩn hóa cách đọc số" trong Cấu hình NghiTTS là **cả hai engine** cùng tắt.
- **Bỏ `normalizingPunctuation` tự viết** ở 1.3.425: app đã có `normalizeQuotesAndDashes` làm đúng việc đó (gạch ngang → `-`, và `-` là vocab id 6). Một đường chuẩn hoá thay vì hai.
- **Một thứ KHÔNG phải lỗi**: `sách → sˈe-ɜc`, `giành → zˈe-2ɲ`, `anh → ˈe-ɲ` có dấu `-` **trong chính từ điển**. Đó là dữ liệu upstream, không sửa.
- **Ràng buộc ratchet-down suýt bị vi phạm**: thêm 2 dòng doc vào `TextPreprocessor.swift` (đúng baseline **1121**) đẩy lên 1123 ⇒ violation mới; đã gỡ. Hai khai báo (`PreprocessorRuntimeConfig`, `processVietnameseText`) hạ `private` → `internal` **tại chỗ, không đổi số dòng**; lối vào mới ở `TextPreprocessor+Numbers.swift` **35** dòng.
- **File sửa**: `TextPreprocessor.swift` **1121 → 1121** (không đổi), `VieNeuTTSEngine.swift` 338 → **344**, `VieNeuTTSEngine+Audio.swift` 190 → **171** (bỏ hàm thừa).
- **Ràng buộc đã đo**: `check_architecture.py` giữ nguyên **5** violation nền cũ và **0** vi phạm mới; `validate_links.py` PASS. Không build được trên Windows.
- **Tài liệu CodeGraph**: `rules.md` thêm 3 luật (đọc số trước khi phonemize; không thêm dòng vào `TextPreprocessor.swift`; `-` trong giá trị từ điển là đúng); `11_subsystems.md` thêm mục về lượt này.

## [1.3.425] - 2026-09-29

### fix: khoang nghi theo dau cau va chuan hoa dau cau la

Người dùng báo `phoneme bỏ: 1` và **"ngừng nghỉ chưa hợp lý"**, kèm lo ngại **"RTF tăng đáng kể so với ver trước"**.

- **`phoneme bỏ: 1` = dấu gạch ngang `–` (U+2013).** Vocab `config.json` có `-` ASCII nhưng **không** có `–`/`—`/`“ ”`, và `VieNeuConfig.encode` **bỏ im lặng** ký tự lạ (chỉ đếm vào `droppedScalars`). Nay `normalizingPunctuation` ánh xạ gạch ngang sang **dấu phẩy** — nó mang nghĩa *ngắt ý*, và dấu phẩy thì model biết đọc — và bỏ các dấu nháy trang trí. **Cố ý không đụng `'`/`’`**: tokenizer dùng chúng để ghép từ.
- **"Ngừng nghỉ chưa hợp lý"**: khoảng nghỉ là **hằng số 0,12 s** cho mọi khe, và **dấu phẩy không nằm trong bộ ký tự ranh giới chunk** — mà khoảng lặng chỉ được chèn **giữa** các chunk, nên dấu phẩy nằm *trong* chunk thì mọi chỗ ngắt theo dấu phẩy đều mất. Nay `pauseSeconds(afterChunk:)` đọc **đúng khoá `UserDefaults`** mà đường NghiTTS dùng (`sentencePauseDuration` 0,3 s / `phrasePauseDuration` 0,15 s) ⇒ chỉnh trong Cấu hình NghiTTS là **cả hai engine** cùng đổi. `,` `，` `、` đã vào `chunkBoundaryCharacters`.
- **Về "RTF tăng": đó là artefact của phép đo, không phải engine chậm đi.** `RTF = synthesisMs / audioSeconds`, nên bất cứ gì làm **audio ngắn đi** đều đẩy RTF lên. Hai lần người dùng đo dùng **văn bản khác nhau** (290 vs 285 ký tự) và cho audio 16,88 s vs 15,08 s (−11%) trong khi thời gian tổng hợp chỉ đổi 4376 → 4554 ms (+4%, trong nhiễu nhiệt). Báo cáo nay in thêm **"nhanh hơn N× so với realtime"** (`1/RTF`) để con số đọc trực tiếp. Muốn so chuẩn thì phải **cùng một đoạn văn**.
- **Thêm "mẫu phoneme" vào khối chẩn đoán** (`phoneme: …`, 120 ký tự đầu của chunk đầu): đây là **bằng chứng duy nhất** phân biệt được "từ điển trả phoneme sai" với "phoneme đúng nhưng model đọc phoneme tiếng Anh bằng giọng Việt" — hai nguyên nhân nghe giống hệt nhau. Cần cho ca `Potter` còn treo.
- **File sửa**: `VieNeuTTSEngine+Audio.swift` 126 → **190**, `VieNeuTTSEngine.swift` 330 → **338**, `VieNeuTTSService.swift` 262 → **267**, `VieNeuTTSTestView.swift` 284 → **285**, `+Diagnostics.swift` 40 → **44**.
- **Ràng buộc đã đo**: `check_architecture.py` giữ nguyên **5** violation nền cũ và **0** vi phạm mới; `validate_links.py` PASS. Không build được trên Windows.
- **Tài liệu CodeGraph**: `rules.md` thêm 3 luật (khoảng nghỉ theo dấu câu; chuẩn hoá dấu câu lạ; RTF là tỉ số nên phải so trên cùng văn bản); `11_subsystems.md` thêm mục về lượt này.

## [1.3.424] - 2026-09-29

### fix: khong che doi tu o ranh gioi chunk, sua picker che do, them nut chia se audio

Người dùng thử đoạn khác và báo **"trở" đọc thành "thê giở"**, **"Harry Potter" đọc thành "harry pô ti tờ"** — vài từ sai lẻ trong câu đúng.

- **Nguyên nhân gốc: `splitIntoChunks` cắt cứng ở đúng `limit` ký tự nên chẻ đôi từ.** Đếm vị trí trên đúng câu người dùng gửi: `trở` ở ký tự **[139..141]** còn ranh giới chunk là **140** ⇒ "t" vào chunk 0, "rở" vào chunk 1; `Potter` vắt qua ranh giới 280 ⇒ "Po" + "tter". Hai mảnh không có trong từ điển nên rơi vào **`charFallback` (đánh vần từng ký tự)** và bị đọc thành **tên chữ cái**.
  * Đã kiểm bằng bộ đọc Python trên `sea_g2p.bin` thật: **cả `trở` (`tʃˈəː4`) lẫn `potter` (`<en>pˈɑːɾɚ`) đều CÓ trong từ điển** ⇒ lỗi không phải từ điển mà là ranh giới chunk. (Đây là lần thứ sáu trong engine này lỗi nằm ở chỗ tôi tự tính thay vì hỏi nguồn.)
  * Sửa: `splitIntoChunks` gói theo **từ**, chỉ cắt cứng khi một từ đơn dài hơn `limit`. Đã mô phỏng lại: `trở` nằm trọn trong một chunk, văn bản nối lại khớp gốc từng ký tự.
- **Picker chế độ không đổi ngay khi chọn**: `VieNeuTTSService` là class thường (**không** `@Observable`), nên `Binding` đọc `service.preferredMode` và nhãn đọc `service.currentMode` đều không làm SwiftUI vẽ lại — nhãn chỉ nhảy khi state khác đổi (bấm Phát). Sửa: lựa chọn giữ ở `@State selectedMode`, đẩy xuống service trong `.onChange`, nhãn đọc state trước.
- **Thêm nút "Chia sẻ audio"** (`ShareLink` với file WAV ghi ra thư mục tạm; xoá file của lượt trước để không tích tụ).
- **Thêm 3 nút icon xoá / sao chép / dán** ở ô nhập chữ, kèm `accessibilityLabel`. `.buttonStyle(.borderless)` là bắt buộc: trong một hàng `Form`, mặc định cả hàng là **một** nút nên mọi cú chạm rơi vào nút đầu.
- **Thêm `chunkCount` vào khối chẩn đoán** (`chunk: N`) — chỉ số bắt đúng lỗi ranh giới chunk.
- **File sửa**: `VieNeuTTSEngine+Audio.swift` (viết lại `splitIntoChunks`), `VieNeuTTSEngine` 324 → **330**, `VieNeuTTSService` 256 → **262**, `VieNeuTTSTestView.swift` 260 → **284**, `+Sections.swift` 167 → **210**, `+Diagnostics.swift` 37 → **40**.
- **Ràng buộc đã đo**: `check_architecture.py` giữ nguyên **5** violation nền cũ và **0** vi phạm mới; `validate_links.py` PASS. Không build được trên Windows.
- **Tài liệu CodeGraph**: `rules.md` thêm 2 luật (không chẻ từ ở ranh giới chunk; UI state phải nằm ở `@State` khi service không observable); `11_subsystems.md` thêm mục về lượt này.

## [1.3.423] - 2026-09-29

### fix: bo che do turbo va chi doi toc do phat audio

Người dùng đo trên máy thật: `fast` (8 bước) **RTF 0.26** (16,88 s audio trong 4,38 s), `high` (16 bước) **RTF 0.48** (8,06 s), giọng "khá ổn" ở cả hai — nhưng chế độ **tắt CFG "quá dở, đứt quãng, không rõ tiếng"**.

- **Bỏ hẳn chế độ `turbo` (`cfg = 0`)**: model card cảnh báo thẳng "hurts intelligibility" và tai người dùng xác nhận. Giữ lại một lựa chọn đã bị từ chối chỉ tạo thêm một cái bẫy. Tương thích: `UserDefaults` còn giá trị `"turbo"` thì `Mode(rawValue:)` trả `nil` ⇒ tự rơi về "tự động", **không cần migrate**.
- **Tách tốc độ phát khỏi tốc độ tạo**: engine `speed` chia `exp(log_s)` (`secs = min(exp(log_s)/speed, 15)`) — tức bắt model **sinh audio ngắn/dài hơn**, đẩy nó ra khỏi nhịp được huấn luyện và bắt tổng hợp lại mỗi lần đổi tốc độ. Nay màn thử giọng **luôn tổng hợp ở 1.0×** và áp tốc độ bằng `AVAudioPlayer.rate` (`enableRate = true` phải đặt **trước** `rate`, nếu không iOS bỏ qua). Mục "Tốc độ" đổi thành **"Tốc độ phát"** kèm giải thích.
- **Hệ quả cần nhớ khi nối Reader (increment 2b)**: số RTF đo được **luôn ứng với 1.0×**, và đổi tốc độ **không được** kích hoạt tổng hợp lại.
- **Chế độ còn lại**: `high` (16 bước, "Chất lượng cao") · `fast` (8 bước, "Nhanh") · *Tự động*.
- **File sửa**: `VieNeuSynthesisPolicy` 86 → **87**, `VieNeuTTSTestView.swift` 255 → **260**, `VieNeuTTSTestView+Sections.swift` 164 → **167**.
- **Ràng buộc đã đo**: `check_architecture.py` giữ nguyên **5** violation nền cũ và **0** vi phạm mới; `validate_links.py` PASS. Không build được trên Windows.
- **Tài liệu CodeGraph**: `rules.md` thêm 2 luật (tốc độ thuộc tầng phát; không có chế độ `cfg = 0`); `11_subsystems.md` thêm mục về lượt đo này.

## [1.3.422] - 2026-09-29

### feat: them bo chon toc do tao audio cho engine VieNeu

Người dùng xác nhận engine đã **đọc đúng tiếng Việt** (`phoneme bỏ: 0`, RTF **0.52**) và yêu cầu **nhanh hơn**, kèm ghi nhận máy **nóng** sau khi tạo xong.

- **Bộ chọn tốc độ tạo audio** trong màn thử giọng: `high` (16 bước, CFG bật) · `fast` (8 bước + sway −1) · `turbo` (8 bước, **tắt CFG**) · *Tự động*. Mỗi Euler step là một lượt `vector_estimator` và CFG chạy **thêm một lượt cho mỗi step** ⇒ 16 bước = **32 lượt/đoạn**, 8 bước = 16, `turbo` = **8**. Đây là **đòn bẩy duy nhất** vừa nhanh hơn vừa mát máy hơn (tăng thread thì nhanh hơn nhưng nóng hơn — ngược yêu cầu).
- **Lựa chọn của người dùng tắt hẳn cơ chế thích nghi**: `VieNeuTTSEngine.requestedMode != nil` ⇒ `updateMode` không chạy. Nếu không, bộ thích nghi sẽ tự nâng/hạ và ghi đè đúng thứ người dùng vừa đặt.
- **`turbo` không bao giờ do thích nghi tự đặt**: `nextMode` chỉ đi giữa `high` ↔ `fast`; bỏ CFG halve compute nhưng model card cảnh báo thẳng là **giảm độ rõ**, nên nó chỉ dùng khi người dùng đã nghe và chấp nhận.
- **Lưu lựa chọn trong `UserDefaults`** (`vieneuPreferredMode`), đặt ở tầng `VieNeuTTSService` để màn thử giọng và đường đọc truyện (khi được nối) dùng **cùng một** giá trị.
- **Tách `VieNeuTTSTestView` thành 3 file** vì đã chạm **397/400** dòng: file chính 397 → **255**, thêm `+Sections.swift` **164** (các khối `Form` + bộ chọn tốc độ) và `+Diagnostics.swift` **37** (khối copy). Tách file extension buộc hạ `@State private` → `internal` — **cái giá của việc tách muộn**.
- **Nhãn UI ở tầng View**: `VieNeuSynthesisPolicy.Mode.displayName` là extension trong file View, để policy giữ nguyên tính thuần (không chuỗi UI, không `UserDefaults`).
- **File sửa**: `VieNeuSynthesisPolicy` 81 → **86**, `VieNeuTTSEngine` 302 → **324**, `VieNeuTTSService` 231 → **256**.
- **Ràng buộc đã đo**: `check_architecture.py` giữ nguyên **5** violation nền cũ và **0** vi phạm mới; `validate_links.py` PASS. Không build được trên Windows.
- **Tài liệu CodeGraph**: `00_index.md`, `02_file_graph.md`, `09_dependency_rules.md`, `11_subsystems.md`, `14_complexity_report.md` (`--accept`); `04_call_graph.md`, `10_risk_report.md`, `13_resource_lifecycle.md`, `rules.md` (`--no-change-needed`).

## [1.3.421] - 2026-09-29

### fix: doc dung base 48 cua sea_g2p.bin va thu tu byte UTF-8

Engine đã chạy (**RTF 0.50** ở chế độ `high`, độ dài audio hợp lý) nhưng người dùng báo **"âm thanh không phải tiếng Việt"**. Hai lỗi trong bộ đọc `sea_g2p.bin`:

- **`SeaG2P.getString` hardcode `32 + offset`** — `write_bin_v2` ghi header **48** byte (4 magic + 4 version + 12 count + 12 vị trí + 8 bảng section + 8 reserved) rồi mới tới blob chuỗi. Lệch **16 byte** nghĩa là **mọi** chuỗi đọc ra đều là *đuôi của chuỗi trước + đầu của chuỗi sau* ⇒ phoneme rác ⇒ model đọc ra thứ không phải tiếng Việt, trong khi shape/tensor/độ dài audio đều đúng nên triệu chứng không phải một lỗi mà là "nghe sai tiếng".
  * Đã xác minh trực tiếp trên file thật (62.829.820 byte): base 48 cho `xin → sˈin`, `chào → tʃˈaː2w`, `đây → ɗˈəɪ`, `việt → vˈiɛ6t̪`, `người → ŋˈyə2j`; base 32 **không tra được từ nào**. Nay `stringBase` đọc từ trường version (v2 → 48, v1 → 32) thay vì hardcode.
- **Sai thứ tự so sánh khi tìm nhị phân**: `write_bin_v2` sắp bảng bằng `sorted(..., key=lambda kv: kv[0].encode("utf-8"))` (thứ tự **byte UTF-8**), còn `SeaG2P` dùng `String.<` của Swift (Unicode canonical ordering) ⇒ có thể trượt khoá **có** trong bảng. Nay dùng `utf8Less` với `lhs.utf8.lexicographicallyPrecedes(rhs.utf8)`.
- **Thêm `droppedScalars` vào khối chẩn đoán của màn thử giọng**: `AppLogger` chỉ ghi khi người dùng bật `AppLogger.isLoggingEnabled`, nên một bộ G2P trả ký tự ngoài vocab sẽ hỏng **im lặng**. Đây chính là chỉ số đã thiếu ở lượt này.
- **File sửa**: `SeaG2P.swift` 253 → **273**, `VieNeuTTSEngine.swift` 297 → **302**, `VieNeuTTSService.swift` 225 → **231**, `VieNeuTTSTestView.swift` 392 → **397** (sát trần 400 — mọi thay đổi UI tiếp theo ở màn này **phải** tách file trước).
- **Ràng buộc đã đo**: `check_architecture.py` giữ nguyên **5** violation nền cũ và **0** vi phạm mới; `validate_links.py` PASS. Không build được trên Windows.
- **Tài liệu CodeGraph**: `rules.md` thêm mục **`sea_g2p.bin` Format Invariants** (4 luật); `11_subsystems.md` thêm mục về hai lỗi này.

## [1.3.420] - 2026-09-29

### fix: doc shape ctx tu model va them nut sao chep ket qua

Người dùng báo `Got invalid dimensions for input: ctx ... Got: 512 Expected: 256`. Đây là **lỗi thứ tư cùng một loại** trong engine này: đoán thay vì hỏi model.

- **Nguyên nhân**: bản trước tự dựng shape `ctx` là `[1, L, dim]` với `dim = 512` đọc từ `config.json`. Chiều thật của `ctx` là **`style_dim` = 256**; `dim` phục vụ một chỗ khác của kiến trúc. Ba lần trước cùng loại: tên output ONNX (1.3.419), kích thước entry `.npz` (1.3.419), và giờ là shape.
- **Cách sửa**: `VieNeuORTRunTextEncoder` trả thêm `outShape`/`outRank` (điền từ `GetDimensions` trong `copyFloats`), và `VieNeuORTRunDurationPredictor`/`VieNeuORTRunVectorEstimator` **bắt buộc** nhận lại đúng shape đó — số token suy từ `contextShape[1]`, `mask` phải cùng số token. `VieNeuConfig.dim` **bị xoá** thay vì để lại trường không dùng kèm doc nói sai.
- **Dời màn thử giọng ra tab Cài đặt**: mục "Thử giọng VieNeu-TTS" nay ở `Settings/Main/TTSSettingsSection.swift`, ngang hàng "Cài đặt TTS"/"Quản lý Model", không còn nằm trong `NghiTTSSettingsView` — đây là engine thứ hai, không phải tuỳ chọn của NghiTTS/Piper.
- **Thêm nút "Sao chép kết quả"** trong màn thử giọng: gom thông báo lỗi + số đo RTF + trạng thái model + engine status thành một khối văn bản để dán vào chat thay vì chụp màn hình.
- **File sửa**: `VieNeuONNXBridge.h/.m` (chữ ký shape), `VieNeuONNXRuntime.swift` 175 → **196**, `VieNeuTTSEngine.swift` 299 → **297**, `VieNeuConfig.swift` 163 → **162**, `VieNeuTTSTestView.swift` 346 → **392**, `NghiTTSSettingsView.swift` **158** (bỏ mục "Engine khác"), `TTSSettingsSection.swift` 25 → **30**.
- **Ràng buộc đã đo**: `check_architecture.py` giữ nguyên **5** violation nền cũ và **0** vi phạm mới; `validate_links.py` PASS. Không build được trên Windows.
- **Tài liệu CodeGraph**: `rules.md` bổ sung luật "đừng suy shape từ `config.json`"; `11_subsystems.md` thêm mục về lỗi này.
