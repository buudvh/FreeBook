# CHANGELOG - Nhật ký Thay đổi CodeGraph FreeBook

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **FreeBook**.

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

## [1.3.638] - 2026-10-28

### feat: xuất TXT cho từ điển chung

Người dùng: *"thêm nút xuất ra txt cho vp,name,phiên âm,… chung"*; chọn "icon trên mỗi thẻ" và "đúng file gốc"; duyệt mockup + plan.

- **Service** `GlobalDictionaryTextExporter` (mới, `Services/Translation/Manager/`): xuất một từ điển chung ra file tạm `VietPhrase_/Name_/PhienAm_/Pronouns_/LuatNhan_<yyyyMMddHHmmss>.txt`. VietPhrase/Name/Pronouns/LuatNhan duyệt ngược cây đang nạp (hoặc mở `.dat`) bằng `allEntries()`, ghi `từ=nghĩa` theo khúc ~1 MB; số entry phải khớp `wordCount`, lệch thì báo lỗi, không xuất file thiếu (cùng chốt chặn với `DictionaryMergeService`). PhienAm (và `.txt` chưa kịp biên dịch) chép nguyên file. Xuất **đúng file gốc** — không kèm từ thêm/xoá ở VP/Name Chung (bản đó đi qua nút Gộp); nhập lại qua chính thẻ cho ra từ điển y như cũ.
- **Cài đặt dịch thuật › Từ điển chung**: icon ↑ cuối mỗi thẻ (`TranslationSettingsView+Export`, phủ `overlay` lên thẻ vì thẻ là nhãn của nút Nhập — lồng nút trong nhãn nút thì chạm lẫn nhau; `DictionaryCard` chừa ô 32×32 qua `reservesExportSlot`). Chạm thẻ vẫn là Nhập. Đang xuất: vòng quay + "Đang xuất...", nút Nhập của thẻ đó khoá; một lượt xuất một lúc; thẻ chưa có dữ liệu thì icon mờ. Xuất chạy `Task.detached` rồi mở bảng chia sẻ; đóng bảng thì xoá file tạm; lỗi ⇒ toast + log `❌`.
- Chuyển entry `[1.3.608]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code + diff; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy. Rủi ro: VietPhrase cỡ trăm nghìn – triệu từ nên xuất mất vài giây và tốn RAM cỡ lúc Gộp.

## [1.3.637] - 2026-10-28

### fix: thanh kéo Giao diện cập nhật ngay, nút + nổi ở Lọc rác

Người dùng: *"cài đặt độ trong suốt và độ đục chưa hoạt động"*, *"nút thêm lọc rác chưa chuẩn hoá"*; duyệt mockup + plan.

- **Khoá cài đặt kính bỏ dấu chấm** (`GlassChromeSettings`): `glassChrome.floatingButton.transparency`… → `glassChromeFloatingTransparency`, `glassChromeFloatingFrost`, `glassChromeDrawerTransparency`, `glassChromeDrawerFrost`. `@AppStorage` nghe thay đổi qua KVO của `UserDefaults`, KVO đọc dấu chấm là key path lồng nhau ⇒ thanh kéo ghi được nhưng nút nổi, ngăn kéo và ô xem trước (mỗi view một `@AppStorage` riêng) không được báo. Mọi khoá `@AppStorage` khác trong app vốn không có dấu chấm. Giá trị đã kéo dưới khoá cũ (chỉ có từ 1.3.636) về mặc định một lần.
- **Ô xem trước** (`AppearanceSettingsView`): nền tối + chữ xám mờ đổi thành dải 5 "bìa" màu (Ch.1–Ch.5) chạy dưới nút và dưới ngăn kéo, cao 112 → 128pt — trên nền tối, lớp màu kính (xám 0.16) và độ nhoè gần như không đổi khi kéo. Mặc định và màu lớp kính giữ nguyên.
- **Lọc rác** (`JunkFilterManagementView`): "Thêm quy tắc" rời ngăn kéo thành nút "+" nổi (`.floatingAddButton`); nút "…" 17pt semibold như các màn danh sách khác; vạch ngăn sau "Sắp xếp lại" chỉ hiện cùng mục đó (đang tìm thì ngăn kéo không mở đầu bằng vạch). Hàng quy tắc giữ nguyên (người dùng loại Lọc rác khỏi đợt đồng bộ hàng ở 1.3.635).
- Chuyển entry `[1.3.607]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code + diff; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy. Nguyên nhân khoá có dấu chấm là suy từ code, chưa tái hiện được trên máy.

## [1.3.636] - 2026-10-28

### feat: màn Giao diện chỉnh nút nổi và menu, nút + nổi, danh sách cuộn vô cực

Người dùng: *"mấy chỗ danh sách lazyload hãy sửa lại thành scroll vô cực"* (chọn cả 4 chỗ), *"đồng bộ UI danh sách khác giống UI của vp/name luôn"*, *"đem hết nút trừ nút quay lại vào dropdown"*, *"đem nút thêm thành nút icon + ra ngoài ... vị trí tương tự nút tai nghe trong reader ... trong suốt. Sửa nút tai nghe trong suốt luôn"*, *"thêm nav giao diện ... gom hết các nav liên quan ... thêm cài đặt giao diện cho menu. có thanh kéo độ trong suốt độ đục"*, gom thêm NSFW; duyệt mockup + plan.

- **Cài đặt › Chung › Giao diện** (`AppearanceSettingsView`, mới): gom "Kiểu hiển thị danh sách", "Nội dung nhạy cảm (NSFW)", "Bàn phím & ô nhập" (bỏ ba dòng đó ở Chung/Thư Viện). Hai nhóm thanh kéo **Độ trong suốt** (lớp màu nền, 1 = không màu) / **Độ đục** (độ nhoè kính) + ô xem trước + "Đặt lại mặc định": **Nút nổi** (mặc định 90% / 0%) và **Menu ba chấm** (mặc định 45% / 60% = đúng "kính đục vừa" 1.3.633). Khoá ở `GlassChromeSettings`.
- **Nền kính dùng chung**: `FloatingGlassBackground` (nút tròn) và `SideDrawerGlassBackground` (ngăn kéo, thay nền gán cứng trong `SideDrawerMenuPanel`) đọc thẳng `@AppStorage` ⇒ kéo là đổi ngay. Nút tai nghe Reader (`readerEdgeButton`) thành nút 52pt nền kính theo cài đặt, tâm giữ đúng chỗ cũ (bỏ nền tối 34% + material + bóng).
- **Nút "+" nổi** (`FloatingAddButton`, `.floatingAddButton(_:action:)` qua `safeAreaInset` để hàng cuối không bị che): thay mục "Thêm…" của ngăn kéo / nút "+" header ở 7 màn — từ điển VP/Name, thay thế TTS, phiên âm NghiTTS, phiên âm VieNeu, công cụ tra cứu, quy tắc mục lục, rule dịch nhanh. Header các màn này chỉ còn nút quay lại + "…" 17pt semibold; "Khôi phục mặc định" của công cụ tra cứu vào ngăn kéo.
- **Hàng kiểu VP/Name** (cụm icon `.subheadline` [Sửa][Chuyển][Tắt/Bật `pause.circle`/`play.circle`][Xoá], giữ vuốt): thay thế TTS (bỏ công tắc; Chuyển chỉ ở tầng riêng), phiên âm NghiTTS (+Xoá), VieNeu (+Sửa/Xoá), công cụ tra cứu (+Sửa/Xoá, xoá theo id), quy tắc mục lục (`TOCRulesConfigView+Row`, bỏ công tắc; rule mặc định Xoá mờ).
- **Cuộn vô cực**: từ điển VP/Name (200/lượt), NghiTTS và VieNeu (100/lượt), rule dịch nhanh (200/lượt, bỏ nút "Xem thêm") nạp lượt kế khi hàng cách cuối 50 hoặc hàng cuối hiện ra; bỏ dòng "Cuộn xuống để tải thêm". **Tin nhắn AI** (`ReaderAIFullScreenView+OlderMessages`): cuộn lên gần đầu tự nạp 20 tin cũ, giữ chỗ bằng `scrollTo` tin đầu cũ; chỉ bật 0,6 s sau khi mở/đổi phiên. **Mục lục nhiều trang** (`BookDetailTOCView+AutoLoad`, lưới video `onReachEnd`): cuộn tới cuối tự tải các trang còn lại **một lần** mỗi lần dựng tab, không tự gọi khi đang báo lỗi (nút "Tải thêm" giữ làm thử lại) và không tự gọi khi đã có mục lục đầy đủ lưu trên máy.
- `CLAUDE.md`/`AGENTS.md`: quy ước màn danh sách (header, nút "+" nổi, hàng VP/Name, nạp trước, `GlassChromeSettings`); đường dẫn NSFW mới.
- Chuyển entry `[1.3.606]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code + diff; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy. Rủi ro cần thử: giữ chỗ khi nạp tin AI cũ (có thể xê dịch ~36pt), mục lục trang 1 ngắn vừa một màn sẽ tự tải ngay khi mở tab, xoá từ ở hai màn phiên âm nạp lại cả từ điển (hành vi cũ, giờ dễ gặp hơn vì icon Xoá một chạm).

## [1.3.635] - 2026-10-28

### fix: thay thế TTS hiện 2 dòng, đồng bộ cỡ chữ danh sách theo VP/Name

Người dùng: *"danh sách thay thế tts: mỗi rule hiển thị 2 dòng, dòng 1 là từ gốc, dòng 2 là mũi tên và từ thay thế. Giảm size chữ lại bằng size của danh sách vp/name. Đồng bộ size chữ các danh sách khác bằng vp/name luôn"*; duyệt mockup, chọn font thường (không monospaced) cho dòng regex, *"chỗ nào chưa hiển thị 2 hàng thì lọc ra chuyển thành 2 hàng luôn"*, *"lọc rác không làm"*.

- **Chuẩn**: hàng VP/Name `DictionaryEntryRow` — dòng khoá `.headline`, dòng giá trị `.subheadline` màu phụ.
- **Thay thế TTS** (`TTSReplacementManagerView+Layer`): `ruleText(for:)` mới dùng chung cho `ruleRow` và `globalRulesSection` — dòng 1 `"gốc"` `.headline` (màu phụ khi rule tắt), dòng 2 `→ "thay thế"` hoặc `→ (rỗng)` `.subheadline`; bỏ `.body` monospaced một dòng. Giữ dấu nháy vì nhiều rule mặc định thay bằng dấu cách. Icon sửa `.subheadline`; công tắc, vuốt "Sang chung", nút "Lấy" giữ nguyên.
- **Từ điển tiếng Nhật VieNeu** (`VieNeuJapaneseDictionaryView.row`): một dòng `khoá … cách đọc` thành hai dòng `.headline` / `.subheadline`, vẫn bấm cả hàng để sửa.
- **Chỉ đổi cỡ chữ**: rule dịch nhanh (`QuickTranslationRuleEntryRow`: pattern `.footnote` monospaced → `.headline`, replacement `.footnote` → `.subheadline`, giữ màu trắng và dòng "dòng N"/badge), công cụ tra cứu (`SearchEnginesConfigView`: URL `.caption` → `.subheadline`), quy tắc mục lục (`TOCRulesConfigView`: tên `.headline`, regex `.caption` monospaced → `.subheadline`, "Ví dụ" giữ `.caption2`), duyệt name AI (`ReaderAINameReviewCardView`: 13/12pt cố định → `.headline`/`.subheadline`, hàng cao hơn, badge giữ cỡ cũ).
- **Không đổi**: lọc rác (người dùng loại), xung đột khi nhập từ điển (bố cục `cũ → mới` cố ý), màn thử rule dịch nhanh, chọn quy tắc mục lục khi nhập truyện.
- Chuyển entry `[1.3.605]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.634] - 2026-10-28

### feat: tải truyện dừng và báo lỗi khi 5 chương liên tiếp tải lỗi

Người dùng: *"nếu tải bị lỗi 5 chương liên tiếp thì dừng lại và thông báo"*; chọn báo lỗi + Thử lại (không thêm trạng thái tạm dừng), áp cho chữ + comic + video, xuất ebook bị dừng thì không ghi file; duyệt plan.

- **`DownloadFailureStreak`** (mới): ngưỡng `limit = 5` (cùng `TTSManager.maxConsecutiveChapterFailures`); chương lỗi ⇒ +1, chương lấy được hoặc đã có sẵn trong máy ⇒ về 0; lời báo *"Đã dừng: 5 chương liên tiếp tải lỗi (ch.12–16). Kiểm tra nguồn rồi bấm Thử lại — chương đã tải không phải tải lại."* (video: "tập").
- **Truyện chữ / xuất ebook** (`DownloadManager+ChapterLanes.runChapterLanes`): đếm ở vòng giao kết quả đã xếp đúng thứ tự mục lục ⇒ "liên tiếp" đúng cả khi chạy 2–3 luồng; `.skippedUncached` ("Chỉ xuất chương đã tải") không tính. Chạm ngưỡng ⇒ `checkCancellation` (đang huỷ thì vẫn báo "Đã hủy") rồi ném `LimitReached` ⇒ nhánh `catch` sẵn có của `executeTask` bỏ file xuất dở + `markFailed`. Trước đây chương lỗi bị bỏ qua tới hết phạm vi.
- **Truyện tranh** (`DownloadManager+Comic`): đếm trong vòng từng chương; chạm ngưỡng ⇒ nhả `ComicImageScriptRunner` + `markFailed`.
- **Video** (`DownloadManager+Video`): đếm theo tập; chạm ngưỡng ⇒ các tập còn chờ thành "Đã huỷ" + `markFailed`, cùng kiểu dừng khi bộ nhớ dưới 1 GB.
- **Thông báo**: dùng `markFailed` sẵn có — toast lỗi, dòng "Thất bại" kèm lý do ở tab Tải và hộp thư Thông báo, nút Thử lại (tải tiếp, chương đã tải bỏ qua nhanh).
- Chuyển entry `[1.3.604]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. CI là cổng biên dịch; chưa thử trên máy.

## [1.3.633] - 2026-10-28

### fix: ngăn kéo menu thành kính đục vừa

Người dùng: *"làm cho menu có một độ đục nhất định. Cho mockup trước"*; duyệt **kiểu 2 — kính đục vừa** (nhoè vừa + tối 55%).

- **`SideDrawerPartialBlurView`** (mới, `Views/Common/SideDrawerMenu/`): nhoè **một phần** — `UIVisualEffectView` với `UIViewPropertyAnimator` chuyển `effect` từ `nil` sang `UIBlurEffect(.systemUltraThinMaterialDark)` rồi dừng ở `intensity` (0,6). Material của SwiftUI chỉ có một mức nhoè, mạnh tới mức nền Kệ đen thành mảng xám đều (lý do 1.3.622–630 bị chê "chẳng trong suốt"). Animator dựng lại khi view vào cửa sổ và khi app trở lại foreground; luôn `stopAnimation(true)` trước khi thả (thả animator đang dừng là crash).
- **`SideDrawerMenuPanel.drawerBackground`**: nhoè 60% + lớp tối `Color(white: 0.16).opacity(0.55)` (thay lớp tối 80% không nhoè của 1.3.632); viền trái và lớp phủ 30% phần màn còn lại giữ nguyên.
- Chuyển entry `[1.3.603]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy — độ nhoè thật trên máy có thể khác mockup, chỉnh `intensity` nếu cần.

## [1.3.632] - 2026-10-28

### fix: bấm dừng lọc name ghi chương đã dừng vào tin AI, ngăn kéo menu tối 80%

Người dùng: *"tôi yêu cầu là bấm dừng thì hiển thị chương đã dừng trong tin nhắn trả lời của ai chứ không phải thông báo. làm lại cho đúng"* — chọn **tin AI riêng ngay sau** tin kết quả; tự dừng *"có, không bỏ toast"*. Thêm: *"độ trong suốt menu thành 80% cho tôi"* — chọn **lớp tối 80%**.

- **Bấm dừng lọc name nhiều chương** (`AIRuntimeCoordinator.stopActiveTask`): bỏ toast "Đã dừng lọc name · …" của 1.3.628; thay bằng **tin AI riêng** ngay sau tin kết quả: `Đã dừng lọc name ở ch.21–30: <tên> → <tên>.` (một chương `ở ch.21: <tên>.`; chưa gửi lượt nào `… khi đang chuẩn bị.`). Danh sách `Tên=Nghĩa` của tin kết quả giữ sạch để sao chép/duyệt. `stopActiveTask` trả về tin đó (`@discardableResult`) để màn AI (`cancelBatchExtraction`, `stopStreaming`) thêm đúng tin ấy vào phiên đang hiện trong `@State`; chat thường không có tiến độ ⇒ không thêm gì.
- **Tự dừng** (lần quét chính và lần thử lại): tin lỗi trong màn AI có thêm dòng đầu `Lọc name tự dừng ở ch.…` trước `Lỗi quét tên riêng: …`; toast "Lọc name tự dừng · ch.…" giữ nguyên.
- Helper mới `nameScanStopNote(_:bookId:)` (`+BatchExtraction`), đọc tiến độ trước khi entry bị dọn.
- **Ngăn kéo menu** (`SideDrawerMenuPanel.drawerBackground`): lớp tối không làm mờ 62% → **80%**.
- Chuyển entry `[1.3.602]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.631] - 2026-10-28

### fix: ngăn kéo menu bỏ lớp kính mờ, nhìn xuyên được nền phía sau

Người dùng (kèm ảnh chụp ngăn kéo Kệ trên máy): *"sao ngăn kéo chẳng trong suốt tí nào"*.

- **Nguyên nhân** (`SideDrawerMenuPanel.drawerBackground`): lớp `.ultraThinMaterial` làm nhoè nền phía sau rất mạnh; nền Kệ gần như toàn đen với chữ nhỏ nên bị nhoè thành một mảng xám đều — nhìn như nền đặc dù lớp tối phía trên đã hạ còn 38% (1.3.626). Mockup đã duyệt vốn không làm mờ.
- **Sửa**: bỏ material, nền ngăn kéo chỉ còn một lớp tối bán trong suốt `Color(white: 0.08).opacity(0.62)` — bìa và chữ của màn bên dưới vẫn nhìn thấy (tối đi), chữ menu trắng vẫn đọc được. Viền trái và lớp phủ 30% phần màn còn lại giữ nguyên.
- Chuyển entry `[1.3.601]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.
