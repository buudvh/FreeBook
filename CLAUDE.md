# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> File này và `AGENTS.md` ở thư mục gốc là **cùng một nội dung**, chỉ khác 3 dòng đầu (một bản cho Claude Code, một bản cho Codex). Sửa file này thì mirror sang `AGENTS.md`.

## Bắt buộc đọc trước khi sửa code

Repo này có quy trình AI riêng, **ưu tiên cao hơn hướng dẫn mặc định**:

1. `.agents/AGENTS.md` — workflow 8 bước bắt buộc cho mọi AI assistant.
2. `Docs/CodeGraph/00_index.md` — mục lục hệ thống tài liệu sống (16 tài liệu, phủ 218 file Swift).
3. `Docs/CodeGraph/rules.md` — quy chuẩn kỹ thuật + checklist tự kiểm tra.

**Thứ tự thẩm quyền khi xung đột**: `rules.md` > Source Code > `Docs/CodeGraph/*` > tài liệu khác. Nếu không đủ bằng chứng để phân biệt sai lệch là chủ ý hay bug, phải đánh dấu `UNKNOWN` và hỏi người dùng — không tự suy đoán. **Nhưng đọc mục "Sai lệch đã biết" ở cuối file trước**: `rules.md` có chỗ đã cũ hơn code, đừng sửa code chỉ để khớp nó.

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
xcodebuild test ... -only-testing:FreeBookTests/ChapterTextNormalizerTests
xcodebuild test ... -only-testing:FreeBookTests/ChapterTextNormalizerTests/testNormalizationIsIdempotent
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

**Script hiện đang đỏ** (baseline đã trôi so với code). Vì vậy: chạy nó *trước* khi sửa, chạy lại *sau*, và chỉ chịu trách nhiệm cho violation mới do mình gây ra. Đừng "sửa cho xanh" bằng cách nới baseline nếu người dùng không yêu cầu.

## Architecture

`Sources/` có 5 tầng: `App` (chỉ `FreeBookApp.swift`) / `Common` / `Models` / `Services` / `Views`. Chiều phụ thuộc: Views → ViewModel/Coordinator → Services/Repositories → Models. 218 file Swift.

### Trục dọc quan trọng nhất: normalize → paragraph → chunk → highlight

Đây là nơi tập trung phần lớn độ phức tạp và cũng là nguồn bug hay gặp:

```
ChapterContentRepository            memory → SwiftData → extension fetch
  └─ ChapterTextNormalizer          nguồn DUY NHẤT chuẩn hoá newline, bỏ dòng trống,
                                    gán paragraph ID, tính NSRange UTF-16
       └─ ChapterDocument           tạo MỘT lần, Reader và TTS cùng dùng
            ├─ ReaderParagraphBuilder → [ParagraphItem] (original + translated + translationSpans)
            └─ TTSParagraphBuilder    → [TTSParagraph] (chunk theo dấu câu, giữ parent line ID)
```

**Bất biến bắt buộc**:

- Chỉ `ChapterTextNormalizer` được chuẩn hoá text chương. Reader/TTS builder tiêu thụ dòng đã normalize, **không tự tách lại hay đánh số lại**.
- Mọi offset trao đổi với UIKit là `NSRange` ngữ nghĩa **UTF-16**, không phải `String.Index`.
- TTS chunk có thể cắt một dòng nhưng phải giữ `ChapterTextLine.id` của dòng cha (`TTSParagraph.paragraphIndex`). Chunk tiêu đề chương dùng `paragraphIndex = -1`.
- Khi TTS đang phát, **TTS sở hữu tiến độ đọc**; snapshot của Reader bị bỏ qua.

**Hệ toạ độ highlight — đọc kỹ, tài liệu cũ nói ngược:**

`TTSParagraph.range` là offset UTF-16 **trên chuỗi đang được hiển thị** (`TTSLineEntry.translatedText` — tức bản dịch khi bật VietPhrase, bản gốc khi tắt), và **tương đối với dòng cha**, không phải tuyệt đối theo chương. `TTSParagraph.sourceRange` mới là range ánh xạ về text gốc.

Lý do: `TTSBackgroundProcessor.processChapter` dịch **từng dòng trước**, rồi `reconstructContentPreservingLineIDs` → `normalizeProcessedContent`, nên `normalizedContent` của TTS và `ParagraphItem` của Reader nằm cùng một hệ toạ độ. Vì vậy `ReaderView` truyền `ttsState.snapshot.highlightRange` **thẳng** xuống `ParagraphCardView` → `ReaderTextView` không ánh xạ gì (guard theo `playingBookId`, `playingChapterIndex`, `currentParentParagraphIndex`). Hàm `ReaderSelectionMapper.mapHighlight` đã bị **xoá** ở 1.3.81 — đừng gọi lại nó.

`ReaderSelectionMapper` giờ chỉ còn chiều ngược cho *selection* của người dùng: `mapSelection(_:in:isTranslationEnabled:bookId:)` map từ chuỗi dịch về text gốc để tra từ điển, ưu tiên `translationSpans`, fallback heuristic câu/token khi span rỗng hoặc không phủ hết.

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

- **Logging**: chỉ `AppLogger.shared.log(...)` → `app_logs.txt` trong `Documents`. Không `print`. App chạy thật qua LiveContainer trên máy iOS vật lý nên **không đính được debugger, Xcode Console vô dụng** — log file là kênh duy nhất. Không log secret hay full payload chương.
- **SwiftData**: không viết predicate lọc chuỗi trong `@Query` (bộ dịch SQLite iOS 17 lỗi) — query hết rồi lọc trên RAM bằng computed property. Tác vụ nền phải tạo `ModelContext` riêng từ `ModelContainer`, không dùng chung context của MainActor.
- **Ghi SwiftData** đi qua `BookTransactionCoordinator` / `ExtensionTransactionCoordinator` với Command DTO bất biến; View chỉ `@Query` để đọc.
- **Toast từ tầng nền**: Service phát event qua `TTSPresentationEventCenter` / `DownloadPresentationEventCenter` (`AsyncStream`); `AppLaunchRootView` là subscriber UI duy nhất.
- **Không chặn Main Thread** bằng `DispatchSemaphore` khi chờ `WKWebView` (bypass Cloudflare) — deadlock vĩnh viễn. Dùng `withCheckedContinuation`.
- **Tiến độ đọc**: chỉ lưu DB khi lệch ≥ 3 đoạn, debounce 3 giây (`ReaderViewModel.dbSaveTask`); lưu ngay khi `scenePhase == .background` — **không** hook `.onDisappear`.
- **Huỷ vs flush**: khi nội dung chương đã qua checkpoint cancel cuối và vào memory chia sẻ, lệnh ghi nền **không được cancel**. Reader dismiss thì *flush* pending write. Một load đang bay có thể phục vụ nhiều subscriber: cancel một subscriber chỉ resume waiter đó bằng `CancellationError`; task gốc chỉ dừng khi waiter cuối rời đi. `CancellationError` không được ghi trạng thái lỗi hay tính là synthesis failure.
- **Xoá sách**: `BookStorageManager` là điều phối viên duy nhất — `ModelContext.save()` thành công rồi mới xoá file nền. Mọi thao tác file phải qua `validatePathSafety(for:)`; xoá thất bại đẩy vào queue `failed_file_deletions_queue` (UserDefaults), retry tối đa 3 lần lúc khởi động.

<!--MORE-->




