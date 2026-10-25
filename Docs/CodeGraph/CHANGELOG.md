# CHANGELOG - Nhật ký Thay đổi CodeGraph FreeBook

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **FreeBook**.

## [1.3.597] - 2026-10-25

### feat: kết quả tìm trong một nguồn theo kiểu hiển thị của loại nguồn

Người dùng: *"màn hình search chưa theo config layout, video, truyện, commic đang chỉ 1 kiểu, tôi đang nói search 1 nguồn"*.

- **Tìm trong một nguồn** (`SearchSingleSourceResultsView`, mới): dựng theo `BookListLayout` của loại nguồn đang tìm — `BookListLayoutScope(kind: SearchExtensionScopePolicy.kind(of:))`, cùng phạm vi với Khám phá của nguồn đó. Kiểu Danh sách giữ nguyên dòng cũ (bìa 50×70, mô tả → nội dung → tác giả, chip tên nguồn); kiểu Lưới / Chỉ bìa dùng `ScrollView` + `LazyVGrid` của `DiscoveryNovelGridCardView` (video bìa ngang 16:9, số cột theo cài đặt). Đang đổi nguồn thì chạm vẫn hỏi xác nhận; còn lại mở Chi tiết truyện, `bookId` giữ dạng cũ.
- **`SearchView`**: nút "Kiểu hiển thị" (icon theo kiểu đang chọn, 17pt semibold) ở góc phải thanh điều hướng, chỉ hiện khi tìm trong một nguồn (kể cả trước khi có kết quả), mở `BookListLayoutSheet`; đang tìm ở kiểu lưới thì hiện khung chờ dạng lưới (`DiscoverySkeletonGridView`). `searchResultCover` thành `static` để view mới dùng chung.
- Không đổi: tìm trên mọi nguồn (dải bìa ngang theo nguồn), chỉ tải trang 1, công tắc dịch của màn Tìm kiếm.
- Chuyển entry `[1.3.567]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. CI là cổng biên dịch; chưa thử trên máy.

## [1.3.596] - 2026-10-24

### feat: màn Thông báo hiện phần trăm từng tập khi tải video

Người dùng: *"Cho màn hình thông báo cũng xem được phần trăm tải của từng tập"*.

- **Màn Thông báo** (`NotificationInboxView+StoryTasks`, hàng tác vụ đang chạy): tác vụ tải video ghi "Tải video · 3/10 tập · 34%" (trước là "Tải truyện · … chương"), thanh tiến độ chạy mượt theo phần trăm tập đang tải, thêm dòng "Tập 4: 45% · 210 MB" và nút **"Chi tiết tập (N)"** dùng chung `VideoEpisodeProgressList` với tab Tải. Tác vụ truyện/xuất ebook giữ nguyên.
- `DownloadTask.smoothProgressCount` / `videoProgressPercent` (mới, cạnh `VideoEpisodeProgress`): một chỗ tính tiến độ mượt + phần trăm cho cả tab Tải lẫn màn Thông báo.
- Chuyển entry `[1.3.566]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. CI là cổng biên dịch; chưa thử trên máy.

## [1.3.595] - 2026-10-24

### feat: tab Tải hiện phần trăm từng tập của tác vụ tải video

Người dùng: *"vì tải video khả năng sẽ tốn khá nhiều thời gian, do đó đối với video tôi cần xem được phần trăm tải của từng video"*; chọn hiện ở **tab Tải** (không thêm gì lên ô tập trong trình phát), mockup đã duyệt.

- **`VideoEpisodeProgress`** (mới, `Services/Download`): trạng thái một tập — chờ / đang tải (phần trăm + byte) / xong (byte) / có sẵn / lỗi / đã huỷ. **`DownloadTask.videoEpisodes`**: trạng thái tạm, không lưu CSDL (không đổi `DownloadTaskModel`); app khởi động lại thì mất, thử lại tác vụ dựng lại.
- **`DownloadManager+Video`**: dựng danh sách lúc bắt đầu (tất cả "Chờ"), tập bỏ qua ⇒ "Có sẵn", bắt đầu ⇒ "Đang tải 0%", xong ⇒ "Xong" kèm dung lượng từ manifest, lỗi ⇒ lý do, huỷ ⇒ tập đang tải và các tập còn chờ thành "Đã huỷ". `VideoDownloadDetailReporter` (≤ 1 lần/giây) cập nhật trạng thái tập **và** dòng `mediaDetail` trong một lần ghi `tasks` (`updateVideoEpisode`; thay `updateMediaDetail`); nhịp đến muộn không kéo tập đã xong về "đang tải".
- **Tab Tải** (`DownloadTrackerView`): tác vụ video có thanh tiến độ chạy mượt trong tập (`progressCount` + phần trăm tập đang tải) và chữ "Tiến độ: 3/10 tập · 34%"; nút **"Chi tiết tập (N)"** (`VideoEpisodeProgressList`, mới) mở/thu danh sách "✓ Xong · 480 MB", "✓ Có sẵn", "↓ 45% · 210 MB", "Chờ", "✕ Lỗi: …", "Đã huỷ" — hiện ở mọi trạng thái tác vụ khi có danh sách. Trên 60 tập thì chỉ hiện mọi tập lỗi (tối đa 50), 10 tập xong gần nhất, tập đang tải, 5 tập chờ kế tiếp, kèm dòng đếm "Xong · Đang tải · Lỗi · Chờ · Đã huỷ".
- Chuyển entry `[1.3.565]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. CI là cổng biên dịch; chưa thử trên máy.

## [1.3.594] - 2026-10-24

### feat: bấm PiP thì trình phát tự thu nhỏ về màn trước

Người dùng: *"khi nhấn video sang pip hãy tự trở về màn hình trước khi vào màn hình phát"*.

- `VideoPictureInPictureCoordinator.onDidStart` (mới) báo khi PiP **đã bật xong**; `VideoPlaybackSession.pictureInPictureStartCount` tăng mỗi lần. `VideoPlayerScreen` nghe số này: PiP đang bật và app đang `.active` (tức người dùng bấm nút PiP) ⇒ `leave(stopPlayback: false)` — thu nhỏ như vuốt xuống, phim chạy tiếp trong cửa sổ PiP, hub hiện mục Video; khôi phục từ PiP mở lại màn qua `requestScreen` như cũ.
- Chờ `didStart` chứ không rời màn ở `willStart`: gỡ layer khỏi cửa sổ lúc PiP đang bật dở có thể làm PiP hỏng. PiP **tự bật khi rời app** (app không còn `.active`) giữ nguyên màn như trước.
- Chuyển entry `[1.3.564]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. CI là cổng biên dịch; chưa thử trên máy (PiP chạy tiếp khi màn đóng, nút khôi phục mở lại đúng màn).

## [1.3.593] - 2026-10-24

### fix: bản tải video phát lại được sau khi app ra nền, ẩn nút xoá khi đã hết bản tải

Rà lại sau 1.3.592 (chưa thử máy), ba lỗi trong code mới:

- **Phát bản tải sau khi app bị treo nền**: listener 127.0.0.1 có thể đã chết nhưng URL item vẫn trỏ cổng cũ, và lượt tự nạp lại chỉ được **một lần mỗi tập** ⇒ tạm dừng / khoá máy lần hai trên cùng tập là báo lỗi, "Tải lại" cũng dùng lại cổng cũ. Nay mỗi lượt nạp HLS bản tải bật server mới (`VideoOfflineHTTPServer.stop()` trước `url(forRelativePath:)`, queue nối tiếp nên tắt xong mới bật); tự nạp lại sau lỗi tối đa một lần mỗi 20 giây (`offlineRetryWindow`, thay `offlineRetriedEpisodeIndex` bằng `offlineLastRetryUptime`).
- **Server không sẵn sàng**: `ensureRunning()` không có hạn chót — listener kẹt ở `.setup`/`.waiting` làm tập quay mãi ở "đang phân giải". Nay quá 3 giây chưa `.ready` ⇒ log ❌, tắt, trả `nil` ⇒ trình phát chuyển sang trực tuyến.
- **Nút "Xoá bản tải" còn hiện khi đã hết bản tải**: xoá dần từng tập / huỷ tập duy nhất để lại thư mục sách rỗng ⇒ `summary.hasFiles` vẫn `true`, nút hiện "0 byte". Nay `hasFiles` chỉ đúng khi còn tập trọn vẹn hoặc còn byte; xoá tập / bỏ bản dở thì dọn luôn thư mục sách rỗng.
- Chuyển entry `[1.3.563]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. CI là cổng biên dịch; vẫn chưa thử trên máy.

## [1.3.592] - 2026-10-24

### feat: tải video về máy để xem offline

Người dùng: *"làm thêm chức năng tải video nữa"*; chốt qua grill-me + mockup (plan `Docs/Plans/2026-10-24-plan-tai-video-offline.md`), rồi *"tự làm đi không cần hỏi nữa"*. Quyết định: tự tải từng đoạn + server nội bộ phát lại; chất lượng mặc định tối đa 720p (chọn lại trong sheet, nhớ cho lần sau); server đã nhớ trước, lỗi thì thử server khác; lối vào ở trang chi tiết + nhấn giữ trên kệ, menu `⋯` trình phát, nhấn giữ ô tập (không có dấu đã tải trên ô); mở tập đã tải phát bản tải + chip "Trực tuyến"; có nút xoá hết bản tải kèm dung lượng.

- **Lưu trữ** (`Services/Video/Offline/`): `VideoOfflineStore` — `videos/<sha256(bookId)>/<episodeIndex>/`, `manifest.json` (`VideoEpisodeManifest`) ghi **sau cùng**, `partial.json` = chữ ký nguồn bỏ query để tải tiếp bản dở, `validatePathSafety` riêng, `videos/` đặt `isExcludedFromBackup`; Backup không gói. `VideoDownloadQuality` (Cao nhất / Tối đa 1080p / 720p / 480p, UserDefaults `videoDownloadQuality`), `VideoDownloadRequestStore` (sidecar tập bắt đầu của "Tải tập này" theo `taskId` — không đổi `DownloadTaskModel`).
- **Bộ tải**: `VideoHLSOfflinePlanner` (thuần: biến thể + rendition của playlist gốc, playlist con ⇒ danh sách khoá/init/đoạn + playlist local URI tương đối; byterange tách file; giữ `MEDIA-SEQUENCE` cho IV AES-128; từ chối `SAMPLE-AES`/`skd://`/live), `VideoHLSDownloader` (chọn mức theo chất lượng, kèm luồng tiếng `EXT-X-MEDIA TYPE=AUDIO` của nhóm, playlist `fbhls://` ghép tiếng đọc từ `subPlaylists`), `VideoFileDownloader` (mp4 ghi luồng ra đĩa, tải tiếp bằng `Range`), `VideoOfflineHTTPClient` (header tiện ích, thử lại 3 lượt; 401/403/404/410 ⇒ phân giải lại link một lần). Tất cả **tuần tự**.
- **Tác vụ** (`DownloadManager+Video`, `VideoEpisodeDownloadPipeline`): nhánh video của `executeMediaTaskIfNeeded` không còn báo "không hỗ trợ"; server → track → `VideoSourceResolver` (bỏ `.embed`) → bộ tải → phụ đề đầu tiên → manifest; `isInteractive: false`. Bỏ qua tập đã có manifest cùng URL tập; còn dưới 1 GB trống ⇒ dừng; huỷ ⇒ bỏ bản dở của tập đang tải, lỗi/khởi động lại ⇒ giữ để tải tiếp. Mỗi phim chỉ một tác vụ video chạy một lúc (`runNextTasksIfNeeded`); "Tải tập này" trùng tập đang chờ/đang tải thì không thêm. `DownloadTask.mediaDetail` (tạm) = "Tập 4: 45% · 210 MB"; `displayTypeName` = "Tải video" (rawValue "Tải truyện" giữ nguyên vì được lưu bền).
- **Phát bản tải** (`VideoPlaybackSession+Offline`): `runEpisodeLoad` thử bản tải **trước** khi tra tiện ích ⇒ xem được khi không mạng / tiện ích đã gỡ. HLS qua `VideoOfflineHTTPServer` + `VideoOfflineHTTPResponder` (`NWListener` **chỉ 127.0.0.1**, cổng + token ngẫu nhiên, chỉ file dưới `videos/`, `GET`/`HEAD` + `Range`), mp4 phát `file://`; phụ đề + mốc "Bỏ qua" từ manifest. Bản tải không kiểm tiếng; item lỗi ⇒ bật lại server, nạp lại một lần. Chip "Bản tải" / "Trực tuyến" ở hàng server và menu server.
- **UI**: `VideoOfflineLibrary` (`@MainActor @Observable`) là nguồn trạng thái đã tải/đang tải/dung lượng cho View. Menu `⋯`: "Tải tập này" / "Xoá bản tải tập này" + "Tải nhiều tập…" (`TaskOptionsSheet`). Nhấn giữ ô tập: "Tải tập này" / "Xoá bản tải". Trang chi tiết: "Tải video offline" + "Xoá bản tải · N tập · X GB" (`VideoDownloadsDeletePill`). Nhấn giữ trên kệ: "Tải video offline" + "Xoá bản tải (…)" (`VideoDownloadsActionRow`, xử lý ngay trong sheet). `TaskOptionsSheet` chế độ video ("Tải từ tập đang xem", "Số lượng tập", "Chất lượng"). Tab Tải: "Tải video", "x/y tập", dòng phần trăm trong tập.
- **Xoá**: `BookStorageManager` (cả 3 đường xoá) và `BookSourceMigrator` xoá `videos/<sha256(bookId)>`; `BookContentDestination` mở phim đã tải bằng trình phát khi tiện ích đã gỡ.
- Tài liệu: `rules.md` mục "Tải video offline (1.3.592)"; `CLAUDE.md`/`AGENTS.md` thêm `videos/` vào danh sách lưu trữ + mục Comic & Video. Chuyển entry `[1.3.562]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code + agent soát lỗi biên dịch; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch. **Chưa thử trên máy**: AVPlayer phát HLS qua `http://127.0.0.1` trong LiveContainer, `NWListener` loopback (có hỏi quyền Mạng cục bộ không), khoá AES-128, nguồn ngụy trang đoạn `.jpg/.png`, tải tiếp sau khi app ra nền. Thử lần đầu: bật log, tải 1 tập từ menu `⋯` → tab Tải có % → bật chế độ máy bay → mở tập (chip "Bản tải") → tua, phụ đề; lỗi thì gửi `app_logs.txt` (dòng `[VideoOffline]`, `[VideoOfflineServer]`).

## [1.3.591] - 2026-10-24

### feat: tắt NSFW ẩn khỏi Kệ/Bộ sưu tập/Tải/hub/phạm vi dịch, video trình duyệt phát tại chỗ, player chọn chất lượng

Người dùng: *"khi tắt nfsw thì cũng phải ẩn ở kệ sách nữa"*, *"nói chung tắt nfsw thì mọi danh sách phim, comic, truyện đều phải ẩn. liệt kê ra chỗ còn sót rồi tôi sẽ duyệt"*; *"browser của app khi click vào video luôn tự mở rồi phóng to lên…"*; *"thêm mục chọn chất lượng cho player nếu được"*. Duyệt: Kệ sách, Bộ sưu tập, tab Tải, hub nổi, phạm vi dịch + plan video trình duyệt + chất lượng; **không** lọc Thông báo (chương mới) và thứ đang phát (widget TTS, màn khoá, PiP). Tải video tách sang phiên riêng.

- **`RepositoryFilterPolicy.excludingNsfwSources(_:includeNsfw:packageId:)`** (mới, generic): bỏ phần tử của nguồn NSFW, giữ thứ tự, mỗi `packageId` tra một lần — dùng chung cho các danh sách dưới đây. Chỉ ẩn hiển thị, dữ liệu giữ nguyên.
- **Kệ sách** (`ShelfBookPartition(hidesNsfw:)`, đổi từ `hidesNsfwHistory`): tắt NSFW bỏ **mọi** sách của nguồn NSFW, cả ghim/chưa ghim lẫn lịch sử (chip loại suy ra từ partition nên tự theo). **Tìm trong Kệ** quan sát công tắc, bỏ cả sách trên kệ.
- **Bộ sưu tập**: danh sách trong bộ (`CollectionDetailView`), 3 bìa xem trước + số truyện của thẻ (`CollectionGridCardView.visibleBooks(of:includeNsfw:)`), số truyện ở màn sắp xếp bộ.
- **Tab Tải** (`DownloadTrackerView`): ẩn tác vụ tải/xuất của truyện nguồn NSFW (tác vụ vẫn chạy).
- **Hub nổi** (`FloatingHubPresentationReader`): "AI đang chạy" bỏ truyện của nguồn NSFW — run AI không lưu `packageId` nên suy từ tiền tố `bookId` (`BookIdUtils.make` = `<packageId viết thường>_<16 hex>`), không khớp tiện ích nào thì không ẩn; mục Video coi phim NSFW thu nhỏ như không có video (nút hub không nháy vì nó). `VideoMiniPlayerState.packageId` (mới, ghi trước `isActive`). Công tắc theo dõi qua `UserDefaults.didChangeNotification` rút về một bit.
- **Quản lý phạm vi dịch** (`TranslationScopeManagementView`): không liệt kê nguồn NSFW và truyện của nguồn NSFW (truyện đã xoá khỏi thư viện thì không biết nguồn ⇒ vẫn liệt kê); cấu hình vẫn có hiệu lực, "Đặt lại tất cả" vẫn xoá cả mục bị ẩn.
- **Video trong trình duyệt phát tại chỗ**: `BypassBrowserTabStore` bật `allowsInlineMediaPlayback`; **`InlineMediaScript`** (mới, `Services/Browser`) gắn `playsinline`/`webkit-playsinline` cho mọi `<video>` ở mọi frame (quét DOM, `MutationObserver`, `loadstart` + chạm ở pha capture — không sửa prototype). Tab mở từ link dùng config WebKit chép từ tab mẹ nên cũng có. Nút toàn màn hình của trang vẫn dùng được.
- **Chất lượng** (`VideoPlaybackSession+Quality`, `VideoQualityOption` — mới): sau mỗi item đọc `AVAsset.variants`, mỗi độ phân giải giữ biến thể bitrate cao nhất, bỏ biến thể chỉ tiếng; từ 2 mức ⇒ menu `⋯` có "Chất lượng · <mức>" (Tự động + 1080p/720p…). Chọn = **trần** (`preferredPeakBitRate` + `preferredMaximumResolution`) — mạng yếu vẫn có thể thấp hơn. Lựa chọn giữ qua các tập (áp mức cao nhất không vượt lựa chọn), `stop()` về Tự động. `refreshBandwidthLimit` gộp: đang ẩn ⇒ thấp nhất, hiện ⇒ trần đã chọn hoặc không giới hạn. mp4 / HLS một mức / playlist ghép hình + tiếng ⇒ không có mục.
- Cài đặt › Nội dung nhạy cảm: dòng Kệ đổi thành danh sách các chỗ ẩn mới.
- Chuyển entry `[1.3.561]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy (đặc biệt: `variants` với asset qua resource loader `fbhls://`, `playsinline` trên các trang thật).

## [1.3.590] - 2026-10-24

### feat: Google/Bing/Baidu lên đầu, tắt NSFW giữa lượt tìm bỏ nguồn NSFW, player ẩn điều khiển khi vuốt và hạ chất lượng khi phát ẩn

Người dùng: *"để google, bing, baidu lên đầu danh sách. khi tìm tất cả nếu tắt nsfw thì không tìm các nguồn nsfw. ở phần player, nếu vuốt tua nhanh, tăng giảm sáng, tăng giảm âm lượng hãy tự ẩn phần đường timeline và các nút tua 10s. nếu được thì khi video phát ở chế độ ẩn thì hãy phát audio của nó thôi để giảm lưu lượng tốn"*; duyệt plan (ẩn **cả** lớp điều khiển khi vuốt; **giữ** ngoại lệ đổi nguồn cho truyện NSFW — *"bật nsfw mới xem được nsfw"*).

- **Truy cập nhanh** (`BypassBrowserHomeView`): Google, Bing, Baidu đứng đầu rồi mới tới tiện ích; tiện ích trùng đúng URL của một trong ba thì bỏ ô trùng.
- **Tìm mọi nguồn**: tắt NSFW từ trước thì vốn đã không tìm nguồn NSFW (`searchableExtensions` → `applyNsfwFilter`). Sửa ca **tắt giữa lượt tìm**: `SearchView.dropHiddenNsfwSources` gỡ nguồn NSFW khỏi `sourceStates` (số "Tìm thấy N", trạng thái rỗng, vòng "đang tìm" tính lại), kết quả về muộn của khoá đã gỡ bị bỏ; `LegadoSearchScheduler.searchAll(shouldStart:)` xét lại nguồn Legado **đang xếp hàng** lúc tới lượt — NSFW mà công tắc đã tắt thì không chạy (báo `nil`). Request của tiện ích JS đã gửi thì không thu hồi được. Ngoại lệ đổi nguồn cho sách của nguồn NSFW giữ nguyên, tách thành `SearchExtensionScopePolicy.keepsNsfw` dùng chung cho cả lọc lẫn bộ lập lịch.
- **Player — vuốt** (`VideoPlayerController.handlePanBegan`): bắt đầu vuốt tua / độ sáng / âm lượng ⇒ ẩn **cả** lớp điều khiển (kiểu YouTube), nhả tay vẫn ẩn, chạm để hiện lại; vuốt xuống thu nhỏ không đổi.
- **Player — phát ẩn** (`VideoPlaybackSession.refreshBandwidthLimit`): khi đã tách hình (thu nhỏ / nền không PiP — vốn đã chỉ phát tiếng) đặt `preferredPeakBitRate = 1` ⇒ HLS xuống biến thể thấp nhất; gắn lại hình ⇒ `0`. Gọi ở `refreshLayerAttachment` và sau `replaceCurrentItem` (tập kế tự phát lúc đang ẩn). Chỉ đỡ dữ liệu với HLS **nhiều** mức chất lượng; mp4, playlist một mức, playlist ghép hình + tiếng (`VideoAudioRenditionComposer`) không giảm được; không đổi sang luồng chỉ tiếng (thay item lúc PiP/nền/thu nhỏ làm hỏng các ca đó). Về lại màn hình thì vài giây đầu hình còn mờ.
- Chuyển entry `[1.3.560]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.589] - 2026-10-24

### feat: tắt NSFW tự đóng màn của nguồn NSFW, Home trình duyệt chỉ giữ Google/Bing/Baidu

Người dùng: *"khi tôi xem các màn khác của nguồn nfsw mà nếu sau đó tôi tắt nfsw đi thì hãy tự tắt các màn đó đi giúp tôi, phím tắt nhanh ở home ngoài các tiện ích ra hãy chỉ giữ lại google, bing, baidu thôi"*; duyệt plan (đóng cả màn của truyện trên Kệ, làm luôn vuốt lùi về Home hết ẩn danh).

- **`NsfwSourceScreenGuard`** (mới, `Views/Common`, `.closesWhenNsfwHidden(packageId:isEnabled:)`): màn của một nguồn tự `dismiss` khi công tắc NSFW toàn app bị tắt mà màn đã **thấy NSFW bật** lúc đang mở (bật lúc mở hoặc bật trong lúc mở) — màn mở khi NSFW đang tắt (sách NSFW trên Kệ) không bị đụng. `packageId` chụp ở lần xuất hiện đầu: Khám phá đổi nguồn khi NSFW tắt và dựng lại màn thể loại đang mở với nguồn **mới**, đọc giá trị sống thì không bao giờ đóng. Xét cả ở `onAppear` (màn ở tab khác / dưới stack có thể chưa nhận `onChange` tới khi hiện lại); `dismiss()` chạy ở lượt main kế tiếp; log không ghi tên nguồn.
- Gắn vào **Chi tiết truyện** (`BookDetailView` — mọi lối vào, kể cả truyện trên Kệ), **danh sách thể loại / xem thêm** (`CategoryNovelsListView`), **tìm trong một nguồn** (`SearchView` ở chế độ một nguồn, không phải đổi nguồn — `isEnabled` đọc sống theo công tắc "tìm mọi nguồn"). Tìm mọi nguồn: `SearchView` quan sát công tắc NSFW và truyền thẳng vào `searchableExtensions` ⇒ nhóm kết quả của nguồn NSFW biến mất ngay; dòng "Tìm thấy N truyện" giữ số cũ tới lượt tìm sau.
- Không cần guard: Reader / truyện tranh / video / trình duyệt (toàn màn hình) và cấu hình tiện ích / chi tiết nguồn Legado (sheet) — lúc chúng mở không với tới công tắc NSFW. TTS đang đọc truyện NSFW và widget nổi **không** bị dừng.
- **Home trình duyệt**: Truy cập nhanh ngoài ô tiện ích chỉ còn Google, Bing, Baidu (bỏ YouTube, Bilibili, Weibo, Zhihu, Wikipedia, Dịch GG, Tangthuvien, Qidian, 69shu).
- **Ẩn danh**: lùi/tiến về Home (`about:blank` của khung chính, `navigationType == .backForward`) cũng tắt `isIncognito` như nút Home; cửa sổ mới mở trống (cũng `about:blank`, loại `.other`) giữ ẩn danh thừa hưởng. **Chưa kiểm trên máy** việc WebKit có gọi `decidePolicyFor` cho trang lấy từ bộ đệm lùi/tiến hay không.
- Cài đặt › Nội dung nhạy cảm thêm dòng giải thích màn tự đóng.
- Chuyển entry `[1.3.559]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

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
