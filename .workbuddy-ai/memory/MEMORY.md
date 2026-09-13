# FreeBook — ghi chú dài hạn của dự án

## Quy ước làm việc với người dùng

- **Không được đoán UI. Luôn đọc code view thật trước khi vẽ mockup, mô tả giao diện, hay sửa giao diện.** Người dùng đã phải sửa lỗi này hai lần liên tiếp (2026-09-11). Repo **không có ảnh chụp màn hình nào** (chỉ 12 file trong `AppIcon.appiconset`) và môi trường làm việc là **Windows** nên không chạy được Simulator — vì vậy mockup chỉ có thể là **wireframe đúng cấu trúc**, và phải **nói rõ giới hạn đó** thay vì để người dùng tưởng là bản mô phỏng sát.
- Khi mô tả một màn hình, phải dẫn `file:line` cho từng khẳng định về cấu trúc. Nếu chỉ grep một đoạn đầu file rồi kết luận cả file thì rất dễ sai (đã sai đúng kiểu này với `SettingsView`: kết luận "không có `navigationTitle`" trong khi nó nằm ở dòng 308).
- Trả lời bằng **tiếng Việt**; giữ thuật ngữ kỹ thuật tiếng Anh inline (MainActor, cache, token, sheet, badge…) nhưng viết prose/tiêu đề bằng tiếng Việt.
- Tài liệu phân tích/kế hoạch viết tiếng Việt, đặt đúng chỗ: kế hoạch → `Docs/Plans/YYYY-MM-DD-plan-<slug>.md`; báo cáo → `Docs/Reports/YYYY-MM-DD-<topic>.md`. **Không** ghi vào `Docs/CodeGraph/` (thư mục đó do validator sở hữu).

## Quy trình bắt buộc của repo

Đọc `AGENTS.md` + `.agents/AGENTS.md` trước khi sửa code. Sau khi sửa code:

1. `python Docs/CodeGraph/validate_links.py --explain` để biết doc nào stale
2. Cập nhật **chỉ trong** vùng `<!-- GENERATED START -->` … `<!-- GENERATED END -->`
3. `--accept <số>` hoặc `--no-change-needed <số>` cho từng doc
4. Thêm entry `CHANGELOG.md` (`[1.3.NNN] - YYYY-MM-DD`, tiêu đề **trùng subject commit**)
5. Chạy lại `validate_links.py` read-only, phải PASS 100%
6. Kết thúc response bằng `"CodeGraph updated."` hoặc `"No CodeGraph update required."`

## Bẫy môi trường & công cụ

- **Không build được trên Windows.** `xcodegen`/`xcodebuild` chỉ chạy macOS. Mọi khẳng định "đã kiểm chứng biên dịch" là sai — phải nói rõ "chưa kiểm chứng tại chỗ".
- `Scripts/check_architecture.py` **đang đỏ sẵn** (~30 violation trên cây sạch vì baseline đã trôi). Không đánh giá thành công bằng exit code; phải đối chiếu trước/sau và chỉ chịu trách nhiệm violation mới do mình gây ra.
- `[PASS]` của script **không phải bằng chứng**: `strip_comments_and_strings` (`check_architecture.py:53-60`) ăn nhầm code thật khi gặp string interpolation Swift, nên `ShelfView.swift:757` và `BookDetailView.swift:239` có `try? modelContext.save()` thật mà script không thấy.
- Grep trong repo phải **scope vào `Sources/`** — thư mục `Tools/` có hơn 4000 file nên grep toàn repo dễ timeout.
- `Docs/CodeGraph/00_index.md` quá lớn để đọc một lần (~50k token) — dùng `offset`/`limit`.

## Ràng buộc kiến trúc (đã xác minh)

- `Sources/Services/**` **không được** `import SwiftUI` ⇒ mọi singleton hướng-SwiftUI phải nằm ở `Sources/Common/**` (tiền lệ: `ToastManager` ở `Sources/Common/Services/`).
- File Swift mới ≤ **400 dòng**; đúng **1 type chính** ở top level mỗi file.
- `Sources/Views/**` không được `modelContext.insert/delete/save`.
- **Ngân sách dòng file legacy** (allowlist `baseline_value`, fail khi vượt): `Views/Settings/Main/SettingsView.swift` **452/453 — chỉ còn 1 dòng**; `Views/Reader/ReaderView.swift` 2002/2053; `Views/Reader/ReaderViewModel.swift` **918/830 — đang vượt**.
- Repo tự ghi nhận ràng buộc này tại `Views/Settings/Main/DeveloperSettingsSection.swift:4`: *"`SettingsView.swift` đã sát baseline dòng nên mọi mục mới phải ra file riêng."*

## Cấu trúc điều hướng thật của app (dễ đoán sai)

- **4 tab**: `Kệ Sách` / `Khám Phá` / `Tiện Ích` / `Cài Đặt` (`MainTabView.swift:12-37`). **Không có tab Tìm kiếm** — tìm kiếm nằm trong Kệ sách (`ShelfSearchView`) và trong trình đọc (`ReaderSearchView`).
- `MainTabView.swift:38` đã có sẵn `.tint(.accentColor)` — **cần gạt accent duy nhất của toàn app**.
- **Khám Phá không có navigation bar** (`.toolbar(.hidden, for: .navigationBar)`, `DiscoveryView.swift:346`) — dùng header tự dựng, và không có tiêu đề nào.
- **Chi tiết truyện**: thanh tab `Chi tiết`/`Mục lục` nằm **ngay dưới nav bar**, còn bìa/tên/thể loại/giới thiệu nằm **bên trong tab `Chi tiết`** (`BookDetailView.swift:206-232`, header ở `:368`).
- Ba màn dùng chung mẫu `TabView(.page)` + cổng `renderedTab` + `asyncAfter(0.15s)` để chống render hai trang: BookDetail, RepositoryManager, (và Shelf/Discovery dùng `.page` không có cổng). **Không đụng cơ chế này khi sửa UI.**
- **Hai kiểu thanh chọn tab khác nhau**: Kệ sách = hàng nút rời (`ShelfTabSelectorView`, 2 nút tròn icon + 2 pill chữ, căn trái); Tiện Ích = `Picker(.segmented)` thật.

## Phân hệ Backup — quy ước đã chốt

- **Bản sao lưu trong máy là bản tạm.** `uploadToDrive` / `uploadToTelegram` xoá file local **sau khi** đích tự xác nhận thành công (`removeLocalCopyAfterUpload`, ở `BackupCoordinator+LocalCleanup.swift`). Hệ quả có chủ ý: đường bấm tay là **một archive → một đích**; muốn một bản lên cả Drive lẫn Telegram thì dùng lượt tự động (`+AutoDrive` export một lần, gửi tuần tự).
- **Hai hàng rào xoá khác nhau, đừng "thống nhất".** `BackupPaths.isAutoBackupFileName` (tiền tố `freebook-auto-`) là hàng rào của phép dọn **ngầm** — bản người dùng tự tạo/đổi tên không bao giờ bị xoá hộ. `LocalBackupStore.deleteAll()` **cố ý** không lọc tiền tố vì đó là hành động người dùng đã xác nhận.
- **`backups/` chứa cả file tạm của worker** ⇒ không bao giờ xoá cả thư mục; luôn duyệt `list()` rồi xoá từng archive.
- **Trần 400 dòng của `BackupCoordinator.swift` là ràng buộc thật.** File này đã từng chạm **402**/400 khi nhồi thêm hàm và sinh `NEW_FILE_TOO_LARGE`. Tính năng mới của phân hệ Backup **phải** ra file extension (`BackupCoordinator+AutoDrive.swift`, `BackupCoordinator+LocalCleanup.swift`) — không nới baseline, không thêm entry allowlist. Extension ở file khác **không** ghi được `isBusy`/`progress` (`private(set)`); nếu cần ghi thì mở cửa nội bộ `setBusy`/`setProgress` như `+AutoDrive` đã làm.

## Quy ước `CHANGELOG.md` (CodeGraph)

- Giữ **30** entry trong `CHANGELOG.md`; vượt thì đẩy entry **cũ nhất** sang `CHANGELOG.archive.md` (archive sắp xếp mới nhất trước, chèn vào ngay trước entry đầu tiên). Đã kiểm: 30 + 294 = 324 = 34 + 290, không mất entry nào.
- Thêm file Swift mới ⇒ `00_index`, `02_file_graph`, `09_dependency_rules`, `14_complexity_report` (structure) **và** `11_subsystems` (content) cùng stale ⇒ phải sửa vùng GENERATED của cả 5 rồi `--accept`. Sửa file trong `Sources/Common/**` thì `03_type_graph` cũng stale.

## Hiệu năng Reader — bẫy đã xác minh (2026-09-13)

- **Trước khi điều tra lại một vấn đề hiệu năng, đọc `Docs/Reports/` trước.** Báo cáo `2026-09-10-reader-tts-perf-review.md` đã bị **trôi một phần**: RC-5 (NSCache không giới hạn) **đã sửa**, RC-9 và P-2 **đã sai** (code đổi kiến trúc). Đi tìm nguyên nhân ở chỗ đã sửa là mất thời gian.
- **Nút "Cập nhật" ở panel Dịch mặc định lưu ở phạm vi "R" (Riêng)** — `ReaderView.swift:123` `@AppStorage("pinnedSaveToBookSpecific") = true`. Nên đường mặc định chỉ bump `bookGenerations[bookId]`, **không** phải `globalGeneration`. Đừng mặc định nói "toàn cục".
- **`ChapterCache.queueReleaseAllNonVisible` (`ChapterCache.swift:153`) không có call site.** Cache chương **không có trần**; chỉ dọn khi Memory Warning (`ReaderViewModel.swift:678`). Đây là đòn bẩy rẻ tiền cho mọi vấn đề bộ nhớ của Reader.
- **`ReaderDefinitionOverlayView` dựng một SwiftUI `Text` cho mỗi đơn vị UTF-16 của cả đoạn** (`:182-202`, `HStack` không lazy). Cùng mẫu ở `ReaderJunkDeleteOverlayView` và `ReaderCopyOriginalOverlayView`. Mọi thay đổi UI ở ba panel này phải tính tới chi phí N view.
- **`TranslationWordToken.id` là `UUID()` sinh trong `init`** (`TranslationWordToken.swift:4`) ⇒ `ForEach(translationTokens)` mất khả năng diff ở **mọi** lượt nạp, và `.onChange(of: translationTokens.map(\.id))` luôn nổ. Đây là cái bẫy: bản vá chống lỗi scroll (1.3.373) lại thành nguồn animation thừa.
- `ReaderEnergyDiagnostics.isEnabled` **chốt một lần** trong `beginReaderSession()` ⇒ muốn có log `[ReaderEnergy] Summary` thì phải bật `AppLogger.isLoggingEnabled` **trước khi mở Reader**.

## `FrozenTrieDictionary` — hai đường tra cứu khác nhau về bản chất (2026-09-13)

- `FrozenTrieDictionary` có **hai** đường: `dat != nil` (nhanh, dừng sớm) và `dat == nil` (duyệt `lengths` + `String(decoding:)` **mỗi độ dài**). `trieMatches` (đường nhanh) **vẫn** cấp phát `Array(text.utf16)` mỗi lần gọi.
- **Từ điển `dat == nil`:** `customNamesDict`, `customVietPhraseDict`, **và `bookVP`/`bookNames` (từ điển riêng truyện)** — tất cả qua `TextDictionary.frozen()`. Từ điển `.dat` (`namesDict`, `vietPhraseDict`, `pronounsDict`, `luatNhanDict`) đi qua `DoubleArrayTrie.frozen()` ⇒ nhanh.
- **Hệ quả:** trước lần lưu từ điển đầu tiên, các dict đó là `nil` nên `VietPhraseTokenizer` **bỏ qua** nhánh tra cứu; sau lần lưu đầu tiên chúng khác `nil` **vĩnh viễn** ⇒ mỗi vị trí ký tự × mỗi dòng × mỗi lượt dựng chương đều cấp phát thêm. Đây là nguồn đốt CPU (→ nóng máy → throttle) lớn nhất đã biết của pipeline dịch.
- **Bẫy khi tối ưu:** `VietPhraseTokenizer` truyền `checkText` + `startIndex: 0` **cố ý** để biên `limit`/`maxLimit` giới hạn vùng quét (chặn VP khớp xuyên mốc bắt đầu của tên riêng đã chọn). Muốn truyền chuỗi gốc + `startIndex` thì chữ ký tra cứu **bắt buộc** phải thêm `maxLength`, nếu không kết quả dịch sẽ đổi.
- **Phép thử phân biệt "từ điển bật lên" vs "cache nguội":** ghi `[ReaderPerf] TranslationRefresh totalMs` → bấm Cập nhật 1 từ → ghi lại (tăng vọt, không hồi) → xoá từ điển riêng truyện → ghi lại (hồi về nền nếu là từ điển, không hồi nếu là cache).

## Bẫy đã xác minh — công cụ & số đo (2026-09-13)

- **`validate_links.py` short-circuit khi cây làm việc sạch.** Nó báo `PASS` dù doc đã stale, miễn là `git status` sạch. Đừng tin `PASS` ngay sau một commit — phải chạy `--explain` **khi cây đã có thay đổi**. Cách phân định nợ cũ vs nợ mới: `git stash push -- Sources/ Docs/` → chạy validator → `git stash pop`.
- **`originalSentence` (panel Dịch) là MỘT ĐOẠN VĂN**, không phải cả chương — gán ở `ReaderView.swift:1494` (`item.original`). Trước khi "sửa O(N) view", **phải đo N thật**: đoạn văn trong truyện thật thường 9–173 ký tự (trung bình ~28), nên N ≈ 28 chứ không phải hàng nghìn. Rủi ro chỉ thành thật với nguồn trả cả chương thành một dòng, vì `ChapterTextNormalizer.normalizeInternal` (`:24-52`) **chỉ tách theo `\n`**.
- **`ChapterCache.queueRelease` / `performRelease` / `queueReleaseAllNonVisible` từng là code chết** (không có caller). Từ 1.3.375 `ReaderView.applyNavigationCommit` gọi thật với cửa sổ ±3. `queueRelease` **phải** là `Task { @MainActor }` vì `performRelease` gỡ khoá trong `cache` (`@Observable`). Bài học: đánh thức code chết thì phải rà tính an toàn luồng trước, không chỉ cắm dây gọi.
- **CHANGELOG có 2 vấn đề chưa sửa:** (a) đã drift lên 43 entry (mốc ~30); (b) **thiếu hẳn 1.3.323–1.3.328 ở cả `CHANGELOG.md` lẫn `CHANGELOG.archive.md`** (archive dừng ở 1.3.322, CHANGELOG bắt đầu ở 1.3.329) trong khi các doc vẫn tham chiếu 1.3.323/325/326/328 ⇒ một lượt lưu trữ trước đây đã mất entry. Lấy lại được từ `git log`. **Đừng tự đẩy entry sang archive khi chưa có kiểm chứng** — quy trình đó đã chứng minh có thể mất dữ liệu.
