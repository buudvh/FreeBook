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
## Sáu file mới, không xoá file nào; danh sách violation không đổi (1.3.338)

* **6 file mới, tất cả dưới trần 400 và đúng 1 type top level**: `QuickTranslationRulePriorityConfiguration` **203**, `QuickTranslationBookEngineConfigStore` **240**, `QuickTranslationRulePriorityListView` **126**, `ReaderBookTokenSettingsView` **121**, `ReaderBookRulePriorityView` **57**, `QuickTranslationRulePrioritySettingsView` **33**. Hai file Service có nhiều type **lồng** (`Key`/`Preset`/`Configuration`; `TokenOverride`/`Overrides`/`Outcome`) — `MULTI_PRIMARY_TYPES` chỉ tính type ở top level nên không cần ngoại lệ nào.
* **File đã có, đều tăng dưới trần**: `QuickTranslationRuleEngine` 293 → **347** (+54: `metric(for:)`, `select(from:priority:)`, phân giải cấu hình ở `rewrite`/`preview`), `ReaderSettingsView` 182 → **257** (+75: 2 hàng + 2 sheet + helper), `QuickTranslationRuleTokenSettings` 68 → **93** (+25: `label`, `isNumeralGroup`), `QuickTranslationRuleDiagnostics` 219 → **223**, `QuickTranslationRulesView` 322 → **326**.
* **`ReaderView.swift` giữ đúng 1997 dòng** (baseline 2053): tham số `bookId` được ghép vào dòng gọi có sẵn thay vì thêm dòng mới, nên file trong baseline không nhích lên.
* **`check_architecture.py` giữ đúng 7 violation cũ**, tập y hệt trước lượt sửa, không phát sinh mới và không nới baseline nào.
* **Nơi độ phức tạp thật sự tăng là comparator, không phải số dòng.** `select` đổi từ 5 phép `if` cố định sang một vòng theo `priority.order`; đây là điểm nóng chạy O(n log n) lần cho **mỗi dòng văn**, nên cấu hình phải là bản chụp truyền vào (`Configuration`), không được đọc `UserDefaults`/file trong comparator. Số tổ hợp hành vi mới là 4! × 2⁴ = **384**, mỗi tổ hợp vẫn là strict weak ordering hợp lệ vì cả bốn khoá là khoá tổng so theo cặp độc lập ngữ cảnh.

## Bốn file mới, không xoá file nào; một file nữa rời danh sách violation (1.3.336)

* Tổng file Swift 483 → **487** (+4, −0). Cả bốn dưới trần 400 và đúng 1 type top level (ba file là `extension`, không tính là type) ⇒ **không** thêm entry `architecture_allowlist.json`: `AddWordSheet` 202, `ShelfSearchView+Actions` 118, `TranslationPunctuationMapper` 98, `CollectionDetailView+Manage` 68.
* **`check_architecture.py` 8 → 7 violation.** `TTSDictionaryEditView.swift` 702 → **559** (baseline 641) rời danh sách nhờ dời `AddWordSheet` ra file riêng. Bảy chỗ còn lại đều là nợ dòng cũ, không phát sinh mới.
* **Hai file giảm nhưng vẫn trong danh sách**: `TranslateUtils.swift` 1023 → **968** (baseline 917) sau khi bảng dấu câu rời đi. Không nới baseline nào.
* **Hai file chạm trần rồi lùi lại**: `ShelfSearchView.swift` gộp cả khối hành động là **396**/400 — đã tách để về **292**; `CollectionDetailView.swift` gộp cả khối quản lý bộ là **405**/400 (**vi phạm thật**, đã bắt được trước khi commit) — đã tách để về **354**. Đây là hai lần tách vì trần dòng, không vì thiết kế.
* **Độ phức tạp có nghĩa lại đúng một chỗ**: `AddWordSheet.body` mất computed property `suggestions` (nó gọi espeak đồng bộ mỗi lượt vẽ) và chỉ còn đọc `@State` — chi phí mỗi lượt vẽ đi từ "một lượt phiên âm espeak dưới `NSLock` dùng chung" xuống một phép đọc mảng.
* `QuickTranslationRuleEditorSheet.swift` 345 → **370**, `+Editing.swift` 96 → **126**, `QuickTranslationRulePatternField.swift` 149 → **156** — đều còn xa trần 400.

## Tám file mới, hai file xoá; ba file rời danh sách violation (1.3.334)

* Tổng file Swift 477 → **483** (+8, −2). Tám file mới đều dưới trần 400 và đúng 1 type top level (sáu file là `extension`, không tính là type) ⇒ **không** thêm entry `architecture_allowlist.json`: `ReaderChapterListView+List` 179, `ReaderDefinitionOverlayView+Rows` 164, `TTSNextChapterPrefixCache+GoogleBatch` 158, `ReaderDefinitionOverlayView+Rules` 156, `TTSNextChapterPrefixSynthesizer` 113, `ReaderView+DefinitionPanel` 107, `ReaderChapterListView+Download` 74, `ReaderRuleAction` 13.
* **Xoá 470 dòng View**: `ReaderRuleTraceOverlayView` 396 + `ReaderRuleTraceGuideSheet` 74. Đây là xoá *thật* — chức năng chẩn đoán rule không bị copy sang chỗ khác nguyên khối, nó gộp vào panel Dịch dưới dạng 2 hàng + 1 popup (`+Rules` 156 dòng), còn màn hướng dẫn thì bỏ hẳn.
* **Ba file rời danh sách violation của `check_architecture.py` (12 → 8)**:
  * `ReaderChapterListView.swift` 468 → **295** (baseline 408) — dời thân `List` sang `+List`.
  * `ReaderDefinitionOverlayView.swift` 489 → **372** (baseline 468) — dời ba hàng dưới sang `+Rows` *trước* khi thêm hai hàng rule, nên thêm chức năng mà file vẫn giảm 117 dòng.
  * `ReaderView.swift` 2052 → **1969** (baseline 2053) — không còn violation dòng, nhưng vẫn nằm trong allowlist vì `MULTI_PRIMARY_TYPES`.
* **Cảnh báo headroom ngược**: hai baseline 408 và 468 **không** được siết lại theo mức mới (295/372), nên hiện có ~200 dòng slack mà một lượt sửa sau có thể ăn hết mà gate vẫn xanh. Ai muốn khoá lại thì giảm `baseline_value`, đó là thao tác hợp luật (baseline chỉ được giảm).
* **Chỗ chật nhất repo vẫn là `BookDetailView.swift` 1197 → 1199 / baseline 1201: còn đúng 2 dòng.** Lượt này chỉ thêm 2 dòng (gọi coordinator + log lỗi). Lần sửa sau ở file đó **phải** tách file trước.
* `ShelfView.swift` 772 → **840** (baseline 942, còn 102 dòng): hai `Section` + `shelfBookRow`/`shelfSectionHeader`/`unpinnedShelfRows` — phần tăng chủ yếu là hàng và tiêu đề nhóm được rút thành hàm dùng chung cho cả hai nhóm.
* `CollectionDetailView.swift` 268 → **324** và `BookActionSheet.swift` 270 → **307** — cả hai **không có baseline**, trần cứng 400, còn lần lượt 76 và 93 dòng.
* **Bậc phức tạp của nạp trước tiền tố chương sau (Google)**: từ **m** request HTTP (m = số chunk tiền tố còn thiếu, mỗi cái một job coordinator tuần tự) xuống **1** request. Cùng bản chất với 1.3.332 nhưng ở đường khác: 1.3.332 gộp *cửa sổ trong chương*, lượt này gộp *tiền tố chương sau*.
* **Tải lẻ một chương**: đường mới bỏ hẳn phần dịch cả chương + dựng `[ParagraphItem]` (chi phí O(số dòng) cộng tra từ điển mỗi dòng) khỏi thao tác "tải xuống", chỉ còn bóc tách + ghi nền. Đổi lại một `Set<Int>` trạng thái trong View và một lượt `ChapterStore.fetchChapter` mỗi hàng để lấy host đúng.

## Ba file mới; `TTSManager` giảm 14 dòng nhờ dời điều phối nạp trước (1.3.332)

* Tổng file Swift 474 → **477**. File mới đều dưới trần 400 và đúng 1 type top level ⇒ **không** thêm entry allowlist: `TTSManager+RemoteBatchPrefetch` 205 (extension, không tính là type), `TTSBatchAudioPayload` 67, `ShelfTab` 38.
* **`TTSManager.swift` 4015 → 4001** (baseline 3470, vẫn violation): `updatePrefetchWindow` từ 26 dòng còn 12 nhờ dời hai khối (dọn task ngoài cửa sổ, xếp hàng nạp trước) sang file `+RemoteBatchPrefetch`. Đây là giảm thật, không phải dời dấu ngoặc.
* `GoogleTTSService.swift` 210 → **260**: thêm `synthesizeBatch` + tách `makeRequest`/`audioParts`/`withRetry`. Phần tăng chủ yếu là hàm mới; `withRetry` **gộp** hai bản retry sẽ phải có nếu viết retry riêng cho đường gộp.
* `ReaderRuleTraceOverlayView.swift` 388 → **396** — file này **không có baseline**, trần cứng là 400 nên chỉ còn **4 dòng**. Lần sửa sau ở đây phải tách file, không thêm được nữa. *(1.3.334: file đã bị xoá, ràng buộc này hết hiệu lực.)*
* `ShelfView.swift` 780 → **772**: `navigationTitleText` (8 dòng) chuyển thành `ShelfTab.navigationTitle`, `Picker` dựng từ `allCases` thay vì 4 dòng `Text().tag()`.
* **Bậc phức tạp của một lượt nạp trước cửa sổ**: từ **k** request HTTP tuần tự (mỗi cái ~370 ms, cộng `offset × delayStep` giữa các lượt) xuống **1** request (~735 ms cho k = 10). Chi phí gần như không phụ thuộc k trong dải 1–20 vì nó là một round trip.
* `pruneRemotePrefetchTasks` thêm một `Set<Task>` mỗi lượt gọi (≤ 10 phần tử) để so định danh task — đổi lại là bỏ được lớp lỗi "huỷ mất lượt gộp còn dùng được".

## Ba file mới nhỏ, một file giảm 165 dòng, một baseline được trả (1.3.330)

* Tổng file Swift 471 → **474**. File mới đều nhỏ và đúng 1 type top level ⇒ **không** thêm entry `architecture_allowlist.json`: `ExtTTSScriptCache` 128, `ExtensionIconImageCache` 45, `RepositoryRefreshPolicy` 42.
* **`ExtTTSService.swift` 230 → 65** — xoá đường PCM không caller. Đây là giảm *thật*, không phải dời chỗ: `synthesize(...targetFormat:)` (102 dòng), `preprocessBufferForExtTTS` (45), bộ theo dõi file tạm (18) đều biến mất, không có file nào nhận lại.
* **`ExtensionManager.swift` 1049 → 1015 (baseline 1022) ⇒ rời danh sách violation.** `getTTSRuntimeFingerprint` từ 36 dòng còn 3; phần băm SHA256 dời sang `ExtTTSScriptCache`. `check_architecture.py` **13 → 12**.
* `TTSManager.swift` 4022 → **4015** (vẫn trên baseline 3470): xoá hàm rỗng `cleanUpTempFile()` + 3 call site. `TTSManager+PrefetchCache.swift` 47 → **43**.
* `RepositoryManagerView.swift` 728 → **734** (baseline 751, còn 17 dòng): thêm tham số `force:`, `filterStatusBar(count:)`, và một `let` gom kết quả lọc.
* **Bậc phức tạp giảm ở hai chỗ đo được**:
  * Ext TTS mỗi đoạn: từ *2 lần đọc file kích thước script + 4 lần parse JSON + 1 lần so chuỗi O(len(script))* xuống *2 lần `stat()` + so 3 giá trị vô hướng*. Chi phí giờ **không phụ thuộc kích thước `tts.js`** nữa.
  * Tab Tiện Ích mỗi lượt vẽ: `filterExtensions` + `sortExtensions` từ **3 lần** xuống **1 lần**. `sorted` dùng `localizedCompare` là so sánh chuỗi đắt nhất trong Foundation, nên đây là hệ số 3 trên phần đắt nhất của lượt vẽ.
* `ExtensionIconImageCache` giữ tối đa 128 entry và **xoá sạch** khi vượt (không LRU): danh sách tiện ích/kệ sách chỉ có vài chục icon nên một lần dọn hiếm khi xảy ra, và code dọn LRU thật sẽ dài hơn phần nó tiết kiệm.

## Mười một file mới, hai file xoá, hai baseline được trả nợ (1.3.328)

* Tổng file Swift 462 → **471**. File mới, tất cả **≤ 400** dòng và đúng 1 type top level ⇒ **không** thêm entry `architecture_allowlist.json`: `BookCollection` 38, `BookCollectionCoordinator` 151, `BookSheetAction` 43, `BookActionRunner` 188, `BookActionSheet` 264, `ShelfBookRowView` 30, `NewChapterBadgeView` 28, `CollectionsTabView` 203, `CollectionDetailView` 268, `CollectionPickerSheet` 126, `BookDetailView+ShelfPlacement` 33.
* **Hai file trả nợ baseline**:
  * `ShelfView.swift` 910 → **780** (baseline 942). Nguồn giảm: hai khối `.contextMenu` 121 dòng bị thay bằng 2 cử chỉ + 1 sheet, và 5 hàm hành động chuyển sang `BookActionRunner`. Khoảng trống dưới baseline nới từ 32 lên **162** dòng.
  * `BookDetailView.swift` 1207 → **1197** (baseline 1201). Đây là lần đầu file này **về dưới** baseline: `addToShelf` 21 dòng dời sang `BookDetailView+ShelfPlacement.swift`, đổi lại chỉ thêm 3 dòng cho `@State` + `.sheet`.
* `ShelfView+NewChapters.swift` 127 → **57** — không mất chức năng nào, ba thân hàm (`newChapterTarget`, `checkNewChapters`, `showNewChapterSummary`) dời sang `BookActionRunner` để màn Bộ sưu tập dùng cùng một bản.
* Hai file xoá: `TTSTransliterationTesterView.swift` (277) và `TransliterationGoldenSet.swift` (128). `EspeakPhonemizer.swift` 193 → **173**, `VietnameseTokenGate.swift` 110 → **95**.
* **Không đổi bậc phức tạp ở đâu.** `shelfBooks`/`CollectionDetailView.books` là hai lượt `filter` trên mảng đã sort (ghim-trước bằng cách nối hai mảng — `sorted(by:)` của Swift không ổn định nên so sánh hai khoá trong một lượt sẽ trộn thứ tự trong cùng nhóm). `BookCollectionCoordinator` fetch toàn bộ `BookCollection` rồi lọc trên RAM: đây là **bắt buộc**, predicate lọc chuỗi của SwiftData iOS 17 dịch sai sang SQLite; số bộ sưu tập là con số người dùng tự tạo, cỡ hàng chục.
* `JapaneseTransliterator.swift` 341 → **347** (baseline 411): 15 giá trị trong bảng đổi tại chỗ, phần tăng là comment giải thích vì sao chọn `u`.
* `check_architecture.py` **14 → 13 violation** — tập cũ trừ `BookDetailView` (LINE_LIMIT_EXCEEDED). Không violation mới nào.

## Một file mới, năm file sửa, không file nào tới trần (1.3.325)

* [`ExtensionDraftMetadata.swift`](../../Sources/Services/Extensions/Debug/Staging/ExtensionDraftMetadata.swift) **136** dòng, đúng 1 type top level ⇒ không thêm/nới entry `architecture_allowlist.json`. Tổng file Swift 461 → **462**.
* File sửa, tất cả **≤ 400**: `ExtensionDebugCommandRouter+Draft.swift` 204 → **297**, `ExtensionDebugCommandRouter.swift` 262 → **308**, `ExtensionDraftInstaller.swift` 147 → **201**, `ExtensionDebugInstallGate.swift` 113 → **134**, `ExtensionDebugServerView.swift` 130 → **151**.
* **Phần tăng của `+Draft.swift` gần một nửa là do *tách* hàm, không phải thêm nhánh**: `handleDraftInstall` cũ 48 dòng nay chia thành `handleDraftInstall` (33) + `installOverExisting` (34) + `installAsNew` (44) + `writeLibraryRow` (17). Đổi lại, mỗi hàm chỉ còn một quyết định và cửa gate xuất hiện đúng một lần mỗi nhánh.
* `check_architecture.py` giữ đúng **14 violation**, cùng một tập như trước lượt này.

## Do phuc tap sau bon luot toi uu (1.3.320)

* **`TextPreprocessor.swift` giu dung 1121 dong** = baseline, du them 4 helper moi (`unitAlternation`, `makeUnitGroup`, `unitExpansion`, `containsSpelledNumber`, `needsWhitespaceNormalization`). Bu bang cach xoa 51 spec regex thu cong va 17 dong log da comment-out.
* **`TTSManager.swift` 4023 → 4022**: hai khoi tinh `blockedIndices` trung nhau duoc gop thanh mot ham `nghiSkippedRefillIndices()`, du du them `nghiRefillCandidate` va vong bo qua doan rong.
* **`TTSReplacementManager.swift` 281 → 392** — file nay chi co exemption `MULTI_PRIMARY_TYPES`, khong co `FILE_SIZE_LIMIT`, nen tran la 400: con **8 dong du**. Them che do thay the moi thi phai tach file truoc.
* **`PiperSynthesisCoordinator.swift` 249 → 339** va **`PiperTTSService.swift` 301 → 356**, ca hai duoi tran 400.
* Cho phuc tap that tang len la `PiperSynthesisCoordinator`: gio co ba duong huy (het waiter, huy reserve, `cancelAll`) va moi duong phai resume continuation **dung mot lan**. Bat bien duoc giu bang cach so `activeRequest.id == reqID` trong vong xu ly.

## Do phuc tap sau khi dong bo goi y phien am (1.3.317)

* **Xoa 3 file (561 dong), them 2 file (154 dong)**: 461 → **460** file Swift. Rong ra 407 dong.
* **`TTSDictionaryEditView.swift` giam 705 → 702** du them badge va accessibility label: khoi dung goi y 24 dong bi thay bang **mot** loi goi `TTSPhoneticSuggestionBuilder`, va mau badge dat trong model chu khong trong View. File nay dang tren baseline 641 tu truoc nen moi dong tiet kiem duoc deu co gia.
* **`TTSPhoneticSuggestionBuilder` co dung mot nhanh quyet dinh**, khong co vong lap nao: gap khoa → tra tu dien → cong `ForeignScriptClassifier` → hai loi goi transliterator. Do phuc tap nam o *thu tu*, khong o cau truc.
* **`TTSParagraphBuilder.buildFromEntries` them mot `.filter`** — mot dong, khong doi do phuc tap cua phan cat chunk.

## Do phuc tap sau nam loi doc/dich/TTS (1.3.313)

* **Them 2 file Swift** (459 -> **461**): `VietnameseOrdinalSpeller` **46** dong (1 regex, 1 ham), `ExtensionInstallAudit` **80** dong (2 struct long, 2 ham tinh, khong nhanh nao sau 2 muc).
* **Khong file nao vuot baseline moi.** `TextPreprocessor.swift` giu **dung** 1 121 dong (bang baseline) bang cach bo mot dong log da comment de doi lay stage moi; `TranslateUtils.swift` giu **dung** 1 023 dong nhu truoc luot sua.
* **Cho phuc tap tang la `QuickTranslationNumberFormatter.renderNumeral`**: gio co 5 nhanh (digit ASCII / khoang hai chu so / danh sach ba chu so / doc tung chu so / doc thanh mot so). Ba nhanh giua deu la port truc tiep tien de "chu so Han tran lien nhau khong phai so ghep", nen giu chung canh nhau de doi chieu duoc.

## Do phuc tap sau luot giu vi tri cuon (1.3.307)

* File moi nho: [`DiscoveryScrollAnchorStore.swift`](../../Sources/Views/Discovery/DiscoveryScrollAnchorStore.swift) **59** dong, 5 ham, khong nhanh nao sau 2 muc.
* [`DiscoveryView.swift`](../../Sources/Views/Discovery/DiscoveryView.swift) 940 -> **984**: them mot `ScrollViewReader` boc `List`, hai modifier tren hang, va hai ham `captureAnchor`/`applyPendingRestore` (moi ham <= 13 dong, khong nhanh long nhau qua 2 muc).
* [`QuickTranslationRuleTokenLengthBar.swift`](../../Sources/Views/Settings/Translation/QuickTranslationRuleTokenLengthBar.swift) 132 -> **145**: `stepper` (VStack) bi thay bang `lengthRow` (HStack + `Slider`), hai lan goi thay vi hai lan goi — cung so nhanh, khong tang do sau.
* **Do phuc tap thuat toan cua duong moi**: ghi `setVisible` la O(1) moi hang; tim hang tren cung la O(n) nhung **mot lan moi luot doi tab**, khong phai moi hang cuon. Day la ly do neo duoc chot o `onDisappear` chu khong tinh lai lien tuc.

## So dong sau luot 1.3.303

* **Them 18 file Swift** (441 -> **459**), tat ca <= 400 dong va moi file mot primary type top-level. Lon nhat: `ExtensionDebugCommandRouter` 278, `ExtensionDebugServer` 248, `ExtensionDebugServerView` 191.
* **Router phai tach hai file** (`+Draft` 183 dong) de khong cham tran 400 - cung mau `X+Feature.swift` ma repo dang dung cho god-object.
* **Ba file sua nho**: `DeveloperSettingsSection` 17 -> 20, `MainTabView` 118 -> 126, `project.yml` +4 dong. Khong file nao o baseline bi phinh.
* **Chi phi thuong truc khi khong bat server**: hai actor rong (`ExtensionDebugServer.shared`, `ExtensionDraftStagingStore.shared`) cong mot lan `removeItem` best-effort luc khoi dong. Khong listener, khong socket, khong timer.
* **Bac phuc tap**: `handle` la mot `switch` O(1); `installedExtensions()` la mot fetch SwiftData + doc `plugin.json` moi extension (chi chay theo lenh, khong theo moi event); `changeSummary` la O(n) file voi mot luot SHA-256 moi file - chay dung mot lan truoc khi xin xac nhan.
* **Package VS Code khong tinh vao so dong Swift** va khong co buoc build trong CI: `src/extension.ts` ~330 dong, `client.ts` ~150, `draft.ts` ~130, `protocol.ts` ~150.
* `check_architecture.py` giu **14 violation nen**, khong violation moi.

## Số dòng sau lượt 1.3.302

* **Thêm 13 file Swift** (428 → **441**), tất cả ≤ 400 dòng và mỗi file một primary type top-level. Lớn nhất: `ExtensionDebugConsoleView` 217, `ExtensionDebugRunner` 206; nhỏ nhất `DeveloperSettingsSection` 17.
* **Hai file ở/sát baseline được giữ bằng tách file, không nới baseline**: `JSExecutor.swift` 1516 → **1553** (chỉ một stored property, một tham số init và 6 lời gọi một dòng; thân các điểm phát ở `JSExecutor+Debug.swift` 77 dòng) — vẫn là violation cũ, không loại mới. `SettingsView.swift` 447 → **450**, còn dưới baseline 453 nhờ đưa mục mới sang `DeveloperSettingsSection.swift`.
* **`ExtensionManager.swift` giữ đúng 1049 dòng** — runner dùng lại API `internal` của nó nên không thêm dòng nào.
* **Chi phí thường trực khi không debug**: mỗi điểm phát là một phép so `nil` (`guard let sink = debugSink else { return }`) trước mọi format chuỗi ⇒ đường đọc/tải production không cấp phát thêm.
* **Bậc phức tạp của trace**: `emit` O(1) (một `NSLock`, một `Task`); `hub.append` O(1) trừ lúc vượt trần tổng thì O(k) cho k event bị evict; `visibleEvents` của reader là một lượt `filter` O(n) trên tối đa 600 phần tử, chạy theo mỗi lượt body của màn debug — chỉ tồn tại khi màn đó đang mở.
* `check_architecture.py` giữ **14 violation nền**, không violation mới.

## Số dòng sau lượt 1.3.297

* **Thêm 1 file Swift** (426 → **427**): `JapaneseLoanwordList` ~95 dòng, chỉ là dữ liệu `Set<String>`.
* `ForeignScriptClassifier` 189 → 213, `TTSIPAProbeSection` 221 → 323. Cả hai không có baseline nên trần là 400.
* **Bậc phức tạp của phân loại giảm cho ca phổ biến**: một lượt tra `Set` O(1) thay cho cắt greedy + ~60 phép `contains`. Từ lạ vẫn đi qua đường cũ.
* **Phép so bộ ký hiệu** là 24 + 30 lượt gọi espeak, nằm trong `Task.detached`. Chỉ chạy khi người dùng bấm.
* `check_architecture.py` giữ **14 violation nền**.

## Số dòng sau lượt 1.3.296

* **Thêm 3 file Swift** (423 → **426**): `TTSIPAProbeSection` 221, `ONNXPiperEngine+Phonemes` 151, `PiperPhonemeInventory` 87. Tất cả ≤ 400 dòng, mỗi file một primary type top-level.
* **Hai file ở baseline không phình**: `ONNXPiperEngine.swift` giữ **đúng 469** (chỉ đổi hai từ khoá `private` → internal, không thêm dòng); `TTSTransliterationTesterView.swift` 277 → 278 (thêm một dòng gọi section mới, file này không có baseline nên trần là 400).
* **Bậc phức tạp của phép đo**: đếm scalar ngoài từ vựng là một lượt quét tuyến tính trên chuỗi IPA cộng một lượt tra `Set`; 24 lượt gọi espeak nằm trong `Task.detached` nên không chạm main thread.
* **Không đổi đường tổng hợp đang chạy.** `synthesizeRawPhonemes` là đường thứ hai, song song; đường text hiện tại chưa bị sửa dòng nào.

## Số dòng sau lượt 1.3.291

* **Thêm 2 file Swift** (421 → **423**): `TTSDictionaryBulkActionsModifier` 67, `TextPreprocessor+Bulk` 30.
* **Hai file sát/vượt trần không phình**: `TextPreprocessor.swift` giữ **đúng 1121** (chỉ đổi 4 từ khoá truy cập), `TTSDictionaryEditView.swift` **giảm** 706 → 705. `IPAToVietnameseMapper` 176 → 210, `JapaneseTransliterator` 320 → **311**, `EnglishTransliterator` 390 → 393, `EnglishPhonemeTransliterator` 67 → 77, `VietnameseTokenGate` 106 → 110, `TransliterationGoldenSet` 114 → 117.
* **Không đổi bậc phức tạp**: `assemble` trả mảng thay vì chuỗi (cùng một lượt quét), `trailingFiller` là một vòng trên coda (≤ 4 phần tử), cổng ngữ cảnh vẫn ≤ 4 lượt tra láng giềng. *(1.3.305 xoá `trailingFiller`; thay vào đó `reducedRime` là một vòng trên cùng mảng coda, và `endsWithDiphthong` là một lượt quét âm tiết đang dựng — vẫn không đổi bậc. `IPAToVietnameseMapper` 210 → 271, `JapaneseTransliterator` 311 → 341, `TransliterationGoldenSet` 117 → 128, cả ba vẫn dưới trần 400.)*
* **Việc còn lại đã biết, chưa làm trong lượt này**: Phase 0 (đo `phoneme_id_map`), Phase 2 (map âm vị Anh trong inventory của model), Phase 3 (để espeak tự chuyển ngôn ngữ), Phase 4 (kana → IPA trực tiếp).

## Số dòng sau lượt 1.3.290

* **Thêm 6 file Swift** (415 → **421**): `TTSTransliterationTesterView` 277, `ForeignScriptClassifier` 189, `IPAToVietnameseMapper` 182, `TransliterationGoldenSet` 114, `VietnameseTokenGate` 106, `EnglishPhonemeTransliterator` 67. Tất cả ≤ 400 dòng, mỗi file một primary type top-level.
* **Hai file gần trần được xử lý đúng hướng**: `TextPreprocessor.swift` giữ **đúng 1121** dòng (bằng baseline — chỉ 5 sửa tại chỗ), `JapaneseTransliterator.swift` **giảm 411 → 320** nhờ xoá `englishBlacklist` (92 dòng) và `simplifySokuon` đã chết (18 dòng). `EnglishTransliterator.swift` 383 → 390 (còn 10 dòng trước trần 400), `EspeakPhonemizer.swift` 141 → 193, `NghiTTSClient.swift` 175 → 188, `NghiTTSSettingsView.swift` 146 → 150.
* **Độ phức tạp lúc chạy đổi bậc ở đúng một chỗ**: mỗi từ tiếng Anh **mới** giờ tốn một lượt gọi vào libespeak (tra `en_dict` + luật, cỡ chục µs) thay vì ~200 lượt `stringByReplacingMatches` của bộ luật cũ — nhanh hơn chứ không chậm hơn. Và kết quả vẫn được `transliterationCache` giữ nên mỗi từ chỉ trả giá một lần.
* **Bộ phân loại**: một lượt chuẩn hoá + cắt greedy O(n) + ~30 phép `contains` trên chuỗi ngắn, thay cho một lượt tra `Set` 420 mục cộng đúng phép cắt đó. Cùng bậc.
* **Cổng ngữ cảnh** thêm tối đa 4 lượt tra láng giềng mỗi token mơ hồ (cửa sổ ±2), mỗi lượt là một `substring` + tra `Set` — không đáng kể so với chi phí phiên âm nó đang gác cửa.
* **Nợ có chủ ý**: bảng IPA→Việt phủ âm vị phổ thông + 5 ký hiệu riêng của espeak; âm vị ngoài bảng bị bỏ qua (mất một âm, không crash) và bộ ca kiểm là chỗ phát hiện. Ngưỡng `japaneseThreshold = 2` mới chỉ hiệu chỉnh trên ~24 ca, chưa trên dữ liệu thật.
* `check_architecture.py` giữ **14 violation nền**, không violation mới. Host Windows không build được: tính đúng đắn biên dịch do CI/macOS xác nhận, còn chất lượng phiên âm phải nghe trên máy thật.

## Số dòng sau lượt 1.3.289

* **Thêm 2 file Swift** (413 → **415**): `QuickTranslationRulePatternField` 149, `QuickTranslationRuleEditorSheet+Editing` 96. Cả hai ≤ 400 dòng; `Coordinator` là type lồng nên vẫn một primary type top-level mỗi file.
* **`QuickTranslationRuleEditorSheet.swift` giảm 374 → 319 dòng** dù thêm bridge UIKit và placeholder overlay, nhờ dời 6 hàm biên tập mẫu sang file `+Editing`. `QuickTranslationRulePatternStripView` 123 → 121 (chỉ sửa doc).
* **Độ phức tạp lúc chạy**: mỗi lần con trỏ dịch chuyển chạy hai lần quy đổi `String.Index` (O(độ dài mẫu), mẫu < 40 ký tự) và một lượt body của sheet — cùng bậc với việc gõ một ký tự. `sizeThatFits` gọi `UITextView.sizeThatFits` mỗi lượt layout của hàng đó, không phải mỗi keystroke.
* **Hai chốt chống vòng lặp** (`isApplying`, `lastReportedRange`) là điều kiện O(1); không có retry, timer hay task nào.
* **Nợ có chủ ý, giữ nguyên từ 1.3.288**: chip `{i}` vẫn chèn vào **cuối** ô Bản dịch — ô đó không có bridge nên không có con trỏ. Nếu sau này cần con trỏ cho cả hai ô thì dùng lại đúng `QuickTranslationRulePatternField` cho ô Bản dịch.
* `check_architecture.py` giữ **14 violation nền**, không violation mới. Host Windows không build được: tính đúng đắn biên dịch do CI/macOS xác nhận.

## Số dòng sau lượt 1.3.288

* **Thêm 7 file Swift** (406 → **413**), tất cả ≤ 400 dòng và đúng một primary type top-level: `QuickTranslationRuleDraftAnalyzer` 238, `QuickTranslationRuleTokenLengthBar` 132, `QuickTranslationRulePatternStripView` 123, `QuickTranslationRuleTokenPaletteView` 111, `QuickTranslationRuleCaptureChipsView` 82, `QuickTranslationRuleDraftStore` 66, `QuickTranslationRuleDraftIssuesView` 57.
* **File sửa**: `QuickTranslationRuleEditorSheet` 179 → **374** (còn 26 dòng trước trần 400 — phần Kiểm tra đã được tách sang file riêng chính vì lý do này), `ReaderView+RuleTools` 297 → **299**, `QuickTranslationRuleCompiler` 316 → **319**. `ReaderView.swift` **không** thêm dòng nào: nó đang vượt baseline (2076 > 2053) nên chỉ được giảm — đó cũng là ràng buộc quyết định thiết kế (bản nháp phải sống trong store ngoài, vì `@State` không khai được trong extension).
* **Độ phức tạp lúc chạy**: mỗi keystroke ở màn nhập chạy `serialize → parse → compile` trên **một** dòng và `segments(of:)` một lần — tuyến tính theo độ dài mẫu (thực tế < 40 ký tự), không đụng từ điển, không I/O. Không có vòng lặp lồng nào mới; `segments` là một lượt quét con trỏ đơn.
* **Nợ có chủ ý được ghi nhận**: `insertCapture` chèn `{i}` vào **cuối** ô Bản dịch (không có con trỏ cho ô đó); dải chip chỉ dựng cho ô Mẫu. Nếu sau này cần con trỏ cho cả hai ô thì phải bọc `UITextView` — iOS 17 không cấp `TextSelection`.
* `check_architecture.py` giữ **14 violation nền** đã biết, không violation mới. Host Windows không build được: tính đúng đắn biên dịch phải do CI/macOS xác nhận.

## Số dòng sau lượt 1.3.287

* **Không thêm file Swift**: chỉ sửa 7 file engine/view setting. Tất cả giữ ≤ 400 dòng: `QuickTranslationRuleParser` 361, `QuickTranslationRuleCompiler` 316, `QuickTranslationRuleMatcher` 244, `QuickTranslationNumberFormatter` 161 (112 → **161**, +49 cho các loại số mới + full-width), `QuickTranslationRuleElement` 146 (132 → **146**), `QuickTranslationRuleTokenSettings` 68 (64 → **68**), `QuickTranslationRuleTokenSettingsView` 67 (63 → **67**). Không file nào vào bảng 1.1, không baseline nào bị sửa.
* **Độ phức tạp lúc chạy không đổi bậc**: `<h>`/`<d>` cùng cơ chế `walkNumeral` greedy dài → ngắn và boundary guard; `units(for:)` tra một `Set<UInt16>` tĩnh nên không thêm đơn vị công việc thường trực. Full-width chỉ thêm 10 phần tử vào `digitMap`.
* `check_architecture.py` giữ **14 violation nền** đã biết, không violation mới. Host Windows không build được; tính đúng đắn biên dịch cần CI/macOS.

## Số dòng sau lượt 1.3.286

* **Tổng file Swift không đổi**: xoá `QuickTranslationRuleDisableIOMenu.swift` 237 dòng, thêm [`QuickTranslationRuleIOMenu+DisabledActions.swift`](../../Sources/Views/Settings/Translation/QuickTranslationRuleIOMenu+DisabledActions.swift) 136 dòng. Đây là tách extension cho cùng `QuickTranslationRuleIOMenu`, không thêm primary type top-level.
* **File owner menu vẫn dưới trần 400**: [`QuickTranslationRuleIOMenu.swift`](../../Sources/Views/Settings/Translation/QuickTranslationRuleIOMenu.swift) 229 → **304** dòng vì nhận thêm state/dialog cho rule tắt và switch theo `showingDisabled`. [`QuickTranslationRuleListView.swift`](../../Sources/Views/Settings/Translation/QuickTranslationRuleListView.swift) vẫn **381** dòng, chỉ đổi từ hai modifier toolbar sang một modifier có tham số tab.
* `check_architecture.py` giữ **14 violation nền** đã biết, không có violation mới và không nới baseline. Host Windows không build được bằng `xcodebuild`; tính đúng đắn biên dịch cần CI/macOS xác nhận.

## Số dòng sau lượt 1.3.279

* **Thay 1 file Service bằng 1 file Service, không tăng số file Swift tổng**: xoá `QuickTranslationRuleFileEditor.swift`, thêm `QuickTranslationRuleRecordStore.swift`. File mới là enum thuần Foundation, một type top-level, dưới trần 400.
* **Giảm độ phức tạp CRUD/import Quick Translation Rule**: bỏ metadata row UUID/source revision và phẫu thuật theo dòng; hai store chung/riêng sửa mảng records theo `pattern` rồi serialize lại TXT canonical. Snapshot/trace nhỏ hơn vì không còn `Row.id`/`rowID`.
* **`check_architecture.py` giữ đúng 14 violation nền** sau khi rút gọn `QuickTranslationRuleStore.swift` dưới trần 400; không thêm allowlist và không tạo violation mới. Build Swift vẫn cần macOS/CI vì host Windows không có `xcodebuild`/`xcodegen`.

## Số dòng sau lượt 1.3.274

* **17 file mới, tất cả dưới trần 400 và đúng 1 type top level** (type lồng `Snapshot`/`Outcome`/`Capture`/`Status`/`SharedFile` không tính). Năm file lớn nhất: `ReaderRuleTraceOverlayView.swift` **383** *(xoá ở 1.3.334)*, [`QuickTranslationRuleBookStore.swift`](../../Sources/Services/Translation/Engine/QuickTranslationRuleBookStore.swift) **360**, [`ReaderView+RuleTools.swift`](../../Sources/Views/Reader/Extensions/ReaderView+RuleTools.swift) **272**, [`QuickTranslationRuleDisableStore.swift`](../../Sources/Services/Translation/Engine/QuickTranslationRuleDisableStore.swift) **239**, [`QuickTranslationRuleDiagnostics.swift`](../../Sources/Services/Translation/Engine/QuickTranslationRuleDiagnostics.swift) **232**. Nhỏ nhất [`TranslationManager+BookScopedFiles.swift`](../../Sources/Services/Translation/Extensions/TranslationManager+BookScopedFiles.swift) **28**; file dưới 100 dòng có 7 (`Scope` 38, `DisableFile` 81, `Trace` 93, `GuideSheet` 74, `ChipStyle` 61, `Chip` 68, `Transfer` 71).
* **Tổng file Swift 388 → 405** (+17): `Sources/Models/Translation/` 7 → **9**, `Sources/Services/Translation/Engine/` 17 → **22**, `Sources/Services/Translation/Extensions/` 3 → **4**, `Sources/Views/Reader/` 15 → **18**, `Sources/Views/Reader/Components/` 6 → **8**, `Sources/Views/Reader/Extensions/` 5 → **7**, `Sources/Views/Settings/Translation/` 8 → **10**. **Không** thêm resource bundled — bộ riêng là dữ liệu người dùng ở `translate/books/<bookId>/`.
* **File legacy giảm thật (điểm nhấn của lượt này)**: [`ReaderView.swift`](../../Sources/Views/Reader/ReaderView.swift) **2286 → 2076** (−210; baseline 2053 — file vẫn trên baseline nhưng khoảng cách thu từ +233 còn +23). Lượt giảm đến từ hai nguồn: dời khối biên tập vùng chọn (179 dòng, `ReaderView+Selection.swift`) và xoá **73 dòng code chết** không caller (`sentenceSegments`, `translatedSentenceSegments`, `selectedTokens`, `isEditableSource`, `deleteMatch`).
* **File đã có, tăng — đều dưới trần 400**: [`QuickTranslationRuleListView.swift`](../../Sources/Views/Settings/Translation/QuickTranslationRuleListView.swift) 244 → **381** (+137: `scope` + 2 tab + hàng `EntryRow` + I/O), [`QuickTranslationRuleEditorSheet.swift`](../../Sources/Views/Settings/Translation/QuickTranslationRuleEditorSheet.swift) 132 → **177** (+45: segment Riêng/Chung + prefilled pattern), [`DictionaryHubView.swift`](../../Sources/Views/Dictionary/DictionaryHubView.swift) 116 → **152** (+36: section Rule Dịch + `ruleStatusText`), [`QuickTranslationRuleEngine.swift`](../../Sources/Services/Translation/Engine/QuickTranslationRuleEngine.swift) 213 → **293** (+80: hai bộ + `collectFound`/`select` nội hoá), [`FloatingSelectionMenu.swift`](../../Sources/Views/Reader/Components/FloatingSelectionMenu.swift) 162 → **202**, [`QuickTranslationRuleStore.swift`](../../Sources/Services/Translation/Engine/QuickTranslationRuleStore.swift) 392 → **394** (chỉ thêm guard lọc tiếng ồn cho rule đang tắt — file sát trần nhất repo, còn 6 dòng). Không file nào chạm trần 400 lần đầu, không baseline nào bị sửa.
* **Độ phức tạp lúc chạy — hai con số cần nhớ**: lượt rewrite thật chạy **hai** lần `collectFound` (riêng + chung) thay vì một nhưng vẫn `select` một lượt — chi phí cộng dồn là hai lần prefilter trên cùng số chữ, không đổi bậc (mỗi lần O(số ký tự × kích thước bucket; bộ riêng vài chục rule nên phần thêm gần như không đáng kể). Màn Check rule (`QuickTranslationRuleDiagnostics.diagnose`) là ca đắt nhất: `includesDisabled: true` chạy matcher trên **cả** rule đang tắt/bị token tắt với cả hai bộ — với bộ 17.278 rule, lượt mở màn có thể đắt gấp vài lần rewrite thật, nhưng vẫn theo quy luật ứng viên/dòng tỉ lệ với chữ chứ không tỉ lệ với số rule (42,3 / 18,0 ứng viên mỗi dòng như cũ). Không có vòng lặp mới theo số truyện: LRU cap 3 khiến mở truyện thứ 4 trở đi compile lại bộ riêng (rẻ — vài chục rule).
* `check_architecture.py` không chạy được trên Windows (cổng tĩnh này cần chạy trên macOS cùng với build); số dòng đo bằng `wc -l`, tính đúng đắn biên dịch do CI xác nhận.

## Số dòng sau lượt 1.3.272

* **26 file mới, tất cả dưới trần 400 và đúng 1 type top level.** Năm file lớn nhất: [`QuickTranslationRuleStore.swift`](../../Sources/Services/Translation/Engine/QuickTranslationRuleStore.swift) **392**, [`QuickTranslationRuleParser.swift`](../../Sources/Services/Translation/Engine/QuickTranslationRuleParser.swift) **349**, [`QuickTranslationRuleCompiler.swift`](../../Sources/Services/Translation/Engine/QuickTranslationRuleCompiler.swift) **310**, [`QuickTranslationRulesView.swift`](../../Sources/Views/Settings/Translation/QuickTranslationRulesView.swift) **303**, [`QuickTranslationRuleListView.swift`](../../Sources/Views/Settings/Translation/QuickTranslationRuleListView.swift) **244**. Hai file mới của lượt này: `QuickTranslationRuleTokenSettings` **64** và `QuickTranslationRuleTokenSettingsView` **59**; cả hai chỉ có một type top level.
* **Tổng file Swift 362 → 388**; `Sources/Services/Translation/Engine/` 1 → **17** file, `Sources/Services/Translation/Extensions/` 1 → **3** file, `Sources/Views/Settings/Translation/` 2 → **8** file. **Không** thêm resource bundled nào — bộ rule là dữ liệu tải về, nằm ở `translate/QuickTranslateRules.txt`.
* **File legacy giảm thật**: [`TranslateUtils.swift`](../../Sources/Services/Translation/Utils/TranslateUtils.swift) 1041 → **1023** (−18) — thêm ~40 dòng plumbing nhưng dời 68 dòng (`buildTranslationSpans`, `findTranslatedTokenRange`) sang file `+QuickTranslationRules`. Baseline allowlist **917** không bị sửa; file vẫn trên baseline như trước lượt này, chỉ gần hơn.
* **File đã có, tăng**: [`SettingsView.swift`](../../Sources/Views/Settings/Main/SettingsView.swift) 443 → **448** (+5, vẫn dưới baseline 453 nhờ tách `QuickTranslateRuleSettingsRows`), [`BackupConfigArchiver.swift`](../../Sources/Services/Backup/BackupConfigArchiver.swift) 109 → **136**, [`BackupPaths.swift`](../../Sources/Services/Backup/BackupPaths.swift) 143 → **149**, [`FreeBookApp.swift`](../../Sources/App/FreeBookApp.swift) 108 → **113**, [`JSExecutor.swift`](../../Sources/Services/Extensions/Engine/JSExecutor.swift) 1514 → **1516**. Không file nào chạm trần 400 lần đầu, không baseline nào bị sửa, `check_architecture.py` giữ **14 violation** cùng một tập.
* **Độ phức tạp lúc chạy — con số cần nhớ**: prefilter cho **42,3** ứng viên/dòng với bộ 633 rule và **18,0** với bộ 17.278 rule (đo trên 30 dòng chương thật). Tập ứng viên tỉ lệ với *chữ trong dòng*, không tỉ lệ với *số rule* — đó là toàn bộ lý do bộ 17k khả thi về nguyên tắc. Chi phí còn lại là O(số ký tự × kích thước bucket) cho mỗi chuỗi, cộng backtracking bị chặn ở 4.000 bước cho mỗi (rule, vị trí).
* **Nơi dễ thành điểm nóng nhất về sau**: `QuickTranslationDictionaryToken.candidates` gọi `findAllPrefixMatches` một lần cho **mỗi nhóm từ điển × mỗi vị trí capture**, và mỗi lời gọi tự dựng `Array(text.utf16)` của cửa sổ. Cửa sổ đã được cắt còn tối đa `maxLength` (≤ 12) đơn vị UTF-16 chính vì lý do này — đừng truyền cả dòng vào đó.

## Số dòng sau lượt 1.3.266

* **Một file mới, dưới trần 400 và đúng 1 type top level**: [`KeyboardDismissGesture.swift`](../../Sources/Common/Utils/KeyboardDismissGesture.swift) **112** dòng (trong đó ~25 dòng là comment giải thích ba thiết lập của recognizer). Tổng file Swift 361 → **362**; không thư mục mới (`Sources/Common/Utils/` 7 → **8** file).
* **File đã có, tăng**: [`StaleBookCleanupSettingsView.swift`](../../Sources/Views/Settings/Cleanup/StaleBookCleanupSettingsView.swift) 209 → **238** (+29: `clampedInactiveDays`, `nudgeButton`, bố cục mới của `thresholdSection`), [`FreeBookApp.swift`](../../Sources/App/FreeBookApp.swift) 107 → **108** (+1). Không file nào chạm trần 400 lần đầu, không file nào vào bảng 1.1, không baseline nào bị sửa.
* **Chi phí lúc chạy của recognizer gần như bằng không, nhưng chỗ tốn nằm ở nơi dễ bỏ qua**: `installIfNeeded()` quét `connectedScenes → windows` **mỗi lần bàn phím hiện**, không phải một lần. Vòng quét là O(số scene × số window) với số window thực tế ≤ 4 (window chính + toast + 2 widget) và mỗi window chỉ so `gestureRecognizers.name`, nên chi phí là hằng số cỡ vài phép so chuỗi — đổi lấy việc phủ được window sinh ra sau. Không tạo `Task`, không giữ danh sách, không có gì cần dọn.
* **`isEditableTextInput` là O(độ sâu cây view)** tính từ view bị chạm lên tới window, chạy **một lần mỗi touch** khi bàn phím đang hiện. Cây view SwiftUI sâu nhưng hữu hạn (thực tế vài chục tầng) và phép kiểm tra chỉ là `as?` + đọc `isEnabled`/`isEditable`; không có regex, không cấp phát. Nếu sau này cần thêm loại ô nhập, thêm vào đúng vòng lặp này thay vì tra bảng tên class.
* **Không có đường rò**: recognizer do window giữ (`window.addGestureRecognizer`) và `target` là singleton sống suốt vòng đời app, nên vòng tham chiếu recognizer ↔ singleton là **có chủ ý** và không cần `[weak self]` (đây là closure-free `#selector`, không phải callback audio). Observer `keyboardWillShowNotification` cũng không cần gỡ vì singleton không bao giờ bị hủy.

## Số dòng sau lượt 1.3.265

* **Hai file mới, đều dưới trần 400 và đúng 1 type top level**: [`BackupConfigArchiver.swift`](../../Sources/Services/Backup/BackupConfigArchiver.swift) **109** (`Report` nest), [`SearchEngineTransfer.swift`](../../Sources/Models/Dictionaries/SearchEngineTransfer.swift) **107** (`Failure` nest). Tổng file Swift 359 → **361**; không thư mục mới (`Sources/Services/Backup/` 22 → **23** file).
* **File tăng mạnh nhất lượt này**: [`SearchEnginesConfigView.swift`](../../Sources/Views/Settings/Search/SearchEnginesConfigView.swift) 116 → **259** (+143). Phần thêm gần như toàn bộ là hạ tầng nhập/xuất đã có khuôn sẵn ở các màn khác (`ExportDocument`, `DocumentPickerPresenter`, `ShareSheet`, `confirmationDialog`, alert) — logic thật (codec + gộp) nằm ở file `Models` dùng chung, nên màn này vẫn cách trần 400 khá xa.
* **File đã có, tăng**: [`BackupRestoreWorker.swift`](../../Sources/Services/Backup/BackupRestoreWorker.swift) 271 → **280** (+9, nặng nhất phần backup), [`BackupPaths.swift`](../../Sources/Services/Backup/BackupPaths.swift) 136 → **143**, [`RestoreOptionsSheet.swift`](../../Sources/Views/Settings/Backup/RestoreOptionsSheet.swift) 123 → **130**, [`BackupManifest.swift`](../../Sources/Services/Backup/BackupManifest.swift) 108 → **114**, [`SearchEngine.swift`](../../Sources/Models/Dictionaries/SearchEngine.swift) 49 → **54**, [`BackupSettingsArchiver.swift`](../../Sources/Services/Backup/BackupSettingsArchiver.swift) 123 → **127**, [`BackupCoordinator.swift`](../../Sources/Services/Backup/BackupCoordinator.swift) 290 → **293**, [`BackupExportWorker.swift`](../../Sources/Services/Backup/BackupExportWorker.swift) 252 → **253**. [`BackupHubView.swift`](../../Sources/Views/Settings/Backup/BackupHubView.swift) **206** và [`BackupScope.swift`](../../Sources/Services/Backup/BackupScope.swift) **55** không đổi số dòng (chỉ đổi chuỗi). Không file nào chạm trần 400 lần đầu, không file nào vào bảng 1.1.
* Chi phí chiều xuất là **hai lần I/O file nhỏ**, không đổi bậc: một `copyItem` cho `toc_rules.json` và một `write` cho `Data` của khoá `custom_search_engines` (thực tế vài KB). **Không** thêm bước nào vào `BackupSizeEstimator` — cùng lý do với khối cài đặt, nó đo thư mục và phần này không đáng kể.
* Chi phí chiều nhập là O(số quy tắc + số công cụ), tất cả trên RAM: `mergeTOCRules` gộp theo `id`, `SearchEngineTransfer.merged` dựng hai `Set` (`id` và chữ ký) rồi quét một lượt danh sách nhập ⇒ O(n + m) chứ không phải O(n·m). `newCount` **gọi lại `merged`** — chấp nhận vì n ≤ 50 và nó chỉ chạy khi dựng chuỗi cho hộp thoại; đừng dùng nó trong vòng lặp. Đĩa bị ghi nhiều nhất hai lần (một `saveTOCRules`, một `saveEngines`), và `saveTOCRules` kéo theo dọn cache regex + cache tên chương — chi phí thật nằm ở lần tra tiếp theo phải dựng lại regex, không ở lúc ghi.
* Chi phí chốt an toàn khi nhập bằng 0 ở đường thành công: kiểm `data.count` trước khi decode nên file rác lớn bị chặn **trước** khi dựng mảng; phần còn lại là một lượt `enumerated()` trim + `contains("%s")`.
* `check_architecture.py`: **14 → 14 violation**, đúng cùng một tập — không vi phạm mới, không baseline nào bị nới, `architecture_allowlist.json` không đổi. Host là Windows nên **không build tại chỗ** và `xcodegen generate` chưa chạy (2 file mới cần nó trên macOS/CI, `project.yml` khai theo thư mục nên không phải sửa); số dòng đo bằng `wc -l`, tính đúng đắn biên dịch do CI xác nhận.

## Số dòng sau lượt 1.3.264

* **Ba file mới, tất cả dưới trần 400 và đúng 1 type top level**: [`ManageDefinitionsDraft.swift`](../../Sources/Views/Dictionary/ManageDefinitionsDraft.swift) **126** (`Row` nest), [`BackupSettingsArchiver.swift`](../../Sources/Services/Backup/BackupSettingsArchiver.swift) **123** (`Report` nest), [`ManageDefinitionRowView.swift`](../../Sources/Views/Dictionary/ManageDefinitionRowView.swift) **73**. Tổng file Swift 356 → **359**; không thư mục mới.
* **File giảm mạnh nhất lượt này**: [`ManageDefinitionsView.swift`](../../Sources/Views/Dictionary/ManageDefinitionsView.swift) 343 → **186** (−157). Phần biến mất là 4 khối `TextField` "thêm nghĩa" gần như giống nhau + hộp thoại nhập nghĩa + `deletedMeanings`/`localMatches` — tức lượt này **giảm** tổng dòng của `Views/Dictionary/` dù thêm 2 file (343 → 385 cho cả ba file, +42 cho đủ nút lên/xuống/chèn/hoàn tác).
* **File đã có, tăng**: [`BackupRestoreWorker.swift`](../../Sources/Services/Backup/BackupRestoreWorker.swift) 249 → **271** (+22, nặng nhất phần backup), [`RestoreOptionsSheet.swift`](../../Sources/Views/Settings/Backup/RestoreOptionsSheet.swift) 111 → **123**, [`BackupPaths.swift`](../../Sources/Services/Backup/BackupPaths.swift) 130 → **136**, [`BackupCoordinator.swift`](../../Sources/Services/Backup/BackupCoordinator.swift) 287 → **290**, [`StaleBookCleanupCoordinator.swift`](../../Sources/Services/Cleanup/StaleBookCleanupCoordinator.swift) 120 → **126**, [`BackupManifest.swift`](../../Sources/Services/Backup/BackupManifest.swift) 103 → **108**, [`BackupExportWorker.swift`](../../Sources/Services/Backup/BackupExportWorker.swift) 248 → **252**, [`StaleBookCleanupSettingsView.swift`](../../Sources/Views/Settings/Cleanup/StaleBookCleanupSettingsView.swift) 208 → **209**. Không file nào chạm trần 400 lần đầu, không file nào vào bảng 1.1.
* Chi phí phần cài đặt là **O(số khoá `UserDefaults`)** đúng một lần mỗi bản sao lưu: `dictionaryRepresentation()` dựng một `[String: Any]`, mỗi giá trị qua một lần `PropertyListSerialization.propertyList(_:isValidFor:)` rồi cả snapshot serialize một lần thành plist nhị phân. Thực tế vài trăm khoá / vài chục KB nên nhỏ hơn hẳn phần từ điển và ảnh bìa; **không** thêm bước nào vào `BackupSizeEstimator` (nó chỉ đo thư mục, và khối này không đáng kể).
* Chi phí màn Quản lý nghĩa ≈ 0 nhưng đổi bậc theo hướng tốt: mọi thao tác sửa/đổi chỗ/xoá là O(số nghĩa của một nhóm) trên RAM (`firstIndex(where:)` theo `UUID`), và **đĩa chỉ bị ghi một lần lúc đóng màn**, cho những nhóm thật sự đổi — bản cũ mỗi lần thêm/xoá một nghĩa là một lượt `saveCustomEntry` + nạp lại từ điển. `activeMeanings` chạy một lần cho mỗi nhóm lúc lưu và cho mỗi lần render section (O(n) với n = số nghĩa, n rất nhỏ).
* Chi phí chốt `isOnShelf` bằng 0: thêm một `guard` vào chính vòng lọc RAM đã có trong `staleBookIds`, không thêm lượt fetch nào. Nó **giảm** việc: tập truyện ứng viên nhỏ hơn nên `deleteBooksAsync` có ít việc hơn.
* `check_architecture.py`: **14 → 14 violation**, đúng cùng một tập — không vi phạm mới, không baseline nào bị nới, `architecture_allowlist.json` không đổi. Host là Windows nên **không build tại chỗ** và `xcodegen generate` chưa chạy (3 file mới cần nó trên macOS/CI, `project.yml` khai theo thư mục nên không phải sửa); số dòng đo bằng `wc -l`, tính đúng đắn biên dịch do CI xác nhận.

## Số dòng sau lượt 1.3.263

* **Bốn file mới, tất cả dưới trần 400 và đúng 1 type top level**: [`StaleBookCleanupSettingsView.swift`](../../Sources/Views/Settings/Cleanup/StaleBookCleanupSettingsView.swift) **208**, [`StaleBookCleanupPolicy.swift`](../../Sources/Services/Cleanup/StaleBookCleanupPolicy.swift) **126** (`Mode` nest, đúng khuôn `DriveAutoBackupPolicy` 123), [`StaleBookCleanupCoordinator.swift`](../../Sources/Services/Cleanup/StaleBookCleanupCoordinator.swift) **120** (`Outcome` nest), [`StaleBookCleanupSettingsSection.swift`](../../Sources/Views/Settings/Main/StaleBookCleanupSettingsSection.swift) **12**. Tổng file Swift 352 → **356**; hai thư mục mới `Sources/Services/Cleanup/` (2 file) và `Sources/Views/Settings/Cleanup/` (1 file).
* **File đã có, tăng**: [`BackupDictionaryRestorer.swift`](../../Sources/Services/Backup/BackupDictionaryRestorer.swift) 127 → **242** (+115, nặng nhất lượt này: 3 hàm trộn plist/JSON + nạp lại cache), [`TaskOptionsSheet.swift`](../../Sources/Views/Download/TaskOptionsSheet.swift) 209 → **277**, [`DownloadManager.swift`](../../Sources/Services/Download/DownloadManager.swift) 437 → **467** (baseline 640), [`MainTabView.swift`](../../Sources/Views/MainTabView.swift) 118 → **139**, [`BackupPaths.swift`](../../Sources/Services/Backup/BackupPaths.swift) 113 → **130**, [`BackupDictionaryArchiver.swift`](../../Sources/Services/Backup/BackupDictionaryArchiver.swift) 93 → **114**, [`BackupPayload.swift`](../../Sources/Services/Backup/BackupPayload.swift) 204 → **217**, [`BackupExportWorker.swift`](../../Sources/Services/Backup/BackupExportWorker.swift) 240 → **248**, [`BackupSizeEstimator.swift`](../../Sources/Services/Backup/BackupSizeEstimator.swift) 45 → **54**, [`BackupRestoreWorker.swift`](../../Sources/Services/Backup/BackupRestoreWorker.swift) 245 → **249**, [`NotificationInboxManager.swift`](../../Sources/Common/Services/NotificationInboxManager.swift) 88 → **93**, [`SettingsView.swift`](../../Sources/Views/Settings/Main/SettingsView.swift) 441 → **443** (baseline legacy 453, vẫn dưới trần), [`DownloadManager+TaskStore.swift`](../../Sources/Services/Download/DownloadManager+TaskStore.swift) 277 → **279**. Không file nào chạm trần 400 lần đầu, không file nào vào bảng 1.1.
* Chi phí runtime của lượt này nằm ở **một lần quét toàn bảng mỗi lượt**: `staleBookIds` `fetch(FetchDescriptor<Book>())` **không** predicate rồi lọc trên RAM (bắt buộc — bộ dịch SQLite iOS 17 lỗi với predicate chuỗi), nên độ phức tạp là O(số truyện trong tủ). Chấp nhận vì nó chạy nhiều nhất một lần mỗi lần khởi động, trong `Task.detached(priority: .utility)`, sau 40 giây. Cùng phép quét đó chạy lại mỗi khi người dùng kéo thanh trượt số ngày trong Cài đặt — đây là chỗ duy nhất nó chạy ở nhịp tương tác.
* Chi phí phần backup là **I/O tuần tự, không đổi bậc**: thêm đúng 3 file nhỏ (`dict/tts/`) vào staging, và phần khôi phục trộn theo khoá nên đọc-ghi mỗi file một lần. Phần nội dung truyện local làm archive **to hơn khi người dùng tắt `.content`** so với trước — đúng mục đích, nhưng `BackupSizeEstimator` không phản ánh được (nó chỉ đo thư mục, không biết truyện nào là local).
* Chi phí phần số chương tuỳ chọn ≈ 0: `ChapterLimitOption` từ enum thành struct 1 field `Int` (`allCases` là `static let`, dựng một lần), thanh trượt chỉ ghi `@State`, `clampCustomLimit` là hai phép so sánh.
* `check_architecture.py`: **14 → 14 violation**, đúng cùng một tập — không vi phạm mới, không baseline nào bị nới, `architecture_allowlist.json` không đổi. Host là Windows nên **không build tại chỗ** và `xcodegen generate` chưa chạy (4 file mới cần nó trên macOS/CI, `project.yml` khai theo thư mục nên không phải sửa); số dòng đo bằng `wc -l`, tính đúng đắn biên dịch do CI xác nhận.

## Số dòng sau lượt 1.3.262

* **File legacy lớn nhất của `Views/Common` tự thu nhỏ**: [`BypassWebView.swift`](../../Sources/Views/Common/BypassWebView.swift) 599 → **350** dòng (−249, baseline legacy 599 chỉ được giảm). Sáu file mới chia phần đã tách, tất cả dưới trần 400 và đúng 1 type top level: [`BypassBrowserHomePage.swift`](../../Sources/Views/Common/BypassBrowserHomePage.swift) **170**, [`BypassBrowserTabStore.swift`](../../Sources/Views/Common/BypassBrowserTabStore.swift) **149**, [`BypassBrowserTab.swift`](../../Sources/Views/Common/BypassBrowserTab.swift) **107**, [`URLBarTextField.swift`](../../Sources/Views/Common/URLBarTextField.swift) **102** (`Coordinator` nest), [`BypassBrowserTabBar.swift`](../../Sources/Views/Common/BypassBrowserTabBar.swift) **62** (`TabPill` nest), [`BypassBrowserWebPane.swift`](../../Sources/Views/Common/BypassBrowserWebPane.swift) **38**.
* File đã có, tăng: [`NavigationBarAppearance.swift`](../../Sources/Common/Utils/NavigationBarAppearance.swift) 44 → **56** (+12, gần hết là doc comment giải thích vì sao phải dựng appearance mới). Tổng file Swift 346 → **352**; `Sources/Views/Common/` 22 → **28** file.
* Chi phí runtime của lượt này nằm ở **bộ nhớ, không phải CPU**: mỗi tab là một `WKWebView` nên `BypassBrowserTabStore.maxTabCount = 8` là trần bắt buộc, và tab đóng phải đi qua `stopLoadingAndDetach()` mới thu hồi được (invalidate 6 KVO + `nil` hai delegate + `stopLoading`). Không có prefetch, không có cache nội dung — đúng 8 webview là mức xấu nhất.
* Đường vẽ lại của SwiftUI được cố tình thu hẹp: `objectWillChange` của mỗi tab được chuyển tiếp lên store nên View quan sát **một** publisher, còn `BypassBrowserWebPane.updateUIView` `return` ngay khi `webView.superview === uiView` ⇒ đổi tiêu đề/tiến độ **không** làm gắn lại webview. `URLBarTextField.updateUIView` chỉ gán `text` khi khác thật, tránh reset caret mỗi lần progress nhảy.
* `check_architecture.py`: **14 → 14 violation**, đúng cùng một tập — không vi phạm mới, không baseline nào bị nới, `architecture_allowlist.json` không đổi. Host là Windows nên **không build tại chỗ** và `xcodegen generate` chưa chạy (6 file mới cần nó trên macOS/CI, `project.yml` khai theo thư mục nên không phải sửa); số dòng đo bằng `wc -l`, tính đúng đắn biên dịch do CI xác nhận.

## Số dòng sau lượt 1.3.261

* Hai file mới, cả hai dưới hạn 400 dòng của file mới: `Sources/Views/Reader/Components/ReaderUserScrollDetector.swift` **143** dòng (một type chính, hai type lồng `Coordinator`/`ProbeView` — `MULTI_PRIMARY_TYPES` chỉ đếm top level nên không vi phạm), `Sources/Models/Extensions/PruneRepositoryExtensionsCommand.swift` **22** dòng.
* File đã có, tăng: `ReaderView.swift` 2241 → **2286** (baseline 2053 — vượt sẵn từ trước, lượt này làm khoảng cách rộng thêm 45 dòng), `ReaderView+Controls.swift` 211 → **248**, `ReaderSearchMatcher.swift` 88 → **120**, `ReaderSearchView.swift` 220 → **223**, `ParagraphCardView.swift` 101 → **106**, `ExtensionTransactionCoordinator.swift` 175 → **213**, `RepositoryManagerView.swift` 709 → **726**. Tổng file Swift 344 → **346**.
* `Scripts/check_architecture.py` giữ **14 violation, đúng cùng một tập** trước và sau lượt này — không file nào mới bước vào danh sách, không baseline nào bị nới, `architecture_allowlist.json` không đổi. `ReaderView.swift` và `ReaderViewModel.swift` vẫn là hai điểm nợ dòng nặng nhất của tầng Views; logic mới của lượt này được đặt vào `ReaderView+Controls.swift` và file component riêng thay vì nhồi thêm vào `ReaderView.swift` đúng theo khuôn `X+Feature.swift`.


## Số liệu sau khi thêm tự động sao lưu Drive (1.3.260)

* Tổng file Swift 340 → **344** (+4, không xoá file nào). Tất cả dưới trần 400 và đúng 1 type top level: [`DriveAutoBackupSettingsView.swift`](../../Sources/Views/Settings/Backup/DriveAutoBackupSettingsView.swift) **143**, [`BackupCoordinator+AutoDrive.swift`](../../Sources/Services/Backup/BackupCoordinator+AutoDrive.swift) **125** (`AutoDriveBackupOutcome` nest trong `extension BackupCoordinator`), [`DriveAutoBackupPolicy.swift`](../../Sources/Services/Backup/DriveAutoBackupPolicy.swift) **123** (`Mode` nest), [`NavigationBarAppearance.swift`](../../Sources/Common/Utils/NavigationBarAppearance.swift) **44**. Phân hệ `Sources/Services/Backup/` 18 → **20** file (26 kể cả `GoogleDrive/`); `Sources/Views/Settings/Backup/` 5 → **6**.
* File phình, đều nhỏ: [`NotificationInboxView.swift`](../../Sources/Views/Shelf/ShelfMain/NotificationInboxView.swift) 299 → **307**, [`BackupCoordinator.swift`](../../Sources/Services/Backup/BackupCoordinator.swift) 275 → **287** (+12, đúng hai hàm `setBusy`/`setProgress` + doc), [`BackupHubView.swift`](../../Sources/Views/Settings/Backup/BackupHubView.swift) 190 → **206**, [`MainTabView.swift`](../../Sources/Views/MainTabView.swift) 96 → **118**, [`BackupPaths.swift`](../../Sources/Services/Backup/BackupPaths.swift) 96 → **113**, [`NotificationInboxManager.swift`](../../Sources/Common/Services/NotificationInboxManager.swift) 68 → **88**, [`ReaderHeaderFooterOverlayView.swift`](../../Sources/Views/Reader/ReaderHeaderFooterOverlayView.swift) 210 → **215**, [`FreeBookApp.swift`](../../Sources/App/FreeBookApp.swift) 105 → **107**. Không file nào vào bảng 1.1, không file nào chạm trần 400.
* Điểm nóng của đợt này **không** phải CPU mà là **dung lượng + băng thông định kỳ**, và nó bị chặn bằng ba hằng ở đúng một chỗ ([`DriveAutoBackupPolicy`](../../Sources/Services/Backup/DriveAutoBackupPolicy.swift#L31)): `maxVersions = 5` (trần số bản ở **cả** Drive và máy — thư mục `backups/` không có cơ chế dọn theo tuổi nào khác), `startupDelayNanoseconds = 25 s` (đẩy nén+upload ra khỏi lúc khởi động), `defaultScopes` bỏ `.content`/`.dictShared` (chênh lệch hàng trăm MB mỗi lượt). Không hằng nào bị nhân bản sang coordinator hay view.
* Chỗ dễ sai nhất là **thứ tự** trong `runAutoDriveBackup`: `markRun()` đứng **trước** phần việc nặng (một lượt lỗi không được biến mỗi lần mở app thành một lần nén archive), và hai hàm dọn đứng **sau** upload (đỉnh chiếm chỗ 6 bản, đổi lấy việc upload lỗi không mất bản cũ nào). Phép xoá dựa **hoàn toàn** vào tiền tố `freebook-auto-`; sai vị từ `isAutoBackupFileName` là xoá bản thủ công của người dùng — đây là chỗ nguy hiểm nhất của đợt này.
* Chi phí phần Reader/thông báo/appearance gần như bằng 0: nút tìm chỉ đổi chỗ phát cùng một closure; `markRead` `guard` bỏ qua record đã đọc nên chạm lại không sinh I/O; `NavigationBarAppearance` chạy đúng một lần lúc `init()` và chỉ sửa 4 dictionary attribute.
* `check_architecture.py`: **14 → 14 violation**, đúng cùng một tập — không vi phạm mới, không baseline nào bị nới, không entry `architecture_allowlist.json` nào được thêm. Host là Windows nên **không build tại chỗ** và `xcodegen generate` chưa chạy (4 file mới cần nó trên macOS/CI, nhưng `project.yml` khai theo thư mục nên không phải sửa); số dòng đo bằng `wc -l`, tính đúng đắn biên dịch do CI xác nhận.

## Số liệu sau khi gỡ tìm toàn văn; thêm tìm-Reader + Trung tâm thông báo (1.3.258)

* Tổng file Swift 344 → **340** (−10 +6). **Xoá 10 file** (cả `Sources/Services/Search/` 7 file + `ShelfContentSearchView.swift`, `ChapterSearchIndexSettingsView.swift`, `ChapterSearchSettingsSection.swift`), gồm cả `ChapterSearchIndexDatabase.swift` 397 dòng — file sát trần nhất repo trước đây nay biến mất. **Thêm 6 file**, tất cả dưới trần 400 và đúng 1 type top level: [`NotificationInboxView.swift`](../../Sources/Views/Shelf/ShelfMain/NotificationInboxView.swift) **299** (`InboxItem` nest), [`ReaderSearchView.swift`](../../Sources/Views/Reader/ReaderSearchView.swift) **220**, [`ReaderSearchMatcher.swift`](../../Sources/Common/Utils/ReaderSearchMatcher.swift) **88** (`Paragraph`/`Chapter`/`Hit` nest), [`NotificationInboxStore.swift`](../../Sources/Common/Services/NotificationInboxStore.swift) **82**, [`NotificationInboxManager.swift`](../../Sources/Common/Services/NotificationInboxManager.swift) **68**, [`NotificationInboxRecord.swift`](../../Sources/Common/Services/NotificationInboxRecord.swift) **54**. `check_architecture.py` vẫn đúng **14 violation** với tập y hệt; không entry `architecture_allowlist.json` nào được thêm.
* `ChapterPersistenceStore.swift` 926 → **915** (gỡ lời gọi index), `ShelfSearchView.swift` 264 → **219** (gỡ `SearchScope`/picker/nhánh `.content`), `SettingsView.swift` 443 → **441** (gỡ section). `ReaderView.swift` tăng nhẹ vì thêm `.sheet` + hai helper — vẫn nằm trong tập 14 violation từ trước (đã trên baseline), không phát sinh loại vi phạm mới.
* Điểm nóng độ phức tạp của phân hệ FTS5 (dung lượng đĩa của tokenizer `trigram`, dựng snippet, hoà giải mục lục) **đã biến mất cùng phân hệ**. Chi phí tìm-Reader thay vào đó là O(số đoạn đã cache): [`ReaderSearchMatcher.search`](../../Sources/Common/Utils/ReaderSearchMatcher.swift#L1) duyệt tuyến tính các chương `.loaded` trong RAM, `folding(options:)` mỗi đoạn, debounce 250 ms ở [`ReaderSearchView`](../../Sources/Views/Reader/ReaderSearchView.swift#L1). Không đĩa, không SQL, không chỉ mục ⇒ không có điểm nóng dung lượng và không tái lập đường crash.
* Trung tâm thông báo giữ chi phí thấp: [`NotificationInboxStore`](../../Sources/Common/Services/NotificationInboxStore.swift#L1) chặn cứng 200 record (drop cũ nhất), ghi `.atomic`; `NotificationInboxManager` cập nhật RAM ngay để badge phản hồi tức thì rồi persist nền qua actor. Phần "mỗi truyện mấy chương" không dựng dữ liệu mới — đọc thẳng `NewChapterRecord` sẵn có.

## Số liệu sau khi thêm hộp thư chương mới (1.3.256)

* Tổng file Swift 326 → **334** (+8, phân hệ mới `Sources/Services/NewChapters/` 5 file): [`NewChapterProbe.swift`](../../Sources/Services/NewChapters/NewChapterProbe.swift) **209**, [`NewChapterInboxManager.swift`](../../Sources/Services/NewChapters/NewChapterInboxManager.swift) **138**, [`ShelfView+NewChapters.swift`](../../Sources/Views/Shelf/ShelfMain/Extensions/ShelfView+NewChapters.swift) **127**, [`NewChapterCheckPolicy.swift`](../../Sources/Services/NewChapters/NewChapterCheckPolicy.swift) **110**, [`NewChapterStore.swift`](../../Sources/Services/NewChapters/NewChapterStore.swift) **107**, [`NewChapterRecord.swift`](../../Sources/Services/NewChapters/NewChapterRecord.swift) **87**, [`NewChapterSettingsView.swift`](../../Sources/Views/Settings/NewChapters/NewChapterSettingsView.swift) **82**, [`NewChapterSettingsSection.swift`](../../Sources/Views/Settings/Main/NewChapterSettingsSection.swift) **12**. Tất cả dưới trần 400 và đúng 1 type top level (`Mode` nest trong `NewChapterCheckPolicy`, `Target`/`Outcome` nest trong `NewChapterProbe`, `BatchSummary` nest trong `NewChapterInboxManager`) ⇒ **không** entry `architecture_allowlist.json` nào được thêm.
* File phình, đều nhỏ: [`ShelfView.swift`](../../Sources/Views/Shelf/ShelfMain/ShelfView.swift) 836 → **867** (baseline allowlist 942, còn dư 75 — badge, `.task`, 2 mục menu, `markSeen`, 2 `@Query` đổi sang `internal`), [`BookDetailLoader.swift`](../../Sources/Services/Extensions/Workers/BookDetailLoader.swift) 97 → **112** (+15, đúng một hàm `fetchPageTOC`), [`MainTabView.swift`](../../Sources/Views/MainTabView.swift) 76 → **79**, [`SettingsView.swift`](../../Sources/Views/Settings/Main/SettingsView.swift) 440 → **441**. Không file nào vào bảng 1.1.
* Điểm nóng của đợt này là **chi phí mạng**, không phải CPU: một lượt tự động tải tối đa `maxBooksPerBatch = 20` mục lục, tuần tự, cách nhau `interBookDelayNanoseconds = 0.4` s. Chặn thứ hai là `maxTOCPagesPerCheck = 8`: nguồn phân trang tới 50 trang thì probe **chỉ lấy trang cuối** (1 request thay vì 50) và đánh `probedIsPartial` — đổi độ chính xác của *con số* lấy độ chính xác của *câu trả lời có/không*. Hai hằng này sống ở đúng một chỗ ([`NewChapterCheckPolicy`](../../Sources/Services/NewChapters/NewChapterCheckPolicy.swift#L27)), không nhân bản sang manager hay probe.
* Chỗ dễ sai nhất là `applyDiff` ([`NewChapterProbe.swift#L168`](../../Sources/Services/NewChapters/NewChapterProbe.swift#L168)) — 4 nhánh xếp theo độ tin cậy giảm dần, và hai nhánh cuối cố ý **không** báo chương mới khi bằng chứng yếu: mục lục chỉ có trang cuối mà không thấy mốc ⇒ báo `1` + `isCountExact = false` (badge hiện `•`), còn nguồn đổi url chương cuối mà tổng số chương không tăng ⇒ báo **0**. Đây là hai nguồn báo động giả duy nhất có thể có.
* Bộ nhớ: `NewChapterStore` giữ toàn bộ record trong RAM sau lượt đọc đầu — mỗi record là ~10 field vô hướng nên 1000 truyện vẫn ở mức trăm KB; `prune` mỗi lần mở Kệ sách chặn file phình theo truyện đã xoá. Probe đổi `[ChapterResult]` sang tuple `(name:url:)` ngay khi nhận, không giữ tham chiếu nào sang tầng extension.
* `check_architecture.py`: **14 → 14 violation**, đúng cùng một tập — không vi phạm mới, không baseline nào bị nới. Host là Windows nên **không build tại chỗ**; số dòng đo bằng `wc -l`, tính đúng đắn biên dịch do CI xác nhận.

## Số liệu sau khi nhập PDF (1.3.255)

* Tổng file Swift 324 → **326** (+2: [`PdfDocumentReader.swift`](../../Sources/Services/Import/PdfDocumentReader.swift) **131**, [`PdfBookParser.swift`](../../Sources/Services/Import/PdfBookParser.swift) **136** — đều dưới trần 400 và đúng 1 type top level với `OutlineEntry` nest). Phân hệ `Sources/Services/Import/` 18 → **20** file.
* File phình: [`BookImportService.swift`](../../Sources/Services/Import/BookImportService.swift) 214 → **257** (+43 — nhánh `.pdf`, `Request.password`, 3 `ImportError`, và tách `loadData(_:)` ra khỏi đầu `parse`), [`BookImportConfirmationSheet.swift`](../../Sources/Views/Shelf/ShelfMain/BookImportConfirmationSheet.swift) 307 → **342**, [`ShelfView+BookImport.swift`](../../Sources/Views/Shelf/ShelfMain/Extensions/ShelfView+BookImport.swift) 215 → **273**, [`ShelfView.swift`](../../Sources/Views/Shelf/ShelfMain/ShelfView.swift) 811 → **836** (baseline allowlist 942, còn dư), [`BookImportFormat.swift`](../../Sources/Services/Import/BookImportFormat.swift) 107 → **125**, [`ParsedBook.swift`](../../Sources/Services/Import/ParsedBook.swift) 27 → **30**. Không file nào vào bảng 1.1.
* Điểm nóng thật của đợt này **không** phải độ phức tạp thuật toán — PDFKit đã lo phần phân tích cú pháp — mà là ba quyết định biên: (1) **ngưỡng 16 ký tự/trang** phân biệt trang scan với trang có chữ; nó chỉ dùng để *đếm và cảnh báo*, không loại nội dung, vì một trang bìa chương hợp lệ cũng rất ngắn. (2) **biên chương chỉ tới mức trang**: mục outline cùng trang bị gộp, mục trỏ lùi bị bỏ, để dãy trang luôn tăng — cắt trong lòng trang cần toạ độ đích và dễ làm sai thứ tự hơn là được thêm chương. (3) **`maxOutlineDepth = 8` / `maxOutlineEntries = 10_000`** chặn outline lồng sâu do máy sinh; đệ quy `appendChildren` là chỗ duy nhất có thể nổ.
* Không nạp cả file vào RAM: đây là lý do `detect(fileNameOnly:)` tồn tại. Chi phí trả thêm là một nhánh `try fileData ?? loadData(...)` ở 6 format cũ — rẻ hơn hẳn việc đổi mọi format sang mapped I/O.
* `check_architecture.py`: **14 → 14 violation**, đúng cùng một tập — không vi phạm mới, không baseline nào bị nới, không entry `architecture_allowlist.json` nào được thêm. Host là Windows nên **không build tại chỗ**; số dòng đo bằng `wc -l`, tính đúng đắn biên dịch do CI xác nhận.

## Số liệu sau khi sao lưu ảnh bìa (1.3.254)

* Tổng file Swift 323 → **324** (+1: [`BackupCoverArchiver.swift`](../../Sources/Services/Backup/BackupCoverArchiver.swift) **80** dòng, dưới trần 400, 1 type top level với `Report` nest). Phân hệ `Sources/Services/Backup/` 17 → **18** file (24 kể cả `GoogleDrive/`).
* File phình, đều nhỏ: [`BackupManifest.swift`](../../Sources/Services/Backup/BackupManifest.swift) 80 → **103** (+23 — gần như toàn bộ là `CodingKeys` + `init(from:)` viết tay, cái giá bắt buộc để archive cũ còn decode được), [`BackupCoordinator.swift`](../../Sources/Services/Backup/BackupCoordinator.swift) 259 → **275**, [`BackupRestoreWorker.swift`](../../Sources/Services/Backup/BackupRestoreWorker.swift) 236 → **245**, [`BackupExportWorker.swift`](../../Sources/Services/Backup/BackupExportWorker.swift) 232 → **240**, [`BackupPayload.swift`](../../Sources/Services/Backup/BackupPayload.swift) 196 → **204**, [`RestoreOptionsSheet.swift`](../../Sources/Views/Settings/Backup/RestoreOptionsSheet.swift) 108 → **111**, [`BackupProgress.swift`](../../Sources/Services/Backup/BackupProgress.swift) 79 → **83**, [`BackupPaths.swift`](../../Sources/Services/Backup/BackupPaths.swift) 94 → **96**, `BackupScope.swift` 54 → **55** (chỉ doc comment). Không file nào vào bảng 1.1.
* Không có điểm nóng mới: đường bìa là chép file (`linkItem` → `copyItem` khi xuất, `Data.write` khi khôi phục), không có số học nhị phân, không có vòng hai lượt. Chỗ dễ sai duy nhất là **tương thích định dạng**, không phải độ phức tạp: `Counts` mà thiếu `init(from:)` viết tay thì mọi `.fbbackup` cũ decode lỗi, và thêm case `BackupScope` thì bản app cũ đọc file mới decode lỗi — đã tránh cả hai.
* `check_architecture.py`: **14 → 14 violation**, đúng cùng một tập — không vi phạm mới, không baseline nào bị nới, không entry `architecture_allowlist.json` nào được thêm. Host là Windows nên **không build tại chỗ**; số dòng đo bằng `wc -l`, tính đúng đắn biên dịch do CI xác nhận.

## Số liệu sau khi tách phân hệ Xuất truyện bốn định dạng (1.3.253)

* Tổng file Swift 303 → **323** (+21 mới, −1 xoá: `Sources/Services/Download/TxtExportFileWriter.swift` 97 dòng). **21/21 file mới dưới trần 400 dòng**, lớn nhất [`MobiExportRenderer.swift`](../../Sources/Services/Export/MobiExportRenderer.swift) **207**, kế tiếp [`EpubExportRenderer.swift`](../../Sources/Services/Export/EpubExportRenderer.swift) 180, [`ZipStoreWriter.swift`](../../Sources/Services/Export/ZipStoreWriter.swift) 154, [`MobiHeaderBuilder.swift`](../../Sources/Services/Export/MobiHeaderBuilder.swift) 138, [`ExportContentProvider.swift`](../../Sources/Services/Export/ExportContentProvider.swift) 111, [`ExportShareCoordinator.swift`](../../Sources/Views/Common/ExportShareCoordinator.swift) 100; nhỏ nhất [`ExportParagraphSplitter.swift`](../../Sources/Services/Export/ExportParagraphSplitter.swift) **15**. Không file mới nào vào bảng 1.1. Phân hệ `Sources/Services/Export/` tổng **1375** dòng trên 20 file, trung bình ~69 dòng/file.
* File co lại — đây là mục tiêu chính của đợt này: [`DownloadManager.swift`](../../Sources/Services/Download/DownloadManager.swift) 484 → **437** (−47; nhánh `.exportTxt` cứng nhắc thay bằng `ExportRendererFactory` + `ExportContentProvider`, và bỏ luôn `import UIKit`). File phình: [`DownloadManager+TaskStore.swift`](../../Sources/Services/Download/DownloadManager+TaskStore.swift) 249 → **277**, [`TaskOptionsSheet.swift`](../../Sources/Views/Download/TaskOptionsSheet.swift) 148 → **209**, [`DownloadTaskOutcomeCalculator.swift`](../../Sources/Services/Download/DownloadTaskOutcomeCalculator.swift) 39 → **62**, [`DownloadTrackerView.swift`](../../Sources/Views/Download/DownloadTrackerView.swift) 208 → **217**, `DownloadPresentationEvent.swift` 5 → **11**, `MainTabView.swift` 70 → **76**, `FreeBookApp.swift` 103 → **105**. `ShelfView.swift` (811) và `BookDetailView.swift` (1175) chỉ đổi nhãn nút, độ dài không đổi.
* Điểm nóng độ phức tạp mới, cả ba đều là số học nhị phân và đã cô lập trong file riêng: (1) `MobiExportRenderer` là chỗ **khó nhất** — toàn văn phải ghi ra file tạm trước, rồi copy lại theo từng record 4096 byte trong lúc **vá tại chỗ** chỗ trống `filepos` 10 chữ số cố định (offset byte tuyệt đối, không thể biết trước khi có đủ text) ⇒ hai lượt đĩa, một bộ đệm, và bất biến "độ dài chuỗi vá phải đúng 10". (2) `MobiHeaderBuilder` dựng header **232 byte** + EXTH với mọi field big-endian tại offset tuyệt đối; lệch một byte là máy đọc hiện tên rác chứ không báo lỗi. (3) `ZipStoreWriter` phải giữ ba thứ khớp nhau — CRC-32 mỗi entry (bảng `crcTable` dựng sẵn), `localHeaderOffset` trong central directory, và số entry trong EOCD — cộng chặn `maxSize = Int(UInt32.max)` vì không cài ZIP64. Ba file này là nơi cần đọc kỹ nhất khi sửa về sau; phần còn lại của phân hệ đều là file ngắn một việc.
* Độ phức tạp **giảm** ở hai chỗ: vòng lặp chương của `DownloadManager` không còn phân nhánh theo định dạng (chỉ `renderer.append`), và quy ước `.part` từ chỗ nằm rải trong đường xuất TXT nay có đúng **một** chủ là `ExportStagingFile`.
* `check_architecture.py`: **14 → 14 violation**, đúng cùng một tập — không vi phạm mới, không baseline nào bị nới, không entry `architecture_allowlist.json` nào được thêm.
* Không build được để đo thời gian biên dịch: host là Windows, `xcodebuild`/`xcodegen` chỉ chạy trên macOS.

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
