# CHANGELOG - Nhật ký Thay đổi CodeGraph FreeBook

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **FreeBook**.

## [1.3.538] - 2026-10-18

### fix: mọi danh sách và tên truyện dịch theo cờ của truyện rồi tới nguồn

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

## [1.3.521] - 2026-10-13

### fix(fd): tu don fd mo coi khi nghe TTS o nen, do fd theo tung buoc doan audio

Người dùng gửi `app_logs (103).txt`, hỏi *"không có cách nào giải phóng…"*, *"bình thường mở file không đóng à"*; duyệt plan gộp (bộ đo + bộ dọn) bằng `/push-ci-monitor`.

- **Phân tích log 103 (bản 1.3.520)**: phiên 07:06 → 08:32 chạm trần 10240 fd, 08:33 `NSPOSIXErrorDomain 24` (EMFILE) khi mở `plugin.json`/chương/bìa = tái hiện lỗi gốc. fd **chỉ tăng khi app ở nền và đang phát TTS** (lúc app trên màn hình gần như 0), ~1 đợt mỗi đoạn audio, mỗi đợt mở thêm **1 fd cho mỗi file** trong một nhóm (`app_logs.txt`; sau sao lưu tự động chạy ở nền thêm `books/*.bin`, `.fbbackup`, `VietPhrase.dat`; có lúc `collator.dat`/`Dictionary.dat`/`default.metallib`). fd mới là **mở mới chỉ-đọc** (`fl=0x0 off=0 cloexec=0`), không phải bản `dup` ⇒ giả thuyết `FD_CLOEXEC` của 1.3.520 **sai**. `live=` toàn 0 ⇒ không phải JS/WebView. File trong thư mục tạm đã xoá dừng ở +4 ⇒ thứ gây rò mở lại **theo đường dẫn**. Code app không có chỗ nào làm vậy ⇒ nghi framework hệ thống được gọi mỗi đoạn audio khi ở nền hoặc LiveContainer — **UNKNOWN**.
- **Bộ đo theo bước (`Services/Logging/FileDescriptorStepProbe.swift`, mới)**: khi app ở nền, trong 60 đoạn audio đầu sau mỗi lần xuống nền, đếm fd trước/sau từng bước — `player.stop`, `session`, `player.init`, `player.play`, `nowPlaying`, `finish.stop`, `finish.next` (`TTSManager.swift`, bọc tại chỗ, **không thêm dòng**: vẫn 3510) và `google.request` (`GoogleTTSService.audioParts`); tăng thì ghi `[FD] step=<bước> +N total=T chunk=C` (tối đa 40 dòng mỗi lần xuống nền). Thêm nhịp 1 giây trong 120 giây đầu ở nền: `[FD] tick t=…s ±N total=T chunk=C` khi tổng đổi — phân biệt rò **trong** một bước (đồng bộ) với rò **giữa** các bước (thứ khác đẩy vào). Đếm bằng `fcntl(F_GETFD)` tới fd lớn nhất từng thấy + 512, không mở fd mới.
- **Bộ dọn fd mồ côi (`Services/Logging/FileDescriptorSweeper.swift`, mới)**: chạy trên queue của census mỗi 20 đoạn audio khi tổng fd ≥ 500. Chỉ đóng fd thoả **hết**: file thường, không phải SQLite (`.db`, `.sqlite`, `-wal`, `-shm`, `-journal`) và không dưới `/dev/`; chỉ-đọc, không `FD_CLOEXEC`, vị trí 0; cùng file (device + inode) có ≥ 4 fd như vậy; đã thấy đúng fd đó cùng file ≥ 45 giây; không phải fd số nhỏ nhất của đống. Ghi `[FD] sweep total=A->B closed=N kept=M top=[…]`. Công tắc **"Tự dọn file mở thừa"** (`fdSweeperEnabled`, mặc định bật) ở Cài đặt → Nhà Phát Triển → Ghi log hệ thống, mục Chẩn Đoán. Rủi ro còn lại (đã nói với người dùng): nếu thứ mở lại thỉnh thoảng dùng/đóng các fd đó thì có thể sinh lỗi lạ — tắt công tắc.
- `FileDescriptorCensus`: `record(event:)` báo `background`/`active` cho bộ đo; `tickChunk()` báo đoạn audio cho bộ đo và gọi bộ dọn; `normalize` bỏ `private` để bộ dọn ghi log.
- `rules.md` §5.9 và `CLAUDE.md`/`AGENTS.md` (mirror): `logAlways` dành cho chẩn đoán fd — census, bộ đo, bộ dọn.
- Chuyển entry `[1.3.491]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 vi phạm nền cũ (JSDom, TTSManager 3510), 0 mới; file mới 157 và 102 dòng, một type chính. **Không build tại chỗ** (Windows), cần CI. Không đụng `Tests/`.

## [1.3.520] - 2026-10-12

### feat(settings): gon tab Cai dat thanh cac man rieng (dich, TTS, trinh duyet, log, theo doi nhiet), census fd chi tiet

Người dùng (4 phiên `/grill-me` + `/push-ci-monitor`): tạo màn log riêng; tạo màn cài đặt dịch thuật gom mọi section dịch; thêm màn theo dõi nhiệt (có chia sẻ, *"thận trọng lựa chọn cách lưu thông tin để tránh ảnh hưởng hiệu năng"*); *"gộp các nav ở tab setting còn lại vào cho gọn"*. Plan `Docs/Plans/2026-10-12-plan-settings-reorg-diagnostics.md`, mọi mockup duyệt nguyên.

- **Tab Cài đặt** (`SettingsView.swift` 453 → 33 dòng): chỉ còn dòng điều hướng, 4 section — **Đọc & Nghe** (`ReadingSettingsSection`: Cài đặt dịch thuật · "Đang bật/Tắt", Nghe truyện (TTS) · tên engine từ `@AppStorage("ttsTool")`, Trợ lý AI, Trình duyệt hiển thị · "Thu nhỏ/Toàn màn hình"), **Thư Viện** (`LibrarySettingsSection`: chương mới, sao lưu, dọn dẹp — gộp 3 section một dòng), **Nhà Phát Triển** (`DeveloperSettingsSection`: Debug Server, Ghi log hệ thống · trạng thái, Theo dõi nhiệt · mức hiện tại), **Thông Tin**. Xoá `TTSSettingsSection`, `AISettingsSection`, `BrowserSettingsSection`, `NewChapterSettingsSection`, `BackupSettingsSection`, `StaleBookCleanupSettingsSection` (chỉ `SettingsView` dùng). Không đổi khoá UserDefaults nào; View không observe `TTSManager`.
- **Màn mới, nội dung chuyển nguyên văn** (cắt dán theo dòng bằng script, không viết lại): `TranslationSettingsView` (2 section dịch + trình chọn file nhập từ điển + `getStatusText`), `DictionaryCard` (file riêng), `TTSSettingsHubView` (3 nhóm TTS, tiêu đề nhóm rút gọn; `engineName(for:)` dùng chung), `VisibleBrowserSettingsView` (công tắc thu nhỏ), `LogSettingsView` (3 công tắc + 3 nút + 3 alert; thêm "File đang mở N / giới hạn" từ `FileDescriptorCensus.openCount()` và danh sách file log chỉ xem).
- **Theo dõi nhiệt (mới)**: `Services/Diagnostics/DeviceThermalMonitor.swift` — `@MainActor`, bật ở `FreeBookApp.init`; `DispatchSourceTimer` main 30 s (leeway 10 s) + mẫu ngay khi `thermalStateDidChangeNotification`; mẫu = mức nhiệt (iOS chỉ có 4 mức, không có °C), % CPU **của app** (Δ`ProcessCPUClock`/Δ tường, 100% = 1 lõi), pin, sạc, Low Power, engine TTS nếu đang phát; bộ đệm vòng `ContiguousArray` cấp phát sẵn 1.440 ô (12 giờ), ghi đè mẫu cũ, **không ghi đĩa**. `ThermalCSVExport` (`Transferable`, `DataRepresentation(.commaSeparatedText)`) dựng CSV trong RAM **đúng lúc chia sẻ** (3 dòng tóm tắt + mỗi mẫu một dòng). `Views/Settings/Diagnostics/ThermalMonitorView` (hiện tại, đọc mỗi 2 s khi mở màn; nút chia sẻ 17pt semibold 36×38) + `ThermalMonitorChart` (Swift Charts: bậc thang mức nhiệt; CPU + pin; tô nền đoạn đang phát TTS; "Đang thu thập…" khi < 2 mẫu).
- **Census fd chi tiết** (plan đã duyệt, gộp commit): `FileDescriptorCensus` thêm dòng `[FD] detail <nhóm> n=… fd=min…max newest(fd,fl,cloexec,off) oldest(…)` cho tối đa 5 nhóm vừa tăng (cùng `off` ⇒ bản `dup` chung một open file description) và `live=[…]` trên dòng đếm đủ; `trackLive` đếm `JSExecutor` (thêm `deinit`), `WebViewLoader`, `VisibleWebViewController` (thêm `deinit`). `AppLogger` đặt `FD_CLOEXEC` cho handle log — phép thử giả thuyết "fd thiếu CLOEXEC bị nhân bản theo nhóm" (log 102: `app_logs.txt`/`collator.dat`/`Dictionary.dat` tăng cùng +N, 23 → 1661 fd trong 33 phút sau lần tìm truyện đa nguồn).
- **Sửa theo review phản biện** (3 hướng × kiểm chứng; 3 phát hiện bị bác): (a) tập "đang nhập từ điển" chuyển sang `TranslationImportState.shared` (giữ tên `importingTypes` qua computed property) — trước kia là `@State` của gốc tab sống suốt phiên, để trên màn con thì mất khi Back/chạm lại tab trong lúc `Task` nhập vẫn chạy ⇒ nhập chồng được; (b) `ThermalCSVExport` cố định `en_US_POSIX` + lịch Gregorian cho cột thời gian/tên file; (c) sửa 2 câu hướng dẫn trỏ vị trí Cài đặt cũ (`NghiTTSSettingsView`, `ReaderDefinitionOverlayView+Rules`); (d) "Mức nhiệt"/"Chế độ nguồn điện thấp" đọc thẳng `ProcessInfo` khi chưa có mẫu thay vì hiện "Bình thường" giả; (e) vòng cập nhật 2 giây của màn nhiệt chạy theo `.task(id: scenePhase)` — ở nền thì dừng.
- `rules.md`: §5.9 trỏ màn log mới + `detail`/`live`/`FD_CLOEXEC`; cây thư mục thêm `Diagnostics/`.
- Chuyển entry `[1.3.490]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code + review phản biện; `check_architecture.py` 2 vi phạm nền cũ (JSDom, TTSManager), 0 mới; mọi file mới ≤ 320 dòng, một type chính. **Không build tại chỗ** (Windows) — CI. Không đụng `Tests/`.

## [1.3.519] - 2026-10-12

### fix(toc): doc duoc toc_rules.json kieu cu thieu truong replace/isRegex

Người dùng: *"fix ❌ Lỗi decode file toc_rules.json, fallback về defaultTOCRules"* (dòng lỗi lộ ra nhờ 1.3.517 luôn ghi log ❌), kèm file `toc_rules_config_CADD841F.json`. Plan duyệt trong chat.

- **Nguyên nhân**: `TOCRule` ban đầu (2026-07-04) chỉ có `id, name, rule, example, enabled`; refactor 2026-08-13 (`688b57ee`) thêm `replace: String` và `isRegex: Bool` **bắt buộc** (không dùng ở logic mục lục nào) nên decoder tự sinh đòi đủ 7 khoá. `translate/toc_rules.json` ghi từ bản cũ thiếu 2 khoá ⇒ mỗi lần đọc đều decode hỏng, app lẳng lặng dùng `defaultTOCRules` và **bỏ qua rule người dùng đã chỉnh**. Cùng lỗi làm nhập file rule kiểu cũ báo "JSON không hợp lệ" (`validateImportedTOCRules`) và khôi phục bản sao lưu cũ báo lỗi phần quy tắc mục lục. File người dùng gửi decode bình thường — đó là bộ 21 rule mặc định xuất ra sau khi app đã rơi về mặc định.
- **Sửa (`Models/Translation/TOCRule.swift`)**: `init(from:)` + `CodingKeys` tường minh — `id`, `name`, `rule` vẫn bắt buộc; thiếu `enabled` ⇒ `true`, `replace` ⇒ `""`, `isRegex` ⇒ `true` (đúng mặc định của `init`). Ghi file giữ nguyên đủ 7 khoá (encode tự sinh). Một chỗ sửa chữa cả 3 đường: đọc lúc chạy, nhập file, khôi phục sao lưu.
- **Log**: dòng `❌ Lỗi decode file toc_rules.json` in thêm lý do (`TranslateUtils.tocRulesDecodeFailureReason(at:)` trong `TranslateUtils+TOCRuleValidation.swift`, chỉ chạy ở nhánh đã hỏng). Sửa trên dòng có sẵn: `TranslateUtils.swift` giữ 917 dòng (baseline).
- **Hệ quả**: rule tự chỉnh trong file cũ có hiệu lực trở lại thay cho bộ mặc định; file cũ có thể thiếu rule mặc định thêm về sau — muốn bộ mới nhất thì "Khôi phục mặc định" ở màn Quy tắc mục lục.
- Chuyển entry `[1.3.489]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 vi phạm nền cũ (JSDom, TTSManager), 0 mới. **Không build tại chỗ** (Windows), cần CI. Không đụng `Tests/`.

## [1.3.518] - 2026-10-12

### perf(log): ghi log o luong nen, tu chia file log 2 MB, xuat va xoa tat ca file log

Người dùng: *"có thể sửa tự động chia log file khi quá nhiều không, tôi sợ nhiều quá gây lag app khi log"* → chọn *"chuyển vào luồng nền và chia thành nhiều file, sửa lại xuất cho phép xuất tất cả các file log, sửa xoá tất cả log xoá tất cả file log"*.

- Ghi chú khi phân tích: kích thước file **không** làm việc ghi chậm đi (mỗi dòng là `seekToEnd` + `write` qua handle giữ sẵn); thứ tốn là số dòng/giây ghi đồng bộ trên luồng gọi (kể cả main) và sao chép/xuất file lớn.
- **Ghi trên luồng nền**: `AppLogger.log`/`logAlways` chỉ dựng chuỗi + lấy thời điểm ở luồng gọi rồi `async` sang serial queue `.utility` của `AppLogger`; định dạng giờ, `print` và ghi file làm trên queue. Bỏ `NSLock`; `clear`/`readLogContents` đồng bộ với queue bằng `queue.sync`; `logFileSize` đọc `stat` trực tiếp (bị gọi lúc dựng view). Đổi lại: crash có thể mất vài dòng cuối chưa kịp ghi.
- **Chia file (mới, `Services/Logging/AppLogFiles.swift`)**: `app_logs.txt` quá 2 MB ⇒ đẩy thành `app_logs.1.txt`, các file cũ lùi một bậc tới `app_logs.4.txt`, file cũ nhất bị xoá (tổng ≤ ~10 MB). Xoay vòng chỉ đổi tên/xoá file (không tốn fd); không mở nổi file mới (cạn fd) thì ghi tiếp vào handle cũ — giờ trỏ `app_logs.1.txt` — để không mất dòng. Thay luật "lúc khởi động file > 5 MB thì giữ 1 MB cuối" của 1.3.517.
- **Cài đặt → Nhật ký**: "Xuất tất cả file log" (`ShareLink(items:)` mọi file đang có), "Xóa tất cả nhật ký log" xoá mọi file (file đang ghi cắt về 0 qua handle), "Sao chép nhật ký log (file mới nhất)" chỉ lấy file đang ghi để tránh đưa ~10 MB lên clipboard. `SettingsView.swift` giữ đúng 453 dòng (baseline).
- **Sửa theo review phản biện**: (a) xoay vòng mà không mở nổi file mới (cạn fd) thì đổi tên file đang ghi về lại `app_logs.txt` để handle luôn trỏ file hiện hành — trước đó handle kẹt ở `app_logs.1.txt` và lần xoay sau/"Xóa tất cả" có thể xoá chính file đang ghi; `shiftForRotation` trả `Bool` để chỉ trả tên khi bước đổi tên đã xảy ra; (b) danh sách file cho "Xuất tất cả file log" giữ trong `@State logFileURLs` (thay `logFileExists`), cập nhật khi mở màn Cài đặt và sau khi xoá, để không bỏ sót file mới chia; (c) sửa số dòng `AppLogger.swift` trích trong `CLAUDE.md`/`AGENTS.md`.
- `rules.md` §5.9 + cây thư mục `Logging/`, `CLAUDE.md`/`AGENTS.md` mục Logging cập nhật theo.
- Chuyển entry `[1.3.488]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 vi phạm nền cũ (JSDom, TTSManager), 0 mới. **Không build tại chỗ** (Windows), cần CI. Không đụng `Tests/`.

## [1.3.517] - 2026-10-12

### fix(tts): tam dung khi 5 chuong lien tiep loi, dem file descriptor de tim cho ro, nang gioi han fd, luon ghi log loi

Người dùng: *"nghe truyện lâu sẽ xảy ra lỗi này, đây là chương đã tải, có vẻ lỗi gì đó chặn truy cập file, tìm nguyên nhân lỗi; ngoài ra hãy sửa lại: trước đây nếu chương lỗi sẽ tự sang chương kế tiếp vô hạn. bây giờ hãy sửa lại, nếu sang chương 5 lần đều lỗi thì tạm dừng"*. Plan duyệt trong chat (Phần 1 + Phần 2 + mục 3c; chương rỗng tính vào 5 lần). Sau đó: *"sửa lại để luôn log lỗi dù có bật log hay không giúp tôi"*.

- **Nguyên nhân (đọc code, chưa có log máy thật)**: tiến trình **cạn file descriptor (EMFILE)** sau vài giờ nghe Google TTS. Dấu hiệu: chuỗi `couldn\U2019t … (NSCocoaErrorDomain error 256.)` là chuỗi gốc chưa bản địa hoá của CoreFoundation (chỉ lộ ra khi CF không nạp nổi bảng bản địa hoá); 256 = `NSFileReadUnknownError` (EMFILE ánh xạ vào 256, chặn do khoá máy sẽ ra 257); "Tải lại" không được, ảnh bìa đã tải cũng không hiện, bật log sau khi lỗi cũng không ghi được, chỉ tắt hẳn app mới hết. Đường đi: đọc `.bin` hỏng bị nuốt (`ChapterPersistenceStore.readChapter`, `ChapterContentRepository.loadUnshared`) ⇒ rơi xuống `ExtensionManager.chap` đọc `plugin.json`/`chap.js` cũng hỏng ⇒ lỗi đó lên Reader. Rà 37 commit `c1e51da6..HEAD` và săn rò rỉ trên đường Google TTS (theo luồng + quét theo API) **chưa thấy chỗ rò** ⇒ phải đo trên máy.
- **Đo fd (mới, `Services/Logging/FileDescriptorCensus.swift`)**: đếm fd đang mở theo nhóm (đường dẫn chuẩn hoá `AS/books/<hex>.bin`, `sock/tcp/:443`, `pipe`…) chỉ bằng `fcntl`/`fstat`/`getsockopt`/`getpeername` — không mở fd mới nên chạy được cả khi đã cạn. Ghi lúc khởi động, mỗi lần TTS sang chương, mỗi 100 đoạn audio (chỉ tổng; tăng > 20 thì đếm đủ), khi app vào nền/trở lại, và chụp toàn bộ bảng fd đúng lúc lỗi (`BookBinManager` mở file hỏng, `ImageCacheManager.loadLocalCover` đọc bìa hỏng, TTS bỏ chương vì hết fd) — mỗi phiên một lần.
- **`AppLogger.logAlways`**: ghi bất kể công tắc log (chỉ census dùng, ~1 dòng/chương nên không chạm ngưỡng tự xoá 5 MB). `appendLocked` giờ tạo file rỗng rồi mở handle ngay từ dòng đầu, giữ suốt phiên ⇒ lúc cạn fd vẫn ghi được.
- **Luôn ghi log lỗi**: `AppLogger.log` giờ ghi mọi dòng chứa `❌` dù công tắc log tắt (dòng thường vẫn theo công tắc); đổi lại chuỗi log luôn được dựng để kiểm tra. Gắn `❌` cho 32 dòng log lỗi thật chưa có dấu (catch-block lưu/đọc file, ChapterStore save failed, espeak init, TTS không bắt đầu/không chuẩn bị được chương, NghiTTS synthesis failed, lỗi AI/Gemini Web…); để nguyên các dòng không phải lỗi (huỷ, thử lại, fallback, thống kê, Debug Server ngắt kết nối). Thêm chi tiết lỗi (`FileDescriptorCensus.describe`) vào log nuốt lỗi ở `ChapterPersistenceStore.readChapter` và `ChapterContentRepository.loadUnshared`; thêm log `❌` khi Reader không tải được chương (`ReaderViewModel.runNavigationWorker`). `CLAUDE.md`/`AGENTS.md` mục Logging ghi quy ước `❌`.
- **3c — nâng giới hạn fd**: `FileDescriptorCensus.start()` (gọi cuối `FreeBookApp.init`) nâng `RLIMIT_NOFILE` mềm lên mức cao nhất hệ thống cho phép trong `10240/8192/4096/2048/1024`, ghi `soft=cũ->mới hard=…` vào log. Che bớt triệu chứng trong lúc chờ tìm chỗ rò; census vẫn thấy fd tăng dần.
- **Dừng sau 5 chương lỗi (mới, `TTSManager+ChapterSkipLimit.swift`)**: `skipFailedChapter` thay 3 chỗ tự bỏ chương — tải lỗi, xử lý lỗi (`fallbackAdvanceToNextChapter`) và chương không có nội dung (`applyNextChapter`). Chương lỗi thứ 5 liên tiếp ⇒ `stopCurrentPlayback()` + `pause()` + toast lỗi; nếu do hết fd thì toast thêm "App đang mở quá nhiều file — hãy tắt hẳn app rồi mở lại". Bộ đếm về 0 khi `applyNextChapter` phát được chương (`noteChapterAdvanceSucceeded`), khi `startSpeaking`, khi `pause()`. Không đếm `CancellationError` và nhánh dịch lại do đổi token. Chương lỗi chạm cuối truyện ⇒ toast "không phát được và đã tới cuối truyện" thay cho "Đã phát hết" gây hiểu lầm.
- Nhánh lỗi tải/xử lý thêm guard `!Task.isCancelled` + `ttsProcessingGeneration == expectedGeneration` (nhánh thành công vốn có) để task cũ không đếm nhầm. Log lỗi chương dùng `FileDescriptorCensus.describe` (domain/code từng tầng, không gọi `localizedDescription`).
- Gộp 6 khối "📖 Đã phát hết nội dung bộ truyện" chép lặp thành `advanceOrFinishBook(after:)`; `nextChapterIndex`/`advanceToNextChapter` bỏ `private`. `TTSManager.swift` 3550 → 3510 dòng (baseline 3470 vẫn vượt như trước).
- `rules.md`: bullet giới hạn bỏ qua chương trong mục "Chapter repository memory and cancellation invariants"; ngoại lệ `AppLogger.logAlways` ở §5.9; `FileDescriptorCensus.swift` trong cây thư mục `Logging/`.
- **Sửa theo review phản biện (không build được nên review thay compiler)**: (a) mở màn Cài đặt từng gọi `logFileSize` khi dựng view và đóng mất handle log — lúc đã cạn fd thì mọi dòng log sau đó mất âm thầm; nay `logFileSize`/`readLogContents` không đóng handle, handle mở `forUpdating` để "Sao chép nhật ký log" đọc qua chính nó, `clear()` cắt file về 0 qua handle thay vì xoá; (b) `AppLogger.init` gặp file > 5 MB thì giữ 1 MB cuối thay vì xoá hẳn, để lần mở lại app ngay sau sự cố không xoá mất log của sự cố; (c) census chạy trên serial queue `.utility` (không chặn main/TTS, bỏ lock), đã chụp lúc lỗi rồi thì không quét lại; (d) `describe` giữ câu mô tả lưu sẵn (`NSLocalizedDescriptionKey`, `errorDescription` của lỗi Swift) để log lỗi chương không mất text exception JS như log cũ.
- Chuyển entry `[1.3.487]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 vi phạm nền cũ (JSDom, TTSManager), 0 mới. **Không build tại chỗ** (Windows), cần CI/máy Mac. Không đụng `Tests/`.

## [1.3.516] - 2026-10-11

### docs: viet lai README.md theo trang thai hien tai cua app

Người dùng: *"merge code vào nhánh main và viết lại readme.md cho tôi"*.

- Fast-forward `main` lên `refactor/god-objects` (không có merge commit, `main` không có commit riêng).
- `README.md` viết lại: README cũ chỉ nói VBook/VietPhrase/NghiTTS và 3 engine TTS. Bản mới liệt kê đúng tính năng hiện có — 5 engine TTS (NghiTTS, VieNeu, Siri, Google, Extension), trợ lý AI (Gemini Web, OpenAI, Anthropic…), Quick Translation Rules, nhập/xuất nhiều định dạng, sao lưu Local/Google Drive/Telegram, hộp thư chương mới, debug server extension + extension VS Code; cập nhật cấu trúc `Sources/`, cách build, CI và chỉ dẫn đóng góp.
- Chuyển entry `[1.3.486]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- Chỉ đổi tài liệu, không đổi code.

## [1.3.515] - 2026-10-11

### fix(ai): dung AI mot lan la xong, quet ten rieng Gemini Web it luot hon va theo cong tac luu, bo nut X widget

Người dùng: *"lọc tên riêng nhiều chương chưa áp dụng config bật tắt tạm à, ngoài ra hãy giảm số batch để thích hợp với gemini web; bỏ nút x trong widget ai; có lỗi phải bấm nút dừng 2 lần trên dải đến batch mới mất dải batch trên top; hơn nữa dòng ai đang suy nghĩ cũng không mất đi khi bấm dừng"*. Plan duyệt trong chat.

- **Phải bấm dừng 2 lần mới mất dải batch**: bấm dừng thì coordinator xoá dải, nhưng request đang bay ném lỗi huỷ, vòng quét coi là "lỗi lẻ của một nhóm", bỏ qua rồi gọi `onProgress`; báo tiến độ chạy trong một `Task` mới (`Task.isCancelled` của nó luôn false) nên dựng lại dải. Sửa: vòng quét gặp huỷ thì thoát, không báo tiến độ; coordinator gắn `batchRunId` cho mỗi lần chạy và bỏ mọi báo cáo không khớp.
- **"AI đang suy nghĩ" không mất khi dừng**: luồng chat bị huỷ thoát ngay mà tin trợ lý trong `activeSession` vẫn `isStreaming`; màn AI đồng bộ ngược trạng thái đó, cộng một nhịp chữ có thể tới sau khi dừng. Sửa: `AIRuntimeCoordinator.stopActiveTask()` (view gọi thay `cancelActiveTask()`) huỷ rồi hoàn tất mọi tin đang chạy — tin rỗng ghi "Đã dừng." — và lưu phiên; nhịp chữ phải khớp `streamRunId` mới được ghi. Màn AI cũng hoàn tất tin của chính nó ngay khi bấm.
- **Quét tên riêng với Gemini Web**:
  - Gom chương liền nhau tới **~40.000 ký tự/lượt**, không cắt giữa chương (chỉ cắt khi một chương đơn lẻ dài hơn). Đã thử thật từ máy dev: 15k/40k/80k ký tự chữ Hán đều trả `Tên=Nghĩa` trong 5–9 s. Ví dụ 100 chương ~3.000 ký tự: 20 → ~8 lượt. Provider API giữ 5 chương/15.000 ký tự. Văn bản chương được đọc trước rồi mới chia lượt (tổng số lượt biết trước như cũ).
  - Theo công tắc "Lưu chat vào lịch sử Gemini": bật ⇒ cả lần quét là một cuộc chat nối tiếp (`GeminiWebClient.sendConversation`, mở cuộc chat mới sau mỗi 5 lượt để ngữ cảnh không phình; trạng thái chỉ giữ trong RAM — `persist: false` — để không đẩy trạng thái chat thật ra khỏi store); tắt ⇒ mỗi lượt là chat tạm độc lập như trước.
- **Bỏ nút X** trên widget AI thu nhỏ (`AIFloatingWidgetView`).
- `rules.md`: bullet mới về dừng/mã lần chạy trong mục Reader AI; bổ sung kích thước lượt quét vào mục Gemini Web.
- **Kiểm chứng**: đọc code + thử prompt lớn thật; `check_architecture.py` 2 vi phạm nền cũ, 0 mới. **Không build tại chỗ** (Windows) — CI nhánh `refactor/god-objects`.

## [1.3.514] - 2026-10-11

### feat(ai): Gemini Web noi tiep cuoc chat theo phien, cong tac luu chat vao lich su Gemini

Người dùng: *"mở gemini thấy trong đoạn chat không có chat mới"*, rồi *"làm cả 2 cách thì sao"*. Plan duyệt trong chat.

- **Vì sao trước đây không thấy**: mỗi lượt gửi `f.req[45] = 1` (chat tạm) và metadata rỗng ⇒ không vào lịch sử tài khoản, mỗi lượt là một cuộc chat mới gửi lại toàn bộ ngữ cảnh.
- **Đã thử thật** (chế độ khách): lượt 2 kèm metadata của lượt 1 ⇒ Gemini nhớ nội dung lượt 1, cùng cid — đúng cả khi chat tạm lẫn chat lưu.
- **Nối tiếp hội thoại (luôn bật)**: `GeminiWebClient.sendConversationStreaming` (file `+Conversation.swift`) — mỗi phiên chat của app ứng với một cuộc chat Gemini. Lượt đầu gửi đủ ngữ cảnh; lượt sau chỉ gửi tin mới, khối ngữ cảnh hệ thống đổi (so băm SHA-256 — sang chương khác, đổi chế độ, đổi từ điển…) thì kèm "Cập nhật ngữ cảnh". Mở cuộc chat mới khi đổi model (tránh 1050) hoặc đổi công tắc lưu; lượt nối tiếp bị từ chối trước khi có chữ ⇒ mở lại một lần với đủ ngữ cảnh (không áp cho lỗi tài khoản/hạn mức/timeout).
- **Công tắc "Lưu chat vào lịch sử Gemini"** trong hàng tài khoản Gemini Web (`geminiWebSaveHistory`, mặc định tắt): tắt = chat tạm như cũ; bật = mỗi phiên chat của app là **một** cuộc chat trên gemini.google.com.
- **Giao thức**: `GeminiWebRequestBuilder` nhận metadata 10 ô cho `f.req[2]` và cờ chat tạm; `GeminiWebResponseParser.conversationUpdate` đọc cid/rid (`inner[1]`), rcid (ứng viên `[0]`), ngữ cảnh (`inner[25]`); `GeminiWebConversationState.apply` chỉ ghi đè ô có giá trị (port setter của `gemini-webapi`).
- **Lưu trạng thái**: `GeminiWebConversationStore` (UserDefaults, theo id phiên, tối đa 100 cuộc chat gần nhất). **Lệch plan có chủ ý**: không lưu trong `AIChatSession` vì màn AI và `AIRuntimeCoordinator` cùng ghi phiên khi một lượt kết thúc ⇒ trường mới dễ bị ghi đè mất.
- **Không đổi**: quét tên riêng và "Kiểm tra kết nối" vẫn là chat tạm, không nối tiếp. `rules.md`: thay bullet "stateless" trong mục Gemini Web.
- **Kiểm chứng**: đọc code + thử nối tiếp hội thoại thật từ máy dev; `check_architecture.py` 2 vi phạm nền cũ, 0 mới. **Không build tại chỗ** (Windows) — CI nhánh `refactor/god-objects`.

## [1.3.513] - 2026-10-11

### perf(reader): tach trang thai highlight TTS khoi ReaderView - nhip highlight chi ve lai cac hang doan van

Người dùng: *"reader vẽ lại như vậy có vẻ khá dư thừa nhỉ, vẫn ở truyện đó thì sao phải vẽ lại liên tục, trong khi chỉ có highlight thay đổi thôi"*. Plan duyệt trong chat.

- **Nguyên nhân**: `ReaderTTSStateReader` có **một** `@Published snapshot` gộp trạng thái thô (đang phát, truyện/chương, widget) với phần mịn (`currentParentParagraphIndex`, `highlightRange`, vệt chuẩn bị); ReaderView `@StateObject` nó ⇒ mỗi câu TTS mới làm **cả thân ReaderView** (~2050 dòng) tính lại, kéo theo overlay, danh sách chương và nội dung mọi màn đang trình bày từ Reader (AI, Cài đặt AI, sheet). `scope(to:)` chỉ chặn highlight của truyện khác. Telemetry máy thật: `updateRPM=105.7`, `repeatUpdateRPM=40.4` khi nghe. Hệ quả đã gặp: sheet đăng nhập Gemini Web bị dựng lại 10 lần/30 s (1.3.512), danh sách chương phải bọc `.equatable()` (1.3.510).
- **Sửa**:
  - `ReaderTTSStateSnapshot` chỉ còn trường thô ⇒ `ReaderTTSStateReader` không publish theo highlight nữa.
  - `ReaderTTSHighlightReader` (file mới) giữ phần mịn, cùng cách gộp highlight của truyện khác thành snapshot trống. ReaderView giữ nó bằng **`@State`** (không `@StateObject` — ReaderView không được quan sát nó).
  - `ReaderTTSHighlightBinder` (file mới) bọc mỗi hàng đoạn văn, quan sát reader mịn và đưa vệt TTS/vệt chuẩn bị vào `ParagraphCardView` (logic chọn vệt y như cũ; thẻ vẫn `.equatable()` nên chỉ thẻ có vệt đổi chạm UIKit).
  - Tự cuộn theo đoạn đang đọc: `.onChange(of: ttsState.snapshot.currentParentParagraphIndex)` → `.background(ReaderTTSParagraphChangeObserver(…))` (file mới, `.onChange` trong view rỗng — giữ ngữ nghĩa chỉ gọi khi đổi).
  - `ReaderView+Controls`, `ReaderView+LoadingView` đọc `ttsHighlight.currentParentParagraphIndex` tức thời (không subscribe).
- ReaderView 2051 → 2045 dòng. `rules.md`: bullet mới về hợp đồng reader thô/mịn.
- **Kiểm chứng**: đọc code + rà soát độc lập 3 lăng kính (observation, tương đương hành vi, biên dịch) có phản biện; `check_architecture.py` 2 vi phạm nền cũ, 0 mới. **Không build tại chỗ** (Windows) — CI nhánh `refactor/god-objects`. Đo trên máy: so `ReaderEnergy updateRPM` trước/sau khi nghe TTS.

## [1.3.512] - 2026-10-11

### fix(ai): dang nhap Gemini Web trong trinh duyet bypass - WebView khong bi SwiftUI dung lai theo Reader

Người dùng: *"gemini web vẫn lỗi đó, vì sao bạn không dùng bypass browser"* kèm `app_logs (94).txt`. Plan duyệt trong chat.

- **Log phân định (giả thuyết 1.3.511 sai)**: không có dòng nào báo iOS kết thúc tiến trình web; thay vào đó `Tạo WKWebView đăng nhập` xuất hiện **10 lần trong 30 giây** — 3 khi mở, 4 khi quay lại từ Gmail (10:34:26), 3 ngay sau một nhịp TTS (10:34:29); mỗi lần kèm `.task` của một màn đăng nhập mới ⇒ SwiftUI dựng lại cả view, WKWebView mới nạp lại trang đăng nhập từ đầu.
- **Nguyên nhân**: sheet đăng nhập nằm đáy chuỗi `ReaderView → fullScreenCover AI → sheet Cài đặt AI → hàng Form (GeminiWebAccountRow) → sheet`. ReaderView vẽ lại theo từng highlight TTS và khi quay về từ nền (một `@Published snapshot` gộp cả `highlightRange`) nên SwiftUI tính lại nội dung mọi presentation bên dưới và dựng lại sheet gắn trên hàng Form. Quy tắc SwiftUI nội bộ chọn "dựng lại" thay vì "cập nhật" không đọc được từ code app; log cho thấy nó xảy ra.
- **Sửa**: `GeminiWebLoginLauncher` (file mới) mở trang đăng nhập trong **trình duyệt bypass** (`VisibleWebViewLoader` + `VisibleBrowserTabManager`, UIKit, sống suốt app, ngoài cây SwiftUI), `selectTab` để luôn mở toàn màn hình kể cả khi cài đặt "mở thu nhỏ" bật. Nhận biết xong bằng **host** `gemini.google.com` qua KVO `webView.url` (không so chuỗi con — URL đăng nhập chứa `continue=…gemini.google.com…`) ⇒ `refreshAfterLogin`, chờ 0,8 s, đóng tab; người dùng đóng tab trước ⇒ chỉ làm mới trạng thái. Vẫn giải phóng WKWebView ẩn khi bắt đầu đăng nhập. Log `🤖 [GeminiWebLogin]` mỗi điều hướng (host + path).
- `GeminiWebAccountRow` gọi launcher thay cho `.sheet`; xoá `GeminiWebLoginView.swift`, `GeminiWebLoginWebPane.swift` (cùng phần xử lý `webViewWebContentProcessDidTerminate` của 1.3.511 — không phải nguyên nhân). `rules.md`: bullet mới trong mục Gemini Web ("WKWebView mang trạng thái người dùng không được để SwiftUI sở hữu bên dưới Reader").
- Gốc rễ chung (ReaderView vẽ lại theo highlight) được xử lý riêng ở 1.3.513.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 vi phạm nền cũ, 0 mới. **Không build tại chỗ** (Windows) — CI nhánh `refactor/god-objects`.

## [1.3.511] - 2026-10-11

### fix(ai): dang nhap Gemini Web - khong tu tai lai khi iOS giai phong trang, log chan doan, giam RAM

Người dùng: *"có lỗi khi đăng nhập gemini web, khi web yêu cầu bấm số xác thực tôi chuyển qua gmail xác thực thì màn hình xác thực của app bị trở về màn hình đăng nhập ban đầu"*. Plan duyệt: `Docs/Plans/2026-10-11-plan-vieneu-search-geminilogin.md` mục 3.

- **Giả thuyết chính (cơ chế có bằng chứng, nhân quả cần log xác nhận)**: khi app ở nền, iOS có thể kết thúc tiến trình WebContent của trang đăng nhập. `GeminiWebLoginWebPane.Coordinator` **không** implement `webViewWebContentProcessDidTerminate` ⇒ WebKit tự tải lại trang khi view hiện lại (mã nguồn WebKit: `NavigationState.mm`, `WebPageProxy::tryReloadAfterProcessTermination`), và trang xác minh của Google mất trạng thái nên quay về bước nhập email. Đã loại trừ theo code: SwiftUI dựng lại pane (sẽ làm sheet đóng hẳn), cửa sổ ẩn của Gemini, xử lý `scenePhase` của app.
- **Không tự tải lại**: implement `webViewWebContentProcessDidTerminate` — ghi log, báo lên `GeminiWebLoginView` để footer hiện "iOS đã giải phóng trang đăng nhập khi app ở nền. Bấm Tải lại để tiếp tục." kèm nút **Tải lại** (`reloadToken` → `updateUIView` gọi `reload()`). Không gọi `reload()` ngay trong callback vì phá lớp chống vòng lặp crash 1 lần/30 s của WebKit.
- **Giảm RAM khi đăng nhập**: sheet mở ⇒ `GeminiWebClient.prepareForLogin()` → `GeminiWebSessionController.releaseWebViewIfIdle()` (file `+Account.swift`; `isIdle` = không fetch đang bay, không nạp trang dở) bỏ WKWebView ẩn — một tiến trình WebContent ít hơn; sau đăng nhập phiên vốn được nạp lại.
- **Mẹo trong footer**: "ở bước bấm số, chọn "Thử cách khác" → mã SMS. iOS gợi ý mã ngay trên bàn phím, không cần rời app."
- **Log chẩn đoán** `🤖 [GeminiWebLogin]`: tạo WKWebView kèm mã instance (hai dòng trong một lần mở sheet ⇒ pane bị dựng lại), mỗi điều hướng / commit / lỗi (chỉ host + path, không query vì chứa token), iOS kết thúc tiến trình, người dùng bấm Tải lại, `scenePhase` khi sheet đang mở.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 vi phạm nền cũ, 0 mới (`GeminiWebSessionController.swift` 393/400). **Không build tại chỗ** (Windows) — CI nhánh `refactor/god-objects`. Cần log từ máy thật (bật Logging trước) để xác nhận nguyên nhân.

## [1.3.510] - 2026-10-11

### fix(reader): tim chuong theo ten dang hien thi, khong phan biet hoa thuong va dau

Người dùng: *"tìm kiếm không được trong danh sách chương của reader"*, *"gõ số chương cũng không được, gõ đúng viết hoa cũng không được"*, *"tôi tìm xong thì dữ liệu không đổi theo tôi tìm nhưng tắt danh sách chương đi rồi mở lại vì có chữ tìm trong đó danh sách sẽ đổ kết quả tìm"*. Plan duyệt: `Docs/Plans/2026-10-11-plan-vieneu-search-geminilogin.md` mục 2.

- **Bằng chứng**: chạy đúng câu SQL tìm của app trên `chapter_store.sqlite` lấy từ máy người dùng (truyện `bookIdHash=88949c37`, 163/163 chương có `title_trans`): `100` → 2 kết quả, `chương 100` → 1, tên đầy đủ → 1. Truy vấn đúng; lỗi nằm ở tầng vẽ. Git: toàn bộ đường tìm không đổi từ 07–08/2026, thay đổi duy nhất là `c9e7c20a` (2026-10-09) cho `ReaderChapterListView` conform `Equatable` + `.equatable()`.
- **Nguyên nhân chính (thoái lui từ `c9e7c20a`)**: view thật có `@State searchQuery` và đọc store `@Observable` lại mang `==` (bỏ qua state, so store theo identity) dưới `.equatable()`; trên máy, body không chạy lại khi gõ hay khi kết quả về — chỉ chạy khi input `isPresented` đổi (đóng/mở danh sách). Trước commit đó `ReaderView` vẽ lại danh sách liên tục nên che mất chỗ hở. Các `@State` nội bộ khác (đảo thứ tự, đang cập nhật mục lục, đang tải chương lẻ, cache tên dịch) kẹt cùng kiểu.
- **Sửa gốc, giữ tối ưu**: `ReaderChapterListHost` (file mới) là vỏ **không trạng thái** mang `==` + `.equatable()`, body chỉ dựng `ReaderChapterListView`; xoá `ReaderChapterListView+Equatable.swift` nên view thật **không** còn `Equatable` ⇒ `@State`/Observation cập nhật bình thường, nhịp vẽ lại của `ReaderView` (highlight TTS) vẫn bị chặn ở vỏ. `ReaderView` chỉ đổi tên view ở chỗ mount.
- **Lọc trên tên đang hiển thị** (`ChapterTitleSearchMatcher`, file mới): `BackgroundSearchWorker` bỏ SQL `LIKE`, đọc `fetchOrderedTOC` rồi khớp trong Swift trên tên hiển thị (cùng cách chọn với `BackgroundPagingWorker`), tên gốc và `titleTrans`, không phân biệt hoa/thường, dấu, độ rộng; kiểm tra huỷ mỗi 200 chương. Sửa luôn: chương thiếu `title_trans` chỉ tìm được bằng chữ Hán (DB người dùng: 60/204 truyện thiếu một phần hoặc toàn bộ), "đại đế" không ra "Đại Đế" (`LIKE` chỉ gấp hoa/thường ASCII), `%`/`_` thành ký tự đại diện, lệch khi chuyển phồn→giản. Nhánh dự phòng `onlineChapters` dùng cùng bộ khớp. `ChapterStoreDatabase.searchChapters` giữ nguyên (không đổi schema), chỉ không còn được ô tìm gọi.
- **Tìm lại sau reset**: `updateChapters`, `reloadAllPages`, `updateTranslation` (cùng `updateSortOrder`) gọi `rerunSearchIfNeeded()` — trước đây kết quả bị xoá mà ô tìm vẫn giữ chữ.
- **Log** mỗi lượt tìm: `🔎 [ChapterSearch] bookIdHash=… len=… results=… ms=…` (không log từ khoá; `ms` gồm debounce 250 ms).
- **Kiểm chứng**: đọc code + thử SQL trên DB thật; `check_architecture.py` 2 vi phạm nền cũ, 0 mới. **Không build tại chỗ** (Windows) — CI nhánh `refactor/god-objects`.

## [1.3.509] - 2026-10-11

### feat(vieneu): bo lua chon 1 luong, mo ta cai dat gon va dung tac dung spin

Người dùng: *"Làm gọn bớt phần mô tả của mỗi config trong màn hình cài đặt tts của vieneu"*, *"gọn hơn nữa"*, *"1 luồng không tiết kiệm pin hơn lại còn lag hơn thì bỏ luôn option 1 luồng đi. Luồng chờ bận (spin) giải thích bậy quá, phải giải thích bật/tắt có hiệu quả gì"*. Plan duyệt: `Docs/Plans/2026-10-11-plan-vieneu-search-geminilogin.md` mục 1.

- **Bỏ "1 luồng"**: picker "Số luồng tổng hợp" còn 2/3/4. Kẹp ở `VieNeuSynthesisPolicy.threadCount(from:)` (`max(2, …)`) — đường đọc **duy nhất** của khoá `vieneuThreadCount`, nên giá trị 1 đã lưu (kể cả từ bản sao lưu cũ, vốn ghi thô) tự thành 2 ở UI, nạp engine, kiểm tra nạp lại và tạo giọng; setter `VieNeuTTSService.threadCount` cũng kẹp `max(2, …)`. Căn cứ: đo trên iPhone 1 luồng 0,63 CPU-s/audio-s như 2 luồng nhưng RTF 0,60 so với 0,32, hụt tiếng khi nóng.
- **Spin**: mô tả cũ nói về trạng thái *tắt* trong khi nhãn công tắc là trạng thái *bật*, kèm câu "chỉ để so sánh" khó hiểu. Mới: "Bật: luồng quay vòng chờ việc thay vì ngủ ngay, tốn CPU và nóng máy hơn mà không nhanh hơn. Nên để tắt." (`session.intra_op.allow_spinning`; iPhone 2 luồng: tắt 0,63 CPU-s/audio-s RTF 0,32, bật 0,76 RTF 0,38 — một lần đo, máy đã ấm nên không ghi % vào UI; audio giống hệt từng bit).
- **Mô tả gọn**: tốc độ tổng hợp gộp 2 dòng còn 1 ("Model nói nhanh hơn, máy mát hơn. 1.15x ít lặp chữ nhất, quá 1.25x mất chữ."); số luồng "Nhiều luồng ít chờ hơn nhưng nóng máy hơn." (+ " Tiết kiệm pin đang ghim Cân bằng + 2 luồng."); ngưỡng đệm "Nạp thêm khi đệm còn dưới N giây.".
- **Sửa tài liệu lệch code** (người dùng duyệt): doc `defaultThreadCount` ("Đã đo và giữ 4" trong khi giá trị là 2), `rules.md` "so 4 is kept" và "opt-in Tiết kiệm pin" (mặc định đang BẬT), doc `VieNeuTTSService.powerSaving`.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 vi phạm nền cũ, 0 mới. **Không build tại chỗ** (Windows) — CI nhánh `refactor/god-objects`.
