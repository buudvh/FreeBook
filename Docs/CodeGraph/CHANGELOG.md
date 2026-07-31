# CHANGELOG - Nhật ký Thay đổi CodeGraph FreeBook

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **FreeBook**.

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
