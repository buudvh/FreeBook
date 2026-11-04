# CHANGELOG - Nhật ký Thay đổi CodeGraph FreeBook

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **FreeBook**.

## [1.3.707] - 2026-11-04

### fix: ô tìm của bảng chọn nguồn Khám phá đứng yên khi cuộn

Người dùng: *"Hãy sửa cho hàng search luôn hiển thị ở vị trí đó dù scroll xuống dưới trên màn chọn tiện ích khám phá"*.

- **Ngăn kéo menu có tuỳ chọn `contentScrolls`** (`sideDrawerMenu(..., contentScrolls:)`, mặc định `true`, đi qua `SideDrawerMenuModifier` → `SideDrawerMenuWindowManager` → `SideDrawerMenuWindowRoot` → `SideDrawerMenuPanel`).
  - `false` thì panel không bọc nội dung trong `ScrollView`. Nội dung chiếm phần còn lại của ngăn kéo và tự cuộn.
  - Mọi ngăn kéo khác giữ nguyên.
- **Bảng chọn nguồn Khám phá** (`DiscoverySourcePickerModifier`, `ExtensionSelectorView`) mở với `contentScrolls: false`.
  - Ô tìm và nút chọn loại đứng yên ở đầu; chỉ danh sách nguồn (hoặc dòng "Không có nguồn nào khớp") cuộn bên dưới.
  - Ô tìm vẫn ở trong cùng view nên từ khoá vẫn là `@State` của bảng: gõ là lọc ngay, như trước.
- **Kiểm chứng:**
  - Đọc code; `check_architecture.py` chỉ còn 1 lỗi nền (`JSDom.swift`), **0 mới**.
  - Không build tại chỗ (Windows), chưa thử trên máy: cuộn danh sách dài, vuốt đóng ngăn kéo, gõ tìm khi bàn phím đang mở.

## [1.3.706] - 2026-11-04

### feat: màn sửa VP/Name theo bố cục màn dịch, nghĩa rule cuộn ngang được

Người dùng:
- *"Cho màn edit của vp/name trong danh sách giống màn dịch của reader nhưng đừng có suggest rule và nghĩa rule"*;
- *"Thêm nút mở rộng thu hẹp, nếu lưu vế trái sẽ lưu phần đang chọn"*;
- *"hàng gốc phải giống dịch. Nút mở rộng thu hẹp trên 1 hàng"*;
- *"Ô nhập hiển thị được tối đa 2 hàng như dịch. Sửa phần nghĩa rule màn dịch nếu dài quá sẽ cho scroll ngang"*;
- chọn *"Giữ từ cũ"*.

- **Màn sửa từ của danh sách VP/Name** (`DictEntryEditSheet`, `+Rows`, `DictEntryEditLookup`): chế độ `.edit` của `DictEntrySheet` chuyển sang màn mới; chế độ thêm (dán nhiều dòng `key=value`) giữ nguyên. Dựng lại theo `ReaderDefinitionOverlayView`, màu theo hệ thống thay cho chữ trắng trên nền tối. Từ trên xuống:
  - **Header:** `.pageTitle("Sửa từ")`, nhãn chỉ đọc loại từ điển và phạm vi ("VP · Chung", "Name · Riêng truyện"). Nút bút chì gõ lại từ gốc, giữ cảnh báo ghi đè. Không còn nút "Lưu" trên header.
  - **Hàng từ gốc:** giống Reader — cao 40, hai cặp nút tròn 28pt mở rộng/thu hẹp hai đầu trên cùng một hàng. Chữ đang chọn đậm và gạch chân, chữ còn lại mờ; chạm một chữ thì chọn chữ đó. Vùng chọn ban đầu là cả từ, mở rộng tới hai đầu từ gốc, thu hẹp còn ít nhất 1 chữ.
  - **Hàng token dịch:** dùng `TranslateUtils.getTranslationTokens`; chạm token thì chọn đúng phạm vi của token.
  - **Ô nghĩa:** 2 dòng như Reader. Đổi vùng chọn thì ô hiện nghĩa của cụm: nghĩa đang lưu nếu cụm đã có trong danh sách, không thì bản dịch (`translateTerm`). Chữ người dùng đang gõ không bị kết quả tra về muộn ghi đè.
  - **Dải gợi ý nghĩa:** chip của Reader, tính lại theo vùng chọn. Có nút dán. Nút ⚙ quản lý nghĩa chỉ hiện khi có truyện.
  - **Chữ hoa/thường** và **tra nhanh** (công cụ tìm của Reader, mở `BypassWebView`, ⚙ cấu hình công cụ).
  - Không có phần rule (nghĩa rule, chip rule, thêm rule) và không có bộ chọn NE/VP, R/C.
- **Lưu bằng nút "Cập nhật"** (`.appFilled`) ở dưới:
  - Chọn cả từ: cập nhật nghĩa như cũ.
  - Từ gõ lại bằng bút chì: đổi tên như cũ.
  - **Chọn một phần: giữ nguyên từ cũ, thêm cụm đang chọn thành từ mới**, kèm dòng báo trước khi lưu và cảnh báo khi cụm đã có trong danh sách.
  - Vuốt đóng khi có thay đổi thì hỏi xác nhận.
- **Màn dịch của Reader:** chữ "Nghĩa rule" và dòng thông báo rule nằm trong khung cuộn ngang, nên chữ dài kéo xem hết được. Vẫn chọn để chép được; hàng giữ cao 50.
- **Kiểm chứng:**
  - Đọc code đối chiếu API có sẵn: `getTranslationTokens`, `translateTerm`, `ReaderView.dictionaryMatches`/`suggestionChips`, `SearchEngine.loadEngines`, `ReaderLookupRoute`.
  - `check_architecture.py` chỉ còn 1 lỗi nền (`JSDom.swift`), **0 mới**. `DictionaryListView` 661/690 dòng.
  - Không build tại chỗ (Windows), chưa thử trên máy.
  - Rủi ro: sửa nghĩa trong ⚙ rồi bấm "Cập nhật" sẽ ghi đè bằng chữ trong ô; gõ lại từ gốc rồi chọn một phần thì thêm cụm thay vì đổi tên.

## [1.3.705] - 2026-11-04

### feat: sửa rule dịch đổi mẫu thì chọn thay rule cũ hoặc lưu thêm rule mới

Người dùng: *"Nút lưu của sửa rule thêm option thay the rule cũ cùng lưu và giữ rule cũ. Hiển thị option kiểu như nút lưu thêm rule"*; duyệt plan + mockup.

- **Trước đây** sửa mà đổi mẫu thì luôn **thêm** rule mới, rule cũ giữ nguyên (`updateRule` bỏ qua `oldPattern`, chỉ `upsert` mẫu mới); muốn bỏ rule cũ phải xoá ở danh sách.
- **Màn sửa rule** (`QuickTranslationRuleEditorSheet`): đổi mẫu ⇒ chạm Lưu mở `Menu` hai mục như nút Lưu của màn thêm: "Thay rule cũ" (phụ đề "Sửa đúng dòng N, mẫu cũ mất") / "Lưu thêm rule mới" ("Giữ nguyên rule cũ" — hành vi cũ). Mẫu không đổi ⇒ Lưu vẫn là nút thường, đè bản dịch tại chỗ: file khoá theo mẫu nên không giữ được hai dòng cùng mẫu. Bản lưu luôn vào bộ của rule đang sửa (chung / tên chương / riêng truyện). Câu trợ giúp ô Mẫu viết lại.
- **Thay chỗ**: `QuickTranslationRuleRecordStore.replacing(oldPattern:pattern:replacement:in:)` (mới) đặt rule mới đúng vị trí dòng cũ (giữ thứ tự khi hoà ưu tiên); mẫu mới trùng một dòng khác trong bộ ⇒ dòng kia bị bỏ để bản đang sửa thắng (như lưu mẫu đã có thì đè); không còn dòng cũ ⇒ thêm như `upsert`. `updateRule` của cả ba kho (`QuickTranslationRuleStore+Editing`, `QuickTranslationRuleChapterStore`, `QuickTranslationRuleBookStore`) dùng hàm này; "Lưu thêm rule mới" đi `QuickTranslationRuleTransfer.copy` như thêm rule.
- `onSubmit` của sheet nhận thêm `replacing` (mẫu bị thay chỗ, `nil` = thêm / giữ rule cũ) nên danh sách rule và Reader không còn tự suy `oldPattern` từ `mode`. Cờ tắt của mẫu cũ không chuyển sang mẫu mới (như xoá rule hiện nay). Chuyển `[1.3.674]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng**: đọc code + diff; `check_architecture.py` chỉ còn lỗi có sẵn của `JSDom.swift`. Máy Windows nên chưa build, chưa thử trên máy — chờ CI biên dịch.

## [1.3.704] - 2026-11-04

### feat: khoá nút kiểm tra nguồn khi đang có lượt kiểm tra chạy nền

Người dùng: *"Đang có tiến trình kiểm tra rồi thì disable nút kiểm tra đi nhé"*. Trước đây bấm vẫn mở màn rồi mới báo "Đang có một lượt kiểm tra khác…".

- **`SourceCheckBusyReader`** (mới, `Views/Extensions/SourceCheck/`): đọc `MinimizedSourceCheckCoordinator.isBusy(kind)` = bộ chạy có lượt **đang chạy ở nền** (đã thu nhỏ). Màn kiểm tra còn mở thì đã che mọi lối vào, và không đổi trạng thái `NavigationLink` đang đẩy chính màn đó. Reader tự observe coordinator nên dùng được trong ngăn kéo ⋯ (cửa sổ nổi riêng).
- **Bốn lối vào** khoá theo đúng bộ chạy, mờ đi và có chữ lý do: ⋯ tab Nguồn Legado "Kiểm tra nguồn (theo nhóm đang lọc)" và ⋯ tab Tất cả tiện ích "Kiểm tra tiện ích đang hiện" (chữ phụ "Đang chạy"); "Kiểm tra nguồn này" ở Chi tiết nguồn Legado (chữ "Đang có lượt kiểm tra"); nút tròn "Kiểm tra" ở thẻ đầu Cấu hình tiện ích (nhãn đổi thành "Đang chạy"). Lượt Legado không khoá lối vào tiện ích JS và ngược lại (hai bộ chạy riêng, chạy song song được).
- Lượt chạy từ Debug server không qua màn kiểm tra nên không khoá; bấm vẫn ra màn báo bận như cũ. `rules.md` luật hub (f) thêm ý này. Chuyển `[1.3.673]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng**: đọc code + diff; `check_architecture.py` chỉ còn lỗi có sẵn của `JSDom.swift`. Máy Windows nên chưa build, chưa thử trên máy — chờ CI biên dịch.

## [1.3.703] - 2026-11-04

### fix: token <m> đứng đầu rule đọc 十 là mười

Người dùng: *"Nếu token <m> giá trị 10 đứng đầu rule ví dụ mười mấy thì dịch là mười thay vì mươi"*; xác nhận `<m>几 = {0} mấy` trên `十几` đang ra "mươi mấy", muốn "mười mấy", tiêu chí *"đứng đầu rule và là 10 thôi, 20 30 vẫn là mươi"*; duyệt plan.

- **Nguyên nhân**: `QuickTranslationMagnitudeFormatter` tra bảng cố định `十`/`一十` → `mươi` (chữ đơn vị để ghép sau số đếm: `几<m>` ⇒ `mấy mươi`), không biết `<m>` đứng ở đâu trong mẫu.
- **Sửa**: compiler đánh dấu `<m>` là phần tử đầu tiên của mẫu (`QuickTranslationRuleCompiler+LeadingMagnitude`, mới; cờ `QuickTranslationRuleElement.leadsPattern`). Neo `<START>`/`<END>` bỏ qua vì không chiếm ký tự; mẫu mở đầu bằng nhóm thì xét phần tử đầu từng nhánh; chữ cố định hay ngoặc đứng trước thì không tính là đứng đầu. `<m>` được đánh dấu mà khớp `十`/`一十` ⇒ `mười` (`renderMagnitude(_:leadsPattern:)`); `二十` vẫn `hai mươi`, `十万` vẫn `chục vạn`, `几<m>年` vẫn `mấy mươi năm`.
- Giới hạn theo đúng tiêu chí vị trí: câu `几十几` gặp rule `<m>几` vẫn khớp từ `十` (`几` không thuộc lớp ký tự của `<m>` nên không bị chặn biên) ⇒ ra "mấy mười mấy". Tên chương đã lưu bản dịch trong mục lục chỉ đổi sau "Dịch lại tên chương".
- Hướng dẫn (`QuickTranslationRuleGuide`, mục Token số và nhãn) thêm một ý. Chuyển `[1.3.672]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng**: đọc code + diff; `check_architecture.py` chỉ còn lỗi có sẵn của `JSDom.swift`. Máy Windows nên chưa build, chưa thử trên máy — chờ CI biên dịch.

## [1.3.702] - 2026-11-04

### fix: thu nhỏ màn kiểm tra nguồn không còn mất dòng trên hub

Người dùng (bản 1.3.698 trên máy): *"Đã thu nhỏ, kiểm tra đang chạy nhưng không hiện hub mà hiện icon thông báo"*. Lượt không bấm chia sẻ; mở lại Kiểm tra nguồn không có nút "Mở lượt đang chạy" ⇒ bản ghi chưa bao giờ được đánh dấu thu nhỏ (phần hub đúng).

- **Nguyên nhân**: nút ⌄ chỉ đóng màn rồi trông vào `onDisappear` để báo thu nhỏ; màn Legado không có lối dự phòng chắc chắn khi sheet đóng mà `onDisappear` không tới (`ScreenLease` chỉ chạy nếu SwiftUI giải phóng màn). Chưa xác nhận được trên máy lối nào rơi.
- **Nút ⌄** gọi `MinimizedSourceCheckCoordinator.screenDidClose(_, screenId: nil)` **trước** khi đóng màn, không qua `onDisappear`.
- **`onDismiss` của mọi sheet có thể chứa màn kiểm tra**: sheet Kiểm tra nguồn và Chi tiết nguồn Legado (`RepositoryManagerView+LegadoMenu`, `DiscoverySourcePickerModifier`), ba chỗ mở Cấu hình tiện ích (`RepositoryManagerView`, `DiscoverySourcePickerModifier`, `TTSSettingsView`); sheet mở lại từ hub dùng `SheetDismissRelay` (`presentationController.delegate`, gán sau khi trình bày).
- `onDisappear` của hai màn bỏ điều kiện cờ chia sẻ (bảng chia sẻ không làm màn biến mất, cờ kẹt thì chặn mất việc thu nhỏ). `update` bỏ qua lượt đã thu nhỏ (màn đóng mà task chưa dừng không cướp mốc "xong" ⇒ mất toast). Log `🧪 [SourceCheck]` ở `track` và các nhánh `screenDidClose` bỏ qua (cần bật log trong Cài đặt). `rules.md` luật hub (f) ghi các lối báo đóng. Chuyển `[1.3.671]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng**: đọc code + diff; `check_architecture.py` chỉ còn lỗi có sẵn của `JSDom.swift`. Máy Windows nên chưa build, chưa thử trên máy — chờ CI biên dịch.

## [1.3.701] - 2026-11-04

### feat: token số trong rule dịch có khoảng giá trị #min-max

Người dùng: *"thêm min max cho các token số trong rule dịch"*; chọn **giá trị số** (không phải độ dài, vốn đã có `<n:1-4>`), áp cho `<n>` `<d>` `<y>` `<h>` `<hn>`, cú pháp `<n#1-200>`; duyệt plan + mockup.

- **Cú pháp**: `#min-max` viết sau tên và sau độ dài: `<n#1-200>`, `<n:1-4#1-200>`, `<d#0-99>`, `#5` = đúng 5, `#100-` = từ 100 trở lên. Kiểu `QuickTranslationRuleValueRange` (mới, `Engine/`) giữ tách `#`, đọc, kẹp, dựng lại cú pháp và kiểm giá trị — parser (`QuickTranslationRuleParser+ValueRange`, mới), `tokenSpecNames` và `TokenSpec` cùng gọi nên hiểu `#` như nhau. `#…` tách **trước** `:`: tách `:` trước thì `<n:1-4#1-200>` bị đọc lặng lẽ thành độ dài `1-200`.
- **Giá trị lấy từ kết quả render**, không parse lại chữ Hán: `<n>` `<y>` `<h>` `<d>` ra chữ số ⇒ `Int` (`二零二五` = 2025, `007` = 7); `<n>` liệt kê (`十三四` → `13, 14`) ⇒ mọi số phải trong khoảng; `<hn>` (render Hán-Việt) ⇒ giá trị bằng `renderNumeral` của chuỗi nguồn; tràn `Int` / đọc không được ⇒ không khớp. Matcher (`walkNumeral`) bỏ độ dài ứng viên có giá trị ngoài khoảng rồi thử độ dài ngắn hơn, như ứng viên `<m>` sai dạng; token có biên chặn hai đầu (`第<n#1-200>章`) chỉ xét cả dãy số ⇒ `第三百章` không khớp hẳn.
- **Lỗi mới `INVALID_VALUE_RANGE` (lỗi nặng)**: `#` trống, không phải số, `#-9` (thiếu số đầu; không chặn dưới thì viết `#0-…`), khoảng ngược `#5-3` (khác độ dài vốn tự kẹp), sai thứ tự `#1-9:1-3`, hoặc `#` gắn cho `<a>` `<m>` `<L>` `<any>`, token từ điển, neo dòng, ngoặc.
- **Chip chỉnh** (`QuickTranslationRuleTokenValueRangeEditor`, mới): dưới thanh độ dài của token số có công tắc "Giới hạn giá trị" (bật ⇒ 1–100, tắt ⇒ bỏ `#`) và hai hàng `[−] ô số [+]`; ô Đến trống = không chặn trên. Ô số chỉ ghi vào mẫu khi rời ô hoặc bấm −/+, kẹp qua `clamped()` (chung với `TokenSpec.clamp()`); thanh chỉnh gắn `.id(tokenPosition)` để chữ gõ dở không dính sang token khác. `TokenSpec` giữ `valueRange` nên chỉnh độ dài không làm mất `#`; `#` viết sai ⇒ không mở thanh (không xoá phần đang gõ). Gợi ý bàn phím coi `#` là đuôi token (con trỏ trước `#…` không bị hiểu là gõ dở).
- **Rule cũ không đổi**: không thêm loại token nên chữ ký cache (`Configuration.signature`) giữ nguyên; token không ghi `#` có `valueRange == nil`, matcher không đi qua nhánh mới. Ưu tiên giữa rule không đổi: `<n>章` và `<n#1-9>章` hoà mọi tiêu chí thì dòng viết trước thắng như cũ.
- Hướng dẫn (`QuickTranslationRuleGuide`: mục Token số và nhãn + Lỗi hay gặp), câu trợ giúp ô Mẫu, đoạn token ở `CLAUDE.md`/`AGENTS.md` cập nhật. Chuyển `[1.3.670]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng**: đọc code + diff; `check_architecture.py` chỉ còn lỗi có sẵn của `JSDom.swift`. Máy Windows nên chưa build, chưa thử trên máy — chờ CI biên dịch.

## [1.3.700] - 2026-11-04

### fix: sửa 5 lỗi engine Legado từ báo cáo kiểm tra nguồn

Người dùng gửi hai báo cáo "Kiểm tra nguồn" (31 nguồn / 735 nguồn dừng ở 76) và duyệt plan sửa các lỗi do app. Bằng chứng lấy từ trang/API thật và corpus nguồn; phần lớn lỗi còn lại là do web hoặc nguồn cũ.

- **`java.getString/getElements` trong JS sau một phân đoạn rule chạy trên trang/mục của rule** (`LegadoRuleAnalyzer.evaluate`: `frameContent` = nội dung gốc, không còn là kết quả trung gian; `result` giữ nguyên). ㊣ UC小说 #一程1101: `$.data.chapterList[0].volumeList<js>java.put('freeUrlPre',java.getString('$.data.freeContUrlPrefix'))…` trước đây ra tiền tố rỗng, URL chương ghép vào API mục lục nên nội dung rỗng. 77 rule cùng kiểu trong corpus (书旗, 阿巴, 人人小说, 起点, 晋江…).
- **JSONPath ngầm `.x` thành `$..x`** (quét sâu, như thư viện JsonPath thêm `$.` trước đường dẫn không bắt đầu bằng `$`/`@`); `..x` và `[…]` chỉ thêm `$`. QQ阅读 ×3 `.bookList[*]`/`.books[*]` trên API trả `{"data":{"bookList":[…]}}` trước đây ra 0 mục.
- **Danh sách giá trị JSON đổi thành chuỗi ra văn bản JSON** như `JSONArray` của json-smart (`LegadoJSBootstrap.core`: `dec` gắn cờ ẩn khi mọi mục là `$json`, `toString()` dùng `JSON.stringify`). 网易云 `data.books[*]` rồi `JSON.parse(result)` trước đây lỗi `Unexpected identifier "object"`; 爱发电 `String(result).replace(/\[/,…)`, 番茄 cũng cần. Danh sách phần tử HTML và danh sách chuỗi giữ như 1.3.694; danh sách rỗng vẫn ra `""`.
- **XPath dựng trên cây SwiftSoup thay vì thân thô** (`rootXPathDocument`, nhánh chuỗi HTML của `xpathItems`): libxml2 2.9 không tự đóng `<dd>` khi gặp `<dd>` kế, nên mục lục R 玩文学 (`<dd><a>…` thiếu `</dd>`) thành lồng nhau, chương i lấy link/tên của chương i…N ⇒ HTTP 414 ở bước nội dung. Tuần tự hoá không pretty-print, escape `.xhtml` để SwiftSoup không chép lại nguyên văn thân gốc; cài đặt in của document trả lại ngay. Rule `/table/tbody/tr` (13 rule corpus) cũng khớp như cây jsoup.
- **Trường URL nhiều giá trị lấy dòng không rỗng đầu** (`LegadoURLResolver.absoluteFieldURL`, sau khi tách khối option): 一曲书屋 `bookUrl: a@href` trên `<p>` có link sách + link tác giả trước đây ra `…/book/132394/\n/author/…` ⇒ HTTP 400. `nextTocUrl`/`nextContentUrl` vẫn là danh sách.
- **Không sửa (không phải lỗi app)**: 企鹅浏览 (bản cài có `bookUrl` hỏng), 天地中文 (web trả danh sách rỗng; kết luận "app" của báo cáo là sai), ⭐ 猫眼看书③ (mọi host API lỗi), 黑岩 ×2 (UA di động mặc định ⇒ web chuyển bản `w.heiyan.com` không có `<span>`; giữ UA theo spec §3.10).
- Spec `legado-source-spec.md` cập nhật §2.2 bước 5, §2.11.1, §2.12, §2.15 bước 1, §6.3 (`toString`), bảng `java.getString`. Chuyển `[1.3.669]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng**: đọc code + diff; chạy `core` bootstrap bằng node với `__lgNative` giả (danh sách JSON/chuỗi/trộn/rỗng, `for…in`, export); lần tay JSONPath trên JSON QQ thật; `check_architecture.py` chỉ còn lỗi có sẵn của `JSDom.swift`. Máy Windows nên chưa build, chưa thử trên máy — chờ CI biên dịch.

## [1.3.698] - 2026-11-04

### feat: thu nhỏ màn kiểm tra nguồn và kiểm tra tiện ích vào hub nổi

Người dùng: *"cho phép thu nhỏ khi kiểm tra nguồn, làm cho cả kiểm tra js luôn"*, rồi *"vuốt xuống sheet đừng tắt mà thu nhỏ nhé"*. Lối mở lại là dòng thứ 4 cố định của hub (người dùng chọn).

- **Rời màn không còn dừng lượt**: màn Kiểm tra nguồn Legado (`LegadoSourceCheckView`) và Kiểm tra tiện ích (`ExtensionCheckView`) có nút ⌄ sát nút chia sẻ (chỉ hiện khi đang chạy). Bấm ⌄, vuốt xuống sheet hay quay lại khi lượt còn chạy ⇒ lượt **thu nhỏ** và chạy tiếp ở bộ chạy; chỉ nút Dừng mới dừng. `stopSourceCheck` (`onDismiss` của sheet kiểm tra tiện ích hàng loạt) đổi từ huỷ lượt sang thu nhỏ.
- **`MinimizedSourceCheckCoordinator`** (mới, `Views/Extensions/SourceCheck/`): mỗi bộ chạy giữ tối đa một bản ghi (lượt Legado và lượt tiện ích JS chạy song song được). Màn bắt đầu hoặc gắn vào lượt ⇒ `track`; vòng thăm dò của màn ⇒ `update`. Màn đóng (`onDisappear`, hoặc `ScreenLease` là `@StateObject` giải phóng cùng màn, để bắt cả lúc sheet bị vuốt khi đang đẩy màn con) ⇒ lượt còn chạy thì thu nhỏ và tự thăm dò mỗi giây, lượt đã xong thì bỏ. Xong hoặc dừng khi đang thu nhỏ ⇒ toast (vào cả Trung tâm thông báo).
- **Mở lại**: `reopen` trình bày màn bằng UIKit từ màn trên cùng của cửa sổ mức thường (sheet có thanh kéo; thử lại khi màn trên cùng đang mở/đóng dở). Màn chạy ở chế độ `attachRunId`: đọc ngay kết quả hiện có, không chạy lượt mới; bộ chạy đã sang lượt khác ⇒ báo rõ và bỏ bản ghi. Màn báo bận có thêm nút "Mở lượt đang chạy" khi lượt kia đang thu nhỏ; "Dừng lượt đang chạy" ở đó cũng thôi theo dõi như nút Dừng.
- **Hub nổi**: dòng thứ 4 cố định `Kind.sourceCheck` "Kiểm tra nguồn" (`checkmark.seal`), xám khi không có lượt. Đang chạy ⇒ là tiến trình của nút (nháy), dòng phụ "12/31 · 3 lỗi"; xong mà chưa xem ⇒ nằm trong `quietKinds` (không nháy), "Xong · 25 đạt · 6 lỗi — bấm để xem". Tiến độ chỉ nằm ở chữ của dòng, không vào `ButtonState`. Hai lượt cùng thu nhỏ ⇒ trang con `FloatingHubSourceCheckListView`. Chạm hub khi đây là tiến trình duy nhất ⇒ mở thẳng màn.
- Tách phần trùng giữa hai màn: `SourceCheckHeaderButtons`, `SourceCheckTile`, `SourceCheckActionButton`, `SourceCheckStartErrorView`, `ExtensionCheckFilterChip` (giữ `ExtensionCheckView` dưới 400 dòng). `rules.md` thêm luật hub (f) cho dòng Kiểm tra nguồn và vòng đời lượt thu nhỏ. Chuyển `[1.3.668]`, `[1.3.667]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng**: đọc code + diff; `check_architecture.py` chỉ còn lỗi có sẵn của `JSDom.swift`. Máy Windows nên chưa build, chưa thử trên máy — chờ CI biên dịch.

## [1.3.697] - 2026-11-04

### feat: xoá hàng loạt nguồn Legado đang hiện hoặc đang tắt

Người dùng: *"thêm option xóa tất cả nguồn legado đang hiển thị, xóa tất cả nguồn legado đang tắt"*. Phạm vi "đang tắt" là toàn bộ danh sách (người dùng chọn).

- **Hai hàng đỏ mới trong ngăn kéo "…" của tab Nguồn Legado**, đặt trên "Xoá tất cả nguồn Legado". Bên phải mỗi hàng là số nguồn sẽ xoá; số bằng 0 thì hàng mờ.
  - **Xoá tất cả (theo danh sách đang hiện)**: lấy từ `legadoVisibleSummaries` (NSFW, nhóm và ô tìm), đúng tập mà "Kiểm tra nguồn" và "Bật/Tắt tất cả" dùng.
  - **Xoá tất cả nguồn đang tắt**: mọi nguồn có `isEnabled == false` trong `LegadoSourceRepository.summaries`, không theo nhóm, ô tìm hay NSFW. Chỉ tính sau lần nạp đầu (`hasLoaded`), vì `isEnabled(packageId:)` dạng tĩnh trả `false` cho mọi nguồn trước lúc đó.
- **Hộp xác nhận** (`PendingAlert.confirmDeleteSubset` + `LegadoSourceTabState.DeleteSubset`):
  - Chụp sẵn danh sách `packageIds` lúc bấm hàng và xoá đúng tập đó, nên số trên nút "Xoá N nguồn" khớp số bị xoá.
  - Phạm vi "đang hiện" ghi tên nhóm và từ khoá ô tìm.
  - Phạm vi "đang tắt" báo cả số nguồn 18+ đang ẩn bị gộp vào.
- **Đường gỡ dùng lại** `LegadoSourceCoordinator.delete(packageIds:)`, cũng là đường của nút "Xoá nguồn lỗi" ở màn kiểm tra. Hàm này xoá thư mục, gọi `ExtensionTransactionCoordinator.deleteExtensions`, nạp lại danh sách và xoá thông tin đăng nhập.
  - Mất bản ghi tiện ích thì truyện trên kệ dùng nguồn đó tự thành truyện mất nguồn (luồng 1.3.690).
- **Sau khi xoá:**
  - Toast `Đã xoá N nguồn Legado đang hiện/đang tắt`; lỗi thì toast đỏ.
  - Nhóm đang lọc không còn nguồn nào thì về "Tất cả" (`resetGroupFilterIfEmpty`).
- `legadoScopeTitle` tách ra từ `checkVisibleLegadoSources`, dùng chung cho màn kiểm tra và hộp xác nhận.

## [1.3.696] - 2026-11-04

### fix: mục lục nguồn Legado nhiều chương không còn làm app hết bộ nhớ

Người dùng: *"sửa cái gì mà tôi bấm chạy kiểm tra sau vài giây nó đơ app rồi crash app luôn?"*; gửi 2 file log rồi duyệt phương án (*"Duyệt, sửa đi"*).

- **Nguyên nhân** (có từ engine gốc `3a9044e5`, không do 1.3.693–695):
  - Log bật đủ cho thấy app chết khi 多看阅读 đang dựng mục lục 九星霸体诀: 7.177 chương, trang JSON 1,3 MB. Mỗi chương chạy 2 đoạn JS (`chapterUrl`, `isVip`), khoảng 14.000 lần.
  - Mỗi lần, `LegadoJSRuntime.apply` gán `src` bằng **nguyên trang**, tức một chuỗi JS mới khoảng 2 MB.
  - API ObjC của JavaScriptCore đưa mọi `JSValue` vào autorelease pool hiện hành và giữ giá trị JS khỏi GC (`objcWrapperForJSValueRef` → `autorelease`, `JSValueProtect`). Thread engine (`LegadoEngineSession.run`) không có pool riêng, nên không gì được nhả cho tới hết bước, và iOS giết app vì hết RAM.
  - Bộ thử Node không tái hiện được lỗi này, vì V8 không có autorelease pool.
- **Mỗi lần chạy JS tự dọn:** `autoreleasepool` bọc `evaluate`, `evaluateRaw`, `evaluateOptionScript`, `runLibrary`, `runQuietly`, `callHelper`, `evaluateBytesScript`/`exportedDescriptor` và `classifyLoginCheck`. Vòng chương của `parseTocPage` cũng có pool riêng cho mỗi chương; mục bị bỏ trả `nil` thay cho `continue`, thứ tự gộp `chapterVariables` giữ nguyên.
- **Chuỗi trang chép một lần mỗi trang:**
  - Ô ẩn `__lgSrcCache` (không liệt kê, không xoá) giữ chuỗi JS của trang lớn gần nhất, chỉ trang ≥ 16 KB. Swift giữ bản `String` tương ứng (`cachedPageText`), không giữ `JSValue`.
  - `src` trùng trang đang đệm thì dùng lại; `result` là nguyên trang cũng dùng lại nhưng không ghi ô đệm.
  - Analyzer truyền cùng một `String` cho mọi mục, nên phép so sánh đi đường tắt.
- **Bớt lời gọi qua cầu nối:**
  - Chỉ lần chạy **lồng** (JS → `java.getString` → rule → JS) mới lưu/khôi phục 7 biến môi trường; lần ngoài cùng bỏ 14 lời gọi, vì `apply` của lần sau gán lại đủ 7.
  - Đã rà: ngoài một lượt `evaluateRaw` không chỗ nào đọc 7 biến này (Swift, bootstrap, `runQuietly`, `jsLib` nạp trước lần `apply` đầu).
  - Giữa hai lượt, các biến giữ giá trị của lượt trước thay cho `undefined`.
- **Lỗi cú pháp có lại số dòng:**
  - Eval gián tiếp báo `SyntaxError` không kèm dòng (log "dòng 0" từ 1.3.693). Khi gặp, phân tích lại mã gốc bằng `JSCheckScriptSyntax` — chỉ phân tích, không chạy.
  - `describe` bỏ hậu tố "(dòng N)" khi N ≤ 0.
  - Đường dự phòng `return` vẫn được xét trước.
- **Spec:** `Docs/Specs/legado-source-spec.md` §6.1, mục "Bộ nhớ khi chạy nhiều lần".
- **Quy trình:** agent riêng viết theo phương án đã duyệt (clean-room).
- **Kiểm chứng:**
  - Đọc code đối chiếu chữ ký API: `autoreleasepool(invoking:)` `rethrows`, và `JSCheckScriptSyntax` mà repo đã dùng ở `ExtensionScriptStaticCheck.swift`.
  - Đọc mã JavaScriptCore trên GitHub để xác nhận cơ chế autorelease.
  - `check_architecture.py` chỉ còn 1 lỗi nền (`JSDom.swift`), **0 mới**.
  - Không build tại chỗ (Windows), chưa thử trên máy. Nên thử: mở mục lục 九星霸体诀 ở 多看阅读, rồi chạy lại kiểm tra nhóm nguồn đó.

## [1.3.695] - 2026-11-04

### feat: nguồn Legado có SecretKeyFactory DES, GZIP/Inflater và java.net.URL

Người dùng: *"làm plan: … 3. Lớp Java còn thiếu: DES, GZIP, URL."*; duyệt plan (*"Duyệt, làm đi"*). Trong 3.339 nguồn đã quét: 7 nguồn cần DES qua `SecretKeyFactory`, 4 nguồn giải nén, khoảng 1 nguồn dùng `java.net.URL`.

- **DES** (`LegadoJSBootstrap+Classes.swift`):
  - `javax.crypto.SecretKeyFactory.getInstance("DES"|"DESede"|"TripleDES")`. `generateSecret(spec)` trả khoá có `getEncoded`, `getAlgorithm`, `getFormat` = `"RAW"`. Thuật toán khác (PBKDF2…) báo chưa hỗ trợ.
  - `DESKeySpec(bytes[, offset])` lấy đúng 8 byte, `DESedeKeySpec(bytes[, offset])` lấy 24 byte, cả hai có `getKey()`. Thiếu byte ném `InvalidKeyException`; spec sai loại ném `InvalidKeySpecException`.
  - Khoá dùng thẳng với `Cipher.init` có sẵn: phần mã hoá (`LegadoSymmetricCipher`) không đổi. `SecretKeySpec` thêm `getFormat()`.
- **Giải nén** (`Files/LegadoInflate.swift` mới, lệnh native `inflate`/`inflateUsed` ở `LegadoJSRuntime+Inflate.swift`):
  - Dùng `compression_stream` của framework `Compression`, với `COMPRESSION_ZLIB` (DEFLATE thô).
  - Ba dạng vỏ:
    - `raw`;
    - `zlib`: kiểm header RFC 1950; FDICT báo chưa hỗ trợ;
    - `gzip`: header RFC 1952 đủ cờ, nối nhiều member, kiểm ISIZE.
  - Đầu ra tối đa 16 MiB, để chặn bom nén. Dữ liệu về JS dạng hex nên bộ nhớ thực tốn gấp 5–6 lần.
  - Lỗi được ném vào JS, nên `try/catch` của nguồn bắt được.
- **Luồng Java** (`LegadoJSBootstrap+Streams.swift` mới, nạp ngay trước `packages`):
  - `java.util.zip.GZIPInputStream` / `InflaterInputStream(in[, inflater])`: `Inflater(true)` = raw, còn lại = zlib. `read()` trả 0..255 hoặc -1, `read(buf)` trả -1 khi hết.
  - `java.util.zip.Inflater([nowrap])`: `setInput`, `inflate`, `finished`, `needsInput`, `getRemaining`, `getTotalIn/Out`, `end`, `reset`. Lần `inflate` đầu giải hết đầu vào rồi trả dần, nên cần trọn dữ liệu trong một `setInput`.
  - `java.io.InputStreamReader(in[, charset])` + `BufferedReader`: `readLine` tách `\n`, `\r\n`, `\r` và trả `null` khi hết. Charset đi qua `bytesToStr`.
  - `java.nio.ByteBuffer.allocate/wrap(...).array()` tối thiểu, để đường giải nén của 微信读书 không chết trước.
  - `java.net.URL(spec)` / `URL(context, spec)`:
    - `getProtocol`, `getHost`, `getPort` (-1 khi không có), `getDefaultPort`, `getPath` (`""` khi không có), `getQuery`/`getRef` (`null` khi không có), `getFile`, `getAuthority`, `toString`/`toExternalForm`.
    - Không scheme ném `MalformedURLException: no protocol`. Spec rỗng trả URL ngữ cảnh bỏ `#ref`, như Java.
    - `openConnection` báo chưa hỗ trợ.
  - Gọi được qua `java.util.zip.X`, `Packages.…`, `JavaImporter` + `with`, `importClass`, `importPackage`.
- **Ngoài phạm vi:** `SecureRandom` (đăng nhập 微信读书), okhttp3, `HttpURLConnection`.
- **Spec:** `Docs/Specs/legado-source-spec.md` §6.4.3 và §6.9.
- **Quy trình:** agent riêng viết theo plan và spec (clean-room). Review bắt các lỗi sau, đã sửa:
  - `URL(ctx, "")` ném lỗi;
  - thiếu `ByteBuffer`;
  - giới hạn 64 MiB quá cao (hạ xuống 16 MiB);
  - comment thứ tự nạp script cũ.
- **Kiểm chứng:**
  - JS bootstrap lấy nguyên văn từ file Swift, chạy Node với native giả theo đúng thuật toán `LegadoInflate`: 85/85 ca đạt.
  - Các ca DES đối chiếu với DES thật của Node: 晋江 (DES-CBC), 国家图书馆 (DES-ECB), DESede-CBC.
  - Các ca giải nén: vòng `read` của 酷匠网; gzip nhiều member; `Inflater(true)` của 微信读书; `readLine` của 云端聚合; giới hạn 16 MiB.
  - `check_architecture.py` chỉ còn 1 lỗi nền, **0 mới**.
  - Không build tại chỗ (Windows), chưa thử trên máy. Rủi ro: chưa xác nhận bộ giải của Apple báo đúng số byte đã dùng khi `END`. Nếu sai, gzip nhiều member chỉ mất các member sau.

## [1.3.694] - 2026-11-04

### fix: đối tượng Java của nguồn Legado có đủ method List, Element, Map, chapter

Người dùng: *"làm plan: … 2. Method sai hoặc thiếu trên đối tượng Java"*; duyệt plan (*"Duyệt, làm đi"*). Khoảng 30 nguồn trong 3.339 nguồn đã quét gọi method thiếu, hoặc method chạy sai ngữ nghĩa Java.

- **Định danh phần tử:**
  - `LegadoJSRuntime.register` trả cùng handle cho cùng node SwiftSoup, qua bảng mới `elementHandleIndex: [ObjectIdentifier: Int]`. Bảng an toàn vì `elementHandles` giữ mạnh mọi node, nên `ObjectIdentifier` không bị dùng lại.
  - Bên JS, `wrap` giữ một wrapper cho mỗi handle, nên cùng node ra cùng đối tượng. Nhờ đó `===`, `contains`, `indexOf` và `remove(obj)` chạy đúng.
  - Thêm `equals(o)`.
- **List** (`javaList`, ngữ nghĩa `java.util.List`):
  - `remove()` không đối số vẫn gỡ khỏi DOM như cũ.
  - `remove(số)` bỏ khỏi **danh sách** và trả phần tử. jsoup ≥1.17.1 gỡ cả DOM; FreeBook cố ý chỉ bỏ khỏi danh sách vì mẫu 言情小说吧 cần vậy.
  - `remove(đối tượng)` trả `true`/`false`.
  - Thêm `set`, `add(i, x)`, `addAll([i,] ds)`, `clear`, `iterator()`.
  - `subList(a, b)` là bản sao; chỉ `clear()` ghi ngược về danh sách gốc. Nếu danh sách gốc đã đổi thì ném `ConcurrentModificationException`.
  - Danh sách toàn Element có thêm `eq(i)`, `parents()` (bỏ trùng theo định danh), và `toString()` = `outerHtml` nối bằng `\n`.
  - Mọi method gắn ẩn, nên `for…in`, `Object.keys` và `JSON.stringify` của danh sách không đổi.
- **Element:**
  - Lệnh native mới: `el.parents`, `el.all`, `el.attrs`, `el.before`, `el.after`.
  - `parents()` lấy từ cha gần nhất tới `<html>`, không gồm Document. `getAllElements()` gồm chính nó và mọi con cháu.
  - `attributes()` trả danh sách Attribute: `getKey`, `getValue`, và `toString`/`html` = `key="value"` có escape. Danh sách có `get(tên|số)`, `hasKey`, `asList`, `size`.
  - `before(html)` / `after(html)` trả chính phần tử.
- **chapter:**
  - `isVip()` / `isVolume()` / `isPay()` là method trả boolean; gán `chapter.isVip = v` vẫn ghi được trường.
  - Thêm thuộc tính bean `vip`/`volume`/`pay` và setter `setVip`/`setVolume`/`setPay`. `getIsVip()` trả giá trị trường.
  - Swift không đọc ngược đối tượng chapter bên JS: mục lục dựng từ giá trị Swift tự tính. Vì vậy đổi này không ảnh hưởng `TocEntry`.
- **Map:** thêm `entrySet()`, mỗi entry có `getKey`, `getValue`, `setValue`, `toString` = `k=v`. Mẫu 刺猬猫 `entrySet().toArray().join("; ")` cho ra chuỗi cookie.
- **Hành vi đổi có chủ ý:**
  - `String(danh sách phần tử)` nối bằng `\n` thay cho `,`.
  - `{{chapter.isVip}}` ra rỗng; `if (chapter.isVip)` quên `()` thì luôn đúng, như Legado. Corpus không có nguồn nào viết như vậy.
- **Spec:** `Docs/Specs/legado-source-spec.md` §6.3, §6.6, §6.8.
- **Quy trình:** agent riêng viết theo plan và spec (clean-room). Review bắt lỗi `subList().clear()` xoá nhầm đoạn khi danh sách gốc đã đổi; đã sửa.
- **Kiểm chứng:**
  - JS bootstrap lấy nguyên văn từ file Swift, chạy Node với `__lgNative` giả: 60/60 ca đạt, gồm mẫu thật của:
    - 言情小说吧 (`parents().contains`, `remove(v)`, `subList(1,i).clear()`);
    - 看书网 (`eq`);
    - 白鹿书院 (`getAllElements().indexOf`);
    - 深夜看书 (`attributes`);
    - 哔哩哔哩 (`before`);
    - 刺猬猫 (`entrySet`);
    - 起点限免 (`chapter.isVip()`).
  - Đối chiếu SwiftSoup 2.14.3: có `Element.before/after(String)`, `getAllElements()`, `getAttributes()`.
  - `check_architecture.py` chỉ còn 1 lỗi nền, **0 mới**.
  - Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.693] - 2026-11-04

### fix: rule JS của nguồn Legado chạy trong scope riêng, hết lỗi khai báo trùng

Người dùng: *"TÔi chắc chắn đang thiếu rất nhiều vì rất nhiều source chạy bị lỗi phần java"*, rồi *"làm plan: 1. Lỗi scope JS (top-level `let`/`const` chạy lần hai bị báo khai báo trùng): vẫn đứng đầu, 149 nguồn"*; duyệt plan (*"Duyệt, làm đi"*).

- **Nguyên nhân:** mọi rule JS của một phiên chạy chung global của `JSContext`. Vì vậy `let`/`const`/`class` ở cấp ngoài cùng sống sang lần sau, và chạy lần hai báo `SyntaxError: Can't create duplicate variable`. Quét 3.339 nguồn thật: 149 nguồn dính, 51 nguồn hỏng ngay từ mục thứ 2 của danh sách.
- **`LegadoJSRuntime.evaluateRaw`** chạy rule bằng **eval gián tiếp ở global**:
  - Hàm `eval` gốc được giữ ở thuộc tính ẩn `__lgEval`, cài ngay sau khi tạo context, trước bootstrap và `jsLib`. Nguồn có gán lại `eval` cũng không ảnh hưởng.
  - Mỗi lần chạy, `let`/`const`/`class` có môi trường lexical riêng.
  - `var`/`function` vẫn lên global, và mọi `function` có ngay trước câu lệnh đầu tiên. Vì vậy luồng `loginUrl` → nút form đăng nhập và nút khám phá vẫn gọi được hàm, kể cả khi đoạn đầu script ném lỗi.
  - Giá trị trả vẫn là câu lệnh cuối; luật "`result` bị gán lại" giữ nguyên.
- **Hết che biến môi trường:** nguồn tự khai `let page`/`key`/`result`/`baseUrl` không còn che giá trị app đặt cho các lần sau. Ví dụ: 晋江, 光遇聚合 (`page`/`key`); 51漫画, 塔读 (`result`); 乐乎文章 (`baseUrl`).
- **`return` ở cấp ngoài cùng:**
  - Chạy code gốc trong `(function(result, baseUrl, src, key, page, title, nextChapterUrl){{…}}).call(this, …)`. Đối số đọc bằng `typeof`, nên `var src = src.trim(); return src` hết ra `undefined`.
  - Khối bên trong cho phép `let` trùng tên tham số.
  - Điều kiện bắt lỗi nới thành `"Return statements"`.
- **Khác đã biết, ghi vào spec, corpus 0 đoạn:**
  - Code mở đầu bằng `"use strict"` thì `var`/`function` chỉ sống trong lần đó.
  - Ở đường `return`, gán `result` mà không `return` thì mất.
- **Không đổi:** `jsLib`, `runQuietly` và mọi nơi gọi `evaluateRaw`.
- **Spec:** viết lại `Docs/Specs/legado-source-spec.md` §6.1 và sửa dòng cũ ở §3.3.
- **Quy trình:** session chính đã đọc code Legado (GPL), nên phần code do agent riêng viết theo plan và spec (clean-room). Bản đầu bọc khối `{…}` bị review bắt lỗi: `function` chỉ lên global khi chạy tới câu khai báo, làm hỏng nút đăng nhập ở 7 nguồn. Đã đổi sang eval gián tiếp.
- **Kiểm chứng:**
  - Chuỗi mẫu dựng lại từ chính literal Swift, chạy trên Node `vm` một context dùng chung, đạt đủ bảng ca thử:
    - `let`/`class` chạy hai lần;
    - `var src = src`;
    - hàm khai sau câu lệnh ném lỗi;
    - hàm `jsLib` gọi hàm rule khai muộn;
    - `with(JavaImporter)`;
    - completion value;
    - đường `return` kiểu 可乐小说.
  - `check_architecture.py` chỉ còn 1 lỗi nền (`JSDom.swift`), **0 mới**.
  - Không build tại chỗ (Windows), chưa thử trên JSC hay trên máy. Nên thử: 少年梦阅读 (lặp `let`), 点众阅读 hoặc 刺猬猫#2 (nút đăng nhập), 可乐小说 (`return`).

## [1.3.692] - 2026-11-04

### feat: token ngoặc <[> <]> với bộ ngoặc chỉnh được, neo <START> <END> và hướng dẫn viết rule

Người dùng: *"thêm token đóng mở ngoặc cho rule dịch, có thể config các loại ngoặc cho token"*, *"ngoặc tròn ngoặc vuông ngoặc nhọn đủ nhé"*, *"nhớ bổ sung hướng dẫn đầy đủ để tạo rule… mỗi ý trong phần hướng dẫn 1 dòng"*. Đã chốt bằng bảng chọn:
- Token viết `<[>` / `<]>` (dấu ngoặc vuông, không lẫn với nhóm `( )`); neo dòng đổi tên thành chữ in hoa `<START>` / `<END>`.
- Mở và đóng phải cùng cặp và cân bằng; ngoặc **không** sinh `{i}`.
- Bộ ngoặc có bản chung và bản riêng từng truyện.

- **Token ngoặc** (`QuickTranslationRuleParser+Bracket`, `QuickTranslationRuleMatcher+Bracket`):
  - `<[>` khớp đúng một ký tự mở, `<]>` khớp đúng một ký tự đóng trong bộ ngoặc đang bật; rộng 1, nhận `?`, không nhận `|` hay độ dài.
  - Parser ghép mỗi `<]>` với `<[>` gần nhất còn mở theo thứ tự nguồn (mỗi nhánh của nhóm bắt đầu từ cùng ngăn xếp). Khi khớp, `<]>` phải đúng ngoặc đóng của ký tự `<[>` đã bắt và đoạn giữa phải cân bằng: `<[><any><]>` trên `(a)Y(b)` ra `(a)` rồi `(b)`. `<]>` không có cặp, hoặc cặp nằm ở nhánh không khớp, thì nhận mọi ngoặc đóng.
  - Ký tự mở giữ ở **ô ẩn** sau các ô `{i}` (`slotCount` ở `QuickTranslationParsedRule` / `QuickTranslationCompiledRule`); `Match.captures` chỉ trả phần `{i}`.
  - Tính như chữ cố định khi xét `ANY_WITHOUT_LITERAL` / `NO_LITERAL_ANCHOR` và khi xếp ưu tiên, nên `<[><any><]><END> =` hợp lệ. `<any>` đứng ngay trước token ngoặc chỉ thử các độ dài mà ký tự kế tiếp là ngoặc hợp lệ.
- **Neo dòng đổi tên** `<^>` → `<START>`, `<$>` → `<END>` (`Kind.lineStart/.lineEnd` rawValue mới). Rule cũ vẫn chạy nhờ `Kind.kind(forTokenName:)`. Khoá công tắc chung giữ nguyên; khoá cũ `^`/`$` trong cấu hình riêng truyện được đọc thành tên mới.
- **Bộ ngoặc** (`QuickTranslationRuleBracketPair`, `QuickTranslationRuleBracketDefaults`, `QuickTranslationRuleBracketSet`, `QuickTranslationRuleBracketStore`):
  - Mặc định 50 cặp: tròn 11, mai rùa 6, vuông 11, ngoặc móc 6, ngoặc góc 16. `<>` ASCII có sẵn nhưng tắt. Không có `「」『』` (lời thoại), `⦍⦎⦏⦐` (ghép chéo), `〈〉` U+2329/232A.
  - Bộ chung ở `UserDefaults` `quickTranslateRuleBracketPairs` (vắng = mặc định, Backup tự gói). Bộ riêng truyện ở trường `brackets` của `QuickTranslateEngineConfig.json`.
  - `TranslationReadContext` chụp bộ ngoặc của truyện; engine và màn chẩn đoán dùng bản chụp đó.
  - Khi lưu, kiểm mỗi ô đúng một ký tự (một đơn vị UTF-16), mở khác đóng, không trùng ký tự với cặp khác.
- **Backup:**
  - `QuickTranslateEngineConfig.json` riêng truyện (thứ tự ưu tiên, công tắc token riêng, bộ ngoặc riêng) giờ được sao lưu và khôi phục nguyên văn. Trước đây file này không có trong Backup.
  - Khôi phục cài đặt xong thì dọn cache dịch để bộ ngoặc chung có hiệu lực ngay.
- **Giao diện:**
  - Cấu hình token rule có công tắc `<[>` `<]>` và hàng "Bộ ngoặc".
  - Màn **Bộ ngoặc** (`QuickTranslationRuleBracketListView`), kiểu danh sách 1.3.636 với [Sửa][Tắt/Bật][Xoá] và nút `+` nổi.
    - Bộ chung: ngăn kéo `…` có "Khôi phục mặc định".
    - Bộ riêng truyện (mở từ Cài đặt đọc › token riêng): khi chưa có bộ riêng chỉ xem kèm nút "Chỉnh riêng cho truyện này"; khi đã có thì ngăn kéo có "Dùng bộ chung".
  - Sheet thêm/sửa cặp (`QuickTranslationRuleBracketEditorSheet`) báo lỗi ngay dưới ô.
- **Hướng dẫn viết rule** — một nguồn `QuickTranslationRuleGuide`:
  - Trang `QuickTranslationRuleGuideView` có 11 mục, mỗi ý một dòng kèm ví dụ. Mở từ hàng đầu "Công cụ" của Rule dịch nhanh và từ hàng "Hướng dẫn đầy đủ" ở màn sửa rule.
  - Các nút "?" ở Mẫu, Bản dịch, Cấu hình token và Bộ ngoặc chỉ còn vài dòng lấy từ cùng nguồn. Bỏ câu sai cũ "Mọi token phải được dùng".
- Gợi ý bàn phím nhận `<[` / `<]`; chip ngoặc và neo không được đánh số.
- `CLAUDE.md` / `AGENTS.md`: cập nhật đoạn token ở mục Dịch thuật VietPhrase.
- Chuyển entry cũ nhất sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng:** đọc code + diff; `check_architecture.py` chỉ còn 1 lỗi nền (`JSDom.swift`), **0 mới**. Dò tay trên code các mẫu `<[><any><]>` trên `(a)Y(b)` và `【a)`, `<]>` đứng một mình, `<[><any><]><END>`, `(<[>a|b)<]>`, rule cũ `<^>第<n>章`. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.691] - 2026-11-04

### fix: chuyển nguồn khi link chương khác dạng, thêm mục chuyển nguồn ở sheet nhấn giữ

Người dùng: *"báo lỗi mục lục nguồn mới khác dạng … nguồn cũ là qimao đường đen, nguồn mới là qimao của tôi"*, *"log không thấy gì, bạn không thêm log lỗi à?"*, rồi *"làm y như bạn nói đi. thêm option chuyển nguồn trong contextmenu với book mất ext"*.

- **Nguyên nhân** (đối chiếu mã hai tiện ích): cùng API mục lục nhưng link chương khác hẳn — bản Đường đen (v37) `https://api-bc.wtzw.com/chapter?chapterId=…&id=…&reader_agent=0`, bản của người dùng (v4) `https://www.qimao.com/shuku/<id>-<chương>/`. 1.3.690 chỉ biết gắn lại tại chỗ nên dừng ở "mục lục khác dạng": gắn tại chỗ thì chương chưa tải mở bằng link cũ hỏng, làm mới mục lục nhân đôi chương.
- **Bước kiểm 3 mức** (`SourceRebindValidator.Match`):
  - `sameLinks`: link 3 chương mẫu (đầu, đang đọc, cuối) có trong mục lục mới ⇒ gắn lại tại chỗ như 1.3.690.
  - `samePositions`: link khác nhưng tên chương ở đúng các vị trí đó trùng (bỏ khoảng trắng thừa, chữ thường) ⇒ chạy luồng Đổi nguồn (`BookSourceChangeCoordinator.run`, kết quả tìm dựng từ link chi tiết cũ): truyện mới với mục lục nguồn mới, chép chương đã tải theo vị trí, chép thiết lập riêng, xoá truyện cũ sau mốc chốt; đang nghe TTS truyện đó thì giữ truyện cũ. View chuyển phiên AI sang truyện mới như `SearchView+SourceChange`.
  - `different`: lệch cả tên ⇒ không chuyển.
- **Log**: mọi lần không chuyển được ghi `❌ [SourceRebind]` (link + tên chương mẫu cũ/mới, số chương hai bên) nên có trong log cả khi công tắc log tắt; 1.3.690 ghi dòng thường nên bị nuốt.
- **Sheet nhấn giữ** (Kệ, Lịch sử, Tìm trên kệ, Bộ sưu tập; `MissingSourceRebindActionRows`, mới): truyện mất nguồn có thêm hàng "Chuyển sang nguồn <tên>" cho từng tiện ích khớp link, đứng trên "Đổi nguồn". Chạy cho riêng truyện đó, kể cả truyện dải báo đã thử không được trong phiên; không đòi đang ở trang gốc Kệ (các màn này là danh sách), vẫn dừng nếu truyện đang mở ở màn đọc.
- Luồng Đổi nguồn giữ lại truyện cũ (đang nghe TTS, chép chương lỗi) ⇒ truyện cũ vẫn mất nguồn, được nhớ trong phiên để dải báo không chạy lại mỗi lần mở Kệ.
- `MissingSourceRebindRunner` (mới): phần View dùng chung cho dải báo và sheet — chạy lượt, chuyển phiên AI, toast ("… chép chương lỗi nên giữ lại truyện cũ" khi luồng Đổi nguồn giữ truyện cũ). Bấm lúc đang có lượt đổi nguồn khác ⇒ toast báo thử lại.
- Rủi ro đã có từ trước: mở truyện cũ trong lúc luồng Đổi nguồn đang chép chương thì màn đọc giữ `Book` cũ khi nó bị xoá.
- `CLAUDE.md` / `AGENTS.md`: cập nhật mục "Gắn lại nguồn khi tiện ích đã gỡ".
- Chuyển entry `[1.3.661]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code + diff; `check_architecture.py` 1 violation nền (`JSDom`), **0 mới**. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.690] - 2026-11-04

### feat: truyện mất nguồn tự chuyển sang tiện ích khớp link, hỏi một chạm hoặc tự chuyển

Người dùng: *"nếu nguồn bị xoá rồi thì tự check url regex nếu có nguồn nào ăn đổi qua nguồn đó được không?"*, rồi *"tạo config Hỏi một chạm - Tự chuyển"*. Duyệt PA1: gắn lại nguồn tại chỗ.

- **Dò** (`MissingSourceRebindCoordinator`, `Services/Books/SourceRebind/`, mới):
  - Truyện mất nguồn = truyện ở Kệ hoặc Lịch sử có `extensionPackageId` không còn cài; sách nhập từ file không tính.
  - Ứng viên là tiện ích đã cài trừ nguồn Legado, cùng loại nội dung nếu còn tra được loại của nguồn cũ.
  - `regexp` phải khớp **cả chuỗi** `detailUrl` như hợp đồng tiện ích: thử link nguyên văn, rồi link bỏ `http(s)://` và `/` cuối (`ExtensionUrlMatcher.WholeMatcher`, mới). `matches(for:in:)` khớp một phần giữ nguyên cho nút Nhập và dịch trang.
- **Kiểm trước khi chuyển** (`SourceRebindValidator`, mới): chạy chi tiết + toàn bộ mục lục của tiện ích mới trên link cũ. Link của 3 chương đã lưu (đầu, đang đọc, cuối) phải có trong mục lục mới; so cả bản ghép host, bỏ scheme, `www.` và `/` cuối. Không đạt thì không chuyển, vì làm mới mục lục khớp chương theo URL sẽ nhân đôi chương.
- **Ghi** (`BookTransactionCoordinator.rebindSource`, file `+SourceRebind` mới): đổi `extensionPackageId`, `sourceName`, `sourceUrl`, `host`, **giữ nguyên `bookId`**. Chương đã tải, tiến độ, Name/từ điển riêng, phiên AI không phải chép như Đổi nguồn. Truyện vừa được đổi nguồn ở chỗ khác thì không ghi đè.
- **Kệ** (`MissingSourceRebindBanner`, mới; `ShelfView` thêm 2 dòng): dò mỗi lần trang gốc Kệ hiện, hiện ở tab Kệ sách và Lịch sử.
  - Hỏi một chạm: dải báo "N truyện mất nguồn có nguồn khớp link · Chuyển", có nút ẩn trong phiên.
  - Tự chuyển: chạy ngầm cho truyện chỉ khớp một nguồn; khớp từ 2 nguồn thì vẫn hiện dải báo.
  - Chạy lần lượt từng truyện, khớp nhiều nguồn thì lấy nguồn đầu tiên (theo thứ tự đã cài) qua bước kiểm. Truyện không chuyển được nhớ trong phiên để không gọi mạng lại. Đang có lượt Đổi nguồn thì bỏ qua.
  - Rời trang gốc Kệ hoặc mở đúng truyện đang chuyển (`ReaderView.activeBookId`) ⇒ dừng trước khi ghi truyện kế tiếp, lần hiện Kệ sau thử lại.
  - Toast: Hỏi một chạm báo số truyện đã chuyển / mục lục khác dạng / lỗi tải; Tự chuyển chỉ báo truyện đã chuyển (lý do không chuyển nằm trong log).
  - Không dò ở Chi tiết/Reader: hai màn giữ `extensionPackageId` cố định từ lúc mở, Chi tiết tìm truyện theo (link, tiện ích), nên gắn lại nguồn khi màn đang mở là màn đó mất truyện.
- **Cài đặt › Thư Viện › Truyện mất nguồn**: Hỏi một chạm (mặc định) / Tự chuyển (`MissingSourceRebindMode`, khoá `missingSourceRebindMode`).
- Giới hạn: tác vụ tải đang chờ của truyện vẫn mang nguồn cũ; thiết lập theo nguồn (bật dịch riêng của nguồn, đăng nhập, cấu hình tiện ích) theo nguồn mới; Chi tiết của truyện đang mở ở tab khác lúc chuyển thì cần mở lại.
- `CLAUDE.md` / `AGENTS.md`: thêm mục "Gắn lại nguồn khi tiện ích đã gỡ" ở Ràng buộc runtime.
- Chuyển entry `[1.3.660]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code + diff; `check_architecture.py` 1 violation nền (`JSDom`), **0 mới**. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.689] - 2026-11-03

### fix: đổi nguồn chép chương theo lô, dọn truyện cũ an toàn khi app chết

Người dùng: *"tôi đổi nguồn 1 truyện có hơn 2k chương đã tải thành đơ app sau đó thoát app luôn. nhưng vẫn chuyển được dữ liệu, tuy nhiên nguồn cũ vẫn còn"*. Lúc đổi không có TTS; truyện mới đủ chương.

- **Nguyên nhân** (suy từ code; log chỉ cho thấy main thread bị chặn ≥ 3 s lúc 21:36:44–21:36:59 và không có dòng ❌ nào của luồng đổi nguồn):
  - Chép chương đã xong, app chết trước khi lệnh xoá truyện cũ lưu xuống đĩa. Bước xoá chạy `BookTransactionCoordinator.deleteBook` trên context **main**, cascade `Book.chapters`. Worker chuyển mục lục sang SQLite (27/7, gỡ 28/7) không xoá dòng `Chapter` SwiftData, nên truyện đời đó còn hàng nghìn dòng phải cascade trên main. Bước này cũng đi tắt qua `BookStorageManager` (không huỷ tải, không xoá bìa).
  - Thứ tự cũ chuyển rồi **xoá ngay** thiết lập riêng (từ điển/rule, phiên AI, trí nhớ AI, điểm quét name) trước khi xoá truyện cũ ⇒ chết giữa chừng thì còn hai truyện, truyện cũ mất thiết lập. Không có gì dọn lại.
  - Vòng chép từng chương: mỗi chương mở/đóng 2 file, 3 lần nhảy actor, một lần commit sqlite; lỗi nuốt bằng `try?`, không tiến trình.
- **`BookSourceChangeCoordinator`** (mới, `Services/Download/SourceChange/`) nhận cả lượt từ `SearchView` (812 ⇒ 693 dòng; phần View còn ở `SearchView+SourceChange`):
  - Nhật ký `source_change/journal.json` (`BookSourceChangeJournal`) ghi **trước** tác dụng phụ đầu tiên. Trước mốc `.committed` chỉ **chép**, truyện cũ nguyên vẹn.
  - Huỷ lượt tìm đang chạy. Nguồn mới trả mục lục xong mới huỷ tác vụ tải của truyện cũ (tra lỗi thì không đụng gì) và ghi nốt lệnh ghi đang chờ của nó, rồi mới đọc mục lục để chép. Nhật ký của lượt trước chưa dọn xong ⇒ báo lỗi, không ghi đè.
  - Truyện đích cùng tiện ích + link chi tiết đã có trên máy ⇒ **dùng lại** (không tạo bản UUID trùng); tiến độ lấy theo bản đọc gần hơn, cờ kệ/lịch sử chỉ bật thêm (`BookTransactionCoordinator.mergeSourceChangeState`).
  - `BookSourceChapterCopier` chép theo lô ≤ 64 chương / ≤ 4 MB: một handle đọc + một handle ghi (`BookBinManager.copyChapterContents`), một transaction (`ChapterStore.markChaptersCached`, tra theo chỉ số). Bỏ qua chương truyện đích đã có. Overlay hiện "Đang chép chương đã tải N/M". Giữ `beginBackgroundTask`; hết hạn thì dừng giữa hai lô và báo "Bị ngắt vì app chuyển nền". Chương lỗi gom một dòng ❌; có chương lỗi ⇒ **giữ** truyện cũ.
  - Sau mốc chốt, View đóng các màn đang giữ `Book` cũ; 1,2 s sau mới xoá truyện cũ qua `BookStorageManager.deleteBooksAsync` (context nền) rồi xoá thiết lập cũ.
  - Mở app / app hoạt động lại (`MainTabView+SourceChangeRecovery`): nhật ký `.copying` ⇒ lùi (xoá truyện mới nếu lượt đó tạo ra); `.committed` ⇒ dọn nốt truyện cũ. Có toast.
- **Thiết lập riêng**: `BookSourceMigrator.copyBookScopedSettings` (chỉ chép, truyện đích có rồi thì giữ của đích) + `removeBookScopedSettings`. `AIChatHistoryStore.copySessions` nạp từng phiên, ghi mục lục một lần; `BookAIMemoryStore.copyMemory`; `AINameScanScopeStore.copy`/`remove`. Đang nghe TTS truyện cũ thì truyện cũ giữ đủ phiên AI và trí nhớ AI (trước đây vẫn bị gỡ).
- **Truyện đã nửa vời trước bản này** (không có nhật ký): mở truyện cũ ⇒ Đổi nguồn ⇒ chọn lại đúng nguồn mới. App dùng lại truyện mới đã có, chỉ chép chương còn thiếu rồi xoá truyện cũ.
- `rules.md`, `CLAUDE.md`, `AGENTS.md` ghi tên hàm mới. Chuyển entry `[1.3.659]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code + diff; `check_architecture.py` trước và sau đều 1 violation nền (`JSDom`), **0 mới**. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.688] - 2026-11-03

### fix: bật dịch trong Reader dịch lại ngay chương đang mở

Người dùng: *"tôi bật dịch lại thì nội dung chương không dịch lại ngay. phải thoát vào lại reader nó mới chịu dịch"*. Lỗi đi kèm (truyện có tiện ích nguồn đã gỡ thì bị tắt dịch): người dùng chọn **không** sửa.

- **Nguyên nhân**: `ReaderViewModel.toggleTranslation(enabled:)` chỉ gán cờ, không dựng lại đoạn. Chương dựng lúc tắt dịch có `translated == original` (`untranslatedTextResult`), nên bật lên thì `ParagraphCardView.displayText` vẫn ra chữ gốc. Tắt dịch thì đúng ngay vì chữ gốc luôn có. Thoát vào lại thì đúng vì ViewModel mới đọc lại cờ, `isTranslationFresh` thấy lệch và dựng lại. `ChapterContentRepository` không liên quan (chỉ giữ chữ gốc).
- **Reader** (`ReaderViewModel+Translation.swift`): `toggleTranslation` dựng lại chương đang hiện (`refreshParagraphItems`, gồm đoạn tiêu đề -1) khi bản đang có không khớp công tắc mới; cờ không đổi thì không làm gì (nhánh Pronouns/LuatNhan vẫn gọi lại hàm này). Chương khác trong cache tự dựng lại khi tới, như cũ. Header và sheet mục lục vốn đã theo cờ.
- **TTS đang phát cùng truyện** (`TTSManager+TranslationIdentity.swift`, `updateTranslationSetting(for:enabled:)`, gọi từ `onChange` của Reader): chữ TTS đọc và vệt highlight phải cùng hệ toạ độ với chữ Reader đang hiện.
  - Đang phát ⇒ tải lại chương hiện tại qua `ChapterContentRepository`, rồi `startSpeaking` từ đầu đoạn đang đọc với `translationEnabled` mới. Đây là tham số mới của `startSpeaking`; bỏ trống thì vẫn tra `TranslationConfigStore` như cũ.
  - Đang dừng ⇒ chỉ đổi cờ phiên và bỏ prefetch, áp từ chương sau; phần còn lại của chương đang dừng giữ chữ cũ.
  - Cờ phiên đổi ngay, nên bấm bật/tắt liên tiếp thì chỉ lượt cuối được đọc lại.
- Gom hai khối huỷ phần đã dịch sẵn giống hệt nhau (khi đổi từ điển / rule dịch nhanh) thành `invalidatePreparedTranslationState()`. `TTSManager.swift` 3500 ⇒ 3468 dòng, về dưới baseline 3470.
- Chuyển entry `[1.3.658]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code + diff; `check_architecture.py` trước sửa 2 violation nền (`JSDom`, `TTSManager`), sau sửa còn 1 (`JSDom`), **0 mới**. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.687] - 2026-11-03

### feat: các nhánh của một nhóm trong rule dịch dùng chung số {i}

Người dùng: *"nhiều any ngăn cách bởi | thật ra chỉ có một nhưng gợi ý nhập phần nghĩa lại không nhận ra"*. Đã chốt: áp **mặc định** cho mọi nhóm, không cần cú pháp riêng.

- **Parser** (`QuickTranslationRuleParser.parseGroup`): mỗi nhánh của nhóm `( | )` đánh số từ **cùng một số**; sau nhóm, số tiếp theo nối từ nhánh nhiều token nhất. Giống `(?|…)` của PCRE.
  - `第<n><L><any>(\(<any>\)|（<any>）|【<any>】)<$>` giờ chỉ có `{0}…{3}`, trong đó `{3}` là nội dung ngoặc của nhánh khớp.
  - `(<n>|<a><d>)<L>`: `<n>` = 0; `<a>` = 0, `<d>` = 1; `<L>` = 2.
  - Nhóm lồng áp luật theo từng tầng. `|` ngoài nhóm vẫn là chữ thường.
  - Matcher không đổi: nhánh không khớp để `{i}` rỗng như trước.
- **Màn sửa rule** (`QuickTranslationRuleDraftAnalyzer.segments`):
  - Số `{i}` của chip lấy từ AST của parser, không tự đếm. Mẫu đang gõ dở chưa parse được thì lùi về đánh số phẳng.
  - `Segment` thêm `tokenPosition` (vị trí duy nhất). Thanh chỉnh độ dài định vị chip bằng vị trí này (`replacing(tokenPosition:)`, `applyTokenSpec`), nên chỉnh `<any>` ở nhánh 2 không sửa nhầm nhánh 1.
- **Gợi ý ô Bản dịch và dải chip `{i}`:**
  - Mỗi số một chip; nhãn VoiceOver ghép các token chung số.
  - Token chưa dùng **không còn tô đỏ như lỗi**, vì `UNUSED_CAPTURE` chỉ là cảnh báo từ 1.3.339. Câu "mọi token phải được dùng" đổi thành "{i} chỉ dùng để khớp, không xuất ra bản dịch". Lời cảnh báo của compiler ghi theo số `{i}`.
- Câu giải thích token ở màn sửa rule và đoạn token trong `CLAUDE.md` / `AGENTS.md` ghi luật chung số.
- **Đổi hành vi rule cũ:** rule có token ở từ 2 nhánh trở lên của cùng một nhóm sẽ bị dời số. `{i}` vượt số token thì rule báo lỗi và không chạy; còn trong khoảng thì trỏ sang token khác. Bộ rule mặc định tải về (633 rule) đã quét: không rule nào bị ảnh hưởng.
- **Kiểm chứng:** đọc code + diff; `check_architecture.py` 2 violation nền, **0 mới**. Dò tay trên code các mẫu:
  - `(<n>|<a><d>)<L>`
  - `((<n>|<a>)<d>|<any>)`
  - `a|<n>`
  - `\(` và `\|`
  - mẫu thiếu `)`
  - rule ngoặc ở trên

  Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.686] - 2026-11-03

### feat: neo đầu/cuối dòng <^> <$> và <any> bắt mọi ký tự trong rule dịch

Người dùng: *"có token xác định đầu dòng trong rule dịch chưa, nếu chưa thì thêm vào"* và *"token any sửa lại bắt mọi ký tự và tăng length lên"*. Chốt bằng bảng chọn:
- Thêm `<^>` và `<$>`, bỏ qua khoảng trắng đầu/cuối dòng.
- `<any>` bắt mọi ký tự trừ xuống dòng, mặc định 1–50, chỉnh được tới 100.

- **Neo `<^>` / `<$>`** (`QuickTranslationRuleLineAnchor`, `QuickTranslationRuleParser+LineAnchor`, mới):
  - Rộng 0 và **không sinh capture**, nên số `{i}` của rule giữ nguyên.
  - `<^>` đúng khi từ đầu chuỗi (hoặc sau `\n`/`\r`) tới vị trí hiện tại chỉ có khoảng trắng; `<$>` đối xứng ở cuối dòng. Khoảng trắng thụt nằm ngoài vùng khớp nên giữ nguyên trong bản dịch.
  - Ghép `|`, ghi độ dài `:min-max` hoặc thêm `?` sau neo ⇒ lỗi `UNKNOWN_TOKEN_NAME` kèm câu giải thích.
- **Giao diện neo:**
  - `QuickTranslationRuleTokenSettings.Kind` thêm `lineStart = "^"`, `lineEnd = "$"` vào **cuối** danh sách, có công tắc ở Cấu hình token (chung và riêng theo truyện).
  - Có nút trong bảng token và gợi ý trên bàn phím.
  - Chip ở màn sửa rule không có thanh độ dài và không được đánh số.
  - Phần giải thích token có ví dụ `<^>第<n>章 = Chương {0}`.
- **`<any>`:**
  - Nuốt **mọi** ký tự, kể cả dấu câu và khoảng trắng; chỉ dừng ở xuống dòng.
  - Không ghi độ dài ⇒ 1–50. Thanh chỉnh độ dài tới 100 (`TokenSpec.defaultRangeMax` / `lengthUpperBound`); token khác giữ 1–12 và trần 20.
  - Được nuốt **trọn** Name riêng: capture mang `allowsEnclosedNames`, `+NameProtection` chấp nhận. Chỉ không được bắt đầu hay kết thúc giữa một Name.
  - Theo sau là chữ cố định thì chỉ thử những độ dài có chữ đó ngay sau, nên vẫn nhẹ dù dài hơn.
  - Ví dụ: `<any:1-6>说` trên `走吧，他说` giờ lấy `走吧，他`; `第<n>章<any>` giờ khớp `第12章 风起`.
- **Đổi hành vi rule cũ:** `<any>` không ghi độ dài giờ nuốt tới 50 ký tự, kể cả dấu câu.
- `CLAUDE.md` / `AGENTS.md`: cập nhật đoạn token ở mục Dịch thuật VietPhrase.
- Chuyển entry cũ nhất sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng:** đọc code + diff; `check_architecture.py` 2 violation nền, **0 mới**. Tự soát tay các ca:
  - `<^>第<n>章` khớp `　　第12章 风起` mà không khớp `他说第12章`.
  - `<any>的<any>` với Name `张三` nằm trọn trong cụm vẫn khớp.

  Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.685] - 2026-11-03

### feat: sheet Bộ lọc hiện chữ đã dịch khi nguồn bật dịch

Người dùng: *"hãy hiển thị nội dung bộ lọc đã dịch nếu ext config dịch"*. Chốt: chỉ sheet Bộ lọc, màn Cấu hình tiện ích giữ nguyên văn.

- `ExtensionFilterSheet`:
  - Lúc nạp, nếu nguồn bật dịch (`TranslationConfigStore.isTranslationEnabled(bookId: nil, packageId:, isChineseSourceHint:)`, nguồn tiếng Trung tự bật) thì gom tiêu đề, dòng phụ và lựa chọn của các mục lọc có chữ Hán, rồi dịch **ngoài main** bằng `translateMeta` (bỏ trùng) vào bảng `translations`.
  - Chưa dịch xong thì hiện chữ gốc.
- `ExtensionConfigFieldRow` thêm `displayText`, áp cho tiêu đề, dòng phụ, nhãn lựa chọn trong menu, lựa chọn đang hiện và tiêu đề màn danh sách. **Giá trị lưu vẫn là chữ gốc**, vì script nhận đúng chuỗi đó. Mặc định giữ nguyên nên màn Cấu hình không đổi.
- Phần E (thứ tự explore/home) người dùng đã huỷ.
- Chuyển entry cũ nhất sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng:** đọc code + diff; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows), chưa thử trên máy. Cần thử: mở Bộ lọc của qidian/qimao khi nguồn bật dịch, chọn một lựa chọn đã dịch rồi Áp dụng và kiểm danh sách lọc đúng.

## [1.3.684] - 2026-11-03

### feat: phồn→giản trước khi dịch trang trình duyệt, chung và riêng theo tên miền

Người dùng: *"thêm cài đặt phồn -> giản trước khi dịch trang"*. Đã chốt bằng bảng chọn: có công tắc chung (mặc định tắt) và chỉnh riêng theo tên miền, còn *"Phồn → giản thụt vào trong Tự dịch QT để biết nó là cài đặt con của Tự dịch QT"*.

- **Luật** `BrowserTranslatePolicy.convertsTraditional(urlString:)`: lấy chỉnh riêng của tên miền trước (`BrowserSitePreference.convertsTraditional`, có gộp tên miền cha); không có thì theo công tắc chung `browserTranslateConvertsTraditional`. Không theo tiện ích khớp URL.
- **Áp cho:** dịch QT cả trang (tự dịch lẫn nút dịch bấm tay) và sheet "Dịch QT" khi bôi đen. `BrowserPageTranslator` đọc cờ trên main ở mỗi lô rồi chỉ chuyển `Bool` sang luồng nền.
- **Cài đặt › Trình duyệt:** section mới "Dịch trang", công tắc "Chuyển phồn thể → giản thể trước khi dịch" kèm nút "?" giải thích (trang giản thể có thể bị đổi vài chữ mập mờ).
- **Bảng khiên:** công tắc con "Phồn → giản" thụt dưới "Tự dịch QT", luôn hiện kể cả khi tự dịch đang tắt. Dòng phụ "Theo cài đặt chung" / "Bật/Tắt cho <tên miền>"; nút "Dùng cài đặt chung" xoá chỉnh riêng của cả tên miền cha.
- **Dịch lại ngay:** đổi công tắc thì tab đang dịch được tắt rồi bật lại dịch trang, không nạp lại. Đổi công tắc chung chỉ dịch lại các tab không có chỉnh riêng.
- **Trang đã chỉnh riêng:** thêm chip "Phồn → giản" / "Giữ phồn thể".
- **Backup:** công tắc chung tự vào backup. Chỉnh riêng nằm ở `site_preferences.json` nên không được backup, giống "Tự dịch QT".
- **Chưa làm:** tiêu đề tab dịch qua `translateMeta` vẫn chưa chuyển phồn→giản.
- Chuyển entry cũ nhất sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng:** đọc code + diff; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows), chưa thử trên máy. Cần thử:
  - Trang phồn thể có/không bật công tắc.
  - Công tắc riêng theo tên miền thắng công tắc chung.
  - Dịch lại ngay khi đổi công tắc.
  - Sheet Dịch QT.

## [1.3.683] - 2026-11-03

### feat: bộ rule dịch tên chương, ưu tiên riêng > tên chương > chung

Người dùng: *"rule dịch thêm 1 phạm vi rule dành cho chương nữa; nhớ thêm vào hub từ điển để quản lý; nhớ backup các rule của chương; độ ưu tiên rule riêng > rule tên chương > rule chung; rule tên chương chỉ dùng để dịch tên chương thôi"* và *"thêm option lưu vào bộ tên chương khi bấm lưu ở màn hình thêm rule"*.

- **Phạm vi thứ ba** `QuickTranslationRuleScope.chapterTitle`:
  - Lưu ở file `translate/QuickTranslateChapterRules.txt`, do store mới `QuickTranslationRuleChapterStore` quản lý (nạp lười, tôn trọng công tắc tổng). Có file tắt riêng `QuickTranslateChapterRulesDisabled.txt`.
  - Hạng `scopeRank`: riêng 0, tên chương 1, chung 2 (`QuickTranslationRuleScope.bookRank/chapterTitleRank/globalRank`). Mặc định của compiler đổi sang hạng chung. Thứ tự đi qua tiêu chí "bộ rule" có sẵn trong cấu hình ưu tiên.
- **Chỉ áp khi dịch tên chương:**
  - `translateChapterTitle(WithMapping)` chạy trong cờ task-local `TranslationReadContext.appliesChapterTitleRules`. Engine và chẩn đoán chỉ trộn bộ tên chương khi cờ bật.
  - Khoá cache `translateText`, cache rewrite và memo mapping có thêm cờ này, nên dòng tên chương và dòng nội dung trùng chữ không dùng chung kết quả.
  - Generation của store đi vào `translationGenerationToken`.
  - Mọi đường dịch tên chương đều có bộ này: Reader đoạn -1, TTS chunk -1, widget, mục lục, xuất TXT, `Qt.translate` chapter_name.
- **Tắt rule:** file tắt riêng truyện vẫn tắt mẫu ở **mọi** bộ. File tắt tên chương chỉ tắt rule của bộ tên chương, file tắt chung chỉ tắt rule của bộ chung. Có trạng thái chip mới `.disabledForChapterTitles` ("tắt ở bộ tên chương").
- **Giao diện:**
  - Hub Từ điển có mục **Rule Tên chương** giữa Riêng và Chung. Cài đặt › Quản lý rule dịch có thêm "Danh sách rule tên chương".
  - Danh sách, hàng rule và menu nhập/xuất/tắt chạy đúng 3 phạm vi: nút + lưu đúng bộ đang mở, tên file xuất `QuickTranslateChapterRules.txt`, "chia sẻ cả bộ" chỉ cho bộ riêng.
  - Nút Chuyển thành menu chọn bộ đích (thay `opposite`).
  - Màn thêm rule có thêm **"Lưu vào bộ rule tên chương"**, mặc định của nút Lưu giữ như cũ. Có truyện ⇒ menu ba mục. Không có truyện ⇒ chạm lưu vào bộ mặc định (mở từ danh sách tên chương thì là bộ tên chương), nhấn giữ để chọn bộ khác.
  - Reader: chip rule trên dòng tiêu đề chương soi cả bộ tên chương. Nhấn giữ chip có tắt ở bộ tên chương và chuyển sang hai bộ còn lại.
- **Backup:** gói và khôi phục `config/QuickTranslateChapterRules.txt` + `config/QuickTranslateChapterRulesDisabled.txt`. Khôi phục xong thì dọn cache dịch và phát một thông báo. `BackupLibraryFingerprint` gộp các file cấu hình thành vòng lặp (thêm 2 file ⇒ mỗi máy sẽ tự sao lưu thêm một lần sau khi cập nhật).
- **Bình luận** (anh Bửu nhờ qua phiên bình luận): dòng mô tả dưới tên, ở cả bình luận lẫn trả lời, đổi sang xám mờ `.tertiary` để tách khỏi nội dung (người dùng chọn kiểu B trên mockup).
- `CLAUDE.md` / `AGENTS.md`: thêm đoạn "Tên chương" ở mục Dịch thuật VietPhrase.
- Chuyển entry cũ nhất sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng:**
  - Đọc code + diff; `check_architecture.py` 2 violation nền, **0 mới**.
  - Đã soát thứ tự khoá: `translationGenerationToken` chỉ đọc bộ đếm của store, `notifyChange` chạy ngoài khoá.
  - Không build tại chỗ (Windows), chưa thử trên máy. Cần thử:
    - Rule tên chương thắng rule chung, thua rule riêng.
    - Nội dung chương không bị rule tên chương ảnh hưởng.
    - Thêm/sửa/tắt/chuyển/nhập/xuất ở hub.
    - Backup rồi khôi phục.
    - Màu mô tả bình luận.

## [1.3.682] - 2026-11-03

### feat: token <any> khớp cụm ký tự bất kỳ trong rule dịch

Người dùng: *"thêm token cụm ký tự bất kỳ trong rule dịch, (nó dùng để xác định một cụm ký tự không cần biết nghĩa nó là gì, chỉ cần biết nó độ dài từ bao nhiêu đến bao nhiêu, trả về phần nghĩa sẽ là cụm nguyên bản đó)"*. Chốt bằng bảng chọn: tên `<any>`, dừng ở dấu câu và khoảng trắng, rule có `<any>` mà không có chữ cố định thì báo lỗi.

- **Cú pháp** `<any>` / `<any:min-max>` (mặc định 1–12, `QuickTranslationRuleParser`): khớp một cụm ký tự bất kỳ, capture trả **nguyên văn**. Chuỗi sau rule vẫn được tách từ và dịch từ điển như phần còn lại của dòng, nên `<any:1-6>的<any:1-6> = {1} của {0}` đảo trật tự rồi dịch đúng. Không ghép được với token khác bằng `|` (báo lỗi).
- **Khớp** (`QuickTranslationRuleMatcher.walkAnyRun`):
  - Nuốt mọi ký tự trừ dấu câu (Unicode P*) và khoảng trắng/xuống dòng.
  - Thử dài → ngắn có lùi như token số; không cắt giữa cặp surrogate.
  - Dừng ở ranh giới Name riêng, nhờ đó vẫn lùi về độ dài ngắn hơn thay vì bỏ cả lượt khớp.
- **Ưu tiên**: `<any>` có hạng độ hẹp 7, rộng nhất (`QuickTranslationRuleNumeralNarrowness.anyRunRank`). Khi hoà mọi tiêu chí, nó thua mọi token ký tự khác; `wildcardCapacity` cộng `maxLength`.
- **Lỗi nặng mới** `ANY_WITHOUT_LITERAL` (`QuickTranslationRuleIssue`, `QuickTranslationRuleCompiler`): rule có `<any>` mà không có chữ cố định nào thì bị loại khi nạp, màn sửa rule báo *"Rule có <any> phải có ít nhất một chữ cố định"*. Lỗi này báo thay cho `NO_LITERAL_ANCHOR` ở cùng chỗ.
- **Giao diện**:
  - Công tắc `<any>` ở Cấu hình token rule (chung và riêng theo truyện).
  - Nút trong bảng token và hàng gợi ý trên bàn phím.
  - Phần giải thích token có ví dụ.
  - `QuickTranslationRuleTokenSettings.Kind.any` nối vào **cuối** danh sách, nên chữ ký cache dịch đổi một lần. Khoá cài đặt `quickTranslateRuleTokenAnyEnabled` tự vào backup.
- Chuyển entry cũ nhất sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**:
  - Đọc code + diff; `check_architecture.py` 2 violation nền, **0 mới**.
  - Tự soát tay 4 ca:
    - `我的剑` ⇒ `剑 của 我`.
    - `走吧，他说` với `<any:1-6>说` chỉ lấy `他`.
    - `<any:2-4>` đứng một mình bị lỗi nặng.
    - `第<n>章<any:1-30>` **không** khớp `第12章 风起` vì khoảng trắng chặn `<any>`; muốn chịu cả hai dạng thì viết `第<n>章( )?<any:1-30>`.
  - Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.681] - 2026-11-03

### fix: tên chương dịch như nội dung, phồn→giản khi xuất và mục lục comic theo cấu hình truyện

Người dùng: *"điều tra logic dịch tên chương giúp tôi"*. Báo cáo điều tra liệt kê 18 chỗ hiện tên chương và 14 điểm lệch. Sau đó chốt bằng bảng chọn: *"translateChapterTitle không dịch kiểu translateChapterTitle, dịch như dịch content bình thường thôi vì bây giờ tôi đã có rule <L> rồi"*, *"Xuất TXT bỏ qua phồn→giản là quên làm"*, giữ `title_trans` làm mới bằng tay, rồi duyệt plan.

- **Tên chương dịch y như nội dung** (`TranslateUtils.translateChapterTitle`): bỏ hai regex cứng `第N章` ⇒ "Chương N: …" và số Ả-rập `"1. …"` ⇒ "Chương 1: …", cùng `chapterUnitMap`, `chineseNumberToInt` và 4 regex trong `TranslateUtils+MappingMemo`. Hàm còn lại: phồn→giản → trim → `chapterTitleCache` → `translateContent`. Nhãn chương do rule dịch nhanh `<L>` của người dùng lo. Tên không có chữ Hán giữ nguyên, nên "Dịch lại tên chương", nhập TXT/EPUB/comic/video và xuất TXT không còn biến `1. Mở đầu` thành `Chương 1: Mở đầu`. Bỏ tham số `applyingQuickTranslationRules` của hàm này; `Qt.translate(..., {chapter_name})` nay áp rule dịch chung.
- **Phồn→giản theo công tắc của truyện** (`TranslationConfigStore.convertsTraditionalToSimplified(bookId:)`, mới): xuất TXT áp cho cả tên lẫn nội dung (trước quên). Mục lục tab Chi tiết và comic đi theo luật của sheet mục lục Reader: bật phồn→giản thì bỏ bản lưu và dịch sống có chuyển. Chỉ mục tìm online ở Chi tiết thêm cờ này vào khoá.
- **Comic** theo công tắc dịch của truyện/nguồn (`TranslationConfigStore`, nghe `didChangeNotification`), không còn theo công tắc chung. Tên chương dịch ngoài main (`ComicChapterTitleTranslator`, `ComicReaderViewModel+TitleTranslation`, mới); lúc chưa dịch xong thì tạm hiện bản lưu `titleTrans`.
- **Trình phát video** dịch tên nhóm tập (`isSection`) một lần sau khi nạp, theo công tắc truyện + phồn→giản; tập thường giữ nguyên.
- **Ô tìm chương** ở Chi tiết (đã lưu và online) và comic dùng `ChapterTitleSearchMatcher` như Reader: không phân biệt hoa/thường và dấu.
- **Dọn dẹp**:
  - Lưới tập video ở Chi tiết dịch vào `@State` khi mục lục/từ khoá/thứ tự/công tắc đổi, không dịch mọi tập ở mỗi lần vẽ.
  - Sheet mục lục Reader bỏ lớp dịch thứ hai và việc ghi `@State` trong `body` (`displayTitleCache`, `warmNearbyTitles`).
  - Xoá code chết `ReaderView.displayedBookTitle`.
  - Lưu nền `title_trans` ở Chi tiết và "Dịch lại tên chương" chờ từ điển nạp xong.
- **Giữ nguyên theo người dùng chọn**:
  - `title_trans` chỉ làm mới bằng tay. Truyện cũ còn bản lưu dạng "Chương 12: …" tới khi bấm "Dịch lại tên chương".
  - Kệ sách và hộp thư theo công tắc chung.
  - Rule TOC và "Loại bỏ tiêu đề chương trùng" không đổi.
- Chuyển entry cũ nhất sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**:
  - Đọc code + diff; `check_architecture.py` 2 violation nền, **0 mới**.
  - Không build tại chỗ (Windows) — CI là cổng biên dịch.
  - Chưa thử trên máy. Cần thử:
    - Rule `<L>` cho tên chương ở Reader, TTS và mục lục sau "Dịch lại".
    - TXT tiếng Việt `1. …` giữ nguyên tên.
    - Phồn→giản ở Chi tiết, comic và file TXT xuất.
    - Comic nguồn Trung khi công tắc chung tắt.
    - Nhãn nhóm tập video.
    - Tìm "kiem" ra "Kiếm".

## [1.3.680] - 2026-11-03

### feat: bình luận hiện avatar người bình luận và các trả lời

Người dùng: *"app chưa làm: replies của comment chưa được hiển, avatar cũng chưa được dùng để hiển thị avatar người comment. xem ext qimao của đường đen để hiểu rõ hơn"*. Chốt bằng mockup + bảng chọn (thẻ Chi tiết chỉ dòng "N trả lời", xổ tại chỗ, mô tả dưới tên, hàng nút kiểu B, qimao tải trả lời khi bấm) rồi duyệt plan.

- **Đọc dữ liệu** (`ExtensionManager+ItemParsing.listItem`): mỗi item đọc thêm `avatar` (resolve như bìa: host item → `source`) và `replies` theo template script bình luận của hợp đồng (mảng cùng dạng bình luận, lồng nhau) — app hiện **một** cấp, trả lời của trả lời đứng ngay sau trả lời cha (`commentReplies`, sâu tối đa 8), trả lời không có nội dung lẫn mô tả bị bỏ. Khoá riêng của FreeBook (hợp đồng không có): `reply_source: {input, script}` (`CommentReplySource`, mới) + `reply_count` = trả lời **tải khi bấm**, chỉ dùng khi `replies` rỗng. `ExtensionItemResult` thêm `avatar`, `replies`, `replySource`, `replyCount` (đều có mặc định).
- **Hàng bình luận dùng chung** (`CommentRowView`, mới, `Views/BookDetail/Comments/`): thay khối chép trùng ở thẻ Chi tiết (`CommentSectionView`) và Tất cả bình luận (`AllCommentsView`). Avatar tròn 32pt / 36pt (`CommentAvatarView`, mới — không có URL thì hình người xám như cũ, đang tải / lỗi thì placeholder hình người), tên, dòng mô tả **dưới** tên (trước nằm bên phải tên; không có nội dung thì mô tả làm thân, không lặp), nội dung 3 dòng. Có trả lời ⇒ cùng hàng với "Xem thêm" (trái) là "💬 N trả lời ⌄" màu nhấn (phải); mặc định thu gọn ở cả hai màn.
- **Khối trả lời xổ tại chỗ** (`CommentRepliesBlock`, mới): thụt vào, vạch dọc trái; mỗi trả lời avatar 22pt, tên, mô tả, nội dung 3 dòng có "Xem thêm" nhỏ; tên / mô tả / nội dung dịch như bình luận. `replies` lồng sẵn ⇒ hiện ngay; `reply_source` ⇒ lần mở đầu gọi `script(input, page)` qua `SourceRuntime.executeCustomScript`, "Đang tải trả lời…", lỗi + "Thử lại", "Tải thêm trả lời" khi còn trang. Trang đã tải giữ ở hàng cha ⇒ thu gọn / mở lại không tải lại. Khối dài hơn 3 trả lời có "Thu gọn" ở đáy. Số trên nút: lồng sẵn = số trả lời có thật; tải khi bấm = `reply_count`, không khai ⇒ "Xem trả lời".
- **Thành phần chung**: `ExpandableTextView` thêm `toggleFont` và `trailingAccessory` (nút phụ cùng hàng "Xem thêm"; mặc định như cũ). `RemoteCoverImage` thêm `placeholderSymbol` (mặc định `photo`). Hàng bình luận gắn `.buttonStyle(.borderless)` để các nút trong một hàng `List` nhận chạm riêng.
- `CLAUDE.md` / `AGENTS.md`: thêm một câu ở mục Extension JavaScript.
- Tiện ích (repo riêng, cùng đợt): STV v24 + qidian v27 tách trả lời khỏi danh sách bình luận gốc (trước hiện thành bình luận riêng lẻ) + avatar; qimao v3 avatar + `reply_source` (`reply.js`), bỏ kiểu gộp trả lời vào nội dung.
- Chuyển entry `[1.3.650]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code + diff; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy — cần thử: avatar hiện ở thẻ / Tất cả bình luận / trả lời, bấm "N trả lời" xổ đúng bình luận và không kích hoạt "Xem thêm" (và ngược lại) trong hàng `List`, qimao tải / tải thêm / thử lại trả lời, cuộn hàng đang tải ra khỏi màn rồi quay lại.

## [1.3.679] - 2026-11-03

### fix: app đơ khi cuộn tới cuối danh sách do chân danh sách tự kích hoạt lại

Người dùng (sau 1.3.678): *"có lỗi vuốt xuống cuối danh sách thì đơ app, lỗi bị sau khi làm Vòng xoay cuối danh sách"*; thêm *"chưa thấy chữ "Đã hết" đã đơ rồi"*. Duyệt plan sửa.

- **Nguyên nhân (suy từ code, chưa tái hiện)**: `LoadMoreFooter` của 1.3.678 ghi `@State spinnerToken = UUID()` trong `onAppear` ở **mọi** trạng thái để dựng mới vòng xoay. Giá trị mới mỗi lần ⇒ hàng cuối của `List` / `LazyVGrid` vẽ lại → "hiện" lại → ghi tiếp, vòng lặp trên main thread; ở trạng thái đang nạp mỗi vòng còn sinh thêm một `Task` nạp trang kế ⇒ đơ ngay khi vòng xoay vừa lộ ra ở cuối (trước cả khi tới "Đã hết").
- **`LoadMoreFooter` không giữ state**: bỏ `spinnerToken` + `.id` bên trong; `onAppear` chỉ gọi nạp trang kế khi đang nạp. Vòng xoay mới cho mỗi trang do nơi dùng gắn `.id(số mục)` — cách màn Tìm và các lưới đã chạy ổn trước 1.3.678; thêm cho ba chỗ còn thiếu: danh sách Khám phá / Thể loại (`DiscoveryNovelsLayoutView`, số truyện), Kệ / Lịch sử kiểu Danh sách (`ShelfBooksLayoutView`, số truyện đang hiện), Tất cả bình luận (số bình luận). Trang không thêm mục nào thì số không đổi, không kích hoạt lại.
- **Gia cố phụ**: `AppAccentColor.applyToWindows()` bỏ qua cửa sổ đã đúng màu — trước đây mỗi lần một sheet / cửa sổ nổi có `.appAccentTint()` hiện là `tintColorDidChange` lan khắp cây view.
- Chuyển entry `[1.3.649]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code + diff; `LoadMoreFooter.swift` không còn `@State` / `UUID()`; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy — cần thử: cuộn tới cuối Khám phá / Thể loại / Tìm / Bình luận / Kệ / Lịch sử (cả kiểu Danh sách lẫn lưới) không đơ, vòng xoay vẫn hiện ở mỗi lần nạp trang kế, hết trang hiện "Đã hết".

## [1.3.678] - 2026-11-03

### fix: vòng xoay cuối danh sách, nút chọn loại chỉ icon và màu nhấn tuỳ chọn

Người dùng: *"các danh sách vô hạn có vẻ đang thiếu icon xoay tròn cuối trang trong lúc đang load phần kế tiếp nhỉ?"*; thêm *"nút chọn tất cả truyện chữ truyện tranh phim bên ô tìm kiếm của chọn nguồn hãy chỉ hiển thị icon của option đã chọn thôi"* và *".tint(.white) đổi thành màu khác đi … thêm config cho tint đi, thêm 1 nav vào màn setting giao diện … xem trước UI … Bỏ option trắng đi nhé, mặc định xanh ngọc"*. Chốt bằng mockup + bảng chọn rồi duyệt plan, gộp một commit.

- **Chân danh sách cuộn vô hạn** (`LoadMoreFooter`, mới): vòng xoay khi đang nạp trang kế; "Không tải được trang kế" + "Thử lại" khi trang kế lỗi hết 3 lượt tự thử; "Đã hết · N truyện" (phim / bình luận) giữa hai vạch mờ khi hết trang. Vòng xoay được dựng mới mỗi lần chân hiện ra — `ProgressView` trong hàng `List` bị tái dùng hiện trống từ lần thứ hai, lý do "thiếu vòng xoay". Áp cho Khám phá + Thể loại/nhãn (`DiscoveryNovelsLayoutView`, cả danh sách lẫn lưới), Tìm trong một nguồn, Tất cả bình luận, Kệ / Lịch sử (nạp trên máy, "Đã hết" chỉ khi danh sách dài hơn một lượt 50). Thời điểm nạp giữ nguyên (người dùng chọn), không có nút "Xem thêm".
- **Bộ nạp báo lỗi trang kế**: `PaginatedNovelLoader.loadMoreError` + `retryLoadMore()`; `SearchPagingState.fail(message:)` thay `stop()` (trước đây tắt im lặng) + `retryLoadMoreSearchResults()`; `AllCommentsView` cùng kiểu (trước đây vòng xoay treo mãi). Trong lúc chờ tự thử lại vẫn giữ cờ đang nạp ⇒ không nạp chồng. Kéo làm mới / áp bộ lọc xoá lỗi.
- **Nút chọn loại ở ngăn kéo Chọn nguồn** (`ExtensionKindMenuButton`): nút tròn 40 × 40 chỉ có icon 17pt nửa đậm của loại đang chọn (cỡ không đổi theo tên loại); tên loại nằm trong menu (✓) và nhãn VoiceOver.
- **Màu nhấn tuỳ chọn** (`AppAccentColor`, mới — Xanh ngọc mặc định, Xanh dương, Cam hổ phách, Chàm; bỏ trắng): Cài đặt › Chung › Giao diện thêm hàng "Màu nhấn" (chấm màu + tên) mở `AccentColorSettingsView` (mới — bốn màu + ô xem trước nền tối / nền sáng bằng thành phần thật như mockup). Áp bằng `.appAccentTint()` (mới, `.tint` + `.accentColor`, đọc `@AppStorage` ⇒ chọn là đổi ngay) ở `MainTabView` (thay `.tint(.white)`) và gốc các cửa sổ / màn mở bằng UIKit không thừa hưởng tint: ngăn kéo `…`, widget TTS + sheet cài đặt / hẹn giờ, Thông báo của hub, trình duyệt / mã xác minh Legado, AI, trình phát video. Phần UIKit đổi qua `applyToWindows()` (gán `tintColor` mọi cửa sổ) khi modifier hiện ra và khi đổi màu.
- **Theo màu nhấn**: công tắc (bỏ `SwitchToggleStyle(tint: Color(white: 0.35))` ở 31 chỗ, người dùng chọn); gỡ `.tint(.white)` cục bộ ở các màn TTS / VieNeu / Nghi, thanh trượt, thanh tiến độ; trạng thái đang chọn đang tô trắng cứng sang kiểu chip của `ExtensionKindFilterBar` (tab Kệ/Lịch sử, tab danh mục Khám phá, tab Chi tiết/Mục lục, nhóm + ô tập đang xem ở lưới tập video, nút hẹn giờ TTS, "Áp dụng" của sheet Bộ lọc, dấu ✓ của vài màn chọn); chấm báo (Thông báo, nút lọc); `.appFilled` mặc định màu nhấn (chữ trắng như mockup).
- **Giữ trắng**: comic, trình phát video (thanh tua, icon cố định `Color.white`), chữ / vòng xoay trên ảnh, `AppLoadingView`, lớp phủ tối của Reader. Vòng xoay ở `ReaderHeaderFooterOverlayView` theo màu chữ của theme (trước vô hình ở nền Sáng).
- **Luật `WHITE_TINT_FILL` giữ nguyên** (người dùng chọn), chỉ sửa lý do trong `check_architecture.py`, `rules.md`, `CLAUDE.md` / `AGENTS.md` (mục màu nhấn viết lại) và chú thích code từng nói "màu nhấn trắng".
- Chuyển entry `[1.3.648]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code + diff; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy — cần thử: vòng xoay hiện ở mọi lần nạp trang kế (cả kiểu Danh sách), "Thử lại" sau lỗi, đổi màu ở Cài đặt là cả app + cửa sổ nổi + menu/hộp thoại UIKit đổi ngay, công tắc trong widget TTS, chữ trắng trên nút đặc Xanh ngọc có đủ rõ.

## [1.3.677] - 2026-11-03

### fix: ngăn kéo chọn nguồn chọn loại bằng menu, icon lọc hình phễu, ô tìm và tên tab ở Kho tiện ích

Người dùng (sau 1.3.675–676): *"nút nsfw ngang với title chọn nguồn; thêm nút select để chọn tất cả, truyện chữ, truyện tranh, phim … bên cạnh ô tìm kiếm; bỏ thanh chọn … vì kéo scroll đang xung đột với vuốt đóng; dùng icon bộ lọc khác … giống y như mockup; sheet bộ lọc … nút reset … giảm size nút áp dụng"*; thêm *"áp dụng cho nút lọc của kho tiện ích luôn, đồng bộ nút search của tìm kiếm chương cho cả kho tiện ích và legado; đổi tên 2 tab con … tiện ích freebook và tiện ích legado"*. Chốt bằng mockup rồi duyệt plan.

- **Ngăn kéo chọn nguồn**: viên NSFW (`ExtensionNsfwToggle`, mới) lên dòng tiêu đề "Chọn nguồn" — `SideDrawerMenu` thêm tham số `titleAccessory` (mặc định không có, menu ⋯ khác không đổi). Bỏ hàng chip loại (kéo cuộn ngang tranh với vuốt đóng); cạnh ô tìm là nút chọn loại dạng menu `ExtensionKindMenuButton` (mới: viên thuốc 40pt icon + tên + ↕; Tất cả · Truyện chữ · Truyện tranh · Phim, ✓ ở mục đang chọn; vẫn khoá `discoveryKindFilter`).
- **Icon lọc hình phễu**: asset vector `TablerFilter` (Tabler Icons `filter`, MIT — `Docs/ThirdParty/Tabler-Icons-LICENSE.txt`), `AppGlyph.filter`; phần vẽ dùng chung `FilterGlyph` (mới — tròn / thanh tiêu đề / cạnh ô tìm, chấm trắng khi đang lọc). Dùng cho nút lọc tiện ích (Khám phá, danh sách thể loại, màn Tìm) và nút lọc của Kho tiện ích (thay `line.3.horizontal.decrease.circle` tô cam).
- **Sheet Bộ lọc**: header chỉ còn "Áp dụng" nhỏ (viên thuốc 28pt, chữ 13pt — người dùng yêu cầu, nhỏ hơn nút chữ header chuẩn 17pt); ↺ Đặt lại nằm trong khung, cùng hàng tiêu đề mục đầu ("Sắp xếp") qua `ExtensionConfigFieldRow.labelAccessory` (mới, màn Cấu hình không dùng); mục đầu không phải ô chọn ⇒ ↺ đứng riêng ở đầu khung.
- **Kho tiện ích**: hai tab đổi tên "Tiện ích FreeBook" · "Tiện ích Legado" (cả tiêu đề ngăn kéo ⋯). Ô tìm của cả hai tab thành viên thuốc kiểu mục lục `ChapterTOCSearchField` ("Tìm kiếm N tiện ích" / "Tìm kiếm N nguồn"), cách tìm giữ nguyên. `ChapterTOCSearchField` tắt tự sửa chính tả.
- Chuyển entry `[1.3.647]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code + diff; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy — cần thử: menu chọn loại mở được trong ngăn kéo (cửa sổ nổi riêng), vuốt đóng ngăn kéo không còn vướng, icon phễu hiện đúng (asset SVG), ↺ cùng hàng "Sắp xếp".
