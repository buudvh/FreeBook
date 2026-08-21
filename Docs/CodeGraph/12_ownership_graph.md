---
generated_by: Antigravity
generator_version: 1.0
generated_at: 2026-08-21T10:30:00+07:00
git_commit: UNKNOWN
source_files: 230
document_version: 5
---

# Đồ thị Sở hữu Đối tượng (Ownership Graph)

Tài liệu này mô tả mối quan hệ sở hữu đối tượng (Object Ownership) trong dự án FreeBook.

## Ghi chú thủ công (Human Notes)
*Ghi chú thủ công của con người.*

<!-- GENERATED START -->
## Sơ Đồ Quyền Sở Hữu & Quyền Hạn (Ownership Graph v4.1/v5.0)

1. **Quyền Sở Hữu Giao Dịch SwiftData**:
   - `BookTransactionCoordinator` & `ExtensionTransactionCoordinator` sở hữu duy nhất quyền thực thi mutation và `context.save()` cho các luồng giao dịch được duyệt trong SwiftUI Views.

2. **Quyền Sở Hữu Phát Sự Kiện Presentation (Toast Output)**:
   - `TTSPresentationEventCenter` sở hữu `AsyncStream<TTSPresentationEvent>`.
   - `DownloadPresentationEventCenter` sở hữu `AsyncStream<DownloadPresentationEvent>`.
   - `AppLaunchRootView` (`FreeBookApp.swift`) sở hữu duy nhất quyền subscribe stream và chuyển giao hiển thị Toast lên UI.

3. **Quyền Sở Hữu Công Việc Nền & Task Cancellation**:
   - `ReaderViewModel` sở hữu `ReaderProgressScheduler` và `Task` dịch thuật.
   - `BookDetailView` sở hữu `bookOpenTask` và task tải còn lại background.

4. **Quyền Sở Hữu Route Điều Hướng Khám Phá (Discovery Detail Route Ownership 1.3.228)**:
   - `DiscoveryView` sở hữu duy nhất `@State private var selectedDetailRoute: DiscoveryDetailRoute?` và đăng ký modifier `.navigationDestination(item: $selectedDetailRoute)` tại cấp root `NavigationStack`.
   - `DiscoveryCategoryTabView` không sở hữu state route hay modifier navigation destination; child view chỉ gọi callback truyền dữ liệu snapshot dạng value type lên view cha.
<!-- GENERATED END -->
