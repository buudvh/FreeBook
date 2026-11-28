# CHANGELOG - Nhật ký Thay đổi CodeGraph Tàng Công Các

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **Tàng Công Các**.

## [1.3.1110] - 2026-11-28

### docs: ghi chú lọc name local theo hậu tố Nhân danh, tiền tố, họ riêng, luật phân loại mới và độ dài name

Cập nhật `.claude/rules/` cho đợt 1.3.1103–1109 (plan `Docs/Plans/2026-11-27-phan-loai-name.md`).
- `translation.md`: "Đuôi" ⇒ "Hậu tố" (1.299 mục, loại Nhân danh thay Pronouns, chip lọc loại); Tiền tố
  (`LocalNameFilterPrefixStore`, chỉ ghép trước tên Latin); Họ riêng (`QuickTranslationSurnameStore.nameFilter`);
  thứ tự phân loại L11 → L1 / L2 → L3 / L4, L6, lý do bỏ `rank_prefix` / `glued_names` / `length_off`; bản tham chiếu
  11 truyện `run11_phanloai.sh` + `cmp_rules_phanloai.py`; hàng Tiền tố / Hậu tố ở màn duyệt; Độ dài name; popup Lưu;
  đầu thẻ dính; dấu gói tạm tính cả tiền tố.
- `ui-conventions.md`: danh sách áp màn Sửa từ; popup ba cách lưu ở chỗ không phải nhập file.
- `storage.md`: các khoá `UserDefaults` / `@AppStorage` của danh sách lọc name.

## [1.3.1109] - 2026-11-28

### feat: sheet lọc name local có danh sách Tiền tố và Họ, thanh kéo hai đầu chọn độ dài name

Plan 2026-11-27-phan-loai-name L10, L13, L15 (anh Bửu: "Thêm chọn min max số từ ở màn lọc name, dạng kéo", "step min max
1 thôi"), mockup https://claude.ai/artifact/9qgrqxGZpkiCQHQdK4vgbx khung 5.

- Mục "Danh sách": Hậu tố · Tiền tố · Họ (`LocalNameFilterSurnameListView`, số = `QuickTranslationSurnameStore.nameFilter`)
  · Không phải name, số mục kiểu Việt (1.299), đọc lại mỗi lần quay về; giải thích "?" viết lại cho bốn danh sách.
- Mục "Tuỳ chọn": hàng "Độ dài name" dưới "Ít nhất N lần" — thanh kéo hai đầu tự dựng `LocalNameFilterLengthRangeSlider`
  (một `DragGesture`, nấc 1 chữ 2…10, đầu phải 10 = "10+" không giới hạn, hai núm trùng nhau được, chọn núm theo hướng
  kéo khi trùng; mỗi núm là phần tử trợ năng riêng có `accessibilityAdjustableAction`; rung nhẹ mỗi nấc), số bên phải
  "2 – 10+ chữ" / "3 – 6 chữ"; nhớ bằng `@AppStorage` `localNameFilterMinLength` / `localNameFilterMaxLength`.
- "Bắt đầu lọc" truyền `prefixes` (danh sách Tiền tố), `minLength`, `maxLength` (10+ ⇒ `nil`) vào
  `LocalNameFilter.Configuration`; dấu nghĩa của gói tạm tính theo đúng danh sách tiền tố của lượt lọc.

Chưa biên dịch được tại chỗ (Windows); check_architecture chỉ còn violation cũ JSDom.swift.

## [1.3.1108] - 2026-11-28

### feat: màn Sửa từ của màn duyệt lọc name local có hàng Tiền tố và Hậu tố cho mọi name, hiện đủ mục nằm trong cụm

Plan 2026-11-27-phan-loai-name mục 7, 10, L10, L11 (anh Bửu: "Ngoài lựa chọn nhanh hãy hiển thị đủ các hậu tố và tiền tố
nằm trong cụm", "sắp xếp theo thứ tự số từ tăng dần"), mockup https://claude.ai/artifact/9qgrqxGZpkiCQHQdK4vgbx khung 2–3.

- `LocalNameFilterSuffixQuickRow(flavor:)` dùng cho hai hàng "Tiền tố" (trên) và "Hậu tố" (dưới), hiện cho mọi loại name
  kể cả tên người (mục mới mặc định Nhân danh); họ tộc (萧家) vẫn không có.
- Chip ✓ cho mọi mục có sẵn nằm trong cụm, dài 1–6 chữ: hậu tố ở cuối hoặc giữa cụm (东城区血刀帮 ⇒ ✓ 区, ✓ 帮), tiền tố ở
  đầu hoặc giữa cụm; chạm ⇒ sửa mục đó. Dấu ● trên mục đang ghép nghĩa: hậu tố dài nhất ở cuối / tiền tố dài nhất ở đầu,
  cùng nhóm với name như bộ ghép (Nhân danh ⇄ tên người). Chip "+" cho đoạn cuối / đầu 1–3 chữ chưa có; "+ Thêm hậu tố /
  tiền tố" (mở cả cụm) luôn cuối hàng; mọi chip xếp theo số chữ tăng dần (陈太上长老: 老 · 长老 · + 上长老 · ● 太上长老).
- `LocalNameFilterReviewSuffixContext`: `affixKind(for:)` thay `suffixKind` (tên người ⇒ Nhân danh);
  `enqueueRecompose(affixes:flavor:)` ghép lại name kết thúc bằng hậu tố / mở đầu bằng tiền tố vừa lưu, kể cả tên người,
  truyền nghĩa máy ghép lần trước (giữ danh xưng 1 chữ "Lâm ca") và danh sách tiền tố hiện tại.
- Toast "Đã thêm hậu tố / tiền tố X · ghép lại N name".

Chưa biên dịch được tại chỗ (Windows); check_architecture chỉ còn violation cũ JSDom.swift.

## [1.3.1107] - 2026-11-28

### feat: lọc name local đổi Đuôi thành Hậu tố, danh sách hậu tố có chip lọc loại và loại Nhân danh, màn Tiền tố dùng chung màn danh sách

Plan 2026-11-27-phan-loai-name mục 6, 11, L10, L11 (anh Bửu: "Đuôi bây giờ gọi hậu tố đi cho đối xứng tiền tố", "Thêm
tiền tố phải đầy đủ như hậu tố"), mockup https://claude.ai/artifact/9qgrqxGZpkiCQHQdK4vgbx khung 4, 6, 7.

- Mới `LocalNameFilterAffixListFlavor` (`.suffix` / `.prefix`): mọi chỗ khác nhau giữa danh sách "Hậu tố" và "Tiền tố" —
  store (`LocalNameFilterSuffixStore` / `LocalNameFilterPrefixStore`), danh từ trên màn, badge "Hậu tố · chung" /
  "Tiền tố · chung", mặc định mục mới (hậu tố: Địa danh, sau tên; tiền tố: Nhân danh, trước tên), luật "nằm cuối / đầu
  name" khi thêm từ một name, mẫu dòng "Ví dụ", lời giải thích "?". Tên type / file giữ chữ Suffix.
- `LocalNameFilterSuffixListView(flavor:)` dùng cho cả hai danh sách (tiêu đề "Hậu tố" / "Tiền tố"); thanh tab đổi thành
  hàng chip lọc theo loại kèm số (`LocalNameFilterAffixKindFilterBar`: Tất cả 1.299 · Địa danh · Tổ chức · Thuật ngữ ·
  Nhân danh, kiểu chip `ExtensionKindFilterBar`, nền chip thường mờ hợp sheet kính, số kiểu Việt); chỉ hiện loại có mục
  (danh sách tiền tố gốc chỉ có Nhân danh). Thêm mới lấy loại của chip đang chọn.
- `LocalNameFilterSuffixEditorSheet(flavor:)`: màn Sửa từ đủ như hậu tố cho tiền tố (hai cặp ‹ ›, token, ô nghĩa, chip
  nghĩa gợi ý, aa…AA, Loại 4 + Nghĩa đứng + Ví dụ, tra cứu); loại thứ tư Nhân danh (ví dụ 陈 + 长老 → Trần trưởng lão),
  tiền tố ví dụ 老尼尔 → lão Neil; thêm từ một name ⇒ "Thêm" mờ + dòng nhắc khi phần chọn không nằm cuối (hậu tố) / đầu
  (tiền tố) name, chọn cả cụm hoặc dài quá 6 chữ. Sửa lỗi biên dịch: `switch` trên `SuffixKind` thiếu `.person`.
- Mọi chữ "Đuôi" trên màn đổi thành "Hậu tố" (tiêu đề, số mục, ô trống, toast, trợ năng, menu …, hộp khôi phục).

Chưa biên dịch được tại chỗ (Windows); check_architecture chỉ còn violation cũ JSDom.swift.

## [1.3.1106] - 2026-11-27

### feat: bấm Lưu ở màn duyệt name hiện popup ba cách lưu như nhập file, cả luồng AI và lọc name local

Plan 2026-11-27-phan-loai-name mục L16 (anh Bửu: "Bấm lưu sẽ hiển thị màn popup vào hoạt động giống nhập name/vp từ
file. Tất nhiên chỉ có name mới thì nhập thẳng như hiện tại. Làm cho cả AI nhé"), mockup
https://claude.ai/artifact/9qgrqxGZpkiCQHQdK4vgbx khung "Bấm Lưu → chọn cách nhập".

- ReaderAINameReviewSheet (+Save mới): bỏ hộp confirmationDialog "Gộp / Thay thế hoàn toàn". Bấm "Lưu vào Name riêng /
  VP riêng" ⇒ đọc file đích của truyện ngoài main; có name đang chọn đã có trong đó ⇒ popup DataImportModePopup đủ ba
  chế độ (Thay thế toàn bộ / Gộp — chọn sẵn / Chỉ thêm key mới), tiêu đề "Lưu vào Name riêng" / "Lưu vào VP riêng",
  dòng dưới "N name mới · M đã có trong Name riêng" (icon người / sách, không phải icon file), nút "Lưu". Toàn name mới
  ⇒ lưu thẳng bằng Gộp như trước.
- "Đã có" tính theo file Names.txt / VietPhrase.txt riêng của truyện (đích thật của ba chế độ), không theo cờ
  hasInBookNames / hasInBookVP (hai cờ đó gồm cả Name / VP Chung và từ điển gốc). Name chỉ có ở từ điển chung giờ lưu
  thẳng thay vì hỏi — kết quả y như chọn Gộp.
- Lời giải thích ba chế độ theo ngữ cảnh lưu: "Xoá Name riêng cũ của truyện, chỉ giữ các name đang chọn." (VP thì "VP
  riêng"), "Name đã có thì lấy nghĩa mới đè lên; chưa có thì thêm vào.", "Chỉ thêm name chưa có; name đã có giữ nguyên
  nghĩa cũ.". DataImportModePopup / .dataImportModePopup nhận thêm messageSystemImage + explanations (tham số tuỳ chọn,
  mặc định giữ icon file và lời cũ — các chỗ nhập file không đổi).
- Đường lưu nhận DataImportMode thay cho isMerge: onSave của sheet, ReaderAIFullScreenView.saveNamesToDictionary,
  LocalNameFilterSheet.save, AIHarnessService.saveExtractedEntries. Service ghi qua TranslationDictionaryWriter.importRecords
  mới (tách từ importEntries, cùng luật ba chế độ với nhập file); nghĩa chuẩn hoá trước, khoá lặp giữ mục đầu.
- saveExtractedEntries trả ExtractedEntriesSaveResult? (nil = không có mục hợp lệ / ghi lỗi). Toast dùng chung
  ReaderAINameReviewSheet.savedToast: "Đã lưu N mục vào … của truyện" như cũ; Chỉ thêm key mới thêm " · giữ nguyên M mục
  đã có"; mọi name đã có ⇒ "Không có mục mới …" (thông báo, không phải lỗi — lọc name local vẫn xoá gói tạm). Tóm tắt
  trong tin AI ở chế độ Chỉ thêm key mới không khẳng định đã lưu đủ N tên.

Chưa biên dịch được tại chỗ (Windows); check_architecture chỉ còn violation cũ JSDom.swift.

## [1.3.1105] - 2026-11-27

### feat: màn duyệt name giữ đầu thẻ, ô tìm và chip loại dính trên cùng khi cuộn

Plan 2026-11-27-phan-loai-name mục L14 (anh Bửu: "các chip và search hiển thị kiểu sticky để scroll xuống vẫn thấy"),
mockup https://claude.ai/artifact/9qgrqxGZpkiCQHQdK4vgbx khung "Màn duyệt — cuộn xuống".

- ReaderAINameReviewCardView: cả thẻ thành một LazyVStack(pinnedViews: [.sectionHeaders]) với một Section; đầu thẻ
  (Tên riêng (N), menu sắp xếp, Chọn hết / Bỏ chọn) + ô tìm + hàng chip loại là tiêu đề section (stickyHeader), cuộn
  xuống vẫn nằm trên cùng vùng cuộn của sheet. Luồng AI không có chip ⇒ dính đầu thẻ + ô tìm.
- Tiêu đề tô nền đặc bằng nền thẻ (cardBackground, tô sau đệm nên phủ cả dải 12 pt phía trên): hàng cuộn qua bên dưới
  không lộ chữ. Lề trên của thẻ dời vào tiêu đề; không đổ bóng lúc dính (đo vị trí cần onGeometryChange — iOS 18).
- Hành vi lọc / chọn giữ nguyên: ô tìm + chip chỉ ẩn hàng, Chọn hết / Bỏ chọn theo mục đang hiện, Lưu lưu mọi mục đang
  chọn; sheet giữ scrollDismissesKeyboard. Thẻ phải là con trực tiếp của ScrollView của ReaderAINameReviewSheet.

Chưa biên dịch được tại chỗ (Windows); check_architecture chỉ còn violation cũ JSDom.swift.

## [1.3.1104] - 2026-11-27

### feat: lọc name local có danh sách họ riêng, thêm họ 洛 và 玉, chép một lần họ đã sửa ở danh sách họ của rule dịch nhanh

- Danh sách họ riêng của Lọc name local (L13, plan 2026-11-27-phan-loai-name, anh Bửu: "Màn quản lý họ riêng cho lọc luôn"): bộ lọc **chỉ** đọc danh sách mới (`LocalNameFilterDictionaries.capture` ⇒ `QuickTranslationSurnameStore.nameFilter.lookupTable()`, đổi đúng một dòng); token `<ho>` của rule dịch nhanh giữ Danh sách họ cũ ⇒ hai danh sách độc lập, sửa bên nào không đổi bên kia.
- Dùng lại store, không chép code: `QuickTranslationSurnameStore` nhận cấu hình `QuickTranslationSurnameStoreConfiguration` (tên file gốc, khoá `UserDefaults` lớp riêng, nhãn log, có đi vào bộ dịch không, chép một lần từ đâu). Bản gốc thành thuộc tính của từng bản (trước là `static let` dùng chung). `shared` = cấu hình `.quickTranslation` (`ChineseSurnames.txt`, `quickTranslateSurnameOverrides`, ghi vẫn dọn cache dịch + báo rule đổi) — hành vi như cũ. `nameFilter` = `NameFilterSurnames.txt` + khoá `localNameFilterSurnameOverrides` (chữ thường ⇒ `BackupSettingsArchiver` tự gói); ghi **không** dọn cache dịch / không báo rule đổi (danh sách không vào bộ dịch, như `LocalNameFilterSuffixStore`); có hiệu lực từ lần "Bắt đầu lọc" sau.
- File gốc mới `Sources/Resources/Translation/NameFilterSurnames.txt` = bản sao `ChineseSurnames.txt` (683 khoá) + `洛=Lạc`, `玉=Ngọc` cuối mục "Họ đơn bổ sung" ⇒ 685 khoá (585 đơn, 100 kép); chú thích đầu file ghi đúng vai trò. 洛 / 玉 không thuộc tập hư từ bộ lọc tự bỏ.
- Chép một lần (anh chọn "chép họ đã sửa"): lần đầu bản `nameFilter` được tạo (mở màn Họ hoặc lượt lọc đầu), nếu cờ `localNameFilterSurnameSeeded` chưa có ⇒ đặt cờ (cả khi không có gì để chép — "Khôi phục mặc định" sau này không làm chép lại); khoá lớp riêng của bộ lọc chưa có và lớp riêng của `<ho>` có ⇒ chép sang, áp lại lên bản gốc mới (`QuickTranslationSurnameOverrides.rebased(onto:)`: họ tự thêm trùng âm với bản gốc mới như 洛=Lạc không còn tính là phần sửa). Đặt trong `init` của store thay cho bootstrap lúc mở app: `static let` bảo đảm chạy một lần, an toàn luồng, trước mọi lượt đọc (kể cả từ task nền của bộ lọc), không đụng `FreeBookApp` / `MainTabView`. Cờ chữ thường ⇒ Backup gói cùng lớp riêng. Log `📋 [NameFilterSurname]`.
- Màn quản lý: `QuickTranslationSurnameListView` nhận `Context` (store, tiêu đề, tên file xuất, dòng "?", chữ khi trống; mặc định `.quickTranslation` ⇒ hai chỗ mở cũ không đổi); `QuickTranslationSurnameEditorSheet` nhận `store` (trùng khoá xét đúng danh sách đang sửa). View mới `LocalNameFilterSurnameListView()` (`Views/Reader/NameFilter/Lists/`, tiêu đề "Họ", xuất `NameFilterSurnames.txt`, đủ Sửa từ / nhập file 3 cách / xuất / khôi phục mặc định / tắt / xoá) để session giao diện nối hàng "Họ" vào sheet Lọc name local — sheet chưa có hàng này.
- `check_architecture.py` chỉ còn violation cũ `JSDom.swift`. Chưa biên dịch được tại chỗ (Windows); chưa thử trên máy.

## [1.3.1103] - 2026-11-27

### feat: lọc name local sửa phân loại, hậu tố Nhân danh thay Pronouns, tiền tố cho tên Latin, lọc độ dài name

Phần lõi của plan Docs/Plans/2026-11-27-phan-loai-name.md (anh Bửu duyệt): L1–L6, L7 / L10 (engine + store), L9, L11,
L12 (dữ liệu), L15 (engine). Giao diện (Views) để session sau. Bản tham chiếu Python
Docs/Plans/local-name-filter-lac/lacpipe.py + name_meaning.py sửa trước (bản cũ *_before_phanloai.py), chạy 11 truyện.

Phân loại phía LAC (LocalNameFilterLACPipeline+Kind, file mới):
- L11: hậu tố Nhân danh 2–6 chữ của bản gốc vào bộ dò phía LAC ⇒ name có hậu tố đó là Nhân danh (天元圣女 →
  "Thiên Nguyên thánh nữ"). Luật (e) và bộ luật không dùng hậu tố Nhân danh.
- L1 / L2: LAC bảo người + chữ cuối là đuôi yếu phía LAC (bộ cũ + 卫 泽) ⇒ theo hậu tố khi nhãn thường nhiều hơn nhãn
  thực thể (không mở đầu bằng họ, không danh xưng) hoặc ≥ 3 chữ không mở đầu bằng họ (玄剑峰, 执事堂, 魔渊); 刘云峰,
  楚渊, 王精卫 vẫn là người.
- L3: chữ cuối là loài vật / yêu ma ⇒ Thuật ngữ (蜃龙, 啸月银狼), trừ mở đầu bằng họ / 阿 / 小 / có danh xưng.
- L4: nhãn thường ≥ 2 lần nhãn thực thể, không đuôi ⇒ Thuật ngữ (天君, 虚空乱流), trừ họ / danh xưng / 小 阿 老 đầu /
  儿 子 cuối.
- Bộ gắn nhãn đếm nhãn thường cho mọi từ ≥ 2 chữ có chữ Hán (trước chỉ từ ≥ 3 chữ có chữ cuối là đuôi); bỏ
  suffixLastScalars.
Lọc:
- L5 rank_prefix: số + 阶 / 级 / 品 ở đầu ⇒ bỏ, cả name đã có (九阶) và hàng bộ luật ở bước hợp.
- L9 glued_names: name chưa có = hai hàng Nhân danh khác của danh sách (mỗi phần ≥ 2 chữ) ⇒ bỏ (姬晴苟义).
- L15 length_off: Configuration.minLength (mặc định 2) / maxLength (nil = không giới hạn), đếm code point, không tính
  dấu ·, lọc ở đầu ra cả hai đường.
Bỏ Pronouns: LocalNameFilterDictionaries thôi chụp Pronouns; danh xưng của bộ luật (pronouns / titles) dựng từ hậu tố
Nhân danh của danh sách người dùng (cùng bộ lọc Config); glued_fragment giữ phần thừa là hậu tố ≥ 2 chữ mọi loại
(东阳酒店, 贝克兰德大学 nay được giữ); nghĩa tên người lấy hậu tố Nhân danh dài nhất (LocalNameFilterSetup.personTitle,
陈太上长老 ⇒ 太上长老), 1 chữ vẫn chỉ chữ thân tộc sau ≥ 3 tên. Bỏ hasPronouns, log "chưa nạp Pronouns".
Tiền tố (L7 / L10): LocalNameFilterPrefixStore mới (NameFilterPrefixes.txt: 老=lão, 小=tiểu, khoá
localNameFilterPrefixOverrides), dùng chung bộ máy với danh sách hậu tố qua lớp cha LocalNameFilterAffixListStore (lời
báo theo danh từ "Hậu tố" / "Tiền tố"). LocalNameFilterProperNames: mảnh mở đầu bằng tiền tố cùng nhóm loại, phần sau
ra tên Latin ⇒ "lão Kolle", "lão Wood", "tiểu Etter" (bật Latin); nghĩa cả mảnh "lão Neil" trong từ điển ⇒ nhận; 小鱼
老张 giữ Hán-Việt. Configuration.prefixes (mặc định rỗng — màn hình phải truyền allPrefixes()).
Gói tạm: signature tính cả tiền tố, canRecompose thêm tên người (danh xưng 1 chữ chỉ giữ khi nghĩa máy trước đã dùng),
Inputs.prefixes mặc định = danh sách hiện tại.
Dữ liệu: NameFilterSuffixes.txt thêm 渡 泽 (địa danh), 酒店 大学 司 卫 (tổ chức), 1.190 dòng Nhân danh từ
DuoiNhanDanh.de-xuat.txt; SuffixKind.person ("Nhân danh").

Đo 11 truyện (so với lượt Pronouns của anh): L1 13, L2 4, L5 13 khớp plan; L3 40 (二阶虎妖 nay bị L5 bỏ trước); L4 52
(镇魔司 → L6, 无量天君 → L11, 九阶 → L5, 金仙 mở đầu bằng họ); L6 đúng 6 hàng + bộ luật thêm 7 tổ chức (城卫司 巡检司…);
L9 thêm 唐三海神; L11 lật 26 hàng sang Nhân danh, có hàng nghi sai (新晋真传, 绝顶天骄, 魂斗罗…) — chi tiết ở ghi chú
bàn giao. Chưa biên dịch (Windows); Views còn một switch thiếu case .person (LocalNameFilterSuffixEditorSheet).

## [1.3.1102] - 2026-11-27

### fix: lọc name local không bật lại nhãn đoán, gói tạm chỉ ghép lại nghĩa khi danh sách đuôi đổi, lưu hai đuôi liền nhau không đè nhau

Gộp xong đợt "nghĩa tên tây huyễn" (1.3.1095–1101), rà soát chéo bằng hai agent (phần bộ lọc; màn duyệt + màn Sửa từ dùng chung): không thấy lỗi biên dịch, luồng AI và các chỗ dùng khác của màn Sửa từ giữ nguyên hành vi; sửa các lỗi tìm được.

- **Nhãn "đoán" không bật lại**: xác nhận nghĩa ở màn Sửa từ (bấm Cập nhật, nghĩa không đổi) bỏ cờ, nhưng lần ghép lại sau so cả cờ nên gắn lại nhãn và đếm dư vào toast. Nay màn duyệt (`LocalNameFilterReviewSuffixContext.recompose`) và gói tạm (`LocalNameFilterDraftRefresher`) chỉ đổi khi nghĩa đổi thật.
- **Gói tạm chỉ ghép lại khi có gì đổi**: gói nhớ dấu danh sách đuôi + công tắc Latin của lần ghép gần nhất (`LocalNameFilterDraft.meaningSignature`, `LocalNameFilterMeaningComposer.signature`); trùng dấu ⇒ bỏ qua. Trước đây mỗi lần trang đầu hiện ra, hàng bộ luật địa danh / tổ chức (lúc lọc lấy đúng đuôi đã dò) có thể tự đổi nghĩa theo đường ghép "đuôi dài nhất" dù không ai đổi gì; nay cũng ít khi giữ khoá kho gói lâu.
- **Lưu hai đuôi liền nhau** (nhất là lúc mô hình Latin đang tải lần đầu): các lượt ghép lại ở màn duyệt chạy lần lượt (`enqueueRecompose`), lượt sau đọc danh sách đã áp lượt trước; chỉ gộp khoá vừa đổi vào `autoMeanings`.
- **Đổi chữ của đuôi có sẵn** (chip ✓, 街 ⇒ 兰街): ghép lại cả name mang khoá cũ (`onSaved` báo thêm khoá bị thay).
- Họ tộc (萧家) không có hàng "Đuôi" (đuôi không bao giờ đổi nghĩa họ tộc). Lượt ghép lại xong muộn không ghi vào gói khác đang mở (gắn `draftId`). Thu một đuôi có sẵn thành đuôi mới ⇒ toast "Đã thêm".
- Tải mô hình Latin dùng phiên riêng có hạn tổng 30 s (`timeoutIntervalForResource`) — mạng nhỏ giọt không còn treo ở "Nạp model…".
- Comment: khoá đuôi 1–6 chữ (`LocalNameFilter.Suffix.key`), lúc tải mô hình Latin. Tài liệu `.claude/rules/translation.md` / `storage.md` / `books-sources.md` cập nhật cho cả đợt.
- Ghi nhận, chưa sửa (nhẹ): huỷ lúc đang tải mô hình Latin lần đầu không cắt ngay (cửa nạp là `Task.detached`); dòng "Ví dụ" khi sửa đuôi có sẵn qua chip ✓ dùng mẫu chung.
- `check_architecture.py` chỉ còn violation cũ `JSDom.swift`. Chưa biên dịch được tại chỗ (Windows); chưa thử trên máy.

## [1.3.1101] - 2026-11-27

### feat: thêm đuôi ngay từ màn sửa từ của màn duyệt lọc name local, đuôi dài 1 đến 6 chữ, ghép lại nghĩa ngay

- Đuôi dài 1–6 chữ (anh Bửu: "chọn đuôi thoải mái hơn"): luật khoá `LocalNameFilterSuffixListParser` nới từ 1–2 lên 1–6 chữ Hán cho danh sách người dùng (cả màn danh sách đuôi). Bộ dò cố định (file gốc, cách A) vẫn chỉ dùng đuôi 1–2 chữ. Ghép nghĩa lấy đuôi **dài nhất** khớp cuối name, phần tên riêng còn ≥ 1 chữ (安保公司 thắng 公司) — `LocalNameFilterSetup.meaningSuffix(of:)`, Python `suffix_of`. 10 truyện với danh sách mặc định ra y như trước (tắt và bật Latin).
- Màn Sửa từ mở từ màn duyệt (chỉ luồng Lọc name local, chỉ name không phải tên người) có hàng phụ **"Đuôi"** dưới aa…AA, nút "?" (`LocalNameFilterSuffixQuickRow`, plan 2026-11-27-nghia-ten-tay-huyen mục 7, mockup v4): cuộn ngang, đầu hàng là chip chọn nhanh = đoạn cuối 1, 2, 3 chữ của name (chừa ≥ 1 chữ trước, bỏ đoạn có chữ không phải Hán) `+ 街` `+ 兰街` `+ 特兰街`; đoạn đã là đuôi ⇒ chip "✓ 街 · phố · trước" chạm để sửa; cuối hàng nút "+ Thêm đuôi".
- Chip "+" / "+ Thêm đuôi" ⇒ `LocalNameFilterSuffixEditorSheet` chế độ thêm từ name (`Source`): mở với đúng đoạn đó hoặc **nguyên cụm** name, thu / nới bằng ‹ › của hàng chữ gốc, khoá lưu = phần đang chọn (luôn thêm mới); ô nghĩa = phiên âm viết thường của phần đang chọn, đã gõ thì giữ; Loại = loại của name, "Sau tên"; dòng "Ví dụ" dùng chính name; "Thêm" mờ + dòng nhắc khi chọn cả cụm ("Chừa ít nhất 1 chữ trước đuôi."), phần chọn không nằm cuối name, hoặc dài quá 6 chữ.
- Lưu đuôi (thêm hoặc sửa) ⇒ ghi qua `LocalNameFilterSuffixStore` như cũ ⇒ ghép lại nghĩa ngay các name trong màn duyệt đang mở: không phải người / họ tộc, kết thúc bằng đuôi đó, nghĩa vẫn do máy ghép (`autoMeanings`) — bằng đúng bộ ghép nghĩa của bộ lọc với danh sách đuôi hiện tại + công tắc Latin (`LocalNameFilterReviewSuffixContext`); nghĩa tự sửa giữ nguyên; ô nghĩa của màn Sửa từ theo nếu chưa gõ khác; gói tạm mang nghĩa máy ghép mới; toast "Đã thêm đuôi 街 · ghép lại N name".
- Màn Sửa từ dùng chung (`DictEntryEditSheet`) thêm móc mặc định không đổi hành vi chỗ khác: `initialSelection`, `accessoryRows` (chế độ từ điển), `followsOriginalValue`; `DictEntryEditListMode.addsFromSource` + `suggestedMeaning`. `LocalNameFilterSuffixStore.suggestedMeaning(for:)` = phiên âm viết thường.
- Chưa biên dịch (máy Windows), chưa thử trên máy.

## [1.3.1100] - 2026-11-27

### fix: lọc name local siết luật ghép mảnh từ điển, tập chữ phiên âm đóng trong app dùng ở mọi chế độ

- Mọi mục từ điển dùng làm **một phần** của nghĩa — cả mảnh (phần riêng trước đuôi / danh xưng, mảnh tách theo `·`) và mục ghép khi phủ trọn — chỉ được nhận khi nghĩa chọn là (a) kiểu tên Hán-Việt: không phải chữ Latin, viết hoa chữ đầu mọi từ ("Đông Khu"); hoặc (b) chữ Latin mà khoá có ≥ 1 chữ thuộc tập chữ phiên âm (`LocalNameFilterProperNames.coverEntry` / `hasTranslitChar`). Không đạt ⇒ về Hán-Việt như cũ. Đường "cả từ có trong từ điển" giữ nguyên (图铎 đứng một mình vẫn ra Tudor). Bỏ ca lạ ở truyện Trung: 炎珠草 "Viên viêm châu thảo" ⇒ "Viêm Châu thảo", 黑礁岛 không còn ra "Black Lagoon đảo".
- Ngưỡng (b) là **≥ 1 chữ**, không phải ≥ nửa (session chính chọn): tập 268 chữ thiếu nhiều chữ phiên âm thông dụng như 戴 里 图 铎, ngưỡng ≥ nửa làm hỏng 戴里克 Derrick, 所罗门 Solomon, 查拉图 Zaratul. Chọn nghĩa Latin (`pick`) và đoán tên khi bật "Ưu tiên tên Latin" vẫn dùng ngưỡng ≥ nửa.
- Tập chữ phiên âm đóng trong app: `Sources/Resources/Translation/NameFilterTranslitChars.txt` (268 chữ, đúng `translitChars` của `translit_latin.json` @ HF `0df8c84a`), đọc một lần qua `LocalNameFilterTranslitChars`, dùng ở **mọi** chế độ kể cả tắt Latin (cách C) — giữ được Backlund Đông Khu, Russel đại đế, Derrick Berg khi tắt Latin. `translitChars` trong file mô hình chỉ để đối chiếu: lệch ⇒ log ❌ (`LocalNameFilterLatinModelGate`).
- Python tham chiếu `name_meaning.py` sửa trước (`cover_entry`, `has_translit_char`, `load_translit_chars`); 10 truyện giữ y hàng. Với VP của anh, so với trước, đổi 8 hàng (tắt và bật Latin như nhau): 炎珠草 (sửa đúng), 图铎家族 / 图铎王朝 Tudor ⇒ Đồ Đạc, 水仙花街 "Thủy Tiên Hoa nhai", 沐氏家族 "Mộc Thị gia tộc", 天元圣女 "Thiên Nguyên Thánh Nữ", 天使神神位 "Thiên Sử Thần Thần Vị", 剑道·君亭 "Kiếm Đạo Quân Đình".
- Comment `LocalNameFilter.Suffix`: danh sách đuôi chỉ để ghép nghĩa (không còn "đuôi đang bật").
- Chưa biên dịch (máy Windows), chưa thử trên máy.

## [1.3.1099] - 2026-11-27

### feat: gói name tạm tự cập nhật theo danh sách đuôi và danh sách không phải name

- Gói tạm của Lọc name local nhớ thêm `autoMeanings` (chữ Hán ⇒ nghĩa máy ghép + loại, lúc lọc hoặc lần cập nhật trước; plan 2026-11-27-nghia-ten-tay-huyen mục 6). Trường tuỳ chọn: gói cũ chưa có ⇒ không ghép lại nghĩa. Màn duyệt mang theo qua `ReviewContext` (lọc xong, mở lại gói, ghi gói).
- Mỗi lần trang đầu "Lọc name local" hiện ra (mở sheet, quay lại từ màn danh sách, bấm ‹ ở màn duyệt), `LocalNameFilterDraftRefresher` cập nhật các gói của truyện đang mở ngoài main: bỏ name nằm trong "Không phải name" (xoá cụm khỏi danh sách thì name đã bỏ không quay lại; gói hết name ⇒ xoá gói); địa danh / tổ chức / thuật ngữ mà nghĩa đang có bằng nghĩa máy ghép ⇒ ghép lại bằng đúng bộ ghép nghĩa của bộ lọc với danh sách đuôi hiện tại + công tắc "Ưu tiên tên Latin" của truyện (cập nhật nghĩa, `autoMeanings`, cờ đoán); nghĩa đã tự sửa giữ nguyên; người / họ tộc không ghép lại. Bật Latin mà thiếu mô hình ⇒ lần đó không ghép lại.
- `LocalNameFilterMeaningComposer`: ghép nghĩa một name lẻ (chụp từ điển của truyện) bằng `LocalNameFilterMeaningBuilder` đường hàng LAC. `LocalNameFilterDraftStore.update`: đọc – sửa – ghi trong một lần giữ khoá, không đổi thì không ghi, `savedAt` giữ nguyên.
- Nút "?" của mục "Gói tạm chưa lưu" thêm đoạn giải thích việc tự cập nhật. Log `🔎 [LọcName] Cập nhật gói tạm: bỏ N name…, ghép lại M nghĩa…`.
- Chưa biên dịch (máy Windows), chưa thử trên máy.

## [1.3.1098] - 2026-11-27

### feat: màn duyệt của lọc name local có nút quay lại, giữ danh sách thành gói tạm rồi về trang lọc

- Màn "Duyệt tên riêng & VP" của luồng Lọc name local có nút ‹ ở header (plan 2026-11-27-nghia-ten-tay-huyen mục 5): `ReaderAINameReviewSheet` nhận `onBack` tuỳ chọn ⇒ `HeaderBackButton` + tiêu đề ngay cạnh (`PageTitleModifier` kiểu `.centered` đọc `\.sheetPageBack`, đặt ngoài `NavigationStack`). Luồng AI không truyền ⇒ header như cũ; sheet Sửa từ mở từ màn duyệt nhận lại giá trị `\.sheetPageBack` kế thừa nên không có nút ‹ lạ.
- Bấm ‹ ⇒ `LocalNameFilterSession.leaveReview`: giữ danh sách đang duyệt thành gói tạm bằng đúng hàm lúc đóng sheet (`keepDraftOnClose`), không toast, rồi về trang đầu "Lọc name local" — sheet không đóng, mục "Gói tạm chưa lưu" hiện ngay (trang đầu nạp lại gói khi hiện ra). Đóng sheet sau đó không ghi gói lần nữa.
- Chưa biên dịch (máy Windows), chưa thử trên máy.

## [1.3.1097] - 2026-11-27

### feat: lọc name local lấy nghĩa theo từ điển, danh sách đuôi chỉ để dịch nghĩa, công tắc ưu tiên tên Latin theo truyện có mô hình đoán tên

- Nghĩa đề xuất theo từ điển (plan 2026-11-27-nghia-ten-tay-huyen mục 2, mọi truyện): cả từ có trong Name 3 lớp rồi VP 3 lớp với nghĩa viết hoa ⇒ lấy nghĩa đó (克莱恩 ⇒ Klein); không có ⇒ bóc danh xưng / đuôi như cũ, phần tên riêng tách theo `·` `.` `•`, mỗi mảnh: cả mảnh trong từ điển ⇒ nghĩa đó, phủ trọn bằng mục ≥ 2 chữ ⇒ ghép (罗塞尔大帝 ⇒ Russel đại đế, 戴里克.伯格 ⇒ Derrick Berg), còn lại ⇒ Hán-Việt như cũ (họ theo Danh sách họ). Name không phải người có đuôi: thử phủ trọn cả từ khi mục cuối dài hơn đuôi (贝克兰德东区 ⇒ Backlund Đông Khu), không được mới bóc đuôi. Nghĩa đầu viết thường (hàng luật (e)) không lấy. Mới: `LocalNameFilterProperNames` (nhớ kết quả cả lượt), `LocalNameFilterDictionaries.dictionaryValue`.
- Danh sách "Đuôi địa danh, tổ chức, thuật ngữ" chỉ để dịch nghĩa (cách A, anh Bửu): mọi đuôi trong danh sách ghép nghĩa name không phải tên người, kể cả 观 花 区 (玄真观 ⇒ Huyền Chân quán); dò ứng viên / luật / phân loại / chữ cuối của bộ gắn nhãn dùng bộ cố định `LocalNameFilterSuffixStore.detectionSuffixes` = file gốc trừ dòng `|off`, không theo danh sách người dùng ⇒ cấu hình mặc định ra đúng số name như trước (10 truyện, so từng hàng). Bỏ bật / tắt: nút ⏸ và chữ "đang tắt" ở màn danh sách, `setEnabled`, trường `enabled` của lớp ghi đè (đọc vào thì bỏ qua, `format` 3), `bundledOffLater`. `|off` trong file gốc nay nghĩa là "không dùng để dò".
- Công tắc "Ưu tiên tên Latin" ở mục Tuỳ chọn của sheet Lọc name local (nút "?", mặc định tắt), nhớ theo truyện ở `UserDefaults` `localNameFilterLatinByBook` (`LocalNameFilterLatinPreferenceStore`); đổi nguồn chép (đích có giá trị riêng thì giữ), xoá truyện thì xoá. Bật ⇒ mảnh trông như phiên âm (≥ nửa số chữ thuộc tập chữ phiên âm) lấy nghĩa chữ Latin đầu tiên trong từ điển (班森 ⇒ Benson); mảnh phiên âm không có trong từ điển ⇒ mô hình đoán (伽罗斯 ⇒ Garos, 霍尔登帝国 ⇒ Holden đế quốc), ít nguyên âm quá thì bỏ; tên đoán gắn `Name.isGuessedMeaning`, chép sang `AIExtractedName.isGuessedMeaning`.
- Mô hình đoán tên `translit_latin.json` (~155 KB) ghim commit + sha256 + kích thước trên kho HF `raikiri1498/vietpharse` (`LocalNameFilterLatinModelStore`), chỉ tải khi một lượt bật công tắc mà máy chưa có, vào `translate/LAC/`; `LocalNameFilterLatinModelGate` gộp lượt nạp trùng, giữ mô hình yếu; bộ giải mã `LocalNameFilterLatinModel` đúng SPEC của `Tools/lac-export/export_translit.py` (chùm 16, LM chữ cái bậc 3, hoà điểm giữ thứ tự sinh). Tải / đọc lỗi ⇒ log ❌, vẫn lọc như tắt công tắc.
- Log `🔎 [LọcName] Xong…` thêm "Latin bật · đoán N" / "Latin bật nhưng thiếu mô hình".
- Bản tham chiếu Python (`name_meaning.py`, `lacpipe.py` cách A, `compare_meaning.py`): 10 truyện giữ y hàng (chữ Hán, loại, số lần, đã có); với VP của anh đổi nghĩa 诡秘之主 239 / 374 (+45 khi bật Latin, 16 đoán), 巫师 24 / 50 (+10), 以一龙之力 15 / 40 (+11), Naruto 50 / 74 (+3), Sư muội 40 / 268, Đấu La 124 / 655. Bộ giải mã Python khớp `Model.predict` của công cụ học 6000 / 6000 mục VP.
- Chưa biên dịch (máy Windows), chưa thử trên máy.

## [1.3.1096] - 2026-11-27

### feat: màn duyệt name có ô tìm chữ Hán hoặc nghĩa, kiểu sắp chưa có trước và nhãn đoán

Phần màn duyệt của đợt "nghĩa tên tây huyễn" (anh Bửu duyệt 2026-11-27, plan `Docs/Plans/2026-11-27-nghia-ten-tay-huyen.md` mục 4, mockup https://claude.ai/artifact/UjY2CA9eEaThdo96xSgoiz khung 2). Anh: "danh sách name kết quả đang thiếu ô tìm kiếm"; về thứ tự: không phải "chưa chọn lên trước" mà là name **chưa có** trong VP / Name lên trước (đã yêu cầu nhầm ở 1.3.1092).

- **Ô tìm** ở `ReaderAINameReviewCardView` (cả luồng lọc name local lẫn luồng AI), nằm trên hàng chip loại: khớp chữ Hán hoặc nghĩa, không phân biệt hoa thường, bỏ dấu, `đ` → `d` (gõ "klein" ra Klein, "khac" ra Khắc); kết hợp với chip loại; không còn mục nào ⇒ dòng "Không có name khớp"; nút ⓧ xoá chữ; kéo danh sách là hạ bàn phím (`scrollDismissesKeyboard(.interactively)`), vùng cuộn tự co theo bàn phím.
- **"Chọn hết" / "Bỏ chọn" áp lên mục đang hiện** (sau ô tìm + chip loại) — trước đây chip loại tính cả danh sách. Hàng gạch của luồng AI vẫn không chọn được. Ô tìm / chip chỉ ẩn hàng: số ở tiêu đề thẻ, số trên chip và nút Lưu vẫn tính cả danh sách; Lưu lưu mọi mục đang chọn, kể cả mục đang bị ẩn.
- **Kiểu sắp "Chưa có trước"** (`SortMode.notInDictionaryFirst`, chip "Chưa có") thay hẳn "Chưa chọn trước" (`unselectedFirst`, 1.3.1092): name không có badge NE / VP (`!(hasInBookNames || hasInBookVP)`) lên đầu, mỗi nhóm số lần giảm dần, hoà thì chữ Hán tăng dần — vd 炽翎 735 → 赤玄子 43 → 李印生 (NE) 4284 → 穆小鱼 (NE) 1287. Mặc định của luồng lọc local, kể cả khi mở lại gói tạm; menu còn "Nhiều lần nhất", "Đã chọn trước", "A → Z". Danh sách chỉ sắp lại lúc mở màn hoặc khi chọn ở menu. Luồng AI giữ "Đã chọn trước".
- **Nhãn "đoán"**: `AIExtractedName.isGuessedMeaning` ⇒ nhãn nhỏ viền vàng cạnh badge loại / NE / VP (`ReaderAINameReviewBadges`). Bấm "Cập nhật" ở màn Sửa từ ⇒ mục mang khoá đích bỏ cờ (`ReaderAINameReviewSheet+Edit.applyEdit`, ghi `names` một lần); chọn một phần thành mục mới thì mục gốc giữ cờ. Cờ đi theo gói tạm qua `AIExtractedName` (Codable).
- Thẻ tách thành `ReaderAINameReviewCardView+Sorting.swift` (kiểu sắp, menu ⇅) và `+Filtering.swift` (ô tìm, phần đang hiện, "Chọn hết") để giữ dưới 400 dòng.
- `check_architecture.py` chỉ còn violation cũ `JSDom.swift`. Chưa biên dịch được tại chỗ (Windows); chưa thử trên máy.

## [1.3.1095] - 2026-11-27

### refactor: hợp đồng lọc name local có cờ nghĩa do máy đoán, công tắc ưu tiên tên Latin và công cụ học mô hình đoán tên

Bước đầu của đợt "nghĩa tên tây huyễn" (anh Bửu duyệt 2026-11-27, plan `Docs/Plans/2026-11-27-nghia-ten-tay-huyen.md`, mockup https://claude.ai/artifact/UjY2CA9eEaThdo96xSgoiz): chốt kiểu chung trước để hai phần (nghĩa + đuôi + công tắc Latin; ô tìm + nhãn "đoán" ở màn duyệt) làm song song.

- `AIExtractedName.isGuessedMeaning` (mặc định `false`, chỉ ghi JSON khi bật — tin nhắn AI cũ, gói tạm đọc được như cũ).
- `LocalNameFilter.Name.isGuessedMeaning`, `Configuration.prefersLatinNames` ("Ưu tiên tên Latin", theo truyện); ghi rõ `Configuration.suffixes` từ nay **chỉ** để ghép nghĩa (cách A).
- `Tools/lac-export/export_translit.py`: học mô hình phiên âm ngược Hán → Latin từ VietPhrase (54.722 cặp tên, EM theo đoạn 1–4 chữ cái + mô hình chữ cái bậc 3), xuất `translit_latin.json` (155 KB) kèm đặc tả bộ giải mã. Bài thi 10 %: đúng y hệt 13 %, sai ≤ 1 chữ cái 36 %. Bộ giải mã độc lập đọc JSON trùng 3000 / 3000 dự đoán. Đã đẩy lên `datasets/raikiri1498/vietpharse` `lac/translit_latin.json`, commit `0df8c84a`.
- Commit này một mình chưa dùng các trường mới; hai phần sau của đợt bổ sung.

## [1.3.1094] - 2026-11-27

### feat: token <m> ghép chữ theo luật, xét vị trí trong bản dịch để nhận chữ số và đọc 十 là mười, 千 đọc ngàn

Anh Bửu (cùng đợt 1.3.1093): "các token số như vạn ức, ngàn vạn chưa chính xác"; về phạm vi `<m>`: "nếu `<m>` là token thứ 2 trở đi … chỉ nhận 十, 百, 千, 万, 十万", rồi "nếu giá trị thay thế đứng đầu mới đọc là mười" và chọn "dùng chung" một tiêu chí; 千 đọc "ngàn".

- `QuickTranslationMagnitudeFormatter` bỏ bảng tay: cụm = [một chữ số] + bậc tăng dần (十 < 百 < 千 < 万 < 亿 < 兆), ≤ 4 chữ; 廿 卅 卌 đứng riêng. Thêm được 万亿 (vạn ức), 两亿…九亿, 四十亿, 三百亿, 三千亿, 十万亿, 千万亿, 十兆 — trước đây rule có `<m>` không khớp các cụm này (vd 数万亿年 ra "mấy 100010000 năm", nay "mấy vạn ức năm"). 万万, 亿万 vẫn không nhận (thành ngữ).
- **Tiêu chí vế phải** thay luật vế trái của 1.3.703: `{i}` của `<m>` đứng đầu bản dịch ⇒ nhận cả chữ số đầu và 十 đọc "mười" (`<m>几 = {0} mấy`: 十几 = mười mấy, 二十几 = hai mươi mấy; `百分之<m>几 = {0} mấy phần trăm`: 百分之十几 trước ra "mươi mấy phần trăm" nay "mười mấy"); không đứng đầu ⇒ chỉ bậc trần (`数<m>年`: 之数五万年 trước "mấy năm vạn năm", nay để `<n:1-5>万年` ra "5 vạn năm").
- 十 trần đứng trước 万 / 亿 nằm ở chữ cố định ngay sau token cũng đọc "chục": `数<m>万年` trên 数十万年 trước "mấy mươi vạn năm", nay "mấy chục vạn năm".
- 千 đọc **ngàn** (trước "nghìn"): 数千年 = mấy ngàn năm, 几百上千 = mấy trăm đến mấy ngàn.
- `leadsPattern` đổi tên `leadsReplacement`; `markLeadingMagnitude` xét `template`. Hướng dẫn viết rule sửa hai dòng `<m>`; `translation.md` thêm đoạn "Token `<m>` ghép chữ".
- Đo trên 6 truyện cùng bộ rule của anh (bản chép Python, gộp cả 1.3.1093): 83 / 3.387 đoạn đổi = 69 đoạn chỉ nghìn → ngàn + 14 đoạn đúng hơn, không đoạn nào hỏng. Sau đợt này anh bỏ được 40 dòng rule mà kết quả không đổi (danh sách ở `Docs/Plans/token-so-lon/remove2_out.txt`, gồm `万万 = 万万`, `亿万 = 亿万`, `千千万万 = 千千万万`, `数<m>万年`…); Javis không sửa file rule của anh.
- `check_architecture.py` chỉ còn violation cũ `JSDom.swift`. Chưa biên dịch được tại chỗ (Windows); chưa thử trên máy.

## [1.3.1093] - 2026-11-27

### fix: token <n> đọc đúng bậc chồng 万亿, không nhận 万万 千千 亿万 là số, không bắt giữa số Ả Rập, danh sách 三、四千 mượn bậc

Anh Bửu: "các token số như vạn ức, ngàn vạn, chưa chính xác", "vạn vạn thật ra không phải số vẫn bị nhận là số", "kiểm tra kỹ xem". Plan `Docs/Plans/2026-11-27-token-so-lon.md` (anh duyệt); đo bằng bản chép Python của engine trên 6 truyện + bộ 537 rule anh gửi (`Docs/Plans/token-so-lon/`).

- **Đọc số:** `QuickTranslationNumberFormatter.parseChineseNumeral` tách theo bậc lớn nhất (lần cuối), vế trái **nhân** bậc: 万亿 / 一万亿 = 1000000000000 (trước 100010000), 三千万亿 = 3·10¹⁵, 三万五千亿 = 3500000000000, 两万万 = 200000000 (trước 30000). Viết tắt 三万五, 两千五, 十万八 giữ nguyên.
- **Cụm không phải số:** matcher ghép phần token bắt với chữ số liền kề trong chữ cố định của rule rồi kiểm (`QuickTranslationNumeralShape`): 万万, 千千, 亿亿, 亿万, 万千, 千百, 兆 đứng đầu, 一一, 万一 không còn là số. Ví dụ 他万万年 trước ra "10000 vạn năm" ⇒ rule `万万 = 万万` của anh thắng; 千岁,千千岁 hết ra "2000 tuổi"; 征兆, 沈兆日后 hết ra "1000000000000".
- **Hai luật kèm:** sau chữ cố định là bậc thì số kế tiếp phải nhỏ hơn bậc đó (`<n>万<n>年` không còn tách 一万亿年 thành "1 vạn 100000000 năm"); bậc trần ngay sau 几 / 数 không bị `<n>` bắt riêng (两千几百人 hết "… mấy 100 người", 十几万两银子 hết "mười mấy 10000 lượng").
- **Số Ả Rập:** token đứng đầu mẫu không bắt đầu giữa số Ả Rập — 3千年修为, 5千万人口, 1.5万人, 2.5亿年 hết ra "3 1000 năm", "1. 50000"; phần đó để rule `<d>…` hoặc VietPhrase.
- **Danh sách:** `<n>,<n>` / `<n>、<n>`: số trước là một chữ số trần thì mượn bậc của số sau — 八,九万年 ra "80000, 90000 năm" (trước "8, 90000"), 三、四千年 ra "3000, 4000 năm".
- `walkNumeral` dời sang `QuickTranslationRuleMatcher+Numeral.swift` (file gốc 387 → 298 dòng); compiler gắn `numeralUnitsBefore/After`, `isPatternHead`, `numeralListPairs` (`QuickTranslationRuleCompiler+NumeralNeighbours`). Hướng dẫn viết rule thêm hai dòng về `<n>`; `translation.md` thêm đoạn "Token số lớn".
- Đo trên 6 truyện (3.387 đoạn có số lớn): chỉ các đoạn sai đổi, không đoạn nào hỏng; 十万年 (274 lần), 两万四千年, 十万八千年 giữ nguyên. Còn cần rule giữ chữ của anh: 百转千回, 成千上万, 万人之上, 千岁 (tước hiệu), 千万 (code không phân biệt 千万不要 với 千万人).
- `check_architecture.py` chỉ còn violation cũ `JSDom.swift`. Chưa biên dịch được tại chỗ (Windows); chưa thử trên máy.

## [1.3.1092] - 2026-11-27

### feat: màn duyệt của lọc name local mặc định xếp mục chưa chọn lên đầu, mỗi nhóm theo số lần xuất hiện

Anh Bửu: "sắp xếp mặc định theo chưa chọn lên trước và theo số lần xuất hiện" (xác nhận cách hiểu 2026-11-27).

- Kiểu sắp mới `ReaderAINameReviewCardView.SortMode.unselectedFirst` ("Chưa chọn trước", chip "Chưa chọn"): mục chưa chọn — chủ yếu name đã có NE / VP bị bỏ chọn sẵn — lên đầu, mỗi nhóm số lần giảm dần, hoà thì theo chữ Hán. Ví dụ 李印生 (NE, 4284) → 穆小鱼 (NE, 1287) → 炽翎 (735) → 赤玄子 (43).
- Là mặc định của luồng lọc local (kể cả mở lại gói tạm); menu vẫn có "Nhiều lần nhất", "Đã chọn trước", "A → Z". Danh sách chỉ sắp lại lúc mở màn hoặc khi chọn ở menu — tích / bỏ tích một ô không làm hàng nhảy chỗ.
- Luồng AI giữ nguyên ("Đã chọn trước", menu cũ). Bốn mục menu dựng bằng một hàm chung `sortMenuButton`.
- `check_architecture.py` chỉ còn violation cũ `JSDom.swift`. Chưa biên dịch được tại chỗ (Windows); chưa thử trên máy.

## [1.3.1091] - 2026-11-27

### fix: lọc name local giữ model khi chỉ lỗi đọc file, bộ luật bỏ dòng tên chương như bản Python, sửa loại đuôi 花 không tự bật

Anh Bửu: "sửa luôn mấy lỗi nhẹ còn lại đi" — bốn lỗi nhẹ ghi nhận ở 1.3.1090.

- **Lỗi đọc file model thoáng qua không còn xoá cả model**: thêm `LACModelError.readFailed` ("Không đọc được model nhận diện tên…", có "Thử lại"). Kiểm sha256 (`LACModelStore.verifyChecksums`), đọc file khi nạp (`LACTagger.load`) và đọc mẫu đối chiếu mà lỗi I/O ⇒ `readFailed`, **giữ** thư mục; chỉ sha lệch / sai định dạng (`invalidFiles`) mới xoá để tải lại 19 MB. Bộ lọc xử lý `readFailed` như hai lỗi kia (sự kiện `.failed`).
- **Bộ luật bỏ dòng tên chương** (`第N章…`) trước khi đếm, như `split_chapters` của bản Python (`LocalNameFilterLACChapterTagger.removingChapterHeadings`, dùng chung hàm nhận dạng của phía LAC) — số lần / mảnh / `dict_common_head` khớp bản tham chiếu cả khi nội dung chương có dòng tên chương. Chương không có dòng nào như vậy ⇒ chữ giữ nguyên.
- **Sửa loại của đuôi gốc 花 không làm công tắc tự bật**: lớp riêng danh sách đuôi có trường `format` (2). Dữ liệu cũ (`format` vắng) đọc vào thì ghi rõ `enabled = true` cho 花 người dùng đã tự thêm từ trước (giữ bật như cũ); mặc định bật / tắt từ nay chỉ theo cờ `|off` của bản gốc.
- **`Name.chapterCount`**: không màn hay luật nào dùng ⇒ không tốn công đếm lại trên chữ từng chương; ghi rõ nghĩa (hàng LAC = số chương LAC gắn nhãn thực thể; hàng bộ luật = số chương sinh ứng viên).
- `translation.md`: ghi `readFailed` và việc bỏ dòng tên chương. `check_architecture.py` chỉ còn violation cũ `JSDom.swift`. Chưa biên dịch được tại chỗ (Windows); chưa thử trên máy.

## [1.3.1090] - 2026-11-27

### fix: lọc name local xoá gói tạm khi xoá truyện, Dừng được lúc đang tải model, toast gói tạm chỉ hiện khi đóng sheet thật

Gộp nhánh của đợt "Lọc name local bằng LAC" (1.3.1082–1089) xong, rà soát chéo bằng hai agent (Services: model LAC + bộ lọc; giao diện + gói tạm): không thấy lỗi biên dịch chắc chắn, hợp đồng giữa ba nhánh khớp; sửa các lỗi tìm được.

- **Xoá truyện xoá luôn gói name tạm**: `BookStorageManager.deleteBookSideData` gọi `LocalNameFilterDraftStore.deleteAll` (lỗi ⇒ hàng đợi xoá lại, như ghi chú / dấu trang). `deleteAll` dọn cả bản `.broken-…` đã cất của truyện đó (Dọn rác cố ý bỏ qua các file này).
- **"Dừng" lúc đang tải / nạp model**: trước phải chờ tải hết ~19 MB + tự kiểm mới dừng (bộ lọc chỉ xét "Dừng" trong vòng đọc chương) ⇒ nay huỷ ngay, về bước chọn với dòng "Đã dừng khi đang chuẩn bị model nhận diện tên".
- **Toast "Đã giữ gói tạm" chỉ khi sheet đóng thật**: `onDisappear` còn chạy khi sheet chỉ bị màn toàn màn che (màn Sửa từ mở tra cứu ngoài) ⇒ gói vẫn ghi (ghi đè cùng gói), toast chỉ hiện khi `isPresented == false`.
- **Dòng "Nạp model…" thôi quay suốt khối 24 chương đầu**: bộ lọc phát `.progress(0, tổng)` ngay khi model xong.
- Comment / tài liệu: tên mới "đuôi địa danh, tổ chức, thuật ngữ"; `.claude/rules/translation.md` (bản LAC: hai chế độ, model `NER/`, chip loại, gói tạm), `storage.md` (`name_filter_drafts/`, `translate/LAC/`), `books-sources.md`, `ui-conventions.md`.
- Ghi nhận, chưa sửa (nhẹ): lỗi đọc file model thoáng qua cũng xoá cả model (lần sau tải lại); `chapterCount` của hàng LAC chỉ đếm chương LAC gắn nhãn thực thể; số lần phía bộ luật tính cả dòng `第N章` nếu nội dung chương có; sửa loại của đuôi gốc 花 thì công tắc tự bật.
- `check_architecture.py` chỉ còn violation cũ `JSDom.swift`. Chưa biên dịch được tại chỗ (Windows); chưa thử trên máy.

## [1.3.1089] - 2026-11-27

### fix: lọc name local thôi nghe bộ lọc ngay sau sự kiện cuối để Thử lại không bị lượt cũ ghi đè

## [1.3.NNN] - 2026-11-27
### fix: lọc name local thôi nghe bộ lọc ngay sau sự kiện cuối để Thử lại không bị lượt cũ ghi đè
- `LocalNameFilterSession.start`: vòng nghe sự kiện thoát ngay sau `.finished` / `.failed`. Trước đó nếu stream của bộ lọc đóng trễ mà người dùng đã bấm "Thử lại", task của lượt cũ tới bước "Bộ lọc dừng mà không báo kết quả" và đẩy lượt mới sang màn lỗi.

## [1.3.1088] - 2026-11-27

### feat: lọc name local chọn loại cần tìm, chip lọc loại và badge NE/VP ở màn duyệt, bước tải model và gói tạm khi đóng chưa lưu

## [1.3.NNN] - 2026-11-27
### feat: lọc name local chọn loại cần tìm, chip lọc loại và badge NE/VP ở màn duyệt, bước tải model và gói tạm khi đóng chưa lưu

Phần giao diện của đợt "Lọc name local bằng LAC" (plan `Docs/Plans/2026-11-27-loc-name-lac.md` mục E, E2 và bước 0; mockup https://claude.ai/artifact/Tx6oQ2Xd7KeaEybnnZ3cQq khung 1–5).

- **Loại cần tìm** (sheet thiết lập): 4 chip Nhân danh / Địa danh / Tổ chức / Thuật ngữ có chấm màu, mặc định bật cả 4, không tắt được chip cuối; nhớ bằng `@AppStorage` `localNameFilterCategories` (rawValue nối phẩy, rỗng = cả 4) ⇒ `Configuration.categories`. Nút "?" giải thích. Màu nhóm ở một chỗ `LocalNameFilterCategoryBadge.color(for:)` (xanh dương / xanh lá / cam / tím), dùng cho chấm chip, hàng hiện dần và thẻ duyệt. Hàng danh sách đuôi đổi tên "Đuôi địa danh, tổ chức, thuật ngữ". Không có hàng tải model.
- **Màn đang lọc**: `.preparingModel` ⇒ dòng "Tải model" + % (đang tải) / "Nạp model…" (nạp + tự kiểm), xong hiện ✓; bước đọc đổi tên "Phân tích chương". `.failed(msg)` (kể cả tải model lỗi) ⇒ phase mới `.failed`: thẻ lỗi + thanh đáy "Quay lại" / "Thử lại" (chạy lại đúng cấu hình, `LocalNameFilterSession.StartRequest`). Hàng hiện dần có badge loại màu.
- **NE / VP như luồng AI**: `LocalNameFilterSession` dựng `AIExtractedName` (nhãn = `Category.label`) rồi qua `AIBookDataInspector.decorateExtractedNames` ngoài main ⇒ badge NE / VP, name đã có bỏ chọn sẵn; toast "Lọc xong: N name · M đã có". `hiddenKnownCount` không còn dùng.
- **Màn duyệt** (chỉ luồng lọc local, luồng AI giữ nguyên hành vi): hàng chip "Tất cả N · Nhân danh N · Địa danh N · Tổ chức N · Thuật ngữ N" (`ReaderAINameReviewCategoryBar`, chỉ nhóm có mục, kiểu chip `ExtensionKindFilterBar`); chip chỉ ẩn hàng, Chọn hết / Bỏ chọn / Lưu vẫn tính cả danh sách; nhóm đang chọn hết mục ⇒ về Tất cả. Badge loại có màu cho 4 nhãn, nhãn khác xám. Cụm badge tách sang `ReaderAINameReviewBadges` (thẻ giữ dưới 400 dòng).
- **Gói tạm** (`Services/Translation/NameFilter/Drafts/`): `LocalNameFilterDraftStore` ghi `name_filter_drafts/<sha256(bookId)>.json`, tối đa 5 gói / truyện (bỏ gói ghi lâu nhất), file hỏng cất `.broken-…`. Gói = danh sách đang duyệt (chữ, nghĩa đã sửa, loại, số lần, đang chọn, cờ NE / VP) + giờ lọc + phạm vi ("chương 1–50" / "193 chương") + số chương. Ghi khi sheet đóng lúc đang duyệt mà chưa Lưu (kể cả sau "Dừng") + toast "Đã giữ gói tạm (N name)", và khi app vào nền lúc đang duyệt. Màn duyệt báo danh sách mới nhất qua `onNamesChange` (chỉ bản nhận sẵn danh sách).
- Sheet thiết lập có section "Gói tạm chưa lưu (N)" ở đầu (chỉ khi có gói): hàng "giờ · phạm vi", dòng 2 "N name · đang chọn M"; chạm ⇒ mở lại màn duyệt đúng trạng thái; vuốt trái ⇒ Xoá. Lưu thành công ⇒ xoá gói đó; lưu lỗi ⇒ ghi lại gói. Mở lại rồi đóng chưa Lưu ⇒ ghi đè đúng gói đó.
- Kho theo `bookId`: `StorageUsageCategory.nameFilterDrafts` ("Gói name tạm (lọc name)"); Dọn rác nhóm "Dữ liệu của truyện đã xoá" bắt `<hash>.json` mồ côi (chung luật với ghi chú / dấu trang, `JunkPaths.nameFilterDraftsRoot` vào `allowedRoots`); Đổi nguồn chép (gộp theo id) / xoá qua `BookSourceMigrator`. Luật Dọn rác không đụng model LAC ở `translate/LAC/` (chỉ `*.partial` khi không có lượt tải).
- Chưa làm: xoá truyện chưa xoá gói tạm (`BookStorageManager.deleteBookSideData` ngoài phạm vi phần này; tới lúc đó Dọn rác bắt file mồ côi). Chưa build được tại chỗ (Windows); `check_architecture.py` chỉ còn violation cũ `JSDom.swift`.

## [1.3.1087] - 2026-11-27

### feat: danh sách đuôi của lọc name local có loại Thuật ngữ, Tông môn đổi tên thành Tổ chức

## [1.3.NNN] - 2026-11-27
### feat: danh sách đuôi của lọc name local có loại Thuật ngữ, Tông môn đổi tên thành Tổ chức
- Màn "Đuôi địa danh & tông môn" đổi tên thành "Đuôi địa danh, tổ chức, thuật ngữ" (plan `2026-11-27-loc-name-lac.md` mục D, mockup LAC khung 4); tab lọc thành Tất cả / Địa danh / Tổ chức / Thuật ngữ.
- Nhãn loại của đuôi lấy từ nhóm name (`SuffixKind.category.label`): `sect` hiện là "Tổ chức", thêm "Thuật ngữ" (`SuffixKind.term`); ô Loại ở màn Sửa từ của đuôi có ba lựa chọn.
- Dòng "Ví dụ" của màn Sửa từ đổi theo loại: thuật ngữ dùng 五气 ⇒ "Ví dụ: 五气丹 → Ngũ Khí đan", địa danh / tổ chức giữ 江海.
- Lời giải thích "?" và dòng danh sách trống nói cả tổ chức / thuật ngữ.

## [1.3.1086] - 2026-11-27

### feat: danh sách đuôi lọc name local thêm loại Thuật ngữ, tắt sẵn 关 và 花

### feat: danh sách đuôi lọc name local thêm loại Thuật ngữ, tắt sẵn 关 và 花

Plan `Docs/Plans/2026-11-27-loc-name-lac.md` mục D (anh Bửu duyệt 2026-11-27).

- `NameFilterSuffixes.txt` 103 đuôi: thêm 40 đuôi loại `term` (神诀 真诀 心法 剑法 功法 真经 宝体 圣体 诀 经 功 丹 鼎 舟 符 箓 阵 珠 镜 氅 袍 甲 旗 钟 炉 剑 刀 枪 印 芝 果 草 盾 轮 花 瘴 术 蟒 鲤 兽), nghĩa Hán-Việt viết thường đặt sau theo bảng phiên âm (旗 = kì, 鲤 = lí).
- Xét từng đuôi trên 6 truyện: chỉ **花** phân loại sai tên người (李翠花) ngang số mục đúng ⇒ tắt sẵn; 芝 gặp một tên người (宋韵芝) nhưng 2/3 đúng ⇒ giữ. **关** tắt sẵn (cùng 路 区 观 团).
- Ghi đè cũ của người dùng giữ nguyên: bật / tắt đuôi gốc vẫn theo `enabled`; ai đã tự thêm đuôi 花 (loại địa danh / tông môn) trước bản này vẫn bật (`LocalNameFilterSuffixOverrides.bundledOffLater`). Parser / store nhận `term` qua `SuffixKind`.
- Chú thích đổi tên danh sách thành "Đuôi địa danh, tổ chức, thuật ngữ" (loại `sect` giữ chữ cũ, hiển thị "Tổ chức").

## [1.3.1085] - 2026-11-27

### feat: lọc name local dùng model LAC gắn nhãn theo chương, hợp với bộ luật, lọc theo loại và giữ name đã có

### feat: lọc name local dùng model LAC gắn nhãn theo chương, hợp với bộ luật, lọc theo loại và giữ name đã có

Đợt "Lọc name local bằng LAC" (plan `Docs/Plans/2026-11-27-loc-name-lac.md` mục C + phần engine bước 0, anh Bửu duyệt 2026-11-27). Bản tham chiếu Python `Docs/Plans/local-name-filter-lac/` (`lacpipe.py` + `local_name_filter2.py` cờ `V3` / `KEEP_KNOWN`) sửa và chạy đủ 6 truyện trước; bản Python soi gương cấu trúc Swift khớp hoàn toàn bản tham chiếu trên 6 truyện (hàng, loại, số lần, nghĩa, cờ đã có, lý do bỏ, số hàng hợp).

- **Chạy** (`LocalNameFilterRun`): chụp từ điển (thiếu VP thì báo ngay, không tải model) ⇒ `LACModel.prepare` phát `.preparingModel(fraction:)` thưa ≥ 1 %; tải lỗi / file hỏng ⇒ `.failed` (màn có "Thử lại"); model tự kiểm lệch ⇒ log ❌ rồi chạy **chỉ bộ luật** như trước bản LAC. Mỗi khối 24 chương: đọc ⇒ gắn nhãn LAC song song theo chương (`LocalNameFilterLACChapterTagger`, tối đa số nhân − 1, mỗi dòng gọi `tag` đúng một lần, bỏ dòng `第N章` / dòng không có chữ Hán) ⇒ cộng theo thứ tự chương. Cập nhật dần, Dừng, huỷ giữ như cũ.
- **Phía LAC** (`LocalNameFilterLACPipeline`, bước 2–4 của `lacpipe.py`): bóc ≤ 2 chữ nhẹ cuối, gộp tên + 1 chữ khi phần tên mạnh ≥ 5 lần, mảnh ≥ 60 %; lọc Ít nhất N lần / từ thường / hư từ / đầu là từ thường / họ + từ thường / chữ dính; phân loại theo đuôi dài nhất (địa danh / tổ chức / thuật ngữ) rồi nhãn LAC (hoà: người > nơi > tổ chức > thuật ngữ), LAC bảo người + đuôi yếu (山 河…) ⇒ vẫn là người. Luật (e): từ VP nghĩa thường nhưng có đuôi không yếu, ≥ 3 chữ, LAC gắn thực thể nhiều hơn nhãn khác ⇒ giữ (菩提丹, 青山县, 华山派 — 6 truyện cứu 5 mục, không rác).
- **Bước hợp** (`LocalNameFilterOutputBuilder`): thêm hàng bộ luật (cờ v3: chữ thời gian / hướng trong tên, chữ cấm trong phần trước đuôi, tên + chữ nhẹ, họ hay dính từ thường mà không có bằng chứng — `LocalNameFilterSurnameBoundness`, `titleAfter`) chưa có, không phải mảnh, không phải name đã có: địa danh / tổ chức / họ tộc; tên người chỉ khi LAC từng gắn PER.
- **Name đã có không còn ẩn** (cả hai chế độ): giữ trong danh sách, đếm `Snapshot.knownCount`; bộ luật giữ cả khi mọi cách hiểu bị luật bỏ. "Không phải name" + "Loại cần tìm" (`Configuration.categories`) lọc ở đầu ra, cả bản hiện dần.
- **Nghĩa**: người / danh xưng như cũ (họ dò theo Danh sách họ); có đuôi ⇒ phần riêng viết hoa + nghĩa đuôi trước / sau (五气丹 → "Ngũ Khí đan"); thuật ngữ không đuôi ⇒ âm từng chữ viết hoa.
- Từ phía LAC khoá theo code point (`LocalNameFilterWord`): dài tuỳ ý, có dấu `·` hay chữ khối mở rộng (日月皇家魂导师学院, 奥斯汀·格里芬, 玄𫄸).
- Đuôi loại `term` không vào bộ luật (không sinh ứng viên), chỉ phân loại + dựng nghĩa phía LAC.
- Log `🔎 [LọcName] Xong`: thêm chế độ, thời gian model / gắn nhãn / lọc LAC, `đã có` (thay `ẩn`), số theo loại, số hàng hợp + (e); `bỏ […]` là lý do phía LAC (trùng tên `lacpipe.py`), `luật bỏ […]` là bộ luật.
- Số Python (mặc định app, 6 truyện): Sư muội 268 name (97 đã có + 171 mới), Võ Thánh 237, Chư thiên 100, Tổng võ 63, Từ cung 22, Đấu La 658 (382 + 276) — phần tăng đúng bằng số name đã có từng bị ẩn.
- `check_architecture.py` chỉ còn violation cũ `JSDom.swift`. Chưa biên dịch (Windows); `LACModel.prepare` còn là bản giữ chỗ tới khi gộp phần model; màn hình (`Views/`) còn dùng `hiddenKnownCount` tới khi gộp phần giao diện.

## [1.3.1084] - 2026-11-27

### fix: kho model LAC kiểm đường dẫn trước mọi lệnh ghi, chuyển, xoá file

Bổ sung cho commit "bộ nhận diện tên LAC chạy trên máy…" theo luật validatePathSafety(for:) của rules.md (có thể gộp vào cùng entry CHANGELOG).

- LACModelStore.validatePathSafety(for:): đích phải nằm trong translate/LAC/; xoá cả thư mục model thì kiểm thư mục đó nằm trong translate/. Chỉ giải symlink phần đã có trên đĩa (file chưa có ⇒ giải thư mục cha rồi ghép tên) để tiền tố /private của /var không làm so lệch.
- LACModelDownloader gọi kiểm này trước khi xoá / chuyển file đã tải vào chỗ và trước khi ghi manifest; lỗi ⇒ downloadFailed.
- check_architecture.py chỉ còn violation cũ JSDom.swift. Chưa biên dịch được tại chỗ (Windows).
