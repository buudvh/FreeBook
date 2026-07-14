# CHANGELOG - Nhật ký Thay đổi CodeGraph FreeBook

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **FreeBook**.

---

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
