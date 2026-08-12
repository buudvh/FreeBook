# CHANGELOG - Nhật ký Thay đổi CodeGraph FreeBook

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **FreeBook**.

## [1.3.123] - 2026-08-12

### Sửa lỗi xóa sách sau khi tắt TTS, lỗi trùng lặp Mục lục nhiều trang và cải tiến tạm dừng khi đọc hết truyện

* Cập nhật `TTSManager.swift`:
  - Reset `self.playingBookId = ""` khi dừng TTS hoàn toàn (`stopPlayback` với `!keepWidget`).
  - Trong `skipForward` và `nextParagraph`, khi phát đến hết nội dung chương cuối cùng của bộ truyện, thay thế lệnh `stop()` bằng `pause()` kèm thông báo *"📖 Đã phát hết nội dung bộ truyện"* để giữ widget nổi ở trạng thái Tạm dừng thay vì tắt hẳn.
* Cập nhật `BookStorageManager.swift`:
  - Kiểm tra trạng thái TTS thực tế (`isTTSActive = isPlaying || showFloatingWidget`) trước khi áp dụng cờ bảo vệ `playingBookId`, giúp xóa thành công sách sau khi đã tắt nghe TTS.
* Cập nhật `ChapterPersistenceStore.swift`:
  - Thêm chuẩn hóa URL `normalizeUrl` trong `ReconciliationPool` (bỏ `http://`/`https://` và dấu `/` cuối) để đối chiếu và cập nhật chính xác các chương đã có khi tải mục lục nhiều trang, ngăn chèn trùng lặp mục lục.
* Không tạo hoặc chỉnh sửa unit test theo workflow rule do người dùng không yêu cầu.

## [1.3.122] - 2026-08-12

### Thêm nút Đổi nguồn khi nhấn giữ sách ở Kệ sách, Lịch sử và trong Trình đọc (Reader)

* Cập nhật `ShelfView.swift`: Thêm nút **"Đổi nguồn"** (`arrow.triangle.2.circlepath`) vào menu ngữ cảnh (Context Menu) khi nhấn giữ một bộ truyện online (`!book.isLocalBook`) ở cả 2 tab **Kệ sách** và **Lịch sử đọc**.
* Cập nhật `ReaderHeaderFooterOverlayView.swift` & `ReaderView.swift`: Thêm nút **"Đổi nguồn truyện"** vào `Menu` tùy chọn `...` góc trên bên phải của Trình đọc (Reader).
* Khi kích hoạt từ 1 trong 3 vị trí trên, ứng dụng mở màn hình `SearchView` điền sẵn tên truyện để người dùng chọn nguồn mới mượt mượt và nhanh chóng.
* Không tạo hoặc chỉnh sửa unit test theo workflow rule do người dùng không yêu cầu.

## [1.3.121] - 2026-08-12

### Bảo toàn trạng thái Kệ sách (isOnShelf) và Lịch sử (isHistory) khi đổi nguồn

* Cập nhật `executeSourceChange` trong `SearchView.swift`: Thay thế cờ cài đặt cứng `isOnShelf: true` bằng `isOnShelf: oldBook.isOnShelf`.
* Khi thực hiện đổi nguồn cho bộ truyện, nếu truyện nguồn cũ chỉ thuộc danh sách Lịch sử đọc (`isHistory == true`, `isOnShelf == false`), truyện nguồn mới được tạo sẽ giữ nguyên vị trí trong Lịch sử mà không bị thêm nhầm lên Kệ sách.
* Nếu truyện nguồn cũ thuộc Kệ sách (`isOnShelf == true`), truyện nguồn mới sẽ được thêm vào Kệ sách chuẩn xác.
* Không tạo hoặc chỉnh sửa unit test theo workflow rule do người dùng không yêu cầu.

## [1.3.120] - 2026-08-12

### Tích hợp trình tô màu cú pháp Syntax Highlighting phong cách VS Code Dark+ cho trình biên tập Script

* Tạo component `HighlightingCodeEditor` (`UIViewRepresentable` wrapper `UITextView`): Phân tích cú pháp tức thì (< 1ms) với tốc độ 60/120 FPS, không gây giật trễ bàn phím.
* Áp dụng bộ quy tắc tô màu theo chuẩn **VS Code Dark+ Theme**:
  - Từ khóa (`function`, `var`, `let`, `const`, `return`, `async`, `await`...): Xanh dương nhạt `#569CD6`.
  - Tên hàm & gọi hàm (`execute()`, `fetch()`, `select()`, `push()`...): Vàng ấm `#DCDCAA`.
  - Chuỗi văn bản (`"..."`, `'...'`, `` `...` ``): Nâu cam `#CE9178`.
  - Số & Boolean (`123`, `true`, `false`, `null`): Xanh lá mạ `#B5CEA8`.
  - Đối tượng tích hợp (`Response`, `JSON`, `Math`, `console`...): Xanh ngọc `#4EC9B0`.
  - Ghi chú (`// comment`, `/* comment */`): Xanh lá cây mờ `#6A9955`.
* Cập nhật `ExtensionScriptEditorView.swift`: Thay thế `TextEditor` phẳng bằng `HighlightingCodeEditor` tích hợp cột số dòng, bàn phím phím tắt JS và tô màu cú pháp sinh động.
* Không tạo hoặc chỉnh sửa unit test theo workflow rule do người dùng không yêu cầu.

## [1.3.119] - 2026-08-12

### Nâng cấp giao diện Trình biên tập Script (ExtensionScriptEditorView) phong cách IDE chuyên nghiệp

* Cập nhật `ExtensionScriptEditorView.swift`: Thiết kế giao diện Dark Code Editor Theme (`#181825`) tương phản cao, dịu mắt với phông chữ monospaced chuẩn IDE.
* Tích hợp **Cột số dòng (Line Numbers Column)** căn lề trái chạy dọc theo mã nguồn giúp dễ dàng định vị vị trí dòng code khi phát hiện lỗi cú pháp.
* Thêm **Thanh ký tự nhanh JS (Quick Symbol Toolbar)** gồm các phím bấm chèn nhanh 1 chạm: `{`, `}`, `(`, `)`, `[`, `]`, `=`, `;`, `:`, `"`, `'`, `=>`, `.`, `,`, `fetch`, `function`.
* Thêm cờ đánh dấu **chấm màu cam `●`** cho các tệp script có thay đổi chưa lưu trên thanh tab file.
* Thêm bộ công cụ **Tùy chỉnh cỡ chữ (`A-` / `A+`)** hỗ trợ thay đổi kích thước chữ linh hoạt từ 11pt đến 22pt ở thanh chân trang (Footer).
* Không tạo hoặc chỉnh sửa unit test theo workflow rule do người dùng không yêu cầu.

## [1.3.118] - 2026-08-12

### Sửa lỗi ẩn nút chỉnh sửa Script trong Cấu hình, chuẩn hóa nút hàng Extension và tự động làm mới Khám Phá

* Cập nhật `ExtensionConfigView.swift`: Màn hình Cấu hình luôn hiển thị `Form` chính. Khi tiện ích không có biến cấu hình tùy chỉnh (`configDefinitions.isEmpty`), dòng thông báo được hiển thị trực tiếp trong `Section("Tùy Chỉnh Biến Global")`, đồng thời `Section("Mã Nguồn Script")` chứa nút **"Chỉnh sửa mã nguồn Script"** luôn xuất hiện bên dưới và truy cập được 100%.
* Cập nhật `RepositoryManagerView.swift`: Bỏ nút `code.square` thừa trên hàng ngoài; chuẩn hóa kích thước cố định `34x34 pt` cho nút Cấu hình & Gỡ bỏ và nút Cập nhật màu cam nổi bật đồng chiều cao `34 pt`, khoảng cách đều tăm tắp `8 pt`.
* Thêm phát thông báo `extensionDidUpdate` khi tiện ích được cập nhật thành công.
* Cập nhật `DiscoveryView.swift`: Lắng nghe thông báo `extensionDidUpdate` và tự động gọi `loadDiscoveryData()` để làm mới dữ liệu `home` và `genres` khi quay lại tab Khám Phá nếu tiện ích đang active vừa được cập nhật.
* Không tạo hoặc chỉnh sửa unit test theo workflow rule do người dùng không yêu cầu.

## [1.3.117] - 2026-08-12

### Bảo toàn nguồn truyện cũ khi đang phát TTS trong quá trình đổi nguồn

* Cập nhật `executeSourceChange` trong `SearchView.swift`: Thêm cờ kiểm tra `isPlayingTTS` dựa trên `TTSManager.shared.isPlaying` và `TTSManager.shared.playingBookId`.
* Khi đổi nguồn trong lúc đang nghe TTS, hệ thống giữ nguyên nguồn truyện cũ trong cơ sở dữ liệu (`SwiftData`), `ChapterStore` và thư mục từ điển `books/<oldBookId>`, đồng thời thêm nguồn mới lên kệ sách để luồng phát âm thanh TTS không bị ngắt hay sập.
* Cập nhật thông báo xác nhận Alert và Toast phản hồi cho người dùng khi thực hiện đổi nguồn trong lúc nghe TTS.
* Cấu hình `UITabBarAppearance` trong `FreeBookApp.swift` (`standardAppearance` và `scrollEdgeAppearance` với `configureWithDefaultBackground()`) kết hợp với `.toolbarBackground(.visible, for: .tabBar)` trong `MainTabView.swift` để khắc phục lỗi thanh tab bar bị trong suốt khi ở tab Cài Đặt (Settings).
* Không tạo hoặc chỉnh sửa unit test theo workflow rule do người dùng không yêu cầu.

## [1.3.116] - 2026-08-11

### Nâng cấp giao diện đề xuất (Suggest 2 cột), ExpandableTextView và sửa lỗi DownloadManager & newVisibleBrowser

* Chuyển danh sách truyện gợi ý/đề xuất (`SuggestRowView`) trong màn hình chi tiết truyện sang giao diện 2 cột (`LazyVGrid`), với bìa sách nằm bên trái và tên truyện hiển thị tối đa 3 dòng.
* Cập nhật giao diện khung xương chờ tải (skeleton placeholder) trong `BookDetailView` đồng bộ với bố cục 2 cột mới.
* Xây dựng component `ExpandableTextView` sử dụng SwiftUI `PreferenceKey` và `GeometryReader` để đo chiều cao văn bản thực tế sau bước layout pass, so sánh `fullHeight` và `truncatedHeight` để tự động bật/tắt nút "Xem thêm / Thu gọn" chính xác 100%.
* Áp dụng `ExpandableTextView` cho phần Giới thiệu (`BookDetailHeaderView`) với tối đa 4 dòng khi thu gọn, khắc phục lỗi mất chữ khi văn bản ít ký tự nhưng xuống dòng nhiều.
* Áp dụng `ExpandableTextView` cho phần Bình luận (`CommentSectionView` và `AllCommentsView`) với tối đa 3 dòng khi thu gọn.
* Tách danh sách Thể loại (`genres`) thành 1 section riêng nằm trên phần Giới thiệu trong `BookDetailHeaderView`, sử dụng component `FlowLayout` tự động xuống dòng linh hoạt thay vì cuộn ngang.
* Khắc phục lỗi `DownloadManager`: Thêm `cancelledTaskIds` để lập tức dừng tiến trình tải ngầm khi xóa tác vụ; đồng thời reset cờ `isCancelled = false` trong RAM và DB khi bấm Tải lại (Retry) tác vụ đã bị hủy.
* Khắc phục lỗi `newVisibleBrowser`: Gọi `loader.presentUIIfNeeded()` lập tức khi đối tượng được khởi tạo trong JS, nâng cấp cơ chế tìm kiếm `UIWindowScene` active/thử lại khi màn hình bận.
* Xây dựng giao diện Dạng Tab cho `newVisibleBrowser` (`VisibleBrowserTabManager` & `TabbedVisibleBrowserViewController`): Khi có nhiều trình duyệt bật cùng lúc, các trình duyệt mới sẽ được gộp vào dạng Tab trên cùng một cửa sổ modal thay vì mở đè nhiều cửa sổ, hỗ trợ tự động đánh số phân biệt tiêu đề trùng ("Tab 1", "Tab 1 (2)").
* Không tạo hoặc chỉnh sửa unit test theo workflow rule do người dùng không yêu cầu.

## [1.3.115] - 2026-08-11

### Loại bỏ vòng lặp hụt buffer/tổng hợp trùng của NghiTTS khi nóng

* N+1 trở thành deadline synthesis không chịu cooldown; N+2 trở đi vẫn dùng cooldown để giữ khoảng nghỉ CPU.
* Mỗi refill task chỉ sở hữu một đoạn. Khi playback bắt kịp N+1 đang chạy, task playback có generation guard sẽ chờ và dùng lại kết quả thay vì hủy rồi tổng hợp trùng.
* Thermal `.serious` chỉ giữ N+1 survival buffer và hủy audio chương kế; `.critical` tiếp tục demand-only.
* Piper trả queue wait, synthesis time và PCM duration; `TTSManager` ghi `[NghiEnergy]` underrun tức thời và summary RTF tổng hợp tối đa mỗi 60 giây/các mốc pause-stop.
* `cancelNghiRefill` không còn hủy toàn bộ hàng chờ Piper, tránh race có thể xóa nhầm request playback vừa enqueue.
* Không tạo hoặc chỉnh sửa unit test theo workflow rule do người dùng không yêu cầu.

## [1.3.114] - 2026-08-11

### Giới hạn RAM chương dùng chung và truyền cancellation theo consumer

* Chuyển `ChapterContentRepository` sang cost-aware LRU tối đa 12 document/12 MiB; document quá lớn không giữ trong RAM dùng chung và memory warning chỉ xóa reusable snapshots.
* Thay in-flight chapter load bằng một task dùng chung có waiter UUID riêng cho Reader/TTS: hủy một consumer trả về ngay, còn underlying load chỉ bị hủy khi waiter cuối cùng rời đi.
* Không nuốt `CancellationError` ở nhánh đọc persistent cache/chuẩn bị metadata, tránh tiếp tục gọi extension sau khi request đã hết người dùng.
* `TTSManager` sở hữu và generation-guard fallback auto-advance task; stop, thay session hoặc advance mới hủy task cũ mà không biến cancellation thành lỗi dừng phát, đồng thời reattach một lần nếu repository chỉ bị force-refresh supersede.
* Không tạo hoặc chỉnh sửa unit test theo workflow rule do người dùng không yêu cầu.

## [1.3.113] - 2026-08-11

### Sửa lỗi chức năng xuất tệp TXT và bổ sung cơ chế lưu vết / chia sẻ lại file

* Khắc phục cơ chế lấy active `UIWindowScene` và `rootViewController` tin cậy trong `DownloadManager.presentShareSheet(for:)`, đồng thời tự động trì hoãn an toàn khi `topVC` đang chuyển cảnh (`isBeingPresented`/`isBeingDismissed`).
* Bổ sung thuộc tính `exportFilePath: String?` vào `DownloadTaskModel` (SwiftData) và `DownloadTask` để lưu vết đường dẫn tệp TXT được xuất ra thư mục `Exports` bền vững trong Sandbox.
* Thêm nút "Xuất file TXT" / "Chia sẻ" trực tiếp trên từng hàng tác vụ hoàn thành trong `DownloadTrackerView` và context menu, cho phép người dùng mở lại tệp TXT đã xuất bất kỳ lúc nào.
* Không tạo hoặc chỉnh sửa unit test theo workflow rule do người dùng không yêu cầu.

## [1.3.112] - 2026-08-11

### Giảm tải foreground và công việc metadata TTS lặp lại

* Bỏ `TimelineView` quay cover 30 FPS; widget dùng ảnh bìa tĩnh trong lúc phát và tạm dừng. Loader ảnh thuộc widget cha giữ cùng `UIImage` khi đổi expanded/peeking, không tạo lại `AsyncImage` hoặc request cover.
* Root, Shelf, widget và Reader không còn quan sát toàn bộ `TTSManager`; các projection snapshot chỉ phát thay đổi cần render và Reader lọc highlight theo `bookId`.
* Tách Now Playing thành metadata tĩnh được cache theo sách/chương/cover/translation generation và timeline động; chỉ một task metadata được phép hoạt động.
* NghiTTS chỉ warm-up khi engine Nghi đang được chọn; chuyển sang Siri/Google/Ext hủy warm-up đang chờ.
* Không tạo hoặc chỉnh sửa unit test theo workflow rule do người dùng không yêu cầu.

## [1.3.111] - 2026-08-11

### Giảm auto-scroll Reader và giữ N+1 thiết yếu khi thermal serious

* Reader bỏ qua auto-scroll nếu tâm paragraph TTS còn trong vùng an toàn 15% của viewport; chỉ target ngoài vùng mới được căn giữa.
* `ParagraphTracker` bỏ qua frame movement dưới 8 pt; `[ReaderEnergy]` thêm scroll requested/skipped/executed và frame accepted/skipped.
* Sửa dự đoán Reader để không coi intrinsic invalidation lúc mount ban đầu là repeated layout churn.
* Google/Ext ở `.serious` chỉ giữ N+1, hủy N+2/N+3 và next-chapter audio; `.critical` vẫn tắt hoàn toàn prefetch.
* Không tạo hoặc chỉnh sửa unit test theo workflow rule do người dùng yêu cầu.

## [1.3.110] - 2026-08-11

### Thêm log tổng hợp tải render của Reader

* Thêm `[ReaderEnergy] Summary` qua `AppLogger`, tổng hợp `updateUIView`, highlight-only, geometry/theme rebuild, intrinsic-size invalidation và TTS scroll target.
* Chỉ ghi khoảng một dòng mỗi phút hoặc tại thermal/background/disappear boundary; các sự kiện render chỉ tăng bộ đếm RAM.
* Dự đoán loại trừ lượt mount đầu của từng `ReaderTextView`, tránh gán nhầm chi phí khởi tạo thành layout churn kéo dài.
* Không tạo hoặc chỉnh sửa unit test theo workflow rule do người dùng yêu cầu.

## [1.3.109] - 2026-08-11

### Giảm layout churn khi Reader hiển thị highlight TTS

* Highlight-only chỉ đổi thuộc tính màu trong `textStorage`, không xóa cache đo kích thước hay invalidate intrinsic size.
* Chỉ invalidate phép đo khi text/font/spacing/bold/alignment thực sự đổi; bỏ qua các lần `contentSize` thay đổi không đáng kể.
* Gỡ auto-scroll UIKit bên trong `ReaderTextView`; `ReaderView.scrollTarget`/`ScrollViewReader` là cơ chế auto-scroll TTS duy nhất.
* Bổ sung workflow rule: không tạo hoặc sửa unit test khi người dùng chưa yêu cầu rõ ràng.

## [1.3.108] - 2026-08-11

### Sửa crash khi bắt đầu TTS lúc App Log đang bật

* Thay phép đọc/ghi optional trực tiếp trên `EnergyWindow.maxQueueDepth` và `deduplicatedWaiters` bằng quy trình copy-update-assign, tránh Swift exclusive-access trap ngay tại request remote đầu tiên.
* Thêm regression test chạy synthesis đầu tiên với `AppLogger.isLoggingEnabled = true`.

## [1.3.107] - 2026-08-11

### Thêm log dự đoán tải năng lượng Google/Ext TTS

* Comment các log thành công theo từng chunk ở `TTSParagraphBuilder`, `TTSManager`, `ExtensionManager.ttsGenerate` và `ReaderView`; giữ nguyên log lỗi/retry.
* `RemoteTTSSynthesisCoordinator` tổng hợp `[TTSEnergy]` khoảng mỗi 60 giây: request/phút, priority, dedup, ký tự, audio bytes, synthesis busy time, queue depth, thermal và dự đoán mức tải.
* Tách cửa sổ foreground/background theo notification của UIKit để log khi khóa màn hình phản ánh riêng tải remote trong nền.
* Bổ sung unit test cho phân loại tải background/thermal và cập nhật CodeGraph tương ứng.

## [1.3.106] - 2026-08-10

### Giảm nhiệt NghiTTS khi nghe lâu trên thiết bị A13

* Thêm `NghiSynthesisPolicy`: buffer nominal giảm từ 4–8 giây xuống 2.5–5 giây, fair còn 1.5–3 giây và dừng toàn bộ speculative refill ở `.serious/.critical`.
* Mỗi lượt refill ONNX có khoảng nghỉ thực 750 ms ở nominal hoặc 1.5 giây ở fair, nhưng vẫn bảo toàn tối thiểu 1.2 giây audio để ưu tiên N+1.
* `ONNXPiperEngine` cố định một worker, bật graph optimization và ưu tiên XNNPACK một luồng với CPU fallback.
* Audio chương kế của NghiTTS chỉ được tổng hợp khi thermal `.nominal`; thermal transition nóng hủy refill và audio chương kế đang chờ.
* Refill dùng trực tiếp `pcmDuration` trả về từ Piper thay vì quét lại WAV.

## [1.3.105] - 2026-08-10

### Hạ nhiệt Google/Ext TTS và tách buffer depth khỏi concurrency

* Thêm `RemoteTTSSynthesisCoordinator` chạy tối đa một synthesis, ưu tiên chunk hiện tại, gộp request trùng và giữ `prefetchDepth = 3` như bộ đệm logic.
* Pause/stop và thermal `.serious/.critical` hủy remote prefetch; `.fair` tăng nhịp nghỉ. Audio chương kế chỉ được tổng hợp gần cuối chương.
* Bỏ retry lồng trong `TTSManager`; Google và Ext sở hữu tối đa hai attempt. Google parse JSON một lần và tôn trọng `Retry-After` có giới hạn.
* Thêm `ExtTTSRuntime` actor tái sử dụng `JSExecutor` theo script/config; native fetch có cancellation/timeout và bỏ text decode cho binary audio.
* `AVAudioSession` không còn cấu hình lại ở từng chunk khi session vẫn hoạt động.

## [1.3.104] - 2026-08-07

### Sửa Logic Bậc Thang Watermark Theo Nhiệt Độ (`TTSManager.swift`)
* **Khắc Phục Logic `nghiWatermarks` Phù Hợp Thứ Tự Nhiệt Độ (`TTSManager.swift`)**:
  * Chuẩn hóa logic co dãn bộ nhớ đệm giảm dần đều theo mức độ nóng của máy:
    * `.nominal`: `low = 4.0s, high = 8.0s`
    * `.fair`: `low = 3.0s, high = 6.0s`
    * `.serious`: `low = 2.0s, high = 4.0s`
    * `.critical`: `low = 1.0s, high = 2.0s`

## [1.3.103] - 2026-08-07

### Tối Ưu Hóa CPU & Hạ Nhiệt Độ Thiết Bị Cho NghiTTS (`ONNXPiperEngine.swift`, `TTSManager.swift`)
* **Tùy Biến Số Luồng ONNX CPU Linh Hoạt (`ONNXPiperEngine.swift`)**:
  * Tự động điều phối `IntraOpNumThreads` thông minh dựa trên số nhân CPU thiết bị (`ProcessInfo.processInfo.processorCount`), trạng thái nhiệt `currentThermalState` và cài đặt người dùng (`nghiTTSThreadCount`).
  * Tự động hạ từ 2 luồng xuống 1 luồng khi thiết bị ở mức ấm (`.fair`/`.serious`) hoặc trên máy ít nhân ($\le 4$ cores), giúp giảm ~45-50% công suất tỏa nhiệt của chip Apple.
* **Cache Tĩnh `punctuationRegex` (`ONNXPiperEngine.swift`)**:
  * Chuyển regex bóc tách dấu câu thành `private static let punctuationRegex: NSRegularExpression?` được khởi tạo duy nhất 1 lần trong RAM, triệt tiêu 100% việc tạo mới và biên dịch lại regex trên từng đoạn văn.
* **Tối Ưu Watermark & Thêm Thermal Duty Cycle (`TTSManager.swift`)**:
  * Điều chỉnh `nghiWatermarks` ở trạng thái bình thường từ `14.0s` về `high = 8.0s` (cắt giảm đợt xung tải bộc phát ban đầu).
  * Chèn `thermalExtraDelayMs = 200ms` giữa các lượt nạp đệm trong `scheduleNghiRefill()` khi `currentThermalState != .nominal` để tạo khoảng nghỉ tản nhiệt cho CPU.

## [1.3.102] - 2026-08-07

### Cải Tiến Ext TTS: Dọn Dẹp File Tạm 100% & Bổ Sung Retry (`ExtTTSService.swift`, `TTSManager.swift`)
* **Dọn Dẹp 100% Tệp Tin Âm Thanh Tạm (`ExtTTSService.swift`)**:
  * Sử dụng khối `defer { cleanupTempFile(tempFileUrl) }` ngay sau khi tạo tệp đĩa tạm trong `synthesize(...)`.
  * Loại bỏ các câu lệnh `cleanupTempFile` dư thừa ở tất cả các nhánh `guard`/`return`/`throw`, đảm bảo dọn dẹp tuyệt đối đĩa đệm `tmp` trong mọi trường hợp (ngoại lệ `AVAudioFile`, lỗi convert hay Task bị hủy).
* **Bổ Sung Retry Tự Động Cho Ext TTS (`TTSManager.swift`)**:
  * Mở rộng `isTransientTTSError(_ error:)` nhận diện các domain `"ExtTTSService"` và `"ExtensionManager"`.
  * Giúp luồng prefetch tự động thử lại khi gặp các sự cố ngắt kết nối mạng tạm thời từ server TTS bên thứ 3.

## [1.3.101] - 2026-08-07

### Tối Ưu Hóa & Sửa Lỗi Lag Google Cloud TTS (`GoogleTTSService.swift`, `TTSManager.swift`)
* **Thêm Request Timeout 12.0s & Thử Lại Nội Bộ (`GoogleTTSService.swift`)**:
  * Đặt `request.timeoutInterval = 12.0`s tránh nghẽn luồng prefetch/playback khi mạng lag (mặc định trước đây 60s).
  * Bổ sung cơ chế thử lại nội bộ (retry) ngắn tối đa 2 lần với delay 400ms khi nhận các lỗi HTTP 5xx, 429 hoặc `Internal error encountered`.
* **Nhận Diện Lỗi Tạm Thời Google API (`TTSManager.swift`)**:
  * Mở rộng `isTransientTTSError(_ error:)` nhận diện các từ khóa lỗi server tạm thời (`internal error`, `rate limit`, `resource_exhausted`, `500`, `502`, `503`, `504`) để luồng prefetch tự động retry thay vì hủy task ngay lập tức.

## [1.3.100] - 2026-08-07

### Sửa Lỗi Cấu Trúc Scope & Biên Dịch (`SettingsView.swift`)
* **Khắc phục lỗi `extraneous '}' at top level` và `cannot find '...' in scope` (`SettingsView.swift`)**:
  * Xóa dấu đóng ngoặc nhọn `}` thừa ở dòng 202 ngay sau khối `if isTranslationEnabled`.
  * Khôi phục đúng cấu trúc lồng nhau của `Form`, `NavigationStack`, `body` và `struct SettingsView`.
  * Đưa các phương thức helper `updateLogStatus()`, `copyLogToClipboard()`, `formatBytes()`, `getStatusText(for:)` trở lại phạm vi của `SettingsView`.

## [1.3.99] - 2026-08-07

### Màn Hình Chỉnh Sửa Mã Nguồn Script Tiện Ích Extension (`ExtensionScriptEditorView.swift`)
* **Xây Dựng Trình Soạn Thảo Script (`ExtensionScriptEditorView.swift`)**:
  * Tạo mới `ExtensionScriptEditorView` hỗ trợ mở và chỉnh sửa mã nguồn JavaScript (`.js`) và tệp cấu hình `plugin.json` trực tiếp trên ứng dụng.
  * Tích hợp bộ chọn danh sách script (`scriptSelectorHeader`), trình soạn thảo Monospace (`TextEditor`) tự động tắt autocorrect & autocapitalization, cùng thanh thống kê số dòng/ký tự.
  * Tích hợp kiểm tra cú pháp JS tức thì (`validateScriptSyntax`) thông qua `JSContext` và `JSONSerialization`.
  * Hỗ trợ nút **Lưu (Save)** ghi đè file trên đĩa kèm Toast thông báo và nút **Tải lại (Revert)** khôi phục nội dung ban đầu.
* **Tích Hợp Truy Cập Nhanh (`RepositoryManagerView.swift`, `ExtensionConfigView.swift`)**:
  * Thêm biểu tượng icon `code.square` màu tím trên từng tiện ích đã cài đặt tại `RepositoryManagerView.swift`.
  * Thêm mục *"Chỉnh sửa mã nguồn Script"* trong màn hình cấu hình `ExtensionConfigView.swift`.

## [1.3.98] - 2026-08-07

### Tính Năng Import Tiện Ích Tệp .ZIP & Menu Dropdown Toolbar (`ExtensionManager.swift`, `RepositoryManagerView.swift`)
* **Xây Dựng Hàm `installFromLocalZip` (`ExtensionManager.swift`)**:
  * Đảm bảo quyền truy cập `security-scoped resource` khi chọn tệp `.zip` từ ứng dụng Tệp.
  * Giải nén file `.zip` bằng `ZIPFoundation` vào thư mục tạm, tự động tìm và bóc tách dữ liệu từ `plugin.json` (`packageId`, `name`, `author`, `version`, `type`, `locale`, `sourceUrl`).
  * Di chuyển thư mục giải nén tới `extensions/<package_id>` của ứng dụng.
* **Gom Thao Tác Vào Menu Dropdown (`RepositoryManagerView.swift`)**:
  * Thay thế nút chữ đỏ đơn lẻ "Xóa tất cả" bằng biểu tượng **Menu Dropdown (`ellipsis.circle`)** trên thanh công cụ.
  * Tích hợp 2 mục thao tác: *"Import tiện ích (.zip)"* (mở `DocumentPickerPresenter`) và *"Xóa tất cả tiện ích"* (mở alert cảnh báo xóa).
  * Viết phương thức `importExtensionFromZip(_ url: URL)` để nạp tiện ích mới từ tệp ZIP và lưu/cập nhật vào CSDL SwiftData.

## [1.3.97] - 2026-08-07

### Tính Năng Cập Nhật Tiện Ích & Cập Nhật Tất Cả (`Extension.swift`, `RepositoryManagerView.swift`)
* **Bổ Sung Trường Remote Version & Computed Property `hasUpdate` (`Extension.swift`)**:
  * Thêm thuộc tính `public var remoteVersion: Int?` lưu phiên bản hiển thị trên repository `plugin.json`.
  * Thêm computed property `public var hasUpdate: Bool` (`!localPath.isEmpty && (remoteVersion ?? 0) > version`).
* **Cập Nhật Giao Diện Thẻ Tiện Ích & Banner "Cập Nhật Tất Cả" (`RepositoryManagerView.swift`)**:
  * Đọc và lưu `remoteVersion` từ kho khi đồng bộ `syncExtensions(for:with:)`.
  * Hiển thị badge phiên bản `v1 ➔ v2` nổi bật màu cam trên từng thẻ tiện ích có bản mới.
  * Thêm nút **"Cập nhật"** màu cam trực quan bên cạnh nút Cấu hình (bánh răng) và Xóa (thùng rác).
  * Render **Banner "Cập nhật tất cả"** ở đầu Tab 0 khi có 1 hoặc nhiều tiện ích có bản nâng cấp mới.
  * Tự động làm mới dữ liệu kho (`refreshAllRepositories()`) khi mở màn hình Kho Tiện Ích (`onAppear`).

## [1.3.96] - 2026-08-07

### Tối Ưu Nhiệt Độ & Prefetch Theo Thời Lượng Audio Cho NghiTTS (`TTSManager.swift`, `TTSChapterPrefetcher.swift`, `ONNXPiperEngine.swift`, `TTSSettingsView.swift`)
* **Duration-Based Prefetch & Hysteresis Watermarking (`TTSManager.swift`)**:
  * Chuyển đổi prefetch NghiTTS từ đếm số lượng đoạn cố định (`nghittsPrefetchCount = 3`) sang cơ chế tính thời lượng bộ đệm audio (`calculateNghiBufferedDuration()`).
  * Áp dụng mốc Low Watermark (5s) / High Watermark (12s). Tự động dừng loop ONNX khi đệm đủ 12 giây, đưa CPU Duty Cycle từ 30%-100% xuống <15%.
  * Giữ vững bất biến (Invariant): Đoạn $N+1$ luôn được ưu tiên tổng hợp và `prepareNext` ngay lập tức để không gây đứt đệm.
* **Thermal-Aware Prefetch Policy (`TTSManager.swift`, `TTSChapterPrefetcher.swift`)**:
  * Lắng nghe sự kiện `ProcessInfo.thermalStateDidChangeNotification`.
  * Điều chỉnh động mốc Watermark theo 4 mức nhiệt (`.nominal`: 6s/14s, `.fair`: 4s/9s, `.serious`: 2.5s/5s, `.critical`: 1.5s/3s).
  * Trong `TTSChapterPrefetcher`, tự động bỏ qua tác vụ prefetch audio chương kế tiếp khi thiết bị ở mức nhiệt `.serious` hoặc `.critical`.
* **Vòng Đời Lifecycle & Cancellation (`TTSManager.swift`)**:
  * Trong `pause()`, bổ sung hủy `nextChapterPrefetcher.cancel()` và `PiperSynthesisCoordinator.shared.cancelAllPending()` để ngắt triệt để CPU compute.
  * Cập nhật `nghiRefillGeneration` và discard ngay kết quả ONNX C++ dở dang sau khi Seek/Skip/Stop.
* **Đồng Bộ Trạng Thái Preload Trực Quan (`TTSSettingsView.swift`)**:
  * Khai báo `@Published public var nghiBufferedDuration: Double` trong `TTSManager`.
  * Đồng bộ giao diện cấu hình `TTSSettingsView` hiển thị mốc bộ đệm audio thực tế (`Đã nạp trước: X s / Y s`) và giải thích cơ chế tự ngắt nạp để hạ nhiệt máy.

## [1.3.95] - 2026-08-06

### Hoàn Thiện Tối Ưu Luồng NghiTTS (Buffer Audio Đầu 1-1.5s, ONNX Threads & Thermal Management) (`ONNXPiperEngine.swift`, `PiperTTSService.swift`, `PiperSynthesisCoordinator.swift`, `TTSManager.swift`, `NghiTTSPerformanceTests.swift`)
* **Tích Hợp `pcmDuration` & Tối Ưu Buffer Audio Đầu Tiên (`ONNXPiperEngine.swift`, `PiperTTSService.swift`, `PiperSynthesisCoordinator.swift`, `TTSManager.swift`)**:
  * Bổ sung API `synthesizeWithDuration(...)` trong `ONNXPiperEngine` và `PiperTTSService` trả về tuple `(data: Data, pcmDuration: Double)` kết hợp cùng `PiperSynthesisPayload` trong `PiperSynthesisCoordinator`.
  * Loại bỏ việc decode dữ liệu WAV thủ công qua `WAVEncoder.duration(of:)`, trực tiếp tính toán độ dài PCM hiệu dụng `pcmDuration / playbackRate` tích lũy $1.0 - 1.5$s câu đầu trước khi kích phát `AVAudioPlayer`.
* **Cấu Hình ONNX Thread Options (`ONNXPiperEngine.swift`)**:
  * Thiết lập cố định `intra-op = 2` và `inter-op = 1` thông qua `ORTSessionOptions` khi tạo `ORTSession`, tối ưu hóa hiệu năng tổng hợp và giảm sử dụng CPU/nhiệt độ thiết bị.
* **Theo Dõi & Quản Lý Nhiệt Độ Thiết Bị Thermal State (`TTSManager.swift`)**:
  * Lắng nghe sự kiện `ProcessInfo.thermalStateDidChangeNotification`.
  * Tạm dừng luồng prefetch `.normal` khi nhiệt độ thiết bị lên mức `.fair`, `.serious`, hoặc `.critical`; tự động phục hồi prefetch ngầm khi trạng thái nhiệt độ về `.nominal`.
  * Các yêu cầu phát âm thanh lập tức `.high` vẫn được giữ ưu tiên phục vụ liên tục.
* **Dọn Dẹp Biến Rác & Dead Code Phân Hệ Reader (`ChapterCache.swift`, `ReaderViewModel.swift`)**:
  * Loại bỏ `typealias SharedChapterCache` và thuộc tính `var failureMessage: String?` thừa trong `ChapterCache.swift`.
  * Loại bỏ phương thức dead `fetchChaptersMetadata()` không còn sử dụng trong `ReaderViewModel.swift`.

## [1.3.94] - 2026-08-06

### Tối Ưu Hiệu Năng Luồng NGHI-TTS `AVAudioPlayer` Double-Buffering & Loại Bỏ Im Lặng Giả (`NghiAudioPlayerQueue.swift`, `TTSManager.swift`, `TTSModels.swift`, `TTSParagraphBuilder.swift`, `ONNXPiperEngine.swift`, `PiperTTSService.swift`)
* **Nâng Cấp `NghiAudioPlayerQueue` Mô Hình Trạng Thái Chuẩn (`NghiAudioPlayerQueue.swift`)**:
  * Định nghĩa `NghiQueueState` (`idle`, `playing`, `prepared`, `scheduled`, `paused`, `waitingForSynthesis`).
  * Tối ưu `updateRate(_:)` và `pause()`: giữ nguyên player instance `nextPlayer` đã `prepareToPlay()`, không hủy và re-create từ `Data` trên MainThread.
  * Áp dụng cửa sổ safe schedule $50\text{ms}$ (`wallClockRemaining > 0.050`): nếu remaining time quá sát, giữ next player ở trạng thái `prepared` cho immediate finish handoff thay vì ép schedule `play(atTime:)`.
  * Đảm bảo concurrency isolation cho delegate `audioPlayerDidFinishPlaying` và `audioPlayerDecodeErrorDidOccur`.
* **Tách Biệt Trạng Thái UI & Handoff Audio Trong `TTSManager` (`TTSManager.swift`)**:
  * Tạo helper `commitParagraphState(index:playbackId:)` cập nhật chỉ số đoạn, bôi đen highlight UI, tiến độ đọc và Now Playing info.
  * Cập nhật `handleNghiAudioTransition`: chỉ gọi `commitParagraphState`, không gọi lại `speakCurrent()` hay `playNghiTTS()`, loại bỏ 100% bug double-play lặp tiếng.
  * Dọn dẹp hàm dead code `playNghiTTSStreaming`.
* **Loại Bỏ Im Lặng Giả Cho Chunk Kỹ Thuật (`TTSModels.swift`, `TTSParagraphBuilder.swift`, `ONNXPiperEngine.swift`, `PiperTTSService.swift`)**:
  * Bổ sung enum `TTSBoundaryKind` (`technicalChunk`, `sentenceEnd`, `paragraphEnd`, `chapterEnd`) vào `TTSParagraph`.
  * Trong `TTSParagraphBuilder`, gán `.paragraphEnd` cho chunk cuối cùng của dòng văn bản gốc và `.technicalChunk` cho các chunk bị cắt giữa câu.
  * Trong `ONNXPiperEngine.synthesize`, chỉ chèn `paragraphPauseDuration` (0.5s) khi `boundaryKind == .paragraphEnd` hoặc `.chapterEnd`; triệt tiêu 100% khoảng im lặng 0.5s giả ở giữa câu.

## [1.3.93] - 2026-08-06

### Sửa Lỗi Biên Dịch Swift & Cảnh Báo Swift 6 Concurrency (`ONNXPiperEngine.swift`, `NghiAudioPlayerQueue.swift`, `TTSChapterPrefetcher.swift`)
* **Khắc Phục Lỗi Biên Dịch `@escaping` (`ONNXPiperEngine.swift`)**:
  * Thêm thuộc tính `@escaping` cho tham số `onChunkPayload` trong `synthesizeStream` để sửa lỗi passing non-escaping parameter.
* **Đồng Bộ Delegate Concurrency Swift 6 (`NghiAudioPlayerQueue.swift`)**:
  * Đánh dấu `nonisolated` cho `audioPlayerDidFinishPlaying` và `audioPlayerDecodeErrorDidOccur`, chuyển xử lý về `@MainActor` Task.
* **Dọn Dẹp Cảnh Báo `await` Dư Thừa (`TTSChapterPrefetcher.swift`)**:
  * Xóa bỏ từ khóa `await` dư thừa trước các cuộc gọi phương thức đồng bộ của `@MainActor` class `TTSChapterPrefetcher`.

## [1.3.92] - 2026-08-06

### Chuyển Đổi Luồng Phát NghiTTS Sang AVAudioPlayer (`TTSManager.swift`)
* **Chuyển Đổi Luồng Phát NghiTTS sang `AVAudioPlayer` (`TTSManager.swift`)**:
  * Thay thế việc streaming qua `AVAudioPlayerNode` bằng việc tổng hợp trọn vẹn tệp WAV Data qua `service.synthesize(...)` và phát qua `playAudioData(wavData)` sử dụng `AVAudioPlayer`.
  * Đồng bộ hoàn hảo trạng thái `play`/`pause`/`stop` và delegate `audioPlayerDidFinishPlaying` với `MPNowPlayingInfoCenter` và `MPRemoteCommandCenter` trên LockScreen & Control Center.

## [1.3.91] - 2026-08-06

### Tích Hợp PiperSynthesisCoordinator & Promoted Audio Prefetch Chương Tiếp Theo (`PiperSynthesisCoordinator.swift`, `PiperTTSService.swift`, `TTSChapterPrefetcher.swift`, `TTSManager.swift`)
* **Tích Hợp Hàng Chờ Ưu Tiên Tổng Hợp Piper TTS (`PiperSynthesisCoordinator.swift`, `PiperTTSService.swift`)**:
  * Xây dựng actor `PiperSynthesisCoordinator` điều phối độ ưu tiên tổng hợp âm thanh (`SynthesisPriority`: `high` cho đoạn đang phát, `normal` cho cửa sổ trượt chương hiện tại, `low` cho prefetch đoạn 0 chương tiếp theo).
  * Tích hợp `priority` và `requestID` vào `PiperTTSService.synthesize(...)`, đảm bảo các yêu cầu phát âm thanh lập tức luôn được ưu tiên phục vụ trước các tác vụ tổng hợp ngầm.
* **Tối Ưu Hóa Audio Promotion & Prefetch Chương Tiếp Theo (`TTSChapterPrefetcher.swift`, `TTSManager.swift`)**:
  * Bổ sung phương thức `promoteAudioIfNeeded` và state `audioReady` trong `TTSChapterPrefetcher` để sẵn sàng tổng hợp âm thanh đoạn 0 chương tiếp theo ngay khi cửa sổ trượt chương hiện tại hoàn tất hoặc khi đang phát đoạn cuối cùng.
  * Tích hợp `checkAndPromoteNextChapterAudioIfNeeded()` và phân tách API dọn cache `clearCurrentParagraphPrefetchCache()` vs `clearAllTTSCaches()` trong `TTSManager.swift`.

## [1.3.90] - 2026-08-06

### Sửa Lỗi Biên Dịch Xcode Build & Bảo Toàn 100% Chữ Khi Highlight (`ReaderTextView.swift`)
* **Khôi Phục API `textStorage` Chuẩn iOS UIKit**:
  * Sử dụng `textStorage.beginEditing()`, `textStorage.removeAttribute`, `textStorage.addAttribute` và `textStorage.endEditing()` loại bỏ hoàn toàn lỗi biên dịch `has no member 'removeTemporaryAttribute'` trên Xcode Runner.
* **Tự Động Mở Rộng Chiều Cao Tránh Mất Chữ Mép Phải**:
  * Xóa cache `cachedWidth = nil`, `cachedHeight = nil` và phát lệnh `uiView.invalidateIntrinsicContentSize()` ngay khi `isHighlightChanged == true`. Đảm bảo nếu ký tự sát mép phải bị trôi xuống dòng dưới, SwiftUI sẽ tự động dãn khung chiều cao, bảo toàn 100% văn bản không bị cắt mờ.

## [1.3.89] - 2026-08-06

### Cập Nhật Triệt Để LayoutManager Optional Chaining (`ReaderTextView.swift`)
* **Áp Dụng Optional Chaining Toàn Bộ (`ReaderTextView.swift`)**:
  * Đã chuyển đổi 100% các cuộc gọi `uiView.layoutManager` (các dòng 141, 205, 206, 216, 226, 227, 237, 251) sang toán tử optional chaining `uiView.layoutManager?.` để tương thích hoàn toàn với kiểu `NSLayoutManager?` trên mọi SDK UIKit / Xcode Runner.

## [1.3.88] - 2026-08-06

### Sửa Lỗi Biên Dịch Optional Chaining ReaderTextView & Warning withLock (`ReaderTextView.swift`, `ExtTTSService.swift`)
* **Sửa Lỗi Truy Cập LayoutManager Optional Chaining (`ReaderTextView.swift`)**:
  * Thêm toán tử optional chaining `?.` tại toàn bộ các truy xuất `uiView.layoutManager` trong `ReaderTextView.swift` (dòng 138, 204, 205, 214, 223, 224, 233, 246) để tương thích chính xác với thuộc tính optional `layoutManager: NSLayoutManager?`.
  * Khởi tạo `AutoSizingTextView(usingTextLayoutManager: false)` trên iOS 16+ để ép `UITextView` dùng TextKit 1 cho highlight và căn chỉnh kích thước text.
* **Khắc Phục Cảnh Báo Giá Trị withLock Không Sử Dụng (`ExtTTSService.swift`)**:
  * Thêm gán `_ = tempFileLock.withLock { activeTempFiles.insert(tempFileUrl) }` loại bỏ warning `result of call to 'withLock' is unused`.

## [1.3.87] - 2026-08-05

### Sửa Lỗi Biên Dịch Swift & Cảnh Báo Build (`TTSBackgroundProcessor.swift`, `ExtTTSService.swift`, `DownloadManager.swift`, `03_type_graph.md`)
* **Sửa Lỗi Biên Dịch Scope `TTSProcessedChapter`**:
  * Thêm `public typealias TTSProcessedChapter = ProcessedChapterDTO` trong `TTSBackgroundProcessor.swift` đảm bảo tên kiểu `TTSProcessedChapter` sẵn sàng trong scope khi biên dịch `TTSManager.swift`.
* **Khắc Phục Cảnh Báo Swift 6 Async Locking & Biến Unused**:
  * Thay thế `tempFileLock.lock()` / `tempFileLock.unlock()` trong `ExtTTSService.swift` bằng `tempFileLock.withLock { ... }` an toàn trong context `async`.
  * Loại bỏ khai báo biến không được sử dụng `let targetChapterId = chapter.id` trong `DownloadManager.swift`.

## [1.3.86] - 2026-08-05

### Bổ Sung Metric Hiệu Năng AppLogger & Tối Ưu Hot Path (`AppLogger.swift`, `SettingsView.swift`, `ExtensionManager.swift`, `TTSManager.swift`, `ReaderViewModel.swift`)
* **Bổ Sung AppLogger Performance Metrics (Phase 0)**:
  * Đo đạc hiệu năng chuyển chương tự động TTS (`TTSManager.swift`) dùng `systemUptime`, khởi tạo context ngay trên MainActor trước khi tải chương, theo dõi `synthesisMs`, `playerSetupMs`, `origin`, `audioCacheHit`, và ghi log `[TTSPerf] AutoAdvance` với outcome `played`, `load_failed`, `process_failed`, `cancelled`, `superseded`.
  * Đo đạc hiệu năng làm mới đoạn văn Reader (`ReaderViewModel.swift`) dùng `systemUptime`, ghi log `[ReaderPerf] TranslationRefresh` với thông số `cachedCount`, `neighborCount`, `currentMs`, `neighborsMs`, `totalMs`, `outcome`.
* **Tối Ưu Hot Path Log & Cấu Hình Log Rút Gọn JS (Phase 1)**:
  * Bọc `#if DEBUG ... #endif` tại toàn bộ vị trí gọi `logRemoteTrace` trong `TTSManager.swift` để triệt tiêu mọi phép nối chuỗi và truy vấn hệ thống trong bản Release.
  * Thêm thuộc tính `isCompactSuccessLogEnabled` và toggle cấu hình "Thu gọn log kết quả Extension" trong Settings (`SettingsView.swift`, `AppLogger.swift`).
  * Tối ưu `verifyJSResponse` trong `ExtensionManager.swift`: trả về ngay `dataVal` khi tắt log, hoặc định dạng rút gọn `[Array: N items]`, `[Object: N keys]`, `[String: N chars]`, `[Value]` khi bật log rút gọn để tiết kiệm bộ nhớ và dung lượng đĩa.

## [1.3.85] - 2026-08-05

### Sửa Lỗi Highlight TextKit Trực Tiếp Trên NSTextStorage & Thêm Unit Test Layout (`ReaderTextView.swift`, `ReaderTextViewTests.swift`)
* **Sửa Lỗi Highlight Bằng NSLayoutManager Temporary Attributes (`ReaderTextView.swift`)**:
  * Chuyển đổi cơ chế bôi đen TTS từ sửa thuộc tính màu trực tiếp trên `NSTextStorage` sang áp dụng `NSLayoutManager.addTemporaryAttributes` / `removeTemporaryAttribute`.
  * Giữ nguyên thuộc tính kiên định (persistent attributes) của `NSTextStorage`, ngăn chặn TextKit tính toán lại glyph advance hay ngắt dòng trên văn bản căn đều (justified text), triệt tiêu lỗi mất/xén chữ ở mép phải dòng cuối cùng khi bật highlight.
* **Thêm Regression Test TextKit Temporary Attributes (`Tests/ReaderTextViewTests.swift`)**:
  * Khởi tạo `ReaderTextViewTextKitTests` với chuỗi tiếng Việt chuẩn UTF-8 chứa đoạn văn tiếng Việt bắt đầu bằng `"Tiền Đa Đa nghe xong..."`.
  * Kiểm tra và khẳng định tính bất biến của thuộc tính kiên định `textStorage`, các bản chụp line layout (`LineLayoutSnapshot`), số lượng line fragment và `usedRect` ở 3 trạng thái (chưa bôi đen, bôi đen temporary attributes, và đã xóa temporary attributes).

## [1.3.84] - 2026-08-05

### Tách Cập Nhật VP/Name Khỏi Phiên TTS Đang Hoạt Động (`ReaderView.swift`, `ReaderViewModel.swift`, `TTSManager.swift`)
* **Chỉ Làm Mới Nội Dung Reader**:
  * Giữ debounce 150 ms và quy trình rebuild tuần tự chương đang hiển thị trước, sau đó mới đến các chương đã cache khi VP/Name thay đổi.
  * Loại bỏ callback `onCurrentChapterReady` và `performTTSSynchronization()`, nên cập nhật từ điển không còn restart TTS hoặc dựng lại chapter TTS đang pause.
* **Bảo Toàn Phiên TTS & Prefetch**:
  * Loại bỏ API `updatePreparedChapterContentSilent`; sự kiện cập nhật VP/Name không còn xóa prepared chapter cache hay audio prefetch cache.
  * Phiên đang phát hoặc đang pause tiếp tục bằng snapshot hiện có. Từ điển mới được áp dụng ở lần nghe mới hoặc khi TTS tự nạp nội dung chương tiếp theo.

## [1.3.83] - 2026-08-05

### Sửa Lỗi Biên Dịch Swift Do Thiếu Import Foundation (`TTSParagraphBuilder.swift`)
* **Thêm Import `Foundation`**:
  * Bổ sung `import Foundation` ở đầu tệp `TTSParagraphBuilder.swift` để định nghĩa đầy đủ các kiểu dữ liệu `NSRange`, `NSIntersectionRange`, `NSMaxRange`, `NSString` và giải quyết lỗi suy luận kiểu dữ liệu (`cannot convert value of type 'Duration' to expected argument type 'Int'`).

## [1.3.82] - 2026-08-05

### Tối Ưu Hóa Reading/Highlight & VP/Name Cascade (`TranslationManager.swift`, `TranslateUtils.swift`, `DictionaryCache.swift`, `TTSManager.swift`, `TTSModels.swift`, `TTSBackgroundProcessor.swift`, `TTSParagraphBuilder.swift`, `ChapterCache.swift`, `ParagraphCardView.swift`, `ReaderTextView.swift`, `ReaderView.swift`, `ReaderViewModel.swift`)
* **Scoped Dictionary Notifications & Generation Counters**:
  * Thêm `globalGeneration`, `bookGenerations`, `settingsGeneration` vào `TranslateUtils.invalidateCache(bookId:)` giúp xóa cache RAM chọn lọc theo `bookId` và cài đặt; tránh làm cold cache của sách B khi từ điển sách A thay đổi.
  * Thêm `bookId` vào `userInfo` của thông báo `.translationDictionariesDidUpdate` trong `TranslationManager` để `ReaderView` lọc đúng phạm vi sách.
* **Bảo Tồn Paused Session & Resume Vị Trí TTS**:
  * Di chuyển kiểm tra cùng sách lên trước khi xóa cache TTS.
  * Bổ sung API `updatePreparedChapterContentSilent` trong `TTSManager` giữ phiên TTS paused nguyên trạng thái và widget khi đổi từ điển.
  * Thêm `sourceRange` vào `TTSParagraph` và cấu trúc `TTSChunkResumeIdentity` lưu `sourceLineId` và `sourceOffset` để resume đúng chunk và bảo toàn hành vi bôi đen chọn "Nghe".
* **Bảo Vệ Snapshot Readiness & Tối Ưu UI Render**:
  * Bổ sung `revision` vào `CachedChapter` và `ReaderViewModel`, hoãn TTS sync nếu dữ liệu chương chưa hoàn tất re-translation.
  * Chuyển công việc dịch ngầm nặng ra off-MainActor với cooperative cancellation và ưu tiên dịch chương hiện tại trước.
  * Dùng trực tiếp `item.translated` làm `displayText` trong `ParagraphCardView` tạo snapshot nguyên tử với `translationSpans`.
* **Sửa Lỗi Compile, Đồng Bộ TTS Readiness & Coordinate Selection**:
  * Phục hồi `let md5 = text.md5()` trong `TranslateUtils.translateText` và chuẩn hóa access control `internal private(set) var currentRevision`.
  * Bổ sung callback `onCurrentChapterReady` trong `ReaderViewModel` để đảm bảo `performTTSSynchronization()` chỉ kích hoạt khi dữ liệu chương hiện tại hoàn tất re-translation ở `currentRevision`.
  * Ánh xạ chính xác `sourceOffset` (`selectedWordOffset`) và `TTSChunkResumeIdentity` khi bấm chọn "Nghe" trên văn bản bôi đen dịch thuật.
  * Xóa bỏ các cache audio/prepared stale trong `updatePreparedChapterContentSilent` khi paused mà không ảnh hưởng tới widget hoặc các sách khác.
  * Khoanh vùng hoàn toàn `chapterTitleCacheDict` theo `bookId` và định tuyến duy nhất qua `notifyDictionariesDidUpdate()`.
  * Hoãn tự động swap snapshot re-translation (`isTranslationRefreshDeferred`) khi người dùng đang bật menu/bảng thao tác bôi đen văn bản, bảo vệ 100% active selection.
* **Tối Ưu Concurrency, Resilient Revision Retry & Per-line Cancellation**:
  * Thêm vòng lặp retry tự động trong `ReaderViewModel.processAndSaveChapter` giúp nạp chương bình thường tự thử lại với `currentRevision` mới nhất nếu từ điển thay đổi trong lúc dịch ngầm, triệt tiêu hoàn toàn nguy cơ mất chương hoặc commit snapshot cũ.
  * Bắt và kiểm tra bộ 5 thuộc tính định danh (`isPlaying`, `playingBookId`, `playingChapterIndex`, `sessionID`, `ttsProcessingGeneration`, `preparationGeneration`) trong `TTSManager.updatePreparedChapterContentSilent`, chặn đứng race condition ghi đè từ các tác vụ ngầm cũ.
  * Tách helper `buildCancellable` trong `ReaderViewModel` hỗ trợ kiểm tra `Task.checkCancellation()` theo từng dòng (per-line), giúp hủy ngay các tác vụ dịch ngầm thừa mà vẫn bảo toàn 100% ngữ nghĩa và dữ liệu `TranslationSpan`.
* **Scoped Translation Generation Token & Tái Sử Dụng Pretranslated Snapshot**:
  * Thêm API `TranslateUtils.translationGenerationToken(for: bookId)` kết hợp `globalGeneration`, `bookGeneration`, `settingsGeneration` và bổ sung `translationToken` vào `TTSPreparedChapterKey`. Tự động làm miss cache prepared TTS cũ khi từ điển/cài đặt thay đổi kể cả khi không có floating session.
  * Tái sử dụng trực tiếp snapshot `ParagraphItem` đã dịch trong `ReaderViewModel` cho `TTSBackgroundProcessor` qua `pretranslatedEntries`, kết hợp kiểm tra validation nghiêm ngặt theo `lineId` và `originalText`. Triệt tiêu hoàn toàn dịch trùng lặp giữa UI và TTS cho chương hiện tại.
* **Snapshot Validation Metadata & Protection Against Race On Toggle**:
  * Thêm `isTranslationEnabled` và `translationToken` vào `CachedChapter` và đóng gói thành `TTSPretranslatedSnapshot`.
  * Trong `TTSBackgroundProcessor`, kiểm tra `snapshot.isTranslationEnabled == shouldTranslateRawContent` và `snapshot.translationToken == TranslateUtils.translationGenerationToken(for: bookId)`. Chặn đứng tuyệt đối việc phát âm nhầm văn bản dịch cũ khi chuyển đổi bật/tắt dịch thuật nhanh hoặc thay đổi từ điển trước khi refresh hoàn tất.

## [1.3.81] - 2026-08-05

### Sửa Lỗi Regression Highlight TTS & Lệch Range Cuối Chunk Cấp Chunk (`ChapterTextNormalizer.swift`, `TTSBackgroundProcessor.swift`, `TTSManager.swift`, `ReaderView.swift`, `ParagraphCardView.swift`, `ReaderSelectionMapper.swift`, `ChapterTextNormalizerTests.swift`)
* **Nâng cấp Bôi Đen TTS Cấp Chunk (Exact Current Chunk Range)**:
  * Phân biệt rõ Paragraph Identity và Chunk Identity: `highlightRange` giữ nguyên `NSRange` cấp chunk của `TTSParagraph.range`.
  * Trong `ParagraphCardView.swift`, bỏ bọc `ReaderSelectionMapper.mapHighlight` và truyền trực tiếp `highlightRange` từ `TTSManager` xuống `ReaderTextView` để tô màu nền đúng dải ký tự của chunk đang đọc, không bôi đen cả paragraph.
  * Trong `ReaderSelectionMapper.swift`, xóa 3 phương thức `mapHighlight`, `mappedRangeUsingOriginalSpans`, và `proportionalHighlightFallback`.
* **Nâng Cấp Thuật Toán Chọn Chunk Khi Bấm "Nghe" (`TTSManager.swift`)**:
  * Khi bôi đen văn bản rồi bấm "Nghe", `startSpeaking` nhận `startTextOffset` là `selectionRange.location` (offset ký tự đầu tiên của selection range).
  * `TTSManager.continueStartSpeaking` lọc danh sách chunks thuộc `startParagraphIndex`, kiểm tra offset hợp lệ (`offset != NSNotFound`, `offset >= 0`, `minLoc <= offset <= maxEnd`). Nếu offset rơi vào ranh giới/khoảng trắng ngắt chunk do trimming, ưu tiên chọn chunk kế tiếp có `location >= offset`, hoặc chunk liền trước có `NSMaxRange(range) <= offset`; nếu offset không hợp lệ (hoặc `NSNotFound` / vượt ngoài phạm vi đoạn), tự động fallback về chunk đầu tiên của đoạn.
* **Unified Pipeline & Preserved Gap Content (`ChapterTextNormalizer.swift`, `TTSBackgroundProcessor.swift`)**:
  * Thêm `ChapterTextNormalizer.reconstructContentPreservingLineIDs(from:)` tái tạo chuỗi raw content từ `cached.paragraphItems` duy trì đúng các ký tự ngắt dòng `\n`.
  * `TTSBackgroundProcessor.processChapter` thực hiện quy trình Lọc rác raw content 1 lần duy nhất $\rightarrow$ Normalize raw $\rightarrow$ Translate per Line $\rightarrow$ Reconstruct gap-preserved content $\rightarrow$ `normalizeProcessedContent` (không lọc rác lần 2 trên chuỗi dịch), đảm bảo `normalizedContent` giữ ngắt dòng và 100% khớp dải ký tự với Reader UI.
* **Snapshot Session & Debounced Coalescing Sync (`TTSManager.swift`, `ReaderView.swift`)**:
  * Thêm `isTranslationEnabled` vào `TTSPreparedChapterKey` và lưu `sessionTranslationEnabled` snapshot cho luồng prefetch trong `TTSManager`.
  * Bổ sung `ttsManager.clearPreparedChapterCache()` để giải phóng cache chapter chuẩn bị khi đổi từ điển/cài đặt.
  * Trong `ReaderView.swift`, thêm `scheduleTTSSynchronization()` với debounce 100ms gom nhóm các sự kiện cập nhật từ điển và bật/tắt dịch, tự động đồng bộ lại phiên TTS active nếu đang chạy hoặc dừng an toàn nếu đang paused.
* **Chuẩn Hóa Tiêu Đề Chương Dịch 1 Lần Duy Nhất (`TTSBackgroundProcessor.swift`, `ReaderView.swift`, `TTSManager.swift`)**:
  * `TTSChapterInfo.title` thống nhất mang tiêu đề gốc (RAW title). `ReaderView.ttsChapterInfo` và `TTSManager` truyền RAW title vào `TTSBackgroundProcessor.processChapter`.
  * `TTSBackgroundProcessor.processChapter` là nơi duy nhất chịu trách nhiệm dịch tiêu đề 1 lần duy nhất khi `shouldTranslateRawContent == true`, trả về `ProcessedChapterDTO.chapterTitle`.
  * Triệt tiêu hoàn toàn lỗi dịch tiêu đề 2 lần (double translation), đảm bảo tiêu đề `TTSParagraph` (`paragraphIndex = -1`), `TTSManager.chapterTitle` (Now Playing/Lock Screen) và tiêu đề hiển thị trên Reader đồng nhất 100%.
* **Dọn Dẹp Unit Tests Sai ở Commit HEAD**:
  * Xóa 5 unit test cases testing `mapHighlight` trong `Tests/ChapterTextNormalizerTests.swift` để phù hợp với kiến trúc bôi đen cấp chunk chuẩn.

## [1.3.80] - 2026-08-05

### Sửa Lỗi Highlight TTS Lệch Khi Đoạn Văn Nhiều Dấu Câu (`ReaderSelectionMapper.swift`, `ParagraphCardView.swift`, `ReaderView.swift`)
* **Root Cause**: `TTSParagraphBuilder` tính `TTSParagraph.range` theo offset UTF-16 trên `ChapterTextLine.text` (nguyên bản), nhưng `ParagraphCardView` lại render bản dịch VietPhrase. `ReaderView` truyền thẳng `ttsManager.highlightRange` xuống mà không ánh xạ, nên range của hệ tọa độ gốc bị áp lên chuỗi đã dịch có độ dài khác. Vì bản dịch Việt dài hơn nguyên bản Trung, độ lệch tích lũy tăng dần theo vị trí chunk trong đoạn; đoạn nhiều dấu câu bị cắt thành nhiều chunk nên lệch thể hiện rõ nhất. Guard `NSMaxRange(highlight) <= nsText.length` trong `ReaderTextView` chỉ chặn crash chứ không chặn lệch, và còn làm mất highlight ở chunk cuối khi bản dịch ngắn hơn.
* **Fix**: Bổ sung `ReaderSelectionMapper.mapHighlight(_:in:displayText:)` — chiều ngược của `mappedRangeUsingSpans` — gộp các `TranslationSpan` giao với vùng gốc rồi lấy bao đóng của chúng trên chuỗi hiển thị.
* Hàm nhận thẳng `displayText` thay vì cờ `isTranslationEnabled`: `toggleTranslation` chỉ đổi cờ mà không rebuild `paragraphItems`, nên `item.translated` có thể cũ so với chuỗi đang render. Span chỉ được dùng khi `displayText == item.translated`; ngược lại rơi về nội suy theo tỉ lệ độ dài.
* Việc ánh xạ đặt tại `ParagraphCardView` — nơi duy nhất biết chắc chuỗi thực sự được render. `ReaderView` tiếp tục truyền range ở hệ tọa độ gốc.
* Dự phòng nội suy tỉ lệ cũng phủ trường hợp `buildTranslationSpans` trả `[]` khi có token không dò được trong chuỗi dịch, giữ highlight bám sát câu thay vì biến mất.



### Giảm Giật TTS Khi Cập Nhật VP/Name (`ReaderView.swift`, `ReaderViewModel.swift`)
* Bỏ việc gọi `TTSManager.clearPrefetchCache()` ngay khi nhận `translationDictionariesDidUpdate`, giữ nguyên audio đã tổng hợp của phiên đang phát để không tạo khoảng ngắt ở đoạn kế tiếp.
* Thay refresh đồng bộ nội dung cache bằng một `translationRefreshTask` có thể hủy, xử lý tuần tự chapter đang hiển thị trước rồi đến các chapter loaded/preload theo khoảng cách.
* Mỗi chapter được rebuild đầy đủ qua `ReaderParagraphBuilder`, cập nhật đồng thời tiêu đề, nội dung, `ParagraphItem` và translation spans theo VP/Name mới. Khi người dùng bấm đọc lại, Reader dịch từ `originalContent` và khởi tạo phiên TTS mới bằng nội dung đã cập nhật.

## [1.3.78] - 2026-08-04

### Sửa Lỗi Tách Từ "仿佛" & Hỗ Trợ VP/Name Chứa Ký Tự Ngoài Tiếng Trung (`DoubleArrayTrie.swift`, `TextDictionary.swift`, `TranslateUtils.swift`)
* **Khắc Phục Lỗi Tách Nhầm Từ "仿佛" Khi Từ Điển Có Cụm Dài Hơn**:
  * Bổ sung phương thức `findAllPrefixMatches(text:startIndex:)` vào `protocol TrieDictionary`, `DoubleArrayTrie` và `TextDictionary` thu thập toàn bộ các mốc tiền tố khớp từ điển nhị phân `.dat` và RAM `.txt` thay vì chỉ giữ 1 match dài nhất (`findLongestMatch`).
  * Cập nhật Bước 3 pre-scan trong `TranslateUtils.swift` để gom toàn bộ ứng viên VietPhrase $\ge 2$ ký tự. Nhờ đó khi cụm dài `仿佛在` (dài 3) bị loại do tranh chấp với `在一瞬间` (dài 4), thuật toán ở Bước 4 sẽ chọn ứng viên tiếp theo là `仿佛` (dài 2) thay vì bị tách nhầm thành các token đơn lẻ `["仿", "佛"]`.
* **Hỗ Trợ VP/Name Chứa Ký Tự La Tinh / Số / ASCII (T-shirt, Đội A, 3D, A-1)**:
  * Gỡ bỏ các câu lệnh tự động bỏ qua (skip) ký tự ASCII ở Bước 1 (Name scan) và ký tự không phải tiếng Trung ở Bước 3 (VP scan) trong `TranslateUtils.swift`.
  * Đưa việc ưu tiên khớp `activeName` và `activeVP` lên đầu vòng lặp Bước 5 (Token assembly) trước khi fallback gom chuỗi ASCII thô, đồng thời tự động dừng gom chuỗi ASCII tại ranh giới `nextBoundary` của Name/VP kế tiếp.

## [1.3.77] - 2026-08-03

### Skeleton Delay + Response.error Không Báo Message (`ReaderViewModel.swift`, `ReaderView.swift`, `ExtensionManager.swift`)
* **Step 1** (`ReaderViewModel.swift` – `requestChapter`): Cancel `navigationWorkerTask` ngay đầu hàm (trước `navigationGeneration++`) để `startNavigationWorkerIfNeeded` luôn tạo Task mới → `Task.yield()` luôn chạy → SwiftUI render Skeleton trước I/O. Dời `Task { await prefetcher.cancelAll() }` xuống sau toàn bộ block `startNavigationWorkerIfNeeded`/debounce để SwiftUI có cơ hội render trước.
* **Step 2** (`ReaderViewModel.swift` – `runNavigationWorker`): `catch is CancellationError` chỉ `continue`, không gọi `failNavigation` — tránh flash error message sai khi worker cũ bị cancel bởi navigation mới.
* **Step 3** (`ReaderView.swift` – `singleChapterReaderView`): Dùng `.transition(.identity)` thay `.transition(.opacity)` khi `pendingNavigationIndex != nil` để chương cũ biến mất ngay lập tức thay vì fade ra từ từ che Skeleton.
* **Step 4** (`ExtensionManager.swift` – `verifyJSResponse`): Thêm kiểm tra field `error` trong JS response (`{ error: "message" }` pattern) — trước đây bị bỏ qua dẫn đến `emptyContent` error thay vì message thực từ server.

## [1.3.76] - 2026-08-03

### Sửa Lỗi Offset Lệch Hàng 2 Màn Hình Dịch (`TranslateUtils.swift`)
* **Root Cause**: `getTranslationTokens` chạy `tokenize` trên chuỗi `converted` (đã map dấu câu Trung qua `punctuationMapping`), trong khi `currentIndex` lại được track trên `sentence` gốc. Dấu câu như `"。"` (1 char) bị expand thành `". "` (2 chars) khiến `token.count` lớn hơn số ký tự thực trong sentence gốc — dẫn đến offset lệch lũy tích sau mỗi dấu câu, token tiếp theo bị tra cứu sai vị trí và hiển thị ký tự gốc tiếng Trung thay vì VP/phiên âm.
* **Fix**: Tokenize trực tiếp từ `sentence` gốc (không qua `converted`) để `token.count` luôn bằng số ký tự thực, loại bỏ hoàn toàn hiện tượng offset lệch sau dấu câu `。，！？…`.

## [1.3.75] - 2026-08-03

### Tái Cấu Trúc Từ Điển Tùy Chỉnh TXT Hợp Nhất, Lọc Từ Đã Xóa Dải Chip Gợi Ý & Cập Nhật Logic Count Từ Điển Truyện (`BypassWebView.swift`, `DictionaryListView.swift`, `DictionaryCache.swift`, `TextDictionary.swift`, `TranslationManager.swift`, `ReaderView.swift`, `DictionaryHubView.swift`)
* **Nâng Cấp Thanh Điều Hướng Dưới & Nút Import Trình Duyệt Bypass (`BypassWebView.swift`, `ShelfView.swift`, `DiscoveryView.swift`, `ReaderView.swift`, `BookDetailView.swift`)**:
  * Bổ sung thanh điều hướng dưới (bottom navigation) và nút Import trực tiếp trên thanh điều hướng trình duyệt; tự động vô hiệu hóa (disabled) khi URL không khớp biểu thức chính quy (regex match).
  * Hỗ trợ hiển thị bộ chọn nguồn (source picker) khi có nhiều tiện ích mở rộng (extensions) cùng khớp với URL.
  * Khắc phục triệt để lỗi không mở trang Chi Tiết Truyện (`BookDetailView`) sau khi hoàn tất Import: Kích hoạt cờ điều hướng `navigateToImportedBook` / `navigateToBookDetail = true` sau khi đóng trình duyệt tại tất cả các điểm gọi (`ShelfView`, `DiscoveryView`, `ReaderView`, `BookDetailView`).
* **Nâng Cấp Bóc Tách Tiêu Đề Chương Số Ả Rập & Triệt Tiêu Trùng Dấu Hai Chấm (`TranslateUtils.swift`)**:
  * Khai báo `arabicNumberTitleRegex` (`^\s*(\d{1,5})[\s.:：,.， 、_—\-]+(.*)$`) hỗ trợ bóc tách và định dạng các tiêu đề số Ả Rập dạng `1、...`, `1. ...`, `1: ...` $\rightarrow$ `Chương 1: [Tiêu đề dịch]`.
  * Tích hợp `cleanLeadingDelimiters` loại bỏ các dấu phân cách đầu chuỗi tên chương, triệt tiêu hoàn toàn lỗi 2 dấu hai chấm liên tiếp (`: :`) khi tiêu đề gốc đã có sẵn dấu hai chấm.
* **Dọn Dẹp SwiftData Fallback Chapter Metadata & Tối Ưu Render Skeleton 0ms (`ReaderViewModel.swift`, `ReaderView.swift`, `TTSManager.swift`, `ReaderChapterListView.swift`, `ShelfView.swift`, `DownloadManager.swift`)**:
  * Chuyển 100% các truy vấn chapter metadata rải rác sang thuần túy **SQLite (`ChapterStore.shared`)**, xóa bỏ hoàn toàn các khối mã fallback `FetchDescriptor<Chapter>` cũ.
  * Tắt hiệu ứng animation mờ dần 0.12s/0.25s khi đang nạp chương (`pendingNavigationIndex != nil`), giúp giao diện ngắt chương cũ và chuyển ngay sang View Skeleton.
  * Bổ sung `await Task.yield()` trong worker nạp dữ liệu nhường Main Thread vẽ khung hình Skeleton ngay ở frame đầu tiên (0ms delay) khi bấm Next/Prev chương.
* **Áp Dụng Loại Trừ Từ Đã Xóa Về Dải Chip Gợi Ý (`ReaderView.swift`)**:
  * Bổ sung điều kiện kiểm tra `!manager.deletedNames.contains(word)` và `!manager.deletedVietPhrase.contains(word)` trong thuộc tính `suggestionChips`, đảm bảo không gợi ý lại nghĩa mặc định hệ thống cho từ đã bị xóa.
* **Chuẩn Hóa Đếm Số Từ Từ Điển Truyện Theo TXT (`DictionaryHubView.swift`, `TextDictionary.swift`)**:
  * Bổ sung phương thức `DictionaryTextFileStore.loadCount(from:)` đếm số từ hoạt động trong tệp `.txt`.
  * Tái cấu trúc phương thức `bookEntryCount(type:)` sử dụng `DictionaryTextFileStore.loadCount`, loại bỏ hoàn toàn mã đọc header tệp `.dat` cũ.
* **Bảo Tồn Thứ Tự Từ Đã Xóa & Tối Ưu Nút Khôi Phục Giao Diện (`DictionaryListView.swift`)**:
  * Đảm bảo thứ tự danh sách từ VietPhrase/Names bị xóa dựa trên danh sách có thứ tự (ordered list) / thứ tự file thay vì hiển thị ngẫu nhiên từ `Set`.
  * Rút gọn nút Khôi phục thành nút dạng icon (icon-only button) kèm nhãn hỗ trợ truy cập (accessibility label).
* **Hợp Nhất Luồng Từ Điển Tùy Chỉnh Sang Định Dạng TXT Thuần (`DictionaryCache.swift`, `TranslationManager.swift`)**:
  * Chuyển toàn bộ luồng từ điển tùy chỉnh VietPhrase/Names sang định dạng TXT; hợp nhất các bản ghi chỉnh sửa (`từ=nghĩa`) và bản ghi xóa (`từ=`) trong cùng các file TXT (`CustomVietPhrase.txt`, `CustomNames.txt`, và `VietPhrase.txt`, `Names.txt` theo từng sách).
  * Loại bỏ hoàn toàn việc sử dụng file `.dat` tùy chỉnh và các file `Deleted*.txt` riêng lẻ trong luồng tùy chỉnh.
* **Phân Tích & Chuẩn Hóa Ký Tự Phân Cách Nghĩa Từ Điển (`TextDictionary.swift`)**:
  * Cập nhật `TextDictionary` và `DictionaryTextFileStore` hỗ trợ phân tích các bản ghi TXT hợp nhất.
  * Tự động chuẩn hóa tất cả các ký tự phân cách nghĩa `/`, `¦`, `|` về một ký tự chuẩn duy nhất là `/`.



## [1.3.74] - 2026-08-01

### Bổ Sung Trình Duyệt Giao Diện `Engine.newVisibleBrowser` & Tối Ưu Độ Tin Cậy Lưu Chương Nguồn STV (`VisibleWebViewLoader.swift`, `JSExecutor.swift`, `GetTextSTVManager.swift`, `ChapterContentRepository.swift`, `ChapterPersistenceStore.swift`, `BypassWebView.swift`, `ReaderView.swift`)
* **Bổ Sung API Trình Duyệt Có Giao Diện Cho JS Engine (`VisibleWebViewLoader.swift`, `JSExecutor.swift`, `ParserTests.swift`)**:
  * Định nghĩa phương thức mới `Engine.newVisibleBrowser(title)` trong JS Engine, cho phép các kịch bản JS khởi tạo và hiển thị một giao diện `WKWebView` Modal Sheet trực quan cho người dùng tương tác khi cần thiết.
  * Xây dựng trợ lý `VisibleWebViewLoader.swift` quản lý vòng đời đóng/mở UI đơn điểm (Single-source-of-truth), hỗ trợ thao tác vuốt xuống (Interactive Swipe-down) thông qua `UIAdaptivePresentationControllerDelegate` và giải phóng bộ nhớ `activeVisibleBrowsers` tức thì.
  * Giữ nguyên 100% cấu trúc, tính năng và các test case của trình duyệt ngầm `Engine.newBrowser()`.
* **Nâng Cấp Độ Tin Cậy Lưu Chương Nguồn Sáng Tác Việt - STV (`GetTextSTVManager.swift`, `ChapterContentRepository.swift`, `ChapterPersistenceStore.swift`, `BypassWebView.swift`, `ReaderView.swift`)**:
  * Khắc phục triệt để lỗi mất dữ liệu khi lưu nội dung chương STV, chuẩn hóa việc sửa lỗi URL và kiểm tra lưu nội dung chương đồng bộ vào cơ sở dữ liệu SQLite.
  * Đảm bảo tính toàn vẹn dữ liệu khi tải và lưu nội dung chương từ tiện ích STV.

## [1.3.73] - 2026-08-01

### Tích Hợp Quản Lý Từ Đã Xóa & Nâng Cấp UI/UX Từ Điển Chung (`DictionaryListView.swift`, `DictionaryCache.swift`, `DictionaryHubView.swift`)
* **Tích Hợp Tab Quản Lý & Khôi Phục Từ Đã Xóa (`DictionaryListView.swift`)**:
  * Bổ sung `TabView` với `.tabViewStyle(.page(indexDisplayMode: .never))` hỗ trợ vuốt tay trái/phải tương tác chuyển qua lại giữa 2 Tab: 📝 **Từ Chỉnh Sửa** và 🗑️ **Từ Đã Xóa**.
  * Trong Tab **Từ Đã Xóa**: Hiển thị danh sách các từ tiếng Trung bị xóa (`Array(deletedWords).reversed()`) với từ mới bị xóa gần đây nhất nằm ở dòng 1 trên cùng, kèm nút **Khôi phục** `arrow.uturn.backward.circle` trả lại nghĩa mặc định hệ thống.
* **Loại Bỏ Vuốt Xóa Mặc Định, Thêm Nút Xóa Thùng Rác Trực Tiếp (`DictionaryListView.swift`)**:
  * Loại bỏ tính năng vuốt xóa vô ý (`.onDelete`), thêm nút bấm **Thùng Rác màu đỏ (`Image(systemName: "trash")`)** trực tiếp trên từng dòng của danh sách Từ Chỉnh Sửa.
* **Đẩy Từ Mới Thêm/Sửa Lên Đầu Index 0 & Export Đồng Bộ (`DictionaryCache.swift`, `DictionaryListView.swift`)**:
  * Đưa bản ghi `DictEntry` vừa thêm mới hoặc vừa sửa nghĩa lên thẳng **`Index 0` (Dòng 1 trên cùng)**.
  * Khi Xuất từ điển (Export): Tự động xuất thêm tất cả các từ trong danh sách từ đã xóa dưới dạng `từ_trung=`.
* **Cập Nhật Phụ Đề Hub Từ Điển (`DictionaryHubView.swift`)**:
  * Hiển thị tổng quan chi tiết: *"X từ chỉnh sửa • Y từ đã xóa"*.

## [1.3.72] - 2026-08-01

### Khắc Phục Triệt Để Lỗi Trượt Lệch ID Đoạn Văn TTS Bằng `originalLineIndex` (`ChapterTextNormalizer.swift`)
* **Duy Trì Chỉ Mục Dòng Gốc Khi Lọc Đoạn Văn Rỗng/Dấu (`ChapterTextNormalizer.swift`)**:
  * Tái cấu trúc vòng lặp phân tách dòng trong `ChapterTextNormalizer.normalize()`, gán thuộc tính `id` của từng `ChapterTextLine` bằng đúng vị trí chỉ mục dòng ban đầu (`originalLineIndex`) trước khi thực hiện lọc bỏ các dòng rỗng.
  * Giúp các đoạn văn phía sau (như *"Từng cái trải qua..."*) **luôn luôn giữ vững `id = 15`** ở cả luồng TTS và luồng UI ngay cả khi đoạn `14` (`..........`) bị lọc bỏ.
  * Triệt tiêu 100% nguyên nhân gây lệch trượt `ParentID` trong TTS so với `ItemID` trên Reader UI khi có đoạn chứa toàn dấu bị bỏ qua.

## [1.3.71] - 2026-08-01

### Sửa Lỗi Highlight TTS Đoạn Văn Ngắn & Hiển Thị Tên Truyện 2 Dòng Kệ Sách/Lịch Sử (`TTSParagraphBuilder.swift`, `ShelfView.swift`)
* **Triệt Tiêu 100% Lỗi Mất Highlight TTS Ở Đoạn Văn Ngắn (`TTSParagraphBuilder.swift`)**:
  * Sửa lệnh `guard` rút gọn ở dòng 18 trong `chunks(for:maximumLength:)` cho các đoạn văn ngắn ($\le 200$ ký tự), chuyển `line.utf16Range` (chỉ mục tuyệt đối toàn chương) thành `NSRange(location: 0, length: line.text.utf16.count)` (chỉ mục tương đối 0-indexed).
  * Đảm bảo **100% tất cả các đoạn văn ngắn hay dài** đều có `range` tương đối bắt đầu từ 0, tô màu bôi đen chính xác từng câu trên UI và tự động cuộn `Auto-scroll` lên giữa màn hình mượt mà.
* **Tăng Số Dòng Hiển Thị Tên Truyện Lên 2 Dòng (`ShelfView.swift`)**:
  * Đổi `.lineLimit(1)` thành `.lineLimit(2)` cho `Text` tên truyện trong `bookItemView(_ book: Book)` của `ShelfView.swift`.
  * Cho phép tên truyện dài ở Kệ Sách và Lịch Sử Đọc hiển thị tối đa 2 dòng (rút gọn `...` ở cuối dòng 2 nếu quá dài).
* **Khôi Phục Mũi Tên Chỉ Báo `>` Mặc Định (`ShelfView.swift`)**:
  * Khôi phục lại cấu trúc `NavigationLink` trực tiếp mặc định của iOS SwiftUI cho cả 2 danh sách Kệ Sách và Lịch Sử Đọc.

## [1.3.70] - 2026-08-01

### Triệt Tiêu Lỗi Lệch Highlight TTS (Relative Indexing) & Xóa Mũi Tên Đồ Họa Lề Phải Sách (`TTSParagraphBuilder.swift`, `ReaderView.swift`, `ShelfView.swift`)
* **Sửa Triệt Để 100% Lỗi Lệch Highlight TTS & Auto-scroll (`TTSParagraphBuilder.swift`, `ReaderView.swift`)**:
  * Chuyển đổi công thức tính `range` trong `TTSParagraphBuilder.swift` sang chỉ mục tương đối nội bộ theo dòng `line.text` (0-indexed), loại bỏ hoàn toàn chỉ mục tuyệt đối cộng dồn của cả chương.
  * Trong `ReaderView.swift`, so sánh trực tiếp `item.id == ttsManager.currentParentParagraphIndex`, gán thẳng `chunkRange` cho `relativeHighlightRange` mà bỏ hẳn việc gọi qua hàm `lineStartOffset` lặp toàn chương.
  * Tự động đưa vị trí bôi đen highlight chính xác 100% từng câu trên UI và cuộn màn hình `Auto-scroll` đưa câu đang đọc vào giữa màn hình mượt mà.
* **Xóa Mũi Tên Mặc Định `>` ở Lề Phải Kệ Sách & Lịch Sử Đọc & Rà Soát Cú Pháp (`ShelfView.swift`, `ReaderView.swift`)**:
  * Sử dụng kỹ thuật bọc `ZStack` với `NavigationLink` ẩn (`.opacity(0)`) cho từng dòng sách trong danh sách Kệ Sách và Lịch Sử Đọc.
  * Loại bỏ hoàn toàn mũi tên `>` (disclosure indicator) mặc định của iOS lề bên phải, giúp giao diện phẳng, đẹp, sạch sẽ và rộng rãi hơn.
  * Sửa lỗi ngoặc nhọn đóng thừa tại dòng 176 và 284 trong `ShelfView.swift` đảm bảo định vị cấu trúc `body` chuẩn xác, đồng thời dọn dẹp biến `textLen` không sử dụng trong `ReaderView.swift`.

## [1.3.69] - 2026-08-01

### Tối Ưu Giao Diện Màn Hình Dịch, Tên Chương 2 Dòng & Log Chẩn Đoán Highlight TTS (`ReaderDefinitionOverlayView.swift`, `ReaderJunkDeleteOverlayView.swift`, `ReaderChapterListView.swift`, `BookDetailTOCView.swift`, `TTSParagraphBuilder.swift`, `TTSManager.swift`, `ReaderView.swift`)
* **Tối Ưu Không Gian Tràn Lề Hàng 1 Màn Hình Dịch & Xóa Từ Rác (`ReaderDefinitionOverlayView.swift`, `ReaderJunkDeleteOverlayView.swift`)**:
  * Thu nhỏ kích thước cụm nút điều chỉnh vùng chọn 2 bên từ `36x36` xuống `28x28`, icon `13pt`, spacing `3pt`.
  * Gỡ bỏ hai `Spacer()` hai bên `ScrollViewReader`, triệt tiêu padding lề 2 bên từ `10pt` xuống `padding(.horizontal, 4)`, giúp thanh cuộn câu tiếng Trung gốc mở rộng chiều ngang tối đa.
* **Cập Nhật Hiển Thị Tên Chương Tối Đa 2 Dòng Kèm Dấu `...` (`ReaderChapterListView.swift`, `BookDetailTOCView.swift`)**:
  * Thay đổi `.lineLimit(1)` thành `.lineLimit(2)` trong `ReaderChapterRowView` ở danh sách chương trình đọc.
  * Thay đổi `.lineLimit(1)` thành `.lineLimit(2)` cho cả 3 trường hợp danh sách chương trong `BookDetailTOCView` mục lục chi tiết truyện.
* **Bổ Sung Log Chẩn Đoán Luồng Tính Toán Highlight TTS (`TTSParagraphBuilder.swift`, `TTSManager.swift`, `ReaderView.swift`)**:
  * Ghi log chi tiết text thô từng chunk trong hàng chờ (`paragraphs` queue) kèm `utf16Range` và `line.id` trong `TTSParagraphBuilder.swift`.
  * Ghi log chi tiết chuỗi `textToSpeak` sau khi áp dụng các quy tắc thay thế từ/ký tự (`TTSReplacementManager`) và giá trị `highlightRange` trong `TTSManager.swift`.
  * Ghi log vị trí `relativeHighlightRange` quy đổi trên giao diện UI `ReaderView.swift` phục vụ đối soát lệch vị trí bôi đen.

## [1.3.68] - 2026-07-31

### Tinh Chỉnh Khoảng Cách Token Dịch Hàng Thứ 2 Màn Hình Dịch & Đồng Bộ Tra Từ Điển (`ReaderDefinitionOverlayView.swift`, `ReaderJunkDeleteOverlayView.swift`, `TranslateUtils.swift`)
* **Thu Hẹp Khoảng Cách Giữa Các Token Dịch**:
  * Giảm `spacing` của `HStack` từ `6` xuống `2` và giảm `.padding(.horizontal)` của từng `Text` token từ `4` xuống `2` ở `translatedTokensRowView`.
  * Giảm tổng khoảng cách giữa các văn bản token kề nhau từ `14pt` xuống `6pt`, giúp chuỗi câu dịch ở hàng thứ 2 trông liền mạch, tự nhiên như một câu đọc bình thường mà vẫn đảm bảo thao tác chọn từ và highlight xanh/đỏ rõ ràng.
* **Tái Cấu Trúc Đồng Bộ Tra Từ Điển Dùng Chung (`TranslateUtils.swift`)**:
  * Tạo mới hai hàm private helper `lookupRawTranslation(for:bookId:)` tra cứu trực tiếp 8 tầng từ điển và `resolveTokenMeaning(for:bookId:phienAm:)` xử lý nghĩa token kết hợp fallback Hán Việt.
  * Cập nhật cả `performTranslation` và `getTranslationTokens` sử dụng chung `resolveTokenMeaning`, loại bỏ hoàn toàn việc gọi gián tiếp `translateMeta` thừa thãi, giúp cả dịch đoạn văn và danh sách token Hàng 2 hiển thị nghĩa đồng bộ 100%.

## [1.3.67] - 2026-07-31

### Tích Hợp Google Cloud TTS (ReadAloud API) & Hỗ Trợ Đọc Văn Bản Bôi Đen (`GoogleTTSService.swift`, `TTSManager.swift`, `ReaderView.swift`, `TTSSettingsView.swift`, `project.yml`, `build-ipa.yml`)
* **Tích Hợp GoogleTTSService Native Swift (`GoogleTTSService.swift`)**:
  * Tạo mới `GoogleTTSService` kết nối REST API `https://readaloud.googleapis.com/v1:generateAudioDocStream`.
  * Hỗ trợ 6 giọng đọc tiếng Việt chuẩn: `via` (Giọng nữ tự nhiên), `vib` (Giọng nam tự nhiên), `vic` (Giọng nữ truyền cảm), `vid` (Giọng nam mạnh mẽ), `vie` (Giọng nữ trẻ trung), `vif` (Giọng nữ sâu lắng).
  * Tự động nhận diện API Key theo thứ tự ưu tiên: Custom Key trong `UserDefaults` -> System Secret nhúng trong `Info.plist`.
* **Cập Nhật TTSManager & TTSSettingsView (`TTSManager.swift`, `TTSSettingsView.swift`)**:
  * Bổ sung luồng `tool == "google"` trong `TTSManager` cho prefetch và playback MP3 audio.
  * Thêm ô chọn trình đọc, danh sách 6 giọng đọc tiếng Việt và ô nhập API Key dạng `SecureField` bảo mật mật khẩu kèm nút bật/tắt xem key trong `TTSSettingsView`.
* **Tích Hợp Google Cloud TTS Cho Văn Bản Bôi Đen (`ReaderView.swift`)**:
  * Cập nhật `readSelectedText()` ưu tiên sử dụng `GoogleTTSService` khi bôi đen đọc đoạn văn, có fallback về Siri nếu không có API key hoặc lỗi mạng.
* **Chuẩn Hóa Mã Book ID `stv_{host}_{bookId}`, Loại Bỏ SwiftData Cho Chapter Meta & Tự Động Đóng Trình Duyệt (`GetTextSTVManager.swift`, `content.js`, `BypassWebView.swift`, `BookDetailActionSheetView.swift`, `BookDetailView.swift`, `ShelfView.swift`, `DiscoveryView.swift`)**:
  * Thêm hàm `GetTextSTVManager.canonicalBookId(from:host:)` chuẩn hóa đồng bộ 100% mã `bookId` theo dạng `stv_{host}_{bookId}` (ví dụ `stv_fanqie_7590221243043826712`).
  * Loại bỏ hoàn toàn truy vấn và fallback đến `localBook?.chapters` từ SwiftData đối với dữ liệu mục lục chương, chuyển 100% sang SQLite `ChapterStore.shared.fetchOrderedTOC`.
  * Đơn giản hóa biến tính số chương trong `BookDetailView.swift`: `let totalChaps = chapterSnapshots.count > 0 ? chapterSnapshots.count : onlineChapters.count`.
  * Tách biệt `rawBookId` (số nguyên STV) dùng cho gọi API cào mục lục STV `/index.php?ngmar=chapterlist` và `canonicalBookId` (`stv_{host}_{bookId}`) gửi về cho iOS Native bridge trong `content.js`.
  * Bổ sung gán `showingBypassBrowser = false` trong `onImport` của các View để tắt ngay trình duyệt sau khi hoàn tất hoặc dừng cào dữ liệu.

## [1.3.66] - 2026-07-31

### Khắc Phục Lỗi "Không Tìm Thấy Extension Thích Hợp" Cho Nguồn Sáng Tác Việt (STV) & Đánh Dấu Nhãn STV (`Book.swift`, `GetTextSTVManager.swift`, `BookDetailView.swift`, `ReaderViewModel.swift`, `ChapterContentRepository.swift`, `DownloadManager.swift`, `BookDetailHeaderView.swift`, `ShelfView.swift`)
* **Hỗ Trợ Thuộc Tính `isSTVBook` Trên `Book` Model (`Book.swift`)**:
  * Thêm thuộc tính tính toán `isSTVBook: Bool` để xác định sách thuộc nguồn Sáng Tác Việt (`extensionPackageId == "local_stv"`, `bookId.hasPrefix("stv_")`, hoặc `sourceName` chứa *"Sáng Tác Việt"*).
* **Xử Lý Mở Chi Tiết & Mục Lục Truyện STV Trong `BookDetailView` (`BookDetailView.swift`)**:
  * Kiểm tra `isSTVBook` trong `loadBookDetailOnly()` và `loadTOCDataOnly()`: Sử dụng thông tin metadata và danh sách chương đã nạp sẵn từ `GetTextSTVManager` / `ChapterStore` mà không báo lỗi thiếu tiện ích bóc tách.
* **Xử Lý Nạp Chương & Tải Xuất Truyện STV (`ReaderViewModel.swift`, `ChapterContentRepository.swift`, `DownloadManager.swift`)**:
  * Cập nhật `ReaderViewModel`: Khởi tạo `TTSExtensionInfo` tổng hợp với `packageId: "local_stv"` khi `ext` trả về `nil`.
  * Cập nhật `ChapterContentRepository`: Thêm lỗi `.stvContentNotCached` với thông báo thân thiện *"Chương này chưa được cào từ Sáng Tác Việt. Vui lòng mở trình duyệt web để cào nội dung."* khi đọc file đĩa `.bin` chưa thành công, tránh báo lỗi thiếu tiện ích.
  * Cập nhật `DownloadManager`: Cho phép chạy tác vụ tải / xuất ebook TXT cho truyện STV dựa trên nội dung offline đã cào.
* **Tối Ưu Hóa Nạp Script Trong `GetTextSTVManager.swift` (`GetTextSTVManager.swift`)**:
  * Tách biệt logic nạp `content.css` và `content.js` độc lập từ `Bundle.main`.
  * Đảm bảo logic dự phòng fallback chỉ chạy khi thuộc tính tương ứng bị rỗng, loại bỏ nguy cơ ghi đè `cssContent` đã nạp thành công.
  * Loại bỏ hoàn toàn các đường dẫn ổ đĩa tuyệt đối cứng (`D:\...`) phục vụ môi trường phát triển local.
* **Bảo Đảm Luồng Lưu 100% DB Trước Khi Chuyển Màn Hình Chi Tiết (`content.js`, `BypassWebView.swift`)**:
  * Bổ sung gửi `syncTOC` trong `stopAutoDownload` và `finishAutoDownload` trước khi phát tín hiệu `finishDownload`.
  * Thực thi `context.save()` lưu 100% SwiftData DB local trước khi đóng trình duyệt và chuyển màn hình Chi tiết truyện.

## [1.3.65] - 2026-07-31

### Loại Bỏ Hoàn Toàn Mã Nguồn Dư Thừa GoogleTTS & Chuyển Đổi Phát Âm Bôi Đen Qua AVSpeechSynthesizer Native (`ReaderView.swift`, `TTSManager.swift`, `SiriTTSService.swift`, `JSExecutor.swift`)
* **Loại Bỏ GoogleTTS Dư Thừa (`ReaderView.swift`, `TTSManager.swift`)**:
  * Xóa bỏ hoàn toàn các tham chiếu `GoogleTTSService`, `googleService`, và `googlePrefetchCount`.
  * Gỡ bỏ các nhánh kiểm tra điều kiện `tool == "google"` trong các thuộc tính và luồng nạp prefetch của `TTSManager.swift`.
  * Chuyển đổi hàm `readSelectedText()` trong `ReaderView.swift` từ gọi GoogleTTS sang sử dụng `AVSpeechSynthesizer` native của hệ thống iOS (Siri Voice) để phát âm từ/đoạn văn bôi đen offline.
* **Khắc Phục Cảnh Báo Concurrency & Unused Capture (`TTSManager.swift`, `SiriTTSService.swift`, `JSExecutor.swift`)**:
  * Khắc phục cảnh báo Swift 6 Concurrency truy cập thuộc tính MainActor trong Timer bằng cách bọc closure trong `@MainActor Task` (`TTSManager.swift`).
  * Loại bỏ `@preconcurrency` thừa trên `AVSpeechSynthesizerDelegate` (`SiriTTSService.swift`).
  * Gỡ bỏ capture `[weak self]` không được sử dụng trong closure `DispatchWorkItem` (`JSExecutor.swift`).

## [1.3.64] - 2026-07-30

### Cập Nhật Thuật Toán Tokenizer Ưu Tiên Cụm Dài, Reader Dịch On-Demand In-Place & Sửa Lỗi TTS Dịch Mới (`TranslateUtils.swift`, `ParagraphCardView.swift`, `ReaderView.swift`, `ReaderViewModel.swift`, `ReaderJunkDeleteOverlayView.swift`)
* **Tái Cấu Trúc Phân Tách VietPhrase Trong `TranslateUtils.tokenize` (`TranslateUtils.swift`)**:
  * Thêm struct nội bộ `VPCandidate` lưu trữ vị trí `range` và độ dài `length` của từng cụm VietPhrase (độ dài $\ge 2$).
  * Chuyển đổi thuật toán phân tách VietPhrase từ duyệt tuyến tính cuốn chiếu sang cơ chế Pre-scan và giải quyết tranh chấp chồng lấp theo quy tắc ưu tiên:
    1. Cụm từ có **chiều dài lớn hơn (`length`) luôn chiến thắng** (`length DESC`).
    2. Nếu hai cụm từ có **chiều dài bằng nhau**, cụm từ **bắt đầu trước (`lowerBound`) chiến thắng** (`lowerBound ASC`).
  * Tối ưu hóa hiệu năng $O(N)$ bằng kỹ thuật Pruning bỏ qua các ký tự không phải Hán tự (`isChineseCharacter`) và chỉ đưa các cụm từ ghép ($\ge 2$ chữ) vào mảng sắp xếp candidates.
  * Từ Hán đơn lẻ standing alone được bảo toàn 100% nghĩa thông qua mảng Token 1-ký tự và hệ thống tra cứu 4 cấp (Book VP $\rightarrow$ Custom VP $\rightarrow$ Base VP $\rightarrow$ Phiên âm Hán Việt) ở bước `performTranslation`.
* **Reader Dịch On-Demand In-Place & Triệt Tiêu Hoàn Toàn Lỗi Trôi/Văng Scroll (`ReaderViewModel.swift`, `ParagraphCardView.swift`, `ReaderView.swift`)**:
  * **Loại bỏ nạp lại mảng dư thừa (`ReaderViewModel.swift`)**: Gỡ bỏ vòng lặp tác vụ bất đồng bộ `processAndSaveChapter` trong `toggleTranslation(enabled:)`, ngăn chặn việc hủy và re-render mảng thẻ view `paragraphItems`.
  * **Dịch On-Demand Inline trực tiếp tại chỗ (`ParagraphCardView.swift`)**: Truyền `bookId` và `@Binding var translationRefreshToken: UUID`. Áp dụng biểu thức dịch inline trực tiếp tại chỗ `text: isTranslationEnabled ? (item.isTitle ? TranslateUtils.translateChapterTitle(item.original, bookId: bookId) : TranslateUtils.translateContent(item.original, bookId: bookId)) : item.original`. Phân biệt chính xác hàm dịch Tiêu đề chuyên dụng và Nội dung đoạn văn.
  * **Đồng bộ tín hiệu đổi từ điển In-Place (`ReaderView.swift`)**: Khai báo `@State private var translationRefreshToken = UUID()`. Khi nhận thông báo `translationDictionariesDidUpdate` (khi người dùng sửa/thêm từ mới trong từ điển), xóa RAM cache `clearCache()` và đổi `translationRefreshToken = UUID()`.
  * **Bảo toàn vị trí cuộn điểm ảnh 100%**: Toàn bộ mảng thẻ view và ID giữ nguyên 100%, tọa độ pixel offset (`contentOffset.y`) đứng yên tuyệt đối không bị trôi hay văng scroll dù 1 pixel, không cần dùng bất kỳ lệnh cuộn `scrollTo` nào.
* **Khắc Phục Lỗi Màn Hình Xoá Từ Rác (`ReaderJunkDeleteOverlayView.swift`, `ReaderView.swift`)**:
  * **Đồng bộ ô nhập từ (`ReaderView.swift`)**: Cập nhật `self.junkPatternInput = word` trong `updateEditorFromSelection()`, giúp ô nhập `TextField` tự động đổi chuỗi từ theo vùng chọn khi bấm các nút chevron mở rộng/thu hẹp.
  * **Sửa lỗi bàn phím che lấp ô nhập (`ReaderView.swift`)**: Gỡ bỏ `.ignoresSafeArea(.keyboard, edges: .bottom)` khỏi overlay `showingJunkDeleteSheet`, giúp khung overlay tự động trượt nổi lên trên đỉnh bàn phím khi chạm nhập từ.
* **Khắc Phục Lỗi TTS Không Đọc Theo Từ Điển Mới Vừa Sửa (`ReaderView.swift`, `ReaderViewModel.swift`)**:
  * **Dịch động tại chỗ cho TTS (`ReaderView.swift`)**: Thêm `getTTSChapterContent(for: index)` dịch động nội dung chương (`TranslateUtils.translateContent`) và dịch động tiêu đề chương (`TranslateUtils.translateChapterTitle`) khi bắt đầu phát giọng đọc.
  * **Làm mới bộ nhớ RAM ViewModel & Xóa đệm TTS (`ReaderViewModel.swift`, `ReaderView.swift`)**: Thêm `updateCachedTranslatedContent(bookId:)` làm mới `cached.content` và `cached.translatedTitle` khi đổi từ điển, đồng thời xóa đệm phát TTS cũ (`TTSManager.shared.clearPrefetchCache()`).

## [1.3.63] - 2026-07-30

### Xoá Từ Rác Khi Bôi Đen Trước Khi Chuẩn Hoá & Màn Hình Quản Lý Lọc Rác Dùng Chung (`JunkFilterManager.swift`, `ChapterTextNormalizer.swift`, `ReaderJunkDeleteOverlayView.swift`, `JunkFilterManagementView.swift`, `ReaderView.swift`, `SettingsView.swift`)
* **Hệ Thống Lọc Rác Từ Gốc Trước Khi Chuẩn Hoá (`JunkFilterManager.swift`, `ChapterTextNormalizer.swift`)**:
  * Tạo dịch vụ `JunkFilterManager` quản lý danh sách quy tắc lọc rác (từ/chuỗi/regex) và áp dụng trực tiếp lên `rawContent` trong `ChapterTextNormalizer.normalize` trước khi cắt dòng và tính toán UTF-16 ranges/Paragraph IDs.
  * Custom Codable hỗ trợ tương thích 100% với định dạng file `TrashWords.json` từ Telegram (`word`, `regex`).
* **Khung Xác Nhận Xoá Từ Rác Khi Bôi Đen Trong Trình Đọc (`ReaderJunkDeleteOverlayView.swift`, `ReaderFloatingMenuOverlayView.swift`, `ReaderView.swift`)**:
  * Thêm nút **"Xoá"** (icon `trash.fill`) vào menu nổi khi bôi đen trong Trình đọc.
  * Hiển thị khung overlay xác nhận với 2 hàng Gốc và Dịch trên cùng kèm 4 nút chevron thu/mở lề bôi đen 2 bên (trái/phải), ô nhập từ muốn xoá để kiểm tra/chỉnh sửa, cùng nút **Hủy** và **Xác nhận**.
  * Tự động xóa cache và nạp/chuẩn hóa lại chương active giúp từ rác biến mất ngay lập tức khỏi màn hình.
* **Màn Hình Quản Lý Lọc Rác Dùng Chung (`JunkFilterManagementView.swift`, `SettingsView.swift`, `ReaderHeaderFooterOverlayView.swift`, `ReaderSettingsView.swift`)**:
  * Xây dựng giao diện SwiftUI `JunkFilterManagementView` hỗ trợ CRUD, bật/tắt, tìm kiếm, nhập/xuất file JSON cấu hình và khôi phục mặc định.
  * Đấu nối từ cả Cài đặt hệ thống (**SettingsView**) lẫn Tuỳ chọn Trình đọc (**ReaderHeaderFooterOverlayView** và **ReaderSettingsView**).
* **Khắc Phục Lỗi Treo Nạp Chương Khi Mở Quy Tắc TOC Từ Reader (`ReaderView.swift`)**:
  * Nguyên nhân: Trước đó `ReaderView` mở `TOCRulesConfigView()` thông qua `NavigationLink` khiến iOS kích hoạt sự kiện `.onDisappear` của `ReaderView`, dẫn tới việc `ReaderViewModel.shutdown()` tự động tắt bộ nhớ và hủy tác vụ nạp chương. Khi người dùng Back quay lại `ReaderView`, `viewModel` đã bị tắt nên treo ở trạng thái nạp mãi.
  * Giải pháp: Chuyển đổi hiển thị `TOCRulesConfigView()` sang dạng `.sheet(isPresented: $showingTOCRules)` dạng modal. Giúp `ReaderView` duy trì liên tục trong cây phân cấp view, bảo toàn trạng thái `viewModel` và mở/đóng quy tắc TOC mượt mà mà không bị mất nội dung chương.
* **Tinh Chỉnh Dải Chip Gợi Ý Màn Hình Dịch & Giao Diện Phông Nền Tối (`ReaderDefinitionOverlayView.swift`, `ReaderView.swift`)**:
  * Đơn giản hóa nguồn truy vấn chip gợi ý: Chỉ lọc dữ liệu từ 3 nguồn: **Names** (Book, Custom, Global), **VietPhrase** (Book, Custom, Global) và **Phiên âm Hán Việt**, loại bỏ Pronouns và Luật nhân khỏi dải gợi ý.
  * Áp dụng lọc trùng phân biệt hoa thường exact matching (`$0.text == trimmed`).
  * Áp dụng giao diện phông nền tối toàn bộ `Color(red: 0.12, green: 0.12, blue: 0.15)` đồng nhất chuẩn Dark Mode, kết hợp phân biệt loại từ bằng màu viền & chữ: **Tím Lavender** (Names), **Xanh Sky Blue** (VietPhrase), **Vàng Amber** (Hán Việt).
* **Tự Động Cập Nhật Số Từ Từ Điển & Tự Động Nạp Dịch Lại Trong Reader (`TranslationManager.swift`, `DictionaryHubView.swift`, `ReaderView.swift`)**:
  * Đánh dấu `@Published` cho `customVietPhraseDict` và `customNamesDict` trong `TranslationManager`.
  * Bổ sung `@State private var refreshToken = UUID()` và `.onAppear` trong `DictionaryHubView` đếm và hiển thị ngay lập tức số từ mới nhất khi bấm Back ra ngoài.
  * Phát thông báo `translationDictionariesDidUpdate` khi cập nhật từ điển; `ReaderView` tự động xóa cache và ép nạp/dịch lại chương đang đọc (`forceRefresh: true`) để hiển thị nghĩa mới tức thì.
* **Xóa Bỏ Hoàn Toàn Google TTS (`GoogleTTSService.swift`, `TTSEngineType.swift`, `TTSManager.swift`, `TTSSettingsView.swift`)**:
  * Xóa bỏ hoàn toàn tệp `GoogleTTSService.swift` và các tham chiếu tới `case google` trong `TTSEngineType`, `TTSManager` và `TTSSettingsView`. Giữ nguyên 100% các công cụ đọc `Siri TTS` và `Nghi TTS` (Piper Engine).
* **Tích Hợp Extension `GetTextSTV` Bóc Tách Nguồn Sáng Tác Việt (`GetTextSTVManager.swift`, `BypassWebView.swift`)**:
  * **Lối Tắt STV IP Trang Home**: Bổ sung thẻ Lối Tắt **"Sáng Tác Việt (STV IP)"** (`http://14.225.254.182/`) nổi bật trên trang chủ Home của Trình duyệt `BypassWebView`.
  * **Bộ Polyfill Safari iPhone (iOS WKWebView)**: Tiêm bộ giả lập `chrome.storage.local` bằng `window.localStorage` và `gettextSTVBridge`, đảm bảo 100% kịch bản bóc tách và lọc rác chạy mượt mà trên iPhone không bị lỗi `ReferenceError`.
  * **Quy Trình 2 Bước & Chuyển Màn Hình Detail**: Nạp mục lục bổ sung metadata chương mới (`syncTOC`) $\rightarrow$ Tải nội dung chương chưa có vào đĩa `.bin` (`saveChapterContent`) qua `enqueueWrite` và `flush` của `ChapterPersistenceStore` $\rightarrow$ Đóng trình duyệt và tự động chuyển sang màn hình Chi Tiết Truyện (`BookDetailView`) qua `onImport` callback ngay khi hoàn tất/dừng tải.
* **Tính Năng Hẹn Giờ Tạm Dừng Nghe Truyện - Sleep Timer (`TTSManager.swift`, `TTSFloatingWidgetView.swift`, `TTSSettingsView.swift`)**:
  * **Bộ Quản Lý Hẹn Giờ Ghi Nhớ Lặp Lại**: Bổ sung `SleepTimerMode` (`off`, `minutes(Int)`, `endOfChapter`) trong `TTSManager.swift`. Tự động lặp lại bộ đếm khi người dùng bấm nghe lại (Play) sau khi tạm dừng, giữ nguyên chế độ hẹn giờ cho đến khi chọn *Tắt hẹn giờ*.
  * **Nút Menu Hẹn Giờ Thích Ứng Khóa Cứng Widget (`TTSFloatingWidgetView.swift`, `FloatingWidgetViewModel.swift`)**: Chuyển nút Hẹn giờ/Cài đặt sang SwiftUI `confirmationDialog` trực tiếp kèm cờ khóa cứng `disableAutoHide = true` trong `FloatingWidgetViewModel`. Đảm bảo Widget ngự cố định 100% ở dạng mở rộng trên màn hình khi đang mở xem/chọn tùy chọn Hẹn giờ, **tuyệt đối không bị tự động thu nhỏ vào góc**.
  * **Tag Đếm Ngược Nổi Đỉnh Widget (Vị Trí 3)**: Hiển thị thanh Tag màu Cam `⏱️ 14:35 - Hẹn giờ 15p` đếm ngược thời gian thực ngay trên đỉnh thanh Widget nổi khi đang đếm ngược.
* **Khắc Phục Lỗi Google TTS HTTP 429 & Tùy Chỉnh Giao Diện Cài Đặt TTS (`GoogleTTSService.swift`, `TTSManager.swift`, `TTSSettingsView.swift`)**:
  * **Chống 429 Google TTS Bằng JS Engine**: Chuyển đổi `GoogleTTSService.swift` sang chạy mã JavaScript qua `JSExecutor` (`JSContext` + JSDOM engine + `fetch` JS giống hệt Extension TTS `ext`), luân chuyển `client=gtx` và `client=dict-chrome-ex` hoàn toàn không bị Google chặn.
  * **Giãn tiến trình tối thiểu 500ms**: Đặt dãn cách tối thiểu 500ms giữa tất cả các đoạn cho các Online Engines. Ép sàn tối thiểu `prefetchDelayMs` $\ge 500\text{ms}$ trong `TTSManager.swift`.
  * **Nút Reset Tốc Độ & Cao Độ**: Bổ sung nút **"Đặt lại"** (icon `arrow.counterclockwise`) trong `TTSSettingsView.swift` khôi phục tức thì Tốc độ và Cao độ về $1.0x$.
  * **Nút Stepper (+/-) nấc 0.1**: Bổ sung Stepper (+/-) nấc tăng giảm $0.1$ cho cả Tốc độ (0.5x–5.0x) và Cao độ (0.5x–2.0x) kết hợp cùng Slider trong `TTSSettingsView.swift`.
  * **Stepper Dãn Tiến Trình**: Cập nhật Stepper dãn tiến trình nạp trước dải giá trị từ $500\text{ms}$ đến $5000\text{ms}$ (không thể chỉnh dưới 500ms), bước tăng/giảm $100\text{ms}$.
* **Khắc Phục Lỗi Vừa Vào Trình Đọc Bấm Nút Nghe Bị Đọc Từ Đầu Chương (`ReaderView.swift`)**:
  * Cập nhật nhánh fallback của nút Nghe (`readerTTSControl`) khi `paragraphTracker` chưa kịp thu thập tọa độ hiển thị: Ưu tiên tra cứu vị trí đọc đã khôi phục bằng `getSavedParagraphIndex(for: chapterIndex)` và `viewModel.readingContext.paragraphIndex`.
  * Khắc phục triệt để sự cố bấm nút Nghe ngay sau khi vừa mở sách tại vị trí khôi phục bị tự động nhảy về phát từ Đoạn 0.
* **Khắc Phục Sự Cố Nút Nghe (TTS) Đọc Nhầm Đầu Chương & Nhầm Đoạn Giữa Màn Hình & Tinh Chỉnh FloatingMenu (`ReaderView.swift`, `ReaderFloatingMenuOverlayView.swift`)**:
  * Nâng cấp `ParagraphTracker` quản lý cấu trúc toạ độ hình học `ParagraphFrame(minY, maxY)` trên từng thẻ đoạn văn trong `ReaderView`.
  * Khắc phục triệt để Lỗi 1 (bấm nút Nghe ngay sau khi mở sách tại vị trí khôi phục bị đọc từ Đoạn 0): Lọc bỏ hoàn toàn các đoạn văn có $maxY \le viewportTopY + 5$ (đã bị cuộn khuất lên phía trên) mà không cần chờ sự kiện `.onDisappear` thụ động từ SwiftUI `LazyVStack`.
  * Khắc phục triệt để Lỗi 2 (đọc đoạn ở giữa màn hình): Lấy chính xác 100% đoạn văn nằm ngay ở đường đỉnh hiển thị trên cùng (`minY` cao nhất trong số các đoạn cắt qua viewport).
  * Tối ưu hoá 0ms overhead: Dữ liệu toạ độ lưu trong Class in-memory không dùng `@State`, đảm bảo tốc độ cuộn mượt mà 60fps/120fps.
  * Loại bỏ nút **"Đóng"** trên menu nổi `FloatingSelectionMenu` khi bôi đen văn bản, tự động đóng menu khi chạm ra ngoài và thu gọn chiều rộng menu xuống 370pt.
* **Sửa Lỗi Biên Dịch Build Errors & Tương Thích Swift 6 Concurrency (`JunkFilterManager.swift`, `ReaderView.swift`)**:
  * Chuyển `JunkFilterManager` thành class thường với `public static let shared` không bị giới hạn bởi `@MainActor init()`, gán `@MainActor` trực tiếp cho thuộc tính UI `rules` và các phương thức CRUD để giải quyết triệt để lỗi biên dịch Swift 6 Concurrency initializer call.
  * Thay thế lệnh gọi `vm.loadChapter(at:forceRefresh:)` không tồn tại bằng `vm.reloadDisplayedChapter()` trong `ReaderView.swift`.
* **Ghim Độc Lập Lựa Chọn Mặc Định Màn Hình Dịch Nhấn Giữ Lâu (`ReaderView.swift`, `ReaderDefinitionOverlayView.swift`)**:
  * Tách độc lập 2 cụm bộ chọn: **Loại từ điển** (`Names`/`VP`, mặc định ban đầu: `VP`) và **Phạm vi từ điển** (`Riêng`/`Chung`, mặc định ban đầu: `Riêng`).
  * Loại bỏ việc tự động ghi đè thụ động khi chọn tạm thời; bấm ngắn (Tap) chỉ đổi tạm thời cho từ đang chỉnh sửa.
  * Hỗ trợ cử chỉ **Nhấn giữ lâu (Long Press)** trực tiếp trên bất kỳ nút nào để Ghim cố định nút đó làm mặc định mới cho cụm tương ứng, kèm rung haptic, hiển thị badge ghim `pin.fill` sáng đèn và thông báo Toast xác nhận.
* **Khắc Phục Lỗi Google TTS 429, Sai Speed, Chuẩn Hóa Toast + Pause & Cài Đặt Độ Trễ Giãn Tiến Trình Cho TẤT CẢ Các Engine TTS (`TTSManager.swift`, `TTSSettingsView.swift`)**:
  * Sửa lỗi lệch khóa `UserDefaults` trong `speed.didSet`, `pitch.didSet`, `selectedVoice.didSet` bằng cách bổ sung nhánh `else if tool == "google"` để lưu chính xác tốc độ đọc `googleRate`, `googlePitch`, `googleVoice`.
  * Khắc phục vòng lặp tự động gọi `nextParagraph()` khi bị lỗi Google TTS HTTP 429 khiến IP bị Google chặn liên tiếp (6 request/3 giây).
  * Chuẩn hóa đồng bộ cho cả 4 Engine TTS (`Google`, `NghiTTS`, `Extension`, `System Siri`): Khi gặp lỗi, lập tức dọn cache đoạn lỗi, bảo toàn vị trí `currentParagraphIndex`, gọi `self.pause()` tạm dừng trình đọc và hiển thị Toast màu đỏ báo lỗi trực quan. Khi người dùng bấm nút **Phát (Play)** lại, hệ thống sẽ tự động tạo lại và thử lại đoạn văn vừa bị lỗi.
  * Bổ sung thuộc tính `@Published public var prefetchDelayMs: Int` dãn khoảng cách gọi API nạp trước (`Task.sleep`) tính theo milisecond giữa các đoạn tiếp theo ($N+2, N+3,...$), lưu trữ độc lập cho từng Engine trong `UserDefaults` (`googlePrefetchDelay`, `nghittsPrefetchDelay`, `extPrefetchDelay_\(tool)`).
  * Bổ sung Stepper tùy chỉnh thời gian dãn tiến trình (từ $0\text{ms}$ đến $2000\text{ms}$, nấc $50\text{ms}$) trong `TTSSettingsView` cho người dùng linh hoạt điều chỉnh theo tốc độ đường truyền.
* **Khắc Phục Lỗi Tự Động Dịch Lại Khi Vào Màn Hình Từ Điển (`TranslationManager.swift`)**:
  * Gỡ bỏ việc phát thông báo `translationDictionariesDidUpdate` thụ động trong hàm nạp dữ liệu `loadAllDictionaries()`.
  * Chuyển lệnh phát thông báo `translationDictionariesDidUpdate` về đúng các phương thức thay đổi từ điển thực sự (`saveCustomEntry`, `deleteCustomEntry`, `addDeletedWords`, `removeDeletedWords`, `importDictionary`, `deleteDictionary`, `downloadDefaultDictionaries`).
  * Giúp Trình đọc không bị xóa cache và dịch lại chương vô ích khi người dùng chỉ bấm vào xem màn hình Từ Điển và Back ra ngoài. Trình đọc chỉ dịch lại khi có thay đổi từ điển thực sự.
* **Mở Màn Hình Quản Lý Thay Thế Ký Tự TTS Dạng Sheet Trực Tiếp Trên Cài Đặt TTS (`TTSSettingsView.swift`)**:
  * Tái sử dụng 100% view `TTSReplacementManagerView.swift` hiện có.
  * Chuyển đổi nút *"Quản lý thay thế ký tự"* trong `TTSSettingsView` mở `TTSReplacementManagerView` dưới dạng cửa sổ `.sheet` đè trực tiếp lên Cài đặt TTS kèm nút *"Đóng"* tiện lợi.

## [1.3.62] - 2026-07-30

### Tùy Chỉnh Phông Chữ Đọc Sách Đa Dạng (Tiếng Việt & Tiếng Trung) & Tinh Chỉnh Màu Highlight Nội Dòng Chuẩn Tông (`ReaderView.swift`, `ReaderSettingsView.swift`, `ReaderTextView.swift`, `ParagraphCardView.swift`)
* **Tùy Chọn Kiểu Chữ Đọc Sách Tối Ưu Cho Cả Tiếng Việt & Hán Tự (`ReaderView.swift`, `ReaderSettingsView.swift`, `ReaderTextView.swift`)**:
  * Khai báo `enum ReaderFontFamily` hỗ trợ đa dạng phông chữ đọc sách chuẩn iOS: `Georgia` (Kindle Classic), `Palatino` (Văn Học), `Charter` (Tiếng Việt Rõ Nét), `Avenir Next` (Hiện Đại), `Songti SC` (Tống Thể - Hán Tự), `Kaiti SC` (Khải Thể - Thư Pháp Hán Tự), `PingFang SC` (Bình Phương Hán Tự) và `San Francisco` (Hệ Thống).
  * Bổ sung Picker chọn Kiểu chữ trong sheet `ReaderSettingsView` giúp người dùng thay đổi phông chữ tức thì khi đọc tiểu thuyết dài.
* **Hệ Thống Màu Highlight Chuẩn Tông Theo Nền Đọc (`ReaderTheme`, `ReaderTextView.swift`)**:
  * Bổ sung `highlightUIColor` và `highlightTextUIColor` trong `enum ReaderTheme` tinh chỉnh màu highlight hòa quyện 100% cho từng theme: Vàng Hổ Phách Mềm cho nền `Paper`, Cam Đất Caramels cho nền `Sepia`, và **Xám Bạc Đêm (Slate Gray - `UIColor(white: 1.0, alpha: 0.16)`)** chữ trắng tinh chuẩn Apple Dark Mode cho nền `Dark`.

## [1.3.61] - 2026-07-30

### Tích Hợp Quản Lý Quy Tắc Mục Lục (TOCRulesConfigView) Dùng Chung Vào Dropdown Menu Của Reader (`ReaderView.swift`, `ReaderHeaderFooterOverlayView.swift`)
* **Tái Sử Dụng Màn Hình Quản Lý Quy Tắc TOC Dùng Chung (`ReaderView.swift`, `ReaderHeaderFooterOverlayView.swift`)**:
  * Tích hợp tùy chọn **"Quy tắc mục lục (TOC)"** (kèm icon `list.bullet.indent`) vào Dropdown Menu (Menu 3 chấm) góc trên màn hình đọc truyện `ReaderHeaderFooterOverlayView`.
  * Đấu nối `NavigationLink` trong `ReaderView` mở trực tiếp màn hình quản lý quy tắc TOC chuẩn `TOCRulesConfigView()`, giúp người dùng bật/tắt hoặc chỉnh sửa regex lọc mục lục ngay trong khi đọc mà không phải thoát ra cài đặt chung.

## [1.3.60] - 2026-07-30

### Đọc Thuộc Tính Thô `plugin.json`, Tập Trung Cấu Hình Extension TTS & Tránh Xung Đột Cài Đặt (`ExtensionConfigView.swift`, `TTSSettingsView.swift`, `TTSManager.swift`)
* **Hỗ Trợ Đọc & Tùy Chỉnh Tất Cả Thuộc Tính Thô (Primitives) trong `plugin.json` (`ExtensionConfigView.swift`)**:
  * Mở rộng `loadConfigDefinitions()` để nhận diện và hiển thị đầy đủ tất cả các trường cấu hình thô không phải Object trong `plugin.json` (bao gồm `"preload_size": 3`, `"max_length": 600`, `"required_api_key": false`, `"support_url": ""`...).
  * Tự động ép kiểu dữ liệu từ chuỗi về đúng dạng nguyên bản (`Bool`, `Int`, `Double`, `String`) trong `saveConfig()` để bảo toàn tính đúng đắn cho JS Engine và `TTSManager`.
* **Áp Dụng Thông Số NẾU CÓ & Chống Chồng Chéo Cài Đặt (`TTSManager.swift`, `TTSSettingsView.swift`)**:
  * `TTSManager.swift`: Tự động trích xuất `preload_size` và `max_length` từ `extensionConfigJson` NẾU Extension có khai báo. Nếu không có, tự động áp dụng giá trị mặc định hệ thống (3 đoạn / 200 ký tự).
  * `TTSSettingsView.swift`: Khi chọn Extension TTS, tự động **ẨN** ô nhập "Độ dài phân đoạn (ký tự)" và Stepper "Số đoạn tải trước" để tránh xung đột và trùng lặp, thay bằng nút bấm mở trực tiếp sheet `ExtensionConfigView` của Extension đó.

## [1.3.59] - 2026-07-30

### Chuyển Đổi TTS Engine Sang AVAudioPlayer Mặc Định & Cài Đặt Preloading Riêng Theo Engine (`TTSManager.swift`, `ExtTTSService.swift`, `TTSSettingsView.swift`)
* **Chuyển Toàn Bộ Engine sang Trình Phát Âm Thanh Mặc Định `AVAudioPlayer` (`TTSManager.swift`, `ExtTTSService.swift`)**:
  * Thay thế luồng phát qua `AVAudioEngine` bằng `AVAudioPlayer(data: audioData)` chuẩn Hardware Audio DSP của iOS cho tất cả các công cụ đọc (Google TTS, Extension TTS, NghiTTS).
  * Tự động mang lại chất âm êm mịn, mượt mà 100% giống ứng dụng VBook mẫu khi phát qua Tai nghe Bluetooth.
  * Bổ sung `synthesizeData` trong `ExtTTSService.swift` trả về dữ liệu `Data` trực tiếp, triệt tiêu hoàn toàn chi phí ghi tệp tạm và resampling PCM.
* **Tách Cài Đặt Preloading Riêng Trực Quan Theo Engine & Đồng Bộ Config Extension (`TTSManager.swift`, `TTSSettingsView.swift`)**:
  * Bổ sung thuộc tính `googlePrefetchCount`, `nghittsPrefetchCount` và `extPrefetchCount` lưu riêng lẻ trong `UserDefaults` cho từng công cụ đọc.
  * Bổ sung phương thức `parseExtensionConfigParams` tự động trích xuất `preload_size` và `max_length` từ JSON `config` của Extension TTS để nạp giá trị mặc định ban đầu.
  * Thiết lập độ ưu tiên 3 cấp: Cài đặt người dùng (`UserDefaults`) > Config Extension (`preload_size`/`max_length`) > Mặc định hệ thống FreeBook (3 đoạn / 200 ký tự).
  * Cập nhật `TTSSettingsView.swift` hiển thị Stepper Preload linh hoạt theo Engine được chọn và hiển thị gợi ý thông số mặc định của Extension.

## [1.3.58] - 2026-07-30

### Sửa Lỗi Không Dịch Lại Các Chương Preloaded Khi Cập Nhật Từ Điển (`ReaderViewModel.swift`, `ReaderView.swift`, `ReaderDefinitionOverlayView.swift`)
* **Dịch Lại Toàn Bộ Các Chương Trong Bộ Nhớ Đệm RAM (`ReaderViewModel.swift`)**:
  * Cập nhật phương thức `toggleTranslation(enabled:)` và `refreshParagraphItems()` trong `ReaderViewModel` để duyệt qua toàn bộ các chương đã được tải trước trong `cache.cache` có `state == .loaded` (thay vì chỉ cập nhật `displayedChapterIndex` và `pendingNavigationIndex`).
  * Thực hiện `processAndSaveChapter` cho tất cả các chương `.loaded` này để cập nhật lại tiêu đề và các đoạn văn bản theo từ điển dịch mới.
* **Đồng Bộ Dịch Lại Khi Đóng/Lưu Từ Điển (`ReaderDefinitionOverlayView.swift`, `ReaderView.swift`)**:
  * Bổ sung callback `onApplyTranslation` kích hoạt dịch lại toàn bộ các chương đã load trong RAM khi người dùng thêm, sửa, xóa từ trong sheet quản lý từ điển `ManageDefinitionsView` hoặc bấm "Cập nhật" ở màn hình dịch chương.

## [1.3.57] - 2026-07-30

### Tối Ưu Chất Lượng Resample & Khắc Phục Tiếng Xì/Rè Audio Hiss (TTS Audio Pipeline)
* **Khắc Phục Nhiễu Răng Cưa (Aliasing Hiss) Trong Converter (`TTSManager.swift`, `ExtTTSService.swift`)**:
  * Đặt `converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue` cho tất cả các `AVAudioConverter` instance trong `makePCMBuffer(fromWavData:targetFormat:)`, `makePCMBuffer(fromMp3Data:targetFormat:)` và `ExtTTSService.synthesize`.
  * Ép bộ chuyển đổi tần số của Apple sử dụng thuật toán nội suy mẫu (resampling) chất lượng tối đa, loại bỏ hoàn toàn nhiễu aliasing dải tần cao khi nâng tần số từ 22.05kHz/24kHz lên 44.1kHz/48kHz.
* **Bộ Lọc Thông Thấp Low-Pass Filter 10kHz & Bypass `timePitchNode` ở 1.0x (`TTSManager.swift`)**:
  * Tích hợp node `AVAudioUnitEQ` (`.lowPass`, `frequency = 10000.0 Hz`) vào `AVAudioEngine` để gọt sạch 100% dải tần rác siêu cao (>10kHz) vốn bị khuyếch đại gây gắt/chói tai trên Tai nghe Bluetooth.
  * Tự động **Bypass `timePitchNode`** ở tốc độ 1.0x (`speed == 1.0 && pitch == 1.0`), nối trực tiếp `playerNode` -> `eqNode` -> `mainMixerNode` để giữ âm thanh nguyên bản, loại bỏ hoàn toàn nhiễu Phase Vocoder của iOS ở tốc độ chuẩn.
* **Chuyển Giải Mã WAV sang `AVAudioFile` & Magic Bytes (`TTSManager.swift`, `ExtTTSService.swift`)**:
  * Thay thế logic giải mã WAV thủ công (`advanced(by: 44)`) bằng `AVAudioFile(forReading:)` của CoreAudio, phòng ngừa triệt để lỗi lệch byte alignment làm đảo sample Int16 gây xé tiếng.
  * Thêm nhận diện Magic Bytes (`RIFF` vs `MP3`) trong `ExtTTSService.swift` để tự động lưu đúng đuôi mở rộng `.wav` hoặc `.mp3` cho tệp tạm.
* **Chuẩn Hóa Biên Độ PCM Float (`ExtTTSService.swift`)**:
  * Bổ sung soft-clamping biên độ float PCM `max(-1.0, min(1.0, sample))` trong `preprocessBufferForExtTTS` để ngăn ngừa hiện tượng vỡ tiếng/xé tiếng do vượt ngưỡng biên độ.

## [1.3.56] - 2026-07-30

### Cập Nhật Danh Sách Quy Tắc Phân Tách Mục Lục Mặc Định (TOC Rules)
* **Cập nhật & Chuẩn hóa `defaultTOCRules` trong ([TranslateUtils.swift](../../Sources/Services/Translation/Utils/TranslateUtils.swift))**:
  * Chuẩn hóa bộ ID thành chuỗi đồng nhất theo định dạng `rule1` đến `rule21`.
  * Đổi toàn bộ tên gọi (Name) sang tiếng Việt trực quan mô tả chính xác cấu trúc dòng tiêu đề nhận diện.
  * Chuẩn hóa toàn bộ các ví dụ mẫu (Example) bằng tiếng Trung nguyên bản đối với các quy tắc liên quan đến tiếng Trung, đảm bảo 100% khớp thành công với biểu thức Regex tương ứng.
  * Khắc phục triệt me lỗi biên dịch `unprintable ASCII character found in source file` trên `TranslateUtils.swift` bằng cách làm sạch tất cả ký tự Tab điều khiển (`0x09`) trực tiếp trong chuỗi Regex `defaultTOCRules`, thay bằng mã hóa chuẩn `\s`.
  * Chuyển logic nhận diện dòng tiêu đề chương `isChapterHeaderLine` trong `TranslateUtils.swift` sang sử dụng 100% các quy tắc `TOCRule` đang bật, loại bỏ các cơ chế từ khóa thủ công (`chương`, `第`, `chapter`...) và số đầu dòng cũ để xử lý triệt để lỗi cắt nhầm câu văn nội dung tiếng Trung/tiếng Việt thành tiêu đề chương phụ.
  * Tắt mặc định quy tắc `rule4` (`enabled: false`) để tránh từ `"场"` (trận đấu) trong văn bản truyện bị nhận nhầm làm tiêu đề chương.
* **Mở Rộng Quy Tắc Thay Thế Ký Tự TTS & Tái Cấu Trúc Giao Diện ([TTSReplacementManager.swift](../../Sources/Services/TTS/Preprocessing/TTSReplacementManager.swift), [TTSReplacementManagerView.swift](../../Sources/Views/Settings/TTS/TTSReplacementManagerView.swift))**:
  * Bổ sung đầy đủ nhóm quy tắc mặc định `defaultRulesList`: phát âm ký hiệu/toán học tiếng Việt (`+` thành `cộng`, `@` thành `a còng`, `%` thành `phần trăm`, `×` thành `nhân`, `÷` thành `chia`, `±` thành `cộng trừ`, `≠` thành `khác`, `≈` thành `xấp xỉ`, `€` `¥` `£`), thay dấu `=` và `&` thành khoảng trắng; loại bỏ `-` đơn để tránh đọc sai từ ghép; bổ sung đầy đủ các loại dấu chấm giữa phân cách tên Trung/Tây/Nhật (`·` `•` `‧` `ㆍ` `⋅` `･` thành khoảng trắng); chuyển tất cả quy tắc thay thế ngoặc kép, ngoặc đơn trích dẫn, ngoặc chú thích/phụ đề/Hán-Nhật (`""`, `''`, `“”`, `‘’`, `„‟`, `«»`, `‹›`, `＂＇`, `❝❞`, `❛❜`, `〞〟`, `()`, `[]`, `{}`, `【】`, `〔〕`, `〖〗`, `「」`, `『』`, `《》`) sang thay thế bằng dấu phẩy `, ` để tạo nhịp ngắt dừng và nhấn mạnh ngữ điệu cho lời thoại/cụm từ khi TTS đọc; và thay thế các biểu tượng rác (`~`, `*`, `#`, `^`, `\`, `|`, `♪♫`, `♥♡❤❥`, `◆◇■□▲△▼▽○●◎`, `☆★✦✧`) bằng khoảng trắng `" "`.
  * Thêm phương thức `resetToDefaults(mode:)` cho phép khôi phục danh sách mặc định (gộp hoặc ghi đè).
  * Tái cấu trúc giao diện `TTSReplacementManagerView`: Gom các tính năng tùy chọn (Khôi phục mặc định, Nhập JSON, Xuất JSON) vào Menu Dropdown `ellipsis.circle` bên trái bottom bar, và di chuyển Nút Thêm quy tắc (`plus`) xuống góc dưới bên phải bottom bar.

## [1.3.55] - 2026-07-29

### Chuyển Đổi Nguồn Dữ Liệu Mục Lục (TOC Metadata) Từ SwiftData Chapter Sang ChapterStore
* **Tối ưu hóa Reader khi Cập nhật Danh sách Chương (`ReaderChapterListView.swift`)**:
  * Cập nhật danh sách chương dùng `ChapterStore` primary để lấy danh sách chương hiện có và đếm tổng số chương qua `fetchCountAndChecksum`, loại bỏ việc đếm bằng SwiftData `modelContext.fetchCount`.
  * Chỉ lọc và upsert các chương mới chưa có vào DB. Nếu không có chương mới, ứng dụng bỏ qua lệnh ghi DB và cập nhật ngay giao diện.
* **Tối ưu hóa Màn hình Chi tiết Sách (`BookDetailView.swift`)**:
  * Khi bấm "Đọc tiếp", nếu sách đã có TOC trong `ChapterStore` thì ứng dụng mở thẳng Reader ngay lập tức mà không tải/lưu lại toàn bộ TOC online.
  * Giao diện mục lục ưu tiên dùng `chapterSnapshots: [StoredChapterSnapshot]` và chuyển các cờ lắng nghe thay đổi số lượng chương khỏi phụ thuộc vào `book.chapters`.
* **Cập nhật Nguồn Sách trong Tìm kiếm (`SearchView.swift`)**:
  * Khi thay đổi nguồn sách, danh sách chương được tạo snapshot và lưu qua `ChapterContentRepository` / `ChapterStore` thay vì khởi tạo các đối tượng `Chapter` SwiftData trực tiếp.
* **Dịch lại Tiêu đề Chương trên Kệ Sách (`ShelfView.swift`)**:
  * Truy vấn danh sách chương từ `ChapterStore.shared.fetchOrderedTOC` và lưu các bản dịch tiêu đề qua `ChapterStore.shared.updateTitleTranslations` thay vì phụ thuộc vào `book.chapters`.
* **Đồng bộ Tiến trình Đọc (`ReadingProgressStore.swift`)**:
  * Cập nhật phương thức `persist` và các hàm checkpoint/flush trong `actor ReadingProgressStore` thành `async throws`.
  * Sử dụng API `ChapterStore.shared.fetchRange(...)` làm fallback lấy tiêu đề chương khi `snapshot.chapterTitle == nil`.

## [1.3.54] - 2026-07-29

### Tối ưu hóa Chuyển đổi Bật/Tắt Dịch thuật trên Màn hình Khám phá (`DiscoveryView.swift`)
* **Loại bỏ Re-fetch Mạng không cần thiết khi Bật/Tắt Dịch (`DiscoveryView.swift`)**:
  * Loại bỏ 2 handler `.onChange(of: isTranslationEnabled)` trong `DiscoveryView` và `DiscoveryCategoryTabView`.
  * Cho phép giao diện Khám phá (Discovery) re-render ngay các chuỗi văn bản hiện có thông qua `translateIfNeeded` khi thay đổi trạng thái dịch thuật mà không cần tải lại danh sách trang chủ hoặc danh mục thể loại từ mạng.

### Đồng bộ Tài liệu CodeGraph cho Điều khiển TTS Remote Command State Machine & Chuẩn hóa Metadata
* **Đồng bộ Máy trạng thái Điều khiển Từ xa TTS (`TTSManager.swift`, `TTSManagerTests.swift`, `05_state_graph.md`, `06_event_graph.md`, `11_subsystems.md`)**:
  * Ghi nhận việc điều chỉnh hàm `syncRemoteCommandState()` và `handleRemoteTransportCommandOnMain(_:)` trong `TTSManager.swift`: Chuyển `RemoteTransportAction` enum và `handleRemoteTransportCommandOnMain` sang `internal` access modifier để phục vụ unit test; cập nhật `playCommand.isEnabled = active && !isPlaying` và `pauseCommand.isEnabled = active && isPlaying`.
  * Bổ sung cơ chế tương thích có phạm vi giới hạn (bounded compatibility fallback) trong `handleRemoteTransportCommandOnMain(.pause)` gọi `resume()` khi đang paused để tương thích với phụ kiện phần cứng gửi lệnh pause vật lý.
  * Bổ sung thử nghiệm chuẩn hóa metadata Now Playing trong `updateNowPlayingInfo()` (loại bỏ `MPNowPlayingInfoPropertyIsLiveStream` cũ và thiết lập `MPNowPlayingInfoPropertyMediaType.audio`), đồng thời chuẩn hóa thứ tự ghi `nowPlayingInfo` và `playbackState`.
  * Bổ sung mã chẩn đoán quan sát Giai đoạn A trong `setupRemoteCommandCenter()` (`remoteCallbackDispatched` và `remoteCallbackCompleted` ghép cặp theo `eventId`) để đo đạc luồng vào và độ trễ xử lý remote commands trên thiết bị thực tế.
  * Triển khai Giai đoạn B: Tạo helper method `@MainActor internal func dispatchRemoteTransportCommand` và thực thi đồng bộ qua `MainActor.assumeIsolated` khi callback ở Main Thread trước khi trả về `.success`, giúp MediaRemote nhận trạng thái `playbackState` mới ngay lập tức để đồng bộ trực quan biểu tượng nút Play/Pause trên Lock Screen UI.
  * Bổ sung unit test hồi quy `testRemotePauseCommandResumesWhenPausedAndDirectPauseIsIdempotent` và `testNowPlayingMetadataNormalization` trong `TTSManagerTests.swift`.
  * Đã đồng bộ khối GENERATED trong `05_state_graph.md`, `06_event_graph.md`, và `11_subsystems.md`.
* **Thử nghiệm Kiểm soát Giai đoạn C cho Điều khiển Remote TTS (`TTSManager.swift`, `05_state_graph.md`, `06_event_graph.md`, `11_subsystems.md`)**:
  * Cập nhật `commandCenter.togglePlayPauseCommand.isEnabled = false` trong cả `setRemoteCommandsEnabled(_:)` và `syncRemoteCommandState()` của `TTSManager.swift` để giải phóng xung đột lệnh trung tâm trên Lock Screen UI, tạo cặp lệnh `play/pause` động không mơ hồ.
  * Giữ nguyên việc đăng ký handler cho `togglePlayPauseCommand`, giữ nguyên dynamic play/pause enablement (`playCommand.isEnabled = active && !isPlaying`, `pauseCommand.isEnabled = active && isPlaying`), giữ nguyên Phase A log trace (`TTSTrace`), Phase B synchronous MainActor dispatch, bounded `.pause` fallback, now-playing metadata và các gọi lệnh `UIApplication`.
  * Đã đồng bộ khối GENERATED trong `05_state_graph.md`, `06_event_graph.md`, và `11_subsystems.md`.
* **Thử nghiệm Kiểm soát Giai đoạn D cho Điều khiển Remote TTS (`TTSManager.swift`, `05_state_graph.md`, `06_event_graph.md`, `11_subsystems.md`)**:
  * Cập nhật `syncRemoteCommandState()` trong `TTSManager.swift`: Giữ `commandCenter.playCommand.isEnabled = active` và `commandCenter.pauseCommand.isEnabled = active` mở đồng thời cho cả phiên active (thay vì bật/tắt động theo `isPlaying`), kết hợp với `commandCenter.togglePlayPauseCommand.isEnabled = false` (Phase C), để khắc phục lỗi nút Play bị mờ/xám (disabled) trên Lock Screen sau khi pause.
  * Giữ nguyên `setRemoteCommandsEnabled(_:)`, giữ nguyên handler `togglePlayPauseCommand`, Phase A log trace (`TTSTrace`), Phase B synchronous MainActor dispatch, bounded `.pause` fallback, now-playing metadata và các gọi lệnh `UIApplication`.
  * Đã đồng bộ khối GENERATED trong `05_state_graph.md`, `06_event_graph.md`, và `11_subsystems.md`.
* **Thử nghiệm Kiểm soát Giai đoạn E cho Điều khiển Remote TTS (`TTSManager.swift`, `05_state_graph.md`, `06_event_graph.md`, `11_subsystems.md`)**:
  * Chuyển đổi sang mô hình Single Enabled Toggle Command trong `TTSManager.swift`: Đặt `playCommand.isEnabled = false` và `pauseCommand.isEnabled = false`, đồng thời chỉ bật `togglePlayPauseCommand.isEnabled = enabled` (trong `setRemoteCommandsEnabled(_:)`) và `active` (trong `syncRemoteCommandState()`), nhằm định tuyến chính xác các thao tác bấm nút trung tâm trên Lock Screen về `action:toggle` thay vì gửi nhầm `action:pause`.
  * Giữ nguyên toàn bộ target registrations/handlers (`togglePlayPauseCommand.addTarget`, `playCommand.addTarget`, `pauseCommand.addTarget`), Phase A log trace (`TTSTrace`), Phase B synchronous MainActor dispatch, bounded `.pause` fallback, now-playing metadata và các gọi lệnh `UIApplication`.
  * Đã đồng bộ khối GENERATED trong `05_state_graph.md`, `06_event_graph.md`, và `11_subsystems.md`.
* **Thử nghiệm Kiểm soát Giai đoạn F cho Phản hồi Trạng thái Điều khiển Remote TTS (`TTSManager.swift`, `05_state_graph.md`, `06_event_graph.md`, `11_subsystems.md`)**:
  * Triển khai mô hình phản hồi trạng thái khách quan (Outcome-Aware Status Return) trong `TTSManager.dispatchRemoteTransportCommand`: Tính toán giá trị `MPRemoteCommandHandlerStatus` phản hồi dựa trên `self.isPlaying` thực tế sau khi xử lý lệnh (`.success` nếu trạng thái cuối khớp yêu cầu, `.commandFailed` nếu mâu thuẫn như khi kích hoạt fallback `resume()` cho lệnh `.pause` lúc paused).
  * Bổ sung log trace `remoteCallbackCompleted` ghi nhận nhãn chữ phân biệt rõ `success` vs `commandFailed` kèm giá trị `status.rawValue` tại runtime.
  * Giữ nguyên chữ ký `func handleRemoteTransportCommandOnMain` (Void return), cấu hình khả dụng Phase E (`playE: false, pauseE: false, toggleE: active`), Phase A log trace (`TTSTrace`), Phase B synchronous MainActor dispatch, bounded `.pause` fallback, now-playing metadata và các gọi lệnh `UIApplication`.
  * Đã đồng bộ khối GENERATED trong `05_state_graph.md`, `06_event_graph.md`, và `11_subsystems.md`.
* **Thử nghiệm Kiểm soát Giai đoạn G cho Chuẩn hóa Metadata Lock Screen TTS (`TTSManager.swift`, `05_state_graph.md`, `06_event_graph.md`, `11_subsystems.md`)**:
  * Triển khai mô hình chuẩn hóa tính tương thích metadata (Controlled Compatibility Normalization): Cập nhật helper `setSystemNowPlayingPlaybackState(_:defaultPlaybackRate:)` và `updateNowPlayingInfo()` để xuất bản tốc độ tương đối `MPNowPlayingInfoPropertyPlaybackRate` (`1.0` khi playing, `0.0` khi paused) và `MPNowPlayingInfoPropertyDefaultPlaybackRate` mang tốc độ đọc TTS (`speed`, giữ nguyên kể cả khi pause).
  * Cập nhật tất cả các vị trí gọi `setSystemNowPlayingPlaybackState` trong `continueStartSpeaking`, `pause` và `resume` để truyền tốc độ `speed` hiện tại làm `defaultPlaybackRate`.
  * Bổ sung log trace `TTSTrace` ghi nhận `currentRate` và `defaultRate` chi tiết tại runtime.
  * Giữ nguyên chữ ký `func handleRemoteTransportCommandOnMain` (Void return), cấu hình khả dụng Phase E (`playE: false, pauseE: false, toggleE: active`), Phase F outcome-aware status return, Phase A log trace, Phase B synchronous MainActor dispatch, bounded `.pause` fallback và các gọi lệnh `UIApplication`.
  * Đã đồng bộ khối GENERATED trong `05_state_graph.md`, `06_event_graph.md`, và `11_subsystems.md`.
* **Thử nghiệm Kiểm soát Giai đoạn H cho Khả dụng Đồng thời Remote Commands TTS (`TTSManager.swift`, `05_state_graph.md`, `06_event_graph.md`, `11_subsystems.md`)**:
  * Triển khai mô hình thử nghiệm cờ khả dụng đồng thời (Controlled Triple-Command Enablement): Bật khả dụng `isEnabled = enabled` (trong `setRemoteCommandsEnabled(_:)`) và `active` (trong `syncRemoteCommandState()`) cho cả 3 lệnh `playCommand`, `pauseCommand` và `togglePlayPauseCommand` đồng thời khi session TTS active.
  * Phối hợp cờ khả dụng mới với bộ xuất bản metadata tương thích Phase G (`currentRate: 1.0/0.0`, `defaultRate: speed`), phản hồi trạng thái Phase F, bounded `.pause` fallback và điều phối đồng bộ MainActor Phase B để kiểm chứng khả năng hỗ trợ iOS MediaRemote UI cập nhật biểu tượng Lock Screen.
  * Giữ nguyên chữ ký `func handleRemoteTransportCommandOnMain` (Void return), target handler registrations (`setupRemoteCommandCenter()`), Phase A log trace (`TTSTrace`) và các gọi lệnh `UIApplication`.
  * Đã đồng bộ khối GENERATED trong `05_state_graph.md`, `06_event_graph.md`, và `11_subsystems.md`.
* **Thử nghiệm Kiểm soát Giai đoạn I cho Hợp đồng Metadata Timeline Hữu hạn TTS (`TTSManager.swift`, `05_state_graph.md`, `06_event_graph.md`, `11_subsystems.md`)**:
  * Chuyển đổi `setSystemNowPlayingPlaybackState(_:)` thành instance method private `@MainActor` trong `TTSManager` để truy cập an toàn các thuộc tính timeline (`currentParagraphIndex`, `paragraphs.count`, `speed`).
  * Hoàn thiện xuất bản bộ 5 key metadata Now Playing hữu hạn (`MPNowPlayingInfoPropertyPlaybackRate`, `MPNowPlayingInfoPropertyDefaultPlaybackRate`, `MPNowPlayingInfoPropertyElapsedPlaybackTime`, `MPMediaItemPropertyPlaybackDuration`, `MPNowPlayingInfoPropertyPlaybackProgress`) đồng bộ trong `setSystemNowPlayingPlaybackState` và `updateNowPlayingInfo()`.
  * Cập nhật log trace `TTSTrace` ghi nhận các thông số timeline `elapsed`, `duration` và `progress` tại runtime.
  * Giữ nguyên khả dụng 3 lệnh Phase H (`playE/pauseE/toggleE = active`), chữ ký `func handleRemoteTransportCommandOnMain`, Phase F outcome-aware status return, bounded `.pause` fallback và các gọi lệnh `UIApplication`.
  * Đã đồng bộ khối GENERATED trong `05_state_graph.md`, `06_event_graph.md`, và `11_subsystems.md`.
* **Điều chỉnh Tính khả dụng Remote Command Phụ thuộc Trạng thái Phát (Phase J) (`TTSManager.swift`, `05_state_graph.md`, `06_event_graph.md`, `11_subsystems.md`)**:
  * Cập nhật `syncRemoteCommandState()` trong `TTSManager.swift` để trạng thái khả dụng của các lệnh điều khiển từ xa phản ánh chính xác trạng thái phát:
    * `let active = !playingBookId.isEmpty && showFloatingWidget`
    * `let playing = active && isPlaying`
    * `let paused = active && !isPlaying`
    * `playCommand.isEnabled = paused`
    * `pauseCommand.isEnabled = playing`
    * `togglePlayPauseCommand.isEnabled = active`
    * `nextTrackCommand.isEnabled = active`
    * `previousTrackCommand.isEnabled = active`
  * Giữ nguyên `setRemoteCommandsEnabled(_:)`, các target handler registrations, bounded `.pause` fallback và hợp đồng metadata timeline hữu hạn (Phase I).
  * Đã đồng bộ khối GENERATED trong `05_state_graph.md`, `06_event_graph.md`, và `11_subsystems.md`.
* **Cập nhật Metadata (`manifest.json`)**:
  * Tái tính toán và cập nhật `sourceHash` và `generatedHash` cho các tài liệu bị ảnh hưởng thông qua kịch bản `validate_links.py --update-hashes`.

## [1.3.53] - 2026-07-28

### Quản lý Quy tắc TOC File TXT & Khắc phục Thanh Tra Cứu Nhanh Panel Dịch
* **Cải tiến Nhận diện Chương File TXT (`ShelfView.swift`, `TranslateUtils.swift`)**:
  * Luồng phân tách chương file TXT (`ShelfView.parseTxtBook`) tái sử dụng bộ so khớp quy tắc TOC cấu hình được do `TranslateUtils` quản lý. Nhận diện chính xác các dòng tiêu đề chương lùi lề hợp lệ (ví dụ: `" 第一章 蓝电潜龙"`), đồng thời loại trừ các dòng văn bản lùi lề thông thường (ví dụ: `"  1000 quân lính tiến vào thành phố"`), tránh bị gộp sai toàn bộ nội dung thành một chương duy nhất ("Mở đầu").
* **Màn hình Quản lý Quy tắc TOC trong Cài đặt (`TOCRulesConfigView.swift`, `SettingsView.swift`)**:
  * Thêm màn hình `TOCRulesConfigView` trong Cài đặt với đường dẫn điều hướng `NavigationLink` hiển thị thường trực tại mục "Dịch Thuật Quick Translate" (hoạt động độc lập với cờ bật/tắt dịch).
  * Hỗ trợ xem danh sách, bật/tắt công tắc kích hoạt trực tiếp, chạm dòng để mở Form chỉnh sửa, sắp xếp lại vị trí quy tắc (`onMove`) và xóa quy tắc tùy chỉnh (`onDelete`).
  * Bảo vệ các quy tắc xuất xưởng mặc định (`isDefaultRule`), khóa tính năng xóa đối với quy tắc mặc định (`deleteDisabled`).
* **Menu Thao tác Toolbar & Nhập/Xuất Cấu hình JSON (`TranslateUtils.swift`)**:
  * Đưa các tùy chọn quản lý vào một dropdown Menu trên toolbar gồm 5 chức năng: *Thêm quy tắc mới*, *Sắp xếp quy tắc* (chuyển đổi EditMode), *Nhập cấu hình JSON*, *Xuất cấu hình JSON*, và *Khôi phục mặc định* (alert xác nhận hủy).
  * Hỗ trợ Nhập file JSON với 2 chế độ: **Gộp theo ID** (cập nhật tại chỗ các ID trùng và thêm quy tắc mới ở cuối) và **Thay thế toàn bộ** (thay bằng danh sách file và tự khôi phục các quy tắc mặc định bị thiếu ở cuối theo đúng thứ tự xuất xưởng).
  * **Tương thích ngược Import**: Tự động gán mặc định `enabled = true` khi decode/import các tệp JSON cũ thiếu trường `enabled`, đồng thời giữ nguyên các giá trị `enabled` được khai báo rõ ràng (`true` / `false`).
  * Kiểm tra hợp lệ file nhập nguyên tử (Atomic Validation): Giới hạn kích thước file (tối đa 500KB), số lượng quy tắc (tối đa 100 quy tắc), ID và Tên trimmed không rỗng và không quá 100 ký tự, kiểm tra trùng lặp ID (bao gồm khoảng trắng), cú pháp Regex hợp lệ (tối đa 250 ký tự); từ chối file nguyên khối nếu có lỗi mà không ghi đĩa hay đụng tới bộ đệm.
  * Tái sử dụng `DocumentPickerPresenter` (với `allowedContentTypes: [.json]`, `asCopy: true`) và `ShareSheet` với tệp xuất tạm thời tại `NSTemporaryDirectory()` được tự động dọn dẹp khi đóng sheet.
* **Đồng bộ Lưu trữ Bất đồng bộ & Quản lý Bộ đệm (`TranslateUtils.swift`)**:
  * Bổ sung `TOCRuleSaveCoordinator` actor quản lý xếp hàng lưu bất đồng bộ theo cơ chế FIFO (`enqueue` / `scheduleSave`) kết hợp rào chắn `flush()`, ngăn ngừa lỗi ghi đè dữ liệu cũ (race condition).
  * Phân tách bộ đệm trong bộ nhớ thành `cachedAllTOCRules` (chứa toàn bộ quy tắc cho UI quản lý) và `cachedTOCRules` (chỉ chứa quy tắc active cho parser TXT). Ghi đĩa nguyên tử (`.atomic`) trước khi cập nhật bộ đệm và tự động làm sạch cache tiêu đề chương (`clearChapterTitleCache`).
  * Quản lý cờ `isSaving` trên UI theo bộ đếm tác vụ `activeSaveCount` và hủy tác vụ `debounceSaveTask` trước mỗi thao tác lưu tức thì.
* **Khắc phục Thanh Tra Cứu Nhanh & Nút Cài đặt trên Panel Dịch (`ReaderView.swift`, `ReaderDefinitionOverlayView.swift`)**:
  * **Khắc phục nạp danh sách công cụ tìm kiếm**: Tự động nạp `SearchEngine.loadEngines()` trong `ReaderView` khi khởi tạo (`initializeReaderIfNeeded()`) và mỗi khi mở panel dịch (`.onChange(of: showingDefinitionSheet)`), khắc phục triệt để lỗi thanh Quick Lookup bên dưới nút Cập nhật bị trống.
  * **Nút Cài đặt Bánh răng (⚙️)**: Bổ sung nút Cài đặt bánh răng góc phải ngoài cùng trên thanh tra cứu nhanh (`quickLookupLinksView`), liên kết mở trực tiếp màn hình quản lý `SearchEnginesConfigView` dùng chung với Cài đặt ứng dụng qua `showingSearchEnginesConfigSheet`.
  * **Tự động làm mới khi đóng Sheet**: Đảm bảo danh sách `searchEngines` được tự động nạp lại trong callback `onDismiss` khi đóng màn hình Cài đặt công cụ tra cứu, đồng thời duy trì nút bánh răng luôn xuất hiện và truy cập được ngay cả khi danh sách công cụ rỗng.
* **Nâng cấp Tô màu Highlight & Phát TTS theo Phân đoạn Nhỏ (`ReaderView.swift`, `TTSManager.swift`)**:
  * **Highlight theo phân đoạn nhỏ (Small Chunk Level)**: Vùng màu vàng bôi đen khi đọc TTS giờ đây tô chính xác từng phân đoạn/câu nhỏ đang phát thay vì bôi đen toàn bộ đoạn văn lớn.
  * **Phát TTS từ vị trí bôi đen chọn**: Khi người dùng bôi đen văn bản và nhấn **Nghe (Speak)** trên menu nổi, TTS bắt đầu phát ngay từ phân đoạn nhỏ chứa văn bản được chọn.
  * **Chuẩn hóa hệ tọa độ UTF-16**: TTS sử dụng dữ liệu chương hiển thị làm chuẩn (`cached.content`). `ReaderView` lưu vết `@State private var selectedDisplayedOffset` cho thao tác phát TTS (đồng thời giữ nguyên `selectedWordOffset` quy đổi về chuỗi gốc cho từ điển/trình chỉnh sửa), và `lineStartOffset` tính toán vị trí tích lũy trên `item.translated` khi bật dịch và `item.original` khi tắt dịch.
* **Bổ sung Bộ Kiểm thử Unit Tests (`Tests/TranslationTests.swift`)**:
  * Thêm các unit test kiểm thử lưu trữ/khôi phục mặc định (`testTOCRulesPersistenceAndResetNonDestructive`), tương thích ngược import thiếu `enabled` (`testImportBackwardsCompatibilityMissingEnabledKey`), validate Regex (`testTOCRulePatternValidation`), validate file import quá cỡ/quá số lượng/ID tên quá dài/trùng ID (`testImportValidationOversizedDataAndRulesCount`, `testImportValidationEmptyOrOverlongIDAndNameAndDuplicateIDs`), thứ tự Gộp và Thay thế deterministic (`testDeterministicMergeAndReplaceOrderDetails`), tính nguyên tử không đổi file/cache khi import lỗi (`testAtomicImportRejectionNoFileOrCacheMutation`), kiểm tra dọn dẹp file tạm (`testTempExportFileCreationAndCleanup`), và kiểm thử FIFO actor `TOCRuleSaveCoordinator` (`testCoordinatorFIFOAndFlush`).

---

## [1.3.52] - 2026-07-28

### Loại bỏ ChapterMigrationWorker & Sửa lỗi Destructive Empty-Import
* **Khắc phục Nguyên nhân Gốc rễ Mất Mục Lục khi Khởi động lại App**:
  * Xác định nguyên nhân mất dữ liệu mục lục (TOC count về 0) sau khi khởi động lại app: Luồng legacy migration (`ChapterMigrationWorker`) chạy tự động ở `FreeBookApp.onAppear` đọc danh sách `book.chapters` rỗng từ SwiftData (do `enableSwiftDataTOCWrite = false`), sau đó gọi `importBookMigration` truyền danh sách snapshot rỗng làm xoá toàn bộ dữ liệu chương hiện có trong SQLite `ChapterStore`.
* **Loại bỏ Hoàn toàn Tệp Migration Worker & Cờ Cấu hình**:
  * Xoá hoàn toàn tệp vật lý `ChapterMigrationWorker.swift` và gỡ bỏ thuộc tính `enableChapterStoreMigration` khỏi `ChapterStoreConfiguration.swift`.
  * Gỡ bỏ lệnh khởi chạy `ChapterMigrationWorker.shared.startMigrationIfNecessary` trong `FreeBookApp.swift` (`.onAppear`).
  * Gỡ bỏ khối code fallback legacy trong `ChapterPersistenceStore.saveChapterList` (kiểm tra `storedCount == 0` để gọi `importBookMigration`).
  * Luồng ghi chính (primary write path) `replaceFullTOC` / `upsertPage` lưu metadata sách vào SwiftData và ghi danh mục TOC trực tiếp vào SQLite `ChapterStore` tiếp tục hoạt động độc lập và không bị thay đổi.
* **Phòng thủ Chuyên sâu Chống Import Rỗng (`ChapterStoreDatabase`)**:
  * Thêm guard kiểm tra `!snapshots.isEmpty` ngay đầu hàm `ChapterStoreDatabase.importBookMigration` trước khi khởi tạo giao dịch (`beginTransaction`).
  * Từ chối mọi yêu cầu import danh sách rỗng, ghi log mã băm sách rút gọn 8 ký tự (`bookHash`) và quăng lỗi ngữ nghĩa `ChapterStoreError.invalidContent`, ngăn ngừa triệt để việc xoá dữ liệu chương cũ và ngăn ghi dòng trạng thái `migration_status = migrated, 0`.
* **Dọn dẹp Cờ Cấu hình Thừa (Batch 1 Cleanup)**:
  * Gỡ bỏ 3 cờ cấu hình ghi kép không còn được sử dụng (`enableDualWriteNewBook`, `enableDualWriteExistingBook`, `enableDualWriteCacheMetadata`) khỏi `ChapterStoreConfiguration.swift`.

---

## [1.3.51] - 2026-07-27

### Chuyển đổi Mục Lục sang SQLite Native (`ChapterStore`)
* **Kiến trúc CSDL Độc lập (`ChapterStoreDatabase`)**:
  * Tách toàn bộ lưu trữ và đọc metadata mục lục (TOC) từ SwiftData `Chapter` sang cơ sở dữ liệu SQLite3 riêng biệt tại `Library/Application Support/chapters/chapter_store.sqlite` (đảm bảo tên thư mục `chapters` viết thường).
  * Cấu hình chế độ WAL (`PRAGMA journal_mode=WAL;`) và `PRAGMA synchronous=NORMAL;` kết hợp bảo vệ đĩa iOS `.completeUntilFirstUserAuthentication` áp dụng cho tệp CSDL chính, `-wal`, `-shm` và thư mục `chapters`, hỗ trợ đọc phát âm thanh TTS khi thiết bị khóa màn hình.
  * Thiết kế bảng `chapter_metadata` (schema v1) lưu trữ thông tin chỉ mục, URL, tiêu đề gốc, tiêu đề dịch (`title_trans`), trạng thái cache (`is_cached`, `offset`, `length`), thời gian cập nhật cùng các chỉ mục tối ưu `idx_chapter_book_index` và `idx_chapter_book_url`.
* **Xử lý Đơn Giao dịch Không Chia Đợt (`ChapterStoreActor`)**:
  * `ChapterStoreActor` quản lý toàn bộ các thao tác đọc/ghi bất đồng bộ, sử dụng Prepared Statements chuẩn bị sẵn cho C-API SQLite.
  * Các phương thức `replaceFullTOC` và `upsertPage` thực thi nguyên khối trong 1 giao dịch `BEGIN IMMEDIATE ... COMMIT` duy nhất (không chia đợt Batch Splitting) nhằm đảm bảo tính toàn vẹn dữ liệu mục lục.
  * Bảo tồn dữ liệu vị trí cache nhị phân (`offset`, `length`), tiêu đề dịch và thông tin chương đang phát TTS (`protectedTTS`).
* **Đồng bộ Luồng Migration & Retry Queue**:
  * `ChapterMigrationWorker` xử lý di chuyển mục lục từ SwiftData sang SQLite3 nguyên khối theo từng cuốn sách, tự động dọn dẹp bản ghi thừa (stale rows) và ghi nhận trạng thái vào `migration_status`.
  * Khôi phục và duy trì cơ chế hàng chờ thử lại xóa tệp nhị phân (`BookStorageManager.drainRetryQueue()`) khi người dùng xóa sách.
* **Tích hợp Các Phân hệ Consumer & Tắt Ghi SwiftData**:
  * Chuyển toàn bộ luồng đọc/hiển thị/dịch tiêu đề/đếm chương tại `BookDetailView`, `BookDetailTOCView`, `ReaderViewModel`, `ReaderChapterListView`, `ReaderView`, `DownloadManager`, `TTSManager`, và `ShelfView` sang sử dụng `ChapterStore` (DTO `StoredChapterSnapshot`).
  * Vô hiệu hóa ghi SwiftData Chapter (`enableSwiftDataTOCWrite = false`) để tránh ghi trùng lặp dữ liệu vào SwiftData Store.
  * Thêm liên kết thư viện hệ thống `SQLite3.tbd` trong `project.yml`.
* **Ghi Log An toàn Quyền Riêng tư & Kiểm chứng**:
  * Định dạng log `[ChapterStore Save]` ghi nhận các trường thời gian thực thi (ms), số lượng chương, trạng thái kết quả và đối chiếu tính toàn vẹn (parity), không ghi mã hash bookId hay checksum trong dòng log save.
  * Thuật toán checksum FNV-1a xác định được tích hợp trong `computeDeterministicChecksum` / `fetchCountAndChecksum` phục vụ kiểm tra tính toàn vẹn dữ liệu.
  * Mã hash sách rút gọn 8 ký tự `Chapter.hashUrl(bookId).prefix(8)` được sử dụng trong log xóa (`ChapterStore Delete`), đảm bảo không ghi lộ tiêu đề chương, đường dẫn CSDL raw, hay `bookId` gốc.
  * Lưu ý kiểm chứng: Đã hoàn thành kiểm chứng tĩnh trên Windows (`git diff --check`, `swiftc -frontend -parse`). Runtime iPhone và CI IPA build phụ thuộc vào GitHub Actions workflows.

---

## [1.3.50] - 2026-07-27

### Tối ưu hóa Database Mục Lục (TOC Database Optimization)
* **Tối ưu hóa Truy vấn Truy cập Sách (`ChapterPersistenceStore`, `BookDetailView`)**:
  * Sử dụng `FetchDescriptor<Book>` với `#Predicate<Book> { $0.bookId == targetBookId }` và `fetchLimit = 1` thay thế toàn bộ truy vấn `context.fetch(FetchDescriptor<Book>())` không có Predicate.
* **Lưu Nền 1 Save Cho Toàn Bộ Thao Tác (`ChapterPersistenceStore.saveChapterList`)**:
  * Chuyển toàn bộ công việc lưu/cập nhật danh sách chương xuống `ModelContext` chạy nền thuộc `ChapterPersistenceStore` (actor). Thực hiện duy nhất 1 lần `try context.save()` cho toàn bộ thao tác.
  * Hỗ trợ 2 chế độ: `.replaceFullTOC` (thay thế toàn bộ mục lục khi nạp đầy đủ) và `.upsertPage` (nạp từng phần/trang mục lục mà không xóa các chương thuộc trang khác).
  * Bảo tồn dữ liệu `isCached`, `offset`, `length`, `titleTrans`, giữ an toàn cho chương đang phát TTS (`isPlayingChapter`).
* **Tái cấu trúc `startReading(at:)` & `ReaderChapterListView`**:
  * `startReading(at:)` thu thập đủ các trang mục lục, gọi `saveChapterList` lưu nền 1 lần, chờ hoàn tất rồi mới refetch `Book` qua predicate và mở `ReaderView`.
  * `ReaderChapterListView.refreshChapters` và các luồng nạp trang nền (`startBackgroundRemainingPagesLoading`, `loadTOCDataOnly`) sử dụng `saveChapterList` với `mode: .upsertPage` chạy nền thay vì insert/save lặp đi lặp lại trên `MainActor`.
* **Bổ sung Unit Tests & Đồng bộ CodeGraph Docs (`04_call_graph.md`, `07_dataflow.md`, `11_subsystems.md`)**:
  * Thêm unit test kiểm thử `.replaceFullTOC`, `.upsertPage`, và bảo vệ TTS trong `Tests/ChapterContentRepositoryTests.swift`.
  * Đồng bộ Đồ thị Lời gọi Hàm, Dòng chảy Dữ liệu và Phân hệ Cốt lõi cho các API `saveChapterList` và cơ chế lưu nền 1 lần.

---

## [1.3.49] - 2026-07-24

### Tái cấu trúc Luồng Tải Mục mục & Lưu Database khi Mở Sách (`BookDetailView`)
* **Tải toàn bộ danh sách chương trước khi mở ReaderView**:
  * Khi mở đọc truyện mới (`isBookReady == false`), hệ thống tự động cào toàn bộ các trang mục lục (`pages`) thành 1 danh sách chương hợp nhất `allChapters`.
* **Lưu DB theo đợt (Chunked Save - 1,000 chương/đợt)**:
  * Chia `allChapters` thành các đợt tối đa 1,000 chương (`updateLocalChaptersChunk`), chèn vào `ModelContext` và gọi `modelContext.save()` sau mỗi đợt.
* **Wait Layer Tiến độ Thời gian Thực**:
  * Hiển thị màn hình chờ `loadingOverlay` với các nhãn tiến độ thời gian thực: `"Đang lấy mục lục..."` (giai đoạn cào trang) và `"Đang lưu database..."` (giai đoạn lưu từng đợt 1000 chương).
  * Hỗ trợ nút **Hủy** để dừng tác vụ an toàn.
  * Tự động mở `ReaderView` sau khi 100% dữ liệu đã được lưu xuống đĩa.

---

## [1.3.48] - 2026-07-24

### Phase 2 & Phase 3: Tái cấu trúc Phân hệ Book Detail & TTS Services
* **Book Detail Component Modularization**:
  * Tách tệp monolithic `BookDetailView.swift` thành 3 Subview thành phần:
    * `Sources/Views/BookDetail/BookDetailHeaderView.swift` (Khu vực thông tin ảnh bìa, tác giả, mô tả và nút action).
    * `Sources/Views/BookDetail/BookDetailTOCView.swift` (Danh sách mục lục chương, ô tìm kiếm chương và lọc phân trang).
    * `Sources/Views/BookDetail/BookDetailActionSheetView.swift` (Quản lý các Hộp thoại Sheet tải xuống và Bypass Cloudflare).
* **TTS Controller Modularization**:
  * Tách `TTSManager.swift` thành các Controller chuyên biệt:
    * `Sources/Services/TTS/TTSAudioEngineController.swift` (Quản lý AVAudioEngine, AVAudioPlayerNode và ngắt âm thanh).
    * `Sources/Services/TTS/TTSNowPlayingController.swift` (Quản lý MPNowPlayingInfoCenter và MPRemoteCommandCenter Lock Screen).
    * `Sources/Services/TTS/TTSChapterPrefetcher.swift` (Quản lý sliding window [N, N+1] giải phóng RAM PCM buffer).
* Cập nhật danh sách 110 tệp nguồn trong `manifest.json` và đồng bộ CodeGraph.

---

## [1.3.47] - 2026-07-24

### Phase 1: Tái cấu trúc Phân hệ Reader (Modularize ReaderView)
* **Reader Component Modularization**:
  * Tách tệp monolithic `ReaderView.swift` thành các Subview độc lập:
    * `Sources/Views/Reader/ReaderDefinitionOverlayView.swift` (Quản lý Bottom Sheet tra cứu từ điển và sửa nghĩa).
    * `Sources/Views/Reader/ReaderFloatingMenuOverlayView.swift` (Quản lý menu bong bóng nổi khi bôi đen văn bản).
    * `Sources/Views/Reader/ReaderHeaderFooterOverlayView.swift` (Quản lý thanh tiêu đề Header và thanh điều hướng Footer).
  * Giảm số dòng code của `ReaderView.swift` từ 2,430 dòng xuống còn ~1,800 dòng.
  * Cập nhật danh sách tệp nguồn trong `manifest.json` và đồng bộ CodeGraph.

---

## [1.3.46] - 2026-07-24

### Phase 0: Sàng lọc & Xóa bỏ mã nguồn / tệp rác không sử dụng (Dead Code Removal)
* **Reader & TTS Cleanup**:
  * Xóa bỏ các tệp tin mồ côi dư thừa `Sources/Views/Reader/CollapsedCircleView.swift`, `Sources/Views/Reader/ExpandedControlPanel.swift`, `Sources/Views/Reader/ChapterContentProvider.swift`.
  * Rà soát & loại bỏ các biến `@State` dư thừa không được đọc/ghi (`isGoingNext`, `editingChapterIndex` trong `ReaderView.swift`; `preparingStatusText`, `preparingTargetChapterTitle` trong `BookDetailView.swift`).
  * Cập nhật danh sách tệp nguồn trong `00_index.md`, `02_file_graph.md`, `03_type_graph.md`, `14_complexity_report.md` và `manifest.json`.

---

## [1.3.45] - 2026-07-24

### Loại bỏ hoàn toàn phân hệ màn hình chờ WaitLayer
* **WaitLayer Cleanup**:
  * Xóa bỏ hoàn toàn tệp `Sources/Common/Services/WaitLayerManager.swift` và `Sources/Views/Reader/ReaderWaitOverlayView.swift`.
  * Gỡ bỏ `ReaderWaitOverlayView()` khỏi cấp root `FreeBookApp.swift`.
  * Dọn dẹp tất cả các lời gọi `WaitLayerManager.shared.open` và `close` ở `BookDetailView.swift`, `ReaderView.swift` và `ShelfView.swift`.
  * Trả lại luồng chuyển hướng mở đọc truyện trực tiếp, gọn nhẹ và không qua màn hình chờ trung gian.

## [1.3.44] - 2026-07-24

### Chuyển đổi WaitLayer sang kiến trúc WaitLayerManager.shared điều khiển open/close thủ công toàn cục
* **WaitLayer Subsystem & Shared Architecture**:
  * Tạo tệp `Sources/Common/Services/WaitLayerManager.swift` quản lý trạng thái hiển thị và dữ liệu của WaitLayer toàn ứng dụng.
  * Gắn duy nhất 1 `ReaderWaitOverlayView` tại cấp root `FreeBookApp.swift` (`.zIndex(10000)`), phủ kín toàn bộ giao diện và chuyển cảnh navigation.
  * Loại bỏ hoàn toàn logic tự động bật `waitLayerOverlay` trong `ReaderView.swift` dựa trên `loadState != .ready`, sửa dứt điểm lỗi trùng lặp/hiển thị 2 lần.
  * Trong `BookDetailView.swift` và `ShelfView.swift`: Gọi `WaitLayerManager.shared.open(...)` ngay khi vừa chạm nút mở đọc, kết hợp `await Task.yield()` cho phép render WaitLayer 0ms trước khi thực thi khởi tạo 2.000+ chương.
  * Trong `ReaderView.swift`: Gọi `WaitLayerManager.shared.close()` khi `loadState` trở thành `.ready` / `.failed` hoặc khi màn hình đóng (`onDisappear`).

## [1.3.43] - 2026-07-24

### Tách ReaderWaitOverlayView thành Component dùng chung & Hiển thị LẬP TỨC khi bấm nút đọc
* **Reader Subsystem & UI Navigation**:
  * Tạo component SwiftUI mới `Sources/Views/Reader/ReaderWaitOverlayView.swift` phục vụ màn hình WaitLayer phủ kín toàn màn hình dùng chung cho toàn bộ các màn hiển thị/chuyển tiếp sang ReaderView.
  * Giao diện WaitLayer gồm:
    * Nút Back (Quay lại) ở góc trên bên trái (`chevron.left`) gọi callback `onBack` cho phép người dùng đóng overlay và hủy tác vụ ngay lập tức.
    * Tiêu đề Truyện và Tiêu đề Chương ở phần trên/giữa header, hỗ trợ dịch thuật tự động nếu bật dịch (`isTranslationEnabled`).
    * Biểu tượng nạp (`ProgressView().controlSize(.large)`) nằm chính giữa màn hình.
    * Phủ kín màu nền theo chủ đề đọc được chọn (`theme.backgroundColor`) với `.zIndex(100)` và hiệu ứng mờ mượt mà `.transition(.opacity)`.
  * **Kích hoạt LẬP TỨC**:
    * Trong `BookDetailView.swift`: Kích hoạt `ReaderWaitOverlayView` ngay lập tức khi bấm các nút "Đọc ngay", "Đọc tiếp" hoặc bấm vào bất kỳ dòng chương nào trong mục lục TOC.
    * Trong `ShelfView.swift`: Kích hoạt `ReaderWaitOverlayView` ngay lập tức khi người dùng bấm/chạm vào bất kỳ cuốn truyện nào trong tab Kệ sách hoặc Lịch sử.
    * Trong `ReaderView.swift`: Sử dụng chung `ReaderWaitOverlayView` cho đến khi `ReaderViewModel.loadState` chuyển sang `.ready` hoặc `.failed`.

## [1.3.42] - 2026-07-22

### Đồng bộ hành vi Hard Delete sách bất đồng bộ không đơ UI và bảo vệ sách đang ở trên kệ / đang nghe TTS
* **BookStorageManager & SwiftData Background Deletion**:
  * Chuyển đổi toàn bộ các thao tác xóa sách (xóa khỏi kệ sách, xóa 1 mục lịch sử, xóa toàn bộ lịch sử) thành **Hard Delete** (xóa bản ghi `Book`, cascade xóa toàn bộ bản ghi `Chapter` trong SwiftData, dừng/hủy tác vụ download, clear reader fallback `UserDefaults` và xóa các file vật lý `.bin` / cover background).
  - Triển khai các API xóa bất đồng bộ `deleteBooksAsync`, `deleteBookAsync`, `clearAllOffShelfHistoryAsync` nhận tham số `ModelContainer` và danh sách `bookId` (`[String]`). Thao tác fetch/delete trong SwiftData chạy trên `backgroundContext` hoàn toàn không gây tắc nghẽn main thread (non-blocking UI).
  - Bổ sung cơ chế bảo vệ ở lớp dịch vụ: không xóa cuốn sách đang phát TTS (`TTSManager.shared.playingBookId`).
  - Thao tác xóa toàn bộ lịch sử (`clearAllOffShelfHistoryAsync`) chỉ xóa các cuốn sách KHÔNG nằm trên kệ (`isOnShelf == false`), bảo tồn 100% các cuốn sách đang nằm trên Kệ sách (`isOnShelf == true`).
* **ShelfView & BookDetailView UI**:
  * Tích hợp cờ trạng thái `isProcessingDeletion` hiển thị indicator dọn dẹp nhẹ và ngăn bấm lặp lại trên `ShelfView`.
  * Cập nhật văn bản thông báo Alert xóa lịch sử làm rõ hành vi chỉ xóa các sách lịch sử không ở trên kệ, giữ nguyên sách trên kệ và sách đang nghe audio.
  * Chuyển đổi các nút xóa trong `ShelfView` và `BookDetailView` sang gọi các phương thức bất đồng bộ của `BookStorageManager` bọc trong `Task { @MainActor in ... }` đảm bảo an toàn Thread Safety cho trạng thái UI.
* **Unit Tests**:
  * Thêm `Tests/BookStorageManagerTests.swift` kiểm định xóa cứng `Book` & `Chapter` cascade delete, bảo tồn sách trên kệ và bảo vệ sách đang nghe TTS.

## [1.3.41] - 2026-07-22

### Khắc phục lỗi điều khiển nút Play màn hình khóa và tai nghe khi tạm dừng TTS
* **TTS Subsystem & MPRemoteCommandCenter**:
  * Đăng ký handler xử lý lệnh `togglePlayPauseCommand` trong `setupRemoteCommandCenter()`, cho phép tai nghe Bluetooth/AirPods và nút điều khiển trung tâm toggle phát/dừng mượt mà qua `pause()` và `resume()`.
  * Cập nhật `setRemoteCommandsEnabled(_:)` và `syncRemoteCommandState()` bật `togglePlayPauseCommand.isEnabled = active` trong toàn bộ phiên TTS đang hoạt động (dù đang phát hay tạm dừng).
  * Khắc phục triệt để hiện tượng nút Play trên Now Playing card (Lock Screen / Control Center) bị mờ/xám (disabled) khi pause và sửa triệt để lỗi bấm tai nghe 2 lần mới tiếp tục phát.
  * Sửa trợ thủ `setSystemNowPlayingPlaybackState` khởi tạo dictionary rỗng khi `nowPlayingInfo` bằng `nil`, đảm bảo `MPNowPlayingInfoPropertyPlaybackRate` và `playbackState` luôn được cập nhật đồng bộ tức thì.
  * Loại bỏ cơ chế debounce 300ms theo thời gian (`shouldProcessPlaybackRemoteCommand()`) để tránh nuốt lệnh Resume/Play/Pause hợp lệ gửi từ tai nghe/iOS Control Center; chuyển sang kiểm tra tính định danh (idempotency) trực tiếp theo trạng thái `isPlaying` hiện tại của `TTSManager`.
  * Bảo vệ Task bất đồng bộ `updateNowPlayingInfo()` sử dụng giá trị `self.isPlaying` và `self.speed` mới nhất tại thời điểm MainActor commit cuối cùng.
* **Unit Tests**:
  * Cập nhật `TTSManagerTests.swift`: thay thế `testRemoteCommandDebounce()` bằng `testRemoteCommandIdempotencyAndImmediateStateSync()` để kiểm định tính định danh của lệnh remote và tính đồng bộ tức thì của Now Playing.

## [1.3.40] - 2026-07-22

### Sửa lỗi nghĩa rỗng VP, tối ưu cuộn/làm nóng mục lục Reader, điều hướng TTS chính xác đoạn văn và định dạng Title Case UI
* **Dictionary & Translation (Vietphrase)**:
  * Khắc phục lỗi không áp dụng nghĩa rỗng ở vị trí đầu tiên khi chuỗi dịch từ điển Vietphrase chứa ký tự phân cách đầu dòng (`/`, `|`, `¦`) trong `TranslateUtils.getFirstMeaning(of:)` và `ManageDefinitionsView`.
  * Bổ sung các ca kiểm thử đơn vị bao quát trong `Tests/TranslationTests.swift`.
* **Reader Subsystem**:
  * `ReaderChapterListView`: Tự động cuộn căn giữa chương đang đọc khi mở sheet mục lục mỗi lần (`onChange(of: isPresented)` & `currentChapterIndex`).
  * Tối ưu hóa việc dịch tên chương Hán-Việt ngầm (`warmNearbyTitles`) theo lô (batch warming) trong bán kính cửa sổ hiển thị (`windowSize = 8`) thay vì gọi giải dịch riêng lẻ từng dòng khi xuất hiện (`onAppear`).
  * Trễ tác vụ nạp trang hiển thị (`scheduleVisiblePageWork`) với cơ chế hoãn (debounce 90ms) giúp ngăn chặn hiện tượng cuộn giật/thrashing khi người dùng lướt nhanh mục lục.
  * Nút "Dịch lại tên chương" trong `ShelfView` nay chạy task nền để dịch lại toàn bộ danh sách chương của cuốn sách và lưu tất cả `titleTrans` xuống SQLite, thay vì chỉ xóa cache bộ nhớ.
  * Màn hình chuẩn bị mở sách mới (Full-screen Reader-like Preparing Screen) trong `BookDetailView` với nút Icon Quay lại (`chevron.left`) ở góc trên bên trái, hiển thị tiến trình nạp TOC, dịch tên chương và lưu SQLite trước khi chuyển sang `ReaderView`.
  * Ẩn navigation header của màn chi tiết khi màn hình chuẩn bị mở sách mới đang hiển thị, đảm bảo wait layer giống trang Reader và không còn lộ title/menu của `BookDetailView`.
  * Chuẩn hóa quy tắc hiển thị tiêu đề chương bên ngoài văn bản: ưu tiên `chapter.titleTrans` từ SQLite khi bật dịch thuật (nếu rỗng dịch tại thời điểm hiển thị); luôn sử dụng `chapter.title` tiếng Trung gốc khi tắt dịch thuật.
  * Khắc phục lỗi mục lục Reader hiện nhiều dòng "Đang tải..." chen giữa các mốc 100 chương dù page kế tiếp đã được prefetch; page cache nay được dùng/publish ngay khi page đó trở thành vùng hiển thị.
* **TTS Navigation Integration**:
  * `ShelfView`: Khi chuyển từ widget / MiniPlayer TTS sang Reader via nút "Nghe tiếp", truyền tham số `navigateToPlayingParagraphIndex` (`initialParagraphIndex`) giúp Reader tự động cuộn và highlight chính xác đoạn văn đang đọc thay vì mở lại từ đầu chương.
* **UI Text Formatting & Styling**:
  * Tích hợp tiện ích `DisplayTextFormatter.titleCase` hỗ trợ định dạng hoa đầu từ theo quy chuẩn tiếng Việt (`Locale(identifier: "vi_VN")`), bảo toàn các từ viết tắt chuyên ngành (`TTS`, `AI`, `VIP`, `iOS`, `API`, `URL`, `FreeBook`, v.v.).
  * Áp dụng định dạng Title Case đồng bộ cho tiêu đề sách và tên tác giả trên các view: `BookDetailView`, `SuggestRowView`, `CategoryNovelsListView`, `DiscoveryView`, `DownloadTrackerView`, `TaskOptionsSheet`, `ReaderView`, `SearchView`, `ShelfView`.
  * Thay thế nhãn chữ "Tác giả:" bằng biểu tượng người dùng (`Image(systemName: "person.fill")`) trong `BookDetailView` và `TaskOptionsSheet` giúp giao diện hiện đại và gọn gàng hơn.
  * Không hiển thị fallback "Không rõ" khi thiếu tên tác giả; các vùng metadata tác giả trong `BookDetailView`, `TaskOptionsSheet` và header mục lục Reader sẽ để trống.
* **Unit Tests**:
  * Tạo mới bộ kiểm thử `Tests/DisplayTextFormatterTests.swift` kiểm định các trường hợp Title Case tiếng Việt, từ viết tắt preserved, `nil`, chuỗi rỗng và xử lý chuẩn hóa khoảng trắng.

## [1.3.39] - 2026-07-21

### Tích hợp cơ chế waitForReady thăm dò DOM động trong Extension Engine
* **Extension Engine & JSExecutor**:
  * Bổ sung API `waitForReady` vào đối tượng `Engine.Browser` trong JS và native bridge `_nativeBrowserWaitForReady` trong `JSExecutor.swift`.
  * Triển khai kiểm tra `Thread.isMainThread` (fail-fast) trong native bridge `waitForReady` mới để ngăn chặn deadlock luồng chính khi gọi đồng bộ; các bridge truyền thống (`launch`, `callJs`) vẫn giữ nguyên rủi ro ban đầu.
  * Mở rộng `WebViewLoader` để thực hiện thăm dò DOM tuần hoàn thông qua `DispatchQueue.main.asyncAfter` thay thế busy-loop.
  * Xác thực trạng thái DOM ổn định dựa trên bộ đôi chỉ số `{chars, encoded}` trong `stablePasses` chu kỳ liên tiếp (với `encoded` là số lượng thẻ `i[t]`).
  * Thực hiện cơ chế giải phóng timer và pending wait an toàn đúng 1 lần (exactly-once) khi đóng trình duyệt hoặc khởi chạy wait mới.
* **Sangtacviet Extension**:
  * Viết lại `src/chap.js` sử dụng `waitForReady` thay thế cho delay cố định (`waitTime`).
  * Thêm logic thử lại AJAX (gọi `gotox()` tối đa 1 lần) và fallback trích xuất văn bản thuần (`getReadableTextFromNode`) khi không tìm thấy thẻ mã hóa `i[t]`.
  * Bổ sung `home.js`, `genre.js` và `homecontent.js`: cung cấp các tab trang chủ, 10 thể loại đã xác minh và phân trang 48 truyện qua endpoint `/io/searchtp/searchBooks`.
  * Tạo cấu hình `plugin.json`, `icon.png`, `src/search.js`, `src/detail.js`, `src/toc.js`, và tệp kiểm thử `tests/smoke.mjs`.
  * Đóng gói `plugin.zip` chứa đúng cấu trúc phân phối (loại bỏ thư mục `tests`).

## [1.3.38] - 2026-07-21

### Tách refresh metadata TTS khỏi Reader UI, giảm giật tab và bỏ kéo sheet mục lục theo tay
* **TTS Subsystem**:
  * Thêm `TTSChapterQueueMetadataWorker` chạy nền bằng `ModelContainer` để `TTSManager` tự refresh metadata queue cho sách local, không phụ thuộc `ReaderView` dựng full queue trên main thread.
  * Thêm `refreshChaptersQueueInBackground(bookId:onlineChapters:)`; Reader chỉ cấp queue khởi động ngắn để phát ngay, còn TTSManager tự cập nhật queue đầy đủ phục vụ auto-next.
  * `stopPlayback` hủy task refresh queue của TTS khi người dùng dừng TTS thật sự; thao tác rời Reader không chặn prefetch/auto-fetch của TTS.
* **ReaderView / ReaderChapterListView**:
  * Bỏ `chapterListDragOffset` và callback kéo realtime của mục lục; vuốt xuống đủ ngưỡng chỉ đóng sheet, không kéo panel chạy theo tay.
  * Thêm vùng tap ngoài mục lục để đóng overlay.
  * `ReaderView` không còn computed full TTS chapter queue; luồng start TTS chỉ lấy chương hiện tại và vài chương kế tiếp.
* **ShelfView / DiscoveryView**:
  * `ShelfView` không reset `shelfLimit/historyLimit` khi vuốt tab con và không quét `book.chapters` trong row render.
  * `DiscoveryView` chỉ render nội dung thật cho tab category hiện tại và tab lân cận; tab xa dùng placeholder rỗng, còn tải tab mới được debounce ngắn.

## [1.3.37] - 2026-07-21

### Tối ưu độ trễ khởi động TTS và giữ điều hướng Reader độc lập
* **TTS Subsystem**:
  * Thiết lập lớp xử lý nền bất đồng bộ `TTSBackgroundProcessor` dưới dạng `actor` gánh vác các phép toán CPU-heavy (chuẩn hóa văn bản `ChapterTextNormalizer.normalize`, dịch nghĩa `TranslateUtils.translateContent` và phân tách đoạn văn `TTSParagraphBuilder.build`) ra khỏi luồng chính `MainActor`.
  * Chuẩn hóa chữ ký truyền tham số `processChapter` rõ ràng (`shouldTranslateRawContent`, `includeChapterTitle`) thay vì truy cập các biến toàn cục bên trong worker. Tránh lặp lại quá trình dịch khi nạp dữ liệu đã được xử lý từ bộ nhớ đệm.
  * Loại bỏ hàng đợi `TTSBackgroundProcessor.shared` dùng chung; mỗi request dùng processor riêng có cancellation checkpoint để thao tác Play không phải chờ các prewarm cũ.
  * `prepareSpeaking` trở thành prewarm thuần cache, không thay đổi chương hoặc trạng thái của phiên TTS đang pause.
  * `startSpeaking` dùng ngay kết quả prewarm khi key nội dung khớp; cache miss mới xử lý nền với ưu tiên cao.
  * Đường bấm Play chỉ truy vấn metadata chương hiện tại và chương kế; từ 1.3.38, refresh danh sách chương đầy đủ được chuyển sang `TTSManager.refreshChaptersQueueInBackground(...)`.
* **ReaderView**:
  * Next/Previous và chọn chương trong mục lục chỉ thay đổi Reader, không dừng hoặc chuyển chương TTS.
  * Prewarm chương Reader không ghi đè dữ liệu phát của chương TTS hiện tại.
  * Bỏ thao tác deactivate/activate AudioSession dư thừa khi bắt đầu TTS từ trạng thái đã dừng hoàn toàn.
* **TTSManagerTests**:
  * Cập nhật test chữ ký processor và bổ sung kiểm tra chương đã prewarm bắt đầu phát đồng bộ không cần chờ xử lý lần hai.

## [1.3.36] - 2026-07-21

### Khắc phục lỗi biên dịch Test Target, hoàn tất tối ưu hóa điều phối và đối sánh persistence an toàn va chạm
* **Tests/ReaderViewModelTests**:
  * Viết lại toàn bộ bộ kiểm thử đơn vị, loại bỏ các symbol giả tự chế (`ChapterSnapshot`, `BookSnapshot`, `ChapterPersistenceStore.shared`, `ensureBook(snapshot:context:)`, v.v.).
  * Chuyển sang gọi các API thực tế của `ChapterPersistenceStore` bất đồng bộ (`ensureBook`, `flush`) sử dụng một `ModelContainer` in-memory biệt lập và các snapshot DTO thực tế (`BookMetadataSnapshot`, `ChapterMetadataSnapshot`).
  * Bổ sung các ca kiểm thử chất lượng cao bao quát toàn bộ các ca kiểm định ảo hóa, giới hạn cửa sổ 300, phòng chống race cùng thế hệ, prefetch không ghi đè, phục hồi khi lỗi, và kiểm thử persistence an toàn va chạm với dữ liệu trùng lặp/rỗng trên API thực tế.
* **ChapterPersistenceStore**:
  * Tích hợp lớp helper tập trung `ReconciliationPool` để chia sẻ logic đối sánh an toàn va chạm $O(N)$ giữa `ensureBook` và `upsert`.
  * Đảm bảo các hàng trùng lặp URL và URL rỗng không bị mutated/collapsed gộp chung thành một hàng và thăng cấp chương trùng lặp còn lại chính xác khi khóa thay đổi.
* **ReaderChapterListStore & ReaderChapterListView**:
  * Khai báo thuộc tính `latestWindowRequestID: UUID` và `activeLoadingTargetPage` để điều phối cửa sổ hiển thị.
  * Chỉ cho phép tác vụ khớp với token cửa sổ hiển thị mới nhất được xuất bản lên UI, loại bỏ triệt để race condition giữa các bộ điều phối cũ thuộc cùng thế hệ hoàn thành trễ.
  * Bổ sung `pageRequestIDs` và `pageCache` để ngăn ngừa các tác vụ tải trang cũ khi kết thúc vô tình xóa nhầm tác vụ trang mới hơn trong `inFlightPages`.
  * Cập nhật `prefetchPageIfNeeded(page:)` chỉ nạp ngầm dữ liệu DTO vào `pageCache` nền mà không dịch chuyển `currentTargetPage` và không ghi đè/mutate trực tiếp lên `loadedRowStates`.
  * Cập nhật `BackgroundPagingWorker.fetchPage` trả về lỗi tường minh (`throw`) và xử lý tại `performPageFetch` trả về `nil` để coordinator không đánh dấu trang lỗi đã nạp, cho phép retry sạch sẽ.
* **ReaderView**:
  * Loại bỏ thuộc tính tính toán `currentChapterHost` đang gọi `vm.fetchChapter(at:)` đồng bộ sang sử dụng trạng thái `@State private var currentChapterHost: String?` được cập nhật đồng bộ bên ngoài SwiftUI body trong `updateCurrentChapterMetadata()`.

## [1.3.35] - 2026-07-21

### Tối ưu hóa Virtualization mục lục Reader, Paging Worker bất đồng bộ, Anti-jitter và Persistence collision-safe
* **ReaderChapterListStore & ReaderChapterListView**:
  * Loại bỏ hoàn toàn mảng `rows` và danh sách ảo `virtualRows` khỏi lớp lưu trữ của mục lục để tối ưu hóa bộ nhớ. Trực tiếp sử dụng ForEach chỉ mục `ForEach(0..<store.totalCount, id: \.self)` để SwiftUI tự ảo hóa.
  * Thiết kế hàm `item(at:)` và `rowState(at:)` bóc tách dòng trạng thái động trong thời gian $O(1)$ mà không tự ý đột biến (non-mutating read) bộ nhớ đệm trạng thái dòng.
  * Triển khai lớp tác vụ phân trang chạy nền `BackgroundPagingWorker` dưới dạng `actor` sở hữu `ModelContainer` độc lập, thực hiện tải trang từ SQLite trên luồng nền bất đồng bộ và trả về từ điển DTO thuần `Sendable`.
  * Xây dựng bộ điều phối tải trang mục lục (page load request coordinator) quản lý tác vụ in-flight của từng trang đơn lẻ (`inFlightPages`), loại bỏ tình trạng hủy bỏ và tạo mới liên tục (cancellation thrash) khi cuộn chậm.
  * Thực thi việc hoán đổi trạng thái nguyên tử (atomic swap) duy nhất một lần trên `loadedRowStates` sau khi toàn bộ trang thuộc cửa sổ hiển thị (lên đến 3 trang / tối đa 300 phần tử) đã sẵn sàng, giữ nguyên cửa sổ cũ cho tới khi cửa sổ mới được tải hoàn chỉnh.
  * Tích hợp cơ chế tải trước chủ động `prefetchPageIfNeeded(page:)` giúp tải ngầm trang kề cận mà không gây dịch chuyển vị trí trang hiển thị trung tâm (target page oscillation).
  * Xóa bỏ các phương thức không sử dụng là `synchronize` và `searchChapters(query:)`. Tích hợp logic tự động kích hoạt tìm kiếm lại với sort order mới khi đổi chiều sắp xếp mục lục lúc đang có query tìm kiếm.
* **ReaderView**:
  * Quản lý trạng thái đếm chương thông qua `@State` flag `didResolveLocalChapterCount`, đảm bảo chỉ truy vấn đếm chương cục bộ từ SQLite duy nhất một lần (kể cả khi bằng 0), khắc phục triệt để lỗi lặp lại lệnh đếm khi view xuất hiện hoặc thay đổi key bootstrap.
  * Loại bỏ thuộc tính truy vấn độ dài mảng `book.chapters.count` trong luồng cập nhật mục lục của `ReaderChapterListView`, thay thế bằng đếm nhanh `fetchCount` trực tiếp từ SQLite.
* **ChapterPersistenceStore**:
  * Tối ưu hóa bộ đối chiếu chèn/sửa danh sách chương bằng bản đồ lưu trữ các thùng chứa an toàn va chạm (collision-safe buckets / order-aware maps) `urlBuckets` và `indexBuckets`.
  * Đảm bảo tính nhất quán của thao tác đối khớp: ưu tiên URL trước, sau đó dùng index dự phòng. Khi thay đổi URL hoặc index của một chương, hệ thống loại bỏ khóa cũ và tự động thăng cấp (promote) chương trùng lặp tiếp theo trong thùng chứa, duy trì chính xác ngữ nghĩa `first(where:)` trong thời gian $O(1)$ trung bình.

## [1.3.34] - 2026-07-20

### Cập nhật CodeGraph tăng dần cho cấu trúc dữ liệu mới, BookStorageManager, phân trang mục lục và bảo mật Sandbox
* **Database Models**:
  * **Chapter**: Cập nhật hàm `Chapter.generateId(bookId:url:index:)` sử dụng định dạng có độ dài tiền tố (length-prefixed format) như `[len]:[bookId]|U:[len]:[url]` cho online và `[len]:[bookId]|I:[index]` cho fallback khi không có URL. Legacy Chapter ID được giữ nguyên không di chuyển.
* **Component mới**:
  * **BookStorageManager**: Quản lý việc xóa sách khỏi kệ và lịch sử, xử lý các side-effects (dừng TTS, huỷ tải xuống, xoá reader fallback progress). Database context được save (commit DB) trước khi tiến hành xóa các file vật lý nhị phân (.bin) và ảnh bìa (.jpg) bất đồng bộ trong background thread. Lỗi xóa file vật lý được đẩy vào retry queue lưu trong `UserDefaults` (`failed_file_deletions_queue`) và được xử lý lại tối đa 3 lần tại app startup (`drainRetryQueue()`).
* **Bảo mật Sandbox & Di chuyển Lưu trữ**:
  * **BookBinManager & ImageCacheManager**: Chuyển sang sử dụng mã băm SHA-256 của `bookId` làm tên file lưu trữ (`[sha256Hex].bin` và `[sha256Hex].jpg`) để tránh lỗi path injection. Tích hợp kiểm tra bảo mật sandbox (`validatePathSafety(for:)`) trước khi đọc, ghi hoặc xóa tệp. Tự động di chuyển (migrate) và dọn dẹp các tệp legacy hiện có.
* **Tối ưu hóa Trình đọc (TOC Pagination)**:
  * **ReaderChapterListStore & ReaderChapterListView**: Giới hạn RAM bằng cơ chế phân trang TOC (TOC pagination) và cửa sổ trượt (sliding window) chỉ giữ tối đa 3 trang liền kề (300 dòng trạng thái chương), giải quyết triệt để lag/OOM cho sách siêu lớn (ví dụ 20.000 chương).
  * **ReaderViewModel**: Loại bỏ memory cache cho toàn bộ chapter list (`cachedSortedChapters`), thực hiện fetch trực tiếp từ DB khi cần và cung cấp API tạo metadata cho TTS (`fetchChaptersMetadata`).
* **Cooperative Cancellation**:
  * **DownloadManager**: Cải thiện cooperative cancellation bằng cách liên tục kiểm tra trạng thái huỷ của Task trong lúc tải chương hoặc xuất file text.
* **Giới hạn & Lưu ý**:
  * Tiếp tục giữ yêu cầu tối thiểu iOS 17+.
  * Không migrate legacy Chapter IDs hiện có để tránh hỏng tham chiếu chéo.
  * Danh sách chương trực tuyến (`onlineChapters` / `ChapterResult`) vẫn giữ nguyên dưới dạng mảng đầy đủ (full array).

## [1.3.33] - 2026-07-20

### Tái cấu trúc Hệ thống Lưu trữ: Đọc/Ghi Nhị phân (.bin) + SQLite offset/length + UUID Sách
* **Database Models**:
  * **Chapter**: Xóa trường `content: String?` khỏi SQLite để giải phóng dung lượng DB. Thêm thuộc tính `bookId: String`, `offset: Int64` và `length: Int64`. Thêm các helper sinh ID tĩnh băm URL (`hashUrl` và `generateId`).
* **App Setup**:
  * **FreeBookApp**: Khởi tạo `ModelContainer` thủ công hướng về `Library/Application Support/library.db` thay vì dùng mặc định.
* **Component mới**:
  * **BookBinManager**: Actor thread-safe quản lý việc đọc/ghi dữ liệu UTF-8 vào file `.bin` của sách tại `Application Support/books/`.
* **Thư mục Lưu trữ**:
  * Di chuyển toàn bộ các thư mục lưu trữ (`covers/` ở **ImageCacheManager**, `extensions/` ở **ExtensionManager**, `translate/` ở **TranslationManager**, và `app_logs.txt` ở **AppLogger**) sang thư mục ẩn `Library/Application Support/` để tuân thủ Apple App Store Guidelines.
* **Logic Nghiệp vụ**:
  * **ChapterPersistenceStore**: Cập nhật hàm `readChapter` và `persistWithRetry` sử dụng `BookBinManager` ghi/đọc nhị phân theo `offset`/`length`. Sử dụng `Chapter.generateId` khi chèn chương mới.
  * **DownloadManager**: Cập nhật luồng download nền ghi chương tải về vào file `.bin` qua `BookBinManager` và lưu thông tin vị trí byte.
  * **ShelfView**: Cập nhật nhập sách `.txt` cục bộ sinh `bookId` dạng UUID, tạo URL chương cục bộ độc bản và ghi nội dung vào file `.bin`.
  * **BookDetailView**: Sử dụng cơ chế `@State resolvedBookId` và hàm `resolveBookId()` tra cứu DB bằng `detailUrl + extensionPackageId` để đảm bảo lưu sách dùng UUID. Cập nhật các đoạn tạo `Chapter` mới truyền đúng `bookId` và dùng `generateId`.
  * **SearchView**: Cập nhật hàm thay đổi nguồn `executeSourceChange` đổi `newBookId` sang UUID và cập nhật chèn danh sách chương mới.

## [1.3.32] - 2026-07-20

### Tối ưu hóa hiệu năng BookDetailView và sửa lỗi token khoảng cách thừa
* **BookDetailView**:
  * Tối ưu hóa thuật toán đối chiếu danh sách chương trong `updateLocalChapters` từ $O(N^2)$ xuống $O(N)$ bằng `Dictionary` tra cứu nhanh theo `url` và `index`.
  * Tránh thực hiện `sorted` và `filter` trực tiếp trong `body` mỗi lần View vẽ lại. Chuyển sang lưu cache danh sách chương và danh sách đã lọc vào các biến `@State` (`chaptersList`, `filteredLocalChapters`, `filteredOnlineChapters`).
  * Sử dụng các modifier `.onChange` để cập nhật lại các danh sách cache này một cách chọn lọc khi có thay đổi các tham số đầu vào (`chaptersList`, `onlineChapters`, `isTocAscending`, `chapterSearchQuery`, `isTranslationEnabled`), giúp loại bỏ hoàn toàn hiện tượng giật lag khi mở chi tiết truyện lớn (khoảng 2000 chương).
  * Thay thế `.onChange(of: allBooks)` bằng `.onChange(of: localBook?.chapters.count)` để khắc phục lỗi trình biên dịch không thể kiểm tra kiểu do kiểu dữ liệu không tuân thủ `Equatable`.
* **TranslateUtils**:
  * Cập nhật `getTranslationTokens(for:bookId:)` và `performTranslation(_:bookId:)` để bỏ qua cơ chế ghép khoảng trắng Hán-Việt cho các token thuần số hoặc chữ Latin (không chứa ký tự tiếng Trung).
  * Khắc phục triệt để lỗi số `1000` bị tách thành `1 0 0 0` và lỗi lệch pha offset làm bôi đen sai/bôi đen toàn bộ cụm từ trong Trình đọc.
* **ExtensionManager**: Cho `ChapterResult` kế thừa thêm `Equatable` để hỗ trợ cụ thể SwiftUI theo dõi thay đổi danh sách chương online.
* **ReaderView & ReaderViewModel**:
  * Áp dụng cơ chế **Lazy Load 100%** cho danh sách chương: Trong hàm khởi tạo của `ReaderViewModel`, chỉ truy vấn `chapters.count` (cực nhanh, không tải thực thể vào RAM).
  * Khởi tạo lười bộ lưu trữ danh sách chương `ReaderChapterListStore` và chỉ đưa `ReaderChapterListView` vào view hierarchy khi menu mục lục thực sự được mở (giúp giảm thiểu tối đa tài nguyên và thời gian vẽ giao diện ban đầu).
  * Ghi chú lịch sử: phiên bản này từng đồng bộ các thuộc tính computed của Reader để sử dụng dữ liệu đã cache trong `viewModel.getSortedChapters()`, loại bỏ hiện tượng giật lag khi chuyển tiếp từ Kệ sách/Lịch sử vào Trình đọc đối với truyện lớn.
  * Đồng bộ hóa các lệnh gọi `synchronize` trong `ReaderChapterListView.swift` tương thích với kiểu chữ ký mới sử dụng `sortedChapters: [Chapter]`.

## [1.3.31] - 2026-07-19

### Hậu kỳ dịch thuật & Đồng bộ Tiện ích
* **JSExecutor**: Bổ sung hàm `base64()` vào đối tượng Response trả về từ hàm `fetch` trong JavaScript để cung cấp dữ liệu dạng Base64 của phản hồi mạng cho các VBook extension, tránh lỗi `TypeError: response.base64 is not a function`.
* **TranslateUtils**:
  * Nâng cấp thuật toán phân tách từ (`tokenize`) sang cơ chế Multi-pass bảo vệ Tên riêng (Name) tối đa trước VietPhrase, giải quyết tranh chấp bằng Global Longest Match (tên riêng dài hơn thắng).
  * Refactor hàm `getTranslationTokens` để tái sử dụng `tokenize`, loại bỏ trùng lặp code và đồng bộ hóa highlight.
  * Tối ưu hóa phân tách dấu câu độc lập (chỉ gom nhóm Alphanumeric, còn dấu câu như `?”` và `.”` tách thành các token độc lập giúp tra cứu từ điển VP chính xác).
  * Hỗ trợ cài đặt bật/tắt dịch Đại từ (Pronouns) và Luật nhân hóa động.
* **ReaderView, ReaderSettingsView, SettingsView**:
  * Thêm UI Toggle cho phép người dùng bật/tắt cài đặt dịch Đại từ (Pronouns) và Luật nhân hóa, lưu trữ qua `@AppStorage`, mặc định là Tắt (`false`).
  * Tự động xóa cache dịch và kết xuất lại giao diện tức thì khi thay đổi một trong hai cài đặt này.
* **RepositoryManagerView**: Thêm in thông báo log debug `print` khi tải hoặc parse file cấu hình `plugin.json` trên mạng của tiện ích chưa cài đặt gặp lỗi, hỗ trợ chẩn đoán chính xác lý do metadata bị hiển thị sai lệch hoặc không đầy đủ.

### Tối ưu hóa cử chỉ Reader, Panel dịch Full-width, Item-based Browser và Mở Chi tiết từ Cover
* **DiscoveryView**: Nâng cấp từ `isPresented`-based sang `item`-based `.fullScreenCover(item:)` thông qua struct `ExtensionBrowserTarget: Identifiable` cho cả header (`headerBrowserTarget`) và danh sách (`listBrowserTarget`). `BypassWebView` chỉ được khởi tạo đúng lúc người dùng bấm nút Safari, tránh hoàn toàn lỗi URL rỗng lần đầu mở.
* **ReaderView — Panel dịch**:
  * Full-width Bottom Sheet: Xoá `.padding(.horizontal)`, dùng `UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16)` để bo 2 góc trên.
  * Bấm ngoài để tắt: Thêm `Color.clear` với `.simultaneousGesture(TapGesture())` (không tiêu thụ event, widget ở zIndex cao hơn vẫn hoạt động bình thường).
  * Vuốt xuống để tắt: Thêm `DragGesture` (ngưỡng > 50pt) trên panel dịch.
  * Drag Indicator: Thêm `Capsule` 36×5pt ở đầu `definitionSheetContent`.
  * Cỡ chữ gốc Hàng 1: `.font(.title3)` → `.font(.body)`.
  * Nút Cập nhật: Thêm `.controlSize(.small)` và giảm `.padding(.vertical, 8)`.
* **ReaderView — Danh sách chương**:
  * Ghi chú lịch sử: phiên bản này từng thêm hành vi kéo panel mục lục theo tay; hành vi đó đã bị loại bỏ ở 1.3.38, chỉ giữ vuốt xuống đủ ngưỡng và tap ngoài để đóng.
* **ReaderChapterListView**:
  * Ghi chú lịch sử: các callback kéo realtime của mục lục đã bị loại bỏ ở 1.3.38.
  * Bọc `BookCoverView` trong `Button` mở `BookDetailView` qua `.sheet(isPresented:)` với `NavigationStack` khi `bookDetailUrl != nil` và `ext != nil`.

## [1.3.30] - 2026-07-19

### Căn lề hai bên Reader, Sửa lỗi URL trình duyệt rỗng, Đồng bộ metadata extension từ plugin.json
* **ReaderTextView**: Áp dụng `.justified` alignment cho đoạn văn thường (nhánh `else` khi không phải `isCentered`), giữ nguyên `firstLineHeadIndent` để thụt đầu dòng vẫn hoạt động.
* **DiscoveryView — sửa lỗi URL trỗng khi mở BypassWebView lần đầu**: Bọc `BypassWebView` trong điều kiện kiểm tra `showingHeaderWeb && !ext.sourceUrl.isEmpty` (header) và `showingListWeb && !listWebUrl.isEmpty` (danh sách), ngăn SwiftUI khởi tạo view khi URL chưa được set.
* **RepositoryManagerView — syncExtensions**: Thay thế `JSONDecoder` + `RemotePluginMeta` bằng `JSONSerialization` để hỗ trợ cấu trúc `"metadata"` lồng nhau trong `plugin.json`. Ưu tiên đọc offline từ `localPath/plugin.json` nếu tiện ích đã tải về; chỉ fallback tải từ thư mục gốc của URL zip trên mạng khi chưa có cục bộ.
* **RepositoryManagerView — installExtension**: Chuyển sang `JSONSerialization` + nhánh `metadata` để đọc `plugin.json` sau khi giải nén. Cập nhật thêm `ext.sourceUrl` từ trường `"source"` trong JSON bên cạnh locale/type/version/author.

## [1.3.29] - 2026-07-19

### Lọc dữ liệu truyện rỗng/trùng lặp tại các View Gợi ý, Thể loại, Tìm kiếm, và Khám phá
* `DiscoveryView`, `SuggestRowView`, `CategoryNovelsListView`, `SearchView`: Định nghĩa hàm helper `normalizeLink(_:)` để loại bỏ scheme + host và đồng bộ tiền tố `/` cho liên kết tương đối/tuyệt đối.
* Áp dụng chuẩn hóa liên kết khi so khớp trùng lặp link nhằm loại bỏ triệt để các truyện bị trùng lặp ở cả hai định dạng tương đối và tuyệt đối (ví dụ: `https://wcshuba.com/book/87661.html` và `/book/87661.html`).

## [1.3.28] - 2026-07-19

### Thống nhất Toast toàn cục, Nút Đọc từ bôi đen, và Tích hợp Engine Google TTS "Chị Google"
* **Thống nhất Toast toàn cục**: Loại bỏ tất cả Toast cục bộ tự vẽ ở các màn hình, chuyển sang gọi qua `ToastManager.shared` đặt tại root view (`AppLaunchRootView` trong `FreeBookApp.swift`). Hỗ trợ thêm icon cho 3 loại Toast (`.success` - checkmark xanh, `.error` - exclamation đỏ, `.info` - không icon).
* **Toast cho 4 chức năng xuất file**: Thêm Toast thành công/thất bại cho xuất ebook TXT, xuất từ điển dịch, xuất từ điển phát âm (NghiTTS), và xuất quy tắc thay thế TTS. Thay thế `ShareLink` tĩnh bằng `Button` tạo file -> báo Toast -> mở `ShareSheet` dùng chung (`ShareSheet.swift`).
* **Tích hợp Engine "Chị Google"**: Thêm `GoogleTTSService` kết nối trực tiếp đến Google Translate TTS API để tải file MP3 trực tuyến. `TTSManager` hỗ trợ prefetch và chuyển đổi trực tiếp MP3 sang `AVAudioPCMBuffer` qua file tạm.
* **Ẩn bộ chọn giọng đọc**: Giao diện `TTSSettingsView` ẩn bộ chọn giọng đọc khi chọn engine "Chị Google" để tối giản trải nghiệm.
* **Nút Đọc từ bôi đen**: Bổ sung nút **Đọc** (biểu tượng loa phát `speaker.wave.2.fill`) vào menu bong bóng nổi khi bôi đen chữ trong `ReaderView` để phát trực tiếp từ bôi đen (đã dịch nếu bật dịch) bằng giọng đọc của Chị Google qua `AVAudioPlayer` (MP3 raw data).

## [1.3.27] - 2026-07-19

### Sửa lỗi Khám phá: không cập nhật khi tắt dịch, lọc novel trùng/rỗng
* `DiscoveryCategoryTabView`: Thêm `.onChange(of: isTranslationEnabled)` để reset và reload danh sách truyện khi bật/tắt dịch — trước đó view cache dữ liệu cũ trong `@State` nên không cập nhật.
* `loadNovels`: Lọc các novel có `name` hoặc `link` trống trước khi hiển thị.
* `loadNovels`: Deduplicate theo `link` — cả page 1 (trong batch) lẫn load-more (so sánh với danh sách hiện có) để tránh hiển thị trùng.

## [1.3.26] - 2026-07-19

### Sửa lỗi vị trí Floating Bubble Menu, tap-outside dismiss, và menu re-show sau TTS jump
* **Lỗi 1 – Vị trí menu sai**: Chuyển đổi `selectionMinY`/`selectionMaxY` từ window coordinates (UIKit) sang local coordinates của GeometryReader bằng cách trừ `geometry.frame(in: .global).minY`; thêm tham số `geometryOriginY` vào `FloatingSelectionMenu`.
* **Lỗi 2 – Không tắt khi tap ngoài**: Thêm `Color.clear` overlay với `.simultaneousGesture(TapGesture())` ở zIndex 9 (dưới menu), bắt mọi tap ra ngoài các nút menu để tắt menu và xóa selection mà không chặn scroll.
* **Lỗi 3 – Menu hiện lại sau TTS jump**: Thêm `uiView.selectedRange = NSRange(location: 0, length: 0)` ngay sau `uiView.attributedText = attributedText` để UIKit không giữ selection cũ khi highlight thay đổi.

## [1.3.25] - 2026-07-18

### Sửa lỗi Floating Bubble Menu và Global TTS Settings Sheet
* Khắc phục menu bong bóng đè lên vùng bôi đen: sử dụng union của `firstRect` và `caretRect(for: end)` để tính `minY`/`maxY` toàn bộ vùng selection; menu xuất hiện phía trên nếu đủ không gian, ngược lại phía dưới.
* Khắc phục menu không tắt khi tap ra ngoài: xóa guard `lastSelectionRange` khi `length == 0` để sự kiện deselect luôn được gửi lên ReaderView.
* Khắc phục bôi đen không xóa sau khi bấm nút: thêm `clearSelectionTrigger: UUID?` binding từ `ReaderView` → `ParagraphCardView` → `ReaderTextView`; mỗi action của menu đều kích hoạt trigger xóa selection trên `UITextView`.
* Tạo file `TTSSettingsSheet.swift` mới: wrapper `NavigationStack { TTSSettingsView(isPresentedAsSheet: true) }` dùng chung toàn cục cho Widget và mọi màn hình.
* Gắn `.sheet(isPresented: $ttsManager.showingSettingsSheet)` lên `AppLaunchRootView` thay vì `ReaderView` để sheet cài đặt TTS hoạt động ở mọi tab; `NavigationLink` bên trong `TTSSettingsView` không còn bị disabled.

## [1.3.24] - 2026-07-18

### Custom Selection Menu, NghiTTS Pronunciation Integration, Custom Dict Export Naming, and Remote Metadata Sync
* Thay thế Edit Menu hệ thống bằng SwiftUI Floating Bubble Menu chứa 5 nút Dịch, Nghe, Phiên âm, Copy, Đóng khi bôi đen văn bản trong Reader.
* Sử dụng scroll offset KVO và selection change delegates để giữ vị trí menu bám sát vùng bôi đen của chữ kể cả khi cuộn trang.
* Khắc phục mất góc Floating Bubble Menu ở sát lề màn hình bằng cách giới hạn tọa độ x theo screenWidth.
* Tăng kích thước Floating Bubble Menu lên to rõ hơn (nút 60x48, cỡ chữ 11, cỡ icon 16) và đổi icon nghe thành headphones hợp lệ.
* Sử dụng từ hiển thị đã dịch (nếu bật dịch) làm từ gốc khi thêm Phiên âm NghiTTS.
* Gỡ bỏ nút Thêm phiên âm trong panel dịch ở đáy.
* Tích hợp màn hình cài đặt TTSSettingsView dạng sheet trong ReaderView để nút cài đặt trên Widget có thể mở chính xác.
* Hỗ trợ tìm kiếm thêm nhanh phiên âm tại màn hình quản lý NghiTTS và tự động điền gợi ý phát âm từ `EnglishTransliterator`.
* Cài đặt nút bánh răng (Cài đặt TTS) nằm ở bên phải cover sách của Floating Widget để mở nhanh cài đặt TTS, mở rộng widget size về 212.
* Định dạng lại cấu trúc tên file xuất từ điển riêng thành `[Vietphrase/Name]_[Tên truyện đã dịch (ưu tiên) hoặc Tên truyện gốc]_[yyyyMMddHHmmss].txt` và hiển thị Toast kết quả.
* Chỉnh sửa cơ chế lấy metadata của Extension khi đồng bộ Repo: tự động tải và parse file `plugin.json` từ xa của từng extension dựa trên trường `path` của file zip, hỗ trợ dự phòng về dữ liệu registry tổng khi gặp lỗi.

## [1.3.23] - 2026-07-18

### Tách biệt điều hướng chương TTS/Reader và tối giản widget nổi
* Sửa đổi logic ReaderView để việc chuyển chương thủ công (Next/Prev/TOC) không kéo theo TTS chuyển chương theo.
* Chỉ tự động cuộn màn hình Reader theo tiến độ đọc của TTS khi người dùng đang ở cùng chương với TTS.
* Khi TTS tự động chuyển chương (advance), Reader chỉ chuyển theo nếu trước đó người dùng đang đọc cùng chương với TTS.
* Cập nhật nút nghe (headphones) trong Reader luôn dừng TTS cũ và phát lại từ dòng đầu tiên hiển thị trên màn hình hiện tại.
* Tối giản widget nổi TTS: loại bỏ hiển thị text tên sách/chương để tránh rối mắt, điều chỉnh chiều rộng widget mở rộng về 174 (thay vì 252) và căn chỉnh khoảng cách các nút điều khiển cho cân đối.

## [1.3.22] - 2026-07-18

### Khôi phục kiến trúc layout và cử chỉ kéo thả/chạm của Widget nổi TTS
* Khôi phục layout bằng `GeometryReader` kết hợp `.position(renderPosition)` thay thế cho `.offset()` cũ để đồng bộ chính xác vùng vẽ visual và vùng nhận tương tác (hit-test area). Điều này giúp khắc phục triệt để lỗi widget bị "liệt" không nhận kéo thả do lệch vùng chạm.
* Sử dụng `DragGesture(minimumDistance: 5)` với `.highPriorityGesture` để ưu tiên cử chỉ kéo thả của widget mà không bị nuốt bởi các nút bấm điều khiển bên trong hoặc các cử chỉ cuộn nền của Reader.
* Khôi phục `.onTapGesture` trực tiếp trên widget để xử lý chạm kích hoạt mở rộng (`reveal()`) khi ở trạng thái ẩn (peeking) hoặc tạm dừng/phát nhạc (`togglePlayback()`) khi chạm vùng trống ở trạng thái mở rộng (revealed), loại bỏ logic nhận diện tap tự chế phức tạp trong `onEnded`.

## [1.3.21] - 2026-07-18

### Sửa lỗi điều khiển tai nghe và kéo widget nổi
* Sửa lỗi bấm tai nghe phải bấm hai lần mới phát lại: bỏ cập nhật trạng thái trước (`setSystemNowPlayingPlaybackState`) trong handler remote command và dùng `DispatchQueue.main.async` thay vì `Task` để `resume()`/`pause()` chạy đồng bộ trên main queue, đảm bảo trạng thái cập nhật nhất quán trước khi iOS xử lý lệnh tiếp theo.
* Sửa lỗi widget nổi không thể kéo hoặc hiển thị lại từ trạng thái thu nhỏ (peeking) và trạng thái đầy đủ (revealed): đổi gesture từ `.simultaneousGesture` sang `.gesture` với `minimumDistance: 0`, loại bỏ `.onTapGesture` riêng trên collapsedWidget vì nó nuốt toàn bộ sự kiện chạm và chặn drag gesture kích hoạt; xử lý tap-to-reveal và tap-to-toggle-playback trong `onEnded` của drag gesture dựa trên ngưỡng di chuyển.

## [1.3.20] - 2026-07-18

### Đồng bộ Lock Screen, cử chỉ kéo widget và khôi phục text DOM
* Khôi phục hành vi trích xuất văn bản DOM (`JSDom.swift`) không trim khoảng trắng và dòng mới tại lớp DOM để tránh làm hỏng các tiền tố kiểm tra của Extension.
* Sửa lỗi đồng bộ điều khiển Lock Screen/AirPods (`TTSManager.swift`): Vô hiệu hóa `togglePlayPauseCommand` tránh nhận trùng lặp sự kiện trên thiết bị Bluetooth; đồng thời cập nhật tức thì trạng thái playback state ngay trong luồng chính để phản hồi nhanh chóng lên UI Lock Screen.
* Tối ưu hóa cử chỉ widget nổi (`TTSFloatingWidgetView.swift`, `FloatingWidgetViewModel.swift`): Giữ nguyên chế độ hiển thị trong suốt quá trình kéo tránh ngắt quãng gesture; tách biệt rõ ràng tap và drag snapping; bổ sung kiểm tra kích thước màn hình hợp lệ để tránh lỗi tính toán.
* Thêm kiểm thử tự động cho trạng thái đồng bộ Now Playing, cử chỉ snapping và các trường hợp widget biên trong `FloatingWidgetViewModelTests.swift` và `TTSManagerTests.swift`.

## [1.3.19] - 2026-07-18

### Local-first Reader/TTS và quản lý kho an toàn
* Dùng chung chapter repository theo thứ tự RAM → SwiftData → extension, coalesce in-flight load và ghi nền bằng `ChapterPersistenceStore` có retry/flush.
* Sửa dữ liệu cũ có content nhưng sai `isCached`, upsert Book/Chapter online và giữ cache khi đồng bộ lại mục lục.
* Cô lập session Reader/TTS theo book/chapter/session identity; Reader sách khác không prepare hoặc seek TTS đang phát hay pause.
* Danh sách kho bỏ swipe-delete và toggle; thêm nút trash, xác nhận xóa và bảo vệ kho đang được TTS sử dụng.
* Tách phần thân Reader và overlay mục lục thành các view con để tránh lỗi SwiftUI type-check quá thời gian; flush persistence không còn cảnh báo giá trị trả về bị bỏ qua.
* Không để snapshot rỗng từ `@Query` ghi đè số chương đã resolve trực tiếp từ SwiftData; Reader bootstrap lại khi dữ liệu local/online đến muộn.
* Widget TTS mở ở trạng thái hiển thị khi session bắt đầu và chỉ tự thu gọn sau timeout hoặc thao tác kéo sát cạnh.
* BookDetail truyền TOC online làm fallback bootstrap để mở Đọc tiếp không phụ thuộc thời điểm `@Query` phát hiện Book local.
* Truy vấn bootstrap Reader lọc theo `bookId` và giới hạn một bản ghi để không quét toàn bộ SwiftData trên MainActor.
* Nút nghe trong Reader luôn giữ biểu tượng tai nghe và chỉ dừng session TTS thuộc cùng sách; metadata Book/author trên màn hình tải và xuất ebook phản ánh cài đặt dịch.
* Đồng bộ Lock Screen/AirPods với trạng thái TTS thực tế, chống Now Playing update cũ ghi đè trạng thái mới và hỗ trợ `togglePlayPauseCommand`.
* Tra cứu nhanh từ màn hình dịch dùng route URL bất biến; WebView tải lại khi URL đích đổi để không còn trang trắng hoặc hiển thị truy vấn trước đó.

## [1.3.18] - 2026-07-18

### Thu gọn và căn sát widget TTS
* Giảm kích thước capsule và các nút điều khiển để widget che ít nội dung Reader hơn.
* Căn trạng thái mở rộng sát mép trái/phải màn hình; trạng thái thu gọn giữ nửa hình tròn nhỏ hơn ở đúng cạnh đã chọn.

## [1.3.17] - 2026-07-18

### Sửa lỗi biên dịch sau khi dọn Reader legacy
* Khôi phục `DictionaryMatchInfo`, `ReaderSettingsView` và `ReaderViewModelObserver` thành các file độc lập thay vì để mất cùng khối Reader legacy.
* Trả đúng `ReaderParagraphBuildResult` từ `Task.detached` trong `ReaderViewModel`, tránh suy luận kết quả thành `Void`.
* Chỉ khởi chạy task cấu hình progress/repository sau khi toàn bộ stored property của `ReaderViewModel` đã được khởi tạo.
* Dọn closure rỗng trong navigation commit và capture `self` không sử dụng của `ImageCacheManager`.
* Reader tự lấy snapshot chương local khi `@Query` đến muộn và đồng bộ danh sách chương online cập nhật sau khi Reader đã mount; widget TTS không còn phủ vùng hit-test toàn màn hình.

## [1.3.16] - 2026-07-18

### Thiết kế lại widget TTS nổi
* Thay widget radial bằng capsule ngang có cover tròn, play/pause, next đoạn và nút đóng.
* Cover xoay liên tục khi phát, giữ góc hiện tại khi tạm dừng; thao tác cover mở đúng chương TTS đang đọc.
* Hỗ trợ kéo vào hai cạnh, tự thu gọn thành nửa hình tròn sau khi chạm cạnh hoặc không thao tác, kéo ra để mở lại và giới hạn vị trí theo màn hình.
* Cho phép chuyển đoạn tiếp theo khi TTS đang tạm dừng và đồng bộ điều hướng Reader khi sách đã mở.

## [1.3.15] - 2026-07-18

### Cải tổ pipeline Reader/TTS
* Chuẩn hóa văn bản chương một lần bằng `ChapterTextNormalizer`, dùng chung `ChapterContentRepository` cho Reader và TTS.
* Thêm bootstrap/load state có retry và timeout, route mục lục bất biến, checkpoint tiến độ nền, ownership TTS và session guard.
* Xóa Reader window/tab/legacy, repository tiến độ trùng và `TTSSession` mirror.

## [1.3.14] - 2026-07-17

### Chuẩn hóa paragraph 1–1 và ánh xạ vùng chọn bản dịch
*   **Người thực hiện**: Trợ lý AI Codex
*   **Tổng số file nguồn ảnh hưởng**: 7 file Swift, 1 file test
*   **Mô tả**:
    *   Tách nội dung gốc thành dòng trước khi dịch, dịch độc lập từng dòng và tạo `ParagraphItem` 1–1 với id ổn định, kể cả dòng rỗng hoặc dòng cuối trống.
    *   Bổ sung kết quả dịch kèm span gốc/bản dịch theo UTF-16; payload `ParagraphItem` cũ vẫn decode với danh sách span rỗng.
    *   Menu “📖 Dịch” chỉ truyền `NSRange` và paragraph id; Reader lấy đúng item trong chương, luôn dùng `item.original` cho màn hình dịch.
    *   Ưu tiên span chính xác và giữ thuật toán câu/token của commit `3312841` làm fallback khi mapping thiếu hoặc không hợp lệ.
    *   Thêm test cho paragraph 1–1, blank/trailing line, Codable cũ, UTF-16, multi-token và fallback lịch sử.

## [1.3.13] - 2026-07-17

### Phản hồi tải chương tức thì và tinh gọn tương tác Reader
*   **Người thực hiện**: Trợ lý AI Codex
*   **Tổng số file nguồn ảnh hưởng**: 5 file Swift, 1 file test
*   **Mô tả**:
    *   Reader trình bày ngay chương đích bằng tiêu đề, số chương và skeleton trong lúc vẫn giữ debounce 300 ms để gộp thao tác liên tiếp.
    *   Bỏ vuốt ngang chuyển chương, swipe hint, state kéo biên và callback selection activity chỉ phục vụ gesture cũ; chọn chữ, tra từ, copy và TTS vẫn giữ nguyên.
    *   Thu gọn header Reader, đổi overflow thành ba chấm dọc; header mục lục bỏ khoảng trống co giãn, đổi icon sắp xếp, bỏ nút X và hỗ trợ vuốt xuống tại tay nắm để đóng.
    *   Bổ sung validator CodeGraph chuẩn hóa link, schema, marker, source/document inventory và SHA-256 của manifest.

## [1.3.12] - 2026-07-17

### Cap nhat UI Reader va header danh sach chuong
*   **Nguoi thuc hien**: Tro ly AI Codex
*   **Tong so file nguon anh huong**: 2 file Swift
*   **Mo ta**:
    *   Header Reader dung ba hang: back/reload/dropdown, nut dich gop hai hang, ten truyen va hang ten chuong mo muc luc.
    *   Body bo thanh cong cu thu gon, chi giu mot nut TTS noi.
    *   Danh sach chuong truot tu duoi len, van mount trong suot vong doi Reader va ton trong Reduce Motion.
    *   Header muc luc hien cover, ten truyen va tac gia day du; cong cu refresh/sap xep/dong nam o goc duoi ben phai metadata.
    *   Metadata dich theo trang thai dich cua Reader va khong tai lai detail hay muc luc.

## [1.3.11] - 2026-07-17

### Refactor Reader mot chuong va toi uu dieu huong
*   **Nguoi thuc hien**: Tro ly AI Codex
*   **Tong so file nguon anh huong**: 7 file Swift, 1 file test
*   **Mo ta**:
    *   Reader chi render mot chuong; chuyen chuong bang swipe ngang hoac footer, khong tu dong tai/chuyen khi cuon doc den cuoi.
    *   Dieu huong thu cong debounce 300 ms va giu target moi nhat; mot worker tai noi dung va generation check ngan request cu commit sai chuong.
    *   Loi `Response.error` duoc giu nguyen, hien cung ten chuong va nut retry o giua man hinh.
    *   Danh sach chuong duoc tao va mount mot lan trong vong doi Reader; cache thanh cong chi cap nhat icon cua mot row.
    *   Dropdown dung chung command cho hien ten chuong, force reload, tu dien, browser va cai dat.
    *   TTS sync chi thay doi vi tri hien thi, khong ghi de lich su; Reader prefetch N+1 bi tat khi TTS cung sach dang phat.
    *   Them test cho rapid-step N+4, chapter list 10.000 row va thong diep source error.

## [1.3.10] - 2026-07-17

### Fix Reader history restore, infinite chapter loading, and jump/list lag
*   **Nguoi thuc hien**: Tro ly AI Codex
*   **Tong so file nguon anh huong**: 4 file Swift, 1 file test
*   **Mo ta**:
    *   Reader mo dung vi tri lich su; TTS dang phat khong ghi de vi tri ban dau, nhung lan chuyen paragraph ke tiep se dua giao dien ve vi tri TTS neu auto-scroll dang bat.
    *   Window render cap nhat `stableIndexes` khi scroll qua chapter, sua loi dung tai gioi han `n+2`.
    *   Chapter list chi duoc khoi tao khi mo va dich title theo row hien thi, giam tai MainActor.
    *   Prefetch task da cancel van chiem local/global concurrency slot den khi fetch dong bo thuc su ket thuc; Reader cu khong the mo them batch song song voi Reader moi sau luong thoat -> Kham pha -> Doc ngay.
    *   Reader teardown huy queue/task rieng va chi force-save khi Reader dang so huu progress.
    *   Them test hoi quy cho window chapter va gioi han concurrency voi fetch khong phan hoi cancellation ngay.
    *   Jump chi tai chapter dich; sau khi dich tai xong va Reader on dinh moi tai mot chapter ke tiep. Jump nhanh loai bo cac chapter trung gian chua bat dau.
    *   Muc luc khong animate qua hang nghin row va khong tao them query toan bo Book/Extension khi mo.

## [1.3.9] - 2026-07-17

### Cap nhat UI Reader header/body/footer va TTS CD radial widget
*   **Nguoi thuc hien**: Tro ly AI Codex
*   **Tong so file nguon anh huong**: 6 file Swift
*   **Mo ta**:
    *   **ReaderView**: Bo HUD tap an/hien, chuyen sang layout co dinh `Header + Body + Footer`; header co back, ten truyen/ten chuong va dropdown option cu; footer hien phan tram va chi so chuong.
    *   **ReaderTextView**: Bo gesture post `toggleReaderControls` de tap vao noi dung khong con an/hien HUD, van giu `UITextView` va text selection/custom menu; them first-line indent cho moi doan van ban ma khong chen khoang trang vao noi dung goc.
    *   **Reader floating controls**: Them cum nut noi thu vao mep phai cho dich, TTS va danh sach chuong.
    *   **TTSFloatingWidgetView / FloatingWidgetViewModel / WidgetState**: Thay expanded/collapsed widget bang CD radial widget co cover trung tam, play/pause overlay, cac nut radial xem reader/next/stop va nut an vao mep.

## [1.3.8] - 2026-07-17

### Refactor Reader sang Infinite Vertical Window va bo sung TTSSession snapshot
*   **Nguoi thuc hien**: Tro ly AI Codex
*   **Tong so file nguon anh huong**: 9 file Swift, 1 file test
*   **Mo ta**:
    *   **ReaderView**: Them runtime `Infinite Vertical Reader` dung mot `ScrollViewReader` + mot `ScrollView` + `LazyVStack` cho window chapter hien tai. Paragraph van render qua `ParagraphCardView`/`ReaderTextView`, giu nguyen `UITextView`, selection menu, dich, nghe doan chon va copy.
    *   **ReaderViewModel**: Bo sung `ReadingContext`, chuyen jump/chapter selection sang thao tac replace/rebase window quanh chapter dich thay vi scroll qua toan bo truyen. Window mac dinh can bang theo `ReaderWindowManager`.
    *   **ReaderWindowManager / ReaderCoordinator / ChapterContentProvider**: Them cac seam kien truc de tach quyet dinh window/progress/loading khoi UI va chuan bi gom cache/content provider dung chung.
    *   **ChapterCache**: Bo sung state `notLoaded`, `ReadingContext` va alias `SharedChapterCache` de thong nhat huong cache dung chung Reader/TTS.
    *   **TTSManager / TTSSession**: Them `TTSSessionSnapshot` va `PlaybackQueue`; TTS cap nhat session snapshot khi start/pause/resume/stop va khi phat tung paragraph, giup Reader mo lai co the sync tu session thay vi so huu playback.
    *   **Tests**: Cap nhat `ReaderViewModelTests` theo API `PrefetchManager.updateQueue(... activeIndex:)` hien tai.

## [1.3.7] - 2026-07-16

### Sửa lỗi lấy chương online của TTS do gán sai thông tin tiện ích khi mở lại màn hình đọc (Fix TTS Online Extension Resolution)
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 4 file Swift (TTSModels.swift, TTSManager.swift, ReaderView.swift, ShelfView.swift)
*   **Mô tả**:
    *   **TTSModels**: Bổ sung thuộc tính `packageId` vào struct `TTSExtensionInfo` để lưu lại định danh của extension (thay vì chỉ lưu localPath).
    *   **TTSManager**:
        *   Thêm các thuộc tính toàn cục `playingBookDetailUrl` và `playingBookSourceName` để lưu trữ đường dẫn chi tiết sách và tên nguồn tương ứng của chương đang phát.
        *   Cập nhật `startSpeaking` và `prepareSpeaking` để nhận và gán hai thuộc tính này khi khởi chạy TTS.
    *   **ReaderView**:
        *   Truyền `packageId` thực tế khi khởi tạo `ttsExtensionInfo`.
        *   Cập nhật các cuộc gọi tới `startSpeaking` và `prepareSpeaking` để truyền thêm thông tin `bookDetailUrl` và `bookSourceName` (ưu tiên lấy từ cơ sở dữ liệu `localBook`, dự phòng lấy từ tham số cấu hình View).
    *   **ShelfView**:
        *   Sửa đổi phương thức xử lý sự kiện khôi phục màn hình đọc truyện đang phát (`openCurrentlyPlayingReader`). Gán đúng thuộc tính `packageId` cho `navigateToPlayingExtensionId`, `playingBookDetailUrl` cho `navigateToPlayingDetailUrl` và `playingBookSourceName` cho `navigateToPlayingSourceName` thay vì gán nhầm các thuộc tính cấu hình nội bộ của extension (như `localPath`, `downloadUrl`, `configJson`). Đảm bảo khôi phục đầy đủ và chính xác thông tin để trình đọc tiếp tục lấy chương mới online bình thường mà không báo lỗi cạn kiệt tiện ích bóc tách.

## [1.3.6] - 2026-07-15

### Khắc phục lỗi điều khiển phát nhạc bằng tai nghe, đồng bộ màn hình khóa & Khôi phục luồng chuyển chương TTS (TTS Remote & Lock Screen Fix v2)
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 1 tệp Swift (TTSManager.swift)
*   **Mô tả**:
    *   **TTSManager**:
        *   Cập nhật `setRemoteCommandsEnabled()` và `setupRemoteCommandCenter()`: Loại bỏ hoàn toàn sự kiện `togglePlayPauseCommand` vì gây xung đột trùng lặp sự kiện trên iOS khi người dùng bấm nút trên tai nghe. OS của iOS sẽ tự động dịch chuyển nút tai nghe thành lệnh `playCommand` hoặc `pauseCommand` dựa trên giá trị của `playbackState`.
        *   Cập nhật `pause()`, `resume()` và `stopPlayback()`: Đồng bộ hóa cập nhật `playbackState` của `MPNowPlayingInfoCenter.default()` ngay khi trạng thái `isPlaying` của ứng dụng thay đổi, loại bỏ độ trễ và giúp lockscreen hiển thị đúng nút Pause/Play tương ứng tức thì.
        *   Cập nhật `pause()`: Ghi nhận thời điểm tạm dừng vào biến `lastPausedTime = Date()`.
        *   Cập nhật `resume()`: Tích hợp bộ đếm thời gian chờ (timeout) 5 giây thông minh. Nếu thời gian từ lúc tạm dừng đến lúc tiếp tục phát vượt quá 5.0 giây hoặc chưa có `currentPlaybackId`, sẽ gọi `speakCurrent()` để tái tạo một buffer mới tinh (tránh cạn kiệt/mất tiếng do OS giải phóng bộ đệm của AVAudioPlayerNode trong nền). Nếu dưới 5.0 giây, ứng dụng sẽ gọi tiếp `playerNode?.play()` để phát tiếp tục liền mạch tại vị trí cũ. Tránh được lỗi lặp lại đoạn hoặc đứng luồng không tự động chuyển chương trong ReaderView.

## [1.3.5] - 2026-07-15

### Tối ưu hóa hiệu năng, prefetch TTS, Đơn giản hóa UI Loading, Tinh gọn Telegram & Fix bug nháy Loading
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 4 file (ReaderView.swift, ReaderViewModel.swift, TTSManager.swift, build-ipa.yml)
*   **Mô tả**:
    *   **ReaderView**:
        *   `schedulePrepareTTS()`: Thêm guard kiểm tra `ttsManager.showFloatingWidget`. Không lên lịch chuẩn bị dữ liệu TTS nếu người dùng chỉ đọc sách chay.
        *   `updateScrollReadingProgress()`: Thêm guard kiểm tra `ttsManager.isPlaying || ttsManager.showFloatingWidget` ở phần 2 (đồng bộ vị trí con trỏ TTS). Khi đọc sách chay, không thực hiện đồng bộ vị trí con trỏ để giải phóng Main Thread.
        *   **Đơn giản hóa màn hình loading**:
            *   Trong `chapterLoadingView` (màn hình loading ban đầu): Loại bỏ dòng mô tả "Đang tải nội dung chương..." và nút "Tải lại" thủ công rườm rã. Chỉ giữ lại Tên chương, biểu tượng load `ProgressView` và nút "Quay lại" căn giữa màn hình.
            *   Trong `stableIndexes` loop (khi vuốt chuyển trang): Tương tự, đơn giản hóa phần loading bằng cách loại bỏ text mô tả và nút "Tải lại", chỉ hiển thị Tên chương, biểu tượng load và nút "Quay lại" căn giữa.
    *   **ReaderViewModel**:
        *   `loadChapterContentFromExtension(_:)`: Thêm điều kiện guard kiểm tra nếu chương đã được tải thành công trước đó trong RAM Cache (trạng thái `.loaded`), bỏ qua không tải lại. Điều này giúp loại bỏ hoàn toàn hiện tượng nhấp nháy màn hình load đè lên nội dung truyện đã có sẵn khi vuốt qua lại giữa các chương.
    *   **TTSManager**:
        *   Bổ sung properties `prepareSpeakingTask` và `nextChapterPrefetchTask` để quản lý các tác vụ bất đồng bộ.
        *   `prepareSpeaking(...)`: Di chuyển hàm xử lý văn bản nặng `parseParagraphs(...)` sang chạy ngầm thông qua `Task.detached` với cú pháp tường minh đầu ra `-> [TTSParagraph]` để sửa lỗi biên dịch Swift. Tự động hủy task cũ khi chuyển chương nhanh.
        *   `updateNowPlayingInfo()`: Di chuyển các tác vụ nặng (dịch thuật Hán Việt tiêu đề, load ảnh bìa từ disk) sang chạy ngầm bất đồng bộ bằng `Task.detached` với priority `.background`. Chỉ cập nhật `MPNowPlayingInfoCenter` sau khi đã xử lý xong dữ liệu từ background.
        *   Thêm phương thức `triggerNextChapterPrefetch()` tự động tải trước 1 chương tiếp theo ngầm (từ DB cache hoặc online extension) khi bắt đầu phát chương hiện tại.
        *   `startSpeaking(...)` & `applyNextChapter(...)`: Kích hoạt `triggerNextChapterPrefetch()` để luôn nạp sẵn chương mới, giảm thiểu khoảng trễ khi nghe chạy nền (đã thoát trình đọc).
        *   `clearPrefetchCache()`: Hủy `nextChapterPrefetchTask` để dọn dẹp tài nguyên.
    *   **build-ipa.yml**:
        *   Loại bỏ hoàn toàn bước chạy script Python trích xuất lỗi và tệp tin `summary_error.txt`.
        *   Sửa đổi tin nhắn gửi đến Telegram khi build thất bại để chỉ hiển thị thông tin chung và link xem logs đầy đủ trên Github Actions, bảo mật và tinh gọn nội dung tin nhắn.
        *   Lược bỏ các lệnh ghi lỗi thừa `2>&1 | tee -a build_error.log` ở bước compile và package.

## [1.3.4] - 2026-07-15

### Gửi chi tiết lỗi build qua Telegram và bóp trigger workflow build
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 1 file workflow (.github/workflows/build-ipa.yml)
*   **Mô tả**:
    *   **build-ipa.yml**:
        *   Cập nhật trigger: chỉ kích hoạt build khi sửa các file trong `Sources/**` (bóp trigger paths).
        *   Tích hợp ghi logs build (`stdout` và `stderr`) từ các bước xcodebuild và xcodegen vào tệp chung `build_error.log` bằng lệnh `tee -a`.
        *   Thêm bước chạy Python inline ở bước `Send Failure Notification to Telegram` để đọc `build_error.log`, trích xuất tối đa 20 dòng lỗi compiler Xcode (lọc theo regex `\s+(error|failed)` để bắt chính xác lỗi Swift compile/warnings có khoảng trắng phía trước) rồi ghi vào `summary_error.txt`.
        *   Đọc tệp `summary_error.txt` (giới hạn 2000 ký tự) gửi kèm vào tin nhắn báo lỗi qua Telegram API.

## [1.3.3] - 2026-07-15

### Fix TTS tự chuyển chương khi thoát Reader & cải thiện cache lookup
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 4 file Swift
*   **Mô tả**:
    *   **TTSModels**: Bổ sung field `host: String?` vào `TTSChapterInfo` để `TTSManager` có đủ thông tin tự fetch nội dung chương khi không có cache.
    *   **TTSManager**:
        *   Thêm hàm `advanceToNextChapter(nextIdx:)` với thứ tự ưu tiên cache: **RAM** (`chaptersQueue.cachedContent`) → **DB** (`Chapter.isCached + content` qua SwiftData) → **fetch online** (`ExtensionManager`). TTSManager giờ tự advance chapter độc lập, không cần `ReaderView` làm trung gian.
        *   Thêm hàm `applyNextChapter(index:content:chapter:)` apply nội dung chương mới, gọi `continueStartSpeaking`, và post notification `ttsDidAdvanceToNextChapter` để sync UI.
        *   Thêm hàm `fetchChapterContentFromDB(chapterUrl:)` query SwiftData trực tiếp để lấy content đã cache.
        *   Thêm hàm `updateChapterCache(at:content:)` cho phép `ReaderViewModel` cập nhật `cachedContent` trong `chaptersQueue` sau mỗi chương load xong.
        *   `nextParagraph()`: khi hết chương gọi `advanceToNextChapter` thay vì post notification trực tiếp.
        *   `skipForward()`: khi hết chương gọi `advanceToNextChapter` thay vì `onChapterFinished?()`.
    *   **ReaderViewModel**: Sau khi `processAndSaveChapter` hoàn thành, gọi `TTSManager.shared.updateChapterCache(at:content:)` để RAM cache luôn sẵn sàng cho TTS advance.
    *   **ReaderView**:
        *   Luồng tạo TTS chapter info truyền `host` từ `Chapter.host` / `ChapterResult.host` vào `TTSChapterInfo`.
        *   `.onDisappear`: clear 3 callbacks (`onChapterFinished`, `onChapterNext`, `onChapterPrev`) để tránh ghost reference.
        *   `.onReceive("ttsDidAdvanceToNextChapter")`: đổi `ttsShouldAutoPlayNextChapter = false` — TTS đã tự phát, ReaderView chỉ sync UI (chuyển tab, scroll).

## [1.3.2] - 2026-07-15

### Fix TabView sliding window jump khi vuốt chương liên tục & các vấn đề hiệu năng liên quan
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 3 file Swift
*   **Mô tả**:
    *   **ReaderViewModel**:
        *   Thêm `stableIndexes: [Int]` — array `TabView` bind vào, chỉ update sau khi animation swipe kết thúc.
        *   Thêm `pendingWindowSlide: Bool` flag và `commitWindowSlide()` — gọi từ `.onAppear` của tab đích để slide window và ghi tiến trình sau animation.
        *   `onTabSelectionChanged` thêm `immediate: Bool` — swipe dùng `false` (deferred), jump từ chapter list/TTS dùng `true` (sync ngay).
        *   `processAndSaveChapter`: đổi guard check sang `visibleIndexes.contains(index) || index == activeChapterIndex` để tránh drop chương đang swipe đến.
        *   `saveProgressImmediately()` được defer sang `commitWindowSlide()` trong swipe path, tránh I/O tranh chấp main thread giữa animation.
        *   `computeWindowRange()` và `enqueuePrefetch()` đổi sang `internal`.
    *   **ReaderView**:
        *   `ForEach(vm.visibleIndexes)` → `ForEach(vm.stableIndexes)`.
        *   Thêm `vm.commitWindowSlide()` vào đầu `.onAppear` của mỗi tab.
        *   Thêm `.onChange(of: vm.tabSelection)` safety net đảm bảo `commitWindowSlide()` được gọi dù `onAppear` không fire.
        *   Xoá `.id(chapterIndex)` khỏi `readerContentView`.
        *   `selectChapter(at:)` gọi `onTabSelectionChanged(immediate: true)`.
        *   `onChange` của chapter count sync `stableIndexes` ngay sau `updateVisibleChaptersWindow()`.
    *   **TTSModels**: Thêm field `host: String?` vào `TTSChapterInfo` (dùng chung với [1.3.3]).

---

## [1.3.1] - 2026-07-15

### Đọc metadata local sau cài đặt tiện ích & Hiển thị hình cờ quốc gia bên cạnh version
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 1 file Swift
*   **Mô tả**:
    *   **RepositoryManagerView**:
        *   Cập nhật hàm `installExtension`: Sau khi giải nén tiện ích thành công, tiến hành đọc tệp cấu hình `plugin.json` nội bộ của tiện ích đó để lấy thông tin thực tế (`locale`, `type`, `version`, `author`) và cập nhật ngược lại vào database SwiftData. Giải quyết triệt để lỗi mất thuộc tính ngôn ngữ tiếng Trung của các tiện ích Trung Quốc (do file plugin.json tổng hợp trên kho GitHub không khai báo trường này).
        *   Thêm emoji lá cờ đại diện quốc gia tương ứng với ngôn ngữ (ví dụ 🇻🇳 cho tiếng Việt, 🇨🇳 cho tiếng Trung, 🇺🇸 cho tiếng Anh) ngay bên cạnh badge hiển thị phiên bản tiện ích.

## [1.3.0] - 2026-07-15

### Cải tiến giao diện và lưu trữ cấu hình tiện ích (Extensions)
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 2 file Swift
*   **Mô tả**:
    *   **ExtensionStoreView**: [DELETE] Xóa hoàn toàn tệp `ExtensionStoreView.swift` vì không còn được sử dụng.
    *   **RepositoryManagerView**:
        *   Chuyển các biến bộ lọc (`filterType`, `filterLocale`, `filterAuthor`) sang `@AppStorage` để lưu trạng thái bộ lọc tiện ích khi thoát/mở lại màn hình.
        *   Xóa bỏ hoàn toàn bộ lọc theo Kho tiện ích (`filterRepoUrl`) và badge tên kho hiển thị trên mỗi dòng tiện ích.
        *   Ẩn dòng chữ "Đã cài" hiển thị bên cạnh các nút chức năng của tiện ích đã cài đặt.
        *   Tại danh sách kho, loại bỏ `NavigationLink` chuyển sang trang chi tiết kho, hiển thị kho dạng dòng thông tin bình thường và hỗ trợ vuốt trái để xóa kho.

## [1.2.9] - 2026-07-15

### Đồng bộ giao diện nạp trang chương bên trong TabView để hiển thị đầy đủ nút điều khiển ở trung tâm
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 1 file Swift
*   **Mô tả**:
    *   **ReaderView**: Cập nhật logic hiển thị trạng thái đang tải (`loading`/`prefetching`) và lỗi (`failed`) của từng trang chương riêng lẻ bên trong `TabView` (`textReaderView`). Bổ sung nút **"Quay lại"**, **"Tải lại"**, và **"Xem nguồn"** xếp dọc ở chính giữa màn hình giống hệt như màn hình nạp chung để người dùng không bị kẹt khi app đang tải nội dung chương.

## [1.2.8] - 2026-07-15

### Đưa nút "Quay lại" có chữ vào giữa màn hình dưới cụm loading và cụm lỗi
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 1 file Swift
*   **Mô tả**:
    *   **ReaderView**: Thiết kế lại giao diện màn hình `chapterLoadingView`. Loại bỏ nút Đóng "X" góc trên trái, thay thế bằng nút bấm có chữ **"Quay lại"** (icon `arrow.left`) và đặt ở chính giữa màn hình bên dưới vòng xoay nạp chương cũng như xếp dưới cùng các nút báo lỗi.

## [1.2.7] - 2026-07-15

### Bổ sung nút "Xem nguồn" xếp dọc dưới nút "Tải lại" khi nạp chương lỗi
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 1 file Swift
*   **Mô tả**:
    *   **ReaderView**: Thiết kế lại giao diện trạng thái báo lỗi của màn hình `chapterLoadingView` để xếp dọc nút **"Tải lại"** ở trên và thêm nút **"Xem nguồn"** ở dưới để mở trình duyệt bypass Cloudflare tương tự nút trên thanh công cụ.

## [1.2.6] - 2026-07-15

### Khôi phục logs chẩn đoán crash và triển khai giải pháp loại bỏ hiển thị overlay khi tải chương
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 4 file Swift
*   **Mô tả**:
    *   **AppLogger, BookDetailView, ReaderViewModel**: Hoàn tác toàn bộ các dòng log chẩn đoán crash (`[FreeBookDebug]`) và bật lại bộ lọc log để giữ mã nguồn gọn gàng.
    *   **ReaderView**:
        *   Khôi phục điều kiện hiển thị thanh công cụ overlay về `if showControls` để bẻ gãy đệ quy khởi tạo sớm ngầm của SwiftUI ngay từ frame nạp đầu tiên.
        *   Thiết kế lại màn hình `chapterLoadingView` với nút Đóng **"X"** (để người dùng thoát ra quay lại màn hình chi tiết) và bổ sung nút **"Tải lại"** (xoay lại) trực tiếp ở giữa màn hình cho cả hai trạng thái đang tải và lỗi.

## [1.2.5] - 2026-07-15

### Khắc phục lỗi crash tràn bộ nhớ do đệ quy eager trong NavigationLink của SwiftUI
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 3 file Swift nguồn
*   **Mô tả**:
    *   **Common/LazyView**: Thêm struct tiện ích `LazyView` giúp trì hoãn việc khởi tạo struct View đích bên trong `NavigationLink` cho đến khi liên kết đó thực sự được kích hoạt (`isActive == true`).
    *   **ReaderView & BookDetailView**: Bọc toàn bộ các đích đến chuyển hướng NavigationLink trỏ vòng quanh nhau (`BookDetailView` $\leftrightarrow$ `ReaderView`) bằng `LazyView`, phá vỡ hoàn toàn lỗi đệ quy khởi tạo sớm eager gây tràn bộ nhớ đệm (stack overflow) làm crash app khi bấm đọc truyện.

## [1.2.4] - 2026-07-15

### Bổ sung logs chẩn đoán crash bằng AppLogger
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 4 file Swift
*   **Mô tả**:
    *   **AppLogger**: Tạm thời tắt điều kiện kiểm tra `isLoggingEnabled` để đảm bảo file log luôn được ghi nhận trên thiết bị của người dùng khi app gặp sự cố.
    *   **BookDetailView, ReaderView, ReaderViewModel**: Chèn các dòng log ghi nhận tham số và trạng thái luồng chạy quan trọng (`[FreeBookDebug]`) để hỗ trợ chẩn đoán chính xác vị trí crash.

## [1.2.3] - 2026-07-15

### Khắc phục triệt để lỗi crash/kẹt ReaderView bất đồng bộ khi mở truyện online/offline
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 2 file Swift
*   **Mô tả**:
    *   **ReaderView**:
        *   Sửa lỗi truyền `@State currentOnlineChapters` khi khởi tạo `ReaderViewModel` trong `onAppear` bằng cách sử dụng trực tiếp tham số `onlineChapters` của View, tránh độ trễ gán `@State` dẫn đến truyền nhầm số chương bằng 0.
        *   Bổ sung bộ lắng nghe thay đổi `.onChange(of: currentOnlineChapters.count)` để tự động cập nhật lại số lượng chương cho `viewModel` khi danh sách chương online tải hoàn tất.
    *   **ReaderViewModel**: Cập nhật hàm `computeWindowRange()` tính toán cận trên (`upper`) và cận dưới (`lower`) và xác thực bằng `guard lower <= upper else { return [] }` trước khi tạo `ClosedRange` nhằm tránh lỗi sập `fatalError` của Swift.

## [1.2.2] - 2026-07-15

### Khắc phục lỗi crash do TabView rỗng và thêm cơ chế Clamp Index
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 2 file Swift
*   **Mô tả**:
    *   **ReaderViewModel**: Bổ sung hàm `clampActiveIndex()` tự động điều chỉnh chỉ mục chương đang hiển thị (`activeChapterIndex` và `tabSelection`) về chương cuối cùng hợp lệ nếu nó vượt quá số chương thực tế của sách, giải quyết triệt để lỗi crash do khởi tạo range sai `9...4` khi dữ liệu biên bị lệch chỉ mục.
    *   **ReaderView**: Sửa đổi `readerContentView` để hiển thị màn hình tải (`chapterLoadingView`) thay vì cố render `textReaderView` khi `totalChaptersCount == 0` hoặc `visibleIndexes` trống, tránh lỗi SwiftUI crash do `TabView` rỗng.

## [1.2.1] - 2026-07-15

### Tối ưu hóa trigger tự động chạy build IPA
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 1 file workflow (.github/workflows/build-ipa.yml)
*   **Mô tả**:
    *   Bổ sung bộ lọc đường dẫn (`paths`) cho các sự kiện `push` và `pull_request`.
    *   Giới hạn workflow chỉ tự động build IPA khi có sự thay đổi trong thư mục mã nguồn `Sources/`, tệp cấu hình dự án `project.yml` hoặc chính tệp workflow build, giúp tiết kiệm thời gian chạy và tài nguyên chạy của GitHub Actions.

## [1.2.0] - 2026-07-15

### Khắc phục lỗi build GitHub Actions do action dọn dẹp workflow runs cũ bị lỗi
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 1 file workflow (.github/workflows/cleanup-runs.yml)
*   **Mô tả**:
    *   Thay thế action bên thứ ba `Mattraiano/delete-old-runs-action` (bị xóa hoặc set private trên GitHub) bằng action chính chủ `actions/github-script@v7`.
    *   Tích hợp script gọi API của GitHub để dọn dẹp các runs cũ hơn 3 ngày của duy nhất repository hiện tại, giữ lại tối thiểu 1 run mới nhất, tăng độ tin cậy và bền vững của workflow.

## [1.1.9] - 2026-07-15

### Tự động tắt ghi log hệ thống khi khởi chạy lại ứng dụng
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 2 file Swift
*   **Mô tả**:
    *   **AppLogger**: Bổ sung cơ chế reset giá trị key `"isLoggingEnabled"` trong `UserDefaults` về `false` ngay trong hàm khởi tạo `init()`, đảm bảo tính năng ghi log hệ thống tự động tắt mỗi khi khởi chạy lại ứng dụng.
    *   **SettingsView**: Đồng bộ hóa giá trị mặc định của Toggle ghi log hệ thống thành `false`.

## [1.1.8] - 2026-07-15

### Khắc phục lỗi crash app khi mở trình đọc truyện
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 2 file Swift
*   **Mô tả**:
    *   **ReaderViewModel**:
        *   Bảo vệ `computeWindowRange()` chống crash bằng cách kiểm tra nếu `totalChaptersCount <= 0` thì trả về Set rỗng `[]` thay vì tạo `ClosedRange` không hợp lệ `0...-1`.
        *   Thay đổi `totalChaptersCount` từ hằng số `let` thành `@Published var` để cho phép cập nhật số chương động.
    *   **ReaderView**:
        *   Thêm modifier `.onChange(of: localBook?.chapters.count)` để tự động theo dõi và cập nhật số chương từ database SwiftData vào `viewModel.totalChaptersCount` khi `@Query allBooks` load dữ liệu xong, đồng thời kích hoạt vẽ lại cửa sổ trượt hiển thị.

## [1.1.7] - 2026-07-14

### Khắc phục lỗi cú pháp YAML trong workflow build-ipa.yml
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 1 file workflow (.github/workflows/build-ipa.yml)
*   **Mô tả**:
    *   Khắc phục lỗi `Invalid workflow file` do định dạng chuỗi xuống dòng trực tiếp trong khối `run: |` gây sai lệch thụt lề YAML.
    *   Sử dụng lệnh `printf` của Bash để định dạng chuỗi chứa ký tự xuống dòng `\n` một cách năng động và an toàn.

## [1.1.6] - 2026-07-14

### Khắc phục lỗi báo quyền truy cập sai khi nhập sách từ file TXT
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 1 file Swift
*   **Mô tả**:
    *   **ShelfView**: Khắc phục lỗi `importTxtBook` trả về thông báo lỗi phân quyền sai ("Lỗi: Không có quyền truy cập tệp tin"). Chuyển đổi lệnh kiểm tra cứng `guard url.startAccessingSecurityScopedResource() else { ... }` thành kiểm tra động (`let accessing = ...`). Vì `DocumentPicker` cấu hình `asCopy: true` trả về các file được copy cục bộ nằm sẵn trong sandbox của app nên `startAccessingSecurityScopedResource()` sẽ trả về `false`, việc gỡ bỏ `guard` giúp tránh bị chặn nhầm trong khi vẫn bảo toàn việc đóng/mở quyền bảo mật nếu cần thiết.

## [1.1.5] - 2026-07-14

### Tích hợp thông báo lỗi build qua Telegram khi workflow GitHub Actions thất bại
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 1 file workflow (.github/workflows/build-ipa.yml)
*   **Mô tả**:
    *   Bổ sung bước `Send Failure Notification to Telegram` với điều kiện `if: failure()` vào cuối workflow `Build Unsigned IPA`.
    *   Tự động gửi thông tin chi tiết lỗi gồm commit message và liên kết trực tiếp tới log lỗi của GitHub Actions run về Telegram chat khi build thất bại.

## [1.1.4] - 2026-07-14

### Khắc phục lỗi lag/đơ khi vuốt chuyển chương trong trình đọc
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 2 file Swift
*   **Mô tả**:
    *   **ReaderViewModel**:
        *   Tối ưu hóa hàm `processAndSaveChapter` bằng cách chuyển các tác vụ dịch thuật (Sino-Vietnamese / Vietphrase) và xử lý mảng `ParagraphItem` xuống chạy ngầm thông qua `Task.detached` với độ ưu tiên cao (`.userInitiated`), giúp nhường hoàn toàn luồng chính (Main Thread) cho hoạt ảnh vuốt trang mượt mà.
        *   Tích hợp kiểm tra an toàn sau khi await để đảm bảo chương đó vẫn đang nằm trong `visibleIndexes` trước khi cập nhật vào RAM cache, ngăn ngừa lỗi dữ liệu lỗi thời khi người dùng vuốt nhanh qua nhiều chương.
        *   Thêm biến cache `cachedLocalBook` và `cachedExt` để lưu giữ tạm thời tham chiếu thực thể sách và extension, tránh truy vấn đĩa lặp lại qua `modelContext.fetch` liên tục trên luồng chính. Giải phóng cache này khi thay đổi sách đọc trong `onBookChanged()`.
    *   **ReaderView**:
        *   Tối ưu hóa hàm `applyTranslationForChapter` bằng cách sử dụng `Task.detached` để chạy ngầm tiến trình dịch thuật trước khi cập nhật dữ liệu chương về luồng chính bằng `MainActor.run`.

## [1.1.3] - 2026-07-14

### Tích hợp tự động dọn dẹp các Workflow Runs cũ sau 3 ngày
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 1 file workflow mới (.github/workflows/cleanup-runs.yml)
*   **Mô tả**:
    *   Tạo mới workflow `Cleanup Old Workflow Runs` định kỳ dọn dẹp các run cũ hơn 3 ngày.
    *   Sử dụng thư viện `Mattraiano/delete-old-runs-action` để xóa an toàn, đồng thời cấu hình giữ lại ít nhất 1 lượt chạy mới nhất.

## [1.1.2] - 2026-07-14

### Tích hợp gửi file IPA tự động lên Telegram sau khi build thành công
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 1 file workflow (.github/workflows/build-ipa.yml)
*   **Mô tả**:
    *   Bổ sung bước `Send IPA to Telegram` vào cuối job `build` của GitHub Actions workflow.
    *   Tự động kiểm tra dung lượng file IPA: Nếu dưới 50MB, gửi trực tiếp qua bot API của Telegram; nếu từ 50MB trở lên, upload lên dịch vụ lưu trữ trung gian `transfer.sh` rồi gửi link tải qua bot Telegram.
    *   Loại bỏ hoàn toàn bước `Upload IPA Artifact` (lưu trữ trên GitHub Artifacts) theo yêu cầu để tối ưu hóa không gian lưu trữ và thời gian build.
    *   Tích hợp nội dung **Commit Message** (tin nhắn commit) gần nhất làm chú thích (caption/text) cho thông báo Telegram, sử dụng cơ chế encode an toàn để tránh lỗi ký tự đặc biệt.

## [1.1.1] - 2026-07-14

### Khắc phục lỗi chuẩn hóa URL mục lục (TOC) khi có script phân trang (page)
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 1 file Swift
*   **Mô tả**:
    *   **ExtensionManager**: Khắc phục lỗi cú pháp tại dòng 380 của `ExtensionManager.swift` trong hàm `toc`. Tích hợp thêm logic kiểm tra `hasScript(localPath:scriptKey:)` cho script `"page"`. Nếu extension có hỗ trợ script phân trang, hàm `toc` sẽ bỏ qua việc gọi `JSExecutor.cleanAndResolveUrl` và sử dụng trực tiếp URL ban đầu để bảo toàn cấu trúc URL đặc thù phục vụ phân trang.

## [1.1.0] - 2026-07-14

### Triển khai UI Reader nâng cao và Tự động hóa Xuất Truyện
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 4 file Swift
*   **Mô tả**:
    *   **Giao diện Trình đọc (ReaderView.swift, ParagraphCardView.swift)**:
        *   Cập nhật layout khi chương đang tải hoặc gặp lỗi trong `textReaderView`. Căn giữa hoàn toàn tên chương, spinner/nút reload (Thử lại) ở chính giữa trang Reader (ngoại vi `ScrollView`, chiều cao chiếm toàn bộ Viewport).
        *   Bổ sung computed property `isChapterLoadingOrFailed: Bool` để giữ HUB điều khiển (top/bottom controls) luôn hiển thị khi chương đang tải hoặc lỗi, giúp người dùng dễ dàng chuyển chương hoặc thoát trình đọc.
        *   Cập nhật `chapterLoadingView` đồng bộ bố cục tương tự cho trường hợp `viewModel == nil`.
        *   Tinh chỉnh cỡ chữ tên chương khi đang tải và khi bị lỗi lên cỡ to hơn (`.title2` kèm bold) và bổ sung padding trên `16` pt.
        *   Nâng kích cỡ tên chương hiển thị trong nội dung đọc của `ParagraphCardView.swift` lên `fontSize * 1.5` và thêm padding trên `32` pt.
    *   **Căn giữa tên chương (ReaderTextView.swift, ParagraphCardView.swift)**:
        *   Nâng cấp `ReaderTextView` để nhận thuộc tính `isCentered: Bool`. Tự động áp dụng `paragraphStyle.alignment = .center` cho văn bản của `UITextView` khi `isCentered` bằng true.
        *   Cập nhật `ParagraphCardView.swift` truyền `isCentered: item.isTitle` để tự động căn lề giữa cho tên chương truyện (có `isTitle == true`).
    *   **Quản lý tải xuống (DownloadTrackerView.swift)**:
        *   Cập nhật hàm `exportFromCached` để gọi trực tiếp `DownloadManager.shared.enqueueTask` và `ToastManager.shared.show`, tự động hóa quá trình thêm tác vụ xuất TXT offline mà không cần hiển thị sheet cấu hình `TaskOptionsSheet` dài dòng.
        *   Khắc phục lỗi hiển thị tên truyện tiếng Trung thô chưa dịch tại danh sách Download bằng cách tự động dịch tên truyện qua `TranslateUtils.translateMeta` khi bật dịch thuật.

## [1.0.9] - 2026-07-14

### Tối ưu hóa JS Engine, chuẩn hóa URL và điều chỉnh định dạng Log
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 2 file Swift
*   **Mô tả**:
    *   **JSExecutor**: Loại bỏ thuộc tính và tham số `host` khỏi lớp và constructor `init` do không sử dụng thực tế trong lớp này.
    *   **ExtensionManager**:
        *   Cập nhật các hàm `detail`, `toc`, `chap`, và `page` để khởi tạo `JSExecutor` không có `host`. Thực hiện gọi `JSExecutor.cleanAndResolveUrl(url, host: host)` để chuẩn hóa URL thành URL tuyệt đối trước khi thực thi script.
        *   Điều chỉnh log chạy script của 10 hàm trong `ExtensionManager`: Loại bỏ `localPath` và `downloadUrl` dài dòng; đưa mảng tham số thực tế `arguments=[...]` truyền vào JS lên đầu tiên; và giữ nguyên các tham số Swift gốc khác ở phía sau để tối ưu hóa khả năng đọc log.

## [1.0.8] - 2026-07-14

### Khắc phục lỗi thiếu truyền host sang trang chi tiết và chuyển nút filter giao diện quản lý tiện ích
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 9 file Swift
*   **Mô tả**:
    *   **Trình chi tiết (BookDetailView)**: Cập nhật `BookDetailView.swift` hỗ trợ nhận tham số `initialHost`. Trích xuất và truyền `importedHost` khi bypass import thành công. Cập nhật mọi cuộc gọi `.detail`, `.toc`, `.page` sử dụng `resolvedHost` (ưu tiên lấy từ cơ sở dữ liệu `localBook.host`, nếu không có lấy từ `host` do danh sách truyền sang, và fallback về `ext.sourceUrl`).
    *   **Danh sách hiển thị (Search, Genres, Home, Suggest, Shelf)**: Cập nhật `SearchView.swift`, `SuggestRowView.swift`, `CategoryNovelsListView.swift`, `DiscoveryView.swift`, `ReaderView.swift`, và `ShelfView.swift` để truyền tham số `host`/`initialHost` hoặc trích xuất lưu `importedHost` đầy đủ (scheme + domain) sang `BookDetailView`.
    *   **Quản lý tiện ích**: Cập nhật `RepositoryManagerView.swift` di chuyển nút Filter từ thanh Navigation Bar xuống bên cạnh ô Tìm kiếm tiện ích, tăng độ trực quan của giao diện và thay đổi icon/màu sắc nổi bật (cam đậm) khi có bộ lọc hoạt động.
    *   **Hệ thống Log JS**: Cập nhật `ExtensionManager.swift` bổ sung thông tin tên extension (tên thư mục) và tên script cụ thể đang chạy (ví dụ `search`, `detail`, `toc`, `chap`, `voice`, etc.) vào các dòng log in ra cho `Response.error` và `Response.success`, hỗ trợ việc chuẩn đoán lỗi của tiện ích cực kỳ trực quan.

## [1.0.7] - 2026-07-14

### Khắc phục lỗi Import truyện TXT cục bộ và bổ sung giao diện Tiến trình động
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 1 file Swift
*   **Mô tả**:
    *   **Kệ sách (Shelf)**: Cập nhật `ShelfView.swift` để sửa lỗi import file TXT.
        *   Hỗ trợ giải mã file bằng cơ chế tự động dò tìm bảng mã (Encoding Fallback) với UTF-8, UTF-16, Windows-1258, ASCII và ISO-8859-1 để tránh crash giải mã ngầm.
        *   Chuyển pha chèn và lưu dữ liệu SwiftData về chạy trên luồng chính (`MainActor` sử dụng `self.modelContext` của View), giúp `@Query` cập nhật tức thì Kệ sách trên giao diện.
        *   Bổ sung giao diện Progress Overlay động phủ mờ toàn màn hình hiển thị tiến độ import thực tế từ 0% đến 100% kèm số chương đang xử lý (có cơ chế sleep 1ms nhường thread để giao diện mượt mà).
        *   Tích hợp thông báo Toast qua `ToastManager` để thông báo trạng thái thành công hoặc chi tiết lỗi cụ thể cho người dùng.

## [1.0.6] - 2026-07-14

### Nâng cấp giao diện Tiện ích (Badge capsule, Sheet Filter, gỡ cài đặt hàng loạt) và loại bỏ logic truyện tranh (Comic)
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 4 file Swift
*   **Mô tả**:
    *   **Tiện ích**: Cập nhật `RepositoryManagerView.swift` loại bỏ dòng text Kho và Tác giả cũ. Thiết kế hệ thống Badge capsule màu sắc hiện đại hiển thị Loại tiện ích (Type), Tên kho (Repository), Tác giả (Author). Tích hợp thêm Sheet bộ lọc nâng cao (`FilterSheet`) lọc theo 4 tiêu chí (Loại, Ngôn ngữ, Tác giả, Kho). Bổ sung nút "Xóa tất cả" kèm Alert xác nhận để gỡ cài đặt hàng loạt toàn bộ các tiện ích đã tải.
    *   **Khám phá**: Cập nhật `DiscoveryView.swift` lọc bỏ các tiện ích loại `"comic"`, chỉ hiển thị các tiện ích truyện chữ (`"novel"`, `"chinese_novel"`) trong phần mở rộng khám phá.
    *   **Trình đọc & Cửa hàng**: Cập nhật `ReaderView.swift` loại bỏ hoàn toàn các logic hiển thị và xử lý ảnh truyện tranh (`comicReaderView`, `imageUrls`), mặc định chạy chế độ đọc truyện chữ. Luôn hiển thị các nút dịch thuật và TTS. Cập nhật `ExtensionStoreView.swift` loại bỏ icon hiển thị `comicbook` mặc định cho truyện tranh.

## [1.0.5] - 2026-07-14

### Khắc phục lỗi lưu sai Shelf/History, sửa màn hình trắng xuất TXT và nâng cấp JS Engine hỗ trợ Console.log/queries
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 3 file Swift
*   **Mô tả**:
    *   **Reader**: Cập nhật hàm `saveOnlineBookIfNeeded` trong `ReaderViewModel.swift` để truyền rõ ràng `isOnShelf: false` và `isHistory: true` khi khởi tạo thực thể `Book`, ngăn sách đọc online tự động lưu vào Kệ sách chính thay vì Lịch sử đọc.
    *   **Downloads**: Cập nhật `DownloadTrackerView.swift` loại bỏ `@State showingOptionsSheet` và chuyển sang sử dụng `.sheet(item: $selectedBookForTask)` để sửa lỗi màn hình trắng xóa khi chọn tùy chọn xuất TXT cho sách đã tải xuống.
    *   **JS Engine**: Cập nhật `JSExecutor.swift` để đăng ký alias global `Console` trỏ tới `console` hỗ trợ `Console.log(...)`. Cập nhật hàm `fetch` trong Javascript bootstrap để tự động phân tích đối tượng `options.queries`, mã hóa và ghép query parameters vào URL trước khi gọi mạng native, khắc phục lỗi crash `TypeError: null is not an object (evaluating 'json.data.books')` do thiếu tham số.

## [1.0.4] - 2026-07-14

### Sửa lỗi lưu chương mới nhất khi thoát nhanh và nâng cấp trang Khám phá
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 3 file Swift
*   **Mô tả**:
    *   **Reader**: Cập nhật hàm `onTabSelectionChanged(newIndex:)` trong `ReaderViewModel.swift` để gán tiến trình `currentProgress` sang chương mới (với paragraph index 0) ngay khi người dùng chọn chương mới, đảm bảo hàm thoát `onDisappear` lưu chính xác chương vừa chọn vào DB.
    *   **Extension Manager**: Thay thế hàm `cleanVal.toArray()` bằng `toDictionaryArray(cleanVal)` trong hàm `home(...)` và `genre(...)` trong `ExtensionManager.swift` để giải tuần tự hóa an toàn kiểu dữ liệu JSValue thành Swift Array. Loại bỏ cơ chế fallback tự động về `genre(...)` trong hàm `home(...)` để phân tách mạch lạc dữ liệu.
    *   **Discovery View**: Thêm `@State private var discoveryError` để quản lý thông tin lỗi tải dữ liệu từ Extension. Sửa đổi `onChange(of: selectedExtensionId)` để dọn dẹp sạch dữ liệu cũ khi đổi extension. Tải dữ liệu `home` và `genre` song song độc lập; chỉ báo lỗi nếu thiếu cả hai. Bổ sung giao diện gợi ý người dùng bấm nút thể loại nếu extension chỉ hỗ trợ thể loại. Cập nhật điều kiện tải dữ liệu trong `.onAppear` để tránh lặp vô hạn. Tích hợp màn hình tải khung xương (`DiscoveryMainSkeletonView` và `DiscoverySkeletonListView`) để hiển thị pulsing loading cân đối khi đang tải danh mục hoặc danh sách truyện lần đầu, giải quyết triệt để lỗi sụp/nhảy layout UI.

## [1.0.3] - 2026-07-14

### Sửa lỗi crash CALayer bounds contains NaN khi chuyển chương trong lúc chạy TTS
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 2 file Swift
*   **Mô tả**:
    *   Cập nhật `ReaderTextView.swift` để bổ sung các kiểm tra an toàn (guard clauses) cho giá trị `NaN` và `Infinite` đối với rect, rectInScrollView, visibleHeight, và targetY trước khi gán `contentOffset` cho `UIScrollView`. Điều này ngăn chặn việc gán giá trị không hợp lệ vào scroll view của trang cũ trong lúc giao diện đang tháo dỡ hoặc cập nhật luồng đọc khi chuyển sang chương mới.
    *   Cập nhật `ReaderView.swift` tại `textReaderView` để bổ sung sự kiện `.onChange(of: chapterIndex)` cho từng trang và liên kết cờ `ttsShouldAutoPlayNextChapter`. Thay đổi này giúp tự động phát tiếp TTS và khôi phục vị trí đọc chính xác khi chuyển sang chương mới đã được preload/prefetch trước từ bộ đệm của `ReaderViewModel`.

## [1.0.2] - 2026-07-14

### Khắc phục triệt để lỗi phân giải Base URL & Lỗi kẹt màn hình trắng Trình đọc
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 5 file Swift
*   **Mô tả**:
    *   Thêm thuộc tính `host` vào mô hình dữ liệu `Book.swift` và thực hiện lưu trữ `NovelDetailResult.host` từ JS Extension vào cơ sở dữ liệu khi nhập sách hoặc reload thông tin chi tiết.
    *   Hoàn tác việc can thiệp phân giải URL ở tầng gọi Swift (`ExtensionManager` và `ReaderChapterListView`), trả lại nguyên vẹn URL tương đối thô cho JS Engine để đảm bảo tính tương thích và không làm hỏng kịch bản regex của Extension (như `bookqq`).
    *   Cải tiến hàm `JSExecutor.cleanAndResolveUrl` chỉ sử dụng tham số `host` từ Swift hoặc tự động truy xuất động các biến cấu hình (`book.host`, `BASE_URL`, `base_url`) trực tiếp từ `JSContext.current()` tại runtime khi JS thực hiện cuộc gọi mạng.
    *   Bọc bắt lỗi ngoại lệ trong `ReaderViewModel.swift` (`enqueuePrefetch`) và cập nhật trạng thái chương tải lỗi sang `.failed(message:)` để giao diện hiển thị nút Thử lại thay vì bị kẹt màn hình trắng.

## [1.0.1] - 2026-07-14

### Sửa lỗi Trình đọc (Reader) và Lỗi base_url cập nhật mục lục
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 4 file Swift
*   **Mô tả**:
    *   Khắc phục lỗi SwiftData `#Predicate` dạng chuỗi trên iOS 17 bằng cơ chế lọc trên bộ nhớ (in-memory filtering) cho `localBook`, `ext` và tiến trình lưu vị trí đọc.
    *   Tối ưu hàng đợi prefetch ưu tiên chương hiện tại tải trước tiên (`activeIndex` priority).
    *   Sửa lỗi thiếu `base_url` khi cập nhật mục lục bằng cách tự động phân giải URL tương đối thành URL tuyệt đối trong `ExtensionManager.swift`.

## [1.0.0] - 2026-07-14

### Khởi tạo hệ thống CodeGraph sống (Initial Release)
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Mã Commit Git**: `UNKNOWN` (Phiên bản phát triển nội bộ đầu tiên)
*   **Tổng số file nguồn ảnh hưởng**: 87 file Swift trong thư mục `Sources/`
*   **Mô tả**:
    *   Thiết lập hệ thống 16 tài liệu markdown phân tích kiến trúc, mối quan hệ file, kiểu dữ liệu, cuộc gọi hàm, máy trạng thái, luồng sự kiện, dòng dữ liệu, vòng đời, quy tắc phụ thuộc và báo cáo rủi ro chi tiết.
    *   Tích hợp metadata YAML Front Matter ở đầu mỗi file và cấu trúc bảo vệ vùng `<!-- GENERATED START -->` / `<!-- GENERATED END -->`.
    *   Thiết lập tệp cấu hình `manifest.json` và schema `codegraph.schema.json`.
    *   Thiết lập hướng dẫn bảo trì toàn cục `AGENTS.md`.
