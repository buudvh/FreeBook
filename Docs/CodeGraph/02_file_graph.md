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
## Nhập truyện PDF chỉ lấy lớp văn bản (1.3.255)

| File mới | Vai trò | Dòng |
|---|---|---|
| [`Services/Import/PdfDocumentReader.swift`](../../Sources/Services/Import/PdfDocumentReader.swift) | **file duy nhất** `import PDFKit`: mở/mở khoá tài liệu, text từng trang, outline làm phẳng, metadata | 131 |
| [`Services/Import/PdfBookParser.swift`](../../Sources/Services/Import/PdfBookParser.swift) | outline → quy tắc TOC → mỗi trang một chương; đếm trang thiếu lớp văn bản để cảnh báo | 136 |

| File sửa | Dòng | Thay đổi |
|---|---|---|
| [`Services/Import/BookImportFormat.swift`](../../Sources/Services/Import/BookImportFormat.swift) | 107 → **125** | thêm `case pdf`, magic `%PDF-`, và `detect(fileNameOnly:) -> BookImportFormat?` để nhánh PDF không phải nạp `Data` |
| [`Services/Import/BookImportService.swift`](../../Sources/Services/Import/BookImportService.swift) | 214 → **257** | nhánh `.pdf`, `Request.password`, 3 `ImportError` mới (`passwordRequired`/`wrongPassword`/`noTextLayer`), `loadData(_:)` chỉ gọi khi nhánh cần byte |
| [`Services/Import/ParsedBook.swift`](../../Sources/Services/Import/ParsedBook.swift) | 27 → **30** | `warningNote` — cảnh báo mất mát nội dung người dùng phải tự chấp nhận |
| [`Views/Shelf/ShelfMain/BookImportConfirmationSheet.swift`](../../Sources/Views/Shelf/ShelfMain/BookImportConfirmationSheet.swift) | 307 → **342** | khối cảnh báo cam + `Toggle` chấp nhận, `canConfirm` chặn nút "Nhập", `.pdf` vào nhóm ẩn hàng Bảng mã |
| [`Views/Shelf/ShelfMain/Extensions/ShelfView+BookImport.swift`](../../Sources/Views/Shelf/ShelfMain/Extensions/ShelfView+BookImport.swift) | 215 → **273** | `startImportParse`/`askImportPassword`/`submitImportPassword`/`cancelPasswordPrompt`; `reanalyzeImport` nhận `password` |
| [`Views/Shelf/ShelfMain/ShelfView.swift`](../../Sources/Views/Shelf/ShelfMain/ShelfView.swift) | 811 → **836** | 3 `@State` mật khẩu, `PendingPasswordFile` (nest), `.alert` `SecureField`, `PendingImport.password` |

* Tổng file Swift 324 → **326** (+2), cả hai trong [`Sources/Services/Import/`](../../Sources/Services/Import/BookImportService.swift) (18 → **20** file). Không thư mục mới, không file bị xoá hay đổi tên.
* Quan hệ import mới: `Services/Import/PdfDocumentReader` → `PDFKit` (framework hệ thống, **không** sửa `project.yml`) — `PdfBookParser` chỉ nói chuyện với reader nên chỗ tách chương không biết gì về PDFKit; `PdfBookParser` → `TxtBookParser` (nhánh quy tắc TOC) + `XhtmlTextExtractor.dropLeadingTitle` (dùng chung với EPUB/DOCX/FB2).
* `Views/Shelf/ShelfMain/**` vẫn là phía gọi duy nhất của `Services/Import/**`; không có quan hệ mới nào theo chiều ngược.

## Sao lưu ảnh bìa của truyện nhập từ file (1.3.254)

| File mới | Vai trò | Dòng |
|---|---|---|
| [`Services/Backup/BackupCoverArchiver.swift`](../../Sources/Services/Backup/BackupCoverArchiver.swift) | chủ duy nhất của entry `covers/<slug>.jpg`, cả hai chiều xuất/khôi phục | 80 |

* File sửa nội dung, quan hệ import không đổi: `BackupPaths.swift` 94 → **96** (`cover(slug:)`), `BackupPayload.swift` 196 → **204** (`BookRecord.hasUnrecoverableCover`), `BackupManifest.swift` 80 → **103** (`Counts.covers` + `CodingKeys` + `init(from:)` khoan nhượng), `BackupProgress.swift` 79 → **83** (19 pha: thêm `copyingCovers`/`restoringCovers`), `BackupExportWorker.swift` 232 → **240**, `BackupRestoreWorker.swift` 236 → **245** (`Outcome.covers`), `BackupCoordinator.swift` 259 → **275**, `BackupScope.swift` (chỉ sửa doc comment đã sai), `RestoreOptionsSheet.swift` 108 → **111**.
* Quan hệ mới: `Services/Backup/BackupCoverArchiver` → `Common/Services/ImageCacheManager` (`localCoverURL(for:)` — không đi qua `saveCover` để không nén lại JPEG) + `Services/Backup/BackupZipArchive`. Cả `BackupExportWorker` và `BackupRestoreWorker` gọi vào **một** file này, không tự dựng tên entry `covers/`.

## Xuất truyện TXT, EPUB, FB2, MOBI trong một tác vụ (1.3.253)

| File mới | Vai trò | Dòng |
|---|---|---|
| [`Services/Export/BookExportRequest.swift`](../../Sources/Services/Export/BookExportRequest.swift) | DTO **bất biến** của một lần xuất; renderer không thấy `DownloadTask`/`Book`/SwiftData | 44 |
| [`Services/Export/BookExportFormat.swift`](../../Sources/Services/Export/BookExportFormat.swift) | `txt`/`epub3`/`fb2`/`mobi` + `fileExtension`/`taskType`/`supportsCover`/`supportsNavigation` | 72 |
| [`Services/Export/ExportRenderer.swift`](../../Sources/Services/Export/ExportRenderer.swift) | protocol `append(_:)`/`finish()`/`discard()` + `writtenChapterCount`/`hasContent` | 19 |
| [`Services/Export/ExportRendererFactory.swift`](../../Sources/Services/Export/ExportRendererFactory.swift) | `BookExportFormat` → renderer; `switch` liệt kê đủ case | 18 |
| [`Services/Export/ExportContentProvider.swift`](../../Sources/Services/Export/ExportContentProvider.swift) | lấy một chương (cache → tải → `.bin` → `ChapterStore`) + `Tally`; **dùng chung** cho tải và xuất | 111 |
| [`Services/Export/ExportChapterPayload.swift`](../../Sources/Services/Export/ExportChapterPayload.swift) | `ordinal`/`title`/`content` đưa vào renderer | 16 |
| [`Services/Export/ExportArtifact.swift`](../../Sources/Services/Export/ExportArtifact.swift) | kết quả `finish()` + `exists` — cổng chặn "hoàn thành mà không có file" | 23 |
| [`Services/Export/ExportStage.swift`](../../Sources/Services/Export/ExportStage.swift) | 3 giai đoạn hiển thị: đang lấy chương / đang tạo file / sẵn sàng chia sẻ | 21 |
| [`Services/Export/ExportRenderError.swift`](../../Sources/Services/Export/ExportRenderError.swift) | `cannotCreateFile`/`emptyExport`/`archiveTooLarge`/`sizeLimitExceeded` (thông báo tiếng Việt) | 23 |
| [`Services/Export/ExportFileNaming.swift`](../../Sources/Services/Export/ExportFileNaming.swift) | `Documents/Exports/<tên>-yyyyMMdd-HHmmss.<ext>` + khử trùng `-2…`, `stagingURL` = `.part` | 54 |
| [`Services/Export/ExportStagingFile.swift`](../../Sources/Services/Export/ExportStagingFile.swift) | `FileHandle` ghi thẳng xuống `.part`, `commit()` mới rename (kế thừa `TxtExportFileWriter`) | 74 |
| [`Services/Export/ExportParagraphSplitter.swift`](../../Sources/Services/Export/ExportParagraphSplitter.swift) | cắt đoạn **giống hệt** `DownloadManager.formatChapter` cũ, dùng chung 4 renderer | 15 |
| [`Services/Export/ExportTextEscaper.swift`](../../Sources/Services/Export/ExportTextEscaper.swift) | escape XML/HTML + bỏ ký tự điều khiển (một `\u{0}` là EPUB/FB2 sai chuẩn) | 41 |
| [`Services/Export/TxtExportRenderer.swift`](../../Sources/Services/Export/TxtExportRenderer.swift) | TXT **giữ nguyên từng byte** bố cục bản xuất cũ | 44 |
| [`Services/Export/ZipStoreWriter.swift`](../../Sources/Services/Export/ZipStoreWriter.swift) | ZIP stored-only (method 0) tự viết: local header + central directory + EOCD, CRC-32 bảng tra | 154 |
| [`Services/Export/EpubExportRenderer.swift`](../../Sources/Services/Export/EpubExportRenderer.swift) | EPUB 3: `mimetype` đầu tiên, `container.xml`, OPF, `nav.xhtml`, một XHTML mỗi chương | 180 |
| [`Services/Export/Fb2ExportRenderer.swift`](../../Sources/Services/Export/Fb2ExportRenderer.swift) | FB2 2.0 chảy thẳng ra đĩa; bìa base64 `<binary>` ghi ở `finish()` | 94 |
| [`Services/Export/MobiExportRenderer.swift`](../../Sources/Services/Export/MobiExportRenderer.swift) | PalmDB/PalmDOC không nén; text staged rồi copy, vá `filepos` mục lục 10 chữ số | 207 |
| [`Services/Export/MobiHeaderBuilder.swift`](../../Sources/Services/Export/MobiHeaderBuilder.swift) | record 0: PalmDOC 16 B + MOBI 232 B + EXTH (100/103/503/201) | 138 |
| [`Services/Export/BigEndianBytes.swift`](../../Sources/Services/Export/BigEndianBytes.swift) | nối UInt16/UInt32 **big-endian** (ngược với ZIP little-endian) | 27 |
| [`Views/Common/ExportShareCoordinator.swift`](../../Sources/Views/Common/ExportShareCoordinator.swift) | chủ `UIActivityViewController`; giữ pending khi app ở background rồi bàn giao lúc `.active` | 100 |

| File sửa nội dung | Dòng | Thay đổi |
|---|---|---|
| [`Services/Download/DownloadManager.swift`](../../Sources/Services/Download/DownloadManager.swift) | 484 → **437** | `TaskType` thêm 3 case xuất; vòng lặp dùng `ExportContentProvider` + `ExportRenderer`; **xoá** `formatChapter`/`presentShareSheet` và `import UIKit` |
| [`Services/Download/DownloadManager+TaskStore.swift`](../../Sources/Services/Download/DownloadManager+TaskStore.swift) | 249 → **277** | thêm `updateExportStage` + `markExportCompleted` (lưu path, tổng kết, phát `exportReady`) |
| [`Services/Download/DownloadTaskOutcomeCalculator.swift`](../../Sources/Services/Download/DownloadTaskOutcomeCalculator.swift) | 39 → **62** | nhánh xuất theo `renderedChapterCount` + `exportSummary(...)` |
| [`Services/Download/Events/DownloadPresentationEvent.swift`](../../Sources/Services/Download/Events/DownloadPresentationEvent.swift) | 5 → **11** | case `exportReady(filePath:bookTitle:)` |
| [`Views/Download/TaskOptionsSheet.swift`](../../Sources/Views/Download/TaskOptionsSheet.swift) | 148 → **209** | picker "Định dạng bản xuất" + xem trước `đã tải X/Y chương`, enqueue `effectiveTaskType` |
| [`Views/Download/DownloadTrackerView.swift`](../../Sources/Views/Download/DownloadTrackerView.swift) | 208 → **217** | dòng giai đoạn + dòng tổng kết thiếu chương; `exportFromCached` mở sheet thay vì enqueue TXT |
| [`App/FreeBookApp.swift`](../../Sources/App/FreeBookApp.swift) | 103 → **105** | `AppLaunchRootView` nhận `.exportReady` → `ExportShareCoordinator.requestShare` |
| [`Views/MainTabView.swift`](../../Sources/Views/MainTabView.swift) | 70 → **76** | `scenePhase == .active` → `flushPendingShare()` |
| [`Views/Shelf/ShelfMain/ShelfView.swift`](../../Sources/Views/Shelf/ShelfMain/ShelfView.swift) | 811 (không đổi) | nhãn `"Xuất ebook TXT"` → `"Xuất ebook"` (2 chỗ) — định dạng chọn ở sheet |
| [`Views/BookDetail/BookDetailView.swift`](../../Sources/Views/BookDetail/BookDetailView.swift) | 1175 (không đổi) | nhãn `"Xuất TXT"` → `"Xuất ebook"` |

* File bị xoá: `Services/Download/TxtExportFileWriter.swift` (97 dòng) — thay bằng `Services/Export/ExportStagingFile.swift` dùng chung cho cả 4 renderer.
* Tổng file Swift 303 → **323** (+21 mới, −1 xoá). Thư mục mới duy nhất: [`Sources/Services/Export/`](../../Sources/Services/Export/BookExportRequest.swift) (20 file).
* Quan hệ import mới: `Services/Download/DownloadManager` → `Services/Export/*` (một chiều — không renderer nào biết `DownloadManager`); `App/FreeBookApp` + `Views/MainTabView` → `Views/Common/ExportShareCoordinator`. `Sources/Services/Export/**` **không** `import UIKit`/`SwiftUI`, **không** gọi `ToastManager.shared`, **không** `import ZIPFoundation` (EPUB dùng `ZipStoreWriter` tự viết).
* `project.yml` không cần sửa: target khai `sources: - path: Sources` nên `xcodegen generate` tự nhặt 21 file mới.

## Nhập truyện PRC, DOCX, FB2 và tách chương quá dài (1.3.252)

| File mới | Vai trò | Dòng |
|---|---|---|
| [`Services/Import/ChapterLengthLimiter.swift`](../../Sources/Services/Import/ChapterLengthLimiter.swift) | hậu xử lý **chung** mọi format: tách chương > 30 000 ký tự theo đoạn → câu → dòng → biên `Character` | 182 |
| [`Services/Import/DocxArchiveReader.swift`](../../Sources/Services/Import/DocxArchiveReader.swift) | giải nén DOCX qua `BackupZipArchive`, lấy `word/document.xml` + `docProps/core.xml`, `defer` tự dọn thư mục tạm | 49 |
| [`Services/Import/DocxBookParser.swift`](../../Sources/Services/Import/DocxBookParser.swift) | OOXML `XMLParser` → `[Block]` → Heading 1–3 → mốc sang trang → quy tắc TOC → 1 chương | 315 |
| [`Services/Import/Fb2BookParser.swift`](../../Sources/Services/Import/Fb2BookParser.swift) | FB2 `section`/`title`/`p` + `title-info` + bìa `<binary>`; từ chối file khai `<!ENTITY` | 297 |

| File sửa nội dung | Dòng | Thay đổi |
|---|---|---|
| [`Services/Import/MobiArchiveReader.swift`](../../Sources/Services/Import/MobiArchiveReader.swift) | 305 → **336** | kiểm chữ ký PalmDB @60…67: `BOOKMOBI`/`TEXtREAd` hợp lệ, biến thể khác `throw .malformed`; `Package` thêm `isPlainText` |
| [`Services/Import/MobiBookParser.swift`](../../Sources/Services/Import/MobiBookParser.swift) | 63 → **101** | `TEXtREAd` (text thuần) rẽ sang `TxtBookParser` sau khi chuẩn hoá `\r\n`/`\r`/`\u{0C}`, thay vì luôn đi `HtmlBookParser` |
| [`Services/Import/BookImportFormat.swift`](../../Sources/Services/Import/BookImportFormat.swift) | 79 → **107** | thêm `docx`/`fb2`, picker mở thêm `prc`/`docx`/`fb2`, phân biệt ZIP `epub+zip` vs `word/document.xml` |
| [`Services/Import/BookImportService.swift`](../../Sources/Services/Import/BookImportService.swift) | 199 → **214** | 2 nhánh mới + **phần đuôi dùng chung** gọi `ChapterLengthLimiter.apply` đúng một lần cho mọi format |
| [`Services/Import/ParserChapter.swift`](../../Sources/Services/Import/ParserChapter.swift) | 10 → **24** | 4 field provenance tạm thời `originalTitle`/`sourceOrdinal`/`partIndex`+`partCount`/`splitReason` |
| [`Services/Import/ParsedBook.swift`](../../Sources/Services/Import/ParsedBook.swift) | 25 → **27** | `chapters` thành `var` để limiter thay danh sách ở bước hậu xử lý |
| [`Views/Shelf/ShelfMain/BookImportConfirmationSheet.swift`](../../Sources/Views/Shelf/ShelfMain/BookImportConfirmationSheet.swift) | 288 → **307** | dòng báo cáo tách chương (cam) + `showsDecodeRow` thành `switch` liệt kê đủ case |

* Tổng file Swift 299 → **303** (+4), tất cả nằm trong [`Sources/Services/Import/`](../../Sources/Services/Import/BookImportService.swift) (14 → **18** file). Không thư mục mới, không file nào bị xoá hay đổi tên.
* Quan hệ import mới: `Services/Import/DocxArchiveReader` → `Services/Backup/BackupZipArchive` (điểm gọi ZIPFoundation duy nhất — file mới **không** `import ZIPFoundation`, giống `EpubArchiveReader`); `DocxBookParser`/`Fb2BookParser` → `Foundation` (`XMLParser`) và `TxtBookParser` cho nhánh quy tắc TOC, **không** đi qua SwiftSoup nên `XhtmlTextExtractor` vẫn là file duy nhất của phân hệ `import SwiftSoup`; `Views/Shelf/ShelfMain/BookImportConfirmationSheet` → `Services/Import/ChapterLengthLimiter` (chỉ đọc `report(for:)`, đúng chiều Views → Services).
* `ChapterLengthLimiter` **không** có caller nào ngoài `BookImportService.parse` — cố ý: limiter là một bước của pipeline nhập, không phải tiện ích dùng chung. Tầng View chỉ gọi `report(for:)` để hiển thị.
* `project.yml` không cần sửa: target khai `sources: - path: Sources` nên `xcodegen generate` tự nhặt 4 file mới.
* Không build được để xác minh biên dịch: host là Windows, `xcodebuild` chỉ chạy trên macOS.

## Nhập truyện từ EPUB, HTML, MOBI/AZW3 ngoài TXT (1.3.251)

| File mới | Vai trò | Dòng |
|---|---|---|
| [`Services/Import/ParserChapter.swift`](../../Sources/Services/Import/ParserChapter.swift) | DTO một chương đã bóc tách (dời từ `ShelfView.swift`) | 10 |
| [`Services/Import/ParsedBook.swift`](../../Sources/Services/Import/ParsedBook.swift) | DTO cả sách; thêm `author/desc/coverData/remoteCoverUrl/structureNote` đều mặc định `nil` | 25 |
| [`Services/Import/BookImportFormat.swift`](../../Sources/Services/Import/BookImportFormat.swift) | 4 format + `detect(fileName:data:)` (đuôi file trước, magic bytes sau) + `pickerContentTypes` | 79 |
| [`Services/Import/BookImportService.swift`](../../Sources/Services/Import/BookImportService.swift) | điểm vào duy nhất `parse(_:)`; nest `StructureMode`/`Request`/`Result`/`ImportError` | 199 |
| [`Services/Import/TxtBookParser.swift`](../../Sources/Services/Import/TxtBookParser.swift) | `parseTxtBook` cũ dời nguyên văn khỏi tầng View | 57 |
| [`Services/Import/XhtmlTextExtractor.swift`](../../Sources/Services/Import/XhtmlTextExtractor.swift) | SwiftSoup → plain text (sentinel `@@FBNL@@`), `headingSections`, `anchorSegments(html:anchorIds:)`, `declaredCharsetName(in:)` | 242 |
| [`Services/Import/HtmlBookParser.swift`](../../Sources/Services/Import/HtmlBookParser.swift) | `<mbp:pagebreak>` → heading → quy tắc TOC → 1 chương | 138 |
| [`Services/Import/EpubArchiveReader.swift`](../../Sources/Services/Import/EpubArchiveReader.swift) | giải nén qua `BackupZipArchive`, `container.xml` → OPF, `resolve(href:)` chặn zip-slip | 98 |
| [`Services/Import/EpubOpfParser.swift`](../../Sources/Services/Import/EpubOpfParser.swift) | `XMLParser` một lượt: metadata + manifest + spine + `coverId` | 146 |
| [`Services/Import/EpubNavParser.swift`](../../Sources/Services/Import/EpubNavParser.swift) | `toc.ncx` (flatten navPoint lồng) và `nav` EPUB3 | 136 |
| [`Services/Import/EpubBookParser.swift`](../../Sources/Services/Import/EpubBookParser.swift) | `tocIndex` → `spine` → `tocRules`; `defer` dọn thư mục tạm | 306 |
| [`Services/Import/PalmDocDecompressor.swift`](../../Sources/Services/Import/PalmDocDecompressor.swift) | LZ77 PalmDOC + `stripTrailingEntries(record:flags:)` | 97 |
| [`Services/Import/MobiArchiveReader.swift`](../../Sources/Services/Import/MobiArchiveReader.swift) | PalmDB/PalmDOC/MOBI/EXTH, mọi offset kiểm biên trước khi đọc | 305 |
| [`Services/Import/MobiBookParser.swift`](../../Sources/Services/Import/MobiBookParser.swift) | ghép record text → decode → `HtmlBookParser` | 63 |
| [`Views/Shelf/ShelfMain/Extensions/BookImportConfirmationSheet+Pickers.swift`](../../Sources/Views/Shelf/ShelfMain/Extensions/BookImportConfirmationSheet+Pickers.swift) | 3 picker: bảng mã, quy tắc TOC, **Cấu trúc** (mới) | 203 |

| File đổi tên | Thành | Dòng |
|---|---|---|
| `Views/Shelf/ShelfMain/Extensions/ShelfView+TXTImport.swift` (283) | [`ShelfView+BookImport.swift`](../../Sources/Views/Shelf/ShelfMain/Extensions/ShelfView+BookImport.swift) | 215 |
| `Views/Shelf/ShelfMain/TXTImportConfirmationSheet.swift` (374) | [`BookImportConfirmationSheet.swift`](../../Sources/Views/Shelf/ShelfMain/BookImportConfirmationSheet.swift) | 288 |

* Tổng file Swift 284 → **299** (+15). Thư mục mới duy nhất: [`Sources/Services/Import/`](../../Sources/Services/Import/BookImportService.swift) (14 file).
* File sửa nội dung: [`ShelfView.swift`](../../Sources/Views/Shelf/ShelfMain/ShelfView.swift) 827 → **811** (−16: xoá 3 DTO `ParserChapter`/`ParsedBook`/`TXTReanalysisResult` đã dời xuống Services, nhãn menu thành `"Nhập truyện từ file"`, picker dùng `BookImportFormat.pickerContentTypes`, `PendingImport` thêm `format`), [`TextEncodingDecoder.swift`](../../Sources/Common/Utils/TextEncodingDecoder.swift) 44 → **102** (thêm `option(forCharsetName:)` + `decodeDeclared(_:charsetName:)`, không thêm case mới cho `TextEncodingOption`).
* Quan hệ import mới: `Views/Shelf/ShelfMain/**` → `Services/Import/**` (một chiều, đúng chiều Views → Services); `Services/Import/EpubArchiveReader` → `Services/Backup/BackupZipArchive` (điểm gọi ZIPFoundation duy nhất — file mới **không** `import ZIPFoundation`); `XhtmlTextExtractor` → `SwiftSoup` (**file duy nhất** của phân hệ `import SwiftSoup`; `EpubNavParser` đi qua `XhtmlTextExtractor.inlineText` vì selector SwiftSoup không nhận tên thuộc tính có dấu `:` như `epub:type`); `MobiArchiveReader`/`EpubOpfParser`/`EpubNavParser` → `Foundation` (`XMLParser`, `Data`) không thư viện ngoài.
* `Services/Import/**` không file nào `import SwiftUI` hay gọi `ToastManager.shared`: lỗi đi bằng `throw BookImportService.ImportError` và tầng View đổ `localizedDescription` vào Toast.
* `project.yml` không cần sửa: target khai `sources: - path: Sources` nên `xcodegen generate` tự nhặt 15 file mới và 2 file đổi tên.
* Không build được để xác minh biên dịch: host là Windows, `xcodebuild` chỉ chạy trên macOS.

## Sửa trình soạn script, khôi phục giữ thứ tự, sắp ext có cập nhật lên đầu (1.3.247)

| File mới | Tách khỏi | Dòng |
|---|---|---|
| `Views/Extensions/Editor/ExtensionScriptEditorView+Picker.swift` | `ExtensionScriptEditorView.swift` | 117 |
| `Views/Extensions/Editor/ExtensionScriptEditorView+Toolbars.swift` | `ExtensionScriptEditorView.swift` | 119 |

* Tổng file Swift 277 → **279** (+2). Không file nào bị xoá, đổi tên hay đổi thư mục.
* `ExtensionScriptEditorView.swift` 583 → **384** (−199): sheet chọn file sang `+Picker`, hai thanh dưới cùng + `dismissKeyboard()` sang `+Toolbars`. File rời khỏi danh sách vi phạm `LINE_LIMIT_EXCEEDED` (baseline 474).
* `+Toolbars.swift` là file duy nhất trong `Views/Extensions/Editor/**` khai `import UIKit` bên cạnh `SwiftUI`: `dismissKeyboard()` gọi `UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), …)` nên không dựa vào việc SwiftUI re-export UIKit.
* File sửa nội dung, quan hệ import không đổi: `CodeEditorTextView.swift` 111 → **170** (quan sát 3 notification bàn phím, cộng phần bị che vào `contentInset.bottom`), `HighlightingCodeEditor.swift` 169 → **204** (`tokenColors` + `applyHighlight` tại chỗ trên `textStorage`), `RepositoryFilterPolicy.swift` 49 → **55** (khoá sắp xếp `hasUpdate` đứng đầu), `AddBookToShelfCommand.swift` (+`lastReadDate`), `BookTransactionCoordinator.swift`, `BackupLibraryWriter.swift`, `BackupCoordinator.swift` 209 → **259** (tách `performRestore` + `restoreEverythingFromDrive`), `BackupHubView.swift`, `GoogleDriveBackupListView.swift` 168 → **211**.
* Quan hệ mới: `GoogleDriveBackupListView` → `TTSWidgetStateReader` + `modelContext.container` (một chạm khôi phục cần container và cờ TTS đang phát); `BackupCoordinator.restoreEverythingFromDrive` → `GoogleDriveClient` → `LocalBackupStore` → `BackupRestoreWorker` trong **một** lượt giữ khoá `isBusy`.
* `project.yml` không cần sửa: target khai `sources: - path: Sources` theo thư mục nên `xcodegen generate` tự nhặt 2 file mới.
* Không build được để xác minh biên dịch: host là Windows, `xcodebuild` chỉ chạy trên macOS.

## Sao lưu/khôi phục, tăng tốc cập nhật ext, sửa thông tin truyện (1.3.246)

| File mới | Vai trò | Dòng |
|---|---|---|
| `Models/Books/EditBookInfoCommand.swift` | command bất biến cho sửa tên/tác giả/bìa | 20 |
| `Services/Backup/BackupScope.swift` | 6 nhóm dữ liệu chọn được, `books` bắt buộc | 54 |
| `Services/Backup/BackupPaths.swift` | nguồn duy nhất của tên entry trong archive + thư mục `backups/` | 94 |
| `Services/Backup/BackupManifest.swift` | `manifest.json`, `schemaVersion 1`, `Counts` | 80 |
| `Services/Backup/BackupPayload.swift` | DTO Codable của Book/Repository/Extension/Chapter | 196 |
| `Services/Backup/BackupProgress.swift` | 17 pha tiến độ + nhãn tiếng Việt | 79 |
| `Services/Backup/BackupZipArchive.swift` | **điểm gọi ZIPFoundation duy nhất** của phân hệ backup | 93 |
| `Services/Backup/BackupLibraryReader.swift` | đọc SwiftData → DTO `Sendable` (MainActor, chỉ đọc) | 139 |
| `Services/Backup/BackupDictionaryArchiver.swift` | gom file từ điển nguyên trạng, không parse | 93 |
| `Services/Backup/BackupSizeEstimator.swift` | dung lượng ước tính từng nhóm cho UI | 45 |
| `Services/Backup/BackupExportWorker.swift` | actor dựng thư mục tạm rồi zip | 232 |
| `Services/Backup/BackupRestoreWorker.swift` | actor điều phối restore (chỉ merge, không xoá) | 236 |
| `Services/Backup/BackupLibraryWriter.swift` | ghi SwiftData qua coordinator, chỉ chèn cái thiếu | 187 |
| `Services/Backup/BackupChapterRestorer.swift` | TOC + cache chương, quyết định giữ/bỏ offset | 189 |
| `Services/Backup/BackupExtensionInstaller.swift` | cài ext, tính lại `localPath` trên máy đích | 120 |
| `Services/Backup/BackupDictionaryRestorer.swift` | merge từ điển, tombstone đi kèm miễn phí | 127 |
| `Services/Backup/LocalBackupStore.swift` | liệt kê/xoá/đổi tên/nhập file trong `backups/` | 105 |
| `Services/Backup/BackupCoordinator.swift` | `ObservableObject` cầu nối UI ↔ worker | 209 |
| `Services/Backup/GoogleDrive/GoogleDriveConfiguration.swift` | clientId (override + Info.plist), scope `drive.file`, endpoint | 64 |
| `Services/Backup/GoogleDrive/GoogleDriveAuthService.swift` | PKCE S256 + `ASWebAuthenticationSession` | 201 |
| `Services/Backup/GoogleDrive/GoogleDriveTokenStore.swift` | refresh token: Keychain + fallback file có file protection | 105 |
| `Services/Backup/GoogleDrive/GoogleDriveFile.swift` | DTO file Drive + tên/kích thước hiển thị | 54 |
| `Services/Backup/GoogleDrive/GoogleDriveClient.swift` | tìm/tạo thư mục, list, download, delete | 137 |
| `Services/Backup/GoogleDrive/GoogleDriveUploader.swift` | resumable upload chunk 8 MiB, xử lý 308 | 171 |
| `Services/Extensions/Manager/ExtensionSyncCommandBuilder.swift` | tải/parse `plugin.json` song song ngoài main | 168 |
| `Views/BookDetail/BookInfoEditView.swift` | form sửa tên/tác giả/bìa (URL hoặc `PhotosPicker`) | 214 |
| `Views/Settings/Backup/BackupHubView.swift` | màn gốc Sao lưu & Khôi phục | 187 |
| `Views/Settings/Backup/BackupScopeToggleList.swift` | toggle nhóm + dung lượng ước tính | 94 |
| `Views/Settings/Backup/LocalBackupListView.swift` | danh sách file backup trong app | 134 |
| `Views/Settings/Backup/GoogleDriveBackupListView.swift` | danh sách file trên Drive + đăng nhập | 168 |
| `Views/Settings/Backup/RestoreOptionsSheet.swift` | tóm tắt manifest + chọn nhóm khôi phục | 108 |
| `Views/Settings/Main/BackupSettingsSection.swift` | section "Sao Lưu & Khôi Phục" trong Cài đặt | 12 |
| `Views/Settings/Main/TTSSettingsSection.swift` | section "Nghe Truyện (TTS)" trích từ `SettingsView` | 24 |
* Tổng file Swift 244 → **277** (+33). Không file nào bị xoá, đổi tên hay đổi thư mục.
* File sửa nội dung: `SettingsView.swift` 453 → **439** (−14: mục TTS chuyển sang `TTSSettingsSection`, thêm `BackupSettingsSection`), `RepositoryManagerView.swift` 751 → **709** (−42: `syncExtensions` chỉ còn snapshot → builder → batch upsert), `BookDetailView.swift` 1213 → **1181** (−32: `ellipsisMenu` chuyển sang file `+Extensions`), `BookDetailView+Extensions.swift` 285 → **343** (+58: `ellipsisMenu` + item "Sửa thông tin truyện"), `ExtensionTransactionCoordinator.swift` → **174** (thêm `upsertExtensions` + helper `apply` dùng chung), `BookTransactionCoordinator.swift` → **239** (thêm `updateBookInfo`), `ImageCacheManager.swift` → **204** (thêm `saveCover` + `downscaled`).
* Quan hệ mới: `Views/Settings/Backup/**` → `BackupCoordinator` → `BackupExportWorker` / `BackupRestoreWorker` / `LocalBackupStore` / `GoogleDrive*`; `BackupLibraryWriter` → `BookTransactionCoordinator` + `ExtensionTransactionCoordinator`; `BackupChapterRestorer` → `ChapterStore` + `BookBinManager`; `BackupDictionaryRestorer` → `DictionaryTextFileStore` + `TranslationManager`; `RepositoryManagerView` → `ExtensionSyncCommandBuilder`.
* [BackupZipArchive.swift:1](../../Sources/Services/Backup/BackupZipArchive.swift#L1) là consumer ZIPFoundation thứ hai của repo (sau `ExtensionManager.swift`) và chỉ dùng `FileManager.zipItem/unzipItem`: `Archive.init` đổi chữ ký giữa các bản 0.9.x mà `Package.resolved` không được commit, nên mọi lời gọi thư viện gói trong đúng một file để sửa nhanh nếu CI resolve bản khác.
* `project.yml` **có sửa** lần này: thêm khoá Info.plist `GOOGLE_DRIVE_CLIENT_ID: "$(GOOGLE_DRIVE_CLIENT_ID)"` ([project.yml:54](../../project.yml#L54)). Danh sách file vẫn tự nhặt vì target khai `sources: - path: Sources` theo thư mục.
* Không build được để xác minh biên dịch: host là Windows, `xcodebuild` chỉ chạy trên macOS.

## Tìm kiếm truyện đích, copy VP/Name, widget trình duyệt kéo được (1.3.244)

| File mới | Vai trò | Dòng |
|---|---|---|
| `Views/Common/BookSearchBarView.swift` | thanh tìm kiếm dùng chung (trích từ `ShelfSearchView`) | 41 |
| `Views/Common/FloatingWidgetGeometry.swift` | hình học kẹp/snap cạnh dùng chung cho hai widget nổi | 39 |
| `Views/Common/VisibleBrowserPulseMonitor.swift` | nguồn duy nhất của cờ nháy widget trình duyệt (ngưỡng 10 s) | 72 |
| `Views/Common/BrowserFloatingWidgetUIWindow.swift` | `UIWindow` overlay + `hitTest` của widget trình duyệt | 26 |
| `Views/Common/BrowserFloatingWidgetContainerViewController.swift` | pan/tap + layout frame trực tiếp của widget trình duyệt | 197 |
| `Views/Common/BrowserFloatingWidgetWindowManager.swift` | điều phối hiện/ẩn window, re-parent scene | 121 |
| `Views/Dictionary/DictionaryTransferTarget.swift` | enum đích copy (`globalCustom` / `privateBook`) | 12 |
| `Views/Dictionary/DictionaryEntryTransferAction.swift` | thực thi copy cho cả 8 tổ hợp nguồn→đích | 47 |
| `Views/Dictionary/DictionaryEntryRow.swift` | một hàng từ điển + 3 icon `[Sửa] [Chuyển] [Xóa]` | 119 |
| `Views/Dictionary/DictionaryListView+Transfer.swift` | keo dán giữa row và action (context bookId, toast) | 41 |
| `Services/Extensions/Engine/VisibleBrowserSettings.swift` | khoá + getter `UserDefaults` cho cài đặt mở thu nhỏ | 13 |
| `Views/Settings/Main/BrowserSettingsSection.swift` | section "Trình Duyệt Hiển Thị" trong Cài đặt | 22 |

* Tổng file Swift 232 → **244**. Không file nào bị xoá, đổi tên hay đổi thư mục.
* File sửa nội dung: `DictionaryListView.swift` 767 → **748** (−19: hàng inline chuyển sang `DictionaryEntryRow`), `BookShareTargetSheet.swift` 77 → 100, `DictionaryHubView.swift` 116 (truyền `contextBookId`), `ShelfSearchView.swift` 242 → 218 (dùng `BookSearchBarView`), `VisibleBrowserTabManager.swift` 234 → 263, `VisibleBrowserTabItem.swift` 18 → 28 (thêm `createdAt`), `VisibleBrowserReopenView.swift` 136 → 51, `VisibleBrowserReopenViewModel.swift` 48 → 61, `FloatingWidgetViewModel.swift` 101 → 108, `FloatingWidgetContainerViewController.swift` 240 → 246, `FreeBookApp.swift` 103 (đổi chỗ, không đổi số dòng), `SettingsView.swift` **453 dòng không đổi**.
* `Views/Common/SizeReader.swift` (17 dòng) nay **không còn consumer** trong `Sources/`: consumer duy nhất là viên pill SwiftUI cũ trong `VisibleBrowserReopenView.swift`. File được giữ nguyên vì xoá nó nằm ngoài phạm vi yêu cầu.
* `project.yml` không cần sửa: target khai `sources: - path: Sources` theo thư mục nên `xcodegen generate` tự nhặt 12 file mới.

## Thêm relay quan sát view model của Reader (1.3.243)

| File mới | Vai trò | Dòng |
|---|---|---|
| `Views/Reader/Components/ReaderViewModelInvalidationRelay.swift` | forward `ReaderViewModel.objectWillChange` → `ReaderView` | 40 |

* Consumer duy nhất: `ReaderView.swift` (`@StateObject viewModelObserver`, gọi `observe(_:)` ở `ensureViewModel` và `.onDisappear`). Không file nào khác import/khởi tạo type này.
* Tổng file Swift 231 → **232**. Không file nào bị xoá, đổi tên hay đổi thư mục.

## Tách `ReaderEnergyDiagnostics` khỏi `ReaderTextView` (1.3.239)

| File mới | Tách khỏi | Dòng |
|---|---|---|
| `Views/Reader/Components/ReaderEnergyDiagnostics.swift` | `ReaderTextView.swift` | 258 |

* Tổng file Swift: **230 → 231**. `ReaderTextView.swift` 647 → **450** (−197): phần đo đếm năng lượng chuyển hẳn sang file mới, phần còn lại là bridge UIKit thuần.
* `ReaderEnergyDiagnostics.swift` — *Uses*: `AppLogger` (`isLoggingEnabled` + `log`), `ProcessInfo`, `UIApplication`. *Used by*: `ReaderView.swift` (`beginReaderSession` + 3 `flush`), `ReaderTextView.swift` (6 điểm `record*`), `ReaderView+LoadingView.swift` (2), `ReaderScrollCoordinator.swift` (2), `ParagraphTracker.swift` (2). Quan hệ *uses/used by* không đổi so với khi type còn nằm trong `ReaderTextView.swift` — chỉ dịch chuyển khai báo, `import UIKit` thay cho `import SwiftUI` của file gốc.
* File sửa nội dung, không đổi quan hệ import: `ReaderView.swift` 2250 → 2248 (xoá `@State translationRefreshToken` + call site), `ParagraphCardView.swift` 102 → 101 (xoá tham số cùng tên khỏi struct và khỏi `==`), `ParagraphTracker.swift` 90 → 94 (chỉ thêm comment), `ReaderView+Controls.swift` 161 (đổi thân `completeReaderPositionRestore`).
* `project.yml` không cần sửa: target khai `sources: - path: Sources` theo thư mục nên `xcodegen generate` tự nhặt file mới.

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
  - `Services/ChapterText/`: `PrefetchManager.swift`, `ReaderChapterListStore.swift`, `Coordinators/ChapterListSearchCoordinator.swift`, `Workers/BackgroundPagingWorker.swift`, `BackgroundSearchWorker.swift`, `ReaderChapterListPageFetcher.swift`, `ChapterStore/ChapterTOCDiff.swift` (hàm thuần, không phụ thuộc sqlite — `ChapterStoreDatabase.swift` gọi vào để chọn `.unchanged`/`.appendOnly`/`.full`).
  - `Services/ReadingProgress/`: `ReaderProgressScheduler.swift`.
  - `Services/TTS/`: `TTSManager.swift`, `TTSAudioEngineController.swift`, `TTSAudioSessionController.swift`, `Events/TTSPresentationEventCenter.swift`, `Events/TTSPresentationEvent.swift`, `Extensions/TTSManager+*.swift`. `DisplayTextFormatter.swift` nằm ở `Common/Extensions/DisplayTextFormatter.swift`, không phải trong `Services/TTS/`.
  - `Services/Download/`: `DownloadManager.swift`, `DownloadManager+TaskStore.swift` (CRUD/tiến độ của `DownloadTaskModel`, giữ một `ModelContext` dùng lại), `DownloadTaskOutcomeCalculator.swift` (chính sách `completed`/`failed` + dòng tổng kết bản xuất thiếu chương), `Events/DownloadPresentationEventCenter.swift`, `Events/DownloadPresentationEvent.swift`.
  - `Services/Export/`: `BookExportRequest.swift` (DTO bất biến), `BookExportFormat.swift`, `ExportRenderer.swift` (protocol `append`/`finish`/`discard`), `ExportRendererFactory.swift`, `ExportContentProvider.swift` (lấy chương — dùng chung cho cả tác vụ tải), `ExportChapterPayload.swift`, `ExportArtifact.swift`, `ExportStage.swift`, `ExportRenderError.swift`, `ExportFileNaming.swift`, `ExportStagingFile.swift` (`.part` rồi rename), `ExportParagraphSplitter.swift`, `ExportTextEscaper.swift`, `TxtExportRenderer.swift`, `EpubExportRenderer.swift` + `ZipStoreWriter.swift`, `Fb2ExportRenderer.swift`, `MobiExportRenderer.swift` + `MobiHeaderBuilder.swift` + `BigEndianBytes.swift`. Phân hệ chỉ sinh file trong `Documents/Exports/`, không mở share sheet (`Sources/Views/Common/ExportShareCoordinator.swift` lo việc đó).
  - `Services/Import/`: `BookImportService.swift` (điểm vào duy nhất), `BookImportFormat.swift`, `ParsedBook.swift`, `ParserChapter.swift`, `ChapterLengthLimiter.swift` (hậu xử lý chung, chạy trong phần đuôi của `BookImportService.parse`), `TxtBookParser.swift`, `XhtmlTextExtractor.swift`, `HtmlBookParser.swift`, `EpubArchiveReader.swift`, `EpubOpfParser.swift`, `EpubNavParser.swift`, `EpubBookParser.swift`, `MobiArchiveReader.swift`, `PalmDocDecompressor.swift`, `MobiBookParser.swift`, `DocxArchiveReader.swift`, `DocxBookParser.swift`, `Fb2BookParser.swift`, `PdfDocumentReader.swift`, `PdfBookParser.swift`. Phân hệ chỉ sinh `ParsedBook`, không sở hữu lưu trữ.
  - `Services/Translation/`: `Utils/TranslateUtils.swift`, `Extensions/TranslateUtils+Tokenization.swift`, `Engine/VietPhraseTokenizer.swift`, `Utils/TOCRuleSaveCoordinator.swift`.
- **Views**:
  - `Views/BookDetail/`: `BookDetailView.swift`, `Extensions/BookDetailView+Extensions.swift`, `BookDetailView+TOCPreparation.swift`.
  - `Views/Reader/`: `ReaderView.swift`, `ReaderViewModel.swift`, `ReaderChapterListView.swift`, `Coordinators/ReaderScrollCoordinator.swift`, `ReaderSelectionCoordinator.swift`, `Extensions/ReaderView+Controls.swift`, `ReaderView+LoadingView.swift`, `ReaderView+Suggestions.swift`, `ReaderViewModel+Translation.swift`.
  - `Views/Extensions/`: `Manager/RepositoryManagerView.swift`, `Extensions/RepositoryManagerView+Actions.swift`, `RepositoryManagerView+RepoOps.swift`.
  - `Views/Shelf/`: `ShelfMain/ShelfView.swift`, `ShelfMain/Extensions/ShelfView+BookImport.swift` (nhập truyện từ file TXT/HTML/EPUB/MOBI–AZW3/PRC/DOCX/FB2/PDF; đọc/ghi `@State` của `ShelfView` nên chúng phải `internal`, không `private`), `ShelfMain/BookImportConfirmationSheet.swift` + `ShelfMain/Extensions/BookImportConfirmationSheet+Pickers.swift`. Logic bóc tách nằm ở `Services/Import/`.
  - `Views/Search/`: `SearchView.swift`.
  - `Views/Discovery/`: `DiscoveryView.swift`.
  - `Views/Common/`: `VisibleBrowserReopenView.swift`.
<!-- GENERATED END -->
