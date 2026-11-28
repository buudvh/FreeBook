# CHANGELOG - Nhật ký Thay đổi CodeGraph Tàng Công Các

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **Tàng Công Các**.

## [1.3.1120] - 2026-11-28

### fix: bấm thể loại lúc màn xem đang tải phim sắp tự phát không đóng màn kẻo huỷ lượt phát

Vá 1.3.1119: màn bìa (`!watchOwnsSession`) hiện cả lúc phim đang tải mà "Tự phát" bật (hoặc tự sang phim đề xuất /
mục playlist, hoặc vừa bấm ▶ đang chuẩn bị) — bấm thể loại / Xem thêm lúc đó, lối "đóng màn rồi mở trang" chạy
`watch.cancel()` nên phim chưa kịp phát đã bị huỷ.
- `VideoWatchModel.isAboutToPlay` (`+Playback`): đang chuẩn bị phát, hoặc chưa xét tự phát (`didConsiderAutoplay`) mà
  tự phát / `autoNext` / `playlistStart` sẽ phát khi mục lục sẵn sàng (phim lỗi thì không).
- `VideoPlayerScreen+Exit.openCategory`: chỉ đóng màn bìa khi không `isAboutToPlay`; còn lại giữ trang đè lên màn xem
  như trước 1.3.1119 (phim tải xong vẫn tự phát bên dưới, chọn phim đổi tại chỗ).
- Ghi chú `.claude/rules/comic-video.md`. Chưa build (Windows), chưa thử máy.

## [1.3.1119] - 2026-11-28

### feat: chọn phim trong danh sách thể loại mở từ màn xem phim giữ lại danh sách, thu nhỏ phim là về lại danh sách

Anh Bửu: vào danh sách video từ màn xem phim, bấm một video khác rồi thu nhỏ hay bấm cửa sổ nhỏ thì phải về lại danh sách
vừa mở, không về màn đầu.
- `VideoWatchPagePresenter.openCategory(_:packageId:sourceName:modelContainer:)` (trang mở sau khi màn xem đóng): chọn
  phim ⇒ **không đóng trang** nữa, gọi thẳng `VideoWatchPresenter.present` ⇒ màn xem mới nằm trên trang (dùng lại lối
  "màn xem mở lại từ cửa sổ nhỏ nằm trên trang" đã có từ 1.3.781: hướng xoay, `closeAllPages` trước khi đổi tab).
  Vuốt xuống / ⌄ / nút Cửa sổ nhỏ chỉ đóng màn xem (`dismissCoveringPage` bỏ qua trang không đè lên màn) ⇒ về danh sách.
- `VideoPlayerScreen+Exit.openCategory`: màn đang hiện bìa (phim khác chạy nền) bấm thể loại / Xem thêm ⇒ đóng màn
  (`leave(stopPlayback: false)`, phim nền không bị đụng) rồi mở trang như lúc phim đang phát; `‹` ở trang về màn bên
  dưới, không về lại bìa (anh chọn). Phim nhúng trang (thu nhỏ là trang nhúng chết) giữ trang đè lên màn xem, chọn phim
  đổi tại chỗ.
- Giữ nguyên: `‹` của trang về màn gốc; bấm thể loại khác trong phim mới ⇒ trang mới thay trang cũ; nút Home về Khám phá
  và đóng luôn trang. Màn nghe nhạc không có trang danh sách mở từ trong nó nên không đổi.
- Ghi chú: `.claude/rules/comic-video.md`. Chưa build (Windows), chưa thử máy.

## [1.3.1118] - 2026-11-28

### docs: ghi chú lọc name local cho tiền tố hậu tố riêng truyện, tên kiểu Latin, luật L16, nút ▼ xuất file và hàng Phân loại

Cập nhật `.claude/rules/` cho đợt 1.3.1112–1117 (plan / mockup https://claude.ai/artifact/JwiiU3XFYTk7Rz1hAMS7G2).
- `translation.md`: kho tiền tố / hậu tố riêng truyện (`LocalNameFilterBookAffixStore`, danh sách hiệu lực Riêng + Chung,
  API phạm vi R | C và luật chuyển C → R / R → C); tên kiểu Latin `latinAffixed`; L16; `rulesVersion` 3; bản tham chiếu
  Python `latin_affixed` / `latin_core`; chip phạm vi ở màn danh sách; nút ▼ + Xuất file; màn Quản lý tiền tố, hậu tố;
  hàng Phân loại; sheet Sửa từ vừa khít; cụm R | C ở màn Sửa từ chế độ danh sách.
- `ui-conventions.md`: cụm R | C (`DictEntryEditScopeToggle`, chỗ cắm `caseRowTrailing` / `interceptSave`); tên file xuất
  `DictionaryExportFileName`; nút ▼ của màn duyệt name.
- `storage.md`: khoá `localNameFilterBookSuffixes` / `localNameFilterBookPrefixes`.

## [1.3.1117] - 2026-11-28

### fix: sửa hậu tố tiền tố có sẵn mở màn Sửa từ với cả name, chữ của mục chọn sẵn, chọn chữ khác là đổi chữ của mục

Khớp mockup bản 3 khung M5b (https://claude.ai/artifact/JwiiU3XFYTk7Rz1hAMS7G2, anh Bửu duyệt) — trước đó màn Sửa từ chỉ hiện chữ của mục.

- Chạm chip có sẵn ở màn Quản lý tiền tố, hậu tố và chip ✓ ở hàng Tiền tố / Hậu tố của màn duyệt lọc name local ⇒ màn Sửa từ với **cả name** (古赫密斯语), chữ của mục chọn sẵn (语, phần còn lại mờ), nới / thu bằng ‹ › như khi thêm. Hậu tố ưu tiên lần nằm cuối, tiền tố lần nằm đầu (`LocalNameFilterAffixListFlavor.selection(of:in:)`).
- Lưu: phần chọn là chữ cũ ⇒ cập nhật mục (nghĩa / loại / vị trí / R | C như trước); chữ khác (phải nằm cuối với hậu tố / đầu với tiền tố) ⇒ đổi chữ của mục — thay khoá cũ cùng phạm vi, kiểm trùng như đổi chữ gốc, dòng "Đổi 语 thành 斯语"; "Cập nhật" mờ + dòng nhắc khi không nằm cuối / đầu, chọn cả cụm, quá 6 chữ như M5. Ô nghĩa: chữ cũ ⇒ nghĩa đang lưu, chữ khác ⇒ phiên âm (đã gõ thì giữ). "Về bản gốc" giữ. Đổi chữ chưa lưu ⇒ vuốt đóng hỏi "Bỏ thay đổi?". Lưu xong ghép lại nghĩa cả name mang chữ cũ lẫn chữ mới + toast như trước.
- Màn Sửa từ chế độ danh sách có thêm chỗ cắm `DictEntryEditListMode.sourceEditingKey` (sửa một mục trong cụm nguồn: tiêu đề "Sửa từ", nút "Cập nhật", `replacing` luôn là khoá đó). Các chế độ khác không đổi.
- Chọn một phần của chip ✓ không còn là "thêm mục mới" — thêm mới qua chip "+ X" / "+ Thêm …".

## [1.3.1116] - 2026-11-28

### feat: màn Sửa từ của màn duyệt lọc name local có hàng Phân loại đổi nhóm name, ghép lại nghĩa theo nhóm mới

Plan "Tiền tố hậu tố riêng truyện" mục C11, mockup bản 3 https://claude.ai/artifact/JwiiU3XFYTk7Rz1hAMS7G2 khung M2 (anh Bửu duyệt).

- Hàng **Phân loại** (`LocalNameFilterReviewCategoryRow`) đứng trên hàng Tiền tố trong khối hàng phụ của màn Sửa từ (luồng lọc name local, mọi name trừ họ tộc): nhãn + nút "?", bốn ô Nhân danh / Địa danh / Tổ chức / Thuật ngữ có chấm màu của badge nhóm (`LocalNameFilterCategoryBadge.color(for:)`), bên phải ghi "Lúc lọc: X" khi đã đổi khác nhóm lúc lọc (chỉ nhớ trong lượt duyệt).
- Đổi nhóm ⇒ badge và số trên chip lọc của màn duyệt đổi ngay, hàng Tiền tố / Hậu tố gợi ý loại theo nhóm mới (`affixKind(for:)` nay đọc nhãn badge, chỉ hỏi loại lúc lọc để loại họ tộc). `LocalNameFilterReviewSuffixContext.changeKind` xếp vào cùng hàng đợi với ghép lại sau khi thêm hậu tố: ghi nghĩa máy + loại mới vào gói tạm (`autoMeanings`), ghép lại nghĩa theo nhóm mới chỉ khi nghĩa đang hiện chưa sửa tay (đổi cả cờ "đoán"). Gói cũ không có nghĩa máy ghép ⇒ chỉ đổi nhãn. Không nhớ cho lần lọc sau.
- Phần "lấy mô hình Latin + dựng bộ ghép bằng danh sách hiệu lực của truyện + chạy ngoài main" tách thành `composeMeanings` dùng chung cho ghép lại sau khi thêm hậu tố và đổi phân loại.

## [1.3.1115] - 2026-11-28

### feat: tiền tố hậu tố riêng truyện ở màn Sửa từ có cụm R | C, màn quản lý tiền tố hậu tố của name và chip phạm vi ở danh sách

Giao diện cho kho tiền tố / hậu tố riêng truyện (plan "Tiền tố hậu tố riêng truyện" mục B6, B7, C9; mockup bản 3 https://claude.ai/artifact/JwiiU3XFYTk7Rz1hAMS7G2 khung M2–M6, anh Bửu duyệt). Lõi (kho riêng + API phạm vi) đã có ở commit trước.

- Màn Sửa từ chế độ danh sách có thêm hai chỗ cắm (`DictEntryEditListMode`): `caseRowTrailing` (phần đặt cuối hàng aa…AA) và `interceptSave` (nơi mở nhận việc lưu để hỏi lại trước). Các chế độ khác không đổi.
- Cụm **R | C** `DictEntryEditScopeToggle` (kiểu nút đoạn R | C của panel Dịch Reader, không ghim) ở màn thêm / sửa hậu tố, tiền tố khi mở từ một truyện (`LocalNameFilterSuffixEditorSheet(bookId:)`): thêm mới mặc định R, sửa thì đúng phạm vi của mục; badge còn "Hậu tố" / "Tiền tố". Ghi qua `store.save(...scope:bookId:original:)`: C → R tạo bản riêng (bản chung giữ cho truyện khác), R → C ghi lên chung rồi xoá bản riêng — chung đã có chữ đó ⇒ hộp "Ghi đè hậu tố chung X?" trước khi ghi. "Về bản gốc" / "Nghĩa gốc" chỉ khi đang ở C. Callback lưu đổi thành `SaveRequest` (khoá, nghĩa, loại, vị trí, phạm vi, mục bị thay).
- Hàng Tiền tố / Hậu tố ở màn Sửa từ của màn duyệt đọc danh sách hiệu lực của truyện (riêng rồi chung không trùng chữ, `LocalNameFilterAffixScopedEntry`): chip ✓ mở đúng phạm vi, ● tính trên danh sách hiệu lực, "+ X" / "+ Thêm …" mặc định R. Luật "nằm trong name" dời vào `LocalNameFilterAffixListFlavor.usablePosition` để màn quản lý dùng chung. Không có thao tác nhấn giữ.
- Nút tròn ⚙ (dáng nút Quản lý nghĩa, màu nhấn) cuối dòng "Tiền tố" ⇒ màn **Quản lý tiền tố, hậu tố** (`LocalNameFilterAffixManagerView` + `LocalNameFilterAffixManagerGroupView`): name + âm Hán-Việt, một thẻ bốn nhóm Tiền tố · Riêng truyện / Chung, Hậu tố · Riêng truyện / Chung, chỉ mục nằm trong name (cùng luật chip ✓), nhóm rỗng "Chưa có"; chip chung bị bản riêng che thì mờ + "bị che". Chạm chip ⇒ Sửa từ của mục; ⓧ ⇒ hỏi "Xoá hậu tố X?" (dòng phụ nói phạm vi) rồi xoá; "+ Thêm" ⇒ Thêm từ với cả cụm, R | C theo nhóm. Mỗi thao tác lưu ngay, ghép lại nghĩa các name trong màn duyệt + toast "Đã thêm / Đã lưu / Đã xoá hậu tố X · ghép lại N name". Khối hàng phụ `LocalNameFilterReviewAffixRows` giữ màn quản lý và số `revision` để hai hàng đọc lại sau mỗi lần ghi.
- Màn danh sách Hậu tố / Tiền tố mở từ sheet Lọc name local (`LocalNameFilterSuffixListView(flavor:bookId:)`) có hàng chip phạm vi "Chung N · Riêng truyện N" trên hàng chip loại; Riêng truyện thêm / sửa / xoá trên kho riêng, hàng không ghi "tự thêm"; "Khôi phục mặc định" chỉ cho Chung. Hàng của sheet ghi "1.299 · N riêng" khi truyện có mục riêng.

## [1.3.1114] - 2026-11-28

### feat: màn Sửa từ có hàng Tiền tố, Hậu tố mở vừa khít nội dung thay vì nửa màn

Mockup https://claude.ai/artifact/JwiiU3XFYTk7Rz1hAMS7G2 khung M2, mục C10 (sheet Sửa từ có hai hàng Tiền tố / Hậu tố mở
vừa khít nội dung, tối đa toàn màn; luồng AI và từ điển giữ nửa màn).

- `DictEntryEditSheet` chế độ từ điển có `accessoryRows` (màn duyệt Lọc name local, mọi name trừ họ tộc) ⇒ bộ nấc
  `[.height(vừa khít), .large]` với `presentationDetents(_:selection:)`: mở ở nấc cao đúng từ tiêu đề tới nút Cập nhật +
  hàng tra cứu ngoài, vẫn kéo lên toàn màn được; nội dung dài hơn màn thì hệ thống kẹp ở toàn màn, cuộn như cũ.
- Đo bằng `GeometryReader` + `PreferenceKey` (iOS 17) ở `DictEntryEditSheet+FittedDetent`: sheet mở ở nấc tạm đã biết
  giá trị (420pt) ⇒ số đo vùng cuộn đầu tiên cho phần đầu sheet ngoài vùng cuộn (tính một lần rồi giữ, ngoài 20…140pt ⇒
  56pt); nấc vừa khít = phần đầu + chiều cao tự nhiên của nội dung trong `ScrollView`. Lần khớp đầu lên hoặc xuống, sau
  đó chỉ nâng (chip / token / hàng phụ về muộn), không hạ ⇒ gõ chữ, bàn phím hiện / ẩn không làm sheet giật. Nấc vừa
  khít đổi chỉ dời lựa chọn khi đang ở nấc vừa khít cũ; đã kéo lên `.large` thì giữ.
- Luồng AI, từ điển, Pronouns, chế độ danh sách giữ nguyên bộ nấc cũ (`.medium` + `.large`, danh sách chỉ `.large`).

Chưa biên dịch được tại chỗ (Windows); check_architecture chỉ còn violation cũ JSDom.swift.

## [1.3.1113] - 2026-11-28

### feat: màn duyệt tên riêng có nút ▼ thay chữ Lưu, menu thêm Xuất file các mục đang tích

Mockup https://claude.ai/artifact/JwiiU3XFYTk7Rz1hAMS7G2 khung M1, mục C8 (anh Bửu chốt: nút ▼ thay chữ Lưu, xuất mục
đang tích). Áp cho cả luồng AI và Lọc name local (`ReaderAINameReviewSheet`).

- Góc phải header: icon `arrowtriangle.down.fill` 17pt nửa đậm, khung `HeaderMetrics.iconFrameWidth` ×
  `iconFrameHeight` canh phải (mép icon chạm lề), `ToolbarItem(.topBarTrailing)`, nhãn trợ năng "Lưu hoặc xuất name".
  Menu luôn mở được: "Lưu vào Name riêng" (person.fill) · "Lưu vào VP riêng" (character.book.closed) — giữ y hành vi cũ
  kể cả popup ba cách lưu, mờ khi chưa tích mục nào — · ngăn cách · "Xuất file" (square.and.arrow.up, dòng phụ "N mục
  đang tích"), mờ khi không có dòng nào để xuất.
- Xuất file (`ReaderAINameReviewSheet+Export`): nội dung là **đúng** tập Lưu sẽ ghi — `recordsToSave` mới ở `+Save`
  (mục đang tích, luồng AI bỏ hàng gạch, khoá đã trim, nghĩa `normalizeMeaning`, khoá lặp giữ mục đầu, cùng luật
  `AIHarnessService.saveExtractedEntries`); phép đếm "đã có" của popup Lưu cũng đọc từ đây. Mỗi dòng `chữ Hán=nghĩa`
  UTF-8, file `Name_<tên truyện>_<yyyyMMddHHmmss>.txt` ở thư mục tạm, mở `ShareSheet` (không kính); ghi lỗi ⇒ toast lỗi
  + log ❌; chia sẻ xong toast "Xuất file name thành công!".
- Đặt tên file tách thành `DictionaryExportFileName` (Views/Dictionary) dùng chung với danh sách VP / Name
  (`DictionaryListView.generateExportURL`): tên truyện DB ⇒ tên truyền vào ⇒ `bookId` ⇒ "Chung", luôn dịch qua
  `ChineseTextPipeline.meta` (phồn → giản theo truyện), bỏ ký tự cấm; `exportNameOptions` dời vào đó. Tên file danh sách
  VP / Name không đổi.
- Tên truyện: luồng lọc local tra `Book` theo `bookId` trong `modelContext` (chỉ khi container có `Book` trong schema,
  không thì lùi về `bookId`); luồng AI nhận `exportBookTitle` = tên truyện màn AI đang hiện (màn AI có thể mở bằng
  UIKit, không có `ModelContainer`) nên tên file luồng AI theo tên hiển thị.

Chưa biên dịch được tại chỗ (Windows); check_architecture chỉ còn violation cũ JSDom.swift.

## [1.3.1112] - 2026-11-28

### feat: lọc name local tách tiền tố hậu tố khỏi tên Latin, luật L16 theo hậu tố khi lõi là tên Latin, thêm tiền tố hậu tố riêng truyện

Plan "Tiền tố hậu tố riêng truyện" (anh Bửu duyệt 2026-11-28, mockup https://claude.ai/artifact/JwiiU3XFYTk7Rz1hAMS7G2)
phần A + B4–B5, chép đúng bản tham chiếu `Docs/Plans/local-name-filter-lac/name_meaning.py` (`latin_affixed`) và
`lacpipe.py` (`latin_core`, L16).

- A1 tên kiểu Latin: `LocalNameFilterProperNames.latinAffixed` (file mới `+Latin`) bỏ tiền tố ở đầu (danh sách Tiền tố,
  mọi loại) và / hoặc hậu tố ở cuối (mọi mục danh sách Hậu tố, kể cả Nhân danh, 1–6 chữ), dài nhất trước, ít nhất một
  phía; lõi ≥ 2 chữ, không dấu ngăn, ra tên Latin qua `latinName(of:)` và khác âm Hán-Việt ⇒ "tiền tố + Latin + hậu tố"
  theo vị trí. `LocalNameFilterMeaningBuilder` gọi ngay sau `nameLike` ở cả hàng bộ luật lẫn hàng phía LAC, mọi loại trừ
  họ tộc; tên người vẫn báo danh xưng. 古赫密斯语 ⇒ "cổ Hermes ngữ", 古弗萨克语 ⇒ "cổ Fusak ngữ", bật Latin: 鲁恩语 ⇒
  "Ruen ngữ", 莫里安语 ⇒ "Morian ngữ". `LocalNameFilterProperNames.init` thêm `affixes:` bắt buộc.
- A2 L16 (`LocalNameFilterLACPipeline+Kind`): LAC bảo người + đuôi yếu + hậu tố địa danh / tổ chức, sau L2 / L1: phần
  trước hậu tố (hoặc nó bỏ một tiền tố của danh sách) có ≥ 1 nghĩa từ điển (tách `/` `|` `;`) là chữ Latin khác âm
  Hán-Việt, khoá có chữ phiên âm ⇒ theo hậu tố (`hasLatinCore`), không theo công tắc Latin. 霍伊河 Nhân danh ⇒ Địa danh
  ("Hoắc Y hà", bật Latin "Khoy hà"), 苏尼亚海 ⇒ Địa danh "Sonia hải". `LocalNameFilterLACPipeline` thêm `properNames`.
- A3 `LocalNameFilterMeaningComposer.rulesVersion = 3` ⇒ mọi gói tạm ghép lại một lần (nghĩa đã sửa tay giữ).
- B4 kho riêng truyện `LocalNameFilterBookAffixStore` (`.suffixes` / `.prefixes`, `UserDefaults`
  `localNameFilterBookSuffixes` / `localNameFilterBookPrefixes` = JSON theo `bookId`, Backup tự gói): thêm / sửa / xoá
  cùng luật khoá + nghĩa với danh sách Chung, trùng khoá trong truyện ⇒ lỗi. Đổi nguồn gộp theo khoá (mục truyện cũ
  thắng), xoá truyện / bản cũ sau mốc chốt xoá theo (`BookSourceMigrator`, `BookStorageManager.deleteBookSideData`).
- B5 danh sách hiệu lực = Riêng + Chung, Riêng thắng cùng chữ: `LocalNameFilterAffixListStore.effective(bookId:)`,
  `LocalNameFilterSuffixStore.allSuffixes(bookId:)`, `LocalNameFilterPrefixStore.allPrefixes(bookId:)`; thao tác theo
  phạm vi R | C + chuyển R ↔ C (`+Scope`: `Scope`, `ScopedKey`, `keyError(_:scope:bookId:original:)`,
  `save(...scope:bookId:original:)`, `delete(key:scope:bookId:)`). Sheet Lọc name local, gói tạm tự cập nhật, dấu gói
  tạm, ghép lại ở màn duyệt đổi sang bản theo truyện; `signature` / composer / `DraftRefresher.Inputs` bỏ mặc định
  `prefixes`. Bộ dò `detectionSuffixes` không đổi; giao diện chưa đổi.

## [1.3.1111] - 2026-11-28

### fix: lọc name local ghép nghĩa bằng hậu tố dài nhất cho cả name của bộ luật, tên kiểu Hán luôn bóc tiền tố hậu tố thay vì lấy nghĩa VP cả cụm

Anh Bửu (2026-11-28, ảnh 瑶池仙阁 "Dao Trì Tiên Các" dù đã có hậu tố 仙阁 = tiên các; "tên không phải la tinh thì dùng tiền
tố hậu tố thôi được rồi sao dùng vp nữa"; duyệt cách 2).
- `LocalNameFilterMeaningBuilder`: hàng bộ luật địa danh / tổ chức lấy hậu tố **dài nhất** của danh sách người dùng khi nó
  dài hơn đuôi đã dò (như hàng phía LAC) — trước đó chỉ lấy đuôi đã dò 阁 nên mục VP 仙阁 "Tiên Các" nuốt cả cụm. Hai
  đường dùng chung `suffixed(_:_:)`.
- `LocalNameFilterProperNames.coverAll` (phủ trọn cả từ bằng mục từ điển, 贝克兰德东区 ⇒ "Backlund Đông Khu"): chỉ còn áp
  cho name có phần tên Latin thật — mục nghĩa chữ Latin và khác âm Hán-Việt của khoá (`isRealLatin`, "Tinh La" của 星罗
  không tính). Tên kiểu Hán luôn bóc hậu tố theo danh sách: 昆仑神宫 ⇒ "Côn Luân Thần cung", 北境五州 ⇒ "Bắc Cảnh Ngũ
  châu". Phần tên vẫn tra VP (玄武 Huyền Vũ, 乾坤 Càn Khôn); name có sẵn cả cụm trong Name / VP giữ nghĩa từ điển.
- Dấu gói tạm có số `rulesVersion` = 2 ⇒ mọi gói tạm ghép lại nghĩa một lần (nghĩa người dùng đã sửa vẫn giữ).
- Bản tham chiếu Python `name_meaning.py` sửa trước; đo 11 truyện (danh sách gốc + 仙阁): 9 hàng mới đổi nghĩa (瑶池仙阁 +
  8 hàng chỉ đổi hậu tố về chữ thường), không thêm / mất / đổi loại hàng nào, tên Latin và name đã có không đổi. Phương án
  bỏ hẳn VP cho tên không Latin đo 410 hàng đổi, hỏng tên Nhật / tây và chữ đa âm (Naruto ⇒ Minh Nhân, Tingen ⇒ Đình Căn,
  Đái Hạo ⇒ Đới Hạo) — không làm.
- `translation.md` cập nhật đoạn Nghĩa và Gói tạm tự cập nhật.
Chưa biên dịch được tại chỗ (Windows); check_architecture chỉ còn violation cũ JSDom.swift.

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
