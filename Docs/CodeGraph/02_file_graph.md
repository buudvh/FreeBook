---
generated_by: Antigravity
generator_version: 1.0
generated_at: 2026-07-17T23:26:29+07:00
git_commit: UNKNOWN
source_files: 93
document_version: 3
---

# Đồ thị File & Quan hệ Import (File & Import Graph)

Tài liệu này chi tiết hóa toàn bộ các mối quan hệ phụ thuộc giữa 87 file mã nguồn Swift trong dự án FreeBook, tách biệt rõ ràng giữa Import Graph và Dependency Graph cho từng tệp.

## Ghi chú thủ công (Human Notes)
*Đây là khu vực con người tự viết ghi chú, AI không được phép ghi đè.*

<!-- GENERATED START -->
## Cấu Trúc Sơ Đồ File Hợp Nhất (Refactor v4.1/v5.0)

Sơ đồ liên kết file của toàn bộ dự án FreeBook sau refactor:
- **App**: `FreeBookApp.swift` -> Đăng ký `TTSPresentationEventCenter`, `DownloadPresentationEventCenter`.
- **Models**:
  - `Models/Books/`: `AddBookToShelfCommand.swift`, `BookTransactionError.swift`.
  - `Models/Extensions/`: `ExtensionConfigCommand.swift`, `ExtensionExecutionSnapshot.swift`, `ExtensionTransactionError.swift`, `UpdateExtensionFolderCommand.swift`, `UpsertExtensionCommand.swift`.
  - `Models/Reader/`: `ChapterRowItem.swift`, `ParagraphFrame.swift`, `ReaderChapterRowState.swift`, `ReaderScrollReason.swift`, `ReaderScrollTarget.swift`, `SearchChapterDTO.swift`.
  - `Models/Translation/`: `SentenceRange.swift`, `TOCImportPreview.swift`, `TOCRule.swift`, `TOCRuleImportError.swift`, `TranslatedTextResult.swift`, `TranslationSpan.swift`, `TranslationWordToken.swift`.
- **Services**:
  - `Services/Books/`: `BookTransactionCoordinator.swift`.
  - `Services/Extensions/`: `ExtensionTransactionCoordinator.swift`, `Policies/RepositoryFilterPolicy.swift`, `Workers/BookDetailLoader.swift`, `Engine/JSExecutor.swift`, `Engine/JSExecutor+Async.swift`.
  - `Services/ChapterText/`: `PrefetchManager.swift`, `ReaderChapterListStore.swift`, `Coordinators/ChapterListSearchCoordinator.swift`, `Workers/BackgroundPagingWorker.swift`, `BackgroundSearchWorker.swift`, `ReaderChapterListPageFetcher.swift`.
  - `Services/ReadingProgress/`: `ReaderProgressScheduler.swift`.
  - `Services/TTS/`: `TTSManager.swift`, `TTSAudioEngineController.swift`, `Events/TTSPresentationEventCenter.swift`, `Events/TTSPresentationEvent.swift`, `Extensions/TTSManager+*.swift`, `Helpers/DisplayTextFormatter.swift`.
  - `Services/Download/`: `DownloadManager.swift`, `Events/DownloadPresentationEventCenter.swift`, `Events/DownloadPresentationEvent.swift`.
  - `Services/Translation/`: `Utils/TranslateUtils.swift`, `Extensions/TranslateUtils+Tokenization.swift`, `Engine/VietPhraseTokenizer.swift`, `Utils/TOCRuleSaveCoordinator.swift`.
- **Views**:
  - `Views/BookDetail/`: `BookDetailView.swift`, `Extensions/BookDetailView+Extensions.swift`, `BookDetailView+TOCPreparation.swift`.
  - `Views/Reader/`: `ReaderView.swift`, `ReaderViewModel.swift`, `ReaderChapterListView.swift`, `Coordinators/ReaderScrollCoordinator.swift`, `ReaderSelectionCoordinator.swift`, `Extensions/ReaderView+Controls.swift`, `ReaderView+LoadingView.swift`, `ReaderViewModel+Translation.swift`.
  - `Views/Extensions/`: `Manager/RepositoryManagerView.swift`, `Extensions/RepositoryManagerView+Actions.swift`, `RepositoryManagerView+RepoOps.swift`.
  - `Views/Shelf/`: `ShelfMain/ShelfView.swift`.
  - `Views/Search/`: `SearchView.swift`.
  - `Views/Discovery/`: `DiscoveryView.swift`.
<!-- GENERATED END -->
