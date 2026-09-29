# FreeBook — ghi chú dài hạn (đã nén)

## Quy ước với người dùng
- Trả lời **tiếng Việt**, giữ thuật ngữ kỹ thuật tiếng Anh inline.
- **Không đoán UI.** Đọc code view thật; mọi khẳng định cấu trúc phải dẫn `file:line`. Repo không có ảnh chụp màn hình, môi trường **Windows** (không có Simulator) ⇒ mockup chỉ là **wireframe đúng cấu trúc**, phải nói rõ giới hạn. Đã sai 2 lần do grep đoạn đầu file rồi kết luận cả file (vd `SettingsView.swift:308` mới có `navigationTitle`).
- Kế hoạch → `Docs/Plans/YYYY-MM-DD-plan-<slug>.md`; báo cáo → `Docs/Reports/YYYY-MM-DD-<topic>.md`. **Không** ghi vào `Docs/CodeGraph/`.

## Quy trình bắt buộc sau khi sửa code
Đọc `AGENTS.md` + `.agents/AGENTS.md`. Rồi: (1) `validate_links.py --explain`; (2) sửa **chỉ trong** `<!-- GENERATED START -->…<!-- GENERATED END -->`; (3) `--accept <n>` / `--no-change-needed <n>`; (4) thêm `CHANGELOG.md` `[1.3.NNN] - YYYY-MM-DD`, tiêu đề **trùng subject commit**; (5) validator read-only PASS 100%; (6) kết thúc bằng `"CodeGraph updated."` hoặc `"No CodeGraph update required."`

## Bẫy môi trường & công cụ
- **Không build được trên Windows** ⇒ không bao giờ nói "đã kiểm chứng biên dịch".
- `Scripts/check_architecture.py` **đỏ sẵn** (~30 violation, baseline trôi): so trước/sau, chỉ chịu trách nhiệm violation mới.
- `[PASS]` của script **không phải bằng chứng**: `strip_comments_and_strings` (`check_architecture.py:53-60`) ăn nhầm code thật khi gặp string interpolation ⇒ `ShelfView.swift:757`, `BookDetailView.swift:239` có `try? modelContext.save()` thật mà script không thấy.
- Grep phải **scope `Sources/`** (`Tools/` >4000 file → timeout). `00_index.md` quá lớn → `offset`/`limit`.
- **`validate_links.py` short-circuit khi cây sạch**: PASS dù doc stale ⇒ phải chạy `--explain` **khi cây đã có thay đổi**; phân định nợ cũ/mới: `git stash push -- Sources/ Docs/` → chạy → `git stash pop`.

## Ràng buộc kiến trúc
- `Sources/Services/**` **không** `import SwiftUI` ⇒ singleton hướng-SwiftUI phải ở `Sources/Common/**` (tiền lệ `ToastManager`).
- File Swift mới ≤ **400 dòng**, **1 type chính** top level. `Sources/Views/**` không `modelContext.insert/delete/save`.
- Trần dòng legacy: `SettingsView.swift` **452/453 — còn 1 dòng**; `ReaderView.swift` 2002/2053; `ReaderViewModel.swift` **918/830 — đang vượt**. `DeveloperSettingsSection.swift:4` tự ghi: mọi mục mới của Settings phải ra file riêng.
- `BackupCoordinator.swift` trần 400 là ràng buộc thật ⇒ tính năng mới phải ra file extension; extension **không** ghi được `isBusy`/`progress` (`private(set)`) trừ khi mở `setBusy`/`setProgress` như `+AutoDrive`.
- Gốc skill: `.agents/skills/` = **Antigravity đọc** (hiện có `antigravity`, `claude-cli`, `push-ci-monitor`, `vbook_helper`); `.claude/skills/` = chỉ Claude Code. `.claude/` **bị gitignore**, `.agents/` và `.workbuddy-ai/` được track.
- **WorkBuddy đọc skill ở**: `~/.workbuddy-ai/skills/` (user-level) và `<workspace>/.workbuddy/skills/` (project-level). `<workspace>/.workbuddy-ai/skills/` **KHÔNG** được quét — dễ nhầm nhất.
- `grill-me` có **3 bản** (`.claude/`, `.workbuddy/`, `~/.workbuddy-ai/`) — sửa 1 bản phải copy sang 2 bản còn lại. Hết phiên grill nó tự ghi plan vào `Docs/Plans/YYYY-MM-DD-plan-<slug>.md` — chính là artifact cho bước "Duyệt" của `push-ci-monitor`.

## Điều hướng app (dễ đoán sai)
- **4 tab**: Kệ Sách / Khám Phá / Tiện Ích / Cài Đặt (`MainTabView.swift:12-37`). **Không có tab Tìm kiếm** (tìm kiếm nằm trong `ShelfSearchView` và `ReaderSearchView`).
- `.tint(.accentColor)` duy nhất ở `MainTabView.swift:38`. **Khám Phá ẩn nav bar** (`DiscoveryView.swift:346`) ⇒ header tự dựng.
- Chi tiết truyện: thanh tab `Chi tiết`/`Mục lục` **ngay dưới nav bar**; bìa/tên/giới thiệu nằm **trong** tab `Chi tiết` (`BookDetailView.swift:206-232`, header `:368`).
- BookDetail / RepositoryManager / Shelf / Discovery dùng `TabView(.page)` + cổng `renderedTab` + `asyncAfter(0.15s)`. **Không đụng cơ chế này khi sửa UI.**
- Thanh chọn tab có 2 kiểu: Kệ sách = nút rời (`ShelfTabSelectorView`); Tiện Ích = `Picker(.segmented)`.

## Phân hệ Backup
- Bản sao lưu trong máy là bản **tạm**: upload xoá file local **sau khi** đích tự xác nhận (`removeLocalCopyAfterUpload`). Cố ý: bấm tay = **1 archive → 1 đích**; muốn cả Drive + Telegram thì dùng `+AutoDrive`.
- **Hai hàng rào xoá khác nhau, đừng "thống nhất"**: `BackupPaths.isAutoBackupFileName` (tiền tố `freebook-auto-`) chặn phép dọn **ngầm**; `LocalBackupStore.deleteAll()` **cố ý** không lọc tiền tố.
- `backups/` chứa cả file tạm của worker ⇒ **không bao giờ xoá cả thư mục**; duyệt `list()` rồi xoá từng archive.

## Phân hệ TTS (dễ đoán sai)
- Engine chọn bằng chuỗi `TTSManager.tool` ∈ {`system`, `nghitts` (Piper ONNX local), `google`, `<packageId extension>`} (`TTSManager.swift:92`; picker `Views/TTSWidget/TTSSettingsView.swift:73-76`). **121 chỗ** so chuỗi `"nghitts"` trên 11 file; `tool != "system" && tool != "nghitts" && tool != "google"` = "là extension tool" ⇒ thêm engine mới mà sót predicate là bị đối xử sai.
- **`TTSManager.swift` 4026 dòng > baseline 3470** (violation nền) ⇒ ratchet-down: code mới **phải** vào `Sources/Services/TTS/Extensions/TTSManager+*.swift`.
- `NghiAudioPlayerQueue` dùng `AVAudioPlayer(data:)` ⇒ sample-rate agnostic (24 kHz không cần sửa). `TTSAudioSynthesisWorker` đã generic theo `engine: String`.
- Repo cũ `VieNeuTTS-Offline` gọi "v3 Nano" nhưng thực chất chạy **v3-Turbo AR** (KV cache + MOSS 48 kHz, trần `maxNewFrames` 80 = 6,4 s audio). Nano thật = flow-matching **non-AR**, 24 kHz, 48M params, không KV cache, không cần BPE tokenizer.
- CoreML EP: repo cũ **đã bỏ có chủ ý** (KV cache zero-dim + external-data crash) ⇒ đừng thử lại cho kiến trúc AR.

## Tài liệu local (gitignored)
- `.gitignore:7-10` chặn `/Docs/Result`, `/Docs/Plans`, `/Docs/CheckList`, `/Docs/Reports` ⇒ plan/báo cáo là artifact **local**, không commit, và **không** làm `validate_links.py` stale. `Docs/Plan/` (số ít) thì **được track** (spec feature).

## CHANGELOG
- Giữ **30** entry, vượt thì đẩy entry cũ nhất sang `CHANGELOG.archive.md` (mới nhất trước).
- **2 vấn đề chưa sửa**: (a) drift lên 43 entry; (b) **thiếu hẳn 1.3.323–1.3.328** ở cả 2 file (archive dừng 1.3.322, CHANGELOG bắt đầu 1.3.329) trong khi doc vẫn tham chiếu ⇒ một lượt lưu trữ trước đây đã mất entry (lấy lại từ `git log`). **Đừng tự đẩy sang archive khi chưa kiểm chứng.**
- Thêm file Swift mới ⇒ `00_index`, `02_file_graph`, `09_dependency_rules`, `14_complexity_report` + `11_subsystems` cùng stale (sửa cả 5 vùng GENERATED rồi `--accept`); sửa `Sources/Common/**` thì `03_type_graph` cũng stale.

## Hiệu năng Reader — bẫy đã xác minh (2026-09-13)
- **Đọc `Docs/Reports/` trước**: `2026-09-10-reader-tts-perf-review.md` đã trôi — RC-5 **đã sửa**, RC-9 và P-2 **đã sai**.
- Nút "Cập nhật" ở panel Dịch mặc định lưu phạm vi **"R" (Riêng)** (`ReaderView.swift:123`) ⇒ chỉ bump `bookGenerations[bookId]`, **không** phải `globalGeneration`.
- **`ChapterCache` không có trần**; chỉ dọn khi Memory Warning (`ReaderViewModel.swift:678`). Từ 1.3.375 `applyNavigationCommit` gọi `queueRelease` thật (cửa sổ ±3); `queueRelease` **phải** là `Task { @MainActor }` vì `performRelease` gỡ khoá trong `cache` (`@Observable`). Bài học: đánh thức code chết phải rà an toàn luồng trước.
- `ReaderDefinitionOverlayView` dựng 1 `Text` cho **mỗi đơn vị UTF-16** của cả đoạn (`:182-202`, `HStack` không lazy); cùng mẫu ở `ReaderJunkDeleteOverlayView` và `ReaderCopyOriginalOverlayView` ⇒ mọi thay đổi UI ở 3 panel này phải tính chi phí N view.
- `TranslationWordToken.id` là `UUID()` sinh trong `init` (`TranslationWordToken.swift:4`) ⇒ `ForEach` mất khả năng diff **mọi** lượt nạp, `.onChange(of: translationTokens.map(\.id))` luôn nổ.
- `ReaderEnergyDiagnostics.isEnabled` chốt một lần trong `beginReaderSession()` ⇒ phải bật `AppLogger.isLoggingEnabled` **trước khi mở Reader**.
- `originalSentence` (panel Dịch) là **MỘT ĐOẠN VĂN**, không phải cả chương (`ReaderView.swift:1494` ← `item.original`); đoạn thật 9–173 ký tự (TB ~28) ⇒ **đo N thật** trước khi "sửa O(N) view". Rủi ro chỉ thành thật với nguồn trả cả chương thành 1 dòng, vì `ChapterTextNormalizer.normalizeInternal` (`:24-52`) **chỉ tách theo `\n`**.

## `FrozenTrieDictionary` — hai đường tra cứu (2026-09-13)
- `dat != nil` = nhanh, dừng sớm; `dat == nil` = duyệt `lengths` + `String(decoding:)` **mỗi độ dài**. `trieMatches` vẫn cấp phát `Array(text.utf16)` mỗi lần gọi.
- `dat == nil`: `customNamesDict`, `customVietPhraseDict`, **và `bookVP`/`bookNames`** (qua `TextDictionary.frozen()`). Từ điển `.dat` đi `DoubleArrayTrie.frozen()` ⇒ nhanh.
- Sau lần lưu từ điển đầu tiên chúng khác `nil` **vĩnh viễn** ⇒ mỗi vị trí ký tự × mỗi dòng × mỗi lượt dựng chương đều cấp phát thêm — nguồn đốt CPU (→ throttle) lớn nhất đã biết của pipeline dịch.
- Bẫy tối ưu: `VietPhraseTokenizer` truyền `checkText` + `startIndex: 0` **cố ý** để biên `limit`/`maxLimit` giới hạn vùng quét. Muốn truyền chuỗi gốc + `startIndex` thì chữ ký tra cứu **bắt buộc** thêm `maxLength`, nếu không kết quả dịch đổi.
- Phép thử "từ điển bật lên" vs "cache nguội": ghi `[ReaderPerf] TranslationRefresh totalMs` → Cập nhật 1 từ → ghi lại (tăng vọt, không hồi) → xoá từ điển riêng truyện → ghi lại (hồi nền = từ điển; không hồi = cache).

## Định tuyến engine TTS — `isLocalEngine` vs `isExtensionTool` (2026-09-29, 1.3.434)
- Hai hàm **khác câu hỏi**, đừng gộp: `TTSManager.isExtensionTool(_:)` = "extension do người dùng cài?"; `TTSManager.isLocalEngine(_:)` = "engine chạy trên máy + đi chung đường phát NghiTTS?" (`nghitts || vieneu`). Quên `isLocalEngine` ⇒ **im lặng** (không lỗi); quên `isExtensionTool` ⇒ **UI kiểu extension**.
- **`playAudioData` bắt buộc** định tuyến engine local sang `playNghiAudioData`; `updatePlaybackParams` chỉ đặt `rate` trên `nghiAudioPlayerQueue` ⇒ engine local đi nhầm nhánh `AVAudioPlayer` sẽ **không có tiếng và không ném lỗi**.
- **`NghiUtteranceSegmenter` KHÔNG phải Piper-only**: `playbackParagraphs` (`:801-803`) cho `vieneu` đi qua nó với `chunkLength` ⇒ VieNeu **cần** nạp `chunkLength` (khoá `vieneuChunk`).
- **Piper-only thật**: khoá `nghittsPrefetchDelay` trong `prefetchDelayMs.didSet`. Đổi sang `isLocalEngine` gây hồi quy (VieNeu ghim 500 ms ⇒ ghi đè độ trễ NghiTTS).
- **Nhánh `else` của `loadParamsForCurrentTool()` là bẫy**: nó là nhánh extension, gọi helper của engine rồi **ghi đè ngay** `speed`/`pitch`/`selectedVoice`. Engine mới **phải** có `else if` riêng.
- ⚠️ **Máy nạp lại/wake của NghiTTS còn gate `tool == "nghitts"` ở ~15 chỗ** (`updateNghiPrefetchWindow:2652`, `prepareNextNghiAudioIfPossible:3252`, `calculateNghiCachedTime:2596`, `handleNghiAudioFinished:3362`, `startPrefetchTask:2991`, `handleNghiScheduledHandoff:3194`) ⇒ `calculateNghiCachedTime()` trả **0.0** cho VieNeu, `vieneuSafeCachedTimeThreshold` **không có nơi đọc**, `vieneuPrefetchCount` chỉ đọc ở đường **remote**. **Đây là việc 2b còn lại.**
- **Cách phát hiện "điều khiển chết" không cần chạy app**: grep hai chiều tên property trong `Sources/`, tự hỏi *"ngoài khai báo/ghi/UI, ai **đọc để quyết định**?"*. Chỉ thấy setter + view ⇒ chết.
- `NghiAudioPlayerQueue` chỉ có `updateRate(_:)` (0.5…2.0) — **không** pitch. `AVAudioUnitTimePitch` chỉ nằm trên đường `AVAudioEngine` (`setupAudioEngine()`), nên `pitch` là no-op với **mọi** engine local.
- **Ratchet-down `TTSManager.swift` (4025/3470)**: gom chuỗi `if/else` trong `didSet` thành `persistSpeed`/`persistPitch`/`persistVoice`/`persistChunkLength` ở `TTSManager+VieNeu.swift` ⇒ thêm engine/khoá mà file legacy **ngắn hơn**. Extension **không** thêm được stored property (nên `@AppStorage` trong extension là bất khả; dùng `Binding` đọc/ghi thẳng service như `vieNeuModeBinding`).
- **`validate_links.py --accept` chỉ nhận 1 doc mỗi lần chạy** ⇒ phải loop từng file. `--accept` báo "vùng GENERATED không đổi" nếu doc đã accept rồi.
