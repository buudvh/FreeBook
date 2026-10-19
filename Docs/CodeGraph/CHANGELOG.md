# CHANGELOG - Nhật ký Thay đổi CodeGraph FreeBook

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **FreeBook**.

## [1.3.551] - 2026-10-19

### fix: thanh công cụ bàn phím có nền riêng, không lệch khỏi bàn phím

Người dùng (ảnh máy thật, màn "Thêm rule", bàn phím nổi kiểu mới): *"vỡ UI bàn phím"* — sau `[1.3.550]` thanh đã hiện nhưng nổi lơ lửng không nền, chữ của màn bên dưới lộ qua giữa các nút và có khoảng hở với bàn phím.

- **Vì sao**: thanh dựa vào nền `.keyboard` của `UIInputView`, nhưng bàn phím nổi kiểu mới để nền đó trong suốt; `UIHostingController` trong accessory còn tính vùng an toàn nên đệm thêm khoảng trống.
- **`KeyboardTextToolbarView`**: thanh tự có nền — viên kính `.regularMaterial` bo tròn, viền mảnh, cách mép 6pt; tổng cao vẫn 46pt.
- **`KeyboardTextToolbarInstaller`**: `host.safeAreaRegions = []`.
- Chuyển entry `[1.3.521]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI xác nhận biên dịch; chưa thử trên máy.

## [1.3.550] - 2026-10-19

### fix: thanh công cụ bàn phím không hiện ở ô nhập SwiftUI

Người dùng (kèm 2 ảnh chụp máy thật — sheet "Quản lý nghĩa từ" và "Thêm từ mới"): *"fix lỗi thanh trên bàn phím hoàn toàn không được thêm vào"*.

- **Vì sao** (đọc code, chưa xác nhận trên máy): `[1.3.548]` gắn thanh bằng cách gán `inputAccessoryView` lúc `textDidBeginEditing`, nhưng (1) `canAttach` bỏ qua mọi ô "đã có accessory của người khác" — ô `TextField`/`TextEditor` của SwiftUI rất có thể có sẵn accessory nội bộ (cho `.toolbar(placement: .keyboard)`) nên bị bỏ qua hết; (2) lớp nội bộ của SwiftUI có thể override getter / gán đè nên giá trị gán từ ngoài không ăn.
- **`KeyboardAccessoryOverride`** (mới): giữ thanh trong associated object của đúng ô rồi thay getter `inputAccessoryView` của **lớp cụ thể** đó (mỗi lớp một lần) — có gắn thì trả thanh, không thì gọi getter gốc. Không bao giờ thay getter của `UITextField`/`UITextView` gốc.
- **`KeyboardTextToolbarInstaller`**: bỏ `canAttach` (app không có màn nào tự gắn accessory); lớp SwiftUI luôn đi đường thay getter, lớp UIKit gán thẳng rồi đọc lại — không ăn thì chuyển sang thay getter. Ngoại lệ giữ nguyên: ô mật khẩu/API key, `CodeEditorTextView`.
- **Log chẩn đoán** một lần mỗi lớp ô: `⌨️ [KeyboardToolbar] lớp ô …, accessory sẵn có …: <cách gắn>` (cần bật log trong Cài đặt); trường hợp hỏng có `❌` nên luôn được ghi.
- Chuyển entry `[1.3.520]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI xác nhận biên dịch; **chưa thử trên máy** — nếu thanh vẫn không hiện, gửi dòng log `⌨️ [KeyboardToolbar]`.

## [1.3.549] - 2026-10-19

### feat: chặn quảng cáo theo bộ lọc AdGuard, chặn popup và chế độ máy tính cho webview

Người dùng: *"tìm cách nâng cấp chặn quảng cáo trong trình duyệt của freebook… Thêm chế độ mở ở máy tính/điện thoại. bật/tắt chặn quảng cáo cho browser"*, *"có thể config chặn quảng cáo của aloha browser không"*; chốt qua `/grill-me` (plan `Docs/Plans/2026-10-19-plan-chan-quang-cao-trinh-duyet.md`, 3 mockup đã duyệt).

- **Vì sao**: chặn cũ chỉ là 11 chuỗi tên miền (`isEngineDomainBlocked`) xét ở `decidePolicyFor` ⇒ chỉ huỷ được điều hướng trang/iframe; script, ảnh, XHR quảng cáo vẫn tải, và mọi `window.open` của trình duyệt mở thành tab mới. Aloha không lấy cấu hình được (mã đóng) nhưng dùng nguồn công khai: bộ lọc AdGuard.
- **Bộ lọc** (`Sources/Services/Browser/AdBlock/`, 16 file): `WKContentRuleList` từ AdGuard bản tối ưu iOS — bật sẵn Base, Mobile Ads, ABPVN, Chinese; tắt sẵn Popups, Cookie Notices, Tracking. Chuyển đổi bằng **SafariConverterLib 4.3.1** (SPM mới, GPL-3.0 — app vốn đã GPL qua espeak-ng), mỗi bộ một rule list `adblock-<id>`, tự tải lại khi quá hạn `! Expires:` (5 ngày) + nút Cập nhật ngay. Bản đóng gói `Sources/Resources/AdBlock/` (4 bộ, `Scripts/update_adblock_snapshot.py`, `.gitattributes` giữ CRLF cho checksum; bỏ 3 dòng luật bên thứ ba chứa chuỗi bị cấm của repo).
- **Chính sách** `WebContentPolicy` → `WebContentConfigurator`: trình duyệt = chỉnh riêng theo tên miền ?? cài đặt chung; webview tiện ích = `Extension.adBlockOverride ?? chung`, `desktopModeOverride ?? false`; UA track video tự khai thắng chế độ máy tính. Áp cho 5 webview (`BypassBrowserTabStore`, `WebViewLoader`, `VisibleWebViewController`, `VideoEmbedWebView`, `VideoMediaSniffer`), đều chuyển sang `decidePolicyFor:preferences:` để đặt `preferredContentMode`. Gemini/Google Drive giữ nguyên.
- **Chặn popup** (trình duyệt, công tắc riêng): `createWebViewWith` không do bấm link (`!= .linkActivated`) sang tên miền khác ⇒ chặn + dải báo "Đã chặn cửa sổ bật lên" có nút Mở.
- **UI**: nút khiên thay ổ khoá trong ô URL (bảng: Chặn quảng cáo / Xem bản máy tính — nhớ theo tên miền, nạp lại tab); màn **Cài đặt → Trình duyệt** (thay "Trình duyệt hiển thị": chặn QC, chặn popup, 7 bộ lọc + trạng thái, mặc định Điện thoại/Máy tính, trang đã chỉnh riêng, công tắc thu nhỏ cũ); **Cấu hình tiện ích → Trình duyệt** (`+WebContent`, lưu ngay).
- **Dữ liệu**: `Extension` thêm `adBlockOverride`, `desktopModeOverride` (JSON, decode khoan dung; có trong sao lưu/khôi phục); `applicationSupportDirectory/adblock/` (Backup không gói); 4 khoá UserDefaults `web*`.
- **Không làm**: scriptlet/extended CSS (đợt 2), bộ lọc tự thêm, đếm số quảng cáo đã chặn (WebKit không có API).
- Chuyển entry `[1.3.519]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới**; rà soát phản biện bằng agent (chữ ký API SafariConverterLib đối chiếu nguồn v4.3.1, caller của mọi init đổi chữ ký). Không build tại chỗ (Windows) — CI xác nhận biên dịch; **chưa thử trên máy**. Chưa chắc: tab `window.open` dùng chung `WKUserContentController` với tab mẹ, popup tạo bằng `a.click()` có bị báo `.linkActivated` không, và nếu chữ ký `decidePolicyFor:preferences:` lệch SDK thì WebKit không gọi (CI vẫn xanh) — kiểm trên máy theo §8 plan.

## [1.3.548] - 2026-10-19

### feat: thanh công cụ trên bàn phím cho mọi ô nhập, chọn tự tắt bàn phím

Người dùng: *"xoá · sao chép · dán cho các ô nhập của màn hình thêm từ mới (phiên âm NghiTTS), thay thế TTS, quản lý nghĩa từ, sửa từ trong từ điển; bổ sung aa Aa1 Aa2 Aa AA…"* → *"thêm chung trên bàn phím ở mọi chỗ dùng bàn phím trong app"*, *"thêm 1 nút đóng bàn phím ở ngoài cùng bên trái"*, *"thêm config tự tắt/tắt tay"*. Plan: `Docs/Plans/2026-10-19-plan-thanh-cong-cu-ban-phim.md` (mockup đã duyệt).

- **Thanh trên bàn phím** (`Sources/Views/Common/KeyboardToolbar/`): `KeyboardTextToolbarInstaller` nghe `textDidBeginEditing` của `UITextField`/`UITextView` và gắn **một** `inputAccessoryView` dùng chung cho ô vừa bắt đầu gõ — phủ mọi `TextField`, `TextEditor`, `.searchable`, ô trong hộp thoại, thanh URL, ô Mẫu rule mà không sửa từng màn. Trái → phải: nút **đóng bàn phím** · `aa · Aa¹ · Aa² · Aa · AA` · **Xoá · Sao chép · Dán** (icon `AppGlyph`). Thanh nằm trên thanh gợi ý chữ của iOS (không làm mất nó).
- **Luật nút** (`KeyboardTextToolbarModel`): định dạng, Sao chép, Xoá tác động **cả ô**; Dán **chèn tại con trỏ** (thay đoạn bôi đen; ô một dòng đổi xuống dòng thành dấu cách). Sửa chữ đi qua `UITextInput` như gõ phím (`insertText`/`deleteBackward`) nên binding SwiftUI, `.editingChanged` và hoàn tác hệ thống chạy như thường; chữ Telex/VNI đang gõ dở được `unmarkText()` trước. Ô trống ⇒ định dạng/Xoá/Sao chép mờ (đọc lại theo notification + timer 0,5 s vì đổi chữ bằng code không bắn notification).
- **Ngoại lệ**: không có thanh ở ô mật khẩu/API key (`isSecureTextEntry`) và trình sửa Script (`CodeEditorTextView`); ẩn `aa…AA` ở ô tìm kiếm/URL (`UISearchTextField`, bàn phím `.URL`/`.webSearch`, phím Return "Tìm") — 8 ô tìm kiếm tự dựng được gắn `.submitLabel(.search)` (`ReaderSearchView` vốn đã có). Ô trong trang web (`WKWebView`) không có thanh.
- **Định dạng chữ dùng chung** `TextCaseFormatter` (`Sources/Common/Utils/`): luật cũ của panel Dịch; ô nhiều dòng định dạng từng dòng. `ReaderSelectionCoordinator.formatMeaning` gọi sang.
- **Chạm ra ngoài ô nhập**: `KeyboardDismissPreference` (`keyboardDismissOnTapOutside`, mặc định tự tắt) — `KeyboardDismissGesture` không cài recognizer khi chọn "Không tắt bàn phím", đổi lúc bàn phím đang mở có hiệu lực ngay. Chỉnh bằng **giữ** nút đóng bàn phím (menu) hoặc Cài đặt → nhóm mới **"Chung"** → **"Bàn phím & ô nhập"** (`GeneralSettingsSection`, `KeyboardSettingsView`). Nhãn "Không tắt bàn phím" thay "Chỉ tắt bằng nút này" của mockup vì Return và kéo danh sách vẫn tắt bàn phím.
- **Gỡ bộ nút theo từng ô** (đã có thanh chung): Cấu hình tiện ích + plugin.json (`TextFieldClipboardButtons` xoá; giữ nút ↺ khôi phục mặc định thành `RestoreDefaultValueButton`), Thêm từ nhiều dòng, Bộ nhớ AI, Cài đặt AI (đồng bộ key/model vẫn qua `.onChange`), ô Mẫu/Bản dịch của rule, ô chữ thử VieNeu (giữ nút Phát), nút Dán của panel Dịch Reader.
- **Không đổi**: hàng `aa…AA` của panel Dịch, nút sao chép tin nhắn AI / log / debug / chẩn đoán, dữ liệu.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới**; grep không còn `TextFieldClipboardButtons|clipboardToolbar(|pasteFromClipboard|appendClipboard`. Không build tại chỗ (Windows) — CI xác nhận biên dịch; chưa thử trên máy.

## [1.3.547] - 2026-10-19

### fix: hàng nút và ô nhập ở màn cấu hình tiện ích khớp mockup

Người dùng (kèm ảnh chụp máy thật): *"phần cấu hình tiện ích mockup đẹp mà kết quả thật xấu quá"*, *"Trình duyệt · Bỏ ghim · Gỡ phần này còn chưa đẹp"* (chọn kiểu nút tròn), *"thêm bộ 3 nút clear, copy, paste những chỗ nhập text"*.

- **Vì sao**: `[1.3.546]` dựng hàng nút bằng `Label` trong một dòng `Form` — iOS dàn icon và chữ ra hai đầu ô, chữ bị co. Mockup vẽ với giá trị ngắn, còn biến cấu hình thật toàn URL dài: ô nhập đặt bên phải chỉ còn vài ký tự, dòng phụ "mặc định https://…" xuống 3–4 dòng.
- **`ExtensionConfigHeaderCard`**: hàng **Trình duyệt · Ghim · Gỡ** thành nút tròn 44pt (icon 18pt semibold) + nhãn `.caption` bên dưới, chia đều; đã ghim thì vòng cam nhạt, icon cam; Gỡ icon + nhãn đỏ.
- **`TextFieldClipboardButtons`** (mới, `Sources/Views/Common/`): bộ nút ô một dòng ↺ khôi phục mặc định (chỉ hiện khi khác mặc định) · xoá · sao chép · dán — cùng dáng `clipboardToolbar` (28×26, dán tô màu nhấn, icon `AppGlyph`), nhưng **dán thay cả giá trị** (đã bỏ khoảng trắng đầu/cuối).
- **Dòng "Cài đặt của tiện ích"** (`+GlobalConfig`): ô chữ = tiêu đề + khoá (chữ đều, một dòng), bộ nút bên phải, ô nhập nền mờ **rộng hết dòng** ở dưới, mặc định là chữ mờ trong ô; bỏ "mặc định …" khỏi dòng phụ. Ô số gọn bên phải (90pt), công tắc giữ chỗ.
- **Màn "Thông tin plugin.json"** (`ExtensionMetadataSection`): 4 ô chữ `name`, `source`, `regexp`, `description` có cùng bộ nút (không có ↺); vẫn tự lưu 0,4 s như gõ tay.
- **`ExtensionConfigView`**: `.listSectionSpacing(.compact)` bớt khoảng trống giữa các nhóm và phía trên thẻ đầu.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI xác nhận biên dịch; chưa thử trên máy.

## [1.3.546] - 2026-10-19

### feat: kiểu hiển thị danh sách truyện theo loại, làm lại màn cấu hình tiện ích

Người dùng: *"tôi muốn thay tuỳ chỉnh hiển thị layout của danh sách truyện (bao gồm tab kệ sách và tab khám phá)"* và *"mockup lại phần cài đặt cấu hình ext… bỏ nút mở trình duyệt ở phần chọn ext của khám phá và mang vào trong cấu hình ext"*. Plan: `Docs/Plans/2026-10-18-plan-kieu-hien-thi-danh-sach-va-cau-hinh-tien-ich.md` (mockup đã duyệt trong phiên phỏng vấn). Nhánh `feature/list-layout-ext-config` tách từ `main` sau khi `feature/comic-video` được fast-forward vào `main`.

- **Kiểu hiển thị** (`Sources/Views/Common/BookListLayout/`): ba kiểu `BookListLayoutMode` — Danh sách (mặc định, như cũ) / Lưới / Chỉ bìa; lưới 2–5 cột (mặc định 3). Lưu **theo loại nội dung** (`BookListLayoutScope`: Tất cả · Truyện chữ · Truyện tranh · Phim/Video), dùng chung giữa Kệ và Khám phá, trong `BookListLayoutPreferences` (`@MainActor @Observable`, khoá `bookListLayout.mode.<scope>` / `bookListLayout.columns.<scope>`; tự vào bản sao lưu vì khoá bắt đầu bằng chữ thường; nạp lại theo `UserDefaults.didChangeNotification` để khôi phục sao lưu có hiệu lực). Bìa video ngang 16:9, còn lại (kể cả "Tất cả") đứng 2:3.
- **Đổi kiểu**: sheet nhỏ `BookListLayoutSheet` ("Áp cho: <loại>", thanh chọn kiểu + Số cột) mở từ menu "…" của Kệ (tab Kệ/Lịch sử), nút tròn mới trên header Khám phá, thanh điều hướng màn Thể loại/Xem thêm, menu của Bộ sưu tập; và Cài đặt → Thư Viện → **Kiểu hiển thị danh sách** (`BookListLayoutSettingsView`, 4 nhóm + "Đặt lại mặc định").
- **Phía kệ**: `ShelfBooksLayoutView` dựng Kệ sách, Lịch sử, chi tiết Bộ sưu tập, Tìm trên kệ — nhánh danh sách giữ `List` cũ, nhánh lưới là `ScrollView` + `LazyVGrid` (không bao giờ lồng trong `List`), giữ nhóm Đang ghim/Truyện khác, nhóm theo ngày, phân trang 50/lượt, chạm/giữ bằng `onTapGesture` + `onLongPressGesture`. Thẻ `ShelfBookGridCardView`: ghim (trên-trái), chương mới (trên-phải), badge loại (dưới-phải), "icon nguồn · Ch. N" ("Tập N" với video). **Chip lọc loại** (`ShelfKindFilter` + `ExtensionKindFilterBar`, `@AppStorage("shelfKindFilter")`) ở đầu trang Kệ và Lịch sử, chỉ hiện khi có ≥ 2 loại; "Xóa tất cả lịch sử" chỉ xoá truyện đang hiện theo chip. Hai trang dời sang `ShelfView+Layout.swift` (`ShelfView` 873 → 684 dòng); header nhóm thành `ShelfSectionHeaderView`; luật dịch tên của danh sách đã lưu gom về `BookDisplayTranslation`.
- **Phía Khám phá**: `DiscoveryNovelsLayoutView` dùng chung cho tab danh mục (`DiscoveryCategoryTabView`, tách sang file riêng) và `CategoryNovelsListView`; cả hai nhánh giữ `.id(link)`, neo cuộn, kéo làm mới, sentinel tải thêm. Thẻ `DiscoveryNovelGridCardView` tải bìa bằng `RemoteCoverImage` (không ghi `covers/`). Skeleton dạng lưới `DiscoverySkeletonGridView`. Trang dạng section **không đổi**.
- **Bỏ nút safari** ở header Khám phá và ở từng dòng bảng chọn nguồn (`ExtensionSelectorView`, tách khỏi `DiscoveryView`; `DiscoveryView` 975 → 600 dòng). Trình duyệt của nguồn chỉ còn mở từ màn Cấu hình tiện ích.
- **Màn Cấu hình tiện ích**: thẻ đầu `ExtensionConfigHeaderCard` (icon, tên, tác giả · phiên bản, loại, ngôn ngữ, mô tả "Xem thêm") với hàng nút **Trình duyệt · Ghim · Gỡ**; các nhóm "Cài đặt của tiện ích", "Duyệt và lịch sử" (18+ thành bộ chọn Tự động/Có/Không), "Mạng", "Nâng cao" (màn con `ExtensionMetadataScreen` "Thông tin plugin.json", sửa Script). **Tự lưu tất cả**: bỏ "Lưu"/"Hủy", chỉ còn "Đóng"; công tắc ghi ngay, ô chữ ghi sau 0,4 s, đóng màn thì ghi nốt (`ExtensionMetadataSection` cũng đổi từ huỷ sang ghi nốt khi rời màn). "Import truyện" từ trình duyệt: mở từ Khám phá thì Chi tiết hiện ở Khám phá như cũ, nơi khác thì hiện ngay trong màn Cấu hình.
- **Sửa kèm**: giá trị bool đã lưu trong `configJson` bị đọc lại thành `"1"`/`"0"` (công tắc luôn hiện tắt, lần lưu sau ghi `true` thành `false`) — nhận diện bool thật qua `CFBoolean`.
- **Không đổi**: `@Model`/schema, Tìm kiếm toàn nguồn, Gợi ý, sheet chọn truyện ở Từ điển, tab Tải về, hộp xác nhận và luật chặn gỡ tiện ích đang là giọng TTS.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền (`JSDom.swift`, `TTSManager.swift`), **0 mới**; mọi file mới ≤ 400 dòng, 1 type chính/file. Không build tại chỗ (Windows, không có `swiftc`) — CI xác nhận biên dịch; chưa thử trên máy.

## [1.3.545] - 2026-10-19

### feat: mục lục video dùng tab theo section ở chi tiết và trình phát

Người dùng: *"mục lục ở chi tiết sửa mockup lại (để các tab vietsub, thuyết minh chọn được, đừng chia theo cụm tập"* và *"các phân mục lục khác của video cũng chia theo tab section"*. Mockup: `Docs/Mockups/2026-10-19-mockup-detail-toc.html`, `Docs/Mockups/2026-10-19-mockup-video-episode-list.html`.

- **Vì sao**: `[1.3.543]` cắt mục lục thành cụm 24 tập (`1–24`, `25–48`…) — mốc số vô nghĩa với người xem, còn tên nhóm (`section`) thì có nghĩa. Trình phát thì ngược lại: vẫn vẽ tiêu đề nhóm chen giữa lưới nên muốn xem nhóm khác phải cuộn qua hết nhóm trước.
- **`BookDetailVideoTOCGrid`**: bỏ hẳn `chunkSize` / `maxRowsPerGroup` / `RangeGroup` / `ordinal`; `SectionGroup` = đúng một section, hàng tab chia đều khi ≤ 3 nhóm và cuộn ngang khi nhiều hơn; badge cạnh tiêu đề đếm theo tab đang mở; `endLabel` theo tên nhóm.
- **Số tập**: đánh lại 1…N **trong từng tab** (giảm dần thì đánh ngược), chạm ô vẫn trả `index` thật. `BookDetailTOCView.videoRows` không còn tính `ordinal`, bỏ luôn tham số `totalCount`.
- **`VideoEpisodeGridView`** (dùng chung cho `VideoEpisodePanel` toàn màn và `VideoPlayerDetailsView` màn dọc): viết lại thành tab + lưới 4 cột ô 46pt, bỏ tiêu đề nhóm chen giữa lưới; `init` chọn sẵn tab chứa `currentEpisodeIndex` để `scrollTo` của màn cha vẫn tìm thấy ô; đổi tab **không** đổi tập đang phát.
- **Tìm kiếm**: ẩn hàng tab, lưới trải trên mọi nhóm (không kẹt trong tab đang mở).
- **Không đổi**: tầng dữ liệu (`session.episodes` / `currentEpisodeIndex` / `chapterSnapshots`), nhánh truyện chữ / truyện tranh, nút tải hàng loạt của `[1.3.544]`.
- **Kiểm chứng**: `swiftc -parse` sạch 6 file; `check_architecture.py` 2 violation nền, **0 mới**; `BookDetailVideoTOCGrid` 370 dòng, `+Groups` 79, `BookDetailTOCView` 378, `VideoEpisodeGridView` 197. Không build tại chỗ (Windows) — CI xác nhận biên dịch.

## [1.3.544] - 2026-10-19

### feat: thêm nút tải hàng loạt trong danh sách chương của reader

Người dùng: *"thêm cả nút download vào danh sách chương của reader"* → *"ở reader chữ, giống chức năng tải truyện khi nhấn giữ ở kệ và lịch sử"* → *"thêm nút tải hàng loạt cho cả reader comic"*. Mockup: `Docs/Mockups/2026-10-19-mockup-bulk-download.html`. Plan: `Docs/Plans/2026-10-19-plan-reader-toc-bulk-download.md`.

- **Hiện trạng**: reader chữ đã có nút tải **từng chương** (1.3.334, ẩn khi `!canDownloadChapters`); comic chỉ hiện dấu "đã tải", chưa có tải lẻ; cả hai chưa có tải cả bộ.
- **Reader chữ**: `bulkDownloadButton` (icon `arrow.down.to.line`) chèn **đầu** hàng nút ở header danh sách chương; `.sheet` ở gốc view mở `TaskOptionsSheet(book:taskType:.download)` — đúng sheet mà nhấn-giữ ở Kệ/Lịch sử vẫn mở, nên không nhân đôi logic tải. Ẩn cùng điều kiện `canDownloadChapters`.
- **Comic**: `ComicReaderView` giữ `Book` đã đọc trong `bootstrap()` vào `@State localBook` (trước đây đọc xong bỏ); `ComicChapterListSheet` nhận `book`, thêm nút ở `topBarLeading` ("Tải ảnh offline") + sheet lồng mở cùng `TaskOptionsSheet`.
- **Không làm**: không thêm tải lẻ cho comic; không đổi `TaskOptionsSheet` / `DownloadManager` / coordinator; không tạo hàng `Book` mới (nút ẩn khi sách chưa có trong thư viện).
- **Kiểm chứng**: `swiftc -parse` sạch 7 file; `check_architecture.py` 2 violation nền (`JSDom.swift`, `TTSManager.swift`), **0 mới**; `ReaderChapterListView` 337 dòng, `+Download` 94, `ComicChapterListSheet` 135, `ComicReaderView` 273. Không build tại chỗ (Windows) — CI xác nhận biên dịch.

## [1.3.543] - 2026-10-19

### feat: mục lục dạng lưới tập cho màn chi tiết video

Người dùng: *"sửa lại mục lục detail của video thành Đề xuất B"*. Mockup: `Docs/Mockups/2026-10-19-mockup-detail-toc.html`. Plan: `Docs/Plans/2026-10-19-plan-detail-video-toc-grid.md`.

- **Vì sao**: tab "Mục lục" của màn Chi tiết vẽ mỗi chương một hàng có `Divider`; phim 60–120 tập thì danh sách rất dài, hàng không có số tập, tiêu đề nhóm không gấp được, và tập đang xem chỉ khác hàng thường ở `.white` ≈ `.primary` trong dark mode (`BookDetailTOCView.swift:155`).
- **Mới — `BookDetailVideoTOCGrid`** (+ `BookDetailVideoTOCGrid+Groups.swift`): thanh công cụ dính (số tập + pill "Cũ nhất/Mới nhất" có nhãn + kính lúp bung ô tìm), chip chia khoảng dựng từ dòng `section` (nhóm > 60 tập tự cắt khúc 24), lưới 4 cột ô 46pt (đang xem = đảo màu, đã xem = mờ 36%, đã tải = chấm 4pt), chân "Hết …".
- **Số tập**: ô hiển thị `ordinal` 1…N đếm bỏ qua dòng section, chạm ô trả về `index` thật; sắp xếp giảm dần thì `ordinal` đánh từ N về 1 nên số trên ô vẫn là số tập thật.
- **`BookDetailTOCView`**: thêm `isVideo` (mặc định `false`), `body` rẽ nhánh bằng `Group`; `videoRows` giữ đúng thứ tự ưu tiên `chapterSnapshots` → `Book.chapters` → `onlineChapters`; tìm kiếm dùng chung `chapterSearchQuery`.
- **`BookDetailView`**: truyền `isVideo: contentKind == .video`.
- **Sửa kèm**: nút cuối danh sách dùng `"Tải thêm \(episodeNoun)"` thay vì hardcode "chương" (`BookDetailTOCView.swift:229`).
- **Không đổi**: nhánh truyện chữ / truyện tranh, `navigationTitle`, tầng dữ liệu (không ghi SwiftData).
- **Kiểm chứng**: `swiftc -parse` sạch 7 file; `check_architecture.py` 2 violation nền (`JSDom.swift`, `TTSManager.swift`), **0 mới**; `BookDetailVideoTOCGrid` 371 dòng, `+Groups` 98, `BookDetailTOCView` 396 (< 400). Không build tại chỗ (Windows) — CI xác nhận biên dịch.

## [1.3.542] - 2026-10-19

### fix: menu dịch ở khám phá mặc định đúng phạm vi nguồn, không hiện "Truyện này"

Người dùng: *"ở khám phá, dịch văn bản không có lựa chọn truyện này nhưng mặc định nó luôn hiển thị truyện này, bấm mở select nó mới đổi lại chọn nguồn này"*. Plan: `Docs/Plans/2026-10-19-plan-discovery-translation-scope-default.md`.

- **Nguyên nhân**: `ReaderTranslationScopeMenuView.selectedScope` khởi tạo cứng `.book` (`:27`), còn `preparePopupState()` chỉ sửa nó trong action của nút nên nội dung popover vẽ lần đầu vẫn đọc `.book`; `scopeDisplayText` đọc thẳng `selectedScope`. Khám phá truyền `bookId: ""` (`DiscoveryView.swift:167`) nên `Menu` không có mục "Truyện này" mà nhãn vẫn ghi "Truyện này", mở `Menu` lần nữa mới vẽ lại sang "Nguồn này". Kèm hệ quả: bấm "Lưu lại" ngay sẽ gọi `setBookOverride(bookId: "", …)` — ghi override rác với khoá rỗng.
- **Sửa**:
  - `availableScope(bookId:packageId:)` (hàm thuần) chọn cấp có thật: truyện → nguồn → toàn cục; dùng ở `init` để state bắt đầu đúng ngay từ lần vẽ đầu.
  - `effectiveScope` kẹp `selectedScope` về cấp có thật; `scopeDisplayText`, dấu checkmark trong `Menu` và `saveSettings` đều dùng nó ⇒ không hiện/ghi "Truyện này" khi `bookId` rỗng.
  - `refreshStatus()` kẹp lại khi `bookId`/`packageId` đổi (đổi nguồn ở Khám phá).
- **Giữ nguyên**: Reader và BookDetail (bookId khác rỗng) vẫn mặc định "Truyện này" như cũ.
- **Kiểm chứng**: `swiftc -parse` sạch; `check_architecture.py` 2 violation nền (`JSDom.swift`, `TTSManager.swift`), **0 mới**; file 307 dòng < 400. Không build tại chỗ (Windows) — CI chỉ xác nhận biên dịch.

## [1.3.541] - 2026-10-19

### fix: giữ mục lục ở chi tiết sau khi đọc ngay, đồng bộ lại khi đóng reader

Người dùng: *"xảy ra lỗi khi bấm đọc ngay rồi back về dễ xảy ra trường hợp mất mục lục ở chi tiết … trên 1000 chương mất rồi có, trên 4000 thì mất luôn"*. Log `app_logs (172).txt` chốt được nguyên nhân.

- **Bằng chứng log**: `[ChapterStore Save] mode=replaceFullTOC items=7243 stored=7243 … status=success` rồi `[ReaderBootstrap] totalChapters=7243 source=ChapterStore` ⇒ **DB không mất chương**. Sau `reader_disappear` không có dòng log nào (không `toc.js`, không lỗi) ⇒ màn Chi tiết không nạp lại.
- **Nguyên nhân**: Reader mở bằng `.fullScreenCover(item: $readerRoute)` không có `onDismiss:` nên `onAppear` của màn Chi tiết không chạy lại khi cover đóng. Sách mới đọc lần đầu chỉ có mục lục trong RAM (`onlineChapters`); `chapterSnapshots` và `chaptersList` rỗng. `startReading` tạo sách ⇒ `localBook` khác nil, mà `BookDetailTOCView` chọn nguồn vẽ `chapterSnapshots` → `localBook != nil` → `filteredLocalChapters`, tức `Book.chapters` — **luôn rỗng** vì `enableSwiftDataTOCWrite = false` ⇒ 0 dòng, trong khi tiêu đề vẫn ghi số chương của `onlineChapters`.
- **F1 — `BookDetailTOCView`**: nhánh `filteredLocalChapters` chỉ dùng khi danh sách **không rỗng**; còn lại rơi xuống `onlineChapters`. Không bao giờ bỏ danh sách đang giữ trong RAM.
- **F2 — `BookDetailView`**: thêm `onDismiss:` cho `fullScreenCover` của Reader → `syncChaptersList()`, `updateFilteredLocalChapters()`, `updateFilteredOnlineChapters()`. Chỉ đọc DB, không gọi mạng (mục lục vừa được `startReading` ghi đủ).
- **F3 — `loadTOCDataOnly`**: guard "Tải thêm chương đang chạy" chỉ bắn khi `onlineChapters` đã có dữ liệu (trước đây bắn cả khi rỗng ⇒ tắt `isLoadingTOC` mà không gán gì = màn trắng, không nút "Tải lại"); khi phải gán trang 1 của nguồn nhiều trang thì mở lại cờ `remainingPagesLoaded` để nút "Tải thêm chương" hiện lại.
- **Kiểm chứng**: `swiftc -parse` hai file sạch; `check_architecture.py` 2 violation nền (`JSDom.swift`, `TTSManager.swift`), **0 mới**; `BookDetailView.swift` 1128/1201 dòng baseline. Không build tại chỗ (Windows) — CI chỉ xác nhận biên dịch.
- Plan: `Docs/Plans/2026-10-19-plan-toc-loss-after-read.md`.

## [1.3.540] - 2026-10-19

### Revert "fix: mọi danh sách và tên truyện dịch theo cờ của truyện rồi tới nguồn"

Người dùng yêu cầu lùi nội dung commit `6bdc424` (entry `[1.3.538]`). Revert bằng `git revert --no-commit 6bdc424`, giữ nguyên `[1.3.539]` (commit sau, không liên quan).

- **Xoá file**: `Sources/Services/Translation/Utils/TranslationConfigSnapshot.swift`, `Sources/Views/Search/SearchView+Translation.swift`.
- **`TranslationConfigStore`**: bỏ hàm dùng chung `resolve(global:bookOverride:sourceOverride:packageId:isChineseSourceHint:)`, `resolveStatus` trở lại đọc `globalEnabled` + hai bảng override tại chỗ.
- **`TranslateUtils.translateBookTitleIfNeeded`**: bỏ tham số `packageId`, điều kiện trở lại cờ toàn cục `isTranslationEnabled`.
- **View**: `BookListItemView`, `CategoryNovelsListView`, `DiscoveryNovelRowView`, `DiscoveryView`, `ExploreBannerView`/`ExploreItemCard`/`ExploreListRow`/`ExploreRenderContext`/`ExploreSectionsView`, `SearchView`, `ComicReaderView`, `DownloadTrackerView`, `TaskOptionsSheet`, `BookActionSheet`/`BookActionRunner`, `NotificationInboxView`, `ReaderView`, `DictionaryListView+Transfer`, `ShelfView+BookImport`, `DownloadManager+TaskStore` trở lại đọc công tắc dịch **toàn cục** (`@AppStorage("isTranslationEnabled")`) thay vì cờ Truyện > Nguồn > Toàn cục. `TTSManager` trở lại `TranslateUtils.isTranslationEnabled`.
- **Xung đột đã xử lý**: `SearchView.swift` auto-merge sạch — thay đổi của `[1.3.539]` (`fetchFullTOC`) còn nguyên. Hai file `Docs/CodeGraph/CHANGELOG*.md` xung đột: giữ nguyên lịch sử (không đẩy entry cũ trở lại `CHANGELOG.md`, không thêm lại entry vào archive).
- **Kiểm chứng**: grep `Sources/` không còn tham chiếu `TranslationConfigSnapshot`, `translationRevision`, `currentTranslationConfig`; mọi call site `translateBookTitleIfNeeded` khớp chữ ký mới. **Không build tại chỗ** (Windows) — chỉ CI xác nhận biên dịch.

## [1.3.539] - 2026-10-18

### fix: chặn mục lục rỗng xoá chương, khớp chương theo url, sửa tải thêm chương

Làm theo báo cáo `Docs/Reports/2026-10-18-toc-update-investigation.md` (đề xuất P1–P4; người dùng duyệt plan trong chat). Báo cáo chỉ ra ba lỗi gây mất dữ liệu. Thứ nhất, script `toc` trả `[]` (trang chặn/captcha) thì `replaceFullTOC` xoá sạch mục lục cùng liên kết tới chương đã tải trong `.bin`. Thứ hai, khoá đối chiếu `(url, index)` làm mất cache của mọi chương phía sau chỉ vì nguồn thêm/xoá một chương. Thứ ba, "Tải thêm chương" bấm lại sau lỗi chạy lại từ trang 2 với chỉ số đã phình, ghi chương trùng vào DB.

- **P1 — chặn mục lục rỗng**:
  - `ChapterStoreDatabase.replaceFullTOC` từ chối mảng rỗng khi DB đang có chương: ghi log `❌`, ném `ChapterStoreError.invalidContent`, không xoá gì (giống `importBookMigration`). Đây là lưới an toàn cho mọi đường ghi.
  - Tầng tải: `BookDetailLoader.requireChapters` coi một trang mục lục rỗng là lỗi ("Nguồn trả về mục lục trống" / "Trang mục lục k/N không có chương nào"). Áp ở `fetchFirstPageTOC`, `fetchRemainingPages`, `fetchFullTOC` và vòng lặp trang của `startReading` / "Tải thêm chương". Gặp lỗi thì không ghi gì.
  - Riêng **trang cuối** của mục lục nhiều trang được phép rỗng, chỉ ghi log `⚠️`, vì `page.js` hay thừa một trang. Nếu không, cả truyện sẽ không làm mới, tải thêm hay dò chương mới được nữa. Đánh đổi: nếu bị chặn đúng ở trang cuối thì mất cache của các chương trang đó.
  - Đổi nguồn: mục lục mới rỗng thì báo lỗi **trước** khi tạo sách mới, sách cũ giữ nguyên.
- **P2 — `page()` trả `[]`**: thêm `BookDetailLoader.fetchFullTOC`. `page.js` rỗng thì dùng url chi tiết, trang đầu là `pages.first`, giống `fetchFirstPageTOC` và `NewChapterProbe`. Hàm này dùng ở kéo làm mới BookDetail, làm mới trong Reader (trước đây `page.js` trả `[]` ở hai chỗ này = 0 chương ⇒ xoá sạch) và đổi nguồn (trước gọi `toc(link chi tiết)` rồi mới `page`).
- **P3 — khớp theo url**:
  - `CompositeKey` tách ra file riêng, thêm `reconcile(url:index:)`: url rỗng mới khớp theo chỉ số. `candidateMap(for:)` gộp đoạn dựng bảng đối chiếu từng lặp ở `replaceFullTOC` và `upsertPage`; cùng url nhiều hàng (rác của bản cũ) thì hàng đã cache đứng trước.
  - Khớp url thì giữ `id`/`is_cached`/`offset`/`length`/tên dịch, chỉ cập nhật `chapter_index`.
  - Nhánh `.appendOnly` dùng bảng ứng viên rỗng để chương đuôi trùng url không kéo hàng cũ đi.
  - Mở BookDetail với nguồn nhiều trang chỉ ghi trang 1 khi DB **chưa** có mục lục. Lý do: riêng trang 1 không đủ để đối chiếu, khớp theo url sẽ kéo các chương đầu trang 2 lên và làm hở chỉ số. Đọc số chương lỗi thì coi như đã có (không ghi).
  - `BackupChapterRestorer.mergeIntoExisting` không thêm lại chương mà url đã có ở chỉ số khác trên máy. Nếu thêm, `upsertPage` giờ sẽ chuyển chỉ số hàng đó và để lại lỗ.
- **P4 — "Tải thêm chương"**:
  - `@State loadedRemainingPageCount` đếm số trang sau trang 1 đã nối vào `onlineChapters`. Bấm lại sau lỗi/huỷ thì tải tiếp từ trang lỗi.
  - Lượt tải tích luỹ cục bộ `base + fetched`, không nối vào `self.onlineChapters`. Nếu kéo làm mới vừa nạp đủ mục lục (`remainingPagesLoaded`) thì lượt tải tự dừng, tránh nhân đôi chương.
  - Sau khi ghi có `checkCancellation`, nên lượt đã bị huỷ không đè cờ/`loadingTask` của lượt mới hơn và không mở sheet tải.
  - Không ghi từng trang nữa: đủ trang mới ghi **một** `replaceFullTOC` mục lục đầy đủ (dọn hàng thừa/trùng), rồi làm mới danh sách và chạy lượt dịch tên chương nền.
  - `prepareForTask` (tải/xuất) bỏ qua trang đã tải và cũng ghi mục lục đầy đủ. `startReading` bỏ qua trang đã tải. Cả hai và `reloadBookData` huỷ lượt "Tải thêm chương" đang chạy. `loadTOCDataOnly` không ghi đè `onlineChapters` bằng trang 1 khi các trang sau đang/đã được nối.
  - `tocMetadata(from:)` bỏ tham số `startIndex` (không còn caller).
  - `reloadBookData` bật `remainingPagesLoaded` cùng lúc với danh sách đầy đủ, sau khi ghi. Nhờ vậy ghi lỗi thì cờ không bật trên danh sách thiếu.
- **Không làm**: P5–P8 của báo cáo (mục lục co bất thường, neo `currentChapterIndex` ở tầng chung, đổi nguồn khớp theo tên, khôi phục sao lưu khớp theo url).
- **Kiểm chứng**: một agent con rà phản biện: không thấy lỗi biên dịch; các lỗi logic nó tìm ra đã sửa ở trên. `check_architecture.py` **2 violation, 0 mới**. Không build tại chỗ (Windows); CI chỉ xác nhận biên dịch.

## [1.3.538] - 2026-10-18

### fix: mọi danh sách và tên truyện dịch theo cờ của truyện rồi tới nguồn

> **Đã bị revert ở `[1.3.540]`** — mục này chỉ còn giá trị lịch sử; code hiện tại quay về trạng thái của `[1.3.537]`.

Tiếp theo 1.3.537. Người dùng yêu cầu rà mọi chỗ còn lỗi tương tự và sửa luôn, nhớ tính cả cờ theo truyện. Dịch có 3 cấp, ưu tiên Truyện > Nguồn > Toàn cục (`TranslationConfigStore`), nhưng nhiều view vẫn đọc thẳng công tắc toàn cục `@AppStorage("isTranslationEnabled")`. Vì vậy tắt dịch cho một nguồn hay một truyện thì danh sách vẫn dịch.

- **Snapshot dùng chung**: thêm `TranslationConfigSnapshot`. Nó đọc cấu hình đè **một lần mỗi lượt vẽ**, rồi áp đúng thứ tự ưu tiên của store qua hàm `resolve` vừa tách khỏi `resolveStatus`. Nhờ vậy danh sách dài không phải tra `UserDefaults` cho từng dòng. Các màn mở lâu nghe `TranslationConfigStore.didChangeNotification` để vẽ lại ngay khi người dùng đổi cấu hình.
- **Theo truyện**:
  - `BookListItemView` (kệ, lịch sử, bộ sưu tập, sheet chia sẻ/nhập)
  - `ComicReaderView`, `DownloadTrackerView`, `TaskOptionsSheet`, `BookActionSheet`, `NotificationInboxView`
  - `ReaderView` (một chỗ), `TTSManager` (thay tại chỗ, **không thêm dòng**)
  - `TranslateUtils.translateBookTitleIfNeeded`: thêm `packageId: String? = nil`; đã cập nhật 8 nơi gọi. Trước đây hàm này nhận `bookId` mà vẫn kiểm cờ toàn cục.
- **Theo truyện, không có cờ riêng thì theo nguồn**, cho item chưa lưu thành sách:
  - các dòng `DiscoveryNovelRowView` và `CategoryNovelsListView`
  - thẻ, dòng, banner của trang explore
  - Tìm kiếm, cả hai chế độ (`SearchView+Translation`)
  - Mã truyện suy ra từ `BookIdUtils.make(packageId, link)`, cùng hai dạng id cũ.
- **Theo nguồn**: tiêu đề section, chip, thể loại, tiêu đề màn "Xem thêm".
- **Giữ toàn cục**: các màn Cài đặt dịch và công tắc nhanh ở Kệ, vì đây là nơi đặt giá trị toàn cục.
- **Lưu ý**:
  - Truyện bị gán UUID qua `resolveBookId` thì ở Khám phá/Tìm kiếm rơi về cờ của nguồn.
  - Tên truyện trên màn khoá theo cờ của phiên TTS đang phát, nên đổi cờ giữa chừng thì phải phát lại mới thấy.
- **Kiểm chứng**: `check_architecture.py` **2 violation, 0 mới**. Không build tại chỗ (Windows); CI chỉ xác nhận biên dịch.

## [1.3.537] - 2026-10-18

### fix: danh sách truyện ở Khám phá theo công tắc dịch của nguồn

Người dùng báo: tắt dịch cho một nguồn rồi mà danh sách truyện ở Khám phá vẫn dịch.

- **Nguyên nhân** (hồi quy từ 1.3.533): hai view tạo mới cho Khám phá đọc công tắc dịch **toàn app** (`@AppStorage("isTranslationEnabled")`), không đọc cờ **theo nguồn** của `TranslationConfigStore` mà `DiscoveryView` vẫn tính và truyền xuống. Hai view đó là:
  - `DiscoveryNovelRowView`: dòng truyện ở tab `home` và màn "Xem thêm".
  - `CategoryNovelsListView`.
- **Sửa**:
  - `DiscoveryNovelRowView` nhận `isTranslationEnabled` qua tham số. Ở `DiscoveryCategoryTabView`, view cha truyền đúng cờ theo nguồn nó đang có.
  - `CategoryNovelsListView` tự tính cờ theo nguồn bằng `TranslationConfigStore.isTranslationEnabled(bookId: "", packageId:, isChineseSourceHint:)`, giống `DiscoveryView`. Cờ này áp cho cả dòng truyện lẫn tiêu đề màn.
  - Trang `explore` (section) vốn đã nhận cờ theo nguồn từ view cha nên không cần đổi.
- **Không đổi**: `BookListItemView` (kệ, lịch sử…) vẫn dùng công tắc toàn app như trước bản này.
- **Kiểm chứng**: `check_architecture.py` **2 violation, 0 mới**. Không build tại chỗ (Windows); CI chỉ xác nhận biên dịch.

## [1.3.536] - 2026-10-18

### fix: phát kèm luồng tiếng audios của track, sửa Dailymotion mất tiếng

Log người dùng gửi (bản 1.3.535) ghi rõ: tiện ích «Dailymotion», nguồn "link tiện ích trả thẳng (native)", "track: 1 hình, 0 tiếng, không có nhóm audible". Giải mã script của tiện ích này cho thấy nó trả `data` là playlist con **chỉ có hình** của một chất lượng, còn luồng tiếng nằm ở `audios: [{data, url, headers, type, label, language}]` (thêm `audio` dạng chuỗi), đúng hợp đồng extension. App trước đây bỏ qua `audios`, nên phát không có tiếng; app gốc phát kèm luồng tiếng.

- **Model**: thêm `VideoAudioTrack` (`data`, `type`, `label`, `language`, `headers`) và `VideoTrack.audios`, mặc định rỗng.
- **Đọc từ track**: `VideoTrackMapper` đọc `audios` (nhận `url` thay cho `data`, bỏ phần tử rỗng và trùng). Khi `audios` rỗng thì đọc trường đơn `audio`.
- **Ghép hình + tiếng** (`VideoAudioRenditionComposer`), áp cho track `native` có `audios`:
  1. Tải nhanh `data` (chỉ khi đuôi là `.m3u8`/`.m3u` hoặc mime `mpegurl`; kèm header; tối đa 4,5 giây).
  2. Nếu `data` đã là playlist gốc (có `#EXT-X-STREAM-INF`): phát như cũ.
  3. Nếu là playlist con, hoặc tải lỗi: dựng playlist gốc tổng hợp, mỗi phần tử `audios` thành một dòng `#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud"` (phần tử đầu là `DEFAULT`), rồi `#EXT-X-STREAM-INF:BANDWIDTH=2000000,AUDIO="aud"` trỏ tới luồng hình. Playlist này phát qua nhánh `.hlsText` / `HLSPlaylistResourceLoader`.
  4. `data` ở dạng text hoặc `data:` cũng ghép được: playlist con được phục vụ kèm.
- **Nhánh `.hlsText`**: giờ gửi User-Agent qua `AVURLAssetHTTPUserAgentKey`.
- **Playlist ghép lỗi**: tự quay về luồng gốc như trước.
- **Kiểm tra mất tiếng**: playlist ghép có nhóm `.audible` nên không còn báo `❌` sai.
- **Rủi ro**:
  - Playlist ghép không khai `CODECS`.
  - Cả asset dùng chung một bộ header: header của track thắng, header riêng của `audios` chỉ bù khoá còn thiếu.
  - Track có `audios` nạp chậm thêm tối đa khoảng 4,5 giây.
  - AirPlay không phát được `fbhls://`, giống nhánh HLS text có từ trước.
- **Kiểm chứng**: `check_architecture.py` **2 violation, 0 mới**. Không build tại chỗ (Windows); CI chỉ xác nhận biên dịch. Cần thử Dailymotion trên máy.

## [1.3.535] - 2026-10-17

### fix: video dò từ trang mất tiếng thì tự thử link khác hoặc nhúng trang, ghi log chẩn đoán

Người dùng báo nguồn Dailymotion (tiện ích HHHTQ, track `auto`) có hình mà mất tiếng; app gốc thì có tiếng. Log người dùng gửi không có dòng chẩn đoán vì công tắc log đang tắt, và từ máy dev không tải được manifest (403, token gắn theo thiết bị). Vì vậy bản này vừa ghi lại bằng chứng, vừa tự khắc phục.

- **Phát hiện mất tiếng**: sau khi item đang phát khoảng 2,5 giây, đếm `AVPlayerItem.tracks` và bỏ các track tiếng đang tắt; nhóm `.audible` chỉ ghi vào log. Mỗi lượt nạp chỉ kiểm một lần; đang tạm dừng thì hoãn tới lần phát sau.
- **Log luôn ghi (`❌`)**:
  - `Không có âm thanh: …` kèm tiện ích, tập, server, nguồn link (link trực tiếp / HLS text / dò từ trang), loại playlist đã chọn (master/media, có `AUDIO` hay không, số ứng viên), số track hình/tiếng.
  - Dòng lỗi `AVPlayerItem` có thêm nguồn link, URL đã che token (scheme + host + tên file), mã lỗi và lỗi mạng gần nhất trong error log của item.
- **Tự khắc phục**, chỉ áp với link do `VideoMediaSniffer` dò từ trang (track `auto`/`webview`):
  - Thứ tự thử: link chính → tối đa 3 m3u8 khác (master có `AUDIO` trước) → nhúng trang.
  - Phương án dự phòng phải có cả hình lẫn tiếng; lỗi thì sang phương án kế. Chuyển phương án thì giữ giây đang xem.
  - Chỉ tự đổi khi màn trình phát đang hiện, app ở trước và không ở PiP.
  - Có thông báo ngắn trên khung phim.
  - Đây là ngoại lệ có chủ đích: DOC không cho `auto` rơi về nhúng trang, chỉ cho phép ở ca mất tiếng.
- **Không còn đưa mp4** vào danh sách dự phòng khi đã có m3u8, vì mp4 thường là quảng cáo. Có nhiều master thì ưu tiên master có `AUDIO` làm link chính.
- **Link tiện ích trả thẳng** (`native`/HLS text): không tự đổi, chỉ ghi log.
- **File mới**: `VideoPlaybackSession+AudioFallback.swift`, `VideoSourceResolution.swift`. Sửa `VideoMediaSniffer`, `VideoHLSPlaylistProbe`, `VideoSourceResolver`, `VideoPlaybackSession` (+`Playback`/`Loading`/`Lifecycle`) và `VideoPlayerStage`.
- **Rủi ro**: HLS tách tiếng có thể không hiện trong `item.tracks`. Khi đó link dò từ trang chuyển sang nhúng dù không cần, còn link tiện ích trả thẳng sẽ ghi một dòng `❌` sai.
- **Kiểm chứng**: `check_architecture.py` **2 violation, 0 mới**. Không build tại chỗ (Windows); CI chỉ xác nhận biên dịch. Thử Dailymotion trên máy: nếu vẫn mất tiếng thì gửi log, giờ sẽ có dòng `Không có âm thanh` dù công tắc log tắt.

## [1.3.534] - 2026-10-17

### feat: nút đánh dấu và bỏ đánh dấu 18+ cho tiện ích

Yêu cầu: *"thêm nút đánh dấu/bỏ đánh dấu ext nsfw"*.

- **Lưu lựa chọn**
  - `Extension.nsfwOverride: Bool?`: `true` = đánh dấu, `false` = bỏ đánh dấu, `nil` = nhận diện tự động. Decode khoan dung.
  - Trường này **tách khỏi** `isNsfw`: cập nhật tiện ích đọc lại `isNsfw` từ `plugin.json`, nhưng không làm mất lựa chọn của người dùng.
- **Nhận diện**: `ExtensionNsfwClassifier` ưu tiên `nsfwOverride` trên cả cờ tự khai lẫn heuristic. `ExtensionNsfwCache` so sánh cả bản ghi nên tự tính lại khi lựa chọn đổi.
- **Ghi**: `ExtensionTransactionCoordinator.setNsfwOverride` (theo mẫu `setSavesHistory`), lưu ngay khi bấm.
- **Giao diện**
  - Màn Cấu hình tiện ích có section "Nội dung nhạy cảm" (`ExtensionConfigView+Nsfw`): nút "Đánh dấu 18+" / "Bỏ đánh dấu 18+"; đã tự chọn thì hiện thêm "Dùng nhận diện tự động". Chú thích ghi rõ trạng thái hiện tại.
  - Nhấn giữ dòng tiện ích đã cài trong Kho có cùng các lựa chọn (`RepositoryManagerView+Nsfw`).
- **Tác dụng kéo theo**: nhãn 18+ trên icon, ẩn khi công tắc NSFW tắt, và mặc định không lưu lịch sử nếu người dùng chưa tự chọn.
- **Sao lưu**
  - `BackupPayload` mang thêm `nsfwOverride`, tính vào fingerprint.
  - Khi khôi phục, chỉ áp lựa chọn cho tiện ích mà máy đang khôi phục chưa tự chọn, cùng luật với `savesHistory`.
- **Kiểm chứng**: `check_architecture.py` **2 violation, 0 mới**. Không build tại chỗ (Windows); CI chỉ xác nhận biên dịch.

## [1.3.533] - 2026-10-17

### feat: khám phá dạng section, trình phát kiểu Aloha có PiP và phát nền, hub luôn hiện, công tắc NSFW toàn app

Mốc giao diện của plan đợt 2 (`Docs/Plans/2026-10-17-plan-round2-fixes-player-hub.md`), nằm trên nhánh `feature/comic-video`. T3, T4 và T5 chạy song song trên worktree riêng; T6 và các yêu cầu bổ sung làm ở session chính; hai agent review phản biện chéo rồi sửa trước khi chốt. Từ mốc này commit viết tiếng Việt có dấu.

- **Khám phá dạng section (T3)**
  - `ExtensionManager+Explore` parse `explore` thành `ExploreSection` / `ExploreItem` / `ExploreAction`.
    - Section: `banner`, `horizontal_list`, `grid`, `list`, `ranking`, `chip`; giá trị lạ thì bỏ qua.
    - Hình thẻ: `book`, `square`, `circle`, `movie`, `short`.
  - Nguồn có `explore` thì trang chính dựng section **thay** tab `home`, đúng DOC; `genre` giữ nguyên. Section hiện ngay, `home` và `genre` nạp song song.
  - "Xem thêm" (`more` kiểu `list`) mở danh sách phân trang. Item không có action thì mở chi tiết theo `link`.
  - Banner giữ item không có tên nếu có ảnh và có `link` hoặc `action`.
  - Bìa dùng `RemoteCoverImage`. Referer dự phòng là `source` của tiện ích, tính một lần khi view xuất hiện.
  - Nhãn `tag` dùng chung `CoverTagBadge` (bỏ `DiscoveryCoverTag`).
  - `hasScript` đọc `script` dạng `[String: Any]`.
- **Trình phát tự dựng (T4)**
  - Kiến trúc:
    - `VideoPlaybackSession` giữ `AVPlayer` sống lâu hơn màn hình; màn hình chỉ gắn vào, đếm theo từng lần gắn.
    - `VideoPlayerSurfaceView` (`AVPlayerLayer`) thay `AVPlayerViewController`.
  - Điều khiển chỉ dùng biểu tượng, theo mockup đã duyệt:
    - tốc độ, Vừa / Lấp đầy, khoá xoay `lock.rotation`, phụ đề, PiP, server
    - nút Xoay (`requestGeometryUpdate`), khoá cảm ứng, tập kế, danh sách tập nhóm theo section, nút "Bỏ qua"
  - Cử chỉ: chạm đúp ±10 giây cộng dồn; vuốt dọc chỉnh độ sáng / âm lượng; vuốt ngang để tua; nhấn giữ phát 2×. Độ sáng được trả lại khi rời trình phát.
  - Thu nhỏ để phát nền qua `VideoMiniPlayerState`. Mở lại bằng `VideoPlayerPresenter` dạng `.overFullScreen`, nên màn đọc bên dưới không bị tháo.
  - PiP tự bật khi rời app. Không bật được PiP thì tách hình và chỉ phát tiếng, có background task.
  - Màn khoá và Now Playing:
    - `VideoNowPlayingCoordinator` giữ phiên màn khoá chỉ khi có item đang phát.
    - TTS bỏ qua lệnh màn khoá khi video giữ phiên (`TTSManager+NowPlaying`, `TTSNowPlayingController`), không sửa `TTSManager.swift`.
  - Ưu tiên TTS:
    - Video đã nhường TTS thì không tự phát khi tải xong.
    - TTS bắt đầu đọc thì media của trang nhúng tạm dừng.
  - Giữ màn sáng qua `ScreenIdleTimerLock` dùng chung với màn đọc truyện tranh; chỉ giữ khi màn trình phát đang hiện.
  - **Dailymotion mất tiếng (giả thuyết, chưa kiểm trên máy)**:
    - Trình bắt link gom thêm m3u8 trong 1,5 giây.
    - `VideoHLSPlaylistProbe` tải tối đa 6 ứng viên và ưu tiên playlist gốc (`#EXT-X-STREAM-INF`).
    - Log loại playlist đã chọn (chỉ host và tên file). Cái giá: mỗi lần mở HLS chậm thêm khoảng 1,5 giây.
- **Hub và widget (T5 + bổ sung)**
  - Hub luôn hiện, bấm là bung đủ 3 dòng cố định: Trợ lý AI, Thông báo, Video. Dòng nào không dùng được thì xám; dòng có định danh cố định, trạng thái đổi không làm vẽ lại.
  - Ẩn khi `FloatingWidgetSuppression` bật (đang xem phim toàn màn).
  - Thông báo **luôn** bấm được. Có tin chưa đọc thì hiện chấm đỏ trên icon chuông; số lượng ghi ở dòng phụ.
  - Icon AI đổi sang màu trắng.
  - Badge số của nút hub chỉ đếm mục đang có việc (`FloatingHubItem.isActive`).
  - Hub nép vào mép thì nút mờ còn 0,5.
  - Widget trình duyệt tách lại thành cửa sổ riêng (`alert-3`): nút mờ 0,7 khi nghỉ, đậm 1,0 khi chạm hoặc kéo; dùng lại khoá vị trí cũ.
  - Widget TTS cũng ẩn theo `FloatingWidgetSuppression`.
- **Công tắc NSFW toàn app (T6)**
  - Khoá chung `extFilterIncludeNsfw` dùng ở Cài đặt › Thư Viện › "Nội dung nhạy cảm (NSFW)" (màn riêng `NsfwSettingsView`, có công tắc và giải thích) và ở bộ lọc Kho.
  - Mặc định tắt và **tự tắt lại mỗi lần mở app** (`resetNsfwVisibilityOnLaunch`).
  - Khi tắt:
    - Khám phá ẩn nguồn NSFW và tự chuyển sang nguồn khác, kể cả khi mở lại app. Nếu mọi nguồn đều bị ẩn thì báo trạng thái rỗng.
    - Tab Lịch sử và phần tìm trong lịch sử ẩn sách của nguồn NSFW. Sách trên Kệ không bị ẩn.
  - Nhãn **18+** (chữ trắng, nền đỏ) ở góc icon của mọi tiện ích NSFW (`ExtensionNsfwBadge` trong `ExtensionIconView` và dòng Kho).
- **Xoá lịch sử theo khoảng**: "Xoá tất cả lịch sử" mở hộp chọn 1 giờ / 1 ngày / 30 ngày / Tất cả. Chỉ xoá sách đang hiển thị (lịch sử NSFW đang ẩn được giữ), qua `BookStorageManager.deleteBooksAsync`.
- **Khám phá ổn định hơn**: lượt tải mới huỷ lượt cũ, kết quả chỉ được ghi khi nguồn vẫn đang được chọn, và không tải hai lần khi tự chuyển nguồn.
- **Kiểm chứng**: `check_architecture.py` **2 violation, 0 mới**. Không build tại chỗ (Windows); CI chỉ xác nhận biên dịch. PiP, phát nền, màn khoá, cử chỉ, xoay và cửa sổ nổi chỉ kiểm được trên máy.

## [1.3.532] - 2026-10-17

### fix: sua host/url va bia gui referer, parse an toan, nhom tap theo server, loc nsfw, cong tac luu lich su

Mốc sửa lỗi của plan đợt 2 (`Docs/Plans/2026-10-17-plan-round2-fixes-player-hub.md`), cùng nhánh `feature/comic-video`. Chia làm 3 phần: nền tảng N chạy trước, sau đó T1 (NSFW + lịch sử) và T2 (bìa, nhãn, nhóm tập) chạy song song. Từ bản này có luật mới: không đưa tên ứng dụng gốc vào comment, chuỗi, tài liệu hay commit; các dòng nhánh đã thêm trước đó đã được dọn.

- **Parse an toàn**
  - Mọi đường parse của `ExtensionManager` (`search`, `custom`, `detail`, `toc`, `page`, `genre`, `home`) đọc qua `JSValueReader` (`ExtensionManager+ItemParsing`). `undefined`/`null` không còn hiện thành chữ.
  - Ca thật: kkphim, tab Mới cập nhật — ext trả `description: item.description` trong khi API không có trường này.
  - `ExtensionItemResult` thêm `tag`, `type`; tách `ExtensionItemResult` và `ChapterResult` ra file riêng.
- **URL và host**
  - `ExtensionURLFormatter` đổi `//x` thành `https://x`.
  - Thêm `resolveAssetURL` cho bìa: URL tuyệt đối giữ nguyên (không còn bước "lấy `https://` cuối cùng" làm hỏng bìa proxy `?url=`).
  - Item thiếu `host` thì dùng `source` của tiện ích; `host: ""` thì giữ nguyên, đúng DOC.
  - `ExtensionHostResolver.chapterHost`: chương → sách → `source`. Áp ở điểm chung `ChapterContentRepository.fetchFromExtension` (Reader, TTS), danh sách chương tải, xuất, comic đọc/tải và video.
  - Host đã lưu không còn bị ghi đè thành rỗng (`updateBookMetadata`, BookDetail). Đổi nguồn lấy host theo thứ tự: detail → item → `source`.
  - `link`/`url` không bị resolve lúc parse, vì chúng là khoá nhận diện.
- **Track video**
  - `VideoSourceResolver` giải escape JSON (`\t \n \/ \uXXXX`…) và cắt khoảng trắng trước khi hiểu `data` là URL.
  - Ca thật: HHHTQ trả `"\thttps://play.abyssplayer.com/…"`, trước đây báo "cần URL http(s) tuyệt đối".
- **Bìa gửi `Referer`**
  - Ca thật: CDN bìa của truyenqq trả 403 khi thiếu `Referer`.
  - `CoverImageLoader` (actor, cache bộ nhớ và `Caches/cover_images/`, downsample) cùng `RemoteCoverImage` thay `AsyncImage` ở Tìm kiếm, Gợi ý, `BookCoverView` và danh sách Khám phá.
  - `Referer` lấy theo host item, rồi `source`.
  - `ImageCacheManager.downloadAndSaveCover` nhận `referer`.
  - Bìa và icon cũ dạng tương đối được ghép `source` lúc hiển thị, không backfill.
  - Thêm nhãn `tag` trên bìa.
- **Nhóm tập theo server**
  - ChapterStore thêm cột `is_section` (`user_version` 2). `toc` của comic/video giữ dòng `type:"section"` làm tiêu đề nhóm; truyện chữ không đổi.
  - Mục lục BookDetail và danh sách chương comic hiện tiêu đề nhóm.
  - Comic, video và lượt tải comic bỏ qua dòng section; lượt tải lọc section **trước** khi áp giới hạn số chương.
- **NSFW**
  - `Extension.isNsfw`, đọc từ `metadata.nsfw`/`tag`/`tags` lúc cài.
  - Registry decode khoan dung: một mục hỏng không làm trắng cả kho.
  - `ExtensionNsfwClassifier`: cờ tường minh, hoặc từ khoá/tên miền theo trang danh mục cộng đồng; bỏ hai từ đơn `dam`, `cu`; cụm nhiều chữ so theo ranh giới từ.
  - Bộ lọc kho có công tắc "Nội dung nhạy cảm (NSFW)", mặc định tắt. Công tắc tắt thì ẩn tiện ích NSFW trong Kho và khi tìm mọi nguồn. Khám phá vẫn hiện tiện ích NSFW đã cài.
- **Lưu lịch sử theo tiện ích**
  - `Extension.savesHistory` + `ExtensionHistoryPolicy` (mặc định bật, NSFW mặc định tắt). Công tắc nằm ở màn cấu hình (`ExtensionConfigView+History`) và lưu ngay qua `ExtensionTransactionCoordinator.setSavesHistory`, không qua `configJson`.
  - `isHistory` chỉ được bật khi chính sách cho phép, ở các chỗ: `ReadingProgressStore.persist`, `ChapterPersistenceStore.ensureBook` và upsert, `removeFromShelf`. Tiến độ đọc vẫn được lưu.
  - Lịch sử cũ được giữ.
  - `HistoryOrphanBookSweeper` chạy lúc mở app, dọn sách mồ côi (không trên kệ, không lịch sử, tiện ích tắt lịch sử), trừ sách đang TTS hoặc đang tải.
  - Backup mang thêm `isNsfw`/`savesHistory`.
- **Rủi ro đã biết**
  - Lần làm mới mục lục đầu tiên ghi lại host của mọi chương (`""` thành `source`).
  - Vị trí đọc dở của comic/video mở trước bản này có thể lệch vì mục lục có thêm dòng section.
  - "Xoá khỏi kệ" với tiện ích đã tắt lưu lịch sử thì sách bị dọn hẳn ở lần mở app sau.
- **Kiểm chứng**: `check_architecture.py` báo **2 violation, 0 mới**. Không build tại chỗ (Windows); CI chỉ xác nhận biên dịch. Thử trên máy theo mục 6 của plan.

## [1.3.531] - 2026-10-17

### feat: ho tro extension comic va video, sua bo loc kho theo nhom the loai/ngon ngu, them nut go o man cau hinh

Người dùng duyệt plan `Docs/Plans/2026-10-17-plan-comic-video.md`, gồm: comic và video làm chung một đợt; video hỗ trợ `native`, `auto` và nhúng `webview`; comic đọc cuộn dọc; làm cả API `Graphics` lẫn tải offline. Thêm hai yêu cầu: sửa bộ lọc kho (Phần E) và nút Gỡ ở màn cấu hình (Phần F). Toàn bộ làm trên nhánh `feature/comic-video`, đã thêm nhánh này vào trigger `build-ipa.yml`. Hợp đồng extension lấy theo `extension-api.md` của Darkrai9x.

- **Nền tảng**
  - `ExtensionType.video`.
  - `ExtensionContentKind` (`text`/`comic`/`video`/`unsupported`) suy loại lúc chạy, theo `packageId` (bản đã cài → catalog → `text`) hoặc theo `plugin.json` của `localPath`. **Không** đổi `@Model`; `detail.type` ghi đè thì không lưu.
  - Model media: `ComicPageSource`, `VideoServer`, `VideoTrack` (+ `VideoTrackKind`, `VideoTimeSkip`, `VideoSubtitleTrack`). Mapper thuần: `ComicPageMapper`, `VideoTrackMapper`, `JSValueReader`.
  - `ExtensionManager+Media`: `comicPages` / `videoServers` / `videoTrack`. **Không** qua pipeline text (`cleanHTML`, JunkFilter, bin, dịch, TTS). `link` của ảnh có `script` và `data` của track được giữ nguyên văn. `chap()` cũ giữ nguyên chữ ký.
  - `toc` bỏ item `type:"section"` chỉ với comic/video; truyện chữ giữ nguyên để chỉ số chương không lệch.
- **Định tuyến**
  - `BookContentDestination` (cùng nhãn tham số với `ReaderView`) thay `ReaderView(` ở 4 chỗ: BookDetail, Kệ, Tìm trên kệ, Bộ sưu tập. Router chọn `ReaderView` / `ComicReaderView` / `VideoPlayerScreen`.
  - `BookContentLaunch.initialParagraphIndex` là `Int?`: `nil` = tiến độ đã lưu.
- **Màn hình cho media**
  - Khám phá và Tìm kiếm có hàng chip loại `ExtensionKindFilterBar`.
  - Đổi nguồn chỉ cho chọn nguồn cùng loại (`SearchExtensionScopePolicy`, `BookSourceMigrator` chặn khác loại).
  - BookDetail (`+Media`): comic/video ẩn Xuất ebook và Từ điển; video ẩn Tải; nhãn "Tải ảnh offline" / "Xem ngay".
  - `BookActionSheet` ẩn các thao tác tương ứng.
  - `BookKindBadge` trên bìa sách ở kệ.
- **Comic**
  - `ComicImageLoader` (actor): header gồm `headers` > `referer` > `Referer: <origin chương>/` + UA iPhone; thử `fallback` lần lượt; tối đa 3 request đồng thời.
  - Downsample bằng ImageIO, khống chế bề ngang và tổng điểm ảnh.
  - Cache gồm `NSCache` và `ComicImageDiskCache` (`Caches/comic_images/`, 400 MB, dọn khi vào nền).
  - `ComicImageScriptRunner` chạy script ảnh, nhận base64 trần, `Response.success` hoặc `data:`.
  - API JS `Graphics` (`JSGraphicsBridge` + `JSGraphicsBootstrapScript`): `createImage`, `createCanvas`, `drawImage` 3/5/9 tham số, `capture` → PNG base64.
  - Màn đọc `Views/ComicReader/`: cuộn dọc, chạm đúp mở `ComicZoomViewer`, mục lục, chương trước/sau. Tiến độ (chỉ số ảnh) lưu qua `ReadingProgressStore.checkpoint`.
  - Tải offline: `ComicOfflineStore` (`comics/<sha256(bookId)>/<chapterIndex>/manifest.json` + ảnh) và `DownloadManager+Comic` tải tuần tự từng chương, từng ảnh. Xoá sách thì xoá thư mục comic.
  - `DownloadManager.executeTask` từ chối xuất ebook cho comic/video và từ chối tải video.
- **Video**
  - Browser của tiện ích bắt cả XHR, fetch, media và iframe nhờ `WebNetworkCaptureScript` (`WKUserScript` mọi frame) cùng `WebNetworkCaptureMessageProxy` (weak). `urls()` / `waitUrl` thấy toàn bộ request, đúng ngữ nghĩa hợp đồng extension.
  - Autoplay tắt tiếng chỉ bật cho tiện ích loại video; tiện ích khác giữ `.all` như cũ.
  - `VideoMediaSniffer` + `VideoSourceResolver` → `VideoPlaybackPlan` (`.native` / `.hlsText` / `.embed`). `auto` không ra link thì báo lỗi, đúng DOC; `webview` không ra link thì nhúng trang.
  - `HLSPlaylistResourceLoader` (`fbhls://`) cho playlist dạng text hoặc `data:`. `VideoSubtitleParser` đọc SRT/VTT.
  - Trình phát `Views/VideoPlayer/`: `AVPlayerViewController` có header (`AVURLAssetHTTPHeaderFieldsKey`) và PiP; chọn server (nhớ theo sách); lưới tập; nút Bỏ qua theo `timeSkip`; phụ đề trong `contentOverlayView`; tự sang tập kế; `VideoEmbedWebView` cho nhánh nhúng.
  - Khi phát thì tạm dừng TTS và chiếm `AVAudioSession` `.playback/.moviePlayback`. Tiến độ (số giây) lưu qua `checkpoint`.
- **Bộ lọc kho (Phần E)**
  - `ExtensionFilterGroups` gom thể loại thô (`eng_novel`, `novel,comic`, `chinese_novel`…) và ngôn ngữ thô (`zh-CN`, `vi`, `vi-VN`, `global`, `ja_JP`, `kr_KR`…) thành nhóm cố định như trang danh mục tiện ích cộng đồng. Riêng `ja`/`ko` so theo tiền tố.
  - `FilterSheet` hiện chip theo nhóm kèm số lượng. Lựa chọn đã lưu được ánh xạ lại qua nhóm. Comic không còn bị lọc khỏi kho.
- **Nút Gỡ (Phần F)**: `ExtensionConfigView+Uninstall` thêm nút Gỡ có xác nhận, đi cùng đường `ExtensionTransactionCoordinator.uninstallExtension`. Chặn gỡ tiện ích đang làm giọng đọc. Khám phá tự chọn lại nguồn khi nguồn đang chọn bị gỡ.
- **Sửa sau review phản biện (2 agent đọc chéo toàn bộ diff)**
  - `waitUrl`:
    - Reset danh sách URL **đồng bộ** lúc bắt đầu load (`beginLaunch`), tránh khớp nhầm URL của lần launch trước.
    - So chuỗi con chỉ áp cho URL điều hướng (hành vi cũ); request bắt được phải khớp regex toàn URL. Nhờ vậy ext truyện chữ và màn giải captcha không bị đóng sớm.
    - Thêm token chống timer cũ kết thúc lượt chờ mới.
  - Browser của ext video được gắn cửa sổ ẩn (`WebViewLoader+HiddenWindow`) để iOS không treo media.
  - Trang nhúng:
    - Gửi `Referer` và UA.
    - Chặn khung chính rời host gốc và chặn domain quảng cáo.
  - Track video:
    - `mimeType` dùng qua `AVURLAssetOverrideMIMETypeKey`, UA qua `AVURLAssetHTTPUserAgentKey`.
    - `chap` trả chuỗi JSON thì được parse lại.
  - Lưu tiến độ video:
    - Hết tập không còn lưu giây ≈ độ dài phim.
    - Mở lại đúng tập đang xem thì xem tiếp từ giây đã lưu.
  - Comic online:
    - Referer lấy theo URL chương **đã resolve**.
    - Byte do script ảnh trả về phải là ảnh thật; mục cache hỏng thì bị xoá.
    - Ảnh có cạnh dài ≤ 16384 px.
  - Comic offline:
    - Chỉ dùng bản đã tải khi `chapterUrl` của manifest khớp chương.
    - Lượt tải dùng script runner riêng.
    - Đổi nguồn thì xoá ảnh offline cũ.
  - `Graphics`:
    - Canvas mỗi cạnh ≤ 8192.
    - `drawImage` giữ toạ độ thực.
  - Đổi nguồn sách comic/video mà tiện ích cũ đã gỡ: không còn bị suy thành `text` (`resolveIfKnown`).
  - Router: khi không tra được loại tiện ích mà sách có ảnh comic offline thì mở bằng màn comic, không mở reader chữ.
  - Log `track` chỉ ghi dạng gọn, vì có thể chứa token hoặc header.
- **Dòng file legacy**: `BookDetailView` 1200 → 1105 (chuyển hai hàm tải trang mục lục sang `+TOCPreparation`), `SearchView` 871 → 862. Mọi file mới ≤ 400 dòng.
- **Ngoài phạm vi**:
  - Video: feed `short`, DRM native (ClearKey chỉ qua nhúng), nhiều audio, danmaku, tải video.
  - Comic: dấu "đã tải" trên mục lục chi tiết truyện.
  - Đồng bộ cookie WKWebView sang URLSession.
  - Sơ đồ mã hoá mới của AllShorts.
  - Backup **không** gói thư mục `comics/`.
- **Kiểm chứng**: `check_architecture.py` báo **2 violation, 0 mới**. Không build tại chỗ (Windows); CI chỉ xác nhận biên dịch. Cần thử trên máy theo danh sách ext mẫu ở mục 7 của plan.

## [1.3.530] - 2026-10-16

### fix(tts): tts tien ich suy duong dan tu packageId, bo ttsExtensionLocalPath tuyet doi

Người dùng: duyệt plan *"TTS tiện ích: bỏ ttsExtensionLocalPath tuyệt đối"* — việc còn lại ở §9 plan `Docs/Plans/2026-10-16-plan-extension-store-json.md` (1.3.529).

- **Vấn đề**: `TTSManager.extensionLocalPath` được lưu nguyên đường dẫn **tuyệt đối** vào `UserDefaults` (`ttsExtensionLocalPath`). Gốc thư mục dữ liệu đổi (LiveContainer, lỗi 1.3.523) ⇒ TTS tiện ích trỏ vào thư mục chết cho tới khi mở màn Cài đặt TTS, và `localStorage` của nó rơi vào namespace `"path:"+md5` thay vì `packageId` (`JSExecutor`). Restore cài đặt cũng hỏng tương tự: `ttsTool` về nhưng khoá đường dẫn bị `BackupSettingsArchiver` chặn ⇒ đường dẫn rỗng.
- **File mới** `Sources/Services/TTS/TTSManager+ExtensionPath.swift`: `libraryExtensionLocalPath(tool:)` / `libraryExtensionConfigJson(tool:)` (`nonisolated static`, đọc `ExtensionLibraryRepository.snapshot(packageId:)`), `refreshExtensionPathFromLibrary()` (chỉ gán khi khác để không xoá cache prefetch vô ích), và dọn khoá cũ một lần — chuyển namespace `"path:"+md5(đường dẫn cũ)` sang `packageId` nếu namespace đó còn trống (cứu `localStorage` mà 1.3.529 có thể đã ghi nhầm chỗ), rồi xoá khoá.
- **`TTSManager.swift`** giữ nguyên **3510** dòng: bỏ dòng ghi `UserDefaults` trong `didSet` (−1); `init` tính `extensionLocalPath` và `extensionConfigJson` từ index (`configJson` của tiện ích là nguồn sự thật, bản sao `ttsExtensionConfigJson` chỉ còn là dự phòng; ±0); `initialize(container:)` gọi `refreshExtensionPathFromLibrary()` sau khi library đã nạp (+1).
- **Tài liệu**: `rules.md` bỏ ngoại lệ "`ttsExtensionLocalPath` còn tồn"; comment deny-list của `BackupSettingsArchiver` cập nhật (vẫn chặn khoá sót trên máy chưa dọn).
- **Không đổi**: màn Cài đặt TTS (vẫn đồng bộ khi mở màn), luồng tổng hợp/cache; chưa tự cập nhật đường dẫn khi bản cập nhật tiện ích đổi thư mục con lúc app đang chạy (có từ trước).
- **Kiểm chứng**: `check_architecture.py` **2 violation, 0 mới**. Không build tại chỗ (Windows) — CI xác nhận biên dịch. Test tay: chọn TTS tiện ích, khởi động lại app, nghe được ngay không cần mở màn cài đặt.

## [1.3.529] - 2026-10-16

### feat: luu tien ich va kho bang JSON thay SwiftData, sap xep ghim/vua dung, loc chip chon nhieu

Người dùng: *"tối ưu lại cách lưu tiện ích (cả data lẫn metadata), danh sách kho, không lưu swiftdata nữa"* → phỏng vấn `grill-me` (tham khảo cấu trúc backup vbook iPhone), plan đã duyệt: `Docs/Plans/2026-10-16-plan-extension-store-json.md`; contract API giữa các nhánh: `Docs/Plans/2026-10-16-extension-store-phase1-api.md`.

- **Gỡ `@Model Extension` và `@Model Repository` khỏi schema** (`FreeBookApp.swift`: còn 4 model `Book`, `BookCollection`, `Chapter`, `DownloadTaskModel`). Dữ liệu tiện ích/kho chuyển sang `applicationSupport/extension_store/`: `installed.json` (index **chỉ tiện ích đã cài**, đường dẫn **tương đối** `folder`), `repositories.json`, `registry/<sha256(url)>.json` (cache registry, tiện ích chưa cài chỉ hiện từ đây), `local_storage.json`. Script/icon vẫn là file trong `extensions/<folder>/` — đo trên 39 tiện ích thật: nhét script+icon vào index như vbook là 5,28 MB, index slim ~53 KB.
- **Tầng mới** `Sources/Services/Extensions/Store/` (9 file, đều ≤ 306 dòng): `ExtensionLibraryRepository` (`@MainActor @Observable`, nguồn sự thật; `catalog` = đã cài ∪ registry chưa cài; tầng nền đọc qua `nonisolated static` + `ExtensionLibrarySnapshotTable` có lock), `ExtensionIndexStore`/`ExtensionStoreFileIO` (ghi atomic trên queue nền, file hỏng bị cách ly `.corrupt-<ts>`), `ExtensionLocalStorageStore`, `ExtensionStorePaths`, `ExtensionStoreEnvelope` (`schemaVersion: 1`). Model value type mới ở `Sources/Models/Extensions/`: `Extension` (struct, `pinnedAt`/`lastUsedAt`, `remoteVersion` transient), `ExtensionRepositoryRecord`, `ExtensionRegistrySnapshot`, `ExtensionRegistryItem` (chuyển khỏi `ExtensionManager.swift`), `ExtensionFolderLocator`. Bỏ `isEnabled` (không có chỗ nào bật/tắt).
- **`ExtensionTransactionCoordinator` viết lại** trên repository, bỏ tham số `in context:`; thêm `saveRegistry`, `markUsed`, `uninstallExtension`, `auditInstalledExtensions`; xoá `pruneRepositoryExtensions`, `updateExtensionFolder`, `touchRepositoryLastUpdated`, `repairExtensionPathsAtLaunch`, `applyInstallAudit`. Xoá `ExtensionPathResolver` (đường dẫn tương đối ⇒ hết lớp lỗi đổi gốc thư mục 1.3.523), `PruneRepositoryExtensionsCommand`, `UpdateExtensionFolderCommand`; `ExtensionInstallAudit` rút gọn; `ExtensionSyncCommandBuilder` 169 → 18 dòng (chỉ giữ `packageId(forName:)`).
- **Migrate một lần** (`LegacyExtensionSQLiteMigrator` + `LegacyExtensionSQLiteReader`, chạy trong `FreeBookApp.init` **trước** `ModelContainer`): `wal_checkpoint` → `VACUUM INTO extension_store/legacy/library-pre-ext.sqlite` (chép cả DB, gồm sách — lưới an toàn), đọc sqlite thô `ZEXTENSION`/`ZREPOSITORY` theo tên cột (thiếu cột ⇒ log `❌` + giữ bản chép để bản sau đọc lại), chỉ lấy tiện ích đã cài, chuyển khoá `UserDefaults` `vbook_ext_storage_<md5(localPath)>_*` sang `local_storage.json` theo `packageId`; cờ `migratedFromLegacy` ghi cuối cùng.
- **Làm mới kho = 1 request registry/kho** (bỏ tải `plugin.json` cho từng tiện ích chưa cài, ~95 request với kho 100 tiện ích). Kho chưa có cache vẫn được tải trong cooldown. `hasUpdate` tính bằng cách ghép cache registry của **đúng** kho `repositoryUrl` (không fallback kho khác — tiện ích zip/debug không bị báo cập nhật sai), không lưu `remoteVersion`.
- **Thứ tự ghim (`pinnedAt` tăng) → vừa dùng (`lastUsedAt` giảm) → A-Z** (`ExtensionSortPolicy` mới) ở chọn nguồn Khám phá và tab "Tất cả tiện ích" (sau nhóm có cập nhật → đã cài). `markUsed` khi chọn nguồn, tìm kiếm **một** nguồn, mở chi tiết truyện (`BookDetailView.onAppear`).
- **Sheet "Bộ lọc tiện ích" dạng chip chọn nhiều** (`FilterSheet.swift` dùng `FlowLayout`; luật HOẶC trong nhóm, VÀ giữa nhóm, rỗng = tất cả); khoá mới `extFilterTypes/extFilterLocales/extFilterAuthors` (JSON), tự đọc khoá cũ lần đầu (`ExtensionFilterSelection`).
- **Gỡ tiện ích = xoá sạch** config/ghim/`localStorage`; cập nhật giữ nguyên. `localStorage` của JS (`JSExecutor`) khoá theo namespace `packageId` / `"global"` / `"path:"+md5` qua `ExtensionLocalStorageStore` (ghi gom ~2 s, flush khi vào nền).
- **Backup**: entry mới `library/extension_local_storage.json` (nhóm `.extensions`; restore chỉ thêm namespace máy chưa có); `ExtensionRecord` thêm `pinnedAt?`/`lastUsedAt?` nhưng vẫn ghi `isEnabled`/`isPinned` cho app cũ; `extensions.json` chỉ còn tiện ích đã cài; `BackupSettingsArchiver` chặn tiền tố `vbook_ext_storage_`; fingerprint (`formatVersion` 3) bỏ `lastUsedAt` và `localStorage` để duyệt nguồn / token JS tự làm mới không kích auto-backup.
- **~25 consumer** (Reader, Kệ sách, Bypass, TTS settings, Config, Script Editor, DownloadManager, Debug server…) chuyển từ `@Query`/`FetchDescriptor` sang repository; View giữ `Extension` tra lại theo `packageId` sau khi ghi (`ReaderViewModel` bỏ `cachedExt`, `ExtensionMetadataSection` hết ghi đè tên cũ).
- **Tài liệu**: `rules.md` thêm mục "Extension store invariants (1.3.529)" và sửa các đoạn còn nói SwiftData/plugin.json-per-extension; `CLAUDE.md`/`AGENTS.md` cập nhật bootstrap, thư mục lưu trữ, số violation thật (2).
- **Kiểm chứng**: `check_architecture.py` **2 violation, 0 mới**. Triển khai bằng 1 agent nền móng + 3 session song song + 1 agent rà soát chéo. **Không build tại chỗ** (Windows, không có `swiftc`) — CI xác nhận biên dịch. Rủi ro chính: lightweight migration của SwiftData khi gỡ 2 entity (nếu `ModelContainer` lỗi thì `fatalError`); tên bảng/cột nội bộ là giả định — chỉ kiểm chứng được bằng IPA trên máy thật.
- **Còn lại**: `ttsExtensionLocalPath` (`TTSManager`) vẫn là đường dẫn tuyệt đối; thời điểm xoá `legacy/library-pre-ext.sqlite` chưa chốt.

## [1.3.528] - 2026-10-16

### feat: them bo giai ma script extension Vbook (AES-256-CBC) luc cai dat

Người dùng: dán một JSON `script_data` gồm 10 file `.js` đã mã hoá nhờ decode, rồi yêu cầu *"thêm bộ giải mã vào app để giải mã những script bị mã hoá như thế này"* → phỏng vấn `grill-me` 6 câu, plan đã duyệt: `Docs/Plans/2026-10-15-plan-extension-script-decoder.md`.

- **File mới** `Sources/Services/Extensions/Manager/ExtensionScriptDecoder.swift` (226 dòng, 1 type `enum`, chỉ `import CommonCrypto` / `CryptoKit` / `Foundation`): bỏ token `x0P1Xx` / `x0P2Xx` / `x0P3Xx` về `+` `/` `=` rồi giải **AES-256-CBC** (IV 16 byte `0x00`, padding PKCS#7), key `SHA256(MD5("com.vbook.app" + source + author) dạng hex)`. CryptoKit không có AES-CBC nên dùng CommonCrypto.
- **Móc 2 dòng** vào `ExtensionManager.swift`, ngay sau `findMainExtensionFolder` ở **cả hai** luồng cài — `install(item:packageId:)` và `installFromLocalZip(fileUrl:)`. File 1003 → **1005** dòng (baseline `FILE_SIZE_LIMIT` 1022): toàn bộ logic nằm trong file mới, không nhồi thêm vào file legacy.
- **Cách ghi**: ghi đè nội dung file script (giữ nguyên tên) + đặt `encrypt = false` trong `plugin.json` ⇒ bản đồ `script` không phải sửa, runtime và editor đọc bản rõ luôn, **không giải mã lại ở mỗi lần chạy**.
- **Chốt phạm vi** (đã phỏng vấn): chỉ dùng công thức chuẩn — không ma trận biến thể key, không giải nén payload (tool chính thức của Vbook mã hoá JS thô), không nút giải mã thủ công / migration. File có token mà giải không ra JS ⇒ **ném lỗi để chặn cài**.
- **Kiểm chứng**: công thức đã đối chứng bằng dữ liệu thật 10 file của extension `hhtqvietsub` v10 — key `d476a9f7…292073`, ciphertext khớp **100% từng ký tự** với ZIP công bố của `Darkrai9x/vbook-extensions`. `check_architecture.py`: **2 violation, 0 mới**. `swiftc -parse` sạch cả 2 file. **Không build tại chỗ** (Windows) — CI xác nhận biên dịch.
- **Gap đã biết**: luồng khôi phục extension từ backup (`BackupExtensionInstaller`) chưa móc giải mã.

## [1.3.527] - 2026-10-14

### feat(ai): quet ten rieng giu mot chat Gemini, tu thu lai luot loi, nut thu lai, log chan doan

Người dùng: *"vẫn không cùng chat, thêm nút thử lại các batch lỗi sau khi chạy xong"*, *"tự động thử lại những cái lỗi ít nhất 1 lần"* (log `app_logs (107)` trên bản 1.3.526: lượt 3, 4, 6/15 lỗi `StreamGenerate lỗi sau ~244 000 ms, chunk=5` — Gemini vẫn đang trả lời chậm, request chạm **trần tuyệt đối 240 s**; lượt 1, 2, 5 xong; log thường đang tắt nên không thấy dòng quyết định nối tiếp/mở chat mới).
- **Một chat cho lượt quét (bắt buộc)**: phiên đã có chat Gemini thì lượt quét (`forceContext`) **không bao giờ** mở chat mới — nối tiếp bị từ chối thì chờ 5 s, gửi lại đúng lượt nối tiếp một lần (Google có thể còn đang viết nốt lượt app đã cắt), vẫn lỗi ⇒ tính lượt lỗi. Chỉ đổi model / đổi công tắc lưu lịch sử mới mở chat mới (log ❌ kèm lý do). Chat thường giữ hành vi cũ (bị từ chối ⇒ mở lại một lần).
- **Log chẩn đoán ❌** (luôn ghi dù tắt log): lượt quét mở chat mới dù phiên đã có chat (lý do: chưa có chat / không có cid / đổi model a → b / đổi công tắc / bị từ chối), nối tiếp bị từ chối, mở chat mới mà không lấy được cid. Dòng bắt đầu quét ghi công tắc lưu lịch sử, id phiên và cid hiện có (`GeminiWebClient.conversationCidPrefix`).
- **Trần tuyệt đối theo từng lượt**: `fetchStream(_:idleTimeout:absoluteTimeout:)` (mặc định vẫn 240 s); lượt quét Gemini Web dùng 600 s.
- **Tự thử lại một vòng** đúng các lượt lỗi ở **cuối** lần quét (không thử ngay — lượt vừa bị cắt có thể còn đang chạy phía Google); dải/widget "Đang thử lại: Batch i/k"; toast "k/T lượt vẫn lỗi sau khi thử lại".
- **Nút "Thử lại k lượt lỗi"** (`ReaderAINameScanRetryButton`) dưới tin kết quả, chỉ hiện khi không có lệnh chạy; mỗi lần bấm một vòng, gộp tên vào đúng tin cũ rồi lưu phiên. Danh sách lượt lỗi chỉ giữ trong RAM (`AIRuntimeCoordinator.nameScanRetry`, người dùng chọn) — mất khi thoát app, xoá khi quét mới. Gặp lỗi tài khoản/hạn mức khi bấm thử lại ⇒ giữ nguyên tin và danh sách cũ.
- Code: vòng gửi dùng chung `AINameExtractionBatchProcessor.runTurns` (quét chính / tự thử lại / nút); `AINameScanFailedBatch` (mới); `AINameScanProgress.isRetry`; `AIRuntimeCoordinator+NameScanRetry.swift` (mới). `rules.md` mục Reader AI + Gemini Web.
- Chuyển entry `[1.3.497]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 vi phạm nền cũ, 0 mới (`GeminiWebSessionController.swift` 399/400). Không build tại chỗ (Windows), cần CI. Nguyên nhân gốc của tách chat vẫn **UNKNOWN** tới khi có log ❌ của bản này.

## [1.3.526] - 2026-10-14

### fix: quet ten rieng Gemini Web khong tao chat moi moi batch khi luot bi timeout, badge so thong bao dung goc chuong

**1. Quét tên riêng: mỗi batch một chat trên Gemini** — người dùng: *"bật lưu lịch sử gemini thì để tất cả chung 1 chat … bây giờ tôi test lọc name nhiều chương thì nó tạo mỗi batch 1 chat"* (log `app_logs (106)`).
- **Nguyên nhân (từ log)**: gần như mọi lượt quét kết thúc bằng `StreamGenerate lỗi sau ~51 s, chunk=1: … không phản hồi kịp thời gian chờ` (13/10 và 14/10, lượt 1/2, 1/7, 1/8, 1/10…). Gemini nhận prompt ~40.000 ký tự, gửi **một** gói đầu (có cid — cuộc chat đã được tạo trên web) rồi nghĩ lâu hơn ngưỡng im lặng 45 s ⇒ app huỷ lượt **và vứt luôn metadata** vì `consumeGeneration` chỉ trả metadata khi xong ⇒ lượt sau không có cid để nối tiếp ⇒ mở cuộc chat mới. Kết quả: chat mới trên web mỗi batch, còn trong app lượt đó tính là lỗi.
- **Giữ cid khi lượt lỗi**: `GeminiWebClient.streamGeneration(onMetadata:)` báo metadata ngay khi Google gửi; `runConversationTurn` ghi nhớ cuộc chat qua `rememberPartial` khi lượt timeout/bị huỷ (cả nhánh nối tiếp lẫn nhánh mở mới). `DeltaFlag` gộp thành `TurnObservation` (cờ đã phát chữ + metadata mới nhất).
- **Chờ lâu hơn cho lượt quét**: `idleTimeout` 150 s cho lượt quét Gemini Web (`AINameExtractionBatchProcessor.geminiWebIdleTimeout`, cả nhánh nối tiếp lẫn chat tạm); chat thường giữ 45 s; trần tuyệt đối 240 s không đổi. Tham số `idleTimeout` của hàm `public` là optional (`nil` = mặc định) vì giá trị mặc định của hàm `public` không được tham chiếu hằng `internal`.
- `rules.md` mục Gemini Web: thêm luật "lượt lỗi giữa chừng vẫn giữ cid".

**2. Badge số thông báo** — người dùng gửi ảnh chuông Kệ sách: *"vị trí hiển thị số thông báo chưa đẹp"* (badge đỏ đè thân chuông, cạnh chấm trắng có sẵn của icon).
- `ShelfView`: `bell.badge.fill` → `bell.fill` (bỏ chấm có sẵn — hai badge chồng nhau; chấm của icon vẽ tràn khung nên neo theo khung làm badge số rơi vào thân chuông). Badge tối thiểu 16×16 (1 chữ số tròn), tâm ở góc trên-phải chuông lùi 2pt, số dài mọc sang phải, viền 1,5pt màu nền tách khỏi nét chuông.
- Hub (`FloatingHubItem.systemImage`): mục Thông báo cũng `bell.fill`/`bell` vì nút hub đã có chấm/số đỏ riêng.

- Chuyển entry `[1.3.496]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code + log thật; `check_architecture.py` 2 vi phạm nền cũ, 0 mới. Không build tại chỗ (Windows), cần CI; cần thử lại quét trên máy (bật log trong Cài đặt để thấy dòng "Lượt lỗi … nhưng đã có cid").

## [1.3.525] - 2026-10-14

### feat(hub): cham hub dang nep co tu 2 muc thi mo menu ngay

Người dùng: *"nếu 2 widget trở lên khi bấm mở rộng thì hiển thị ngay danh sách widget ở trạng thái mở rộng luôn"*, *"ví dụ chỉ 1 browser thì hiển thị icon browser thay vì icon chung"*, *"trường hợp có thông báo và 1 cái khác ở kệ sách thì tính 1"*.
- **`FloatingHubContainerViewController.handlePrimaryAction`**: chạm khi `.peeking` mà có ≥ 2 mục ⇒ bung **và** `openMenu()` ngay (trước đây phải chạm hai lần). `updateLayout` gán vị trí đích ngay nên `layoutMenu` đặt thẻ đúng cạnh nút đã bung; mở menu bật `disableAutoHide` nên không bị tự thu giữa chừng. 1 mục: giữ nguyên (chạm khi nép chỉ bung, chạm lần nữa mới mở).
- Icon 1 mục = icon của chính mục đó và cách đếm mục ở tab Kệ Sách (không tính Thông báo) **đã đúng từ 1.3.524** (`FloatingHubPresentationReader.makeSnapshot`, `FloatingHubButton.glyphName`) — chỉ ghi rõ thành luật trong `rules.md` mục "Nút hub nổi".
- Chuyển entry `[1.3.495]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 vi phạm nền cũ, 0 mới. Không build tại chỗ (Windows), cần CI.

## [1.3.524] - 2026-10-14

### feat: gop widget noi thanh nut hub, quet ten rieng noi tiep chat cua phien, icon Lucide sao chep dan, badge 99+ khong vo

Người dùng duyệt 4 plan bằng `/push-ci-monitor thực hiện mỗi plan trong 1 session ... push và theo dõi CI chung`. Mỗi plan do một agent con làm trong worktree riêng, gộp thành một commit. Plan: `Docs/Plans/2026-10-14-plan-ai-batch-name-scan-session-chat.md`, `Docs/Plans/2026-10-14-plan-floating-hub-widget.md`; hai plan còn lại duyệt trong chat.

**1. Quét tên riêng nhiều chương** — người dùng: *"Lỗi từ batch thứ 2 … không có prompt, chỉ có raw"*, *"bị tạo một đoạn chat khác đoạn chat chung của phiên"*, *"số batch thật sự được gửi yêu cầu cũng không chính xác"*, *"khi có lệnh đang chạy hãy disabled prompt nhanh"*, *"nếu bật lưu vào lịch sử chat thì không cần gom nội dung đoạn chat vào prompt"*.
- **Gốc lỗi thiếu prompt**: lượt nối tiếp chỉ kèm khối hệ thống khi băm của nó đổi (`GeminiWebClient+Conversation.runConversationTurn`), mà prompt trích xuất giống hệt giữa các lượt ⇒ lượt 2–5 chỉ gửi raw. Thêm `forceContext`: lượt quét luôn kèm prompt; băm vẫn cập nhật nên chat thường kế tiếp tự gửi lại ngữ cảnh chương.
- **Một chat của phiên**: Gemini Web + bật "Lưu chat vào lịch sử Gemini" ⇒ lượt quét nối tiếp đúng cuộc chat của phiên app (`AIChatSession.id`, `persist: true`), **bỏ** xoay chat mới sau mỗi 5 lượt (nguyên nhân số tin trên Gemini lệch số batch). Tắt công tắc: như cũ (chat tạm từng lượt, đủ prompt).
- **Đếm đúng lượt** (`AINameScanProgress`, `ReaderAIBatchProgressBannerView`): báo tổng ngay sau khi chia lượt (hết "Batch 0/1"), N = lượt **đang gửi**, dòng phụ đếm lượt lỗi; tin gửi có nhãn `(lượt N/T)`, log `gửi lượt N/T`. Xong mà có lượt lỗi ⇒ toast `.error` cả khi màn AI đang mở.
- **Khoá chip prompt nhanh** khi có lệnh AI đang chạy (mờ + không bấm); màn AI không cho bắt đầu quét khi đang chat (trước đây `cancelActiveTask()` huỷ ngang câu trả lời).
- **Chat thường, Gemini Web + bật lưu**: chỉ gửi `[system, tin hiện tại]`, không gom lịch sử trao đổi/tóm tắt ngữ cảnh cũ (kể cả khi phải mở cuộc chat Gemini mới).
- Luồng quét chuyển sang `AIRuntimeCoordinator+BatchExtraction.swift` (file gốc 387/400 dòng); nới `batchRunId`/`activeBatchTask` sang `internal`, setter `isRunning`/`activeTaskTitle` sang `internal(set)`. Nhánh xong/lỗi phải khớp `batchRunId` mới xoá trạng thái.

**2. Nút hub nổi thay 3 widget** — người dùng: *"hiện tại có quá nhiều widget, có cách nào gọn lại không?"*, chọn phương án "một nút hub" (TTS giữ riêng).
- Widget AI, trình duyệt thu nhỏ và Thông báo gộp thành **một** nút 36px, một cửa sổ (`alert - 2`; TTS vẫn `alert - 1`). Thư mục mới `Sources/Views/FloatingHub/` (11 file, ~1.500 dòng); xoá 14 file widget cũ; `NotificationFloatingWidgetPresentationReader` đổi tên thành `NotificationInboxPresenceReader`.
- Hub hiện khi có ≥1 mục (AI đang chạy và màn AI đóng / trình duyệt thu nhỏ còn tab / thông báo chưa đọc hoặc tác vụ chạy, trừ tab Kệ sách). **Luôn xuất hiện nép mép**, không tự bung khi có tin mới; chạm khi nép ⇒ bung; chạm khi bung: 1 mục ⇒ mở thẳng, ≥2 ⇒ menu (Trợ lý AI → Trình duyệt → Thông báo, có dòng phụ); tự nép sau 3 s trừ khi menu mở.
- Chỉ báo: chấm đỏ / số chưa đọc ("99+" một dòng); AI đang chạy ⇒ viền tím tĩnh; trình duyệt tab nằm yên ⇒ nháy đỏ bằng màu; **bỏ** badge số tab và chấm đỏ của trình duyệt.
- Sheet Thông báo chuyển nguyên văn từ widget cũ (nhánh hit-test, móc `.onDisappear`, `.modelContainer`, delegate sau present, giữ cửa sổ sống). Cờ "menu đang mở" được hạ ở mọi đường (ẩn, kéo, đổi số mục, mở sheet, đổi scene) — luật mới trong `rules.md`.
- Vị trí: key mới `floatingHubVerticalRatio`/`floatingHubEdge`, lần đầu lấy từ vị trí widget Thông báo cũ.

**3. Icon sao chép/dán** — người dùng: *"các nút copy và paste … dùng SF Symbols khó phân biệt quá"*, chọn bộ Lucide.
- `doc.on.doc`/`doc.on.clipboard` (23 chỗ, 14 file) ⇒ Lucide `copy` / `clipboard-paste` (asset SVG template, `lucide-static@0.400.0`, ISC — `Docs/ThirdParty/Lucide-LICENSE.txt`); mục "Gốc" của menu chọn chữ ⇒ Lucide `languages`. Nút "Copy" của màn sao chép bản gốc từng dùng nhầm icon dán.
- `AppGlyph` (`Sources/Views/Common/AppGlyph.swift`) là nguồn tên icon duy nhất; cỡ truyền tường minh từng chỗ (asset không co theo `.font()`). Quy ước thêm vào `CLAUDE.md`/`AGENTS.md`.

**4. Badge "99+" trên chuông Kệ sách bị vỡ** — `overlay` chỉ đề xuất đúng khung icon (~20pt) nên "99+" bị ép xuống dòng. `ShelfView`: `.lineLimit(1)` + `.fixedSize()`, neo mép trái badge vào mép phải icon để số dài mọc sang phải.

- Chuyển entry `[1.3.494]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code + review phản biện bằng agent con; `check_architecture.py` 2 vi phạm nền cũ (JSDom, TTSManager), 0 mới. **Không build tại chỗ** (Windows), cần CI. Cần xem trên máy thật: nét SVG Lucide, hub (chạm xuyên khi menu đóng, mở Reader từ sheet Thông báo ở tab khác). Không đụng `Tests/`.

## [1.3.523] - 2026-10-13

### fix: tu sua duong dan tien ich khi doi goc thu muc, danh sach ten AI dai khong giat, Gemini Web giai phong WebView khi loi

Người dùng duyệt gộp 3 plan bằng `/push-ci-monitor tất cả 1 lượt`.

**1. Tiện ích "bị xoá" — thật ra là đường dẫn hỏng** (`app_logs (105)`: từ 10:38:53 mọi chương chưa tải lỗi `ExtensionManager -3 "plugin.json not found inside extension"`; mở tab Tiện ích thấy trống; tắt mở lại vẫn mất; thư mục plugin trên máy còn đủ; restore backup thì có lại).
- **Cơ chế**: `Extension.localPath` lưu **đường dẫn tuyệt đối** trong `library.db`. Gốc thư mục dữ liệu của app đổi ⇒ mọi `localPath` trỏ về gốc cũ (file vẫn ở `extensions/<packageId>/` hiện tại) ⇒ lỗi -3; rồi `ExtensionInstallAudit` (chạy mỗi lần mở tab Tiện ích) coi là mất file: tiện ích của kho bị đưa `localPath` về rỗng, tiện ích import zip bị **xoá hàng** ⇒ tab trống, lưu luôn trong DB. Restore chữa được vì `BackupExtensionInstaller` giữ file đang có và **tính lại** `localPath` từ thư mục hiện tại. Vì sao gốc đổi: **UNKNOWN** — khớp thời gian với khuyến nghị "Convert to Private App" của 1.3.522 (LiveContainer chuyển thư mục dữ liệu giữa App Group và container riêng), chưa xác nhận.
- **`ExtensionPathResolver`** (mới, `Services/Extensions`): khi `localPath` không còn `plugin.json`, tìm lại theo thứ tự (1) phần sau `/extensions/` của path cũ ghép vào gốc hiện tại, (2) `extensions/<packageId>/` kể cả thư mục con có `plugin.json`. Chỉ nhận thư mục nằm trong `extensions/`, không nhận `..`.
- **`ExtensionInstallAudit`** tìm lại **trước** khi gỡ/xoá (`Plan.relocations`); chỉ gỡ/xoá khi không thấy ở đâu. Tiện ích đã bị đưa `localPath` về rỗng mà thư mục còn `plugin.json` được khôi phục. Đánh đổi có chủ ý: gỡ tiện ích đúng lúc path đang hỏng (thư mục không xoá được) thì nó hiện lại.
- **Lúc mở app** (`AppLaunchRootView.onAppear` → `ExtensionTransactionCoordinator.repairExtensionPathsAtLaunch`): chỉ sửa path, không gỡ/xoá, chạy trước khi Reader/TTS cần tới.
- **Log ❌** (luôn ghi kể cả khi tắt log): một dòng khi sửa path (số tiện ích, gốc cũ → gốc mới, packageId); dòng gỡ/xoá của audit nay cũng có ❌. Lỗi -3 kèm đường dẫn đã tìm (`localPath rỗng` khi rỗng).

**2. AI: hiển thị danh sách tên dài làm giật máy và TTS** (`TTSManager` là `@MainActor`, main thread bận thì TTS khựng).
- **`AIMarkdownMessageView`**: mỗi dòng là một `Text(LocalizedStringKey)` trong `VStack` không lazy, dựng lại cả tin mỗi nhịp stream 50 ms / mỗi batch quét tên. Nay chỉ dựng **100 đoạn cuối**, tự nạp thêm 100 đoạn khi cuộn lên gần mép trên (vòng xoay nhỏ, không nút; đo bằng `GeometryProxy.bounds(of: .scrollView)`, preference `Bool` nên mỗi lần lọt vào vùng nhìn chỉ nạp một đợt). Nạp từ đáy lên vì chat neo đáy (`.defaultScrollAnchor(.bottom)`) và cố ý không dùng `LazyVStack`. Sao chép / Thêm vào VP-Name vẫn dùng toàn bộ nội dung.
- **`hasDictionaryEntries`** (gọi trong `.contextMenu` của mọi tin mỗi lần vẽ): `enumerateLines`, dừng ở dòng `từ=nghĩa` đầu tiên thay vì tách cả tin.
- **Sheet duyệt tên riêng** (`ReaderAINameReviewCardView`): `LazyVStack` — chọn/bỏ chọn trước đây cập nhật lại mọi hàng kèm `TextField`. Nút chọn icon 22 pt, vùng chạm 44×44 (cũ: 16 pt); chạm dòng tên cũng chọn/bỏ chọn; hàng bỏ đệm trái để giữ chiều cao gần như cũ.
- **`AIRuntimeCoordinator`**: bước gắn cờ NE/VP cuối đợt quét (đọc `Names.txt`/`VietPhrase.txt` + tra từ điển cả danh sách) chuyển ra `Task.detached`, kiểm tra huỷ sau khi chờ.

**3. Gemini Web: WebView ẩn không được giải phóng khi `prepare()` lỗi.** `touch()` (hẹn giải phóng sau 10 phút) chỉ chạy ở nhánh thành công; `prepare()` ném (`notSignedIn`/timeout/`protocolChanged`) ⇒ WKWebView + window ẩn sống tới khi app thoát. Nay `touch()` nằm trong `defer` của task (mọi lối ra). Hẹn giờ thêm điều kiện `webView != nil` để không ghi log "Giải phóng WKWebView ẩn" sai khi WebView đã bị giải phóng giữa chừng. Tối đa một WebView (singleton) nên lỗ này không làm fd tăng dần.

- Chuyển entry `[1.3.493]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 vi phạm nền cũ (JSDom, TTSManager 3510), 0 mới; file mới `ExtensionPathResolver.swift` 65 dòng, một type chính. **Không build tại chỗ** (Windows), cần CI. Không đụng `Tests/`.

## [1.3.522] - 2026-10-13

### docs(fd): ghi nhan nguyen nhan can fd khi nghe TTS o nen la bug Dead10ccFix cua LiveContainer

Người dùng: *"ghi lại changelog để biết lỗi này do LiveContainer"*. Chỉ ghi tài liệu, không đổi code.

- **Lỗi**: nghe TTS (Google) lâu với màn hình khoá ⇒ tiến trình cạn file descriptor (EMFILE, `NSPOSIXErrorDomain 24`, hiện ra thành `NSCocoaErrorDomain 256`): không mở được chương, ảnh bìa, cả file log; chỉ tắt hẳn app mới hết. Điều tra qua 1.3.517 → 1.3.521 (census `[FD]`, `detail`, bộ đo theo bước, nhịp 1 s).
- **Nguyên nhân gốc — không nằm trong code FreeBook**: `LiveContainer/Tweaks/Dead10ccFix.m` (đã đọc source bản mirror, commit `4dbe0f9a`; vòng 2 giây có từ commit `85ca2724`, 2025-07-31). Đoạn này **chỉ được cài khi app chạy dạng Shared App hoặc Multitask (LiveProcess)**. Khi app ở nền mà chưa bị iOS treo (tức đang phát audio), cứ `dispatch_after` **2 giây** nó liệt kê fd của tiến trình (`PROC_PIDLISTFDS`), rồi với mỗi đường dẫn file thường (bỏ `-wal`/`-shm`/`-journal`, bỏ SQLite không khoá, bỏ file có xattr `com.apple.runningboard.can-suspend-locked` ≠ 0) gọi `open(path, O_RDONLY | O_NOCTTY)` + `fcntl(F_GETLKPID)` và **không bao giờ `close`**. Bản mở thừa lại giữ đường dẫn trong danh sách ⇒ file nào đã bị "bắt" một lần là rò mãi, khoảng 30 fd/phút mỗi file.
- **Khớp từng số đo trong log**: chỉ tăng khi app ở nền (trên màn hình ≈ 0; ở nền mà dừng TTS ⇒ app bị treo ⇒ 0); +1 mỗi ~2,1 s theo đồng hồ, không theo đoạn audio (log 104); fd mới là mở mới chỉ-đọc `fl=0x0 off=0 cloexec=0`, không phải bản `dup`; SQLite không bao giờ bị nhân; file đã xoá thì dừng nhân (log 103); file hệ thống `collator.dat`/`Dictionary.dat`/`default.metallib` lúc có lúc không (bị bắt khi tình cờ đang mở đúng vòng 2 s).
- **Vì sao chỉ mới gặp từ 2026-10-12**: commit `bd683b62` (2026-10-09, *"AppLogger giữ file mở có khoá"*) khiến `app_logs.txt` **luôn mở** ⇒ bị bắt ngay vòng đầu mỗi lần xuống nền. Trước đó log mở/ghi/đóng từng dòng nên hầu như không bị bắt. Sao lưu tự động chạy ở nền bắt thêm `books/*.bin`, `.fbbackup`, `VietPhrase.dat` (log 103: cạn 10240 fd sau ~1,5 giờ). Rà 45 commit 2026-10-08 → 2026-10-11: không commit nào tự mở lại file theo nhịp; `bd683b62` chỉ là chỗ khuếch đại.
- **Cách tránh**: (1) phía người dùng — trong LiveContainer chọn **"Convert to Private App"** cho FreeBook và không chạy Multitask ⇒ đoạn lỗi không được cài; (2) trong app — gắn xattr `com.apple.runningboard.can-suspend-locked = 0x01` lên file app giữ mở lâu (Dead10ccFix tự bỏ qua), còn file hệ thống thì nhờ `FileDescriptorSweeper` (1.3.521) dọn bản thừa. Bản sửa phía app đang chờ duyệt.
- **Không phải nguyên nhân** (đã loại trừ bằng số đo): `FD_CLOEXEC`/bản `dup` (giả thuyết của 1.3.520), JSExecutor/WebView (bộ đếm `live=` bằng 0), các bước phát audio `AVAudioPlayer`/Now Playing (bộ đo theo bước của 1.3.521 không thấy tăng), tính năng nhảy về chương đang nghe khi mở lại Reader (`c9e7c20a`).
- **Tham khảo**: [Dead10ccFix.m](https://github.com/LiveContainerMirror/LiveContainer/blob/4dbe0f9a626de801184a42c0be8d2cb105058e3d/LiveContainer/Tweaks/Dead10ccFix.m) · [commit thêm vòng 2 s](https://github.com/LiveContainerMirror/LiveContainer/commit/85ca2724812b5098d67bb5a02317cf94995525bc) · [chỗ cài trong LCBootstrap.m](https://github.com/LiveContainerMirror/LiveContainer/blob/4dbe0f9a626de801184a42c0be8d2cb105058e3d/LiveContainer/LCBootstrap.m#L514-L518) · [gist gốc cũng thiếu `close`](https://gist.github.com/JJTech0130/07e2458df592faad1d2ba72283a0ca50).
- Chuyển entry `[1.3.492]` sang `CHANGELOG.archive.md` để giữ 30 entry.
