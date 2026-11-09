# CHANGELOG - Nhật ký Thay đổi CodeGraph Tàng Công Các

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **Tàng Công Các**.

## [1.3.813] - 2026-11-09

### fix: đĩa nghe góc dưới giống nút nổi khác, vòng kính theo độ trong suốt và độ đục, bìa luôn rõ

Anh Bửu: *"áp dụng theo cài độ trong suốt, độ đục như nút khác"*. Bản 1.3.812 cho cả **bìa** mờ theo "Độ trong suốt" (bìa hiện `1 − độ trong suốt`) ⇒ ở mức mặc định 90% bìa chỉ còn thấy ~10%, gần như tàng hình.

- `MediaDiscFaceButton(.corner)`: bỏ lớp mờ của bìa. Vòng kính `FloatingGlassBackground` vẫn theo "Độ trong suốt" + "Độ đục" của nút nổi (Cài đặt › Chung › Giao diện); bìa luôn rõ như icon của nút "+" / Home.
- `CLAUDE.md` / `AGENTS.md`: sửa câu mô tả độ trong suốt của đĩa góc.
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows), chưa thử máy.

## [1.3.812] - 2026-11-09

### feat: đĩa nghe ở ô giữa thanh tab, đĩa góc chỉ hiện ở màn không có thanh tab, nhấn giữ đĩa góc tạm lên header 5 giây

Plan anh Bửu đã duyệt (thay bản "đĩa trên header" đã bỏ): đĩa nghe nằm ở ô giữa thanh tab ở trang gốc các tab; mọi màn khác giữ đĩa góc dưới phải; nhấn giữ đĩa góc để tạm đưa nó lên header 5 giây.

- **Thanh tab luôn 5 ô** (`MainTabBar`): Kệ Sách · Khám Phá · [giữa] · Tiện Ích · Cài Đặt. Ô giữa (`MediaDiscTabBarSlot`, mới) = đĩa 32 pt gọn trong chiều cao thanh khi có nhạc / TTS kiểu "Đĩa góc dưới", trống và không bấm được khi không nghe — icon tab không đổi chỗ. Có đĩa hay không đọc `MediaDiscWindowManager.kind` ⇒ đúng ngay từ khung đầu.
- **Đĩa góc chỉ ở màn không có thanh tab**: thanh tab là neo `.hostsDisc` (vai mới của `MediaDiscAnchorRegistry`) ⇒ màn trên cùng có thanh tab thì đĩa góc ẩn **ngay**; đĩa đang ẩn chỉ hiện lại khi điều kiện đã giữ đủ 0,3 s (đẩy trang không làm đĩa lóe). Bàn phím, màn nghe, phim, hộp thoại vẫn ẩn như 1.3.808.
- **Nút đĩa dùng chung** `MediaDiscFaceButton` (`.corner` / `.tabBar`, mới) cho cả hai chỗ; chạm ⇒ `MediaDiscWindowManager.presentQuickControls()` ⇒ sheet điều khiển nhanh luôn trình bày từ cửa sổ của đĩa qua `MediaDiscSheetHost` (mới, tách từ `MediaDiscContentView` — đã xoá). Chạm đầu sheet giữ như cũ (nhạc ⇒ màn nghe; TTS ⇒ Reader đúng chương, Reader của truyện đang mở thì `navigateReaderToPlayingChapter`).
- **Bìa đĩa góc mờ theo "Độ trong suốt" của nút nổi**: bìa hiện `1 − độ trong suốt`, đúng như lớp màu của vòng kính; "Độ đục" vẫn là nhoè của vòng kính. Mờ gắn lên lớp bìa, không lên lớp cha của kính.
- **Nhấn giữ đĩa góc 0,4 s** ⇒ rung nhẹ, trượt lò xo mềm lên góc phải vùng header (mép trên ngay dưới thanh trạng thái, lề phải 16 pt — `MediaDiscPlacement.elevatedFrame`) 5 giây rồi về chỗ; trong lúc đó chạm vẫn mở sheet, đóng sheet ⇒ về ngay, đổi màn ⇒ giữ đủ 5 giây. Chỉ dời khung trong cửa sổ đĩa, không đụng layout app. Thanh tab không có cử chỉ này.
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows), chưa thử máy.

## [1.3.811] - 2026-11-09

### fix: nút ⋮ thêm playlist trong hàng danh sách không nhận chạm của cả hàng

Rà commit 1.3.810 trước khi push:

- `PlaylistListItemMenu` gắn `.menuStyle(.borderlessButton)` như menu chuyển từ của `DictionaryEntryRow` / `QuickTranslationRuleEntryRow`: ở kiểu Danh sách của Khám phá / Thể loại và Tìm một nguồn, ⋮ đè lên nút mở item **trong hàng `List`** — Menu kiểu mặc định có thể nhận chạm của cả hàng (chạm item lại mở ⋮). Lưới, Trang chủ Khám phá, Tìm nhiều nguồn không nằm trong `List`, không đổi gì.
- Comment của `PlaylistAddRequest` / `PlaylistAddSheet` hết ghi "ba lối" — liệt kê thêm icon cuối hàng và ⋮ / icon của item danh sách chưa mở.
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows), chưa thử máy.

## [1.3.810] - 2026-11-09

### feat: thêm vào playlist ngay trên danh sách nhạc và phim, nút ? xem thay đổi của bản đang dùng, chip Tất cả ở tab Playlist

Plan + mockup anh Bửu đã duyệt (chỉ thêm, không đổi bố cục cũ). Truyện chữ / truyện tranh không có gì mới.

- **Icon "Thêm vào playlist" trực tiếp** (`text.badge.plus`, 17 nửa đậm, vùng chạm 32 × 36, nút **anh em** với nút mở — không nằm trong `label`): cuối mỗi bài ở trang Danh sách màn nghe (`AudioPlaylistRow`, giữ nhấn giữ; chế độ playlist không có); cuối mỗi dòng gợi ý nhạc, sau nhãn "Tiếp theo" (`AudioSuggestionRow` → `PlaylistAlbumAddButton`, thêm **mọi bài** của album gợi ý); cuối mỗi hàng tập kiểu Danh sách của sheet "Tất cả tập", sau ô ⬇ (`VideoEpisodeListView`, chỉ khi có `onAddToPlaylist`; Lưới và dải tập giữ nhấn giữ). Nền bài / tập đang phát và vạch ngăn dời ra hàng ngoài để phủ cả icon.
- **Nút ⋮ hai mục** "Thêm vào playlist" + "Thêm vào kệ" (`PlaylistListItemMenu`, mới): Khám phá › Trang chủ (`ExploreItemCard` tách thành nút bìa + hàng [nút chữ | ⋮ nhỏ]; `ExploreListRow` ⋮ cuối dòng; thẻ tròn và item action `list` không có), tab danh mục + Thể loại / Xem thêm (`DiscoveryNovelsLayoutView`: hàng ⋮ giữa mép phải, thẻ lưới ⋮ góc dưới phải cạnh tên — `DiscoveryNovelGridCardView.reservesMenuSpace`, lưới chỉ bìa ⋮ tròn nền tối góc trên phải bìa), Tìm một nguồn (`SearchSingleSourceResultsView`) và nhiều nguồn (`SearchView`, thẻ ngang). Gắn bằng `.playlistListItemMenuOverlay(item:context:style:)` đè lên nút / link mở item. Chỉ nguồn `.audio` / `.video` (`PlaylistListAddContext.make` — dựng một lần mỗi danh sách, Tìm nhiều nguồn mỗi nguồn một lần; đang đổi nguồn ⇒ không có). ⋮ của thẻ phim đề xuất ở màn xem thêm "Thêm vào playlist" **đứng trên** "Thêm vào kệ".
- **Một đường dựng mục cho mọi lối** (gợi ý nhạc, đề xuất phim, Khám phá, Tìm, sheet nhấn giữ trên Kệ): `PlaylistItemMapper.album(of: ExtensionItemResult, …)` lấy id album = id trình nghe / màn xem sẽ dùng (`VideoWatchRequest.resolveBookId`) ⇒ album đã có trên máy đọc đúng mục lục đã lưu; `PlaylistAlbumItemsLoader.addRequest` trả `PlaylistAddRequest` (mục lục trên máy → tải `fetchFullTOC`, bỏ `section`; bài lẻ = mục lục một bài ⇒ một mục, tên rỗng lấy tên item). Vòng xoay thay ⋮ / icon khi tải, lỗi ⇒ toast (`PlaylistAddFeedback`). "Thêm vào kệ" dùng `VideoWatchShelfAdder` cho cả album âm thanh. `PlaylistAddBookActionRow` chuyển sang cùng đường.
- **Nút "?" cạnh "Phiên bản ứng dụng"** (Cài đặt › Thông Tin, kiểu glyph / vùng chạm của `SectionHelpButton`, nút anh em đặt chồng — chạm phần còn lại của hàng vẫn kiểm tra bản mới) ⇒ sheet **"Có gì mới ở bản này"** (`AppReleaseNotesSheet`, khuôn `AppUpdateSheet`: `sparkles` màu nhấn, "<version> (<build>) · bản đang dùng", panel "• <subject>"). Nguồn (`AppReleaseNotesLoader`, Services): `ReleaseNotes.txt` trong bundle → bản cùng `buildVersion` trong `apps.json` (`AppUpdateSourceClient.fetchVersion`, API GitHub rồi link raw) → "Không còn ghi chú cho bản này".
- **CI** (`build-ipa.yml`, bước Package IPA): `telegram_commit_summary.py --format notes` (bỏ dòng trùng, `- <subject>`) ghi `build/commit_subjects.txt` thành `Payload/FreeBook.app/ReleaseNotes.txt` trước khi nén; thiếu danh sách / lỗi ⇒ bỏ qua, không làm đỏ build.
- **Chip "Tất cả" ở tab Playlist**: thứ tự Tất cả · N / Nhạc · N / Video · N, "Tất cả" mặc định (`PlaylistKindFilter`, kiểu riêng của View — **không** thêm case vào `PlaylistKind`; khoá `shelfPlaylistKind` giữ, giá trị cũ `audio` / `video` vẫn đọc được, mới thêm `all`). Ở "Tất cả": thẻ thêm icon loại trước số mục, "+" mở sheet tạo chọn sẵn Nhạc (tạo xong giữ chip), màn trống "Chưa có playlist nào".
- **Kiểm chứng:** đọc code + grep chéo mọi chỗ gọi type đổi chữ ký (`AudioPlaylistRow`, `AudioSuggestionRow`, `DiscoveryNovelsLayoutView`, `SearchSingleSourceResultsView`, `ExploreRenderContext`, `PlaylistKindChipBar`, `PlaylistGridCardView`); `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows), chưa thử máy: Menu đè lên nút trong hàng `List`, sheet gắn trên ô lưới lười, nút "?" chồng trong hàng `Form`.

## [1.3.809] - 2026-11-09

### fix: sheet của đĩa nghe không kẹt khi mở Reader từ sheet Hẹn giờ, bìa trong sheet xoay theo trạng thái app

Rà commit 1.3.808 (đĩa nghe góc dưới phải), sửa hai chỗ session làm đĩa đã nêu là chưa chắc:

- `MediaDiscWindowManager.openCurrentlyPlayingReader`: chờ 0,45 s rồi mới xin đóng sheet của đĩa. Chọn chương ở sheet Hẹn giờ TTS (sheet lớp hai đè lên sheet điều khiển nhanh) gửi `openCurrentlyPlayingReader` lúc sheet con còn đang trượt xuống; đóng sheet cha ngay khi đó UIKit có thể bỏ qua ⇒ sheet nhanh kẹt lại che Reader.
- `AudioQuickControlSheet` / `TTSQuickControlSheet`: đĩa đầu sheet xoay theo `isAppActive` (thông báo `didBecomeActive` / `willResignActive`) thay cho `scenePhase` — sheet giờ trình bày từ cửa sổ riêng của đĩa, `scenePhase` không chắc lan tới (cùng lỗi màn nghe đứng đĩa đã sửa ở 1.3.797).
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows), chưa thử máy.

## [1.3.808] - 2026-11-09

### feat: đĩa xoay góc dưới phải cho nhạc và TTS trên mọi màn, bỏ thanh nghe nhạc mini và kiểu thanh của widget TTS

Plan anh Bửu đã duyệt (mockup 2026-11-09): thay thanh nghe nhạc mini và kiểu "Thanh nghe nhạc" của widget TTS bằng **một đĩa xoay tròn ở góc dưới phải trên mọi màn**, dùng chung cho nhạc và TTS; giữ kiểu "Đĩa nổi" của TTS; đĩa hiện ở trang gốc tab, trang đẩy vào, sheet, trình duyệt, Reader.

- **Đĩa chung** (`Views/MediaDisc/`, mới): `MediaDiscWindowManager` dựng cửa sổ lớp phủ `MediaDiscWindow` (level `alert − 1.75`, chỉ khung đĩa nhận chạm) khi trình nghe có album hoặc TTS có phiên + kiểu "Đĩa góc dưới"; nút 52 pt nền kính `FloatingGlassBackground`, bìa tròn 44 pt xoay khi đang phát (`MediaDiscMusicFace` — `AudioRotatingCover`, album 18+ lúc NSFW tắt không bìa; `MediaDiscTTSFace` — `TTSCoverView` + `TTSWidgetCoverRotation`). Chờ cổng từ điển như các cửa sổ nổi khác; hết nguồn ⇒ đóng sheet, thu đĩa rồi ẩn cửa sổ.
- **Vị trí** (`MediaDiscPlacement`): đĩa đứng ngay trên **neo cao nhất** của tầng trình bày trên cùng của cửa sổ chính (khe 12 pt), không neo ⇒ góc dưới phải trên vùng an toàn 12 pt, lề phải 16 pt. Neo = `.mediaDiscAnchor(_:)` (`MediaDiscAnchorProbe` + `MediaDiscAnchorRegistry`): `FloatingRoundButton` (mọi nút "+", Home, menu xổ, FAB Chi tiết), cụm pill đang xổ của `FloatingActionMenu` (đĩa lên trên, không che "Về trang gốc"), nút tai nghe Reader (mép phải trùng nút), `MainTabBar`, `BrowserBottomBar`, thanh dưới truyện tranh. Neo trong sheet thắng neo trang dưới; trang con ngoài màn của `TabView` dạng trang không tính. Cửa sổ phim nhỏ đè chỗ ⇒ đĩa lên trên nó (`VideoMiniPlayerWindowManager.visiblePlayerFrame`).
- **Ẩn** khi bàn phím hiện, màn nghe hiện, phim toàn màn (`FloatingWidgetSuppression`), màn xem phim ở trên cùng (neo `.blocker` ở `VideoPlayerScreen`), hộp thoại / bảng chọn (`UIAlertController`) hay bảng chia sẻ ở trên cùng.
- **Tính lại** khi neo vào / rời cửa sổ / đổi cỡ, bàn phím, xoay màn, đổi trạng thái, cộng lượt hỏi 0,4 s (chế độ `.common`) chỉ khi cửa sổ hiện và app không ở nền. Giữ chỗ mép phải ở `FloatingWidgetLayoutCoordinator` (`.mediaDisc`, mới) để nút hub vừa thả / vừa hiện né đĩa.
- **Chạm đĩa** ⇒ sheet điều khiển nhanh từ cửa sổ của đĩa (`.appAccentTint()` + `.modelContainer` ở gốc): `AudioQuickControlSheet` — chạm khối bìa + tên ⇒ đóng sheet rồi mở màn nghe trang Đĩa (`AudioPlayerPresenter.reopen(at: .disc)` trong `onDismiss`), **bỏ nút ⤢**; `TTSQuickControlSheet` (thêm `onOpenReader`) — chạm khối bìa + tên ⇒ đóng sheet rồi Reader của truyện đó đang mở thì `navigateReaderToPlayingChapter` (không đổi tab), chưa mở thì `openCurrentlyPlayingReader`. Sheet Hẹn giờ TTS mở Reader ⇒ đóng mọi sheet của đĩa.
- **Bỏ**: `AudioMiniPlayerBar`, `AudioMiniPlayerTimerBadge` (khỏi `MainTabBarModifier` và `BypassWebView`), `MiniPlayerBarChrome` / `MiniPlayerControlButton` / `MiniPlayerProgressLine`, toàn bộ kiểu thanh TTS (`TTSWidgetBarContainerViewController`, `TTSWidgetBarContentView`, `TTSWidgetBarView`, `TTSWidgetBarPillView`, `TTSWidgetBarViewModel`, `TTSWidgetBarProgressLine`, `TTSWidgetBarPresence`), `ReaderAudioDiscButton`, `ReaderTTSDiscButton`, `ReaderTTSBarBottomSpacer` (đáy Reader về `Spacer().frame(height: 52)`), `ReaderPresenceTracker` (chỉ thanh TTS dùng). Giữ `TTSWidgetBarInfoReader` (sheet TTS dùng).
- **Dòng báo trình nghe** (`AudioPlaybackNotice`: "Tự sang: <tên>", "Bỏ qua …") trước nổi trên thanh mini ⇒ nay là **toast** (`recordsInInbox: false`) khi màn nghe không hiện; màn nghe vẫn có dải báo.
- **Cài đặt › Đọc & Nghe › Widget TTS**: **Đĩa nổi** (giữ nguyên) / **Đĩa góc dưới** (`TTSWidgetStyle.cornerDisc`, raw value `"bar"` cũ ⇒ ai đang chọn "Thanh nghe nhạc" tự sang); bỏ hai công tắc "Thu gọn khi mở Reader" / "Tự thu gọn sau 5 giây" và khoá của chúng ở `TTSWidgetPreferences`. Kiểu Đĩa góc dưới ⇒ `TTSFloatingWidgetWindowManager` không dựng cửa sổ.
- **Kiểm chứng:** đọc code + grep chéo mọi type / khoá bị xoá; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows), chưa thử máy.

## [1.3.807] - 2026-11-09

### feat: thanh nghe nhạc mini có nút hẹn giờ và hiện trên trình duyệt

Anh Bửu: *"thêm nút hẹn giờ vào thanh nghe nhạc mini của nghe nhạc"* và *"chỉ cần cao hơn browser được rồi"* (không làm cửa sổ nổi toàn app).

- `AudioMiniPlayerBar`: thêm ⏱ giữa ⏭ và ✕ (4 nút rộng 36 pt như thanh widget TTS), chạm mở `MediaSleepTimerSheet` của trình nghe; đang hẹn ⇒ viên "⏱ m:ss" cạnh tên ca sĩ (`AudioMiniPlayerTimerBadge`, view riêng đọc `MediaSleepTimer` ⇒ thân thanh không vẽ lại mỗi giây).
- Trình duyệt người dùng (`BypassWebView.browserArea`): đang có album ⇒ thanh nhạc mini nằm ngay trên thanh dưới, trang co lại chừa chỗ (không che); ẩn lúc gõ địa chỉ. Trang đẩy vào / sheet giữ như cũ.
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows), chưa thử máy.

## [1.3.806] - 2026-11-09

### feat: nút đĩa TTS trong Reader cho kiểu Thanh nghe nhạc, chạm mở sheet điều khiển nhanh, thanh bung nằm sát đáy không che chữ

Anh Bửu: *"kiểu widget tts thanh nghe nhạc bạn làm thiếu đĩa xoay tròn ở reader"*, chọn "nút đĩa như nhạc", rồi *"để cho thanh nghe nhạc thấp hơn nút nghe truyện. Đừng che nội dung truyện"* và *"bấm vào đĩa ở reader thì hiển thị sheet"* (mockup duyệt 2026-11-09).

- **Cầu nối** `TTSWidgetBarPresence` (`Views/TTSWidget/`): gộp trạng thái thu gọn của thanh (`TTSWidgetBarViewModel` ghi qua `didSet`), cửa sổ widget đang hiện và kiểu widget thành hai cờ cho Reader: `showsReaderDisc` (thanh thu gọn) và `readerBottomInset` (thanh bung). Reader không đọc thẳng view model của container hay `TTSManager`.
- **Trong Reader, thanh thu gọn ⇒ không còn viên nép mép**: `TTSWidgetBarContainerViewController` để viên alpha 0 (cửa sổ chạm xuyên) và không giữ chỗ ở `FloatingWidgetLayoutCoordinator`; thay bằng `ReaderTTSDiscButton` ngay trên nút tai nghe, cùng chỗ / dáng nút đĩa nhạc (52 pt, kính `FloatingGlassBackground`, bìa truyện xoay theo góc chung `TTSWidgetCoverRotation`).
- **Chạm đĩa ⇒ `TTSQuickControlSheet`** (khuôn sheet nhạc, nền kính ngăn kéo): đĩa bìa · tên truyện + tên chương · ⏱ (đang hẹn ⇒ giờ còn lại màu nhấn, mở `TTSQuickTimerSheet`); câu đang đọc + vạch "Đoạn N / M đoạn" (`TTSQuickControlNowReading`, chỉ khối này vẽ lại theo đoạn); ⏮ đoạn trước · ⏯ · ⏭ đoạn kế; Mục lục (`TTSQuickTimerSheet(initialTab: 1)`) · Giọng đọc (Cài đặt TTS, state riêng — không qua `showingSettingsSheet` để không tranh host với sheet Hẹn giờ) · Tắt đọc. Không bung thanh.
- **Bấm tai nghe bắt đầu đọc trong Reader giữ thu gọn** khi bật "Thu gọn khi mở Reader" (`TTSWidgetBarViewModel.revealRequested`; trước đây `reveal` bung thanh đè lên chữ).
- **Thanh bung trong Reader** (tắt "Thu gọn khi mở Reader"): nằm sát đáy (khe 6 pt, `readerBarBottomGap`), thấp hơn nút tai nghe; `ReaderTTSBarBottomSpacer` thay khoảng đáy 52 pt của `ReaderView` bằng chiều cao thanh + khe ⇒ chữ dừng ngay trên thanh, nút tai nghe đẩy lên trên thanh. Ra khỏi Reader như cũ (thanh trên thanh tab, viên nép mép).
- Nền kính của sheet nhạc tách ra `DrawerGlassSheetBackground` (`Views/Common/GlassChrome/`), sheet nhạc và sheet TTS dùng chung.
- **Kiểm chứng:** đọc code + grep chéo chữ ký (`TTSQuickTimerSheet()` vẫn gọi được nhờ tham số mặc định, `registerSlot` chỉ một chỗ gọi); `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows), chưa thử máy.

## [1.3.805] - 2026-11-09

### feat: phát playlist nhạc và video, hết bài hoặc tập sang mục kế, lặp và xáo cả playlist, bỏ qua mục hỏng

Phần 2 của plan "Playlist nhạc và video (tạo, sửa, xoá, phát)" anh Bửu đã duyệt (phần 1 = 1.3.802): **phát playlist** bằng trình nghe / màn xem sẵn có, đúng bài / tập đã lưu.

- **`PlaylistPlaybackCoordinator`** (mới, `Services/Playlists/`, `@MainActor @Observable`, + `+Audio` / `+Video`): chủ duy nhất của chế độ phát playlist — một hàng đợi nhạc, một hàng đợi phim (`PlaylistPlaybackQueue`, mới: mục còn hiện đã lọc NSFW theo thứ tự người dùng xếp + thứ tự phát của vòng hiện tại; xáo = hoán vị bắt đầu bằng mục đang phát; tra lại playlist **theo id** mỗi lần chuyển mục — mục bị xoá giữa chừng thì mục kế là mục đứng ở chỗ đó, playlist bị xoá ⇒ phát nốt mục hiện tại rồi dừng). Chỉ ở RAM. Hai phiên phát chỉ **hỏi** coordinator ở các chỗ chuyển bài / tập nên nút trên màn, thanh mini, màn khoá, tai nghe đều đi theo playlist.
- **Trang chi tiết playlist**: hàng **Phát tất cả** (`.appFilled`) / **Phát ngẫu nhiên** (`PlaylistPlayButtonsRow`) ngay dưới đầu trang; chạm một mục ⇒ phát playlist từ mục đó (tra theo id; không chạy khi đang "Sắp xếp lại"); mục đang phát tô màu nhấn + icon loa. Lối vào duy nhất từ View: `PlaylistPlaybackLauncher` (nhạc ⇒ màn nghe trang Đĩa qua `AudioPlayerPresenter.reopen`; phim ⇒ `VideoWatchPresenter.present(playlistStart:)`).
- **Nhạc**: mục cùng album đang mở ⇒ chuyển bài trong phiên (`AudioPlaybackSession+Playlist.playPlaylistTrack`, nạp sẵn được bài kế cùng album); khác album ⇒ `stopSession(keepsPlaybackSession: true)` + giữ hẹn giờ mốc phút + `open(fromPlaylist: true)` như `AudioAutoNextCoordinator` (giữ `AVAudioSession` + màn khoá, cả khi ở nền — lượt chuyển trong background task tới khi mục mới phát). `AudioListenRequest.playlistTrackUrl` (mới): bài phải đúng mục — link bài trước, chỉ số sau, không còn ⇒ lỗi chứ không phát bài khác; luôn từ giây 0. Lặp **Tắt / Playlist / Một bài** (`album` của phiên đọc là "Lặp playlist" — `AudioRepeatMode.title(inPlaylist:)`, `repeatModeTitle`), xáo áp cho cả playlist; ngoài playlist giữ Tắt / Album / Một bài. Hết bài ⇒ mục kế, **không** sang bài kế của album, **không** tự phát gợi ý (`AudioAutoNextCoordinator` đứng ngoài ở `trackLoadDidBegin` / `albumDidEnd` / `upNextLink`). Trang **Danh sách** của màn nghe ⇒ `AudioPlaylistQueueList` (mới): "Phát từ playlist <tên>", các mục theo thứ tự playlist, mục đang phát theo id, chạm ⇒ nhảy tới mục; không có phần gợi ý.
- **Phim**: mục cùng phim đang mở ⇒ chuyển tập trong phiên (`VideoPlaybackSession+Playlist.playPlaylistEpisode`, không thoát chế độ như `selectEpisode`); phim khác ⇒ màn xem đang hiện mục của playlist đổi tại chỗ (`VideoWatchModel.replace(playlistStart:)`), không màn ⇒ `VideoWatchModel` không màn (khuôn `VideoAutoNextCoordinator`; lấy màn đang hiện qua `visibleScreenModel`). `VideoWatchModel.PlaylistStart` (mới): phát luôn dù tắt tự phát, đúng tập (link trước, chỉ số sau — `VideoWatchModel+Playlist`), giây 0, giữ tiếng + hẹn giờ của phim vừa xem; `token` mỗi lượt — coordinator đã sang mục khác ⇒ model cũ không mở phiên. Hết tập ⇒ mục kế (không lặp, không sang tập kế, không tự sang phim đề xuất — nhánh "hết tập" dời sang `+Playlist.advanceAfterEpisodeEnded` cho `+Playback` dưới 400 dòng). Màn xem có dải **"Playlist <tên> · 3/12"** + nút mục kế ngay dưới khối tên (`VideoWatchPlaylistBar`); ⏭ của thanh dưới và màn khoá cũng sang mục kế (`canPlayNext`). Phim chưa mở phiên sau 90 giây mà không còn màn xem đang hiện ⇒ thôi chế độ playlist.
- **Mục hỏng** (tiện ích gỡ, link / nạp lỗi, không còn bài / tập): chờ 0,7 s, vẫn lỗi (người dùng chưa "Thử lại") ⇒ "Bỏ qua <tên>: <lý do>" (nhạc: `AudioPlaybackNotice`; phim: `playbackNotice`, phim mới hiện khi bắt đầu phát) rồi mục kế; hỏng liên tiếp đủ số mục ⇒ "Không phát được mục nào trong playlist <tên>", thôi chế độ playlist — không lặp vô hạn kể cả khi lặp playlist. Phim đang giữ âm thanh (nhạc) / TTS đang đọc (phim) ⇒ không tự mở mục kế (mở là bắt bên kia nhường): để mục lỗi, hết bài thì dừng ở cuối. Hẹn giờ "Hết bài" / "Hết tập" vẫn dừng ở cuối, không sang mục kế.
- **Thoát chế độ playlist**: mở album / phim bình thường (`open` không cờ playlist — Kệ, Khám phá, Tìm, gợi ý, đề xuất), chọn bài của album / chọn tập khác, đóng hẳn trình nghe / trình phát, TTS giành trình nghe.
- `CLAUDE.md` / `AGENTS.md`: gạch "Phát playlist" ở mục Âm thanh + một gạch ở Comic & Video. Chuyển `[1.3.775]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng:** đọc code + grep chéo mọi nơi gọi `AudioPlaybackSession.open`, `VideoPlaybackSession.open`, `VideoWatchModel.replace`, `VideoWatchPresenter.present`, `AudioListenRequest(`, `selectEpisode`, `playNextEpisode`, `nextEpisode`; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới** (file mới ≤ 299 dòng, một type chính; `VideoPlaybackSession+Playback` 392, `AudioPlaybackSession` 389). Không build tại chỗ (Windows), chưa thử máy: chuyển mục khác album / khác phim khi app ở nền và trên màn khoá, bỏ qua mục lỗi, mở lại màn xem từ hub giữa lúc mục phim kế đang tải.

## [1.3.804] - 2026-11-09

### fix: thanh widget TTS kiểu nghe nhạc chỉ ghi tên chương, bỏ tiền tố Ch. N

Anh Bửu: *"bỏ dòng ch. x trong hàng tên chương giúp tôi"*.

- `TTSWidgetBarInfoReader.refresh`: dòng 2 của kiểu **Thanh nghe nhạc** chỉ còn tên chương (đã dịch theo phiên TTS, cắt khoảng trắng), không còn "Ch. N · " phía trước; tên rỗng mới lùi về "Chương N". Nhãn "Ch. N" của thẻ Kệ (`BookListRowSize`) không phải hàng tên chương ⇒ giữ nguyên.
- **Kiểm chứng:** đọc code (`displayedChapterTitle` là `String`); `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows), chưa thử máy.

## [1.3.803] - 2026-11-09

### fix: bỏ dòng Âm thanh khỏi hub nổi, trình nghe điều khiển ở thanh mini, nút đĩa Reader và màn khoá

Anh Bửu: *"bỏ hub âm thanh đi"*.

- `FloatingHubItem.Kind` bỏ case `.audio` ⇒ menu hub còn AI → Thông báo → Video → Kiểm tra nguồn. Gỡ theo: `AudioState` / `subscribeToAudio()` / `audioItem()` của `FloatingHubPresentationReader(+Media)`, nhánh `.audio` ở `open` / `togglePlayback` / `stopPlayback` (`FloatingHubContainerViewController+Actions`), glyph của nút hub, cụm nút phát của `FloatingHubMenuRow`. Nhạc không còn là tiến trình của nút hub (không đổi icon, không nháy, không tính vào "mở thẳng khi chỉ có 1 tác vụ").
- `AudioMiniPlayerState` giữ nguyên (thanh mini, nút đĩa Reader, tự sang bài vẫn đọc nó). Chú thích phần âm thanh bỏ chữ "hub".
- Hệ quả: ở trang đẩy vào / sheet / cover không còn lối mở lại màn nghe (thanh mini chỉ ở trang gốc tab); Reader dùng nút đĩa, còn lại màn khoá.
- `CLAUDE.md` / `AGENTS.md`: mục Âm thanh ghi hub không có dòng "Âm thanh". Chuyển entry cũ nhất sang `CHANGELOG.archive.md`.
- **Kiểm chứng:** đọc code + grep chéo `FloatingHubItem.Kind` / `.audio` toàn `Sources/`; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows), chưa thử máy.

## [1.3.802] - 2026-11-09

### feat: tab Playlist ở Kệ sách, tạo sửa xoá playlist nhạc và video, thêm bài hoặc tập từ màn nghe, màn xem phim và Kệ

Anh Bửu duyệt plan "Playlist nhạc và video (tạo, sửa, xoá, phát)" và chốt: playlist gồm **từng bài / từng tập** (không phải cả album), **tách riêng Nhạc và Video**, ở **tab con mới của Kệ sách**, thêm được từ **cả 3 lối**. Đây là **phần 1** (kho + tab + thêm vào playlist); phát playlist (Phát tất cả, xáo, sang mục kế…) là phần sau — chạm một mục chưa làm gì.

- **Kho** (không đụng `@Model`): `playlists/playlists.json` (`PlaylistLibraryFile` có `schemaVersion`). Model ở `Models/Playlists/`: `PlaylistKind` (`audio` / `video`, rawValue là hợp đồng file), `Playlist`, `PlaylistItem` (`packageId`, `detailUrl`, `index` = chỉ số thưa của mục lục đủ, `chapterUrl`, tên, dòng phụ, bìa, tên album, `host` / `sourceName` tuỳ chọn, `addedAt`; giải mã khoan dung — trường vắng lấy mặc định), `PlaylistAlbumInfo`, `PlaylistAddRequest`. Chống trùng = tiện ích + `chapterUrl` (rỗng ⇒ `detailUrl` + `index`), cả trong một lượt thêm.
- **Services/Playlists/**: `PlaylistStore` (chủ file duy nhất, ghi `.atomic`; file hỏng ⇒ cất sang `playlists.broken-<thời điểm>.json`, log `❌`), `PlaylistRepository` (`@MainActor @Observable`, nạp đồng bộ trong `init`, `commit` ghi đĩa trước RAM sau), `PlaylistCoordinator` (tạo / đổi tên / xoá; thêm nhiều mục trả số mục thực sự thêm; bỏ mục và đổi thứ tự **theo id**; gộp từ sao lưu), `PlaylistItemMapper` (dựng mục từ phiên nghe, phiên phim, màn xem, `Book`), `PlaylistAlbumItemsLoader` (mọi bài / tập của album: mục lục trên máy, chưa có thì `BookDetailLoader.fetchFullTOC`, không ghi), `PlaylistError`.
- **Sao lưu**: `BackupPlaylistArchiver` — entry `library/playlists.json` đi kèm nhóm `.books` (không thêm `BackupScope`), luôn ghi, khôi phục là **gộp** (playlist mới theo `id` thêm nguyên; đã có ⇒ thêm mục còn thiếu, giữ tên trên máy), không phụ thuộc công tắc khôi phục cài đặt. **Dung lượng**: loại mới "Playlist" (`StorageUsageCategory.playlists`).
- **Tab Playlist** (`ShelfTab.playlists`, rawValue **4**, khai ngay sau `.collections` ⇒ nút icon `music.note.list` cạnh Bộ sưu tập; trang của `TabView` đặt sau Bộ sưu tập; 🔍 ẩn ở tab này như Tải xuống): chip Nhạc / Video (nhớ bằng `@AppStorage` `shelfPlaylistKind`), lưới thẻ (`PlaylistGridCardView`, bìa ghép `PlaylistCoverMosaicView` = 4 bìa **khác nhau** đầu tiên 2 × 2 qua `RemoteCoverImage`, ít hơn ⇒ một bìa), nhấn giữ thẻ ⇒ Đổi tên / Xoá; trống ⇒ màn mời tạo; nút "+" nổi ⇒ `PlaylistCreateSheet` (tên + loại, mặc định theo chip).
- **Trang chi tiết** `PlaylistDetailView` (trang đẩy vào, `.backPageTitle`): `PlaylistDetailHeader` (bìa ghép, tên, "Nhạc · 12 bài") — hàng nút phát của phần sau đặt ngay dưới; hàng `PlaylistItemRow` (bìa vuông cho nhạc / ngang cho phim, `.headline` + `.subheadline` phụ); vuốt hoặc nhấn giữ ⇒ bỏ mục; ngăn kéo `…`: Sắp xếp lại (chế độ sửa của `List`, "Xong" ở header), Đổi tên, Xoá playlist (hỏi trước — `PlaylistManageAlertsModifier`, dùng chung với thẻ).
- **Sheet "Thêm vào playlist"** (`PlaylistAddSheet`, một sheet cho mọi lối): playlist **cùng loại** (mới sửa trước) + "Tạo playlist mới" (tạo xong thêm luôn); toast "Đã thêm N mục vào <tên>" / "Đã có sẵn trong <tên>". Ba lối: (1) bài / tập đang phát — ngăn kéo `…` + nút `text.badge.plus` ở trang Đĩa của màn nghe, ngăn kéo `⋯` của trình phát phim ("Thêm tập này vào playlist", `VideoPlayerController.playlistAddRequest`); (2) nhấn giữ một bài ở trang Danh sách màn nghe, một tập ở dải tập + sheet "Tất cả tập" của màn xem (Lưới / Danh sách nhận `onAddToPlaylist`); (3) nhấn giữ album / phim trên Kệ ⇒ hàng "Thêm cả album / phim vào playlist" (`PlaylistAddBookActionRow`, vòng chờ trên hàng, lỗi ⇒ toast) — không thêm case `BookSheetAction`.
- Công tắc NSFW tắt ⇒ bìa, số mục và danh sách bỏ mục của nguồn NSFW (như Bộ sưu tập); mục ẩn giữ nguyên chỗ khi xoá / đổi thứ tự.
- `CLAUDE.md` / `AGENTS.md`: thêm `playlists/` vào danh sách thư mục dữ liệu + gạch "Playlist" ở mục Âm thanh. Chuyển `[1.3.772]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng:** đọc code + grep chéo chữ ký (`RemoteCoverImage`, `BookDetailLoader.fetchFullTOC`, `ChapterStore.fetchOrderedTOC`, `SourceRuntimeContext`, `BackupZipArchive.stage/readStaged`, mọi nơi gọi `VideoEpisodeGridView` / `VideoEpisodeListView` / `AudioPlayerDrawerMenu` / `VideoWatchEpisodeSheet`); `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới** (file mới ≤ 200 dòng, một type chính; `BookActionSheet` 389, `BackupRestoreWorker` 398, `VideoPlayerScreen` 374). Không build tại chỗ (Windows). Chưa thử máy: thêm từ ba lối, sheet chồng lên sheet (Tất cả tập, nhấn giữ trên Kệ), kéo đổi thứ tự, sao lưu / khôi phục playlist.

## [1.3.801] - 2026-11-09

### docs: ghi phần gợi ý ở trang Danh sách của màn nghe vào CLAUDE.md và AGENTS.md

- Mục Âm thanh, gạch "Tự phát bài gợi ý": thêm `AudioSuggestionSection` (1.3.800) và `AudioSuggestionStore` dùng chung với `AudioAutoNextCoordinator`.
- **Kiểm chứng:** chỉ sửa tài liệu; `CLAUDE.md` và `AGENTS.md` vẫn trùng nhau trừ 3 dòng đầu.

## [1.3.800] - 2026-11-09

### feat: trang Danh sách của màn nghe hiện bài gợi ý của nguồn, chạm để nghe ngay, nhãn Tiếp theo cho mục sẽ tự phát

Anh Bửu hỏi *"phần suggest của nhạc hiển thị ở đâu"* — trước đây gợi ý chỉ chạy ngầm cho tự phát (1.3.798). Anh duyệt: hiện gợi ý ở trang Danh sách kiểu "Có thể bạn muốn nghe" của Zing MP3.

- **`AudioSuggestionStore`** (mới, `Services/Audio/`, `@MainActor @Observable`): **một nguồn** gợi ý của album đang mở cho cả tự phát lẫn màn nghe. Nhóm gợi ý = `suggests` của chi tiết (chờ chi tiết trình nghe đang tải → cache `BookDetailCacheManager` → tải chi tiết không tương tác), mỗi nhóm có `script` chạy trang 1 **một lần** cho mỗi album; gọi lại cùng album dùng kết quả cũ, album khác ⇒ huỷ lượt cũ. Nhóm đầu tải trước (tự phát cần); các nhóm sau (tới 3 nhóm) chỉ tải khi trang Danh sách hiện (`loadForDisplay`). Phần tải chi tiết / chạy nhóm chuyển từ `AudioAutoNextCoordinator` sang đây (không nhân bản); `Album` chụp album đang mở chuyển theo (`AudioSuggestionStore.Album.snapshot(of:)`, coordinator dùng `typealias`).
- **`AudioAutoNextCoordinator`**: tải trước / thử lại qua store (`firstGroupItems` / `reloadFirstGroup`). Cách chọn mục tự phát gom về **`pick(after:items:)`** — dùng cho cả lúc hết album lẫn nhãn "Tiếp theo" (`upNextLink(in:firstGroupItems:)`: `nil` khi đang lặp / hẹn "Hết bài" / trình nghe rảnh), nên nhãn luôn trùng mục sẽ phát (đã trừ mục đã phát trong chuỗi).
- **Trang Danh sách** (`AudioPlaylistPage`): dưới danh sách bài là **`AudioSuggestionSection`** (mới): mỗi nhóm một tiêu đề (tên nhóm của tiện ích, vd "Bài gợi ý", "Playlist liên quan") + các dòng **`AudioSuggestionRow`** (mới: bìa nhỏ `RemoteCoverImage` — không ghi `covers/`, tên, nghệ sĩ / mô tả, chữ trắng trên nền tối). Mỗi nhóm tối đa 20 dòng (Zing trả tới 100 bài); mục "Tiếp theo" luôn hiện. Chưa tải xong / lỗi / không có gợi ý ⇒ không vẽ gì. Trang hiện / đổi album lúc đang xem ⇒ `loadForDisplay`.
- **Chạm dòng** ⇒ `ContentDetailRouter.openIfVideo` với tiện ích của album: tiện ích âm thanh ⇒ `AudioPlayerPresenter.present` — màn nghe đang mở nên đổi album **tại chỗ**, không chồng màn.
- **Nhãn "Tiếp theo"** (viên thuốc chữ màu nhấn) trên mục sẽ tự phát khi công tắc "Tự phát bài gợi ý" bật (đọc `@AppStorage` ⇒ bật / tắt là đổi ngay); tắt công tắc, đang lặp album / một bài hoặc hẹn "Hết bài" ⇒ không nhãn.
- Log: `⏭️ [AudioSuggest] …` (lỗi tải ghi `❌ [AudioSuggest] …`), `🎵 [AudioPlayerUI] Chọn mục gợi ý …`.
- Chuyển `[1.3.770]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng:** đọc code + grep chéo (`AudioSuggestionStore.Album.snapshot` thay `albumSnapshot`, không còn chỗ gọi `prepareTask` / `loadSuggestions` cũ; chữ ký `ContentDetailRouter.openIfVideo(_:packageId:sourceName:modelContainer:)`, `RemoteCoverImage(url:referer:placeholderSymbol:)`); `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới** (file mới ≤ 216 dòng, một type chính). Không build tại chỗ (Windows). Chưa thử máy: phần gợi ý ở trang Danh sách với Zing MP3 / NhacCuaTui, chạm đổi album tại chỗ, nhãn "Tiếp theo" đổi theo công tắc.

## [1.3.799] - 2026-11-09

### fix: thanh nghe nhạc mini và thanh widget TTS nền đặc giống hệt nhau, thanh TTS cố định vị trí

Anh Bửu: *"cho widget tts thanh nghe nhạc giống hệt thanh nghe nhạc mini, đừng có trong suốt, tôi nói trong suốt là đĩa trong reader ấy. đừng cho nó có thể di chuyển lên xuống, cố định vị trí"*.

- **Nền đặc**: khung chung `MiniPlayerBarChrome` bỏ `FloatingGlassBackground` (độ trong suốt / độ đục của Cài đặt › Giao diện), dùng nền **đặc tối cố định** (`Color(white: 0.12)`) + viền trắng mờ 0,75 pt (`solidBackground(_:)`) ⇒ thanh nghe nhạc mini (`AudioMiniPlayerBar`) và kiểu "Thanh nghe nhạc" của widget TTS giống hệt nhau, chữ trắng đọc rõ trên mọi nền. Viên thu gọn (`TTSWidgetBarPillView`) cùng nền. Nút đĩa nhạc trong Reader và sheet gọn của nó (`ReaderAudioDiscButton`, `AudioQuickControlSheet`) **giữ** theo độ trong suốt — không đổi.
- **Cố định vị trí**: bỏ kéo dọc của thanh và viên (`TTSWidgetBarContainerViewController` chỉ còn cử chỉ vuốt ngang để thu gọn; viên không có cử chỉ). Thanh luôn ngay trên `MainTabBar` (khe 6 pt, đúng chỗ thanh nhạc), viên nép mép phải ngang tâm thanh. Bỏ lưu/đọc vị trí: khoá cũ `ttsWidgetBarBottomGap` / `ttsWidgetBarPillBottomGap` (1.3.796) bỏ qua. Nút » và vuốt ngang để thu gọn giữ nguyên.
- Chữ giải thích ở Cài đặt › Widget TTS bỏ câu "Kéo lên xuống để đổi chỗ"; `CLAUDE.md` / `AGENTS.md` sửa ghi chú widget TTS theo.
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows). Chưa thử máy — cần xem thanh nhạc + thanh TTS trên nền Kệ sáng/tối, và thanh TTS ở trang đẩy vào (không có thanh tab, vẫn đứng ở độ cao đó) có đè nút Home / "+" nổi không.

## [1.3.798] - 2026-11-09

### feat: trình nghe tự phát bài gợi ý khi hết bài hoặc album, công tắc ở Cài đặt › Âm thanh và ngăn kéo màn nghe

Anh Bửu duyệt: trình nghe âm thanh có "Tự phát bài gợi ý", làm **như phim** (`VideoAutoNextCoordinator`, 1.3.751).

- **Công tắc** `AudioAutoNextPolicy` (mới, khoá `audioAutoNextSuggest`, mặc định **bật**): Cài đặt › Đọc & Nghe › **Âm thanh** (`AudioSettingsView`, trang mới; hàng mới ở `ReadingSettingsSection` ngay dưới Video), nhóm "Khi hết bài" có nút "?"; hàng công tắc cùng khoá trong ngăn kéo `…` của màn nghe (`AudioPlayerDrawerMenu` tự đọc `@AppStorage`, không cần environment).
- **`AudioAutoNextCoordinator`** (mới, `Services/Audio/`):
  - **Tải trước**: `beginTrackLoad` báo `trackLoadDidBegin`; bài đang nạp là bài cuối (lặp tắt, `autoAdvanceTarget() == nil` — gồm album một bài; không hẹn "Hết bài") ⇒ lấy nhóm gợi ý của album (chờ chi tiết trình nghe đang tải để khỏi tải trùng → cache chi tiết → tải chi tiết `isInteractive: false`) rồi chạy trang 1 của **nhóm đầu tiên có `script`**.
  - **Hết album** (nhánh "Hết album (không lặp)" của `advanceAfterTrackEnded` ⇒ `albumDidEnd`): mục đầu tiên có link, khác album vừa hết và chưa phát trong chuỗi tự sang (chống A → B → A; chuỗi bắt đầu lại khi album vừa hết không phải album tự sang gần nhất). Tải sẵn rỗng ⇒ thử lại một lần. Trước khi mở kiểm: còn đúng album, vẫn đứng ở cuối (`reachedEndOfItem` — bấm phát lại / tua / chọn bài xoá cờ ngay; không dựa `isPlaying` vì KVO `.paused` của lúc hết bài về qua một nhịp Task), phim có tiếng không giành âm thanh, công tắc còn bật. Mở bằng `AudioListenRequest` cùng tiện ích ⇒ mở thẳng trình nghe, vào Lịch sử như khi tự mở; màn nghe đang hiện tự vẽ theo session. Album nhập từ file / tiện ích chưa cài ⇒ bỏ qua.
  - Background task từ lúc hết album tới khi album mới phát / lỗi / người dùng đổi album / 90 giây (lúc hết album không còn tiếng giữ app sống khi chạy nền).
  - Hẹn giờ tắt mốc phút được giữ qua lượt tự sang (`sleepTimer.schedule` → `restore`, như `open(keepsSleepTimer:)` của phim); hẹn "Hết bài" dừng ở cuối bài, không tự sang.
- **Giữ phiên âm thanh khi chuyển album**: `stopSession(handingOverToTTS:keepsPlaybackSession:)` (tham số mới, mặc định `false`, chỉ coordinator dùng ngay trước `open`) bỏ qua `AudioNowPlayingCoordinator.release`, `deactivateAudioSessionIfIdle` và `AudioMiniPlayerState.reset` ⇒ ở nền / màn khoá không tắt rồi bật lại `AVAudioSession` (có thể không phát được nữa), màn khoá giữ lệnh (`claim()` của album mới thành no-op, `publishNowPlayingLoading` ghi tên bài mới), hub không nhận nhịp `isActive == false`. `open` ngay sau ghi đè hết cầu nối mini; album mới lỗi thì `fail` / `failOpen` trả phiên như thường.
- **Dòng báo "Tự sang: <tên>"** khi album mới bắt đầu phát: `AudioPlaybackNotice` (mới, `ObservableObject`, tự ẩn sau 5 giây) + `AudioPlaybackNoticeBanner` (mới, kiểu `VideoMiniPlayerNotice`) ở đầu vùng trang của màn nghe và ngay trên thanh phát mini. "Bắt đầu phát" lấy từ cầu nối `AudioMiniPlayerState` (Combine) — không thêm hook vào session. Album 18+ lúc NSFW tắt ⇒ "Tự sang bài gợi ý", không ghi tên.
- File chung của trình nghe chỉ thêm dòng gọi: `+TrackLoading` và `+Queue` (mỗi file 1 dòng gọi coordinator), `AudioPlaybackSession.swift` (tham số `keepsPlaybackSession` + 3 điều kiện), `AudioPlayerScreen` / `AudioMiniPlayerBar` (1 overlay mỗi file), `AudioPlayerDrawerMenu` (khoá + 1 hàng).
- Log: `⏭️ [AudioAutoNext] …`; lỗi tải gợi ý / chi tiết ghi `❌ [AudioAutoNext] …`.
- `CLAUDE.md` / `AGENTS.md` mục Âm thanh thêm một gạch đầu dòng.
- Chuyển `[1.3.768]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng:** đọc code + diff (grep chéo chữ ký `stopSession`, `executeCustomScript`, `fetchDetail`, `MediaSleepTimer.restore`); `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới** (file mới ≤ 400 dòng, một type chính; `AudioPlaybackSession.swift` 386 dòng). Không build tại chỗ (Windows). Chưa thử máy: tự sang ở nền / màn khoá, dòng báo, giữ hẹn giờ qua lượt tự sang.

## [1.3.797] - 2026-11-09

### fix: đĩa bìa ở màn nghe nhạc xoay khi đang phát, bìa trang Lời cũng là đĩa xoay

Người dùng: *"cho màn hình phát nghe nhạc cũng làm cover xoay tròn khi đang phát nhạc"*.

- **Nguyên nhân nghi nhất**: trang Đĩa chỉ xoay khi `isOnScreen` = app active (`@Environment(\.scenePhase)`) + đang ở trang Đĩa; màn nghe trình bày bằng UIKit (`AudioPlayerPresenter`, host ngoài cây SwiftUI của scene) nên `scenePhase` có thể không tới ⇒ đĩa đứng im dù đang phát (thanh mini và sheet nhạc trong Reader nằm trong cây SwiftUI nên không bị).
- `AudioPlayerScreen`: bỏ `scenePhase`, tự theo dõi `UIApplication.didBecomeActive` / `willResignActive` (`isAppActive`, khởi tạo theo `applicationState`). Trang Lời cũng nhận cờ này (`isVisible` = app active + đang ở trang Lời + chưa rời màn).
- `AudioLyricsPage`: bìa nhỏ đầu trang (ảnh vuông tĩnh) ⇒ `AudioRotatingCover` 48 pt, xoay khi đang phát, cùng góc `AudioCoverRotation` với trang Đĩa / thanh mini.
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows). Chưa thử máy.

## [1.3.796] - 2026-11-09

### feat: widget TTS thêm kiểu Thanh nghe nhạc trên thanh tab, thu gọn được, chọn ở Cài đặt

Anh Bửu duyệt plan: widget TTS có thêm kiểu giống thanh phát mini nghe nhạc (đĩa tròn xoay), có nút thu gọn, chọn trong cài đặt. Kiểu cũ giữ nguyên làm mặc định.

- **Cài đặt › Đọc & Nghe › Widget TTS** (`TTSWidgetSettingsView`, mới; hàng mới ở `ReadingSettingsSection` hiện kiểu đang chọn): Kiểu widget = **Đĩa nổi** (như trước, mặc định) / **Thanh nghe nhạc**; chọn Thanh thì có thêm "Thu gọn khi mở Reader" (mặc định bật) và "Tự thu gọn sau 5 giây" (mặc định tắt). Khoá `ttsWidgetStyle`, `ttsWidgetBarCollapsesInReader`, `ttsWidgetBarAutoCollapse` (không dấu chấm); tầng chạy đọc qua `TTSWidgetPreferences` (nạp lại theo `UserDefaults.didChangeNotification`, chỉ phát khi giá trị khác). Đổi kiểu ⇒ `TTSFloatingWidgetWindowManager` thay root view controller của cửa sổ widget ngay (cửa sổ, luật hiện/ẩn giữ nguyên).
- **Cửa sổ dùng chung**: `FloatingWidgetUIWindow` giữ `any TTSFloatingWidgetContaining` (protocol mới) và hit-test theo `widgetContainerView` của container ⇒ chỉ nhận chạm trong thanh / viên, phần còn lại chạm xuyên xuống app. Góc đĩa bìa dời ra `TTSWidgetCoverRotation.shared` (trước nằm trong container Đĩa nổi) để đổi kiểu không giật góc; container Đĩa nổi chỉ đổi chỗ lấy `CoverRotationState`, hành vi giữ nguyên.
- **Thanh** (`TTSWidgetBarContainerViewController` + `TTSWidgetBarView`): cùng dáng thanh mini nhạc — tách dáng chung ra `Views/Common/MiniPlayerBar/` (`MiniPlayerBarChrome` 56 pt bo 14 nền kính theo độ trong suốt đã cài, `MiniPlayerProgressLine`, `MiniPlayerControlButton`); `AudioMiniPlayerBar` chuyển sang dùng, hiển thị không đổi. Nội dung: đĩa bìa xoay · tên truyện / "Ch. N · tên chương" (đã dịch theo phiên TTS, `TTSWidgetBarInfoReader` chỉ tính lại khi đổi truyện/chương) + viên phút hẹn giờ còn lại · ⏯ · ⏭ (đoạn kế) · ⏱ (sheet Hẹn giờ, Cài đặt TTS mở từ đó như cũ) · ✕ (dừng) · vạch mảnh · ô » hẹp sát mép phải. Vạch tiến độ chương (đoạn đang đọc / tổng đoạn) ở mép trên là view riêng tự observe (`TTSWidgetBarProgressLine`) — thân thanh không vẽ lại theo từng đoạn. Chạm bìa hoặc chữ ⇒ mở chương đang đọc (`openCurrentlyPlayingReader`).
- **Vị trí**: mặc định ngay trên `MainTabBar` (khe 6 pt, lề ngang 8 pt như thanh nhạc — nhạc và TTS không cùng phát nên không đè). Kéo dọc để đổi chỗ, thả tay thì nhớ (khoảng cách tới đáy vùng an toàn: `ttsWidgetBarBottomGap`, viên riêng `ttsWidgetBarPillBottomGap`), luôn kẹp trong vùng an toàn; xoay màn / đổi vùng an toàn đặt lại khung.
- **Thu gọn** (`TTSWidgetBarViewModel`): » hoặc vuốt thanh sang ngang ⇒ **viên nép mép phải** (`TTSWidgetBarPillView`: đĩa xoay + ⏯, chỉ kéo dọc), chạm đĩa ⇒ bung lại; nhớ đang thu hay bung (`ttsWidgetBarCollapsed`). "Thu gọn khi mở Reader": cờ nhẹ `ReaderPresenceTracker` (mới; `ReaderView` thêm đúng hai dòng ở đầu `onAppear` / `onDisappear`) ⇒ mở Reader tự thu, rời Reader bung lại nếu trước đó đang bung (cờ Reader không lưu); bấm đĩa trong Reader thì bung tới khi rời Reader. "Tự thu gọn sau 5 giây": bung mà 5 giây không bấm nút / không kéo ⇒ thu; sheet Hẹn giờ đang mở thì không đếm (sheet gắn ở gốc nội dung nên thu/bung không làm mất sheet).
- **Giữ chỗ với widget nổi khác**: viên giữ chỗ mép phải trong `FloatingWidgetLayoutCoordinator`; thanh rộng cả hai mép nên gỡ chỗ `.tts`, nút hub tự né khi được thả / hiện ra.
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới** (file mới đều ≤ 400 dòng, một type chính; `ReaderView.swift` +2 dòng, dưới baseline). Không build tại chỗ (Windows). Chưa thử máy. Cần thử: thanh mặc định so với nút Home / "+" nổi ở trang đẩy vào và nút hub; viên thu gọn so với nút tai nghe / đĩa nhạc góc dưới phải của Reader; kéo dọc và vuốt ngang không cướp chạm của các nút trên thanh; Reader truyện tranh **không** tính là Reader (chỉ màn đọc truyện chữ).

## [1.3.795] - 2026-11-09

### feat: hẹn giờ tắt cho xem phim và nghe nhạc giống TTS

Anh Bửu duyệt plan: phim và nhạc có hẹn giờ tắt như TTS (mốc phút, ô cuối riêng, tuỳ chỉnh).

- **Bộ đếm** `MediaSleepTimer` (`Services/Media/`, mới; mỗi phiên một bộ: `VideoPlaybackSession.sleepTimer`, `AudioPlaybackSession.sleepTimer`): mốc 15/30/45/60/90 phút, tuỳ chỉnh 1–180 phút, ô cuối **"Hết tập"** (phim) / **"Hết bài"** (nhạc). Chỉ đếm khi đang phát (app ở nền vẫn đếm; tạm dừng giữ số giây còn lại), đếm theo mốc `systemUptime` nên tick trễ không làm lệch giờ. Hết giờ ⇒ `pause()` của phiên (màn khoá cập nhật qua đường KVO sẵn có) + toast "⏱️ Hẹn giờ (N phút): đã tạm dừng phim/nhạc." qua kênh mới `MediaPresentationEventCenter` (subscriber ở `FreeBookApp`, cùng khuôn `TTSPresentationEventCenter`; Services không gọi `ToastManager`).
- **Sau khi kích hoạt — giống TTS**: chế độ giữ nguyên tới khi người dùng tắt. Mốc phút hết giờ thì lần phát sau đếm lại một vòng đủ; "Hết tập" / "Hết bài" dừng ở cuối mỗi tập / bài.
- **Hết tập** (`VideoPlaybackSession+SleepTimer`, chặn ở đầu `handlePlayedToEnd`): không sang tập kế, không sang phim đề xuất (`VideoAutoNextCoordinator`); lưu tập ở giây 0 như nhánh hết tập cuối. **Hết bài** (`AudioPlaybackSession+SleepTimer`, dòng đầu `advanceAfterTrackEnded`): dừng ở cuối bài kể cả đang lặp một / lặp album, không nạp sẵn bài kế; lưu bài ở giây 0.
- **Gắn với lượt đang phát**: `stop()` (đóng hẳn, mở phim / album khác, TTS giành phiên nhạc) huỷ hẹn giờ. **Ngoại lệ Javis tự chốt**: tự sang phim đề xuất (`open(keepsSleepTimer:)`, truyền từ `VideoWatchModel+Playback`) **giữ** hẹn giờ — ngủ quên thì chuỗi phim đề xuất vẫn dừng đúng giờ.
- **Đếm phim**: `refreshIdleTimer()` (điểm mọi lần trạng thái phát đổi đi qua) gọi `syncSleepTimerCounting()` với điều kiện riêng `launch != nil && isPlaying && không nhúng` — không phụ thuộc màn có hiện (hub, cửa sổ nhỏ, nền vẫn đếm). Phim **nhúng trang** không có trạng thái phát ⇒ không đếm; hàng "Hẹn giờ tắt" ẩn khi đang nhúng mà chưa hẹn. Nhạc: `handleTimeControlChange`.
- **UI**: tách lưới mốc + tuỳ chỉnh của `TTSQuickTimerSheet` thành `SleepTimerOptionsView` (`Views/Common/SleepTimer/`) — sheet TTS giữ nguyên giao diện, hành vi và ô "Hết chương". Phim / nhạc dùng sheet gọn `MediaSleepTimerSheet` (tiêu đề + dòng trạng thái + "Tắt hẹn giờ" khi đang hẹn; vuốt xuống để đóng). Lối vào: **nhạc** — nút ⏱ ở hàng phụ trang Đĩa (đang hẹn ⇒ viên thuốc màu nhấn "m:ss"), hàng "Hẹn giờ tắt" trong ngăn kéo `…` của màn nghe, nút ⏱ cạnh ⤢ trong sheet nhạc của Reader (sheet hẹn giờ mở chồng lên); **phim** — hàng "Hẹn giờ tắt" đầu ngăn kéo `⋯` của trình phát, đang hẹn ⇒ badge ⏱ + số phút còn lại ("Np") ở thanh trên. Số giây chỉ đọc ở view lá `MediaSleepTimerCountdownText`.
- **Kiểm chứng:** đọc code + diff; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới** (`VideoPlaybackSession+Playback.swift` đúng 400 dòng). Không build tại chỗ (Windows). Chưa thử máy: đếm khi app ở nền / khoá màn; hết giờ có tạm dừng + toast; sheet hẹn giờ chồng lên sheet nhạc của Reader; badge thanh trên trình phát.

## [1.3.794] - 2026-11-09

### fix: sheet chọn truyện nguồn / truyện đích của từ điển VP/Name chỉ hiện truyện chữ

Người dùng: *"danh sách chọn truyện nguồn, chọn truyện đích chỉ được hiển thị truyện chữ (hiện tại video, commic, nhạc đều được hiển thị)"* — hai sheet của từ điển VP/Name.

- `BookImportSourceSheet` (nhập từ truyện khác) và `BookShareTargetSheet` (chia sẻ sang truyện khác — cũng dùng ở chia sẻ bộ rule dịch nhanh riêng) bỏ truyện tranh, phim và âm thanh; luật NSFW giữ nguyên.
- Loại sách suy **đúng như router mở sách**: tách `BookContentDestination.resolveKind` thành `BookContentKindResolver` (`Services/Books/`, mới) — ghi đè loại của sách ở nguồn Legado → loại của tiện ích → tiện ích đã gỡ thì xét bản tải truyện tranh / phim. `.unsupported` vẫn tính là chữ (router mở bằng Reader chữ).
- **Kiểm chứng:** đọc code; router gọi resolver mới, hành vi không đổi. `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows). Chưa thử máy.

## [1.3.793] - 2026-11-09

### fix: TTS không còn phát lặp một câu khi âm thanh Google/tiện ích lỗi giải mã

Người dùng (Google TTS): *"tts bị phát lại 1 câu nhiều lần, phải dừng mở lại mới được"*. Log: ~107 dòng `AVAudioPlayer decode error` (OSStatus 560164718 = `'!con'`) trong 11 giây, header vẫn qua (không có lỗi khởi tạo player).

- **Nguyên nhân**: `audioPlayerDecodeErrorDidOccur` của engine remote chỉ hạ `isPlaying` ⇒ player hỏng vẫn chạy (lỗi ~10 lần/giây), `pause()` thoát ngay ở `guard isPlaying` nên nút Dừng / màn khoá không ăn, còn dữ liệu hỏng nằm lại trong `preloadedData` ⇒ bấm phát là `speakCurrent` phát lại đúng câu đó từ đầu. Chỉ dừng hẳn (`clearPrefetchCache`) mới thoát.
- **Sửa** (`TTSManager+PlaybackFailure`, `TTSPlaybackFailureTracker` — mới): lỗi giải mã của player đang phát ⇒ ghi một dòng `❌ [TTSRemote]`, dừng hẳn player (gỡ delegate), bỏ dữ liệu đệm của đoạn, rồi: lần đầu ⇒ tổng hợp lại đoạn đó **một** lần; vẫn lỗi ⇒ **bỏ qua đoạn, đọc tiếp**; bỏ qua liền **3** đoạn ⇒ dừng đọc + thông báo "Âm thanh TTS bị lỗi liên tục, đã tạm dừng đọc.". Đoạn phát trọn ⇒ đếm lại. Player cũ còn bắn lỗi ⇒ gỡ delegate, không xử lý lại. "Phát kết thúc không thành công" (`successfully == false`) đi cùng lối phục hồi thay vì chỉ hạ cờ.
- **NghiTTS/VieNeu**: đoạn kế lỗi giải mã chỉ được tổng hợp lại tối đa một lần mỗi đoạn (trước đó có thể tổng hợp lại mãi).
- **Log chẩn đoán** (luôn ghi vì có `❌`): engine, chương, đoạn, id, số byte, 8 byte đầu, sample rate, số kênh, độ dài, vị trí, domain#mã lỗi — không ghi nội dung chương. Nhánh Nghi ghi `❌ [NghiQueue]` một lần cho mỗi player.
- **Kiểm chứng:** đọc code; `TTSManager.swift` 3467 dòng (baseline 3470); `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows). Chưa thử máy — lỗi hiếm (anh gặp một lần), dòng log mới sẽ cho biết dữ liệu hỏng hay phiên âm thanh lỗi nếu gặp lại.

## [1.3.792] - 2026-11-09

### feat: nút đĩa nhạc trong Reader trên nút tai nghe, chạm mở sheet điều khiển gọn theo độ trong suốt

Anh Bửu duyệt plan (kiểu A): khi đang có album trong trình nghe, Reader có nút riêng để điều khiển nhạc mà không phải rời màn đọc.

- **Nút đĩa nhạc** `ReaderAudioDiscButton` (file mới, `Views/Reader/Components/`): tròn 52 pt, nền `FloatingGlassBackground(isDark:outline:)` như nút tai nghe (theo Cài đặt › Chung › Giao diện), nằm ngay **trên** nút tai nghe, cách 12 pt; chỉ hiện khi `AudioMiniPlayerState.isActive` (không có album thì không chiếm chỗ — nút tai nghe đứng nguyên chỗ cũ). Trong nút là bìa đĩa tròn 44 pt **xoay khi đang phát**, đứng yên khi dừng (`AudioRotatingCover`, góc chung `AudioCoverRotation` với thanh mini / trang Đĩa), đặt trên nền tối riêng để nốt nhạc dự phòng vẫn thấy ở nền đọc sáng; album 18+ lúc NSFW tắt ⇒ chỉ nốt nhạc, không tải bìa. View riêng chỉ đọc cầu nối `AudioMiniPlayerState` (không chạm `AudioPlaybackSession` khi chưa mở, `ReaderView` không vẽ lại theo tiến độ bài). Gắn qua `readerEdgeControls(geometry:)` mới ở `ReaderView+Controls` (`ReaderView.swift` chỉ đổi một dòng).
- **Sheet điều khiển gọn** `AudioQuickControlSheet` (file mới, `Views/AudioPlayer/`): cao vừa nội dung (đo như `FittedSheetDetentModifier`, chiều cao giữ ở nút), thanh kéo hệ thống, không nút chỉ để đóng. Nền kính theo "Độ trong suốt" / "Độ đục" **của ngăn kéo menu** (`GlassChromeSettings.drawer*` — cùng kiểu ngăn kéo `…` của Reader, tông tối; mặc định nút nổi 90% trong suốt không nhoè sẽ không đọc được chữ trên trang truyện) qua `.presentationBackground`, nội dung ở `colorScheme` tối, màu nhấn app (`.appAccentTint()`). Nội dung: đĩa bìa xoay + tên bài + "nghệ sĩ · album" + ⤢ (màn nghe đầy đủ); một dòng lời đang hát (`AudioCurrentLyricLine`) hoặc chữ lỗi; thanh tua `AudioPlayerSeekRow` + cụm Xáo · ⏮ · ⏯ · ⏭ · Lặp `AudioTransportControls(.full)` dùng lại của màn nghe (tông trắng trên nền kính tối, không phải sửa); hàng Danh sách · Lời · Tắt nhạc (viên thuốc cao 38 pt, nền mờ, không tô nền đặc màu nhấn). Album 18+ lúc NSFW tắt ⇒ "Đang phát", không bìa, không lời.
- **Mở màn nghe ở trang chỉ định**: `AudioPlayerScreen(initialPage:onDismiss:)` (mặc định Đĩa) + `AudioPlayerPresenter.reopen(at:)` (đặt trang cho đúng một lượt trình bày rồi `requestScreen`). Nút chờ sheet **đóng xong** (`onDismiss`) mới gọi — trình bày từ sheet đang đóng thì UIKit đóng luôn màn mới. "Tắt nhạc" đóng sheet rồi `AudioMiniPlayerState.onStop` (dừng hẳn). Album bị dừng nơi khác (bấm tai nghe đọc TTS — 1.3.791) ⇒ nút biến mất, sheet đang mở tự đóng.
- Log: `🎵 [AudioPlayerUI] Mở sheet điều khiển nhạc từ nút đĩa Reader`, `… Mở màn nghe từ sheet điều khiển của Reader (trang …)`, `… Tắt nhạc từ sheet điều khiển của Reader`; log trình bày màn nghe ghi thêm trang.
- `CLAUDE.md` / `AGENTS.md` mục Âm thanh thêm một câu về nút đĩa + sheet + `reopen(at:)`.
- Chuyển `[1.3.762]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng:**
  - Đọc code: `.sheet` gắn ở khung ngoài luôn tồn tại của nút (không trong nhánh `if mini.isActive`); vùng đệm giữa hai nút không nhận chạm; `AudioPlayerScreen()` của router vẫn dịch được nhờ tham số mặc định.
  - `check_architecture.py`: 1 violation nền (`JSDom.swift`), **0 mới**.
  - Không build tại chỗ (Windows). Chưa thử trên máy: đĩa xoay / đứng yên theo nhạc, chiều cao sheet vừa nội dung, nút Danh sách / Lời mở đúng trang, nền sheet đổi theo cài đặt ngăn kéo.

## [1.3.791] - 2026-11-09

### feat: nhạc và TTS không bao giờ cùng phát: nghe nhạc tắt TTS, đọc TTS dừng nhạc

Anh Bửu duyệt plan: không bao giờ cùng lúc có thanh nhạc mini lẫn widget TTS. Trước đây (1.3.784) nhạc bắt đầu chỉ **tạm dừng** TTS và TTS bắt đầu chỉ **tạm dừng** nhạc ⇒ cả hai thanh cùng nằm trên màn. Phim giữ nguyên luật nhường cũ với cả hai.

- **Nhạc bắt đầu phát ⇒ tắt hẳn TTS** (`AudioPlaybackSession+AudioSession`, helper `stopTTSForMusic`): `beginUserRequestedPlayback` (mở album, chọn bài, bấm phát, thử lại) và `prepareAudioForPlayback` (bài sẵn sàng tự phát — kể cả tự sang bài —, `play()`, chuyển sang phát từ màn khoá / tai nghe) gọi `TTSManager.stop()` như nút ✕ của widget (lưu tiến độ đọc, ẩn widget, xoá Now Playing) khi TTS có phiên (`isPlaying || showFloatingWidget`). Vẫn chạy **trước** `setActive(true)` + `claim()` như cũ. Mở lại mục nghe lúc khởi động (`autoplay: false`) không đụng TTS.
- **TTS bắt đầu / tiếp tục đọc ⇒ dừng hẳn trình nghe**: `AudioNowPlayingCoordinator.yieldToTTS()` (hai hook có sẵn ở `TTSManager+NowPlaying`, không đổi code TTS) giờ trả phiên màn khoá **trước** (`release(handBackToTTS: false)`) rồi gọi action mới `stopForTTS` ⇒ `AudioPlaybackSession.stopForTTS()`: như `stop()` (lưu tiến độ, gỡ item, `AudioMiniPlayerState.reset()` ⇒ thanh mini + dòng hub ẩn, màn nghe đang mở tự đóng) nhưng **không** dựng lại lệnh / Now Playing của TTS (tránh đệ quy `reclaimRemoteControlsAfterVideo` → `setRemoteCommandsEnabled` lúc `startSpeaking` / `resume` đang chạy) và **không** tắt `AVAudioSession` (hook chạy sau `configureAudioSession()` của TTS nhưng trước `isPlaying = true` — tắt lúc đó là TTS câm). Không có album ⇒ không làm gì; chưa từng mở trình nghe ⇒ `actions == nil`, không dựng `AVPlayer`.
- `stop()` tách thân thành `stopSession(handingOverToTTS:)`; `yieldToOtherMedia()` (phim) giữ hành vi tạm dừng + trả phiên, bỏ hàm chung `yield(reason:)`.
- Log mới: `⏹️ [AudioPlayer] … ⇒ tắt hẳn TTS`, `⏹️ [AudioPlayer] TTS bắt đầu đọc ⇒ dừng hẳn trình nghe`, `⏹️ [AudioNowPlaying] TTS bắt đầu đọc ⇒ nhường điều khiển màn khoá, dừng hẳn nhạc`; log đóng trình nghe ghi thêm ", nhường TTS".
- Doc comment `AudioNowPlayingCoordinator`, `MediaNowPlayingOwnership`, `AudioPlaybackSession(+AudioSession)`, `TTSManager+NowPlaying` và dòng "Màn khoá ba bên" của `CLAUDE.md` / `AGENTS.md` theo luật mới.
- Chuyển `[1.3.757]`–`[1.3.761]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng:**
  - Đọc code: `TTSManager.stop` không đi qua `setSystemNowPlayingPlaybackState(.playing)` (không gọi ngược vào trình nghe); `prepareSpeaking` không hiện widget nên widget TTS chỉ xuất hiện qua `startSpeaking` (đã dừng nhạc); `Actions` chỉ dựng ở `installRemoteActions`.
  - `check_architecture.py`: 1 violation nền (`JSDom.swift`), **0 mới**.
  - Không build tại chỗ (Windows). Chưa thử trên máy: đang nghe nhạc bấm tai nghe Reader ⇒ thanh nhạc + hub biến mất, TTS đọc có tiếng; đang đọc TTS mở album ⇒ widget TTS biến mất; màn khoá đúng bên.

## [1.3.790] - 2026-11-09

### docs: ghi phân hệ âm thanh vào CLAUDE.md và AGENTS.md

- Mục mới **Âm thanh (1.3.784–789)**: loại `audio` mở thẳng màn nghe, lõi `AudioPlaybackSession` (nguồn đầu tiên có `data`, `audios[0]`, lời), màn khoá ba bên qua `MediaNowPlayingOwnership`, giao diện `Views/AudioPlayer/` + thanh mini + hub, những gì chưa có (tải/xuất, Legado âm thanh, dò mp3 trong trang).
- Sửa ba câu đã lệch code: router chọn thêm `AudioListenRouteView`; `currentChapterPage` = số giây cả với âm thanh; autoplay tắt tiếng của trình duyệt tiện ích bật cho cả loại âm thanh.
- **Kiểm chứng:** chỉ sửa tài liệu; `CLAUDE.md` và `AGENTS.md` vẫn trùng nhau trừ 3 dòng đầu.

## [1.3.789] - 2026-11-09

### feat: nhận loại tiện ích âm thanh: hiện ở Khám phá, Tìm, Kệ và mở thẳng màn nghe

Phần 1/3 (phần cuối) của trình nghe âm thanh cho tiện ích JS loại `audio` (plan anh Bửu đã duyệt): app nhận loại `audio` ở mọi nơi và nối định tuyến tới màn nghe đã có (1.3.784–788). Không sửa lõi `Sources/Services/Audio/` lẫn giao diện `Sources/Views/AudioPlayer/`.

- **`ExtensionContentKind.audio`** (nhóm `audio`/`music` của `ExtensionFilterGroups`, hằng mới `audioGroup`): nhãn "Âm thanh", icon `music.note`. `isMedia` gồm âm thanh (mục lục gắn `isSection`, không đi pipeline chữ); `isPlayable` (mới) = phim hoặc âm thanh.
- **Chip + bố cục**:
  - `SearchExtensionScopePolicy.browsableKinds` thêm `.audio` (sau `.video`) ⇒ chip "Âm thanh" ở Khám phá, Tìm, Kệ; Đổi nguồn / gắn lại nguồn mất chỉ cùng loại.
  - `BookListLayoutScope.audio`: nhãn "Âm thanh", "album", bìa lưới vuông 1:1 (ghi chú ở sheet Kiểu hiển thị và Cài đặt › Kiểu hiển thị danh sách); `ExploreLayoutSizePreferences.scopes` thêm `.audio` (thiếu thì cỡ trang Khám phá của âm thanh không lưu được).
  - Badge loại màu cam. Dòng danh sách (`BookListItemView`): bìa vuông qua `BookListRowSize.coverHeight(for:)` — badge loại + ghim của `ShelfBookRowView` canh theo cùng khung; "Bài N" / "Đang nghe". Thẻ lưới kệ "Bài N" (`BookListRowSize.progressLabel`).
- **Định tuyến — mở thẳng màn nghe, không bao giờ Chi tiết**:
  - `ContentDetailRouter.openIfVideo` giữ tên (8 lối gọi tự nhận): âm thanh ⇒ `AudioPlayerPresenter.present(AudioListenRequest(…))`. `opensPlayer(packageId:)` (mới) cho `ContentDetailLink` và `SearchSingleSourceResultsView`; `isVideo` giữ chỉ phim (đổi phim tại chỗ ở trang thể loại của màn xem).
  - `VideoWatchPagePresenter.openDetail`: đề xuất âm thanh ⇒ màn nghe thay cho trang Chi tiết.
  - `BookContentDestination` `.audio` ⇒ `AudioListenRouteView` (Kệ, Tìm trên kệ, Bộ sưu tập, chạm bài ở Chi tiết, mở lại lúc khởi động — `ShelfView+LaunchRestore` không lọc theo loại nên không phải sửa).
  - `WebViewLoader`: tiện ích âm thanh cũng được tự phát media tắt tiếng (bước dò link `auto`/`webview`).
- **Ẩn tải / xuất của album**: sheet nhấn giữ `BookActionSheet` (ẩn Tải + Xuất, không mở Chi tiết), Chi tiết (`showsExport`, `downloadActionTitle`), `TaskOptionsSheet` (chốt chặn: báo chưa hỗ trợ, khoá "Bắt đầu"), `DownloadTrackerView` (không có "Xuất … đã tải"), `BookExportFormat.formats(.audio) = []`, `DownloadManager+Comic` báo thất bại ngay tác vụ của album (không rơi vào nhánh truyện tranh hay pipeline chữ).
- **Kiểm tra tiện ích**: `ExtensionCheckReport.Kind.audio` ("Âm thanh"); truyện thử chạy `chap` bằng `audioStreamData` rồi `track` bằng `audioTrack` (`runAudio`, đúng đường của trình nghe), mục lục đếm "bài".
- `ExtensionConfigHeaderCard`: âm thanh hiện badge loại như các loại được hỗ trợ (không phải sửa file).
- Chuyển `[1.3.756]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng:** đọc code; grep lại mọi `switch` / so sánh `.video` theo loại nội dung; check_architecture 0 lỗi mới (chỉ còn lỗi có sẵn `JSDom.swift`); không build tại chỗ (Windows); chưa thử máy.

## [1.3.788] - 2026-11-09

### feat: bìa thanh phát mini và trang Đĩa là đĩa tròn xoay như widget TTS, hub không nháy khi màn nghe đang mở

Anh Bửu đổi yêu cầu thanh phát mini (1.3.787): bìa là **đĩa tròn** (không còn vuông bo góc) và **xoay** khi đang phát, dừng thì đứng yên ở góc đang có — dùng lại đúng cơ chế xoay của widget TTS.

- `AudioRotatingCover` (mới): đĩa bìa tròn dùng `TTSRotatingCoverView` (Core Animation trên render server, gỡ animation khi không xoay ⇒ không tốn CPU lúc không hiện, không giật về 0) + `CoverRotationState` của widget TTS — **không** sửa file nào ở `Sources/Views/TTSWidget/`, không nhân bản cơ chế. Ảnh qua `CoverImageLoader` (downsample theo cỡ khung, không ghi `covers/`); chưa có ảnh / không bìa / album 18+ lúc NSFW tắt (không tải bìa) ⇒ nốt nhạc tĩnh.
- `AudioCoverRotation` (mới): **một** `CoverRotationState` dùng chung cho đĩa của thanh mini ở mọi tab và trang Đĩa ⇒ cùng góc; theo `AudioMiniPlayerState.isPlaying` (`syncPlaybackState`), đổi album ⇒ `resetAngle`. Tốc độ theo widget TTS: 15 s/vòng (trước là 20 s/vòng của bản `TimelineView`).
- Thanh mini: bìa 40 pt thành đĩa tròn xoay khi đang phát. Trang Đĩa của màn nghe dùng cùng view (xoay khi trang hiện, app mở và nhạc đang phát); bỏ `AudioSpinningDisc` / `AudioDiscArtwork` (`TimelineView`).
- Hub: dòng Âm thanh vẫn sáng lúc màn nghe đang hiện nhưng không tính là tiến trình của nút hub (`AudioState.isScreenPresented` ⇒ `isActive == false`, như Video chỉ tính khi đã thu nhỏ) ⇒ nút hub không nháy / không đổi icon đè lên màn nghe.
- Chuyển `[1.3.755]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng:** đọc code; check_architecture 0 lỗi mới (chỉ còn lỗi có sẵn `JSDom.swift`); không build tại chỗ (Windows); chưa thử máy; chưa nối định tuyến — Phần 1.

## [1.3.787] - 2026-11-09

### feat: màn nghe âm thanh ba trang kiểu Zing MP3, thanh phát mini và dòng Âm thanh ở hub

Phần 3/3 của trình nghe âm thanh cho tiện ích JS loại `audio` (plan anh Bửu đã duyệt): giao diện trên lõi `AudioPlaybackSession` (1.3.784–786). **Chưa** nối định tuyến / `ExtensionContentKind.audio` (phần 1 gọi presenter / route view dưới đây). Không sửa lõi `Sources/Services/Audio/`.

- **Màn nghe** `AudioPlayerScreen` (`Sources/Views/AudioPlayer/`, bố cục tham khảo Zing MP3, không dùng logo / asset của họ): nền tối lấy màu trung bình của bìa (`AudioCoverBackdrop`, ảnh 64 px, làm tối, nhớ theo URL; không bìa ⇒ xám-ngọc tối), chữ trắng, điểm nhấn = màu nhấn của app. Header ⌄ (thu nhỏ) · "Phát từ album" + tên album · `…` (ngăn kéo: thông tin album, Mở trang nguồn `.sourcePageBrowser`, chọn nguồn lời khi ≥ 2, tốc độ phát, Dừng hẳn). Chấm chỉ trang + 3 trang vuốt ngang (`TabView` `.page`), mở vào trang giữa:
  - **Danh sách phát** (`AudioPlaylistPage`): "Danh sách phát · N bài", số thứ tự theo vị trí, luôn theo mục lục (không theo thứ tự xáo); bài đang phát chữ màu nhấn + nền nhấn mờ 18% + loa; chạm ⇒ `playTrack(at: track.index)`; trang hiện ⇒ cuộn bài đang phát vào giữa.
  - **Đĩa** (`AudioDiscPage`): bìa tròn ~70% bề ngang xoay 20 s/vòng khi đang phát (`AudioSpinningDisc`: `TimelineView` 30 nhịp/s, dừng thì đứng ở góc đang có, ngưng hẳn khi trang khác / app ở nền / nhạc dừng); tên bài + nghệ sĩ + ♡ (thêm / bỏ kệ qua `BookTransactionCoordinator` — `AudioShelfToggle`, bỏ kệ = `removeFromShelf`; mờ khi album chưa có `Book`); một dòng lời đang hát; thanh tua (`VideoSeekBar`, nhả tay mới `seek`) + `mm:ss`; Xáo · ⏮ · ⏯ (vòng xoay khi đang nạp / đệm) · ⏭ · Lặp; hàng phụ tốc độ (menu 0,5–2×), sang trang Danh sách / Lời. Bài lỗi ⇒ câu lỗi + "Thử lại" + `ErrorLinkButton` (`.errorLinkBrowser` thử lại bài).
  - **Lời** (`AudioLyricsPage` + `AudioLyricsScrollView`): bìa nhỏ + tên bài; lời có mốc giờ ⇒ dòng đang hát to + màu nhấn, dòng đã qua mờ, tự cuộn giữ giữa (cuộn tay ⇒ ngưng 3 s), chạm dòng ⇒ tua tới mốc; lời chữ thường cuộn tay; đang tải / không có lời / lỗi (+ Thử lại) báo ngắn; chọn nguồn lời; cuối trang thanh tua + cụm nút gọn.
  - Giây phát chỉ đọc ở `AudioPlayerSeekRow` ⇒ cả màn không vẽ lại mỗi tick. Màn gắn / gỡ session bằng token (`attachScreen` / `detachScreen`); trình duyệt lỗi / trang nguồn che màn không tính là rời màn; session dừng ở nơi khác ⇒ màn tự đóng.
  - **Vuốt xuống để thu nhỏ** (`AudioMinimizeDragState` / `AudioMinimizeDragContainer` / `AudioMinimizeDragGesture`): kéo xuống ở header, đĩa, dòng tên bài, đầu trang Danh sách / Lời (không ở thanh tua, vùng cuộn) ⇒ cả màn trôi theo tay, quá 140 pt hoặc vuốt nhanh ⇒ trượt nốt rồi đóng, nhạc vẫn phát.
- **Presenter** `AudioPlayerPresenter`: `present(_ request: AudioListenRequest, modelContainer:, autoplay: Bool = true, animated: Bool = true)` mở album rồi trình bày bằng UIKit `.overFullScreen` (`AudioPlayerHostingController`, chỉ dọc; gắn lại `.appAccentTint()` + `.modelContainer`); màn nghe đang hiện ⇒ chỉ đổi album, không chồng màn. `install()` gắn `presentScreenHandler` (thanh mini / hub mở lại màn), gọi ở `present`, `openInPlace` và lúc màn hiện. `AudioListenRouteView(launch:)` cho router: màn nằm trong `fullScreenCover` sẵn có (như `VideoWatchRouteView`), mở album một lần, lượt mở lại lúc khởi động (`ReaderSessionRestoreStore.consumePausedVideoStart`) ⇒ `autoplay: false`.
- **Thanh phát mini** `AudioMiniPlayerBar`: ngay trên `MainTabBar` ở trang gốc các tab (cùng khối `safeAreaInset` của `MainTabBarModifier` ⇒ nội dung tự chừa chỗ, ẩn cùng thanh tab khi bàn phím hiện); bìa 40 pt (1.3.788 đổi thành đĩa tròn xoay), tên bài + nghệ sĩ, ⏯, ⏭, ✕ (dừng hẳn), vạch tiến độ màu nhấn ở mép trên, chạm phần còn lại ⇒ mở lại màn nghe; nền `FloatingGlassBackground`. Ẩn khi không có album / màn nghe đang hiện. Album 18+ lúc NSFW tắt ⇒ "Đang phát", không bìa. Chỉ đọc `AudioMiniPlayerState`.
- **Hub**: `FloatingHubItem.Kind.audio` ("Âm thanh", `music.note`) ngay sau Video — xám khi không có album; có album ⇒ dòng phụ = tên bài (18+ lúc NSFW tắt ⇒ "Đang phát" / "Đã dừng"; lỗi ⇒ chữ đỏ), nút phát/dừng + ✕ như dòng Video (`FloatingHubMenuView` / `FloatingHubMenuRow` / `+Actions` đổi sang `togglePlayback(_:)` / `stopPlayback(_:)` theo loại dòng), chạm ⇒ mở lại màn nghe. Album đang dừng vẫn là mục của nút hub nhưng không nháy (`quietKinds`). Dòng Video + Âm thanh dựng ở `FloatingHubPresentationReader+Media` (giữ file chính dưới 400 dòng); trạng thái nghe theo dõi không gồm tiến độ ⇒ hub không vẽ lại theo nhịp phát.
- Chuyển `[1.3.754]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng:** đọc code; check_architecture 0 lỗi mới (chỉ còn lỗi có sẵn `JSDom.swift`); không build tại chỗ (Windows); chưa thử máy; chưa nối định tuyến — Phần 1.

## [1.3.786] - 2026-11-09

### fix: màn khoá của trình nghe hiện nút bài trước/sau thay vì tua ±15 giây

Rà lại 1.3.784: `AudioNowPlayingCoordinator.claim` bật cả `skipForward/skipBackwardCommand` ⇒ iOS hiện nút tua ±15 s trên màn khoá **thay chỗ** nút bài trước/sau, lệch plan đã duyệt (màn khoá: phát/dừng, bài trước/sau, kéo thanh tua).

- `claim`: tắt tường minh hai lệnh tua (TTS có thể đã bật), bỏ đăng ký target tua và `preferredIntervals`; bỏ `skipInterval` / `skipPayload`. Tua ±15 s chỉ còn trong màn nghe; tai nghe / AirPods vẫn chuyển bài qua `next/previousTrackCommand`.
- **Kiểm chứng:** đọc code; không build tại chỗ (Windows); chưa thử máy.

## [1.3.785] - 2026-11-09

### fix: bấm phát sau khi bài nhạc lỗi giữa chừng thì thử lại bài đó

Rà lại 1.3.784: bài lỗi lúc đang phát (`AVPlayerItem` báo `failed` / `failedToPlayToEndTime`) để item hỏng vẫn gắn vào player ⇒ `AudioPlaybackSession.play()` thấy có item chưa `readyToPlay` nên chỉ chờ, không làm gì; nút phát/dừng của thanh mini / hub / màn khoá (`togglePlayPause`) cũng vậy.

- `play()`: đang `.failed` ⇒ `retry()` trước mọi nhánh khác (gỡ item hỏng, nạp lại bài ở giây đang nghe).
- **Kiểm chứng:** đọc code; check_architecture 0 lỗi mới (chỉ còn lỗi có sẵn `JSDom.swift`); không build tại chỗ (Windows); chưa thử máy.

## [1.3.784] - 2026-11-09

### feat: lõi phát âm thanh riêng cho tiện ích loại audio: lặp, xáo, lời bài hát, màn khoá

Phần 2/3 của tính năng trình nghe âm thanh cho tiện ích JS loại `audio` (plan anh Bửu đã duyệt): chỉ lõi phát ở `Sources/Services/Audio/`, **chưa** có màn nghe / thanh mini / hub (phần 3) và **chưa** nối định tuyến / `ExtensionContentKind.audio` (phần 1).

- **`AudioPlaybackSession`** (`@MainActor @Observable`, `shared`, `AVPlayer` riêng; chia `+Loading`, `+TrackLoading`, `+Player`, `+Transport`, `+Queue`, `+Progress`, `+AudioSession`, `+NowPlaying`, `+Lyrics`, `+MiniPlayer`): `open(_:modelContainer:autoplay:)` — album khác ⇒ dừng album cũ; cùng album ⇒ không nạp lại (chỉ chuyển bài / thử lại); `autoplay: false` (mở lại lúc khởi động) ⇒ nạp tới bài + giây đã lưu rồi dừng sẵn. Album: `Book` + mục lục trên máy phát ngay rồi làm mới từ nguồn ở nền (lấy nghệ sĩ, nhận bài thêm ở cuối); chưa có thì chi tiết + mục lục đủ từ nguồn, tạo `Book` + ghi mục lục (`ChapterContentRepository.saveChapterList`, như màn xem phim) trước lần lưu tiến độ đầu. Dòng `section` bị bỏ; `Track.index` là chỉ số mục lục thật (thưa).
- **Mỗi bài**: `chap` chỉ lấy nguồn đầu tiên có `data` (không có ⇒ URL bài — `ExtensionManager/SourceRuntime.audioStreamData`) → `track` (`audioTrack`: `VideoTrack` + nguồn lời, ánh xạ trong cùng `runMediaScript`) → áp `audios[0]` (`data`, `headers` khi khác rỗng), bỏ `audios` để `VideoSourceResolver` không ghép tiếng vào hình; `auto`/`webview` trỏ thẳng file nghe (`.mp3`, `.m4a`…) ⇒ `native` → chỉ nhúng được trang ⇒ lỗi "Nguồn này chỉ phát được trong trang web.". Nguồn Legado ⇒ lỗi chưa hỗ trợ. Lượt nạp gắn generation, `CancellationError` không là lỗi.
- **Nạp sẵn** bài kế khi bài hiện còn ≤ 15 s (resolver riêng, cache theo chỉ số + lượt mở, quá 10 phút bỏ; lỗi thì không thử lại mỗi tick). **Lặp** `AudioRepeatMode` `off` → `album` → `one` + **xáo trộn** (hoán vị bắt đầu bằng bài đang phát; hết vòng lặp album thì xáo lại, vòng kế dựng sẵn để nạp sẵn và lúc hết bài chọn cùng một bài), nhớ toàn app (`AudioPlaybackPreferences`: `audioPlayerRepeatMode`, `audioPlayerShuffle`). Bài trước khi đã quá 3 s ⇒ về đầu bài. Tốc độ 0,5–2× (`defaultRate`).
- **Lời bài hát**: model `AudioLyricSource` / `AudioLyrics` / `AudioLyricLine` (`Models/Extensions/Media/`), `AudioLyricMapper` (`lyrics` mảng / chuỗi trần, `lyric` + `lyricType`), `AudioLyricLoader` (URL http(s) tải kèm header track, URI `data:`, chữ trực tiếp), `AudioLyricParser` (LRC nhiều nhãn / `[offset:]` / bỏ nhãn meta và `<mm:ss.xx>`; VTT/SRT qua `VideoSubtitleParser`; còn lại chữ thường bỏ HTML). Nạp sau khi bài sẵn sàng, nguồn đầu có nội dung thắng, `selectLyricSource`, `currentLyricLineIndex` theo tick.
- **Màn khoá** — `AudioNowPlayingCoordinator` (khuôn `VideoNowPlayingCoordinator`): tên bài, nghệ sĩ (`description` của mục `toc` — thêm `ChapterResult.itemDescription`, không lưu `ChapterStore`) / tác giả album, tên album, bìa cắt vuông; phát/dừng, bài trước/sau, kéo thanh tua, tua ±15 s; nguồn 18+ ⇒ "Đang phát" + `LockScreenAppIcon`. Now Playing đánh dấu bằng `MPNowPlayingInfoPropertyExternalContentIdentifier` (TTS cũng ghi loại `.audio`), trả phiên thì xoá.
- **Phân xử ba bên**: `MediaNowPlayingOwnership.isHeldByMedia` (phim **hoặc** nhạc giữ phiên) thay 9 chỗ `VideoNowPlayingCoordinator…isHoldingSession` ở `TTSManager+NowPlaying` / `TTSNowPlayingController`; TTS bắt đầu đọc ⇒ nhạc `yieldToTTS`. Nhạc do người dùng phát ⇒ dừng TTS + `VideoNowPlayingCoordinator.yieldToOtherMedia` (mới) rồi mới `claim`. Phim có tiếng bắt đầu / người dùng chọn phát phim ⇒ `AudioNowPlayingCoordinator.yieldToOtherMedia`; phim **tắt tiếng** phát cùng nhạc như với TTS (cả nút âm lượng cứng). Cờ nhẹ `AudioPlaybackFlag` (không dựng `AVPlayer`): TTS dừng / phim đóng không tắt `AVAudioSession` khi nhạc còn phát; nhạc đóng chỉ tắt khi TTS và phim native đều không phát. `AVAudioSession` `.playback` / `.default`; ngắt (cuộc gọi) ⇒ dừng, hết ngắt + `shouldResume` ⇒ phát tiếp.
- **Tiến độ + Lịch sử**: `ReadingProgressStore.checkpoint` — `chapterIndex` = bài, `paragraphIndex` = **số giây**; lúc bắt đầu phát, tạm dừng, đổi bài, mỗi ~10 s, vào nền, đóng. Mở lại album ⇒ tiếp đúng bài + giây (request chỉ định bài thì theo request; `-1` = đầu bài).
- **Cầu nối** `AudioMiniPlayerState` (`ObservableObject`, như `VideoMiniPlayerState`) + `presentScreenHandler` / `requestScreen` / `attachScreen` / `detachScreen` cho phần 3. `AudioListenRequest` dùng lại quy tắc id của `VideoWatchRequest`.
- **Kiểm chứng:** đọc code; check_architecture 0 lỗi mới (chỉ còn lỗi có sẵn `JSDom.swift`); không build tại chỗ (Windows); chưa thử máy; chưa nối UI/định tuyến (phần sau).
