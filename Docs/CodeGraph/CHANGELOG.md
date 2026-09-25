# CHANGELOG - Nhật ký Thay đổi CodeGraph FreeBook

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **FreeBook**.

## [1.3.398] - 2026-09-25

### feat: nang cap toan dien giao dien ai, giu chuong da tai va session khi doi nguon, ghim khong dong sheet va toi uu icon header

Thêm **4** file Swift mới, sửa **18** file Swift trong `Sources/Models/`, `Sources/Services/`, `Sources/Views/`, `Sources/Common/`:

- **Di Trú Dữ Liệu Đổi Nguồn Sách (`BookSourceMigrator.swift`, `SearchView.swift`, `AIChatHistoryStore.swift`, `BookAIMemoryStore.swift`, `TranslationManager+BookScopedFiles.swift`)**:
  - Tạo actor `BookSourceMigrator`: sao chép toàn bộ chương đã tải (`BookBinManager` + `ChapterStore`), chuyển lịch sử chat AI (`AIChatHistoryStore.migrateSessions`), chuyển bộ nhớ AI (`BookAIMemoryStore.migrateMemory`), copy cấu hình dịch (`TranslationConfigStore.setBookOverride`), và dọn dẹp an toàn file `.bin` cũ nếu không phát TTS.
  - Bổ sung `QuickTranslateEngineConfig.json` vào `bookScopedMigrationFiles`.
  - Giảm kích thước `SearchView.swift` từ 868 xuống 858 dòng (dưới baseline 872).
- **Tái Cấu Trúc Toàn Diện Giao Diện AI (`ReaderAIFullScreenView.swift`, `ReaderAIInputBarView.swift`, `ReaderAINameReviewCardView.swift`, `ReaderAISessionListView.swift`, `AIBookDataInspector.swift`, `AIHarnessMode.swift`)**:
  - Header: nút back tròn `chevron.down`, tiêu đề hiển thị tên session 1 dòng dưới "Trợ lý AI", menu dropdown `ellipsis.circle` gom các nút tính năng.
  - Đổi màu chủ đạo phân hệ AI sang tone slate navy `#242c38`.
  - Tin nhắn AI loại bỏ icon sparkles, text căn lề trái. Thanh nhập gom mode 1 hàng (`Manual`, `Plan`, `Bypass`) và phóng to nút gửi 36x36.
  - Thẻ trích xuất tên riêng kiểm tra chéo cả từ điển riêng và chung (`Names.dat`, `VietPhrase.dat`), tự động bỏ chọn mặc định nếu đã có từ trước, đồng bộ màu badge NE (đỏ) và VP (xanh nhạt), nút lưu 1 hàng không icon tone `#242c38`.
- **Mở Rộng Bộ Nhớ Truyện AI (`BookAIMemory.swift`, `BookAIMemoryStore.swift`, `BookAIMemorySheet.swift`, `ReaderAIFullScreenView+Actions.swift`)**:
  - Hỗ trợ lưu trữ nhân vật/bối cảnh, tóm tắt cốt truyện, snapshot từ điển và ghi chú riêng. Tự động đồng bộ thầm lặng khi khởi tạo phiên chat.
- **Trang Chủ Bypass WebView & Quản Lý Lịch Sử Duyệt Web (`BypassBrowserHomeView.swift`, `BrowserHistoryStore.swift`, `BrowserHistorySheetView.swift`, `BypassBrowserTabStore.swift`, `BypassWebView.swift`)**:
  - Trang chủ dark theme native dạng lưới 4x3 phân trang cho domain phổ biến, kèm 10 mục lịch sử gần đây và sheet quản lý/tìm kiếm lịch sử.
- **Tối Ưu Kệ Sách & Danh Sách Chương Reader (`BookActionSheet.swift`, `BookActionRunner.swift`, `ReaderChapterListView.swift`, `ReaderChapterListStore.swift`, `ReaderHeaderFooterOverlayView.swift`, `BookDetailView+Extensions.swift`, `ReaderView.swift`)**:
  - Giữ mở context menu sau khi ghim truyện ở Kệ sách.
  - Tự động làm mới danh sách chương trong Reader khi hoàn tất dịch lại tiêu đề.
  - Thu nhỏ icon header về 13pt (chỉ thu nhỏ hàng trên cùng cùng hàng nút back ở Reader).
  - Sửa vòng lặp loading vô hạn khi ấn Back từ màn hình Đổi nguồn Reader mà không chọn nguồn mới.

## [1.3.397] - 2026-09-24

### fix: sua loi reader load lai khi dong ai va mat tin nhan khi mo lai tu widget

Sửa **5** file Swift trong `Sources/Views/Reader/AI/`, `Sources/Views/Reader/Extensions/`, `Sources/Views/Reader/`:

- **Khôi Phục Toàn Màn Hình Native Trong Reader & Bảo Toàn Skeleton Handshake (`ReaderView.swift`, `ReaderView+AI.swift`, `AIRuntimeCoordinator.swift`)**:
  - Khôi phục `.fullScreenCover(isPresented: $showingAIFullScreen)` của SwiftUI ngay tại `ReaderView` thay cho modal UIKit `.fullScreen`. Cây view `ReaderView` không bị unmount khỏi Window, không bị trigger lại lifecycle, bảo toàn cổng handshake skeleton loading (`isChapterSubtreeRenderable`) $\rightarrow$ text hiển thị tức thì, không kẹt skeleton loading hay reload lại khi đóng AI.
  - Quản lý cờ `isReaderActive` trong `onAppear`/`onDisappear` của `ReaderView`. Khi người dùng ở trong Reader mà bấm mở lại từ Floating Widget thu nhỏ, `AIRuntimeCoordinator` phát notification `reopenReaderAI` để `ReaderView` mở lại qua `.fullScreenCover`. Khi mở từ ngoài Reader (Kệ sách, Khám phá), Coordinator dùng `modalPresentationStyle = .overFullScreen` để không làm mất ViewController bên dưới.
- **Lưu Đĩa Tức Thì & Nguồn Sự Thật Duy Nhất Cho Chat AI (`AIRuntimeCoordinator.swift`, `ReaderAIFullScreenView.swift`, `ReaderAIFullScreenView+Actions.swift`)**:
  - Ghi đĩa tức thì qua `AIChatHistoryStore.shared.saveSession` ngay tại khoảnh khắc khởi tạo tin nhắn người dùng và tin nhắn chờ của AI (áp dụng cho gõ tay, chip Tóm tắt, Bối cảnh, Dịch mượt, Lọc name chương, Quét batch).
  - Quản lý `activeSession: AIChatSession?` làm Source of Truth trong `AIRuntimeCoordinator.shared`. Tích luỹ token stream và kết quả trích xuất vào `activeSession` xuyên suốt quá trình chạy ngầm.
  - Khi mở lại AI từ widget, `initializeSession()` ưu tiên nạp ngay `activeSession` của Coordinator (nếu trùng `bookId`), đồng thời đồng bộ reactive các token delta và tiến trình batch qua Combine `$activeSession`, `$isRunning`, `$batchProgress`.

## [1.3.396] - 2026-09-24

### feat: dong bo ai dang suy nghi, chay ngam toan app va floating widget thu nho

Thêm **5** file Swift mới, sửa **5** file Swift trong `Sources/Views/Reader/AI/`, `Sources/Views/Reader/Extensions/`, `Sources/Views/Reader/`, `Sources/App/`:

- **Điều Phối Vòng Đời Tác Vụ Ngầm & Toast Hoàn Thành (`AIRuntimeCoordinator.swift`)**:
  - Tạo `AIRuntimeCoordinator` quản lý `Task` chạy ngầm độc lập khỏi vòng đời View cho streaming chat, lọc name chương hiện tại và quét batch các chương đã tải.
  - Tự động nạp/lưu phiên chat vào `AIChatHistoryStore` và phát thông báo Toast qua `ToastManager.shared.show(..., type: .success)` khi tác vụ hoàn tất ở trạng thái ngầm (khi màn hình AI đang đóng).
  - Cung cấp cơ chế `presentFullScreen(context:)` thông qua việc tìm `findTopViewController()` ở tầng window `.normal`, cho phép mở lại màn hình AI toàn màn hình từ bất kỳ đâu (Shelf, Reader, BookDetail, Settings) mà không phụ thuộc vào `ReaderView` và không bị xung đột modal.
- **Cửa Sổ & Widget Nổi Toàn Ứng Dụng (`AIFloatingWidgetWindowManager.swift`, `AIFloatingWidgetUIWindow.swift`, `AIFloatingWidgetContainerViewController.swift`, `AIFloatingWidgetView.swift`)**:
  - `AIFloatingWidgetUIWindow`: `UIWindow` riêng biệt có windowLevel `alert - 3` (thấp hơn TTS `alert - 1` và Browser `alert - 2` một bậc để tránh tranh chấp hit-testing, đảm bảo chạm vào TTS widget luôn được ưu tiên).
  - Passthrough touch chuẩn xác cho các điểm chạm ngoài viên pill để không chặn thao tác giao diện bên dưới.
  - `AIFloatingWidgetContainerViewController`: Quản lý cử chỉ `UIPanGestureRecognizer` và `UITapGestureRecognizer`, snap mượt mà vào mép màn hình bằng `FloatingWidgetGeometry` và lưu vị trí người dùng kéo vào `UserDefaults`. Chạm vào widget kích hoạt mở lại toàn màn hình AI.
  - `AIFloatingWidgetView`: Viên pill mờ (`.ultraThinMaterial`) với viền tím tinh tế, icon `sparkles` tím animated, text trạng thái tiến trình và nút tròn `xmark` huỷ tác vụ nhanh.
- **Đồng Bộ Chỉ Báo "AI đang suy nghĩ" & Đóng An Toàn Khi TTS Điều Hướng (`ReaderAIFullScreenView.swift`, `ReaderAIFullScreenView+Actions.swift`, `ReaderView.swift`, `ReaderView+AI.swift`)**:
  - Khởi tạo tin nhắn phản hồi với `content: ""` và `isStreaming: true` cho mọi thao tác (gõ tay, chip Tóm tắt, Bối cảnh, Dịch mượt, Lọc name chương, Lọc name cả bộ tải) -> luôn hiển thị động `ReaderAIThinkingIndicatorView` với text đồng nhất `"AI đang suy nghĩ"`.
  - Lắng nghe sự kiện điều hướng từ TTS Widget (`openCurrentlyPlayingReader`, `navigateReaderToPlayingChapter`) để tự động đóng màn hình AI an toàn, nhường quyền điều hướng cho Reader mà không làm gián đoạn tác vụ AI đang chạy ngầm.
  - Chuyển `onOpenAI` trong `ReaderView` sang `openAIFromReader()`, loại bỏ modal `.fullScreenCover` cục bộ giúp giảm dòng code trong `ReaderView.swift` (từ 2049 xuống 2042 dòng, dưới baseline 2053).

## [1.3.395] - 2026-09-24

### feat: sua loi nut dich kham pha khi chuyen nguon trung viet

Sửa **4** file Swift trong `Sources/Services/Translation/Utils/`, `Sources/Views/Reader/`, `Sources/Views/Discovery/`, `Sources/Views/BookDetail/`:

- **Khắc Phục Vòng Đời Nút Dịch Khám Phá (`ReaderTranslationScopeMenuView.swift`, `DiscoveryView.swift`, `BookDetailView.swift`)**:
  - `ReaderTranslationScopeMenuView`: Bổ sung tham số `isChineseSourceHint: Bool?` và hai bộ lắng nghe `.onChange(of: packageId)`, `.onChange(of: bookId)` để kích hoạt `refreshStatus()` ngay khi nguồn hoặc truyện thay đổi.
  - `DiscoveryView`: Gán `.id("discovery-translate-\(selectedExtensionId)")` cho nút dịch trên toolbar để SwiftUI tái khởi tạo view tương ứng với nguồn mới; truyền `isChineseSourceHint: selectedExtension?.isChineseSource`.
  - `BookDetailView`: Đồng bộ truyền `isChineseSourceHint: ext?.isChineseSource` vào `ReaderTranslationScopeMenuView` và các lời gọi `isTranslationEnabled`.
- **Nâng Cấp Cache & Cơ Chế Dò Nguồn Tiếng Trung (`TranslationConfigStore.swift`)**:
  - Thêm bộ nhớ đệm `sourceIsChineseMap` cùng phương thức `registerSource(packageId:isChinese:)` giúp tra cứu trạng thái nguồn O(1).
  - Tối ưu hàm `isChineseSource`: tìm kiếm đệ quy thư mục con cấp 1 trong thư mục extension khi file zip giải nén vào folder con lồng nhau; hỗ trợ trích xuất `type`, `locale`, `language` từ cả đối tượng `metadata` lẫn root `plugin.json`.
- **Cập Nhật Tức Thì Trạng Thái Dịch Thẻ Truyện (`DiscoveryView.swift`)**:
  - Cập nhật cờ `isTranslationEnabled` ngay khi đổi nguồn hoặc nhận thông báo cấu hình dịch thay đổi, giúp các thẻ truyện hiển thị tên dịch tức thì mà không cần tải lại mạng.

## [1.3.394] - 2026-09-24

### feat: dong bo popup dich mau trang, toi uu danh sach chuong va do mo chuong da doc

Sửa **9** file Swift trong `Sources/Models/Database/`, `Sources/Services/Translation/Utils/`, `Sources/Views/Reader/`, `Sources/Views/BookDetail/`, `Sources/Views/Discovery/`:

- **Popover Cấu hình Dịch Thuật Tone Trắng Tối Giản (`ReaderTranslationScopeMenuView.swift`, `DiscoveryView.swift`, `BookDetailView.swift`)**:
  - Viết lại nút dịch thành Popover nhỏ gọn với `.presentationCompactAdaptation(.popover)`, giao diện `.preferredColorScheme(.dark)`.
  - Thay đổi toàn bộ nút điều khiển sang tone màu TRẮNG (`.white`), toggle switch sử dụng `.tint(.white)`, nút Lưu lại viền trắng tối giản thay cho màu xanh primary mặc định.
  - Tích hợp đồng nhất Popover dịch tại thanh công cụ của Reader, Chi tiết truyện (`BookDetailView`) và màn hình Khám phá (`DiscoveryView`).
- **Tối ưu Danh Sách Chương & Độ Mờ Chương Đã Đọc (`ReaderChapterListView.swift`, `ReaderChapterListView+List.swift`, `ReaderChapterRowView.swift`, `BookDetailTOCView.swift`)**:
  - Tách huy hiệu nguồn/extension (`Local` / `Extension`) thành một hàng riêng biệt phía trên số chương trong danh sách chương Reader.
  - Thêm nút icon chuyên dụng "Dịch lại chương" (`character.bubble` màu trắng) trên Header cạnh nút đảo chiều để dịch lại toàn bộ tiêu đề chương và xóa cache hiển thị khi người dùng yêu cầu.
  - Làm mờ tiêu đề các chương đã đọc (`logicalIndex < currentChapterIndex` hoặc `chap.index < currentIdx`) với độ mờ `opacity: 0.40` ở cả danh sách chương Reader và Chi tiết truyện.
- **Tối ưu Hiển Thị Khi Bật Tắt Dịch Trong Reader (`ReaderView.swift`)**:
  - Bỏ việc kích hoạt `scheduleCoalescedTranslationRefresh` và `retranslateChapterTitles` trong sự kiện `.onChange(of: isTranslationEnabled)` giúp chuyển đổi hiển thị bản dịch tức thì 0ms, không gây reload hay chớp giật.
  - Đồng bộ trạng thái dịch tự động thông qua `NotificationCenter` từ `TranslationConfigStore.didChangeNotification`.
- **Mặc Định Bật Dịch Cho Nguồn Tiếng Trung (`Extension.swift`, `TranslationConfigStore.swift`)**:
  - Thêm computed property `Extension.isChineseSource` nhận diện các nguồn truyện Trung Quốc (`chinese_novel` hoặc locale chứa `zh`/`cn`).
  - `TranslationConfigStore.resolveStatus` tự động mặc định Bật dịch cho nguồn tiếng Trung khi chưa có cấu hình override, các nguồn khác mặc định Tắt dịch.

## [1.3.393] - 2026-09-24

### feat: cau hinh bat tat dich phan cap truyen nguon va toan cuc

Thêm **3** file Swift mới và sửa **8** file Swift trong `Sources/Services/Translation/`, `Sources/Services/TTS/`, `Sources/Views/Reader/`, `Sources/Views/BookDetail/`, `Sources/Views/Settings/`:

- **Quản lý cấu hình dịch phân cấp 3 mức (`TranslationConfigStore.swift`, `TranslateUtils.swift`)**:
  - `TranslationConfigStore`: Quản lý phân cấp 3 tầng rõ ràng: Truyện (`bookOverrides`) > Nguồn truyện (`sourceOverrides`) > Toàn cục (`globalEnabled`). Lưu trữ an toàn trong `UserDefaults` bằng từ điển JSON, không can thiệp schema SwiftData `@Model`.
  - Phân giải ưu tiên `resolveStatus(bookId:packageId:)`: Truyện đặt Bật/Tắt -> Áp dụng cấu hình Truyện; Truyện để Mặc định -> Áp dụng cấu hình Nguồn; Nguồn để Mặc định -> Áp dụng cấu hình Toàn cục.
  - Hỗ trợ thông báo reactive qua `TranslationConfigStore.didChangeNotification`.
- **Menu xổ xuống 1 chạm trên Header Reader & BookDetail (`ReaderTranslationScopeMenuView.swift`, `ReaderHeaderFooterOverlayView.swift`, `BookDetailView.swift`, `BookDetailView+Extensions.swift`)**:
  - Nút Menu Dịch (`character.bubble`) trên Header Reader và Toolbar Chi tiết truyện hiển thị nguồn gốc quyết định (`Truyện này`, `Nguồn này`, `Toàn cục`) kèm chấm tròn chỉ thị màu khi có cấu hình riêng.
  - Chạm mở ngay menu xổ xuống trực quan với 3 sections: Truyện này (Mặc định / Luôn Bật / Luôn Tắt), Nguồn này (Mặc định / Luôn Bật / Luôn Tắt), Toàn cục (Bật / Tắt).
- **Bộ điều khiển 3 mức trong Sheet Cài đặt đọc (`ReaderSettingsView.swift`)**:
  - Bổ sung nhóm điều khiển phân cấp trong mục Cấu hình Dịch Thuật: Picker cho Truyện này, Picker cho Nguồn này, Toggle Toàn cục.
- **Màn hình Quản lý Tập trung cấu hình dịch riêng (`TranslationScopeManagementView.swift`, `SettingsView.swift`)**:
  - Màn hình quản lý danh sách tập trung các nguồn và truyện đã override, cho phép chuyển đổi trạng thái, vuốt xoá từng mục hoặc đặt lại tất cả về mặc định.
  - Tích hợp đường dẫn `NavigationLink` trong Section Dịch Thuật Quick Translate của `SettingsView`.
- **Đồng bộ phân cấp Dịch sang TTS (`TTSManager.swift`)**:
  - Tự động nạp cờ dịch theo phân cấp của cuốn sách đang phát khi khởi chạy phiên đọc (`startWithContent` / `start`) thông qua `TranslationConfigStore.shared.isTranslationEnabled(bookId:packageId:)`.

## [1.3.392] - 2026-09-24

### feat: badge vp ne tu dong bo chon ten da co tu dong luu ai va tat auto sang chuong reader

Sửa **7** file Swift trong `Sources/Models/AI/`, `Sources/Services/AI/`, `Sources/Views/Reader/`, `Sources/Views/Settings/AI/`:

- **Badge VP / NE & Bỏ chọn mặc định tên riêng đã có (`AIExtractedName.swift`, `AIBookDataInspector.swift`, `ReaderAINameReviewCardView.swift`, `ReaderAIFullScreenView+Actions.swift`, `AINameExtractionBatchProcessor.swift`)**:
  - `AIExtractedName`: Thêm hai thuộc tính `hasInBookNames: Bool` và `hasInBookVP: Bool`, kèm bộ giải mã tùy biến an toàn tương thích ngược các file JSON chat cũ.
  - `AIBookDataInspector`: Thêm hàm `fetchBookDictionarySets` và `decorateExtractedNames`, đối chiếu với `Names.txt` và `VietPhrase.txt` của cuốn truyện đang đọc để tự động gắn cờ và đặt `isSelected = false` (bỏ chọn mặc định) cho các tên riêng đã tồn tại.
  - `ReaderAINameReviewCardView`: Hiển thị badge `NE` (tím) và `VP` (cam) trên từng hàng tên riêng để người dùng nhận diện trực quan từ nào đã có trong từ điển truyện.
  - `AINameExtractionBatchProcessor`: Không loại bỏ các từ đã có trong từ điển ở tầng xử lý batch để toàn bộ tên trích xuất đều được gắn badge đầy đủ.
- **Tự động lưu Cấu hình AI & Prompt (`AISettingsView.swift`, `AISettingsView+Actions.swift`, `AIPromptSettingsView.swift`)**:
  - Bỏ nút "Lưu" thủ công trên toolbar của `AISettingsView` và `AIPromptSettingsView`.
  - Tự động lưu cấu hình và prompt ngay lập tức khi thay đổi qua `.onChange`, khi đổi/thêm/xóa profile và khi thoát màn hình qua `.onDisappear`.
- **Tắt tự động sang chương của Reader khi tắt cuộn theo Highlight (`ReaderView.swift`)**:
  - Thêm điều kiện `guard !isAutoScrollDisabled else { return }` vào bộ nhận sự kiện `ttsDidAdvanceToNextChapter`.
  - Khi người dùng đã tắt chức năng cuộn theo highlight của TTS, Reader sẽ giữ nguyên chương và vị trí đang đọc thay vì tự ý nhảy sang chương mới theo TTS.

## [1.3.391] - 2026-09-23

### fix: sua loi parse json trich xuat ten rieng ai luon tra ve 0 ket qua

Sửa **2** file Swift trong `Sources/Models/AI/` và `Sources/Services/AI/`:

- **Nâng cấp Resilient JSON Parser trích xuất tên riêng (`AINameExtractionBatchProcessor.swift`)**:
  - Khắc phục lỗi kiểm tra cứng trường `dict["meaning"]` trong khi cấu hình AI yêu cầu `suggestedMeaning` dẫn đến kết quả luôn bị bỏ qua thành rỗng.
  - Bổ sung cơ chế bóc tách JSON đa tầng: bóc tách markdown code fence (`extractMarkdownBlock`) kể cả khi có văn bản phụ bao quanh; fallback cắt lát dải JSON substring mảng `[...]` hoặc object `{...}` qua chỉ số mở/đóng đầu tiên và cuối cùng.
  - Hỗ trợ làm sạch dấu phẩy thừa (trailing commas trước `}` và `]`) thông qua Regex `cleanTrailingCommas`.
  - Mở rộng hỗ trợ đa dạng tên trường (multi-key fallback): từ gốc Hán tự (`original`, `name`, `word`, `hanzi`, `raw`, `chinese`, `text`), nghĩa dịch Hán Việt (`suggestedMeaning`, `meaning`, `translation`, `vietnamese`, `hvdic`, `hanviet`, `viet`, `val`, `value`), phân loại (`category`, `type`, `tag`, `role`) và số lần xuất hiện (`occurrenceCount`, `count`, `occurrences`, `frequency`).
  - Tự động khử trùng lặp và cộng dồn số lần xuất hiện theo từ gốc tiếng Trung.
- **Chuẩn hóa Prompt trích xuất tên riêng (`AIConfiguration.swift`)**:
  - Bổ sung trường mẫu `category` trong `defaultNameExtractionPrompt` để hỗ trợ AI phân loại chính xác các thực thể trích xuất.

## [1.3.390] - 2026-09-23

### feat: nang cap toan dien ai harness tri nho truyen compact va luu tu dien

Thêm **6** file Swift mới và sửa **8** file Swift trong `Sources/Models/AI/`, `Sources/Services/AI/`, `Sources/Views/Reader/`, `Sources/Views/Settings/AI/`:

- **Trí nhớ dài hạn theo truyện & Tự động nạp từ điển (`BookAIMemory.swift`, `BookAIMemoryStore.swift`, `AIBookDataInspector.swift`, `BookAIMemorySheet.swift`)**:
  - Tạo model và store `BookAIMemory` lưu ghi chú bối cảnh, nhân vật của từng cuốn truyện tại `applicationSupportDirectory/ai_memory/`.
  - Tự động nạp các mục từ điển `Names.txt` và `VietPhrase.txt` của cuốn truyện vào System Context, lọc thông minh theo nội dung raw chương hiện tại.
  - Cung cấp sheet `BookAIMemorySheet` để xem và chỉnh sửa nhanh trí nhớ truyện.
- **Tự động compact ngữ cảnh phiên chat (`AIContextCompactor.swift`, `AIChatSession.swift`)**:
  - Tự động tóm tắt các tin nhắn cũ khi session vượt quá 12 tin nhắn thành `contextSummary`, chỉ gửi tóm tắt + 6 tin nhắn mới nhất để tối ưu token và chống tràn context window.
- **Nâng cấp Lưu Từ điển Name riêng & VP riêng (`ReaderAINameReviewCardView.swift`, `AIHarnessService.swift`, `ReaderAIFullScreenView+Actions.swift`)**:
  - Bổ sung 2 nút bấm riêng biệt: `Lưu Name riêng` và `Lưu VP riêng`.
  - Hộp thoại xác nhận 2 chế độ: *Gộp (trùng từ thì thay mới)* và *Thay thế hoàn toàn*.
  - Chuyển đổi nút Lưu thành banner xác nhận màu xanh sau khi lưu thành công, kèm Toast thông báo (sửa cú pháp `ToastManager.shared.show(message:type:)`).
  - Thêm nút xóa từng mục và sửa liên kết hai chiều (binding) bỏ chọn tên riêng trực tiếp vào session messages.
- **Cải tiến giao diện & trải nghiệm AI (`AIMarkdownMessageView.swift`, `ReaderAIThinkingIndicatorView.swift`, `ReaderAIFullScreenView.swift`, `ReaderAIInputBarView.swift`)**:
  - Render phản hồi AI chuẩn Markdown với khối code monospaced có nút chép, tiêu đề và gạch đầu dòng.
  - Animation 3 chấm nảy phát sáng và con trỏ nhấp nháy khi AI đang suy nghĩ.
  - Mốc neo cuộn `bottomScrollAnchor` và tương tác bàn phím chống lỗi cuộn đen màn hình.
  - Menu ngữ cảnh sao chép tin nhắn khi bấm giữ.
  - Tự động nhận diện câu lệnh lọc tên riêng khi người dùng tự gõ.
  - Tự động đóng tab AI khi bấm nhảy chương từ widget TTS (`ReaderView.swift`).
- **Màn hình Tùy chỉnh Prompt AI & Đồng bộ Profile (`AIPromptSettingsView.swift`, `AISettingsView.swift`, `AISettingsView+Actions.swift`, `AISettingsStore.swift`)**:
  - Màn hình tùy chỉnh System Prompt chat và Name extraction prompt.
  - Tinh gọn Profile: chỉ lưu các profile người dùng thực sự thêm hoặc đã nhập API key.
  - Đồng bộ thời gian thực danh sách Profile giữa Cài đặt và Reader AI qua `didChangeNotification`.

## [1.3.389] - 2026-09-23

### feat: quan ly provider profiles doc lap, picker chon mau va sua loi hien thi ai

Thêm **2** file Swift mới và sửa **5** file Swift trong `Sources/Models/AI/`, `Sources/Services/AI/`, `Sources/Views/Reader/`, `Sources/Views/Settings/AI/`:

- **Quản lý Provider Profile độc lập (`AIProviderProfile.swift`, `AIConfiguration.swift`, `AISettingsStore.swift`)**:
  - Tạo struct `AIProviderProfile` lưu trữ cấu hình riêng biệt của từng Provider (`id`, `name`, `baseURL`, `apiKey`, `selectedModel`, `availableModels`, `temperature`, `isCustom`).
  - Nâng cấp `AIConfiguration` chứa mảng `profiles` và `activeProfileId`, tự động di trú dữ liệu legacy không mất cấu hình.
  - Bổ sung các phương thức `saveProfile`, `deleteProfile`, `setActiveProfile` trong `AISettingsStore`.
- **Sheet Thêm Mới Option Provider dạng Picker (`AddProviderProfileSheet.swift`, `AISettingsView.swift`)**:
  - Thay thế thanh chọn nhanh bằng Menu Picker phân nhóm chuẩn iOS (`.pickerStyle(.menu)`) gồm Mẫu có sẵn (Gemini, OpenAI, DeepSeek, OpenRouter, Groq, Ollama), Nhân bản từ Profile đã lưu, và Tuỳ chỉnh trống.
  - Tích hợp nút "⚡ Load từ API" gọi `OpenAIClient.fetchAvailableModels` để tự động tải danh sách models.
  - Giữ duy nhất 1 nút icon `+` trên thanh Navigation bar của `AISettingsView` để thêm Profile mới.
- **Sửa lỗi hiển thị toàn màn hình AI (`ReaderView.swift`, `ReaderView+AI.swift`)**:
  - Chuyển `.fullScreenCover` sang gắn trực tiếp trên `readerSheetLayer` (neo vào UIHostingController chính) thay vì gắn vào `EmptyView` trong ZStack.

## [1.3.388] - 2026-09-23

### fix: chuyen aibookdatainspector sang internal de fix loi bien dich

Sửa access level trong `Sources/Services/AI/Harness/AIBookDataInspector.swift`:

- **Khắc phục lỗi biên dịch dùng kiểu internal trong public API (`AIBookDataInspector.swift`)**:
  - Chuyển `AIBookDataInspector` và các phương thức `fetchDownloadedChapters`, `readRawChapterContent` từ `public` sang `internal` nhằm tương thích với kiểu `StoredChapterSnapshot` (được định nghĩa `internal`).


### fix: nang cap chan doan ci va tranh xung dot type trong ai harness

Cải thiện workflow CI và refactor kiểu dữ liệu trong `Sources/Services/AI/`:

- **Đổi tên kiểu AnyCodable (`OpenAITypes.swift`)**:
  - Đổi tên `OpenAIChatRequest.AnyCodable` thành `OpenAIChatAnyCodable` và bổ sung typealias tương thích ngược nhằm phòng tránh xung đột định danh tiềm ẩn.
- **Nâng cấp công cụ chẩn đoán lỗi CI (`.github/workflows/build-ipa.yml`)**:
  - Bổ sung bước đọc trực tiếp `build_error.log` và trích xuất toàn bộ chuỗi thông báo lỗi/note từ các file serialized diagnostics (`.dia`) để hiển thị tường minh nguyên nhân thất bại trên GitHub Actions.


### fix: sua cac loi bien dich trong phan he ai harness

Sửa **4** file Swift trong `Sources/Services/AI/` và `Sources/Views/Reader/Extensions/`.

- **Sửa API nạp tên riêng trong truyện (`AIBookDataInspector.swift`)**:
  - Đọc danh sách từ/tên riêng từ `Names.txt` qua `DictionaryTextFileStore.loadEntries(from: txtUrl)` thay vì gọi `allWords()` không tồn tại trên `TrieDictionary`.
- **Sửa gọi thêm quy tắc lọc rác (`AIHarnessService.swift`)**:
  - Sử dụng `JunkFilterManager.shared.addRule(pattern:)` trên `MainActor` thay vì `addPattern`.
- **Sửa nạp nội dung chương cho Reader AI (`ReaderView+AI.swift`)**:
  - Truy xuất chương đang đọc qua `viewModel?.cache.get(readerPresentedChapterIndex)` thay vì `cachedChapters`.
- **Loại bỏ non-sendable stored property (`AIChatHistoryStore.swift`)**:
  - Dùng trực tiếp `FileManager.default` trong các hàm thay vì lưu trữ thuộc tính `private let fileManager`, tương thích hoàn toàn với chế độ Swift 6.

## [1.3.385] - 2026-09-23

### feat: them che do ai agent harness toan man hinh o reader voi 3 mode ask plan bypass

Thêm **24** file Swift mới và sửa **3** file Swift trong `Sources/Views/Reader/` và `Sources/Views/Settings/`.

- **Màn hình AI Agent Harness toàn màn hình (`ReaderAIFullScreenView.swift`, `ReaderView+AI.swift`)**:
  - Mở dạng `.fullScreenCover` từ nút icon `sparkles` trên Header và Action Menu của Reader.
  - Hỗ trợ streaming SSE phản hồi theo thời gian thực từ bất kỳ endpoint nào tương thích OpenAI API (Gemini, OpenAI, Claude/OpenRouter, DeepSeek, Groq, Ollama, Custom).
  - Tách `ReaderAIFullScreenView+Actions.swift` giữ cả 2 file dưới trần 400 dòng vật lý.
- **3 chế độ Harness ngay trên khung chat (`ReaderAIInputBarView.swift`, `AIHarnessMode.swift`)**:
  - `Manual (Ask)`: Tạo ActionPlan và hỏi người dùng trước khi áp dụng thay đổi vào dữ liệu truyện.
  - `Plan`: Lập kế hoạch chi tiết các bước, người dùng ấn "Duyệt kế hoạch" mới thực thi.
  - `Bypass permissions`: Tự động thực thi ngay lập tức.
  - Menu chuyển đổi mode dạng Pill Menu ngay trên Input Bar, kèm Model Picker Menu tức thì.
- **Quản lý cấu hình & Model trong Cài đặt (`AISettingsView.swift`, `AISettingsStore.swift`)**:
  - Hỗ trợ preset cho các nhà cung cấp phổ biến kèm cấu hình tùy chỉnh endpoint / API key / timeout.
  - Nút "Load danh sách từ API" (`GET /models`) và TextEditor nhập danh sách model thủ công (mỗi model một dòng).
  - `AISettingsSection.swift` giúp `SettingsView.swift` giảm dòng và loại bỏ khỏi baseline vi phạm kiến trúc.
- **Phân tích raw chapter & Trích xuất tên riêng (`AIBookDataInspector.swift`, `AINameExtractionBatchProcessor.swift`)**:
  - Sử dụng văn bản gốc Hán tự (raw text) từ `ChapterStore` / `BookBinManager` để LLM phân tích chính xác tên riêng, nhân vật, địa danh.
  - Quét batch offline các chương đã tải theo lô 5 chương kèm thanh tiến trình và nút Dừng.
  - Thẻ `ReaderAINameReviewCardView` cho phép duyệt, tick chọn, sửa nghĩa và lưu thẳng vào từ điển truyện (`TranslationManager.shared.saveCustomEntry(..., isName: true, bookId:)`), tự động kích hoạt bảo vệ Name riêng trước Rule dịch.
- **Lưu trữ phiên trò chuyện (`AIChatHistoryStore.swift`, `ReaderAISessionListView.swift`)**:
  - Tự động lưu session chat theo từng truyện dưới `Application Support/ai_chats/<sha256(bookId)>.json`.
  - Hỗ trợ New Chat (`+ Mới`), xem danh sách session cũ và xóa từng session hoặc xóa tất cả.
- **Tài liệu CodeGraph**: Cập nhật `00_index.md`, `02_file_graph.md`, `03_type_graph.md`, `04_call_graph.md`, `05_state_graph.md`, `08_lifecycle.md`, `09_dependency_rules.md`, `10_risk_report.md`, `11_subsystems.md`, `13_resource_lifecycle.md`, `14_complexity_report.md`, `rules.md` và `CHANGELOG.md`.

## [1.3.384] - 2026-09-18

### feat: dua rule tranh chap name rieng len thanh chip o trang thai thua

Sửa **2** file Swift trong `Sources/Services/Translation/Engine/`.

- **Thu thập đầy đủ Rule tranh chấp Name riêng vào thanh chip (`QuickTranslationRuleMatcher.swift`, `QuickTranslationRuleEngine.swift`)**:
  - `QuickTranslationRuleMatcher.walkNumeral`: Đếm `run` số tự nhiên (không ngắt sớm tại ký tự Name riêng) để matcher nhận diện được đầy đủ cụm khớp quét qua Name.
  - `QuickTranslationRuleEngine.collectFound`: Khi `hasConflict == true` ở chế độ `includesDisabled: true`, match tranh chấp vẫn được đưa vào `found` và dịch `cursor = match.start + 1` để không bỏ sót các lượt thử hợp lệ tiếp theo (như `start = 3` ngay sau Name riêng).
  - `QuickTranslationRuleDiagnostics.diagnose`: Match tranh chấp Name riêng không được vào `winners`, tự động nhận `status = .lostOverlap` và hiển thị trên thanh chip ở trạng thái tranh chấp thua (chip mờ).
- **Tài liệu CodeGraph**: Cập nhật `07_dataflow.md`, `11_subsystems.md` và `CHANGELOG.md`.

## [1.3.383] - 2026-09-18

### feat: bao ve name rieng truoc rule dich va co dinh nghia rule panel dich

Sửa **4** file Swift trong `Sources/Services/Translation/Engine/`, `Sources/Views/Reader/` và thêm **1** file Swift mới trong `Sources/Services/Translation/Extensions/`.

- **Cố định ô "Nghĩa rule" trong panel Dịch (`ReaderView+DefinitionPanel.swift`)**:
  - `isLoadingRules` chỉ theo dõi `definitionSession.loadingRules` (bỏ `definitionSession.loading`), giữ nguyên nội dung nghĩa rule khi tra từ điển lúc nới/thu token, loại bỏ triệt để hiện tượng chớp giật.
- **Bảo vệ Name riêng trước Rule dịch (`QuickTranslationRuleMatcher.swift`, `QuickTranslationRuleEngine.swift`, `QuickTranslationRuleEngine+NameProtection.swift`, `QuickTranslationRuleDiagnostics.swift`)**:
  - Thêm `scanBookNameOccupiedIndices(text:bookId:)` quét cây Double Array Trie `bookNames` của truyện để tạo bản đồ `bookNameRanges` và tập hợp `bookNameOccupiedIndices`.
  - `QuickTranslationRuleMatcher.walkNumeral`: Coi ranh giới Name riêng là ranh giới số hợp lệ (bỏ qua chặn `guardsLeft` nếu ký tự liền kề thuộc Name riêng), cho phép các token số (`<n>`, `<y>`, `<h>`, `<d>`) khớp độc lập ngay sát cạnh Name riêng (ví dụ `比唐三六个月` -> `唐三` giữ nguyên "Đường Tam", `六个月` khớp "6 tháng" -> "hơn Đường Tam 6 tháng").
  - `ruleMatchConflictsWithBookNames`: Bất kỳ rule nào cắt ngang hoặc nuốt một phần Name riêng đều bị loại trừ khỏi danh sách trúng tuyển trong cả dịch thật lẫn chẩn đoán (`.lostOverlap`).
  - Tách `QuickTranslationRuleEngine+NameProtection.swift` (50 dòng) để `QuickTranslationRuleEngine.swift` giảm về 372 dòng (< 400 dòng trần kiến trúc).
- **Tài liệu CodeGraph**: Cập nhật `00_index.md`, `02_file_graph.md`, `04_call_graph.md`, `07_dataflow.md`, `09_dependency_rules.md`, `11_subsystems.md`, `14_complexity_report.md` và `CHANGELOG.md`.

## [1.3.382] - 2026-09-18

### feat: tu dong cuon va chon token khi bam chip rule trong panel dich

Sửa **2** file Swift trong `Sources/Views/Reader/`.

- **Tự động chọn token của rule (`ReaderDefinitionOverlayView+Rules.swift`)**:
  - Khi người dùng bấm vào chip rule trên thanh chip rule, gán `selectedWordOffset` và `selectedWordLength` theo `trace.sourceRange`, đồng thời gọi `onUpdateEditorFromSelection()`.
  - Tự động bôi chọn các ký tự câu gốc và token tương ứng, đồng thời nạp nghĩa từ điển và gợi ý cho cụm từ khớp với rule.
- **Tự động cuộn đến vị trí token tương ứng (`ReaderDefinitionOverlayView.swift`)**:
  - Bổ sung `@State internal var ruleScrollTrigger: Int = 0` được tăng mỗi lần bấm chip.
  - Cả hàng ký tự gốc (`originalSentenceRowView`) và hàng token dịch (`translatedTokensRowView`) đều lắng nghe `ruleScrollTrigger` để kích hoạt cuộn mượt (animated) về vị trí ký tự / token tương ứng ở tâm màn hình.
- **Tài liệu CodeGraph**: Cập nhật `04_call_graph.md`, `11_subsystems.md` và `CHANGELOG.md`.

## [1.3.381] - 2026-09-18

### fix: cap nhat rule trace khi mo panel dich va loc signal theo truyen

Sửa **5** file Swift trong `Sources/Services/Translation/Engine/`, `Sources/Views/Reader/` và `Sources/Views/Reader/Extensions/`.

- **Cập nhật rule traces khi mở panel Dịch (`ReaderView+RuleTools.swift`, `ReaderView.swift`)**:
  - Gọi `refreshRuleTraces()` trong `openDefinitionPanel()` và trong `.onChange(of: showingDefinitionSheet)` (khi `newValue == true`) để thanh chip rule nạp dữ liệu chẩn đoán của cả đoạn văn ngay khi mở.
- **Chống reload dải chip khi nới/thu token (`ReaderView+DefinitionLoading.swift`, `ReaderView+DefinitionPanel.swift`)**:
  - `refreshDefinitionRules()` chuyển sang kiểm tra theo đoạn văn gốc `originalSentence == text` và `definitionSession.identity == sessionID`, bỏ phụ thuộc vào selection `range`/`word` của `currentDefinitionSnapshot()`.
  - Khi mở rộng / thu hẹp vùng chọn token trong câu, editor chỉ gọi `loadDefinitionData()` để cập nhật nghĩa từ điển, thanh chip rule giữ nguyên trạng thái hiển thị.
- **Phát và lọc sự kiện rule theo truyện (`QuickTranslationRuleBookStore.swift`, `ReaderView.swift`)**:
  - `QuickTranslationRuleBookStore.notifyChange(bookId:)` gọi thêm `TranslationManager.shared.notifyRulesDidUpdate(bookId: bookId)`.
  - `ReaderView` đăng ký nhận `.quickTranslationRulesDidUpdate` và chỉ reload bản dịch / thanh chip rule khi `targetBookId == nil` (rule chung) hoặc `targetBookId == bookId` (rule riêng đang đọc). Bỏ qua hoàn toàn nếu là thay đổi rule riêng của truyện khác.
- **Tài liệu CodeGraph**: Cập nhật `00_index.md`, `04_call_graph.md`, `05_state_graph.md`, `06_event_graph.md`, `07_dataflow.md`, `11_subsystems.md`, `rules.md` và `CHANGELOG.md`.

## [1.3.380] - 2026-09-17

### fix: khong dung rule trace khi cap nhat name vp

Sửa **1** file Swift trong `Sources/Views/Reader/Extensions/`.

- **Panel Dịch không đụng task rule khi chỉ reload nghĩa/token (`ReaderView+DefinitionLoading.swift`)**:
  - Bỏ `definitionSession.ruleTask?.cancel()` khỏi `loadDefinitionData()`.
  - Khi người dùng cập nhật Name/VP, notification từ điển vẫn reload nghĩa/token qua `loadDefinitionData(preservingMeaning: true)` nhưng không hủy và không lấy lại rule trace của cả đoạn văn.
  - Rule trace vẫn chỉ do luồng rule tự quản: `refreshDefinitionRules()` tự cancel lượt rule cũ khi thật sự cần refresh.
- **Tài liệu CodeGraph**: ghi nhận các doc stale theo validator; không cần cập nhật nội dung mô tả hệ thống.
- Gate: `validate_links.py` và `check_architecture.py` sẽ chạy sau khi ghi nhận doc; host Windows không build Xcode tại chỗ.

## [1.3.379] - 2026-09-17

### fix: tach signal rule khoi signal tu dien trong panel dich

Sửa **11** file Swift trong `Sources/Services/TTS/`, `Sources/Services/Translation/` và `Sources/Views/Reader|Settings/`.

- **Tách kênh event rule khỏi kênh từ điển (`TranslationManager.swift`)**:
  - Thêm `.quickTranslationRulesDidUpdate` và `notifyRulesDidUpdate(bookId:)`.
  - Rule/token/priority change phát rule signal; dictionary change giữ `notifyDictionariesDidUpdate(bookId:scope:)`.
- **Giảm lag panel Dịch (`ReaderView.swift`, `ReaderView+DefinitionLoading.swift`)**:
  - `refreshRuleTraces()` không còn chạy sau mỗi `loadDefinitionData()` hoặc mỗi lần `selectedWordOffset` đổi.
  - Panel re-diagnose rule khi mở, khi `originalSentence` đổi hoặc khi nhận rule signal.
- **Đồng bộ Reader/TTS theo signal mới (`TTSManager.swift`, các store rule/settings)**:
  - `TTSManager` lắng nghe thêm `.quickTranslationRulesDidUpdate` để huỷ prepared chapter, claimed synthesis, next-chapter prefetch/prefix và metadata tĩnh.
  - `QuickTranslationRuleStore`, `QuickTranslationRuleDisableStore`, token settings, priority settings và công tắc áp dụng rule phát rule signal đúng một lần sau khi cache/generation đã invalidated.
  - Sửa lỗi compile đã làm CI fail: `QuickTranslationRuleDisableStore` dùng đúng `TranslateUtils.invalidateCache(bookId:)` thay vì `clearCache(bookId:)`; bỏ notify dư ở CRUD rule.
- **Tài liệu CodeGraph**: cập nhật `00_index.md`, `02_file_graph.md`, `04_call_graph.md`, `05_state_graph.md`, `06_event_graph.md`, `07_dataflow.md`, `08_lifecycle.md`, `11_subsystems.md`, `rules.md` và `CHANGELOG.md`.
- Gate: `validate_links.py` sẽ được chạy lại sau khi accept doc; `check_architecture.py` dự kiến vẫn đỏ bởi baseline legacy, không do lượt này mở luật mới.
- **Chưa kiểm chứng biên dịch tại chỗ**: workspace Windows, không chạy được `xcodegen`/`xcodebuild`; CI GitHub là nguồn build.

## [1.3.378] - 2026-09-15

### fix: tach cac chu so han liet ke bang dau phay trong rule dich

Sửa **1** file Swift trong `Sources/Services/Translation/Engine/`.

- **Tách các chữ số Hán liệt kê bằng dấu phẩy trong rule dịch (`QuickTranslationNumberFormatter.swift`)**:
  - Gỡ bỏ ràng buộc bắt buộc tăng liền kề đúng 1 đơn vị (`digit == last + 1`) và `parsed <= last` trong hàm `enumeratedNumbers`.
  - Hỗ trợ đầy đủ các chuỗi số Hán trần 2-3 chữ số đứng liền nhau được liệt kê theo thứ tự bất kỳ (bao gồm tăng dần cách quãng như `二四` → `2, 4`, `三五` → `3, 5`, `二四六` → `2, 4, 6`; giảm dần hoặc ngẫu nhiên như `九五二` → `9, 5, 2`, `五三` → `5, 3`, `四二` → `4, 2`).
  - Khắc phục triệt để lỗi `第二四个` bị dịch sai thành "cái thứ 24" nay chuyển thành "cái thứ 2, 4"; `第九五二个` nay chuyển thành "cái thứ 9, 5, 2".
  - Bảo tồn nguyên vẹn các số chính thức có từ chỉ bậc (`二十四` = 24, `九百五十二` = 952, `八千三` = 8300, `一万二` = 12000), số năm/mã số chứa `零`/`〇` (`二零二五` = 2025), và số năm 4 chữ số trần (`一九九八` = 1998) qua guard `runLength >= 4`.
- **Tài liệu CodeGraph**: cập nhật `11_subsystems.md` (`--accept`); `07_dataflow.md` ghi `--no-change-needed`.
- Gate: `check_architecture.py` không phát sinh vi phạm mới (`QuickTranslationNumberFormatter.swift` 342 dòng $\le 400$ dòng); `validate_links.py` PASS 100%.
- **Chưa kiểm chứng biên dịch tại chỗ**: workspace Windows, không chạy được `xcodegen`/`xcodebuild`.

## [1.3.377] - 2026-09-15

### fix: dieu chinh chieu cao ban dau cua context menu sach va man hinh hen gio tts

Sửa **2** file Swift trong `Sources/Views/Shelf/BookActions/` và `Sources/Views/TTSWidget/`.

- **Điều chỉnh chiều cao ban đầu của Context Menu sách (`BookActionSheet.swift`)**:
  - Nâng `presentationDetents` từ `[.medium, .large]` lên `[.fraction(0.85), .large]`.
  - Giúp sheet mở ban đầu ở mức 85% chiều cao màn hình, hiển thị trọn vẹn toàn bộ các tuỳ chọn hành động ("Đổi nguồn", "Tải truyện", "Xuất ebook", "Dịch lại tên chương", "Bỏ khỏi bộ sưu tập", "Xoá"), khắc phục lỗi chỉ thấy đến "Đổi nguồn" khi mở ở mức `.medium`.
- **Điều chỉnh chiều cao ban đầu của Màn hình Hẹn giờ TTS (`TTSQuickTimerSheet.swift`)**:
  - Nâng `presentationDetents` từ `[.fraction(0.78), .large]` lên `[.fraction(0.88), .large]`.
  - Mở ban đầu ở mức 88% chiều cao màn hình, bổ sung ~85–90 pt không gian, giúp nút "Hẹn giờ 90 phút" và khối card tuỳ chỉnh phía dưới hiển thị trọn vẹn, không còn bị cắt ở góc trên của nút.
- **Tài liệu CodeGraph**: cập nhật `11_subsystems.md` (`--accept`); `03_type_graph.md`, `05_state_graph.md` ghi `--no-change-needed`.
- Gate: `check_architecture.py` không phát sinh vi phạm mới (vẫn đúng 6 vi phạm nền); `validate_links.py` PASS 100%.
- **Chưa kiểm chứng biên dịch tại chỗ**: workspace Windows, không chạy được `xcodegen`/`xcodebuild`.

## [1.3.376] - 2026-09-13

### fix: bao ton chu hoa thuong trong panel dich va rule, them nut x clear, bat goi y ban phim toan app

Sửa **31** file Swift trong `Sources/Services/Translation/`, `Sources/Views/Reader/`, `Sources/Views/Settings/`, `Sources/Views/Dictionary/`, `Sources/Views/BookDetail/`, `Sources/Views/Search/`, `Sources/Views/Discovery/`, `Sources/Views/Common/`, `Sources/Views/Extensions/`, `Sources/Views/TTSWidget/`.

- **Bảo tồn hoa/thường nghĩa từ điển trong Panel Dịch & Rule Editor (`TranslationTextPostProcessor.swift`, `TranslateUtils.swift`, `TranslateUtils+Tokenization.swift`)**:
  - `TranslationTextPostProcessor.apply(to:capitalizeFirstLetter:)`, `TranslateUtils.postProcessText(_:capitalizeFirstLetter:)`, và `TranslateUtils.performTranslation(_:bookId:applyingQuickTranslationRules:capitalizeFirstLetter:)` hỗ trợ cờ `capitalizeFirstLetter: Bool = true`.
  - Thêm `TranslateUtils.translateTerm(_:bookId:shouldConvertTraditionalToSimplified:)` (đặt trong `TranslateUtils+Tokenization.swift` để giữ `TranslateUtils.swift` nguyên baseline 917 dòng vật lý, tuân thủ `Scripts/check_architecture.py`) với `capitalizeFirstLetter: false`. Tuyệt đối không dùng `.lowercased()` hay ép thường vì sẽ làm hỏng tên riêng / danh từ viết hoa.
  - `ReaderDefinitionWorker.swift`: Gọi `TranslateUtils.translateTerm` cho mode "VP", hiển thị nguyên vẹn chữ hoa/thường của nghĩa từ điển.
  - `ReaderSelectionCoordinator.swift`: Bỏ `.capitalized` trong `hanViet(for:)`, trả về âm Hán-Việt nguyên bản.
- **Thêm nút xoá (x) và cấu hình bàn phím trong màn hình Thêm / Sửa Rule (`QuickTranslationRuleEditorSheet+Editing.swift`, `QuickTranslationRulePatternField.swift`)**:
  - Thêm nút `x` (clear) tròn 28pt cho cả ô Mẫu (`patternSection`) và ô Bản dịch (`replacementSection`).
  - Trong `QuickTranslationRulePatternField.swift`, đặt `view.autocorrectionType = .yes`, `view.spellCheckingType = .yes` và giữ `view.autocapitalizationType = .none` ở cả `makeUIView` và `updateUIView`.
- **Bật thanh gợi ý từ bàn phím (QuickType) toàn bộ ứng dụng (Lựa chọn C)**:
  - Gỡ bỏ `.autocorrectionDisabled()` / `.disableAutocorrection(true)` tại 24 vị trí trong toàn bộ ứng dụng (Tìm kiếm, Từ điển, Thay thế TTS, Lọc rác, Cấu hình TOC...).
  - Giữ nguyên tắt autocorrection cho các ô code/URL đặc thù: `URLBarTextField.swift`, `CodeEditorTextView.swift`, `ReaderTextView.swift`, `ExtensionDebugConsoleView.swift`.
- **Tài liệu CodeGraph**: cập nhật `04_call_graph.md`, `07_dataflow.md`, `11_subsystems.md` (`--accept`); `03_type_graph.md`, `05_state_graph.md`, `12_ownership_graph.md`, `13_resource_lifecycle.md` ghi `--no-change-needed`.
- Gate: `check_architecture.py` không phát sinh vi phạm mới (vẫn đúng 6 vi phạm nền, `DictionaryListView.swift` giảm dòng từ 710 xuống 708); `validate_links.py` PASS 100%.
- **Chưa kiểm chứng biên dịch tại chỗ**: workspace Windows, không chạy được `xcodegen`/`xcodebuild`.

## [1.3.375] - 2026-09-13

### fix: bo tai lai noi dung khi chi ban dich loi thoi, dat tran cache chuong va noi tran memo rule rewrite

Sửa **4** file Swift trong `Sources/Views/Reader/` và `Sources/Services/Translation/Engine/`.

- **Chuyển chương khi chỉ bản dịch lỗi thời không còn tải lại nội dung (`ReaderViewModel.swift`)**:
  - `loadChapterContentFromExtension` thoát sớm trả `.memory` khi `forceRefresh == false` **và** cache Reader đã có `state == .loaded` với `originalContent` khác rỗng. Tiền đề: khi đó lý do duy nhất phải qua hàm này là token dịch đã đổi (sửa từ điển/rule), còn nội dung chương không đổi — `runNavigationWorker` tự gọi `processAndSaveChapter(originalContent: cached.originalContent)` ngay sau đó.
  - Trước 1.3.375, mỗi lần lật trang sau khi sửa từ điển vẫn tốn thêm một vòng `ChapterContentRepository.load` (DB/extension) chỉ để lấy lại nội dung đã nằm trong RAM.
  - `forceRefresh: true` **không** đi nhánh mới, nên "Cập nhật mục lục" và `reloadDisplayedChapter` giữ nguyên hành vi; `retryPendingNavigation` cũng vậy vì chương lỗi có `state != .loaded`.
- **`ChapterCache` có trần thật, lần đầu được thi hành (`ReaderView.swift`, `ChapterCache.swift`)**:
  - `queueReleaseAllNonVisible` là **code chết** từ trước tới nay (không có caller), nên cache chương chỉ được dọn khi Memory Warning — mà `handleMemoryWarning` chỉ giữ **đúng** chương đang đọc.
  - `ReaderView.applyNavigationCommit` gọi nó sau mỗi commit với cửa sổ **±3** quanh chương vừa tới và ân hạn 5 s (`queueRelease` huỷ hẹn nếu `get()` chạm lại chương đó).
  - `queueRelease` đổi sang `Task { @MainActor }`: `performRelease` gỡ khoá trong `cache` (`@Observable`) nên không được chạy nền. Lỗi này chưa từng lộ vì hàm chưa có caller.
- **Memo rewrite của rule engine từ 64 lên 2048 entry (`QuickTranslationRuleEngine.swift`)**:
  - Pipeline gọi `rewrite` hai lần cho cùng một chuỗi (một lần dịch, một lần dựng span) nên 64 entry **nhỏ hơn một chương** ⇒ memo thrash ngay trong một lượt dựng chương. Trần bộ nhớ thật vẫn là `maxCost` 2 MiB nên nâng `maxEntries` **không** nới bộ nhớ.
- **Tài liệu CodeGraph**: cập nhật vùng GENERATED của `04_call_graph.md`, `05_state_graph.md`, `08_lifecycle.md`, `10_risk_report.md`, `11_subsystems.md`, `13_resource_lifecycle.md`, `rules.md` (`--accept`); `03_type_graph.md`, `07_dataflow.md`, `12_ownership_graph.md` ghi `--no-change-needed`.
  - `05_state_graph.md` chứa một khẳng định **nay đã sai** và đã được sửa: mục 1.3.240 viết "`ChapterCache` thực tế không evict (`queueRelease*` không có caller)" — tiền đề đó không còn đúng từ 1.3.375.
  - **Lưu ý về nợ tài liệu**: 10 doc này đã stale sẵn từ commit `fbbeef1` (phiên trước commit mà không `--accept`); `validate_links.py` khi đó vẫn báo PASS vì công cụ **short-circuit khi cây làm việc sạch**. Lượt này ghi nhận cả 10.
- Gate: `check_architecture.py` không phát sinh vi phạm mới (vẫn đúng 6 vi phạm nền: `ChapterPersistenceStore`, `JSDom`, `JSExecutor`, `TTSManager`, `DictionaryListView`, `ReaderViewModel`); `validate_links.py` PASS 100%.
- **Chưa kiểm chứng biên dịch tại chỗ**: workspace Windows, không chạy được `xcodegen`/`xcodebuild`/Instruments. Mọi số đo hiệu năng phải lấy lại trên máy thật.

## [1.3.374] - 2026-09-13

### feat: tai thiet ke sheet hen gio va muc luc tts, nen xam widget dem nguoc va tab the loai kham pha

Sửa **6** file trong `Sources/Services/TTS/`, `Sources/Views/Reader/`, `Sources/Views/TTSWidget/`, `Sources/Views/Discovery/` và `.github/workflows/build-ipa.yml`.

- **Màn hình Sheet Điều khiển Hẹn giờ & Mục lục TTS (`TTSQuickTimerSheet.swift`)**:
  - Bỏ navigation header "Hẹn giờ tắt" và bỏ card cài đặt giọng đọc ở dưới (truy cập cài đặt qua icon bánh răng ⚙️ trên toolbar).
  - Tích hợp Card thông tin truyện đang phát:
    - Bìa sách: Chạm vào bìa sách tự động đóng sheet và bắn notification `openCurrentlyPlayingReader` để mở Reader tại chương đang phát.
    - Tên truyện: Hiển thị đầy đủ toàn bộ số hàng, kèm badge số chương bên cạnh.
    - Tác giả: Hiển thị icon `person.fill` + tên tác giả (`displayedAuthor`). Nếu rỗng chỉ hiển thị biểu tượng tác giả và để trống text (tuyệt đối không điền "Không rõ").
    - Slot bộ đếm giờ cố định 22pt: Hiển thị badge xám `Color(white: 0.22)` + nút "Hủy" khi có hẹn giờ hoặc text mờ khi không hẹn giờ, giữ layout 100% ổn định không bị nhảy/giật khi bật/tắt hẹn giờ.
  - Hàng tên chương đang phát: Nằm giữa card thông tin và thanh tab con, hiển thị đúng 1 hàng kèm icon `waveform`.
  - 2 Tab con chuẩn 1 hàng ngang với cử chỉ vuốt chuyển tab (`.tabViewStyle(.page(indexDisplayMode: .never))`):
    - Tab 1 ("⏱️ Hẹn giờ tắt"): Lưới chọn nhanh mốc hẹn giờ + bộ tuỳ chỉnh thời gian với slider 1-180 phút.
    - Tab 2 ("📑 Danh sách chương"): Danh sách toàn bộ chương của truyện đang phát, mỗi chương tối đa 2 hàng (`lineLimit(2)`), đánh dấu chương đang phát, tự động cuộn đến chương đang phát, chạm vào chương nào thì chuyển phát ngay chương đó qua `TTSManager.jumpToChapter(at:)`.
  - Thiết lập `.presentationDetents([.fraction(0.78), .large])` giúp mở vừa vặn không thừa đáy.
- **Widget TTS (`TTSFloatingWidgetView.swift`)**:
  - Thêm nền xám `Color(white: 0.22)` cho badge đếm ngược thời gian tạm dừng/hẹn giờ ngủ trên widget capsule.
- **Màn hình Khám phá (`DiscoveryView.swift`)**:
  - Đưa tab Thể loại hình tròn `Circle()` vào bên trong `ScrollView` ngang như tab đầu tiên, cuộn mượt cùng hàng với các tab Home.
- **TTS Core & Reader (`TTSManager.swift`, `TTSManager+Playback.swift`, `ReaderView.swift`)**:
  - `TTSManager`: Thêm `playingAuthor`, public `@Published chaptersQueue`, nhận `author` trong `startSpeaking`.
  - `TTSManager+Playback`: Bổ sung `displayedBookTitle`, `displayedAuthor`, `displayedChapterTitle`, `displayTitle(for:)` (tự động dịch VietPhrase nếu áp dụng) và `jumpToChapter(at:)` với Toast thông báo đã dịch.
  - `ReaderView`: Truyền `author` khi gọi `ttsManager.startSpeaking`.
- **CI Workflow (`build-ipa.yml`)**:
  - Tối ưu bắt log lỗi và thêm filter trigger cho thư mục workflow.
- Gate: `check_architecture.py` không phát sinh vi phạm mới; `validate_links.py` PASS 100%.

## [1.3.373] - 2026-09-12

### feat: triet tieu 100% rung vat ly khi boi den va fix loi tu scroll token man hinh dich

Sửa **3** file và cập nhật **1** file trong `Sources/Views/Reader/`.

- **Triệt tiêu 100% rung vật lý Taptic Engine (`SelectionHapticsSilencer.swift`)**:
  - Mở rộng swizzle toàn diện bằng `method_setImplementation`: vô hiệu hóa cả `UIImpactFeedbackGenerator.impactOccurred()`, `UIImpactFeedbackGenerator.impactOccurred(intensity:)`, `UISelectionFeedbackGenerator.selectionChanged()`, `UIFeedbackGenerator.prepare` và các lớp private `_UIFeedbackGenerator` / `_UISelectionFeedbackGenerator`.
  - Triệt tiêu hoàn toàn phản hồi rung vật lý của máy cả khi ấn giữ (long-press) để bắt đầu chọn lẫn khi kéo thanh neo bôi đen text.
- **Tự động scroll đến đúng token đã chọn trong màn hình Dịch (`ReaderDefinitionOverlayView.swift`, `ReaderJunkDeleteOverlayView.swift`)**:
  - Khắc phục triệt để lỗi race condition "lúc cuộn được lúc không": bổ sung `.onChange(of: translationTokens.count)` và `.onChange(of: translationTokens.map(\.id))` để tự động cuộn đến đúng token ngay khi dữ liệu nạp bất đồng bộ hoàn tất.
  - Tích hợp hàm `scrollToSelectedToken(proxy:)` với nhiều mốc retry trong `.onAppear`.
- **Chặn Layout loop trong `AutoSizingTextView` (`ReaderTextView.swift`)**:
  - Chặn `invalidateIntrinsicContentSize()` khi `selectedRange.length > 0`, ngăn việc đo lại kích thước thẻ liên tục gây rung giật hình ảnh khi bôi đen.
- Gate: `check_architecture.py` không phát sinh vi phạm mới; `validate_links.py` PASS 100%.

## [1.3.372] - 2026-09-12

### feat: tat rung mac dinh khi boi den, tu dong tat auto-scroll tts va toi uu do muot boi den reader

Sửa **2** file và thêm **1** file Swift mới trong `Sources/Views/Reader/`.

- **Triệt tiêu rung phản hồi xúc giác (Haptic Feedback) (`SelectionHapticsSilencer.swift`, `ReaderTextView.swift`)**:
  - Tạo `SelectionHapticsSilencer` swizzle phương thức `UISelectionFeedbackGenerator.selectionChanged()` thành no-op để chặn hoàn toàn lệnh kích hoạt rung Taptic Engine từ UIKit khi người dùng bôi đen văn bản.
  - Quá trình kéo thanh bôi đen chữ trên iPhone trở nên 100% êm ái, loại bỏ hoàn toàn cảm giác rung giật vật lý của máy.
- **Tối ưu độ mượt bôi đen text (`ReaderTextView.swift`)**:
  - Áp dụng debounce 120 ms cho `textViewDidChangeSelection` khi đang kéo chọn chữ (`length > 0`), cho phép UIKit render kính lúp loupe và các thanh neo ở 60/120fps native mà không bị giật lag do liên tục re-render SwiftUI.
  - Xử lý bỏ chọn tức thì (0 ms delay) khi `length == 0`, tắt Floating Menu ngay lập tức khi chạm ra ngoài.
  - Xóa lệnh dispatch async `UIMenuController.shared.hideMenu()` thừa thãi; tăng ngưỡng chống rung toạ độ `isSamePosition` lên 1.0 pt.
- **Tự động tắt cuộn theo highlight TTS (`ReaderView.swift`)**:
  - Trong `onSelectionChangeInParagraph`, tự động gán `isAutoScrollDisabled = true` khi phát hiện bắt đầu bôi đen (`selectionRange.length > 0`), ngăn TTS tự động cuộn trang tranh chấp với ngón tay người dùng.
- Gate: `check_architecture.py` không phát sinh vi phạm mới; `validate_links.py` PASS 100%.
