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
## Số liệu sau khi thêm PRC/DOCX/FB2 và limiter chương dài (1.3.252)

* Tổng file Swift 299 → **303** (+4, không xoá và không đổi tên file nào). **4/4 file mới dưới trần 400 dòng**: [`DocxBookParser.swift`](../../Sources/Services/Import/DocxBookParser.swift) **315**, [`Fb2BookParser.swift`](../../Sources/Services/Import/Fb2BookParser.swift) **297**, [`ChapterLengthLimiter.swift`](../../Sources/Services/Import/ChapterLengthLimiter.swift) **182**, [`DocxArchiveReader.swift`](../../Sources/Services/Import/DocxArchiveReader.swift) **49**. Không file mới nào vào bảng 1.1.
* File phình, không file nào chạm trần: [`MobiArchiveReader.swift`](../../Sources/Services/Import/MobiArchiveReader.swift) 305 → **336** (+31 cho việc kiểm chữ ký PalmDB), [`MobiBookParser.swift`](../../Sources/Services/Import/MobiBookParser.swift) 63 → **101** (+38 cho nhánh text thuần), [`BookImportFormat.swift`](../../Sources/Services/Import/BookImportFormat.swift) 79 → **107**, [`BookImportService.swift`](../../Sources/Services/Import/BookImportService.swift) 199 → **214**, [`BookImportConfirmationSheet.swift`](../../Sources/Views/Shelf/ShelfMain/BookImportConfirmationSheet.swift) 288 → **307**, `ParserChapter.swift` 10 → **24**, `ParsedBook.swift` 25 → **27**. Phân hệ `Sources/Services/Import/` tổng **2872** dòng trên 18 file, trung bình ~160 dòng/file. Không file nào ở tầng khác bị sửa.
* Điểm nóng độ phức tạp mới, đều cố ý và cô lập trong file riêng: (1) `ChapterLengthLimiter.split` là **thang bốn bậc** đoạn → câu → dòng → biên `Character`, mỗi bậc chỉ chạy khi bậc trên còn đơn vị quá dài, rồi `group()` gom tham lam bằng bộ đếm `Int` (không gọi lại `String.count`) và gộp đuôi quá ngắn về phần trước — độ sâu lồng khối 3, nhưng bất biến quan trọng hơn số liệu và được ghi ngay ở doc comment. (2) `DocxBookParser` có **hai** chiến lược cắt (`chaptersByHeading`, `chaptersByPageBreak`) cùng một delegate `XMLParser` mang state 5 biến — ngưỡng tin heading (`≥ 2` **và** không quá nửa số đoạn) là chỗ dễ sửa sai nhất. (3) `Fb2BookParser.Collector` là máy trạng thái sâu nhất trong phân hệ: stack `Frame` cộng 6 cờ vùng (`inBody`/`inDescription`/`inTitleInfo`/`inAuthor`/`inCoverpage` + hai bộ đếm độ sâu), và bất biến thứ tự đọc phụ thuộc vào việc `case "section"` **xả frame cha trước khi push**.
* `check_architecture.py`: **14 → 14 violation**, đúng cùng một tập — không vi phạm mới, không baseline nào bị nới, không entry `architecture_allowlist.json` nào được thêm.
* Không build được để đo thời gian biên dịch: host là Windows, `xcodebuild` chỉ chạy trên macOS.

## Số liệu sau khi thêm nhập truyện EPUB/HTML/MOBI–AZW3 (1.3.251)

* Tổng file Swift 284 → **299** (+15). **15/15 file mới dưới trần 400 dòng**, file lớn nhất là [`EpubBookParser.swift`](../../Sources/Services/Import/EpubBookParser.swift) **306**, kế tiếp `MobiArchiveReader.swift` 305, `XhtmlTextExtractor.swift` 242, `BookImportConfirmationSheet+Pickers.swift` 203, `BookImportService.swift` 199; nhỏ nhất `ParserChapter.swift` 10. Không file mới nào vào bảng 1.1.
* File co lại: `ShelfView.swift` 827 → **811** (dời 3 DTO xuống `Services/Import/`), `TXTImportConfirmationSheet.swift` 374 → `BookImportConfirmationSheet.swift` **288** (tách 2 picker sang `+Pickers`, thêm picker "Cấu trúc"), `ShelfView+TXTImport.swift` 283 → `ShelfView+BookImport.swift` **215** (`parseTxtBook` 43 dòng dời sang `TxtBookParser`, phần decode/parse thay bằng một lời gọi `BookImportService.parse`). File phình: `TextEncodingDecoder.swift` 44 → **102**.
* Điểm nóng độ phức tạp mới, đều cố ý và đã cô lập trong file riêng: `PalmDocDecompressor.decompress` (LZ77 4 dải byte, vòng lặp con trỏ ngược) và `stripTrailingEntries` (backwards variable-width integer); `MobiArchiveReader` đọc PalmDB/PalmDOC/MOBI/EXTH với **mọi offset kiểm biên trước khi đọc** rồi `throw .malformed(...)` thay vì đọc rác; `XhtmlTextExtractor.anchorSegments` định vị từng `id` neo rồi **lùi về dấu `<` mở tag** để không cắt giữa tag, sắp theo vị trí và cắt tài liệu thành map `id` → text. Ba chỗ này là nơi cần đọc kỹ nhất khi sửa về sau.
* `check_architecture.py`: **14 → 14 violation**, đúng cùng một tập — không vi phạm mới, không baseline nào bị nới, không entry `architecture_allowlist.json` nào được thêm.
* Không build được để đo thời gian biên dịch: host là Windows, `xcodebuild` chỉ chạy trên macOS.

## Số liệu sau khi tối ưu xuất TXT, mục lục, từ điển (1.3.250)

* Tổng file Swift: **279 → 284** (+5, không xoá và không đổi tên file nào). Ba file mới ở Services: `Download/DownloadManager+TaskStore.swift` **249 dòng**, `Download/TxtExportFileWriter.swift` **97**, `ChapterText/ChapterStore/ChapterTOCDiff.swift` **55**. Hai ở Views: `Shelf/ShelfMain/Extensions/ShelfView+TXTImport.swift` **283**, `Reader/Extensions/ReaderView+Suggestions.swift` **106**. File lớn nhất còn dư 117 dòng tới trần 400; chỉ `TxtExportFileWriter` khai type top-level (`public final class`), bốn file kia là `extension` nên **không entry `MULTI_PRIMARY_TYPES` nào được thêm**.
* File cũ **giảm** dòng: `ShelfView.swift` 1076 → **827** (−249, baseline 942 ⇒ từ vượt +134 thành dư −115), `DownloadManager.swift` 688 → **484** (−204, baseline 640 ⇒ từ vượt +48 thành dư −156), `ReaderView.swift` 2268 → **2186** (−82, vẫn vượt baseline 2053), `BookDetailView.swift` 1181 → **1175**, `ReaderChapterListView+Refresh.swift` 150 → **146**, `ChapterStoreDatabase.swift` 955 → **954**, `DictionaryCache.swift` 201 → **200**. Hai violation `LINE_LIMIT_EXCEEDED` mất đi lần này là của `ShelfView.swift` và `DownloadManager.swift`.
* File cũ **tăng** dòng, không file nào vượt baseline vì việc này: `TranslationManager.swift` 594 → **631** (+37 cho `reloadCustomDictionary`, baseline 642 ⇒ còn dư 11), `BookBinManager.swift` 154 → **168** (+14 cho cache `resolvedBinURLs`), `BookDetailView+Extensions.swift` 343 → **345** (+2). `ChapterPersistenceStore.swift` giữ đúng **915** (thay `context.save()` bằng phiên bản có điều kiện, trung tính về dòng) — file này đang vượt baseline 884 nên chỉ được phép không tăng. `git diff --stat` phần code: 15 file sửa, 293 thêm / 787 xoá; cộng 5 file mới tổng **790 dòng**.
* `check_architecture.py`: **16 → 14 violation** (6 `LINE_LIMIT_EXCEEDED` ở Services, 6 ở Views, 2 `VIEW_SWIFTDATA_MUTATION`). Tập còn lại là tập con thật sự của tập cũ; không entry `architecture_allowlist.json` nào được thêm, nới hay gia hạn.
* Độ phức tạp rẽ nhánh: ba điểm **giảm**, một điểm tăng có kiểm soát. Giảm: (1) `ReaderChapterListView+Refresh` bỏ hẳn khối dựng 2×N chuỗi identity + vòng so sánh, thay bằng một biểu thức ba điều kiện trên `SaveTOCResult`; (2) `saveDefinition` bớt hai lời gọi refresh, còn một đường duy nhất; (3) `suggestionChips` rời `body` nên đồ thị đánh giá của `ReaderView.body` bớt 6 lượt tra từ điển mỗi lần render. Tăng: `ChapterStoreDatabase.replaceFullTOC`/`upsertPage` thêm một `switch` ba nhánh trên `ChapterTOCDiff.Plan` — nhưng bù lại bỏ được lần `fetchOrderedTOC` thứ hai và cả hàm `computeDeterministicChecksum` + `fnv1aUpdate`, nên độ sâu lồng khối của hai hàm này **không tăng**. `ChapterTOCDiff.plan` là vòng `for` phẳng với các `return .full` sớm, độ sâu 2. Không file nào vào hay ra khỏi top-10 độ phức tạp / top-10 độ sâu lồng khối.
* Không build được để xác minh biên dịch: host là Windows, `xcodebuild` chỉ chạy trên macOS.

## Số liệu sau khi sửa trình soạn script và thứ tự khôi phục/ext (1.3.247)

* Tổng file Swift: **277 → 279** (+2, không xoá và không đổi tên file nào). Hai file mới đều là `extension` của `ExtensionScriptEditorView`: `+Toolbars.swift` **119 dòng**, `+Picker.swift` **117 dòng** — không khai type top-level nên không cần entry `MULTI_PRIMARY_TYPES`, và còn dư ~280 dòng tới trần 400.
* File cũ **giảm** dòng: `ExtensionScriptEditorView.swift` 583 → **384** (−199, baseline 474 ⇒ từ vượt +109 thành dư −90). Đây là violation duy nhất mất đi lần này.
* File cũ **tăng** dòng, không file nào trong allowlist: `BackupCoordinator.swift` 209 → **259** (+50: `performRestore` + `restoreEverythingFromDrive`), `GoogleDriveBackupListView.swift` 168 → **211** (+43), `HighlightingCodeEditor.swift` 169 → **204** (+35), `CodeEditorTextView.swift` 111 → **170** (+59), `RepositoryFilterPolicy.swift` 49 → **55** (+6), `BackupHubView.swift` 187 → **190** (+3). Ba file còn lại chỉ +2…+5 dòng: `AddBookToShelfCommand.swift`, `BookTransactionCoordinator.swift`, `BackupLibraryWriter.swift`. `git diff --stat` phần code: 10 file sửa, 270 thêm / 267 xoá; cộng 2 file mới tổng **236 dòng**.
* `check_architecture.py`: **17 → 16 violation** (8 `LINE_LIMIT_EXCEEDED` ở Services, 6 ở Views, 2 `VIEW_SWIFTDATA_MUTATION`). Không violation mới; không entry `architecture_allowlist.json` nào được thêm, nới hay gia hạn.
* Độ phức tạp rẽ nhánh: hai điểm tăng, cả hai đều thay *nhiều* nhánh bằng *ít* nhánh. (1) `HighlightingCodeEditor.Coordinator.tokenColors` gộp 2 lượt regex chồng nhau thành 1 lượt "vùng bảo vệ" + 4 lượt bị lọc bằng `intersectsProtected` (tìm nhị phân trên mảng range đã sắp tăng dần) — số nhánh giữ nguyên nhưng thứ tự ưu tiên nay do chính regex quyết định thay vì do thứ tự gọi. (2) `CodeEditorTextView` thêm 3 observer bàn phím dồn về **một** hàm `applyKeyboardInset()` với 2 nhánh (không có window/bàn phím ẩn ⇒ inset 0). `BackupCoordinator.restoreEverythingFromDrive` là chuỗi 3 bước tuần tự có `guard` lỗi từng bước, không lồng sâu. Không file nào vào hay ra khỏi top-10 độ phức tạp / top-10 độ sâu lồng khối.
* Không build được để xác minh biên dịch: host là Windows, `xcodebuild` chỉ chạy trên macOS.

## Số liệu sau sao lưu/khôi phục, tăng tốc cập nhật ext và sửa thông tin truyện (1.3.246)

* Tổng file Swift: **244 → 277** (+33, không xoá và không đổi tên file nào). Đây là lần thêm file lớn nhất từ phép tách một-primary-type 1.3.236 (+14). File mới lớn nhất là `Services/Backup/BackupRestoreWorker.swift` **236 dòng** — còn dư 164 dòng tới trần 400 cho file mới; nhỏ nhất là `Views/Settings/Main/BackupSettingsSection.swift` **12 dòng**. Cả 33 file đều đúng 1 primary type (các record Codable dùng type lồng trong `BackupPayload`), nên **không entry `MULTI_PRIMARY_TYPES` nào được thêm**.
* Dòng của 33 file mới — Services/Backup (17): `BackupRestoreWorker.swift` 236, `BackupExportWorker.swift` 232, `BackupCoordinator.swift` 209, `BackupPayload.swift` 196, `BackupChapterRestorer.swift` 189, `BackupLibraryWriter.swift` 187, `BackupLibraryReader.swift` 139, `BackupDictionaryRestorer.swift` 127, `BackupExtensionInstaller.swift` 120, `LocalBackupStore.swift` 105, `BackupPaths.swift` 94, `BackupDictionaryArchiver.swift` 93, `BackupZipArchive.swift` 93, `BackupManifest.swift` 80, `BackupProgress.swift` 79, `BackupScope.swift` 54, `BackupSizeEstimator.swift` 45.
* Dòng của 33 file mới — Services/Backup/GoogleDrive (6): `GoogleDriveAuthService.swift` 201, `GoogleDriveUploader.swift` 171, `GoogleDriveClient.swift` 137, `GoogleDriveTokenStore.swift` 105, `GoogleDriveConfiguration.swift` 64, `GoogleDriveFile.swift` 54. Views (8): `BookInfoEditView.swift` 214, `BackupHubView.swift` 187, `GoogleDriveBackupListView.swift` 168, `LocalBackupListView.swift` 134, `RestoreOptionsSheet.swift` 108, `BackupScopeToggleList.swift` 94, `TTSSettingsSection.swift` 24, `BackupSettingsSection.swift` 12. Services khác (1): `ExtensionSyncCommandBuilder.swift` 168. Models (1): `EditBookInfoCommand.swift` 20.
* File cũ **giảm** dòng — cả ba đều là file allowlist đang sát hoặc vượt baseline: `BookDetailView.swift` 1213 → **1181** (baseline 1201 ⇒ từ vượt +12 thành dư −20), `RepositoryManagerView.swift` 751 → **709** (baseline 751 ⇒ dư −42, trước là 0), `SettingsView.swift` 453 → **439** (baseline 453 ⇒ dư −14, trước là 0). Không baseline nào bị nới.
* File cũ **tăng** dòng, không file nào trong allowlist: `BookDetailView+Extensions.swift` 285 → **343** (+58, nhận `ellipsisMenu` chuyển sang, còn dư 57 tới trần 400), `ExtensionTransactionCoordinator.swift` → **174** (+35), `ImageCacheManager.swift` → **204** (+31), `BookTransactionCoordinator.swift` → **239** (+23). `git diff --stat` phần code: 9 file sửa, 194 thêm / 135 xoá; cộng 33 file mới tổng **3.701 dòng** cho hai thư mục backup (Services + Views).
* `check_architecture.py`: **18 → 17 violation**. Violation duy nhất mất đi là `LINE_LIMIT_EXCEEDED` của `BookDetailView.swift`; **không violation mới nào xuất hiện**, tập còn lại giống hệt (9 `LINE_LIMIT_EXCEEDED` ở Services, 6 ở Views, 2 `VIEW_SWIFTDATA_MUTATION`). Không entry `architecture_allowlist.json` nào được thêm, nới hay gia hạn.
* Độ phức tạp rẽ nhánh: ba điểm tập trung mới, đều nằm trong file mới nên không đẩy file cũ nào vào top-10. (1) `BackupChapterRestorer` — quyết định offset là nhánh nhị phân sâu nhất của phân hệ: `importFresh` (local chưa có TOC, có thể giữ offset từ backup) so với `mergeIntoExisting` (đọc lại `length` byte tại `offset` từ `.bin` đã giải nén rồi ghi lại qua `BookBinManager`, offset backup **không bao giờ** vào DB), nhân với nhánh có/không chọn nhóm `content`. (2) `BackupProgress` là enum 17 pha — nhiều case nhưng phẳng, không nhánh lồng. (3) `ExtensionSyncCommandBuilder.build` dùng `TaskGroup` cửa sổ trượt 6 lượt: 1 vòng lặp + 1 nhánh local/remote thay cho vòng lặp tuần tự 60 request trước đây. Không file nào vào hay ra khỏi top-10 độ phức tạp / top-10 độ sâu lồng khối.
* Không build được để xác minh biên dịch: host là Windows, `xcodebuild` chỉ chạy trên macOS.

## Số liệu sau tìm kiếm truyện đích, copy VP/Name và widget kéo được (1.3.244)

* Tổng file Swift: **232 → 244** (+12, không xoá file nào). File mới lớn nhất là `Views/Common/BrowserFloatingWidgetContainerViewController.swift` **197 dòng** — cách trần 400 cho file mới đúng 203 dòng; nhỏ nhất là `Views/Dictionary/DictionaryTransferTarget.swift` **12 dòng** và `Services/Extensions/Engine/VisibleBrowserSettings.swift` **13 dòng**. Cả 12 file đều đúng 1 primary type.
* Dòng của 12 file mới: `BrowserFloatingWidgetContainerViewController.swift` 197, `DictionaryEntryRow.swift` 119, `BrowserFloatingWidgetWindowManager.swift` 121, `VisibleBrowserPulseMonitor.swift` 72, `DictionaryEntryTransferAction.swift` 47, `DictionaryListView+Transfer.swift` 41, `BookSearchBarView.swift` 41, `FloatingWidgetGeometry.swift` 39, `BrowserFloatingWidgetUIWindow.swift` 26, `BrowserSettingsSection.swift` 22, `VisibleBrowserSettings.swift` 13, `DictionaryTransferTarget.swift` 12.
* File cũ **giảm** dòng: `VisibleBrowserReopenView.swift` 136 → **51** (−85, chuyển cử chỉ/vị trí sang UIKit), `ShelfSearchView.swift` 242 → **218** (−24), `DictionaryListView.swift` 767 → **748** (−19 — lần đầu file này giảm, khoảng cách tới baseline 690 thu từ −77 còn −58).
* File cũ **tăng** dòng: `VisibleBrowserTabManager.swift` 234 → **263** (+29), `BookShareTargetSheet.swift` 77 → **100** (+23), `VisibleBrowserReopenViewModel.swift` 48 → **61** (+13), `VisibleBrowserTabItem.swift` 18 → **28** (+10), `FloatingWidgetViewModel.swift` 101 → **108** (+7), `FloatingWidgetContainerViewController.swift` 240 → **246** (+6). Không file nào trong nhóm này nằm trong allowlist, nên không baseline nào bị chạm.
* Hai file over-baseline được giữ nguyên có chủ ý: `SettingsView.swift` đúng **453 dòng** (bằng baseline — section cài đặt mới nằm ở file riêng nên không phình), `DictionaryListView.swift` giảm như trên. `git diff --stat`: 12 file sửa, 187 thêm / 227 xoá.
* `check_architecture.py`: **18 → 18 violation**, tập vi phạm giống hệt (9 `LINE_LIMIT_EXCEEDED` ở Services, 7 ở Views, 2 `VIEW_SWIFTDATA_MUTATION`). Không entry `architecture_allowlist.json` nào được thêm hay nới.
* Độ phức tạp rẽ nhánh: nơi tăng đáng kể duy nhất là `DictionaryEntryRow` (2 nhánh scope × 2 loại đích = 4 mục Menu mỗi chiều, cộng nhánh thiếu ngữ cảnh) và `VisibleBrowserTabManager.openContainer` (+1 nhánh `opensMinimized`). `DictionaryEntryTransferAction.copy` chỉ có 2 nhánh và không có vòng lặp. Không file nào vào/ra khỏi top-10 độ phức tạp.
* Không build được để xác minh biên dịch: host là Windows, `xcodebuild` chỉ chạy trên macOS.

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
| 8 | `BookImportConfirmationSheet.swift` | [Views/Shelf/ShelfMain/BookImportConfirmationSheet.swift](../../Sources/Views/Shelf/ShelfMain/BookImportConfirmationSheet.swift) | 10 |
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
