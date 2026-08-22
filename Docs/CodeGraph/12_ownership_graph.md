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
6. **Quyền Sở Hữu Sao Lưu/Khôi Phục, Đồng Bộ Ext & Sửa Thông Tin Truyện (1.3.246)**:
   - `BackupCoordinator.shared` sở hữu duy nhất trạng thái trình bày của phân hệ backup (`progress`, `isBusy`, `localBackups`, `driveFiles`, `isDriveSignedIn`, `preparedRestore`, `lastMessage`, `lastError`). Không View nào tự chạy worker; không worker nào tự hiện toast.
   - `BackupPaths` sở hữu duy nhất tên entry trong archive và đường dẫn thư mục `backups/`; `BackupZipArchive` sở hữu duy nhất mọi lời gọi ZIPFoundation của phân hệ. `BackupManifest.currentSchemaVersion` là nơi duy nhất định nghĩa phiên bản định dạng.
   - Quyền **ghi** khi restore vẫn thuộc owner cũ, không bị chuyển giao: `BackupLibraryWriter` (`@MainActor`) chỉ gọi `BookTransactionCoordinator`/`ExtensionTransactionCoordinator`; `ChapterStore` vẫn sở hữu `chapter_store.sqlite`; `BookBinManager` vẫn sở hữu `books/<sha256>.bin` và là nơi duy nhất sinh offset mới; `DictionaryTextFileStore` vẫn sở hữu định dạng TXT; `ExtensionManager` vẫn sở hữu `extensionsDirectory` và phép `findMainExtensionFolder`.
   - `BackupChapterRestorer` sở hữu duy nhất quyết định "offset trong backup còn hiệu lực hay không" (`keptOffsets`) — không nơi nào khác được copy offset qua máy khác.
   - `GoogleDriveConfiguration` sở hữu duy nhất việc nạp client id (Info.plist + override `UserDefaults("googleDriveClientId")`) và suy ra `redirectURI`; `GoogleDriveAuthService` sở hữu access token trong bộ nhớ; `GoogleDriveTokenStore` sở hữu duy nhất refresh token bền (Keychain, fallback file có file protection). Không type nào khác đọc hai nguồn này, và không nơi nào log giá trị token.
   - `ExtensionSyncCommandBuilder` sở hữu công việc tải/parse `plugin.json` khi đồng bộ kho (trước 1.3.246 nằm trong thân `RepositoryManagerView.syncExtensions`); `ExtensionTransactionCoordinator` sở hữu duy nhất `context.save()` cho cả lô.
   - `BookTransactionCoordinator.updateBookInfo` sở hữu duy nhất việc tính lại `titleTrans`/`authorTrans` khi người dùng tự sửa thông tin truyện; `ImageCacheManager.saveCover` là đường ghi duy nhất cho bìa do người dùng chọn từ máy (`covers/<sha256(bookId)>.jpg`), và cũng chỉ nó được xoá bìa để buộc tải lại theo `coverUrl`.
   - `BackupHubView` sở hữu quyền chặn restore khi TTS đang phát, nhưng **không** sở hữu trạng thái TTS — nó đọc qua projection reader `TTSWidgetStateReader`; `TTSManager` giữ nguyên quyền sở hữu tiến độ đọc trong lúc phát.
<!-- GENERATED END -->
