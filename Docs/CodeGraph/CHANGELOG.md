# CHANGELOG - Nhật ký Thay đổi CodeGraph FreeBook

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **FreeBook**.

## [1.3.693] - 2026-11-04

### fix: rule JS của nguồn Legado chạy trong scope riêng, hết lỗi khai báo trùng

Người dùng: *"TÔi chắc chắn đang thiếu rất nhiều vì rất nhiều source chạy bị lỗi phần java"*, rồi *"làm plan: 1. Lỗi scope JS (top-level `let`/`const` chạy lần hai bị báo khai báo trùng): vẫn đứng đầu, 149 nguồn"*; duyệt plan (*"Duyệt, làm đi"*).

- **Nguyên nhân:** mọi rule JS của một phiên chạy chung global của `JSContext`. Vì vậy `let`/`const`/`class` ở cấp ngoài cùng sống sang lần sau, và chạy lần hai báo `SyntaxError: Can't create duplicate variable`. Quét 3.339 nguồn thật: 149 nguồn dính, 51 nguồn hỏng ngay từ mục thứ 2 của danh sách.
- **`LegadoJSRuntime.evaluateRaw`** chạy rule bằng **eval gián tiếp ở global**:
  - Hàm `eval` gốc được giữ ở thuộc tính ẩn `__lgEval`, cài ngay sau khi tạo context, trước bootstrap và `jsLib`. Nguồn có gán lại `eval` cũng không ảnh hưởng.
  - Mỗi lần chạy, `let`/`const`/`class` có môi trường lexical riêng.
  - `var`/`function` vẫn lên global, và mọi `function` có ngay trước câu lệnh đầu tiên. Vì vậy luồng `loginUrl` → nút form đăng nhập và nút khám phá vẫn gọi được hàm, kể cả khi đoạn đầu script ném lỗi.
  - Giá trị trả vẫn là câu lệnh cuối; luật "`result` bị gán lại" giữ nguyên.
- **Hết che biến môi trường:** nguồn tự khai `let page`/`key`/`result`/`baseUrl` không còn che giá trị app đặt cho các lần sau. Ví dụ: 晋江, 光遇聚合 (`page`/`key`); 51漫画, 塔读 (`result`); 乐乎文章 (`baseUrl`).
- **`return` ở cấp ngoài cùng:**
  - Chạy code gốc trong `(function(result, baseUrl, src, key, page, title, nextChapterUrl){{…}}).call(this, …)`. Đối số đọc bằng `typeof`, nên `var src = src.trim(); return src` hết ra `undefined`.
  - Khối bên trong cho phép `let` trùng tên tham số.
  - Điều kiện bắt lỗi nới thành `"Return statements"`.
- **Khác đã biết, ghi vào spec, corpus 0 đoạn:**
  - Code mở đầu bằng `"use strict"` thì `var`/`function` chỉ sống trong lần đó.
  - Ở đường `return`, gán `result` mà không `return` thì mất.
- **Không đổi:** `jsLib`, `runQuietly` và mọi nơi gọi `evaluateRaw`.
- **Spec:** viết lại `Docs/Specs/legado-source-spec.md` §6.1 và sửa dòng cũ ở §3.3.
- **Quy trình:** session chính đã đọc code Legado (GPL), nên phần code do agent riêng viết theo plan và spec (clean-room). Bản đầu bọc khối `{…}` bị review bắt lỗi: `function` chỉ lên global khi chạy tới câu khai báo, làm hỏng nút đăng nhập ở 7 nguồn. Đã đổi sang eval gián tiếp.
- **Kiểm chứng:**
  - Chuỗi mẫu dựng lại từ chính literal Swift, chạy trên Node `vm` một context dùng chung, đạt đủ bảng ca thử:
    - `let`/`class` chạy hai lần;
    - `var src = src`;
    - hàm khai sau câu lệnh ném lỗi;
    - hàm `jsLib` gọi hàm rule khai muộn;
    - `with(JavaImporter)`;
    - completion value;
    - đường `return` kiểu 可乐小说.
  - `check_architecture.py` chỉ còn 1 lỗi nền (`JSDom.swift`), **0 mới**.
  - Không build tại chỗ (Windows), chưa thử trên JSC hay trên máy. Nên thử: 少年梦阅读 (lặp `let`), 点众阅读 hoặc 刺猬猫#2 (nút đăng nhập), 可乐小说 (`return`).

## [1.3.692] - 2026-11-04

### feat: token ngoặc <[> <]> với bộ ngoặc chỉnh được, neo <START> <END> và hướng dẫn viết rule

Người dùng: *"thêm token đóng mở ngoặc cho rule dịch, có thể config các loại ngoặc cho token"*, *"ngoặc tròn ngoặc vuông ngoặc nhọn đủ nhé"*, *"nhớ bổ sung hướng dẫn đầy đủ để tạo rule… mỗi ý trong phần hướng dẫn 1 dòng"*. Đã chốt bằng bảng chọn:
- Token viết `<[>` / `<]>` (dấu ngoặc vuông, không lẫn với nhóm `( )`); neo dòng đổi tên thành chữ in hoa `<START>` / `<END>`.
- Mở và đóng phải cùng cặp và cân bằng; ngoặc **không** sinh `{i}`.
- Bộ ngoặc có bản chung và bản riêng từng truyện.

- **Token ngoặc** (`QuickTranslationRuleParser+Bracket`, `QuickTranslationRuleMatcher+Bracket`):
  - `<[>` khớp đúng một ký tự mở, `<]>` khớp đúng một ký tự đóng trong bộ ngoặc đang bật; rộng 1, nhận `?`, không nhận `|` hay độ dài.
  - Parser ghép mỗi `<]>` với `<[>` gần nhất còn mở theo thứ tự nguồn (mỗi nhánh của nhóm bắt đầu từ cùng ngăn xếp). Khi khớp, `<]>` phải đúng ngoặc đóng của ký tự `<[>` đã bắt và đoạn giữa phải cân bằng: `<[><any><]>` trên `(a)Y(b)` ra `(a)` rồi `(b)`. `<]>` không có cặp, hoặc cặp nằm ở nhánh không khớp, thì nhận mọi ngoặc đóng.
  - Ký tự mở giữ ở **ô ẩn** sau các ô `{i}` (`slotCount` ở `QuickTranslationParsedRule` / `QuickTranslationCompiledRule`); `Match.captures` chỉ trả phần `{i}`.
  - Tính như chữ cố định khi xét `ANY_WITHOUT_LITERAL` / `NO_LITERAL_ANCHOR` và khi xếp ưu tiên, nên `<[><any><]><END> =` hợp lệ. `<any>` đứng ngay trước token ngoặc chỉ thử các độ dài mà ký tự kế tiếp là ngoặc hợp lệ.
- **Neo dòng đổi tên** `<^>` → `<START>`, `<$>` → `<END>` (`Kind.lineStart/.lineEnd` rawValue mới). Rule cũ vẫn chạy nhờ `Kind.kind(forTokenName:)`. Khoá công tắc chung giữ nguyên; khoá cũ `^`/`$` trong cấu hình riêng truyện được đọc thành tên mới.
- **Bộ ngoặc** (`QuickTranslationRuleBracketPair`, `QuickTranslationRuleBracketDefaults`, `QuickTranslationRuleBracketSet`, `QuickTranslationRuleBracketStore`):
  - Mặc định 50 cặp: tròn 11, mai rùa 6, vuông 11, ngoặc móc 6, ngoặc góc 16. `<>` ASCII có sẵn nhưng tắt. Không có `「」『』` (lời thoại), `⦍⦎⦏⦐` (ghép chéo), `〈〉` U+2329/232A.
  - Bộ chung ở `UserDefaults` `quickTranslateRuleBracketPairs` (vắng = mặc định, Backup tự gói). Bộ riêng truyện ở trường `brackets` của `QuickTranslateEngineConfig.json`.
  - `TranslationReadContext` chụp bộ ngoặc của truyện; engine và màn chẩn đoán dùng bản chụp đó.
  - Khi lưu, kiểm mỗi ô đúng một ký tự (một đơn vị UTF-16), mở khác đóng, không trùng ký tự với cặp khác.
- **Backup:**
  - `QuickTranslateEngineConfig.json` riêng truyện (thứ tự ưu tiên, công tắc token riêng, bộ ngoặc riêng) giờ được sao lưu và khôi phục nguyên văn. Trước đây file này không có trong Backup.
  - Khôi phục cài đặt xong thì dọn cache dịch để bộ ngoặc chung có hiệu lực ngay.
- **Giao diện:**
  - Cấu hình token rule có công tắc `<[>` `<]>` và hàng "Bộ ngoặc".
  - Màn **Bộ ngoặc** (`QuickTranslationRuleBracketListView`), kiểu danh sách 1.3.636 với [Sửa][Tắt/Bật][Xoá] và nút `+` nổi.
    - Bộ chung: ngăn kéo `…` có "Khôi phục mặc định".
    - Bộ riêng truyện (mở từ Cài đặt đọc › token riêng): khi chưa có bộ riêng chỉ xem kèm nút "Chỉnh riêng cho truyện này"; khi đã có thì ngăn kéo có "Dùng bộ chung".
  - Sheet thêm/sửa cặp (`QuickTranslationRuleBracketEditorSheet`) báo lỗi ngay dưới ô.
- **Hướng dẫn viết rule** — một nguồn `QuickTranslationRuleGuide`:
  - Trang `QuickTranslationRuleGuideView` có 11 mục, mỗi ý một dòng kèm ví dụ. Mở từ hàng đầu "Công cụ" của Rule dịch nhanh và từ hàng "Hướng dẫn đầy đủ" ở màn sửa rule.
  - Các nút "?" ở Mẫu, Bản dịch, Cấu hình token và Bộ ngoặc chỉ còn vài dòng lấy từ cùng nguồn. Bỏ câu sai cũ "Mọi token phải được dùng".
- Gợi ý bàn phím nhận `<[` / `<]`; chip ngoặc và neo không được đánh số.
- `CLAUDE.md` / `AGENTS.md`: cập nhật đoạn token ở mục Dịch thuật VietPhrase.
- Chuyển entry cũ nhất sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng:** đọc code + diff; `check_architecture.py` chỉ còn 1 lỗi nền (`JSDom.swift`), **0 mới**. Dò tay trên code các mẫu `<[><any><]>` trên `(a)Y(b)` và `【a)`, `<]>` đứng một mình, `<[><any><]><END>`, `(<[>a|b)<]>`, rule cũ `<^>第<n>章`. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.691] - 2026-11-04

### fix: chuyển nguồn khi link chương khác dạng, thêm mục chuyển nguồn ở sheet nhấn giữ

Người dùng: *"báo lỗi mục lục nguồn mới khác dạng … nguồn cũ là qimao đường đen, nguồn mới là qimao của tôi"*, *"log không thấy gì, bạn không thêm log lỗi à?"*, rồi *"làm y như bạn nói đi. thêm option chuyển nguồn trong contextmenu với book mất ext"*.

- **Nguyên nhân** (đối chiếu mã hai tiện ích): cùng API mục lục nhưng link chương khác hẳn — bản Đường đen (v37) `https://api-bc.wtzw.com/chapter?chapterId=…&id=…&reader_agent=0`, bản của người dùng (v4) `https://www.qimao.com/shuku/<id>-<chương>/`. 1.3.690 chỉ biết gắn lại tại chỗ nên dừng ở "mục lục khác dạng": gắn tại chỗ thì chương chưa tải mở bằng link cũ hỏng, làm mới mục lục nhân đôi chương.
- **Bước kiểm 3 mức** (`SourceRebindValidator.Match`):
  - `sameLinks`: link 3 chương mẫu (đầu, đang đọc, cuối) có trong mục lục mới ⇒ gắn lại tại chỗ như 1.3.690.
  - `samePositions`: link khác nhưng tên chương ở đúng các vị trí đó trùng (bỏ khoảng trắng thừa, chữ thường) ⇒ chạy luồng Đổi nguồn (`BookSourceChangeCoordinator.run`, kết quả tìm dựng từ link chi tiết cũ): truyện mới với mục lục nguồn mới, chép chương đã tải theo vị trí, chép thiết lập riêng, xoá truyện cũ sau mốc chốt; đang nghe TTS truyện đó thì giữ truyện cũ. View chuyển phiên AI sang truyện mới như `SearchView+SourceChange`.
  - `different`: lệch cả tên ⇒ không chuyển.
- **Log**: mọi lần không chuyển được ghi `❌ [SourceRebind]` (link + tên chương mẫu cũ/mới, số chương hai bên) nên có trong log cả khi công tắc log tắt; 1.3.690 ghi dòng thường nên bị nuốt.
- **Sheet nhấn giữ** (Kệ, Lịch sử, Tìm trên kệ, Bộ sưu tập; `MissingSourceRebindActionRows`, mới): truyện mất nguồn có thêm hàng "Chuyển sang nguồn <tên>" cho từng tiện ích khớp link, đứng trên "Đổi nguồn". Chạy cho riêng truyện đó, kể cả truyện dải báo đã thử không được trong phiên; không đòi đang ở trang gốc Kệ (các màn này là danh sách), vẫn dừng nếu truyện đang mở ở màn đọc.
- Luồng Đổi nguồn giữ lại truyện cũ (đang nghe TTS, chép chương lỗi) ⇒ truyện cũ vẫn mất nguồn, được nhớ trong phiên để dải báo không chạy lại mỗi lần mở Kệ.
- `MissingSourceRebindRunner` (mới): phần View dùng chung cho dải báo và sheet — chạy lượt, chuyển phiên AI, toast ("… chép chương lỗi nên giữ lại truyện cũ" khi luồng Đổi nguồn giữ truyện cũ). Bấm lúc đang có lượt đổi nguồn khác ⇒ toast báo thử lại.
- Rủi ro đã có từ trước: mở truyện cũ trong lúc luồng Đổi nguồn đang chép chương thì màn đọc giữ `Book` cũ khi nó bị xoá.
- `CLAUDE.md` / `AGENTS.md`: cập nhật mục "Gắn lại nguồn khi tiện ích đã gỡ".
- Chuyển entry `[1.3.661]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code + diff; `check_architecture.py` 1 violation nền (`JSDom`), **0 mới**. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.690] - 2026-11-04

### feat: truyện mất nguồn tự chuyển sang tiện ích khớp link, hỏi một chạm hoặc tự chuyển

Người dùng: *"nếu nguồn bị xoá rồi thì tự check url regex nếu có nguồn nào ăn đổi qua nguồn đó được không?"*, rồi *"tạo config Hỏi một chạm - Tự chuyển"*. Duyệt PA1: gắn lại nguồn tại chỗ.

- **Dò** (`MissingSourceRebindCoordinator`, `Services/Books/SourceRebind/`, mới):
  - Truyện mất nguồn = truyện ở Kệ hoặc Lịch sử có `extensionPackageId` không còn cài; sách nhập từ file không tính.
  - Ứng viên là tiện ích đã cài trừ nguồn Legado, cùng loại nội dung nếu còn tra được loại của nguồn cũ.
  - `regexp` phải khớp **cả chuỗi** `detailUrl` như hợp đồng tiện ích: thử link nguyên văn, rồi link bỏ `http(s)://` và `/` cuối (`ExtensionUrlMatcher.WholeMatcher`, mới). `matches(for:in:)` khớp một phần giữ nguyên cho nút Nhập và dịch trang.
- **Kiểm trước khi chuyển** (`SourceRebindValidator`, mới): chạy chi tiết + toàn bộ mục lục của tiện ích mới trên link cũ. Link của 3 chương đã lưu (đầu, đang đọc, cuối) phải có trong mục lục mới; so cả bản ghép host, bỏ scheme, `www.` và `/` cuối. Không đạt thì không chuyển, vì làm mới mục lục khớp chương theo URL sẽ nhân đôi chương.
- **Ghi** (`BookTransactionCoordinator.rebindSource`, file `+SourceRebind` mới): đổi `extensionPackageId`, `sourceName`, `sourceUrl`, `host`, **giữ nguyên `bookId`**. Chương đã tải, tiến độ, Name/từ điển riêng, phiên AI không phải chép như Đổi nguồn. Truyện vừa được đổi nguồn ở chỗ khác thì không ghi đè.
- **Kệ** (`MissingSourceRebindBanner`, mới; `ShelfView` thêm 2 dòng): dò mỗi lần trang gốc Kệ hiện, hiện ở tab Kệ sách và Lịch sử.
  - Hỏi một chạm: dải báo "N truyện mất nguồn có nguồn khớp link · Chuyển", có nút ẩn trong phiên.
  - Tự chuyển: chạy ngầm cho truyện chỉ khớp một nguồn; khớp từ 2 nguồn thì vẫn hiện dải báo.
  - Chạy lần lượt từng truyện, khớp nhiều nguồn thì lấy nguồn đầu tiên (theo thứ tự đã cài) qua bước kiểm. Truyện không chuyển được nhớ trong phiên để không gọi mạng lại. Đang có lượt Đổi nguồn thì bỏ qua.
  - Rời trang gốc Kệ hoặc mở đúng truyện đang chuyển (`ReaderView.activeBookId`) ⇒ dừng trước khi ghi truyện kế tiếp, lần hiện Kệ sau thử lại.
  - Toast: Hỏi một chạm báo số truyện đã chuyển / mục lục khác dạng / lỗi tải; Tự chuyển chỉ báo truyện đã chuyển (lý do không chuyển nằm trong log).
  - Không dò ở Chi tiết/Reader: hai màn giữ `extensionPackageId` cố định từ lúc mở, Chi tiết tìm truyện theo (link, tiện ích), nên gắn lại nguồn khi màn đang mở là màn đó mất truyện.
- **Cài đặt › Thư Viện › Truyện mất nguồn**: Hỏi một chạm (mặc định) / Tự chuyển (`MissingSourceRebindMode`, khoá `missingSourceRebindMode`).
- Giới hạn: tác vụ tải đang chờ của truyện vẫn mang nguồn cũ; thiết lập theo nguồn (bật dịch riêng của nguồn, đăng nhập, cấu hình tiện ích) theo nguồn mới; Chi tiết của truyện đang mở ở tab khác lúc chuyển thì cần mở lại.
- `CLAUDE.md` / `AGENTS.md`: thêm mục "Gắn lại nguồn khi tiện ích đã gỡ" ở Ràng buộc runtime.
- Chuyển entry `[1.3.660]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code + diff; `check_architecture.py` 1 violation nền (`JSDom`), **0 mới**. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.689] - 2026-11-03

### fix: đổi nguồn chép chương theo lô, dọn truyện cũ an toàn khi app chết

Người dùng: *"tôi đổi nguồn 1 truyện có hơn 2k chương đã tải thành đơ app sau đó thoát app luôn. nhưng vẫn chuyển được dữ liệu, tuy nhiên nguồn cũ vẫn còn"*. Lúc đổi không có TTS; truyện mới đủ chương.

- **Nguyên nhân** (suy từ code; log chỉ cho thấy main thread bị chặn ≥ 3 s lúc 21:36:44–21:36:59 và không có dòng ❌ nào của luồng đổi nguồn):
  - Chép chương đã xong, app chết trước khi lệnh xoá truyện cũ lưu xuống đĩa. Bước xoá chạy `BookTransactionCoordinator.deleteBook` trên context **main**, cascade `Book.chapters`. Worker chuyển mục lục sang SQLite (27/7, gỡ 28/7) không xoá dòng `Chapter` SwiftData, nên truyện đời đó còn hàng nghìn dòng phải cascade trên main. Bước này cũng đi tắt qua `BookStorageManager` (không huỷ tải, không xoá bìa).
  - Thứ tự cũ chuyển rồi **xoá ngay** thiết lập riêng (từ điển/rule, phiên AI, trí nhớ AI, điểm quét name) trước khi xoá truyện cũ ⇒ chết giữa chừng thì còn hai truyện, truyện cũ mất thiết lập. Không có gì dọn lại.
  - Vòng chép từng chương: mỗi chương mở/đóng 2 file, 3 lần nhảy actor, một lần commit sqlite; lỗi nuốt bằng `try?`, không tiến trình.
- **`BookSourceChangeCoordinator`** (mới, `Services/Download/SourceChange/`) nhận cả lượt từ `SearchView` (812 ⇒ 693 dòng; phần View còn ở `SearchView+SourceChange`):
  - Nhật ký `source_change/journal.json` (`BookSourceChangeJournal`) ghi **trước** tác dụng phụ đầu tiên. Trước mốc `.committed` chỉ **chép**, truyện cũ nguyên vẹn.
  - Huỷ lượt tìm đang chạy. Nguồn mới trả mục lục xong mới huỷ tác vụ tải của truyện cũ (tra lỗi thì không đụng gì) và ghi nốt lệnh ghi đang chờ của nó, rồi mới đọc mục lục để chép. Nhật ký của lượt trước chưa dọn xong ⇒ báo lỗi, không ghi đè.
  - Truyện đích cùng tiện ích + link chi tiết đã có trên máy ⇒ **dùng lại** (không tạo bản UUID trùng); tiến độ lấy theo bản đọc gần hơn, cờ kệ/lịch sử chỉ bật thêm (`BookTransactionCoordinator.mergeSourceChangeState`).
  - `BookSourceChapterCopier` chép theo lô ≤ 64 chương / ≤ 4 MB: một handle đọc + một handle ghi (`BookBinManager.copyChapterContents`), một transaction (`ChapterStore.markChaptersCached`, tra theo chỉ số). Bỏ qua chương truyện đích đã có. Overlay hiện "Đang chép chương đã tải N/M". Giữ `beginBackgroundTask`; hết hạn thì dừng giữa hai lô và báo "Bị ngắt vì app chuyển nền". Chương lỗi gom một dòng ❌; có chương lỗi ⇒ **giữ** truyện cũ.
  - Sau mốc chốt, View đóng các màn đang giữ `Book` cũ; 1,2 s sau mới xoá truyện cũ qua `BookStorageManager.deleteBooksAsync` (context nền) rồi xoá thiết lập cũ.
  - Mở app / app hoạt động lại (`MainTabView+SourceChangeRecovery`): nhật ký `.copying` ⇒ lùi (xoá truyện mới nếu lượt đó tạo ra); `.committed` ⇒ dọn nốt truyện cũ. Có toast.
- **Thiết lập riêng**: `BookSourceMigrator.copyBookScopedSettings` (chỉ chép, truyện đích có rồi thì giữ của đích) + `removeBookScopedSettings`. `AIChatHistoryStore.copySessions` nạp từng phiên, ghi mục lục một lần; `BookAIMemoryStore.copyMemory`; `AINameScanScopeStore.copy`/`remove`. Đang nghe TTS truyện cũ thì truyện cũ giữ đủ phiên AI và trí nhớ AI (trước đây vẫn bị gỡ).
- **Truyện đã nửa vời trước bản này** (không có nhật ký): mở truyện cũ ⇒ Đổi nguồn ⇒ chọn lại đúng nguồn mới. App dùng lại truyện mới đã có, chỉ chép chương còn thiếu rồi xoá truyện cũ.
- `rules.md`, `CLAUDE.md`, `AGENTS.md` ghi tên hàm mới. Chuyển entry `[1.3.659]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code + diff; `check_architecture.py` trước và sau đều 1 violation nền (`JSDom`), **0 mới**. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.688] - 2026-11-03

### fix: bật dịch trong Reader dịch lại ngay chương đang mở

Người dùng: *"tôi bật dịch lại thì nội dung chương không dịch lại ngay. phải thoát vào lại reader nó mới chịu dịch"*. Lỗi đi kèm (truyện có tiện ích nguồn đã gỡ thì bị tắt dịch): người dùng chọn **không** sửa.

- **Nguyên nhân**: `ReaderViewModel.toggleTranslation(enabled:)` chỉ gán cờ, không dựng lại đoạn. Chương dựng lúc tắt dịch có `translated == original` (`untranslatedTextResult`), nên bật lên thì `ParagraphCardView.displayText` vẫn ra chữ gốc. Tắt dịch thì đúng ngay vì chữ gốc luôn có. Thoát vào lại thì đúng vì ViewModel mới đọc lại cờ, `isTranslationFresh` thấy lệch và dựng lại. `ChapterContentRepository` không liên quan (chỉ giữ chữ gốc).
- **Reader** (`ReaderViewModel+Translation.swift`): `toggleTranslation` dựng lại chương đang hiện (`refreshParagraphItems`, gồm đoạn tiêu đề -1) khi bản đang có không khớp công tắc mới; cờ không đổi thì không làm gì (nhánh Pronouns/LuatNhan vẫn gọi lại hàm này). Chương khác trong cache tự dựng lại khi tới, như cũ. Header và sheet mục lục vốn đã theo cờ.
- **TTS đang phát cùng truyện** (`TTSManager+TranslationIdentity.swift`, `updateTranslationSetting(for:enabled:)`, gọi từ `onChange` của Reader): chữ TTS đọc và vệt highlight phải cùng hệ toạ độ với chữ Reader đang hiện.
  - Đang phát ⇒ tải lại chương hiện tại qua `ChapterContentRepository`, rồi `startSpeaking` từ đầu đoạn đang đọc với `translationEnabled` mới. Đây là tham số mới của `startSpeaking`; bỏ trống thì vẫn tra `TranslationConfigStore` như cũ.
  - Đang dừng ⇒ chỉ đổi cờ phiên và bỏ prefetch, áp từ chương sau; phần còn lại của chương đang dừng giữ chữ cũ.
  - Cờ phiên đổi ngay, nên bấm bật/tắt liên tiếp thì chỉ lượt cuối được đọc lại.
- Gom hai khối huỷ phần đã dịch sẵn giống hệt nhau (khi đổi từ điển / rule dịch nhanh) thành `invalidatePreparedTranslationState()`. `TTSManager.swift` 3500 ⇒ 3468 dòng, về dưới baseline 3470.
- Chuyển entry `[1.3.658]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code + diff; `check_architecture.py` trước sửa 2 violation nền (`JSDom`, `TTSManager`), sau sửa còn 1 (`JSDom`), **0 mới**. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.687] - 2026-11-03

### feat: các nhánh của một nhóm trong rule dịch dùng chung số {i}

Người dùng: *"nhiều any ngăn cách bởi | thật ra chỉ có một nhưng gợi ý nhập phần nghĩa lại không nhận ra"*. Đã chốt: áp **mặc định** cho mọi nhóm, không cần cú pháp riêng.

- **Parser** (`QuickTranslationRuleParser.parseGroup`): mỗi nhánh của nhóm `( | )` đánh số từ **cùng một số**; sau nhóm, số tiếp theo nối từ nhánh nhiều token nhất. Giống `(?|…)` của PCRE.
  - `第<n><L><any>(\(<any>\)|（<any>）|【<any>】)<$>` giờ chỉ có `{0}…{3}`, trong đó `{3}` là nội dung ngoặc của nhánh khớp.
  - `(<n>|<a><d>)<L>`: `<n>` = 0; `<a>` = 0, `<d>` = 1; `<L>` = 2.
  - Nhóm lồng áp luật theo từng tầng. `|` ngoài nhóm vẫn là chữ thường.
  - Matcher không đổi: nhánh không khớp để `{i}` rỗng như trước.
- **Màn sửa rule** (`QuickTranslationRuleDraftAnalyzer.segments`):
  - Số `{i}` của chip lấy từ AST của parser, không tự đếm. Mẫu đang gõ dở chưa parse được thì lùi về đánh số phẳng.
  - `Segment` thêm `tokenPosition` (vị trí duy nhất). Thanh chỉnh độ dài định vị chip bằng vị trí này (`replacing(tokenPosition:)`, `applyTokenSpec`), nên chỉnh `<any>` ở nhánh 2 không sửa nhầm nhánh 1.
- **Gợi ý ô Bản dịch và dải chip `{i}`:**
  - Mỗi số một chip; nhãn VoiceOver ghép các token chung số.
  - Token chưa dùng **không còn tô đỏ như lỗi**, vì `UNUSED_CAPTURE` chỉ là cảnh báo từ 1.3.339. Câu "mọi token phải được dùng" đổi thành "{i} chỉ dùng để khớp, không xuất ra bản dịch". Lời cảnh báo của compiler ghi theo số `{i}`.
- Câu giải thích token ở màn sửa rule và đoạn token trong `CLAUDE.md` / `AGENTS.md` ghi luật chung số.
- **Đổi hành vi rule cũ:** rule có token ở từ 2 nhánh trở lên của cùng một nhóm sẽ bị dời số. `{i}` vượt số token thì rule báo lỗi và không chạy; còn trong khoảng thì trỏ sang token khác. Bộ rule mặc định tải về (633 rule) đã quét: không rule nào bị ảnh hưởng.
- **Kiểm chứng:** đọc code + diff; `check_architecture.py` 2 violation nền, **0 mới**. Dò tay trên code các mẫu:
  - `(<n>|<a><d>)<L>`
  - `((<n>|<a>)<d>|<any>)`
  - `a|<n>`
  - `\(` và `\|`
  - mẫu thiếu `)`
  - rule ngoặc ở trên

  Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.686] - 2026-11-03

### feat: neo đầu/cuối dòng <^> <$> và <any> bắt mọi ký tự trong rule dịch

Người dùng: *"có token xác định đầu dòng trong rule dịch chưa, nếu chưa thì thêm vào"* và *"token any sửa lại bắt mọi ký tự và tăng length lên"*. Chốt bằng bảng chọn:
- Thêm `<^>` và `<$>`, bỏ qua khoảng trắng đầu/cuối dòng.
- `<any>` bắt mọi ký tự trừ xuống dòng, mặc định 1–50, chỉnh được tới 100.

- **Neo `<^>` / `<$>`** (`QuickTranslationRuleLineAnchor`, `QuickTranslationRuleParser+LineAnchor`, mới):
  - Rộng 0 và **không sinh capture**, nên số `{i}` của rule giữ nguyên.
  - `<^>` đúng khi từ đầu chuỗi (hoặc sau `\n`/`\r`) tới vị trí hiện tại chỉ có khoảng trắng; `<$>` đối xứng ở cuối dòng. Khoảng trắng thụt nằm ngoài vùng khớp nên giữ nguyên trong bản dịch.
  - Ghép `|`, ghi độ dài `:min-max` hoặc thêm `?` sau neo ⇒ lỗi `UNKNOWN_TOKEN_NAME` kèm câu giải thích.
- **Giao diện neo:**
  - `QuickTranslationRuleTokenSettings.Kind` thêm `lineStart = "^"`, `lineEnd = "$"` vào **cuối** danh sách, có công tắc ở Cấu hình token (chung và riêng theo truyện).
  - Có nút trong bảng token và gợi ý trên bàn phím.
  - Chip ở màn sửa rule không có thanh độ dài và không được đánh số.
  - Phần giải thích token có ví dụ `<^>第<n>章 = Chương {0}`.
- **`<any>`:**
  - Nuốt **mọi** ký tự, kể cả dấu câu và khoảng trắng; chỉ dừng ở xuống dòng.
  - Không ghi độ dài ⇒ 1–50. Thanh chỉnh độ dài tới 100 (`TokenSpec.defaultRangeMax` / `lengthUpperBound`); token khác giữ 1–12 và trần 20.
  - Được nuốt **trọn** Name riêng: capture mang `allowsEnclosedNames`, `+NameProtection` chấp nhận. Chỉ không được bắt đầu hay kết thúc giữa một Name.
  - Theo sau là chữ cố định thì chỉ thử những độ dài có chữ đó ngay sau, nên vẫn nhẹ dù dài hơn.
  - Ví dụ: `<any:1-6>说` trên `走吧，他说` giờ lấy `走吧，他`; `第<n>章<any>` giờ khớp `第12章 风起`.
- **Đổi hành vi rule cũ:** `<any>` không ghi độ dài giờ nuốt tới 50 ký tự, kể cả dấu câu.
- `CLAUDE.md` / `AGENTS.md`: cập nhật đoạn token ở mục Dịch thuật VietPhrase.
- Chuyển entry cũ nhất sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng:** đọc code + diff; `check_architecture.py` 2 violation nền, **0 mới**. Tự soát tay các ca:
  - `<^>第<n>章` khớp `　　第12章 风起` mà không khớp `他说第12章`.
  - `<any>的<any>` với Name `张三` nằm trọn trong cụm vẫn khớp.

  Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.685] - 2026-11-03

### feat: sheet Bộ lọc hiện chữ đã dịch khi nguồn bật dịch

Người dùng: *"hãy hiển thị nội dung bộ lọc đã dịch nếu ext config dịch"*. Chốt: chỉ sheet Bộ lọc, màn Cấu hình tiện ích giữ nguyên văn.

- `ExtensionFilterSheet`:
  - Lúc nạp, nếu nguồn bật dịch (`TranslationConfigStore.isTranslationEnabled(bookId: nil, packageId:, isChineseSourceHint:)`, nguồn tiếng Trung tự bật) thì gom tiêu đề, dòng phụ và lựa chọn của các mục lọc có chữ Hán, rồi dịch **ngoài main** bằng `translateMeta` (bỏ trùng) vào bảng `translations`.
  - Chưa dịch xong thì hiện chữ gốc.
- `ExtensionConfigFieldRow` thêm `displayText`, áp cho tiêu đề, dòng phụ, nhãn lựa chọn trong menu, lựa chọn đang hiện và tiêu đề màn danh sách. **Giá trị lưu vẫn là chữ gốc**, vì script nhận đúng chuỗi đó. Mặc định giữ nguyên nên màn Cấu hình không đổi.
- Phần E (thứ tự explore/home) người dùng đã huỷ.
- Chuyển entry cũ nhất sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng:** đọc code + diff; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows), chưa thử trên máy. Cần thử: mở Bộ lọc của qidian/qimao khi nguồn bật dịch, chọn một lựa chọn đã dịch rồi Áp dụng và kiểm danh sách lọc đúng.

## [1.3.684] - 2026-11-03

### feat: phồn→giản trước khi dịch trang trình duyệt, chung và riêng theo tên miền

Người dùng: *"thêm cài đặt phồn -> giản trước khi dịch trang"*. Đã chốt bằng bảng chọn: có công tắc chung (mặc định tắt) và chỉnh riêng theo tên miền, còn *"Phồn → giản thụt vào trong Tự dịch QT để biết nó là cài đặt con của Tự dịch QT"*.

- **Luật** `BrowserTranslatePolicy.convertsTraditional(urlString:)`: lấy chỉnh riêng của tên miền trước (`BrowserSitePreference.convertsTraditional`, có gộp tên miền cha); không có thì theo công tắc chung `browserTranslateConvertsTraditional`. Không theo tiện ích khớp URL.
- **Áp cho:** dịch QT cả trang (tự dịch lẫn nút dịch bấm tay) và sheet "Dịch QT" khi bôi đen. `BrowserPageTranslator` đọc cờ trên main ở mỗi lô rồi chỉ chuyển `Bool` sang luồng nền.
- **Cài đặt › Trình duyệt:** section mới "Dịch trang", công tắc "Chuyển phồn thể → giản thể trước khi dịch" kèm nút "?" giải thích (trang giản thể có thể bị đổi vài chữ mập mờ).
- **Bảng khiên:** công tắc con "Phồn → giản" thụt dưới "Tự dịch QT", luôn hiện kể cả khi tự dịch đang tắt. Dòng phụ "Theo cài đặt chung" / "Bật/Tắt cho <tên miền>"; nút "Dùng cài đặt chung" xoá chỉnh riêng của cả tên miền cha.
- **Dịch lại ngay:** đổi công tắc thì tab đang dịch được tắt rồi bật lại dịch trang, không nạp lại. Đổi công tắc chung chỉ dịch lại các tab không có chỉnh riêng.
- **Trang đã chỉnh riêng:** thêm chip "Phồn → giản" / "Giữ phồn thể".
- **Backup:** công tắc chung tự vào backup. Chỉnh riêng nằm ở `site_preferences.json` nên không được backup, giống "Tự dịch QT".
- **Chưa làm:** tiêu đề tab dịch qua `translateMeta` vẫn chưa chuyển phồn→giản.
- Chuyển entry cũ nhất sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng:** đọc code + diff; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows), chưa thử trên máy. Cần thử:
  - Trang phồn thể có/không bật công tắc.
  - Công tắc riêng theo tên miền thắng công tắc chung.
  - Dịch lại ngay khi đổi công tắc.
  - Sheet Dịch QT.

## [1.3.683] - 2026-11-03

### feat: bộ rule dịch tên chương, ưu tiên riêng > tên chương > chung

Người dùng: *"rule dịch thêm 1 phạm vi rule dành cho chương nữa; nhớ thêm vào hub từ điển để quản lý; nhớ backup các rule của chương; độ ưu tiên rule riêng > rule tên chương > rule chung; rule tên chương chỉ dùng để dịch tên chương thôi"* và *"thêm option lưu vào bộ tên chương khi bấm lưu ở màn hình thêm rule"*.

- **Phạm vi thứ ba** `QuickTranslationRuleScope.chapterTitle`:
  - Lưu ở file `translate/QuickTranslateChapterRules.txt`, do store mới `QuickTranslationRuleChapterStore` quản lý (nạp lười, tôn trọng công tắc tổng). Có file tắt riêng `QuickTranslateChapterRulesDisabled.txt`.
  - Hạng `scopeRank`: riêng 0, tên chương 1, chung 2 (`QuickTranslationRuleScope.bookRank/chapterTitleRank/globalRank`). Mặc định của compiler đổi sang hạng chung. Thứ tự đi qua tiêu chí "bộ rule" có sẵn trong cấu hình ưu tiên.
- **Chỉ áp khi dịch tên chương:**
  - `translateChapterTitle(WithMapping)` chạy trong cờ task-local `TranslationReadContext.appliesChapterTitleRules`. Engine và chẩn đoán chỉ trộn bộ tên chương khi cờ bật.
  - Khoá cache `translateText`, cache rewrite và memo mapping có thêm cờ này, nên dòng tên chương và dòng nội dung trùng chữ không dùng chung kết quả.
  - Generation của store đi vào `translationGenerationToken`.
  - Mọi đường dịch tên chương đều có bộ này: Reader đoạn -1, TTS chunk -1, widget, mục lục, xuất TXT, `Qt.translate` chapter_name.
- **Tắt rule:** file tắt riêng truyện vẫn tắt mẫu ở **mọi** bộ. File tắt tên chương chỉ tắt rule của bộ tên chương, file tắt chung chỉ tắt rule của bộ chung. Có trạng thái chip mới `.disabledForChapterTitles` ("tắt ở bộ tên chương").
- **Giao diện:**
  - Hub Từ điển có mục **Rule Tên chương** giữa Riêng và Chung. Cài đặt › Quản lý rule dịch có thêm "Danh sách rule tên chương".
  - Danh sách, hàng rule và menu nhập/xuất/tắt chạy đúng 3 phạm vi: nút + lưu đúng bộ đang mở, tên file xuất `QuickTranslateChapterRules.txt`, "chia sẻ cả bộ" chỉ cho bộ riêng.
  - Nút Chuyển thành menu chọn bộ đích (thay `opposite`).
  - Màn thêm rule có thêm **"Lưu vào bộ rule tên chương"**, mặc định của nút Lưu giữ như cũ. Có truyện ⇒ menu ba mục. Không có truyện ⇒ chạm lưu vào bộ mặc định (mở từ danh sách tên chương thì là bộ tên chương), nhấn giữ để chọn bộ khác.
  - Reader: chip rule trên dòng tiêu đề chương soi cả bộ tên chương. Nhấn giữ chip có tắt ở bộ tên chương và chuyển sang hai bộ còn lại.
- **Backup:** gói và khôi phục `config/QuickTranslateChapterRules.txt` + `config/QuickTranslateChapterRulesDisabled.txt`. Khôi phục xong thì dọn cache dịch và phát một thông báo. `BackupLibraryFingerprint` gộp các file cấu hình thành vòng lặp (thêm 2 file ⇒ mỗi máy sẽ tự sao lưu thêm một lần sau khi cập nhật).
- **Bình luận** (anh Bửu nhờ qua phiên bình luận): dòng mô tả dưới tên, ở cả bình luận lẫn trả lời, đổi sang xám mờ `.tertiary` để tách khỏi nội dung (người dùng chọn kiểu B trên mockup).
- `CLAUDE.md` / `AGENTS.md`: thêm đoạn "Tên chương" ở mục Dịch thuật VietPhrase.
- Chuyển entry cũ nhất sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng:**
  - Đọc code + diff; `check_architecture.py` 2 violation nền, **0 mới**.
  - Đã soát thứ tự khoá: `translationGenerationToken` chỉ đọc bộ đếm của store, `notifyChange` chạy ngoài khoá.
  - Không build tại chỗ (Windows), chưa thử trên máy. Cần thử:
    - Rule tên chương thắng rule chung, thua rule riêng.
    - Nội dung chương không bị rule tên chương ảnh hưởng.
    - Thêm/sửa/tắt/chuyển/nhập/xuất ở hub.
    - Backup rồi khôi phục.
    - Màu mô tả bình luận.

## [1.3.682] - 2026-11-03

### feat: token <any> khớp cụm ký tự bất kỳ trong rule dịch

Người dùng: *"thêm token cụm ký tự bất kỳ trong rule dịch, (nó dùng để xác định một cụm ký tự không cần biết nghĩa nó là gì, chỉ cần biết nó độ dài từ bao nhiêu đến bao nhiêu, trả về phần nghĩa sẽ là cụm nguyên bản đó)"*. Chốt bằng bảng chọn: tên `<any>`, dừng ở dấu câu và khoảng trắng, rule có `<any>` mà không có chữ cố định thì báo lỗi.

- **Cú pháp** `<any>` / `<any:min-max>` (mặc định 1–12, `QuickTranslationRuleParser`): khớp một cụm ký tự bất kỳ, capture trả **nguyên văn**. Chuỗi sau rule vẫn được tách từ và dịch từ điển như phần còn lại của dòng, nên `<any:1-6>的<any:1-6> = {1} của {0}` đảo trật tự rồi dịch đúng. Không ghép được với token khác bằng `|` (báo lỗi).
- **Khớp** (`QuickTranslationRuleMatcher.walkAnyRun`):
  - Nuốt mọi ký tự trừ dấu câu (Unicode P*) và khoảng trắng/xuống dòng.
  - Thử dài → ngắn có lùi như token số; không cắt giữa cặp surrogate.
  - Dừng ở ranh giới Name riêng, nhờ đó vẫn lùi về độ dài ngắn hơn thay vì bỏ cả lượt khớp.
- **Ưu tiên**: `<any>` có hạng độ hẹp 7, rộng nhất (`QuickTranslationRuleNumeralNarrowness.anyRunRank`). Khi hoà mọi tiêu chí, nó thua mọi token ký tự khác; `wildcardCapacity` cộng `maxLength`.
- **Lỗi nặng mới** `ANY_WITHOUT_LITERAL` (`QuickTranslationRuleIssue`, `QuickTranslationRuleCompiler`): rule có `<any>` mà không có chữ cố định nào thì bị loại khi nạp, màn sửa rule báo *"Rule có <any> phải có ít nhất một chữ cố định"*. Lỗi này báo thay cho `NO_LITERAL_ANCHOR` ở cùng chỗ.
- **Giao diện**:
  - Công tắc `<any>` ở Cấu hình token rule (chung và riêng theo truyện).
  - Nút trong bảng token và hàng gợi ý trên bàn phím.
  - Phần giải thích token có ví dụ.
  - `QuickTranslationRuleTokenSettings.Kind.any` nối vào **cuối** danh sách, nên chữ ký cache dịch đổi một lần. Khoá cài đặt `quickTranslateRuleTokenAnyEnabled` tự vào backup.
- Chuyển entry cũ nhất sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**:
  - Đọc code + diff; `check_architecture.py` 2 violation nền, **0 mới**.
  - Tự soát tay 4 ca:
    - `我的剑` ⇒ `剑 của 我`.
    - `走吧，他说` với `<any:1-6>说` chỉ lấy `他`.
    - `<any:2-4>` đứng một mình bị lỗi nặng.
    - `第<n>章<any:1-30>` **không** khớp `第12章 风起` vì khoảng trắng chặn `<any>`; muốn chịu cả hai dạng thì viết `第<n>章( )?<any:1-30>`.
  - Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.681] - 2026-11-03

### fix: tên chương dịch như nội dung, phồn→giản khi xuất và mục lục comic theo cấu hình truyện

Người dùng: *"điều tra logic dịch tên chương giúp tôi"*. Báo cáo điều tra liệt kê 18 chỗ hiện tên chương và 14 điểm lệch. Sau đó chốt bằng bảng chọn: *"translateChapterTitle không dịch kiểu translateChapterTitle, dịch như dịch content bình thường thôi vì bây giờ tôi đã có rule <L> rồi"*, *"Xuất TXT bỏ qua phồn→giản là quên làm"*, giữ `title_trans` làm mới bằng tay, rồi duyệt plan.

- **Tên chương dịch y như nội dung** (`TranslateUtils.translateChapterTitle`): bỏ hai regex cứng `第N章` ⇒ "Chương N: …" và số Ả-rập `"1. …"` ⇒ "Chương 1: …", cùng `chapterUnitMap`, `chineseNumberToInt` và 4 regex trong `TranslateUtils+MappingMemo`. Hàm còn lại: phồn→giản → trim → `chapterTitleCache` → `translateContent`. Nhãn chương do rule dịch nhanh `<L>` của người dùng lo. Tên không có chữ Hán giữ nguyên, nên "Dịch lại tên chương", nhập TXT/EPUB/comic/video và xuất TXT không còn biến `1. Mở đầu` thành `Chương 1: Mở đầu`. Bỏ tham số `applyingQuickTranslationRules` của hàm này; `Qt.translate(..., {chapter_name})` nay áp rule dịch chung.
- **Phồn→giản theo công tắc của truyện** (`TranslationConfigStore.convertsTraditionalToSimplified(bookId:)`, mới): xuất TXT áp cho cả tên lẫn nội dung (trước quên). Mục lục tab Chi tiết và comic đi theo luật của sheet mục lục Reader: bật phồn→giản thì bỏ bản lưu và dịch sống có chuyển. Chỉ mục tìm online ở Chi tiết thêm cờ này vào khoá.
- **Comic** theo công tắc dịch của truyện/nguồn (`TranslationConfigStore`, nghe `didChangeNotification`), không còn theo công tắc chung. Tên chương dịch ngoài main (`ComicChapterTitleTranslator`, `ComicReaderViewModel+TitleTranslation`, mới); lúc chưa dịch xong thì tạm hiện bản lưu `titleTrans`.
- **Trình phát video** dịch tên nhóm tập (`isSection`) một lần sau khi nạp, theo công tắc truyện + phồn→giản; tập thường giữ nguyên.
- **Ô tìm chương** ở Chi tiết (đã lưu và online) và comic dùng `ChapterTitleSearchMatcher` như Reader: không phân biệt hoa/thường và dấu.
- **Dọn dẹp**:
  - Lưới tập video ở Chi tiết dịch vào `@State` khi mục lục/từ khoá/thứ tự/công tắc đổi, không dịch mọi tập ở mỗi lần vẽ.
  - Sheet mục lục Reader bỏ lớp dịch thứ hai và việc ghi `@State` trong `body` (`displayTitleCache`, `warmNearbyTitles`).
  - Xoá code chết `ReaderView.displayedBookTitle`.
  - Lưu nền `title_trans` ở Chi tiết và "Dịch lại tên chương" chờ từ điển nạp xong.
- **Giữ nguyên theo người dùng chọn**:
  - `title_trans` chỉ làm mới bằng tay. Truyện cũ còn bản lưu dạng "Chương 12: …" tới khi bấm "Dịch lại tên chương".
  - Kệ sách và hộp thư theo công tắc chung.
  - Rule TOC và "Loại bỏ tiêu đề chương trùng" không đổi.
- Chuyển entry cũ nhất sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**:
  - Đọc code + diff; `check_architecture.py` 2 violation nền, **0 mới**.
  - Không build tại chỗ (Windows) — CI là cổng biên dịch.
  - Chưa thử trên máy. Cần thử:
    - Rule `<L>` cho tên chương ở Reader, TTS và mục lục sau "Dịch lại".
    - TXT tiếng Việt `1. …` giữ nguyên tên.
    - Phồn→giản ở Chi tiết, comic và file TXT xuất.
    - Comic nguồn Trung khi công tắc chung tắt.
    - Nhãn nhóm tập video.
    - Tìm "kiem" ra "Kiếm".

## [1.3.680] - 2026-11-03

### feat: bình luận hiện avatar người bình luận và các trả lời

Người dùng: *"app chưa làm: replies của comment chưa được hiển, avatar cũng chưa được dùng để hiển thị avatar người comment. xem ext qimao của đường đen để hiểu rõ hơn"*. Chốt bằng mockup + bảng chọn (thẻ Chi tiết chỉ dòng "N trả lời", xổ tại chỗ, mô tả dưới tên, hàng nút kiểu B, qimao tải trả lời khi bấm) rồi duyệt plan.

- **Đọc dữ liệu** (`ExtensionManager+ItemParsing.listItem`): mỗi item đọc thêm `avatar` (resolve như bìa: host item → `source`) và `replies` theo template script bình luận của hợp đồng (mảng cùng dạng bình luận, lồng nhau) — app hiện **một** cấp, trả lời của trả lời đứng ngay sau trả lời cha (`commentReplies`, sâu tối đa 8), trả lời không có nội dung lẫn mô tả bị bỏ. Khoá riêng của FreeBook (hợp đồng không có): `reply_source: {input, script}` (`CommentReplySource`, mới) + `reply_count` = trả lời **tải khi bấm**, chỉ dùng khi `replies` rỗng. `ExtensionItemResult` thêm `avatar`, `replies`, `replySource`, `replyCount` (đều có mặc định).
- **Hàng bình luận dùng chung** (`CommentRowView`, mới, `Views/BookDetail/Comments/`): thay khối chép trùng ở thẻ Chi tiết (`CommentSectionView`) và Tất cả bình luận (`AllCommentsView`). Avatar tròn 32pt / 36pt (`CommentAvatarView`, mới — không có URL thì hình người xám như cũ, đang tải / lỗi thì placeholder hình người), tên, dòng mô tả **dưới** tên (trước nằm bên phải tên; không có nội dung thì mô tả làm thân, không lặp), nội dung 3 dòng. Có trả lời ⇒ cùng hàng với "Xem thêm" (trái) là "💬 N trả lời ⌄" màu nhấn (phải); mặc định thu gọn ở cả hai màn.
- **Khối trả lời xổ tại chỗ** (`CommentRepliesBlock`, mới): thụt vào, vạch dọc trái; mỗi trả lời avatar 22pt, tên, mô tả, nội dung 3 dòng có "Xem thêm" nhỏ; tên / mô tả / nội dung dịch như bình luận. `replies` lồng sẵn ⇒ hiện ngay; `reply_source` ⇒ lần mở đầu gọi `script(input, page)` qua `SourceRuntime.executeCustomScript`, "Đang tải trả lời…", lỗi + "Thử lại", "Tải thêm trả lời" khi còn trang. Trang đã tải giữ ở hàng cha ⇒ thu gọn / mở lại không tải lại. Khối dài hơn 3 trả lời có "Thu gọn" ở đáy. Số trên nút: lồng sẵn = số trả lời có thật; tải khi bấm = `reply_count`, không khai ⇒ "Xem trả lời".
- **Thành phần chung**: `ExpandableTextView` thêm `toggleFont` và `trailingAccessory` (nút phụ cùng hàng "Xem thêm"; mặc định như cũ). `RemoteCoverImage` thêm `placeholderSymbol` (mặc định `photo`). Hàng bình luận gắn `.buttonStyle(.borderless)` để các nút trong một hàng `List` nhận chạm riêng.
- `CLAUDE.md` / `AGENTS.md`: thêm một câu ở mục Extension JavaScript.
- Tiện ích (repo riêng, cùng đợt): STV v24 + qidian v27 tách trả lời khỏi danh sách bình luận gốc (trước hiện thành bình luận riêng lẻ) + avatar; qimao v3 avatar + `reply_source` (`reply.js`), bỏ kiểu gộp trả lời vào nội dung.
- Chuyển entry `[1.3.650]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code + diff; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy — cần thử: avatar hiện ở thẻ / Tất cả bình luận / trả lời, bấm "N trả lời" xổ đúng bình luận và không kích hoạt "Xem thêm" (và ngược lại) trong hàng `List`, qimao tải / tải thêm / thử lại trả lời, cuộn hàng đang tải ra khỏi màn rồi quay lại.

## [1.3.679] - 2026-11-03

### fix: app đơ khi cuộn tới cuối danh sách do chân danh sách tự kích hoạt lại

Người dùng (sau 1.3.678): *"có lỗi vuốt xuống cuối danh sách thì đơ app, lỗi bị sau khi làm Vòng xoay cuối danh sách"*; thêm *"chưa thấy chữ "Đã hết" đã đơ rồi"*. Duyệt plan sửa.

- **Nguyên nhân (suy từ code, chưa tái hiện)**: `LoadMoreFooter` của 1.3.678 ghi `@State spinnerToken = UUID()` trong `onAppear` ở **mọi** trạng thái để dựng mới vòng xoay. Giá trị mới mỗi lần ⇒ hàng cuối của `List` / `LazyVGrid` vẽ lại → "hiện" lại → ghi tiếp, vòng lặp trên main thread; ở trạng thái đang nạp mỗi vòng còn sinh thêm một `Task` nạp trang kế ⇒ đơ ngay khi vòng xoay vừa lộ ra ở cuối (trước cả khi tới "Đã hết").
- **`LoadMoreFooter` không giữ state**: bỏ `spinnerToken` + `.id` bên trong; `onAppear` chỉ gọi nạp trang kế khi đang nạp. Vòng xoay mới cho mỗi trang do nơi dùng gắn `.id(số mục)` — cách màn Tìm và các lưới đã chạy ổn trước 1.3.678; thêm cho ba chỗ còn thiếu: danh sách Khám phá / Thể loại (`DiscoveryNovelsLayoutView`, số truyện), Kệ / Lịch sử kiểu Danh sách (`ShelfBooksLayoutView`, số truyện đang hiện), Tất cả bình luận (số bình luận). Trang không thêm mục nào thì số không đổi, không kích hoạt lại.
- **Gia cố phụ**: `AppAccentColor.applyToWindows()` bỏ qua cửa sổ đã đúng màu — trước đây mỗi lần một sheet / cửa sổ nổi có `.appAccentTint()` hiện là `tintColorDidChange` lan khắp cây view.
- Chuyển entry `[1.3.649]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code + diff; `LoadMoreFooter.swift` không còn `@State` / `UUID()`; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy — cần thử: cuộn tới cuối Khám phá / Thể loại / Tìm / Bình luận / Kệ / Lịch sử (cả kiểu Danh sách lẫn lưới) không đơ, vòng xoay vẫn hiện ở mỗi lần nạp trang kế, hết trang hiện "Đã hết".

## [1.3.678] - 2026-11-03

### fix: vòng xoay cuối danh sách, nút chọn loại chỉ icon và màu nhấn tuỳ chọn

Người dùng: *"các danh sách vô hạn có vẻ đang thiếu icon xoay tròn cuối trang trong lúc đang load phần kế tiếp nhỉ?"*; thêm *"nút chọn tất cả truyện chữ truyện tranh phim bên ô tìm kiếm của chọn nguồn hãy chỉ hiển thị icon của option đã chọn thôi"* và *".tint(.white) đổi thành màu khác đi … thêm config cho tint đi, thêm 1 nav vào màn setting giao diện … xem trước UI … Bỏ option trắng đi nhé, mặc định xanh ngọc"*. Chốt bằng mockup + bảng chọn rồi duyệt plan, gộp một commit.

- **Chân danh sách cuộn vô hạn** (`LoadMoreFooter`, mới): vòng xoay khi đang nạp trang kế; "Không tải được trang kế" + "Thử lại" khi trang kế lỗi hết 3 lượt tự thử; "Đã hết · N truyện" (phim / bình luận) giữa hai vạch mờ khi hết trang. Vòng xoay được dựng mới mỗi lần chân hiện ra — `ProgressView` trong hàng `List` bị tái dùng hiện trống từ lần thứ hai, lý do "thiếu vòng xoay". Áp cho Khám phá + Thể loại/nhãn (`DiscoveryNovelsLayoutView`, cả danh sách lẫn lưới), Tìm trong một nguồn, Tất cả bình luận, Kệ / Lịch sử (nạp trên máy, "Đã hết" chỉ khi danh sách dài hơn một lượt 50). Thời điểm nạp giữ nguyên (người dùng chọn), không có nút "Xem thêm".
- **Bộ nạp báo lỗi trang kế**: `PaginatedNovelLoader.loadMoreError` + `retryLoadMore()`; `SearchPagingState.fail(message:)` thay `stop()` (trước đây tắt im lặng) + `retryLoadMoreSearchResults()`; `AllCommentsView` cùng kiểu (trước đây vòng xoay treo mãi). Trong lúc chờ tự thử lại vẫn giữ cờ đang nạp ⇒ không nạp chồng. Kéo làm mới / áp bộ lọc xoá lỗi.
- **Nút chọn loại ở ngăn kéo Chọn nguồn** (`ExtensionKindMenuButton`): nút tròn 40 × 40 chỉ có icon 17pt nửa đậm của loại đang chọn (cỡ không đổi theo tên loại); tên loại nằm trong menu (✓) và nhãn VoiceOver.
- **Màu nhấn tuỳ chọn** (`AppAccentColor`, mới — Xanh ngọc mặc định, Xanh dương, Cam hổ phách, Chàm; bỏ trắng): Cài đặt › Chung › Giao diện thêm hàng "Màu nhấn" (chấm màu + tên) mở `AccentColorSettingsView` (mới — bốn màu + ô xem trước nền tối / nền sáng bằng thành phần thật như mockup). Áp bằng `.appAccentTint()` (mới, `.tint` + `.accentColor`, đọc `@AppStorage` ⇒ chọn là đổi ngay) ở `MainTabView` (thay `.tint(.white)`) và gốc các cửa sổ / màn mở bằng UIKit không thừa hưởng tint: ngăn kéo `…`, widget TTS + sheet cài đặt / hẹn giờ, Thông báo của hub, trình duyệt / mã xác minh Legado, AI, trình phát video. Phần UIKit đổi qua `applyToWindows()` (gán `tintColor` mọi cửa sổ) khi modifier hiện ra và khi đổi màu.
- **Theo màu nhấn**: công tắc (bỏ `SwitchToggleStyle(tint: Color(white: 0.35))` ở 31 chỗ, người dùng chọn); gỡ `.tint(.white)` cục bộ ở các màn TTS / VieNeu / Nghi, thanh trượt, thanh tiến độ; trạng thái đang chọn đang tô trắng cứng sang kiểu chip của `ExtensionKindFilterBar` (tab Kệ/Lịch sử, tab danh mục Khám phá, tab Chi tiết/Mục lục, nhóm + ô tập đang xem ở lưới tập video, nút hẹn giờ TTS, "Áp dụng" của sheet Bộ lọc, dấu ✓ của vài màn chọn); chấm báo (Thông báo, nút lọc); `.appFilled` mặc định màu nhấn (chữ trắng như mockup).
- **Giữ trắng**: comic, trình phát video (thanh tua, icon cố định `Color.white`), chữ / vòng xoay trên ảnh, `AppLoadingView`, lớp phủ tối của Reader. Vòng xoay ở `ReaderHeaderFooterOverlayView` theo màu chữ của theme (trước vô hình ở nền Sáng).
- **Luật `WHITE_TINT_FILL` giữ nguyên** (người dùng chọn), chỉ sửa lý do trong `check_architecture.py`, `rules.md`, `CLAUDE.md` / `AGENTS.md` (mục màu nhấn viết lại) và chú thích code từng nói "màu nhấn trắng".
- Chuyển entry `[1.3.648]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code + diff; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy — cần thử: vòng xoay hiện ở mọi lần nạp trang kế (cả kiểu Danh sách), "Thử lại" sau lỗi, đổi màu ở Cài đặt là cả app + cửa sổ nổi + menu/hộp thoại UIKit đổi ngay, công tắc trong widget TTS, chữ trắng trên nút đặc Xanh ngọc có đủ rõ.

## [1.3.677] - 2026-11-03

### fix: ngăn kéo chọn nguồn chọn loại bằng menu, icon lọc hình phễu, ô tìm và tên tab ở Kho tiện ích

Người dùng (sau 1.3.675–676): *"nút nsfw ngang với title chọn nguồn; thêm nút select để chọn tất cả, truyện chữ, truyện tranh, phim … bên cạnh ô tìm kiếm; bỏ thanh chọn … vì kéo scroll đang xung đột với vuốt đóng; dùng icon bộ lọc khác … giống y như mockup; sheet bộ lọc … nút reset … giảm size nút áp dụng"*; thêm *"áp dụng cho nút lọc của kho tiện ích luôn, đồng bộ nút search của tìm kiếm chương cho cả kho tiện ích và legado; đổi tên 2 tab con … tiện ích freebook và tiện ích legado"*. Chốt bằng mockup rồi duyệt plan.

- **Ngăn kéo chọn nguồn**: viên NSFW (`ExtensionNsfwToggle`, mới) lên dòng tiêu đề "Chọn nguồn" — `SideDrawerMenu` thêm tham số `titleAccessory` (mặc định không có, menu ⋯ khác không đổi). Bỏ hàng chip loại (kéo cuộn ngang tranh với vuốt đóng); cạnh ô tìm là nút chọn loại dạng menu `ExtensionKindMenuButton` (mới: viên thuốc 40pt icon + tên + ↕; Tất cả · Truyện chữ · Truyện tranh · Phim, ✓ ở mục đang chọn; vẫn khoá `discoveryKindFilter`).
- **Icon lọc hình phễu**: asset vector `TablerFilter` (Tabler Icons `filter`, MIT — `Docs/ThirdParty/Tabler-Icons-LICENSE.txt`), `AppGlyph.filter`; phần vẽ dùng chung `FilterGlyph` (mới — tròn / thanh tiêu đề / cạnh ô tìm, chấm trắng khi đang lọc). Dùng cho nút lọc tiện ích (Khám phá, danh sách thể loại, màn Tìm) và nút lọc của Kho tiện ích (thay `line.3.horizontal.decrease.circle` tô cam).
- **Sheet Bộ lọc**: header chỉ còn "Áp dụng" nhỏ (viên thuốc 28pt, chữ 13pt — người dùng yêu cầu, nhỏ hơn nút chữ header chuẩn 17pt); ↺ Đặt lại nằm trong khung, cùng hàng tiêu đề mục đầu ("Sắp xếp") qua `ExtensionConfigFieldRow.labelAccessory` (mới, màn Cấu hình không dùng); mục đầu không phải ô chọn ⇒ ↺ đứng riêng ở đầu khung.
- **Kho tiện ích**: hai tab đổi tên "Tiện ích FreeBook" · "Tiện ích Legado" (cả tiêu đề ngăn kéo ⋯). Ô tìm của cả hai tab thành viên thuốc kiểu mục lục `ChapterTOCSearchField` ("Tìm kiếm N tiện ích" / "Tìm kiếm N nguồn"), cách tìm giữ nguyên. `ChapterTOCSearchField` tắt tự sửa chính tả.
- Chuyển entry `[1.3.647]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code + diff; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy — cần thử: menu chọn loại mở được trong ngăn kéo (cửa sổ nổi riêng), vuốt đóng ngăn kéo không còn vướng, icon phễu hiện đúng (asset SVG), ↺ cùng hàng "Sắp xếp".

## [1.3.676] - 2026-11-03

### fix: nút lọc không nháy mất khi vừa áp dụng bộ lọc

Tiếp 1.3.675 (rà lại sau khi CI xanh).

- **`ExtensionFilterCatalog.info(for:)`**: khoá tra gồm cả `configJson`, nên mỗi lần áp dụng bộ lọc hoặc màn Cấu hình tự lưu thì khoá mới chưa có ⇒ trả `nil` ⇒ nút lọc biến mất một nhịp, cụm nút tròn của header Khám phá xô sang trái rồi về. Giờ trong lúc đọc bộ mới vẫn trả bộ cũ của cùng tiện ích; lần đầu (chưa có bộ nào) vẫn ẩn tới khi đọc xong.
- Chuyển entry `[1.3.646]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.675] - 2026-11-03

### fix: bộ lọc tiện ích ở mọi màn danh sách, ngăn kéo chọn nguồn và ô tìm thể loại

Người dùng: *"sửa lại ext qidian… dùng config của ext select để làm bộ lọc… thêm ô tìm kiếm cho genres… thêm biểu tượng lọc ngoài màn hình nếu config có kiểu select, bool, list"*; thêm *"hiển thị nút bộ lọc ở tất cả màn hình danh sách"*; chốt từng nhánh qua grill-me + mockup rồi duyệt plan. Tiện ích qidian (bộ lọc STV, home thể loại, genre nhãn) sửa ở repo tiện ích riêng.

- **Nút lọc** (`ExtensionFilterButton`, mới): chỉ hiện khi `config` của tiện ích có mục `select` / công tắc (cả bool trần) / `list`; chấm trắng khi khác mặc định. Đọc `plugin.json` ở luồng nền một lần cho mỗi (tiện ích, phiên bản, `configJson`) qua `ExtensionFilterCatalog` (`@MainActor @Observable`), `body` chỉ tra bảng. Ba chỗ: header Khám phá (nút tròn 38 trước ⋯, mọi tab home/nhãn/Trang chủ), trang danh sách thể loại/nhãn `CategoryNovelsListView` (cặp với Kiểu hiển thị trong một `ToolbarItem`, cả khi mở từ Chi tiết), màn Tìm khi tìm trong một nguồn (thay chỗ nút "Tìm").
- **Sheet Bộ lọc** (`ExtensionFilterSheet`, mới): mọi mục lọc theo thứ tự `plugin.json`, dùng lại dòng của màn Cấu hình. Sửa trên bản nháp; ↺ về mặc định; "Áp dụng" **lưu vĩnh viễn** qua `ExtensionTransactionCoordinator.saveExtensionConfig` — đọc config mới nhất, chỉ thay khoá lọc; vuốt đóng khi chưa áp dụng thì hỏi (`confirmDiscardOnSwipe`).
- **Tải lại sau khi áp dụng** (kể cả đang ở trang 2+): Khám phá dùng `reloadAfterConfigChangeIfPending()` khi sheet đóng (tab đang xem giữ, về trang 1, neo cuộn bị xoá); danh sách thể loại gọi `PaginatedNovelLoader.reset(configJson:)` (mới — config là `var`, bộ đếm lượt bỏ trang cũ về muộn và lượt tự thử lại đã hẹn); màn Tìm tìm lại bằng bản tiện ích mới nhất (`selectedExtension` là bản chụp có config cũ).
- **Màn Cấu hình tách phần dùng chung**: `ExtensionConfigSchema` (mới — đọc `config` theo thứ tự, mục ở gốc, `support_url`, giá trị ban đầu, dựng `configJson`, `filterKeys`) và `ExtensionConfigFieldRow` (mới — 5 dáng dòng chuyển từ `+GlobalConfig`). Hành vi màn Cấu hình giữ nguyên; `plugin.json` hỏng vẫn báo lỗi.
- **Header Khám phá + ngăn kéo chọn nguồn**: nút tròn icon tiện ích + tên và link hai dòng (`DiscoverySourceHeaderButton`, mới); bấm nút hay vùng chữ đều mở ngăn kéo **trượt từ trái** (`DiscoverySourcePickerModifier`, mới) thay sheet chọn nguồn: ô tìm viên thuốc, NSFW, chip loại, hàng nguồn với ⚙/ⓘ và 📌. Sheet Cấu hình / Chi tiết nguồn Legado chuyển về màn Khám phá. `SideDrawerMenu` thêm tham số `edge` (mặc định phải; panel, nền kính, vuốt đóng theo mép).
- **Ô tìm kiểu mục lục**: `ChapterTOCSearchField` thêm `onSubmit`/`onClear` tuỳ chọn. Màn Tìm bỏ nút "Tìm" (bấm Tìm trên bàn phím). Tab nhãn Khám phá có ô "Tìm kiếm N thể loại": lọc ngay khi gõ, khớp tên gốc lẫn tên đã dịch, bỏ dấu, "đ" ≈ "d"; thanh tab ẩn theo bàn phím.
- Chuyển entry `[1.3.645]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code + diff; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy — cần thử: gõ phím trong ngăn kéo chọn nguồn (cửa sổ nổi riêng); qidian bản 25: nút lọc hiện ở Khám phá, chọn "Lượt đọc tuần" + "> 500" rồi Áp dụng thì tab đang xem tải lại từ đầu; tìm "hệ thống" ở tab nhãn.

## [1.3.674] - 2026-11-01

### fix: danh sách kho thành trang con, tự kiểm tra cập nhật tiện ích

Người dùng: *"cho màn hình danh sách kho thành màn hình con của tất cả tiện ích. Khi vào tất cả tiên ích hãy tự chạy kiểm tra cập nhật của tất cả ext"*; duyệt plan: lối vào nằm trong ngăn kéo …, giãn cách 5 phút.

- **Trang con Danh sách kho** (`ExtensionRepositoryListView`, mới): ô chọn của tab Kho tiện ích còn hai mục Tất cả tiện ích · Nguồn Legado (giữ tag 0/2). Hàng "Danh sách kho" (chữ phụ = số kho) đứng đầu ngăn kéo … của Tất cả tiện ích ⇒ đẩy trang `.backPageTitle`, phủ thanh tab. Header giữ cụm ↻ | +; xoá kho, trang trống + nút nhập kho mặc định như cũ. Bỏ lối vào cũ.
- **Tự kiểm tra cập nhật** (`ExtensionUpdateCheckCoordinator`, mới, `@MainActor @Observable`): kiểm tra = tải lại registry của mọi kho (1 request/kho, song song, tối đa 20 s/kho, bỏ cache URLSession cục bộ) rồi `saveRegistry` ⇒ `hasUpdate` và banner "Cập nhật tất cả" tự đổi. Chạy khi vào tab Kho tiện ích lúc đang ở Tất cả tiện ích, hoặc khi chuyển ô chọn từ Legado sang. Giãn cách 5 phút, giữ trong RAM (mở lại app ⇒ kiểm tra ngay lần đầu vào), chỉ tính lượt tải được ít nhất một kho; kho chưa có cache vẫn được tải trong giãn cách. ↻ / "Thử lại" bỏ qua giãn cách. Chỉ kiểm tra, không tự cài; nguồn Legado ngoài phạm vi. Bỏ `RepositoryRefreshPolicy` (cửa 6 tiếng nên gần như không bao giờ tự chạy); `rules.md` mục 7 cập nhật theo.
- **Một cờ bận chung** (`isBusy`): kiểm tra, thêm kho, xoá kho cùng đọc ⇒ không chạy trùng. Sửa lỗi cũ: thêm kho trong lúc làm mới hạ cờ `isRefreshingAll` giữa chừng ⇒ mở lại nút xoá kho, cho lượt làm mới thứ hai chạy.
- **Hiển thị** (`ExtensionUpdateCheckStatusLine`, mới): dòng nhỏ dưới "Đang hiển thị N tiện ích" — vòng quay "Đang kiểm tra cập nhật…"; xong "Đã kiểm tra cập nhật lúc HH:mm"; lỗi chữ cam "Không kiểm tra được cập nhật" / "Không tải được f/t kho" + "Thử lại". Cache cũ giữ nguyên, không toast, không alert. Trang Danh sách kho dùng cùng dòng. Thông báo của "Cập nhật tất cả", Import zip và tự thêm kho mặc định giờ hiện ở tab Tất cả tiện ích (trước chỉ hiện ở tab kho).
- **Back từ trang Danh sách kho**: gốc nhận lại `onAppear` ⇒ bỏ qua đúng một lần (không dọn, không kiểm tra, không tự thêm lại kho mặc định vừa bị xoá hết).
- `RepositoryManagerView.swift` 603 → 508 dòng.
- Chuyển entry `[1.3.644]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code + diff; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy — cần thử: vào tab Kho tiện ích thấy "Đang kiểm tra cập nhật…" rồi giờ kiểm tra; tắt mạng thấy chữ cam + "Thử lại"; ngăn kéo … → Danh sách kho → back thì không chạy lại.

## [1.3.673] - 2026-11-01

### fix: tiện ích JS cài an toàn, tìm kiếm tải thêm, cookie của nguồn

Người dùng nhờ điều tra tiện ích JS nào FreeBook chưa dùng được (báo cáo 33 mục); chọn "Lập plan mục 1–3", duyệt cả 3 kể cả nút trang đăng nhập.

- **Cài/cập nhật an toàn** (`ExtensionPackageInstaller`, mới): giải nén + giải mã ở thư mục tạm, thành công mới đổi chỗ vào `extensions/<packageId>/` (bản cũ dời sang tmp, chuyển bản mới lỗi thì trả bản cũ về). Trước đây `install(item:)` xoá bản đang chạy rồi mới giải mã ⇒ gói không giải được làm mất bản cũ; cài mới lỗi để lại thư mục dở; nhập zip xoá bản cũ trước khi chuyển. Giữ nguyên hình dạng `localPath` (zip bọc thư mục con vẫn trỏ thư mục con). `ExtensionManager.findMainExtensionFolder` thành `ExtensionPackageInstaller.findMainFolder`.
- **Định dạng mã hoá mới**: 14/93 gói của kho chính thức (wikidich, wattpad, mangadex, metruyenchu-app, allshorts…) có ciphertext mở đầu `a7 e4 1d 02`; app chưa giải được (thử AES-GCM/ChaCha20/CTR với khoá cũ đều không khớp — UNKNOWN). `ExtensionScriptDecoder` nhận ra ngay sau Base64, **trước** bước kiểm độ dài (4 file dài đúng bội 16 từng rơi xuống CBC rồi báo nhầm "source/author bị sửa"), ném lỗi riêng (`isUnsupportedFormat`). Màn Quản lý tiện ích báo "<tên> dùng định dạng mã hoá mới, FreeBook chưa đọc được." kèm "Bản đang cài vẫn giữ nguyên."; "Cập nhật tất cả" gom lỗi, báo "Đã cập nhật N/M tiện ích." (trước luôn báo xong, lỗi của tiện ích trước bị xoá). Máy đã bấm cập nhật trước bản này thì bản cũ đã mất.
- **Tìm kiếm tải thêm trang** (tìm trên một nguồn): `ExtensionManager+Search` (mới) có `searchPage` trả token trang kế — đọc `next` của object script trả về, thiếu thì `Response.nextPage`; `search(page:)` cũ thành vỏ cho bộ kiểm tra, tìm nhiều nguồn, bộ nghiệm thu. Trang 1 vẫn gửi `"1"`, trang sau gửi nguyên token. `SourceRuntime.searchPage`: nguồn Legado có trang kế khi `searchUrl` có chỗ cắm số trang và trang có kết quả. Màn Tìm (`SearchView+Paging`, `SearchPagingState`): tự nạp khi một trong 5 mục cuối hoặc sentinel cuối hiện ra (lưới `.id(count)`), không có nút "Xem thêm"; dừng khi token rỗng/trùng token vừa dùng, trang không thêm link mới, hoặc đủ 50 trang; lỗi trang sau tự thử lại 3 lần cách 2 s rồi dừng im lặng; tìm lại thì huỷ lượt tải thêm cũ. Tìm nhiều nguồn vẫn chỉ trang 1.
- **Cookie của nguồn**: `ExtensionCookieSync` (mới) chép cookie WebKit (nơi người dùng đăng nhập) sang `HTTPCookieStorage.shared` cho tên miền `source` ở đầu mỗi `JSExecutor.callAsync` (phủ cả runtime TTS). Rẻ nhờ `WKHTTPCookieStoreObserver` + bộ đếm thế hệ: WebKit không đổi ⇒ một lần khoá, không nhảy main. Chỉ chép cookie còn thiếu hoặc vừa đổi bên WebKit (dấu SHA-256 trong `UserDefaults`, không lưu giá trị) để không đè cookie `Set-Cookie` mới hơn của `fetch`; app ở nền hoặc WebKit không trả lời sau 2 s ⇒ bỏ lượt. `localCookie` (`JSExecutor+Cookie`, mới) đọc/ghi kho thật: `getCookie(url?)`; `setCookie` nhận dòng Set-Cookie hoặc danh sách `a=1; b=2`. `fetch` trả header thật đã gửi (gồm `Cookie` tính lúc gửi) ⇒ `response.request.headers` thêm khoá chữ thường (`.cookie`), kể cả khi qua browser ẩn. `WebKitCookieBridge` ghi dấu cho cookie chép từ "Mở link lỗi".
- **Trang đăng nhập** (`ExtensionConfigView+SupportLink`, mới): `support_url` là URL http(s) (trong `config` hoặc ở gốc) ⇒ dòng "Mở trang đăng nhập" thay ô chữ, mở `BypassWebView`; đóng ⇒ chép cookie ngay (WebKit thắng). Hưởng lợi: tiktok-tts, metruyenchu/vtruyen (phần cần đăng nhập), koanchay.
- **Không làm**: giải mã định dạng mới; trang sau của tìm nhiều nguồn; ghi header `Cookie` do script tự truyền vào kho; chiều URLSession → WebKit. Lưu ý: tiện ích có `source` thuộc google.com giờ nhận cookie đăng nhập Google — tắt bằng "Xử lý cookie hệ thống".
- Chuyển entry `[1.3.643]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code + diff; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy — cần thử: cập nhật một gói định dạng mới thì báo rõ và bản cũ vẫn chạy; tìm một nguồn rồi cuộn xuống thấy trang 2; tiktok-tts đăng nhập qua "Mở trang đăng nhập" rồi đọc được.

## [1.3.672] - 2026-11-01

### fix: cấu hình tiện ích hiện ô chọn select và danh sách list

Người dùng: *"bạn hãy đọc ext qimao của đường đen. trong đó có config dạng select. app chưa đọc được dạng đó"*; thêm các mục còn thiếu theo hợp đồng (từ phiên rà màn Cấu hình), *"đừng làm mode database"*; duyệt plan, chưa áp `thread_num`/`delay`/`ignore` làm giới hạn.

- **Tiện ích**: Qimao của Đường đen (repo GitHub của tài khoản `duongden`, `Novel_Zh/qimao` v37 có 6 mục `select`; bản Phim ngắn v7 có 1). Script (mã hoá) đọc biến global `CONFIG_*`, rồi `localConfig.getItem`, và so đúng chữ của lựa chọn.
- **Nguyên nhân**: `ExtensionConfigView.ConfigItem` decode bằng `JSONDecoder` chỉ 4 trường `title/mode/format/default`, bỏ `values`/`subtitle` ⇒ `select` rơi vào nhánh ô chữ. Phần tiêm giá trị chọn vào script vốn đúng.
- **`select`**: nút menu rộng hết dòng dưới tiêu đề, ✓ ở lựa chọn đang hiện (kiểu ô chọn của form đăng nhập Legado), chọn là lưu ngay, luôn lưu chuỗi. Mọi `format` đều là chọn **một**: hợp đồng bản đầu có `single`/`multiple` (chọn nhiều, nối dấu phẩy), bản hiện tại bỏ `multiple`; khảo sát ~800 `plugin.json` ở 8 kho: `single` 42, bỏ trống 17, `text` 2, `multiple` 0. Giá trị không có trong `values` hiện lựa chọn đầu (hợp đồng), không tự ghi đè.
- **`ConfigItem`** dựng tay từ dict: `default`/`values` là số/bool ⇒ ép chuỗi thay vì mất cả dòng. **`subtitle`** hiện ở mọi dòng có khai.
- **`list`** (mới, `ExtensionConfigListEditor`): dòng hiện số mục, chạm mở trang thêm (nút `+` nổi)/sửa/xoá từng dòng; giá trị là chuỗi JSON `"[\"a\",\"b\"]"`. Giá trị cũ không phải mảng JSON ⇒ một dòng; `default` viết thành mảng thật vẫn hiện (hợp đồng nói hiện rỗng — cố ý khác vì script cũng nhận nó).
- **Thứ tự mục** theo `plugin.json` (đọc lại bằng `LegadoEngineJSONParser` giữ thứ tự). `ExtensionScriptDecoder.clearEncryptFlag` giờ chỉ sửa đúng chữ `"encrypt": true` (trước ghi lại cả file `.sortedKeys` ⇒ tiện ích mã hoá mất thứ tự). Bản đã cài trước bản này phải cài lại mới có thứ tự gốc.
- **Khoá kết nối** `thread_num`/`delay`/`ignore` viết dạng giá trị trần: ẩn khỏi màn Cấu hình (hợp đồng: là giới hạn, không phải cài đặt), vẫn tiêm vào script; giá trị cũ người dùng đã sửa bị bỏ ở lượt lưu kế tiếp. Chưa áp làm giới hạn tải/lịch sử. Giá trị trần khác (`max_length`, `preload_size`…) vẫn sửa được.
- **Script nhận chuỗi**: `JSExecutor.injectGlobals` đổi mọi giá trị sang chuỗi trước khi đưa vào JS (biến global + `localConfig.getItem`) qua `ExtensionConfigValueFormatter` (mới) — bool ⇒ `"true"`/`"false"`, số ⇒ `"3000"`, mảng ⇒ JSON, `null` ⇒ `""`. `injectedConfigs` của Swift giữ kiểu gốc; cách lưu `configJson` không đổi. Script cũ dùng `if (X)` với bool sẽ thấy `"false"` là đúng.
- **Khám phá** tải lại `home`/`genre` khi `configJson` của nguồn đang xem đổi — chờ sheet chọn nguồn (nơi mở Cấu hình) đóng, hoặc lúc màn hiện lại nếu sửa từ tab Tiện ích; không tải lại sau mỗi lượt tự lưu của ô chữ (gọi nguồn dồn dập, tên miền gõ dở). Tab danh mục và trang `explore` dựng lại bộ nạp (`.id` theo mốc tải lại vì config).
- **Không làm**: `mode: "database"` (giữ như cũ — ô chữ), `config.js` động, `actions`, `format` `password`/`multiline` (mỗi kiểu 1 tiện ích dùng), áp giới hạn kết nối.
- **Kiểm chứng**: đọc code + diff; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy — cần thử: cài lại Qimao, màn Cấu hình hiện 6 ô chọn đúng thứ tác giả, đổi "Nhóm nội dung" rồi đóng sheet thấy Khám phá đổi; tiện ích AI có `api_key` dạng `list` thêm/xoá được dòng.

## [1.3.671] - 2026-11-01

### fix: tìm nhiều nguồn chừa luồng cho TTS khi đang phát

Người dùng: *"Tìm nhiều nguồn làm đơ google tts, nên ưu tiên để dư 1 luồng cho tts"*; chọn "A trước, B sau", duyệt plan.

- **Nguyên nhân**: "Tìm trên tất cả nguồn" chạy mọi tiện ích JS cùng lúc, không giới hạn. Script chạy **đồng bộ** trên cooperative pool (`JSExecutor.callAsync` → `runner.call`), `fetch` chờ bằng semaphore tới 15 s ⇒ quá ~6 nguồn là pool (≈ số lõi) bị chiếm hết. Google TTS cần chính pool đó ở mọi bước (`TTSAudioSynthesisWorker` → `RemoteTTSSynthesisCoordinator` → `URLSession` async) ⇒ hết đoạn nạp trước là đơ. Không phải main thread; không phải giới hạn kết nối của URLSession (Google TTS khác tên miền với nguồn). Đúng chẩn đoán #1 của plan perf 2026-10-09 (bản sửa đang chờ số đo).
- **Sửa (A)**: `SearchTTSThreadReservePolicy` (mới): TTS đang phát (mọi engine) ⇒ nguồn JS chạy cùng lúc tối đa `số lõi − 1 − (lời gọi JS khác đang chạy)`, tối thiểu 1; TTS không phát ⇒ không giới hạn như cũ. `LegadoSearchScheduler.searchAll` đưa nguồn JS vào cửa sổ trượt, tính lại giới hạn mỗi khi một nguồn JS xong (TTS dừng giữa lượt ⇒ nguồn còn chờ chạy hết); `shouldStart` (NSFW) xét cả nguồn JS đang chờ. Nguồn Legado giữ cửa sổ 8. `JSExecutionTelemetry.inFlightCount` đọc bộ đếm có sẵn. Không đụng tải truyện.
- **Log** (phải bật ghi log): `[SearchPerf] JSCap sources= cap= jsInFlight= cores= ttsPlaying=1` (một lần khi giới hạn có tác dụng), `[SearchPerf] JSDone sources= peak= ms= cancelled=`; `[TTSPerf] RemoteWait priority= engine= waitMs= queueMs= runMs= outcome= jsInFlight= cores=` (đoạn đang đọc chờ ≥ 400 ms hoặc một lượt chạy ≥ 2 s; `queueMs`/`runMs` lớn kèm `jsInFlight` gần `cores` = đói thread, không phải mạng chậm).
- **Giới hạn**: đang nghe mà tìm thì kết quả về chậm hơn; tải truyện/nạp chương đã chiếm gần hết pool thì tìm chỉ còn 1 nguồn và TTS vẫn có thể chậm; TTS bắt đầu sau khi bấm tìm thì nguồn đã chạy không bị giới hạn. Cách tận gốc (B: đưa JS ra khỏi pool, plan perf §1.4) để làm sau.
- `rules.md` (Tìm mọi nguồn) ghi luật mới và sửa nhận định sai "nằm trong actor ⇒ không chặn pool" (`BookDownloadWorker`, `ExtTTSRuntime` là actor mặc định, vẫn chạy trên pool). Chuyển entry `[1.3.641]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code + diff; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy — cần thử: nghe Google TTS rồi tìm tất cả nguồn, giọng không đơ và log có `JSCap`; tìm khi không nghe vẫn chạy hết cùng lúc như cũ.

## [1.3.670] - 2026-11-01

### fix: trình duyệt Legado dùng chung profile với trình duyệt của app

Người dùng: *"vì sao bạn làm trình duyệt đăng nhập của legado có profile khác trình duyệt chung vậy"*; duyệt "dùng chung".

- **Nguyên nhân**: `LegadoBrowserController` (trình duyệt hiện cho người dùng của nguồn Legado: đăng nhập web §10.2, `java.startBrowser*` §10.8) tạo `WKWebsiteDataStore.nonPersistent()` **mới mỗi lần mở** (chọn từ đợt 2 Legado, 4d69a023, để cookie không lẫn sang nơi khác — spec không bắt buộc). Trình duyệt của app, browser tiện ích JS và WebView ẩn của Legado (`LegadoWebViewFetcher` qua `WebViewLoader`) đều dùng kho mặc định ⇒ đăng nhập Google/GitHub, cookie qua Cloudflare không sang được; `localStorage` của trang mất sau mỗi lần đóng.
- **Sửa**: kho `.default()`. Giữ nguyên đồng bộ hai chiều với kho cookie của nguồn (gieo khi mở, đọc cookie các tên miền đã ghé khi đóng) — giống WebView ẩn của Legado vốn đã làm trên kho mặc định.
- **Đăng xuất** (`LegadoLoginService.logout`): thêm xoá cookie WebKit của tên miền nguồn (`baseURL` + URL đăng nhập web) qua `WebKitCookieBridge.removeCookies(forHosts:)` mới — cookie áp cho host (của host hoặc tên miền cha) và cookie của tên miền con. Không xoá thì lần mở sau đọc lại phiên cũ vào kho của nguồn. Tên miền khác đã ghé (Google, GitHub khi đăng nhập OAuth) **không** bị xoá. `localStorage` của trang không xoá.
- **Hệ quả**: cookie của nguồn Legado thấy được trong trình duyệt của app; đăng xuất nguồn cũng đăng xuất tên miền đó trong trình duyệt của app. Gieo cookie khi mở vẫn ghi đè cookie trùng tên/tên miền đang có trong kho WebKit (như WebView ẩn).
- Chuyển entry `[1.3.640]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy — cần thử: đăng nhập Google ở trình duyệt của app rồi mở "Đăng nhập trên web" của một nguồn Legado thấy vẫn còn phiên Google; đóng mở lại trình duyệt Legado vẫn còn đăng nhập; Đăng xuất nguồn rồi mở lại thì trang nguồn không còn đăng nhập.

## [1.3.669] - 2026-11-01

### fix: giữ dòng dừng lọc name và điểm tiếp nối khi đổi nguồn

Người dùng: *"Dòng Đã dừng lọc name ở ch.240: Chương 256: Võ đạo đường rẽ cùng mới cảnh giới. Bị mất khi chuyển nguồn truyện"*; chọn "giữ nguyên chỉ số", duyệt plan.

- **Nguyên nhân 1 — mở nhầm phiên**: dòng dừng là một tin trong phiên chat AI. Đổi nguồn tạo `bookId` mới (UUID); `AIChatHistoryStore.migrateSessions` có chép phiên nhưng gán `updatedAt = Date()` lần lượt theo thứ tự mới → cũ ⇒ phiên cũ nhất nhận mốc mới nhất, thứ tự bị đảo. Màn AI của truyện mới (chưa có `lastSessionIds`) mở `summaries.first` = phiên **cũ nhất** ⇒ dòng dừng trông như mất. Phiên chép sang còn giữ `session.bookId` cũ (`let`) ⇒ `condenseHistoricalMessages` lưu nhầm về thư mục của truyện cũ, xoá phiên ở Cài đặt trỏ nhầm thư mục.
- **Sửa**: `migrateSessions` dựng lại phiên với `bookId` mới, giữ `id`, `createdAt`, `updatedAt`. `AIRuntimeCoordinator.migrateLastSession(from:to:)` chuyển phiên lượt gần nhất đã dùng (RAM), gọi từ `SearchView.executeSourceChange`. `condenseHistoricalMessages` lưu theo `bookId` của màn (đỡ cho phiên đã chép trước bản này).
- **Nguyên nhân 2 — mất điểm tiếp nối**: `AINameScanScopeStore` (điểm tiếp nối + lựa chọn "từ chương đang đọc", UserDefaults theo `bookId`) không được chép ⇒ sheet quét mất dòng "Tiếp nối lần quét trước". **Sửa**: `AINameScanScopeStore.migrate(from:to:keepingOld:)` gọi trong `BookSourceMigrator.migrateMetadataAndSettings`; **giữ nguyên chỉ số** (người dùng chọn) vì chương đã tải được chép sang theo vị trí — chỉ số cũ vẫn trỏ ngay sau phần nội dung đã quét. Đang phát TTS truyện cũ thì giữ bản của truyện cũ (như cấu hình dịch).
- **Truyện đã đổi nguồn trước bản này**: không tự khôi phục — thứ tự phiên đã lưu bị đảo, điểm tiếp nối nằm ở id cũ không còn ánh xạ. Dòng dừng vẫn có trong danh sách phiên; quét tiếp bằng "Chọn chương…".
- **Chưa làm**: kết quả AI chưa xem trên hub (`AIUnseenResultStore`), nút "Thử lại k lượt lỗi" (chỉ trong RAM), lượt quét đang chạy lúc đổi nguồn vẫn ghi vào id cũ; chép chương đã tải theo vị trí (có từ trước) có thể lệch tên/nội dung khi hai mục lục khác nhau.
- `rules.md` thêm luật dữ liệu AI theo truyện phải đi theo khi đổi nguồn. Chuyển entry `[1.3.639]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code + diff; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy — cần thử: dừng lọc name → đổi nguồn → mở AI của truyện mới thấy đúng phiên có dòng dừng; sheet quét có "Tiếp nối lần quét trước" và quét tiếp được trên nguồn mới.

## [1.3.668] - 2026-10-31

### fix: thanh tab tự vẽ trong trang gốc, back về không giật

Người dùng: *"bạn làm màn hình trong full xấu quá, khi từ màn hình full về trang đầu có thanh tab thì cảm giác bị giật màn hình khi hiển thị lại thanh tab. Tham khảo cách hiển thị của reader"*; chọn "thanh tab tự vẽ", duyệt plan.

- **Nguyên nhân**: 1.3.660 ẩn thanh tab hệ thống ở trang đẩy vào bằng `.toolbar(.hidden, for: .tabBar)` (đổi theo kiểu tiêu đề). Lúc back, SwiftUI hiện thanh lại **trễ** hơn trang gốc ⇒ trang gốc co lại một nhịp — đúng lỗi Reader từng gặp (b12ddee7, sửa bằng `fullScreenCover`: cover phủ cả thanh nên thanh không bao giờ ẩn/hiện).
- **Thanh tab tự vẽ** (`MainTabBar`, mới, `Views/Common/MainTabBar/`): 4 mục icon + chữ (danh sách `items` dùng chung với `.tabItem` của `MainTabView`), mục đang chọn theo `.tint` (trắng), mục khác xám, nền `.bar` + vạch mảnh phía trên, cao 49pt, nền kéo xuống vùng home indicator; badge đỏ số truyện có chương mới ở Kệ Sách (chuyển từ `.badge` của `MainTabView`, bỏ `@ObservedObject newChapters` ở đó).
- **`.mainTabBar()`** (`MainTabBarModifier`, mới): ẩn thanh hệ thống + `safeAreaInset(edge: .bottom)` đặt `MainTabBar` vào nội dung trang gốc **bên trong** `NavigationStack` ⇒ trang đẩy vào phủ lên thanh, back/vuốt mép thì thanh trượt về cùng trang gốc. Tab đang chọn đi qua environment `mainTabSelection` (`MainTabView` truyền `$selectedTab`). `hidesWithKeyboard: true` chỉ ở tab Tiện ích (trang gốc có ô tìm): bàn phím hiện ⇒ bỏ thanh, ẩn ⇒ hiện lại; chỉ nghe khi trang gốc đang hiện và trả thanh về lúc bị trang đẩy vào che (bàn phím của trang con không được làm thanh hiện lại giữa nhịp back). Gắn ở 4 trang gốc: `ShelfView`, `DiscoveryView`, `RepositoryManagerView`, `SettingsView` (nút "+" nổi của Kệ tự nằm trên thanh).
- **Thanh hệ thống luôn ẩn**: `PageTitleModifier` ẩn ở **mọi** kiểu (không còn đổi theo trang); `MainTabView` ẩn thêm ở từng tab (ngoài `NavigationStack`) làm chốt chặn cho trang đẩy vào thiếu modifier tiêu đề. Giữ `TabView` + `.tag` + `.tabItem` để `MainTabView+TabReset` vẫn thấy đủ 4 tab. Cập nhật luật ở mục header của `CLAUDE.md`/`AGENTS.md`.
- Chuyển entry `[1.3.638]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. CI là cổng biên dịch; chưa thử trên máy (để ý: thanh tab hệ thống có còn lộ ra ở trang nào không; đẩy/back/vuốt mép có còn giật không; cỡ icon/chữ/badge so với thanh cũ).

## [1.3.667] - 2026-10-31

### feat: bỏ chạm 1/3 hai bên và vuốt ngang để đổi chương

Người dùng: *"bỏ chạm 1/3 trái phải để chuyển chương giúp tôi"* — chọn bỏ ở cả Reader lẫn truyện tranh; comic chỉ đổi chương bằng nút/mục lục (bỏ luôn vuốt ngang), chạm ảnh ở đâu cũng bật/tắt thanh, bỏ nút "…", cuối chương *"không có gì"*. Đảo phần chạm hai bên của 1.3.643 và vuốt ngang của 1.3.613.

- **Truyện tranh**: xoá `ComicChapterNavigationMode` cùng ngăn kéo "Tuỳ chọn đọc" và nút "…" ở thanh trên (thanh trên còn ☰, khung 36×38 vì giờ đứng một mình). `ComicReaderView` bỏ `chapterSwipeGesture`/`handleChapterSwipe`, `handleSingleTap`, `stepChapter` (cùng hai toast chương đầu/mới nhất); chạm ảnh và dòng cuối chương gọi thẳng `toggleChrome()`. `ComicPageView.onSingleTap` thành `() -> Void` (không cần điểm chạm). Đổi chương chỉ còn nút Chương trước/sau ở thanh dưới, mục lục, và nút "Chương tiếp" ở màn chương rỗng (giữ nguyên).
- **Cuối chương comic**: bỏ dòng gợi ý "Chạm bên phải…/Vuốt sang trái…"; còn "Hết chương" (chương cuối thêm "Đây là chương mới nhất"), giữ lề dưới 96 để ảnh cuối không nằm dưới thanh dưới.
- **Reader truyện chữ**: xoá `ReaderEdgeTapDetector` và `handleEdgeTap`; `readerScrollProbes` chỉ còn `ReaderUserScrollDetector` (tắt cuộn theo highlight khi tự kéo lúc TTS đọc — giữ nguyên). Bỏ công tắc "Chạm hai bên để chuyển chương" ở Cài đặt đọc.
- **Giá trị đã lưu**: khoá `comicChapterNavigationMode` và `readerEdgeTapChangesChapter` còn trong `UserDefaults` nhưng không code nào đọc ⇒ không ảnh hưởng, không cần migration.
- CLAUDE.md/AGENTS.md cập nhật mục màn đọc comic. Chuyển entry `[1.3.637]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code + diff, grep sạch các tên đã xoá trong `Sources/`; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy — cần thử: comic chạm ảnh (cả hai bên) chỉ bật/tắt thanh, chạm đúp phóng to, vuốt ngang không đổi chương, nút Chương trước/sau; Reader chạm hai bên không đổi chương, bôi đen và tắt cuộn theo highlight khi TTS đọc như cũ.

## [1.3.666] - 2026-10-31

### feat: thanh dưới trình duyệt gắn sát đáy, nút Import và ⋮ trong thanh

Người dùng: *"mockup lại phần bottom của browser"* → *"cho nó sát dưới luôn đừng làm kiểu lở lửng lên, như vậy nó sẽ che mất nội dung trang"* → *"giữ nguyên các thành phần, thêm import vào nữa"* → *"thay nút dịch bằng nút dropdown nhưng đổi icon còn icon ba chấm dọc"*; duyệt mockup + plan.

- **Thanh dưới gắn sát đáy** (`BypassWebView.browserArea`): `ZStack` (thanh nổi đè trang) → `VStack` trang ở trên, `BrowserBottomBar` ở dưới; trang kết thúc ngay trên thanh, không còn gì che nội dung. Nền thanh tối đặc + vạch mảnh trên, kéo xuống hết vùng vạch Home (`ignoresSafeArea(.container, edges: .bottom)` — bàn phím hiện thì thanh nằm ngay trên bàn phím). Bỏ đo safe area đáy (`bottomSafeInset`), các khoản chừa chỗ (`chromeClearance`, `barBottomPadding`, `importPillClearance`) và cơ chế thụt `contentInset` của `BypassBrowserWebPane` (`bottomObstruction`).
- **Thanh**: lùi, tiến, ô URL (giữ nguyên khiên/tên miền/tải lại), nút **Import**, nút **⋮** (`ellipsis` xoay 90° — SF Symbols không có ba chấm dọc) mở ngăn kéo "Trình duyệt". Đang nhập địa chỉ giữ như cũ (ô giãn hết + "Huỷ").
- **Nút Import** (`BrowserImportButton` mới, thay viên nổi `BrowserImportPill` đã xoá): icon tiện ích đầu tiên khớp URL, ≥ 2 nguồn có số nguồn ở góc; 1 nguồn chạm là import, nhiều nguồn mở bảng chọn nguồn (popover, nút sáng kiểu chip trong lúc mở); giữ cách import **sau** khi popover đóng hẳn. Ẩn khi không khớp nguồn / màn không nhận import / đang nhập địa chỉ. Bỏ theo dõi cuộn của tab (`isScrolledDown`, KVO `contentOffset`) vì chỉ viên nổi dùng để thu gọn.
- **Header**: bỏ nút "…", chỉ còn "Xong".
- **Dịch trang**: nút dịch rời thanh, thành công tắc "Dịch trang" đầu nhóm "Trang này" của ngăn kéo (`SideDrawerToggleRow`, bật/tắt tay cho tab này như nút cũ — `toggleTranslation`, không ghi nhớ; mờ ở Home/trang không phải web). Trang đang dịch ⇒ ô URL có icon dịch nhỏ trước tên miền (`BrowserAddressPill`, cùng chỗ icon ẩn danh).
- **Dải báo**: popup bị chặn nổi ở cuối vùng trang (ngay trên thanh); dải tự dịch giữ ở đầu trang. `BrowserGlassCapsuleBackground` giờ chỉ còn dải tự dịch dùng ⇒ bỏ tham số `usesBarGlass`/`isHighlighted` và nhánh khoá nút nổi.
- Sửa tài liệu chuẩn cụm nút header của 1.3.665 (`HeaderButtonMetrics`, `CLAUDE.md`/`AGENTS.md`, `rules.md`, `.agents/AGENTS.md`): ghi nhầm số 1.3.664 (số đó là CryptoJS) và ví dụ "… | Xong" không còn sau đợt này.
- Chuyển entry `[1.3.636]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code + diff; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy. Rủi ro cần thử: thanh khi bàn phím hiện (ô URL và ô nhập của trang), popover chọn nguồn bật từ nút trong thanh và từ mục ngăn kéo, công tắc "Dịch trang" đổi ngay khi ngăn kéo còn mở, trang Home cuộn tới cuối không bị thanh che.

## [1.3.665] - 2026-10-31

### fix: nút liền nhau trên header đứng sát nhau

Người dùng: *"cho phím dropdown và nút xong gần nhau hơn và nhỏ lại"* (header trình duyệt), rồi *"cái nào có 2 nút gần cũng gom thành group"*, sau đó *"thôi đừng làm group, để cho các nút gần lại là được"*; duyệt plan, chọn **giữ cỡ 17pt** (không thu nhỏ, không viên bao ngoài).

- **`HeaderButtonMetrics`** (mới, `Views/Common/PageHeader/`): `pairSpacing = 2`, `pairIconWidth = 32`, `pairCircleSpacing = 4`. Cụm nút liền nhau trên thanh điều hướng gộp vào **một** `ToolbarItem` chứa `HStack(spacing: pairSpacing)` — để nhiều `ToolbarItem`/`ToolbarItemGroup` thì iOS tự giãn cách, không chỉnh được. Icon giữ 17pt nửa đậm, chỉ khung hẹp 36 → 32 (chiều cao giữ 36/38 như cũ).
- **Thanh điều hướng (5 màn)**: trình duyệt (… | Xong), Trợ lý AI toàn màn (… | ⌄), Kệ (🔍 | …, kính lúp vẫn ẩn ở tab Tải xuống, chấm đỏ thông báo bám icon vì `.frame` đặt sau `.overlay`), Chi tiết truyện (nút dịch | …, `HStack` sẵn có cách 6 → 2), Quản lý tiện ích tab Kho (↻ | +, `ProgressView` lúc làm mới nằm trong khung 32).
- **Header tự dựng (4 chỗ)**: chỉ bọc cặp nút trong `HStack` con, khoảng cách của thanh (nút lùi, tiêu đề) giữ nguyên — màn đọc truyện tranh (☰ | …), trình duyệt Legado (↻ | ✓, nút tròn ✓ giữ 38), Khám phá (hai nút tròn 38 cách 8 → 4), cặp trái trình phát video (⌄ | ✕; `VideoPlayerIconButton`/`VideoPlayerIconLabel` thêm tham số `width` mặc định 36 nên các nút video khác không đổi).
- **Không đổi**: header Reader (6 nút) và cụm nút phải của trình phát video.
- **Chuẩn header**: `CLAUDE.md`/`AGENTS.md`, `rules.md` (§ chuẩn Header + checklist) và `.agents/AGENTS.md` thêm quy định cụm nút liền nhau (2pt, khung 32, nút tròn cách 4); nút đứng một mình giữ chuẩn 36×36.
- Chuyển entry `[1.3.635]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code + diff; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy. Rủi ro: vùng chạm khung 32 hẹp hơn chuẩn 36 (dễ bấm nhầm nút bên cạnh); nút chữ "Xong" và icon trong `HStack` của `ToolbarItem` có thể nhận kiểu nút toolbar khác một chút so với khi là mục riêng.

## [1.3.664] - 2026-10-31

### feat: CryptoJS dựng sẵn cho load('crypto.js') của tiện ích

Lệch hợp đồng phát hiện khi viết tiện ích ciyuanji (giải mã DES): hợp đồng chuẩn (mục "Crypto") nói `load('crypto.js')` nạp CryptoJS dựng sẵn, nhưng FreeBook chỉ tìm file trong tiện ích — không có thì bỏ qua im lặng, script chết với `CryptoJS is not defined`. Người dùng duyệt plan, chọn **file của tiện ích thắng** (khác hợp đồng), CryptoJS 4.2.0, GCM + PBKDF2 native.

- **Thư viện đóng gói** `Sources/Resources/ExtensionLibraries/crypto-js-4.2.0.min.js` = `crypto-js.min.js` 4.2.0 của cdnjs (khớp SRI, giữ nguyên byte qua `.gitattributes`); giấy phép MIT ở `Docs/ThirdParty/CryptoJS-LICENSE.txt`. `project.yml` khai tường minh thư mục này là resource (loại khỏi mục `Sources` chung).
- **`JSBuiltInLibrary`** (mới, `Engine/`): tên thư viện dựng sẵn (`crypto.js`) + nguồn đọc từ bundle một lần; thiếu resource ⇒ log ❌. Dùng chung cho `load` và hai bộ kiểm tra tĩnh.
- **`load('crypto.js')`** (`JSExecutor+Load`): file `crypto.js` của tiện ích (gốc rồi `src/`) chạy như cũ; không có ⇒ chạy bản dựng sẵn, một lần mỗi executor (cả `load` lúc runtime). Chạy được cả khi executor không gắn tiện ích.
- **Phần native** (`JSCryptoJSBridge` mới ở `Bridges/`, JS ở `Bootstrap/JSCryptoJSBootstrapScript`), cài cho mọi executor bằng một dòng trong `JSExecutor`: `crypto.getRandomValues` toàn cục (JSC không có ⇒ CryptoJS 4.x không sinh được salt khi mã hoá bằng passphrase). Sau mỗi lần nạp `crypto.js` (bản nào cũng vậy) gắn thêm: `WordArray.random` lấy byte native (bản 4.1 tiện ích đang mang không dò `globalThis.crypto`); `AES.encryptGcm/decryptGcm` theo hợp đồng qua CryptoKit (khoá hex 32/48/64 hoặc passphrase đệm 0/cắt 16/24/32, IV rỗng = 12 byte 0, IV < 12 byte ⇒ lỗi, thẻ sai ⇒ WordArray rỗng như hành vi iOS; WordArray có byte ≥ 0x80 dùng byte thô thay vì hỏng như app gốc); `PBKDF2` với hasher SHA1/224/256/384/512 qua `CCKeyDerivationPBKDF` (250 000 vòng mặc định của 4.2.0 chạy JS thuần trong JSC không JIT mất hàng chục giây), hasher khác giữ bản JS. Đoạn JS bổ sung bỏ qua `CryptoJS` không đúng dạng và không bao giờ ném lỗi ra ngoài.
- **Bộ kiểm tra tiện ích** (`ExtensionScriptStaticCheck`) và **validator nháp của server debug** (`ExtensionDraftValidator`) không còn báo `load("crypto.js")` thiếu file (trước đây server debug chặn chạy nháp).
- **Tương thích**: ciyuanji, qidian-vp tự mang cùng bản CryptoJS 4.0/4.1 ⇒ vẫn chạy bản của mình (được gắn thêm `WordArray.random` native, GCM, PBKDF2 native; kết quả các hàm sẵn có không đổi). Bản dựng sẵn 4.2.0 chỉ khác 4.1 ở mặc định PBKDF2 (SHA256/250 000 thay SHA1/1). `Crypto.md5/sha*/hmac*` giữ nguyên.
- Ghi vào `rules.md` (global JS) và `CLAUDE.md`/`AGENTS.md` (đoạn `load()`). Chuyển entry `[1.3.634]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; JS bổ sung chạy thử bằng node trên context không có `crypto`/`require` với native giả lập (28/28 đạt: DES-ECB 4.1 → 4.2.0, AES passphrase khứ hồi trên cả hai bản, PBKDF2 native = JS, GCM khớp node, thẻ sai ⇒ rỗng); `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows); phần Swift (CryptoKit/CommonCrypto, resource trong bundle) chỉ CI chứng minh biên dịch + đóng gói; chưa thử trên máy.
