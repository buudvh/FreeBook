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
