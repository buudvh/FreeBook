---
generated_by: Antigravity
generator_version: 1.0
generated_at: 2026-08-21T10:30:00+07:00
git_commit: UNKNOWN
source_files: 230
document_version: 7
---

# Dòng chảy Dữ liệu & Cơ chế Cache (Data Flow & Caching)

Tài liệu này theo dõi chi tiết đường đi của dữ liệu qua các tầng kiến trúc (Input -> View -> ViewModel -> Manager -> Repository -> Database) và làm rõ toàn bộ các cơ chế bộ nhớ đệm (Cache) đang vận hành trong dự án FreeBook.

## Ghi chú thủ công (Human Notes)
*Ghi chú thủ công của con người.*

<!-- GENERATED START -->
## Luồng sao lưu/khôi phục, đồng bộ ext theo lô, sửa thông tin truyện (1.3.246)

* **Luồng export**: `BackupHubView` → `BackupCoordinator.createBackup(container:scopes:)` → `BackupExportWorker.export(destination:)` ([BackupExportWorker.swift:26](../../Sources/Services/Backup/BackupExportWorker.swift#L26)) → **đúng một** `MainActor.run { BackupLibraryReader(container:).read(scopes:) }` → DTO `Sendable` → ghi `library/*.json` → mỗi sách `ChapterStore.fetchOrderedTOC(bookId:)` → `chapters/<slug>.json` → `stageContent` ([:178](../../Sources/Services/Backup/BackupExportWorker.swift#L178)) → `BackupZipArchive.stage(fileAt:)` (thử `linkItem` trước `copyItem`) → `manifest.json` ghi **cuối** → `FileManager.zipItem` → `backups/freebook-yyyyMMdd-HHmmss.fbbackup`. Nội dung chương **không bao giờ chảy qua RAM**: `.bin` đi theo đường file.
* `slug` (`b0001`, `b0002`…) là lớp trung gian bắt buộc giữa `bookId` và tên entry: `bookId` có thể chứa ký tự đường dẫn, và hàm sha256 bị cài lại độc lập ở từng owner nên không dùng làm tên entry được. `makeSlugTable` ([:98](../../Sources/Services/Backup/BackupExportWorker.swift#L98)) phủ cả `orphanDictionaryBookIds` — bookId chỉ còn từ điển riêng mà không còn trong thư viện vẫn có slug.
* **Luồng restore**: `RestoreOptionsSheet` → `BackupRestoreWorker.prepare(archive:)` ([:72](../../Sources/Services/Backup/BackupRestoreWorker.swift#L72), giải nén + decode manifest/slugs, xoá thư mục tạm nếu throw) → `restore()` ([:99](../../Sources/Services/Backup/BackupRestoreWorker.swift#L99)) theo đúng thứ tự: ext + kho → `insertMissingBooks` → TOC/nội dung từng sách → từ điển → `TranslationManager.loadAllDictionaries()` + `notifyDictionariesDidUpdate()` → `NotificationCenter.post("extensionDidUpdate")`. Toast không đi trong luồng này: `BackupCoordinator` chỉ đẩy `lastMessage`/`lastError`, `BackupHubView` mới hiển thị.
* **Nhánh quyết định offset** — chỗ dễ sai nhất của luồng dữ liệu chương ([BackupChapterRestorer.swift:39](../../Sources/Services/Backup/BackupChapterRestorer.swift#L39)): `localCount == 0` ⇒ `importFresh` ([:53](../../Sources/Services/Backup/BackupChapterRestorer.swift#L53)); ngược lại ⇒ `mergeIntoExisting` ([:119](../../Sources/Services/Backup/BackupChapterRestorer.swift#L119)).
  - `importFresh`: chỉ khi `installBinFile` ([:95](../../Sources/Services/Backup/BackupChapterRestorer.swift#L95)) copy được nguyên `content/<slug>.bin` vào chỗ chưa có file thì `keepsOffsets = true` và `offset/length/isCached` trong backup **còn hiệu lực**; sau đó `ChapterStore.importBookMigration(bookId:snapshots:statusInfo:)` ghi TOC + `is_cached/offset/length` trong **một transaction**. Không chọn nhóm `content`, hoặc `.bin` local đã tồn tại ⇒ cùng lời gọi nhưng `isCached=false, offset=0, length=0`.
  - `mergeIntoExisting`: `upsertPage` cho index còn thiếu (**chỉ metadata**), rồi với chương backup có cache mà local chưa cache: `FileHandle` đọc `length` byte tại `offset` trong `.bin` đã giải nén → `String(data:encoding:.utf8)` → `BookBinManager.writeChapterContent` (append, sinh offset **mới của máy này**) → `ChapterStore.updateCacheMetadata`. Offset từ backup **không bao giờ** được ghi vào DB ở nhánh này.
* **Luồng từ điển**: file TXT trong archive → `DictionaryTextFileStore.parseRecords` (bản local) → `mergedRecords(imported:existing:isMerge: true)` → `persist(records:to:)`. Vì `isDeleted` chính là `value.isEmpty` và tombstone nằm ngay trong TXT, luồng này mang cả "mục VP/Name đã xoá" mà không có định dạng riêng. `.dat` chung chỉ chảy vào máy khi **thiếu** file cùng tên, trừ khi người dùng tick "ghi đè từ điển chung".
* **Luồng đồng bộ ext (đổi)**: trước đây `syncExtensions` chảy tuần tự trên MainActor — mỗi ext một `URLSession.shared.data(from:)` rồi một `context.save()` riêng, và vì `allExtensions` là `@Query` nên mỗi save còn kéo view render lại (kho 60 ext ⇒ 60 request + 60 transaction). Nay: `allExtensions` → snapshot `[packageId: localPath]` (chụp một lần trên MainActor) → `ExtensionSyncCommandBuilder.build` ([:66](../../Sources/Services/Extensions/Manager/ExtensionSyncCommandBuilder.swift#L66)) chạy `withTaskGroup` cửa sổ trượt 6 lượt **ngoài main** ([:75](../../Sources/Services/Extensions/Manager/ExtensionSyncCommandBuilder.swift#L75), timeout 10 s/request) → `[UpsertExtensionCommand]` **giữ đúng thứ tự input** → `ExtensionTransactionCoordinator.upsertExtensions` → **một** `save()`. Thứ tự fallback dữ liệu mỗi ext không đổi: `plugin.json` local → `plugin.json` remote → hàng registry → mặc định (`locale "vi_VN"`, `ExtensionType.novel`, `version 1`).
* **Luồng sửa thông tin truyện**: `BookInfoEditView` → (ảnh trong máy) `PhotosPicker` → `Data` → `ImageCacheManager.saveCover(data:for:)` (downscale ≤ 1024 px, JPEG 0.85, ghi `covers/<sha256(bookId)>.jpg`); (URL mới) `ImageCacheManager.deleteCover(for:)` để `BookCoverView` tự tải lại → `BookTransactionCoordinator.updateBookInfo(command:in:)` → `title/author/coverUrl` + **tính lại** `titleTrans`/`authorTrans` → `save()`. `Result` được xử lý ở View nên không có nhánh nào bỏ lỗi im lặng.

## Luồng cài đặt mở thu nhỏ và luồng mở lại container (1.3.245)

* **Cờ `opensMinimized` nay được đọc ở ba điểm, không phải một.** Ngoài `openContainer(initialActiveId:)` (1.3.244), `addTab` đọc nó ở **cả hai** nhánh có thể mở container: nhánh tab mới khi đang thu nhỏ (đã có từ 1.3.244) và nhánh **tab ID trùng** (mới ở 1.3.245). Mục 1.3.244 bên dưới nói "đọc một lần mỗi lần mở tại `openContainer`" — điều đó không còn đủ để mô tả luồng.
* Luồng thật của `Engine.newVisibleBrowser()` + `launch(url)` khi cờ **bật**: `_nativeBrowserNewVisible` → `VisibleWebViewLoader(id:title:)` → `presentUIIfNeeded()` → `addTab` (ID mới) → `openContainer` → `prepareContainerMinimized()` (`isHidden = true`, `isPresented = false`, container `loadViewIfNeeded()` nhưng không present) → `_nativeBrowserLaunchVisible` → `loader.load(url:…)` → `presentUIIfNeeded()` **lần hai** → `addTab` (ID trùng) → `activateTab(id:)` **và dừng ở đó**. Trước 1.3.245 lượt thứ hai này chảy tiếp vào `selectTab` → `reopenContainer()`, nên dữ liệu cài đặt bị vô hiệu ngay ở bước cuối.
* `activateTab(id:)` là đường lập trình duy nhất ghi `activeTabId`; nó **không** đọc `opensMinimized` và không đổi `isHidden`/`isPresented` — cờ chỉ được hỏi ở caller. Nhờ vậy cùng một hàm dùng được cho cả hai trạng thái cài đặt.
* Luồng nạp trang **không** đi qua trạng thái present: `load`/`loadAsync` gọi `webView.load(request)` ngay sau `presentUIIfNeeded()` ([VisibleWebViewLoader.swift:111](../../Sources/Services/Extensions/Engine/VisibleWebViewLoader.swift#L111), [:150](../../Sources/Services/Extensions/Engine/VisibleWebViewLoader.swift#L150)), nên tab vẫn nạp khi container chưa bao giờ được present. Chưa xác minh runtime cho các trang cần tương tác thật (xem `10_risk_report.md`).
* Luồng mở lại container: cử chỉ (tap widget / accessibility action / pill tab) → `reopenContainer()` → `findTopViewController()` (chỉ window level `.normal`) → `navigationController(wrapping:)` → `present` → `notifyStateChanged()` → hẹn `verifyReopenPresented(nav)`. Nếu 1.2 s sau `nav.presentingViewController == nil` thì trạng thái chảy **ngược** về `isHidden = true` + `navController = nil` và widget hiện lại.
* Luồng màu nháy: `VisibleBrowserPulseMonitor.isPulsing` → `isPulseBright` → `pulseLevel` (0.4 ↔ 1.0) → `Color(red:green:blue:)` đặc. Không có giá trị nào chảy vào `opacity`/alpha, nên `hitTest` của window widget không phụ thuộc nhịp nháy.

## Luồng copy từ điển và luồng cài đặt mở thu nhỏ (1.3.244)

* **Ba tầng từ điển, chỉ hai tầng ghi được.** Dựng sẵn: `translateDirectory/VietPhrase.dat` + `Names.dat` (DoubleArrayTrie, nạp lúc khởi động, **không có đường ghi nào**). Chung custom: `translateDirectory/Custom<VietPhrase|Names>.txt`. Riêng: `translateDirectory/books/<bookId>/<VietPhrase|Names>.txt`. Cả hai tầng custom là TXT `key=value` do `DictionaryTextFileStore` đọc/ghi (`parseRecords`, `persist`, `loadEntries`, `mergedRecords`, `normalizeMeaning`); thứ tự ưu tiên khi tra là riêng > chung custom > dựng sẵn, và bản ghi giá trị rỗng trong TXT là "tombstone" che entry dựng sẵn.
* Luồng copy **Chung → Riêng**: `DictEntry(key, value)` (đọc từ `Custom*.txt`) → `DictionaryEntryTransferAction.copy` → `TranslationManager.saveCustomEntry(word:meaning:isName:bookId: <bookId màn Từ điển đang mở>)` → `parseRecords(books/<bookId>/*.txt)` → `records.removeAll { $0.key == cleanWord }` → `insert(at: 0)` → `persist` → `bookDicts.removeValue(forKey:)` → `loadAllDictionaries()` → `notifyDictionariesDidUpdate(scope: .term(...))`. File chung **không được mở để ghi** trên đường này.
* Luồng copy **Riêng → Chung**: `DictEntry` (đọc từ `books/<bookId>/*.txt`) → `DictionaryCache.upsertEntry(key:value:type:)` → `currentRecords` từ `Custom*.txt` → `removeAll` key trùng → `insert(at: 0)` → `persist` → cập nhật `@Published` entries → `loadAllDictionaries()` → `notifyDictionariesDidUpdate(bookId: nil)`. File riêng và hai `.dat` **không được mở để ghi**.
* Ba luật ghi là **hệ quả trực tiếp của `removeAll` + `insert(at: 0)`**, không phải nhánh `if` phải bảo trì: key chưa có trong custom ⇒ tạo mới; key đã có ⇒ ghi đè trọn giá trị (không trùng lặp, không gộp, không bỏ qua) — `天才 = thiên tài` bị `天才 = thiên tài tuyệt thế` thay hẳn; key chỉ có ở dựng sẵn ⇒ TXT nhận bản ghi mới đóng vai override, `.dat` giữ nguyên nên `天道 = Thiên Đạo` vẫn còn trong dựng sẵn còn custom mang `天道 = thiên đạo của thế giới này`. Nguồn không bị đọc-để-xoá ở bất kỳ nhánh nào — đây là **copy**, không phải move.
* `normalizeMeaning` là điểm chuẩn hoá duy nhất trên cả hai đường (được gọi bên trong hai API ghi), nên giá trị copy sang đích giống hệt giá trị người dùng thấy ở nguồn.
* Luồng ngữ cảnh sách: `BookDictionaryView` → `DictionaryHubView(bookId:bookName:)` → `DictionaryListView(type:bookId:contextBookId:)`. Hai link chung truyền `bookId: nil, contextBookId: bookId`; hai link riêng truyền `bookId: bookId` như cũ. `transferContextBookId = bookId ?? contextBookId` ⇒ đích riêng **luôn** là sách của màn Từ điển đang mở; không có nguồn dữ liệu nào khác (không TTS, không "sách mở gần nhất", không picker) chảy vào tham số `bookId` của `saveCustomEntry`.
* Luồng lọc truyện đích: `@Query`/`loadBooks()` → `books: [Book]` → `filteredBooks` = `ShelfBookSearchMatcher.matches(query:title:titleTrans:author:authorTrans:)` → `List`. Dữ liệu chọn đích (`Book` được chạm → `dictionaryModeDialog` → callback) đi đúng đường cũ; bộ lọc chỉ thu hẹp tập hiển thị.
* Luồng cài đặt mở thu nhỏ: `Toggle` (`@AppStorage(VisibleBrowserSettings.openMinimizedKey)`) → `UserDefaults.standard["openVisibleBrowserMinimized"]` → `VisibleBrowserSettings.opensMinimized` → đọc **một lần mỗi lần mở** tại `VisibleBrowserTabManager.openContainer(initialActiveId:)`. Không có bản sao cờ này ở nơi khác, và nó không chảy vào bất kỳ tab/loader nào.
* Luồng tuổi tab: `VisibleBrowserTabItem.createdAt` (đặt lúc tạo) → `VisibleBrowserPulseMonitor.evaluate()` tính `max(now - createdAt)` → `isPulsing` → `opacity`. Không dữ liệu nào được lưu bền cho việc nháy.
* Luồng vị trí widget trình duyệt: `UIPanGestureRecognizer.translation` → `widgetContainerView.center` (ghi trực tiếp, không qua state) → khi nhả: `FloatingWidgetGeometry.nearestEdge/clampedCenterY` → `verticalRatio` + `edgeDirection` → `UserDefaults`; chiều đọc ngược lại chỉ xảy ra ở `restingCenter(in:)`.

## All-source novel-search data flow (1.3.225)

* Caller-provided `[Extension]` → `SearchView.searchableExtensions` removes `type == "tts"` → parallel extension search → per-source UI state/results. The filtered collection is reused by the `Xem thêm` destination; no TTS extension reaches `ExtensionManager.search` through the all-source path.

## Local TXT title translation and search data flow (1.3.224)

* `ParsedBook.chapters` → detached `TranslateUtils.translateChapterTitle` + metadata map → `ChapterMetadataSnapshot.title/titleTrans` → `ChapterStore.replaceFullTOC` → SQLite `chapter_metadata.title/title_trans`. Cache offset/length updates reuse the same snapshot and do not discard `titleTrans`.
* Local chapter query → one `%query%` pattern bound to both stored title columns → `StoredChapterSnapshot` results → presentation chooses the row title according to `isTranslationEnabled`. No import-time or startup backfill is performed for older local books.

## Sơ Đồ Luồng Dữ Liệu (Data Flow v4.1/v5.0)

1. **Luồng Dữ Liệu Giao Dịch Lưu Trữ**:
   `SwiftUI View` -> (Tạo `Command DTO`) -> `Transaction Coordinator` -> `SwiftData ModelContext` -> `Persistent Store`
   - Dataflow hoàn toàn một chiều và bất biến ở ranh giới View.

2. **Luồng Thực Thi Tiện Ích Bóc Tách Cách Lý**:
   `BookDetailView` / `ReaderView` -> `ExtensionExecutionSnapshot` -> `JSExecutor.runAsync` -> `VBook JS Engine` -> `DTO Results`

3. **Luồng Tải Trang & Tìm Kiếm Chương Nền**:
   `ReaderViewModel` -> `BackgroundPagingWorker` / `BackgroundSearchWorker` -> `ChapterStore` -> `ChapterRowItem` / `SearchChapterDTO` -> `@Published` UI State

4. **Luồng dữ liệu NghiTTS an toàn khi chuyển chương (1.3.147)**:
   `paragraph.text` -> replacements -> `TextPreprocessor` -> kiểm tra speakable
   - Speakable -> Piper ONNX -> PCM/WAV -> `preloadedData[index]`.
   - Unspeakable -> silence samples -> WAV hoặc một terminal streaming payload -> cache/playback như audio bình thường.
   - Failure metadata chỉ lưu khóa định danh session/chapter/paragraph, số attempt và cờ block; không lưu nội dung văn bản người dùng trong log.
<!-- GENERATED END -->
