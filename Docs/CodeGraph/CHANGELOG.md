# CHANGELOG - Nhật ký Thay đổi CodeGraph FreeBook

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **FreeBook**.

## [1.3.668] - 2026-10-31

### fix: thanh tab tự vẽ trong trang gốc, back về không giật

Người dùng: *"bạn làm màn hình trong full xấu quá, khi từ màn hình full về trang đầu có thanh tab thì cảm giác bị giật màn hình khi hiển thị lại thanh tab. Tham khảo cách hiển thị của reader"*; chọn "thanh tab tự vẽ", duyệt plan.

- **Nguyên nhân**: 1.3.660 ẩn thanh tab hệ thống ở trang đẩy vào bằng `.toolbar(.hidden, for: .tabBar)` (đổi theo kiểu tiêu đề). Lúc back, SwiftUI hiện thanh lại **trễ** hơn trang gốc ⇒ trang gốc co lại một nhịp — đúng lỗi Reader từng gặp (b12ddee7, sửa bằng `fullScreenCover`: cover phủ cả thanh nên thanh không bao giờ ẩn/hiện).
- **Thanh tab tự vẽ** (`MainTabBar`, mới, `Views/Common/MainTabBar/`): 4 mục icon + chữ (danh sách `items` dùng chung với `.tabItem` của `MainTabView`), mục đang chọn theo `.tint` (trắng), mục khác xám, nền `.bar` + vạch mảnh phía trên, cao 49pt, nền kéo xuống vùng home indicator; badge đỏ số truyện có chương mới ở Kệ Sách (chuyển từ `.badge` của `MainTabView`, bỏ `@ObservedObject newChapters` ở đó).
- **`.mainTabBar()`** (`MainTabBarModifier`, mới): ẩn thanh hệ thống + `safeAreaInset(edge: .bottom)` đặt `MainTabBar` vào nội dung trang gốc **bên trong** `NavigationStack` ⇒ trang đẩy vào phủ lên thanh, back/vuốt mép thì thanh trượt về cùng trang gốc. Tab đang chọn đi qua environment `mainTabSelection` (`MainTabView` truyền `$selectedTab`). `hidesWithKeyboard: true` chỉ ở tab Tiện ích (trang gốc có ô tìm): bàn phím hiện ⇒ bỏ thanh, ẩn ⇒ hiện lại; chỉ nghe khi trang gốc đang hiện và trả thanh về lúc bị trang đẩy vào che (bàn phím của trang con không được làm thanh hiện lại giữa nhịp back). Gắn ở 4 trang gốc: `ShelfView`, `DiscoveryView`, `RepositoryManagerView`, `SettingsView` (nút "+" nổi của Kệ tự nằm trên thanh).
- **Thanh hệ thống luôn ẩn**: `PageTitleModifier` ẩn ở **mọi** kiểu (không còn đổi theo trang); `MainTabView` ẩn thêm ở từng tab (ngoài `NavigationStack`) làm chốt chặn cho trang đẩy vào thiếu modifier tiêu đề. Giữ `TabView` + `.tag` + `.tabItem` để `MainTabView+TabReset` vẫn thấy đủ 4 tab. Cập nhật luật ở mục header của `CLAUDE.md`/`AGENTS.md`.
- Chuyển entry `[1.3.638]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. CI là cổng biên dịch; chưa thử trên máy (để ý: thanh tab hệ thống có còn lộ ra ở trang nào không; đẩy/back/vuốt mép có còn giật không; cỡ icon/chữ/badge so với thanh cũ).

## [1.3.667] - 2026-10-31

### feat: bỏ chạm 1/3 hai bên và vuốt ngang để đổi chương

Người dùng: *"bỏ chạm 1/3 trái phải để chuyển chương giúp tôi"* — chọn bỏ ở cả Reader lẫn truyện tranh; comic chỉ đổi chương bằng nút/mục lục (bỏ luôn vuốt ngang), chạm ảnh ở đâu cũng bật/tắt thanh, bỏ nút "…", cuối chương *"không có gì"*. Đảo phần chạm hai bên của 1.3.643 và vuốt ngang của 1.3.613.

- **Truyện tranh**: xoá `ComicChapterNavigationMode` cùng ngăn kéo "Tuỳ chọn đọc" và nút "…" ở thanh trên (thanh trên còn ☰, khung 36×38 vì giờ đứng một mình). `ComicReaderView` bỏ `chapterSwipeGesture`/`handleChapterSwipe`, `handleSingleTap`, `stepChapter` (cùng hai toast chương đầu/mới nhất); chạm ảnh và dòng cuối chương gọi thẳng `toggleChrome()`. `ComicPageView.onSingleTap` thành `() -> Void` (không cần điểm chạm). Đổi chương chỉ còn nút Chương trước/sau ở thanh dưới, mục lục, và nút "Chương tiếp" ở màn chương rỗng (giữ nguyên).
- **Cuối chương comic**: bỏ dòng gợi ý "Chạm bên phải…/Vuốt sang trái…"; còn "Hết chương" (chương cuối thêm "Đây là chương mới nhất"), giữ lề dưới 96 để ảnh cuối không nằm dưới thanh dưới.
- **Reader truyện chữ**: xoá `ReaderEdgeTapDetector` và `handleEdgeTap`; `readerScrollProbes` chỉ còn `ReaderUserScrollDetector` (tắt cuộn theo highlight khi tự kéo lúc TTS đọc — giữ nguyên). Bỏ công tắc "Chạm hai bên để chuyển chương" ở Cài đặt đọc.
- **Giá trị đã lưu**: khoá `comicChapterNavigationMode` và `readerEdgeTapChangesChapter` còn trong `UserDefaults` nhưng không code nào đọc ⇒ không ảnh hưởng, không cần migration.
- CLAUDE.md/AGENTS.md cập nhật mục màn đọc comic. Chuyển entry `[1.3.637]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code + diff, grep sạch các tên đã xoá trong `Sources/`; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy — cần thử: comic chạm ảnh (cả hai bên) chỉ bật/tắt thanh, chạm đúp phóng to, vuốt ngang không đổi chương, nút Chương trước/sau; Reader chạm hai bên không đổi chương, bôi đen và tắt cuộn theo highlight khi TTS đọc như cũ.

## [1.3.666] - 2026-10-31

### feat: thanh dưới trình duyệt gắn sát đáy, nút Import và ⋮ trong thanh

Người dùng: *"mockup lại phần bottom của browser"* → *"cho nó sát dưới luôn đừng làm kiểu lở lửng lên, như vậy nó sẽ che mất nội dung trang"* → *"giữ nguyên các thành phần, thêm import vào nữa"* → *"thay nút dịch bằng nút dropdown nhưng đổi icon còn icon ba chấm dọc"*; duyệt mockup + plan.

- **Thanh dưới gắn sát đáy** (`BypassWebView.browserArea`): `ZStack` (thanh nổi đè trang) → `VStack` trang ở trên, `BrowserBottomBar` ở dưới; trang kết thúc ngay trên thanh, không còn gì che nội dung. Nền thanh tối đặc + vạch mảnh trên, kéo xuống hết vùng vạch Home (`ignoresSafeArea(.container, edges: .bottom)` — bàn phím hiện thì thanh nằm ngay trên bàn phím). Bỏ đo safe area đáy (`bottomSafeInset`), các khoản chừa chỗ (`chromeClearance`, `barBottomPadding`, `importPillClearance`) và cơ chế thụt `contentInset` của `BypassBrowserWebPane` (`bottomObstruction`).
- **Thanh**: lùi, tiến, ô URL (giữ nguyên khiên/tên miền/tải lại), nút **Import**, nút **⋮** (`ellipsis` xoay 90° — SF Symbols không có ba chấm dọc) mở ngăn kéo "Trình duyệt". Đang nhập địa chỉ giữ như cũ (ô giãn hết + "Huỷ").
- **Nút Import** (`BrowserImportButton` mới, thay viên nổi `BrowserImportPill` đã xoá): icon tiện ích đầu tiên khớp URL, ≥ 2 nguồn có số nguồn ở góc; 1 nguồn chạm là import, nhiều nguồn mở bảng chọn nguồn (popover, nút sáng kiểu chip trong lúc mở); giữ cách import **sau** khi popover đóng hẳn. Ẩn khi không khớp nguồn / màn không nhận import / đang nhập địa chỉ. Bỏ theo dõi cuộn của tab (`isScrolledDown`, KVO `contentOffset`) vì chỉ viên nổi dùng để thu gọn.
- **Header**: bỏ nút "…", chỉ còn "Xong".
- **Dịch trang**: nút dịch rời thanh, thành công tắc "Dịch trang" đầu nhóm "Trang này" của ngăn kéo (`SideDrawerToggleRow`, bật/tắt tay cho tab này như nút cũ — `toggleTranslation`, không ghi nhớ; mờ ở Home/trang không phải web). Trang đang dịch ⇒ ô URL có icon dịch nhỏ trước tên miền (`BrowserAddressPill`, cùng chỗ icon ẩn danh).
- **Dải báo**: popup bị chặn nổi ở cuối vùng trang (ngay trên thanh); dải tự dịch giữ ở đầu trang. `BrowserGlassCapsuleBackground` giờ chỉ còn dải tự dịch dùng ⇒ bỏ tham số `usesBarGlass`/`isHighlighted` và nhánh khoá nút nổi.
- Sửa tài liệu chuẩn cụm nút header của 1.3.665 (`HeaderButtonMetrics`, `CLAUDE.md`/`AGENTS.md`, `rules.md`, `.agents/AGENTS.md`): ghi nhầm số 1.3.664 (số đó là CryptoJS) và ví dụ "… | Xong" không còn sau đợt này.
- Chuyển entry `[1.3.636]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code + diff; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy. Rủi ro cần thử: thanh khi bàn phím hiện (ô URL và ô nhập của trang), popover chọn nguồn bật từ nút trong thanh và từ mục ngăn kéo, công tắc "Dịch trang" đổi ngay khi ngăn kéo còn mở, trang Home cuộn tới cuối không bị thanh che.

## [1.3.665] - 2026-10-31

### fix: nút liền nhau trên header đứng sát nhau

Người dùng: *"cho phím dropdown và nút xong gần nhau hơn và nhỏ lại"* (header trình duyệt), rồi *"cái nào có 2 nút gần cũng gom thành group"*, sau đó *"thôi đừng làm group, để cho các nút gần lại là được"*; duyệt plan, chọn **giữ cỡ 17pt** (không thu nhỏ, không viên bao ngoài).

- **`HeaderButtonMetrics`** (mới, `Views/Common/PageHeader/`): `pairSpacing = 2`, `pairIconWidth = 32`, `pairCircleSpacing = 4`. Cụm nút liền nhau trên thanh điều hướng gộp vào **một** `ToolbarItem` chứa `HStack(spacing: pairSpacing)` — để nhiều `ToolbarItem`/`ToolbarItemGroup` thì iOS tự giãn cách, không chỉnh được. Icon giữ 17pt nửa đậm, chỉ khung hẹp 36 → 32 (chiều cao giữ 36/38 như cũ).
- **Thanh điều hướng (5 màn)**: trình duyệt (… | Xong), Trợ lý AI toàn màn (… | ⌄), Kệ (🔍 | …, kính lúp vẫn ẩn ở tab Tải xuống, chấm đỏ thông báo bám icon vì `.frame` đặt sau `.overlay`), Chi tiết truyện (nút dịch | …, `HStack` sẵn có cách 6 → 2), Quản lý tiện ích tab Kho (↻ | +, `ProgressView` lúc làm mới nằm trong khung 32).
- **Header tự dựng (4 chỗ)**: chỉ bọc cặp nút trong `HStack` con, khoảng cách của thanh (nút lùi, tiêu đề) giữ nguyên — màn đọc truyện tranh (☰ | …), trình duyệt Legado (↻ | ✓, nút tròn ✓ giữ 38), Khám phá (hai nút tròn 38 cách 8 → 4), cặp trái trình phát video (⌄ | ✕; `VideoPlayerIconButton`/`VideoPlayerIconLabel` thêm tham số `width` mặc định 36 nên các nút video khác không đổi).
- **Không đổi**: header Reader (6 nút) và cụm nút phải của trình phát video.
- **Chuẩn header**: `CLAUDE.md`/`AGENTS.md`, `rules.md` (§ chuẩn Header + checklist) và `.agents/AGENTS.md` thêm quy định cụm nút liền nhau (2pt, khung 32, nút tròn cách 4); nút đứng một mình giữ chuẩn 36×36.
- Chuyển entry `[1.3.635]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code + diff; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy. Rủi ro: vùng chạm khung 32 hẹp hơn chuẩn 36 (dễ bấm nhầm nút bên cạnh); nút chữ "Xong" và icon trong `HStack` của `ToolbarItem` có thể nhận kiểu nút toolbar khác một chút so với khi là mục riêng.

## [1.3.664] - 2026-10-31

### feat: CryptoJS dựng sẵn cho load('crypto.js') của tiện ích

Lệch hợp đồng phát hiện khi viết tiện ích ciyuanji (giải mã DES): hợp đồng chuẩn (mục "Crypto") nói `load('crypto.js')` nạp CryptoJS dựng sẵn, nhưng FreeBook chỉ tìm file trong tiện ích — không có thì bỏ qua im lặng, script chết với `CryptoJS is not defined`. Người dùng duyệt plan, chọn **file của tiện ích thắng** (khác hợp đồng), CryptoJS 4.2.0, GCM + PBKDF2 native.

- **Thư viện đóng gói** `Sources/Resources/ExtensionLibraries/crypto-js-4.2.0.min.js` = `crypto-js.min.js` 4.2.0 của cdnjs (khớp SRI, giữ nguyên byte qua `.gitattributes`); giấy phép MIT ở `Docs/ThirdParty/CryptoJS-LICENSE.txt`. `project.yml` khai tường minh thư mục này là resource (loại khỏi mục `Sources` chung).
- **`JSBuiltInLibrary`** (mới, `Engine/`): tên thư viện dựng sẵn (`crypto.js`) + nguồn đọc từ bundle một lần; thiếu resource ⇒ log ❌. Dùng chung cho `load` và hai bộ kiểm tra tĩnh.
- **`load('crypto.js')`** (`JSExecutor+Load`): file `crypto.js` của tiện ích (gốc rồi `src/`) chạy như cũ; không có ⇒ chạy bản dựng sẵn, một lần mỗi executor (cả `load` lúc runtime). Chạy được cả khi executor không gắn tiện ích.
- **Phần native** (`JSCryptoJSBridge` mới ở `Bridges/`, JS ở `Bootstrap/JSCryptoJSBootstrapScript`), cài cho mọi executor bằng một dòng trong `JSExecutor`: `crypto.getRandomValues` toàn cục (JSC không có ⇒ CryptoJS 4.x không sinh được salt khi mã hoá bằng passphrase). Sau mỗi lần nạp `crypto.js` (bản nào cũng vậy) gắn thêm: `WordArray.random` lấy byte native (bản 4.1 tiện ích đang mang không dò `globalThis.crypto`); `AES.encryptGcm/decryptGcm` theo hợp đồng qua CryptoKit (khoá hex 32/48/64 hoặc passphrase đệm 0/cắt 16/24/32, IV rỗng = 12 byte 0, IV < 12 byte ⇒ lỗi, thẻ sai ⇒ WordArray rỗng như hành vi iOS; WordArray có byte ≥ 0x80 dùng byte thô thay vì hỏng như app gốc); `PBKDF2` với hasher SHA1/224/256/384/512 qua `CCKeyDerivationPBKDF` (250 000 vòng mặc định của 4.2.0 chạy JS thuần trong JSC không JIT mất hàng chục giây), hasher khác giữ bản JS. Đoạn JS bổ sung bỏ qua `CryptoJS` không đúng dạng và không bao giờ ném lỗi ra ngoài.
- **Bộ kiểm tra tiện ích** (`ExtensionScriptStaticCheck`) và **validator nháp của server debug** (`ExtensionDraftValidator`) không còn báo `load("crypto.js")` thiếu file (trước đây server debug chặn chạy nháp).
- **Tương thích**: ciyuanji, qidian-vp tự mang cùng bản CryptoJS 4.0/4.1 ⇒ vẫn chạy bản của mình (được gắn thêm `WordArray.random` native, GCM, PBKDF2 native; kết quả các hàm sẵn có không đổi). Bản dựng sẵn 4.2.0 chỉ khác 4.1 ở mặc định PBKDF2 (SHA256/250 000 thay SHA1/1). `Crypto.md5/sha*/hmac*` giữ nguyên.
- Ghi vào `rules.md` (global JS) và `CLAUDE.md`/`AGENTS.md` (đoạn `load()`). Chuyển entry `[1.3.634]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; JS bổ sung chạy thử bằng node trên context không có `crypto`/`require` với native giả lập (28/28 đạt: DES-ECB 4.1 → 4.2.0, AES passphrase khứ hồi trên cả hai bản, PBKDF2 native = JS, GCM khớp node, thẻ sai ⇒ rỗng); `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows); phần Swift (CryptoKit/CommonCrypto, resource trong bundle) chỉ CI chứng minh biên dịch + đóng gói; chưa thử trên máy.

## [1.3.663] - 2026-10-31

### fix: mọi nút sao chép cạnh ô nhập báo toast Đã sao chép

Người dùng: *"tôi đã yêu cầu nhấp nút copy trên bàn phím thì có toast báo nhưng sao bạn chỉ làm cho màn hình browser thôi, phải làm tất cả chỗ nào hiển thị bàn phím có nút copy chứ"* (1.3.656 chỉ thêm toast cho nút sao chép của thanh công cụ bàn phím).

- **`ClipboardCopier.copy(_:message:)`** (mới, `Views/Common/`): ghi bộ nhớ tạm + toast "Đã sao chép" (`recordsInInbox: false`, không vào Trung tâm thông báo). Nút sao chép mới thì gọi qua đây.
- Dùng cho: thanh công cụ bàn phím (`KeyboardTextToolbarModel.copy`), bộ nút cạnh ô một dòng `TextFieldClipboardButtons` (Cấu hình tiện ích, Thông tin plugin.json), nút sao chép cạnh ô của Từ điển (`DictEntrySheet`), Trí nhớ AI (`BookAIMemorySheet`), Cài đặt AI (`AISettingsView+Actions`), ô chữ thử VieNeu, và hai nút trước đây sao chép im lặng: "Sao chép tin nhắn" của Trợ lý AI toàn màn, địa chỉ của Debug server tiện ích. Các nút đã có toast/chỉ báo riêng giữ nguyên.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows); chưa thử trên máy — toast nổi trên bàn phím ở sheet (Từ điển, Trí nhớ AI).

## [1.3.662] - 2026-10-31

### feat: panel Mục lục dùng chung, thẻ gợi ý và bình luận ở Chi tiết

Người dùng: *"Sửa lại UI panel comment và panel suggest cho đồng bộ với UI của chi tiết. Sửa lại UI mục lục tham khảo hình. Sửa lại màn hình comment panel dạng bo góc giống danh sách truyện"*, thêm *"đồng bộ mục lục reader và commic nữa"*, *"Bỏ số trên bìa"*, *"Cho màu chữ mục lục(xx chương) thành trắng luôn"*; duyệt plan + mockup.

- **Panel Mục lục dùng chung** (`Views/Common/ChapterTOCPanel/`, mới): `ChapterTOCPanelHeader` = "Mục lục" 22pt đậm + "(N chương)" 17pt, chữ trắng, nút đảo thứ tự `arrow.up.arrow.down` 17pt nửa đậm khung 36×36 (ô `accessory` đứng trước), dưới là `ChapterTOCSearchField` viên thuốc cao 40 "Tìm kiếm N chương"; `.chapterTOCPanel(_:)` = nền bo 16 hai góc trên, tràn xuống vùng an toàn đáy, lề ngang 16 — đầu panel + ô tìm đứng yên, chỉ danh sách cuộn; `ChapterTOCPalette` `.system` (Chi tiết) / `.reader(theme)` (nền Sáng/Trầm ấm: tiêu đề và chương đang đọc dùng màu chữ của nền vì chữ trắng không đọc được).
- **Tab Mục lục của Chi tiết** (`BookDetailTOCView`): bỏ hàng "Danh sách chương (N)" + ô tìm `.roundedBorder` cũ, dựng panel trên; "Tải lại lỗi" + la bàn "Mở link lỗi" (`tocErrorActions`) nằm ở đầu panel. Ba nhánh hàng (bản chụp `chapter_store`, `Book.chapters`, mục lục online) dùng chung `BookDetailTOCRow` (mới): chữ `.body` tối đa 2 dòng, vạch ở trên mỗi hàng, đang đọc = đậm + nền mờ bo 8, đã đọc mờ 0.4, đã tải icon xanh. Số chương trên tiêu đề không tính dòng nhóm. Lưới tập video giữ nguyên.
- **Mục lục Reader** (`ReaderChapterListView`) và **comic** (`ComicChapterListSheet`): header bìa + tên + nguồn + hàng nút giữ nguyên, nhưng nút đảo thứ tự dời xuống đầu panel và bìa bỏ dải số chương (`CoverCaptionStrip`). `List` nền trong suốt trong panel; hàng (`ReaderChapterRowView`, `row(for:)`) nền trong suốt, chương đang đọc nền `currentRowFill`, vạch `listRowSeparatorTint` theo nền đọc. Sửa luôn chữ trắng của chương đang đọc trên nền Sáng/Trầm ấm. Ô tìm cũ của hai màn bị xoá.
- **Thẻ đề xuất + bình luận** (tab Chi tiết): `BookDetailSectionCard` có thêm ô `trailing` (mặc định trống, ba thẻ cũ không đổi). `SuggestRowView`/`CommentSectionView` nhận `title` và tự bọc thẻ (tiêu đề xanh nhạt như "Giới thiệu"); "Xem thêm ›" dời từ `BookDetailView` vào ô `trailing` của thẻ đề xuất. Bỏ lề ngang lồng và `Divider` giữa các khối, khoảng cách thẻ 12 đều với thẻ phía trên; vạch chỉ nằm giữa hai bình luận; nút "Xem tất cả bình luận" nền `tertiarySystemFill` (nền 5% cũ chìm trên nền thẻ). Khung chờ tải của hai khối có cùng dáng thẻ.
- **Màn tất cả bình luận** (`AllCommentsView`): mỗi bình luận là panel `.bookListPanelRow()` như kiểu Danh sách truyện, không vạch; hàng chờ trang sau `.bookListPanelRowChrome()`. Cuộn vô cực, kéo làm mới giữ nguyên.
- Ghi quy ước panel Mục lục vào `CLAUDE.md`/`AGENTS.md`. Chuyển entry `[1.3.632]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. CI là cổng biên dịch; chưa thử trên máy (để ý: chạm hàng mục lục trong panel, vạch ngăn `List` ở nền Sáng/Trầm ấm, nút nổi của Chi tiết đè lên panel).

## [1.3.661] - 2026-10-31

### feat: nhớ độ sáng khi xem phim, đổi tab về trang gốc

Người dùng: *"Ghi nhớ độ sáng của video mở lần gần nhất, mọi video, mọi nguồn. Chuyển qua tab khác về tab cũ thì hiển thị màn hình ban đầu của tab"*; chọn áp độ sáng ngay khi mở phim (cả khung dọc nhỏ lẫn toàn màn) và chỉ đặt lại tab khi tab đang ở trang con; duyệt plan.

- **Độ sáng phim** (`VideoBrightnessKeeper`, mới, `Views/VideoPlayer/`): chủ duy nhất đổi `UIScreen.brightness` ở trình phát. Một mức chung cho mọi phim, mọi nguồn = mức cuối vuốt chỉnh, UserDefaults `videoPlayerBrightness` (chưa từng vuốt ⇒ không đụng; tra `object(forKey:)` vì 0 là mức hợp lệ). `VideoPlayerScreen.onAppear` ⇒ `activate(controller)`: chụp độ sáng của máy **rồi** áp mức đã nhớ (cả phim nhúng trang); `onDisappear` (đóng / thu nhỏ / PiP) ⇒ `deactivate(controller)` trả độ sáng máy — giữ **tập** màn như `VideoPlaybackSession.attachedScreens` nên màn mới hiện trước khi màn cũ kịp biến mất (mở lại từ hub / PiP) không bị màn cũ trả mất độ sáng; hai chỗ đặt sau nhánh bỏ qua trình duyệt "Mở link lỗi". App mất active ⇒ trả độ sáng máy; active lại khi màn còn mở ⇒ chụp lại (có thể vừa chỉnh ở Trung tâm điều khiển) rồi áp lại.
- **`VideoGestureView`** bỏ phần tự chụp/trả độ sáng gốc (`originalBrightness`, `willMove(toWindow:)`, observer `willResignActive`) — để lại thì nó chụp nhầm mức của phim làm "gốc". Vuốt ⇒ `setLevel(_:on:)` đặt ngay; nhả tay ⇒ `commitLevel()` lưu mức cuối đã đặt (gọi **sau** `value(for:)` của nhịp nhả tay; cử chỉ huỷ báo 0 cho controller nhưng không lưu số đó).
- **Đổi tab về trang gốc** (`MainTabView` + `MainTabView+TabReset.swift`, mới): mỗi tab có mã `.id` (`tabResetTokens`, gắn trước `.tabItem`). `onChange(of: selectedTab)` vẫn phát `.appTabDidChange`, rồi tăng mã của **tab vừa rời** nếu `shouldResetTab(at:)` ⇒ SwiftUI tạo lại tab đó ngầm. Tab đang vào không bị đụng (widget TTS chuyển sang tab Kệ còn phải mở Reader trong cùng nhịp). Các tab gốc dùng `NavigationStack` không `path` (cờ `isPresented` + `NavigationLink`, riêng Cài đặt 40 chỗ) nên đọc **chỉ đọc** cây UIKit của cửa sổ có thanh tab: có `UINavigationController` nào trong tab nhiều hơn 1 trang ⇒ đặt lại; tab đang ở trang gốc giữ nguyên (Khám phá không tải lại, giữ chỗ cuộn). Có sheet / màn toàn màn đang phủ (Reader, phim, truyện tranh) ⇒ không đặt lại để khỏi đóng mất màn đó. Không đọc được cây UIKit, hoặc thanh tab không liệt kê đủ 4 tab (chỉ số có thể trỏ nhầm tab) ⇒ đặt lại và log `❌ [TabReset]` (luôn ghi); mỗi lần đặt lại log `🔄 [TabReset]` (chỉ khi bật ghi log).
- Chuyển entry `[1.3.631]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. CI là cổng biên dịch; chưa thử trên máy (rủi ro chính: SwiftUI có đọc được `UITabBarController`/`UINavigationController` như giả định không — xem log `❌ [TabReset]`, bật ghi log để thấy cả `🔄`; tab Kệ tạo lại lúc ẩn có còn nhận lệnh mở Reader từ widget TTS).

## [1.3.660] - 2026-10-30

### fix: Chi tiết từ trình đọc đẩy vào màn đọc, trang đẩy vào ẩn thanh tab

Người dùng thử 1.3.659: *"reader -> chi tiết bị lỗi hiển thị 2 nút back"*, *"tôi muốn chi tiết luôn full màn hình"*; chọn ẩn thanh tab ở **mọi** trang đẩy vào và đẩy Chi tiết vào màn đọc.

- **Mọi trang đẩy vào ẩn thanh tab** (`PageTitleModifier`): `.toolbar(style == .leading ? .automatic : .hidden, for: .tabBar)`. Theo quy ước header, `.centered` (`.backPageTitle`, màn mở được cả hai kiểu khi đẩy vào) và `.hidden` (Chi tiết truyện) là trang đẩy vào; `.leading` là tab gốc / gốc sheet ⇒ chỉ 4 tab gốc còn thanh tab. Đã soát các đích `NavigationLink`/`navigationDestination`: đều dùng kiểu giữa (riêng `BookDictionaryView` chuyển tiếp sang `DictionaryHubView` có `style:`). Ghi luật vào mục header của `CLAUDE.md`/`AGENTS.md`.
- **Chi tiết từ mục lục Reader** không còn `fullScreenCover` + nút `chevron.left` tự vẽ (bản 1.3.659 hiện hai nút back): chạm bìa ⇒ `onOpenBookDetail` (thay `onBookDetailCoverChange`, qua `ReaderChapterListHost`) ⇒ `ReaderView` gán `imported*` theo sách đang đọc, đóng sheet, `onDismiss` của sheet bật `navigateToBookDetail` ⇒ đẩy vào `NavigationStack` của Reader bằng đúng đường Import có sẵn (`onDisappear` vốn bỏ qua `shutdown` khi `navigateToBookDetail`). Một nút back hệ thống, vuốt mép quay lại về trang đọc.
- **Màn đọc truyện tranh** tương tự: `ComicChapterListSheet` báo URL chi tiết qua `onOpenBookDetail(_:)`, `ComicReaderView` đẩy bằng `.navigationDestination(item: $bookDetailUrl)` sau `onDismiss` của sheet mục lục; `handleDisappear` bỏ qua dọn dẹp khi `bookDetailUrl != nil`; quay lại thì `bootstrap()` tự bỏ qua (`hasStarted`).
- Xoá `CoverBackButtonModifier.swift`, cờ `isBookDetailCoverPresented`/`isBookDetailCovering`. Chuyển entry `[1.3.630]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. CI là cổng biên dịch; chưa thử trên máy (để ý thanh tab có giật một nhịp lúc đẩy/back không).

## [1.3.659] - 2026-10-30

### fix: màn Chi tiết không tải lại khi quay về, mở toàn màn từ trình đọc

Người dùng: *"khi mở xem thêm comment hoặc xem thêm suggest, danh sách genres từ màn hình chi tiết back về màn hình chi tiết đều phải load lại dù là không cần thiết"*; qua phỏng vấn chọn: chỉ xử lý khi back, khối đang lỗi tự thử lại khi back, kéo làm mới tải lại cả gợi ý/bình luận, và *"cho màn hình chi tiết luôn hiển thị toàn màn hình, kể cả mở từ reader"*.

- **Mã truyện ổn định** (`BookDetailView.resolveBookId`): truyện chưa lưu có link không dạng UUID (không chứa `-` hoặc ≤ 30 ký tự) trước đây được cấp `UUID()` **mới mỗi lần màn hiện** ⇒ cache chi tiết 5 phút (`BookDetailCacheManager`) không bao giờ trúng, back về là tải lại cả chi tiết lẫn mục lục; `.task(id: actualBookId)` và phạm vi dịch theo truyện cũng lệch theo. Nay dùng `fallbackBookId` (`@State`, cấp một lần cho cả đời màn).
- **Hiện lại không gọi mạng** (`BookDetailView+AppearLoad.swift`, mới): `onAppear` gọi `loadBookDataOnAppear()` — lần đầu `loadBookData()`; các lần sau (back từ Xem thêm, bình luận, thể loại, truyện gợi ý, từ điển…) chỉ phần đang lỗi tự thử lại (`detailErrorMessage` ⇒ `loadBookDetailOnly`; `tocErrorMessage` khi `onlineChapters` còn rỗng ⇒ `loadTOCDataOnly` — lỗi của lượt "Tải thêm chương" thì không, vì sẽ thay danh sách bằng trang 1; nút "Tải thêm" vẫn là nút thử lại tay). Hết cảnh trang 1 mục lục tải lại mỗi lần back và đặt lại tiến độ "Tải thêm chương". Việc rẻ trên máy (cờ dịch, `markSourceUsed`, đồng bộ mục lục đã lưu, `VideoOfflineLibrary.refresh`) vẫn chạy mỗi lần hiện; nhánh `skipsReappearLoad` của "Mở link lỗi" giữ nguyên.
- **Khối Gợi ý / Bình luận** (`SuggestRowView`, `CommentSectionView`): `.task(id: refreshGeneration)` + `loadedGeneration` — chỉ tải khi lượt làm mới hiện tại chưa có kết quả thành công. Lỗi thật giữ hiển thị và tự thử lại ở lần back sau; `CancellationError` (kể cả bọc trong `ExtensionLoadError`) không ghi lỗi, lần hiện lại tải tiếp.
- **Kéo làm mới** (`reloadBookData`) tăng `sectionRefreshGeneration` ⇒ các khối gợi ý/bình luận tải lại cùng lượt (trước đây không: mã khối không đổi nên view con giữ nguyên).
- **Danh sách thể loại / Xem thêm** (`CategoryNovelsListView`, dùng chung với Khám phá): `.task` chỉ `loadInitial()` khi danh sách rỗng (chưa tải, bị huỷ, lỗi trang 1) ⇒ back từ một truyện giữ nguyên các trang đã cuộn vô cực.
- **Chi tiết toàn màn từ trình đọc**: bấm bìa ở mục lục Reader (`ReaderChapterListView`) và màn đọc truyện tranh (`ComicChapterListSheet+Header`) mở `BookDetailView` bằng `fullScreenCover` thay cho `sheet`; nút quay lại `.coverBackButton()` (`Views/Common/PageHeader/CoverBackButtonModifier.swift`, mới: `chevron.left` 17pt nửa đậm, khung 38×44, `dismiss()`). Cover che màn đọc có thể làm `onDisappear` của nó nổ ⇒ mục lục báo lên qua `onBookDetailCoverChange` (đi qua `ReaderChapterListHost`, closure không vào `==`); `ReaderView` (`isBookDetailCoverPresented`, như `navigateToBookDetail`) và `ComicReaderView` (`isBookDetailCovering`, như trình xem phóng to) bỏ qua dọn dẹp/`shutdown`. Đóng cover thì mục lục có thể chạy lại `onAppear` ⇒ cuộn về chương đang đọc (chỉ tra store, không gọi mạng).
- Không đổi: đổi tab Chi tiết ↔ Mục lục vẫn dựng lại tab chi tiết và tải lại khối gợi ý/bình luận (người dùng chọn chỉ xử lý back). Dữ liệu chi tiết giữ tới khi đóng màn hoặc kéo làm mới.
- Chuyển entry `[1.3.629]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. CI là cổng biên dịch; chưa thử trên máy.

## [1.3.658] - 2026-10-30

### fix: dọn dẹp/xoá tác vụ xuất xoá luôn file trong Documents/Exports

Người dùng: *"dù đã dọn dẹp/xoá tác vụ xuất (truyện, video, comic) trong app, các file trong Documents/Exports vẫn còn"*, *"khi bấm dọn dẹp tác vụ mà có tác vụ xuất file trong đó thì dọn dẹp file xuất trong documents nữa"*; "Xóa khỏi danh sách" từng tác vụ cũng xoá file; duyệt plan.

- **Nguyên nhân**: `deleteTask` / `clearFinishedTasks` chỉ xoá hàng `DownloadTaskModel` + sidecar, không dòng nào xoá file — đúng cho cả TXT/EPUB/FB2/MOBI, CBZ/PDF và video (file hoặc thư mục). Thêm hai chỗ rò: `.part` của lần xuất bị tắt giữa chừng (tên có mốc giờ nên lần sau không trùng để tự dọn) và thư mục ẩn `.video-export-<taskId>.part` (chỉ dọn khi "Tải lại" đúng tác vụ đó).
- **`ExportFileCleaner`** (mới, `Services/Export/`): chỉ xoá mục nằm **trực tiếp** trong `Exports/` (`validateInsideExports` + kiểm thư mục cha), không bao giờ xoá chính `Exports/`; lỗi ⇒ log `❌` (không vào `failed_file_deletions_queue` — hàng đó chỉ nhận `applicationSupport`).
- **Đường dẫn bền**: `exportFilePath` lưu tuyệt đối (kèm UUID container, đổi khi cập nhật/cài lại app) ⇒ `ExportFileCleaner.resolvedURL` luôn ghép tên cuối vào `Exports/` của lần chạy này. `DownloadTask.existingExportURL` dùng cho nút/ menu Chia sẻ lại và `shareExportedFile`. Không đổi `@Model`.
- **Xoá một tác vụ** (menu đổi nhãn "Xóa tác vụ và file" với tác vụ xuất): tác vụ xuất đã kết thúc ⇒ xoá file/thư mục + thư mục tạm video. Tác vụ đang chạy tự dọn `.part` khi bị huỷ; `markExportCompleted` của tác vụ đã bị xoá (ghi xong đúng lúc xoá) xoá luôn file vừa ghi.
- **Dọn dẹp tác vụ**: xoá file của mọi tác vụ xuất bị dọn; không còn tác vụ xuất nào chạy/chờ ⇒ xoá luôn mọi mục mồ côi trong `Exports/` (bản xuất của các lần dọn trước, `.part`). Có xoá ⇒ toast "Đã xoá N file xuất trong Documents/Exports.". Mục "Dọn dẹp tác vụ" ở ngăn kéo tab Tải hiện cả khi danh sách rỗng (trước ẩn ⇒ file tồn đọng sau khi đã dọn hết tác vụ không bao giờ dọn được). Xoá chạy trên `Task.detached`, sau khi CSDL đã lưu (như `BookStorageManager`). Tác vụ tải không đụng file.
- **Khởi động**: `initialize` dọn `.part` sót lại một lần mỗi lần chạy app, chỉ mục sửa lần cuối trước mốc khởi động. Xoá truyện vẫn không xoá bản xuất.
- Chuyển entry `[1.3.628]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.657] - 2026-10-30

### fix: load() không đè hàm của script chính, chi tiết đọc trường comment

Người dùng gửi tiện ích Chuangshi QQ (Khám phá trả `{"baseUrl":…,"apiBase":…,"ok":true}` thay cho danh sách) và FQWeb Universal (*"vì sao script comment của ext này không chạy rồi fix chung luôn"*).

- **`load('x.js')` theo hợp đồng = thay văn bản trước khi chạy** (`extension-api.md` của Darkrai9x): khai báo của script chính đứng sau file nạp nên thắng khi trùng tên. App cũ chạy file nạp **lúc gặp lời gọi** ⇒ `function execute()` của `config.js` (Chuangshi QQ có hàm này để thử cấu hình) đè `execute()` của script chính đã hoist từ trước ⇒ cả 7 script của tiện ích trả object cấu hình. Sửa: `JSExecutor+Load.swift` (mới, nhận khối `load` dời khỏi `init`) — `prepareScript` chạy trước các file mà script chính `load(...)` ở **cột 0** (cho phép BOM), rồi mới chạy script chính; file đã chạy trong lúc chuẩn bị ghi vào `preparedLibraries` ⇒ `load` cùng tên sau đó là no-op (không chạy lại file có `let` cấp cao nhất). `load` lúc runtime với file chưa nạp (`Script.execute("gen.js", "execute")`, `Qt.include`, lời gọi thụt lề trong thân hàm) giữ hành vi cũ. Số dòng của script chính không đổi (màn Debug). `JSExecutor.swift` 1012 ⇒ 988 dòng.
- **Detail: trường `comment`** (một nguồn `{title, input, script}`, hiện trước `comments` — hợp đồng) trước đây bị bỏ qua ⇒ FQWeb Universal (chỉ trả `comment`, không có `title`) không bao giờ gọi `comment.js`. `ExtensionManager.detailCommentSources`: `comment` (object; lỡ là mảng thì đọc như `comments`) rồi `comments`, thiếu `title` ⇒ "Bình luận", script mặc định `comment.js`, trùng nguồn giữ một. `genres`/`suggests` giữ luật cũ (thiếu `title` ⇒ bỏ). `reviews` của hợp đồng vẫn chưa đọc.
- Chuyển entry `[1.3.627]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng**: đọc code; đối chiếu hợp đồng (`load()`, bảng trường detail); `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows); chưa thử trên máy — Khám phá/tìm/đọc của Chuangshi QQ, khối bình luận ở Chi tiết của FQWeb Universal.

## [1.3.656] - 2026-10-30

### fix: trình duyệt bôi đen thấy được, ô URL tìm Google, tự dịch nguồn tiếng Trung

Người dùng (thử 1.3.655): *"Phần bôi đen của web bị sửa thành màu trắng không thấy được chữ nào bôi đen"*, *"nhập vào ô url nếu là chữ bình thường không phải link hãy search bằng google, bàn phím đổi thành bàn phím bình thường"*, *"tự quyết định trình duyệt từ đầu có bật tự động dịch không nếu chưa config … url match với ext có ngôn ngữ là tiếng trung thì từ đầu phải bật dịch"*, *"khi bấm nút copy trên bàn phím, hãy thêm toast"*; duyệt plan.

- **Vùng bôi đen**: app đặt màu nhấn trắng toàn cục (`.tint(.white)`) ⇒ vùng chọn + tay nắm của trang thành trắng. `BrowserWebView` và `URLBarTextField` gán `tintColor = .systemBlue` tường minh (như Safari).
- **Ô địa chỉ**: bàn phím thường (`.default`, thanh công cụ bàn phím của app vẫn tự gắn), chữ gợi ý "Tìm hoặc nhập địa chỉ web". Enter: link (`http(s)://`, hoặc không khoảng trắng + `localhost`/IPv4/tên miền có đuôi chữ ≥ 2 ký tự) ⇒ mở; còn lại ⇒ tìm Google (`BrowserAddressInputMapper`, dùng chung `webSearchURL(for:)` với "Tìm trên web").
- **Tự dịch mặc định** (`BrowserTranslatePolicy`): tên miền ⇒ công tắc tiện ích khớp URL ⇒ **mặc định của tiện ích khớp đầu tiên** = cấu hình dịch "Nguồn này" của Reader (`TranslationConfigStore`) nếu đã đặt, không thì nguồn tiếng Trung (`Extension.isChineseSource`) ⇒ bật ⇒ tắt. Công tắc "Tự dịch trang (QT)" ở Cấu hình tiện ích hiện giá trị đang hiệu lực, ghi `true`/`false` tường minh, thêm dòng "Dùng mặc định" khi đã chỉnh.
- **Toast "Đã sao chép"** khi bấm nút sao chép của thanh bàn phím (mọi ô nhập). `ToastManager.show` thêm `recordsInInbox` (mặc định `true`) để toast này không vào Trung tâm thông báo; lớp toast giữ vùng bàn phím (`.ignoresSafeArea(.container)`) nên không bị bàn phím che.
- Chuyển entry `[1.3.626]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows); chưa thử trên máy — màu vùng chọn trên trang, toast nằm trên bàn phím (cửa sổ toast mức `.alert`), mở URL tiện ích tiếng Trung lần đầu tự dịch.

## [1.3.655] - 2026-10-30

### feat: trình duyệt mới với dịch QT, menu nhấn giữ và viên Import

Người dùng: *"thêm chức năng dịch (dùng qt) cho browser"* rồi `/grill-me` *"thiết kế lại giao diện browser mới cho đẹp hơn, hợp với yêu cầu thêm dịch, custom context menu của browser lại"*; sau mockup: *"hiển thị thanh tab đi, bỏ lưới"*, *"để nút thêm tab bên phải tab cuối cùng, luôn hiển thị thanh tab"*, Import là viên nổi trong suốt mang icon tiện ích khớp; *"duyệt, làm giống y vậy nhé"*. Plan: `Docs/Plans/2026-10-30-plan-trinh-duyet-moi.md`.

- **Dịch trang QT** (`Services/Browser/Translate/`): script trong content world riêng (`BrowserPageTranslateScript`, chỉ khung chính) dịch **tại chỗ** text node + `title`/`alt`/`placeholder` theo lô qua handler có trả lời `fbPageTranslate` (`BrowserPageTranslator`, `TranslateUtils.translateContent(_, bookId: nil)` ngoài main); tắt ⇒ khôi phục bản gốc; `MutationObserver` dịch nội dung nạp thêm. Tiêu đề tab dịch theo (`displayTitle`).
- **Nhớ dịch**: `BrowserSitePreference.translate` (công tắc "Tự dịch QT" trong bảng khiên, xem ở Cài đặt › Trang đã chỉnh riêng) ⇒ `Extension.translateOverride` của tiện ích **đầu tiên** khớp URL có giá trị (công tắc mới "Tự dịch trang (QT)" ở Cấu hình tiện ích › Trình duyệt; vào sao lưu, khoá `nil` không đổi vân tay cũ) ⇒ tắt (`BrowserTranslatePolicy`). Nút dịch trên thanh chỉ bật/tắt cho tab đang xem, giữ khi còn cùng tên miền. Dải báo "Tự dịch QT · theo …" chỉ hiện lần đầu tab vào tên miền.
- **Giao diện** (giống mockup đã duyệt): header `.pageTitle` + `…` (ngăn kéo "Trình duyệt": Import truyện, Sao chép link, Chia sẻ, Tab mới, Về trang chủ, Lịch sử, Cài đặt trình duyệt) + Xong; **dải tab luôn hiện**, nút + ngay sau tab cuối, ẩn ✕ khi 1 tab; **thanh kính nổi** dưới (lùi, tiến, ô URL có khiên + tải lại, nút dịch; nền đọc khoá kính ngăn kéo của `GlassChromeSettings`); **viên Import** trong suốt mang icon tiện ích khớp URL (1 nguồn import luôn, ≥ 2 mở bảng chọn nguồn thay hộp thoại cũ, cuộn xuống thu còn icon). File mới ở `Views/Common/Browser/Chrome/`.
- **Menu nhấn giữ** thay menu Safari: link (UIMenu gốc, không xem trước) ⇒ Mở / Mở trong tab mới / Mở trong tab nền / Sao chép link / Chia sẻ, link bọc ảnh thêm nhóm Ảnh; ảnh ngoài link ⇒ menu tại điểm chạm (`UIEditMenuInteraction`: Lưu ảnh, Sao chép ảnh, Mở ảnh trong tab mới; thêm `NSPhotoLibraryAddUsageDescription`); chữ bôi đen (`BrowserWebView.buildMenu`, bỏ Tra cứu/Dịch/Chia sẻ/Nói hệ thống) ⇒ Sao chép, Dịch QT, Tra từ điển, Sao chép bản dịch, Tìm trên web, Mở tab mới (khi trong link). Trang đã dịch ⇒ dùng bản gốc của vùng chọn.
- **Sheet** Dịch QT (bản gốc/bản dịch, Sao chép bản dịch, Tra từ điển) và Tra từ điển (token của câu, Hán Việt, VietPhrase/Names từ điển chung) — `browserContextSheets(store:)`.
- Script + handler cài **một lần** mỗi `WKUserContentController` (tab `target=_blank` dùng chung controller với tab mẹ ⇒ tránh crash trùng handler).
- CLAUDE.md/AGENTS.md: thêm ghi chú content world chung, cài một lần mỗi controller, hai kiểu handler, luật nhớ dịch.
- Chuyển entry `[1.3.625]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng**: đọc code + 2 agent review phản biện (biên dịch, hành vi) — đã sửa 1 lỗi biên dịch (đăng ký handler sai bản API) và 6 lỗi hành vi; JS qua `node --check`; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows); **chưa thử trên máy** — menu bôi đen có thay được menu hệ thống không, `previewProvider: nil` còn xem trước không, menu ảnh sau khi nhả tay, dịch trang dài/SPA, tab mở bằng `_blank`, thanh dưới che cuối trang trên máy có vạch Home.

## [1.3.654] - 2026-10-29

### fix: bấm Xuất video không còn ra tác vụ tải, thêm Xuất video/chương đã tải

Người dùng: *"tôi bấm xuất video mà nó không xuất, chỉ tải video, tôi phải qua tab tải bấm xuất video đã tải nó mới xuất. fix lỗi nào đi. Nên có option xuất video đã tải, xuất chương đã tải cho commic"*.

- **Nguyên nhân (khả năng cao, chưa kiểm được trên máy)**: Kệ, Tìm trên kệ, Bộ sưu tập, Chi tiết, tab Tải mỗi màn giữ hai state rời — sách (`selectedBookForTask`, item của `.sheet`) và loại tác vụ (`selectedTaskType`, mặc định `.download`) — và closure của sheet đọc loại tác vụ riêng. SwiftUI có thể dựng nội dung sheet bằng giá trị cũ ở lần mở đầu ⇒ ra sheet "Tải video", bấm Bắt đầu thành tác vụ tải.
- **Sửa**: `TaskSheetRequest` (mới, `Views/Download/`) gộp sách + loại tác vụ + cờ "chỉ chương đã tải" làm **một** item cho `.sheet(item:)` ở cả 5 nơi (`ShelfView`, `ShelfSearchView(+Actions)`, `CollectionDetailView`, `BookDetailView` + `BookDetailActionSheetModifier`, `DownloadTrackerView`).
- **"Xuất video đã tải" / "Xuất chương đã tải"**: nhãn ở sheet nhấn giữ, màn Chi tiết và tab Tải (thay "Xuất video", "Xuất CBZ/PDF"). `TaskOptionsSheet` xuất truyện tranh/video mặc định bắt đầu **từ đầu** (mọi tập/chương đã tải) thay vì từ tập/chương đang xem; vẫn đổi được mốc bắt đầu và số lượng.
- Chuyển entry `[1.3.624]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows); chưa thử trên máy — bấm "Xuất video đã tải" ở Kệ và Chi tiết ngay lần đầu mở app: sheet phải là "Xuất video", tác vụ là xuất.

## [1.3.653] - 2026-10-29

### fix: xuất video nhiều file chia sẻ được từng file thay vì thư mục

Người dùng: *"xuất video dạng folder nên đâu gửi được"* — đúng rủi ro đã ghi ở 1.3.650.

- **`ExportShareCoordinator`**: bản xuất là **thư mục** (video nhiều tập, hoặc một tập kèm file tiếng / phụ đề) ⇒ lúc mở bảng chia sẻ bung thành danh sách mọi file thường bên trong (bỏ file ẩn, xếp tên tự nhiên — "Tập 2" trước "Tập 10") và đưa cả danh sách vào `UIActivityViewController` ⇒ "Lưu vào Tệp" / AirDrop nhận nhiều file một lượt. Bản xuất một file giữ nguyên. Thư mục rỗng ⇒ toast lỗi.
- Chuyển entry `[1.3.623]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows); chưa thử trên máy — xuất 2 tập rồi "Lưu vào Tệp" và AirDrop.

## [1.3.652] - 2026-10-29

### fix: trang có nút back hiện tiêu đề giữa, nút chữ header 17pt nửa đậm

Người dùng: *"các màn khác cũng vậy nhé, đồng bộ 1 size chữ title, 1 size button icon, 1 size button chữ"*, rồi *"Reader, Truyện tranh, Trình y như cũ … Trừ chi tiết và reader thì hãy giữ title giữa cho các màn có back"*; duyệt mockup.

- **Tiêu đề ba kiểu** (`PageTitleStyle`: `.leading` / `.centered` / `.hidden`, `PageTitleModifier`): `.pageTitle(_:)` = trái (tab gốc, gốc sheet, như 1.3.641); `.backPageTitle(_:)` = **giữa**, 22pt đậm, một dòng, thu nhỏ tới 80% rồi cắt đuôi (trước đây không hiện); `.pageTitle(_:style:)` cho màn mở hai kiểu (9 chỗ: `style: cờ ? .leading : .centered`). Ngoại lệ **Chi tiết truyện** `.hidden`. Reader, truyện tranh, trình phát video giữ header riêng như cũ.
- **Nút chữ trên header** (`.headerTextButton()`, mới): 17pt nửa đậm cho 31 chỗ (Lưu, Nhập, Xong, Bắt đầu, Khôi phục, Áp dụng, Xác nhận, Xóa tất cả…, nhãn của menu "Lưu ▾", 4 `EditButton`); bỏ `.fontWeight(.bold/.semibold)` lẻ tẻ cũ. Nút xoá vẫn đỏ.
- **Icon**: nút đóng Trợ lý AI toàn màn `chevron.down` trong ô tròn nền xám ⇒ `chevron.down.circle` không nền, cùng kiểu `ellipsis.circle` bên cạnh; "Tab mới" của trình duyệt `plus.square.on.square` ⇒ `plus.square`; icon thẻ thể loại ở Khám phá 16pt thường ⇒ 17pt nửa đậm.
- CLAUDE.md/AGENTS.md: cập nhật mục "Header trang & sheet" và chuẩn nút chữ header.
- Chuyển entry `[1.3.622]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows); chưa thử trên máy — tiêu đề giữa dài (Thể loại, Bình luận, Bộ sưu tập) có chèn icon phải không; nút `.confirmationAction`/`EditButton` có bị iOS tự in đậm thêm không.

## [1.3.651] - 2026-10-29

### fix: chỉ widget TTS nổi trên ngăn kéo menu, hub và trình duyệt nằm dưới

Người dùng: *"sửa lại cho widget tts cao hơn menu ... thôi, vì nếu như widget kia cao hơn thì bấm vào xem thông báo từ widget không xem được menu ..."*.

- **`SideDrawerMenuWindowManager`**: cửa sổ ngăn kéo `alert - 3.5` (1.3.648, dưới mọi widget) ⇒ `alert - 1.5` — **dưới** widget TTS (`alert - 1`) và toast, **trên** hub (`alert - 2`) và trình duyệt thu nhỏ (`alert - 3`). Widget TTS vẫn bấm được khi menu mở; hub/trình duyệt không còn che menu "…" (bấm hub mở Thông báo lúc menu đang mở không đè lên menu).
- Chuyển entry `[1.3.621]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows); chưa thử trên máy — mở menu "…" khi widget TTS và hub cùng hiện.

## [1.3.650] - 2026-10-29

### feat: xuất video từ các tập đã tải

Người dùng: *"làm thêm xuất video"* — chọn HLS **ghép .ts**, đích **Tệp + chia sẻ**; duyệt plan.

- **Lối vào**: "Xuất video" ở sheet nhấn giữ và màn Chi tiết của sách video ⇒ `TaskOptionsSheet` định dạng "Video" (chọn tập bắt đầu + số tập như tác vụ tải); tab Tải có "Xuất video từ tập đã tải". `BookExportFormat.video`, `TaskType.exportVideo` ("Xuất video", rawValue mới — dữ liệu cũ vẫn đọc được); mọi `switch` liên quan đã cập nhật.
- **Tác vụ** (`DownloadManager+VideoExport`, rẽ từ `executeMediaTaskIfNeeded`, không cần tiện ích ⇒ phim nhập từ file cũng xuất được): chỉ lấy tập có manifest khớp url tập; kiểm dung lượng trống (tổng `totalBytes` × 1,05); mỗi phim một tác vụ video (tải hoặc xuất) chạy một lúc; tập lỗi bỏ qua kèm dòng tổng kết; huỷ/lỗi xoá bản dở.
- **Từng tập** (`Sources/Services/Export/Video/`): tập dạng file chép nguyên; tập HLS đọc playlist trên máy (`VideoHLSLocalStream`), nối đoạn theo thứ tự (tôn trọng `BYTERANGE`), giải mã AES-128-CBC theo luồng bằng CommonCrypto (`VideoAES128CBCDecryptor`, IV từ playlist hoặc số thứ tự media), khúc 1 MiB — không đọc cả tập vào RAM. Đoạn `.ts` ⇒ file `.ts` (mở bằng VLC/Infuse, không mở bằng Ảnh/Tệp của iOS); fMP4 ⇒ init + đoạn ⇒ `.mp4`. Luồng tiếng tách riêng ⇒ thêm file `… (tiếng)`; phụ đề chép kèm `<tên>.<ngôn ngữ>.<đuôi>`.
- **Đích**: một tập chỉ một file ⇒ `Documents/Exports/<Tên phim> - Tập N.<đuôi>`; còn lại (nhiều tập, hoặc có file tiếng/phụ đề) ⇒ một thư mục trong `Exports/`, chia sẻ cả thư mục qua `ExportShareCoordinator`. Bản xuất loại khỏi sao lưu iCloud.
- **Không làm**: chuyển HLS sang mp4 (FFmpeg), lưu vào Ảnh, xuất tập chưa tải.
- Chuyển entry `[1.3.620]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là lần biên dịch đầu; chưa thử trên máy — **share sheet có nhận thư mục không** (không thì bản nhiều file không lấy ra được), file `.ts` trong VLC, ghép phim vài GB, xoá tác vụ không xoá file đã xuất (như mọi loại xuất cũ).

## [1.3.649] - 2026-10-29

### fix: widget nổi không đè lên nhau khi cùng mép

Người dùng: *"đừng cho các widget đè lên nhau nhé"* — duyệt plan.

- **`FloatingWidgetLayoutCoordinator`** (mới, `Views/Common/`, `@MainActor`): widget TTS, nút hub, nút mở lại trình duyệt — mỗi cái một cửa sổ riêng, trước đây không biết nhau — đăng ký khoảng dọc đứng yên theo cạnh; ẩn thì gỡ. `resolve(id:edge:proposedCenterY:height:minY:maxY:)` chọn tâm Y **trống gần đề xuất nhất** (khe 8pt) trên cạnh đề xuất, hết chỗ thì thử cạnh kia, cả hai hết thì giữ nguyên + log. Tìm thẳng điểm trống gần nhất (đầu mút khoảng cấm) nên không lắc qua lại giữa hai widget.
- **Khi nào xếp**: thả tay sau khi kéo (dời có hiệu ứng) và lúc widget vừa hiện (đặt thẳng vào chỗ trống trước khi hiện — không thấy cảnh chồng rồi mới tách). Widget vừa kéo/vừa hiện là bên nhường, widget đứng yên không bị đẩy. Vị trí mới lưu như kéo tay (`applyResolvedPlacement` + `persistPosition` ở ba view model). Xoay màn / đổi vùng an toàn chỉ báo lại khung (`refresh`), không xếp lại.
- **Widget TTS** giữ chỗ theo chiều cao mở rộng (56pt, 80pt khi đang hẹn giờ). Hai cạnh khác nhau không xét; menu bung của hub không xét.
- File mới `FloatingHubContainerViewController+Placement.swift`; `FloatingWidgetGeometry.centerYRange`.
- Chuyển entry `[1.3.619]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows); chưa thử trên máy — kéo hai widget về cùng mép cùng độ cao, mở app khi cả ba cùng hiện, bật hẹn giờ TTS sau khi đã xếp (chưa xếp lại theo chiều cao mới), màn ngang.

## [1.3.648] - 2026-10-29

### fix: widget nổi luôn nằm trên ngăn kéo menu

Người dùng: *"bạn sửa gì mà widget tts và widget khác bị che bởi ngăn kéo "…""* → chọn *"Widget nổi trên"*.

- **Nguyên nhân**: từ 1.3.628 cửa sổ ngăn kéo ở level `alert - 0.5`, **trên** widget TTS (`alert - 1`), hub (`alert - 2`), trình duyệt thu nhỏ (`alert - 3`), lớp tối 30% của nó phủ cả màn. Trước 1.3.645 nền ngăn kéo không thật sự nhoè (kính iOS bị giảm độ hiện) nên vẫn nhìn xuyên thấy widget; từ khi nền nhoè thật (1.3.645 ảnh chụp, 1.3.647 kính 6 nấc) widget dưới vùng ngăn kéo bị che hẳn.
- **Sửa**: `SideDrawerMenuWindowManager` đặt cửa sổ ngăn kéo ở `alert - 3.5` — dưới cả ba widget và toast ⇒ widget luôn nổi trên ngăn kéo và lớp tối, bấm được bình thường (như thời `fullScreenCover`). Đánh đổi: widget ở mép phải có thể che vài hàng menu.
- Chuyển entry `[1.3.618]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows); chưa thử trên máy — mở ngăn kéo khi widget TTS / hub đang hiện, bấm widget lúc ngăn kéo mở.

## [1.3.647] - 2026-10-29

### fix: ngăn kéo menu bỏ ảnh chụp nền, độ đục theo 6 nấc kính như nút nổi

Người dùng: *"revert ngăn kéo "…" lại đi, sửa thành 6 nấc"*.

- **Gỡ ảnh chụp nền của 1.3.645**: `SideDrawerMenuPanel`, `SideDrawerMenuWindowRoot`, `SideDrawerMenuWindowManager` về đúng bản trước 1.3.645 (không còn `captureBackdrop`, không chụp màn khi mở ngăn kéo).
- **`SideDrawerGlassBackground`**: dùng chung 6 nấc kính iOS với nút nổi (`GlassFrostLevel`: Không nhoè / Rất mỏng / Mỏng / Vừa / Dày / Rất dày), luôn vẽ ở độ hiện 100%; thêm `trailingRadius` cho ô xem trước. Mặc định 60% ⇒ nấc "Vừa".
- **Cài đặt › Giao diện**: thanh độ đục của ngăn kéo bước 20% kèm tên nấc như nút nổi; ô xem trước ngăn kéo chỉ cắt góc dải bìa, không cắt khung chứa lớp kính. Sửa chú thích `GlassChromeSettings`, `GlassFrostLevel`.
- Chuyển entry `[1.3.616]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows); chưa thử trên máy — cần xem 6 nấc của ngăn kéo trên nền Kệ.

## [1.3.646] - 2026-10-29

### fix: sheet nhập truyện thấp vừa ba lựa chọn

Người dùng: *"sheet import cao quá, điều chỉnh lại chiều cao vừa phải thôi"*.

- **`ShelfImportSheet`**: nấc `.medium` thành nấc gọn `.height(300)` (thanh kéo + tiêu đề + ba hàng) và `.large`, có `selection`; bước "Từ URL" tự lên `.large` (bàn phím + danh sách nguồn khớp), quay lại thì về nấc gọn. Không dùng `fittedSheetDetent` vì `List` trong `NavigationStack` không đo được chiều cao.
- Chuyển entry `[1.3.617]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows); chưa thử trên máy — cỡ chữ lớn có thể cần kéo lên.

## [1.3.645] - 2026-10-29

### fix: ngăn kéo nhoè mịn theo độ đục, nút nổi chỉnh độ đục theo 6 nấc kính

Người dùng: *"Vì sao config độ đục giữa 95% và 100% nó khác biệt hoàn toàn vậy?"* — điều tra lại, chọn phương án B (ảnh chụp nền cho ngăn kéo).

- **Nguyên nhân**: 1.3.640 vẽ `.ultraThinMaterial` rồi `.opacity(độ đục)`. Tài liệu `UIVisualEffectView` của Apple: alpha < 1 trên lớp hiệu ứng hoặc lớp cha ép vẽ tách riêng ⇒ hiệu ứng "hiện sai hoặc không hiện". Kính SwiftUI chạy cùng cơ chế ⇒ 0–95% thực ra **không nhoè** (chỉ phủ lớp xám), chỉ 100% mới nhoè. Mặc định ngăn kéo 60% vì vậy chưa từng nhoè.
- **Ngăn kéo** (`SideDrawerGlassBackground<Backdrop>`): bỏ kính iOS, nhoè **mịn** bằng SwiftUI `.blur(radius: độ đục × 28pt, opaque: true)` trên ảnh chụp màn bên dưới. `SideDrawerMenuWindowManager.captureBackdrop` chụp cửa sổ chính (level `.normal`) bằng `drawHierarchy(afterScreenUpdates: false)` ở scale 1 lúc mở, chỉ khi độ đục > 0; ảnh đi qua `Session` → `Presentation` → `SideDrawerMenuPanel`, nhả khi ẩn cửa sổ; có log `[Drawer]` đo ms, chụp lỗi ⇒ log `❌` và mở như độ đục 0. Ảnh phủ lớp tối 30% như `dimmingLayer` (không thì từ 0 lên 5% phần sau ngăn kéo sáng vọt), dịch `-offset` của ngăn kéo để đứng yên theo màn khi trượt/vuốt. Video và trang web có thể ra tối trong ảnh chụp.
- **Nút nổi** (`FloatingGlassBackground`): độ đục thành 6 nấc kính iOS (`GlassFrostLevel`: Không nhoè / Rất mỏng / Mỏng / Vừa / Dày / Rất dày), luôn vẽ ở độ hiện 100%; giá trị đã lưu làm tròn về nấc gần nhất (bước 0,2).
- **Cài đặt › Giao diện**: thanh độ đục nút nổi bước 20% kèm tên nấc ("60% · Vừa"); ô xem trước nút nổi chỉ cắt góc dải bìa (kính iOS hỏng khi lớp cha bị cắt mặt nạ); ô xem trước ngăn kéo nhoè chính dải bìa theo cùng công thức. Sửa chú thích sai ở `GlassChromeSettings`.
- **Thay đổi thấy được**: ngăn kéo để mặc định 60% giờ mới nhoè thật.
- Chuyển entry `[1.3.615]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng**: đọc code + tài liệu Apple; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy — cần thử kéo độ đục ngăn kéo 0→100% (mịn, không nhảy), ngăn kéo trượt vào/vuốt ra (nền đứng yên), độ trễ mở ngăn kéo (log `[Drawer]`), 6 nấc nút nổi.

## [1.3.644] - 2026-10-29

### fix: nhập truyện tranh và phim từ file bị từ chối do lệch tiền tố /private

Người dùng gửi log: `❌ [MediaImport] Lỗi chuẩn bị nhập truyện tranh: Truy cập file ngoài thư mục tạm bị từ chối.` (và cùng lỗi với phim) — mọi lượt nhập comic/phim của 1.3.642 đều hỏng ngay bước đầu.

- **Nguyên nhân**: `LocalMediaImportWorkspace.isInside` so `standardizedFileURL.path` của gốc `tmp/LocalMediaImport/` với file đích. iOS trả `temporaryDirectory` dạng `/private/var/…`; chuẩn hoá chỉ bỏ `/private` khi đường dẫn **đang tồn tại** ⇒ gốc (đã có) thành `/var/…`, file đích (chưa tạo) vẫn `/private/var/…` ⇒ lệch tiền tố, `adopt` từ chối mọi file. Truyện chữ không bị (đi luồng nhập cũ).
- **Sửa**: chuẩn hoá **thư mục cha** của đích (luôn đã tồn tại lúc gọi) bằng cùng cách với gốc (`standardizedFileURL.resolvingSymlinksInPath()`) rồi ghép tên file; tên rỗng / `.` / `..` / chứa `/` bị từ chối. `discard` và dọn thư mục cũ đi cùng hàm nên cũng nhất quán. Các kiểm đường dẫn khác của luồng nhập (quét ảnh sau giải nén) so hai đường dẫn đã tồn tại nên không dính lỗi này.
- Chuyển entry `[1.3.614]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy — cần nhập lại một `.cbz` và một `.mp4`.

## [1.3.643] - 2026-10-29

### feat: chạm 1/3 hai bên để chuyển chương ở Reader và truyện tranh

Người dùng: *"Tôi muốn thêm hành động tap ở 1/3 màn hình trái phải để chuyển chương. Nhưng sợ xung đột với hành động bôi đen"* — duyệt plan, công tắc mặc định **bật**.

- **`ReaderEdgeTapDetector`** (`Sources/Views/Reader/Components/`): `UITapGestureRecognizer` không tiêu thụ touch gắn lên `UIScrollView` của chương (cùng mẫu `ReaderUserScrollDetector`: `cancelsTouchesInView = false`, nhận đồng thời, không đòi recognizer khác fail) ⇒ không giành touch của ô chữ. 1/3 trái ⇒ chương trước, 1/3 phải ⇒ chương sau, giữa không làm gì; tính cả chạm lên chữ lẫn lề.
- **Không tính là chạm chuyển chương** khi: lúc đặt ngón đang có đoạn bôi đen / menu bôi đen hiện (chạm để bỏ bôi đen); giữ > 0,35 s hoặc kéo; trang đang trôi/đang kéo (chạm để dừng cuộn); chạm đúp — chờ 0,25 s, có chạm thứ hai hoặc chữ vừa được bôi đen thì huỷ; chương đầu/cuối; chương đang tải/lỗi (khung cuộn chưa có). Khung nội dung chương chỉ chứa đoạn chữ, nút Chương trước/sau ở thanh điều khiển ngoài ⇒ không bấm trùng nút.
- Chuyển chương đi qua `stepChapterHonoringTTS` như nút Chương trước/sau (tôn trọng TTS đang đọc), rung nhẹ. Hai đầu dò gộp thành `readerScrollProbes` ở `ReaderView+Controls`.
- Công tắc "Chạm hai bên để chuyển chương" ở Cài đặt đọc (`@AppStorage("readerEdgeTapChangesChapter")`, mặc định bật).
- **Truyện tranh** (người dùng: *"Comic làm luôn, cho config chọn kiểu mới này và kiểu vuốt cũ. Mặc định kiểu mới"*): `ComicChapterNavigationMode` (`@AppStorage("comicChapterNavigationMode")`) chọn ở ngăn kéo "…" mới trên thanh trên của màn đọc ("Tuỳ chọn đọc" › "Chuyển chương"). **Chạm hai bên** (mặc định): chạm 1/3 trái/phải trên ảnh hoặc dòng "Hết chương" ⇒ chương trước/sau, giữa ⇒ bật/tắt thanh, vuốt ngang không đổi chương. **Vuốt ngang**: như 1.3.613. Chạm đúp vẫn phóng to (`ComicPageView` báo điểm chạm `.global`). Dòng gợi ý cuối chương đổi theo kiểu; chạm hai bên và vuốt dùng chung `stepChapter(forward:)` (chặn khi đang nạp chương, toast ở chương đầu/cuối). CLAUDE.md/AGENTS.md cập nhật mục màn đọc comic.
- Chuyển entry `[1.3.613]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy — cần thử: nhấn giữ bôi đen, chạm đúp chọn từ, kéo nới vùng chọn, chạm bỏ bôi đen, chạm khi trang đang trôi, chạm lúc TTS đang đọc; truyện tranh: chạm hai bên, chạm đúp phóng to, chuyển kiểu ở ngăn kéo "…".

## [1.3.642] - 2026-10-29

### feat: nhập truyện tranh và phim từ file, xuất truyện tranh CBZ/PDF

Phần P5 của plan `Docs/Plans/2026-10-29-plan-dong-bo-ui-va-nhap-media.md`, tách khỏi 1.3.641 theo yêu cầu người dùng ("push sau").

- **Loại nội dung không đổi `@Model`**: sách nhập từ file dùng packageId `local-comic` / `local-video` (`LocalMediaPackage`), url vẫn `local://…` nên `Book.isLocalBook` giữ đúng; `ExtensionContentKind` thêm hai nhánh, `BookContentDestination` tự mở đúng màn. Dịch tên theo công tắc chung như sách `"local"` (`TranslationConfigStore.isLocalPackage`).
- **Nhập truyện tranh** (`Services/Import/Media/LocalComicImporter`): một file `.cbz`/`.zip` = cả bộ (người dùng chốt); giải nén vào `tmp/LocalMediaImport/<uuid>/`, mỗi thư mục chứa ảnh là một chương (tên tự nhiên, bỏ thư mục bọc chung), không có thư mục con ⇒ một chương. Sheet "Nhập truyện tranh" (tên sửa được, "Chương N · X ảnh") ⇒ chuyển ảnh vào `ComicOfflineStore` (manifest `chapterUrl` = url mục lục, host chương nil), `replaceFullTOC`, bìa = trang đầu. File nén chứa symlink ⇒ huỷ lượt nhập. `.zip` là EPUB vẫn nhập dạng chữ.
- **Nhập phim** (`LocalVideoImporter`): một hay nhiều `.mp4`/`.mov`/`.m4v` gộp một phim, tập theo tên file; sheet "Nhập phim" ⇒ **chuyển** file (không đọc vào RAM) vào `VideoOfflineStore`, manifest `.file`, bìa là một khung hình; khác ổ thì chép (kiểm dung lượng) rồi xoá nguồn. Chọn nhiều file lẫn loại ⇒ báo lỗi, không nhập gì.
- **Sách nhập media**: ẩn Tải offline, Xoá bản tải, chip Bản tải/Trực tuyến, nút tải ở mục lục comic, Thay đổi nguồn và Mở bằng trình duyệt ở Chi tiết (đổi nguồn xoá mất bản duy nhất). Thiếu file (khôi phục backup) ⇒ "…không còn trên máy — hãy nhập lại file". Backup **không** gói ảnh/video của sách nhập (người dùng chốt).
- **Xuất truyện tranh**: `BookExportFormat.cbz` / `.pdf` (+ `TaskType`, rawValue lưu bền, dữ liệu cũ vẫn đọc được); `DownloadManager+ComicExport` chỉ lấy chương đã có ảnh offline, CBZ bằng `ZipStoreWriter` (chặn trước khi ghi nếu vượt 65.535 ảnh / 4 GB — `ZipStoreWriter` cũng tự chặn entry thứ 65.536 thay vì tràn `UInt16`), PDF mỗi ảnh một trang (JPEG nhúng nguyên). Picker định dạng lọc theo loại; "Xuất CBZ/PDF" ở sheet nhấn giữ, Chi tiết, tab Tải. Tiến độ trễ không đưa tác vụ đã xong về "Đang chạy".
- Thư mục làm việc bỏ dở (> 6 giờ) dọn ở lượt nhập kế tiếp. Chuyển entry `[1.3.612]` sang `CHANGELOG.archive.md`.
- **Chưa làm**: CBR/RAR/7z, ZIP mật khẩu, xuất phim, `ComicInfo.xml`, chặn zip bomb trước khi giải nén (đầy ổ ⇒ giải nén lỗi ⇒ dọn thư mục), dọn sách nhập dở khi app bị tắt giữa lúc ghi.
- **Kiểm chứng**: đọc code + rà soát bằng agent (không thấy lỗi biên dịch; đã sửa crash CBZ > 65.535 ảnh, symlink, dịch tên sách media, tiến độ trễ); `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy — cần thử sheet xác nhận sau bộ chọn file, mở comic/phim vừa nhập, mov/m4v, phim vài GB, PDF webtoon dài, CBZ mở ở app khác.

## [1.3.641] - 2026-10-29

### feat: đồng bộ header, menu, danh sách panel và nhập truyện ở Kệ

Người dùng yêu cầu một loạt đồng bộ giao diện (plan `Docs/Plans/2026-10-29-plan-dong-bo-ui-va-nhap-media.md` + `2026-10-29-plan-nut-header-sheet.md`, đã duyệt mockup). Phần nhập/xuất comic/video tách sang entry sau.

- **Ngăn kéo menu "…"**: bỏ vạch giữa các hàng, vạch dưới tiêu đề và dải tối giữa nhóm (`SideDrawerDivider` thành khoảng trống 12pt); tiêu đề 22pt đậm một dòng, tiêu đề nhóm 13pt đậm. `SideDrawerActionRow` thêm `badgeCount:`.
- **Kiểu Danh sách**: mỗi truyện là panel bo góc (`BookListPanelModifier`, nền `secondarySystemBackground`, bo 12), không vạch ngăn — Kệ/Lịch sử/Bộ sưu tập, tab danh mục Khám phá/Thể loại, tìm một nguồn, Tìm trên kệ, khung chờ. Vẫn là `List` (vuốt hàng, kéo tải lại, tiêu đề nhóm dính, cuộn về vị trí cũ).
- **Nút xoá/dọn đỏ** (chữ + icon): "Dọn dẹp tác vụ", "Xóa tất cả" lịch sử tìm (Tìm kiếm, Tìm trên kệ), "Xóa lịch sử" trang chủ trình duyệt, xoá trí nhớ AI, pill "Xoá bản tải", nút thùng rác xoá chữ trong ô.
- **Header trang** (`Common/PageHeader/PageTitleModifier`): tab gốc + sheet tiêu đề trái 22pt đậm một dòng; trang có nút back không hiện tiêu đề (vẫn giữ `navigationTitle` cho VoiceOver/menu nút back); màn mở hai kiểu nhận cờ `isPresentedAsSheet`. Áp ~100 màn; tiêu đề tab gốc viết thường ("Kệ sách", "Kho tiện ích", "Cài đặt"…). Nút trái của tab gốc dồn sang phải.
- **Kệ**: chuông vào hàng "Thông báo" đầu ngăn kéo (badge số); có thông báo ⇒ chấm đỏ trên nút "…". Nút + nổi ở tab Kệ sách mở sheet nửa màn "Nhập truyện": Từ URL (dò `regexp` tiện ích bằng `ExtensionUrlMatcher` tách khỏi `BypassWebView`; 1 khớp ⇒ Chi tiết, nhiều ⇒ chọn nguồn, 0 ⇒ mở trong trình duyệt; nút dán dạng icon), Mở trình duyệt, Từ file. Hàng "Nhập truyện từ file" của ngăn kéo thành "Nhập truyện" mở cùng sheet.
- **Sheet nhấn giữ sách**: "Mở trong trình duyệt" (trừ sách nhập file) và "Đánh dấu / Bỏ đánh dấu NSFW" (ẩn với nguồn 18+). Dấu lưu ở `UserDefaults` `nsfwMarkedBookIds` (`NsfwBookMarkStore`); `RepositoryFilterPolicy.isNsfwBook` = dấu || nguồn, áp ở Kệ/Lịch sử, Bộ sưu tập, Tìm trên kệ, tác vụ tải, hub AI, chọn truyện nguồn/đích, tắt tiếng phim (`VideoMutePolicy.shouldStartMuted(bookId:packageId:)`). Chưa áp: mục video của hub, Cấu hình dịch riêng, kết quả Tìm kiếm (không có bookId).
- **Sheet bỏ nút chỉ để đóng** (Huỷ/Đóng/✕/Xong/Bỏ qua không lưu, ~52 chỗ): vuốt xuống để đóng + thanh kéo. Nút trái còn lại sang phải dạng icon (Đặt lại bộ lọc ↺ đỏ, ⚙ Hẹn giờ TTS, ⌄ Trợ lý AI, tab mới của trình duyệt, ↻ Kho). Nút header chỉ chữ hoặc chỉ icon ("Lưu" của Script editor chỉ còn chữ). Màn toàn màn giữ lối đóng. Sheet mã xác minh Legado nay vuốt đóng được (= huỷ).
- **"Bỏ thay đổi?" khi vuốt lúc chưa lưu** (`Common/SheetDismissGuard/`): proxy `UIAdaptivePresentationControllerDelegate` chuyển tiếp mọi callback cho delegate gốc, giữ mạnh + gỡ khi probe bị gỡ; chỉ chặn vuốt khi đã cài được proxy (không cài được ⇒ vuốt đóng thẳng, không kẹt). Áp cho Sửa JSON nguồn, Script editor, Thêm/Sửa rule (Bỏ ⇒ xoá nháp). Tạo giọng VieNeu: dọn ghi âm/mẫu dời sang `onDisappear`.
- **Giải thích → nút "?"** (`SectionHelpButton` chuyển từ `QuickTranslationRuleHelpButton`, `SectionHelpHeader`): 84 footer giải thích chuyển hẳn vào popover cạnh tiêu đề section, 8 footer tách đôi (giải thích vào "?", số liệu/trạng thái giữ footer), 4 giữ nguyên (sentinel tải thêm, "Nhịp chạy").
- CLAUDE.md/AGENTS.md: thêm quy ước "Header trang & sheet (1.3.641)". Chuyển entry `[1.3.611]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng**: đọc code + rà soát bằng agent (không thấy lỗi biên dịch chắc chắn; đã sửa 4 rủi ro logic: sheet kẹt khi proxy không cài được, `original` yếu, đóng nhầm màn dưới ở trình bày Legado, hộp thoại sao lưu gắn header); `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy — cần thử vuốt đóng rồi mở lại từng sheet, hộp "Bỏ thay đổi?", tiêu đề dài trong toolbar, sheet "Nhập truyện" + mở trình duyệt/Chi tiết sau khi đóng, chấm đỏ nút "…".

## [1.3.640] - 2026-10-28

### fix: độ trong suốt và độ đục của nút nổi, menu áp đúng cài đặt

Người dùng: *"Cài đặt trong suốt không hoạt động. Tôi cài kiểu gì cũng hiển thị giống 2 hình đầu"* (ảnh: nút tai nghe Reader là đĩa xám đặc, ngăn kéo menu xám đều; ô xem trước ở màn Giao diện thì đổi đúng theo thanh kéo).

- **Nguyên nhân (khả năng cao, chưa kiểm được trên máy)**: lớp nhoè `SideDrawerPartialBlurView` (1.3.633) dùng `UIViewPropertyAnimator` dừng giữa chừng để có mức nhoè lưng chừng. Animator dễ bị hệ thống chạy hết (dựng view lần đầu, chuyển màn, app vào nền rồi về) ⇒ kẹt ở mức nhoè **đầy đủ**; ô xem trước trông đúng chỉ vì mỗi lần kéo thanh là animator được dựng lại. Hệ quả: "kính đục vừa" của 1.3.633 nhiều khả năng chưa bao giờ hiện đúng trên máy, và mọi giá trị cài đặt trông như nhau.
- **`FloatingGlassBackground`, `SideDrawerGlassBackground`**: lớp nhoè thay bằng shape tô `.ultraThinMaterial` (ép tông tối/sáng qua `colorScheme`) với `.opacity(frost)` — không có trạng thái nên không kẹt. Lớp màu vẫn `1 − độ trong suốt`, viền giữ nguyên.
- **Đánh đổi** (người dùng đã duyệt): 0% và 100% đúng y cài đặt; mức giữa là nền rõ trộn nền nhoè (hơi có bóng đôi) thay vì nhoè mịn bán kính nhỏ.
- Xoá `SideDrawerPartialBlurView.swift` (chỉ hai chỗ dùng trên); sửa chú thích `GlassChromeSettings`.
- Chuyển entry `[1.3.610]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy — cần thử 0%/100% ở cả ngăn kéo lẫn nút tai nghe, và sau khi cho app vào nền rồi mở lại.

## [1.3.639] - 2026-10-28

### fix: tin dừng lọc name không còn hiện hai lần

Người dùng: *"Đã dừng lọc name ở ch.115: Chương 116: Dò xét động cùng gặp lại U Minh Hà.. tôi bấm dừng lọc name, dòng này xuất hiện 2 lần"*.

- **Nguyên nhân** (lỗi của 1.3.632): `stopActiveTask` thêm tin dừng vào phiên của coordinator qua `updateRun` ⇒ `$runs` phát ⇒ màn AI `mergeRunningSession` đã gộp tin đó vào phiên đang hiện; sau đó `appendStopNote` của màn lại dựng **một tin mới** (khác `id`) từ chuỗi trả về ⇒ hai dòng.
- **`AIRuntimeCoordinator.stopActiveTask`** trả về chính `AIChatMessage` đã thêm (thay cho `String?`); **`ReaderAIFullScreenView.appendStopNote`** chỉ thêm khi phiên đang hiện chưa có tin cùng `id` — đúng dù `$runs` tới trước hay sau.
- **`nameScanStopNote`**: tên chương đã kết bằng `.`/`!`/`?`/`…` thì không thêm dấu chấm (hết "Hà.."); áp cho cả tin dừng tay lẫn dòng đầu tin lỗi khi tự dừng.
- "ch.115" cạnh tên "Chương 116" **không** phải lỗi: số ch. là vị trí trong mục lục (đếm từ 1, `AINameScanTextLoader` lấy `chapter.index`), tên là cách nguồn tự đánh số — giữ nguyên.
- Phiên chat đã lưu trước bản này vẫn giữ hai dòng cũ; chỉ lần dừng sau mới đúng.
- Chuyển entry `[1.3.609]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.
