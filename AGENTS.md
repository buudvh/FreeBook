# AGENTS.md

This file provides guidance to AI coding agents (Codex, Claude Code, …) when working with code in this repository.

> `CLAUDE.md` chỉ chứa `@AGENTS.md` (Claude Code nạp file này qua import) — hướng dẫn chung **chỉ sửa ở đây**, không còn bản mirror. Ghi chú riêng từng phân hệ nằm ở `.claude/rules/*.md` (mục lục ở mục "Ghi chú theo phân hệ" bên dưới); ghi chú mới của một phân hệ thì thêm vào đúng file đó, không thêm vào đây.

## Bắt buộc đọc trước khi sửa code

Repo này có quy trình AI riêng, **ưu tiên cao hơn hướng dẫn mặc định**:

1. `.agents/AGENTS.md` — workflow 8 bước bắt buộc cho mọi AI assistant.
2. `Docs/CodeGraph/rules.md` — quy chuẩn kỹ thuật + checklist tự kiểm tra (tài liệu có thẩm quyền cao nhất).
3. `CHANGELOG.md` — lịch sử thay đổi theo version `[1.3.NNN]`.

**Điều hướng cấu trúc**: thay vì đọc doc MB, hãy dùng công cụ MCP **`codegraph_explore`** (hoặc CLI `codegraph explore "<câu hỏi>"`) — nó trả source verbatim + call paths + quan hệ trong một lần gọi. Index nằm ở `.codegraph/` (tự động đồng bộ khi file đổi; build bằng `codegraph init`). Nếu agent không có MCP, fallback CLI `codegraph explore`. **Agent được tự chạy `codegraph sync` khi cần** — ví dụ codegraph báo *"pending index sync"*, kết quả rõ ràng cũ hơn code vừa sửa, hoặc sau `git pull`/đổi nhánh; chỉ `codegraph init` (build lần đầu) mới là việc của người dùng.

**Thứ tự thẩm quyền khi xung đột**: `rules.md` > Source Code > `CHANGELOG.md` > tài liệu khác. Nếu không đủ bằng chứng để phân biệt sai lệch là chủ ý hay bug, phải đánh dấu `UNKNOWN` và hỏi người dùng — không tự suy đoán. **Nhưng đọc mục "Bẫy đã xác minh & sai lệch tài liệu" ở cuối file trước**: `rules.md` có chỗ đã cũ hơn code, đừng sửa code chỉ để khớp nó.

Sau khi sửa code: cập nhật `CHANGELOG.md` (version `[1.3.NNN] - YYYY-MM-DD`, tăng NNN mỗi thay đổi; tiêu đề entry **trùng với subject của git commit**), và **kết thúc response bằng một trong hai cụm**: `"CodeGraph updated."` hoặc `"No CodeGraph update required."` (giữ quy ước này cho nhất quán dù không còn validator). Khi cần hiểu/sửa cấu trúc, ưu tiên `codegraph_explore` thay vì đọc file lớn.

Luôn thêm entry mới vào `CHANGELOG.md`; khi file vượt ~30 entry thì đẩy phần cũ nhất sang `CHANGELOG.archive.md` (chỉ để tra cứu, không bao giờ ghi mới vào đó) để giữ file chính gọn token.

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

**Không còn validator `validate_links.py`.** Phần "đồ thị cấu trúc" của CodeGraph đã nghỉ hưu, thay bằng công cụ **`codegraph` MCP** (Rust/Node, 100% local, tự động đồng bộ index khi file đổi). Mọi truy vấn cấu trúc (tìm symbol, call path, blast radius) dùng `codegraph_explore` MCP hoặc CLI `codegraph explore` — **không** đọc doc MB.

## Build, CI & môi trường

**Lưu ý môi trường**: build chỉ chạy được trên macOS. Repo hay được mở trên Windows — khi đó không build tại chỗ được; phải nói rõ điều đó thay vì báo "đã kiểm chứng".

**CI không phải test gate.** `.github/workflows/build-ipa.yml` chỉ `xcodegen generate` → `xcodebuild archive` (unsigned) → đóng gói IPA + nhồi `espeak-ng-data` → gửi Telegram. Nó **không chạy unit test, không chạy `check_architecture.py`, cũng không truy vấn `codegraph` MCP**, và chỉ trigger khi đổi `Sources/**` hoặc `project.yml`. Nghĩa là CI xanh = *biên dịch được*, không phải *đúng*. Build local cần chạy `Scripts/ci/build_audiocpp_ios.sh` trước `xcodegen` (thư mục `Vendor/AudioCpp/` bị gitignore).

- **Đừng bật lại WMO / dSYM** cho Release (`project.yml` › `settings.configs.Release` dùng `singlefile`, không dSYM — cố ý, WMO làm archive trên CI chậm gấp đôi) nếu anh Bửu không yêu cầu.
- **Version app = số bản đầu `Docs/CodeGraph/CHANGELOG.md`** (CI đọc làm `MARKETING_VERSION`) ⇒ commit quên thêm entry CHANGELOG thì version không đổi, chỉ số build tăng.
- Chi tiết CI, AudioCpp, chế độ biên dịch Release, nguồn LiveContainer, tin Telegram, báo bản mới trong app: `.claude/rules/ci-release.md`. Thiết lập codegraph trên máy mới: skill `.claude/skills/codegraph-setup/SKILL.md`.

`GOOGLE_CLOUD_TTS_API_KEY` đi từ GitHub secret → build setting → `Info.plist` (`project.yml` khai `GOOGLE_CLOUD_TTS_API_KEY: "$(GOOGLE_CLOUD_TTS_API_KEY)"`, workflow còn `plutil -replace` vào IPA). Build local không có key thì Google TTS im lặng không hoạt động — không phải bug.

## Kỷ luật kiến trúc (có script cưỡng chế)

`Scripts/check_architecture.py` quét `Sources/` và enforce 6 luật:

| Luật | Nội dung |
|---|---|
| `FILE_SIZE_LIMIT` / `NEW_FILE_TOO_LARGE` | file Swift mới ≤ **400 dòng vật lý**; file legacy dùng baseline riêng và **chỉ được giảm** |
| `MULTI_PRIMARY_TYPES` | đúng **1** type chính (class/struct/enum/actor) ở top level mỗi file |
| `VIEW_SWIFTDATA_MUTATION` | `Sources/Views/**` không được `modelContext.insert/delete/save`; 6 view lớn còn bị cấm gán trực tiếp thuộc tính `@Model` và cấm bỏ qua `Result` của coordinator |
| `SERVICE_TOAST_COUPLING` | `Sources/Services/**` không được gọi `ToastManager.shared` |
| `SERVICE_SWIFTUI_IMPORT` | `Sources/Services/**` không được `import SwiftUI` (trừ `*WebViewLoader.swift`) |
| `WHITE_TINT_FILL` | `Sources/Views/**` không tô nền đặc bằng `Color.accentColor` (mờ < 50% thì được) và không dùng `.borderedProminent` thiếu `.tint(<màu cố định khác trắng>)`. Tên luật có từ thời màu nhấn trắng (trắng trên trắng); từ 1.3.678 màu nhấn do người dùng chọn nên luật **giữ nguyên** với lý do mới: nền nhấn đổi theo lựa chọn, màu chữ trên nó phải do một chỗ quyết định. Nút đặc mới dùng `.buttonStyle(.appFilled)` (`Sources/Views/Common/AppFilledButtonStyle.swift`, mặc định màu nhấn) |

Miễn trừ khai trong `Scripts/architecture_allowlist.json` (`schema_version: 2`, fail-closed). Mỗi entry có `expiresAt` — **script FAIL nếu entry hết hạn**. Chỉ có miễn trừ cho `FILE_SIZE_LIMIT` và `MULTI_PRIMARY_TYPES`; hai luật View-SwiftData và Service-Toast không có ngoại lệ nào.

**Script hiện đang đỏ** (baseline đã trôi so với code): 2 violation trên cây sạch (`JSDom.swift`, `TTSManager.swift` vượt baseline dòng; đếm lại ở 1.3.529). Vì vậy chạy nó *trước* khi sửa, chạy lại *sau*, và chỉ chịu trách nhiệm cho violation mới do mình gây ra. Đừng "sửa cho xanh" bằng cách nới baseline nếu người dùng không yêu cầu.

**Và `[PASS]` của script không phải bằng chứng.** Hàm `strip_comments_and_strings` (`check_architecture.py:53-60`) dùng regex `"([^"\\]|\\.)*"` để xoá string literal, nhưng regex này ghép sai dấu nháy khi gặp string interpolation Swift nên **ăn cả code thật**. Kết quả: `ShelfView.swift:757` và `BookDetailView.swift:239` đều có `try? modelContext.save()` thật mà script **không phát hiện**. Vẫn phải tự đọc code, đừng tin mỗi exit code.

## Architecture

`Sources/` có 5 tầng: `App` (chỉ `FreeBookApp.swift`) / `Common` / `Models` / `Services` / `Views`. Chiều phụ thuộc: Views → ViewModel/Coordinator → Services/Repositories → Models.

### Ghi chú theo phân hệ (nạp lười)

Chi tiết từng phân hệ nằm ở `.claude/rules/<file>`. Claude Code tự nạp file khi đọc / sửa file khớp `paths:` ở đầu file; agent khác (Codex…) **phải tự đọc** file tương ứng trước khi sửa phân hệ đó.

| File | Nội dung |
|---|---|
| `storage.md` | Bootstrap hai chỗ (`FreeBookApp` / `MainTabView`), schema SwiftData, mọi thư mục dữ liệu, màn Dung lượng, Dọn rác, bìa truyện |
| `reader-text-pipeline.md` | normalize → paragraph → chunk → highlight, hệ toạ độ highlight, Reader bridge UIKit |
| `tts.md` | `TTSManager`, 4 đường tổng hợp, thay thế từ theo token, cache / retry, giọng dự phòng, widget TTS |
| `tts-vieneu.md` | VieNeu Nano / Turbo, audio.cpp + AMX, Core ML, chọn / tải / nhân bản giọng, đọc lai, tên Nhật |
| `translation.md` | VietPhrase, `ChineseTextPipeline`, phồn → giản, tên chương, rule dịch nhanh, bộ dịch tiện ích |
| `extensions-js.md` | Bridge `JSExecutor`, `load()`, fetch lỗi ⇒ browser ẩn, "Mở link lỗi", bộ lọc theo tab, báo cáo kiểm tra |
| `comic-video.md` | Loại nội dung, router, comic, trình phát video, thu nhỏ / cửa sổ nhỏ, phụ đề + OCR, tải offline |
| `audio-playlist.md` | Âm thanh, màn khoá ba bên, tự phát gợi ý, playlist |
| `floating-pills.md` | Đĩa nghe nửa viên thuốc, hub, nút trình duyệt, vùng đứng cố định, `OverlaySheetPresenter` |
| `browser.md` | Chặn quảng cáo, chế độ máy tính, dịch QT + menu của trình duyệt người dùng |
| `books-sources.md` | Mở lại mục gần nhất khi khởi động, Đổi nguồn, Gắn lại nguồn khi tiện ích đã gỡ |
| `network-dns.md` | DNS mã hoá (DoH), relay 127.0.0.1, hướng proxy đã chốt |
| `ci-release.md` | CI, AudioCpp, Release `singlefile`, version, LiveContainer, Telegram, báo bản mới |
| `ui-conventions.md` | Header / toolbar, màu nhấn, `AppGlyph`, màn danh sách, nút Home nổi, header & sheet kính, mục lục, toast bấm được |

Bẫy dùng chung nhiều phân hệ (chi tiết ở file tương ứng):

- **`ChapterStoreConfiguration.enableSwiftDataTOCWrite = false`** ⇒ `Book.chapters` **rỗng** ở production; mục lục nằm ở `chapters/chapter_store.sqlite` (`storage.md`).
- Không có `VersionedSchema` / `SchemaMigrationPlan` — đổi shape `@Model` là việc nguy hiểm (`storage.md`).
- Mọi lối mở reader / màn xem phim / màn nghe đi qua `BookContentDestination` / `ContentDetailRouter`, đừng gọi `ReaderView(` trực tiếp (`comic-video.md`).
- `Book.currentChapterPage` có ba nghĩa theo loại: chỉ số đoạn (chữ), chỉ số ảnh (comic), số giây (video, âm thanh) (`comic-video.md`).
- Thêm kho dữ liệu mới ⇒ khai cả `StorageUsageCategory` / luật Dọn rác (`storage.md`), và nếu theo `bookId` thì cả `copyBookScopedSettings` / `removeBookScopedSettings` (`books-sources.md`).

## Ràng buộc runtime cần nhớ

- **Logging**: chỉ `AppLogger.shared.log(...)`. Từ 1.3.948 log lưu bằng **SQLite theo phiên** ở `applicationSupportDirectory/app_logs.sqlite` (`AppLogDatabase`, chỉ dùng trên queue của logger; **không** phải `Documents`): mỗi lần mở app là một phiên kèm thông tin đầu phiên (`AppLogSessionInfo`: version + build, máy, iOS, nhiệt / RAM / ổ trống, trình đọc TTS + giọng), ghi theo lô trên queue nền (64 dòng hoặc 0,5 s; dòng ❌ ghi ngay), vào nền / đóng app ⇒ ghi nốt đồng bộ + đánh dấu trạng thái phiên (phiên cũ còn `foreground` ⇒ "Chết đột ngột", phiên kế ghi giờ + dòng cuối của nó; LiveContainer chuyển app gọi `markSessionEnded`). Giữ 20 phiên / 30 MB. Màn Ghi log hệ thống chỉ có danh sách phiên: chọn ⇒ xuất **một** `.txt` (`AppLogger+Sessions`, đọc bằng kết nối riêng) hoặc xoá; `clear()` = xoá hết rồi mở phiên mới. File `app_logs*.txt` cũ bị xoá ở lần mở đầu (`AppLogFiles` đã bỏ). `AppLogger.init` **set `isLoggingEnabled = false` mỗi lần khởi chạy** (giữ nguyên ở 1.3.948) — thêm log mà không thấy gì thì là do đây, phải bật lại trong Settings. Ngoại lệ (1.3.517): dòng chứa `❌` (log lỗi) luôn được ghi dù công tắc tắt — log lỗi mới phải có `❌`, dòng thường không được gắn `❌` để lách công tắc; `AppLogger.logAlways` chỉ dành cho chẩn đoán fd (`FileDescriptorCensus`, `FileDescriptorStepProbe`, `FileDescriptorSweeper`). App chạy thật qua LiveContainer trên máy iOS vật lý nên không đính được debugger; log file là kênh duy nhất. Lúc bật log, `MainThreadHangMonitor` (1.3.965) ghi `🐢 [MainHang]` mỗi khi main kẹt ≥ 150 ms (gộp mỗi 10 s, ≥ 500 ms ghi ngay) kèm bối cảnh — tra giật / lag bằng dòng này; màn muốn hiện trong bối cảnh thì gọi `noteScreen(_:visible:)`. Không log secret hay full payload chương. (`AppLogger.log` tự gọi `print` bên trong — luật "không `print`" là không gọi trực tiếp ở nơi khác.)
- **SwiftData**: không viết predicate lọc chuỗi trong `@Query` (bộ dịch SQLite iOS 17 lỗi) — query hết rồi lọc trên RAM bằng computed property. Tác vụ nền phải tạo `ModelContext` riêng từ `ModelContainer`, không dùng chung context của MainActor.
- **Ghi SwiftData** đi qua `BookTransactionCoordinator` với Command DTO bất biến; View chỉ `@Query` để đọc.
- **Tiện ích & kho** (1.3.529): đọc qua `ExtensionLibraryRepository` (`@MainActor @Observable`; View đọc `.installed`/`.catalog` trong `body`, tầng nền dùng các hàm `nonisolated static` qua tên type như `ExtensionLibraryRepository.snapshot(packageId:)`), ghi qua `ExtensionTransactionCoordinator` (không còn tham số `in context:`). `Extension` là **struct** — biến giữ nó là bản chụp, sau khi ghi phải tra lại theo `packageId`. Luật chi tiết: mục "Extension store invariants (1.3.529)" trong `rules.md`.
- **Toast từ tầng nền**: Service phát event qua `TTSPresentationEventCenter` / `DownloadPresentationEventCenter` (`AsyncStream`); `AppLaunchRootView` là subscriber UI duy nhất.
- **Không chặn Main Thread** bằng `DispatchSemaphore` khi chờ `WKWebView` (bypass Cloudflare) — deadlock vĩnh viễn. Dùng `withCheckedContinuation`.
- **Tiến độ đọc**: chỉ lưu DB khi lệch ≥ 3 đoạn, debounce 3 giây (`ReaderViewModel.dbSaveTask`); lưu ngay khi `scenePhase == .background` — **không** hook `.onDisappear`.
- **Huỷ vs flush**: khi nội dung chương đã qua checkpoint cancel cuối và vào memory chia sẻ, lệnh ghi nền **không được cancel**. Reader dismiss thì *flush* pending write. Một load đang bay có thể phục vụ nhiều subscriber: cancel một subscriber chỉ resume waiter đó bằng `CancellationError`; task gốc chỉ dừng khi waiter cuối rời đi. `CancellationError` không được ghi trạng thái lỗi hay tính là synthesis failure.
- **Xoá sách**: `BookStorageManager` là điều phối viên duy nhất — `ModelContext.save()` thành công rồi mới xoá file nền. Mọi thao tác file phải qua `validatePathSafety(for:)`; xoá thất bại đẩy vào queue `failed_file_deletions_queue` (UserDefaults), retry tối đa 3 lần lúc khởi động.
- Mở lại mục gần nhất khi khởi động, Đổi nguồn, Gắn lại nguồn ⇒ `.claude/rules/books-sources.md`; DNS mã hoá / proxy ⇒ `network-dns.md`; toast bấm được ⇒ `ui-conventions.md`.

## Quy ước đặt tên & cấu trúc

- **Từ "Extensions" bị dùng cho 4 nghĩa khác nhau** — bẫy đặt tên tệ nhất repo này:
  - `Sources/Services/Extensions/` = phân hệ **plugin JavaScript (tiện ích)**
  - `Sources/Views/Extensions/` = **màn hình quản lý** plugin
  - `Sources/*/*/Extensions/` = file `extension` **Swift** thuần
  - `struct Extension` trong `Sources/Models/Extensions/Extension.swift` = **bản ghi tiện ích** (JSON, không còn là `@Model` từ 1.3.529)

  Đường dẫn `Sources/Views/Extensions/Manager/Extensions/RepositoryManagerView+Actions.swift` chứa hai nghĩa khác nhau của cùng một từ. Đọc kỹ path trước khi kết luận.
- **Tách file kiểu `X+Feature.swift`** (vd `TTSManager+Playback`, `ReaderViewModel+Translation`) là cách repo giữ god-object dưới baseline dòng. Muốn thêm code vào một type lớn thì thêm vào file `+` phù hợp (hoặc tạo file mới), đừng làm file gốc phình thêm.
- **Chỉ có 5 ViewModel thật**: `ReaderViewModel`, `FloatingWidgetViewModel`, `FloatingHubViewModel`, `ComicReaderViewModel` và `VideoPlayerController` (1.3.531), đặt cạnh view của nó chứ không có thư mục `ViewModels/`. Mọi màn khác dùng `@State` trong View + projection reader.
- Hậu tố quyết định vai trò (theo `rules.md`, và code tuân thủ khá sát): `Repository` = single source of truth cho một domain, `Store` = engine lưu trữ mức thấp, `Coordinator` = chủ transaction/flow, `Worker` = actor/task nền, `Snapshot` = bản sao bất biến qua ranh giới isolation, `Command`/`DTO` = payload bất biến, `Mapper`/`Formatter` = converter thuần, `Engine` = thực thi mức thấp.
- **View không observe trực tiếp `TTSManager`** — dùng projection reader (`TTSWidgetStateReader`, `TTSRootPresentationReader`, `ReaderTTSStateReader`). `ReaderTTSStateReader.scope(to: bookId)` làm snapshot của sách khác thành inactive để Reader ngoài màn hình không redraw theo mỗi bước highlight.
- **NotificationCenter vẫn là event bus liên module nhưng phần lớn tên là string literal trần** — đổi tên là vỡ ngầm, grep cả hai đầu: `"openCurrentlyPlayingReader"`, `"navigateReaderToPlayingChapter"`, `"ttsDidAdvanceToNextChapter"`, `"sourceChangedNavigateToShelf"`, `"extensionDidUpdate"`. Chỉ 2 tên có hằng số kiểu: `.translationDictionariesDidUpdate` và `VisibleBrowserTabManager.stateDidChangeNotification` — nhưng `TTSManager` vẫn observe tên thứ nhất bằng string trần. Signalling mới thì dùng `AsyncStream` event center, đừng thêm notification string mới.
- Comment, chuỗi lỗi và log message viết **tiếng Việt**; tên type/member viết tiếng Anh. Comment kiến trúc mới thì tiếng Anh. Cả hai đều bình thường ở đây — giữ theo file đang sửa.
- **Nội dung nhạy cảm chỉ ghi "NSFW" hoặc "nội dung nhạy cảm"** — không ghi "18+" (anh Bửu, 1.3.1019): áp cho chữ trên màn hình, toast, comment, log, tài liệu. Ngoại lệ: từ khoá nhận diện `"18+"` trong `ExtensionNsfwClassifier` (bắt tiện ích tự ghi 18+ trong tên), dữ liệu mẫu thẻ tiện ích, emoji 🔞 đầu dòng log, entry CHANGELOG cũ. **Mờ bìa NSFW** (1.3.1019, công tắc chung `nsfwCoverBlurEnabled`, mặc định tắt): `BookCoverView` tự xét `isNsfwBook`; `RemoteCoverImage` chỉ mờ khi màn đặt `.nsfwCoverContext(nguồn NSFW)` (`NsfwCoverBlurModifier`) — màn danh sách mới của một nguồn phải gắn cờ này, màn xem phim / nghe / playlist / avatar cố ý không gắn.
- **Chuẩn UI bắt buộc** (header / toolbar, màu nhấn, `AppGlyph`, màn danh sách, nút Home nổi, header & sheet kính, mục lục & thẻ Chi tiết) ⇒ `.claude/rules/ui-conventions.md` — đọc trước khi sửa `Sources/Views/**`.

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
