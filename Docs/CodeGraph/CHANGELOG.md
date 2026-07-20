# CHANGELOG - Nhật ký Thay đổi CodeGraph FreeBook

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **FreeBook**.

---

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
  * Đồng bộ hóa thuộc tính computed `currentChapterHost` và `ttsChaptersQueue` để sử dụng dữ liệu đã cache trong `viewModel.getSortedChapters()`, loại bỏ hoàn toàn hiện tượng giật lag/khựng khi chuyển tiếp từ Kệ sách/Lịch sử vào Trình đọc đối với truyện lớn (~2000 chương).
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
  * Thêm `@State chapterListDragOffset` để theo dõi khoảng cách kéo real-time.
  * Giảm height từ `geometry.size.height` xuống `geometry.size.height - 60` (topPeek = 60pt) để lộ dải reader phía trên.
  * Offset y = `max(60, 60 + chapterListDragOffset)` khi đang mở, panel trượt theo ngón tay mượt mà.
  * Kéo > 120pt → đóng bằng `.easeInOut`; kéo chưa đủ → nảy về vị trí cũ bằng `.spring`.
  * Truyền `onDragChanged` và `onDragEnded` xuống `ReaderChapterListView`.
* **ReaderChapterListView**:
  * Thêm callbacks `onDragChanged` và `onDragEnded` (optional, mặc định nil).
  * Cập nhật `dismissGesture`: `.onChanged` gọi `onDragChanged`, `.onEnded` gọi `onDragEnded` thay vì trực tiếp `onClose`.
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
