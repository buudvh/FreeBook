# CHANGELOG - Nhật ký Thay đổi CodeGraph FreeBook

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **FreeBook**.

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

## [1.3.676] - 2026-11-03

### fix: nút lọc không nháy mất khi vừa áp dụng bộ lọc

Tiếp 1.3.675 (rà lại sau khi CI xanh).

- **`ExtensionFilterCatalog.info(for:)`**: khoá tra gồm cả `configJson`, nên mỗi lần áp dụng bộ lọc hoặc màn Cấu hình tự lưu thì khoá mới chưa có ⇒ trả `nil` ⇒ nút lọc biến mất một nhịp, cụm nút tròn của header Khám phá xô sang trái rồi về. Giờ trong lúc đọc bộ mới vẫn trả bộ cũ của cùng tiện ích; lần đầu (chưa có bộ nào) vẫn ẩn tới khi đọc xong.
- Chuyển entry `[1.3.646]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.675] - 2026-11-03

### fix: bộ lọc tiện ích ở mọi màn danh sách, ngăn kéo chọn nguồn và ô tìm thể loại

Người dùng: *"sửa lại ext qidian… dùng config của ext select để làm bộ lọc… thêm ô tìm kiếm cho genres… thêm biểu tượng lọc ngoài màn hình nếu config có kiểu select, bool, list"*; thêm *"hiển thị nút bộ lọc ở tất cả màn hình danh sách"*; chốt từng nhánh qua grill-me + mockup rồi duyệt plan. Tiện ích qidian (bộ lọc STV, home thể loại, genre nhãn) sửa ở repo tiện ích riêng.

- **Nút lọc** (`ExtensionFilterButton`, mới): chỉ hiện khi `config` của tiện ích có mục `select` / công tắc (cả bool trần) / `list`; chấm trắng khi khác mặc định. Đọc `plugin.json` ở luồng nền một lần cho mỗi (tiện ích, phiên bản, `configJson`) qua `ExtensionFilterCatalog` (`@MainActor @Observable`), `body` chỉ tra bảng. Ba chỗ: header Khám phá (nút tròn 38 trước ⋯, mọi tab home/nhãn/Trang chủ), trang danh sách thể loại/nhãn `CategoryNovelsListView` (cặp với Kiểu hiển thị trong một `ToolbarItem`, cả khi mở từ Chi tiết), màn Tìm khi tìm trong một nguồn (thay chỗ nút "Tìm").
- **Sheet Bộ lọc** (`ExtensionFilterSheet`, mới): mọi mục lọc theo thứ tự `plugin.json`, dùng lại dòng của màn Cấu hình. Sửa trên bản nháp; ↺ về mặc định; "Áp dụng" **lưu vĩnh viễn** qua `ExtensionTransactionCoordinator.saveExtensionConfig` — đọc config mới nhất, chỉ thay khoá lọc; vuốt đóng khi chưa áp dụng thì hỏi (`confirmDiscardOnSwipe`).
- **Tải lại sau khi áp dụng** (kể cả đang ở trang 2+): Khám phá dùng `reloadAfterConfigChangeIfPending()` khi sheet đóng (tab đang xem giữ, về trang 1, neo cuộn bị xoá); danh sách thể loại gọi `PaginatedNovelLoader.reset(configJson:)` (mới — config là `var`, bộ đếm lượt bỏ trang cũ về muộn và lượt tự thử lại đã hẹn); màn Tìm tìm lại bằng bản tiện ích mới nhất (`selectedExtension` là bản chụp có config cũ).
- **Màn Cấu hình tách phần dùng chung**: `ExtensionConfigSchema` (mới — đọc `config` theo thứ tự, mục ở gốc, `support_url`, giá trị ban đầu, dựng `configJson`, `filterKeys`) và `ExtensionConfigFieldRow` (mới — 5 dáng dòng chuyển từ `+GlobalConfig`). Hành vi màn Cấu hình giữ nguyên; `plugin.json` hỏng vẫn báo lỗi.
- **Header Khám phá + ngăn kéo chọn nguồn**: nút tròn icon tiện ích + tên và link hai dòng (`DiscoverySourceHeaderButton`, mới); bấm nút hay vùng chữ đều mở ngăn kéo **trượt từ trái** (`DiscoverySourcePickerModifier`, mới) thay sheet chọn nguồn: ô tìm viên thuốc, NSFW, chip loại, hàng nguồn với ⚙/ⓘ và 📌. Sheet Cấu hình / Chi tiết nguồn Legado chuyển về màn Khám phá. `SideDrawerMenu` thêm tham số `edge` (mặc định phải; panel, nền kính, vuốt đóng theo mép).
- **Ô tìm kiểu mục lục**: `ChapterTOCSearchField` thêm `onSubmit`/`onClear` tuỳ chọn. Màn Tìm bỏ nút "Tìm" (bấm Tìm trên bàn phím). Tab nhãn Khám phá có ô "Tìm kiếm N thể loại": lọc ngay khi gõ, khớp tên gốc lẫn tên đã dịch, bỏ dấu, "đ" ≈ "d"; thanh tab ẩn theo bàn phím.
- Chuyển entry `[1.3.645]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code + diff; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy — cần thử: gõ phím trong ngăn kéo chọn nguồn (cửa sổ nổi riêng); qidian bản 25: nút lọc hiện ở Khám phá, chọn "Lượt đọc tuần" + "> 500" rồi Áp dụng thì tab đang xem tải lại từ đầu; tìm "hệ thống" ở tab nhãn.

## [1.3.674] - 2026-11-01

### fix: danh sách kho thành trang con, tự kiểm tra cập nhật tiện ích

Người dùng: *"cho màn hình danh sách kho thành màn hình con của tất cả tiện ích. Khi vào tất cả tiên ích hãy tự chạy kiểm tra cập nhật của tất cả ext"*; duyệt plan: lối vào nằm trong ngăn kéo …, giãn cách 5 phút.

- **Trang con Danh sách kho** (`ExtensionRepositoryListView`, mới): ô chọn của tab Kho tiện ích còn hai mục Tất cả tiện ích · Nguồn Legado (giữ tag 0/2). Hàng "Danh sách kho" (chữ phụ = số kho) đứng đầu ngăn kéo … của Tất cả tiện ích ⇒ đẩy trang `.backPageTitle`, phủ thanh tab. Header giữ cụm ↻ | +; xoá kho, trang trống + nút nhập kho mặc định như cũ. Bỏ lối vào cũ.
- **Tự kiểm tra cập nhật** (`ExtensionUpdateCheckCoordinator`, mới, `@MainActor @Observable`): kiểm tra = tải lại registry của mọi kho (1 request/kho, song song, tối đa 20 s/kho, bỏ cache URLSession cục bộ) rồi `saveRegistry` ⇒ `hasUpdate` và banner "Cập nhật tất cả" tự đổi. Chạy khi vào tab Kho tiện ích lúc đang ở Tất cả tiện ích, hoặc khi chuyển ô chọn từ Legado sang. Giãn cách 5 phút, giữ trong RAM (mở lại app ⇒ kiểm tra ngay lần đầu vào), chỉ tính lượt tải được ít nhất một kho; kho chưa có cache vẫn được tải trong giãn cách. ↻ / "Thử lại" bỏ qua giãn cách. Chỉ kiểm tra, không tự cài; nguồn Legado ngoài phạm vi. Bỏ `RepositoryRefreshPolicy` (cửa 6 tiếng nên gần như không bao giờ tự chạy); `rules.md` mục 7 cập nhật theo.
- **Một cờ bận chung** (`isBusy`): kiểm tra, thêm kho, xoá kho cùng đọc ⇒ không chạy trùng. Sửa lỗi cũ: thêm kho trong lúc làm mới hạ cờ `isRefreshingAll` giữa chừng ⇒ mở lại nút xoá kho, cho lượt làm mới thứ hai chạy.
- **Hiển thị** (`ExtensionUpdateCheckStatusLine`, mới): dòng nhỏ dưới "Đang hiển thị N tiện ích" — vòng quay "Đang kiểm tra cập nhật…"; xong "Đã kiểm tra cập nhật lúc HH:mm"; lỗi chữ cam "Không kiểm tra được cập nhật" / "Không tải được f/t kho" + "Thử lại". Cache cũ giữ nguyên, không toast, không alert. Trang Danh sách kho dùng cùng dòng. Thông báo của "Cập nhật tất cả", Import zip và tự thêm kho mặc định giờ hiện ở tab Tất cả tiện ích (trước chỉ hiện ở tab kho).
- **Back từ trang Danh sách kho**: gốc nhận lại `onAppear` ⇒ bỏ qua đúng một lần (không dọn, không kiểm tra, không tự thêm lại kho mặc định vừa bị xoá hết).
- `RepositoryManagerView.swift` 603 → 508 dòng.
- Chuyển entry `[1.3.644]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code + diff; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy — cần thử: vào tab Kho tiện ích thấy "Đang kiểm tra cập nhật…" rồi giờ kiểm tra; tắt mạng thấy chữ cam + "Thử lại"; ngăn kéo … → Danh sách kho → back thì không chạy lại.

## [1.3.673] - 2026-11-01

### fix: tiện ích JS cài an toàn, tìm kiếm tải thêm, cookie của nguồn

Người dùng nhờ điều tra tiện ích JS nào FreeBook chưa dùng được (báo cáo 33 mục); chọn "Lập plan mục 1–3", duyệt cả 3 kể cả nút trang đăng nhập.

- **Cài/cập nhật an toàn** (`ExtensionPackageInstaller`, mới): giải nén + giải mã ở thư mục tạm, thành công mới đổi chỗ vào `extensions/<packageId>/` (bản cũ dời sang tmp, chuyển bản mới lỗi thì trả bản cũ về). Trước đây `install(item:)` xoá bản đang chạy rồi mới giải mã ⇒ gói không giải được làm mất bản cũ; cài mới lỗi để lại thư mục dở; nhập zip xoá bản cũ trước khi chuyển. Giữ nguyên hình dạng `localPath` (zip bọc thư mục con vẫn trỏ thư mục con). `ExtensionManager.findMainExtensionFolder` thành `ExtensionPackageInstaller.findMainFolder`.
- **Định dạng mã hoá mới**: 14/93 gói của kho chính thức (wikidich, wattpad, mangadex, metruyenchu-app, allshorts…) có ciphertext mở đầu `a7 e4 1d 02`; app chưa giải được (thử AES-GCM/ChaCha20/CTR với khoá cũ đều không khớp — UNKNOWN). `ExtensionScriptDecoder` nhận ra ngay sau Base64, **trước** bước kiểm độ dài (4 file dài đúng bội 16 từng rơi xuống CBC rồi báo nhầm "source/author bị sửa"), ném lỗi riêng (`isUnsupportedFormat`). Màn Quản lý tiện ích báo "<tên> dùng định dạng mã hoá mới, FreeBook chưa đọc được." kèm "Bản đang cài vẫn giữ nguyên."; "Cập nhật tất cả" gom lỗi, báo "Đã cập nhật N/M tiện ích." (trước luôn báo xong, lỗi của tiện ích trước bị xoá). Máy đã bấm cập nhật trước bản này thì bản cũ đã mất.
- **Tìm kiếm tải thêm trang** (tìm trên một nguồn): `ExtensionManager+Search` (mới) có `searchPage` trả token trang kế — đọc `next` của object script trả về, thiếu thì `Response.nextPage`; `search(page:)` cũ thành vỏ cho bộ kiểm tra, tìm nhiều nguồn, bộ nghiệm thu. Trang 1 vẫn gửi `"1"`, trang sau gửi nguyên token. `SourceRuntime.searchPage`: nguồn Legado có trang kế khi `searchUrl` có chỗ cắm số trang và trang có kết quả. Màn Tìm (`SearchView+Paging`, `SearchPagingState`): tự nạp khi một trong 5 mục cuối hoặc sentinel cuối hiện ra (lưới `.id(count)`), không có nút "Xem thêm"; dừng khi token rỗng/trùng token vừa dùng, trang không thêm link mới, hoặc đủ 50 trang; lỗi trang sau tự thử lại 3 lần cách 2 s rồi dừng im lặng; tìm lại thì huỷ lượt tải thêm cũ. Tìm nhiều nguồn vẫn chỉ trang 1.
- **Cookie của nguồn**: `ExtensionCookieSync` (mới) chép cookie WebKit (nơi người dùng đăng nhập) sang `HTTPCookieStorage.shared` cho tên miền `source` ở đầu mỗi `JSExecutor.callAsync` (phủ cả runtime TTS). Rẻ nhờ `WKHTTPCookieStoreObserver` + bộ đếm thế hệ: WebKit không đổi ⇒ một lần khoá, không nhảy main. Chỉ chép cookie còn thiếu hoặc vừa đổi bên WebKit (dấu SHA-256 trong `UserDefaults`, không lưu giá trị) để không đè cookie `Set-Cookie` mới hơn của `fetch`; app ở nền hoặc WebKit không trả lời sau 2 s ⇒ bỏ lượt. `localCookie` (`JSExecutor+Cookie`, mới) đọc/ghi kho thật: `getCookie(url?)`; `setCookie` nhận dòng Set-Cookie hoặc danh sách `a=1; b=2`. `fetch` trả header thật đã gửi (gồm `Cookie` tính lúc gửi) ⇒ `response.request.headers` thêm khoá chữ thường (`.cookie`), kể cả khi qua browser ẩn. `WebKitCookieBridge` ghi dấu cho cookie chép từ "Mở link lỗi".
- **Trang đăng nhập** (`ExtensionConfigView+SupportLink`, mới): `support_url` là URL http(s) (trong `config` hoặc ở gốc) ⇒ dòng "Mở trang đăng nhập" thay ô chữ, mở `BypassWebView`; đóng ⇒ chép cookie ngay (WebKit thắng). Hưởng lợi: tiktok-tts, metruyenchu/vtruyen (phần cần đăng nhập), koanchay.
- **Không làm**: giải mã định dạng mới; trang sau của tìm nhiều nguồn; ghi header `Cookie` do script tự truyền vào kho; chiều URLSession → WebKit. Lưu ý: tiện ích có `source` thuộc google.com giờ nhận cookie đăng nhập Google — tắt bằng "Xử lý cookie hệ thống".
- Chuyển entry `[1.3.643]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code + diff; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy — cần thử: cập nhật một gói định dạng mới thì báo rõ và bản cũ vẫn chạy; tìm một nguồn rồi cuộn xuống thấy trang 2; tiktok-tts đăng nhập qua "Mở trang đăng nhập" rồi đọc được.

## [1.3.672] - 2026-11-01

### fix: cấu hình tiện ích hiện ô chọn select và danh sách list

Người dùng: *"bạn hãy đọc ext qimao của đường đen. trong đó có config dạng select. app chưa đọc được dạng đó"*; thêm các mục còn thiếu theo hợp đồng (từ phiên rà màn Cấu hình), *"đừng làm mode database"*; duyệt plan, chưa áp `thread_num`/`delay`/`ignore` làm giới hạn.

- **Tiện ích**: Qimao của Đường đen (repo GitHub của tài khoản `duongden`, `Novel_Zh/qimao` v37 có 6 mục `select`; bản Phim ngắn v7 có 1). Script (mã hoá) đọc biến global `CONFIG_*`, rồi `localConfig.getItem`, và so đúng chữ của lựa chọn.
- **Nguyên nhân**: `ExtensionConfigView.ConfigItem` decode bằng `JSONDecoder` chỉ 4 trường `title/mode/format/default`, bỏ `values`/`subtitle` ⇒ `select` rơi vào nhánh ô chữ. Phần tiêm giá trị chọn vào script vốn đúng.
- **`select`**: nút menu rộng hết dòng dưới tiêu đề, ✓ ở lựa chọn đang hiện (kiểu ô chọn của form đăng nhập Legado), chọn là lưu ngay, luôn lưu chuỗi. Mọi `format` đều là chọn **một**: hợp đồng bản đầu có `single`/`multiple` (chọn nhiều, nối dấu phẩy), bản hiện tại bỏ `multiple`; khảo sát ~800 `plugin.json` ở 8 kho: `single` 42, bỏ trống 17, `text` 2, `multiple` 0. Giá trị không có trong `values` hiện lựa chọn đầu (hợp đồng), không tự ghi đè.
- **`ConfigItem`** dựng tay từ dict: `default`/`values` là số/bool ⇒ ép chuỗi thay vì mất cả dòng. **`subtitle`** hiện ở mọi dòng có khai.
- **`list`** (mới, `ExtensionConfigListEditor`): dòng hiện số mục, chạm mở trang thêm (nút `+` nổi)/sửa/xoá từng dòng; giá trị là chuỗi JSON `"[\"a\",\"b\"]"`. Giá trị cũ không phải mảng JSON ⇒ một dòng; `default` viết thành mảng thật vẫn hiện (hợp đồng nói hiện rỗng — cố ý khác vì script cũng nhận nó).
- **Thứ tự mục** theo `plugin.json` (đọc lại bằng `LegadoEngineJSONParser` giữ thứ tự). `ExtensionScriptDecoder.clearEncryptFlag` giờ chỉ sửa đúng chữ `"encrypt": true` (trước ghi lại cả file `.sortedKeys` ⇒ tiện ích mã hoá mất thứ tự). Bản đã cài trước bản này phải cài lại mới có thứ tự gốc.
- **Khoá kết nối** `thread_num`/`delay`/`ignore` viết dạng giá trị trần: ẩn khỏi màn Cấu hình (hợp đồng: là giới hạn, không phải cài đặt), vẫn tiêm vào script; giá trị cũ người dùng đã sửa bị bỏ ở lượt lưu kế tiếp. Chưa áp làm giới hạn tải/lịch sử. Giá trị trần khác (`max_length`, `preload_size`…) vẫn sửa được.
- **Script nhận chuỗi**: `JSExecutor.injectGlobals` đổi mọi giá trị sang chuỗi trước khi đưa vào JS (biến global + `localConfig.getItem`) qua `ExtensionConfigValueFormatter` (mới) — bool ⇒ `"true"`/`"false"`, số ⇒ `"3000"`, mảng ⇒ JSON, `null` ⇒ `""`. `injectedConfigs` của Swift giữ kiểu gốc; cách lưu `configJson` không đổi. Script cũ dùng `if (X)` với bool sẽ thấy `"false"` là đúng.
- **Khám phá** tải lại `home`/`genre` khi `configJson` của nguồn đang xem đổi — chờ sheet chọn nguồn (nơi mở Cấu hình) đóng, hoặc lúc màn hiện lại nếu sửa từ tab Tiện ích; không tải lại sau mỗi lượt tự lưu của ô chữ (gọi nguồn dồn dập, tên miền gõ dở). Tab danh mục và trang `explore` dựng lại bộ nạp (`.id` theo mốc tải lại vì config).
- **Không làm**: `mode: "database"` (giữ như cũ — ô chữ), `config.js` động, `actions`, `format` `password`/`multiline` (mỗi kiểu 1 tiện ích dùng), áp giới hạn kết nối.
- **Kiểm chứng**: đọc code + diff; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy — cần thử: cài lại Qimao, màn Cấu hình hiện 6 ô chọn đúng thứ tác giả, đổi "Nhóm nội dung" rồi đóng sheet thấy Khám phá đổi; tiện ích AI có `api_key` dạng `list` thêm/xoá được dòng.

## [1.3.671] - 2026-11-01

### fix: tìm nhiều nguồn chừa luồng cho TTS khi đang phát

Người dùng: *"Tìm nhiều nguồn làm đơ google tts, nên ưu tiên để dư 1 luồng cho tts"*; chọn "A trước, B sau", duyệt plan.

- **Nguyên nhân**: "Tìm trên tất cả nguồn" chạy mọi tiện ích JS cùng lúc, không giới hạn. Script chạy **đồng bộ** trên cooperative pool (`JSExecutor.callAsync` → `runner.call`), `fetch` chờ bằng semaphore tới 15 s ⇒ quá ~6 nguồn là pool (≈ số lõi) bị chiếm hết. Google TTS cần chính pool đó ở mọi bước (`TTSAudioSynthesisWorker` → `RemoteTTSSynthesisCoordinator` → `URLSession` async) ⇒ hết đoạn nạp trước là đơ. Không phải main thread; không phải giới hạn kết nối của URLSession (Google TTS khác tên miền với nguồn). Đúng chẩn đoán #1 của plan perf 2026-10-09 (bản sửa đang chờ số đo).
- **Sửa (A)**: `SearchTTSThreadReservePolicy` (mới): TTS đang phát (mọi engine) ⇒ nguồn JS chạy cùng lúc tối đa `số lõi − 1 − (lời gọi JS khác đang chạy)`, tối thiểu 1; TTS không phát ⇒ không giới hạn như cũ. `LegadoSearchScheduler.searchAll` đưa nguồn JS vào cửa sổ trượt, tính lại giới hạn mỗi khi một nguồn JS xong (TTS dừng giữa lượt ⇒ nguồn còn chờ chạy hết); `shouldStart` (NSFW) xét cả nguồn JS đang chờ. Nguồn Legado giữ cửa sổ 8. `JSExecutionTelemetry.inFlightCount` đọc bộ đếm có sẵn. Không đụng tải truyện.
- **Log** (phải bật ghi log): `[SearchPerf] JSCap sources= cap= jsInFlight= cores= ttsPlaying=1` (một lần khi giới hạn có tác dụng), `[SearchPerf] JSDone sources= peak= ms= cancelled=`; `[TTSPerf] RemoteWait priority= engine= waitMs= queueMs= runMs= outcome= jsInFlight= cores=` (đoạn đang đọc chờ ≥ 400 ms hoặc một lượt chạy ≥ 2 s; `queueMs`/`runMs` lớn kèm `jsInFlight` gần `cores` = đói thread, không phải mạng chậm).
- **Giới hạn**: đang nghe mà tìm thì kết quả về chậm hơn; tải truyện/nạp chương đã chiếm gần hết pool thì tìm chỉ còn 1 nguồn và TTS vẫn có thể chậm; TTS bắt đầu sau khi bấm tìm thì nguồn đã chạy không bị giới hạn. Cách tận gốc (B: đưa JS ra khỏi pool, plan perf §1.4) để làm sau.
- `rules.md` (Tìm mọi nguồn) ghi luật mới và sửa nhận định sai "nằm trong actor ⇒ không chặn pool" (`BookDownloadWorker`, `ExtTTSRuntime` là actor mặc định, vẫn chạy trên pool). Chuyển entry `[1.3.641]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code + diff; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy — cần thử: nghe Google TTS rồi tìm tất cả nguồn, giọng không đơ và log có `JSCap`; tìm khi không nghe vẫn chạy hết cùng lúc như cũ.

## [1.3.670] - 2026-11-01

### fix: trình duyệt Legado dùng chung profile với trình duyệt của app

Người dùng: *"vì sao bạn làm trình duyệt đăng nhập của legado có profile khác trình duyệt chung vậy"*; duyệt "dùng chung".

- **Nguyên nhân**: `LegadoBrowserController` (trình duyệt hiện cho người dùng của nguồn Legado: đăng nhập web §10.2, `java.startBrowser*` §10.8) tạo `WKWebsiteDataStore.nonPersistent()` **mới mỗi lần mở** (chọn từ đợt 2 Legado, 4d69a023, để cookie không lẫn sang nơi khác — spec không bắt buộc). Trình duyệt của app, browser tiện ích JS và WebView ẩn của Legado (`LegadoWebViewFetcher` qua `WebViewLoader`) đều dùng kho mặc định ⇒ đăng nhập Google/GitHub, cookie qua Cloudflare không sang được; `localStorage` của trang mất sau mỗi lần đóng.
- **Sửa**: kho `.default()`. Giữ nguyên đồng bộ hai chiều với kho cookie của nguồn (gieo khi mở, đọc cookie các tên miền đã ghé khi đóng) — giống WebView ẩn của Legado vốn đã làm trên kho mặc định.
- **Đăng xuất** (`LegadoLoginService.logout`): thêm xoá cookie WebKit của tên miền nguồn (`baseURL` + URL đăng nhập web) qua `WebKitCookieBridge.removeCookies(forHosts:)` mới — cookie áp cho host (của host hoặc tên miền cha) và cookie của tên miền con. Không xoá thì lần mở sau đọc lại phiên cũ vào kho của nguồn. Tên miền khác đã ghé (Google, GitHub khi đăng nhập OAuth) **không** bị xoá. `localStorage` của trang không xoá.
- **Hệ quả**: cookie của nguồn Legado thấy được trong trình duyệt của app; đăng xuất nguồn cũng đăng xuất tên miền đó trong trình duyệt của app. Gieo cookie khi mở vẫn ghi đè cookie trùng tên/tên miền đang có trong kho WebKit (như WebView ẩn).
- Chuyển entry `[1.3.640]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy — cần thử: đăng nhập Google ở trình duyệt của app rồi mở "Đăng nhập trên web" của một nguồn Legado thấy vẫn còn phiên Google; đóng mở lại trình duyệt Legado vẫn còn đăng nhập; Đăng xuất nguồn rồi mở lại thì trang nguồn không còn đăng nhập.

## [1.3.669] - 2026-11-01

### fix: giữ dòng dừng lọc name và điểm tiếp nối khi đổi nguồn

Người dùng: *"Dòng Đã dừng lọc name ở ch.240: Chương 256: Võ đạo đường rẽ cùng mới cảnh giới. Bị mất khi chuyển nguồn truyện"*; chọn "giữ nguyên chỉ số", duyệt plan.

- **Nguyên nhân 1 — mở nhầm phiên**: dòng dừng là một tin trong phiên chat AI. Đổi nguồn tạo `bookId` mới (UUID); `AIChatHistoryStore.migrateSessions` có chép phiên nhưng gán `updatedAt = Date()` lần lượt theo thứ tự mới → cũ ⇒ phiên cũ nhất nhận mốc mới nhất, thứ tự bị đảo. Màn AI của truyện mới (chưa có `lastSessionIds`) mở `summaries.first` = phiên **cũ nhất** ⇒ dòng dừng trông như mất. Phiên chép sang còn giữ `session.bookId` cũ (`let`) ⇒ `condenseHistoricalMessages` lưu nhầm về thư mục của truyện cũ, xoá phiên ở Cài đặt trỏ nhầm thư mục.
- **Sửa**: `migrateSessions` dựng lại phiên với `bookId` mới, giữ `id`, `createdAt`, `updatedAt`. `AIRuntimeCoordinator.migrateLastSession(from:to:)` chuyển phiên lượt gần nhất đã dùng (RAM), gọi từ `SearchView.executeSourceChange`. `condenseHistoricalMessages` lưu theo `bookId` của màn (đỡ cho phiên đã chép trước bản này).
- **Nguyên nhân 2 — mất điểm tiếp nối**: `AINameScanScopeStore` (điểm tiếp nối + lựa chọn "từ chương đang đọc", UserDefaults theo `bookId`) không được chép ⇒ sheet quét mất dòng "Tiếp nối lần quét trước". **Sửa**: `AINameScanScopeStore.migrate(from:to:keepingOld:)` gọi trong `BookSourceMigrator.migrateMetadataAndSettings`; **giữ nguyên chỉ số** (người dùng chọn) vì chương đã tải được chép sang theo vị trí — chỉ số cũ vẫn trỏ ngay sau phần nội dung đã quét. Đang phát TTS truyện cũ thì giữ bản của truyện cũ (như cấu hình dịch).
- **Truyện đã đổi nguồn trước bản này**: không tự khôi phục — thứ tự phiên đã lưu bị đảo, điểm tiếp nối nằm ở id cũ không còn ánh xạ. Dòng dừng vẫn có trong danh sách phiên; quét tiếp bằng "Chọn chương…".
- **Chưa làm**: kết quả AI chưa xem trên hub (`AIUnseenResultStore`), nút "Thử lại k lượt lỗi" (chỉ trong RAM), lượt quét đang chạy lúc đổi nguồn vẫn ghi vào id cũ; chép chương đã tải theo vị trí (có từ trước) có thể lệch tên/nội dung khi hai mục lục khác nhau.
- `rules.md` thêm luật dữ liệu AI theo truyện phải đi theo khi đổi nguồn. Chuyển entry `[1.3.639]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code + diff; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy — cần thử: dừng lọc name → đổi nguồn → mở AI của truyện mới thấy đúng phiên có dòng dừng; sheet quét có "Tiếp nối lần quét trước" và quét tiếp được trên nguồn mới.

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
