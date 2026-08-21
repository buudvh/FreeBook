# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> File này và `AGENTS.md` ở thư mục gốc là **cùng một nội dung**, chỉ khác 3 dòng đầu (một bản cho Claude Code, một bản cho Codex). Sửa file này thì mirror sang `AGENTS.md`.

## Bắt buộc đọc trước khi sửa code

Repo này có quy trình AI riêng, **ưu tiên cao hơn hướng dẫn mặc định**:

1. `.agents/AGENTS.md` — workflow 8 bước bắt buộc cho mọi AI assistant.
2. `Docs/CodeGraph/00_index.md` — mục lục hệ thống tài liệu sống (16 tài liệu, phủ 218 file Swift).
3. `Docs/CodeGraph/rules.md` — quy chuẩn kỹ thuật + checklist tự kiểm tra.

**Thứ tự thẩm quyền khi xung đột**: `rules.md` > Source Code > `Docs/CodeGraph/*` > tài liệu khác. Nếu không đủ bằng chứng để phân biệt sai lệch là chủ ý hay bug, phải đánh dấu `UNKNOWN` và hỏi người dùng — không tự suy đoán. **Nhưng đọc mục "Bẫy đã xác minh & sai lệch tài liệu" ở cuối file trước**: `rules.md` có chỗ đã cũ hơn code, đừng sửa code chỉ để khớp nó.

Sau khi sửa code phải: cập nhật tài liệu CodeGraph bị ảnh hưởng (chỉ trong vùng `<!-- GENERATED START -->` … `<!-- GENERATED END -->`, tuyệt đối không đụng nội dung ngoài vùng này), cập nhật `manifest.json` + `CHANGELOG.md`, chạy validator, và **kết thúc response bằng một trong hai cụm**: `"CodeGraph updated."` hoặc `"No CodeGraph update required."`

`CHANGELOG.md` đánh version `[1.3.NNN] - YYYY-MM-DD` (tăng NNN mỗi thay đổi); tiêu đề entry **trùng với subject của git commit** tương ứng — giữ đúng quy ước này.

## Commands

Dự án là app iOS, dùng **XcodeGen** — `.xcodeproj` không commit mà sinh từ `project.yml`.

```bash
# Sinh FreeBook.xcodeproj (chạy lại mỗi khi thêm/xoá/đổi tên file Swift)
xcodegen generate

# Build
xcodebuild build -project FreeBook.xcodeproj -scheme FreeBook \
  -destination 'platform=iOS Simulator,name=iPhone 15'

# Chạy toàn bộ test (target FreeBookTests, 20 file)
xcodebuild test -project FreeBook.xcodeproj -scheme FreeBook \
  -destination 'platform=iOS Simulator,name=iPhone 15'

# Một test class / một test case
xcodebuild test ... -only-testing:FreeBookTests/BookIdUtilsTests
xcodebuild test ... -only-testing:FreeBookTests/BookIdUtilsTests/testMake_withEmptyInputs_returnsEmptyString
```

Hai script Python là cổng kiểm tra chạy được **mọi nền tảng**, kể cả Windows — luôn chạy chúng dù không build được:

```bash
python Docs/CodeGraph/validate_links.py                  # read-only, phải PASS 100%
python Docs/CodeGraph/validate_links.py --update-hashes   # sau khi sửa source/vùng GENERATED, rồi chạy lại read-only
python Scripts/check_architecture.py                      # gate kiến trúc, exit 0 = pass
```

**Lưu ý môi trường**: build chỉ chạy được trên macOS. Repo hay được mở trên Windows — khi đó không build/test tại chỗ được; phải nói rõ điều đó thay vì báo "đã test".

**CI không phải test gate.** `.github/workflows/build-ipa.yml` chỉ `xcodegen generate` → `xcodebuild archive` (unsigned) → đóng gói IPA + nhồi `espeak-ng-data` → gửi Telegram. Nó **không chạy unit test, không chạy `validate_links.py`, không chạy `check_architecture.py`**, và chỉ trigger khi đổi `Sources/**` hoặc `project.yml`. Nghĩa là CI xanh = *biên dịch được*, không phải *đúng*.

`GOOGLE_CLOUD_TTS_API_KEY` đi từ GitHub secret → build setting → `Info.plist` (`project.yml` khai `GOOGLE_CLOUD_TTS_API_KEY: "$(GOOGLE_CLOUD_TTS_API_KEY)"`, workflow còn `plutil -replace` vào IPA). Build local không có key thì Google TTS im lặng không hoạt động — không phải bug.

Target đặt `CODE_SIGNING_ALLOWED: NO`. Deployment target iOS 17.0. Dependencies (SwiftSoup, ZIPFoundation, ONNX Runtime, espeak-ng-spm) khai SPM trong `project.yml`.

## Kỷ luật kiến trúc (có script cưỡng chế)

`Scripts/check_architecture.py` quét `Sources/` và enforce 5 luật:

| Luật | Nội dung |
|---|---|
| `FILE_SIZE_LIMIT` / `NEW_FILE_TOO_LARGE` | file Swift mới ≤ **400 dòng vật lý**; file legacy dùng baseline riêng và **chỉ được giảm** |
| `MULTI_PRIMARY_TYPES` | đúng **1** type chính (class/struct/enum/actor) ở top level mỗi file |
| `VIEW_SWIFTDATA_MUTATION` | `Sources/Views/**` không được `modelContext.insert/delete/save`; 6 view lớn còn bị cấm gán trực tiếp thuộc tính `@Model` và cấm bỏ qua `Result` của coordinator |
| `SERVICE_TOAST_COUPLING` | `Sources/Services/**` không được gọi `ToastManager.shared` |
| `SERVICE_SWIFTUI_IMPORT` | `Sources/Services/**` không được `import SwiftUI` (trừ `*WebViewLoader.swift`) |

Miễn trừ khai trong `Scripts/architecture_allowlist.json` (`schema_version: 2`, fail-closed). Mỗi entry có `expiresAt` — **script FAIL nếu entry hết hạn**; 88 entry hiện tại đều hết hạn `2026-12-31`. Chỉ có miễn trừ cho `FILE_SIZE_LIMIT` và `MULTI_PRIMARY_TYPES`; hai luật View-SwiftData và Service-Toast không có ngoại lệ nào.

**Script hiện đang đỏ** (baseline đã trôi so với code): 30 violation trên cây sạch. Vì vậy chạy nó *trước* khi sửa, chạy lại *sau*, và chỉ chịu trách nhiệm cho violation mới do mình gây ra. Đừng "sửa cho xanh" bằng cách nới baseline nếu người dùng không yêu cầu.

**Và `[PASS]` của script không phải bằng chứng.** Hàm `strip_comments_and_strings` (`check_architecture.py:53-60`) dùng regex `"([^"\\]|\\.)*"` để xoá string literal, nhưng regex này ghép sai dấu nháy khi gặp string interpolation Swift nên **ăn cả code thật**. Kết quả: `ShelfView.swift:757` và `BookDetailView.swift:239` đều có `try? modelContext.save()` thật mà script **không phát hiện**. Vẫn phải tự đọc code, đừng tin mỗi exit code.

## Architecture

`Sources/` có 5 tầng: `App` (chỉ `FreeBookApp.swift`) / `Common` / `Models` / `Services` / `Views`. Chiều phụ thuộc: Views → ViewModel/Coordinator → Services/Repositories → Models. 218 file Swift.

### Bootstrap & lưu trữ

Khởi động chia làm **hai chỗ**, đây là bẫy cho người mới:

- `Sources/App/FreeBookApp.swift` — `ModelContainer` trỏ URL tường minh `applicationSupportDirectory/library.db` (không phải mặc định của SwiftData), schema đúng **5** `@Model`: `Repository`, `Extension`, `Book`, `Chapter`, `DownloadTaskModel`. Không có `VersionedSchema`/`SchemaMigrationPlan` — chỉ có lightweight migration ngầm, nên đổi shape `@Model` là việc nguy hiểm. `AppLaunchRootView` **chặn toàn bộ app** sau `AppLoadingView` cho tới khi `TranslationManager.shared.isInitialized`; cờ này set trong `defer` nên bật `true` **kể cả khi nạp từ điển thất bại**. Sau đó: drain hai retry queue của `BookStorageManager`, bơm `ModelContainer` vào `TTSFloatingWidgetWindowManager`, chạy `BookTitleTranslationMigrator.runIfNeeded`, và subscribe hai `AsyncStream` toast.
- `Sources/Views/MainTabView.swift` — nơi thật sự gọi `DownloadManager.shared.initialize(container:)` và `TTSManager.shared.initialize(container:)`, cộng flush khi `scenePhase` vào background (`TTSManager.checkpointForBackground()`, `ReadingProgressStore.flushAll()`, `ChapterContentRepository.flushAll()`). `MainTabView` chỉ mount **sau** khi cổng từ điển mở.

**`ChapterStoreConfiguration.enableSwiftDataTOCWrite = false`** — mục lục chương **không** nằm ở bảng SwiftData `Chapter` mà ở `chapters/chapter_store.sqlite` (raw sqlite3, actor `ChapterStore`). Đọc `Book.chapters` trong production sẽ thấy rỗng. Code branch theo cờ này ở `ReaderViewModel`, `ReadingProgressStore`, `BookDetailView`.

Mọi thứ nằm dưới `applicationSupportDirectory` (ngoại lệ duy nhất: `Documents/Exports/` cho export TXT): `library.db`, `chapters/chapter_store.sqlite`, `books/<sha256(bookId)>.bin` (append-only, không compaction — ghi lại chương làm file phình mãi, chỉ xoá cả truyện mới thu hồi), `covers/<sha256(bookId)>.jpg`, `extensions/<packageId>/`, `translate/`, `FreeBook/TTS/`, `app_logs.txt`. Hàm băm SHA-256 và `validatePathSafety(for:)` bị **cài lại độc lập ở từng owner** (`BookBinManager`, `ImageCacheManager`, `BookStorageManager`, `ChapterStorePath`) — sửa một chỗ không lan sang chỗ khác.

### Trục dọc quan trọng nhất: normalize → paragraph → chunk → highlight

Đây là nơi tập trung phần lớn độ phức tạp và cũng là nguồn bug hay gặp:

```
ChapterContentRepository            memory (12 entry/12 MiB) → SwiftData → extension fetch
  └─ ChapterTextNormalizer          nguồn DUY NHẤT chuẩn hoá newline, bỏ dòng trống,
     normalize / normalizeProcessedContent   gán line ID, tính NSRange UTF-16
       └─ NormalizedChapterText { content, lines: [ChapterTextLine] }
            └─ ChapterDocument      tạo MỘT lần, Reader và TTS cùng dùng
                 ├─ Reader: ReaderViewModel+Translation → [ParagraphItem]
                 │           (original + translated + translationSpans; title id = -1)
                 └─ TTS:    TTSBackgroundProcessor → TTSParagraphBuilder → [TTSParagraph]
                             (chunk theo dấu câu, giữ parent line ID)
```

`normalize()` chạy `JunkFilterManager.shared.filterRawContent` trước; `normalizeProcessedContent()` thì **không** lọc rác lần hai — dùng cho chuỗi đã qua xử lý/dịch.

**Bất biến bắt buộc**:

- Chỉ `ChapterTextNormalizer` được chuẩn hoá text chương. Reader/TTS builder tiêu thụ dòng đã normalize, **không tự tách lại hay đánh số lại**.
- **`ChapterTextLine.id` là chỉ số dòng thô, tính cả dòng trống** (`id: originalLineIndex`, `ChapterTextNormalizer.swift:40`), trong khi `content` chỉ join dòng không rỗng. Nên paragraph ID **thưa và không phải array index** — `"Một\n\nHai"` cho ids `[0, 2]`. Luôn tra theo `id`, đừng bao giờ dùng làm offset. `ParagraphItem.id` và `TTSParagraph.paragraphIndex` thừa hưởng đúng tính chất này.
- Hệ quả: `ChapterTextLine.utf16Range` tính trên chuỗi **trước khi lọc dòng trống** (`location += length + 1` chạy qua mọi component), nên nó **không** index được vào `NormalizedChapterText.content` khi chương có dòng trống. Đừng dùng nó để cắt `content`.
- Mọi offset trao đổi với UIKit là `NSRange` ngữ nghĩa **UTF-16**, không phải `String.Index`.
- TTS chunk có thể cắt một dòng nhưng phải giữ `ChapterTextLine.id` của dòng cha (`TTSParagraph.paragraphIndex`). Chunk tiêu đề chương dùng `paragraphIndex = -1` (khớp `ParagraphItem.id = -1`).
- Khi TTS đang phát, **TTS sở hữu tiến độ đọc**; `ReadingProgressStore` loại bỏ snapshot `.reader` khi sách đã bị `.tts` claim.

**Hệ toạ độ highlight — đọc kỹ, tài liệu cũ nói ngược:**

`TTSParagraph.range` là offset UTF-16 **trên chuỗi đang được hiển thị** (`TTSLineEntry.translatedText` — tức bản dịch khi bật VietPhrase, bản gốc khi tắt), và **tương đối với dòng cha**, không phải tuyệt đối theo chương. `TTSParagraph.sourceRange` mới là range ánh xạ về text gốc.

Lý do: `TTSBackgroundProcessor.processChapter` dịch **từng dòng trước**, rồi `reconstructContentPreservingLineIDs` → `normalizeProcessedContent`, nên `normalizedContent` của TTS và `ParagraphItem` của Reader nằm cùng một hệ toạ độ. Vì vậy `ReaderView` truyền `ttsState.snapshot.highlightRange` **thẳng** xuống `ParagraphCardView` → `ReaderTextView` không ánh xạ gì (guard theo `playingBookId`, `playingChapterIndex`, `currentParentParagraphIndex`). Hàm `ReaderSelectionMapper.mapHighlight` đã bị **xoá** ở 1.3.81 — đừng gọi lại nó.

`ReaderSelectionMapper` giờ chỉ còn chiều ngược cho *selection* của người dùng: `mapSelection(_:in:isTranslationEnabled:bookId:)` map từ chuỗi dịch về text gốc để tra từ điển, ưu tiên `translationSpans`, fallback heuristic câu/token khi span rỗng hoặc không phủ hết.

### Reader là bridge UIKit, đừng "đơn giản hoá" nó

`ReaderTextView` (`UIViewRepresentable` → `AutoSizingTextView : ReaderUITextView : UITextView`) có ba quyết định cố ý dễ bị coi là code cũ:

- Khởi tạo `AutoSizingTextView(usingTextLayoutManager: false)` (`ReaderTextView.swift:81`) — bắt buộc dùng TextKit 1, vì code cần `layoutManager.characterIndex(for:in:fractionOfDistanceBetweenInsertionPoints:)` (:209) để đổi điểm chạm thành offset ký tự. Bật TextKit 2 là mất API này.
- `ReaderUITextView.addInteraction` **chặn** `UITextInteraction(.nonEditable)` và `UIEditMenuInteraction` (:372-386) để dập menu Speak/Look Up/Share của hệ thống, nhường chỗ cho `FloatingSelectionMenu`.
- `updateUIView` (:108-230) diff tay text/font/theme/highlight; khi chỉ đổi highlight thì chỉ sửa attribute background trên `textStorage` thay vì gán lại text. Thay bằng gán thẳng là giật và mất selection.

### TTS

`TTSManager` (file lớn nhất repo, ~4100 dòng) phân nhánh theo biến `tool` — **4 đường tổng hợp**, không phải 3:

| `tool` | Engine | Vị trí |
|---|---|---|
| `nghitts` | Piper offline chạy ONNX Runtime | `Services/TTS/NghiTTS/` |
| `system` | AVSpeechSynthesizer native | `Services/TTS/Siri/` |
| `google` | Google Cloud TTS REST | `Services/TTS/Google/` |
| *(mọi giá trị khác)* | Extension JavaScript tự định nghĩa | `Services/TTS/Ext/` |

Text đi qua `Preprocessing/` (đọc số tiếng Việt, chuyển tự Anh/Nhật, luật regex, từ điển thay thế) trước khi tổng hợp. Kết quả sau thay thế phải khác rỗng mới được đưa vào engine — chuỗi rỗng phải thành WAV/PCM im lặng hợp lệ, không bao giờ đẩy string rỗng vào ONNX/eSpeak.

Giới hạn cần nhớ:

- Cache PCM `preloadedWavs` chỉ giữ cửa sổ trượt `[N, N+1]` — không dọn sẽ OOM. Callback audio ngầm phải `[weak self]`.
- `NghiSynthesisPolicy` là nguồn duy nhất cho watermark/cooldown/thermal: `defaultSafeCachedTimeThreshold = 8.0`s, dải `4.0...20.0` (UserDefaults `nghittsSafeCachedTimeSeconds`), `maxOptionalReserveItems = 2`. Đừng nhân bản các hằng này sang manager/prefetcher.
- ONNX/XNNPACK cố định **1 worker** — cố ý, không phải thiếu tối ưu; đừng scale theo số core.
- Chỉ **1** operation tổng hợp chạy tại một thời điểm; `PiperSynthesisCoordinator` xếp hàng theo 4 mức ưu tiên.
- **Retry thuộc về đúng một tầng**: Remote (Google/Ext) retry tối đa 2 lần *bên trong* `RemoteTTSSynthesisCoordinator` — `TTSManager` **không** được bọc thêm vòng retry. Ngược lại refill của NghiTTS do `TTSManager` sở hữu (2 lần, cooldown 1s).
- Không dùng `AVAudioEngine` node-streaming cho NghiTTS; đường phát là `AVAudioPlayer` double-buffering qua `NghiAudioPlayerQueue`.
- `ChapterContentRepository` giữ cache chia sẻ tối đa **12 entry / 12 MiB** (`maxMemoryEntryCount`, `maxMemoryCost`). Document vượt budget vẫn trả về cho caller, chỉ là không được cache.

### Dịch thuật VietPhrase

`TranslateUtils` tra từ điển và dựng `TranslatedTextResult { text, spans }`. `buildTranslationSpans` dò từng token dịch trong chuỗi kết quả; nếu **một** token không tìm thấy thì trả `[]` — mọi code tiêu thụ span phải xử lý được mảng rỗng.

### Extension JavaScript (VBook)

Entrypoint mọi file JS (`search.js`, `detail.js`, `toc.js`, `chap.js`, `genre.js`, `home.js`) là hàm `execute(...)`, gọi qua `runAsync`. Script nằm ở gốc extension hoặc trong `src/`. Manifest là `plugin.json`.

**Kiến trúc bridge cần hiểu trước khi thêm API JS**: `JSExecutor` không expose Swift trực tiếp cho script. Nó cài các block Swift tên `_nativeXxx` (`_nativeSyncFetch`, `_nativeBrowserLaunch`, `_nativeQtTranslate`, `_nativeStorageGet`…) rồi `evaluateScript` các gói polyfill JS (`responseBootstrap`, `fetchBootstrap`, `engineBootstrap`, `qtBootstrap`, `storageBootstrap`, `userAgentBootstrap`, `scriptBootstrap`) dựng nên API mà extension thấy: `Html`, `Engine`, `Response`, `fetch`, `Qt`, `Crypto`, `Script`, `UserAgent`, `localStorage`, `cacheStorage`, `localConfig`, `localCookie`, `console`/`Console`/`print`/`Log`, `toast`, `load`, `atob`/`btoa`. Thêm một API JS = thêm cả block `_native*` **và** wrapper trong bootstrap tương ứng. Đừng phá tương thích ngược nếu không được yêu cầu.

Mỗi tác vụ bóc tách tạo `JSExecutor` mới rồi giải phóng — **không** dùng executor dùng chung (`sharedExecutor` là anti-pattern có tên trong `rules.md`). Ngoại lệ duy nhất: `ExtTTSRuntime` actor được giữ executor lâu dài. `DownloadManager` dùng đúng một `BookDownloadWorker` actor cho mỗi truyện, tuần tự và cancel được.

Có skill riêng cho việc này: `.agents/skills/vbook_helper/SKILL.md` (mẫu `plugin.json` + mẫu từng script).

## Ràng buộc runtime cần nhớ

- **Logging**: chỉ `AppLogger.shared.log(...)`. File ghi ở `applicationSupportDirectory/app_logs.txt` (**không** phải `Documents`), tự xoá khi vượt 5 MB. `AppLogger.init` **set `isLoggingEnabled = false` mỗi lần khởi chạy** (`AppLogger.swift:50`) — thêm log mà không thấy gì thì là do đây, phải bật lại trong Settings. App chạy thật qua LiveContainer trên máy iOS vật lý nên không đính được debugger; log file là kênh duy nhất. Không log secret hay full payload chương. (`AppLogger.log` tự gọi `print` bên trong — luật "không `print`" là không gọi trực tiếp ở nơi khác.)
- **SwiftData**: không viết predicate lọc chuỗi trong `@Query` (bộ dịch SQLite iOS 17 lỗi) — query hết rồi lọc trên RAM bằng computed property. Tác vụ nền phải tạo `ModelContext` riêng từ `ModelContainer`, không dùng chung context của MainActor.
- **Ghi SwiftData** đi qua `BookTransactionCoordinator` / `ExtensionTransactionCoordinator` với Command DTO bất biến; View chỉ `@Query` để đọc.
- **Toast từ tầng nền**: Service phát event qua `TTSPresentationEventCenter` / `DownloadPresentationEventCenter` (`AsyncStream`); `AppLaunchRootView` là subscriber UI duy nhất.
- **Không chặn Main Thread** bằng `DispatchSemaphore` khi chờ `WKWebView` (bypass Cloudflare) — deadlock vĩnh viễn. Dùng `withCheckedContinuation`.
- **Tiến độ đọc**: chỉ lưu DB khi lệch ≥ 3 đoạn, debounce 3 giây (`ReaderViewModel.dbSaveTask`); lưu ngay khi `scenePhase == .background` — **không** hook `.onDisappear`.
- **Huỷ vs flush**: khi nội dung chương đã qua checkpoint cancel cuối và vào memory chia sẻ, lệnh ghi nền **không được cancel**. Reader dismiss thì *flush* pending write. Một load đang bay có thể phục vụ nhiều subscriber: cancel một subscriber chỉ resume waiter đó bằng `CancellationError`; task gốc chỉ dừng khi waiter cuối rời đi. `CancellationError` không được ghi trạng thái lỗi hay tính là synthesis failure.
- **Xoá sách**: `BookStorageManager` là điều phối viên duy nhất — `ModelContext.save()` thành công rồi mới xoá file nền. Mọi thao tác file phải qua `validatePathSafety(for:)`; xoá thất bại đẩy vào queue `failed_file_deletions_queue` (UserDefaults), retry tối đa 3 lần lúc khởi động.

## Quy ước đặt tên & cấu trúc

- **Từ "Extensions" bị dùng cho 4 nghĩa khác nhau** — bẫy đặt tên tệ nhất repo này:
  - `Sources/Services/Extensions/` = phân hệ **plugin JavaScript VBook**
  - `Sources/Views/Extensions/` = **màn hình quản lý** plugin
  - `Sources/*/*/Extensions/` = file `extension` **Swift** thuần
  - `@Model Extension` trong `Sources/Models/Database/Extension.swift` = **thực thể SwiftData**

  Đường dẫn `Sources/Views/Extensions/Manager/Extensions/RepositoryManagerView+Actions.swift` chứa hai nghĩa khác nhau của cùng một từ. Đọc kỹ path trước khi kết luận.
- **Tách file kiểu `X+Feature.swift`** (19 file) là cách repo giữ god-object dưới baseline dòng: `TTSManager+{Playback,Interruption,NowPlaying,NghiEnergy,PrefetchCache,Telemetry}`, `ReaderView+{Controls,LoadingView}`, `ReaderViewModel+Translation`, `BookDetailView+{Extensions,TOCPreparation}`, `JSExecutor+Async`, `TranslateUtils+Tokenization`. Muốn thêm code vào một type lớn thì thêm vào file `+` phù hợp (hoặc tạo file mới), đừng làm file gốc phình thêm.
- **Chỉ có 2 ViewModel thật**: `ReaderViewModel` và `FloatingWidgetViewModel`, đặt cạnh view của nó chứ không có thư mục `ViewModels/`. Mọi màn khác dùng `@State` trong View + projection reader.
- Hậu tố quyết định vai trò (theo `rules.md`, và code tuân thủ khá sát): `Repository` = single source of truth cho một domain, `Store` = engine lưu trữ mức thấp, `Coordinator` = chủ transaction/flow, `Worker` = actor/task nền, `Snapshot` = bản sao bất biến qua ranh giới isolation, `Command`/`DTO` = payload bất biến, `Mapper`/`Formatter` = converter thuần, `Engine` = thực thi mức thấp.
- **View không observe trực tiếp `TTSManager`** — dùng projection reader (`TTSWidgetStateReader`, `TTSRootPresentationReader`, `ReaderTTSStateReader`). `ReaderTTSStateReader.scope(to: bookId)` làm snapshot của sách khác thành inactive để Reader ngoài màn hình không redraw theo mỗi bước highlight.
- **NotificationCenter vẫn là event bus liên module nhưng phần lớn tên là string literal trần** — đổi tên là vỡ ngầm, grep cả hai đầu: `"openCurrentlyPlayingReader"`, `"navigateReaderToPlayingChapter"`, `"ttsDidAdvanceToNextChapter"`, `"sourceChangedNavigateToShelf"`, `"extensionDidUpdate"`. Chỉ 2 tên có hằng số kiểu: `.translationDictionariesDidUpdate` và `VisibleBrowserTabManager.stateDidChangeNotification` — nhưng `TTSManager` vẫn observe tên thứ nhất bằng string trần. Signalling mới thì dùng `AsyncStream` event center, đừng thêm notification string mới.
- Comment, chuỗi lỗi và log message viết **tiếng Việt**; tên type/member viết tiếng Anh. Comment kiến trúc mới thì tiếng Anh. Cả hai đều bình thường ở đây — giữ theo file đang sửa.

## Tests

XCTest trong `Tests/` (20 file), `@testable import FreeBook`. Test nhắm tầng logic thuần (normalizer, builder, translate utils, repository, accounting) chứ không phải UI.

**Test Lock Rule** — `.agents/AGENTS.md` §2.1: **không tạo mới, bổ sung hay chỉnh sửa unit test nếu người dùng chưa yêu cầu rõ ràng**; `rules.md` siết thêm là không tạo/sửa/đổi tên/xoá/format bất kỳ file nào dưới `Tests/`. Vẫn được phép **chạy** test có sẵn và chạy validation tĩnh.

**`Tests/ChapterTextNormalizerTests.swift` đang lạc hậu và sẽ FAIL** — nó assert `ids == [0, 1]` và `utf16Range.location == 4` từ thời paragraph ID còn liên tục, trong khi normalizer hiện gán chỉ số dòng thô (xem mục Architecture). Truy vết bằng tay: `"  Một\r\n\r\n \t\rHai 😀  \n"` cho `ids == [0, 3]` và range thứ hai ở `location: 6`; `"Một\n\nHai"` cho `[0, 2]`. Ba trong bốn test trong file này fail, kể cả `testNormalizationIsIdempotent`. CI không chạy test nên chuyện này không tự lộ ra, và Test Lock Rule khiến nó không tự lành. **Đừng dùng file này làm đặc tả.** (Truy vết thủ công — chưa thực thi được vì cần macOS.)

## Bẫy đã xác minh & sai lệch tài liệu

`rules.md` là tài liệu quy phạm có thẩm quyền cao nhất, **nhưng vài chỗ đã cũ hơn code**. Ở các điểm dưới đây phải đánh dấu `UNKNOWN` và hỏi người dùng, **không** tự sửa code để khớp rules.md:

1. **`ReaderSelectionMapper.mapHighlight` đã bị xoá.** `rules.md:86-87` vẫn bắt buộc mọi highlight TTS phải map qua hàm này. Nó bị xoá ở 1.3.81 cùng `mappedRangeUsingOriginalSpans` và `proportionalHighlightFallback` (xem `CHANGELOG.md` mục `[1.3.81]`), vì pipeline đã dịch-trước-khi-normalize nên không còn lệch hệ toạ độ. Đừng thêm lại.
2. **Thermal state của NghiTTS mâu thuẫn nội bộ.** `rules.md` khẳng định ba lần rằng thermal chỉ dùng để log và không được chặn refill/prefetch, nhưng §5.7.2 lại quy định gating theo `.serious`/`.critical`. Hỏi trước khi dựa vào bên nào.
3. **`Scripts/check_architecture.py` không phải build gate.** `rules.md` không yêu cầu chạy nó (chỉ nhắc `architecture_allowlist.json` như baseline), và step chạy nó đã bị bỏ khỏi `build-ipa.yml` theo quyết định của maintainer. Nó là tool local — vẫn nên chạy, nhưng không ai chặn merge vì nó.
4. **`ReaderParagraphBuilder` và `TTSParagraphBuilder.build(from:)` là API chỉ test dùng.** Production dựng `[ParagraphItem]` ở `Sources/Views/Reader/Extensions/ReaderViewModel+Translation.swift` (logic gần như copy y nguyên của `ReaderParagraphBuilder.build`, thêm `Task.checkCancellation()` mỗi 5 dòng) và dựng chunk qua `TTSBackgroundProcessor` → `TTSParagraphBuilder.buildFromEntries`. Cả `ReaderParagraphBuilder` và overload `build(from:chunkLength:)` **không có caller nào trong `Sources/`**. Sửa logic dựng đoạn phải sửa **cả hai bản**; test xanh không chứng minh đường production đúng.
5. **`00_index.md` front matter ghi `source_files: 87`** trong khi `manifest.json` và validator đếm **218**. Con số trong front matter đã lạc hậu, đừng dùng nó để suy luận phạm vi.
6. **`ReaderRoute` không nằm trong thư mục Reader.** Nó khai ở `Sources/Views/BookDetail/BookDetailView.swift:4`; một type khác `ShelfReaderRoute` ở `Sources/Views/Shelf/ShelfMain/ShelfView.swift:5`. Không có file `ReaderRoute.swift` nào dù `Tests/ReaderRouteTests.swift` tồn tại.
7. **`ReaderSelectionCoordinator` bị đặt tên sai** — nó chỉ làm tra Hán-Việt và format chữ hoa/thường, không liên quan gì tới selection.
