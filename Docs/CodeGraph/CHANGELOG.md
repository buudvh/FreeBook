# CHANGELOG - Nhật ký Thay đổi CodeGraph FreeBook

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **FreeBook**.

## [1.3.576] - 2026-10-22

### fix: chia sẻ báo cáo và xuất nguồn Legado báo nhầm "truy cập file ngoài thư mục" từ lần thứ hai

Người dùng: *"có thông báo truy cập file ngoài thư mục chia sẻ báo cáo bị từ chối"*.

- **Nguyên nhân**: thư mục tạm của iOS nằm dưới `/private/var/…`, và `URL.standardizedFileURL` chỉ bỏ tiền tố `/private` khi đường dẫn **đã tồn tại**. Lần đầu thư mục chia sẻ chưa có ⇒ hai bên cùng `/private/var/…`, khớp. Từ lần thứ hai thư mục đã có (rút thành `/var/…`) còn tệp mới chưa có (giữ `/private/var/…`) ⇒ `validatePathSafety` tưởng tệp nằm ngoài thư mục và từ chối.
- **Sửa**: `LegadoCorpusReportShare` (chia sẻ báo cáo Kiểm tra nguồn) và `LegadoSourceExporter` (xuất / chia sẻ nguồn — cùng ghi vào thư mục tạm, cùng lỗi) so sánh thành phần đường dẫn sau khi **tự bỏ `/private`** (`comparableComponents`), không phụ thuộc tệp đã tồn tại hay chưa. Các kho khác của nguồn Legado ghi vào Application Support (`/var/…`, không có `/private`) nên không bị.
- Chuyển entry `[1.3.546]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.575] - 2026-10-22

### fix: nút chia sẻ chỉ chạy được lần đầu: bảng chia sẻ đóng xong không báo SwiftUI

Người dùng: *"tôi bấm chia sẻ kiểm tra nguồn nhưng không thấy hoạt động, trước đây có thành công 1 lần"*.

- **Nguyên nhân**: `UIActivityViewController` tự đóng khi chia sẻ xong (hoặc huỷ) mà SwiftUI không biết ⇒ cờ `isPresented` / `item` của `.sheet` kẹt ở "đang mở"; lần bấm sau gán URL mới khi cờ vẫn `true` nên không có gì hiện ra.
- **`ShareSheet`** (dùng chung cả app — sao lưu, từ điển, rule dịch, lọc rác, công cụ tìm kiếm, xuất nguồn Legado…): trong `completionWithItemsHandler` gọi `dismiss` của chính sheet (`context.environment.dismiss`, trên MainActor) sau `onComplete` ⇒ SwiftUI hạ trạng thái, lần sau trình bày lại được.
- **Màn Kiểm tra nguồn**: `onComplete` hạ `shareURL`; nếu cờ vẫn kẹt khi bấm lại thì hạ trước, chờ ~0,4 s cho sheet cũ gỡ xong rồi mới trình bày.
- Chuyển entry `[1.3.545]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.574] - 2026-10-22

### feat: tự kết luận lỗi nguồn Legado do web, do nguồn hay do app, chia sẻ báo cáo kiểm tra

Người dùng: *"nhiều nguồn lỗi nhưng không biết lỗi do nguồn hay do app"*; xem mockup rồi bảo *"tiếp tục"*.

- **Bộ phân xử** (`LegadoFailureArbiter` + `+Evidence`, `LegadoFailureVerdict`, hàm thuần, `Services/LegadoSource/Diagnostics/`) — dừng ở luật đầu khớp:
  1. **Cần xác minh / đăng nhập**: trang thử thách/captcha (dấu `challenge-platform` chỉ tính khi mã ≥ 400 vì Cloudflare chèn cả vào trang thường; chữ yếu như "captcha" chỉ tính trong `<title>`, trang < 6 KB hoặc mã ≥ 400), nguồn có `loginUrl` bị 401/403, hoặc engine báo cần trình duyệt/mã xác minh khi chạy không tương tác.
  2. **Web chặn / sập**: trang chặn theo vùng / từ chối truy cập (`LegadoPageMarker`), lỗi mạng, engine quá thời gian, HTTP 403 / 404 ở bước đầu / 410 / 429 / 451 / 5xx.
  3. **Nghi do app**: cú pháp/hàm chưa hỗ trợ (trừ lớp dò app `io.legado.*`/`io.legato.*`), lỗi JS chỉ vào phần app giả lập, hoặc **đầu dò bộ chọn** thấy trang 2xx có đủ class/id của rule mà rule khớp 0 (thêm điều kiện: rule không có JS sau bộ chọn, khớp 0 chứ không phải lọc hết, thẻ cuối có thật trong phần tử chứa — trang tìm không có kết quả không bị kết luận oan; bước nội dung cần ≥ 50 ký tự chữ).
  4. **Nguồn lỗi thời**: trang 2xx mà không token class/id nào của rule có trong trang, hoặc nguồn thiếu rule.
  5. **Chưa rõ**: còn lại, kèm lý do (404 ở bước sau, máy mất mạng, lỗi JS của chính script nguồn…).
- **Đầu dò bộ chọn** (`LegadoSelectorProbe`, `LegadoRuleSelectorTokens`): khi bước danh sách/nội dung ra rỗng sau trang 2xx, tách token `class.X`/`.X`/`id.X`/`#X`/`tag.X` của rule và kiểm trong **toàn bộ** HTML trang, ghi vào run log.
- **Bằng chứng cho bộ chạy hàng loạt**: `LegadoRunLog.current` (task-local) — `runSession` dùng `log ?? LegadoRunLog.current` (đọc trước khi sang thread engine); bộ chạy bọc **từng bước** của mỗi nguồn. Không đổi chữ ký facade.
- **Báo cáo**: `SourceResult.verdict` + `verdictReason` (tuỳ chọn), báo cáo tổng thêm `byVerdict`; mirror `protocol.ts` (trường tuỳ chọn, không nâng version; `tsc --noEmit` sạch).
- **UI** (khớp mockup): màn Kiểm tra nguồn có ô đếm "Lỗi do ai" (`LegadoSourceCheckVerdictPanel`, chỉ ô > 0), chip lọc theo kết luận (`LegadoSourceCheckFilter`), dòng lỗi "Kết luận · bước · lý do" theo màu kết luận (`LegadoFailureVerdictStyle`), nút **chia sẻ báo cáo** ở toolbar (`LegadoCorpusReportShare` ghi JSON đã redact ra file tạm, `ShareSheet`); màn Gỡ lỗi từng bước có dải "Kết luận: …" (`LegadoFailureVerdictBanner`, nền nhạt — không nền màu nhấn đặc) dùng chung bộ phân xử.
- Chuyển entry `[1.3.544]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới** (kể cả `WHITE_TINT_FILL`); không đụng engine `{JS,Engine,Net,Rule}`. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.573] - 2026-10-22

### fix: chặn tận gốc lỗi nút trắng trên trắng: kiểu nút appFilled và luật WHITE_TINT_FILL

Người dùng: *"Trắng trên trắng tìm cách fix luôn lỗi này đi, tôi thấy thêm nút mới hay bị lắm"*.

- **Nguyên nhân gốc**: `MainTabView` đặt `.tint(.white)` toàn cục ⇒ `Color.accentColor` là **trắng**, `.borderedProminent` không kèm `.tint(…)` là nền trắng; nút mới tô nền bằng màu nhấn rồi đặt chữ trắng là vô hình. Đã gặp ở 1.3.447 (thư viện giọng VieNeu) và 1.3.567 (các màn nguồn Legado, sửa ở 1.3.570). Rà toàn app: hiện không còn chỗ nào dính — mọi `.borderedProminent` đều kèm tint màu.
- **`AppFilledButtonStyle`** (mới, `Views/Common/`): kiểu nút nền đặc chuẩn, chữ trắng trên màu cố định (mặc định xanh), mờ khi nhấn/tắt; `.buttonStyle(.appFilled)`, `.appFilled(.green, fullWidth: false)`. Nút "Mở trang đăng nhập" (`LegadoLoginView`) dùng kiểu này.
- **Luật mới `WHITE_TINT_FILL`** trong `Scripts/check_architecture.py` (quét `Sources/Views/**`, bỏ dòng comment): báo lỗi `.borderedProminent` mà chuỗi modifier của chính nút không có `.tint(<màu khác trắng>)`, và `.background(…Color.accentColor…)` đặc (mờ < 50% thì được; `.background(.tint)` cũng bị bắt). `.fill(Color.accentColor)` cho hình vẽ (thanh tua video) không bị cấm. Thử trên mẫu: bắt đúng 5/5 mẫu sai, không báo nhầm 3 mẫu đúng; trên code thật 0 vi phạm mới.
- **Tài liệu**: `CLAUDE.md` + `AGENTS.md` (bảng luật 5 → 6, ghi chú "màu nhấn của app là trắng"), `rules.md` §5.4 thêm quy tắc kèm ví dụ đúng/sai.
- Chuyển entry `[1.3.543]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.572] - 2026-10-22

### feat: danh mục tìm nhanh ở Khám phá cho nguồn Legado không có Khám phá

Người dùng: *"các nguồn không khai báo exploreUrl/ruleExplore của legado hãy thêm danh sách các từ tìm kiếm nhanh để người dùng có thể dùng để tìm kiếm nhanh. Tham khảo danh sách của …/wcshuba/src/genre.js"* (kèm báo 69書吧 không có ở Khám phá — nguồn này không khai `exploreUrl`).

- **`LegadoQuickSearch`** (mới, `Services/LegadoSource/Search/`): 70 từ khoá tiếng Trung lấy theo danh mục tìm của tiện ích `wcshuba` (诸天, 聊天群, 万界, 斗罗, 遮天, 凡人, 火影, 柯南…), bỏ các mục phân loại riêng của trang đó; mục "木叶" tìm đúng "木叶" (bản tham khảo trỏ nhầm sang "火影"). Áp cho nguồn **có rule tìm kiếm** mà **không có Khám phá dùng được** (thiếu `exploreUrl`/rule khám phá, hoặc `enabledExplore = false`).
- **Khám phá**: `SearchExtensionScopePolicy.isDiscoverable` nhận thêm nguồn Legado `LegadoSourcePolicy.isQuickSearchable` ⇒ hiện ở bảng chọn nguồn. Tab lưới của nguồn (`LegadoExploreTabView`) hiện các ô từ khoá (4 ô một hàng; tên ô dịch QT khi bật dịch như tên thể loại) — `LegadoSourceRuntime.exploreEntries`/`exploreCategories` trả mục tìm nhanh, không chạy engine.
- **Bấm ô** ⇒ đi đường của mục khám phá (`legadoExploreScriptName`, URL mang tiền tố `legado-quick-search:`); `SourceRuntime.executeCustomScript` nhận ra và chạy **tìm kiếm** của nguồn với từ khoá đó; có trang sau khi trang có kết quả và `searchUrl` có dùng `page` (`PaginatedNovelLoader` vẫn dừng khi trang không thêm mục mới).
- Nguồn có Khám phá riêng giữ nguyên danh mục của nguồn; tiện ích JS không đổi.
- Chuyển entry `[1.3.542]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.571] - 2026-10-22

### feat: nút chi tiết nguồn Legado trong bảng Phần mở rộng của Khám phá

Người dùng: *"thêm nút chi tiết nguồn các ext ở phần mở rộng của khám phá"*.

- Bảng chọn nguồn "Phần mở rộng" của Khám phá (`ExtensionSelectorView`): dòng nguồn Legado có nút ⓘ (`info.circle`, cùng kiểu và vị trí với nút ⚙ của tiện ích JS) mở `LegadoSourceDetailView` dạng sheet — từ đó sửa JSON, gỡ lỗi từng bước, kiểm tra, đăng nhập, chia sẻ ngay khi đang duyệt. Tiện ích JS giữ nút ⚙ mở màn Cấu hình như cũ; nguồn Legado vẫn không có lối vào màn cấu hình/sửa script của tiện ích JS.
- Chuyển entry `[1.3.541]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới** (`ExtensionSelectorView.swift` 200 → 217). Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.570] - 2026-10-22

### fix: nguồn Legado: tên gốc ở Kho, nút và chip không còn trắng trên trắng, không nối sang chương sau

Thử máy với bộ 1298 (log `app_logs (113)`, `(114)`). Người dùng: *"đừng dịch tên nguồn ở tab tiện ích"*, *"nút đăng nhập đang lỗi nền trắng chữ trắng"*.

- **Tên nguồn hiện bản gốc** ở tab Nguồn Legado, màn chi tiết, kiểm tra, gỡ lỗi, đăng nhập (`LegadoSourceSummary.displayName = name`; đảo quyết định 11 của plan đợt 1 theo yêu cầu người dùng). Tên dịch QT vẫn giữ để ô tìm khớp; **nhóm vẫn hiển thị bản dịch**.
- **Trắng trên trắng**: app đặt `.tint(.white)` toàn cục (`MainTabView`) nên `Color.accentColor` là trắng. Nút "Đăng nhập" / "Mở trang đăng nhập" (`LegadoLoginView`) và "Chạy" (`LegadoSourceDebugView`) đổi sang nền `Color.blue`; chip đang chọn ở tab Nguồn Legado, Kiểm tra nguồn và Gỡ lỗi (nền nhấn 85% + chữ trắng) theo kiểu chip của `ExtensionKindFilterBar` (chữ nhấn, nền nhấn 18%, viền 60%).
- **Không nối sang chương sau**: vòng `nextContentUrl` trước chỉ dừng ở **một** URL chương kế; tra không ra (mục lục chưa nạp trong phiên, URL lệch dạng…) là đi theo nút "下一章" kéo tới 30 chương vào một chương, request dồn dập và web chặn (thấy ở 错层小说: app nhận HTTP 400 cho đúng URL chương mà curl trả 200). Nay dừng khi gặp **bất kỳ** URL chương nào khác của mục lục (`LegadoEngineSession.tocStopKeys`; nguồn: mục lục đệm `LegadoTocURLCache.urls`, không có thì đọc `ChapterStore` một lần theo `bookId` rồi đệm).
- **Bỏ lỗi giả khi nguồn dò app**: script tạo thử lớp nội bộ `io.legado.*` / `io.legato.*` trong `try/catch` để biết đang chạy trên app nào (spec §6.10) — vẫn ném cho script đi nhánh khác, nhưng ghi thông tin thay vì "chưa hỗ trợ" `❌` (魔丸小说 ghi 4 dòng `❌` mỗi lần đọc).
- **`PaginatedNovelLoader`**: `CancellationError` (rời màn, đổi nguồn) không còn ghi `❌`, không hiện thông báo lỗi, không tự thử lại.
- **Khám phá chạy `exploreUrl` một lần**: danh mục và tab điều khiển cùng hỏi khi mở nguồn trước khi bản đệm có ⇒ lượt thứ hai dùng chung lượt đang bay (`ExploreEntriesCache.runningTask`); màn Gỡ lỗi vẫn chạy riêng.
- **Không phải lỗi app** (đã kiểm từ máy cùng vùng mạng): 篱笆好文学 (chặn theo vùng, 1Panel), 小原文学网, 可乐小说 (HTTP 403), 思路客 (captcha Cloudflare), 文桑小说 (quá thời gian), 鬼吹灯 (tên miền chết). 8/15 nguồn của bộ 1298 không khai `exploreUrl` nên không có ở Khám phá — đúng hành vi.
- Chuyển entry `[1.3.540]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử lại trên máy.

## [1.3.569] - 2026-10-21

### feat: nối nốt nguồn Legado: giải mã bìa, imageStyle, ghi đè loại sách, làm mới chương, alert trình duyệt, dọn trạng thái mồ côi

Người dùng: *"Làm nốt các mục chưa nối: coverDecodeJs, imageStyle, typeOverride cho BookContentDestination, refreshContent vào trình đọc, alert() trong trình duyệt nhỏ, dọn sidecar mồ côi lúc mở app."* Hành vi theo spec phần 2 §8.5, §8.7, §13.6.

- **`coverDecodeJs`** (`LegadoCoverDecoder`, mới): luồng tìm / khám phá / chi tiết ghi URL bìa của nguồn có `coverDecodeJs` vào sổ; `CoverImageLoader.data` (tìm kiếm, Khám phá) giải mã bytes → bytes **trước** bước kiểm ảnh rồi cache bản đã giải; `ImageCacheManager.downloadAndSaveCover(packageId:)` (mặc định `nil`) + `BookCoverView` truyền `extensionPackageId` nên bìa trên kệ giải được sau khi mở lại app. Tối đa 2 phiên engine cùng lúc; lỗi ⇒ dùng byte gốc, `❌` một lần mỗi nguồn. JS nhận `result` dạng luồng (`read()`/`available()`) — harness `runImageDecode` chỉ thêm, không đổi hành vi `imageDecode`. Tiện ích JS chỉ tốn một lần tra từ điển.
- **`imageStyle`**: `ComicPageSource.imageStyle` (tuỳ chọn, mặc định `nil`), ưu tiên `style` trong option của ảnh > `book.imageStyle` do JS `content` ghi trong cùng phiên > `ruleContent.imageStyle`; chuyền tới `ComicPageView`. Trình đọc tranh vốn vẽ ảnh tràn bề ngang, không khoảng cách (= `FULL`, giá trị phổ biến nhất) nên **hình không đổi**; giá trị khác giữ cách hiện tại.
- **Ghi đè loại theo sách** (`LegadoBookTypeOverride`, mới, bitmask §13.6: 64 ⇒ tranh, 8 ⇒ chữ; audio/tệp/`3` ⇒ theo loại của nguồn): `BookContentDestination.resolveKind` ưu tiên ghi đè của sách; guard `SourceRuntime.chap` nới cho sách tranh bị nguồn ghi đè thành chữ.
- **`refreshContent` → trình đọc** (`LegadoContentRefreshSignal` + modifier `legadoContentRefresh`, mới; gom lặp 3 s): presenter báo tín hiệu theo nguồn; Reader chữ tải lại chương đang mở bỏ qua cache (`reloadCurrentChapterFromMenu`; `ReaderView` 2045 → 2046, baseline 2053); trình đọc tranh `retry()`. Không dùng NotificationCenter.
- **`alert()` / `confirm()` / `prompt()`** trong trình duyệt nhỏ (`LegadoBrowserController` + `LegadoBrowserJSPanel`, mới; trình duyệt đăng nhập dùng chung): `UIAlertController`, completion gọi đúng một lần kể cả khi đóng trình duyệt giữa chừng.
- **Dọn trạng thái mồ côi** (`LegadoOrphanStateSweeper`, mới): một lần mỗi lần mở app từ `MainTabView` (225 → 227), `Task.detached` + `ModelContext` riêng; `LegadoBookStateStore.removeOrphanFiles` chỉ xoá tệp đúng mẫu `<64 hex>.json` ở gốc `legado_state/` không còn sách, sửa lần cuối trước lúc bắt đầu lượt, qua `validatePathSafety`; đọc lỗi / danh sách sách rỗng ⇒ bỏ lượt.
- **Còn hở**: tải truyện, `BookKindBadge` và nhãn "Tải truyện" vẫn theo loại của nguồn; bìa cho TTS không truyền `packageId`; `resolveKind` đọc tệp sidecar nhỏ trên main một lần mỗi sách; chương tranh đã tải offline thì làm mới vẫn mở bản offline; đổi nguồn giữa hai nguồn Legado có thể giữ ghi đè cũ; `book.imageStyle` chưa lưu bền.
- Chuyển entry `[1.3.539]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới** (`ComicReaderViewModel` không đổi). Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.568] - 2026-10-21

### docs: quy chuẩn nguồn Legado trong rules.md, client gỡ lỗi nhận chi tiết media

Rà soát cuối đợt 2 + 3 nguồn Legado.

- **`rules.md`** thêm mục "Nguồn Legado (1.3.557–1.3.567)": clean-room (hành vi chỉ lấy từ spec), mọi lời gọi runtime qua `SourceRuntime`, nhận diện theo `Extension.type` + `packageId` đóng băng, không qua `cleanAndResolveUrl`, engine chạy ngoài main và chờ UI qua event center, `isInteractive` chỉ cho thao tác một nguồn do người dùng bấm, đăng nhập chỉ ở Keychain (dự phòng tệp bảo vệ) và không sao lưu, cửa sổ trượt 8 nguồn khi tìm mọi nguồn, media không qua pipeline text.
- **Client VS Code** (`Tools/VSCode/FreeBookExtDebug/src/protocol.ts`): mirror trường tuỳ chọn `media` (`LegadoCorpusMediaCheck`) mà 1.3.565 thêm vào báo cáo nghiệm thu — trường thêm, tuỳ chọn, không đổi version giao thức. Kiểm kiểu `tsc --noEmit`: 0 lỗi.
- **Bộ quét gợi ý** (`LegadoCorpusFeatureScan`): bỏ `Jsoup.connect` khỏi danh sách "chưa hỗ trợ" — shim `Connection` đã cài ở 1.3.564 (bootstrap `connect` chạy sau `jsoup`, ghi đè stub mặc định).
- Entry 1.3.564 ghi rõ `java.open`, `openVideoPlayer`, `addBook` vẫn là stub (hoãn hẳn theo spec).
- Chuyển entry `[1.3.538]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch.

## [1.3.567] - 2026-10-21

### feat: đăng nhập nguồn Legado (form + web), trình duyệt cho JS, Khám phá động

Khối D-UI, E-UI của plan đợt 2 + 3 nguồn Legado — giao diện khớp mockup đã duyệt (người dùng chọn giữ cả đăng nhập bằng form lẫn trên web). Hành vi theo spec phần 2 §10, §11.

- **Đăng nhập** (`Views/Extensions/Legado/Login/`, mới): `LegadoLoginView` (+`Actions`, `LegadoLoginFieldView`) dựng form từ `loginUi` (ô chữ/mật khẩu…, nút hành động của nguồn chạy JS), Đăng nhập, "Đăng nhập trên web", Đăng xuất, dải trạng thái; `LegadoLoginWebView` — trình duyệt nhỏ (Huỷ / URL / ↻ / Xong ⇒ nhập cookie vào kho cookie của nguồn). Nút Đăng nhập ở màn chi tiết nguồn nối vào đây (ẩn khi `loginUrl` rỗng/chỉ là chú thích).
- **Keychain dự phòng**: `LegadoLoginFallbackStore` theo mẫu `TelegramTokenStore`, chỉ dùng khi Keychain lỗi (vd chạy dưới LiveContainer); tệp ở `.legado_login/` ngoài `legado_state/`, không log, không sao lưu. Xoá nguồn ⇒ xoá luôn thông tin đăng nhập của nguồn (`LegadoLoginService.forget`, khoá theo `bookSourceUrl`).
- **Trình duyệt / mã xác minh từ JS** (`Views/Extensions/Legado/Browser/`, mới): `LegadoPresentationPresenter` là subscriber duy nhất của event center engine, gắn một lần ở root (`.legadoPresentationHandler()` trong `FreeBookApp`); trình bày `LegadoBrowserSheet` (`java.startBrowser*`) hoặc `LegadoVerificationCodeSheet` (`getVerificationCode`), trả kết quả/huỷ cho thread engine đang chờ ngoài main. `searchBook` mở Tìm kiếm; `openUrl` hỏi nhập nguồn / mở trình duyệt nhỏ / hỏi trước khi mở app ngoài.
- **Cờ người dùng chủ động**: `SourceRuntimeContext.isInteractive` (mặc định `false`); facade Legado bọc `LegadoInteraction.$isInteractive` khi bật. Bật ở: trang chi tiết (chi tiết + mục lục), chương đang mở trong Reader (không phải prefetch; chương Legado đang mở chờ tối đa 620 s để kịp qua xác minh, tiện ích JS vẫn 30 s), kéo làm mới mục lục, Đổi nguồn, chương tranh đang mở, video đang xem, Khám phá, Gỡ lỗi từng bước. **Không** bật ở TTS, tải truyện, kiểm chương mới, tìm mọi nguồn, kiểm tra hàng loạt, bộ nghiệm thu. Engine nay cũng không phát `refreshExplore`/`searchBook`/`refreshContent`/`copyText` khi không có người dùng (kiểm tra hàng loạt không tự bật màn hình).
- **Khám phá động** (`Views/Discovery/Legado/`, mới: `LegadoExploreTabView`, `LegadoExploreControlView`, `LegadoExploreRefreshSignal`; `Views/Common/LegadoFlexLayout`): tab lưới thể loại của nguồn Legado có tiêu đề nhóm, ô bấm, điều khiển chọn / bật tắt / ô nhập + "Áp dụng", bố cục theo `style` của nguồn; `java.refreshExplore` tải lại danh mục. API: `SourceRuntime+ExploreControls`, `LegadoSourceRuntime+ExploreControls`. Danh sách mở ra vẫn là `CategoryNovelsListView`/`PaginatedNovelLoader`. `DiscoveryGenresTabView` chỉ thêm chỗ cắm; `DiscoveryView+Loading` chạy `exploreUrl` của nguồn Legado một lần rồi đệm.
- **Dọn ráp nối**: bộ quét gợi ý của bộ nghiệm thu (`LegadoCorpusFeatureScan`) chỉ còn gắn cờ những gì vẫn chưa hỗ trợ; hai comment lỗi thời ở `SearchExtensionScopePolicy`.
- **Chưa làm**: `refreshContent` chưa nối vào trình đọc (chỉ ghi log); trình duyệt nhỏ chưa xử lý `alert()` của trang.
- Chuyển entry `[1.3.537]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới** (`ChapterContentRepository` 430 → 430, `ReaderViewModel` 777 → 777, `DiscoveryView` 621 → 622, `SearchView` 794 → 794, `ComicReaderViewModel` 395 → 395). Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.566] - 2026-10-21

### feat: màn quản lý nguồn Legado: chi tiết, sửa JSON, gỡ lỗi, kiểm tra hàng loạt, xuất, liên kết legado://

Khối F, G, H của plan đợt 2 + 3 nguồn Legado. Giao diện khớp mockup người dùng đã duyệt 2026-10-21. Hành vi Legado theo spec phần 2 §12.

- **Chi tiết nguồn** (`Views/Extensions/Legado/LegadoSourceDetailView` + `…DetailHeaderCard`, mới): chạm dòng ở tab Nguồn Legado (toggle và 🗑 giữ nguyên) ⇒ thẻ đầu (tên QT, tên gốc · phiên bản, chip, URL, ghi chú "Xem thêm"), nút tròn Trình duyệt / Đăng nhập (khi có `loginUrl`) / Xoá; mục Hoạt động (Bật nguồn, **Biến của nguồn** — `…VariablesView`, gợi ý từ `variableComment`); mục Công cụ (Sửa JSON, Gỡ lỗi từng bước, Kiểm tra nguồn này, Chia sẻ nguồn).
- **Sửa JSON** (`…JSONEditorView`): dùng lại trình sửa code của tiện ích JS (Cú pháp / Định dạng / Tải lại, đếm dòng/ký tự, cỡ chữ); chỉ lưu khi JSON hợp lệ (`LegadoSourceJSONValidator`, báo dòng lỗi); đổi `bookSourceUrl` ⇒ hỏi lại. Lưu qua `LegadoSourceCoordinator+Editing` (ghi dạng chuẩn hoá + `lastUpdateTime`, tăng `version`; runtime tự bỏ bản đệm cũ theo `version`).
- **Gỡ lỗi từng bước** (`…DebugView`, `…DebugStepCard`; `Services/LegadoSource/Debug/` mới: `LegadoSourceDebugRunner`, `LegadoDebugInput`, `LegadoDebugStep`, `LegadoDebugReportFormatter`): chế độ từ khoá / URL chi tiết / `++` mục lục / `--` nội dung / `::` khám phá; thẻ từng bước có request, HTTP, bảng mã, số kết quả, trường mục đầu, thời gian, lớp lỗi, log JS / hàm chưa hỗ trợ, "Xem HTML trang (cắt 4 KB)". `LegadoRunLog` gom thêm ghi vết request của engine. Bản sao chép báo cáo che giá trị query; không gửi gì ra ngoài.
- **Kiểm tra hàng loạt** (`…CheckView`, `…CheckRow`): từ menu ⋯ (danh sách đang hiện) hoặc từ chi tiết; dùng `LegadoCorpusRunner` trong app; Đạt / Lỗi / Còn lại, chip lọc, nút bọ ⇒ Gỡ lỗi, **Tắt nguồn lỗi**, **Gắn nhóm "Lỗi"**, **Xoá nguồn lỗi** (hỏi xác nhận), Dừng. Nguồn đang tắt không kiểm (bộ chạy bỏ qua).
- **Xuất / chia sẻ** (`LegadoSourceExporter`): tệp `.json` là mảng `source.json` nguyên văn, qua `ShareSheet` có sẵn. Menu ⋯ thêm "Kiểm tra nguồn …" / "Xuất nguồn …"; "Bật/Tắt tất cả (theo danh sách đang hiện)" — đổi nhãn theo người dùng.
- **Liên kết `legado://`**: `CFBundleURLTypes` (scheme `legado`) trong `project.yml`; `LegadoLinkImportModifier` ở root (`FreeBookApp` 131 → 133) hỏi "Nhập nguồn từ liên kết?" rồi nhập như "Nhập từ URL" (chỉ http/https, tối đa 20 MB); dạng khác báo chưa hỗ trợ.
- **NSFW**: `ExtensionNsfwClassifier+Legado` nhận nguồn Legado theo nhóm/tên (cờ `nsfw` ghi vào `plugin.json`, bù cho nguồn đã nhập theo lô 200); tab Legado theo công tắc NSFW chung. Tìm kiếm/Khám phá bỏ heuristic theo ghi chú với nguồn Legado (41 nguồn bị gắn nhầm 18+ vì ghi chú có chữ `java.`).
- **Backup** (`BackupLegadoStateArchiver`, mới): đưa sidecar truyện + biến/giá trị/cache của trạng thái nguồn trong `legado_state/` vào backup; **không** sao lưu cookie, đăng nhập (Keychain), `device.json`, `jslib/`. Khôi phục sau bước cài lại tiện ích, gộp theo khoá, giữ bản của máy. `BackupLibraryFingerprint.formatVersion` 3 → 4.
- Chuyển entry `[1.3.536]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới**; `RepositoryManagerView.swift` không đổi. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.565] - 2026-10-21

### feat: truyện tranh và video từ nguồn Legado

Khối A, B, C (và phần cấp luồng của khối I) của plan đợt 2 + 3 nguồn Legado (người dùng đã duyệt). Hành vi theo spec phần 2 §8, §9, §13, §15.3.

- **Facade media** `SourceRuntime+Media` (mới): `comicPages`/`videoServers`/`videoTrack` cùng nhãn tham số với `ExtensionManager+Media`; tiện ích JS chuyển nguyên tham số, nguồn Legado chạy engine. Nối `ComicReaderViewModel` (+`+SourceContext`), `DownloadManager+Comic`, `VideoPlaybackSession+Loading`. Không còn lời gọi `ExtensionManager.shared.(comicPages|videoServers|videoTrack)(` ngoài facade. Media vẫn **không** đi qua pipeline text; `chap` gọi trên nguồn tranh/video ném lỗi rõ ràng.
- **Tranh** (`Runtime/LegadoSourceRuntime+Comic`, `LegadoComicImageExtractor`): nội dung chương ⇒ `[ComicPageSource]` (giữ `src` nguyên văn kể cả khối option; thiếu Referer thì chèn vào option), phân trang nội dung. `imageDecode`: `ComicPageSource.script` mang tên giả của Legado, `ComicImageScriptRunner` rẽ sang engine giải mã bytes → bytes (`+ImageDecode`; ảnh vẫn qua `concurrentRate`). Chương không có ảnh ⇒ lỗi kèm tối đa 600 ký tự chữ của trang.
- **Video** (`+Video`, `LegadoVideoServerPayload`): mỗi tập đúng một server (nguồn Legado không có khái niệm server); `data` là JSON chứa URL tập + ngữ cảnh; URL phát giải lại mỗi lần `videoTrack` (kể cả Thử lại / chọn lại) vì có chữ ký hết hạn; URL tập đã là tệp media thì không tải thân.
- **Mục lục tranh/video**: mục `isVolume` thành dòng tiêu đề nhóm (`isSection`); truyện chữ vẫn bỏ như cũ.
- **Phần đuôi cấp luồng** (`+TocTail`): `preUpdateJs`, `formatJs` (`index` đếm từ 1, trần 2 s), hiệu lực `book.setReverseToc`, `refreshTocUrl`/`reGetBook`, `sourceRegex` chuyển cho engine.
- **Mở loại**: `LegadoSourcePolicy` nhận chữ + tranh + video (chip "Chưa hỗ trợ" tự mất); Tìm kiếm / Khám phá / Đổi nguồn nhận nguồn tranh/video Legado theo loại.
- **Bộ chạy nghiệm thu**: nguồn tranh/video đo ở bước nội dung (`LegadoCorpusProbe+Media`, trường tuỳ chọn `SourceResult.media`); không đổi API public.
- **Chưa làm**: `coverDecodeJs` (2 nguồn), `imageStyle`, `ruleContent.title`, `canReName`; ghi đè loại theo từng sách (`typeOverride` đã lưu, `BookContentDestination` chưa đọc).
- Chuyển entry `[1.3.535]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới** (`ComicReaderViewModel.swift` 394 → 395). Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.564] - 2026-10-21

### feat: engine nguồn Legado đợt 2 + 3: đăng nhập, trình duyệt từ JS, khám phá có kiểu, font, tệp, RSA

Khối D-engine, E-engine, I, J của plan đợt 2 + 3 nguồn Legado (người dùng đã duyệt). Hành vi theo spec phần 2 §10, §11, §13, §14, §15.3. 43 file mới (~3.450 dòng) + 29 file engine sửa, mọi file ≤ 400 dòng.

- **Đăng nhập** (`Login/`): `source.getLoginInfo*/putLoginInfo/getLoginHeader*/putLoginHeader/removeLoginHeader/login` cài thật; `LegadoLoginStore` lưu thông tin + header đăng nhập trong **Keychain** theo nguồn (Keychain hỏng — vd dưới LiveContainer — thì chỉ giữ trong phiên); `LegadoLoginService` cho UI: trường form từ `loginUi`, gửi đăng nhập, nút hành động, đăng xuất (xoá Keychain + mọi cookie của nguồn), trạng thái, nhập cookie từ WebView. `loginCheckJs` chạy sau request luồng chính; header đăng nhập chỉ gắn khi tên miền trùng nguồn/trang đang đọc (U42).
- **Trình duyệt / mã xác minh từ JS** (`Presentation/`): `java.startBrowser`, `startBrowserAwait`, `startBrowserDp`, `getVerificationCode`… phát yêu cầu qua event center `AsyncStream` (Services, không UI) và chờ **ngoài main** có timeout + huỷ. Chỉ hiện khi lời gọi được bọc `LegadoInteraction.$isInteractive` (người dùng chủ động) và có presenter; mặc định coi là không có người dùng.
- **Khám phá có kiểu**: `LegadoEngineExploreItem` giữ `type` (url/text/button/toggle/select…), `action`, `chars`, `default`, `style`; giá trị chọn đi qua `infoMap` + JS của nguồn (§11.3, không tự chèn vào URL), lưu theo nguồn; `java.refreshExplore` phát sự kiện làm mới.
- **Phần đuôi đợt 2**: URL `data:`, `java.importScript`, `java.toURL`, `Jsoup.connect`, giả lập `javax.crypto` phần hay gặp, `book.*` ghi thuộc tính + cờ cho luồng (`reverseTocOverride`, `typeOverride`, `onRefreshTocUrl`, `onReGetBook`), `fetch(…, sourceRegex:)` + bắt ứng viên phát video qua WebView. Đính chính phần 1 (§15.3): `book.type` dạng bitmask 8/32/64/128; `contentString` giữ outer HTML cho trường nội dung; `src` của `<img>` có option JSON.
- **Đợt 3**: font chống crawl `queryTTF`/`queryBase64TTF`/`replaceFont` (`Font/`, parser TTF tự viết, lỗi ⇒ giữ văn bản gốc); tệp/zip (`Files/`, ZIPFoundation có sẵn, thư mục `legado_state/files/<nguồn>/`, 7z/rar ⇒ "Chưa hỗ trợ định dạng"); RSA `createAsymmetricCrypto`/`createSign` (`Crypto/`, Security framework); chế độ mã hoá đối xứng còn thiếu; phần đuôi `java.*`/`source.*`/`cookie.*`/`cache.*` theo §14. Cố ý không định nghĩa `java.readFile`, `showBrowser`, `showReadingBrowser`, `openWeb` (spec); `java.open`, `openVideoPlayer`, `addBook` vẫn là stub "Chưa hỗ trợ" (hoãn hẳn theo spec). Chưa có shim `android.graphics`, `Inflater`, `java.net.URL`.
- **Ghi vết request** cho màn Gỡ lỗi: `LegadoEngineRequestRecord` + `LegadoEngineDiagnostics.recordRequest/requests` (≤ 100/phiên, mọi request kể cả lỗi, WebView, `data:`), không ghi vào `AppLogger`.
- Chuyển entry `[1.3.534]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới**. 9 bootstrap JS chạy thử trên Node với lệnh native giả: 43/43 phép thử đạt. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.563] - 2026-10-21

### docs: đặc tả hành vi nguồn Legado phần 2 (tranh, video, đăng nhập, quản lý, phần hiếm)

Người dùng: *"làm ra thành phẩm luôn đừng có nghiệm thu"* — chọn làm luôn đợt 2 + 3 (không thử máy giữa chừng), giữ bộ chạy nghiệm thu, giao diện mới dựng mockup trước (đã duyệt cả 3 nhóm màn; giữ cả đăng nhập bằng form lẫn trên web; tab Legado theo công tắc NSFW chung; "Bật/Tắt tất cả" đổi nhãn). Plan đợt 2 + 3 đã duyệt (`Docs/Plans/2026-10-21-plan-nguon-legado-dot-2-3.md`, gitignore).

- **`Docs/Specs/legado-source-spec-part2.md`** (mới, ~1.320 dòng), đánh số nối tiếp phần 1: §8 tranh (nội dung ra ảnh, URL ảnh kèm option, `imageStyle`, `imageDecode`, `coverDecodeJs`) · §9 video (13 nguồn mẫu: 12 trong corpus + 1 từ bộ yckceo 1111 tải thêm; tuyến phát trải thẳng vào mục lục, không có khái niệm server) · §10 đăng nhập (`loginUrl`, `loginUi`, `loginCheckJs`, `source.*Login*`, `java.startBrowser*`/`getVerificationCode`) · §11 Khám phá động (mục text/button/toggle/select, `refreshExplore`, `infoMap`) · §12 quản lý (xuất, scheme nhập nhanh, chế độ gỡ lỗi, `variableComment`) · §13 phần đuôi đợt 2 (`data:`, `sourceRegex`, `preUpdateJs`, `formatJs`, `setReverseToc`, `importScript`, `toURL`, `Jsoup.connect`, `javax.crypto`) · §14 đợt 3 (font chống crawl, tệp/zip, RSA/ký số, mã hoá đối xứng còn thiếu, danh sách đủ phần đuôi `java.*`/`source.*`/`cookie.*`/`cache.*`) · §15 phụ lục (bảng đợt, U29–U63, **đính chính phần 1** 8 mục — vd `book.type` là bitmask 8/32/64/128, khác §6.6).
- Viết bởi agent riêng, cùng luật clean-room như phần 1: chỉ tài liệu trợ giúp được phép + quan sát corpus + 3 lần curl. Nhãn: `[tài liệu]` 60 / `[quan sát]` 128 / `[UNKNOWN]` 53.
- **Kiểm clean-room** (script ngoài repo): tên lớp lạ xuất hiện đều có trong `jsHelp.md` hoặc trong script của corpus; không câu văn xuôi nào trùng nguyên văn tài liệu; 0 chữ cấm.
- Không đổi code; commit chỉ tài liệu nên CI không chạy.
- Chuyển entry `[1.3.533]` sang `CHANGELOG.archive.md` để giữ 30 entry.

## [1.3.562] - 2026-10-21

### feat: bộ chạy nghiệm thu nguồn Legado qua Debug server

Bước 13 của đợt 1 plan "nguồn truyện Legado — viết mới theo đặc tả": đo tỉ lệ nguồn chạy trọn chuỗi để chốt cổng đợt 1 (bộ 1316 nguồn chữ ≥ 55%). Không có UI trong app.

- **`LegadoCorpusRunner`** (`Sources/Services/LegadoSource/Diagnostics/`, 11 file mới): với mỗi nguồn Legado **đã cài** được chọn — tìm (từ khoá `ruleSearch.checkKeyWord`, thiếu thì mặc định; nguồn không có rule tìm thì đi Khám phá qua `genre`) → kết quả đầu → chi tiết → mục lục → nội dung chương đầu, **qua facade `SourceRuntime`** (đúng đường app chạy thật). Song song tối đa 4; trần mỗi bước (tìm/khám phá/chi tiết 60 s, mục lục 300 s, nội dung 120 s); huỷ được. Trạng thái truyện dùng `bookId = "corpus-runner:<packageId>"` nên không đụng sách thật, không sinh sidecar.
- **Phân loại lỗi** (`LegadoCorpusErrorClassifier`): cú pháp chưa hỗ trợ / HTTP (kèm mã) / rule khớp 0 / quá thời gian / mạng / JS / nguồn hỏng / khác. Thông điệp đã redact (giá trị query thành `…`, khối option `,{…}` và URL JS bị che, cắt 300 ký tự), không chứa nội dung chương, header, cookie.
- **Báo cáo** JSON ở `applicationSupport/legado_reports/<thời điểm>.json` (`validatePathSafety`): tổng nguồn, số qua trọn chuỗi, %, đếm theo lớp lỗi và theo bước, chi tiết từng nguồn; một dòng tóm tắt qua `AppLogger` (không gắn `❌`).
- **Debug server — contract v2**: lệnh mới `legado.sources`, `legado.corpus.start` (đầu vào chỉ là danh sách `packageId` **hoặc** "tất cả nguồn Legado đang bật", từ khoá, giới hạn — không nhận URL/đường dẫn/JS), `legado.corpus.status`, `legado.corpus.cancel`; mã lỗi `BUSY`. `ExtensionDebugProtocol.version` 1 → 2 và `ExtensionDebugEvent.contractVersion` 1 → 2 (shape event không đổi); server vẫn nhận envelope v1 nên client cũ chạy như trước, chỉ lệnh `legado.*` đòi v2. Logic ở `ExtensionDebugCommandRouter+Legado.swift` (mới); router gốc chỉ thêm `case`. Không qua `ExtensionDebugInstallGate`: lệnh không ghi thư viện/sách/cài đặt.
- `extensions.list` không còn liệt kê nguồn Legado; `run.start` với nguồn Legado trả `UNKNOWN_ENTRYPOINT` kèm hướng dẫn (không cố chạy `search.js` không tồn tại).
- **Client VS Code** (`Tools/VSCode/FreeBookExtDebug`): mirror `protocol.ts`; 3 lệnh Command Palette chạy / xem tiến độ / huỷ nghiệm thu (`legadoCorpus.ts` mới, `client.ts`, `extension.ts`, `package.json`); client mới gặp app cũ tự hạ về v1. Mô tả gói bỏ tên nền tảng cũ.
- **Log facade**: thông điệp lỗi của nhánh Legado trong `SourceRuntime` được redact URL trước khi ghi file.
- Chuyển entry `[1.3.532]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới**. TypeScript kiểm kiểu với stub theo chữ ký thật (chưa `npm run compile` thật). Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa chạy trên máy.

## [1.3.561] - 2026-10-21

### feat: luồng nguồn Legado, facade SourceRuntime và nối vào Tìm kiếm, Khám phá, Reader, tải truyện

Bước 9, 10 và phần còn lại của bước 11 trong đợt 1 plan "nguồn truyện Legado — viết mới theo đặc tả". Luồng theo `Docs/Specs/legado-source-spec.md` §5.

- **Luồng** (`Sources/Services/LegadoSource/Runtime/`, mới): `LegadoSourceRuntime` + `Search` / `Explore` / `Detail` / `Toc` / `Content` trên engine 1.3.560, trả đúng DTO hiện có (`ExtensionItemResult`, `NovelDetailResult`, `ChapterResult`, `CategoryResult`, `String`). Vòng `nextTocUrl`/`nextContentUrl` dừng + chống lặp theo §5.6, có trần trang; nội dung nhiều trang dùng chung một runtime JS. Mục tên tập (`isVolume`) **không thành chương** (quyết định K), chương đánh số liên tục; chương tên rỗng thành "Chương N"; trang sau lỗi thì giữ phần đã tải. `kind` → thẻ thể loại không có script (chỉ là nhãn). Nguồn đang tắt vẫn đọc tiếp được sách đã có trên kệ.
- **Trạng thái theo truyện** (quyết định G): `LegadoBookStateStore` giữ `tocUrl` + biến truyện/chương **trong bộ nhớ** theo `packageId + bookUrl`; chỉ ghi sidecar `applicationSupport/legado_state/<sha256(bookId)>.json` khi sách đã thật sự tồn tại (đã có mục lục trong `ChapterStore`) — mở trang chi tiết (bookId UUID mới mỗi lần) hay đổi nguồn thất bại không sinh file. Lượt thông tin sách chạy song song với mục lục được gộp (`LegadoBookInfoCoalescer`). `deleteState(bookId:)` static, gọi khi xoá sách và khi đổi nguồn dọn sách cũ.
- **Facade** `SourceRuntime` (`Sources/Services/Extensions/`, mới): giữ **nguyên nhãn tham số** của `ExtensionManager.search/detail/page/toc/chap/genre/home/executeCustomScript` (+ `context: SourceRuntimeContext?` tuỳ chọn ở cuối — bookId, URL sách, tên, tác giả, tiêu đề/chỉ số chương). Tiện ích JS ⇒ chuyển nguyên tham số sang `ExtensionManager` (hành vi không đổi). Nguồn Legado ⇒ engine, **không** qua `cleanAndResolveUrl`. `page` của Legado trả `[url]` (vòng mục lục nằm trong `toc`); `home` trả `[]`, `genre` trả các mục khám phá bấm được với script giả `__legado_explore__`. Tranh/video Legado ném "chưa hỗ trợ ở bản này".
- **Call site** đổi sang facade (không đổi logic tiện ích JS): `ChapterContentRepository` (tách `+SourceFetch`), `BookDetailLoader` (+`context:`), `BookDetailView+Extensions/+TOCPreparation`, `SearchView`, `DiscoveryView+Loading`, `PaginatedNovelLoader`, `AllCommentsView`, `CommentSectionView`, `SuggestRowView`, `NewChapterProbe`, `ExportContentProvider`, `DownloadManager`. `BookDownloadWorker` rẽ nhánh Legado **trước** `prepareIfNeeded`/`cleanAndResolveUrl` (`+Legado`), vẫn tuần tự và huỷ được.
- **Lọc nguồn**: `SearchExtensionScopePolicy.isSearchScoped`/`isDiscoverable` — Tìm kiếm, Đổi nguồn chỉ nhận nguồn Legado đang bật + loại đã hỗ trợ + có rule tìm; Khám phá thêm điều kiện có `exploreUrl` (tranh/video Legado bị chặn dù "browsable" theo loại). **Tìm mọi nguồn**: tiện ích JS song song như cũ, nguồn Legado qua cửa sổ trượt tối đa 8 (`LegadoSearchScheduler`, mới). Ẩn nút ⚙ cấu hình JS cho nguồn Legado ở bảng chọn nguồn Khám phá; trình duyệt bỏ nguồn Legado khỏi lối tắt và bước dò URL; kiểm chương mới bỏ sách Legado không chạy được và chờ danh sách Legado nạp (≤ ~5 s).
- **Phân trang Khám phá**: `PaginatedNovelLoader` nhận chỗ cắm `{{…page…}}`; với mục khám phá Legado chỉ tin `nextPage` của runtime và dừng khi trang không thêm mục mới (trang web bỏ qua số trang không làm tải mãi).
- **Trang chi tiết**: thẻ thể loại không có script hiện dạng nhãn tĩnh (`BookDetailHeaderView.genreChip`), không mở danh sách hỏng. Tiện ích JS luôn có script nên không đổi.
- **Log**: chẩn đoán mềm của engine chỉ gắn `❌` cho 3 mục đầu mỗi phiên (trước là 20) để "tìm mọi nguồn" không làm tràn file log; lỗi `search` của facade không gắn `❌`.
- **Còn nợ**: chưa dọn sidecar mồ côi lúc mở app; thêm sách rồi thoát trước lượt mục lục kế tiếp thì mất biến của lượt tìm; `canReName`, `ruleContent.title`, `isVip`/`updateTime` chưa dùng; nhập lại nguồn với `bookSourceType` khác đổi loại của sách đã lưu từ nguồn đó.
- Chuyển entry `[1.3.531]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới** (`SearchView.swift` 821 → 794, `ChapterContentRepository.swift` 455 → 430; các file legacy khác ≤ baseline). Không còn `ExtensionManager.shared.(search|detail|toc|chap|page|home|genre|executeCustomScript)(` ngoài facade. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.560] - 2026-10-21

### feat: engine nguồn Legado (rule, mạng, JS) viết mới theo đặc tả

Bước 6, 7, 8 của đợt 1 plan "nguồn truyện Legado — viết mới theo đặc tả". Viết mới hoàn toàn từ `Docs/Specs/legado-source-spec.md` (clean-room), 65 file / ~7.600 dòng dưới `Sources/Services/LegadoSource/{Rule,Net,JS,Engine}/`. Chưa có caller — luồng + facade ở commit sau.

- **Rule** (`Rule/`): đường ống phân đoạn `<js>`/`@js:`; 4 chế độ — mặc định kiểu jsoup (`LegadoJsoupSelector` trên SwiftSoup), CSS `@css:`, JSONPath tự viết có filter (`LegadoJSONPathEvaluator`/`Filter`), XPath trên libxml2 (`LegadoXPathDocument` mở rộng: ngữ cảnh theo nút, nút/chuỗi, serialize; `LegadoXPathNode`); regex danh sách `:`; toán tử `||` `&&` `%%`; đuôi `##`/`###`; chỉ số `.0` `.-1` `!0` `[a:b:c]` `[1,3]`; mẫu `{{…}}`/`{$.x}`/`@get:{}`; `@put`; tiền tố `-`/`+` của rule danh sách. Bộ quét có nhận biết nháy/ngoặc (`LegadoRuleScanner`), regex cache theo pattern (`LegadoRegexCache`), HTML → văn bản (`LegadoHTMLText`). Parser JSON lỏng riêng của engine (`LegadoEngineJSONParser`).
- **Mạng** (`Net/`): dựng request theo thứ tự §3.2 — khối option `,{…}`, placeholder trang/từ khoá, `<a,b>`, mã hoá query/form theo `charset` kể cả GBK (`LegadoURLEncoder`, `LegadoCharset`), body + Content-Type; header nguồn JSON hoặc JS tính mỗi request; HTTP client riêng tự đi chuyển hướng để giữ `Set-Cookie` mọi chặng; cookie jar **theo nguồn** khi `enabledCookieJar`; `retry`; giải mã phản hồi theo §4.5; `concurrentRate` (cả `N/ms` và số ms) dùng chung giữa mọi phiên của cùng nguồn (`LegadoRateLimiter`); WebView ẩn qua `WebViewLoader` có sẵn (nhảy main bất đồng bộ, thread engine chờ theo lát ngắn — không semaphore trên main).
- **JS** (`JS/`): JavaScriptCore **riêng** (không dùng `JSExecutor`) chạy trên thread nền chuyên dụng, một native dispatcher; `java.*` đợt 1 theo spec §6.4 (mạng `ajax`/`ajaxAll`/`connect`/`get`/`post`/`head`; rule `getString`/`getStringList`/`getElements`/`getElement`/`setContent`/`put`/`get`/`toNumChapter`; mã hoá/băm/base64/hex/AES/DES/HMAC; `log`/`toast`/`timeFormat`/`t2s`/`s2t`/`htmlFormat`/`randomUUID`/`androidId`/`getWebViewUA`/`getCookie`), `source`, `book`, `chapter`, `cookie`, `cache`, shim `org.jsoup`, `Packages`/`JavaImporter` giả lập phần hay gặp. `jsLib` nạp một lần mỗi runtime. Hàm hoãn (§6.11: `startBrowser*`, đăng nhập, `refreshExplore`, font, file/zip…) ném lỗi "Chưa hỗ trợ <tên> ở bản này" để bộ chạy nghiệm thu phân loại; cố ý không định nghĩa `java.qread`, `deviceID`, `reLoginView`, `getUserAgent` (§6.10). `toast` chỉ ghi log (Services không toast).
- **Phiên** (`Engine/`): `LegadoEngineSession.run` chạy thân tác vụ trên thread engine, huỷ được, không bao giờ bọc `CancellationError`; `LegadoEngineSource` (bối cảnh nguồn, không phụ thuộc model của kho); `LegadoBookContext`/`LegadoChapterContext` (biến truyện/chương — luồng ở commit sau ghi sidecar); `LegadoEngineError` phân loại `category` (cú pháp chưa hỗ trợ / HTTP / quá thời gian / JS…), lỗi mềm vào `LegadoEngineDiagnostics`. Biến nguồn, `source.put`, `cache.*`, cookie, `jsLib` dạng map, `androidId` lưu file dưới `applicationSupport/legado_state/` (`LegadoFileStateStore`); `cache.putMemory` chỉ trong bộ nhớ.
- **Tự chọn khi spec chưa nói** (cần đo bằng bộ chạy nghiệm thu): phân đoạn JS đứng đầu nhận `result` là chuỗi thân trang; XPath `//x` dưới một mục hiểu là tương đối với mục; placeholder trong mã JS chỉ nhận `{{…}}` và `@get:{}`; `book.setReverseToc`/`setUseReplaceRule` chỉ ghi chẩn đoán. WebView dùng kho dữ liệu WebKit mặc định (chung cookie với trình duyệt của app), POST qua WebView có thể mất body, mã trạng thái luôn 200.
- Chuyển entry `[1.3.530]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới**; mọi file ≤ 400 dòng; không có tên/đường dẫn của mã nguồn gốc trong code. Bootstrap JS đã qua `node --check`. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.559] - 2026-10-21

### feat: kho nguồn Legado và tab Nguồn Legado trong Kho Tiện Ích

Bước 4, 5, 12 và phần màn Kho của bước 11 trong đợt 1 plan "nguồn truyện Legado — viết mới theo đặc tả" (người dùng đã duyệt plan + mockup). Hành vi Legado theo `Docs/Specs/legado-source-spec.md`.

- **Model** (`Sources/Models/LegadoSource/`, mới): `LegadoBookSource` (+`Derived`) decode khoan dung qua `LegadoModelJSON`/`LegadoModelCoercion` (số-hoặc-chuỗi, bool-hoặc-số, nhóm rule là object hoặc chuỗi JSON lồng, giữ JSON gốc), `LegadoSearchRule` (dùng chung cho khám phá), `LegadoBookInfoRule`, `LegadoTocRule`, `LegadoContentRule`, `LegadoExploreEntry` (dạng không phải JS của `exploreUrl`), `LegadoSourceKind` (0 chữ / 2 tranh / 4 video / còn lại không hỗ trợ), `LegadoSourceSummary`, `LegadoSourceGroupCount`.
- **Kho** (`Sources/Services/LegadoSource/Store/`, mới): mỗi nguồn là `extensions/<packageId>/` gồm `source.json` (nguyên văn) + `plugin.json` sinh tự động (`author: "Legado"`, `type` họ `legado*`, `locale: zh_CN`, `version` tăng mỗi lần ghi). `packageId = "legado_" + sha256(bookSourceUrl đã trim).prefix(16)` — đóng băng. Nhận diện nguồn Legado theo `Extension.type`, không theo tiền tố. Bật/tắt vá đúng khoá `enabled`. `LegadoSourceImporter` nhận mảng / object / chuỗi escape, bỏ trùng theo `bookSourceUrl`, bỏ qua kèm lý do: audio, tệp tải về, loại lạ, thiếu `bookSourceUrl`, thiếu rule tối thiểu (bản nới: tìm **hoặc** khám phá + mục lục + nội dung). `LegadoSourceRepository` (`@MainActor @Observable` + bảng chụp nonisolated cho tầng nền: `isEnabled(packageId:)`, `summarySnapshot(packageId:)`) nạp trên nền sau cổng từ điển, dịch QT tên + nhóm một lần rồi cache. `LegadoSourceCoordinator`: nhập tệp/URL/bộ nhớ tạm, bật/tắt, bật/tắt hàng loạt, xoá, xoá tất cả — ghi file trên nền rồi **một** lời gọi `upsertExtensions`. `installOrigin` mới `"legadoImport"`.
- **`LegadoSourcePolicy`** (mới, thuần): `isLegado`, `excludingLegado`, `isRunnable` (Legado + đang bật + loại đã hỗ trợ — đợt 1 chỉ chữ).
- **UI tab "Nguồn Legado"** (segment thứ 3 của Kho Tiện Ích, khớp mockup): toolbar chỉ menu ⋯ (nhập từ tệp JSON / URL / bộ nhớ tạm · bật/tắt tất cả theo danh sách đang lọc · "Xoá tất cả nguồn Legado" có xác nhận); ô "Tìm nguồn Legado" khớp tên gốc lẫn tên QT; chip nhóm có số đếm (sắp theo số nguồn, cuối là "Chưa nhóm"); dòng "Đang bật x/y"; dòng nguồn: tên QT, chip loại + nhóm (tối đa 2, còn lại "+N"), "Cần đăng nhập", "Chưa hỗ trợ" cho tranh/video, URL, công tắc, nút 🗑 34×34 xoá ngay. Alert tổng kết "Đã nhập N nguồn" (mới / cập nhật / bỏ qua theo lý do / "Nguồn giữ trạng thái bật/tắt trong tệp"). File: `LegadoSourceListView`, `LegadoSourceRowView`, `LegadoSourceTabState`, `RepositoryManagerView+LegadoMenu`; nút 🗑 tách thành `ExtensionRowTrashButton` dùng chung cho hai tab.
- **Chặn rò rỉ ở màn Kho**: tab 0 và số đếm bộ lọc loại nguồn Legado; "Xóa tất cả tiện ích" chỉ gỡ tiện ích JS; audit gỡ bản ghi thì nạp lại danh sách Legado. `RepositoryManagerView.swift` 606 → 605 dòng; chữ hướng dẫn ở tab "Danh sách kho" bỏ tên nền tảng cũ, nay là "kho tiện ích".
- **Coordinator**: thêm `ExtensionTransactionCoordinator.deleteExtensions(packageIds:)` — xoá nhiều bản ghi, ghi index một lần (xoá tất cả nguồn Legado).
- **Backup**: `BackupExtensionInstaller` dựng bản ghi Legado từ thư mục thật sau bước thay (type/version theo `plugin.json`); `BackupRestoreWorker` nạp lại danh sách sau khôi phục.
- **Hiệu năng (bộ 1316, 1.378 nguồn, ~10 MB)**: parse, phân loại, ghi file, dịch QT đều trên nền; main chỉ nhận kết quả + một lần upsert. Mô phỏng phân loại: nhập 804, bỏ qua 574 (thiếu rule tối thiểu 535, tệp 21, audio 11, trùng 6, thiếu URL 1).
- **Chưa xong / cần xác nhận**: tab Legado chưa áp công tắc NSFW (195 nguồn nhóm `特殊书源 🔞`); tên QT hiện kể cả khi tắt dịch toàn app; bật/tắt không tăng `version`. Tìm kiếm / Khám phá / Đổi nguồn / tải truyện / debug server chưa nối — commit sau.
- Chuyển entry `[1.3.529]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.558] - 2026-10-21

### docs: đặc tả hành vi nguồn Legado đợt 1 (clean-room)

Bước 2 của đợt 1 plan "nguồn truyện Legado — viết mới theo đặc tả": `Docs/Specs/legado-source-spec.md` (mới, ~1.630 dòng) là **nguồn sự thật duy nhất** về "Legado chạy thế nào" cho các agent triển khai.

- **Viết bởi một agent riêng**, chỉ từ tài liệu trợ giúp được phép (`ruleHelp.md`, `jsHelp.md`, `xpathHelp.md`, `regexHelp.md`, `debugHelp.md`…) + quan sát 6 bộ corpus yckceo (1315, 1316, 1208, 1158, 1298, 1272 — 3.701 nguồn sau bỏ trùng, 3.406 nguồn chữ) + ~20 lần curl trang thật. Không đọc mã nguồn Legado/Yuedu/nhánh cũ. Corpus nằm ngoài repo.
- **Mục lục**: §0 phạm vi + luật nhãn · §1 model JSON (decode khoan dung, tách nhóm, loại, rule tối thiểu — 84% nguồn chữ đạt) · §2 rule (đường ống, nhận diện chế độ, `||` `&&` `%%`, `##`/`###`, placeholder, phương ngữ kiểu jsoup, CSS, `@put`/`@get`, JSONPath, XPath, regex danh sách) · §3 URL (khối option, placeholder, `<a,b>`, charset, header) · §4 mạng (`concurrentRate`, cookie, retry, WebView, redirect) · §5 luồng (tìm, khám phá 3 dạng, thông tin, mục lục, nội dung, phân trang + chống lặp, biến, `jsLib`) · §6 JS bridge (danh sách hàm `java.*`/`source.*`/`book`/`chapter`/`cookie`/`cache` đợt 1 theo tần suất, shim `org.jsoup`, hàm hoãn) · §7 phụ lục (bảng đợt 1/hoãn, 28 điểm `[UNKNOWN]` U1–U28 để bộ chạy nghiệm thu đo).
- Mỗi khẳng định gắn `[tài liệu]` (112) / `[quan sát]` (151) / `[UNKNOWN]` (62); `[đề xuất]` là ghi chú khuyến nghị khi không có bằng chứng (§0.3).
- **Kiểm clean-room** (script ngoài repo): không có tên lớp nội bộ của engine gốc ngoài những tên xuất hiện trong script của chính corpus; không câu nào trùng nguyên văn tài liệu (cửa sổ 40 ký tự / 15 chữ Hán); 0 chữ cấm.
- Không đổi code. Không build — commit chỉ có tài liệu nên CI không chạy.
- Chuyển entry `[1.3.528]` sang `CHANGELOG.archive.md` để giữ 30 entry.

## [1.3.557] - 2026-10-21

### build: link libxml2 cho XPath của nguồn Legado, CI chạy trên nhánh Legado

Bước 3 của đợt 1 plan "nguồn truyện Legado — viết mới theo đặc tả" (2026-10-19, người dùng đã duyệt): chứng minh libxml2 hệ thống link được trên CI trước khi xây engine rule.

- **`project.yml`**: thêm `- sdk: libxml2.tbd` cạnh `libsqlite3.tbd`, và `HEADER_SEARCH_PATHS` = `$(inherited)` + `$(SDKROOT)/usr/include/libxml2` (header của libxml2 tự include nhau theo dạng `<libxml/...>`).
- **Bridging header gom chung**: `SWIFT_OBJC_BRIDGING_HEADER` đổi từ `VieNeuONNXBridge.h` sang `Sources/Common/Bridging/FreeBookBridgingHeader.h` (mới), file này include `VieNeuONNXBridge.h` (không đổi nội dung) và `LegadoLibXML2.h` (mới — `HTMLparser.h`, `tree.h`, `xpath.h`, `xpathInternals.h`). Sai đường dẫn ở đây là mọi file Swift hỏng.
- **`LegadoXPathDocument`** (mới, `Sources/Services/LegadoSource/Rule/`): bọc `htmlReadMemory` (RECOVER/NOERROR/NOWARNING/NONET) + `xmlXPathEval`, trả giá trị chuỗi của node-set/string/number/boolean. **Không** `#if canImport`, không fallback: thiếu libxml2 phải là lỗi biên dịch. Chưa có caller — engine rule ở các commit sau.
- **CI**: `build-ipa.yml` chạy cả trên nhánh `claude/legado-source-bb5e46`.
- Chuyển entry `[1.3.527]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền (`JSDom.swift`, `TTSManager.swift`), **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch.

## [1.3.556] - 2026-10-21

### feat: thanh gợi ý token trên bàn phím ở màn thêm rule dịch

Người dùng: *"thêm thanh gợi ý nhập các loại token vào phần nhập vế trái … token nghĩa vào phần nhập vế phải thêm rule dịch"*, *"ý tôi là thêm thanh gợi ý vào bàn phím"*; duyệt mockup bản gọn (*"token 1 hàng thôi"*) rồi duyệt plan.

- **Thanh công cụ bàn phím chung có thêm hàng gợi ý tuỳ chọn** nằm trên hàng `aa…AA` · xoá · sao chép · dán. Ô nhập nào cài `KeyboardSuggestionSource` (mới, `KeyboardSuggestion.swift`) thì có hàng; mọi ô khác vẫn một tầng. Hàng (`KeyboardSuggestionRowView`, mới) là một dòng chip cuộn ngang, mép phải mờ dần. `KeyboardTextToolbarInstaller` đổi chiều cao accessory 46 ↔ 82pt lúc ô **bắt đầu gõ** (model gắn trước, rồi mới `reloadInputViews()`), không đổi giữa chừng. Bấm chip ⇒ `KeyboardTextToolbarModel.applySuggestion` chèn qua `UITextInput.insertText` như Dán, nên binding, con trỏ và hoàn tác đi đúng đường gõ tay; đang bôi đen thì thay đoạn đó.
- **Ô Mẫu** (vế trái): đủ 13 token theo thứ tự nhóm của bảng token, rồi `( | ) )?`; token đang tắt ở Cấu hình token rule hiện mờ. **Ô Bản dịch** (vế phải): `{0} {1}…` theo token của mẫu, đã dùng có ✓, chưa dùng đỏ; mẫu chưa có token thì không có hàng.
- **Lọc theo phần gõ dở**: sát trước con trỏ là `<h` (hoặc `{1`) thì chỉ còn chip khớp và chip thay luôn đoạn gõ dở; không khớp thì hiện đủ. Bỏ qua `\<` (escape) và lúc con trỏ nằm giữa một token đã viết xong. Logic ở `QuickTranslationRuleKeyboardSuggestions` (mới); `QuickTranslationRulePatternField` dùng `SuggestingTextView` (lớp con `UITextView`) và tham số `keyboardSuggestionMode`.
- `QuickTranslationRuleTokenPaletteView`: danh sách token, cú pháp nhóm và nhãn chuyển từ `private` sang `internal` để hàng gợi ý dùng lại, không chép. Bảng token và dải `{i}` trong form giữ nguyên.
- Chuyển entry `[1.3.526]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI xác nhận biên dịch; chưa thử trên máy.

## [1.3.555] - 2026-10-20

### feat: đưa lại nút xoá, sao chép, dán cạnh ô nhập, thêm nút viết hoa

Người dùng: *"thêm lại copy, paste, clear và các nút format viết hoa … vào ô nhập"* — chọn "nút cạnh ô như cũ" (thanh công cụ trên bàn phím vẫn giữ), duyệt plan; kèm *"giảm size nút nsfw … nút quá to"*.

- **Khôi phục nguyên văn** phần đã gỡ ở `[1.3.548]` (`b4c67e26`), đảo ngược đúng các hunk gỡ nút, không đụng code thanh bàn phím:
  - `TextFieldClipboardButtons` (↺ · xoá · sao chép · dán, **dán thay cả giá trị**) ở Cấu hình tiện ích (biến cấu hình) và Thông tin plugin.json; xoá `RestoreDefaultValueButton` vì ↺ quay về trong bộ nút này.
  - `clipboardToolbar` (**dán nối thêm dòng**) ở Thêm từ nhiều dòng (`DictEntrySheet`), Bộ nhớ AI (4 ô), Cài đặt AI (API keys, models).
  - Nút ✕ / sao chép / dán tròn (dán **chèn tại con trỏ**, có toast) ở ô Mẫu và ô Bản dịch của Thêm/Sửa rule; Xoá / Sao chép / Dán ở ô chữ thử VieNeu; nút Dán tròn ở panel Dịch của Reader (bỏ lại hàm `hideKeyboard` riêng mà `[1.3.552]` đã gỡ).
- **`TextCaseButtonGroup`** (mới, `Views/Common`): 5 nút `aa · Aa¹ · Aa² · Aa · AA` cao 26pt khớp bộ nút cạnh ô, luật đổi chữ dùng lại `TextCaseFormatter`. Gắn ở: Thêm từ nhiều dòng (đầu hàng nút; **chỉ đổi phần nghĩa** sau dấu `=` đầu tiên của từng dòng, dòng không có `=` giữ nguyên), Sửa từ (dòng dưới ô "Nghĩa dịch"), ô Bản dịch của Thêm/Sửa rule. Không gắn ở ô URL/khoá/API key, Bộ nhớ AI, chữ thử VieNeu (đoạn văn dài — `aa` sẽ viết thường cả đoạn) và ô Mẫu rule (thường là chữ Hán).
- **Nút NSFW** ở bảng chọn nguồn Khám phá (`[1.3.554]`) thu nhỏ: viên thuốc cao 26pt, chữ 12pt, icon 11pt — nhỏ hơn chuẩn nút header 38pt theo yêu cầu người dùng; vùng chạm vẫn 36×38pt.
- Chuyển entry `[1.3.525]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI xác nhận biên dịch; chưa thử trên máy.

## [1.3.554] - 2026-10-20

### feat: Khám phá giữ tab home khi có explore, nút NSFW ở bảng chọn nguồn

Người dùng: *"hãy sửa để home không bị bỏ"* và *"thêm bật tắt nfsw ở màn chọn ext ở khám phá nữa"* (duyệt mockup B: nút trên thanh tiêu đề).

- **Giữ tab `home` — cố ý khác hợp đồng**: `extension-api.md` (Darkrai9x, dòng 214–216 và 433–434) quy định khai cả `explore` lẫn `home` thì `explore` thắng, `home` bị bỏ. Nay `DiscoveryView.fetchCatalog` luôn gọi `home` song song với `genre`; tab "Trang chủ" dạng section (`ExploreSectionsView`) **đứng đầu**, các tab `home` xếp sau. Dùng lại đúng `exploreTab` truyền vào để trang section không bị dựng/tải lại. Đừng "sửa" về lại cho khớp hợp đồng.
- **Gán tab sớm** (`loadDiscoveryData`): giữ tạm các tab `home` cũ cạnh tab explore mới, để tải lại cùng nguồn (đổi cấu hình, `extensionDidUpdate`) không đẩy người đang xem tab `home` về "Trang chủ". Đổi nguồn thì danh sách đã bị xoá trước nên vẫn mở vào "Trang chủ"; tab `home` xem lần trước không được khôi phục khi có `explore`.
- **Thanh chip** không đổi code: điều kiện cũ đã tự hiện khi có tab `home` thật.
- **Hợp đồng không cho tải bất đồng bộ từng section**: section chỉ có `type, title, subtitle, id, items, shape, more` (không có `script`/`input` riêng) và `fetch` là hàm đồng bộ — đường tải sau duy nhất là action `list` ("Xem thêm"). Không làm gì thêm ở đợt này.
- **Nút NSFW** ở góc phải thanh tiêu đề của `ExtensionSelectorView`: viên thuốc `eye.slash`/`eye` + "NSFW", cao 38pt, bật thì tô màu nhấn như chip đang chọn của `ExtensionKindFilterBar`. Dùng chung khoá toàn app `RepositoryFilterPolicy.includeNsfwDefaultsKey` (Kho, Tìm kiếm, Lịch sử, Cài đặt đổi theo; vẫn tự tắt mỗi lần mở app). Danh sách nguồn do `DiscoveryView` lọc theo cùng khoá nên đổi ngay; tắt khi đang xem nguồn NSFW thì `DiscoveryView` tự chuyển nguồn như cũ. Chú thích ở `NsfwSettingsView` nhắc thêm chỗ bật nhanh này.
- Ghi luật giữ tab `home` vào `CLAUDE.md`/`AGENTS.md` (mục Comic & Video). Chuyển entry `[1.3.524]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI xác nhận biên dịch; chưa thử trên máy.

## [1.3.553] - 2026-10-19

### fix: tiêu đề nhóm ở kiểu lưới của kệ sách dính đầu khi cuộn như danh sách

Người dùng: *"phần section đang ghim, truyện khác, ngày ở kệ sách, lịch sử nếu chọn kiểu khác danh sách scroll lên không còn hiển thị sticker như danh sách"*.

- **Vì sao**: kiểu danh sách là `List` `.plain` nên tiêu đề nhóm tự dính đầu màn; kiểu lưới (`ShelfBooksLayoutView`, `[1.3.546]`) bọc `LazyVGrid` trong một `LazyVStack` (để đặt sentinel tải thêm) và không khai `pinnedViews`, nên tiêu đề cuộn trôi theo thẻ.
- **Sửa**: `LazyVGrid(pinnedViews: [.sectionHeaders])` nằm thẳng trong `ScrollView`; sentinel tải thêm chuyển thành **footer** của một section rỗng (vẫn trải hết bề ngang, vẫn dựng lười, giữ `.id(loadedCount)`). Tiêu đề lưới có nền đặc `systemBackground` tràn qua lề 16pt để thẻ cuộn bên dưới không lộ ra.
- **Áp cho**: "Đang ghim" / "Truyện khác" ở Kệ sách và chi tiết Bộ sưu tập, từng ngày ở Lịch sử (cùng `ShelfBooksLayoutView`). Phía Khám phá không có tiêu đề nhóm — không đổi.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI xác nhận biên dịch; chưa thử trên máy.

## [1.3.552] - 2026-10-19

### fix: các màn tự tắt bàn phím khi chạm nền theo đúng tuỳ chọn

Người dùng: *"dù cài đặt tắt tay nhưng vẫn đang tự động tắt"* — chọn "Không tắt bàn phím" mà chạm ra ngoài ô nhập vẫn tắt.

- **Vì sao**: `KeyboardDismissGesture` (bộ chung ở window) có đọc `KeyboardDismissPreference`, nhưng 4 màn tự gắn `.onTapGesture` tắt bàn phím riêng từ trước thì không.
- **`KeyboardDismissPreference.dismissOnTapOutsideIfEnabled()`** (mới): chỉ tắt khi tuỳ chọn là "Tự tắt". Bốn chỗ chuyển sang gọi nó: panel Dịch/tra từ (`ReaderDefinitionOverlayView`), panel xoá rác (`ReaderJunkDeleteOverlayView`), sheet công cụ tìm kiếm (`SearchEnginesConfigView`), vùng trống hai thanh dưới của trình sửa Script (`ExtensionScriptEditorView`); bỏ hai hàm `hideKeyboard()` riêng không còn dùng.
- **Không đổi**: phím Return của ô một dòng, kéo danh sách, nút đóng bàn phím ở thanh công cụ và nút tắt bàn phím của trình sửa Script vẫn tắt như cũ.
- Chuyển entry `[1.3.522]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI xác nhận biên dịch; chưa thử trên máy.

## [1.3.551] - 2026-10-19

### fix: thanh công cụ bàn phím có nền riêng, không lệch khỏi bàn phím

Người dùng (ảnh máy thật, màn "Thêm rule", bàn phím nổi kiểu mới): *"vỡ UI bàn phím"* — sau `[1.3.550]` thanh đã hiện nhưng nổi lơ lửng không nền, chữ của màn bên dưới lộ qua giữa các nút và có khoảng hở với bàn phím.

- **Vì sao**: thanh dựa vào nền `.keyboard` của `UIInputView`, nhưng bàn phím nổi kiểu mới để nền đó trong suốt; `UIHostingController` trong accessory còn tính vùng an toàn nên đệm thêm khoảng trống.
- **`KeyboardTextToolbarView`**: thanh tự có nền — viên kính `.regularMaterial` bo tròn, viền mảnh, cách mép 6pt; tổng cao vẫn 46pt.
- **`KeyboardTextToolbarInstaller`**: `host.safeAreaRegions = []`.
- Chuyển entry `[1.3.521]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI xác nhận biên dịch; chưa thử trên máy.

## [1.3.550] - 2026-10-19

### fix: thanh công cụ bàn phím không hiện ở ô nhập SwiftUI

Người dùng (kèm 2 ảnh chụp máy thật — sheet "Quản lý nghĩa từ" và "Thêm từ mới"): *"fix lỗi thanh trên bàn phím hoàn toàn không được thêm vào"*.

- **Vì sao** (đọc code, chưa xác nhận trên máy): `[1.3.548]` gắn thanh bằng cách gán `inputAccessoryView` lúc `textDidBeginEditing`, nhưng (1) `canAttach` bỏ qua mọi ô "đã có accessory của người khác" — ô `TextField`/`TextEditor` của SwiftUI rất có thể có sẵn accessory nội bộ (cho `.toolbar(placement: .keyboard)`) nên bị bỏ qua hết; (2) lớp nội bộ của SwiftUI có thể override getter / gán đè nên giá trị gán từ ngoài không ăn.
- **`KeyboardAccessoryOverride`** (mới): giữ thanh trong associated object của đúng ô rồi thay getter `inputAccessoryView` của **lớp cụ thể** đó (mỗi lớp một lần) — có gắn thì trả thanh, không thì gọi getter gốc. Không bao giờ thay getter của `UITextField`/`UITextView` gốc.
- **`KeyboardTextToolbarInstaller`**: bỏ `canAttach` (app không có màn nào tự gắn accessory); lớp SwiftUI luôn đi đường thay getter, lớp UIKit gán thẳng rồi đọc lại — không ăn thì chuyển sang thay getter. Ngoại lệ giữ nguyên: ô mật khẩu/API key, `CodeEditorTextView`.
- **Log chẩn đoán** một lần mỗi lớp ô: `⌨️ [KeyboardToolbar] lớp ô …, accessory sẵn có …: <cách gắn>` (cần bật log trong Cài đặt); trường hợp hỏng có `❌` nên luôn được ghi.
- Chuyển entry `[1.3.520]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI xác nhận biên dịch; **chưa thử trên máy** — nếu thanh vẫn không hiện, gửi dòng log `⌨️ [KeyboardToolbar]`.

## [1.3.549] - 2026-10-19

### feat: chặn quảng cáo theo bộ lọc AdGuard, chặn popup và chế độ máy tính cho webview

Người dùng: *"tìm cách nâng cấp chặn quảng cáo trong trình duyệt của freebook… Thêm chế độ mở ở máy tính/điện thoại. bật/tắt chặn quảng cáo cho browser"*, *"có thể config chặn quảng cáo của aloha browser không"*; chốt qua `/grill-me` (plan `Docs/Plans/2026-10-19-plan-chan-quang-cao-trinh-duyet.md`, 3 mockup đã duyệt).

- **Vì sao**: chặn cũ chỉ là 11 chuỗi tên miền (`isEngineDomainBlocked`) xét ở `decidePolicyFor` ⇒ chỉ huỷ được điều hướng trang/iframe; script, ảnh, XHR quảng cáo vẫn tải, và mọi `window.open` của trình duyệt mở thành tab mới. Aloha không lấy cấu hình được (mã đóng) nhưng dùng nguồn công khai: bộ lọc AdGuard.
- **Bộ lọc** (`Sources/Services/Browser/AdBlock/`, 16 file): `WKContentRuleList` từ AdGuard bản tối ưu iOS — bật sẵn Base, Mobile Ads, ABPVN, Chinese; tắt sẵn Popups, Cookie Notices, Tracking. Chuyển đổi bằng **SafariConverterLib 4.3.1** (SPM mới, GPL-3.0 — app vốn đã GPL qua espeak-ng), mỗi bộ một rule list `adblock-<id>`, tự tải lại khi quá hạn `! Expires:` (5 ngày) + nút Cập nhật ngay. Bản đóng gói `Sources/Resources/AdBlock/` (4 bộ, `Scripts/update_adblock_snapshot.py`, `.gitattributes` giữ CRLF cho checksum; bỏ 3 dòng luật bên thứ ba chứa chuỗi bị cấm của repo).
- **Chính sách** `WebContentPolicy` → `WebContentConfigurator`: trình duyệt = chỉnh riêng theo tên miền ?? cài đặt chung; webview tiện ích = `Extension.adBlockOverride ?? chung`, `desktopModeOverride ?? false`; UA track video tự khai thắng chế độ máy tính. Áp cho 5 webview (`BypassBrowserTabStore`, `WebViewLoader`, `VisibleWebViewController`, `VideoEmbedWebView`, `VideoMediaSniffer`), đều chuyển sang `decidePolicyFor:preferences:` để đặt `preferredContentMode`. Gemini/Google Drive giữ nguyên.
- **Chặn popup** (trình duyệt, công tắc riêng): `createWebViewWith` không do bấm link (`!= .linkActivated`) sang tên miền khác ⇒ chặn + dải báo "Đã chặn cửa sổ bật lên" có nút Mở.
- **UI**: nút khiên thay ổ khoá trong ô URL (bảng: Chặn quảng cáo / Xem bản máy tính — nhớ theo tên miền, nạp lại tab); màn **Cài đặt → Trình duyệt** (thay "Trình duyệt hiển thị": chặn QC, chặn popup, 7 bộ lọc + trạng thái, mặc định Điện thoại/Máy tính, trang đã chỉnh riêng, công tắc thu nhỏ cũ); **Cấu hình tiện ích → Trình duyệt** (`+WebContent`, lưu ngay).
- **Dữ liệu**: `Extension` thêm `adBlockOverride`, `desktopModeOverride` (JSON, decode khoan dung; có trong sao lưu/khôi phục); `applicationSupportDirectory/adblock/` (Backup không gói); 4 khoá UserDefaults `web*`.
- **Không làm**: scriptlet/extended CSS (đợt 2), bộ lọc tự thêm, đếm số quảng cáo đã chặn (WebKit không có API).
- Chuyển entry `[1.3.519]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới**; rà soát phản biện bằng agent (chữ ký API SafariConverterLib đối chiếu nguồn v4.3.1, caller của mọi init đổi chữ ký). Không build tại chỗ (Windows) — CI xác nhận biên dịch; **chưa thử trên máy**. Chưa chắc: tab `window.open` dùng chung `WKUserContentController` với tab mẹ, popup tạo bằng `a.click()` có bị báo `.linkActivated` không, và nếu chữ ký `decidePolicyFor:preferences:` lệch SDK thì WebKit không gọi (CI vẫn xanh) — kiểm trên máy theo §8 plan.

## [1.3.548] - 2026-10-19

### feat: thanh công cụ trên bàn phím cho mọi ô nhập, chọn tự tắt bàn phím

Người dùng: *"xoá · sao chép · dán cho các ô nhập của màn hình thêm từ mới (phiên âm NghiTTS), thay thế TTS, quản lý nghĩa từ, sửa từ trong từ điển; bổ sung aa Aa1 Aa2 Aa AA…"* → *"thêm chung trên bàn phím ở mọi chỗ dùng bàn phím trong app"*, *"thêm 1 nút đóng bàn phím ở ngoài cùng bên trái"*, *"thêm config tự tắt/tắt tay"*. Plan: `Docs/Plans/2026-10-19-plan-thanh-cong-cu-ban-phim.md` (mockup đã duyệt).

- **Thanh trên bàn phím** (`Sources/Views/Common/KeyboardToolbar/`): `KeyboardTextToolbarInstaller` nghe `textDidBeginEditing` của `UITextField`/`UITextView` và gắn **một** `inputAccessoryView` dùng chung cho ô vừa bắt đầu gõ — phủ mọi `TextField`, `TextEditor`, `.searchable`, ô trong hộp thoại, thanh URL, ô Mẫu rule mà không sửa từng màn. Trái → phải: nút **đóng bàn phím** · `aa · Aa¹ · Aa² · Aa · AA` · **Xoá · Sao chép · Dán** (icon `AppGlyph`). Thanh nằm trên thanh gợi ý chữ của iOS (không làm mất nó).
- **Luật nút** (`KeyboardTextToolbarModel`): định dạng, Sao chép, Xoá tác động **cả ô**; Dán **chèn tại con trỏ** (thay đoạn bôi đen; ô một dòng đổi xuống dòng thành dấu cách). Sửa chữ đi qua `UITextInput` như gõ phím (`insertText`/`deleteBackward`) nên binding SwiftUI, `.editingChanged` và hoàn tác hệ thống chạy như thường; chữ Telex/VNI đang gõ dở được `unmarkText()` trước. Ô trống ⇒ định dạng/Xoá/Sao chép mờ (đọc lại theo notification + timer 0,5 s vì đổi chữ bằng code không bắn notification).
- **Ngoại lệ**: không có thanh ở ô mật khẩu/API key (`isSecureTextEntry`) và trình sửa Script (`CodeEditorTextView`); ẩn `aa…AA` ở ô tìm kiếm/URL (`UISearchTextField`, bàn phím `.URL`/`.webSearch`, phím Return "Tìm") — 8 ô tìm kiếm tự dựng được gắn `.submitLabel(.search)` (`ReaderSearchView` vốn đã có). Ô trong trang web (`WKWebView`) không có thanh.
- **Định dạng chữ dùng chung** `TextCaseFormatter` (`Sources/Common/Utils/`): luật cũ của panel Dịch; ô nhiều dòng định dạng từng dòng. `ReaderSelectionCoordinator.formatMeaning` gọi sang.
- **Chạm ra ngoài ô nhập**: `KeyboardDismissPreference` (`keyboardDismissOnTapOutside`, mặc định tự tắt) — `KeyboardDismissGesture` không cài recognizer khi chọn "Không tắt bàn phím", đổi lúc bàn phím đang mở có hiệu lực ngay. Chỉnh bằng **giữ** nút đóng bàn phím (menu) hoặc Cài đặt → nhóm mới **"Chung"** → **"Bàn phím & ô nhập"** (`GeneralSettingsSection`, `KeyboardSettingsView`). Nhãn "Không tắt bàn phím" thay "Chỉ tắt bằng nút này" của mockup vì Return và kéo danh sách vẫn tắt bàn phím.
- **Gỡ bộ nút theo từng ô** (đã có thanh chung): Cấu hình tiện ích + plugin.json (`TextFieldClipboardButtons` xoá; giữ nút ↺ khôi phục mặc định thành `RestoreDefaultValueButton`), Thêm từ nhiều dòng, Bộ nhớ AI, Cài đặt AI (đồng bộ key/model vẫn qua `.onChange`), ô Mẫu/Bản dịch của rule, ô chữ thử VieNeu (giữ nút Phát), nút Dán của panel Dịch Reader.
- **Không đổi**: hàng `aa…AA` của panel Dịch, nút sao chép tin nhắn AI / log / debug / chẩn đoán, dữ liệu.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới**; grep không còn `TextFieldClipboardButtons|clipboardToolbar(|pasteFromClipboard|appendClipboard`. Không build tại chỗ (Windows) — CI xác nhận biên dịch; chưa thử trên máy.

## [1.3.547] - 2026-10-19

### fix: hàng nút và ô nhập ở màn cấu hình tiện ích khớp mockup

Người dùng (kèm ảnh chụp máy thật): *"phần cấu hình tiện ích mockup đẹp mà kết quả thật xấu quá"*, *"Trình duyệt · Bỏ ghim · Gỡ phần này còn chưa đẹp"* (chọn kiểu nút tròn), *"thêm bộ 3 nút clear, copy, paste những chỗ nhập text"*.

- **Vì sao**: `[1.3.546]` dựng hàng nút bằng `Label` trong một dòng `Form` — iOS dàn icon và chữ ra hai đầu ô, chữ bị co. Mockup vẽ với giá trị ngắn, còn biến cấu hình thật toàn URL dài: ô nhập đặt bên phải chỉ còn vài ký tự, dòng phụ "mặc định https://…" xuống 3–4 dòng.
- **`ExtensionConfigHeaderCard`**: hàng **Trình duyệt · Ghim · Gỡ** thành nút tròn 44pt (icon 18pt semibold) + nhãn `.caption` bên dưới, chia đều; đã ghim thì vòng cam nhạt, icon cam; Gỡ icon + nhãn đỏ.
- **`TextFieldClipboardButtons`** (mới, `Sources/Views/Common/`): bộ nút ô một dòng ↺ khôi phục mặc định (chỉ hiện khi khác mặc định) · xoá · sao chép · dán — cùng dáng `clipboardToolbar` (28×26, dán tô màu nhấn, icon `AppGlyph`), nhưng **dán thay cả giá trị** (đã bỏ khoảng trắng đầu/cuối).
- **Dòng "Cài đặt của tiện ích"** (`+GlobalConfig`): ô chữ = tiêu đề + khoá (chữ đều, một dòng), bộ nút bên phải, ô nhập nền mờ **rộng hết dòng** ở dưới, mặc định là chữ mờ trong ô; bỏ "mặc định …" khỏi dòng phụ. Ô số gọn bên phải (90pt), công tắc giữ chỗ.
- **Màn "Thông tin plugin.json"** (`ExtensionMetadataSection`): 4 ô chữ `name`, `source`, `regexp`, `description` có cùng bộ nút (không có ↺); vẫn tự lưu 0,4 s như gõ tay.
- **`ExtensionConfigView`**: `.listSectionSpacing(.compact)` bớt khoảng trống giữa các nhóm và phía trên thẻ đầu.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI xác nhận biên dịch; chưa thử trên máy.
