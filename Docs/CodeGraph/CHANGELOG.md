# CHANGELOG - Nhật ký Thay đổi CodeGraph FreeBook

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **FreeBook**.

---

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
        *   `ttsChaptersQueue`: truyền `host` từ `Chapter.host` / `ChapterResult.host` vào `TTSChapterInfo`.
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
