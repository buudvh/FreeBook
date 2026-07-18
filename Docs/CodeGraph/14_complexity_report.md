---
generated_by: Antigravity
generator_version: 1.0
generated_at: 2026-07-17T23:26:29+07:00
git_commit: UNKNOWN
source_files: 93
document_version: 2
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
*   **Lý do**: Được tính toán tự động bằng cách phân tích tĩnh cấu trúc mã nguồn thực tế và đếm các từ khóa rẽ nhánh rập khuôn trong 87 file Swift.

---

## 1. Báo cáo Độ phức tạp Mã nguồn (Complexity Report)

### 1.1. Top 10 File lớn nhất theo số dòng code (Largest Files)
| Hạng | Tên File | Đường dẫn | Số dòng |
| :--- | :--- | :--- | :--- |
| 1 | `ReaderView.swift` | [Views/Reader/ReaderView.swift](../../Sources/Views/Reader/ReaderView.swift) | 2782 |
| 2 | `TTSManager.swift` | [Services/TTS/TTSManager.swift](../../Sources/Services/TTS/TTSManager.swift) | 1576 |
| 3 | `BookDetailView.swift` | [Views/BookDetail/BookDetailView.swift](../../Sources/Views/BookDetail/BookDetailView.swift) | 1379 |
| 4 | `TextPreprocessor.swift` | [Services/TTS/Preprocessing/TextPreprocessor.swift](../../Sources/Services/TTS/Preprocessing/TextPreprocessor.swift) | 1119 |
| 5 | `JSExecutor.swift` | [Services/Extensions/Engine/JSExecutor.swift](../../Sources/Services/Extensions/Engine/JSExecutor.swift) | 885 |
| 6 | `TranslateUtils.swift` | [Services/Translation/Utils/TranslateUtils.swift](../../Sources/Services/Translation/Utils/TranslateUtils.swift) | 830 |
| 7 | `ExtensionManager.swift` | [Services/Extensions/Manager/ExtensionManager.swift](../../Sources/Services/Extensions/Manager/ExtensionManager.swift) | 826 |
| 8 | `DiscoveryView.swift` | [Views/Discovery/DiscoveryView.swift](../../Sources/Views/Discovery/DiscoveryView.swift) | 788 |
| 9 | `SearchView.swift` | [Views/Search/SearchView.swift](../../Sources/Views/Search/SearchView.swift) | 777 |
| 10 | `ShelfView.swift` | [Views/Shelf/ShelfMain/ShelfView.swift](../../Sources/Views/Shelf/ShelfMain/ShelfView.swift) | 691 |

### 1.2. Top 10 File có độ phức tạp rẽ nhánh lớn nhất (Cyclomatic Complexity ước lượng)
*Công thức ước lượng: Base (1) + số lượng các từ khóa rẽ nhánh (`if`, `guard`, `for`, `while`, `switch`, `case`, `&&`, `||`, `catch`).*

| Hạng | Tên File | Đường dẫn | Độ phức tạp (CC) |
| :--- | :--- | :--- | :--- |
| 1 | `ReaderView.swift` | [Views/Reader/ReaderView.swift](../../Sources/Views/Reader/ReaderView.swift) | 300 |
| 2 | `TTSManager.swift` | [Services/TTS/TTSManager.swift](../../Sources/Services/TTS/TTSManager.swift) | 204 |
| 3 | `TextPreprocessor.swift` | [Services/TTS/Preprocessing/TextPreprocessor.swift](../../Sources/Services/TTS/Preprocessing/TextPreprocessor.swift) | 141 |
| 4 | `JSExecutor.swift` | [Services/Extensions/Engine/JSExecutor.swift](../../Sources/Services/Extensions/Engine/JSExecutor.swift) | 137 |
| 5 | `TranslationManager.swift` | [Services/Translation/Manager/TranslationManager.swift](../../Sources/Services/Translation/Manager/TranslationManager.swift) | 124 |
| 6 | `TranslateUtils.swift` | [Services/Translation/Utils/TranslateUtils.swift](../../Sources/Services/Translation/Utils/TranslateUtils.swift) | 118 |
| 7 | `ExtensionManager.swift` | [Services/Extensions/Manager/ExtensionManager.swift](../../Sources/Services/Extensions/Manager/ExtensionManager.swift) | 108 |
| 8 | `BookDetailView.swift` | [Views/BookDetail/BookDetailView.swift](../../Sources/Views/BookDetail/BookDetailView.swift) | 106 |
| 9 | `JSDom.swift` | [Services/Extensions/Engine/JSDom.swift](../../Sources/Services/Extensions/Engine/JSDom.swift) | 74 |
| 10 | `TTSDictionaryEditView.swift` | [Views/Settings/TTS/TTSDictionaryEditView.swift](../../Sources/Views/Settings/TTS/TTSDictionaryEditView.swift) | 69 |

### 1.3. Top 10 File có độ lồng ngoặc nhọn sâu nhất (Nested Brackets Depth)
*Đo lường mức độ lồng nhau sâu nhất của cấu trúc code `{ ... }` (Nested Closure/Scope).*

| Hạng | Tên File | Đường dẫn | Độ sâu lồng nhau tối đa |
| :--- | :--- | :--- | :--- |
| 1 | `ReaderView.swift` | [Views/Reader/ReaderView.swift](../../Sources/Views/Reader/ReaderView.swift) | 288 |
| 2 | `BookDetailView.swift` | [Views/BookDetail/BookDetailView.swift](../../Sources/Views/BookDetail/BookDetailView.swift) | 168 |
| 3 | `TTSManager.swift` | [Services/TTS/TTSManager.swift](../../Sources/Services/TTS/TTSManager.swift) | 127 |
| 4 | `JSExecutor.swift` | [Services/Extensions/Engine/JSExecutor.swift](../../Sources/Services/Extensions/Engine/JSExecutor.swift) | 98 |
| 5 | `DiscoveryView.swift` | [Views/Discovery/DiscoveryView.swift](../../Sources/Views/Discovery/DiscoveryView.swift) | 94 |
| 6 | `SearchView.swift` | [Views/Search/SearchView.swift](../../Sources/Views/Search/SearchView.swift) | 94 |
| 7 | `TextPreprocessor.swift` | [Services/TTS/Preprocessing/TextPreprocessor.swift](../../Sources/Services/TTS/Preprocessing/TextPreprocessor.swift) | 84 |
| 8 | `DictionaryListView.swift` | [Views/Dictionary/DictionaryListView.swift](../../Sources/Views/Dictionary/DictionaryListView.swift) | 82 |
| 9 | `TTSDictionaryEditView.swift` | [Views/Settings/TTS/TTSDictionaryEditView.swift](../../Sources/Views/Settings/TTS/TTSDictionaryEditView.swift) | 77 |
| 10 | `RepositoryManagerView.swift` | [Views/Extensions/Manager/RepositoryManagerView.swift](../../Sources/Views/Extensions/Manager/RepositoryManagerView.swift) | 75 |

---

## 2. Danh sách TODO / FIXME / HACK / WARNING (TODO Graph)

*Tổng số ghi chú phát hiện được: 0*

> [!NOTE]
> Không tìm thấy bất kỳ comment chứa từ khóa `TODO`, `FIXME`, `HACK`, hay `WARNING` nào trong mã nguồn dự án FreeBook.

#### Reader/TTS unified pipeline (2026-07)

- `ChapterTextNormalizer` is the single source for LF newlines, trimmed non-empty lines, compact paragraph IDs, and UTF-16 ranges. `ChapterContentRepository` produces one normalized `ChapterDocument` for both Reader and TTS.
- Reader uses `ReaderLoadState` with bootstrap retry/clamping, typed failures, generation checks, cache-first rendering, and a short opacity crossfade only for newly fetched content. `ReaderRoute.chapterIndex` preserves the selected TOC index through navigation.
- `TTSParagraphBuilder` chunks normalized lines without renumbering parent paragraph IDs; replacement output is checked before synthesis. TTS asynchronous work is guarded by session identity and TTS owns progress while playing.
- `ReadingProgressStore` coalesces RAM snapshots in an actor and flushes from background contexts on checkpoints, dismissal, and app backgrounding. Legacy window/tab Reader, duplicate progress repository, and `TTSSession` mirror are removed.

<!-- GENERATED END -->
