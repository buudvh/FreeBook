---
generated_by: Antigravity
generator_version: 1.0
generated_at: 2026-08-21T10:30:00+07:00
git_commit: UNKNOWN
source_files: 230
document_version: 3
---

# Báo cáo Độ phức tạp & Đồ thị TODO (Complexity & TODO Report)

Tài liệu này cung cấp báo cáo chi tiết về độ phức tạp mã nguồn của dự án FreeBook và liệt kê toàn bộ các ghi chú đang dang dở (TODO / FIXME / HACK / WARNING).

## Ghi chú thủ công (Human Notes)
*Đây là khu vực con người tự viết ghi chú, AI không được phép ghi đè.*

<!-- GENERATED START -->
## Số liệu sau khi trả lại quan sát view model (1.3.243)

* Tổng file Swift: **231 → 232** (thêm `Views/Reader/Components/ReaderViewModelInvalidationRelay.swift`, 40 dòng, 1 primary type — file nhỏ nhất trong thư mục `Views/Reader/`).
* `ReaderView.swift`: 2263 → **2268 dòng** (+5: một `@StateObject`, hai lời gọi `observe`, ba dòng comment). Khoảng cách tới baseline 2053 còn −215. Vẫn là `LINE_LIMIT_EXCEEDED` cũ.
* Không file nào khác đổi số dòng: `ReaderViewModel.swift` 933, `ReaderView+LoadingView.swift` 112, `ReaderView+Controls.swift` 211, `ReaderEnergyDiagnostics.swift` 338.
* Độ phức tạp nhận thức giảm ở một điểm đáng kể hơn số dòng: cổng render của Reader (1.3.242) và nhịp chờ 32 ms (1.3.241) trước đây **không thể suy ra hành vi từ chính chúng** — phải biết thêm rằng view không quan sát view model. Sau 1.3.243 chuỗi đọc code là tuyến tính: `@Published` đổi → relay → pass → cổng.

## Số liệu sau tối ưu năng lượng Reader (1.3.239)

* Tổng file Swift: **230 → 231** (thêm `Views/Reader/Components/ReaderEnergyDiagnostics.swift`, 258 dòng, 1 primary type — dưới trần 400 dòng cho file mới).
* `ReaderTextView.swift`: 647 → **450 dòng** (−197). Baseline allowlist của file là 651 nên nó vẫn không nằm trong `LINE_LIMIT_EXCEEDED`; khoảng dư tăng từ 4 lên 201 dòng. File vẫn còn 3 type top-level nên miễn trừ `MULTI_PRIMARY_TYPES` chưa bỏ được.
* `ReaderView.swift`: 2250 → **2248 dòng**; khoảng cách tới baseline 2053 còn −195 (trước là −197). Vẫn là `LINE_LIMIT_EXCEEDED` cũ, không phải violation mới.
* Các file còn lại: `ParagraphCardView.swift` 102 → 101, `ParagraphTracker.swift` 90 → 94 (chỉ thêm comment cảnh báo về `minimumFrameDelta`), `ReaderView+Controls.swift` 161 (không đổi số dòng).
* Độ phức tạp rẽ nhánh: `ReaderTextView.swift` giảm nhẹ (chuyển `prediction`/`thermalStateName`/`applicationStateName` — tổng ~20 nhánh `switch`/`if` — sang file mới), bù lại `publishSelection`/`isSamePosition` thêm ~6 nhánh. File mới có CC ước lượng ~45, không chạm top-10. Không file nào vào/ra khỏi top-10 độ phức tạp hay top-10 độ sâu lồng khối.
* `check_architecture.py`: **18 → 18 violation**, tập vi phạm giống hệt trước thay đổi. Không nới baseline, không thêm entry allowlist.
* Không build được để xác minh biên dịch: host là Windows, `xcodebuild` chỉ chạy trên macOS.

## Số liệu sau phép tách một-primary-type (1.3.236)

* Tổng file Swift: **216 → 230** (+14 file tách ra, không xoá file nào).
* `check_architecture.py`: **28 → 18 violation**. Hết toàn bộ 8 `MULTI_PRIMARY_TYPES` và cả 2 `NEW_FILE_TOO_LARGE`.
* File lớn nhất trong 14 file mới: `FloatingWidgetContainerViewController.swift` 240 dòng; `TabbedVisibleBrowserViewController.swift` 201; `VisibleWebViewController.swift` 122; `CodeEditorTextView.swift` 111; `TextEncodingOption.swift` 102. Tất cả dưới trần 400 dòng cho file mới.
* Giảm dòng đáng kể ở file gốc: `TTSFloatingWidgetWindowManager.swift` 375 → 112 (−263), `VisibleBrowserTabManager.swift` 448 → 234 (−214), `HighlightingCodeEditor.swift` 278 → 166 (−112), `VisibleWebViewLoader.swift` 404 → 285 (−119), `VisibleBrowserReopenView.swift` 234 → 128 (−106), `TextEncodingDecoder.swift` 145 → 43 (−102).
* **Nợ còn lại: 16 `LINE_LIMIT_EXCEEDED`.** Không file nào trong số đó có type top-level thứ hai để tách, nên phải tách thành viên sang file `X+Feature.swift`. Khoảng cách tới baseline: `TTSManager.swift` −533, `JSExecutor.swift` −448, `ReaderView.swift` −197, `ShelfView.swift` −134, `TranslateUtils.swift` −124, `ExtensionScriptEditorView.swift` −109, `DictionaryListView.swift` −77, `ReaderViewModel.swift` −66, `TTSDictionaryEditView.swift` −65, `ReaderChapterListView.swift` −60, `DownloadManager.swift` −48, `ChapterPersistenceStore.swift` −31, `JSDom.swift` −28, `ExtensionManager.swift` −27, `ReaderDefinitionOverlayView.swift` −21, `BookDetailView.swift` −12.

## Dọn code chết: số liệu trước/sau (1.3.235)

* Tổng file Swift: **220 → 216** (xoá 5, thêm 1 do đổi tên). Ngoài ra 20 file dưới `Tests/` bị xoá khỏi repo (không tính vào `Sources/`).
* `check_architecture.py`: **30 → 28 violation**. Hai violation hết hẳn: `NEW_FILE_TOO_LARGE` của `TTSChapterPrefetcher.swift` (402 → 375) và `LINE_LIMIT_EXCEEDED` của `TranslationManager.swift` (649 → 601, dưới baseline 642).
* Các file lớn giảm dòng: `TTSManager.swift` **4097 → 4003** (xoá `logRemoteTrace` + 4 hàm chết, sau khi đã cộng +4 dòng của tính năng prefix chương kế ở 1.3.234); `ExtensionManager.swift` 1066 → 1049; `TranslateUtils.swift` 1046 → 1041; `DoubleArrayTrie.swift` −49; `NghiTTSClient.swift` −57.
* Không file nào tăng dòng. Không thêm primary type mới; `ReaderParagraphBuildResult.swift` (7 dòng) là file nhỏ nhất repo sau thay đổi.

## Incremental complexity update (1.3.234)

* File mới `Sources/Services/TTS/TTSNextChapterPrefixCache.swift`: **380 dòng vật lý**, 1 primary type (kèm nested `PreparedChunk`), hàm dài nhất `synthesize` (~62 dòng, 3 nhánh engine), không có nested closure sâu quá 2 mức. Dưới trần 400 dòng cho file mới.
* File mới `Sources/Services/TTS/Extensions/TTSManager+NextChapterPrefix.swift`: **130 dòng vật lý**, extension nên không khai primary type; 8 hàm, hàm dài nhất `requestNghiNextChapterPrefixIfNeeded` (~26 dòng).
* `Sources/Services/TTS/NghiTTS/NghiSynthesisPolicy.swift`: 28 → **32 dòng** (thêm hằng `maxTotalAudioPayloads` + doc comment).
* `Sources/Services/TTS/TTSManager.swift`: 4097 → **4101 dòng** (+4 call site: `pause`, `applyNextChapter`, `updatePrefetchWindow`, `updateNghiPrefetchWindow`). Baseline allowlist là 3470 nên file này vẫn nằm trong danh sách `LINE_LIMIT_EXCEEDED` đã có từ trước; thay đổi này **không tạo violation mới** nhưng cũng chưa hạ được baseline — cần được tính vào nợ kỹ thuật của `TTSManager`.
* `Sources/Services/TTS/Extensions/TTSManager+PrefetchCache.swift`: 46 → **47 dòng**.
* `check_architecture.py` trước/sau thay đổi: cùng 30 violation, khác biệt duy nhất là số dòng của `TTSManager.swift`.

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
