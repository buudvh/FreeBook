# CHANGELOG - Nhật ký Thay đổi CodeGraph FreeBook

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **FreeBook**.

> Chỉ giữ các version gần đây. Lịch sử cũ hơn (≤ 1.3.259) nằm ở [CHANGELOG.archive.md](CHANGELOG.archive.md).

## [1.3.289] - 2026-08-30

### Rule editor: chèn token tại con trỏ của ô nhập mẫu

- **Nút token luôn chèn vào cuối mẫu.** Ở 1.3.288 con trỏ duy nhất là vạch 2pt giữa hai chip của dải mẫu, nên trừ khi bấm đúng vạch đó, mọi lần chèn đều rơi xuống cuối chuỗi. Sửa bằng `QuickTranslationRulePatternField` — `UIViewRepresentable` bọc `UITextView` để đọc/ghi **con trỏ thật**: `textViewDidChangeSelection` báo lên `selectionStart`/`selectionLength`, `updateUIView` áp ngược lại khi dải chip hoặc nút token đặt vùng chọn mới. Phải bọc UIKit vì iOS 17 không cho SwiftUI đọc vùng chọn của `TextField` (`TextSelection` là iOS 18). Bấm token giờ chèn tại con trỏ, hoặc **thay** đoạn đang bôi đen.
- Quy đổi đơn vị đặt đúng ở biên UIKit: model đếm theo **ký tự** (`Array(pattern)`), `UITextView` dùng `NSRange` UTF-16, hai chiều đổi qua `String.Index`. Hai chốt chống vòng lặp cập nhật: `isApplying` (không báo lên khi tự áp xuống) và `lastReportedRange` (không áp lại range vừa báo lên — cần khi chuỗi có ký tự ngoài BMP).
- Thanh `:min-max` nay mở theo **con trỏ** chứ không chỉ theo vùng chọn khít: token có `start < caret ≤ end` là mở. Vừa chèn `<n>` xong là chỉnh được độ dài ngay, và chạm vào giữa `<n:1-6>` trong ô nhập cũng mở đúng token đó.
- Bỏ cờ `isProgrammaticPatternEdit` và heuristic "gõ tay ⇒ con trỏ về cuối" của 1.3.288: chúng chỉ tồn tại vì trước đó không đọc được con trỏ thật, giữ lại là hai nguồn tranh nhau quyết định con trỏ ở đâu. `reconcileSelection` giờ chỉ kẹp biên.
- `@FocusState` chỉ còn cho ô Bản dịch; ô Mẫu tự `becomeFirstResponder()` một lần trong `makeUIView` khi bản nháp nói nó đang được gõ, và báo focus ra ngoài bằng `onFocusChange`. `focusedField` đổi từ `@FocusState` sang `@State` thường vì nó là *dữ liệu của bản nháp*, không phải cái điều khiển focus.
- 2 file Swift mới (413 → **415**), nhưng `QuickTranslationRuleEditorSheet.swift` **giảm** 374 → 319 dòng nhờ dời 6 hàm biên tập sang `QuickTranslationRuleEditorSheet+Editing.swift`; các `@State` liên quan chuyển sang `internal` (đúng khuôn `ReaderView` + `ReaderView+Selection`). `check_architecture.py` giữ 14 violation nền.

## [1.3.288] - 2026-08-30

### Rule editor: giữ bản nháp, bảng token, thanh min-max, chip {i}

- **Mất sạch chữ đang gõ ở màn thêm/sửa rule khi TTS tự chuyển chương.** Sheet **vẫn mở** mà mọi ô về giá trị seed ⇒ SwiftUI dựng lại content của sheet, `init` chạy lại. Sửa bằng `QuickTranslationRuleDraftStore` (1 slot theo `Mode.id`, sống ngoài cây view, không `ObservableObject`): `init` seed `@State` từ slot, mọi thay đổi mirror ngược lại, `@FocusState` khôi phục ở `onAppear`. Draft chỉ xoá khi **lưu thành công** hoặc bấm **Hủy** — cố ý không xoá ở `onDisappear` vì chính lượt dựng lại có thể kèm một lần disappear. Không hoist lên `@State` của `ReaderView` được: `@State` không khai được trong extension và `ReaderView.swift` đang vượt baseline (2076 > 2053) nên chỉ được giảm dòng. Fix áp cho **cả hai** call site mà không sửa call site nào.
- **Bảng nút token** (`QuickTranslationRuleTokenPaletteView`): 10 token dựng từ `QuickTranslationRuleTokenSettings.Kind.allCases` + 4 nút cú pháp nhóm; chạm là chèn tại con trỏ hoặc **thay** vùng đang chọn. Token đang tắt ở Cấu hình token rule hiện mờ kèm cảnh báo. Kèm `QuickTranslationRulePatternStripView` — dải chip của mẫu (một token là **một** chip) cấp con trỏ và vùng chọn, vì iOS 17 không cho SwiftUI đọc vị trí con trỏ của `TextField` mà luồng chính (nút `+` của Check rule) cần **thay** một đoạn chữ Trung thành token.
- **Thanh min–max bước 1, `[−]`/`[+]` hai bên** (`QuickTranslationRuleTokenLengthBar`) cho token đang chọn, kèm công tắc `?`. Biên lấy từ parser chứ không đặt lại: `min ≥ 1`, `max ≥ min`, trần 20; token không khai `:min-max` nghĩa là `1...12` nên về mặc định thì xuất token **trần**, `min == max` xuất `:N`. `<L>`/`<hv>` không có thanh vì parser ép chúng về đúng 1 ký tự.
- **Chip `{0}/{1}/{2}` theo số token của mẫu** (`QuickTranslationRuleCaptureChipsView`) để chèn vào bản dịch, chip chưa dùng tô đỏ, cộng section **Kiểm tra** (`QuickTranslationRuleDraftIssuesView`) hiện **mọi** issue ngay khi gõ thay vì một issue sau khi bấm Lưu. Verdict do `QuickTranslationRuleDraftAnalyzer` cấp: dựng đúng dòng store sẽ ghi (`RecordStore.serialize`) rồi chạy lại `parse` → `compile`, nên không có trạng thái "ở đây xanh mà lưu vẫn đỏ". `QuickTranslationRuleCompiler.parseTemplate` mở `private` → `internal` để không có bản quét `{…}` thứ hai.
- Sheet hướng dẫn Check rule dời từ ZStack của `ruleToolsOverlay` xuống chính panel Check rule: một view chỉ có một chỗ trình bày.
- 7 file Swift mới (406 → **413**), tất cả ≤ 400 dòng và 1 primary type top-level; `ReaderView.swift` không thêm dòng nào. `check_architecture.py` giữ **14 violation nền**, không violation mới. Host Windows không build được — tính đúng đắn biên dịch do CI xác nhận.
- Đẩy 10 entry cũ nhất (1.3.249–1.3.258) sang `CHANGELOG.archive.md` để file chính về 30 entry theo quy ước.

## [1.3.287] - 2026-08-28

### Add `<h>` (Chinese digits) and `<d>` (ASCII + fullwidth digits) numeral tokens

- `QuickTranslationRuleElement.NumeralKind` thay cho trạng thái `isDigitwise: Bool`: `<n>` = `.chinese`, `<y>` = `.digitwise`, `<h>` = `.hanDigits`, `<d>` = `.asciiDigits`.
- `<h>` chỉ nuốt chữ số Hán `〇零一二两兩三四五六七八九`; `<d>` chỉ nuốt `0123456789` ASCII + full-width `０..９` (U+FF10-FF19), render full-width về ASCII. `<n>/<y>` cũng nhận full-width giờ.
- `QuickTranslationNumberFormatter` thêm `hanDigitsUnits`/`asciiDigitsUnits`, `units(for:)`, `renderHanDigits`/`renderAsciiDigits`; `digitMap` thêm full-width. Matcher/Compiler dùng `units(for:)` cho boundary guard và render theo loại.
- `QuickTranslationRuleTokenSettings` tăng 8 → **10** token (thêm `h`/`d` + 2 khoá UserDefaults lower-camel-case); `QuickTranslationRuleTokenSettingsView` thêm 2 Toggle ở nhóm "Token số và nhãn". `|` giữa các token số vẫn được parse theo loại đầu tiên để giữ tương thích `<n|y>` cũ.
- Mọi file sửa vẫn ≤ 400 dòng; không thêm file mới.

## [1.3.286] - 2026-08-28

### Merge Quick Translation rule action menus

- `QuickTranslationRuleListView` chỉ còn một dropdown `quickTranslationRuleIOMenu(scope:showingDisabled:)`; tab Đang bật hiện nhập/xuất/xoá bộ rule, tab Đã tắt hiện nhập/xuất/bật lại/xoá danh sách rule tắt.
- Xoá modifier riêng `QuickTranslationRuleDisableIOMenu`, chuyển các thao tác rule tắt sang `QuickTranslationRuleIOMenu+DisabledActions.swift` để vẫn giữ mỗi file dưới 400 dòng.
- Giữ `DocumentPickerPresenter`/`ShareSheet` gắn trên body chính, không đưa presenter vào toolbar.

## [1.3.285] - 2026-08-28

### Fix: Correct disabled rule import API label

- Sửa chữ ký `QuickTranslationRuleDisableStore.importPatterns(imported:mode:scope:)` khớp call site nhập danh sách rule tắt, tránh lỗi compile do label `imported:`.
- Tách scope mặc định của `QuickTranslationRuleEditorSheet` trong Reader thành helper rõ ràng, giữ nguyên hành vi sửa/thêm rule theo đúng scope.

## [1.3.282] - 2026-08-28

### Fix Check rule edit, add disable rules import/export

- Màn Check rule: popup ấn giữ chip thêm nút **"Sửa rule"** (mở `QuickTranslationRuleEditorSheet` chế độ `.edit` với scope đúng của rule — riêng/chung). Sheet dùng `updateRule(oldPattern:)` đúng ngữ nghĩa: đổi mẫu = thêm rule mới, giữ rule cũ.
- `QuickTranslationRuleEditorSheet.Mode.edit` thêm associated value `scope: QuickTranslationRuleScope` — mode tự chứa, mọi đường mở sheet đều biết sửa bộ nào.
- Xuất/nhập/bật lại/xoá **rule tắt riêng & chung**: thêm ViewModifier `QuickTranslationRuleDisableIOMenu` gắn vào List (file mới < 400 dòng). Menu có 4 mục: Nhập (.txt, 3 chế độ `DataImportMode`), Xuất, Bật lại tất cả, Xoá tất cả rule đã tắt (destructive, xoá hẳn rule khỏi file + dọn danh sách tắt). Nhập dùng đủ 3 mode chuẩn app (2 mode đè/giữ đồng nghĩa với tập mẫu — ghi chú trong code).
- `QuickTranslationRuleDisableStore`: thêm `importPatterns(_:mode:scope:)` (luôn notifyChange) + `clearDisabled(scope:)`.
- `QuickTranslationRuleStore+Editing` / `QuickTranslationRuleBookStore`: thêm bulk `deleteRules(patterns:)` / `deleteRules(patterns:bookId:)` — filter records rồi ghi lại; không fail khi có mẫu stale.
- Cập nhật accessibility/hướng dẫn: "Ấn giữ: sửa / bật / tắt / xoá".

## [1.3.283] - 2026-08-28

### Fix: Remove @ObservedObject from QuickTranslationRuleIOMenu

- Gỡ `@ObservedObject` khỏi `QuickTranslationRuleIOMenu`, vì `ViewModifier` dùng trực tiếp các singleton store giống modifier danh sách rule tắt.
- Giữ nguyên hành vi đọc, nhập, xuất và xoá rule theo phạm vi chung/riêng.

## [1.3.284] - 2026-08-28

### Fix: Isolate Quick Translation rule modifiers on MainActor

- Đánh dấu hai `ViewModifier` quản lý rule dịch là `@MainActor` để truy cập singleton store có trạng thái UI an toàn khi build với Swift concurrency hiện hành.

## [1.3.281] - 2026-08-28

### Fix rule list back bug, add rule set import/export

- Chuyển `QuickTranslationRuleIOMenu` từ View nhúng toolbar sang **ViewModifier** áp lên `List`, gỡ bug SwiftUI: `DocumentPickerPresenter` (UIViewControllerRepresentable) đặt trong toolbar gây kẹt transition khi pop trong sheet → màn trắng (bug 1.3.281). Giống `DictionaryListView`, mọi presenter/presentation giờ gắn lên body chính.
- Menu Nhập/Xuất/Xoá hiện cho **cả rule riêng và chung** (trước chỉ riêng).
- Route import/export/xoá theo `scope`: `QuickTranslationRuleBookStore` (riêng) / `QuickTranslationRuleStore` (chung).
- Giữ `.searchable` (bằng chứng: Rule Chung back bình thường → `.searchable` không phải thủ phạm).

## [1.3.280] - 2026-08-26

### Canonicalize Quick Translation rule storage

Sửa lỗi build CI của hai API xoá rule sau khi chuyển sang closure `withMutationLock`.

* Thêm `return withMutationLock { ... }` cho `deleteRule(pattern:)` ở store chung và riêng.
* Giữ nguyên commit subject cho lần push sửa CI.

## [1.3.279] - 2026-08-26

### Canonicalize Quick Translation rule storage

Quick Translation Rule chung và riêng theo truyện nay dùng cùng ngữ nghĩa TXT như VP/Name custom: thao tác theo key `pattern`, duplicate giữ dòng đầu, dòng hỏng bị bỏ qua và mọi lần ghi sinh lại file canonical `.txt`.

* Thay `QuickTranslationRuleFileEditor` bằng `QuickTranslationRuleRecordStore` cho parse/merge/upsert/delete/serialize records.
* `QuickTranslationRuleStore` và `QuickTranslationRuleBookStore` đều thêm/sửa/xoá theo `pattern`; không dùng UUID/sourceLine/sourceRevision cho nghiệp vụ.
* Snapshot và trace bỏ `rowID`; UI list dùng `pattern` làm identity sau canonical first-wins và đảo thứ tự file để rule cuối file lên đầu.
* Import preview và import 3 chế độ tính theo key hợp lệ; comments/header/dòng lỗi rơi khỏi file sau lần ghi đầu.
* Windows không có `xcodebuild`/`xcodegen`; đã chạy validator tĩnh, build Swift cần xác nhận trên macOS/CI.

## [1.3.278] - 2026-08-26

### Match preparing TTS highlight color to config

Preparing highlight của đoạn sắp nghe nay dùng đúng màu highlight đã cấu hình, trùng với active TTS highlight.

* `ReaderTextView` bỏ alpha riêng `0.28` cho preparing highlight; background luôn là `theme.highlightUIColor`.
* Preparing highlight cũng áp `theme.highlightTextUIColor` nếu theme/config có màu chữ highlight, giống active highlight.
* `highlightIsPreparing` vẫn giữ vai trò diff/repaint khi chuyển preparing → active, nhưng không còn tạo palette riêng.
* Không đổi state TTS, progress, Now Playing, prefetch hay thứ tự ưu tiên active → preparing → search.

## [1.3.277] - 2026-08-26

### Reveal TTS widget when starting from Reader

Khi bấm nút nghe trong Reader hoặc bôi đen rồi bấm "Nghe", widget TTS mở ở dạng capsule ban đầu thay vì peeking. Không đổi `TTSManager.startSpeaking`, không đổi `WidgetMode`, không thêm notification/event center.

* `TTSFloatingWidgetWindowManager` thêm request một lượt `requestRevealOnNextShow()` với cờ pending `shouldRevealOnNextShow`, consume khi container sẵn sàng hoặc reveal ngay nếu widget đã tồn tại.
* `FloatingWidgetContainerViewController` expose `reveal(animated:)`, dùng lại `FloatingWidgetViewModel.reveal()` nên auto-hide 3 giây và layout/snap hiện có giữ nguyên.
* `ReaderView.startTTS(...)` gọi request reveal ngay trước `ttsManager.startSpeaking(...)`; đây là điểm chung của nút headphones và menu bôi đen "Nghe".
* Giữ ranh giới kiến trúc: `Services/TTS` không biết widget UI; request nằm ở tầng View.

## [1.3.276] - 2026-08-26

### Show preparing TTS highlight before audio starts

Thêm state highlight chuẩn bị để Reader tô đoạn sắp nghe ngay khi bấm phát, trước khi engine TTS tổng hợp/phát audio thật. Không thêm file Swift, không đổi `@Model`, không thêm notification/event center mới.

* `TTSPlaybackSnapshot` thêm `preparingParentParagraphIndex` và `preparingHighlightRange`; `TTSManager.speakCurrent()` publish hai field này trước khi dispatch engine, còn `commitAudibleParagraphState(index:)` vẫn là cửa duy nhất publish active `highlightRange` khi audio bắt đầu.
* Reader projection (`ReaderTTSStateReader`) truyền state chuẩn bị chỉ cho đúng sách đang phát. `ReaderView` chọn highlight theo thứ tự active TTS → preparing TTS → search, và `ParagraphCardView`/`ReaderTextView` render vệt chuẩn bị bằng `highlightIsPreparing`.
* State chuẩn bị chỉ là presentation state: không lưu tiến độ, không update Now Playing, không claim `ReadingProgressStore`, không đổi prefetch/cache audio và không dùng mapper highlight.
* Windows không có `xcodebuild`; đã chạy kiểm tra tĩnh cục bộ, build Swift cần xác nhận trên macOS/CI.

## [1.3.275] - 2026-08-26

### Fix Reader lookup route visibility for CI build

Sửa access control của `ReaderLookupRoute` để extension `ReaderView+Selection` có thể khởi tạo route tra cứu ngoài. Không đổi hành vi UI, navigation hay dữ liệu.

* `ReaderLookupRoute` chuyển từ `private` thành internal để phù hợp với `ReaderView.lookupRoute` và call site ở file extension.
* Sửa lỗi archive CI: `cannot find 'ReaderLookupRoute' in scope` và `property must be declared fileprivate because its type uses a private type`.
* Windows không có `xcodebuild`; đã chạy kiểm tra tĩnh và sẽ xác nhận bằng CI macOS.

## [1.3.274] - 2026-08-26

### Rule dịch: trace lý do match, bật/tắt từng rule, bộ rule riêng theo truyện, overlay xem bản gốc

Thêm **17** file Swift, sửa **17** file Swift, không xoá file, không đổi shape `@Model`, **không** thêm resource bundled (bộ riêng là dữ liệu người dùng, nằm ở `translate/books/<bookId>/`). **Chưa biên dịch** (viết trên Windows, không có `xcodebuild`); có file Swift mới nên khi lên macOS phải `xcodegen generate`.

* **Hai bộ rule thật — bộ riêng theo truyện**: `QuickTranslationRuleScope` (Models, `enum { global, book(String) }`, `rank` 0 riêng / 1 chung) và `QuickTranslationRuleBookStore` (chủ `translate/books/<bookId>/QuickTranslateRules.txt`, LRU cap **3** truyện, compile lazy, cùng hợp đồng validate-then-swap, dùng lại Parser/Compiler/FileEditor/`rowIDs` của bộ chung). Engine trộn hai bộ trong cùng một lượt rewrite (hai lần `collectFound` + `select` **một** lần trên tập hợp nhất); `scopeRank` là tiêu chí ưu tiên **thứ 5**, đứng ngay trước `sourceLine`, nên trong một bộ đơn lẻ thứ tự cũ không đổi — rule riêng thắng rule chung khi trùng mọi tiêu chí khác. Đường dịch không có `bookId` (meta/global, `Qt` bridge) chỉ thấy bộ chung — đúng thiết kế.
* **Bật/tắt từng rule bằng FILE, không sửa file rule**: `QuickTranslationRuleDisableFile` (hàm thuần trên `String`, không chạm `FileManager`) + `QuickTranslationRuleDisableStore` (chủ hai file `QuickTranslateRulesDisabled.txt` chung/riêng). Rule đang tắt **vẫn nằm** trong `snapshot.rules` (bật lại được, giữ `sourceLine`/`rowIDs`); khoá là **mẫu** chứ không phải `sourceLine`; `Snapshot.isDisabled(pattern:scopeRank:)` là toàn bộ ngữ nghĩa — tắt ở bộ chung là tắt cho **mọi** truyện, muốn dùng lại ở một truyện thì thêm mẫu vào bộ rule riêng. Ghi file thất bại ⇒ không bump, không notify — `Toggle` quay về trạng thái cũ. Mọi invalidation gói vào đúng một `notifyDictionariesDidUpdate(bookId:scope: .config(bookId:))`, không thêm notification mới.
* **Màn Check rule ở Reader xem "vì sao thắng/thua/tắt"**: `QuickTranslationRuleDiagnostics` (Service) soi cả đoạn và giữ **cả** rule thua chồng lấn + rule đang tắt, bắt buộc dùng lại `collectFound` (`includesDisabled: true`) + `select` của engine — thay đổi visibility `private` → `internal` duy nhất ở engine — và không ghi trạng thái (`notesComplexRules: false`). DTO `QuickTranslationRuleTrace` (Models) mang `rowID` (handle xoá, không dùng `sourceLine` — lý do crash đã sửa 1.3.271), `scope`, `sourceRange`, `captures` và `Status` 6 case; `id` xác định theo `rowID#location`. `QuickTranslationRuleMatcher.Capture` gộp `text` + `sourceRange?` thành **một** mảng (rollback `let saved = captures` ở 5 chỗ) để hiện được chữ gốc từng token.
* **Hai công cụ mới trong menu bôi đen (2 hàng × 4 cột, thêm "Gốc" và "Rule")**: panel "Copy nội dung gốc" (`ReaderCopyOriginalOverlayView` — **mọi** đường đóng đều copy, không có nút Hủy; chọn lại cụm trên text gốc vì map ngược qua `ReaderSelectionMapper` khi bật dịch có thể lệch ở vùng rule vừa rewrite) và màn Check rule (`ReaderRuleTraceOverlayView` — thanh gốc → nghĩa rule → nghĩa token → dải chip; bấm ký tự snap vào cụm rule; ấn giữ chip ra popup Bật/Tắt/Xoá; nút `+` thêm rule từ cụm đang chọn; chip 3 mức màu `ReaderRuleChipStyle`; `ReaderRuleTraceGuideSheet` cho nút `?`). Khối biên tập vùng chọn dời sang `ReaderView+Selection.swift` (bốn panel Dịch/Xoá từ rác/Copy gốc/Check rule dùng chung); `ReaderView.swift` 2286 → **2076** (−210) nhờ dời 179 dòng + xoá 73 dòng code chết, nhiều `@State` bỏ `private` thành `internal` (phạm vi file).
* **Danh sách rule theo phạm vi, 2 tab Đang bật / Đã tắt**: hàng `[Sửa][Chuyển][Tắt][Xoá]` (`QuickTranslationRuleEntryRow`, mirror `DictionaryEntryRow`); Chuyển là **COPY** qua `QuickTranslationRuleTransfer` (nguồn giữ nguyên; ở danh sách Chung không biết truyện đang mở thì mờ + báo lý do); bộ riêng có menu Nhập (3 chế độ qua `DataImportMode`)/Xuất/Xoá cả bộ (`QuickTranslationRuleIOMenu`); hub Từ điển thêm section **Rule Dịch** với subtitle "N đang bật • M đã tắt"; swipe Sửa/Xoá bị bỏ. Ô Thử nhanh và màn Quản lý giờ **tôn trọng file tắt**; `menuWidth` của bong bóng suy ra từ hằng thành phần (bug tràn mép khi hard-code).
* **Backup liên quan**: tên file riêng truyện gom về **một** nguồn (`TranslationManager+BookScopedFiles` — `BackupPaths.bookDictionaryFiles`/`bookRuleFiles` và luồng đổi nguồn của `SearchView` đều đọc từ đó, hết nhân bản ở hai chỗ); bộ rule riêng + file tắt riêng đi theo scope `.dictBooks` nhưng **tách vòng lặp** khỏi từ điển riêng (vòng cũ trộn bằng `parseRecords` — bỏ dòng không có `=` và sinh lại `key=value`, làm mất comment + thứ tự dòng là tie-break cuối của priority), chiều khôi phục dùng `importRules(.overwriteExisting)` + `DisableStore.merge`; file tắt **chung** vào `config/QuickTranslateRulesDisabled.txt` (`BackupConfigArchiver`), khôi phục **hợp tập** — "khôi phục chỉ thêm, không xoá".
* **Xác minh** (không dùng `Tests/`): 17 file mới đều ≤ 400 dòng (lớn nhất `ReaderRuleTraceOverlayView` 383) và đúng 1 type top level ⇒ không cần entry `architecture_allowlist.json`; tổng file Swift 388 → **405**. `validate_links.py` PASS sau khi cập nhật toàn bộ 13 doc CodeGraph bị stale (7 doc đã sửa vùng GENERATED từ trước + 6 doc sửa/ghi nhận trong lượt này). `check_architecture.py` đã chạy và giữ nguyên **14 violation** baseline (cùng một tập, `ReaderView.swift` 2076 dòng) — không có violation mới; host là Windows nên không build được tại chỗ; CI xanh mới chứng minh *biên dịch được*.

## [1.3.273] - 2026-08-25

### Rule dịch: sửa build token

Sửa lỗi biên dịch SwiftUI ở màn **Cấu hình token rule**.

* Đổi hai `Section` sang initializer `content/header/footer` tương thích với toolchain CI; giao diện và logic bật/tắt token không đổi.
* Đã rà lại `11_subsystems.md` và ghi nhận `--no-change-needed`; CI macOS sẽ xác nhận build archive.

## [1.3.272] - 2026-08-25

### Rule dịch: cấu hình bật tắt token

Thêm **2** file Swift, sửa **10** file Swift; không đổi DSL, `QuickTranslateRules.txt`, backup file rule, SwiftData hay UUID hàng đã dùng để tránh crash. Vì có file Swift mới, cần `xcodegen generate` và build trên macOS; host hiện tại là Windows nên không có `xcodebuild`.

* **Tám công tắc runtime độc lập, mặc định bật**: `<n>`, `<y>`, `<L>`, `<ne>`, `<pn>`, `<vp>`, `<hv>`, `<w>`. `QuickTranslationRuleTokenSettings` dùng Foundation + UserDefaults lower-camel-case; thiếu khoá vẫn là `true`, chữ ký theo thứ tự token ổn định cho cache. Các khoá theo luồng backup/restore settings hiện có, còn rule file/dataset không bị rewrite.
* **Chặn rule dựa trên syntax gốc, không dựa trên matcher đã hạ token**: AST giữ `sourceTokenKinds`, compiler tạo `requiredTokenKinds` đệ quy. Tắt bất kỳ token nào sẽ bỏ cả rule chứa nó, kể cả token optional, group hoặc danh sách `|`; `<w>` luôn độc lập với `<ne>/<pn>/<vp>`. Capture, priority và matcher không đổi.
* **Cache và runtime không giữ kết quả cũ**: engine chụp một cấu hình cho mỗi lượt rewrite, lọc rule trước matcher và đưa signature vào memo key; `QuickTranslationRuleStore.cacheTag` cũng chứa signature. Mỗi Toggle chỉ `TranslateUtils.clearCache()` rồi phát đúng một `notifyDictionariesDidUpdate()`; `dictionaryIssues()` bỏ qua rule bị token tắt.
* **Giao diện**: mục Công cụ có màn "Cấu hình token rule" (nhóm số/nhãn và từ điển, nêu rõ không sửa file). Ô Thử nhanh mặc định "Theo cấu hình token", có mode tạm "Bỏ qua cấu hình token" để coi mọi token bật; cả hai vẫn bỏ qua công tắc tổng. Mô tả editor và trạng thái list đổi thành “đã nạp” để không coi rule bị policy tắt là chưa nạp.
* **Xác minh** (không dùng `Tests/`): `validate_links.py` PASS sau khi cập nhật CodeGraph; `check_architecture.py` vẫn đúng 14 violation baseline, không có violation mới. Build LiveContainer cần xác nhận trên macOS.

## [1.3.271] - 2026-08-25

### Rule dịch: sửa crash xoá và định danh hàng ổn định

Sửa **5** file Swift, không thêm/xoá/đổi tên file và không đổi shape `@Model`. **Chưa biên dịch**: thay đổi được thực hiện trên Windows nên không có `xcodebuild`; không cần `xcodegen` vì project không đổi danh sách file Swift.

* **Sửa nguyên nhân crash khi xoá rule trong `List`**: `sourceLine` là toạ độ vật lý, các hàng sau đổi số sau một lần xoá nhưng trước đây lại là identity của `ForEach`. `QuickTranslationRuleSnapshot` nay giữ UUID tạm song song với rule compile; `QuickTranslationRuleListView` diff bằng UUID, không dựng lại `List`, nên hàng không liên quan giữ identity và vị trí cuộn.
* **Xoá chính xác cả rule trùng hoàn toàn**: API đổi thành `deleteRule(rowID:)`. Store kiểm SHA-256 revision của toàn bộ text, tìm row UUID, rồi FileEditor đối chiếu pattern **và** replacement tại `sourceLine` hiện hành trước khi xoá; không còn fallback về occurrence đầu tiên.
* **Giữ hợp đồng CRUD/file**: FileEditor trả metadata insert/replace/delete để Store remap UUID sau dịch dòng; add/overwrite/đổi key giữ ngữ nghĩa cũ và UUID của hàng không tác động. Nhập, tải, khôi phục và nạp dataset tạo handle mới. Toàn bộ giao dịch nội bộ tuần tự hoá theo thứ tự kiểm revision → sửa → validate → atomic write → swap snapshot, giữ cache invalidation và một notification hiện có.
* **Tài liệu/kiểm tra**: cập nhật generated region của `03`, `07`, `08`, `11`, `12`; không đọc/sửa/chạy `Tests/`. `validate_links.py` PASS (16 tài liệu, 386 Swift); architecture checker vẫn đúng 14 violation baseline, không có violation mới. Windows không thể xác minh build hay LiveContainer.

## [1.3.270] - 2026-08-25

### Rule dịch: CRUD từng dòng, nhập 3 chế độ, danh sách riêng

Thêm **5** file Swift, sửa **8** file, không xoá file, không đổi shape `@Model`. Tiếp nối `[1.3.269]`. **Chưa biên dịch** (viết trên Windows, không có `xcodebuild`); có file Swift mới nên khi lên macOS phải `xcodegen generate`.

* **Sửa crash `EXC_BREAKPOINT` khi mở màn quản lý rule** (5 file `.ips` của LiveContainer): một hàng `List` bọc `LazyVStack` làm `UICollectionViewCompositionalLayout` (backing của `List` từ iOS 16) tự vô hiệu layout **ngay trong** lượt cập nhật cell đang chạy — `_updateVisibleCellsNow:` gọi đệ quy chính nó rồi chết ở `_assertionFailure`. `List` vốn đã lazy nên mỗi rule giờ là **một hàng `List` thật**, phần chặn 17k dòng nằm ở `prefix(visibleLimit)` chứ không ở kiểu container.
* **Danh sách rule và ô tìm kiếm là màn riêng** (`QuickTranslationRuleListView`): trước đó `.searchable` lọc một danh sách xen giữa thẻ trạng thái và các nút hành động. Màn quản lý còn trạng thái + hành động + section "Công cụ" (2 `NavigationLink`); màn danh sách có hàng tóm tắt "n/N rule khớp", tìm theo **mẫu / bản dịch / số dòng** (số dòng là thứ sheet lỗi in ra), phân trang 200, và badge cảnh báo gộp theo `sourceLine`.
* **CRUD từng rule, ngữ nghĩa mượn nguyên của từ điển** (`QuickTranslationRuleFileEditor` + `QuickTranslationRuleStore+Editing` + `QuickTranslationRuleEditorSheet`): nút `+`, swipe **Sửa** / **Xoá**. Thêm mà key đã có ⇒ **đè nghĩa** (vế phải), giữ nguyên vị trí dòng nên priority không đổi; **xoá là xoá hẳn dòng**; **đổi key ⇒ xử như thêm key mới, dòng cũ giữ nguyên** — đúng `DictionaryCache.upsertEntry` / `updateKey` / `deleteEntry`. Rule tự thêm chèn ngay **sau khối comment header** để trùng mọi tiêu chí priority thì rule người dùng thắng bộ tải về. Máy chưa có file rule vẫn thêm được.
* **Sửa file rule là phẫu thuật theo dòng, địa chỉ hoá theo key**: không sinh lại file từ danh sách đã parse (mất comment — kể cả 11 dòng header đặc tả DSL — và xáo thứ tự dòng, tức tiebreak cuối của priority). Khoá là **mẫu bên trái dấu `=`**, không phải `sourceLine` (số dòng đổi sau mỗi lần thêm/xoá), nhờ vậy sheet sửa không cần khoá phiên bản file. `QuickTranslationRuleParser.splitRuleLine` đổi `private` → `internal` để editor hỏi đúng một nguồn "khoá của dòng này là gì". File editor là hàm thuần trên `String`, không chạm `FileManager` — vẫn chỉ một nơi ghi file rule. Cả ba thao tác đi qua `importRules` nên giữ validate-then-swap; sheet **không tự đóng** khi bị từ chối mà in `dòng N — CODE: message`.
* **Nhập file rule có 3 chế độ** (`DataImportMode` — enum dùng chung mới ở `Sources/Models/Dictionaries/`, mở đường cho 8 màn còn lại trong `Docs/CheckList/import-3-modes-checklist.md`): **Thay thế hoàn toàn** (`role: .destructive`) / **Đè nghĩa mới lên key trùng** / **Giữ nghĩa cũ, chỉ thêm key mới**, kèm số đếm thật từ `importPreview`. Hai chế độ trộn giữ thứ tự dòng bản trên máy và comment cả hai bên; rule mới nối cuối file dưới mốc `# --- Rule nhập thêm ---`. Trộn xong **validate lại toàn bộ**. `importRules(text:source:mode:)` mặc định `.replaceAll` nên nút tải bộ mặc định và khôi phục backup giữ nguyên hành vi.
* **Rule `<pn>` KHÔNG còn phụ thuộc công tắc `isTranslationPronounsEnabled`** (đổi so với plan §17 #5b): công tắc đó là của đường tra từ điển đại từ theo token ở tokenizer, còn `<pn>` trong rule là ràng buộc của rule người dùng chủ động viết. Hệ quả cần biết: `Rule_new.txt` (16.941 rule `<pn>`) chạy ngay khi nạp nếu máy có `Pronouns`.
* **Sửa cảnh báo `LITERAL_SPACE_IN_PATTERN` báo sai hàng loạt**: bản đầu kiểm `rule.pattern.contains(" ")` trên text thô nên tính luôn khoảng trắng trong `( )?` — idiom "khoảng trắng tuỳ chọn" có ở **1.023/1.177** rule của `rule-aio.txt`. Giờ duyệt AST, chỉ tính literal ở mức ngoài cùng và không optional: aio 1.023 → 0 cảnh báo rác, bộ v21 vẫn đúng 7 dòng space trần thật.
* **Một lần đổi bộ rule = đúng một thông báo**: `importRules` thêm `notifiesObservers: Bool = true`, `BackupConfigArchiver` truyền `false` vì `BackupRestoreWorker` đã phát `notifyDictionariesDidUpdate()` ở cuối lượt — trước đó Reader dựng lại hai lượt, lượt đầu còn dở dữ liệu. `invalidateTranslationCaches()` bỏ lời gọi dư `clearChapterTitleCache()`.
* **Đo dòng trùng mẫu** (script tạm, đã xoá): bộ v21 đang chạy có **0** dòng `DUPLICATE_PATTERN` và 26 cảnh báo = 7 space trần + 19 token dán nhau; `rule-aio.txt` có **3** dòng trùng (269, 836, 837) và cả ba trùng luôn vế phải nên vô hại — lỗi file nguồn, giờ xoá được ngay trong app.
* **Xác minh** (không dùng `Tests/`): `check_architecture.py` giữ **14 violation**, cùng một tập — 5 file mới đều ≤ 400 dòng và đúng 1 type top level (lớn nhất `QuickTranslationRuleFileEditor` 194). `validate_links.py` PASS (16 doc, 386 file Swift).

## [1.3.269] - 2026-08-25

### Rule dịch Quick Translate: engine, màn hình quản lý và công tắc

Thêm **19** file Swift, sửa **6** file, không xoá file, không đổi shape `@Model`, **không** thêm resource bundled. **Chưa biên dịch** (viết trên Windows, không có `xcodebuild`); có file Swift mới nên khi lên macOS phải `xcodegen generate`. Thực thi theo `Docs/Plan/quick-translate-rule-engine.md`, với một thay đổi về nguồn rule theo yêu cầu chủ dự án: bộ rule **không** đi kèm app.

* **Bộ rule là dữ liệu tải về, không phải resource của app.** Nó nằm ở `translate/QuickTranslateRules.txt` (cùng thư mục với `VietPhrase.txt`/`ChinesePhienAmWords.txt`) và có đúng hai đường vào: nút **"Tải bộ rule mặc định"** trong màn quản lý — lấy từ `https://huggingface.co/datasets/raikiri1498/vietpharse/resolve/main/QuickTranslateRules.txt`, đúng dataset mà `TranslationManager.downloadDefaultDictionaries` đang dùng — hoặc người dùng nhập file `.txt`. Chưa tải thì `activeSnapshot` trả `nil` và pipeline dịch chạy **y như trước khi có tính năng này**, không lỗi, không cảnh báo ồn ào. Đường tải đi qua đúng `importRules` nên vẫn validate-then-swap: file tải về hỏng thì bộ đang chạy không bị thay. Có trần cứng 8 MB trước khi parse, và bản tải phải là UTF-8.
* **Rule chạy đúng chỗ đã chốt**: `QuickTranslationRuleEngine.rewrite` ở **đầu** `TranslateUtils.performTranslation` — sau Phồn thể → Giản thể (`textForTranslation`), **trước** `punctuationMapping` và trước tokenize. Phải trước `punctuationMapping` vì LHS của rule có literal `．`, `.`, `,` và dấu ngoặc. Hai cửa cũ (`containsChinese`, `isVietPhraseLoaded`) vẫn đứng trước nên rule không chạy cho chuỗi không có chữ Hán và không chạy khi từ điển chưa nạp.
* **Matcher tự viết, không `NSRegularExpression`** (`QuickTranslationRuleMatcher`, 200 dòng): AST-walk có backtracking bằng stack frame, cap **4.000** bước cho mỗi (rule, vị trí). Lý do bắt buộc: token `<ne>/<pn>/<vp>/<w>` phải khớp **một entry của từ điển** tại vị trí capture — regex không diễn tả được. Reference biên dịch chúng thành `([\p{Script=Han}A-Za-z0-9]{1,12})` rồi trả nguyên văn nên `<pn>一人` gặp "众人皆知他一人" nuốt cả "众人皆知他" và ra câu Việt sai thứ tự **mà không lộ chữ Hán**. Ràng buộc từ điển đi qua `TrieDictionary.findAllPrefixMatches` (đã có sẵn), thử ứng viên dài → ngắn; range `:min-max` chỉ còn vai trò cắt bớt ứng viên.
* **Hỗ trợ đủ DSL trong header file rule ngay từ đầu**: `<n> <y> <L> <ne> <pn> <vp> <hv> <w>`, group lồng đệ quy, `\x` escape, `<x>?` và `(a|b)?`. Ba thứ này reference **biên dịch sai mà không throw**, nên nhờ tự parse mà số dòng bị chặn cứng trong `rule-aio.txt` tụt **27 → 2** (dòng 916 thiếu `)`, dòng 668 không dùng hết capture).
* **Ba điểm cố ý lệch reference, làm theo header**: `<y>` bỏ mọi ký tự bậc `十百千万萬亿億兆` (6 rule dòng 131-136 của bộ bundled dùng `十` làm literal, giữ parity là giết chúng); `<L>` cố định 1 ký tự (reference để `{1,12}` rồi trả nguyên văn = rác); boundary guard `<n>/<y>` **có điều kiện** — chỉ guard khi phần tử liền kề không tiếp tục chuỗi số theo lớp ký tự của chính token, vì bọc vô điều kiện giết `<n:1-6>万`, `十<y:1>级`, `<n:1-3>十<n:1-3>(万|萬)` (82 + 49 vị trí đã đo). Giữ parity: `chineseNumber` cộng dồn section (`一万亿` = `100010000`), không cascade, không exhaustive match, không `trim()`, không dấu phân cách số.
* **Prefilter là điều kiện khả thi, không phải tối ưu** (`QuickTranslationLiteralIndex`): gom rule theo đơn vị UTF-16 đầu của literal bắt buộc, xác nhận cả literal tại chỗ, rồi suy **tập vị trí bắt đầu** = vị trí literal − bề rộng phần đứng trước. Đo trên 30 dòng chương thật: **42,3** ứng viên/dòng với bộ 633 rule và **18,0** với bộ 17.278 rule — tập ứng viên tỉ lệ với chữ trong dòng, không tỉ lệ với số rule.
* **Span còn đúng sau khi rule đảo thứ tự từ**: `QuickTranslationRewriteResult` mang bản đồ đoạn `(sourceRange, outputRange, sourceLine?)` theo UTF-16; `translationSpansApplyingRules` lấy token trên chuỗi **sau rewrite** rồi rebase về nguồn. Đoạn passthrough map theo offset tuyệt đối, đoạn do rule sinh map về **toàn bộ** match nguồn, đoạn không chứng minh được thì bỏ span của riêng nó. Không gọi lại `buildTranslationSpans(original:translated:)` cho vùng đã rewrite — hàm đó dò token của chuỗi *gốc* trong chuỗi *đã dịch* nên vừa bỏ span vừa có thể khớp bừa.
* **Công tắc `isQuickTranslateRuleEnabled`, mặc định BẬT**, ở section "Dịch Thuật Quick Translate" cùng link "Quản lý rule dịch" (`QuickTranslateRuleSettingsRows`, tách file để `SettingsView.swift` giữ dưới baseline 453). Repo không có `UserDefaults.register(defaults:)` nên Service đọc `object(forKey:) as? Bool ?? true` còn View khai `@AppStorage(…) = true` — lệch hai chỗ là toggle nhảy trạng thái lần đầu. Trạng thái công tắc + `generation` snapshot vào **cả** cache key `translateText` (`v3` → `v4`, thêm `q:`) **và** `translationGenerationToken(for:)`.
* **Màn hình quản lý** (`QuickTranslationRulesView` + `QuickTranslationRuleIssueSheet` + `QuickTranslationRuleTesterView`): thẻ trạng thái (nguồn — *trên máy / vừa tải / vừa nhập*, số rule, số cảnh báo, `sourceHash`, thời điểm nạp, banner khi công tắc đang tắt, lời mời tải khi máy chưa có bộ rule), nút **tải bộ rule mặc định** kèm `ProgressView` (cờ `isDownloading` do store sở hữu), nhập `.txt`, xuất bộ đang chạy, xoá bộ rule có `confirmationDialog`, danh sách phân trang 200 dòng có tìm kiếm, và ô thử nhanh hiện "rule nào khớp ở offset nào, capture ra gì".
* **Ba mức lỗi, ba hệ quả**: `hard` (cú pháp, `{i}` sai, thiếu neo, không dùng hết capture) ⇒ **không nạp cả file**, bộ đang chạy giữ nguyên, sheet chỉ đúng dòng lỗi; `disabling` (`DICT_TOKEN_WITHOUT_DICTIONARY`) ⇒ chỉ vô hiệu rule đó và được **tính lại mỗi lần mở màn** vì nó phụ thuộc trạng thái runtime; `warning` (space literal, hai token dán nhau, trùng mẫu, neo yếu, rule quá phức tạp) ⇒ vẫn nạp. `importRules` là validate-then-swap: compile toàn bộ vào staging, chỉ khi sạch hard error mới `Data.write(options: .atomic)` rồi swap snapshot dưới `NSLock`.
* **Qt bridge bị loại tường minh**, không suy đoán ngữ cảnh: tham số `applyingQuickTranslationRules` xuyên `translateMeta`/`translateContent`/`translateChapterTitle`/`translateText`/`performTranslation`, `JSExecutor._nativeQtTranslate` truyền `false`, và cờ nằm trong cả cache key `translateText` (`q:off`) lẫn khoá con của `chapterTitleCacheDict`.
* **Backup**: `config/QuickTranslateRules.txt` đi cùng công tắc `restoreSettings` như `config/toc_rules.json` — **không** thêm case `BackupScope` (rawValue lạ làm bản app cũ decode manifest lỗi). Vì bộ rule không đi kèm app, file này là dữ liệu người dùng thật sự nên **phải** vào archive; chiều khôi phục gọi `QuickTranslationRuleStore.importRules` để ghi file + swap + dọn cache dùng đúng một đường.
* **Lệch có chủ ý so với plan §17 #5**: plan chọn rule chạy **trước** formatter tiêu đề chương; bản này giữ `translateChapterTitle` làm chủ tiền tố `第<n><L>` và chỉ áp rule cho phần còn lại, vì rule `第<n:1-6><L> = {1} {0}` cho "Chương 1 mở đầu" trong khi formatter cho "Chương 1: Mở đầu" (có dấu hai chấm + bảng `chapterUnitMap`) — đổi thứ tự là đổi mọi tiêu đề chương ở Kệ/Mục lục/Reader. Muốn theo plan thì dời lời gọi `rewrite` lên đầu `translateChapterTitle`, một chỗ sửa. Điểm thứ hai: `wildcardCapacity` của token từ điển không khai range dùng 12 như reference thay vì "độ dài entry dài nhất" (plan §7.2) vì `TrieDictionary` không expose số đó; đây chỉ là metric tiebreak.
* **Việc còn lại của chủ dự án**: upload `QuickTranslateRules.txt` (bộ chuẩn v21, 36.608 byte, LF) lên `huggingface.co/datasets/raikiri1498/vietpharse` cạnh `vietpharse.txt`/`phienam.txt`. Trước khi có file đó, nút tải sẽ báo lỗi 404 và app vẫn dịch bình thường bằng từ điển.
* **Xác minh** (không dùng `Tests/`): `check_architecture.py` giữ **14 violation**, cùng một tập — 19 file mới đều ≤ 400 dòng và đúng 1 type top level, `TranslateUtils.swift` **giảm** 1041 → 1023 nhờ dời `buildTranslationSpans`/`findTranslatedTokenRange` sang `TranslateUtils+QuickTranslationRules.swift` (hai hàm phải bỏ `private` vì `private` là phạm vi file). `validate_links.py` PASS (16 doc, 381 file Swift). Thêm một bản **mirror thuật toán bằng Python** (script tạm, đã xoá — không phải test của repo) chạy trên ba bộ rule thật: bộ chuẩn v21 (bản sẽ đưa lên HuggingFace) **633** rule / 0 hard error, `rule-aio.txt` **1.175** rule / đúng 2 hard error, `Rule_new.txt` **17.278** rule / 0 hard error; các ví dụ biên đều đúng đặc tả (`三百五十米`→"350 mét", `十五级`→"cấp 15", `五十级`→"cấp 50", `二十五级`→"cấp 25", `第一章卷` chỉ nuốt `章`, `一万亿`→`100010000`, `500立方米`→"500 mét khối", `生命能量+300`, `50%暴击` và `50.5%暴击` cùng khớp). Mirror chứng minh **thuật toán**, không chứng minh bản Swift biên dịch được.

## [1.3.268] - 2026-08-25

### Nhắc khi tự động sao lưu chưa đăng nhập Drive, báo đúng số truyện đã dọn

Sửa **7** file Swift, không thêm/xoá file, không đổi shape `@Model`. Chưa biên dịch (viết trên Windows, không có `xcodebuild`/`xcodegen`; không có file mới nên không cần `xcodegen generate`).

* **Lỗ tín hiệu 1 — bật tự động sao lưu mà chưa đăng nhập Drive thì hoàn toàn im lặng.** `runAutoDriveBackup` trả `.skipped` cho mọi lý do và `MainTabView` bỏ qua nhánh này, nên người dùng tưởng đang có bản sao lưu định kỳ trong khi không có bản nào. Nay `AutoDriveBackupOutcome.skipped` mang `SkipReason` (`.notDue` / `.driveNotLinked`) và `MainTabView` hiện toast `.error` "Tự động sao lưu đang bật nhưng chưa đăng nhập Google Drive". `GoogleDriveConfiguration.isConfigured == false` vẫn im lặng có chủ ý — build thiếu client id không phải việc người dùng sửa được.
* **Nhịp nhắc là khoá riêng, không tiêu nhịp sao lưu** (`DriveAutoBackupPolicy.swift`, 123 → 143): thêm `driveAutoBackupLastLinkWarningAt` + `linkWarningCooldown = 24 h` (`shouldWarnDriveNotLinked`/`markDriveNotLinkedWarned`). Nhánh chưa-đăng-nhập rời `runAutoDriveBackup` **trước** `markRun()`, nên đăng nhập xong là lượt sao lưu chạy được ngay thay vì phải chờ hết cooldown. Đường bấm tay (`force`) bỏ qua cửa nhắc và luôn được trả lời ngay.
* **Lỗ tín hiệu 2 — dọn bản cũ trên Drive lỗi mà toast vẫn báo thành công trọn vẹn** (`BackupCoordinator+AutoDrive.swift`, 125 → 157): `pruneRemoteAutoBackups`/`pruneLocalAutoBackups` đổi sang `-> (removed: Int, incomplete: Bool)`, gộp cả lỗi `listBackups()` và lỗi xoá từng file. `incomplete` chảy vào `.succeeded(…, pruneIncomplete:)`; toast đọc qua `AutoDriveBackupOutcome.pruneNote` (`" — đã dọn N bản cũ"` / `" — chưa dọn hết bản cũ"`) và hạ `type` xuống `.info`. Vẫn tính là thành công vì bản vừa upload còn nguyên. Gộp vào **một** message vì `ToastManager.show` gọi `currentTask?.cancel()` — toast thứ hai sẽ đè toast thứ nhất.
* **Lỗ tín hiệu 3 — toast báo số truyện dự kiến, không phải số truyện thật sự bị xoá** (`BookStorageManager.swift` 363 → 368, `StaleBookCleanupCoordinator.swift` 126 → 134): `deleteBooksAsync` nay `-> Int` (`@discardableResult` nên caller cũ không phải sửa) trả số bản ghi đã `delete` + `save`. Truyện được TTS bắt đầu phát trong khoảng giữa lúc quét `staleBookIds` và lúc xoá bị loại **bên trong** `deleteBooksAsync`, nên trước bản này câu "Đã xoá N truyện" có thể sai. `deletedCount == 0` ⇒ `.skipped` thay vì `.deleted(count: 0)`.
* **Câu chữ khớp giữa các màn**: `DriveAutoBackupSettingsView.swift` (143 → 148) map `.skipped(.driveNotLinked)` → "Chưa đăng nhập Google Drive", `.skipped(.notDue)` → "Chưa chạy được lúc này, thử lại sau"; `StaleBookCleanupSettingsView.swift:200` đổi `inactiveDays` → `clampedInactiveDays` để số ngày trong toast trùng hàng "Ngưỡng bỏ quên" khi UserDefaults còn giữ giá trị ngoài dải `7...365`.
* **Cố ý không sửa trong lượt này**: xoá file vật lý (`.bin`, ChapterStore, cover) chạy `Task.detached` fire-and-forget, thất bại chỉ vào `failed_file_deletions_queue` và `drainRetryQueue` bỏ hẳn sau 3 lần — **không** báo gì cho người dùng. Báo được thì phải thêm một kênh báo cáo ra khỏi task nền, rộng hơn phạm vi vá tín hiệu này; đã ghi vào `10_risk_report.md`.
* Không dòng nào trong `Sources/Services/**` gọi `ToastManager` — toàn bộ toast vẫn nằm ở View, mọi thay đổi đi qua giá trị trả về.
* **Kết quả gate**: `check_architecture.py` giữ **14 violation** (tập y hệt, không violation mới; mọi file sửa đều dưới 400 dòng). `validate_links.py` PASS.

## [1.3.267] - 2026-08-25

### Nhập/xoá từ điển VietPhrase riêng làm Reader dịch lại ngay

Sửa **1** file Swift, không thêm/xoá file, không đổi shape `@Model`. Chưa biên dịch (viết trên Windows, không có `xcodebuild`/`xcodegen`).

* **Lỗi**: "Từ điển truyện → VietPhrase Riêng → Nhập" ghi file, gọi `TranslateUtils.clearCache()` + `TranslationManager.shared.clearBookDictCache(for:)` rồi báo thành công, nhưng **không** phát `notifyDictionariesDidUpdate`. Reader chỉ dựng lại `[ParagraphItem]` khi nhận `.translationDictionariesDidUpdate` (`ReaderView.swift:672`), nên chương đang hiển thị giữ nguyên bản dịch cũ — chỉ đổi chương/tải lại mới thấy từ điển mới. Nhánh "Xoá tất cả" của từ điển truyện thiếu y hệt.
* **Sửa** (`DictionaryListView.swift`, 748 → 752): thêm `TranslationManager.shared.notifyDictionariesDidUpdate(bookId: bid)` vào đúng hai nhánh sách sau khi ghi file thành công — `deleteAllEntries()` (:482) và `importFile(from:isMerge:)` (:523). Giữ `bookId` để chỉ Reader của truyện đó refresh, và giữ `scope` mặc định `.globalReload` vì nhập/xoá cả từ điển không phải sửa một từ (`.term`). Vẫn giữ `clearCache()` hiện có: thu hẹp nó thành `invalidateCache(bookId:)` là thay đổi hành vi rộng hơn, không thuộc lỗi này.
* **Chỉ Reader cần vá.** Toàn repo có đúng hai subscriber của notification này: `ReaderView` và `TTSManager`. Phía TTS **đã** tự lo bằng token — `TTSPreparedChapterKey`/`TTSPreparedNextChapterKey`/`NowPlayingStaticMetadataKey` đều nhúng `translationGenerationToken`, nên prefetch cũ không bao giờ khớp `consumeCache` và rơi về `fallbackAdvanceToNextChapter` (nạp + xử lý lại). Notification với TTS chỉ là *áp dụng ngay cho chương đang phát*, không phải điều kiện đúng đắn.
* `shareToBook(targetBook:isMerge:)` (:534) **cố ý giữ nguyên**: Reader luôn trình bày bằng `fullScreenCover(item:)` nên không thể có Reader của truyện đích đang mở, và phía TTS đã token-guard như trên.
* **Kết quả gate**: `check_architecture.py` giữ **14 violation** (baseline, không có violation mới — `DictionaryListView.swift` vượt baseline 690 từ trước bản này). `validate_links.py` PASS.

## [1.3.266] - 2026-08-24

### Nút -/+ ngưỡng dọn truyện cũ, bấm ra ngoài là tắt bàn phím

Thêm **1** file Swift (361 → 362), sửa 2 file. Chưa biên dịch (viết trên Windows, không có `xcodebuild`/`xcodegen`) — **phải chạy `xcodegen generate` trên macOS/CI** vì có file mới.

* **Nút −/+ cạnh thanh trượt "Ngưỡng bỏ quên"** (`StaleBookCleanupSettingsView.swift`, 209 → 238): mỗi lần bấm đổi đúng 1 ngày. Cả nút và slider đều ghi qua `StaleBookCleanupPolicy.clampInactiveDays` nên dải `7...365` vẫn có **một** nguồn duy nhất; nút tự `disabled` khi tới biên. Dùng `.buttonStyle(.borderless)` để hàng `Form` không biến thành một vùng bấm chung, và `LabeledContent` hiển thị số ngày hiện tại phía trên slider.
* **Bàn phím tự tắt khi bấm ra ngoài ô nhập** — trước đây phải mỗi màn tự gọi `hideKeyboard()` nên phần lớn ô nhập trong app không tắt được bàn phím. Nay giải ở tầng window bằng file mới `Sources/Common/Utils/KeyboardDismissGesture.swift` (112 dòng, chỉ `import UIKit`, 1 type top-level): singleton `@MainActor` gắn `UITapGestureRecognizer` lên mọi `UIWindow` có `windowLevel == .normal && !isHidden`, tap thì `endEditing(true)`.
  * `cancelsTouchesInView = false` + `shouldRecognizeSimultaneouslyWith → true`: recognizer **không** ăn touch, nên scroll/list/nút bấm vẫn hoạt động y như trước.
  * `shouldReceive touch` đi ngược cây superview, gặp `UITextField.isEnabled` / `UITextView.isEditable` / `UISearchBar` thì **bỏ qua** tap — tránh lỗi cổ điển "bấm vào chính ô nhập lại tự tắt bàn phím". Kiểm theo thuộc tính chứ không theo tên class nên `ReaderUITextView` (read-only) vẫn tắt được bàn phím.
  * Lọc theo `windowLevel == .normal` loại các overlay window (toast `.alert`, widget TTS `alert - 1`, widget browser `alert - 2`) và window bàn phím của hệ thống — cùng idiom đã dùng ở `VisibleBrowserTabManager.swift:264`.
  * Cài **trễ** theo `keyboardWillShowNotification` thay vì lúc khởi động, để bắt cả window sinh sau (scene mới, LiveContainer). Idempotent nhờ cờ `isObserving` + đặt `name` cho recognizer, nên không cần bảng weak window.
  * `FreeBookApp.swift` (107 → 108): `AppLaunchRootView.onAppear` gọi `KeyboardDismissGesture.shared.activate()` trước khi drain retry queue.
  * `View.hideKeyboard()` và 3 chỗ `resignFirstResponder` tường minh (`ExtensionScriptEditorView+Toolbars`, `ReaderJunkDeleteOverlayView`, `ReaderDefinitionOverlayView`) **giữ nguyên** — chúng tắt bàn phím theo hành động cụ thể, không phải theo tap ra ngoài.
* **Kết quả gate**: `check_architecture.py` giữ **14 violation** (baseline, không có violation mới). `validate_links.py` PASS.

## [1.3.265] - 2026-08-24

### Backup quy tắc mục lục, xuất nhập công cụ tra cứu nhanh

Thêm **2** file Swift (359 → 361), sửa 11 file; **không** `@Model` nào đổi shape, **không** thêm `BackupScope` case, **không** thêm dependency. Chưa biên dịch (viết trên Windows, không có `xcodebuild`/`xcodegen`) — **phải chạy `xcodegen generate` trên macOS/CI** vì có file mới.

* **Bản sao lưu mang theo quy tắc mục lục.** `Sources/Services/Backup/BackupConfigArchiver.swift` (109) sở hữu nhánh archive mới `config/`: `config/toc_rules.json` chép nguyên `translate/toc_rules.json` (gồm cả quy tắc đang tắt — tắt cũng là lựa chọn của người dùng) và `config/search_engines.json` giữ danh sách công cụ tra cứu nhanh. Vẫn **không** thêm `BackupScope` case: rawValue lạ trong `manifest.scopes` (kiểu `[BackupScope]`, decoder tổng hợp) làm bản app cũ decode **cả manifest** thất bại. Cả hai file luôn được ghi vào archive và chịu chung công tắc `BackupRestoreWorker.Options.restoreSettings` với khối plist cài đặt.
* **Công cụ tra cứu nhanh rời khối plist để khôi phục *gộp* được.** Trước bản này khoá `custom_search_engines` nằm trong `settings/user_defaults.plist`, nên khôi phục **ghi đè cả mảng** và xoá sạch công cụ chỉ có ở máy nhận. Nay `SearchEngine.storageKey` vào `deniedKeys` của `BackupSettingsArchiver` **cùng lúc** `BackupConfigArchiver` nhận quyền sở hữu — phải làm cùng lúc, vì khối plist ghi ở **bước cuối** `restore()` nên nếu còn hai chủ thì nó dập kết quả gộp bằng mảng cũ.
* **Chiều xuất đọc `Data` thô của khoá, không gọi `SearchEngine.loadEngines()`** — hàm đó **ghi** bộ mặc định vào `UserDefaults` khi khoá còn trống, và một lượt sao lưu không được thay đổi trạng thái thứ nó đang chụp.
* **Chiều nhập dùng lại primitive sẵn có, không cài lại luật gộp**: quy tắc mục lục đi qua `TranslateUtils.validateImportedTOCRules` → `mergeTOCRules(current:imported:)` → `saveTOCRules` (hàm cuối tự dọn cache regex + cache tên chương nên có hiệu lực ngay, khác khối cài đặt phải mở lại app); công cụ tra cứu đi qua `SearchEngineTransfer.merged` + `SearchEngine.saveEngines` và chỉ **thêm** phần máy chưa có.
* **File mới `Sources/Models/Dictionaries/SearchEngineTransfer.swift`** (107, thuần `Foundation`) là codec + luật gộp dùng chung cho **cả hai** người gọi ở hai tầng khác nhau: `SearchEnginesConfigView` (Views) và `BackupConfigArchiver` (Services) — đặt ở `Models` vì đó là chỗ duy nhất cả hai được phép nhìn vào mà không đảo chiều phụ thuộc. Nhận diện trùng theo **chữ ký** (tên chuẩn hoá hoa/thường + mẫu URL) chứ **không** theo `id`: cùng một công cụ thêm tay ở hai máy có `id` khác nhau nên so theo `id` sẽ nhân đôi; ngược lại `id` đụng nhau thì phát `UUID()` mới, vì `ForEach` dựng theo `Identifiable` và hai hàng cùng `id` là hỏng danh sách. Chốt an toàn khi nhập: > 200 KB, > 50 công cụ, thiếu tên/mẫu URL, hoặc mẫu URL không có `%s` — báo rõ công cụ thứ mấy sai.
* **Màn Công cụ tra cứu nhanh có nút Xuất/Nhập cấu hình JSON** (`SearchEnginesConfigView.swift` 116 → 259): menu `ellipsis.circle` ở toolbar, `DocumentPickerPresenter` đặt trong `.background`, `ShareSheet` qua `.sheet(item:)` với file tạm được dọn ở `onDismiss`, và `confirmationDialog` chọn **Gộp** / **Thay thế toàn bộ** kèm số đếm thật (`SearchEngineTransfer.newCount`) — đúng khuôn các màn Nhập/Xuất khác của repo.
* **`manifest.counts.config`** thêm mới với `decodeIfPresent(…) ?? 0` như mọi khoá khác nên `.fbbackup` tạo trước bản này vẫn decode được (hiện 0); `RestoreOptionsSheet` bật sẵn công tắc khi `counts.settings > 0 || counts.config > 0`, thêm hàng "File cấu hình", và footer nói rõ là gộp thêm quy tắc mục lục + công cụ tra cứu.
* **Sửa hai chỗ mô tả sai**: footer `BackupHubView` từng có thể đọc thành "mọi bản sao lưu đều kèm luật thay ký tự TTS", nhưng file đó đi theo nhóm **tuỳ chọn** `.dictCustom` (từ 1.3.263) — nay footer nêu đúng phần luôn có mặt và subtitle của `.dictCustom` mang thông tin đó ngay tại công tắc.
* **Gate**: `check_architecture.py` giữ đúng **14 violation**, cùng một tập; 2 file mới đều ≤ 400 dòng và đúng 1 type top level (`Report` nest trong `BackupConfigArchiver`, `Failure` nest trong `SearchEngineTransfer`), `architecture_allowlist.json` không đổi. `validate_links.py`: 6 doc stale (`00_index`, `02_file_graph`, `03_type_graph`, `09_dependency_rules`, `11_subsystems`, `14_complexity_report`) đã cập nhật + `--accept`, PASS 16 doc / 361 file.

## [1.3.264] - 2026-08-24

### Backup kèm cài đặt, sửa nghĩa tại chỗ, không dọn truyện trên kệ

Thêm **3** file Swift (356 → 359), sửa 10 file; **không** `@Model` nào đổi shape, **không** thêm `BackupScope` case, **không** thêm dependency. Chưa biên dịch (viết trên Windows, không có `xcodebuild`/`xcodegen`) — **phải chạy `xcodegen generate` trên macOS/CI** vì có file mới.

* **Bản sao lưu mang theo cài đặt & cấu hình của app.** `Sources/Services/Backup/BackupSettingsArchiver.swift` (123) chụp `UserDefaults.standard.dictionaryRepresentation()` thành **plist nhị phân** ở entry `settings/user_defaults.plist` — plist chứ không JSON vì nó giữ đúng kiểu `Bool`/`Int`/`Double`/`Date`/`Data`/mảng/từ điển. Khối này **luôn** được ghi vào archive (vài chục KB) và **không** thuộc `BackupScope` nào: thêm case là bản app cũ decode `manifest.scopes` (kiểu `[BackupScope]`, decoder tổng hợp) thất bại — cùng lý do với `dict/tts/` ở 1.3.263. Quyền quyết định chuyển sang chiều khôi phục bằng cờ `BackupRestoreWorker.Options.restoreSettings`.
* **Bộ lọc khoá là luật hình dạng + deny-list, không phải danh sách trắng**: nhận khoá bắt đầu bằng chữ **thường ASCII** (khoá app là camelCase/snake_case, rác hệ thống là `Apple*`/`NS*`/`WebKit*`/`PK*`/`com.apple.*`/`kCF*`), rồi trừ khoá API & token (`google_cloud_tts_custom_api_key`, `googleDriveClientId`), đường dẫn tuyệt đối theo máy (`ttsExtensionLocalPath`), mốc lượt chạy cuối của ba phân hệ nền, hàng đợi retry xoá file, tiến độ đọc từng truyện (`lastChapterIndex_*`, `lastParagraphIndex_*`) và hẹn giờ tắt TTS. Nhờ vậy khoá cài đặt thêm sau này **tự vào** bản sao lưu. Refresh token Drive nằm ở Keychain/file nên vốn không có đường lọt vào đây.
* **Ba chốt an toàn**: mỗi giá trị phải qua `PropertyListSerialization.propertyList(["value": value], isValidFor: .binary)` trước khi vào snapshot (giá trị không hợp lệ làm `data(fromPropertyList:)` ném ObjC exception **không catch được**); chiều đọc lọc `isExportable` **lần nữa** vì file có thể do bản app khác tạo; và ghi cài đặt là **bước cuối** của `restore()` — manager đang chạy vẫn giữ giá trị cũ trong RAM nên `BackupCoordinator` nối "Mở lại app để cài đặt có hiệu lực" vào toast. `manifest.counts.settings` decode lenient (`?? 0`) nên file tạo trước bản này vẫn đọc được, và công tắc trong `RestoreOptionsSheet` tự tắt + mờ khi số đó là 0.
* **Màn "Quản lý nghĩa từ": mỗi nghĩa là một ô nhập sửa được, kèm nút lên/xuống.** `Sources/Views/Dictionary/ManageDefinitionsDraft.swift` (126, thuần `Foundation`) giữ bản nháp với `Row.id: UUID` — bắt buộc đổi từ khoá-theo-chuỗi sang khoá-theo-`UUID` vì nội dung ô nhập không còn là khoá ổn định, và hai nghĩa trùng chữ vẫn phải là hai hàng khác nhau; `Sources/Views/Dictionary/ManageDefinitionRowView.swift` (73) là một hàng gồm `TextField` + 4 nút icon `.borderless` (lên/xuống/chèn ô trống phía trên/xoá, hoặc hoàn tác khi đã xoá mềm).
* **`ManageDefinitionsView.swift` 343 → 186 dòng**: bỏ 4 khối `TextField` "thêm nghĩa" gần như giống nhau và hộp thoại nhập nghĩa (thành thừa khi mọi hàng đều sửa được), bỏ `localMatches`/`deletedMeanings`. Đĩa chỉ bị ghi **một lần lúc đóng màn** (`hasSaved` + `.onDisappear`) và chỉ cho nhóm mà `activeMeanings` khác bản đọc lúc mở; xoá là **xoá mềm** (gạch ngang, hoàn tác được); `Row.preservesEmpty` — chỉ đúng với hàng rỗng đọc từ đĩa — giữ quy ước nghĩa rỗng đầu chuỗi (`/foo`) khỏi bị viết lại lặng lẽ. Chữ ký `ManageDefinitionsView(word:bookId:matches:onChanged:)` không đổi nên call site duy nhất không phải sửa.
* **Lượt dọn truyện cũ không bao giờ chạm truyện trên Kệ sách** (yêu cầu tường minh của người dùng): `guard !book.isOnShelf` thêm vào `StaleBookCleanupCoordinator.staleBookIds` ngay trước chốt `isLocalBook`, nên phạm vi thu về đúng phần **lịch sử** (`isOnShelf == false`). Vì cả `runIfDue`, `runNow` và `previewStaleCount` dùng chung bộ lọc này, số đếm trong Cài đặt vẫn khớp số truyện thật sự bị xoá; hai footer của `StaleBookCleanupSettingsView` sửa lại cho khỏi hứa sai. `BookStorageManager` **không** bị sửa — nó vẫn phải xoá được truyện trên kệ khi người dùng tự bấm xoá.
* **Gate**: `check_architecture.py` giữ đúng **14 violation**, cùng một tập; 3 file mới đều ≤ 400 dòng và đúng 1 type top level (`Report` nest trong `BackupSettingsArchiver`, `Row` nest trong `ManageDefinitionsDraft`), `architecture_allowlist.json` không đổi. `validate_links.py`: 5 doc stale (`00_index`, `02_file_graph`, `09_dependency_rules`, `11_subsystems`, `14_complexity_report`) đã cập nhật + `--accept`, PASS 16 doc / 359 file.

## [1.3.263] - 2026-08-24

### Tự xoá truyện cũ, tuỳ chọn số chương, backup từ điển TTS, xoá báo đã đọc

Thêm **4** file Swift (352 → 356), sửa 15 file; **không** `@Model` nào đổi shape, **không** thêm `BackupScope` case, **không** thêm dependency. Chưa biên dịch (viết trên Windows, không có `xcodebuild`/`xcodegen`) — **phải chạy `xcodegen generate` trên macOS/CI** vì có file mới.

* **Tự động xoá truyện lâu không đọc** (phân hệ nền thứ ba, đúng khuôn tự động sao lưu Drive): `Sources/Services/Cleanup/StaleBookCleanupPolicy.swift` (126) chủ sở hữu duy nhất mọi khoá UserDefaults + ngưỡng, `StaleBookCleanupCoordinator.swift` (120) `@MainActor` trả `Outcome`, `Sources/Views/Settings/Cleanup/StaleBookCleanupSettingsView.swift` (208) + `StaleBookCleanupSettingsSection.swift` (12). Ba khác biệt cố ý so với hai lượt nền kia: cờ mặc định **tắt** (nó xoá dữ liệu, không chỉ tốn pin/mạng), `startupDelayNanoseconds` **40 s** thay vì 25 s (bản sao lưu phải chạy trước khi có gì bị xoá), và `markRun()` gọi **trước** phần việc (lượt chết giữa đường vẫn tiêu nhịp — nghiêng về xoá ít hơn dự kiến). Ngưỡng ngày kẹp `7...365`, hai chế độ `.cooldown`/`.daily`.
* **Bốn chốt chặn xoá oan** vì xoá là không hoàn tác: cờ mặc định tắt; truyện `isLocalBook` **luôn** được loại (không tải lại được); `protectedBookIds()` loại truyện đang phát TTS / có widget nổi và truyện có task tải `.pending`/`.running`; mốc so là `Book.lastReadDate`. Quét là `fetch(FetchDescriptor<Book>())` **không predicate** rồi lọc trên RAM trong `Task.detached` với `ModelContext` riêng (`autosaveEnabled = false`) — bộ dịch SQLite iOS 17 lỗi với predicate chuỗi. Việc xoá thật vẫn do `BookStorageManager.deleteBooksAsync` làm, coordinator không chạm file lẫn `ModelContext.delete`. Cài đặt hiện **số truyện sẽ bị xoá** ngay khi kéo thanh trượt, nút "Dọn ngay" có `confirmationDialog`.
* **Số chương "Tuỳ chọn" cho tải/xuất truyện**: `ChapterLimitOption` từ `enum Int` thành `struct RawRepresentable` (`Hashable, Codable, CaseIterable, Sendable`) nên nhận mọi số `1...1000`; `.custom` = `-1` là **nhãn picker sống trong `TaskOptionsSheet`**, `startTask()` quy đổi sang số thật trước khi `enqueueTask` nên `-1` không bao giờ vào `DownloadTaskModel.limitRaw`. `TaskOptionsSheet` 209 → **277** (thanh trượt `1...1000` step 1 + hai nút −/+ `.borderless`, `clampCustomLimit`), `DownloadManager` 437 → **467**, `DownloadManager+TaskStore` bỏ được `?? .all` vì init struct không thất bại. Cửa ra vẫn là `limitValue` (mọi `rawValue <= 0` ⇒ không giới hạn) nên tầng tải/xuất không phải sửa.
* **Từ điển phiên âm TTS vào sao lưu**: 3 file tiền xử lý ở `FreeBook/TTS/` đi theo nhóm `.dictCustom` qua thư mục entry `dict/tts/` — **không** thêm `BackupScope` case (scope là `Codable`, rawValue nằm trong `manifest.scopes`, thêm case là bản build cũ hết giải mã được). `BackupPaths` 113 → **130** giữ vai trò nơi duy nhất biết tên entry; `BackupDictionaryArchiver` 93 → **114**; `BackupDictionaryRestorer` 127 → **242** trộn **theo khoá** (`mergeStringPlist`, `mergeReplacementRules`) rồi nạp lại cache trong bộ nhớ (`TextPreprocessor.loadResources()`, `TTSReplacementManager.loadRules()`) — không nạp lại thì file mới chỉ có hiệu lực từ lần khởi động sau. Hạn chế đã biết: trộn nên **không có tombstone**, mục đã xoá sẽ sống lại khi khôi phục từ bản cũ.
* **Truyện local luôn được sao lưu nội dung dù tắt `.content`** vì chúng không tải lại được từ mạng: `BackupExportWorker` 240 → **248** chọn `contentBooks` = toàn bộ khi có `.content`, ngược lại `filter { $0.isLocalBook }`; `BackupRestoreWorker` 245 → **249** phản chiếu bằng `options.scopes.contains(.content) || book.isLocalBook`. Thêm computed `BackupPayload.BookRecord.isLocalBook` (204 → **217**) để tầng payload không phải mở SwiftData. Hạn chế được ghi nhận, không sửa: `BackupSizeEstimator` (45 → **54**) báo thiếu trong ca này vì tên file là `sha256(bookId)`, và `manifest.scopes` vẫn không ghi `.content` — khôi phục vẫn đúng vì nó quyết định theo `book.isLocalBook`, không theo scope.
* **"Xoá tất cả thông báo" giờ chỉ xoá thông báo đã đọc** (đảo lại quyết định của 1.3.260): `NotificationInboxManager` 88 → **93** đổi `deleteUnread()` thành `deleteRead()` (`records.filter { !$0.isRead }`) + thêm `hasRead`. Vẫn cố ý **không** toast xác nhận: `ToastManager.show` ghi vào chính hộp thư này nên toast sẽ tạo ngay một thông báo chưa đọc mới. `NotificationInboxStore.clearAll()` còn đó nhưng không UI nào gọi.
* `check_architecture.py` giữ **14 violation, đúng cùng một tập** trước/sau; 4 file mới đều ≤ 400 dòng và đúng 1 type top level, `SettingsView` 441 → 443 (baseline 453), không nới baseline, không sửa `architecture_allowlist.json`. CodeGraph: cập nhật `00`, `02`, `03`, `04`, `06`, `08`, `09`, `10`, `11`, `14`; `13` đã xem, không cần đổi.

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
