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
5. **Quyền Sở Hữu Ghi Từ Điển & Widget Nổi (1.3.244)**:
   - `DictionaryCache` sở hữu duy nhất quyền ghi tầng **chung custom** (`translateDirectory/Custom<VietPhrase|Names>.txt`) qua `upsertEntry/updateKey/deleteEntry/importEntries/clearAllEntries`; `TranslationManager` sở hữu duy nhất quyền ghi tầng **riêng theo sách** (`translateDirectory/books/<bookId>/*.txt`) qua `saveCustomEntry/deleteCustomEntry`. Hai tệp dựng sẵn `VietPhrase.dat`/`Names.dat` **không có chủ sở hữu quyền ghi** — không đường code nào trong `Sources/` mở chúng để ghi.
   - `DictionaryEntryTransferAction` không sở hữu gì: nó chỉ chọn một trong hai chủ trên theo `DictionaryTransferTarget`. `DictionaryTextFileStore` (Models) tiếp tục sở hữu duy nhất định dạng TXT và luật khử trùng key (`persist` giữ bản ghi đầu tiên của mỗi key).
   - `DictionaryHubView` sở hữu duy nhất ngữ cảnh "sách đang mở màn Từ điển" và truyền nó xuống dưới dạng `contextBookId`; `DictionaryListView` không tự suy ra sách từ bất kỳ nguồn toàn cục nào (không `TTSManager`, không "sách mở gần nhất").
   - `VisibleBrowserTabManager` sở hữu duy nhất trạng thái present/hide của trình duyệt và là nơi duy nhất đọc `VisibleBrowserSettings.opensMinimized`. `VisibleBrowserSettings` sở hữu tên khoá `UserDefaults`; tầng Views chỉ tham chiếu khoá đó qua `@AppStorage`, không tự viết lại chuỗi.
   - `VisibleBrowserPulseMonitor.shared` sở hữu duy nhất cờ `isPulsing` và `Timer` one-shot của nhịp nháy. `BrowserFloatingWidgetWindowManager.shared` sở hữu duy nhất `BrowserFloatingWidgetUIWindow` + container VC của widget trình duyệt; `TTSFloatingWidgetWindowManager.shared` giữ nguyên quyền sở hữu window TTS. `AppLaunchRootView` không sở hữu window nào — nó chỉ gọi `refreshState()`.
   - `VisibleBrowserReopenViewModel` sở hữu duy nhất hai giá trị vị trí bền (`visibleBrowserReopenVerticalRatio`, `visibleBrowserReopenEdge`) và cờ `isDragging`; `BrowserFloatingWidgetContainerViewController` sở hữu `center`/`bounds` thật của viên pill trong khi kéo. `FloatingWidgetGeometry` là hàm thuần, không sở hữu state nào — hai widget dùng chung nó mà không chia sẻ dữ liệu.
<!-- GENERATED END -->
