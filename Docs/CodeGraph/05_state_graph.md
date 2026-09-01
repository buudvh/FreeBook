---
generated_by: Antigravity
generator_version: 1.0
generated_at: 2026-08-21T10:30:00+07:00
git_commit: UNKNOWN
source_files: 230
document_version: 6
---

# Máy Trạng thái (State Graph)

Tài liệu này phân tích chi tiết các máy trạng thái (State Machine) đang vận hành trong dự án FreeBook.

## Ghi chú thủ công (Human Notes)
*Ghi chú thủ công của con người.*

<!-- GENERATED START -->
## Trạng thái của một lượt bóc tách nguồn Legado (1.3.309)

* **Ba tầng biến, ba tuổi thọ khác nhau.** `LegadoVariableBag.sessionVariables` chỉ sống trong một lượt; `bookVariables` được ghi ra `legado_state/<sha256(bookId)>.json` nên **sống qua các lần khởi chạy app**; `chapterVariables` cũng persist nhưng khoá theo `chapterIndex`. Phải có tầng giữa vì mẫu dùng phổ biến nhất của nguồn là `java.put('bookId', …)` ở rule tìm kiếm rồi `java.get('bookId')` ở rule nội dung — hai lần fetch cách nhau cả phiên.
* **`isDirty` là điều kiện duy nhất để ghi file.** Nguồn không dùng biến thì không sinh file nào; đây là lý do một kệ sách toàn nguồn VBook sẽ không có thư mục `legado_state` nào.
* **`tocUrl` là state, không phái sinh được.** `BookInfoRule.tocUrl` cho phép mục lục ở URL khác trang chi tiết, mà `Book` chỉ có `detailUrl` và `detailUrl` **không được đổi** (vì `bookId = BookIdUtils.make(packageId, detailUrl)`). Vì vậy `tocUrl` được ghi vào sidecar lúc đọc chi tiết và đọc lại lúc làm mới mục lục.
* **`LegadoJSRuntime.unsupportedFeatures` là state tích luỹ trong lượt**, không reset giữa các đoạn rule; `LegadoRuleEvaluator` hút nó lên sau mỗi lần gọi JS để báo cáo tương thích thấy được cả thứ chỉ lộ ra lúc chạy.
* **Cache rule là state toàn cục có chủ ý** (`LegadoRuleCompiler` LRU 512, `LegadoXPathParser` 256, `LegadoRegexExtractor` 128). Khoá là chuỗi rule thô nên không lẫn giữa các nguồn; đổi nguồn không cần dọn cache.

## Bộ đếm hẹn giờ tắt: `sleepTimerRemainingSeconds` là state của phiên, không phái sinh từ `timerMode` (1.3.300)

* Ba biến, ba vai riêng: `timerMode` là **ý định** của người dùng (persist ở `ttsSleepTimerMode` / `ttsSleepTimerMinutes`), `sleepTimerRemainingSeconds` là **phần chưa đếm** của phiên hiện tại (chỉ trong RAM), `isTimerRunning` là **có `Timer` đang tick hay không**. Nạp lại `remaining` từ `minutes` của `timerMode` là xoá mất biến thứ hai — đúng lỗi "tạm dừng rồi phát lại thì đếm lại từ đầu".
* Vì vậy `restartSleepTimerIfNeeded` phân **ba** ca thay vì một: đang chạy ⇒ không làm gì; `remaining > 0` ⇒ `resumeTimerCountdown()` đếm tiếp; `remaining == 0` mà mode vẫn còn ⇒ `startTimerCountdown(minutes:)` nạp một vòng mới (ca bấm phát lại sau khi hẹn giờ đã tự tạm dừng). Hàm này bị gọi ở **mỗi** lượt `speakCurrent()`, nên cửa `guard !isTimerRunning` là thứ giữ nó khỏi reset theo từng đoạn.
* `remaining` chỉ về 0 ở hai chỗ: tick cuối cùng, và `stopTimerCountdown(keepMode: false)` (tức `cancelSleepTimer` / `setStopAtEndOfChapter`). `pause()` và `stopPlayback()` dùng `keepMode: true` nên không đụng tới nó.
* `sleepTimerBadgeText` vì thế **không** còn đọc `isTimerRunning`: điều kiện hiển thị là `remaining > 0`. Badge trống lúc tạm dừng làm người dùng tưởng hẹn giờ đã bị huỷ trong khi state vẫn còn nguyên.

## Hai cờ tiêu đề chương: `@State` là bản sao để vẽ, UserDefaults là nguồn sự thật (1.3.299)

* `ReaderView.showChapterTitle` / `removeDuplicatedTitle` **không** phải nguồn sự thật. Người đọc chúng lúc dựng đoạn là `ReaderViewModel.processAndSaveChapter` và `TTSManager`, cả hai đọc `UserDefaults` theo `bookId`. Hai `@State` chỉ tồn tại để `Toggle` vẽ đúng vị trí, và được nạp lại ở `initializeReaderIfNeeded`.
* Vì vậy `ReaderSettingsView` **không** bind trực tiếp vào chúng: `Toggle` dùng `Binding` tự dựng, setter ghi `@State` *và* gọi closure của `ReaderView` để lưu khoá + dựng lại đoạn. Bind trực tiếp (1.3.298) tạo ra hai nguồn lệch nhau — cái vẽ đổi, cái dựng không đổi.
* `onShowChapterTitleChanged` / `onRemoveDuplicatedTitleChanged` nhận **giá trị mới** và cố ý **không** toggle lần nữa: chủ sở hữu việc flip là setter của binding, không phải `ReaderView`. Đây là lý do hai hàm cũ `toggleChapterTitleVisibility`/`toggleRemoveDuplicatedTitle` bị thay bằng `applyShowChapterTitle`/`applyRemoveDuplicatedTitle`.
* `showingTOCRules` và `showingJunkFilterManagerSheet` đã bị **xoá** khỏi `ReaderView` cùng hai `.sheet` của chúng: sau khi 1.3.298 gỡ hai mục menu thì không còn lối phát nào. `TOCRulesConfigView`/`JunkFilterManagementView` vẫn vào được từ tab Cài Đặt.

## Con trỏ của ô nhập mẫu là state chia sẻ giữa UIKit và SwiftUI (1.3.289)

* **`selectionStart`/`selectionLength` vẫn là một nguồn sự thật duy nhất, nhưng nay có hai người ghi**: `QuickTranslationRulePatternField` (báo con trỏ thật của `UITextView` lên) và dải chip / nút token / thanh min–max (đặt vùng chọn xuống). Không có bản sao thứ hai của con trỏ ở đâu.
* **Đơn vị không đổi ở tầng model**: chỉ số **ký tự** trên `Array(pattern)`. `NSRange` UTF-16 chỉ tồn tại bên trong representable, đúng biên UIKit — vẫn tôn trọng bất biến "mọi offset trao đổi với UIKit là NSRange UTF-16".
* **Hai cái chốt chống vòng lặp cập nhật**: cờ `isApplying` của coordinator (không báo lên khi chính mình đang áp giá trị xuống) và `lastReportedRange` (không áp lại đúng range vừa báo lên — cần khi quy đổi ký tự ⇄ UTF-16 không tròn vì chuỗi có ký tự ngoài BMP).
* **Cờ `isProgrammaticPatternEdit` của 1.3.288 đã bị xoá** cùng heuristic "gõ tay thì con trỏ về cuối". Nó chỉ tồn tại vì trước đó không đọc được con trỏ thật; giữ lại sẽ là hai nguồn tranh nhau quyết định con trỏ ở đâu. `reconcileSelection(after:)` giờ chỉ kẹp biên.
* **`@FocusState` chỉ còn dùng cho ô Bản dịch.** Ô Mẫu là `UIViewRepresentable` nên không tham gia hệ focus của SwiftUI: nó tự `becomeFirstResponder()` một lần trong `makeUIView` khi bản nháp nói ô này đang được gõ, và báo focus ra ngoài bằng `onFocusChange` để bản nháp ghi lại. `focusedField` vì vậy đổi từ `@FocusState` sang `@State` thường — nó là *dữ liệu của bản nháp*, không phải cái điều khiển focus.
* **Điều kiện mở thanh `:min-max` là state dẫn xuất, không phải state mới**: có vùng chọn ⇒ token trùng khít; chỉ có con trỏ ⇒ token có `start < caret ≤ end`.

## Bản nháp và vùng chọn của màn thêm/sửa rule (1.3.288)

* **`@State` của sheet không còn là nơi cuối cùng giữ chữ đang gõ.** Nguồn sự thật cho `TextField` vẫn là `@State`, nhưng nó được mirror sang `QuickTranslationRuleDraftStore` ở mỗi thay đổi (`.onChange(of: currentDraft)`) và `init` seed lại từ đó. Vì vậy một lượt SwiftUI dựng lại content của sheet — thứ đang xảy ra khi Reader tự chuyển chương lúc đang nghe — không còn xoá trạng thái nhập.
* **Store cố ý không phải `ObservableObject`**: nó chỉ là bản sao để khôi phục. Phát `objectWillChange` mỗi keystroke chỉ thêm một lượt invalidate vô ích.
* **Vòng đời slot bản nháp**: `store()` mỗi thay đổi → `clear()` **chỉ** khi lưu thành công hoặc bấm Hủy. Mở một `Mode.id` khác ⇒ slot cũ bị ghi đè (một slot duy nhất, không rò). Đóng sheet bằng vuốt xuống **giữ** bản nháp, nên mở lại đúng rule đó thì chữ còn nguyên — trạng thái trung gian này là hợp lệ và có chủ ý.
* **`selectionStart`/`selectionLength` là chỉ số ký tự trên `Array(pattern)`**, không phải UTF-16 và không phải `String.Index`. `length == 0` nghĩa là con trỏ chèn; `length > 0` là vùng chọn. (1.3.288 chỉ có dải chip cấp con trỏ; từ 1.3.289 ô nhập cấp con trỏ thật — xem mục trên.)
* **`isProgrammaticPatternEdit` (1.3.288) đã bị xoá ở 1.3.289** — xem mục trên. Nó từng phân biệt "gõ tay vào `TextField`" với "nút vừa chèn/sửa token" vì lúc đó không đọc được con trỏ thật.
* **`@FocusState` được khôi phục ở `onAppear`** theo `focus` của bản nháp: giữ chữ mà vẫn tụt bàn phím mỗi lần chuyển chương thì trạng thái nhập vẫn coi như bị gián đoạn.
* `didRestoreDraft` là cờ chỉ-đọc do `init` tính, log **một lần mỗi identity** ở `onAppear` (không log trong `init` — `init` chạy lại theo mỗi lượt body của view chủ). Đây là đầu dò để lần sau chẩn đoán được *nguyên nhân* SwiftUI dựng lại sheet, không phải chỉ triệu chứng.

## Preparing highlight trùng màu active highlight (1.3.278)

* `highlightIsPreparing` vẫn là state render cấp card/text-view để diff UIKit đúng khi chuyển preparing → active dù `NSRange` giống nhau, nhưng nó **không còn đổi màu**.
* Preparing và active highlight đều dùng `theme.highlightUIColor` và `theme.highlightTextUIColor` nếu có. Màu đến từ cấu hình highlight/theme hiện hành; không hard-code alpha riêng cho preparing.

## State mở rộng ban đầu của widget TTS khi phát từ Reader (1.3.277)

* `TTSFloatingWidgetWindowManager.shouldRevealOnNextShow` là cờ một lượt: `true` sau `requestRevealOnNextShow()`, trở về `false` ngay khi có `FloatingWidgetContainerViewController` để reveal.
* Nếu widget đã tồn tại, request reveal chạy ngay; nếu widget chưa tồn tại, cờ được consume trong `showWidget()` sau khi window/container được tạo. Nhờ đó không cần đổi default `FloatingWidgetViewModel.mode` khỏi `.peeking` cho toàn app.
* State mở rộng vẫn là `WidgetMode.revealed` hiện có và vẫn chịu auto-hide 3 giây của `FloatingWidgetViewModel.reveal()`. Không thêm state "force expanded" bền vững.

## Trạng thái highlight chuẩn bị của TTS (1.3.276)

* `TTSPlaybackSnapshot` nay có hai nhóm state highlight: nhóm **active** (`currentParentParagraphIndex` + `highlightRange`) chỉ được commit khi audio bắt đầu phát, và nhóm **preparing** (`preparingParentParagraphIndex` + `preparingHighlightRange`) được publish ngay trước khi tổng hợp/phát đoạn hiện tại.
* State chuẩn bị không phải trạng thái tiến độ đọc. Nó không đổi `currentParagraphIndex`, không claim progress và không làm Reader lưu DB; nó chỉ cho Reader vẽ vệt tô trong khoảng chờ engine, đặc biệt với `nghitts`.
* `ReaderView` không lưu range chuẩn bị vào `@State`: nó là giá trị phái sinh từ `ReaderTTSStateSnapshot`. Nếu active highlight có mặt thì chuẩn bị bị bỏ qua; nếu không có active highlight thì chuẩn bị thắng vệt tô tìm kiếm.
* `highlightIsPreparing` là state render cấp card/text-view để diff UIKit đúng màu nền. Cờ này là một phần của equality/diff, nên chuyển từ chuẩn bị sang active được repaint dù `NSRange` giống nhau.

## State của hai công cụ mới ở Reader (1.3.274)

* 6 `@State` mới khai trong `ReaderView.swift` nhưng **mọi hành vi** nằm ở `ReaderView+RuleTools.swift`: `showingCopyOriginalSheet`, `showingRuleTraceSheet`, `showingRuleGuide`, `ruleTraces`, `focusedRuleTraceID`, `ruleEditorMode`, `didChangeRuleData`. Extension **không thể** khai stored property nên state phải ở type gốc; đổi lại `ReaderView.swift` chỉ nhận thêm phần khai báo cộng một dòng `ruleToolsOverlay(in: geometry)`.
* **Nhiều thuộc tính đổi từ `private` sang `internal`** (không đổi ngữ nghĩa, chỉ mở phạm vi): `private` trong Swift là phạm vi **file**, mà `ReaderView+Selection.swift` và `ReaderView+RuleTools.swift` là file khác. Gồm `originalSentence`, `selectedWordOffset/Length`, `selectedTextForDefinition`, `customMeaning`, `translationMode`, `translationTokens`, `dictionaryMatches`, `saveAsNameType`, `saveToBookSpecific`, hai khoá `pinned*`, `shouldConvertTraditionalToSimplified`, `lookupRoute`, `editingParagraphIndex`, `selectedDisplayedText/Offset`, `clearSelectionTrigger`, và hai hàm `applyTranslation()` / `checkAndReleaseDeferredTranslationRefresh()`.
* **Bốn panel dùng chung một vùng chọn.** Màn Dịch, panel Xoá từ rác, panel Copy gốc và màn Check rule đều đọc `originalSentence` + `selectedWordOffset/Length`, nên `closeOtherSelectionPanels(except:)` đóng những panel còn lại khi mở một panel. `isAnySelectionOrOverlayActive` được cộng thêm `showingCopyOriginalSheet || showingRuleTraceSheet` để cơ chế deferral dịch-lại vẫn đúng.
* **`didChangeRuleData` là cờ một lượt**: bật khi có thao tác ghi rule thành công, đọc **một lần** lúc đóng sheet để quyết định gọi `applyTranslation()`, rồi reset. Không đổi gì ⇒ không dựng lại đoạn văn.
* **`focusedRuleTraceID` là `String?` chứ không phải index**: `QuickTranslationRuleTrace.id` xác định theo scope/pattern/location, nên sau khi chẩn đoán lại focus cũ còn tồn tại thì được giữ; không tồn tại thì về `nil` (`refreshRuleTraces` tự dọn).
* **`revision` của hai store mới không phải state của Reader.** Nó là `@MainActor @Published` chỉ để đẩy UI danh sách/hub; nó **không** đi vào cache key dịch — đường invalidation là `notifyDictionariesDidUpdate`.

## Trạng thái vệt tô kết quả tìm và cờ tắt cuộn theo highlight (1.3.261)

* `ReaderView.searchHighlight: ReaderSearchMatcher.Highlight?` là state **ý nghĩa**, không phải state **toạ độ**: nó giữ `(chapterIndex, paragraphIndex, query)`, còn `NSRange` là giá trị **phái sinh tính lại mỗi lần render** trong `searchHighlightRange(...)`. Bất biến bắt buộc: không được cache `NSRange` vào state này — chuỗi hiển thị đổi theo công tắc dịch (`isTranslationEnabled`) và theo việc `translated` đã dựng xong chưa, nên một range đã lưu sẽ trỏ sai ký tự; range phái sinh thì tệ nhất là tự mất (trả `nil`).
* Vòng đời của nó: `nil` là "không tô gì" (giá trị khởi tạo), được ghi **duy nhất** ở `jumpToReaderSearchResult`, và bị xoá về `nil` ở `.onChange(of: chapterIndex)` — không xoá thì vệt của chương cũ còn treo và sẽ tự tô lại nếu người dùng quay về đúng chương đó. Không có đường nào khác ghi vào nó; đóng sheet tìm **không** xoá vệt (cố ý: vệt là chỉ dẫn cho trang đọc, không thuộc vòng đời của sheet).
* `isAutoScrollDisabled` nay có **ba** nguồn ghi thay vì một: nút bật/tắt ở header (đã có), `jumpToReaderSearchResult` (nhảy tới kết quả tìm), và `handleUserScrollWhilePlaying` (người dùng kéo trang khi TTS đang đọc). Cả ba đều chỉ ghi `true` ngoài nút toggle. Cờ vẫn **không được persist**: `ReaderView.swift` đọc `UserDefaults("disableAutoScroll_\(bookId)")` một lần lúc dựng và không nơi nào ghi key đó, nên trạng thái tắt là **phạm vi phiên** — cố ý, mở lại truyện là quay về cuộn theo highlight.
* Mỗi lần ghi `isAutoScrollDisabled = true` phải đi kèm **hai** động tác dọn, nếu không cú cuộn đã hẹn giờ trước đó vẫn nổ: `ttsAutoScrollGeneration += 1` (vô hiệu closure đã schedule) và huỷ `scrollTarget` khi `reason == .ttsAuto` (cú đang chờ). Đây là bất biến của cả hai điểm ghi mới.
* `ReaderUserScrollDetector.Coordinator.didReportForCurrentDrag` là state **cấp cú kéo**, không phải cấp phiên: bật ở `.changed` khi vượt ngưỡng, tắt ở `.began`/`.ended`/`.cancelled`/`.failed` và ở `detach()`. Nhờ nó một cú kéo dài chỉ gọi `onUserScroll()` đúng **một** lần thay vì mỗi frame. `attachedScrollView` là `weak` và `attach(to:)` idempotent theo identity (`!==`), nên `updateUIView` chạy nhiều lần không tạo recognizer thứ hai.
* `showingFloatingMenu` đổi từ `private` sang `internal` (không đổi ngữ nghĩa, chỉ mở phạm vi): Swift `private` là phạm vi **file**, mà `handleUserScrollWhilePlaying` sống ở `ReaderView+Controls.swift` và cần đọc cờ này để không coi cú kéo nới vùng bôi đen là "người dùng cuộn".


## Trạng thái gợi ý ô nghĩa, sheet sửa thông tin và tiến độ task (1.3.250)

* `ReaderView.suggestionChips` đổi từ **giá trị phái sinh** (computed property, tính lại mỗi lần `body` evaluate) sang **state tường minh** `@State internal var suggestionChips: [SuggestionChip]`. Nó nay là hàm của hai đại lượng và chỉ được ghi khi một trong hai đổi: chuỗi đang chọn (`updateEditorFromSelection`, `onGetDictionaryMatches`) và nội dung từ điển của từ đó (nhánh xoá định nghĩa). Bất biến bắt buộc: cache phải bị làm mới theo **cả** `bookId` và chuỗi chọn — `refreshSuggestionChips(for:)` luôn nhận từ mới và luôn ghi đè, không có nhánh nào giữ lại giá trị cũ.
* `showingEditInfo` của `BookDetailView` **không còn tồn tại**. Trạng thái "đang sửa thông tin truyện" chuyển thành `@State private var editingInfoBook: Book?` của `ShelfView`, dùng chung cho hai tab — `nil` là đóng, khác `nil` là mở, không còn cặp cờ Bool + tham chiếu rời rạc. Không có state hiển thị nào cần đồng bộ tay sau khi lưu (`refreshDisplayedBookInfo()` đã bị xoá): `@Query` của ShelfView là nguồn duy nhất.
* `DownloadManager` có hai state phụ mới, cả hai **thuần để giảm nhịp ghi**, không mang ngữ nghĩa nghiệp vụ: `taskContext` (một `ModelContext` `autosaveEnabled = false` giữ suốt phiên) và `lastTaskSaveAt` + `lastProgressPublishAt[taskId]`. Bất biến: giá trị mới **luôn** được áp vào `DownloadTaskModel` ở mọi lần gọi `updateTaskInDB`; chỉ `save()` bị gộp (`coalesce: true` cho bước trung gian, `false` cho mọi trạng thái cuối). `@Published tasks` chỉ đổi tối đa ~10 lần/giây nhưng bước đầu, bước cuối và mọi thay đổi trạng thái/tổng số luôn được phát — nên `progressCount` mà UI thấy có thể nhảy bậc, còn giá trị cuối luôn đúng. `lastProgressPublishAt` được xoá ở `deleteTask`/`retryTask`/`markCompleted`/`markFailed`/`markCancelled` để không rò theo số task.
* `BookBinManager.resolvedBinURLs` là cache phái sinh (bookId → URL đã resolve + đã migrate legacy), không phải nguồn sự thật; `deleteBinFile` xoá entry để không giữ URL của truyện đã bị xoá.
* `ChapterTOCDiff.Plan` là giá trị bất biến tính **một lần** trên snapshot đọc từ DB, không phải state được duy trì: `.unchanged` / `.appendOnly(tailStart:)` / `.full`. Bất biến an toàn: mọi tình huống không chắc (ít hàng hơn hiện có, lệch bất kỳ field nào, chương TTS đang được bảo vệ mà TOC mới không chứa) phải trả `.full`.

## Trạng thái trình duyệt thu nhỏ, nhịp nháy và vị trí widget (1.3.244)

* `VisibleBrowserTabManager` có **một trạng thái mới hợp lệ**: `isPresented == false && isHidden == true && !tabs.isEmpty` — container đã dựng (`loadViewIfNeeded()`) và tab đã attach, nhưng **chưa bao giờ được present**. Trước 1.3.244 `isHidden == true` chỉ đạt được sau một lần present rồi thu nhỏ. `prepareContainerMinimized()` là điểm vào duy nhất của trạng thái này và tự guard `!isPresented, !isDismissing`.
* Bất biến giữ nguyên: mọi consumer đọc "đang thu nhỏ" bằng `isHidden && !tabs.isEmpty` (`VisibleBrowserPresentationReader.showReopenButton`, `BrowserFloatingWidgetWindowManager.refreshState`, `VisibleBrowserPulseMonitor.evaluate`), nên trạng thái mới tự động hợp lệ với cả ba mà không cần cờ phụ. `reopenContainer()`/`hideContainer()` không đổi ngữ nghĩa.
* `VisibleBrowserSettings.opensMinimized` là **input**, không phải state: nó chỉ được đọc tại `openContainer(initialActiveId:)`. Đổi cài đặt không hề chuyển trạng thái của trình duyệt đang mở — nó quyết định trạng thái *khởi tạo* của lần mở kế tiếp.
* `VisibleBrowserTabItem.createdAt` là dữ liệu bất biến đặt lúc tạo tab; tuổi tab vì vậy suy ra được, không phải state phải duy trì. Không có bộ đếm nào cho mỗi tab.
* `VisibleBrowserPulseMonitor.isPulsing` là **hàm của ba đại lượng**: `isHidden`, `tabs`, và `now`. Luật: `isPulsing == isHidden && !tabs.isEmpty && max(now - tab.createdAt) >= 10`. Không có trạng thái "đã từng nháy" — mở rộng trình duyệt (`isHidden = false`) đưa cờ về `false` ngay, thu nhỏ lại thì tính lại từ `createdAt` thật (nên một tab 30 s vẫn nháy ngay, không chờ thêm 10 s). Đóng tab tới khi không tab nào đủ tuổi thì cờ về `false`.
* Nhịp nháy được biểu diễn **thuần bằng `opacity` của SwiftUI** (`isDimmed` 1.0 ↔ 0.45, `repeatForever(autoreverses:)`); `alpha` của `widgetContainerView` giữ nguyên 1.0 nên `BrowserFloatingWidgetUIWindow.hitTest` (guard `alpha > 0.01`) không bao giờ đổi kết quả theo nhịp nháy.
* Vị trí widget trình duyệt vẫn là hai giá trị bền trong `UserDefaults` (`visibleBrowserReopenVerticalRatio` mặc định 1.0, `visibleBrowserReopenEdge`), y như trước — nhưng nay **không còn là `@Published` điều khiển layout**: `center` do UIKit ghi trực tiếp trong `.changed`, và `restingCenter(in:)` chỉ đọc lại hai giá trị đó khi layout lại. Hệ quả: vẽ lại SwiftUI (đổi `tabCount`, nhịp nháy) không reset vị trí, và ngón tay không chờ vòng cập nhật state.
* `isDragging` của `VisibleBrowserReopenViewModel` là cờ chặn duy nhất: `viewDidLayoutSubviews` và nhánh đổi `tabCount` đều bỏ qua layout khi nó `true`, và `handleTap` bỏ qua khi nó `true`.

## Hai cờ mới quyết định lúc nào subtree chương được dựng (1.3.242)

* `ReaderView` thêm hai `@State`: `renderedChapterIndex: Int?` (chương mà subtree nội dung đang thực sự hiển thị, set ở `onAppear` của `singleChapterScrollView`) và `skeletonHandshakeIndex: Int?` (chương mà skeleton đã xuất hiện ít nhất một frame, set ở `onAppear` của `chapterInlineLoadingView`).
* Bất biến mới: subtree nội dung của chương `N` chỉ hợp lệ khi `renderedChapterIndex == nil` (lần đầu mở), `renderedChapterIndex == N` (reload tại chỗ), hoặc `skeletonHandshakeIndex == N`. Nghĩa là **mọi lần đổi chương đều đi qua trạng thái skeleton**, kể cả khi `commitNavigation` xoá `pendingNavigationIndex` trước khi SwiftUI kịp chạy một update pass. Đây là điều kiện cấu trúc, không phải hẹn giờ — trước 1.3.242 chỉ có nhịp 32 ms bảo vệ, và log thiết bị cho thấy nhịp đó thường xuyên bị bỏ lỡ (không có dòng `[ReaderPerf] Skeleton`, `Present` cách cú bấm 1.6–3.5 s).
* Điều kiện nhánh nội dung thêm `pendingNavigationIndex == nil || pendingNavigationIndex == displayedChapterIndex`, thay cho nhánh skeleton riêng của trạng thái pending. Trạng thái "pending trùng chương đang hiển thị" (reload) vẫn giữ nội dung, không nháy skeleton.
* Hai cờ này reset theo vòng đời `@State` của `ReaderView` (mở lại Reader là `nil`), không được ghi từ `ReaderViewModel` và không tham gia quyết định điều hướng.

## Trạng thái navigation: hạ cánh hai pha, `stepChapter` biến mất (1.3.241)

* `ReaderViewModel.stepChapter(by:source:persistProgress:)` **đã xoá**. Mọi chuyển chương của Reader nay đi qua đúng một cửa ở tầng View: `ReaderView.requestChapter(at:paragraphIndex:source:persistProgress:)` (nay `internal`) → `ReaderViewModel.requestChapter(index:…)`. Bốn điểm vào (Next/Prev, danh sách chương, nhảy từ widget TTS, `ttsSync`) vì vậy có **cùng** tiền trạng thái: `isRestoringReaderPosition = true` và `paragraphTracker.removeAll()` được đặt *trước* khi phát yêu cầu, không còn đường nào bỏ qua cổng này.
* `scrollTarget` nay chuyển **hai pha** cho một lượt chuyển chương có đoạn hạ cánh sâu: `applyNavigationCommit` luôn đặt `ScrollTarget(paragraphIndex: -1, reason: .navigation)` (đầu chương), rồi `scheduleDeepLandingScroll` đặt `ScrollTarget(paragraphIndex: commit.paragraphIndex, reason: .initialRestore)` sau 0.15 s. Trạng thái trung gian "đã hiện chương, chưa tới đoạn" là hợp lệ và có thật, khác với trước 1.3.241 (neo sâu giải ngay trong layout pass dựng chương).
* Cờ `isRestoringReaderPosition` được **đặt lại `true`** ngay trước pha hai, nên nó bao trọn cả hai cú cuộn; `completeReaderPositionRestore(after: 0.25)` của mỗi cú cuộn là nơi duy nhất nhả cờ.
* Chuyển pha hai bị bỏ (không đổi trạng thái) khi generation commit đã cũ, còn `pendingNavigationIndex != nil`, hoặc `displayedChapterIndex` đã khác — tức mọi cú bấm mới đều thắng.

## Trạng thái navigation của Reader: commit RAM hoãn một turn (1.3.240)

* `ReaderLoadState` không thêm case nào, nhưng **thứ tự thời gian** đổi ở đường cache-hit: trước đây `requestChapter` set `.loading(chapterIndex:)` + `pendingNavigationIndex = N` rồi gọi `commitNavigation` **đồng bộ trong cùng turn main actor**, nên `.loading` → `.ready` và `pendingNavigationIndex` N → `nil` xảy ra trước khi SwiftUI kịp present frame nào. Từ 1.3.240 commit đó chạy trong `memoryCommitTask` (`Task { @MainActor }` + `await Task.yield()`) và guard theo `navigationGeneration`, nên tồn tại đúng một frame ở trạng thái `(pending = N, .loading)`.
* Cổng render của `singleChapterReaderView` đọc đúng trạng thái đó: nhánh mới `pending != displayedChapterIndex` → `chapterInlineLoadingView(index: pending)` đặt **trước** nhánh `cache.get(presentationIndex)?.state == .loaded`. Vì `ChapterCache` thực tế không evict (`queueRelease*` không có caller) và N+1 được prefetch, chương đích gần như luôn `.loaded`; không có nhánh này thì skeleton không bao giờ được vẽ khi Next/Prev. Reload cùng chương (`pending == displayedChapterIndex`) vẫn đi nhánh cũ nên không nháy skeleton.
* `memoryCommitTask` bị cancel ở đúng ba chỗ đang cancel `navigationWorkerTask`: đầu `requestChapter`, `failBootstrap`, `shutdown(saveProgress:)`. Bấm Next/Prev liên tiếp vì vậy chỉ commit lần cuối — generation cũ bị guard chặn.
* Cờ `isRestoringReaderPosition` hết đường kẹt: nhánh thoát sớm `guard !chapter.isPositionRestored` của `restoreReaderPositionIfNeeded` nay gọi `completeReaderPositionRestore()` trước khi return. Trước đó, một chương từng restore rồi cộng với `scrollTarget` đã tiêu thụ sẽ để cờ ở `true` hết session, làm `requestTTSScrollIfNeeded` và `updateScrollReadingProgress` (cả hai mở đầu bằng `guard !isRestoringReaderPosition`) chết im lặng.

## Next-chapter prefix cache state (1.3.234)

* `TTSNextChapterPrefixCache` giữ trạng thái phẳng, không phải máy trạng thái enum như `TTSChapterPrefetcher`: `activeKey: TTSPreparedNextChapterKey?`, `chunks: [Int: PreparedChunk]` (audio + `finalText` đã đọc), `durations: [Int: Double]`, `tasks: [Int: Task<Void, Never>]`, `taskTokens: [Int: UInt64]`, `failureStates: [Int: TTSManager.RefillFailureState]`, `nextTaskToken`/`generation: UInt64`.
* `durations` được ghi cùng lúc với `chunks` (qua `WAVEncoder.duration`) và là dữ liệu duy nhất mà watermark cached-time của NghiTTS đọc: `contiguousDuration(matching:from:)` cộng dồn chuỗi index liên tục và dừng ở khe trống đầu tiên; key không trùng trả `0`. Với Google/Ext, `WAVEncoder.duration` trả `0` cho MP3 nên trường này vô hại (không consumer nào dùng).
* Chuyển trạng thái:
  - `request(key:…)` với key khác `activeKey` → `reset()` rồi nhận key mới. Cùng key → `trim(toCapacity:)` rồi mở task cho các index còn thiếu trong `1..<min(paragraphs.count, capacity + 1)`.
  - `capacity == 0` (giữa chương với Google/Ext, hoặc chương hiện tại còn ứng viên optional-reserve với Nghi) → `trim(toCapacity: 0)` thu hồi toàn bộ, không mở task mới.
  - Nghi khi `cachedTime >= nghittsSafeCachedTimeThreshold` → **không gọi `request` nữa**, nên không thu hồi và cũng không nạp thêm: state đóng băng cho tới sự kiện kế tiếp.
  - Task xong → `finishSynthesis` ghi vào `chunks` **chỉ khi** `generation`, `activeKey` và `taskTokens[index]` còn khớp; thành công thì xóa `failureStates[index]`.
  - Lỗi → `TTSManager.evaluateRefillError(maxAttempts: 2)` quyết định `failureStates[index]`: `.blocked` (non-retryable / hết attempt / audio rỗng) khiến index bị bỏ qua ở mọi `request` tiếp theo; `.retryScheduled` chỉ tăng attempt và để lần đánh giá cửa sổ sau thử lại; `.cancelled` không đổi state.
  - `cancelPendingWork()` (pause) tăng `generation`, hủy `tasks`, **giữ** `chunks`.
  - `reset()` / `consume(matching:)` tăng `generation`, hủy `tasks`, xóa `chunks`, bỏ `activeKey`.
* Ba lớp chống ghi trễ: `generation` (toàn cục), `activeKey` (chương/cấu hình) và `taskTokens[index]` (đúng task của index). `failureStates` dùng lại kiểu `TTSManager.RefillFailureState` của `nghiRefillFailureStates` nhưng khoá theo index và có vòng đời bằng `activeKey`.
* Trạng thái này độc lập với `TTSNextChapterState`; hai bên chỉ giao nhau ở điều kiện đọc (`.synthesizingAudio`/`.audioReady`) và ở thời điểm `applyNextChapter` tiêu thụ cả hai.

## Sơ Đồ Quản Lý Trạng Thái & Sự Kiện (State Graph v4.1/v5.0)

1. **Luồng Sự Kiện Presentation Bất Đồng Bộ**:
   `Services` (`TTSManager`, `DownloadManager`)
     └── Phát event -> `AsyncStream.Continuation`
           └── `AppLaunchRootView` (`AsyncStream` Consumer)
                 └── `@State` Toast presentation trong UI root context

2. **Trạng Thái Giao Dịch Dữ Liệu Khách (Coordinator Ownership)**:
   - Client Action (UI Event) -> Khởi tạo Command DTO bất biến -> Chuyển giao cho Coordinator (`BookTransactionCoordinator` / `ExtensionTransactionCoordinator`).
   - Coordinator thực hiện fetch/validate/mutate/save trên `ModelContext` -> Trả về `Result<T, Error>`.
   - View nhận `Result`: Hiển thị thành công hoặc cập nhật `@State errorMessage` mà không bao giờ thay đổi trực tiếp đối tượng `@Model`.

3. **Máy trạng thái lỗi NghiTTS refill (1.3.147)**:
   - `idle` -> tổng hợp prefetch -> `success`: xóa failure state và tiếp tục cập nhật cửa sổ đệm.
   - Lỗi tạm thời lần đầu -> `retryScheduled(attempt: 1)`: khóa scheduler, chờ 1 giây, xác thực session/chapter/generation rồi thử lại.
   - Lỗi tạm thời lần hai hoặc lỗi không retry -> `blocked`: bỏ qua paragraph index đó trong các lần chọn prefetch tiếp theo.
   - `CancellationError`, stop, đổi session hoặc chuyển chương -> `cancelled/reset`: hủy retry task và xóa toàn bộ state liên quan, không ghi lại state từ task cũ.
<!-- GENERATED END -->
