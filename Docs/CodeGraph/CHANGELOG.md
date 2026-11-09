# CHANGELOG - Nhật ký Thay đổi CodeGraph Tàng Công Các

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **Tàng Công Các**.

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
