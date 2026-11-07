# CHANGELOG - Nhật ký Thay đổi CodeGraph Tàng Công Các

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **Tàng Công Các**.

## [1.3.776] - 2026-11-07

### feat: hàng thể loại ở màn xem phim hiện đủ trên một hàng, thiếu chỗ thì cuộn ngang

Người dùng: *"phần genres ở trình xem video (thanh các tag dạng #tên tag) hãy hiển thị đầy đủ trên 1 hàng, không đủ thì scroll ngang"*.

- `VideoWatchTitleBlock`: hàng nhãn `#ThểLoại` hiện **mọi** thể loại (bỏ giới hạn 4), mỗi nhãn đủ chữ (bỏ cắt đuôi), nằm trong `ScrollView` ngang không thanh cuộn; hàng cuộn tràn sát hai mép màn, nhãn đầu vẫn thẳng lề 16 với tên phim.
- **Kiểm chứng:** đọc code + diff; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows). Chưa thử trên máy.

## [1.3.775] - 2026-11-07

### feat: nút Home của màn xem phim thu phim vào cửa sổ nhỏ hay hub theo cài đặt vuốt xuống

Người dùng: *"khi bấm vào home thì tình trạng video là pip hay vào hub sẽ theo config vuốt xuống trình phát"*.

- Nút Home "Về Khám phá" của màn xem phim và nút Home nổi của trang đè lên màn xem (thể loại / Chi tiết) thu nhỏ phim theo **Cài đặt › Video › Vuốt xuống trình phát** (`VideoMinimizePolicy`: riêng phim thường / phim 18+, tiện ích ghi đè được): cửa sổ nhỏ (đang ngang / toàn màn thì xoay về dọc trước) hoặc hub (khung phim bay vào nút hub). Phim nhúng trang luôn vào hub; màn đang hiện bìa chỉ đóng màn. Trước đây Home luôn đóng màn ⇒ hub.
- `VideoPlayerScreen+Exit.minimizeByPolicy`; `minimizeToHub` / `flyToHub` nhận `then` (về Khám phá / gốc tab sau khi màn đã đóng hẳn).
- Phim 18+: Home vẫn tắt NSFW (1.3.769) — guard NSFW xin thu vào hub bị `VideoLeaveToHubCoordinator` bỏ qua trong 2 giây sau Home (`applyLeaveRules(keepsPlacement:)`) để cửa sổ nhỏ vừa mở theo cài đặt không bị kéo vào hub.
- `CLAUDE.md` / `AGENTS.md` mục Comic & Video.
- **Kiểm chứng:** đọc code + diff; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows). Chưa thử trên máy: Home lúc đang ngang với cài đặt cửa sổ nhỏ.

## [1.3.774] - 2026-11-07

### feat: hub che tên phim 18+ thành Đang phát khi NSFW đã tắt

Anh Bửu chọn *"Che thành Đang phát"* cho câu hỏi còn treo của 1.3.769 (NSFW đã tắt mà phim 18+ vẫn chạy ở hub thì dòng Video hiện tên phim thật).

- Dòng Video của hub: phim 18+ (`RepositoryFilterPolicy.isNsfwBook`) lúc công tắc NSFW **tắt** ⇒ dòng chính "Đang phát" (như màn khoá 1.3.764), dòng phụ "Chạm để mở lại" / "Đã dừng" — không lộ tên phim, tên tập. NSFW bật ⇒ hiện tên như cũ.
- `VideoMiniPlayerState.isNsfw` (phiên ghi ở `syncMiniPlayerState`), `FloatingHubPresentationReader` đọc cùng công tắc NSFW đang theo dõi sẵn ⇒ gạt NSFW là dòng đổi ngay.
- **Kiểm chứng:** đọc code + diff; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows). Chưa thử trên máy.

## [1.3.773] - 2026-11-07

### fix: rời app lúc màn xem mở sheet không kẹt màn, chuyển tab đóng cả trang của màn xem, nút Home bám góc màn

Sửa theo review phản biện (2 agent) của đợt 1.3.766–772, trước khi push.

- **Màn xem kẹt khi rời app lúc đang mở sheet** (Thông tin, Tải nhiều tập, chia sẻ…): `host.dismiss` chỉ đóng sheet con, màn xem ở lại với `isLeaving = true` (mọi nút chết, khung phim đen). `VideoWatchPresenter` / `VideoPlayerPresenter` giờ đóng từ VC đã trình bày host (`host.presentingViewController ?? host`).
- **Trang thể loại nằm dưới màn xem mở lại** (bấm Thể loại ⇒ cửa sổ nhỏ ⇒ chạm mở lại màn xem ⇒ "Về Khám phá") còn che tab vừa đổi: `VideoWatchPagePresenter.closeAllPages` đóng mọi trang của màn xem (giữ danh sách yếu `openPages`), `MainTabView` gọi nó trước mỗi lệnh chuyển tab (`showDiscoveryRoot`, `showCurrentTabRoot`).
- **Rời app khi phim chỉ đang ở hub** (không màn xem / cửa sổ nhỏ gắn phiên) không còn tắt NSFW và nhảy Khám phá — chỉ áp khi đang xem (`session.isScreenAttached`).
- Nút Home của trang đè lên màn xem không thu cửa sổ nhỏ của phim khác (`VideoMiniPlayerWindowManager` bỏ qua lý do `.homeButton`).
- **Nút Home tròn bám góc màn**: nội dung trang được kéo giãn trước khi phủ nút (`FloatingHomeButtonModifier`), trước đó trang chỉ có vòng xoay "Đang tải…" (vd tất cả bình luận) đặt nút gần giữa đáy màn.
- Đầu dò Home không đọc được vị trí ⇒ bỏ đăng ký cũ (`FloatingHomeProbe`); bỏ `floatingHomeHostedByPage()` không còn chỗ gọi.
- Sheet "Kiểu hiển thị" của Khám phá chỉ hiện nhóm "Trang Khám phá" khi nguồn có trang `explore`.
- **Kiểm chứng:** đọc code + diff; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows). Chưa thử trên máy.

## [1.3.772] - 2026-11-07

### feat: nút + của Chi tiết theo cấu hình nút nổi, Home nằm trong menu xổ của nút +

Người dùng: *"Cho phép nút home, các nút + (kể cả nút + của detail) hiển thị UI theo config nút nổi (ở cài đặt giao diện)"*.

- Nút "+" nổi của Chi tiết truyện (nút tròn + pill Đọc / Thêm vào kệ / Tải / Xuất) đổi sang **nền kính** theo cấu hình nút nổi ở Cài đặt › Giao diện (độ trong suốt / độ đục), canh lề 16 / 12 như nút "+" chung; "Đã ở kệ" là viền + icon xanh thay cho nền xanh đặc; pill canh phải nên nút không xê dịch khi mở menu.
- Chi tiết đủ điều kiện nút Home (trang đẩy vào trong tab Kệ / Khám phá / Tiện ích, hoặc mở từ màn xem phim): thêm pill "Về trang gốc" dưới cùng menu; chưa có mục lục (đang tải / lỗi) thì còn nút Home tròn ở góc.
- Tách FAB khỏi `BookDetailView` sang `BookDetailFloatingActions` (1177 → 1066 dòng), dùng chung `FloatingActionMenu` với nút "+" của màn danh sách. Các nút "+" nổi khác vốn đã dùng `FloatingGlassBackground`; nút "+" trên header không phải nút nổi nên giữ nguyên.
- **Kiểm chứng:** đọc code + diff; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows). Chưa thử trên máy: chạm trúng pill của menu xổ.

## [1.3.771] - 2026-11-07

### feat: nút Home nổi ở trang con của Kệ, Khám phá và Tiện ích về trang gốc của tab

Người dùng: *"Thêm nút home vào tất cả màn hình trừ reader và xem commic và các màn hình của tab cài đặt."* Anh Bửu chọn: về **trang gốc của tab đang đứng**; nút ở **góc dưới phải**, trang có nút "+" thì Home nằm trong menu xổ của "+", ở **dưới cùng**.

- Trang đẩy vào trong tab Kệ Sách, Khám Phá, Tiện Ích có nút Home tròn nổi góc dưới phải (52pt, nền kính theo Cài đặt › Giao diện, nhãn "Về trang gốc"); bấm ⇒ về trang gốc của tab đang đứng (tab Khám phá dựng lại = tải lại nguồn đang xem). Bàn phím hiện thì ẩn.
- Trang có nút "+" nổi: bấm "+" xổ menu pill (kính) gồm hành động gốc của "+" và "Về trang gốc" ở dưới cùng; trang không có Home thì "+" vẫn bấm một chạm.
- Không hiện ở trang gốc các tab, tab Cài Đặt, Reader / truyện tranh / màn xem phim và mọi trang trong chúng, sheet / form / trình soạn, trình duyệt, hub / widget. Quyết định lúc chạy bằng đầu dò UIKit (`FloatingHomePlacement`, `FloatingHomeProbe`), gắn tự động ở `PageTitleModifier`; nút "+" và tiêu đề ghép theo trang qua `FloatingHomeRegistry` (đúng với mọi thứ tự modifier).
- Trang trình bày bằng UIKit ngoài cây tab bật Home bằng cách cho VC được present conform `FloatingHomeActionProviding`: trang thể loại / Xem thêm / Chi tiết của màn xem phim (`VideoWatchPagePresenter`) — Home đóng trang (trang đè lên màn xem thì màn xem cũng thu vào hub) rồi về trang gốc tab đang đứng.
- Lệnh mới `MainTabNavigationEvents.showCurrentTabRoot`; FAB riêng của Chi tiết tạm giữ chỗ Home (`.floatingHomeHostedByPage()`).
- `CLAUDE.md` / `AGENTS.md` mục quy ước UI.
- **Kiểm chứng:** đọc code + diff; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows). Chưa thử trên máy: bấm pill của menu xổ (vẽ lòi ngoài khung nút 52pt); Home đè góc phải cuối trang con; cửa sổ phim nhỏ / hub / widget TTS đậu góc dưới phải che nút.

## [1.3.770] - 2026-11-07

### feat: rời app thì thu phim vào hub, có công tắc ở Cài đặt Video

Người dùng: *"Khi người dùng đang xem video mà tắt màn hình thì tự động cho video và hub widget (nếu đang ở nfsw thì tắt và chuyển sang nguồn khác không nfsw), video thu vào hub không cần pause đâu (tính năng này có thể config bật tắt)"*. Anh Bửu chọn kích hoạt **khi rời app** (khoá màn hình hoặc về màn hình chính), phim 18+ làm giống nút Home mới (1.3.769).

- Cài đặt › Đọc & Nghe › Video thêm nhóm "Khi rời app" với công tắc "Rời app thì thu phim vào hub" (`VideoLeaveAppPolicy`, khoá `videoCollapseToHubOnLeaveApp`, mặc định **bật**).
- App vào nền (`didEnterBackground`: khoá màn hình, vuốt về màn hình chính — kéo Trung tâm điều khiển không tính) lúc có phim: màn xem đóng **không hiệu ứng**, cửa sổ nhỏ thu vào hub; phim phát tiếp chỉ tiếng, không bao giờ bị dừng vì việc này. Trang đè lên màn xem đóng theo.
- Rồi như nút Home: phim 18+ tắt tiếng theo "Tắt tiếng khi mở phim"; công tắc NSFW đang bật thì tắt rồi về trang gốc Khám phá (sau khi màn xem đã đóng hẳn) ⇒ Khám phá đổi sang nguồn không 18+. NSFW đang tắt thì không chuyển tab. Gọi lặp an toàn; log `🎬` / `🔞` cho từng bước, lỗi có `❌`.
- Màn xem gỡ khỏi phiên ngay khi rời app (không chờ `onDisappear`, có thể bị hoãn ở nền); trình duyệt "Mở link lỗi" / "Trình duyệt" đang che màn thì giữ nguyên màn. Phim nhúng trang cũng bị thu (trang web huỷ, hub hiện "Chạm để mở lại" như nút ⌄).
- `CLAUDE.md` / `AGENTS.md` mục Comic & Video.
- **Kiểm chứng:** đọc code + diff; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows). Chưa thử trên máy: đóng màn xem khi app đã ở nền (lượt chuyển Khám phá chờ `onDisappear`); đang xem ngang mà rời app.

## [1.3.769] - 2026-11-07

### fix: tắt NSFW không còn dừng phim 18+ mà thu vào hub và tắt tiếng theo cài đặt

Người dùng: *"sửa lại hành động đối với video về home của nfsw, video được thu vào hub, tùy theo cài đặt tắt tiếng sẽ tự tắt tiếng hoặc không (các hành động khác giữ nguyên)"*; khi được báo luật 1.3.740 (tắt NSFW ⇒ dừng phim 18+, hub ẩn phim): *"vậy bỏ luật dừng, sửa lại thu vào hub và tắt tiếng theo config"*.

- **Đảo luật 1.3.740**: tắt công tắc NSFW lúc phim 18+ đang phát **không dừng** phim nữa. Phim đang ở màn xem / cửa sổ nhỏ ⇒ thu vào hub và phát tiếp; tắt tiếng nếu "Tắt tiếng khi mở phim" (`VideoMutePolicy`) không phải «Không». Phim đang ở hub sẵn ⇒ chỉ áp tắt tiếng.
- Nút Home của màn xem: phim 18+ không dừng — như phim thường, màn xem thu nhỏ vào hub, phim 18+ tắt tiếng theo cài đặt, công tắc NSFW đang bật thì tắt rồi về trang gốc Khám phá (Khám phá tự đổi sang nguồn không 18+ đầu tiên). Màn rời trước rồi mới tắt NSFW nên lời xin thu của guard NSFW không làm rời màn hai lần, không mất lượt chuyển Khám phá. (Thay ngoại lệ "nút Home dừng phim 18+" còn ghi ở 1.3.765.)
- Hub luôn hiện dòng Video (điều khiển, tắt được) cho phim 18+ đang phát dù NSFW đã tắt; các chỗ ẩn nội dung 18+ khác giữ nguyên. Bỏ `VideoMiniPlayerState.packageId` (chỉ dùng để ẩn dòng này).
- Thêm `VideoLeaveToHubCoordinator` (tầng dịch vụ, không SwiftUI, không toast): màn xem và cửa sổ nhỏ đăng ký nhận lời xin thu vào hub; luật chung của Home (`applyLeaveRules`) dùng được cả khi không có `VideoWatchModel`, `prepareGoHome` gọi lại nó.
- `CLAUDE.md` / `AGENTS.md` mục Comic & Video.
- **Kiểm chứng:** đọc code + diff; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows). Chưa thử trên máy: thứ tự guard NSFW với nút Home; dòng Video ở hub hiện tên thật của phim 18+ khi NSFW đã tắt (màn khoá vẫn che thành "Đang phát").

## [1.3.768] - 2026-11-07

### feat: bấm Thể loại hoặc Xem thêm khi đang xem phim thì phim vào cửa sổ nhỏ

Người dùng: *"KHi đang xem video mà bấm xem thêm suggest hoặc bấm vào genres thì tự động cho video thì pip (nếu làm cái này có xung đột thì báo tôi)"*. Đã báo xung đột: PiP hệ thống bỏ từ 1.3.751 ⇒ "pip" = cửa sổ phim nhỏ trong app; đảo thiết kế 1.3.744 (trang đè lên màn xem, ‹ về màn xem). Anh Bửu duyệt.

- Màn xem phim: bấm nhãn thể loại, thể loại trong sheet Thông tin hoặc "Xem thêm ›" của nhóm đề xuất lúc màn đang phát phim của nó (không phải phim nhúng trang) ⇒ khung phim co vào **cửa sổ nhỏ** trong app (đang ngang / toàn màn thì xoay về dọc trước), màn xem đóng rồi mới mở trang danh sách. Chạm cửa sổ nhỏ để mở lại màn xem (nằm trên trang, đóng màn là về trang).
- Màn đang hiện bìa (phim khác chạy nền) hoặc phim nhúng trang: giữ kiểu cũ — trang đè lên màn xem, chọn phim thì đổi tại chỗ. Chi tiết của đề xuất không phải phim giữ nguyên.
- Trang mở sau khi màn xem đóng: chọn một phim ⇒ đóng trang rồi mở màn xem mới theo lối thường; truyện chữ / tranh vẫn đẩy Chi tiết trong trang. Nút ‹ đọc "Quay lại" (trang đè lên màn xem vẫn là "Quay lại màn xem phim").
- Ba lối đi chung `VideoWatchExit.openCategory`; `VideoWatchPagePresenter` chỉ coi là "đang che màn xem" trang mở đè lên màn (nút âm lượng cứng, đóng màn xem không đụng trang nằm dưới), nút ‹ và lượt chọn phim đóng đúng trang của mình. Lối rời màn tách sang `VideoPlayerScreen+Exit`.
- **Kiểm chứng:** đọc code + diff; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows). Chưa thử trên máy: thứ tự co vào cửa sổ nhỏ → đóng màn → mở trang; khoá máy đúng lúc khung phim đang co.

## [1.3.767] - 2026-11-07

### feat: chỉnh cỡ hiển thị từng bố cục của trang Khám phá

Người dùng: *"thêm size hiển thị của các layout của explore"*. Anh Bửu duyệt plan: mỗi bố cục một mức "Cỡ" 7 nấc, lưu theo loại nguồn.

- Trang Khám phá (`explore`) có mức **"Cỡ" 7 nấc** cho từng bố cục, nấc 4 = mặc định = hiển thị y như trước: **Lưới** (nấc to bớt cột, nhỏ thêm cột: số cột gốc theo hình thẻ − (nấc − 4), kẹp 1…6), **Hàng ngang** (bề rộng thẻ ×0,7…1,5), **Danh sách & Xếp hạng** chung một mức (ảnh nhỏ ×0,7…1,5, chữ tên/mô tả phóng như "Cỡ dòng"), **Banner** (tỉ lệ 2,4:1 … 16:9 … 1,3:1). Hàng chip không có mức cỡ.
- Lưu theo loại nguồn truyện chữ / truyện tranh / video (`ExploreLayoutSizePreferences`, khoá `exploreLayoutSize_<bố cục>_<loại>`, tự vào bản sao lưu); truyền xuống các section qua `ExploreRenderContext`.
- Chỉnh ở sheet "Kiểu hiển thị" mở từ Khám phá (thêm nhóm "Trang Khám phá", sheet cao nửa màn, kéo lên được, cuộn được) và Cài đặt › Giao diện › Kiểu hiển thị (mỗi loại chữ/tranh/video thêm nhóm "<loại> · Trang Khám phá"); "Đặt lại mặc định" đặt lại cả cỡ Khám phá. Sheet của Kệ / Thể loại / Bộ sưu tập / Tìm giữ nguyên.
- Thanh trượt nấc dùng chung `LayoutLevelSlider` (cả "Cỡ dòng" của kiểu Danh sách).
- Vài nấc trùng kết quả do kẹp 1…6 cột: lưới phim ngang ra 1 cột ở nấc 5–7, lưới tròn ra 6 cột ở nấc 1–2.
- **Kiểm chứng:** đọc code + diff; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows). Chưa thử trên máy: kéo thanh trượt trong vùng cuộn của sheet nửa màn.

## [1.3.766] - 2026-11-07

### feat: kiểu Lưới và Chỉ bìa chọn được 1 cột

Người dùng: *"Cho kiểu hiển thị lưới và chỉ bìa hiển thị được số cột là 1 luôn"*.

- Bước "Số cột" của kiểu Lưới / Chỉ bìa (sheet Kiểu hiển thị và Cài đặt › Giao diện › Kiểu hiển thị) chọn được **1…5** cột (trước 2…5; `BookListLayoutPreferences.columnRange`). 1 cột = bìa tràn bề ngang, truyện chữ/tranh đứng 2:3, video ngang 16:9.
- Đã rà các lưới dùng số cột (Kệ / Lịch sử / Bộ sưu tập, Khám phá, Thể loại / Xem thêm, Tìm trong một nguồn, khung chờ lưới): không chỗ nào ngầm đòi từ 2 cột; ảnh bìa tải theo cỡ khung nên không mờ.
- **Kiểm chứng:** đọc code + diff; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows). Chưa thử trên máy.

## [1.3.765] - 2026-11-07

### feat: kéo cửa sổ phim nhỏ lên nút hub để thu vào hub, vuốt xuống theo tay, không nhớ vị trí, thu nhỏ không dừng phim

Người dùng: *"thêm hành động chuyển pip vào hub"*, *"khi vuốt pip hãy xuống dưới theo tay như youtube, đừng nhớ vị trí pip trước đó"*, *"bị nút thu nhỏ đừng pause"*. Anh Bửu duyệt mockup + plan gộp, chọn: kéo thả lên nút hub (không thêm nút, không hất ra mép); vào hub thì phim chạy tiếp chỉ tiếng; chỗ đậu mặc định góc dưới phải; giữ ngoại lệ nút Home dừng phim 18+.

- **Kéo vào hub** (`VideoMiniPlayerViewController`): kéo tới gần nút hub (tâm cửa sổ cách tâm nút < 60 pt, `VideoMiniPlayerLayout.isOverHub`) ⇒ nút hub phóng to + viền màu nhấn (`FloatingHubWindowManager.setDropTargetHighlighted`), máy rung nhẹ, cửa sổ mờ. Thả ⇒ cửa sổ co nhỏ bay vào nút hub (`shrinkAway`, dùng chung với vòng ✕), `VideoMiniPlayerWindowManager.minimizeToHub` ẩn cửa sổ + gỡ khỏi phiên (phiên tự tách hình, lưu tiến độ, hiện dòng Video ở hub) rồi hub nháy. Cửa sổ đậu mép phải ngang hub không tự lọt (tâm cách ~100 pt).
- **Vuốt theo tay** (`VideoMinimizeDragState.travel`): quãng kéo = khoảng dọc từ mép trên khung phim (mép trên vùng an toàn) tới mép trên chỗ đậu, thay hằng 420 pt ⇒ mép trên khung phim đi đúng theo ngón tay, khung co dần và dịch về mép phải.
- **Không nhớ vị trí** (`VideoMiniPlayerLayout`): mỗi lần thu nhỏ đậu góc dưới phải ngay trên thanh tab; kéo bám mép trong lúc hiện không ghi lại. Khoá `videoMiniPlayerDock` thôi đọc/ghi (giá trị cũ còn trên máy, vô hại).
- **Thu nhỏ không dừng phim**: code không có chỗ nào dừng phim khi bấm ⌄ / vuốt (đã kiểm: chỉ tách hình + hạ chất lượng HLS). Thêm lớp giữ phát: `VideoPlayerScreen.leave` (thu nhỏ) và kéo vào hub gọi `noteMinimizing()` chụp "đang phát" **trước** khi màn đóng; màn cuối rời phiên (`detachScreen`) mà player bị dừng ⇒ phát tiếp ngay và kiểm lại sau 1,5 giây, log `⏯️ Thu nhỏ: phim bị dừng … ⇒ phát tiếp` để biết nguyên nhân thật. Người dùng bấm dừng (`pause()`) xoá mốc; TTS đang đọc mà phim có tiếng / phim đã nhường TTS / hết phim ⇒ không phát tiếp. Ngoại lệ giữ nguyên: nút Home khi xem phim 18+ dừng hẳn + tắt NSFW; phim nhúng trang thu nhỏ vẫn im (trang web huỷ cùng màn).
- Câu hướng dẫn Cài đặt › Video; `CLAUDE.md` / `AGENTS.md` mục Comic & Video.
- **Kiểm chứng:** đọc code + diff; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows). Chưa thử trên máy: kéo trúng hub đang nép mép; độ mượt khi vuốt theo tay; lớp giữ phát có phải chạy không (xem log).

## [1.3.764] - 2026-11-06

### feat: màn khoá khi phát phim hiện tên phim, tác giả và bìa, phim 18+ chỉ hiện Đang phát với icon app

Người dùng: *"custom hiển thị ở màn hình lock luôn giúp tôi, dùng cover của video, đối với nfsw thì đừng dùng. Hiển thị tên video và tác giả"*. Anh Bửu duyệt mockup + plan, chọn: dòng phụ "Tác giả · Tập N"; thiếu tác giả thì bỏ phần tác giả; phim 18+ dùng icon app và chỉ **một** dòng "Đang phát" (bỏ chữ "Ẩn danh").

- **Hiển thị** (`VideoNowPlayingMetadata`): phim thường = tiêu đề tên phim, dòng phụ "Tác giả · Tập N" (tên tập chỉ khi phim có từ 2 tập phát được; thiếu tác giả ⇒ chỉ tên tập; phim một tập không tác giả ⇒ không dòng phụ), ảnh = bìa phim. Phim 18+ (`RepositoryFilterPolicy.isNsfwBook`, cùng luật tắt tiếng / thu nhỏ, xét lại mỗi lần ghi) = "Đang phát", không dòng phụ, không tên tập, ảnh = icon app. Không ghi Album nữa (trước: tiêu đề = tên tập, Album/Artist = tên phim, không ảnh).
- **Bìa** (`VideoPlaybackSession+NowPlaying`, `publishNowPlaying` dời từ `+Transport`): nạp một lần mỗi phim lúc `open` — bìa trên máy (`covers/`, đọc ngoài main) → chưa có thì `ImageCacheManager.downloadAndSaveCover` rồi ghi lại màn khoá; phim 18+ không đọc, không tải. Tác giả lấy từ lượt mở, trống thì từ `Book` (màn xem điền khi chi tiết về muộn).
- **Icon app**: `LockScreenAppIcon.imageset` (bản 512 px của icon) — không đọc icon app lúc chạy (không chắc chắn trong LiveContainer).
- `VideoNowPlayingCoordinator.publish` / `publishLoading` nhận `metadata`; `MPMediaItemArtwork` dựng ở hàm `nonisolated` (closure trả ảnh bị hệ thống gọi ngoài main), cùng ảnh thì dùng lại.
- **Kiểm chứng:** đọc code + diff; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows). Chưa thử trên máy: ảnh có hiện trên màn khoá với loại media video không; bìa tải chậm có cập nhật lên sau không.

## [1.3.763] - 2026-11-06

### feat: màn xem phim có nút Trình duyệt mở link chi tiết của phim, kể cả khi không lỗi

Người dùng: *"thêm nút mở link chi tiết trên browser kể cả lỗi hay không"*. Chốt (bảng chọn): chỉ màn xem phim; viên thuốc ở hàng nút; đóng trình duyệt thì chép cookie, không tải lại; tách riêng với "Mở link lỗi" — *"nút này mở link chi tiết chớ không phải link tập"*.

- **Vì sao chỉ phim**: Chi tiết truyện (ngăn kéo `…`), Reader chữ (ngăn kéo) và sheet nhấn giữ ở Kệ đã có "Mở bằng trình duyệt" luôn hiện; phim mất lối này từ 1.3.747 (thôi mở trang Chi tiết), chỉ còn "Mở link lỗi" khi lỗi.
- **Nút**: `VideoWatchActionRow` thêm viên thuốc **"Trình duyệt"** (icon `safari` như `ErrorLinkButton`) sau Chia sẻ. Link = `VideoWatchModel.detailPageLink` (file `+Actions`): `request.detailUrl` của **phim** đang hiện trên màn (không phải link tập; tự sang phim đề xuất ⇒ đổi theo) chuẩn hoá như URL đầu vào của "Mở link lỗi" (`SourceErrorLink.resolve(from: nil, fallbacks:host:)` — bỏ khối option Legado, ghép host cho `/…`), lùi về `shareURL`. Phim nhập từ file / không có link http(s) ⇒ ẩn nút.
- **Trình duyệt**: `.sourcePageBrowser(link:packageId:)` (mới, `ErrorLinkBrowserModifier.swift`) = cùng modifier với `.errorLinkBrowser` nhưng `onRetry == nil`: `BypassWebView` chế độ điện thoại, đóng lại chỉ chép cookie WebKit của host sang `fetch` (+ kho cookie nguồn Legado) — không toast "Đang thử lại…", không thử lại, phim đang phát không bị đụng.
- **Màn không bị gỡ khi trình duyệt che**: `VideoPlayerScreen` giữ `openingDetailPage` (truyền xuống `VideoWatchDetailsView` → `VideoWatchActionRow`) và thêm nó vào chốt `onDisappear` cạnh hai link lỗi ⇒ không thu nhỏ phim vào hub, không trả khoá xoay, `onAppear` lúc quay lại bỏ qua (`isCoveredByErrorBrowser`).
- **Giới hạn đã biết** (chung với "Mở link lỗi"): lúc trình duyệt đang che, nút âm lượng cứng vẫn có thể hiện thanh âm lượng của phim ở màn bên dưới.
- **Kiểm chứng**: `check_architecture.py` chỉ còn 1 lỗi có sẵn (`JSDom.swift` vượt baseline); chưa build (máy Windows), chưa thử trên máy.

## [1.3.762] - 2026-11-06

### feat: dọn bìa truyện mồ côi, thu nhỏ bìa khi lưu và lịch tự dọn dung lượng

Người dùng: *"nên có dọn dẹp bìa truyện, hiện tại bìa truyện lên tới 1.01 GB"* (màn Dung lượng), rồi *"đặt thời gian dọn dọn như kiểu thời gian tự backup vậy, có config nhé"*. Chốt: nút Dọn chỉ xoá bìa mồ côi; thu nhỏ bìa mới + bìa cũ về 1024 px; không giới hạn dung lượng; lịch tự dọn áp cho mọi mục dọn được (công tắc riêng), mặc định bật chỉ bìa, mỗi ngày sau 03:00, lối vào ở đầu màn Dung lượng.

- **Nguyên nhân (đọc code, chưa đo trên máy)**: trang Chi tiết của truyện chưa lưu dùng `bookId` ngẫu nhiên mỗi lần mở (`BookDetailView.resolveBookId`, có từ 2026-07-20), mà bìa lớn + nền mờ (`BookDetailHeroView` → `BookCoverView`) ghi `covers/<sha256(id)>.jpg` ⇒ mỗi lần xem một truyện chưa lưu là một file không `Book` nào giữ, không bao giờ bị xoá. Thêm nữa `storeDownloadedCover` ghi bìa **nguyên cỡ**; `saveCover` "thu nhỏ 1024" nhưng `UIGraphicsImageRenderer` mặc định nhân scale màn hình ⇒ thực tế tới 3072 px.
- **Chặn từ gốc**: `BookCoverView(persistsCover:)` — `false` ⇒ tải qua `ImageCacheManager.fetchTransientCoverData` (gộp lượt trùng bìa lớn/nền mờ, giữ byte vài trang gần nhất trong `NSCache` 8 mục / 8 MB), giải mã thẳng ra thumbnail đúng cỡ khung (`CoverThumbnailCache.makeThumbnail(data:)`), **không** ghi `covers/`, **không** vào cache thumbnail dùng chung. `BookDetailView` truyền `localBook != nil` qua `BookDetailHeaderView` → `BookDetailHeroView`; truyện vừa được lưu ngay trên trang (thêm kệ, đọc, tải) ⇒ `.task` chạy lại, tải + ghi file như cũ (EPUB vẫn có bìa). Đang hiện bìa chỉ RAM thì không nháy placeholder khi chuyển sang lưu.
- **Thu nhỏ khi lưu**: `CoverImageEncoder` (file mới, ImageIO `CGImageSourceCreateThumbnailAtIndex`): cạnh dài ≤ 1024 **pixel thật**, JPEG 0.8, xoay theo EXIF, không giữ ảnh nguyên cỡ trong RAM. Dùng cho bìa tải về (`storeDownloadedCover`) và bìa tự chọn / nhập file (`saveCover`, bỏ `downscaled`). Tách bước tải thành `fetchCoverBytes` (Referer + UA + `coverDecodeJs` của Legado) dùng chung cho đường ghi đĩa và đường chỉ RAM.
- **Quét + dọn `covers/`** (`ImageCacheManager+Maintenance`, file mới; `coversDirectory`, `fileManager`, `validatePathSafety`, `sha256Hex`, `getNewFileName`, `getLegacyFileName` từ `private` thành `internal` cho file này): file **có chủ** khi trùng `sha256(bookId).jpg` hoặc tên kiểu cũ của một `Book` bất kỳ (kể cả truyện ẩn — không ở Kệ/Lịch sử). File ghi / chuyển vào chưa quá 10 phút (lấy lớn nhất của ngày sửa, ngày đổi thuộc tính, ngày tạo) không bị coi là mồ côi. `scanCoverFolder` đếm trước (`CoverFolderScan`, file mới); `removeOrphanCovers` kiểm lại chủ + tuổi từng file trước khi xoá; `shrinkOversizedCovers` ghi lại bản ≤ 1024 px cho bìa có chủ quá cỡ (chỉ khi nhỏ hơn) rồi `invalidateCover`. Mọi thao tác file qua `validatePathSafety`.
- **`CoverCleanupCoordinator`** (`Services/Cleanup/`, file mới): đọc mọi `Book.bookId` trên `ModelContext` riêng ngoài main (`propertiesToFetch`); fetch lỗi ⇒ **không dọn gì**. `preview` / `run` (đọc lại thư viện ngay trước khi xoá) / `runUnattended`; cờ `isRunning` chặn hai lượt chồng nhau.
- **Màn Dung lượng**: hàng "Bìa truyện" có nút **Dọn** (`StorageUsageCategory.isTrimmable`, không gắn `isClearable`): vòng xoay lúc đếm ⇒ hộp xác nhận "N bìa không còn truyện nào · X MB" + "M bìa đang dùng lớn quá cỡ (Y MB) sẽ thu nhỏ" ⇒ dọn, đo lại, toast "Đã dọn bìa truyện (Z)". Không có gì ⇒ "Bìa truyện đã gọn"; đang sao lưu/khôi phục ⇒ báo dọn sau. Hàng **Tự động dọn** (`StorageAutoCleanupRow`, file mới) đầu danh sách ghi nhịp đang đặt.
- **Lịch tự dọn**: `StorageAutoCleanupPolicy` (file mới, khuôn `DriveAutoBackupPolicy`: bật/tắt mặc định bật, "Mỗi ngày một lần" sau 03:00 hoặc "Theo chu kỳ" 6–168 giờ, mục được dọn mặc định chỉ bìa, `lastRunAt` + `lastFreedBytes`); `StorageAutoCleanupCoordinator` (file mới): `runIfDue` gọi từ `MainTabView` lúc mở app — hoãn 45 s, chờ `BackupCoordinator.isBusy` xong (bìa vừa khôi phục chưa có `Book`), đánh dấu kỳ lúc bắt đầu; bìa ⇒ `CoverCleanupCoordinator.runUnattended` (mồ côi + thu nhỏ), cache ảnh truyện tranh / file xuất / nhật ký / báo cáo kiểm tra ⇒ `StorageUsageCleaner.clear`; đo dung lượng trước/sau bằng `StorageUsageScanner`; chạy im lặng, chỉ log `🧹 [StorageAutoCleanup]`. Màn `StorageAutoCleanupSettingsView` (file mới, Cài đặt › Thư Viện › Dung lượng › Tự động dọn): công tắc, nhịp chạy, công tắc từng mục (nút "?" giải thích, nhắc log là kênh tìm lỗi), trạng thái + "Dọn ngay theo các mục đã bật" có xác nhận.
- **Phụ hiệu ứng**: dọn bìa làm đổi `BackupLibraryFingerprint` (băm cả file bìa) ⇒ tự sao lưu có thể chạy thêm một lượt. Bìa của truyện chưa lưu mở lại thì tải lại qua mạng (như trước — mỗi lần mở vốn đã ra id mới).
- **Kiểm chứng**: `check_architecture.py` chỉ còn 1 lỗi có sẵn (`JSDom.swift` vượt baseline); chưa build (máy Windows), chưa thử trên máy.

## [1.3.761] - 2026-11-06

### feat: rule dịch viết hoa tên token chữ thì viết hoa phần nghĩa

Người dùng: *"token chữ của rule dịch, thêm viết hoa phần nghĩa"*; chốt: *"token gốc viết hoa thì cũng viết hoa ví dụ vp thì như thường, VP thì ép viết hoa"*, mọi token chữ trừ `<any>`, chỉ kiểu AA.

- **Cú pháp**: viết HOA cả tên token chữ `<NE> <PN> <VP> <W> <HV> <HN> <M> <A>` ⇒ nghĩa ép kiểu AA của `TextCaseFormatter` (hoa chữ đầu mọi từ, phần còn lại thành thường): `<VP>宗 = {0} Tông` trên `天剑宗` ra `Thiên Kiếm Tông`. Vẫn kèm độ dài, `?` và `|` (`<VP:1-4>`, `<NE|PN>?`). Trộn hoa thường trong một token (`<NE|pn>`) ⇒ `UNKNOWN_TOKEN_NAME` kèm câu giải thích. `<N> <Y> <H> <D> <ANY>` vẫn là lỗi như trước (chữ số / chữ Hán nguyên văn không có hoa thường); `<L>` vốn đã ra nhãn viết hoa.
- **`QuickTranslationRuleParser+TitleCase`** (file mới): `normalizedTokenNames` hạ tên về thường ngay khi tách + trả cờ; `parseToken` gắn `capitalizesMeaning` lên `QuickTranslationRuleElement` của token số/ký tự và từ điển. Mọi chỗ phía sau (công tắc token, cấu hình riêng truyện, độ hẹp token số, `<m>` đầu mẫu) thấy token thường ⇒ `<VP>` theo công tắc VietPhrase như `<vp>`.
- **`QuickTranslationRuleElement.renderedMeaning`**: chỗ duy nhất áp chữ hoa, matcher gọi trong `store`. Các bước sau rule không hạ thường lại và span dò bản dịch không phân biệt hoa thường. Không thêm cấu hình runtime ⇒ khoá cache không đổi (sửa file rule đã làm generation đổi).
- **Màn sửa rule**: thanh chỉnh token đang chọn có nút **"AA hoa nghĩa"** cạnh "? vắng mặt được" (chỉ token chữ) — bấm là viết lại tên token hoa/thường (`TokenSpec.isTitleCase` / `supportsTitleCase` / `setTitleCase`). Thanh độ dài coi `<HV>`/`<M>` như `<hv>`/`<m>` (không có độ dài).
- **Hướng dẫn** (`QuickTranslationRuleGuide`): mục mới "Viết hoa nghĩa"; dòng `<a>` thêm `<A>`; lỗi `UNKNOWN_TOKEN_NAME` thêm ví dụ `<Vp>`, `<NE|pn>`. Popover "Mẫu" nhắc nút AA.
- `CLAUDE.md` + `AGENTS.md` (mục Dịch thuật VietPhrase) + `rules.md` (luật chỉ viết hoa ở `renderedMeaning`).
- Hệ quả: `<vp>宗` và `<VP>宗` là hai mẫu khác nhau (mẫu là định danh rule) — đổi trên rule đã có thì Lưu hỏi Thay rule cũ / Lưu thêm; bản app cũ đọc `<VP>` báo lỗi và bỏ dòng.
- Chuyển entry cũ nhất sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng:**
  - Đọc code + diff; grep mọi chỗ dựng `QuickTranslationRuleElement(` và gọi `store(` trong matcher.
  - `check_architecture.py` chỉ còn lỗi nền (`JSDom.swift`), **0 mới**.
  - Không build tại chỗ (Windows). Chưa thử trên máy: rule `<VP>`, `<NE|PN>?`, nút AA ở thanh chỉnh token.

## [1.3.760] - 2026-11-06

### fix: kiểm tra bản mới đọc nguồn qua API GitHub, không còn trễ tới 5 phút sau khi CI đăng

Người dùng: *"tôi bấm kiểm tra ver trên app không được nhưng trên livecontainer lại đúng"* — app 1.3.754 (1169) báo "Đang dùng bản mới nhất" dù `apps.json` đã có 1.3.757 (1170).

- **Nguyên nhân**: `raw.githubusercontent.com` đi qua CDN (`Cache-Control: max-age=300`), mỗi máy chủ đệm giữ bản sao tới 5 phút. CI đăng 1.3.757 lúc 08:02:57 UTC; trong 5 phút sau đó máy chủ còn bản cũ vẫn trả danh sách có 1.3.754 đứng đầu ⇒ so build 1169 với 1169 ⇒ "mới nhất". Đã thử: thêm tham số vào link (`?t=…`) CDN vẫn trả bản đệm. So build không sai.
- **`AppUpdateSourceClient`**: đọc `https://api.github.com/repos/buudvh/FreeBook/contents/apps.json?ref=source` trước, header `Accept: application/vnd.github.raw+json` (API trả thẳng nội dung file, cùng định dạng ⇒ giữ bộ giải mã cũ) + `User-Agent`. API đệm tối đa 60 s.
- API lỗi (hết 60 lượt/giờ mỗi IP: 403/429, mạng, file hỏng) ⇒ log `⚠️ [AppUpdate]` rồi đọc link raw như trước. Huỷ thì không lùi.
- LiveContainer vẫn đọc link raw theo cách của nó (không đổi).
- `CLAUDE.md` + `AGENTS.md`: ghi đường đọc mới ở mục "Báo có bản mới trong app".
- Chuyển entry cũ nhất sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng:**
  - Gọi thử API bằng curl: trả 1.3.757 (1170), `Content-Type: application/vnd.github.raw+json`, `X-RateLimit-Limit: 60`.
  - Đọc code + diff; `check_architecture.py` chỉ còn lỗi nền (`JSDom.swift`), **0 mới**.
  - Không build tại chỗ (Windows). Chưa thử trên máy: bấm "Phiên bản ứng dụng" ngay sau khi CI đăng bản mới.

## [1.3.759] - 2026-11-06

### feat: trang Báo cáo kiểm tra cho tiện ích JS và nguồn Legado, tự giữ 20 báo cáo mới nhất

Anh Bửu: *"nên có trang quản lý các report của js và legado. tôi thôi legado reports hoàn toàn không được dọn dẹp"*. Đã chọn: lưu cả báo cáo JS, giữ 20 bản mới nhất mỗi loại, áp luật cho đống Legado cũ lúc mở app, thêm vào màn Dung lượng (xoá được), lối vào ở ngăn kéo … tab Tiện Ích. Anh duyệt plan.

- **Nguyên nhân:** `LegadoCorpusRunner` ghi mỗi lượt kiểm tra (menu ⋯, từng nguồn ở màn chi tiết, Debug server) một file `legado_reports/<yyyyMMdd-HHmmss>.json` kèm kết quả từng nguồn (~1 KB/nguồn, ước tính). `LegadoCorpusReportStore` chỉ có `write`, không ai xoá hay đọc lại. Thư mục cũng không có trong `StorageUsageCategory` nên bị tính vào "Khác". Còn báo cáo JS (`ExtensionCheckRunner`) chỉ nằm trong RAM.
- **`CheckReportStore`** (`Services/Extensions/Diagnostics/Reports/`) là chủ duy nhất của hai thư mục `legado_reports/` (giữ tên cũ, không chuyển dữ liệu) và `extension_check_reports/` (mới). Nó lo ghi, liệt kê, đọc, xoá và tự dọn:
  - Giữ `retainedCount` = 20 bản mới nhất mỗi loại. Dọn sau mỗi lần ghi và một lần lúc mở app (`MainTabView`, `Task.detached`).
  - Lượt đang chạy (`markActive` / `markInactive`, sổ trong RAM) không bị xoá, kẻo checkpoint 50 nguồn ghi lại file vừa xoá.
  - Có `validatePathSafety` riêng; chỉ đụng file `.json`.
  - `LegadoCorpusReportStore` thành lớp mỏng gọi sang store này.
- **Báo cáo JS được lưu:** `ExtensionCheckReport` + `ExtensionCheckVerdict` chuyển `Codable`. `errorLink` vẫn không vào JSON, nên báo cáo đọc lại không có nút "Mở link lỗi". Runner ghi khi xong hoặc dừng; "Chạy lại" ghi đè cùng file; dừng trước khi có kết quả thì không ghi.
- **Tên báo cáo:** thêm trường tuỳ chọn `title` vào `LegadoCorpusReport` và `ExtensionCheckReport`. Hai màn kiểm tra truyền `scopeTitle` qua `start(…, title:)`. Bản cũ và lượt từ Debug server không có tên ⇒ hiện "N nguồn".
- **`CheckReportRepository`** (`@MainActor @Observable`) + `CheckReportCatalog` lo phần đọc. Tóm tắt Legado chỉ giải mã các trường đầu, không dựng mảng `sources`. `reload()` dọn theo luật trước khi đọc. View không đụng đĩa.
- **Trang Báo cáo kiểm tra** (`Views/Extensions/CheckReports/`) mở từ hàng "Báo cáo kiểm tra" ở ngăn kéo … của tab JS (mở sẵn loại JS) và tab Legado (mở sẵn loại Legado):
  - Hai chip chọn loại. Hàng panel gồm tên + nhãn (Đang chạy / Dở · app đã thoát / Đã dừng / File hỏng), dòng giờ · số đếm · dung lượng, và [Chia sẻ][Xoá].
  - Ngăn kéo … có "Xoá hết" cho từng loại, hỏi xác nhận, chừa lượt đang chạy. Kéo xuống để làm mới.
  - Màn chi tiết chỉ để xem, header có [Chia sẻ][Xoá]:
    - Legado: dùng lại ô đếm, `LegadoSourceCheckVerdictPanel`, `LegadoSourceCheckRow`. Nút 🐞 chỉ hiện khi nguồn còn cài (`onDebug` thành tuỳ chọn).
    - JS: dùng lại `ExtensionCheckBatchRow` → `ExtensionCheckDetailContent`.
    - Không chạy lại, không có nút Tắt/Xoá nguồn lỗi.
- **Dung lượng:** thêm loại `checkReports` "Báo cáo kiểm tra", xoá được, đo cả hai thư mục. `StorageUsageCleaner` gọi `CheckReportRepository.deleteAll`.
- `CLAUDE.md` / `AGENTS.md`: thêm hai thư mục vào danh sách lưu trữ, cập nhật danh sách xoá được ở màn Dung lượng, thêm đoạn "Báo cáo kiểm tra lưu trên máy".
- Chuyển `[1.3.729]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng:**
  - Grep: chỉ `CheckReportStore` đụng hai thư mục; mọi lời gọi `start(` của hai bộ chạy đã xem lại.
  - `check_architecture.py`: 1 violation nền (`JSDom.swift`), **0 mới**.
  - Không build tại chỗ (Windows). Chưa thử trên máy: lần mở app đầu dọn còn 20 báo cáo Legado; kiểm tra JS xong có file mới; xoá/xoá hết/chia sẻ; hàng mới ở màn Dung lượng.

## [1.3.758] - 2026-11-06

### refactor: bỏ code chết standardEntrypoint và extensionRootURL của trình sửa script

Anh Bửu: *"Xoá đi"*. Đây là hai hàm Javis báo là không còn ai gọi, sau đợt gói tiện ích một file (1.3.755–757).

- `ExtensionScriptEditorView+Toolbars`: xoá `standardEntrypoint(for:)` (đoán script đang mở ứng với `search`/`detail`/`toc`/`chap`/`genre`/`home`) và `extensionRootURL`. Cả hai đều `private` và chỉ gọi lẫn nhau; grep toàn `Sources/` không còn tham chiếu. `packagePath` vẫn được trình sửa dùng, giữ nguyên.
- Chuyển `[1.3.728]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng:**
  - Grep `standardEntrypoint|extensionRootURL` toàn `Sources/`: 0 kết quả.
  - `check_architecture.py`: 1 violation nền (`JSDom.swift`), **0 mới**.
  - Không build tại chỗ (Windows). Hành vi không đổi.

## [1.3.757] - 2026-11-06

### feat: màn Dung lượng tách hàng Tiện ích JS và Nguồn Legado

Anh Bửu chọn "Tách 2 hàng" khi phỏng vấn về bố cục `extensions/js` + `extensions/legado`; duyệt plan, đây là bước 3.

- `StorageUsageCategory`:
  - **`.extensions`** giữ rawValue (bản đo đã lưu vẫn đọc được), đổi nhãn thành **"Tiện ích JS"**, đo `extensions/js/` + `extension_store/`.
  - Thêm **`.legadoSources`** "Nguồn Legado", đo `extensions/legado/` + `legado_state/` (trước đây `legado_state/` rơi vào "Khác").
- Thư mục cũ còn sót ở gốc `extensions/` (chờ dọn trên nền, hoặc bản ghi chuyển lỗi) tạm tính vào "Khác". Trước khi dọn, file Legado hard link có thể bị đếm hai lần (ở "Nguồn Legado" và "Khác").
- Chuyển `[1.3.727]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng:**
  - Đọc code: `StorageUsageCleaner` dùng `default` nên không phải sửa; màn hình liệt kê theo `allCases`.
  - `check_architecture.py`: 1 violation nền (`JSDom.swift`), **0 mới**.
  - Không build tại chỗ (Windows). Chưa thử trên máy: màn Dung lượng có hai hàng mới, tổng vẫn khớp.

## [1.3.756] - 2026-11-06

### feat: mỗi tiện ích JS và mỗi nguồn Legado là một file JSON trong extensions/js và extensions/legado

Người dùng: *"chia folder extension ra 2 sub folder cho legado và js"*, *"ý tôi là mỗi tiện ích js là 1 json ấy"*. Đã chốt qua phỏng vấn: nguồn Legado cũng một file, icon nhúng base64, tự chuyển khi mở app, xoá ngay thư mục cũ, bỏ `common/`. Anh Bửu duyệt plan; đây là bước 2.

- **Bố cục mới** dưới `applicationSupport/extensions/`:
  - `js/<packageId>.json` = `ExtensionPackageBundle`: `plugin.json` nguyên văn, mọi `*.js` theo đường dẫn tương đối, `icon.png` base64. Gom **lúc cài**; kho ngoài vẫn phát zip.
  - `legado/<packageId>.json` = nguyên văn `source.json`, không còn `plugin.json` tự sinh. `version` nằm ở bản ghi, cờ 18+ đi trong `UpsertExtensionCommand.declaredNsfw`; coordinator không đọc manifest Legado.
- **`ExtensionPackageWriter`** (mới) là cửa ghi duy nhất của gói JS:
  - Gom thư mục: đổi bytes sang chữ bằng `TextEncodingDecoder` (như `JSExecutor.decodeData`); không giải được thì ném lỗi, không gom thiếu.
  - Ghi nguyên tử, mọi lần ghi (cài, cài nháp, trình sửa script, sửa metadata, khôi phục) đi qua một hàng đợi tuần tự.
- **`ExtensionFolderLocator`** nhận file gói, có `jsRoot`/`legadoRoot`/`jsPackageURL`/`legadoPackageURL`/`packagePath(packageId:)`; dự phòng theo `packageId` thử file mới trước thư mục cũ. `packageId` không làm được tên file ⇒ báo lỗi. **`ExtensionInstallAudit`** dùng `ExtensionPackageReader.isPresent`.
- **`ExtensionPackageLayoutMigrator`** (mới), gọi trong `FreeBookApp.init` giữa `LegacyExtensionSQLiteMigrator` và `ExtensionLibraryRepository.load()`. Không có cờ hoàn tất, xét từng bản ghi:
  1. Thư mục cũ trùng tên gốc mới (`js`, `legado`) ⇒ đổi sang `<tên>.legacy` và ghi `installed.json` ngay.
  2. JS gom thành `js/<id>.json`; Legado **hard link** `source.json` sang `legado/<id>.json` (lỗi thì chép, đích có sẵn thì xoá trước). Không parse nguồn Legado lúc khởi động.
  3. Ghi `installed.json` một lần.
  4. Sau `load()`, quét một cấp `extensions/` trên luồng nền và xoá thư mục cũ không bản ghi nào trỏ tới (kể cả `common/`). Chỉ quét khi đọc được `installed.json` và không còn bản cách ly `installed.json.corrupt-*`.

  Chết ở bước nào cũng chạy lại được; bản ghi chuyển lỗi giữ dạng thư mục và vẫn chạy nhờ bộ đọc ba dạng, log `❌ [ExtLayout]`.
- **Legado:**
  - `LegadoSourceStore` đọc, ghi, vá `enabled`/nhóm, xoá trên file (vẫn đọc được thư mục cũ); `makeCommand` mang cờ 18+.
  - `LegadoSourceNsfwBackfill` bị xoá, thay bằng bước sửa cờ trong `LegadoSourceRepository.readAllSummaries`: cờ bản ghi lệch nội dung nguồn ⇒ upsert lại.
  - Importer tính `version` theo bản ghi; Coordinator, Exporter, `TranslationConfigStore` theo vị trí gói của bản ghi.
- **Cài:**
  - `ExtensionPackageInstaller.install(archive:packageId:)` dựng, giải mã rồi gom ở thư mục tạm, trả file gói.
  - `ExtensionDraftInstaller`: cài nháp gom thư mục nháp; `.backup/<id>.json`; rollback hiểu cả bản sao lưu dạng thư mục.
  - Trình sửa script (`ScriptFileInfo(relativePath:)`) và `ExtensionMetadataEditor` đọc/ghi qua reader + writer, giao diện như cũ.
- **Backup:** gói đúng file theo `Extension.folder` (bản ghi chưa chuyển thì gói thư mục). Khôi phục nhận cả archive cũ (gom thư mục JS, lấy `source.json` của Legado) lẫn mới. Bỏ `extensions/common` (`BackupPaths.extensionCommonFolder*`, `installCommonFolder`, `ExtensionManager.commonDirectory`). Vân tay backup đổi một lần ⇒ có một lần sao lưu tự động.
- **Hành vi đổi:**
  - Gói JS chỉ mang `plugin.json`, `*.js`, `icon.png`.
  - `load('../x.js')` không với ra ngoài gói.
  - Zip có `packageId` chứa `/` báo lỗi.
- **Tài liệu:** `rules.md` § Extension store invariants, `CLAUDE.md` + `AGENTS.md` (mục lưu trữ, tiện ích JS), chú thích `ExtensionStorePaths`.
- Chuyển `[1.3.726]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng:**
  - Đọc diff, nhất là các điểm chết giữa chừng của migrator.
  - Grep: ngoài reader, writer, migrator, staging debug và `ExtensionScriptDecoder` (thư mục tạm), không còn chỗ ghép `plugin.json` / `src` / `icon.png` vào `localPath`.
  - `check_architecture.py`: 1 violation nền (`JSDom.swift`), **0 mới**. `ExtensionManager` 765 → 754 dòng, `ExtensionScriptEditorView` 399 → 365.
  - Không build tại chỗ (Windows). Chưa thử trên máy: mở app lần đầu sau khi cập nhật, Kho đủ tiện ích, ghim và cấu hình còn; app Tệp chỉ thấy `js/` + `legado/`; tìm kiếm, đọc chương, comic có script, TTS tiện ích, sửa script tay, nguồn Legado bật/tắt/nhóm/xoá, backup + khôi phục (cả bản cũ), debug cài nháp + rollback.

## [1.3.755] - 2026-11-06

### refactor: mọi chỗ đọc plugin.json, script và icon tiện ích đi qua một bộ đọc chung

Người dùng: *"chia folder extension ra 2 sub folder cho legado và js, bạn nghĩ sao nếu js gom tất cả script vào json?"*, rồi chốt: *"ý tôi là mỗi tiện ích js là 1 json ấy"*, mục tiêu "Nhìn thư mục cho gọn". Anh Bửu duyệt plan 3 bước; đây là bước 1. Bố cục trên đĩa **chưa đổi**.

- **`ExtensionPackageReader`** (`Sources/Models/Extensions/`, mới) là nơi **duy nhất** đọc gói tiện ích theo `localPath`, hiểu ba dạng:
  - thư mục cũ (`plugin.json` + script ở gốc hoặc `src/` + `icon.png`), vẫn dùng cho thư mục nháp của debug server;
  - file gói JS `…/js/<id>.json` (`ExtensionPackageBundle`: `bundleFormat`, `files` đường dẫn tương đối → chữ, `icon` base64);
  - file nguồn Legado `…/legado/<id>.json` = nguyên văn `source.json`, manifest dựng trong RAM (`LegadoSourceManifest`, không có `version` / `nsfw`).
- `script(named:)` giữ đúng luật **gốc rồi `src/`** của `load()` và mục `script` trong `plugin.json`.
- Gói JS đã parse được nhớ trong RAM (`ExtensionPackageBundleCache`), khoá theo đường dẫn + mtime + cỡ, tối đa 96 mục / 24 MiB. `stat()` lỗi thì coi như không có gói, không bao giờ trả bản đã nhớ. Nguồn Legado không nhớ.
- Hằng `author` "Legado" / `locale` "zh_CN" dời xuống `LegadoSourceManifest`; `LegadoSourceIdentity` trỏ tới đó (một nguồn sự thật).
- **Đổi chữ ký:**
  - `ExtensionManager.getScriptPath(extensionPath:scriptKey:) -> URL` thành `entryScript(localPath:scriptKey:) -> ExtensionPackageReader.Script`. Giữ mã lỗi -3/-4/-5 và câu lỗi.
  - `ComicImageScriptRunner.scriptURL` thành `scriptContent(localPath:fileName:)`.
  - Bỏ `ExtensionScriptStaticCheck.resolve` và `ExtensionDebugRunner.relativePath(of:under:)` (không còn caller).
- **Chuyển sang bộ đọc:**
  - Lõi: `JSExecutor+Load`, `ExtensionManager` (+Search/Explore/Media), `ComicImageScriptRunner`, `BookDownloadWorker`, `ExtTTSScriptCache` (mốc kiểm hạn lấy từ `modificationStamp`).
  - Quét và kiểm tra: `ExtensionScriptConfigScanner`, `ExtensionDebugRunner`, `ExtensionDebugScriptScanner`, `ExtensionDebugInstalledSnapshot`, `ExtensionScriptStaticCheck`.
  - Manifest: `ExtensionManifestReader`, `ExtensionUrlMatcher`, `ExtensionContentKind`, `TranslationConfigStore`.
  - View: `ExtensionConfigSchema`, `ExtensionFilterScope`, `RepositoryManagerView+Actions`, `ExtensionIconImageCache`, `BypassBrowserHomePage`, `ExtensionScriptEditorView+Toolbars` (so đường dẫn tương đối của script thay cho URL).
- Tên tiện ích trong log/lỗi và khoá cache ảnh comic dùng `packageName` (tên thư mục, hoặc tên file bỏ `.json`), để khoá không đổi khi gói thành một file.
- Chuyển `[1.3.725]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng:**
  - Đọc diff; grep chéo caller của các hàm đổi chữ ký.
  - `check_architecture.py`: 1 violation nền (`JSDom.swift`), **0 mới**; `ExtensionManager.swift` giảm 799 → 765 dòng.
  - Không build tại chỗ (Windows). Chưa thử trên máy.

## [1.3.754] - 2026-11-06

### feat: hub luôn hiện tất cả thì icon luôn là chồng thẻ

Người dùng: *"Cài đặt hub: luôn hiện tất cả thì đừng đổi icon khi có 1 tác vụ đang chạy"*, rồi chốt: *"luôn là chồng thẻ bất cứ lúc nào Ở chế độ “Luôn hiện tất cả mục”"*; vẫn nháy khi có tác vụ. Anh Bửu duyệt plan.

- **`FloatingHubButton.glyphName`**: cài đặt "Khi chạm hub" là **Luôn hiện tất cả mục** (mặc định) ⇒ icon **luôn** `square.stack.3d.up`, kể cả lúc 0 tiến trình, tác vụ nền hay chỉ còn kết quả AI chưa xem. **Mở thẳng khi chỉ có 1 tác vụ** ⇒ bảng icon cũ (chuông / icon của mục / chồng thẻ).
- **Nháy không đổi** ở cả hai lựa chọn: chỉ nháy khi có tiến trình thật sự đang chạy (`ButtonState.isPulsing`); lúc rảnh chồng thẻ đứng yên, màu chữ hệ thống.
- Nút đọc cài đặt bằng `@AppStorage(FloatingHubTapBehavior.storageKey)` ngay trong view ⇒ đổi cài đặt là icon đổi ngay; nút chỉ vẽ lại thêm khi đổi cài đặt, `ButtonState` không đổi. Nhãn VoiceOver giữ nguyên.
- Câu "?" của nhóm "Khi chạm hub nổi" (Giao diện) nói icon của từng lựa chọn; doc comment `FloatingHubTapBehavior` / `FloatingHubButton` và **`rules.md`** § Nút hub nổi (a) cập nhật theo (bỏ câu "Icon và nháy không đổi theo cài đặt"). `CLAUDE.md` / `AGENTS.md` không nhắc icon hub ⇒ không sửa. Chuyển `[1.3.724]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng:**
  - Đọc code + diff; `glyphName` chỉ dùng trong `FloatingHubButton.body`.
  - `check_architecture.py`: 1 violation nền (`JSDom.swift`), **0 mới**.
  - Không build tại chỗ (Windows). Chưa thử trên máy: hub hiện chồng thẻ lúc rảnh (không nháy) và lúc có 1 video (nháy); đổi sang "Mở thẳng" ⇒ icon về chuông / icon của mục ngay, không cần mở lại app.

## [1.3.753] - 2026-11-06

### fix: tiện ích cùng tên khác tác giả ở các kho không còn che nhau, cài song song được

Người dùng: nhập kho `buudvh/leech_story_ext` báo 32 tiện ích mà chỉ hiện 18, trước đó đã nhập kho thứ hai (kho tổng hợp 781 mục) — *"tôi nghi bạn xử lý sai các nguồn trùng tên"*, rồi *"so sánh tác giả nữa"*. Anh Bửu duyệt plan (gồm sửa `rules.md`).

- **Nguyên nhân:** danh mục dedupe theo `packageId` = tên viết thường (`ExtensionSyncCommandBuilder.packageId(forName:)`), kho nhập trước thắng. 15/32 tiện ích của kho anh trùng tên với bản của tác giả khác trong kho thứ hai (txt520, 101kks, shuhaige, ixdzs, 69shuba, qidian, twkan, Book QQ, uukanshu, idejian, html5.qq.com, Google TTS, Bing TTS, sudugu, YouTube) nên bị che; chính kho thứ hai cũng tự che 98 bản cùng tên khác tác giả. Không phải lọc NSFW / loại.
- **Danh tính mới = tên + tác giả** (`ExtensionCatalogIdentity`, file mới; tác giả so không phân biệt hoa thường, bỏ khoảng trắng hai đầu):
  - Cùng tên cùng tác giả ⇒ một hàng, kho đứng trước thắng như cũ.
  - Cùng tên khác tác giả ⇒ hai hàng, cài song song được. Mã theo tên giữ cho bản chiếm trước (đã cài, hoặc kho đứng trước); bản sau nhận `<mã>__<tác giả>` (vd `qidian__huongmt`; tác giả rỗng ⇒ `an_danh`, ký tự `/ \ :` ⇒ `_`).
  - Tiện ích đã cài **không** đổi mã ⇒ truyện trên kệ, TTS, cấu hình, `localStorage` giữ nguyên.
- **`ExtensionLibraryRepository`:** chỉ mục registry theo kho (`registryIndexes`, dựng lại khi cache kho đổi); `buildCatalog` đánh dấu khoá của bản đã cài lẫn khoá dòng registry khớp nó trong kho của nó (tác giả trong `plugin.json` khác chữ registry không làm hiện thêm hàng); `remoteVersion` ghép đúng dòng của kho mình theo tên + tác giả → mã (mã trơn, rồi `<mã>__<tác giả>` qua chỉ mục `bySuffixedId`). **Không** ghép chỉ theo tên: bản đầu của commit có bậc này và rà soát chỉ ra kho nhiều tác giả cùng tên sẽ trả nhầm bản (báo cập nhật sai, nút Cập nhật tải zip tiện ích khác đè vào thư mục) — sửa ở commit tiếp theo cùng tiêu đề; không khớp ⇒ `nil`, chỉ mất báo cập nhật. Hàm mới `registryItem(for:)` / `registryItem(repositoryUrl:packageId:name:author:)` dùng chung cho `registryDownloadUrl` (nút cài/cập nhật) và `registryNsfwFlag` (`ExtensionTransactionCoordinator`).
- **`rules.md`:** dòng ghép `remoteVersion` và luật "ba đường cài cùng mã" ghi ngoại lệ: import zip / Debug vẫn chỉ theo tên ⇒ import zip một tiện ích trùng tên bản đã cài vẫn đè bản cùng mã như trước.
- Giới hạn: mã của mục **chưa cài** phụ thuộc thứ tự kho (xoá kho đứng trước ⇒ bản sau lấy lại mã trơn); chỉ mã lúc cài được lưu.
- Chuyển `[1.3.723]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng:**
  - Mô phỏng thuật toán bằng Python trên `plugin.json` thật của hai kho (thứ tự kho thứ hai → kho anh): 807 hàng (trước 695), kho anh đủ 32, mã không trùng; cài cả hai bản qidian ⇒ vẫn đúng hai hàng qidian. Một dòng tên rỗng của kho thứ hai bị bỏ như trước.
  - Đọc code + diff; grep `Sources/`: không còn chỗ ghép registry bằng `packageId(forName:)` ngoài chỉ mục mới (còn lại là bản mirror của Debug/zip).
  - `check_architecture.py` chỉ còn lỗi nền `JSDom.swift`, **0 mới**.
  - Không build tại chỗ (Windows). Chưa thử trên máy: tab Tất cả tiện ích hiện đủ 32 tiện ích của kho anh (lọc tác giả HuongMT); cài qidian của hai tác giả cùng lúc, mỗi bản đọc truyện riêng; nút cập nhật báo đúng phiên bản từng bản.

## [1.3.752] - 2026-11-06

### feat: nhập kho tiện ích chỉ cần link, tên kho lấy từ metadata của plugin.json

Người dùng: *"phần nhập kho tiện ích mới bỏ nhập tên kho đi, tên kho lấy từ metadata.name || metadata.author"*. Anh Bửu chọn: thiếu cả hai ⇒ `owner/repo` (link GitHub) hoặc tên miền; kho đã lưu giữ tên cũ; không có chỗ sửa tên tay; duyệt plan.

- **Sheet "Nhập kho tiện ích"** (`AddRepositoryView`): bỏ ô "Tên kho (tuỳ chọn)", chỉ còn ô link; `onAdd` nhận mỗi URL.
- **Đặt tên** (`ExtensionRepositoryNaming`, file mới): `metadata.name` → `metadata.author` → `owner/repo` khi link là `raw.githubusercontent.com/<owner>/<repo>/…` hoặc `github.com/<owner>/<repo>/…` → tên miền (bỏ `www.`) → nguyên link. Thay chữ cố định "Kho Tiện Ích Mới".
- **Đọc metadata kho** (`ExtensionManager.swift`): `RegistryMetadata` thêm `name`, đọc từng trường riêng (một trường sai kiểu chỉ thành `nil`); hàm mới `fetchRegistryResponse` trả cả `metadata`, `fetchRegistry` gọi qua nó ⇒ lượt kiểm tra cập nhật không đổi.
- `ExtensionUpdateCheckCoordinator.addRepository(url:)` bỏ tham số tên. Lượt kiểm tra cập nhật **không** đổi tên kho đã lưu.
- Lưu ý: hai kho của anh (`leech_story_ext`, `tangcongcac_ext`) chưa có `metadata.name` và cùng `author: "HuongMT"` ⇒ nhập mới cả hai sẽ cùng tên, phân biệt bằng dòng link; muốn tên riêng thì thêm `name` vào `metadata` của kho.
- Chuyển `[1.3.722]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng:**
  - Đọc code + diff; grep `Sources/`: `AddRepositoryView` và `addRepository(url:)` mỗi thứ một chỗ gọi; không ai dựng `RegistryMetadata(` bằng tay (thêm `init(from:)` an toàn).
  - `check_architecture.py` chỉ còn lỗi nền `JSDom.swift`, **0 mới**.
  - Không build tại chỗ (Windows). Chưa thử trên máy: nhập kho có `metadata.author` ⇒ tên = tác giả; kho không có metadata trên GitHub ⇒ `owner/repo`; câu báo "Đã nhập thành công kho '…'" đúng tên.

## [1.3.751] - 2026-11-06

### feat: hết phim tự sang phim đề xuất, vuốt xuống co khung phim vào cửa sổ nhỏ hoặc hub, bỏ PiP hệ thống

Người dùng muốn phim hết tập cuối thì tự sang phim đề xuất thứ nhất (có công tắc ở Cài đặt › Video và ngăn kéo ⋯ của trình phát), và thấy vuốt xuống vào PiP *"chưa mượt"* ⇒ muốn trình phát thu nhỏ tự dựng kiểu YouTube. Anh Bửu duyệt mockup + plan, chọn: tự sang **ở mọi nơi**, **sang ngay** (không đếm ngược), mặc định bật, có dòng báo ngắn; kiểu "Hình trong hình" thành **cửa sổ nhỏ tự dựng**, kiểu hub thì khung phim **bay vào nút hub**; cửa sổ nhỏ **bám mép trái/phải, cao tuỳ ý**, thả vào vòng ✕ để tắt; **bỏ hẳn PiP hệ thống**, rời app chỉ phát tiếng.

- **Tự sang phim đề xuất** (`VideoAutoNextPolicy`, khoá `videoAutoNextSuggest`, mặc định bật; Cài đặt › Đọc & Nghe › Video nhóm mới "Khi hết phim" + hàng thứ hai ngăn kéo ⋯ — công tắc, không nằm trong lưới vì lưới là chọn một-trong-nhiều):
  - `VideoAutoNextCoordinator` tải sẵn khi phiên bắt đầu nạp **tập cuối**: nhóm đề xuất lấy từ model màn xem → cache chi tiết (5 phút) → tải chi tiết `isInteractive: false`; chạy trang 1 của nhóm đầu có script (đề xuất trên màn chỉ tải khi cuộn tới nên không dựa được).
  - Phim = mục đầu tiên khác phim vừa hết và chưa phát trong chuỗi tự sang hiện tại (chống A → B → A). Lượt tải sẵn rỗng (mạng chập chờn) ⇒ lúc hết phim tải lại một lần.
  - Hết tập cuối (`handlePlayedToEnd`): màn xem đang hiện đúng phim ⇒ `VideoWatchModel.replace(with:autoNext:)`; không có màn (cửa sổ nhỏ, hub, nền) ⇒ `VideoWatchModel` không màn, giữ tối đa 90 giây, mở phiên xong thì chỉ thả (không huỷ, để lượt làm mới mục lục chạy nốt); cả lượt nằm trong background task.
  - Phát luôn dù tắt "Tự phát khi mở phim" (`autoNext`), giữ tiếng của phim vừa hết (`open(muteOverride:)`), báo "Tự sang: <tên>" khi phim mới **bắt đầu phát** (`open(startNotice:)` → `pendingStartNotice`; hiện ngay lúc mở sẽ bị lượt nạp tập xoá).
  - Phim nhúng trang không báo hết ⇒ không tự sang; phim nhập từ file không có đề xuất.
- **Bỏ PiP hệ thống**: xoá `VideoPictureInPictureCoordinator` cùng mọi trạng thái PiP của session / màn / stage; trang nhúng `allowsPictureInPictureMediaPlayback = false`. Vào nền ⇒ tách hình ngay, phát tiếp chỉ tiếng nếu đang phát lúc rời active (`wasPlayingWhenResigned`).
- **Co khung phim theo tay** (`Views/VideoPlayer/Minimize/`):
  - `VideoGestureView` báo khoảng kéo + tốc độ theo **toạ độ cửa sổ** (khung phim đang co nên đo theo chính view sẽ lệch).
  - `VideoMinimizeDragState` (controller giữ) + `VideoMinimizeDragContainer` (chỉ container vẽ lại mỗi nhịp): khung phim co và trôi tới chỗ đậu cửa sổ nhỏ, phần dưới mờ dần, nền đen nhạt dần lộ màn phía sau (presenter để nền trong suốt, router `presentationBackground(.clear)`).
  - Nhả tay quá 110 pt hoặc hất nhanh ⇒ theo `VideoMinimizePolicy`; chưa tới ⇒ bật về. Kiểu hub và nút ⌄: bay vào nút hub (`FloatingHubWindowManager.visibleButtonFrame`) rồi tan, hub nháy (`bounceButton`). Kiểu Cửa sổ nhỏ (`VideoMinimizeStyle.miniPlayer`, raw value giữ `"pictureInPicture"` ⇒ lựa chọn đã lưu không mất): co đúng vào chỗ đậu. Tới đích rồi mới đóng màn, không animation.
- **Cửa sổ nhỏ** (`Views/VideoPlayer/MiniPlayer/`):
  - `UIWindow` lớp phủ ở level `alert - 2.5` (dưới hub, trên widget trình duyệt), chạm ngoài cửa sổ rơi xuống app; 50% cạnh ngắn, 16:9; ‖/▶, ✕, vạch tiến độ, dòng báo dưới cửa sổ.
  - Kéo ⇒ bám mép trái/phải ở độ cao thả tay (nhớ ở `videoMiniPlayerDock`); thả vào vòng ✕ ở đáy ⇒ tắt hẳn phim; chạm ⇒ nở lên chỗ khung phim rồi mở lại màn xem không animation (`requestScreen(animated:)`).
  - Gắn vào phiên như một màn (`attachScreen(_:isMiniPlayer:)`, phần gắn/gỡ tách sang `VideoPlaybackSession+Screens`): hình giữ gắn, dòng Video của hub ẩn; chỉ màn to (`isFullScreenAttached`) chặn mở lại. Ẩn khi màn to gắn (`onFullScreenAttached`) hoặc phiên vẫn rảnh ở nhịp sau `stop()` (`onDidStop` — tự sang dừng rồi mở phim mới ngay).
  - Nút PiP trên thanh trên ⇒ "Cửa sổ nhỏ" (ngang / toàn màn dọc thì về khung dọc trước). Phim nhúng trang ⇒ hub. `VideoPlayerSurfaceView` không giành lại hình khi cửa sổ nhỏ đang hiện.
- `CLAUDE.md` / `AGENTS.md`: sửa mục Comic & Video (bỏ PiP, thêm cửa sổ nhỏ + tự sang). Chuyển `[1.3.721]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng:**
  - Đọc code + diff; grep `Sources/` không còn tham chiếu PiP cũ (`togglePictureInPicture`, `isPictureInPicture…`, `.pictureInPicture`).
  - `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới** (`+Playback` giữ dưới 400 dòng).
  - Không build tại chỗ (Windows). Chưa thử trên máy: lộ màn phía sau khi kéo ở lối mở từ Kệ / Lịch sử (`fullScreenCover` + `presentationBackground(.clear)`); tự sang khi app chạy nền (iOS có thể treo app trước khi tải xong); phát tiếp chỉ tiếng khi rời app; cửa sổ nhỏ nằm trên sheet / bàn phím.

## [1.3.750] - 2026-11-06

### feat: cài đặt chạm hub, mặc định luôn hiện tất cả mục

Người dùng: *"thêm config cho hub, 2 option, hiển thị hub con khi chỉ có 1 hub action và hiển thị tất cả hub con mọi lúc"*. Chốt qua mockup inline + bảng chọn: hiểu theo **cách chạm hub**, đặt ở Giao diện, mặc định "Luôn hiện tất cả", không có tác vụ thì vẫn mở menu. Anh Bửu duyệt plan (gồm cả việc sửa `rules.md`).

- **`FloatingHubTapBehavior`** (file mới, `Views/FloatingHub/`): `alwaysMenu` = "Luôn hiện tất cả mục" (**mặc định**) / `directWhenSingle` = "Mở thẳng khi chỉ có 1 tác vụ". Khoá `floatingHubTapBehavior` (không dấu chấm); chưa ghi hoặc giá trị lạ ⇒ mặc định.
- **Chạm hub** (`activateByRunningTasks`, `+Actions`): "Luôn hiện tất cả mục" ⇒ bung (nếu đang nép) và mở menu ở **trang chính** dù có 0, 1 hay nhiều tiến trình — kể cả khi tiến trình duy nhất là AI (chạm dòng Trợ lý AI mới sang trang "Tác vụ AI"). "Mở thẳng khi chỉ có 1 tác vụ" ⇒ y nguyên bảng chạm 0/1/≥2 chốt 2026-10-22. Đọc `UserDefaults` lúc chạm ⇒ đổi là có hiệu lực ngay, không publisher, nút không vẽ lại.
- **Nút hub giữ nguyên**: icon (chuông / icon mục / chồng thẻ) và nháy vẫn theo số tiến trình ở cả hai lựa chọn.
- **Cài đặt › Chung › Giao diện**: nhóm mới "Khi chạm hub nổi" sau "Danh sách chương" — `Picker` kiểu inline hai dòng có dấu chọn (tên lựa chọn dài, kiểu menu sẽ cắt chữ), nút "?" giải thích.
- **Hệ quả**: sau khi cập nhật, chạm hub lúc 0/1 tác vụ mở menu thay vì mở thẳng Thông báo / mục đó; muốn cách cũ thì chọn lại trong Giao diện.
- Comment bảng chạm ở `FloatingHubContainerViewController`, `+Actions`, `+Menu`, `FloatingHubButton` cập nhật theo. **`rules.md`** § Nút hub nổi (a) + (e): phần chạm theo số tiến trình chỉ áp ở lựa chọn "Mở thẳng"; câu "0/1 tiến trình thì chạm không mở được menu" thành hệ quả của lựa chọn đó. `CLAUDE.md` / `AGENTS.md` không nhắc bảng chạm hub ⇒ không sửa. Chuyển `[1.3.720]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng:**
  - Đọc code + diff; `activateByRunningTasks` chỉ có một chỗ gọi (`handlePrimaryAction`, đường chung của chạm và VoiceOver). Không đụng `FloatingHubWindowManager`, `FloatingHubUIWindow`, vị trí hub (việc video đang làm).
  - `check_architecture.py`: 1 violation nền (`JSDom.swift`), **0 mới**.
  - Không build tại chỗ (Windows). Chưa thử trên máy: chạm hub lúc rảnh / 1 video / 1 AI ⇒ menu trang chính; đổi sang "Mở thẳng" ⇒ chạm lại có hiệu lực ngay; dòng Video vẫn phát/dừng/đóng được trong menu.

## [1.3.749] - 2026-11-06

### feat: bỏ link kho tiện ích có sẵn, xoá kho không gỡ tiện ích đã cài

Người dùng: *"bỏ url mặc định của tôi trong danh sách kho js"*, rồi nói rõ: người dùng phải tự tìm link để nhập, không có sẵn link để bấm cài; *"gỡ kho đừng có gỡ tiện ích của kho đó đang cài đi"*. Anh Bửu duyệt plan (gồm cả câu chỉ đường ở tab trống).

- **Bỏ kho có sẵn** (`buudvh/leech_story_ext`):
  - `ExtensionUpdateCheckCoordinator`: xoá `defaultRepositoryName` / `defaultRepositoryUrl` / `addDefaultRepository()`.
  - `RepositoryManagerView.onAppear`: không còn tự thêm kho khi danh sách kho trống (trước đây xoá hết kho thì lần vào tab sau kho tự quay lại); chỉ còn `checkOnEntry` ở tab Tất cả tiện ích.
  - Trang Danh sách kho trống: bỏ nút "Nhập kho tiện ích mặc định", câu hướng dẫn thêm "Bấm + ở góc trên để dán link kho".
  - Tab Tất cả tiện ích trống khi chưa có kho nào: "Chưa có kho tiện ích. Mở … › Danh sách kho để nhập link kho."
  - Kho đã lưu trên máy giữ nguyên. Nguồn cập nhật app `buudvh/FreeBook/source/apps.json` (LiveContainer) không đổi — không phải kho tiện ích.
- **Xoá kho giữ tiện ích** (`ExtensionTransactionCoordinator.deleteRepository`): chỉ xoá bản ghi kho + cache registry; file, bản ghi, cấu hình, `localStorage` và `repositoryUrl` của tiện ích đã cài giữ nguyên (không ghi lại `installed.json`).
  - Hệ quả: tiện ích của kho đã xoá vẫn chạy nhưng không báo bản mới, không vào "Cập nhật tất cả" (không có `remoteVersion`) cho tới khi nhập lại đúng link kho đó; gỡ tiện ích sau đó là mất hẳn. Mục chưa cài của kho mất cùng cache registry.
  - Hộp xác nhận: "Kho X sẽ bị xóa khỏi danh sách. Tiện ích đã cài từ kho này vẫn giữ nguyên." Bỏ chặn "kho đang được TTS sử dụng" vì xoá kho không còn gỡ gì TTS đang dùng.
- `CLAUDE.md` / `AGENTS.md` / `rules.md` không nhắc kho mặc định hay luật xoá kho gỡ tiện ích ⇒ không sửa. Chuyển `[1.3.719]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng:**
  - Đọc code + diff; grep `Sources/` không còn `addDefaultRepository` / `leech_story_ext`; `deleteRepository` chỉ có một chỗ gọi (trang Danh sách kho).
  - `check_architecture.py` chỉ còn lỗi có sẵn (`JSDom.swift`, `VideoPlaybackSession+Playback.swift` của việc video đang làm), **0 mới**.
  - Không build tại chỗ (Windows). Chưa thử trên máy: cài mới ⇒ tab Tiện Ích không tự có kho, hiện câu chỉ đường; xoá kho ⇒ tiện ích đã cài còn, chạy được; nhập lại kho ⇒ báo cập nhật trở lại.

## [1.3.748] - 2026-11-06

### feat: mở app tự kiểm tra cập nhật tiện ích, có bản mới thì toast, bấm mở tab Tiện Ích

Người dùng: *"thông toast thông báo khi cập nhật ext, mở app lên thì hãy check ext update và thông báo"*. Anh Bửu chọn: chỉ kiểm khi mở app; lần nào còn bản chưa cập nhật thì báo; bấm toast mở tab Tiện Ích; thêm công tắc tắt và toast khi cập nhật xong; toast hiện ở `MainTabView` (không thêm event center); duyệt plan.

- **Kiểm khi mở app** (`ExtensionUpdateCheckCoordinator.checkOnLaunch`):
  - Một lượt đủ mọi kho mỗi lần khởi động (cờ trong RAM), tính vào giãn cách 5 phút ⇒ vào "Tất cả tiện ích" ngay sau đó không tải lại.
  - Trả tiện ích đã cài có bản mới (loại Legado — nguồn Legado không có `remoteVersion`), dùng gần nhất trước. Mất mạng ⇒ vẫn theo cache registry cũ.
  - Lõi `run` tách thành `perform` (async) để chờ được; `checkOnEntry` / ↻ / "Thử lại" giữ nguyên hành vi.
- **Toast** (`MainTabView.announceExtensionUpdatesOnLaunch`, cùng khuôn tự sao lưu / dọn truyện cũ — service chỉ trả kết quả, không gọi `ToastManager`):
  - 1 tiện ích: "Tiện ích X có bản mới (vA → vB)"; nhiều: "Có bản mới cho N tiện ích: A, B, C…" (tối đa 3 tên).
  - Bấm ⇒ dựng lại tab Tiện Ích về trang gốc "Tất cả tiện ích" (kể cả đang ở Legado / trang con) rồi chọn tab.
  - Màn đọc tự mở lại lúc khởi động che toàn màn ⇒ bấm toast thì tab đổi phía sau, đóng màn đọc mới thấy.
- **Toast bấm được** (`ToastManager.show(..., onTap:)`, mặc định `nil` ⇒ mọi chỗ gọi cũ không đổi):
  - Cửa sổ toast vẫn chạm xuyên qua. Chỉ toast có `onTap` nhận chạm, và chỉ trong viên thuốc (khung đo bằng `GeometryReader` — deployment iOS 17), có dấu `›`.
  - Bấm ⇒ ẩn ngay rồi chạy hành động. Mục ở Trung tâm thông báo vẫn chỉ là chữ.
- **Công tắc** "Báo cập nhật khi mở app" ở ngăn kéo … tab Tiện Ích (`ExtensionLaunchUpdateToggleRow`, khoá `extensionUpdateLaunchCheckEnabled`, thiếu khoá = bật, được sao lưu): tắt ⇒ không kiểm lúc mở app, không toast; lượt tự kiểm khi vào tab vẫn chạy.
- **Toast khi cập nhật xong**:
  - "Cập nhật tất cả" ⇒ "Đã cập nhật N tiện ích" / "Đã cập nhật x/N tiện ích, k lỗi" — luôn hiện (dòng chữ dưới danh sách chỉ thấy khi còn đứng ở trang đó), dòng chữ cũ giữ.
  - Nút cập nhật từng tiện ích ⇒ "Đã cập nhật X lên vB" hoặc câu lỗi. Cài mới không toast.
- `rules.md` (mục 7 + luật toast bấm được), `CLAUDE.md` + `AGENTS.md` thêm luật. Chuyển `[1.3.718]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng:**
  - Đọc code + diff; grep không có chỗ nào truyền `ToastManager.shared.show` như giá trị hàm (thêm tham số an toàn).
  - `check_architecture.py` chỉ còn 1 lỗi nền (`JSDom.swift`), **0 mới**.
  - Không build tại chỗ (Windows). Chưa thử trên máy: mở app khi có tiện ích chưa cập nhật ⇒ toast có `›`, bấm sang tab Tiện Ích; chạm cạnh toast vẫn bấm được màn dưới; tắt công tắc ⇒ mở app không toast; "Cập nhật tất cả" xong ⇒ toast.

## [1.3.747] - 2026-11-06

### feat: phim không còn mở trang Chi tiết cũ, ⋮ thẻ đề xuất chỉ còn Thêm vào kệ

Người dùng: *"Bỏ luôn màn hình xem chi tiết cũ của video đi"* — *"đừng dùng màn cũ đấy nữa"*. Anh Bửu chốt: ⋮ chỉ còn "Thêm vào kệ", không thêm chốt chặn trong `BookDetailView`, tra hết lối còn mở trang cũ cho phim.

- **Rà 15 chỗ gọi `BookDetailView(`**: với phim chỉ còn 2 lối lọt, đã đóng cả hai.
  - ⋮ "Mở trang chi tiết" của thẻ đề xuất ở màn xem: bỏ mục, gỡ `onOpenDetail` qua `VideoWatchSuggestCard` / `Section` / `Feed` / `VideoWatchDetailsView`. Bấm đề xuất không phải phim vẫn mở Chi tiết của truyện đó (`VideoWatchPagePresenter.openDetail`).
  - Nút "Nhập" trong trình duyệt mở từ màn đọc chữ (`ReaderView` `BypassWebView.onImport`): gọi `ContentDetailRouter.openIfVideo` trước ⇒ link của tiện ích phim mở màn xem phim.
  - Các lối khác đã đi router từ trước: Kệ, Lịch sử, nhấn giữ, Bộ sưu tập, Tìm trên kệ, Khám phá, Trang chủ, Tìm một nguồn, đề xuất ở Chi tiết, nút Nhập ở Kệ / Khám phá / Cấu hình / Chi tiết, nhập phim từ file.
- **Xoá code chỉ dành cho phim trong Chi tiết** (grep chéo `Sources/` trước khi xoá):
  - `BookDetailVideoTOCGrid` (+`+Groups`), nhánh `isVideo` / `videoRows` / `episodeNoun` của `BookDetailTOCView` (+`DownloadEvents`).
  - `VideoDownloadsDeletePill` (dời `detailText` sang `VideoDownloadsActionRow` — sheet nhấn giữ vẫn xoá được bản tải).
  - `prefersLandscapeCover` của `BookDetailHeaderView` / `BookDetailHeroView`, `VideoOfflineLibrary.refresh` lúc mở, nhánh video của `resolveBookId` và của `+Media` (nhãn tải / xuất / "Xem ngay").
  - `BookDetailView.swift` còn 1176 dòng (baseline 1201).
- `CLAUDE.md` + `AGENTS.md`: thêm luật "phim không bao giờ mở `BookDetailView`" ở mục Comic & Video.
- Chuyển entry cũ nhất sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng:**
  - Đọc code + diff; grep `Sources/` không còn `BookDetailVideoTOCGrid` / `VideoDownloadsDeletePill` / `onOpenDetail` / `prefersLandscapeCover` / `episodeNoun`.
  - `check_architecture.py` chỉ còn 1 lỗi nền (`JSDom.swift`), **0 mới**.
  - Không build tại chỗ (Windows). Chưa thử trên máy: ⋮ của thẻ đề xuất chỉ có "Thêm vào kệ"; Nhập link phim từ trình duyệt của màn đọc ⇒ màn xem phim; Chi tiết truyện chữ / tranh hiện như cũ.
