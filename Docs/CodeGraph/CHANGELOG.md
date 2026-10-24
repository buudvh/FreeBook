# CHANGELOG - Nhật ký Thay đổi CodeGraph FreeBook

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **FreeBook**.

## [1.3.588] - 2026-10-24

### feat: trình duyệt ẩn nguồn NSFW ở Home và tự ẩn danh với nguồn không lưu lịch sử

Người dùng: *"khi tắt nsfw thì đừng hiển thị các nguồn đó ở home của trình duyệt, tự động duyệt ẩn danh nếu config lựa chọn không lưu lịch sử"*; duyệt plan (ẩn danh theo tab, ẩn cả lịch sử duyệt cũ, thêm giải thích ở Cài đặt).

- **`BrowserSourceSiteIndex`** (mới, `Services/Browser`): dò trang thuộc nguồn **đã cài** nào theo tên miền — host của trang trùng tên miền `sourceUrl` hoặc là tên miền con của nó, so **một chiều** (nguồn ở `xyz.blogspot.com` không kéo `blogspot.com`), bỏ `www.` hai phía. Gồm cả nguồn Legado; tra một host thì lọc thô bằng chuỗi con tên miền gốc trước khi phân tích URL, tra cả danh sách thì dựng chỉ mục một lần.
- **Ẩn danh theo tab** (`BypassBrowserTab.isIncognito`): áp cho nguồn đang tắt "Lưu lịch sử đọc/xem" (`ExtensionHistoryPolicy`, mặc định = nguồn NSFW), **không** phụ thuộc công tắc NSFW. `BypassBrowserTabStore` bật cờ ở mọi điều hướng khung chính (kể cả chuyển hướng sang mirror) và xét lại ở `didFinish` (trang khôi phục từ bộ đệm lùi/tiến); tab ẩn danh không ghi `BrowserHistoryStore`. Tab mở từ tab ẩn danh (`createWebViewWith`, mở cửa sổ đã chặn) thừa hưởng; về Home (`loadHome`, tab mới) thì hết. Ô URL hiện icon `eye.slash`. Ẩn danh **chỉ** bỏ ghi lịch sử: cookie vẫn ở kho WebKit mặc định — dùng chung với trình duyệt ẩn của tiện ích — để vượt Cloudflare/đăng nhập ở đây vẫn có tác dụng cho nguồn. Log không ghi host.
- **Home trình duyệt khi tắt NSFW**: Truy cập nhanh bỏ tiện ích NSFW (`RepositoryFilterPolicy.applyNsfwFilter`); Lịch sử truy cập ở Home và màn "Xem thêm" (`BrowserHistorySheetView`) ẩn mục thuộc trang của nguồn NSFW (chỉ ẩn, không xoá; "Xóa toàn bộ" vẫn xoá cả mục bị ẩn). Nút Import truyện không đổi.
- **Giải thích**: Cài đặt › Nội dung nhạy cảm thêm dòng cho danh sách chọn truyện chia sẻ/nhập từ điển riêng (1.3.587), Home trình duyệt và ẩn danh; dòng Kệ đổi thành "vẫn hiện ở Kệ và Tìm trong Kệ". Chú thích công tắc "Lưu lịch sử đọc/xem" (`ExtensionConfigView+History`) nhắc trình duyệt tự ẩn danh.
- Chuyển entry `[1.3.558]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.587] - 2026-10-24

### fix: danh sách chọn truyện chia sẻ/nhập từ điển riêng theo công tắc NSFW

Người dùng: danh sách truyện để chia sẻ VP và nhập VP *"chưa theo config nsfw"*.

- **Nguyên nhân**: `BookShareTargetSheet` / `BookImportSourceSheet` (3 lối vào: chia sẻ + nhập từ điển riêng ở `DictionaryListView`, chia sẻ rule dịch nhanh ở `QuickTranslationRuleListView`) nạp mọi `Book` rồi chỉ bỏ truyện đang mở, không xét công tắc NSFW toàn app.
- **Sửa**: `loadBooks()` của hai sheet đọc `RepositoryFilterPolicy.includesNsfwPreference` một lần; tắt ⇒ bỏ **mọi** truyện có `RepositoryFilterPolicy.isNsfwSource` (cả nguồn Legado), **kể cả truyện trên kệ** — người dùng chọn chặt hơn Kệ/Lịch sử (vốn giữ sách trên kệ). Truyện không ở kệ cũng không ở lịch sử vẫn hiện như cũ. Sheet modal nạp một lần nên không theo dõi công tắc khi đang mở.
- Màn Cài đặt › Nội dung nhạy cảm chưa nhắc hai sheet này (dòng "Sách đã thêm lên Kệ vẫn hiện bình thường" chỉ đúng cho Kệ).
- Chuyển entry `[1.3.557]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.586] - 2026-10-22

### merge: đưa nguồn Legado (đợt 1–3) vào main

Gộp nhánh `claude/legado-source-bb5e46` (nguồn truyện Legado viết mới theo đặc tả — engine rule/mạng/JS, tab Nguồn Legado, tranh/video, đăng nhập, quản lý, bộ chạy nghiệm thu) vào `main`.

- **Đánh lại số phiên bản**: `main` đã dùng 1.3.557–1.3.561 cho năm commit của các phiên khác, nên các mục của nhánh **1.3.557–1.3.580 nay là 1.3.562–1.3.585** (cộng 5; đổi cả chỗ nhắc trong `rules.md`, `check_architecture.py`, comment `AppFilledButtonStyle`). Số cũ còn gặp trong ghi chú/hội thoại trước ngày 2026-10-22 thì cộng 5.
- **Xung đột**: chỉ ở `CHANGELOG.md` / `CHANGELOG.archive.md` — giữ mục của cả hai phía (Legado ở trên), phần đã chuyển sang lưu trữ theo nhánh; đối chiếu đủ mọi phiên bản của hai phía, không mất mục nào (ba số trùng 1.3.172/173/180 có sẵn từ trước). Đẩy 1.3.551–1.3.556 sang lưu trữ để file chính còn ~30 mục.
- **File Swift tự gộp** (`SearchView`, `DiscoveryView`, `ExtensionSelectorView`, `BookDetailView`, `SearchExtensionScopePolicy`): đã đọc lại hai phía — `kindScopePackageId` của `main` và bộ lọc/lịch tìm nguồn Legado của nhánh cùng tồn tại; `main` không thêm lời gọi `ExtensionManager.shared.<x>` trực tiếp nào bỏ qua `SourceRuntime`.
- **Kiểm chứng**: xem commit merge. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.585] - 2026-10-22

### fix: ô Khám phá của nguồn Legado hiện đủ chữ: 3 dòng, tự co chữ, cao bằng hàng

Người dùng: tag ở Khám phá của nguồn Legado *"nhỏ quá"*, chữ bị cắt — nhiều nguồn khai 4 ô/hàng (`style.layout_flexBasisPercent: 0.25`) cho nhãn tiếng Trung 2–3 chữ, bật dịch thì nhãn tiếng Việt dài gấp đôi. Người dùng chọn **giữ số ô/hàng nguồn khai**, chỉ tinh chỉnh để chữ hiện đủ.

- **`LegadoExploreTabView`** (ô bấm, kể cả tag tìm nhanh): `lineLimit` 2 → **3**; `minimumScaleFactor(0.75)` + `allowsTightening` ⇒ chữ co (15pt → ~11pt) trước khi phải cắt "…"; đệm ngang 6 → 4, thêm đệm dọc 4; khung `maxHeight: .infinity` ⇒ các ô cùng hàng cao bằng ô cao nhất (`LegadoFlexLayout` đã tính chiều cao hàng theo ô cao nhất, không sửa).
- Tiêu đề nhóm, ô chọn / ô nhập / nút của nguồn giữ nguyên. Đánh đổi: ô có nhãn quá dài có chữ nhỏ hơn ô bên cạnh.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.584] - 2026-10-22

### fix: nguồn Legado dùng bộ giới hạn nhịp kiểu Java (69書吧) dựng được URL tìm kiếm

Từ báo cáo `kiem-tra-nguon-legado-20261022-160304.json`: 69書吧 báo *"Nguồn không có URL gốc để ghép"* dù `searchUrl` là `@js:` dựng URL tuyệt đối.

- **Nguyên nhân**: hàm `buildRequest` trong `jsLib` của nguồn kiểm chữ ký `bookSourceComment`, giới hạn nhịp bằng `java.lang.System.getProperties().computeIfAbsent(…, k => new AtomicLong(0))` + `System.nanoTime()` + `compareAndSet` + `LockSupport.parkNanos`, rồi ký request. Giả lập `java.lang.System` của app chỉ có `currentTimeMillis` ⇒ JS ném `TypeError`, URL thành rỗng, `LegadoURLBuilder` báo nhầm thành `missingBaseURL`. Không phải thiếu cấu hình đăng nhập (`loginUi` chỉ có 2 nút).
- **Script `concurrent`** (`LegadoJSBootstrap+Concurrent`, nạp sau `classes`): `java.util.concurrent.atomic.AtomicLong` / `AtomicInteger` (get/set/compareAndSet/getAndSet/addAndGet/increment…), `System.getProperties()` (bảng `get`/`put`/`putIfAbsent`/`computeIfAbsent`/`getProperty`/`setProperty`…), `System.nanoTime()`, `getProperty`/`setProperty`/`clearProperty`/`lineSeparator`, `LockSupport.parkNanos`/`parkUntil` (qua lệnh `sleep` sẵn có: ≤ 5 giây, huỷ được).
- **Ô dùng chung toàn tiến trình** (`LegadoJavaSharedCells` + lệnh native `javaCell`/`nanoTime` ở `LegadoJSRuntime+Concurrent`): mỗi tác vụ một `JSContext`, nên `AtomicLong` đặt vào bảng thuộc tính được gắn với ô native theo khoá — nhờ vậy bộ giới hạn nhịp của nguồn có tác dụng giữa các chương. Chỉ giữ số, tối đa 512 ô, không ghi đĩa. Nguồn này tự giãn: tìm ~5 s/lần, nội dung ~2 s/lần — là ý của nguồn.
- **`java.lang.System`**: thành viên chưa có ⇒ lỗi "chưa hỗ trợ" thay vì `TypeError … is not a function`, để Kiểm tra nguồn quy về giới hạn của app.
- **`LegadoURLBuilder`**: URL không thành tuyệt đối mà JS dựng URL vừa lỗi ⇒ báo đúng lỗi đó (`unsupportedSyntax` trước, rồi `javaScript`); URL rỗng ⇒ `invalidURL`; `missingBaseURL` chỉ còn cho URL tương đối khi nguồn không có URL gốc.
- **Kiểm chứng**: chạy `jsLib` thật của nguồn cùng các script bootstrap trích từ Swift trong Node `vm` ⇒ ra đúng URL tìm kiếm kèm header ký. `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy (tìm → chi tiết → mục lục → nội dung).

## [1.3.583] - 2026-10-22

### fix: trình duyệt ẩn của nguồn Legado chờ trang thử thách JS tự tải lại rồi mới lấy HTML

Từ báo cáo `kiem-tra-nguon-legado-20261022-160304.json`: 起点小说 và 🎉起点中文网 (tìm kiếm `webView:true`) luôn nhận trang ~1 KB và bị kết luận nhầm "nguồn lỗi thời".

- **Nguyên nhân**: lần tải đầu, qidian trả HTTP 202, 209 byte — thân rỗng + `probe.js`; trong trình duyệt, script này đặt cookie rồi tự tải lại đúng URL (trang thật ~60 KB, 11 mục `.res-book-item`). `WebViewLoader` báo xong ngay lần tải đầu nên `LegadoWebViewFetcher` lấy HTML trang thử thách rồi dọn WebView — JS không kịp đặt cookie, lần nào cũng gặp lại trang thử thách.
- **Chờ trang lắng** (`LegadoWebViewFetcher+Settle`, file mới): sau lần tải đầu, mỗi 0,25 s kiểm `webView.isLoading`; trang phải yên liên tục 0,5 s mới xét. Một đoạn JS đếm chữ / ảnh / script / meta refresh: dưới 64 ký tự chữ, dưới 3 ảnh, có script hoặc meta refresh ⇒ coi là trang chờ, chờ tiếp tối đa 8 s kể từ lần tải xong gần nhất. Trần cứng vẫn là timeout của request (không kéo dài tổng thời gian chờ); huỷ thì dừng ở lượt kiểm kế tiếp. Trang thường chỉ chậm thêm ~0,5 s.
- **Sửa kèm**: `webViewDelayTime` giờ tính **sau** khi trang lắng, và HTML được đọc lại sau khoảng chờ đó (trước đây dùng bản chụp cũ, sai spec §4.4). `java.webView(html, …)` (nạp chuỗi HTML) không qua bước chờ lắng; đường `sourceRegex` không đổi.
- **Kiểm chứng**: cơ chế tải lại và ngưỡng phân loại đã quan sát trên trình duyệt Chromium, **chưa** trên WKWebView của iPhone. `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy (thử sau khi xoá cookie, vì kho cookie WebKit giữ lại giữa các lần).

## [1.3.582] - 2026-10-22

### fix: kiểm tra nguồn Legado không kết luận nhầm "lỗi thời" với trang báo lỗi ngắn, từ khoá mặc định dài hơn

Từ báo cáo `kiem-tra-nguon-legado-20261022-160304.json`: 抖音小说 bị kết luận **"Nguồn lỗi thời"**, nhưng web thực ra trả trang 444 byte chỉ có `alert("关键字最少 10 个字符")` — chê từ khoá mặc định `我的` quá ngắn. 起点 cũng bị kết luận lỗi thời với trang tìm kiếm ~1 KB (trang thử thách JS, sửa riêng).

- **Bộ phân xử** (`LegadoFailureArbiter`): trang 2xx dưới **3 KB** (`minimumOutdatedPageBytes`) hoặc trang có `alert(...)` **không** còn đủ để kết luận "nguồn lỗi thời" — rơi về "Chưa rõ" kèm lý do cụ thể:
  - có `alert(...)` ⇒ *"Web báo: «…»"*, ở bước tìm kiếm thêm gợi ý thử từ khoá khác;
  - trang quá ngắn ⇒ *"Trang trả về rất ngắn (HTTP …, N KB) — thường là trang báo lỗi, chặn, hoặc trang thử thách JS chưa chạy xong"*.
- **Dò bộ chọn** (`LegadoSelectorProbe`): thêm `alertMessage` — câu trong `alert("…")` đầu tiên của trang ≤ 4 KB (gọn khoảng trắng, tối đa 200 ký tự).
- **Từ khoá mặc định** khi nguồn không khai `checkKeyWord`: `我的` → `斗罗大陆` (Kiểm tra nguồn `LegadoCorpusRequest` và Gỡ lỗi nguồn `LegadoDebugInput`) — đủ dài để web có giới hạn độ dài từ khoá không chặn, và là tên truyện phổ biến nên dễ có kết quả.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.581] - 2026-10-22

### fix: chia sẻ báo cáo và xuất nguồn Legado báo nhầm "truy cập file ngoài thư mục" từ lần thứ hai

Người dùng: *"có thông báo truy cập file ngoài thư mục chia sẻ báo cáo bị từ chối"*.

- **Nguyên nhân**: thư mục tạm của iOS nằm dưới `/private/var/…`, và `URL.standardizedFileURL` chỉ bỏ tiền tố `/private` khi đường dẫn **đã tồn tại**. Lần đầu thư mục chia sẻ chưa có ⇒ hai bên cùng `/private/var/…`, khớp. Từ lần thứ hai thư mục đã có (rút thành `/var/…`) còn tệp mới chưa có (giữ `/private/var/…`) ⇒ `validatePathSafety` tưởng tệp nằm ngoài thư mục và từ chối.
- **Sửa**: `LegadoCorpusReportShare` (chia sẻ báo cáo Kiểm tra nguồn) và `LegadoSourceExporter` (xuất / chia sẻ nguồn — cùng ghi vào thư mục tạm, cùng lỗi) so sánh thành phần đường dẫn sau khi **tự bỏ `/private`** (`comparableComponents`), không phụ thuộc tệp đã tồn tại hay chưa. Các kho khác của nguồn Legado ghi vào Application Support (`/var/…`, không có `/private`) nên không bị.
- Chuyển entry `[1.3.546]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.580] - 2026-10-22

### fix: nút chia sẻ chỉ chạy được lần đầu: bảng chia sẻ đóng xong không báo SwiftUI

Người dùng: *"tôi bấm chia sẻ kiểm tra nguồn nhưng không thấy hoạt động, trước đây có thành công 1 lần"*.

- **Nguyên nhân**: `UIActivityViewController` tự đóng khi chia sẻ xong (hoặc huỷ) mà SwiftUI không biết ⇒ cờ `isPresented` / `item` của `.sheet` kẹt ở "đang mở"; lần bấm sau gán URL mới khi cờ vẫn `true` nên không có gì hiện ra.
- **`ShareSheet`** (dùng chung cả app — sao lưu, từ điển, rule dịch, lọc rác, công cụ tìm kiếm, xuất nguồn Legado…): trong `completionWithItemsHandler` gọi `dismiss` của chính sheet (`context.environment.dismiss`, trên MainActor) sau `onComplete` ⇒ SwiftUI hạ trạng thái, lần sau trình bày lại được.
- **Màn Kiểm tra nguồn**: `onComplete` hạ `shareURL`; nếu cờ vẫn kẹt khi bấm lại thì hạ trước, chờ ~0,4 s cho sheet cũ gỡ xong rồi mới trình bày.
- Chuyển entry `[1.3.545]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.579] - 2026-10-22

### feat: tự kết luận lỗi nguồn Legado do web, do nguồn hay do app, chia sẻ báo cáo kiểm tra

Người dùng: *"nhiều nguồn lỗi nhưng không biết lỗi do nguồn hay do app"*; xem mockup rồi bảo *"tiếp tục"*.

- **Bộ phân xử** (`LegadoFailureArbiter` + `+Evidence`, `LegadoFailureVerdict`, hàm thuần, `Services/LegadoSource/Diagnostics/`) — dừng ở luật đầu khớp:
  1. **Cần xác minh / đăng nhập**: trang thử thách/captcha (dấu `challenge-platform` chỉ tính khi mã ≥ 400 vì Cloudflare chèn cả vào trang thường; chữ yếu như "captcha" chỉ tính trong `<title>`, trang < 6 KB hoặc mã ≥ 400), nguồn có `loginUrl` bị 401/403, hoặc engine báo cần trình duyệt/mã xác minh khi chạy không tương tác.
  2. **Web chặn / sập**: trang chặn theo vùng / từ chối truy cập (`LegadoPageMarker`), lỗi mạng, engine quá thời gian, HTTP 403 / 404 ở bước đầu / 410 / 429 / 451 / 5xx.
  3. **Nghi do app**: cú pháp/hàm chưa hỗ trợ (trừ lớp dò app `io.legado.*`/`io.legato.*`), lỗi JS chỉ vào phần app giả lập, hoặc **đầu dò bộ chọn** thấy trang 2xx có đủ class/id của rule mà rule khớp 0 (thêm điều kiện: rule không có JS sau bộ chọn, khớp 0 chứ không phải lọc hết, thẻ cuối có thật trong phần tử chứa — trang tìm không có kết quả không bị kết luận oan; bước nội dung cần ≥ 50 ký tự chữ).
  4. **Nguồn lỗi thời**: trang 2xx mà không token class/id nào của rule có trong trang, hoặc nguồn thiếu rule.
  5. **Chưa rõ**: còn lại, kèm lý do (404 ở bước sau, máy mất mạng, lỗi JS của chính script nguồn…).
- **Đầu dò bộ chọn** (`LegadoSelectorProbe`, `LegadoRuleSelectorTokens`): khi bước danh sách/nội dung ra rỗng sau trang 2xx, tách token `class.X`/`.X`/`id.X`/`#X`/`tag.X` của rule và kiểm trong **toàn bộ** HTML trang, ghi vào run log.
- **Bằng chứng cho bộ chạy hàng loạt**: `LegadoRunLog.current` (task-local) — `runSession` dùng `log ?? LegadoRunLog.current` (đọc trước khi sang thread engine); bộ chạy bọc **từng bước** của mỗi nguồn. Không đổi chữ ký facade.
- **Báo cáo**: `SourceResult.verdict` + `verdictReason` (tuỳ chọn), báo cáo tổng thêm `byVerdict`; mirror `protocol.ts` (trường tuỳ chọn, không nâng version; `tsc --noEmit` sạch).
- **UI** (khớp mockup): màn Kiểm tra nguồn có ô đếm "Lỗi do ai" (`LegadoSourceCheckVerdictPanel`, chỉ ô > 0), chip lọc theo kết luận (`LegadoSourceCheckFilter`), dòng lỗi "Kết luận · bước · lý do" theo màu kết luận (`LegadoFailureVerdictStyle`), nút **chia sẻ báo cáo** ở toolbar (`LegadoCorpusReportShare` ghi JSON đã redact ra file tạm, `ShareSheet`); màn Gỡ lỗi từng bước có dải "Kết luận: …" (`LegadoFailureVerdictBanner`, nền nhạt — không nền màu nhấn đặc) dùng chung bộ phân xử.
- Chuyển entry `[1.3.544]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới** (kể cả `WHITE_TINT_FILL`); không đụng engine `{JS,Engine,Net,Rule}`. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.578] - 2026-10-22

### fix: chặn tận gốc lỗi nút trắng trên trắng: kiểu nút appFilled và luật WHITE_TINT_FILL

Người dùng: *"Trắng trên trắng tìm cách fix luôn lỗi này đi, tôi thấy thêm nút mới hay bị lắm"*.

- **Nguyên nhân gốc**: `MainTabView` đặt `.tint(.white)` toàn cục ⇒ `Color.accentColor` là **trắng**, `.borderedProminent` không kèm `.tint(…)` là nền trắng; nút mới tô nền bằng màu nhấn rồi đặt chữ trắng là vô hình. Đã gặp ở 1.3.447 (thư viện giọng VieNeu) và 1.3.572 (các màn nguồn Legado, sửa ở 1.3.575). Rà toàn app: hiện không còn chỗ nào dính — mọi `.borderedProminent` đều kèm tint màu.
- **`AppFilledButtonStyle`** (mới, `Views/Common/`): kiểu nút nền đặc chuẩn, chữ trắng trên màu cố định (mặc định xanh), mờ khi nhấn/tắt; `.buttonStyle(.appFilled)`, `.appFilled(.green, fullWidth: false)`. Nút "Mở trang đăng nhập" (`LegadoLoginView`) dùng kiểu này.
- **Luật mới `WHITE_TINT_FILL`** trong `Scripts/check_architecture.py` (quét `Sources/Views/**`, bỏ dòng comment): báo lỗi `.borderedProminent` mà chuỗi modifier của chính nút không có `.tint(<màu khác trắng>)`, và `.background(…Color.accentColor…)` đặc (mờ < 50% thì được; `.background(.tint)` cũng bị bắt). `.fill(Color.accentColor)` cho hình vẽ (thanh tua video) không bị cấm. Thử trên mẫu: bắt đúng 5/5 mẫu sai, không báo nhầm 3 mẫu đúng; trên code thật 0 vi phạm mới.
- **Tài liệu**: `CLAUDE.md` + `AGENTS.md` (bảng luật 5 → 6, ghi chú "màu nhấn của app là trắng"), `rules.md` §5.4 thêm quy tắc kèm ví dụ đúng/sai.
- Chuyển entry `[1.3.543]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.577] - 2026-10-22

### feat: danh mục tìm nhanh ở Khám phá cho nguồn Legado không có Khám phá

Người dùng: *"các nguồn không khai báo exploreUrl/ruleExplore của legado hãy thêm danh sách các từ tìm kiếm nhanh để người dùng có thể dùng để tìm kiếm nhanh. Tham khảo danh sách của …/wcshuba/src/genre.js"* (kèm báo 69書吧 không có ở Khám phá — nguồn này không khai `exploreUrl`).

- **`LegadoQuickSearch`** (mới, `Services/LegadoSource/Search/`): 70 từ khoá tiếng Trung lấy theo danh mục tìm của tiện ích `wcshuba` (诸天, 聊天群, 万界, 斗罗, 遮天, 凡人, 火影, 柯南…), bỏ các mục phân loại riêng của trang đó; mục "木叶" tìm đúng "木叶" (bản tham khảo trỏ nhầm sang "火影"). Áp cho nguồn **có rule tìm kiếm** mà **không có Khám phá dùng được** (thiếu `exploreUrl`/rule khám phá, hoặc `enabledExplore = false`).
- **Khám phá**: `SearchExtensionScopePolicy.isDiscoverable` nhận thêm nguồn Legado `LegadoSourcePolicy.isQuickSearchable` ⇒ hiện ở bảng chọn nguồn. Tab lưới của nguồn (`LegadoExploreTabView`) hiện các ô từ khoá (4 ô một hàng; tên ô dịch QT khi bật dịch như tên thể loại) — `LegadoSourceRuntime.exploreEntries`/`exploreCategories` trả mục tìm nhanh, không chạy engine.
- **Bấm ô** ⇒ đi đường của mục khám phá (`legadoExploreScriptName`, URL mang tiền tố `legado-quick-search:`); `SourceRuntime.executeCustomScript` nhận ra và chạy **tìm kiếm** của nguồn với từ khoá đó; có trang sau khi trang có kết quả và `searchUrl` có dùng `page` (`PaginatedNovelLoader` vẫn dừng khi trang không thêm mục mới).
- Nguồn có Khám phá riêng giữ nguyên danh mục của nguồn; tiện ích JS không đổi.
- Chuyển entry `[1.3.542]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.576] - 2026-10-22

### feat: nút chi tiết nguồn Legado trong bảng Phần mở rộng của Khám phá

Người dùng: *"thêm nút chi tiết nguồn các ext ở phần mở rộng của khám phá"*.

- Bảng chọn nguồn "Phần mở rộng" của Khám phá (`ExtensionSelectorView`): dòng nguồn Legado có nút ⓘ (`info.circle`, cùng kiểu và vị trí với nút ⚙ của tiện ích JS) mở `LegadoSourceDetailView` dạng sheet — từ đó sửa JSON, gỡ lỗi từng bước, kiểm tra, đăng nhập, chia sẻ ngay khi đang duyệt. Tiện ích JS giữ nút ⚙ mở màn Cấu hình như cũ; nguồn Legado vẫn không có lối vào màn cấu hình/sửa script của tiện ích JS.
- Chuyển entry `[1.3.541]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới** (`ExtensionSelectorView.swift` 200 → 217). Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.575] - 2026-10-22

### fix: nguồn Legado: tên gốc ở Kho, nút và chip không còn trắng trên trắng, không nối sang chương sau

Thử máy với bộ 1298 (log `app_logs (113)`, `(114)`). Người dùng: *"đừng dịch tên nguồn ở tab tiện ích"*, *"nút đăng nhập đang lỗi nền trắng chữ trắng"*.

- **Tên nguồn hiện bản gốc** ở tab Nguồn Legado, màn chi tiết, kiểm tra, gỡ lỗi, đăng nhập (`LegadoSourceSummary.displayName = name`; đảo quyết định 11 của plan đợt 1 theo yêu cầu người dùng). Tên dịch QT vẫn giữ để ô tìm khớp; **nhóm vẫn hiển thị bản dịch**.
- **Trắng trên trắng**: app đặt `.tint(.white)` toàn cục (`MainTabView`) nên `Color.accentColor` là trắng. Nút "Đăng nhập" / "Mở trang đăng nhập" (`LegadoLoginView`) và "Chạy" (`LegadoSourceDebugView`) đổi sang nền `Color.blue`; chip đang chọn ở tab Nguồn Legado, Kiểm tra nguồn và Gỡ lỗi (nền nhấn 85% + chữ trắng) theo kiểu chip của `ExtensionKindFilterBar` (chữ nhấn, nền nhấn 18%, viền 60%).
- **Không nối sang chương sau**: vòng `nextContentUrl` trước chỉ dừng ở **một** URL chương kế; tra không ra (mục lục chưa nạp trong phiên, URL lệch dạng…) là đi theo nút "下一章" kéo tới 30 chương vào một chương, request dồn dập và web chặn (thấy ở 错层小说: app nhận HTTP 400 cho đúng URL chương mà curl trả 200). Nay dừng khi gặp **bất kỳ** URL chương nào khác của mục lục (`LegadoEngineSession.tocStopKeys`; nguồn: mục lục đệm `LegadoTocURLCache.urls`, không có thì đọc `ChapterStore` một lần theo `bookId` rồi đệm).
- **Bỏ lỗi giả khi nguồn dò app**: script tạo thử lớp nội bộ `io.legado.*` / `io.legato.*` trong `try/catch` để biết đang chạy trên app nào (spec §6.10) — vẫn ném cho script đi nhánh khác, nhưng ghi thông tin thay vì "chưa hỗ trợ" `❌` (魔丸小说 ghi 4 dòng `❌` mỗi lần đọc).
- **`PaginatedNovelLoader`**: `CancellationError` (rời màn, đổi nguồn) không còn ghi `❌`, không hiện thông báo lỗi, không tự thử lại.
- **Khám phá chạy `exploreUrl` một lần**: danh mục và tab điều khiển cùng hỏi khi mở nguồn trước khi bản đệm có ⇒ lượt thứ hai dùng chung lượt đang bay (`ExploreEntriesCache.runningTask`); màn Gỡ lỗi vẫn chạy riêng.
- **Không phải lỗi app** (đã kiểm từ máy cùng vùng mạng): 篱笆好文学 (chặn theo vùng, 1Panel), 小原文学网, 可乐小说 (HTTP 403), 思路客 (captcha Cloudflare), 文桑小说 (quá thời gian), 鬼吹灯 (tên miền chết). 8/15 nguồn của bộ 1298 không khai `exploreUrl` nên không có ở Khám phá — đúng hành vi.
- Chuyển entry `[1.3.540]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử lại trên máy.

## [1.3.574] - 2026-10-21

### feat: nối nốt nguồn Legado: giải mã bìa, imageStyle, ghi đè loại sách, làm mới chương, alert trình duyệt, dọn trạng thái mồ côi

Người dùng: *"Làm nốt các mục chưa nối: coverDecodeJs, imageStyle, typeOverride cho BookContentDestination, refreshContent vào trình đọc, alert() trong trình duyệt nhỏ, dọn sidecar mồ côi lúc mở app."* Hành vi theo spec phần 2 §8.5, §8.7, §13.6.

- **`coverDecodeJs`** (`LegadoCoverDecoder`, mới): luồng tìm / khám phá / chi tiết ghi URL bìa của nguồn có `coverDecodeJs` vào sổ; `CoverImageLoader.data` (tìm kiếm, Khám phá) giải mã bytes → bytes **trước** bước kiểm ảnh rồi cache bản đã giải; `ImageCacheManager.downloadAndSaveCover(packageId:)` (mặc định `nil`) + `BookCoverView` truyền `extensionPackageId` nên bìa trên kệ giải được sau khi mở lại app. Tối đa 2 phiên engine cùng lúc; lỗi ⇒ dùng byte gốc, `❌` một lần mỗi nguồn. JS nhận `result` dạng luồng (`read()`/`available()`) — harness `runImageDecode` chỉ thêm, không đổi hành vi `imageDecode`. Tiện ích JS chỉ tốn một lần tra từ điển.
- **`imageStyle`**: `ComicPageSource.imageStyle` (tuỳ chọn, mặc định `nil`), ưu tiên `style` trong option của ảnh > `book.imageStyle` do JS `content` ghi trong cùng phiên > `ruleContent.imageStyle`; chuyền tới `ComicPageView`. Trình đọc tranh vốn vẽ ảnh tràn bề ngang, không khoảng cách (= `FULL`, giá trị phổ biến nhất) nên **hình không đổi**; giá trị khác giữ cách hiện tại.
- **Ghi đè loại theo sách** (`LegadoBookTypeOverride`, mới, bitmask §13.6: 64 ⇒ tranh, 8 ⇒ chữ; audio/tệp/`3` ⇒ theo loại của nguồn): `BookContentDestination.resolveKind` ưu tiên ghi đè của sách; guard `SourceRuntime.chap` nới cho sách tranh bị nguồn ghi đè thành chữ.
- **`refreshContent` → trình đọc** (`LegadoContentRefreshSignal` + modifier `legadoContentRefresh`, mới; gom lặp 3 s): presenter báo tín hiệu theo nguồn; Reader chữ tải lại chương đang mở bỏ qua cache (`reloadCurrentChapterFromMenu`; `ReaderView` 2045 → 2046, baseline 2053); trình đọc tranh `retry()`. Không dùng NotificationCenter.
- **`alert()` / `confirm()` / `prompt()`** trong trình duyệt nhỏ (`LegadoBrowserController` + `LegadoBrowserJSPanel`, mới; trình duyệt đăng nhập dùng chung): `UIAlertController`, completion gọi đúng một lần kể cả khi đóng trình duyệt giữa chừng.
- **Dọn trạng thái mồ côi** (`LegadoOrphanStateSweeper`, mới): một lần mỗi lần mở app từ `MainTabView` (225 → 227), `Task.detached` + `ModelContext` riêng; `LegadoBookStateStore.removeOrphanFiles` chỉ xoá tệp đúng mẫu `<64 hex>.json` ở gốc `legado_state/` không còn sách, sửa lần cuối trước lúc bắt đầu lượt, qua `validatePathSafety`; đọc lỗi / danh sách sách rỗng ⇒ bỏ lượt.
- **Còn hở**: tải truyện, `BookKindBadge` và nhãn "Tải truyện" vẫn theo loại của nguồn; bìa cho TTS không truyền `packageId`; `resolveKind` đọc tệp sidecar nhỏ trên main một lần mỗi sách; chương tranh đã tải offline thì làm mới vẫn mở bản offline; đổi nguồn giữa hai nguồn Legado có thể giữ ghi đè cũ; `book.imageStyle` chưa lưu bền.
- Chuyển entry `[1.3.539]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới** (`ComicReaderViewModel` không đổi). Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.573] - 2026-10-21

### docs: quy chuẩn nguồn Legado trong rules.md, client gỡ lỗi nhận chi tiết media

Rà soát cuối đợt 2 + 3 nguồn Legado.

- **`rules.md`** thêm mục "Nguồn Legado (1.3.562–1.3.572)": clean-room (hành vi chỉ lấy từ spec), mọi lời gọi runtime qua `SourceRuntime`, nhận diện theo `Extension.type` + `packageId` đóng băng, không qua `cleanAndResolveUrl`, engine chạy ngoài main và chờ UI qua event center, `isInteractive` chỉ cho thao tác một nguồn do người dùng bấm, đăng nhập chỉ ở Keychain (dự phòng tệp bảo vệ) và không sao lưu, cửa sổ trượt 8 nguồn khi tìm mọi nguồn, media không qua pipeline text.
- **Client VS Code** (`Tools/VSCode/FreeBookExtDebug/src/protocol.ts`): mirror trường tuỳ chọn `media` (`LegadoCorpusMediaCheck`) mà 1.3.570 thêm vào báo cáo nghiệm thu — trường thêm, tuỳ chọn, không đổi version giao thức. Kiểm kiểu `tsc --noEmit`: 0 lỗi.
- **Bộ quét gợi ý** (`LegadoCorpusFeatureScan`): bỏ `Jsoup.connect` khỏi danh sách "chưa hỗ trợ" — shim `Connection` đã cài ở 1.3.569 (bootstrap `connect` chạy sau `jsoup`, ghi đè stub mặc định).
- Entry 1.3.569 ghi rõ `java.open`, `openVideoPlayer`, `addBook` vẫn là stub (hoãn hẳn theo spec).
- Chuyển entry `[1.3.538]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch.

## [1.3.572] - 2026-10-21

### feat: đăng nhập nguồn Legado (form + web), trình duyệt cho JS, Khám phá động

Khối D-UI, E-UI của plan đợt 2 + 3 nguồn Legado — giao diện khớp mockup đã duyệt (người dùng chọn giữ cả đăng nhập bằng form lẫn trên web). Hành vi theo spec phần 2 §10, §11.

- **Đăng nhập** (`Views/Extensions/Legado/Login/`, mới): `LegadoLoginView` (+`Actions`, `LegadoLoginFieldView`) dựng form từ `loginUi` (ô chữ/mật khẩu…, nút hành động của nguồn chạy JS), Đăng nhập, "Đăng nhập trên web", Đăng xuất, dải trạng thái; `LegadoLoginWebView` — trình duyệt nhỏ (Huỷ / URL / ↻ / Xong ⇒ nhập cookie vào kho cookie của nguồn). Nút Đăng nhập ở màn chi tiết nguồn nối vào đây (ẩn khi `loginUrl` rỗng/chỉ là chú thích).
- **Keychain dự phòng**: `LegadoLoginFallbackStore` theo mẫu `TelegramTokenStore`, chỉ dùng khi Keychain lỗi (vd chạy dưới LiveContainer); tệp ở `.legado_login/` ngoài `legado_state/`, không log, không sao lưu. Xoá nguồn ⇒ xoá luôn thông tin đăng nhập của nguồn (`LegadoLoginService.forget`, khoá theo `bookSourceUrl`).
- **Trình duyệt / mã xác minh từ JS** (`Views/Extensions/Legado/Browser/`, mới): `LegadoPresentationPresenter` là subscriber duy nhất của event center engine, gắn một lần ở root (`.legadoPresentationHandler()` trong `FreeBookApp`); trình bày `LegadoBrowserSheet` (`java.startBrowser*`) hoặc `LegadoVerificationCodeSheet` (`getVerificationCode`), trả kết quả/huỷ cho thread engine đang chờ ngoài main. `searchBook` mở Tìm kiếm; `openUrl` hỏi nhập nguồn / mở trình duyệt nhỏ / hỏi trước khi mở app ngoài.
- **Cờ người dùng chủ động**: `SourceRuntimeContext.isInteractive` (mặc định `false`); facade Legado bọc `LegadoInteraction.$isInteractive` khi bật. Bật ở: trang chi tiết (chi tiết + mục lục), chương đang mở trong Reader (không phải prefetch; chương Legado đang mở chờ tối đa 620 s để kịp qua xác minh, tiện ích JS vẫn 30 s), kéo làm mới mục lục, Đổi nguồn, chương tranh đang mở, video đang xem, Khám phá, Gỡ lỗi từng bước. **Không** bật ở TTS, tải truyện, kiểm chương mới, tìm mọi nguồn, kiểm tra hàng loạt, bộ nghiệm thu. Engine nay cũng không phát `refreshExplore`/`searchBook`/`refreshContent`/`copyText` khi không có người dùng (kiểm tra hàng loạt không tự bật màn hình).
- **Khám phá động** (`Views/Discovery/Legado/`, mới: `LegadoExploreTabView`, `LegadoExploreControlView`, `LegadoExploreRefreshSignal`; `Views/Common/LegadoFlexLayout`): tab lưới thể loại của nguồn Legado có tiêu đề nhóm, ô bấm, điều khiển chọn / bật tắt / ô nhập + "Áp dụng", bố cục theo `style` của nguồn; `java.refreshExplore` tải lại danh mục. API: `SourceRuntime+ExploreControls`, `LegadoSourceRuntime+ExploreControls`. Danh sách mở ra vẫn là `CategoryNovelsListView`/`PaginatedNovelLoader`. `DiscoveryGenresTabView` chỉ thêm chỗ cắm; `DiscoveryView+Loading` chạy `exploreUrl` của nguồn Legado một lần rồi đệm.
- **Dọn ráp nối**: bộ quét gợi ý của bộ nghiệm thu (`LegadoCorpusFeatureScan`) chỉ còn gắn cờ những gì vẫn chưa hỗ trợ; hai comment lỗi thời ở `SearchExtensionScopePolicy`.
- **Chưa làm**: `refreshContent` chưa nối vào trình đọc (chỉ ghi log); trình duyệt nhỏ chưa xử lý `alert()` của trang.
- Chuyển entry `[1.3.537]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới** (`ChapterContentRepository` 430 → 430, `ReaderViewModel` 777 → 777, `DiscoveryView` 621 → 622, `SearchView` 794 → 794, `ComicReaderViewModel` 395 → 395). Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.571] - 2026-10-21

### feat: màn quản lý nguồn Legado: chi tiết, sửa JSON, gỡ lỗi, kiểm tra hàng loạt, xuất, liên kết legado://

Khối F, G, H của plan đợt 2 + 3 nguồn Legado. Giao diện khớp mockup người dùng đã duyệt 2026-10-21. Hành vi Legado theo spec phần 2 §12.

- **Chi tiết nguồn** (`Views/Extensions/Legado/LegadoSourceDetailView` + `…DetailHeaderCard`, mới): chạm dòng ở tab Nguồn Legado (toggle và 🗑 giữ nguyên) ⇒ thẻ đầu (tên QT, tên gốc · phiên bản, chip, URL, ghi chú "Xem thêm"), nút tròn Trình duyệt / Đăng nhập (khi có `loginUrl`) / Xoá; mục Hoạt động (Bật nguồn, **Biến của nguồn** — `…VariablesView`, gợi ý từ `variableComment`); mục Công cụ (Sửa JSON, Gỡ lỗi từng bước, Kiểm tra nguồn này, Chia sẻ nguồn).
- **Sửa JSON** (`…JSONEditorView`): dùng lại trình sửa code của tiện ích JS (Cú pháp / Định dạng / Tải lại, đếm dòng/ký tự, cỡ chữ); chỉ lưu khi JSON hợp lệ (`LegadoSourceJSONValidator`, báo dòng lỗi); đổi `bookSourceUrl` ⇒ hỏi lại. Lưu qua `LegadoSourceCoordinator+Editing` (ghi dạng chuẩn hoá + `lastUpdateTime`, tăng `version`; runtime tự bỏ bản đệm cũ theo `version`).
- **Gỡ lỗi từng bước** (`…DebugView`, `…DebugStepCard`; `Services/LegadoSource/Debug/` mới: `LegadoSourceDebugRunner`, `LegadoDebugInput`, `LegadoDebugStep`, `LegadoDebugReportFormatter`): chế độ từ khoá / URL chi tiết / `++` mục lục / `--` nội dung / `::` khám phá; thẻ từng bước có request, HTTP, bảng mã, số kết quả, trường mục đầu, thời gian, lớp lỗi, log JS / hàm chưa hỗ trợ, "Xem HTML trang (cắt 4 KB)". `LegadoRunLog` gom thêm ghi vết request của engine. Bản sao chép báo cáo che giá trị query; không gửi gì ra ngoài.
- **Kiểm tra hàng loạt** (`…CheckView`, `…CheckRow`): từ menu ⋯ (danh sách đang hiện) hoặc từ chi tiết; dùng `LegadoCorpusRunner` trong app; Đạt / Lỗi / Còn lại, chip lọc, nút bọ ⇒ Gỡ lỗi, **Tắt nguồn lỗi**, **Gắn nhóm "Lỗi"**, **Xoá nguồn lỗi** (hỏi xác nhận), Dừng. Nguồn đang tắt không kiểm (bộ chạy bỏ qua).
- **Xuất / chia sẻ** (`LegadoSourceExporter`): tệp `.json` là mảng `source.json` nguyên văn, qua `ShareSheet` có sẵn. Menu ⋯ thêm "Kiểm tra nguồn …" / "Xuất nguồn …"; "Bật/Tắt tất cả (theo danh sách đang hiện)" — đổi nhãn theo người dùng.
- **Liên kết `legado://`**: `CFBundleURLTypes` (scheme `legado`) trong `project.yml`; `LegadoLinkImportModifier` ở root (`FreeBookApp` 131 → 133) hỏi "Nhập nguồn từ liên kết?" rồi nhập như "Nhập từ URL" (chỉ http/https, tối đa 20 MB); dạng khác báo chưa hỗ trợ.
- **NSFW**: `ExtensionNsfwClassifier+Legado` nhận nguồn Legado theo nhóm/tên (cờ `nsfw` ghi vào `plugin.json`, bù cho nguồn đã nhập theo lô 200); tab Legado theo công tắc NSFW chung. Tìm kiếm/Khám phá bỏ heuristic theo ghi chú với nguồn Legado (41 nguồn bị gắn nhầm 18+ vì ghi chú có chữ `java.`).
- **Backup** (`BackupLegadoStateArchiver`, mới): đưa sidecar truyện + biến/giá trị/cache của trạng thái nguồn trong `legado_state/` vào backup; **không** sao lưu cookie, đăng nhập (Keychain), `device.json`, `jslib/`. Khôi phục sau bước cài lại tiện ích, gộp theo khoá, giữ bản của máy. `BackupLibraryFingerprint.formatVersion` 3 → 4.
- Chuyển entry `[1.3.536]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới**; `RepositoryManagerView.swift` không đổi. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.570] - 2026-10-21

### feat: truyện tranh và video từ nguồn Legado

Khối A, B, C (và phần cấp luồng của khối I) của plan đợt 2 + 3 nguồn Legado (người dùng đã duyệt). Hành vi theo spec phần 2 §8, §9, §13, §15.3.

- **Facade media** `SourceRuntime+Media` (mới): `comicPages`/`videoServers`/`videoTrack` cùng nhãn tham số với `ExtensionManager+Media`; tiện ích JS chuyển nguyên tham số, nguồn Legado chạy engine. Nối `ComicReaderViewModel` (+`+SourceContext`), `DownloadManager+Comic`, `VideoPlaybackSession+Loading`. Không còn lời gọi `ExtensionManager.shared.(comicPages|videoServers|videoTrack)(` ngoài facade. Media vẫn **không** đi qua pipeline text; `chap` gọi trên nguồn tranh/video ném lỗi rõ ràng.
- **Tranh** (`Runtime/LegadoSourceRuntime+Comic`, `LegadoComicImageExtractor`): nội dung chương ⇒ `[ComicPageSource]` (giữ `src` nguyên văn kể cả khối option; thiếu Referer thì chèn vào option), phân trang nội dung. `imageDecode`: `ComicPageSource.script` mang tên giả của Legado, `ComicImageScriptRunner` rẽ sang engine giải mã bytes → bytes (`+ImageDecode`; ảnh vẫn qua `concurrentRate`). Chương không có ảnh ⇒ lỗi kèm tối đa 600 ký tự chữ của trang.
- **Video** (`+Video`, `LegadoVideoServerPayload`): mỗi tập đúng một server (nguồn Legado không có khái niệm server); `data` là JSON chứa URL tập + ngữ cảnh; URL phát giải lại mỗi lần `videoTrack` (kể cả Thử lại / chọn lại) vì có chữ ký hết hạn; URL tập đã là tệp media thì không tải thân.
- **Mục lục tranh/video**: mục `isVolume` thành dòng tiêu đề nhóm (`isSection`); truyện chữ vẫn bỏ như cũ.
- **Phần đuôi cấp luồng** (`+TocTail`): `preUpdateJs`, `formatJs` (`index` đếm từ 1, trần 2 s), hiệu lực `book.setReverseToc`, `refreshTocUrl`/`reGetBook`, `sourceRegex` chuyển cho engine.
- **Mở loại**: `LegadoSourcePolicy` nhận chữ + tranh + video (chip "Chưa hỗ trợ" tự mất); Tìm kiếm / Khám phá / Đổi nguồn nhận nguồn tranh/video Legado theo loại.
- **Bộ chạy nghiệm thu**: nguồn tranh/video đo ở bước nội dung (`LegadoCorpusProbe+Media`, trường tuỳ chọn `SourceResult.media`); không đổi API public.
- **Chưa làm**: `coverDecodeJs` (2 nguồn), `imageStyle`, `ruleContent.title`, `canReName`; ghi đè loại theo từng sách (`typeOverride` đã lưu, `BookContentDestination` chưa đọc).
- Chuyển entry `[1.3.535]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới** (`ComicReaderViewModel.swift` 394 → 395). Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.569] - 2026-10-21

### feat: engine nguồn Legado đợt 2 + 3: đăng nhập, trình duyệt từ JS, khám phá có kiểu, font, tệp, RSA

Khối D-engine, E-engine, I, J của plan đợt 2 + 3 nguồn Legado (người dùng đã duyệt). Hành vi theo spec phần 2 §10, §11, §13, §14, §15.3. 43 file mới (~3.450 dòng) + 29 file engine sửa, mọi file ≤ 400 dòng.

- **Đăng nhập** (`Login/`): `source.getLoginInfo*/putLoginInfo/getLoginHeader*/putLoginHeader/removeLoginHeader/login` cài thật; `LegadoLoginStore` lưu thông tin + header đăng nhập trong **Keychain** theo nguồn (Keychain hỏng — vd dưới LiveContainer — thì chỉ giữ trong phiên); `LegadoLoginService` cho UI: trường form từ `loginUi`, gửi đăng nhập, nút hành động, đăng xuất (xoá Keychain + mọi cookie của nguồn), trạng thái, nhập cookie từ WebView. `loginCheckJs` chạy sau request luồng chính; header đăng nhập chỉ gắn khi tên miền trùng nguồn/trang đang đọc (U42).
- **Trình duyệt / mã xác minh từ JS** (`Presentation/`): `java.startBrowser`, `startBrowserAwait`, `startBrowserDp`, `getVerificationCode`… phát yêu cầu qua event center `AsyncStream` (Services, không UI) và chờ **ngoài main** có timeout + huỷ. Chỉ hiện khi lời gọi được bọc `LegadoInteraction.$isInteractive` (người dùng chủ động) và có presenter; mặc định coi là không có người dùng.
- **Khám phá có kiểu**: `LegadoEngineExploreItem` giữ `type` (url/text/button/toggle/select…), `action`, `chars`, `default`, `style`; giá trị chọn đi qua `infoMap` + JS của nguồn (§11.3, không tự chèn vào URL), lưu theo nguồn; `java.refreshExplore` phát sự kiện làm mới.
- **Phần đuôi đợt 2**: URL `data:`, `java.importScript`, `java.toURL`, `Jsoup.connect`, giả lập `javax.crypto` phần hay gặp, `book.*` ghi thuộc tính + cờ cho luồng (`reverseTocOverride`, `typeOverride`, `onRefreshTocUrl`, `onReGetBook`), `fetch(…, sourceRegex:)` + bắt ứng viên phát video qua WebView. Đính chính phần 1 (§15.3): `book.type` dạng bitmask 8/32/64/128; `contentString` giữ outer HTML cho trường nội dung; `src` của `<img>` có option JSON.
- **Đợt 3**: font chống crawl `queryTTF`/`queryBase64TTF`/`replaceFont` (`Font/`, parser TTF tự viết, lỗi ⇒ giữ văn bản gốc); tệp/zip (`Files/`, ZIPFoundation có sẵn, thư mục `legado_state/files/<nguồn>/`, 7z/rar ⇒ "Chưa hỗ trợ định dạng"); RSA `createAsymmetricCrypto`/`createSign` (`Crypto/`, Security framework); chế độ mã hoá đối xứng còn thiếu; phần đuôi `java.*`/`source.*`/`cookie.*`/`cache.*` theo §14. Cố ý không định nghĩa `java.readFile`, `showBrowser`, `showReadingBrowser`, `openWeb` (spec); `java.open`, `openVideoPlayer`, `addBook` vẫn là stub "Chưa hỗ trợ" (hoãn hẳn theo spec). Chưa có shim `android.graphics`, `Inflater`, `java.net.URL`.
- **Ghi vết request** cho màn Gỡ lỗi: `LegadoEngineRequestRecord` + `LegadoEngineDiagnostics.recordRequest/requests` (≤ 100/phiên, mọi request kể cả lỗi, WebView, `data:`), không ghi vào `AppLogger`.
- Chuyển entry `[1.3.534]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới**. 9 bootstrap JS chạy thử trên Node với lệnh native giả: 43/43 phép thử đạt. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.568] - 2026-10-21

### docs: đặc tả hành vi nguồn Legado phần 2 (tranh, video, đăng nhập, quản lý, phần hiếm)

Người dùng: *"làm ra thành phẩm luôn đừng có nghiệm thu"* — chọn làm luôn đợt 2 + 3 (không thử máy giữa chừng), giữ bộ chạy nghiệm thu, giao diện mới dựng mockup trước (đã duyệt cả 3 nhóm màn; giữ cả đăng nhập bằng form lẫn trên web; tab Legado theo công tắc NSFW chung; "Bật/Tắt tất cả" đổi nhãn). Plan đợt 2 + 3 đã duyệt (`Docs/Plans/2026-10-21-plan-nguon-legado-dot-2-3.md`, gitignore).

- **`Docs/Specs/legado-source-spec-part2.md`** (mới, ~1.320 dòng), đánh số nối tiếp phần 1: §8 tranh (nội dung ra ảnh, URL ảnh kèm option, `imageStyle`, `imageDecode`, `coverDecodeJs`) · §9 video (13 nguồn mẫu: 12 trong corpus + 1 từ bộ yckceo 1111 tải thêm; tuyến phát trải thẳng vào mục lục, không có khái niệm server) · §10 đăng nhập (`loginUrl`, `loginUi`, `loginCheckJs`, `source.*Login*`, `java.startBrowser*`/`getVerificationCode`) · §11 Khám phá động (mục text/button/toggle/select, `refreshExplore`, `infoMap`) · §12 quản lý (xuất, scheme nhập nhanh, chế độ gỡ lỗi, `variableComment`) · §13 phần đuôi đợt 2 (`data:`, `sourceRegex`, `preUpdateJs`, `formatJs`, `setReverseToc`, `importScript`, `toURL`, `Jsoup.connect`, `javax.crypto`) · §14 đợt 3 (font chống crawl, tệp/zip, RSA/ký số, mã hoá đối xứng còn thiếu, danh sách đủ phần đuôi `java.*`/`source.*`/`cookie.*`/`cache.*`) · §15 phụ lục (bảng đợt, U29–U63, **đính chính phần 1** 8 mục — vd `book.type` là bitmask 8/32/64/128, khác §6.6).
- Viết bởi agent riêng, cùng luật clean-room như phần 1: chỉ tài liệu trợ giúp được phép + quan sát corpus + 3 lần curl. Nhãn: `[tài liệu]` 60 / `[quan sát]` 128 / `[UNKNOWN]` 53.
- **Kiểm clean-room** (script ngoài repo): tên lớp lạ xuất hiện đều có trong `jsHelp.md` hoặc trong script của corpus; không câu văn xuôi nào trùng nguyên văn tài liệu; 0 chữ cấm.
- Không đổi code; commit chỉ tài liệu nên CI không chạy.
- Chuyển entry `[1.3.533]` sang `CHANGELOG.archive.md` để giữ 30 entry.

## [1.3.567] - 2026-10-21

### feat: bộ chạy nghiệm thu nguồn Legado qua Debug server

Bước 13 của đợt 1 plan "nguồn truyện Legado — viết mới theo đặc tả": đo tỉ lệ nguồn chạy trọn chuỗi để chốt cổng đợt 1 (bộ 1316 nguồn chữ ≥ 55%). Không có UI trong app.

- **`LegadoCorpusRunner`** (`Sources/Services/LegadoSource/Diagnostics/`, 11 file mới): với mỗi nguồn Legado **đã cài** được chọn — tìm (từ khoá `ruleSearch.checkKeyWord`, thiếu thì mặc định; nguồn không có rule tìm thì đi Khám phá qua `genre`) → kết quả đầu → chi tiết → mục lục → nội dung chương đầu, **qua facade `SourceRuntime`** (đúng đường app chạy thật). Song song tối đa 4; trần mỗi bước (tìm/khám phá/chi tiết 60 s, mục lục 300 s, nội dung 120 s); huỷ được. Trạng thái truyện dùng `bookId = "corpus-runner:<packageId>"` nên không đụng sách thật, không sinh sidecar.
- **Phân loại lỗi** (`LegadoCorpusErrorClassifier`): cú pháp chưa hỗ trợ / HTTP (kèm mã) / rule khớp 0 / quá thời gian / mạng / JS / nguồn hỏng / khác. Thông điệp đã redact (giá trị query thành `…`, khối option `,{…}` và URL JS bị che, cắt 300 ký tự), không chứa nội dung chương, header, cookie.
- **Báo cáo** JSON ở `applicationSupport/legado_reports/<thời điểm>.json` (`validatePathSafety`): tổng nguồn, số qua trọn chuỗi, %, đếm theo lớp lỗi và theo bước, chi tiết từng nguồn; một dòng tóm tắt qua `AppLogger` (không gắn `❌`).
- **Debug server — contract v2**: lệnh mới `legado.sources`, `legado.corpus.start` (đầu vào chỉ là danh sách `packageId` **hoặc** "tất cả nguồn Legado đang bật", từ khoá, giới hạn — không nhận URL/đường dẫn/JS), `legado.corpus.status`, `legado.corpus.cancel`; mã lỗi `BUSY`. `ExtensionDebugProtocol.version` 1 → 2 và `ExtensionDebugEvent.contractVersion` 1 → 2 (shape event không đổi); server vẫn nhận envelope v1 nên client cũ chạy như trước, chỉ lệnh `legado.*` đòi v2. Logic ở `ExtensionDebugCommandRouter+Legado.swift` (mới); router gốc chỉ thêm `case`. Không qua `ExtensionDebugInstallGate`: lệnh không ghi thư viện/sách/cài đặt.
- `extensions.list` không còn liệt kê nguồn Legado; `run.start` với nguồn Legado trả `UNKNOWN_ENTRYPOINT` kèm hướng dẫn (không cố chạy `search.js` không tồn tại).
- **Client VS Code** (`Tools/VSCode/FreeBookExtDebug`): mirror `protocol.ts`; 3 lệnh Command Palette chạy / xem tiến độ / huỷ nghiệm thu (`legadoCorpus.ts` mới, `client.ts`, `extension.ts`, `package.json`); client mới gặp app cũ tự hạ về v1. Mô tả gói bỏ tên nền tảng cũ.
- **Log facade**: thông điệp lỗi của nhánh Legado trong `SourceRuntime` được redact URL trước khi ghi file.
- Chuyển entry `[1.3.532]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới**. TypeScript kiểm kiểu với stub theo chữ ký thật (chưa `npm run compile` thật). Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa chạy trên máy.

## [1.3.566] - 2026-10-21

### feat: luồng nguồn Legado, facade SourceRuntime và nối vào Tìm kiếm, Khám phá, Reader, tải truyện

Bước 9, 10 và phần còn lại của bước 11 trong đợt 1 plan "nguồn truyện Legado — viết mới theo đặc tả". Luồng theo `Docs/Specs/legado-source-spec.md` §5.

- **Luồng** (`Sources/Services/LegadoSource/Runtime/`, mới): `LegadoSourceRuntime` + `Search` / `Explore` / `Detail` / `Toc` / `Content` trên engine 1.3.565, trả đúng DTO hiện có (`ExtensionItemResult`, `NovelDetailResult`, `ChapterResult`, `CategoryResult`, `String`). Vòng `nextTocUrl`/`nextContentUrl` dừng + chống lặp theo §5.6, có trần trang; nội dung nhiều trang dùng chung một runtime JS. Mục tên tập (`isVolume`) **không thành chương** (quyết định K), chương đánh số liên tục; chương tên rỗng thành "Chương N"; trang sau lỗi thì giữ phần đã tải. `kind` → thẻ thể loại không có script (chỉ là nhãn). Nguồn đang tắt vẫn đọc tiếp được sách đã có trên kệ.
- **Trạng thái theo truyện** (quyết định G): `LegadoBookStateStore` giữ `tocUrl` + biến truyện/chương **trong bộ nhớ** theo `packageId + bookUrl`; chỉ ghi sidecar `applicationSupport/legado_state/<sha256(bookId)>.json` khi sách đã thật sự tồn tại (đã có mục lục trong `ChapterStore`) — mở trang chi tiết (bookId UUID mới mỗi lần) hay đổi nguồn thất bại không sinh file. Lượt thông tin sách chạy song song với mục lục được gộp (`LegadoBookInfoCoalescer`). `deleteState(bookId:)` static, gọi khi xoá sách và khi đổi nguồn dọn sách cũ.
- **Facade** `SourceRuntime` (`Sources/Services/Extensions/`, mới): giữ **nguyên nhãn tham số** của `ExtensionManager.search/detail/page/toc/chap/genre/home/executeCustomScript` (+ `context: SourceRuntimeContext?` tuỳ chọn ở cuối — bookId, URL sách, tên, tác giả, tiêu đề/chỉ số chương). Tiện ích JS ⇒ chuyển nguyên tham số sang `ExtensionManager` (hành vi không đổi). Nguồn Legado ⇒ engine, **không** qua `cleanAndResolveUrl`. `page` của Legado trả `[url]` (vòng mục lục nằm trong `toc`); `home` trả `[]`, `genre` trả các mục khám phá bấm được với script giả `__legado_explore__`. Tranh/video Legado ném "chưa hỗ trợ ở bản này".
- **Call site** đổi sang facade (không đổi logic tiện ích JS): `ChapterContentRepository` (tách `+SourceFetch`), `BookDetailLoader` (+`context:`), `BookDetailView+Extensions/+TOCPreparation`, `SearchView`, `DiscoveryView+Loading`, `PaginatedNovelLoader`, `AllCommentsView`, `CommentSectionView`, `SuggestRowView`, `NewChapterProbe`, `ExportContentProvider`, `DownloadManager`. `BookDownloadWorker` rẽ nhánh Legado **trước** `prepareIfNeeded`/`cleanAndResolveUrl` (`+Legado`), vẫn tuần tự và huỷ được.
- **Lọc nguồn**: `SearchExtensionScopePolicy.isSearchScoped`/`isDiscoverable` — Tìm kiếm, Đổi nguồn chỉ nhận nguồn Legado đang bật + loại đã hỗ trợ + có rule tìm; Khám phá thêm điều kiện có `exploreUrl` (tranh/video Legado bị chặn dù "browsable" theo loại). **Tìm mọi nguồn**: tiện ích JS song song như cũ, nguồn Legado qua cửa sổ trượt tối đa 8 (`LegadoSearchScheduler`, mới). Ẩn nút ⚙ cấu hình JS cho nguồn Legado ở bảng chọn nguồn Khám phá; trình duyệt bỏ nguồn Legado khỏi lối tắt và bước dò URL; kiểm chương mới bỏ sách Legado không chạy được và chờ danh sách Legado nạp (≤ ~5 s).
- **Phân trang Khám phá**: `PaginatedNovelLoader` nhận chỗ cắm `{{…page…}}`; với mục khám phá Legado chỉ tin `nextPage` của runtime và dừng khi trang không thêm mục mới (trang web bỏ qua số trang không làm tải mãi).
- **Trang chi tiết**: thẻ thể loại không có script hiện dạng nhãn tĩnh (`BookDetailHeaderView.genreChip`), không mở danh sách hỏng. Tiện ích JS luôn có script nên không đổi.
- **Log**: chẩn đoán mềm của engine chỉ gắn `❌` cho 3 mục đầu mỗi phiên (trước là 20) để "tìm mọi nguồn" không làm tràn file log; lỗi `search` của facade không gắn `❌`.
- **Còn nợ**: chưa dọn sidecar mồ côi lúc mở app; thêm sách rồi thoát trước lượt mục lục kế tiếp thì mất biến của lượt tìm; `canReName`, `ruleContent.title`, `isVip`/`updateTime` chưa dùng; nhập lại nguồn với `bookSourceType` khác đổi loại của sách đã lưu từ nguồn đó.
- Chuyển entry `[1.3.531]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới** (`SearchView.swift` 821 → 794, `ChapterContentRepository.swift` 455 → 430; các file legacy khác ≤ baseline). Không còn `ExtensionManager.shared.(search|detail|toc|chap|page|home|genre|executeCustomScript)(` ngoài facade. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.565] - 2026-10-21

### feat: engine nguồn Legado (rule, mạng, JS) viết mới theo đặc tả

Bước 6, 7, 8 của đợt 1 plan "nguồn truyện Legado — viết mới theo đặc tả". Viết mới hoàn toàn từ `Docs/Specs/legado-source-spec.md` (clean-room), 65 file / ~7.600 dòng dưới `Sources/Services/LegadoSource/{Rule,Net,JS,Engine}/`. Chưa có caller — luồng + facade ở commit sau.

- **Rule** (`Rule/`): đường ống phân đoạn `<js>`/`@js:`; 4 chế độ — mặc định kiểu jsoup (`LegadoJsoupSelector` trên SwiftSoup), CSS `@css:`, JSONPath tự viết có filter (`LegadoJSONPathEvaluator`/`Filter`), XPath trên libxml2 (`LegadoXPathDocument` mở rộng: ngữ cảnh theo nút, nút/chuỗi, serialize; `LegadoXPathNode`); regex danh sách `:`; toán tử `||` `&&` `%%`; đuôi `##`/`###`; chỉ số `.0` `.-1` `!0` `[a:b:c]` `[1,3]`; mẫu `{{…}}`/`{$.x}`/`@get:{}`; `@put`; tiền tố `-`/`+` của rule danh sách. Bộ quét có nhận biết nháy/ngoặc (`LegadoRuleScanner`), regex cache theo pattern (`LegadoRegexCache`), HTML → văn bản (`LegadoHTMLText`). Parser JSON lỏng riêng của engine (`LegadoEngineJSONParser`).
- **Mạng** (`Net/`): dựng request theo thứ tự §3.2 — khối option `,{…}`, placeholder trang/từ khoá, `<a,b>`, mã hoá query/form theo `charset` kể cả GBK (`LegadoURLEncoder`, `LegadoCharset`), body + Content-Type; header nguồn JSON hoặc JS tính mỗi request; HTTP client riêng tự đi chuyển hướng để giữ `Set-Cookie` mọi chặng; cookie jar **theo nguồn** khi `enabledCookieJar`; `retry`; giải mã phản hồi theo §4.5; `concurrentRate` (cả `N/ms` và số ms) dùng chung giữa mọi phiên của cùng nguồn (`LegadoRateLimiter`); WebView ẩn qua `WebViewLoader` có sẵn (nhảy main bất đồng bộ, thread engine chờ theo lát ngắn — không semaphore trên main).
- **JS** (`JS/`): JavaScriptCore **riêng** (không dùng `JSExecutor`) chạy trên thread nền chuyên dụng, một native dispatcher; `java.*` đợt 1 theo spec §6.4 (mạng `ajax`/`ajaxAll`/`connect`/`get`/`post`/`head`; rule `getString`/`getStringList`/`getElements`/`getElement`/`setContent`/`put`/`get`/`toNumChapter`; mã hoá/băm/base64/hex/AES/DES/HMAC; `log`/`toast`/`timeFormat`/`t2s`/`s2t`/`htmlFormat`/`randomUUID`/`androidId`/`getWebViewUA`/`getCookie`), `source`, `book`, `chapter`, `cookie`, `cache`, shim `org.jsoup`, `Packages`/`JavaImporter` giả lập phần hay gặp. `jsLib` nạp một lần mỗi runtime. Hàm hoãn (§6.11: `startBrowser*`, đăng nhập, `refreshExplore`, font, file/zip…) ném lỗi "Chưa hỗ trợ <tên> ở bản này" để bộ chạy nghiệm thu phân loại; cố ý không định nghĩa `java.qread`, `deviceID`, `reLoginView`, `getUserAgent` (§6.10). `toast` chỉ ghi log (Services không toast).
- **Phiên** (`Engine/`): `LegadoEngineSession.run` chạy thân tác vụ trên thread engine, huỷ được, không bao giờ bọc `CancellationError`; `LegadoEngineSource` (bối cảnh nguồn, không phụ thuộc model của kho); `LegadoBookContext`/`LegadoChapterContext` (biến truyện/chương — luồng ở commit sau ghi sidecar); `LegadoEngineError` phân loại `category` (cú pháp chưa hỗ trợ / HTTP / quá thời gian / JS…), lỗi mềm vào `LegadoEngineDiagnostics`. Biến nguồn, `source.put`, `cache.*`, cookie, `jsLib` dạng map, `androidId` lưu file dưới `applicationSupport/legado_state/` (`LegadoFileStateStore`); `cache.putMemory` chỉ trong bộ nhớ.
- **Tự chọn khi spec chưa nói** (cần đo bằng bộ chạy nghiệm thu): phân đoạn JS đứng đầu nhận `result` là chuỗi thân trang; XPath `//x` dưới một mục hiểu là tương đối với mục; placeholder trong mã JS chỉ nhận `{{…}}` và `@get:{}`; `book.setReverseToc`/`setUseReplaceRule` chỉ ghi chẩn đoán. WebView dùng kho dữ liệu WebKit mặc định (chung cookie với trình duyệt của app), POST qua WebView có thể mất body, mã trạng thái luôn 200.
- Chuyển entry `[1.3.530]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới**; mọi file ≤ 400 dòng; không có tên/đường dẫn của mã nguồn gốc trong code. Bootstrap JS đã qua `node --check`. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.564] - 2026-10-21

### feat: kho nguồn Legado và tab Nguồn Legado trong Kho Tiện Ích

Bước 4, 5, 12 và phần màn Kho của bước 11 trong đợt 1 plan "nguồn truyện Legado — viết mới theo đặc tả" (người dùng đã duyệt plan + mockup). Hành vi Legado theo `Docs/Specs/legado-source-spec.md`.

- **Model** (`Sources/Models/LegadoSource/`, mới): `LegadoBookSource` (+`Derived`) decode khoan dung qua `LegadoModelJSON`/`LegadoModelCoercion` (số-hoặc-chuỗi, bool-hoặc-số, nhóm rule là object hoặc chuỗi JSON lồng, giữ JSON gốc), `LegadoSearchRule` (dùng chung cho khám phá), `LegadoBookInfoRule`, `LegadoTocRule`, `LegadoContentRule`, `LegadoExploreEntry` (dạng không phải JS của `exploreUrl`), `LegadoSourceKind` (0 chữ / 2 tranh / 4 video / còn lại không hỗ trợ), `LegadoSourceSummary`, `LegadoSourceGroupCount`.
- **Kho** (`Sources/Services/LegadoSource/Store/`, mới): mỗi nguồn là `extensions/<packageId>/` gồm `source.json` (nguyên văn) + `plugin.json` sinh tự động (`author: "Legado"`, `type` họ `legado*`, `locale: zh_CN`, `version` tăng mỗi lần ghi). `packageId = "legado_" + sha256(bookSourceUrl đã trim).prefix(16)` — đóng băng. Nhận diện nguồn Legado theo `Extension.type`, không theo tiền tố. Bật/tắt vá đúng khoá `enabled`. `LegadoSourceImporter` nhận mảng / object / chuỗi escape, bỏ trùng theo `bookSourceUrl`, bỏ qua kèm lý do: audio, tệp tải về, loại lạ, thiếu `bookSourceUrl`, thiếu rule tối thiểu (bản nới: tìm **hoặc** khám phá + mục lục + nội dung). `LegadoSourceRepository` (`@MainActor @Observable` + bảng chụp nonisolated cho tầng nền: `isEnabled(packageId:)`, `summarySnapshot(packageId:)`) nạp trên nền sau cổng từ điển, dịch QT tên + nhóm một lần rồi cache. `LegadoSourceCoordinator`: nhập tệp/URL/bộ nhớ tạm, bật/tắt, bật/tắt hàng loạt, xoá, xoá tất cả — ghi file trên nền rồi **một** lời gọi `upsertExtensions`. `installOrigin` mới `"legadoImport"`.
- **`LegadoSourcePolicy`** (mới, thuần): `isLegado`, `excludingLegado`, `isRunnable` (Legado + đang bật + loại đã hỗ trợ — đợt 1 chỉ chữ).
- **UI tab "Nguồn Legado"** (segment thứ 3 của Kho Tiện Ích, khớp mockup): toolbar chỉ menu ⋯ (nhập từ tệp JSON / URL / bộ nhớ tạm · bật/tắt tất cả theo danh sách đang lọc · "Xoá tất cả nguồn Legado" có xác nhận); ô "Tìm nguồn Legado" khớp tên gốc lẫn tên QT; chip nhóm có số đếm (sắp theo số nguồn, cuối là "Chưa nhóm"); dòng "Đang bật x/y"; dòng nguồn: tên QT, chip loại + nhóm (tối đa 2, còn lại "+N"), "Cần đăng nhập", "Chưa hỗ trợ" cho tranh/video, URL, công tắc, nút 🗑 34×34 xoá ngay. Alert tổng kết "Đã nhập N nguồn" (mới / cập nhật / bỏ qua theo lý do / "Nguồn giữ trạng thái bật/tắt trong tệp"). File: `LegadoSourceListView`, `LegadoSourceRowView`, `LegadoSourceTabState`, `RepositoryManagerView+LegadoMenu`; nút 🗑 tách thành `ExtensionRowTrashButton` dùng chung cho hai tab.
- **Chặn rò rỉ ở màn Kho**: tab 0 và số đếm bộ lọc loại nguồn Legado; "Xóa tất cả tiện ích" chỉ gỡ tiện ích JS; audit gỡ bản ghi thì nạp lại danh sách Legado. `RepositoryManagerView.swift` 606 → 605 dòng; chữ hướng dẫn ở tab "Danh sách kho" bỏ tên nền tảng cũ, nay là "kho tiện ích".
- **Coordinator**: thêm `ExtensionTransactionCoordinator.deleteExtensions(packageIds:)` — xoá nhiều bản ghi, ghi index một lần (xoá tất cả nguồn Legado).
- **Backup**: `BackupExtensionInstaller` dựng bản ghi Legado từ thư mục thật sau bước thay (type/version theo `plugin.json`); `BackupRestoreWorker` nạp lại danh sách sau khôi phục.
- **Hiệu năng (bộ 1316, 1.378 nguồn, ~10 MB)**: parse, phân loại, ghi file, dịch QT đều trên nền; main chỉ nhận kết quả + một lần upsert. Mô phỏng phân loại: nhập 804, bỏ qua 574 (thiếu rule tối thiểu 535, tệp 21, audio 11, trùng 6, thiếu URL 1).
- **Chưa xong / cần xác nhận**: tab Legado chưa áp công tắc NSFW (195 nguồn nhóm `特殊书源 🔞`); tên QT hiện kể cả khi tắt dịch toàn app; bật/tắt không tăng `version`. Tìm kiếm / Khám phá / Đổi nguồn / tải truyện / debug server chưa nối — commit sau.
- Chuyển entry `[1.3.529]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.563] - 2026-10-21

### docs: đặc tả hành vi nguồn Legado đợt 1 (clean-room)

Bước 2 của đợt 1 plan "nguồn truyện Legado — viết mới theo đặc tả": `Docs/Specs/legado-source-spec.md` (mới, ~1.630 dòng) là **nguồn sự thật duy nhất** về "Legado chạy thế nào" cho các agent triển khai.

- **Viết bởi một agent riêng**, chỉ từ tài liệu trợ giúp được phép (`ruleHelp.md`, `jsHelp.md`, `xpathHelp.md`, `regexHelp.md`, `debugHelp.md`…) + quan sát 6 bộ corpus yckceo (1315, 1316, 1208, 1158, 1298, 1272 — 3.701 nguồn sau bỏ trùng, 3.406 nguồn chữ) + ~20 lần curl trang thật. Không đọc mã nguồn Legado/Yuedu/nhánh cũ. Corpus nằm ngoài repo.
- **Mục lục**: §0 phạm vi + luật nhãn · §1 model JSON (decode khoan dung, tách nhóm, loại, rule tối thiểu — 84% nguồn chữ đạt) · §2 rule (đường ống, nhận diện chế độ, `||` `&&` `%%`, `##`/`###`, placeholder, phương ngữ kiểu jsoup, CSS, `@put`/`@get`, JSONPath, XPath, regex danh sách) · §3 URL (khối option, placeholder, `<a,b>`, charset, header) · §4 mạng (`concurrentRate`, cookie, retry, WebView, redirect) · §5 luồng (tìm, khám phá 3 dạng, thông tin, mục lục, nội dung, phân trang + chống lặp, biến, `jsLib`) · §6 JS bridge (danh sách hàm `java.*`/`source.*`/`book`/`chapter`/`cookie`/`cache` đợt 1 theo tần suất, shim `org.jsoup`, hàm hoãn) · §7 phụ lục (bảng đợt 1/hoãn, 28 điểm `[UNKNOWN]` U1–U28 để bộ chạy nghiệm thu đo).
- Mỗi khẳng định gắn `[tài liệu]` (112) / `[quan sát]` (151) / `[UNKNOWN]` (62); `[đề xuất]` là ghi chú khuyến nghị khi không có bằng chứng (§0.3).
- **Kiểm clean-room** (script ngoài repo): không có tên lớp nội bộ của engine gốc ngoài những tên xuất hiện trong script của chính corpus; không câu nào trùng nguyên văn tài liệu (cửa sổ 40 ký tự / 15 chữ Hán); 0 chữ cấm.
- Không đổi code. Không build — commit chỉ có tài liệu nên CI không chạy.
- Chuyển entry `[1.3.528]` sang `CHANGELOG.archive.md` để giữ 30 entry.

## [1.3.562] - 2026-10-21

### build: link libxml2 cho XPath của nguồn Legado, CI chạy trên nhánh Legado

Bước 3 của đợt 1 plan "nguồn truyện Legado — viết mới theo đặc tả" (2026-10-19, người dùng đã duyệt): chứng minh libxml2 hệ thống link được trên CI trước khi xây engine rule.

- **`project.yml`**: thêm `- sdk: libxml2.tbd` cạnh `libsqlite3.tbd`, và `HEADER_SEARCH_PATHS` = `$(inherited)` + `$(SDKROOT)/usr/include/libxml2` (header của libxml2 tự include nhau theo dạng `<libxml/...>`).
- **Bridging header gom chung**: `SWIFT_OBJC_BRIDGING_HEADER` đổi từ `VieNeuONNXBridge.h` sang `Sources/Common/Bridging/FreeBookBridgingHeader.h` (mới), file này include `VieNeuONNXBridge.h` (không đổi nội dung) và `LegadoLibXML2.h` (mới — `HTMLparser.h`, `tree.h`, `xpath.h`, `xpathInternals.h`). Sai đường dẫn ở đây là mọi file Swift hỏng.
- **`LegadoXPathDocument`** (mới, `Sources/Services/LegadoSource/Rule/`): bọc `htmlReadMemory` (RECOVER/NOERROR/NOWARNING/NONET) + `xmlXPathEval`, trả giá trị chuỗi của node-set/string/number/boolean. **Không** `#if canImport`, không fallback: thiếu libxml2 phải là lỗi biên dịch. Chưa có caller — engine rule ở các commit sau.
- **CI**: `build-ipa.yml` chạy cả trên nhánh `claude/legado-source-bb5e46`.
- Chuyển entry `[1.3.527]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền (`JSDom.swift`, `TTSManager.swift`), **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch.
## [1.3.561] - 2026-10-22

### feat: menu Khám phá mở lại trình duyệt, widget chung nháy theo tiến trình

Người dùng: *"đem nút mở trình duyệt ở khám phá trở lại"*, rồi *"gộp luôn nút dịch đi, dùng biểu tượng của widget chung, đổi biểu tượng widget chung thành cái khác"*, *"khi widget chỉ có 1 mục đang chạy thì hiển thị icon mục đó… bấm vào thì hiển thị trực tiếp ra mục đó"*, *"màu nhấp nháy đồng bộ"*, *"khi không có tiến trình chạy thì Icon chuông, không nháy, bấm vào mở màn hình thông báo"*. Chốt qua `/grill-me` (plan `Docs/Plans/2026-10-22-plan-menu-kham-pha-va-widget-chung.md`, mockup đã duyệt); người dùng duyệt cả việc viết lại `rules.md` § Nút hub nổi.

- **Header Khám phá**: nút Kiểu hiển thị và nút dịch gộp thành một nút menu tròn `square.grid.2x2` (`DiscoverySourceMenuButton`, 38×38, 17pt semibold, `.menuOrder(.fixed)`): **Mở trình duyệt** (trang nguồn đang chọn bằng `BypassWebView` toàn màn hình, ẩn khi nguồn không có link; "Import truyện" ⇒ Chi tiết trong stack Khám phá, bỏ toast "Đã hoàn tất tải các chương!" của nút cũ) · **Kiểu hiển thị** (sheet như cũ) · **Dịch văn bản** + dòng phụ Đang bật/Đang tắt (popover bảng dịch cũ neo ở nút menu). Nút safari đã bỏ ở 1.3.546 nay quay lại trong menu; bảng chọn nguồn vẫn không có, nút Trình duyệt ở Cấu hình tiện ích giữ nguyên. Dựng route Import gom về `DiscoveryView.showImportedBook`.
- **Bảng dịch dùng chung**: nội dung popover của `ReaderTranslationScopeMenuView` (công tắc, phạm vi, Lưu lại, kẹp phạm vi) tách thành `TranslationScopePopupView` (`ReaderTranslationScopeMenuView` 307 → 143 dòng); chữ ký public và `TranslationPopupScope` giữ chỗ cũ, Reader và Chi tiết truyện không đổi.
- **Chip Thể loại** ở Khám phá đổi icon lưới → `tag` (không trùng nút menu ngay trên).
- **Widget chung theo số tiến trình** (AI đang chạy, video thu nhỏ, tác vụ nền tải/xuất/nhập/sao lưu/tải model; mọi tab; tin chưa đọc **không** tính — `ButtonState.runningKinds`): 0 ⇒ chuông `bell`, không nháy, chạm mở màn Thông báo; 1 ⇒ icon của mục, nháy, chạm mở thẳng mục (AI ⇒ bung + menu ở trang "AI đang chạy"); ≥ 2 ⇒ `square.stack.3d.up`, nháy, chạm mở menu. Áp cả khi đang nép. Bỏ badge số/chấm đỏ, viền tím AI, tham số `mode`/`edge` của `FloatingHubButton` và sink vẽ lại theo cạnh. Rẽ nhánh chạm ở `activateByRunningTasks` (`+Actions`).
- **Nháy đồng bộ với nút trình duyệt thu nhỏ**: `FloatingHubPulseView` (`CABasicAnimation` đổi màu nền một layer con, ≤ 20 fps, chỉ gắn khi chưa có, gỡ khi rời cửa sổ, khôi phục khi về foreground; không đụng opacity). Màu đỏ, đáy nhịp (mức 0,4) và nửa chu kỳ 0,9 s là hằng `static` dùng chung — `VisibleBrowserReopenButton` đọc lại, giá trị không đổi. Không bảo đảm trùng pha (SwiftUI vs Core Animation).
- **`rules.md`** § Nút hub nổi: (a) viết lại theo luật tiến trình; (b) bỏ đường "số mục còn < 2" (code không có — menu có tập dòng cố định từ 1.3.533); (c), (e) và câu hitTest cập nhật theo. Luật chạm cũ ở (a) vốn đã lệch code (code luôn mở menu).
- Chuyển entry `[1.3.531]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code, grep chéo `ReaderTranslationScopeMenuView(`, `TranslationPopupScope`, `FloatingHubButton(`, `activeKinds`; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI xác nhận biên dịch; **chưa thử trên máy**: popover dịch mở từ `Menu`, nháy khi hub nép mép, về lại foreground, chạm khi chỉ 1 AI.

## [1.3.560] - 2026-10-22

### fix: đổi nguồn ở chi tiết truyện chưa lưu chỉ tìm nguồn cùng loại

Người dùng: *"khi tìm truyện thay thế thì chỉ tìm nguồn truyện, không tìm video và comic, ngược lại video và comic cũng thế"*; bác giả thuyết `type` lạ (*"điều tra kỹ vào"*), duyệt plan.

- **Nguyên nhân**: menu "…" → "Thay đổi nguồn" ở `BookDetailView` luôn hiện, nhưng truyện **chưa lưu** (mở từ Khám phá/Tìm kiếm, chưa đọc) có `localBook == nil` ⇒ `SearchView` nhận `changeSourceTargetBook: nil` và chạy như tìm thường: hiện hàng chip, lọc theo chip đã nhớ (mặc định "Tất cả") ⇒ tìm cả chữ, tranh, video. Bốn lối còn lại (Kệ, Tìm trên kệ, Bộ sưu tập, Reader) truyền đủ sách nên vốn đã lọc cùng loại. Giá trị `type` của tiện ích (registry + `plugin.json`) được lưu đúng chuẩn — không phải nguyên nhân.
- `SearchView` thêm tham số `kindScopePackageId` (mặc định `nil`). `sameKindScopePackageId` (`SearchView+KindFilter`) = tiện ích của sách cần đổi ?? `kindScopePackageId`, đưa vào `SearchExtensionScopePolicy.searchableExtensions(changeSourcePackageId:)` — cùng luật cùng loại và ngoại lệ NSFW của đổi nguồn. Hàng chip và lượt tìm lại khi đổi chip tắt theo cùng điều kiện.
- `BookDetailView` luôn truyền `kindScopePackageId: extensionPackageId` (sách đã lưu thì trùng tiện ích của `localBook`).
- Truyện chưa lưu: bấm kết quả vẫn mở chi tiết truyện như trước (không có sách để chuyển dữ liệu); bản sửa chỉ giới hạn loại nguồn được tìm.
- Chuyển entry `[1.3.530]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code, grep chéo caller của `SearchView(`; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI xác nhận biên dịch; chưa thử trên máy.

## [1.3.559] - 2026-10-21

### fix: thanh xoá, sao chép, dán bị bàn phím che ở màn thêm rule

Người dùng: *"có lỗi thanh sao chép, dán, clear, bị che bởi gợi ý của bàn phím"* — chỉ ở màn Thêm rule; duyệt plan.

- **Nguyên nhân (suy luận, chưa kiểm chứng trên máy)**: `[1.3.556]` dùng **một** `UIInputView` cho mọi ô rồi đổi chiều cao 46 ↔ 82pt theo ô; iOS giữ chiều cao đo lần đầu (46pt) nên nội dung 82pt tràn xuống, hàng xoá · sao chép · dán nằm sau thanh gợi ý chữ của bàn phím.
- `KeyboardTextToolbarInstaller` giữ **hai** accessory, chiều cao đặt một lần lúc tạo và không bao giờ đổi: 46pt cho ô thường (như trước `[1.3.556]`), 82pt cho ô cài `KeyboardSuggestionSource`. Bỏ `updateAccessoryHeight`. Ô chuyển thanh đi đúng nhánh gán lại / `install` lại sẵn có.
- `KeyboardTextToolbarView` nhận `includesSuggestionRow` cố định theo instance (thanh 82pt luôn chừa chỗ hàng gợi ý) thay vì đọc `model.showsSuggestionRow`; cờ này thôi `@Published` vì chỉ installer đọc.
- **Chẩn đoán**: 0,6 s sau khi gắn thanh, nếu chiều cao thật lệch chiều cao đã đặt thì ghi `❌ [KeyboardToolbar] thanh cao …pt, cần …pt (ô <lớp>)` — ghi cả khi tắt log, mỗi chiều cao một lần.
- Chuyển entry `[1.3.529]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI xác nhận biên dịch; chưa thử trên máy.
