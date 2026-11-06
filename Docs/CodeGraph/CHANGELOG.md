# CHANGELOG - Nhật ký Thay đổi CodeGraph Tàng Công Các

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **Tàng Công Các**.

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

## [1.3.746] - 2026-11-06

### feat: bộ lọc chỉ hiện config mà script của tab dùng tới

Người dùng: *"Chỉ hiển thị những config dùng trong danh sách trong bộ lọc"*. Anh Bửu chốt qua grill-me: tab chạy `gen.js`, trong `gen.js` (cùng các file nó `load()`) có nhắc tới config B thì bấm lọc ở tab đó mới có B. Chỉ sửa app, không sửa tiện ích.

- **`ExtensionScriptConfigScanner`** (mới, `Services/Extensions/Config`): quét chữ, không chạy script.
  - Đọc file script của tab cùng mọi `load('x.js')` chữ cố định (đệ quy, chống lặp, tối đa 30 file). File tìm ở gốc tiện ích rồi `src/` như `JSExecutor+Load`; thư viện dựng sẵn không có file thì bỏ qua.
  - Bỏ comment `//`, `/* */` ngoài chuỗi (chuỗi giữ nguyên; ngoài chuỗi `\` bỏ qua ký tự kế để `/https?:\/\//` không thành comment).
  - Khớp **nguyên tên** khoá: `(?<![A-Za-z0-9_$])KEY(?![A-Za-z0-9_$])` ⇒ `FILTER_SORT` không khớp `FILTER_SORT_NAME`.
- **`ExtensionFilterScope`** (mới): `.file(tên)` hoặc `.pluginScript(khoá)` (đổi ra tên file lúc quét, ngoài main).
  - Khám phá theo tab đang chọn: Trang chủ ⇒ `explore`, Thể loại ⇒ `genre`, tab home ⇒ `script` của mục. Sheet giữ tab lúc bấm.
  - Danh sách thể loại / Xem thêm (`CategoryNovelsListView`) ⇒ `category.script`; Tìm một nguồn ⇒ `search`.
- `ExtensionConfigSchema.tabFilterKeys(for:localPath:)`; `hasActiveFilter(values:keys:)` chỉ xét khoá của tab.
- `ExtensionFilterCatalog`: khoá bảng gồm cả tab; chỉ dọn bản của version/config cũ, không dọn tab khác. Chấm "đang lọc" theo khoá của tab.
- `ExtensionFilterButton(ext:scope:…)`, `ExtensionFilterSheet(packageId:scope:…)`: sheet chỉ hiện / đặt lại / ghi khoá của tab, khoá khác giữ nguyên trong `configJson`. Đọc `plugin.json` + quét chạy ngoài main. Tab không dùng khoá nào ⇒ ẩn nút.
- **Giới hạn đã báo anh**: quét chữ không theo luồng dữ liệu. Tiện ích đọc mọi khoá trong file dùng chung (`config.js` của sto9, missav, 123av) thì mọi tab vẫn hiện đủ; qimao / wikidich thừa `COMMENT_MODE` / `FILTER_REVIEW_SORT`. qidian, STV, youtube hiện đúng theo tab.
- `CLAUDE.md` + `AGENTS.md`: thêm luật bộ lọc theo tab ở mục Extension JavaScript.
- Chuyển entry cũ nhất sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng:**
  - Đọc code + diff. Mô phỏng cùng thuật toán bằng Python trên 9 tiện ích của anh ⇒ kết quả khớp phân tích ở trên.
  - `check_architecture.py` chỉ còn 1 lỗi nền (`JSDom.swift`), **0 mới**.
  - Không build tại chỗ (Windows). Chưa thử trên máy: nút lọc đổi theo tab ở Khám phá, trang Xem thêm, Tìm một nguồn; áp dụng xong danh sách tải lại.

## [1.3.745] - 2026-11-05

### docs: cập nhật README theo tính năng hiện tại của app

Người dùng: *"cập nhật lại readme.md giúp tôi"*.

- **Mở đầu**: app đọc truyện chữ, truyện tranh **và xem phim**. Nguồn là tiện ích JavaScript hoặc nguồn Legado.
- **Mục mới "Cài đặt và cập nhật"**:
  - nguồn LiveContainer `apps.json`;
  - Release giữ 5 bản;
  - số phiên bản theo CHANGELOG, số build theo CI;
  - báo bản mới trong app, kèm lưu ý app không tự cài được.
- **Tính năng — bổ sung**:
  - tiện ích ba loại nội dung, cấu hình riêng từng tiện ích, bộ kiểm tra tiện ích, nguồn Legado, lọc NSFW;
  - đổi nguồn có nhật ký, gắn lại nguồn khi tiện ích đã gỡ;
  - tải nhiều luồng theo nguồn;
  - nhập ZIP/CBZ / video nhiều tập, xuất CBZ/PDF / video;
  - màn Dung lượng, mở lại mục đọc dở.
- **Tính năng — mục mới**:
  - Truyện tranh.
  - Video: màn xem dọc, tự phát, tắt tiếng, PiP / hub, chất lượng nhớ theo tiện ích, tải offline HLS.
  - Trình duyệt: AdGuard, chỉnh riêng theo tên miền, dịch trang.
  - Giao diện.
- **Tính năng — mục cũ cập nhật**:
  - luật dịch nhanh: rule tên chương, các token, trang hướng dẫn;
  - TTS: hẹn giờ;
  - AI: Chế độ AI của Google, AI theo truyện.
- **Build / CI**:
  - thêm SafariConverterLib (GPL-3.0, `-skipPackagePluginValidation`);
  - phiên bản mặc định `1.3.0 (1)` khi build tay;
  - các bước CI mới: version, Release + `apps.json` nhánh `source`, Telegram liệt kê commit.
- **Cấu trúc mã nguồn**:
  - cây thư mục `Services/` / `Views/` đúng hiện tại;
  - `Models/` chỉ còn 4 `@Model`, tiện ích là JSON;
  - bảng thư mục dữ liệu đủ `extension_store/`, `comics/`, `videos/`, `adblock/`, `Caches/comic_images/`.
- Chuyển entry cũ nhất sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đối chiếu với `CLAUDE.md`, `project.yml`, cây `Sources/`. Chỉ đổi tài liệu, không đụng code.

## [1.3.744] - 2026-11-05

### feat: màn xem video: tiêu đề nhóm đề xuất nổi bật có Xem thêm, thể loại và Xem thêm mở trang toàn màn đè lên phim

Plan đợt 2 trình phát video, mục 7–8 (anh Bửu đã duyệt).

- **Tiêu đề nhóm đề xuất kiểu A** (`VideoWatchSuggestSection.header`): khoảng trống + đường ngăn mờ phía trên, vạch màu nhấn 3 pt bên trái (không bo góc), chữ `.title3` đậm (to hơn tên phim trong thẻ), "Xem thêm ›" màu nhấn bên phải. Mọi nhóm có "Xem thêm"; nhóm cuối vẫn nạp thêm khi cuộn.
- **`VideoWatchPagePresenter`** (mới, `Views/VideoPlayer/Watch`): trang **toàn màn** đè lên màn xem.
  - `UIHostingController` `.overFullScreen` (không `.fullScreen`: kiểu đó gỡ màn xem ⇒ `onDisappear` ⇒ phim thu nhỏ). Màn xem vẫn gắn bên dưới, phim chạy tiếng như cũ.
  - `NavigationStack` riêng (trong trang vẫn đẩy tiếp Chi tiết, thể loại khác), nút `‹` đóng trang về lại màn xem, `.appAccentTint()` + `modelContainer` ở gốc.
  - Chỉ dọc (VC con trả `.portrait`); đang ngang thì xin xoay dọc rồi mới mở.
  - Dùng cho 3 lối: thể loại (nhãn `#` trên tên + chip của sheet Thông tin, mở sau khi sheet đóng), "Xem thêm" của đề xuất (`CategoryNovelsListView`), "Mở trang chi tiết" ở `⋮` của thẻ đề xuất (và đề xuất không phải phim) (`BookDetailView`).
- **`CategoryNovelsListView(onSelectVideo:)`** (mặc định `nil` = hành vi cũ ở mọi chỗ khác): trong trang, bấm phim của nguồn video ⇒ đóng trang trước, lượt sau đổi phim tại chỗ (`VideoWatchModel.replace`, mẫu `BookActionSheet.emit`). Nguồn khác ⇒ đẩy Chi tiết trong trang như cũ.
- **Bỏ đường sheet cũ**: `VideoWatchExit` chỉ còn `.home` / `.close`; `VideoPlayerScreen.handleExit` bỏ hai nhánh thu nhỏ rồi mở sheet; `VideoWatchPresenter` bỏ `presentPage` / `dismissPage`, `readyTopViewController` dùng chung với trang mới. `performDismiss` đóng trang đang đè (nếu có) trước khi đóng màn.
- **Nút âm lượng cứng khi trang đang che màn xem**: màn không "đang hiện" ⇒ không hiện thanh, không bỏ tắt tiếng (`VideoWatchPagePresenter.isPresenting`).
- Commit sửa thêm (cùng tiêu đề, trước khi đẩy): gọi `VideoWatchPagePresenter.dismiss` / `.shared` bằng tên kiểu trong closure thoát của hàm `static`.
- Chuyển entry cũ nhất sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng:**
  - Đọc code + diff, grep chéo `Sources/` không còn tham chiếu `presentPage` / `dismissPage` / `VideoWatchExit.genre` / `.openDetail` của màn xem. `check_architecture.py` chỉ còn 1 lỗi nền (`JSDom.swift`), **0 mới**.
  - Không build tại chỗ (Windows). Chưa thử trên máy: tiêu đề nhóm dễ thấy; "Xem thêm" từng nhóm mở trang, phim vẫn phát tiếng; bấm phim trong trang ⇒ trang đóng, màn đổi phim tại chỗ; bấm thể loại (nhãn # và sheet Thông tin); "Mở trang chi tiết" ở ⋮; nút ‹ về màn xem; trang không xoay ngang.

## [1.3.743] - 2026-11-05

### feat: nhớ chất lượng phim đã chọn theo tiện ích, phim sau không có mức đó thì lấy mức thấp hơn hoặc Tự động

Plan đợt 2 trình phát video, mục 6 (anh Bửu đã duyệt).

- **`VideoQualityPreferenceStore`** (mới, `Services/Video`): một dictionary `UserDefaults` `videoQualityPreferenceByPackage` dạng `[packageId: {height, bitrate}]`. Lưu chiều cao, kèm bitrate cho playlist không khai độ phân giải; không lưu `id`.
- **`VideoPlaybackSession+Quality`**:
  - `selectQuality` ghi vào kho theo `launch.extensionPackageId`; chọn "Tự động" ⇒ xoá. `refreshBandwidthLimit` (ép thấp nhất khi phát ẩn) **không** ghi.
  - Mỗi item mới (mở phim, đổi tập) ⇒ `selectedQuality` đọc lại từ kho. `stop()` chỉ xoá bản trong RAM, không xoá kho.
  - `appliedQuality` = mức cao nhất ≤ đã chọn; **không có** ⇒ Tự động (thay cho "mức thấp nhất").
- **Lưới Chất lượng ở ngăn kéo ⋮**: ô sáng theo mức đang áp — áp Tự động (kể cả khi mức đã nhớ không có ở phim này) ⇒ ô "Tự động" sáng.
- "Nguồn" hiểu là **tiện ích**: phim nào cùng tiện ích thì cùng mức. AVPlayer chỉ đặt được trần, mạng yếu vẫn có thể xuống thấp hơn. Bản tải offline vẫn theo `videoDownloadQuality` riêng.
- Commit sửa thêm (cùng tiêu đề, trước khi đẩy): mục ghi vào kho khai kiểu `[String: Any]` tường minh — literal dictionary trộn `Int` + `Double` không khai kiểu có thể bị trình biên dịch từ chối.
- Chuyển entry cũ nhất sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng:**
  - Đọc code + diff. `check_architecture.py` chỉ còn 1 lỗi nền (`JSDom.swift`), **0 mới**.
  - Không build tại chỗ (Windows). Chưa thử trên máy: chọn 720p ở phim A, mở phim B cùng tiện ích ⇒ 720p hoặc mức thấp hơn gần nhất, không có thì Tự động; tắt app mở lại vẫn nhớ.

## [1.3.742] - 2026-11-05

### feat: nút Toàn màn tự xoay ngang khi phim ngang, giữ dọc khi phim dọc

Plan đợt 2 trình phát video, mục 5 (anh Bửu đã duyệt).

- **`VideoPlayerController.toggleFullscreenForVideoShape()`** (nút "Toàn màn" của `VideoPlayerBottomBar` ở màn dọc): đọc `player.currentItem.presentationSize` lúc bấm.
  - Ngang (rộng > cao) ⇒ `rotate(currentlyLandscape: false)`: xoay ngang như nút Xoay.
  - Dọc hoặc vuông ⇒ toàn màn dọc như cũ (`togglePortraitFullscreen`).
  - Chưa biết khung (đang tải, trang nhúng — kích thước 0) ⇒ xoay ngang, vì phần lớn phim là ngang.
  - Đang toàn màn dọc ⇒ nút là "Thoát toàn màn" như cũ.
  - Log thường `🎬 [VideoPlayer] Toàn màn: …` ghi khung + lựa chọn.
- Nút Xoay giữ nguyên.
- Chuyển entry cũ nhất sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng:**
  - Đọc code + diff. `check_architecture.py` chỉ còn 1 lỗi nền (`JSDom.swift`), **0 mới**.
  - Không build tại chỗ (Windows). Chưa thử trên máy: "Toàn màn" với phim ngang (xoay ngang) và phim dọc (giữ dọc), lúc đang khoá xoay.

## [1.3.741] - 2026-11-05

### feat: nút âm lượng cứng hiện thanh âm lượng trên trình phát và bỏ tắt tiếng phim khi TTS không đọc

Plan đợt 2 trình phát video, mục 4 (anh Bửu đã duyệt).

- **Vì sao không hiện gì**: khung phim native giữ một `MPVolumeView` gần như vô hình (`VideoGestureView`) để vuốt chỉnh âm lượng, và nó ẩn luôn thanh âm lượng của iOS. Không chỗ nào theo dõi `AVAudioSession.outputVolume`.
- **`VideoVolumeObserver`** (mới, `Services/Video`): KVO `AVAudioSession.outputVolume`, bật/tắt theo màn trình phát cùng chỗ `VideoBrightnessKeeper.activate/deactivate` (`VideoPlayerScreen.onAppear/onDisappear`), đếm theo từng màn, màn mới nhất nhận sự kiện.
  - Mỗi lần đổi ⇒ `controller.showFeedback(.volume(level))`: thanh âm lượng sẵn có của trình phát, ở màn dọc lẫn toàn màn.
  - Màn xem đang hiện bìa (chưa phát phim của nó) ⇒ bỏ qua. Thu nhỏ vào hub / PiP ⇒ không còn màn ⇒ nút cứng không đụng tới phim.
- **Bỏ tắt tiếng** (`VideoPlaybackSession.handleHardwareVolumeChange`): chỉ khi phim native đang tắt tiếng + màn trình phát đang hiện + TTS **không** đọc ⇒ `setMuted(false)`. TTS đang đọc ⇒ giữ tắt tiếng, chỉ hiện thanh (anh chọn).
- **Lỗ phiên âm thanh**: phim tắt tiếng phát cùng TTS, rồi TTS dừng hẳn ⇒ TTS `setActive(false)` ⇒ KVO im luôn.
  - `VideoNativePlaybackFlag` (mới): cờ "phim native đang phát", `VideoPlaybackSession` ghi ở `handleTimeControlChange` và `stop`. Tầng TTS đọc cờ mà không phải chạm `VideoPlaybackSession.shared`.
  - `TTSAudioSessionController.deactivateUnlessVideoPlaying()`: phim native còn phát thì không tắt phiên.
  - `TTSManager.stopPlayback` gọi hàm này thay cho dòng `setActive(false)` (đổi 1 dòng lấy 1 dòng, không thêm dòng vào file sát baseline). Hai chỗ tắt phiên khi có cuộc gọi / ngắt âm thanh giữ nguyên.
- **Giới hạn iOS**: đang 100% mà bấm tăng, hay đang 0% mà bấm giảm, thì iOS không báo đổi ⇒ không hiện thanh, không bật tiếng.
- `CLAUDE.md` + `AGENTS.md`: thay dòng "nút âm lượng cứng thì không" bằng luật mới. Sửa comment ở `VideoPlayerController.handlePanBegan`.
- Chuyển entry cũ nhất sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng:**
  - Đọc code + diff. `check_architecture.py` chỉ còn 1 lỗi nền (`JSDom.swift`), **0 mới**. `TTSManager.swift` giữ 3468 dòng.
  - Không build tại chỗ (Windows). Chưa thử trên máy: bấm nút cứng ở màn dọc và toàn màn (hiện thanh); phim tắt tiếng, TTS không đọc ⇒ bật tiếng; TTS đang đọc ⇒ chỉ hiện thanh; phim tắt tiếng phát cùng TTS, dừng hẳn TTS rồi bấm nút cứng ⇒ vẫn hiện thanh.

## [1.3.740] - 2026-11-05

### feat: trang Cài đặt Video, vuốt xuống thu nhỏ vào hub hoặc Hình trong hình, tắt NSFW thì dừng phim 18+

Plan đợt 2 trình phát video, mục 1–3 (anh Bửu đã duyệt).

- **Trang Cài đặt › Đọc & Nghe › Video** (`VideoSettingsView`, `Sources/Views/Settings/Video/`; hàng `NavigationLink` icon `play.rectangle` trong `ReadingSettingsSection`):
  - Nhóm **Khi mở phim**: "Tự phát khi mở phim" (dời từ section Đọc & Nghe, bỏ hàng cũ) và "Tắt tiếng khi mở phim" (dời từ màn Nội dung nhạy cảm, bỏ hàng cũ). Cùng khoá cũ, không mất lựa chọn.
  - Nhóm **Vuốt xuống trình phát** (nút "?"): "Phim thường" / "Phim 18+", mỗi dòng chọn Thu nhỏ vào hub / Hình trong hình. Mặc định cả hai là hub (giữ hành vi cũ).
  - Sửa comment sai ở `NsfwSettingsView` (màn nằm ở Cài đặt › Chung › Giao diện, không phải Thư Viện), `VideoMutePolicy`, `VideoAutoplayPolicy`, `ReadingSettingsSection`.
- **`VideoMinimizeStyle` + `VideoMinimizePolicy`** (`Services/Video`): khoá `videoSwipeMinimizeNormal` / `videoSwipeMinimizeNsfw`; luật `Extension.videoMinimizeOverride ?? (RepositoryFilterPolicy.isNsfwBook ? "Phim 18+" : "Phim thường")`.
- **Vuốt xuống** (`VideoPlayerScreen.minimizeBySwipe`, gắn vào `controller.onMinimizeRequest`):
  - Kiểu hub ⇒ thu nhỏ như cũ.
  - Kiểu PiP và `isPictureInPicturePossible` ⇒ chỉ `togglePictureInPicture()`; handler `pictureInPictureStartCount` có sẵn tự thu nhỏ khi PiP đã bật (không đóng màn trực tiếp vì PiP cần layer còn gắn).
  - PiP không được (phim nhúng, item chưa sẵn sàng) ⇒ hub. PiP không lên sau 1,5 giây (bị từ chối, lỗi) ⇒ hub.
  - Nút ⌄ không đổi: luôn thu nhỏ vào hub.
- **Ghi đè theo tiện ích**:
  - `Extension.videoMinimizeOverride: String?` (`nil` = theo cài đặt chung; decode khoan dung).
  - `ExtensionTransactionCoordinator.setVideoMinimizeOverride`.
  - Mục **Video** trong Cấu hình tiện ích (`ExtensionConfigView+Video`), chỉ tiện ích loại video: Picker menu "Theo cài đặt chung (…)" / Thu nhỏ vào hub / Hình trong hình (mẫu `NsfwChoice`). Nhãn "Theo cài đặt chung" ghi giá trị chung đang áp (tiện ích 18+ theo dòng "Phim 18+").
  - Backup: `BackupPayload.ExtensionRecord`, `BackupLibraryReader`, `BackupLibraryWriter` (chỉ áp khi máy này chưa tự chọn), `BackupLibraryFingerprint`. Optional mặc định `nil` ⇒ vân tay backup cũ không đổi.
- **Tắt NSFW thì dừng phim 18+** (`VideoPlaybackSession+NsfwGuard`): nghe `UserDefaults.didChangeNotification` (nhận trên main), chỉ xử lý lúc khoá `RepositoryFilterPolicy.includeNsfwDefaultsKey` chuyển từ bật sang tắt; phim đang phát là `isNsfwBook` ⇒ `stop()`, kể cả khi đang ở hub hay PiP.
- `CLAUDE.md` + `AGENTS.md`: cập nhật chỗ đặt "Tắt tiếng khi mở phim", thêm luật vuốt xuống và dừng phim 18+.
- Chuyển entry cũ nhất sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng:**
  - Đọc code + diff. `check_architecture.py` chỉ còn 1 lỗi nền (`JSDom.swift`), **0 mới**.
  - Không build tại chỗ (Windows). Chưa thử trên máy: vuốt xuống ở màn dọc theo từng cài đặt (phim thường / 18+ / tiện ích đặt riêng, PiP được và không được); tắt NSFW lúc phim 18+ đang ở hub hoặc PiP ⇒ phim dừng.

## [1.3.739] - 2026-11-05

### fix: hub và widget nổi không còn mất sau khi tắt Hình trong hình

Người dùng: xem phim → bật PiP → tắt PiP ⇒ **mất cả hub** tới khi tắt app mở lại (có lúc thấy widget hiện trong khung PiP).

- **Nguyên nhân nhiều khả năng nhất** (đọc code, chưa xác nhận trên máy):
  - Bật PiP thì iOS (trong LiveContainer) có thể nối thêm một `UIWindowScene` cũng báo `didActivate`.
  - `handleSceneDidActivate` của các window manager chuyển cửa sổ nổi sang **bất kỳ** scene nào báo `didActivate`; `activeWindowScene` lấy scene active **đầu tiên** của một `Set` không thứ tự.
  - ⇒ Hub bị chuyển sang scene của PiP. Tắt PiP thì scene đó mất, không còn gì gọi `refreshState` (app không rời `.active`, cờ ẩn không đổi, scene chính không báo `didActivate` lại).
- **`AppMainWindowScene`** (mới, `Sources/Common/Utils/`): chọn scene chứa giao diện chính theo hạng:
  1. scene có key window không phải lớp phủ, level `.normal`;
  2. scene có cửa sổ `.normal` đang hiện không phải lớp phủ;
  3. cách chọn cũ (active → inactive → bất kỳ), để không bao giờ trả `nil` khi còn scene.
  - Lớp phủ đánh dấu bằng protocol `AppOverlayWindow`: `FloatingHubUIWindow`, `FloatingWidgetUIWindow`, `BrowserFloatingWidgetUIWindow`, `ToastUIWindow`, `SideDrawerMenuOverlayWindow`.
  - `isMainInterface(_:)` = scene đó có đúng là `current()` không (không chỉ xét "có cửa sổ `.normal`", vì cửa sổ của PiP là lớp riêng của hệ thống).
- **`FloatingHubWindowManager`, `TTSFloatingWidgetWindowManager`, `BrowserFloatingWidgetWindowManager`, `ToastManager`**:
  - `activeWindowScene` = `AppMainWindowScene.current()`.
  - `handleSceneDidActivate` bỏ qua scene không phải scene chính.
  - Nghe `UIScene.didDisconnectNotification`: scene đang giữ cửa sổ bị ngắt (hoặc `windowScene == nil`) ⇒ chuyển cửa sổ về scene chính rồi `refreshState()` ở lượt sau (lúc ngắt, scene cũ có thể còn trong `connectedScenes`).
  - Log thường `🪟 [FloatingHub]` / `🪟 [TTSWidget]` / `🪟 [BrowserWidget]` khi chuyển scene, bỏ qua scene hoặc scene bị ngắt: vai trò, trạng thái, số scene, lớp + level từng cửa sổ (phải bật log trong Cài đặt mới thấy).
- Cùng hàm chọn scene cho `VideoPlayerPresenter.findTopViewController` (cả `VideoWatchPresenter` dùng chung), `VideoOrientationLock.activeScene`, và — ngoài brief, cùng lỗi — `SideDrawerMenuWindowManager` (ngăn kéo `…`) và `GeminiWebHiddenWindowHost` (webview ẩn).
- Không nối phiên video vào hub.
- Chuyển entry cũ nhất sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng:**
  - Đọc code + diff. `check_architecture.py` chỉ còn 1 lỗi nền (`JSDom.swift`), **0 mới**.
  - Không build tại chỗ (Windows). Chưa thử trên máy: bật PiP rồi tắt bằng ✕ (hub còn); bật PiP rồi bấm nút về app (hub còn, không có widget trong PiP); lặp lại với widget TTS và trình duyệt thu nhỏ đang hiện. Nếu vẫn mất, bật log và gửi các dòng `🪟`.

## [1.3.738] - 2026-11-05

### fix: bấm nút bỏ khỏi kệ là bỏ ngay, không hỏi lại ở mọi màn

Người dùng: *"bỏ hỏi khi bấm nút bỏ khỏi kệ (nhớ tất cả màn hình có nút này) trực tiếp bỏ khỏi kệ"*.

- **Grep mọi nút bỏ kệ**:
  - 5 chỗ có hộp "Bỏ … khỏi kệ?":
    - danh sách chương Reader chữ;
    - mục lục truyện tranh;
    - nút kệ của sheet nhấn giữ ở Kệ sách / Lịch sử;
    - Tìm trên kệ;
    - Bộ sưu tập.
  - Không hỏi sẵn từ trước:
    - nút "Trên kệ" của màn xem video;
    - nút "Đã ở kệ" của màn Chi tiết.
- **`ShelfToggleFlowModifier.toggle`**: đã ở kệ ⇒ `BookActionRunner.removeFromShelfOnly` ngay (tự toast, truyện về Lịch sử, rời bộ sưu tập, bỏ ghim — y như nút "Bỏ khỏi kệ" của hộp cũ).
  - Modifier chỉ còn sheet chọn bộ sưu tập: `shelfToggleFlow(collectionPickerBook:)`.
  - Bỏ `isConfirmingShelfRemoval` ở `ReaderChapterListView` / `ComicChapterListSheet`.
- **`ShelfView` / `ShelfSearchView(+Actions)` / `CollectionDetailView`**:
  - `.removeFromShelfOnly` gọi thẳng `removeFromShelfOnly`.
  - Bỏ hàng chờ `queuedShelfRemovalBook` / `pendingShelfRemovalBook`: chúng chỉ để bật hộp sau khi sheet nhấn giữ đóng hẳn.
- Xoá `ShelfRemovalConfirmationModifier.swift` (không còn chỗ dùng). Sửa comment nhắc tới hàng chờ cũ.
- Chuyển entry cũ nhất sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng:**
  - Đọc code + diff, grep chéo `Sources/` không còn tham chiếu tới hộp cũ. `check_architecture.py` chỉ còn 1 lỗi nền (`JSDom.swift`), **0 mới**.
  - Không build tại chỗ (Windows). Chưa thử trên máy.

## [1.3.737] - 2026-11-05

### fix: nhấn giữ phim ở Kệ và Lịch sử không còn mở trang Chi tiết

Người dùng: *"bỏ bấm vào chi tiết từ contextmenu ở kệ và lịch sử đối với video"*.

- **`BookActionSheet.canOpenDetail`**: phim (`ExtensionContentKind.resolve(packageId:) == .video`) trả `false` ⇒ chạm phần đầu (bìa + tên) của sheet nhấn giữ không mở `BookDetailView` nữa.
  - Dòng gợi ý "?" và trait nút của phần đầu đổi theo (không còn "Chạm phần trên để xem chi tiết").
  - Nhấn giữ để ghim, nút Sửa thông tin, nút Kệ và mọi hàng khác giữ nguyên.
  - Sheet dùng chung ⇒ áp cả ở Bộ sưu tập và Tìm trên kệ.
- Đảo một phần quyết định của 1.3.735 (giữ "Xem chi tiết" cho phim làm lối vào trang Chi tiết kiểu cũ). "Mở trang chi tiết" ở ⋮ của thẻ đề xuất trên màn xem vẫn giữ.
- Chuyển entry cũ nhất sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng:**
  - Đọc code + diff. `check_architecture.py` chỉ còn 1 lỗi nền (`JSDom.swift`), **0 mới**.
  - Không build tại chỗ (Windows). Chưa thử trên máy.

## [1.3.736] - 2026-11-05

### fix: màn xem video: đề xuất và bình luận không kẹt khi cuộn nhanh, khai rõ giá trị đầu của state

Rà lại phần 2–3 của màn xem video (1.3.734–735) trước khi đẩy lên.

- **Đề xuất kẹt "Không có đề xuất nào"**:
  - Nhóm đề xuất tải trang 1 bằng `.task` trong `LazyVStack`. Cuộn nhanh qua nhóm thì `.task` bị huỷ.
  - `PaginatedNovelLoader` coi lượt bị huỷ là "không lỗi, không mục", còn cờ đã bắt đầu chặn mọi lần thử lại.
  - Sửa: `VideoWatchSuggestSection` tải bằng `Task` riêng trong `onAppear`, rời màn không huỷ.
- **Bình luận tải lại mỗi lần cuộn qua**: `VideoWatchCommentsCard` nhớ nhóm đã tải xong (thành công hoặc lỗi thật). Lượt bị huỷ thì lần hiện sau tải tiếp.
- **Lỗi biên dịch của 1.3.734** (CI: "unable to type-check this expression in reasonable time"): chip nhóm ở dải tập (`VideoWatchEpisodeStrip.chip`) gộp màu chọn / màu thường trong một biểu thức ⇒ tách màu, nhãn, trait ra hằng có kiểu rõ + hàm vẽ nhãn riêng.
- **Khai rõ `= nil`** cho các `@State` optional mới (`VideoPlayerScreen`, `VideoWatchActionRow`, `VideoWatchDetailsView`, `VideoWatchRouteView`), theo cách viết của repo. Thiếu giá trị đầu, thuộc tính `private` có thể làm init tự sinh thành `private` ⇒ chỗ dựng view ở file khác không gọi được.
- Chuyển entry cũ nhất sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng:**
  - Đọc code + diff. `check_architecture.py` chỉ còn 1 lỗi nền (`JSDom.swift`), **0 mới**.
  - Không build tại chỗ (Windows). Chưa thử trên máy.

## [1.3.735] - 2026-11-05

### feat: mọi lối vào phim mở thẳng màn xem phát dọc thay cho trang Chi tiết

Phần 3 (cuối) của plan "Màn xem video kiểu trình phát dọc" (anh Bửu đã duyệt): bấm phim ở đâu cũng vào màn xem, phát dọc ngay theo công tắc "Tự phát khi mở phim". Truyện chữ / truyện tranh giữ `BookDetailView` như cũ.

- **`ContentDetailRouter`** (mới, `Views/ContentRouting/`): loại nội dung suy từ tiện ích lúc bấm (`ExtensionContentKind.resolve(packageId:)`).
  - Video ⇒ `VideoWatchPresenter.present(VideoWatchRequest(...))` với tên / bìa của item, trả `true`.
  - Loại khác ⇒ `false`, chỗ gọi đẩy `BookDetailView` như cũ.
  - Id phim không lấy từ chỗ gọi (mỗi màn tự chế một kiểu) mà do `VideoWatchRequest.resolveBookId` phân giải.
- **`ContentDetailLink`** (mới): thay `NavigationLink(destination: BookDetailView(...))` của item danh sách — phim ⇒ `Button` mở màn xem, loại khác ⇒ `NavigationLink` y như cũ.
- **Chỗ gọi đã đổi** (grep chéo mọi `BookDetailView(` trong `Sources/`):
  - Khám phá: `openNovel` (tab danh mục `DiscoveryCategoryTabView` + tab "Trang chủ" `ExploreSectionsView`) và nhập từ trình duyệt của nguồn (`showImportedBook`).
  - Tìm nhiều nguồn (`SearchView`): ô kết quả. Chế độ đổi nguồn giữ nguyên.
  - Tìm một nguồn (`SearchSingleSourceResultsView`): hàng danh sách (phim là nút thường, không mũi tên `>`) và ô lưới.
  - Danh sách thể loại (`CategoryNovelsListView`), Đề xuất trong Chi tiết (`SuggestRowView`).
  - Nhập từ trình duyệt / "Từ URL" ở Kệ (`ShelfView+ImportEntry`), ở Cấu hình tiện ích (`ExtensionConfigView+Browser`), ở Chi tiết (`BookDetailView` `onImport`, +3 dòng, còn dưới baseline 1201).
- **Kệ / Lịch sử / Bộ sưu tập / Tìm trên kệ / mở lại lúc khởi động / chạm tập ở Chi tiết** (qua router `BookContentDestination`):
  - Nhánh `.video` thành `VideoWatchRouteView` (mới): cùng màn xem, trong `fullScreenCover` sẵn có, model dựng một lần từ `VideoWatchRequest(launch:)` (id `Book` thật, tập / giây của launch).
  - Tự phát theo công tắc như mọi lối vào. Lượt mở lại lúc khởi động vẫn dừng sẵn.
  - Màn xem trong cover đang hiện bìa mà hub / PiP mở lại phim đang chạy ⇒ đổi chính màn đó sang phim đang chạy (`VideoWatchPresenter.presentRunningSession`), không chồng màn mới.
- **Giữ nguyên `BookDetailView`**: nhấn giữ "Xem chi tiết" ở Kệ / Bộ sưu tập / Tìm trên kệ (lối duy nhất xem trang chi tiết đầy đủ kiểu cũ cho phim), Chi tiết mở từ Reader / màn truyện tranh, và "Mở trang chi tiết" ở ⋮ của thẻ đề xuất trên màn xem.
- `VideoPlayerScreen(launch:)` không còn chỗ gọi, giữ lại.
- Chuyển entry cũ nhất sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng:**
  - Đọc code + diff; grep chéo `BookDetailView(`, `VideoPlayerScreen(`, `navigateToImportedBook = true`.
  - `check_architecture.py` chỉ còn 1 lỗi nền (`JSDom.swift`), **0 mới**.
  - Không build tại chỗ (Windows). Chưa thử trên máy.

## [1.3.734] - 2026-11-05

### feat: giao diện màn xem video kiểu trình phát dọc, nút Home và mở lại từ hub

Phần 2 của plan "Màn xem video kiểu trình phát dọc" (anh Bửu đã duyệt). Kèm hai việc dọn của phần 1 (1.3.733).

- **Id truyện chữ / truyện tranh trả về như cũ** (sửa rủi ro của 1.3.733):
  - `BookDetailView.resolveBookId` chỉ dùng id xác định theo (tiện ích, link) cho **video**.
  - Truyện chữ / tranh chưa lưu lại nhận UUID ngẫu nhiên một lần mỗi màn (`fallbackBookId`), hoặc chính id caller khi nó dạng UUID.
  - Lý do: xoá rồi thêm lại cùng truyện sẽ dùng lại id cũ. Hàng đợi xoá lỗi của `BookStorageManager` (`failed_file_deletions_queue`, `failed_chapterstore_deletions_queue`) còn mục của lần xoá trước thì lần mở app sau có thể xoá nhầm file / mục lục của bản mới.
  - **Rủi ro còn lại, cố ý giữ**: video vẫn dùng id xác định (để mở cùng phim từ nhiều lối không ra hai `Book`), nên rủi ro trên vẫn còn với phim. Chỉ xảy ra khi lần xoá phim trước **lỗi file** rồi phim được thêm lại trước lần mở app kế tiếp. Lối nhập từ trình duyệt vốn đã dùng id xác định từ trước.
- **Mở lại từ hub / PiP dùng giao diện mới**:
  - `VideoPlayerPresenter` chuyển sang `VideoWatchPresenter.present(VideoWatchRequest(launch: session.launch))` (có `completion` cho PiP).
  - Id lấy nguyên từ phiên ⇒ màn gắn ngay vào phim đang chạy, không tự phát lại.
  - Màn xem đang hiện bìa phim B mà hub mở lại phim A ⇒ đóng màn cũ rồi mới mở, **không chồng** trình phát.
  - Lối trình bày cũ chỉ còn làm dự phòng khi phiên thiếu `modelContainer`.
- **Phần dưới khung phim** (`VideoWatchDetailsView`, thay `VideoPlayerDetailsView` ở màn xem; thư mục mới `Views/VideoPlayer/Watch/`):
  - **Nhãn thể loại** `#KiếmHiệp #CổTrang` trên tên phim (`VideoWatchTitleBlock`): tối đa 4 nhãn, một dòng, bỏ khoảng trắng sau `#`, dài thì cắt đuôi. Thể loại không có script chỉ là chữ.
  - Tên phim + dòng meta `nguồn · N tập · tác giả` + "…thêm" ⇒ sheet **Thông tin** (`VideoWatchInfoSheet`: bìa, tác giả, nguồn, số tập, đủ chip thể loại, giới thiệu đầy đủ).
  - **Hàng nút** viên thuốc 38pt (`VideoWatchActionRow`):
    - **Trên kệ**: bật = `setOnShelf` (phim chưa lưu ⇒ tạo `Book` trên kệ cùng mục lục đủ) rồi mời chọn bộ sưu tập. Tắt = `removeFromShelf` (phim về Lịch sử). **Không** dùng `deleteBookAsync`, cũng không `setOnShelf(false)` (hạ cả cờ Lịch sử).
    - **Tải**: sheet tải nhiều tập của **phim này** (`TaskOptionsSheet`), phim chưa lưu thì tạo trên kệ như Chi tiết.
    - **Đổi nguồn**: `SearchView` chế độ đổi nguồn trong sheet; xong thì đóng sheet rồi đóng màn.
    - **Chia sẻ**: link chi tiết tuyệt đối (ghép host), không có link http(s) thì ẩn.
    - Phim nhập từ file không có Tải / Đổi nguồn.
  - **Giới thiệu** 3 dòng, chạm ⇒ sheet Thông tin.
  - **Lưới Server** 3 cột (`VideoPlayerOptionGrid` + `VideoServerOptions`, mới, dùng chung với ngăn kéo ⋯). Chỉ hiện khi phiên đang phát đúng phim này. **Chất lượng không hiện** ở màn xem.
  - **Dải tập** (`VideoWatchEpisodeStrip`): chip nhóm (chỉ khi ≥ 2 nhóm, chọn sẵn nhóm chứa tập đang xem) + dải ngang ô số tập + "Tất cả ›" ⇒ sheet lưới **6 cột** (`VideoWatchEpisodeSheet`), dấu ⬇ cho tập đã tải (`VideoOfflineLibrary` theo id phim của màn).
  - **Bình luận** (`VideoWatchCommentsCard`): xem trước 2 bình luận, chạm ⇒ sheet `AllCommentsView` (có `NavigationStack` riêng).
  - **Đề xuất kiểu bảng tin** (`VideoWatchSuggestFeed` / `Section` / `Card`):
    - Mỗi nhóm đề xuất một tiêu đề, xếp liền nhau. Nhóm tải khi cuộn tới; nhóm **cuối** nạp thêm trang khi tới thẻ cuối, nhóm giữa một trang. Bỏ chính phim đang xem.
    - Thẻ: ảnh 16:9 rộng hết màn (bìa dọc đặt giữa trên nền mờ), nhãn `tag` góc ảnh; dưới là icon nguồn tròn, tên 2 dòng, dòng phụ `nguồn · tác giả / mô tả`, và ⋮.
    - ⋮ › **Thêm vào kệ** (`VideoWatchShelfAdder`, mới: tải chi tiết + đủ mục lục rồi tạo `Book` trên kệ; đã có thì bật cờ kệ) / **Mở trang chi tiết**.
    - Bấm phim ⇒ `replace(with:)` đổi phim **ngay tại màn** (cuộn về đầu).
  - Chi tiết lỗi ⇒ một dòng báo + Thử lại + "Mở link lỗi" (trình duyệt riêng, thử lại bằng `VideoWatchModel`, không đụng phiên phát).
- **Nút Home nổi** (`.floatingAddButton(systemImage: "house")`, chỉ trên màn xem):
  1. Phim **đang phát** là 18+ (`RepositoryFilterPolicy.isNsfwBook`) ⇒ dừng hẳn. Còn lại ⇒ thu nhỏ, phát tiếp ở hub.
  2. Công tắc NSFW đang bật ⇒ tắt.
  3. Đóng màn (và trang phụ của màn nếu có), sang tab **Khám phá**, về **trang gốc**.
  - Báo qua `MainTabNavigationEvents` (AsyncStream mới, `Views/Common/MainTabBar/`), không thêm notification chuỗi. `MainTabView` tự tạo lại tab Khám phá khi tab đó đang có trang đẩy vào (`tabHasPushedPages`, mới — không bỏ qua khi có màn phủ như `shouldResetTab`).
- **Lối rời màn xem** (`VideoWatchExit`): thể loại, Chi tiết của đề xuất, Home, đổi nguồn xong.
  - `VideoPlayerScreen.leave(then:)` chạy trang tiếp theo **sau khi** màn đã đóng (`onDisappear`).
  - **Quyết định cần anh xác nhận**: danh sách thể loại và Chi tiết mở từ màn xem hiện ở **sheet lớn** (`VideoWatchPresenter.presentPage`, vuốt xuống để đóng), không đẩy vào tab đang mở. Các tab dùng `NavigationStack` không `path` nên không đẩy trang được từ ngoài cây tab.
- **Gộp thuật toán chia nhóm tập** thành `VideoEpisodeGrouping` (mới), dùng cho lưới tập trình phát, màn xem và tab Mục lục của Chi tiết. `Group.id` = vị trí **sau khi** bỏ nhóm rỗng: bản cũ đánh số trước khi bỏ nên lệch khi hai section liền nhau. `VideoEpisodeGridView` thêm `columnCount` + `downloadedIndexes`.
- **Đổi nguồn dừng phim trước**: `SearchView+SourceChange` dừng `VideoPlaybackSession` nếu đang phát truyện cũ, trước khi chạy `BookSourceChangeCoordinator`. Áp cho mọi lối đổi nguồn, kể cả từ Chi tiết.
- **Bấm ▶ không bị "dừng sẵn"**: tự tay bấm phát bỏ lệnh dừng sẵn của lượt mở lại lúc khởi động (`consumePausedVideoStart`). Chỉ lượt tự phát mới giữ lệnh đó.
- Chuyển entry cũ nhất sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng:**
  - Đọc code + diff; grep chéo mọi chỗ gọi `VideoEpisodeGridView(`, `leave(`, `SearchView(`.
  - `check_architecture.py` chỉ còn 1 lỗi nền (`JSDom.swift`), **0 mới**; file mới ≤ 400 dòng, mỗi file 1 type.
  - Không build tại chỗ (Windows). Chưa thử trên máy.

## [1.3.733] - 2026-11-05

### feat: nền màn xem video: định danh phim, tải chi tiết + mục lục, tự phát và lưới tuỳ chọn trình phát

Người dùng: *"thiết kế lại màn chi tiết cho video (kiểu như app youtube), bấm vào thì sẽ chiếu dọc luôn"*; duyệt plan 3 phần. Đây là **phần 1** (nền); phần 2 = giao diện dưới khung phim + nút Home, phần 3 = đổi các lối vào. Chưa có lối vào nào gọi màn mới.

- **`VideoWatchRequest`** (mới, `Services/Video/Watch/`): dữ liệu lúc bấm phim (tiện ích, link chi tiết, nguồn, host, tên/bìa của item; `init(book:)`, `init(launch:)` cho `Book` đã có).
  - **Một quy tắc định danh** cho mọi lối vào: `Book` cùng (link, tiện ích) ⇒ id đó (nhiều bản ⇒ bản xem gần nhất); id caller là `Book` có thật ⇒ giữ; còn lại ⇒ id **xác định** `BookIdUtils.make`. Mở cùng phim từ Khám phá rồi từ Tìm không ra hai `Book`.
  - `BookDetailView.resolveBookId` dùng chung quy tắc này (bỏ `fallbackBookId`). **Đổi cả truyện chữ / truyện tranh**: truyện mới mở từ Chi tiết trước đây nhận UUID ngẫu nhiên mỗi lần mở màn (hoặc chính link khi link có "-" và dài > 30 ký tự), nay nhận id xác định theo (tiện ích, link). Truyện đã lưu không đổi id.
- **`VideoWatchModel`** (mới, `@MainActor @Observable`, một phiên mỗi màn xem):
  - Id chốt trong `init`, trước mọi lần gọi nguồn (`SourceRuntimeContext`, cache chi tiết).
  - Phim đã có `Book` + mục lục trên máy ⇒ hiện và phát được ngay (kể cả ngoại tuyến / chỉ còn bản tải), rồi làm mới từ nguồn.
  - Chi tiết: cache 5 phút → `BookDetailLoader.fetchDetail`, chạy song song với mục lục; lỗi chi tiết không chặn phát.
  - Mục lục **đủ**: `fetchFirstPageTOC` + `fetchRemainingPages` (trang 1 hiện ngay, phát khi đủ). Lỗi khi máy chưa có bản nào ⇒ lỗi + "Mở link lỗi" (`SourceErrorLink`, dự phòng trang mục lục đang tải → link chi tiết).
  - `Book` chỉ tạo khi **bấm phát** (`isOnShelf: false`, `isHistory: false` — Lịch sử bật ở lần lưu tiến độ đầu), cùng đường `startReading` của Chi tiết (`saveChapterList(.replaceFullTOC)`), ghi xong mới `session.open` (tránh đua với `ensureHistoryBook`). Chi tiết về sau khi đã tạo ⇒ điền nốt metadata cho `Book` vừa tạo (`updateBookMetadata`); `Book` có sẵn thì không đè.
  - `Book` có sẵn mà nguồn **thêm tập ở cuối** ⇒ ghi lại đủ và phiên phát đang chạy phim đó nhận danh sách tập mới (`VideoPlaybackSession+Watch.adoptRefreshedEpisodes`, mới). Nguồn đổi thứ tự / bớt tập ⇒ giữ bản đã lưu (bản tải, tiến độ, server đã nhớ theo chỉ số tập).
  - Màn biến mất (kể cả bị đóng bằng code) ⇒ huỷ lượt tải / chuẩn bị phát, không tự mở phim khi không còn màn.
  - `play(episodeIndex:)` dựng `BookContentLaunch` (thêm trường `host`, mặc định `nil`, mọi chỗ khởi tạo cũ không đổi; phiên phát dùng sau `Book.host`) rồi `VideoPlaybackSession.shared.open`. Ghi "Mở lại truyện đọc gần nhất" như `BookContentDestination`.
  - Có sẵn `ensureBook(isOnShelf:)` và `replace(with:)` (đổi phim tại màn) cho phần 2.
- **`VideoWatchPresenter`** (mới): mở màn xem bằng `VideoPlayerHostingController` `.overFullScreen` như `VideoPlayerPresenter` (dùng chung `findTopViewController`), gắn lại màu nhấn + `modelContainer`.
- **`VideoPlayerScreen(watch:onDismiss:)`** (init mới; hai init cũ giữ nguyên):
  - Phiên phát chưa chạy phim của màn (đang tải, tắt tự phát, phim khác chạy nền) ⇒ khung phim là **`VideoWatchPosterView`** (mới): bìa đặt giữa trên nền mờ của chính bìa, nút ▶ giữa, nhãn "Xem tiếp Tập N · m:ss" / "Tập 1"; đang tải ⇒ vòng xoay; lỗi ⇒ lớp phủ lỗi chung.
  - Lúc đó màn **không** gắn vào phiên: phim khác vẫn chạy nền, hub vẫn hiện nó, ⌄/✕ chỉ đóng màn. Phiên chuyển sang phim của màn mới gắn.
  - Phần dưới khung phim lúc chưa phát tạm là tên phim + lưới tập của model (phần 2 thay).
- **Công tắc "Tự phát khi mở phim"** (`VideoAutoplayPolicy`, khoá `videoAutoplayOnOpen`, mặc định bật): hàng ở Cài đặt › Đọc & Nghe (cạnh "Mở lại truyện đọc gần nhất", có giải thích ở nút "?") và hàng đầu ngăn kéo ⋯ của trình phát.
  - Bật ⇒ phát ngay khi có mục lục, đúng tập xem dở; phim khác đang chạy nền bị dừng.
  - Tắt ⇒ bìa + ▶; phim khác đang chạy nền chạy tiếp tới khi bấm ▶.
- **Ngăn kéo ⋯ của trình phát**: Khung hình / Server / Chất lượng đổi từ hàng chọn sang **lưới 3 cột** `VideoPlayerOptionGrid` (mới, dùng chung): ô đang chọn chữ màu nhấn + nền nhấn mờ 18% + viền 60%, ô thường nền xám tối, tên dài cắt "…". Bấm là áp dụng, ngăn kéo vẫn mở. Điều kiện hiện từng nhóm giữ nguyên.
  - `SideDrawerOptionRow` không còn chỗ dùng (để nguyên).
- Chuyển entry cũ nhất sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng:**
  - Đọc code + diff; grep chéo mọi chỗ khởi tạo `BookContentLaunch` (chỉ `BookContentDestination`) và `fallbackBookId`. `check_architecture.py` chỉ còn 1 lỗi nền (`JSDom.swift`), **0 mới**.
  - Không build tại chỗ (Windows). Chưa thử trên máy.

## [1.3.732] - 2026-11-05

### fix: mở app là kiểm tra bản mới, bấm dòng phiên bản ở Cài đặt để kiểm tay

Người dùng: *"1.3.728 tôi mở nhưng lại không báo cập nhật ver mới cho tôi"*. Chốt: kiểm mỗi lần mở app, thêm kiểm tay ở dòng phiên bản.

- **Nguyên nhân** (đối chiếu giờ đăng release với code 1.3.727):
  - `checkIfNeeded()` giãn cách **6 giờ cho mọi lần**.
  - Mở 1.3.728 (1155, đăng 15:51) thì lần kiểm thấy nguồn cũng là 1155 ⇒ không báo, nhưng vẫn ghi `appUpdateLastCheckAt`.
  - 1.3.730 (1156) đăng 16:23 ⇒ phải chờ 6 giờ mới tới lần kiểm kế.
  - Lần kiểm "đang dùng bản mới nhất" không ghi log nên không soát được trên máy.
- **`AppUpdateRepository`**:
  - `checkOnLaunch()`: mở app (`.task` của `MainTabView`) là kiểm, **không giãn cách**.
  - `checkOnForeground()`: quay lại app kiểm nếu lần trước đã quá **30 phút** (thay 6 giờ).
  - `checkNow() -> CheckOutcome` (`upToDate` / `updateAvailable` / `failed`): kiểm tay.
  - Gọi dồn khi đang có lượt đọc nguồn thì chờ chung lượt đó, không đọc chồng.
  - `isChecking` thành thuộc tính quan sát được.
  - Mỗi lần kiểm đều ghi log: "✅ Đang dùng bản mới nhất … (nguồn: …)" / "⬆️ Có bản mới …" / "❌ Không đọc được nguồn cập nhật".
- **Cài đặt › Thông Tin**: dòng "Phiên bản ứng dụng" bấm được ⇒ kiểm ngay (vòng xoay thay số version khi đang kiểm).
  - Kết quả: toast "Đang dùng bản mới nhất", hoặc "Có bản mới 1.3.NNN" + mở sheet bản mới, hoặc "Không kiểm tra được bản mới".
- **Lưu ý**: bản 1.3.728 / 1.3.730 đang cài vẫn giữ giãn cách 6 giờ cũ; từ bản này trở đi mới kiểm khi mở app.
- `CLAUDE.md` / `AGENTS.md`: sửa đoạn "Báo có bản mới trong app".
- Chuyển entry cũ nhất sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng:**
  - Đọc code + diff; `check_architecture.py` chỉ còn 1 lỗi nền (`JSDom.swift`), **0 mới**.
  - Không build tại chỗ (Windows). Chưa thử trên máy.

## [1.3.731] - 2026-11-05

### feat: nhập phim nhiều tập từ file ZIP, mỗi video trong file là một tập

Người dùng: *"Hãy cho phép nhập video từ zip, tất cả video trong đó là các tập của 1 phim"*.

- **Trước đây**: một file `.zip`/`.cbz` ở Kệ sách › Nhập truyện › Từ file luôn đi luồng truyện tranh ⇒ ZIP chỉ có video báo "Không tìm thấy ảnh nào trong file". Nhập phim chỉ nhận chọn thẳng các file MP4/MOV/M4V.
- **`LocalMediaArchiveImporter`** (mới, `Services/Import/Media/`): giải nén **một lần** rồi mới quyết định.
  - Phần chuyển file vào thư mục làm việc, kiểm chỗ trống (cỡ file + 50 MB), `BackupZipArchive.extract`, xoá bản nén: **chuyển nguyên** từ đầu `LocalComicImporter.prepare`, không đổi hành vi.
  - Có ít nhất một file MP4/MOV/M4V ⇒ **một phim**. Ảnh lẫn trong ZIP bị bỏ qua.
  - Không có video ⇒ truyện tranh như cũ.
  - Lỗi bất kỳ bước nào ⇒ xoá cả thư mục làm việc.
- **`LocalVideoImporter.plan(fromExtracted:workDirectory:archiveName:)`** (mới):
  - Tập = mọi file MP4/MOV/M4V ở mọi cấp thư mục, xếp theo đường dẫn tên tự nhiên (từng cấp, "Tập 2" trước "Tập 10").
  - Tên tập = tên file bỏ đuôi. Tên phim mặc định = tên file ZIP bỏ đuôi.
  - Cùng lớp an toàn với bước quét ảnh: có symlink ⇒ huỷ; bỏ file ẩn, `__MACOSX/`, file nằm ngoài thư mục giải nén.
  - Video không phát được (MKV, AVI, WEBM, FLV, WMV, TS, 3GP, MPG, RMVB, VOB…):
    - Có cả file phát được ⇒ bỏ qua, sheet hiện "Bỏ qua N file không hỗ trợ (chỉ MP4/MOV/M4V)".
    - Chỉ toàn file không phát được ⇒ báo lỗi "File nén chỉ có video … — app chỉ phát được MP4/MOV/M4V".
  - File đã nằm trong thư mục làm việc ⇒ `commit` có sẵn **chuyển** thẳng vào `VideoOfflineStore`, không chép bản thứ hai.
- `LocalComicImporter.prepare(pickedURL:)` → `plan(fromExtracted:workDirectory:fileName:)` (chỉ còn quét ảnh). Luật chương / ảnh / thông báo lỗi giữ nguyên.
- `LocalMediaImportRoute`: case `.comic` đổi tên `.archive` (phim hay truyện tranh chỉ biết sau khi giải nén). EPUB đội lốt `.zip` vẫn đi luồng chữ.
- `LocalVideoImportPlan` thêm `skippedCount` (mặc định 0).
- `ShelfView+MediaImport`: nhánh `.archive` mở sheet "Nhập phim" có sẵn (`LocalVideoImportSheet`) hoặc sheet truyện tranh theo kết quả.
- `CLAUDE.md` / `AGENTS.md`: mục Comic & Video thêm dòng nhập từ file.
- Chuyển entry cũ nhất sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng:**
  - Đọc code + diff; grep chéo mọi chỗ gọi `LocalComicImporter.prepare` / case route (chỉ `ShelfView+MediaImport`). `check_architecture.py` chỉ còn 1 lỗi nền (`JSDom.swift`), **0 mới**.
  - Không build tại chỗ (Windows).
  - Chưa thử trên máy:
    - ZIP nhiều tập MP4: thứ tự tập, tên phim, phát offline, ảnh bìa.
    - ZIP truyện tranh vẫn như cũ.
    - ZIP lẫn MKV.
    - ZIP lớn: cần chỗ trống cho cả bản nén lẫn bản giải nén lúc giải nén.

## [1.3.730] - 2026-11-05

### feat: màn Dung lượng hiện ngay lần đo gần nhất, đo lại ngầm kể cả khi đã thoát màn

Người dùng: *"mỗi lần vào dung lượng đều phải chờ à?"*, rồi *"ngoài ra tôi vào rồi thoát ra thì vẫn đo ẩn đi nhé"*.

- **Trước đây**: kết quả đo là `@State` của `StorageUsageView`. Mỗi lần mở màn phải đo lại cả cây thư mục từ đầu (có thể vài giây khi có phim HLS hay nhiều ảnh comic). Thoát màn là huỷ luôn lượt đo.
- **`StorageUsageRepository`** (mới, `Services/Storage/`, `@MainActor @Observable`, nguồn sự thật duy nhất của số liệu):
  - Giữ lần đo gần nhất và lưu xuống máy (`UserDefaults` `storageUsageLastSnapshot`, JSON) ⇒ còn sau khi tắt app.
  - `refresh()` chạy lượt đo bằng `Task` của repository, **không** gắn vòng đời màn ⇒ thoát màn giữa chừng vẫn đo tiếp và lưu kết quả. Đang có lượt chạy thì bỏ qua, không đo chồng.
  - `refreshAfterChange()` (sau khi xoá): chờ lượt đang chạy rồi đo một lượt mới, chờ xong.
- `StorageUsageSnapshot` thêm `measuredAt`, cùng `Entry` và `StorageUsageCategory` thành `Codable`.
- **Màn Dung lượng**:
  - Mở màn ⇒ hiện ngay số cũ kèm dòng "Đo lúc 14:32" (khác ngày thì thêm "dd/MM"), rồi đo lại ngầm. Đang đo thì nút ↻ thành vòng xoay, dòng giờ thêm "· đang đo lại"; đo xong số tự cập nhật.
  - Chỉ lần đầu tiên (chưa có số cũ) mới hiện vòng chờ thay cho số.
  - Xoá vẫn đo lại ngay rồi mới báo số đã giải phóng.
- `CLAUDE.md` / `AGENTS.md`: đoạn màn Dung lượng ghi thêm `StorageUsageRepository`.
- Chuyển entry cũ nhất sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng:**
  - Đọc code + diff; `check_architecture.py` chỉ còn 1 lỗi nền (`JSDom.swift`), **0 mới**.
  - Không build tại chỗ (Windows).
  - Chưa thử trên máy: mở lại màn thấy số ngay, thoát giữa lúc đo rồi vào lại thấy số mới.

## [1.3.729] - 2026-11-05

### fix: tin Telegram và ghi chú bản bỏ dòng commit trùng tên

Người dùng chọn *"Có, lọc trùng"*. Lượt build 1155 liệt kê 5 dòng: commit sửa lỗi biên dịch (`705bbf3e`) dùng lại đúng message của commit hỏng (`71aaf405`) theo quy trình sửa CI. Vì vậy dòng "feat: màn Dung lượng…" hiện hai lần.

- `Scripts/ci/telegram_commit_summary.py`: `read_subjects` bỏ subject trùng (so nguyên văn), giữ thứ tự cũ → mới, giữ lần đầu. Áp cho cả tin Telegram lẫn ghi chú release / `apps.json`. Số "N commit" đếm sau khi lọc.
- Bước `Collect Commit List` của CI không đổi (log vẫn in đủ danh sách thô).
- Ghi chú của release `build-1155` đã đăng giữ nguyên; từ lượt build sau mới lọc.
- `CLAUDE.md` / `AGENTS.md`: đoạn "Tin Telegram + ghi chú release liệt kê mọi commit" ghi thêm việc bỏ dòng trùng.
- Chuyển entry cũ nhất sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng:**
  - Tại chỗ với đúng danh sách của lượt 1155 (API so sánh `a7a5aba2...705bbf3e`, 5 dòng) ⇒ tin "💬 4 commit:" không trùng, ghi chú 4 dòng.
  - Commit này chỉ đổi `Scripts/` + tài liệu ⇒ không kích hoạt build; lượt build kế tiếp dùng bản lọc.

## [1.3.728] - 2026-11-05

### feat: màn Dung lượng xem app chiếm bao nhiêu theo loại dữ liệu, xoá cache ảnh, file xuất và log

Người dùng: *"tôi muốn thêm kiểm tra dung lượng đã dùng trên máy có là được không?"*. Chốt theo mockup: xoá mục an toàn (có hỏi xác nhận), chưa cần xem theo từng truyện.

- **Cài đặt › Thư Viện** thêm hàng **Dung lượng** (icon `cylinder.split.1x2` như mockup), đặt trên "Sao lưu & khôi phục dữ liệu". Hàng không hiện số: đo cả cây thư mục mỗi lần mở Cài đặt là tốn.
- **Màn Dung lượng** (`StorageUsageView`, trang đẩy vào, tiêu đề giữa, nút ↻ đo lại):
  - Thẻ đầu: "App đang dùng" + số lớn. Thanh chia theo tỉ lệ: 3 loại lớn nhất màu riêng (teal/tím/cam, không dùng màu nhấn), còn lại xám. Dòng "Máy đã dùng X / Y · Còn trống Z".
  - Danh sách panel (`.bookListPanelRow()`), xếp lớn → nhỏ, bỏ loại 0 byte.
  - Ba loại xoá được có nút chữ đỏ **Xoá** + `confirmationDialog` kèm lời nhắc; xoá xong đo lại và toast "Đã xoá … (số đã giải phóng)".
- **`Services/Storage/`** (mới):
  - `StorageUsageCategory`: 15 loại theo đúng thư mục app ghi: `books/`, `videos/`, `comics/`, `Caches/comic_images/`, `chapters/`, `translate/`, `covers/`, `extensions/` + `extension_store/`, `FreeBook/`, `adblock/`, `backups/`, `library.db*`, `Documents/Exports/`, `app_logs*`, Khác.
  - `StorageUsageScanner`:
    - Đo dung lượng thật trên đĩa (`totalFileAllocatedSize`), đếm cả file ẩn, không theo symlink. `BackupPaths.directorySize` giữ nguyên cho Sao lưu.
    - **Khác** = cả thư mục nhà của app trừ các loại đã liệt kê ⇒ tổng khớp dung lượng thật.
    - Dung lượng máy qua `volumeAvailableCapacityForImportantUsage` / `volumeTotalCapacity`.
  - `StorageUsageSnapshot`: kết quả bất biến.
  - `StorageUsageCleaner`: chỉ gọi đường xoá có sẵn của từng owner.
- **Đường xoá**:
  - `ComicImageLoader.clearDiskCache()` → `ComicImageDiskCache.removeAllAndWait()` (mới, chờ xoá xong; `removeAll()` cũ dùng chung thân).
  - `DownloadManager.clearFinishedExportTasks()` (mới, `@MainActor`): như `clearFinishedTasks()` nhưng **chỉ tác vụ xuất** đã xong/lỗi/huỷ — xoá hàng + file của chúng. Không còn tác vụ xuất nào chạy ⇒ dọn mục mồ côi trong `Exports/`. Đợi xoá file xong, không tự báo toast.
  - `AppLogger.shared.clear()` (có sẵn).
- `CLAUDE.md` / `AGENTS.md`: mục lưu trữ ghi thêm "thêm thư mục dữ liệu mới thì thêm vào `StorageUsageCategory`".
- Chuyển entry cũ nhất sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng:**
  - Đọc code + diff; `check_architecture.py` chỉ còn 1 lỗi nền (`JSDom.swift`), **0 mới**. `DownloadManager+TaskStore.swift` 387/400 dòng.
  - Không build tại chỗ (Windows).
  - Chưa thử trên máy: số liệu so với Cài đặt iOS (app chạy trong LiveContainer nên iOS tính chung vào LiveContainer), xoá ba loại, bản đang xuất không bị xoá.

## [1.3.727] - 2026-11-05

### feat: báo có bản cập nhật mới trong app, dải báo ở Kệ và hàng ở Cài đặt

Người dùng: *"có thể thì thông báo có bản cập nhập mới trong app để user biết"*. Chốt theo mockup bản 4:
- Dải báo không có nút cập nhật; phải bấm vào xem thay đổi.
- Icon cập nhật kiểu mockup (`arrow.down.square`), không dùng chuông, không ghi vào Trung tâm thông báo, không ghi số thay đổi.
- Thêm hàng ở Cài đặt và chấm đỏ tab Cài Đặt.
- Kiểm tra khi mở app và khi quay lại app, giãn cách 6 giờ.
- Giữ nút "Mở LiveContainer" để thử trên máy.

- **`Services/AppUpdate/`** (mới, không `import SwiftUI`):
  - `AppUpdateSourceClient`: đọc `apps.json` ở nhánh `source` (raw GitHub, timeout 15 s, bỏ cache cục bộ). Lấy `apps[0].versions[0]`.
  - `AppUpdateInfo`: `version`, `buildNumber`, `date`, `notes` (mỗi commit một dòng, bỏ tiền tố `- `).
  - `AppUpdateRepository` (`@MainActor @Observable`, nguồn sự thật duy nhất):
    - Có bản mới ⇔ số build của nguồn > `CFBundleVersion` đang chạy. Bản build tay (số build 1) luôn thấy báo.
    - `checkIfNeeded()` giãn cách 6 giờ (`appUpdateLastCheckAt`). Bản đọc được cuối lưu ở `appUpdateLatestJSON`. Lỗi ⇒ log `❌ [AppUpdate]`, giữ kết quả cũ.
    - Ẩn / bỏ qua / đã xem nhớ **theo số build** (`appUpdateDismissedBuild`, `appUpdateSkippedBuild`, `appUpdateSeenBuild`) ⇒ bản mới hơn nữa ra là báo lại.
- **Dải báo Kệ** (`AppUpdateBanner`, dưới dải "mất nguồn", chỉ tab Kệ sách):
  - Dòng "Có bản mới 1.3.NNN · xem thay đổi ›" + ×, cùng kiểu panel `MissingSourceRebindBanner`.
  - Bấm ⇒ sheet. × ⇒ ẩn tới bản sau.
- **Sheet** (`AppUpdateSheet`):
  - Tiêu đề + "bản mới · đang dùng".
  - Danh sách thay đổi.
  - "Cách cập nhật: Mở LiveContainer › Sources › Refresh › Install, chọn thay app cũ để giữ dữ liệu".
  - Nút **Mở LiveContainer** và **Bỏ qua bản này**. Mở sheet ⇒ đánh dấu đã xem.
- **Cài đặt › Thông Tin**: hàng "Có bản mới 1.3.NNN" (chấm đỏ khi chưa xem) mở cùng sheet. Hàng vẫn còn sau khi bấm × ở Kệ, chỉ mất khi bỏ qua hoặc đã lên bản đó.
- **Tab Cài Đặt** (`MainTabBar`): chấm đỏ 8pt khi có bản mới chưa xem. Badge chương mới của tab Kệ giữ nguyên.
- **Kích hoạt** (`MainTabView`): `.task(priority: .utility)` lúc mở app + khi `scenePhase` về `.active`.
- **Vì sao không có nút "Cập nhật ngay"** (đọc mã LiveContainer `TweakLoader/UIKit+GuestHooks.m`):
  - App đang chạy bên trong LiveContainer gọi `livecontainer://install?url=…` ⇒ LiveContainer chỉ báo "Vui lòng mở lại LiveContainer để cài app", không cài.
  - Nút "Mở LiveContainer" dùng `livecontainer://livecontainer-launch?bundle-name=ui` (hộp xác nhận rồi về màn chính LiveContainer). Không mở được ⇒ toast lỗi.
- `CLAUDE.md` / `AGENTS.md`: thêm đoạn "Báo có bản mới trong app".
- Chuyển entry cũ nhất sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng:**
  - Đọc code + diff; `check_architecture.py` chỉ còn 1 lỗi nền (`JSDom.swift`), **0 mới**.
  - Không build tại chỗ (Windows).
  - Chưa thử trên máy: dải báo / × / bỏ qua, chấm đỏ, và nút "Mở LiveContainer" có chuyển về màn chính LiveContainer không.

## [1.3.726] - 2026-11-05

### chore: bỏ nút thêm nguồn LiveContainer, tin Telegram gửi link apps.json thay link release

Người dùng: *"không cần nút này, bỏ nút này và nút copy đi giúp tôi, gửi chung link app.json với tele là được, cũng không cần gửi link realase chung tele"*.

- **Cài đặt › Thông Tin**: bỏ hàng "Thêm nguồn cập nhật vào LiveContainer" và nút sao chép link nguồn (thêm ở 1.3.724). Chỉ còn dòng "Phiên bản ứng dụng".
  - Xoá `AppDistributionSource` (`Sources/Common/Utils/`), không còn nơi dùng.
- **Tin Telegram** (`build-ipa.yml`):
  - Bước Publish ghi `SOURCE_URL` (link `apps.json` ở nhánh `source`) thay cho `RELEASE_URL`.
  - Caption gửi IPA kết thúc bằng `📲 Nguồn LiveContainer: <link apps.json>`, **không** còn link release.
  - File quá 50 MB: link tải transfer.sh như trước, kèm dòng nguồn LiveContainer.
  - Dòng thừa đổi thành `… và K commit khác` (bỏ "(xem release)").
- Release `build-*` vẫn tạo như cũ (để `apps.json` có link tải IPA), chỉ không gửi link của nó qua Telegram.
- `CLAUDE.md` / `AGENTS.md`: sửa đoạn "Nguồn cập nhật LiveContainer" và "Tin Telegram + ghi chú release liệt kê mọi commit".
- Chuyển entry cũ nhất sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng:**
  - Đọc code + diff; YAML hợp lệ; `check_architecture.py` chỉ còn 1 lỗi nền (`JSDom.swift`), **0 mới**.
  - Commit này đổi `Sources/**` ⇒ kích hoạt build. Lượt đó cũng là lần đầu chạy thật phần liệt kê mọi commit của 1.3.725: tin Telegram phải có 2 commit (1.3.725, 1.3.726) và dòng nguồn LiveContainer.
  - Chưa thử trên máy.

## [1.3.725] - 2026-11-05

### feat: tin Telegram và ghi chú release liệt kê mọi commit của lượt build, gửi lại khi lỗi

Người dùng (qua /grill-me): chia việc cho session con thì *"việc push và build làm cuối cùng sau khi các việc của session con đã xong hết … nội dung commit phải chứa đủ những thứ đã sửa"*. Chốt: giữ commit riêng, session chính push một lần. Thêm: *"nhớ cắt tin nhắn trước khi gửi tele để đảm bảo không bị lỗi tin quá dài nhé. và nhớ check tin nhắn đã được gửi, nếu chưa được thì thử lại 2 lần"*.

- **Trước đây**: CI chỉ đọc `git log -1`. Một lượt push mang nhiều commit thì caption Telegram, ghi chú release và `localizedDescription` của `apps.json` chỉ có commit cuối. `curl … || echo` coi mọi phản hồi là đã gửi, kể cả 400/429.
- **Bước mới `Collect Commit List`** (`build-ipa.yml`):
  - SHA lần build xanh trước trên `main` lấy qua `gh run list` (job thêm `permissions: actions: read`).
  - Danh sách commit lấy qua `gh api repos/…/compare/<cũ>...<mới>` (checkout chỉ có 1 commit). Mỗi commit lấy dòng đầu, cũ → mới, ghi `build/commit_subjects.txt`.
  - Không lấy được ⇒ commit cuối như trước.
- **`Scripts/ci/telegram_commit_summary.py`** (mới): dựng tin `💬 N commit:` + `• <subject>`; một commit giữ dạng `💬 Commit: …`.
  - **Cắt vừa giới hạn trước khi gửi**, đếm theo UTF-16 như Telegram (emoji = 2): caption gửi IPA 1024, tin 4096. Có chừa chỗ cho dòng link. Thừa ⇒ `… và K commit khác (xem release)`.
  - `--format notes` ⇒ danh sách đầy đủ cho ghi chú release, nên LiveContainer cũng thấy đủ.
  - In UTF-8 bất kể bảng mã console.
- **`Scripts/ci/telegram_send.sh`** (mới, `tg_call`): coi là đã gửi **chỉ khi** phản hồi có `"ok":true`. Lỗi ⇒ thử lại **2 lần** (nghỉ 5 s, 10 s). Hết lượt ⇒ `::warning::`, không làm đỏ build (để không gửi nhầm tin "Build Thất Bại").
  - Dùng cho cả 3 tin: gửi IPA, file quá 50 MB, build thất bại.
  - Caption/`chat_id` gửi bằng `--form-string` ⇒ subject có `@`, `<`, `;type=` không bị curl hiểu nhầm.
- `CLAUDE.md` / `AGENTS.md`: thêm đoạn "Tin Telegram + ghi chú release liệt kê mọi commit" ở mục CI.
- Chuyển entry cũ nhất sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng:**
  - Tại chỗ: API so sánh `4cefa5f7...a7a5aba2` trả đúng 3 subject. Caption 3 commit đúng dạng. 40 commit cắt còn 978/1024 đơn vị UTF-16 kèm "… và 28 commit khác". `tg_call` với curl giả (lỗi 2 lần rồi ok ⇒ gửi ở lần 3; luôn lỗi ⇒ trả 1 sau 3 lần). YAML hợp lệ.
  - Commit này không đổi `Sources/**`/`project.yml` ⇒ không kích hoạt build. Lượt build thật kế tiếp là lần kiểm đầu tiên trên CI.

## [1.3.724] - 2026-11-05

### feat: CI đăng IPA lên GitHub Release và cập nhật nguồn LiveContainer, giữ 5 bản mới nhất

Người dùng: *"có cách tạo nguồn app để livecontainer update không?"*. Duyệt plan: *"Chỉ giữ 5 bản gần nhất là ok, không bỏ GOOGLE_CLOUD_TTS_API_KEY đâu"*.

- **LiveContainer** có tab Sources đọc nguồn kiểu AltStore: thêm bằng URL hoặc link `livecontainer://source?url=…`; `Refresh` rồi `Install` cài bản mới nhất của nguồn.
- **CI** (`build-ipa.yml`), bước mới `Publish GitHub Release + LiveContainer Source`. Chỉ chạy với push lên `main`, không chạy với PR. `continue-on-error` ⇒ lỗi đăng không làm đỏ build, IPA vẫn gửi Telegram.
  - Script `Scripts/ci/publish_altstore_source.py` (mới):
    - Tạo release `build-<số build>` kèm `TangCongCac-<version>-<số build>.ipa`, ghi chú = subject commit. Chạy lại workflow (cùng số build) ⇒ xoá release cũ cùng tag rồi tạo lại.
    - Chỉ giữ **5** release `build-*` mới nhất; release cũ hơn xoá kèm tag (`--cleanup-tag`).
    - Dựng `apps.json` (định dạng nguồn AltStore: `versions` + các trường một bản kiểu cũ) từ 5 release còn lại. Ghi kèm `icon.png` (`icon_60_3x.png`) và `README.md` lên nhánh riêng **`source`** (orphan, không phải `main` ⇒ không kích hoạt build, không đụng lịch sử code).
    - Push bị từ chối (hai lượt build đẩy cùng lúc) ⇒ tải lại nhánh, dựng lại từ danh sách release mới nhất, thử tối đa 3 lần.
  - Job có `permissions: contents: write`.
  - Caption Telegram thêm dòng `🔗 Release: …` khi đăng thành công; file quá 50 MB thì gửi link release thay cho transfer.sh.
- **URL nguồn cố định:** `https://raw.githubusercontent.com/buudvh/FreeBook/source/apps.json`.
- **App:**
  - `AppDistributionSource` mới (`Sources/Common/Utils/`) giữ URL nguồn và dựng link `livecontainer://source?url=…`.
  - Cài đặt › Thông Tin thêm hàng "Thêm nguồn cập nhật vào LiveContainer" (mở LiveContainer; không mở được ⇒ toast lỗi) và nút sao chép link nguồn (`ClipboardCopier`, toast "Đã sao chép link nguồn").
- **Khoá Google Cloud TTS:** repo công khai ⇒ IPA trên Release ai cũng tải được và đọc được `GOOGLE_CLOUD_TTS_API_KEY` trong `Info.plist`. Người dùng chọn giữ khoá trong IPA.
- `CLAUDE.md` / `AGENTS.md`: thêm đoạn "Nguồn cập nhật LiveContainer" ở mục CI.
- Chuyển entry cũ nhất sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng:**
  - Đọc code + diff; cú pháp script Python và YAML hợp lệ; thử đọc danh sách release thật bằng `gh` (chỉ đọc).
  - `check_architecture.py` chỉ còn 1 lỗi nền (`JSDom.swift`), **0 mới**.
  - Lượt CI của chính commit này là lượt đầu tiên tạo release và nhánh `source`.
  - Chưa thử trên máy: thêm nguồn trong LiveContainer, cài đè bản mới có giữ dữ liệu không (tài liệu LiveContainer không nói).

## [1.3.723] - 2026-11-05

### feat: version app tự nâng theo số bản CHANGELOG mỗi lần CI build

Người dùng: *"tôi muốn tự nâng ver mỗi khi build thành công"*. Người dùng chọn phương án "Theo CHANGELOG" (không dùng bộ đếm riêng có CI commit ngược).

- **Trước đây**: `project.yml` không khai version ⇒ app mang mặc định của Xcode. Màn Cài đặt › Thông Tin ghi cứng `1.0.0`; caption Telegram không có version.
- **CI** (`build-ipa.yml`):
  - Bước mới `Resolve App Version` lấy số bản đầu `Docs/CodeGraph/CHANGELOG.md` (`## [1.3.NNN]`) làm `APP_VERSION` và `github.run_number` làm `BUILD_NUMBER`. Không đọc được số bản ⇒ cảnh báo + dùng `1.3.0`.
  - `xcodebuild archive` nhận thêm `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`.
  - Bước đóng gói chốt lại `CFBundleShortVersionString` / `CFBundleVersion` trong `Info.plist` của IPA bằng `plutil` và in ra log.
  - Caption Telegram (thành công, file quá 50 MB, thất bại) có `1.3.NNN (số build)`.
  - CI **không** commit ngược về repo ⇒ không có vòng build lặp, không xung đột với các session commit trên main.
- **`project.yml`**: `CFBundleShortVersionString: "$(MARKETING_VERSION)"`, `CFBundleVersion: "$(CURRENT_PROJECT_VERSION)"`. Mặc định cho bản build tay: `MARKETING_VERSION: "1.3.0"`, `CURRENT_PROJECT_VERSION: "1"`.
- **App**:
  - `AppVersionInfo` mới (`Sources/Common/Utils/`) đọc hai khoá trên, dạng hiển thị `1.3.723 (412)`.
  - Màn Cài đặt › Thông Tin hiện version thật thay cho `1.0.0`.
  - `BackupManifest.runningAppVersion` dùng chung `AppVersionInfo.display` (kết quả như cũ).
- **Hệ quả**: commit quên thêm entry CHANGELOG mới thì version không đổi, chỉ số build tăng.
- `CLAUDE.md` / `AGENTS.md`: thêm đoạn "Version app tự nâng theo CHANGELOG" ở mục CI.
- Chuyển entry cũ nhất sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng:**
  - Đọc code + diff; `check_architecture.py` chỉ còn 1 lỗi nền (`JSDom.swift`), **0 mới**.
  - Không build tại chỗ (Windows). Lượt CI của chính commit này là lượt kiểm đầu tiên: log bước `Resolve App Version` và dòng `Info.plist version:` phải ra `1.3.723 (<số lượt>)`. Chưa thử trên máy.

## [1.3.722] - 2026-11-05

### fix: Khám phá đổi nguồn thì tab trùng tên tải lại theo nguồn mới

Người dùng: *"Có lỗi khi chuyển ext mở lại tab cũ không được load lại. Ví dụ đang xem tab đồng nhân ext qidian rồi chuyển sang ext stv mở lại tab đồng nhân vẫn hiển thị dữ liệu cũ"*.

- **Nguyên nhân** (`DiscoveryView`):
  - Trang tab trong `TabView` được nhận diện bằng `CategoryResult.id` (= `title + "_" + input`) cộng `.id(catalogConfigStamp)`, không có nguồn.
  - Bộ nạp của tab (`PaginatedNovelLoader`, `@StateObject` của `DiscoveryCategoryTabView`) chỉ tạo một lần, với `localPath`/`configJson` của lần dựng đầu.
  - Đổi nguồn có xoá `homeItems`, nhưng nguồn mới có `explore` thì `loadDiscoveryData` thêm lại tab section **ngay** ⇒ màn chờ không hiện, khung tab không bị dựng lại.
  - Tab của nguồn mới trùng tên + input với tab của nguồn cũ (vd "Đồng nhân" của qidian và STV) ⇒ SwiftUI giữ nguyên trang, kèm bộ nạp vẫn trỏ vào nguồn cũ. Tab section (`ExploreSectionsView`, id cố định) bị y như vậy.
- **Sửa**:
  - Trang tab danh mục và tab section gắn `.id("\(packageId)#\(catalogConfigStamp)")` ⇒ đổi nguồn hay đổi config đều dựng lại với bộ nạp mới.
  - Tab Thể loại gắn `.id(selectedExtensionId)` ⇒ đổi nguồn thì ô tìm thể loại về rỗng.
  - Tải lại khi đổi config giữ nguyên như cũ.
- Chuyển entry cũ nhất sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng:**
  - Đọc code + diff; `check_architecture.py` chỉ còn 1 lỗi nền (`JSDom.swift`), **0 mới**.
  - Không build tại chỗ (Windows), chưa thử trên máy: đổi qua lại hai nguồn có tab trùng tên, đổi config của nguồn đang xem.

## [1.3.721] - 2026-11-05

### fix: chip nghĩa theo đúng thứ tự màn quản lý, chỉ còn Name/VP

Người dùng: *"Thanh chip màn hình dịch và nội dung trong màn hình quản lý nghĩa khác nhau (xem hình). Ngoài ra có trường hợp chip không hiển thị badge (như hình 3), xảy ra với chữ ngươi"*. Người dùng chọn: chip chỉ còn Name/VP, Phiên âm giữ ở cuối hàng.

- **Nguyên nhân**:
  - `suggestionChips(from:)` dựng chip theo thứ tự của `dictionaryMatches`: Name → Xưng hô → Luật nhân → VP → Phiên âm.
  - `dictionaryMatches` luôn có Xưng hô / Luật nhân, kể cả khi công tắc dịch của chúng tắt. Pipeline (`lookupRawTranslation`) chỉ dùng hai nguồn này khi bật.
  - Pronouns của người dùng có `县丞=huyện thừa` ⇒ chip đầu là "huyện thừa" của Xưng hô. Nghĩa thứ 3 của VP Chung trùng chữ, gộp vào và nâng chip đó lên badge C ⇒ trông như VP Chung xếp "huyện thừa" đầu. Màn Quản lý nghĩa (chỉ 4 mục Name/VP Riêng/Chung) thì ghi `Huyện Thừa/Huyện thừa/huyện thừa`.
  - Nghĩa chỉ có ở Xưng hô không mượn được badge nên nằm giữa hàng mà không có badge (vd `你们` → "các người", "mọi người").
- **Sửa** (`ReaderView+Suggestions.swift`):
  - Chip chỉ lấy Name R → Name C → VP R → VP C (`ManageDefinitionsDraft.editableSources`, đúng thứ tự mục của màn quản lý), rồi Phiên âm ở cuối.
  - Xếp theo danh sách cố định này, không theo thứ tự của `matches` (màn quản lý nối nguồn mới thêm vào cuối danh sách).
  - Bỏ chip Xưng hô / Luật nhân. Gộp nghĩa trùng và luật badge "Riêng thắng Chung" giữ nguyên.
- Hàm dùng chung nên áp cho cả sheet Dịch của Reader, sheet Sửa từ VP/Name và sheet Tra từ điển của trình duyệt (nhóm VietPhrase ở đó không còn nghĩa Xưng hô / Luật nhân).
- `dictionaryMatches(for:bookId:)` giữ nguyên vì màn quản lý và phần ghi nghĩa dựa vào nó. Chỉ sửa comment mô tả thứ tự cũ ở `ReaderView+Selection`, `SuggestionChip`, `MeaningSuggestionChipRow`, `BrowserDictionaryLookup`.
- "huyền thừa" ở mục Phiên âm của màn quản lý không phải lỗi code: file phiên âm của người dùng ghi `县=huyền`.
- Chuyển entry cũ nhất sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**:
  - Đối chiếu file VietPhrase + Pronouns của người dùng với logic dựng chip.
  - `check_architecture.py`: 1 violation nền (`JSDom.swift`), **0 mới**.
  - Không build tại chỗ (Windows), chưa thử trên máy.
