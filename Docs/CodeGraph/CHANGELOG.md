# CHANGELOG - Nhật ký Thay đổi CodeGraph Tàng Công Các

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **Tàng Công Các**.

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

## [1.3.1083] - 2026-11-27

### feat: bộ nhận diện tên LAC chạy trên máy, tự tải model lần đầu và tự kiểm với mẫu đối chiếu

Phần "model LAC bằng Swift" của đợt Lọc name local bằng LAC (anh Bửu duyệt 2026-11-27, plan Docs/Plans/2026-11-27-loc-name-lac.md): thay thân LACModel.prepare (chữ ký giữ nguyên).

- Tải model: lần đầu dùng tải ~19 MB từ kho Hugging Face datasets/raikiri1498/vietpharse, thư mục lac/, ghim commit 73bb76d4 (LACModelMirror, ghim cả sha256 của lac_manifest.json) vào Application Support/translate/LAC/ (LACModelStore). Thứ tự: manifest ⇒ từng file vào file tạm của hệ thống ⇒ đúng kích thước + sha256 ⇒ chuyển vào ⇒ ghi manifest cuối cùng. Tiến độ 0…1 theo tổng byte; resume theo từng file; huỷ ⇒ CancellationError, file tạm luôn bị xoá; không đặt file .partial dưới translate/ vì Dọn rác coi *.partial là rác.
- Bộ gán nhãn LACTagger viết lại LAC 2.1.2 theo README của kho: tách từ sơ bộ trên small_seg.dic (LACSegmenter, mọi vị trí theo Unicode scalar, điểm Double từ manifest cộng đúng thứ tự ⇒ hoà giống hệt LAC), ra id word.dic + q2b.dic (LACVocabulary), hai lớp BiGRU + FC bằng Accelerate (LACNetwork: vDSP_mmul chiếu cả câu một lần, mỗi bước một vDSP_mmul 1×H, vvexpf / vvtanhf, không cấp phát trong vòng lặp bước; embedding fp16 đọc thẳng từ file ánh xạ bộ nhớ), Viterbi (LACViterbi), gộp nhãn B/I như parse_result. Từ điển tra bằng cây tiền tố theo scalar (LACScalarTrie), không dùng String làm khoá (Swift so tương đương chính tắc, LAC so code point). Bất biến ⇒ gọi song song nhiều chương được; dòng dài hơn 2.000 chữ cắt sau dấu hết câu rồi gán nhãn từng đoạn.
- Mỗi lần nạp: kiểm sha256 mọi file (hỏng ⇒ xoá thư mục + invalidFiles, lần sau tải lại), rồi tự kiểm 203 câu lac_golden.json (LACSelfCheck): tách từ + id phải trùng 100%, nhãn cuối lệch tối đa 3 câu, lệch hơn ⇒ selfCheckFailed (giữ file) và log ❌ mẫu đầu tiên kèm chuỗi LAC / app.
- LACModelGate: nhiều lượt gọi cùng lúc chỉ một lượt tải + nạp, tiến độ phát cho mọi người chờ; người chờ bị huỷ chỉ nhận CancellationError cho riêng mình, lượt gốc dừng khi người chờ cuối rời đi; giữ bộ gán nhãn yếu, còn sống thì lượt sau trả ngay không báo gì.
- Log 🧠 [LAC]: thời gian tải, nạp, tự kiểm, số câu lệch; lỗi thật kèm ❌.
- Đối chiếu trên PC bằng bản Python chép dòng-dòng phần Swift (không commit): golden 203 / 203 trùng cả bốn bước; 19.749 dòng truyện trùng tách từ + id 100%; 2.000 dòng chạy đủ mạng lệch nhãn 2 dòng (embedding fp16, như lúc xuất).
- Giấy phép Apache-2.0 của LAC ở Docs/ThirdParty/LAC-LICENSE.txt; công cụ xuất model Tools/lac-export/ (export_lac.py, lac_shim.py, bản giấy phép).
- check_architecture.py chỉ còn violation cũ JSDom.swift. Chưa biên dịch được tại chỗ (Windows); chưa thử trên máy.

## [1.3.1082] - 2026-11-27

### refactor: hợp đồng lọc name local có loại Thuật ngữ, bốn nhóm name và cửa vào model LAC

Bước đầu của đợt "Lọc name local bằng LAC" (anh Bửu duyệt 2026-11-27, plan `Docs/Plans/2026-11-27-loc-name-lac.md`, mockup https://claude.ai/artifact/Tx6oQ2Xd7KeaEybnnZ3cQq): chốt kiểu dữ liệu chung trước để ba phần (model LAC, bộ lọc + danh sách, giao diện + gói tạm) làm song song.

- `LocalNameFilter`: `Kind.term` (thuật ngữ); nhóm `Category` (Nhân danh / Địa danh / Tổ chức / Thuật ngữ) — `Kind.category`, `label` theo nhóm (tông môn + họ tộc ⇒ "Tổ chức"); `SuffixKind.term` + `SuffixKind.category`; `Configuration.categories` ("Loại cần tìm", mặc định cả bốn); `Event.preparingModel(fraction:)`; `Snapshot.knownCount` thay `hiddenKnownCount` — name đã có không còn bị ẩn, màn duyệt gắn badge NE / VP và bỏ chọn sẵn như luồng AI.
- `NameFilter/NER/`: `LACToken`, giao thức `LACTagging` (một dòng ⇒ các từ + nhãn, an toàn đa luồng), `LACModelError`, `LACModel.prepare(progress:)` (bản giữ chỗ). Model đã đẩy lên `datasets/raikiri1498/vietpharse` thư mục `lac/`, commit `73bb76d4`.
- Commit này một mình **chưa biên dịch được** (các `switch` trên `Kind` / `SuffixKind` / `Event` chưa có nhánh mới) — các phần sau của đợt bổ sung, chỉ push khi đủ.

## [1.3.1081] - 2026-11-27

### fix: nhận diện chữ Hán gồm cả khối mở rộng để panel Dịch điền đúng nghĩa chữ hiếm như 𫄸 thay vì chữ gốc

Anh Bửu thử 1.3.1080 (hết văng, 𫄸 thành một ô) và gửi ảnh: chọn riêng 𫄸 ⇒ ô nghĩa hiện nguyên "𫄸" trong khi chip có "huân" (VietPhrase Chung).

- **Nguyên nhân**: `TranslateUtils.translateTerm` chỉ tra từ điển khi `containsChinese` đúng, mà hàm này chỉ nhận U+4E00–9FFF ⇒ chữ khối mở rộng C trở đi bị trả nguyên văn (bấm "Cập nhật" lúc đó là lưu nhầm `𫄸=𫄸`). `VietPhraseTokenizer.isChineseCharacter` cũng chỉ có cơ bản + mở rộng A, B.
- **Sửa**: bảng dải chữ Hán dùng chung mới `ChineseCharacterClassifier` (`Services/Translation/Utils/`): cơ bản, mở rộng A, B–F + I, G–H, chữ tương thích (F900–FAFF, 2F800–2FA1F). `containsChinese` và `isChineseCharacter` cùng gọi vào đây.
- **Ảnh hưởng** (22 file gọi hai hàm này): chuỗi đã có chữ Hán cơ bản cho kết quả y như cũ; chỉ chuỗi mà chữ Hán **toàn** thuộc khối mở rộng / tương thích mới đổi từ "để nguyên" sang "được dịch / phiên âm" (chương, TTS, phụ đề, tên truyện…); token một chữ mở rộng không có trong từ điển giờ lùi về phiên âm Hán-Việt như chữ thường.
- `check_architecture.py` chỉ còn violation cũ `JSDom.swift`. Chưa build được tại chỗ (Windows); chưa thử trên máy.
- Dọn: entry 1.3.1051 chuyển sang `CHANGELOG.archive.md`.

## [1.3.1080] - 2026-11-27

### fix: panel Dịch không văng app khi thu hẹp cụm có chữ Hán hiếm như 𫄸, tách từ đếm đúng chữ, nút ‹ › và hàng chữ gốc theo trọn chữ

Anh Bửu: bôi đen 玄𫄸法衣 trong Reader ⇒ Dịch ⇒ bấm "Thu hẹp bên phải" ⇒ văng app. Ba crash log `.ips` cùng một stack: trap Swift trên luồng nền, đúng chỗ `ReaderDefinitionWorker.load` dịch lại cụm sau mỗi lần thu hẹp (bản Release không có dSYM nên kết luận từ đọc code). 𫄸 (U+2B138) nằm ngoài BMP: một chữ nhưng hai đơn vị UTF-16.

- **Nguyên nhân văng** — `VietPhraseTokenizer.tokenizeUncached`: chỉ số là chỉ số `Character` (`Array(text)`) nhưng trie trả độ dài khớp theo UTF-16 ⇒ mục từ điển chứa chữ ngoài BMP làm độ dài dư 1 mỗi chữ, cắt lấn sang chữ sau; cụm ngắn (panel dịch lại cụm đã thu hẹp qua `translateTerm`) thì vượt cuối mảng ⇒ sập. Sửa: chuỗi có ký tự dài ≠ 1 đơn vị thì dựng bảng offset UTF-16 từng ký tự, đổi độ dài trie ⇒ số ký tự (`characterCounts`), bỏ độ dài rơi giữa một ký tự; ngưỡng "cụm VP ≥ 2" tính theo chữ (một chữ ngoài BMP đứng lẻ từng lọt ngưỡng). Chuỗi toàn ký tự 1 đơn vị: kết quả y như cũ. Hệ quả: chương / TTS có chữ ngoài BMP khớp từ điển nay tách đúng (trước nuốt thêm chữ sau ⇒ dịch sai).
- **Token `<hv>`** (`QuickTranslationDictionaryToken.candidates`): chỉ nhận chữ dài đúng 1 đơn vị UTF-16 — chữ ngoài BMP không còn bị capture lấy nửa cặp surrogate.
- **Nút ‹ › nhích trọn chữ**: hàm chung mới `ComposedTextSelection` (`Sources/Common/Utils/`, dựa trên `rangeOfComposedCharacterSequence`) cho Reader (`ReaderView+Selection` — dùng chung panel Dịch / Xoá từ rác / Copy gốc), sheet Dịch truyện tranh (`ComicDefinitionSheet+Selection`) và màn Sửa từ (`DictEntryEditSheet`). Vùng chọn vẫn là `NSRange` UTF-16; chữ 1 đơn vị nhích y như trước.
- **Hàng chữ gốc mỗi chữ một ô** (`ComposedTextSelection.cells`): panel Dịch, Xoá từ rác, Copy gốc, màn Sửa từ — 𫄸 không còn vẽ thành hai ô vỡ; chạm một ô chọn trọn chữ đó.
- Ghi bất biến vào `.claude/rules/reader-text-pipeline.md`. `check_architecture.py` chỉ còn violation cũ `JSDom.swift`. Chưa build được tại chỗ (Windows); chưa thử trên máy.
- Dọn: entry 1.3.1050 chuyển sang `CHANGELOG.archive.md`.

## [1.3.1079] - 2026-11-27

### fix: gạch hàng name AI không mất khi đang có lượt AI chạy, Quản lý nghĩa không ghi lại Pronouns khi không sửa, màn Thêm báo rõ khi chỉ thêm phần đang chọn

Sửa sau lượt rà soát chéo đợt 1.3.1074–1078 (hai agent đọc code, không thấy lỗi biên dịch chắc chắn).

- **Gạch hàng name AI** (`ReaderAIFullScreenView.setNameStruck`): sửa cả bản phiên của lượt AI đang chạy (`AIRuntimeCoordinator.updateMessage`) — lượt đó ghi đè phiên xuống đĩa khi xong / mỗi lượt quét, nên gạch trong lúc đang quét hay chờ AI trả lời từng bị mất khi mở lại.
- Sửa một name thành khoá đang gạch ⇒ tự bỏ gạch khoá đó (`ReaderAINameReviewSheet+Edit`); VoiceOver "Sửa" không mở hàng gạch; gạch hết mọi hàng thì nút đầu thẻ là "Chọn hết" (không còn "Bỏ chọn" bấm không có tác dụng). Sửa comment còn nói "✕ xoá như cũ".
- **Quản lý nghĩa từ**: so bản gốc đã chuẩn hoá y như bản nháp (cùng tách + bỏ trùng) — nghĩa trùng sẵn trong file (vd Pronoun `ta/ta`) làm mở-rồi-đóng cũng ghi lại cả file Pronouns gốc + dựng lại `.dat` + dịch lại Reader.
- **Màn Sửa từ ở chế độ danh sách** (đuôi, "Không phải name", họ, token): chế độ Thêm chọn một phần chữ gốc ⇒ hiện "Chỉ thêm X (phần đang chọn)" thay vì lặng lẽ chỉ thêm phần đó; mở cao hết cỡ (`.large`) như form cũ để bàn phím không che nút "Thêm" và hàng Loại / Nghĩa đứng (VP / Name / Pronouns giữ nấc nửa màn).
- `check_architecture.py` chỉ còn violation cũ `JSDom.swift`. Không build tại chỗ (Windows).
- Dọn: entry cũ nhất chuyển sang `CHANGELOG.archive.md`.

## [1.3.1078] - 2026-11-27

### feat: danh sách duyệt name của AI gạch hàng kèm nút Hoàn tác thay cho xoá hẳn, mở lại vẫn còn gạch

Anh Bửu: "khi xóa từ trong danh sách của AI đừng xóa hẳn, xóa thì gạch hàng đó và chuyển thành nút hoàn tác", rồi chốt "mở lên lại thì vẫn còn gạch hàng + nút hoàn tác, cái bị gạch thì không chọn được". Chỉ màn duyệt của AI (nút xoá ở đó từng xoá hẳn dòng `từ=nghĩa` khỏi tin nhắn — lỡ tay là mất); màn duyệt của lọc name local giữ menu "Bỏ khỏi lần này / Không phải name".

- Thùng rác ⇒ **gạch** hàng: chữ gạch ngang + mờ, ô chọn bỏ chọn và khoá, chạm thân hàng không mở màn Sửa từ, nút thành ↶ Hoàn tác (xanh lá). Bấm ↶ ⇒ bỏ gạch. Đầu thẻ "· đã gạch N"; "Chọn hết / Bỏ chọn" bỏ qua hàng gạch; Lưu lọc bỏ hàng gạch (`ReaderAINameReviewCardView` `struckKeys` + `onToggleStrike`, `ReaderAINameReviewSheet`).
- Trạng thái gạch lưu theo **tin nhắn**: trường mới `AIChatMessage.struckNameKeys` (khoá = vế trái đã trim, optional — lịch sử cũ đọc như chưa gạch), ghi ngay mỗi lần gạch / bỏ gạch qua `AIChatHistoryStore.saveSession` (`ReaderAIFullScreenView.setNameStruck`, thay `removeNameLine`). `content` của tin **không** đổi nên mở lại sheet (kể cả sau khi tắt app) dựng lại danh sách như cũ rồi vẽ hàng gạch. Gạch theo từng tin.
- Không còn đường nào gọi `AIRuntimeCoordinator.forgetName` / `contentRemovingNameLines` từ sheet duyệt (để nguyên trong coordinator).
- `check_architecture.py` chỉ còn violation cũ `JSDom.swift`. Không build tại chỗ (Windows).
- Dọn: entry cũ nhất chuyển sang `CHANGELOG.archive.md`.

## [1.3.1077] - 2026-11-27

### fix: nút NE, VP, PN, R, C ở panel Dịch rộng cố định 30 pt để hàng nút không tràn trên máy 375 pt

Rà lại 1.3.1076 (chưa thử máy): nút loại / phạm vi đặt `minWidth: 30` + `maxWidth: .infinity` trong khi cụm aa…AA cũng giãn vô hạn ⇒ hai cụm hoà về độ co giãn, `HStack` có thể chia đôi cho cụm aa…AA trước ⇒ cụm NE | VP | PN · R | C thiếu ~11 pt ở panel 329 pt (máy 375 pt) và hàng tràn; đặt trần hữu hạn thì `HStack` bên trong lại chia cho cụm R | C trước ⇒ R / C rộng hơn NE / VP / PN.

- `ReaderDefinitionOverlayView+Rows.dictSegmentButton`: `.frame(width: segmentButtonWidth)` = 30 pt cố định — đúng mockup khung 1 anh Bửu chọn ("nút loại còn khoảng 30 pt"). Cụm nút cứng ⇒ đặt trước, cụm aa…AA nhận phần còn lại (~27 pt / nút ở 329 pt, giãn trên máy rộng). Trên máy rộng hơn 375 pt, NE / VP / R / C không còn giãn theo màn (trước 1.3.1076 rộng ~36–47 pt).
- Sửa chữ entry 1.3.1076: lưu PN đổi chip / bảng tra ngay, còn **chữ dịch** chỉ đổi ở chỗ có rule `<pn>` khớp (tách từ không tra Pronouns từ 1.3.1016 — luật đó giữ nguyên).
- Dọn: entry 1.3.1047 chuyển sang `CHANGELOG.archive.md`. Chưa build được tại chỗ (Windows); `check_architecture.py` chỉ còn violation cũ `JSDom.swift`. Bề ngang chưa đo trên máy.

## [1.3.1076] - 2026-11-27

### feat: panel Dịch lưu được vào Pronoun bằng nút PN cạnh NE và VP

Anh Bửu (plan `Docs/Plans/2026-11-27-pronoun-chip-dict-edit.md` ý 6): chọn **cách A** của mockup https://claude.ai/artifact/3LcrV8ViqPyhmg7wSYhE5W khung 1 — giữ một hàng; sau đó chốt "PN không ghim được".

- **Hàng định dạng + nơi lưu** (`ReaderDefinitionOverlayView+Rows`, dùng chung panel Dịch Reader và sheet Dịch của truyện tranh): `[aa Aa¹ Aa² Aa AA] | [NE|VP|PN] [R|C]`. Nút NE / VP / PN / R / C bề ngang tối thiểu 30 pt (máy 375 pt: cụm aa…AA tự co còn ~27 pt / nút, chữ aa…AA co tới 80% nếu thiếu chỗ; máy rộng hơn cả hai cụm giãn như trước).
- **Lựa chọn ba giá trị** `DefinitionSaveTarget` (mới: `.name` / `.vietPhrase` / `.pronoun`) thay `@State saveAsNameType: Bool` ở `ReaderView` và `ComicDefinitionSheet`. Ghim mặc định giữ nguyên `@AppStorage pinnedSaveAsNameType` (`Bool`, NE / VP) — PN không ghim được: `dictSegmentButton` nhận `onPin: nil` ⇒ tắt riêng cử chỉ nhấn giữ (`including: .subviews`), không badge, không rung, không toast. Mở panel / đổi vùng chọn vẫn lấy NE hoặc VP theo ghim (kể cả đang chọn PN mà nới vùng chọn — như NE / VP hiện nay).
- **Chọn PN ⇒ cụm R | C mờ 0,35**, không bấm / không nhấn giữ ghim được (`.disabled` + `.allowsHitTesting(false)`); lựa chọn R / C giữ nguyên, chọn lại NE / VP thì về như cũ.
- **"Cập nhật" với PN** (`DefinitionSaveTarget.save`): nghĩa chuẩn hoá như NE / VP (`DictionaryTextFileStore.normalizeMeaning`) rồi `GlobalDictionaryEditor.save` vào file Pronouns gốc — từ đã có ⇒ thay nghĩa; dựng lại `.dat`, nạp lại riêng Pronouns, xoá cache dịch, báo đổi từ điển (Reader / truyện tranh tra lại chip; chữ dịch chỉ đổi ở chỗ có rule `<pn>` khớp — tách từ không tra Pronouns từ 1.3.1016). Thành công ⇒ đóng panel y NE / VP — NE / VP vốn **không** có toast thành công nên PN cũng không; lỗi ⇒ "Không lưu được định nghĩa (Pronoun): …".
- `.claude/rules/translation.md` thêm phần panel Dịch vào đoạn "Pronoun trên chip nghĩa".
- Dọn: entry 1.3.1046 chuyển sang `CHANGELOG.archive.md`. Chưa build được tại chỗ (Windows); `check_architecture.py` chỉ còn violation cũ `JSDom.swift`. Bề ngang hàng nút chưa đo trên máy.

## [1.3.1075] - 2026-11-27

### feat: đuôi địa danh, Không phải name, Danh sách họ và token tùy chọn sửa bằng màn Sửa từ như từ điển

Anh Bửu (plan `Docs/Plans/2026-11-27-pronoun-chip-dict-edit.md` ý 1, mockup https://claude.ai/artifact/3LcrV8ViqPyhmg7wSYhE5W khung 4): "làm cái gì có vế trái là chữ Hán giống từ điển cũng làm kiểu edit của từ điển" — bốn danh sách `chữ Hán = …` bỏ form hai ô, thêm / sửa một mục mở **chính** màn Sửa từ `DictEntryEditSheet` (hàng chữ gốc chọn được ‹ › | chữ | ‹ ›, hàng token, ô nghĩa, chip nghĩa gợi ý, aa…AA, "Cập nhật", tra cứu ngoài, bút chì đổi chữ gốc).

- **Chế độ danh sách** (`DictEntryEditListMode` mới + `DictEntryEditSheet+List.swift`, tham số `listMode:` cuối init, mặc định `nil` ⇒ VP / Name / Pronouns / name AI chạy y như trước — ba chỗ gọi cũ không sửa): kiểm luật + trùng khoá qua store của từng danh sách, lỗi hiện đỏ ở dòng thông báo (ô trống không tô đỏ); store từ chối khoá đã có nên câu "sẽ bị ghi đè" + cảnh báo cam ẩn đi; lưu trả lỗi ⇒ sheet giữ nguyên. Khoá rỗng = thêm mới: tiêu đề "Thêm từ", ô gõ chữ gốc mở sẵn + focus, nút "Thêm". Chọn cả từ ⇒ cập nhật / đổi chữ gốc (`replacing` = khoá đang sửa); chọn một phần ⇒ thêm mục mới = phần đang chọn, mục đang sửa giữ nguyên ("Lưu thêm X, giữ nguyên Y"). Hàng phụ riêng của danh sách qua `extraRows` (sau aa…AA) + `isExtraDirty` (hỏi "Bỏ thay đổi?"). Không gắn truyện ⇒ không có ⚙ Quản lý nghĩa; chip lấy từ hàm chip dùng chung (có chip Pronoun của 1.3.1074).
- **Đuôi địa danh & tông môn** (`LocalNameFilterSuffixEditorSheet`): badge "Đuôi · Chung", khối **Loại** (Địa danh / Tông môn) + **Nghĩa đứng** (Trước tên / Sau tên, mục mới mặc định Sau tên, loại mặc định theo tab) và dòng "Ví dụ: 江海市 → …" đổi theo lựa chọn; giữ "Nghĩa gốc: …" khi nghĩa khác bản gốc và nút "Về bản gốc: …" cho đuôi gốc đã sửa.
- **Không phải name** (`LocalNameFilterBlocklistEditorSheet`, thay `LocalNameFilterBlocklistAddSheet`): chỉ hàng chữ gốc + hàng token, không ô nghĩa / chip / aa…AA. Hàng của danh sách nay chạm thân hàng = sửa cụm (trước chỉ xoá rồi thêm lại); đổi cụm qua `LocalNameFilterBlocklistStore.replace(_:with:)` mới — giữ chỗ và ngày thêm, trùng cụm khác ⇒ lỗi; cụm giữ nguyên ⇒ không làm gì, không toast.
- **Danh sách họ** (`QuickTranslationSurnameEditorSheet`): badge "Họ · Chung", ô nghĩa = âm Hán-Việt của họ, giữ nút "Về âm gốc: …".
- **Token tùy chọn** (`QuickTranslationCustomTokenEntryEditorSheet`): badge "<@tên> · Chung", ô nghĩa = nghĩa của từ.
- `onSave` của ba sheet đuôi / họ / token thêm tham số `replacing` (màn danh sách thôi tự lấy khoá của mục đang mở). Ghi chú: `.claude/rules/ui-conventions.md` (luật "Danh sách vế trái chữ Hán ⇒ màn Sửa từ"), `translation.md` (đoạn cùng tên + Danh sách họ / Token tùy chọn / Lọc name local).
- Dọn: entry 1.3.1045 chuyển sang `CHANGELOG.archive.md`. Chưa build được tại chỗ (Windows); `check_architecture.py` chỉ còn violation cũ `JSDom.swift`. Chưa thử máy.

## [1.3.1074] - 2026-11-27

### feat: chip nghĩa Pronoun viền tím, nhóm Pronoun trong Quản lý nghĩa từ, tách nghĩa Pronoun bằng | và chuẩn hoá | thành / một lần

Anh Bửu (plan `Docs/Plans/2026-11-27-pronoun-chip-dict-edit.md` ý 2–5, mockup https://claude.ai/artifact/3LcrV8ViqPyhmg7wSYhE5W khung 1–3 / 5): Pronoun thành lớp nghĩa ngang hàng NE / VP ở mọi chỗ tra / sửa nghĩa — đảo quyết định 1.3.721 "chip chỉ Name/VP". Ý 6 (nơi lưu PN ở panel Dịch) chưa làm, chờ anh chọn cách xếp.

- **Chip Pronoun** (`ReaderView.suggestionChips(from:)` — panel Dịch Reader, màn Sửa từ / Thêm từ): nguồn `"Xưng hô (Pronouns)"` của `dictionaryMatches`, nay là hằng `ManageDefinitionsDraft.pronounSource` và là mục thứ năm của `editableSources` ⇒ thứ tự Name Riêng → Name Chung → VP Riêng → VP Chung → **Pronoun** → Phiên âm. Category mới `SuggestionChipCategory.pronoun` viền tím (`rgba(191,90,242,0.7)` như mockup), chữ trắng, không badge R/C; nghĩa trùng chữ với chip đứng trước gộp vào chip đó. Sheet Tra từ điển của trình duyệt thêm nhóm "Pronouns" (chỉ hiện khi có nghĩa riêng của Pronoun). VoiceOver đọc thêm "Pronoun".
- **Tách nghĩa Pronoun thêm bằng `|`** (ngoài `/`, `¦`), chỉ Pronoun: chip và `ManageDefinitionsDraft.splitMeanings(_:source:)` (bản nháp + phép so lúc lưu cùng gọi ⇒ mục `a|b` không đụng tới thì không ghi lại). `<pn>` và danh xưng lọc name local vốn đã nhận `|`.
- **Quản lý nghĩa từ có nhóm "Pronoun · Chung"** sau VP Chung (`ManageDefinitionsView` / `ManageDefinitionGroupView`): thêm / sửa / xoá / đổi chỗ như nhóm khác. Đóng màn ⇒ nhóm đã đổi ghi thẳng file Pronouns gốc qua `GlobalDictionaryEditor` (`save` nối `/`, hết nghĩa ⇒ `delete`) — cùng đường danh sách Pronouns: dựng lại `.dat`, nạp lại riêng Pronouns, xoá cache dịch. Log lỗi lưu của màn này đổi `⚠️` ⇒ `❌`.
- **Chuẩn hoá một lần** (`PronounsSeparatorNormalization`, mới; cờ `pronounsPipeNormalizedV1`): `TranslationManager.init` gọi ngay sau lượt nạp từ điển đầu ⇒ `GlobalDictionaryEditor.normalizePronounSeparators()` (trong hàng đợi ghi) đổi mọi `|` trong nghĩa thành `/`, một ký tự đổi một ký tự — dòng, khoá, chữ nghĩa giữ nguyên; không mục nào có `|` ⇒ không ghi. Chưa có file ⇒ đánh dấu xong; lỗi ⇒ `❌`, lần mở sau thử lại. Log `📚 [Pronouns] Chuẩn hoá một lần | → /: đổi N / tổng` (dòng thường — log tắt lúc mở app nên lần chạy đầu thường không ghi). `GlobalDictionaryEditor` tách phần nạp lại sau khi ghi thành `reloadAfterWrite(type:)` dùng chung.
- Sửa comment / tài liệu cũ nói "Xưng hô không lên chip"; `.claude/rules/translation.md` thêm đoạn "Pronoun trên chip nghĩa + Quản lý nghĩa từ", làm rõ luật "Pronouns chỉ qua `<pn>`" là về đường dịch.
- Dọn: entry 1.3.1044 chuyển sang `CHANGELOG.archive.md`. Chưa build được tại chỗ (Windows); `check_architecture.py` chỉ còn violation cũ `JSDom.swift`. Chưa thử máy.

## [1.3.1073] - 2026-11-27

### fix: nút xoá ở danh sách duyệt name dùng thùng rác đỏ như danh sách từ điển

Anh Bửu (ngay sau 1.3.1072): "đổi thành nút xóa giống danh sách trong từ điển".

- `ReaderAINameReviewCardView.removeIcon`: ✕ tròn xám 22 pt ⇒ `trash` đỏ `.subheadline` y hàng `DictionaryEntryRow`; vẫn giữ vùng chạm 44 × 44 của 1.3.1072. Áp cho cả màn duyệt của AI và của lọc name local (luồng local bấm vẫn ra menu "Bỏ khỏi lần này / Không phải name").
- Không build tại chỗ (Windows).
- Dọn: entry 1.3.1043 chuyển sang `CHANGELOG.archive.md`.
