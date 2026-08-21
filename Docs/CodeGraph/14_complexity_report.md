---
generated_by: Antigravity
generator_version: 1.0
generated_at: 2026-08-21T10:30:00+07:00
git_commit: UNKNOWN
source_files: 218
document_version: 3
---

# Báo cáo Độ phức tạp & Đồ thị TODO (Complexity & TODO Report)

Tài liệu này cung cấp báo cáo chi tiết về độ phức tạp mã nguồn của dự án FreeBook và liệt kê toàn bộ các ghi chú đang dang dở (TODO / FIXME / HACK / WARNING).

## Ghi chú thủ công (Human Notes)
*Đây là khu vực con người tự viết ghi chú, AI không được phép ghi đè.*

<!-- GENERATED START -->
## Incremental complexity update (1.3.14)

* Reader paragraph creation and translated-selection mapping moved out of `ReaderView`/`ReaderViewModel` into two focused, unit-testable helpers.
* The previous duplicated paragraph split/max-line logic and inline sentence/token selection heuristic were removed from `ReaderView`.

## Đánh giá mức độ tin cậy (Confidence Level)

*   **Mức độ tin cậy**: **High**
*   **Lý do**: Được tính toán tự động bằng cách phân tích tĩnh cấu trúc mã nguồn thực tế và đếm các từ khóa rẽ nhánh rập khuôn trong 218 file Swift.

---

## 1. Báo cáo Độ phức tạp Mã nguồn (Complexity Report)

### 1.1. Top 10 File lớn nhất theo số dòng code (Largest Files)
| Hạng | Tên File | Đường dẫn | Số dòng |
| :--- | :--- | :--- | :--- |
| 1 | `TTSManager.swift` | [Services/TTS/TTSManager.swift](../../Sources/Services/TTS/TTSManager.swift) | 4097 |
| 2 | `ReaderView.swift` | [Views/Reader/ReaderView.swift](../../Sources/Views/Reader/ReaderView.swift) | 2223 |
| 3 | `JSExecutor.swift` | [Services/Extensions/Engine/JSExecutor.swift](../../Sources/Services/Extensions/Engine/JSExecutor.swift) | 1514 |
| 4 | `BookDetailView.swift` | [Views/BookDetail/BookDetailView.swift](../../Sources/Views/BookDetail/BookDetailView.swift) | 1213 |
| 5 | `TextPreprocessor.swift` | [Services/TTS/Preprocessing/TextPreprocessor.swift](../../Sources/Services/TTS/Preprocessing/TextPreprocessor.swift) | 1121 |
| 6 | `ShelfView.swift` | [Views/Shelf/ShelfMain/ShelfView.swift](../../Sources/Views/Shelf/ShelfMain/ShelfView.swift) | 1076 |
| 7 | `ExtensionManager.swift` | [Services/Extensions/Manager/ExtensionManager.swift](../../Sources/Services/Extensions/Manager/ExtensionManager.swift) | 1066 |
| 8 | `TranslateUtils.swift` | [Services/Translation/Utils/TranslateUtils.swift](../../Sources/Services/Translation/Utils/TranslateUtils.swift) | 1046 |
| 9 | `ChapterStoreDatabase.swift` | [Services/ChapterText/ChapterStore/ChapterStoreDatabase.swift](../../Sources/Services/ChapterText/ChapterStore/ChapterStoreDatabase.swift) | 955 |
| 10 | `DiscoveryView.swift` | [Views/Discovery/DiscoveryView.swift](../../Sources/Views/Discovery/DiscoveryView.swift) | 919 |

### 1.2. Top 10 File có độ phức tạp rẽ nhánh lớn nhất (Cyclomatic Complexity ước lượng)
*Công thức ước lượng: Base (1) + số lượng các từ khóa rẽ nhánh (`if`, `guard`, `for`, `while`, `switch`, `case`, `&&`, `||`, `catch`).*

| Hạng | Tên File | Đường dẫn | Độ phức tạp (CC) |
| :--- | :--- | :--- | :--- |
| 1 | `TTSManager.swift` | [Services/TTS/TTSManager.swift](../../Sources/Services/TTS/TTSManager.swift) | 666 |
| 2 | `ReaderView.swift` | [Views/Reader/ReaderView.swift](../../Sources/Views/Reader/ReaderView.swift) | 320 |
| 3 | `JSExecutor.swift` | [Services/Extensions/Engine/JSExecutor.swift](../../Sources/Services/Extensions/Engine/JSExecutor.swift) | 265 |
| 4 | `TextPreprocessor.swift` | [Services/TTS/Preprocessing/TextPreprocessor.swift](../../Sources/Services/TTS/Preprocessing/TextPreprocessor.swift) | 150 |
| 5 | `ExtensionManager.swift` | [Services/Extensions/Manager/ExtensionManager.swift](../../Sources/Services/Extensions/Manager/ExtensionManager.swift) | 133 |
| 6 | `ReaderViewModel.swift` | [Views/Reader/ReaderViewModel.swift](../../Sources/Views/Reader/ReaderViewModel.swift) | 129 |
| 7 | `TranslateUtils.swift` | [Services/Translation/Utils/TranslateUtils.swift](../../Sources/Services/Translation/Utils/TranslateUtils.swift) | 124 |
| 8 | `ChapterPersistenceStore.swift` | [Services/ChapterText/ChapterPersistenceStore.swift](../../Sources/Services/ChapterText/ChapterPersistenceStore.swift) | 111 |
| 9 | `TranslationManager.swift` | [Services/Translation/Manager/TranslationManager.swift](../../Sources/Services/Translation/Manager/TranslationManager.swift) | 107 |
| 10 | `ChapterStoreDatabase.swift` | [Services/ChapterText/ChapterStore/ChapterStoreDatabase.swift](../../Sources/Services/ChapterText/ChapterStore/ChapterStoreDatabase.swift) | 105 |

### 1.3. Top 10 File có độ lồng khối `{ }` sâu nhất (Max Brace Nesting Depth)
*Đo lường mức lồng nhau tối đa của khối `{ ... }` (đếm số dấu `{` mở lồng nhau chưa đóng tại điểm sâu nhất). Đây là **độ sâu**, không phải tổng số khối; giá trị thực tế của repo hiện nằm trong khoảng 10–18.*

| Hạng | Tên File | Đường dẫn | Độ sâu lồng nhau tối đa |
| :--- | :--- | :--- | :--- |
| 1 | `SearchView.swift` | [Views/Search/SearchView.swift](../../Sources/Views/Search/SearchView.swift) | 18 |
| 2 | `DiscoveryView.swift` | [Views/Discovery/DiscoveryView.swift](../../Sources/Views/Discovery/DiscoveryView.swift) | 13 |
| 3 | `ExtensionScriptEditorView.swift` | [Views/Extensions/Editor/ExtensionScriptEditorView.swift](../../Sources/Views/Extensions/Editor/ExtensionScriptEditorView.swift) | 12 |
| 4 | `ExtensionConfigView.swift` | [Views/Extensions/Config/ExtensionConfigView.swift](../../Sources/Views/Extensions/Config/ExtensionConfigView.swift) | 12 |
| 5 | `TTSDictionaryEditView.swift` | [Views/Settings/TTS/TTSDictionaryEditView.swift](../../Sources/Views/Settings/TTS/TTSDictionaryEditView.swift) | 11 |
| 6 | `BookDetailView.swift` | [Views/BookDetail/BookDetailView.swift](../../Sources/Views/BookDetail/BookDetailView.swift) | 11 |
| 7 | `BookDetailTOCView.swift` | [Views/BookDetail/BookDetailTOCView.swift](../../Sources/Views/BookDetail/BookDetailTOCView.swift) | 11 |
| 8 | `TXTImportConfirmationSheet.swift` | [Views/Shelf/ShelfMain/TXTImportConfirmationSheet.swift](../../Sources/Views/Shelf/ShelfMain/TXTImportConfirmationSheet.swift) | 10 |
| 9 | `ShelfSearchView.swift` | [Views/Shelf/ShelfMain/ShelfSearchView.swift](../../Sources/Views/Shelf/ShelfMain/ShelfSearchView.swift) | 10 |
| 10 | `ReaderChapterListView.swift` | [Views/Reader/ReaderChapterListView.swift](../../Sources/Views/Reader/ReaderChapterListView.swift) | 10 |

---

## 2. Danh sách TODO / FIXME / HACK / WARNING (TODO Graph)

*Tổng số ghi chú phát hiện được: 0*

> [!NOTE]
> Không tìm thấy bất kỳ comment chứa từ khóa `TODO`, `FIXME`, `HACK`, hay `WARNING` nào trong mã nguồn dự án FreeBook.

#### Reader/TTS unified pipeline (2026-07)

- `ChapterTextNormalizer` is the single source for LF newlines, trimmed non-empty lines, **sparse paragraph IDs (`ChapterTextLine.id` is the raw line index and counts blank lines, so IDs are not array offsets and must be looked up by `id`, never used as an array index)**, and UTF-16 ranges. Because those ranges are computed before blank lines are dropped, `ChapterTextLine.utf16Range` must not be used to slice `NormalizedChapterText.content`. `ChapterContentRepository` produces one normalized `ChapterDocument` for both Reader and TTS.
- Reader uses `ReaderLoadState` with bootstrap retry/clamping, typed failures, generation checks, cache-first rendering, and a short opacity crossfade only for newly fetched content. `ReaderRoute.chapterIndex` preserves the selected TOC index through navigation.
- `TTSParagraphBuilder` chunks normalized lines without renumbering parent paragraph IDs; replacement output is checked before synthesis. TTS asynchronous work is guarded by session identity and TTS owns progress while playing.
- `ReadingProgressStore` coalesces RAM snapshots in an actor and flushes from background contexts on checkpoints, dismissal, and app backgrounding. Legacy window/tab Reader, duplicate progress repository, and `TTSSession` mirror are removed.

- `RemoteTTSSynthesisCoordinator.swift` and `ExtTTSRuntime.swift` add bounded actors that extract queue/runtime state from the already-large `TTSManager.swift` and `ExtensionManager.swift`; neither new file enters the existing top-complexity set.

<!-- GENERATED END -->
