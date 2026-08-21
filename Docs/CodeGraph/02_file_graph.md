---
generated_by: Antigravity
generator_version: 1.0
generated_at: 2026-08-21T10:30:00+07:00
git_commit: UNKNOWN
source_files: 230
document_version: 4
---

# Đồ thị File & Quan hệ Import (File & Import Graph)

Tài liệu này chi tiết hóa toàn bộ các mối quan hệ phụ thuộc giữa 218 file mã nguồn Swift trong dự án FreeBook, tách biệt rõ ràng giữa Import Graph và Dependency Graph cho từng tệp.

## Ghi chú thủ công (Human Notes)
*Đây là khu vực con người tự viết ghi chú, AI không được phép ghi đè.*

<!-- GENERATED START -->
## 14 file mới sinh ra từ phép tách một-primary-type (1.3.236)

| File mới | Tách khỏi | Dòng |
|---|---|---|
| `Common/Utils/TextEncodingOption.swift` | `TextEncodingDecoder.swift` | 102 |
| `Common/BookListItemStyle.swift` (Views) | `BookListItemView.swift` | 10 |
| `Views/Common/VisibleBrowserPresentationReader.swift` | `VisibleBrowserReopenView.swift` | 39 |
| `Views/Common/VisibleBrowserReopenViewModel.swift` | `VisibleBrowserReopenView.swift` | 48 |
| `Views/Common/SizeReader.swift` | `VisibleBrowserReopenView.swift` | 17 |
| `Views/Extensions/Editor/CodeEditorTextView.swift` | `HighlightingCodeEditor.swift` | 111 |
| `Views/Shelf/ShelfMain/ShelfBookSearchMatcher.swift` | `ShelfSearchView.swift` | 22 |
| `Views/TTSWidget/FloatingWidgetUIWindow.swift` | `TTSFloatingWidgetWindowManager.swift` | 29 |
| `Views/TTSWidget/FloatingWidgetContainerViewController.swift` | `TTSFloatingWidgetWindowManager.swift` | 240 |
| `Services/Translation/BookTitleTranslationBackfill.swift` | `BookTitleTranslationMigrator.swift` | 40 |
| `Services/Translation/Manager/DictionaryInvalidationScope.swift` | `TranslationManager.swift` | 7 |
| `Services/Extensions/Engine/VisibleWebViewController.swift` | `VisibleWebViewLoader.swift` | 122 |
| `Services/Extensions/Engine/VisibleBrowserTabItem.swift` | `VisibleBrowserTabManager.swift` | 18 |
| `Services/Extensions/Engine/TabbedVisibleBrowserViewController.swift` | `VisibleBrowserTabManager.swift` | 201 |

* Quan hệ *uses/used by* không đổi: mọi tham chiếu vẫn nằm trong cùng module nên chỉ là dịch chuyển khai báo. Hai type đổi access level (`SizeReader`, `BookTitleTranslationBackfill`) vì `private` ở file cũ là phạm vi file.
* Không file nào trong `Sources/Services/**` mới thêm `import SwiftUI`: `VisibleWebViewController.swift` và `TabbedVisibleBrowserViewController.swift` chỉ dùng `Foundation`/`UIKit`/`WebKit`, nên miễn trừ `SERVICE_SWIFTUI_IMPORT` cho `*WebViewLoader.swift` vẫn không bị nới rộng.
* File gốc sau khi tách: `TextEncodingDecoder.swift` 145 → 43, `BookListItemView.swift` 182 → 171, `VisibleBrowserReopenView.swift` 234 → 128, `HighlightingCodeEditor.swift` 278 → 166, `ShelfSearchView.swift` 263 → 240, `TTSFloatingWidgetWindowManager.swift` 375 → 112, `BookTitleTranslationMigrator.swift` 79 → 38, `TranslationManager.swift` 601 → 593, `VisibleBrowserTabManager.swift` 448 → 234, `VisibleWebViewLoader.swift` 404 → 285.

## File bị xoá/đổi tên khi dọn code chết (1.3.235)

* **Xoá**: `Sources/Services/TTS/Helpers/TTSHighlightCalculator.swift`, `Sources/Services/TTS/Helpers/TTSParagraphSplitter.swift`, `Sources/Services/TTS/Helpers/TTSVoiceResolver.swift` (cả ba đều 0 *used by*; thư mục `Helpers/` không còn tồn tại), `Sources/Views/Reader/ReaderViewModelObserver.swift` (0 *used by*).
* **Đổi tên**: `Sources/Views/Reader/ReaderParagraphBuilder.swift` → `Sources/Views/Reader/ReaderParagraphBuildResult.swift` (7 dòng). *Used by*: `Views/Reader/Extensions/ReaderViewModel+Translation.swift`. Enum `ReaderParagraphBuilder` bị xoá; đường dựng `[ParagraphItem]` của production nay là **một bản duy nhất** trong `ReaderViewModel+Translation.swift`.
* **Xoá `Tests/` (20 file) và target `FreeBookTests` trong `project.yml`** — không còn file nào ngoài `Sources/` được biên dịch, nên đồ thị import/dependency chỉ còn một target.
* Các file mất bớt thành viên nhưng giữ nguyên quan hệ *uses/used by*: `TTSManager.swift`, `TTSChapterPrefetcher.swift`, `TTSChapterTextWorker.swift`, `TTSNowPlayingController.swift`, `TTSParagraphBuilder.swift`, `ModelStore.swift`, `NghiTTSClient.swift`, `PiperTTSService.swift`, `ExtensionManager.swift`, `TranslationManager.swift`, `TranslateUtils.swift`, `BookTransactionCoordinator.swift`, `ExtensionTransactionCoordinator.swift`, `JunkFilterManager.swift`, `ReaderChapterListStore.swift`, `ImageCacheManager.swift`, `DisplayTextFormatter.swift`, `DoubleArrayTrie.swift`, `ToastManager.swift`, `BookDictionaryView.swift`.

## Next-chapter prefix audio files (1.3.234)

* `Sources/Services/TTS/TTSNextChapterPrefixCache.swift` (380 dòng, 1 primary type `TTSNextChapterPrefixCache`)
  - *Uses*: `TTSPreparedNextChapterKey`, `TTSParagraph`, `TTSBoundaryKind`, `TTSReplacementManager`, `TTSSynthesisIdentity`, `TTSAudioSynthesisWorker`, `RemoteTTSSynthesisCoordinator.Priority`, `PiperTTSService`, `SynthesisPriority`, `GoogleTTSService`, `ExtTTSService`, `WAVEncoder`, `AppLogger`, `TTSManager.RefillFailureState` + `TTSManager.evaluateRefillError` (tái sử dụng phân loại lỗi).
  - *Used by*: `TTSManager+NextChapterPrefix.swift` (chỉ một consumer duy nhất).
* `Sources/Services/TTS/Extensions/TTSManager+NextChapterPrefix.swift` (130 dòng, extension — không khai primary type)
  - *Uses*: `TTSManager` (nội bộ: `nextChapterPrefetcher`, `preloadedData`, `preloadedDurations`, `paragraphs`, `nghiTTSService`, `googleService`, `extService`, `audioSynthesisWorker`, `makeNextChapterKey`, `selectNghiOptionalRefillCandidate`), `TTSNextChapterPrefixCache`, `NghiUtteranceSegmenter`, `NghiSynthesisPolicy`, `ProcessedChapterDTO`, `WAVEncoder`, `AppLogger`.
  - *Used by*: `TTSManager.swift` (4 call site: `pause`, `applyNextChapter`, `updatePrefetchWindow`, `updateNghiPrefetchWindow`), `TTSManager+PrefetchCache.swift` (`clearAllTTSCaches`).
* `TTSManager.swift` mở rộng khả năng truy cập cho hai thành viên đã có (`nghiTTSService`, `makeNextChapterKey`) từ `private` sang `internal` để extension ở file khác dùng được; không thêm type mới. `NghiSynthesisPolicy.swift` thêm hằng `maxTotalAudioPayloads` (vẫn là single source cho mọi hằng số năng lượng của Nghi).

## Extension type constants (1.3.226)

* File mới `Sources/Models/Extensions/ExtensionType.swift` khai báo namespace public dùng chung cho các giá trị type chuẩn mà không thay `Extension.type: String` thành enum.
* `UpsertExtensionCommand` và `ExtensionManager` phụ thuộc `ExtensionType.novel` cho default/fallback; `RepositoryFilterPolicy`, `SearchView`, `DiscoveryView`, `TTSSettingsView`, `RepositoryManagerView`, `FilterSheet` và `RepositoryManagerView+Actions` phụ thuộc cùng namespace cho policy và presentation.

## Cấu Trúc Sơ Đồ File Hợp Nhất (Refactor v4.1/v5.0)

Sơ đồ liên kết file của toàn bộ dự án FreeBook sau refactor:
- **App**: `FreeBookApp.swift` -> Đăng ký `TTSPresentationEventCenter`, `DownloadPresentationEventCenter`.
- **Models**:
  - `Models/Books/`: `AddBookToShelfCommand.swift`, `BookTransactionError.swift`.
  - `Models/Extensions/`: `ExtensionConfigCommand.swift`, `ExtensionExecutionSnapshot.swift`, `ExtensionTransactionError.swift`, `ExtensionType.swift`, `UpdateExtensionFolderCommand.swift`, `UpsertExtensionCommand.swift`.
  - `Models/Reader/`: `ChapterRowItem.swift`, `ParagraphFrame.swift`, `ReaderChapterRowState.swift`, `ReaderScrollReason.swift`, `ReaderScrollTarget.swift`, `SearchChapterDTO.swift`.
  - `Models/Translation/`: `SentenceRange.swift`, `TOCImportPreview.swift`, `TOCRule.swift`, `TOCRuleImportError.swift`, `TranslatedTextResult.swift`, `TranslationSpan.swift`, `TranslationWordToken.swift`.
- **Services**:
  - `Services/Books/`: `BookTransactionCoordinator.swift`.
  - `Services/Extensions/`: `ExtensionTransactionCoordinator.swift`, `Policies/RepositoryFilterPolicy.swift`, `Workers/BookDetailLoader.swift`, `Engine/JSExecutor.swift`, `Engine/JSExecutor+Async.swift`.
  - `Services/ChapterText/`: `PrefetchManager.swift`, `ReaderChapterListStore.swift`, `Coordinators/ChapterListSearchCoordinator.swift`, `Workers/BackgroundPagingWorker.swift`, `BackgroundSearchWorker.swift`, `ReaderChapterListPageFetcher.swift`.
  - `Services/ReadingProgress/`: `ReaderProgressScheduler.swift`.
  - `Services/TTS/`: `TTSManager.swift`, `TTSAudioEngineController.swift`, `TTSAudioSessionController.swift`, `Events/TTSPresentationEventCenter.swift`, `Events/TTSPresentationEvent.swift`, `Extensions/TTSManager+*.swift`. `DisplayTextFormatter.swift` nằm ở `Common/Extensions/DisplayTextFormatter.swift`, không phải trong `Services/TTS/`.
  - `Services/Download/`: `DownloadManager.swift`, `Events/DownloadPresentationEventCenter.swift`, `Events/DownloadPresentationEvent.swift`.
  - `Services/Translation/`: `Utils/TranslateUtils.swift`, `Extensions/TranslateUtils+Tokenization.swift`, `Engine/VietPhraseTokenizer.swift`, `Utils/TOCRuleSaveCoordinator.swift`.
- **Views**:
  - `Views/BookDetail/`: `BookDetailView.swift`, `Extensions/BookDetailView+Extensions.swift`, `BookDetailView+TOCPreparation.swift`.
  - `Views/Reader/`: `ReaderView.swift`, `ReaderViewModel.swift`, `ReaderChapterListView.swift`, `Coordinators/ReaderScrollCoordinator.swift`, `ReaderSelectionCoordinator.swift`, `Extensions/ReaderView+Controls.swift`, `ReaderView+LoadingView.swift`, `ReaderViewModel+Translation.swift`.
  - `Views/Extensions/`: `Manager/RepositoryManagerView.swift`, `Extensions/RepositoryManagerView+Actions.swift`, `RepositoryManagerView+RepoOps.swift`.
  - `Views/Shelf/`: `ShelfMain/ShelfView.swift`.
  - `Views/Search/`: `SearchView.swift`.
  - `Views/Discovery/`: `DiscoveryView.swift`.
  - `Views/Common/`: `VisibleBrowserReopenView.swift`.
<!-- GENERATED END -->
