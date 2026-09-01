---
generated_by: Antigravity
generator_version: 1.0
generated_at: 2026-08-21T10:30:00+07:00
git_commit: UNKNOWN
source_files: 230
document_version: 7
---

# Dòng chảy Dữ liệu & Cơ chế Cache (Data Flow & Caching)

Tài liệu này theo dõi chi tiết đường đi của dữ liệu qua các tầng kiến trúc (Input -> View -> ViewModel -> Manager -> Repository -> Database) và làm rõ toàn bộ các cơ chế bộ nhớ đệm (Cache) đang vận hành trong dự án FreeBook.

## Ghi chú thủ công (Human Notes)
*Ghi chú thủ công của con người.*

<!-- GENERATED START -->
## Đường trace của một lượt debug extension (1.3.302)

```text
ExtensionDebugConsoleView  (Views)
  └─ ExtensionDebugRunner.start(...)                → runId, trả về ngay
       └─ Task
            ├─ resolveScript                        khoá `script` trong plugin.json
            │                                        | custom: tìm theo TÊN FILE ở gốc rồi src/
            ├─ ExtensionDebugSession(runId, scriptKey, scriptPath, revision = sha256(source)[0..<12])
            ├─ emit runStarted
            ├─ JSExecutor(localPath:downloadUrl:debugSink: session)   ← executor MỚI mỗi run
            │    ├─ console/print/Log      → emit console
            │    ├─ exceptionHandler       → emit exception  (+ line/column/stack)
            │    ├─ prepareScript throw    → emit compileFailed
            │    ├─ cancelCurrentExecution → emit cancelled
            │    └─ _nativeSyncFetch       → emit fetchStarted / fetchFinished | fetchFailed
            ├─ verifyJSResponse            → emit responseValidated | responseError
            └─ emit runFinished

ExtensionDebugSession.emit  (đồng bộ, không blocking)
  ├─ NSLock → cấp `sequence` (đơn điệu theo runId)
  └─ Task { await hub.append(event) }
       └─ ExtensionDebugEventHub (actor): quota → ring buffer → yield mọi AsyncStream
            └─ ExtensionDebugTraceReader (@MainActor) → @Published allEvents → View
```

* **Chiều dữ liệu vẫn một chiều.** Views → Runner → JSExecutor/ExtensionManager; trace đi ngược lên **chỉ** qua `AsyncStream` của hub, không có tham chiếu Services → Views. Cùng khuôn với `TTSPresentationEventCenter`.
* **`emit` là điểm cắt đồng bộ/không đồng bộ.** Nó bị gọi từ thread đang chạy JS và từ callback `URLSession`, nên chỉ được làm hai việc: cấp số thứ tự dưới `NSLock` rồi bàn sang hub bằng `Task`. Mọi thứ đắt hơn (buffer, quota, broadcast) nằm sau ranh giới actor.
* **Redaction xảy ra ở phía *tạo* event, không ở phía gửi.** `ExtensionDebugEvent` được coi là đã sạch; nhờ vậy khi Phase 2 gắn socket thì không tồn tại đường nào để một event chưa redact lọt ra.
* **Reader giữ mọi event rồi lọc theo `focusedRunId`**, không lọc ngay ở stream: nếu lọc sớm thì những event phát ra giữa lúc bấm Run và lúc View biết `runId` sẽ mất — mà đó đúng là `runStarted` và lỗi compile.
* **`script` và `location.script` là hai thứ khác nhau**: một là *script key* (`search`) để nhóm trace, một là *path tương đối* (`src/search.js`) để client Phase 2 mở file. Không được trộn.

## `<n>` phân biệt số ghép và khoảng xấp xỉ Hán (1.3.301)

```text
walkNumeral → renderNumeral(value)
  ├─ toàn digit ASCII/full-width       → normalizeFullWidth        "45" → "45"
  ├─ approximateRange(value) != nil    → "{low} đến {high}"        "四五" → "4 đến 5"      ← MỚI
  ├─ không có ký tự bậc 十百千万…       → renderDigitwise           "二零二五" → "2025"
  └─ còn lại                           → parseChineseNumeral       "一百二十三" → "123"
```

* **Điều kiện của nhánh mới là một sự thật về chữ Hán, không phải heuristic**: tiếng Trung viết 45 là `四十五`, không bao giờ là `四五`. Nên **hai chữ số Hán trần liền nhau là idiom "từ mấy đến mấy"**, và trước 1.3.301 nó bị `renderDigitwise` ghép thành `45`.
* **Cách tính hai đầu khoảng không phụ thuộc vị trí của cặp số.** `approximateRange` thay cặp đó lần lượt bằng từng chữ số rồi đọc cả chuỗi như một số thường, nên cùng một nhánh phủ `四五` (0 bậc), `十七八` → 17…18 (bậc đứng trước), `三十四五` → 34…35, `二三十` → 20…30 và `三四百` → 300…400 (bậc đứng sau).
* **Ba cửa hẹp giữ hành vi cũ**: phải có **đúng một** dãy chữ số Hán trần, dãy phải dài **đúng hai**, và hai chữ số phải tăng liền bậc. Vì vậy `二零二五` (dãy 4), `零五` và `一〇` (không liền bậc) vẫn đi đúng đường cũ. Chuỗi digit ASCII/full-width thoát ở nhánh đầu nên `"45"` người dùng gõ tay không bao giờ bị đổi.
* **Chỉ `<n>` đổi.** `<y>/<h>/<d>` là các token *đọc từng chữ số* theo đặc tả — biến `二零二五` thành `2025` là việc của chúng — nên `renderDigitwise`/`renderHanDigits`/`renderAsciiDigits` không đụng tới.
* Phần đọc số Hán tách ra `parseChineseNumeral` trả `Int?` (`nil` khi tràn) để cả `renderNumeral` và `approximateRange` dùng chung một bản. Ngữ nghĩa cộng dồn theo *section* (`一万亿` = `100010000`) giữ nguyên theo reference.
* Đường xuống TTS không cần gì thêm: `"4 đến 5 tuổi"` đi qua `TextPreprocessor.processDigits` (`\b\d+\b`) thành `"bốn đến năm tuổi"`.

## Bản nháp rule: một dòng đi qua đúng pipeline thật (1.3.288)

```text
pattern + replacement (đang gõ)
  └─ QuickTranslationRuleRecordStore.serialize([Record])      → "pattern = replacement"
       └─ QuickTranslationRuleParser.parse                    → captureCount, issues cú pháp
            └─ QuickTranslationRuleCompiler.compile           → issues hợp đồng (hard/warning)
                 └─ parseTemplate(replacement)                → {i} nào đang được tham chiếu
                      └─ Analysis { captureCount, referenced, missing, outOfRange, issues }
                           ├─ CaptureChipsView   (chip {i}, đỏ = chưa dùng)
                           └─ DraftIssuesView    (mọi issue, sắp theo severity)
```

* **Không có nhánh validate thứ hai.** Verdict lúc gõ dùng đúng `serialize → parse → compile` mà `QuickTranslationRuleRecordStore.validRecords` dùng lúc ghi file, nên không thể có trạng thái "ở đây xanh mà lưu vẫn đỏ". Kể cả trường hợp mẫu chứa dấu `=`: định dạng file cắt ở dấu `=` **đầu tiên** nên mẫu như vậy vốn không biểu diễn được, và bản nháp hiện đúng cái sai đó ngay thay vì đợi tới lúc lưu.
* **Ngoại lệ đã biết**: `DUPLICATE_PATTERN` chỉ phát hiện được khi so với cả file, còn bản nháp chỉ có một dòng — nên trùng mẫu vẫn chỉ báo lúc lưu, và ngữ nghĩa lúc đó là *đè vế phải*, không phải lỗi.
* **`Segment` là đường dữ liệu thứ hai, thuần văn bản.** `segments(of: pattern)` cắt **văn bản nguồn** (không đi theo AST): `<…>?` là một chip token, `(`/`|`/`)`/`)?` là chip cú pháp, `\x` giữ nguyên 2 ký tự trong một chip, còn lại là từng ký tự. Cắt phẳng nên token nằm trong `(a|<n>)` vẫn chọn/sửa được, và `tokenOrdinal` khớp `captureIndex` của parser vì cả hai đánh số theo thứ tự xuất hiện từ trái sang phải.
* **`TokenSpec` là cầu hai chiều cho một token**: `tokenSpec(of:)` đọc `<names:min-max>?` (kẹp về vùng hợp lệ của parser, ép `<L>`/`<hv>` về 1...1), `syntax` ghi lại — bỏ `:spec` khi trùng mặc định `1...12`, dùng `:N` khi `min == max`. Mẫu vì vậy không phình thêm ký tự nào so với người gõ tay.

## Token số mở rộng `<h>`/`<d>` và full-width digits (1.3.287)

* **Bốn loại token số thay cho hai trạng thái digitwise `Bool`.** `Kind` của parser/compiler/matcher dùng chung `QuickTranslationRuleElement.NumeralKind`: `.chinese`/`.digitwise`/`.hanDigits`/`.asciiDigits` tương ứng `<n>/<y>/<h>/<d>`. Tập ký tự của matcher (`units(for:)`) giờ đắt riêng: `<h>` chỉ `〇零一二两兩三四五六七八九`, `<d>` chỉ `0123456789` + full-width `０..９`. Full-width (U+FF10-FF19) được **ba loại `<n>/<y>/<d>`** nhận và render về ASCII.
* **Render vẫn theo cơ chế cũ.** Matcher `walkNumeral` gọi đúng hàm render theo loại: `<n>` `renderNumeral` (số Â Rập/Hán có bậc), `<y>`/`<h>`/`<d>` digitwise. Chuỗi nguồn không bị `trim`; range UTF-16 vẫn được giữ.
* **Cấu hình token là input của rewrite, không phải output.** `QuickTranslationRuleTokenSettings` thêm 2 khoá `quickTranslateRuleTokenHanDigitsEnabled` / `quickTranslateRuleTokenAsciiDigitsEnabled` (kho mặc định bật), chữ ký `Configuration.signature` đổi độ dài khi token mới thêm nên cache cũ bị vô hiệu ngay khi cấu hình đổi. Không đổi file rule/snapshot key.

## Rule dịch: hai bộ trộn trong một lượt rewrite (1.3.274)

```text
chuỗi Trung (sau Phồn→Giản, trước punctuationMapping)
  └─ QuickTranslationRuleEngine.rewrite(text, bookId:)
       ├─ bookSnapshot   = QuickTranslationRuleBookStore.activeSnapshot(for: bookId)   scopeRank 0
       ├─ globalSnapshot = QuickTranslationRuleStore.activeSnapshot                    scopeRank 1
       ├─ disable        = QuickTranslationRuleDisableStore.snapshot(bookId:)
       ├─ collectFound(bookSnapshot, 0) + collectFound(globalSnapshot, 1)
       ├─ select(from: found)   ← MỘT lượt trên tập hợp nhất
       └─ assemble(...)         → QuickTranslationRewriteResult
```

* **Không dựng `literalIndex` gộp cho từng truyện.** Index của bộ 17k dòng là cấu trúc lớn; bộ riêng thường vài chục rule nên hai lần `collectFound` rẻ hơn nhiều, và kết quả không đổi vì `select` vẫn chạy đúng một lượt trên tập hợp nhất.
* **Thứ tự ưu tiên có 6 tiêu chí**: vị trí trái → `literalLength` dài hơn → `wildcardCapacity` hẹp hơn → match dài hơn → **`scopeRank` nhỏ hơn (riêng thắng chung)** → `sourceLine` nhỏ hơn. Tiêu chí thứ 5 là mới; bốn tiêu chí đầu và ngữ nghĩa `executeRules` của reference **không đổi**, và trong một bộ đơn lẻ `scopeRank` là hằng số nên kết quả của bộ chung giữ nguyên.
* **Tập tắt tra theo phạm vi của rule, không phải hợp phẳng** (`Snapshot.isDisabled(pattern:scopeRank:)`): rule bộ riêng chỉ chịu file tắt riêng; rule bộ chung chịu file tắt chung **hoặc** file tắt riêng của truyện đang đọc. Đây đúng là ngữ nghĩa VP riêng/VP chung: tắt ở bộ chung là tắt cho **mọi** truyện, muốn dùng lại ở một truyện thì thêm mẫu vào bộ rule riêng của truyện.
* **Chỗ dịch không truyền `bookId`** (meta/global, `Qt` bridge) chỉ thấy bộ chung. Đúng thiết kế, không phải bug.
* Memo của engine mang generation của **cả hai** snapshot: hai truyện khác nhau đã khác `bookId`, nhưng cùng một truyện sau khi sửa bộ riêng phải là khoá khác.

## Một lời gọi cho mọi invalidation khi đổi dữ liệu rule (1.3.274)

* Mọi thao tác (tắt/bật/thêm/sửa/xoá/chuyển, phạm vi nào cũng vậy) kết thúc bằng **đúng một** `TranslationManager.notifyDictionariesDidUpdate(bookId:scope: .config(bookId:))`. Không thêm tên NotificationCenter mới, không mở đường refresh thứ hai.
* Lý do đủ: `notifyDictionariesDidUpdate` → `TranslateUtils.invalidateCache(bookId:)` đã (a) gọi `QuickTranslationRuleEngine.clearCache()` ở **dòng đầu**, (b) bump `bookGenerations[bookId]` (phạm vi riêng) hoặc `globalGeneration + settingsGeneration` (phạm vi chung), (c) dọn cache tiêu đề chương — rồi post `.translationDictionariesDidUpdate`. Mọi cache key dịch đều mang các generation đó nên entry cũ thành không thể tra tới.
* Vì vậy **không** thêm `disableRevision` vào cache key hay `cacheTag`: thêm nữa chỉ làm cache của các truyện khác bị đổ oan. `revision` của hai store mới chỉ để `@Published` đẩy UI.
* Ghi file thất bại ⇒ **không** bump, **không** notify, trả lỗi lên View để `Toggle` quay về trạng thái cũ.

## Rule dịch Quick Translate: engine, màn hình quản lý và công tắc (1.3.272)

* **Một bước biến đổi mới trên trục dịch, đặt đúng giữa hai bước đã có**:

```text
raw chương → JunkFilterManager.filterRawContent → ChapterTextNormalizer
  → textForTranslation (Phồn thể → Giản thể, khi callsite yêu cầu)
  → QuickTranslationRuleEngine.rewrite        ← snapshot rule + snapshot cấu hình token
  → punctuationMapping → VietPhraseTokenizer.tokenize → 8 tầng từ điển
  → joined(separator: " ") → postProcessText
```

* **Output của rule KHÔNG phải text cuối.** Chuỗi Việt do rule sinh ra vẫn đi qua tokenizer rồi bị ghép lại bằng `joined(separator: " ")`, và `postProcessText` chỉ dọn space trước `,.?!}]>”’):】`. Vì vậy khoảng trắng trong RHS của rule **không** là bất biến — đừng thiết kế rule dựa vào việc giữ nguyên từng space.
* **Chữ Hán không khớp rule đi tiếp bằng đường cũ**: `assemble` chỉ thay đúng vùng match, phần còn lại được chép nguyên văn và được đánh dấu là đoạn passthrough trong bản đồ.
* **Cấu hình token đi cùng dữ liệu vào rewrite nhưng không làm biến đổi rule.** `UserDefaults` → `QuickTranslationRuleTokenSettings.currentConfiguration()` (đọc đúng một lần/lượt) → `rule.isEnabled(for:)` **trước** `QuickTranslationRuleMatcher.match`. `sourceTokenKinds` → compiler → `requiredTokenKinds` giữ cả nhánh group, optional và các tên trong `<a|b>`; vì vậy token bị tắt chặn cả rule, trong khi literal-only vẫn đi thẳng vào matcher. Chữ ký cấu hình có mặt trong cache engine và `store.cacheTag`, nên cache TranslateUtils/Reader/TTS không tái dùng output cũ.
* **Dòng dữ liệu ngược (output → nguồn) là dữ liệu hạng nhất, không phải suy luận**: `QuickTranslationRewriteResult.segments` mang cặp `(sourceRange, outputRange, sourceLine?)` theo UTF-16. Đoạn passthrough map theo offset tuyệt đối; đoạn rule map về **toàn bộ** match nguồn; token nằm vắt qua nhiều đoạn lấy hợp. Đây là dữ liệu duy nhất cho phép `TranslationSpan` (tra từ điển khi bôi chọn) còn đúng sau khi rule đảo thứ tự từ và đổi độ dài chuỗi.
* **Cảnh báo của compiler đọc trên AST, không đọc trên text thô của mẫu.** `LITERAL_SPACE_IN_PATTERN` chỉ tính literal ở **mức ngoài cùng và không optional** (`QuickTranslationRuleCompiler.hasBareLiteralSpace`): `( )?` là idiom "khoảng trắng tuỳ chọn" và có ở **1.023/1.177** rule của `rule-aio.txt`, nên tìm chuỗi `" "` trên `rule.pattern` sẽ sinh hơn nghìn cảnh báo rác và chôn mất cảnh báo thật. Đo lại sau khi sửa: bộ v21 **7** dòng (space trần trước `km`/`m`/`cm`… nên rule gần như không khớp), `rule-aio.txt` **0**, `Rule_new.txt` **166** — khớp đúng con số plan §6 đã chốt.

* **Dữ liệu vào của rule có bốn nguồn, đúng một chủ và đúng một file trên máy** (`applicationSupportDirectory/translate/QuickTranslateRules.txt`): tải từ HuggingFace (`datasets/raikiri1498/vietpharse/…/QuickTranslateRules.txt`, cùng dataset với VietPhrase/PhienAm), người dùng nhập file, archive `config/QuickTranslateRules.txt` khi khôi phục backup, hoặc CRUD từng rule ngay trong app. Tất cả đi qua `QuickTranslationRuleRecordStore` → parser/compiler → ghi TXT canonical → snapshot; không có đường nào nạp rule trực tiếp vào matcher, và **không có bộ rule nào bundled trong app** nên trạng thái mặc định của bản cài mới là *không có rule*. Import có **3 chế độ trộn** (`DataImportMode`): `replaceAll` lấy records hợp lệ của file nhập, còn `overwriteExisting`/`keepExisting` trộn theo khoá = mẫu bên trái dấu `=`. Dòng không parse/compile được bị bỏ qua, duplicate key lấy dòng đầu, update key cũ giữ vị trí, key mới append cuối. Chiều nào cũng kết thúc bằng đúng **một** `notifyDictionariesDidUpdate()`, trừ khôi phục backup: ở đó `importRules(notifiesObservers: false)` nhường lời cho lần phát duy nhất của `BackupRestoreWorker` ở cuối lượt.

## Luồng dữ liệu chương mới: mục lục → mốc → badge (1.3.256)

* **Một shape đầu vào, một shape đầu ra.** `Book` + `Extension` (từ `@Query`) → [`NewChapterProbe.Target`](../../Sources/Services/NewChapters/NewChapterProbe.swift#L15) (`bookId`, `title`, `detailUrl`, `host`, `ExtensionExecutionSnapshot`) — **bất biến**, `Sendable`, và là **giao diện duy nhất** giữa tầng Views và phân hệ kiểm tra: phân hệ không thấy `Book`/`Extension` nên không có đường nào đọc/ghi SwiftData từ đó. Chiều ra là [`Outcome`](../../Sources/Services/NewChapters/NewChapterProbe.swift#L23) (`record`, `newlyFound`, `failure`).
* **`[ChapterResult]` không đi xa.** `BookDetailLoader` trả `[ChapterResult]` (type của phân hệ extension, không `Sendable`); `fetchTOC` đổi ngay sang `[(name: String, url: String)]` rồi mới cho `dedupePreservingOrder`/`applyDiff` chạy, nên biên isolation chỉ bị vượt tại đúng một chỗ và phần so mốc là số học thuần trên tuple.
* **Hai mốc, hai chủ.** `seenChapterCount`/`seenLastChapterUrl` chỉ đổi khi **người dùng mở truyện** (`markSeen`); `probedChapterCount`/`probedLastChapterUrl`/`probedIsPartial` chỉ đổi khi **probe chạy**. Con số badge (`newChapterCount` + `isCountExact`) là **kết quả suy ra** từ hiệu hai mốc, không phải một bộ đếm tự cộng — nên một lượt kiểm tra lặp lại không bao giờ nhân đôi số chương mới.
* **`applyDiff` là bốn nhánh xếp theo bằng chứng giảm dần** ([#L168](../../Sources/Services/NewChapters/NewChapterProbe.swift#L168)): chưa từng có mốc ⇒ ghi mốc, báo **0**; url chương cuối trùng mốc ⇒ **0**, chính xác; tìm được mốc trong mục lục ⇒ `chapters.count - 1 - anchorIndex`, chính xác; không thấy mốc ⇒ nếu chỉ có trang cuối thì **1** + `isCountExact = false` (badge `•`), còn nếu có đủ mục lục thì `max(0, chapters.count - baseline.count)` và chỉ coi là *chính xác* khi bằng 0 — tức nguồn đổi url mà không thêm chương thì **không** báo động giả.
* **`newlyFound` khác `newChapterCount`.** Toast dùng số **vừa phát hiện trong lượt này** (`max(0, newChapterCount - previousNewCount)`), badge dùng tổng tích luỹ. Nhờ vậy lượt tự động sau 6 giờ không báo lại đúng những chương đã báo hôm qua, trong khi badge vẫn giữ đủ con số cho tới khi người dùng mở truyện.
* **Đường bền hoá**: `[NewChapterRecord]` → `NewChapterStore.save(_ batch:)` → dictionary `[bookId: record]` → `JSONEncoder` (ISO8601) → `new_chapters.json` ghi `.atomic`, **một** lượt ghi cho cả batch 20 truyện. Chiều đọc: file → `[String: NewChapterRecord]` (decode lỗi ⇒ log + `[:]`, `bookId` rỗng được điền lại từ khoá dictionary) → `@Published records` → badge dòng truyện + `.badge` tab + `LabeledContent` trong Cài Đặt.

## Luồng dữ liệu xuất truyện: một lượt chương, bốn định dạng (1.3.253)

* **Một shape đầu vào cho mọi renderer**: `Book` + lựa chọn trên `TaskOptionsSheet` → [`BookExportRequest`](../../Sources/Services/Export/BookExportRequest.swift#L1) (`format`, `bookId`, `bookTitle`, `author`, `desc`, `coverJpegData`, `translate`, `cacheOnly`, `plannedChapterCount`) — **bất biến**, `Sendable`, và là **giao diện duy nhất** giữa `DownloadManager` và 4 renderer. Renderer không thấy `Book`, `DownloadTask` hay bất kỳ type SwiftData nào, nên không có nhánh dữ liệu riêng cho định dạng nào ở phía điều phối.
* **Chương chảy đúng một lượt**: `StoredChapterSnapshot` → `ExportContentProvider.acquire` → `.content(String)` / `.skippedUncached` / `.failed`. Nhánh `.content` đi tiếp: (dịch nếu bật) → [`ExportChapterPayload`](../../Sources/Services/Export/ExportChapterPayload.swift#L1) (`ordinal`, `title`, `content`) → `renderer.append`. Chương vừa **tải** cũng chảy qua đúng ống này sau khi đã ghi `.bin` + `ChapterStore` — trước 1.3.253 bản xuất phải đọc lại từ `.bin` sau khi tải xong.
* **Ba nhánh kết quả được đếm riêng, không gộp**: `ExportContentProvider.Tally` (`cached`, `skippedUncached`, `uncachedAttempt`, `saved`, `failed`) + `renderer.writtenChapterCount` là **toàn bộ** dữ liệu mà `DownloadTaskOutcomeCalculator` cần để nói "đã xuất X/Y (thiếu M, lỗi F)". Không có chỗ nào suy ngược số chương thiếu từ kích thước file.
* **Cắt đoạn và escape là hai bước chung, đặt trước mọi phân nhánh định dạng**: `content` → [`ExportParagraphSplitter.paragraphs`](../../Sources/Services/Export/ExportParagraphSplitter.swift#L9) (cắt theo mọi loại newline, `trim`, bỏ dòng rỗng — **y hệt** `DownloadManager.formatChapter` cũ) → `[String]`; định dạng nào cần markup thì mỗi đoạn qua [`ExportTextEscaper.xml`](../../Sources/Services/Export/ExportTextEscaper.swift#L1). Nhờ vậy TXT/EPUB/FB2/MOBI thấy **cùng** danh sách đoạn cho cùng một chương, và một `\u{0}` trong nội dung nguồn không thể thành file XML sai chuẩn.
* **Hướng ghi: chảy thẳng ra đĩa, không tích cả sách trong RAM.** TXT/FB2 ghi từng chương; EPUB ghi từng entry ZIP và chỉ tích central directory; MOBI là ngoại lệ **hai pha** (text → file tạm → copy 4096 byte/record) vì `filepos` mục lục là offset byte tuyệt đối chỉ biết được sau khi toàn văn hoàn tất. Đỉnh RAM vì vậy tỉ lệ với **một chương** (một record với MOBI), không phải với cả sách.
* **Đường ra**: `ExportArtifact { fileURL, exists }` → `exportFilePath` trong `DownloadTaskModel` (dữ liệu duy nhất được bền hoá thêm — không field mới) → hai người tiêu thụ: `.exportReady` (share sheet ngay) và nút chia sẻ lại trên tracker. Tên file mang định dạng + timestamp nên hai lần xuất cùng truyện là **hai** file, không ghi đè.

## Luồng dữ liệu nhập truyện EPUB/HTML/MOBI–AZW3 (1.3.251)

* File người dùng chọn → bản copy trong `temporaryDirectory/<uuid>.<ext>` → `Data` → `BookImportFormat.detect` → **một** `ParsedBook` (`title`, `chapters`, `author`, `desc`, `coverData`, `remoteCoverUrl`, `structureNote`). `ParsedBook` là **giao diện duy nhất** giữa phân hệ nhập và tầng lưu trữ: mọi format đổ về cùng một shape nên không có nhánh ghi riêng cho format nào.
* `ParsedBook` → chuỗi ghi cũ không đổi: `AddBookToShelfCommand` (`author: parsed.author ?? "Local"`, `desc: parsed.desc ?? "Truyện nhập cục bộ từ file …"`, `coverUrl: parsed.remoteCoverUrl ?? ""`) → `BookTransactionCoordinator.addBookToShelf` → `ChapterMetadataSnapshot(url: "local://<id>/chapter/<i>")` + `TranslateUtils.translateChapterTitle` (detached) → `ChapterStore.replaceFullTOC` → mỗi chương `BookBinManager.writeChapterContent` → `(offset, length)` → `ChapterStore.upsertCachedChapter(isCached: true)`.
* Bìa có hai đường tách bạch: `coverData` (bìa nhúng trong EPUB/MOBI) → `ImageCacheManager.saveCover` → `covers/<sha256(bookId)>.jpg`, **`coverUrl` giữ rỗng** vì `BookCoverView` ưu tiên file bìa local; `remoteCoverUrl` (`<img src="http…">` của HTML) → `coverUrl` → `AsyncImage`.
* Encoding chảy theo thứ tự cố định: **override người dùng** (picker "Bảng mã") → **khai báo trong file** (`<meta charset>` của HTML, `<?xml encoding=…>` của XHTML, `codepage` trong MOBI header) → `TextEncodingDecoder.decode` auto-detect. EPUB ẩn hàng "Bảng mã" vì XHTML là UTF-8 theo chuẩn.
* Dữ liệu **không** đi ra: ảnh trong nội dung (Reader là `UITextView` plain text) và định dạng chữ đều bị loại ở bước `XhtmlTextExtractor.plainText`; chương lưu xuống `.bin` là plain text.
* Vòng đời file tạm: `<uuid>.<ext>` bị xoá ở cả 3 nhánh của tầng View (nhập xong / huỷ / lỗi); thư mục giải nén `<uuid>-epub` do `EpubBookParser` `defer` xoá ngay sau khi mọi nội dung và bìa đã vào RAM.

## Luồng diff mục lục, luồng sửa từ điển và luồng ghi file TXT (1.3.250)

* **Luồng mục lục có thêm một trạm quyết định trước khi ghi**: `ExtensionManager.toc` → `[ChapterResult]` → `tocMetadata(from:)` → `[ChapterMetadataSnapshot]` → `ChapterContentRepository.saveChapterList` → `ChapterStoreActor` → `ChapterStoreDatabase.replaceFullTOC` → `fetchOrderedTOC` (`[StoredChapterSnapshot]`) → **`ChapterTOCDiff.plan(existing:incoming:protectedTTS:bookId:)`** → `.unchanged` (dừng, không transaction) / `.appendOnly(tailStart:)` (chỉ ghi `chapters[tailStart...]`) / `.full`. `plan` là hàm **thuần**, so từng field `(index, url, title, host, titleTrans-nếu-mới-khác-rỗng)` và **không cấp phát chuỗi** — trước đây caller ở Reader phải dựng 2×N chuỗi nội suy để làm cùng việc này.
* **Chiều ngược đã đủ thông tin nên caller thôi tự diff**: `SaveTOCResult(inserted:updated:deleted:totalChapters:)` là nguồn duy nhất cho "có gì đổi không". `ReaderChapterListView+Refresh` và `BookDetailView+Extensions.reloadBookData` đọc nó thay vì đọc lại TOC. Checksum không còn chảy trong luồng này: `computeDeterministicChecksum` bị xoá (nó băm cả `id`/`isCached`/`offset`/`length` — những field mà TOC vừa fetch online **không có**, nên không bao giờ dùng lại được để diff), `totalChapters` nay đến từ `countChapters(bookId:)` = `SELECT COUNT(*)`.
* **Luồng sửa từ điển thu ngắn ở đúng một khúc**: ghi TXT (`DictionaryTextFileStore.persist`) → **`reloadCustomDictionary(isName:)`** (parse `Custom{Names,VietPhrase}.txt` → `TextDictionary` → `customNamesDict`/`customVietPhraseDict`, kèm `updateDeletedState` để dòng tombstone `word=` vào `deletedNames`/`deletedVietPhrase` cùng nhịp) → `notifyDictionariesDidUpdate` → `TranslateUtils.invalidateCache` → token dịch mới → `processAndSaveChapter` dịch lại thật. Khúc bị bỏ là `loadAllDictionaries()`: 4 file `.dat` + `ChinesePhienAmWords.txt` (hàng trăm nghìn entry) không còn chảy qua luồng "sửa một từ". Nhánh riêng truyện thì không chảy gì cả — `bookDicts.removeValue(forKey:)` và dữ liệu được nạp lại lazy từ `translate/books/<bookId>/{VietPhrase,Names}.txt` ở lần dịch kế tiếp.
* `DictionaryCache.persistAndUpdate` đưa **cả** `persist` và `loadEntries` vào cùng một `Task.detached` rồi mới đem `[(key, value)]` về; trước đây parse chạy trên actor của caller (MainActor khi gọi từ View). `importEntries` parse **một** lần và dùng lại kết quả cho cả persist và cache, thay vì ba lượt cho một lần nhập.
* **Luồng xuất TXT đổi từ "tích RAM rồi ghi một lần" sang "chảy thẳng ra đĩa"**: `BookBinManager.readChapterContent` → (dịch nếu bật) → `TxtExportFileWriter.append(_:)` → `<tên>.txt.part` → `finish()` rename thành `.txt` trong `Documents/Exports/`. Đỉnh RAM vì vậy phẳng theo chương thay vì bằng cả file; `discard()` chạy ở **mọi** nhánh huỷ/lỗi nên không có file dở dang nào ở lại. Luồng đọc `.bin` đi qua `resolvedBinURL(for:)` (cache theo bookId) nên `sha256Hex` + `validatePathSafety` + kiểm migrate legacy chỉ chảy **một** lần cho cả truyện.
* **Luồng tiến độ task**: giá trị `(progress, total)` vẫn chảy tới `DownloadTaskModel` ở **mọi** bước; chỉ `save()` bị gộp theo `taskSaveCoalesceInterval` và nhánh `@Published tasks` bị throttle ~10 lần/giây. Trạng thái cuối (`markCompleted`/`markFailed`/`markCancelled`) luôn ghi thẳng, nên đường resume/retry sau khi app bị kill vẫn đọc được tiến độ (lùi tối đa một cửa sổ coalesce).

## Luồng khôi phục một chạm + luồng thứ tự danh sách ext (1.3.247)

* **Mốc đọc là dữ liệu đi xuyên luồng, không phải phái sinh ở đích**: `BackupPayload.BookRecord.lastReadDate` → `BackupLibraryWriter.insertMissingBooks` → `AddBookToShelfCommand.lastReadDate` → `BookTransactionCoordinator.addBookToShelf` (`command.lastReadDate ?? Date()`) → `Book.lastReadDate` → `@Query(sort: \Book.lastReadDate, order: .reverse)` của Kệ sách. Trước 1.3.247 mắt cuối bị cắt: command không có field nên coordinator dập `Date()`, biến thứ tự đọc của máy nguồn thành thứ tự chèn. Luồng **chương** không liên quan và đã đúng: cả ba câu lệnh TOC `ORDER BY chapter_index ASC`, `BackupChapterRestorer` sort theo `index` trước khi ghi.
* **Luồng một chạm từ Drive**: `GoogleDriveBackupListView` → `BackupCoordinator.restoreEverythingFromDrive(_:container:)` → `GoogleDriveClient.download(file:)` (file tạm) → `LocalBackupStore.importArchive(from:)` (nhập vào `backups/`, xoá thư mục tạm bằng `defer`) → `refreshLocal()` → `Task.detached { BackupRestoreWorker.prepare(archive:) }` → `performRestore(prepared:container:options:)` với `scopes: BackupScope.defaultSelection` → `cancelPreparedRestore()`. Không nhánh nào đi qua `RestoreOptionsSheet`. Điểm cần biết khi đọc code: cả chuỗi chạy dưới **một** lượt `isBusy` vì `performRestore` không tự giữ khoá — mọi entry point công khai của coordinator đều `guard !isBusy` nên nếu gọi `runRestore` từ trong đây thì tự khoá chính mình.
* Luồng tiến độ ra UI không đổi hình dạng (`BackupProgress` qua `@Published`) nhưng nay có **hai** subscriber (`BackupHubView`, `GoogleDriveBackupListView`), cùng một dải chiều cao cố định. Toast vẫn chỉ phát ở tầng Views.
* **Luồng thứ tự danh sách ext**: `@Query var allExtensions` (không sort) → `RepositoryFilterPolicy.filterExtensions` (lọc comic → author → type → locale → query) → `sortExtensions`: `hasUpdate` → đã-cài (`!localPath.isEmpty`) → `isPinned` → `name`. `Extension.hasUpdate` đọc `remoteVersion > version` **và** `!localPath.isEmpty`, hai field mà `ExtensionTransactionCoordinator.upsertExtensions` vừa ghi ở cuối luồng đồng bộ kho — nên ngay sau "Cập nhật lại các kho", ext có bản mới nổi lên đầu mà không cần tín hiệu riêng. Sắp xếp làm trên RAM; `@Query` vẫn không mang sort/predicate chuỗi.
* **Luồng tô màu trình soạn script (đổi)**: trước đây mỗi lần gõ chảy thành `parent.text = …` → gán lại `attributedText` (mất con trỏ, `typingAttributes` cũ) và màu dựng bằng **hai lượt regex chồng nhau** theo thứ tự gọi. Nay: `textViewDidChange` → `applyHighlight(to:fontSize:)` sửa attribute **tại chỗ** trên `textStorage` (`beginEditing`/`endEditing`) → đặt lại `typingAttributes`; màu dựng một lượt qua `tokenColors(in:)` — regex `protected` (ghi chú + 3 loại chuỗi trong **một** alternation, match trái thắng) cho vùng bảo vệ, rồi number/keyword/builtin/functionCall bị loại nếu `intersectsProtected`. `updateGutterInset()` vẫn chạy sau mỗi lần gõ.

## Luồng sao lưu/khôi phục, đồng bộ ext theo lô, sửa thông tin truyện (1.3.246)

* **Luồng export**: `BackupHubView` → `BackupCoordinator.createBackup(container:scopes:)` → `BackupExportWorker.export(destination:)` ([BackupExportWorker.swift:26](../../Sources/Services/Backup/BackupExportWorker.swift#L26)) → **đúng một** `MainActor.run { BackupLibraryReader(container:).read(scopes:) }` → DTO `Sendable` → ghi `library/*.json` → mỗi sách `ChapterStore.fetchOrderedTOC(bookId:)` → `chapters/<slug>.json` → `stageContent` ([:178](../../Sources/Services/Backup/BackupExportWorker.swift#L178)) → `BackupZipArchive.stage(fileAt:)` (thử `linkItem` trước `copyItem`) → `manifest.json` ghi **cuối** → `FileManager.zipItem` → `backups/freebook-yyyyMMdd-HHmmss.fbbackup`. Nội dung chương **không bao giờ chảy qua RAM**: `.bin` đi theo đường file.
* `slug` (`b0001`, `b0002`…) là lớp trung gian bắt buộc giữa `bookId` và tên entry: `bookId` có thể chứa ký tự đường dẫn, và hàm sha256 bị cài lại độc lập ở từng owner nên không dùng làm tên entry được. `makeSlugTable` ([:98](../../Sources/Services/Backup/BackupExportWorker.swift#L98)) phủ cả `orphanDictionaryBookIds` — bookId chỉ còn từ điển riêng mà không còn trong thư viện vẫn có slug.
* **Luồng restore**: `RestoreOptionsSheet` → `BackupRestoreWorker.prepare(archive:)` ([:72](../../Sources/Services/Backup/BackupRestoreWorker.swift#L72), giải nén + decode manifest/slugs, xoá thư mục tạm nếu throw) → `restore()` ([:99](../../Sources/Services/Backup/BackupRestoreWorker.swift#L99)) theo đúng thứ tự: ext + kho → `insertMissingBooks` → TOC/nội dung từng sách → từ điển → `TranslationManager.loadAllDictionaries()` + `notifyDictionariesDidUpdate()` → `NotificationCenter.post("extensionDidUpdate")`. Toast không đi trong luồng này: `BackupCoordinator` chỉ đẩy `lastMessage`/`lastError`, `BackupHubView` mới hiển thị.
* **Nhánh quyết định offset** — chỗ dễ sai nhất của luồng dữ liệu chương ([BackupChapterRestorer.swift:39](../../Sources/Services/Backup/BackupChapterRestorer.swift#L39)): `localCount == 0` ⇒ `importFresh` ([:53](../../Sources/Services/Backup/BackupChapterRestorer.swift#L53)); ngược lại ⇒ `mergeIntoExisting` ([:119](../../Sources/Services/Backup/BackupChapterRestorer.swift#L119)).
  - `importFresh`: chỉ khi `installBinFile` ([:95](../../Sources/Services/Backup/BackupChapterRestorer.swift#L95)) copy được nguyên `content/<slug>.bin` vào chỗ chưa có file thì `keepsOffsets = true` và `offset/length/isCached` trong backup **còn hiệu lực**; sau đó `ChapterStore.importBookMigration(bookId:snapshots:statusInfo:)` ghi TOC + `is_cached/offset/length` trong **một transaction**. Không chọn nhóm `content`, hoặc `.bin` local đã tồn tại ⇒ cùng lời gọi nhưng `isCached=false, offset=0, length=0`.
  - `mergeIntoExisting`: `upsertPage` cho index còn thiếu (**chỉ metadata**), rồi với chương backup có cache mà local chưa cache: `FileHandle` đọc `length` byte tại `offset` trong `.bin` đã giải nén → `String(data:encoding:.utf8)` → `BookBinManager.writeChapterContent` (append, sinh offset **mới của máy này**) → `ChapterStore.updateCacheMetadata`. Offset từ backup **không bao giờ** được ghi vào DB ở nhánh này.
* **Luồng từ điển**: file TXT trong archive → `DictionaryTextFileStore.parseRecords` (bản local) → `mergedRecords(imported:existing:isMerge: true)` → `persist(records:to:)`. Vì `isDeleted` chính là `value.isEmpty` và tombstone nằm ngay trong TXT, luồng này mang cả "mục VP/Name đã xoá" mà không có định dạng riêng. `.dat` chung chỉ chảy vào máy khi **thiếu** file cùng tên, trừ khi người dùng tick "ghi đè từ điển chung".
* **Luồng đồng bộ ext (đổi)**: trước đây `syncExtensions` chảy tuần tự trên MainActor — mỗi ext một `URLSession.shared.data(from:)` rồi một `context.save()` riêng, và vì `allExtensions` là `@Query` nên mỗi save còn kéo view render lại (kho 60 ext ⇒ 60 request + 60 transaction). Nay: `allExtensions` → snapshot `[packageId: localPath]` (chụp một lần trên MainActor) → `ExtensionSyncCommandBuilder.build` ([:66](../../Sources/Services/Extensions/Manager/ExtensionSyncCommandBuilder.swift#L66)) chạy `withTaskGroup` cửa sổ trượt 6 lượt **ngoài main** ([:75](../../Sources/Services/Extensions/Manager/ExtensionSyncCommandBuilder.swift#L75), timeout 10 s/request) → `[UpsertExtensionCommand]` **giữ đúng thứ tự input** → `ExtensionTransactionCoordinator.upsertExtensions` → **một** `save()`. Thứ tự fallback dữ liệu mỗi ext không đổi: `plugin.json` local → `plugin.json` remote → hàng registry → mặc định (`locale "vi_VN"`, `ExtensionType.novel`, `version 1`).
* **Luồng sửa thông tin truyện**: `BookInfoEditView` → (ảnh trong máy) `PhotosPicker` → `Data` → `ImageCacheManager.saveCover(data:for:)` (downscale ≤ 1024 px, JPEG 0.85, ghi `covers/<sha256(bookId)>.jpg`); (URL mới) `ImageCacheManager.deleteCover(for:)` để `BookCoverView` tự tải lại → `BookTransactionCoordinator.updateBookInfo(command:in:)` → `title/author/coverUrl` + **tính lại** `titleTrans`/`authorTrans` → `save()`. `Result` được xử lý ở View nên không có nhánh nào bỏ lỗi im lặng.

## Luồng cài đặt mở thu nhỏ và luồng mở lại container (1.3.245)

* **Cờ `opensMinimized` nay được đọc ở ba điểm, không phải một.** Ngoài `openContainer(initialActiveId:)` (1.3.244), `addTab` đọc nó ở **cả hai** nhánh có thể mở container: nhánh tab mới khi đang thu nhỏ (đã có từ 1.3.244) và nhánh **tab ID trùng** (mới ở 1.3.245). Mục 1.3.244 bên dưới nói "đọc một lần mỗi lần mở tại `openContainer`" — điều đó không còn đủ để mô tả luồng.
* Luồng thật của `Engine.newVisibleBrowser()` + `launch(url)` khi cờ **bật**: `_nativeBrowserNewVisible` → `VisibleWebViewLoader(id:title:)` → `presentUIIfNeeded()` → `addTab` (ID mới) → `openContainer` → `prepareContainerMinimized()` (`isHidden = true`, `isPresented = false`, container `loadViewIfNeeded()` nhưng không present) → `_nativeBrowserLaunchVisible` → `loader.load(url:…)` → `presentUIIfNeeded()` **lần hai** → `addTab` (ID trùng) → `activateTab(id:)` **và dừng ở đó**. Trước 1.3.245 lượt thứ hai này chảy tiếp vào `selectTab` → `reopenContainer()`, nên dữ liệu cài đặt bị vô hiệu ngay ở bước cuối.
* `activateTab(id:)` là đường lập trình duy nhất ghi `activeTabId`; nó **không** đọc `opensMinimized` và không đổi `isHidden`/`isPresented` — cờ chỉ được hỏi ở caller. Nhờ vậy cùng một hàm dùng được cho cả hai trạng thái cài đặt.
* Luồng nạp trang **không** đi qua trạng thái present: `load`/`loadAsync` gọi `webView.load(request)` ngay sau `presentUIIfNeeded()` ([VisibleWebViewLoader.swift:111](../../Sources/Services/Extensions/Engine/VisibleWebViewLoader.swift#L111), [:150](../../Sources/Services/Extensions/Engine/VisibleWebViewLoader.swift#L150)), nên tab vẫn nạp khi container chưa bao giờ được present. Chưa xác minh runtime cho các trang cần tương tác thật (xem `10_risk_report.md`).
* Luồng mở lại container: cử chỉ (tap widget / accessibility action / pill tab) → `reopenContainer()` → `findTopViewController()` (chỉ window level `.normal`) → `navigationController(wrapping:)` → `present` → `notifyStateChanged()` → hẹn `verifyReopenPresented(nav)`. Nếu 1.2 s sau `nav.presentingViewController == nil` thì trạng thái chảy **ngược** về `isHidden = true` + `navController = nil` và widget hiện lại.
* Luồng màu nháy: `VisibleBrowserPulseMonitor.isPulsing` → `isPulseBright` → `pulseLevel` (0.4 ↔ 1.0) → `Color(red:green:blue:)` đặc. Không có giá trị nào chảy vào `opacity`/alpha, nên `hitTest` của window widget không phụ thuộc nhịp nháy.

## Luồng copy từ điển và luồng cài đặt mở thu nhỏ (1.3.244)

* **Ba tầng từ điển, chỉ hai tầng ghi được.** Dựng sẵn: `translateDirectory/VietPhrase.dat` + `Names.dat` (DoubleArrayTrie, nạp lúc khởi động, **không có đường ghi nào**). Chung custom: `translateDirectory/Custom<VietPhrase|Names>.txt`. Riêng: `translateDirectory/books/<bookId>/<VietPhrase|Names>.txt`. Cả hai tầng custom là TXT `key=value` do `DictionaryTextFileStore` đọc/ghi (`parseRecords`, `persist`, `loadEntries`, `mergedRecords`, `normalizeMeaning`); thứ tự ưu tiên khi tra là riêng > chung custom > dựng sẵn, và bản ghi giá trị rỗng trong TXT là "tombstone" che entry dựng sẵn.
* Luồng copy **Chung → Riêng**: `DictEntry(key, value)` (đọc từ `Custom*.txt`) → `DictionaryEntryTransferAction.copy` → `TranslationManager.saveCustomEntry(word:meaning:isName:bookId: <bookId màn Từ điển đang mở>)` → `parseRecords(books/<bookId>/*.txt)` → `records.removeAll { $0.key == cleanWord }` → `insert(at: 0)` → `persist` → `bookDicts.removeValue(forKey:)` → `loadAllDictionaries()` → `notifyDictionariesDidUpdate(scope: .term(...))`. File chung **không được mở để ghi** trên đường này.
* Luồng copy **Riêng → Chung**: `DictEntry` (đọc từ `books/<bookId>/*.txt`) → `DictionaryCache.upsertEntry(key:value:type:)` → `currentRecords` từ `Custom*.txt` → `removeAll` key trùng → `insert(at: 0)` → `persist` → cập nhật `@Published` entries → `loadAllDictionaries()` → `notifyDictionariesDidUpdate(bookId: nil)`. File riêng và hai `.dat` **không được mở để ghi**.
* Ba luật ghi là **hệ quả trực tiếp của `removeAll` + `insert(at: 0)`**, không phải nhánh `if` phải bảo trì: key chưa có trong custom ⇒ tạo mới; key đã có ⇒ ghi đè trọn giá trị (không trùng lặp, không gộp, không bỏ qua) — `天才 = thiên tài` bị `天才 = thiên tài tuyệt thế` thay hẳn; key chỉ có ở dựng sẵn ⇒ TXT nhận bản ghi mới đóng vai override, `.dat` giữ nguyên nên `天道 = Thiên Đạo` vẫn còn trong dựng sẵn còn custom mang `天道 = thiên đạo của thế giới này`. Nguồn không bị đọc-để-xoá ở bất kỳ nhánh nào — đây là **copy**, không phải move.
* `normalizeMeaning` là điểm chuẩn hoá duy nhất trên cả hai đường (được gọi bên trong hai API ghi), nên giá trị copy sang đích giống hệt giá trị người dùng thấy ở nguồn.
* Luồng ngữ cảnh sách: `BookDictionaryView` → `DictionaryHubView(bookId:bookName:)` → `DictionaryListView(type:bookId:contextBookId:)`. Hai link chung truyền `bookId: nil, contextBookId: bookId`; hai link riêng truyền `bookId: bookId` như cũ. `transferContextBookId = bookId ?? contextBookId` ⇒ đích riêng **luôn** là sách của màn Từ điển đang mở; không có nguồn dữ liệu nào khác (không TTS, không "sách mở gần nhất", không picker) chảy vào tham số `bookId` của `saveCustomEntry`.
* Luồng lọc truyện đích: `@Query`/`loadBooks()` → `books: [Book]` → `filteredBooks` = `ShelfBookSearchMatcher.matches(query:title:titleTrans:author:authorTrans:)` → `List`. Dữ liệu chọn đích (`Book` được chạm → `dictionaryModeDialog` → callback) đi đúng đường cũ; bộ lọc chỉ thu hẹp tập hiển thị.
* Luồng cài đặt mở thu nhỏ: `Toggle` (`@AppStorage(VisibleBrowserSettings.openMinimizedKey)`) → `UserDefaults.standard["openVisibleBrowserMinimized"]` → `VisibleBrowserSettings.opensMinimized` → đọc **một lần mỗi lần mở** tại `VisibleBrowserTabManager.openContainer(initialActiveId:)`. Không có bản sao cờ này ở nơi khác, và nó không chảy vào bất kỳ tab/loader nào.
* Luồng tuổi tab: `VisibleBrowserTabItem.createdAt` (đặt lúc tạo) → `VisibleBrowserPulseMonitor.evaluate()` tính `max(now - createdAt)` → `isPulsing` → `opacity`. Không dữ liệu nào được lưu bền cho việc nháy.
* Luồng vị trí widget trình duyệt: `UIPanGestureRecognizer.translation` → `widgetContainerView.center` (ghi trực tiếp, không qua state) → khi nhả: `FloatingWidgetGeometry.nearestEdge/clampedCenterY` → `verticalRatio` + `edgeDirection` → `UserDefaults`; chiều đọc ngược lại chỉ xảy ra ở `restingCenter(in:)`.

## All-source novel-search data flow (1.3.225)

* Caller-provided `[Extension]` → `SearchView.searchableExtensions` removes `type == "tts"` → parallel extension search → per-source UI state/results. The filtered collection is reused by the `Xem thêm` destination; no TTS extension reaches `ExtensionManager.search` through the all-source path.

## Local TXT title translation and search data flow (1.3.224)

* `ParsedBook.chapters` → detached `TranslateUtils.translateChapterTitle` + metadata map → `ChapterMetadataSnapshot.title/titleTrans` → `ChapterStore.replaceFullTOC` → SQLite `chapter_metadata.title/title_trans`. Cache offset/length updates reuse the same snapshot and do not discard `titleTrans`.
* Local chapter query → one `%query%` pattern bound to both stored title columns → `StoredChapterSnapshot` results → presentation chooses the row title according to `isTranslationEnabled`. No import-time or startup backfill is performed for older local books.

## Sơ Đồ Luồng Dữ Liệu (Data Flow v4.1/v5.0)

1. **Luồng Dữ Liệu Giao Dịch Lưu Trữ**:
   `SwiftUI View` -> (Tạo `Command DTO`) -> `Transaction Coordinator` -> `SwiftData ModelContext` -> `Persistent Store`
   - Dataflow hoàn toàn một chiều và bất biến ở ranh giới View.

2. **Luồng Thực Thi Tiện Ích Bóc Tách Cách Lý**:
   `BookDetailView` / `ReaderView` -> `ExtensionExecutionSnapshot` -> `JSExecutor.runAsync` -> `VBook JS Engine` -> `DTO Results`

3. **Luồng Tải Trang & Tìm Kiếm Chương Nền**:
   `ReaderViewModel` -> `BackgroundPagingWorker` / `BackgroundSearchWorker` -> `ChapterStore` -> `ChapterRowItem` / `SearchChapterDTO` -> `@Published` UI State

4. **Luồng dữ liệu NghiTTS an toàn khi chuyển chương (1.3.147)**:
   `paragraph.text` -> replacements -> `TextPreprocessor` -> kiểm tra speakable
   - Speakable -> Piper ONNX -> PCM/WAV -> `preloadedData[index]`.
   - Unspeakable -> silence samples -> WAV hoặc một terminal streaming payload -> cache/playback như audio bình thường.
   - Failure metadata chỉ lưu khóa định danh session/chapter/paragraph, số attempt và cờ block; không lưu nội dung văn bản người dùng trong log.
<!-- GENERATED END -->
