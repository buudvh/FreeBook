# CHANGELOG - Nhật ký Thay đổi CodeGraph Tàng Công Các

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **Tàng Công Các**.

## [1.3.873] - 2026-11-11

### feat: mọi sheet và popup dùng nền kính, ô mờ như sheet hub, độ đục thấp nhất 20%

Anh Bửu: "sửa nền các loại sheet như các sheet gần đây", "như hub, nút + kệ sách… hạn chế mức thấp nhất độ đục là 20% nhé", "mấy pop up như bật tắt dịch cũng vậy nhé" (đã duyệt mockup + plan).

- **Modifier dùng chung** (mới, `Views/Common/GlassChrome/AppGlassSheetModifier.swift`): `.appGlassSheet()` (sheet — nền `DrawerGlassSheetBackground`, bo 16), `.appGlassPopover()` (popup), `.appGlassUIKitSheet()` (sheet trình bày bằng UIKit — kính vẽ bằng `.background`); cả ba ẩn nền danh sách, tông tối, đặt environment `isGlassSheet`. `.glassSheetRows()` cho ô danh sách mờ `Color.primary.opacity(0.08)` (màu dòng của sheet hub) — chỉ có tác dụng trong sheet kính (ngoài sheet kính không ghi `listRowBackground` nào, kể cả `nil`) nên trang thường dùng chung view giữ y nguyên, kể cả dòng tự đặt nền riêng; `.glassAwareBackground(_:)` cho nền đặc tự tô trong view dùng chung (thanh tìm của `SearchView`).
- **122 chỗ mở sheet** (khoảng 60 loại) bọc `Group { … }.appGlassSheet()` bằng script có kiểm cân bằng ngoặc. Không gắn: sheet chia sẻ / chọn file của hệ thống, bảng mục lục / cài đặt / tra từ / tìm của Reader và truyện tranh (theo nền đọc), trang đăng nhập web, sheet đã có nền riêng (sheet hub, sheet nghe / TTS, sheet kiểu hub, sheet "đang đọc chương này").
- **114 `List` / `Form`** bọc `Group { … }.glassSheetRows()` dạng gọn (`List { Group {` … `}.glassSheetRows() }`, không thêm dòng — giữ baseline dòng của file legacy). CI lượt đầu đỏ ở hai `List(…) { _, result in` (tham số hai tên nằm dòng dưới `{`, script đặt `Group {` trước tham số) ⇒ sửa tay ở `LegadoCheckReportContent` và `LegadoSourceCheckView`. Bỏ nền đặc tự tô ở `MediaSleepTimerSheet`, `TTSQuickTimerSheet`, `FilterSheet`; ô thông tin `AppUpdateSheet`, thẻ `TTSQuickTimerSheet` và dòng chưa chọn của `DictionaryImportConflictView` dùng màu ô mờ khi ở sheet kính.
- **5 popup** gắn `.appGlassPopover()`: bật tắt dịch (Reader / truyện tranh, Khám phá), "?" giải thích, bảng khiên và bảng chọn tiện ích của nút "Nhập" ở trình duyệt.
- **Màn kiểm tra nguồn mở lại bằng UIKit** (`MinimizedSourceCheckCoordinator.reopen`): kính `.appGlassUIKitSheet()`, hosting trong suốt, bo 16.
- **Độ đục thấp nhất 20%** (`GlassChromeSettings.minimumDrawerFrost` / `effectiveDrawerFrost`): thanh "Độ đục" của Menu ba chấm bắt đầu từ 20%; nền sheet / popup, ngăn kéo `…` và thanh kính trình duyệt kẹp giá trị cũ dưới 20% lên 20%. Giải thích của mục Menu ba chấm ghi rõ mọi sheet / popup dùng chung nền này.
- `CLAUDE.md` / `AGENTS.md`: luật nền kính cho sheet / popup mới.
- **Kiểm chứng:**
  - Đọc code + script kiểm cân bằng ngoặc mọi file sửa. `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 lỗi mới**.
  - **Chưa build** (máy Windows) — CI sẽ biên dịch. **Chưa thử trên máy.**
  - Cần thử: mở các sheet hay dùng (nhấn giữ truyện, tải / xuất, kiểu hiển thị, bộ sưu tập, playlist, bộ lọc tiện ích, cập nhật app, từ điển, cài đặt TTS, hẹn giờ) ⇒ nền kính bo 16, ô mờ, chữ đọc rõ; popup dịch / "?" ⇒ nền kính; Cài đặt › Giao diện › Menu ba chấm › Độ đục thấp nhất 20%; trang Cài đặt thường, Kệ, Playlist, Dung lượng (không phải sheet) giữ y nền cũ — có đổi là lỗi; nền ô có tới được dòng nằm trong `Section` không (không tới ⇒ ô vẫn xám đặc, chỉ là thẩm mỹ).

## [1.3.872] - 2026-11-11

### feat: Từ URL, Thông báo và Kiểm tra nguồn chuyển trang ngay trong sheet như Tác vụ AI

Anh Bửu: "làm cho sheet import từ URL cũng chuyển sheet giống sheet hub vào sheet tác vụ AI", "màn hình thông báo vào kiểm tra nguồn cũng chuyển giống vậy được chứ" (đã duyệt mockup bấm thử + plan).

- **Trang con cho sheet kiểu hub** (`HubStyleActionSheet`): dòng có `page` (`HubStyleActionSheetContent.Page`) ⇒ chạm chuyển trang ngay trong sheet, sheet lên nấc large, tiêu đề giữa + nút ‹ về trang chính (về lại chiều cao vừa nội dung). Đường đóng chung `CloseSheet` (đóng xong mới làm) thay `onSelect`, dùng được cho cả sheet nằm trên viên thuốc lẫn sheet lùi.
- **Nút ‹ trang con dùng chung** (mới, `SheetPageBackButtonModifier`): environment `sheetPageBack` + `.sheetPageBackButton()` gắn bên trong `NavigationStack` của trang; không có hành động ⇒ không có nút (màn dùng chung mở ở chỗ khác vẫn như cũ).
- **Kệ › nút "+" › Từ URL** là trang con trong sheet "Nhập truyện" (`ShelfImportURLStep`, ô link tự focus sau 0,35 s). Chọn tiện ích / mở link trong trình duyệt ⇒ sheet đóng xong mới làm (`ShelfView.runImportChoice`). Bỏ sheet "Nhập từ URL" riêng (`ShelfImportSheet`, `showingImportSheet`, `queuedImportChoice`); lựa chọn tách thành `ShelfImportChoice`.
- **Cửa sổ sheet nhận bàn phím**: `OverlaySheetPresenter` cho cửa sổ phủ nhận key trong lúc có sheet (trước đó không bao giờ key) và trả key cho cửa sổ cũ / cửa sổ chính **trước** khi chạy việc kèm theo. Cửa sổ hub cũng nhận key trong lúc trình bày sheet hub (`FloatingHubWindowManager.setSheetPresented`) để ô nhập / bảng chia sẻ / trình duyệt mở từ trang con nằm đúng cửa sổ.
- **Hub › Thông báo** là trang con lớn của sheet hub (`FloatingHubSheet.Page.notifications`): `NotificationInboxView` + `.modelContainer`, tiêu đề giữa + nút ‹ khi nằm trong sheet. Chạm một truyện ⇒ sheet đóng rồi mở Reader (`openInboxBook`). Bỏ sheet UIKit riêng `presentInbox` / `openReader` / delegate vuốt-để-đóng. "Mở thẳng khi chỉ có 1 tác vụ" lúc 0 tác vụ ⇒ sheet mở ở trang Thông báo.
- **Hub › Kiểm tra nguồn** (một lượt, hoặc chọn một trong hai lượt) là trang con lớn (`.sourceCheck`): màn kiểm tra gắn vào lượt đang thu nhỏ dựng qua `MinimizedSourceCheckCoordinator.embeddedPage` / `embeddedScreen`, tiêu đề giữa; nút ‹ thay ⌄ (`SourceCheckHeaderButtons` thôi vẽ ⌄ trong trang con) ⇒ `screenDidClose` rồi về trang chính; vuốt đóng sheet khi đang ở trang này cũng thu nhỏ lượt (`FloatingHubSheetState.didDismiss`). Lượt vẫn chạy nền như trước.
- `CLAUDE.md` / `AGENTS.md` + `rules.md` (hub (b), (f), luật 25, cửa sổ sheet phủ): luật mới về trang con và nhận key.
- **Kiểm chứng:**
  - Đọc code. `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 lỗi mới**.
  - **Chưa build** (máy Windows) — CI sẽ biên dịch. **Chưa thử trên máy.**
  - Cần thử: Kệ › "+" › Từ URL ⇒ sheet lớn lên, bàn phím hiện, gõ / dán link, chọn tiện ích ⇒ mở Chi tiết; ‹ về ba dòng. Hub › Thông báo ⇒ trang lớn, ‹ về, chạm truyện ⇒ mở Reader, ngăn kéo … của trang vẫn chạy. Hub › Kiểm tra nguồn khi đang có lượt chạy ⇒ trang lớn theo dõi tiến độ, ‹ về thì dòng hub vẫn "đang chạy", vuốt đóng sheet cũng vậy, Dừng vẫn dừng; mở link lỗi / chia sẻ báo cáo từ trang này hiện trên sheet.

## [1.3.871] - 2026-11-11

### feat: mỗi viên thuốc nổi có độ trong suốt, độ đục và độ nhô riêng, nhô tối thiểu còn bán nguyệt

Anh Bửu: "thêm config độ nhô ra các loại viên thuốc", "làm độ trong suốt riêng luôn", "độ đục riêng luôn", "mỗi viên thuốc có độ trong suốt và đục riêng, nhấp nháy cũng theo trong suốt và đục. Cho độ rộng tối thiểu còn hình bán nguyệt" (đã duyệt mockup kéo thử + plan).

- **Cài đặt riêng từng viên** (mới, `Views/Common/GlassChrome/EdgePillSettings.swift`): đĩa nghe, hub, nút trình duyệt thu nhỏ — mỗi viên ba khoá `edgePill<Disc|Hub|Browser><Transparency|Frost|Width>` (không dấu chấm): độ trong suốt (mặc định 90%), độ đục (6 nấc `GlassFrostLevel`, mặc định không nhoè), độ nhô (đĩa 26–84 pt mặc định 68; hub / trình duyệt 18–50 pt mặc định 38; bước 2; tối thiểu = nửa chiều cao ⇒ bán nguyệt). Độc lập với "Nút nổi" (nút "+", tai nghe Reader giữ nguyên). Ai đã chỉnh "Nút nổi" khác mặc định thì viên thuốc về mặc định tới khi chỉnh ở mục mới.
- **Cài đặt › Chung › Giao diện › Viên thuốc nổi** (`EdgePillSettingsSection`, ngay dưới "Nút nổi"): thanh phân đoạn Đĩa nghe / Hub / Trình duyệt, ba thanh kéo của viên đang chọn, "Đặt lại <viên>", công tắc "Xem thử nháy đỏ" và ô xem trước vẽ cả ba viên.
- **Hình** `EdgePillShape`: vẽ tay bằng cung tiếp tuyến, bán kính = nửa chiều cao ⇒ đúng tới bán nguyệt (bỏ `UnevenRoundedRectangle` và hai hằng `largeSize` / `smallSize`; `contentInset(height:content:)`, `contentPadding(for:)`). Bìa / icon gắn bằng `overlay` đồng tâm đầu bo ⇒ viên hẹp thì lọt ra ngoài mép, không đẩy khung kính.
- **Kính + độ mờ**: `FloatingGlassBackground(shape:pill:)` và `.floatingIconTransparency(pill:)` đọc khoá của viên; `MediaDiscFaceButton`, `FloatingHubButton`, `VisibleBrowserReopenButton` dùng cài đặt riêng của mình.
- **Nháy đỏ theo trong suốt + đục**: màu nháy có alpha `1 − trong suốt` của viên, nằm trên lớp kính (độ đục) — hub (`FloatingHubPulseView`: alpha của màu trong `CABasicAnimation`, đổi alpha ⇒ gắn lại cùng pha; layer nháy cắt bằng mặt nạ `EdgePillShape` thay `cornerRadius`) và nút trình duyệt. Không đổi opacity của view. Số tab của nút trình duyệt vẫn rõ.
- **Đổi ngay khi kéo**: độ nhô đọc lúc chạy (`EdgePillSettings.size(of:)`); container đĩa / hub / trình duyệt nghe `UserDefaults.didChangeNotification` ⇒ tính lại khung (đang kéo bằng tay thì để lượt thả tự đặt).
- `CLAUDE.md` / `AGENTS.md` + `rules.md` (hub (a): luật mới thay "nền nháy giữ rõ"; sửa câu cũ "sheet hub mở thì nút đã giấu" — từ 1.3.866 nút vẫn hiện).
- **Kiểm chứng:**
  - Đọc code. `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 lỗi mới**.
  - **Chưa build** (máy Windows) — CI sẽ biên dịch. **Chưa thử trên máy.**
  - Cần thử: Giao diện › Viên thuốc nổi, kéo từng thanh của từng viên ⇒ viên thật (đang hiện) và ô xem trước đổi ngay; độ nhô nhỏ nhất ⇒ bán nguyệt, bìa / icon ló nửa; kéo / thả viên vẫn bám mép đúng; hub đang nháy ⇒ đỏ mờ theo trong suốt, thấy nhoè khi tăng độ đục; "Đặt lại" chỉ đặt lại viên đang chọn.

## [1.3.870] - 2026-11-11

### feat: nút + của Kệ sách mở sheet Nhập truyện kiểu hub, Từ URL thành sheet riêng

Anh Bửu: "sửa sheet nút + của kệ cũng giống hub luôn, hiện tại chưa giống" (đã duyệt mockup + plan).

- **Sheet "Nhập truyện" kiểu hub** (`ShelfView.presentImportSheet`, dùng `.hubStyleActionSheet` của 1.3.869) cho nút "+" nổi tab Kệ sách và hàng "Nhập truyện" của ngăn kéo: ba dòng dạng ô có `›` — Từ URL ("Dán link, chọn nguồn khớp"), Mở trình duyệt ("Trang chủ trình duyệt"), Từ file ("txt, epub, cbz, mp4…"). Nằm trên mọi viên thuốc; chạm dòng ⇒ sheet đóng xong mới làm. Thay danh sách `insetGrouped` cũ (nấc 300 / large).
- **"Từ URL"** ⇒ sheet **"Nhập từ URL"** riêng ở cửa sổ chính (`ShelfImportSheet` giờ chỉ bọc `ShelfImportURLStep`, nấc large, tiêu đề trái) — cửa sổ sheet phủ không bao giờ key nên không đặt ô nhập chữ ở đó. Dò ra tiện ích / mở link trong trình duyệt vẫn qua `queuedImportChoice` + `onDismiss` như cũ. Bỏ lựa chọn `pickFile` (Từ file chạy thẳng từ sheet kiểu hub).
- `CLAUDE.md` / `AGENTS.md`: luật sheet trên viên thuốc ghi thêm sheet của Kệ. `rules.md` (mục hub + luật 25): thêm cửa sổ `OverlaySheetWindow` (`alert - 1.6`) và sửa câu cũ "`alert - 3` không còn cửa sổ nào dùng" (nút trình duyệt thu nhỏ vẫn ở level này).
- **Kiểm chứng:**
  - Đọc code. `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 lỗi mới**.
  - **Chưa build** (máy Windows) — CI sẽ biên dịch. **Chưa thử trên máy.**
  - Cần thử: tab Kệ sách ⇒ "+" ⇒ sheet ba dòng nằm trên đĩa nghe / hub; Từ URL ⇒ sheet "Nhập từ URL" lên, gõ được (bàn phím hiện), dán link ⇒ mở Chi tiết; Mở trình duyệt ⇒ trang chủ trình duyệt; Từ file ⇒ bộ chọn file; ngăn kéo … › Nhập truyện ⇒ cùng sheet.

## [1.3.869] - 2026-11-11

### feat: nút + của Chi tiết truyện mở sheet kiểu hub thay cho cụm pill xổ lên

Anh Bửu: "để cho nút + ở chi tiết sẽ mở ra sheet như sheet hub vậy" (đã duyệt mockup + plan).

- **Sheet hành động kiểu hub** dùng chung (mới, `Views/Common/HubStyleSheet/`): `HubStyleActionSheetContent` (tiêu đề + chú thích phải + các dòng: icon, tên, dòng phụ, màu icon, `›`, việc làm), `HubStyleActionSheet` (khuôn sheet hub: nền kính ngăn kéo, bo 16, cao vừa nội dung, vuốt xuống để đóng, nền tối), `HubStyleActionSheetRow` (khuôn dòng của sheet hub: ô bo góc `hubSheetPanelRow`, cao 56) và `.hubStyleActionSheet(_:)` — trình bày qua `OverlaySheetPresenter` ⇒ nằm **trên** mọi viên thuốc; chạm dòng ⇒ sheet đóng xong mới làm việc; không trình bày được ⇒ lùi về sheet thường của màn (log `[HubStyleSheet]`).
- **Chi tiết truyện** (`BookDetailFloatingActions`): nút "+" là nút tròn thường, chạm ⇒ sheet: dòng đầu tên truyện (bản đang hiện) + "Ch. N/tổng" (truyện chưa lưu ⇒ "N chương"); Đọc ngay / Đọc tiếp (Đọc tiếp kèm tên chương sẽ mở, cùng luật tên chương của tab Mục lục), Thêm vào kệ / Đã ở kệ (icon xanh, "Chạm để bỏ khỏi kệ"), Tải, Xuất, "Về trang gốc" dưới cùng khi trang có Home. Thuộc tính `floatingActionButton` chuyển sang `BookDetailView+FloatingActions` (file legacy ngắn đi 23 dòng).
- `OverlaySheetPresenter.dismiss(then:)`: chạm dòng thứ hai lúc sheet đang trượt xuống ⇒ bỏ qua (trước đó việc chạy luôn ⇒ hai lần). Việc kèm theo khai `@MainActor () -> Void` (cùng kiểu `action` của dòng — tránh lỗi đổi hàm mất actor khi biên dịch); `HubStyleActionSheetModifier` gắn `@MainActor`.
- `CLAUDE.md` / `AGENTS.md`: mục Nút Home nổi + luật sheet trên viên thuốc.
- **Kiểm chứng:**
  - Đọc code. `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 lỗi mới**.
  - **Chưa build** (máy Windows) — CI sẽ biên dịch. **Chưa thử trên máy.**
  - Cần thử: Chi tiết truyện đã lưu ⇒ "+" ⇒ sheet có tên + "Ch. N/tổng", "Đọc tiếp" có tên chương; chạm từng dòng (đọc, bỏ / thêm kệ, tải, xuất, về trang gốc) ⇒ sheet đóng rồi làm đúng việc; đĩa nghe / hub vẫn thấy dưới lớp tối của sheet; truyện chưa lưu ⇒ "N chương", "Đọc ngay"; Chi tiết mở trong Reader ⇒ không có dòng "Về trang gốc".

## [1.3.868] - 2026-11-11

### feat: sheet đang đọc chương này nằm trên mọi viên thuốc thay vì ẩn đĩa nghe

Anh Bửu: "Sheet 'đang đọc chương này' hiển thị đừng có ẩn nửa viên thuốc, cho nó dưới sheet thôi, cho luôn nửa viên thuốc hub ở dưới sheet luôn… mọi sheet mở ra từ viên thuốc đều không ẩn các viên thuốc mà chỉ hiển thị cao hơn viên thuốc thôi, tránh trường hợp mở sheet từ viên thuốc rồi lại mở sheet mới khác từ viên thuốc đè lên" (đã duyệt mockup + plan).

- **Cửa sổ sheet phủ** (mới, `Views/Common/OverlaySheet/`): `OverlaySheetPresenter` + `OverlaySheetWindow` (level `alert − 1.6`: trên đĩa nghe `− 1.75`, hub `− 2` / `− 1.7`, nút trình duyệt `− 3`; dưới ngăn kéo `…` `− 1.5` và toast) + `OverlaySheetHost` (view 1×1 giữ `.sheet`, khuôn `MediaDiscSheetHost`). Cửa sổ chỉ hiện lúc có sheet, không bao giờ key, hit-test chỉ nhận chạm khi đang trình bày (luật 25); `onDismiss` là đường đóng chung (luật 26); `dismiss(then:)` đóng sheet **xong** mới chạy việc kèm theo. Sheet của cửa sổ chính luôn nằm dưới các cửa sổ viên thuốc nên đây là cách duy nhất để một sheet che được chúng.
- **Sheet "đang đọc chương này" của Reader** trình bày qua cửa sổ này (vỏ `ReaderTTSSameChapterPromptHost`: tự giữ chiều cao + tự đọc "đang phát" qua `TTSWidgetStateReader`) ⇒ đĩa nghe, hub, nút trình duyệt, cửa sổ phim nhỏ nằm dưới lớp mờ của sheet, **không bị ẩn**, không bấm được để mở chồng sheet. Bỏ neo `.blocker` của sheet này. Không trình bày được (đang có sheet phủ khác / chưa có scene) ⇒ lùi về sheet thường của Reader như cũ.
- Sheet của chính đĩa nghe và sheet hub / màn Thông báo vốn đã nằm trên mọi viên thuốc (cửa sổ của chúng) — giữ nguyên.
- `CLAUDE.md` / `AGENTS.md`: đoạn đĩa nghe thêm luật "sheet nằm trên mọi viên thuốc".
- **Kiểm chứng:**
  - Đọc code. `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 lỗi mới**.
  - **Chưa build** (máy Windows) — CI sẽ biên dịch. **Chưa thử trên máy.**
  - Cần thử: đang nghe truyện, bấm tai nghe trúng chương đang đọc ⇒ sheet hiện, đĩa nghe + hub vẫn thấy mờ dưới lớp tối; chọn "Đọc tiếp chỗ đang đọc" / "Đọc từ đoạn đang xem" / "Đọc lại từ đầu chương" ⇒ Reader làm đúng như cũ; vuốt sheet xuống ⇒ không làm gì, đĩa vẫn ở đó.

## [1.3.867] - 2026-11-11

### feat: viên thuốc nổi đứng trong vùng cố định, luôn tránh header và thanh tab để không nhảy khi đổi màn

Anh Bửu: "để cho viên thuốc tự tránh header và thanh tab dù có hay không luôn, tránh nó chạy lên chạy xuống" (đã duyệt mockup + plan). Áp cho cả ba viên: đĩa nghe, nút hub, nút trình duyệt thu nhỏ.

- `EdgePillZone` (mới, `Views/Common/GlassChrome/`): vùng đứng cố định — mép trên ≥ vùng an toàn trên + 52 (header 44 + 8), mép dưới ≤ vùng an toàn đáy − 76 (= khe 12 + nút "+" 52 + khe 12). iPhone 15: 111…742 pt ⇒ luôn trên thanh tab (769), nút "+" (754), thanh dưới trình duyệt (766), nút tai nghe Reader (750) — **kể cả màn không có chúng**, nên đổi tab / đẩy trang / mở sheet không làm viên thuốc lên xuống. Chỗ người dùng kéo tới vẫn lưu nguyên; vùng chỉ kẹp lúc vẽ và lúc thả.
- **Đĩa nghe** (`MediaDiscPlacement`): dải dọc lấy từ `EdgePillZone`; chỉ neo / cửa sổ phim nhỏ **lấn vào vùng** (mép trên cao hơn đáy vùng — cụm pill của menu "+" đang xổ ở màn danh sách có Home, cửa sổ phim nhỏ kéo lên) chồng cột mới tạm đẩy đĩa lên. Nút "+", Home, tai nghe, thanh tab, thanh dưới không còn đẩy đĩa (trước đây đẩy theo từng màn ⇒ nhảy).
- **Nút hub, nút trình duyệt**: lề trên / dưới đổi từ 12 pt quanh vùng an toàn sang `EdgePillZone` (kẹp lúc vẽ, lúc giữ chỗ với widget khác, lúc thả tay) ⇒ không còn kéo lên được header hay xuống đè thanh tab / thanh dưới. Bỏ hằng `verticalMargin`.
- `CLAUDE.md` / `AGENTS.md`: câu chỗ đứng của đĩa, câu thanh tab 4 ô, câu "Cùng khuôn" của hub / trình duyệt.
- **Kiểm chứng:**
  - Đọc code. `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 lỗi mới**.
  - **Chưa build** (máy Windows) — CI sẽ biên dịch. **Chưa thử trên máy.**
  - Cần thử: đang nghe, đi qua lại trang gốc Kệ (thanh tab + "+") ⇄ trang đẩy vào (không thanh tab) ⇄ Reader ⇒ đĩa đứng yên một chỗ. Kéo hub / nút trình duyệt lên sát đỉnh ⇒ dừng dưới header; kéo xuống đáy ⇒ dừng trên thanh tab. Ở màn danh sách có "+" kèm Home, bấm "+" xổ menu ⇒ đĩa mép phải né lên, đóng menu ⇒ về chỗ.

## [1.3.866] - 2026-11-11

### feat: mở sheet hub không ẩn nút hub, giống đĩa nghe mở sheet nghe

Anh Bửu: "Khi mở sheet mở rộng từ widget hub thì đừng ẩn các widget khác (làm giống như widget đĩa mở sheet nghe nhạc/nghe truyện mini)" (đã duyệt).

- Kiểm lúc sheet hub / màn Thông báo mở (sau 1.3.865): nửa viên đĩa nghe, nút trình duyệt thu nhỏ, cửa sổ phim nhỏ đều vẫn hiện; **chỉ nút hub** bị giấu (`setSheetPresented(true)` đặt `widgetContainerView.isHidden = true`, `refreshState` giữ giấu suốt lúc sheet mở).
- `FloatingHubWindowManager`: thôi giấu nút khi sheet mở — nút nằm yên dưới sheet (sheet trình bày trong cùng cửa sổ hub, đè lên nút; lớp mờ của sheet chặn chạm), y như đĩa nghe dưới sheet điều khiển nhanh của nó. Vẫn giữ: phim toàn màn mà sheet còn mở ⇒ giữ cửa sổ, chỉ giấu nút (`hideWidget()` sẽ cuốn mất sheet). Level cửa sổ hub lúc trình bày sheet giữ như 1.3.865 (`alert − 1.7`, trên cửa sổ đĩa).
- `rules.md` luật hub (b), `CLAUDE.md` / `AGENTS.md` đoạn đĩa nghe: ghi nút hub không ẩn lúc sheet hub mở.
- **Kiểm chứng:**
  - Đọc code. `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 lỗi mới**.
  - **Chưa build** (máy Windows) — CI sẽ biên dịch. **Chưa thử trên máy.**
  - Cần thử: chạm hub ⇒ sheet hub mở, nút hub (và nửa viên, nút trình duyệt nếu có) vẫn thấy mờ phía sau lớp tối; chạm vùng tối ⇒ sheet đóng, không mở lại hub; chạm Thông báo ⇒ màn Thông báo, đóng ⇒ nút hub vẫn đúng chỗ.

## [1.3.865] - 2026-11-11

### feat: bỏ ô đĩa giữa thanh tab, nửa viên đĩa nghe hiện ở mọi màn và sheet

Anh Bửu: "Bỏ luôn tab thứ 5 hiển thị đĩa đi, mọi màn hình, sheet đều hiển thị viên thuốc cho tôi" (đã duyệt plan; sheet "đang đọc chương này" của Reader anh chọn giữ ẩn đĩa như cũ).

- **Thanh tab 4 ô** (`MainTabBar`): Kệ Sách · Khám Phá · Tiện Ích · Cài Đặt. Xoá `MediaDiscTabBarSlot`, `MediaDiscIdleFace` (đĩa xám), kiểu `.tabBar` của `MediaDiscFaceButton` (nay chỉ còn mặt nửa viên, `MediaDiscFaceButton()`), vai neo `.hostsDisc`.
- **Trang gốc các tab có nửa viên**: thanh tab là neo `.bar` (`MainTabBarModifier`) ⇒ nửa viên đè lên thanh thì tự đứng trên nó 12 pt.
- **Đổi màn ⇒ đĩa đứng yên**: bỏ luật "trang đổi ⇒ thu đĩa tại chỗ, hiện lại sau 0,3 s" (1.3.820, theo `MediaDiscScreenContext.page`). Đang chuyển cảnh vẫn đứng yên; hết chuyển cảnh mà màn mới có neo cần né thì trượt tới chỗ mới. Đĩa đang ẩn (bàn phím, phim…) vẫn chỉ hiện lại khi điều kiện giữ đủ 0,3 s.
- **Sheet hub / màn Thông báo không ẩn đĩa nữa** (thay cách ẩn của 1.3.864): `FloatingHubWindowManager.setSheetPresented` nâng cửa sổ hub từ `alert − 2` lên `alert − 1.7` (trên cửa sổ đĩa `alert − 1.75`) lúc trình bày sheet ⇒ sheet đè lên nửa viên như sheet của chính đĩa; đóng sheet thì hạ về để nút hub nằm dưới sheet điều khiển nhanh của đĩa.
- **Vẫn ẩn đĩa** khi: không có gì đang phát, bàn phím hiện, màn nghe nhạc mở, phim toàn màn / màn xem phim, hộp thoại / bảng chọn / bảng chia sẻ, sheet "đang đọc chương này" của Reader (`ReaderTTSSameChapterSheet`, neo `.blocker`). Mọi sheet khác của cửa sổ chính nằm dưới nửa viên (đĩa có thể che mép hàng của sheet — kéo đi chỗ khác).
- `CLAUDE.md` / `AGENTS.md`: đoạn "Hai chỗ đặt đĩa" ⇒ "Một chỗ đặt đĩa", đoạn đĩa nghe (neo `.bar` ở thanh tab, sheet hub). `rules.md`: level cửa sổ hub, luật widget TTS bỏ "ô giữa thanh tab".
- **Kiểm chứng:**
  - Đọc code + grep chéo `MediaDiscTabBarSlot` / `MediaDiscIdleFace` / `hostsDisc` / `MediaDiscFaceButton(style:` (không còn chỗ gọi). `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 lỗi mới**.
  - **Chưa build** (máy Windows) — CI sẽ biên dịch. **Chưa thử trên máy.**
  - Cần thử:
    1. Thanh tab còn 4 ô, chia đều. Đang nghe ⇒ ở trang gốc Kệ Sách có nửa viên, đứng trên thanh tab (và trên nút "+" nếu có).
    2. Đẩy trang / mở Reader / quay lại ⇒ nửa viên không thu lại rồi hiện lại; chỉ trượt khi phải né nút.
    3. Chạm hub ⇒ sheet hub đè lên nửa viên, bấm được mọi dòng; đóng sheet ⇒ nửa viên vẫn ở đó.
    4. Mở một sheet bất kỳ (Cài đặt Reader, mục lục…) ⇒ nửa viên vẫn hiện trên sheet.
    5. Bấm tai nghe trúng chương đang đọc ⇒ sheet "đang đọc chương này" hiện, nửa viên ẩn như cũ.

## [1.3.864] - 2026-11-11

### fix: ẩn đĩa nghe khi sheet hub hoặc màn Thông báo của hub đang mở

Rà lại đợt nút nổi nửa viên (1.3.858–863) thấy: cửa sổ hub ở `alert − 2`, **thấp hơn** cửa sổ đĩa nghe (`alert − 1.75`). Sheet hub (1.3.862) và màn Thông báo trình bày từ cửa sổ hub nên nằm **dưới** nửa viên đĩa nghe — đĩa đè lên mấy dòng cuối của sheet và cướp chạm (đúng chỗ ⏸ / ✕ của dòng Video khi đĩa ở chỗ mặc định). `MediaDiscPlacement` chỉ xét tầng trên cùng của cửa sổ **chính** nên không thấy sheet đó. Màn Thông báo vốn đã bị vậy; sheet hub làm nó xảy ra mỗi lần chạm hub.

- `MediaDiscWindowManager.isDiscAllowed` thêm điều kiện `!FloatingHubWindowManager.shared.isSheetPresented` ⇒ sheet hub / màn Thông báo mở thì đĩa thu lại, đóng thì hiện lại (luồng hiện chậm 0,3 s như cũ).
- `FloatingHubWindowManager.setSheetPresented` gọi `MediaDiscWindowManager.shared.refreshState()` ⇒ đĩa thu ngay, không chờ lượt hỏi 0,4 s.
- Ô đĩa ở giữa thanh tab (cửa sổ chính) không đổi — nó nằm dưới cửa sổ hub nên sheet tự che.
- `CLAUDE.md` / `AGENTS.md`: thêm điều kiện ẩn này vào đoạn đĩa nghe.
- **Kiểm chứng:**
  - Đọc code. `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 lỗi mới**.
  - **Chưa build** (máy Windows). **Chưa thử trên máy.**
  - Cần thử: đang nghe nhạc (nửa viên ở mép phải) ⇒ chạm hub ⇒ nửa viên thu lại, bấm được ⏸ / ✕ dòng Video; vuốt sheet xuống ⇒ nửa viên hiện lại. Tương tự với màn Thông báo.

## [1.3.863] - 2026-11-11

### feat: icon nút nổi mờ theo độ trong suốt như nền kính

Anh Bửu hỏi "hình như icon của các nút nổi chưa làm mờ theo cài đặt đúng không?" — đúng: trước đây "Độ trong suốt" chỉ áp vào nền kính và bìa đĩa nghe. Anh chốt: "Mờ, pill menu rõ".

- `FloatingIconTransparencyModifier` (mới, `Views/Common/GlassChrome/`, `.floatingIconTransparency()`): icon mờ đúng số `1 − độ trong suốt`, không sàn — cùng luật bìa đĩa nghe và icon nút hub / nút trình duyệt. Gắn lên **icon**, không lên nút (mờ lớp cha của kính là tắt nhoè).
- Áp ở `FloatingRoundButton` (nút "+", Home nổi, nút bật menu xổ, Home ở Chi tiết), nút tai nghe Reader (`readerEdgeButton`) và ô xem trước nút nổi ở Cài đặt › Giao diện (kéo thanh là thấy ngay). **Không** áp cho pill của menu xổ (`FloatingActionMenu`).
- Hệ quả đã báo anh: mặc định trong suốt 90% ⇒ dấu "+" / Home / tai nghe chỉ còn hiện 10%; muốn rõ thì kéo thanh "Độ trong suốt" xuống.
- `CLAUDE.md` / `AGENTS.md`: câu icon mờ ở đoạn "Nút Home nổi". Chuyển 6 mục CHANGELOG cũ nhất (1.3.828–833) sang `CHANGELOG.archive.md`.
- **Kiểm chứng:**
  - Đọc code. `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 lỗi mới**.
  - **Chưa build** (máy Windows). **Chưa thử trên máy.**
  - Cần thử:
    1. Cài đặt › Giao diện kéo "Độ trong suốt" 0% ↔ 100% ⇒ icon ô xem trước rõ ↔ trong hẳn.
    2. Màn danh sách có "+" ⇒ icon "+" mờ theo; bấm "+" ⇒ pill "Thêm" / "Home" vẫn rõ.
    3. Reader ⇒ icon tai nghe mờ theo.

## [1.3.862] - 2026-11-11

### feat: chạm hub mở sheet như sheet nghe thay cho thẻ menu

Anh Bửu: "chuyển popup khi bấm vào hub thành dạng sheet như sheet tts và nghe" (đã duyệt mockup). Thẻ menu nổi cạnh nút hub + lớp nền trong suốt nuốt chạm toàn màn được thay bằng **sheet hub**.

- **Sheet** `FloatingHubSheet` (mới): nền kính tối theo cài đặt ngăn kéo (`DrawerGlassSheetBackground`), bo 16, cao vừa nội dung (đo chiều cao như `AudioQuickControlSheet`), thanh kéo, vuốt xuống để đóng — không nút đóng. Trang chính: dòng đầu "Lối tắt nổi" + "N đang chạy", **bốn dòng cố định** AI → Thông báo → Video → Kiểm tra nguồn dạng ô bo góc (`hubSheetPanelRow`), dòng xám mờ 40% không biến mất, dòng Video giữ ⏸ / ✕ (sheet không đóng), các dòng khác có ›. Trang con "Tác vụ AI" / "Kiểm tra nguồn" (hai lượt) nằm trong sheet với nút ‹, danh sách rỗng ⇒ tự về trang chính.
- **Chỗ giữ sheet** `FloatingHubSheetHost` (view 1×1 trong cửa sổ hub, khuôn `MediaDiscSheetHost`) + trạng thái `FloatingHubSheetState`. Sheet mở ⇒ `setSheetPresented(true)` (giữ cửa sổ, giấu nút). Mọi đường đóng đi qua `onDismiss` ⇒ báo `false` trước, rồi mới chạy việc kèm theo (`dismiss(then:)`): màn Thông báo / AI / phim / màn kiểm tra mở **sau** khi sheet đóng xong.
- `+Actions`: `open(_:)`, `openAITask`, `openSourceCheck`, `activateByRunningTasks` dùng sheet (AI / hai lượt kiểm tra ⇒ trang con). Cài đặt "Khi chạm hub" giữ nguyên ý: "Luôn hiện tất cả mục" ⇒ sheet trang chính; "Mở thẳng khi chỉ có 1 tác vụ" ⇒ như cũ, chỗ trước mở menu nay mở sheet.
- **Xoá** `FloatingHubMenuView`, `FloatingHubContainerViewController+Menu`, `menuBackdropView` / `menuContainerView`, cờ `isMenuOpen` và mọi `closeMenu` ở `FloatingHubWindowManager`; `FloatingHubUIWindow.hitTest` còn hai nhánh (sheet đang trình bày ⇒ cả cửa sổ; còn lại chỉ khung nút).
- `FloatingHubMenuRow`, `FloatingHubAITaskListView`, `FloatingHubSourceCheckListView`: đổi sang kiểu ô của sheet (cao 56, không vạch ngăn, tiêu đề trang con 17 pt). Chữ cài đặt "Khi chạm hub" đổi "menu" ⇒ "sheet".
- `rules.md`: viết lại luật hub (a) (nửa viên dính mép), (b) (sheet thay menu + cờ / thứ tự đóng), (e), (f), thứ tự `hitTest`. `CLAUDE.md` / `AGENTS.md`: câu sheet hub ở đoạn đĩa nghe.
- **Kiểm chứng:**
  - Đọc code + grep chéo `isMenuOpen` / `closeMenu` / `openMenu` / `FloatingHubMenuView` (không còn chỗ gọi). `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 lỗi mới**.
  - **Chưa build** (máy Windows). **Chưa thử trên máy.**
  - Cần thử:
    1. Chạm hub ⇒ sheet bốn dòng; vuốt xuống ⇒ đóng, nút hub hiện lại.
    2. Chạm Thông báo ⇒ sheet hub đóng rồi màn Thông báo mở; đóng màn Thông báo ⇒ nút hub hiện lại.
    3. Có AI đang chạy ⇒ chạm Trợ lý AI ⇒ trang "Tác vụ AI" trong sheet, ‹ quay lại; chạm truyện ⇒ màn AI của truyện đó.
    4. Phim thu nhỏ vào hub ⇒ dòng Video ⏸ đổi glyph ngay, ✕ dừng phim, chạm dòng ⇒ mở lại màn xem.
    5. Cài đặt "Mở thẳng khi chỉ có 1 tác vụ" + 1 AI đang chạy ⇒ chạm hub mở thẳng trang "Tác vụ AI".

## [1.3.861] - 2026-11-11

### feat: nút hub và nút trình duyệt thu nhỏ thành nửa viên thuốc nhỏ dính mép

Anh Bửu duyệt mockup ("hub và browser viên nhộng nhỏ thôi", "ngắn lại chút nữa, phần icon cũng phải theo độ trong suốt"): nút hub và nút mở lại trình duyệt thu nhỏ đổi từ nút tròn 36 px nép mép sang **nửa viên 38 × 36** cùng khuôn `EdgePillShape` với đĩa nghe.

- **Hình** (`FloatingHubButton`, `VisibleBrowserReopenButton`): nền kính `FloatingGlassBackground(shape:)` theo Độ trong suốt / Độ đục của nút nổi (thay `.ultraThinMaterial` + bóng đổ); icon 17 pt trắng đồng tâm đầu bo (cách mép 20 pt), **mờ đúng số** theo Độ trong suốt như bìa đĩa nghe. Nền nháy đỏ (hub có việc / tab thu nhỏ quá 10 s) và badge số tab **giữ rõ**. Badge số tab ở góc trên của icon, không còn lật phía / thu thành chấm.
- **Luôn dính mép**: bỏ hai trạng thái nép mép nửa ẩn (`.peeking`, mờ 0,5 ở hub) / bung vào trong màn (`.revealed`) và hẹn giờ tự thu 3 s (`FloatingHubViewModel`, `VisibleBrowserReopenViewModel`); bỏ độ mờ 0,7 cố định khi nghỉ của nút trình duyệt (`setTouchActive` + `sendEvent` của `BrowserFloatingWidgetUIWindow`). `WidgetMode` và `FloatingWidgetGeometry.restingCenterX` hết người dùng ⇒ xoá.
- **Kéo**: bắt đầu kéo ⇒ co tròn 36 đặt đúng tâm icon, theo tay; thả ⇒ bám mép gần hơn, kẹp dọc như cũ, né widget nổi khác cùng mép (`FloatingWidgetLayoutCoordinator`, chiều cao 36), lưu vào khoá cũ (`floatingHub*`, `visibleBrowserReopen*`).
- `FloatingHubPulseView`: thêm `edge` ⇒ layer nháy chỉ bo hai góc phía đầu bo (`maskedCorners`). Chạm hub vẫn mở thẻ menu như cũ (đổi sang sheet ở commit sau); `+Actions` bỏ các lệnh "thu về nép mép". Viền sáng của hub khi kéo cửa sổ phim nhỏ tới bo theo cạnh ngắn.
- `CLAUDE.md` / `AGENTS.md`: câu "Cùng khuôn" ở đoạn đĩa nghe. `rules.md` mục nút hub sửa ở commit sheet hub ngay sau.
- **Kiểm chứng:**
  - Đọc code + grep chéo `WidgetMode` / `mode` / `reveal` / `setTouchActive` (không còn chỗ gọi). `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 lỗi mới**.
  - **Chưa build** (máy Windows). **Chưa thử trên máy.**
  - Cần thử:
    1. Hub và nút trình duyệt (thu nhỏ trình duyệt có 3 tab) hiện thành nửa viên nhỏ dính mép, icon mờ theo thanh "Độ trong suốt".
    2. Kéo mỗi nút sang mép kia ⇒ bám mép đúng độ cao; mở lại app vẫn ở đó.
    3. Hub có việc ⇒ nền nháy đỏ đúng hình nửa viên; trình duyệt thu nhỏ quá 10 s ⇒ nháy đỏ.
    4. Chạm hub ⇒ menu; chạm nút trình duyệt ⇒ mở lại trình duyệt.
    5. Kéo cửa sổ phim nhỏ tới hub ⇒ hub phóng to + viền màu nhấn; thả ⇒ vào hub.

## [1.3.860] - 2026-11-11

### feat: sheet nghe truyện thêm nút chương trước và chương kế ở hai đầu

Anh Bửu duyệt mockup: sheet điều khiển nhanh TTS (mở từ đĩa nghe) có thêm hai nút đổi chương ở hai đầu ngoài cùng của hàng nút.

- Hàng nút `TTSQuickControlSheet.transportRow`: **chương trước** · đoạn trước · ⏯ · đoạn kế · **chương kế**, chia đều bằng `Spacer` như `AudioTransportControls(.full)` của sheet nhạc. Nút chương icon `backward.end.fill` / `forward.end.fill` 20 pt (khác nút đoạn `backward.fill` / `forward.fill` 22 pt), trắng 85%, khung 44 pt; không có chương đó ⇒ mờ 35%, tắt.
- `TTSManager+ChapterStep` (mới): `previousChapterIndex(before:)` + `jumpToAdjacentChapter(forward:)` — tra chương liền trước / sau theo `index` thưa trong `chaptersQueue` (cùng luật `nextChapterIndex(after:)`), rồi `jumpToChapter(at:)` có sẵn (toast "Đang chuyển sang …", đọc từ đầu chương).
- `TTSWidgetBarInfoReader`: thêm `hasPreviousChapter` / `hasNextChapter`, tính lại khi đổi chương và khi số chương trong hàng đợi đổi. Sheet không observe `TTSManager` trực tiếp.
- Giới hạn đã biết: vừa bấm tai nghe ở Reader, hàng đợi chỉ có vài chương từ chương đang đọc trở đi cho tới khi `refreshChaptersQueueInBackground` nạp đủ (~1 s) ⇒ "chương trước" mờ trong lúc đó.
- `CLAUDE.md` / `AGENTS.md`: thêm câu hàng nút sheet vào đoạn "Widget TTS chỉ một kiểu".
- **Kiểm chứng:**
  - Đọc code. `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 lỗi mới**.
  - **Chưa build** (máy Windows). **Chưa thử trên máy.**
  - Cần thử:
    1. Đang nghe chương 128 ⇒ mở sheet ⇒ "chương kế" ⇒ toast "Đang chuyển sang …", đọc từ đầu chương 129; tên chương ở đầu sheet đổi theo.
    2. "Chương trước" ⇒ chương 127.
    3. Chương đầu / chương cuối ⇒ nút tương ứng mờ, bấm không có tác dụng.
    4. Đang tạm dừng mà bấm nút chương ⇒ đọc luôn chương mới (như chọn ở mục lục).

## [1.3.859] - 2026-11-11

### feat: widget TTS chỉ còn kiểu nửa viên thuốc, bỏ kiểu Đĩa nổi và hàng Widget TTS ở Cài đặt

Anh Bửu: "giữ lại 1 kiểu thôi widget thôi nhé, là widget của tts thôi ấy". Widget TTS chỉ còn **đĩa nghe** dùng chung với nhạc (nửa viên thuốc dính mép của 1.3.858 + ô giữa thanh tab); kiểu **Đĩa nổi** (trước là mặc định) bỏ hẳn.

- `MediaDiscWindowManager.resolveKind`: TTS có phiên ⇒ đĩa TTS, không còn xét kiểu widget. Ai đang dùng Đĩa nổi tự sang đĩa nghe; ô giữa thanh tab có đĩa thật khi đang nghe truyện (trước đó là đĩa xám nếu chọn Đĩa nổi).
- **Xoá 9 file**: `FloatingWidgetContainerViewController`, `FloatingWidgetUIWindow`, `FloatingWidgetViewModel`, `TTSFloatingWidgetView`, `TTSFloatingWidgetWindowManager`, `TTSFloatingWidgetContaining`, `TTSWidgetStyle`, `TTSWidgetPreferences`, `TTSWidgetSettingsView`. Khoá `ttsWidgetStyle` / `ttsWidgetVerticalRatio` / `ttsWidgetEdge` bỏ mặc, không đọc nữa.
- `TTSCoverView` + `TTSCoverImageLoader` (mặt đĩa TTS và sheet điều khiển nhanh dùng) dời ra file riêng trong `Views/TTSWidget/` trước khi xoá file cũ. **Sửa build** (commit cùng tên, CI lượt 43016106688 đỏ): `CoverRotationState` (góc xoay bìa, `AudioCoverRotation` / `TTSWidgetCoverRotation` / `TTSRotatingCoverView` dùng) cũng nằm trong `TTSFloatingWidgetView.swift` mà bị sót ⇒ dời nguyên văn sang `Views/TTSWidget/CoverRotationState.swift`; grep lại mọi type của các file đã xoá trong đợt, không còn chỗ dùng nào khác.
- Gỡ chỗ gọi: `FreeBookApp` (4 chỗ; `modelContainer` của đĩa nghe nay cũng set trong `.task(id:)` và khi TTS bật/tắt phiên), `ReaderView` (`requestRevealOnNextShow`), `TTSQuickControlSheet` + `TTSSettingsSheetHost` (`modelContainer` lấy từ `MediaDiscWindowManager`), Cài đặt › Đọc & Nghe (bỏ hàng "Widget TTS"), `FloatingWidgetLayoutCoordinator` (bỏ id `.tts`).
- `architecture_allowlist.json`: gỡ hai entry của `TTSFloatingWidgetView.swift` (file đã xoá).
- `rules.md`: thay mục "TTS widget reveal-from-Reader invariants (1.3.277)" bằng luật một kiểu widget; luật 25 + mục nút hub nêu cửa sổ còn lại (hub, đĩa nghe, trình duyệt). `CLAUDE.md` / `AGENTS.md`: đoạn "Widget TTS chỉ một kiểu".
- **Kiểm chứng:**
  - Đọc code + grep chéo mọi symbol đã xoá (không còn chỗ gọi). `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 lỗi mới**.
  - **Chưa build** (máy Windows). **Chưa thử trên máy.**
  - Cần thử:
    1. Bấm tai nghe ở Reader ⇒ nửa viên đĩa TTS hiện (không còn đĩa nổi), chạm ⇒ sheet điều khiển nhanh.
    2. Về trang gốc tab khi đang đọc ⇒ ô giữa thanh tab là đĩa bìa truyện xoay.
    3. Sheet điều khiển nhanh ⇒ Giọng đọc / Hẹn giờ mở được (cần `modelContainer`).
    4. Cài đặt › Đọc & Nghe không còn hàng "Widget TTS".

## [1.3.858] - 2026-11-11

### feat: đĩa nghe thành nửa viên thuốc dính mép, kéo đổi mép và độ cao, bỏ nhấn giữ lên header

Anh Bửu duyệt mockup: nút góc của nhạc / TTS (đĩa nghe) đổi từ đĩa tròn 52 pt góc dưới phải thành **nửa viên thuốc** dính mép trái hoặc phải, kéo đổi được mép và độ cao; chạm vẫn mở sheet điều khiển nhanh như cũ.

- **Hình dùng chung** `EdgePillShape` (`Views/Common/GlassChrome/`): cạnh phẳng áp mép (vẽ tràn 1 pt ra ngoài để viền kính không thành vạch sáng), đầu bo bán kính = nửa chiều cao quay vào trong; `edge == nil` = hình tròn (lúc kéo). Hai cỡ: lớn 68 × 52 (đĩa nghe), nhỏ 38 × 36 (hub, trình duyệt — dùng ở commit sau).
- **Đĩa nghe** (`MediaDiscFaceButton(.corner)`): nửa viên 68 × 52 = lề 16 + nút "+" 52; nền kính `FloatingGlassBackground(shape:)` theo Độ trong suốt / Độ đục như nút "+"; bìa 32 pt đồng tâm đầu bo (thẳng cột với icon "+"), vẫn mờ đúng số theo Độ trong suốt.
- **Chạm + kéo ở UIKit** (`MediaDiscContainerViewController+Drag`, khuôn nút hub): mặt đĩa SwiftUI không còn cử chỉ (bài học 1.3.812). Kéo ⇒ co tròn 52 theo tay; thả ⇒ bám mép gần hơn, nhường nút hub / trình duyệt cùng mép (`FloatingWidgetLayoutCoordinator.resolve`), lưu mép + tỉ lệ dọc tâm (`MediaDiscPositionStore`, khoá `mediaDiscEdge` / `mediaDiscVerticalRatio`, một chỗ chung cho nhạc và TTS). Đang kéo mà đĩa bị ẩn (bàn phím, màn xem phim…) ⇒ thôi kéo, không lưu.
- **Chỗ đứng** (`MediaDiscPlacement` viết lại): mép + độ cao đã nhớ; chưa kéo lần nào ⇒ mép phải, thấp nhất (trang có nút "+" thì đứng ngay trên nút như đĩa góc cũ). Kẹp dưới header (vùng an toàn trên + 52) tới trên vùng an toàn đáy 12. Neo `.button` / `.bar` chồng cột mà đĩa đè lên (kể khe 12) ⇒ tạm đẩy lên trên neo, không ghi đè chỗ nhớ; cửa sổ phim nhỏ tính như neo. Luật ẩn giữ nguyên.
- **Bỏ nhấn giữ đưa đĩa lên header** (1.3.812–815): xoá `MediaDiscHeaderSlot`, vai neo `.headerTrailing` (gỡ ở header Reader + màn truyện tranh), `isDiscElevated`, vùng chạm 38 pt, `quickControlsDidDismiss`.
- `CLAUDE.md` / `AGENTS.md`: viết lại đoạn đĩa nghe + "Hai chỗ đặt đĩa".
- **Kiểm chứng:**
  - Đọc code + grep chéo symbol đã xoá. `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 lỗi mới**.
  - **Chưa build** (máy Windows). **Chưa thử trên máy.**
  - Cần thử:
    1. Nghe nhạc, mở trang có nút "+" ⇒ nửa viên mép phải ngay trên nút "+".
    2. Chạm ⇒ sheet nhạc; kéo sang mép trái, thả giữa màn ⇒ dính mép trái đúng độ cao, mở lại app vẫn ở đó.
    3. Kéo lên sát đỉnh ⇒ dừng dưới header, không che nút quay lại / "…".
    4. Thả đè nút hub cùng mép ⇒ nửa viên dời sát trên / dưới hub.
    5. Reader: nửa viên mép phải đứng trên nút tai nghe; trình duyệt / truyện tranh: đứng trên thanh dưới.
    6. Bàn phím hiện giữa lúc kéo ⇒ đĩa thu, không kẹt.

## [1.3.857] - 2026-11-11

### feat: phụ đề và lời bài hát dịch được bằng tiện ích dịch, sheet dịch có mục bộ dịch và ngôn ngữ

Anh Bửu duyệt: phụ đề phim và lời bài hát dịch được bằng tiện ích dịch như nội dung truyện chữ; sheet "Dịch phụ đề" / "Dịch lời" có BỘ DỊCH + NGÔN NGỮ giống popup dịch truyện. Dựa trên phần nền `ChineseTextExtensionTranslator`.

- **Phụ đề mềm + lời bài hát** (`MediaCaptionTranslator`):
  - `prepare(…, extensionSource:)` mới: chỗ gọi xin nhãn `source` thì lượt tra bộ dịch của phim / album (`ChineseTextExtensionTranslator.request`, truyện ⇒ nguồn ⇒ toàn cục như popup dịch). Bộ dịch là tiện ích ⇒ lượt mang `extensionRequest`; QT ⇒ như cũ.
  - Phụ đề phim: mỗi lô 50 dòng là **một** lượt gửi tiện ích (`source: chapterContent`). Lời bài hát: cả bài một lượt.
  - Chỉ dòng có chữ Hán được gửi — giữ cổng dịch như QT; dòng khác giữ nguyên.
  - Phồn → giản vẫn chạy trước: `converted` giữ cho kiểu Gốc / Song ngữ; bản dịch so với chữ đã chuyển.
  - Dòng tiện ích lỗi ⇒ dịch QT (cùng ảnh chụp từ điển của lượt), chỉ ghi log `❌ [MediaCaption]`, không báo người dùng.
  - Vẫn chạy trong `subtitleTask` / `lyricsTranslationTask`, huỷ được, không `Task.detached`; huỷ giữa lượt ⇒ bỏ cả lô.
- **Phụ đề cứng (OCR)**: không đổi — `prepare` không xin nhãn ⇒ luôn QT.
- **Sheet "Dịch phụ đề" / "Dịch lời"**: mục mới **Bộ dịch** (`MediaCaptionEngineRow`, `Views/Common/MediaCaption/`) gồm hai hàng, đúng hai cấp mà công tắc dịch của sheet đang ghi:
  - "Phim này" / "Album này" ⇒ `TranslationEngineStore.setBookSelection` ("Theo cấp trên" = theo nguồn).
  - "Nguồn" ⇒ `setSourceSelection` ("Theo cấp trên" = toàn cục).
  - Mỗi hàng: BỘ DỊCH (`TranslationEnginePickerSection`) + NGÔN NGỮ (`TranslationLanguagePickerRow`), dùng lại nguyên bản của popup dịch truyện. Không phải đổi `private` ⇒ `internal` nào: hai view này và `TranslationEngineDraft` vốn đã `internal`. Phần đọc danh sách ngôn ngữ chép theo popup vì hàm ở đó `private`, gắn state của popup.
  - Như mọi lựa chọn khác của sheet: chọn là ghi ngay (chỉ khi khác giá trị đang lưu). Tiện ích vừa chọn chưa có cặp ngôn ngữ thì chờ danh sách đọc xong rồi ghi cùng ngôn ngữ mặc định.
  - Ghi xong ⇒ đóng sheet thì `retranslateSubtitles()` / `retranslateLyrics()` dịch lại (không nạp lại phim / bài).
  - Nút "?" của mục giải thích ba cấp, lùi QT khi lỗi, và phụ đề cứng luôn QT.
- **Kiểm chứng:**
  - Đọc code + grep. `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 lỗi mới**.
  - **Chưa build** (máy Windows, không build tại chỗ). **Chưa thử trên máy.**
  - Cần thử:
    1. Phim có phụ đề chữ Trung, bật dịch, chọn tiện ích dịch ở "Phim này" ⇒ đóng sheet ⇒ phụ đề dịch bằng tiện ích, từ dòng đang chiếu trở đi.
    2. Đổi ngôn ngữ đích ⇒ dịch lại.
    3. Chọn "Theo cấp trên" ⇒ theo bộ dịch của nguồn.
    4. Tắt mạng / tiện ích lỗi ⇒ phụ đề vẫn có bản dịch QT, log có `❌ [MediaCaption]`.
    5. Lời bài hát: tương tự với sheet "Dịch lời".
    6. Đọc phụ đề cứng vẫn dịch QT khi bộ dịch là tiện ích.
    7. Bật phồn → giản: kiểu Gốc vẫn hiện chữ đã chuyển.
- `CLAUDE.md` / `AGENTS.md` (cả đợt 1.3.846–857): đoạn **Một đường cho mọi chữ Trung** (`ChineseTextPipeline`, `TranslationConfigSnapshot`, `TranslationDisplayRevision`, chữ gốc = chữ đã chuyển) ở mục Dịch thuật; phồn → giản "là bước riêng — cả khi tắt dịch"; bộ dịch tiện ích cho chữ ngoài nội dung chương (`ChineseTextExtensionTranslator`, `ExtensionTextTranslationStore`, chỗ nào vẫn QT); phụ đề / lời (1.3.851) và trình duyệt (1.3.850). Chuyển 12 mục CHANGELOG cũ nhất (1.3.816–827) sang `CHANGELOG.archive.md`.

## [1.3.856] - 2026-11-11

### feat: Khám phá dịch tên và mô tả truyện bằng tiện ích dịch theo từng trang danh sách

Anh Bửu: *"thực hiện thêm dịch bằng tiện ích vào những chỗ có pop còn thiếu"*. Phần Khám phá: ngăn kéo "Dịch văn bản" đã chọn được BỘ DỊCH nhưng danh sách vẫn dịch QT. Anh đã được báo số lượt gọi tiện ích là chỗ rủi ro nhất ⇒ chỉ xin dịch mẩu đang hiện.

- **Một store mỗi màn**: `DiscoveryView` (và `CategoryNovelsListView` của riêng nó) giữ một `ExtensionTextTranslationStore` thay cho cờ `textOptions`, truyền xuống `ExploreSectionsView` → `ExploreRenderContext`, `DiscoveryGenresTabView`, `DiscoveryCategoryTabView` → `DiscoveryNovelsLayoutView` → `DiscoveryNovelRowView` / `DiscoveryNovelGridCardView`. Bộ dịch của nguồn / toàn cục là tiện ích dịch (`ChineseTextExtensionTranslator.request(bookId: nil, packageId:, options:, source: .discovery)` khác `nil`) ⇒ tên truyện, mô tả, nhãn tag, tên tab danh mục, tên thể loại, tiêu đề / dòng phụ / chip của trang section và tiêu đề trang Thể loại / Xem thêm hiện **bản QT trước** rồi được thay bằng bản tiện ích; bộ dịch QT hoặc tắt dịch ⇒ y như trước (phồn → giản + QT theo nguồn).
- **Chỉ xin mẩu đang hiện**: hàng / thẻ đọc `store.text(_, kind: .meta)` trong `body`; danh sách vẫn dựng lười (`ScrollView` + `LazyVStack` / `LazyVGrid` / `LazyHStack`, chân `LoadMoreFooter`, cách nạp trang giữ nguyên) nên chỉ hàng đang dựng xin dịch, store gom các mẩu của một nhịp vẽ thành một lô. Không duyệt cả mảng item để xin trước. Ô tìm thể loại so khớp bằng bản QT + bản tiện ích **đã có**, không xin thêm.
- **Dựng lại lượt dịch** ngoài `body`: `DiscoveryView.refreshTextOptions()` (đổi nguồn, màn hiện lại, `TranslationDisplayRevision` đổi — nay tăng cả khi đổi bộ dịch); `CategoryNovelsListView` dùng `.onChange(of: TranslationDisplayRevision.shared.value, initial: true)`. Cấu hình + `Request` dựng ở `DiscoveryView.textStoreConfiguration` (file mới `DiscoveryView+TextTranslation.swift`, `DiscoveryView` không tăng dòng). Store giống cũ thì bỏ qua (back từ Chi tiết không dịch lại).
- **Tác giả** giữ phiên âm Hán Việt, không gửi tiện ích. Tên truyện khi dịch QT vẫn tra từ điển theo `link` như trước.
- **Tiện ích lỗi** ⇒ mẩu đó giữ bản QT; lỗi chỉ ghi log (`❌ [ExtTranslate]` của `TranslationExtensionRunner`), không dải báo.
- **Chưa dịch bằng tiện ích**: tab Thể loại của nguồn **Legado** (bố cục flex dựng mọi ô một lượt, không lười ⇒ giữ QT để không xin cả danh sách); Tìm kiếm và sheet Bộ lọc (ngoài phạm vi, vẫn QT).
- **Kiểm chứng:** đọc code + grep chéo mọi chỗ gọi các view đổi tham số (`DiscoveryNovelRowView`, `DiscoveryNovelsLayoutView`, `DiscoveryCategoryTabView`, `DiscoveryGenresTabView`, `ExploreSectionsView`, `ExploreRenderContext`; `DiscoveryNovelGridCardView` thêm `textStore` tuỳ chọn nên Tìm kiếm không đổi); `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới** (`DiscoveryView` giữ 674 dòng). Không build tại chỗ (Windows), chưa thử máy. Cần thử: (1) chọn tiện ích dịch ở popup dịch của Khám phá (Nguồn này) ⇒ tên / mô tả hiện QT rồi đổi sang bản tiện ích, tác giả vẫn phiên âm; (2) cuộn dài một tab danh mục: log `🌐 [ExtTranslate] … N dòng mới, M lần gọi` chỉ tăng theo trang đang xem, không gửi cả danh sách; (3) đổi lại QT / đổi nguồn ⇒ danh sách về QT ngay; (4) tiện ích lỗi ⇒ vẫn thấy QT, log `❌ [ExtTranslate]`; (5) Thể loại / Xem thêm (cả mở từ Chi tiết) dịch theo bộ dịch của nguồn.

## [1.3.855] - 2026-11-11

### feat: trang Chi tiết dịch tên, giới thiệu, thể loại, bình luận, đề xuất và mục lục bằng tiện ích dịch

Anh Bửu duyệt: popup dịch ở thanh trên Chi tiết có mục BỘ DỊCH nhưng cả trang vẫn dịch QT — chọn tiện ích dịch thì chữ của trang phải dịch bằng tiện ích đó. Dùng phần nền `ChineseTextExtensionTranslator` + `ExtensionTextTranslationStore`.

- **Hai store** của trang (`BookDetailText.Stores`, một `@State` của `BookDetailView`): `source: .detail` cho tên, giới thiệu, thể loại, tiêu đề thẻ đề xuất / bình luận, tiêu đề ngăn kéo `…`, tên truyện đề xuất, bình luận + trả lời (cả màn Tất cả bình luận); `source: .tableOfContent` cho tab Mục lục. `syncTextStores()` (`BookDetailView+TextOptions`) dựng lại lượt dịch bằng `ChineseTextExtensionTranslator.request(bookId: actualBookId, …)` trong `.onChange(of: textSyncKey, initial: true)` — khoá gồm `TranslationDisplayRevision` (tăng cả khi đổi bộ dịch), cờ dịch của trang và truyện; không gọi `update` trong `body`. Bộ dịch QT / tắt dịch ⇒ `request` `nil`, trang y như trước.
- **`BookDetailText`** (mới): chữ của một chỗ hiện = bản QT theo `options` (đúng ngay lượt vẽ đầu; đề xuất / bình luận vẫn chỉ từ điển chung) hoặc bản tiện ích của store. Chưa có ⇒ hiện bản QT rồi thay; store gom mẩu **đang hiện** thành lô (danh sách lười: đề xuất, bình luận, mục lục). Tiện ích lỗi ⇒ giữ bản QT, chỉ log (`❌ [ExtTranslate]` của runner).
- **Tác giả** giữ phiên âm Hán Việt, không gửi tiện ích.
- **Tab Mục lục**, luật như tên chương trong Reader: bộ dịch ra tiếng Việt (`targetsVietnamese`) và có `title_trans` ⇒ bản lưu, không gọi tiện ích; không thì tiện ích (cả dòng nhóm, mục lục online); lỗi / chưa xong ⇒ bản QT. Chỉ tên đang hiện, theo lô. Ô tìm chương khớp thêm bản tiện ích đã có (mục lục đã lưu và online; chỉ mục tên online để tìm vẫn là QT).
- `BookDetailHeaderView`, `SuggestRowView`, `CommentSectionView`, `CommentRowView`, `CommentRepliesBlock`, `AllCommentsView`, `BookDetailTOCView` nhận `BookDetailText` thay `ChineseTextPipeline.Options`. Màn xem phim: init `isTranslationEnabled:` của `CommentRowView` / `AllCommentsView` giữ QT như cũ (`BookDetailText.quickOnly`).
- **Kiểm chứng:** đọc code + grep (Chi tiết không còn chỗ hiện chữ Trung đi thẳng QT ngoài `BookDetailText`, trừ lượt điền `title_trans` để lưu); `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới** (`BookDetailView` 1029 ⇒ 1027). Không build tại chỗ (Windows), chưa thử máy. Cần thử: (1) popup dịch ở Chi tiết chọn một tiện ích dịch ⇒ tên, giới thiệu, thể loại, đề xuất, bình luận hiện QT rồi đổi sang bản tiện ích, log `🌐 [ExtTranslate] … dòng mới`; (2) tab Mục lục: truyện đã lưu có `title_trans` + bộ dịch ra tiếng Việt ⇒ không gọi tiện ích; truyện chưa lưu ⇒ tên chương đang hiện dịch theo lô khi cuộn; (3) tiện ích lỗi ⇒ trang giữ QT, có log ❌; (4) chọn lại QT ⇒ trang về QT ngay; (5) bình luận ở màn xem phim vẫn QT.

## [1.3.854] - 2026-11-11

### feat: truyện tranh dịch khối chữ OCR và tên chương bằng tiện ích dịch, popup có lại mục bộ dịch

Anh Bửu: *"thực hiện thêm dịch bằng tiện ích vào những chỗ có pop còn thiếu"* — phần truyện tranh: khối chữ OCR, tên chương (thanh trên + mục lục) và tên truyện dịch bằng tiện ích dịch khi bộ dịch của truyện là tiện ích; popup dịch của màn đọc truyện tranh có lại mục BỘ DỊCH / NGÔN NGỮ.

- **Popup dịch**: bỏ `showsEngineSection: false` ở `ComicReaderChromeView` ⇒ chọn bộ dịch + ngôn ngữ ngay ở màn đọc truyện tranh (3 cấp Truyện > Nguồn > Toàn cục như truyện chữ).
- **`ComicExtensionTextTranslation`** (mới, `Views/ComicReader/`, `@MainActor @Observable`): giữ hai `ExtensionTextTranslationStore` (tên chương `source: .tableOfContent`, tên truyện `.detail`) + lượt dịch khối chữ OCR (`.chapterContent`). Dựng lại lượt dịch qua `.comicExtensionText(…)` — `.task(id:)` khoá công tắc dịch + `TranslationDisplayRevision`, không gọi `store.update` trong `body`. Đổi cấu hình tiện ích (model, kiểu dịch) không làm lượt dịch khác đi ⇒ thông báo `TranslationEngineStore.didChangeNotification` bỏ hết bản cũ (cache runner tính cả cấu hình nên lấy bản mới) và tăng `engineRevision` ⇒ ảnh đang hiện dịch lại. `init` không có tác dụng phụ.
- **Khối chữ OCR** (`ComicPageTextTranslator`, thêm tham số `extensionRequest`): bộ dịch là tiện ích ⇒ mọi khối có chữ Hán của một ảnh đi **một** lượt `ChineseTextExtensionTranslator.translateWithFallback(kind: .content)` ngoài main (runner gom lô theo `max_line` / `max_length`); khối lỗi lùi QT, runner ghi log ❌. `Item.id` vẫn là vị trí khối gốc. Đường QT đổi sang `ChineseTextPipeline.content` (cùng kết quả). Lớp dịch vẫn chỉ khi bật dịch; trình xem phóng to dùng cùng lượt ⇒ trúng cache RAM của runner. `ComicImageTranslationContext` thêm `extensionRequest` + `extensionRevision`, chỉ còn `Equatable` (`Request` không `Hashable`).
- **Tên chương** (thanh trên + mục lục, cả dòng nhóm) — luật như Reader: bộ dịch sang tiếng Việt và chương có `title_trans` ⇒ `title_trans`; không thì tiện ích (kind `.chapterTitle`); lỗi ⇒ QT. Chỉ tên **đang hiện** xin dịch, theo lô: mỗi hàng `ComicChapterListRow` đọc store trong `body` của chính nó; bản tiện ích **không** ghi vào `ComicChapterEntry` nên vỏ `.equatable()` của `ComicChapterListHost` không bị phá (host so `extensionText` bằng `===`). Chữ tạm khi chờ = tên QT dựng sẵn ngoài main.
- **Tên truyện** (thanh trên + đầu mục lục): store riêng `.detail`, kind `.meta`, viết hoa chữ đầu mỗi từ như bản QT. Tác giả vẫn phiên Hán-Việt QT.
- Ô tìm của mục lục vẫn khớp tên QT, tên gốc, tên đã chuyển phồn → giản (dựng hàng ngoài main, không thấy bản tiện ích).
- **Kiểm chứng:** đọc code + grep chéo mọi chỗ gọi `ComicPageTextTranslator.translate` (lớp dịch trang, trình xem phóng to), `ComicChapterListHost(` / `ComicReaderChromeView(` / `ComicChapterListSheet(` / `ComicChapterListRow(` / `ComicImageTranslationContext(`; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới** (`ComicReaderView` vẫn 393 dòng). Không build tại chỗ (Windows), chưa thử máy. Cần thử: (1) truyện tranh nguồn Trung, chọn bộ dịch tiện ích ở popup ⇒ khối chữ trên ảnh, tên chương thanh trên + mục lục, tên truyện đổi sang bản tiện ích; (2) phóng to ảnh ⇒ cùng bản dịch, không gọi tiện ích lần hai (log `🌐 [ExtTranslate]`); (3) đổi model / kiểu dịch ở cấu hình tiện ích ⇒ ảnh + tên dịch lại; (4) tiện ích lỗi (tắt mạng) ⇒ khối / tên hiện QT, log ❌; (5) bộ dịch sang tiếng Việt + truyện đã lưu có `title_trans` ⇒ tên chương dùng `title_trans`; (6) mục lục dài cuộn nhanh ⇒ chỉ tên đang hiện được dịch, không giật; (7) bộ dịch QT ⇒ mọi thứ như cũ.

## [1.3.853] - 2026-11-11

### feat: đầu trang và mục lục Reader dịch tên chương, tên truyện bằng tiện ích dịch như trong chương

Anh Bửu duyệt: đầu trang + mục lục Reader dịch tên chương / tên truyện bằng tiện ích dịch như trong chương. Trước đây bộ dịch tiện ích chỉ dịch nội dung + tên chương trong chương; tên chương ở đầu trang (chương chưa dựng), màn đang tải, màn lỗi, tên truyện ở đầu trang và cả sheet mục lục vẫn là QT ⇒ đầu trang có thể hiện tên QT ngay trên tiêu đề chương bản tiện ích.

- **`ReaderTitleTranslationStore`** (mới, `Services/ChapterText/`, `@MainActor @Observable`; `ReaderView` giữ một bản cho cả phiên đọc, truyền xuống sheet mục lục): tên chương theo **chỉ số chương**, cùng luật với tên chương trong chương (`TranslationExtensionChapterTranslator.translateTitle`) — bộ dịch sang tiếng Việt và chương có `title_trans` ⇒ dùng `title_trans`, không gọi tiện ích; không thì tiện ích (`source = tableOfContent`, chữ đã chuyển phồn → giản, `cacheBookId = bookId` qua `ChineseTextExtensionTranslator`) ⇒ trúng cùng cache RAM của runner với đường trong chương (`translateText` và `translateLines` dùng chung `Cache.shared`, cùng phạm vi); lỗi ⇒ QT, chỉ log `❌ [ExtTranslate]`, không thêm dải báo. Tên gốc + `title_trans` đọc theo lô từ `ChapterStore` (truyện đã lưu, chia đoạn liền nhau) hoặc mục lục online (truyện chưa lưu).
- **Chỉ dịch chương đang hiện**: `title(at:)` gọi trong `body` (hàng mục lục đang dựng, tên chương đầu trang) chỉ xếp chỉ số vào hàng chờ (trường `@ObservationIgnored`); sau 0,15 s cả nhịp đi một lô — không gửi cả mục lục. Chương chưa đọc được tên gốc (truyện vừa lên kệ, `ChapterStore` chưa ghi) được xin lại ở lượt vẽ sau. Bản dịch chỉ ở RAM (trần 3000 tên).
- **Tên truyện**: `ReaderTitleTranslationStore.book` (`ExtensionTextTranslationStore`, `source = detail`, kiểu `meta`) — một store mỗi `source`; đầu trang Reader và đầu sheet mục lục dùng chung, tạm hiện bản QT rồi thay khi tiện ích xong.
- **Đầu trang / màn đang tải / màn lỗi** (`ReaderView+TitleTranslation`, mới): chương đã dựng vẫn hiện tên của bản dựng (đã theo bộ dịch); chương chưa dựng ⇒ `chapterHeaderTitle(at:rawTitle:)` = bản tiện ích (hoặc `title_trans`) nếu đã có, không thì QT. `translateMetaIfNeeded` / `translateChapterTitleIfNeeded` chuyển sang file này. Mục lục: `ReaderChapterListView+List.displayTitle(for:)` = bản tiện ích của chương nếu đã có, không thì tên worker chọn (`title_trans` / QT / đã chuyển). Giữ `ReaderChapterListHost` `.equatable()` (so store theo identity) + `List`.
- **Đổi cấu hình**: `.task(id: titleTranslationKey)` (khoá gồm `TranslationDisplayRevision.shared.value` — tăng cả khi đổi bộ dịch — công tắc dịch, phồn → giản, truyện đã lên kệ, nguồn) + đổi mục lục online ⇒ `syncTitleTranslations()` dựng lại `Request` ngoài `body`; khác lượt cũ ⇒ bỏ bản dịch cũ, dịch lại khi hàng hiện lại. `ReaderView` vì thế vẽ lại mỗi lần `TranslationDisplayRevision` tăng (đổi từ điển / rule cũng tăng).
- **Chưa làm**: ô tìm chương vẫn khớp tên QT / gốc / đã chuyển như trước — bản tiện ích chỉ thay chữ hiển thị. `ReaderTitleTranslationStore` để `public` chỉ vì `init` public của `ReaderChapterListView` nhận nó (thành viên vẫn `internal`). Tên chương của chương đang mở có thể được xin tiện ích hai lần (đầu trang trước khi dựng xong + bản dựng trong chương) — chung cache nên lượt sau thường trúng cache.
- `ReaderView.swift` 1930 ⇒ 1918 dòng.
- **Kiểm chứng:** đọc code + grep chéo chỗ gọi `ReaderChapterListView(` / `ReaderChapterListHost(` / hai hàm dịch tên đã chuyển file. `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. **Chưa build** (Windows), chưa thử máy. Cần thử: (1) bộ dịch tiện ích sang tiếng Việt + chương có `title_trans` ⇒ mục lục / đầu trang dùng `title_trans`, log không có lượt gọi tiện ích cho tên chương; (2) bộ dịch sang ngôn ngữ khác ⇒ mục lục hiện QT trước rồi đổi sang bản tiện ích khi cuộn tới; (3) đổi bộ dịch hoặc phồn → giản ở popup ⇒ tên đầu trang + mục lục dịch lại; (4) làm hỏng tiện ích ⇒ đầu trang / mục lục giữ QT, log chỉ có ❌; (5) truyện vừa lên kệ: mở mục lục ngay ⇒ tên vẫn được dịch khi mục lục lưu xong; (6) đầu sheet mục lục và đầu trang cùng tên truyện bản tiện ích.
- **Sửa lỗi CI:** hai móc `.task(id: titleTranslationKey)` / `.onChange(of: currentOnlineChapters)` gắn thẳng vào chuỗi modifier dài của `readerObserverLayer` làm trình biên dịch quá thời gian suy kiểu (`ReaderView.swift:468`) ⇒ tách ra lớp `readerTitleSyncLayer` (`ReaderView+TitleTranslation`).

## [1.3.852] - 2026-11-11

### refactor: thêm phần nền dịch chữ ngắn bằng tiện ích dịch theo lô, lùi QT khi lỗi

Anh Bửu: *"thực hiện thêm dịch bằng tiện ích vào những chỗ có pop còn thiếu"*, duyệt cả 5 chỗ (đầu trang + mục lục Reader, Chi tiết, truyện tranh, Khám phá, phụ đề / lời). Đây là phần nền; các màn chuyển sang dùng nó ở các bản kế tiếp.

- **`ChineseTextExtensionTranslator`** (mới, `Services/Translation/Pipeline/`): bước "dịch" của `ChineseTextPipeline` khi bộ dịch là tiện ích, cho chữ **ngoài** nội dung chương. Cùng thứ tự: phồn → giản trước ⇒ tiện ích (`TranslationExtensionRunner.translateLines`: gom lô theo `max_line` / `max_length`, cache RAM theo dòng + lỗi gần đây 90 s, gộp lượt trùng) ⇒ mẩu lỗi lùi QT theo `Kind` (`meta` / `chapterTitle` / `content`), mẩu lỗi không có chữ Hán giữ chữ đã chuyển. Chữ nhiều dòng tách theo `
` rồi ghép lại; mẩu trùng gửi một lần. `request(bookId:packageId:options:source:)` tra bộ dịch như popup (truyện ⇒ nguồn ⇒ toàn cục), `nil` khi tắt dịch hoặc bộ dịch là QT; `Request.targetsVietnamese` cho luật `title_trans`.
- **`ExtensionTextTranslationStore`** (mới, `@MainActor @Observable`): cho màn hiện nhiều mẩu trong `body` — `text(_:kind:quick:)` trả bản tiện ích nếu đã có, không thì bản QT và xếp mẩu vào hàng chờ; sau 0,15 s mọi mẩu của nhịp đó đi một lượt ⇒ màn vẽ lại. Gọi được trong `body` (chỉ ghi trường không quan sát). Mẩu lỗi giữ QT tới khi đổi lượt; giữ tối đa 3000 bản.
- **`TranslationDisplayRevision`** tăng cả khi đổi bộ dịch (`TranslationEngineStore.didChangeNotification`).
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows). Chưa có màn nào gọi phần nền mới — hành vi app không đổi.

## [1.3.851] - 2026-11-11

### feat: phụ đề, lời bài hát và tên phim, tên bài chuyển phồn → giản cả khi tắt dịch

Anh Bửu: *"dù bật hay không thì cũng gói trong 1 function, nếu bật phồn->giản thì chuyển phồn giản sang bước dịch -> nếu bật dịch thì dịch khi thì return luôn"*, *"nếu bật phồn giản thì chữ gốc bạn hãy để kết quả sau phồn → giản"*. Phần này áp luật đó cho phim / nhạc qua `ChineseTextPipeline`.

- **Phụ đề mềm + lời bài hát** (`MediaCaptionTranslator`):
  - `prepare` đọc `ChineseTextPipeline.options(bookId:packageId:)` (phim / album này ⇒ nguồn ⇒ Tất cả). Lượt mở khi bật phồn → giản **hoặc** bật dịch.
  - Mỗi dòng trả `LineResult { converted, translation }`: chuyển cả dòng một lần, rồi dịch từng hàng bằng `ChineseTextPipeline.content(…, alreadyConverted)`. Bản dịch so với chữ **đã chuyển**, nên dòng chỉ đổi phồn → giản không bị coi là "bản dịch".
  - `VideoSubtitleCue` và `AudioLyricLine` thêm `converted` + `displayText`. `text` vẫn nguyên văn, `data` phụ đề / nguồn lời không đổi.
  - Phim: chuyển cả bộ phụ đề trước (`Pass.convertOnly`) rồi mới dịch theo lô như cũ. Lời bài hát: chuyển + dịch một lượt.
  - Kiểu Gốc = chữ đã chuyển; Song ngữ = chữ đã chuyển + bản dịch (`currentCueText`, `AudioLyricsScrollView`, `AudioCurrentLyricLine`).
  - Dịch lại (đóng sheet) bỏ cả chữ đã chuyển lẫn bản dịch (`AudioLyrics.clearingCaptions`).
  - Vẫn chạy trong `subtitleTask` / `lyricsTranslationTask`, không `Task.detached`.
- **Phụ đề cứng (OCR)**: vẫn **chỉ** đọc khi bật dịch (`Pass.translates`). Lượt chỉ chuyển phồn → giản coi như cổng dịch tắt: không vẽ chữ Trung lên hình. Khi đang đọc, câu Trung ở Song ngữ là chữ đã chuyển (`DisplayedCue.original`); đệm theo câu lưu `LineResult`.
- **Tên hiển thị** — `MediaDisplayNames` (mới, `Services/Media/DisplayNames/`):
  - Bảng tên gốc → tên đã qua pipeline: `meta` cho tên phim / album, `author` cho tác giả / nghệ sĩ, `chapterTitle` cho tên tập / nhóm tập / bài. Tính ngoài main, chụp từ điển một lần.
  - Tên gốc giữ nguyên văn vì còn ghi `Book`, mục lục, playlist, ngữ cảnh nguồn, từ điển truyện: `bookTitle`, `albumTitle`, `albumAuthor`, `Episode.title`, `Track.title`, `Track.artist`.
  - `Episode` / `Track` thêm `shownTitle`; `displayTitle` đọc trường này.
  - **Phim** (`VideoPlaybackSession+DisplayNames`):
    - Tính lại lúc nạp phim, khi màn xem nhận mục lục làm mới, và khi đóng sheet "Dịch phụ đề" / "Từ điển truyện" (`retranslateSubtitles`).
    - Thay `translateSectionTitles` (trước chỉ dịch tên nhóm tập khi bật dịch và ghi đè `title`).
    - Dùng ở: thanh trên, chi tiết trình phát, tên nhóm tập (`VideoEpisodeGrouping`), hub / cửa sổ nhỏ (`VideoMiniPlayerState.title`), màn khoá. Phim 18+ ở màn khoá vẫn chỉ "Đang phát".
  - **Nhạc** (`AudioPlaybackSession+DisplayNames`):
    - Tính lại khi bắt đầu phát, khi chi tiết về, khi làm mới mục lục, và khi đóng sheet "Dịch lời".
    - Dùng ở: đầu màn nghe, ngăn kéo `…`, các trang Đĩa / Lời / Danh sách, sheet điều khiển nhanh, đĩa góc dưới, màn khoá.
    - `currentArtist` nay là tên để vẽ.
    - Danh sách gợi ý nhạc cũng đi `meta` / `author`, như thẻ đề xuất phim.
  - **Màn xem phim** (`VideoWatchModel`):
    - `meta` = `ChineseTextPipeline.meta` (chuyển cả khi tắt dịch); thêm `displayAuthor`.
    - Đọc `TranslationDisplayRevision` để vẽ lại khi cấu hình đổi.
    - Tên tập của mục lục màn xem (phim chưa phát) gắn `shownTitle` lúc `markReady`.
    - Dòng "Tự sang: <tên>" dùng tên đã chuyển.
- **Sheet "Dịch phụ đề" / "Dịch lời"**:
  - Giải thích lại: phồn → giản chạy cả khi tắt dịch và áp cho cả tên.
  - Dòng "Hiện tại" của sheet và "Đang bật / Đang tắt" của ngăn kéo tính cùng luật với chỗ chạy (`ChineseTextPipeline.options`).
- **Ngoài phạm vi, giữ nguyên**:
  - Hàng bình luận (`CommentRowView` / `AllCommentsView` chỉ nhận cờ dịch) ⇒ bình luận phim chưa chuyển phồn → giản khi tắt dịch.
  - Playlist: trước đây không dịch tên ⇒ vẫn nguyên văn.
  - Tên tập ở màn tải (`Views/Download`).
- **Kiểm chứng:**
  - Đọc code + grep. `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 lỗi mới**.
  - **Chưa build** (máy Windows, không build tại chỗ). **Chưa thử trên máy.**
  - Cần thử:
    1. Phim có phụ đề phồn thể, tắt dịch, bật phồn → giản ở sheet "Dịch phụ đề" ⇒ phụ đề hiện giản thể. Bật dịch ⇒ Gốc = giản thể, Song ngữ = bản dịch + giản thể.
    2. Lời bài hát phồn thể: tương tự, với sheet "Dịch lời".
    3. Đọc phụ đề cứng, tắt dịch + bật phồn → giản ⇒ không vẽ gì lên hình. Bật dịch ⇒ Song ngữ hiện chữ Trung giản thể.
    4. Chỉ bật phồn → giản ⇒ tên phim / tập / nhóm tập / bài / album / nghệ sĩ phồn thể đổi sang giản thể ở thanh trên, hub, đĩa góc dưới, màn khoá.
    5. Phim / album 18+: màn khoá vẫn "Đang phát".
    6. Thêm vào playlist / ghi Lịch sử vẫn lưu tên gốc.

## [1.3.850] - 2026-11-11

### feat: trình duyệt chuyển phồn → giản riêng, không cần bật dịch trang

Anh Bửu: *"Trình duyệt dịch QT cũng làm thành các bước như tôi yêu cầu"* — phồn → giản là bước riêng chạy trước khi dịch, chạy cả khi tắt dịch; mọi chữ Trung đi qua một hàm (chuyển nếu bật ⇒ dịch nếu bật ⇒ trả); khi bật phồn → giản, "chữ gốc" ở mọi nơi là chữ đã chuyển. Trước đây ở trình duyệt phồn → giản chỉ là bước con của dịch trang.

- **Hai cờ độc lập trên tab** (`BypassBrowserTab`): thêm `isConvertingTraditional` cạnh `isTranslating`, một setter `setPageProcessing(translates:converts:)` (mỗi cờ chỉ gán khi khác giá trị cũ), `pageTextOptions` (`nil` khi cả hai tắt). Trang được xử lý khi bật dịch **hoặc** bật phồn → giản; chỉ bật phồn → giản ⇒ trang hiện giản thể, không dịch.
- **Handler `fbPageTranslate`** (`BrowserPageTranslator`): hai closure `accepts` + `convertsTraditional` gộp thành một `pageOptions` (đọc hai cờ của tab trên main mỗi lô); xử lý ngoài main bằng `ChineseTextPipeline.content` (chuyển ⇒ dịch ⇒ trả, từ điển chung). Vẫn cài một lần mỗi `WKUserContentController`, cùng content world, handler có trả lời; webview tiện ích không đổi.
- **Script trang** (`BrowserPageTranslateScript`): `enable(mode)` với chế độ `"c"` / `"t"` / `"ct"` — cùng chế độ là no-op, khác chế độ ⇒ khôi phục chữ gốc rồi xử lý lại (gạt một trong hai công tắc, hoặc trang khôi phục từ bộ đệm lùi/tiến đã xử lý theo chế độ cũ); tắt cả hai ⇒ trả nguyên bản. Thêm `isTranslating()`.
- **Store** (`BypassBrowserTabStore+Translation`): commit / nút dịch tay / đổi luật nhớ đều đẩy hai cờ (phồn → giản = chỉnh riêng theo tên miền ?? công tắc chung, `BrowserTranslatePolicy.convertsTraditional`). Đổi phồn → giản (khiên hoặc Cài đặt mở từ trình duyệt) áp lại cho **mọi** tab web của tên miền bị đổi, kể cả tab không dịch — `retranslateTabs(underHosts:)` / `retranslateTabsFollowingGlobalConvert()` đổi tên thành `reapplyConvertPolicy(underHosts:)` / `reapplyConvertPolicyFollowingGlobal()`.
- **Tiêu đề tab** chuyển / dịch theo đúng hai cờ (`ChineseTextPipeline.meta`, nhớ theo tiêu đề gốc + hai cờ).
- **Menu bôi đen**: Dịch QT / Tra từ điển / Sao chép bản dịch dùng câu gốc **đã chuyển** khi tab đang chuyển, kể cả khi không dịch trang. Script chỉ lấy bản gốc của node khi chữ đang hiện là bản dịch (`isTranslating`); chỉ phồn → giản thì dùng chữ đang hiện (giữ đúng từ + vị trí cho Tra từ điển). Bản gốc của đoạn đã dịch là chữ thô ⇒ store chuyển lúc bấm (`pageSourceText`, `pageLookupRequest`; độ dài đoạn đổi ⇒ bỏ vị trí từ). Sheet Dịch QT nhận câu gốc đã chuyển, bỏ tham số `convertsTraditional`.
- **Sheet khiên** (`BrowserShieldTranslateSection`): "Phồn → giản" thành hàng ngang hàng, độc lập với "Tự dịch QT" (cùng cột icon, cùng cỡ chữ), vẫn nhớ theo tên miền + "Dùng cài đặt chung".
- **Cài đặt › Trình duyệt › Dịch trang**: công tắc "Chuyển phồn thể → giản thể" (bỏ "trước khi dịch"), giải thích mới (bước riêng, chạy cả khi không dịch, áp cho chữ trang, tiêu đề tab và câu gốc menu bôi đen). Doc của `BrowserTranslatePolicy`, `BrowserSitePreference`, `BrowserSitePreferenceStore` sửa theo.
- **Dải báo**: vẫn chỉ báo khi tự **dịch** theo luật nhớ ("Tự dịch QT · theo …"); chỉ phồn → giản thì không báo — cờ đó theo công tắc chung, báo ở mọi tên miền mới là ồn.
- **Kiểm chứng:** đọc code + grep chéo các tên đổi / bỏ (`setTranslating`, `retranslateTabs…`, `BrowserPageTranslator.translate`, `enableCall`, tham số `convertsTraditional` của sheet Dịch QT); `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới** (script trang 384 dòng, `BypassWebView` không tăng dòng). Không build tại chỗ (Windows), chưa thử máy. Cần thử: (1) trang phồn thể, tắt dịch, bật Phồn → giản ở khiên ⇒ trang + tiêu đề tab thành giản thể ngay, không dịch; tắt ⇒ về nguyên bản; (2) bật cả hai ⇒ dịch; tắt dịch (ngăn kéo) ⇒ trang còn giản thể; (3) đổi công tắc chung ở Cài đặt mở từ trình duyệt ⇒ tab không có chỉnh riêng đổi theo; (4) chỉ phồn → giản: bôi đen ⇒ Dịch QT "Bản gốc" là giản thể, Tra từ điển tra đúng từ đang chọn; đang dịch + phồn → giản ⇒ "Bản gốc" là giản thể; (5) lùi / tiến giữa trang đã đổi chế độ ⇒ trang xử lý đúng chế độ hiện tại.

## [1.3.849] - 2026-11-11

### feat: Khám phá và Tìm kiếm chuyển phồn → giản và dịch tên, tác giả theo nguồn như popup dịch

Anh Bửu: *"dù bật hay không thì cũng gói trong 1 function, nếu bật phồn->giản thì chuyển phồn giản sang bước dịch -> nếu bật dịch thì dịch khi thì return luôn"*, *"nếu bật phồn giản thì chữ gốc bạn hãy để kết quả sau phồn → giản"*. Đã duyệt: phồn → giản chạy cả khi tắt dịch; màn chưa có truyện (Khám phá, Tìm kiếm) theo Nguồn ⇒ Tất cả cho cả dịch lẫn phồn → giản, như popup dịch; Tìm kiếm thôi chỉ theo công tắc Tất cả.

- **Khám phá** (`DiscoveryView`): cờ `isTranslationEnabled` thay bằng `textOptions` (`ChineseTextPipeline.Options` của nguồn đang xem, `sourceOptions(packageId:isChineseSourceHint:)` giữ gợi ý `isChineseSource` như cũ), tính **một lần** ở `refreshTextOptions()` khi đổi nguồn, khi màn hiện lại và khi `TranslationDisplayRevision` đổi (thay chỗ nghe `TranslationConfigStore.didChangeNotification` — nay đổi ở mọi cấp, công tắc Tất cả, từ điển / rule cũng tính lại). Chip tab `home`, trang section (`ExploreSectionsView` → `ExploreRenderContext.display`), tab Thể loại (`DiscoveryGenresTabView`, cache tên dịch bỏ khi `textOptions` đổi), tab Legado (`LegadoExploreTabView`), tab danh mục (`DiscoveryCategoryTabView` → `DiscoveryNovelsLayoutView` → `DiscoveryNovelRowView` / `DiscoveryNovelGridCardView`) đều nhận `textOptions` và gọi `ChineseTextPipeline.meta` / `.author`. Tên truyện vẫn tra từ điển theo `link` như trước (chép `Options`, đổi `dictionaryBookId`). Tác giả nay chuyển phồn → giản cả khi tắt dịch. Dòng "Dịch văn bản" của menu nguồn đọc `textOptions.translates`.
- **Thể loại / Xem thêm** (`CategoryNovelsListView`): tính `Options` của nguồn một lần mỗi lượt `body` (đọc `TranslationDisplayRevision` ⇒ popup dịch lưu là vẽ lại; trước đó không tự vẽ lại), cho danh sách và tiêu đề trang. `init` không đổi.
- **Tìm kiếm** (`SearchView`): bỏ `@AppStorage("isTranslationEnabled")`; mỗi kết quả theo **nguồn của nó**. Tìm mọi nguồn: `textOptionsBySource` (file mới `SearchView+TextOptions.swift`) chụp `TranslationConfigStore.shared.snapshot()` một lần mỗi lượt dựng rồi tra từng nguồn (không từng hàng); tìm một nguồn: `textOptions(for:)` truyền một `Options` xuống `SearchSingleSourceResultsView` (tên, mô tả / nội dung / tác giả dự phòng, thẻ lưới).
- **Bộ lọc tiện ích** (`ExtensionFilterSheet`): tiêu đề / dòng phụ / lựa chọn hiện chữ phồn → giản + dịch theo nguồn (chạy ngoài main như trước); nguồn chỉ bật phồn → giản cũng chuyển. Giá trị lưu vẫn là chữ gốc.
- Trong `Views/Discovery`, `Views/Search`, `CategoryNovelsListView`, `ExtensionFilterSheet` không còn gọi thẳng `translateMeta` / `translateAuthorHanViet`. Không đổi cấu trúc danh sách (`ScrollView` + `LazyVStack` giữ nguyên).
- Ngoài phạm vi, chưa đổi: nhãn `tag` trên bìa kết quả Tìm (`SearchView+Cover`) vốn không dịch; `BypassBrowserTab` (trình duyệt); `BookListItemView` / `BookDisplayTranslation` (màn Tìm không dùng hai view này).
- **Kiểm chứng:** đọc code + grep chéo mọi chỗ gọi các view đổi tham số (`DiscoveryNovelRowView`, `DiscoveryNovelGridCardView`, `DiscoveryNovelsLayoutView`, `DiscoveryCategoryTabView`, `DiscoveryGenresTabView`, `LegadoExploreTabView`, `ExploreSectionsView`, `ExploreRenderContext`, `SearchSingleSourceResultsView`); `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới** (`DiscoveryView` 685 → 674, `SearchView` 701 → 695 dòng). Không build tại chỗ (Windows), chưa thử máy. Cần thử: (1) Khám phá một nguồn tiếng Trung phồn thể: bật phồn → giản ở popup dịch (Nguồn này), tắt dịch ⇒ tên / mô tả / tác giả / chip tab hiện chữ giản thể; bật dịch ⇒ bản dịch; (2) đổi ở popup dịch ⇒ Trang chủ section, tab danh mục, Thể loại, Xem thêm đổi ngay không cần đổi nguồn; (3) Tìm mọi nguồn: tắt dịch riêng một nguồn ⇒ chỉ kết quả của nguồn đó hiện nguyên văn; (4) sheet Bộ lọc của nguồn phồn thể chỉ bật phồn → giản ⇒ nhãn hiện giản thể, áp dụng vẫn đúng giá trị.

## [1.3.848] - 2026-11-11

### feat: tên truyện và tác giả ở Kệ, Lịch sử, Chi tiết theo ba cấp dịch và phồn → giản của popup

Anh Bửu: phồn → giản là bước riêng chạy trước khi dịch, chạy cả khi tắt dịch; khi bật thì "chữ gốc" ở mọi nơi là chữ đã chuyển; Kệ / Lịch sử thôi chỉ theo công tắc Tất cả — *"vì pop dịch chung mà, có 3 mức phạm vi"*. Phần C của đợt chuyển sang `ChineseTextPipeline` (1.3.846).

- **Một nguồn cho truyện đã lưu** — `BookDisplayTranslation` (Views/Common) đi qua `ChineseTextPipeline`: phồn → giản theo Truyện ⇒ Nguồn ⇒ Tất cả (cả khi tắt dịch), dịch theo **ba cấp** của popup dịch thay cho `@AppStorage("isTranslationEnabled")`. `listOptions(…)` cho hàng / thẻ: đọc `TranslationDisplayRevision` (danh sách vẽ lại khi popup lưu ở bất kỳ cấp nào) và dùng **một** `TranslationConfigSnapshot` chung cho mọi hàng tới lần đổi cấu hình kế tiếp (không chụp từng hàng, không luồn bản chụp qua `ShelfBooksLayoutView`). `screenOptions(…)` cho màn đã có cờ dịch ba cấp riêng; `options(…)` cho sheet / toast (gọi được ngoài main). Tác giả chỉ phiên âm khi có chữ Hán (tên Latin không bị tách lại).
- **Kệ, Lịch sử, Bộ sưu tập, Tìm trên kệ**: `BookListItemView` (tên, tác giả, mô tả, dòng "Đang đọc" — tên chương qua `ChineseTextPipeline.chapterTitle`) và `ShelfBookGridCardView`; bỏ `@AppStorage` dịch ở hàng. Công tắc "Dịch nghĩa" của Kệ giữ nguyên (là cấp Tất cả).
- **Tìm trên kệ** + sheet chọn truyện của Từ điển: `ShelfBookSearchMatcher.matches(query:book:config:)` khớp thêm tên / tác giả **đã chuyển** khi truyện bật phồn → giản (chữ hàng đang hiện khi tắt dịch); một bản chụp mỗi lượt lọc.
- **Sheet nhấn giữ, toast, thông báo, tải / xuất**: `BookActionSheet`, `BookActionRunner`, `NotificationInboxView` (tên truyện + tên chương mới nhất), dòng tác vụ ở Thông báo, `DownloadTrackerView`, `TaskOptionsSheet`, toast kết quả tải / xuất (`DownloadTask.displayBookTitle`), dải báo + toast truyện mất nguồn (tính với nguồn mới sau khi chuyển), toast chia sẻ / nhập từ điển, toast khôi phục đổi nguồn (truyện còn lại), tiến trình + toast nhập truyện từ file (`Book.title` vẫn ghi tên gốc). Tên file xuất từ điển vẫn **luôn** dịch như trước, thêm phồn → giản theo truyện.
- **Chi tiết** (cả trang theo truyện đang mở): `BookDetailView+TextOptions` (mới) — `metaTextOptions` = cờ dịch ba cấp đang có + phồn → giản của truyện, đọc revision nên trang vẽ lại khi đổi phồn → giản; tên, tác giả, mô tả, thể loại, tiêu đề thẻ, tiêu đề ngăn kéo `…`. Đề xuất, bình luận, trả lời, Tất cả bình luận dùng `relatedTextOptions` (cùng cấu hình, chỉ từ điển chung như trước); các view này nhận `textOptions` thay `isTranslationEnabled`. Init `isTranslationEnabled:` của `CommentRowView` / `AllCommentsView` giữ cho màn xem phim (hành vi cũ).
- **Reader / truyện tranh**: tên truyện ở header Reader + tìm trong truyện (`translateMetaIfNeeded`), tên / tác giả đầu sheet mục lục Reader và truyện tranh, tên truyện ở thanh trên truyện tranh — phồn → giản chạy cả khi tắt dịch. Hàng tên chương không đổi.
- **Bản để tìm `titleTrans` / `authorTrans`**: công thức duy nhất `BookTitleTranslationMigrator.searchTranslations` — luôn dịch / phiên âm như trước nhưng **sau** phồn → giản theo cấu hình của truyện; dùng ở backfill, làm mới lúc mở truyện, sửa thông tin truyện (`updateBookInfo`), khôi phục backup (một bản chụp mỗi lô). Đổi phồn → giản ở popup dịch ⇒ `TranslationTraditionalDraft.commit` tính lại cho các truyện vừa đổi (`BookTitleTranslationMigrator.refresh`, `ModelContext` riêng, trước lượt dịch lại tên chương). Lượt một lần lúc mở app cho truyện đang bật phồn → giản (trong `runIfNeeded`, cờ `bookTitleTransConvertMigrationV1`, lưu được mới ghi cờ).
- `TranslateUtils.translateBookTitleIfNeeded` không còn caller trong `Sources/`.
- **Kiểm chứng:** đọc code + grep (không còn `translateBookTitleIfNeeded(` / `translateMeta(` / `translateAuthorHanViet(` gọi thẳng trong các file của phần này); `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới** (`BookDetailView` 1066 ⇒ 1062, `ReaderView` 1942 ⇒ 1939, `DictionaryListView` 661 ⇒ 660, `ReaderChapterListView` 299 ⇒ 294). Không build tại chỗ (Windows), chưa thử máy. Cần thử: (1) popup dịch ở một truyện bật phồn → giản "Truyện này", tắt dịch ⇒ tên / tác giả ở Kệ, Lịch sử, Chi tiết, đầu Reader thành chữ giản; (2) tắt dịch "Nguồn này" ⇒ Kệ hiện tên gốc cho truyện của nguồn đó, nguồn khác vẫn dịch; (3) Tìm trên kệ gõ chữ giản tìm ra truyện tên phồn đã bật chuyển; (4) log `📚 [BookTitleTranslationMigrator] Tính lại tên dịch/phiên âm theo phồn→giản` lúc mở app và sau khi đổi phồn → giản; (5) bình luận ở màn xem phim vẫn dịch như cũ. Đổi hành vi: truyện có tiện ích nguồn đã gỡ không còn dịch tên ở Kệ / Lịch sử (như Chi tiết) trừ khi đặt riêng truyện / nguồn.

## [1.3.847] - 2026-11-11

### fix: phồn → giản chạy cả khi tắt dịch ở Reader, TTS, mục lục, AI và xuất TXT; chữ gốc là chữ đã chuyển

Anh Bửu: *"dù bật hay không thì cũng gói trong 1 function, nếu bật phồn->giản thì chuyển phồn giản sang bước dịch -> nếu bật dịch thì dịch khi thì return luôn"*, *"nếu bật phồn giản thì chữ gốc bạn hãy để kết quả sau phồn → giản"*. Phần chữ truyện của đợt chuyển sang `ChineseTextPipeline` (1.3.846): Reader, TTS, lọc rác, AI, mục lục, xuất TXT, truyện tranh.

- **Reader** (`ReaderViewModel+Translation`): chương chuẩn hoá bằng `ChineseTextPipeline.normalizeChapter(_, converts:)` — chuyển **trước** khi chuẩn hoá, kể cả khi tắt dịch; dòng dịch bằng `contentWithMapping(…, options.alreadyConverted)`, tên chương bằng `chapterTitleWithMapping`. `ParagraphItem.original` (cả tên chương id -1) là chữ **đã chuyển** ⇒ tắt dịch + bật phồn → giản hiện giản thể; màn Dịch / bôi đen / chép chữ gốc nhận câu đã chuyển. `cached.originalContent` / `originalTitle` giữ chữ **chưa** chuyển (hàm dựng trả lại chuỗi đầu vào thay vì bản đã chuẩn hoá) — dựng lại khi tắt phồn → giản mới về được chữ phồn, và TTS chuẩn hoá đúng chuỗi đó với cùng cờ ⇒ cùng dòng, cùng id, cùng chữ cho vệt highlight. Đổi phồn → giản khi tắt dịch dựng lại chương như cũ (`isTranslationFresh` so cả cờ phồn → giản). Tên chương chưa dựng (`chapterTitle(at:)`, mục lục online) cũng là tên đã chuyển.
- **Bộ dịch tiện ích** (`TranslationExtensionChapterTranslator.translate(…, titleConvertsTraditional:)`): dòng nhận vào đã chuyển (Reader và TTS cùng dựng bằng `normalizeChapter`) nên không chuyển lại, không lệch line ID; tên chương còn thô (để so `title_trans` với tên đã lưu) ⇒ chỉ chuyển tên. Dòng lỗi lùi QT qua pipeline; tên không cần dịch trả tên đã chuyển.
- **TTS**: `TTSBackgroundProcessor` và `TTSExtensionTranslationPreparer` dùng `normalizeChapter` cùng cờ với Reader; tắt dịch đọc chữ đã chuyển, tên chương không dịch ⇒ đã chuyển; `TTSPretranslatedSnapshot.matches` so dòng đã chuyển hai bên. Tên truyện / tác giả / tên chương của widget, sheet điều khiển, danh sách chương, màn khoá qua `ChineseTextPipeline.meta/author/chapterTitle` (`TTSManager.sessionTextOptions`, mới). Thay đổi kèm theo: tác giả ở widget là phiên âm Hán Việt (`author`) thay vì `translateMeta`; màn khoá theo cờ dịch **của phiên** (trước đây theo công tắc Tất cả); đổi phồn → giản khi đang phát ⇒ **đọc lại chương hiện tại** như khi bật/tắt dịch (`updateTraditionalToSimplifiedSetting` chuyển sang `TTSManager+TranslationIdentity`, dùng chung `rereadCurrentChapter`; trước đây chỉ bỏ prefetch chương sau). Ô tìm của danh sách chương sheet Hẹn giờ chọn tên y như `displayTitle(for:)`. `TTSManager.swift` giảm 34 dòng.
- **Lọc rác**: lọc chạy trên chữ đã chuyển bằng bộ mẫu đã chuyển — `JunkFilterManager.filterRawContent(_:convertsTraditional:)` dựng lười **một lần** bộ quy tắc có mẫu + chữ thay đã chuyển phồn → giản (xoá khi đổi quy tắc), nên mẫu viết bằng chữ phồn vẫn khớp; `ChapterTextNormalizer.normalize(_:convertsTraditional:)` (bản một tham số giữ cho kho lưu trữ / `ChapterDocument`).
- **AI**: quét tên riêng đọc chữ đã chuyển (`AINameScanTextLoader.loadTexts(…convertsTraditional:)`, cờ Reader đã giải ba cấp đi theo `AINameScanChapterTitleStyle`) ⇒ tên quét ra khớp chữ trong truyện và khoá từ điển. Tên chương ở dải tiến độ, sheet chọn phạm vi (`AIBookDataInspector.nameScanChapters`, ưu tiên `title_trans` như mục lục Reader) và `readRawChapterContent` qua pipeline.
- **Mục lục**: tắt dịch ⇒ tên đã chuyển; tìm chương khớp cả tên đã chuyển. `BackgroundPagingWorker`, `BackgroundSearchWorker` (`chapterTitle(_:storedTranslation:_:)`), `ReaderChapterListPageFetcher` + `ChapterListSearchCoordinator` (mục lục online: dòng khớp nay hiện tên đã dịch / đã chuyển thay vì tên gốc), sheet chọn chương tải (`DownloadStartChapterCatalog`, ưu tiên `title_trans`), `ChapterTitleRetranslator`. Chi tiết: tên chương sang `BookDetailView+ChapterTitles.swift` (mới) — cấu hình đọc **một lần** mỗi lượt vẽ (`tocTitleOptions`, đọc `TranslationDisplayRevision` ⇒ mục lục đổi khi popup đổi phồn → giản), `BookDetailTOCView.titleOptions` thay ba closure; chỉ mục tên online (`BookDetailOnlineTOCIndex.Key.options`) dựng cả khi chỉ bật phồn → giản; lượt tự điền tên trống dịch tên đã chuyển. `BookDetailView.swift` giảm 33 dòng.
- **Truyện tranh**: `ComicChapterEntry.convertedTitle` (mới) — tắt dịch vẫn hiện / tìm được tên đã chuyển; `ComicChapterTitleTranslator.displayTitles(for:options:)` dựng tên dịch + tên đã chuyển ngoài main; đổi phồn → giản khi tắt dịch dựng lại tên (`refreshTranslations` không còn chặn khi tắt dịch; lớp dịch ảnh vẫn chỉ khi bật dịch). Màn Dịch khi chạm khối nhận chữ OCR đã chuyển.
- **Xuất TXT** (`DownloadManager`): không dịch vẫn chuyển phồn → giản nội dung + tên chương theo cấu hình truyện (`ChineseTextPipeline.content` / `chapterTitle`).
- **Popup dịch**: dòng phụ hàng Phồn → giản đổi thành "Chuyển chữ phồn thể sang giản thể, có dịch hay không"; hàng luôn hiện, không khoá theo "Dịch văn bản".
- **Đầu trang Reader + nhập TXT** (gộp lúc cherry-pick): `ReaderView.getChapterTitle(at:)` / `translateChapterTitleIfNeeded` qua `ChineseTextPipeline.chapterTitle` ⇒ tên chương ở đầu trang, màn đang tải, màn lỗi chuyển phồn → giản cả khi tắt dịch (trước đây chương chưa có trong cache hiện tên gốc). Nhập truyện TXT ghi `title_trans` đã qua phồn → giản (nguồn `"local"` ⇒ Tất cả); nhập truyện tranh / phim từ file đã chuyển từ 1.3.845.
- **Còn gọi dịch thẳng (cố ý):** cầu `Qt` của `JSExecutor` (hợp đồng tiện ích), tên nguồn Legado, khối OCR truyện tranh (`ComicPageTextTranslator`, tự chuyển trong `translateContent`; lớp dịch ảnh chỉ khi bật dịch).
- **Kiểm chứng:** đọc code + grep chéo mọi chỗ gọi hàm đổi chữ ký; `ChapterTextNormalizer.normalize(` chỉ còn ở kho lưu trữ (`ChapterContentRepository`, `ChapterPersistenceStore`) và trong pipeline. `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. **Chưa build** (Windows), chưa thử máy. Cần thử: (1) Reader tắt dịch, bật / tắt phồn → giản ở popup ⇒ nội dung, tên chương đầu chương, mục lục đổi theo; đang nghe TTS thì đọc lại đúng đoạn, vệt highlight khớp chữ; (2) quy tắc lọc rác viết chữ phồn + bật phồn → giản ⇒ vẫn lọc; (3) bộ dịch tiện ích + phồn → giản: Reader và TTS ra cùng chữ; (4) mục lục truyện tranh tắt dịch + phồn → giản ⇒ tên giản thể, tìm bằng chữ giản; (5) mục lục Chi tiết tìm bằng chữ giản; (6) xuất TXT không dịch ⇒ giản thể; (7) quét tên AI truyện phồn thể ⇒ tên giản thể; (8) widget / màn khoá TTS khi tắt dịch ⇒ tên giản thể.

## [1.3.846] - 2026-11-11

### refactor: thêm hàm chung chuyển phồn → giản rồi dịch cho mọi chữ Trung

Anh Bửu: *"dù bật hay không thì cũng gói trong 1 function, nếu bật phồn->giản thì chuyển phồn giản sang bước dịch -> nếu bật dịch thì dịch khi thì return luôn"*, *"nếu bật phồn giản thì chữ gốc bạn hãy để kết quả sau phồn → giản"*. Đây là phần nền; các màn chuyển sang dùng nó ở các bản kế tiếp.

- **`ChineseTextPipeline`** (mới, `Services/Translation/Pipeline/`): một đường cho mọi chữ Trung — phồn → giản nếu bật (bước riêng, chạy cả khi tắt dịch) ⇒ dịch QT nếu bật ⇒ trả chữ đã chuyển. `Options` (`converts`, `translates`, `dictionaryBookId`) đọc một lần: `options(bookId:packageId:)` cho màn có truyện (Truyện ⇒ Nguồn ⇒ Tất cả, như popup dịch), `sourceOptions(packageId:)` cho màn chưa có truyện (Nguồn ⇒ Tất cả); gợi ý "nguồn tiếng Trung" lấy từ bản ghi tiện ích trong RAM, không dò `plugin.json` trên đĩa. Hàm chữ: `convert`, `meta`, `author`, `chapterTitle` (có bản ưu tiên `title_trans`), `chapterTitleWithMapping`, `content`, `contentWithMapping`, `normalizeChapter` (chuyển **trước** khi chuẩn hoá ⇒ line ID / range UTF-16 tính trên chữ đã chuyển, Reader và TTS cùng toạ độ). Chuỗi ngắn nhớ kết quả chuyển (`NSCache`, ≤ 512 UTF-16).
- **`TranslationConfigSnapshot`** (mới): bản chụp các cấp dịch + phồn → giản, là nơi **duy nhất** giữ luật phân cấp — `TranslationConfigStore.resolveStatus` và `convertsTraditionalToSimplified` chỉ chụp rồi gọi vào. Danh sách dài chụp một lần mỗi lượt dựng (`TranslationConfigStore.shared.snapshot()`). Thêm `convertsTraditionalToSimplified(packageId:)` (Nguồn ⇒ Tất cả).
- **`TranslationDisplayRevision`** (mới, `@MainActor @Observable`): mốc tăng khi cấu hình dịch đổi ở bất kỳ cấp nào, khi công tắc dịch Tất cả đổi (Cài đặt ghi thẳng `UserDefaults`) và khi từ điển / rule đổi — cho danh sách vẽ lại theo popup dịch.
- **Sửa:** `bookId` rỗng không còn đọc / ghi được cấp truyện (`getBookOverride`, `setBookOverride`, `traditionalOverride`, `setTraditionalOverride`) — trước đó ghi "Truyện này" với `bookId` rỗng sẽ thành khoá chung cho mọi item chưa lưu.
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows). Chưa có màn nào gọi hàm mới — hành vi app không đổi ngoài sửa `bookId` rỗng.

## [1.3.845] - 2026-11-11

### fix: phồn → giản thành bước chuyển trước khi dịch, title_trans luôn dùng được, chỉnh phồn → giản ở popup dịch theo phạm vi

Anh Bửu: bấm "Dịch lại tên chương" ở truyện tranh thì hiện bản mới rồi về bản cũ — tắt phồn → giản thì không bị; *"Phồn chỉ là bước chuyển đổi trước khi dịch thôi. Logic hiện tại đang có vấn đề"*. Duyệt cách B (tự dịch lại khi đổi phồn → giản + một lượt lúc mở app), *"đem phồn giản vào popup bật tắt dịch"*, phồn → giản **theo phạm vi** đang chọn, bỏ hàng phồn → giản ở hai màn cài đặt.

- **Nguyên nhân:** `title_trans` luôn được dịch **không** chuyển phồn → giản (`BookActionRunner.retranslateChapterTitles`, Chi tiết tự điền tên trống, nhập file), nên mọi danh sách (mục lục / tìm chương Reader, mục lục Chi tiết, truyện tranh) **bỏ qua** `title_trans` khi truyện bật phồn → giản và dịch sống. Truyện tranh còn nháy: nạp lại hiện `title_trans` một thoáng rồi bản dịch sống về.
- **Ghi:** `ChapterTitleRetranslator` (mới, `Services/ChapterText/`) — chỗ duy nhất dịch lại tên chương: chuyển phồn → giản theo cấu hình của truyện **rồi** dịch (`translateChapterTitle`, có rule tên chương), ghi `title_trans`, báo `chapterTitlesDidRetranslate`. `BookActionRunner` chỉ còn kiểm từ điển + toast. Chi tiết tự điền tên trống và nhập truyện tranh / phim từ file cũng dịch có chuyển.
- **Hiện:** `BackgroundPagingWorker`, `BackgroundSearchWorker`, `BookDetailView.displayTitle(for:)`, `ComicChapterTitleTranslator` **luôn ưu tiên** `title_trans` (kể cả khi bật phồn → giản); không có thì dịch sống có chuyển. Lượt dịch tên chương của truyện tranh chỉ ghi khi tên gốc **và** `title_trans` còn khớp lúc bắt đầu (lượt cũ về muộn không đè bản mới).
- **Ba cấp phồn → giản** (`TranslationConfigStore`): truyện này (khoá cũ `convertTraditionalToSimplified_<bookId>`, vắng = theo nguồn) ⇒ nguồn (`sourceTraditionalOverride` ba trạng thái — dict cũ của phim / nhạc, thêm giá trị `false`) ⇒ Tất cả (`globalConvertsTraditional`, khoá mới, mặc định tắt). Một hàm đọc `convertsTraditionalToSimplified(bookId:packageId:)` cho **mọi** chỗ (Reader, TTS, tải / xuất, chọn chương tải, Chi tiết, truyện tranh, phụ đề / lời); bản chỉ có `bookId` và các chỗ đọc thẳng khoá `UserDefaults` (TTS, chọn chương tải, Reader) đã bỏ.
- **Popup dịch** (`TranslationScopePopupView`): hàng **Phồn → giản** (`TranslationTraditionalToggleRow`) dưới Phạm vi áp dụng; hiện giá trị đang hiệu lực, "Lưu lại" chỉ ghi khi đã gạt, ghi vào **phạm vi đang chọn** (Truyện này / Nguồn này / Tất cả) — `TranslationTraditionalDraft`. Ghi xong ⇒ tự dịch lại tên chương mọi truyện đã lưu có phồn → giản hiệu lực vừa đổi (toast "Đang dịch lại tên chương…"; từ điển chưa nạp ⇒ bỏ lượt).
- **Bỏ** hàng "Văn bản trước khi dịch" ở Cài đặt trình đọc (`ReaderSettingsView`) và Cài đặt dịch truyện tranh. Reader đọc phồn → giản qua `refreshTraditionalConversion()` (mới, `ReaderView+TraditionalConversion`) lúc mở truyện và mỗi khi cấu hình dịch đổi; **không** ghi ngược khoá theo truyện (ghi ngược sẽ biến giá trị kế thừa thành đặt riêng).
- **Một lần sau khi cập nhật:** `ChapterTitleConvertMigration` (mới, gọi từ `MainTabView`, hoãn 20 s, chờ từ điển) dịch lại tên chương của mọi truyện đang bật phồn → giản theo luật mới; xong mới ghi cờ.
- Sheet Dịch phụ đề / Dịch lời: dòng giải thích phồn → giản đổi cho đúng (cùng công tắc với popup dịch). Cấp nguồn của sheet đó vẫn hai trạng thái (Tắt = theo Tất cả).
- `CLAUDE.md` / `AGENTS.md`: luật `title_trans` + phồn → giản ở mục Dịch thuật.
- **Kiểm chứng:** đọc code + grep chéo mọi chỗ gọi `convertsTraditionalToSimplified` / khoá `convertTraditionalToSimplified_`; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới** (`ReaderView` 1942, `TTSManager`, `BookDetailView` không tăng dòng; popup 394). Không build tại chỗ (Windows), chưa thử máy. Cần thử: (1) truyện bật phồn → giản: Dịch lại tên chương ⇒ tên mới ở lại; (2) popup: bật phồn → giản ở Truyện này / Nguồn này ⇒ toast + tên chương đổi; (3) Reader đổi phồn → giản qua popup ⇒ nội dung + mục lục đổi theo; (4) lần mở app đầu: log `📚 [ChapterTitle] Dịch lại tên chương một lần…`. Chưa làm: trang Chi tiết đang mở không tự nạp lại tên sau lượt dịch lại nền (mở lại là thấy).

## [1.3.844] - 2026-11-11

### feat: mục lục truyện tranh có nút dịch lại tên chương như Reader

Anh Bửu: *"nếu dùng title_trans thì nên thêm nút dịch lại tên chương như reader"*.

- Nút **Dịch lại tên chương** (icon dịch 14 pt, khung 32×32, cạnh nút kệ / tải — như mục lục Reader) ở header mục lục truyện tranh; chỉ khi truyện đã lưu (có `Book`, mục lục nằm trong `ChapterStore`) — truyện chưa lưu không có `title_trans`, tên chương vốn dịch thẳng.
- Bấm ⇒ đúng hàm của Reader / Kệ: `BookActionRunner.retranslateChapterTitles(for:)` (từ điển chưa nạp ⇒ báo lỗi; dịch lại mọi tên chương kể cả dòng nhóm bằng `translateChapterTitle`, ghi `title_trans`, toast).
- Xong ⇒ thông báo `chapterTitlesDidRetranslate` (đã có) ⇒ `ComicReaderView` gọi `ComicReaderViewModel.reloadStoredTitleTranslations()` (mới, file `+TitleTranslation`: nạp lại `titleTrans` từ `ChapterStore`, bỏ tên dịch cũ) rồi dịch lại tên đang hiện ⇒ mục lục và thanh trên đổi ngay.
- `CLAUDE.md` / `AGENTS.md`: mục màn đọc comic (mục lục 1.3.843–844).
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows), chưa thử máy. Cần thử: sửa một name có trong tên chương ⇒ bấm Dịch lại tên chương ⇒ toast xong, mục lục + tên chương ở thanh trên đổi theo.

