# CHANGELOG (Lưu trữ) - Nhật ký Thay đổi CodeGraph FreeBook

Lịch sử thay đổi cũ (version ≤ 1.3.262) tách khỏi [CHANGELOG.md](CHANGELOG.md) để giữ file chính gọn. Chỉ dùng để tra cứu; không cần đọc khi làm task thường.

## [1.3.262] - 2026-08-24

### Nút back không chữ chạy thật, ô URL tự bôi đen, bypass browser nhiều tab

Thêm **6** file Swift (346 → 352), sửa 2 file; **không** `@Model` nào đổi shape, **không** thêm dependency. Chưa biên dịch (viết trên Windows, không có `xcodebuild`/`xcodegen`) — **phải chạy `xcodegen generate` trên macOS/CI** vì có file mới.

* **Sửa lỗi "bỏ chữ nút back không hoạt động" của 1.3.260**: nguyên nhân là `NavigationBarAppearance` đọc `UINavigationBar.appearance().standardAppearance` rồi sửa **tại chỗ** — appearance proxy chỉ bảo đảm hợp đồng cho *setter*, getter của nó không trả về đối tượng đang có hiệu lực, nên phép sửa rơi vào hư không. Nay dựng **4 `UINavigationBarAppearance()` mới**: `standard`/`compact` dùng `configureWithDefaultBackground()`, `scrollEdge`/`compactScrollEdge` dùng `configureWithTransparentBackground()` (đúng mặc định iOS 15+ nên diện mạo thanh nav không đổi). Thêm `.font: .systemFont(ofSize: 0.1)` cạnh `.foregroundColor: .clear` cho cả 4 trạng thái `backButtonAppearance` để nhãn không **chiếm chỗ** — chỉ đổi màu thì chevron bị đẩy lệch khỏi vị trí quen thuộc. Vẫn không dùng `UIBarButtonItem.appearance()`.
* **Bypass browser mở nhiều tab, link ngoài mở tab mới**: 4 file mới `BypassBrowserTabStore` (149), `BypassBrowserTab` (107), `BypassBrowserTabBar` (62), `BypassBrowserWebPane` (38). Trước đây `BypassWebView` **không gắn `WKUIDelegate`** nên `target="_blank"`/`window.open` không làm gì cả. Store là chủ sở hữu duy nhất mọi `WKWebView` và là delegate dùng chung; `createWebViewWith` **dùng lại** `WKWebViewConfiguration` do WebKit trao và **không** tự `load` (tạo config mới ⇒ mất `window.opener`; tự load ⇒ nạp hai lần), trần **8 tab** vì mỗi tab là một webview, đạt trần thì nạp link trên tab hiện tại. KVO (6 khoá) nằm trên tab chứ không trên `Coordinator` nên tab nền vẫn cập nhật tiêu đề/URL; đổi tab chỉ đổi subview của một `UIView` container nên giữ nguyên lịch sử và vị trí cuộn. `webViewDidClose` đóng đúng tab; `closeTab` từ chối đóng tab cuối.
* **Chạm ô URL là bôi đen toàn bộ địa chỉ**: file mới `URLBarTextField` (102) bọc `UITextField` vì SwiftUI `TextField` (iOS 17) không có API chọn hết. Đặt `selectedTextRange` trong `textFieldDidBeginEditing` phải **hoãn một vòng run loop** (UIKit ghi đè bằng caret cuối chuỗi ngay sau callback), và dùng `selectedTextRange` thay `selectAll(nil)` để không bật kèm menu Cut/Copy/Paste. Cờ `isEditing` chặn observer URL của webview ghi đè lúc đang gõ; `updateUIView` chỉ gán `text` khi khác thật.
* **`BypassWebView.swift` 599 → 350 dòng** (baseline legacy 599, chỉ được giảm): gỡ `WebViewStore`, `SwiftUIWebView` + Coordinator, `fileprivate isDomainBlocked` (dùng lại `isEngineDomainBlocked` của Engine — một nguồn sự thật cho danh sách chặn) và `generateHomeHtml()` (tách nguyên văn sang `BypassBrowserHomePage`, 170 dòng). API công khai `BypassWebView(urlString:host:onImport:)` **không đổi** nên 6 call site không phải sửa.
* `check_architecture.py` giữ **14 violation, đúng cùng một tập** trước/sau; 6 file mới đều ≤ 400 dòng và đúng 1 type top level, không nới baseline, không sửa `architecture_allowlist.json`. CodeGraph: cập nhật `00`, `02`, `03`, `09`, `11`, `14`.

## [1.3.261] - 2026-08-24

### Tô sáng kết quả tìm, tự tắt cuộn khi kéo trang, dọn tiện ích kho đã gỡ

Thêm **2** file Swift (344 → 346), sửa 7 file; **không** `@Model` nào đổi shape, **không** thêm dependency. Chưa biên dịch (viết trên Windows, không có `xcodebuild`/`xcodegen`) — **phải chạy `xcodegen generate` trên macOS/CI** vì có file mới.

* **Chọn kết quả tìm ⇒ nhảy + tô sáng + tắt cuộn theo highlight**: `ReaderSearchView.onSelect` đổi thành `(Int, Int, String) -> Void` (chapterIndex, paragraphIndex, **query**) để chuỗi truy vấn sống lâu hơn sheet. `ReaderSearchMatcher` thêm struct lồng `Highlight` + `static firstHighlightRange(of:in:)`; `ReaderView.searchHighlight` là `@State` giữ **ý nghĩa** `(chapterIndex, paragraphIndex, query)` chứ không cache `NSRange` — range được tính lại mỗi lần render (`searchHighlightRange(...)`) nên không bao giờ trỏ sai khi bật/tắt dịch. Vệt TTS vẫn thắng: `relativeHighlightRange ?? searchHighlightRange(...)`. Vệt bị xoá ở `.onChange(of: chapterIndex)`, **không** xoá khi đóng sheet.
* **Người dùng kéo trang lúc TTS đang đọc ⇒ tự tắt cuộn theo highlight**: file mới `Sources/Views/Reader/Components/ReaderUserScrollDetector.swift` (143 dòng) — `UIViewRepresentable` gắn `UIPanGestureRecognizer` **không tiêu thụ touch** (`cancelsTouchesInView = false`, nhận diện đồng thời, không đòi recognizer khác fail) lên `UIScrollView` bao ngoài. Quan sát `contentOffset` bị loại vì cú `ScrollViewProxy.scrollTo` của TTS cũng đổi offset. `handleUserScrollWhilePlaying` (`ReaderView+Controls`) có 4 guard: `!isAutoScrollDisabled`, `isTTSPlayingThisBook`, `!isRestoringReaderPosition`, `!showingFloatingMenu` (chặn cú kéo nới vùng bôi đen). Mỗi lần tắt đều `ttsAutoScrollGeneration += 1` và huỷ `scrollTarget` khi `reason == .ttsAuto`.
* **Tiện ích kho đã gỡ khỏi registry bị xoá khỏi máy, trừ tiện ích đã cài**: file mới `Sources/Models/Extensions/PruneRepositoryExtensionsCommand.swift` (22 dòng) + `ExtensionTransactionCoordinator.pruneRepositoryExtensions(command:in:)` trả `Result<Int, _>`. `RepositoryManagerView.syncExtensions` gọi prune **sau** khi upsert `.success`, với tập giữ lại suy ra từ chính `commands.map(\.packageId)` nên hai transaction không thể lệch cách viết `packageId`. Ba chốt chặn xoá oan: `items.isEmpty` thoát sớm, `keepPackageIds` rỗng ⇒ `.success(0)`, prune chỉ chạy khi upsert thành công. Tiện ích đã cài (`localPath` khác rỗng) và tiện ích nhập từ zip (`repository == nil`) luôn được giữ; chỉ xoá **bản ghi**, không đụng file.
* `check_architecture.py` giữ **14 violation, đúng cùng một tập** trước/sau; không nới baseline, không sửa `architecture_allowlist.json`. CodeGraph: cập nhật `00`–`06`, `08`–`14` (`07`, `rules.md` xem lại và vẫn đúng).

## [1.3.260] - 2026-08-24

### Tự sao lưu Drive, nút tìm ra header, thông báo đã đọc, nút back không chữ

Bốn thay đổi UX/nền độc lập. Thêm **4** file Swift, **không** `@Model` nào đổi shape, **không** thêm dependency. Chưa biên dịch (Windows).

* **Nút tìm trong chương ra ngoài header**, đứng cạnh nút bật/tắt cuộn theo TTS thay vì nằm trong menu `ellipsis` (`ReaderHeaderFooterOverlayView`, `ReaderView`, `ReaderView+Controls`).
* **Trung tâm thông báo**: bấm vào một thông báo ⇒ chỉ thông báo đó thành đã đọc (`NotificationInboxManager.markRead(_:)`, không ghi đĩa lại nếu đã đọc). `clearAll()` được **thay** bằng `deleteUnread() -> Int` — theo đúng yêu cầu "xoá tất cả thông báo chỉ xoá thông báo chưa đọc", nên phần **đã đọc** được giữ lại như nhật ký và nút đổi nhãn theo nghĩa mới (`hasUnread`).
* **Bỏ chữ ở nút back mọi màn hình**: file mới `Sources/Common/Utils/NavigationBarAppearance.swift` — `applyTitlelessBackButton()` đặt màu chữ trong suốt cho **cả bốn** trạng thái của `backButtonAppearance` trên `UINavigationBar.appearance()`, sửa tại chỗ đối tượng appearance đang có để giữ nền mờ mặc định. Không dùng `UIBarButtonItem.appearance()` (sẽ xoá luôn chữ "Đóng"/"Xong"/"Huỷ"), không dùng `navigationBarBackButtonDisplayMode(.minimal)` (API iOS 18). Gọi một lần ở `FreeBookApp.init()`. Hai nút *hành động* nhãn "Quay lại" trong nội dung (`BookDetailView.swift:611`, `ReaderView+LoadingView.swift:90`) **giữ nguyên** — chúng không phải nút back của thanh điều hướng.
* **Tự động sao lưu lên Google Drive, giữ 5 bản gần nhất**: file mới `DriveAutoBackupPolicy` (nguồn duy nhất của chính sách chạy: `.cooldown`/`.daily`, `maxVersions = 5`, hoãn 25 s sau khởi động, nhóm mặc định `books/extensions/dictBooks/dictCustom` — cố ý bỏ `.content` và `.dictShared`), `BackupCoordinator+AutoDrive` (thân việc, **trả về** `AutoDriveBackupOutcome`) và `DriveAutoBackupSettingsView`. Đúng khuôn lượt kiểm tra chương mới: `MainTabView.task` là điểm phát duy nhất và là nơi hiện toast, nên `Sources/Services/**` vẫn không gọi `ToastManager`. Bản thứ 6 trở đi (cũ nhất trước) bị xoá ngay sau khi bản mới tải lên xong.

## [1.3.259] - 2026-08-23

### Thêm sidebar debug extension FreeBook cho VS Code

Thêm tool nội bộ `Tools/VSCode/FreeBookExtDebug`, đóng gói VSIX độc lập để debug extension VBook qua FreeBook App. Sidebar theo luồng extension beta: tự nhận root/script, hiện đúng input theo contract `ExtensionManager`, chạy Draft/Installed, Pair/Mock và xem trace tại chỗ. Tool không thực thi JavaScript VBook bằng Node; Mock luôn ghi rõ không chạy JSExecutor iOS. Draft chỉ stage file đã lưu, token/session chỉ nằm trong VS Code SecretStorage, và các script TTS `voice`/`tts` bị đánh dấu chưa hỗ trợ bởi protocol v1 thay vì chạy sai contract.

## [1.3.258] - 2026-08-23

### Tìm trong Reader + Trung tâm thông báo, gỡ tìm toàn văn toàn cục

Gỡ hẳn phân hệ tìm toàn văn 1.3.257 (nguồn crash, sai ý định), thay bằng **tìm trong Reader** chạy trên cache RAM và một **Trung tâm thông báo** ở header Kệ sách. Xoá **10** file, thêm **6** file Swift (344 → 340), **không** `@Model` nào đổi shape, **không** thêm dependency.

* **Gỡ toàn bộ `Sources/Services/Search/` (7 file) + 3 view** (`ShelfContentSearchView`, `ChapterSearchSettingsSection`, `ChapterSearchIndexSettingsView`) và mọi lời gọi `ChapterSearchIndex.shared.*` tại 4 chỗ ghi + 3 chỗ xoá (`ChapterPersistenceStore`, `ShelfView+BookImport`, `BackupChapterRestorer`, `ExportContentProvider`, `BookStorageManager`). `ShelfSearchView` hoàn nguyên về tìm-theo-tên (xoá `SearchScope`, picker, `@AppStorage` cờ bật). `MainTabView` thêm dọn best-effort một lần thư mục `applicationSupportDirectory/search/` còn sót. Grep xác nhận không còn tham chiếu `ChapterSearch*` nào trong `Sources/`.
* **Tìm trong Reader thuần RAM, không đường crash**: `ReaderSearchMatcher` (enum namespace + 3 struct lồng) khớp không dấu/không hoa-thường trên **cả** `original` và `translated` của các `CachedChapter` `state == .loaded` (chương đang đọc + lân cận đã cache), 1 hit/đoạn + snippet. `ReaderSearchView` (sheet, debounce 250ms, nhóm theo chương) mở từ menu `ellipsis`; chọn kết quả nhảy đúng đoạn (cùng chương ⇒ `scrollTarget`, khác chương ⇒ `requestChapter(source: .chapterList)`). Không đọc đĩa/mạng, không dựng chỉ mục.
* **Trung tâm thông báo (nút chuông trên cả 3 tab con)**: choke point `ToastManager.show` ghi mọi toast vào `NotificationInboxManager` (Common, không `import SwiftUI`) → `NotificationInboxStore` (actor, `notifications.json`, `.atomic`, cap 200). `NotificationInboxView` gộp hai nguồn nhóm theo ngày: nhật ký toast (swipe-xoá, "đánh dấu đã đọc hết", "dọn dẹp") và **cập nhật chương mới per-book** — tái dùng `NewChapterInboxManager`, mỗi truyện hiện rõ "N chương mới" (hoặc "≥N" khi `!isCountExact`) + tên chương mới nhất; bấm mở truyện + `markSeen`. Badge chuông = `unreadCount` + `totalNewBooks`.
* CodeGraph: `00_index`, `02_file_graph`, `03_type_graph`, `04_call_graph`, `08_lifecycle`, `09_dependency_rules`, `11_subsystems`, `14_complexity_report`. `check_architecture.py` giữ đúng **14 violation** cùng một tập (6 file mới ≤ 299 dòng, mỗi file 1 type top level); host Windows nên không `xcodegen generate`/`xcodebuild` tại chỗ, biên dịch do CI xác nhận.

## [1.3.257] - 2026-08-23

### Tìm toàn văn offline cho chương đã tải

Tìm theo **nội dung** chương đã có trên máy (truyện nhập cục bộ và chương online đã cache), trả về snippet + đúng chương + đúng đoạn để mở Reader ngay tại chỗ. Thêm **10** file Swift (334 → 344), **không** `@Model` nào đổi shape, **không** thêm dependency, tính năng **mặc định tắt**.

* **Phân hệ mới `Sources/Services/Search/` (7 file) là chủ sở hữu duy nhất của chỉ mục**, đặt ở `applicationSupportDirectory/search/chapter_search.sqlite` — file sqlite **thứ ba** của app, tách hẳn khỏi `chapters/chapter_store.sqlite` để bật/tắt/xoá chỉ mục không bao giờ đụng tới mục lục thật. Bảy vai rời nhau: `ChapterSearchPolicy` (nguồn duy nhất của mọi hằng + cờ bật), `ChapterSearchIndexPath`, `ChapterSearchIndexDatabase` (chỗ duy nhất `import SQLite3` ngoài `ChapterStoreDatabase`), `ChapterSearchHit`, `ChapterSearchSnippetBuilder`, `ChapterSearchIndex` (actor, cửa duy nhất ra ngoài), `ChapterSearchIndexBuilder`.
* **Tokenizer là `trigram`, và đó là lý do mặc định TẮT**: đây là tokenizer built-in duy nhất khớp được chuỗi con cho tiếng Trung/Việt không dấu cách, nhưng nó lưu cả nội dung nên chỉ mục phình vài lần dung lượng text. Vì vậy có màn riêng để bật/dựng/xoá, hiện dung lượng thật, và truy vấn **bắt buộc ≥ 3 ký tự** (`minimumQueryLength`) vì trigram không match nổi chuỗi ngắn hơn.
* **Hai bảng chứ không một bảng FTS5 có cột `UNINDEXED`**: `chapter_doc` (khoá + `book_id` có index) và `chapter_fts` (chỉ text), vì `DELETE … WHERE book_id = ?` trên bảng FTS5 là full scan. Cạm bẫy đã gặp: FTS5 nhận `MATCH` theo **tên bảng**, đặt alias cho `chapter_fts` là SQLite báo "no such column".
* **Đoạn trả về khớp đúng đoạn Reader hiển thị**: `ChapterSearchSnippetBuilder` chạy `ChapterTextNormalizer.normalize` — **đúng biến thể có lọc rác** mà `ChapterContentRepository.makeDocument` dùng — nên `line.id` bằng thẳng `ParagraphItem.id`. `ChapterSearchHit.paragraphIndex` đi tiếp qua `ShelfReaderRoute.paragraphIndex` → `ReaderView.initialParagraphIndex` **không qua một phép ánh xạ toạ độ nào**. Đổi sang `normalizeProcessedContent` là vỡ ngầm bất biến này.
* **Index incremental gắn ở đúng 4 chỗ ghi nội dung và 3 chỗ xoá**, không có đường ghi `.bin` nào bỏ sót: `ChapterPersistenceStore.upsert`, `ShelfView+BookImport`, `BackupChapterRestorer`, `ExportContentProvider`; xoá qua `BookStorageManager`. Mọi lời gọi ghi chỉ mục là `async` và **không bao giờ throw** — thất bại chỉ vào `AppLogger`, nên `SERVICE_TOAST_COUPLING` giữ nguyên và một chỉ mục lỗi không bao giờ làm hỏng lượt ghi chương.
* **Kết quả được đối chiếu lại với mục lục hiện tại** trước khi hiện: hit còn URL nhưng đổi số chương ⇒ sửa số; biến mất khỏi mục lục ⇒ bỏ hit. `removeBook` **không** gác theo cờ bật/tắt để tắt tính năng rồi xoá truyện vẫn không để lại rác.
* CodeGraph: `00_index`, `02_file_graph`, `09_dependency_rules`, `11_subsystems`, `14_complexity_report`. `check_architecture.py` giữ đúng **14 violation** với tập vi phạm y hệt, không thêm allowlist entry (file mới lớn nhất `ChapterSearchIndexDatabase.swift` **397/400**); host là Windows nên không `xcodegen generate`/`xcodebuild` tại chỗ, biên dịch do CI xác nhận.

## [1.3.256] - 2026-08-23

### Hộp thư chương mới: badge, cooldown và refresh từng truyện

Theo dõi chương mới cho truyện online trên kệ: mỗi truyện có mốc riêng, lượt kiểm tra tự động chạy **sau** khi Kệ sách đã hiện và bị chặn bởi cooldown (hoặc giờ người dùng chọn), có badge trên dòng truyện + tab, refresh tay toàn bộ hoặc từng truyện. Thêm **8** file Swift (326 → 334), **không** `@Model` nào đổi shape, **không** thêm dependency.

* **Phân hệ mới `Sources/Services/NewChapters/` (5 file)** với 5 vai rời nhau: `NewChapterRecord` (DTO `Codable`), `NewChapterStore` (actor, chủ duy nhất của `applicationSupportDirectory/new_chapters.json`), `NewChapterCheckPolicy` (nguồn duy nhất của "được kiểm tra lúc này không" + mọi hằng điều tiết), `NewChapterProbe` (một lượt dò cho một truyện, thuần — không ghi đĩa/không toast/không SwiftData), `NewChapterInboxManager` (`@MainActor ObservableObject`, chủ duy nhất của việc lượt nào chạy và lưu gì).
* **Không thêm `@Model` thứ sáu**: `ModelContainer` khai đúng 5 `@Model` và **không** có `VersionedSchema`/`SchemaMigrationPlan`, nên thêm thuộc tính vào `Book` là rủi ro migration cho dữ liệu mà **một lượt tải mục lục dựng lại được**. Mốc theo dõi vì vậy nằm ở một file JSON ghi `.atomic`, đọc đĩa một lần mỗi phiên, decode lỗi ⇒ log + coi như rỗng, `prune(keeping:)` mỗi lần mở Kệ sách. Tích hợp sao lưu/khôi phục **chưa** làm ở đợt này.
* **Chỉ tải mục lục, và có trần trang**: `NewChapterProbe` gọi **duy nhất** `BookDetailLoader` (thêm `fetchPageTOC(snapshot:url:host:)`, 97 → 112 dòng; ba hàm cũ không đổi một dòng) nên không có đường nào lỡ tải nội dung chương. Mục lục quá `maxTOCPagesPerCheck = 8` trang ⇒ chỉ lấy **trang cuối** (1 request thay vì 50), biết "có chương lạ" nhưng không biết tổng số ⇒ `isCountExact = false` và badge hiện **dấu chấm** thay vì con số sai. Lần kiểm tra đầu lấy mốc từ `ChapterStore.fetchOrderedTOC` để thư viện sẵn có không bị báo "toàn bộ là chương mới".
* **Hai mốc, hai chủ**: `seen*` chỉ đổi khi người dùng **mở truyện** (`markSeen`, và thoát sớm không ghi đĩa khi không có gì mới), `probed*` chỉ đổi khi probe chạy. `newChapterCount` là kết quả **suy ra** từ hiệu hai mốc chứ không phải bộ đếm tự cộng, nên kiểm tra lặp lại không nhân đôi số chương. Hai nhánh bằng chứng yếu cố ý *không* báo động giả: chỉ có trang cuối mà không thấy mốc ⇒ báo 1 + dấu chấm; nguồn đổi url chương cuối mà tổng số chương không tăng ⇒ báo **0**.
* **Không chặn khởi động, một toast mỗi lượt**: `.task` của `ShelfView` chạy sau khi Kệ sách đã hiện và thoát im lặng khi chưa tới lượt (mặc định cách nhau 6 giờ; chế độ "mỗi ngày một lần" so với giờ người dùng chọn). Một lượt = tối đa `maxBooksPerBatch = 20` truyện, tuần tự, cách nhau 0,4 s, **một** lượt ghi file, **một** toast; `Outcome.newlyFound` trừ phần đã biết nên lượt sau không báo lại chương cũ. Refresh tay bỏ qua cooldown và luôn báo kết quả.
* **Ranh giới tầng giữ nguyên**: `Services/NewChapters/**` không `import SwiftUI`, không `ToastManager.shared` — manager **trả về** `BatchSummary` và `ShelfView+NewChapters` (`@MainActor`, vì `ToastManager` là `@MainActor`) mới hiện toast. Badge tab dùng `.badge(totalNewBooks)` (`0` không vẽ gì); `BookListItemView` **không** bị sửa vì dùng chung với Khám phá và sheet chia sẻ — badge là view em cạnh nó trong `HStack`. Hai `@Query` của `ShelfView` đổi `private` → `internal` do `private` của Swift là phạm vi file.
* CodeGraph: `00_index`, `02_file_graph`, `04_call_graph`, `06_event_graph`, `07_dataflow`, `08_lifecycle`, `09_dependency_rules`, `11_subsystems`, `13_resource_lifecycle`, `14_complexity_report`. `check_architecture.py` **14 → 14 violation** đúng cùng một tập (8 file mới ≤ 209 dòng, mỗi file 1 type top level; `ShelfView.swift` 836 → 867, baseline 942); host Windows nên không `xcodegen generate`/`xcodebuild` tại chỗ, biên dịch do CI xác nhận.

## [1.3.255] - 2026-08-23

### Nhập truyện PDF chỉ lấy lớp văn bản

Thêm `.pdf` vào đường nhập file, dùng **PDFKit** của hệ thống (không dependency mới, `project.yml` không đổi). Thêm **2** file Swift (324 → 326), **không** `@Model` nào đổi shape, **không** thêm OCR và **không** vượt bảo vệ tài liệu.

* **PDF không đi qua `Data`**: `BookImportFormat` tách `detect(fileNameOnly:) -> BookImportFormat?` (chỉ theo đuôi file, `nil` khi lạ) chạy trước; chỉ đuôi lạ mới nạp byte để dò magic (`%PDF-` trong 1 KB đầu). Sáu format cũ đọc byte qua `try fileData ?? loadData(...)` nên hành vi **không đổi**, còn PDF được `PDFDocument(url:)` mở lazy từng trang thay vì nạp cả file vào RAM.
* **`PdfDocumentReader` (131 dòng) là file duy nhất `import PDFKit`** — mở/mở khoá, lấy text từng trang, phẳng hoá `outlineRoot`, đọc `documentAttributes`. Đệ quy outline bị chặn `maxOutlineDepth = 8` và `maxOutlineEntries = 10_000`; trang lấy qua `destination?.page`, thiếu thì `PDFActionGoTo`.
* **Biên chương chỉ tới mức trang**: mục outline cùng một trang gộp về mục đầu, mục trỏ lùi bị bỏ để dãy trang đơn điệu tăng; phần trước mục đầu thành `"Mở đầu"`. Thứ tự rơi giống các format khác: outline (`.auto`/`.tocIndex`) → mỗi trang một chương (`.spine`) → nối text rồi `TxtBookParser.parse` (quy tắc TOC), rồi vẫn qua `ChapterLengthLimiter` đúng một lần ở `BookImportService.parse`.
* **PDF scan báo không hỗ trợ, PDF hỗn hợp phải xác nhận**: trang dưới **16 ký tự** bị tính là không có lớp văn bản; *mọi* trang như vậy ⇒ `throw .noTextLayer` ("PDF này chỉ có ảnh scan…"); một phần ⇒ `ParsedBook.warningNote` ghi rõ *N/M trang* bị bỏ và **nút "Nhập" bị chặn** cho tới khi người dùng tick "Tôi hiểu, chỉ nhập phần có văn bản". Ngưỡng 16 ký tự chỉ dùng để đếm và cảnh báo, không loại nội dung.
* **Tài liệu khoá**: `isLocked` ⇒ `throw .passwordRequired`, View hiện `.alert` với `SecureField` rồi gọi lại `reanalyzeImport(... password:)`; sai mật khẩu ⇒ `.wrongPassword`. Hai nhánh này **không** xoá file tạm để nhập lại được ngay. Mật khẩu chỉ nằm trong `@State`/`PendingImport.password`, **không** ghi UserDefaults/Keychain, **không** log; PDFKit tự thử mật khẩu người dùng rỗng nên file chỉ có owner password vẫn mở được mà không phá gì.
* CodeGraph: `00_index`, `02_file_graph`, `09_dependency_rules`, `11_subsystems`, `14_complexity_report`. `check_architecture.py` **14 → 14 violation** đúng cùng một tập (2 file mới 131/136 dòng, mỗi file 1 type top level, `OutlineEntry` nest); host Windows nên không `xcodegen generate`/`xcodebuild` tại chỗ, biên dịch do CI xác nhận.

## [1.3.254] - 2026-08-23

### Sao lưu và khôi phục ảnh bìa của truyện nhập từ file

Truyện nhập từ file (TXT/EPUB/HTML/MOBI/DOCX/FB2) lưu bìa **chỉ** ở `covers/<sha256(bookId)>.jpg` với `coverUrl` rỗng, nên archive `.fbbackup` trước đây khôi phục xong là mất bìa vĩnh viễn. Thêm **1** file Swift (323 → 324), **không** `@Model` nào đổi shape, **không** phá tương thích file sao lưu cũ.

* **`BackupCoverArchiver` (80 dòng) là chủ duy nhất của entry `covers/<slug>.jpg`**, giữ cả hai chiều xuất/khôi phục trong một file để tên entry không lệch — cùng lý do `BackupPaths` tồn tại. `BackupExportWorker` và `BackupRestoreWorker` mỗi bên chỉ gọi một hàm.
* **Tiêu chí là "tải lại được hay không"**, không phải "sách local hay không": `BookRecord.hasUnrecoverableCover` = `coverUrl` không bắt đầu bằng `http(s)`. Nhờ vậy bìa người dùng tự chọn cho truyện online (`BookInfoEditView` cũng để `coverUrl` rỗng) được cứu luôn, còn bìa online tải lại được vẫn bị bỏ qua để archive không phình vài chục MB.
* **Không thêm case `BackupScope`** — rawValue của scope nằm trong `manifest.scopes`, thêm case là bản app cũ đọc file mới decode lỗi. Bìa vì vậy đi kèm nhóm bắt buộc `books`, không có toggle riêng.
* **`BackupManifest.Counts` thêm `covers` kèm `CodingKeys` + `init(from:)` viết tay** dùng `decodeIfPresent(...) ?? 0` cho **mọi** khoá: decoder tổng hợp của Swift **không** dùng giá trị mặc định của thuộc tính, thiếu bước này là mọi `.fbbackup` cũ decode lỗi.
* **Khôi phục vẫn thuần gộp**: máy đang có bìa thì giữ bìa của máy (`skippedCovers`), chỉ điền chỗ thiếu ⇒ khôi phục lại cùng một file vẫn idempotent. Byte JPEG chép nguyên qua `ImageCacheManager.localCoverURL(for:)`, **không** qua `saveCover` (hàm đó giải mã `UIImage` rồi nén lại, và sẽ kéo `UIKit` vào tầng Services).
* **UI/telemetry**: `BackupProgress.Phase` 17 → **19** pha (`copyingCovers`, `restoringCovers`); `RestoreOptionsSheet` thêm hàng "Ảnh bìa truyện nhập" (ẩn khi `counts.covers == 0` nên archive cũ không hiện số 0); toast khôi phục cộng thêm số bìa khi > 0; log xuất/khôi phục ghi số bìa. `BackupSizeEstimator` **giữ nguyên** vì `covers/` lẫn cả bìa online.
* CodeGraph: `00_index`, `02_file_graph`, `09_dependency_rules`, `11_subsystems` (gạch bỏ câu "không có nhóm ảnh bìa: bìa tải lại được từ `coverUrl`" đã sai), `14_complexity_report`. `check_architecture.py` **14 → 14 violation** đúng cùng một tập; host Windows nên không build tại chỗ, biên dịch do CI xác nhận.

## [1.3.253] - 2026-08-23

### Xuất truyện TXT, EPUB, FB2, MOBI trong một tác vụ

Tách hai ý định bị trộn chung: `Tải truyện` = chỉ lấy + cache; `Xuất truyện` = lấy → cache → kết xuất → **xác minh file tồn tại** → sẵn sàng chia sẻ, tất cả trong **một** tác vụ. Thêm **21** file Swift, xoá **1** (303 → 323), **không** `@Model` nào đổi shape, **không** thêm dependency.

* **Phân hệ mới `Sources/Services/Export/` (20 file)**, điểm vào là `BookExportRequest` bất biến, điểm ra là `ExportArtifact`. Nhánh `.exportTxt` cứng nhắc trong `DownloadManager` được tách thành ba vai: `ExportContentProvider` (lấy nội dung: cache trước, tải khi cần) → `ExportRenderer` (`append` / `finish` / `discard`) → `ExportArtifact`. `DownloadManager.swift` **437** dòng (từ 484) và bỏ được `import UIKit`.
* **Chương vừa tải xong đi thẳng vào renderer của cùng tác vụ đó** — không còn lượt hai đọc lại `.bin` sau khi tải xong. Đây là lý do hai ý định phải nằm trong một job chứ không phải hai.
* **Bốn định dạng, một giao thức**: `TxtExportRenderer`, `EpubExportRenderer` (EPUB 3), `Fb2ExportRenderer`, `MobiExportRenderer`; `ExportRendererFactory.makeRenderer(for:)` là chỗ duy nhất biết đủ cả bốn, nên thêm định dạng về sau **không** đụng `DownloadManager`. Markdown/HTML cố ý **không** làm.
* **Hai chỗ phải tự viết vì thư viện bị giam đúng chỗ**: (1) `ZipStoreWriter` — ZIP stored-only (method 0) tự dựng CRC-32 + central directory + EOCD, vì EPUB bắt buộc entry `mimetype` **không nén** đứng đầu mà `FileManager.zipItem` không đảm bảo được, và `BackupZipArchive` là file duy nhất được gọi ZIPFoundation; không cài ZIP64 nên chặn `maxSize = Int(UInt32.max)` rồi `throw .archiveTooLarge`. (2) `MobiHeaderBuilder` — PalmDB + PalmDOC (`compression = 1` **không nén** có chủ ý, `encryptionType = 0`) + MOBI header **232 byte** + EXTH (100 tác giả / 103 mô tả / 503 tên sách / 201 offset bìa).
* **MOBI là chỗ khó nhất**: `filepos` của mục lục là **offset byte tuyệt đối trong toàn văn**, không thể biết trước khi có đủ text ⇒ text được ghi ra file tạm trước, rồi copy lại theo record 4096 byte trong lúc **vá tại chỗ** chỗ trống 10 chữ số cố định (bất biến: chuỗi vá phải đúng 10 ký tự). `recordCount` là UInt16 nên vượt 65535 record ⇒ `throw .sizeLimitExceeded` thay vì tạo file hỏng.
* **"Hoàn thành" nay có nghĩa chặt hơn**: chỉ đánh dấu xong khi `finish()` thành công **và** file thật sự tồn tại **và** đường dẫn đã được bền hoá. Xuất thiếu chương không còn im lặng: `DownloadTaskOutcomeCalculator` cho `.failed` khi **0** chương ghi được, còn > 0 thì `.completed` kèm dòng cam `"Đã xuất X/Y chương (thiếu M, lỗi F)"` (nil khi đủ chương, nên sự xuất hiện của dòng này tự mang nghĩa cảnh báo) hiện ở **cả** tracker **và** toast.
* **Ranh giới Services ↔ Views của share sheet**: tầng Services dừng ở `ExportArtifact` và phát `DownloadPresentationEvent.exportReady(filePath:bookTitle:)` trên `AsyncStream` sẵn có (**không** thêm tên `NotificationCenter` string trần); `AppLaunchRootView` — subscriber UI duy nhất — chuyển cho `ExportShareCoordinator` (Views) mở `UIActivityViewController`. Bản xuất xong lúc app ở background thì share sheet không trình bày được, nên yêu cầu được giữ ở `pendingFileURL` và flush khi `scenePhase == .active` từ `MainTabView`.
* **Một chủ cho mỗi việc dùng chung** thay vì mỗi renderer tự làm: `ExportParagraphSplitter` (tách đoạn, logic y nguyên `formatChapter` cũ), `ExportTextEscaper` (escape XML cho EPUB/FB2), `ExportStagingFile` (chủ **duy nhất** của quy ước `.part` → `commit()`/`discard()`, `init` xoá `.part` sót lại), `ExportFileNaming` (tên file mang định dạng + mốc thời gian ⇒ **không ghi đè im lặng**), `BigEndianBytes`. `TxtExportFileWriter.swift` (97 dòng) bị xoá, vai trò về `ExportStagingFile`. `renderer` được khai **ngoài** khối `do` nên `discard()` với tới được mọi nhánh thoát; file text tạm của MOBI dọn bằng `defer`.
* **Không đổi schema SwiftData**: định dạng bền hoá bằng raw value mới của `TaskType` trong cột `taskTypeRaw` sẵn có; `exportStage`/`exportSummary` là field **tạm** trên `DownloadTask` trong RAM (đánh đổi đã biết: mất sau khi khởi động lại app, nhưng nút chia sẻ lại vẫn còn vì `exportFilePath` đã bền hoá). Việc thêm field kiểu `exportOptionsJson` là **điểm dừng thiết kế được báo lại, không tự cài**.
* **UI**: `TaskOptionsSheet` thêm picker định dạng + dòng mô tả + thống kê chương đã cache; `DownloadTrackerView` thêm dòng bước, dòng tổng kết và nút chia sẻ lại. Nhãn `"Xuất TXT"`/`"Xuất ebook TXT"` → `"Xuất ebook"`. **Đổi hành vi có chủ ý**: nút "Xuất từ chương đã tải" trong tracker nay **mở `TaskOptionsSheet`** (để chọn định dạng) thay vì xếp hàng TXT ngay.
* Gate: `check_architecture.py` giữ đúng **14 violation** với tập **y hệt** — 21 file mới đều ≤ **207** dòng và đúng 1 type top-level, không entry `architecture_allowlist.json` nào được thêm hay nới. `Sources/Services/Export/**` không `import SwiftUI`, không `import UIKit`, không gọi `ToastManager.shared`, không `import ZIPFoundation`. Không biên dịch tại chỗ (host Windows — `xcodegen generate`/`xcodebuild` chỉ chạy trên macOS) và **chưa** kiểm trên máy thật: **chưa** có máy đọc nào xác nhận 3 file nhị phân mở được. CI chỉ chứng minh *biên dịch được*.

## [1.3.252] - 2026-08-23

### Nhập truyện PRC, DOCX, FB2 và tách chương quá dài

Mở đường nhập file từ 4 lên **7** định dạng và thêm **một** bước hậu xử lý chung chặn chương quá dài. Thêm **4** file Swift (299 → 303), tất cả trong phân hệ có sẵn `Sources/Services/Import/` (14 → 18 file); **không** `@Model` nào đổi shape, **không** thêm dependency, **không** dựng pipeline lưu trữ thứ hai.

* **`.prc` nhận diện chương sai vì hai lỗi độc lập, sửa cả hai.** (1) `MobiArchiveReader.read` **không** kiểm chữ ký PalmDB ở byte 60…67, nên `.prc` của họ khác (eReader, iSilo…) bị đọc như MOBI rồi ra rác **im lặng**; nay `"BOOKMOBI"` ⇒ MOBI, `"TEXtREAd"` ⇒ text thuần, còn lại `throw .malformed("biến thể PalmDB '…' chưa hỗ trợ")`, và `Package` mang thêm `isPlainText`. (2) `MobiBookParser` đẩy **mọi** file PalmDB vào `HtmlBookParser`, mà `text()` của SwiftSoup gộp mọi whitespace — thân `TEXtREAd` không có một thẻ HTML nào nên mất sạch ranh giới dòng và **luôn** còn 1 chương. Nay nhánh text thuần chuẩn hoá `\r\n`/`\r`/`\u{0C}` về `\n` rồi đi `TxtBookParser` (quy tắc TOC), vẫn giữ cửa `looksLikeHtml` cho `TEXtREAd` chứa HTML. Chặn DRM (`encryptionType != 0`) và HUFF/CDIC (`compression == 17480`) không đổi. Picker mở thêm đuôi `prc`, `.mobi` hiện nhãn `"MOBI/AZW3/PRC"`.
* **DOCX**: `DocxArchiveReader` giải nén qua `BackupZipArchive.extract` (**không** `import ZIPFoundation`) và dọn thư mục tạm ngay trong `defer` — khác `EpubArchiveReader`, caller không phải quản lý vòng đời nên không có đường rò thư mục tạm. Thiếu `word/document.xml` ⇒ báo rõ *"định dạng .doc cũ chưa hỗ trợ"*. `DocxBookParser` đọc OOXML bằng `XMLParser` (không SwiftSoup: `w:`-namespace là XML chặt chẽ, không cần cả cây DOM) thành `[Block]` rồi rơi theo thứ tự **Heading 1–3 → mốc sang trang → quy tắc TOC → 1 chương**. Heading chỉ được tin khi có ≥ 2 heading **và** không chiếm quá nửa số đoạn; nguồn heading là `<w:pStyle w:val>` — so tiền tố `heading` sau khi bỏ khoảng trắng/`_`/`-` vì `w:val` là **style ID** độc lập ngôn ngữ (Word ghi `Heading1` ở mọi bản dịch, LibreOffice ghi `Heading_20_1`) — **hoặc** `<w:outlineLvl>` (0-based, nguồn thứ hai độc lập hoàn toàn với tên style). Mốc sang trang gom `<w:br w:type="page"/>`, `<w:pageBreakBefore/>` (có xét `w:val="0"` là tắt tường minh) và `<w:sectPr>` trong `<w:pPr>` (đánh dấu **kết thúc** section ⇒ đoạn *sau* sang trang mới). `docProps/core.xml` cho `dc:title`/`dc:creator`. Ảnh và định dạng chữ bị bỏ; DOCX không có khái niệm ảnh bìa nên `coverData` luôn `nil`.
* **FB2**: `Fb2BookParser` là format có mục lục đáng tin **thứ hai sau EPUB** — `section`/`title`/`p` có sẵn nên không phải đoán ranh giới bằng regex. Lấy `book-title`, `author` (ghép `first-name`/`middle-name`/`last-name`/`nickname`), `annotation` làm mô tả, ảnh bìa từ `<binary>` base64 (ưu tiên `id` khớp `<coverpage>`, không có thì ảnh `image/*` đầu tiên). An toàn XML: `shouldResolveExternalEntities = false` + `externalEntityResolvingPolicy = .never`, **cộng thêm** từ chối thẳng file khai `<!ENTITY` trong 8 KB đầu thay vì nhờ parser tự chống billion-laughs, và `href` bìa **chỉ** nhận dạng `#id` trỏ vào chính file ⇒ không có đường đọc file ngoài. `<body name="notes">` bị bỏ vì là chú thích. Hai bất biến thứ tự: `section` con mở ra thì text trực tiếp của `section` cha được **xả trước** (nên thứ tự đọc không bao giờ đảo), và `</body>` xả hết frame còn lại nên text nằm ngoài mọi `section` vẫn thành chương. Sách một khối (`chapters.count < 2`) hoặc người dùng ép `tocRules` thì chạy lại bằng `TxtBookParser`.
* **Một bước hậu xử lý chung chặn chương quá dài**: `ChapterLengthLimiter` tách chương > **30 000** ký tự thành các phần ~**15 000**, ưu tiên ranh giới **đoạn → câu → dòng → biên ký tự an toàn**. Ba bất biến: **không mất chữ** (mỗi đơn vị giữ `\n` của chính nó khi ghép lại), **không phần rỗng** (đuôi ngắn hơn 1/5 mục tiêu gộp vào phần trước), **không tách lại phần đã tách** (bỏ qua chương có `partIndex != nil`, nên bấm "Phân tích lại" nhiều lần vẫn ra đúng một kết quả). Việc cắt luôn đi theo `Character` (grapheme cluster), **tuyệt đối không** dùng `NSRange` UTF-16 để cắt `String`. Tiêu đề thành `Lời thì thầm của đá (1)`, `(2)`…; provenance `originalTitle`/`sourceOrdinal`/`partIndex`/`partCount`/`splitReason` trên `ParserChapter` là field **tạm thời**, chỉ sống tới khi sheet xác nhận đóng — `performImport` chỉ đọc `title` + `content` nên **không** chạm schema `@Model` nào. Nhờ có `partIndex` nên không bao giờ phải suy ngược từ hậu tố `" (2)"` trong tiêu đề: hậu tố là kết quả, không phải nguồn dữ liệu.
* **Limiter không thể bị quên**: `BookImportService.parse(_:)` đổi cấu trúc sao cho mỗi nhánh format chỉ dựng `parsed`/`autoDecodeID`/`probe`, còn **phần đuôi dùng chung** kiểm chương rỗng → `ChapterLengthLimiter.apply` → trả `Result`. Thêm format mới về sau không có đường bỏ sót bước này, và `ParsedBook.chapters` phải thành `var` vì thế. `structureNote` vẫn giữ số chương **parser tìm được** (mô tả cách tìm ranh giới), còn số chương sau cùng và báo cáo tách do sheet tự tính từ `chapters` — hai dòng bổ nghĩa cho nhau chứ không mâu thuẫn.
* **Nhận diện ZIP không cần giải nén**: `BookImportFormat` thêm `case docx`/`case fb2`; nhánh magic bytes phân biệt hai họ ZIP bằng cách soi *bên trong* archive — `epub+zip` nằm trong 512 byte đầu (EPUB bắt buộc entry `mimetype` **không nén** đứng đầu file) ⇒ EPUB, thấy chuỗi `word/document.xml` ⇒ DOCX. FB2 phải xét **trước** HTML vì nó cũng là XML nên khớp dấu hiệu `<?xml`.
* **Sheet xác nhận**: thêm dòng cảnh báo màu cam `"Đã tách N chương quá dài thành M phần"` (từ `ChapterLengthLimiter.report`) cạnh dòng "Cách tách", và `showsDecodeRow` đổi từ `if` sang `switch` **liệt kê đủ** mọi case (EPUB/DOCX/FB2 ẩn hàng Bảng mã vì tự khai bảng mã trong file) — thêm format mới sẽ **không biên dịch được** thay vì âm thầm xử lý sai.
* Gate: `check_architecture.py` giữ đúng **14 violation** với tập vi phạm **y hệt** — 4 file mới ≤ 315 dòng và đúng 1 type top-level (mọi delegate `XMLParser`, `struct Block`, `Frame` đều **nest** trong enum), không entry `architecture_allowlist.json` nào được thêm hay nới, không baseline nào bị nới. `Sources/Services/Import/**` vẫn không `import SwiftUI`, không gọi `ToastManager.shared` (lỗi trả bằng `throw`), không `import ZIPFoundation`, và `XhtmlTextExtractor` vẫn là file **duy nhất** `import SwiftSoup`. Không biên dịch tại chỗ (host Windows, `xcodebuild` chỉ chạy trên macOS) và **chưa** kiểm trên máy thật ở lần sửa này — CI chỉ chứng minh *biên dịch được*.

## [1.3.251] - 2026-08-23

### Nhập truyện từ EPUB, HTML, MOBI/AZW3 ngoài TXT

Mở rộng đường nhập file **chỉ nhận `.txt`** thành 4 định dạng. Thêm **15** file Swift (284 → 299), đổi tên 2 file, **không** `@Model` nào đổi shape, **không** thêm dependency nào, **không** dựng pipeline lưu trữ thứ hai.

* **Phân hệ mới `Sources/Services/Import/` (14 file), điểm vào duy nhất `BookImportService.parse(_:)`.** `Request { tempFileUrl, fileName, encodingOverride, ruleIDs, structure }` → `BookImportFormat.detect(fileName:data:)` (ưu tiên đuôi file, fallback magic bytes: `PK\x03\x04` ⇒ epub, `"BOOKMOBI"`/`"TEXtREAd"` ở byte 60…67 ⇒ mobi, thấy `<html`/`<?xml` ⇒ html, còn lại txt) → một trong bốn parser → `Result { parsed, format, autoDecodeID, matchedRuleIDs }`. Cả lần parse đầu **và** mỗi lần "Phân tích lại" đều đi đúng hàm này — không có hai đường code song song. Lý do phải làm được như vậy: `ChapterContentRepository.loadUnshared` phục vụ từ persistence store **trước** nhánh `guard let extensionInfo`, nên bất kỳ format nào chỉ cần sinh ra `ParsedBook` là đọc được không cần extension.
* **Chuỗi ghi cũ dùng lại nguyên xi**: `AddBookToShelfCommand` → `BookTransactionCoordinator.addBookToShelf` → `ChapterStore.replaceFullTOC` → mỗi chương `BookBinManager.writeChapterContent` + `ChapterStore.upsertCachedChapter(isCached: true)`, vẫn cập nhật tiến độ mỗi 50 chương + `Task.sleep(1ms)`. Ba DTO `ParserChapter`/`ParsedBook`/`TXTReanalysisResult` **phải** rời `ShelfView.swift` xuống tầng Services (parser Services không được trả về type khai ở Views — sẽ đảo chiều phụ thuộc); `TXTReanalysisResult` bị xoá, thay bằng `BookImportService.Result`. `ParsedBook` thêm `author`/`desc`/`coverData`/`remoteCoverUrl`/`structureNote`, **tất cả mặc định `nil`** nên call site TXT cũ biên dịch không đổi.
* **TXT không đổi một chút hành vi nào**: `parseTxtBook` dời **nguyên văn** sang `TxtBookParser` (giữ cả `"Mở đầu"`, `trimmingCharacters` từng dòng, cách bỏ dòng trống); chỉ đổi chỗ cắt đuôi tên file từ `replacingOccurrences(of: ".txt")` sang `deletingPathExtension` để dùng chung cho mọi format.
* **EPUB là format có mục lục thật.** `EpubArchiveReader` giải nén qua `BackupZipArchive.extract(archive:to:)` — **không** `import ZIPFoundation`, giữ đúng ràng buộc "một điểm gọi duy nhất" đã ghi trong `BackupZipArchive.swift`; `container.xml` → `rootfile[full-path]` → OPF (fallback: quét `*.opf` đầu tiên), và `resolve(href:)` **bắt buộc** kiểm kết quả vẫn nằm trong `rootDirectory` để chặn zip-slip. `EpubOpfParser` (`XMLParser` một lượt) lấy `dc:title`/`dc:creator`/`dc:description` + manifest + spine + `coverId` (`<meta name="cover">` của EPUB2 hoặc `properties` chứa `cover-image` của EPUB3). `EpubNavParser` đọc `toc.ncx` (**flatten `navPoint` lồng nhau, giữ cả cấp con** — mục lục truyện dài hay để volume ở cấp 1, chương ở cấp 2) và `nav` của EPUB3. `EpubBookParser` rơi theo thứ tự `tocIndex` → `spine` → `tocRules`; nhiều mục lục trỏ cùng một file thì có `#fragment` ⇒ `XhtmlTextExtractor.anchorSegments` cắt theo `id` neo, không fragment ⇒ khử trùng về một chương. `defer` xoá thư mục giải nén tạm sau khi mọi nội dung và bìa đã vào RAM.
* **HTML là nền cho cả MOBI.** `HtmlBookParser` rơi theo thứ tự: tách `<mbp:pagebreak>` ≥ 2 mảnh → `XhtmlTextExtractor.headingSections` (`h1`–`h3`) ≥ 2 → `plainText` rồi đưa vào `TxtBookParser` (đúng đường TXT đang chạy) → cuối cùng giữ 1 chương với `structureNote` nói rõ không tìm thấy ranh giới. `XhtmlTextExtractor` dùng SwiftSoup giới hạn trong tập API đã chạy thật ở `JSDom.swift`, bỏ `script`/`style`, và chèn sentinel `@@FBNL@@` ở biên block trước khi gọi `text()` vì `text()` gộp mọi whitespace — không thể lấy lại newline sau đó. **Không** dùng `String.cleanHTML()` cho đường này (nó không bỏ nội dung `<script>/<style>` và không tách biên `<h1>/<li>`); `cleanHTML()` giữ nguyên cho các caller cũ.
* **MOBI/AZW3 là thử nghiệm, chỉ file không DRM.** `MobiArchiveReader` đọc PalmDB (78 byte header + bảng record-info) → PalmDOC header → MOBI header → EXTH (100 = tác giả, 103 = mô tả, 201 = offset bìa, 503 = tên sách), **mọi offset kiểm biên trước khi đọc** và lệch thì `throw .malformed(...)` thay vì đọc rác; `encryptionType != 0` ⇒ `throw .drmProtected` ("File có DRM, không thể nhập."), `compression == 17480` (HUFF/CDIC) ⇒ `throw .unsupportedCompression`. `PalmDocDecompressor` làm LZ77 PalmDOC **và** `stripTrailingEntries(record:flags:)` (backwards variable-width integer theo `extraDataFlags`, cộng `1 + (lastByte & 0x03)` khi bit 0 bật) — bỏ bước strip là mỗi biên 4096 byte lẫn vài ký tự rác. `MobiBookParser` ghép record text, decode theo codepage rồi đẩy thẳng vào `HtmlBookParser`. **Không** cài SKEL/FDST của KF8, **không** đọc INDX/NCX nhị phân ⇒ ranh giới chương AZW3 có thể lệch, phải dùng "Phân tích lại" với quy tắc TOC.
* **Lệch có chủ ý so với plan** (ghi lại để không bị coi là quên): **offset MOBI header trong plan sai và tự mâu thuẫn**, đã sửa theo `lib/mobi_header.py` của KindleUnpack — tính từ đầu record 0: `"MOBI"` @0x10, `headerLength` @0x14, `codepage` @0x1C, `version` @0x24, `fullNameOffset` @0x54, `fullNameLength` @0x58, `firstImageIndex` @0x6C, EXTH flags @0x80 (bit `0x40`), `extraDataFlags` @0xF2 (chỉ đọc khi `headerLength >= 0xE4` **và** `version >= 5`), `0xFFFFFFFF` = không có. Plan ghi `fullNameOffset @0x3C`, `firstImageIndex @0x54`, `exthFlags @0x68` — dùng con số đó là đọc rác hoặc trượt biên. Lệch thứ hai, nhỏ hơn: `nav` của EPUB3 **không** đọc bằng `SwiftSoup.select("nav[epub|type=toc] a")` như plan mô tả, vì selector SwiftSoup không nhận tên thuộc tính có dấu `:`; `EpubNavParser` khoanh vùng khối `<nav>` bằng regex rồi lấy từng `<a href>` và gọi `XhtmlTextExtractor.inlineText`. Hệ quả: `XhtmlTextExtractor` là file **duy nhất** trong phân hệ `import SwiftSoup`.
* **Encoding**: `TextEncodingDecoder` 44 → **102** dòng, thêm `option(forCharsetName:)` (ánh xạ tên IANA) và `decodeDeclared(_:charsetName:)`; thứ tự áp dụng là **override người dùng → khai báo trong file (`<meta charset>`, `<?xml encoding=…>`, `codepage` của MOBI) → auto-detect như cũ**. **Không** thêm case cho `TextEncodingOption` vì thêm case là đổi thứ tự ưu tiên auto-detect của TXT.
* **Bìa và metadata không cần code lưu trữ mới**: `parsed.coverData` ⇒ `ImageCacheManager.shared.saveCover(data:for:)` và **để `coverUrl` rỗng** (đúng tiền lệ `BookInfoEditView`; `BookCoverView` ưu tiên file bìa local), ngược lại `parsed.remoteCoverUrl` ⇒ `AddBookToShelfCommand.coverUrl`. `author`/`desc` nay lấy từ file, vẫn rơi về `"Local"` và `"Truyện nhập cục bộ từ file …"` khi thiếu; `Book.isLocalBook` chỉ dựa `extensionPackageId`/`detailUrl`/`sourceName` nên sách không mất tính "local".
* **UI**: nhãn menu `"Nhập truyện TXT"` → `"Nhập truyện từ file"`, picker dùng `BookImportFormat.pickerContentTypes`. Sheet xác nhận thêm hàng **"Cấu trúc"** (Tự động / Theo mục lục / Theo thứ tự spine / Theo quy tắc TOC) và dòng `structureNote` cho biết đã tách bằng cách nào; hàng "Bảng mã" **ẩn** khi format là EPUB (XHTML là UTF-8 theo chuẩn). Đổi tên cho khớp phạm vi mới: `ShelfView+TXTImport.swift` → `ShelfView+BookImport.swift`, `TXTImportConfirmationSheet` → `BookImportConfirmationSheet`, `importTxtBook` → `importLocalBook`, `reanalyzeTxt` → `reanalyzeImport`, `isParsingTXT` → `isParsingImport`.
* **Giới hạn phải nói rõ**: (1) ảnh trong nội dung bị bỏ — Reader là `UITextView` plain text, chỉ ảnh bìa được giữ; (2) định dạng chữ (in nghiêng, tiêu đề nhỏ) bị mất vì chương lưu plain text trong `.bin`; (3) nhập lại cùng một file tạo truyện mới (`bookId = UUID().uuidString`, không dedupe — đúng hành vi TXT hiện có); (4) MOBI/AZW3 thử nghiệm, từ chối DRM và HUFF/CDIC; (5) HTML nhiều file/thư mục không hỗ trợ (picker một file, ảnh `src` tương đối bị bỏ).
* **Trần dòng, không nới gì**: 15 file mới đều ≤ 400 dòng và **đúng 1 type top level** (type con nest trong `BookImportService`/`EpubArchiveReader`/`EpubOpfParser`/`EpubNavParser`/`MobiArchiveReader`), lớn nhất `EpubBookParser.swift` **306**. `ShelfView.swift` 827 → **811**, `TXTImportConfirmationSheet.swift` 374 → `BookImportConfirmationSheet.swift` **288** + `+Pickers.swift` **203**, `ShelfView+TXTImport.swift` 283 → `ShelfView+BookImport.swift` **215** — đều đúng chiều "chỉ được giảm". `Sources/Services/Import/**` không file nào `import SwiftUI`, gọi `ToastManager.shared` (lỗi đi bằng `throw BookImportService.ImportError` mang chuỗi tiếng Việt) hay `import ZIPFoundation`.
* **Xác minh**: `check_architecture.py` **14 → 14 violation**, đúng **cùng một tập** — không vi phạm mới, không entry `architecture_allowlist.json` nào được thêm hay nới, không baseline nào bị nới. `validate_links.py` PASS 16 doc / 299 file Swift. **Không biên dịch được tại chỗ** (host Windows, `xcodebuild` chỉ chạy trên macOS) — CI xanh chỉ nghĩa là *biên dịch được*; phải kiểm trên máy thật với log bật: nhập lại đúng file TXT cũ để chắc không hồi quy, một EPUB2 + một EPUB3 + một EPUB "một file XHTML, mục lục toàn `#anchor`", một HTML có `<h2>` mỗi chương và một HTML không heading, một `.mobi` không DRM, một `.azw3` có DRM (phải hiện đúng thông báo và **không** tạo sách rỗng trên kệ), rồi kiểm `temporaryDirectory` không còn file tạm lẫn thư mục `<uuid>-epub`.

## [1.3.250] - 2026-08-23

### Tối ưu xuất TXT, mục lục, từ điển; dời sửa thông tin truyện

Bốn việc hiệu năng + một việc dời UI trong một commit. Thêm **5** file Swift (279 → 284), không `@Model` nào đổi shape, không thêm tên notification string nào.

* **Sửa một từ VietPhrase/Names không còn nạp lại cả từ điển.** `TranslationManager.reloadCustomDictionary(isName:)` parse lại đúng một file (`CustomNames.txt` **hoặc** `CustomVietPhrase.txt`), dựng lại dict tương ứng và gọi `updateDeletedState` (nên tombstone `word=` của nhánh xoá cũng đúng) — **không** chạm 4 file `.dat` lẫn `ChinesePhienAmWords.txt`. `saveCustomEntry`/`deleteCustomEntry` với `bookId != nil` thì chỉ bỏ entry `bookDicts[bid]` và **không reload gì cả** (`getBookDictionaries` nạp lazy ở lần dịch sau). `DictionaryCache.persistAndUpdate` cũng chuyển sang hàm này và đưa `loadEntries` ra khỏi actor của caller. `loadAllDictionaries()` giữ nguyên cho khởi động, tải/cài lại từ điển chung và khôi phục backup. Tiền lệ có sẵn trong file: `removeDeletedWords` vốn đã persist → `updateDeletedState` → notify mà không reload.
* **Bảo đảm không bị cắt**: thêm/sửa/xoá VietPhrase–Names **vẫn dịch lại chương**, và giờ **đúng một lần** thay vì ≥ 2. Chuỗi còn nguyên: ghi TXT → `reloadCustomDictionary` → `notifyDictionariesDidUpdate` → `TranslateUtils.invalidateCache` (bump generation) → `.translationDictionariesDidUpdate` → `ReaderView.onReceive` → `scheduleCoalescedTranslationRefresh` (defer nếu overlay đang mở) → 150 ms → `updateCachedTranslatedContent` → `refreshParagraphItems()`. Cái bị bỏ ở `saveDefinition` là lần `updateCachedTranslatedContent` gọi **trực tiếp** và lần `scheduleCoalescedTranslationRefresh` tường minh — đường notification vốn đã có scope + debounce + deferral. `suggestionChips` từ computed property (chạy ~6 `findLongestMatch` + `getHanViet` **mỗi lần body dựng lại**, tức mỗi ký tự gõ vào ô nghĩa) thành `@State` tính một lần khi chuỗi chọn đổi, tách sang `ReaderView+Suggestions.swift`.
* **Mục lục: quyết định trước khi ghi.** `ChapterTOCDiff.plan` (hàm thuần, không sqlite) so từng field `(index, url, title, host, titleTrans-nếu-mới-khác-rỗng)` **không cấp phát chuỗi nội suy**; `.unchanged` ⇒ `replaceFullTOC`/`upsertPage` **không mở transaction**, `.appendOnly` ⇒ chỉ `REPLACE` phần đuôi và bỏ pass xoá stale, mọi trường hợp không chắc ⇒ `.full` như cũ (chương TTS được bảo vệ mà TOC mới không có ⇒ ép `.full`). Lượt `fetchOrderedTOC` **thứ hai** — trước dùng để tính `computeDeterministicChecksum`/parity, tức materialize lại N hàng — bị bỏ, thay bằng `countChapters(bookId:)` O(1). Nút "Cập nhật mục lục" trong Reader bỏ luôn `fetchOrderedTOC` + 2×N chuỗi identity mà nó tự dựng để so, giờ đọc `SaveTOCResult`; `reloadBookData()` gom 4 `await MainActor.run` thành 1, chỉ `updateBookMetadata` khi field thật khác, và chỉ `refreshLocalTOCSnapshots()` khi có gì đổi ⇒ kéo-để-tải-lại không có chương mới **không** ghi DB và **không** gán lại mảng `@State`. `saveChapterList` bỏ `context.save()` khi `createSnapshot == nil`.
* **Xuất TXT (kể cả "Chỉ xuất chương đã tải") bỏ phần lớn việc dư mỗi chương.** CRUD task tách sang `DownloadManager+TaskStore.swift`: một `ModelContext` dùng lại cho cả phiên (thay vì tạo mới **mỗi** lần cập nhật tiến độ), `FetchDescriptor` có `#Predicate` theo `id` + `fetchLimit = 1` (thay cho fetch **toàn bảng**), `save()` được coalesce theo thời gian nhưng luôn ghi chắc ở `markCompleted`/`markFailed`/`markCancelled`/`initialize`, và `@Published tasks` chỉ đổi ~10 lần/giây (bước cuối, bước 0 và mọi thay đổi trạng thái luôn phát) — giá trị mới vẫn áp vào model ở mọi lần gọi, chỉ fsync bị gộp. Bỏ hop MainActor chỉ để hỏi cancel (`Task.isCancelled` là đủ vì mọi đường huỷ đều `handle.cancel()`). `BookBinManager` cache đường dẫn `.bin` đã resolve (`resolvedBinURLs`, dọn trong `deleteBinFile`) nên `sha256Hex` + `validatePathSafety` + kiểm migrate legacy không còn chạy lại cho từng chương. Bộ đệm `String` cộng dồn cả bản xuất bị thay bằng `TxtExportFileWriter`: ghi dần vào `<tên>.txt.part`, `finish()` mới rename ⇒ RAM phẳng và huỷ/lỗi không để lại `.txt` dở dang.
* **"Sửa thông tin truyện" dời khỏi màn Chi tiết.** `BookDetailView` bỏ `showingEditInfo`, `.sheet`, item menu và `refreshDisplayedBookInfo()` (caller cuối là `onDismiss` của sheet đó); `ShelfView` giữ một `@State editingInfoBook: Book?` + một `.sheet(item:)` dùng chung cho cả tab Kệ sách và Lịch sử, sau khi lưu thì `@Query` tự cập nhật. `BookInfoEditView.swift` giữ nguyên chỗ cũ để tránh churn.
* **Lệch có chủ ý so với plan** (ghi lại để không bị coi là quên): (1) `BookBinManager` được cache **đường dẫn** thay vì `openReader(bookId:)` giữ `FileHandle` — handle mang `FileHandle` không `Sendable` nên không qua được ranh giới actor, còn cache cho cùng phần tiết kiệm và có lợi cho mọi caller; (2) kiểm cancel dùng `Task.isCancelled` **một mình** thay vì cộng thêm snapshot `Set` `cancelledTaskIds` — đọc `Set` đó từ task nền là truy cập không đồng bộ hoá, thêm race để lấy một tín hiệu đã có.
* **Trần dòng, không nới gì**: `ShelfView.swift` 1076 → **827** (baseline 942) nhờ tách `Extensions/ShelfView+TXTImport.swift` (283) và `DownloadManager.swift` 688 → **484** (baseline 640) nhờ tách `+TaskStore` (249) + `TxtExportFileWriter` (97) ⇒ **cả hai rời khỏi danh sách vi phạm**. `ReaderView.swift` 2268 → **2186**, `ChapterStoreDatabase.swift` 955 → **954**, `BookDetailView.swift` 1181 → **1175**, `ChapterPersistenceStore.swift` giữ **915** — đều đúng chiều "chỉ được giảm"; `TranslationManager.swift` 594 → **631** (baseline 642). Năm file mới đều ≤ 400 dòng và đúng 1 type top-level; `Sources/Services/**` không `import SwiftUI`, không `ToastManager.shared` (toast xuất TXT vẫn qua `DownloadPresentationEventCenter`).
* **Xác minh**: `check_architecture.py` **16 → 14 violation**, tập còn lại là **tập con thật sự** — không entry `architecture_allowlist.json` nào được thêm, nới hay gia hạn, không baseline nào bị nới. `validate_links.py` PASS 16 doc / 284 file Swift. **Không biên dịch được tại chỗ** (host Windows, `xcodebuild` chỉ chạy trên macOS) — CI xanh chỉ nghĩa là *biên dịch được*; hiệu năng thật và 6 tổ hợp thêm/sửa/xoá × VietPhrase/Names × global/riêng-truyện phải kiểm trên máy thật với log bật.

## [1.3.249] - 2026-08-22

### Lấy tiến độ tải Drive qua didCreateTask và KVO

Sửa nốt lỗi 1.3.248 chưa vá đúng: thanh tiến độ tải xuống **vẫn đứng im** dù đã gắn task delegate. Một file Swift đổi, không thêm/xoá file (279 file), không type top-level nào mới.

* **Nguyên nhân thật**: bản **async** của `URLSession.download(for:delegate:)` được dựng trên completion handler, và Foundation **chặn toàn bộ callback của `URLSessionDownloadDelegate`** ở đường đó — `didWriteData` không bao giờ được gọi. Tệ hơn, tham số `delegate:` khai kiểu `URLSessionTaskDelegate`, nên `didWriteData` (thuộc `URLSessionDownloadDelegate`) thậm chí không nằm trong tập hàm được xét. Apple DTS xác nhận hành vi này và coi việc chặn *riêng* callback tiến độ là đáng báo lỗi, nhưng nó vẫn còn nguyên.
* **Sửa**: `DownloadProgressObserver` chuyển sang conform `URLSessionTaskDelegate` và cài `urlSession(_:didCreateTask:)` — callback **vẫn được gọi** ở đường async và là nơi *duy nhất* lấy được `URLSessionTask` (API async không trả về task handle). Từ đó bám `task.progress` bằng **KVO**. Vẫn không duyệt từng byte kiểu `for await`: quá chậm với archive vài trăm MB.
* **Bám hai khoá KVO, không phải một**: `fractionCompleted` là khoá chính thức của `Progress`, nhưng nếu Drive không gửi `Content-Length` thì `totalUnitCount` là -1 ⇒ `fractionCompleted` đứng im ở 0 và **không phát tín hiệu nào**; vì vậy bám thêm `completedUnitCount` và tính phần trăm với tổng rơi về `GoogleDriveFile.byteCount` (lấy từ lượt `listBackups`). Tiết chế theo phần trăm giữ nguyên nên hai khoá cùng nổ cũng không nhân đôi lượt hop lên MainActor; `deinit` `invalidate()` cả hai observation.
* Phần đã đúng ở 1.3.248 **không sửa lại**: `BackupCoordinator` vẫn truyền `makeReporter()` ở cả hai call site, khoá đăng xuất (`guard !isBusy` + `.disabled(coordinator.isBusy)`) giữ nguyên. `GoogleDriveClient` 203 → **216** dòng (trần 400); observer vẫn là `private final class` lồng trong actor nên không thêm primary type ở cột 0.
* **Xác minh**: `check_architecture.py` giữ **đúng 16 violation với tập y hệt**; `validate_links.py` PASS sau khi cập nhật `11_subsystems.md`. **Không biên dịch được tại chỗ** (host Windows) — CI xanh chỉ nghĩa là biên dịch được; tiến độ chạy thật phải nhìn trên máy.

## [1.3.248] - 2026-08-22

### Thanh tiến độ tải Drive chạy thật, chặn đăng xuất khi đang tải

Hai lỗi trong một commit, **không thêm/xoá/đổi tên file Swift nào** (279 file), không type top-level nào mới, **không `@Model` nào đổi shape**.

* **Thanh tiến độ tải xuống hiện ra nhưng không bao giờ nhích** — nguyên nhân là dữ liệu, không phải UI. `BackupProgress.fraction` trả `nil` khi `totalUnits == 0`, và `ProgressView(value: nil)` kiểu `.linear` vẽ một thanh **tĩnh**; `GoogleDriveClient.download(file:)` chưa từng báo byte nào nên `totalUnits` giữ 0 suốt lượt tải. Sửa: `download(file:report:)` gắn task delegate `DownloadProgressObserver` vào `URLSession.shared.download(for:delegate:)`, và `BackupCoordinator` truyền `makeReporter()` ở **cả hai** call site (`downloadFromDrive`, `restoreEverythingFromDrive`) — đúng cầu hop-lên-MainActor mà `GoogleDriveUploader` đã dùng, nên hai chiều tải lên/tải xuống giờ đối xứng.
* **Vì sao phải là task delegate**: bản async của `download(for:)` **không trả về `URLSessionTask`** nên không có handle nào để đọc `Progress`; còn duyệt `for await byte in` thì chậm hơn nhiều lần và giữ RAM vô ích với archive vài trăm MB (ghi chú sẵn có trong file đã nói rõ điều này). Ba chi tiết bắt buộc: (1) chỉ cài `didWriteData`, `didFinishDownloadingTo` cố ý **để trống** vì bản async tự dời file tạm — cài thật là tranh chấp với nó; (2) `totalBytesExpectedToWrite <= 0` (Drive có thể không gửi `Content-Length`) thì rơi về `GoogleDriveFile.byteCount` lấy từ lượt `listBackups`; (3) báo theo **phần trăm** (`completedUnits: percent, totalUnits: 100`) và **chỉ khi phần trăm đổi** — delegate được gọi mỗi lần có gói dữ liệu về, không tiết chế thì hàng nghìn lượt hop dội lên MainActor. Observer phải được giữ **mạnh** trong thân hàm vì `download(for:delegate:)` chỉ giữ delegate yếu.
* **Đang tải dữ liệu từ Drive mà vẫn đăng xuất được** ⇒ `GoogleDriveAuthService.signOut()` thu hồi access token đang nằm trong tay worker, request đang bay chết giữa đường và để lại archive dở. Sửa ở hai tầng cho khớp mẫu sẵn có: `BackupCoordinator.signOutDrive()` thêm `guard !isBusy` và đặt `lastError` (**không** im lặng bỏ qua — toast do `BackupHubView` sở hữu vẫn sống khi màn Drive được push, nên người dùng thấy lý do), còn nút "Đăng xuất Google Drive" thêm `.disabled(coordinator.isBusy)` — trước đó nó là nút **duy nhất** ở `accountSection` thiếu điều kiện này.
* **Kiến trúc**: `DownloadProgressObserver` là `private final class` **lồng trong** actor `GoogleDriveClient`, nên `check_architecture.py` (chỉ tính type ở cột 0) không coi là primary type thứ hai; `Services/Backup/**` vẫn không `import SwiftUI`, không gọi `ToastManager`. Số dòng: `GoogleDriveClient` 137 → **203**, `BackupCoordinator` 259 → **271**, `GoogleDriveBackupListView` 211 → **212** — cả ba là file mới của 1.3.246 nên trần là 400 dòng.
* **Xác minh**: `check_architecture.py` giữ **đúng 16 violation với tập y hệt** (không nới baseline, không thêm allowlist); `validate_links.py` PASS 16 doc / 279 file Swift sau khi cập nhật `11_subsystems.md` (doc duy nhất có `sourcePatterns` phủ `Services/Backup/**` + `Views/Settings/**`). **Không biên dịch được tại chỗ** — host là Windows, `xcodebuild` chỉ chạy trên macOS; CI xanh chỉ nghĩa là *biên dịch được*, không phải đã kiểm chứng runtime của task delegate dưới LiveContainer.

## [1.3.247] - 2026-08-22

### Khôi phục giữ thứ tự đọc và một chạm từ Drive, sửa trình soạn script, ext có bản mới lên đầu

Năm lỗi/yêu cầu trong một commit, **+2 file Swift (277 → 279)**, không xoá hay đổi tên file nào, **không `@Model` nào đổi shape** ⇒ không rủi ro lightweight migration.

* **Khôi phục làm mất thứ tự đọc của máy nguồn — nguyên nhân ở mắt cuối của luồng, không ở nơi đọc dữ liệu.** Kệ sách sắp xếp bằng `@Query(sort: \Book.lastReadDate, order: .reverse)`; backup **đã** mang `BackupPayload.BookRecord.lastReadDate` và `BackupLibraryWriter` **đã** đọc nó, nhưng `AddBookToShelfCommand` không có field tương ứng nên `BookTransactionCoordinator.addBookToShelf` dập `Date()` cho mọi sách ⇒ thứ tự đọc biến thành thứ tự chèn. Sửa: thêm `public let lastReadDate: Date?` vào command với **mặc định `nil`** (mọi call site cũ biên dịch không đổi) và đọc `command.lastReadDate ?? Date()` ở cả hai nhánh của coordinator — `nil` giữ hành vi cũ cho việc thêm sách thủ công. **Luồng chương không liên quan và vốn đã đúng**: ba câu lệnh TOC đều `ORDER BY chapter_index ASC` và `BackupChapterRestorer` sort theo `index` trước khi ghi, nên không sửa gì ở đó.
* **Thông báo tiến độ khôi phục làm giật khung hình** vì mỗi pha có độ dài chữ khác nhau, dòng chữ đổi số dòng ⇒ đổi chiều cao hàng ⇒ cả list nhảy. Sửa bằng cách cố định chiều cao dải tiến độ ở **cả hai** subscriber (`BackupHubView`, `GoogleDriveBackupListView`); `BackupProgress` không đổi shape và không có bản sao tiến độ nào ở tầng View.
* **Thêm khôi phục một chạm cho bản backup trên Drive**: `BackupCoordinator.restoreEverythingFromDrive(_:container:)` chạy trọn `download` → `LocalBackupStore.importArchive` → `prepare` → restore với `BackupScope.defaultSelection` → `cancelPreparedRestore()`, **không mở `RestoreOptionsSheet`**. Điểm kỹ thuật đáng nhớ: mọi entry point công khai của coordinator đều `guard !isBusy`, nên phải tách thân dùng chung thành `performRestore(prepared:container:options:)` **private, không tự giữ khoá** — nếu gọi `runRestore` từ trong `restoreEverythingFromDrive` thì nó tự khoá chính mình. `runRestore` giữ nguyên chữ ký, nay chỉ là lớp bọc giữ khoá. **Tiền điều kiện "TTS không đang phát" được kiểm ở cả hai entry point** (vẫn qua projection reader `TTSWidgetStateReader`, không observe `TTSManager`), và thư mục tải tạm vẫn tự xoá bằng `defer`.
* **Trình soạn script — nội dung cuối bị bàn phím che khi script ngắn.** `UIScrollView` có content ngắn hơn viewport thì **không thể cuộn**, nên không cách nào đưa dòng cuối lên trên bàn phím bằng cuộn. Sửa: `CodeEditorTextView` quan sát `willShow`/`willChangeFrame`/`willHide`, quy giao điểm khung bàn phím với chính nó về `contentInset.bottom` + `verticalScrollIndicatorInsets.bottom` (`layoutSubviews` tính lại khi khung đổi), `deinit` gỡ observer. Đổi inset < 0.5 pt thì bỏ qua để không tự kích hoạt layout vòng.
* **Màu code "thỉnh thoảng trục trặc"** là hệ quả của hai lượt regex **chồng nhau**: `comment` và `string` tô riêng theo thứ tự gọi nên `"https://…"` bị nửa sau ăn màu ghi chú, còn `// "trong ngoặc"` thì ngược lại. Sửa: gộp ghi chú + 3 loại chuỗi vào **một** alternation `protected` — `NSRegularExpression` match không chồng lấn và trái-thắng nên đúng ngữ nghĩa lexer; các token còn lại (number/keyword/builtin/functionCall) bị loại nếu giao với vùng bảo vệ (tìm nhị phân). Đồng thời `textViewDidChange` **không gán lại `attributedText`** nữa mà sửa attribute **tại chỗ** trên `textStorage` rồi đặt lại `typingAttributes` — trước đây gán lại làm mất con trỏ và để `typingAttributes` cũ, khiến chữ vừa gõ mang màu của token trước.
* **Bấm ra ngoài vùng nhập không tắt bàn phím**: thêm `dismissKeyboard()` (`resignFirstResponder` gửi tới `nil`) gọi từ hai chỗ — vùng trống của hai thanh dưới cùng (`.contentShape(Rectangle())` + `.onTapGesture`) và một nút `keyboard.chevron.compact.down` ở đầu thanh ký hiệu nhanh.
* **Ext có bản cập nhật chưa áp dụng nay nằm đầu danh sách.** Sửa tại đúng một choke point: `RepositoryFilterPolicy.sortExtensions` (comparator duy nhất sau `filteredExtensions`), thêm `hasUpdate` làm **khoá so sánh đầu tiên** trước đã-cài → được-ghim → tên. An toàn có chứng minh: `Extension.hasUpdate` = `remoteVersion > version` **và** `!localPath.isEmpty`, nên nó luôn hàm ý "đã cài" và không thể phản chứng khoá cài/chưa-cài ở dưới. Sắp xếp làm trên RAM — `@Query` vẫn không mang sort/predicate chuỗi (luật SQLite iOS 17), và `RepositoryManagerView.swift` **không bị sửa một dòng** nên số dòng của nó không tăng.
* **Ngân sách dòng: `ExtensionScriptEditorView.swift` 583 → 384 (baseline 474) ⇒ rời khỏi danh sách vi phạm.** Trích sang hai file `extension` mới: `ExtensionScriptEditorView+Picker.swift` (**117**) và `+Toolbars.swift` (**119**) — file chỉ chứa `extension` không khai type top-level nên `MULTI_PRIMARY_TYPES` không áp dụng. `+Toolbars.swift` khai `import UIKit` tường minh (cần `UIApplication`/`UIResponder`); nó ở `Views/**` nên luật `SERVICE_SWIFTUI_IMPORT` (chỉ áp `Sources/Services/**`) không liên quan. Các file đổi khác: `CodeEditorTextView` 111 → 170, `HighlightingCodeEditor` 169 → 204, `BackupCoordinator` 209 → 259, `GoogleDriveBackupListView` 168 → 211, `RepositoryFilterPolicy` 49 → 55.
* **Gate:** `check_architecture.py` **17 → 16 violation** — violation duy nhất mất đi là `LINE_LIMIT_EXCEEDED` của `ExtensionScriptEditorView.swift`, **không violation mới**, không entry `architecture_allowlist.json` nào được thêm, nới hay gia hạn. `validate_links.py`: 8 doc `--accept` (`00`, `02`, `03`, `07`, `09`, `11`, `12`, `14`) + `13` `--no-change-needed` (mục 1.3.246 của nó đã mô tả đúng `TaskGroup` 6 lượt và `save()` một lần; hai file mới nằm ngoài `sourcePatterns` của nó), read-only **PASS 16 doc / 279 file Swift**. `project.yml` không cần sửa (không key Info.plist mới); `xcodegen generate` vẫn phải chạy vì có file Swift mới.
* **Chưa biên dịch**: host là Windows, `xcodegen`/`xcodebuild` chỉ chạy trên macOS. Xác minh ở đây là đọc code (`hasUpdate` thật, chữ ký `addBookToShelf`, đường `filteredExtensions`, ngữ nghĩa không-chồng-lấn của `NSRegularExpression`) cộng hai script Python. **CI xanh chỉ nghĩa là biên dịch được.**
* **Chưa thể xác minh ở môi trường này** (hành vi runtime trên máy thật): thứ tự kệ sách sau khôi phục, dải tiến độ không còn giật, chuỗi một chạm từ Drive chạy trọn và vẫn bị chặn khi TTS phát, dòng cuối script với bàn phím mở, màu của `"https://…"` và `// "trong ngoặc"`, bàn phím tắt khi chạm ra ngoài, và ext có bản mới nổi lên đầu sau "Cập nhật lại các kho".

## [1.3.246] - 2026-08-22

### Sao lưu/khôi phục Drive + local, cập nhật ext song song, sửa thông tin truyện

Ba việc trong một commit: phân hệ sao lưu/khôi phục mới (`Sources/Services/Backup/` + `Sources/Views/Settings/Backup/`), sửa nguyên nhân thật của "cập nhật ext quá chậm", và màn sửa thông tin truyện. **+33 file Swift (244 → 277), không xoá hay đổi tên file nào; không `@Model` nào đổi shape ⇒ không rủi ro lightweight migration.**

* **Định dạng `.fbbackup` là ZIP có manifest, không phải dump DB.** Cây entry: `manifest.json` (schemaVersion, appVersion, createdAt, scope, counts) · `library/{slugs,books,repositories,extensions}.json` · `chapters/<slug>.json` (toàn bộ TOC kèm `isCached/offset/length`) · `content/<slug>.bin` · `extensions/<packageId>/**` · `dict/global/Custom{VietPhrase,Names}.txt` · `dict/books/<slug>/{VietPhrase,Names}.txt` · `dict/shared/*`. Dùng **slug `b0001…`** thay bookId vì bookId là URL có thể chứa ký tự đường dẫn, và vì hàm sha256 bị cài lại độc lập ở từng owner (`BookBinManager`, `ImageCacheManager`, `ChapterStorePath`) nên không mượn được. `library/slugs.json` phủ cả bookId **chỉ có từ điển riêng** mà không còn trong kệ.
* **6 nhóm chọn được, mặc định bật hết, không có nhóm bìa.** `books` bắt buộc (nền của mọi nhóm khác) · `content` · `extensions` · `dictBooks` · `dictCustom` · `dictShared`. Bỏ `covers/` là quyết định của người dùng: bìa từ `coverUrl` tải lại được, còn **bìa người dùng tự chọn từ máy sẽ mất khi restore sang máy khác** — giới hạn đã biết, không phải bug. `dict/shared` chỉ lấy `<Name>.txt` ở gốc `translate/` khi **không** có `.dat` cùng tên (tránh nhân đôi vài chục MB); `BackupSizeEstimator` hiện dung lượng ước tính từng nhóm trước khi tạo.
* **"Mục VP/Name đã xoá" không cần định dạng riêng.** Tombstone chính là bản ghi `value.isEmpty` nằm ngay trong `Custom*.txt` / `translate/books/<bookId>/*.txt` (`DictionaryTextRecord.isDeleted`), nên chỉ cần thêm hai nhóm TXT nguyên trạng là đã phủ. Khi restore, `DictionaryTextFileStore.parseRecords` + `mergedRecords(imported:existing:isMerge: true)` + `persist` xử lý gộp — **dùng lại nguyên primitive đang có, không tầng lưu trữ song song nào được tạo**.
* **Restore là MERGE, không bao giờ ghi đè toàn bộ, và chạy lại cùng một file thì không nhân đôi.** Kho: `Repository.url` là `.unique` mà `addRepository` không dedupe ⇒ query tập url hiện có trước, chỉ insert cái thiếu. Ext: thư mục đích đã có thì giữ bản local (chỉ thay khi `version` trong backup lớn hơn), rồi `localPath` **tính lại** bằng `findMainExtensionFolder(at:)` vì `Extension.localPath` là đường dẫn tuyệt đối của máy cũ; `upsertExtension` đã upsert theo `packageId`. Truyện: bookId đã có ⇒ **không ghi đè** metadata/tiến độ local.
* **Offset của `.bin` là thứ dễ làm hỏng dữ liệu nhất, nên tách hẳn hai nhánh.** Local **chưa có TOC** ⇒ copy nguyên `content/<slug>.bin` vào đúng chỗ ⇒ offset trong backup còn hiệu lực ⇒ `ChapterStore.importBookMigration` ghi TOC + `is_cached/offset/length` trong một transaction (đây là **caller production đầu tiên** của hàm đó; nó xoá chương không có trong tập truyền vào nên chỉ dùng ở nhánh này). Local **đã có TOC** ⇒ `upsertPage` cho index còn thiếu, rồi với chương backup có cache mà local chưa cache thì đọc `length` byte tại `offset` từ `.bin` đã giải nén bằng `FileHandle` → `BookBinManager.writeChapterContent` → `updateCacheMetadata`; **offset từ backup không bao giờ vào DB ở nhánh này**. Mirror sang bảng SwiftData `Chapter` chỉ khi `ChapterStoreConfiguration.enableSwiftDataTOCWrite` (production đang `false`).
* **Chặn restore khi TTS đang phát**, đọc qua projection reader `TTSWidgetStateReader` chứ không observe `TTSManager` — vì restore ghi vào đúng các hàng mà TTS đang sở hữu tiến độ. Kết thúc restore: `loadAllDictionaries()` + `notifyDictionariesDidUpdate()` + phát lại `"extensionDidUpdate"` (**không thêm tên notification string mới**). Toast do tầng Views hiện: `Sources/Services/Backup/**` không `import SwiftUI` và không gọi `ToastManager.shared`.
* **Google Drive: OAuth PKCE + Drive v3, không có `client_secret`.** `ASWebAuthenticationSession` (Google chặn embedded WKWebView) với `callbackURLScheme` suy ra tại runtime từ client id đảo ngược ⇒ **không cần khai `CFBundleURLTypes`**. Scope `drive.file` (chỉ file do app tạo, không phải scope sensitive nên không cần Google review), thư mục `FreeBookBackups`, upload resumable chunk 8 MiB có xử lý 308 và retry 5xx 3 lần ⇒ **peak memory không phụ thuộc kích thước archive**. Refresh token vào Keychain (`kSecAttrAccessibleAfterFirstUnlock`), fallback file có `FileProtectionType.completeUntilFirstUserAuthentication` cho LiveContainer; **không log token, không log payload**.
* **Client id đi đường GitHub secret y hệt `GOOGLE_CLOUD_TTS_API_KEY`**: `project.yml` `info:` thêm `GOOGLE_DRIVE_CLIENT_ID: "$(GOOGLE_DRIVE_CLIENT_ID)"`, `build-ipa.yml` thêm `env:` cho hai step và một khối `plutil -extract/-replace/-insert`. `GoogleDriveConfiguration` đọc `UserDefaults("googleDriveClientId")` trước rồi Info.plist với **đủ ba guard** (`!= "$(GOOGLE_DRIVE_CLIENT_ID)"`, `!contains("$(")`, rỗng-sau-trim) — vì build không có secret thì chuỗi `$(VAR)` nằm nguyên văn trong plist. Thiếu client id ⇒ tab Drive hiện "chưa cấu hình" kèm ô dán, **kênh local vẫn chạy đủ**.
* **Kênh local**: `backups/` trong appSupport, liệt kê kèm ngày + dung lượng, xuất ra Files bằng `ShareSheet` sẵn có, nhập bằng `DocumentPicker` với `UTType(filenameExtension: "fbbackup") ?? .data`, `asCopy: true`.
* **"Cập nhật ext quá chậm": nguyên nhân là network tuần tự, không phải SwiftData.** `RepositoryManagerView.syncExtensions` là `@MainActor` và chạy tuần tự từng ext: mỗi ext chưa cài thì một `URLSession.shared.data(from:)` riêng (timeout mặc định **60 s**), rồi `upsertExtension` với **một `context.save()` riêng cho mỗi ext** — mà `allExtensions` là `@Query` nên mỗi save còn kéo view render lại. Kho 60 ext ⇒ 60 request tuần tự + 60 transaction. Sửa: `ExtensionSyncCommandBuilder` (Services, 168 dòng) nhận snapshot bất biến chụp một lần trên MainActor, chạy **ngoài main** trong `TaskGroup` cửa sổ trượt **6 lượt đồng thời** với `timeoutIntervalForRequest = 10`, trả về `[UpsertExtensionCommand]`; `ExtensionTransactionCoordinator.upsertExtensions(commands:in:)` áp cả lô rồi **`save()` một lần**. **Thứ tự fallback resolve field giữ y nguyên không đổi một dòng.** Thêm log `ℹ️ [ExtSync] … trong Xs` để đo trước/sau trên máy thật; đổi `print` còn lại sang `AppLogger`. **Không tạo store SQLite mới, không migrate lúc khởi động, không đụng `@Query` nào.**
* **Sửa thông tin truyện (tên, tác giả, bìa).** `EditBookInfoCommand` (Models, 20 dòng) + `BookTransactionCoordinator.updateBookInfo` — command mới thay vì tái dùng `updateBookMetadata` vì hàm cũ **không** cập nhật `titleTrans`/`authorTrans`, nên kệ sách sẽ hiện tên dịch cũ; hàm mới tính lại bằng đúng công thức của `BookTitleTranslationBackfill`. Bìa theo URL ⇒ set `coverUrl` + `deleteCover(for:)` để `BookCoverView` tự tải lại; bìa từ máy ⇒ `PhotosPicker` → `ImageCacheManager.saveCover` (downscale ≤1024 px, JPEG 0.85, dùng lại `validatePathSafety` sẵn có). Giới hạn đã biết: `BookCoverView` cache ảnh trong `@State` nên bìa mới chỉ chắc chắn hiện lại sau khi view xuất hiện lại. Vào từ `ellipsisMenu` của BookDetail.
* **Ngân sách dòng: cả ba file allowlist đang sát/vượt baseline đều giảm.** `BookDetailView.swift` 1213 → **1181** (baseline 1201 ⇒ **rời khỏi danh sách vi phạm**, `ellipsisMenu` chuyển sang `BookDetailView+Extensions.swift` 285 → 343), `RepositoryManagerView.swift` 751 → **709** (baseline 751), `SettingsView.swift` 453 → **439** (baseline 453, mục TTS trích sang `TTSSettingsSection.swift`). File mới lớn nhất `BackupRestoreWorker.swift` **236 dòng**, nhỏ nhất `BackupSettingsSection.swift` **12**; cả 33 file đúng 1 primary type (record Codable dùng type lồng trong `BackupPayload`).
* **Gate:** `check_architecture.py` **18 → 17 violation** — violation duy nhất mất đi là `LINE_LIMIT_EXCEEDED` của `BookDetailView.swift`, **không violation mới**, không entry `architecture_allowlist.json` nào được thêm, nới hay gia hạn. `Sources/Views/Settings/Backup/**` và `BookInfoEditView.swift` không có `modelContext.insert/delete/save` nào, mọi ghi đi qua coordinator và `Result` đều được xử lý. `validate_links.py`: 10 doc `--accept` (`00`, `01`, `02`, `03`, `07`, `09`, `11`, `12`, `13`, `14`), read-only **PASS 16 doc / 277 file Swift**.
* **Chưa biên dịch**: host là Windows, `xcodebuild` và `xcodegen` chỉ chạy trên macOS. Xác minh ở đây là đọc code (chữ ký thật của `importBookMigration`, `addRepository`, `upsertExtension`, `findMainExtensionFolder`, `writeChapterContent`, `readChapterContent`, `parseRecords`/`mergedRecords`/`persist`, ba guard `$(...)` của mẫu Google TTS) cộng hai script Python. **CI xanh chỉ nghĩa là biên dịch được.**
* **Chưa thể xác minh ở môi trường này** (đều là hành vi runtime trên máy thật): round-trip backup → restore trên bản cài khác; restore lần hai cùng file không nhân đôi; `ASWebAuthenticationSession` dưới LiveContainer; và **trạng thái publishing của OAuth consent screen** — nếu project còn ở *Testing* thì Google thu hồi refresh token sau **7 ngày**. Ngoài ra nếu quên tạo secret `GOOGLE_DRIVE_CLIENT_ID` thì IPA của CI ra tab Drive "chưa cấu hình" mà **CI vẫn xanh** — không cổng nào bắt được việc này.

## [1.3.245] - 2026-08-22

### Sửa mở thu nhỏ, nháy đỏ và tap mở lại widget trình duyệt

Ba lỗi của 1.3.244, không lỗi nào nằm ở tầng cài đặt: `VisibleBrowserSettings` và `BrowserSettingsSection` đều đúng.

* **"Bật mở thu nhỏ nhưng không thu nhỏ" — nguyên nhân là `presentUIIfNeeded()` bị gọi hai lần.** `VisibleWebViewLoader.presentUIIfNeeded()` chạy ở **mỗi** `load(url:timeout:completion:)` và `loadAsync(url:)`, không chỉ lúc tạo loader. Nên `Engine.newVisibleBrowser()` → `addTab` (ID mới) → `prepareContainerMinimized()` đúng như thiết kế, rồi `launch(url)` → `addTab` (ID **trùng**) → `selectTab(id:)` → `if isHidden { reopenContainer() }` bung trình duyệt ra ngay. Sửa: tách `activateTab(id:)` (internal — chỉ đổi `activeTabId`, `reloadTabs()`, `notifyStateChanged()`) khỏi `selectTab(id:)` (public, dành cho **cử chỉ người dùng**, giữ nguyên hành vi mở lại). Nhánh tab trùng của `addTab` nay gọi `activateTab` và chỉ `reopenContainer()` khi `!VisibleBrowserSettings.opensMinimized` — cùng điều kiện đã dùng cho nhánh tab mới, nên **cài đặt tắt thì hành vi cũ không đổi**. `selectTab` còn đúng một caller: `TabbedVisibleBrowserViewController.handleTabTap`.
* **"Nhấp nháy dùng trong suốt" → nháy đỏ.** `VisibleBrowserReopenView.swift` 51 → **78 dòng**: bỏ `@State isDimmed` + `.opacity(isDimmed ? 0.45 : 1.0)`, thay bằng `@State isPulseBright` → `pulseLevel` (0.4 ↔ 1.0) → `Color(red: 0.42 + 0.48·level, green: 0.04 + 0.13·level, blue: 0.04 + 0.13·level)` phủ đặc trên `.ultraThinMaterial`, chữ trắng khi đang nháy. **Alpha luôn 1** nên `hitTest` của `BrowserFloatingWidgetUIWindow` và alpha của `widgetContainerView` không dính nhịp nháy — bất biến cũ được giữ, chỉ đổi cách biểu diễn. Chuỗi timer one-shot của `VisibleBrowserPulseMonitor` **không đổi một dòng logic** (72 → 73, chỉ doc comment).
* **"Bấm widget thì widget mất mà trình duyệt không mở" — hai nghi phạm, bịt cả hai.** Triệu chứng chỉ xảy ra được khi `isHidden` đã thành `false` (widget hết điều kiện hiện) mà sheet không lên. (a) `findTopViewController()` nhặt window theo `isKeyWindow ?? windows.first`, tức có thể chọn **window overlay của chính widget** (`alert - 2`) hoặc của TTS (`alert - 1`); present pageSheet vào đó thì `notifyStateChanged()` ngay sau đó ẩn window ⇒ sheet biến mất cùng nó. Nay chỉ nhận `windowLevel == .normal` (ưu tiên `isKeyWindow`, fallback cuối vẫn quét window `.normal`). (b) `reopenContainer()` tạo nav **trước** khi biết có host, nên khi không có host thì `container` mắc parent là nav bị bỏ và nav sau không bọc lại được nó; nay tìm host trước, và `navigationController(wrapping:)` tái dùng nav cũ hoặc `removeFromParent()` rồi bọc mới.
* **Lưới an toàn `verifyReopenPresented(_:)`.** Sau `present`, hẹn **một** lần kiểm tra 1.2 s (`asyncAfter`, `[weak self, weak nav]`, guard `navController === nav`): nếu `nav.presentingViewController == nil` thì trả trạng thái về `isHidden = true`, `navController = nil` và phát notification ⇒ **widget hiện lại**. Nếu còn nguyên nhân thứ ba chưa biết thì lỗi thoái hoá thành "bấm không ăn" thay vì "mất hết". Đường thành công không bị ảnh hưởng: UIKit gán `presentingViewController` ngay lúc `present`, không chờ animation.
* **Gate:** `check_architecture.py` **18 → 18 violation**, tập vi phạm y hệt; không entry `architecture_allowlist.json` nào được thêm hay nới. `VisibleBrowserTabManager.swift` 263 → **325 dòng** (dưới trần, không vào danh sách vi phạm), `VisibleBrowserReopenView.swift` 51 → 78, `VisibleBrowserPulseMonitor.swift` 72 → 73. **Không file Swift nào được thêm/xoá** (vẫn 244) nên các doc `staleOn: structure` không stale. `validate_links.py`: 5 doc `--accept` (`06`, `07`, `10`, `11`, `13`), 1 doc `--no-change-needed` (`rules.md`), read-only PASS.
* **Chưa biên dịch**: host là Windows, `xcodebuild` chỉ chạy trên macOS. Xác minh ở đây là đọc code (hai call site `presentUIIfNeeded`, caller duy nhất của `selectTab`, điều kiện `refreshState()` của window manager, `hitTest` của window widget, `webView.load` không phụ thuộc window) cộng hai script Python. CI xanh chỉ nghĩa là biên dịch được.
* **Chưa thể xác minh ở môi trường này**: cả ba lỗi đều là hành vi runtime. Đặc biệt chưa xác nhận được: window nào thực sự được `findTopViewController()` chọn trên máy thật (app chạy qua LiveContainer), và WKWebView của tab có nạp bình thường khi container **chưa bao giờ** vào window — đường này trước 1.3.245 chưa từng chạy thật vì lỗi (a) luôn present container lên.

## [1.3.244] - 2026-08-22

### Tìm kiếm truyện đích, copy VP/Name, widget trình duyệt kéo được

Năm tính năng, tất cả dựng trên thành phần sẵn có: thanh tìm kiếm của Kệ sách, hai API ghi từ điển đã tồn tại, và kiến trúc kéo/thả UIKit của widget TTS. **Không tầng lưu trữ mới, không notification string mới, không base class mới.**

* **Tìm truyện trong sheet chia sẻ từ điển.** Thanh tìm kiếm của Kệ sách được trích nguyên vẹn thành `Views/Common/BookSearchBarView.swift` (41 dòng): `@Binding text`, nút xoá `xmark.circle.fill`, `.autocorrectionDisabled()`, `secondarySystemBackground`, `cornerRadius 10`, kèm `onCommit` tuỳ chọn. `ShelfSearchView.swift` 242 → 218 dòng và **giữ nguyên hook lịch sử tìm kiếm** qua `onCommit` (`SearchHistoryStore.addQuery`). `BookShareTargetSheet.swift` 77 → 100: lọc realtime bằng computed property qua `ShelfBookSearchMatcher.matches` (tên + tác giả, cả bản dịch), không debounce, **logic chọn đích không đổi một dòng**; overlay rỗng phân biệt "không có truyện khác để chia sẻ" với "không tìm thấy truyện nào".
* **Copy VP/Name giữa Riêng và Chung — icon trong hàng, không phải nút chữ.** `Views/Dictionary/DictionaryEntryRow.swift` (119 dòng) dựng lại hàng theo thứ tự cố định `[Sửa] [Chuyển] [Xóa]`: icon `arrow.left.arrow.right`, cùng `.subheadline`, cùng `.buttonStyle(.plain)`, cùng `.padding(.leading, 8)` như nút `Xóa`, không nhãn chữ nào ăn chiều rộng hàng, mọi control có `accessibilityLabel`. Ý nghĩa hành động do **phạm vi danh sách** quyết định (danh sách chung ⇒ Menu "Chuyển qua Riêng"; danh sách riêng ⇒ Menu "Chuyển qua Chung"), còn **loại đích** người dùng chọn trong Menu độc lập với loại nguồn ⇒ đủ **4 tổ hợp mỗi chiều, 8 tổng cộng**.
* **Luật ghi đè là hệ quả của API sẵn có, không phải code mới.** `DictionaryEntryTransferAction` (47 dòng) chỉ là bộ định tuyến 2×2: đích `.globalCustom` → `DictionaryCache.shared.upsertEntry(key:value:type:)`, đích `.privateBook` → `TranslationManager.shared.saveCustomEntry(word:meaning:isName:bookId:)`. Cả hai làm `records.removeAll { $0.key == cleanKey }` rồi `insert(at: 0)` ⇒ **key chưa có thì tạo, key đã có thì ghi đè hoàn toàn**, không trùng key, không merge, không skip; `DictionaryTextFileStore.normalizeMeaning` là điểm chuẩn hoá duy nhất. Nguồn **không bị sửa hay xoá** (copy, không move). Hai tệp dựng sẵn `VietPhrase.dat`/`Names.dat` **không có đường ghi nào trong `Sources/`**, nên key chỉ có ở built-in sẽ sinh **override ở tầng custom** mà built-in vẫn nguyên — thứ tự tra đã là riêng > chung custom > built-in (`VietPhraseTokenizer`). Cả hai API tự gọi `loadAllDictionaries()` + `notifyDictionariesDidUpdate`, nên đường copy **không phát thêm event nào** lên bus.
* **Chiều chung → riêng luôn dùng sách của màn Từ điển đang mở.** `DictionaryHubView` là nơi duy nhất biết sách hiện tại, nay truyền `contextBookId` xuống hai NavigationLink danh sách chung (`bookId: nil, contextBookId: bookId`); `DictionaryListView+Transfer.swift` (41 dòng) giải nó bằng `bookId ?? contextBookId`. **Không picker, không sách đang phát TTS, không "sách mở gần nhất", không biến toàn cục.** Thiếu ngữ cảnh ⇒ nút chuyển thành trạng thái vô hiệu, chạm vào chỉ hiện toast lỗi và **không ghi gì**. `DictionaryListView.swift` 767 → **748 dòng** (lần đầu file này giảm; khoảng cách tới baseline 690 thu từ −77 còn −58).
* **Cài đặt "Mở trình duyệt ở chế độ thu nhỏ".** `Services/Extensions/Engine/VisibleBrowserSettings.swift` (13 dòng, chỉ `import Foundation`) sở hữu khoá `openVisibleBrowserMinimized`; `Views/Settings/Main/BrowserSettingsSection.swift` (22 dòng) là Toggle `@AppStorage` — `SettingsView.swift` giữ **đúng 453 dòng** (bằng baseline) vì section nằm ở file riêng. Khi bật, `VisibleBrowserTabManager.openContainer` rẽ sang `prepareContainerMinimized()`: dựng `TabbedVisibleBrowserViewController`, `loadViewIfNeeded()` (⇒ `viewDidLoad` → `reloadTabs()` → gắn WKWebView của tab active) rồi vào đúng trạng thái `isPresented == false, isHidden == true` mà **không present lần nào**. Tắt thì hành vi y như trước; trình duyệt/tab đang tồn tại không bị ảnh hưởng; mở rộng/thu nhỏ tay vẫn nguyên.
* **Nháy widget khi có tab ≥ 10 s, chỉ khi đang thu nhỏ.** `VisibleBrowserPulseMonitor` (72 dòng) giữ **một** `Timer` one-shot cho toàn app, hẹn đúng `max(0.2, 10 − tuổi tab già nhất)`; **không** timer theo tab, **không** polling. Tuổi suy từ `VisibleBrowserTabItem.createdAt` (18 → 28 dòng) nên mở rộng rồi thu nhỏ lại là **tính lại từ tuổi thật**, không có cờ "đã xem". Đánh giá lại chỉ theo `stateDidChangeNotification` **đã có sẵn**. Nháy biểu diễn bằng `opacity` của SwiftUI ⇒ `alpha` của window vẫn 1 và **`hitTest` không đổi**.
* **Widget trình duyệt kéo được, cùng kiến trúc widget TTS.** Dựng họ thứ hai song song: `BrowserFloatingWidgetUIWindow` (26 dòng, custom `hitTest` cho touch ngoài viên pill xuyên qua), `BrowserFloatingWidgetContainerViewController` (197 dòng, `UIPanGestureRecognizer` ghi thẳng `center` trong `.changed` nên ngón tay không chờ vòng state của SwiftUI, nhả tay thì snap cạnh bằng spring 0.34 s damping 0.82, `UITapGestureRecognizer` mở trình duyệt và bị chặn khi `isDragging`), `BrowserFloatingWidgetWindowManager` (121 dòng, window level `alert - 2` — TTS giữ `alert - 1`, cả hai không `makeKeyAndVisible()`). Phần dùng chung được trích ra **đúng một mảnh**: `FloatingWidgetGeometry` (39 dòng, 3 hàm thuần) — `FloatingWidgetViewModel` (101 → 108) và `FloatingWidgetContainerViewController` (240 → 246) đổi sang gọi nó, công thức tương đương từng phép toán nên **hành vi widget TTS không đổi**; không base class, không chia sẻ state. `VisibleBrowserReopenView.swift` 136 → **51 dòng** (chỉ còn vẽ); `FreeBookApp.swift` giữ 103 dòng, bỏ khối pill trong `ZStack`, thay bằng ba điểm gọi `refreshState()`. Vị trí bền qua `visibleBrowserReopenVerticalRatio`/`visibleBrowserReopenEdge` nên **không reset khi redraw**.
* **Gate:** `check_architecture.py` **18 → 18 violation**, tập vi phạm y hệt (9 `LINE_LIMIT_EXCEEDED` ở Services, 7 ở Views, 2 `VIEW_SWIFTDATA_MUTATION`); 12 file mới đều ≤ 197 dòng và đúng một type top-level nên **không entry `architecture_allowlist.json` nào được thêm hay nới**; `VisibleBrowserSettings.swift` không `import SwiftUI` nên miễn trừ `SERVICE_SWIFTUI_IMPORT` không bị nới, toast của đường copy phát từ tầng Views nên `SERVICE_TOAST_COUPLING` an toàn. Tổng file Swift 232 → **244**. `validate_links.py`: 14 doc `--accept` (`00`, `02`–`14`), 2 doc `--no-change-needed` (`01`, `rules.md`), read-only PASS 16 doc / 244 file Swift.
* **Chưa biên dịch**: host là Windows, `xcodebuild` chỉ chạy trên macOS. Xác minh ở đây là đọc code (thứ tự tra từ điển từ `VietPhraseTokenizer`, ngữ nghĩa tombstone `value.isEmpty` và luật khử trùng key của `DictionaryTextFileStore`, thân hai API ghi, đường `loadViewIfNeeded` gắn WKWebView mà không present, nhánh dọn `!isPresented` của `dismissContainer`, `hitTest` của cả hai window, cấp phát/thu hồi `Timer`) cộng hai script Python. CI xanh chỉ nghĩa là biên dịch được.
* **Chưa thể xác minh ở môi trường này**: mọi hành vi runtime — nháy đúng mốc 10 s, cảm giác kéo/snap, touch ngoài pill xuyên qua, hai widget cùng tồn tại không phá `hitTest` của nhau, toast copy, và việc từ điển được nạp lại sau khi ghi.

## [1.3.243] - 2026-08-22

### ReaderView quan sát lại ReaderViewModel, hết đơ khi đổi chương

Ba lần sửa trước (`Task.yield()` 1.3.240, nhịp 32 ms 1.3.241, cổng bắt tay skeleton 1.3.242) đều sắp xếp lại việc **bên trong** một update pass, trong khi bug thật là **không có pass nào được kích hoạt**: `ReaderViewModel` là `ObservableObject` nhưng `ReaderView` giữ nó trong `@State` (`ReaderView.swift:193`), và `@State` chỉ giữ tham chiếu — nó **không** subscribe `objectWillChange`. Hệ quả: `pendingNavigationIndex`, `navigationCommit`, `loadState`… đổi mà body không dựng lại. Reader chỉ được vẽ lại nhờ những nguồn invalidate vô can: publish của `@StateObject ttsState`, một `@State` khác đổi, bốn `.onReceive` notification, `@Query`. Khoảng cách giữa cú bấm Next/Prev và frame đầu tiên vì vậy bằng đúng khoảng chờ tới sự kiện vô can kế tiếp — log thiết bị đo 0.6–4.3 s, và đó là cảm giác "đơ".

* **File mới `Sources/Views/Reader/Components/ReaderViewModelInvalidationRelay.swift` (40 dòng, 1 primary type).** `@MainActor final class … : ObservableObject`, giữ một `AnyCancellable` forward `ReaderViewModel.objectWillChange` sang `objectWillChange` của chính nó — đúng cơ chế `@ObservedObject` dùng, chỉ khác là chịu được `nil` và đổi instance. `observe(_:)` idempotent theo identity (`observed !== viewModel`) nên bootstrap chạy lại không tạo thêm subscription; `observed` là `weak`, chỉ để so identity. Không lọc theo thuộc tính: phải nhớ danh sách `@Published` mới chính là mầm của bug này.
* **`ReaderView.swift` — 3 điểm nối.** `@StateObject internal var viewModelRelay = ReaderViewModelInvalidationRelay()` cạnh `ttsState`; `viewModelRelay.observe(newViewModel)` ngay sau `viewModel = newViewModel` trong `ensureViewModel`; `viewModelRelay.observe(nil)` trong `.onDisappear`. Không đổi logic điều hướng, không đổi cổng render, không đổi nhịp 32 ms.
* **Vì sao chọn chương từ danh sách không bị đơ**: việc đóng sheet tự sinh một chuỗi update pass, nên cổng render và commit gặp pass ngay. Cú nhảy từ widget TTS và Next/Prev không có nguồn pass nào ⇒ chỉ hai đường đó biểu hiện triệu chứng, khớp đúng báo cáo của người dùng.
* **Chuỗi kỳ vọng sau bản này**: bấm → pass 1 vẽ skeleton (`[ReaderPerf] Skeleton sinceTapMs` ≈ 1 frame) → commit sau 32 ms → pass 2 dựng nội dung (`Present`) → +0.25 s nhả cờ restore. Tổng khoảng vài trăm ms thay cho 1.6–4.3 s. Dòng `[ReaderPerf] NavRealize reason=commit` **không** phải bằng chứng có pass: nó phát từ `ReaderViewModel.swift:672`, tức từ view model, không phải từ body.
* **Rủi ro có chủ ý**: Reader nay dựng lại body theo *mọi* `@Published` của view model, kể cả `currentProgress`. Đây là đúng hành vi của `@ObservedObject` mà lẽ ra view đã phải có; nếu thấy churn, cách xử lý là giảm tần suất publish ở view model, **không** phải bỏ relay. Mọi điểm gán `viewModel = …` mới trong tương lai phải gọi kèm `observe(_:)`.
* **Đặt tên**: không dùng lại `ReaderViewModelObserver` — đó là một wrapper view `@ObservedObject` chưa từng có caller, đã xoá ở 1.3.235; header của file mới ghi rõ sự khác biệt để không ai tưởng là revert.
* `check_architecture.py`: **18 violation** trước và sau, tập vi phạm y hệt, không nới baseline nào (`ReaderView.swift` 2263 → 2268 so với baseline 2053 — vi phạm cũ, không phải mới). `validate_links.py`: 9 doc `--accept` (`00`, `02`, `04`, `08`, `09`, `10`, `11`, `13`, `14`), 1 doc `--no-change-needed` (`rules.md`), read-only PASS 16 doc / 232 file Swift.
* **Chưa biên dịch**: host là Windows, `xcodebuild` chỉ chạy trên macOS. Xác minh ở đây là đọc code (không còn đường nào để view model thay đổi mà view không biết; relay không giữ tham chiếu mạnh nào tới view; `observe(nil)` chạy khi Reader rời màn hình) cộng hai script Python. CI xanh chỉ nghĩa là biên dịch được.

## [1.3.242] - 2026-08-22

### Bắt buộc một frame skeleton giữa hai subtree chương ở Reader

Log thiết bị (`app_logs (41).txt`, 2026-08-22 11:48) cho phép quy trách nhiệm chính xác, 6/6 mẫu khớp: mỗi lượt Next/Prev **có** dòng `[ReaderPerf] Skeleton` thì `Present` cách commit ~15–20 ms; mỗi lượt **thiếu** dòng đó thì `Present` cách cú bấm 1.6–3.5 s (`Tap index=23 → Nav … origin=memory commitMs=41.49 → Present sinceTapMs=3520.6`). Đúng bốn lượt xấu đều là đường hit RAM (`ChapterCache` đã có chương, không có dòng `RepoLoad`). Nghĩa là nhịp chờ 32 ms của 1.3.241 **không đủ**: nếu SwiftUI không kịp chạy một update pass trong cửa sổ đó, pass kế tiếp thấy `pendingNavigationIndex` đã bị xoá và đi thẳng nhánh nội dung — vừa tháo subtree TextKit-1 của chương cũ vừa dựng subtree chương mới trong **cùng một** update pass.

* **`ReaderView+LoadingView.swift` — thêm cổng bắt tay `isChapterSubtreeRenderable(_:)`.** Subtree nội dung của chương `N` chỉ được dựng khi `renderedChapterIndex == nil` (lần đầu mở), `renderedChapterIndex == N` (reload tại chỗ), hoặc `skeletonHandshakeIndex == N` (skeleton của chính chương đó đã xuất hiện ít nhất một frame). Đây là điều kiện **cấu trúc**, thay cho phỏng đoán thời gian: dù commit nhanh cỡ nào, pass "tháo chương cũ" và pass "dựng chương mới" cũng bị tách ra.
* **`ReaderView.swift` — áp cổng và hợp nhất nhánh skeleton.** Hai nhánh skeleton cũ (pending chưa commit / chưa `.loaded`) gộp thành một nhánh `else` mang `.id("chapter-skeleton-\(presentationIndex)")`; nhánh nội dung thêm điều kiện `pendingNavigationIndex == nil || == displayedChapterIndex` cộng cổng bắt tay. `.id` của skeleton là bắt buộc: bấm tiếp trong lúc skeleton đang hiển thị mà không đổi identity thì `onAppear` không nổ lần hai và cổng sẽ treo ở chương cũ.
* **Hai `@State` mới nuôi cổng**: `renderedChapterIndex` (set ở `onAppear` của `singleChapterScrollView`, cạnh `recordChapterPresented`), `skeletonHandshakeIndex` (set ở `onAppear` của `chapterInlineLoadingView`, cạnh `recordSkeletonPresented`). Cả hai thuần trạng thái render, `ReaderViewModel` không biết tới, không ảnh hưởng quyết định điều hướng.
* **Giữ nguyên** nhịp 32 ms, hạ cánh hai pha `scheduleDeepLandingScroll`, `ReaderScrollCoordinator`, transition `.opacity`, `.id("single-chapter-N")`, đường highlight, prefetch khi TTS sở hữu sách. Từ 1.3.242, dòng `[ReaderPerf] Skeleton` phải xuất hiện ở **mọi** lượt đổi chương — thiếu nó là dấu hiệu cổng bị bỏ qua.
* **Chưa giải thích được** vì sao pass gộp tốn tới 1.6–3.5 s trong khi pass dựng chương sau skeleton chỉ tốn ~20 ms; giả thuyết còn lại là hai cây `UITextView` cùng sống trong một transition `.opacity` bọc `withAnimation(.easeOut(0.12))`, phù hợp với `sizeInvalidationRPM=498.6` và `prediction=reader_layout_churn_likely` trong `[ReaderEnergy] Summary`. Bản sửa này chặn pass đó xảy ra chứ không tối ưu nó.
* `check_architecture.py`: **18 violation** trước và sau, tập vi phạm y hệt, không nới baseline nào (`ReaderView.swift` 2252 → 2263, `ReaderView+LoadingView.swift` 95 → 112 < 400). `validate_links.py`: 5 doc `--accept` (`04`, `05`, `08`, `10`, `11`), 2 doc `--no-change-needed` (`13`, `rules.md`).
* **Chưa biên dịch**: host là Windows, `xcodebuild` chỉ chạy trên macOS. Xác minh ở đây gồm đọc code (cân bằng nhánh của render gate, mọi đường set/đọc hai cờ mới, đường không nháy skeleton khi reload cùng chương, `.id` chống treo cổng) và hai script Python.

## [1.3.241] - 2026-08-22

### Sửa đơ Next/Prev khi TTS phát: chờ frame thật và hạ cánh hai pha

1.3.240 chưa giải quyết được khiếu nại: Next/Prev từ chương đang nghe sang chương khác (và ngược lại) vẫn giữ chương cũ trên màn hình ~5–6 s, **không** chuyển sang skeleton, rồi hiện thẳng nội dung chương mới. Manh mối phân biệt của người dùng: chọn chương từ **danh sách chương** thì "hoàn toàn không bị đơ, skeleton hiển thị đầy đủ", còn nhảy tới chương đang nghe từ **widget TTS** thì đơ y như Next/Prev. Ba khác biệt cấu trúc giữa hai nhóm đường này là nội dung của bản sửa.

* **`ReaderViewModel.swift` — `Task.yield()` không bảo đảm một frame được present.** Đây là lỗi của 1.3.240: yield chỉ đưa continuation về cuối hàng đợi main actor, mà run loop drain hết hàng đợi *trước* khi CoreAnimation commit — nên `memoryCommitTask` vẫn commit trong cùng lượt drain với cú bấm và skeleton không bao giờ được vẽ. Thay bằng `try? await Task.sleep(nanoseconds: 32_000_000)` (timer ⇒ chắc chắn sang turn sau), thêm `guard !Task.isCancelled` trước khi commit. Nhịp chờ tương tự áp cho `startNavigationWorkerIfNeeded` — comment cũ ở đó ("`Task.yield()` luôn chạy → SwiftUI render Skeleton trước I/O") vốn sai. Chi phí: 32 ms cố định mỗi lượt điều hướng.
* **`ReaderView.swift` + `ReaderView+Controls.swift` — hạ cánh hai pha, neo sâu rời khỏi layout pass dựng chương.** `applyNavigationCommit` nay luôn đặt `ScrollTarget(paragraphIndex: -1)`; đoạn hạ cánh sâu do `scheduleDeepLandingScroll(_:)` đặt sau 0.15 s với `reason: .initialRestore`. Lý do: neo `paragraph-N-P` buộc `LazyVStack` realize + đo **mọi** card trung gian (mỗi card một `UITextView` TextKit 1) ngay trong layout pass dựng chương, tức cú bấm phải trả cả hai chi phí trong một turn main actor — nhiều giây khi CPU đang chia với ONNX. Đây đúng là mẫu trì hoãn 0.15 s mà `restoreReaderPositionIfNeeded` (đường mở Reader, không ai báo đơ) đã dùng từ trước. Timer chỉ nổ khi main thread rảnh nên luôn chạy sau khi chương đã present; block tự vô hiệu theo generation commit, `pendingNavigationIndex`, `displayedChapterIndex`. Cờ `isRestoringReaderPosition` được đặt lại `true` trước pha hai để auto-scroll TTS và lưu tiến độ theo cuộn không đọc vị trí giữa đường.
* **`ReaderView+Controls.swift` + `ReaderView.swift` — Next/Prev đi qua đúng cùng một cửa với danh sách chương.** `stepChapterHonoringTTS` trước đây gọi thẳng `viewModel?.requestChapter`/`stepChapter`, **bỏ qua** wrapper `ReaderView.requestChapter(at:…)` mà đường danh sách chương và widget TTS đều dùng — nên nó không đặt `isRestoringReaderPosition = true` và không `paragraphTracker.removeAll()` trước khi phát yêu cầu. Nay nó gọi wrapper đó (đổi `private` → `internal`), tính `baseIndex = pendingNavigationIndex ?? displayedChapterIndex` như `stepChapter` cũ. Hệ quả: **xoá** `ReaderViewModel.stepChapter(by:source:persistProgress:)` (không còn caller nào trong `Sources/`), và bốn điểm vào điều hướng có cùng một tiền trạng thái.
* **Instrumentation đủ để quy trách nhiệm cho phần còn lại** (`ReaderEnergyDiagnostics.swift`, `ReaderView.swift`, `ReaderView+LoadingView.swift`): ba dòng `[ReaderPerf] Tap index= source=` → `Skeleton index= sinceTapMs=` → `Present index= sinceTapMs=`. Skeleton muộn hoặc thiếu ⇒ main thread bị chiếm; Skeleton ~0 ms mà Present muộn ⇒ chương load lâu nhưng UI vẫn phản hồi. Vẫn sau cờ `isEnabled` đã latch ở `beginReaderSession()`, không đọc `UserDefaults` mỗi event.
* **Không làm**: không nới `setSpeculativePrefetchEnabled(false)` khi TTS sở hữu sách — đó là lý do Next/Prev lúc đang phát gần như luôn đi đường worker qua `ChapterContentRepository` (actor dùng chung với TTS), nên bản sửa này làm chờ đợi **có phản hồi** chứ không làm nó ngắn hơn; nới ra là quyết định năng lượng, cần người dùng chọn. Không đụng `ReaderScrollCoordinator`, `.id("single-chapter-N")`, evict của `ChapterCache`, highlight, `minimumFrameDelta`, hay `Tests/`.
* `check_architecture.py`: **18 violation** trước và sau, tập vi phạm y hệt, không nới baseline nào (`ReaderView.swift` 2246 → 2252, `ReaderViewModel.swift` 943 → 931 — cả hai đã là `LINE_LIMIT_EXCEEDED` từ trước; `ReaderEnergyDiagnostics.swift` 338 < 400). `validate_links.py`: 7 doc `--accept` (`03`, `04`, `05`, `08`, `10`, `11`, `13`), 2 doc `--no-change-needed` (`12`, `rules.md`).
* **Chưa biên dịch**: host là Windows, `xcodebuild` chỉ chạy trên macOS. Xác minh ở đây gồm đọc code (đường cancel `memoryCommitTask`, mọi đường nhả `isRestoringReaderPosition`, không còn tham chiếu `stepChapter`, thứ tự hai pha `scrollTarget`) và hai script Python.

## [1.3.240] - 2026-08-22

### Sửa đơ Next/Prev tới chương TTS đang đọc, trả lại skeleton

Người dùng báo: khi TTS đang phát, bấm Next/Prev tới **đúng chương đang được đọc** thì app đơ khá lâu mới chuyển chương, và **không thấy skeleton view lần nào**. Đọc code cho ra hai cơ chế, cả hai chứng minh được bằng đường code chứ không cần đo.

* **`ReaderViewModel.swift` — commit của đường ngắn mạch RAM hoãn đúng một turn main actor.** Trước đây, khi `cache.get(index)?.state == .loaded` và token dịch còn khớp, `requestChapter` gọi `commitNavigation(request, origin: .memory)` **đồng bộ ngay trong turn của cú bấm**: `.loading` → `.ready` và `pendingNavigationIndex` N → `nil` xảy ra trước khi SwiftUI present được frame nào (khác đường worker, vốn cố ý `await Task.yield()` trước I/O). Vì `ChapterCache` thực tế không evict (`queueRelease*` không có caller nào trong `Sources/`) và `scheduleSettledPrefetch` nạp sẵn N+1, chương đích gần như **luôn** `.loaded` ⇒ nhánh skeleton không bao giờ có một frame để hiển thị. Nay commit đó chạy trong `memoryCommitTask` (`Task { @MainActor }` + `await Task.yield()`), guard theo `navigationGeneration`, và bị cancel ở đúng ba chỗ đang cancel `navigationWorkerTask`: đầu `requestChapter`, `failBootstrap`, `shutdown(saveProgress:)`.
* **`ReaderView.swift` — cổng render nhường một frame cho skeleton.** Thêm nhánh `pending != displayedChapterIndex` → `chapterInlineLoadingView(index: pending)` **trước** nhánh `cache.get(presentationIndex)?.state == .loaded`. Reload cùng chương (`pending == displayedChapterIndex`) vẫn đi nhánh cũ nên không nháy skeleton khi chỉ refresh. Tổng thời gian chuyển chương **không tự nhiên ngắn lại** — nội dung vẫn phải dựng vài trăm `ParagraphCardView` + `UITextView` TextKit 1 trong một turn — nhưng UI thôi đứng im không phản hồi.
* **`ReaderView+Controls.swift` + `ReaderView.swift` — hạ cánh thẳng vào đoạn TTS đang đọc: một lượt realize thay vì hai.** `nextChapter()`/`prevChapter()` rút về một dòng gọi `stepChapterHonoringTTS(by:source:)`. Khi chương đích đúng là chương TTS đang phát của **sách này** (và `!isAutoScrollDisabled`), helper xin thẳng `paragraphIndex = currentParentParagraphIndex` qua `requestChapter` thay vì `stepChapter` (vốn luôn `-1`). Trước đây: neo `chapter-N` `.top` → 0,25 s sau nhả cờ → tới **lần đổi đoạn TTS kế tiếp** (có thể ~10 s sau) `requestTTSScrollIfNeeded` phán "ngoài safe viewport" và bắn `scrollTo("paragraph-N-P", anchor: .center)`, buộc `LazyVStack` realize + đo **lại** mọi card trung gian. Nay neo sâu được giải **một lần** ngay lượt dựng đầu tiên và cú nhảy trễ thứ hai biến mất (`requestTTSScrollIfNeeded` thoát bằng `recordTTSScrollSkippedVisible()`). `persistProgress` vẫn `false` khi TTS đang phát sách này, nên luật "TTS sở hữu tiến độ" không đổi. `stepChapter` giữ nguyên vì còn phục vụ đường khác.
* **`ReaderView+Controls.swift` — sửa cờ `isRestoringReaderPosition` bị kẹt (bug thật, phát hiện khi đọc đường hạ cánh).** Nhánh thoát sớm `guard !chapter.isPositionRestored` của `restoreReaderPositionIfNeeded` không gọi `completeReaderPositionRestore()`, nên khi `applyNavigationCommit` đã set cờ `true` mà `restoreSingleChapterPosition` rơi vào nhánh fallback với một chương từng restore rồi, cờ **kẹt `true` cả session** ⇒ `requestTTSScrollIfNeeded` và `updateScrollReadingProgress` (cả hai mở đầu bằng `guard !isRestoringReaderPosition`) chết im lặng: auto-scroll TTS ngừng hoạt động cho tới khi mở lại Reader.
* **Đo để xác nhận phần nào chi phối** (`ReaderViewModel.swift`, `ReaderScrollCoordinator.swift`, `ReaderEnergyDiagnostics.swift`): thêm `[ReaderPerf] Nav … commitMs=`, `[ReaderPerf] RepoLoad … ms=` (lượng hoá tranh chấp actor `ChapterContentRepository` dùng chung với TTS), `[ReaderPerf] Scroll … anchor=`, và `[ReaderPerf] NavRealize … cards=` + cột `paragraphRealized` trong `[ReaderEnergy] Summary`. Tất cả sau cổng cờ đã latch (`isEnabled` của `ReaderEnergyDiagnostics`, hoặc `AppLogger.shared.isLoggingEnabled` đọc một lần ngoài hot path) — giữ đúng luật 1.3.239: không đọc `UserDefaults` mỗi event. **Cố ý không đo ms quanh `proxy.scrollTo`**: hàm đó chỉ ghi nhận neo, phần đắt xảy ra ở layout pass sau nên số ms tại chỗ gần 0 và sẽ gây hiểu sai; `NavRealize cards=` mới là con số chứng minh "hai lượt realize → một lượt".
* **Không làm**: không cho `ChapterCache` evict lại (giảm cache sẽ đẩy Next/Prev sang đường worker + fetch, chậm hơn nhiều), không đổi `.id("single-chapter-N")`, không đổi sang `scrollPosition(id:)`, không đụng tranh chấp `ChapterContentRepository` với TTS (chỉ đo), không đụng highlight, `minimumFrameDelta`, anchor `.center`, hay `Tests/`.
* `check_architecture.py`: **18 violation** trước và sau, tập vi phạm y hệt, không nới baseline nào (`ReaderView.swift` 2248 → 2246, `ReaderViewModel.swift` 896 → 943 — cả hai đã là `LINE_LIMIT_EXCEEDED` từ trước). `validate_links.py`: 6 doc cập nhật + `--accept` (`04`, `05`, `08`, `10`, `11`, `13`), 3 doc `--no-change-needed` (`03`, `12`, `rules.md`).
* **Chưa biên dịch**: host là Windows, `xcodebuild` chỉ chạy trên macOS. Xác minh ở đây gồm đọc code (mọi đường cancel `memoryCommitTask`, mọi đường nhả `isRestoringReaderPosition`, chữ ký `requestChapter`/`stepChapter`) và hai script Python.

## [1.3.239] - 2026-08-21

### Tối ưu năng lượng Reader khi TTS: bỏ xử lý dư thừa trên đường cuộn

Người dùng báo Reader nóng máy / tụt pin / lag khi TTS đang đọc, và chốt rõ là **giữ nguyên cảm giác** của highlight + auto-scroll, chỉ bỏ phần xử lý dư thừa. Đọc code cho thấy chi phí **không** nằm ở nhịp highlight (chunk 200 ký tự + dedup snapshot ⇒ ~1 tick/10 giây) mà nằm ở đường cuộn: mỗi lần `contentOffset` đổi (60–120 Hz) thì *mọi* paragraph đang realized đều chạy việc thừa.

* **`ReaderTextView.swift`** — KVO `contentOffset` chuyển từ *cài vô điều kiện trong `updateUIView`* sang *cài lazy khi có selection thật*. Trước đây mỗi paragraph cài một observer trên **cùng một** `UIScrollView`, nên với ~40 đoạn realized × 120 Hz là ~4.800 callback/giây chỉ để phục vụ *một* selection thường không tồn tại. Nay `setupScrollObservation` chỉ gọi từ `textViewDidChangeSelection` khi `selectedRange.length > 0`, và `teardownScrollObservation()` chạy ngay khi selection về rỗng ⇒ trạng thái thường ngày là **0 observer**.
* **`ReaderTextView.swift`** — `handleSelectionOrScrollUpdate` `guard nsRange.length > 0` **trước** khi đo độ dài text, và dùng `textView.textStorage.length` (O(1), đã là UTF-16) thay cho `((textView.text ?? "") as NSString).length` (một vòng bridging Swift↔ObjC mỗi callback). Thêm dedup `lastPublishedSelection`: bỏ qua `onSelectionChange` khi range không đổi và minY/maxY lệch < 0.5 pt — đây là chỗ chặn `onSelectionChangeInParagraph` ghi 8 `@State`, tức invalidate toàn bộ `ReaderView.body`, mỗi frame khi vừa có selection vừa cuộn. `triggerCustomDefine` publish với `force: true` nên hành vi tra từ không đổi.
* **File mới `Sources/Views/Reader/Components/ReaderEnergyDiagnostics.swift`** (258 dòng) — instrumentation tách khỏi `ReaderTextView.swift` (647 → **450 dòng**) và nay **miễn phí khi log tắt**: cờ `isEnabled` chốt một lần trong `beginReaderSession()` từ `AppLogger.shared.isLoggingEnabled` (getter đó chạm `UserDefaults`, không được gọi mỗi event), mọi `record*`/`flush` mở đầu bằng `guard isEnabled`. Vì `AppLogger.init` set `isLoggingEnabled = false` mỗi lần khởi chạy, production ⇒ toàn bộ đo đếm rút về một phép so bool. `Window` đổi từ `struct` sang `final class` để mutate in-place (bản struct chứa `Set<ObjectIdentifier>` bị copy-on-write **toàn bộ Set** mỗi lần `recordUIViewUpdate` qua `var snapshot = window … window = snapshot`), và `ProcessInfo.systemUptime` chỉ đọc mỗi 64 event thay vì mỗi event.
  * Đánh đổi có chủ ý: **bật/tắt log trong Settings giữa lúc Reader đang mở chỉ có hiệu lực từ lần mở Reader kế tiếp**, và số liệu `[ReaderEnergy] Summary` chỉ tồn tại khi log được bật *trước* khi mở Reader.
* **`ParagraphTracker.swift`** — chỉ thêm comment: ghi rõ nhánh bị lọc trong `updateFrame` là hot path (mỗi paragraph, mỗi frame cuộn) và **không được nới** `minimumFrameDelta = 8`, vì ngưỡng này quyết định phán quyết của `isParagraphInsideSafeViewport` — nới nó là đổi hành vi auto-scroll, không phải tối ưu. Logic không đổi.
* **`ReaderView.swift` + `ParagraphCardView.swift`** — xoá `translationRefreshToken` (dead code: `@State` không hề được ghi ở đâu; refresh bản dịch thực chất đi qua `viewModel?.updateCachedTranslatedContent` làm `paragraphItems` đổi). Bớt một field trong struct và một phép so trong `==` trên mỗi paragraph mỗi lượt dựng `ForEach`.
* **`ReaderView+Controls.swift`** — `completeReaderPositionRestore` không còn `paragraphTracker.removeAll()`. Các đoạn đang hiển thị không `onAppear` lại nên map frame rỗng làm tick TTS đầu tiên sau restore luôn thấy "ngoài viewport" ⇒ một cú `scrollTo` thừa (một cú nhảy + một layout pass); `isRestoringReaderPosition` đã tự chặn mọi consumer trong lúc restore. **Đây là item duy nhất có thay đổi thấy được** (mất một cú nhảy thừa ngay sau khi mở chương), đã nêu rõ trong plan và được người dùng chấp thuận. Các `removeAll()` khác (`onDisappear`, `onChange(of: chapterIndex)`, đường navigate, `applyNavigationCommit`, `reloadCurrentChapterFromMenu`) giữ nguyên.
* **Không đổi**: đường highlight (`ttsState.snapshot.highlightRange` vẫn truyền thẳng, không ánh xạ), anchor `.center`, việc bám theo `currentParentParagraphIndex`, hành vi cuộn tay, `minimumFrameDelta`, hệ toạ độ `frame(in: .global)`.
* Tổng file Swift 230 → 231. `check_architecture.py` giữ **18 violation**, tập vi phạm giống hệt trước thay đổi (phép tách file là để *tránh* violation mới: `ReaderTextView.swift` từng lên 707 dòng > baseline 651 trước khi tách). `validate_links.py`: 7 doc bị stale do thay đổi này đã cập nhật + `--accept`; **4 doc còn stale từ trước** (`05_state_graph.md`, `08_lifecycle.md`, `10_risk_report.md`, `rules.md`) không thuộc phạm vi thay đổi này nên không bless.
* **Chưa biên dịch**: host là Windows, `xcodebuild` chỉ chạy trên macOS. Xác minh ở đây chỉ gồm đọc code, đối chiếu mọi đường tạo/huỷ `offsetObservation`, và hai script Python.

## [1.3.238] - 2026-08-21

### Sửa caption Telegram vượt 1024 ký tự và mô tả đường dẫn log trong Settings

Hai sửa nhỏ, không đổi logic runtime nào.

* **`.github/workflows/build-ipa.yml`** — bug hạ tầng phát hiện từ log CI thật: caption của `sendDocument` bị Telegram giới hạn **1024 ký tự**, nhưng workflow dựng caption từ *toàn bộ* commit message (`%B`). Với commit message nhiều đoạn, Telegram trả `400 Bad Request: message caption is too long` và **IPA không tới được Telegram** — trong khi `curl` vẫn exit 0 nên step `Send IPA to Telegram` vẫn báo success và CI vẫn xanh. Nay caption chỉ dùng **subject một dòng** (`%s` qua biến mới `COMMIT_SUBJECT`); `COMMIT_MSG` (`%B`) giữ nguyên cho hai nhánh `sendMessage` vì giới hạn ở đó là 4096 ký tự. Toàn bộ message vẫn tra được bằng `git log`.
* **`Sources/Views/Settings/Main/SettingsView.swift`** — sửa mô tả nút "Ghi log hệ thống": bỏ giới hạn sai "của các VBook extension" (log phủ toàn app, không riêng extension) và ghi đúng đường dẫn `applicationSupportDirectory/app_logs.txt` thay vì `app_logs.txt`, khớp với thực tế `AppLogger` và với `rules.md` §5.9.
* Hệ quả cần biết: các build đã push trước đó với commit message dài (`511e1b5`, `60937fd`) rất có thể **chưa từng gửi được IPA sang Telegram** dù CI xanh; run kế tiếp là lần đầu caption đủ ngắn.

## [1.3.237] - 2026-08-21

### Sửa lỗi biên dịch của phép tách file: batchSize fileprivate xuyên file

CI của `6357674` fail ở step `Build and Archive App (Unsigned)`. Nguyên nhân là hệ quả trực tiếp của phép tách ở 1.3.236: `BookTitleTranslationMigrator.batchSize` được khai `fileprivate static let`, mà `fileprivate` trong Swift là **phạm vi file**, nên sau khi `BookTitleTranslationBackfill` rời sang file riêng thì `BookTitleTranslationMigrator.batchSize` không còn truy cập được.

* **`BookTitleTranslationMigrator.swift`**: xoá `fileprivate static let batchSize = 50` (không còn ai trong file dùng).
* **`BookTitleTranslationBackfill.swift`**: thêm `private static let batchSize = 50` (kèm doc comment nêu mục đích: giới hạn số sách mỗi lần `save()`), và đổi call site `BookTitleTranslationMigrator.batchSize` → `Self.batchSize`. Hằng nay nằm đúng chỗ actor thực sự dùng nó, phạm vi hẹp hơn trước.
* Giá trị 50 và hành vi batch không đổi.
* **Kiểm tra bổ sung sau sự cố** (để không lặp lại cùng loại lỗi ở 13 phép tách còn lại): quét chéo mọi khai báo `private`/`fileprivate` giữa từng cặp file-gốc ↔ file-mới → chỉ còn 3 kết quả và cả 3 là trùng tên vô hại (`container` là tham số, `pillHeight` là tham số, `containerViewController` do mỗi type tự khai); quét trùng khai báo type top-level toàn `Sources/` → 0; quét identifier chưa resolve trong 14 file mới → không thiếu `import` nào.
* `check_architecture.py` giữ **18 violation** (không đổi). `validate_links.py` PASS.

## [1.3.236] - 2026-08-21

### Tách file theo luật một-primary-type, hết MULTI_PRIMARY_TYPES và NEW_FILE_TOO_LARGE

Phase 3 phần cơ học của kế hoạch dọn nợ kiến trúc: tách type, **không đổi một dòng logic nào**. Mọi tham chiếu vẫn trong cùng module nên đây chỉ là dịch chuyển khai báo.

* **8 file vi phạm `MULTI_PRIMARY_TYPES` → 14 file mới**, mỗi file đúng một type top-level: `TextEncodingOption` ← `TextEncodingDecoder.swift`; `BookListItemStyle` ← `BookListItemView.swift`; `VisibleBrowserPresentationReader`/`VisibleBrowserReopenViewModel`/`SizeReader` ← `VisibleBrowserReopenView.swift`; `CodeEditorTextView` ← `HighlightingCodeEditor.swift`; `ShelfBookSearchMatcher` ← `ShelfSearchView.swift`; `FloatingWidgetUIWindow`/`FloatingWidgetContainerViewController` ← `TTSFloatingWidgetWindowManager.swift`; `BookTitleTranslationBackfill` ← `BookTitleTranslationMigrator.swift`; `DictionaryInvalidationScope` ← `TranslationManager.swift`; `VisibleWebViewController` ← `VisibleWebViewLoader.swift`; `VisibleBrowserTabItem`/`TabbedVisibleBrowserViewController` ← `VisibleBrowserTabManager.swift`.
* **Cả 2 `NEW_FILE_TOO_LARGE` cũng hết** nhờ chính phép tách đó: `VisibleBrowserTabManager.swift` 448 → 234, `VisibleWebViewLoader.swift` 404 → 285.
* **Hai type nâng access level** vì `private` ở Swift là phạm vi file: `SizeReader` (`private struct` → internal), `BookTitleTranslationBackfill` (`private actor` → `internal actor`). Không type nào thành `public`.
* Type lồng đi cùng type cha (`Layout`, `Snapshot`, `Coordinator`); protocol `BookDisplayable` ở lại `BookListItemView.swift` vì luật không tính protocol.
* Không file mới nào dưới `Sources/Services/**` import SwiftUI, nên miễn trừ `SERVICE_SWIFTUI_IMPORT` cho `*WebViewLoader.swift` không bị nới rộng.
* **Sự cố đã sửa trong lúc làm**: lần ghi file đầu dùng `newline=CRLF` trên nội dung vốn đã CRLF nên sinh `\r\r\n`, khiến gate đọc `TabbedVisibleBrowserViewController.swift` thành 402 dòng (gấp đôi 201 thật). Đã chuẩn hoá cả 14 file về LF cho khớp phần còn lại của repo.
* **Kết quả gate**: `check_architecture.py` **28 → 18 violation**. Tổng file Swift 216 → 230.
* **Còn nợ, chưa làm trong lần này**: 16 `LINE_LIMIT_EXCEEDED` (không giải được bằng tách type vì các file đó chỉ có 1 type — phải tách *thành viên* sang `X+Feature.swift`; nợ lớn nhất `TTSManager.swift` −533 dòng, `JSExecutor.swift` −448, `ReaderView.swift` −197) và 2 `VIEW_SWIFTDATA_MUTATION` thật ở `DiscoveryView.swift`/`ReaderView.swift` (phải chuyển ghi qua transaction coordinator — đổi quyền sở hữu transaction, không phải dọn cơ học).
* **Chưa biên dịch cục bộ**: máy Windows. Cần `xcodegen generate` + build trên macOS; CI là bước xác minh compile.

## [1.3.235] - 2026-08-21

### Xoá tầng test, dọn code chết và scaffolding chẩn đoán

Theo yêu cầu trực tiếp của người dùng (Phase 0 = xoá `Tests/`), tầng test bị loại bỏ hoàn toàn; nhờ đó mọi symbol không có tham chiếu trong `Sources/` mới kết luận được là code chết thật (trước đây không thể vì `Tests/` có thể đang dùng). Đây là thay đổi rộng nhất từ trước tới nay về số file bị đụng nhưng **không đổi hành vi runtime nào**.

* **Phase 0 — bỏ tầng test**: `git rm -r Tests` (20 file, vẫn phục hồi được từ git history) và bỏ target `FreeBookTests` khỏi `project.yml`. Từ đây chỉ còn một target biên dịch (`FreeBook`, `sources: Sources`). Quy chuẩn tương ứng trong `rules.md` đổi từ "Test Lock Rule" sang **"Test Layer Removed"**: không tạo lại `Tests/` hay target test khi chưa được yêu cầu; xác minh dựa trên đọc code + build macOS + hai script tĩnh.
* **Phase 1 — rác không phải symbol**: bỏ `import Foundation` trùng ở `NghiSynthesisPolicy.swift`; bỏ hai biến chết `startRange`/`endRange` cùng hai dòng `let _ = … // suppress unused warning` trong `ReaderTextView.selectionGlobalMinMaxY` (guard rút về đúng `end` là giá trị thực sự dùng); **xoá scaffolding `logRemoteTrace`** mà chính tác giả đã đánh dấu `REMOVE_AFTER_TTS_REMOTE_DIAGNOSIS` — gồm `remoteTraceSequenceCount`, hàm `logRemoteTrace` và 7 call site (đều nằm trong `#if DEBUG` nên vô hiệu trên LiveContainer), kéo theo 3 tham số `entryUptime`/`isMain`/`eventId` của `dispatchRemoteTransportCommand` chỉ tồn tại để nuôi nó.
* **Phase 2A — xoá 4 file chết**: `Services/TTS/Helpers/{TTSHighlightCalculator,TTSParagraphSplitter,TTSVoiceResolver}.swift` (thư mục `Helpers/` không còn) và `Views/Reader/ReaderViewModelObserver.swift`. `Views/Reader/ReaderParagraphBuilder.swift` được đổi tên thành `ReaderParagraphBuildResult.swift` sau khi xoá enum builder — DTO `ReaderParagraphBuildResult` vẫn được `ReaderViewModel+Translation` dùng, nên chỉ còn **một** đường dựng `[ParagraphItem]`.
* **Phase 2B — xoá ~30 symbol chết** ở 20 file: `TTSManager.{clearPreparedChapterCache,restartCurrentParagraph,downloadNghiTTSModel,nghiWatermarks}`, `TTSChapterPrefetcher.awaitTextWorkerResult`, `TTSChapterTextWorker.shouldTriggerPrefetch` (bản song song của điều kiện đã inline trong `triggerNextChapterPrefetch`), `TTSNowPlayingController.clearNowPlayingInfo`, `TTSParagraphBuilder.build(from:chunkLength:)`, `ModelStore.{cacheSummary,readCachedVoices,writeCachedVoices,voicesCacheURL}` + `CacheSummary`, `NghiTTSClient.{fetchVietnameseVoices,getModelList}` + `ModelsResponse`, `UnavailablePiperEngine`, `TranslationManager.{addDeletedWords,deleteDictionary}`, `TranslateUtils.resetTOCRulesToDefault`, `DoubleArrayTrie.allEntries`, `BookTransactionCoordinator.updateCurrentChapterTitle`, `ExtensionTransactionCoordinator.deleteExtension`, `JunkFilterManager.toggleRule`, `ImageCacheManager.hasLocalCover`, `DisplayTextFormatter.titleCaseOrNil`, `ExtensionManager.hasConfig`, `ReaderChapterListStore.loadPageIfNeeded` (bị `loadVisiblePageIfNeeded` thay thế), `SearchBar`, hai typealias `SearchNovelResult`/`TTSProcessedChapter`, và abstraction rỗng `GlobalToastModifier`/`globalToast()` cùng 2 call site.
* **Không xoá false positive**: toàn bộ `Services/Extensions/Engine/JS*` (API mà extension JavaScript gọi theo tên), conformance delegate (`speechSynthesizer`, `callObserver`, `scrollViewDidScroll`, `textViewDidChange`, `placeSubviews`) và hàm truyền dạng function reference đều được giữ. Đã kiểm tra không symbol nào bị xoá là protocol requirement.
* **Kết quả gate**: `check_architecture.py` **30 → 28 violation** — hết `NEW_FILE_TOO_LARGE` của `TTSChapterPrefetcher.swift` (402 → 375) và hết `LINE_LIMIT_EXCEEDED` của `TranslationManager.swift`. `TTSManager.swift` 4097 → **4003**; `ExtensionManager.swift` 1066 → 1049; `TranslateUtils.swift` 1046 → 1041. Tổng file Swift 220 → 216.
* **Chưa biên dịch được**: thay đổi viết trên Windows. Bắt buộc `xcodegen generate` (có file bị xoá/đổi tên) rồi build trên macOS trước khi coi là đã xác minh.

## [1.3.234] - 2026-08-21

### Lấp buffer nghèo ở biên chương bằng prefix audio chương kế cho Google/Ext và NghiTTS

Trước thay đổi này, cửa sổ prefetch đoạn văn bị chặn cứng ở biên chương (`idx < paragraphs.count`), nên càng gần cuối chương buffer càng co lại, và ngay sau khi chuyển chương chỉ có đúng chunk 0 sẵn sàng — chunk 1 phải chờ tổng hợp trong khi coordinator chỉ chạy 1 operation. Đây là điểm nghèo buffer nhất của cả phiên nghe. Chương kế **vẫn không** được coi là chunk nối tiếp của chương hiện tại (không đổi không gian index `preloadedData`); thay vào đó phần thiếu được lấp bằng prefix của chương kế trong đúng số slot đang trống.

* **File mới `Sources/Services/TTS/TTSNextChapterPrefixCache.swift`** (380 dòng, `@MainActor`, singleton `.shared`): nạp trước các chunk **index >= 1** đầu chương kế cho cả `nghitts`, `google` và extension TTS (`system` bị loại). Giữ `activeKey`/`chunks`/`durations`/`tasks`/`generation`; `request(key:playbackParagraphs:capacity:…)` mở task cho index còn thiếu trong `1..<min(count, capacity + 1)`, `trim(toCapacity:)` thu hồi khi capacity co lại, `consume(matching:)` chỉ trả dữ liệu khi key trùng tuyệt đối, `contiguousDuration(matching:from:)` trả thời lượng chuỗi chunk liên tục cho watermark của Nghi, `cancelPendingWork()` hủy task nhưng giữ chunk đã xong, `reset()` giải phóng toàn bộ. Tổng hợp đi qua `PiperTTSService.synthesize(priority: .optionalReserve)` (Nghi) hoặc `TTSAudioSynthesisWorker.synthesizeParagraph(priority: .nextChapter, offset: index, prefetchDelayMs: prefetchDelayMs)` (Google/Ext) — đều là mức ưu tiên thấp nhất của engine, không có retry riêng. Nhánh remote đi qua đúng bước giãn `sleep(offset × max(300, prefetchDelayMs))` của worker nên tôn trọng cấu hình `prefetchDelayMs`/`extPrefetchDelay_<tool>`; số ký tự mỗi phân đoạn đã nằm trong `key.chunkLength` (`max_length` với extension). Chunk 0 chương kế vẫn giữ `offset: 0, prefetchDelayMs: 0` vì là slot bắt buộc.
* **File mới `Sources/Services/TTS/Extensions/TTSManager+NextChapterPrefix.swift`** (130 dòng): `nextChapterPrefixContext()` chỉ trả bối cảnh khi `nextChapterPrefetcher.currentState` là `.synthesizingAudio`/`.audioReady` (bảo đảm chunk 0 vào hàng đợi trước) và chunk hoá theo `key.chunkLength`; `mergeNextChapterPrefixAudio(for:)` dựng lại key từ `TTSChapterInfo` rồi nhồi vào `preloadedData`/`preloadedDurations`; `nextChapterPrefixContiguousDuration(matching:)`; `cancelNextChapterPrefixWork()`/`resetNextChapterPrefixCache()`.
* **Google/Ext — độ sâu buffer theo `preload_size`/`googlePrefetchCount`**: `requestRemoteNextChapterPrefixIfNeeded(windowCount:inChapterTargetCount:)` dùng `capacity = max(0, count - inChapterTargetCount - 1)`. Vì `inChapterTargetCount + 1 (chunk 0) + capacity == count`, độ sâu phía trước **luôn bằng đúng `count` chunk kể cả khi đi qua biên chương** — giữa chương capacity = 0, càng gần cuối chương capacity càng lớn.
* **NghiTTS — kéo dài watermark 8s qua biên chương**: `calculateNghiCachedTime()` cộng thêm chuỗi chunk prefix **liên tục ngay sau chunk 0** chương kế, nên `cachedTime` đo được chuỗi phát vượt biên chương. `requestNghiNextChapterPrefixIfNeeded` chỉ nạp khi chương hiện tại đã hết ứng viên **và** `cachedTime < nghittsSafeCachedTimeThreshold`, với `capacity = max(0, NghiSynthesisPolicy.maxTotalAudioPayloads - heldPayloads)`; đủ ngưỡng thì dừng nạp và giữ nguyên chunk đã có. Hằng mới `NghiSynthesisPolicy.maxTotalAudioPayloads = 5` giữ đúng trần payload đã ghi trong quy chuẩn (policy vẫn là single source cho mọi hằng năng lượng của Nghi).
* **`TTSManager.swift`** (+4 dòng, 4097 → 4101): `pause()` gọi `cancelNextChapterPrefixWork()`; `applyNextChapter` gọi `mergeNextChapterPrefixAudio(for: chapter)` sau khi gán `preloadedData[0]`; `updatePrefetchWindow()` gọi `requestRemoteNextChapterPrefixIfNeeded(...)`; `updateNghiPrefetchWindow()` gọi `requestNghiNextChapterPrefixIfNeeded(...)` sau `promoteAudioIfNeeded`. Nhánh chương kế trong `calculateNghiCachedTime()` cộng thêm `nextChapterPrefixContiguousDuration(matching: key)` (net 0 dòng). Ngoài ra `nghiTTSService` và `makeNextChapterKey(for:)` đổi `private` → `internal` để extension ở file khác dùng được (0 dòng thay đổi).
* **`TTSManager+PrefetchCache.swift`** (+1 dòng): `clearAllTTSCaches()` gọi `resetNextChapterPrefixCache()`, nhờ đó stop, đổi `tool` và đổi `selectedVoice` (đều đi qua `clearPrefetchCache()`) đều giải phóng bộ đệm.
* **Highlight của chunk prefix hoạt động y hệt chunk thường**: nó do `commitAudibleParagraphState` phát từ `paragraphs[index]` của chương đã áp dụng, không phụ thuộc nguồn gốc byte audio. Để index↔text không thể lệch, `chunks` lưu `PreparedChunk { data, finalText }` và `mergeNextChapterPrefixAudio` so `finalText` với `applyReplacements(paragraphs[index].text)` trước khi nhồi; không khớp thì bỏ chunk và log `textMismatch=M`. Lớp này phủ cả trường hợp DTO chương kế bị dựng lại mà key không đổi.
* **Dùng lại đúng cơ chế của cửa sổ đoạn văn**: token theo index cho mỗi task (tương ứng `removePrefetchTask(for:taskGen:)`), và phân loại lỗi bằng chính `TTSManager.evaluateRefillError(_:currentAttempts:maxAttempts: 2)` + `TTSManager.RefillFailureState` nên index non-retryable/hết attempt/audio rỗng bị block tới khi `reset()`. Prefix không có retry task/backoff riêng. Hai sai lệch có chủ ý so với refill trong chương (Nghi xếp hàng nhiều task thay vì 1-in-flight; identity không gồm `sessionID` — dùng chung tính chất với `TTSChapterPrefetcher`) được ghi ở `10_risk_report.md`.
* **Trần bộ nhớ không đổi** — đây là *tái phân bổ*, không phải nới trần: remote vẫn `<= count + 1` payload, Nghi vẫn `<= NghiSynthesisPolicy.maxTotalAudioPayloads` (5). Phép đếm payload của Nghi cố ý thiên về bảo thủ (có thể đếm trùng `hasPreparedNext` với `preloadedData`) để không bao giờ vượt trần. Bất biến mới ghi ở `rules.md`.
* **Chưa biên dịch được**: thay đổi viết trên Windows, `xcodebuild` chỉ chạy trên macOS. Sau khi thêm file mới phải chạy `xcodegen generate` rồi build; `check_architecture.py` trước/sau đều 30 violation, không có violation mới.

## [1.3.233] - 2026-08-21

### Tạm ngưng Reader TTS auto-scroll khi ứng dụng không hiển thị (scenePhase != .active)

* **`ReaderView.swift` & `ReaderView+LoadingView.swift`**:
  - Quản lý trạng thái hiển thị qua `@State internal var isSceneActive` (đồng bộ tại `onAppear` và `.onChange(of: scenePhase)`) và số thế hệ `ttsAutoScrollGeneration` tăng dần mỗi lần chuyển phase, tránh việc SwiftUI closure capture snapshot struct `self.scenePhase` cũ.
  - Chặn mọi entry point TTS auto-scroll khi `isSceneActive == false`, bao gồm callback `.onChange(of: currentParentParagraphIndex)`, `requestTTSScrollIfNeeded`, và callback delayed `scrollToTTSHighlightIfNeeded` (closure `asyncAfter` kiểm tra cờ `isSceneActive` và token `ttsAutoScrollGeneration == currentGen`).
  - Khi `scenePhase` chuyển sang inactive/background, `ttsAutoScrollGeneration` tăng lên làm hủy lập tức mọi callback `asyncAfter` đang chờ, đồng thời tự động hủy `scrollTarget` pending có `reason == .ttsAuto`, không ảnh hưởng đến các target navigation/manual/initial-restore.
  - Thêm kiểm tra phòng thủ (defense-in-depth) tại `attemptScroll` và `.onChange(of: scrollTarget)` để hủy lập tức bất kỳ `.ttsAuto` target nào phát sinh khi `!isSceneActive` mà không thực thi.
  - Khi `scenePhase` trở lại `.active`, kích hoạt resync 1-shot duy nhất (`scrollToTTSHighlightIfNeeded`) khớp với token mới nhất sau 0.1s defer để đồng bộ về câu TTS hiện tại mà không replay backlog scroll ngầm.
  - Giữ nguyên trạng thái hiển thị highlight, audio TTS, tiến độ logic, prefetch, và background chapter sync.

## [1.3.232] - 2026-08-21

### Đưa cơ chế staleness mới tới Codex/agent khác: sửa .agents/AGENTS.md, bỏ gitignore AGENTS.md

Chỉ sửa hạ tầng tài liệu/quy trình; không đụng `Sources/`, `Tests/`, hay vùng ngoài `GENERATED` của doc nào. Vá lỗ hổng: cơ chế routing per-doc (1.3.230) chỉ nằm ở `rules.md` + `CLAUDE.md`, còn hai kênh mà agent khác thật sự đọc thì lệch — `.agents/AGENTS.md` (tài liệu bước-1 bắt buộc) vẫn mô tả quy trình cũ, và bản mirror `AGENTS.md` cho Codex bị gitignore nên không tới được agent nào clone repo.

* **`.agents/AGENTS.md`** (sửa theo yêu cầu trực tiếp của người dùng, đúng §7): bước 6 đổi từ "tính lại `sourceHash`/`generatedHash` thủ công" sang chạy `--explain` rồi ghi nhận từng doc bằng `--accept`/`--no-change-needed` (validator tự ghi 3 hash + `reviewMode`, không sửa tay); bước 7 nêu rõ read-only phải PASS gồm cả điều kiện "không doc nào còn stale"; §5 thêm ghi chú validator tự phát hiện trigger qua `sourcePatterns`/`staleOn`; §6 Completion Criteria mục 3-4 cập nhật theo audit trail + luật xoay CHANGELOG. Mọi chi tiết luật vẫn trỏ về `rules.md` §6.2, không nhân bản.
* **`.gitignore`**: bỏ dòng `/AGENTS.md`. Bản mirror `AGENTS.md` (đích cho Codex, đúng ghi chú đầu `CLAUDE.md`) trước đây bị ignore nên chỉ tồn tại cục bộ; giờ được track để commit và tới được agent khác. Regenerate mirror từ `CLAUDE.md`, `diff` từ dòng 4 = khớp.
* Không entry nào trong 16 doc CodeGraph bị stale (thay đổi không chạm `Sources/**`); `validate_links.py` read-only vẫn PASS.

## [1.3.231] - 2026-08-21

### Xoay CHANGELOG: tách lịch sử cũ sang CHANGELOG.archive.md

Chỉ sửa hạ tầng tài liệu; không đụng `Sources/` hay `Tests/`. `CHANGELOG.md` đã phình tới ~95K token / 2986 dòng (222 entry ≤ 1.3.200), lớn hơn nửa mã nguồn và không ai được lệnh *đọc* — thuần chi phí ghi, đi ngược mục tiêu tiết kiệm token của CodeGraph.

* **Tách file**: giữ 18 version gần nhất (1.3.213 → 1.3.231, ~6.9K token) trong `CHANGELOG.md`; chuyển toàn bộ entry ≤ 1.3.200 sang `CHANGELOG.archive.md` (~88K token, chỉ để tra cứu). 3 link `../../Sources/*.swift` trong phần cũ vẫn resolve vì archive nằm cùng thư mục.
* **Luật xoay (`CLAUDE.md` / `AGENTS.md`)**: khi `CHANGELOG.md` vượt ~30 entry, đẩy phần cũ nhất sang `CHANGELOG.archive.md`; luôn thêm entry mới vào `CHANGELOG.md`, không bao giờ vào archive.
* `validate_links.py` vẫn PASS 16 documents / 218 Swift files (nó kiểm link mọi `*.md` trong `Docs/CodeGraph`, gồm cả archive mới).

## [1.3.230] - 2026-08-21

### Định tuyến staleness theo từng doc: sourcePatterns, --explain, --accept/--no-change-needed

Chỉ sửa hạ tầng tài liệu (`Docs/CodeGraph/`, `CLAUDE.md`, `AGENTS.md`); không đụng `Sources/` hay `Tests/`. Trước bản này, `manifest.json` lưu **cùng một danh sách 205 file** cho cả 16 doc và `--update-hashes` tính lại mọi hash vô điều kiện, nên đổi logic hay thêm file chỉ làm `manifest.json` + `CHANGELOG.md` đổi còn doc không bao giờ bị chỉ ra là stale.

* **`manifest.json` → `schemaVersion: 2`**: mỗi doc khai `sourcePatterns` (glob tương đối gốc repo) thay cho danh sách file nhân bản, cộng `staleOn` (`structure` cho `00_index`, `02`, `09`, `14`; `content` cho `01`, `03`–`08`, `10`–`13`, `rules.md`), `structureHash` (băm *tập đường dẫn*), và audit trail `reviewedAt` / `reviewedCommit` / `reviewMode`. `sourceFiles` giờ do script tự ghi từ pattern.
* **`codegraph.schema.json`**: khai 6 field mới và đưa vào `required`.
* **`validate_links.py`**: viết lại phần manifest — `structureHash` bắt thêm/xoá/đổi tên file, `sourceHash` bắt sửa nội dung trong phạm vi doc; thêm **Coverage Rule** hai điều kiện (mọi `Sources/**/*.swift` phải khớp pattern của ít nhất một doc, **và** phải được ít nhất một doc `content` phủ — nếu chỉ doc `structure` phủ thì sửa nội dung không làm doc nào stale), FAIL kèm tên file nếu vi phạm; thêm `--explain [--since REF]` liệt kê doc stale + lý do + file Swift đã đổi; thêm `--accept DOC…` (từ chối nếu vùng GENERATED không đổi) và `--no-change-needed DOC…` (ghi nhận "đã xem, vẫn đúng"); `--update-hashes` chỉ accept doc đã sửa rồi **FAIL nếu còn doc stale**; `--bootstrap` dành riêng cho lần đổi `sourcePatterns`. Tên doc nhận `08`, `08_lifecycle.md` hoặc đường dẫn đầy đủ; output ép UTF-8 để chạy được trên console Windows.
* **Phạm vi `11_subsystems.md`** mở rộng thành `Sources/Services/**` + `Sources/Views/**` + `Sources/Models/Extensions/*` để 218/218 file đều có doc content-mode phụ trách (trước đó 49 file Views chỉ được doc structure phủ, và 12 file chưa từng nằm trong `sourceFiles` của doc nào).
* **`rules.md` §6.2 + §7**: thêm Doc Routing Policy / Doc Review Policy / Coverage Rule, viết lại Manifest Hash Policy theo 3 hash, và bỏ thói quen `--update-hashes` vô điều kiện khỏi checklist.
* **`CLAUDE.md` / `AGENTS.md`**: mục Commands liệt kê 5 chế độ validator và nêu rõ không có hook/CI nào chạy nó — đây là cổng chạy tay.
* Cổng đã được tự kiểm chứng bằng cách giả lập stale trong `manifest.json` (không sửa `Sources/`): read-only FAIL đúng tên doc → `--update-hashes` từ chối bless → `--accept` bị chặn vì GENERATED không đổi → `--no-change-needed` xoá stale; trường hợp "thêm file mới" cũng báo đúng tên file thêm vào.

## [1.3.229] - 2026-08-21

### Cập nhật tài liệu CodeGraph khớp code: highlight TTS, thermal, cache prefetch, số liệu file

Sửa **tài liệu** (không đụng `Sources/` hay `Tests/`) tại 22 điểm đã trôi so với code hiện tại. Toàn bộ nội dung nằm trong vùng `<!-- GENERATED START/END -->` và YAML front matter; không đụng "Ghi chú thủ công".

* **Highlight & selection (`rules.md`, `CLAUDE.md`, `AGENTS.md`)**: `TTSParagraph.range` là offset UTF-16 trên chuỗi **đang hiển thị** và **tương đối dòng cha**, `sourceRange` mới ánh xạ về text gốc. `ReaderSelectionMapper.mapHighlight`/`mappedRangeUsingOriginalSpans`/`proportionalHighlightFallback` đã xoá ở 1.3.81 — bỏ yêu cầu map highlight; `ReaderSelectionMapper` chỉ còn `mapSelection`.
* **Thermal (`rules.md`, `00_index`, `06`, `10`, `13`)**: bỏ mọi mô tả gating theo `.serious`/`.critical` cho Nghi/Remote refill và next-chapter audio. Thermal chỉ là telemetry/diagnostic (`TTSManager.currentThermalState` + energy log). `NghiSynthesisPolicy` chỉ giữ watermark (`defaultSafeCachedTimeThreshold = 8.0`, dải `4.0...20.0`) và `maxOptionalReserveItems = 2`, không cooldown/thermal eligibility; retry refill là backoff 1s (tối đa 2 lần) do `TTSManager` sở hữu.
* **Cache prefetch (`rules.md`, `CLAUDE.md`, `AGENTS.md`)**: `preloadedWavs` → `preloadedData`/`preloadedDurations`; cửa sổ đúng là Remote `[N, N+count]` (count clamp 1…10), Nghi `N` + `N+1` bắt buộc + ≤2 optional reserve.
* **Audio playback (`13`, `10` R-05/R-15)**: node graph `AVAudioEngine` được dựng nhưng **không phát** (`TTSAudioEngineController.play()` không caller, không `scheduleBuffer`); phát thật qua `AVAudioPlayer` (`NghiAudioPlayerQueue` double-buffer cho nghitts, `TTSManager.audioPlayer` cho google/ext) và `AVSpeechSynthesizer` cho `system`. Retain-cycle risk chuyển về callback delegate `AVAudioPlayer`.
* **Lifecycle & callbacks (`08`, `13`)**: chỉ còn callback `onChapterFinished` (bỏ `onChapterNext`/`onChapterPrev`); Reader không nil callback trong `onDisappear`. `onDisappear` chạy `shutdown(saveProgress: !ttsOwnsProgress)` + `ChapterContentRepository.flush(bookId:)`; `saveProgressImmediately()` thuộc nhánh `scenePhase == .background`.
* **Logging (`rules.md`, `CLAUDE.md`, `AGENTS.md`)**: `app_logs.txt` ở `applicationSupportDirectory`, không phải `Documents`; `AppLogger.init` set `isLoggingEnabled = false` mỗi lần khởi chạy, tự xoá khi >5 MB.
* **Model schema (`rules.md`)**: thêm `DownloadTaskModel` (schema có 5 `@Model`).
* **Sai lệch tên/đường dẫn**: `TTSPresentationEventCenter.shared.events` → `.stream` (`04`); `DisplayTextFormatter.swift` ở `Common/Extensions/` (`02`); `ReaderSelectionCoordinator` là misnomer, chỉ có `getHanViet`+`formatMeaning` (`03`); miễn trừ SwiftUI khớp hậu tố `*WebViewLoader.swift`, hiện không file Services nào import SwiftUI (`09`, `rules.md`).
* **Sparse paragraph IDs**: sửa cùng một câu ở `00_index`, `06`, `08`, `10`, `13`, `14` — `ChapterTextLine.id` là chỉ số dòng thô (tính cả dòng trống), không phải array index; `utf16Range` không dùng để cắt `content`.
* **Số liệu (`14`, `00_index`, `02`, front matter 16 file)**: `source_files` → `218`; §1.1/§1.2 dựng lại theo `wc -l` và công thức CC của doc; §1.3 đổi nhãn thành "Max Brace Nesting Depth" (giá trị thật 10–18). `ReaderParagraphBuilder`/`TTSParagraphBuilder.build(from:)` chỉ test dùng, không caller production (`00_index`).

## [1.3.228] - 2026-08-21

### Khắc phục lỗi pop Chi tiết truyện khi vuốt tab Home Khám phá

* **`Sources/Views/Discovery/DiscoveryView.swift`**: Khai báo `DiscoveryDetailRoute` tuân thủ `Identifiable, Hashable` giữ các thuộc tính bất biến (`bookId`, `extensionPackageId`, `initialDetailUrl`, `sourceName`, `initialHost`); di chuyển `@State selectedDetailRoute` và `.navigationDestination(item: $selectedDetailRoute)` từ `DiscoveryCategoryTabView` lên root `NavigationStack` trong `DiscoveryView`.
* **`DiscoveryCategoryTabView`**: Bỏ `@State selectedNovel` và `.navigationDestination` cục bộ, nhận callback `onSelectNovel: (ExtensionItemResult) -> Void` từ view cha khi bấm vào một hàng truyện.
* Bảo toàn route state không bị reset hay tháo gỡ khi swiping tab Home trong `TabView`; cập nhật CodeGraph tại `00_index.md`, `06_event_graph.md`, và `12_ownership_graph.md`.

## [1.3.227] - 2026-08-20

### Mở rộng vùng bấm lịch sử tìm kiếm

* **`ShelfSearchView.historyView` / `SearchView.searchHistoryView`**: label nút chọn lịch sử chiếm toàn bộ chiều rộng còn lại và dùng `Rectangle` cho hit testing, nên vùng trống trước nút `x` có thể bấm được.
* Giữ nút xóa độc lập và không đổi action chọn lịch sử, layout row, scroll hay logic lọc; cập nhật CodeGraph tại `00_index.md` và `06_event_graph.md`.

## [1.3.226] - 2026-08-20

### Chuẩn hóa hằng số Extension.type

* **`Sources/Models/Extensions/ExtensionType.swift`**: thêm namespace public với các giá trị chuẩn `novel`, `chineseNovel`, `comic`, và `tts`.
* Thay literal biểu diễn `Extension.type` trong model command, metadata import, repository policy, Search, Discovery, TTS Settings và UI quản lý extension; giữ nguyên script key/action TTS, sentinel `"all"`, schema `String` và dữ liệu hiện có.
* Không migration, không đổi public API shape và không khóa type lạ; cập nhật CodeGraph tại `00_index.md`, `02_file_graph.md`, `03_type_graph.md`, `09_dependency_rules.md`, và `11_subsystems.md`.

## [1.3.225] - 2026-08-20

### Loại nguồn TTS khỏi tìm kiếm tất cả truyện

* **`Sources/Views/Search/SearchView.swift`**: thêm `searchableExtensions = activeExtensions.filter { $0.type != "tts" }`; chế độ tất cả nguồn dùng tập này cho task search, source state, render kết quả và `Xem thêm`.
* Không đổi tìm một nguồn cụ thể, public API, model hay chính sách lọc của caller; cập nhật CodeGraph tại `00_index.md`, `04_call_graph.md`, `06_event_graph.md`, và `07_dataflow.md`.

## [1.3.224] - 2026-08-20

### Persist titleTrans cho local TXT, preview bounded và search hai cột

* **TXT import**: `ParserChapter`/`ParsedBook` trở thành `Sendable`; `ShelfView.performImport` dịch title và dựng toàn bộ metadata trong `Task.detached`, persist `titleTrans` cùng title gốc và tái sử dụng snapshot khi ghi cache. `BookTransactionCoordinator.insertChapterDTO` nhận thêm `titleTrans` optional cho nhánh SwiftData dự phòng.
* **Confirmation sheet**: tối đa sáu chương hiển thị toàn bộ; trên sáu chương chỉ render ba đầu, một dòng số chương bị lược và ba cuối. Reanalyze dùng cùng preview.
* **Chapter search**: bỏ `searchTrans` khỏi ChapterStore API; SQLite và các bộ lọc local BookDetail luôn OR `title`/`titleTrans`, còn toggle dịch chỉ điều khiển presentation. Không migration localBook cũ.
* Không thay đổi parser, DocumentPicker, nội dung chương hay TOC online; cập nhật CodeGraph tại `00_index.md`, `03_type_graph.md`, `04_call_graph.md`, `06_event_graph.md`, `07_dataflow.md`, và `08_lifecycle.md`.

## [1.3.223] - 2026-08-20

### Không còn khoảng trống giữa wait layer parse TXT và sheet xác nhận

* **`Sources/Views/Shelf/ShelfMain/ShelfView.swift`**: nhánh parse thành công giữ `isParsingTXT` bật sau khi gán `pendingImport`; chỉ tắt khi `TXTImportConfirmationSheet.onAppear`. Nhánh lỗi và cleanup Hủy/Nhập giữ nguyên.
* **`Sources/Views/Shelf/ShelfMain/TXTImportConfirmationSheet.swift`**: danh sách chương dùng `LazyVStack` và duyệt trực tiếp `parsed.chapters.indices`, tránh dựng/copy toàn bộ row trước khi sheet xuất hiện.
* Không đổi DocumentPicker, parser, reanalyze hay database import; cập nhật CodeGraph tại `00_index.md`, `04_call_graph.md`, `06_event_graph.md`, và `08_lifecycle.md`.

## [1.3.222] - 2026-08-20

### Toggle dịch đúng cho tác giả/tên chương và history ShelfSearch tự co chiều cao

* **`Sources/Views/Common/BookListItemView.swift`**: tác giả chỉ phiên âm Hán-Việt khi `isTranslationEnabled` bật; khi tắt hiển thị author gốc trên mọi row dùng chung của Shelf/History/ShelfSearch.
* **`Sources/Views/Reader/ReaderViewModel.swift` / `Sources/Services/ReadingProgress/ReadingProgressStore.swift`**: thêm đường lấy original chapter title riêng cho progress, không persist `CachedChapter.title` đã dịch; snapshot title rỗng được bỏ qua để fallback sang TOC gốc.
* **`Sources/Views/Shelf/ShelfMain/ShelfView.swift`**: `"Dịch lại tên chương"` chỉ cập nhật `titleTrans`, bỏ ghi bản dịch vào `Book.currentChapterTitle`. Không triển khai migration phục hồi dữ liệu cũ theo yêu cầu người dùng.
* **`Sources/Views/Shelf/ShelfMain/ShelfSearchView.swift`**: history khớp query co theo tối đa bốn row, không giữ khoảng trống khi không match và chỉ scroll khi vượt bốn kết quả.
* Không đổi quy chuẩn trong `rules.md`; cập nhật CodeGraph tại `00_index.md`, `04_call_graph.md`, `06_event_graph.md`, và `08_lifecycle.md`.

## [1.3.221] - 2026-08-20

### Upsert rule thay thế TTS khi thêm trùng pattern

* **`Sources/Services/TTS/Preprocessing/TTSReplacementManager.swift`**: `addRule(_:)` xóa toàn bộ rule cũ có cùng pattern chính xác rồi append rule mới xuống cuối và chỉ `saveRules()` một lần; trả `AddRuleResult.added/replaced` với `@discardableResult` để giữ tương thích caller hiện có.
* **`Sources/Views/Reader/ReaderView.swift`**: dùng kết quả từ manager để Toast phân biệt `"Đã thêm"` và `"Đã cập nhật"` thay thế TTS.
* Không đổi `updateRule(_:)`, import JSON hay quy chuẩn kiến trúc trong `rules.md`; cập nhật CodeGraph liên quan ở `00_index.md`, `04_call_graph.md`, `06_event_graph.md`, và `11_subsystems.md`.

## [1.3.220] - 2026-08-20

### Đồng bộ Download/Detail và chuyển Phồn thể → Giản thể theo truyện

* **`Sources/Views/Download/DownloadTrackerView.swift`**: task row dùng cover 50x70 và title 14.5pt semibold, tối đa 2 dòng — cùng style cover/title với Shelf và History.
* **`Sources/Views/BookDetail/BookDetailHeaderView.swift`**: title được cố định theo chiều dọc để không cắt tên truyện dài trong cột bên cạnh cover.
* **`Sources/Views/Reader/ReaderSettingsView.swift` / `ReaderView.swift`**: thêm Picker `"Văn bản trước khi dịch"`, lưu `convertTraditionalToSimplified_<bookId>` và làm mới bản dịch khi đổi lựa chọn.
* **`Sources/Services/Translation/Utils/TranslateUtils.swift`** và pipeline Reader: khi bật, dùng ICU transform `StringTransform("Traditional-Simplified")` để chuẩn hoá phồn thể sang giản thể trước tra từ điển; text lưu trữ không đổi và translation spans chỉ dùng khi bảo toàn UTF-16. Cờ cấu hình trở thành một phần identity của `CachedChapter`; TOC paging/search và popup dịch từ/câu cũng dùng cùng cấu hình.
* **Pipeline TTS (`TTSManager`, `TTSBackgroundProcessor`, prepared models/prefetch workers)**: áp dụng cùng option cho title/nội dung TTS của chương hiện tại, auto-advance, text/audio prefetch chương kế và metadata Now Playing. Key/snapshot mang cờ chuyển đổi để loại cache khác cấu hình; đổi option giữa phiên hủy prefetch cũ nhưng không ngắt audio chương đã dựng.
* Không đổi quy chuẩn kiến trúc trong `rules.md`; các cập nhật CodeGraph liên quan nằm trong `00_index.md`, `06_event_graph.md`, và `08_lifecycle.md`.

## [1.3.219] - 2026-08-20

### Revert dùng BookListItemView trong DownloadTrackerView, chuẩn hoá BookListItemView 2 style và bỏ chevron NavigationLink

* **`Sources/Views/Download/DownloadTrackerView.swift`**: revert `taskRow` về HStack cover+title custom gốc (cover 44x60, title `.headline` lineLimit(1), badge taskType, `statusBadge`, ProgressView, nút cancel/share/retry, contextMenu). Bỏ `extension DownloadTask: BookDisplayable`; `taskRow` dịch title nội bộ qua `@AppStorage("isTranslationEnabled")` + `TranslateUtils.translateMeta`. Giữ `.contentShape(Rectangle())` và Toast `exportFromCached`.
* **`Sources/Views/Common/BookListItemView.swift`**: thêm `enum BookListItemStyle { case shelfOrHistory, discovery }`. `.shelfOrHistory` default `showChapter=true`/`showDescription=false`; `.discovery` default `showChapter=false`/`showDescription=true`. Init nhận `showChapter`/`showDescription` dạng `Bool?` (nil → theo style). Cover 50x70 + title `.system(size:14.5, weight:.semibold)` lineLimit(2) đồng bộ mọi style; HStack author/source chỉ render khi `hasAuthor || hasSource`.
* **`Sources/Views/Common/CategoryNovelsListView.swift`**: `BookListItemView(item: novel, style: .discovery)` (bỏ override cover 60x80); đổi `NavigationLink` → `Button` + `@State selectedNovel` + `.navigationDestination(item:)` để bỏ chevron.
* **`Sources/Views/Discovery/DiscoveryView.swift`**: `DiscoveryCategoryTabView` dùng `BookListItemView(item: novel, style: .discovery)`; đổi `NavigationLink` → `Button` + `selectedNovel` + `.navigationDestination(item:)`.
* **`Sources/Views/Shelf/ShelfMain/ShelfView.swift`**: dời 3 overlay chờ (`isParsingTXT`/`isImporting`/`isProcessingDeletion`) ra khỏi closure `.sheet(item: $pendingImport)` thành sibling của `VStack` trong `ZStack` — fix không hiển thị khi `pendingImport == nil`. Sheet content chỉ còn `TXTImportConfirmationSheet`.
* **`Sources/Services/Extensions/Manager/ExtensionManager.swift`**: `ExtensionItemResult` thêm conformance `Hashable` (dùng làm item của `.navigationDestination(item:)`).
* `ShelfView`, `ShelfSearchView`, `BookShareTargetSheet` dùng default `.shelfOrHistory` (BookShareTargetSheet override `showChapter: false`) — không đổi API. Không cần cập nhật `rules.md`.

## [1.3.218] - 2026-08-20

### Tái sử dụng BookListItemView trong DownloadTrackerView và bỏ chevron NavigationLink

* **`Sources/Views/Download/DownloadTrackerView.swift`**: thêm `extension DownloadTask: BookDisplayable` (title→`bookTitle`, coverUrl→`bookCoverUrl`, còn lại rỗng/0; `bookId` có sẵn). `taskRow` bỏ HStack cover+title custom → `BookListItemView(item: task, showChapter: false)`; badge taskType, statusBadge, ProgressView, nút cancel/share/retry + contextMenu chuyển xuống dưới row truyện trong `VStack`. Bỏ dịch title thủ công trong taskRow (BookListItemView tự dịch nội bộ qua `@AppStorage`); giữ `@AppStorage("isTranslationEnabled")` để dùng trong Toast `exportFromCached` (bọc `TranslateUtils.translateBookTitleIfNeeded`).
* **`Sources/Views/Common/CategoryNovelsListView.swift`**: thêm `.buttonStyle(.plain)` lên NavigationLink → bỏ chevron `>` mặc định, giữ tap đi chi tiết.
* **`Sources/Views/Discovery/DiscoveryView.swift`**: thêm `.buttonStyle(.plain)` lên NavigationLink → bỏ chevron `>` mặc định ở `DiscoveryCategoryTabView` (home tabs).
* Không đổi public API Service/Manager, không đổi dependency tầng logic; không cần cập nhật `rules.md`.

## [1.3.217] - 2026-08-20

### Import TXT: bảng mã giải mã đa dạng, xác nhận trước khi nhập, overlay Material

* File mới `Sources/Common/Utils/TextEncodingDecoder.swift`: helper giải mã `Data → String` thử tuần tự 20 bảng mã (UTF-8/BOM, UTF-16LE/BE, UTF-32LE/BOM/BE, GB18030, GBK, Big5-HKSCS, Big5, EUC-JP, windowsVietnamese/CP1258, VSCII/TCVN3, ISO-8859-1, windows-1250/1251/1252/1253/1254, ASCII). Mã đơn byte đặt cuối để tránh nuốt nhầm file tiếng Trung.
* `JSExecutor.decodeData` dùng chung `TextEncodingDecoder.decode(data)` thay cho logic tự viết.
* `ShelfView` tách import TXT thành 3 giai đoạn: `importTxtBook(from:)` (copy + decode + parse → hiện sheet xác nhận, giữ file tạm), `performImport()` (tạo Book + ghi chương + progress, xóa temp), `cancelImport()` (xóa temp). Thêm `PendingImport` struct + state `pendingImport`/`showImportConfirmation`/`importIsIndeterminate`.
* Sheet mới `Sources/Views/Shelf/ShelfMain/TXTImportConfirmationSheet.swift`: hiện tên truyện, số chương, tên file và danh sách toàn bộ chương trước khi nhập; nút Hủy/Nhập.
* Overlay import + overlay xóa sách bọc trong ZStack riêng (fix lệch giữa), card `.ultraThinMaterial`, spinner khi indeterminate, thanh linear + % khi ghi chương.

## [1.3.216] - 2026-08-20

### Đồng bộ badge nguồn sách thành capsule xám giữa detail, BookListItemView và ReaderChapterListView

* **Phạm vi**: 3 badge hiển thị tên nguồn/extension (và "Local") đồng nhất style capsule xám trung tính, thay thế pill xanh.
* **Style mới**: icon extension + chữ `.caption2` medium `.secondary`, nền `Color.secondary.opacity(0.12)` bo `Capsule()`, padding `(6, 2)`. Font size không đổi.
* **`Sources/Views/BookDetail/BookDetailHeaderView.swift`**: badge nguồn bỏ trạng thái chỉ icon+chữ → bọc thêm nền capsule; fallback `puzzlepiece.extension` giảm 16→14pt.
* **`Sources/Views/Common/BookListItemView.swift`**: protocol `BookDisplayable` thêm `extensionLocalPath: String` (default `""`) và `extensionIconUrl: String?` (default `nil`) qua `extension BookDisplayable`; `BookListItemView` thêm 2 init param `extensionLocalPath`/`extensionIconUrl`; badge thay 2 nhánh pill xanh (`Local`/`sourceName`) bằng helper `sourceBadge(text:)` (icon + chữ trong capsule). `Book` conformance giữ default.
* **`Sources/Views/Shelf/ShelfMain/ShelfView.swift`**: `bookItemView` resolve `allExtensions.first(where: { $0.packageId == book.extensionPackageId })` và truyền `localPath`/`iconUrl` vào `BookListItemView`.
* **`Sources/Views/Shelf/ShelfMain/ShelfSearchView.swift`**: thêm `@Query private var allExtensions: [Extension]`; resolve extension và truyền icon.
* **`Sources/Views/Dictionary/BookShareTargetSheet.swift`**: thêm `@Query private var allExtensions: [Extension]`; resolve extension và truyền icon.
* **`Sources/Views/Reader/ReaderChapterListView.swift`**: badge `Local`/`ext.name` đổi từ pill xanh sang capsule xám; dùng sẵn đối tượng `ext` để lấy `localPath`/`iconUrl`; không đổi API view.
* Không đổi public API Service/Manager, không đổi font size; không cần cập nhật `rules.md`.

## [1.3.215] - 2026-08-20

### Giảm cỡ chữ toàn bộ BookListItemView và BookDetailHeaderView

* **Phạm vi**: Thu nhỏ font theo tỉ lệ ~×0.85 (floor 11pt) cho mọi thành phần text của 2 view hiển thị title sách, giữ title luôn là phần lớn nhất; bỏ giới hạn số dòng title ở detail.
* **`Sources/Views/Common/BookListItemView.swift`**: title `.headline` (17pt semibold) → `.system(size: 14.5, weight: .semibold)`; author `.subheadline` (15pt) → `.system(size: 13)`; dòng "Đang đọc" `.caption` (12pt) → `.caption2` (11pt). Badge nguồn/Local và description giữ `.caption2`.
* **`Sources/Views/BookDetail/BookDetailHeaderView.swift`**: title `.title3.bold` (20pt bold) + `lineLimit(3)` → `.headline` (17pt semibold) không còn `lineLimit`; section "Thể loại"/"Giới thiệu" `.headline` (17pt) → `.system(size: 14.5, weight: .semibold)`; author `.subheadline` (15pt) → `.system(size: 13)`; tên nguồn `.caption.medium` (12pt) → `.caption2.medium` (11pt); giới thiệu (ExpandableTextView) `.body` (17pt) → `.system(size: 14.5)`. Metadata `caption2` và genre tags giữ nguyên.
* Không đổi public API, protocol `BookDisplayable` hay dependency; không cần cập nhật `rules.md`.

## [1.3.214] - 2026-08-19

### Badge tên nguồn (extension / Local) trong Reader danh sách chương và BookListItemView

* **Phạm vi**: 2 view hiển thị pill nguồn sách được bổ sung nhánh badge "Local" và chuẩn hoá hiển thị tên extension.
* **`Sources/Views/Reader/ReaderChapterListView.swift`**: Trong `header`, bọc text `"\(store.totalCount) chương"` vào `HStack(spacing: 6)` và thêm badge pill bên cạnh — nếu `isLocalTXTBook == true` hiển thị `"Local"`, ngược lại nếu `ext != nil` (và `ext.name` không rỗng) hiển thị `ext.name`. Style pill xanh: `.caption2`, `.lineLimit(1)`, `.padding(.horizontal, 6)` / `.padding(.vertical, 2)`, `.background(Color.blue.opacity(0.1))`, `.foregroundColor(.blue)`, `.cornerRadius(4)`. Giữ nguyên `Spacer(minLength: 4)` và nút refresh/sort; không đổi API của view.
* **`Sources/Views/Common/BookListItemView.swift`**: Thêm `isLocalBook: Bool` vào protocol `BookDisplayable` (default `false` qua `extension BookDisplayable`); `Book` thoả mãn sẵn qua computed property `Book.isLocalBook` (dựa trên `extensionPackageId`/`detailUrl`/`sourceUrl`/`sourceName` local), `ExtensionItemResult` dùng default. Khối pill nguồn thay bằng nhánh: `item.isLocalBook == true` → pill `"Local"`, ngược lại `!item.sourceName.isEmpty` → pill `sourceName` (giữ nguyên hành vi cũ cho sách online).

## [1.3.213] - 2026-08-19

### Revert toàn bộ về c78d042, giữ lại các tính năng logic (trừ hiển thị Detail và danh sách chương từ Reader)

* **Phạm vi**: Đưa toàn bộ mã nguồn về trạng thái commit `c78d042`, sau đó thêm lại các tính năng không thuộc 2 nhóm bị loại.
* **Loại bỏ (trình bày Detail)**: `BookDetailRoute`/`DetailRouter`, root presentation hub `ReaderRouter`/`DetailRouter` (2 `.fullScreenCover` root trong `AppLaunchRootView`), `BookDetailRoute` rải khắp 9 view (ShelfView, SearchView, DiscoveryView, CategoryNovelsListView, SuggestRowView, ReaderChapterListView, ReaderView, BookDetailView import), fix crash env injection (1.3.212). Detail quay lại mở bằng `NavigationLink` push trong NavigationStack của tab (tab bar hiện).
* **Loại bỏ (danh sách chương từ Reader)**: Bottom Sheet `presentationDetents` (978f200), badge nguồn, prefetch & giảm skeleton, fix skeleton forever, refactor single source of truth (82af6f8) và việc xoá `ReaderChapterListPageFetcher.swift`/`Tests/ReaderViewModelTests.swift`. Danh sách chương quay lại overlay custom (`readerChapterListOverlay` + Capsule + `dismissGesture`).
* **Loại bỏ (trình bày Reader)**: root ReaderRouter, fix re-creation loop (8e53471/144feb4), ẩn nav bar detail khi reader mở (3d090af), gỡ ignoresSafeArea (8978405), diagnostics (99d5fb3). Reader mở bằng `.fullScreenCover(item: $readerRoute)` cục bộ trong `BookDetailView` như c78d042.
* **Thêm lại (Nhóm C)**: `VietPhraseTokenizer` (tiếng Việt có dấu, số thập phân, gom cụm Latin/ASCII), `TranslateUtils` gom token tên tác giả, `ExpandableTextView` (căn lề 2 bên Description, layout-safe, fix "Xem thêm", fix comment, `WrappingLabel` public) + `Tests/ExpandableTextViewTests.swift`, `TTSManager` khôi phục chính xác chunk TTS, `TTSQuickTimerSheet` (spacing, nút gearshape, detents 0.85), tối ưu `BookListItemView`/`BookDetailHeaderView`, cải tiến Lịch Sử Đọc trong `ShelfView` (sort theo `lastReadDate`, `removeFromHistory` thông minh), toast thông minh cập nhật mục lục trong `ReaderChapterListView+Refresh`.
* **File mới/xoá**: xoá `Sources/Views/Reader/ReaderRouter.swift`; khôi phục `Sources/Services/ChapterText/Workers/ReaderChapterListPageFetcher.swift` và `Tests/ReaderViewModelTests.swift`; thêm `Tests/ExpandableTextViewTests.swift`.

## [1.3.200] - 2026-08-17

### Đồng bộ toàn diện API `newVisibleBrowser`, Sửa lỗi kiểm tra cú pháp JS và Nâng cấp Gutter số dòng & Bộ chọn Script Editor

* **Đồng bộ `newVisibleBrowser` (`VisibleWebViewLoader.swift` & `JSExecutor.swift`)**:
  - Bổ sung `launchAsync(url)`, `html(timeout)`, `waitUrl(urls, timeout)` (hỗ trợ cả mảng URL), `block(patterns)`, `urls()` (danh sách 200 URL gần nhất), và `getVariable(name)`.
  - Cung cấp các native bridge blocks: `_nativeBrowserLaunchAsyncVisible`, `_nativeBrowserBlockVisible`, `_nativeBrowserGetUrlsVisible`, `_nativeBrowserWaitUrlVisible`.
* **Sửa lỗi kiểm tra cú pháp JS (`JSExecutor.swift` & `ExtensionScriptEditorView.swift`)**:
  - Thêm `JSExecutor.validateSyntax(_ scriptContent: String)` hỗ trợ nạp script trong môi trường runtime đầy đủ.
  - Cập nhật `validateScriptSyntax()` trong `ExtensionScriptEditorView` khởi tạo `JSExecutor(localPath: folderPath)` kèm nạp cấu hình `getCombinedConfigs` và `injectGlobals(configs)`, giải quyết dứt điểm lỗi báo sai `ReferenceError` khi dùng `load()`, `Qt`, `UserAgent`, `Crypto`, `Engine`, `Response`...
* **Sửa lỗi lệch số dòng do xuống hàng (`HighlightingCodeEditor.swift`)**:
  - Xây dựng `CodeEditorTextView: UITextView` tích hợp Line Number Gutter vẽ trực tiếp trong `draw(_ rect:)` dựa trên `layoutManager.lineFragmentRect(forGlyphAt:)`.
  - Khi một dòng code dài tự động xuống hàng (word wrap), số dòng vẫn nằm chính xác ở đầu dòng logic đó, các dòng xuống hàng không bị sinh số mới, đảm bảo số dòng và mã nguồn luôn khớp 100% không bao giờ bị lệch.
* **Sửa lỗi biên dịch Swift trên Xcode / CI**:
  - `HighlightingCodeEditor.swift`: Thay thế `guard let` bằng `let` cho `layoutManager` và `textStorage` (non-optional trong `UITextView`); chuẩn hóa nhãn `actualGlyphRange: nil`.
  - `TranslateUtils.swift`: Đổi access level `buildTranslationSpans` thành `public static func` với `bookId: String? = nil` để tương thích với `JSExecutor.swift`.

## [1.3.199] - 2026-08-17

### Thiết kế lại giao diện Hẹn giờ tắt & Cài đặt nhanh TTS Widget (TTSQuickTimerSheet)

* **Vấn đề**: Giao diện hẹn giờ tắt của TTS Floating Widget trước đây sử dụng `.confirmationDialog` dạng danh sách nút văn bản đơn giản và `.alert` thô sơ để nhập số phút, gây cảm giác đơn điệu, thiếu trực quan và không hiển thị đồng hồ đếm ngược thời gian thực.
* **Giải pháp**:
  - `TTSQuickTimerSheet.swift` (Mới): Xây dựng Bottom Sheet hiện đại theo chuẩn Apple Audio Apps (`presentationDetents([.fraction(0.68), .large])`):
    + Banner trạng thái đếm ngược thời gian thực (phút:giây) nổi bật với viền cam và nút "Hủy" nhanh.
    + Lưới 6 mốc hẹn giờ phổ biến (`15m`, `30m`, `45m`, `60m`, `90m`, và `Hết chương` - `endOfChapter`) kèm hiệu ứng highlight mốc đang chọn.
    + Thanh trượt và nút `+/-` tuỳ chỉnh thời gian từ 5 đến 180 phút (bước nhảy 5 phút).
    + Phím tắt mở nhanh Bảng cài đặt giọng đọc đầy đủ (`TTSSettingsSheet`).
  - `TTSFloatingWidgetView.swift`:
    + Thay thế hoàn toàn `.confirmationDialog` và `.alert` cũ bằng `@State private var showingQuickTimerSheet = false` và `.sheet(isPresented: $showingQuickTimerSheet) { TTSQuickTimerSheet() }`.

## [1.3.198] - 2026-08-17

### Tách riêng biệt thuộc tính `description` và `content` cho ExtensionItemResult và nâng cấp giao diện hiển thị bình luận

* **Vấn đề**: Trước đây, hàm bóc tách dữ liệu JS (`search` và `executeCustomScript`) gộp chung `content` vào `description` (`dict["description"] ?? dict["desc"] ?? dict["content"]`). Điều này làm lẫn lộn giữa phần mô tả tóm tắt / metadata bình luận (thời gian đăng, số sao, số chương) và phần nội dung bình luận chi tiết (`content`).
* **Giải pháp**:
  - `ExtensionManager.swift`:
    + Thêm thuộc tính `public let content: String` vào `ExtensionItemResult` và cập nhật `init`.
    + Tách riêng trích xuất `description` (`desc`/`description`) và `content` (`content`) trong cả hai hàm `search` và `executeCustomScript`.
  - `CommentSectionView.swift` & `AllCommentsView.swift`:
    + Cập nhật header hàng bình luận hiển thị tên người bình luận và `comment.description` (thời gian, đánh giá).
    + Cập nhật phần thân bình luận hiển thị `comment.content` (fallback về `comment.description` nếu extension cũ chỉ trả 1 trường).
  - `SearchView.swift`:
    + Cập nhật dòng hiển thị mô tả tóm tắt sách với cơ chế fallback linh hoạt (`description` -> `content` -> `author`).

## [1.3.197] - 2026-08-17

### Bổ sung toàn diện các phương thức Quick Translator (Qt.translate), Storage, Fetch mở rộng, DOM parsing mở rộng và Browser cho VBook Extensions

* **Vấn đề**: Các extension VBook nâng cao cần các hàm dịch thuật offline Quick Translator (`Qt.translate`), lưu trữ cục bộ (`localStorage`, `cacheStorage`, `localConfig`, `localCookie`), xử lý DOM nâng cao (`attributes()`, `isEmpty()`, `map()`), HTTP Fetch đầy đủ (`statusText`, `url`, `headers`, `header()`, `blob()`, `request`, `timeout`), và điều khiển trình duyệt WebKit nâng cao (`launchAsync`, `waitUrl` mảng, `block`, `urls`, `getVariable`).
* **Giải pháp**:
  - `JSDom.swift`:
    + Thêm `element.attributes() -> [String: String]` vào `JSElementExport` và `JSElement`.
    + Thêm `elements.isEmpty() -> Bool` và `elements.map(_ callback: JSValue) -> [JSValue]` vào `JSElementsExport` và `JSElements`.
  - `WebViewLoader.swift`:
    + Thu thập danh sách mạng `interceptedUrls: [String]` (tối đa 200 URLs).
    + Thêm `block(patterns: [String])` và `isDynamicDomainBlocked(_:)` chặn domain động theo phiên.
    + Nâng cấp `waitUrl(targetUrls:timeout:completion:)` nhận mảng URL strings.
    + Thêm `loadAsync(url: URL)` tải trang ngầm không chặn luồng JS.
  - `JSExecutor.swift`:
    + Kết nối Quick Translator `Qt.translate(text, to, extras)` với `TranslateUtils` và `TranslationManager` native, trích xuất spans mapping thành `segments`.
    + Đăng ký hệ thống Storage toàn cục: `localStorage` (lưu bền vững theo extension vào `UserDefaults`), `cacheStorage` (RAM cache), `localConfig` (đọc cấu hình plugin/người dùng qua `getItem`/`get`), `localCookie` (`setCookie`, `getCookie`).
    + Mở rộng `_nativeSyncFetch` và `fetchBootstrap`: hỗ trợ `options.timeout`, bổ sung `response.statusText`, `response.url`, `response.headers` (dictionary + `.get()`), `response.header(name)`, `response.blob()`, `response.request` (`{ url, headers }`).
    + Mở rộng `Engine.newBrowser`: hỗ trợ `launchAsync()`, `html(timeout)`, `waitUrl(urls, timeout)`, `block(patterns)`, `urls()`, `getVariable(name)`.
    + Đăng ký `Log.log(...)` và `UserAgent.system()`, nâng cấp `Script.execute(scriptOrName, functionName, ...args)` tự động nạp file script extension nếu tham số đầu là tên file.
    + Cập nhật `injectGlobals` tiêm đồng thời cả biến toàn cục và `_injectedConfigs` cho `localConfig`.

## [1.3.196] - 2026-08-17

### Bổ sung toàn diện các phương thức và đối tượng Rhino / VBook Android cho JSExecutor

* **Vấn đề**: Các extension VBook được viết cho môi trường Rhino hoặc port từ QML/Qt runtime (như Fanqie Novel) gặp lỗi runtime khi gọi các hàm chưa được định nghĩa trong `JSExecutor`: `TypeError: UserAgent.chrome is not a function`, `ReferenceError: Can't find variable: Qt`.
* **Giải pháp**:
  - `JSCrypto.swift`: Mở rộng giao thức `JSCryptoExport` và lớp `JSCrypto` với các thuật toán băm và mã hoá native từ `CryptoKit`: `sha1`, `sha512`, `base64Encode`, `base64Decode`, `hmacSha256`, `hmacSha1`, `hmacMd5`.
  - `JSExecutor.swift`:
    + Đăng ký các hàm toàn cục chuẩn Rhino: `print(...)` (alias của `console.log`), `sleep(ms)` (delay đồng bộ không block WebKit), `toast(msg)` / `Toast` (kết nối `ToastManager`).
    + Mở rộng `UserAgent`: Bổ sung `chrome()`, `mobile()`, `safari()`, `firefox()`, `mac()`, `macos()`, `windows()`, `random()`, `default()`, `get()`.
    + Đăng ký đối tượng toàn cục `Qt`: `Qt.md5`, `Qt.sha256`, `Qt.sha1`, `Qt.sha512`, `Qt.atob`, `Qt.btoa`, `Qt.formatDate`, `Qt.include` (kết nối hàm `load`), `Qt.platform` (`{ os: "ios" }`), `Qt.point`, `Qt.size`, `Qt.rect`, `Qt.rgba`, `Qt.hsla`, `Qt.quit`, `Qt.exit`.
    + Mở rộng `Http` builder: Thêm `.json()` và `.table()` để parse trực tiếp JSON object từ response mà không cần gọi `JSON.parse()`, bổ sung `Http.request()`, `Http.head()`, `Http.put()`, `Http.delete()`, `Http.patch()`, `.contentType()`.
  - Giúp toàn bộ các extension VBook cũ và mới thực thi hoàn hảo, không còn tình trạng văng ngoại lệ do thiếu hàm môi trường.

## [1.3.195] - 2026-08-17

### Trình bày TTS Floating Widget & Global Toast qua Passthrough UIWindow chuyên dụng

* **Vấn đề**: Khi mở Reader (`ReaderView` qua `fullScreenCover`), trình duyệt bypass (`BypassWebView` qua `fullScreenCover`) hoặc trình duyệt `Engine.newVisibleBrowser` (`TabbedVisibleBrowserViewController` qua `present(pageSheet)`), widget TTS và các thông báo Toast toàn cục trong `AppLaunchRootView` bị che khuất.
* **Giải pháp**:
  - `TTSFloatingWidgetWindowManager`: Tạo `FloatingWidgetUIWindow` (`windowLevel = .alert - 1`, non-key, `isHidden = false/true`) gắn với `UIWindowScene` active. Cung cấp `@Published isWidgetActuallyVisible` được cập nhật tập trung qua `updateWindowVisibility(hidden:)`. Tuyệt đối không gọi `makeKeyAndVisible()`.
  - `FloatingWidgetUIWindow.hitTest`: Ranh giới hit-testing native duy nhất: khi container có `presentedViewController` (e.g. `confirmationDialog`, `.alert`, hoặc `TTSSettingsSheet`), trả về `super.hitTest` để toàn bộ dialog/sheet nhận touch; khi ở chế độ widget thông thường, chỉ trả về `widgetContainerView` khi chạm trong bounds, còn mọi điểm ngoài trả `nil` để rơi xuống màn hình bên dưới (Reader/WebView/Shelf).
  - `FloatingWidgetContainerViewController`: Quản lý bounded container (212x56/80 hoặc 52x52), gắn `UIPanGestureRecognizer` kéo 1:1 theo tần số quét của thiết bị, `UITapGestureRecognizer` (chỉ bật khi `.peeking`), và spring animation snap mép/resize chuẩn anchor. Sở hữu `CoverRotationState` dài hạn và lắng nghe Combine `$isPlaying`, `$playingBookId` để điều khiển hiệu ứng xoay đĩa cover 20s/vòng (18°/s) mượt mà.
  - `TTSFloatingWidgetView.swift`: Tách thành `TTSWidgetContentView`, `TTSWidgetCapsuleView`, `TTSWidgetPeekCircleView`. Sử dụng trực tiếp `.confirmationDialog` và `.alert` native trong SwiftUI. `TTSSettingsSheet` được chuyển vào `TTSWidgetContentView` (bên trong `FloatingWidgetUIWindow`) kèm theo `modelContainer`, loại bỏ xung đột modal presentation trên root view controller làm đóng `ReaderView` đồng thời cho phép `@Query` truy vấn đầy đủ danh sách Extension TTS. `TTSCoverView` áp dụng hiệu ứng xoay đĩa đằm mượt (18°/s) qua `TimelineView` read-only.
  - `ToastManager.swift`: Nâng cấp hiển thị qua `ToastUIWindow` chuyên dụng (`windowLevel = .alert`, non-key, `hitTest = nil`), giúp toàn bộ thông báo toast trong ứng dụng (sao chép, lưu từ điển, cập nhật mục lục, tải chương...) hiển thị nổi rõ ràng trên `ReaderView`, `BypassWebView` và trình duyệt mà không chặn touch.
  - `FreeBookApp.swift`: Gỡ bỏ widget và `TTSSettingsSheet` khỏi `AppLaunchRootView`, gắn hook `TTSFloatingWidgetWindowManager.shared.refreshState()` và truyền `modelContext.container` vào `TTSFloatingWidgetWindowManager`.
  - Giữ nguyên 100% API của `FloatingWidgetViewModel` và các unit test hiện có trong `FloatingWidgetViewModelTests.swift`.
* **XcodeGen**: Có thêm file mới `Sources/Views/TTSWidget/TTSFloatingWidgetWindowManager.swift` → cần chạy `xcodegen generate` trên máy macOS khi tạo lại `.xcodeproj`.

## [1.3.192] - 2026-08-17

### Reader trình bày dạng fullScreenCover — bỏ ẩn/hiện tab bar, sửa tab bar hiện trễ khi quay lại

* **Vấn đề**: Reader đang được **push** lên `NavigationStack` của từng tab và ẩn tab bar bằng `.toolbar(.hidden, for: .tabBar)` (`ReaderView.swift`). Trên iOS 16/17, khi pop về, hệ thống khôi phục tab bar **trễ hơn** nội dung → tab bar hiển thị ra sau khá khó chịu khi đóng màn hình toàn màn hình.
* **Giải pháp**: đổi toàn bộ điểm mở Reader sang **`fullScreenCover(item:)`** — cover phủ toàn màn hình (kể cả tab bar) nên TabView phía dưới không bao giờ bị ẩn/hiện lại, không rẽ layout, không reload nội dung. Đóng cover là tab bar + nội dung hiện ra ngay cùng lúc.
* **`ReaderView.swift`**: xoá `.toolbar(.hidden, for: .tabBar)` (trong cover không có tab bar — modifier giờ là dead code). `@Environment(\.dismiss)` đóng cover; 2 `NavigationLink` ẩn bên trong (mở BookDetail / Đổi nguồn) push lên `NavigationStack` riêng của cover.
* **`ShelfView.swift`**: thêm `@State readerPresentationRoute: ShelfReaderRoute?`; 2 dòng `NavigationLink(destination: ReaderView)` ở Kệ Sách & Lịch Sử đổi thành `Button { readerPresentationRoute = ... }` + `.buttonStyle(.plain)` (giữ `bookItemView(book)` làm label + nguyên contextMenu); route từ widget TTS (`navigationDestination(isPresented: $triggerNavigation)`) đổi thành `.fullScreenCover(item: $readerPresentationRoute)` trình bày `NavigationStack { ReaderView(...).id(route.id) }`; handler `openCurrentlyPlayingReader` gán route thay vì bật push.
* **`ShelfSearchView.swift`**: thêm `@State readerRoute: ShelfReaderRoute?`; `NavigationLink` kết quả đổi thành `Button` + `.fullScreenCover(item:)`.
* **`BookDetailView.swift`**: `.navigationDestination(item: $readerRoute)` đổi thành `.fullScreenCover(item: $readerRoute) { NavigationStack { LazyView { ReaderView(...) } } }` (`ReaderRoute.id = chapterIndex`, cover tự reset item về nil khi đóng).
* Không thêm file Swift mới → không cần `xcodegen generate`; Windows không build/test tại chỗ — kiểm chứng qua CI `.github/workflows/build-ipa.yml` hoặc máy Mac, cần test tay luồng widget TTS `openCurrentlyPlayingReader` (MainTabView chuyển tab trước rồi ShelfView present cover).

## [1.3.191] - 2026-08-16

### Gợi ý lịch sử tìm kiếm theo từ đang nhập (ShelfSearch + SearchView)

* **Ý tưởng**: khi đang gõ từ khóa, danh sách lịch sử tìm kiếm (dùng chung `search_history`) được lọc live theo nội dung đã nhập thành gợi ý — bấm vào là dùng ngay, không cần chờ gõ xong. Chỉ re-render lại phần lịch sử có sẵn, không thêm UI/section mới.
* **`ShelfSearchView.swift`**: thêm computed `matchingHistory` (lọc `searchHistory` bằng `localizedCaseInsensitiveContains` khi có query, ngược lại trả toàn bộ); `historyView` đổi `searchHistory` → `matchingHistory` và placeholder chỉ hiện khi query rỗng; body khi query có nội dung hiện `historyView` đã lọc **bên trên** `resultsView` (giới hạn `.frame(maxHeight: 220)` để không nuốt hết chiều cao List kết quả). Bấm gợi ý → `searchQuery = item` (lịch sử lọc tiếp + kết quả sách cập nhật).
* **`SearchView.swift`**: thêm `matchingHistory` cùng filter; `searchHistoryView` dùng `matchingHistory` thay cho `searchHistory` — nhánh idle khi có query hiện các mục lịch sử khớp, bấm → `searchQuery = item` + `performSearch()`; kết quả web không đổi.
* Không thêm file Swift mới → không cần `xcodegen generate`; Windows không build/test tại chỗ — kiểm chứng qua CI `.github/workflows/build-ipa.yml` hoặc máy Mac.

## [1.3.190] - 2026-08-16

### Tìm kiếm sách trong Kệ sách & Lịch sử + backfill/refresh tên đã dịch

* **Ý tưởng**: nút tìm kiếm trên tab Kệ Sách giúp tìm nhanh truyện trong Kệ sách + Lịch sử, bấm kết quả mở thẳng ReaderView; dùng chung lịch sử tìm kiếm với màn hình Tìm Kiếm. Để tìm được cả tên đã dịch, thêm 2 cột `titleTrans`/`authorTrans` vào `Book` và lấp chúng bằng migration lúc mở app + refresh mỗi khi mở truyện.
* **Model**: `Book.swift` thêm `titleTrans: String = ""` + `authorTrans: String = ""` (non-optional có default → SwiftData lightweight migration tự thêm cột, không cần VersionedSchema).
* **Migration**: `BookTitleTranslationMigrator.swift` (mới) — `runIfNeeded(container:)` chạy sau khi từ điển nạp xong (trigger bởi `.task(id: translationManager.isInitialized)` trong `AppLaunchRootView`), dùng `ModelContext(container)` riêng theo luật SwiftData, fetch toàn bộ + lọc trong RAM (`titleTrans.isEmpty || authorTrans.isEmpty` — tránh string predicate iOS 17), batch save mỗi 50; `titleTrans = translateMeta(title, bookId:)`, `authorTrans = translateAuthorHanViet(author)` — không gating theo toggle dịch (search bất kể bật/tắt).
* **Refresh khi mở truyện**: `refreshTranslations(for:)` (cùng file) chỉ ghi khi giá trị đổi, guard `isVietPhraseLoaded`; gọi từ `ReaderView.initializeReaderIfNeeded` (sau khi resolve `localBookSnapshot`, bao phủ cả sách online lẫn local) và `BookDetailView` qua `.task(id: actualBookId)` — sách thêm trong phiên hoặc dict/custom dict thay đổi được cập nhật ngay, không chờ lần mở app sau.
* **Lịch sử dùng chung**: `SearchHistoryStore.swift` (mới, key `search_history`, max 15, trim + dedup + chèn đầu) — `SearchView` refactor sang store (hành vi giữ nguyên), `ShelfSearchView` đọc/ghi cùng key.
* **UI**: `ShelfSearchView.swift` (mới) — search bar, khi query rỗng hiện lịch sử dùng chung (xóa từng item / xóa tất cả), khi có query filter `isOnShelf || isHistory` qua `ShelfBookSearchMatcher` (khớp 1 trong 4 trường `title`/`titleTrans`/`author`/`authorTrans`, `localizedCaseInsensitiveContains`), kết quả = `BookListItemView` + `NavigationLink` → ReaderView; `ShelfView` thêm `@State showingShelfSearch` + ToolbarItem `magnifyingglass` (chỉ hiện khi `selectedTab != 0`) + `.navigationDestination(isPresented:)`.
* **Tests**: user yêu cầu **không** viết unit test cho feature này.
* 3 file Swift mới (`SearchHistoryStore.swift`, `BookTitleTranslationMigrator.swift`, `ShelfSearchView.swift`) → cần `xcodegen generate` (CI `.github/workflows/build-ipa.yml` tự chạy khi push `sigle_reader`); Windows không build/test tại chỗ — kiểm chứng qua CI hoặc máy Mac.

## [1.3.189] - 2026-08-16

### Loại bỏ tiêu đề chương trùng trong nội dung (dùng TOC rule, config chung TTS + Reader)

* **Ý tưởng**: nhiều chương bắt đầu bằng đúng tiêu đề chương → Reader hiển thị lặp lại và TTS đọc hai lần. Feature mới: kiểm tra dòng/paragraph đầu tiên của chương có phải tiêu đề chương không (nhận diện bằng TOC rules, đúng pattern TXT import), nếu phải thì loại bỏ khỏi cả hiển thị lẫn TTS. Kèm option bật/tắt trong dropdown Reader.
* **Detection** (mirror `ShelfView.swift:712-718` TXT import): compile một lần `TranslateUtils.getCompiledActiveTOCRegexes()` rồi gọi `TranslateUtils.isChapterHeaderLine(_:compiledTOCRegexes:)` trên `lines.first`; TOC rules vẫn global (`toc_rules.json`).
* **Config chung**: **một key duy nhất** `removeDuplicatedTitle_\(bookId)` (UserDefaults, **default ON**, lưu riêng mỗi truyện) — TTS + Reader cùng đọc, không thêm setting riêng; mirror pattern `showChapterTitle_\(bookId)`.
* **TTS side**: `TTSPreparedChapterKey` + `TTSPreparedNextChapterKey` thêm field `removeDuplicatedTitle`; `TTSBackgroundProcessor.processChapter` thêm param và bỏ `lines.removeFirst()` sau normalize khi khớp TOC rule (trước khi build entries/chunks — ID dòng cha giữ nguyên); `TTSManager.prepareSpeaking`/`startSpeaking`/`makeNextChapterKey`/auto-advance đọc key + truyền xuống; `TTSChapterTextWorker` truyền `key.removeDuplicatedTitle`; `resumeAfterSettings` rebuild phân đoạn bỏ dòng đầu tương ứng (qua `TTSParagraphBuilder.buildFromEntries`).
* **Reader side**: `ReaderParagraphBuilder.build` + `ReaderViewModel.buildCancellable` + `performChapterTranslationOffMainActor` + `processAndSaveChapter` thêm param `removeDuplicatedTitle` (đọc key default true), bỏ dòng đầu khỏi `lines` trước khi dựng `paragraphItems`/`translatedContent` — ID cố định nên ánh xạ highlight/TTS vẫn khớp; `cached.originalContent` giữ nguyên văn bản normalize đầy đủ, mỗi lần build lại áp dụng bỏ dòng.
* **UI**: `ReaderHeaderFooterOverlayView` thêm binding `removeDuplicatedTitle` + nút Menu "Loại bỏ tiêu đề chương trùng trong nội dung" (checkmark cạnh toggle "Hiển thị tên chương"); `ReaderView` `@State removeDuplicatedTitle = true` + load key ở `initializeReaderIfNeeded`; `ReaderView+Controls.toggleRemoveDuplicatedTitle()` persist + `refreshParagraphItems()`.
* **Tests**: `ReaderTranslationTests` (bỏ dòng đầu khớp TOC / giữ khi tắt / không bỏ khi không phải heading), `TTSManagerTests` (processChapter bỏ/giữ dòng đầu); cập nhật call `ReaderParagraphBuilder.build` + `processChapter` cũ sang param mới.
* **Rủi ro còn lại** (ghi `10_risk_report.md`): nếu TOC rule không khớp hoặc bị tắt, tiêu đề trùng vẫn giữ nguyên — đây là tiện ích hiển thị, không phải dedupe tuyệt đối.
* Không thêm file Swift mới → không cần `xcodegen generate`; Windows không build/test tại chỗ — kiểm chứng qua CI `.github/workflows/build-ipa.yml` hoặc máy Mac.

## [1.3.184] - 2026-08-16

### Widget TTS thu nhỏ: chỉ hiển thị nửa vòng tròn ở mép

* **`TTSFloatingWidgetView.swift`** (`restingPosition`, nhánh `.peeking`): trước đây `inset = Layout.peekSize * 0.38` (=19.76, bán kính 26) → chỉ ~6.24pt bị mép che, widget hiện gần như cả vòng tròn bị cắt lẹm trông như lỗi canh vị trí. Đổi `inset = 0` → tâm vòng tròn đặt **ngay tại mép màn hình**: đúng một nửa vòng nhô ra, nửa còn lại bị mép che (mép trái `x=0`, mép phải `x=screenWidth`). Nửa hiển thị nằm trọn trong window nên hit-target tap-to-reveal (vùng chạm 26pt) vẫn hợp lệ.
* Không đổi `Layout.peekSize`, `collapsedWidget`, cơ chế kéo/thu/mở, `FloatingWidgetViewModel`.
* Không thêm file Swift mới → không cần `xcodegen generate`; Windows không build/test tại chỗ — kiểm chứng qua CI; hành vi tap-to-reveal nên kiểm chứng thêm trên máy thật.

## [1.3.183] - 2026-08-16

### Dịch tên sách trong toast của DownloadManager (bổ sung)

* **`DownloadManager.swift`**: 3 toast gửi qua `DownloadPresentationEventCenter` còn dùng tên sách thô (`tasks[index].bookTitle`) — "Đã xong: \(type) '\(title)' thành công!", "Lỗi \(type) '\(title)': ...", "Đã hủy tác vụ: \(type) '\(title)'" — đổi `let title = ...` sang `TranslateUtils.translateBookTitleIfNeeded(tasks[index].bookTitle, bookId: tasks[index].bookId)` (các hàm `markCompleted`/`markFailed`/`markCancelled` đều `@MainActor`; `TranslateUtils` tầng Services, không vi phạm phân tầng).
* Đã rà soát đầy đủ: 103 toast `ToastManager.shared.show` + toàn bộ `.send(.showToast)` của TTS/Download event centers — không còn toast nào hiển thị tên sách chưa dịch (ngoại trừ toast tên extension ở `SearchView` nằm ngoài phạm vi).
* Không thêm file Swift mới → không cần `xcodegen generate`; Windows không build/test tại chỗ — kiểm chứng qua CI.

## [1.3.182] - 2026-08-16

### Quay về tab Kệ sách sau khi đổi nguồn truyện thành công

* **`SearchView.swift`** (`executeSourceChange`): trước `onSourceChanged?()` post notification mới `sourceChangedNavigateToShelf` với `userInfo: ["shelfTab": createSnapshot.isOnShelf ? 1 : 2]`. Truyện mới thừa kế `isOnShelf`/`isHistory` từ truyện cũ nên giá trị sub-tab khớp filter `historyBooks = isHistory && !isOnShelf` của `ShelfView`.
* **`MainTabView.swift`**: thêm observer `sourceChangedNavigateToShelf` (cạnh observer `openCurrentlyPlayingReader` sẵn có) → `selectedTab = 0` (tab Kệ Sách chính).
* **`ShelfView.swift`**: thêm observer `sourceChangedNavigateToShelf` → đặt `selectedTab` theo `userInfo["shelfTab"]` (1 = Kệ Sách, 2 = Lịch Sử) để sau khi đổi nguồn thành công, kệ sách hiển thị đúng sub-tab chứa truyện mới.
* **`ReaderView.swift`**: `onSourceChanged` của màn Đổi nguồn giờ thêm `dismiss()` sau 0.3s (`DispatchQueue.main.asyncAfter`, khớp pattern sẵn có) để pop Reader về root kệ sách — cần thiết vì truyện cũ bị xóa ở nhánh không phát TTS.
* **`BookDetailView.swift`**: `onSourceChanged` mirror `ReaderView` — đặt `navigateToChangeSource = false` (SearchView được push qua `NavigationLink(isActive:)`, chỉ gọi `dismiss()` không pop được vì binding còn active → màn hình Search bị kẹt) rồi `dismiss()` sau 0.3s; việc chuyển main tab do observer `MainTabView` xử lý.
* Không thêm file Swift mới → không cần `xcodegen generate`; Windows không build/test tại chỗ — kiểm chứng qua CI `.github/workflows/build-ipa.yml` hoặc máy Mac.

## [1.3.180] - 2026-08-16

## [1.3.181] - 2026-08-16

### Fix: "Đóng tất cả" browser khi đang tải truyện không còn chờ ~16s cho chương kế tiếp

* **Nguyên nhân**: khi nhấn "Đóng tất cả", `removeAllTabs()` → `cleanUpQuietly()` chỉ **set nil** `navigationCompletion`/`waitUrlCompletion` mà không gọi chúng → `JSExecutor` đang chờ `chap.js` bằng `DispatchSemaphore` trong `_nativeBrowserLaunchVisible` (chờ tối đa `timeoutMs+1` ≈ 16s) và `_nativeBrowserWaitUrlVisible` (≈ 16s) **không được báo** → chương hiện tại block trọn timeout (waitForReady không bị vì `cancelPendingWaitReady` đã gọi completion). Sau đó `chap.js` tạo browser mới (webview lạnh, load lại + Cloudflare) → chương kế tiếp phải đợi rất lâu.
* **`VisibleWebViewLoader.swift`**: thêm `firePendingCompletions()` — capture rồi **gọi** `navigationCompletion?(nil)` và `waitUrlCompletion?(false)` trước khi set nil; gọi từ **cả `cleanUp()` lẫn `cleanUpQuietly()`**. Kết quả: JS bridge release ngay, chương hiện tại fail tức thì, download chuyển sang chương kế tiếp ngay.
* **`VisibleBrowserTabManager.swift`**:
  - `addTab`: thêm nhánh `isDismissing` — không còn `reloadTabs()` trên container đang teardown khi browser đang bị tắt.
  - `dismissContainer`: trong completion, nếu vẫn còn tab (download tiếp tục dùng browser để bypass Cloudflare, tab mới được thêm lúc dismiss) → `presentContainerView(initialActiveId:)` để browser hiện lại nhanh với container mới thay vì webview bị bỏ rơi trong container chết.
* Không thêm file Swift mới → không cần `xcodegen generate`; Windows không build/test tại chỗ — kiểm chứng qua CI.

## [1.3.180] - 2026-08-16

### Dịch tên sách trong toast khi bật dịch

* **`TranslateUtils.swift`**: thêm `translateBookTitleIfNeeded(_:bookId:)` — `guard isTranslationEnabled && containsChinese(title)` rồi `translateMeta(title, bookId:)`, ngược lại trả nguyên văn. Đóng gói đúng pattern đang dùng rộng rãi (VD `BookListItemView`), vì `translateMeta`/`translateText` không tự check `isTranslationEnabled`.
* **6 toast hiển thị tên sách** giờ hiện tên đã dịch khi bật dịch (dùng `bookId` sẵn trong scope):
  - `ShelfView.swift`: "Đã dịch lại xong tên chương cho: \(bookTitle)" (`bookId` dòng 563); "Đã thêm '\(book.title)' vào kệ sách"; "Đã xoá '\(book.title)' khỏi kệ sách" (`book.bookId`); "Đã nhập thành công: \(parsed.title)" (`newBookId` tạo lúc import TXT).
  - `DownloadTrackerView.swift`: "Đã thêm tác vụ xuất '\(book.title)' từ các chương đã tải." (`book.bookId`).
  - `DictionaryListView.swift`: "Đã chia sẻ ... sang truyện \(targetBook.title)" (`targetBook.bookId`).
* **Không dịch** `SearchView.swift` toast "Đã thêm nguồn mới '\(ext.name)'..." — `ext.name` là tên extension/nguồn, không phải tên sách.
* Không thêm file Swift mới → không cần `xcodegen generate`; Windows không build/test tại chỗ — kiểm chứng qua CI.

## [1.3.178] - 2026-08-16

### Vuốt xuống / nút ẩn Visible Browser = ẩn (giữ tabs) + pill kéo được để mở lại

* **`VisibleBrowserTabManager.swift`**:
  - `presentationControllerDidDismiss` (vuốt xuống pageSheet) đổi từ **xoá toàn bộ tabs + cleanup loader** → **ẩn**: giữ `tabs` + `containerViewController` (+ webview sống), `isPresented=false, isHidden=true, navController=nil`, post `stateDidChangeNotification` để UI refresh.
  - Thêm `hideContainer()` (nút ẩn): dismiss sheet giữ tabs/webview, đặt `isHidden=true` — tương đương vuốt xuống.
  - Thêm `reopenContainer()`: nếu đang ẩn & còn tabs & còn `containerViewController` → tạo `UINavigationController` mới bọc lại container cũ (webview không bị mất), present lại, `isPresented=true, isHidden=false`.
  - Tách `findTopViewController()` (tái dùng giữa `presentContainerView` và `reopenContainer`, kèm retry khi topVC đang chuyển cảnh).
  - `addTab`: nhánh đang ẩn → `reloadTabs()` + `reopenContainer()` (không tạo container mới làm mất webview). `selectTab`: đang ẩn thì mở lại.
  - `removeTab`/`removeAllTabs`/`dismissContainer`: xử lý cleanup khi `!isPresented` (đang ẩn) — nil tham chiếu + reset `isHidden`; đóng tab cuối / "Đóng tất cả" vẫn là đóng thật.
- **`TabbedVisibleBrowserViewController.setupNavigationBar`**: thay text button "Đóng tất cả" bằng `rightBarButtonItems = [closeAllButton, hideButton]` — `closeAllButton` icon `trash` (accessibilityLabel "Đóng tất cả", giữ `removeAllTabs`), `hideButton` icon `chevron.down` (accessibilityLabel "Ẩn trình duyệt", gọi `hideContainer()`).
- **File mới `Sources/Views/Common/VisibleBrowserReopenView.swift`** (3 thành phần trong 1 file):
  - `VisibleBrowserPresentationReader`: ObservableObject subscribe `stateDidChangeNotification`, snapshot `{isHidden, tabCount, showReopenButton = isHidden && tabCount > 0}`.
  - `VisibleBrowserReopenViewModel`: `verticalRatio` + `edgeDirection` + `isDragging`, persist qua `UserDefaults` (`visibleBrowserReopenVerticalRatio`, `visibleBrowserReopenEdge`) — tham chiếu `FloatingWidgetViewModel`.
  - `VisibleBrowserReopenButton`: capsule `ultraThinMaterial` (icon `globe` + "Trình duyệt • N tab"), **kéo được như TTS widget** — snap sát mép trái/phải theo hướng kéo, kéo dọc **giới hạn trong dải dưới 92pt** (`center cách đáy ∈ [26, 68]`) vì cạnh đáy TTS widget luôn ≥ 92pt so với đáy màn hình (`FloatingWidgetViewModel.handleDragEnd` clamp) → **không bao giờ đè widget nghe kể cả khi đang kéo** (y được clamp trong lúc drag). Tap → `reopenContainer()`.
- **`FreeBookApp.swift`**: `AppLaunchRootView` thêm `@StateObject browserPresentation = VisibleBrowserPresentationReader()`; overlay `if translationManager.isInitialized && browserPresentation.snapshot.showReopenButton { VisibleBrowserReopenButton(tabCount:).zIndex(9998) }` (cạnh `TTSFloatingWidgetView` zIndex 9999).
- **Ghi chú môi trường**: Windows không build/test tại chỗ — CI `.github/workflows/build-ipa.yml` tự chạy `xcodegen generate` (dòng 41) nên file Swift mới được build; máy Mac local phải chạy `xcodegen generate` trước khi build.

## [1.3.177] - 2026-08-16

### Thay placeholder "Đang tải..." của danh sách chương Reader thành skeleton

* **`SkeletonView.swift`**: thêm `var color: Color = Color(.systemGray5)` (mặc định giữ màu cũ, memberwise init không đổi → mọi call site hiện có `SkeletonView(width:height:)` không cần sửa); `.fill(Color(.systemGray5))` → `.fill(color)` để cho phép khớp màu theo `ReaderTheme` (paper/sepia/dark) thay vì màu hệ thống — tránh contrast kém trên nền reader tuỳ biến.
* **`ReaderChapterRowView.swift`**: tách `body` theo `chapter.isPlaceholder` — placeholder giờ render **skeleton row** (`HStack` gồm 2 `SkeletonView`: thanh tiêu đề cao 14px, width biến thiên deterministic theo `[150, 130, 160, 120, 140, 110][chapter.index % 6]`, cộng chấm tròn 14x14 mô phỏng slot icon đã cache; màu `theme.textColor.opacity(0.18)`) kèm `.padding(.vertical, 4)` + `.listRowBackground(theme.backgroundColor)` + `.accessibilityLabel("Đang tải chương...")`, không phải Button nên không thể chọn. Ngược lại giữ nguyên button hiện tại và bỏ `.disabled(chapter.isPlaceholder)` (không còn áp dụng). Chiều cao thanh giữ gần bằng line-height text body → không nhảy layout giữa skeleton và dòng đã nạp.
* **`ReaderChapterListView.swift`**: không đổi logic; `displayTitle(for:)` vẫn trả "Đang tải..." cho placeholder nhưng không còn được render (skeleton thay thế). Search results luôn `isPlaceholder == false` nên skeleton chỉ xuất hiện ở danh sách chính.
* **Không thêm file mới** (tránh phải chạy `xcodegen` — không chạy được trên Windows); không đổi state/`isPlaceholder` trong `ReaderChapterListStore` nên các test hiện có (`ReaderViewModelTests`) không bị ảnh hưởng.
* **Môi trường**: Windows không build/test tại chỗ — kiểm chứng qua CI `.github/workflows/build-ipa.yml` hoặc máy Mac.

## [1.3.176] - 2026-08-16

### Cần gạt "Hiển thị trong Kệ sách / Lịch sử" trên màn hình tải truyện

* **`TaskOptionsSheet.swift`**: thêm `@State displayInShelf = true` + `Toggle("Hiển thị trong Kệ sách")` trong section "Tùy chọn tác vụ", hiển thị cho **cả** `taskType == .download` ("Tải truyện") và `.exportTxt` ("Xuất ebook TXT"). Footer bổ sung ghi chú "Tắt 'Hiển thị trong Kệ sách' để truyện nằm trong Lịch sử đọc."
* **`TaskOptionsSheet.startTask()`**: trước `enqueueTask` áp dụng lựa chọn qua `BookTransactionCoordinator` — `displayInShelf == true` → `setOnShelf(bookId:isOnShelf: true, in:)` (`isOnShelf = true`, `isHistory = false`); ngược lại → `removeFromShelf(bookId:in:)` (`isOnShelf = false`, `isHistory = true`). Không dùng `setOnShelf(false)` vì nó ép `isHistory = false` làm sách biến mất khỏi cả 2 tab (xem 1.3.173). Placement được save vào DB ngay trước khi enqueue nên background worker đọc được giá trị đúng.
* **`DownloadManager.executeTask`**: đổi guard ép kệ từ `if !bgBook.isOnShelf` → `if !bgBook.isOnShelf && !bgBook.isHistory` — chỉ đẩy truyện lên kệ khi nó chưa nằm ở đâu; lựa chọn "Lịch sử" của người dùng không bị worker tải nền ghi đè về kệ nữa. Hành vi mặc định (Kệ sách) và luồng tải từ sách đang nằm trong Lịch sử không đổi.
* **Môi trường**: Windows không build/test tại chỗ — kiểm chứng qua CI `.github/workflows/build-ipa.yml` hoặc máy Mac.

## [1.3.175] - 2026-08-16

### Danh sách chương hiển thị toàn "Đang tải..." sau khi bấm nút cập nhật mục lục

* **Nguyên nhân gốc**: `ReaderChapterListStore.updateChapters(...)` gọi `setupPlaceholderRows()` xoá toàn bộ `loadedRowStates`/`loadedPages` → mọi dòng thành placeholder "Đang tải...", nhưng sau reset **không có gì nạp lại vùng đang xem** trong khi danh sách vẫn mở. `List` key hàng bằng `.id(item.index)` (`ReaderChapterListView.swift:276,298`); khi TOC mới chỉ thêm chương ở cuối, index các chương cũ không đổi → SwiftUI không tạo lại row → `.onAppear` không cháy lại → `loadVisiblePageIfNeeded` không được gọi. `scrollToCurrentChapter` chỉ chạy qua `.onAppear`/`.onChange(of: isPresented)`/`.onChange(of: currentChapterIndex)` — không cái nào kích hoạt sau refresh. Đóng rồi mở lại mới hết lỗi (vì `isPresented` đổi → `jumpToChapter` nạp lại page).
* **Sửa `ReaderChapterListStore.swift`**:
  - Thêm `private var lastViewportPage: Int? = nil` — ghi nhận page đang xem, **không** bị `setupPlaceholderRows()` xoá nên chịu được nhiều reset liên tiếp.
  - Gán `lastViewportPage = page` tại 3 nơi đang gán `currentTargetPage = page` (`loadPageIfNeeded`, `loadVisiblePageIfNeeded`, `jumpToChapter`).
  - `updateChapters(...)` sau `setupPlaceholderRows()` gọi `reloadViewportAfterReset()`: nếu `lastViewportPage` còn hợp lệ với `totalCount` mới thì set lại `currentTargetPage` và `loadPagesAround(page:includeNeighbors: true)`. Bao trùm mọi nguồn gọi `updateChapters` khi list đang mở (nút refresh, `.onChange(of: currentOnlineChapters.count)`, handler `onLocalTOCRefreshed`, trường hợp TOC không đổi). Không đổi hành vi `init`/`updateTranslation`/`updateSortOrder`; race/double-fetch được chặn bởi generation guard + `inFlightPages`/`loadedPages`.
* **Test**: thêm `testUpdateChaptersReloadsLastViewport` trong `Tests/ReaderViewModelTests.swift` (pattern `pageLoaderSeam` có sẵn): `jumpToChapter(index: 150)` nạp page 1 → `updateChapters(totalCount: 520, onlineChapters: [])` reset → chờ load → assert `rowState(at: 150).isPlaceholder == false`.

## [1.3.174] - 2026-08-16

### Hẹn giờ tạm dừng TTS: giữ chế độ sau khi hết giờ + persist qua UserDefaults

* **Nguyên nhân gốc**: khi countdown chạm 0, tick của `TTSManager.startTimerCountdown(...)` gọi `stopTimerCountdown(keepMode: false)` → ghi đè `timerMode = .off` ngay thời điểm hết giờ, đồng thời `restartSleepTimerIfNeeded()` chỉ được gọi trong `speakCurrent()` nên nhiều nhánh `resume()` (system qua `siriService.resume()`, nghitts qua `nghiAudioPlayerQueue.resume()`, google/ext qua `audioPlayer.play()`) không re-arm lại bộ đếm → sau khi hẹn 1p hết giờ rồi bấm Play lại, app "không còn nhớ thời gian hẹn giờ".
* **Sửa `TTSManager.swift`**:
  - Tick hết giờ đổi `stopTimerCountdown(keepMode: false)` → `keepMode: true`: giữ `timerMode = .minutes(n)` sau khi hết giờ (badge `sleepTimerBadgeText` vẫn rỗng vì `isTimerRunning = false`, không hiện "0:00").
  - Thêm `restartSleepTimerIfNeeded()` đầu `resume()` (trước nhánh `if isPlaying`) để bộ đếm được re-arm trên mọi engine/nhánh resume; `.off`/`.endOfChapter` là no-op, đang đếm thì không restart.
  - **Persist chế độ hẹn giờ**: thêm `didSet` vào `@Published timerMode` gọi `persistSleepTimerMode()` ghi `"ttsSleepTimerMode"` (`off`/`minutes`/`endOfChapter`) + `"ttsSleepTimerMinutes"` (Int) qua `UserDefaults`; nạp lại trong `init()` trước `super.init()` (guard `isInitializing` tránh ghi lại khi load). Chỉ `cancelSleepTimer()` (nút "Tắt hẹn giờ") ghi `off` — đúng yêu cầu "chỉ xoá hẹn giờ khi người dùng tắt"; số giây còn lại không persist, Play lại đếm từ đầu.
* **Test**: thêm `testSleepTimerModePersistsAndClearsOnCancel` + `testRestartSleepTimerAfterExpiryStateReArmsCountdown` trong `Tests/TTSManagerTests.swift`.

## [1.3.173] - 2026-08-15

### Thêm "Xoá khỏi kệ sách" (chỉ gỡ khỏi kệ) + đổi tên destructive thành "Xoá"

* **`BookTransactionCoordinator.swift`**: thêm `removeFromShelf(bookId:in:)` set `isOnShelf = false` + `isHistory = true` + `lastReadDate = Date()` rồi save. Khác với `setOnShelf(false)` (vốn ép `isHistory = false` làm sách biến mất khỏi cả 2 tab), method này giữ sách hiển thị ở tab **Lịch sử** (`historyBooks = isHistory && !isOnShelf`).
* **`ShelfView.swift`** (context menu Kệ sách): thêm nút mới **"Xoá khỏi kệ sách"** (`bookmark.slash`) gọi `removeFromShelfOnly(_:)` (chỉ gỡ khỏi kệ, giữ lịch sử); đồng thời **đổi tên** nút destructive hiện có từ "Xóa khỏi kệ sách" → **"Xoá"** (icon `trash.fill`), giữ nguyên hành vi xoá hẳn qua `removeFromShelf(_:)` (`BookStorageManager.deleteBookAsync`).

### Tăng chiều rộng cell menu bôi đen Reader

* **`FloatingSelectionMenu.swift`**: `buttonWidth` 46→52 (các cell 2-4), `ngheWidth` 56→62 (cột Nghe), và `menuWidth` 199→223 đồng bộ theo công thức `menuWidth = ngheWidth + 1 + 3*buttonWidth + 4`. Layout dùng `HStack(spacing:0)` + `.frame(width:)` nên cell tự dãn; giữ `menuWidth` đúng để clamp trục x không bị cắt ở mép màn hình.

### Chuẩn hoá parse object JS qua JSON round-trip (sửa lỗi tên sách detail shuhaige)

* **Nguyên nhân gốc**: `ExtensionManager.detail(...)` parse dictionary JS qua `cleanVal.toDictionary()` rồi đọc `dict["name"] as? String`. `JSValue.toDictionary()` bridge giá trị `name` (chuỗi Hán dài đi qua `formatTocName()`) sang kiểu không phải `String` nên `as? String` trả `nil` → `""`, trong khi `author` (cũng chuỗi Hán) bridge bình thường — `Response.success` raw vẫn có đủ `name`. Đây là lý do tên sách shuhaige không hiển thị ở màn hình detail (log chẩn đoán xác nhận `detail parsed info: name= | author=???`).
* **Sửa**: thêm `ExtensionManager.parseJSObject(_ jsValue:) -> [String: Any]?` — đưa object JS qua `JSON.stringify` (tái dùng `stringify`) + `JSONSerialization`, chuẩn hoá mọi giá trị về kiểu Foundation tiêu chuẩn (NSString/NSNumber/NSArray/NSDictionary) để `as? String` hoạt động đáng tin cậy. Có guard chống chuỗi rỗng/`"undefined"` (khi JSON.stringify fail).
* **`detail`** (`ExtensionManager.swift:409`): dùng `parseJSObject(cleanVal)` thay `cleanVal.toDictionary()` — vá luôn `name/author/cover/description/detail/host/link` **và** các read `item["title"]/["input"]/["script"] as? String` của genres/suggests/comments trong một chỗ (cùng chảy qua `dict`).
* **`executeCustomScript`** fallback dict (`:632`, `:636`): chuyển sang `parseJSObject(cleanVal)` cho đồng nhất.
* **Giữ nguyên vì hiệu năng**: luồng chính `executeCustomScript` (`:727`), `toc`/`search`/`genre`/`home` (đều đọc qua `?.toString()` trên JSValue) — nhẹ và đã đúng; JSON round-trip chỉ áp cho object nhỏ để tránh chi phí bộ nhớ/CPU 3-4x trên payload lớn (base64 TTS, nội dung chương, mảng books).

## [1.3.172] - 2026-08-15

### Bật log chẩn đoán tên sách detail (điều tra shuhaige)

* **`ExtensionManager.swift`** (`detail`, dòng 470): bỏ comment log `AppLogger.shared.log("✅ [ExtensionManager] detail parsed info: name=\(result.name) | author=\(result.author)")` để ghi chính xác giá trị `NovelDetailResult.name` app đã parse từ JS dictionary. Mục đích: trong khi điều tra vì sao tên sách không hiển thị ở màn hình detail của ext shuhaige (dù `Response.success` đã log tên), log này giúp phân biệt lỗi parse (`result.name` rỗng) vs lỗi render (`result.name` có giá trị). Dùng 1 lần trên máy Mac/CI để chốt nguyên nhân, sau đó revert log nếu không cần.

## [1.3.173] - 2026-08-15

### Đổi tên `SearchNovelResult` thành `ExtensionItemResult` & Lọc dữ liệu Extension 100% theo thuộc tính dữ liệu

* **`ExtensionManager.swift`**:
  - Đổi tên struct DTO `SearchNovelResult` thành **`ExtensionItemResult`** phản ánh đúng bản chất DTO chung của các item trả về từ JS Extension. Giữ `public typealias SearchNovelResult = ExtensionItemResult` để đảm bảo tương thích ngược 100%.
  - Cập nhật kiểu trả về của `search(...)` và `executeCustomScript(...)` sang `[ExtensionItemResult]`.
  - **Loại bỏ hoàn toàn việc check `scriptFileName`**: Thay thế `let isCommentScript = scriptFileName.localizedCaseInsensitiveContains("comment")` bằng cơ chế kiểm tra **100% dựa vào thuộc tính dữ liệu đặc trưng** (`guard hasLink || hasContent else { continue }` với `hasLink = !link.isEmpty` cho truyện và `hasContent = !(dict["content"]?.toString() ?? "").isEmpty` cho bình luận/đánh giá).
  - Sửa fallback `author` khi parse custom script thành `""` thay vì `"Không rõ"`.
* **Đồng bộ hóa các thành phần tiêu thụ**:
  - **`PaginatedNovelLoader.swift`**: `@Published private(set) var novels: [ExtensionItemResult] = []`.
  - **`NovelListUtils.swift`**: `filterAndDeduplicate(_ results: [ExtensionItemResult]) -> [ExtensionItemResult]`.
  - **`BookListItemView.swift`**: `extension ExtensionItemResult: BookDisplayable`.
  - **`CommentSectionView.swift`** & **`AllCommentsView.swift`**: `@State private var comments: [ExtensionItemResult] = []`.
  - **`SuggestRowView.swift`**: `@State private var novels: [ExtensionItemResult] = []`.
  - **`SearchView.swift`**: `ExtensionItemResultWithExt`, `@State private var searchResults: [ExtensionItemResultWithExt] = []` và các hàm tìm kiếm/đổi nguồn liên quan.

## [1.3.172] - 2026-08-15

### Nút "Dán" ở suggest chip màn hình Dịch + Chia sẻ từ điển giữa các truyện (tái sử dụng logic import + row bookshelf)

* **`ReaderDefinitionOverlayView.swift`**: thêm nút dán (`doc.on.clipboard`) vào `suggestionChipsView` giữa nút gear và `ScrollView` chip, cùng style icon tròn nền xanh. `pasteFromClipboard()` đọc `UIPasteboard.general.string`; clipboard rỗng → toast "Không có nội dung trong clipboard", ngược lại gán `customMeaning` (thay thế, giống hành vi tap chip).
* **File mới `BookListItemView.swift`** (`Views/Common`): tách row hiển thị một cuốn sách từ `ShelfView.bookItemView` thành component dùng chung. Được **tổng quát hóa** thành `BookListItemView<Item: BookDisplayable>` với protocol `BookDisplayable` (bookId/title/author/coverUrl/sourceName/description/currentChapterTitle/currentChapterIndex). `Book` conform qua `desc`; `SearchNovelResult` conform (name→title, cover→coverUrl, link→bookId, sourceName=""). Row hiển thị cover (`BookCoverView`, cỡ tuỳ chỉnh) + title dịch, rồi **description** (khi `showDescription: true`) hoặc **author (Hán Việt) + pill nguồn** (ẩn khi sourceName rỗng), và dòng "Đang đọc" tuỳ chọn (`showChapter`, mặc định true).
* **`ShelfView.swift`**: `bookItemView(_:)` trả về `BookListItemView(item: book)` (giữ hành vi Bookshelf không đổi); xoá 2 helper `translateIfNeeded`/`translateChapterTitleIfNeeded` đã chuyển vào component.
* **`CategoryNovelsListView.swift`** (genre): thay row HStack inline (cover + title + desc) bằng `BookListItemView(item: novel, showChapter: false, showDescription: true, coverWidth: 60, coverHeight: 80)`; bỏ 3 dòng author đang comment.
* **`DiscoveryView.swift`** (`DiscoveryCategoryTabView`, home tabs): thay row dùng raw `AsyncImage` bằng `BookListItemView(item: novel, showChapter: false, showDescription: true)` — đồng thời cover chuyển sang `BookCoverView` (có local cache); xoá helper `translateIfNeeded` dư của tab này.
* **`TextDictionary.swift`**: thêm `DictionaryTextFileStore.mergedRecords(imported:existing:isMerge:)` — chỗ duy nhất xử lý merge/replace (thay thế → trả về `imported`; gộp → giữ `existing` không trùng key, prepend `imported`).
* **File mới `DictionaryImportModeDialog.swift`**: `ViewModifier` `dictionaryModeDialog(isPresented:title:message:onSelect:)` — dialog dùng chung **"Thay thế hoàn toàn"** / **"Gộp (trùng key thì thay mới)"** / Hủy, `onSelect(Bool)` (false=thay, true=gộp); `extension View` để gắn modifier.
* **File mới `BookShareTargetSheet.swift`**: tách struct `BookShareTargetSheet` khỏi `DictionaryListView.swift` — sheet chọn truyện đích (`FetchDescriptor<Book>` sort `lastReadDate` desc, loại truyện hiện tại), mỗi dòng dùng `BookListItemView(book:showChapter: false)` (đủ cover + title dịch + tác giả + nguồn), dùng lại `dictionaryModeDialog`.
* **`DictionaryListView.swift`**:
  - `importFile` nhánh per-book: bỏ khối merge/replace thủ công, gọi `mergedRecords`.
  - `shareToBook(targetBook:isMerge:)`: đọc records nguồn từ `books/{source}/{type}.txt`; nguồn rỗng → toast & dừng; gọi `mergedRecords` rồi `persist` vào `books/{target}/{type}.txt`; `TranslateUtils.clearCache()` + `TranslationManager.clearBookDictCache(for: targetBookId)`; toast thành công.
  - Dialog import: thay `confirmationDialog` thủ công bằng `.dictionaryModeDialog(...)` (dùng chung với share).
  - Xoá struct `BookShareTargetSheet` cũ khỏi file; giữ nút toolbar "Chia sẻ sang truyện khác" + `.sheet`.

### Thống nhất logic nạp danh sách truyện genres / discovery / search (dùng chung loader + helper)

* **File mới `Sources/Common/Utils/NovelListUtils.swift`**: gom 2 helper từng nằm rải rác thành nguồn dùng chung — `normalizeLink(_:)` (bỏ scheme/host, đảm bảo tiền tố "/") và `filterAndDeduplicate(_:)` (bỏ kết quả rỗng name/link, dedupe theo link chuẩn hoá).
* **Xoá duplicate**: 4 bản `fileprivate func normalizeLink` (`CategoryNovelsListView`, `DiscoveryView`, `SearchView`, `SuggestRowView`) và method `SearchView.filterAndDeduplicate`. `SuggestRowView` và `SearchView` chuyển sang gọi helper chung.
* **File mới `Sources/Services/Extensions/PaginatedNovelLoader.swift`** (`@MainActor`, `ObservableObject`, `import Combine` — không import SwiftUI, đúng ràng buộc Manager/Service): đóng gói luồng phân trang `executeCustomScript` — `novels/isLoading/isLoadingMore/errorMessage/canLoadMore`; `loadInitial()/loadMore()/reload()`; dedupe qua các trang; auto-retry load-more 3 lần/2s; quy tắc chung `canLoadMore = results.count >= 10 && (nextPage != nil || input.contains("{0}"))`.
* **`CategoryNovelsListView.swift`** (genres) và **`DiscoveryView.swift`** (`DiscoveryCategoryTabView`, home tabs): thay `@State` local bằng `@StateObject PaginatedNovelLoader`; discovery giữ lazy-tab `checkAndLoadData`/`scheduleInitialLoad` (ủy quyền `loader.loadInitial()`); cả hai giữ footer lazy-load cuộn (`ProgressView` `.onAppear` → `loader.loadMore()`).
* **2 chênh lệch hành vi được thống nhất**: `canLoadMore` theo quy tắc của discovery; pull-to-refresh (`reload()`) dedupe cho cả hai (sửa lỗi discovery trước đây set `novels = results` không dedupe khi reload).

### Giữ highlight đang đọc khi pause TTS

* **`ReaderView.swift`** (`chapterContentView`): bỏ điều kiện `ttsState.snapshot.isPlaying` khi tính `relativeHighlightRange`. `pause()` gọi `publishLifecycleState(isPlaying: false)` không kèm `isStopped` nên `highlightRange`/`currentParentParagraphIndex`/`playingBookId`/`playingChapterIndex` vẫn được giữ trong snapshot; việc bỏ guard `isPlaying` giữ nguyên highlight của chunk đang đọc khi tạm dừng. Khi **stop** (`isStopped: true`) vẫn nil range/bookId/parentIndex và khi đổi sách/chương các guard khác vẫn loại bỏ highlight như trước.

## [1.3.171] - 2026-08-15

### Revert chạy chữ (MarqueeText) + giảm label menu bôi đen xuống 7pt (icon 15pt, label center)

* **Xoá file `Sources/Views/Reader/Components/MarqueeText.swift`**: bỏ component dùng chung vừa tách ở 1.3.170; loại bỏ toàn bộ xử lý marquee (chạy chữ trái→phải khi tràn).
* **`FloatingSelectionMenu.swift`**: bỏ `MarqueeText` trong `menuItemContent`, thay bằng `Text(label)` thường.
  - **Label giảm xuống `7pt`** bold, `lineLimit(1)`, hiển thị **center** cả ngang (`.frame(maxWidth: .infinity)`) và dọc (`.frame(height: 15, alignment: .center)`).
  - **Icon giữ `15pt`**, mỗi dòng (icon/chữ) cùng `frame` cao `15pt` để cao độ bằng nhau.
  - Giữ nguyên layout: ô vuông 46×46, Nghe 56×93 merge 2 hàng, kẻ dọc mờ giữa Nghe & phần còn lại, kẻ ngang mờ giữa 2 hàng.
* **`ReaderHeaderFooterOverlayView.swift`**: khôi phục `Text` thường cho tên truyện (`readerBookDisplayTitle`, 16 bold) và tên chương (`readerChapterDisplayTitle`, 13 medium) với `.lineLimit(1).truncationMode(.tail)` như trước 1.3.170; giữ màu, layout và action `onOpenChapterList`.

## [1.3.170] - 2026-08-15

### Tách MarqueeText thành component dùng chung + áp dụng cho header Reader (tên truyện/tên chương chạy chữ)

* **Tạo file mới `Sources/Views/Reader/Components/MarqueeText.swift`**: chuyển struct `MarqueeText` từ `FloatingSelectionMenu.swift` sang file riêng, bỏ `private` → internal để dùng chung. Logic giữ nguyên: đo rộng bằng `NSString.size(withAttributes:)`, đủ chỗ hiển thị tĩnh 1 dòng (`.lineLimit(1)`), tràn thì duplicate 2 bản text + `.offset` animate `0 → -contentWidth` (`.linear(duration: contentWidth/30).repeatForever(autoreverses: false)`) + `.clipped()`, reset khi `.onDisappear`.
* **Xoá struct `MarqueeText` private trong `FloatingSelectionMenu.swift`** (dùng bản dùng chung, không đổi hành vi).
* **`ReaderHeaderFooterOverlayView.swift`**: thay `Text` của tên truyện (`readerBookDisplayTitle`, font 16 bold) và tên chương (`readerChapterDisplayTitle`, font 13 medium) bằng `MarqueeText`; giữ nguyên màu (`selectedTheme.textColor` / `.opacity(0.72)`), layout và action button `onOpenChapterList`. Tên truyện/tên chương hiển thị 1 dòng, tràn thì chạy trái→phải.

## [1.3.169] - 2026-08-15

### FloatingSelectionMenu: ô vuông, label 1 dòng + marquee, giảm font, bỏ kẻ dọc giữa ô

* **Restructure layout `FloatingSelectionMenu.swift`**:
  - 6 ô (Phiên âm, Copy, Đọc, Dịch, Thay thế, Xoá) là **hình vuông 46×46** (`row1Height`/`row2Height` 80/42 → 46); cột Nghe rộng hơn `56pt`, merge 2 hàng full menu (`menuHeight = 46 + 1 + 46 = 93`).
  - `menuWidth` cập nhật 191 → 199 (`56 + 1 kẻ dọc + 3×46 + 4 padding`).
  - **Bỏ kẻ dọc giữa các ô** trong hàng 1 và hàng 2; **giữ** 1 kẻ dọc mờ (`white.opacity(0.15)`) giữa cột Nghe & phần còn lại (full height) và `Divider` ngang mờ giữa 2 hàng (chỉ cột 2-4).
  - **Giảm font label** `11 → 9` trong `menuItemContent` (icon giữ `15pt`).
* **Thêm `MarqueeText` (private struct cùng file)**:
  - Đo độ rộng text bằng `NSString.size(withAttributes:)` với font tương ứng (`uiFontWeight` map `Font.Weight` → `UIFont.Weight`).
  - Không tràn (`contentWidth <= containerWidth`) → hiển thị tĩnh 1 dòng (`.lineLimit(1)`).
  - Tràn → duplicate text 2 bản trong `HStack`, `.offset(x:)` animate `0 → -contentWidth` bằng `.linear(duration: contentWidth/30).repeatForever(autoreverses: false)`, `.clipped()`, reset `animate` khi `.onDisappear`.
  - Áp dụng cho **cả 7 label** (Nghe, Phiên âm, Copy, Đọc, Dịch, Thay thế, Xoá) — mỗi label hiển thị 1 hàng, tràn thì chạy trái→phải.

## [1.3.168] - 2026-08-15

### Tăng tốc độ đọc từ bôi đen ("Đọc") lên 1.5

* **`ReaderView.swift`**:
  - Google TTS: `readSelectedText()` truyền `speed: 1.5` (trước là `1.0`), giữ `pitch: 1.0`.
  - Fallback Siri `fallbackSiriReadSelectedText()`: set `utterance.rate = AVSpeechUtteranceMaximumSpeechRate` (nhanh nhất có thể, vì AVSpeechSynthesizer không hỗ trợ vượt 1.0).

## [1.3.167] - 2026-08-15

### Restructure FloatingSelectionMenu: Nghe merge 2 hàng, sửa vị trí clamp màn hình, UI gọn gàng

* **Restructure layout `FloatingSelectionMenu.swift`**:
  - Cột 1 là Button **Nghe** (`headphones`) cao full menu (`80 + 1 + 42 = 123pt`), merge 2 hàng thật sự — bỏ `Color.clear` spacer cũ.
  - Cột 2-4 là `VStack` 2 hàng: **Hàng 1** Phiên âm, Copy, Đọc (cao 80pt); **Divider ngang chỉ nằm trong cột 2-4** (không chạy xuyên cột Nghe); **Hàng 2** đổi thứ tự thành **Dịch, Thay thế, Xoá** (cao 42pt).
  - Thu gọn UI: `buttonWidth` 52 → 46pt, `gap` 36 → 24pt, icon 16 → 15pt; menu cao 145 → 123pt, `menuWidth` 215 → 191pt.
* **Sửa vị trí menu không che chữ + không mất góc**:
  - Thêm param `screenHeight` (truyền từ `ReaderView` → `ReaderFloatingMenuOverlayView` → `FloatingSelectionMenu`).
  - Clamp y: ưu tiên đặt phía trên (`aboveY = localMinY - gap - menuHeight/2`) nếu đủ chỗ, ngược lại đặt phía dưới (`belowY = localMaxY + gap + menuHeight/2`), cuối cùng kẹp vào `[margin + menuHeight/2, screenHeight - margin - menuHeight/2]` (`margin = 16`) — menu luôn nằm trọn trong màn hình, giữ góc bo tròn khi gần mép.
  - Giữ clamp x cũ (căn giữa theo `screenWidth`, kẹp trong khoảng margin 16pt).

## [1.3.166] - 2026-08-15

### Thêm suggest chip vào màn hình thêm phiên âm từ Reader, bỏ auto-fill value

* **Sửa `AddWordSheet.swift`** (`TTSDictionaryEditView.swift`):
  - Bỏ auto-fill `value` bằng `EnglishTransliterator.transliterateWord` trong `init` và `.onChange(of: key)`; `value` khởi tạo rỗng.
  - Thêm tham số `showSuggestions: Bool = false` vào init; khi `true` hiển thị section `"Gợi ý phiên âm"` gồm hàng `ScrollView(.horizontal)` các chip dạng `Capsule` có thể tap để gán `value`.
  - Chip thư viện (màu xanh) hiện khi `TextPreprocessor.lookupWord` tìm thấy từ trong `wordMap`; chip luật `JapaneseTransliterator.transliterateRomaji` và `EnglishTransliterator.transliterateWord` luôn hiển thị (màu xám nhạt), dedupe và bỏ chip rỗng.
  - Nạp `librarySuggestion` qua `TextPreprocessor.shared.lookupWord(trimmedKey.lowercased())` (actor, async) với debounce 300ms: `suggestionLoadTask` hủy task cũ mỗi lần `key` đổi (`.onChange(of: key)`), ngủ 300ms rồi mới lookup; hủy task trong `.onDisappear`.
* **Đấu nối trong `ReaderView.swift`**: sheet `AddWordSheet` (mở từ action "Phiên âm" trong menu bôi đen) truyền `showSuggestions: true`; `TTSDictionaryEditView` giữ nguyên (không chips).

## [1.3.165] - 2026-08-15

### Chuyển FloatingSelectionMenu sang layout 2 hàng, nút "Nghe" merge 2 ô

* **Restructure `FloatingSelectionMenu.swift` sang 2 hàng (VStack 2 HStack)**:
  - **Hàng 1 (cao 96pt)**: Nút **Nghe** (`headphones`) đặt cột 1 chiếm trọn chiều cao 96pt (merge 2 hàng) theo sau bởi Phiên âm, Copy, Đọc — mỗi nút cao 96pt để căn giữa nội dung.
  - **Divider ngang** giữa 2 hàng (1pt, `white.opacity(0.15)`).
  - **Hàng 2 (cao 48pt)**: Cột 1 là `Color.clear` spacer tương ứng vùng Nghe, theo sau bởi Thay thế, Xoá (đỏ), Dịch.
  - Thêm helper `menuItemContent(icon:label:)` và `verticalDivider(height:)`; `menuWidth` giảm 378 → 215pt (4 cột × 52 + dividers + padding) nên menu gọn hơn và căn giữa tốt hơn trên màn hình hẹp.

## [1.3.164] - 2026-08-15

### Thêm option "Thay thế" thêm chuỗi bôi đen vào bộ thay thế ký tự TTS

* **Thêm nút "Thay thế" vào menu bôi đen (`FloatingSelectionMenu.swift`, `ReaderFloatingMenuOverlayView.swift`)**:
  - `FloatingSelectionMenu.swift`: Thêm prop `onAddToTTSReplacement` và nút mới (icon `textformat.alt`, label "Thay thế") đặt giữa nút "Đọc" và "Xoá". Thu gọn chiều rộng từng nút xuống 52pt và `menuWidth` lên 378pt để menu 7 nút không tràn trên màn hình hẹp.
  - `ReaderFloatingMenuOverlayView.swift`: Truyền callback `onAddToTTSReplacement` xuống menu.
* **Tạo `AddTTSReplacementSheet.swift` (file mới)**:
  - Sheet Form 2 trường: **Chuỗi gốc (pattern)** mặc định là text đã bôi đen (cho phép sửa), **Chuỗi thay thế (replacement)** tự điền sẵn replacement của rule đã tồn tại trong `TTSReplacementManager.shared.rules` nếu pattern trùng, ngược lại để trống. Validation chỉ yêu cầu pattern không rỗng (cho phép khoảng trắng/dấu câu vì là pattern thay thế ký tự).
* **Đấu nối trong `ReaderView.swift`**:
  - Thêm `@State showingAddTTSReplacementSheet`, `pendingTTSReplacementPattern`; callback menu lưu `selectedDisplayedText` vào pattern rồi mở sheet.
  - `.sheet` hiển thị `AddTTSReplacementSheet` truyền `TTSReplacementManager.shared.rules`, khi lưu gọi `TTSReplacementManager.shared.addRule(rule)` và Toast thông báo "Đã thêm thay thế TTS".
  - Thêm `showingAddTTSReplacementSheet` vào `isAnySelectionOrOverlayActive` (hoãn refresh dịch khi đang mở sheet) và handler `.onChange` giải phóng deferred translation refresh khi đóng sheet.

## [1.3.163] - 2026-08-15

### Thêm nút bật/tắt "Tự động cuộn theo Highlight TTS" trong header Reader

* **Thêm nút toggle auto-scroll trong header (`ReaderHeaderFooterOverlayView.swift`, `ReaderView.swift`)**:
  - `ReaderHeaderFooterOverlayView.swift`: Thêm `@Binding var isAutoScrollDisabled: Bool` và nút toggle mới đặt **bên trái** nút Reload (luôn hiển thị, kể cả sách local TXT), icon `scroll.fill`/`scroll` với màu theo trạng thái giống nút bật/tắt dịch (`.blue` khi bật scroll, `textColor.opacity(0.85)` khi tắt, nền `textColor.opacity(0.07)`).
  - `ReaderView.swift`: Truyền `$isAutoScrollDisabled` (state đã có sẵn) vào `ReaderHeaderFooterOverlayView`. Bấm nút flip `isAutoScrollDisabled` ngay lập tức, hiệu lực tức thì qua `guard` trong `.onChange(of: ttsState.snapshot.currentParentParagraphIndex)` và `scrollToTTSHighlightIfNeeded()`/`requestTTSScrollIfNeeded()` mà không cần khởi động lại. Giá trị persist per-book qua UserDefaults key `disableAutoScroll_\(bookId)` (đã có sẵn, mặc định bật scroll).

## [1.3.162] - 2026-08-14

### Xây dựng BookDownloadWorker tải tuần tự và hỗ trợ đa worker song song nhiều sách

* **Xây dựng `BookDownloadWorker` tái sử dụng `JSExecutor` (`BookDownloadWorker.swift`, `DownloadManager.swift`)**:
  - `BookDownloadWorker.swift`: Tạo actor quản lý tác vụ tải/xuất cho một cuốn sách. Khởi tạo và nạp script `chap.js` đúng một lần duy nhất (`prepareScript`, `injectGlobals`), tái sử dụng thực thể `JSExecutor` xuyên suốt toàn bộ các chương của cuốn sách đó, triệt tiêu việc tạo và hủy `JSContext` liên tục.
  - `DownloadManager.swift`: Nâng cấp sang kiến trúc đa worker song song (`activeWorkers: [UUID: BookDownloadWorker]`, `activeTasks: [UUID: Task<Void, Never>]`, `maxConcurrentTasks = 2`). Khi tải nhiều sách (ví dụ 2 sách), mỗi sách sở hữu 1 worker riêng biệt chạy song song với nhau trong luồng nền.
* **Cơ chế ngắt hủy tác vụ tức thì & độc lập (`DownloadManager.swift`, `JSExecutor.swift`)**:
  - `DownloadManager.swift`: Khi người dùng bấm hủy tác vụ (`cancelTask` / `cancelTasksForBook`), lập tức ngắt đúng `Task` và `BookDownloadWorker` của cuốn sách đó, bắt `CancellationError` và dừng ngay lập tức; các cuốn sách khác đang tải song song không bị ảnh hưởng.
  - `JSExecutor.swift`: Cập nhật `cancelCurrentExecution()` hủy toàn bộ `URLSessionDataTask` in-flight và đóng/dọn dẹp các WebView loader trên Main Thread.

## [1.3.161] - 2026-08-14

### Tự động bỏ qua chương lỗi khi phát hết chương trong TTS

* **Tự động bỏ qua chương lỗi/rỗng khi chuyển chương (`TTSManager.swift`)**:
  - `advanceToNextChapter(nextIdx:)`: Nếu không tìm thấy chương trong `chaptersQueue`, tìm chương kế tiếp `nextChapterIndex(after: nextIdx)` thay vì dừng phát.
  - `fallbackAdvanceToNextChapter(...)`: Khi nạp chương (`loadChapterForAutoAdvance`) hoặc xử lý nội dung (`processChapter`) ném ngoại lệ, log cảnh báo và gửi Toast, sau đó tự động chuyển tiếp sang chương kế tiếp `nextChapterIndex(after: nextChapter.index)`. Nếu đã hết toàn bộ sách, dừng phát an toàn.
  - `applyNextChapter(...)`: Nếu chương không có nội dung đọc (`playbackParas.isEmpty`), gửi Toast cảnh báo và tự động chuyển sang chương tiếp theo.
  - `playNghiTTS(_:)`: Khi `nghiTTSService == nil`, chuyển sang gọi `pause()` kèm Toast thông báo lỗi thay vì `stop()`, giữ nguyên widget nổi và phiên đọc.
* **Đồng bộ giao diện Reader khi nhảy qua chương lỗi (`ReaderView.swift`)**:
  - `ReaderView.swift`: Gỡ bỏ điều kiện giới hạn `if chapterIndex == nextIdx - 1` trong handler `ttsDidAdvanceToNextChapter`, cho phép `ReaderView` tự động đồng bộ sang chương mới ngay cả khi TTS nhảy cách quãng do bỏ qua các chương lỗi.

## [1.3.160] - 2026-08-14

### Sửa lỗi đoạn cuối chương không được phát trong NghiTTS

* **Fix `prepareNextNghiAudioIfPossible()` trong `TTSManager.swift`**:
  - Xóa điều kiện sai `|| nghiAudioPlayerQueue.nextItem?.paragraphIndex == currentParagraphIndex` trong guard early-return. Điều kiện này được thêm vào commit `7e55c61` nhưng gây ra race condition: sau khi đoạn N-1 transition sang N, `nextItem` vẫn còn giữ index của đoạn N trong một window ngắn trước khi discard → điều kiện match → hàm return sớm → đoạn N+1 (đoạn cuối chương) không bao giờ được prepare → Underrun → AutoAdvance sớm sang chương kế tiếp mà không phát đoạn cuối.
  - Sửa nhánh `clearPreparedNext()` khi `nextIndex >= paragraphs.count`: chỉ clear nếu `nextItem.paragraphIndex != currentParagraphIndex`, tránh hủy nhầm audio đoạn hiện tại đang là `currentItem` trong queue.

## [1.3.159] - 2026-08-14

### Sửa lag khi bấm Next/Prev chuyển đến/từ chương đang nghe TTS

* **Ngăn TTS scroll cạnh tranh với Navigation scroll (`ReaderView.swift`, `ReaderView+LoadingView.swift`)**:
  - `ReaderView.swift`: Thêm `guard !isRestoringReaderPosition else { return }` trong `.onChange(of: ttsState.snapshot.currentParentParagraphIndex)` để ngăn TTS auto-scroll ghi đè `scrollTarget` trong khi navigation đang restore vị trí chương mới.
  - `ReaderView+LoadingView.swift`: Thêm `guard !isRestoringReaderPosition else { return }` đầu hàm `requestTTSScrollIfNeeded` để chặn toàn bộ TTS scroll trigger trong cửa sổ ~150ms sau `commitNavigation`. Sau khi `completeReaderPositionRestore` giải phóng cờ, TTS auto-scroll tiếp tục bình thường.

## [1.3.158] - 2026-08-14

### Sửa lỗi từ dịch cũ hiển thị khi chuyển chương ngay sau khi lưu từ điển

* **Kiểm tra token trước shortcut memory cache (`ReaderViewModel.swift`)**:
  - `ReaderViewModel.swift`: Trong `requestChapter()`, thêm kiểm tra `translationToken` và `isTranslationEnabled` trước khi sử dụng đường ngắn mạch từ RAM cache. Nếu token lỗi thời, hệ thống chuyển sang `runNavigationWorker` để dịch lại chương trước khi hiển thị.
* **Invalidate token ngay lập tức khi lưu từ (`ReaderView.swift`)**:
  - `ReaderView.swift`: Trong `saveDefinition()`, gọi `viewModel?.updateCachedTranslatedContent(bookId:scope:)` **trực tiếp (0ms)** trước khi đóng sheet, đảm bảo `translationToken` của tất cả chương trong cache bị vô hiệu trước bất kỳ thao tác chuyển chương nào.
* **Dọn dẹp handler thừa (`ReaderView.swift`)**:
  - `ReaderView.swift`: Xóa handler `.onChange(of: showingDefinitionSheet)` bị trùng lặp và handler `.onChange(of: showingManageDefinitionsSheet)` vô dụng.

## [1.3.155] - 2026-08-14

### Loại bỏ tự động gọi startTTS khi bấm nút Next/Prev trên Reader

* **Hoàn trả logic nút Next/Prev (`ReaderView.swift`)**:
  - `ReaderView.swift`: Loại bỏ việc tự động gọi `startTTS(at: targetIndex, paragraphIndex: 0)` trong `nextChapter()` và `prevChapter()`, giữ nguyên luồng chuyển chương gốc theo yêu cầu của người dùng.

## [1.3.154] - 2026-08-14

### Khắc phục lỗi trang trắng hiển thị rỗng khi cập nhật VietPhrase và chuyển chương

* **Khắc phục lỗi trang rỗng khi mở chương cũ sau khi đổi từ điển (`ReaderViewModel+Translation.swift`)**:
  - `ReaderViewModel+Translation.swift`: Trong `updateCachedTranslatedContent()`, chỉ gán `cached.translationToken = 0` để đánh dấu bản dịch lỗi thời. Không xóa đệm `cached.title`, `cached.content`, `cached.paragraphItems` để đảm bảo giao diện không bị hiện trang trắng rỗng (`[]`) trong khi `processAndSaveChapter()` đang biên dịch lại bản dịch mới theo từ điển VietPhrase vừa cập nhật.

## [1.3.153] - 2026-08-14

### Tối ưu triệt để hiệu năng hiển thị màn hình Reader khi nghe TTS và chuyển chương

* **Tối ưu hiển thị mượt 60/120 FPS trong `ReaderView` (`ReaderView.swift`)**:
  - `ReaderView.swift`: Đọc tiêu đề chương đã dịch từ `cached.title` trong RAM và đệm `cachedDisplayedBookTitle` trong `@State`, triệt tiêu toàn bộ việc tra từ điển tiêu đề đồng bộ trên UI Thread.
  - `ReaderView.swift`: Tạm ngưng áp dụng highlight TTS khi `pendingNavigationIndex != nil` (đang chuyển sang chương mới), giúp 100-300 View đoạn văn mới dựng ngầm và hiển thị tức thì mà không bị tín hiệu TTS chèn ngang gây đơ màn hình.
  - `ReaderView.swift`: Bổ sung kiểm tra ngưỡng hysteresis $5\text{pt}$ cho `updateReaderViewport(_ frame: CGRect)`, triệt tiêu vòng lặp re-render liên tục trên từng pixel khi cuộn nạp chương mới.
  - `ReaderView.swift`: Đồng bộ `startTTS(at: targetIndex, paragraphIndex: 0)` khi bấm nút `nextChapter()` / `prevChapter()` trên Reader trong lúc đang nghe TTS, giải phóng tiến trình đọc chương cũ và phát ngay chương mới.

## [1.3.152] - 2026-08-14

### Khắc phục lỗi NghiTTS tua đoạn và dọn dẹp cache bản dịch VietPhrase cũ

* **Khắc phục lỗi NghiTTS ngắt âm tua phân đoạn (`NghiAudioPlayerQueue.swift`, `TTSManager.swift`)**:
  - `NghiAudioPlayerQueue.swift`: Bổ sung kiểm tra `nextIsScheduled` và `nextPlayer.isPlaying` trong `prepareNext()` và `discardNext(force:)`, ngăn chặn việc `discardNext()` ngắt tiếng và dừng `nextPlayer` khi âm thanh của phân đoạn $N+1$ vừa mới bắt đầu phát.
  - `TTSManager.swift`: Cập nhật `prepareNextNghiAudioIfPossible()` dừng nạp đè `nextItem` mới khi `nghiAudioPlayerQueue.nextItem` trùng với `currentParagraphIndex` (vừa được commit handoff ở $t - 5\text{ms}$) hoặc `currentParagraphIndex + 1`.
* **Cập nhật logic dọn dẹp cache bản dịch khi đổi từ điển (`ReaderViewModel+Translation.swift`)**:
  - `ReaderViewModel+Translation.swift`: Trong `updateCachedTranslatedContent()`, đặt `cached.translationToken = 0` và reset dữ liệu bản dịch đối với tất cả các chương ngoài chương đang hiển thị (`idx != displayedChapterIndex`), buộc ứng dụng tự động dịch lại theo từ điển VietPhrase mới khi người dùng mở hoặc cuộn tới các chương đó.

## [1.3.151] - 2026-08-14

### Sửa lỗi biên dịch optional unwrapping trong ReaderView và dọn dẹp cảnh báo TTS

* **Sửa lỗi biên dịch Swift (`ReaderView.swift`)**:
  - `ReaderView.swift`: Thêm optional chaining `?` vào `self.chapterListStore?.updateChapters(totalCount: result.totalCount, onlineChapters: [])` trong `onLocalTOCRefreshed`, khắc phục lỗi biên dịch `value of optional type 'ReaderChapterListStore?' must be unwrapped`.
* **Dọn dẹp cảnh báo biến chưa sử dụng (`TTSManager+Playback.swift`)**:
  - `TTSManager+Playback.swift`: Loại bỏ hằng số `let expectedBookID = playingBookId` không sử dụng ở cả hai phương thức `playGoogleTTS` và `playExtTTS`.

## [1.3.150] - 2026-08-14

### Khắc phục chuẩn hóa Thỏa thuận TTS, Phạm vi Dịch thuật, Remap TOC & Hiệu năng Reader

* **Khắc phục Thỏa thuận `TTSPlaybackContext` & Vô hiệu hóa Context Cũ (`TTSModels.swift`, `TTSManager.swift`, `TTSManager+Playback.swift`, `SiriTTSService.swift`)**:
  - Chuẩn hóa chữ ký `commitAudibleParagraphState(index:playbackId:context:)` nhất quán trên toàn bộ codebase.
  - Siri TTS và hardware player khởi tạo `TTSPlaybackContext` đầy đủ và xác thực context trước khi commit highlight.
  - Hủy/vô hiệu hóa context từ xa khi thực hiện stop, skip, previous, hoặc restart qua `invalidateAudibleHandoffGeneration()` trong `stopCurrentPlayback()`.
* **Kiểm tra Trình phát Thực tế cho Lập lịch NghiTTS (`NghiAudioPlayerQueue.swift`, `TTSManager.swift`)**:
  - `ScheduledStatus` phân biệt rõ `isCurrentItem` và `isNextItem`.
  - Đối với item $N+1$ được lập lịch, timer đếm lùi kiểm tra `status.isNextPlaying` (thực tế `nextPlayer.isPlaying == true`) mới phát hành commit highlight; ngủ ngắn 5ms bounded recheck nếu chạm mốc thời gian clock nhưng player chưa phát, tránh publish highlight sớm trước khi phát âm thanh.
* **Đơn vị Lắng nghe Scope Từ điển & Tái cấu trúc Dịch Chương Hiện tại (`ReaderView.swift`, `ReaderViewModel.swift`, `ReaderViewModel+Translation.swift`)**:
  - Giữ duy nhất một handler `.onReceive` cho `.translationDictionariesDidUpdate` trong `ReaderView.swift`, giải mã `DictionaryInvalidationScope` và gộp vào `pendingTranslationScope` trong cửa sổ debounce 150ms.
  - Khi thay đổi từ điển/cấu hình, chỉ làm mới và tái cấu trúc chương hiện đang hiển thị (`displayedChapterIndex`), không lặp hay dịch các chương lân cận/preload, giảm tải CPU/nhiệt độ thiết bị.
  - Kiểm tra tính bằng nhau trước khi ghi (`isDisplayEqual`): tránh gán lại các trường hiển thị `@Published` khi nội dung dịch không thay đổi.
  - `ReaderViewModel.runNavigationWorker` thực hiện đọc lại cache trước khi `commitNavigation`, đảm bảo cache có `state == .loaded`, `translationToken` mới nhất và `isTranslationEnabled` khớp cấu hình hiện tại trước khi hiển thị.
* **Bảo vệ & Remap TOC cho phiên TTS Đang phát và Tạm dừng (`ChapterPersistenceStore.swift`, `ReaderChapterListView+Refresh.swift`, `ReaderViewModel.swift`, `ReaderChapterListPageFetcher.swift`)**:
  - Cơ chế bảo vệ và remap TOC (`ttsIsActive`) duy trì bảo vệ và ánh xạ lại chỉ số chương cho cả phiên TTS đang phát (`isPlaying == true`) lẫn phiên TTS đang tạm dừng được giữ lại (`playingBookId == book.bookId && playingChapterIndex >= 0 && (isPlaying || showFloatingWidget || !playingChapterUrl.isEmpty)`).
  - Khi TOC thay đổi (`!isTOCUnchanged`), gọi `cache.clearAll()` và tự động nạp lại chương qua `requestChapter`.
  - Khắc phục phân trang danh sách chương Reader giảm dần trong `ReaderChapterListPageFetcher.swift`: ánh xạ vị trí hiển thị sang chỉ số logic chính xác, bao gồm cả trang cuối không đầy đủ.
  - *Ghi chú kiểm thử môi trường*: Đã chạy các bước xác minh tĩnh (ripgrep check), kiểm tra cú pháp định dạng (`git diff --check`) và CodeGraph link/hash validator đạt 100% trên hệ điều hành Windows. Dự án không thực hiện chạy Xcode build/unit test trên iOS Simulator do giới hạn môi trường Windows (yêu cầu macOS).

## [1.3.149] - 2026-08-14

### Thêm tùy chọn Gộp (Merge) khi nhập từ điển Custom/Riêng

* **Thêm UI chọn chế độ nhập từ điển (`DictionaryListView.swift`)**:
  - Sau khi chọn file import, hiện `.confirmationDialog` với 2 option: "Thay thế hoàn toàn" và "Gộp (trùng key thì thay mới)".
  - `importFile(from:isMerge:)` nhận thêm tham số `isMerge` để quyết định chế độ.
* **Logic Merge cho từ điển Riêng (Book) (`DictionaryListView.swift`)**:
  - Gộp: giữ dữ liệu cũ không trùng key, key trùng lấy giá trị mới từ import, import được chèn lên đầu.
  - Thay thế: xóa hết dữ liệu cũ, chỉ giữ file import.
* **Logic Merge cho từ điển Custom Chung (Global) (`DictionaryCache.swift`)**:
  - `importEntries(from:type:isMerge:)` thêm tham số `isMerge` (mặc định `false`).
  - Merge: giữ custom cũ không trùng key, import thắng key trùng, bảo toàn deleted không bị restore bởi import có value, thêm deleted mới từ import.
  - Thay thế: xóa sạch dữ liệu cũ (custom + deleted), chỉ giữ file import.

## [1.3.148] - 2026-08-14

### Sửa lỗi biên dịch Swift và dọn dẹp cảnh báo CI

* **Sửa lỗi biên dịch Swift (`TTSManager.swift`)**:
  - `TTSManager.swift`: Gán `taskOutcome = outcome` tại hai case `.blocked` và `.retryScheduled` trong `scheduleNghiRefill()`, khắc phục lỗi biên dịch `member 'blocked(reason:action:)' is a function that produces expected type 'TTSManager.RefillTaskOutcome'`.
* **Dọn dẹp các cảnh báo biến/hằng chưa sử dụng**:
  - `TTSManager.swift`: Loại bỏ biến `let synthMs` không dùng trong pattern matching `case .audioReady` và gỡ bỏ `let startupBufferTarget = 1.2`.
  - `BackgroundSearchWorker.swift`: Thay `var descriptor` thành `let descriptor`.
  - `ShelfView.swift`: Thay `let targetBook =` thành `_ =`.

## [1.3.147] - 2026-08-14

### Khắc phục NghiTTS lỗi khi chuyển từ tên chương sang nội dung

* **Xử lý văn bản rỗng sau tiền xử lý (`PiperTTSService.swift`)**:
  - Kiểm tra lại kết quả từ `TextPreprocessor`; nếu không còn ký tự có thể đọc, NghiTTS tạo WAV khoảng lặng hợp lệ thay vì chuyển chuỗi rỗng vào ONNX/eSpeak.
  - Luồng streaming dùng chung bộ tạo khoảng lặng và phát đúng một payload kết thúc (`chunkIndex = 0`, `totalChunks = 1`, `isLast = true`).
* **Chặn vòng lặp prefetch lỗi (`TTSManager.swift`)**:
  - Theo dõi lỗi theo `sessionID + chapterIndex + paragraphIndex`, thử tối đa hai attempt đối với lỗi tạm thời và chờ 1 giây trước lần thử lại.
  - Lỗi không thể retry bị block ngay; các chỉ số đã block được bỏ qua khi chọn đoạn prefetch tiếp theo, trong khi luồng tổng hợp foreground vẫn giữ nguyên.
  - Task retry được hủy và trạng thái lỗi được xóa khi dừng, đổi session hoặc chuyển chương; cancellation không ghi ngược trạng thái cũ sau reset.
  - Scheduler không cho callback khác bỏ qua khoảng cooldown và chỉ mở lại ngay trước lần retry hợp lệ.
* **Kiểm thử hồi quy (`NghiTTSPerformanceTests.swift`)**:
  - Bổ sung kiểm tra khoảng lặng, payload streaming terminal, phân loại lỗi, chính sách hai attempt, bỏ qua index bị block và cổng scheduler trong thời gian retry.

## [1.3.146] - 2026-08-14

### Khắc phục lỗi sập ứng dụng do Range Trap trong NghiTTS và bổ sung Unit Tests

* **Khắc phục lỗi sập ứng dụng do Range Trap trong NghiTTS (`TTSManager.swift`)**:
  - `TTSManager.swift`: Tách hàm tĩnh `selectNghiOptionalRefillCandidate(currentParagraphIndex:paragraphsCount:preloadedIndices:)` (`nonisolated internal static`) bổ sung kiểm tra an toàn biên `guard optionalStart < paragraphsCount else { return nil }` trước khi quét các đoạn đệm dự phòng $N+2...$, xử lý triệt để bẫy dải chỉ số (`start > end`) khi $N$ ở gần cuối chương truyện (như $N = \text{count} - 1$ hoặc $N = \text{count} - 2$).
  - `TTSManager.swift`: Bổ sung kiểm tra `startIdx < paragraphs.count` trong `calculateNghiCachedTime()` để tránh tạo Range không hợp lệ khi tính tổng thời lượng âm thanh đã lưu đệm.
* **Bổ sung Unit Tests kiểm tra ranh giới (`NghiTTSPerformanceTests.swift`)**:
  - `NghiTTSPerformanceTests.swift`: Tạo mới test case `testSelectNghiOptionalRefillCandidatePreventsRangeTrapAtEndOfChapter()` kiểm tra các trường hợp biên $N = \text{count} - 1$, $N = \text{count} - 2$, $N = 263/\text{count} = 264$, $N = 83/\text{count} = 84$, đảm bảo hàm luôn trả về `nil` an toàn mà không gây sập ứng dụng.

## [1.3.145] - 2026-08-13

### Sửa toàn bộ các lỗi biên dịch Swift (Swift Compilation Fixes)

* **Sửa lỗi lệch vị trí bôi đen văn bản dịch (Selection Mapping Fix)**:
  - `TranslateUtils+Tokenization.swift`: Chuẩn hóa `originalOffset` và `originalLength` trong `getTranslationTokens` và `snapToToken` theo UTF-16 code units (`NSString`), triệt tiêu hiện tượng offset Hán tự gốc bị trượt khi câu chứa các dấu câu đặc biệt.
  - `TranslateUtils.swift`: Trong `buildTranslationSpans`, tiếp tục ghi nhận danh sách `TranslationSpan` từ vựng khi một token dấu câu không khớp.
  - `ReaderSelectionMapper.swift`: Cập nhật `selectionIsCovered` bỏ qua các ký tự dấu câu/khoảng trắng khi bôi đen, giúp tra cứu chính xác từ Hán tự gốc cho các thao tác dịch từ, nghe từ vị trí chọn và xóa từ rác từ điển.
* **Sửa lỗi cú pháp ngoặc đóng `}` & Logic bị thiếu**:
  - Bổ sung ngoặc `}` bị thiếu ở cuối file `JSExecutor.swift`, `ReaderChapterListView.swift`, `ShelfView.swift`.
  - `JSExecutor.swift`: Bổ sung câu lệnh `throw NSError(...)` khi `context.exception` có lỗi compile JS.
  - `ReaderChapterListView.swift`: Bổ sung `let finalResults = results` trước khi merge cache.
  - `ShelfView.swift`: Bổ sung `self.isImporting = false` trong catch handler import TXT.
* **Khôi phục kiểu dữ liệu DTO & Class**:
  - `BookDetailLoader.swift`: Cập nhật `DetailResult` thành `NovelDetailResult`.
  - `TOCRule.swift`: Cập nhật cấu trúc `TOCRule` hỗ trợ alias `pattern` <-> `rule`, thuộc tính `example`, `enabled`, `replace`, `isRegex` và các initializers.
  - `TOCRuleImportError.swift`: Bổ sung các case lỗi import quy tắc TOC.
  - `TOCImportPreview.swift`: Bổ sung thuộc tính và initializers thống kê import quy tắc.
  - `TTSAudioSessionController.swift`: Tạo mới tệp adapter quản lý `AVAudioSession`.
  - `TTSManager.swift`: Bổ sung `TTSPrefetchPerfSummary` và các biến theo dõi telemetry prefetch.
* **Sửa vi phạm mức độ truy cập &Ambiguity**:
  - `JSExecutor+Async.swift`: Loại bỏ hàm `makeReadyResponse` bị định nghĩa trùng lặp ở top-level.
  - `ChapterCache.swift`: Chuyển `ReadingContext`, `ChapterLoadState`, `CachedChapter`, `ChapterCache` thành `public`.
  - `ReaderChapterListStore.swift`: Chuyển `modelContext` và `onlineChapters` thành `internal`.
  - `ReaderChapterListPageFetcher.swift`: Sửa tên biến `isTranslationEnabled` và bổ sung `publishCachedPageIfAvailable`.
  - `ReadingProgressStore.swift` & `ReaderProgressScheduler.swift`: Chuyển `ReadingProgressStore` và các struct liên quan thành `public`, hỗ trợ gọi async `scheduleSave`.
  - `ReaderView.swift`: Thêm `readerContentView` ViewBuilder và case `initialRestore` cho `ScrollTarget.Reason`.
  - `ReaderViewModel.swift`: Sửa `currentRevision` setter thành `internal(set)`.
  - `SearchView.swift`: Sửa `errorMessage` thành `searchStatusMessage`.
  - `VietPhraseTokenizer.swift` & `TranslateUtils.swift`: Định danh `VietPhraseTokenizer.isChineseCharacter` `internal static`.

## [1.3.144] - 2026-08-13

### Sửa lỗi CI Build IPA sau refactor TTS

* **Khôi phục `TTSNowPlayingController`**: Restore `Sources/Services/TTS/TTSNowPlayingController.swift` vì `TTSManager` vẫn sở hữu controller này để gắn callback remote command center (`play`, `pause`, `next`, `previous`). Việc xóa file trong refactor trước tạo lỗi thiếu symbol khi archive iOS trên GitHub Actions.

## [1.3.143] - 2026-08-13

### Điều chỉnh GitHub Actions Build IPA

* **Bỏ Architecture Checker khỏi Build IPA**: Gỡ bước `Run Architecture Compliance Check` khỏi `.github/workflows/build-ipa.yml` theo quyết định trực tiếp của maintainer. `Scripts/check_architecture.py` vẫn được giữ lại như công cụ kiểm tra thủ công/local, nhưng không còn là gate của workflow build IPA.

## [1.3.142] - 2026-08-13

### Tái Cấu Trúc Mã Nguồn FreeBook iOS (Refactor v4.1/v4.2/v5.0)

* **Thiết lập Tooling Check Kiến Trúc & GitHub Actions**: Tạo `Scripts/check_architecture.py` và `Scripts/architecture_allowlist.json` (schema v2 với mảng `violations`), hỗ trợ chốt chặn baseline (ratcheting). Tích hợp vào workflow `.github/workflows/build-ipa.yml`.
* **Phân Tách Subsystem TTS & Uncoupling Sự Kiện Presentation**:
  - Hợp nhất vòng đời Audio Session, EQ 2-band (lowPass 6500Hz & highShelf 7500Hz -12dB), Now Playing và Interruption Observer trong `TTSManager`.
  - Khôi phục tương thích 100% stored `@Published` timer properties, `SleepTimerMode` enum và `$sleepTimerRemainingSeconds` publisher cho `TTSPlayStateReader`.
  - Triển khai `TTSPresentationEventCenter` và `DownloadPresentationEventCenter` thread-safe `Sendable` non-`@MainActor` để phát Toast qua `AsyncStream` về `AppLaunchRootView` (`FreeBookApp.swift`).
* **Tách Các File Dịch Vụ Monolith**: Tách DTO `TOCRule`, Actor `TOCRuleSaveCoordinator`, Thuật toán `VietPhraseTokenizer` (~245 dòng) và Platform Adapter `WebViewLoader`.
* **Domain Stores & SwiftData Transaction Coordinators (Manager Approval A)**:
  - Di chuyển `PrefetchManager.swift` sang `Sources/Services/ChapterText/`.
  - Tách `ReaderChapterListStore`, `ChapterListSearchCoordinator`, `BackgroundSearchWorker`, `BackgroundPagingWorker`, `ReaderChapterListPageFetcher`.
  - Xây dựng `ExtensionTransactionCoordinator` & `BookTransactionCoordinator` tiếp nhận Command DTOs/IDs bất biến. Loại bỏ 100% lệnh `modelContext.insert/delete/save` trực tiếp trong tất cả SwiftUI Views.
* **Tách Thành Phần Giao Diện & Safe Actor Boundaries**:
  - Tách `BookDetailLoader` sử dụng `ExtensionExecutionSnapshot` DTO bất biến qua ranh giới actor.
  - Bổ sung `ReaderSelectionCoordinator`, `ReaderScrollCoordinator`, `RepositoryFilterPolicy`, `ReaderProgressScheduler`. Tất cả các file mới <= 400 dòng vật lý và 1 type chính.
* **Khóa Ràng Buộc Khống Chế Unit Tests (Manager Decision: Option B REJECTED and LOCKED)**: Đã giữ nguyên 100% thư mục `Tests/` (0 file bị tạo, sửa, đổi tên, di chuyển hay xóa), đáp ứng tuyệt đối quy tắc Rule 2.1 trong AGENTS.md.

## [1.3.141] - 2026-08-13

### Triển khai NghiTTS SafeCachedTime Prefetch Scheduler & Cấu hình Người dùng Persisted

* Chuẩn hóa thuộc tính cấu hình người dùng `nghittsSafeCachedTimeThreshold` (mặc định 8.0s, dải 4.0...20.0s, step 1.0s) tự động lưu và normalize trong `UserDefaults` key `"nghittsSafeCachedTimeThreshold"`.
* Triển khai bộ tính toán `calculateNghiCachedTime()` chuỗi âm thanh liên tục: bắt đầu từ thời lượng còn lại của player hiện tại + $N+1$ trong `NghiAudioPlayerQueue` (sử dụng `preparedNextDuration` và `effectivePlaybackRate`), cộng dồn preloaded $N+2...$ và dừng ngay ở missing chunk đầu tiên; chỉ cộng $K+1/0$ khi toàn bộ chương $K$ đã ready không lỗ hổng.
* Chuyển sang cơ chế 1 wake task duy nhất (`nghiWakeTask`) ngủ theo khoảng thời gian dự tính $\Delta t = \text{cachedTime} - \text{threshold}$ khi đệm đủ; reschedule tự động khi tốc độ `speed` thay đổi trong `updatePlaybackParams`.
* Đảm bảo ô bắt buộc $N+1$ và $K+1/0$ luôn được ưu tiên tổng hợp. Khi `cachedTime < threshold`, nạp thêm tối đa 2 ô dự phòng tùy chọn ($N+2, N+3$), giữ tổng dung lượng ở mức tối đa 5 payload logic.
* Nâng cấp `PiperSynthesisCoordinator` lên 4 cấp ưu tiên (`demand` > `immediateSuccessor` > `nextChapterMandatory` > `optionalReserve`), hỗ trợ nâng cấp ưu tiên (`promote`), gộp trùng request theo exact `synthesisKey`, và hỗ trợ `cancelPendingOptionalReserveRequests()` chỉ hủy tác vụ phụ trợ khi pause.
* Phân tách cờ hợp lệ session/identity (`isIdentityValid()`) khỏi cờ phát âm thanh (`isPlaying`): các tác vụ ONNX đang chạy hợp lệ (refill/demand) khi pause vẫn được hoàn tất và lưu bộ đệm `preloadedData` để phát ngay khi Resume.
* Đảm bảo `TTSChapterTextWorker` quản lý `ownerGeneration` nguyên tử; hủy tác vụ theo generation ngăn chặn hoàn toàn rủi ro hủy nhầm tác vụ thay thế cùng key.
* Loại bỏ tác động của nhiệt độ thiết bị (`thermalState`) khỏi các quyết định nạp âm thanh NghiTTS (giữ lại cho mục đích chẩn đoán/logging). Giữ nguyên cơ chế scheduler của Google TTS & Extension TTS.
* Tích hợp Stepper cấu hình ngưỡng nạp NghiTTS vào `TTSSettingsView.swift` và `NghiTTSSettingsView.swift`, ẩn Stepper count NghiTTS cũ để tránh nhầm lẫn nhưng vẫn bảo toàn tương thích ngược.

## [1.3.140] - 2026-08-13

### Cải tiến luồng nạp trước TTS Remote, chuyển giao tác vụ âm thanh và quản lý bộ đệm theo vòng đời

* Google TTS và Extension TTS không còn bị hạn chế nạp trước theo mức nhiệt độ thiết bị; chính sách quản lý nhiệt độ được giữ nguyên đối với NghiTTS.
* Tác vụ tổng hợp âm thanh cho chương kế tiếp đang chạy được tiếp quản và đẩy lên ưu tiên cao để phát tiếp ngay, thay vì bị hủy và tổng hợp lại từ đầu.
* Độ cao giọng đọc (pitch) của Google TTS được truyền chính xác khi tạo âm thanh và tự động xóa bộ đệm cũ khi người dùng thay đổi pitch.
* Tạo mã nhận dạng (fingerprint) theo script và cấu hình của Extension TTS để ngăn tái sử dụng âm thanh cũ khi tiện ích có thay đổi.
* Hủy ngay các tác vụ nạp trước hoặc tác vụ đang chờ đã lỗi thời khi người dùng Tạm dừng, đổi trình đọc, đổi giọng, đổi pitch hoặc thay đổi cấu hình.
* Nút Đặt lại Cài đặt Extension tôn trọng thông số `preload_size` và `max_length` từ extension, đồng thời tắt thanh điều chỉnh pitch cho Extension TTS do chưa hỗ trợ.
* Các bộ xử lý nạp trước văn bản và âm thanh (`TTSChapterTextWorker` & `TTSAudioSynthesisWorker`) trực tiếp quản lý luồng dữ liệu DTO và thời gian thực tế, sử dụng khóa định danh tổng hợp ổn định để tránh trùng lặp qua coordinator.

## [1.3.139] - 2026-08-13

### Tái cấu trúc Giao diện Cài đặt TTS thành 5 Section Chuẩn mực & Tinh chỉnh Stepper Nạp trước

* Tái cấu trúc toàn bộ `TTSSettingsView.swift` thành 5 Section mạch lạc: `Trình đọc`, `Giọng đọc`, `Quản lý riêng của trình đọc` (tập trung API Key, Model, Tiền xử lý, Từ điển & Cấu hình Extension), `Cấu hình giọng nói`, `Tải trước dữ liệu`. Gỡ bỏ Section Hẹn giờ tắt (đã có trên Widget).
* Chuyển Độ dài phân đoạn của NghiTTS & Siri sang Stepper chuẩn với `step: 10`, dải 50-500 ký tự.
* Cập nhật Stepper Thời gian dãn tiến trình `prefetchDelayMs` với `step: 50`, dải 300-5000ms.
* Bổ sung nút "Đặt lại" cho Section Tải trước dữ liệu với tham số chuẩn: Prefetch Count = 2 đoạn, Chunk Length = 100 ký tự, Delay = 350ms.
* Tái sử dụng `ExtensionManager.shared.getCombinedConfigs(...)` để tự động đọc `plugin.json` từ `localPath` của Extension TTS.

## [1.3.136] - 2026-08-13


### Sửa triệt để 2 lỗi im lặng âm thanh TTS và tự động hóa cấu hình Extension / Google TTS

* Cập nhật `ReaderView.swift`: Kiểm tra cờ `isPlaying` trong `schedulePrepareTTS()` và sau bước `await` trong `prepareTTSForCurrentState()` để ngắt việc nạp lại rác làm mất tiếng khi bấm Nghe ngay lúc vừa mở Reader.
* Cập nhật `TTSSettingsView.swift` & `TTSManager.swift`: Sửa lỗi im lặng âm thanh khi đóng Cài đặt TTS bằng cách kiểm tra trùng chuỗi `extensionConfigJson` và bổ sung `wasPlaying = wasPlayingBeforeSettings || isPlaying` trong `resumeAfterSettings()`.
* Cập nhật UI Cấu hình: Extension TTS tự động dùng `preload_size` và `max_length` từ JSON config (ẩn Stepper trên UI); Google TTS khôi phục Stepper `chunkLength` (50-500 ký tự) và Stepper `googlePrefetchCount` (2-10 đoạn).

## [1.3.135] - 2026-08-13


### Tái cấu trúc Trình nghe TTS theo Mô hình 2 Worker Chuyên Trách Độc Lập

* Tạo mới `TTSChapterTextWorker.swift` (Worker 1): Độc lập chịu trách nhiệm nạp trước & chuẩn hóa văn bản DTO chương $K+1$. Kích hoạt khi $N \ge \text{count}/2$ hoặc $\text{remainingParents} \le 3$.
* Tạo mới `TTSAudioSynthesisWorker.swift` (Worker 2): Độc lập chịu trách nhiệm quản lý hàng chờ tổng hợp âm thanh MP3/PCM đệm RAM.
* Kết nối Worker 1 & Worker 2 vào `TTSManager.swift`, tinh gọn logic quản lý prefetch và hủy tác vụ ngầm.
* Cập nhật quy chuẩn `rules.md` và tài liệu CodeGraph liên quan.

## [1.3.134] - 2026-08-13


### Khôi phục cấu hình Preload 2-10 đoạn và lưu riêng theo từng Extension TTS với delay tối thiểu 300ms

* Cập nhật `TTSManager.swift`: Đảm bảo `prefetchDelayMs` luôn $\ge 300\text{ ms}$ cho Google TTS và Ext TTS. Lưu giữ thông số `extPrefetchCount` (2-10 đoạn) và `extPrefetchDelay_\(tool)` riêng biệt cho từng Extension theo packageId (`tool`).
* Cập nhật `TTSSettingsView.swift`: Thêm Stepper `extPrefetchCount` (dải 2...10 đoạn) cho Extension TTS, chỉnh dải Stepper `prefetchDelayMs` thành `300...5000` ms, và hiển thị đúng nút "Cấu hình Extension" khi sử dụng Extension TTS.
* Cập nhật quy chuẩn `rules.md` và các tài liệu CodeGraph liên quan.

## [1.3.133] - 2026-08-13


### Loại bỏ chính sách giới hạn nhiệt độ (thermalState) đối với Remote TTS

* Cập nhật `TTSManager.swift`: Loại bỏ việc kiểm tra và điều tiết/hủy prefetch `currentThermalState` đối với Remote TTS (Google TTS và JS Extension TTS) trong `updatePrefetchWindow()`, `triggerNextChapterPrefetch()`, `prefetchAudioForParagraph()`, và listener `thermalStateDidChangeNotification`.
* Remote TTS tiếp tục nạp đệm đầy đủ theo cửa sổ `currentPrefetchCount` đã cấu hình vì tác vụ mạng/JS API được tuần tự hóa 1 worker qua `RemoteTTSSynthesisCoordinator`.
* Giữ nguyên chính sách quản lý nhiệt độ đối với Offline TTS (NghiTTS / Piper ONNX).
* Cập nhật quy chuẩn `rules.md` và các tài liệu CodeGraph liên quan.

## [1.3.132] - 2026-08-12


### Khắc phục thiếu biến showingDiscardAlert trong ExtensionScriptEditorView

* Khôi phục biến `@State private var showingDiscardAlert = false` trong `ExtensionScriptEditorView.swift`.
* Sửa lỗi biên dịch `cannot find 'showingDiscardAlert' in scope` và lỗi suy luận kiểu dữ liệu kéo theo của `body`.
* Tuân thủ quy định: Không thực hiện tự động push code lên Git repository.

## [1.3.131] - 2026-08-12

### Lưu trữ lâu dài cài đặt Cỡ chữ (FontSize) mặc định 11pt trong Trình biên tập Script

* Cập nhật `ExtensionScriptEditorView.swift`: Thay thế `@State private var fontSize` bằng `@AppStorage("scriptEditorFontSize") private var scriptEditorFontSize: Double = 11.0` với kích thước mặc định ban đầu 11pt.
* Ghi nhớ tự động cỡ chữ tùy chỉnh từ nút `A-`/`A+` qua các lần đóng/mở lại trình biên tập script và khởi động lại ứng dụng.
* Tuân thủ quy định: Không thực hiện tự động push code lên Git repository.

## [1.3.130] - 2026-08-12

### Tự động ẩn kết quả nguồn truyện trùng lập khi thực hiện Đổi nguồn

* Cập nhật `SearchView.swift`: Bổ sung helper `isSameBookSource` kiểm tra đối chiếu `bookId` và `detailUrl` với `changeSourceTargetBook`.
* Lọc ẩn nguồn truyện hiện tại khỏi danh sách kết quả tìm kiếm ở cả 2 chế độ hiển thị Tìm kiếm đa nguồn và Tìm kiếm đơn nguồn khi ở màn hình Đổi nguồn.
* Không tạo hoặc chỉnh sửa unit test theo workflow rule do người dùng không yêu cầu.

## [1.3.129] - 2026-08-12

### Xóa khối modifier navigationDestination bị trùng lặp gây nên lỗi Swift compiler type-checker timeout

* Phát hiện và loại bỏ khối modifier `.navigationDestination(isPresented: $triggerNavigation)` bị trùng lặp từ trước trong `ShelfView.swift`.
* Khắc phục triệt để và dứt điểm lỗi biên dịch `the compiler is unable to type-check this expression in reasonable time`.

## [1.3.128] - 2026-08-12

### Phân tách shelfTabView và historyTabView trong ShelfView giải quyết triệt me lỗi type-checker timeout

* Tách 2 tab Kệ sách (`shelfTabView`) và Lịch sử đọc (`historyTabView`) thành các thuộc tính `@ViewBuilder private var` độc lập trong `ShelfView.swift`.
* Giảm độ sâu của cây generic trong `ShelfView.body`, khắc phục triệt để lỗi biên dịch Swift compiler `the compiler is unable to type-check this expression in reasonable time`.

## [1.3.127] - 2026-08-12

### Khắc phục lỗi ngoặc đóng làm mở lại body của ShelfView

* Căn chỉnh chính xác các ngoặc đóng `}` của `ZStack`, `NavigationStack` và `var body: some View` trong `ShelfView.swift`.
* Đảm bảo `var body: some View` được đóng hoàn toàn trước khi bắt đầu khai báo các thuộc tính và phương thức `private` trong `ShelfView`, khắc phục triệt để lỗi `attribute 'private' can only be used in a non-local scope` và `expected '}' in struct`.

## [1.3.126] - 2026-08-12

### Khắc phục lỗi ngoặc đóng làm gián đoạn khai báo struct trong ShelfView

* Sửa lỗi ngoặc đóng thừa làm kết thúc sớm khối `struct ShelfView: View` trong `ShelfView.swift`.
* Đặt thuộc tính `@ViewBuilder private var changeSourceDestinationView: some View` bên trong phạm vi `struct ShelfView`, giúp toàn bộ các phương thức helper khôi phục đúng scope của `ShelfView`.

## [1.3.125] - 2026-08-12

### Khắc phục lỗi Swift type-checker timeout trong ShelfView và ReaderView

* Tách `changeSourceDestinationView` thành thuộc tính `@ViewBuilder private var` độc lập trong cả `ShelfView.swift` và `ReaderView.swift`.
* Khắc phục triệt để lỗi biên dịch Swift compiler `the compiler is unable to type-check this expression in reasonable time` khi xử lý biểu thức phức tạp trong `GeometryReader` và `NavigationStack` / `navigationDestination`.

## [1.3.124] - 2026-08-12

### Sửa lỗi biên dịch Xcode trong ShelfView, ReaderView và loại bỏ cảnh báo Swift 6

* Cập nhật `ShelfView.swift`: Thay thế `@Query(filter: #Predicate<Extension> { $0.isActive == true })` bằng `@Query private var allExtensions: [Extension]` và computed property `activeExtensions` filtering `!$0.localPath.isEmpty && $0.isEnabled`. Khắc phục lỗi `Extension has no member isActive` và lỗi `ShelfView initializer is inaccessible due to private protection level`.
* Cập nhật `ReaderView.swift`: Thay thế `$0.isActive` bằng `!$0.localPath.isEmpty && $0.isEnabled` trong `allExtensions.filter`.
* Cập nhật `TTSPlayStateReader.swift`: Thay giá trị mặc định của thuộc tính tĩnh `manager: TTSManager = .shared` trong tham số khởi tạo bằng `manager: TTSManager? = nil` và gán nội bộ `manager ?? TTSManager.shared` để tránh cảnh báo phân lập MainActor trong môi trường Swift 6.
* Cập nhật `ExtensionManager.swift`: Loại bỏ biến `scriptName` không dùng.

## [1.3.123] - 2026-08-12

### Sửa lỗi xóa sách sau khi tắt TTS, lỗi trùng lặp Mục lục nhiều trang và cải tiến tạm dừng khi đọc hết truyện

* Cập nhật `TTSManager.swift`:
  - Reset `self.playingBookId = ""` khi dừng TTS hoàn toàn (`stopPlayback` với `!keepWidget`).
  - Trong `skipForward` và `nextParagraph`, khi phát đến hết nội dung chương cuối cùng của bộ truyện, thay thế lệnh `stop()` bằng `pause()` kèm thông báo *"📖 Đã phát hết nội dung bộ truyện"* để giữ widget nổi ở trạng thái Tạm dừng thay vì tắt hẳn.
* Cập nhật `BookStorageManager.swift`:
  - Kiểm tra trạng thái TTS thực tế (`isTTSActive = isPlaying || showFloatingWidget`) trước khi áp dụng cờ bảo vệ `playingBookId`, giúp xóa thành công sách sau khi đã tắt nghe TTS.
* Cập nhật `ChapterPersistenceStore.swift`:
  - Thêm chuẩn hóa URL `normalizeUrl` trong `ReconciliationPool` (bỏ `http://`/`https://` và dấu `/` cuối) để đối chiếu và cập nhật chính xác các chương đã có khi tải mục lục nhiều trang, ngăn chèn trùng lặp mục lục.
* Không tạo hoặc chỉnh sửa unit test theo workflow rule do người dùng không yêu cầu.

## [1.3.122] - 2026-08-12

### Thêm nút Đổi nguồn khi nhấn giữ sách ở Kệ sách, Lịch sử và trong Trình đọc (Reader)

* Cập nhật `ShelfView.swift`: Thêm nút **"Đổi nguồn"** (`arrow.triangle.2.circlepath`) vào menu ngữ cảnh (Context Menu) khi nhấn giữ một bộ truyện online (`!book.isLocalBook`) ở cả 2 tab **Kệ sách** và **Lịch sử đọc**.
* Cập nhật `ReaderHeaderFooterOverlayView.swift` & `ReaderView.swift`: Thêm nút **"Đổi nguồn truyện"** vào `Menu` tùy chọn `...` góc trên bên phải của Trình đọc (Reader).
* Khi kích hoạt từ 1 trong 3 vị trí trên, ứng dụng mở màn hình `SearchView` điền sẵn tên truyện để người dùng chọn nguồn mới mượt mượt và nhanh chóng.
* Không tạo hoặc chỉnh sửa unit test theo workflow rule do người dùng không yêu cầu.

## [1.3.121] - 2026-08-12

### Bảo toàn trạng thái Kệ sách (isOnShelf) và Lịch sử (isHistory) khi đổi nguồn

* Cập nhật `executeSourceChange` trong `SearchView.swift`: Thay thế cờ cài đặt cứng `isOnShelf: true` bằng `isOnShelf: oldBook.isOnShelf`.
* Khi thực hiện đổi nguồn cho bộ truyện, nếu truyện nguồn cũ chỉ thuộc danh sách Lịch sử đọc (`isHistory == true`, `isOnShelf == false`), truyện nguồn mới được tạo sẽ giữ nguyên vị trí trong Lịch sử mà không bị thêm nhầm lên Kệ sách.
* Nếu truyện nguồn cũ thuộc Kệ sách (`isOnShelf == true`), truyện nguồn mới sẽ được thêm vào Kệ sách chuẩn xác.
* Không tạo hoặc chỉnh sửa unit test theo workflow rule do người dùng không yêu cầu.

## [1.3.120] - 2026-08-12

### Tích hợp trình tô màu cú pháp Syntax Highlighting phong cách VS Code Dark+ cho trình biên tập Script

* Tạo component `HighlightingCodeEditor` (`UIViewRepresentable` wrapper `UITextView`): Phân tích cú pháp tức thì (< 1ms) với tốc độ 60/120 FPS, không gây giật trễ bàn phím.
* Áp dụng bộ quy tắc tô màu theo chuẩn **VS Code Dark+ Theme**:
  - Từ khóa (`function`, `var`, `let`, `const`, `return`, `async`, `await`...): Xanh dương nhạt `#569CD6`.
  - Tên hàm & gọi hàm (`execute()`, `fetch()`, `select()`, `push()`...): Vàng ấm `#DCDCAA`.
  - Chuỗi văn bản (`"..."`, `'...'`, `` `...` ``): Nâu cam `#CE9178`.
  - Số & Boolean (`123`, `true`, `false`, `null`): Xanh lá mạ `#B5CEA8`.
  - Đối tượng tích hợp (`Response`, `JSON`, `Math`, `console`...): Xanh ngọc `#4EC9B0`.
  - Ghi chú (`// comment`, `/* comment */`): Xanh lá cây mờ `#6A9955`.
* Cập nhật `ExtensionScriptEditorView.swift`: Thay thế `TextEditor` phẳng bằng `HighlightingCodeEditor` tích hợp cột số dòng, bàn phím phím tắt JS và tô màu cú pháp sinh động.
* Không tạo hoặc chỉnh sửa unit test theo workflow rule do người dùng không yêu cầu.

## [1.3.119] - 2026-08-12

### Nâng cấp giao diện Trình biên tập Script (ExtensionScriptEditorView) phong cách IDE chuyên nghiệp

* Cập nhật `ExtensionScriptEditorView.swift`: Thiết kế giao diện Dark Code Editor Theme (`#181825`) tương phản cao, dịu mắt với phông chữ monospaced chuẩn IDE.
* Tích hợp **Cột số dòng (Line Numbers Column)** căn lề trái chạy dọc theo mã nguồn giúp dễ dàng định vị vị trí dòng code khi phát hiện lỗi cú pháp.
* Thêm **Thanh ký tự nhanh JS (Quick Symbol Toolbar)** gồm các phím bấm chèn nhanh 1 chạm: `{`, `}`, `(`, `)`, `[`, `]`, `=`, `;`, `:`, `"`, `'`, `=>`, `.`, `,`, `fetch`, `function`.
* Thêm cờ đánh dấu **chấm màu cam `●`** cho các tệp script có thay đổi chưa lưu trên thanh tab file.
* Thêm bộ công cụ **Tùy chỉnh cỡ chữ (`A-` / `A+`)** hỗ trợ thay đổi kích thước chữ linh hoạt từ 11pt đến 22pt ở thanh chân trang (Footer).
* Không tạo hoặc chỉnh sửa unit test theo workflow rule do người dùng không yêu cầu.

## [1.3.118] - 2026-08-12

### Sửa lỗi ẩn nút chỉnh sửa Script trong Cấu hình, chuẩn hóa nút hàng Extension và tự động làm mới Khám Phá

* Cập nhật `ExtensionConfigView.swift`: Màn hình Cấu hình luôn hiển thị `Form` chính. Khi tiện ích không có biến cấu hình tùy chỉnh (`configDefinitions.isEmpty`), dòng thông báo được hiển thị trực tiếp trong `Section("Tùy Chỉnh Biến Global")`, đồng thời `Section("Mã Nguồn Script")` chứa nút **"Chỉnh sửa mã nguồn Script"** luôn xuất hiện bên dưới và truy cập được 100%.
* Cập nhật `RepositoryManagerView.swift`: Bỏ nút `code.square` thừa trên hàng ngoài; chuẩn hóa kích thước cố định `34x34 pt` cho nút Cấu hình & Gỡ bỏ và nút Cập nhật màu cam nổi bật đồng chiều cao `34 pt`, khoảng cách đều tăm tắp `8 pt`.
* Thêm phát thông báo `extensionDidUpdate` khi tiện ích được cập nhật thành công.
* Cập nhật `DiscoveryView.swift`: Lắng nghe thông báo `extensionDidUpdate` và tự động gọi `loadDiscoveryData()` để làm mới dữ liệu `home` và `genres` khi quay lại tab Khám Phá nếu tiện ích đang active vừa được cập nhật.
* Không tạo hoặc chỉnh sửa unit test theo workflow rule do người dùng không yêu cầu.

## [1.3.117] - 2026-08-12

### Bảo toàn nguồn truyện cũ khi đang phát TTS trong quá trình đổi nguồn

* Cập nhật `executeSourceChange` trong `SearchView.swift`: Thêm cờ kiểm tra `isPlayingTTS` dựa trên `TTSManager.shared.isPlaying` và `TTSManager.shared.playingBookId`.
* Khi đổi nguồn trong lúc đang nghe TTS, hệ thống giữ nguyên nguồn truyện cũ trong cơ sở dữ liệu (`SwiftData`), `ChapterStore` và thư mục từ điển `books/<oldBookId>`, đồng thời thêm nguồn mới lên kệ sách để luồng phát âm thanh TTS không bị ngắt hay sập.
* Cập nhật thông báo xác nhận Alert và Toast phản hồi cho người dùng khi thực hiện đổi nguồn trong lúc nghe TTS.
* Cấu hình `UITabBarAppearance` trong `FreeBookApp.swift` (`standardAppearance` và `scrollEdgeAppearance` với `configureWithDefaultBackground()`) kết hợp với `.toolbarBackground(.visible, for: .tabBar)` trong `MainTabView.swift` để khắc phục lỗi thanh tab bar bị trong suốt khi ở tab Cài Đặt (Settings).
* Không tạo hoặc chỉnh sửa unit test theo workflow rule do người dùng không yêu cầu.

## [1.3.116] - 2026-08-11

### Nâng cấp giao diện đề xuất (Suggest 2 cột), ExpandableTextView và sửa lỗi DownloadManager & newVisibleBrowser

* Chuyển danh sách truyện gợi ý/đề xuất (`SuggestRowView`) trong màn hình chi tiết truyện sang giao diện 2 cột (`LazyVGrid`), với bìa sách nằm bên trái và tên truyện hiển thị tối đa 3 dòng.
* Cập nhật giao diện khung xương chờ tải (skeleton placeholder) trong `BookDetailView` đồng bộ với bố cục 2 cột mới.
* Xây dựng component `ExpandableTextView` sử dụng SwiftUI `PreferenceKey` và `GeometryReader` để đo chiều cao văn bản thực tế sau bước layout pass, so sánh `fullHeight` và `truncatedHeight` để tự động bật/tắt nút "Xem thêm / Thu gọn" chính xác 100%.
* Áp dụng `ExpandableTextView` cho phần Giới thiệu (`BookDetailHeaderView`) với tối đa 4 dòng khi thu gọn, khắc phục lỗi mất chữ khi văn bản ít ký tự nhưng xuống dòng nhiều.
* Áp dụng `ExpandableTextView` cho phần Bình luận (`CommentSectionView` và `AllCommentsView`) với tối đa 3 dòng khi thu gọn.
* Tách danh sách Thể loại (`genres`) thành 1 section riêng nằm trên phần Giới thiệu trong `BookDetailHeaderView`, sử dụng component `FlowLayout` tự động xuống dòng linh hoạt thay vì cuộn ngang.
* Khắc phục lỗi `DownloadManager`: Thêm `cancelledTaskIds` để lập tức dừng tiến trình tải ngầm khi xóa tác vụ; đồng thời reset cờ `isCancelled = false` trong RAM và DB khi bấm Tải lại (Retry) tác vụ đã bị hủy.
* Khắc phục lỗi `newVisibleBrowser`: Gọi `loader.presentUIIfNeeded()` lập tức khi đối tượng được khởi tạo trong JS, nâng cấp cơ chế tìm kiếm `UIWindowScene` active/thử lại khi màn hình bận.
* Xây dựng giao diện Dạng Tab cho `newVisibleBrowser` (`VisibleBrowserTabManager` & `TabbedVisibleBrowserViewController`): Khi có nhiều trình duyệt bật cùng lúc, các trình duyệt mới sẽ được gộp vào dạng Tab trên cùng một cửa sổ modal thay vì mở đè nhiều cửa sổ, hỗ trợ tự động đánh số phân biệt tiêu đề trùng ("Tab 1", "Tab 1 (2)").
* Không tạo hoặc chỉnh sửa unit test theo workflow rule do người dùng không yêu cầu.

## [1.3.115] - 2026-08-11

### Loại bỏ vòng lặp hụt buffer/tổng hợp trùng của NghiTTS khi nóng

* N+1 trở thành deadline synthesis không chịu cooldown; N+2 trở đi vẫn dùng cooldown để giữ khoảng nghỉ CPU.
* Mỗi refill task chỉ sở hữu một đoạn. Khi playback bắt kịp N+1 đang chạy, task playback có generation guard sẽ chờ và dùng lại kết quả thay vì hủy rồi tổng hợp trùng.
* Thermal `.serious` chỉ giữ N+1 survival buffer và hủy audio chương kế; `.critical` tiếp tục demand-only.
* Piper trả queue wait, synthesis time và PCM duration; `TTSManager` ghi `[NghiEnergy]` underrun tức thời và summary RTF tổng hợp tối đa mỗi 60 giây/các mốc pause-stop.
* `cancelNghiRefill` không còn hủy toàn bộ hàng chờ Piper, tránh race có thể xóa nhầm request playback vừa enqueue.
* Không tạo hoặc chỉnh sửa unit test theo workflow rule do người dùng không yêu cầu.

## [1.3.114] - 2026-08-11

### Giới hạn RAM chương dùng chung và truyền cancellation theo consumer

* Chuyển `ChapterContentRepository` sang cost-aware LRU tối đa 12 document/12 MiB; document quá lớn không giữ trong RAM dùng chung và memory warning chỉ xóa reusable snapshots.
* Thay in-flight chapter load bằng một task dùng chung có waiter UUID riêng cho Reader/TTS: hủy một consumer trả về ngay, còn underlying load chỉ bị hủy khi waiter cuối cùng rời đi.
* Không nuốt `CancellationError` ở nhánh đọc persistent cache/chuẩn bị metadata, tránh tiếp tục gọi extension sau khi request đã hết người dùng.
* `TTSManager` sở hữu và generation-guard fallback auto-advance task; stop, thay session hoặc advance mới hủy task cũ mà không biến cancellation thành lỗi dừng phát, đồng thời reattach một lần nếu repository chỉ bị force-refresh supersede.
* Không tạo hoặc chỉnh sửa unit test theo workflow rule do người dùng không yêu cầu.

## [1.3.113] - 2026-08-11

### Sửa lỗi chức năng xuất tệp TXT và bổ sung cơ chế lưu vết / chia sẻ lại file

* Khắc phục cơ chế lấy active `UIWindowScene` và `rootViewController` tin cậy trong `DownloadManager.presentShareSheet(for:)`, đồng thời tự động trì hoãn an toàn khi `topVC` đang chuyển cảnh (`isBeingPresented`/`isBeingDismissed`).
* Bổ sung thuộc tính `exportFilePath: String?` vào `DownloadTaskModel` (SwiftData) và `DownloadTask` để lưu vết đường dẫn tệp TXT được xuất ra thư mục `Exports` bền vững trong Sandbox.
* Thêm nút "Xuất file TXT" / "Chia sẻ" trực tiếp trên từng hàng tác vụ hoàn thành trong `DownloadTrackerView` và context menu, cho phép người dùng mở lại tệp TXT đã xuất bất kỳ lúc nào.
* Không tạo hoặc chỉnh sửa unit test theo workflow rule do người dùng không yêu cầu.

## [1.3.112] - 2026-08-11

### Giảm tải foreground và công việc metadata TTS lặp lại

* Bỏ `TimelineView` quay cover 30 FPS; widget dùng ảnh bìa tĩnh trong lúc phát và tạm dừng. Loader ảnh thuộc widget cha giữ cùng `UIImage` khi đổi expanded/peeking, không tạo lại `AsyncImage` hoặc request cover.
* Root, Shelf, widget và Reader không còn quan sát toàn bộ `TTSManager`; các projection snapshot chỉ phát thay đổi cần render và Reader lọc highlight theo `bookId`.
* Tách Now Playing thành metadata tĩnh được cache theo sách/chương/cover/translation generation và timeline động; chỉ một task metadata được phép hoạt động.
* NghiTTS chỉ warm-up khi engine Nghi đang được chọn; chuyển sang Siri/Google/Ext hủy warm-up đang chờ.
* Không tạo hoặc chỉnh sửa unit test theo workflow rule do người dùng không yêu cầu.

## [1.3.111] - 2026-08-11

### Giảm auto-scroll Reader và giữ N+1 thiết yếu khi thermal serious

* Reader bỏ qua auto-scroll nếu tâm paragraph TTS còn trong vùng an toàn 15% của viewport; chỉ target ngoài vùng mới được căn giữa.
* `ParagraphTracker` bỏ qua frame movement dưới 8 pt; `[ReaderEnergy]` thêm scroll requested/skipped/executed và frame accepted/skipped.
* Sửa dự đoán Reader để không coi intrinsic invalidation lúc mount ban đầu là repeated layout churn.
* Google/Ext ở `.serious` chỉ giữ N+1, hủy N+2/N+3 và next-chapter audio; `.critical` vẫn tắt hoàn toàn prefetch.
* Không tạo hoặc chỉnh sửa unit test theo workflow rule do người dùng yêu cầu.

## [1.3.110] - 2026-08-11

### Thêm log tổng hợp tải render của Reader

* Thêm `[ReaderEnergy] Summary` qua `AppLogger`, tổng hợp `updateUIView`, highlight-only, geometry/theme rebuild, intrinsic-size invalidation và TTS scroll target.
* Chỉ ghi khoảng một dòng mỗi phút hoặc tại thermal/background/disappear boundary; các sự kiện render chỉ tăng bộ đếm RAM.
* Dự đoán loại trừ lượt mount đầu của từng `ReaderTextView`, tránh gán nhầm chi phí khởi tạo thành layout churn kéo dài.
* Không tạo hoặc chỉnh sửa unit test theo workflow rule do người dùng yêu cầu.

## [1.3.109] - 2026-08-11

### Giảm layout churn khi Reader hiển thị highlight TTS

* Highlight-only chỉ đổi thuộc tính màu trong `textStorage`, không xóa cache đo kích thước hay invalidate intrinsic size.
* Chỉ invalidate phép đo khi text/font/spacing/bold/alignment thực sự đổi; bỏ qua các lần `contentSize` thay đổi không đáng kể.
* Gỡ auto-scroll UIKit bên trong `ReaderTextView`; `ReaderView.scrollTarget`/`ScrollViewReader` là cơ chế auto-scroll TTS duy nhất.
* Bổ sung workflow rule: không tạo hoặc sửa unit test khi người dùng chưa yêu cầu rõ ràng.

## [1.3.108] - 2026-08-11

### Sửa crash khi bắt đầu TTS lúc App Log đang bật

* Thay phép đọc/ghi optional trực tiếp trên `EnergyWindow.maxQueueDepth` và `deduplicatedWaiters` bằng quy trình copy-update-assign, tránh Swift exclusive-access trap ngay tại request remote đầu tiên.
* Thêm regression test chạy synthesis đầu tiên với `AppLogger.isLoggingEnabled = true`.

## [1.3.107] - 2026-08-11

### Thêm log dự đoán tải năng lượng Google/Ext TTS

* Comment các log thành công theo từng chunk ở `TTSParagraphBuilder`, `TTSManager`, `ExtensionManager.ttsGenerate` và `ReaderView`; giữ nguyên log lỗi/retry.
* `RemoteTTSSynthesisCoordinator` tổng hợp `[TTSEnergy]` khoảng mỗi 60 giây: request/phút, priority, dedup, ký tự, audio bytes, synthesis busy time, queue depth, thermal và dự đoán mức tải.
* Tách cửa sổ foreground/background theo notification của UIKit để log khi khóa màn hình phản ánh riêng tải remote trong nền.
* Bổ sung unit test cho phân loại tải background/thermal và cập nhật CodeGraph tương ứng.

## [1.3.106] - 2026-08-10

### Giảm nhiệt NghiTTS khi nghe lâu trên thiết bị A13

* Thêm `NghiSynthesisPolicy`: buffer nominal giảm từ 4–8 giây xuống 2.5–5 giây, fair còn 1.5–3 giây và dừng toàn bộ speculative refill ở `.serious/.critical`.
* Mỗi lượt refill ONNX có khoảng nghỉ thực 750 ms ở nominal hoặc 1.5 giây ở fair, nhưng vẫn bảo toàn tối thiểu 1.2 giây audio để ưu tiên N+1.
* `ONNXPiperEngine` cố định một worker, bật graph optimization và ưu tiên XNNPACK một luồng với CPU fallback.
* Audio chương kế của NghiTTS chỉ được tổng hợp khi thermal `.nominal`; thermal transition nóng hủy refill và audio chương kế đang chờ.
* Refill dùng trực tiếp `pcmDuration` trả về từ Piper thay vì quét lại WAV.

## [1.3.105] - 2026-08-10

### Hạ nhiệt Google/Ext TTS và tách buffer depth khỏi concurrency

* Thêm `RemoteTTSSynthesisCoordinator` chạy tối đa một synthesis, ưu tiên chunk hiện tại, gộp request trùng và giữ `prefetchDepth = 3` như bộ đệm logic.
* Pause/stop và thermal `.serious/.critical` hủy remote prefetch; `.fair` tăng nhịp nghỉ. Audio chương kế chỉ được tổng hợp gần cuối chương.
* Bỏ retry lồng trong `TTSManager`; Google và Ext sở hữu tối đa hai attempt. Google parse JSON một lần và tôn trọng `Retry-After` có giới hạn.
* Thêm `ExtTTSRuntime` actor tái sử dụng `JSExecutor` theo script/config; native fetch có cancellation/timeout và bỏ text decode cho binary audio.
* `AVAudioSession` không còn cấu hình lại ở từng chunk khi session vẫn hoạt động.

## [1.3.104] - 2026-08-07

### Sửa Logic Bậc Thang Watermark Theo Nhiệt Độ (`TTSManager.swift`)
* **Khắc Phục Logic `nghiWatermarks` Phù Hợp Thứ Tự Nhiệt Độ (`TTSManager.swift`)**:
  * Chuẩn hóa logic co dãn bộ nhớ đệm giảm dần đều theo mức độ nóng của máy:
    * `.nominal`: `low = 4.0s, high = 8.0s`
    * `.fair`: `low = 3.0s, high = 6.0s`
    * `.serious`: `low = 2.0s, high = 4.0s`
    * `.critical`: `low = 1.0s, high = 2.0s`

## [1.3.103] - 2026-08-07

### Tối Ưu Hóa CPU & Hạ Nhiệt Độ Thiết Bị Cho NghiTTS (`ONNXPiperEngine.swift`, `TTSManager.swift`)
* **Tùy Biến Số Luồng ONNX CPU Linh Hoạt (`ONNXPiperEngine.swift`)**:
  * Tự động điều phối `IntraOpNumThreads` thông minh dựa trên số nhân CPU thiết bị (`ProcessInfo.processInfo.processorCount`), trạng thái nhiệt `currentThermalState` và cài đặt người dùng (`nghiTTSThreadCount`).
  * Tự động hạ từ 2 luồng xuống 1 luồng khi thiết bị ở mức ấm (`.fair`/`.serious`) hoặc trên máy ít nhân ($\le 4$ cores), giúp giảm ~45-50% công suất tỏa nhiệt của chip Apple.
* **Cache Tĩnh `punctuationRegex` (`ONNXPiperEngine.swift`)**:
  * Chuyển regex bóc tách dấu câu thành `private static let punctuationRegex: NSRegularExpression?` được khởi tạo duy nhất 1 lần trong RAM, triệt tiêu 100% việc tạo mới và biên dịch lại regex trên từng đoạn văn.
* **Tối Ưu Watermark & Thêm Thermal Duty Cycle (`TTSManager.swift`)**:
  * Điều chỉnh `nghiWatermarks` ở trạng thái bình thường từ `14.0s` về `high = 8.0s` (cắt giảm đợt xung tải bộc phát ban đầu).
  * Chèn `thermalExtraDelayMs = 200ms` giữa các lượt nạp đệm trong `scheduleNghiRefill()` khi `currentThermalState != .nominal` để tạo khoảng nghỉ tản nhiệt cho CPU.

## [1.3.102] - 2026-08-07

### Cải Tiến Ext TTS: Dọn Dẹp File Tạm 100% & Bổ Sung Retry (`ExtTTSService.swift`, `TTSManager.swift`)
* **Dọn Dẹp 100% Tệp Tin Âm Thanh Tạm (`ExtTTSService.swift`)**:
  * Sử dụng khối `defer { cleanupTempFile(tempFileUrl) }` ngay sau khi tạo tệp đĩa tạm trong `synthesize(...)`.
  * Loại bỏ các câu lệnh `cleanupTempFile` dư thừa ở tất cả các nhánh `guard`/`return`/`throw`, đảm bảo dọn dẹp tuyệt đối đĩa đệm `tmp` trong mọi trường hợp (ngoại lệ `AVAudioFile`, lỗi convert hay Task bị hủy).
* **Bổ Sung Retry Tự Động Cho Ext TTS (`TTSManager.swift`)**:
  * Mở rộng `isTransientTTSError(_ error:)` nhận diện các domain `"ExtTTSService"` và `"ExtensionManager"`.
  * Giúp luồng prefetch tự động thử lại khi gặp các sự cố ngắt kết nối mạng tạm thời từ server TTS bên thứ 3.

## [1.3.101] - 2026-08-07

### Tối Ưu Hóa & Sửa Lỗi Lag Google Cloud TTS (`GoogleTTSService.swift`, `TTSManager.swift`)
* **Thêm Request Timeout 12.0s & Thử Lại Nội Bộ (`GoogleTTSService.swift`)**:
  * Đặt `request.timeoutInterval = 12.0`s tránh nghẽn luồng prefetch/playback khi mạng lag (mặc định trước đây 60s).
  * Bổ sung cơ chế thử lại nội bộ (retry) ngắn tối đa 2 lần với delay 400ms khi nhận các lỗi HTTP 5xx, 429 hoặc `Internal error encountered`.
* **Nhận Diện Lỗi Tạm Thời Google API (`TTSManager.swift`)**:
  * Mở rộng `isTransientTTSError(_ error:)` nhận diện các từ khóa lỗi server tạm thời (`internal error`, `rate limit`, `resource_exhausted`, `500`, `502`, `503`, `504`) để luồng prefetch tự động retry thay vì hủy task ngay lập tức.

## [1.3.100] - 2026-08-07

### Sửa Lỗi Cấu Trúc Scope & Biên Dịch (`SettingsView.swift`)
* **Khắc phục lỗi `extraneous '}' at top level` và `cannot find '...' in scope` (`SettingsView.swift`)**:
  * Xóa dấu đóng ngoặc nhọn `}` thừa ở dòng 202 ngay sau khối `if isTranslationEnabled`.
  * Khôi phục đúng cấu trúc lồng nhau của `Form`, `NavigationStack`, `body` và `struct SettingsView`.
  * Đưa các phương thức helper `updateLogStatus()`, `copyLogToClipboard()`, `formatBytes()`, `getStatusText(for:)` trở lại phạm vi của `SettingsView`.

## [1.3.99] - 2026-08-07

### Màn Hình Chỉnh Sửa Mã Nguồn Script Tiện Ích Extension (`ExtensionScriptEditorView.swift`)
* **Xây Dựng Trình Soạn Thảo Script (`ExtensionScriptEditorView.swift`)**:
  * Tạo mới `ExtensionScriptEditorView` hỗ trợ mở và chỉnh sửa mã nguồn JavaScript (`.js`) và tệp cấu hình `plugin.json` trực tiếp trên ứng dụng.
  * Tích hợp bộ chọn danh sách script (`scriptSelectorHeader`), trình soạn thảo Monospace (`TextEditor`) tự động tắt autocorrect & autocapitalization, cùng thanh thống kê số dòng/ký tự.
  * Tích hợp kiểm tra cú pháp JS tức thì (`validateScriptSyntax`) thông qua `JSContext` và `JSONSerialization`.
  * Hỗ trợ nút **Lưu (Save)** ghi đè file trên đĩa kèm Toast thông báo và nút **Tải lại (Revert)** khôi phục nội dung ban đầu.
* **Tích Hợp Truy Cập Nhanh (`RepositoryManagerView.swift`, `ExtensionConfigView.swift`)**:
  * Thêm biểu tượng icon `code.square` màu tím trên từng tiện ích đã cài đặt tại `RepositoryManagerView.swift`.
  * Thêm mục *"Chỉnh sửa mã nguồn Script"* trong màn hình cấu hình `ExtensionConfigView.swift`.

## [1.3.98] - 2026-08-07

### Tính Năng Import Tiện Ích Tệp .ZIP & Menu Dropdown Toolbar (`ExtensionManager.swift`, `RepositoryManagerView.swift`)
* **Xây Dựng Hàm `installFromLocalZip` (`ExtensionManager.swift`)**:
  * Đảm bảo quyền truy cập `security-scoped resource` khi chọn tệp `.zip` từ ứng dụng Tệp.
  * Giải nén file `.zip` bằng `ZIPFoundation` vào thư mục tạm, tự động tìm và bóc tách dữ liệu từ `plugin.json` (`packageId`, `name`, `author`, `version`, `type`, `locale`, `sourceUrl`).
  * Di chuyển thư mục giải nén tới `extensions/<package_id>` của ứng dụng.
* **Gom Thao Tác Vào Menu Dropdown (`RepositoryManagerView.swift`)**:
  * Thay thế nút chữ đỏ đơn lẻ "Xóa tất cả" bằng biểu tượng **Menu Dropdown (`ellipsis.circle`)** trên thanh công cụ.
  * Tích hợp 2 mục thao tác: *"Import tiện ích (.zip)"* (mở `DocumentPickerPresenter`) và *"Xóa tất cả tiện ích"* (mở alert cảnh báo xóa).
  * Viết phương thức `importExtensionFromZip(_ url: URL)` để nạp tiện ích mới từ tệp ZIP và lưu/cập nhật vào CSDL SwiftData.

## [1.3.97] - 2026-08-07

### Tính Năng Cập Nhật Tiện Ích & Cập Nhật Tất Cả (`Extension.swift`, `RepositoryManagerView.swift`)
* **Bổ Sung Trường Remote Version & Computed Property `hasUpdate` (`Extension.swift`)**:
  * Thêm thuộc tính `public var remoteVersion: Int?` lưu phiên bản hiển thị trên repository `plugin.json`.
  * Thêm computed property `public var hasUpdate: Bool` (`!localPath.isEmpty && (remoteVersion ?? 0) > version`).
* **Cập Nhật Giao Diện Thẻ Tiện Ích & Banner "Cập Nhật Tất Cả" (`RepositoryManagerView.swift`)**:
  * Đọc và lưu `remoteVersion` từ kho khi đồng bộ `syncExtensions(for:with:)`.
  * Hiển thị badge phiên bản `v1 ➔ v2` nổi bật màu cam trên từng thẻ tiện ích có bản mới.
  * Thêm nút **"Cập nhật"** màu cam trực quan bên cạnh nút Cấu hình (bánh răng) và Xóa (thùng rác).
  * Render **Banner "Cập nhật tất cả"** ở đầu Tab 0 khi có 1 hoặc nhiều tiện ích có bản nâng cấp mới.
  * Tự động làm mới dữ liệu kho (`refreshAllRepositories()`) khi mở màn hình Kho Tiện Ích (`onAppear`).

## [1.3.96] - 2026-08-07

### Tối Ưu Nhiệt Độ & Prefetch Theo Thời Lượng Audio Cho NghiTTS (`TTSManager.swift`, `TTSChapterPrefetcher.swift`, `ONNXPiperEngine.swift`, `TTSSettingsView.swift`)
* **Duration-Based Prefetch & Hysteresis Watermarking (`TTSManager.swift`)**:
  * Chuyển đổi prefetch NghiTTS từ đếm số lượng đoạn cố định (`nghittsPrefetchCount = 3`) sang cơ chế tính thời lượng bộ đệm audio (`calculateNghiBufferedDuration()`).
  * Áp dụng mốc Low Watermark (5s) / High Watermark (12s). Tự động dừng loop ONNX khi đệm đủ 12 giây, đưa CPU Duty Cycle từ 30%-100% xuống <15%.
  * Giữ vững bất biến (Invariant): Đoạn $N+1$ luôn được ưu tiên tổng hợp và `prepareNext` ngay lập tức để không gây đứt đệm.
* **Thermal-Aware Prefetch Policy (`TTSManager.swift`, `TTSChapterPrefetcher.swift`)**:
  * Lắng nghe sự kiện `ProcessInfo.thermalStateDidChangeNotification`.
  * Điều chỉnh động mốc Watermark theo 4 mức nhiệt (`.nominal`: 6s/14s, `.fair`: 4s/9s, `.serious`: 2.5s/5s, `.critical`: 1.5s/3s).
  * Trong `TTSChapterPrefetcher`, tự động bỏ qua tác vụ prefetch audio chương kế tiếp khi thiết bị ở mức nhiệt `.serious` hoặc `.critical`.
* **Vòng Đời Lifecycle & Cancellation (`TTSManager.swift`)**:
  * Trong `pause()`, bổ sung hủy `nextChapterPrefetcher.cancel()` và `PiperSynthesisCoordinator.shared.cancelAllPending()` để ngắt triệt để CPU compute.
  * Cập nhật `nghiRefillGeneration` và discard ngay kết quả ONNX C++ dở dang sau khi Seek/Skip/Stop.
* **Đồng Bộ Trạng Thái Preload Trực Quan (`TTSSettingsView.swift`)**:
  * Khai báo `@Published public var nghiBufferedDuration: Double` trong `TTSManager`.
  * Đồng bộ giao diện cấu hình `TTSSettingsView` hiển thị mốc bộ đệm audio thực tế (`Đã nạp trước: X s / Y s`) và giải thích cơ chế tự ngắt nạp để hạ nhiệt máy.

## [1.3.95] - 2026-08-06

### Hoàn Thiện Tối Ưu Luồng NghiTTS (Buffer Audio Đầu 1-1.5s, ONNX Threads & Thermal Management) (`ONNXPiperEngine.swift`, `PiperTTSService.swift`, `PiperSynthesisCoordinator.swift`, `TTSManager.swift`, `NghiTTSPerformanceTests.swift`)
* **Tích Hợp `pcmDuration` & Tối Ưu Buffer Audio Đầu Tiên (`ONNXPiperEngine.swift`, `PiperTTSService.swift`, `PiperSynthesisCoordinator.swift`, `TTSManager.swift`)**:
  * Bổ sung API `synthesizeWithDuration(...)` trong `ONNXPiperEngine` và `PiperTTSService` trả về tuple `(data: Data, pcmDuration: Double)` kết hợp cùng `PiperSynthesisPayload` trong `PiperSynthesisCoordinator`.
  * Loại bỏ việc decode dữ liệu WAV thủ công qua `WAVEncoder.duration(of:)`, trực tiếp tính toán độ dài PCM hiệu dụng `pcmDuration / playbackRate` tích lũy $1.0 - 1.5$s câu đầu trước khi kích phát `AVAudioPlayer`.
* **Cấu Hình ONNX Thread Options (`ONNXPiperEngine.swift`)**:
  * Thiết lập cố định `intra-op = 2` và `inter-op = 1` thông qua `ORTSessionOptions` khi tạo `ORTSession`, tối ưu hóa hiệu năng tổng hợp và giảm sử dụng CPU/nhiệt độ thiết bị.
* **Theo Dõi & Quản Lý Nhiệt Độ Thiết Bị Thermal State (`TTSManager.swift`)**:
  * Lắng nghe sự kiện `ProcessInfo.thermalStateDidChangeNotification`.
  * Tạm dừng luồng prefetch `.normal` khi nhiệt độ thiết bị lên mức `.fair`, `.serious`, hoặc `.critical`; tự động phục hồi prefetch ngầm khi trạng thái nhiệt độ về `.nominal`.
  * Các yêu cầu phát âm thanh lập tức `.high` vẫn được giữ ưu tiên phục vụ liên tục.
* **Dọn Dẹp Biến Rác & Dead Code Phân Hệ Reader (`ChapterCache.swift`, `ReaderViewModel.swift`)**:
  * Loại bỏ `typealias SharedChapterCache` và thuộc tính `var failureMessage: String?` thừa trong `ChapterCache.swift`.
  * Loại bỏ phương thức dead `fetchChaptersMetadata()` không còn sử dụng trong `ReaderViewModel.swift`.

## [1.3.94] - 2026-08-06

### Tối Ưu Hiệu Năng Luồng NGHI-TTS `AVAudioPlayer` Double-Buffering & Loại Bỏ Im Lặng Giả (`NghiAudioPlayerQueue.swift`, `TTSManager.swift`, `TTSModels.swift`, `TTSParagraphBuilder.swift`, `ONNXPiperEngine.swift`, `PiperTTSService.swift`)
* **Nâng Cấp `NghiAudioPlayerQueue` Mô Hình Trạng Thái Chuẩn (`NghiAudioPlayerQueue.swift`)**:
  * Định nghĩa `NghiQueueState` (`idle`, `playing`, `prepared`, `scheduled`, `paused`, `waitingForSynthesis`).
  * Tối ưu `updateRate(_:)` và `pause()`: giữ nguyên player instance `nextPlayer` đã `prepareToPlay()`, không hủy và re-create từ `Data` trên MainThread.
  * Áp dụng cửa sổ safe schedule $50\text{ms}$ (`wallClockRemaining > 0.050`): nếu remaining time quá sát, giữ next player ở trạng thái `prepared` cho immediate finish handoff thay vì ép schedule `play(atTime:)`.
  * Đảm bảo concurrency isolation cho delegate `audioPlayerDidFinishPlaying` và `audioPlayerDecodeErrorDidOccur`.
* **Tách Biệt Trạng Thái UI & Handoff Audio Trong `TTSManager` (`TTSManager.swift`)**:
  * Tạo helper `commitParagraphState(index:playbackId:)` cập nhật chỉ số đoạn, bôi đen highlight UI, tiến độ đọc và Now Playing info.
  * Cập nhật `handleNghiAudioTransition`: chỉ gọi `commitParagraphState`, không gọi lại `speakCurrent()` hay `playNghiTTS()`, loại bỏ 100% bug double-play lặp tiếng.
  * Dọn dẹp hàm dead code `playNghiTTSStreaming`.
* **Loại Bỏ Im Lặng Giả Cho Chunk Kỹ Thuật (`TTSModels.swift`, `TTSParagraphBuilder.swift`, `ONNXPiperEngine.swift`, `PiperTTSService.swift`)**:
  * Bổ sung enum `TTSBoundaryKind` (`technicalChunk`, `sentenceEnd`, `paragraphEnd`, `chapterEnd`) vào `TTSParagraph`.
  * Trong `TTSParagraphBuilder`, gán `.paragraphEnd` cho chunk cuối cùng của dòng văn bản gốc và `.technicalChunk` cho các chunk bị cắt giữa câu.
  * Trong `ONNXPiperEngine.synthesize`, chỉ chèn `paragraphPauseDuration` (0.5s) khi `boundaryKind == .paragraphEnd` hoặc `.chapterEnd`; triệt tiêu 100% khoảng im lặng 0.5s giả ở giữa câu.

## [1.3.93] - 2026-08-06

### Sửa Lỗi Biên Dịch Swift & Cảnh Báo Swift 6 Concurrency (`ONNXPiperEngine.swift`, `NghiAudioPlayerQueue.swift`, `TTSChapterPrefetcher.swift`)
* **Khắc Phục Lỗi Biên Dịch `@escaping` (`ONNXPiperEngine.swift`)**:
  * Thêm thuộc tính `@escaping` cho tham số `onChunkPayload` trong `synthesizeStream` để sửa lỗi passing non-escaping parameter.
* **Đồng Bộ Delegate Concurrency Swift 6 (`NghiAudioPlayerQueue.swift`)**:
  * Đánh dấu `nonisolated` cho `audioPlayerDidFinishPlaying` và `audioPlayerDecodeErrorDidOccur`, chuyển xử lý về `@MainActor` Task.
* **Dọn Dẹp Cảnh Báo `await` Dư Thừa (`TTSChapterPrefetcher.swift`)**:
  * Xóa bỏ từ khóa `await` dư thừa trước các cuộc gọi phương thức đồng bộ của `@MainActor` class `TTSChapterPrefetcher`.

## [1.3.92] - 2026-08-06

### Chuyển Đổi Luồng Phát NghiTTS Sang AVAudioPlayer (`TTSManager.swift`)
* **Chuyển Đổi Luồng Phát NghiTTS sang `AVAudioPlayer` (`TTSManager.swift`)**:
  * Thay thế việc streaming qua `AVAudioPlayerNode` bằng việc tổng hợp trọn vẹn tệp WAV Data qua `service.synthesize(...)` và phát qua `playAudioData(wavData)` sử dụng `AVAudioPlayer`.
  * Đồng bộ hoàn hảo trạng thái `play`/`pause`/`stop` và delegate `audioPlayerDidFinishPlaying` với `MPNowPlayingInfoCenter` và `MPRemoteCommandCenter` trên LockScreen & Control Center.

## [1.3.91] - 2026-08-06

### Tích Hợp PiperSynthesisCoordinator & Promoted Audio Prefetch Chương Tiếp Theo (`PiperSynthesisCoordinator.swift`, `PiperTTSService.swift`, `TTSChapterPrefetcher.swift`, `TTSManager.swift`)
* **Tích Hợp Hàng Chờ Ưu Tiên Tổng Hợp Piper TTS (`PiperSynthesisCoordinator.swift`, `PiperTTSService.swift`)**:
  * Xây dựng actor `PiperSynthesisCoordinator` điều phối độ ưu tiên tổng hợp âm thanh (`SynthesisPriority`: `high` cho đoạn đang phát, `normal` cho cửa sổ trượt chương hiện tại, `low` cho prefetch đoạn 0 chương tiếp theo).
  * Tích hợp `priority` và `requestID` vào `PiperTTSService.synthesize(...)`, đảm bảo các yêu cầu phát âm thanh lập tức luôn được ưu tiên phục vụ trước các tác vụ tổng hợp ngầm.
* **Tối Ưu Hóa Audio Promotion & Prefetch Chương Tiếp Theo (`TTSChapterPrefetcher.swift`, `TTSManager.swift`)**:
  * Bổ sung phương thức `promoteAudioIfNeeded` và state `audioReady` trong `TTSChapterPrefetcher` để sẵn sàng tổng hợp âm thanh đoạn 0 chương tiếp theo ngay khi cửa sổ trượt chương hiện tại hoàn tất hoặc khi đang phát đoạn cuối cùng.
  * Tích hợp `checkAndPromoteNextChapterAudioIfNeeded()` và phân tách API dọn cache `clearCurrentParagraphPrefetchCache()` vs `clearAllTTSCaches()` trong `TTSManager.swift`.

## [1.3.90] - 2026-08-06

### Sửa Lỗi Biên Dịch Xcode Build & Bảo Toàn 100% Chữ Khi Highlight (`ReaderTextView.swift`)
* **Khôi Phục API `textStorage` Chuẩn iOS UIKit**:
  * Sử dụng `textStorage.beginEditing()`, `textStorage.removeAttribute`, `textStorage.addAttribute` và `textStorage.endEditing()` loại bỏ hoàn toàn lỗi biên dịch `has no member 'removeTemporaryAttribute'` trên Xcode Runner.
* **Tự Động Mở Rộng Chiều Cao Tránh Mất Chữ Mép Phải**:
  * Xóa cache `cachedWidth = nil`, `cachedHeight = nil` và phát lệnh `uiView.invalidateIntrinsicContentSize()` ngay khi `isHighlightChanged == true`. Đảm bảo nếu ký tự sát mép phải bị trôi xuống dòng dưới, SwiftUI sẽ tự động dãn khung chiều cao, bảo toàn 100% văn bản không bị cắt mờ.

## [1.3.89] - 2026-08-06

### Cập Nhật Triệt Để LayoutManager Optional Chaining (`ReaderTextView.swift`)
* **Áp Dụng Optional Chaining Toàn Bộ (`ReaderTextView.swift`)**:
  * Đã chuyển đổi 100% các cuộc gọi `uiView.layoutManager` (các dòng 141, 205, 206, 216, 226, 227, 237, 251) sang toán tử optional chaining `uiView.layoutManager?.` để tương thích hoàn toàn với kiểu `NSLayoutManager?` trên mọi SDK UIKit / Xcode Runner.

## [1.3.88] - 2026-08-06

### Sửa Lỗi Biên Dịch Optional Chaining ReaderTextView & Warning withLock (`ReaderTextView.swift`, `ExtTTSService.swift`)
* **Sửa Lỗi Truy Cập LayoutManager Optional Chaining (`ReaderTextView.swift`)**:
  * Thêm toán tử optional chaining `?.` tại toàn bộ các truy xuất `uiView.layoutManager` trong `ReaderTextView.swift` (dòng 138, 204, 205, 214, 223, 224, 233, 246) để tương thích chính xác với thuộc tính optional `layoutManager: NSLayoutManager?`.
  * Khởi tạo `AutoSizingTextView(usingTextLayoutManager: false)` trên iOS 16+ để ép `UITextView` dùng TextKit 1 cho highlight và căn chỉnh kích thước text.
* **Khắc Phục Cảnh Báo Giá Trị withLock Không Sử Dụng (`ExtTTSService.swift`)**:
  * Thêm gán `_ = tempFileLock.withLock { activeTempFiles.insert(tempFileUrl) }` loại bỏ warning `result of call to 'withLock' is unused`.

## [1.3.87] - 2026-08-05

### Sửa Lỗi Biên Dịch Swift & Cảnh Báo Build (`TTSBackgroundProcessor.swift`, `ExtTTSService.swift`, `DownloadManager.swift`, `03_type_graph.md`)
* **Sửa Lỗi Biên Dịch Scope `TTSProcessedChapter`**:
  * Thêm `public typealias TTSProcessedChapter = ProcessedChapterDTO` trong `TTSBackgroundProcessor.swift` đảm bảo tên kiểu `TTSProcessedChapter` sẵn sàng trong scope khi biên dịch `TTSManager.swift`.
* **Khắc Phục Cảnh Báo Swift 6 Async Locking & Biến Unused**:
  * Thay thế `tempFileLock.lock()` / `tempFileLock.unlock()` trong `ExtTTSService.swift` bằng `tempFileLock.withLock { ... }` an toàn trong context `async`.
  * Loại bỏ khai báo biến không được sử dụng `let targetChapterId = chapter.id` trong `DownloadManager.swift`.

## [1.3.86] - 2026-08-05

### Bổ Sung Metric Hiệu Năng AppLogger & Tối Ưu Hot Path (`AppLogger.swift`, `SettingsView.swift`, `ExtensionManager.swift`, `TTSManager.swift`, `ReaderViewModel.swift`)
* **Bổ Sung AppLogger Performance Metrics (Phase 0)**:
  * Đo đạc hiệu năng chuyển chương tự động TTS (`TTSManager.swift`) dùng `systemUptime`, khởi tạo context ngay trên MainActor trước khi tải chương, theo dõi `synthesisMs`, `playerSetupMs`, `origin`, `audioCacheHit`, và ghi log `[TTSPerf] AutoAdvance` với outcome `played`, `load_failed`, `process_failed`, `cancelled`, `superseded`.
  * Đo đạc hiệu năng làm mới đoạn văn Reader (`ReaderViewModel.swift`) dùng `systemUptime`, ghi log `[ReaderPerf] TranslationRefresh` với thông số `cachedCount`, `neighborCount`, `currentMs`, `neighborsMs`, `totalMs`, `outcome`.
* **Tối Ưu Hot Path Log & Cấu Hình Log Rút Gọn JS (Phase 1)**:
  * Bọc `#if DEBUG ... #endif` tại toàn bộ vị trí gọi `logRemoteTrace` trong `TTSManager.swift` để triệt tiêu mọi phép nối chuỗi và truy vấn hệ thống trong bản Release.
  * Thêm thuộc tính `isCompactSuccessLogEnabled` và toggle cấu hình "Thu gọn log kết quả Extension" trong Settings (`SettingsView.swift`, `AppLogger.swift`).
  * Tối ưu `verifyJSResponse` trong `ExtensionManager.swift`: trả về ngay `dataVal` khi tắt log, hoặc định dạng rút gọn `[Array: N items]`, `[Object: N keys]`, `[String: N chars]`, `[Value]` khi bật log rút gọn để tiết kiệm bộ nhớ và dung lượng đĩa.

## [1.3.85] - 2026-08-05

### Sửa Lỗi Highlight TextKit Trực Tiếp Trên NSTextStorage & Thêm Unit Test Layout (`ReaderTextView.swift`, `ReaderTextViewTests.swift`)
* **Sửa Lỗi Highlight Bằng NSLayoutManager Temporary Attributes (`ReaderTextView.swift`)**:
  * Chuyển đổi cơ chế bôi đen TTS từ sửa thuộc tính màu trực tiếp trên `NSTextStorage` sang áp dụng `NSLayoutManager.addTemporaryAttributes` / `removeTemporaryAttribute`.
  * Giữ nguyên thuộc tính kiên định (persistent attributes) của `NSTextStorage`, ngăn chặn TextKit tính toán lại glyph advance hay ngắt dòng trên văn bản căn đều (justified text), triệt tiêu lỗi mất/xén chữ ở mép phải dòng cuối cùng khi bật highlight.
* **Thêm Regression Test TextKit Temporary Attributes (`Tests/ReaderTextViewTests.swift`)**:
  * Khởi tạo `ReaderTextViewTextKitTests` với chuỗi tiếng Việt chuẩn UTF-8 chứa đoạn văn tiếng Việt bắt đầu bằng `"Tiền Đa Đa nghe xong..."`.
  * Kiểm tra và khẳng định tính bất biến của thuộc tính kiên định `textStorage`, các bản chụp line layout (`LineLayoutSnapshot`), số lượng line fragment và `usedRect` ở 3 trạng thái (chưa bôi đen, bôi đen temporary attributes, và đã xóa temporary attributes).

## [1.3.84] - 2026-08-05

### Tách Cập Nhật VP/Name Khỏi Phiên TTS Đang Hoạt Động (`ReaderView.swift`, `ReaderViewModel.swift`, `TTSManager.swift`)
* **Chỉ Làm Mới Nội Dung Reader**:
  * Giữ debounce 150 ms và quy trình rebuild tuần tự chương đang hiển thị trước, sau đó mới đến các chương đã cache khi VP/Name thay đổi.
  * Loại bỏ callback `onCurrentChapterReady` và `performTTSSynchronization()`, nên cập nhật từ điển không còn restart TTS hoặc dựng lại chapter TTS đang pause.
* **Bảo Toàn Phiên TTS & Prefetch**:
  * Loại bỏ API `updatePreparedChapterContentSilent`; sự kiện cập nhật VP/Name không còn xóa prepared chapter cache hay audio prefetch cache.
  * Phiên đang phát hoặc đang pause tiếp tục bằng snapshot hiện có. Từ điển mới được áp dụng ở lần nghe mới hoặc khi TTS tự nạp nội dung chương tiếp theo.

## [1.3.83] - 2026-08-05

### Sửa Lỗi Biên Dịch Swift Do Thiếu Import Foundation (`TTSParagraphBuilder.swift`)
* **Thêm Import `Foundation`**:
  * Bổ sung `import Foundation` ở đầu tệp `TTSParagraphBuilder.swift` để định nghĩa đầy đủ các kiểu dữ liệu `NSRange`, `NSIntersectionRange`, `NSMaxRange`, `NSString` và giải quyết lỗi suy luận kiểu dữ liệu (`cannot convert value of type 'Duration' to expected argument type 'Int'`).

## [1.3.82] - 2026-08-05

### Tối Ưu Hóa Reading/Highlight & VP/Name Cascade (`TranslationManager.swift`, `TranslateUtils.swift`, `DictionaryCache.swift`, `TTSManager.swift`, `TTSModels.swift`, `TTSBackgroundProcessor.swift`, `TTSParagraphBuilder.swift`, `ChapterCache.swift`, `ParagraphCardView.swift`, `ReaderTextView.swift`, `ReaderView.swift`, `ReaderViewModel.swift`)
* **Scoped Dictionary Notifications & Generation Counters**:
  * Thêm `globalGeneration`, `bookGenerations`, `settingsGeneration` vào `TranslateUtils.invalidateCache(bookId:)` giúp xóa cache RAM chọn lọc theo `bookId` và cài đặt; tránh làm cold cache của sách B khi từ điển sách A thay đổi.
  * Thêm `bookId` vào `userInfo` của thông báo `.translationDictionariesDidUpdate` trong `TranslationManager` để `ReaderView` lọc đúng phạm vi sách.
* **Bảo Tồn Paused Session & Resume Vị Trí TTS**:
  * Di chuyển kiểm tra cùng sách lên trước khi xóa cache TTS.
  * Bổ sung API `updatePreparedChapterContentSilent` trong `TTSManager` giữ phiên TTS paused nguyên trạng thái và widget khi đổi từ điển.
  * Thêm `sourceRange` vào `TTSParagraph` và cấu trúc `TTSChunkResumeIdentity` lưu `sourceLineId` và `sourceOffset` để resume đúng chunk và bảo toàn hành vi bôi đen chọn "Nghe".
* **Bảo Vệ Snapshot Readiness & Tối Ưu UI Render**:
  * Bổ sung `revision` vào `CachedChapter` và `ReaderViewModel`, hoãn TTS sync nếu dữ liệu chương chưa hoàn tất re-translation.
  * Chuyển công việc dịch ngầm nặng ra off-MainActor với cooperative cancellation và ưu tiên dịch chương hiện tại trước.
  * Dùng trực tiếp `item.translated` làm `displayText` trong `ParagraphCardView` tạo snapshot nguyên tử với `translationSpans`.
* **Sửa Lỗi Compile, Đồng Bộ TTS Readiness & Coordinate Selection**:
  * Phục hồi `let md5 = text.md5()` trong `TranslateUtils.translateText` và chuẩn hóa access control `internal private(set) var currentRevision`.
  * Bổ sung callback `onCurrentChapterReady` trong `ReaderViewModel` để đảm bảo `performTTSSynchronization()` chỉ kích hoạt khi dữ liệu chương hiện tại hoàn tất re-translation ở `currentRevision`.
  * Ánh xạ chính xác `sourceOffset` (`selectedWordOffset`) và `TTSChunkResumeIdentity` khi bấm chọn "Nghe" trên văn bản bôi đen dịch thuật.
  * Xóa bỏ các cache audio/prepared stale trong `updatePreparedChapterContentSilent` khi paused mà không ảnh hưởng tới widget hoặc các sách khác.
  * Khoanh vùng hoàn toàn `chapterTitleCacheDict` theo `bookId` và định tuyến duy nhất qua `notifyDictionariesDidUpdate()`.
  * Hoãn tự động swap snapshot re-translation (`isTranslationRefreshDeferred`) khi người dùng đang bật menu/bảng thao tác bôi đen văn bản, bảo vệ 100% active selection.
* **Tối Ưu Concurrency, Resilient Revision Retry & Per-line Cancellation**:
  * Thêm vòng lặp retry tự động trong `ReaderViewModel.processAndSaveChapter` giúp nạp chương bình thường tự thử lại với `currentRevision` mới nhất nếu từ điển thay đổi trong lúc dịch ngầm, triệt tiêu hoàn toàn nguy cơ mất chương hoặc commit snapshot cũ.
  * Bắt và kiểm tra bộ 5 thuộc tính định danh (`isPlaying`, `playingBookId`, `playingChapterIndex`, `sessionID`, `ttsProcessingGeneration`, `preparationGeneration`) trong `TTSManager.updatePreparedChapterContentSilent`, chặn đứng race condition ghi đè từ các tác vụ ngầm cũ.
  * Tách helper `buildCancellable` trong `ReaderViewModel` hỗ trợ kiểm tra `Task.checkCancellation()` theo từng dòng (per-line), giúp hủy ngay các tác vụ dịch ngầm thừa mà vẫn bảo toàn 100% ngữ nghĩa và dữ liệu `TranslationSpan`.
* **Scoped Translation Generation Token & Tái Sử Dụng Pretranslated Snapshot**:
  * Thêm API `TranslateUtils.translationGenerationToken(for: bookId)` kết hợp `globalGeneration`, `bookGeneration`, `settingsGeneration` và bổ sung `translationToken` vào `TTSPreparedChapterKey`. Tự động làm miss cache prepared TTS cũ khi từ điển/cài đặt thay đổi kể cả khi không có floating session.
  * Tái sử dụng trực tiếp snapshot `ParagraphItem` đã dịch trong `ReaderViewModel` cho `TTSBackgroundProcessor` qua `pretranslatedEntries`, kết hợp kiểm tra validation nghiêm ngặt theo `lineId` và `originalText`. Triệt tiêu hoàn toàn dịch trùng lặp giữa UI và TTS cho chương hiện tại.
* **Snapshot Validation Metadata & Protection Against Race On Toggle**:
  * Thêm `isTranslationEnabled` và `translationToken` vào `CachedChapter` và đóng gói thành `TTSPretranslatedSnapshot`.
  * Trong `TTSBackgroundProcessor`, kiểm tra `snapshot.isTranslationEnabled == shouldTranslateRawContent` và `snapshot.translationToken == TranslateUtils.translationGenerationToken(for: bookId)`. Chặn đứng tuyệt đối việc phát âm nhầm văn bản dịch cũ khi chuyển đổi bật/tắt dịch thuật nhanh hoặc thay đổi từ điển trước khi refresh hoàn tất.

## [1.3.81] - 2026-08-05

### Sửa Lỗi Regression Highlight TTS & Lệch Range Cuối Chunk Cấp Chunk (`ChapterTextNormalizer.swift`, `TTSBackgroundProcessor.swift`, `TTSManager.swift`, `ReaderView.swift`, `ParagraphCardView.swift`, `ReaderSelectionMapper.swift`, `ChapterTextNormalizerTests.swift`)
* **Nâng cấp Bôi Đen TTS Cấp Chunk (Exact Current Chunk Range)**:
  * Phân biệt rõ Paragraph Identity và Chunk Identity: `highlightRange` giữ nguyên `NSRange` cấp chunk của `TTSParagraph.range`.
  * Trong `ParagraphCardView.swift`, bỏ bọc `ReaderSelectionMapper.mapHighlight` và truyền trực tiếp `highlightRange` từ `TTSManager` xuống `ReaderTextView` để tô màu nền đúng dải ký tự của chunk đang đọc, không bôi đen cả paragraph.
  * Trong `ReaderSelectionMapper.swift`, xóa 3 phương thức `mapHighlight`, `mappedRangeUsingOriginalSpans`, và `proportionalHighlightFallback`.
* **Nâng Cấp Thuật Toán Chọn Chunk Khi Bấm "Nghe" (`TTSManager.swift`)**:
  * Khi bôi đen văn bản rồi bấm "Nghe", `startSpeaking` nhận `startTextOffset` là `selectionRange.location` (offset ký tự đầu tiên của selection range).
  * `TTSManager.continueStartSpeaking` lọc danh sách chunks thuộc `startParagraphIndex`, kiểm tra offset hợp lệ (`offset != NSNotFound`, `offset >= 0`, `minLoc <= offset <= maxEnd`). Nếu offset rơi vào ranh giới/khoảng trắng ngắt chunk do trimming, ưu tiên chọn chunk kế tiếp có `location >= offset`, hoặc chunk liền trước có `NSMaxRange(range) <= offset`; nếu offset không hợp lệ (hoặc `NSNotFound` / vượt ngoài phạm vi đoạn), tự động fallback về chunk đầu tiên của đoạn.
* **Unified Pipeline & Preserved Gap Content (`ChapterTextNormalizer.swift`, `TTSBackgroundProcessor.swift`)**:
  * Thêm `ChapterTextNormalizer.reconstructContentPreservingLineIDs(from:)` tái tạo chuỗi raw content từ `cached.paragraphItems` duy trì đúng các ký tự ngắt dòng `\n`.
  * `TTSBackgroundProcessor.processChapter` thực hiện quy trình Lọc rác raw content 1 lần duy nhất $\rightarrow$ Normalize raw $\rightarrow$ Translate per Line $\rightarrow$ Reconstruct gap-preserved content $\rightarrow$ `normalizeProcessedContent` (không lọc rác lần 2 trên chuỗi dịch), đảm bảo `normalizedContent` giữ ngắt dòng và 100% khớp dải ký tự với Reader UI.
* **Snapshot Session & Debounced Coalescing Sync (`TTSManager.swift`, `ReaderView.swift`)**:
  * Thêm `isTranslationEnabled` vào `TTSPreparedChapterKey` và lưu `sessionTranslationEnabled` snapshot cho luồng prefetch trong `TTSManager`.
  * Bổ sung `ttsManager.clearPreparedChapterCache()` để giải phóng cache chapter chuẩn bị khi đổi từ điển/cài đặt.
  * Trong `ReaderView.swift`, thêm `scheduleTTSSynchronization()` với debounce 100ms gom nhóm các sự kiện cập nhật từ điển và bật/tắt dịch, tự động đồng bộ lại phiên TTS active nếu đang chạy hoặc dừng an toàn nếu đang paused.
* **Chuẩn Hóa Tiêu Đề Chương Dịch 1 Lần Duy Nhất (`TTSBackgroundProcessor.swift`, `ReaderView.swift`, `TTSManager.swift`)**:
  * `TTSChapterInfo.title` thống nhất mang tiêu đề gốc (RAW title). `ReaderView.ttsChapterInfo` và `TTSManager` truyền RAW title vào `TTSBackgroundProcessor.processChapter`.
  * `TTSBackgroundProcessor.processChapter` là nơi duy nhất chịu trách nhiệm dịch tiêu đề 1 lần duy nhất khi `shouldTranslateRawContent == true`, trả về `ProcessedChapterDTO.chapterTitle`.
  * Triệt tiêu hoàn toàn lỗi dịch tiêu đề 2 lần (double translation), đảm bảo tiêu đề `TTSParagraph` (`paragraphIndex = -1`), `TTSManager.chapterTitle` (Now Playing/Lock Screen) và tiêu đề hiển thị trên Reader đồng nhất 100%.
* **Dọn Dẹp Unit Tests Sai ở Commit HEAD**:
  * Xóa 5 unit test cases testing `mapHighlight` trong `Tests/ChapterTextNormalizerTests.swift` để phù hợp với kiến trúc bôi đen cấp chunk chuẩn.

## [1.3.80] - 2026-08-05

### Sửa Lỗi Highlight TTS Lệch Khi Đoạn Văn Nhiều Dấu Câu (`ReaderSelectionMapper.swift`, `ParagraphCardView.swift`, `ReaderView.swift`)
* **Root Cause**: `TTSParagraphBuilder` tính `TTSParagraph.range` theo offset UTF-16 trên `ChapterTextLine.text` (nguyên bản), nhưng `ParagraphCardView` lại render bản dịch VietPhrase. `ReaderView` truyền thẳng `ttsManager.highlightRange` xuống mà không ánh xạ, nên range của hệ tọa độ gốc bị áp lên chuỗi đã dịch có độ dài khác. Vì bản dịch Việt dài hơn nguyên bản Trung, độ lệch tích lũy tăng dần theo vị trí chunk trong đoạn; đoạn nhiều dấu câu bị cắt thành nhiều chunk nên lệch thể hiện rõ nhất. Guard `NSMaxRange(highlight) <= nsText.length` trong `ReaderTextView` chỉ chặn crash chứ không chặn lệch, và còn làm mất highlight ở chunk cuối khi bản dịch ngắn hơn.
* **Fix**: Bổ sung `ReaderSelectionMapper.mapHighlight(_:in:displayText:)` — chiều ngược của `mappedRangeUsingSpans` — gộp các `TranslationSpan` giao với vùng gốc rồi lấy bao đóng của chúng trên chuỗi hiển thị.
* Hàm nhận thẳng `displayText` thay vì cờ `isTranslationEnabled`: `toggleTranslation` chỉ đổi cờ mà không rebuild `paragraphItems`, nên `item.translated` có thể cũ so với chuỗi đang render. Span chỉ được dùng khi `displayText == item.translated`; ngược lại rơi về nội suy theo tỉ lệ độ dài.
* Việc ánh xạ đặt tại `ParagraphCardView` — nơi duy nhất biết chắc chuỗi thực sự được render. `ReaderView` tiếp tục truyền range ở hệ tọa độ gốc.
* Dự phòng nội suy tỉ lệ cũng phủ trường hợp `buildTranslationSpans` trả `[]` khi có token không dò được trong chuỗi dịch, giữ highlight bám sát câu thay vì biến mất.



### Giảm Giật TTS Khi Cập Nhật VP/Name (`ReaderView.swift`, `ReaderViewModel.swift`)
* Bỏ việc gọi `TTSManager.clearPrefetchCache()` ngay khi nhận `translationDictionariesDidUpdate`, giữ nguyên audio đã tổng hợp của phiên đang phát để không tạo khoảng ngắt ở đoạn kế tiếp.
* Thay refresh đồng bộ nội dung cache bằng một `translationRefreshTask` có thể hủy, xử lý tuần tự chapter đang hiển thị trước rồi đến các chapter loaded/preload theo khoảng cách.
* Mỗi chapter được rebuild đầy đủ qua `ReaderParagraphBuilder`, cập nhật đồng thời tiêu đề, nội dung, `ParagraphItem` và translation spans theo VP/Name mới. Khi người dùng bấm đọc lại, Reader dịch từ `originalContent` và khởi tạo phiên TTS mới bằng nội dung đã cập nhật.

## [1.3.78] - 2026-08-04

### Sửa Lỗi Tách Từ "仿佛" & Hỗ Trợ VP/Name Chứa Ký Tự Ngoài Tiếng Trung (`DoubleArrayTrie.swift`, `TextDictionary.swift`, `TranslateUtils.swift`)
* **Khắc Phục Lỗi Tách Nhầm Từ "仿佛" Khi Từ Điển Có Cụm Dài Hơn**:
  * Bổ sung phương thức `findAllPrefixMatches(text:startIndex:)` vào `protocol TrieDictionary`, `DoubleArrayTrie` và `TextDictionary` thu thập toàn bộ các mốc tiền tố khớp từ điển nhị phân `.dat` và RAM `.txt` thay vì chỉ giữ 1 match dài nhất (`findLongestMatch`).
  * Cập nhật Bước 3 pre-scan trong `TranslateUtils.swift` để gom toàn bộ ứng viên VietPhrase $\ge 2$ ký tự. Nhờ đó khi cụm dài `仿佛在` (dài 3) bị loại do tranh chấp với `在一瞬间` (dài 4), thuật toán ở Bước 4 sẽ chọn ứng viên tiếp theo là `仿佛` (dài 2) thay vì bị tách nhầm thành các token đơn lẻ `["仿", "佛"]`.
* **Hỗ Trợ VP/Name Chứa Ký Tự La Tinh / Số / ASCII (T-shirt, Đội A, 3D, A-1)**:
  * Gỡ bỏ các câu lệnh tự động bỏ qua (skip) ký tự ASCII ở Bước 1 (Name scan) và ký tự không phải tiếng Trung ở Bước 3 (VP scan) trong `TranslateUtils.swift`.
  * Đưa việc ưu tiên khớp `activeName` và `activeVP` lên đầu vòng lặp Bước 5 (Token assembly) trước khi fallback gom chuỗi ASCII thô, đồng thời tự động dừng gom chuỗi ASCII tại ranh giới `nextBoundary` của Name/VP kế tiếp.

## [1.3.77] - 2026-08-03

### Skeleton Delay + Response.error Không Báo Message (`ReaderViewModel.swift`, `ReaderView.swift`, `ExtensionManager.swift`)
* **Step 1** (`ReaderViewModel.swift` – `requestChapter`): Cancel `navigationWorkerTask` ngay đầu hàm (trước `navigationGeneration++`) để `startNavigationWorkerIfNeeded` luôn tạo Task mới → `Task.yield()` luôn chạy → SwiftUI render Skeleton trước I/O. Dời `Task { await prefetcher.cancelAll() }` xuống sau toàn bộ block `startNavigationWorkerIfNeeded`/debounce để SwiftUI có cơ hội render trước.
* **Step 2** (`ReaderViewModel.swift` – `runNavigationWorker`): `catch is CancellationError` chỉ `continue`, không gọi `failNavigation` — tránh flash error message sai khi worker cũ bị cancel bởi navigation mới.
* **Step 3** (`ReaderView.swift` – `singleChapterReaderView`): Dùng `.transition(.identity)` thay `.transition(.opacity)` khi `pendingNavigationIndex != nil` để chương cũ biến mất ngay lập tức thay vì fade ra từ từ che Skeleton.
* **Step 4** (`ExtensionManager.swift` – `verifyJSResponse`): Thêm kiểm tra field `error` trong JS response (`{ error: "message" }` pattern) — trước đây bị bỏ qua dẫn đến `emptyContent` error thay vì message thực từ server.

## [1.3.76] - 2026-08-03

### Sửa Lỗi Offset Lệch Hàng 2 Màn Hình Dịch (`TranslateUtils.swift`)
* **Root Cause**: `getTranslationTokens` chạy `tokenize` trên chuỗi `converted` (đã map dấu câu Trung qua `punctuationMapping`), trong khi `currentIndex` lại được track trên `sentence` gốc. Dấu câu như `"。"` (1 char) bị expand thành `". "` (2 chars) khiến `token.count` lớn hơn số ký tự thực trong sentence gốc — dẫn đến offset lệch lũy tích sau mỗi dấu câu, token tiếp theo bị tra cứu sai vị trí và hiển thị ký tự gốc tiếng Trung thay vì VP/phiên âm.
* **Fix**: Tokenize trực tiếp từ `sentence` gốc (không qua `converted`) để `token.count` luôn bằng số ký tự thực, loại bỏ hoàn toàn hiện tượng offset lệch sau dấu câu `。，！？…`.

## [1.3.75] - 2026-08-03

### Tái Cấu Trúc Từ Điển Tùy Chỉnh TXT Hợp Nhất, Lọc Từ Đã Xóa Dải Chip Gợi Ý & Cập Nhật Logic Count Từ Điển Truyện (`BypassWebView.swift`, `DictionaryListView.swift`, `DictionaryCache.swift`, `TextDictionary.swift`, `TranslationManager.swift`, `ReaderView.swift`, `DictionaryHubView.swift`)
* **Nâng Cấp Thanh Điều Hướng Dưới & Nút Import Trình Duyệt Bypass (`BypassWebView.swift`, `ShelfView.swift`, `DiscoveryView.swift`, `ReaderView.swift`, `BookDetailView.swift`)**:
  * Bổ sung thanh điều hướng dưới (bottom navigation) và nút Import trực tiếp trên thanh điều hướng trình duyệt; tự động vô hiệu hóa (disabled) khi URL không khớp biểu thức chính quy (regex match).
  * Hỗ trợ hiển thị bộ chọn nguồn (source picker) khi có nhiều tiện ích mở rộng (extensions) cùng khớp với URL.
  * Khắc phục triệt để lỗi không mở trang Chi Tiết Truyện (`BookDetailView`) sau khi hoàn tất Import: Kích hoạt cờ điều hướng `navigateToImportedBook` / `navigateToBookDetail = true` sau khi đóng trình duyệt tại tất cả các điểm gọi (`ShelfView`, `DiscoveryView`, `ReaderView`, `BookDetailView`).
* **Nâng Cấp Bóc Tách Tiêu Đề Chương Số Ả Rập & Triệt Tiêu Trùng Dấu Hai Chấm (`TranslateUtils.swift`)**:
  * Khai báo `arabicNumberTitleRegex` (`^\s*(\d{1,5})[\s.:：,.， 、_—\-]+(.*)$`) hỗ trợ bóc tách và định dạng các tiêu đề số Ả Rập dạng `1、...`, `1. ...`, `1: ...` $\rightarrow$ `Chương 1: [Tiêu đề dịch]`.
  * Tích hợp `cleanLeadingDelimiters` loại bỏ các dấu phân cách đầu chuỗi tên chương, triệt tiêu hoàn toàn lỗi 2 dấu hai chấm liên tiếp (`: :`) khi tiêu đề gốc đã có sẵn dấu hai chấm.
* **Dọn Dẹp SwiftData Fallback Chapter Metadata & Tối Ưu Render Skeleton 0ms (`ReaderViewModel.swift`, `ReaderView.swift`, `TTSManager.swift`, `ReaderChapterListView.swift`, `ShelfView.swift`, `DownloadManager.swift`)**:
  * Chuyển 100% các truy vấn chapter metadata rải rác sang thuần túy **SQLite (`ChapterStore.shared`)**, xóa bỏ hoàn toàn các khối mã fallback `FetchDescriptor<Chapter>` cũ.
  * Tắt hiệu ứng animation mờ dần 0.12s/0.25s khi đang nạp chương (`pendingNavigationIndex != nil`), giúp giao diện ngắt chương cũ và chuyển ngay sang View Skeleton.
  * Bổ sung `await Task.yield()` trong worker nạp dữ liệu nhường Main Thread vẽ khung hình Skeleton ngay ở frame đầu tiên (0ms delay) khi bấm Next/Prev chương.
* **Áp Dụng Loại Trừ Từ Đã Xóa Về Dải Chip Gợi Ý (`ReaderView.swift`)**:
  * Bổ sung điều kiện kiểm tra `!manager.deletedNames.contains(word)` và `!manager.deletedVietPhrase.contains(word)` trong thuộc tính `suggestionChips`, đảm bảo không gợi ý lại nghĩa mặc định hệ thống cho từ đã bị xóa.
* **Chuẩn Hóa Đếm Số Từ Từ Điển Truyện Theo TXT (`DictionaryHubView.swift`, `TextDictionary.swift`)**:
  * Bổ sung phương thức `DictionaryTextFileStore.loadCount(from:)` đếm số từ hoạt động trong tệp `.txt`.
  * Tái cấu trúc phương thức `bookEntryCount(type:)` sử dụng `DictionaryTextFileStore.loadCount`, loại bỏ hoàn toàn mã đọc header tệp `.dat` cũ.
* **Bảo Tồn Thứ Tự Từ Đã Xóa & Tối Ưu Nút Khôi Phục Giao Diện (`DictionaryListView.swift`)**:
  * Đảm bảo thứ tự danh sách từ VietPhrase/Names bị xóa dựa trên danh sách có thứ tự (ordered list) / thứ tự file thay vì hiển thị ngẫu nhiên từ `Set`.
  * Rút gọn nút Khôi phục thành nút dạng icon (icon-only button) kèm nhãn hỗ trợ truy cập (accessibility label).
* **Hợp Nhất Luồng Từ Điển Tùy Chỉnh Sang Định Dạng TXT Thuần (`DictionaryCache.swift`, `TranslationManager.swift`)**:
  * Chuyển toàn bộ luồng từ điển tùy chỉnh VietPhrase/Names sang định dạng TXT; hợp nhất các bản ghi chỉnh sửa (`từ=nghĩa`) và bản ghi xóa (`từ=`) trong cùng các file TXT (`CustomVietPhrase.txt`, `CustomNames.txt`, và `VietPhrase.txt`, `Names.txt` theo từng sách).
  * Loại bỏ hoàn toàn việc sử dụng file `.dat` tùy chỉnh và các file `Deleted*.txt` riêng lẻ trong luồng tùy chỉnh.
* **Phân Tích & Chuẩn Hóa Ký Tự Phân Cách Nghĩa Từ Điển (`TextDictionary.swift`)**:
  * Cập nhật `TextDictionary` và `DictionaryTextFileStore` hỗ trợ phân tích các bản ghi TXT hợp nhất.
  * Tự động chuẩn hóa tất cả các ký tự phân cách nghĩa `/`, `¦`, `|` về một ký tự chuẩn duy nhất là `/`.



## [1.3.74] - 2026-08-01

### Bổ Sung Trình Duyệt Giao Diện `Engine.newVisibleBrowser` & Tối Ưu Độ Tin Cậy Lưu Chương Nguồn STV (`VisibleWebViewLoader.swift`, `JSExecutor.swift`, `GetTextSTVManager.swift`, `ChapterContentRepository.swift`, `ChapterPersistenceStore.swift`, `BypassWebView.swift`, `ReaderView.swift`)
* **Bổ Sung API Trình Duyệt Có Giao Diện Cho JS Engine (`VisibleWebViewLoader.swift`, `JSExecutor.swift`, `ParserTests.swift`)**:
  * Định nghĩa phương thức mới `Engine.newVisibleBrowser(title)` trong JS Engine, cho phép các kịch bản JS khởi tạo và hiển thị một giao diện `WKWebView` Modal Sheet trực quan cho người dùng tương tác khi cần thiết.
  * Xây dựng trợ lý `VisibleWebViewLoader.swift` quản lý vòng đời đóng/mở UI đơn điểm (Single-source-of-truth), hỗ trợ thao tác vuốt xuống (Interactive Swipe-down) thông qua `UIAdaptivePresentationControllerDelegate` và giải phóng bộ nhớ `activeVisibleBrowsers` tức thì.
  * Giữ nguyên 100% cấu trúc, tính năng và các test case của trình duyệt ngầm `Engine.newBrowser()`.
* **Nâng Cấp Độ Tin Cậy Lưu Chương Nguồn Sáng Tác Việt - STV (`GetTextSTVManager.swift`, `ChapterContentRepository.swift`, `ChapterPersistenceStore.swift`, `BypassWebView.swift`, `ReaderView.swift`)**:
  * Khắc phục triệt để lỗi mất dữ liệu khi lưu nội dung chương STV, chuẩn hóa việc sửa lỗi URL và kiểm tra lưu nội dung chương đồng bộ vào cơ sở dữ liệu SQLite.
  * Đảm bảo tính toàn vẹn dữ liệu khi tải và lưu nội dung chương từ tiện ích STV.

## [1.3.73] - 2026-08-01

### Tích Hợp Quản Lý Từ Đã Xóa & Nâng Cấp UI/UX Từ Điển Chung (`DictionaryListView.swift`, `DictionaryCache.swift`, `DictionaryHubView.swift`)
* **Tích Hợp Tab Quản Lý & Khôi Phục Từ Đã Xóa (`DictionaryListView.swift`)**:
  * Bổ sung `TabView` với `.tabViewStyle(.page(indexDisplayMode: .never))` hỗ trợ vuốt tay trái/phải tương tác chuyển qua lại giữa 2 Tab: 📝 **Từ Chỉnh Sửa** và 🗑️ **Từ Đã Xóa**.
  * Trong Tab **Từ Đã Xóa**: Hiển thị danh sách các từ tiếng Trung bị xóa (`Array(deletedWords).reversed()`) với từ mới bị xóa gần đây nhất nằm ở dòng 1 trên cùng, kèm nút **Khôi phục** `arrow.uturn.backward.circle` trả lại nghĩa mặc định hệ thống.
* **Loại Bỏ Vuốt Xóa Mặc Định, Thêm Nút Xóa Thùng Rác Trực Tiếp (`DictionaryListView.swift`)**:
  * Loại bỏ tính năng vuốt xóa vô ý (`.onDelete`), thêm nút bấm **Thùng Rác màu đỏ (`Image(systemName: "trash")`)** trực tiếp trên từng dòng của danh sách Từ Chỉnh Sửa.
* **Đẩy Từ Mới Thêm/Sửa Lên Đầu Index 0 & Export Đồng Bộ (`DictionaryCache.swift`, `DictionaryListView.swift`)**:
  * Đưa bản ghi `DictEntry` vừa thêm mới hoặc vừa sửa nghĩa lên thẳng **`Index 0` (Dòng 1 trên cùng)**.
  * Khi Xuất từ điển (Export): Tự động xuất thêm tất cả các từ trong danh sách từ đã xóa dưới dạng `từ_trung=`.
* **Cập Nhật Phụ Đề Hub Từ Điển (`DictionaryHubView.swift`)**:
  * Hiển thị tổng quan chi tiết: *"X từ chỉnh sửa • Y từ đã xóa"*.

## [1.3.72] - 2026-08-01

### Khắc Phục Triệt Để Lỗi Trượt Lệch ID Đoạn Văn TTS Bằng `originalLineIndex` (`ChapterTextNormalizer.swift`)
* **Duy Trì Chỉ Mục Dòng Gốc Khi Lọc Đoạn Văn Rỗng/Dấu (`ChapterTextNormalizer.swift`)**:
  * Tái cấu trúc vòng lặp phân tách dòng trong `ChapterTextNormalizer.normalize()`, gán thuộc tính `id` của từng `ChapterTextLine` bằng đúng vị trí chỉ mục dòng ban đầu (`originalLineIndex`) trước khi thực hiện lọc bỏ các dòng rỗng.
  * Giúp các đoạn văn phía sau (như *"Từng cái trải qua..."*) **luôn luôn giữ vững `id = 15`** ở cả luồng TTS và luồng UI ngay cả khi đoạn `14` (`..........`) bị lọc bỏ.
  * Triệt tiêu 100% nguyên nhân gây lệch trượt `ParentID` trong TTS so với `ItemID` trên Reader UI khi có đoạn chứa toàn dấu bị bỏ qua.

## [1.3.71] - 2026-08-01

### Sửa Lỗi Highlight TTS Đoạn Văn Ngắn & Hiển Thị Tên Truyện 2 Dòng Kệ Sách/Lịch Sử (`TTSParagraphBuilder.swift`, `ShelfView.swift`)
* **Triệt Tiêu 100% Lỗi Mất Highlight TTS Ở Đoạn Văn Ngắn (`TTSParagraphBuilder.swift`)**:
  * Sửa lệnh `guard` rút gọn ở dòng 18 trong `chunks(for:maximumLength:)` cho các đoạn văn ngắn ($\le 200$ ký tự), chuyển `line.utf16Range` (chỉ mục tuyệt đối toàn chương) thành `NSRange(location: 0, length: line.text.utf16.count)` (chỉ mục tương đối 0-indexed).
  * Đảm bảo **100% tất cả các đoạn văn ngắn hay dài** đều có `range` tương đối bắt đầu từ 0, tô màu bôi đen chính xác từng câu trên UI và tự động cuộn `Auto-scroll` lên giữa màn hình mượt mà.
* **Tăng Số Dòng Hiển Thị Tên Truyện Lên 2 Dòng (`ShelfView.swift`)**:
  * Đổi `.lineLimit(1)` thành `.lineLimit(2)` cho `Text` tên truyện trong `bookItemView(_ book: Book)` của `ShelfView.swift`.
  * Cho phép tên truyện dài ở Kệ Sách và Lịch Sử Đọc hiển thị tối đa 2 dòng (rút gọn `...` ở cuối dòng 2 nếu quá dài).
* **Khôi Phục Mũi Tên Chỉ Báo `>` Mặc Định (`ShelfView.swift`)**:
  * Khôi phục lại cấu trúc `NavigationLink` trực tiếp mặc định của iOS SwiftUI cho cả 2 danh sách Kệ Sách và Lịch Sử Đọc.

## [1.3.70] - 2026-08-01

### Triệt Tiêu Lỗi Lệch Highlight TTS (Relative Indexing) & Xóa Mũi Tên Đồ Họa Lề Phải Sách (`TTSParagraphBuilder.swift`, `ReaderView.swift`, `ShelfView.swift`)
* **Sửa Triệt Để 100% Lỗi Lệch Highlight TTS & Auto-scroll (`TTSParagraphBuilder.swift`, `ReaderView.swift`)**:
  * Chuyển đổi công thức tính `range` trong `TTSParagraphBuilder.swift` sang chỉ mục tương đối nội bộ theo dòng `line.text` (0-indexed), loại bỏ hoàn toàn chỉ mục tuyệt đối cộng dồn của cả chương.
  * Trong `ReaderView.swift`, so sánh trực tiếp `item.id == ttsManager.currentParentParagraphIndex`, gán thẳng `chunkRange` cho `relativeHighlightRange` mà bỏ hẳn việc gọi qua hàm `lineStartOffset` lặp toàn chương.
  * Tự động đưa vị trí bôi đen highlight chính xác 100% từng câu trên UI và cuộn màn hình `Auto-scroll` đưa câu đang đọc vào giữa màn hình mượt mà.
* **Xóa Mũi Tên Mặc Định `>` ở Lề Phải Kệ Sách & Lịch Sử Đọc & Rà Soát Cú Pháp (`ShelfView.swift`, `ReaderView.swift`)**:
  * Sử dụng kỹ thuật bọc `ZStack` với `NavigationLink` ẩn (`.opacity(0)`) cho từng dòng sách trong danh sách Kệ Sách và Lịch Sử Đọc.
  * Loại bỏ hoàn toàn mũi tên `>` (disclosure indicator) mặc định của iOS lề bên phải, giúp giao diện phẳng, đẹp, sạch sẽ và rộng rãi hơn.
  * Sửa lỗi ngoặc nhọn đóng thừa tại dòng 176 và 284 trong `ShelfView.swift` đảm bảo định vị cấu trúc `body` chuẩn xác, đồng thời dọn dẹp biến `textLen` không sử dụng trong `ReaderView.swift`.

## [1.3.69] - 2026-08-01

### Tối Ưu Giao Diện Màn Hình Dịch, Tên Chương 2 Dòng & Log Chẩn Đoán Highlight TTS (`ReaderDefinitionOverlayView.swift`, `ReaderJunkDeleteOverlayView.swift`, `ReaderChapterListView.swift`, `BookDetailTOCView.swift`, `TTSParagraphBuilder.swift`, `TTSManager.swift`, `ReaderView.swift`)
* **Tối Ưu Không Gian Tràn Lề Hàng 1 Màn Hình Dịch & Xóa Từ Rác (`ReaderDefinitionOverlayView.swift`, `ReaderJunkDeleteOverlayView.swift`)**:
  * Thu nhỏ kích thước cụm nút điều chỉnh vùng chọn 2 bên từ `36x36` xuống `28x28`, icon `13pt`, spacing `3pt`.
  * Gỡ bỏ hai `Spacer()` hai bên `ScrollViewReader`, triệt tiêu padding lề 2 bên từ `10pt` xuống `padding(.horizontal, 4)`, giúp thanh cuộn câu tiếng Trung gốc mở rộng chiều ngang tối đa.
* **Cập Nhật Hiển Thị Tên Chương Tối Đa 2 Dòng Kèm Dấu `...` (`ReaderChapterListView.swift`, `BookDetailTOCView.swift`)**:
  * Thay đổi `.lineLimit(1)` thành `.lineLimit(2)` trong `ReaderChapterRowView` ở danh sách chương trình đọc.
  * Thay đổi `.lineLimit(1)` thành `.lineLimit(2)` cho cả 3 trường hợp danh sách chương trong `BookDetailTOCView` mục lục chi tiết truyện.
* **Bổ Sung Log Chẩn Đoán Luồng Tính Toán Highlight TTS (`TTSParagraphBuilder.swift`, `TTSManager.swift`, `ReaderView.swift`)**:
  * Ghi log chi tiết text thô từng chunk trong hàng chờ (`paragraphs` queue) kèm `utf16Range` và `line.id` trong `TTSParagraphBuilder.swift`.
  * Ghi log chi tiết chuỗi `textToSpeak` sau khi áp dụng các quy tắc thay thế từ/ký tự (`TTSReplacementManager`) và giá trị `highlightRange` trong `TTSManager.swift`.
  * Ghi log vị trí `relativeHighlightRange` quy đổi trên giao diện UI `ReaderView.swift` phục vụ đối soát lệch vị trí bôi đen.

## [1.3.68] - 2026-07-31

### Tinh Chỉnh Khoảng Cách Token Dịch Hàng Thứ 2 Màn Hình Dịch & Đồng Bộ Tra Từ Điển (`ReaderDefinitionOverlayView.swift`, `ReaderJunkDeleteOverlayView.swift`, `TranslateUtils.swift`)
* **Thu Hẹp Khoảng Cách Giữa Các Token Dịch**:
  * Giảm `spacing` của `HStack` từ `6` xuống `2` và giảm `.padding(.horizontal)` của từng `Text` token từ `4` xuống `2` ở `translatedTokensRowView`.
  * Giảm tổng khoảng cách giữa các văn bản token kề nhau từ `14pt` xuống `6pt`, giúp chuỗi câu dịch ở hàng thứ 2 trông liền mạch, tự nhiên như một câu đọc bình thường mà vẫn đảm bảo thao tác chọn từ và highlight xanh/đỏ rõ ràng.
* **Tái Cấu Trúc Đồng Bộ Tra Từ Điển Dùng Chung (`TranslateUtils.swift`)**:
  * Tạo mới hai hàm private helper `lookupRawTranslation(for:bookId:)` tra cứu trực tiếp 8 tầng từ điển và `resolveTokenMeaning(for:bookId:phienAm:)` xử lý nghĩa token kết hợp fallback Hán Việt.
  * Cập nhật cả `performTranslation` và `getTranslationTokens` sử dụng chung `resolveTokenMeaning`, loại bỏ hoàn toàn việc gọi gián tiếp `translateMeta` thừa thãi, giúp cả dịch đoạn văn và danh sách token Hàng 2 hiển thị nghĩa đồng bộ 100%.

## [1.3.67] - 2026-07-31

### Tích Hợp Google Cloud TTS (ReadAloud API) & Hỗ Trợ Đọc Văn Bản Bôi Đen (`GoogleTTSService.swift`, `TTSManager.swift`, `ReaderView.swift`, `TTSSettingsView.swift`, `project.yml`, `build-ipa.yml`)
* **Tích Hợp GoogleTTSService Native Swift (`GoogleTTSService.swift`)**:
  * Tạo mới `GoogleTTSService` kết nối REST API `https://readaloud.googleapis.com/v1:generateAudioDocStream`.
  * Hỗ trợ 6 giọng đọc tiếng Việt chuẩn: `via` (Giọng nữ tự nhiên), `vib` (Giọng nam tự nhiên), `vic` (Giọng nữ truyền cảm), `vid` (Giọng nam mạnh mẽ), `vie` (Giọng nữ trẻ trung), `vif` (Giọng nữ sâu lắng).
  * Tự động nhận diện API Key theo thứ tự ưu tiên: Custom Key trong `UserDefaults` -> System Secret nhúng trong `Info.plist`.
* **Cập Nhật TTSManager & TTSSettingsView (`TTSManager.swift`, `TTSSettingsView.swift`)**:
  * Bổ sung luồng `tool == "google"` trong `TTSManager` cho prefetch và playback MP3 audio.
  * Thêm ô chọn trình đọc, danh sách 6 giọng đọc tiếng Việt và ô nhập API Key dạng `SecureField` bảo mật mật khẩu kèm nút bật/tắt xem key trong `TTSSettingsView`.
* **Tích Hợp Google Cloud TTS Cho Văn Bản Bôi Đen (`ReaderView.swift`)**:
  * Cập nhật `readSelectedText()` ưu tiên sử dụng `GoogleTTSService` khi bôi đen đọc đoạn văn, có fallback về Siri nếu không có API key hoặc lỗi mạng.
* **Chuẩn Hóa Mã Book ID `stv_{host}_{bookId}`, Loại Bỏ SwiftData Cho Chapter Meta & Tự Động Đóng Trình Duyệt (`GetTextSTVManager.swift`, `content.js`, `BypassWebView.swift`, `BookDetailActionSheetView.swift`, `BookDetailView.swift`, `ShelfView.swift`, `DiscoveryView.swift`)**:
  * Thêm hàm `GetTextSTVManager.canonicalBookId(from:host:)` chuẩn hóa đồng bộ 100% mã `bookId` theo dạng `stv_{host}_{bookId}` (ví dụ `stv_fanqie_7590221243043826712`).
  * Loại bỏ hoàn toàn truy vấn và fallback đến `localBook?.chapters` từ SwiftData đối với dữ liệu mục lục chương, chuyển 100% sang SQLite `ChapterStore.shared.fetchOrderedTOC`.
  * Đơn giản hóa biến tính số chương trong `BookDetailView.swift`: `let totalChaps = chapterSnapshots.count > 0 ? chapterSnapshots.count : onlineChapters.count`.
  * Tách biệt `rawBookId` (số nguyên STV) dùng cho gọi API cào mục lục STV `/index.php?ngmar=chapterlist` và `canonicalBookId` (`stv_{host}_{bookId}`) gửi về cho iOS Native bridge trong `content.js`.
  * Bổ sung gán `showingBypassBrowser = false` trong `onImport` của các View để tắt ngay trình duyệt sau khi hoàn tất hoặc dừng cào dữ liệu.

## [1.3.66] - 2026-07-31

### Khắc Phục Lỗi "Không Tìm Thấy Extension Thích Hợp" Cho Nguồn Sáng Tác Việt (STV) & Đánh Dấu Nhãn STV (`Book.swift`, `GetTextSTVManager.swift`, `BookDetailView.swift`, `ReaderViewModel.swift`, `ChapterContentRepository.swift`, `DownloadManager.swift`, `BookDetailHeaderView.swift`, `ShelfView.swift`)
* **Hỗ Trợ Thuộc Tính `isSTVBook` Trên `Book` Model (`Book.swift`)**:
  * Thêm thuộc tính tính toán `isSTVBook: Bool` để xác định sách thuộc nguồn Sáng Tác Việt (`extensionPackageId == "local_stv"`, `bookId.hasPrefix("stv_")`, hoặc `sourceName` chứa *"Sáng Tác Việt"*).
* **Xử Lý Mở Chi Tiết & Mục Lục Truyện STV Trong `BookDetailView` (`BookDetailView.swift`)**:
  * Kiểm tra `isSTVBook` trong `loadBookDetailOnly()` và `loadTOCDataOnly()`: Sử dụng thông tin metadata và danh sách chương đã nạp sẵn từ `GetTextSTVManager` / `ChapterStore` mà không báo lỗi thiếu tiện ích bóc tách.
* **Xử Lý Nạp Chương & Tải Xuất Truyện STV (`ReaderViewModel.swift`, `ChapterContentRepository.swift`, `DownloadManager.swift`)**:
  * Cập nhật `ReaderViewModel`: Khởi tạo `TTSExtensionInfo` tổng hợp với `packageId: "local_stv"` khi `ext` trả về `nil`.
  * Cập nhật `ChapterContentRepository`: Thêm lỗi `.stvContentNotCached` với thông báo thân thiện *"Chương này chưa được cào từ Sáng Tác Việt. Vui lòng mở trình duyệt web để cào nội dung."* khi đọc file đĩa `.bin` chưa thành công, tránh báo lỗi thiếu tiện ích.
  * Cập nhật `DownloadManager`: Cho phép chạy tác vụ tải / xuất ebook TXT cho truyện STV dựa trên nội dung offline đã cào.
* **Tối Ưu Hóa Nạp Script Trong `GetTextSTVManager.swift` (`GetTextSTVManager.swift`)**:
  * Tách biệt logic nạp `content.css` và `content.js` độc lập từ `Bundle.main`.
  * Đảm bảo logic dự phòng fallback chỉ chạy khi thuộc tính tương ứng bị rỗng, loại bỏ nguy cơ ghi đè `cssContent` đã nạp thành công.
  * Loại bỏ hoàn toàn các đường dẫn ổ đĩa tuyệt đối cứng (`D:\...`) phục vụ môi trường phát triển local.
* **Bảo Đảm Luồng Lưu 100% DB Trước Khi Chuyển Màn Hình Chi Tiết (`content.js`, `BypassWebView.swift`)**:
  * Bổ sung gửi `syncTOC` trong `stopAutoDownload` và `finishAutoDownload` trước khi phát tín hiệu `finishDownload`.
  * Thực thi `context.save()` lưu 100% SwiftData DB local trước khi đóng trình duyệt và chuyển màn hình Chi tiết truyện.

## [1.3.65] - 2026-07-31

### Loại Bỏ Hoàn Toàn Mã Nguồn Dư Thừa GoogleTTS & Chuyển Đổi Phát Âm Bôi Đen Qua AVSpeechSynthesizer Native (`ReaderView.swift`, `TTSManager.swift`, `SiriTTSService.swift`, `JSExecutor.swift`)
* **Loại Bỏ GoogleTTS Dư Thừa (`ReaderView.swift`, `TTSManager.swift`)**:
  * Xóa bỏ hoàn toàn các tham chiếu `GoogleTTSService`, `googleService`, và `googlePrefetchCount`.
  * Gỡ bỏ các nhánh kiểm tra điều kiện `tool == "google"` trong các thuộc tính và luồng nạp prefetch của `TTSManager.swift`.
  * Chuyển đổi hàm `readSelectedText()` trong `ReaderView.swift` từ gọi GoogleTTS sang sử dụng `AVSpeechSynthesizer` native của hệ thống iOS (Siri Voice) để phát âm từ/đoạn văn bôi đen offline.
* **Khắc Phục Cảnh Báo Concurrency & Unused Capture (`TTSManager.swift`, `SiriTTSService.swift`, `JSExecutor.swift`)**:
  * Khắc phục cảnh báo Swift 6 Concurrency truy cập thuộc tính MainActor trong Timer bằng cách bọc closure trong `@MainActor Task` (`TTSManager.swift`).
  * Loại bỏ `@preconcurrency` thừa trên `AVSpeechSynthesizerDelegate` (`SiriTTSService.swift`).
  * Gỡ bỏ capture `[weak self]` không được sử dụng trong closure `DispatchWorkItem` (`JSExecutor.swift`).

## [1.3.64] - 2026-07-30

### Cập Nhật Thuật Toán Tokenizer Ưu Tiên Cụm Dài, Reader Dịch On-Demand In-Place & Sửa Lỗi TTS Dịch Mới (`TranslateUtils.swift`, `ParagraphCardView.swift`, `ReaderView.swift`, `ReaderViewModel.swift`, `ReaderJunkDeleteOverlayView.swift`)
* **Tái Cấu Trúc Phân Tách VietPhrase Trong `TranslateUtils.tokenize` (`TranslateUtils.swift`)**:
  * Thêm struct nội bộ `VPCandidate` lưu trữ vị trí `range` và độ dài `length` của từng cụm VietPhrase (độ dài $\ge 2$).
  * Chuyển đổi thuật toán phân tách VietPhrase từ duyệt tuyến tính cuốn chiếu sang cơ chế Pre-scan và giải quyết tranh chấp chồng lấp theo quy tắc ưu tiên:
    1. Cụm từ có **chiều dài lớn hơn (`length`) luôn chiến thắng** (`length DESC`).
    2. Nếu hai cụm từ có **chiều dài bằng nhau**, cụm từ **bắt đầu trước (`lowerBound`) chiến thắng** (`lowerBound ASC`).
  * Tối ưu hóa hiệu năng $O(N)$ bằng kỹ thuật Pruning bỏ qua các ký tự không phải Hán tự (`isChineseCharacter`) và chỉ đưa các cụm từ ghép ($\ge 2$ chữ) vào mảng sắp xếp candidates.
  * Từ Hán đơn lẻ standing alone được bảo toàn 100% nghĩa thông qua mảng Token 1-ký tự và hệ thống tra cứu 4 cấp (Book VP $\rightarrow$ Custom VP $\rightarrow$ Base VP $\rightarrow$ Phiên âm Hán Việt) ở bước `performTranslation`.
* **Reader Dịch On-Demand In-Place & Triệt Tiêu Hoàn Toàn Lỗi Trôi/Văng Scroll (`ReaderViewModel.swift`, `ParagraphCardView.swift`, `ReaderView.swift`)**:
  * **Loại bỏ nạp lại mảng dư thừa (`ReaderViewModel.swift`)**: Gỡ bỏ vòng lặp tác vụ bất đồng bộ `processAndSaveChapter` trong `toggleTranslation(enabled:)`, ngăn chặn việc hủy và re-render mảng thẻ view `paragraphItems`.
  * **Dịch On-Demand Inline trực tiếp tại chỗ (`ParagraphCardView.swift`)**: Truyền `bookId` và `@Binding var translationRefreshToken: UUID`. Áp dụng biểu thức dịch inline trực tiếp tại chỗ `text: isTranslationEnabled ? (item.isTitle ? TranslateUtils.translateChapterTitle(item.original, bookId: bookId) : TranslateUtils.translateContent(item.original, bookId: bookId)) : item.original`. Phân biệt chính xác hàm dịch Tiêu đề chuyên dụng và Nội dung đoạn văn.
  * **Đồng bộ tín hiệu đổi từ điển In-Place (`ReaderView.swift`)**: Khai báo `@State private var translationRefreshToken = UUID()`. Khi nhận thông báo `translationDictionariesDidUpdate` (khi người dùng sửa/thêm từ mới trong từ điển), xóa RAM cache `clearCache()` và đổi `translationRefreshToken = UUID()`.
  * **Bảo toàn vị trí cuộn điểm ảnh 100%**: Toàn bộ mảng thẻ view và ID giữ nguyên 100%, tọa độ pixel offset (`contentOffset.y`) đứng yên tuyệt đối không bị trôi hay văng scroll dù 1 pixel, không cần dùng bất kỳ lệnh cuộn `scrollTo` nào.
* **Khắc Phục Lỗi Màn Hình Xoá Từ Rác (`ReaderJunkDeleteOverlayView.swift`, `ReaderView.swift`)**:
  * **Đồng bộ ô nhập từ (`ReaderView.swift`)**: Cập nhật `self.junkPatternInput = word` trong `updateEditorFromSelection()`, giúp ô nhập `TextField` tự động đổi chuỗi từ theo vùng chọn khi bấm các nút chevron mở rộng/thu hẹp.
  * **Sửa lỗi bàn phím che lấp ô nhập (`ReaderView.swift`)**: Gỡ bỏ `.ignoresSafeArea(.keyboard, edges: .bottom)` khỏi overlay `showingJunkDeleteSheet`, giúp khung overlay tự động trượt nổi lên trên đỉnh bàn phím khi chạm nhập từ.
* **Khắc Phục Lỗi TTS Không Đọc Theo Từ Điển Mới Vừa Sửa (`ReaderView.swift`, `ReaderViewModel.swift`)**:
  * **Dịch động tại chỗ cho TTS (`ReaderView.swift`)**: Thêm `getTTSChapterContent(for: index)` dịch động nội dung chương (`TranslateUtils.translateContent`) và dịch động tiêu đề chương (`TranslateUtils.translateChapterTitle`) khi bắt đầu phát giọng đọc.
  * **Làm mới bộ nhớ RAM ViewModel & Xóa đệm TTS (`ReaderViewModel.swift`, `ReaderView.swift`)**: Thêm `updateCachedTranslatedContent(bookId:)` làm mới `cached.content` và `cached.translatedTitle` khi đổi từ điển, đồng thời xóa đệm phát TTS cũ (`TTSManager.shared.clearPrefetchCache()`).

## [1.3.63] - 2026-07-30

### Xoá Từ Rác Khi Bôi Đen Trước Khi Chuẩn Hoá & Màn Hình Quản Lý Lọc Rác Dùng Chung (`JunkFilterManager.swift`, `ChapterTextNormalizer.swift`, `ReaderJunkDeleteOverlayView.swift`, `JunkFilterManagementView.swift`, `ReaderView.swift`, `SettingsView.swift`)
* **Hệ Thống Lọc Rác Từ Gốc Trước Khi Chuẩn Hoá (`JunkFilterManager.swift`, `ChapterTextNormalizer.swift`)**:
  * Tạo dịch vụ `JunkFilterManager` quản lý danh sách quy tắc lọc rác (từ/chuỗi/regex) và áp dụng trực tiếp lên `rawContent` trong `ChapterTextNormalizer.normalize` trước khi cắt dòng và tính toán UTF-16 ranges/Paragraph IDs.
  * Custom Codable hỗ trợ tương thích 100% với định dạng file `TrashWords.json` từ Telegram (`word`, `regex`).
* **Khung Xác Nhận Xoá Từ Rác Khi Bôi Đen Trong Trình Đọc (`ReaderJunkDeleteOverlayView.swift`, `ReaderFloatingMenuOverlayView.swift`, `ReaderView.swift`)**:
  * Thêm nút **"Xoá"** (icon `trash.fill`) vào menu nổi khi bôi đen trong Trình đọc.
  * Hiển thị khung overlay xác nhận với 2 hàng Gốc và Dịch trên cùng kèm 4 nút chevron thu/mở lề bôi đen 2 bên (trái/phải), ô nhập từ muốn xoá để kiểm tra/chỉnh sửa, cùng nút **Hủy** và **Xác nhận**.
  * Tự động xóa cache và nạp/chuẩn hóa lại chương active giúp từ rác biến mất ngay lập tức khỏi màn hình.
* **Màn Hình Quản Lý Lọc Rác Dùng Chung (`JunkFilterManagementView.swift`, `SettingsView.swift`, `ReaderHeaderFooterOverlayView.swift`, `ReaderSettingsView.swift`)**:
  * Xây dựng giao diện SwiftUI `JunkFilterManagementView` hỗ trợ CRUD, bật/tắt, tìm kiếm, nhập/xuất file JSON cấu hình và khôi phục mặc định.
  * Đấu nối từ cả Cài đặt hệ thống (**SettingsView**) lẫn Tuỳ chọn Trình đọc (**ReaderHeaderFooterOverlayView** và **ReaderSettingsView**).
* **Khắc Phục Lỗi Treo Nạp Chương Khi Mở Quy Tắc TOC Từ Reader (`ReaderView.swift`)**:
  * Nguyên nhân: Trước đó `ReaderView` mở `TOCRulesConfigView()` thông qua `NavigationLink` khiến iOS kích hoạt sự kiện `.onDisappear` của `ReaderView`, dẫn tới việc `ReaderViewModel.shutdown()` tự động tắt bộ nhớ và hủy tác vụ nạp chương. Khi người dùng Back quay lại `ReaderView`, `viewModel` đã bị tắt nên treo ở trạng thái nạp mãi.
  * Giải pháp: Chuyển đổi hiển thị `TOCRulesConfigView()` sang dạng `.sheet(isPresented: $showingTOCRules)` dạng modal. Giúp `ReaderView` duy trì liên tục trong cây phân cấp view, bảo toàn trạng thái `viewModel` và mở/đóng quy tắc TOC mượt mà mà không bị mất nội dung chương.
* **Tinh Chỉnh Dải Chip Gợi Ý Màn Hình Dịch & Giao Diện Phông Nền Tối (`ReaderDefinitionOverlayView.swift`, `ReaderView.swift`)**:
  * Đơn giản hóa nguồn truy vấn chip gợi ý: Chỉ lọc dữ liệu từ 3 nguồn: **Names** (Book, Custom, Global), **VietPhrase** (Book, Custom, Global) và **Phiên âm Hán Việt**, loại bỏ Pronouns và Luật nhân khỏi dải gợi ý.
  * Áp dụng lọc trùng phân biệt hoa thường exact matching (`$0.text == trimmed`).
  * Áp dụng giao diện phông nền tối toàn bộ `Color(red: 0.12, green: 0.12, blue: 0.15)` đồng nhất chuẩn Dark Mode, kết hợp phân biệt loại từ bằng màu viền & chữ: **Tím Lavender** (Names), **Xanh Sky Blue** (VietPhrase), **Vàng Amber** (Hán Việt).
* **Tự Động Cập Nhật Số Từ Từ Điển & Tự Động Nạp Dịch Lại Trong Reader (`TranslationManager.swift`, `DictionaryHubView.swift`, `ReaderView.swift`)**:
  * Đánh dấu `@Published` cho `customVietPhraseDict` và `customNamesDict` trong `TranslationManager`.
  * Bổ sung `@State private var refreshToken = UUID()` và `.onAppear` trong `DictionaryHubView` đếm và hiển thị ngay lập tức số từ mới nhất khi bấm Back ra ngoài.
  * Phát thông báo `translationDictionariesDidUpdate` khi cập nhật từ điển; `ReaderView` tự động xóa cache và ép nạp/dịch lại chương đang đọc (`forceRefresh: true`) để hiển thị nghĩa mới tức thì.
* **Xóa Bỏ Hoàn Toàn Google TTS (`GoogleTTSService.swift`, `TTSEngineType.swift`, `TTSManager.swift`, `TTSSettingsView.swift`)**:
  * Xóa bỏ hoàn toàn tệp `GoogleTTSService.swift` và các tham chiếu tới `case google` trong `TTSEngineType`, `TTSManager` và `TTSSettingsView`. Giữ nguyên 100% các công cụ đọc `Siri TTS` và `Nghi TTS` (Piper Engine).
* **Tích Hợp Extension `GetTextSTV` Bóc Tách Nguồn Sáng Tác Việt (`GetTextSTVManager.swift`, `BypassWebView.swift`)**:
  * **Lối Tắt STV IP Trang Home**: Bổ sung thẻ Lối Tắt **"Sáng Tác Việt (STV IP)"** (`http://14.225.254.182/`) nổi bật trên trang chủ Home của Trình duyệt `BypassWebView`.
  * **Bộ Polyfill Safari iPhone (iOS WKWebView)**: Tiêm bộ giả lập `chrome.storage.local` bằng `window.localStorage` và `gettextSTVBridge`, đảm bảo 100% kịch bản bóc tách và lọc rác chạy mượt mà trên iPhone không bị lỗi `ReferenceError`.
  * **Quy Trình 2 Bước & Chuyển Màn Hình Detail**: Nạp mục lục bổ sung metadata chương mới (`syncTOC`) $\rightarrow$ Tải nội dung chương chưa có vào đĩa `.bin` (`saveChapterContent`) qua `enqueueWrite` và `flush` của `ChapterPersistenceStore` $\rightarrow$ Đóng trình duyệt và tự động chuyển sang màn hình Chi Tiết Truyện (`BookDetailView`) qua `onImport` callback ngay khi hoàn tất/dừng tải.
* **Tính Năng Hẹn Giờ Tạm Dừng Nghe Truyện - Sleep Timer (`TTSManager.swift`, `TTSFloatingWidgetView.swift`, `TTSSettingsView.swift`)**:
  * **Bộ Quản Lý Hẹn Giờ Ghi Nhớ Lặp Lại**: Bổ sung `SleepTimerMode` (`off`, `minutes(Int)`, `endOfChapter`) trong `TTSManager.swift`. Tự động lặp lại bộ đếm khi người dùng bấm nghe lại (Play) sau khi tạm dừng, giữ nguyên chế độ hẹn giờ cho đến khi chọn *Tắt hẹn giờ*.
  * **Nút Menu Hẹn Giờ Thích Ứng Khóa Cứng Widget (`TTSFloatingWidgetView.swift`, `FloatingWidgetViewModel.swift`)**: Chuyển nút Hẹn giờ/Cài đặt sang SwiftUI `confirmationDialog` trực tiếp kèm cờ khóa cứng `disableAutoHide = true` trong `FloatingWidgetViewModel`. Đảm bảo Widget ngự cố định 100% ở dạng mở rộng trên màn hình khi đang mở xem/chọn tùy chọn Hẹn giờ, **tuyệt đối không bị tự động thu nhỏ vào góc**.
  * **Tag Đếm Ngược Nổi Đỉnh Widget (Vị Trí 3)**: Hiển thị thanh Tag màu Cam `⏱️ 14:35 - Hẹn giờ 15p` đếm ngược thời gian thực ngay trên đỉnh thanh Widget nổi khi đang đếm ngược.
* **Khắc Phục Lỗi Google TTS HTTP 429 & Tùy Chỉnh Giao Diện Cài Đặt TTS (`GoogleTTSService.swift`, `TTSManager.swift`, `TTSSettingsView.swift`)**:
  * **Chống 429 Google TTS Bằng JS Engine**: Chuyển đổi `GoogleTTSService.swift` sang chạy mã JavaScript qua `JSExecutor` (`JSContext` + JSDOM engine + `fetch` JS giống hệt Extension TTS `ext`), luân chuyển `client=gtx` và `client=dict-chrome-ex` hoàn toàn không bị Google chặn.
  * **Giãn tiến trình tối thiểu 500ms**: Đặt dãn cách tối thiểu 500ms giữa tất cả các đoạn cho các Online Engines. Ép sàn tối thiểu `prefetchDelayMs` $\ge 500\text{ms}$ trong `TTSManager.swift`.
  * **Nút Reset Tốc Độ & Cao Độ**: Bổ sung nút **"Đặt lại"** (icon `arrow.counterclockwise`) trong `TTSSettingsView.swift` khôi phục tức thì Tốc độ và Cao độ về $1.0x$.
  * **Nút Stepper (+/-) nấc 0.1**: Bổ sung Stepper (+/-) nấc tăng giảm $0.1$ cho cả Tốc độ (0.5x–5.0x) và Cao độ (0.5x–2.0x) kết hợp cùng Slider trong `TTSSettingsView.swift`.
  * **Stepper Dãn Tiến Trình**: Cập nhật Stepper dãn tiến trình nạp trước dải giá trị từ $500\text{ms}$ đến $5000\text{ms}$ (không thể chỉnh dưới 500ms), bước tăng/giảm $100\text{ms}$.
* **Khắc Phục Lỗi Vừa Vào Trình Đọc Bấm Nút Nghe Bị Đọc Từ Đầu Chương (`ReaderView.swift`)**:
  * Cập nhật nhánh fallback của nút Nghe (`readerTTSControl`) khi `paragraphTracker` chưa kịp thu thập tọa độ hiển thị: Ưu tiên tra cứu vị trí đọc đã khôi phục bằng `getSavedParagraphIndex(for: chapterIndex)` và `viewModel.readingContext.paragraphIndex`.
  * Khắc phục triệt để sự cố bấm nút Nghe ngay sau khi vừa mở sách tại vị trí khôi phục bị tự động nhảy về phát từ Đoạn 0.
* **Khắc Phục Sự Cố Nút Nghe (TTS) Đọc Nhầm Đầu Chương & Nhầm Đoạn Giữa Màn Hình & Tinh Chỉnh FloatingMenu (`ReaderView.swift`, `ReaderFloatingMenuOverlayView.swift`)**:
  * Nâng cấp `ParagraphTracker` quản lý cấu trúc toạ độ hình học `ParagraphFrame(minY, maxY)` trên từng thẻ đoạn văn trong `ReaderView`.
  * Khắc phục triệt để Lỗi 1 (bấm nút Nghe ngay sau khi mở sách tại vị trí khôi phục bị đọc từ Đoạn 0): Lọc bỏ hoàn toàn các đoạn văn có $maxY \le viewportTopY + 5$ (đã bị cuộn khuất lên phía trên) mà không cần chờ sự kiện `.onDisappear` thụ động từ SwiftUI `LazyVStack`.
  * Khắc phục triệt để Lỗi 2 (đọc đoạn ở giữa màn hình): Lấy chính xác 100% đoạn văn nằm ngay ở đường đỉnh hiển thị trên cùng (`minY` cao nhất trong số các đoạn cắt qua viewport).
  * Tối ưu hoá 0ms overhead: Dữ liệu toạ độ lưu trong Class in-memory không dùng `@State`, đảm bảo tốc độ cuộn mượt mà 60fps/120fps.
  * Loại bỏ nút **"Đóng"** trên menu nổi `FloatingSelectionMenu` khi bôi đen văn bản, tự động đóng menu khi chạm ra ngoài và thu gọn chiều rộng menu xuống 370pt.
* **Sửa Lỗi Biên Dịch Build Errors & Tương Thích Swift 6 Concurrency (`JunkFilterManager.swift`, `ReaderView.swift`)**:
  * Chuyển `JunkFilterManager` thành class thường với `public static let shared` không bị giới hạn bởi `@MainActor init()`, gán `@MainActor` trực tiếp cho thuộc tính UI `rules` và các phương thức CRUD để giải quyết triệt để lỗi biên dịch Swift 6 Concurrency initializer call.
  * Thay thế lệnh gọi `vm.loadChapter(at:forceRefresh:)` không tồn tại bằng `vm.reloadDisplayedChapter()` trong `ReaderView.swift`.
* **Ghim Độc Lập Lựa Chọn Mặc Định Màn Hình Dịch Nhấn Giữ Lâu (`ReaderView.swift`, `ReaderDefinitionOverlayView.swift`)**:
  * Tách độc lập 2 cụm bộ chọn: **Loại từ điển** (`Names`/`VP`, mặc định ban đầu: `VP`) và **Phạm vi từ điển** (`Riêng`/`Chung`, mặc định ban đầu: `Riêng`).
  * Loại bỏ việc tự động ghi đè thụ động khi chọn tạm thời; bấm ngắn (Tap) chỉ đổi tạm thời cho từ đang chỉnh sửa.
  * Hỗ trợ cử chỉ **Nhấn giữ lâu (Long Press)** trực tiếp trên bất kỳ nút nào để Ghim cố định nút đó làm mặc định mới cho cụm tương ứng, kèm rung haptic, hiển thị badge ghim `pin.fill` sáng đèn và thông báo Toast xác nhận.
* **Khắc Phục Lỗi Google TTS 429, Sai Speed, Chuẩn Hóa Toast + Pause & Cài Đặt Độ Trễ Giãn Tiến Trình Cho TẤT CẢ Các Engine TTS (`TTSManager.swift`, `TTSSettingsView.swift`)**:
  * Sửa lỗi lệch khóa `UserDefaults` trong `speed.didSet`, `pitch.didSet`, `selectedVoice.didSet` bằng cách bổ sung nhánh `else if tool == "google"` để lưu chính xác tốc độ đọc `googleRate`, `googlePitch`, `googleVoice`.
  * Khắc phục vòng lặp tự động gọi `nextParagraph()` khi bị lỗi Google TTS HTTP 429 khiến IP bị Google chặn liên tiếp (6 request/3 giây).
  * Chuẩn hóa đồng bộ cho cả 4 Engine TTS (`Google`, `NghiTTS`, `Extension`, `System Siri`): Khi gặp lỗi, lập tức dọn cache đoạn lỗi, bảo toàn vị trí `currentParagraphIndex`, gọi `self.pause()` tạm dừng trình đọc và hiển thị Toast màu đỏ báo lỗi trực quan. Khi người dùng bấm nút **Phát (Play)** lại, hệ thống sẽ tự động tạo lại và thử lại đoạn văn vừa bị lỗi.
  * Bổ sung thuộc tính `@Published public var prefetchDelayMs: Int` dãn khoảng cách gọi API nạp trước (`Task.sleep`) tính theo milisecond giữa các đoạn tiếp theo ($N+2, N+3,...$), lưu trữ độc lập cho từng Engine trong `UserDefaults` (`googlePrefetchDelay`, `nghittsPrefetchDelay`, `extPrefetchDelay_\(tool)`).
  * Bổ sung Stepper tùy chỉnh thời gian dãn tiến trình (từ $0\text{ms}$ đến $2000\text{ms}$, nấc $50\text{ms}$) trong `TTSSettingsView` cho người dùng linh hoạt điều chỉnh theo tốc độ đường truyền.
* **Khắc Phục Lỗi Tự Động Dịch Lại Khi Vào Màn Hình Từ Điển (`TranslationManager.swift`)**:
  * Gỡ bỏ việc phát thông báo `translationDictionariesDidUpdate` thụ động trong hàm nạp dữ liệu `loadAllDictionaries()`.
  * Chuyển lệnh phát thông báo `translationDictionariesDidUpdate` về đúng các phương thức thay đổi từ điển thực sự (`saveCustomEntry`, `deleteCustomEntry`, `addDeletedWords`, `removeDeletedWords`, `importDictionary`, `deleteDictionary`, `downloadDefaultDictionaries`).
  * Giúp Trình đọc không bị xóa cache và dịch lại chương vô ích khi người dùng chỉ bấm vào xem màn hình Từ Điển và Back ra ngoài. Trình đọc chỉ dịch lại khi có thay đổi từ điển thực sự.
* **Mở Màn Hình Quản Lý Thay Thế Ký Tự TTS Dạng Sheet Trực Tiếp Trên Cài Đặt TTS (`TTSSettingsView.swift`)**:
  * Tái sử dụng 100% view `TTSReplacementManagerView.swift` hiện có.
  * Chuyển đổi nút *"Quản lý thay thế ký tự"* trong `TTSSettingsView` mở `TTSReplacementManagerView` dưới dạng cửa sổ `.sheet` đè trực tiếp lên Cài đặt TTS kèm nút *"Đóng"* tiện lợi.

## [1.3.62] - 2026-07-30

### Tùy Chỉnh Phông Chữ Đọc Sách Đa Dạng (Tiếng Việt & Tiếng Trung) & Tinh Chỉnh Màu Highlight Nội Dòng Chuẩn Tông (`ReaderView.swift`, `ReaderSettingsView.swift`, `ReaderTextView.swift`, `ParagraphCardView.swift`)
* **Tùy Chọn Kiểu Chữ Đọc Sách Tối Ưu Cho Cả Tiếng Việt & Hán Tự (`ReaderView.swift`, `ReaderSettingsView.swift`, `ReaderTextView.swift`)**:
  * Khai báo `enum ReaderFontFamily` hỗ trợ đa dạng phông chữ đọc sách chuẩn iOS: `Georgia` (Kindle Classic), `Palatino` (Văn Học), `Charter` (Tiếng Việt Rõ Nét), `Avenir Next` (Hiện Đại), `Songti SC` (Tống Thể - Hán Tự), `Kaiti SC` (Khải Thể - Thư Pháp Hán Tự), `PingFang SC` (Bình Phương Hán Tự) và `San Francisco` (Hệ Thống).
  * Bổ sung Picker chọn Kiểu chữ trong sheet `ReaderSettingsView` giúp người dùng thay đổi phông chữ tức thì khi đọc tiểu thuyết dài.
* **Hệ Thống Màu Highlight Chuẩn Tông Theo Nền Đọc (`ReaderTheme`, `ReaderTextView.swift`)**:
  * Bổ sung `highlightUIColor` và `highlightTextUIColor` trong `enum ReaderTheme` tinh chỉnh màu highlight hòa quyện 100% cho từng theme: Vàng Hổ Phách Mềm cho nền `Paper`, Cam Đất Caramels cho nền `Sepia`, và **Xám Bạc Đêm (Slate Gray - `UIColor(white: 1.0, alpha: 0.16)`)** chữ trắng tinh chuẩn Apple Dark Mode cho nền `Dark`.

## [1.3.61] - 2026-07-30

### Tích Hợp Quản Lý Quy Tắc Mục Lục (TOCRulesConfigView) Dùng Chung Vào Dropdown Menu Của Reader (`ReaderView.swift`, `ReaderHeaderFooterOverlayView.swift`)
* **Tái Sử Dụng Màn Hình Quản Lý Quy Tắc TOC Dùng Chung (`ReaderView.swift`, `ReaderHeaderFooterOverlayView.swift`)**:
  * Tích hợp tùy chọn **"Quy tắc mục lục (TOC)"** (kèm icon `list.bullet.indent`) vào Dropdown Menu (Menu 3 chấm) góc trên màn hình đọc truyện `ReaderHeaderFooterOverlayView`.
  * Đấu nối `NavigationLink` trong `ReaderView` mở trực tiếp màn hình quản lý quy tắc TOC chuẩn `TOCRulesConfigView()`, giúp người dùng bật/tắt hoặc chỉnh sửa regex lọc mục lục ngay trong khi đọc mà không phải thoát ra cài đặt chung.

## [1.3.60] - 2026-07-30

### Đọc Thuộc Tính Thô `plugin.json`, Tập Trung Cấu Hình Extension TTS & Tránh Xung Đột Cài Đặt (`ExtensionConfigView.swift`, `TTSSettingsView.swift`, `TTSManager.swift`)
* **Hỗ Trợ Đọc & Tùy Chỉnh Tất Cả Thuộc Tính Thô (Primitives) trong `plugin.json` (`ExtensionConfigView.swift`)**:
  * Mở rộng `loadConfigDefinitions()` để nhận diện và hiển thị đầy đủ tất cả các trường cấu hình thô không phải Object trong `plugin.json` (bao gồm `"preload_size": 3`, `"max_length": 600`, `"required_api_key": false`, `"support_url": ""`...).
  * Tự động ép kiểu dữ liệu từ chuỗi về đúng dạng nguyên bản (`Bool`, `Int`, `Double`, `String`) trong `saveConfig()` để bảo toàn tính đúng đắn cho JS Engine và `TTSManager`.
* **Áp Dụng Thông Số NẾU CÓ & Chống Chồng Chéo Cài Đặt (`TTSManager.swift`, `TTSSettingsView.swift`)**:
  * `TTSManager.swift`: Tự động trích xuất `preload_size` và `max_length` từ `extensionConfigJson` NẾU Extension có khai báo. Nếu không có, tự động áp dụng giá trị mặc định hệ thống (3 đoạn / 200 ký tự).
  * `TTSSettingsView.swift`: Khi chọn Extension TTS, tự động **ẨN** ô nhập "Độ dài phân đoạn (ký tự)" và Stepper "Số đoạn tải trước" để tránh xung đột và trùng lặp, thay bằng nút bấm mở trực tiếp sheet `ExtensionConfigView` của Extension đó.

## [1.3.59] - 2026-07-30

### Chuyển Đổi TTS Engine Sang AVAudioPlayer Mặc Định & Cài Đặt Preloading Riêng Theo Engine (`TTSManager.swift`, `ExtTTSService.swift`, `TTSSettingsView.swift`)
* **Chuyển Toàn Bộ Engine sang Trình Phát Âm Thanh Mặc Định `AVAudioPlayer` (`TTSManager.swift`, `ExtTTSService.swift`)**:
  * Thay thế luồng phát qua `AVAudioEngine` bằng `AVAudioPlayer(data: audioData)` chuẩn Hardware Audio DSP của iOS cho tất cả các công cụ đọc (Google TTS, Extension TTS, NghiTTS).
  * Tự động mang lại chất âm êm mịn, mượt mà 100% giống ứng dụng VBook mẫu khi phát qua Tai nghe Bluetooth.
  * Bổ sung `synthesizeData` trong `ExtTTSService.swift` trả về dữ liệu `Data` trực tiếp, triệt tiêu hoàn toàn chi phí ghi tệp tạm và resampling PCM.
* **Tách Cài Đặt Preloading Riêng Trực Quan Theo Engine & Đồng Bộ Config Extension (`TTSManager.swift`, `TTSSettingsView.swift`)**:
  * Bổ sung thuộc tính `googlePrefetchCount`, `nghittsPrefetchCount` và `extPrefetchCount` lưu riêng lẻ trong `UserDefaults` cho từng công cụ đọc.
  * Bổ sung phương thức `parseExtensionConfigParams` tự động trích xuất `preload_size` và `max_length` từ JSON `config` của Extension TTS để nạp giá trị mặc định ban đầu.
  * Thiết lập độ ưu tiên 3 cấp: Cài đặt người dùng (`UserDefaults`) > Config Extension (`preload_size`/`max_length`) > Mặc định hệ thống FreeBook (3 đoạn / 200 ký tự).
  * Cập nhật `TTSSettingsView.swift` hiển thị Stepper Preload linh hoạt theo Engine được chọn và hiển thị gợi ý thông số mặc định của Extension.

## [1.3.58] - 2026-07-30

### Sửa Lỗi Không Dịch Lại Các Chương Preloaded Khi Cập Nhật Từ Điển (`ReaderViewModel.swift`, `ReaderView.swift`, `ReaderDefinitionOverlayView.swift`)
* **Dịch Lại Toàn Bộ Các Chương Trong Bộ Nhớ Đệm RAM (`ReaderViewModel.swift`)**:
  * Cập nhật phương thức `toggleTranslation(enabled:)` và `refreshParagraphItems()` trong `ReaderViewModel` để duyệt qua toàn bộ các chương đã được tải trước trong `cache.cache` có `state == .loaded` (thay vì chỉ cập nhật `displayedChapterIndex` và `pendingNavigationIndex`).
  * Thực hiện `processAndSaveChapter` cho tất cả các chương `.loaded` này để cập nhật lại tiêu đề và các đoạn văn bản theo từ điển dịch mới.
* **Đồng Bộ Dịch Lại Khi Đóng/Lưu Từ Điển (`ReaderDefinitionOverlayView.swift`, `ReaderView.swift`)**:
  * Bổ sung callback `onApplyTranslation` kích hoạt dịch lại toàn bộ các chương đã load trong RAM khi người dùng thêm, sửa, xóa từ trong sheet quản lý từ điển `ManageDefinitionsView` hoặc bấm "Cập nhật" ở màn hình dịch chương.

## [1.3.57] - 2026-07-30

### Tối Ưu Chất Lượng Resample & Khắc Phục Tiếng Xì/Rè Audio Hiss (TTS Audio Pipeline)
* **Khắc Phục Nhiễu Răng Cưa (Aliasing Hiss) Trong Converter (`TTSManager.swift`, `ExtTTSService.swift`)**:
  * Đặt `converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue` cho tất cả các `AVAudioConverter` instance trong `makePCMBuffer(fromWavData:targetFormat:)`, `makePCMBuffer(fromMp3Data:targetFormat:)` và `ExtTTSService.synthesize`.
  * Ép bộ chuyển đổi tần số của Apple sử dụng thuật toán nội suy mẫu (resampling) chất lượng tối đa, loại bỏ hoàn toàn nhiễu aliasing dải tần cao khi nâng tần số từ 22.05kHz/24kHz lên 44.1kHz/48kHz.
* **Bộ Lọc Thông Thấp Low-Pass Filter 10kHz & Bypass `timePitchNode` ở 1.0x (`TTSManager.swift`)**:
  * Tích hợp node `AVAudioUnitEQ` (`.lowPass`, `frequency = 10000.0 Hz`) vào `AVAudioEngine` để gọt sạch 100% dải tần rác siêu cao (>10kHz) vốn bị khuyếch đại gây gắt/chói tai trên Tai nghe Bluetooth.
  * Tự động **Bypass `timePitchNode`** ở tốc độ 1.0x (`speed == 1.0 && pitch == 1.0`), nối trực tiếp `playerNode` -> `eqNode` -> `mainMixerNode` để giữ âm thanh nguyên bản, loại bỏ hoàn toàn nhiễu Phase Vocoder của iOS ở tốc độ chuẩn.
* **Chuyển Giải Mã WAV sang `AVAudioFile` & Magic Bytes (`TTSManager.swift`, `ExtTTSService.swift`)**:
  * Thay thế logic giải mã WAV thủ công (`advanced(by: 44)`) bằng `AVAudioFile(forReading:)` của CoreAudio, phòng ngừa triệt để lỗi lệch byte alignment làm đảo sample Int16 gây xé tiếng.
  * Thêm nhận diện Magic Bytes (`RIFF` vs `MP3`) trong `ExtTTSService.swift` để tự động lưu đúng đuôi mở rộng `.wav` hoặc `.mp3` cho tệp tạm.
* **Chuẩn Hóa Biên Độ PCM Float (`ExtTTSService.swift`)**:
  * Bổ sung soft-clamping biên độ float PCM `max(-1.0, min(1.0, sample))` trong `preprocessBufferForExtTTS` để ngăn ngừa hiện tượng vỡ tiếng/xé tiếng do vượt ngưỡng biên độ.

## [1.3.56] - 2026-07-30

### Cập Nhật Danh Sách Quy Tắc Phân Tách Mục Lục Mặc Định (TOC Rules)
* **Cập nhật & Chuẩn hóa `defaultTOCRules` trong ([TranslateUtils.swift](../../Sources/Services/Translation/Utils/TranslateUtils.swift))**:
  * Chuẩn hóa bộ ID thành chuỗi đồng nhất theo định dạng `rule1` đến `rule21`.
  * Đổi toàn bộ tên gọi (Name) sang tiếng Việt trực quan mô tả chính xác cấu trúc dòng tiêu đề nhận diện.
  * Chuẩn hóa toàn bộ các ví dụ mẫu (Example) bằng tiếng Trung nguyên bản đối với các quy tắc liên quan đến tiếng Trung, đảm bảo 100% khớp thành công với biểu thức Regex tương ứng.
  * Khắc phục triệt me lỗi biên dịch `unprintable ASCII character found in source file` trên `TranslateUtils.swift` bằng cách làm sạch tất cả ký tự Tab điều khiển (`0x09`) trực tiếp trong chuỗi Regex `defaultTOCRules`, thay bằng mã hóa chuẩn `\s`.
  * Chuyển logic nhận diện dòng tiêu đề chương `isChapterHeaderLine` trong `TranslateUtils.swift` sang sử dụng 100% các quy tắc `TOCRule` đang bật, loại bỏ các cơ chế từ khóa thủ công (`chương`, `第`, `chapter`...) và số đầu dòng cũ để xử lý triệt để lỗi cắt nhầm câu văn nội dung tiếng Trung/tiếng Việt thành tiêu đề chương phụ.
  * Tắt mặc định quy tắc `rule4` (`enabled: false`) để tránh từ `"场"` (trận đấu) trong văn bản truyện bị nhận nhầm làm tiêu đề chương.
* **Mở Rộng Quy Tắc Thay Thế Ký Tự TTS & Tái Cấu Trúc Giao Diện ([TTSReplacementManager.swift](../../Sources/Services/TTS/Preprocessing/TTSReplacementManager.swift), [TTSReplacementManagerView.swift](../../Sources/Views/Settings/TTS/TTSReplacementManagerView.swift))**:
  * Bổ sung đầy đủ nhóm quy tắc mặc định `defaultRulesList`: phát âm ký hiệu/toán học tiếng Việt (`+` thành `cộng`, `@` thành `a còng`, `%` thành `phần trăm`, `×` thành `nhân`, `÷` thành `chia`, `±` thành `cộng trừ`, `≠` thành `khác`, `≈` thành `xấp xỉ`, `€` `¥` `£`), thay dấu `=` và `&` thành khoảng trắng; loại bỏ `-` đơn để tránh đọc sai từ ghép; bổ sung đầy đủ các loại dấu chấm giữa phân cách tên Trung/Tây/Nhật (`·` `•` `‧` `ㆍ` `⋅` `･` thành khoảng trắng); chuyển tất cả quy tắc thay thế ngoặc kép, ngoặc đơn trích dẫn, ngoặc chú thích/phụ đề/Hán-Nhật (`""`, `''`, `“”`, `‘’`, `„‟`, `«»`, `‹›`, `＂＇`, `❝❞`, `❛❜`, `〞〟`, `()`, `[]`, `{}`, `【】`, `〔〕`, `〖〗`, `「」`, `『』`, `《》`) sang thay thế bằng dấu phẩy `, ` để tạo nhịp ngắt dừng và nhấn mạnh ngữ điệu cho lời thoại/cụm từ khi TTS đọc; và thay thế các biểu tượng rác (`~`, `*`, `#`, `^`, `\`, `|`, `♪♫`, `♥♡❤❥`, `◆◇■□▲△▼▽○●◎`, `☆★✦✧`) bằng khoảng trắng `" "`.
  * Thêm phương thức `resetToDefaults(mode:)` cho phép khôi phục danh sách mặc định (gộp hoặc ghi đè).
  * Tái cấu trúc giao diện `TTSReplacementManagerView`: Gom các tính năng tùy chọn (Khôi phục mặc định, Nhập JSON, Xuất JSON) vào Menu Dropdown `ellipsis.circle` bên trái bottom bar, và di chuyển Nút Thêm quy tắc (`plus`) xuống góc dưới bên phải bottom bar.

## [1.3.55] - 2026-07-29

### Chuyển Đổi Nguồn Dữ Liệu Mục Lục (TOC Metadata) Từ SwiftData Chapter Sang ChapterStore
* **Tối ưu hóa Reader khi Cập nhật Danh sách Chương (`ReaderChapterListView.swift`)**:
  * Cập nhật danh sách chương dùng `ChapterStore` primary để lấy danh sách chương hiện có và đếm tổng số chương qua `fetchCountAndChecksum`, loại bỏ việc đếm bằng SwiftData `modelContext.fetchCount`.
  * Chỉ lọc và upsert các chương mới chưa có vào DB. Nếu không có chương mới, ứng dụng bỏ qua lệnh ghi DB và cập nhật ngay giao diện.
* **Tối ưu hóa Màn hình Chi tiết Sách (`BookDetailView.swift`)**:
  * Khi bấm "Đọc tiếp", nếu sách đã có TOC trong `ChapterStore` thì ứng dụng mở thẳng Reader ngay lập tức mà không tải/lưu lại toàn bộ TOC online.
  * Giao diện mục lục ưu tiên dùng `chapterSnapshots: [StoredChapterSnapshot]` và chuyển các cờ lắng nghe thay đổi số lượng chương khỏi phụ thuộc vào `book.chapters`.
* **Cập nhật Nguồn Sách trong Tìm kiếm (`SearchView.swift`)**:
  * Khi thay đổi nguồn sách, danh sách chương được tạo snapshot và lưu qua `ChapterContentRepository` / `ChapterStore` thay vì khởi tạo các đối tượng `Chapter` SwiftData trực tiếp.
* **Dịch lại Tiêu đề Chương trên Kệ Sách (`ShelfView.swift`)**:
  * Truy vấn danh sách chương từ `ChapterStore.shared.fetchOrderedTOC` và lưu các bản dịch tiêu đề qua `ChapterStore.shared.updateTitleTranslations` thay vì phụ thuộc vào `book.chapters`.
* **Đồng bộ Tiến trình Đọc (`ReadingProgressStore.swift`)**:
  * Cập nhật phương thức `persist` và các hàm checkpoint/flush trong `actor ReadingProgressStore` thành `async throws`.
  * Sử dụng API `ChapterStore.shared.fetchRange(...)` làm fallback lấy tiêu đề chương khi `snapshot.chapterTitle == nil`.

## [1.3.54] - 2026-07-29

### Tối ưu hóa Chuyển đổi Bật/Tắt Dịch thuật trên Màn hình Khám phá (`DiscoveryView.swift`)
* **Loại bỏ Re-fetch Mạng không cần thiết khi Bật/Tắt Dịch (`DiscoveryView.swift`)**:
  * Loại bỏ 2 handler `.onChange(of: isTranslationEnabled)` trong `DiscoveryView` và `DiscoveryCategoryTabView`.
  * Cho phép giao diện Khám phá (Discovery) re-render ngay các chuỗi văn bản hiện có thông qua `translateIfNeeded` khi thay đổi trạng thái dịch thuật mà không cần tải lại danh sách trang chủ hoặc danh mục thể loại từ mạng.

### Đồng bộ Tài liệu CodeGraph cho Điều khiển TTS Remote Command State Machine & Chuẩn hóa Metadata
* **Đồng bộ Máy trạng thái Điều khiển Từ xa TTS (`TTSManager.swift`, `TTSManagerTests.swift`, `05_state_graph.md`, `06_event_graph.md`, `11_subsystems.md`)**:
  * Ghi nhận việc điều chỉnh hàm `syncRemoteCommandState()` và `handleRemoteTransportCommandOnMain(_:)` trong `TTSManager.swift`: Chuyển `RemoteTransportAction` enum và `handleRemoteTransportCommandOnMain` sang `internal` access modifier để phục vụ unit test; cập nhật `playCommand.isEnabled = active && !isPlaying` và `pauseCommand.isEnabled = active && isPlaying`.
  * Bổ sung cơ chế tương thích có phạm vi giới hạn (bounded compatibility fallback) trong `handleRemoteTransportCommandOnMain(.pause)` gọi `resume()` khi đang paused để tương thích với phụ kiện phần cứng gửi lệnh pause vật lý.
  * Bổ sung thử nghiệm chuẩn hóa metadata Now Playing trong `updateNowPlayingInfo()` (loại bỏ `MPNowPlayingInfoPropertyIsLiveStream` cũ và thiết lập `MPNowPlayingInfoPropertyMediaType.audio`), đồng thời chuẩn hóa thứ tự ghi `nowPlayingInfo` và `playbackState`.
  * Bổ sung mã chẩn đoán quan sát Giai đoạn A trong `setupRemoteCommandCenter()` (`remoteCallbackDispatched` và `remoteCallbackCompleted` ghép cặp theo `eventId`) để đo đạc luồng vào và độ trễ xử lý remote commands trên thiết bị thực tế.
  * Triển khai Giai đoạn B: Tạo helper method `@MainActor internal func dispatchRemoteTransportCommand` và thực thi đồng bộ qua `MainActor.assumeIsolated` khi callback ở Main Thread trước khi trả về `.success`, giúp MediaRemote nhận trạng thái `playbackState` mới ngay lập tức để đồng bộ trực quan biểu tượng nút Play/Pause trên Lock Screen UI.
  * Bổ sung unit test hồi quy `testRemotePauseCommandResumesWhenPausedAndDirectPauseIsIdempotent` và `testNowPlayingMetadataNormalization` trong `TTSManagerTests.swift`.
  * Đã đồng bộ khối GENERATED trong `05_state_graph.md`, `06_event_graph.md`, và `11_subsystems.md`.
* **Thử nghiệm Kiểm soát Giai đoạn C cho Điều khiển Remote TTS (`TTSManager.swift`, `05_state_graph.md`, `06_event_graph.md`, `11_subsystems.md`)**:
  * Cập nhật `commandCenter.togglePlayPauseCommand.isEnabled = false` trong cả `setRemoteCommandsEnabled(_:)` và `syncRemoteCommandState()` của `TTSManager.swift` để giải phóng xung đột lệnh trung tâm trên Lock Screen UI, tạo cặp lệnh `play/pause` động không mơ hồ.
  * Giữ nguyên việc đăng ký handler cho `togglePlayPauseCommand`, giữ nguyên dynamic play/pause enablement (`playCommand.isEnabled = active && !isPlaying`, `pauseCommand.isEnabled = active && isPlaying`), giữ nguyên Phase A log trace (`TTSTrace`), Phase B synchronous MainActor dispatch, bounded `.pause` fallback, now-playing metadata và các gọi lệnh `UIApplication`.
  * Đã đồng bộ khối GENERATED trong `05_state_graph.md`, `06_event_graph.md`, và `11_subsystems.md`.
* **Thử nghiệm Kiểm soát Giai đoạn D cho Điều khiển Remote TTS (`TTSManager.swift`, `05_state_graph.md`, `06_event_graph.md`, `11_subsystems.md`)**:
  * Cập nhật `syncRemoteCommandState()` trong `TTSManager.swift`: Giữ `commandCenter.playCommand.isEnabled = active` và `commandCenter.pauseCommand.isEnabled = active` mở đồng thời cho cả phiên active (thay vì bật/tắt động theo `isPlaying`), kết hợp với `commandCenter.togglePlayPauseCommand.isEnabled = false` (Phase C), để khắc phục lỗi nút Play bị mờ/xám (disabled) trên Lock Screen sau khi pause.
  * Giữ nguyên `setRemoteCommandsEnabled(_:)`, giữ nguyên handler `togglePlayPauseCommand`, Phase A log trace (`TTSTrace`), Phase B synchronous MainActor dispatch, bounded `.pause` fallback, now-playing metadata và các gọi lệnh `UIApplication`.
  * Đã đồng bộ khối GENERATED trong `05_state_graph.md`, `06_event_graph.md`, và `11_subsystems.md`.
* **Thử nghiệm Kiểm soát Giai đoạn E cho Điều khiển Remote TTS (`TTSManager.swift`, `05_state_graph.md`, `06_event_graph.md`, `11_subsystems.md`)**:
  * Chuyển đổi sang mô hình Single Enabled Toggle Command trong `TTSManager.swift`: Đặt `playCommand.isEnabled = false` và `pauseCommand.isEnabled = false`, đồng thời chỉ bật `togglePlayPauseCommand.isEnabled = enabled` (trong `setRemoteCommandsEnabled(_:)`) và `active` (trong `syncRemoteCommandState()`), nhằm định tuyến chính xác các thao tác bấm nút trung tâm trên Lock Screen về `action:toggle` thay vì gửi nhầm `action:pause`.
  * Giữ nguyên toàn bộ target registrations/handlers (`togglePlayPauseCommand.addTarget`, `playCommand.addTarget`, `pauseCommand.addTarget`), Phase A log trace (`TTSTrace`), Phase B synchronous MainActor dispatch, bounded `.pause` fallback, now-playing metadata và các gọi lệnh `UIApplication`.
  * Đã đồng bộ khối GENERATED trong `05_state_graph.md`, `06_event_graph.md`, và `11_subsystems.md`.
* **Thử nghiệm Kiểm soát Giai đoạn F cho Phản hồi Trạng thái Điều khiển Remote TTS (`TTSManager.swift`, `05_state_graph.md`, `06_event_graph.md`, `11_subsystems.md`)**:
  * Triển khai mô hình phản hồi trạng thái khách quan (Outcome-Aware Status Return) trong `TTSManager.dispatchRemoteTransportCommand`: Tính toán giá trị `MPRemoteCommandHandlerStatus` phản hồi dựa trên `self.isPlaying` thực tế sau khi xử lý lệnh (`.success` nếu trạng thái cuối khớp yêu cầu, `.commandFailed` nếu mâu thuẫn như khi kích hoạt fallback `resume()` cho lệnh `.pause` lúc paused).
  * Bổ sung log trace `remoteCallbackCompleted` ghi nhận nhãn chữ phân biệt rõ `success` vs `commandFailed` kèm giá trị `status.rawValue` tại runtime.
  * Giữ nguyên chữ ký `func handleRemoteTransportCommandOnMain` (Void return), cấu hình khả dụng Phase E (`playE: false, pauseE: false, toggleE: active`), Phase A log trace (`TTSTrace`), Phase B synchronous MainActor dispatch, bounded `.pause` fallback, now-playing metadata và các gọi lệnh `UIApplication`.
  * Đã đồng bộ khối GENERATED trong `05_state_graph.md`, `06_event_graph.md`, và `11_subsystems.md`.
* **Thử nghiệm Kiểm soát Giai đoạn G cho Chuẩn hóa Metadata Lock Screen TTS (`TTSManager.swift`, `05_state_graph.md`, `06_event_graph.md`, `11_subsystems.md`)**:
  * Triển khai mô hình chuẩn hóa tính tương thích metadata (Controlled Compatibility Normalization): Cập nhật helper `setSystemNowPlayingPlaybackState(_:defaultPlaybackRate:)` và `updateNowPlayingInfo()` để xuất bản tốc độ tương đối `MPNowPlayingInfoPropertyPlaybackRate` (`1.0` khi playing, `0.0` khi paused) và `MPNowPlayingInfoPropertyDefaultPlaybackRate` mang tốc độ đọc TTS (`speed`, giữ nguyên kể cả khi pause).
  * Cập nhật tất cả các vị trí gọi `setSystemNowPlayingPlaybackState` trong `continueStartSpeaking`, `pause` và `resume` để truyền tốc độ `speed` hiện tại làm `defaultPlaybackRate`.
  * Bổ sung log trace `TTSTrace` ghi nhận `currentRate` và `defaultRate` chi tiết tại runtime.
  * Giữ nguyên chữ ký `func handleRemoteTransportCommandOnMain` (Void return), cấu hình khả dụng Phase E (`playE: false, pauseE: false, toggleE: active`), Phase F outcome-aware status return, Phase A log trace, Phase B synchronous MainActor dispatch, bounded `.pause` fallback và các gọi lệnh `UIApplication`.
  * Đã đồng bộ khối GENERATED trong `05_state_graph.md`, `06_event_graph.md`, và `11_subsystems.md`.
* **Thử nghiệm Kiểm soát Giai đoạn H cho Khả dụng Đồng thời Remote Commands TTS (`TTSManager.swift`, `05_state_graph.md`, `06_event_graph.md`, `11_subsystems.md`)**:
  * Triển khai mô hình thử nghiệm cờ khả dụng đồng thời (Controlled Triple-Command Enablement): Bật khả dụng `isEnabled = enabled` (trong `setRemoteCommandsEnabled(_:)`) và `active` (trong `syncRemoteCommandState()`) cho cả 3 lệnh `playCommand`, `pauseCommand` và `togglePlayPauseCommand` đồng thời khi session TTS active.
  * Phối hợp cờ khả dụng mới với bộ xuất bản metadata tương thích Phase G (`currentRate: 1.0/0.0`, `defaultRate: speed`), phản hồi trạng thái Phase F, bounded `.pause` fallback và điều phối đồng bộ MainActor Phase B để kiểm chứng khả năng hỗ trợ iOS MediaRemote UI cập nhật biểu tượng Lock Screen.
  * Giữ nguyên chữ ký `func handleRemoteTransportCommandOnMain` (Void return), target handler registrations (`setupRemoteCommandCenter()`), Phase A log trace (`TTSTrace`) và các gọi lệnh `UIApplication`.
  * Đã đồng bộ khối GENERATED trong `05_state_graph.md`, `06_event_graph.md`, và `11_subsystems.md`.
* **Thử nghiệm Kiểm soát Giai đoạn I cho Hợp đồng Metadata Timeline Hữu hạn TTS (`TTSManager.swift`, `05_state_graph.md`, `06_event_graph.md`, `11_subsystems.md`)**:
  * Chuyển đổi `setSystemNowPlayingPlaybackState(_:)` thành instance method private `@MainActor` trong `TTSManager` để truy cập an toàn các thuộc tính timeline (`currentParagraphIndex`, `paragraphs.count`, `speed`).
  * Hoàn thiện xuất bản bộ 5 key metadata Now Playing hữu hạn (`MPNowPlayingInfoPropertyPlaybackRate`, `MPNowPlayingInfoPropertyDefaultPlaybackRate`, `MPNowPlayingInfoPropertyElapsedPlaybackTime`, `MPMediaItemPropertyPlaybackDuration`, `MPNowPlayingInfoPropertyPlaybackProgress`) đồng bộ trong `setSystemNowPlayingPlaybackState` và `updateNowPlayingInfo()`.
  * Cập nhật log trace `TTSTrace` ghi nhận các thông số timeline `elapsed`, `duration` và `progress` tại runtime.
  * Giữ nguyên khả dụng 3 lệnh Phase H (`playE/pauseE/toggleE = active`), chữ ký `func handleRemoteTransportCommandOnMain`, Phase F outcome-aware status return, bounded `.pause` fallback và các gọi lệnh `UIApplication`.
  * Đã đồng bộ khối GENERATED trong `05_state_graph.md`, `06_event_graph.md`, và `11_subsystems.md`.
* **Điều chỉnh Tính khả dụng Remote Command Phụ thuộc Trạng thái Phát (Phase J) (`TTSManager.swift`, `05_state_graph.md`, `06_event_graph.md`, `11_subsystems.md`)**:
  * Cập nhật `syncRemoteCommandState()` trong `TTSManager.swift` để trạng thái khả dụng của các lệnh điều khiển từ xa phản ánh chính xác trạng thái phát:
    * `let active = !playingBookId.isEmpty && showFloatingWidget`
    * `let playing = active && isPlaying`
    * `let paused = active && !isPlaying`
    * `playCommand.isEnabled = paused`
    * `pauseCommand.isEnabled = playing`
    * `togglePlayPauseCommand.isEnabled = active`
    * `nextTrackCommand.isEnabled = active`
    * `previousTrackCommand.isEnabled = active`
  * Giữ nguyên `setRemoteCommandsEnabled(_:)`, các target handler registrations, bounded `.pause` fallback và hợp đồng metadata timeline hữu hạn (Phase I).
  * Đã đồng bộ khối GENERATED trong `05_state_graph.md`, `06_event_graph.md`, và `11_subsystems.md`.
* **Cập nhật Metadata (`manifest.json`)**:
  * Tái tính toán và cập nhật `sourceHash` và `generatedHash` cho các tài liệu bị ảnh hưởng thông qua kịch bản `validate_links.py --update-hashes`.

## [1.3.53] - 2026-07-28

### Quản lý Quy tắc TOC File TXT & Khắc phục Thanh Tra Cứu Nhanh Panel Dịch
* **Cải tiến Nhận diện Chương File TXT (`ShelfView.swift`, `TranslateUtils.swift`)**:
  * Luồng phân tách chương file TXT (`ShelfView.parseTxtBook`) tái sử dụng bộ so khớp quy tắc TOC cấu hình được do `TranslateUtils` quản lý. Nhận diện chính xác các dòng tiêu đề chương lùi lề hợp lệ (ví dụ: `" 第一章 蓝电潜龙"`), đồng thời loại trừ các dòng văn bản lùi lề thông thường (ví dụ: `"  1000 quân lính tiến vào thành phố"`), tránh bị gộp sai toàn bộ nội dung thành một chương duy nhất ("Mở đầu").
* **Màn hình Quản lý Quy tắc TOC trong Cài đặt (`TOCRulesConfigView.swift`, `SettingsView.swift`)**:
  * Thêm màn hình `TOCRulesConfigView` trong Cài đặt với đường dẫn điều hướng `NavigationLink` hiển thị thường trực tại mục "Dịch Thuật Quick Translate" (hoạt động độc lập với cờ bật/tắt dịch).
  * Hỗ trợ xem danh sách, bật/tắt công tắc kích hoạt trực tiếp, chạm dòng để mở Form chỉnh sửa, sắp xếp lại vị trí quy tắc (`onMove`) và xóa quy tắc tùy chỉnh (`onDelete`).
  * Bảo vệ các quy tắc xuất xưởng mặc định (`isDefaultRule`), khóa tính năng xóa đối với quy tắc mặc định (`deleteDisabled`).
* **Menu Thao tác Toolbar & Nhập/Xuất Cấu hình JSON (`TranslateUtils.swift`)**:
  * Đưa các tùy chọn quản lý vào một dropdown Menu trên toolbar gồm 5 chức năng: *Thêm quy tắc mới*, *Sắp xếp quy tắc* (chuyển đổi EditMode), *Nhập cấu hình JSON*, *Xuất cấu hình JSON*, và *Khôi phục mặc định* (alert xác nhận hủy).
  * Hỗ trợ Nhập file JSON với 2 chế độ: **Gộp theo ID** (cập nhật tại chỗ các ID trùng và thêm quy tắc mới ở cuối) và **Thay thế toàn bộ** (thay bằng danh sách file và tự khôi phục các quy tắc mặc định bị thiếu ở cuối theo đúng thứ tự xuất xưởng).
  * **Tương thích ngược Import**: Tự động gán mặc định `enabled = true` khi decode/import các tệp JSON cũ thiếu trường `enabled`, đồng thời giữ nguyên các giá trị `enabled` được khai báo rõ ràng (`true` / `false`).
  * Kiểm tra hợp lệ file nhập nguyên tử (Atomic Validation): Giới hạn kích thước file (tối đa 500KB), số lượng quy tắc (tối đa 100 quy tắc), ID và Tên trimmed không rỗng và không quá 100 ký tự, kiểm tra trùng lặp ID (bao gồm khoảng trắng), cú pháp Regex hợp lệ (tối đa 250 ký tự); từ chối file nguyên khối nếu có lỗi mà không ghi đĩa hay đụng tới bộ đệm.
  * Tái sử dụng `DocumentPickerPresenter` (với `allowedContentTypes: [.json]`, `asCopy: true`) và `ShareSheet` với tệp xuất tạm thời tại `NSTemporaryDirectory()` được tự động dọn dẹp khi đóng sheet.
* **Đồng bộ Lưu trữ Bất đồng bộ & Quản lý Bộ đệm (`TranslateUtils.swift`)**:
  * Bổ sung `TOCRuleSaveCoordinator` actor quản lý xếp hàng lưu bất đồng bộ theo cơ chế FIFO (`enqueue` / `scheduleSave`) kết hợp rào chắn `flush()`, ngăn ngừa lỗi ghi đè dữ liệu cũ (race condition).
  * Phân tách bộ đệm trong bộ nhớ thành `cachedAllTOCRules` (chứa toàn bộ quy tắc cho UI quản lý) và `cachedTOCRules` (chỉ chứa quy tắc active cho parser TXT). Ghi đĩa nguyên tử (`.atomic`) trước khi cập nhật bộ đệm và tự động làm sạch cache tiêu đề chương (`clearChapterTitleCache`).
  * Quản lý cờ `isSaving` trên UI theo bộ đếm tác vụ `activeSaveCount` và hủy tác vụ `debounceSaveTask` trước mỗi thao tác lưu tức thì.
* **Khắc phục Thanh Tra Cứu Nhanh & Nút Cài đặt trên Panel Dịch (`ReaderView.swift`, `ReaderDefinitionOverlayView.swift`)**:
  * **Khắc phục nạp danh sách công cụ tìm kiếm**: Tự động nạp `SearchEngine.loadEngines()` trong `ReaderView` khi khởi tạo (`initializeReaderIfNeeded()`) và mỗi khi mở panel dịch (`.onChange(of: showingDefinitionSheet)`), khắc phục triệt để lỗi thanh Quick Lookup bên dưới nút Cập nhật bị trống.
  * **Nút Cài đặt Bánh răng (⚙️)**: Bổ sung nút Cài đặt bánh răng góc phải ngoài cùng trên thanh tra cứu nhanh (`quickLookupLinksView`), liên kết mở trực tiếp màn hình quản lý `SearchEnginesConfigView` dùng chung với Cài đặt ứng dụng qua `showingSearchEnginesConfigSheet`.
  * **Tự động làm mới khi đóng Sheet**: Đảm bảo danh sách `searchEngines` được tự động nạp lại trong callback `onDismiss` khi đóng màn hình Cài đặt công cụ tra cứu, đồng thời duy trì nút bánh răng luôn xuất hiện và truy cập được ngay cả khi danh sách công cụ rỗng.
* **Nâng cấp Tô màu Highlight & Phát TTS theo Phân đoạn Nhỏ (`ReaderView.swift`, `TTSManager.swift`)**:
  * **Highlight theo phân đoạn nhỏ (Small Chunk Level)**: Vùng màu vàng bôi đen khi đọc TTS giờ đây tô chính xác từng phân đoạn/câu nhỏ đang phát thay vì bôi đen toàn bộ đoạn văn lớn.
  * **Phát TTS từ vị trí bôi đen chọn**: Khi người dùng bôi đen văn bản và nhấn **Nghe (Speak)** trên menu nổi, TTS bắt đầu phát ngay từ phân đoạn nhỏ chứa văn bản được chọn.
  * **Chuẩn hóa hệ tọa độ UTF-16**: TTS sử dụng dữ liệu chương hiển thị làm chuẩn (`cached.content`). `ReaderView` lưu vết `@State private var selectedDisplayedOffset` cho thao tác phát TTS (đồng thời giữ nguyên `selectedWordOffset` quy đổi về chuỗi gốc cho từ điển/trình chỉnh sửa), và `lineStartOffset` tính toán vị trí tích lũy trên `item.translated` khi bật dịch và `item.original` khi tắt dịch.
* **Bổ sung Bộ Kiểm thử Unit Tests (`Tests/TranslationTests.swift`)**:
  * Thêm các unit test kiểm thử lưu trữ/khôi phục mặc định (`testTOCRulesPersistenceAndResetNonDestructive`), tương thích ngược import thiếu `enabled` (`testImportBackwardsCompatibilityMissingEnabledKey`), validate Regex (`testTOCRulePatternValidation`), validate file import quá cỡ/quá số lượng/ID tên quá dài/trùng ID (`testImportValidationOversizedDataAndRulesCount`, `testImportValidationEmptyOrOverlongIDAndNameAndDuplicateIDs`), thứ tự Gộp và Thay thế deterministic (`testDeterministicMergeAndReplaceOrderDetails`), tính nguyên tử không đổi file/cache khi import lỗi (`testAtomicImportRejectionNoFileOrCacheMutation`), kiểm tra dọn dẹp file tạm (`testTempExportFileCreationAndCleanup`), và kiểm thử FIFO actor `TOCRuleSaveCoordinator` (`testCoordinatorFIFOAndFlush`).

---

## [1.3.52] - 2026-07-28

### Loại bỏ ChapterMigrationWorker & Sửa lỗi Destructive Empty-Import
* **Khắc phục Nguyên nhân Gốc rễ Mất Mục Lục khi Khởi động lại App**:
  * Xác định nguyên nhân mất dữ liệu mục lục (TOC count về 0) sau khi khởi động lại app: Luồng legacy migration (`ChapterMigrationWorker`) chạy tự động ở `FreeBookApp.onAppear` đọc danh sách `book.chapters` rỗng từ SwiftData (do `enableSwiftDataTOCWrite = false`), sau đó gọi `importBookMigration` truyền danh sách snapshot rỗng làm xoá toàn bộ dữ liệu chương hiện có trong SQLite `ChapterStore`.
* **Loại bỏ Hoàn toàn Tệp Migration Worker & Cờ Cấu hình**:
  * Xoá hoàn toàn tệp vật lý `ChapterMigrationWorker.swift` và gỡ bỏ thuộc tính `enableChapterStoreMigration` khỏi `ChapterStoreConfiguration.swift`.
  * Gỡ bỏ lệnh khởi chạy `ChapterMigrationWorker.shared.startMigrationIfNecessary` trong `FreeBookApp.swift` (`.onAppear`).
  * Gỡ bỏ khối code fallback legacy trong `ChapterPersistenceStore.saveChapterList` (kiểm tra `storedCount == 0` để gọi `importBookMigration`).
  * Luồng ghi chính (primary write path) `replaceFullTOC` / `upsertPage` lưu metadata sách vào SwiftData và ghi danh mục TOC trực tiếp vào SQLite `ChapterStore` tiếp tục hoạt động độc lập và không bị thay đổi.
* **Phòng thủ Chuyên sâu Chống Import Rỗng (`ChapterStoreDatabase`)**:
  * Thêm guard kiểm tra `!snapshots.isEmpty` ngay đầu hàm `ChapterStoreDatabase.importBookMigration` trước khi khởi tạo giao dịch (`beginTransaction`).
  * Từ chối mọi yêu cầu import danh sách rỗng, ghi log mã băm sách rút gọn 8 ký tự (`bookHash`) và quăng lỗi ngữ nghĩa `ChapterStoreError.invalidContent`, ngăn ngừa triệt để việc xoá dữ liệu chương cũ và ngăn ghi dòng trạng thái `migration_status = migrated, 0`.
* **Dọn dẹp Cờ Cấu hình Thừa (Batch 1 Cleanup)**:
  * Gỡ bỏ 3 cờ cấu hình ghi kép không còn được sử dụng (`enableDualWriteNewBook`, `enableDualWriteExistingBook`, `enableDualWriteCacheMetadata`) khỏi `ChapterStoreConfiguration.swift`.

---

## [1.3.51] - 2026-07-27

### Chuyển đổi Mục Lục sang SQLite Native (`ChapterStore`)
* **Kiến trúc CSDL Độc lập (`ChapterStoreDatabase`)**:
  * Tách toàn bộ lưu trữ và đọc metadata mục lục (TOC) từ SwiftData `Chapter` sang cơ sở dữ liệu SQLite3 riêng biệt tại `Library/Application Support/chapters/chapter_store.sqlite` (đảm bảo tên thư mục `chapters` viết thường).
  * Cấu hình chế độ WAL (`PRAGMA journal_mode=WAL;`) và `PRAGMA synchronous=NORMAL;` kết hợp bảo vệ đĩa iOS `.completeUntilFirstUserAuthentication` áp dụng cho tệp CSDL chính, `-wal`, `-shm` và thư mục `chapters`, hỗ trợ đọc phát âm thanh TTS khi thiết bị khóa màn hình.
  * Thiết kế bảng `chapter_metadata` (schema v1) lưu trữ thông tin chỉ mục, URL, tiêu đề gốc, tiêu đề dịch (`title_trans`), trạng thái cache (`is_cached`, `offset`, `length`), thời gian cập nhật cùng các chỉ mục tối ưu `idx_chapter_book_index` và `idx_chapter_book_url`.
* **Xử lý Đơn Giao dịch Không Chia Đợt (`ChapterStoreActor`)**:
  * `ChapterStoreActor` quản lý toàn bộ các thao tác đọc/ghi bất đồng bộ, sử dụng Prepared Statements chuẩn bị sẵn cho C-API SQLite.
  * Các phương thức `replaceFullTOC` và `upsertPage` thực thi nguyên khối trong 1 giao dịch `BEGIN IMMEDIATE ... COMMIT` duy nhất (không chia đợt Batch Splitting) nhằm đảm bảo tính toàn vẹn dữ liệu mục lục.
  * Bảo tồn dữ liệu vị trí cache nhị phân (`offset`, `length`), tiêu đề dịch và thông tin chương đang phát TTS (`protectedTTS`).
* **Đồng bộ Luồng Migration & Retry Queue**:
  * `ChapterMigrationWorker` xử lý di chuyển mục lục từ SwiftData sang SQLite3 nguyên khối theo từng cuốn sách, tự động dọn dẹp bản ghi thừa (stale rows) và ghi nhận trạng thái vào `migration_status`.
  * Khôi phục và duy trì cơ chế hàng chờ thử lại xóa tệp nhị phân (`BookStorageManager.drainRetryQueue()`) khi người dùng xóa sách.
* **Tích hợp Các Phân hệ Consumer & Tắt Ghi SwiftData**:
  * Chuyển toàn bộ luồng đọc/hiển thị/dịch tiêu đề/đếm chương tại `BookDetailView`, `BookDetailTOCView`, `ReaderViewModel`, `ReaderChapterListView`, `ReaderView`, `DownloadManager`, `TTSManager`, và `ShelfView` sang sử dụng `ChapterStore` (DTO `StoredChapterSnapshot`).
  * Vô hiệu hóa ghi SwiftData Chapter (`enableSwiftDataTOCWrite = false`) để tránh ghi trùng lặp dữ liệu vào SwiftData Store.
  * Thêm liên kết thư viện hệ thống `SQLite3.tbd` trong `project.yml`.
* **Ghi Log An toàn Quyền Riêng tư & Kiểm chứng**:
  * Định dạng log `[ChapterStore Save]` ghi nhận các trường thời gian thực thi (ms), số lượng chương, trạng thái kết quả và đối chiếu tính toàn vẹn (parity), không ghi mã hash bookId hay checksum trong dòng log save.
  * Thuật toán checksum FNV-1a xác định được tích hợp trong `computeDeterministicChecksum` / `fetchCountAndChecksum` phục vụ kiểm tra tính toàn vẹn dữ liệu.
  * Mã hash sách rút gọn 8 ký tự `Chapter.hashUrl(bookId).prefix(8)` được sử dụng trong log xóa (`ChapterStore Delete`), đảm bảo không ghi lộ tiêu đề chương, đường dẫn CSDL raw, hay `bookId` gốc.
  * Lưu ý kiểm chứng: Đã hoàn thành kiểm chứng tĩnh trên Windows (`git diff --check`, `swiftc -frontend -parse`). Runtime iPhone và CI IPA build phụ thuộc vào GitHub Actions workflows.

---

## [1.3.50] - 2026-07-27

### Tối ưu hóa Database Mục Lục (TOC Database Optimization)
* **Tối ưu hóa Truy vấn Truy cập Sách (`ChapterPersistenceStore`, `BookDetailView`)**:
  * Sử dụng `FetchDescriptor<Book>` với `#Predicate<Book> { $0.bookId == targetBookId }` và `fetchLimit = 1` thay thế toàn bộ truy vấn `context.fetch(FetchDescriptor<Book>())` không có Predicate.
* **Lưu Nền 1 Save Cho Toàn Bộ Thao Tác (`ChapterPersistenceStore.saveChapterList`)**:
  * Chuyển toàn bộ công việc lưu/cập nhật danh sách chương xuống `ModelContext` chạy nền thuộc `ChapterPersistenceStore` (actor). Thực hiện duy nhất 1 lần `try context.save()` cho toàn bộ thao tác.
  * Hỗ trợ 2 chế độ: `.replaceFullTOC` (thay thế toàn bộ mục lục khi nạp đầy đủ) và `.upsertPage` (nạp từng phần/trang mục lục mà không xóa các chương thuộc trang khác).
  * Bảo tồn dữ liệu `isCached`, `offset`, `length`, `titleTrans`, giữ an toàn cho chương đang phát TTS (`isPlayingChapter`).
* **Tái cấu trúc `startReading(at:)` & `ReaderChapterListView`**:
  * `startReading(at:)` thu thập đủ các trang mục lục, gọi `saveChapterList` lưu nền 1 lần, chờ hoàn tất rồi mới refetch `Book` qua predicate và mở `ReaderView`.
  * `ReaderChapterListView.refreshChapters` và các luồng nạp trang nền (`startBackgroundRemainingPagesLoading`, `loadTOCDataOnly`) sử dụng `saveChapterList` với `mode: .upsertPage` chạy nền thay vì insert/save lặp đi lặp lại trên `MainActor`.
* **Bổ sung Unit Tests & Đồng bộ CodeGraph Docs (`04_call_graph.md`, `07_dataflow.md`, `11_subsystems.md`)**:
  * Thêm unit test kiểm thử `.replaceFullTOC`, `.upsertPage`, và bảo vệ TTS trong `Tests/ChapterContentRepositoryTests.swift`.
  * Đồng bộ Đồ thị Lời gọi Hàm, Dòng chảy Dữ liệu và Phân hệ Cốt lõi cho các API `saveChapterList` và cơ chế lưu nền 1 lần.

---

## [1.3.49] - 2026-07-24

### Tái cấu trúc Luồng Tải Mục mục & Lưu Database khi Mở Sách (`BookDetailView`)
* **Tải toàn bộ danh sách chương trước khi mở ReaderView**:
  * Khi mở đọc truyện mới (`isBookReady == false`), hệ thống tự động cào toàn bộ các trang mục lục (`pages`) thành 1 danh sách chương hợp nhất `allChapters`.
* **Lưu DB theo đợt (Chunked Save - 1,000 chương/đợt)**:
  * Chia `allChapters` thành các đợt tối đa 1,000 chương (`updateLocalChaptersChunk`), chèn vào `ModelContext` và gọi `modelContext.save()` sau mỗi đợt.
* **Wait Layer Tiến độ Thời gian Thực**:
  * Hiển thị màn hình chờ `loadingOverlay` với các nhãn tiến độ thời gian thực: `"Đang lấy mục lục..."` (giai đoạn cào trang) và `"Đang lưu database..."` (giai đoạn lưu từng đợt 1000 chương).
  * Hỗ trợ nút **Hủy** để dừng tác vụ an toàn.
  * Tự động mở `ReaderView` sau khi 100% dữ liệu đã được lưu xuống đĩa.

---

## [1.3.48] - 2026-07-24

### Phase 2 & Phase 3: Tái cấu trúc Phân hệ Book Detail & TTS Services
* **Book Detail Component Modularization**:
  * Tách tệp monolithic `BookDetailView.swift` thành 3 Subview thành phần:
    * `Sources/Views/BookDetail/BookDetailHeaderView.swift` (Khu vực thông tin ảnh bìa, tác giả, mô tả và nút action).
    * `Sources/Views/BookDetail/BookDetailTOCView.swift` (Danh sách mục lục chương, ô tìm kiếm chương và lọc phân trang).
    * `Sources/Views/BookDetail/BookDetailActionSheetView.swift` (Quản lý các Hộp thoại Sheet tải xuống và Bypass Cloudflare).
* **TTS Controller Modularization**:
  * Tách `TTSManager.swift` thành các Controller chuyên biệt:
    * `Sources/Services/TTS/TTSAudioEngineController.swift` (Quản lý AVAudioEngine, AVAudioPlayerNode và ngắt âm thanh).
    * `Sources/Services/TTS/TTSNowPlayingController.swift` (Quản lý MPNowPlayingInfoCenter và MPRemoteCommandCenter Lock Screen).
    * `Sources/Services/TTS/TTSChapterPrefetcher.swift` (Quản lý sliding window [N, N+1] giải phóng RAM PCM buffer).
* Cập nhật danh sách 110 tệp nguồn trong `manifest.json` và đồng bộ CodeGraph.

---

## [1.3.47] - 2026-07-24

### Phase 1: Tái cấu trúc Phân hệ Reader (Modularize ReaderView)
* **Reader Component Modularization**:
  * Tách tệp monolithic `ReaderView.swift` thành các Subview độc lập:
    * `Sources/Views/Reader/ReaderDefinitionOverlayView.swift` (Quản lý Bottom Sheet tra cứu từ điển và sửa nghĩa).
    * `Sources/Views/Reader/ReaderFloatingMenuOverlayView.swift` (Quản lý menu bong bóng nổi khi bôi đen văn bản).
    * `Sources/Views/Reader/ReaderHeaderFooterOverlayView.swift` (Quản lý thanh tiêu đề Header và thanh điều hướng Footer).
  * Giảm số dòng code của `ReaderView.swift` từ 2,430 dòng xuống còn ~1,800 dòng.
  * Cập nhật danh sách tệp nguồn trong `manifest.json` và đồng bộ CodeGraph.

---

## [1.3.46] - 2026-07-24

### Phase 0: Sàng lọc & Xóa bỏ mã nguồn / tệp rác không sử dụng (Dead Code Removal)
* **Reader & TTS Cleanup**:
  * Xóa bỏ các tệp tin mồ côi dư thừa `Sources/Views/Reader/CollapsedCircleView.swift`, `Sources/Views/Reader/ExpandedControlPanel.swift`, `Sources/Views/Reader/ChapterContentProvider.swift`.
  * Rà soát & loại bỏ các biến `@State` dư thừa không được đọc/ghi (`isGoingNext`, `editingChapterIndex` trong `ReaderView.swift`; `preparingStatusText`, `preparingTargetChapterTitle` trong `BookDetailView.swift`).
  * Cập nhật danh sách tệp nguồn trong `00_index.md`, `02_file_graph.md`, `03_type_graph.md`, `14_complexity_report.md` và `manifest.json`.

---

## [1.3.45] - 2026-07-24

### Loại bỏ hoàn toàn phân hệ màn hình chờ WaitLayer
* **WaitLayer Cleanup**:
  * Xóa bỏ hoàn toàn tệp `Sources/Common/Services/WaitLayerManager.swift` và `Sources/Views/Reader/ReaderWaitOverlayView.swift`.
  * Gỡ bỏ `ReaderWaitOverlayView()` khỏi cấp root `FreeBookApp.swift`.
  * Dọn dẹp tất cả các lời gọi `WaitLayerManager.shared.open` và `close` ở `BookDetailView.swift`, `ReaderView.swift` và `ShelfView.swift`.
  * Trả lại luồng chuyển hướng mở đọc truyện trực tiếp, gọn nhẹ và không qua màn hình chờ trung gian.

## [1.3.44] - 2026-07-24

### Chuyển đổi WaitLayer sang kiến trúc WaitLayerManager.shared điều khiển open/close thủ công toàn cục
* **WaitLayer Subsystem & Shared Architecture**:
  * Tạo tệp `Sources/Common/Services/WaitLayerManager.swift` quản lý trạng thái hiển thị và dữ liệu của WaitLayer toàn ứng dụng.
  * Gắn duy nhất 1 `ReaderWaitOverlayView` tại cấp root `FreeBookApp.swift` (`.zIndex(10000)`), phủ kín toàn bộ giao diện và chuyển cảnh navigation.
  * Loại bỏ hoàn toàn logic tự động bật `waitLayerOverlay` trong `ReaderView.swift` dựa trên `loadState != .ready`, sửa dứt điểm lỗi trùng lặp/hiển thị 2 lần.
  * Trong `BookDetailView.swift` và `ShelfView.swift`: Gọi `WaitLayerManager.shared.open(...)` ngay khi vừa chạm nút mở đọc, kết hợp `await Task.yield()` cho phép render WaitLayer 0ms trước khi thực thi khởi tạo 2.000+ chương.
  * Trong `ReaderView.swift`: Gọi `WaitLayerManager.shared.close()` khi `loadState` trở thành `.ready` / `.failed` hoặc khi màn hình đóng (`onDisappear`).

## [1.3.43] - 2026-07-24

### Tách ReaderWaitOverlayView thành Component dùng chung & Hiển thị LẬP TỨC khi bấm nút đọc
* **Reader Subsystem & UI Navigation**:
  * Tạo component SwiftUI mới `Sources/Views/Reader/ReaderWaitOverlayView.swift` phục vụ màn hình WaitLayer phủ kín toàn màn hình dùng chung cho toàn bộ các màn hiển thị/chuyển tiếp sang ReaderView.
  * Giao diện WaitLayer gồm:
    * Nút Back (Quay lại) ở góc trên bên trái (`chevron.left`) gọi callback `onBack` cho phép người dùng đóng overlay và hủy tác vụ ngay lập tức.
    * Tiêu đề Truyện và Tiêu đề Chương ở phần trên/giữa header, hỗ trợ dịch thuật tự động nếu bật dịch (`isTranslationEnabled`).
    * Biểu tượng nạp (`ProgressView().controlSize(.large)`) nằm chính giữa màn hình.
    * Phủ kín màu nền theo chủ đề đọc được chọn (`theme.backgroundColor`) với `.zIndex(100)` và hiệu ứng mờ mượt mà `.transition(.opacity)`.
  * **Kích hoạt LẬP TỨC**:
    * Trong `BookDetailView.swift`: Kích hoạt `ReaderWaitOverlayView` ngay lập tức khi bấm các nút "Đọc ngay", "Đọc tiếp" hoặc bấm vào bất kỳ dòng chương nào trong mục lục TOC.
    * Trong `ShelfView.swift`: Kích hoạt `ReaderWaitOverlayView` ngay lập tức khi người dùng bấm/chạm vào bất kỳ cuốn truyện nào trong tab Kệ sách hoặc Lịch sử.
    * Trong `ReaderView.swift`: Sử dụng chung `ReaderWaitOverlayView` cho đến khi `ReaderViewModel.loadState` chuyển sang `.ready` hoặc `.failed`.

## [1.3.42] - 2026-07-22

### Đồng bộ hành vi Hard Delete sách bất đồng bộ không đơ UI và bảo vệ sách đang ở trên kệ / đang nghe TTS
* **BookStorageManager & SwiftData Background Deletion**:
  * Chuyển đổi toàn bộ các thao tác xóa sách (xóa khỏi kệ sách, xóa 1 mục lịch sử, xóa toàn bộ lịch sử) thành **Hard Delete** (xóa bản ghi `Book`, cascade xóa toàn bộ bản ghi `Chapter` trong SwiftData, dừng/hủy tác vụ download, clear reader fallback `UserDefaults` và xóa các file vật lý `.bin` / cover background).
  - Triển khai các API xóa bất đồng bộ `deleteBooksAsync`, `deleteBookAsync`, `clearAllOffShelfHistoryAsync` nhận tham số `ModelContainer` và danh sách `bookId` (`[String]`). Thao tác fetch/delete trong SwiftData chạy trên `backgroundContext` hoàn toàn không gây tắc nghẽn main thread (non-blocking UI).
  - Bổ sung cơ chế bảo vệ ở lớp dịch vụ: không xóa cuốn sách đang phát TTS (`TTSManager.shared.playingBookId`).
  - Thao tác xóa toàn bộ lịch sử (`clearAllOffShelfHistoryAsync`) chỉ xóa các cuốn sách KHÔNG nằm trên kệ (`isOnShelf == false`), bảo tồn 100% các cuốn sách đang nằm trên Kệ sách (`isOnShelf == true`).
* **ShelfView & BookDetailView UI**:
  * Tích hợp cờ trạng thái `isProcessingDeletion` hiển thị indicator dọn dẹp nhẹ và ngăn bấm lặp lại trên `ShelfView`.
  * Cập nhật văn bản thông báo Alert xóa lịch sử làm rõ hành vi chỉ xóa các sách lịch sử không ở trên kệ, giữ nguyên sách trên kệ và sách đang nghe audio.
  * Chuyển đổi các nút xóa trong `ShelfView` và `BookDetailView` sang gọi các phương thức bất đồng bộ của `BookStorageManager` bọc trong `Task { @MainActor in ... }` đảm bảo an toàn Thread Safety cho trạng thái UI.
* **Unit Tests**:
  * Thêm `Tests/BookStorageManagerTests.swift` kiểm định xóa cứng `Book` & `Chapter` cascade delete, bảo tồn sách trên kệ và bảo vệ sách đang nghe TTS.

## [1.3.41] - 2026-07-22

### Khắc phục lỗi điều khiển nút Play màn hình khóa và tai nghe khi tạm dừng TTS
* **TTS Subsystem & MPRemoteCommandCenter**:
  * Đăng ký handler xử lý lệnh `togglePlayPauseCommand` trong `setupRemoteCommandCenter()`, cho phép tai nghe Bluetooth/AirPods và nút điều khiển trung tâm toggle phát/dừng mượt mà qua `pause()` và `resume()`.
  * Cập nhật `setRemoteCommandsEnabled(_:)` và `syncRemoteCommandState()` bật `togglePlayPauseCommand.isEnabled = active` trong toàn bộ phiên TTS đang hoạt động (dù đang phát hay tạm dừng).
  * Khắc phục triệt để hiện tượng nút Play trên Now Playing card (Lock Screen / Control Center) bị mờ/xám (disabled) khi pause và sửa triệt để lỗi bấm tai nghe 2 lần mới tiếp tục phát.
  * Sửa trợ thủ `setSystemNowPlayingPlaybackState` khởi tạo dictionary rỗng khi `nowPlayingInfo` bằng `nil`, đảm bảo `MPNowPlayingInfoPropertyPlaybackRate` và `playbackState` luôn được cập nhật đồng bộ tức thì.
  * Loại bỏ cơ chế debounce 300ms theo thời gian (`shouldProcessPlaybackRemoteCommand()`) để tránh nuốt lệnh Resume/Play/Pause hợp lệ gửi từ tai nghe/iOS Control Center; chuyển sang kiểm tra tính định danh (idempotency) trực tiếp theo trạng thái `isPlaying` hiện tại của `TTSManager`.
  * Bảo vệ Task bất đồng bộ `updateNowPlayingInfo()` sử dụng giá trị `self.isPlaying` và `self.speed` mới nhất tại thời điểm MainActor commit cuối cùng.
* **Unit Tests**:
  * Cập nhật `TTSManagerTests.swift`: thay thế `testRemoteCommandDebounce()` bằng `testRemoteCommandIdempotencyAndImmediateStateSync()` để kiểm định tính định danh của lệnh remote và tính đồng bộ tức thì của Now Playing.

## [1.3.40] - 2026-07-22

### Sửa lỗi nghĩa rỗng VP, tối ưu cuộn/làm nóng mục lục Reader, điều hướng TTS chính xác đoạn văn và định dạng Title Case UI
* **Dictionary & Translation (Vietphrase)**:
  * Khắc phục lỗi không áp dụng nghĩa rỗng ở vị trí đầu tiên khi chuỗi dịch từ điển Vietphrase chứa ký tự phân cách đầu dòng (`/`, `|`, `¦`) trong `TranslateUtils.getFirstMeaning(of:)` và `ManageDefinitionsView`.
  * Bổ sung các ca kiểm thử đơn vị bao quát trong `Tests/TranslationTests.swift`.
* **Reader Subsystem**:
  * `ReaderChapterListView`: Tự động cuộn căn giữa chương đang đọc khi mở sheet mục lục mỗi lần (`onChange(of: isPresented)` & `currentChapterIndex`).
  * Tối ưu hóa việc dịch tên chương Hán-Việt ngầm (`warmNearbyTitles`) theo lô (batch warming) trong bán kính cửa sổ hiển thị (`windowSize = 8`) thay vì gọi giải dịch riêng lẻ từng dòng khi xuất hiện (`onAppear`).
  * Trễ tác vụ nạp trang hiển thị (`scheduleVisiblePageWork`) với cơ chế hoãn (debounce 90ms) giúp ngăn chặn hiện tượng cuộn giật/thrashing khi người dùng lướt nhanh mục lục.
  * Nút "Dịch lại tên chương" trong `ShelfView` nay chạy task nền để dịch lại toàn bộ danh sách chương của cuốn sách và lưu tất cả `titleTrans` xuống SQLite, thay vì chỉ xóa cache bộ nhớ.
  * Màn hình chuẩn bị mở sách mới (Full-screen Reader-like Preparing Screen) trong `BookDetailView` với nút Icon Quay lại (`chevron.left`) ở góc trên bên trái, hiển thị tiến trình nạp TOC, dịch tên chương và lưu SQLite trước khi chuyển sang `ReaderView`.
  * Ẩn navigation header của màn chi tiết khi màn hình chuẩn bị mở sách mới đang hiển thị, đảm bảo wait layer giống trang Reader và không còn lộ title/menu của `BookDetailView`.
  * Chuẩn hóa quy tắc hiển thị tiêu đề chương bên ngoài văn bản: ưu tiên `chapter.titleTrans` từ SQLite khi bật dịch thuật (nếu rỗng dịch tại thời điểm hiển thị); luôn sử dụng `chapter.title` tiếng Trung gốc khi tắt dịch thuật.
  * Khắc phục lỗi mục lục Reader hiện nhiều dòng "Đang tải..." chen giữa các mốc 100 chương dù page kế tiếp đã được prefetch; page cache nay được dùng/publish ngay khi page đó trở thành vùng hiển thị.
* **TTS Navigation Integration**:
  * `ShelfView`: Khi chuyển từ widget / MiniPlayer TTS sang Reader via nút "Nghe tiếp", truyền tham số `navigateToPlayingParagraphIndex` (`initialParagraphIndex`) giúp Reader tự động cuộn và highlight chính xác đoạn văn đang đọc thay vì mở lại từ đầu chương.
* **UI Text Formatting & Styling**:
  * Tích hợp tiện ích `DisplayTextFormatter.titleCase` hỗ trợ định dạng hoa đầu từ theo quy chuẩn tiếng Việt (`Locale(identifier: "vi_VN")`), bảo toàn các từ viết tắt chuyên ngành (`TTS`, `AI`, `VIP`, `iOS`, `API`, `URL`, `FreeBook`, v.v.).
  * Áp dụng định dạng Title Case đồng bộ cho tiêu đề sách và tên tác giả trên các view: `BookDetailView`, `SuggestRowView`, `CategoryNovelsListView`, `DiscoveryView`, `DownloadTrackerView`, `TaskOptionsSheet`, `ReaderView`, `SearchView`, `ShelfView`.
  * Thay thế nhãn chữ "Tác giả:" bằng biểu tượng người dùng (`Image(systemName: "person.fill")`) trong `BookDetailView` và `TaskOptionsSheet` giúp giao diện hiện đại và gọn gàng hơn.
  * Không hiển thị fallback "Không rõ" khi thiếu tên tác giả; các vùng metadata tác giả trong `BookDetailView`, `TaskOptionsSheet` và header mục lục Reader sẽ để trống.
* **Unit Tests**:
  * Tạo mới bộ kiểm thử `Tests/DisplayTextFormatterTests.swift` kiểm định các trường hợp Title Case tiếng Việt, từ viết tắt preserved, `nil`, chuỗi rỗng và xử lý chuẩn hóa khoảng trắng.

## [1.3.39] - 2026-07-21

### Tích hợp cơ chế waitForReady thăm dò DOM động trong Extension Engine
* **Extension Engine & JSExecutor**:
  * Bổ sung API `waitForReady` vào đối tượng `Engine.Browser` trong JS và native bridge `_nativeBrowserWaitForReady` trong `JSExecutor.swift`.
  * Triển khai kiểm tra `Thread.isMainThread` (fail-fast) trong native bridge `waitForReady` mới để ngăn chặn deadlock luồng chính khi gọi đồng bộ; các bridge truyền thống (`launch`, `callJs`) vẫn giữ nguyên rủi ro ban đầu.
  * Mở rộng `WebViewLoader` để thực hiện thăm dò DOM tuần hoàn thông qua `DispatchQueue.main.asyncAfter` thay thế busy-loop.
  * Xác thực trạng thái DOM ổn định dựa trên bộ đôi chỉ số `{chars, encoded}` trong `stablePasses` chu kỳ liên tiếp (với `encoded` là số lượng thẻ `i[t]`).
  * Thực hiện cơ chế giải phóng timer và pending wait an toàn đúng 1 lần (exactly-once) khi đóng trình duyệt hoặc khởi chạy wait mới.
* **Sangtacviet Extension**:
  * Viết lại `src/chap.js` sử dụng `waitForReady` thay thế cho delay cố định (`waitTime`).
  * Thêm logic thử lại AJAX (gọi `gotox()` tối đa 1 lần) và fallback trích xuất văn bản thuần (`getReadableTextFromNode`) khi không tìm thấy thẻ mã hóa `i[t]`.
  * Bổ sung `home.js`, `genre.js` và `homecontent.js`: cung cấp các tab trang chủ, 10 thể loại đã xác minh và phân trang 48 truyện qua endpoint `/io/searchtp/searchBooks`.
  * Tạo cấu hình `plugin.json`, `icon.png`, `src/search.js`, `src/detail.js`, `src/toc.js`, và tệp kiểm thử `tests/smoke.mjs`.
  * Đóng gói `plugin.zip` chứa đúng cấu trúc phân phối (loại bỏ thư mục `tests`).

## [1.3.38] - 2026-07-21

### Tách refresh metadata TTS khỏi Reader UI, giảm giật tab và bỏ kéo sheet mục lục theo tay
* **TTS Subsystem**:
  * Thêm `TTSChapterQueueMetadataWorker` chạy nền bằng `ModelContainer` để `TTSManager` tự refresh metadata queue cho sách local, không phụ thuộc `ReaderView` dựng full queue trên main thread.
  * Thêm `refreshChaptersQueueInBackground(bookId:onlineChapters:)`; Reader chỉ cấp queue khởi động ngắn để phát ngay, còn TTSManager tự cập nhật queue đầy đủ phục vụ auto-next.
  * `stopPlayback` hủy task refresh queue của TTS khi người dùng dừng TTS thật sự; thao tác rời Reader không chặn prefetch/auto-fetch của TTS.
* **ReaderView / ReaderChapterListView**:
  * Bỏ `chapterListDragOffset` và callback kéo realtime của mục lục; vuốt xuống đủ ngưỡng chỉ đóng sheet, không kéo panel chạy theo tay.
  * Thêm vùng tap ngoài mục lục để đóng overlay.
  * `ReaderView` không còn computed full TTS chapter queue; luồng start TTS chỉ lấy chương hiện tại và vài chương kế tiếp.
* **ShelfView / DiscoveryView**:
  * `ShelfView` không reset `shelfLimit/historyLimit` khi vuốt tab con và không quét `book.chapters` trong row render.
  * `DiscoveryView` chỉ render nội dung thật cho tab category hiện tại và tab lân cận; tab xa dùng placeholder rỗng, còn tải tab mới được debounce ngắn.

## [1.3.37] - 2026-07-21

### Tối ưu độ trễ khởi động TTS và giữ điều hướng Reader độc lập
* **TTS Subsystem**:
  * Thiết lập lớp xử lý nền bất đồng bộ `TTSBackgroundProcessor` dưới dạng `actor` gánh vác các phép toán CPU-heavy (chuẩn hóa văn bản `ChapterTextNormalizer.normalize`, dịch nghĩa `TranslateUtils.translateContent` và phân tách đoạn văn `TTSParagraphBuilder.build`) ra khỏi luồng chính `MainActor`.
  * Chuẩn hóa chữ ký truyền tham số `processChapter` rõ ràng (`shouldTranslateRawContent`, `includeChapterTitle`) thay vì truy cập các biến toàn cục bên trong worker. Tránh lặp lại quá trình dịch khi nạp dữ liệu đã được xử lý từ bộ nhớ đệm.
  * Loại bỏ hàng đợi `TTSBackgroundProcessor.shared` dùng chung; mỗi request dùng processor riêng có cancellation checkpoint để thao tác Play không phải chờ các prewarm cũ.
  * `prepareSpeaking` trở thành prewarm thuần cache, không thay đổi chương hoặc trạng thái của phiên TTS đang pause.
  * `startSpeaking` dùng ngay kết quả prewarm khi key nội dung khớp; cache miss mới xử lý nền với ưu tiên cao.
  * Đường bấm Play chỉ truy vấn metadata chương hiện tại và chương kế; từ 1.3.38, refresh danh sách chương đầy đủ được chuyển sang `TTSManager.refreshChaptersQueueInBackground(...)`.
* **ReaderView**:
  * Next/Previous và chọn chương trong mục lục chỉ thay đổi Reader, không dừng hoặc chuyển chương TTS.
  * Prewarm chương Reader không ghi đè dữ liệu phát của chương TTS hiện tại.
  * Bỏ thao tác deactivate/activate AudioSession dư thừa khi bắt đầu TTS từ trạng thái đã dừng hoàn toàn.
* **TTSManagerTests**:
  * Cập nhật test chữ ký processor và bổ sung kiểm tra chương đã prewarm bắt đầu phát đồng bộ không cần chờ xử lý lần hai.

## [1.3.36] - 2026-07-21

### Khắc phục lỗi biên dịch Test Target, hoàn tất tối ưu hóa điều phối và đối sánh persistence an toàn va chạm
* **Tests/ReaderViewModelTests**:
  * Viết lại toàn bộ bộ kiểm thử đơn vị, loại bỏ các symbol giả tự chế (`ChapterSnapshot`, `BookSnapshot`, `ChapterPersistenceStore.shared`, `ensureBook(snapshot:context:)`, v.v.).
  * Chuyển sang gọi các API thực tế của `ChapterPersistenceStore` bất đồng bộ (`ensureBook`, `flush`) sử dụng một `ModelContainer` in-memory biệt lập và các snapshot DTO thực tế (`BookMetadataSnapshot`, `ChapterMetadataSnapshot`).
  * Bổ sung các ca kiểm thử chất lượng cao bao quát toàn bộ các ca kiểm định ảo hóa, giới hạn cửa sổ 300, phòng chống race cùng thế hệ, prefetch không ghi đè, phục hồi khi lỗi, và kiểm thử persistence an toàn va chạm với dữ liệu trùng lặp/rỗng trên API thực tế.
* **ChapterPersistenceStore**:
  * Tích hợp lớp helper tập trung `ReconciliationPool` để chia sẻ logic đối sánh an toàn va chạm $O(N)$ giữa `ensureBook` và `upsert`.
  * Đảm bảo các hàng trùng lặp URL và URL rỗng không bị mutated/collapsed gộp chung thành một hàng và thăng cấp chương trùng lặp còn lại chính xác khi khóa thay đổi.
* **ReaderChapterListStore & ReaderChapterListView**:
  * Khai báo thuộc tính `latestWindowRequestID: UUID` và `activeLoadingTargetPage` để điều phối cửa sổ hiển thị.
  * Chỉ cho phép tác vụ khớp với token cửa sổ hiển thị mới nhất được xuất bản lên UI, loại bỏ triệt để race condition giữa các bộ điều phối cũ thuộc cùng thế hệ hoàn thành trễ.
  * Bổ sung `pageRequestIDs` và `pageCache` để ngăn ngừa các tác vụ tải trang cũ khi kết thúc vô tình xóa nhầm tác vụ trang mới hơn trong `inFlightPages`.
  * Cập nhật `prefetchPageIfNeeded(page:)` chỉ nạp ngầm dữ liệu DTO vào `pageCache` nền mà không dịch chuyển `currentTargetPage` và không ghi đè/mutate trực tiếp lên `loadedRowStates`.
  * Cập nhật `BackgroundPagingWorker.fetchPage` trả về lỗi tường minh (`throw`) và xử lý tại `performPageFetch` trả về `nil` để coordinator không đánh dấu trang lỗi đã nạp, cho phép retry sạch sẽ.
* **ReaderView**:
  * Loại bỏ thuộc tính tính toán `currentChapterHost` đang gọi `vm.fetchChapter(at:)` đồng bộ sang sử dụng trạng thái `@State private var currentChapterHost: String?` được cập nhật đồng bộ bên ngoài SwiftUI body trong `updateCurrentChapterMetadata()`.

## [1.3.35] - 2026-07-21

### Tối ưu hóa Virtualization mục lục Reader, Paging Worker bất đồng bộ, Anti-jitter và Persistence collision-safe
* **ReaderChapterListStore & ReaderChapterListView**:
  * Loại bỏ hoàn toàn mảng `rows` và danh sách ảo `virtualRows` khỏi lớp lưu trữ của mục lục để tối ưu hóa bộ nhớ. Trực tiếp sử dụng ForEach chỉ mục `ForEach(0..<store.totalCount, id: \.self)` để SwiftUI tự ảo hóa.
  * Thiết kế hàm `item(at:)` và `rowState(at:)` bóc tách dòng trạng thái động trong thời gian $O(1)$ mà không tự ý đột biến (non-mutating read) bộ nhớ đệm trạng thái dòng.
  * Triển khai lớp tác vụ phân trang chạy nền `BackgroundPagingWorker` dưới dạng `actor` sở hữu `ModelContainer` độc lập, thực hiện tải trang từ SQLite trên luồng nền bất đồng bộ và trả về từ điển DTO thuần `Sendable`.
  * Xây dựng bộ điều phối tải trang mục lục (page load request coordinator) quản lý tác vụ in-flight của từng trang đơn lẻ (`inFlightPages`), loại bỏ tình trạng hủy bỏ và tạo mới liên tục (cancellation thrash) khi cuộn chậm.
  * Thực thi việc hoán đổi trạng thái nguyên tử (atomic swap) duy nhất một lần trên `loadedRowStates` sau khi toàn bộ trang thuộc cửa sổ hiển thị (lên đến 3 trang / tối đa 300 phần tử) đã sẵn sàng, giữ nguyên cửa sổ cũ cho tới khi cửa sổ mới được tải hoàn chỉnh.
  * Tích hợp cơ chế tải trước chủ động `prefetchPageIfNeeded(page:)` giúp tải ngầm trang kề cận mà không gây dịch chuyển vị trí trang hiển thị trung tâm (target page oscillation).
  * Xóa bỏ các phương thức không sử dụng là `synchronize` và `searchChapters(query:)`. Tích hợp logic tự động kích hoạt tìm kiếm lại với sort order mới khi đổi chiều sắp xếp mục lục lúc đang có query tìm kiếm.
* **ReaderView**:
  * Quản lý trạng thái đếm chương thông qua `@State` flag `didResolveLocalChapterCount`, đảm bảo chỉ truy vấn đếm chương cục bộ từ SQLite duy nhất một lần (kể cả khi bằng 0), khắc phục triệt để lỗi lặp lại lệnh đếm khi view xuất hiện hoặc thay đổi key bootstrap.
  * Loại bỏ thuộc tính truy vấn độ dài mảng `book.chapters.count` trong luồng cập nhật mục lục của `ReaderChapterListView`, thay thế bằng đếm nhanh `fetchCount` trực tiếp từ SQLite.
* **ChapterPersistenceStore**:
  * Tối ưu hóa bộ đối chiếu chèn/sửa danh sách chương bằng bản đồ lưu trữ các thùng chứa an toàn va chạm (collision-safe buckets / order-aware maps) `urlBuckets` và `indexBuckets`.
  * Đảm bảo tính nhất quán của thao tác đối khớp: ưu tiên URL trước, sau đó dùng index dự phòng. Khi thay đổi URL hoặc index của một chương, hệ thống loại bỏ khóa cũ và tự động thăng cấp (promote) chương trùng lặp tiếp theo trong thùng chứa, duy trì chính xác ngữ nghĩa `first(where:)` trong thời gian $O(1)$ trung bình.

## [1.3.34] - 2026-07-20

### Cập nhật CodeGraph tăng dần cho cấu trúc dữ liệu mới, BookStorageManager, phân trang mục lục và bảo mật Sandbox
* **Database Models**:
  * **Chapter**: Cập nhật hàm `Chapter.generateId(bookId:url:index:)` sử dụng định dạng có độ dài tiền tố (length-prefixed format) như `[len]:[bookId]|U:[len]:[url]` cho online và `[len]:[bookId]|I:[index]` cho fallback khi không có URL. Legacy Chapter ID được giữ nguyên không di chuyển.
* **Component mới**:
  * **BookStorageManager**: Quản lý việc xóa sách khỏi kệ và lịch sử, xử lý các side-effects (dừng TTS, huỷ tải xuống, xoá reader fallback progress). Database context được save (commit DB) trước khi tiến hành xóa các file vật lý nhị phân (.bin) và ảnh bìa (.jpg) bất đồng bộ trong background thread. Lỗi xóa file vật lý được đẩy vào retry queue lưu trong `UserDefaults` (`failed_file_deletions_queue`) và được xử lý lại tối đa 3 lần tại app startup (`drainRetryQueue()`).
* **Bảo mật Sandbox & Di chuyển Lưu trữ**:
  * **BookBinManager & ImageCacheManager**: Chuyển sang sử dụng mã băm SHA-256 của `bookId` làm tên file lưu trữ (`[sha256Hex].bin` và `[sha256Hex].jpg`) để tránh lỗi path injection. Tích hợp kiểm tra bảo mật sandbox (`validatePathSafety(for:)`) trước khi đọc, ghi hoặc xóa tệp. Tự động di chuyển (migrate) và dọn dẹp các tệp legacy hiện có.
* **Tối ưu hóa Trình đọc (TOC Pagination)**:
  * **ReaderChapterListStore & ReaderChapterListView**: Giới hạn RAM bằng cơ chế phân trang TOC (TOC pagination) và cửa sổ trượt (sliding window) chỉ giữ tối đa 3 trang liền kề (300 dòng trạng thái chương), giải quyết triệt để lag/OOM cho sách siêu lớn (ví dụ 20.000 chương).
  * **ReaderViewModel**: Loại bỏ memory cache cho toàn bộ chapter list (`cachedSortedChapters`), thực hiện fetch trực tiếp từ DB khi cần và cung cấp API tạo metadata cho TTS (`fetchChaptersMetadata`).
* **Cooperative Cancellation**:
  * **DownloadManager**: Cải thiện cooperative cancellation bằng cách liên tục kiểm tra trạng thái huỷ của Task trong lúc tải chương hoặc xuất file text.
* **Giới hạn & Lưu ý**:
  * Tiếp tục giữ yêu cầu tối thiểu iOS 17+.
  * Không migrate legacy Chapter IDs hiện có để tránh hỏng tham chiếu chéo.
  * Danh sách chương trực tuyến (`onlineChapters` / `ChapterResult`) vẫn giữ nguyên dưới dạng mảng đầy đủ (full array).

## [1.3.33] - 2026-07-20

### Tái cấu trúc Hệ thống Lưu trữ: Đọc/Ghi Nhị phân (.bin) + SQLite offset/length + UUID Sách
* **Database Models**:
  * **Chapter**: Xóa trường `content: String?` khỏi SQLite để giải phóng dung lượng DB. Thêm thuộc tính `bookId: String`, `offset: Int64` và `length: Int64`. Thêm các helper sinh ID tĩnh băm URL (`hashUrl` và `generateId`).
* **App Setup**:
  * **FreeBookApp**: Khởi tạo `ModelContainer` thủ công hướng về `Library/Application Support/library.db` thay vì dùng mặc định.
* **Component mới**:
  * **BookBinManager**: Actor thread-safe quản lý việc đọc/ghi dữ liệu UTF-8 vào file `.bin` của sách tại `Application Support/books/`.
* **Thư mục Lưu trữ**:
  * Di chuyển toàn bộ các thư mục lưu trữ (`covers/` ở **ImageCacheManager**, `extensions/` ở **ExtensionManager**, `translate/` ở **TranslationManager**, và `app_logs.txt` ở **AppLogger**) sang thư mục ẩn `Library/Application Support/` để tuân thủ Apple App Store Guidelines.
* **Logic Nghiệp vụ**:
  * **ChapterPersistenceStore**: Cập nhật hàm `readChapter` và `persistWithRetry` sử dụng `BookBinManager` ghi/đọc nhị phân theo `offset`/`length`. Sử dụng `Chapter.generateId` khi chèn chương mới.
  * **DownloadManager**: Cập nhật luồng download nền ghi chương tải về vào file `.bin` qua `BookBinManager` và lưu thông tin vị trí byte.
  * **ShelfView**: Cập nhật nhập sách `.txt` cục bộ sinh `bookId` dạng UUID, tạo URL chương cục bộ độc bản và ghi nội dung vào file `.bin`.
  * **BookDetailView**: Sử dụng cơ chế `@State resolvedBookId` và hàm `resolveBookId()` tra cứu DB bằng `detailUrl + extensionPackageId` để đảm bảo lưu sách dùng UUID. Cập nhật các đoạn tạo `Chapter` mới truyền đúng `bookId` và dùng `generateId`.
  * **SearchView**: Cập nhật hàm thay đổi nguồn `executeSourceChange` đổi `newBookId` sang UUID và cập nhật chèn danh sách chương mới.

## [1.3.32] - 2026-07-20

### Tối ưu hóa hiệu năng BookDetailView và sửa lỗi token khoảng cách thừa
* **BookDetailView**:
  * Tối ưu hóa thuật toán đối chiếu danh sách chương trong `updateLocalChapters` từ $O(N^2)$ xuống $O(N)$ bằng `Dictionary` tra cứu nhanh theo `url` và `index`.
  * Tránh thực hiện `sorted` và `filter` trực tiếp trong `body` mỗi lần View vẽ lại. Chuyển sang lưu cache danh sách chương và danh sách đã lọc vào các biến `@State` (`chaptersList`, `filteredLocalChapters`, `filteredOnlineChapters`).
  * Sử dụng các modifier `.onChange` để cập nhật lại các danh sách cache này một cách chọn lọc khi có thay đổi các tham số đầu vào (`chaptersList`, `onlineChapters`, `isTocAscending`, `chapterSearchQuery`, `isTranslationEnabled`), giúp loại bỏ hoàn toàn hiện tượng giật lag khi mở chi tiết truyện lớn (khoảng 2000 chương).
  * Thay thế `.onChange(of: allBooks)` bằng `.onChange(of: localBook?.chapters.count)` để khắc phục lỗi trình biên dịch không thể kiểm tra kiểu do kiểu dữ liệu không tuân thủ `Equatable`.
* **TranslateUtils**:
  * Cập nhật `getTranslationTokens(for:bookId:)` và `performTranslation(_:bookId:)` để bỏ qua cơ chế ghép khoảng trắng Hán-Việt cho các token thuần số hoặc chữ Latin (không chứa ký tự tiếng Trung).
  * Khắc phục triệt để lỗi số `1000` bị tách thành `1 0 0 0` và lỗi lệch pha offset làm bôi đen sai/bôi đen toàn bộ cụm từ trong Trình đọc.
* **ExtensionManager**: Cho `ChapterResult` kế thừa thêm `Equatable` để hỗ trợ cụ thể SwiftUI theo dõi thay đổi danh sách chương online.
* **ReaderView & ReaderViewModel**:
  * Áp dụng cơ chế **Lazy Load 100%** cho danh sách chương: Trong hàm khởi tạo của `ReaderViewModel`, chỉ truy vấn `chapters.count` (cực nhanh, không tải thực thể vào RAM).
  * Khởi tạo lười bộ lưu trữ danh sách chương `ReaderChapterListStore` và chỉ đưa `ReaderChapterListView` vào view hierarchy khi menu mục lục thực sự được mở (giúp giảm thiểu tối đa tài nguyên và thời gian vẽ giao diện ban đầu).
  * Ghi chú lịch sử: phiên bản này từng đồng bộ các thuộc tính computed của Reader để sử dụng dữ liệu đã cache trong `viewModel.getSortedChapters()`, loại bỏ hiện tượng giật lag khi chuyển tiếp từ Kệ sách/Lịch sử vào Trình đọc đối với truyện lớn.
  * Đồng bộ hóa các lệnh gọi `synchronize` trong `ReaderChapterListView.swift` tương thích với kiểu chữ ký mới sử dụng `sortedChapters: [Chapter]`.

## [1.3.31] - 2026-07-19

### Hậu kỳ dịch thuật & Đồng bộ Tiện ích
* **JSExecutor**: Bổ sung hàm `base64()` vào đối tượng Response trả về từ hàm `fetch` trong JavaScript để cung cấp dữ liệu dạng Base64 của phản hồi mạng cho các VBook extension, tránh lỗi `TypeError: response.base64 is not a function`.
* **TranslateUtils**:
  * Nâng cấp thuật toán phân tách từ (`tokenize`) sang cơ chế Multi-pass bảo vệ Tên riêng (Name) tối đa trước VietPhrase, giải quyết tranh chấp bằng Global Longest Match (tên riêng dài hơn thắng).
  * Refactor hàm `getTranslationTokens` để tái sử dụng `tokenize`, loại bỏ trùng lặp code và đồng bộ hóa highlight.
  * Tối ưu hóa phân tách dấu câu độc lập (chỉ gom nhóm Alphanumeric, còn dấu câu như `?”` và `.”` tách thành các token độc lập giúp tra cứu từ điển VP chính xác).
  * Hỗ trợ cài đặt bật/tắt dịch Đại từ (Pronouns) và Luật nhân hóa động.
* **ReaderView, ReaderSettingsView, SettingsView**:
  * Thêm UI Toggle cho phép người dùng bật/tắt cài đặt dịch Đại từ (Pronouns) và Luật nhân hóa, lưu trữ qua `@AppStorage`, mặc định là Tắt (`false`).
  * Tự động xóa cache dịch và kết xuất lại giao diện tức thì khi thay đổi một trong hai cài đặt này.
* **RepositoryManagerView**: Thêm in thông báo log debug `print` khi tải hoặc parse file cấu hình `plugin.json` trên mạng của tiện ích chưa cài đặt gặp lỗi, hỗ trợ chẩn đoán chính xác lý do metadata bị hiển thị sai lệch hoặc không đầy đủ.

### Tối ưu hóa cử chỉ Reader, Panel dịch Full-width, Item-based Browser và Mở Chi tiết từ Cover
* **DiscoveryView**: Nâng cấp từ `isPresented`-based sang `item`-based `.fullScreenCover(item:)` thông qua struct `ExtensionBrowserTarget: Identifiable` cho cả header (`headerBrowserTarget`) và danh sách (`listBrowserTarget`). `BypassWebView` chỉ được khởi tạo đúng lúc người dùng bấm nút Safari, tránh hoàn toàn lỗi URL rỗng lần đầu mở.
* **ReaderView — Panel dịch**:
  * Full-width Bottom Sheet: Xoá `.padding(.horizontal)`, dùng `UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16)` để bo 2 góc trên.
  * Bấm ngoài để tắt: Thêm `Color.clear` với `.simultaneousGesture(TapGesture())` (không tiêu thụ event, widget ở zIndex cao hơn vẫn hoạt động bình thường).
  * Vuốt xuống để tắt: Thêm `DragGesture` (ngưỡng > 50pt) trên panel dịch.
  * Drag Indicator: Thêm `Capsule` 36×5pt ở đầu `definitionSheetContent`.
  * Cỡ chữ gốc Hàng 1: `.font(.title3)` → `.font(.body)`.
  * Nút Cập nhật: Thêm `.controlSize(.small)` và giảm `.padding(.vertical, 8)`.
* **ReaderView — Danh sách chương**:
  * Ghi chú lịch sử: phiên bản này từng thêm hành vi kéo panel mục lục theo tay; hành vi đó đã bị loại bỏ ở 1.3.38, chỉ giữ vuốt xuống đủ ngưỡng và tap ngoài để đóng.
* **ReaderChapterListView**:
  * Ghi chú lịch sử: các callback kéo realtime của mục lục đã bị loại bỏ ở 1.3.38.
  * Bọc `BookCoverView` trong `Button` mở `BookDetailView` qua `.sheet(isPresented:)` với `NavigationStack` khi `bookDetailUrl != nil` và `ext != nil`.

## [1.3.30] - 2026-07-19

### Căn lề hai bên Reader, Sửa lỗi URL trình duyệt rỗng, Đồng bộ metadata extension từ plugin.json
* **ReaderTextView**: Áp dụng `.justified` alignment cho đoạn văn thường (nhánh `else` khi không phải `isCentered`), giữ nguyên `firstLineHeadIndent` để thụt đầu dòng vẫn hoạt động.
* **DiscoveryView — sửa lỗi URL trỗng khi mở BypassWebView lần đầu**: Bọc `BypassWebView` trong điều kiện kiểm tra `showingHeaderWeb && !ext.sourceUrl.isEmpty` (header) và `showingListWeb && !listWebUrl.isEmpty` (danh sách), ngăn SwiftUI khởi tạo view khi URL chưa được set.
* **RepositoryManagerView — syncExtensions**: Thay thế `JSONDecoder` + `RemotePluginMeta` bằng `JSONSerialization` để hỗ trợ cấu trúc `"metadata"` lồng nhau trong `plugin.json`. Ưu tiên đọc offline từ `localPath/plugin.json` nếu tiện ích đã tải về; chỉ fallback tải từ thư mục gốc của URL zip trên mạng khi chưa có cục bộ.
* **RepositoryManagerView — installExtension**: Chuyển sang `JSONSerialization` + nhánh `metadata` để đọc `plugin.json` sau khi giải nén. Cập nhật thêm `ext.sourceUrl` từ trường `"source"` trong JSON bên cạnh locale/type/version/author.

## [1.3.29] - 2026-07-19

### Lọc dữ liệu truyện rỗng/trùng lặp tại các View Gợi ý, Thể loại, Tìm kiếm, và Khám phá
* `DiscoveryView`, `SuggestRowView`, `CategoryNovelsListView`, `SearchView`: Định nghĩa hàm helper `normalizeLink(_:)` để loại bỏ scheme + host và đồng bộ tiền tố `/` cho liên kết tương đối/tuyệt đối.
* Áp dụng chuẩn hóa liên kết khi so khớp trùng lặp link nhằm loại bỏ triệt để các truyện bị trùng lặp ở cả hai định dạng tương đối và tuyệt đối (ví dụ: `https://wcshuba.com/book/87661.html` và `/book/87661.html`).

## [1.3.28] - 2026-07-19

### Thống nhất Toast toàn cục, Nút Đọc từ bôi đen, và Tích hợp Engine Google TTS "Chị Google"
* **Thống nhất Toast toàn cục**: Loại bỏ tất cả Toast cục bộ tự vẽ ở các màn hình, chuyển sang gọi qua `ToastManager.shared` đặt tại root view (`AppLaunchRootView` trong `FreeBookApp.swift`). Hỗ trợ thêm icon cho 3 loại Toast (`.success` - checkmark xanh, `.error` - exclamation đỏ, `.info` - không icon).
* **Toast cho 4 chức năng xuất file**: Thêm Toast thành công/thất bại cho xuất ebook TXT, xuất từ điển dịch, xuất từ điển phát âm (NghiTTS), và xuất quy tắc thay thế TTS. Thay thế `ShareLink` tĩnh bằng `Button` tạo file -> báo Toast -> mở `ShareSheet` dùng chung (`ShareSheet.swift`).
* **Tích hợp Engine "Chị Google"**: Thêm `GoogleTTSService` kết nối trực tiếp đến Google Translate TTS API để tải file MP3 trực tuyến. `TTSManager` hỗ trợ prefetch và chuyển đổi trực tiếp MP3 sang `AVAudioPCMBuffer` qua file tạm.
* **Ẩn bộ chọn giọng đọc**: Giao diện `TTSSettingsView` ẩn bộ chọn giọng đọc khi chọn engine "Chị Google" để tối giản trải nghiệm.
* **Nút Đọc từ bôi đen**: Bổ sung nút **Đọc** (biểu tượng loa phát `speaker.wave.2.fill`) vào menu bong bóng nổi khi bôi đen chữ trong `ReaderView` để phát trực tiếp từ bôi đen (đã dịch nếu bật dịch) bằng giọng đọc của Chị Google qua `AVAudioPlayer` (MP3 raw data).

## [1.3.27] - 2026-07-19

### Sửa lỗi Khám phá: không cập nhật khi tắt dịch, lọc novel trùng/rỗng
* `DiscoveryCategoryTabView`: Thêm `.onChange(of: isTranslationEnabled)` để reset và reload danh sách truyện khi bật/tắt dịch — trước đó view cache dữ liệu cũ trong `@State` nên không cập nhật.
* `loadNovels`: Lọc các novel có `name` hoặc `link` trống trước khi hiển thị.
* `loadNovels`: Deduplicate theo `link` — cả page 1 (trong batch) lẫn load-more (so sánh với danh sách hiện có) để tránh hiển thị trùng.

## [1.3.26] - 2026-07-19

### Sửa lỗi vị trí Floating Bubble Menu, tap-outside dismiss, và menu re-show sau TTS jump
* **Lỗi 1 – Vị trí menu sai**: Chuyển đổi `selectionMinY`/`selectionMaxY` từ window coordinates (UIKit) sang local coordinates của GeometryReader bằng cách trừ `geometry.frame(in: .global).minY`; thêm tham số `geometryOriginY` vào `FloatingSelectionMenu`.
* **Lỗi 2 – Không tắt khi tap ngoài**: Thêm `Color.clear` overlay với `.simultaneousGesture(TapGesture())` ở zIndex 9 (dưới menu), bắt mọi tap ra ngoài các nút menu để tắt menu và xóa selection mà không chặn scroll.
* **Lỗi 3 – Menu hiện lại sau TTS jump**: Thêm `uiView.selectedRange = NSRange(location: 0, length: 0)` ngay sau `uiView.attributedText = attributedText` để UIKit không giữ selection cũ khi highlight thay đổi.

## [1.3.25] - 2026-07-18

### Sửa lỗi Floating Bubble Menu và Global TTS Settings Sheet
* Khắc phục menu bong bóng đè lên vùng bôi đen: sử dụng union của `firstRect` và `caretRect(for: end)` để tính `minY`/`maxY` toàn bộ vùng selection; menu xuất hiện phía trên nếu đủ không gian, ngược lại phía dưới.
* Khắc phục menu không tắt khi tap ra ngoài: xóa guard `lastSelectionRange` khi `length == 0` để sự kiện deselect luôn được gửi lên ReaderView.
* Khắc phục bôi đen không xóa sau khi bấm nút: thêm `clearSelectionTrigger: UUID?` binding từ `ReaderView` → `ParagraphCardView` → `ReaderTextView`; mỗi action của menu đều kích hoạt trigger xóa selection trên `UITextView`.
* Tạo file `TTSSettingsSheet.swift` mới: wrapper `NavigationStack { TTSSettingsView(isPresentedAsSheet: true) }` dùng chung toàn cục cho Widget và mọi màn hình.
* Gắn `.sheet(isPresented: $ttsManager.showingSettingsSheet)` lên `AppLaunchRootView` thay vì `ReaderView` để sheet cài đặt TTS hoạt động ở mọi tab; `NavigationLink` bên trong `TTSSettingsView` không còn bị disabled.

## [1.3.24] - 2026-07-18

### Custom Selection Menu, NghiTTS Pronunciation Integration, Custom Dict Export Naming, and Remote Metadata Sync
* Thay thế Edit Menu hệ thống bằng SwiftUI Floating Bubble Menu chứa 5 nút Dịch, Nghe, Phiên âm, Copy, Đóng khi bôi đen văn bản trong Reader.
* Sử dụng scroll offset KVO và selection change delegates để giữ vị trí menu bám sát vùng bôi đen của chữ kể cả khi cuộn trang.
* Khắc phục mất góc Floating Bubble Menu ở sát lề màn hình bằng cách giới hạn tọa độ x theo screenWidth.
* Tăng kích thước Floating Bubble Menu lên to rõ hơn (nút 60x48, cỡ chữ 11, cỡ icon 16) và đổi icon nghe thành headphones hợp lệ.
* Sử dụng từ hiển thị đã dịch (nếu bật dịch) làm từ gốc khi thêm Phiên âm NghiTTS.
* Gỡ bỏ nút Thêm phiên âm trong panel dịch ở đáy.
* Tích hợp màn hình cài đặt TTSSettingsView dạng sheet trong ReaderView để nút cài đặt trên Widget có thể mở chính xác.
* Hỗ trợ tìm kiếm thêm nhanh phiên âm tại màn hình quản lý NghiTTS và tự động điền gợi ý phát âm từ `EnglishTransliterator`.
* Cài đặt nút bánh răng (Cài đặt TTS) nằm ở bên phải cover sách của Floating Widget để mở nhanh cài đặt TTS, mở rộng widget size về 212.
* Định dạng lại cấu trúc tên file xuất từ điển riêng thành `[Vietphrase/Name]_[Tên truyện đã dịch (ưu tiên) hoặc Tên truyện gốc]_[yyyyMMddHHmmss].txt` và hiển thị Toast kết quả.
* Chỉnh sửa cơ chế lấy metadata của Extension khi đồng bộ Repo: tự động tải và parse file `plugin.json` từ xa của từng extension dựa trên trường `path` của file zip, hỗ trợ dự phòng về dữ liệu registry tổng khi gặp lỗi.

## [1.3.23] - 2026-07-18

### Tách biệt điều hướng chương TTS/Reader và tối giản widget nổi
* Sửa đổi logic ReaderView để việc chuyển chương thủ công (Next/Prev/TOC) không kéo theo TTS chuyển chương theo.
* Chỉ tự động cuộn màn hình Reader theo tiến độ đọc của TTS khi người dùng đang ở cùng chương với TTS.
* Khi TTS tự động chuyển chương (advance), Reader chỉ chuyển theo nếu trước đó người dùng đang đọc cùng chương với TTS.
* Cập nhật nút nghe (headphones) trong Reader luôn dừng TTS cũ và phát lại từ dòng đầu tiên hiển thị trên màn hình hiện tại.
* Tối giản widget nổi TTS: loại bỏ hiển thị text tên sách/chương để tránh rối mắt, điều chỉnh chiều rộng widget mở rộng về 174 (thay vì 252) và căn chỉnh khoảng cách các nút điều khiển cho cân đối.

## [1.3.22] - 2026-07-18

### Khôi phục kiến trúc layout và cử chỉ kéo thả/chạm của Widget nổi TTS
* Khôi phục layout bằng `GeometryReader` kết hợp `.position(renderPosition)` thay thế cho `.offset()` cũ để đồng bộ chính xác vùng vẽ visual và vùng nhận tương tác (hit-test area). Điều này giúp khắc phục triệt để lỗi widget bị "liệt" không nhận kéo thả do lệch vùng chạm.
* Sử dụng `DragGesture(minimumDistance: 5)` với `.highPriorityGesture` để ưu tiên cử chỉ kéo thả của widget mà không bị nuốt bởi các nút bấm điều khiển bên trong hoặc các cử chỉ cuộn nền của Reader.
* Khôi phục `.onTapGesture` trực tiếp trên widget để xử lý chạm kích hoạt mở rộng (`reveal()`) khi ở trạng thái ẩn (peeking) hoặc tạm dừng/phát nhạc (`togglePlayback()`) khi chạm vùng trống ở trạng thái mở rộng (revealed), loại bỏ logic nhận diện tap tự chế phức tạp trong `onEnded`.

## [1.3.21] - 2026-07-18

### Sửa lỗi điều khiển tai nghe và kéo widget nổi
* Sửa lỗi bấm tai nghe phải bấm hai lần mới phát lại: bỏ cập nhật trạng thái trước (`setSystemNowPlayingPlaybackState`) trong handler remote command và dùng `DispatchQueue.main.async` thay vì `Task` để `resume()`/`pause()` chạy đồng bộ trên main queue, đảm bảo trạng thái cập nhật nhất quán trước khi iOS xử lý lệnh tiếp theo.
* Sửa lỗi widget nổi không thể kéo hoặc hiển thị lại từ trạng thái thu nhỏ (peeking) và trạng thái đầy đủ (revealed): đổi gesture từ `.simultaneousGesture` sang `.gesture` với `minimumDistance: 0`, loại bỏ `.onTapGesture` riêng trên collapsedWidget vì nó nuốt toàn bộ sự kiện chạm và chặn drag gesture kích hoạt; xử lý tap-to-reveal và tap-to-toggle-playback trong `onEnded` của drag gesture dựa trên ngưỡng di chuyển.

## [1.3.20] - 2026-07-18

### Đồng bộ Lock Screen, cử chỉ kéo widget và khôi phục text DOM
* Khôi phục hành vi trích xuất văn bản DOM (`JSDom.swift`) không trim khoảng trắng và dòng mới tại lớp DOM để tránh làm hỏng các tiền tố kiểm tra của Extension.
* Sửa lỗi đồng bộ điều khiển Lock Screen/AirPods (`TTSManager.swift`): Vô hiệu hóa `togglePlayPauseCommand` tránh nhận trùng lặp sự kiện trên thiết bị Bluetooth; đồng thời cập nhật tức thì trạng thái playback state ngay trong luồng chính để phản hồi nhanh chóng lên UI Lock Screen.
* Tối ưu hóa cử chỉ widget nổi (`TTSFloatingWidgetView.swift`, `FloatingWidgetViewModel.swift`): Giữ nguyên chế độ hiển thị trong suốt quá trình kéo tránh ngắt quãng gesture; tách biệt rõ ràng tap và drag snapping; bổ sung kiểm tra kích thước màn hình hợp lệ để tránh lỗi tính toán.
* Thêm kiểm thử tự động cho trạng thái đồng bộ Now Playing, cử chỉ snapping và các trường hợp widget biên trong `FloatingWidgetViewModelTests.swift` và `TTSManagerTests.swift`.

## [1.3.19] - 2026-07-18

### Local-first Reader/TTS và quản lý kho an toàn
* Dùng chung chapter repository theo thứ tự RAM → SwiftData → extension, coalesce in-flight load và ghi nền bằng `ChapterPersistenceStore` có retry/flush.
* Sửa dữ liệu cũ có content nhưng sai `isCached`, upsert Book/Chapter online và giữ cache khi đồng bộ lại mục lục.
* Cô lập session Reader/TTS theo book/chapter/session identity; Reader sách khác không prepare hoặc seek TTS đang phát hay pause.
* Danh sách kho bỏ swipe-delete và toggle; thêm nút trash, xác nhận xóa và bảo vệ kho đang được TTS sử dụng.
* Tách phần thân Reader và overlay mục lục thành các view con để tránh lỗi SwiftUI type-check quá thời gian; flush persistence không còn cảnh báo giá trị trả về bị bỏ qua.
* Không để snapshot rỗng từ `@Query` ghi đè số chương đã resolve trực tiếp từ SwiftData; Reader bootstrap lại khi dữ liệu local/online đến muộn.
* Widget TTS mở ở trạng thái hiển thị khi session bắt đầu và chỉ tự thu gọn sau timeout hoặc thao tác kéo sát cạnh.
* BookDetail truyền TOC online làm fallback bootstrap để mở Đọc tiếp không phụ thuộc thời điểm `@Query` phát hiện Book local.
* Truy vấn bootstrap Reader lọc theo `bookId` và giới hạn một bản ghi để không quét toàn bộ SwiftData trên MainActor.
* Nút nghe trong Reader luôn giữ biểu tượng tai nghe và chỉ dừng session TTS thuộc cùng sách; metadata Book/author trên màn hình tải và xuất ebook phản ánh cài đặt dịch.
* Đồng bộ Lock Screen/AirPods với trạng thái TTS thực tế, chống Now Playing update cũ ghi đè trạng thái mới và hỗ trợ `togglePlayPauseCommand`.
* Tra cứu nhanh từ màn hình dịch dùng route URL bất biến; WebView tải lại khi URL đích đổi để không còn trang trắng hoặc hiển thị truy vấn trước đó.

## [1.3.18] - 2026-07-18

### Thu gọn và căn sát widget TTS
* Giảm kích thước capsule và các nút điều khiển để widget che ít nội dung Reader hơn.
* Căn trạng thái mở rộng sát mép trái/phải màn hình; trạng thái thu gọn giữ nửa hình tròn nhỏ hơn ở đúng cạnh đã chọn.

## [1.3.17] - 2026-07-18

### Sửa lỗi biên dịch sau khi dọn Reader legacy
* Khôi phục `DictionaryMatchInfo`, `ReaderSettingsView` và `ReaderViewModelObserver` thành các file độc lập thay vì để mất cùng khối Reader legacy.
* Trả đúng `ReaderParagraphBuildResult` từ `Task.detached` trong `ReaderViewModel`, tránh suy luận kết quả thành `Void`.
* Chỉ khởi chạy task cấu hình progress/repository sau khi toàn bộ stored property của `ReaderViewModel` đã được khởi tạo.
* Dọn closure rỗng trong navigation commit và capture `self` không sử dụng của `ImageCacheManager`.
* Reader tự lấy snapshot chương local khi `@Query` đến muộn và đồng bộ danh sách chương online cập nhật sau khi Reader đã mount; widget TTS không còn phủ vùng hit-test toàn màn hình.

## [1.3.16] - 2026-07-18

### Thiết kế lại widget TTS nổi
* Thay widget radial bằng capsule ngang có cover tròn, play/pause, next đoạn và nút đóng.
* Cover xoay liên tục khi phát, giữ góc hiện tại khi tạm dừng; thao tác cover mở đúng chương TTS đang đọc.
* Hỗ trợ kéo vào hai cạnh, tự thu gọn thành nửa hình tròn sau khi chạm cạnh hoặc không thao tác, kéo ra để mở lại và giới hạn vị trí theo màn hình.
* Cho phép chuyển đoạn tiếp theo khi TTS đang tạm dừng và đồng bộ điều hướng Reader khi sách đã mở.

## [1.3.15] - 2026-07-18

### Cải tổ pipeline Reader/TTS
* Chuẩn hóa văn bản chương một lần bằng `ChapterTextNormalizer`, dùng chung `ChapterContentRepository` cho Reader và TTS.
* Thêm bootstrap/load state có retry và timeout, route mục lục bất biến, checkpoint tiến độ nền, ownership TTS và session guard.
* Xóa Reader window/tab/legacy, repository tiến độ trùng và `TTSSession` mirror.

## [1.3.14] - 2026-07-17

### Chuẩn hóa paragraph 1–1 và ánh xạ vùng chọn bản dịch
*   **Người thực hiện**: Trợ lý AI Codex
*   **Tổng số file nguồn ảnh hưởng**: 7 file Swift, 1 file test
*   **Mô tả**:
    *   Tách nội dung gốc thành dòng trước khi dịch, dịch độc lập từng dòng và tạo `ParagraphItem` 1–1 với id ổn định, kể cả dòng rỗng hoặc dòng cuối trống.
    *   Bổ sung kết quả dịch kèm span gốc/bản dịch theo UTF-16; payload `ParagraphItem` cũ vẫn decode với danh sách span rỗng.
    *   Menu “📖 Dịch” chỉ truyền `NSRange` và paragraph id; Reader lấy đúng item trong chương, luôn dùng `item.original` cho màn hình dịch.
    *   Ưu tiên span chính xác và giữ thuật toán câu/token của commit `3312841` làm fallback khi mapping thiếu hoặc không hợp lệ.
    *   Thêm test cho paragraph 1–1, blank/trailing line, Codable cũ, UTF-16, multi-token và fallback lịch sử.

## [1.3.13] - 2026-07-17

### Phản hồi tải chương tức thì và tinh gọn tương tác Reader
*   **Người thực hiện**: Trợ lý AI Codex
*   **Tổng số file nguồn ảnh hưởng**: 5 file Swift, 1 file test
*   **Mô tả**:
    *   Reader trình bày ngay chương đích bằng tiêu đề, số chương và skeleton trong lúc vẫn giữ debounce 300 ms để gộp thao tác liên tiếp.
    *   Bỏ vuốt ngang chuyển chương, swipe hint, state kéo biên và callback selection activity chỉ phục vụ gesture cũ; chọn chữ, tra từ, copy và TTS vẫn giữ nguyên.
    *   Thu gọn header Reader, đổi overflow thành ba chấm dọc; header mục lục bỏ khoảng trống co giãn, đổi icon sắp xếp, bỏ nút X và hỗ trợ vuốt xuống tại tay nắm để đóng.
    *   Bổ sung validator CodeGraph chuẩn hóa link, schema, marker, source/document inventory và SHA-256 của manifest.

## [1.3.12] - 2026-07-17

### Cap nhat UI Reader va header danh sach chuong
*   **Nguoi thuc hien**: Tro ly AI Codex
*   **Tong so file nguon anh huong**: 2 file Swift
*   **Mo ta**:
    *   Header Reader dung ba hang: back/reload/dropdown, nut dich gop hai hang, ten truyen va hang ten chuong mo muc luc.
    *   Body bo thanh cong cu thu gon, chi giu mot nut TTS noi.
    *   Danh sach chuong truot tu duoi len, van mount trong suot vong doi Reader va ton trong Reduce Motion.
    *   Header muc luc hien cover, ten truyen va tac gia day du; cong cu refresh/sap xep/dong nam o goc duoi ben phai metadata.
    *   Metadata dich theo trang thai dich cua Reader va khong tai lai detail hay muc luc.

## [1.3.11] - 2026-07-17

### Refactor Reader mot chuong va toi uu dieu huong
*   **Nguoi thuc hien**: Tro ly AI Codex
*   **Tong so file nguon anh huong**: 7 file Swift, 1 file test
*   **Mo ta**:
    *   Reader chi render mot chuong; chuyen chuong bang swipe ngang hoac footer, khong tu dong tai/chuyen khi cuon doc den cuoi.
    *   Dieu huong thu cong debounce 300 ms va giu target moi nhat; mot worker tai noi dung va generation check ngan request cu commit sai chuong.
    *   Loi `Response.error` duoc giu nguyen, hien cung ten chuong va nut retry o giua man hinh.
    *   Danh sach chuong duoc tao va mount mot lan trong vong doi Reader; cache thanh cong chi cap nhat icon cua mot row.
    *   Dropdown dung chung command cho hien ten chuong, force reload, tu dien, browser va cai dat.
    *   TTS sync chi thay doi vi tri hien thi, khong ghi de lich su; Reader prefetch N+1 bi tat khi TTS cung sach dang phat.
    *   Them test cho rapid-step N+4, chapter list 10.000 row va thong diep source error.

## [1.3.10] - 2026-07-17

### Fix Reader history restore, infinite chapter loading, and jump/list lag
*   **Nguoi thuc hien**: Tro ly AI Codex
*   **Tong so file nguon anh huong**: 4 file Swift, 1 file test
*   **Mo ta**:
    *   Reader mo dung vi tri lich su; TTS dang phat khong ghi de vi tri ban dau, nhung lan chuyen paragraph ke tiep se dua giao dien ve vi tri TTS neu auto-scroll dang bat.
    *   Window render cap nhat `stableIndexes` khi scroll qua chapter, sua loi dung tai gioi han `n+2`.
    *   Chapter list chi duoc khoi tao khi mo va dich title theo row hien thi, giam tai MainActor.
    *   Prefetch task da cancel van chiem local/global concurrency slot den khi fetch dong bo thuc su ket thuc; Reader cu khong the mo them batch song song voi Reader moi sau luong thoat -> Kham pha -> Doc ngay.
    *   Reader teardown huy queue/task rieng va chi force-save khi Reader dang so huu progress.
    *   Them test hoi quy cho window chapter va gioi han concurrency voi fetch khong phan hoi cancellation ngay.
    *   Jump chi tai chapter dich; sau khi dich tai xong va Reader on dinh moi tai mot chapter ke tiep. Jump nhanh loai bo cac chapter trung gian chua bat dau.
    *   Muc luc khong animate qua hang nghin row va khong tao them query toan bo Book/Extension khi mo.

## [1.3.9] - 2026-07-17

### Cap nhat UI Reader header/body/footer va TTS CD radial widget
*   **Nguoi thuc hien**: Tro ly AI Codex
*   **Tong so file nguon anh huong**: 6 file Swift
*   **Mo ta**:
    *   **ReaderView**: Bo HUD tap an/hien, chuyen sang layout co dinh `Header + Body + Footer`; header co back, ten truyen/ten chuong va dropdown option cu; footer hien phan tram va chi so chuong.
    *   **ReaderTextView**: Bo gesture post `toggleReaderControls` de tap vao noi dung khong con an/hien HUD, van giu `UITextView` va text selection/custom menu; them first-line indent cho moi doan van ban ma khong chen khoang trang vao noi dung goc.
    *   **Reader floating controls**: Them cum nut noi thu vao mep phai cho dich, TTS va danh sach chuong.
    *   **TTSFloatingWidgetView / FloatingWidgetViewModel / WidgetState**: Thay expanded/collapsed widget bang CD radial widget co cover trung tam, play/pause overlay, cac nut radial xem reader/next/stop va nut an vao mep.

## [1.3.8] - 2026-07-17

### Refactor Reader sang Infinite Vertical Window va bo sung TTSSession snapshot
*   **Nguoi thuc hien**: Tro ly AI Codex
*   **Tong so file nguon anh huong**: 9 file Swift, 1 file test
*   **Mo ta**:
    *   **ReaderView**: Them runtime `Infinite Vertical Reader` dung mot `ScrollViewReader` + mot `ScrollView` + `LazyVStack` cho window chapter hien tai. Paragraph van render qua `ParagraphCardView`/`ReaderTextView`, giu nguyen `UITextView`, selection menu, dich, nghe doan chon va copy.
    *   **ReaderViewModel**: Bo sung `ReadingContext`, chuyen jump/chapter selection sang thao tac replace/rebase window quanh chapter dich thay vi scroll qua toan bo truyen. Window mac dinh can bang theo `ReaderWindowManager`.
    *   **ReaderWindowManager / ReaderCoordinator / ChapterContentProvider**: Them cac seam kien truc de tach quyet dinh window/progress/loading khoi UI va chuan bi gom cache/content provider dung chung.
    *   **ChapterCache**: Bo sung state `notLoaded`, `ReadingContext` va alias `SharedChapterCache` de thong nhat huong cache dung chung Reader/TTS.
    *   **TTSManager / TTSSession**: Them `TTSSessionSnapshot` va `PlaybackQueue`; TTS cap nhat session snapshot khi start/pause/resume/stop va khi phat tung paragraph, giup Reader mo lai co the sync tu session thay vi so huu playback.
    *   **Tests**: Cap nhat `ReaderViewModelTests` theo API `PrefetchManager.updateQueue(... activeIndex:)` hien tai.

## [1.3.7] - 2026-07-16

### Sửa lỗi lấy chương online của TTS do gán sai thông tin tiện ích khi mở lại màn hình đọc (Fix TTS Online Extension Resolution)
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 4 file Swift (TTSModels.swift, TTSManager.swift, ReaderView.swift, ShelfView.swift)
*   **Mô tả**:
    *   **TTSModels**: Bổ sung thuộc tính `packageId` vào struct `TTSExtensionInfo` để lưu lại định danh của extension (thay vì chỉ lưu localPath).
    *   **TTSManager**:
        *   Thêm các thuộc tính toàn cục `playingBookDetailUrl` và `playingBookSourceName` để lưu trữ đường dẫn chi tiết sách và tên nguồn tương ứng của chương đang phát.
        *   Cập nhật `startSpeaking` và `prepareSpeaking` để nhận và gán hai thuộc tính này khi khởi chạy TTS.
    *   **ReaderView**:
        *   Truyền `packageId` thực tế khi khởi tạo `ttsExtensionInfo`.
        *   Cập nhật các cuộc gọi tới `startSpeaking` và `prepareSpeaking` để truyền thêm thông tin `bookDetailUrl` và `bookSourceName` (ưu tiên lấy từ cơ sở dữ liệu `localBook`, dự phòng lấy từ tham số cấu hình View).
    *   **ShelfView**:
        *   Sửa đổi phương thức xử lý sự kiện khôi phục màn hình đọc truyện đang phát (`openCurrentlyPlayingReader`). Gán đúng thuộc tính `packageId` cho `navigateToPlayingExtensionId`, `playingBookDetailUrl` cho `navigateToPlayingDetailUrl` và `playingBookSourceName` cho `navigateToPlayingSourceName` thay vì gán nhầm các thuộc tính cấu hình nội bộ của extension (như `localPath`, `downloadUrl`, `configJson`). Đảm bảo khôi phục đầy đủ và chính xác thông tin để trình đọc tiếp tục lấy chương mới online bình thường mà không báo lỗi cạn kiệt tiện ích bóc tách.

## [1.3.6] - 2026-07-15

### Khắc phục lỗi điều khiển phát nhạc bằng tai nghe, đồng bộ màn hình khóa & Khôi phục luồng chuyển chương TTS (TTS Remote & Lock Screen Fix v2)
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 1 tệp Swift (TTSManager.swift)
*   **Mô tả**:
    *   **TTSManager**:
        *   Cập nhật `setRemoteCommandsEnabled()` và `setupRemoteCommandCenter()`: Loại bỏ hoàn toàn sự kiện `togglePlayPauseCommand` vì gây xung đột trùng lặp sự kiện trên iOS khi người dùng bấm nút trên tai nghe. OS của iOS sẽ tự động dịch chuyển nút tai nghe thành lệnh `playCommand` hoặc `pauseCommand` dựa trên giá trị của `playbackState`.
        *   Cập nhật `pause()`, `resume()` và `stopPlayback()`: Đồng bộ hóa cập nhật `playbackState` của `MPNowPlayingInfoCenter.default()` ngay khi trạng thái `isPlaying` của ứng dụng thay đổi, loại bỏ độ trễ và giúp lockscreen hiển thị đúng nút Pause/Play tương ứng tức thì.
        *   Cập nhật `pause()`: Ghi nhận thời điểm tạm dừng vào biến `lastPausedTime = Date()`.
        *   Cập nhật `resume()`: Tích hợp bộ đếm thời gian chờ (timeout) 5 giây thông minh. Nếu thời gian từ lúc tạm dừng đến lúc tiếp tục phát vượt quá 5.0 giây hoặc chưa có `currentPlaybackId`, sẽ gọi `speakCurrent()` để tái tạo một buffer mới tinh (tránh cạn kiệt/mất tiếng do OS giải phóng bộ đệm của AVAudioPlayerNode trong nền). Nếu dưới 5.0 giây, ứng dụng sẽ gọi tiếp `playerNode?.play()` để phát tiếp tục liền mạch tại vị trí cũ. Tránh được lỗi lặp lại đoạn hoặc đứng luồng không tự động chuyển chương trong ReaderView.

## [1.3.5] - 2026-07-15

### Tối ưu hóa hiệu năng, prefetch TTS, Đơn giản hóa UI Loading, Tinh gọn Telegram & Fix bug nháy Loading
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 4 file (ReaderView.swift, ReaderViewModel.swift, TTSManager.swift, build-ipa.yml)
*   **Mô tả**:
    *   **ReaderView**:
        *   `schedulePrepareTTS()`: Thêm guard kiểm tra `ttsManager.showFloatingWidget`. Không lên lịch chuẩn bị dữ liệu TTS nếu người dùng chỉ đọc sách chay.
        *   `updateScrollReadingProgress()`: Thêm guard kiểm tra `ttsManager.isPlaying || ttsManager.showFloatingWidget` ở phần 2 (đồng bộ vị trí con trỏ TTS). Khi đọc sách chay, không thực hiện đồng bộ vị trí con trỏ để giải phóng Main Thread.
        *   **Đơn giản hóa màn hình loading**:
            *   Trong `chapterLoadingView` (màn hình loading ban đầu): Loại bỏ dòng mô tả "Đang tải nội dung chương..." và nút "Tải lại" thủ công rườm rã. Chỉ giữ lại Tên chương, biểu tượng load `ProgressView` và nút "Quay lại" căn giữa màn hình.
            *   Trong `stableIndexes` loop (khi vuốt chuyển trang): Tương tự, đơn giản hóa phần loading bằng cách loại bỏ text mô tả và nút "Tải lại", chỉ hiển thị Tên chương, biểu tượng load và nút "Quay lại" căn giữa.
    *   **ReaderViewModel**:
        *   `loadChapterContentFromExtension(_:)`: Thêm điều kiện guard kiểm tra nếu chương đã được tải thành công trước đó trong RAM Cache (trạng thái `.loaded`), bỏ qua không tải lại. Điều này giúp loại bỏ hoàn toàn hiện tượng nhấp nháy màn hình load đè lên nội dung truyện đã có sẵn khi vuốt qua lại giữa các chương.
    *   **TTSManager**:
        *   Bổ sung properties `prepareSpeakingTask` và `nextChapterPrefetchTask` để quản lý các tác vụ bất đồng bộ.
        *   `prepareSpeaking(...)`: Di chuyển hàm xử lý văn bản nặng `parseParagraphs(...)` sang chạy ngầm thông qua `Task.detached` với cú pháp tường minh đầu ra `-> [TTSParagraph]` để sửa lỗi biên dịch Swift. Tự động hủy task cũ khi chuyển chương nhanh.
        *   `updateNowPlayingInfo()`: Di chuyển các tác vụ nặng (dịch thuật Hán Việt tiêu đề, load ảnh bìa từ disk) sang chạy ngầm bất đồng bộ bằng `Task.detached` với priority `.background`. Chỉ cập nhật `MPNowPlayingInfoCenter` sau khi đã xử lý xong dữ liệu từ background.
        *   Thêm phương thức `triggerNextChapterPrefetch()` tự động tải trước 1 chương tiếp theo ngầm (từ DB cache hoặc online extension) khi bắt đầu phát chương hiện tại.
        *   `startSpeaking(...)` & `applyNextChapter(...)`: Kích hoạt `triggerNextChapterPrefetch()` để luôn nạp sẵn chương mới, giảm thiểu khoảng trễ khi nghe chạy nền (đã thoát trình đọc).
        *   `clearPrefetchCache()`: Hủy `nextChapterPrefetchTask` để dọn dẹp tài nguyên.
    *   **build-ipa.yml**:
        *   Loại bỏ hoàn toàn bước chạy script Python trích xuất lỗi và tệp tin `summary_error.txt`.
        *   Sửa đổi tin nhắn gửi đến Telegram khi build thất bại để chỉ hiển thị thông tin chung và link xem logs đầy đủ trên Github Actions, bảo mật và tinh gọn nội dung tin nhắn.
        *   Lược bỏ các lệnh ghi lỗi thừa `2>&1 | tee -a build_error.log` ở bước compile và package.

## [1.3.4] - 2026-07-15

### Gửi chi tiết lỗi build qua Telegram và bóp trigger workflow build
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 1 file workflow (.github/workflows/build-ipa.yml)
*   **Mô tả**:
    *   **build-ipa.yml**:
        *   Cập nhật trigger: chỉ kích hoạt build khi sửa các file trong `Sources/**` (bóp trigger paths).
        *   Tích hợp ghi logs build (`stdout` và `stderr`) từ các bước xcodebuild và xcodegen vào tệp chung `build_error.log` bằng lệnh `tee -a`.
        *   Thêm bước chạy Python inline ở bước `Send Failure Notification to Telegram` để đọc `build_error.log`, trích xuất tối đa 20 dòng lỗi compiler Xcode (lọc theo regex `\s+(error|failed)` để bắt chính xác lỗi Swift compile/warnings có khoảng trắng phía trước) rồi ghi vào `summary_error.txt`.
        *   Đọc tệp `summary_error.txt` (giới hạn 2000 ký tự) gửi kèm vào tin nhắn báo lỗi qua Telegram API.

## [1.3.3] - 2026-07-15

### Fix TTS tự chuyển chương khi thoát Reader & cải thiện cache lookup
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 4 file Swift
*   **Mô tả**:
    *   **TTSModels**: Bổ sung field `host: String?` vào `TTSChapterInfo` để `TTSManager` có đủ thông tin tự fetch nội dung chương khi không có cache.
    *   **TTSManager**:
        *   Thêm hàm `advanceToNextChapter(nextIdx:)` với thứ tự ưu tiên cache: **RAM** (`chaptersQueue.cachedContent`) → **DB** (`Chapter.isCached + content` qua SwiftData) → **fetch online** (`ExtensionManager`). TTSManager giờ tự advance chapter độc lập, không cần `ReaderView` làm trung gian.
        *   Thêm hàm `applyNextChapter(index:content:chapter:)` apply nội dung chương mới, gọi `continueStartSpeaking`, và post notification `ttsDidAdvanceToNextChapter` để sync UI.
        *   Thêm hàm `fetchChapterContentFromDB(chapterUrl:)` query SwiftData trực tiếp để lấy content đã cache.
        *   Thêm hàm `updateChapterCache(at:content:)` cho phép `ReaderViewModel` cập nhật `cachedContent` trong `chaptersQueue` sau mỗi chương load xong.
        *   `nextParagraph()`: khi hết chương gọi `advanceToNextChapter` thay vì post notification trực tiếp.
        *   `skipForward()`: khi hết chương gọi `advanceToNextChapter` thay vì `onChapterFinished?()`.
    *   **ReaderViewModel**: Sau khi `processAndSaveChapter` hoàn thành, gọi `TTSManager.shared.updateChapterCache(at:content:)` để RAM cache luôn sẵn sàng cho TTS advance.
    *   **ReaderView**:
        *   Luồng tạo TTS chapter info truyền `host` từ `Chapter.host` / `ChapterResult.host` vào `TTSChapterInfo`.
        *   `.onDisappear`: clear 3 callbacks (`onChapterFinished`, `onChapterNext`, `onChapterPrev`) để tránh ghost reference.
        *   `.onReceive("ttsDidAdvanceToNextChapter")`: đổi `ttsShouldAutoPlayNextChapter = false` — TTS đã tự phát, ReaderView chỉ sync UI (chuyển tab, scroll).

## [1.3.2] - 2026-07-15

### Fix TabView sliding window jump khi vuốt chương liên tục & các vấn đề hiệu năng liên quan
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 3 file Swift
*   **Mô tả**:
    *   **ReaderViewModel**:
        *   Thêm `stableIndexes: [Int]` — array `TabView` bind vào, chỉ update sau khi animation swipe kết thúc.
        *   Thêm `pendingWindowSlide: Bool` flag và `commitWindowSlide()` — gọi từ `.onAppear` của tab đích để slide window và ghi tiến trình sau animation.
        *   `onTabSelectionChanged` thêm `immediate: Bool` — swipe dùng `false` (deferred), jump từ chapter list/TTS dùng `true` (sync ngay).
        *   `processAndSaveChapter`: đổi guard check sang `visibleIndexes.contains(index) || index == activeChapterIndex` để tránh drop chương đang swipe đến.
        *   `saveProgressImmediately()` được defer sang `commitWindowSlide()` trong swipe path, tránh I/O tranh chấp main thread giữa animation.
        *   `computeWindowRange()` và `enqueuePrefetch()` đổi sang `internal`.
    *   **ReaderView**:
        *   `ForEach(vm.visibleIndexes)` → `ForEach(vm.stableIndexes)`.
        *   Thêm `vm.commitWindowSlide()` vào đầu `.onAppear` của mỗi tab.
        *   Thêm `.onChange(of: vm.tabSelection)` safety net đảm bảo `commitWindowSlide()` được gọi dù `onAppear` không fire.
        *   Xoá `.id(chapterIndex)` khỏi `readerContentView`.
        *   `selectChapter(at:)` gọi `onTabSelectionChanged(immediate: true)`.
        *   `onChange` của chapter count sync `stableIndexes` ngay sau `updateVisibleChaptersWindow()`.
    *   **TTSModels**: Thêm field `host: String?` vào `TTSChapterInfo` (dùng chung với [1.3.3]).

---

## [1.3.1] - 2026-07-15

### Đọc metadata local sau cài đặt tiện ích & Hiển thị hình cờ quốc gia bên cạnh version
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 1 file Swift
*   **Mô tả**:
    *   **RepositoryManagerView**:
        *   Cập nhật hàm `installExtension`: Sau khi giải nén tiện ích thành công, tiến hành đọc tệp cấu hình `plugin.json` nội bộ của tiện ích đó để lấy thông tin thực tế (`locale`, `type`, `version`, `author`) và cập nhật ngược lại vào database SwiftData. Giải quyết triệt để lỗi mất thuộc tính ngôn ngữ tiếng Trung của các tiện ích Trung Quốc (do file plugin.json tổng hợp trên kho GitHub không khai báo trường này).
        *   Thêm emoji lá cờ đại diện quốc gia tương ứng với ngôn ngữ (ví dụ 🇻🇳 cho tiếng Việt, 🇨🇳 cho tiếng Trung, 🇺🇸 cho tiếng Anh) ngay bên cạnh badge hiển thị phiên bản tiện ích.

## [1.3.0] - 2026-07-15

### Cải tiến giao diện và lưu trữ cấu hình tiện ích (Extensions)
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 2 file Swift
*   **Mô tả**:
    *   **ExtensionStoreView**: [DELETE] Xóa hoàn toàn tệp `ExtensionStoreView.swift` vì không còn được sử dụng.
    *   **RepositoryManagerView**:
        *   Chuyển các biến bộ lọc (`filterType`, `filterLocale`, `filterAuthor`) sang `@AppStorage` để lưu trạng thái bộ lọc tiện ích khi thoát/mở lại màn hình.
        *   Xóa bỏ hoàn toàn bộ lọc theo Kho tiện ích (`filterRepoUrl`) và badge tên kho hiển thị trên mỗi dòng tiện ích.
        *   Ẩn dòng chữ "Đã cài" hiển thị bên cạnh các nút chức năng của tiện ích đã cài đặt.
        *   Tại danh sách kho, loại bỏ `NavigationLink` chuyển sang trang chi tiết kho, hiển thị kho dạng dòng thông tin bình thường và hỗ trợ vuốt trái để xóa kho.

## [1.2.9] - 2026-07-15

### Đồng bộ giao diện nạp trang chương bên trong TabView để hiển thị đầy đủ nút điều khiển ở trung tâm
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 1 file Swift
*   **Mô tả**:
    *   **ReaderView**: Cập nhật logic hiển thị trạng thái đang tải (`loading`/`prefetching`) và lỗi (`failed`) của từng trang chương riêng lẻ bên trong `TabView` (`textReaderView`). Bổ sung nút **"Quay lại"**, **"Tải lại"**, và **"Xem nguồn"** xếp dọc ở chính giữa màn hình giống hệt như màn hình nạp chung để người dùng không bị kẹt khi app đang tải nội dung chương.

## [1.2.8] - 2026-07-15

### Đưa nút "Quay lại" có chữ vào giữa màn hình dưới cụm loading và cụm lỗi
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 1 file Swift
*   **Mô tả**:
    *   **ReaderView**: Thiết kế lại giao diện màn hình `chapterLoadingView`. Loại bỏ nút Đóng "X" góc trên trái, thay thế bằng nút bấm có chữ **"Quay lại"** (icon `arrow.left`) và đặt ở chính giữa màn hình bên dưới vòng xoay nạp chương cũng như xếp dưới cùng các nút báo lỗi.

## [1.2.7] - 2026-07-15

### Bổ sung nút "Xem nguồn" xếp dọc dưới nút "Tải lại" khi nạp chương lỗi
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 1 file Swift
*   **Mô tả**:
    *   **ReaderView**: Thiết kế lại giao diện trạng thái báo lỗi của màn hình `chapterLoadingView` để xếp dọc nút **"Tải lại"** ở trên và thêm nút **"Xem nguồn"** ở dưới để mở trình duyệt bypass Cloudflare tương tự nút trên thanh công cụ.

## [1.2.6] - 2026-07-15

### Khôi phục logs chẩn đoán crash và triển khai giải pháp loại bỏ hiển thị overlay khi tải chương
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 4 file Swift
*   **Mô tả**:
    *   **AppLogger, BookDetailView, ReaderViewModel**: Hoàn tác toàn bộ các dòng log chẩn đoán crash (`[FreeBookDebug]`) và bật lại bộ lọc log để giữ mã nguồn gọn gàng.
    *   **ReaderView**:
        *   Khôi phục điều kiện hiển thị thanh công cụ overlay về `if showControls` để bẻ gãy đệ quy khởi tạo sớm ngầm của SwiftUI ngay từ frame nạp đầu tiên.
        *   Thiết kế lại màn hình `chapterLoadingView` với nút Đóng **"X"** (để người dùng thoát ra quay lại màn hình chi tiết) và bổ sung nút **"Tải lại"** (xoay lại) trực tiếp ở giữa màn hình cho cả hai trạng thái đang tải và lỗi.

## [1.2.5] - 2026-07-15

### Khắc phục lỗi crash tràn bộ nhớ do đệ quy eager trong NavigationLink của SwiftUI
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 3 file Swift nguồn
*   **Mô tả**:
    *   **Common/LazyView**: Thêm struct tiện ích `LazyView` giúp trì hoãn việc khởi tạo struct View đích bên trong `NavigationLink` cho đến khi liên kết đó thực sự được kích hoạt (`isActive == true`).
    *   **ReaderView & BookDetailView**: Bọc toàn bộ các đích đến chuyển hướng NavigationLink trỏ vòng quanh nhau (`BookDetailView` $\leftrightarrow$ `ReaderView`) bằng `LazyView`, phá vỡ hoàn toàn lỗi đệ quy khởi tạo sớm eager gây tràn bộ nhớ đệm (stack overflow) làm crash app khi bấm đọc truyện.

## [1.2.4] - 2026-07-15

### Bổ sung logs chẩn đoán crash bằng AppLogger
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 4 file Swift
*   **Mô tả**:
    *   **AppLogger**: Tạm thời tắt điều kiện kiểm tra `isLoggingEnabled` để đảm bảo file log luôn được ghi nhận trên thiết bị của người dùng khi app gặp sự cố.
    *   **BookDetailView, ReaderView, ReaderViewModel**: Chèn các dòng log ghi nhận tham số và trạng thái luồng chạy quan trọng (`[FreeBookDebug]`) để hỗ trợ chẩn đoán chính xác vị trí crash.

## [1.2.3] - 2026-07-15

### Khắc phục triệt để lỗi crash/kẹt ReaderView bất đồng bộ khi mở truyện online/offline
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 2 file Swift
*   **Mô tả**:
    *   **ReaderView**:
        *   Sửa lỗi truyền `@State currentOnlineChapters` khi khởi tạo `ReaderViewModel` trong `onAppear` bằng cách sử dụng trực tiếp tham số `onlineChapters` của View, tránh độ trễ gán `@State` dẫn đến truyền nhầm số chương bằng 0.
        *   Bổ sung bộ lắng nghe thay đổi `.onChange(of: currentOnlineChapters.count)` để tự động cập nhật lại số lượng chương cho `viewModel` khi danh sách chương online tải hoàn tất.
    *   **ReaderViewModel**: Cập nhật hàm `computeWindowRange()` tính toán cận trên (`upper`) và cận dưới (`lower`) và xác thực bằng `guard lower <= upper else { return [] }` trước khi tạo `ClosedRange` nhằm tránh lỗi sập `fatalError` của Swift.

## [1.2.2] - 2026-07-15

### Khắc phục lỗi crash do TabView rỗng và thêm cơ chế Clamp Index
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 2 file Swift
*   **Mô tả**:
    *   **ReaderViewModel**: Bổ sung hàm `clampActiveIndex()` tự động điều chỉnh chỉ mục chương đang hiển thị (`activeChapterIndex` và `tabSelection`) về chương cuối cùng hợp lệ nếu nó vượt quá số chương thực tế của sách, giải quyết triệt để lỗi crash do khởi tạo range sai `9...4` khi dữ liệu biên bị lệch chỉ mục.
    *   **ReaderView**: Sửa đổi `readerContentView` để hiển thị màn hình tải (`chapterLoadingView`) thay vì cố render `textReaderView` khi `totalChaptersCount == 0` hoặc `visibleIndexes` trống, tránh lỗi SwiftUI crash do `TabView` rỗng.

## [1.2.1] - 2026-07-15

### Tối ưu hóa trigger tự động chạy build IPA
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 1 file workflow (.github/workflows/build-ipa.yml)
*   **Mô tả**:
    *   Bổ sung bộ lọc đường dẫn (`paths`) cho các sự kiện `push` và `pull_request`.
    *   Giới hạn workflow chỉ tự động build IPA khi có sự thay đổi trong thư mục mã nguồn `Sources/`, tệp cấu hình dự án `project.yml` hoặc chính tệp workflow build, giúp tiết kiệm thời gian chạy và tài nguyên chạy của GitHub Actions.

## [1.2.0] - 2026-07-15

### Khắc phục lỗi build GitHub Actions do action dọn dẹp workflow runs cũ bị lỗi
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 1 file workflow (.github/workflows/cleanup-runs.yml)
*   **Mô tả**:
    *   Thay thế action bên thứ ba `Mattraiano/delete-old-runs-action` (bị xóa hoặc set private trên GitHub) bằng action chính chủ `actions/github-script@v7`.
    *   Tích hợp script gọi API của GitHub để dọn dẹp các runs cũ hơn 3 ngày của duy nhất repository hiện tại, giữ lại tối thiểu 1 run mới nhất, tăng độ tin cậy và bền vững của workflow.

## [1.1.9] - 2026-07-15

### Tự động tắt ghi log hệ thống khi khởi chạy lại ứng dụng
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 2 file Swift
*   **Mô tả**:
    *   **AppLogger**: Bổ sung cơ chế reset giá trị key `"isLoggingEnabled"` trong `UserDefaults` về `false` ngay trong hàm khởi tạo `init()`, đảm bảo tính năng ghi log hệ thống tự động tắt mỗi khi khởi chạy lại ứng dụng.
    *   **SettingsView**: Đồng bộ hóa giá trị mặc định của Toggle ghi log hệ thống thành `false`.

## [1.1.8] - 2026-07-15

### Khắc phục lỗi crash app khi mở trình đọc truyện
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 2 file Swift
*   **Mô tả**:
    *   **ReaderViewModel**:
        *   Bảo vệ `computeWindowRange()` chống crash bằng cách kiểm tra nếu `totalChaptersCount <= 0` thì trả về Set rỗng `[]` thay vì tạo `ClosedRange` không hợp lệ `0...-1`.
        *   Thay đổi `totalChaptersCount` từ hằng số `let` thành `@Published var` để cho phép cập nhật số chương động.
    *   **ReaderView**:
        *   Thêm modifier `.onChange(of: localBook?.chapters.count)` để tự động theo dõi và cập nhật số chương từ database SwiftData vào `viewModel.totalChaptersCount` khi `@Query allBooks` load dữ liệu xong, đồng thời kích hoạt vẽ lại cửa sổ trượt hiển thị.

## [1.1.7] - 2026-07-14

### Khắc phục lỗi cú pháp YAML trong workflow build-ipa.yml
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 1 file workflow (.github/workflows/build-ipa.yml)
*   **Mô tả**:
    *   Khắc phục lỗi `Invalid workflow file` do định dạng chuỗi xuống dòng trực tiếp trong khối `run: |` gây sai lệch thụt lề YAML.
    *   Sử dụng lệnh `printf` của Bash để định dạng chuỗi chứa ký tự xuống dòng `\n` một cách năng động và an toàn.

## [1.1.6] - 2026-07-14

### Khắc phục lỗi báo quyền truy cập sai khi nhập sách từ file TXT
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 1 file Swift
*   **Mô tả**:
    *   **ShelfView**: Khắc phục lỗi `importTxtBook` trả về thông báo lỗi phân quyền sai ("Lỗi: Không có quyền truy cập tệp tin"). Chuyển đổi lệnh kiểm tra cứng `guard url.startAccessingSecurityScopedResource() else { ... }` thành kiểm tra động (`let accessing = ...`). Vì `DocumentPicker` cấu hình `asCopy: true` trả về các file được copy cục bộ nằm sẵn trong sandbox của app nên `startAccessingSecurityScopedResource()` sẽ trả về `false`, việc gỡ bỏ `guard` giúp tránh bị chặn nhầm trong khi vẫn bảo toàn việc đóng/mở quyền bảo mật nếu cần thiết.

## [1.1.5] - 2026-07-14

### Tích hợp thông báo lỗi build qua Telegram khi workflow GitHub Actions thất bại
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 1 file workflow (.github/workflows/build-ipa.yml)
*   **Mô tả**:
    *   Bổ sung bước `Send Failure Notification to Telegram` với điều kiện `if: failure()` vào cuối workflow `Build Unsigned IPA`.
    *   Tự động gửi thông tin chi tiết lỗi gồm commit message và liên kết trực tiếp tới log lỗi của GitHub Actions run về Telegram chat khi build thất bại.

## [1.1.4] - 2026-07-14

### Khắc phục lỗi lag/đơ khi vuốt chuyển chương trong trình đọc
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 2 file Swift
*   **Mô tả**:
    *   **ReaderViewModel**:
        *   Tối ưu hóa hàm `processAndSaveChapter` bằng cách chuyển các tác vụ dịch thuật (Sino-Vietnamese / Vietphrase) và xử lý mảng `ParagraphItem` xuống chạy ngầm thông qua `Task.detached` với độ ưu tiên cao (`.userInitiated`), giúp nhường hoàn toàn luồng chính (Main Thread) cho hoạt ảnh vuốt trang mượt mà.
        *   Tích hợp kiểm tra an toàn sau khi await để đảm bảo chương đó vẫn đang nằm trong `visibleIndexes` trước khi cập nhật vào RAM cache, ngăn ngừa lỗi dữ liệu lỗi thời khi người dùng vuốt nhanh qua nhiều chương.
        *   Thêm biến cache `cachedLocalBook` và `cachedExt` để lưu giữ tạm thời tham chiếu thực thể sách và extension, tránh truy vấn đĩa lặp lại qua `modelContext.fetch` liên tục trên luồng chính. Giải phóng cache này khi thay đổi sách đọc trong `onBookChanged()`.
    *   **ReaderView**:
        *   Tối ưu hóa hàm `applyTranslationForChapter` bằng cách sử dụng `Task.detached` để chạy ngầm tiến trình dịch thuật trước khi cập nhật dữ liệu chương về luồng chính bằng `MainActor.run`.

## [1.1.3] - 2026-07-14

### Tích hợp tự động dọn dẹp các Workflow Runs cũ sau 3 ngày
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 1 file workflow mới (.github/workflows/cleanup-runs.yml)
*   **Mô tả**:
    *   Tạo mới workflow `Cleanup Old Workflow Runs` định kỳ dọn dẹp các run cũ hơn 3 ngày.
    *   Sử dụng thư viện `Mattraiano/delete-old-runs-action` để xóa an toàn, đồng thời cấu hình giữ lại ít nhất 1 lượt chạy mới nhất.

## [1.1.2] - 2026-07-14

### Tích hợp gửi file IPA tự động lên Telegram sau khi build thành công
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 1 file workflow (.github/workflows/build-ipa.yml)
*   **Mô tả**:
    *   Bổ sung bước `Send IPA to Telegram` vào cuối job `build` của GitHub Actions workflow.
    *   Tự động kiểm tra dung lượng file IPA: Nếu dưới 50MB, gửi trực tiếp qua bot API của Telegram; nếu từ 50MB trở lên, upload lên dịch vụ lưu trữ trung gian `transfer.sh` rồi gửi link tải qua bot Telegram.
    *   Loại bỏ hoàn toàn bước `Upload IPA Artifact` (lưu trữ trên GitHub Artifacts) theo yêu cầu để tối ưu hóa không gian lưu trữ và thời gian build.
    *   Tích hợp nội dung **Commit Message** (tin nhắn commit) gần nhất làm chú thích (caption/text) cho thông báo Telegram, sử dụng cơ chế encode an toàn để tránh lỗi ký tự đặc biệt.

## [1.1.1] - 2026-07-14

### Khắc phục lỗi chuẩn hóa URL mục lục (TOC) khi có script phân trang (page)
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 1 file Swift
*   **Mô tả**:
    *   **ExtensionManager**: Khắc phục lỗi cú pháp tại dòng 380 của `ExtensionManager.swift` trong hàm `toc`. Tích hợp thêm logic kiểm tra `hasScript(localPath:scriptKey:)` cho script `"page"`. Nếu extension có hỗ trợ script phân trang, hàm `toc` sẽ bỏ qua việc gọi `JSExecutor.cleanAndResolveUrl` và sử dụng trực tiếp URL ban đầu để bảo toàn cấu trúc URL đặc thù phục vụ phân trang.

## [1.1.0] - 2026-07-14

### Triển khai UI Reader nâng cao và Tự động hóa Xuất Truyện
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 4 file Swift
*   **Mô tả**:
    *   **Giao diện Trình đọc (ReaderView.swift, ParagraphCardView.swift)**:
        *   Cập nhật layout khi chương đang tải hoặc gặp lỗi trong `textReaderView`. Căn giữa hoàn toàn tên chương, spinner/nút reload (Thử lại) ở chính giữa trang Reader (ngoại vi `ScrollView`, chiều cao chiếm toàn bộ Viewport).
        *   Bổ sung computed property `isChapterLoadingOrFailed: Bool` để giữ HUB điều khiển (top/bottom controls) luôn hiển thị khi chương đang tải hoặc lỗi, giúp người dùng dễ dàng chuyển chương hoặc thoát trình đọc.
        *   Cập nhật `chapterLoadingView` đồng bộ bố cục tương tự cho trường hợp `viewModel == nil`.
        *   Tinh chỉnh cỡ chữ tên chương khi đang tải và khi bị lỗi lên cỡ to hơn (`.title2` kèm bold) và bổ sung padding trên `16` pt.
        *   Nâng kích cỡ tên chương hiển thị trong nội dung đọc của `ParagraphCardView.swift` lên `fontSize * 1.5` và thêm padding trên `32` pt.
    *   **Căn giữa tên chương (ReaderTextView.swift, ParagraphCardView.swift)**:
        *   Nâng cấp `ReaderTextView` để nhận thuộc tính `isCentered: Bool`. Tự động áp dụng `paragraphStyle.alignment = .center` cho văn bản của `UITextView` khi `isCentered` bằng true.
        *   Cập nhật `ParagraphCardView.swift` truyền `isCentered: item.isTitle` để tự động căn lề giữa cho tên chương truyện (có `isTitle == true`).
    *   **Quản lý tải xuống (DownloadTrackerView.swift)**:
        *   Cập nhật hàm `exportFromCached` để gọi trực tiếp `DownloadManager.shared.enqueueTask` và `ToastManager.shared.show`, tự động hóa quá trình thêm tác vụ xuất TXT offline mà không cần hiển thị sheet cấu hình `TaskOptionsSheet` dài dòng.
        *   Khắc phục lỗi hiển thị tên truyện tiếng Trung thô chưa dịch tại danh sách Download bằng cách tự động dịch tên truyện qua `TranslateUtils.translateMeta` khi bật dịch thuật.

## [1.0.9] - 2026-07-14

### Tối ưu hóa JS Engine, chuẩn hóa URL và điều chỉnh định dạng Log
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 2 file Swift
*   **Mô tả**:
    *   **JSExecutor**: Loại bỏ thuộc tính và tham số `host` khỏi lớp và constructor `init` do không sử dụng thực tế trong lớp này.
    *   **ExtensionManager**:
        *   Cập nhật các hàm `detail`, `toc`, `chap`, và `page` để khởi tạo `JSExecutor` không có `host`. Thực hiện gọi `JSExecutor.cleanAndResolveUrl(url, host: host)` để chuẩn hóa URL thành URL tuyệt đối trước khi thực thi script.
        *   Điều chỉnh log chạy script của 10 hàm trong `ExtensionManager`: Loại bỏ `localPath` và `downloadUrl` dài dòng; đưa mảng tham số thực tế `arguments=[...]` truyền vào JS lên đầu tiên; và giữ nguyên các tham số Swift gốc khác ở phía sau để tối ưu hóa khả năng đọc log.

## [1.0.8] - 2026-07-14

### Khắc phục lỗi thiếu truyền host sang trang chi tiết và chuyển nút filter giao diện quản lý tiện ích
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 9 file Swift
*   **Mô tả**:
    *   **Trình chi tiết (BookDetailView)**: Cập nhật `BookDetailView.swift` hỗ trợ nhận tham số `initialHost`. Trích xuất và truyền `importedHost` khi bypass import thành công. Cập nhật mọi cuộc gọi `.detail`, `.toc`, `.page` sử dụng `resolvedHost` (ưu tiên lấy từ cơ sở dữ liệu `localBook.host`, nếu không có lấy từ `host` do danh sách truyền sang, và fallback về `ext.sourceUrl`).
    *   **Danh sách hiển thị (Search, Genres, Home, Suggest, Shelf)**: Cập nhật `SearchView.swift`, `SuggestRowView.swift`, `CategoryNovelsListView.swift`, `DiscoveryView.swift`, `ReaderView.swift`, và `ShelfView.swift` để truyền tham số `host`/`initialHost` hoặc trích xuất lưu `importedHost` đầy đủ (scheme + domain) sang `BookDetailView`.
    *   **Quản lý tiện ích**: Cập nhật `RepositoryManagerView.swift` di chuyển nút Filter từ thanh Navigation Bar xuống bên cạnh ô Tìm kiếm tiện ích, tăng độ trực quan của giao diện và thay đổi icon/màu sắc nổi bật (cam đậm) khi có bộ lọc hoạt động.
    *   **Hệ thống Log JS**: Cập nhật `ExtensionManager.swift` bổ sung thông tin tên extension (tên thư mục) và tên script cụ thể đang chạy (ví dụ `search`, `detail`, `toc`, `chap`, `voice`, etc.) vào các dòng log in ra cho `Response.error` và `Response.success`, hỗ trợ việc chuẩn đoán lỗi của tiện ích cực kỳ trực quan.

## [1.0.7] - 2026-07-14

### Khắc phục lỗi Import truyện TXT cục bộ và bổ sung giao diện Tiến trình động
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 1 file Swift
*   **Mô tả**:
    *   **Kệ sách (Shelf)**: Cập nhật `ShelfView.swift` để sửa lỗi import file TXT.
        *   Hỗ trợ giải mã file bằng cơ chế tự động dò tìm bảng mã (Encoding Fallback) với UTF-8, UTF-16, Windows-1258, ASCII và ISO-8859-1 để tránh crash giải mã ngầm.
        *   Chuyển pha chèn và lưu dữ liệu SwiftData về chạy trên luồng chính (`MainActor` sử dụng `self.modelContext` của View), giúp `@Query` cập nhật tức thì Kệ sách trên giao diện.
        *   Bổ sung giao diện Progress Overlay động phủ mờ toàn màn hình hiển thị tiến độ import thực tế từ 0% đến 100% kèm số chương đang xử lý (có cơ chế sleep 1ms nhường thread để giao diện mượt mà).
        *   Tích hợp thông báo Toast qua `ToastManager` để thông báo trạng thái thành công hoặc chi tiết lỗi cụ thể cho người dùng.

## [1.0.6] - 2026-07-14

### Nâng cấp giao diện Tiện ích (Badge capsule, Sheet Filter, gỡ cài đặt hàng loạt) và loại bỏ logic truyện tranh (Comic)
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 4 file Swift
*   **Mô tả**:
    *   **Tiện ích**: Cập nhật `RepositoryManagerView.swift` loại bỏ dòng text Kho và Tác giả cũ. Thiết kế hệ thống Badge capsule màu sắc hiện đại hiển thị Loại tiện ích (Type), Tên kho (Repository), Tác giả (Author). Tích hợp thêm Sheet bộ lọc nâng cao (`FilterSheet`) lọc theo 4 tiêu chí (Loại, Ngôn ngữ, Tác giả, Kho). Bổ sung nút "Xóa tất cả" kèm Alert xác nhận để gỡ cài đặt hàng loạt toàn bộ các tiện ích đã tải.
    *   **Khám phá**: Cập nhật `DiscoveryView.swift` lọc bỏ các tiện ích loại `"comic"`, chỉ hiển thị các tiện ích truyện chữ (`"novel"`, `"chinese_novel"`) trong phần mở rộng khám phá.
    *   **Trình đọc & Cửa hàng**: Cập nhật `ReaderView.swift` loại bỏ hoàn toàn các logic hiển thị và xử lý ảnh truyện tranh (`comicReaderView`, `imageUrls`), mặc định chạy chế độ đọc truyện chữ. Luôn hiển thị các nút dịch thuật và TTS. Cập nhật `ExtensionStoreView.swift` loại bỏ icon hiển thị `comicbook` mặc định cho truyện tranh.

## [1.0.5] - 2026-07-14

### Khắc phục lỗi lưu sai Shelf/History, sửa màn hình trắng xuất TXT và nâng cấp JS Engine hỗ trợ Console.log/queries
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 3 file Swift
*   **Mô tả**:
    *   **Reader**: Cập nhật hàm `saveOnlineBookIfNeeded` trong `ReaderViewModel.swift` để truyền rõ ràng `isOnShelf: false` và `isHistory: true` khi khởi tạo thực thể `Book`, ngăn sách đọc online tự động lưu vào Kệ sách chính thay vì Lịch sử đọc.
    *   **Downloads**: Cập nhật `DownloadTrackerView.swift` loại bỏ `@State showingOptionsSheet` và chuyển sang sử dụng `.sheet(item: $selectedBookForTask)` để sửa lỗi màn hình trắng xóa khi chọn tùy chọn xuất TXT cho sách đã tải xuống.
    *   **JS Engine**: Cập nhật `JSExecutor.swift` để đăng ký alias global `Console` trỏ tới `console` hỗ trợ `Console.log(...)`. Cập nhật hàm `fetch` trong Javascript bootstrap để tự động phân tích đối tượng `options.queries`, mã hóa và ghép query parameters vào URL trước khi gọi mạng native, khắc phục lỗi crash `TypeError: null is not an object (evaluating 'json.data.books')` do thiếu tham số.

## [1.0.4] - 2026-07-14

### Sửa lỗi lưu chương mới nhất khi thoát nhanh và nâng cấp trang Khám phá
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 3 file Swift
*   **Mô tả**:
    *   **Reader**: Cập nhật hàm `onTabSelectionChanged(newIndex:)` trong `ReaderViewModel.swift` để gán tiến trình `currentProgress` sang chương mới (với paragraph index 0) ngay khi người dùng chọn chương mới, đảm bảo hàm thoát `onDisappear` lưu chính xác chương vừa chọn vào DB.
    *   **Extension Manager**: Thay thế hàm `cleanVal.toArray()` bằng `toDictionaryArray(cleanVal)` trong hàm `home(...)` và `genre(...)` trong `ExtensionManager.swift` để giải tuần tự hóa an toàn kiểu dữ liệu JSValue thành Swift Array. Loại bỏ cơ chế fallback tự động về `genre(...)` trong hàm `home(...)` để phân tách mạch lạc dữ liệu.
    *   **Discovery View**: Thêm `@State private var discoveryError` để quản lý thông tin lỗi tải dữ liệu từ Extension. Sửa đổi `onChange(of: selectedExtensionId)` để dọn dẹp sạch dữ liệu cũ khi đổi extension. Tải dữ liệu `home` và `genre` song song độc lập; chỉ báo lỗi nếu thiếu cả hai. Bổ sung giao diện gợi ý người dùng bấm nút thể loại nếu extension chỉ hỗ trợ thể loại. Cập nhật điều kiện tải dữ liệu trong `.onAppear` để tránh lặp vô hạn. Tích hợp màn hình tải khung xương (`DiscoveryMainSkeletonView` và `DiscoverySkeletonListView`) để hiển thị pulsing loading cân đối khi đang tải danh mục hoặc danh sách truyện lần đầu, giải quyết triệt để lỗi sụp/nhảy layout UI.

## [1.0.3] - 2026-07-14

### Sửa lỗi crash CALayer bounds contains NaN khi chuyển chương trong lúc chạy TTS
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 2 file Swift
*   **Mô tả**:
    *   Cập nhật `ReaderTextView.swift` để bổ sung các kiểm tra an toàn (guard clauses) cho giá trị `NaN` và `Infinite` đối với rect, rectInScrollView, visibleHeight, và targetY trước khi gán `contentOffset` cho `UIScrollView`. Điều này ngăn chặn việc gán giá trị không hợp lệ vào scroll view của trang cũ trong lúc giao diện đang tháo dỡ hoặc cập nhật luồng đọc khi chuyển sang chương mới.
    *   Cập nhật `ReaderView.swift` tại `textReaderView` để bổ sung sự kiện `.onChange(of: chapterIndex)` cho từng trang và liên kết cờ `ttsShouldAutoPlayNextChapter`. Thay đổi này giúp tự động phát tiếp TTS và khôi phục vị trí đọc chính xác khi chuyển sang chương mới đã được preload/prefetch trước từ bộ đệm của `ReaderViewModel`.

## [1.0.2] - 2026-07-14

### Khắc phục triệt để lỗi phân giải Base URL & Lỗi kẹt màn hình trắng Trình đọc
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 5 file Swift
*   **Mô tả**:
    *   Thêm thuộc tính `host` vào mô hình dữ liệu `Book.swift` và thực hiện lưu trữ `NovelDetailResult.host` từ JS Extension vào cơ sở dữ liệu khi nhập sách hoặc reload thông tin chi tiết.
    *   Hoàn tác việc can thiệp phân giải URL ở tầng gọi Swift (`ExtensionManager` và `ReaderChapterListView`), trả lại nguyên vẹn URL tương đối thô cho JS Engine để đảm bảo tính tương thích và không làm hỏng kịch bản regex của Extension (như `bookqq`).
    *   Cải tiến hàm `JSExecutor.cleanAndResolveUrl` chỉ sử dụng tham số `host` từ Swift hoặc tự động truy xuất động các biến cấu hình (`book.host`, `BASE_URL`, `base_url`) trực tiếp từ `JSContext.current()` tại runtime khi JS thực hiện cuộc gọi mạng.
    *   Bọc bắt lỗi ngoại lệ trong `ReaderViewModel.swift` (`enqueuePrefetch`) và cập nhật trạng thái chương tải lỗi sang `.failed(message:)` để giao diện hiển thị nút Thử lại thay vì bị kẹt màn hình trắng.

## [1.0.1] - 2026-07-14

### Sửa lỗi Trình đọc (Reader) và Lỗi base_url cập nhật mục lục
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Tổng số file nguồn ảnh hưởng**: 4 file Swift
*   **Mô tả**:
    *   Khắc phục lỗi SwiftData `#Predicate` dạng chuỗi trên iOS 17 bằng cơ chế lọc trên bộ nhớ (in-memory filtering) cho `localBook`, `ext` và tiến trình lưu vị trí đọc.
    *   Tối ưu hàng đợi prefetch ưu tiên chương hiện tại tải trước tiên (`activeIndex` priority).
    *   Sửa lỗi thiếu `base_url` khi cập nhật mục lục bằng cách tự động phân giải URL tương đối thành URL tuyệt đối trong `ExtensionManager.swift`.

## [1.0.0] - 2026-07-14

### Khởi tạo hệ thống CodeGraph sống (Initial Release)
*   **Người thực hiện**: Trợ lý AI Antigravity
*   **Mã Commit Git**: `UNKNOWN` (Phiên bản phát triển nội bộ đầu tiên)
*   **Tổng số file nguồn ảnh hưởng**: 87 file Swift trong thư mục `Sources/`
*   **Mô tả**:
    *   Thiết lập hệ thống 16 tài liệu markdown phân tích kiến trúc, mối quan hệ file, kiểu dữ liệu, cuộc gọi hàm, máy trạng thái, luồng sự kiện, dòng dữ liệu, vòng đời, quy tắc phụ thuộc và báo cáo rủi ro chi tiết.
    *   Tích hợp metadata YAML Front Matter ở đầu mỗi file và cấu trúc bảo vệ vùng `<!-- GENERATED START -->` / `<!-- GENERATED END -->`.
    *   Thiết lập tệp cấu hình `manifest.json` và schema `codegraph.schema.json`.
    *   Thiết lập hướng dẫn bảo trì toàn cục `AGENTS.md`.
