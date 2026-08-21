---
generated_by: Antigravity
generator_version: 1.0
generated_at: 2026-08-21T10:30:00+07:00
git_commit: UNKNOWN
source_files: 218
document_version: 6
---

# Máy Trạng thái (State Graph)

Tài liệu này phân tích chi tiết các máy trạng thái (State Machine) đang vận hành trong dự án FreeBook.

## Ghi chú thủ công (Human Notes)
*Ghi chú thủ công của con người.*

<!-- GENERATED START -->
## Sơ Đồ Quản Lý Trạng Thái & Sự Kiện (State Graph v4.1/v5.0)

1. **Luồng Sự Kiện Presentation Bất Đồng Bộ**:
   `Services` (`TTSManager`, `DownloadManager`)
     └── Phát event -> `AsyncStream.Continuation`
           └── `AppLaunchRootView` (`AsyncStream` Consumer)
                 └── `@State` Toast presentation trong UI root context

2. **Trạng Thái Giao Dịch Dữ Liệu Khách (Coordinator Ownership)**:
   - Client Action (UI Event) -> Khởi tạo Command DTO bất biến -> Chuyển giao cho Coordinator (`BookTransactionCoordinator` / `ExtensionTransactionCoordinator`).
   - Coordinator thực hiện fetch/validate/mutate/save trên `ModelContext` -> Trả về `Result<T, Error>`.
   - View nhận `Result`: Hiển thị thành công hoặc cập nhật `@State errorMessage` mà không bao giờ thay đổi trực tiếp đối tượng `@Model`.

3. **Máy trạng thái lỗi NghiTTS refill (1.3.147)**:
   - `idle` -> tổng hợp prefetch -> `success`: xóa failure state và tiếp tục cập nhật cửa sổ đệm.
   - Lỗi tạm thời lần đầu -> `retryScheduled(attempt: 1)`: khóa scheduler, chờ 1 giây, xác thực session/chapter/generation rồi thử lại.
   - Lỗi tạm thời lần hai hoặc lỗi không retry -> `blocked`: bỏ qua paragraph index đó trong các lần chọn prefetch tiếp theo.
   - `CancellationError`, stop, đổi session hoặc chuyển chương -> `cancelled/reset`: hủy retry task và xóa toàn bộ state liên quan, không ghi lại state từ task cũ.
<!-- GENERATED END -->
