# CHANGELOG - Nhật ký Thay đổi CodeGraph FreeBook

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **FreeBook**.

---

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
