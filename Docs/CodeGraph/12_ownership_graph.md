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
## Ai sở hữu bộ sưu tập và cờ ghim (1.3.328)

```
BookCollectionCoordinator                <- chủ sở hữu DUY NHẤT của việc ghi BookCollection
  |- createCollection / renameCollection / deleteCollection
  |- reorderCollections                  ghi lại sortOrder sau kéo-thả
  |- addBook / removeBook / setMemberships
  |- promoteToShelf (private)            bất biến "trong bộ ⇒ trên kệ", không phải tiện tay

BookTransactionCoordinator               <- chủ sở hữu của Book, kể cả isPinned và việc DỌN membership
  |- setPinned / setHistory              hai lối vào mới
  |- removeFromShelf                     hạ isOnShelf ⇒ collections = [], isPinned = false
  |- setOnShelf(false) / addBookToShelf  cùng luật dọn như trên

BookActionRunner                         <- KHÔNG sở hữu gì; gọi coordinator rồi hiện toast
BookActionSheet / CollectionsTabView     <- chỉ @Query để đọc, phát lệnh, xử lý Result
BackupLibraryWriter.restoreCollections   <- khôi phục kiểu gộp, đi qua coordinator như mọi đường ghi khác
```

* **Hai chủ sở hữu, một bất biến.** Bộ sưu tập thuộc `BookCollectionCoordinator`, nhưng bất biến "truyện trong bộ sưu tập luôn ở trên kệ" có **hai phía**: phía thêm (coordinator bộ sưu tập bật `isOnShelf`) và phía rời kệ (coordinator sách dọn `collections`). Đặt cả hai vào một chỗ là không được — hạ `isOnShelf` xảy ra ở đường xoá khỏi kệ, chỗ đó không biết gì về bộ sưu tập nếu không được dạy.
* **Xoá bộ sưu tập không bao giờ xoá sách**: `deleteRule: .nullify` lo phần dữ liệu, `deleteCollection` còn dọn tay `books = []` trước khi `context.delete` cho rõ ý. Đây là chỗ dễ hiểu sai nhất của tính năng nên nó được ghi cả trong code lẫn ở đây.
* **Ghim chỉ là thứ tự hiển thị**, không ai ngoài `BookTransactionCoordinator.setPinned` được ghi `Book.isPinned`; `check_architecture.py` đã canh sẵn chuỗi `.isPinned =` cho nhóm `SCOPED_VIEWS`.
* **Khôi phục backup không mở đường ghi mới**: `restoreCollections` gộp theo **tên** (không phân biệt hoa/thường) rồi gắn thành viên qua `addBook`, nên bất biến trên vẫn do coordinator giữ, không do writer tự làm.

## Ai duoc xoa hang tien ich (1.3.313)

```
ExtensionTransactionCoordinator          <- chu so huu DUY NHAT cua viec ghi/xoa hang Extension
  |- pruneRepositoryExtensions   xoa hang cua kho da go khoi registry (chi hang CHUA cai)
  |- applyInstallAudit           xoa hang mat file + khong co nguon tai lai; xoa localPath cho hang cua kho
  |- deleteExtension             xoa mot hang khi go tien ich khong co nguon tai lai

ExtensionInstallAudit                    <- chi DOC dia, khong so huu gi, khong ghi gi
RepositoryManagerView                    <- chuyen [Entry] -> Plan -> coordinator, khong tu quyet
```

* **Ba duong xoa nhung mot chu so huu.** Truoc luot nay chi co `pruneRepositoryExtensions`, va no co y **khong** cham hang da cai — dieu do dung cho tien ich cua kho nhung de lai hang chet cho tien ich import zip. Hai duong moi bu dung khoang trong do, khong noi long duong cu.
* **`isRegisteredExtension` la mot vi tu, khong phai trang thai luu tru**: `repository != nil || !downloadUrl.isEmpty`. Khong them cot DB nao de danh dau "import cuc bo".

## Chu so huu vi tri cuon Kham Pha (1.3.307)

```
DiscoveryView
  |- @State selectedCategoryId            (tab dang xem)
  |- @State scrollAnchors  -----------------> DiscoveryScrollAnchorStore  (class, @MainActor)
  |                                            |- anchors[categoryId] = link      (hang tren cung)
  |                                            |- visible[categoryId] = Set<link>
  |- TabView -> DiscoveryCategoryTabView (moi tab)
       |- @StateObject loader              (du lieu cua rieng tab)
       |- let scrollAnchors                (tham chieu, KHONG so huu)
```

* **Mot store cho ca man**, khong phai mot store moi tab: tab la thu bi do, nen no khong the la chu so huu cua thu phai song qua luot do do.
* **Tab chi ghi va doc, khong tao va khong xoa.** `removeAll()` chi duoc goi tu `DiscoveryView.loadDiscoveryData()` — dung mot chu so huu cho vong doi.
* `pendingRestoreAnchor` la `@State` **cua tab**: no la y dinh nhat thoi ("con mot neo chua ap duoc"), chet cung tab la dung.

## Rule dịch Quick Translate: engine, màn hình quản lý và công tắc (1.3.272)

* **Chủ của bộ rule đang chạy là `QuickTranslationRuleStore.shared`, và nó sở hữu bằng snapshot bất biến.** Snapshot nằm trong `nonisolated(unsafe) var snapshot` được `NSLock` bảo vệ; mọi bên đọc lấy **giá trị** (`activeSnapshot`) rồi tự dùng, nên một lượt `rewrite` đang chạy không bao giờ thấy bộ rule đổi giữa đường. Snapshot sở hữu rules đã compile, warning đã cắt và `sourceHash`; đổi bộ rule = tạo snapshot mới + `generation += 1`, không mutate snapshot cũ.
* **Bốn trạng thái, bốn chủ khác nhau, cố ý không gộp**: (1) *bộ rule* — Store/snapshot; (2) *công tắc tổng* — `UserDefaults` (`isQuickTranslateRuleEnabled`); (3) *policy tám token* — `QuickTranslationRuleTokenSettings` đọc `UserDefaults`, còn `QuickTranslationRuleTokenSettingsView` ghi qua `@AppStorage`; (4) *hiệu lực cache dịch* — `TranslateUtils` (`globalGeneration`/`settingsGeneration` + cache key `v4`). Mỗi rewrite chỉ sở hữu một `Configuration` value ngắn hạn; không chủ nào ghi policy vào file rule hoặc snapshot.
* **`status` là bản chiếu cho UI, không phải nguồn sự thật.** `@MainActor @Published private(set) var status` được cập nhật bằng `Task { @MainActor in }` sau khi swap xong (khuôn `JunkFilterManager`); mọi quyết định lúc chạy đọc `snapshot`/`isEnabled`, không đọc `status`. Vì vậy `status` trễ vài chu kỳ là vô hại.
* **Không có vòng giữ**: matcher giữ `[UInt16]` + `NSString` của chuỗi đang xử lý và một `QuickTranslationDictionaryToken` (struct chứa tham chiếu tới trie do `TranslationManager` sở hữu) — cả hai chết cuối lượt `rewrite`. Memo của engine là `NSCache` giữ `CacheEntry` (class chỉ bọc một struct), tự nhả khi hệ thống cần bộ nhớ.
* **Chủ của file rule là store, không phải View**: `ruleFileURL` = `TranslationManager.shared.translateDirectory/QuickTranslateRules.txt`. `QuickTranslationRulesView` không ghi file nào và **không** tự gọi mạng: nó bấm `store.downloadDefaultRules()` hoặc trao text đọc từ `DocumentPickerPresenter` cho `store.importRules`, còn khi xuất thì viết bản tạm ở `NSTemporaryDirectory()` để `ShareSheet` dùng. Cờ `isDownloading` cũng do store sở hữu (`@MainActor @Published`) để hai màn không bao giờ hiện hai trạng thái tải khác nhau.
* **CRUD từng rule cũng không phá quyền sở hữu đó**: `QuickTranslationRuleStore+Editing` (3 hàm) đọc records qua `QuickTranslationRuleRecordStore`, sửa theo **key** là pattern rồi trao lại Store đã tuần tự hoá để ghi file. Record store là hàm thuần, **không** chạm `FileManager`, nên vẫn chỉ có một nơi ghi file rule. Duplicate key lấy dòng đầu; update key cũ giữ vị trí, key mới append cuối; xoá định vị theo pattern sau khi file canonical bảo đảm duy nhất.

## Ai sở hữu recognizer, vệt tô và tập giữ lại (1.3.261)

* `UIPanGestureRecognizer` của đầu dò có **hai chủ theo hai nghĩa**: `UIScrollView` giữ nó strong (`addGestureRecognizer`), còn `ReaderUserScrollDetector.Coordinator` giữ tham chiếu strong để gỡ được và giữ `attachedScrollView` **weak**. Không có vòng giữ: `UIGestureRecognizer` không giữ target strong, và SwiftUI mới là chủ của `Coordinator` (qua `makeCoordinator`). Vì vậy `deinit` của `Coordinator` chỉ là lưới an toàn cho trường hợp `dismantleUIView` không chạy.
* `ProbeView.coordinator` là **weak** — probe do UIKit giữ, coordinator do SwiftUI giữ; nếu probe giữ strong thì coordinator sống thêm quá vòng đời `@State` của view.
* Vệt tô kết quả tìm thuộc **`ReaderView`, không thuộc `ReaderViewModel`**: `searchHighlight` là `@State` của View, `ReaderSearchMatcher` không giữ state nào, `ReaderSearchView` chỉ báo ra rồi đóng. Đây là chủ ý — vệt tô là dữ liệu trình bày thuần, không tham gia điều hướng lẫn tiến độ đọc, nên không được lẫn vào state điều hướng của ViewModel.
* Tập `keepPackageIds` do **`syncExtensions` sở hữu và tính một lần**, rồi trao cho DTO bất biến; `ExtensionTransactionCoordinator` chỉ đọc. Coordinator vẫn là chủ duy nhất của `ModelContext.save()` trong phân hệ kho tiện ích, và là chủ duy nhất của việc `context.delete(ext)` — View không bao giờ nắm quyền xoá bản ghi.


## Chủ của lịch sao lưu tự động, của khoá `isBusy` sau khi có lượt nền, và của appearance toàn app (1.3.260)

* **Lịch chạy có đúng một chủ và nó là UserDefaults, không phải coordinator hay view.** [`DriveAutoBackupPolicy`](../../Sources/Services/Backup/DriveAutoBackupPolicy.swift#L11) sở hữu 5 khoá công khai (`driveAutoBackupEnabled`/`Mode`/`CooldownHours`/`DailyHour`/`Scopes`) + khoá `private` `driveAutoBackupLastRunAt`. Mốc lần chạy cuối **chỉ** ghi được qua `markRun()` — không setter công khai nào khác, nên không view/worker nào "dời lịch" được. Tầng View dùng `@AppStorage` trỏ **đúng** các `static let ...Key` đó, nên không tồn tại bản sao chuỗi khoá thứ hai; việc kẹp biên (`6...168`, `0...23`) và hằng `maxVersions = 5` cũng thuộc policy.
* **`markRun()` được gọi lúc *bắt đầu* lượt, không lúc thành công** — đó là quyết định sở hữu, không phải chi tiết cài đặt: chủ của mốc cooldown là "đã thử", không phải "đã xong". Nhờ vậy một lượt thất bại (mất mạng, Drive từ chối) không biến mỗi lần mở app thành một lần nén archive vô ích.
* **Khoá `isBusy` của `BackupCoordinator` vẫn do tầng entry point sở hữu, nhưng tập entry point nay có thêm một lượt nền.** `runAutoDriveBackup` tự `guard !isBusy` rồi `setBusy(true)` + `defer { setBusy(false) }` — cùng hợp đồng với `runRestore`/`restoreEverythingFromDrive`. Vì lượt nền dùng **cùng** khoá, nó không bao giờ chồng với lượt thủ công (và ngược lại: đang sao lưu tay thì lượt nền trả `.skipped`, chờ tới lượt sau). Luật kèm theo: `setBusy`/`setProgress` là hai cửa **duy nhất** cho phần ở file khác, và **không** được gọi từ tầng View — chúng `internal` chỉ vì `private(set)` của Swift là phạm vi file.
* **`BackupProgress` vẫn một chủ (`@Published progress` của coordinator), nay có thêm người ghi và người đọc.** Người ghi mới là `autoReporter()` của lượt nền (hop về `@MainActor` rồi `setProgress`); người đọc thứ ba là `DriveAutoBackupSettingsView` (đọc `isBusy`, `isDriveSignedIn`, `lastError`). Không view nào giữ bản sao tiến độ riêng, và `DriveAutoBackupSettingsView` **xoá** `coordinator.lastError` sau khi đổ ra toast để lỗi không hiện lại lần sau.
* **Chủ của "bản nào được xoá" là quy tắc tên file, không phải danh sách nào cả.** `BackupPaths.isAutoBackupFileName` (tiền tố `freebook-auto-`) là vị từ duy nhất mà `pruneRemoteAutoBackups`/`pruneLocalAutoBackups` dựa vào; `LocalBackupStore` vẫn giữ nguyên quyền sở hữu thư mục `backups/` (dọn local đi qua `LocalBackupStore.delete(_:)`, không `FileManager` trực tiếp), và `GoogleDriveClient` vẫn là chủ duy nhất của mọi lời gọi Drive REST.
* **Appearance toàn app có đúng một chủ và một điểm gọi.** `FreeBookApp.init()` là nơi duy nhất cấu hình proxy UIKit: hai dòng `UITabBar.appearance()` sẵn có, nay thêm `NavigationBarAppearance.applyTitlelessBackButton()`. `NavigationBarAppearance` **sửa tại chỗ** object appearance đang có của `UINavigationBar.appearance()` (và chỉ chạm `compactAppearance`/`scrollEdgeAppearance`/`compactScrollEdgeAppearance` khi chúng khác `nil`) nên nó *thêm* thuộc tính chứ không **giành** quyền sở hữu nền navigation bar khỏi hệ thống. Không View nào được gọi lại hàm này.
* **Trạng thái đã-đọc của thông báo**: `NotificationInboxManager` là chủ duy nhất của `records`; `markRead(_:)`/`deleteUnread()` sửa RAM trước rồi bàn giao snapshot cho actor `NotificationInboxStore` (chủ duy nhất của `notifications.json`). `NotificationInboxView` không sở hữu bản sao nào — nó chỉ đọc và gọi hai hàm trên.

## Chủ sở hữu mốc đọc, khoá `isBusy` và tô màu trình soạn script (1.3.247)

* **Mốc đọc `Book.lastReadDate` nay có chủ rõ ràng ở hai vai**: `BookTransactionCoordinator.addBookToShelf` vẫn là **nơi ghi duy nhất** khi thêm sách, nhưng nó không còn là nơi *quyết định giá trị* — biểu thức `command.lastReadDate ?? Date()` giao quyền quyết định cho caller. Caller khôi phục (`BackupLibraryWriter.insertMissingBooks`) sở hữu giá trị lấy từ backup; caller thêm sách thủ công không truyền gì nên coordinator vẫn tự đóng `Date()`. Hệ quả về sở hữu: `AddBookToShelfCommand` là DTO bất biến nên không có đường nào khác ghi được field này, và không View nào chạm `Book.lastReadDate` trực tiếp.
* **Khoá `isBusy` của `BackupCoordinator` vẫn do đúng một tầng sở hữu — tầng entry point công khai.** `restoreEverythingFromDrive` và `runRestore` mỗi hàm tự `guard !isBusy` rồi giữ khoá; phần thân dùng chung `performRestore(prepared:container:options:)` là private và **cố ý không** giữ khoá. Luật kèm theo: mọi hàm mới muốn khôi phục phải gọi `performRestore`, không được gọi `runRestore` từ trong coordinator — làm vậy là tự khoá chính mình. Tiền điều kiện "TTS không đang phát" vẫn được kiểm ở **cả hai** entry point, không nằm trong thân dùng chung.
* `LocalBackupStore` giữ nguyên quyền sở hữu thư mục `backups/`: đường một chạm từ Drive tải xuống thư mục **tạm** rồi bàn giao cho `importArchive(from:)`, và tự xoá thư mục tạm bằng `defer`. `GoogleDriveClient` không bao giờ ghi thẳng vào `backups/`.
* `BackupProgress` chỉ có một chủ (`BackupCoordinator.@Published progress`) nhưng nay có **hai** người đọc (`BackupHubView`, `GoogleDriveBackupListView`); không view nào sở hữu bản sao tiến độ riêng.
* **Trình soạn script**: `CodeEditorTextView` sở hữu `keyboardObservers` (`[NSObjectProtocol]`) và tự gỡ trong `deinit` — không có chủ nào khác đăng ký observer bàn phím cho editor này, và `contentInset.bottom` chỉ được ghi từ `setKeyboardInset(_:)`. `HighlightingCodeEditor.Coordinator` sở hữu `regexCache` và nay là nơi **duy nhất** sửa attribute của `textStorage` khi người dùng gõ (`applyHighlight(to:fontSize:)` tại chỗ); đường gán lại `attributedText` chỉ còn ở `makeUIView`/`updateUIView`. `ExtensionScriptEditorView` sở hữu first responder gián tiếp qua `dismissKeyboard()` — hai file `+Picker`/`+Toolbars` là `extension` nên không thêm chủ sở hữu state nào.
* `RepositoryFilterPolicy` tiếp tục sở hữu duy nhất thứ tự danh sách tiện ích. `Extension.hasUpdate` là thuộc tính phái sinh (computed) nên không ai "sở hữu" nó: chủ hai field nguồn `version`/`remoteVersion`/`localPath` vẫn là `ExtensionTransactionCoordinator`.

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
