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
## Một enum mới ở Services, một View rời file chủ, hai type mở rộng shape (1.3.336)

* **Type mới duy nhất ở Services: `TranslationPunctuationMapper`** — `public enum` không case, chỉ `private static let mapping: [Character: String]` + `public static func apply(to:)`. Bảng là `[Character: String]` (không phải `[Character: Character]`) vì một ký tự ra nhiều ký tự: `。` → `". "`. Nó **thay thế** `TranslateUtils.punctuationMapping` (đã xoá) — đừng dựng lại bảng thứ hai ở bất kỳ đâu.
* **`AddWordSheet` chuyển từ `public struct` trong `TTSDictionaryEditView.swift` sang `struct` ở file riêng.** Hạ `public` → `internal` an toàn vì repo là **một** module. Shape state đổi: bỏ `librarySuggestion: String?`, thêm `suggestions: [TTSPhoneticSuggestion]` + `isBuildingSuggestions: Bool`; `suggestionLoadTask` giữ nguyên. `init(initialKey:showSuggestions:onAdd:)` **không đổi** nên hai call site (Reader, màn từ điển TTS) không phải sửa.
* **`TTSPhoneticSuggestion` và `TTSPhoneticSuggestion.Origin` khai thêm `Sendable`.** Bắt buộc, không phải trang trí: struct/enum `public` không được suy ra `Sendable` ngầm, mà giá trị này giờ đi qua biên `Task.detached`. Các field đều là `String`/`Bool`/enum raw-String; `Color` chỉ là computed property nên không ảnh hưởng.
* **`QuickTranslationRuleDraftStore.Draft` +2 field**: `replacementSelectionStart`, `replacementSelectionLength`. `Draft` là struct trong RAM (không `Codable`) nên thêm field không có vấn đề tương thích; nó vẫn `Equatable` để `.onChange(of: currentDraft)` hoạt động.
* **`QuickTranslationRulePatternField` +1 tham số `usesMonospacedFont: Bool = true`**, khai bằng `var` (không `let`) để init memberwise vẫn cấp tham số này — `let` có giá trị mặc định bị loại khỏi init memberwise. Đặt **trước** `onFocusChange` để trailing closure vẫn bám đúng tham số cuối.
* **`QuickTranslationRuleEditorSheet` bỏ `@FocusState isReplacementFocused`**: cả hai ô nhập nay là `UIViewRepresentable` và tự báo focus qua `onFocusChange` → `focusedField`. Một cơ chế focus, không phải hai.

## `@Model` thứ 6 và hai field mới trên `Book` (1.3.328)

* **`BookCollection` là `@Model` đầu tiên thêm vào schema kể từ khi repo có 5 model.** Shape: `@Attribute(.unique) collectionId: String`, `name: String`, `sortOrder: Int = 0`, `createdAt: Date = Date()`, và `@Relationship(deleteRule: .nullify, inverse: \Book.collections) books: [Book] = []`. Tên type là **`BookCollection`**, không phải `Collection` — `Collection` sẽ che `Swift.Collection` trong toàn module và làm mọi generic constraint sau này hiểu sai.
* **`Book` đổi shape (thêm, không sửa)**: `isPinned: Bool = false` và `collections: [BookCollection] = []`. Cả hai có giá trị mặc định nên **lightweight migration** đủ — repo không có `VersionedSchema`/`SchemaMigrationPlan`, và `ModelContainer` init thất bại là `fatalError`, nên bất kỳ thay đổi phá vỡ nào ở đây sẽ làm app không mở được.
* **Chiều nghịch khai đúng một đầu**: macro `@Relationship(inverse:)` nằm ở `BookCollection.books`, còn `Book.collections` để trơn — giống cặp `Repository.extensions` ⇄ `Extension.repository`. Khai `inverse:` cả hai đầu là dựng sai quan hệ.
* **`deleteRule: .nullify` là bất biến ngữ nghĩa, không phải mặc định tình cờ**: xoá một bộ sưu tập chỉ tháo liên kết; `.cascade` ở đây nghĩa là xoá sách thật khỏi kệ.
* `BookTransactionError` thêm 3 case (`collectionNotFound`, `invalidCollectionName`, `duplicateCollectionName`) — enum này chỉ dùng nội bộ qua `LocalizedError`, không ai `switch` exhaustively nên thêm case không phá call site nào.
* **Type mới ở tầng View**: `BookSheetAction` (+ nested `Mode`, `Target`), `BookActionRunner` (`@MainActor struct`, chỉ static), `BookActionSheet`, `ShelfBookRowView`, `NewChapterBadgeView`, `CollectionsTabView`, `CollectionDetailView`, `CollectionPickerSheet`. `BookDetailView` thêm đúng một `@State` (`collectionPickerBook: Book?`).
* **Type bị xoá**: `TTSTransliterationTesterView`, `TransliterationGoldenSet` (kèm nested `Case`). Hai method bị xoá: `EspeakPhonemizer.probeVoices`, `VietnameseTokenGate.explain` — cả hai chỉ có màn đã xoá gọi.
* `BackupPayload.CollectionRecord` là record thứ 5 của archive. `BackupPayload.BookRecord` **đổi shape**: thêm `isPinned: Bool?` — optional có chủ đích, vì `init(from:)` tổng hợp của Swift không dùng giá trị mặc định nên khoá không-optional mới sẽ làm mọi `.fbbackup` cũ decode lỗi. `BackupManifest.Counts` thêm `collections` (an toàn nhờ `init(from:)` viết tay sẵn có).

## `KeyboardDismissGesture` có đường tháo, không chỉ đường cài (1.3.323)

* **Bề mặt công khai không đổi**: vẫn đúng `shared` + `activate()`. Thay đổi nằm ở phần private — thêm `keyboardWillHide()` (`@objc`) và `uninstall()`, đối xứng với `keyboardWillShow()`/`installIfNeeded()`. Người gọi duy nhất (`AppLaunchRootView.onAppear`) không phải sửa gì.
* **Bất biến mới của type**: recognizer chỉ tồn tại trong quãng bàn phím đang hiện. Nghĩa là "`activate()` đã chạy chưa" (cờ `isObserving`) và "recognizer đang có trên window hay không" là **hai** trạng thái khác nhau — cái sau không được cache, phải đọc từ chính window qua `UIGestureRecognizer.name`.
* **`isEditableTextInput(_:)` giữ nguyên hợp đồng** (`as?` + `isEnabled`/`isEditable`, không so tên class) và vẫn cố ý trả `false` cho `UITextView` chỉ đọc. Điều nó **không** làm được là phân biệt "tap vào chữ" với "vừa bôi đen chữ xong rồi thả tay" — cùng một `UITapGestureRecognizer` nhìn hai cú đó y như nhau. Vì vậy hàng rào của vùng bôi đen là **vòng đời recognizer**, không phải bộ lọc touch.

## API moi cua debug server (1.3.303)

* **`ExtensionDebugServer` la mat tien duy nhat cho tang Views**: `start(container:serviceName:)`, `stop()`, `statusStream()`, `approvePairing()`, `rejectPairing()`, `decideInstall(id:approved:)`. `NWListener`/`NWConnection` khong lo ra ngoai actor nay.
* **`ExtensionDebugPairingAuthority` khong co API "cap session" truc tiep.** `requestPairing(token:clientName:)` chi tra `.success` nghia la *duoc phep xin*; `isPaired` chi `true` sau `approvePending()`. Khong co duong nao bo qua buoc bam tren thiet bi.
* **`ExtensionDebugCommandRouter` nhan `send` closure**, khong nhan `NWConnection`. Nho vay router doc lap voi tang truyen va khong giu tai nguyen socket.
* **`ExtensionDebugInstalledSnapshot` la ranh gioi `@Model`**: router doc SwiftData bang `ModelContext` rieng roi copy sang struct `Sendable`; khong `Extension` nao ra khoi context cua no.
* **`ExtensionDraftStagingStore` chi nhan `relativePath` + `Data`** - khong co overload nao nhan `URL` hay path tuyet doi, nen client khong co API de chi dinh cho ghi.
* **`ExtensionDebugInstallGate.requestApproval(_:) async -> Decision`** la diem treo: no bien "lenh tu mang" thanh "cho nguoi bam". `cancelPending()` la nghia vu cua moi duong tat may - khong goi la `Task` cua router treo mai.
* `Data.sha256Hex()` tach khoi `String.sha256()`: snapshot la **byte**, encode lai sang String truoc khi bam se lam hong checksum file nhi phan.

## API mở rộng widget TTS từ Reader (1.3.277)

* `TTSFloatingWidgetWindowManager` thêm state nội bộ `shouldRevealOnNextShow` và method `requestRevealOnNextShow()`. Đây là API tầng View, không đi qua `TTSManager` để giữ `Services/TTS` không phụ thuộc `Views/TTSWidget`.
* `FloatingWidgetContainerViewController` thêm method `reveal(animated:)` dùng lại `FloatingWidgetViewModel.reveal()` và layout hiện có. Không thêm enum mode mới: `WidgetMode` vẫn chỉ có `.peeking` và `.revealed`.
* `ReaderView.startTTS(...)` là caller duy nhất của request này, nên cả nút headphones và menu bôi đen "Nghe" được phủ mà không đổi chữ ký `TTSManager.startSpeaking(...)`.

## Snapshot highlight chuẩn bị TTS (1.3.276)

* `TTSPlaybackSnapshot` thêm hai field public `preparingParentParagraphIndex: Int?` và `preparingHighlightRange: NSRange?`. Đây là **visual state trước audio**, tách khỏi `currentParentParagraphIndex`/`highlightRange` active để `commitAudibleParagraphState` vẫn tạo snapshot khác khi audio thật bắt đầu.
* `ReaderTTSStateSnapshot` mirror hai field trên nhưng chỉ phát khi `ReaderTTSStateReader.scope(to:)` khớp `playingBookId`; Reader sách khác vẫn nhận `nil` và không redraw theo lượt chuẩn bị của phiên TTS khác.
* `ParagraphCardView` và `ReaderTextView` thêm cờ `highlightIsPreparing: Bool`. Type shape của `ParagraphItem`, `TTSParagraph`, `TTSPlaybackContext` và mọi `@Model` không đổi.

## Hai bộ rule, hai chủ sở hữu: `QuickTranslationRuleScope` + `QuickTranslationRuleBookStore` (1.3.274)

* **`QuickTranslationRuleScope` (`Sources/Models/Translation/`) là `enum { global, book(String) }`** — ở tầng Models vì cả Service (`DisableStore`, `Transfer`) và View (`QuickTranslationRuleListView`, hub từ điển) đều nhận nó làm tham số. `rank` (0 riêng / 1 chung) là **hằng số duy nhất** quyết định rule riêng thắng rule chung.
* **`QuickTranslationRuleBookStore` là chủ sở hữu thứ hai, không phải bản tổng quát hoá của `QuickTranslationRuleStore`.** Store chung hard-code một file; store riêng giữ cùng chính sách TXT canonical và **dùng lại** `QuickTranslationRuleParser` / `Compiler` / `QuickTranslationRuleRecordStore` nên phần khó không bị cài lại lần hai.
* Cache snapshot theo `bookId` là **LRU cap 3**: bộ riêng nhỏ nên compile lại rẻ, còn giữ mọi truyện thì bộ nhớ phình theo số truyện từng mở. Hai `NSLock` (`mutationLock` → `lock`) luôn khoá theo một chiều nên không có deadlock.
* **`QuickTranslationCompiledRule.scopeRank`** (mặc định `1`) là tiêu chí ưu tiên **thứ 5** trong `select`, đứng ngay trước `sourceLine`. Trong một bộ đơn lẻ nó là hằng số ⇒ thứ tự cũ của bộ chung **không đổi**.

## `QuickTranslationRuleDisableStore` + `QuickTranslationRuleDisableFile` — tắt rule bằng file (1.3.274)

* **Bật/tắt không sửa file rule.** Rule bị tắt vẫn nằm trong `snapshot.rules` (để bật lại được và giữ nguyên `sourceLine`); chỉ có **mẫu** của nó được ghi vào một file thứ hai: `translate/QuickTranslateRulesDisabled.txt` (chung) hoặc `translate/books/<bookId>/QuickTranslateRulesDisabled.txt` (riêng).
* **`QuickTranslationRuleDisableFile` là hàm thuần trên `String`** (`parse`/`serialize`/`adding`/`removing`/`union`), không chạm `FileManager` — cùng tinh thần key-based của `QuickTranslationRuleRecordStore`, để chỉ có **một** nơi ghi file.
* **`Snapshot.isDisabled(pattern:scopeRank:)` là toàn bộ ngữ nghĩa**, và nó là ngữ nghĩa của VP riêng/chung: rule bộ riêng chỉ chịu file tắt riêng; rule bộ chung chịu file tắt chung (mọi truyện) **hoặc** file tắt riêng của truyện đang đọc. Muốn dùng lại một rule đã tắt chung ở đúng một truyện thì thêm mẫu vào bộ rule riêng của truyện đó.
* Khoá là **mẫu** (phần trước dấu `=`), không phải `sourceLine`: số dòng đổi sau mỗi lần thêm/xoá. Hết mẫu thì file bị **xoá** thay vì để lại file rỗng.

## `QuickTranslationRuleTrace` — DTO chẩn đoán, giữ cả rule thua (1.3.274)

* `QuickTranslationRewriteResult` chỉ giữ rule **thắng** nên không dùng được cho màn Check rule. `QuickTranslationRuleTrace` (Models) mang `scope` + `pattern` để hành động được ngay từ chip, `sourceRange`/`matchedText` để tô cụm, `captures` để hiện nghĩa **từng token**, và `Status` 6 case: `applied` · `lostOverlap(toSourceLine:)` · `disabledGlobally` · `disabledForBook` · `tokenDisabled` · `tooComplex`.
* **`id` xác định theo scope/pattern/location — không phải `UUID()` mới mỗi lượt.** Một rule khớp nhiều vị trí trong đoạn ⇒ mỗi vị trí một chip, và chẩn đoán lại không dựng lại cả dải.
* Hành động xoá dùng `pattern` (vế trái rule) như nghiệp vụ từ điển; `sourceLine` chỉ còn là tie-break/hiển thị sau khi compile lại.

## `QuickTranslationRuleMatcher.Capture` — một mảng, không hai mảng song song (1.3.274)

* `captures` đổi từ `[String]` sang `[Capture]` (`text` + `sourceRange?`) vì màn Check rule phải hiện **chữ gốc** của từng token, mà range đó trước đây bị bỏ dù mọi call site `store(...)` đều đang biết `position` và độ dài đã nuốt.
* Bắt buộc là **một** mảng: matcher rollback bằng `let saved = captures` … `captures = saved` ở **5** chỗ; hai mảng song song chỉ cần quên một chỗ là range lệch âm thầm. `QuickTranslationCompiledRule.render(captures:)` giữ nguyên chữ ký `[String]`, engine truyền `match.captureTexts`.

## Type mới ở tầng Models: DataImportMode (1.3.269)

* **`DataImportMode` là `enum String, CaseIterable, Sendable` ở `Sources/Models/Dictionaries/`, không phải type cục bộ của một màn.** Nó tồn tại vì chữ "Gộp" trong app đang mang **hai nghĩa trái ngược** tuỳ màn: `DictionaryCache.importEntries(isMerge:)`, `JunkFilterManager.importRules(mode: .merge)` và `TranslateUtils.mergeTOCRules` hiểu là *đè key trùng*, còn `TTSReplacementManager.importRules(mode: .merge)` và `SearchEngineTransfer.merged` hiểu là *giữ bản cũ*. Ba case `replaceAll` / `overwriteExisting` / `keepExisting` buộc mỗi màn nói rõ ai thắng khi trùng khoá.
* **Ở tầng `Models` chứ không `Views`**: `QuickTranslationRuleStore.importRules(text:source:mode:)` (Service) nhận nó làm tham số, còn `QuickTranslationRulesView` (View) dựng dialog từ `allCases` — để cùng dùng được thì enum phải thuần Foundation và nằm dưới cả hai. `actionTitle`/`explanation`/`isDestructive` là dữ liệu trình bày *không phụ thuộc SwiftUI*, nên vẫn hợp luật `SERVICE_SWIFTUI_IMPORT`.
* **Chỉ `replaceAll` mang `isDestructive == true`** — dialog dùng cờ này để gắn `role: .destructive`, thay vì mỗi màn tự đoán nút nào là nút phá dữ liệu.
* Hiện chỉ màn rule dịch dùng; 8 màn còn lại trong `Docs/CheckList/import-3-modes-checklist.md` sẽ chuyển sang sau, và `DictionaryImportModeDialogModifier` (`onSelect(Bool)`) vẫn giữ nguyên tới lượt đó.

## `QuickTranslationRuleEditorSheet.Mode` — enum lồng, `Identifiable` có lý do

* `case add` / `case edit(pattern:replacement:sourceLine:)`, `id` là `"add"` hoặc `"edit:<line>:<pattern>"`. Conform `Identifiable` để mở sheet bằng `.sheet(item:)`: mở theo *dữ liệu* thì không có khoảng thời gian sheet đã hiện mà state còn rỗng như cách `isPresented` + biến phụ.
* `pattern` trong case `edit` vẫn mang ngữ nghĩa key cho thao tác lưu; `sourceLine` chỉ để in dòng lỗi/đối chiếu ngắn hạn, không phải định danh hàng của `List`.

## `QuickTranslationRuleTokenSettings` — policy Foundation, không phải thuộc tính của rule (1.3.272)

* `Kind` là raw enum của đúng 8 cú pháp `<n>`, `<y>`, `<L>`, `<ne>`, `<pn>`, `<vp>`, `<hv>`, `<w>`; mỗi case sở hữu một khoá `UserDefaults` lower-camel-case và thiếu khoá nghĩa là `true`. Type sống ở `Services/Translation/Engine/` nhưng chỉ `import Foundation`, nên engine và View cùng dùng được mà Service không phụ thuộc ngược vào SwiftUI.
* `Configuration` chỉ là `Set<Kind>` bất biến của **một** lượt rewrite. `signature` duyệt `Kind.allCases` theo thứ tự khai báo, không dùng `hashValue`, nên có thể làm một phần cache key ổn định giữa process.
* `QuickTranslationRuleElement.sourceTokenKinds` giữ lại syntax trước khi parser hạ `<w>` thành `[name, pronoun, vietPhrase]`; compiler gộp đệ quy các element/group thành `QuickTranslationCompiledRule.requiredTokenKinds`. `isEnabled(for:)` là gate toàn rule: literal-only luôn qua, còn một token tắt trong optional, alternative hoặc `|` chặn rule.

## `QuickTranslationRuleSnapshot` — snapshot rule canonical, không giữ handle UI

* Snapshot chỉ giữ `rules`, `literalIndex`, `sourceHash`, `generation` và warning đã cắt. Không còn `Row.id`, `sourceRevision` hay UUID tạm song song với rule.
* `QuickTranslationRuleListView.DisplayRule` dùng `pattern` cho `ForEach` vì file rule đã được canonical first-wins, nên mỗi pattern là duy nhất trong snapshot.
* CRUD/import/tải/khôi phục đều đi qua `QuickTranslationRuleRecordStore`: bỏ dòng hỏng, duplicate lấy dòng đầu, sửa key cũ giữ vị trí, key mới append cuối rồi ghi lại TXT `pattern = replacement`.

## Type mới ở tầng Common: KeyboardDismissGesture (1.3.266)

* **`KeyboardDismissGesture` là `@MainActor final class: NSObject, UIGestureRecognizerDelegate`** — không phải `enum` hàm tĩnh như `NavigationBarAppearance` cùng thư mục, vì nó **phải** là đối tượng: cần `target` cho `#selector` của `UITapGestureRecognizer`, cần là `delegate` của recognizer, và cần một cờ `isObserving` để `activate()` idempotent. `NSObject` là điều kiện của cả hai vai đó.
* **Toàn bộ trạng thái là một `Bool`**: `isObserving`. Danh sách window đã cài **không** được giữ trong type — mỗi lượt `installIfNeeded()` tự nhận diện bằng `UIGestureRecognizer.name == "FreeBookKeyboardDismissTap"`, nên window bị hủy/tạo lại không để lại tham chiếu treo và không cần `NSHashTable` weak.
* **Không có type nào của repo xuất hiện trong chữ ký của nó** — chỉ `UIWindow`, `UITapGestureRecognizer`, `UITouch`, `UIView`, `UITextField`, `UITextView`, `UISearchBar`. Việc phân loại "ô nhập được" đọc `isEnabled`/`isEditable` chứ không so tên class, nên `ReaderUITextView` (chỉ đọc) không bị coi là ô nhập.
* Quan hệ duy nhất với phần còn lại: `AppLaunchRootView` gọi `KeyboardDismissGesture.shared.activate()`. Type này **không** thay thế `View.hideKeyboard()` ở `Common/Extensions/View+Keyboard.swift` — cái đó là lệnh tắt chủ động do người dùng bấm, còn đây là recognizer nền.

## Type của codec công cụ tra cứu nhanh (1.3.265)

* [`SearchEngineTransfer`](../../Sources/Models/Dictionaries/SearchEngineTransfer.swift#L1) là `public enum` namespace thuần (không case, không state, chỉ `Foundation` + `SearchEngine`) — đặt ở tầng `Models` **vì có hai người gọi ở hai tầng khác nhau**: [`SearchEnginesConfigView`](../../Sources/Views/Settings/Search/SearchEnginesConfigView.swift#L1) (Views) và [`BackupConfigArchiver`](../../Sources/Services/Backup/BackupConfigArchiver.swift#L1) (Services). Đưa logic này vào một trong hai tầng đó là buộc tầng kia phải phụ thuộc ngang.
* Type lồng duy nhất (giữ đúng 1 type top level): `enum Failure: LocalizedError, Equatable` với 6 case mang tham số định vị lỗi — `fileTooLarge(maxKB:)`, `invalidJSON`, `empty`, `tooMany(count:max:)`, `emptyField(index:)`, `missingPlaceholder(index:name:)`. `Equatable` để so sánh được mà không phải khớp chuỗi `errorDescription`.
* Thành viên `static`: hai hằng chốt `maxEngineCount = 50` / `maxFileSizeBytes = 200 * 1024`, `encode(_:) throws -> Data` (`prettyPrinted` + `sortedKeys` để file xuất ra diff được), `decode(_:maxSizeBytes:) -> Result<[SearchEngine], Failure>` (không `throws` — mọi lỗi là lỗi *dữ liệu người dùng*, caller phải hiện được thông báo cụ thể), `merged(current:imported:)`, `newCount(current:imported:)` và `private signature(of:)`.
* **Luật gộp là hợp đồng của `merged`, không phải chi tiết cài đặt**: khoá trùng lặp là `signature` = tên đã trim + lowercase, `\u{1}`, mẫu URL đã trim — **không** phải `id`. `SearchEngine.id` là `UUID` sinh lúc thêm nên cùng một công cụ ở hai máy có hai id; ngược lại hai bản ghi khác nhau vẫn có thể trùng id (khôi phục chồng nhau), nên khi `id` đụng thì `merged` phát `UUID()` mới — hai hàng cùng id làm `ForEach` mất identity. Thứ tự bản trên máy được giữ, phần nhập chỉ nối vào cuối.
* [`SearchEngine`](../../Sources/Models/Dictionaries/SearchEngine.swift#L1) giữ nguyên shape (`Identifiable, Codable, Hashable`: `id`, `name`, `urlTemplate`) và chỉ thêm `public static let storageKey = "custom_search_engines"` — trước đây chuỗi này bị nhắc lại ở `loadEngines`/`saveEngines`, giờ có thêm hai người đọc ngoài file (`BackupConfigArchiver` để ghi `config/search_engines.json`, `BackupSettingsArchiver` để **loại** khoá khỏi khối plist).
* Không `@Model` nào đổi shape ⇒ không rủi ro lightweight migration.

## Type của hộp thư thông báo sau lượt 1.3.263

* [`NotificationInboxManager`](../../Sources/Common/Services/NotificationInboxManager.swift#L1) đổi **API xoá theo lô**: `deleteUnread() -> Int` biến thành [`deleteRead() -> Int`](../../Sources/Common/Services/NotificationInboxManager.swift#L84) (`records.filter { !$0.isRead }` giữ lại, tức xoá đúng phần **đã** đọc), và có thêm computed [`hasRead`](../../Sources/Common/Services/NotificationInboxManager.swift#L30) đứng cạnh `hasUnread`. Cả hai giữ nguyên hình dạng cũ: `@discardableResult`, trả số dòng đã xoá, ghi đĩa bằng `Task { await NotificationInboxStore.shared.replace(with:) }` với **snapshot** chụp sau khi sửa `records` (không capture `self`). Manager **không** có API xoá trắng — `NotificationInboxStore.clearAll()` vẫn tồn tại ở tầng lưu trữ nhưng không có đường nào từ UI tới nó, nên mục menu duy nhất giờ là "Xoá thông báo đã đọc" và thông báo chưa đọc chỉ mất khi người dùng tự xoá từng dòng.
* Không có type nào trong `Sources/Models/**` hay `Sources/Common/**` được thêm/xoá/đổi shape ở lượt này; `NotificationInboxRecord` và `NotificationInboxStore` không đổi, nên dữ liệu đã ghi trên đĩa đọc lại nguyên vẹn.

## Type của trình duyệt bypass nhiều tab và ô URL tự bôi đen (1.3.262)

* [`BypassBrowserTabStore`](../../Sources/Views/Common/BypassBrowserTabStore.swift#L1) — `final class : NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate`. Trạng thái: `@Published private(set) tabs: [BypassBrowserTab]`, `@Published private(set) activeTabId: String`, `private tabObservations: [String: AnyCancellable]`, `static let maxTabCount = 8`. **Cố ý không `@MainActor`** — theo tiền lệ `VisibleWebViewController`, để không xung đột isolation với hai protocol delegate của WebKit (vốn không isolated). Nó chuyển tiếp `objectWillChange` của từng tab lên chính mình nên View chỉ quan sát **một** đối tượng (cần `import Combine`).
* [`BypassBrowserTab`](../../Sources/Views/Common/BypassBrowserTab.swift#L1) — `final class : ObservableObject, Identifiable`. Sở hữu `let webView: WKWebView` + `private var observers: [NSKeyValueObservation]` (6 cái) và 6 `@Published` phản chiếu (`title`, `urlString`, `isLoading`, `progress`, `canGoBack`, `canGoForward`). `pendingUrl` là `URL?` **tiêu thụ một lần** qua `consumePendingUrl()`: tab do WebKit tự nạp (`window.open`) phải để `nil` vì nạp tay sẽ phá navigation. `displayTitle` rơi bậc title → host → `"Trang mới"`.
* [`URLBarTextField`](../../Sources/Views/Common/URLBarTextField.swift#L1) — `struct : UIViewRepresentable` với `Coordinator: NSObject, UITextFieldDelegate` (nest). Coordinator giữ `Binding<String>`/`Binding<Bool>` được **làm mới trong `updateUIView`** (binding cũ trỏ vào snapshot state cũ). Hai binding tách vai rõ: `text` là nội dung, `isEditing` là cửa chặn ghi đè từ observer URL.
* [`BypassBrowserWebPane`](../../Sources/Views/Common/BypassBrowserWebPane.swift#L1) — `UIViewRepresentable` trả về `UIView` **container**, không trả trực tiếp `WKWebView`: kiểu trả về phải cố định trong khi webview đổi theo tab. [`BypassBrowserTabBar`](../../Sources/Views/Common/BypassBrowserTabBar.swift#L1) có `TabPill` nest (`@ObservedObject var tab` để pill tự cập nhật tiêu đề khi tab nền nạp xong). [`BypassBrowserHomePage`](../../Sources/Views/Common/BypassBrowserHomePage.swift#L1) là `enum` namespace thuần (`html(for:)` + `iconSource(for:)` + 2 hằng private).
* [`BypassWebView`](../../Sources/Views/Common/BypassWebView.swift#L1) mất `WebViewStore` và `SwiftUIWebView`; `ExtensionMatch` (nest, `Identifiable` theo `packageId`) và `static var regexpCache: [String: String]` giữ nguyên. Toàn bộ trạng thái webview rời khỏi `@State` sang `@StateObject store` ⇒ không còn hai bản sự thật về URL/tiêu đề.
* [`NavigationBarAppearance`](../../Sources/Common/Utils/NavigationBarAppearance.swift#L1) giữ đúng hình dạng cũ (enum namespace, `applyTitlelessBackButton()` + private `hideBackButtonTitle(in:)`) nhưng đảo cách dùng UIKit: **tạo mới** `UINavigationBarAppearance` cho cả 4 slot thay vì đọc từ proxy rồi sửa tại chỗ — appearance proxy chỉ bảo đảm hợp đồng cho setter.

## Type của vệt tô kết quả tìm, đầu dò cuộn tay và lệnh dọn kho (1.3.261)

* [`ReaderSearchMatcher`](../../Sources/Common/Utils/ReaderSearchMatcher.swift#L1) nay có **4** struct lồng (vẫn đúng 1 type top level): thêm `Highlight { chapterIndex, paragraphIndex, query }`, `Equatable`, không `Identifiable`. Nó **cố ý không mang `NSRange`** — range phải tính trên đúng chuỗi đang hiển thị lúc render (bản dịch hay bản gốc tuỳ công tắc dịch), nên chỉ `query` mới an toàn để lưu. `paragraphIndex` vẫn là `ParagraphItem.id` **sparse**. Thành viên mới: `static firstHighlightRange(of:in:) -> NSRange?` (dùng `NSString.range(of:options:range:locale:)` nên range trả về đã ở toạ độ UTF-16 của chính chuỗi truyền vào — gấp dấu rồi tìm lại sẽ lệch).
* `ParagraphCardView.displayText(for:isTranslationEnabled:)` từ method instance thành **`static`**, không đổi chữ ký còn lại. Đây là nguồn duy nhất của luật "dịch hay gốc"; mọi nơi cần toạ độ ký tự trên chữ người dùng đang thấy phải gọi nó thay vì lặp lại điều kiện. `ParagraphCardView` giữ nguyên `Equatable` và danh sách field so sánh.
* `ReaderSearchView.onSelect` đổi chữ ký: `(Int, Int) -> Void` → `(_ chapterIndex: Int, _ paragraphIndex: Int, _ query: String) -> Void`. Chỉ một call site (`ReaderView`), sheet vẫn không giữ tham chiếu tới view model.
* [`ReaderUserScrollDetector`](../../Sources/Views/Reader/Components/ReaderUserScrollDetector.swift#L1) là `struct: UIViewRepresentable` với 2 type lồng để giữ đúng 1 type top level: `final class Coordinator: NSObject, UIGestureRecognizerDelegate` (giữ `weak var attachedScrollView`, `recognizer`, cờ `didReportForCurrentDrag`; `attach(to:)` idempotent, `detach()` gọi từ `dismantleUIView` **và** `deinit`) và `final class ProbeView: UIView` (`weak var coordinator`, gắn ở `didMoveToWindow`). Field: `threshold: CGFloat = 24`, `onUserScroll: () -> Void`. Ba delegate method trả `true`/`false`/`false` — nhận diện đồng thời, không đòi ai fail, không để ai đòi mình fail.
* [`PruneRepositoryExtensionsCommand`](../../Sources/Models/Extensions/PruneRepositoryExtensionsCommand.swift#L1) là Command DTO bất biến `Sendable`: `repositoryUrl: String`, `keepPackageIds: Set<String>`. `Set` chứ không `[String]` vì bộ lọc tra `contains` cho từng ext của kho. Là DTO **xoá** đầu tiên của phân hệ kho tiện ích, cùng khuôn với `UpsertExtensionCommand`/`UpdateExtensionFolderCommand`.
* `ExtensionTransactionCoordinator` thêm một thành viên `public @discardableResult func pruneRepositoryExtensions(command:in:) -> Result<Int, ExtensionTransactionError>` — **kiểu trả khác** mọi hàm còn lại của coordinator (`Result<Void, _>`): `Int` là số bản ghi đã xoá, `0` là hợp lệ chứ không phải lỗi. Không type nào khác đổi shape.
* Không `@Model` nào đổi shape (`Extension`/`Repository` giữ nguyên field và `deleteRule: .cascade`) ⇒ không rủi ro lightweight migration. `ReaderSearchMatcher.Hit`, `ScrollTarget`, `ReaderNavigationCommit` giữ nguyên.


## Type của tự động sao lưu Drive + appearance nút back (1.3.260)

* [`DriveAutoBackupPolicy`](../../Sources/Services/Backup/DriveAutoBackupPolicy.swift#L1) là `enum` namespace (không case, không state, chỉ `Foundation`) — cùng khuôn với `NewChapterCheckPolicy`. Một type lồng duy nhất để giữ đúng 1 type top level: `enum Mode: String, CaseIterable, Sendable { case cooldown, daily }` + `displayName`. Thành viên `static`: `maxVersions = 5`, `startupDelayNanoseconds: UInt64`, `defaultScopes: Set<BackupScope>`, các accessor `isEnabled`/`mode`/`cooldownHours`/`dailyHour`/`scopes`/`lastRunAt`, và `shouldRun(now:)`/`markRun(now:)`. Mọi accessor đọc-ghi thẳng `UserDefaults` nên **không có instance nào tồn tại** — đừng thêm state vào đây.
* [`BackupCoordinator+AutoDrive.swift`](../../Sources/Services/Backup/BackupCoordinator+AutoDrive.swift#L1) khai `enum AutoDriveBackupOutcome: Sendable, Equatable` **lồng trong `extension BackupCoordinator`** (`case skipped`, `succeeded(fileName:size:prunedRemote:prunedLocal:)`, `failed(String)`) — lồng vì file `extension` vẫn bị `MULTI_PRIMARY_TYPES` tính. Đây là cách phân hệ Service trả kết quả ra ngoài mà không `import SwiftUI`; caller (`MainTabView`, `DriveAutoBackupSettingsView`) mới dịch thành toast.
* `BackupCoordinator` **không đổi shape**, chỉ thêm hai thành viên `internal` `setBusy(_:)` / `setProgress(_:)`. Lý do kỹ thuật: `isBusy`/`progress` là `private(set)` và `private` của Swift là phạm vi **file**, nên extension ở file khác không ghi được. Hai hàm này là cửa duy nhất — không mở thêm và không gọi từ tầng View.
* `BackupPaths` giữ nguyên vai trò namespace, thêm `autoBackupPrefix`/`makeAutoBackupFileName(at:)`/`isAutoBackupFileName(_:)` và rút tiền tố thủ công thành `private manualBackupPrefix`. `makeBackupFileName(at:)` giữ nguyên chữ ký và kết quả.
* **Không thêm case cho `BackupScope`** — rawValue của nó đi thẳng vào `manifest.scopes` của file `.fbbackup`, thêm case là làm bản app cũ decode lỗi. Lượt tự động chỉ chọn tập con case sẵn có (`defaultScopes` cố ý bỏ `.content` và `.dictShared`).
* [`NavigationBarAppearance`](../../Sources/Common/Utils/NavigationBarAppearance.swift#L1) là `enum` namespace thuần, chỉ `import UIKit`, một thành viên public `static func applyTitlelessBackButton()` + private `hideBackButtonTitle(in:)`. Nó **sửa tại chỗ** object `UINavigationBarAppearance` đang có của proxy (không tạo mới) để giữ nền translucent mặc định.
* `NotificationInboxManager` đổi API: thêm `var hasUnread: Bool` + `func markRead(_:)`, **xoá `clearAll()`** và thay bằng `@discardableResult func deleteUnread() -> Int`. `NotificationInboxRecord`, `NotificationInboxStore` và `NotificationInboxView.InboxItem` không đổi shape (`isRead` đã là `var` từ 1.3.258). `NotificationInboxStore.clearAll()` vẫn còn nhưng nay không caller nào trong `Sources/` — giữ lại vì là primitive của store.
* Không type nào bị xoá, đổi kế thừa hay đổi conformance. Không `@Model` nào đổi shape ⇒ không rủi ro lightweight migration.

## Type của tìm-Reader + Trung tâm thông báo (1.3.258)

* **Gỡ mọi type của phân hệ tìm toàn văn 1.3.257** (`ChapterSearch*`, `SearchScope`…) cùng 10 file bị xoá. Không type nào khác tham chiếu chúng.
* [`ReaderSearchMatcher`](../../Sources/Common/Utils/ReaderSearchMatcher.swift#L1) là `enum` namespace thuần (không case, không state) với 3 struct lồng để giữ đúng 1 type top level: `Paragraph { paragraphIndex, isTitle, original, translated }`, `Chapter { chapterIndex, paragraphs }`, `Hit { chapterIndex, paragraphIndex, isTitle, snippet, matchedInTranslated }` (`id = "\(chapterIndex).\(paragraphIndex).\(matchedInTranslated)"`). `paragraphIndex` thừa hưởng `ParagraphItem.id` **sparse** (chỉ số dòng thô, không phải array offset) — dùng thẳng cho điều hướng, không index vào mảng.
* Phân hệ Trung tâm thông báo thêm ba type ở `Common`: [`NotificationInboxRecord`](../../Sources/Common/Services/NotificationInboxRecord.swift#L1) (`Codable, Identifiable, Sendable, Equatable`: `id: UUID`, `message`, `type: ToastType`, `date`, `var isRead`) với `init(from:)` chịu lỗi (mọi field `decodeIfPresent`); `NotificationInboxStore` (actor); `NotificationInboxManager` (`@MainActor ObservableObject`). Kèm **retroactive conformance** `extension ToastType: Codable` (map string `success`/`error`/`info`) — `ToastType` gốc chỉ `Sendable, Equatable`, nên conformance này là điểm phải giữ khi đổi `ToastType`. [`NotificationInboxView`](../../Sources/Views/Shelf/ShelfMain/NotificationInboxView.swift#L1) lồng `enum InboxItem: Identifiable { case newChapter(NewChapterRecord); case toast(NotificationInboxRecord) }` với `date`/`sortRank` để gộp-nhóm hai nguồn.

## Type của phân hệ nhập truyện đa định dạng (1.3.251)

* **Dời tầng, không đổi shape**: `ParserChapter` (`title`, `content`) và `ParsedBook` rời `Sources/Views/Shelf/ShelfMain/ShelfView.swift` xuống `Sources/Services/Import/` — bắt buộc, vì parser ở tầng Services không được trả về type khai trong tầng View (sẽ đảo chiều phụ thuộc). Cả hai vẫn `Sendable`.
* `ParsedBook` **đổi shape** (thêm field, mọi field mới có `= nil` nên call site cũ biên dịch không đổi): `author`, `desc`, `coverData: Data?`, `remoteCoverUrl: String?`, `structureNote: String?`. `title` + `chapters` giữ nguyên vị trí và ngữ nghĩa.
* **Xoá**: `TXTReanalysisResult` — thay bằng [`BookImportService.Result`](../../Sources/Services/Import/BookImportService.swift#L1) (`parsed`, `format`, `autoDecodeID`, `matchedRuleIDs`), một type ít hơn ở top level.
* `BookImportFormat` (`enum: String, CaseIterable`, 4 case `txt`/`html`/`epub`/`mobi`): `displayName`, `static detect(fileName:data:)` (đuôi file trước, magic bytes sau), `static pickerContentTypes: [UTType]` (`compactMap` nên UTI động thiếu thì bỏ, không crash).
* `BookImportService` (`enum` namespace, không case) là **điểm vào duy nhất** của phân hệ; 4 type lồng để giữ đúng 1 type top level mỗi file: `StructureMode` (`String, CaseIterable, Identifiable`: `auto`/`tocIndex`/`spine`/`tocRules` + `displayName`), `Request`, `Result`, `ImportError` (`LocalizedError`: `drmProtected`, `unsupportedCompression`, `emptyContent`, `malformed(String)` — `errorDescription` tiếng Việt để View đổ thẳng vào Toast). Thành viên: `static parse(_:) async throws -> Result`.
* Namespace thuần (`enum`, không case, không state): `TxtBookParser` (`parse(content:fileName:rules:)`, `bookTitle(fromFileName:)`), `HtmlBookParser.parse(html:fileName:rules:structure:)`, `MobiBookParser.parse(data:fileName:rules:structure:encodingOverride:) throws`, `PalmDocDecompressor` (`decompress(_:)`, `stripTrailingEntries(record:flags:)`), `XhtmlTextExtractor` (type lồng `Section { title, text }`; `plainText(html:)`, `inlineText(html:)`, `headingSections(html:) -> [Section]?`, `firstHeading(html:)`, `firstTagText(html:tags:)`, `firstImageSrc(html:)`, `dropLeadingTitle(_:title:)`, `anchorSegments(html:anchorIds:) -> [String: String]`, `declaredCharsetName(in:)`).
* `EpubArchiveReader.read(fileUrl:) throws -> Package`; `Package { rootDirectory, opfURL, opfDirectory }` mang **method** `resolve(href:base:) -> URL?` — trả `nil` khi file không tồn tại **hoặc** đường dẫn thoát ra ngoài `rootDirectory` (chặn zip-slip), `base` mặc định là thư mục OPF vì href trong NCX/nav phải giải theo thư mục của chính file mục lục.
* `EpubOpfParser.parse(opfURL:) throws -> Manifest` (2 type lồng: `Item { href, mediaType, properties }`, `Manifest`); `EpubNavParser` có `parseNcx(data:) -> [Entry]` + `parseNav(html:) -> [Entry]` (type lồng `Entry { title, href, fragment, depth }`); `MobiArchiveReader.read(data:) throws -> Package` (type lồng `Package { textData, charsetName, title, author, desc, coverData, … }`, `private typealias Failure = BookImportService.ImportError` để `throw` trực tiếp lỗi của tầng service); `EpubBookParser.parse(fileUrl:fileName:rules:structure:) throws -> ParsedBook`.
* `TextEncodingDecoder` thêm hai thành viên `static`: `option(forCharsetName:) -> TextEncodingOption?` (ánh xạ tên IANA) và `decodeDeclared(_:charsetName:) -> String?` (trả `nil` để caller rơi về auto-detect). `decode(_:)`/`detect(_:)` giữ nguyên chữ ký. **Không** thêm case cho `TextEncodingOption` — thêm case là đổi thứ tự ưu tiên auto-detect của TXT.
* `BookImportConfirmationSheet` thay `TXTImportConfirmationSheet`: thêm `let format: BookImportFormat`, `@State var selectedStructure: BookImportService.StructureMode`, case `structure` trong `PickerType`; `onReanalyze` đổi chữ ký thành `(String?, Set<String>, BookImportService.StructureMode) async -> BookImportService.Result?`. Các `@State` phải `internal` vì `private` của Swift là phạm vi **file** mà 3 picker nằm ở `+Pickers.swift`.
* `ShelfView` đổi tên thành viên: `importTxtBook(from:)` → `importLocalBook(from:)`, `reanalyzeTxt(...)` → `reanalyzeImport(decodeID:ruleIDs:structure:tempFileUrl:fileName:)`, `@State isParsingTXT` → `isParsingImport`; `parseTxtBook` bị xoá (dời sang `TxtBookParser`). `PendingImport` thêm `let format: BookImportFormat`.
* Không `@Model` nào đổi shape ⇒ không có rủi ro lightweight migration. `Book.isLocalBook` chỉ dựa `extensionPackageId`/`detailUrl`/`sourceName` nên việc `performImport` nay ghi `author`/`desc` thật từ file **không** làm sách mất tính "local".

## Đổi shape command khôi phục + API tô màu trình soạn script (1.3.247)

* `AddBookToShelfCommand` **đổi shape** (lần đầu): thêm `public let lastReadDate: Date?` cuối danh sách thuộc tính, tham số init `lastReadDate: Date? = nil` — mặc định `nil` nên **mọi call site cũ biên dịch không đổi**. Ngữ nghĩa: `nil` = lấy `Date()` như trước (thêm sách thủ công), có giá trị = giữ đúng mốc đọc của máy nguồn khi khôi phục. Điểm đọc duy nhất là `BookTransactionCoordinator.addBookToShelf` (`command.lastReadDate ?? Date()` ở cả hai nhánh); điểm ghi duy nhất là `BackupLibraryWriter.insertMissingBooks`. Không `@Model` nào đổi shape ⇒ không rủi ro lightweight migration. Điều này **thay thế** câu "`AddBookToShelfCommand` không đổi shape" ở mục 1.3.246 dưới đây.
* `BackupCoordinator` thêm hai thành viên: `restoreEverythingFromDrive(_:container:) async` (public) và `performRestore(prepared:container:options:) async` (private — thân dùng chung, **không** tự giữ `isBusy`). `runRestore(container:options:)` giữ nguyên chữ ký, nay chỉ là lớp bọc giữ khoá quanh `performRestore`.
* `RepositoryFilterPolicy.sortExtensions(_:)` giữ nguyên chữ ký, thêm khoá so sánh đầu tiên `hasUpdate`. `Extension.hasUpdate` không đổi.
* `CodeEditorTextView` thêm state riêng tư `keyboardScreenFrame: CGRect?` + `keyboardObservers: [NSObjectProtocol]`, `deinit` gỡ observer, override `layoutSubviews()`, và ba hàm riêng tư `observeKeyboard()` / `applyKeyboardInset()` / `setKeyboardInset(_:)`. `gutterWidth`, `updateGutterInset()`, `draw(_:)` không đổi.
* `HighlightingCodeEditor.Coordinator` thêm `applyHighlight(to:fontSize:)` (public — tô tại chỗ trên `textStorage`), `tokenColors(in:) -> [(NSRange, UIColor)]` (internal) và `intersectsProtected(_:_:)` (private, tìm nhị phân). `highlight(_:fontSize:) -> NSAttributedString` giữ nguyên chữ ký (dùng cho `makeUIView`/`updateUIView`) nhưng nay dựng màu từ `tokenColors`. `regexCache` đổi **tập khoá**: hai khoá `comment` + `string` gộp thành một khoá `protected`.
* `ExtensionScriptEditorView` không đổi thuộc tính hay chữ ký nào — chỉ chuyển khai báo sang hai file `extension` mới; `dismissKeyboard()` là thành viên `internal` mới duy nhất. `ScriptFileInfo` không đổi.
* Không type nào bị xoá, đổi tên, đổi kế thừa hay đổi conformance trong lần này.

## Type mới cho sao lưu/khôi phục, đồng bộ ext theo lô, sửa thông tin truyện (1.3.246)

* `EditBookInfoCommand` (`struct`, bất biến): `bookId`, `title`, `author`, `coverUrl`. Command DTO duy nhất được thêm; `AddBookToShelfCommand` và `UpsertExtensionCommand` **không đổi shape**.
* `BookTransactionCoordinator` thêm `updateBookInfo(command:in:) -> Result<Void, Error>` (`@discardableResult`), tính lại `titleTrans = TranslateUtils.translateMeta(...)` và `authorTrans = TranslateUtils.translateAuthorHanViet(...)` — xem [BookTransactionCoordinator.swift:89](../../Sources/Services/Books/BookTransactionCoordinator.swift#L89). `updateBookMetadata` cũ giữ nguyên hành vi (không đụng hai field dịch), nên hai API cố ý cùng tồn tại.
* `ExtensionTransactionCoordinator` thêm `upsertExtensions(commands:in:)` (một `save()` cho cả lô) và private `apply(command:in:)` dùng chung với `upsertExtension` — xem [ExtensionTransactionCoordinator.swift:47](../../Sources/Services/Extensions/ExtensionTransactionCoordinator.swift#L47). Chữ ký `upsertExtension(command:in:)` không đổi.
* `ExtensionSyncCommandBuilder` (`enum` namespace, không case): type lồng `Input { item: ExtensionRegistryItem, existingLocalPath: String }`, `static let defaultConcurrency = 6`, `requestTimeout: TimeInterval = 10`, `packageId(forName:)`, `build(inputs:repositoryUrl:maxConcurrent:) async -> [UpsertExtensionCommand]` (giữ đúng thứ tự input).
* `ImageCacheManager` thêm `saveCover(data:for:maxDimension:quality:) -> UIImage?` (`@discardableResult`) và private `downscaled(_:maxDimension:)`; dùng lại `validatePathSafety`/`getNewFileName` private sẵn có, không thêm root lưu trữ mới.
* Phân hệ backup — mỗi type một file, `Sources/Services/Backup/`:
  - Giá trị/DTO: `BackupScope` (`enum: String, CaseIterable`, 6 case, `isMandatory`, `defaultSelection`, `displayOrder`), `BackupManifest` (`Codable`, type lồng `Counts`, `currentSchemaVersion = 1`, `isSupported`), `BackupPayload` (`enum` namespace chứa `BookRecord`/`RepositoryRecord`/`ExtensionRecord`/`ChapterRecord`/`SlugRecord`), `BackupProgress` (`struct` + `enum Phase` 17 case, `idle`), `GoogleDriveFile` (`Codable`), `LocalBackupStore.Item`.
  - Namespace thuần: `BackupPaths` (tên entry archive + `backupsDirectory`), `BackupZipArchive`, `BackupSizeEstimator`, `BackupDictionaryArchiver`, `GoogleDriveConfiguration`.
  - Actor: `BackupExportWorker`, `BackupRestoreWorker` (type lồng `Prepared`/`Options`/`Outcome`/`Failure`), `GoogleDriveClient`, `GoogleDriveUploader`.
  - `@MainActor`: `BackupCoordinator` (`ObservableObject`, singleton `.shared`), `BackupLibraryReader` (chỉ đọc, type lồng `Payload`), `BackupLibraryWriter` (`struct`), `GoogleDriveAuthService` (type lồng `PresentationProvider`, `Failure`).
  - Còn lại: `BackupChapterRestorer`, `BackupExtensionInstaller`, `BackupDictionaryRestorer`, `GoogleDriveTokenStore`, `LocalBackupStore`.
* View mới đều là `struct: View` một type/file: `BookInfoEditView`, `BackupHubView`, `BackupScopeToggleList`, `LocalBackupListView`, `GoogleDriveBackupListView`, `RestoreOptionsSheet`, `BackupSettingsSection`, `TTSSettingsSection`. `TTSSettingsSection` là phép trích **nguyên văn** mục TTS khỏi `SettingsView` — không type nào của màn TTS đổi.
* Không type nào bị xoá, đổi tên, đổi kế thừa hay đổi conformance trong lần này. Không `@Model` nào đổi shape ⇒ không có rủi ro lightweight migration.

## Type mới cho copy từ điển và widget trình duyệt (1.3.244)

* `DictionaryTransferTarget` (`enum`, `Equatable`): `case globalCustom` và `case privateBook(bookId: String)`. Đây là **toàn bộ** vốn từ vựng về đích copy — không có case nào trỏ tới dữ liệu dựng sẵn (`.dat`), nên "ghi vào built-in" không biểu diễn được bằng type.
* `DictionaryEntryTransferAction` (`@MainActor enum` không case, dùng như namespace): `copy(key:value:destinationType:target:) async throws` và `destinationLabel(destinationType:target:) -> String`. Nó không sở hữu storage — chỉ định tuyến sang `DictionaryCache.shared.upsertEntry(key:value:type:)` (đích `globalCustom`) hoặc `TranslationManager.shared.saveCustomEntry(word:meaning:isName:bookId:)` (đích `privateBook`). Cả hai API đã tồn tại trước 1.3.244; không API nào của chúng đổi shape.
* `DictionaryEntryRow` (`struct: View`): hàng từ điển tách khỏi `DictionaryListView`, nhận `entry`, `type`, `isGlobalScope`, `contextBookId`, `onEdit`, `onDelete`, `onTransfer(DictType, DictionaryTransferTarget)`, `onMissingContext`.
* `DictionaryListView` thêm **một** thuộc tính: `var contextBookId: String? = nil` (mặc định `nil` ⇒ mọi call site cũ vẫn biên dịch). `bookId` giữ đúng nghĩa cũ (scope của danh sách); `contextBookId` chỉ là ngữ cảnh "sách nào đang mở màn Từ điển".
* `BookSearchBarView` (`struct: View`): `@Binding text`, `placeholder`, `onCommit` — trích nguyên `searchBarView` của `ShelfSearchView`, không đổi visual hay hành vi.
* `FloatingWidgetGeometry` (`enum` namespace, `import UIKit`): `clampedCenterY(_:widgetHeight:screenHeight:topMargin:bottomMargin:)`, `nearestEdge(centerX:screenWidth:)`, `restingCenterX(edge:widgetWidth:screenWidth:horizontalMargin:)`. Ba hàm thuần, không state.
* `VisibleBrowserPulseMonitor` (`@MainActor final class: ObservableObject`, singleton `.shared`): `static let pulseThreshold: TimeInterval = 10`, `@Published private(set) var isPulsing`, `func evaluate()`.
* `BrowserFloatingWidgetUIWindow: UIWindow`, `BrowserFloatingWidgetContainerViewController: UIViewController, UIGestureRecognizerDelegate` (type lồng `Layout`), `BrowserFloatingWidgetWindowManager` (`@MainActor final class: ObservableObject`, singleton) — bộ ba đối xứng với `FloatingWidgetUIWindow` / `FloatingWidgetContainerViewController` / `TTSFloatingWidgetWindowManager` của TTS widget, nhưng là **type riêng**, không kế thừa hay chia sẻ base class.
* `VisibleBrowserReopenViewModel` giữ tên và hai khoá `UserDefaults` cũ, đổi API sang mô hình UIKit: `handleDragStart()`, `handleDragEnd(finalPosition:widgetHeight:screenWidth:screenHeight:topMargin:bottomMargin:)`. `VisibleBrowserReopenButton` thu về `let tabCount: Int` — không còn cử chỉ, không còn đo kích thước.
* `VisibleBrowserTabItem` thêm `public let createdAt: Date` (mặc định `Date()` trong init) — nguồn tuổi tab duy nhất. `VisibleBrowserSettings` (`enum` namespace, chỉ `Foundation`): `openMinimizedKey`, `opensMinimized`. `VisibleBrowserTabManager` thêm `internal func prepareContainerMinimized()`.
* `EdgeDirection`, `DictType`, `DictEntry` **không đổi** — cả ba được tái dùng nguyên.

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
