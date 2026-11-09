# CHANGELOG - Nhật ký Thay đổi CodeGraph Tàng Công Các

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **Tàng Công Các**.

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

## [1.3.783] - 2026-11-09

### feat: danh sách tập phim chọn kiểu Lưới hoặc Danh sách như mục lục truyện, nhớ theo tiện ích

Người dùng: *"sửa sheet danh sách tập có nút chọn layout của danh sách tập (có 2 loại là danh sách và lưới, danh sách thì giống mục lục truyện) nhớ lựa chọn layout theo tiện ích"*. Anh Bửu chọn: nhóm theo chip như Lưới; panel tập toàn màn dùng chung lựa chọn; duyệt mockup.

- **Nút đổi kiểu** (`VideoPlayerIconButton`, 17 pt nửa đậm, 36 × 38; icon = kiểu sẽ chuyển sang: `list.bullet` / `square.grid.2x2`): sheet "Tất cả tập" (`VideoWatchEpisodeSheet`) — kiểu Lưới ở cạnh tiêu đề "Danh sách tập (N)", kiểu Danh sách đứng trước ↓↑ của đầu panel; panel tập khi xem toàn màn (`VideoEpisodePanel`) — cạnh nút ✕.
- **Nhớ theo tiện ích** (`VideoEpisodeLayoutMode`, mới): từ điển UserDefaults `videoEpisodeLayoutByPackage` (`packageId` → `"list"`); chưa chọn / `packageId` rỗng ⇒ Lưới như cũ, chọn lại Lưới thì xoá mục. Sheet đọc `packageId` của phim của màn xem (`model.request.packageId`, truyền qua `VideoWatchEpisodeStrip`), panel đọc `session.launch?.extensionPackageId`. Thứ tự ↓↑ và từ khoá tìm không nhớ.
- **Kiểu Danh sách** (`VideoEpisodeListView`, mới): hàng như mục lục comic/Reader — cột số `ChapterOrdinalLabel` (theo công tắc "Hiện số thứ tự chương"), tên tập 2 dòng, tập đang phát đậm + nền mờ, đã xem mờ, đã tải ⬇ xanh trong ô 30 × 30, nhấn giữ "Tải tập này / Xoá bản tải" (khi có `downloadActions`). Phim nhiều nhóm: chip nhóm như Lưới, mỗi nhóm đánh số lại từ 1; tìm và ↓↑ áp lên nhóm đang chọn. Sheet bọc trong panel Mục lục dùng chung (`ChapterTOCPanelHeader` "Mục lục (N tập)" + ô tìm, `.chapterTOCPanel(.reader(.dark))`); panel toàn màn hẹp nên chỉ chip + hàng. Dựng bằng `ScrollView` + `LazyVStack`, không tự `dismiss` (trong panel toàn màn sẽ đóng cả trình phát).
- **Hàng chip nhóm** tách khỏi `VideoEpisodeGridView` thành `VideoEpisodeGroupTabs` (mới) để hai kiểu dùng chung; Lưới giữ y giao diện cũ, `VideoEpisodeGridView.label(of:)` chuyển tiếp sang đó.
- Giữ nguyên: dải tập ngang của màn xem; lưới tập của `VideoPlayerDetailsView` (màn dọc cũ khi chưa có màn xem). "N" ở tiêu đề / ô tìm của kiểu Danh sách là mọi tập phát được (như tiêu đề Lưới), còn tìm chỉ trong nhóm đang chọn.
- Chuyển `[1.3.753]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng:** đọc code. `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows). Chưa thử trên máy.

## [1.3.782] - 2026-11-09

### fix: chỉ báo hỏi lại hướng xoay khi còn trang thể loại, rời trình phát không bị bật ngang lại

Rà lại 1.3.781 trước khi thử máy: `resetForExit` và lúc trình bày xong màn xem **luôn** báo UIKit hỏi lại hướng (`setNeedsUpdateOfSupportedInterfaceOrientations`). Ở lối thường (màn bên dưới là tab gốc, cho xoay ngang), cầm máy ngang rồi bấm ⌄ ⇒ `leave` xin dọc, nhưng lần báo hỏi lại ở `onDisappear` có thể làm iOS xoay Kệ / Khám phá ngang trở lại theo cảm biến — trước 1.3.781 không có.

- `VideoWatchPagePresenter.hasOpenPage` (mới): còn trang nào đang hiện (kể cả trang nằm dưới màn xem mở lại).
- `VideoOrientationLock.resetForExit`: hết ngang thì như cũ (xin dọc, `request` vẫn báo hỏi lại trước khi xin); không ngang thì chỉ báo hỏi lại khi vừa bỏ khoá xoay (như trước 1.3.781) hoặc còn trang chỉ dọc.
- `VideoWatchPresenter.present`: chỉ báo hỏi lại sau khi trình bày khi còn trang.
- Giữ nguyên: `request` luôn báo hỏi lại ngay trước `requestGeometryUpdate` (sửa nút Toàn màn / Xoay; có lời xin tường minh theo sau nên không xoay lạc); `PortraitHostingController` nhường hướng cho màn xem phía trên.
- **Kiểm chứng:** đọc code. `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows). Chưa thử trên máy.

## [1.3.781] - 2026-11-09

### fix: nút Toàn màn xoay ngang được khi mở lại phim từ cửa sổ nhỏ trên trang thể loại

Người dùng: *"Có lỗi video -> mở danh sách video từ genres -> mở lại video pip -> bấm nút video full screen -> không xay ngang lại"*.

- **Nguyên nhân**: bấm thể loại / "Xem thêm ›" lúc màn xem đang phát ⇒ phim vào cửa sổ nhỏ, màn đóng, trang danh sách mở bằng `PortraitHostingController` (chỉ dọc). Chạm cửa sổ nhỏ ⇒ màn xem mở lại **đè lên** trang đó (`VideoWatchPresenter` trình bày lên VC trên cùng), trang chỉ dọc vẫn trong chuỗi trình bày; `VideoOrientationLock.rotate` lại chỉ báo UIKit hỏi lại hướng khi đang khoá xoay ⇒ xin ngang bị từ chối (hoặc UIKit dùng mask `.portrait` cũ).
- **Trang nhường hướng cho màn xem nằm trên nó**: `PortraitHostingController.supportedInterfaceOrientations` trả `VideoOrientationLock.supportedMask` khi trong chuỗi `presentedViewController` của trang có `VideoPlayerHostingController` chưa bị gỡ; còn lại vẫn `.portrait` (sheet Bộ lọc / nhấn giữ của trang không mở khoá ngang; trang đè lên màn xem giữ như cũ).
- **Luôn báo UIKit hỏi lại hướng**: `VideoOrientationLock.request` gọi `refreshSupportedOrientations()` trước mỗi `requestGeometryUpdate` (nút Toàn màn, Xoay, dự phòng khoá xoay); `resetForExit` luôn báo hỏi lại (màn xem rời đi ⇒ trang lấy lại `.portrait`); `VideoWatchPresenter.present` báo hỏi lại khi trình bày xong ⇒ nghiêng máy thật cũng xoay được. `refreshSupportedOrientations` bỏ `private`.
- **Kiểm chứng:** đọc code; bấm thể loại lần nữa ở màn xem mở lại ⇒ phim vào cửa sổ nhỏ, trang cũ (không còn màn xem phía trên) về `.portrait` rồi mới bị đóng. `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows). Chưa thử trên máy; nếu vẫn không xoay, log `❌ [VideoPlayer] Không xoay được màn hình: …` (luôn ghi) cho biết mask UIKit đang dùng.

## [1.3.780] - 2026-11-08

### feat: nút sửa từng name trong danh sách name AI, mở màn Sửa từ như VP/Name

Người dùng: *"thêm nút edit cho mỗi tên trong danh sách name của AI, bấm vào sẽ hiển ra màn hình giống sửa vp/name trong từ điển. Bấm cập nhật sẽ tuỳ theo vế trái mà sửa nghĩa hoặc thêm từ mới"*, rồi chọn *"lưu vào tin luôn"*.

- **Nút bút chì** trên mỗi hàng của sheet "Duyệt tên riêng & VP" (`ReaderAINameReviewCardView`, trước nút ✕, kiểu nút Sửa của `DictionaryEntryRow`, vùng chạm 36 pt) ⇒ mở **đúng màn Sửa từ** của danh sách VP/Name (`DictEntryEditSheet`): nới/thu vùng chọn, token, chip nghĩa, aa…AA, tra cứu, gõ lại từ gốc. Token / nghĩa gợi ý / chip tra theo từ điển của truyện. Badge header ghi **"AI · Riêng truyện"** (tham số mới `badgeText`, mặc định `nil` ⇒ màn từ điển không đổi) vì danh sách AI chưa có loại — Name hay VP chọn lúc Lưu.
- **"Cập nhật" theo vế trái**, đúng luật màn Sửa từ: chọn cả từ gốc ⇒ sửa nghĩa; gõ lại cả từ gốc ⇒ đổi khoá; chọn một phần ⇒ thêm name mới ngay dưới name đang sửa. Khoá đích đã có trong danh sách ⇒ ghi đè nghĩa mục đó (màn báo trước), không tạo bản trùng. Mục sửa / thêm được chọn sẵn; đổi khoá / thêm mục ⇒ tra lại cờ NE/VP ngoài main (chỉ chép cờ, không đổi trạng thái chọn); sửa nghĩa ở màn ⚙ cũng tra lại. Chưa ghi từ điển — nút "Lưu" vẫn lo.
- **Lưu vào tin nguồn**: `AINameEdit` (`Services/AI/`, mới) là một phép áp **cùng lúc** lên danh sách của sheet, nội dung tin (dòng `từ=nghĩa` thay tại chỗ, dòng khác giữ nguyên, dòng trùng khoá cũ/mới bỏ như nút ✕) và `extractedNames` của tin cũ (`ReaderAIFullScreenView+NameEdit`). Như nút ✕ (1.3.611), coordinator nhớ chuỗi sửa **theo tin** (`AIRuntimeCoordinator.nameEdits`, `+NameEdits`) và `applyBatchProgress` / `writeNames` áp lại sau bộ lọc khoá đã ✕ (`applyingUserNameChanges`) ⇒ lượt quét đang chạy và "Thử lại k lượt lỗi" không đè mất; context thử lại của đúng tin đó sửa luôn. ✕ một name sau khi đã sửa ⇒ ghi thêm phép xoá vào cuối chuỗi (`forgetName`), kẻo name do lần sửa tạo ra quay lại.
- **Kiểm chứng:** đọc code + diff; `keepingUnremovedNames` chỉ còn được gọi qua `applyingUserNameChanges`; `ReaderAINameReviewSheet` chỉ dựng ở màn AI; `DictEntryEditSheet` thêm chỗ dựng thứ hai, chỗ cũ (`DictEntrySheet`) không truyền `badgeText`. `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows). Chưa thử trên máy: sửa trong lúc lượt quét đang ghi vào chính tin đó; mở lại sheet sau khi sửa.

## [1.3.779] - 2026-11-07

### feat: độ sáng chỉnh khi xem phim vẫn giữ khi phim ở cửa sổ nhỏ

Người dùng: *"chỉnh độ sáng theo video vẫn giữ kể cả ở chế độ pip"*.

- Cửa sổ phim nhỏ (`VideoMiniPlayerWindowManager`) là một chủ của `VideoBrightnessKeeper` như màn xem phim: hiện ⇒ giữ mức sáng đã vuốt chỉnh của trình phát; thu vào hub / tắt phim ⇒ trả độ sáng của máy. Mở cửa sổ **trước** khi màn to rời đi và màn to mở lại **trước** khi cửa sổ ẩn ⇒ độ sáng không nháy khi chuyển qua lại. App vào nền vẫn trả độ sáng của máy như cũ, quay lại lúc cửa sổ còn hiện thì áp lại.
- **Kiểm chứng:** đọc code + diff; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows). Chưa thử trên máy.

## [1.3.778] - 2026-11-07

### feat: bộ lọc NSFW riêng của tab Kệ sách: Không hiển thị, Tất cả, Chỉ NSFW

Người dùng: *"thêm filter, chỉ nfsw, không hiển thị nfsw, tất cả ở phần tùy chọn kệ của tab kệ sách"*; anh Bửu chốt: *"Độc lập, ba công tắc này dành riêng cho tab kệ sách thôi. Tắt app, tắt màn hình, về home mở lên lại sẽ về không hiển thị nfsw"*, bấm nút Home trong app cũng về "Không hiển thị NSFW".

- Ngăn kéo "…" của tab Kệ Sách: công tắc NSFW chung được thay bằng nhóm **"NSFW"** ba hàng chọn (`SideDrawerOptionRow`): **Không hiển thị NSFW** (mặc định) · **Tất cả** · **Chỉ NSFW** (`ShelfNsfwFilter`). Công tắc NSFW chung vẫn ở Khám phá / Cài đặt.
- **Độc lập** với công tắc chung: chỉ quyết định danh sách Kệ + Lịch sử (`ShelfBookPartition(nsfwFilter:)`); Bộ sưu tập / Tải / Tìm trên kệ vẫn theo công tắc chung. "NSFW" = truyện của nguồn NSFW hoặc truyện tự đánh dấu NSFW.
- **Không lưu**: `ShelfNsfwFilterState` (singleton trong bộ nhớ, sống qua lần dựng lại tab) — mở app, app vào nền (khoá màn hình / về màn hình chính) hay bấm nút Home trong app (nút Home nổi, "Về Khám phá" của màn xem phim) đều về "Không hiển thị NSFW".
- **Kiểm chứng:** đọc code + diff; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows). Chưa thử trên máy.

## [1.3.777] - 2026-11-07

### feat: bấm nút Home ở bất kỳ đâu cũng tắt NSFW như nút Home của màn xem phim

Người dùng: *"ở mọi nơi, chỉ cần nhấn nút home thì phải tắt nfsw (giống như đang ở màn hình xem phim của nfsw vậy)"*.

- Mọi lối Home nổi (nút tròn của trang con, pill "Về trang gốc" trong menu "+", FAB Chi tiết, trang đè lên màn xem phim) chạy luật chung `VideoLeaveToHubCoordinator.applyLeaveRules` **trước** khi về trang gốc tab: công tắc NSFW đang bật ⇒ tắt (Khám phá tự đổi sang nguồn không 18+), phim 18+ đang phát tắt tiếng theo "Tắt tiếng khi mở phim" — như nút Home của màn xem phim. Gắn một chỗ ở `FloatingHomePlacement.homeAction`.
- `keepsPlacement`: phim đang ở cửa sổ nhỏ / vừa thu nhỏ theo cài đặt vuốt xuống giữ nguyên chỗ, guard NSFW không kéo vào hub.
- `CLAUDE.md` / `AGENTS.md` mục quy ước UI.
- **Kiểm chứng:** đọc code + diff; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows). Chưa thử trên máy.

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
