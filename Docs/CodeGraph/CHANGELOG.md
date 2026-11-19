# CHANGELOG - Nhật ký Thay đổi CodeGraph Tàng Công Các

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **Tàng Công Các**.

## [1.3.990] - 2026-11-19

### feat: Cài đặt dịch thuật — giải thích của công tắc Quick Translate và Áp dụng rule dịch vào nút "?" cạnh tên

Trước: dưới tên "Bật dịch Quick Translate" và "Áp dụng rule dịch" luôn có một dòng chữ phụ giải thích (công tắc "Dịch Luật nhân hóa" đã bỏ ở commit trước).
Nay: dòng giải thích chuyển vào nút "?" (SectionHelpButton, popover) đứng ngay cạnh tên công tắc. Hàng dựng bằng HelpLabeledToggle (mới): HStack [tên][?] … [Toggle ẩn nhãn] — cố ý không đặt nút "?" trong nhãn của Toggle để chạm "?" không bật/tắt công tắc; nhãn trợ năng của công tắc vẫn là tên. Hàng "Áp dụng rule dịch" giữ thụt lề 16 như cũ.

File: Views/Settings/Translation/{HelpLabeledToggle (mới), TranslationSettingsView}, Views/Settings/Main/QuickTranslateRuleSettingsRows.

Chưa kiểm: chưa build, chưa chạy máy — cần xem trên máy popover "?" mở đúng trong hàng Form và chạm "?" không đổi công tắc.

## [1.3.989] - 2026-11-19

### feat: Gỡ từ điển LuatNhan khỏi dịch QT — bỏ công tắc Dịch Luật nhân hóa, tự dọn file và khoá cũ

Trước: dịch QT có thêm từ điển LuatNhan (Luật nhân hoá, mặc định tắt) — công tắc ở Cài đặt dịch thuật, Cài đặt trình đọc, Cài đặt dịch truyện tranh; thẻ LuatNhan.txt ở Từ điển chung; tải mặc định kèm luatnhan.txt; tra từ bôi đen trong Reader hiện dòng "Luật nhân"; sao lưu nhóm Từ điển chung gói LuatNhan.dat/.txt.
Nay: engine (VietPhraseTokenizer, TranslateUtils.lookupRawTranslation, TokenizeMemo, mapping memo, TranslationReadContext) không còn tra LuatNhan; ba công tắc, thẻ, mục tải mặc định, dòng tra từ và hai tên file trong sao lưu đều bỏ. Người chưa bật (mặc định) dịch y như cũ; khoá memo đổi dạng nên cache dịch cũ tự rụng.
Dọn sót: LuatNhanRetirement.removeLeftovers chạy đầu TranslationManager.loadAllDictionaries — còn translate/LuatNhan.dat / .txt hay khoá isTranslationLuatNhanEnabled thì xoá và ghi log "🧹 [LuatNhan]" (chỉ thấy khi đang bật ghi log; lỗi xoá file ghi ❌). Kiểm mỗi lần nạp nên không cần cờ "đã chạy". Khôi phục bản sao lưu cũ có LuatNhan ⇒ BackupDictionaryRestorer.restoreShared bỏ qua hai file đó, không báo lỗi; BackupSettingsArchiver chặn khoá cũ ở cả hai chiều.

File: Services/Translation/Manager/{LuatNhanRetirement (mới), TranslationManager, TranslationDictionaryState, TranslationReadContext, GlobalDictionaryTextExporter}, Services/Translation/Engine/VietPhraseTokenizer, Services/Translation/Utils/{TranslateUtils, TokenizeMemo}, Services/Translation/Extensions/TranslateUtils+MappingMemo, Services/Backup/{BackupPaths, BackupScope, BackupDictionaryRestorer, BackupSettingsArchiver}, Views/Settings/Translation/TranslationSettingsView, Views/Reader/{ReaderView, ReaderSettingsView, Extensions/ReaderView+Selection, Extensions/ReaderView+Suggestions (chỉ comment)}, Views/ComicReader/ComicTranslationSettingsSheet, Views/Dictionary/{ManageDefinitionsDraft, ManageDefinitionsView} (chỉ comment), .claude/rules/translation.md.

Chưa kiểm: chưa build (máy Windows), chưa chạy trên máy; không đọc / chạy Tests/ nên chưa biết test nào còn gọi API đã bỏ (isLuatNhanEnabled của TokenizeMemo, luatNhanDict…).

## [1.3.988] - 2026-11-19

### fix: Nhập quy tắc mục lục Thay thế toàn bộ không thêm lại quy tắc mặc định, công cụ tra cứu so trùng theo URL, lọc rác chỉ thêm mẫu mới không hỏi

Anh Bửu chốt 3 điểm còn ngỏ của commit nhập 3 lựa chọn: "Quy tắc mục lục không được thêm quy tắc mặc định khi Thay thế toàn bộ", "khoá Công cụ tra cứu là URL", "Lọc rác thì không có option như vậy, chỉ cần thêm từ không có vào thôi, phân hoa thường", "thay thế tts thì không phân hoa thường, key là từ gốc".

Trước (commit 159b5f17):
- Quy tắc mục lục — Thay thế toàn bộ dùng `TranslateUtils.replaceTOCRules`: thay bằng file rồi tự thêm lại quy tắc mặc định bị thiếu.
- Công cụ tra cứu — khoá so trùng là tên công cụ (không phân biệt hoa thường).
- Lọc rác — có popup 3 lựa chọn.
Nay:
- Quy tắc mục lục — Thay thế toàn bộ chỉ còn đúng danh sách trong file (`mergeTOCRules` lên danh sách rỗng, chỉ để chuẩn hoá chữ), không thêm lại quy tắc mặc định; muốn có lại thì dùng "Khôi phục mặc định". Nạp / lưu `toc_rules.json` không tự chèn mặc định khi file đã có (chỉ khi chưa có file), nên danh sách nhập giữ nguyên.
- Công cụ tra cứu — khoá so trùng là mẫu URL (bỏ khoảng trắng hai đầu, so đúng từng chữ), tên là giá trị: Gộp = cùng URL thì lấy tên trong file; Chỉ thêm key mới = cùng URL thì giữ tên cũ.
- Lọc rác — bỏ popup: "Nhập cấu hình (JSON)" mở bộ chọn file luôn, nhập chỉ thêm quy tắc có mẫu chưa có (so đúng từng chữ, phân biệt hoa thường), mẫu đã có giữ nguyên bản trên máy; toast "Đã nhập: thêm X, bỏ qua Y key đã có.". `JunkFilterManager.importRules(fromJSONString:)` bỏ tham số `mode`. Không còn cách ghi đè toàn bộ danh sách lọc rác bằng file.
- Thay thế ký tự TTS — giữ như 159b5f17: khoá là từ gốc (`TTSReplacementRule.matchKey`, không phân biệt hoa thường, giữ dấu).

File đã đụng: `Sources/Services/DataImport/TOCRuleImporter.swift`, `Sources/Models/Dictionaries/SearchEngineTransfer.swift`, `Sources/Views/Settings/Search/SearchEnginesConfigView.swift` (chú thích), `Sources/Services/ChapterText/JunkFilterManager.swift`, `Sources/Views/Settings/Translation/JunkFilterManagementView.swift`.

Chưa kiểm: không build được (máy Windows), chưa chạy trên máy. Chú thích của `DataImportModePopupModifier` (khung chung) còn kể "lọc rác" trong danh sách màn dùng popup — file của session chính, chưa sửa.

## [1.3.987] - 2026-11-19

### feat: Nhập dữ liệu ở 6 màn TTS và cài đặt luôn có 3 lựa chọn — Thay thế toàn bộ, Gộp, Chỉ thêm key mới

Anh Bửu: "nhập luôn có 3 option: thay thế toàn bộ (xoá danh sách cũ và chỉ giữ lại mới), gộp (vế trái trùng thì đè lên, chưa có thì thêm vào), chỉ thêm vào những key chưa có của vế mới" — popup giữa màn, 3 radio có mô tả, cuối là nút "Nhập file" (đã duyệt mockup).

Trước: mỗi màn nhập một kiểu — phiên âm NghiTTS luôn ghi đè toàn bộ không hỏi; phiên âm VieNeu luôn trộn không hỏi; thay thế ký tự TTS, lọc rác, quy tắc mục lục, công cụ tra cứu chọn file trước rồi hỏi Gộp / Ghi đè bằng confirmationDialog (có đoạn xem trước số đếm), và chữ "Gộp" mang hai nghĩa ngược nhau tuỳ màn (lọc rác, mục lục = đè key trùng; thay thế TTS, công cụ tra cứu = giữ bản cũ).
Nay: hàng "Nhập…" trong ngăn kéo … mở popup `.dataImportModePopup` (khung của commit d0929e34, mặc định chọn Gộp) ⇒ bấm "Nhập file" ⇒ chọn file ⇒ nhập theo chế độ đã chọn ⇒ toast số đếm ("Đã nhập: thêm X, cập nhật Y[, Z mục trùng y hệt]" / "Đã nhập: thêm X, bỏ qua Y key đã có" / "Đã thay thế toàn bộ: N mục (trước có M)"). Bỏ các confirmationDialog Gộp / Ghi đè và phần xem trước số đếm (chọn chế độ trước nên số đếm chuyển sang toast). File sai định dạng vẫn báo như cũ (toast hoặc hộp thoại của từng màn).

Luật chung cho cả 6 màn (`KeyedImportMerger`, `Sources/Models/Dictionaries/KeyedImportMerger.swift` + `KeyedImportSummary.swift`, hàm thuần):
- Thay thế toàn bộ = chỉ còn các mục của file; Gộp = khoá trùng lấy giá trị mới (thay tại chỗ, giữ vị trí + id cũ), khoá mới nối cuối, khoá chỉ có trên máy giữ; Chỉ thêm key mới = khoá trùng giữ bản cũ, chỉ nối khoá mới.
- Khoá lặp trong file: bản đứng sau cùng thắng. Mục mang id trùng mục khác ⇒ cấp id mới (danh sách có id).

Khoá từng loại:
- Phiên âm NghiTTS: từ gốc bỏ khoảng trắng hai đầu + chữ thường (như `TextPreprocessor.updateWord`; trước đây nhập .plist / .json giữ nguyên khoá có chữ hoa ⇒ mục chết). Ghi qua `TextPreprocessor.replaceAllWords` (xoá luôn cache phiên âm — đường cũ ghi plist rồi `loadResources()` không xoá cache). File rỗng / không có khoá hợp lệ ⇒ báo lỗi, không còn xoá trắng từ điển.
- Phiên âm VieNeu: `VieNeuJapaneseDictionary.normalizedKey` (gấp dấu phụ + chữ thường), bỏ mục khoá hoặc cách đọc rỗng. Ghi qua `replaceAll`.
- Thay thế ký tự TTS: `TTSReplacementRule.matchKey` (mẫu chữ thường, giữ dấu). Áp cho tầng đang mở (chung hoặc riêng của truyện), ghi qua `importRules(fromJSONString:mode: .overwrite, bookId:)` sau khi gộp. "Khôi phục mặc định" giữ nguyên hộp thoại hai lựa chọn cũ.
- Lọc rác: `pattern` đúng từng chữ (như `addRule`), bỏ mẫu rỗng. `JunkFilterManager.importRules` nhận `DataImportMode`, trả `KeyedImportSummary?`; bỏ enum `JunkFilterImportMode`. Sửa kèm: bản Gộp cũ sắp lại danh sách theo ABC (thứ tự là thứ tự áp dụng ⇒ đổi kết quả lọc) và dựng `Dictionary(uniqueKeysWithValues:)` ⇒ sập khi danh sách sẵn có mẫu trùng — nay giữ thứ tự, không sập.
- Quy tắc mục lục: `id` (bỏ khoảng trắng). Thay thế toàn bộ = `TranslateUtils.replaceTOCRules` — vẫn **tự thêm lại quy tắc mặc định bị thiếu** như "Thay thế toàn bộ" cũ (quy tắc mặc định không xoá được ở màn này); Gộp = `mergeTOCRules` (= "Gộp theo ID" cũ); Chỉ thêm key mới = `mergeTOCRules` với các quy tắc có id chưa có. Logic ở `TOCRuleImporter`.
- Công cụ tra cứu: tên công cụ (bỏ khoảng trắng, không phân biệt hoa thường), mẫu URL là giá trị — trước đây "Gộp" so cặp tên + mẫu URL và giữ bản cũ, nên khoá cũ khiến Gộp và Chỉ thêm key mới gần như trùng nhau. `SearchEngineTransfer.imported(current:imported:mode:)`; `merged` giữ nguyên cho khôi phục sao lưu (`BackupConfigArchiver`); bỏ `newCount` (chỉ hộp thoại cũ dùng).

File đã đụng:
- Mới: `Sources/Models/Dictionaries/KeyedImportMerger.swift`, `Sources/Models/Dictionaries/KeyedImportSummary.swift`, `Sources/Services/DataImport/PhoneticDictionaryImporter.swift`, `Sources/Services/DataImport/TTSReplacementRuleImporter.swift`, `Sources/Services/DataImport/TOCRuleImporter.swift` (thư mục `Services/DataImport/` để không đụng `Services/TTS/**`, `Services/Translation/**` — chỉ gọi API công khai có sẵn).
- Sửa: `Sources/Services/ChapterText/JunkFilterManager.swift`, `Sources/Models/Dictionaries/SearchEngineTransfer.swift`, `Sources/Views/Settings/TTS/TTSDictionaryEditView.swift`, `Sources/Views/Settings/TTS/VieNeuJapaneseDictionaryView.swift`, `Sources/Views/Settings/TTS/TTSReplacementManagerView.swift`, `Sources/Views/Settings/TTS/TTSReplacementManagerView+Layer.swift`, `Sources/Views/Settings/Translation/JunkFilterManagementView.swift`, `Sources/Views/Settings/Translation/TOCRulesConfigView.swift`, `Sources/Views/Settings/Search/SearchEnginesConfigView.swift`.

Chưa kiểm: không build được (máy Windows) — chỉ đọc code + `check_architecture.py`; chưa chạy trên máy (popup mở từ ngăn kéo rồi bộ chọn file, nhất là ở màn mở dạng sheet: Thay thế TTS từ Cài đặt TTS / hub truyện, Công cụ tra cứu từ Reader). Cần chạy `xcodegen generate` vì có file / thư mục mới. Chưa đo nhập từ điển NghiTTS lớn (~30k mục) theo chế độ Gộp (gộp trên RAM rồi ghi một lần như đường cũ).

## [1.3.986] - 2026-11-19

### feat: Bỏ nút bút chì trên hàng các danh sách TTS và cài đặt — chạm thân hàng là mở màn sửa

Anh Bửu: "các màn hình danh sách ... bỏ nút edit đi mà hãy sửa thành khi click vào hàng mỗi item sẽ hiển thị màn hình edit".

Trước: hàng của 6 màn danh sách có icon bút chì [Sửa] cạnh các icon khác; màn Thay thế ký tự TTS và Lọc rác chỉ mở được sheet sửa qua bút chì (chạm thân hàng không làm gì).
Nay: bỏ bút chì ở cả 6 màn; chạm vào thân hàng (khối chữ, rộng hết phần còn lại của hàng) mở sheet sửa. Các icon còn lại (Chuyển, Tắt/Bật, Xoá) và công tắc của Lọc rác vẫn bấm riêng được — chạm chỉ gắn vào khối chữ, hàng không bọc Button. VoiceOver có thêm thao tác "Sửa" trên hàng (`accessibilityAction(named:)`). Lọc rác đang ở chế độ kéo sắp xếp thì chạm hàng không mở sheet.

Màn đã đụng:
- Phiên âm NghiTTS — `Sources/Views/Settings/TTS/TTSDictionaryEditView.swift` (`wordRow`: chỉ bỏ bút chì, chạm đã có).
- Phiên âm VieNeu — `Sources/Views/Settings/TTS/VieNeuJapaneseDictionaryView.swift` (`row(key:)`; chữ nút "?" bỏ "hoặc icon bút").
- Thay thế ký tự TTS — `Sources/Views/Settings/TTS/TTSReplacementManagerView+Layer.swift` (`ruleRow`: thêm chạm hàng ⇒ `prepareForEdit`, bỏ bút chì ở `ruleActionIcons`).
- Lọc rác — `Sources/Views/Settings/Translation/JunkFilterManagementView.swift` (`ruleRow`: khối chữ rộng hết hàng + chạm mở sheet, bỏ `Spacer` và bút chì, giữ `Toggle`).
- Quy tắc mục lục — `Sources/Views/Settings/Translation/TOCRulesConfigView+Row.swift` (chỉ bỏ bút chì, chạm đã có).
- Công cụ tra cứu — `Sources/Views/Settings/Search/SearchEnginesConfigView.swift` (`engineRow`: chỉ bỏ bút chì, chạm đã có).

Chưa kiểm: không build được (máy Windows), chưa chạy trên máy. `.claude/rules/ui-conventions.md` (mục "Màn danh sách") vẫn ghi cụm icon [Sửa][Chuyển][Tắt/Bật][Xoá] — cần sửa thành "chạm hàng = sửa", session con không sửa file đó.

## [1.3.985] - 2026-11-19

### feat: Bộ lọc NSFW của Kệ đồng bộ công tắc NSFW chung, rời app tắt cả hai

Anh Bửu: "đồng bộ tuỳ chọn nsfw của kệ với những chỗ khác (chỉ nsfw/tất cả = bật)"; khoá màn hình / về màn hình chính thì chọn "Có, tắt cả hai".

- **Trước** (1.3.778): Kệ có bộ lọc riêng ba mức (Không hiển thị NSFW / Tất cả / Chỉ NSFW), độc lập với công tắc NSFW chung (`extFilterIncludeNsfw`) của Khám phá, Bộ sưu tập, Tải, Tìm, Cài đặt… Rời app chỉ Kệ tự về "Không hiển thị"; công tắc chung chỉ tự tắt lúc mở app và khi bấm Home.
- **Nay** (`ShelfNsfwFilterState`):
  - Kệ chọn "Tất cả" / "Chỉ NSFW" ⇒ bật công tắc chung; chọn "Không hiển thị NSFW" ⇒ tắt.
  - Chỗ khác bật công tắc ⇒ Kệ đang "Không hiển thị" chuyển sang "Tất cả"; chỗ khác tắt ⇒ Kệ về "Không hiển thị" (nghe `UserDefaults.didChangeNotification`). "Chỉ NSFW" vẫn chỉ áp cho Kệ.
  - Rời app (vào nền) và bấm Home ⇒ tắt **cả hai** (`resetToHidden` giờ tắt luôn công tắc chung).
  - Trạng thái khởi đầu theo công tắc chung; `MainTabView` tạo singleton lúc hiện để luật vào nền chạy cả khi chưa mở tab Kệ.
  - Log `📚 [ShelfNsfw]` ghi mỗi lần đồng bộ.
- Chú thích `ShelfNsfwFilter`, `RepositoryFilterPolicy.includeNsfwDefaultsKey` cập nhật theo luật mới.
- Kiểm: chỉ đọc code, **không build tại chỗ (Windows), chưa chạy trên máy** — cần thử: bật NSFW ở Khám phá rồi về Kệ, chọn "Chỉ NSFW" ở Kệ rồi sang Khám phá, khoá màn hình lúc đang nghe / xem nội dung 18+.

## [1.3.984] - 2026-11-19

### feat: Tiêu đề trang có nút back nằm hàng 2 sát lề trái, cuộn lên thu vào cạnh nút back

Anh Bửu: "các sheet, màn hình bị hiển thị title giữa do có nút ở góc trái thì bây giờ sửa lại hiển thị ở lề trái dưới các nút đó (nghĩa là sẽ hiển thị hàng thứ 2 của header)" → khi cuộn: "cuộn lên thì tiêu đề về nằm kế nút bên trái và giảm size lại để đảm bảo chỗ hiển thị".

- **Trước**: kiểu `.centered` (mọi `.backPageTitle` — 61 màn — các màn `isPresentedAsSheet ? .leading : .centered` khi được đẩy vào, trang con của sheet kiểu hub) đặt tiêu đề 22pt ở **giữa** thanh (ô `principal`).
- **Nay**: tiêu đề lớn của iOS (`navigationBarTitleDisplayMode(.large)`) ⇒ hàng 2, sát lề trái, dưới nút back / nút phải; cỡ 22pt đậm đặt toàn app ở `NavigationBarAppearance.applyLargeTitleFont` (cả bốn trạng thái thanh). Cuộn lên ⇒ hàng 2 thu lại, tiêu đề nhỏ 17pt nửa đậm hiện ở ô `topBarLeading` ngay cạnh nút back (rộng tối đa 230pt, dài thì cắt đuôi). Ô `principal` luôn rỗng ⇒ không còn tiêu đề giữa ở đâu.
- Mới `PageTitleCollapseProbe` (đầu dò UIKit 0×0 ở nền trang): tìm `UINavigationBar` qua chuỗi responder, theo dõi `frame`/`bounds` của thanh và `contentOffset` của scroll view lớn nhất trong trang; "đã thu" = nhãn tiêu đề lớn (UILabel chữ đúng tiêu đề, cỡ ≥ 20pt) bị ẩn / mờ < 50% / bị thanh cắt quá nửa. Không tìm thấy nhãn ⇒ coi như còn hiện (không bao giờ hiện chồng hai tiêu đề; dò hỏng thì tiêu đề chỉ cuộn đi).
- Kiểu `.leading` (tab gốc, gốc sheet) và `.hidden` không đổi. Cập nhật `ui-conventions.md`.
- Kiểm: chỉ đọc code, **không build tại chỗ (Windows), chưa chạy trên máy** — cần thử: độ cao hàng 2 với chữ 22pt, tiêu đề nhỏ có hiện/ẩn đúng lúc cuộn (List, Form, ScrollView, danh sách có ô tìm luôn hiện), trang con trong sheet kiểu hub (sheet thấp), tiêu đề dài, iOS 18 / 26.

## [1.3.983] - 2026-11-19

### feat: Ô tìm kiếm của các danh sách luôn hiện, cuộn xuống không ẩn

Anh Bửu: "luôn hiển thị ô tìm kiếm ở các danh sách đó dù cuộn xuống".

- `.searchable` của 9 danh sách thêm `placement: .navigationBarDrawer(displayMode: .always)` (trước để mặc định ⇒ iOS giấu ô tìm khi cuộn xuống): VP/Name (cả tab Từ đã xoá) `DictionaryListView`, rule dịch `QuickTranslationRuleListView`, lọc rác `JunkFilterManagementView`, phiên âm NghiTTS `TTSDictionaryEditView`, phiên âm VieNeu `VieNeuJapaneseDictionaryView`, thay thế ký tự TTS `TTSReplacementManagerView`, phiên trò chuyện AI `AIChatAllSessionsManagerView`, xung đột nhập từ điển `DictionaryImportConflictView`. Màn chọn chương quét tên AI vốn đã `.always`.
- Danh sách mới có ô tìm thì dùng cùng `placement` này.
- Kiểm: chỉ đọc code, **không build tại chỗ (Windows), chưa chạy trên máy**.

## [1.3.982] - 2026-11-19

### feat: Popup chọn cách nhập dữ liệu — Thay thế toàn bộ / Gộp / Chỉ thêm key mới, chọn xong mới chọn file

Anh Bửu: "sửa lại nhập luôn có 3 option: thay thế toàn bộ (xoá danh sách cũ và chỉ giữ lại mới), gộp (vế trái trùng thì đè lên, chưa có thì thêm vào), chỉ thêm vào những key chưa có của vế mới — mockup lại màn chọn này thành kiểu popup giữa màn hình, gồm 3 radio cho 3 option, mỗi option có mô tả và cuối cùng là nút nhập file" → duyệt mockup.

- Mới `Sources/Views/Common/DataImportModePopup/`: `DataImportModePopup` (thẻ kính giữa màn: tên + "Chọn cách nhập", ba hàng radio của `DataImportMode` kèm một dòng mô tả, nút đặc `.appFilled` ở cuối) + `.dataImportModePopup(isPresented:title:confirmTitle:confirmSystemImage:modes:initialMode:onConfirm:)`.
  - Trình bày bằng `fullScreenCover` nền trong, mở / đóng không trượt (transaction tắt animation), thẻ hiện mờ dần; lớp tối phủ cả thanh điều hướng, chạm ra ngoài là đóng (không nút Huỷ).
  - `onConfirm(mode)` chạy **sau khi** popup đóng hẳn (`onDismiss`) ⇒ chỗ gọi mở bộ chọn file ngay trong đó được.
  - Mặc định chọn "Gộp"; nút cuối mặc định "Nhập file", chỗ không chọn file (nhập từ truyện khác…) truyền `confirmTitle`.
- `DataImportMode`: tên lựa chọn đổi theo chữ anh — "Thay thế toàn bộ", "Gộp" (= đè key trùng), "Chỉ thêm key mới" — và mô tả một dòng mới. Ba dialog nhập rule cũ đang dùng `actionTitle` thì đổi chữ theo; các màn nhập được nối vào popup ở các commit sau của đợt này.
- Kiểm: chỉ đọc code, **không build tại chỗ (Windows), chưa chạy trên máy**; `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`.

## [1.3.981] - 2026-11-18

### feat: Quản lý nghĩa từ kiểu chip — bốn nhóm trong một thẻ, nút x góc chip để xoá nhanh

Anh Bửu: "mockup lại màn hình quản lý nghĩa từ" → xem bản gọn thì hỏi "còn cách nào gọn hơn không?" → chọn "Làm kiểu A" (chip theo nhóm), rồi thêm: "thêm x trên góc phải bên trên mỗi viên con nhộng để xoá nhanh nghĩa, nếu bị xoá thì thêm nút hoàn tác (dùng icon hết nhé)".

- **Trước**: `List` sáu section — "Từ đang chọn", "Phiên âm", rồi bốn nhóm từ điển; mỗi nghĩa một hàng ô nhập kèm bốn nút icon hẹp 26pt (lên, xuống, chèn ô trống phía trên, xoá); nhóm trống vẫn chiếm hai hàng ("Chưa có định nghĩa nào" + "Thêm nghĩa ở cuối").
- **Nay**: chữ gốc + phiên âm Hán Việt nằm trên một dòng; bốn nhóm (Name / VP × Riêng / Chung) nằm trong **một** thẻ, mỗi nhóm một dòng: nhãn bên trái, các nghĩa là viên con nhộng tràn dòng (`FlowLayout`), chip `+` nét đứt ở cuối. Nhóm trống chỉ còn nhãn + chip `+`.
  - Bấm thân chip ⇒ ô sửa hiện ngay dưới nhóm (tự focus), kèm hai nút icon ← → đổi chỗ; bấm lại chip hoặc phím Xong ⇒ đóng ô sửa.
  - Nút tròn góc trên phải mỗi chip: `xmark` xoá nhanh (xoá mềm, chip gạch ngang), chip đã xoá thì nút đổi thành `arrow.uturn.backward` để hoàn tác; bấm thân chip đã xoá cũng hoàn tác. Cả hai chỉ là icon.
  - Chip đứng đầu nhóm tô màu nhấn (nền mờ 18%, viền 60%): đó là nghĩa được dùng khi dịch (`TranslateUtils.getFirstMeaning`).
  - `+` thêm chip trống ở cuối và mở luôn ô sửa; chip vừa thêm mà bỏ trống thì tự gỡ khi rời nó (bấm x trên chip trống cũng gỡ hẳn, không để lại chip gạch ngang).
  - Chân màn: "Thay đổi được lưu khi đóng" / "Đã sửa N nhóm · lưu khi đóng".
- **Bỏ**: nút "chèn ô trống phía trên" (thêm ở cuối rồi dùng ← → đưa về chỗ cần) ⇒ xoá `ManageDefinitionsDraft.insertEmptyRow` và file `ManageDefinitionRowView.swift`.
- **Không đổi**: cách lưu (ghi đĩa một lần lúc đóng màn, `saveAllChangesToDisk` / `mergedMatches` giữ nguyên), bốn nhóm sửa được và nhãn nguồn, hai chỗ mở màn (panel Dịch của Reader, sheet Sửa từ).
- File: `ManageDefinitionsView.swift` (dựng lại phần giao diện bằng `ScrollView`, thẻ dùng `AppGlassSheetModifier.rowFill`; phiên âm tính một lần lúc mở thay vì mỗi lượt `body`), mới `ManageDefinitionChipView.swift` + `ManageDefinitionGroupView.swift`, `ManageDefinitionsDraft` thêm `removeRow` / `isDiscardableBlank`, `appendEmptyRow` trả `id`. Nút góc nằm **trong** khung layout của chip (chip lùi 6pt) chứ không nhô ra như `ChipCornerBadge`, vì nó bấm được.
- Kiểm: bốn file qua `swiftc -frontend -parse` (chỉ cú pháp); `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. **Không build tại chỗ (Windows), chưa chạy trên máy** — chưa kiểm: chip dài có cắt đuôi ở 240pt không, vùng chạm của nút góc trên chip ngắn, focus ô sửa khi chuyển giữa hai nhóm, bàn phím có che ô sửa của nhóm cuối không.

## [1.3.980] - 2026-11-18

### feat: Tìm trong chương cuộn vô hạn hai đầu — kéo lên tìm chương trước, kéo xuống tìm chương sau

Anh Bửu: "sửa lại tìm trong chương theo ý của tôi đã" — "tìm trong chương hay là load vô hạn 2 đầu, đầu trên sẽ tìm tiếp trang trước, đầu dưới sẽ load trang sau". Hỏi thêm thì chọn: chương chưa tải về máy ⇒ "tải từ nguồn rồi tìm"; mỗi lần kéo tới một đầu ⇒ "đúng 1 chương".

- **Trước**: sheet chỉ tìm trên các chương đang nằm trong RAM của Reader (chương đang đọc + vài chương lân cận), không nạp thêm được.
- **Nay**: mở sheet vẫn tìm ngay trên chương đang đọc + các chương **liền kề** đã dựng trong RAM (không tải gì) và cuộn tới chương đang đọc. Danh sách có hàng ở **hai đầu**: kéo tới đầu trên ⇒ tìm thêm **một** chương liền trước, đầu dưới ⇒ **một** chương liền sau; hàng đó cũng bấm được (chương vừa tìm không có kết quả thì hàng vẫn trên màn ⇒ bấm để tìm tiếp), hiện "Đang tìm <chương>…", lỗi tải thì "Không tải được … · Bấm để thử lại", hết thì "Đầu truyện" / "Hết truyện". Mỗi chương đã tìm có tiêu đề + số kết quả; không có kết quả thì ghi "Không có kết quả trong chương này" để thấy đã tìm tới đâu. Đổi từ khoá chỉ khớp lại các chương đã nạp (ngoài main, chờ 250 ms), không nạp lại.
- **Nạp chương** (`ReaderViewModel.loadChapterForSearch`, file mới `ReaderViewModel+Search.swift`): chương có sẵn trong RAM ⇒ dùng luôn; không thì **cùng đường với Reader** — `ChapterContentRepository.load` (file đã tải, không có thì tải qua tiện ích; tải từ nguồn thì chương được lưu lại và mục lục đánh dấu "đã tải" như lúc đọc) rồi `performChapterTranslationOffMainActor` với đúng cài đặt dịch / phồn → giản / tiêu đề hiện tại ⇒ cùng `ParagraphItem.id`, bấm kết quả nhảy đúng đoạn. **Không** ghi vào cache / cửa sổ trượt của Reader. Để dùng chung, tách `chapterContentRequest(at:forceRefresh:interactive:)` + `noteChapterFetchedFromSource(_:)` khỏi `loadChapterContentFromExtension` và `chapterTitleLayout(bookId:)` (hai cờ `showChapterTitle_` / `removeDuplicatedTitle_`) khỏi `processAndSaveChapter` — hành vi Reader không đổi.
- **Trạng thái** ở `ReaderSearchSession` (`@Observable`, mới): dãy chương đã tìm luôn **liền** `lower...upper`; mỗi đầu một lượt tải tại một thời điểm, hai đầu độc lập; chương nạp xong trong lúc đang khớp lại thì lượt khớp tự khớp thêm. Đóng sheet ⇒ huỷ mọi lượt.
- **Danh sách** đổi từ `List` sang `ScrollView` + `LazyVStack` + `scrollPosition(id:anchor: .top)`: chèn chương lên đầu vẫn giữ nguyên chỗ đang xem (bài học 1.3.822). Hàng hai đầu nạp khi **hiện ra** (`onAppear` trên khung ngoài, danh tính không đổi theo trạng thái) ⇒ không tự nạp liên tục khi hàng còn nằm trên màn — đúng "mỗi lần một chương"; vì vậy không dùng `LoadMoreFooter` (cái đó tự nạp tiếp khi chân còn trên màn).
- Kiểm: các file Swift đã sửa / thêm qua `swiftc -frontend -parse` (chỉ cú pháp); `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. **Không build tại chỗ (Windows), chưa chạy trên máy** — chưa kiểm: vị trí cuộn khi chèn chương lên đầu, hàng đầu trên có tự nạp một chương ngay lúc mở sheet không (khi chương đang đọc ngắn), tốc độ tìm chương phải tải từ nguồn.

## [1.3.979] - 2026-11-18

### fix: CI build lại được — ONNX Runtime chép vào repo, file nhị phân lưu ở repo FreeBook-deps vì repo của Microsoft đã mất

CI của 1.3.978 hỏng ở bước "Resolve and patch Package dependencies", cả lần chạy lại: `xcodebuild -resolvePackageDependencies` không clone được `https://github.com/microsoft/onnxruntime-swift-package-manager.git` (`fatal: could not read Username` — GitHub trả 401 cho repo không tồn tại). Kiểm tra 2026-11-18: cả `microsoft/onnxruntime-swift-package-manager` lẫn `microsoft/onnxruntime` đều trả 404 qua API; có issue công khai báo cùng lúc (onnx/onnx #8842, 2026-11-17). Bước biên dịch chưa chạy tới — code của 1.3.978 chưa được biên dịch.

Anh Bửu: "có thể tải hết file cần thiết về không, tôi sợ repo đó biến mất không có để build tiếp" → chọn "tạo repo mới bỏ lên release repo đó".

- **Mã nguồn gói chép vào repo**: `Vendor/onnxruntime-swift-package-manager/` = gói SPM cục bộ. `objectivec/` chép nguyên văn từ commit `b7fb7f7dea8a2469e6335d95a61b8f36d0dc83b2` ("Update ORT to 1.24.2 (#43)" — commit upstream của người bảo trì ORT, lấy từ bản fork `masicai/onnxruntime-swift-package-manager`), đúng bản 1.24.2 mà các lần CI xanh trước đã resolve; chỉ giữ file target `OnnxRuntimeBindings` cần (gói gốc cũng `exclude` test / tài liệu / training), bỏ product `onnxruntime_extensions` (app không dùng). Kèm `LICENSE` (MIT, Microsoft). `Package.swift` viết lại gọn, ghi nguồn gốc và cách nâng bản.
- **File nhị phân 52 MB** (`pod-archive-onnxruntime-c-1.24.2.zip`) tải từ `download.onnxruntime.ai` của Microsoft, SHA-256 `f7100a99…6e600b54` **trùng** checksum gốc, đưa lên release `onnxruntime-1.24.2` của repo mới **`buudvh/FreeBook-deps`** (public, README ghi nguồn gốc + checksum + "đừng xoá"); đã tải lại ẩn danh qua link release, checksum vẫn khớp. `binaryTarget(url:checksum:)` trỏ tới link đó.
- `project.yml`: `onnxruntime-swift-package-manager` đổi từ gói git sang `path: Vendor/onnxruntime-swift-package-manager`; tên package / product (`onnxruntime`) / target (`OnnxRuntimeBindings`) giữ nguyên ⇒ phần còn lại của `project.yml` và `import OnnxRuntimeBindings` không đổi.
- Kiểm: `Package.swift` qua `swiftc -frontend -parse` (chỉ cú pháp — `swift package dump-package` trên Windows lỗi liên kết của toolchain, không phải lỗi manifest). **Chưa push** (anh Bửu: "fix lỗi nhưng khoan push đã") ⇒ chưa biết CI resolve / biên dịch được không.
- Các package git còn lại (SwiftSoup, ZIPFoundation, espeak-ng-spm, SafariConverterLib) vẫn tải từ repo của bên thứ ba như cũ.

## [1.3.978] - 2026-11-18

### fix: Thay thế từ TTS không phân biệt hoa thường — lúc đọc lẫn chip R/C

Anh Bửu báo chip gợi ý của "Thêm thay thế TTS" sai, rồi tự tìm ra nguyên nhân: "có vẻ do R/C phân biệt hoa thường"; được hỏi sửa tới đâu thì chọn "cả lúc đọc cũng không phân biệt".

- **Trước**: luật chữ khớp token **bằng đúng cả hoa thường** (1.3.940) — rule `sasuke` không thay "Sasuke" đầu câu, và chip R/C của sheet "Thêm thay thế TTS" (lẫn sheet Thêm / Sửa quy tắc) không hiện rule đó khi bôi đen "Sasuke". Chip R/C không bị 1.3.974 đổi — phép lọc `pattern == ` đã có từ trước.
- **Nay**: một khoá khớp duy nhất `TTSReplacementRule.matchKey` (hạ chữ thường, **giữ dấu**: `Hà` vẫn không đụng `Ha` / `Hàn`; chuỗi thay thế giữ nguyên chữ người dùng gõ) dùng cho mọi phép so mẫu:
  - lúc đọc — `TTSReplacementPlan` (luật chữ; luật ký hiệu không có hoa thường);
  - gộp tầng riêng với tầng chung (`mergedRules`: rule riêng — kể cả đang tắt — chặn rule chung cùng mẫu khác hoa thường);
  - `addRule` hai tầng, màn Sửa quy tắc (đè luật trùng), nhập JSON / khôi phục mặc định ở chế độ gộp, khôi phục sao lưu (`BackupDictionaryRestorer`);
  - cảnh báo "trùng mẫu" của `TTSReplacementRuleValidator`, câu mô tả luật chữ, chữ giải thích ở màn Thay thế ký tự TTS;
  - chip R/C (`TTSReplacementSuggestionSection.ruleChips`).
- **Ảnh hưởng tới luật đang có**: luật cho tên riêng giờ thay cả từ thường cùng chữ (rule `Long` thay cả "long") — anh Bửu đã được báo trước khi chọn. Một tầng đang có hai luật chỉ khác hoa thường (`Sasuke`, `sasuke`): lúc đọc luật **đứng trước** thắng, hàng của chúng hiện cảnh báo trùng mẫu; thêm / sửa lần sau sẽ đè nhau như mọi luật trùng. Dữ liệu không tự sửa.
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift` (`TTSReplacementManager.swift` legacy giữ nguyên số dòng). Không build tại chỗ (Windows), chưa chạy trên máy.

## [1.3.977] - 2026-11-17

### feat: Gemini Web chạy được khi chưa đăng nhập Google (chế độ khách)

Anh Bửu: "gemini web cũng có thể hoạt động tốt dù không đăng nhập, làm thêm đi".

- **Hành vi**: profile Gemini Web không còn báo "Chưa đăng nhập Google" khi chat / quét tên riêng / kiểm tra kết nối — chưa đăng nhập thì lượt chạy **chế độ khách**. Đã đăng nhập thì giữ nguyên đường cũ (giao thức `StreamGenerate`, chọn model, lưu lịch sử). Còn cookie Google mà trang vẫn là phiên khách (cookie hết hạn) cũng rẽ sang chế độ khách.
- **Vì sao khách phải điều khiển trang** (thử thật 2026-11-17, Chromium giả lập mobile, chưa đăng nhập, 3 tin): trang khách không có token `SNlM0e`, và sau khi gửi tin **không** gọi `StreamGenerate` — chỉ thấy `batchexecute` cùng `geminiweb-pa.clients6.google.com/v1/processSession` và bước chứng thực `waa-pa…/Waa/Create`. App không dựng lại API đó (là vượt cơ chế chống lạm dụng của Google): app gõ câu hỏi vào ô nhập của trang, bấm gửi, đọc câu trả lời từ DOM — `GeminiWebGuestPageContract`.
- **Dùng lại bộ điều khiển trang của ChatGPT Web**: `ChatGPTWebSessionController` / `ChatGPTWebClient` / `ChatGPTWebTurnQueue` nay nhận một `ChatGPTWebSite` (URL + ba đoạn JS trả cùng khuôn `Snapshot` / `SubmitOutcome`), mỗi trang một WebView ẩn, hàng đợi và client riêng (`.shared` = ChatGPT, `.geminiGuest` = Gemini khách). Hành vi ChatGPT Web không đổi. Lỗi của bộ điều khiển đổi sang `GeminiWebError` ở `GeminiWebClient+Guest` nên luật dừng quét / thông điệp Gemini Web chạy như cũ.
- **Trang khách** (đã thử): ô nhập Quill `rich-textarea .ql-editor` — gán chữ bằng cách dựng thẳng các `<p>` (trang dùng Trusted Types nên không `innerHTML`) + `input`, **không focus** (bài học bàn phím 1.3.976); nút gửi `.send-button` (lớp `submit` / `stop`), bấm bằng `click()` (Enter ở bản mobile chỉ xuống dòng); câu trả lời `model-response` › `message-content .markdown`, xong khi `aria-busy="false"` và `.response-footer.complete`; nạp lại `/app/<id>` bị đưa về `/app` (cuộc chat khách chỉ sống trong trang). Model do trang chọn (lúc thử: Gemini 3.5 Flash-Lite).
- **Khác bản đã đăng nhập**: mỗi lượt là một cuộc chat mới (không nối tiếp được) ⇒ màn AI gửi kèm cửa sổ tin gần nhất kể cả khi bật "Lưu chat vào lịch sử Gemini"; không chọn model; quét tên riêng dùng ~10.000 chữ/lượt và tách chương dài thay cho 40.000. Ba chỗ đó hỏi `GeminiWebGuestMode.isLikelyGuest` (bản ghi nhớ đồng bộ, `GeminiWebClient` cập nhật mỗi lần đọc cookie; màn AI đọc lại khi mở).
- **Bộ đọc chữ câu trả lời dùng chung**: hàm JS `__collectText` tách ra `HiddenWebAnswerTextScript` (ChatGPT ẩn danh, ChatGPT đã đăng nhập, Gemini khách), thêm bỏ phần đầu khối code của Gemini (`.code-block-decoration`).
- **UI**: hàng tài khoản Gemini Web ghi "Chế độ khách (chưa đăng nhập Google)" kèm giải thích; thông điệp `notSignedIn` đổi cho đúng nghĩa mới (Gemini đòi đăng nhập cho việc đang làm). "Load từ API" vẫn cần đăng nhập.
- Kiểm: tám đoạn JS trích từ file Swift qua `node --check`; logic đọc trạng thái + gán chữ + dò nút gửi của bản chính thức chạy trên trang khách thật (nhận ~7.200 ký tự, nút gửi bật, `activeElement` vẫn là `body`); bộ đọc chữ chạy trên ba câu trả lời khách thật (danh sách, khối code, bảng). `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. **Không build tại chỗ (Windows), chưa chạy trên iPhone** — chưa kiểm: UA iPhone có nhận cùng trang khách không, trang hiện gì khi khách hết lượt / bị bắt đăng nhập (chưa gặp ⇒ sẽ ra `timeout` / `protocolChanged` kèm log), giới hạn độ dài câu hỏi của khách. Log: `🤖 [GeminiGuest]`.

## [1.3.976] - 2026-11-17

### fix: ChatGPT Web không còn bật bàn phím mỗi lần WebView ẩn chạy

Anh Bửu báo: "có vẻ mỗi lần mở webview chatgpt web lên đều có bàn phím hiển thị lên".

- **Nguyên nhân**: phần tử trong trang được focus thì WebKit mở phiên nhập cho WKWebView và giành bàn phím của app. Có hai nguồn focus: (1) đoạn JS gán câu hỏi của app tự gọi `focus()` lên ô nhập (cả trang ẩn danh lẫn trang đã đăng nhập); (2) trang đã đăng nhập tự focus vùng soạn thảo của nó. Trang ẩn danh không tự focus (thử thật: sau khi nạp `document.activeElement` là `body`).
- **Sửa**: JS gán chữ không còn gọi `focus()` — thử thật trên cả hai trang: gán `textarea` (setter gốc + `input`) và sự kiện `paste` vào vùng soạn thảo đều nhận chữ khi ô nhập không được focus, trang đã đăng nhập gửi và trả lời bình thường. Thêm `ChatGPTWebPageContract.focusGuardScript`, gắn bằng `WKUserScript` lúc document bắt đầu: `focus()` của trang thành hàm rỗng, phần tử vẫn kịp được focus bằng đường khác thì bị bỏ focus ngay. Lưới an toàn phía UIKit: sau khi gán chữ dự phòng và sau khi gửi, WebView ẩn `endEditing(true)` (chỉ tác động responder bên trong WebView ẩn, ô nhập của app không bị đụng).
- Đường dự phòng `execCommand('insertText')` (chỉ chạy khi sự kiện `paste` không đưa được chữ vào vùng soạn thảo) vẫn cần focus trong tích tắc ⇒ bàn phím có thể nháy ở đúng trường hợp đó; có dòng log riêng.
- `ChatGPTWebPageContract.swift` vượt 400 dòng ⇒ tách phần JavaScript sang `ChatGPTWebPageContract+Scripts.swift` (không đổi nội dung script ngoài các điểm trên).
- Chế độ AI của Google cũng gọi `focus()` trong JS gán chữ của lượt nối tiếp (`GoogleAIModePageContract`) — cùng kiểu lỗi nhưng anh Bửu chưa báo, **chưa sửa**.
- Kiểm: năm đoạn JS trích từ file Swift qua `node --check`; `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), **chưa chạy trên iPhone** — chưa xác nhận trên máy là bàn phím hết bật.

## [1.3.975] - 2026-11-17

### fix: Từ điển phiên âm NghiTTS / VieNeu khớp từ có dấu nối - hoặc . theo luật token của thay thế TTS, sheet Thêm từ nhận từ gốc có dấu nối

Anh Bửu: "tôi nhớ rule xác định từ của thêm phiên âm vieneu và nghitts không xác định các từ có nối - hoặc . đúng như thay thế tts đúng không, sửa cho nó áp dụng được".

- **Đúng là lệch, ở ba chỗ** (thay thế từ TTS tách token bằng `TTSReplacementTokenizer` trên chữ gốc của đoạn; từ điển phiên âm thì không):
  - **Lúc nhập** — `AddWordSheet.validateKey` báo "Từ gốc không được chứa dấu câu" cho **mọi** dấu câu, nên gõ `Kamar-Taj`, `S.H.I.E.L.D`, `e-mail` là nút Lưu khoá.
  - **NghiTTS lúc đọc** — `TextPreprocessor.preprocess` đổi mọi `-` không nằm giữa hai chữ số thành dấu cách (`cleanEmojisAndSymbols`) **trước** khi tra từ điển ⇒ mục có `-` không bao giờ khớp, còn mục `Kamar` lại khớp bên trong "Kamar-Taj"; mục có `.` chỉ khớp khi không quá 4 mẩu (bước tra cụm) và không bị bước đọc số làm vỡ.
  - **Cả hai engine lúc đọc** — từ điển tra **sau** `processVietnameseText`, lúc đó số La Mã / số thập phân đã làm vỡ token: `S.H.I.E.L.D` → `S.H.1.E.L.D`, `X-Men` → `10-Men`, `v1.2` → `v một phẩy hai`. (VieNeu vốn tra được cả token có `-` / `.` qua `PreprocessorRegex.token` khi token không bị vỡ: `Kamar-Taj`, `Wi-Fi`, `U.S.A`.)
- **Một bộ tách token cho cả ba nơi** (`TTSPhoneticJoinedWords`, `Services/TTS/Preprocessing/`): từ có nối = token từ của `TTSReplacementTokenizer` có `-` / `.` bên trong (kẹp giữa hai chữ / số, không dấu cách). Lúc đọc, chữ **gốc** của đoạn được cắt quanh các từ nối có trong từ điển: cả token khớp mới áp (mục `Kamar-Taj` thắng mục `Kamar`; `Kamar-Taj-Mahal`, `Kamar- Taj` không khớp mục `Kamar-Taj`), cách đọc đi nguyên văn, phần chữ còn lại đi nguyên đường cũ rồi ghép lại (khoảng trắng ở chỗ nối giữ theo chữ gốc, hai cách đọc không dính liền nhau).
  - **NghiTTS**: `TextPreprocessor.preprocessAroundJoinedWords` (`TextPreprocessor+JoinedWords.swift`), gọi ở đầu `preprocess`; theo công tắc "Sử dụng từ điển" sẵn có; tra khoá hạ chữ thường rồi khoá đã gấp dấu phụ.
  - **VieNeu Nano + Turbo**: `VieNeuJapanesePreprocessor.synthesisText(for:)` (`VieNeuJapanesePreprocessor+JoinedWords.swift`) gói `normalizeVietnameseText` → `applyUsingStoredFlags`; `VieNeuTTSService` và `VieNeuTurboTextFrontend` gọi hàm này thay cho cặp gọi cũ; theo công tắc "Áp dụng từ điển phiên âm VieNeu".
  - **Lúc nhập**: `TTSPhoneticKeyValidator` — `-` / `.` kẹp giữa hai chữ / số được nhận; đứng mép hoặc đứng liền nhau (`Kamar-`, `-Taj`, `a--b`, `U.S.A.`) báo "Dấu - hoặc . chỉ được nằm giữa hai chữ / số, không dấu cách". `AddWordSheet.validateKey` chỉ còn gọi hàm này.
- **Không đổi**: mục không có `-` / `.` (đoạn không có từ nối nào khớp thì không token hoá gì thêm, đi đúng đường cũ; ô Từ gốc không có `-` / `.` báo lỗi y như trước); từ nối **không** có mục riêng vẫn đọc từng phần như cũ ("Sasuke-kun" với mục `Sasuke`, 1.3.960); mục có cách đọc rỗng không được áp (không làm rơi chữ); sheet sửa từ (`EditWordSheet`) chỉ sửa cách đọc nên không có gì để kiểm; từ gốc lấy từ chữ bôi đen ở Reader vẫn không bị kiểm cho tới khi sửa ô.
- **Giới hạn**: gạch ngang dài (`–`, `—`) không phải dấu nối — như thay thế từ TTS; bộ phân loại đọc lai (`VieNeuForeignTextClassifier`) vẫn đếm từng phần của từ nối là tiếng nước ngoài dù từ điển đã có mục cho cả từ; chip gợi ý JP / EN cho từ gốc có dấu nối chưa xét từng phần.
- `.claude/rules/tts.md` ghi luật từ nối của từ điển phiên âm.
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift` (`TextPreprocessor.swift` 1119 / 1121, bốn file mới 26–84 dòng); 8 file Swift đã sửa / thêm qua `swiftc -frontend -parse` (chỉ cú pháp); bộ tách token + cắt + ghép + luật ô Từ gốc mô phỏng bằng bản chép Python trên 9 câu và 13 từ gốc (toolchain Swift trên Windows không biên dịch được). **Không build tại chỗ (Windows), chưa chạy trên máy** — chưa nghe NghiTTS / VieNeu đọc mục có dấu nối, chưa xem câu báo lỗi mới của sheet Thêm từ trên iPhone.

## [1.3.974] - 2026-11-17

### feat: Chip phiên âm Anh / Nhật ở sheet Thêm thay thế TTS, dãy chip gợi ý ở sheet sửa quy tắc thay thế và sửa từ điển phiên âm NghiTTS / VieNeu

Anh Bửu: "thêm phiên âm anh và nhật (nếu có) vào chip gợi ý của thêm thay thế tts, bấm vào thì tự thêm từ vào chuỗi thay thế và bật kích hoạt thay thế"; "thêm chip thay thế vào sửa từ trong từ điển phiên âm của vieneu, nghitts, và danh sách từ thay thế tts".

- **Một section chip dùng chung cho bốn sheet** (`TTSReplacementSuggestionSection`, `Views/Settings/TTS/`): tiêu đề "Gợi ý" + nút "?", chip viền capsule xếp `FlowLayout`, badge góc trên phải, chip vừa bấm viền màu nhấn; không có chip nào thì không vẽ gì.
  - **Reader › Thêm thay thế TTS** (`AddTTSReplacementSheet`): sau chip rule đã có (R / C, rule tắt ⇒ mờ — giữ nguyên luật 2026-09-30) có thêm chip **JP** / **EN** của mẫu đang nhập. Bấm chip phiên âm ⇒ điền chuỗi thay thế **và bật** "Kích hoạt thay thế".
  - **Thay thế ký tự TTS › sheet Thêm / Sửa quy tắc** (`TTSReplacementManagerView`, tầng chung lẫn tầng riêng của truyện): cùng dãy chip — rule trùng mẫu ở cả hai tầng (trừ chính rule đang sửa) + JP / EN; bấm ⇒ điền chuỗi thay thế + đặt công tắc "Kích hoạt quy tắc" (chip phiên âm: bật; chip rule: theo rule đó).
  - **Sửa từ của từ điển phiên âm NghiTTS và VieNeu-TTS** (`EditWordSheet`, tách khỏi `TTSDictionaryEditView.swift` ra file riêng — file legacy đó giảm 596 → 557 dòng): chip **NGI** / **VIE** (cách đọc đang lưu ở hai từ điển, như sheet Thêm từ) + JP / EN; bấm ⇒ điền cách đọc (sheet này không có công tắc). Không có nhấn-giữ-để-xoá; màn VieNeu vẫn có chip EN.
- **Bấm chip là thay nội dung ô, không nối thêm** — như mọi chip sẵn có của app (chip rule R / C, chip gợi ý của sheet Thêm từ).
- **"Nếu có"** (`TTSPhoneticSuggestionBuilder.transliterations(for:)`, mới — không tra từ điển phiên âm): không chip nào khi từ có dấu tiếng Việt (cùng phép thử với `VietnameseTokenGate`, hàm `hasVietnameseDiacritic` bỏ `private`), có số / dấu cách / dấu chấm / chữ Hán, hoặc dưới 2 chữ. Chip JP chỉ hiện khi từ cắt được hết thành âm tiết romaji; kana đổi sang romaji trước và chỉ có chip JP; từ có gạch nối ("Sasuke-kun") xét từng phần; mẫu viết hoa chữ đầu thì chuỗi gợi ý cũng viết hoa chữ đầu ("Sasuke" → "Xa xư kê"). Chip chữ rõ = cách đọc bộ phiên âm sẽ chọn (`ForeignScriptClassifier`), chữ nhạt = cách còn lại. Chip không phụ thuộc công tắc "Phiên âm tiếng Anh" / "Phiên âm tiếng Nhật" của trình đọc (1.3.973) — đây là gợi ý để chọn tay.
- **Nạp ngoài main thread** (`TTSPhoneticSuggestionLoadModifier`, `.phoneticSuggestions(for:mode:into:)` gắn lên `Form`): đường EN gọi `EspeakPhonemizer` (khoá chung với NghiTTS) trong `Task.detached` như `AddWordSheet`; lượt đầu chạy ngay, gõ tiếp thì chờ 0,3 s, `.task(id:)` tự huỷ lượt cũ. Là modifier vì section rỗng không vẽ gì nên không gắn `.task` lên chính nó được.
- `AddWordSheet` (sheet Thêm từ) không đổi. `.claude/rules/tts.md` ghi dãy chip dùng chung.
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift` (3 file mới 56 / 86 / 161 dòng, `TTSReplacementManagerView.swift` 376 / 400); 9 file Swift đã sửa / thêm qua `swiftc -frontend -parse` (chỉ cú pháp). **Không build tại chỗ (Windows), chưa chạy trên máy** — chưa xem dãy chip trên iPhone, chưa nghe thử chuỗi phiên âm do chip điền.

## [1.3.973] - 2026-11-17

### feat: Công tắc Phiên âm tiếng Nhật có ở mọi trình đọc TTS, lưu riêng từng trình đọc

Anh Bửu: "sửa lại nút phiên âm tiếng nhật cho tất cả tts, config lưu riêng mỗi loại tts". Trước đó mỗi trình đọc một kiểu: NghiTTS gộp chung "Phiên âm tiếng Anh/Nhật" (nằm sâu trong Cấu hình tiền xử lý), VieNeu có "Đọc tên Nhật theo âm tiết" (công tắc "Tự động phiên âm tiếng Nhật" đã bỏ ở 1.3.899), còn Siri / Google / tiện ích không có gì.

- **Một công tắc "Phiên âm tiếng Nhật" ở Cài đặt TTS › Quản lý riêng của trình đọc**, hiện với **mọi** trình đọc (`TTSJapaneseTransliterationRow`, `Views/Settings/TTS/`): Siri (thay dòng "không cần cấu hình"), NghiTTS, Google, từng tiện ích TTS; VieNeu qua `VieNeuReaderManagementRows` (thay hàng "Đọc tên Nhật theo âm tiết") nên màn Giọng dự phòng cũng có; mục NghiTTS của màn Giọng dự phòng và "Tiền xử lý text" của Cấu hình NghiTTS có cùng hàng. Tiêu đề mục có nút "?" giải thích công tắc làm gì ở trình đọc đang chọn. Đổi trình đọc ⇒ công tắc hiện đúng giá trị của trình đọc đó.
- **Lưu riêng từng trình đọc** (`TTSJapaneseTransliterationSettings`, khoá `ttsJapaneseTransliterationEnabled.<tool>`: `system`, `nghitts`, `vieneu`, `google`, `packageId` của tiện ích — "mỗi loại TTS" hiểu là **trình đọc**, không phải từng giọng; VieNeu Nano và Turbo chung một khoá như các cờ VieNeu khác). Giữ giá trị đang có: NghiTTS lấy từ `preprocessorTransliterationEnabled`, VieNeu lấy từ `vieneuJapaneseNameSyllablesEnabled`, chép sang khoá mới ở lần đọc đầu (khoá cũ không xoá); Siri / Google / tiện ích **mặc định tắt** — trước giờ không phiên âm, cách đọc không tự đổi.
- **Mỗi đường tổng hợp đọc đúng khoá của mình:**
  - NghiTTS: `PreprocessorRuntimeConfig.japaneseTransliterationEnabled` điều khiển bước kana → romaji và nhánh romaji của `TextPreprocessor.transliterateToken`; công tắc cũ đổi tên thành **"Phiên âm tiếng Anh"** và chỉ còn điều khiển nhánh tiếng Anh (tắt tiếng Nhật thì từ romaji đi theo luật tiếng Anh nếu tiếng Anh bật; tắt tiếng Anh thì chỉ từ romaji được đổi). Khoá đệm phiên âm mang cả hai cờ.
  - VieNeu: `VieNeuJapaneseNameReader.isEnabled` đọc khoá mới ⇒ tiền xử lý Nano / Turbo, bộ phân loại đọc lai và dấu vân tay giọng dự phòng đi theo, không đổi cách đọc.
  - Siri / Google / tiện ích: `TTSJapaneseTextTransliterator` (mới) đổi chữ ở **tầng service** (`SiriTTSService.speak`, `GoogleTTSService.synthesize` + `synthesizeBatch`, `ExtTTSService.synthesizeData` — tra `packageId` theo `localPath`) ⇒ đoạn đang đọc, nạp trước, đệm chương kế, request gộp của Google và "Nghe" đoạn bôi đen cùng một đường; giọng dự phòng nhận chữ gốc và áp cài đặt của chính nó. Cùng luật với nhánh tiếng Nhật của NghiTTS (`ForeignScriptClassifier` sau cổng `VietnameseTokenGate`): "Sakura" → "Xa cư ra", token gạch nối xét từng phần, dãy kana → romaji → âm tiết Việt, chữ Hán giữ nguyên.
- `TTSSettingsSnapshot` thêm `japaneseTransliteration` của trình đọc chính, dấu vân tay giọng dự phòng NghiTTS thêm cờ ⇒ gạt công tắc rồi đóng Cài đặt là dựng lại đoạn, bỏ tiếng đã nạp trước theo cài đặt cũ.
- `.claude/rules/tts.md`, `.claude/rules/tts-vieneu.md` ghi luật mới.
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift` (`TextPreprocessor.swift` 1117 / 1121 dòng, `TTSSettingsView.swift` 327); 15 file Swift đã sửa / thêm qua `swiftc -frontend -parse` (chỉ cú pháp). **Không build tại chỗ (Windows), chưa chạy trên máy** — chưa nghe thử cách Siri / Google / tiện ích đọc chữ đã phiên âm, chưa xem công tắc trên màn thật.

## [1.3.972] - 2026-11-17

### fix: VieNeu Turbo không tự tắt AMX vì app sập chỗ khác, hết lỗi "Chưa nạp model Turbo" khi model vừa bị nhả, xoá dữ liệu và thử giọng trả lại đúng engine

Rà soát phân hệ VieNeu Turbo (code review hai lượt); anh Bửu chọn sửa các mục **đã xác nhận**. Bảy lỗi:

- **Bản vá `capi_abort_file` thay handler `std::terminate` của cả tiến trình rồi `abort()` thẳng.** Sau lần dựng session Turbo đầu tiên, mọi exception chưa bắt của app (NSException của UIKit / SwiftData… không liên quan audio.cpp) bị ghi vào `audiocpp-abort.txt`; lần mở sau `VieNeuTurboCrashGuard.recoverIfNeeded` coi là audio.cpp sập ⇒ tự tắt AMX tới bản build sau (RTF 0,25 → 0,40), và handler cũ (của ggml, rồi libobjc / Foundation — nơi ghi lý do "Terminating app due to uncaught exception" vào `.ips`) không còn được gọi. Nay: dòng của handler mang tiền tố `terminate: `, ghi xong **gọi lại handler đã cài trước** (cài một lần, có chốt chống gọi vòng); `recoverIfNeeded` chỉ tắt AMX khi có dấu "đang thử AMX" hoặc có câu báo của chính ggml — file chỉ có dòng `terminate: ` (và ba dạng chữ của bản vá cũ) thì chỉ ghi `❌` vào log.
- **`release()` chen giữa `prepare` và `synthesize` của runtime ⇒ "Chưa nạp model Turbo".** `VieNeuTurboTTSService.executeInternalSynthesis` gọi `runtime.prepare`, `await` phiên âm rồi mới `runtime.synthesize` — hai block rời trên hàng đợi; một `release()` xếp hàng lúc GGUF đang nạp (đổi sang giọng Nano khác rồi bấm ▶ thử giọng Turbo: lượt nạp sẵn Nano gọi `releaseForNano`; lượt `prepare` đầu của engine đọc lai; xoá dữ liệu Turbo) luôn chạy trước `synthesize`. `VieNeuTurboRuntime.synthesize` nhận thêm `modelURL` / `threads` và tự `prepareLocked` trong cùng block; model + session còn nguyên thì chỉ so vài biến.
- **`freeAll()` đặt lại `codecAMXVerified`** ⇒ dấu canh sập AMX mở lại sau mỗi lần nạp lại model (đổi Nano ↔ Turbo, tạo giọng lúc runtime nguội, xoá dữ liệu), không phải "lượt đầu mỗi lần mở app" như doc; app bị giết trong cửa sổ đó vì lý do khác cũng bị tính là sập do AMX. Bỏ dòng đặt lại.
- **Xoá dữ liệu Turbo không nạp lại tham số trình đọc.** Đang chọn giọng Turbo mà xoá dữ liệu Turbo: model hiệu lực lùi về Nano nhưng `selectedVoice` còn là id giọng Turbo ⇒ hàng giọng hiện "minh_quan_pro · Nano", Nano đọc giọng mặc định thay vì giọng Nano dùng gần nhất, tới khi mở lại app. Hàm của đường tải xong chuyển thành `TTSManager.reapplyVieNeuReaderIfModelChanged(from:reason:)` (`TTSManager+VieNeuVoice`), `deleteTurbo` gọi chung; `stopReaderIfUsing` dừng cả trình đọc đang **đọc lai** (model kia cũng đang được dùng theo đoạn; xoá một giọng Turbo ⇒ xét cả giọng Turbo của cặp); sau khi xoá nhả runtime + bộ phiên âm Turbo lần nữa.
- **`deleteNano` chặn main.** Enum `@MainActor` gọi thẳng `releaseEngineRuntime()` (chờ khoá engine; một chunk Nano đang tổng hợp giữ khoá vài giây, `stop()` không cắt được) ⇒ UI đứng. Nay `await VieNeuTurboTTSService.releaseNanoEngineIfLoaded(reason:)` (chờ trên hàng đợi GCD; thêm tham số `reason` cho dòng log), rồi kiểm lại "đang tải" vì vừa nhường main.
- **Thử giọng lúc trình đọc không phải VieNeu để model nằm lại RAM tới khi tắt app** (Turbo ~200 MB, Nano ~280 MB): `finishSession` chỉ dọn khi `tool == "vieneu"`, mà ngoài `prepare` của VieNeu không ai nhả. Luật gom về `TTSManager.restoreVieNeuEngines(afterUsing:reason:)`: trình đọc là VieNeu ⇒ như cũ (nạp lại engine của trình đọc); không phải ⇒ nhả engine VieNeu, trừ engine đang là giọng dự phòng của trình đọc online. `VieNeuVoiceCopyRunner` (đọc mẫu nhân bản) dùng chung.
- **Engine đọc lai nhớ `preparedBase` cũ.** Rời đọc lai (chọn giọng không cặp) rồi quay lại cùng model chính: `beginPrepare` thấy trùng nên không nhả model phụ, service chính cũng không nhả vì đang đọc lai ⇒ Nano (ORT + Core ML) và Turbo cùng nằm RAM dù máy mát. `prepare` của service Nano / Turbo thường, khi trình đọc không đọc lai, gọi `VieNeuHybridTTSService.readerLeftHybrid()` để quên giá trị đó.

Chưa sửa (mức "có khả năng", chờ anh Bửu quyết): `isReaderUsingTurbo` bỏ sót đọc lai; `sea_g2p.bin` tải về không kiểm dung lượng; `ensureVoice` xoá nhầm mục của lượt tải mới. `.claude/rules/tts-vieneu.md` ghi các điểm mới.

- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`; 10 file Swift đã sửa qua `swiftc -frontend -parse` (chỉ cú pháp); bản vá Python áp thử lên cây nguồn giả có đủ mốc, chạy lại lần hai tự bỏ qua. **Không build tại chỗ (Windows), chưa chạy trên máy**; đoạn C++ của bản vá chưa qua trình biên dịch nào (máy không có thư viện chuẩn C++ đủ mới) — job `audiocpp-ios.yml` sẽ dựng lại framework vì bản vá đổi.

## [1.3.971] - 2026-11-17

### feat: Thêm provider AI ChatGPT Web (không cần key, đăng nhập hay không đều chạy)

Anh Bửu: "thêm provider chế độ AI chatgpt web"; "chatgpt web có thể sử dụng mà không cần đăng nhập, tận dụng cái này để đỡ đăng nhập, hơn nữa tôi phát hiện không đăng nhập sẽ hiển thị ra nhanh hơn"; "tìm xem có hạn chế số câu hỏi hay gì không"; "phục vụ cho cả đăng nhập lẫn không đăng nhập luôn".

- **Provider mới** `apiFormat = "chatgptWeb"` (`AIProviderProfile.defaultChatGPTWeb`, mẫu "ChatGPT Web (không cần key)" trong sheet thêm provider): không key, không chọn model, không temperature. Chưa đăng nhập ChatGPT trong trình duyệt của app ⇒ chạy trang **ẩn danh**; đã đăng nhập ⇒ chạy bằng **tài khoản đó**. Dùng cho chat trong Reader, quét tên riêng (một chương / nhiều chương) và "Kiểm tra kết nối".
- **Cách chạy** (`Sources/Services/AI/ChatGPTWeb/`, 12 file): mở `chatgpt.com/?temporary-chat=true` trong WKWebView ẩn (`ChatGPTWebSessionController`, cùng kho cookie + UA với trình duyệt bypass), gán câu hỏi vào ô nhập, gửi form, đọc DOM theo nhịp (`ChatGPTWebClient+Turn`). Mọi selector + JS của **cả hai kiểu trang** ở `ChatGPTWebPageContract`; hàng đợi tuần tự `ChatGPTWebTurnQueue`; ngân sách prompt 20.000 ký tự `ChatGPTWebPromptBudget`.
- **Thử thật trước khi viết** (2026-11-17):
  - *Trang ẩn danh* (Chromium giả lập mobile, 5 tin): trang server-render riêng (`/unauth-mweb`), ô nhập `textarea[data-mobile-composer-prompt]`, tin `li[data-message-role]` + `data-message-complete`. Tin ngắn xong sau ~2–5 s; prompt 12.166 ký tự chữ Hán gửi được và trả đúng `Tên=Nghĩa`; hỏi tiếp trong cùng trang nhớ ngữ cảnh.
  - *Trang đã đăng nhập* (Chrome máy tính, tài khoản Free, 3 tin chat tạm): app React khác hẳn — ô nhập là vùng soạn thảo `contenteditable`, nút gửi chỉ có khi ô có chữ, mỗi lượt là `[data-talvt-turn-state]` `in_progress` → `complete`, chữ ở `[data-dil-response]`, khối code không phải `<pre>`. Gán chữ bằng sự kiện `paste` tự dựng, gửi bằng `requestSubmit`, hỏi tiếp trong trang đều chạy.
  - Bốn đoạn JS của bản chính thức (đọc trang, gán chữ, gán chữ dự phòng, gửi) được trích từ file Swift, kiểm cú pháp bằng `node --check`; đoạn đọc trang đã chạy nguyên văn trên trang đã đăng nhập thật (đúng trạng thái, khối code, bảng). Trên trang ẩn danh mới chạy bản trước khi gộp (cùng nhánh logic).
- **Ba bẫy thấy khi thử**: (1) trang ẩn danh: nút gửi chỉ bật theo `requestAnimationFrame` — trang không được vẽ thì nút không bao giờ bật ⇒ gửi bằng `form.requestSubmit(nút)`; (2) xuống dòng mềm trong câu trả lời là text node `"\n"` (`white-space: pre-line`) ⇒ bộ đọc chữ không gộp `\n`; (3) trang đã đăng nhập: lượt vừa gửi mang `complete` trong tích tắc khi chưa có phần trợ lý ⇒ chỉ tin `complete` khi lượt đã có vai `assistant`.
- **Chat**: cuộc chat ẩn danh / chat tạm không khôi phục được sau khi nạp lại trang. Nên lượt chat thành công giữ trang 180 s; lượt kế của đúng phiên chat app hỏi tiếp ngay trong trang (chỉ gửi tin mới, đổi chương thì kèm "Cập nhật ngữ cảnh"), không thì mở cuộc chat mới với đủ ngữ cảnh + cửa sổ 6 tin gần nhất. Không nén ngữ cảnh.
- **Đã đăng nhập ⇒ luôn chat tạm**: không lượt nào vào lịch sử ChatGPT của người dùng (quét cả truyện là hàng chục cuộc chat).
- **Quét tên riêng**: mỗi lượt một cuộc chat mới, ~10.000 chữ/lượt (chương dài được tách như Chế độ AI), nghỉ 5 s (giãn theo nhiệt), tạm dừng khi app ở nền.
- **Giới hạn số câu hỏi** (tìm theo yêu cầu) — ẩn danh: (a) mềm — mã của trang có `noAuthSoftRateLimit.triggerMessageCount = 5`, đếm ở `localStorage`; đã thấy thật: sau tin thứ 5 trang mở hộp mời đăng nhập. (b) cứng — máy chủ có cổng `rate_limited` / `force_login` / `forbidden` (kèm `retryAfter`), con số OpenAI không công bố. Đã đăng nhập: hạn mức theo tài khoản, chưa gặp nên chưa biết trang hiện gì. App: gặp cổng ⇒ dừng, báo rõ, `rate_limited` đặt hạn chờ toàn cục; **không** tự đóng hộp mời đăng nhập, **không** xoá cookie / `localStorage` hay đổi danh tính để lách.
- **UI**: `ChatGPTWebInfoRow` (thay ô Base URL / API key): dòng trạng thái tài khoản, nút "Đăng nhập ChatGPT" / "Mở ChatGPT" (mở trong trình duyệt bypass), nút "Đăng xuất" (`ChatGPTWebAccount` — xoá cookie `*.chatgpt.com` / `*.openai.com`, trình duyệt của app cũng mất đăng nhập ChatGPT). Nút "Mở ChatGPT" (`ChatGPTWebOpenButton`) dưới tin lỗi cần người dùng tự xử lý trên trang; `AIWebRecoveryButtons` gộp nút này với "Mở Google để xác minh" (`ReaderAIFullScreenView.swift` giữ 399 dòng). Ô "Định dạng API" (Cấu hình AI, sheet thêm provider) đổi từ thanh phân đoạn sang **menu xổ** vì 5 định dạng không vừa một hàng. `AIProviderProfile.hasFixedWebModel` gom điều kiện ẩn khối model / temperature của Chế độ AI và ChatGPT Web.
- `rules.md`: mục "ChatGPT Web provider invariants (1.3.971)".
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. **Không build tại chỗ (Windows), chưa chạy trên máy** — chưa kiểm: UA iPhone có nhận đúng trang ẩn danh mobile không; **trang đã đăng nhập với UA điện thoại** (mới thử Chrome máy tính); `requestSubmit` / sự kiện `paste` tự dựng trong WKWebView iOS; hộp mời đăng nhập có chặn gửi không; chữ / ngưỡng của cổng `rate_limited`; tên cookie phiên (dòng trạng thái ghi "đoán theo cookie" tới khi có lượt thật); banner cookie. Log chẩn đoán: `🤖 [ChatGPTWeb]`, ghi kiểu trang mỗi lượt.

## [1.3.970] - 2026-11-17

### perf: Lọc rác chương bỏ qua quy tắc chắc chắn không khớp, nhớ kết quả theo chuỗi vào

Log build 1293 (1.3.968, ~28 phút): `JunkFilterManager.filterRawContent` chạy **575 lần**, trung vị 132 ms, p90 176 ms, tối đa 393 ms mỗi chương, tổng **~78 s CPU** — bộ 907 quy tắc, mỗi quy tắc một lượt `replaceOccurrences` / `replaceMatches` trên cả chương dù hầu hết không khớp gì.

- **Ai gọi, luồng nào**: chỉ qua `ChapterTextNormalizer.normalize` — actor `ChapterContentRepository` / `ChapterPersistenceStore` (dựng `ChapterDocument`, đọc / ghi file chương), `ReaderViewModel.performChapterTranslationOffMainActor` (`nonisolated async`), actor `TTSBackgroundProcessor` + `TTSExtensionTranslationPreparer`, quét tên riêng AI (`AINameScanTextLoader`, 4 việc song song), `AIBookDataInspector`. **Không lượt nào chạy trên main** (Swift 5, hàm `nonisolated async` chạy trên executor chung). Các dòng `🐢 [MainHang]` gần đó (vd 11:36:16 `Main kẹt 769 ms`, ~1 s sau hai lần lọc 393 / 296 ms lúc TTS chuẩn bị chương kế — đã xong trước khi main kẹt) trùng lúc Chế độ AI xong lượt trên `WKWebView` và JS tiện ích chạy dồn; lọc rác chỉ góp phần gián tiếp: đốt CPU nền (A13 chỉ 2 lõi hiệu năng) và đẩy nhiệt Ấm → Nóng.
- **Gọi lặp cùng chương**: **538/575 lần là quét tên riêng AI**, mỗi lượt quét chuẩn hoá cả loạt chương lúc bắt đầu ("chuẩn hoá ~3 s") và **chạy lại đọc lại đúng loạt đó**: 95 chương ×4 lượt (11:38–11:43), ~80 chương ×2 (11:32, 11:34) ⇒ ~2/3 là việc lặp (~48 s CPU). Reader + TTS: một chương lấy từ tiện ích lọc chữ thô một lần rồi lọc **cùng một chuỗi** 2–3 lần (`upsert` lưu file, Reader `normalizeChapter`, TTS `processChapter`); mở chương từ file cũng lọc hai lần cùng chuỗi.
- **Bỏ quy tắc chắc chắn không khớp** (`JunkFilterTextProbe`, mới): mỗi chương dựng bản đồ đơn vị UTF-16 của chữ gốc ∪ NFD và cặp đơn vị liền nhau trong NFD (băm 2^18 bit). Quy tắc chuỗi thường (options `[]` = khớp theo tương đương chính tắc) cần mọi đơn vị của NFD(mẫu) và mọi cặp **starter** liền nhau của NFD(mẫu) — sắp xếp chính tắc không chen dấu vào giữa hai starter; regex cần các ký tự literal bắt buộc ở tầng ngoài (`JunkFilterRegexLiterals`, mới, bảo thủ: có `|` ngoài cùng, cờ `(?i)`…, `\Q`, `\p{…}`, `\x…`, backref… ⇒ luôn chạy). Thiếu ⇒ bỏ qua, vì lượt thay vốn ra 0 chỗ. Một quy tắc thay được ≥ 1 chỗ thì dựng lại bản đồ trước quy tắc kế ⇒ **giữ nguyên thứ tự và kết quả**. Điều kiện biên dịch sẵn cùng regex (`JunkFilterCompiledRule`, mới) khi bộ quy tắc đổi, kể cả bộ đã chuyển phồn → giản.
- **Cache kết quả theo đúng chuỗi vào** (`NSCache`, 256 mục / 8 MB, hai bộ thô / đã chuyển phồn → giản): lọc là hàm thuần của (chuỗi, bộ quy tắc) ⇒ trả lại y hệt; đổi quy tắc ⇒ tăng `rulesGeneration` + xoá; kết quả tính bằng bộ cũ không được ghi vào. Chuỗi > 200 000 đơn vị không giữ.
- Dòng log đổi: `[ReaderPerf] JunkFilter rules=907 ran=… fired=… chars=… ms=…` (`ran` = số quy tắc thật sự chạy, `fired` = số quy tắc thay được) hoặc `… cache=hit …` — log sau sẽ cho tỉ lệ bỏ qua thật.
- **Ước lượng** (chưa đo trên máy, không biết tỉ lệ regex trong 907 quy tắc của anh Bửu): số lần lọc thật trong phiên như log 575 → ~200 (quét lại + Reader/TTS trùng chuỗi trúng cache); mỗi lần ~0,15 ms × số quy tắc còn chạy + ~0,3 ms dựng bản đồ / xét quy tắc — chữ Trung với mẫu Trung / Việt bỏ được phần lớn quy tắc ⇒ cỡ 5–15 ms thay vì ~130 ms; regex không rút được literal vẫn chạy như cũ. Chữ Việt có dấu được lợi ít hơn (đơn vị nào cũng có mặt, chỉ cặp starter lọc được).
- Kiểm: mô phỏng Python — bộ rút literal regex đối chiếu `re` trên 800 000 phép thử ngẫu nhiên, 0 lần bỏ sót; điều kiện chuỗi thường đối chiếu mô hình khớp tương đương chính tắc (cả khớp lệch ranh giới ký tự, chữ Việt dựng sẵn / tổ hợp, chữ Hán tương thích, Hangul, Kelvin / Ohm, ngoài BMP) trên 120 000 cặp, 0 lần bỏ sót. `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.969] - 2026-11-17

### fix: Chạm truyện AI chạy trước ở hub mở được màn AI: màn AI tự ghi ngữ cảnh, không còn im lặng bỏ qua

Anh Bửu báo: chạy AI từ 2 truyện trở lên, ở hub chạm vào truyện chạy trước thì không mở được. Log build 1293 (1.3.968): 4 lần `❌ Không có ngữ cảnh để mở màn AI của truyện D63FA7C7…` (11:41–11:44) trong lúc 4 lượt quét tên riêng của 4 truyện xen nhau, có truyện dừng rồi chạy lại.

- **Nguyên nhân**: ngữ cảnh mở màn AI (`AIRuntimeCoordinator.contexts`) chỉ được ghi khi bấm nút AI trong Reader (`ReaderView.openAIFromReader`). `pruneContexts` (chạy mỗi khi một lượt kết thúc) bỏ ngữ cảnh của truyện không còn lượt và không phải "mở AI gần nhất". Màn AI mở lại từ hub / Reader (`reopenReaderAI`) không ghi ngữ cảnh ⇒ dừng rồi chạy lại quét trong màn đó là ngữ cảnh bị dọn lúc lượt cũ kết thúc, lượt mới vẫn chạy ⇒ hub không mở được truyện đó nữa.
- **Màn AI tự ghi ngữ cảnh** ở mọi lối mở: `onAppear` gọi `AIRuntimeCoordinator.screenDidAppear(runtimeContext)` (ngữ cảnh dựng từ chính tham số của màn — `ReaderAIFullScreenView+Context`, file mới) thay cho chỉ đặt `presentedAIBookId`.
- **`pruneContexts` giữ cả truyện đang mở màn AI** (`presentedAIBookId`).
- **Lưới an toàn**: vẫn thiếu ngữ cảnh mà truyện còn trong `runs` ⇒ mở màn AI với ngữ cảnh tối thiểu (tên truyện, chương đầu, không nội dung chương) + `❌`, thay vì không mở.

Đọc code còn thấy `presentFullScreen` có ba lối ra khác không làm gì mà cũng không ghi log, sửa luôn:

- **Nhờ Reader mở lại mà Reader không mở** (`reopenReaderAI`): đường này chỉ đi khi `activeReaderBookId` trùng truyện được chạm. Cờ đó có thể còn trỏ truyện của Reader đã rời đi (Reader rời màn lúc cờ cover AI còn bật thì không xoá), Reader có thể đang bị màn khác che, hoặc cờ cover của Reader đã bật sẵn nên gán lại không có tác dụng ⇒ không ai mở. Nay chờ 0,8 s, màn AI chưa lên (`presentedAIBookId` vẫn `nil`) thì mở bằng UIKit `.overFullScreen` như đường của truyện khác.
- **Cờ `presentedAIBookId` kẹt**: màn AI mở bằng UIKit đã bị gỡ khỏi cây (`presentingViewController == nil`) mà cờ còn ⇒ dọn rồi mở tiếp; màn AI khác thật sự đang mở ⇒ từ chối nhưng ghi `❌`.
- **Tìm màn trên cùng**: ưu tiên scene giao diện chính (`AppMainWindowScene`, scene PiP cũng có thể đang hoạt động), bỏ cửa sổ lớp phủ / cửa sổ ẩn (khuôn `MediaDiscPlacement.mainWindow`); không tìm được ⇒ `❌`. Màn trên cùng đang mở / đóng dở ⇒ thử lại mỗi 0,3 s, tối đa 10 lần (trước đó thử lại vô hạn qua `presentFullScreen`).
- Mọi lối từ chối ghi `❌ 🤖 [AI]` (luôn ghi dù tắt log) — lần sau còn lỗi thì log chỉ ra đúng lối nào.
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.968] - 2026-11-17

### feat: Sheet quét tên riêng nhớ prompt tự nhập: Gần đây theo truyện, ghim dùng chung

Anh Bửu: "ghi nhớ prompt tự nhập ở AI" — ô "Tự nhập prompt" của sheet "Quét tên riêng theo phạm vi" trước đây chỉ dùng cho một lần quét, mở lại sheet là mất. Plan + mockup phương án B đã duyệt: `Docs/Plans/2026-11-17-plan-name-scan-saved-prompts.md`.

- **Kho mới `AINameScanPromptStore`** (`Services/AI/`, model `AINameScanSavedPrompt`): bấm "Bắt đầu quét" với nguồn Tự nhập ⇒ chữ trong ô "Prompt cho lần này" (cắt khoảng trắng hai đầu, không bao giờ kèm nội dung truyện) vào **Gần đây của truyện** — tối đa 10, dùng gần nhất lên đầu, trùng y nội dung thì đưa lên đầu chứ không thêm bản mới. Prompt trùng prompt Cài đặt hay trùng một bản ghim thì không ghi. **Đã ghim dùng chung mọi truyện** (mới ghim lên đầu, không giới hạn); Gần đây hiện ra lọc bỏ chữ trùng bản ghim. Lưu UserDefaults `aiNameScanPromptRecents` / `aiNameScanPromptPins` (chữ thường đầu ⇒ Sao lưu tự mang theo; khôi phục là ghi đè).
- **Sheet**: mục Nguồn prompt thêm dòng "Chọn prompt đã lưu…" (phụ đề "2 đã ghim · 3 gần đây"; chưa có gì thì mờ, khoá, "Chưa có prompt nào đã lưu", cùng kiểu "Chọn chương…"); lời giải thích "?" đổi theo. Sheet vẫn mở với nguồn "Dùng prompt trong Cài đặt" như cũ.
- **Trang "Prompt đã lưu"** (`ReaderAISavedPromptsView`; dòng vào là `ReaderAISavedPromptsView.EntryRow`): nhóm Đã ghim / Gần đây của truyện này, xem trước 2 dòng + "N dòng" (Gần đây thêm "14:20 hôm nay" / "Hôm qua" / "dd/MM"). Chạm ⇒ chép vào ô, chọn Tự nhập, quay về sheet. Nhấn giữ: Ghim / Bỏ ghim (về đầu Gần đây của truyện đang mở), Xoá; vuốt trái: Xoá (không hỏi lại).
- **Đổi nguồn**: `BookSourceMigrator` chép / xoá Gần đây theo truyện như các kho AI khác; `rules.md` (luật 1.3.669) ghi thêm kho này.
- Không đụng ô chat màn AI, chip hành động nhanh, prompt trong Cài đặt AI. Xoá truyện không dọn Gần đây của truyện đó (như mọi dữ liệu AI theo truyện hiện nay).
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.967] - 2026-11-17

### feat: Sheet hub có mục "Đang chạy" với thanh tiến độ của mọi tác vụ nền

Anh Bửu: "tôi muốn thấy thanh tiến độ ở sheet hub"; duyệt mockup **A · Mục "Đang chạy"** và bỏ giới hạn 3 ô ("lỡ có nhiều hơn thì sao").

- **Mục "Đang chạy"** dưới bốn dòng cố định (`FloatingHubActivitySection`, file mới): mỗi tác vụ nền có thanh tiến độ ở màn Thông báo một ô — icon, tên, chi tiết, thanh — cùng khung với dòng hub (`hubSheetPanelRow`). Dòng đầu "Đang chạy (N) · M đang chờ" (chỉ có tác vụ chờ ⇒ "M tác vụ đang chờ"). Chạm ô ⇒ trang Thông báo trong sheet (nơi có nút Huỷ, chi tiết từng tập). Không giới hạn số ô.
- **Nguồn chung** `FloatingHubActivity` (file mới): `items()` dựng ô theo thứ tự tải / xuất (hàng đợi) → nhập truyện → sao lưu / khôi phục → tải giọng → gộp VietPhrase → phiên âm lại Nghi / VieNeu; `counts()` đếm đang chạy / đang chờ (đang chờ = tác vụ tải / xuất xếp hàng + lượt tải VieNeu chờ lượt khác).
- **Chữ của tác vụ tải / xuất dùng chung** (`DownloadTask+ActivityText`: `activityTitle` / `activityDetail` / `activityFraction`) — dòng ở màn Thông báo (`StoryTaskActivityRow`) chuyển sang dùng, bỏ bản riêng.
- **Đếm thay cho một bit** (`NotificationInboxPresenceReader.Snapshot`: `runningCount` / `pendingCount`, `hasRunningTask` thành tính toán): dòng Thông báo ghi "5 đang chạy · 1 chờ · 2 chưa đọc" (bỏ vế bằng 0; trước đó "N chưa đọc" hoặc "Đang chạy tác vụ"). **Vá sót**: gộp VietPhrase và phiên âm lại trước không được tính là "đang chạy" ⇒ nút hub không nháy dù màn Thông báo có thanh chạy; nay nghe `phase` của hai việc này (rút về một bit, `removeDuplicates`).
- **Đầu sheet "N đang chạy" đếm tác vụ** (`Snapshot.runningTaskCount`: AI đang chạy + tác vụ nền + lượt kiểm tra nguồn đang chạy + video thu nhỏ), không còn đếm loại dòng. Không vào `ButtonState` ⇒ nút hub không vẽ lại theo số này.
- **Sheet cuộn khi dài**: trang nhỏ của sheet (`compactPage`) nằm trong `ScrollView` (`scrollBounceBehavior(.basedOnSize)`): nội dung cao hơn màn thì nấc `.height` bị kẹp ở mức cao nhất và phần dư cuộn; vừa màn thì không nảy.
- Hiệu năng: mục "Đang chạy" tự observe các nguồn (`DownloadManager` phát ~10 lần/giây lúc tải) nên chỉ nó vẽ lại theo nhịp tiến độ, và chỉ khi sheet mở; hub vẫn chỉ đọc số đã gộp + `removeDuplicates`.
- `.claude/rules/floating-pills.md` ghi luật mới.
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.965] - 2026-11-17

### fix: Bớt việc trên main khi tải truyện để mục lục đỡ giật, thêm log đo main thread bị kẹt

Anh Bửu báo mục lục Reader giật khi đang tải truyện; log build 1289 không có dấu vết lúc giao diện khựng (JS của tiện ích chạy ngoài main, `[ReaderEnergy]` không tăng lúc tải) nên chưa xác định chắc nguyên nhân. Đợt này bỏ hai việc thừa trên main đã thấy khi đọc code và thêm bộ đo để lần sau có số liệu.

- **Tiến độ tải không còn fetch SwiftData mỗi chương** (`DownloadManager.updateProgress`): trước đó mỗi chương một lần fetch `#Predicate` trên main + `save()` mỗi giây; mỗi lần lưu có thể đánh thức `@Query` của màn đang mở (Reader giữ `@Query` cả thư viện, Kệ nằm dưới cũng vậy). Nay chỉ ghi CSDL khi đổi trạng thái / bước đầu / bước cuối và mỗi 5 s (`progressPersistInterval`, đếm riêng từng tác vụ — `lastProgressPersistAt`); thanh tiến độ trên màn vẫn ~10 lần/giây như cũ. CSDL chỉ cần tiến độ để hiện lại sau khi app bị tắt giữa chừng.
- **Mục lục của Chi tiết gộp sự kiện "chương vừa tải" tối đa 1 lần/giây** (`BookDetailTOCView.observeChapterDownloads`): mỗi lần ghi `freshlyCachedIndices` (`@State`) là cả `body` dựng lại kèm `ForEach` hàng nghìn chương — kể cả khi Chi tiết đang nằm dưới Reader. Tải 2–3 luồng là vài chương mỗi giây. Icon "đã tải" ở đó trễ tối đa 1 giây.
- **Log đo main kẹt** (`MainThreadHangMonitor`, `Services/Diagnostics/`, khởi động ở `FreeBookApp.init`): chỉ chạy khi bật "Ghi log hệ thống"; mỗi 0,25 s gửi một khối rỗng vào main và đo độ trễ. Kẹt ≥ 500 ms ⇒ một dòng `🐢 [MainHang] Main kẹt N ms`; các lần ≥ 150 ms gộp thành dòng tổng kết mỗi 10 s. Mỗi dòng kèm bối cảnh: số tác vụ tải / xuất đang chạy, Chế độ AI đang chạy lượt (`GoogleAIModeSessionController.isTurnActive`), "mục lục Reader" / "mục lục Chi tiết" đang mở (`noteScreen`), mức nhiệt. Mục lục Reader thêm dòng `📑 [ReaderTOC] Mở / Đóng mục lục`.
- Sheet hub đếm tác vụ: anh Bửu chưa duyệt mockup ⇒ chưa làm.
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.964] - 2026-11-17

### fix: Đĩa nghe không ẩn khi có hộp thoại xác nhận / huỷ, ở lại như nằm dưới hộp

Anh Bửu báo: có thông báo dạng chọn xác nhận / huỷ thì đĩa nghe bị ẩn dù hub không ẩn — "việc ẩn là không cần, chỉ cần để nó nằm dưới các thông báo đó".

- Cửa sổ đĩa (`alert − 1.75`) nằm trên cửa sổ chính, còn hộp thoại SwiftUI (`.alert`, `.confirmationDialog` ⇒ `UIAlertController`) trình bày **trong** cửa sổ chính ⇒ không vẽ đĩa dưới hộp thật được. Thay vì ẩn (`MediaDiscPlacement` luật 1), đĩa giả "nằm dưới":
  - **Né khung hộp**: khung `alert.view` là vật cản (cùng luật "tạm đẩy" của neo lấn vùng), đĩa trượt lên trên nó; không ghi đè chỗ đã nhớ, hộp đóng thì về chỗ cũ. Đẩy tới đỉnh vùng đứng mà vẫn đè khung (bảng chọn cao) ⇒ ẩn như cũ để không che nút của hộp.
  - **Không nhận chạm / kéo** (`isDiscInteractive` = đang hiện và không nằm dưới hộp; đang kéo thì thôi kéo, không lưu), `presentQuickControls` từ chối, VoiceOver ẩn — hộp thoại là modal.
  - **Phủ tối** đúng hình viên một lớp đen 20% (giao diện tối 40%) như lớp mờ của hộp (`MediaDiscFaceButton`, cờ `MediaDiscWindowManager.isDiscUnderModal`); phủ chứ không hạ alpha vì alpha < 1 tắt nhoè kính. Độ tối là ước lượng, chỉnh theo máy nếu lệch.
  - Bật ngay cả khi hộp còn đang trượt lên (đặt trước nhánh chuyển cảnh của `updateDisc`).
- Bảng chia sẻ vẫn ẩn đĩa như trước.
- `.claude/rules/floating-pills.md` ghi luật mới.
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.963] - 2026-11-17

### fix: Google Chế độ AI bớt nóng máy: trang ẩn về trắng sau mỗi lượt, quét đọc trang chậm lại, máy nóng thì giãn nhịp quét

Anh Bửu báo chức năng Google AI dễ làm nóng máy. Chế độ AI chạy trang `google.com/search?udm=50` trong WKWebView ẩn; cửa sổ ẩn (`GeminiWebHiddenWindowHost`) cố ý giữ WebView ở trạng thái "hiển thị" để WebKit không tạm dừng tiến trình web (bài học 1.3.507) ⇒ trang Google chạy và vẽ như trang đang mở. Phần việc này nằm trong tiến trình web nên % CPU của app ở màn Theo dõi nhiệt không thấy.

- **Trang ẩn về trắng sau lượt** (`GoogleAIModeSessionController.schedulePark`): lượt xong 3 s mà không có lượt mới ⇒ `loadHTMLString("")` (cùng cách `abort` đã làm). Trước đó trang Google của lượt cuối nằm nguyên tới 10 phút (hạn giải phóng WebView) với JS, hẹn giờ, hoạt ảnh và con trỏ ô nhập vẫn chạy. Lượt nào cũng điều hướng lại (lượt mới ⇒ URL câu hỏi, nối tiếp ⇒ URL khôi phục `mstk`) nên không mất gì; giữ WebView + tiến trình web để lượt sau không phải dựng lại. Chờ 3 s để request cuối của trang (lưu cuộc chat, xoay cookie) xong; `beginTurn` huỷ lượt chờ.
- **Lượt không phát chữ đọc trang mỗi 1 s** (`readAnswer`, quét tên riêng + "Kiểm tra kết nối"; chat vẫn 0,3 s). Mỗi nhịp đọc gọi `innerText` của cả trang và từng lượt ⇒ WebKit tính lại style + layout. Luật xong (đứng yên 2 s + "sẵn sàng", hoặc đứng yên 8 s) đo bằng giờ thật nên giữ nguyên; nhịp đầu chạy ngay sau commit nên vẫn bắt được trạng thái "chưa sẵn sàng".
- **Máy nóng thì giãn nhịp quét** (`GoogleAIModeTurnQueue.thermalScanGap(_:)`): Ấm ⇒ nghỉ 10 s, Nóng ⇒ 20 s, Rất nóng ⇒ 60 s giữa hai lượt quét (bình thường 5 s); log `🌡️ [AIMode]` chỉ khi mức nhiệt đổi. Mỗi lượt quét là một lần nạp trang Google đầy đủ; quét cả truyện là hàng chục lượt liền. Chat không bị giãn.
- **Bằng chứng từ log build 1289** (anh Bửu gửi sau khi bật log; iPhone 11, TTS Google chỉ bận ~5%, Reader bình thường): 4 lượt quét tên riêng bằng Chế độ AI (89 / 49 / 12 / 64 lượt, ~4 s mỗi lượt, ~9 s một vòng với nghỉ 5 s). Lần nào cũng Mát → Ấm sau ~2 phút quét, → Nóng sau ~5 phút; ngừng quét thì 2–4 phút sau hạ về Ấm (08:51–08:57, 09:00–09:04, 09:15–09:17, 09:26–09:29). Vì vậy giãn nhịp từ mức Ấm chứ không chờ tới Nóng.
- `rules.md` (mục Chế độ AI, hàng đợi) ghi ba luật trên. Đẩy entry 1.3.932 sang `CHANGELOG.archive.md`.
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.962] - 2026-11-17

### fix: Giọng dự phòng nạp sẵn khi TTS online hụt lượt đầu, quay lại online thì bỏ lượt dự phòng chưa xong

Log build 1288 (bản 1.3.961) do anh Bửu gửi; anh Bửu duyệt "Sửa cả hai". Luật thử lại / chuyển / quay lại của 1.3.960 chạy đúng, còn hai chỗ chậm:

- **Nạp sẵn giọng dự phòng khi online có dấu hiệu trục trặc** (`TTSManager.prewarmOnlineFallback`, gọi từ `RemoteTTSAttemptPolicy.run` khi một lượt hụt mà còn lượt thử; mỗi phiên một lần). Trong log, lượt nạp trước của đoạn 56 hụt lần đầu ("Could not connect to the server") 7,4 s trước khi phải chuyển, nhưng VieNeu chỉ được nạp lúc chuyển ⇒ đoạn dự phòng đầu tiên tổng hợp nguội 1,9 s (RTF 0,31, các đoạn sau 0,12), khoảng lặng 2,4 s. Nay engine dự phòng (`prepare` + chạy nháp Core ML) được nạp ngay ở lượt hụt đầu. Không nạp sẵn lúc bắt đầu đọc: VieNeu (~280 MB) chỉ nên chiếm RAM khi online đã trục trặc.
- **Quay lại online thì bỏ lượt nạp trước dự phòng chưa xong** (`returnToOnline`): huỷ các lượt đó (lượt tổng hợp tự huỷ khi không còn ai chờ) rồi nạp lại cửa sổ bằng online; đoạn dự phòng đã nạp xong vẫn phát nốt. Trong log, lượt dự phòng của đoạn 66 bắt đầu 41 ms trước khi online chạy lại, chạy nốt rồi vẫn được phát bằng giọng dự phòng, trong khi online chỉ mất 0,3–0,7 s. Log dòng quay lại ghi số lượt bỏ.
- `.claude/rules/tts.md` ghi hai luật trên.
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.961] - 2026-11-16

### refactor: Cài đặt VieNeu dùng chung một bản cho Cài đặt TTS và Giọng dự phòng, chạy nháp Core ML chờ tín hiệu thay vì hỏi khoá mỗi 10 ms

Nhóm E của lượt rà soát chức năng nghe truyện (anh Bửu: "Làm E rồi push").

- **Một bản cài đặt VieNeu cho hai màn** (`VieNeuReaderManagementRows`, `VieNeuSynthesisSpeedRow` ở `Views/Settings/TTS/`): lối vào Cài đặt VieNeu TTS, công tắc từ điển phiên âm / đọc tên Nhật theo âm tiết, Picker "Đọc chậm đoạn có tên (Nano)", từ điển tiếng Nhật (lối vào hoặc cảnh báo + nút tải) và hàng Tốc độ tổng hợp. Trước đó màn Giọng dự phòng chép riêng một bản ⇒ thêm công tắc mới là phải nhớ thêm cả hai nơi. Khác biệt giữ nguyên qua tham số: màn dự phòng mở Cài đặt VieNeu TTS ở chế độ chỉ lưu lựa chọn giọng; Cài đặt TTS bỏ phần đệm đã tổng hợp khi đổi tốc độ tổng hợp (`onSaved`). Nút "Đặt lại" của Cài đặt TTS chỉ còn đặt giá trị — hàng tự lưu + bỏ phần đệm khi giá trị đổi.
- **Chạy nháp Core ML chờ tín hiệu** (`VieNeuTTSEngine.withSynthesisLock`): `readerWaitLock` thành `NSCondition`, lượt đọc nhả khoá qua `unlockForReader()` thì đánh thức luồng chạy nháp; bên giữ khoá khác không báo nên chờ có hạn 0,1 s. Trước đó luồng chạy nháp hỏi lại mỗi 10 ms — ~100 lần đánh thức CPU mỗi giây trong lúc Nano đọc liên tục. Luật nhường lượt đọc (1.3.955) giữ nguyên.
- `.claude/rules/tts-vieneu.md` ghi hai thay đổi trên.
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.960] - 2026-11-16

### fix: TTS online thử lại đúng một tầng, chậm thì đọc song song bằng giọng dự phòng, cùng các lỗi rà soát chức năng nghe truyện

Rà soát chức năng nghe truyện (13 phát hiện), anh Bửu duyệt sửa nhóm A–D. Giữa chừng anh Bửu báo: có giọng dự phòng thì không thử lại + timeout 3 s nên *"vài trường hợp bị chậm hoặc lỗi chưa kịp thử thì đã tự chuyển sang offline, nhất là khi tải trước"*. Log thật (364 phút đọc Google / `google_tts`, dòng `[TTSEnergy] Summary`): lượt thường 0,2–0,8 s; 5% số phút có lượt > 3 s mà phần lớn vẫn **thành công** (chậm nhất 6,8 s), chỉ 1 lượt > 7 s và lượt đó lỗi thật. Anh Bửu chọn "7 s + thử lại 1 + song song".

- **Thử lại + timeout chỉ còn một tầng** — `RemoteTTSSynthesisCoordinator` chạy job qua `RemoteTTSAttemptPolicy.run` (file mới). Trước đó vòng thử lại nằm trong closure của từng bên gọi ⇒ đoạn đang đọc gộp vào lượt nạp trước cùng khoá (trường hợp "hit_wait" lúc server chậm) chạy theo chính sách của lượt nạp trước: **một** lần, không thử lại ⇒ lỗi một lần là dừng đọc dù đã cài 3 lần. Nay số lượt thử đọc theo mức ưu tiên **hiện tại** của job, hỏi lại sau mỗi lượt hụt; `enqueue` / `promote` nâng cả job **đang chạy**.
- **Bỏ vòng thử riêng 2 lượt của `GoogleTTSService`** — chồng với vòng chung thành tới 8 request một đoạn, im ~30 s rồi mới dừng. Nghe thử giọng (gọi thẳng service) bọc `RemoteTTSAttemptPolicy.withRetry(maxAttempts: 2)` để giữ hành vi cũ; đọc đoạn bôi đen vốn đi qua coordinator nên nay theo cấu hình chung.
- **Không thử lại lỗi chắc chắn lặp lại**: thiếu API key / văn bản trống / URL hỏng, HTTP 400 / 401 / 403 / 404, base64 hỏng của tiện ích, lượt bị app huỷ. `Retry-After` của server được tôn trọng (tối đa 2 s).
- **Có giọng dự phòng** (`TTSOnlineSynthesisSettings`): timeout theo cài đặt (bỏ 3 s cố định), thử lại khoá **1** lần cho **cả** lượt nạp trước; chỉ chuyển cả phiên khi hết lượt thử hoặc mất mạng.
- **Đọc song song** (`TTSManager+OnlineFallbackHedge`, file mới): đoạn đang đọc quá 3 s chưa có tiếng ⇒ giọng dự phòng tổng hợp song song, bên nào xong trước phát bên đó (`TTSOnlineFallbackState.claimDelivery`); online về trước ⇒ huỷ lượt dự phòng; dự phòng phát rồi mà online vẫn thành công ⇒ đoạn sau vẫn đọc online; online hết lượt thử sau khi dự phòng đã phát ⇒ chỉ chuyển phiên, không đọc lại đoạn.
- **Giọng dự phòng huỷ lượt thừa**: lượt tổng hợp dự phòng đếm người chờ, không còn ai chờ (bỏ qua đoạn, tạm dừng, online về trước) ⇒ huỷ và gỡ khỏi `inflight`. Trước đó bấm "đoạn kế" liên tục thì đoạn mới phải chờ sau mọi lượt của các đoạn đã bỏ (hàng đợi chạy theo thứ tự trong cùng mức ưu tiên), tạm dừng thì cả cửa sổ vẫn tổng hợp rồi vứt kết quả.
- **Lượt nạp trước hết lượt thử** ⇒ bật dự phòng, bỏ mọi lượt nạp trước online đang chờ và nạp lại cửa sổ bằng giọng dự phòng **ngay** (như nhánh mất mạng của 1.3.957). Trước đó đoạn vừa hụt không ai nạp lại tới lúc nó thành đoạn đang đọc.
- **Lượt thử online ở nền** đi qua coordinator (mức `nextChapter`, một lượt) — gọi thẳng service thì chạy chồng lượt tiện ích khác trên cùng runtime JS, hết giờ là huỷ luôn lượt kia.
- **Ghi tiếng online luôn xoá dấu "dự phòng"** (`storeOnlineAudio`: nạp trước từng đoạn, nạp gộp Google, lượt thử ở nền) và dấu của chương khác bị bỏ khi lưu lượt mới. Trước đó đường nạp gộp không xoá dấu ⇒ đoạn online phát theo tốc độ giọng dự phòng + hiện badge "Dự phòng". (Chương kế / prefix chương không bị: chúng ghi ngay sau `forgetChunks`.)
- **Khoá tổng hợp của giọng dự phòng** dùng `TTSSynthesisIdentity.computeKey` (SHA-256) thay hàm băm djb2 tự viết.
- **Tên Nhật có gạch nối tra từ điển phiên âm theo từng phần** (`VieNeuJapaneseNameReader.replacement(for:dictionary:)`): trước đó mục "Sasuke" của người dùng áp cho "Sasuke nói" nhưng "Sasuke-kun" vẫn đọc theo âm tiết tự động. Bộ phân loại đọc lai (`readsSuffix(_:afterHead:dictionaryKeys:)`) theo cùng luật.
- **Sheet nghe mini**: tra lại badge khi đoạn thật sự bắt đầu phát (`$playbackSnapshot` thôi "đang chuẩn bị") ⇒ đoạn đọc bằng giọng dự phòng ngay lúc chuyển giờ có badge "Dự phòng" + RTF; RTF chỉ hiện khi tiếng đoạn do engine offline tạo.
- **Đổi nguồn lúc đang nghe**: lượt tự nghe tiếp ở truyện mới chỉ chạy khi phiên chưa đổi trong lúc tải chương — người dùng tự bấm nghe / dừng thì không bị kéo về chương cũ.
- **Mục "TTS online" của Cài đặt TTS**: có giọng dự phòng thì hàng Thử lại khoá ở 1, Timeout vẫn sửa được; chữ giải thích theo luật mới; đọc khoá giọng dự phòng qua `@AppStorage` nên chọn / bỏ giọng dự phòng rồi quay lại là mục vẽ lại ngay. Màn Giọng dự phòng thêm một đoạn giải thích.
- `RemoteTTSSynthesisCoordinator.swift` giữ dưới trần 429 dòng: `energyPrediction` sang `RemoteTTSSynthesisCoordinator+EnergyPrediction.swift`, tên mức nhiệt dùng chung `NghiSynthesisPolicy.thermalStateName`.
- `rules.md` (§5.7.1 + ba luật retry cũ của 1.3.330–1.3.334) và `.claude/rules/tts.md` ghi luật thử lại mới.
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.959] - 2026-11-16

### docs: gọn AGENTS.md thành bản lõi, CLAUDE.md chỉ import @AGENTS.md, ghi chú phân hệ tách sang .claude/rules

Anh Bửu chạy `/doctor`: `/usage` báo `CLAUDE.md` (128.843 ký tự ≈ 32k token) chiếm ~31% lượng dùng vì Claude Code nạp lại nó ở **mọi** request, dù phần lớn chỉ cần khi sửa một phân hệ. Anh Bửu duyệt: "dọn dẹp AGENTS.md như bạn nói, rồi ở CLAUDE.md chỉ cần @AGENTS.md".

- **`AGENTS.md` = bản lõi dùng chung** (~19,7k ký tự): quy trình bắt buộc, thứ tự thẩm quyền, CHANGELOG, lệnh, build / CI / môi trường, luật `check_architecture.py`, ràng buộc runtime chung, quy ước đặt tên, Tests, Bẫy đã xác minh, cộng bảng mục lục `.claude/rules/` và 5 bẫy dùng chung nhiều phân hệ.
- **`CLAUDE.md` chỉ còn `@AGENTS.md`** (Claude Code nạp qua import) — từ nay chỉ sửa `AGENTS.md`, bỏ luật mirror hai file.
- **14 file `.claude/rules/*.md`** chép **nguyên văn** các mục phân hệ (storage, reader-text-pipeline, tts, tts-vieneu, translation, extensions-js, comic-video, audio-playlist, floating-pills, browser, books-sources, network-dns, ci-release, ui-conventions). Mỗi file khai `paths:` nên Claude Code chỉ nạp khi đọc / sửa file khớp; Codex và agent khác đọc theo mục lục. Ghi chú mới của một phân hệ thì thêm vào đúng file đó.
- **Thiết lập codegraph trên máy mới** thành skill `.claude/skills/codegraph-setup/SKILL.md`. `.gitignore` thêm `!.claude/rules/`.
- **Bỏ 6 câu cũ / suy ra được từ code**: câu CHANGELOG lặp, mô tả `codegraph.json`, dòng code signing / iOS 17 / danh sách SPM (đã thiếu gói), "88 entry hết hạn 2026-12-31", "814 file Swift", "(19 file)" + danh sách file `+` (nay 343 file).
- Kiểm: script đối chiếu từng dòng không rỗng của `CLAUDE.md` cũ — mọi dòng (trừ 6 câu trên và tiêu đề mục đổi thành tiêu đề file) có mặt nguyên văn trong bộ file mới. Không đổi code, không build.

## [1.3.958] - 2026-11-16

### fix: RTF trên sheet nghe mini chia cho thời lượng lời đọc, không tính khoảng lặng chèn thêm

Anh Bửu: *"rtf có chính xác không vậy, sao tôi thấy tts engine nào cũng thấp hết vậy"* rồi duyệt "Đổi, bỏ khoảng lặng". Số là số đo thật và thấp là đúng với máy (Nano + Core ML 0,09–0,13 ở log build 1285), nhưng mẫu số từ 1.3.954 là `pcmDuration` — gồm cả khoảng nghỉ giữa các chunk và khoảng lặng đuôi theo ranh giới, là phần không tốn công tổng hợp. Đoạn dài gần như không lệch (7,46 s: 0,097 so với 0,099); đoạn ngắn lệch rõ ("Ninh công tử?" 0,89 s lời + 0,20 s lặng: 0,45 so với 0,56).

- **Một công thức, một chỗ:** `TTSEngineRTFStore.record(text:synthesisMs:speechSeconds:)` tự chia; ba engine chỉ đưa thời gian tổng hợp và thời lượng lời đọc. Lời đọc dưới 0,05 s (đoạn im lặng) thì không ghi ⇒ badge ẩn thay vì hiện "RTF 0.00".
- **Nano:** dùng `output.speechDuration` engine đã tính sẵn.
- **Turbo:** `pcmDuration − pause` — nay khớp với `RTF=` của dòng log `[VieNeuTurbo] Đoạn` (trước đó badge và log của cùng một đoạn ra hai số khác nhau).
- **Piper / NghiTTS:** `ONNXPiperEngine.synthesizeInternal` đếm số mẫu lặng chèn thêm (khoảng nghỉ theo dấu câu giữa các chunk + khoảng lặng đuôi) và trả thêm `speechDuration`; `PiperSynthesisPayload` có thêm trường `speechDuration` (không truyền ⇒ bằng `pcmDuration`), `PiperSynthesisCoordinator` chuyển tiếp.
- **Không đổi:** `rtf=` trong log `[VieNeuPerf]` và `[NghiEnergy]` vẫn chia cho `pcmDuration` (log đã in riêng `speech=`), bộ thích nghi chế độ của Nano cũng vậy. RTF vẫn so với thời lượng tiếng ở tốc độ **tổng hợp**, không nhân tốc độ phát, và chỉ đo lúc engine chạy (không gồm thời gian chờ hàng đợi / chờ khoá).
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.957] - 2026-11-16

### fix: Giọng dự phòng tổng hợp các đoạn đúng thứ tự và bật ngay khi lượt nạp trước lỗi vì mất mạng

Log build 1285 (bản 1.3.956, chương 24): không còn dòng `Nạp sẵn + chạy nháp` nào và đoạn dự phòng thứ 2 trễ **459 ms** thay cho 5178 ms của build 1283 — nhưng vẫn trễ. Dựng lại theo số byte của từng lượt phát: đoạn 21 phát lúc 13:13:04.15, ba lượt nạp trước 22 / 23 / 24 được tạo cùng lúc, và hàng đợi tổng hợp chạy **23 → 22 → 24**. Đoạn 23 (9,5 s tiếng, session Core ML còn nguội) mất 2,8 s; đoạn 22 chỉ bắt đầu lúc 07.02 trong khi cần lúc 07.22.

- **Nguyên nhân:** mỗi lượt dự phòng phải qua `service.prepare` (nhiều điểm chờ: nhả Turbo, `Task.detached`, khoá engine) rồi mới vào `PiperSynthesisCoordinator`, nên trong ba lượt tạo cùng lúc lượt nào tới trước là ngẫu nhiên; hàng đợi đang rảnh thì chạy luôn lượt tới trước và không ngắt giữa chừng. Việc nâng mức ưu tiên của 1.3.955 chỉ xếp lại lượt **đang chờ**, không cứu được trường hợp này.
- **Sửa:** lượt nạp trước nối đuôi lượt nạp trước tạo ngay trước nó (`TTSOnlineFallbackState.prefetchTail`) — chờ lượt đó xong rồi mới `prepare` và vào hàng đợi, nên thứ tự tổng hợp luôn là thứ tự tạo (đoạn gần trước). Đoạn **đang đọc** không nối đuôi: đi thẳng; nếu lượt nạp trước của chính nó còn xếp hàng (`hasStarted == false`) thì bỏ lượt đó và tạo lượt mới, đã rời hàng thì dùng chung + `promote` như cũ. Tập `demanded` / `isDemanded` của 1.3.955 thay bằng `started` / `hasStarted`.
- Với thứ tự đúng, ở log này đoạn 22 (cùng cỡ khung với đoạn 21 vừa chạy) xong sau ~0,65 s, sớm hơn lúc cần ~2,3 s.
- **Bật dự phòng sớm khi mất mạng** (anh Bửu duyệt: "Thêm bật dự phòng sớm"). Cùng log: đoạn dự phòng **đầu tiên** trễ ~1,9 s (`RemoteHandoff index=21 gapMs=1918`) vì chỉ bắt đầu tổng hợp khi tiếng online đã nạp phát hết, dù mạng mất từ 13:12:51 — 11 s trước đó — và các lượt nạp trước online lỗi liên tục. `handleOnlinePrefetchFailure` (1.3.953) chỉ bật dự phòng khi lỗi là hết giờ; nay bật cả khi lượt nạp trước lỗi lúc `TTSNetworkReachability` báo máy không có mạng (và đang đọc): bỏ các lượt nạp trước online đang chờ rồi `updatePrefetchWindow()` ⇒ các đoạn còn thiếu trong cửa sổ được tổng hợp bằng giọng dự phòng ngay trong lúc tiếng online đã nạp còn phát. Tiếng online đã nạp giữ nguyên; lỗi nội dung lúc vẫn có mạng thì im như cũ.
  - Hệ quả thấy được: toast "Mất mạng — đọc bằng giọng dự phòng" hiện sớm hơn (lúc lượt nạp trước đầu tiên lỗi, không phải lúc hết tiếng online); mạng có lại trong vài giây đó thì các đoạn đã nạp bằng giọng dự phòng vẫn phát hết rồi mới về online (luật cũ của 1.3.945).
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.956] - 2026-11-16

### fix: VieNeu Nano đọc đúng hậu tố xưng hô, thêm khoảng dẫn cho dòng thoại, không cắt chunk giữa tên và các lỗi rà soát khác

Sửa tiếp các phát hiện của lượt rà soát mã VieNeu Nano (cùng ngày với 1.3.955).

- **Hậu tố `kun` / `san` / `chan` / `tan` / `chin` giờ được đọc theo âm tiết.** `VieNeuRomajiSyllabifier.syllables(of:)` trả `nil` cho từ dưới 2 âm tiết nên 5/10 mục của `honorifics` là mục chết — "Sasuke-kun" chỉ đổi "Sasuke", còn "kun" đi vào `SeaG2P` đọc kiểu tiếng Anh. Thêm tham số `minimumSyllables` (mặc định 2, luật nhận tên không đổi); `VieNeuJapaneseNameReader.honorificPhonemes` gọi với 1 ⇒ `kˈun`, `sˈaːn`, `tʃˈaːn`… đúng các luật phiên âm đã duyệt. Bản chép Python của bộ cắt (`Scripts/gen_vieneu_romaji_english_lookalikes.py`) chỉ dùng mặc định nên không phải sửa.
- **Đọc lai không còn chuyển sang Turbo vì hậu tố.** `VieNeuForeignTextClassifier` tách token ở gạch nối nên "sensei" / "senpai" / "sama" của "Kakashi-sensei" bị tính là tiếng nước ngoài dù bộ tiền xử lý đã đọc chúng theo âm tiết. Giờ bộ phân loại theo dõi phần đầu của cụm gạch nối và hỏi `VieNeuJapaneseNameReader.readsSuffix(_:afterHead:)`.
- **Khoảng dẫn cho đoạn mở đầu bằng dấu mà vocab không có.** `withLeadIn` xét theo ký hiệu đầu tiên **có trong vocab**: dấu nháy mở của dòng thoại (`normalizeVietnameseText` giữ lại, `encode` bỏ đi) trước đây làm chunk bị coi là "đã mở đầu bằng dấu câu" nên không có khoảng dẫn. Phần bị bỏ ở đầu được cắt khỏi chuỗi (ids không đổi; chỉ không còn đếm vào `dropped=`). Dấu có trong vocab đứng đầu thì như cũ. Log build 1283 cho thấy dấu hai chấm không có trong vocab; dấu nháy có hay không thì **chưa xác minh** được từ repo.
- **Cắt chunk không tính ký hiệu bọc phiên âm và không cắt giữa tên.** `VieNeuTTSEngine+Chunking` đo độ dài bằng `length(_:)` (bỏ `SeaG2P.rawPhonemeOpen` / `Close`) — trước đó "Sasuke" 6 chữ thành 18 ký tự nên đoạn nhiều tên bị tách chunk sớm; `balancedCut` có thêm luật chặn `splitsName` (hai âm tiết bọc đứng liền nhau).
- **Khung "miễn phí" chỉ có khi chunk chạy được bằng Core ML.** `runChunk` hỏi `canRun` trước khi hỏi trần cỡ khung: chunk sẽ lùi ORT vì chuỗi token dài hơn graph / giọng khác dạng thì không còn được thêm tới +30% khung như thể miễn phí (ORT ⇒ đúng `minimumBoost`, chế độ Miễn phí ⇒ không thêm).
- **`coreMLChunks` đếm sau khi codec xong** (`VieNeuCoreMLFlowBackend.decode`): codec lỗi rồi chạy lại ORT không còn bị tính là chunk Core ML (badge "Nano · Core ML" sai).
- **Dọn mã chết của màn thử đã bỏ (1.3.919):** `lastDroppedScalars` / `lastChunkCount` / `lastPhonemeSample` / `lastSpeechDuration` / `lastTiming` / `lastVectorMs` / `lastOtherMs` của `VieNeuTTSService`, `Output.phonemeSample` của engine (mỗi lượt ghép chuỗi phoneme mọi chunk cho không ai đọc), `Timing.vectorMs` / `otherMs`.
- **Chưa sửa, chờ anh Bửu quyết:** luật 2 của `VieNeuNameFrameBoost.isNameChunk` nhận nhầm cặp Hán Việt thanh ngang ("Tu La", "Ma Tu", "Hư Vô") là tên phiên âm — luật do anh nghe và duyệt. RTF trên badge vẫn chia cho `pcmDuration` (gồm khoảng lặng) — công thức anh đã duyệt ở 1.3.954 và dùng chung với Piper.
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.955] - 2026-11-16

### fix: Giọng dự phòng VieNeu không còn hụt đoạn offline thứ 2 do chạy nháp Core ML lặp lại ở mỗi đoạn

Anh Bửu: *"tắt mạng sau khi đọc xong cache audio online thì phát được ngay giọng offline nhưng lại hụt đoạn offline thứ 2"*. Log build 1283 (chương 7, giọng dự phòng VieNeu Nano): tiêu đề phát sau 1,7 s, đoạn kế trễ **5,18 s** (`RemoteHandoff index=1 gapMs=5178`), các đoạn sau 30–40 ms. Ba nguyên nhân chồng nhau:

- **Chạy nháp Core ML lặp lại ở mỗi đoạn.** `TTSManager.onlineFallbackAudio` gọi `service.prepare` cho **từng** đoạn dự phòng, mà `VieNeuTTSService.prepare` lần nào cũng bắn `warmUpCoreMLForReader()`; `warmUpIfReady` chỉ chặn hai lượt chạy cùng lúc, không chặn lượt lặp ⇒ 4 lượt chạy nháp trong 20 s (5493 / 3150 / 1583 / 5800 ms). Sửa: `VieNeuCoreMLFlowBackend.isWarm(kind:bucket:)` (session đang nạp **và** đã chạy lượt đầu) + `VieNeuCoreMLReaderRoute.pendingWarmUp` — chỉ chạy nháp khung còn thiếu, đủ rồi thì thoát ngay (không đọc gói, không log). `releaseSessions()` (máy báo thiếu RAM) quên luôn `firstRunDone` ⇒ lần `prepare` sau chạy nháp lại đúng các khung đã nhả.
- **Lượt chạy nháp giữ khoá tổng hợp liền cả 5 khung.** `NSLock` không xếp hàng công bằng: luồng chạy nháp nhả khoá rồi lấy lại ngay ở khung kế nên thắng luồng đang chờ — trong log, từ 11:19:11.53 tới 15.51 không lượt tổng hợp nào chen vào được. Sửa: `VieNeuTTSEngine.lockForReader()` (dùng ở `synthesize` và `prepare`) đếm lượt đọc đang xếp hàng; `withSynthesisLock` chỉ lấy khoá khi khoá rảnh và không ai xếp hàng (`lock.try()`, hỏi lại mỗi 10 ms). Lượt đọc tới giữa một khung chỉ chờ hết khung đó — có tác dụng cả ở lần chạy nháp đầu tiên (engine Nano vừa nạp lúc giọng dự phòng bật).
- **Đoạn đang chờ phát bị xếp sau các đoạn nạp trước.** Ba lượt nạp trước cùng mức `.immediateSuccessor`, kẹt ở `prepare` (chờ khoá engine) rồi vào hàng đợi theo thứ tự ngẫu nhiên: log tổng hợp đoạn 3 → 2 → 1 trong lúc đoạn 1 đang chờ để phát. Sửa: lượt dự phòng mang khoá tổng hợp (`onlineFallbackSynthesisKey`: engine + giọng + tốc độ + ranh giới + chữ); đoạn đang đọc dùng chung lượt nạp trước đang chạy thì `PiperSynthesisCoordinator.promote(…, to: .demand)`, và lượt chưa kịp vào hàng đợi đọc `TTSOnlineFallbackState.isDemanded` để xếp thẳng ở mức `.demand`.
- Đoạn 66 ký tự mà phiên WorkBuddy gọi là "mồ côi, không bao giờ phát" thật ra là **đoạn 3** (`bytes=192044` = 4,00 s, phát lúc 11:19:28) — không có tiếng nào bị bỏ.
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử trên máy. Thử: tắt mạng giữa chừng, nghe ≥ 5 đoạn offline; log không còn dòng `Nạp sẵn + chạy nháp` lặp lại và `RemoteHandoff … gapMs` của đoạn 1 về cỡ vài chục ms (lần đầu engine Nano còn nguội có thể vẫn chờ nạp session).

## [1.3.954] - 2026-11-16

### feat: hiển thị RTF của VieNeu và Piper trên sheet điều khiển nhanh TTS

Anh Bửu yêu cầu mockup "hiển thị thêm badge rtf của vieneu" rồi bổ sung *"hiển thị rtf cho có pipetts luôn nhé"*. RTF = thời gian tổng hợp ÷ thời lượng audio (0,32 = nhanh ~3× thời gian thực, > 1 = chậm hơn thời gian thực) — số **đo trong engine**, không ước lượng.

- **`TTSEngineRTFStore`** (mới, `Services/TTS/`): kho RTF theo **chữ đã nói** (cùng khoá với `VieNeuEngineBadgeStore`, capacity 64) — ghi từ cả VieNeu (Nano/Turbo) và Piper/NghiTTS. Số đo lấy trong engine, không lẫn thời gian chờ hàng đợi (`queueWaitMs` của Piper bị loại).
- **`TTSRTFBadge`** (mới, `Views/TTSWidget/`): viên nhỏ kiểu `TTSEngineBadge` — icon `gauge.with.dots.needle.50percent` + `"RTF 0.32"` (`monospacedDigit`), nền capsule 18%. Màu theo ngưỡng: ≤ 0,5 xanh · 0,5–1,0 vàng · > 1,0 đỏ.
- **Ghi số:** Nano tại chỗ ghi badge cũ (`VieNeuTTSService` — có sẵn `output.synthesisMs` + `output.pcmDuration`); Turbo **dời** lệnh ghi badge xuống sau khi tính `synthesisMs`/`pcmDuration`; Piper ghi trong `PiperTTSService.synthesizeWithDuration` (trả sẵn `payload.synthesisMs`/`payload.pcmDuration`).
- **Hiện:** `TTSQuickControlSheet.NowReadingBlock` thêm viên RTF ngay sau badge "Turbo · AMX"; `TTSQuickControlNowReading.Snapshot` thêm `rtf`, tách `spoken` (chữ đã áp quy tắc thay thế) khỏi nhánh VieNeu để tra cho mọi engine. Đoạn chưa tổng hợp xong (chưa có số đo) ⇒ viên ẩn.
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.953] - 2026-11-16

### feat: TTS online có cấu hình timeout và số lần thử lại, có giọng dự phòng thì chuyển offline sau 3 giây

Anh Bửu: *"giảm thời gian timeout của các ext tts online khi có giọng offline backup"* ⇒ hỏi từng nhánh (grill-me) rồi mới code. Trước đây mỗi engine tự quyết: `ExtTTSService` retry cứng 2 lượt, Google TTS không retry, và **không** có giới hạn thời gian chờ (fetch của extension mặc định 15 s, script tự đặt tới 120 s) ⇒ đoạn đang đọc có thể im lặng ~30 s trước khi giọng dự phòng lên tiếng.

- **Hai cấu hình ở Cài đặt TTS › mục "TTS online"** (chỉ hiện khi trình đọc chính là online — Google Cloud TTS / TTS tiện ích; mỗi hàng có nút "?" giải thích):
  - **Số lần thử lại**: 0–5, mặc định **3** (= số lần *thử lại*; 0 = chỉ thử một lần). Retry **mọi lỗi** (trừ `CancellationError`).
  - **Timeout mỗi lượt thử**: 5–20 s, mặc định **7 s**.
  - Đã chọn giọng dự phòng offline ⇒ hai hàng **tự khoá**: hiện **0** lần thử lại và **3 giây** timeout (cứng) — lúc đó có tiếng thay thế nên không cần chờ thử lại.
- **Một chỗ điều khiển** — `TTSAudioSynthesisWorker.synthesizeParagraph` (điểm chặn duy nhất của mọi lượt tổng hợp online: playback, nạp trước, prefix chương kế):
  - `withTimeout` huỷ **thật** khi hết giờ: huỷ Task con ⇒ `JSExecutor.callAsync` gọi `cancelCurrentExecution()` (`JSExecutor.swift:949`) huỷ `URLSessionDataTask` đang chờ; Google thì `URLSession` bị huỷ theo Task ⇒ không rò tiến trình.
  - `withRetry` **bên trong** closure của `RemoteTTSSynthesisCoordinator` ⇒ đoạn đang đọc giữ slot liền mạch. (Đặt *ngoài* coordinator thì tệ hơn: lúc một lượt thử hụt, `complete()` gọi `startNextIfNeeded()` ngay trong cùng lượt actor ⇒ lượt nạp trước chiếm slot trước khi lượt retry kịp xếp lại ⇒ đoạn đang đọc nhận lỗi muộn ~33 s thay vì ~22 s.)
  - Retry chỉ cho **đoạn đang đọc** (`priority == .current`); lượt nạp trước thử **một** lần rồi bỏ (server chết thì thử lại vô ích mà lại tốn slot hàng đợi).
- **Gỡ retry khỏi `ExtTTSService`** (tránh nhân đôi 4 × 2 = 8 lượt); xem thử giọng trong sheet (`TTSVoicePreviewPlayer`) gọi thẳng service nên tự thử lại 2 lượt như cũ.
- **Lượt nạp trước hụt timeout ⇒ bật giọng dự phòng ngay** (`TTSManager+OnlineFallbackPrefetch`): trước đây lỗi nạp trước chỉ được log ⇒ app phát nốt tiếng cache tới hết cửa sổ nạp trước (~10–30 s) mới chuyển offline. Chỉ **lỗi timeout** mới kích hoạt (triệu chứng server chết chung); lỗi nội dung (voice sai, base64 hỏng) thì im như cũ, chờ đoạn đang đọc quyết định. Khi bật theo đường này: **không** huỷ lượt đang đọc, **không** huỷ lượt nạp trước khác, **không** xoá tiếng đã nạp — chỉ các đoạn từ đoạn lỗi trở đi mới chuyển sang giọng dự phòng.
- **Sửa race:** lượt đang đọc đang bay lỗi *sau khi* giọng dự phòng đã bật ⇒ `switchToOnlineFallback` trước đây trả `false` ⇒ dừng đọc + báo lỗi; nay đọc lại đoạn đó bằng giọng dự phòng.
- **Lượt thử của probe** (quay về online) cũng gói timeout 3 s để kết luận nhanh khi server chậm; nhịp probe 15 s → ×2 → trần 120 s giữ nguyên.
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.952] - 2026-11-15

### feat: Nano đọc chậm đoạn có tên phiên âm để không nuốt chữ, dùng phần khung Core ML tính sẵn nên gần như không tốn thêm pin

Anh Bửu: *"vẫn có mất chữ … mất giữa đoạn chứ không ở chỗ dấu"*, *"Chữ Goku rất hay mất chữ"* (nghe thành "gu"). Anh nghe 12 file riêng (bám chữ CFG 3 / 4,5 / 6 × 4 lượt): lượt nào mất thì mất ở **mọi** mức ⇒ nhiễu khởi đầu quyết định, bám chữ không chữa. Đo 30 lượt trên PC cùng câu "Son Gô Cu cười trả lời…": CFG, biên độ nhiễu, CFG chỉ theo chữ, sway, 16 bước, cách viết phiên âm đều không giảm (5–11/30 so với 8/30); chỉ **số khung** giảm đều theo nấc — 62 khung 8/30 → +4% 5 → +9% 3 → +14% 2 → +20% 1 → +29% 0. Anh hỏi ảnh hưởng nhiệt trước khi làm ⇒ tìm ra phần miễn phí: Core ML tính trọn cỡ khung cố định nên khung thêm tới trần cỡ đang dùng không tốn phép tính. Anh chọn **"Miễn phí + tối thiểu 10%"**.

- **`VieNeuNameFrameBoost`** (mới, `Services/TTS/VieNeu/Names/`): `isNameChunk` nhận đoạn có tên phiên âm theo âm tiết — ≥ 2 âm tiết do `VieNeuJapaneseNameReader` sinh (đếm `SeaG2P.rawPhonemeOpen`) **hoặc** ≥ 2 chữ viết hoa liền nhau là âm tiết mở không dấu thanh ("Gô Cu", "Na Ru Tô"; dấu câu cắt chuỗi; tên Hán Việt không dính). `frames(base:mode:limit:freeCeiling:)`: đích +30%; `free` = dừng ở trần cỡ khung đang dùng; `freeWithMinimum` (mặc định) = chưa đủ +10% thì nhảy lên cỡ lớn hơn rồi dùng luôn phần trống của cỡ đó, không nhảy khi vượt cỡ lớn nhất (Core ML sẽ lùi ORT); chạy ORT thì thêm đúng +10%. Khoá `vieneuNameFrameBoostMode`.
- **`VieNeuFlowBackend.freeFrameCeiling(for:)`** (mặc định `nil`); `VieNeuCoreMLFlowBackend` trả cỡ nhỏ hơn giữa cỡ vòng Euler và cỡ codec.
- **`VieNeuTTSEngine.runChunk`** nhận `nameBoost`, tính `frames` từ `baseFrames`; `Timing.nameBoostChunks` / `nameBoostFrames` ⇒ log `[VieNeuPerf] … nameBoost=<số chunk>/+<số khung>`.
- **Cài đặt**: hàng chọn "Đọc chậm đoạn có tên (Nano)" (Tắt / Miễn phí / Ít nhất 10%) ở Cài đặt TTS (mục Quản lý riêng của VieNeu) và màn Giọng dự phòng, cùng `VieNeuJapaneseFlags.nameFrameBoost`; giải thích sau nút "?" (`nameFrameBoostHelp`). Fingerprint giọng dự phòng thêm chế độ này. Trình đọc chính: theo luật `TTSSettingsSnapshot` (không gồm `vieneu*`), đoạn đã nạp trước giữ cài đặt cũ.
- **Số ước trên chương Dragon Ball của log build 1280** (bản chép Python của luật, cỡ khung giả định 64/96/128/160): 19/48 đoạn có tên; "Miễn phí" thêm khung trung vị +29% (thấp nhất +3%), phép tính Core ML +0%; "Ít nhất 10%" thêm trung vị +30% (thấp nhất +12%), phép tính cả chương +2,9%, tiếng cả chương dài thêm ~13% (đoạn có tên đọc chậm đi đúng mức thêm, không bù ở tốc độ phát).
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử máy — phần tiếng chờ anh nghe trên iPhone.

## [1.3.951] - 2026-11-15

### fix: Màn Giọng dự phòng có thêm công tắc Đọc tên Nhật theo âm tiết

Anh Bửu: "giọng dự phòng thiếu config phiên âm mới". Màn Giọng dự phòng (`TTSFallbackVoiceSettingsView`) tự dựng mục Quản lý riêng của VieNeu nên không có hàng mới của 1.3.950.

- Thêm `Toggle("Đọc tên Nhật theo âm tiết")` ngay dưới "Áp dụng từ điển phiên âm VieNeu", cùng `VieNeuJapaneseFlags.nameSyllablesEnabled` (một khoá `vieneuJapaneseNameSyllablesEnabled` cho cả trình đọc chính lẫn giọng dự phòng — như công tắc từ điển).
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử máy.
