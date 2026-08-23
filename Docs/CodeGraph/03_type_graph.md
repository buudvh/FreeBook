---
generated_by: Antigravity
generator_version: 1.0
generated_at: 2026-08-21T10:30:00+07:00
git_commit: UNKNOWN
source_files: 230
document_version: 5
---

# Đồ thị Kiểu dữ liệu (Type Graph)

Tài liệu này liệt kê chi tiết định nghĩa và mối quan hệ giữa các kiểu dữ liệu (Class, Struct, Enum, Protocol, Actor, Extension) trong dự án FreeBook.

## Ghi chú thủ công (Human Notes)
*Đây là khu vực con người tự viết ghi chú, AI không được phép ghi đè.*

<!-- GENERATED START -->
## Type của tìm-Reader + Trung tâm thông báo (1.3.258)

* **Gỡ mọi type của phân hệ tìm toàn văn 1.3.257** (`ChapterSearch*`, `SearchScope`…) cùng 10 file bị xoá. Không type nào khác tham chiếu chúng.
* [`ReaderSearchMatcher`](../../Sources/Common/Utils/ReaderSearchMatcher.swift#L1) là `enum` namespace thuần (không case, không state) với 3 struct lồng để giữ đúng 1 type top level: `Paragraph { paragraphIndex, isTitle, original, translated }`, `Chapter { chapterIndex, paragraphs }`, `Hit { chapterIndex, paragraphIndex, isTitle, snippet, matchedInTranslated }` (`id = "\(chapterIndex).\(paragraphIndex).\(matchedInTranslated)"`). `paragraphIndex` thừa hưởng `ParagraphItem.id` **sparse** (chỉ số dòng thô, không phải array offset) — dùng thẳng cho điều hướng, không index vào mảng.
* Phân hệ Trung tâm thông báo thêm ba type ở `Common`: [`NotificationInboxRecord`](../../Sources/Common/Services/NotificationInboxRecord.swift#L1) (`Codable, Identifiable, Sendable, Equatable`: `id: UUID`, `message`, `type: ToastType`, `date`, `var isRead`) với `init(from:)` chịu lỗi (mọi field `decodeIfPresent`); `NotificationInboxStore` (actor); `NotificationInboxManager` (`@MainActor ObservableObject`). Kèm **retroactive conformance** `extension ToastType: Codable` (map string `success`/`error`/`info`) — `ToastType` gốc chỉ `Sendable, Equatable`, nên conformance này là điểm phải giữ khi đổi `ToastType`. [`NotificationInboxView`](../../Sources/Views/Shelf/ShelfMain/NotificationInboxView.swift#L1) lồng `enum InboxItem: Identifiable { case newChapter(NewChapterRecord); case toast(NotificationInboxRecord) }` với `date`/`sortRank` để gộp-nhóm hai nguồn.

## Type của phân hệ nhập truyện đa định dạng (1.3.251)

* **Dời tầng, không đổi shape**: `ParserChapter` (`title`, `content`) và `ParsedBook` rời `Sources/Views/Shelf/ShelfMain/ShelfView.swift` xuống `Sources/Services/Import/` — bắt buộc, vì parser ở tầng Services không được trả về type khai trong tầng View (sẽ đảo chiều phụ thuộc). Cả hai vẫn `Sendable`.
* `ParsedBook` **đổi shape** (thêm field, mọi field mới có `= nil` nên call site cũ biên dịch không đổi): `author`, `desc`, `coverData: Data?`, `remoteCoverUrl: String?`, `structureNote: String?`. `title` + `chapters` giữ nguyên vị trí và ngữ nghĩa.
* **Xoá**: `TXTReanalysisResult` — thay bằng [`BookImportService.Result`](../../Sources/Services/Import/BookImportService.swift#L1) (`parsed`, `format`, `autoDecodeID`, `matchedRuleIDs`), một type ít hơn ở top level.
* `BookImportFormat` (`enum: String, CaseIterable`, 4 case `txt`/`html`/`epub`/`mobi`): `displayName`, `static detect(fileName:data:)` (đuôi file trước, magic bytes sau), `static pickerContentTypes: [UTType]` (`compactMap` nên UTI động thiếu thì bỏ, không crash).
* `BookImportService` (`enum` namespace, không case) là **điểm vào duy nhất** của phân hệ; 4 type lồng để giữ đúng 1 type top level mỗi file: `StructureMode` (`String, CaseIterable, Identifiable`: `auto`/`tocIndex`/`spine`/`tocRules` + `displayName`), `Request`, `Result`, `ImportError` (`LocalizedError`: `drmProtected`, `unsupportedCompression`, `emptyContent`, `malformed(String)` — `errorDescription` tiếng Việt để View đổ thẳng vào Toast). Thành viên: `static parse(_:) async throws -> Result`.
* Namespace thuần (`enum`, không case, không state): `TxtBookParser` (`parse(content:fileName:rules:)`, `bookTitle(fromFileName:)`), `HtmlBookParser.parse(html:fileName:rules:structure:)`, `MobiBookParser.parse(data:fileName:rules:structure:encodingOverride:) throws`, `PalmDocDecompressor` (`decompress(_:)`, `stripTrailingEntries(record:flags:)`), `XhtmlTextExtractor` (type lồng `Section { title, text }`; `plainText(html:)`, `inlineText(html:)`, `headingSections(html:) -> [Section]?`, `firstHeading(html:)`, `firstTagText(html:tags:)`, `firstImageSrc(html:)`, `dropLeadingTitle(_:title:)`, `anchorSegments(html:anchorIds:) -> [String: String]`, `declaredCharsetName(in:)`).
* `EpubArchiveReader.read(fileUrl:) throws -> Package`; `Package { rootDirectory, opfURL, opfDirectory }` mang **method** `resolve(href:base:) -> URL?` — trả `nil` khi file không tồn tại **hoặc** đường dẫn thoát ra ngoài `rootDirectory` (chặn zip-slip), `base` mặc định là thư mục OPF vì href trong NCX/nav phải giải theo thư mục của chính file mục lục.
* `EpubOpfParser.parse(opfURL:) throws -> Manifest` (2 type lồng: `Item { href, mediaType, properties }`, `Manifest`); `EpubNavParser` có `parseNcx(data:) -> [Entry]` + `parseNav(html:) -> [Entry]` (type lồng `Entry { title, href, fragment, depth }`); `MobiArchiveReader.read(data:) throws -> Package` (type lồng `Package { textData, charsetName, title, author, desc, coverData, … }`, `private typealias Failure = BookImportService.ImportError` để `throw` trực tiếp lỗi của tầng service); `EpubBookParser.parse(fileUrl:fileName:rules:structure:) throws -> ParsedBook`.
* `TextEncodingDecoder` thêm hai thành viên `static`: `option(forCharsetName:) -> TextEncodingOption?` (ánh xạ tên IANA) và `decodeDeclared(_:charsetName:) -> String?` (trả `nil` để caller rơi về auto-detect). `decode(_:)`/`detect(_:)` giữ nguyên chữ ký. **Không** thêm case cho `TextEncodingOption` — thêm case là đổi thứ tự ưu tiên auto-detect của TXT.
* `BookImportConfirmationSheet` thay `TXTImportConfirmationSheet`: thêm `let format: BookImportFormat`, `@State var selectedStructure: BookImportService.StructureMode`, case `structure` trong `PickerType`; `onReanalyze` đổi chữ ký thành `(String?, Set<String>, BookImportService.StructureMode) async -> BookImportService.Result?`. Các `@State` phải `internal` vì `private` của Swift là phạm vi **file** mà 3 picker nằm ở `+Pickers.swift`.
* `ShelfView` đổi tên thành viên: `importTxtBook(from:)` → `importLocalBook(from:)`, `reanalyzeTxt(...)` → `reanalyzeImport(decodeID:ruleIDs:structure:tempFileUrl:fileName:)`, `@State isParsingTXT` → `isParsingImport`; `parseTxtBook` bị xoá (dời sang `TxtBookParser`). `PendingImport` thêm `let format: BookImportFormat`.
* Không `@Model` nào đổi shape ⇒ không có rủi ro lightweight migration. `Book.isLocalBook` chỉ dựa `extensionPackageId`/`detailUrl`/`sourceName` nên việc `performImport` nay ghi `author`/`desc` thật từ file **không** làm sách mất tính "local".

## Đổi shape command khôi phục + API tô màu trình soạn script (1.3.247)

* `AddBookToShelfCommand` **đổi shape** (lần đầu): thêm `public let lastReadDate: Date?` cuối danh sách thuộc tính, tham số init `lastReadDate: Date? = nil` — mặc định `nil` nên **mọi call site cũ biên dịch không đổi**. Ngữ nghĩa: `nil` = lấy `Date()` như trước (thêm sách thủ công), có giá trị = giữ đúng mốc đọc của máy nguồn khi khôi phục. Điểm đọc duy nhất là `BookTransactionCoordinator.addBookToShelf` (`command.lastReadDate ?? Date()` ở cả hai nhánh); điểm ghi duy nhất là `BackupLibraryWriter.insertMissingBooks`. Không `@Model` nào đổi shape ⇒ không rủi ro lightweight migration. Điều này **thay thế** câu "`AddBookToShelfCommand` không đổi shape" ở mục 1.3.246 dưới đây.
* `BackupCoordinator` thêm hai thành viên: `restoreEverythingFromDrive(_:container:) async` (public) và `performRestore(prepared:container:options:) async` (private — thân dùng chung, **không** tự giữ `isBusy`). `runRestore(container:options:)` giữ nguyên chữ ký, nay chỉ là lớp bọc giữ khoá quanh `performRestore`.
* `RepositoryFilterPolicy.sortExtensions(_:)` giữ nguyên chữ ký, thêm khoá so sánh đầu tiên `hasUpdate`. `Extension.hasUpdate` không đổi.
* `CodeEditorTextView` thêm state riêng tư `keyboardScreenFrame: CGRect?` + `keyboardObservers: [NSObjectProtocol]`, `deinit` gỡ observer, override `layoutSubviews()`, và ba hàm riêng tư `observeKeyboard()` / `applyKeyboardInset()` / `setKeyboardInset(_:)`. `gutterWidth`, `updateGutterInset()`, `draw(_:)` không đổi.
* `HighlightingCodeEditor.Coordinator` thêm `applyHighlight(to:fontSize:)` (public — tô tại chỗ trên `textStorage`), `tokenColors(in:) -> [(NSRange, UIColor)]` (internal) và `intersectsProtected(_:_:)` (private, tìm nhị phân). `highlight(_:fontSize:) -> NSAttributedString` giữ nguyên chữ ký (dùng cho `makeUIView`/`updateUIView`) nhưng nay dựng màu từ `tokenColors`. `regexCache` đổi **tập khoá**: hai khoá `comment` + `string` gộp thành một khoá `protected`.
* `ExtensionScriptEditorView` không đổi thuộc tính hay chữ ký nào — chỉ chuyển khai báo sang hai file `extension` mới; `dismissKeyboard()` là thành viên `internal` mới duy nhất. `ScriptFileInfo` không đổi.
* Không type nào bị xoá, đổi tên, đổi kế thừa hay đổi conformance trong lần này.

## Type mới cho sao lưu/khôi phục, đồng bộ ext theo lô, sửa thông tin truyện (1.3.246)

* `EditBookInfoCommand` (`struct`, bất biến): `bookId`, `title`, `author`, `coverUrl`. Command DTO duy nhất được thêm; `AddBookToShelfCommand` và `UpsertExtensionCommand` **không đổi shape**.
* `BookTransactionCoordinator` thêm `updateBookInfo(command:in:) -> Result<Void, Error>` (`@discardableResult`), tính lại `titleTrans = TranslateUtils.translateMeta(...)` và `authorTrans = TranslateUtils.translateAuthorHanViet(...)` — xem [BookTransactionCoordinator.swift:89](../../Sources/Services/Books/BookTransactionCoordinator.swift#L89). `updateBookMetadata` cũ giữ nguyên hành vi (không đụng hai field dịch), nên hai API cố ý cùng tồn tại.
* `ExtensionTransactionCoordinator` thêm `upsertExtensions(commands:in:)` (một `save()` cho cả lô) và private `apply(command:in:)` dùng chung với `upsertExtension` — xem [ExtensionTransactionCoordinator.swift:47](../../Sources/Services/Extensions/ExtensionTransactionCoordinator.swift#L47). Chữ ký `upsertExtension(command:in:)` không đổi.
* `ExtensionSyncCommandBuilder` (`enum` namespace, không case): type lồng `Input { item: ExtensionRegistryItem, existingLocalPath: String }`, `static let defaultConcurrency = 6`, `requestTimeout: TimeInterval = 10`, `packageId(forName:)`, `build(inputs:repositoryUrl:maxConcurrent:) async -> [UpsertExtensionCommand]` (giữ đúng thứ tự input).
* `ImageCacheManager` thêm `saveCover(data:for:maxDimension:quality:) -> UIImage?` (`@discardableResult`) và private `downscaled(_:maxDimension:)`; dùng lại `validatePathSafety`/`getNewFileName` private sẵn có, không thêm root lưu trữ mới.
* Phân hệ backup — mỗi type một file, `Sources/Services/Backup/`:
  - Giá trị/DTO: `BackupScope` (`enum: String, CaseIterable`, 6 case, `isMandatory`, `defaultSelection`, `displayOrder`), `BackupManifest` (`Codable`, type lồng `Counts`, `currentSchemaVersion = 1`, `isSupported`), `BackupPayload` (`enum` namespace chứa `BookRecord`/`RepositoryRecord`/`ExtensionRecord`/`ChapterRecord`/`SlugRecord`), `BackupProgress` (`struct` + `enum Phase` 17 case, `idle`), `GoogleDriveFile` (`Codable`), `LocalBackupStore.Item`.
  - Namespace thuần: `BackupPaths` (tên entry archive + `backupsDirectory`), `BackupZipArchive`, `BackupSizeEstimator`, `BackupDictionaryArchiver`, `GoogleDriveConfiguration`.
  - Actor: `BackupExportWorker`, `BackupRestoreWorker` (type lồng `Prepared`/`Options`/`Outcome`/`Failure`), `GoogleDriveClient`, `GoogleDriveUploader`.
  - `@MainActor`: `BackupCoordinator` (`ObservableObject`, singleton `.shared`), `BackupLibraryReader` (chỉ đọc, type lồng `Payload`), `BackupLibraryWriter` (`struct`), `GoogleDriveAuthService` (type lồng `PresentationProvider`, `Failure`).
  - Còn lại: `BackupChapterRestorer`, `BackupExtensionInstaller`, `BackupDictionaryRestorer`, `GoogleDriveTokenStore`, `LocalBackupStore`.
* View mới đều là `struct: View` một type/file: `BookInfoEditView`, `BackupHubView`, `BackupScopeToggleList`, `LocalBackupListView`, `GoogleDriveBackupListView`, `RestoreOptionsSheet`, `BackupSettingsSection`, `TTSSettingsSection`. `TTSSettingsSection` là phép trích **nguyên văn** mục TTS khỏi `SettingsView` — không type nào của màn TTS đổi.
* Không type nào bị xoá, đổi tên, đổi kế thừa hay đổi conformance trong lần này. Không `@Model` nào đổi shape ⇒ không có rủi ro lightweight migration.

## Type mới cho copy từ điển và widget trình duyệt (1.3.244)

* `DictionaryTransferTarget` (`enum`, `Equatable`): `case globalCustom` và `case privateBook(bookId: String)`. Đây là **toàn bộ** vốn từ vựng về đích copy — không có case nào trỏ tới dữ liệu dựng sẵn (`.dat`), nên "ghi vào built-in" không biểu diễn được bằng type.
* `DictionaryEntryTransferAction` (`@MainActor enum` không case, dùng như namespace): `copy(key:value:destinationType:target:) async throws` và `destinationLabel(destinationType:target:) -> String`. Nó không sở hữu storage — chỉ định tuyến sang `DictionaryCache.shared.upsertEntry(key:value:type:)` (đích `globalCustom`) hoặc `TranslationManager.shared.saveCustomEntry(word:meaning:isName:bookId:)` (đích `privateBook`). Cả hai API đã tồn tại trước 1.3.244; không API nào của chúng đổi shape.
* `DictionaryEntryRow` (`struct: View`): hàng từ điển tách khỏi `DictionaryListView`, nhận `entry`, `type`, `isGlobalScope`, `contextBookId`, `onEdit`, `onDelete`, `onTransfer(DictType, DictionaryTransferTarget)`, `onMissingContext`.
* `DictionaryListView` thêm **một** thuộc tính: `var contextBookId: String? = nil` (mặc định `nil` ⇒ mọi call site cũ vẫn biên dịch). `bookId` giữ đúng nghĩa cũ (scope của danh sách); `contextBookId` chỉ là ngữ cảnh "sách nào đang mở màn Từ điển".
* `BookSearchBarView` (`struct: View`): `@Binding text`, `placeholder`, `onCommit` — trích nguyên `searchBarView` của `ShelfSearchView`, không đổi visual hay hành vi.
* `FloatingWidgetGeometry` (`enum` namespace, `import UIKit`): `clampedCenterY(_:widgetHeight:screenHeight:topMargin:bottomMargin:)`, `nearestEdge(centerX:screenWidth:)`, `restingCenterX(edge:widgetWidth:screenWidth:horizontalMargin:)`. Ba hàm thuần, không state.
* `VisibleBrowserPulseMonitor` (`@MainActor final class: ObservableObject`, singleton `.shared`): `static let pulseThreshold: TimeInterval = 10`, `@Published private(set) var isPulsing`, `func evaluate()`.
* `BrowserFloatingWidgetUIWindow: UIWindow`, `BrowserFloatingWidgetContainerViewController: UIViewController, UIGestureRecognizerDelegate` (type lồng `Layout`), `BrowserFloatingWidgetWindowManager` (`@MainActor final class: ObservableObject`, singleton) — bộ ba đối xứng với `FloatingWidgetUIWindow` / `FloatingWidgetContainerViewController` / `TTSFloatingWidgetWindowManager` của TTS widget, nhưng là **type riêng**, không kế thừa hay chia sẻ base class.
* `VisibleBrowserReopenViewModel` giữ tên và hai khoá `UserDefaults` cũ, đổi API sang mô hình UIKit: `handleDragStart()`, `handleDragEnd(finalPosition:widgetHeight:screenWidth:screenHeight:topMargin:bottomMargin:)`. `VisibleBrowserReopenButton` thu về `let tabCount: Int` — không còn cử chỉ, không còn đo kích thước.
* `VisibleBrowserTabItem` thêm `public let createdAt: Date` (mặc định `Date()` trong init) — nguồn tuổi tab duy nhất. `VisibleBrowserSettings` (`enum` namespace, chỉ `Foundation`): `openMinimizedKey`, `opensMinimized`. `VisibleBrowserTabManager` thêm `internal func prepareContainerMinimized()`.
* `EdgeDirection`, `DictType`, `DictEntry` **không đổi** — cả ba được tái dùng nguyên.

## Thành viên đổi ở đường điều hướng Reader (1.3.241)

* `ReaderViewModel`: **xoá** `stepChapter(by:source:persistProgress:)`. Không type nào khác đổi thành viên public; `requestChapter(index:paragraphIndex:source:persistProgress:forceRefresh:)` là API điều hướng duy nhất còn lại.
* `ReaderView`: `requestChapter(at:paragraphIndex:source:persistProgress:)` đổi access level `private` → `internal` để `ReaderView+Controls.swift` gọi được; thêm `scheduleDeepLandingScroll(_:)` (internal, khai trong file `+Controls`).
* `ReaderEnergyDiagnostics`: thêm `recordNavigationTap(index:source:)`, `recordSkeletonPresented(index:)`, `recordChapterPresented(index:)`; hai thuộc tính private mới (`navigationTapUptime`, `navigationTapIndex`). Không đổi kế thừa/conformance của bất kỳ type nào.
* `ScrollTarget` không đổi shape — pha hai hạ cánh chỉ dùng lại `reason: .initialRestore` vốn đã có.

## Nơi khai báo type sau phép tách (1.3.236)

* 14 type rời file gốc sang file riêng mang đúng tên nó: `TextEncodingOption`, `BookListItemStyle`, `VisibleBrowserPresentationReader`, `VisibleBrowserReopenViewModel`, `SizeReader`, `CodeEditorTextView`, `ShelfBookSearchMatcher`, `FloatingWidgetUIWindow`, `FloatingWidgetContainerViewController`, `BookTitleTranslationBackfill`, `DictionaryInvalidationScope`, `VisibleWebViewController`, `VisibleBrowserTabItem`, `TabbedVisibleBrowserViewController`.
* Không type nào đổi tên, đổi kế thừa, đổi conformance hay đổi thành viên. Hai type đổi access level do rời phạm vi file: `SizeReader` (`private struct` → internal), `BookTitleTranslationBackfill` (`private actor` → `internal actor`).
* Type lồng bên trong vẫn đi cùng type cha: `Layout` theo `FloatingWidgetContainerViewController`, `Snapshot` theo `VisibleBrowserPresentationReader`, `Coordinator` theo `HighlightingCodeEditor`.
* Protocol không bị luật `MULTI_PRIMARY_TYPES` tính, nên `BookDisplayable` vẫn ở `BookListItemView.swift`.

## Type bị xoá khi dọn code chết (1.3.235)

* Xoá hẳn: `TTSHighlightCalculator`, `TTSParagraphSplitter`, `TTSVoiceResolver`, `ReaderViewModelObserver`, `ReaderParagraphBuilder`, `UnavailablePiperEngine` (struct fallback không bao giờ được khởi tạo), `SearchBar` (trong `BookDictionaryView.swift`), `CacheSummary` (`ModelStore`), `ModelsResponse` (`NghiTTSClient`), `GlobalToastModifier`.
* Xoá hai `typealias` tương thích ngược không còn tham chiếu: `SearchNovelResult = ExtensionItemResult` và `TTSProcessedChapter = ProcessedChapterDTO`. Tên chính thức duy nhất nay là `ExtensionItemResult` và `ProcessedChapterDTO`.
* `ReaderParagraphBuildResult` vẫn tồn tại (production dùng) và nay là primary type duy nhất của file cùng tên.
* Không có protocol nào mất requirement: đã kiểm tra toàn bộ thân `protocol` trong `Sources/` không khai bất kỳ symbol nào bị xoá.

## ExtensionType namespace (1.3.226)

* `public enum ExtensionType` là namespace không có case, cung cấp bốn `public static let String`: `novel`, `chineseNovel`, `comic`, và `tts`.
* `Extension.type`, `ExtensionItem.type` và `UpsertExtensionCommand.type` tiếp tục là `String`; namespace chỉ chuẩn hóa vocabulary, không đóng tập type hợp lệ và không yêu cầu migration.

## Local import and chapter-search type changes (1.3.224)

* `ParserChapter` and `ParsedBook` conform to `Sendable`, allowing immutable parsed TXT data to cross into detached metadata/translation work.
* `ChapterStoreProtocol.searchChapters(bookId:query:)` removes the presentation-derived `searchTrans` argument; implementations now expose one two-column search contract.
* `BookTransactionCoordinator.insertChapterDTO` accepts optional `titleTrans` (default `nil`) so the dormant SwiftData TOC-write path preserves the same imported metadata as ChapterStore.

## Sơ Đồ Kiểu Dữ Liệu & Thực Thể (Type Graph v4.1/v5.0)

Các kiểu dữ liệu chính và mối quan hệ sau refactor:
1. **Command DTOs & Transaction Errors**:
   - `AddBookToShelfCommand`, `UpsertExtensionCommand`, `ExtensionConfigCommand`, `UpdateExtensionFolderCommand` (Immutable value structs); `ExtensionType` (namespace hằng số String).
   - `BookTransactionError`, `ExtensionTransactionError`, `TOCRuleImportError`, `BackgroundPagingError` (Error enums).
2. **Domain Transaction Coordinators**:
   - `BookTransactionCoordinator` (`@MainActor` singleton): Nhận `AddBookToShelfCommand`, `updateBookMetadata`, `setOnShelf`, `setCurrentChapterIndex`, `insertChapterDTO`, `updateChapterTitleTranslations`.
   - `ExtensionTransactionCoordinator` (`@MainActor` singleton): Nhận `UpsertExtensionCommand`, `ExtensionConfigCommand`, `UpdateExtensionFolderCommand`, `touchRepositoryLastUpdated`.
3. **Reader & Extension Components**:
   - `ReaderScrollCoordinator`: Điều khiển cuộn cho `ReaderView`.
   - `ReaderSelectionCoordinator`: **Tên gọi là misnomer lịch sử** — không điều khiển selection/menu chọn. Thực tế chỉ có `getHanViet(for:)` (tra Hán-Việt một từ) và `formatMeaning(_:style:)` (format hoa/thường nghĩa tra được).
   - `ReaderProgressScheduler`: Lập lịch lưu tiến độ đọc định kỳ cho `ReaderViewModel`.
   - `RepositoryFilterPolicy`: Lọc và sắp xếp danh sách tiện ích trong `RepositoryManagerView`.
   - `BookDetailLoader`: Tải chi tiết và danh sách chương online cho `BookDetailView`.
   - `ExtensionExecutionSnapshot`: Thread-safe copy dữ liệu tiện ích phục vụ thực thi JS cách ly.
4. **Presentation Event Stream Types**:
   - `TTSPresentationEvent`, `DownloadPresentationEvent` (Value enums).
   - `TTSPresentationEventCenter`, `DownloadPresentationEventCenter` (`AsyncStream` publishers).
<!-- GENERATED END -->
