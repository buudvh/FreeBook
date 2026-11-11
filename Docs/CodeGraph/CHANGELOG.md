# CHANGELOG - Nhật ký Thay đổi CodeGraph Tàng Công Các

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **Tàng Công Các**.

## [1.3.859] - 2026-11-11

### feat: widget TTS chỉ còn kiểu nửa viên thuốc, bỏ kiểu Đĩa nổi và hàng Widget TTS ở Cài đặt

Anh Bửu: "giữ lại 1 kiểu thôi widget thôi nhé, là widget của tts thôi ấy". Widget TTS chỉ còn **đĩa nghe** dùng chung với nhạc (nửa viên thuốc dính mép của 1.3.858 + ô giữa thanh tab); kiểu **Đĩa nổi** (trước là mặc định) bỏ hẳn.

- `MediaDiscWindowManager.resolveKind`: TTS có phiên ⇒ đĩa TTS, không còn xét kiểu widget. Ai đang dùng Đĩa nổi tự sang đĩa nghe; ô giữa thanh tab có đĩa thật khi đang nghe truyện (trước đó là đĩa xám nếu chọn Đĩa nổi).
- **Xoá 9 file**: `FloatingWidgetContainerViewController`, `FloatingWidgetUIWindow`, `FloatingWidgetViewModel`, `TTSFloatingWidgetView`, `TTSFloatingWidgetWindowManager`, `TTSFloatingWidgetContaining`, `TTSWidgetStyle`, `TTSWidgetPreferences`, `TTSWidgetSettingsView`. Khoá `ttsWidgetStyle` / `ttsWidgetVerticalRatio` / `ttsWidgetEdge` bỏ mặc, không đọc nữa.
- `TTSCoverView` + `TTSCoverImageLoader` (mặt đĩa TTS và sheet điều khiển nhanh dùng) dời ra file riêng trong `Views/TTSWidget/` trước khi xoá file cũ.
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

## [1.3.843] - 2026-11-11

### perf: mục lục truyện tranh dựng hàng một lần và giữ dòng nhóm khi tìm hay đảo thứ tự

Anh Bửu: *"vì sao mở danh sách chương ở commic hiển thị lâu vậy?"*, *"xem cách hiển thị khác gì danh sách chương của reader"*, *"nếu có group thì vẫn nên để group"*.

- **Nguyên nhân có khả năng (đọc code, so với mục lục Reader; chưa đo trên máy):** mỗi lượt vẽ, `ComicChapterListSheet` lọc / đảo / đánh số **cả** mục lục trên main; mỗi hàng bọc `Group { if dòng nhóm … else hàng chương … }` (Reader ghi rõ kiểu bọc này có thể buộc `List` dựng mọi hàng để đếm); không có vỏ chặn vẽ lại nên mỗi lượt vẽ của màn đọc (ảnh tải xong, dịch xong tên chương…) kéo cả mục lục tính lại; tìm thì lọc toàn bộ trên main mỗi phím.
- `ComicChapterListRows` (mới, hàm thuần): dựng hàng + số thứ tự **một lần** mỗi khi mục lục / ô tìm / thứ tự / công tắc "Hiện số thứ tự" đổi (`.task(id:)`); mục lục > 400 dòng dựng ngoài main kèm vòng xoay, lượt mới huỷ lượt cũ.
- **Dòng nhóm luôn giữ** (trước đây ẩn khi tìm hoặc xếp giảm dần): mục lục chia nhóm theo thứ tự gốc; giảm dần ⇒ đảo thứ tự nhóm và chương trong nhóm, tiêu đề vẫn trên chương của nó; tìm ⇒ giữ tiêu đề trên các chương khớp của nhóm (tiêu đề tự khớp ⇒ giữ cả nhóm, nhóm không còn gì ⇒ ẩn). Số thứ tự vẫn theo mục lục đầy đủ.
- `ComicChapterListRow` (mới): một kiểu hàng cho mọi phần tử (dòng nhóm hoặc chương, cùng dáng như trước); nền hàng / màu vạch gắn ở `List`.
- `ComicChapterListHost` (mới): vỏ không trạng thái `.equatable()` như `ReaderChapterListHost` (`==` so mục lục, chương đang đọc, chương đã tải, bật dịch, `Book` theo identity, launch, thứ tự).
- Log `📚 [ComicTOC] Mở mục lục N dòng (M hiện): có hàng sau X ms` (bật log) để đo trên máy.
- `ComicTranslationStatus` nhận thêm `sourceName` / `definitionRequest` (chuyển từ `ComicReaderView`, giữ file đó dưới 400 dòng).
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows), chưa thử máy. Cần thử: (1) mở mục lục truyện dài — xem log `📚 [ComicTOC]`; (2) truyện có nhóm: đảo thứ tự, tìm — tiêu đề nhóm vẫn đúng chỗ; (3) gõ tìm liên tục không giật; (4) cuộn tới đúng chương đang đọc khi mở.

## [1.3.842] - 2026-11-11

### fix: đọc lại từ đầu chương thì trang cũng về đầu chương và tự cuộn theo

Rà lại 1.3.841 trước khi đẩy: người bấm nút tai nghe giữa lúc nghe thường đang ở giữa chương, hay đã tự kéo trang (kéo trang lúc TTS đọc ⇒ tắt tự cuộn theo highlight, chỉ lệnh nhảy của widget bật lại). Chọn "Đọc lại từ đầu chương" khi đó thì tiếng đọc về tên chương nhưng trang đứng yên giữa chương và không đi theo nữa.

- `ReaderView+TTSSameChapterPrompt`: sau khi đọc lại từ đầu chương ⇒ bật lại tự cuộn (`reenableTTSAutoScrollFromWidgetJump`) rồi cuộn tới đầu chương (`ScrollTarget` đoạn -1 ⇒ `ReaderScrollCoordinator` cuộn tới mốc `chapter-N`; tên chương không có highlight nên tự cuộn không tự kéo tới). Reader đã sang chương khác trong lúc sheet mở ⇒ mở lại chương được hỏi.
- "Đọc từ đoạn đang xem" giữ đúng hành vi cũ (đoạn đó đang trên màn hình).
- Nhãn trợ năng của nút tai nghe: bỏ "Dừng đọc thành tiếng" (nút không dừng đọc, giờ mở sheet hỏi) ⇒ luôn "Đọc thành tiếng". Chuyển `[1.3.812]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows), chưa thử máy. Cần thử: đang nghe giữa chương, kéo trang đi, bấm tai nghe → "Đọc lại từ đầu chương" ⇒ trang về đầu chương và cuộn theo đoạn đang đọc.

## [1.3.841] - 2026-11-11

### feat: bấm nút tai nghe trúng chương đang phát thì hỏi đọc tiếp, đọc từ đoạn đang xem hay đọc lại từ đầu chương

Anh Bửu: *"nếu như bấm nút nghe truyện mà chương được bấm nghe cũng đang phát thì hãy hiển thị message hỏi"*; chê hộp thoại giữa màn của iOS (*"màn hỏi hơi xấu"*), chọn kiểu sheet kính.

- **Trước đây**: nút tai nghe nổi của Reader, khi TTS đang phát đúng chương đó, dừng phiên rồi đọc lại từ **đoạn trên cùng màn hình** ⇒ bấm nhầm là mất chỗ đang nghe.
- **Giờ**: TTS **đang phát** đúng truyện + đúng chương mà nút sắp đọc (chương của đoạn trên cùng màn hình, tính như cũ) ⇒ mở sheet `ReaderTTSSameChapterSheet` (mới), chưa đụng phiên TTS. Khuôn `TTSQuickControlSheet`: nền kính ngăn kéo, cao vừa nội dung, vuốt xuống để đóng (không nút Huỷ). Hàng đầu: đĩa bìa xoay + tên truyện + tên chương + nhãn "Đang đọc" / "Tạm dừng". Ba hàng:
  - **Đọc tiếp chỗ đang đọc** — không dựng lại phiên; trang về đoạn đang đọc + bật lại tự cuộn (cùng đường nhảy của widget, tách thành `jumpToPlayingTTSPosition` dùng chung với `navigateReaderToPlayingChapter`); tạm dừng giữa lúc sheet mở ⇒ phát tiếp; phiên đã tắt ⇒ đọc từ đoạn đang xem.
  - **Đọc từ đoạn đang xem** — đúng hành vi cũ (đoạn chụp lúc bấm, vì TTS vẫn đọc và trang vẫn tự cuộn khi sheet mở).
  - **Đọc lại từ đầu chương** — chunk đầu (tên chương nếu TTS đọc tên chương).
- **Không đổi**: tạm dừng mà đoạn đang dừng còn trên màn hình ⇒ phát tiếp ngay; tạm dừng đã kéo trang đi / chương khác / truyện khác ⇒ đọc từ đoạn trên cùng màn hình; "Nghe" của menu bôi đen đọc ngay chỗ đã bôi. Ngoài Reader không có lối nào bắt đầu đọc một chương (Chi tiết, Kệ, widget, hub chỉ phát tiếp / dừng / mở Reader).
- Sheet gắn neo `.blocker` ⇒ đĩa nghe góc dưới ẩn trong lúc sheet mở (không thì đè lên hàng cuối). Đĩa nổi (cửa sổ riêng) vẫn có thể che sheet như mọi sheet khác của Reader.
- Logic nút tai nghe chuyển từ `ReaderView+Controls` sang `ReaderView+TTSSameChapterPrompt` (mới); `ReaderView` thêm 2 `@State` (yêu cầu đang hỏi + chiều cao sheet đo được) và gắn sheet ở tầng sheet gốc. Chuyển `[1.3.811]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows), chưa thử máy. Cần thử: (1) đang nghe, bấm tai nghe ở chương đang đọc ⇒ hiện sheet, ba lựa chọn làm đúng; (2) kéo trang đi rồi chọn "Đọc tiếp" ⇒ trang về đoạn đang đọc và tự cuộn lại; (3) chương khác / đang tạm dừng ⇒ không hỏi như cũ; (4) kiểu widget Đĩa góc dưới ⇒ đĩa ẩn khi sheet mở, hiện lại khi đóng.

## [1.3.840] - 2026-11-11

### fix: phụ đề cứng ghép chữ đúng kiểu phụ đề Trung, dịch theo công tắc dịch của phim, thêm Từ điển truyện vào trình phát

Anh Bửu thử 1.3.830: *"Dịch phụ đề cứng … ra nghĩa gì tầm bậy nhìn không hiểu"*, *"vì sao cùng OCR mà commic đúng còn video sai?"*, rồi *"áp dụng bật tắt dịch và từ điển như truyện tranh và truyện chữ luôn nhé"*; chốt **giữ công tắc "Đọc phụ đề cứng"**, còn dịch thì theo bật/tắt dịch.

- **Nguyên nhân dịch tầm bậy** (cùng Vision + VietPhrase với truyện tranh, khác ở khâu ghép chữ trước khi dịch): (1) xoá mọi khoảng trắng, trong khi phụ đề Trung dùng **dấu cách thay dấu phẩy** ⇒ hai vế dính nhau; (2) mảnh cùng hàng xếp theo chiều dọc và chỉ giữ 2 mảnh cuối ⇒ đảo vế / rơi vế; (3) dịch từng hàng thay vì cả câu. `VideoHardSubtitleRecognizer` giờ: khoảng trắng giữa hai chữ Hán ⇒ `，` (cạnh dấu câu toàn khổ ⇒ nối liền, chữ Latin ⇒ dấu cách); mảnh gom theo hàng (chồng dọc ≥ 50% mảnh thấp hơn), trong hàng xếp trái → phải; bỏ mảnh sát mép (tâm ngang ngoài 5–95%) và mảnh không có chữ Hán; hàng cần ≥ 2 chữ Hán, tâm 15–85%; hàng dưới cùng + hàng gần nhất ngay trên nối thành **một câu**, hàng bắt đầu bằng gạch ngang (thoại hai người) giữ xuống dòng.
- **Dịch theo công tắc dịch của phim** như truyện chữ / truyện tranh / phụ đề mềm: `VideoHardSubtitleEngine+Translation` (mới) dùng `MediaCaptionTranslator.prepare` (phim này > nguồn > nguồn tự khai tiếng Trung > toàn cục; phồn→giản theo phim / nguồn — bỏ "luôn phồn→giản" của 1.3.830) + `MediaCaptionTranslator.translate`. Phim tắt dịch hoặc kiểu "Gốc" ⇒ engine ngưng đọc (không có gì để phủ, đỡ pin), lớp phủ không vẽ, phụ đề mềm hiện lại (`VideoPlayerStage` chỉ ẩn phụ đề mềm khi đang đọc **và** đang dịch). Đổi cấu hình dịch / từ điển / rule (ba thông báo có sẵn: `TranslationConfigStore.didChangeNotification`, `.translationDictionariesDidUpdate`, `.quickTranslationRulesDidUpdate`) ⇒ dựng lại `Pass`, xoá đệm, dịch lại câu đang hiện. Engine tách phần dịch sang file `+Translation` để file chính dưới 400 dòng.
- **Ngăn kéo `⋯`** của trình phát: công tắc đổi tên **"Đọc phụ đề cứng"** (khoá cũ `videoHardSubtitleOCRByPackage` giữ nguyên). Đang đọc ⇒ hàng "Phim đang tắt dịch" (khi phim tắt dịch, mở sheet "Dịch phụ đề") + lưới **Gốc / Bản dịch / Song ngữ** (cùng khoá `videoSubtitleDisplayMode` với phụ đề mềm; Song ngữ = bản dịch + chữ Trung OCR nhỏ bên dưới để đối chiếu). Hàng "Dịch phụ đề" hiện cả khi chỉ đọc phụ đề cứng; thêm **"Từ điển truyện"** (`VideoBookDictionarySheetModifier` mới, `BookDictionaryView` dạng sheet theo `bookId` của phim — phim đang phát luôn có `Book` ẩn; đóng ⇒ dịch lại phụ đề mềm).
- Lớp phủ (`VideoHardSubtitleOverlay`) vẽ theo kiểu hiển thị, câu không có bản dịch ⇒ không vẽ. Log mỗi câu mới `🔤 [VideoOCR] «chữ Trung» ⇒ «bản dịch»` (theo công tắc log).
- Chưa làm: chạm phụ đề mở màn Dịch (dùng lại sheet của truyện tranh, để sau); giảm trễ / nhớ câu theo thời điểm / quét trước tập đã tải (chờ anh chốt). Không đọc trước được khung của luồng đang phát.
- `CLAUDE.md` / `AGENTS.md`: viết lại gạch "Đọc phụ đề cứng (OCR)". Chuyển `[1.3.810]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới** (`VideoHardSubtitleEngine.swift` 361 dòng, `VideoPlayerScreen.swift` 385, `VideoPlayerTopBar.swift` 356). Không build tại chỗ (Windows), chưa thử máy. Cần thử: (1) phim có phụ đề Trung tách vế bằng dấu cách — bản dịch đọc hiểu được, đặt Song ngữ để so chữ Trung OCR với chữ trong phim; (2) tắt dịch ở sheet "Dịch phụ đề" ⇒ lớp dịch biến mất, phụ đề mềm (nếu có) hiện lại, bật lại ⇒ dịch ngay; (3) thêm name ở "Từ điển truyện" ⇒ câu đang hiện đổi theo; (4) gửi log `🔤 [VideoOCR]`.

## [1.3.839] - 2026-11-11

### feat: chọn bộ dịch tiện ích và ngôn ngữ trong popup dịch, màn cấu hình tiện ích dịch có model, kiểu dịch, dịch thử

Phần C (giao diện) của plan tiện ích dịch truyện, gộp commit gốc và bản sửa theo review phản biện. Bộ dịch chỉ chọn ở popup dịch, không thêm vào Cài đặt (anh Bửu chốt).

**Popup dịch** (`TranslationScopePopupView`: header Reader, Chi tiết, menu Khám phá). Thứ tự: Dịch văn bản → PHẠM VI ÁP DỤNG → **BỘ DỊCH** → **NGÔN NGỮ** → hàng báo QT thay thế → Lưu lại.
- **Bộ dịch** (`TranslationEnginePickerSection`, mới):
  - Danh sách xổ tại chỗ, có icon. Không dùng `Menu` hệ thống vì iOS đặt ảnh cuối dòng và tô một màu.
  - Thứ tự: "Theo cấp trên (…)" (chỉ ở phạm vi Truyện này / Nguồn này; tiện ích cấp trên đã gỡ ⇒ ghi "đã gỡ — đang dùng QT") → "QT (VietPhrase, có sẵn)" với icon app → tiện ích dịch đã cài.
  - Chưa cài tiện ích dịch nào ⇒ dòng "Chưa cài tiện ích dịch nào".
- **Ngôn ngữ** (`TranslationLanguagePickerRow`, mới):
  - Ô Dịch từ → Dịch sang theo `language.js`, có "Tự nhận" nếu tiện ích hỗ trợ. Dòng phụ ghi model · kiểu dịch.
  - Đang đọc ⇒ vòng xoay; lỗi ⇒ chữ đỏ + "Thử lại".
  - QT ⇒ hai ô mờ, ghi "QT chỉ dịch Trung → Việt".
- **Bản nháp** (`TranslationEngineDraft`, mới): mỗi phạm vi một bản nháp, nhớ cặp ngôn ngữ theo từng tiện ích. Chọn tiện ích mới ⇒ cặp mặc định (Trung → Việt nếu có).
- **Lưu lại**:
  - Chỉ ghi bộ dịch khi nó thật sự đổi.
  - Chỉ ghi công tắc bật/tắt khi người dùng gạt nó. Trước bản sửa: đổi phạm vi sang "Nguồn này" để chọn bộ dịch rồi Lưu là tắt dịch cả nguồn.
  - Khoá khi tiện ích vừa chọn chưa có cặp ngôn ngữ (đang đọc hoặc đọc lỗi).
- **Báo QT thay thế** (`TranslationFallbackNoticeRow`, mới): dùng chung chữ với dải báo đầu chương, có nút "Thử lại".
- **Ẩn ở truyện tranh**: tham số `showsEngineSection`; `ComicReaderChromeView` truyền `false` vì bộ dịch tiện ích không áp cho truyện tranh.

**Nút dịch** (`ReaderTranslationScopeMenuView`): nhận `chapterIndex`. Chương đang hiện có báo QT thay thế ⇒ chấm cam "!" ở góc dưới phải (chấm xanh/đỏ góc trên giữ nguyên).

**Màn Cấu hình tiện ích loại `translate`** (`ExtensionConfigView+TranslateEngine`, mới):
- Ẩn nút Trình duyệt / Kiểm tra, mục Duyệt và lịch sử, chặn quảng cáo / chế độ máy tính.
- Mục **Bộ dịch**: Model / Kiểu dịch, đầu danh sách là "Mặc định của tiện ích"; ghi ngay qua `TranslationExtensionSettingsStore`.
- Mục **Dịch thử**:
  - Ngôn ngữ chỉ dùng để thử, không lưu.
  - Ô nhập (để trống ⇒ dịch câu mẫu).
  - Nút "Dịch thử" luôn gọi script (`bypassCache`).
  - Ghi config đang chờ (khoá API) trước khi chạy.

**Tài liệu**: `CLAUDE.md` / `AGENTS.md` thêm đoạn "Bộ dịch bằng tiện ích loại `translate`" ở mục Dịch thuật.

**Kiểm chứng:**
- Đọc code + 2 agent review phản biện.
- `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 lỗi mới**. 5 file mới; `TranslationScopePopupView` 387 dòng.
- Không build tại chỗ (Windows), chưa thử máy.
- Cần thử:
  1. Xổ / thu danh sách bộ dịch: popover có giãn theo nội dung không.
  2. Chọn tiện ích ⇒ ngôn ngữ mặc định. Đổi phạm vi ⇒ nạp đúng lựa chọn đã lưu.
  3. Truyện tắt dịch riêng ⇒ chọn bộ dịch ở "Nguồn này" ⇒ nguồn vẫn bật dịch.
  4. Chấm cam + hàng báo + Thử lại.
  5. Dịch thử ngay sau khi nhập khoá API.

## [1.3.838] - 2026-11-11

### feat: dịch nội dung chương bằng tiện ích dịch trong Reader và TTS, báo khi dùng QT thay thế

Phần B của plan tiện ích dịch truyện (lõi 1.3.832 / 1.3.836). Gộp commit gốc và bản sửa theo review phản biện. Bộ dịch là tiện ích ⇒ nội dung chương truyện chữ và tên chương ở header Reader / TTS được dịch bằng tiện ích. Mục lục, Chi tiết, Khám phá, xuất TXT vẫn QT. Phần chọn bộ dịch ở popup là phần C (bản kế).

**Reader**
- Khi dịch bật và bộ dịch của truyện là tiện ích, `ReaderViewModel+ExtensionTranslation` (mới) gọi `TranslationExtensionChapterTranslator` với đúng các dòng sẽ dựng đoạn và tên chương. Bộ dịch tra lại mỗi lượt dựng qua `TranslationEngineStore.resolve` với `extensionPackageId`.
- `buildCancellable` nhận bản dịch sẵn theo `line.id`; không có thì chạy QT như cũ. Bản dịch của tiện ích không có span.
- Bỏ tên chương trùng gom về **một** hàm, `ChapterTextNormalizer.contentLines(of:removingDuplicatedTitle:)` (mới), dùng chung cho Reader, `TTSBackgroundProcessor` và lượt dịch bằng tiện ích. `getTTSChapterContent` trả nội dung chưa bỏ tên trùng, nên không còn bỏ hai lần.
- **Báo QT thay thế:**
  - Mỗi lần áp bản dựng, `applyPreparedTranslation` ghi `TranslationFallbackStatusStore`.
  - Dải báo đầu chương `ReaderTranslationFallbackBanner` (mới): nền cam 14%, icon tam giác, "Đang dịch bằng QT thay thế" + "<tiện ích> lỗi: <lỗi> · N/M đoạn", nút "Thử lại".
  - Dải vẽ trong `ParagraphCardView` của mục đầu chương (`chapterIndex` + `isChapterStart`). `ReaderView.swift` chỉ sửa tại chỗ.
- `ReaderExtensionTranslationObserver` (mới):
  - Đổi bộ dịch / ngôn ngữ / model / kiểu ⇒ chương đang hiện dựng lại.
  - "Thử lại" ⇒ dựng lại dù generation không đổi.
- `requestRetry` xoá cache dịch của truyện (cả lỗi đã nhớ) **ngay lúc xin**, để Reader và TTS dịch lại cùng một lượt. "Tải lại chương" cũng xoá cache dịch của truyện.
- `ParagraphCardView.displayText` hiện `translated` cả với dòng không có chữ Hán: tiện ích dịch được cả truyện tiếng Anh, và TTS đọc đúng chữ đó. Đường QT không đổi vì dòng không có chữ Hán có `translated == original`.

**TTS**
- 4 chỗ gọi `processChapter` đi qua `TTSExtensionTranslationPreparer.processChapterWithEngine` (mới).
  - Có snapshot hợp lệ của Reader thì dùng y, kể cả tên chương (`TTSPretranslatedSnapshot.originalTitle` / `translatedTitle`).
  - Không có thì dịch bằng translator rồi dựng snapshot.
  - Lượt chuẩn bị sẵn không bao giờ tự gọi tiện ích.
- TTS tra bộ dịch và công tắc dịch theo đúng `packageId` của Reader (`translationPackageId`; TXT tự nhập là `"local"`). Giá trị này đi theo khoá nạp trước chương kế.
- `TTSExtensionTranslationObserver` (mới):
  - Đổi bộ dịch của truyện đang phát (vân tay: tiện ích + ngôn ngữ + model + kiểu) ⇒ bỏ bản chuẩn bị sẵn, đọc lại chương đang phát từ đầu đoạn đang đọc.
  - "Thử lại" đúng chương đang đọc cũng vậy (`TTSManager+ExtensionTranslation`, khuôn `updateTranslationSetting`).
- `TTSTranslationFallbackNotifier` (mới):
  - TTS phải đọc bản QT ⇒ toast "<tiện ích> lỗi, TTS đọc bản QT thay thế", một lần mỗi chương, **chỉ lúc bắt đầu đọc chương đó** qua `TTSPresentationEventCenter`.
  - Ẩn khi Reader đã báo cho chương.
- `TTSPreparedChapter.chapterTitle`: bắt đầu đọc từ bản chuẩn bị sẵn thì không dịch QT lại tên chương.

**Kiểm chứng:**
- Đọc code, có 2 agent review phản biện. `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 lỗi mới**: 8 file mới, `TTSManager.swift` 3467 ⇒ 3458, `ReaderView.swift` 1957 ⇒ 1952.
- Không build tại chỗ (Windows), chưa thử máy.
- Cần thử:
  1. Bộ dịch là tiện ích ⇒ chương hiện bản tiện ích, header đúng tên chương.
  2. Tiện ích lỗi (sai khoá / tắt mạng) ⇒ dải báo; Thử lại khi TTS đang đọc ⇒ Reader và TTS cùng đổi, vệt khớp.
  3. Đổi model / ngôn ngữ khi đang nghe ⇒ TTS đọc lại từ đoạn đang đọc.
  4. TTS tự sang chương khi Reader đóng mà tiện ích lỗi ⇒ toast một lần.
  5. Truyện tiếng Anh dịch sang Việt ⇒ vệt highlight khớp cả dòng không có chữ Hán.
- Rủi ro còn lại:
  - Tiện ích treo thì Reader kẹt ở khung chờ.
  - Thử lại xoá cache dịch cả truyện.

## [1.3.837] - 2026-11-11

### feat: chạm khối dịch trong truyện tranh mở màn Dịch của Reader với chữ Trung gốc đã nhận

Anh Bửu: *"khi tôi nhấn vào vùng dịch trong trang đọc commic hãy hiển thị màn hình giống màn hình dịch của reader, đầu vào là đoạn tiếng trung gốc đã OCR"*.

- **Chạm một khối dịch** (trên trang và trong trình xem phóng to) ⇒ sheet **Dịch** = nguyên `ReaderDefinitionOverlayView` của Reader (nền xám đậm, cao vừa nội dung `fittedSheetDetent`, vuốt xuống để đóng), câu gốc = chữ Trung OCR của khối, lúc mở chọn sẵn cả câu. Đủ như Reader: chạm chữ / mũi tên nới thu vùng chọn, nghĩa VP / Hán-Việt, chip gợi ý, ⚙ quản lý nghĩa, lưu Name / VP riêng / chung kèm ghim mặc định (cùng khoá `@AppStorage` với Reader), chip rule + bật tắt / sửa / xoá / chuyển rule, nút `+` thêm rule, tra nhanh bằng công cụ tìm. **Nhấn giữ** khối ⇒ đổi gốc ↔ dịch (chức năng chạm cũ).
- `ComicDefinitionSheet` (mới, `Views/ComicReader/Definition/`, + `+Selection`, `+Rules`): giữ trạng thái như `ReaderView` và **chép** phần ráp nối của Reader (`ReaderView+Selection` / `+RuleTools` / `+DefinitionLoading` / `+SelectionSheets`, gắn chặt vào trạng thái của `ReaderView`); lõi dùng lại nguyên `ReaderDefinitionOverlayView`, `ReaderDefinitionWorker`, `ReaderDefinitionSession`, `QuickTranslationRuleEditorSheet`, `QuickTranslationRuleMutation`, `TranslationManager.saveCustomEntry`. **Không sửa `ReaderView`.** Câu gốc là bong bóng nên không soi bộ rule tên chương.
- Trên trang: `ComicTranslationOverlay` chạm ⇒ `onOpenDefinition`, nhấn giữ 0,4 s ⇒ đổi gốc / dịch; sheet gắn ở `ComicTranslationToolsModifier` (`definitionRequest`), mọi sheet của nó đóng ⇒ dịch lại bong bóng + tên chương.
- Trình xem phóng to: cover giờ là `ComicZoomScreen` (mới) = `ComicZoomViewer` + sheet Dịch của chính nó (sheet phải gắn trong cover). `ComicZoomTranslationLayer`: chạm ⇒ `onTapBlock`, nhấn giữ ⇒ đổi gốc / dịch. Đóng sheet Dịch ⇒ `revision` mới ⇒ trình xem dịch lại lớp của nó (giữ khối cũ tới khi có bản mới).
- `CLAUDE.md` / `AGENTS.md`: mục dịch ảnh.
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới** (`ComicReaderView.swift` 395 dòng). Không build tại chỗ (Windows), chưa thử máy. Cần thử: (1) chạm bong bóng ⇒ màn Dịch đúng câu gốc; (2) chạm một chữ / mũi tên đổi cụm, nghĩa đổi theo; (3) lưu một name ⇒ sheet đóng, bong bóng đang hiện đổi theo (cả trong trình xem phóng to); (4) nhấn giữ đổi gốc ↔ dịch, chạm ngoài khối vẫn bật / tắt thanh, chạm đúp vẫn phóng to.

## [1.3.836] - 2026-11-11

### fix: dịch bằng tiện ích gộp lượt trùng giữa Reader và TTS, nhớ lỗi gần đây, đổi nguồn mang theo bộ dịch

Sửa lõi phần A (1.3.832) theo review phản biện, trước khi nối vào Reader / TTS / giao diện.

- **Gộp lượt trùng** (`TranslationExtensionInflight`, mới). Reader và TTS (hoặc hai lượt nạp trước chương kế) xin dịch cùng các dòng với cùng cấu hình thì chỉ một lượt gọi tiện ích chạy, mọi bên nhận cùng kết quả.
  - Trước đây hai bên cùng trượt cache, gọi tiện ích hai lần. Với máy dịch kiểu AI, hai lần ra hai chữ khác nhau nên vệt highlight lệch.
  - Lượt chạy là `Task` riêng: bên cuối cùng rời đi vì huỷ thì lượt bị huỷ theo.
- **Nhớ lỗi gần đây** (`TranslationExtensionLineCache`, 90 s). Dòng vừa lỗi ở Reader thì TTS cũng lùi QT, không gọi lại rồi ra chữ khác. Đang bị giới hạn lượt thì không gọi dồn. "Thử lại" / tải lại chương xoá luôn phần này.
- **Thế hệ cache theo từng truyện**: xoá cache của truyện A không còn làm rơi lượt ghi đang chạy của truyện B.
- **Chia lô**:
  - Lỗi ở nửa sau không còn làm mất bản dịch của nửa đầu.
  - `max_length ≤ 0` (hợp đồng: không chia gì) ⇒ lệch số dòng thì cả lô tính lỗi, không chia đôi.
  - Gặp lỗi gọi tiện ích (không phải lệch dòng) ⇒ dừng gọi tiếp.
- **Tên chương**:
  - `title_trans` (bản QT tiếng Việt) chỉ dùng khi tiện ích dịch sang tiếng Việt. Dịch sang ngôn ngữ khác thì hiện tên tiếng Việt là sai.
  - Nội dung vừa gặp lỗi gọi tiện ích ⇒ tên chương lùi QT luôn, không tốn thêm một lượt gọi.
- `translateText(_:job:bypassCache:)`: ô Dịch thử luôn gọi script. Lỗi của tên chương cũng được nhớ.
- `BookSourceMigrator`: Đổi nguồn chép bộ dịch riêng của truyện sang truyện mới và xoá bản của truyện cũ (luật "thêm kho theo `bookId` ⇒ thêm vào cả hai hàm").
- **Kiểm chứng:**
  - Đọc code + 2 agent review.
  - `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 lỗi mới**.
  - Không build tại chỗ (Windows), chưa thử máy.

## [1.3.835] - 2026-11-11

### fix: chạm đúp xem ảnh truyện tranh lần đầu không còn mở rồi tự đóng

Anh Bửu: *"phần đọc commic lần đầu tap đúp xem ảnh bị lỗi mở rồi tự đóng màn xem ảnh full"*.

- **Nguyên nhân (đọc code, chưa thử máy):** trình xem phóng to mở bằng `fullScreenCover(isPresented:)` còn ảnh nằm ở `@State` riêng (`zoomImage`). Lần đầu, SwiftUI dựng nội dung cover bằng giá trị cũ của biến ảnh (vẫn `nil`, vì thân `ComicReaderView` không đọc biến đó) ⇒ rơi vào nhánh dự phòng `Color.black.onAppear { isZoomPresented = false }` ⇒ cover tự đóng. Lỗi có từ khi làm màn đọc truyện tranh, không do 1.3.833 / 1.3.834.
- **Sửa:** `ComicReaderView` trình bày bằng `fullScreenCover(item:)` với `ComicZoomViewer.Target` (ảnh + yêu cầu ảnh của trang) ⇒ cover nhận đúng ảnh ngay lần đầu; bỏ nhánh tự đóng và hai biến `zoomImage` / `zoomRequest` / `isZoomPresented`. "Đang xem phóng to thì không dọn dẹp màn đọc" (`handleDisappear`) giờ kiểm `zoomTarget != nil`.
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows), chưa thử máy. Cần thử: chạm đúp ảnh ngay sau khi mở truyện ⇒ trình xem ở lại; đóng rồi mở lại vẫn được; đang xem phóng to, màn đọc không bị ghi tiến độ / giải phóng giữa chừng.

## [1.3.834] - 2026-11-11

### feat: dịch tên truyện trên thanh trên và chữ trong trình xem phóng to của màn đọc truyện tranh

Anh Bửu hỏi màn đọc truyện tranh đã dịch hết các mục khi bật dịch chưa. Javis rà thì còn hai chỗ: tên truyện ở thanh trên hiện nguyên văn, trình xem phóng to không có lớp dịch. Anh chọn sửa cả hai.

- **Tên truyện ở thanh trên** (`ComicReaderChromeView`): dịch bằng `BookDisplayTranslation.title` theo công tắc dịch của truyện — như đầu mục lục truyện tranh và tên truyện ở header Reader.
- **Trình xem phóng to** (`ComicZoomViewer`): truyện đang bật dịch ⇒ có lớp dịch như trên trang. View được zoom đổi từ `imageView` sang `contentView` (chứa ảnh + lớp dịch, cùng khung) ⇒ khối phóng / cuộn theo ảnh. Khối lấy từ `ComicPageTextRepository` theo yêu cầu ảnh của trang vừa chạm đúp (trúng RAM, không nhận chữ lại) rồi dịch như trên trang; task huỷ khi đóng trình xem.
- `ComicZoomTranslationLayer` (mới, UIKit): khối = nền + `UILabel`, cỡ chữ đo một lần ở 1× (thu nhỏ dần tới khi vừa khung); zoom xong đặt `contentScaleFactor` của chữ theo mức zoom để vẽ lại sắc nét (trong lúc chụm hai ngón hơi mờ). Chạm khối ⇒ lộ chữ gốc (viền nét đứt màu nhấn), chạm lại ⇒ dịch; chạm khối chờ chạm đúp phóng to thất bại; vùng trống không nhận chạm.
- `ComicTranslationLayout` (mới): khung, cỡ chữ, màu của lớp dịch — một nguồn cho `ComicTranslationOverlay` (SwiftUI, trên trang) và lớp UIKit của trình xem.
- `ComicTranslationStatus` (mới): cách tính bật dịch y Chi tiết, chuyển từ `ComicReaderView` ra (file đó về 392 dòng).
- `CLAUDE.md` / `AGENTS.md`: mục dịch ảnh bỏ câu "trình xem phóng to chưa có lớp dịch".
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows), chưa thử máy. Cần thử: (1) chạm đúp một trang đã dịch ⇒ trình xem có đúng các khối, đúng chỗ; (2) phóng 2,5× / 4× chữ có sắc lại sau khi buông tay; (3) chạm khối đổi gốc ↔ dịch, chạm đúp vẫn phóng / thu; (4) tên truyện ở thanh trên đổi khi bật / tắt dịch.

## [1.3.833] - 2026-11-11

### feat: dịch ảnh truyện tranh theo công tắc dịch của truyện, thêm nút dịch, Cài đặt dịch và Từ điển truyện vào màn đọc

Anh Bửu: *"thêm màn hình dịch và từ điển riêng cho truyện giống reader, ngoài ra hãy xác định có bật dịch hay không tương tự như truyện chữ nữa cho dịch OCR"* — bật/tắt dịch ở trang Chi tiết của truyện tranh đã đúng, còn dịch ảnh (1.3.826) thì chưa.

- **Dịch ảnh theo đúng công tắc dịch của truyện:** chạy khi và chỉ khi truyện đang bật dịch — cùng `TranslationConfigStore` với trang Chi tiết và tên chương (truyện này > nguồn > nguồn tự khai tiếng Trung > toàn cục). `ComicReaderView` giờ tính y như `BookDetailView` (kèm `isChineseSourceHint` = `isChineseSource` của bản ghi tiện ích) ⇒ hai nơi luôn khớp. Bỏ `ComicImageTranslationPolicy` (công tắc theo tiện ích của 1.3.826) cùng nút "Dịch ảnh" và toast; khoá cũ `comicImageTranslate_*` không đọc nữa (không dọn). Hệ quả: nguồn tự khai tiếng Trung ⇒ mở là dịch cả ảnh; nguồn khác mặc định không; truyện tranh nhập từ file theo công tắc Mặc định toàn cục.
- **Thanh trên** (`ComicReaderChromeView`): nút dịch = nguyên `ReaderTranslationScopeMenuView` của Reader / Chi tiết (bảng "Dịch văn bản" + phạm vi + Lưu lại; icon 17, khung 36×38, không nền), rồi ☰, rồi `⋯` mới. Neo `.mediaDiscAnchor(.headerTrailing)` ở nút dịch (nút trái nhất của cụm phải).
- **Ngăn kéo `⋯`** "Tuỳ chọn truyện tranh" (`ComicTranslationToolsModifier`, file mới; giữ `ComicReaderView` dưới 400 dòng): "Cài đặt dịch" (chữ phụ Đang bật / Đang tắt) và "Từ điển truyện" (`BookDictionaryView` dạng sheet, chỉ khi truyện có `Book` — như Reader). Chỉ có mục dịch, không có gì đổi chương (ngăn kéo cũ đã bỏ ở 1.3.667).
- **Sheet "Cài đặt dịch"** (`ComicTranslationSettingsSheet`, file mới) bám mục "Dịch thuật Quick Translate" của `ReaderSettingsView`: Hiện tại; Truyện này (Theo nguồn / Bật / Tắt), Nguồn (Toàn cục / Bật / Tắt), Mặc định toàn cục; khi đang bật: văn bản trước khi dịch (Giữ nguyên / Phồn → giản, khoá theo truyện như Reader, ghi qua `setTraditionalOverride` để có thông báo), dịch đại từ / luật nhân hoá (khoá chung của app như Reader, đổi ⇒ `notifyDictionariesDidUpdate`), Thứ tự ưu tiên rule, Token rule của truyện (mở lại `ReaderBookRulePriorityView` / `ReaderBookTokenSettingsView`). Form + `.pageTitle` + nút "?", vuốt xuống để đóng. Không sửa `ReaderSettingsView` / `TranslationScopePopupView` (lặp vài picker là chủ ý).
- **Dịch lại khi đổi:** cấu hình dịch (`TranslationConfigStore.didChangeNotification` mà bật/tắt không đổi — vd phồn → giản), từ điển (`.translationDictionariesDidUpdate`, chỉ khi không ghi `bookId` hoặc đúng truyện này), rule (`.quickTranslationRulesDidUpdate`), đóng sheet Cài đặt dịch ⇒ dịch lại tên chương **và** ảnh đang hiện (`refreshTranslations`; chữ đã nhận lấy từ RAM). Trước đó tên chương chỉ dịch lại khi bật/tắt dịch.
- `CLAUDE.md` / `AGENTS.md`: mục dịch ảnh + câu "thanh trên chỉ còn ☰" của mục màn đọc comic.
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới** (`ComicReaderView.swift` 399 dòng — sát giới hạn, việc sau nên thêm vào file riêng). Không build tại chỗ (Windows), chưa thử máy. Cần thử: (1) bật/tắt ở Chi tiết, ở nút dịch thanh trên và ở Cài đặt dịch đều bật/tắt dịch ảnh + tên chương ngay; (2) nguồn manhua tự khai tiếng Trung mở là dịch ảnh; (3) thêm name ở Từ điển truyện ⇒ bong bóng đang hiện đổi theo; (4) đĩa nghe nhấn giữ đậu trái nút dịch.

## [1.3.832] - 2026-11-11

### feat: lõi dịch truyện bằng tiện ích loại translate

Anh Bửu duyệt plan "tiện ích dịch truyện" theo `extension-api.md` của Darkrai9x (loại `translate`). Đây là phần A: lõi Services, **chưa nối** vào Reader, TTS hay giao diện (phần B và C ở các commit sau), nên bản này chưa đổi gì người dùng thấy.

- `Services/Translation/Engine/` (mới):
  - `TranslationEngineSelection`: QT, hoặc một tiện ích kèm ngôn ngữ nguồn → đích.
  - `TranslationEngineStore`: 3 cấp Truyện > Nguồn > Toàn cục như `TranslationConfigStore`, độc lập với công tắc bật/tắt dịch, lưu JSON trong `UserDefaults`. Tiện ích đã gỡ ⇒ `resolve` lùi về QT. Đổi lựa chọn ⇒ `TranslateUtils.invalidateCache` + `didChangeNotification`.
  - `TranslationExtensionSettingsStore`: model / kiểu dịch theo từng tiện ích.
  - `TranslationFallbackStatus` + `TranslationFallbackStatusStore` (`@MainActor @Observable`): báo "đang dịch bằng QT thay thế" theo từng chương, cộng yêu cầu Thử lại.
- `Services/Translation/Engine/Extension/` (mới):
  - `TranslationExtensionContext`: đọc một lần mỗi lượt — config đã trộn, ba khoá thô `support_auto_detect` / `max_line` / `max_length`, model / kiểu, dấu vân tay.
  - `TranslationExtensionRunner`: một `JSExecutor` mỗi lượt; lô tuần tự nối bằng `\n`; lệch số dòng ⇒ chia đôi tới mức từng dòng; lô lỗi ⇒ dừng gọi tiếp; chỉ ném `CancellationError`.
  - `TranslationExtensionBatchPlanner`, `TranslationExtensionResultParser` (nhận chuỗi hoặc `{ text }`; `segments` chưa dùng).
  - `TranslationExtensionLineCache`: chỉ RAM; khoá gồm tiện ích + phiên bản/config + ngôn ngữ + model + kiểu + `source` + truyện + dòng; chỉ lưu bản dịch khác rỗng.
  - `TranslationExtensionCatalog` (actor): chạy `language.js` / `model.js` / `style.js`, nhớ theo dấu vân tay; mặc định Trung → Việt.
  - `TranslationExtensionChapterTranslator`: điểm vào chung của Reader và TTS. Dòng lỗi có chữ Hán ⇒ QT, không có ⇒ giữ chữ gốc. Tên chương: `title_trans` ⇒ tiện ích (`tableOfContent`) ⇒ QT. Phồn → giản áp trước khi gửi.
- Không giữ executor lâu dài (không thêm ngoại lệ cạnh `ExtTTSRuntime`). Không sửa `TranslateUtils.swift` (đang chạm baseline dòng).
- Chưa làm (đúng plan): `localBook`, các khoá `localConfig` dành riêng (`translate_model`…), `segments`, Kiểm tra tiện ích cho loại này.
- Chuyển `[1.3.802]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng:** đọc code. `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 lỗi mới** (17 file mới, lớn nhất 194 dòng, mỗi file một type chính). Không build tại chỗ (Windows), chưa thử máy.

## [1.3.831] - 2026-11-11

### feat: bật DNS mã hoá riêng từng tiện ích và nguồn Legado

Anh Bửu: *"mặc định tắt DNS, cho bật tắt DNS cho mỗi ext, thêm vào cấu hình ext"* — chốt thêm: giữ công tắc chung (mặc định tắt, 1.3.828), nguồn Legado cũng có công tắc, phạm vi = request trong script / engine của nguồn, một máy chủ chung cho mọi nguồn.

- `Extension.encryptedDNSEnabled` (tắt ghi `nil`) + `ExtensionTransactionCoordinator.setEncryptedDNSEnabled`; cập nhật tiện ích giữ cờ; backup (`BackupPayload` / Writer / Reader / Fingerprint) như `adBlockOverride`.
- Apple không có DoH theo từng `URLSession` ⇒ **proxy HTTP CONNECT nội bộ 127.0.0.1**: `EncryptedDNSRelay` (listener loopback, cổng ngẫu nhiên, khuôn `VideoOfflineHTTPServer`) + `EncryptedDNSRelayTunnel` (CONNECT và `GET http://` tuyệt đối — viết lại dòng đầu, ép `Connection: close`; ra ngoài bằng `NWConnection` với privacy context riêng bắt buộc DoH, dùng lại theo máy chủ; hạn kết nối 10 s, `.waiting` = 502/504; đứng yên 60 s; một bên đóng ⇒ đóng cả hai; log `[DNS-Relay] → host:port`, lỗi `❌`).
- `EncryptedDNSSessionRouter`: `JSExecutor` `fetch` đổi `URLSession.shared` ⇒ `session(forExtensionPath:)` (session `.default` + `proxyConfigurations`, chung cookie/cache); `LegadoHTTPClient(cancellation:proxyConfigurations:)` qua `LegadoEngineSource.packageId` (đặt ở `LegadoSourceRuntime.Target`). Không ai bật cờ / đang lùi / đang bật cho cả app / proxy chưa sẵn ⇒ đi thẳng như cũ. Bản chụp cho thread nền: `EncryptedDNSRouting`.
- `EncryptedDNSRepository`: cần DNS ⇔ công tắc chung **hoặc** có nguồn bật cờ; chỉ công tắc chung đụng context mặc định; có nguồn bật cờ ⇒ bật proxy ngay; `sourcesDidChange()` / `refreshSourceCount()`. `FreeBookApp.init` gọi `start()` **sau** khi nạp bảng tiện ích.
- Giao diện (theo mockup): công tắc "DNS mã hoá (DoH)" trong mục **Mạng** của Cấu hình tiện ích (dưới "Xử lý cookie hệ thống", chân mục theo trạng thái) và mục **Hoạt động** của Chi tiết nguồn Legado (`ExtensionEncryptedDNSToggle`); đang bật cho cả app ⇒ bật + mờ. Mạng & DNS: "Bật cho cả app", máy chủ luôn hiện, dòng "Bật riêng: N tiện ích / nguồn", trạng thái khi có ai cần.
- `CLAUDE.md` / `AGENTS.md`: viết lại mục DNS mã hoá.
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows), chưa thử máy. Cần thử: (1) bật cờ cho tiện ích có nguồn bị nhà mạng chặn ⇒ tải được **và** log có `[DNS-Relay] → <host của nguồn>` (thiếu ⇒ request vòng qua proxy, vd QUIC); tắt ⇒ lại bị chặn; tiện ích khác không đổi; (2) như trên với nguồn Legado; (3) nguồn `http://`; (4) bật chung ⇒ công tắc riêng mờ, tắt chung ⇒ cờ riêng vẫn chạy.

## [1.3.830] - 2026-11-11

### feat: dịch phụ đề cứng trong phim bằng nhận chữ trên máy, phủ bản dịch lên đúng chỗ chữ gốc

Anh Bửu duyệt plan OCR phụ đề cứng (chọn thay Whisper vì nhẹ hơn: không model, không tải lại đoạn HLS): phim Trung in sẵn phụ đề trong hình ⇒ đọc bằng Vision, dịch VietPhrase, che chữ gốc. Hai mặc định đã chốt: nhớ bật **theo tiện ích**, **chỉ hiện bản dịch** (che chữ gốc).

- Công tắc **"Dịch phụ đề cứng"** ở ngăn kéo `⋯` của trình phát (`VideoHardSubtitleDrawerRow`, ngay dưới "Dịch phụ đề" của phụ đề mềm; ẩn khi nhúng trang), nhớ theo tiện ích (`VideoHardSubtitlePreferenceStore`, khoá `videoHardSubtitleOCRByPackage`, thiếu = tắt) — không theo phim để khỏi đụng Đổi nguồn. Bật ⇒ phụ đề mềm của tiện ích nhường chỗ (`VideoPlayerStage`).
- `Services/Video/HardSubtitle/` (mới): `VideoHardSubtitleEngine` (`@MainActor @Observable`, singleton) chạy **chỉ** khi lớp phủ của màn xem to đang hiện (`screenDidAppear` / `screenDidDisappear` đếm màn), tự KVO `player.currentItem` — không sửa `VideoPlaybackSession` (`stop()` thay item bằng `nil` ⇒ tự gỡ); mỗi item một `generation` để kết quả về muộn của tập trước bị bỏ. Nhịp 0,5 s (timer ở run loop `.common`), bỏ qua khi nhúng trang / chỉ còn cửa sổ nhỏ / app ở nền / tạm dừng mà khung đã đọc. `VideoHardSubtitleFrameSampler` gắn `AVPlayerItemVideoOutput` (4:2:0 full range; chạy cả HLS).
- Một lượt (`VideoHardSubtitleFrameJob`, hàng đợi nền tuần tự, lượt trước chưa xong thì bỏ nhịp): `VideoHardSubtitleBrightMask` (lưới 128×32 điểm trên mặt phẳng độ sáng của dải dưới 30%, ngưỡng theo full / video range) giống lần Vision trước (Jaccard ≥ 0,9) ⇒ giữ nguyên, quá 4 s vẫn đọc lại; rỗng ⇒ coi như không có chữ, trừ khi quá 3 s (dò thưa) hoặc item này từng có chữ mà mặt nạ không thấy (chữ màu nhạt ⇒ Vision mỗi nhịp); còn lại ⇒ `VideoHardSubtitleRecognizer`: cắt dải dưới **trước** rồi đưa vào `VNRecognizeTextRequest` (`.accurate`, `zh-Hans` + `zh-Hant`, chữ cao ≥ 8% dải), giữ dòng ≥ 2 chữ Hán có tâm ngang trong 15–85% (bỏ logo góc), khối = dòng thấp nhất + tối đa một dòng ngay trên.
- `VideoHardSubtitleCueTracker`: giống ≥ 75% (Levenshtein, bỏ dấu câu) = cùng câu, giữ câu cũ (bản mới nhiều chữ Hán hơn thì thay); trống 2 lượt liên tiếp mới xoá. Dịch `TranslateUtils.translateContent` **từng dòng** ngoài main, Name/VP riêng của phim (`bookId`), **luôn** phồn→giản, không theo cổng dịch của phim; đệm 200 câu, đổi phim thì xoá đệm.
- `VideoHardSubtitleOverlay` (mới): cùng `ignoresSafeArea` với `VideoPlayerSurfaceView`; vùng hình tự tính theo Vừa / Lấp đầy / Phóng từ cỡ khung (không đọc `AVPlayerLayer.videoRect`); dải che + nền chữ dịch vẽ chung một lớp (`compositingGroup`, mờ 0,86) nên chỗ chồng không đậm hơn; chữ 13–22 pt theo chiều cao dòng gốc, ép vào vùng nhìn thấy. Dòng báo "Không đọc được hình của nguồn này" (đang phát mà 5 s không có khung — nguồn DRM) / "Máy chưa hỗ trợ nhận chữ Trung", tự ẩn sau 4 s.
- Log `🔤 [VideoOCR]`: bật / tắt, bắt đầu, tóm tắt mỗi 30 s (số lượt, số lần Vision + ms trung bình, bỏ qua giống / rỗng / đang bận, số câu); lỗi có `❌`. Không tự giảm nhịp theo nhiệt — đo trên máy rồi quyết.
- Chưa làm: lưu câu xuống đĩa (xem lại phải đọc lại), hiện hai dòng gốc / dịch, quét trước tập đã tải, Whisper. Rủi ro đã biết: biển hiệu / thẻ tên ở dải dưới bị dịch nhầm thành phụ đề; HLS tự hạ 360p đọc kém; video có thông tin xoay (quay dọc bằng điện thoại) buffer chưa xoay.
- `CLAUDE.md` / `AGENTS.md`: thêm gạch đầu dòng ở mục Comic & Video. Chuyển `[1.3.800]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới** (9 file mới, lớn nhất 364 dòng, mỗi file một type chính; `VideoPlayerTopBar.swift` 352 dòng). Không build tại chỗ (Windows), chưa thử máy. Cần thử: (1) phim Trung có phụ đề trắng in sẵn — bản dịch che đúng chỗ ở màn dọc và toàn màn, đổi Vừa / Phóng; (2) bật log, xem dòng `🔤 [VideoOCR]` (ms Vision, tỉ lệ bỏ qua) và máy có nóng không; (3) phụ đề vàng / màu nhạt; (4) tạm dừng, tua, đổi tập, thu cửa sổ nhỏ rồi mở lại.

## [1.3.829] - 2026-11-11

### feat: gợi ý chữ Hán khi tìm truyện bằng tiếng Việt

Anh Bửu duyệt ý 7 của plan `Docs/Plans/2026-11-11-dich-phu-de-loi-va-tim-ca-truyen.md`: gõ tên truyện bằng âm Hán Việt ở màn Tìm, app gợi ý dạng chữ Hán để chọn khi nguồn Trung chỉ tìm được bằng chữ Hán; chip **tự hiện khi gõ**.

- `SearchChineseSuggestionBar` (mới) ngay dưới ô tìm của `SearchView` (tìm một nguồn và mọi nguồn; `SearchView` chỉ chèn một dòng): hàng **"Chữ Hán:"** tối đa 6 chip cuộn ngang, kiểu chip nhấn như `ExtensionKindFilterBar` (chữ màu nhấn, nền nhấn 18%, viền 60%). Bấm Tìm vẫn tìm đúng chữ đã gõ; chạm chip ⇒ tắt bàn phím, ô tìm thành chữ Hán đó và tìm ngay (lịch sử lưu chữ Hán). Tính sau khi ngừng gõ 300 ms, ngoài main (`Task.detached`), gõ tiếp ⇒ `.task(id:)` huỷ lượt cũ, kết quả muộn bị bỏ; truy vấn chắc chắn không gợi ý được (rỗng, có chữ Hán, 1 hoặc hơn 8 âm tiết, có số…) ⇒ ẩn ngay, không chờ.
- `Services/Translation/Reverse/` (mới): `HanVietReverseIndex` = bảng `phienAm` đảo ngược (âm ⇒ chữ; chỉ khoá đúng một chữ Hán BMP; một chữ nhiều âm ngăn `/` `,` `;` `|`), hai bảng có dấu / bỏ dấu, nhớ theo `TranslationDictionaryState.revision()`. Chuẩn hoá âm: không tính vị trí dấu thanh (`hoà` = `hòa`), `đ` bỏ dấu là `d`, `y` đứng một mình sau phụ âm = `i` (`lý` = `lí`, `quý` = `quí`). Xét từng âm tiết: âm có dấu ⇒ khớp đúng dấu (không ra chữ thì lùi về bỏ dấu), âm không dấu ⇒ khớp bỏ dấu — gõ dấu một phần vẫn ra.
- `ChineseQuerySuggester` (mới): mỗi vị trí bắt đầu hỏi Name (tuỳ chỉnh, chung) + VietPhrase (tuỳ chỉnh, chung) các khoá có thật dài tới 6 chữ; bỏ khoá đã xoá của từ điển chung như `VietPhraseTokenizer`; không dùng từ điển riêng truyện. Quy hoạch động giữ 16 đường mỗi vị trí, xếp: ít đoạn ⇒ ít đoạn một chữ ⇒ Name trước VietPhrase ⇒ giản thể trước phồn thể (ICU `Traditional-Simplified`) ⇒ thứ tự mã. Bỏ đường trộn giản + phồn, đường có quá nửa số âm tiết là đoạn một chữ (chỉ là đoán chữ đồng âm), đường nhiều hơn đường tốt nhất quá một đoạn. Log `🔎 [HanSuggest]` (số âm tiết / cạnh / kết quả / ms; không log từ khoá).
- `FrozenTrieDictionary.keys(matchingCharacterSets:limit:)` (mới): đi cây đôi theo đúng phép tính của `trieTerminals`, mỗi độ sâu thử mọi chữ của tập, nhánh không có con thì dừng ⇒ chỉ đi qua tiền tố có thật, không gọi `allEntries()`; trần 200 000 cạnh thử; kho `entries` (từ điển tuỳ chỉnh) lọc khoá đúng độ dài.
- Giới hạn: chỉ màn Tìm Kiếm (ô tìm nhanh của Khám phá chưa có); chữ Việt thuần không phải âm Hán Việt không ra gợi ý; thứ tự là đoán theo từ điển (không có tần suất); chạm một chip xong ô tìm là chữ Hán ⇒ hàng chip ẩn, muốn thử cách viết khác phải gõ lại âm Việt.
- Chuyển `[1.3.799]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng:** đọc code + review phản biện bằng agent; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới** (file mới ≤ 400 dòng, một type chính; `SearchView.swift` 701 dòng ≤ baseline 872). Không build tại chỗ (Windows), chưa thử máy. Cần thử: (1) `đấu phá thương khung` và `dau pha thuong khung` ra chip hợp lý; (2) log `🔎 [HanSuggest]` (bật log) xem ms — lần đầu sau khi từ điển đổi có thêm bước dựng bảng đảo; (3) gõ nhanh không giật, không bấm nhầm chip cũ.

## [1.3.828] - 2026-11-11

### fix: DNS mã hoá cho cả app mặc định tắt

Anh Bửu (sau 1.3.825): *"sai ý tôi rồi, mặc định tắt DNS, cho bật tắt DNS cho mỗi ext, thêm vào cấu hình ext"*. Bước 0 của plan: tắt ngay mặc định đang bật sẵn cho mọi người dùng nguồn LiveContainer; công tắc riêng từng tiện ích / nguồn Legado làm ở bản kế.

- `EncryptedDNSPolicy.defaultEnabled = false`. Máy chưa từng bật tay ⇒ tắt (khoá chưa ghi); ai đã bật tay ở Mạng & DNS thì giữ.
- `CLAUDE.md` / `AGENTS.md`: mục DNS mã hoá ghi mặc định tắt.
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows), chưa thử máy.
