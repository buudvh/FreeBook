# CHANGELOG - Nhật ký Thay đổi CodeGraph FreeBook

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **FreeBook**.

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

## [1.3.546] - 2026-10-19

### feat: kiểu hiển thị danh sách truyện theo loại, làm lại màn cấu hình tiện ích

Người dùng: *"tôi muốn thay tuỳ chỉnh hiển thị layout của danh sách truyện (bao gồm tab kệ sách và tab khám phá)"* và *"mockup lại phần cài đặt cấu hình ext… bỏ nút mở trình duyệt ở phần chọn ext của khám phá và mang vào trong cấu hình ext"*. Plan: `Docs/Plans/2026-10-18-plan-kieu-hien-thi-danh-sach-va-cau-hinh-tien-ich.md` (mockup đã duyệt trong phiên phỏng vấn). Nhánh `feature/list-layout-ext-config` tách từ `main` sau khi `feature/comic-video` được fast-forward vào `main`.

- **Kiểu hiển thị** (`Sources/Views/Common/BookListLayout/`): ba kiểu `BookListLayoutMode` — Danh sách (mặc định, như cũ) / Lưới / Chỉ bìa; lưới 2–5 cột (mặc định 3). Lưu **theo loại nội dung** (`BookListLayoutScope`: Tất cả · Truyện chữ · Truyện tranh · Phim/Video), dùng chung giữa Kệ và Khám phá, trong `BookListLayoutPreferences` (`@MainActor @Observable`, khoá `bookListLayout.mode.<scope>` / `bookListLayout.columns.<scope>`; tự vào bản sao lưu vì khoá bắt đầu bằng chữ thường; nạp lại theo `UserDefaults.didChangeNotification` để khôi phục sao lưu có hiệu lực). Bìa video ngang 16:9, còn lại (kể cả "Tất cả") đứng 2:3.
- **Đổi kiểu**: sheet nhỏ `BookListLayoutSheet` ("Áp cho: <loại>", thanh chọn kiểu + Số cột) mở từ menu "…" của Kệ (tab Kệ/Lịch sử), nút tròn mới trên header Khám phá, thanh điều hướng màn Thể loại/Xem thêm, menu của Bộ sưu tập; và Cài đặt → Thư Viện → **Kiểu hiển thị danh sách** (`BookListLayoutSettingsView`, 4 nhóm + "Đặt lại mặc định").
- **Phía kệ**: `ShelfBooksLayoutView` dựng Kệ sách, Lịch sử, chi tiết Bộ sưu tập, Tìm trên kệ — nhánh danh sách giữ `List` cũ, nhánh lưới là `ScrollView` + `LazyVGrid` (không bao giờ lồng trong `List`), giữ nhóm Đang ghim/Truyện khác, nhóm theo ngày, phân trang 50/lượt, chạm/giữ bằng `onTapGesture` + `onLongPressGesture`. Thẻ `ShelfBookGridCardView`: ghim (trên-trái), chương mới (trên-phải), badge loại (dưới-phải), "icon nguồn · Ch. N" ("Tập N" với video). **Chip lọc loại** (`ShelfKindFilter` + `ExtensionKindFilterBar`, `@AppStorage("shelfKindFilter")`) ở đầu trang Kệ và Lịch sử, chỉ hiện khi có ≥ 2 loại; "Xóa tất cả lịch sử" chỉ xoá truyện đang hiện theo chip. Hai trang dời sang `ShelfView+Layout.swift` (`ShelfView` 873 → 684 dòng); header nhóm thành `ShelfSectionHeaderView`; luật dịch tên của danh sách đã lưu gom về `BookDisplayTranslation`.
- **Phía Khám phá**: `DiscoveryNovelsLayoutView` dùng chung cho tab danh mục (`DiscoveryCategoryTabView`, tách sang file riêng) và `CategoryNovelsListView`; cả hai nhánh giữ `.id(link)`, neo cuộn, kéo làm mới, sentinel tải thêm. Thẻ `DiscoveryNovelGridCardView` tải bìa bằng `RemoteCoverImage` (không ghi `covers/`). Skeleton dạng lưới `DiscoverySkeletonGridView`. Trang dạng section **không đổi**.
- **Bỏ nút safari** ở header Khám phá và ở từng dòng bảng chọn nguồn (`ExtensionSelectorView`, tách khỏi `DiscoveryView`; `DiscoveryView` 975 → 600 dòng). Trình duyệt của nguồn chỉ còn mở từ màn Cấu hình tiện ích.
- **Màn Cấu hình tiện ích**: thẻ đầu `ExtensionConfigHeaderCard` (icon, tên, tác giả · phiên bản, loại, ngôn ngữ, mô tả "Xem thêm") với hàng nút **Trình duyệt · Ghim · Gỡ**; các nhóm "Cài đặt của tiện ích", "Duyệt và lịch sử" (18+ thành bộ chọn Tự động/Có/Không), "Mạng", "Nâng cao" (màn con `ExtensionMetadataScreen` "Thông tin plugin.json", sửa Script). **Tự lưu tất cả**: bỏ "Lưu"/"Hủy", chỉ còn "Đóng"; công tắc ghi ngay, ô chữ ghi sau 0,4 s, đóng màn thì ghi nốt (`ExtensionMetadataSection` cũng đổi từ huỷ sang ghi nốt khi rời màn). "Import truyện" từ trình duyệt: mở từ Khám phá thì Chi tiết hiện ở Khám phá như cũ, nơi khác thì hiện ngay trong màn Cấu hình.
- **Sửa kèm**: giá trị bool đã lưu trong `configJson` bị đọc lại thành `"1"`/`"0"` (công tắc luôn hiện tắt, lần lưu sau ghi `true` thành `false`) — nhận diện bool thật qua `CFBoolean`.
- **Không đổi**: `@Model`/schema, Tìm kiếm toàn nguồn, Gợi ý, sheet chọn truyện ở Từ điển, tab Tải về, hộp xác nhận và luật chặn gỡ tiện ích đang là giọng TTS.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền (`JSDom.swift`, `TTSManager.swift`), **0 mới**; mọi file mới ≤ 400 dòng, 1 type chính/file. Không build tại chỗ (Windows, không có `swiftc`) — CI xác nhận biên dịch; chưa thử trên máy.

## [1.3.545] - 2026-10-19

### feat: mục lục video dùng tab theo section ở chi tiết và trình phát

Người dùng: *"mục lục ở chi tiết sửa mockup lại (để các tab vietsub, thuyết minh chọn được, đừng chia theo cụm tập"* và *"các phân mục lục khác của video cũng chia theo tab section"*. Mockup: `Docs/Mockups/2026-10-19-mockup-detail-toc.html`, `Docs/Mockups/2026-10-19-mockup-video-episode-list.html`.

- **Vì sao**: `[1.3.543]` cắt mục lục thành cụm 24 tập (`1–24`, `25–48`…) — mốc số vô nghĩa với người xem, còn tên nhóm (`section`) thì có nghĩa. Trình phát thì ngược lại: vẫn vẽ tiêu đề nhóm chen giữa lưới nên muốn xem nhóm khác phải cuộn qua hết nhóm trước.
- **`BookDetailVideoTOCGrid`**: bỏ hẳn `chunkSize` / `maxRowsPerGroup` / `RangeGroup` / `ordinal`; `SectionGroup` = đúng một section, hàng tab chia đều khi ≤ 3 nhóm và cuộn ngang khi nhiều hơn; badge cạnh tiêu đề đếm theo tab đang mở; `endLabel` theo tên nhóm.
- **Số tập**: đánh lại 1…N **trong từng tab** (giảm dần thì đánh ngược), chạm ô vẫn trả `index` thật. `BookDetailTOCView.videoRows` không còn tính `ordinal`, bỏ luôn tham số `totalCount`.
- **`VideoEpisodeGridView`** (dùng chung cho `VideoEpisodePanel` toàn màn và `VideoPlayerDetailsView` màn dọc): viết lại thành tab + lưới 4 cột ô 46pt, bỏ tiêu đề nhóm chen giữa lưới; `init` chọn sẵn tab chứa `currentEpisodeIndex` để `scrollTo` của màn cha vẫn tìm thấy ô; đổi tab **không** đổi tập đang phát.
- **Tìm kiếm**: ẩn hàng tab, lưới trải trên mọi nhóm (không kẹt trong tab đang mở).
- **Không đổi**: tầng dữ liệu (`session.episodes` / `currentEpisodeIndex` / `chapterSnapshots`), nhánh truyện chữ / truyện tranh, nút tải hàng loạt của `[1.3.544]`.
- **Kiểm chứng**: `swiftc -parse` sạch 6 file; `check_architecture.py` 2 violation nền, **0 mới**; `BookDetailVideoTOCGrid` 370 dòng, `+Groups` 79, `BookDetailTOCView` 378, `VideoEpisodeGridView` 197. Không build tại chỗ (Windows) — CI xác nhận biên dịch.

## [1.3.544] - 2026-10-19

### feat: thêm nút tải hàng loạt trong danh sách chương của reader

Người dùng: *"thêm cả nút download vào danh sách chương của reader"* → *"ở reader chữ, giống chức năng tải truyện khi nhấn giữ ở kệ và lịch sử"* → *"thêm nút tải hàng loạt cho cả reader comic"*. Mockup: `Docs/Mockups/2026-10-19-mockup-bulk-download.html`. Plan: `Docs/Plans/2026-10-19-plan-reader-toc-bulk-download.md`.

- **Hiện trạng**: reader chữ đã có nút tải **từng chương** (1.3.334, ẩn khi `!canDownloadChapters`); comic chỉ hiện dấu "đã tải", chưa có tải lẻ; cả hai chưa có tải cả bộ.
- **Reader chữ**: `bulkDownloadButton` (icon `arrow.down.to.line`) chèn **đầu** hàng nút ở header danh sách chương; `.sheet` ở gốc view mở `TaskOptionsSheet(book:taskType:.download)` — đúng sheet mà nhấn-giữ ở Kệ/Lịch sử vẫn mở, nên không nhân đôi logic tải. Ẩn cùng điều kiện `canDownloadChapters`.
- **Comic**: `ComicReaderView` giữ `Book` đã đọc trong `bootstrap()` vào `@State localBook` (trước đây đọc xong bỏ); `ComicChapterListSheet` nhận `book`, thêm nút ở `topBarLeading` ("Tải ảnh offline") + sheet lồng mở cùng `TaskOptionsSheet`.
- **Không làm**: không thêm tải lẻ cho comic; không đổi `TaskOptionsSheet` / `DownloadManager` / coordinator; không tạo hàng `Book` mới (nút ẩn khi sách chưa có trong thư viện).
- **Kiểm chứng**: `swiftc -parse` sạch 7 file; `check_architecture.py` 2 violation nền (`JSDom.swift`, `TTSManager.swift`), **0 mới**; `ReaderChapterListView` 337 dòng, `+Download` 94, `ComicChapterListSheet` 135, `ComicReaderView` 273. Không build tại chỗ (Windows) — CI xác nhận biên dịch.

## [1.3.543] - 2026-10-19

### feat: mục lục dạng lưới tập cho màn chi tiết video

Người dùng: *"sửa lại mục lục detail của video thành Đề xuất B"*. Mockup: `Docs/Mockups/2026-10-19-mockup-detail-toc.html`. Plan: `Docs/Plans/2026-10-19-plan-detail-video-toc-grid.md`.

- **Vì sao**: tab "Mục lục" của màn Chi tiết vẽ mỗi chương một hàng có `Divider`; phim 60–120 tập thì danh sách rất dài, hàng không có số tập, tiêu đề nhóm không gấp được, và tập đang xem chỉ khác hàng thường ở `.white` ≈ `.primary` trong dark mode (`BookDetailTOCView.swift:155`).
- **Mới — `BookDetailVideoTOCGrid`** (+ `BookDetailVideoTOCGrid+Groups.swift`): thanh công cụ dính (số tập + pill "Cũ nhất/Mới nhất" có nhãn + kính lúp bung ô tìm), chip chia khoảng dựng từ dòng `section` (nhóm > 60 tập tự cắt khúc 24), lưới 4 cột ô 46pt (đang xem = đảo màu, đã xem = mờ 36%, đã tải = chấm 4pt), chân "Hết …".
- **Số tập**: ô hiển thị `ordinal` 1…N đếm bỏ qua dòng section, chạm ô trả về `index` thật; sắp xếp giảm dần thì `ordinal` đánh từ N về 1 nên số trên ô vẫn là số tập thật.
- **`BookDetailTOCView`**: thêm `isVideo` (mặc định `false`), `body` rẽ nhánh bằng `Group`; `videoRows` giữ đúng thứ tự ưu tiên `chapterSnapshots` → `Book.chapters` → `onlineChapters`; tìm kiếm dùng chung `chapterSearchQuery`.
- **`BookDetailView`**: truyền `isVideo: contentKind == .video`.
- **Sửa kèm**: nút cuối danh sách dùng `"Tải thêm \(episodeNoun)"` thay vì hardcode "chương" (`BookDetailTOCView.swift:229`).
- **Không đổi**: nhánh truyện chữ / truyện tranh, `navigationTitle`, tầng dữ liệu (không ghi SwiftData).
- **Kiểm chứng**: `swiftc -parse` sạch 7 file; `check_architecture.py` 2 violation nền (`JSDom.swift`, `TTSManager.swift`), **0 mới**; `BookDetailVideoTOCGrid` 371 dòng, `+Groups` 98, `BookDetailTOCView` 396 (< 400). Không build tại chỗ (Windows) — CI xác nhận biên dịch.

## [1.3.542] - 2026-10-19

### fix: menu dịch ở khám phá mặc định đúng phạm vi nguồn, không hiện "Truyện này"

Người dùng: *"ở khám phá, dịch văn bản không có lựa chọn truyện này nhưng mặc định nó luôn hiển thị truyện này, bấm mở select nó mới đổi lại chọn nguồn này"*. Plan: `Docs/Plans/2026-10-19-plan-discovery-translation-scope-default.md`.

- **Nguyên nhân**: `ReaderTranslationScopeMenuView.selectedScope` khởi tạo cứng `.book` (`:27`), còn `preparePopupState()` chỉ sửa nó trong action của nút nên nội dung popover vẽ lần đầu vẫn đọc `.book`; `scopeDisplayText` đọc thẳng `selectedScope`. Khám phá truyền `bookId: ""` (`DiscoveryView.swift:167`) nên `Menu` không có mục "Truyện này" mà nhãn vẫn ghi "Truyện này", mở `Menu` lần nữa mới vẽ lại sang "Nguồn này". Kèm hệ quả: bấm "Lưu lại" ngay sẽ gọi `setBookOverride(bookId: "", …)` — ghi override rác với khoá rỗng.
- **Sửa**:
  - `availableScope(bookId:packageId:)` (hàm thuần) chọn cấp có thật: truyện → nguồn → toàn cục; dùng ở `init` để state bắt đầu đúng ngay từ lần vẽ đầu.
  - `effectiveScope` kẹp `selectedScope` về cấp có thật; `scopeDisplayText`, dấu checkmark trong `Menu` và `saveSettings` đều dùng nó ⇒ không hiện/ghi "Truyện này" khi `bookId` rỗng.
  - `refreshStatus()` kẹp lại khi `bookId`/`packageId` đổi (đổi nguồn ở Khám phá).
- **Giữ nguyên**: Reader và BookDetail (bookId khác rỗng) vẫn mặc định "Truyện này" như cũ.
- **Kiểm chứng**: `swiftc -parse` sạch; `check_architecture.py` 2 violation nền (`JSDom.swift`, `TTSManager.swift`), **0 mới**; file 307 dòng < 400. Không build tại chỗ (Windows) — CI chỉ xác nhận biên dịch.

## [1.3.541] - 2026-10-19

### fix: giữ mục lục ở chi tiết sau khi đọc ngay, đồng bộ lại khi đóng reader

Người dùng: *"xảy ra lỗi khi bấm đọc ngay rồi back về dễ xảy ra trường hợp mất mục lục ở chi tiết … trên 1000 chương mất rồi có, trên 4000 thì mất luôn"*. Log `app_logs (172).txt` chốt được nguyên nhân.

- **Bằng chứng log**: `[ChapterStore Save] mode=replaceFullTOC items=7243 stored=7243 … status=success` rồi `[ReaderBootstrap] totalChapters=7243 source=ChapterStore` ⇒ **DB không mất chương**. Sau `reader_disappear` không có dòng log nào (không `toc.js`, không lỗi) ⇒ màn Chi tiết không nạp lại.
- **Nguyên nhân**: Reader mở bằng `.fullScreenCover(item: $readerRoute)` không có `onDismiss:` nên `onAppear` của màn Chi tiết không chạy lại khi cover đóng. Sách mới đọc lần đầu chỉ có mục lục trong RAM (`onlineChapters`); `chapterSnapshots` và `chaptersList` rỗng. `startReading` tạo sách ⇒ `localBook` khác nil, mà `BookDetailTOCView` chọn nguồn vẽ `chapterSnapshots` → `localBook != nil` → `filteredLocalChapters`, tức `Book.chapters` — **luôn rỗng** vì `enableSwiftDataTOCWrite = false` ⇒ 0 dòng, trong khi tiêu đề vẫn ghi số chương của `onlineChapters`.
- **F1 — `BookDetailTOCView`**: nhánh `filteredLocalChapters` chỉ dùng khi danh sách **không rỗng**; còn lại rơi xuống `onlineChapters`. Không bao giờ bỏ danh sách đang giữ trong RAM.
- **F2 — `BookDetailView`**: thêm `onDismiss:` cho `fullScreenCover` của Reader → `syncChaptersList()`, `updateFilteredLocalChapters()`, `updateFilteredOnlineChapters()`. Chỉ đọc DB, không gọi mạng (mục lục vừa được `startReading` ghi đủ).
- **F3 — `loadTOCDataOnly`**: guard "Tải thêm chương đang chạy" chỉ bắn khi `onlineChapters` đã có dữ liệu (trước đây bắn cả khi rỗng ⇒ tắt `isLoadingTOC` mà không gán gì = màn trắng, không nút "Tải lại"); khi phải gán trang 1 của nguồn nhiều trang thì mở lại cờ `remainingPagesLoaded` để nút "Tải thêm chương" hiện lại.
- **Kiểm chứng**: `swiftc -parse` hai file sạch; `check_architecture.py` 2 violation nền (`JSDom.swift`, `TTSManager.swift`), **0 mới**; `BookDetailView.swift` 1128/1201 dòng baseline. Không build tại chỗ (Windows) — CI chỉ xác nhận biên dịch.
- Plan: `Docs/Plans/2026-10-19-plan-toc-loss-after-read.md`.

## [1.3.540] - 2026-10-19

### Revert "fix: mọi danh sách và tên truyện dịch theo cờ của truyện rồi tới nguồn"

Người dùng yêu cầu lùi nội dung commit `6bdc424` (entry `[1.3.538]`). Revert bằng `git revert --no-commit 6bdc424`, giữ nguyên `[1.3.539]` (commit sau, không liên quan).

- **Xoá file**: `Sources/Services/Translation/Utils/TranslationConfigSnapshot.swift`, `Sources/Views/Search/SearchView+Translation.swift`.
- **`TranslationConfigStore`**: bỏ hàm dùng chung `resolve(global:bookOverride:sourceOverride:packageId:isChineseSourceHint:)`, `resolveStatus` trở lại đọc `globalEnabled` + hai bảng override tại chỗ.
- **`TranslateUtils.translateBookTitleIfNeeded`**: bỏ tham số `packageId`, điều kiện trở lại cờ toàn cục `isTranslationEnabled`.
- **View**: `BookListItemView`, `CategoryNovelsListView`, `DiscoveryNovelRowView`, `DiscoveryView`, `ExploreBannerView`/`ExploreItemCard`/`ExploreListRow`/`ExploreRenderContext`/`ExploreSectionsView`, `SearchView`, `ComicReaderView`, `DownloadTrackerView`, `TaskOptionsSheet`, `BookActionSheet`/`BookActionRunner`, `NotificationInboxView`, `ReaderView`, `DictionaryListView+Transfer`, `ShelfView+BookImport`, `DownloadManager+TaskStore` trở lại đọc công tắc dịch **toàn cục** (`@AppStorage("isTranslationEnabled")`) thay vì cờ Truyện > Nguồn > Toàn cục. `TTSManager` trở lại `TranslateUtils.isTranslationEnabled`.
- **Xung đột đã xử lý**: `SearchView.swift` auto-merge sạch — thay đổi của `[1.3.539]` (`fetchFullTOC`) còn nguyên. Hai file `Docs/CodeGraph/CHANGELOG*.md` xung đột: giữ nguyên lịch sử (không đẩy entry cũ trở lại `CHANGELOG.md`, không thêm lại entry vào archive).
- **Kiểm chứng**: grep `Sources/` không còn tham chiếu `TranslationConfigSnapshot`, `translationRevision`, `currentTranslationConfig`; mọi call site `translateBookTitleIfNeeded` khớp chữ ký mới. **Không build tại chỗ** (Windows) — chỉ CI xác nhận biên dịch.

## [1.3.539] - 2026-10-18

### fix: chặn mục lục rỗng xoá chương, khớp chương theo url, sửa tải thêm chương

Làm theo báo cáo `Docs/Reports/2026-10-18-toc-update-investigation.md` (đề xuất P1–P4; người dùng duyệt plan trong chat). Báo cáo chỉ ra ba lỗi gây mất dữ liệu. Thứ nhất, script `toc` trả `[]` (trang chặn/captcha) thì `replaceFullTOC` xoá sạch mục lục cùng liên kết tới chương đã tải trong `.bin`. Thứ hai, khoá đối chiếu `(url, index)` làm mất cache của mọi chương phía sau chỉ vì nguồn thêm/xoá một chương. Thứ ba, "Tải thêm chương" bấm lại sau lỗi chạy lại từ trang 2 với chỉ số đã phình, ghi chương trùng vào DB.

- **P1 — chặn mục lục rỗng**:
  - `ChapterStoreDatabase.replaceFullTOC` từ chối mảng rỗng khi DB đang có chương: ghi log `❌`, ném `ChapterStoreError.invalidContent`, không xoá gì (giống `importBookMigration`). Đây là lưới an toàn cho mọi đường ghi.
  - Tầng tải: `BookDetailLoader.requireChapters` coi một trang mục lục rỗng là lỗi ("Nguồn trả về mục lục trống" / "Trang mục lục k/N không có chương nào"). Áp ở `fetchFirstPageTOC`, `fetchRemainingPages`, `fetchFullTOC` và vòng lặp trang của `startReading` / "Tải thêm chương". Gặp lỗi thì không ghi gì.
  - Riêng **trang cuối** của mục lục nhiều trang được phép rỗng, chỉ ghi log `⚠️`, vì `page.js` hay thừa một trang. Nếu không, cả truyện sẽ không làm mới, tải thêm hay dò chương mới được nữa. Đánh đổi: nếu bị chặn đúng ở trang cuối thì mất cache của các chương trang đó.
  - Đổi nguồn: mục lục mới rỗng thì báo lỗi **trước** khi tạo sách mới, sách cũ giữ nguyên.
- **P2 — `page()` trả `[]`**: thêm `BookDetailLoader.fetchFullTOC`. `page.js` rỗng thì dùng url chi tiết, trang đầu là `pages.first`, giống `fetchFirstPageTOC` và `NewChapterProbe`. Hàm này dùng ở kéo làm mới BookDetail, làm mới trong Reader (trước đây `page.js` trả `[]` ở hai chỗ này = 0 chương ⇒ xoá sạch) và đổi nguồn (trước gọi `toc(link chi tiết)` rồi mới `page`).
- **P3 — khớp theo url**:
  - `CompositeKey` tách ra file riêng, thêm `reconcile(url:index:)`: url rỗng mới khớp theo chỉ số. `candidateMap(for:)` gộp đoạn dựng bảng đối chiếu từng lặp ở `replaceFullTOC` và `upsertPage`; cùng url nhiều hàng (rác của bản cũ) thì hàng đã cache đứng trước.
  - Khớp url thì giữ `id`/`is_cached`/`offset`/`length`/tên dịch, chỉ cập nhật `chapter_index`.
  - Nhánh `.appendOnly` dùng bảng ứng viên rỗng để chương đuôi trùng url không kéo hàng cũ đi.
  - Mở BookDetail với nguồn nhiều trang chỉ ghi trang 1 khi DB **chưa** có mục lục. Lý do: riêng trang 1 không đủ để đối chiếu, khớp theo url sẽ kéo các chương đầu trang 2 lên và làm hở chỉ số. Đọc số chương lỗi thì coi như đã có (không ghi).
  - `BackupChapterRestorer.mergeIntoExisting` không thêm lại chương mà url đã có ở chỉ số khác trên máy. Nếu thêm, `upsertPage` giờ sẽ chuyển chỉ số hàng đó và để lại lỗ.
- **P4 — "Tải thêm chương"**:
  - `@State loadedRemainingPageCount` đếm số trang sau trang 1 đã nối vào `onlineChapters`. Bấm lại sau lỗi/huỷ thì tải tiếp từ trang lỗi.
  - Lượt tải tích luỹ cục bộ `base + fetched`, không nối vào `self.onlineChapters`. Nếu kéo làm mới vừa nạp đủ mục lục (`remainingPagesLoaded`) thì lượt tải tự dừng, tránh nhân đôi chương.
  - Sau khi ghi có `checkCancellation`, nên lượt đã bị huỷ không đè cờ/`loadingTask` của lượt mới hơn và không mở sheet tải.
  - Không ghi từng trang nữa: đủ trang mới ghi **một** `replaceFullTOC` mục lục đầy đủ (dọn hàng thừa/trùng), rồi làm mới danh sách và chạy lượt dịch tên chương nền.
  - `prepareForTask` (tải/xuất) bỏ qua trang đã tải và cũng ghi mục lục đầy đủ. `startReading` bỏ qua trang đã tải. Cả hai và `reloadBookData` huỷ lượt "Tải thêm chương" đang chạy. `loadTOCDataOnly` không ghi đè `onlineChapters` bằng trang 1 khi các trang sau đang/đã được nối.
  - `tocMetadata(from:)` bỏ tham số `startIndex` (không còn caller).
  - `reloadBookData` bật `remainingPagesLoaded` cùng lúc với danh sách đầy đủ, sau khi ghi. Nhờ vậy ghi lỗi thì cờ không bật trên danh sách thiếu.
- **Không làm**: P5–P8 của báo cáo (mục lục co bất thường, neo `currentChapterIndex` ở tầng chung, đổi nguồn khớp theo tên, khôi phục sao lưu khớp theo url).
- **Kiểm chứng**: một agent con rà phản biện: không thấy lỗi biên dịch; các lỗi logic nó tìm ra đã sửa ở trên. `check_architecture.py` **2 violation, 0 mới**. Không build tại chỗ (Windows); CI chỉ xác nhận biên dịch.

## [1.3.538] - 2026-10-18

### fix: mọi danh sách và tên truyện dịch theo cờ của truyện rồi tới nguồn

> **Đã bị revert ở `[1.3.540]`** — mục này chỉ còn giá trị lịch sử; code hiện tại quay về trạng thái của `[1.3.537]`.

Tiếp theo 1.3.537. Người dùng yêu cầu rà mọi chỗ còn lỗi tương tự và sửa luôn, nhớ tính cả cờ theo truyện. Dịch có 3 cấp, ưu tiên Truyện > Nguồn > Toàn cục (`TranslationConfigStore`), nhưng nhiều view vẫn đọc thẳng công tắc toàn cục `@AppStorage("isTranslationEnabled")`. Vì vậy tắt dịch cho một nguồn hay một truyện thì danh sách vẫn dịch.

- **Snapshot dùng chung**: thêm `TranslationConfigSnapshot`. Nó đọc cấu hình đè **một lần mỗi lượt vẽ**, rồi áp đúng thứ tự ưu tiên của store qua hàm `resolve` vừa tách khỏi `resolveStatus`. Nhờ vậy danh sách dài không phải tra `UserDefaults` cho từng dòng. Các màn mở lâu nghe `TranslationConfigStore.didChangeNotification` để vẽ lại ngay khi người dùng đổi cấu hình.
- **Theo truyện**:
  - `BookListItemView` (kệ, lịch sử, bộ sưu tập, sheet chia sẻ/nhập)
  - `ComicReaderView`, `DownloadTrackerView`, `TaskOptionsSheet`, `BookActionSheet`, `NotificationInboxView`
  - `ReaderView` (một chỗ), `TTSManager` (thay tại chỗ, **không thêm dòng**)
  - `TranslateUtils.translateBookTitleIfNeeded`: thêm `packageId: String? = nil`; đã cập nhật 8 nơi gọi. Trước đây hàm này nhận `bookId` mà vẫn kiểm cờ toàn cục.
- **Theo truyện, không có cờ riêng thì theo nguồn**, cho item chưa lưu thành sách:
  - các dòng `DiscoveryNovelRowView` và `CategoryNovelsListView`
  - thẻ, dòng, banner của trang explore
  - Tìm kiếm, cả hai chế độ (`SearchView+Translation`)
  - Mã truyện suy ra từ `BookIdUtils.make(packageId, link)`, cùng hai dạng id cũ.
- **Theo nguồn**: tiêu đề section, chip, thể loại, tiêu đề màn "Xem thêm".
- **Giữ toàn cục**: các màn Cài đặt dịch và công tắc nhanh ở Kệ, vì đây là nơi đặt giá trị toàn cục.
- **Lưu ý**:
  - Truyện bị gán UUID qua `resolveBookId` thì ở Khám phá/Tìm kiếm rơi về cờ của nguồn.
  - Tên truyện trên màn khoá theo cờ của phiên TTS đang phát, nên đổi cờ giữa chừng thì phải phát lại mới thấy.
- **Kiểm chứng**: `check_architecture.py` **2 violation, 0 mới**. Không build tại chỗ (Windows); CI chỉ xác nhận biên dịch.

## [1.3.537] - 2026-10-18

### fix: danh sách truyện ở Khám phá theo công tắc dịch của nguồn

Người dùng báo: tắt dịch cho một nguồn rồi mà danh sách truyện ở Khám phá vẫn dịch.

- **Nguyên nhân** (hồi quy từ 1.3.533): hai view tạo mới cho Khám phá đọc công tắc dịch **toàn app** (`@AppStorage("isTranslationEnabled")`), không đọc cờ **theo nguồn** của `TranslationConfigStore` mà `DiscoveryView` vẫn tính và truyền xuống. Hai view đó là:
  - `DiscoveryNovelRowView`: dòng truyện ở tab `home` và màn "Xem thêm".
  - `CategoryNovelsListView`.
- **Sửa**:
  - `DiscoveryNovelRowView` nhận `isTranslationEnabled` qua tham số. Ở `DiscoveryCategoryTabView`, view cha truyền đúng cờ theo nguồn nó đang có.
  - `CategoryNovelsListView` tự tính cờ theo nguồn bằng `TranslationConfigStore.isTranslationEnabled(bookId: "", packageId:, isChineseSourceHint:)`, giống `DiscoveryView`. Cờ này áp cho cả dòng truyện lẫn tiêu đề màn.
  - Trang `explore` (section) vốn đã nhận cờ theo nguồn từ view cha nên không cần đổi.
- **Không đổi**: `BookListItemView` (kệ, lịch sử…) vẫn dùng công tắc toàn app như trước bản này.
- **Kiểm chứng**: `check_architecture.py` **2 violation, 0 mới**. Không build tại chỗ (Windows); CI chỉ xác nhận biên dịch.

## [1.3.536] - 2026-10-18

### fix: phát kèm luồng tiếng audios của track, sửa Dailymotion mất tiếng

Log người dùng gửi (bản 1.3.535) ghi rõ: tiện ích «Dailymotion», nguồn "link tiện ích trả thẳng (native)", "track: 1 hình, 0 tiếng, không có nhóm audible". Giải mã script của tiện ích này cho thấy nó trả `data` là playlist con **chỉ có hình** của một chất lượng, còn luồng tiếng nằm ở `audios: [{data, url, headers, type, label, language}]` (thêm `audio` dạng chuỗi), đúng hợp đồng extension. App trước đây bỏ qua `audios`, nên phát không có tiếng; app gốc phát kèm luồng tiếng.

- **Model**: thêm `VideoAudioTrack` (`data`, `type`, `label`, `language`, `headers`) và `VideoTrack.audios`, mặc định rỗng.
- **Đọc từ track**: `VideoTrackMapper` đọc `audios` (nhận `url` thay cho `data`, bỏ phần tử rỗng và trùng). Khi `audios` rỗng thì đọc trường đơn `audio`.
- **Ghép hình + tiếng** (`VideoAudioRenditionComposer`), áp cho track `native` có `audios`:
  1. Tải nhanh `data` (chỉ khi đuôi là `.m3u8`/`.m3u` hoặc mime `mpegurl`; kèm header; tối đa 4,5 giây).
  2. Nếu `data` đã là playlist gốc (có `#EXT-X-STREAM-INF`): phát như cũ.
  3. Nếu là playlist con, hoặc tải lỗi: dựng playlist gốc tổng hợp, mỗi phần tử `audios` thành một dòng `#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud"` (phần tử đầu là `DEFAULT`), rồi `#EXT-X-STREAM-INF:BANDWIDTH=2000000,AUDIO="aud"` trỏ tới luồng hình. Playlist này phát qua nhánh `.hlsText` / `HLSPlaylistResourceLoader`.
  4. `data` ở dạng text hoặc `data:` cũng ghép được: playlist con được phục vụ kèm.
- **Nhánh `.hlsText`**: giờ gửi User-Agent qua `AVURLAssetHTTPUserAgentKey`.
- **Playlist ghép lỗi**: tự quay về luồng gốc như trước.
- **Kiểm tra mất tiếng**: playlist ghép có nhóm `.audible` nên không còn báo `❌` sai.
- **Rủi ro**:
  - Playlist ghép không khai `CODECS`.
  - Cả asset dùng chung một bộ header: header của track thắng, header riêng của `audios` chỉ bù khoá còn thiếu.
  - Track có `audios` nạp chậm thêm tối đa khoảng 4,5 giây.
  - AirPlay không phát được `fbhls://`, giống nhánh HLS text có từ trước.
- **Kiểm chứng**: `check_architecture.py` **2 violation, 0 mới**. Không build tại chỗ (Windows); CI chỉ xác nhận biên dịch. Cần thử Dailymotion trên máy.

## [1.3.535] - 2026-10-17

### fix: video dò từ trang mất tiếng thì tự thử link khác hoặc nhúng trang, ghi log chẩn đoán

Người dùng báo nguồn Dailymotion (tiện ích HHHTQ, track `auto`) có hình mà mất tiếng; app gốc thì có tiếng. Log người dùng gửi không có dòng chẩn đoán vì công tắc log đang tắt, và từ máy dev không tải được manifest (403, token gắn theo thiết bị). Vì vậy bản này vừa ghi lại bằng chứng, vừa tự khắc phục.

- **Phát hiện mất tiếng**: sau khi item đang phát khoảng 2,5 giây, đếm `AVPlayerItem.tracks` và bỏ các track tiếng đang tắt; nhóm `.audible` chỉ ghi vào log. Mỗi lượt nạp chỉ kiểm một lần; đang tạm dừng thì hoãn tới lần phát sau.
- **Log luôn ghi (`❌`)**:
  - `Không có âm thanh: …` kèm tiện ích, tập, server, nguồn link (link trực tiếp / HLS text / dò từ trang), loại playlist đã chọn (master/media, có `AUDIO` hay không, số ứng viên), số track hình/tiếng.
  - Dòng lỗi `AVPlayerItem` có thêm nguồn link, URL đã che token (scheme + host + tên file), mã lỗi và lỗi mạng gần nhất trong error log của item.
- **Tự khắc phục**, chỉ áp với link do `VideoMediaSniffer` dò từ trang (track `auto`/`webview`):
  - Thứ tự thử: link chính → tối đa 3 m3u8 khác (master có `AUDIO` trước) → nhúng trang.
  - Phương án dự phòng phải có cả hình lẫn tiếng; lỗi thì sang phương án kế. Chuyển phương án thì giữ giây đang xem.
  - Chỉ tự đổi khi màn trình phát đang hiện, app ở trước và không ở PiP.
  - Có thông báo ngắn trên khung phim.
  - Đây là ngoại lệ có chủ đích: DOC không cho `auto` rơi về nhúng trang, chỉ cho phép ở ca mất tiếng.
- **Không còn đưa mp4** vào danh sách dự phòng khi đã có m3u8, vì mp4 thường là quảng cáo. Có nhiều master thì ưu tiên master có `AUDIO` làm link chính.
- **Link tiện ích trả thẳng** (`native`/HLS text): không tự đổi, chỉ ghi log.
- **File mới**: `VideoPlaybackSession+AudioFallback.swift`, `VideoSourceResolution.swift`. Sửa `VideoMediaSniffer`, `VideoHLSPlaylistProbe`, `VideoSourceResolver`, `VideoPlaybackSession` (+`Playback`/`Loading`/`Lifecycle`) và `VideoPlayerStage`.
- **Rủi ro**: HLS tách tiếng có thể không hiện trong `item.tracks`. Khi đó link dò từ trang chuyển sang nhúng dù không cần, còn link tiện ích trả thẳng sẽ ghi một dòng `❌` sai.
- **Kiểm chứng**: `check_architecture.py` **2 violation, 0 mới**. Không build tại chỗ (Windows); CI chỉ xác nhận biên dịch. Thử Dailymotion trên máy: nếu vẫn mất tiếng thì gửi log, giờ sẽ có dòng `Không có âm thanh` dù công tắc log tắt.

## [1.3.534] - 2026-10-17

### feat: nút đánh dấu và bỏ đánh dấu 18+ cho tiện ích

Yêu cầu: *"thêm nút đánh dấu/bỏ đánh dấu ext nsfw"*.

- **Lưu lựa chọn**
  - `Extension.nsfwOverride: Bool?`: `true` = đánh dấu, `false` = bỏ đánh dấu, `nil` = nhận diện tự động. Decode khoan dung.
  - Trường này **tách khỏi** `isNsfw`: cập nhật tiện ích đọc lại `isNsfw` từ `plugin.json`, nhưng không làm mất lựa chọn của người dùng.
- **Nhận diện**: `ExtensionNsfwClassifier` ưu tiên `nsfwOverride` trên cả cờ tự khai lẫn heuristic. `ExtensionNsfwCache` so sánh cả bản ghi nên tự tính lại khi lựa chọn đổi.
- **Ghi**: `ExtensionTransactionCoordinator.setNsfwOverride` (theo mẫu `setSavesHistory`), lưu ngay khi bấm.
- **Giao diện**
  - Màn Cấu hình tiện ích có section "Nội dung nhạy cảm" (`ExtensionConfigView+Nsfw`): nút "Đánh dấu 18+" / "Bỏ đánh dấu 18+"; đã tự chọn thì hiện thêm "Dùng nhận diện tự động". Chú thích ghi rõ trạng thái hiện tại.
  - Nhấn giữ dòng tiện ích đã cài trong Kho có cùng các lựa chọn (`RepositoryManagerView+Nsfw`).
- **Tác dụng kéo theo**: nhãn 18+ trên icon, ẩn khi công tắc NSFW tắt, và mặc định không lưu lịch sử nếu người dùng chưa tự chọn.
- **Sao lưu**
  - `BackupPayload` mang thêm `nsfwOverride`, tính vào fingerprint.
  - Khi khôi phục, chỉ áp lựa chọn cho tiện ích mà máy đang khôi phục chưa tự chọn, cùng luật với `savesHistory`.
- **Kiểm chứng**: `check_architecture.py` **2 violation, 0 mới**. Không build tại chỗ (Windows); CI chỉ xác nhận biên dịch.

## [1.3.533] - 2026-10-17

### feat: khám phá dạng section, trình phát kiểu Aloha có PiP và phát nền, hub luôn hiện, công tắc NSFW toàn app

Mốc giao diện của plan đợt 2 (`Docs/Plans/2026-10-17-plan-round2-fixes-player-hub.md`), nằm trên nhánh `feature/comic-video`. T3, T4 và T5 chạy song song trên worktree riêng; T6 và các yêu cầu bổ sung làm ở session chính; hai agent review phản biện chéo rồi sửa trước khi chốt. Từ mốc này commit viết tiếng Việt có dấu.

- **Khám phá dạng section (T3)**
  - `ExtensionManager+Explore` parse `explore` thành `ExploreSection` / `ExploreItem` / `ExploreAction`.
    - Section: `banner`, `horizontal_list`, `grid`, `list`, `ranking`, `chip`; giá trị lạ thì bỏ qua.
    - Hình thẻ: `book`, `square`, `circle`, `movie`, `short`.
  - Nguồn có `explore` thì trang chính dựng section **thay** tab `home`, đúng DOC; `genre` giữ nguyên. Section hiện ngay, `home` và `genre` nạp song song.
  - "Xem thêm" (`more` kiểu `list`) mở danh sách phân trang. Item không có action thì mở chi tiết theo `link`.
  - Banner giữ item không có tên nếu có ảnh và có `link` hoặc `action`.
  - Bìa dùng `RemoteCoverImage`. Referer dự phòng là `source` của tiện ích, tính một lần khi view xuất hiện.
  - Nhãn `tag` dùng chung `CoverTagBadge` (bỏ `DiscoveryCoverTag`).
  - `hasScript` đọc `script` dạng `[String: Any]`.
- **Trình phát tự dựng (T4)**
  - Kiến trúc:
    - `VideoPlaybackSession` giữ `AVPlayer` sống lâu hơn màn hình; màn hình chỉ gắn vào, đếm theo từng lần gắn.
    - `VideoPlayerSurfaceView` (`AVPlayerLayer`) thay `AVPlayerViewController`.
  - Điều khiển chỉ dùng biểu tượng, theo mockup đã duyệt:
    - tốc độ, Vừa / Lấp đầy, khoá xoay `lock.rotation`, phụ đề, PiP, server
    - nút Xoay (`requestGeometryUpdate`), khoá cảm ứng, tập kế, danh sách tập nhóm theo section, nút "Bỏ qua"
  - Cử chỉ: chạm đúp ±10 giây cộng dồn; vuốt dọc chỉnh độ sáng / âm lượng; vuốt ngang để tua; nhấn giữ phát 2×. Độ sáng được trả lại khi rời trình phát.
  - Thu nhỏ để phát nền qua `VideoMiniPlayerState`. Mở lại bằng `VideoPlayerPresenter` dạng `.overFullScreen`, nên màn đọc bên dưới không bị tháo.
  - PiP tự bật khi rời app. Không bật được PiP thì tách hình và chỉ phát tiếng, có background task.
  - Màn khoá và Now Playing:
    - `VideoNowPlayingCoordinator` giữ phiên màn khoá chỉ khi có item đang phát.
    - TTS bỏ qua lệnh màn khoá khi video giữ phiên (`TTSManager+NowPlaying`, `TTSNowPlayingController`), không sửa `TTSManager.swift`.
  - Ưu tiên TTS:
    - Video đã nhường TTS thì không tự phát khi tải xong.
    - TTS bắt đầu đọc thì media của trang nhúng tạm dừng.
  - Giữ màn sáng qua `ScreenIdleTimerLock` dùng chung với màn đọc truyện tranh; chỉ giữ khi màn trình phát đang hiện.
  - **Dailymotion mất tiếng (giả thuyết, chưa kiểm trên máy)**:
    - Trình bắt link gom thêm m3u8 trong 1,5 giây.
    - `VideoHLSPlaylistProbe` tải tối đa 6 ứng viên và ưu tiên playlist gốc (`#EXT-X-STREAM-INF`).
    - Log loại playlist đã chọn (chỉ host và tên file). Cái giá: mỗi lần mở HLS chậm thêm khoảng 1,5 giây.
- **Hub và widget (T5 + bổ sung)**
  - Hub luôn hiện, bấm là bung đủ 3 dòng cố định: Trợ lý AI, Thông báo, Video. Dòng nào không dùng được thì xám; dòng có định danh cố định, trạng thái đổi không làm vẽ lại.
  - Ẩn khi `FloatingWidgetSuppression` bật (đang xem phim toàn màn).
  - Thông báo **luôn** bấm được. Có tin chưa đọc thì hiện chấm đỏ trên icon chuông; số lượng ghi ở dòng phụ.
  - Icon AI đổi sang màu trắng.
  - Badge số của nút hub chỉ đếm mục đang có việc (`FloatingHubItem.isActive`).
  - Hub nép vào mép thì nút mờ còn 0,5.
  - Widget trình duyệt tách lại thành cửa sổ riêng (`alert-3`): nút mờ 0,7 khi nghỉ, đậm 1,0 khi chạm hoặc kéo; dùng lại khoá vị trí cũ.
  - Widget TTS cũng ẩn theo `FloatingWidgetSuppression`.
- **Công tắc NSFW toàn app (T6)**
  - Khoá chung `extFilterIncludeNsfw` dùng ở Cài đặt › Thư Viện › "Nội dung nhạy cảm (NSFW)" (màn riêng `NsfwSettingsView`, có công tắc và giải thích) và ở bộ lọc Kho.
  - Mặc định tắt và **tự tắt lại mỗi lần mở app** (`resetNsfwVisibilityOnLaunch`).
  - Khi tắt:
    - Khám phá ẩn nguồn NSFW và tự chuyển sang nguồn khác, kể cả khi mở lại app. Nếu mọi nguồn đều bị ẩn thì báo trạng thái rỗng.
    - Tab Lịch sử và phần tìm trong lịch sử ẩn sách của nguồn NSFW. Sách trên Kệ không bị ẩn.
  - Nhãn **18+** (chữ trắng, nền đỏ) ở góc icon của mọi tiện ích NSFW (`ExtensionNsfwBadge` trong `ExtensionIconView` và dòng Kho).
- **Xoá lịch sử theo khoảng**: "Xoá tất cả lịch sử" mở hộp chọn 1 giờ / 1 ngày / 30 ngày / Tất cả. Chỉ xoá sách đang hiển thị (lịch sử NSFW đang ẩn được giữ), qua `BookStorageManager.deleteBooksAsync`.
- **Khám phá ổn định hơn**: lượt tải mới huỷ lượt cũ, kết quả chỉ được ghi khi nguồn vẫn đang được chọn, và không tải hai lần khi tự chuyển nguồn.
- **Kiểm chứng**: `check_architecture.py` **2 violation, 0 mới**. Không build tại chỗ (Windows); CI chỉ xác nhận biên dịch. PiP, phát nền, màn khoá, cử chỉ, xoay và cửa sổ nổi chỉ kiểm được trên máy.

## [1.3.532] - 2026-10-17

### fix: sua host/url va bia gui referer, parse an toan, nhom tap theo server, loc nsfw, cong tac luu lich su

Mốc sửa lỗi của plan đợt 2 (`Docs/Plans/2026-10-17-plan-round2-fixes-player-hub.md`), cùng nhánh `feature/comic-video`. Chia làm 3 phần: nền tảng N chạy trước, sau đó T1 (NSFW + lịch sử) và T2 (bìa, nhãn, nhóm tập) chạy song song. Từ bản này có luật mới: không đưa tên ứng dụng gốc vào comment, chuỗi, tài liệu hay commit; các dòng nhánh đã thêm trước đó đã được dọn.

- **Parse an toàn**
  - Mọi đường parse của `ExtensionManager` (`search`, `custom`, `detail`, `toc`, `page`, `genre`, `home`) đọc qua `JSValueReader` (`ExtensionManager+ItemParsing`). `undefined`/`null` không còn hiện thành chữ.
  - Ca thật: kkphim, tab Mới cập nhật — ext trả `description: item.description` trong khi API không có trường này.
  - `ExtensionItemResult` thêm `tag`, `type`; tách `ExtensionItemResult` và `ChapterResult` ra file riêng.
- **URL và host**
  - `ExtensionURLFormatter` đổi `//x` thành `https://x`.
  - Thêm `resolveAssetURL` cho bìa: URL tuyệt đối giữ nguyên (không còn bước "lấy `https://` cuối cùng" làm hỏng bìa proxy `?url=`).
  - Item thiếu `host` thì dùng `source` của tiện ích; `host: ""` thì giữ nguyên, đúng DOC.
  - `ExtensionHostResolver.chapterHost`: chương → sách → `source`. Áp ở điểm chung `ChapterContentRepository.fetchFromExtension` (Reader, TTS), danh sách chương tải, xuất, comic đọc/tải và video.
  - Host đã lưu không còn bị ghi đè thành rỗng (`updateBookMetadata`, BookDetail). Đổi nguồn lấy host theo thứ tự: detail → item → `source`.
  - `link`/`url` không bị resolve lúc parse, vì chúng là khoá nhận diện.
- **Track video**
  - `VideoSourceResolver` giải escape JSON (`\t \n \/ \uXXXX`…) và cắt khoảng trắng trước khi hiểu `data` là URL.
  - Ca thật: HHHTQ trả `"\thttps://play.abyssplayer.com/…"`, trước đây báo "cần URL http(s) tuyệt đối".
- **Bìa gửi `Referer`**
  - Ca thật: CDN bìa của truyenqq trả 403 khi thiếu `Referer`.
  - `CoverImageLoader` (actor, cache bộ nhớ và `Caches/cover_images/`, downsample) cùng `RemoteCoverImage` thay `AsyncImage` ở Tìm kiếm, Gợi ý, `BookCoverView` và danh sách Khám phá.
  - `Referer` lấy theo host item, rồi `source`.
  - `ImageCacheManager.downloadAndSaveCover` nhận `referer`.
  - Bìa và icon cũ dạng tương đối được ghép `source` lúc hiển thị, không backfill.
  - Thêm nhãn `tag` trên bìa.
- **Nhóm tập theo server**
  - ChapterStore thêm cột `is_section` (`user_version` 2). `toc` của comic/video giữ dòng `type:"section"` làm tiêu đề nhóm; truyện chữ không đổi.
  - Mục lục BookDetail và danh sách chương comic hiện tiêu đề nhóm.
  - Comic, video và lượt tải comic bỏ qua dòng section; lượt tải lọc section **trước** khi áp giới hạn số chương.
- **NSFW**
  - `Extension.isNsfw`, đọc từ `metadata.nsfw`/`tag`/`tags` lúc cài.
  - Registry decode khoan dung: một mục hỏng không làm trắng cả kho.
  - `ExtensionNsfwClassifier`: cờ tường minh, hoặc từ khoá/tên miền theo trang danh mục cộng đồng; bỏ hai từ đơn `dam`, `cu`; cụm nhiều chữ so theo ranh giới từ.
  - Bộ lọc kho có công tắc "Nội dung nhạy cảm (NSFW)", mặc định tắt. Công tắc tắt thì ẩn tiện ích NSFW trong Kho và khi tìm mọi nguồn. Khám phá vẫn hiện tiện ích NSFW đã cài.
- **Lưu lịch sử theo tiện ích**
  - `Extension.savesHistory` + `ExtensionHistoryPolicy` (mặc định bật, NSFW mặc định tắt). Công tắc nằm ở màn cấu hình (`ExtensionConfigView+History`) và lưu ngay qua `ExtensionTransactionCoordinator.setSavesHistory`, không qua `configJson`.
  - `isHistory` chỉ được bật khi chính sách cho phép, ở các chỗ: `ReadingProgressStore.persist`, `ChapterPersistenceStore.ensureBook` và upsert, `removeFromShelf`. Tiến độ đọc vẫn được lưu.
  - Lịch sử cũ được giữ.
  - `HistoryOrphanBookSweeper` chạy lúc mở app, dọn sách mồ côi (không trên kệ, không lịch sử, tiện ích tắt lịch sử), trừ sách đang TTS hoặc đang tải.
  - Backup mang thêm `isNsfw`/`savesHistory`.
- **Rủi ro đã biết**
  - Lần làm mới mục lục đầu tiên ghi lại host của mọi chương (`""` thành `source`).
  - Vị trí đọc dở của comic/video mở trước bản này có thể lệch vì mục lục có thêm dòng section.
  - "Xoá khỏi kệ" với tiện ích đã tắt lưu lịch sử thì sách bị dọn hẳn ở lần mở app sau.
- **Kiểm chứng**: `check_architecture.py` báo **2 violation, 0 mới**. Không build tại chỗ (Windows); CI chỉ xác nhận biên dịch. Thử trên máy theo mục 6 của plan.
