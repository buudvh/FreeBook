# Checklist: chuẩn hoá 3 chế độ Nhập (Import) cho toàn app

> Trạng thái: **chưa sửa code**. File này là bản khảo sát hiện trạng + việc cần làm.
> Ngày khảo sát: 2026-08-25. Branch: `sigle_reader`.

## 1. Mục tiêu

Sau khi chọn file thành công, **mọi** màn có tính năng Nhập đều hiện đúng 3 lựa chọn:

| # | Nhãn UI (đề xuất) | Ngữ nghĩa |
|---|---|---|
| 1 | **Thay thế hoàn toàn** | Xoá sạch dữ liệu cũ, chỉ giữ nội dung file nhập |
| 2 | **Đè nghĩa mới lên key trùng** | Key trùng → lấy giá trị **mới**; key chỉ có trong file → thêm; key chỉ có trên máy → giữ |
| 3 | **Giữ nghĩa cũ, chỉ thêm key mới** | Key trùng → giữ giá trị **cũ**; chỉ thêm key máy chưa có |

Bất biến: cả 3 chế độ đều **không** làm mất dữ liệu ngoài phạm vi khai báo, và chế độ 1 phải
là `role: .destructive` trong dialog.

## 2. Vấn đề gốc phát hiện được (đọc trước khi sửa)

- [ ] Chữ **"Gộp"** hiện mang **hai nghĩa trái ngược** tuỳ màn — đây là lý do phải chuẩn hoá:
  - Đè key trùng: `DictionaryCache.importEntries(isMerge:)` (`Sources/Services/Translation/Utils/DictionaryCache.swift:106`),
    `JunkFilterManager.importRules(mode: .merge)` (`Sources/Services/ChapterText/JunkFilterManager.swift:212`),
    `TranslateUtils.mergeTOCRules` (`Sources/Services/Translation/Utils/TranslateUtils.swift:883`).
  - Giữ bản cũ: `TTSReplacementManager.importRules(mode: .merge)` (`Sources/Services/TTS/Preprocessing/TTSReplacementManager.swift:262`),
    `SearchEngineTransfer.merged` (`Sources/Models/Dictionaries/SearchEngineTransfer.swift:79`).
- [ ] Vậy: 3 màn thiếu chế độ **3**, 2 màn thiếu chế độ **2**, 3 màn thiếu **cả 2 và 3**.
- [ ] Sau khi sửa, **xoá hẳn từ "Gộp" trần** khỏi UI; nhãn phải nói rõ ai thắng khi trùng key.

## 3. Bảng hiện trạng 13 điểm chọn file

Trong phạm vi (dữ liệu dạng key–value / danh sách có khoá):

| Màn / file | Picker | Chế độ hiện có | Nghĩa "gộp" hiện tại | Cần thêm |
|---|---|---|---|---|
| [DictionaryListView.swift:209](Sources/Views/Dictionary/DictionaryListView.swift:209) — VietPhrase/Names (chung + riêng truyện) | ✅ | 2 | đè key trùng | mode 3 |
| [SettingsView.swift:332](Sources/Views/Settings/Main/SettingsView.swift:332) — từ điển gốc `.dat`/`.txt` | ✅ | **0** | — (luôn thay thế) | mode 2 + 3 |
| [TTSDictionaryEditView.swift:203](Sources/Views/Settings/TTS/TTSDictionaryEditView.swift:203) — từ không phải tiếng Việt | ✅ | **0** | — (luôn thay thế) | mode 2 + 3 |
| [QuickTranslationRulesView.swift:83](Sources/Views/Settings/Translation/QuickTranslationRulesView.swift:83) — rule dịch `.txt` | ✅ | **0** | — (luôn thay thế) | mode 2 + 3 |
| [TTSReplacementManagerView.swift:108](Sources/Views/Settings/TTS/TTSReplacementManagerView.swift:108) — thay thế ký tự TTS | ✅ | 2 | **giữ bản cũ** | mode 2 |
| [JunkFilterManagementView.swift:119](Sources/Views/Settings/Translation/JunkFilterManagementView.swift:119) — lọc rác | ✅ | 2 | đè key trùng | mode 3 |
| [TOCRulesConfigView.swift:157](Sources/Views/Settings/Translation/TOCRulesConfigView.swift:157) — quy tắc mục lục | ✅ | 2 | đè theo `id` | mode 3 |
| [SearchEnginesConfigView.swift:117](Sources/Views/Settings/Search/SearchEnginesConfigView.swift:117) — công cụ tra cứu | ✅ | 2 | **giữ bản cũ** | mode 2 |
| [BookShareTargetSheet.swift:79](Sources/Views/Dictionary/BookShareTargetSheet.swift:79) — chia sẻ từ điển sang truyện khác | ❌ (không chọn file) | 2 | đè key trùng | mode 3 |

Ngoài phạm vi (nhập **file/asset**, không có khái niệm key–value → giữ nguyên):

- [ ] [ShelfView.swift:362](Sources/Views/Shelf/ShelfMain/ShelfView.swift:362) — nhập truyện `.txt`/`.epub`.
- [ ] [TTSModelManagerView.swift:143](Sources/Views/Settings/TTS/TTSModelManagerView.swift:143) — nhập model giọng ONNX.
- [ ] [RepositoryManagerView.swift:159](Sources/Views/Extensions/Manager/RepositoryManagerView.swift:159) — nhập tiện ích `.zip`.
- [ ] [BackupHubView.swift:150](Sources/Views/Settings/Backup/BackupHubView.swift:150) — nhập file backup (đã có `RestoreOptionsSheet` riêng, xem §7).

## 4. Việc chung (làm trước, các màn dùng lại)

- [ ] Tạo enum dùng chung, ví dụ `Sources/Models/Dictionaries/DataImportMode.swift`:
      `case replaceAll` / `case overwriteExisting` / `case keepExisting`.
      Phải là **1 primary type / file** và ≤ 400 dòng (luật `check_architecture.py`).
- [ ] Enum đặt ở tầng `Models` (hoặc `Common`) để cả `Services` và `Views` dùng được;
      **không** để trong `Views` vì Service cũng cần.
- [ ] Nâng cấp [DictionaryImportModeDialog.swift](Sources/Views/Dictionary/DictionaryImportModeDialog.swift)
      từ `onSelect(Bool)` → `onSelect(DataImportMode)` với 3 nút + "Hủy"; đổi tên modifier cho
      trung tính (không chỉ "dictionary") vì sẽ dùng cho rule/JSON, ví dụ `importModeDialog`.
      Sửa signature này là **breaking change** với 2 caller hiện tại (DictionaryListView,
      BookShareTargetSheet) — sửa cùng lượt.
- [ ] Viết một hàm merge dùng chung cho dạng "danh sách có khoá", tránh mỗi màn tự cài lại:
      key selector + mode → mảng kết quả, **giữ thứ tự bản trên máy** (quan trọng với
      TTSReplacement và JunkFilter vì thứ tự = thứ tự áp dụng).
- [ ] Chuẩn hoá message của dialog: mỗi màn hiện đếm số lượng khác nhau
      (`importDialogMessage`, `buildImportDialogMessage`). Quyết định: có bắt buộc mọi màn
      phải hiện preview "thêm N / cập nhật M / giữ K" hay chỉ những màn đang có.

## 5. Việc theo từng màn

### 5.1 Từ điển VietPhrase / Names — `DictionaryListView`

- [ ] `DictionaryCache.importEntries(from:type:isMerge:)`
      (`Sources/Services/Translation/Utils/DictionaryCache.swift:95`): đổi `isMerge: Bool` → `mode:`.
- [ ] `DictionaryTextFileStore.mergedRecords(imported:existing:isMerge:)`
      (`Sources/Models/Dictionaries/TextDictionary.swift:122`): đổi sang `mode:`; nhánh
      `keepExisting` = chỉ nối bản ghi có key máy chưa có.
- [ ] **Cẩn thận tombstone**: bản ghi `value` rỗng là "đã xoá" (`isDeleted`,
      `TextDictionary.swift:77`). `importEntries` đang xử lý riêng `existingDeleted` /
      `newDeletedFromImport` — phải định nghĩa rõ mode 3 làm gì với tombstone
      (xem câu hỏi Q1 ở §8).
- [ ] Nhánh từ điển **riêng truyện** trong `importFile(from:isMerge:)`
      (`Sources/Views/Dictionary/DictionaryListView.swift:494`) dùng đường khác
      (`parseRecords` → `mergedRecords` → `persist`) — sửa cả hai nhánh.
- [ ] Sau import vẫn phải: `TranslateUtils.clearCache()` +
      `clearBookDictCache(for:)` + `notifyDictionariesDidUpdate(bookId:)` (Reader chỉ dựng lại
      đoạn khi nhận notification này).
- [ ] Cập nhật message dialog ở `DictionaryListView.swift:223`.

### 5.2 Chia sẻ từ điển sang truyện khác — `BookShareTargetSheet`

- [ ] Đổi `onConfirm: (Book, Bool)` → `(Book, DataImportMode)`; sửa `shareToBook`
      (`DictionaryListView.swift:534`) theo.
- [ ] Message hiện nói "Thay thế / Gộp" — viết lại theo 3 chế độ.

### 5.3 Từ điển gốc trong Cài đặt — `SettingsView`

- [ ] `TranslationManager.importDictionary(from:type:)`
      (`Sources/Services/Translation/Manager/TranslationManager.swift:446`) hiện **xoá file đích
      rồi build lại trie** từ đúng file người dùng chọn ⇒ chỉ có mode 1.
- [ ] Để có mode 2/3 phải merge ở **dạng text nguồn** trước khi
      `DoubleArrayTrieBuilder().build(fromTxtFile:toDatFile:)`. Nhưng máy chỉ giữ `.dat`
      (đã build), không giữ `.txt` gốc cho `vietphrase`/`names`/`pronouns`/`luatnhan`
      ⇒ **chưa có nguồn để merge**. Xem Q2 ở §8 — đây là điểm chặn, không tự quyết.
- [ ] `ChinesePhienAmWords.txt` là copy file thẳng nên merge được ngay (dạng `key=value`).
- [ ] Sau import: giữ nguyên `DictionaryCache.invalidate(type:)` + toast hiện có.

### 5.4 Từ điển từ không phải tiếng Việt (TTS) — `TTSDictionaryEditView`

- [ ] `importDictionary(from:hasAccess:)`
      (`Sources/Views/Settings/TTS/TTSDictionaryEditView.swift:400`) hiện ghi thẳng
      `plistData` lên `TextPreprocessor.getWordsURL()` ⇒ **im lặng thay thế toàn bộ**, không hỏi gì.
- [ ] Thêm dialog 3 chế độ **sau** khi parse thành công (đã có `allWords` trong RAM để merge,
      nên cả 3 mode khả thi, không có điểm chặn).
- [ ] Giữ nguyên các guard hiện có: rỗng, > 5 MB, đuôi hợp lệ (`plist/json/csv/txt`).
- [ ] Sau import vẫn `TextPreprocessor.shared.loadResources()` + `loadDictionary()`.
- [ ] Toast đang báo `"Đã cập nhật \(importedWords.count) từ"` — với mode 2/3 con số này sai,
      phải báo theo số thực tế đã thêm/cập nhật.

### 5.5 Rule dịch nhanh — `QuickTranslationRulesView`

- [ ] `QuickTranslationRuleStore.importRules(text:source:)`
      (`Sources/Services/Translation/Engine/QuickTranslationRuleStore.swift:134`) hiện
      **ghi đè nguyên file** `QuickTranslateRules.txt` rồi validate-then-swap ⇒ chỉ mode 1.
- [ ] Mode 2/3 cần merge **theo dòng nguồn**, key = `pattern` bên trái dấu `=`. Rủi ro: mất
      comment / thứ tự / số dòng gốc (`sourceLine` đang hiển thị trên UI và trong
      `QuickTranslationRuleIssue`). Xem Q3 ở §8.
- [ ] Bất biến phải giữ: **validate-then-swap** — có hard error thì file cũ và snapshot đang
      chạy **không đổi** (`.rejected`). Merge xong phải validate lại **toàn bộ** kết quả, không
      chỉ phần mới.
- [ ] `importRules` cũng là đường đi của nút "Tải bộ rule mặc định"
      (`downloadDefaultRules` → `fetchRules` → `importRules(source: .downloaded)`) **và** của
      restore backup (`BackupConfigArchiver.swift:90`). Thêm tham số `mode` phải có default
      `.replaceAll` để 2 caller kia không đổi hành vi.
- [ ] Nút "Tải bộ rule mặc định" có nên hỏi 3 chế độ luôn không? (Q6 ở §8)

### 5.6 Thay thế ký tự TTS — `TTSReplacementManagerView`

- [ ] `TTSReplacementManager.ImportMode`
      (`Sources/Services/TTS/Preprocessing/TTSReplacementManager.swift:277`): `.merge` hiện =
      **giữ bản cũ** (bỏ qua `pattern` trùng). Đổi sang enum 3 case và **giữ nguyên** hành vi
      cũ cho `keepExisting`; thêm nhánh `overwriteExisting` (trùng `pattern` thì lấy bản mới,
      **giữ đúng vị trí cũ** trong mảng vì thứ tự = thứ tự áp dụng).
- [ ] `resetToDefaults(mode:)` (`TTSReplacementManager.swift:174`) dùng chung enum này —
      sửa enum là ảnh hưởng cả dialog "Khôi phục quy tắc mặc định"
      (`TTSReplacementManagerView.swift:136`). Xem Q6.
- [ ] `BackupDictionaryRestorer.mergeReplacementRules`
      (`Sources/Services/Backup/BackupDictionaryRestorer.swift:172`) mô tả trong comment là
      "đúng ngữ nghĩa `importRules(mode: .merge)`" — nếu đổi tên case, **phải sửa comment đó**
      kẻo tài liệu nói sai.
- [ ] Sửa 2 nhãn nút ở `TTSReplacementManagerView.swift:154-177` + message.

### 5.7 Lọc rác — `JunkFilterManagementView`

- [ ] `JunkFilterImportMode` (`Sources/Services/ChapterText/JunkFilterManager.swift:60`) →
      3 case; `.merge` hiện = **đè** (`currentMap[rule.pattern] = rule`).
- [ ] ⚠️ Nhánh `.merge` hiện **sort lại theo `pattern`** (`JunkFilterManager.swift:219`) làm
      **mất thứ tự áp dụng luật** người dùng đã kéo-thả (`moveRules`). Cần quyết định có sửa
      luôn không (Q4 ở §8) — đây là bug tiềm ẩn sẵn có, không phải do đổi 3 mode.
- [ ] Thêm nhánh `keepExisting`: chỉ thêm `pattern` chưa có, giữ nguyên thứ tự cũ.
- [ ] Guard `!rule.pattern.isEmpty` phải áp cho cả 3 nhánh.
- [ ] View `JunkFilterManagementView.swift:142-166`: 3 nút + message mới. Lưu ý view này
      **không** validate JSON trước khi mở dialog (khác `TTSReplacementManagerView.swift:122`
      có `decode` thử) — nên validate trước để không mở dialog cho file rác.

### 5.8 Quy tắc mục lục — `TOCRulesConfigView`

- [ ] `TranslateUtils.mergeTOCRules` (`Sources/Services/Translation/Utils/TranslateUtils.swift:883`)
      = đè theo `id`, giữ vị trí. Thêm hàm/nhánh `keepExisting`: `id` trùng thì bỏ qua.
- [ ] `TranslateUtils.calculateImportPreview(current:imported:isMerge:)`
      (`TranslateUtils.swift:854`) đang nhận `Bool` → đổi sang `mode` và bổ sung số liệu cho
      chế độ thứ 3 (khi đó `updateCount = 0`, `preservedCount` = toàn bộ bản trên máy).
- [ ] `replaceTOCRules` (`TranslateUtils.swift:910`) **tự bơm lại default rule bị thiếu** —
      đây là hành vi cố ý, mode 1 phải giữ. Mode 2/3 thì không bơm. Ghi rõ trong message.
- [ ] `ImportMode` cục bộ trong `TOCRulesConfigView.swift:10` → dùng enum chung, xoá enum cục bộ.
- [ ] View `TOCRulesConfigView.swift:139-155`: 3 nút; cập nhật `buildImportDialogMessage()`.
- [ ] Nhớ `TOCRuleSaveCoordinator.shared.scheduleSave` + `cancelPendingDebounce()` như đường cũ.

### 5.9 Công cụ tra cứu nhanh — `SearchEnginesConfigView`

- [ ] `SearchEngineTransfer.merged(current:imported:)`
      (`Sources/Models/Dictionaries/SearchEngineTransfer.swift:79`) = **giữ bản cũ**, nhận dạng
      trùng theo `signature` = (tên lowercase, mẫu URL) — **không** theo `id`.
- [ ] Vấn đề định nghĩa "key": nếu key = signature (tên + URL) thì mode 2 và mode 3 **giống nhau**
      (trùng cả tên lẫn URL thì đè hay giữ đều ra kết quả y nhau). Muốn mode 2 có nghĩa thì key
      phải là **tên** (đè `urlTemplate` mới lên công cụ cùng tên). Xem Q5 ở §8.
- [ ] `newCount(current:imported:)` (`SearchEngineTransfer.swift:98`) tính bằng
      `merged().count - current.count` — nếu đổi khoá nhận dạng thì hàm này phải tính lại.
- [ ] Phải giữ luật: `id` trùng mà nội dung khác thì cấp `id` mới (`ForEach` theo `Identifiable`).
- [ ] View `SearchEnginesConfigView.swift:125-135` + `applyImport(replacing:)` (`:216`) →
      `applyImport(mode:)`; sửa `importDialogMessage` (`:185`).

## 6. Ràng buộc phải tuân khi sửa (đã đối chiếu `CLAUDE.md` / `rules.md`)

- [ ] `Sources/Services/**` **không** `import SwiftUI`, **không** gọi `ToastManager.shared`
      ⇒ enum mode phải thuần Foundation; toast do View phát.
- [ ] File Swift mới ≤ **400 dòng**, đúng **1 primary type** ở top level.
- [ ] Chạy `python Scripts/check_architecture.py` **trước** khi sửa để chốt baseline (script hiện
      đỏ ~30 violation sẵn), chạy lại sau, chỉ chịu trách nhiệm violation mới.
- [ ] **Không** tạo/sửa/chạy/đọc bất cứ gì dưới `Tests/`; không dùng test làm bằng chứng.
- [ ] Máy đang là Windows ⇒ **không build được tại chỗ**. Phải nói rõ điều đó, không báo
      "đã kiểm chứng bằng build".
- [ ] Sau khi sửa code: `python Docs/CodeGraph/validate_links.py --explain` →
      cập nhật doc trong vùng `GENERATED` → `--accept` / `--no-change-needed` →
      thêm entry `CHANGELOG.md` (`[1.3.NNN]`, tiêu đề = subject commit) → chạy lại validator.
      Dự kiến stale: `04_call_graph`, `06_event_graph`, `07_dataflow`, `11_subsystems`,
      `10_risk_report` (đổi API tầng Service), cộng `02_file_graph`/`00_index`/`09`/`14` nếu
      **thêm file mới** (enum dùng chung).
- [ ] Nếu thêm/xoá file Swift: phải chạy `xcodegen generate` (trên macOS) — nhắc trong PR.

## 7. Liên quan nhưng KHÔNG đổi trong lần này (ghi để không bỏ sót)

- [ ] Khôi phục backup dùng lại đúng các primitive trên nhưng **hard-code chế độ gộp**:
      `BackupDictionaryRestorer.merge(...isMerge: true)` (`:75`),
      `BackupConfigArchiver.restoreTOCRules` → `mergeTOCRules` (`:111`),
      `restoreSearchEngines` → `SearchEngineTransfer.merged` (`:130`),
      `restoreQuickTranslateRules` → `importRules` (`:90`).
      Đổi signature ở tầng Service là **phải sửa các caller này**; giữ hành vi restore y như cũ
      bằng cách truyền mode tương đương, **không** đổi ngữ nghĩa restore.
- [ ] `RestoreOptionsSheet` có toggle "Ghi đè từ điển chung" — là 2 trạng thái riêng của luồng
      backup, **không** biến thành 3 chế độ trong lần này.
- [ ] `TTSReplacementManagerView` "Khôi phục quy tắc mặc định" và `JunkFilter` reset dùng chung
      enum ⇒ sẽ bị ảnh hưởng gián tiếp. Xem Q6.

## 8. Câu hỏi cần bạn quyết trước khi code (UNKNOWN — không tự suy đoán)

- **Q1 — Tombstone từ điển**: bản ghi `key=` (value rỗng) nghĩa là "đã xoá khỏi từ điển gốc".
  Ở chế độ 3 (giữ nghĩa cũ), nếu file nhập có nghĩa cho một key mà **máy đang đánh dấu đã xoá**
  thì: (a) giữ trạng thái đã xoá, hay (b) coi "đã xoá" không phải nghĩa nên nhận nghĩa mới?
- **Q2 — Từ điển gốc ở Cài đặt**: máy chỉ giữ `.dat` đã build, không giữ `.txt` nguồn ⇒ mode 2/3
  hiện **không có nguồn để merge**. Chọn: (a) giữ nguyên 1 chế độ cho màn này, (b) lưu thêm bản
  `.txt` nguồn (tốn dung lượng, VietPhrase rất lớn), hay (c) đọc ngược từ trie ra cặp key–value?
- **Q3 — Rule dịch nhanh**: merge theo dòng sẽ **mất comment và số dòng gốc** đang hiển thị trên
  UI. Chấp nhận đánh số lại, hay giữ 1 chế độ cho màn này?
- **Q4 — Lọc rác**: nhánh gộp hiện sort lại theo `pattern`, làm mất thứ tự kéo-thả. Sửa luôn
  trong lần này (giữ thứ tự cũ) hay để nguyên?
- **Q5 — Công cụ tra cứu**: key để so trùng là **tên** (mode 2 có nghĩa: đè URL mới) hay
  **tên + URL** (mode 2 ≡ mode 3)?
- **Q6 — Nút "Khôi phục mặc định" / "Tải bộ rule mặc định"**: có áp 3 chế độ cho các nút này
  luôn, hay chỉ áp cho luồng nhập-từ-file?
- **Q7 — Nhãn UI**: chốt đúng chữ hiển thị. Đề xuất ở §1; bạn muốn ngắn hơn
  ("Thay thế hoàn toàn" / "Ưu tiên file nhập" / "Ưu tiên dữ liệu hiện có") không?

## 9. Xác minh khi làm xong

- [ ] `python Scripts/check_architecture.py` — không có violation mới so với baseline đã chốt.
- [ ] `python Docs/CodeGraph/validate_links.py` — PASS 100% (read-only).
- [ ] Đọc lại từng caller của các hàm đã đổi signature (grep từng tên hàm, gồm cả
      `Sources/Services/Backup/**`) để chắc không còn chỗ nào truyền `Bool` cũ.
- [ ] Build trên macOS: `xcodegen generate` +
      `xcodebuild build -project FreeBook.xcodeproj -scheme FreeBook -destination 'platform=iOS Simulator,name=iPhone 15'`.
- [ ] Thử tay 9 màn ở §3: mỗi màn × 3 chế độ, kiểm tra số đếm trong toast khớp thực tế.



