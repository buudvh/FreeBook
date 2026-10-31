# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

> File này và `AGENTS.md` ở thư mục gốc là **cùng một nội dung**, chỉ khác 3 dòng đầu (một bản cho Claude Code, một bản cho Codex). Sửa file này thì mirror sang `AGENTS.md`.

## Bắt buộc đọc trước khi sửa code

Repo này có quy trình AI riêng, **ưu tiên cao hơn hướng dẫn mặc định**:

1. `.agents/AGENTS.md` — workflow 8 bước bắt buộc cho mọi AI assistant.
2. `Docs/CodeGraph/rules.md` — quy chuẩn kỹ thuật + checklist tự kiểm tra (tài liệu có thẩm quyền cao nhất).
3. `CHANGELOG.md` — lịch sử thay đổi theo version `[1.3.NNN]`.

**Điều hướng cấu trúc**: thay vì đọc doc MB, hãy dùng công cụ MCP **`codegraph_explore`** (hoặc CLI `codegraph explore "<câu hỏi>"`) — nó trả source verbatim + call paths + quan hệ trong một lần gọi. Index nằm ở `.codegraph/` (tự động đồng bộ khi file đổi; build bằng `codegraph init`). Nếu agent không có MCP, fallback CLI `codegraph explore`. **Agent được tự chạy `codegraph sync` khi cần** — ví dụ codegraph báo *"pending index sync"*, kết quả rõ ràng cũ hơn code vừa sửa, hoặc sau `git pull`/đổi nhánh; chỉ `codegraph init` (build lần đầu) mới là việc của người dùng.

**Thứ tự thẩm quyền khi xung đột**: `rules.md` > Source Code > `CHANGELOG.md` > tài liệu khác. Nếu không đủ bằng chứng để phân biệt sai lệch là chủ ý hay bug, phải đánh dấu `UNKNOWN` và hỏi người dùng — không tự suy đoán. **Nhưng đọc mục "Bẫy đã xác minh & sai lệch tài liệu" ở cuối file trước**: `rules.md` có chỗ đã cũ hơn code, đừng sửa code chỉ để khớp nó.

Sau khi sửa code: cập nhật `CHANGELOG.md` (version `[1.3.NNN] - YYYY-MM-DD`, tăng NNN mỗi thay đổi; tiêu đề entry **trùng với subject của git commit**), và **kết thúc response bằng một trong hai cụm**: `"CodeGraph updated."` hoặc `"No CodeGraph update required."` (giữ quy ước này cho nhất quán dù không còn validator). Khi cần hiểu/sửa cấu trúc, ưu tiên `codegraph_explore` thay vì đọc file lớn.

`CHANGELOG.md` đánh version `[1.3.NNN] - YYYY-MM-DD` (tăng NNN mỗi thay đổi); tiêu đề entry **trùng với subject của git commit** tương ứng — giữ đúng quy ước này. Luôn thêm entry mới vào `CHANGELOG.md`; khi file vượt ~30 entry thì đẩy phần cũ nhất sang `CHANGELOG.archive.md` (chỉ để tra cứu, không bao giờ ghi mới vào đó) để giữ file chính gọn token.

## Commands

Dự án là app iOS, dùng **XcodeGen** — `.xcodeproj` không commit mà sinh từ `project.yml`.

```bash
# Sinh FreeBook.xcodeproj (chạy lại mỗi khi thêm/xoá/đổi tên file Swift)
xcodegen generate

# Build
xcodebuild build -project FreeBook.xcodeproj -scheme FreeBook \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

Không có lệnh test ở đây — xem mục [Tests](#tests): tầng test bị coi như không tồn tại.

Công cụ kiểm tra chạy được **mọi nền tảng**, kể cả Windows — luôn chạy chúng dù không build được:

```bash
codegraph explore "<câu hỏi hoặc tên symbol>"   # source verbatim + call paths (giống MCP codegraph_explore)
codegraph status                                 # thống kê index (.codegraph/)
codegraph sync                                   # đồng bộ index với cây làm việc — agent TỰ chạy khi cần
codegraph init                                   # build index lần đầu (tạo .codegraph/) — chỉ người dùng chạy
python Scripts/check_architecture.py             # gate kiến trúc, exit 0 = pass
```

**Không còn validator `validate_links.py`.** Phần "đồ thị cấu trúc" của CodeGraph đã nghỉ hưu, thay bằng công cụ **`codegraph` MCP** (Rust/Node, 100% local, tự động đồng bộ index khi file đổi). Mọi truy vấn cấu trúc (tìm symbol, call path, blast radius) dùng `codegraph_explore` MCP hoặc CLI `codegraph explore` — **không** đọc doc MB. `codegraph.json` ở root khai `exclude` (`Tools/`, `Docs/CodeGraph/`, `Docs/Plans/`, `Docs/Reports/`, `*.xcodeproj`) và `deprioritize` (`Sources/Extensions/**/src/`).

## Thiết lập trên máy mới / checkout mới

Khi clone repo này về máy khác (hoặc để lâu ngày rồi `git pull` nhiều thay đổi), codegraph cần khởi tạo thủ công một lần — công cụ **không tự build index** (lệnh `codegraph explore` sẽ báo *"no .codegraph/ index exists ... run 'codegraph init'"* và bảo agent không tự chạy init):

1. Cài codegraph (binary + PATH): chạy `install.ps1` từ GitHub release, hoặc `codegraph upgrade` nếu đã có.
2. Tại root repo: `codegraph init` — build `.codegraph/` từ `codegraph.json` (bắt buộc; agent **không** tự chạy).
3. Wire các agent hỗ trợ: `codegraph install --yes --target=claude,codex,antigravity`.
4. WorkBuddy (không nằm trong danh sách `install`): tự tạo `~/.workbuddy-ai/mcp.json`:
   ```json
   {
     "mcpServers": {
       "codegraph": {
         "command": "codegraph",
         "args": ["serve", "--mcp"],
         "env": { "CODEGRAPH_TELEMETRY": "0", "CODEGRAPH_WATCH_DEBOUNCE_MS": "2000" }
       }
     }
   }
   ```
   rồi Connectors → mục **"Custom connectors"** góc trên bên phải → bấm **Trust**.
5. Đồng bộ lại sau idle dài / git pull / đổi nhánh: `codegraph sync` (hoặc `codegraph index` để rebuild toàn bộ) — **agent tự chạy**, không cần hỏi. File watcher tự động đồng bộ khi session đang chạy, nhưng **không** bắt kịp thay đổi lúc máy tắt.

**Lưu ý môi trường**: build chỉ chạy được trên macOS. Repo hay được mở trên Windows — khi đó không build tại chỗ được; phải nói rõ điều đó thay vì báo "đã kiểm chứng".

**CI không phải test gate.** `.github/workflows/build-ipa.yml` chỉ `xcodegen generate` → `xcodebuild archive` (unsigned) → đóng gói IPA + nhồi `espeak-ng-data` → gửi Telegram. Nó **không chạy unit test, không chạy `check_architecture.py`, cũng không truy vấn `codegraph` MCP**, và chỉ trigger khi đổi `Sources/**` hoặc `project.yml`. Nghĩa là CI xanh = *biên dịch được*, không phải *đúng*.

`GOOGLE_CLOUD_TTS_API_KEY` đi từ GitHub secret → build setting → `Info.plist` (`project.yml` khai `GOOGLE_CLOUD_TTS_API_KEY: "$(GOOGLE_CLOUD_TTS_API_KEY)"`, workflow còn `plutil -replace` vào IPA). Build local không có key thì Google TTS im lặng không hoạt động — không phải bug.

Target đặt `CODE_SIGNING_ALLOWED: NO`. Deployment target iOS 17.0. Dependencies (SwiftSoup, ZIPFoundation, ONNX Runtime, espeak-ng-spm) khai SPM trong `project.yml`.

## Kỷ luật kiến trúc (có script cưỡng chế)

`Scripts/check_architecture.py` quét `Sources/` và enforce 6 luật:

| Luật | Nội dung |
|---|---|
| `FILE_SIZE_LIMIT` / `NEW_FILE_TOO_LARGE` | file Swift mới ≤ **400 dòng vật lý**; file legacy dùng baseline riêng và **chỉ được giảm** |
| `MULTI_PRIMARY_TYPES` | đúng **1** type chính (class/struct/enum/actor) ở top level mỗi file |
| `VIEW_SWIFTDATA_MUTATION` | `Sources/Views/**` không được `modelContext.insert/delete/save`; 6 view lớn còn bị cấm gán trực tiếp thuộc tính `@Model` và cấm bỏ qua `Result` của coordinator |
| `SERVICE_TOAST_COUPLING` | `Sources/Services/**` không được gọi `ToastManager.shared` |
| `SERVICE_SWIFTUI_IMPORT` | `Sources/Services/**` không được `import SwiftUI` (trừ `*WebViewLoader.swift`) |
| `WHITE_TINT_FILL` | `Sources/Views/**` không tô nền đặc bằng `Color.accentColor` (mờ < 50% thì được) và không dùng `.borderedProminent` thiếu `.tint(<màu khác trắng>)` — app đặt `.tint(.white)` toàn cục nên đó là **trắng trên trắng**. Nút đặc mới dùng `.buttonStyle(.appFilled)` (`Sources/Views/Common/AppFilledButtonStyle.swift`) |

Miễn trừ khai trong `Scripts/architecture_allowlist.json` (`schema_version: 2`, fail-closed). Mỗi entry có `expiresAt` — **script FAIL nếu entry hết hạn**; 88 entry hiện tại đều hết hạn `2026-12-31`. Chỉ có miễn trừ cho `FILE_SIZE_LIMIT` và `MULTI_PRIMARY_TYPES`; hai luật View-SwiftData và Service-Toast không có ngoại lệ nào.

**Script hiện đang đỏ** (baseline đã trôi so với code): 2 violation trên cây sạch (`JSDom.swift`, `TTSManager.swift` vượt baseline dòng; đếm lại ở 1.3.529). Vì vậy chạy nó *trước* khi sửa, chạy lại *sau*, và chỉ chịu trách nhiệm cho violation mới do mình gây ra. Đừng "sửa cho xanh" bằng cách nới baseline nếu người dùng không yêu cầu.

**Và `[PASS]` của script không phải bằng chứng.** Hàm `strip_comments_and_strings` (`check_architecture.py:53-60`) dùng regex `"([^"\\]|\\.)*"` để xoá string literal, nhưng regex này ghép sai dấu nháy khi gặp string interpolation Swift nên **ăn cả code thật**. Kết quả: `ShelfView.swift:757` và `BookDetailView.swift:239` đều có `try? modelContext.save()` thật mà script **không phát hiện**. Vẫn phải tự đọc code, đừng tin mỗi exit code.

## Architecture

`Sources/` có 5 tầng: `App` (chỉ `FreeBookApp.swift`) / `Common` / `Models` / `Services` / `Views`. Chiều phụ thuộc: Views → ViewModel/Coordinator → Services/Repositories → Models. 814 file Swift (đếm 1.3.531).

### Bootstrap & lưu trữ

Khởi động chia làm **hai chỗ**, đây là bẫy cho người mới:

- `Sources/App/FreeBookApp.swift` — `ModelContainer` trỏ URL tường minh `applicationSupportDirectory/library.db` (không phải mặc định của SwiftData), schema đúng **4** `@Model`: `Book`, `BookCollection`, `Chapter`, `DownloadTaskModel`. **Tiện ích và kho không còn là SwiftData** (1.3.529): trước khi mở container, `init` gọi `LegacyExtensionSQLiteMigrator.runIfNeeded` (chuyển một lần dữ liệu cũ bằng sqlite thô từ bản `VACUUM INTO`) rồi `ExtensionLibraryRepository.shared.load()`. Không có `VersionedSchema`/`SchemaMigrationPlan` — chỉ có lightweight migration ngầm, nên đổi shape `@Model` là việc nguy hiểm. `AppLaunchRootView` **chặn toàn bộ app** sau `AppLoadingView` cho tới khi `TranslationManager.shared.isInitialized`; cờ này set trong `defer` nên bật `true` **kể cả khi nạp từ điển thất bại**. Sau đó: drain hai retry queue của `BookStorageManager`, bơm `ModelContainer` vào `TTSFloatingWidgetWindowManager` và `FloatingHubWindowManager`, chạy `BookTitleTranslationMigrator.runIfNeeded`, và subscribe hai `AsyncStream` toast.
- `Sources/Views/MainTabView.swift` — nơi thật sự gọi `DownloadManager.shared.initialize(container:)` và `TTSManager.shared.initialize(container:)`, cộng flush khi `scenePhase` vào background (`TTSManager.checkpointForBackground()`, `ReadingProgressStore.flushAll()`, `ChapterContentRepository.flushAll()`). `MainTabView` chỉ mount **sau** khi cổng từ điển mở.

**`ChapterStoreConfiguration.enableSwiftDataTOCWrite = false`** — mục lục chương **không** nằm ở bảng SwiftData `Chapter` mà ở `chapters/chapter_store.sqlite` (raw sqlite3, actor `ChapterStore`). Đọc `Book.chapters` trong production sẽ thấy rỗng. Code branch theo cờ này ở `ReaderViewModel`, `ReadingProgressStore`, `BookDetailView`.

Mọi thứ nằm dưới `applicationSupportDirectory` (hai ngoại lệ: `Documents/Exports/` cho export TXT, và `Caches/comic_images/` = cache ảnh comic tải lại được, hệ điều hành được phép xoá): `library.db`, `chapters/chapter_store.sqlite`, `books/<sha256(bookId)>.bin` (append-only, không compaction — ghi lại chương làm file phình mãi, chỉ xoá cả truyện mới thu hồi), `covers/<sha256(bookId)>.jpg`, `extensions/<packageId>/` (script/icon của tiện ích), `extension_store/` (`installed.json` = index tiện ích đã cài với đường dẫn **tương đối**, `repositories.json`, `registry/<sha256(url)>.json` = cache registry, `local_storage.json` = `localStorage` của JS theo `packageId`, `legacy/library-pre-ext.sqlite` = bản chép DB trước migrate), `comics/<sha256(bookId)>/<chapterIndex>/` (ảnh comic tải offline + `manifest.json`, `ComicOfflineStore`; Backup **không** gói), `videos/<sha256(bookId)>/<episodeIndex>/` (phim tải offline: playlist/đoạn HLS hoặc `video.mp4` + `manifest.json` ghi sau cùng, `partial.json` = chữ ký bản dở; `VideoOfflineStore`; Backup không gói, `isExcludedFromBackup`), `adblock/` (bộ lọc tải về, `filters_meta.json`, `compiled/` của `WKContentRuleListStore`, `site_preferences.json` = chỉnh riêng theo tên miền; Backup không gói), `translate/`, `FreeBook/TTS/`, `app_logs.txt`. Hàm băm SHA-256 và `validatePathSafety(for:)` bị **cài lại độc lập ở từng owner** (`BookBinManager`, `ImageCacheManager`, `BookStorageManager`, `ChapterStorePath`, `ComicOfflineStore`, `VideoOfflineStore`) — sửa một chỗ không lan sang chỗ khác.

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

- Cache PCM `preloadedData` (+ `preloadedDurations`) chỉ giữ cửa sổ trượt của từng engine — Remote (Google/Ext) `[N, N+count]` với `count = clamp(currentPrefetchCount, 1, 10)`, NghiTTS `N` + `N+1` bắt buộc + tối đa 2 optional reserve — không dọn sẽ OOM. Callback audio ngầm phải `[weak self]`.
- `NghiSynthesisPolicy` là nguồn duy nhất cho watermark cached-time: `defaultSafeCachedTimeThreshold = 8.0`s, dải `4.0...20.0` (UserDefaults `nghittsSafeCachedTimeSeconds`), `maxOptionalReserveItems = 2`. **Không** chứa cooldown hay thermal eligibility. Thermal state chỉ là telemetry (energy log), không bao giờ chặn/điều tiết refill hay prefetch của Nghi lẫn Remote. Đừng nhân bản các hằng này sang manager/prefetcher.
- ONNX/XNNPACK cố định **1 worker** — cố ý, không phải thiếu tối ưu; đừng scale theo số core.
- Chỉ **1** operation tổng hợp chạy tại một thời điểm; `PiperSynthesisCoordinator` xếp hàng theo 4 mức ưu tiên.
- **Retry thuộc về đúng một tầng**: Remote (Google/Ext) retry tối đa 2 lần *bên trong* `RemoteTTSSynthesisCoordinator` — `TTSManager` **không** được bọc thêm vòng retry. Ngược lại refill của NghiTTS do `TTSManager` sở hữu (2 lần, retry backoff 1s qua `Task.sleep`).
- Không dùng `AVAudioEngine` node-streaming cho NghiTTS; đường phát là `AVAudioPlayer` double-buffering qua `NghiAudioPlayerQueue`.
- `ChapterContentRepository` giữ cache chia sẻ tối đa **12 entry / 12 MiB** (`maxMemoryEntryCount`, `maxMemoryCost`). Document vượt budget vẫn trả về cho caller, chỉ là không được cache.

### Dịch thuật VietPhrase

`TranslateUtils` tra từ điển và dựng `TranslatedTextResult { text, spans }`. `buildTranslationSpans` dò từng token dịch trong chuỗi kết quả; nếu **một** token không tìm thấy thì trả `[]` — mọi code tiêu thụ span phải xử lý được mảng rỗng.

### Extension JavaScript (VBook)

Entrypoint mọi file JS (`search.js`, `detail.js`, `toc.js`, `chap.js`, `genre.js`, `home.js`) là hàm `execute(...)`, gọi qua `runAsync`. Script nằm ở gốc extension hoặc trong `src/`. Manifest là `plugin.json`.

**Kiến trúc bridge cần hiểu trước khi thêm API JS**: `JSExecutor` không expose Swift trực tiếp cho script. Nó cài các block Swift tên `_nativeXxx` (`_nativeSyncFetch`, `_nativeBrowserLaunch`, `_nativeQtTranslate`, `_nativeStorageGet`…) rồi `evaluateScript` các gói polyfill JS (`responseBootstrap`, `fetchBootstrap`, `engineBootstrap`, `qtBootstrap`, `storageBootstrap`, `userAgentBootstrap`, `scriptBootstrap`) dựng nên API mà extension thấy: `Html`, `Engine`, `Response`, `fetch`, `Qt`, `Crypto`, `Script`, `UserAgent`, `localStorage`, `cacheStorage`, `localConfig`, `localCookie`, `console`/`Console`/`print`/`Log`, `toast`, `load`, `atob`/`btoa`. Thêm một API JS = thêm cả block `_native*` **và** wrapper trong bootstrap tương ứng. Đừng phá tương thích ngược nếu không được yêu cầu.

**`load('x.js')` = thay văn bản trước khi chạy** (hợp đồng, 1.3.657): `prepareScript` chạy trước các file mà script chính `load(...)` ở **cột 0**, rồi mới chạy script chính ⇒ khai báo của script chính thắng khi trùng tên (`config.js` có `execute()` riêng không đè `execute()` của script). `load` cùng tên sau đó là no-op; `load` runtime file chưa nạp (`Script.execute`, `Qt.include`) giữ kiểu chạy ngay. Code ở `JSExecutor+Load`. Tiện ích không mang file mà tên nằm trong `JSBuiltInLibrary` (`crypto.js` = CryptoJS 4.2.0 đóng gói, 1.3.664) ⇒ app cấp bản dựng sẵn; file của tiện ích **luôn thắng** (người dùng chọn, khác hợp đồng); sau mỗi lần nạp `crypto.js` gắn `AES.encryptGcm/decryptGcm` + PBKDF2 native (`JSCryptoJSBridge`). Detail đọc cả `comment` (một nguồn, hiện trước) lẫn `comments`; thiếu `title` ⇒ "Bình luận".

Mỗi tác vụ bóc tách tạo `JSExecutor` mới rồi giải phóng — **không** dùng executor dùng chung (`sharedExecutor` là anti-pattern có tên trong `rules.md`). Ngoại lệ duy nhất: `ExtTTSRuntime` actor được giữ executor lâu dài. `DownloadManager` mặc định dùng đúng một `BookDownloadWorker` actor cho mỗi tác vụ, tuần tự và cancel được; nguồn được người dùng chọn 2–3 luồng (`DownloadSpeedSettings`, nhớ theo nguồn, 1.3.624) thì mỗi luồng một worker riêng (`DownloadManager+ChapterLanes`), kết quả vẫn xếp đúng thứ tự mục lục.

**`fetch` lỗi tự thử lại bằng browser ẩn** (1.3.613, `JSExecutor+FetchBrowserFallback` → `HiddenBrowserFetch`): chỉ khi lỗi mạng / hết giờ / HTTP 403, 429, 503, request GET không body, URL http(s), không phải domain bị chặn, không huỷ, và **không ở main thread** (semaphore + main queue sẽ deadlock ⇒ bỏ qua). Browser ẩn chờ tối đa 15s qua trang chặn Cloudflare, đọc lỗi điều hướng + mã HTTP trang chính (`WebViewLoader+NavigationResponse`). Thành công ⇒ trả 200 cho script; cả hai lỗi ⇒ giữ response gốc, `statusText` = `"<gốc> | Browser ẩn: <lý do>"`. Executor cần dữ liệu nhị phân tắt bằng `allowsFetchBrowserFallback = false` (`ExtTTSRuntime`, `ComicImageScriptRunner`). Cookie qua thử thách nằm trong kho WebKit, **không** sang URLSession.

**Nút "Mở link lỗi"** (1.3.614): executor ghi URL fetch lỗi / fetch gần nhất của lượt chạy (`JSExecutor+FetchTrace`, xoá ở `beginExecution()`; tên miền chặn sẵn không ghi); `ExtensionManager` bọc lỗi của 10 hàm chạy script bằng `ExtensionLoadError` (chữ lỗi giữ nguyên — so kiểu lỗi gốc thì `ExtensionLoadError.unwrapped(_:)`). Màn lỗi dựng link bằng `SourceErrorLink.resolve(from:fallback(s):host:)` **ngay trong `catch`** (fetch lỗi → fetch gần nhất → URL lỗi Legado → URL đầu vào), hiện `ErrorLinkCaption` + `ErrorLinkButton`, và `.errorLinkBrowser(link:onRetry:)` mở `BypassWebView(forcesMobileUserAgent: true)`; đóng ⇒ `WebKitCookieBridge` chép cookie WebKit của tên miền sang `HTTPCookieStorage.shared` ⇒ tự thử lại. Màn lỗi mới thì nối cùng kiểu này.

Có skill riêng cho việc này: `.agents/skills/vbook_helper/SKILL.md` (mẫu `plugin.json` + mẫu từng script).

### Comic & Video (1.3.531)

Hợp đồng chuẩn: `extension-api.md` của Darkrai9x (repo Darkrai9x).

- **Loại nội dung suy ra lúc chạy, không lưu**: `ExtensionContentKind.resolve(packageId:)` (bản đã cài → catalog → `text`; `"local"` luôn `text`) hoặc `resolve(localPath:)` (đọc `metadata.type` của `plugin.json`). `Book` **không** có trường loại; `detail.type` ghi đè không được lưu.
- **Một router duy nhất**: `BookContentDestination` (cùng nhãn tham số với `ReaderView`) đứng ở cả 4 chỗ mở reader (BookDetail, Kệ, Tìm trên kệ, Bộ sưu tập) và chọn `ReaderView` / `ComicReaderView` / `VideoPlayerScreen`. Thêm lối vào reader mới thì dùng router, đừng gọi `ReaderView(` trực tiếp.
- **Media không bao giờ đi qua pipeline text**: ảnh comic và server/track video lấy bằng `ExtensionManager.comicPages` / `videoServers` / `videoTrack` (`ExtensionManager+Media.swift`), không qua `chap()`, `ChapterContentRepository`, `cleanHTML`, JunkFilter, bin, dịch hay TTS. `link` của ảnh có `script` và `data` của server/track phải giữ **nguyên văn**, không `cleanAndResolveUrl`, không trim.
- **`Book.currentChapterPage` có ba nghĩa** theo loại: chỉ số đoạn (chữ), chỉ số ảnh (comic), **số giây** (video). Comic/video ghi tiến độ qua `ReadingProgressStore.checkpoint`, nếu không sách sẽ rơi khỏi tab Lịch sử.
- `toc` bỏ item `type:"section"` **chỉ** với comic/video; truyện chữ giữ nguyên để chỉ số chương của sách đã lưu không lệch.
- **Browser của tiện ích** (`WebViewLoader`, `VisibleWebViewController`) cài `WebNetworkCaptureScript` vào mọi frame. Vì vậy `urls()` / `waitUrl` thấy cả XHR, fetch và media, không chỉ điều hướng. Autoplay tắt tiếng **chỉ** bật cho tiện ích loại video.
- **Trình phát video** chiếm `AVAudioSession` (`.playback/.moviePlayback`) và tạm dừng TTS khi phát — **trừ khi video đang tắt tiếng** (1.3.610, `VideoPlaybackSession.isEffectivelyMuted`): khi đó TTS đọc tiếp, video không đổi session và không giành màn khoá; bật tiếng lại mới giành. Mở phim mới đặt tắt tiếng theo `VideoMutePolicy` (Cài đặt › Chung › Giao diện › Nội dung nhạy cảm từ 1.3.636, mặc định chỉ nguồn 18+). Vuốt chỉnh âm lượng ở chế độ toàn màn tự bật tiếng (nút âm lượng cứng thì không).
- **Màn đọc comic** (1.3.613): mục lục `ComicChapterListSheet` bám bố cục `ReaderChapterListView` (sheet 0.88/large, header bìa, tìm, đảo thứ tự giữ trong phiên). Chuyển chương theo `ComicChapterNavigationMode` chọn ở ngăn kéo "…" (1.3.643): mặc định **chạm 1/3 trái/phải** (giữa = bật/tắt thanh, vuốt ngang không đổi chương); kiểu cũ **vuốt ngang** (`chapterSwipeGesture`: trái ⇒ chương sau). Cuối chương chỉ còn dòng gợi ý, không còn nút. Reader truyện chữ cũng có chạm 1/3 hai bên (`ReaderEdgeTapDetector`, công tắc ở Cài đặt đọc) — không đụng bôi đen.
- **Tải video offline** (1.3.592): tác vụ `.download` của sách video đi `DownloadManager+Video` → `VideoEpisodeDownloadPipeline` (server đã nhớ trước, lỗi thì thử server khác; `isInteractive: false`; bỏ `.embed`/DRM/live). HLS tự tải **tuần tự** từng đoạn (`VideoHLSDownloader`), phát lại qua server nội bộ **chỉ 127.0.0.1** + token (`VideoOfflineHTTPServer` — AVPlayer không chính thức phát m3u8 `file://`); mp4 phát `file://`. `runEpisodeLoad` thử bản tải **trước** khi tra tiện ích (`VideoPlaybackSession+Offline`). Mỗi phim chỉ một tác vụ video chạy một lúc. UI đọc trạng thái tải qua `VideoOfflineLibrary`, không tự đọc đĩa trong `body`.
- **Khám phá giữ cả `explore` lẫn `home` — cố ý khác hợp đồng** (1.3.554): hợp đồng nói khai cả hai thì `explore` thắng, nhưng `DiscoveryView.fetchCatalog` vẫn gọi `home`; tab "Trang chủ" dạng section (`ExploreSectionsView`) đứng đầu, tab `home` và `genre` theo sau. Đừng sửa về lại cho khớp hợp đồng. Trang `explore` chờ script trả về toàn bộ mới hiện (hợp đồng không có tải lười từng section, `fetch` đồng bộ).

### Chặn quảng cáo & chế độ máy tính (1.3.549)

- **Cơ chế**: `WKContentRuleList` biên dịch từ bộ lọc AdGuard bản tối ưu iOS (`filters.adtidy.org`, id 2/11/214/224 bật sẵn; 19/18/3 tắt sẵn). Chuyển đổi bằng **SafariConverterLib 4.3.1** (SPM, GPL-3.0, có build plugin nên CI cần `-skipPackagePluginValidation`). Mỗi bộ lọc một rule list `adblock-<id>`. Code ở `Sources/Services/Browser/AdBlock/`; bản đóng gói `Sources/Resources/AdBlock/` (tạo lại bằng `Scripts/update_adblock_snapshot.py`, `.gitattributes` giữ CRLF để checksum khớp). Tự cập nhật khi quá hạn `! Expires:` (mặc định 5 ngày).
- **Một nguồn quyết định**: `WebContentPolicy.decision(for:)` → `WebContentDecision { adBlock, desktop }`; `WebContentConfigurator.apply` gắn rule list + UA. Luật ưu tiên: trình duyệt người dùng = chỉnh riêng theo tên miền (`BrowserSitePreferenceStore`) ?? cài đặt chung; webview tiện ích = `Extension.adBlockOverride ?? chung` và `Extension.desktopModeOverride ?? false` (mặc định máy tính của trình duyệt **không** áp sang tiện ích); UA tiện ích tự khai (header track video) thắng chế độ máy tính. Gemini/Google Drive **không** thuộc phạm vi.
- **Chỉ có hiệu lực qua biến thể** `decidePolicyFor:preferences:decisionHandler:` (5 delegate: `BypassBrowserTabStore`, `WebViewLoader`, `VisibleWebViewController`, `VideoEmbedWebView`, `VideoMediaSniffer`). Thêm lại biến thể cũ là WebKit gọi một trong hai — đừng thêm song song.
- `WKContentRuleList` **không** tác động URLSession: `fetch` native của `JSExecutor` vẫn chỉ qua `isEngineDomainBlocked`. Không có API đếm request bị chặn.
- `currentRuleLists()` là bản chụp đồng bộ (lock), rỗng tới khi `warmUp()` (gọi từ `MainTabView`) biên dịch xong — webview tạo trước lúc đó chạy không luật.
- **Dịch QT + menu nhấn giữ của trình duyệt người dùng (1.3.655)**: script dịch (`Services/Browser/Translate/`) và script menu (`Services/Browser/ContextMenu/`) chạy trong **cùng** content world `BrowserPageTranslateScript.contentWorld`. Cài qua `BypassBrowserTabStore.installBrowserSupport(into:)` — **một lần mỗi `WKUserContentController`** (tab `window.open`/`_blank` dùng chung controller của tab mẹ; thêm trùng tên handler là crash). Handler `fbPageTranslate` có trả lời (`addScriptMessageHandler`), `fbContextMenu` không trả lời (`add(_:contentWorld:name:)`). Nhớ dịch: tên miền (`BrowserSitePreference.translate`) ⇒ tiện ích khớp URL (`Extension.translateOverride`) ⇒ tắt (`BrowserTranslatePolicy`). Webview của tab là `BrowserWebView` (lớp con, `buildMenu` thay menu bôi đen) dù `tab.webView` khai `WKWebView`.
- Chặn popup chỉ ở trình duyệt người dùng (`createWebViewWith`): script mở sang tên miền khác ⇒ chặn + dải báo; link `.linkActivated` vẫn mở. Chưa kiểm trên máy: popup tạo bằng `a.click()` có bị báo `.linkActivated` không, và tab `window.open` dùng chung `WKUserContentController` với tab mẹ (đã xử lý bằng cách áp lại ở điều hướng kế tiếp).

## Ràng buộc runtime cần nhớ

- **Logging**: chỉ `AppLogger.shared.log(...)`. File ghi ở `applicationSupportDirectory/app_logs.txt` (**không** phải `Documents`); ghi trên queue nền riêng (luồng gọi không chờ đĩa; crash có thể mất vài dòng cuối) và xoay vòng theo `AppLogFiles`: file quá 2 MB thì đẩy thành `app_logs.1.txt`…`app_logs.4.txt`, file cũ nhất bị xoá (1.3.518). Xuất log = xuất tất cả file, xoá log = xoá tất cả file. `AppLogger.init` **set `isLoggingEnabled = false` mỗi lần khởi chạy** (`AppLogger.swift:61`) — thêm log mà không thấy gì thì là do đây, phải bật lại trong Settings. Ngoại lệ (1.3.517): dòng chứa `❌` (log lỗi) luôn được ghi dù công tắc tắt — log lỗi mới phải có `❌`, dòng thường không được gắn `❌` để lách công tắc; `AppLogger.logAlways` chỉ dành cho chẩn đoán fd (`FileDescriptorCensus`, `FileDescriptorStepProbe`, `FileDescriptorSweeper`). App chạy thật qua LiveContainer trên máy iOS vật lý nên không đính được debugger; log file là kênh duy nhất. Không log secret hay full payload chương. (`AppLogger.log` tự gọi `print` bên trong — luật "không `print`" là không gọi trực tiếp ở nơi khác.)
- **SwiftData**: không viết predicate lọc chuỗi trong `@Query` (bộ dịch SQLite iOS 17 lỗi) — query hết rồi lọc trên RAM bằng computed property. Tác vụ nền phải tạo `ModelContext` riêng từ `ModelContainer`, không dùng chung context của MainActor.
- **Ghi SwiftData** đi qua `BookTransactionCoordinator` với Command DTO bất biến; View chỉ `@Query` để đọc.
- **Tiện ích & kho** (1.3.529): đọc qua `ExtensionLibraryRepository` (`@MainActor @Observable`; View đọc `.installed`/`.catalog` trong `body`, tầng nền dùng các hàm `nonisolated static` qua tên type như `ExtensionLibraryRepository.snapshot(packageId:)`), ghi qua `ExtensionTransactionCoordinator` (không còn tham số `in context:`). `Extension` là **struct** — biến giữ nó là bản chụp, sau khi ghi phải tra lại theo `packageId`. Luật chi tiết: mục "Extension store invariants (1.3.529)" trong `rules.md`.
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
  - `struct Extension` trong `Sources/Models/Extensions/Extension.swift` = **bản ghi tiện ích** (JSON, không còn là `@Model` từ 1.3.529)

  Đường dẫn `Sources/Views/Extensions/Manager/Extensions/RepositoryManagerView+Actions.swift` chứa hai nghĩa khác nhau của cùng một từ. Đọc kỹ path trước khi kết luận.
- **Tách file kiểu `X+Feature.swift`** (19 file) là cách repo giữ god-object dưới baseline dòng: `TTSManager+{Playback,Interruption,NowPlaying,NghiEnergy,PrefetchCache,Telemetry}`, `ReaderView+{Controls,LoadingView}`, `ReaderViewModel+Translation`, `BookDetailView+{Extensions,TOCPreparation}`, `JSExecutor+Async`, `TranslateUtils+Tokenization`. Muốn thêm code vào một type lớn thì thêm vào file `+` phù hợp (hoặc tạo file mới), đừng làm file gốc phình thêm.
- **Chỉ có 5 ViewModel thật**: `ReaderViewModel`, `FloatingWidgetViewModel`, `FloatingHubViewModel`, `ComicReaderViewModel` và `VideoPlayerController` (1.3.531), đặt cạnh view của nó chứ không có thư mục `ViewModels/`. Mọi màn khác dùng `@State` trong View + projection reader.
- Hậu tố quyết định vai trò (theo `rules.md`, và code tuân thủ khá sát): `Repository` = single source of truth cho một domain, `Store` = engine lưu trữ mức thấp, `Coordinator` = chủ transaction/flow, `Worker` = actor/task nền, `Snapshot` = bản sao bất biến qua ranh giới isolation, `Command`/`DTO` = payload bất biến, `Mapper`/`Formatter` = converter thuần, `Engine` = thực thi mức thấp.
- **View không observe trực tiếp `TTSManager`** — dùng projection reader (`TTSWidgetStateReader`, `TTSRootPresentationReader`, `ReaderTTSStateReader`). `ReaderTTSStateReader.scope(to: bookId)` làm snapshot của sách khác thành inactive để Reader ngoài màn hình không redraw theo mỗi bước highlight.
- **NotificationCenter vẫn là event bus liên module nhưng phần lớn tên là string literal trần** — đổi tên là vỡ ngầm, grep cả hai đầu: `"openCurrentlyPlayingReader"`, `"navigateReaderToPlayingChapter"`, `"ttsDidAdvanceToNextChapter"`, `"sourceChangedNavigateToShelf"`, `"extensionDidUpdate"`. Chỉ 2 tên có hằng số kiểu: `.translationDictionariesDidUpdate` và `VisibleBrowserTabManager.stateDidChangeNotification` — nhưng `TTSManager` vẫn observe tên thứ nhất bằng string trần. Signalling mới thì dùng `AsyncStream` event center, đừng thêm notification string mới.
- Comment, chuỗi lỗi và log message viết **tiếng Việt**; tên type/member viết tiếng Anh. Comment kiến trúc mới thì tiếng Anh. Cả hai đều bình thường ở đây — giữ theo file đang sửa.
- **Chuẩn Header & Toolbar UI (Bắt buộc cho mọi màn hình)**:
  - Mọi icon trên Header, NavigationBar, Toolbar bắt buộc dùng font `.system(size: 17, weight: .semibold)` (Apple SF Pro Header Action). Tuyệt đối không dùng kích cỡ tuỳ tiện (`.title3`, 13pt, 14pt hay regular).
  - Nút chữ trên Header/Toolbar (Lưu, Nhập, Xong…) dùng `.headerTextButton()` (`Sources/Views/Common/PageHeader/HeaderTextButtonModifier.swift`) = cùng font 17pt semibold (1.3.652).
  - Khoảng cách giữa các nút liền kề trên Header bar tối thiểu **`6pt`**; hitbox chạm tối thiểu **`36 x 36pt`** (khuyến nghị **`36 x 38pt`**).
  - Nút tròn: **`38 x 38pt`**. Nút capsule/pill cùng hàng: chiều cao **`38pt`** (`cornerRadius: 19`).
  - Nút Quay lại (Back): hitbox tối thiểu **`38 x 44pt`**. Cụm nút mục lục/menu phụ bên trong: icon **`14pt semibold`**, frame **`32 x 32pt`**, spacing **`4pt`**.
- **Màu nhấn của app là TRẮNG** (`MainTabView` đặt `.tint(.white)`): `Color.accentColor`, `.tint`, `.borderedProminent` không kèm tint đều ra trắng. Nút nền đặc dùng `.buttonStyle(.appFilled)` / `.appFilled(.green)`; chip đang chọn theo kiểu `ExtensionKindFilterBar` (chữ màu nhấn, nền nhấn mờ ~18%, viền ~60%). Luật `WHITE_TINT_FILL` của `check_architecture.py` chặn hai mẫu sai.
- **Icon sao chép/dán bắt buộc dùng `AppGlyph`** (`Sources/Views/Common/AppGlyph.swift`: `.copy`, `.paste`, `.originalText` — asset Lucide `Lucide*.imageset` trong `Sources/Assets.xcassets`, giấy phép ISC ở `Docs/ThirdParty/Lucide-LICENSE.txt`). **Không** dùng SF Symbol `doc.on.doc` / `doc.on.clipboard` (hai icon gần như giống hệt nhau). Ảnh asset không co theo `.font(...)` nên phải gọi `image(size:)` với cỡ tường minh; trong `contextMenu`/`Menu` dùng `Label(_:image: AppGlyph.copy.assetName)`.
- **Màn danh sách (1.3.636)**: header chỉ còn nút quay lại + `…` (`.sideDrawerMenu`), mọi thao tác khác vào ngăn kéo; "Thêm" là nút `+` nổi `.floatingAddButton(_:action:)` (`Sources/Views/Common/GlassChrome/`). Hàng theo kiểu VP/Name (`DictionaryEntryRow`): dòng 1 `.headline`, dòng 2 `.subheadline` màu phụ, cụm icon `.subheadline` [Sửa][Chuyển][Tắt/Bật `pause.circle`/`play.circle`][Xoá]. Danh sách dài nạp theo lượt nhưng phải nạp trước khi tới cuối (không có nút "Xem thêm"). Nền kính của nút nổi / ngăn kéo đọc `GlassChromeSettings` (Cài đặt › Chung › Giao diện) — đừng gán cứng độ mờ.
- **Header trang & sheet (1.3.641, tiêu đề ba kiểu 1.3.652)**: tiêu đề dùng `.pageTitle(_:)` (tab gốc, gốc sheet: trái, 22pt bold, một dòng) / `.backPageTitle(_:)` (trang có nút back: tiêu đề **giữa**, 22pt bold, một dòng, thu nhỏ tới 80% rồi cắt đuôi — ô `principal`, 1.3.652) / `.pageTitle(_:style:)` với `PageTitleStyle` `.leading`/`.centered`/`.hidden` (màn mở được cả hai kiểu: `style: isPresentedAsSheet ? .leading : .centered`) ở `Sources/Views/Common/PageHeader/` — **không** gọi `.navigationTitle` trực tiếp. Kiểu `.centered`/`.hidden` (trang đẩy vào) **tự ẩn thanh tab** dưới đáy (1.3.660) — chỉ tab gốc còn thanh tab; đừng gắn `.toolbar(.hidden, for: .tabBar)` riêng, và trang đẩy vào phải dùng đúng kiểu này. Ngoại lệ: Chi tiết truyện dùng `.hidden` (header là bìa lớn; mở từ mục lục Reader/Comic cũng là trang đẩy vào `NavigationStack` của màn đọc, không phải sheet/cover); Reader, màn đọc truyện tranh, trình phát video (và Khám phá) giữ header tự dựng. Nút chữ trên header (Lưu, Nhập, Xong, `Menu("Lưu")`, `EditButton`…) gắn `.headerTextButton()` (17pt nửa đậm; không kèm `.fontWeight`/`.bold()`); icon header 17pt nửa đậm. Sheet **không** có nút chỉ để đóng (Huỷ/Đóng/✕/Xong không lưu): vuốt xuống + `.presentationDragIndicator(.visible)`; nút trái khác dời sang phải dạng icon; mỗi nút header chỉ chữ **hoặc** chỉ icon. Sheet có nội dung chưa lưu: `.confirmDiscardOnSwipe(isDirty:onDiscard:)` (`Common/SheetDismissGuard/`). Màn toàn màn (`fullScreenCover`) giữ lối đóng. Giải thích của section: nút "?" `SectionHelpHeader`/`SectionHelpButton` cạnh tiêu đề, không viết footer giải thích (footer chỉ cho số liệu/trạng thái). Kiểu Danh sách: hàng là panel bo góc `.bookListPanelRow`, không vạch ngăn; ngăn kéo menu không vạch ngăn.
- **Mục lục & thẻ Chi tiết (1.3.662)**: tab Mục lục của Chi tiết, sheet mục lục Reader và màn đọc comic dùng chung panel ở `Sources/Views/Common/ChapterTOCPanel/`: `ChapterTOCPanelHeader` ("Mục lục (N chương)" trắng + nút ↓↑ 17pt + ô tìm viên thuốc "Tìm kiếm N chương"), `.chapterTOCPanel(_:)` (nền bo hai góc trên, kéo tới đáy, chỉ danh sách cuộn) và `ChapterTOCPalette` (`.system` / `.reader(theme)` — nền đọc Sáng/Trầm ấm dùng màu chữ của nền thay cho trắng). Nút đảo thứ tự nằm ở đầu panel, bìa sheet mục lục không còn dải số chương. Mục lục mới thì dựng bằng các mảnh này. Thẻ của tab Chi tiết (Thông tin, Thể loại, Giới thiệu, đề xuất, bình luận) là `BookDetailSectionCard` (ô `trailing` cho "Xem thêm ›"); màn tất cả bình luận là panel `.bookListPanelRow()`.

## Tests

**Coi `Tests/` như không tồn tại.** Theo yêu cầu của người dùng, từ nay bỏ qua hoàn toàn tầng test: **không** tạo, sửa, đổi tên, xoá, format, chạy hay đọc bất kỳ file nào dưới `Tests/`; **không** dùng test (đang có hay giả định) làm bằng chứng cho tính đúng; **không** báo "đã test" hay "test pass". Xác minh chỉ dựa trên đọc code, build (khi có macOS) và validator tĩnh (`check_architecture.py`). Truy vấn cấu trúc dùng `codegraph explore` / `codegraph_explore`.

Luật này **chặt hơn và bao trùm** Test Lock Rule ở `.agents/AGENTS.md` §2.1 và mục "Test Placement" của `rules.md` (vốn chỉ cấm tạo/sửa test). Khi hai bên xung đột, áp luật này. `.agents/AGENTS.md` và `rules.md` giữ nguyên văn — không sửa chúng theo luật này trừ khi người dùng yêu cầu.

## Bẫy đã xác minh & sai lệch tài liệu

`rules.md` là tài liệu quy phạm có thẩm quyền cao nhất, **nhưng vài chỗ đã cũ hơn code**. Ở các điểm dưới đây phải đánh dấu `UNKNOWN` và hỏi người dùng, **không** tự sửa code để khớp rules.md:

1. **`Scripts/check_architecture.py` không phải build gate.** `rules.md` không yêu cầu chạy nó (chỉ nhắc `architecture_allowlist.json` như baseline), và step chạy nó đã bị bỏ khỏi `build-ipa.yml` theo quyết định của maintainer. Nó là tool local — vẫn nên chạy, nhưng không ai chặn merge vì nó.
2. **`ReaderParagraphBuilder` và `TTSParagraphBuilder.build(from:)` là API chỉ test dùng.** Production dựng `[ParagraphItem]` ở `Sources/Views/Reader/Extensions/ReaderViewModel+Translation.swift` (logic gần như copy y nguyên của `ReaderParagraphBuilder.build`, thêm `Task.checkCancellation()` mỗi 5 dòng) và dựng chunk qua `TTSBackgroundProcessor` → `TTSParagraphBuilder.buildFromEntries`. Cả `ReaderParagraphBuilder` và overload `build(from:chunkLength:)` **không có caller nào trong `Sources/`**. Sửa logic dựng đoạn phải sửa **cả hai bản**.
3. **`ReaderRoute` không nằm trong thư mục Reader.** Nó khai ở `Sources/Views/BookDetail/BookDetailView.swift:4`; một type khác `ShelfReaderRoute` ở `Sources/Views/Shelf/ShelfMain/ShelfView.swift:5`. Không có file `ReaderRoute.swift` nào.
4. **`ReaderSelectionCoordinator` bị đặt tên sai** — nó chỉ làm tra Hán-Việt và format chữ hoa/thường, không liên quan gì tới selection.
5. **`codegraph_callers` không đủ 100%**: nó bỏ sót lời gọi tĩnh qua tên type (`TranslateUtils.xxx(...)` → báo 0 caller trong khi grep thấy 12) và lời gọi qua biến/optional từ View (`viewModel?.saveProgressImmediately()`). Dùng codegraph để **định vị và đọc**; trước khi **xoá** hay **đổi chữ ký** một member, phải grep chéo toàn `Sources/` để có danh sách caller đầy đủ.
