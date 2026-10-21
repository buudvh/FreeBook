# Đặc tả hành vi: nguồn truyện JSON kiểu Legado (clean-room)

> Trạng thái: bản 1 (2026-10-21). Tài liệu này mô tả **hành vi quan sát được và hành vi đề xuất**,
> không mô tả cách cài đặt của bất kỳ ứng dụng nào. Đội triển khai viết engine Swift **từ đầu** chỉ dựa
> trên file này và code FreeBook.

**Mục lục**: §0 Mở đầu (phạm vi, nhãn, tài liệu, đơn vị) · §1 Model JSON nguồn · §2 Rule · §3 URL · §4 Mạng · §5 Luồng ·
§6 JS bridge · §7 Phụ lục (đợt 1/hoãn, danh sách `[UNKNOWN]` U1–U28).

## §0. Mở đầu

### §0.1 Mục đích

Cho phép FreeBook (iOS) nhập và chạy các "nguồn truyện" dạng JSON mà cộng đồng Legado chia sẻ: một nguồn là
một object JSON mô tả cách tìm truyện, đọc thông tin, lấy mục lục và lấy nội dung chương trên một trang web
hoặc API, bằng các "rule" (chuỗi bộ chọn HTML/JSON/XPath/regex/JS).

### §0.2 Phạm vi

| Loại (`bookSourceType`) | Ý nghĩa | Đợt 1 |
|---|---|---|
| `0` | truyện chữ | **Trọng tâm**: nhập, lưu, tìm, khám phá, thông tin, mục lục, nội dung |
| `2` | ảnh / truyện tranh | Chỉ: nhập, lưu, nhận diện loại (§1.6, §5.12). Không chạy |
| `4` | video | Chỉ: nhập, lưu, nhận diện loại (§1.6, §5.12). Không chạy |
| `1` | audio | Bỏ: nhập được nhưng đánh dấu "không hỗ trợ" |
| `3` | tệp (tải file) | Bỏ: như trên |

Ngoài phạm vi đợt 1: đăng nhập (`loginUrl`/`loginUi`/`loginCheckJs`), nút tuỳ biến, `callBackJs`, mua chương
(`payAction`), giải mã ảnh/bìa, phân tích font, nguồn đăng ký (RSS).

### §0.3 Luật nhãn

Mỗi khẳng định quan trọng mang một nhãn:

- **`[tài liệu]`**: tài liệu hướng dẫn được phép nói rõ (ghi tên file `.md`).
- **`[quan sát]`**: suy ra từ nguồn thật trong corpus (ghi bộ `yck_<id>`/tên nguồn hoặc trích một rule ngắn),
  hoặc từ trang web thật đã curl (ghi URL).
- **`[UNKNOWN]`**: không đủ bằng chứng. Ghi các khả năng và **khuyến nghị** an toàn nhất. Bộ chạy nghiệm thu
  phải đo lại các điểm này (§7.2).
- **`[đề xuất]`**: ghi chú phụ, không phải nhãn thứ tư. Trên việc **chỉ thuộc FreeBook** (log, giới hạn số trang, nhịp toast,
  thông báo lỗi, giao diện) thì đó là quyết định thiết kế thuần. Trên bất cứ thứ gì **làm đổi đầu ra của nguồn** (cách chuyển
  kiểu, URL nền, tiền tố JSONPath ngầm, luật bỏ mục…) thì `[đề xuất]` nghĩa là **không có bằng chứng về hành vi gốc**, tức là
  `[UNKNOWN]` kèm khuyến nghị; bộ nghiệm thu đo các chỗ này qua mục U28 (§7.2).

Khi tài liệu và corpus mâu thuẫn, spec ghi cả hai và nói nên theo bên nào.

### §0.4 Tài liệu và dữ liệu đã dùng

- Tài liệu (thư mục trợ giúp web của bản dịch tiếng Việt): `ruleHelp.md`, `jsHelp.md`, `xpathHelp.md`,
  `regexHelp.md`, `debugHelp.md`, `SourceMBookHelp.md`, `rssRuleHelp.md`, `appHelp.md`, `ExtensionContentType.md`
  (file này chỉ là bảng MIME, không nói về loại nguồn).
- Corpus: `yck_1315`, `yck_1316`, `yck_1208`, `yck_1158`, `yck_1298`, `yck_1272` (5102 object, **3701 nguồn sau
  khi bỏ trùng `bookSourceUrl`**, giữ bản gặp trước theo thứ tự bộ vừa liệt kê; **3406 nguồn loại 0**).
- Bảng tần suất cú pháp chạy sẵn (`census_all.txt`) và các script thống kê tự viết (chỉ đọc corpus như dữ liệu).
- Khoảng 20 request curl tới trang thật (ghi URL tại chỗ dùng).

### §0.5 Đơn vị đo

- "**N nguồn**" = số nguồn (sau bỏ trùng) có ít nhất một lần xuất hiện. Mặc định trên 3701 nguồn, hoặc 3406
  nguồn loại 0 khi ghi "(loại 0)".
- "**N chuỗi rule**" = số giá trị chuỗi trong 5 nhóm rule (loại 0 có 58 588 chuỗi rule không rỗng, không tính
  `checkKeyWord`, `imageStyle`, `canReName`, `webJs`, `preUpdateJs`, `formatJs`, `callBackJs`, `payAction`, `imageDecode`).
- "**N lần**" = số lần xuất hiện (một nguồn có thể đóng góp nhiều lần).
- Ngưỡng chọn hàm đợt 1 tính theo **số nguồn**, không theo số lần (§6.4).

### §0.6 Quy ước trong spec

- "Nội dung hiện hành" (content) = đối tượng mà rule đang được áp lên: chuỗi HTML, phần tử HTML, nút XPath,
  giá trị JSON, hoặc giá trị JS. Kiểu của nó quyết định chế độ mặc định (§2.3).
- `getString` = đánh giá rule ra **một chuỗi**; `getStringList` = ra **danh sách chuỗi**; `getElements` = ra
  **danh sách phần tử/giá trị** (dùng cho rule danh sách). Đây là tên khái niệm trong spec, không phải API bắt buộc.
- Mọi so khớp tiền tố chế độ (`@css:`, `@json:`, `@xpath:`, `@js:`, `<js>`) **không phân biệt hoa thường**
  `[quan sát]`: corpus có `@JSon:` (102 lần), `@CSS:` (34), `@json:` (16), `@XPath:` (3), `@xpath:` (1).

---

## §1. Model JSON nguồn

### §1.1 Nhập

- **Dạng tệp** `[quan sát]`: cả 6 bộ là mảng JSON ở gốc, UTF-8, không BOM. Đề xuất chấp nhận thêm:
  1. object đơn (một nguồn) → bọc thành mảng một phần tử;
  2. chuỗi JSON mà nội dung là JSON (văn bản bị escape hai lần) → giải mã tối đa 2 lớp;
  3. BOM UTF-8 ở đầu → bỏ;
  4. tệp `.txt` có nội dung JSON (`appHelp.md` nói nguồn có đuôi `.txt` hoặc `.json`) `[tài liệu]`.
- Phần tử mảng không phải object → bỏ qua, ghi log, không làm hỏng cả lô `[đề xuất]`.
- **Khoá định danh** = `bookSourceUrl` (§1.4). Corpus có 1074 `bookSourceUrl` xuất hiện ở hơn một bộ, và **cả
  1074 đều khác nội dung** giữa các bộ; trong cùng một bộ không có trùng `[quan sát]`.
  - `[UNKNOWN]` hành vi gốc khi nhập trùng khoá. Khuyến nghị: bản nhập sau **ghi đè** bản đang có, giữ lại các
    trạng thái người dùng tự chỉnh (bật/tắt, nhóm người dùng tự đặt, thứ tự, biến nguồn `source.setVariable`).
    Màn nhập hiển thị số "mới / cập nhật / giống hệt" để người dùng chọn.
- **Lưu**: giữ nguyên **toàn bộ object JSON gốc** (kể cả khoá lạ) để xuất lại không mất dữ liệu; các trường đã
  parse là bản chụp dẫn xuất `[đề xuất]`.

### §1.2 Decode khoan dung

Corpus **rất đồng nhất về kiểu** `[quan sát]`: mọi nhóm rule là object (không gặp nhóm rule là chuỗi JSON lồng),
`enabled`/`enabledExplore`/`enabledCookieJar` luôn là bool, `bookSourceType`/`customOrder`/`weight`/
`lastUpdateTime`/`respondTime` luôn là số nguyên, `concurrentRate` luôn là chuỗi. Các luật dưới đây là **phòng
thủ** ("không gặp trong corpus" trừ khi ghi khác):

| Trường hợp | Xử lý `[đề xuất]` |
|---|---|
| Số nguyên nhận dạng chuỗi số (`"0"`) hoặc số thực (`0.0`) | ép về int; không parse được → mặc định |
| Bool nhận dạng số (`0`/`1`) hoặc chuỗi (`"true"`, `"false"`, `"1"`, `"0"`, không phân biệt hoa thường) | ép về bool; giá trị khác → mặc định |
| Chuỗi nhận dạng số/bool | chuyển sang chuỗi thập phân / `"true"`/`"false"` |
| Nhóm rule là **chuỗi** chứa JSON object | parse chuỗi đó (lenient, §1.2.1); lỗi → coi như nhóm rỗng |
| `null` ở bất kỳ khoá nào | như khoá vắng mặt |
| Khoá lạ cấp nguồn hoặc trong nhóm | giữ nguyên trong JSON gốc, engine bỏ qua |
| Giá trị rule không phải chuỗi (số, bool) | chuyển sang chuỗi |

**Mặc định khi vắng**: `bookSourceType=0`, `enabled=true`, `enabledExplore=true`, `enabledCookieJar=false`
`[UNKNOWN]` (corpus luôn có khoá này, nên không quan sát được mặc định), `customOrder=0`, `weight=0`, chuỗi rỗng
cho mọi rule.

#### §1.2.1 Parser JSON lenient (dùng chung cho header, exploreUrl, option URL, `@put`)

Corpus có JSON "lỏng" ở các trường chuỗi chứa JSON `[quan sát]`:

| Trường | Hỏng | Kiểu lỗi |
|---|---|---|
| `header` | 75/957 dạng `{…}` | 61 dùng nháy đơn (`{'User-Agent':'…'}`), 3 dấu phẩy thừa, 6 chuỗi không đóng nháy, 5 khác (ví dụ hai object nối nhau `{…},\n{"webView": true}`) |
| `exploreUrl` | 33/1000 dạng `[…]` | khoá không nháy (`{layout_flexGrow: 1}`), nháy đơn, phẩy thừa, ký tự điều khiển (`\x00`) trong chuỗi |
| option URL `,{…}` | 24/1009 (searchUrl) | nháy đơn, giá trị chứa `{{…}}` có nháy kép lồng (xử lý bằng cách thay `{{}}` trước, §3.2) |

Thuật toán đề xuất: (1) thử JSON chuẩn; (2) thử parser kiểu JSON5: chấp nhận nháy đơn, khoá không nháy, phẩy thừa,
chú thích `//` `/* */`, ký tự điều khiển và xuống dòng thô trong chuỗi; (3) nếu văn bản là nhiều object nối nhau
thì lấy object đầu; (4) vẫn lỗi → coi như rỗng và ghi log có tên nguồn và tên trường `[đề xuất]`.

### §1.3 Khoá cấp nguồn

Tần suất trên 3701 nguồn. "Có giá trị" = khoá có mặt và không rỗng.

| Khoá | Có mặt / có giá trị | Kiểu quan sát | Nghĩa và xử lý | Đợt |
|---|---|---|---|---|
| `bookSourceUrl` | 3701 / 3699 | chuỗi | Khoá định danh **và** URL gốc (§1.4) | 1 |
| `bookSourceName` | 3701 / 3700 | chuỗi (3 chuỗi số) | Tên hiển thị, có thể chứa emoji | 1 |
| `bookSourceGroup` | 3699 / 2735 | chuỗi | Danh sách nhóm (§1.5) | 1 |
| `bookSourceType` | 3701 | int | Loại nguồn (§1.6) | 1 |
| `bookSourceComment` | 2938 / 951 | chuỗi | Ghi chú tự do; **110 lần** được dùng làm mã JS qua `eval(String(source.bookSourceComment))` nên phải đưa nguyên văn vào JS (§6.5) `[quan sát]` | 1 |
| `enabled` | 3701 | bool | Tắt → không tham gia tìm/khám phá; vẫn mở được sách đã có `[đề xuất]` | 1 |
| `enabledExplore` | 3701 | bool | Có hiện ở Khám phá hay không | 1 |
| `enabledCookieJar` | 3701 | bool | Tự lưu `Set-Cookie` (§4.2) `[tài liệu ruleHelp.md]` | 1 |
| `concurrentRate` | 382 / 67 | chuỗi | Giới hạn nhịp request (§4.1) | 1 |
| `header` | 1546 / 1092 | chuỗi | Header mặc định (§3.10) | 1 |
| `searchUrl` | 3169 / 3159 | chuỗi | URL tìm kiếm (§3, §5.1) | 1 |
| `exploreUrl` | 2459 / 2011 | chuỗi | Danh mục khám phá (§5.2) | 1 |
| `bookUrlPattern` | 1415 / 605 | chuỗi regex | Nhận diện URL trang sách (§5.9); có giá trị rác như `已校验` | 1 (nhẹ) |
| `jsLib` | 121 / 110 | chuỗi JS (91) hoặc chuỗi JSON map tên→URL (19) | Thư viện JS dùng chung (§5.8) | 1 |
| `customOrder` | 3701 | int | Thứ tự sắp xếp thủ công | 1 (lưu) |
| `weight` | 3701 | int | Trọng số, dùng khi sắp xếp/đổi nguồn `[UNKNOWN]` nghĩa chính xác; chỉ lưu | lưu |
| `lastUpdateTime` | 3701 | int (ms epoch) | Thời điểm sửa nguồn; dùng khi so bản nhập trùng | lưu |
| `respondTime` | 3701 | int (ms) | Thời gian phản hồi đo lần trước; chỉ lưu | lưu |
| `loginUrl` | 1634 / 494 | chuỗi: URL (261 loại 0), JS có hàm `login` (70), JS khác (35), object rác `{"url":"null"}` (83) | Đăng nhập; **16 lần** bị `eval(String(source.loginUrl))` để lấy hàm dùng chung | 2 (nhưng xem §6.5) |
| `loginUi` | 413 / 96 | chuỗi JSON mảng | Form đăng nhập `[tài liệu ruleHelp.md]` | 2 |
| `loginCheckJs` | 372 / 52 | chuỗi JS | Kiểm tra sau mỗi request `[tài liệu ruleHelp.md]` | 2 |
| `variableComment` | 300 / 32 | chuỗi | Hướng dẫn cho người dùng nhập biến nguồn; hiển thị ở màn chỉnh biến | 1 (hiển thị) |
| `coverDecodeJs` | 249 / 2 | chuỗi JS | Giải mã ảnh bìa `[tài liệu ruleHelp.md]` | 3 |
| `exploreScreen` | 234 / 0 | luôn rỗng | Bỏ qua | – |
| `customButton` | 2379 | bool | Nút tuỳ biến trên trang sách | 3 |
| `eventListener` | 2379 | bool | Bật `callBackJs` | 3 |
| `ruleSearch` … `ruleContent` | ~3300 mỗi nhóm | object | §1.7 | 1 |
| `ruleReview` | 6 | object `{enabled}` | Bình luận; bỏ qua | – |

Không gặp trong corpus nhưng nên chấp nhận và lưu nguyên: mọi khoá khác.

### §1.4 `bookSourceUrl`: khoá và URL gốc

- **Là khoá thô**: 1199 nguồn có `#` trong `bookSourceUrl` để phân biệt các bản cùng trang (`https://m.qidian.com##限免部分书`,
  `https://api-bc.wtzw.com#七猫官方API`, `https://www.sjks88.com#`) `[quan sát]`. Nguồn còn tự cắt phần sau `#`:
  `source.getKey().match(/([^\#]+)\#/)[1]` (2 lần) `[quan sát]`. Vậy `source.getKey()` / `source.key` /
  `source.bookSourceUrl` trả **nguyên chuỗi** (gồm `#…`).
- **Là URL gốc** để ghép URL tương đối: theo luật ghép URL chuẩn, phần fragment bị bỏ, nên
  `https://zh.virtualtaboo.live##吉吉国王` + `/api/x` cho `https://zh.virtualtaboo.live/api/x` `[đề xuất]`.
- 52 nguồn có `bookSourceUrl` không phải URL (`69-明月`, `苹果通用API接口聚合`, `阅读2.0`) `[quan sát]`; các nguồn này tự
  dựng URL tuyệt đối bằng JS. Ghép tương đối khi gốc không phải URL → lỗi rõ ràng "nguồn không có URL gốc".
- 22 nguồn có khoảng trắng đầu/cuối (`'https://www.pinshuzhai.com '`). `[UNKNOWN]` có trim khoá hay không.
  Khuyến nghị: trim khi dùng làm URL gốc; khoá định danh lưu nguyên văn nhưng so trùng sau khi trim.
- 603 nguồn có `/` cuối, 86 có path (`https://m.jjwxc.net/channel/`). Không chuẩn hoá khoá.

### §1.5 `bookSourceGroup`: tách nhóm

- Dấu phân cách gặp trong corpus: **chỉ dấu phẩy ASCII `,`** (1153 nguồn có nhiều nhóm, ví dụ `快速书源 ⚡,通常书源 📂`)
  `[quan sát]`. Dấu cách **không** phải phân cách: tên nhóm chứa dấu cách và emoji (`通常书源 📂`, `正版小说 书源`).
- Thuật toán `[đề xuất]`: tách theo `,` (thêm `，` `;` `；` cho phòng thủ, corpus không có), trim từng phần, bỏ phần
  rỗng, bỏ trùng giữ thứ tự.
- Nhóm hay gặp (để test): `🌹已检26.10.15` (1203 nguồn), `通常书源 📂` (627), `搜索链接规则为空` (541, nghĩa là
  "rule tìm kiếm rỗng"), `快速书源 ⚡` (474), `免费` (275), `特殊书源 🔞` (195), `漫画书源 🎨` (74).

### §1.6 `bookSourceType` và nhận diện loại

| Giá trị | Số nguồn | Nghĩa | Bằng chứng |
|---|---|---|---|
| 0 | 3406 (92,0%) | chữ | `[tài liệu jsHelp.md]` ghi `type // 0:text 1:audio` cho sách |
| 1 | 65 | audio | như trên; nhóm `有声书源 🔊` đều là loại 1 `[quan sát]` |
| 2 | 175 | ảnh/tranh | nhóm `漫画书源 🎨`, `图片书源 📷` `[quan sát]` |
| 3 | 43 | tệp | nhóm `下载书源 📥`; `ruleHelp.md` có mục "Loại nguồn sách: Tệp" `[tài liệu]` |
| 4 | 12 | video | nhóm `影视频源 🎬`, `短剧` `[quan sát]` |

- Loại chỉ lấy từ `bookSourceType`; **không** suy từ tên/nhóm: 55 nguồn loại 0 có chữ `漫` trong tên/nhóm, 13 nguồn
  loại 0 có `🎨` `[quan sát]`.
- Giá trị lạ (âm, >4, không parse được) → coi là 0 và ghi log `[đề xuất]`.
- Nối với FreeBook: ánh xạ `0→ExtensionContentKind.text`, `2→.comic`, `4→.video`, `1`/`3`→`.unsupported`
  (đúng cách `ExtensionContentKind` của FreeBook đã chia). Loại tính lúc chạy theo nguồn, không ghi vào `Book`,
  giống quy ước comic/video hiện có của FreeBook `[đề xuất]`.

### §1.7 Nhóm rule và khoá con

Số nguồn có khoá / có giá trị (trên 3701). Ghi chú ngắn; chi tiết ở §5.

**`ruleSearch`** (3298 nguồn có nhóm):

| Khoá | Có / có giá trị | Vai trò |
|---|---|---|
| `bookList` | 3168 / 3161 | rule danh sách |
| `name` | 3170 / 3163 | tên truyện |
| `bookUrl` | 3164 / 3157 | URL trang sách (URL rule) |
| `author` | 2944 / 2887 | tác giả |
| `coverUrl` | 2573 / 2400 | ảnh bìa (URL) |
| `kind` | 2392 / 2227 | phân loại/nhãn |
| `lastChapter` | 2096 / 1845 | chương mới nhất |
| `intro` | 1760 / 1470 | giới thiệu |
| `wordCount` | 1195 / 863 | số chữ |
| `checkKeyWord` | 743 / 587 | từ khoá thử (§5.10) |

**`ruleExplore`** (3270 có nhóm): cùng khoá như `ruleSearch` trừ `checkKeyWord`; `bookList` 1818/1374,
`name` 1705/1377, `bookUrl` 1692/1379, `author` 1547/1202, `coverUrl` 1439/1102, `kind` 1280/936, `intro` 1244/906,
`lastChapter` 1065/680, `wordCount` 711/406. Luật thừa kế khi rỗng: §5.2.4.

**`ruleBookInfo`** (3299):

| Khoá | Có / có giá trị | Vai trò |
|---|---|---|
| `init` | 1078 / 442 | rule chạy trước, đổi "nội dung hiện hành" (§5.3) |
| `name`, `author`, `kind`, `intro`, `coverUrl`, `lastChapter`, `wordCount` | 2687/2545, 2598/2471, 2509/2355, 2854/2766, 2545/2388, 2445/2293, 1281/900 | ghi đè thông tin từ tìm kiếm |
| `tocUrl` | 1738 / 1357 | URL trang mục lục; rỗng = dùng chính trang sách |
| `canReName` | 394 / 84 | giá trị `1` (36), `true` (30), `True` (1) `[quan sát]` (§5.3.3) |
| `downloadUrls` | 123 / 99 | URL tải tệp (loại 3) — bỏ ở đợt 1 |

**`ruleToc`** (3294):

| Khoá | Có / có giá trị | Vai trò |
|---|---|---|
| `chapterList` | 3165 / 3159 | rule danh sách |
| `chapterName` | 3165 / 3161 | tên chương |
| `chapterUrl` | 3114 / 3103 | URL chương; rỗng = URL trang mục lục (§5.4) |
| `nextTocUrl` | 1071 / 700 | trang mục lục kế (§5.6) |
| `updateTime` | 718 / 334 | chuỗi hiển thị phụ (thời gian/số chữ) |
| `isVip` | 585 / 216 | cờ VIP (§5.4.3) |
| `isVolume` | 363 / 73 | cờ tiêu đề quyển |
| `isPay` | 47 / 23 | cờ đã mua |
| `preUpdateJs` | 54 / 18 | JS chạy trước khi lấy mục lục |
| `formatJs` | 11 / 3 | JS định dạng tên chương |

**`ruleContent`** (3293):

| Khoá | Có / có giá trị | Vai trò |
|---|---|---|
| `content` | 3249 / 3132 | nội dung |
| `nextContentUrl` | 1364 / 961 | trang nội dung kế (§5.6) |
| `replaceRegex` | 1048 / 736 | rule làm sạch áp lên nội dung (§5.5.3) |
| `imageStyle` | 806 / 523 | `0` (247), `FULL` (104), `full` (20), `TEXT` (12), `DEFAULT` (2), `0.0` (2), `text`, `FULl`, `Text`, và CSS rác ở loại 2 `[quan sát]` |
| `webJs` | 412 / 8 | JS chạy trong WebView khi tải nội dung bằng WebView (§4.4) |
| `sourceRegex` | 403 / 12 | regex lọc URL tài nguyên khi tải bằng WebView (`.*\.(mp3\|m4a).*`) — đợt 2 |
| `title` | 55 / 37 | tên chương lấy từ trang nội dung |
| `imageDecode` | 19 / 7 | giải mã ảnh — đợt 3 |
| `payAction` | 19 / 7 | mua chương — đợt 3 |
| `callBackJs` | 6 / 6 | sự kiện UI — đợt 3 |
| `subContent` | 2 / 2 | `[UNKNOWN]`, bỏ qua |

### §1.8 Cú pháp kiểu cũ

- Corpus **không** có khoá kiểu ứng dụng thế hệ trước (không gặp `ruleSearchUrl`, `ruleBookName`…) `[quan sát]`.
  `appHelp.md` nói một số nguồn thế hệ 2.0 không chạy trên 3.0 `[tài liệu]`. Đợt 1: không hỗ trợ; nhận diện được
  (object không có `bookSourceUrl` nhưng có khoá `rule…Url`) thì báo "định dạng nguồn cũ, không hỗ trợ" `[đề xuất]`.
- Placeholder kiểu cũ `searchKey`/`searchPage` trần trong URL: bảng census báo 4 nguồn, nhưng cả 3 mẫu xem được đều
  là **tên tham số** (`searchKey={{key}}`, fbook.net), không phải placeholder `[quan sát]`. Không hỗ trợ; tuyệt đối
  không thay chuỗi `searchKey` trong URL.

### §1.9 "Rule tối thiểu" cho một nguồn chữ

Định nghĩa đề xuất (nguồn loại 0 "chạy được về cú pháp"):

```
searchUrl ≠ "" ∧ ruleSearch.bookList ≠ "" ∧ ruleSearch.name ≠ "" ∧ ruleSearch.bookUrl ≠ ""
∧ ruleToc.chapterList ≠ "" ∧ ruleToc.chapterName ≠ ""
∧ ruleContent.content ≠ ""
```

Đo trên 3406 nguồn loại 0 `[quan sát]`: tìm kiếm đủ 2862 (84,0%), mục lục đủ 2885 (84,7%), nội dung đủ 2886 (84,7%),
**cả ba: 2861 (84,0%)**. Nới thành "(tìm kiếm **hoặc** khám phá) + mục lục + nội dung" thì 2873 (84,4%); 12 nguồn chỉ
dùng được qua Khám phá. Phần còn lại hầu hết là nguồn không có nhóm rule nào (402 nguồn loại 0 thiếu `ruleSearch`,
thường nằm trong nhóm `搜索链接规则为空`).

- `chapterUrl` **không** bắt buộc: rỗng ở 39 nguồn có `chapterList`, và đó đều là truyện một trang (`chapterList: html`,
  `chapterName: {{book.name}}`) (§5.4.1) `[quan sát]`.
- Nguồn không đạt rule tối thiểu: vẫn nhập và lưu, gắn cờ "thiếu rule" và không đưa vào tìm kiếm `[đề xuất]`.
- Bảng census báo chỉ 17,4% (591 nguồn) chạy được nếu cấm JS/XPath/WebView/đăng nhập, nên đợt 1 **bắt buộc** có
  JS, XPath và JSONPath.

---

## §2. Rule

> Phần lớn ngữ pháp rule **không có trong tài liệu được phép**. Tài liệu chỉ nói: bảng dấu hiệu chế độ
> (`@@`, `@XPath:`/`//`, `@Json:`/`$.`, `:` regex chỉ dùng cho danh sách), và việc rule đặt trong `{{…}}` cần tiền tố
> chế độ, thiếu tiền tố thì nội dung được chạy như JS `[tài liệu ruleHelp.md]`; `jsHelp.md` có thêm ví dụ `##{{book.name+"…"+title}}`
> sau nội dung. Mọi thứ khác dưới đây là `[quan sát]` hoặc `[UNKNOWN]`.

### §2.1 Ba cách đánh giá một rule

Cùng một chuỗi rule được đánh giá theo một trong ba **dạng yêu cầu**, do trường quyết định:

| Dạng | Trường dùng | Kết quả |
|---|---|---|
| `getElements` | `bookList`, `chapterList`, `ruleBookInfo.init` | danh sách "mục" (phần tử HTML, nút XPath, giá trị JSON, mảng nhóm regex, giá trị JS) |
| `getStringList` | `nextTocUrl`, `nextContentUrl`, `downloadUrls` | danh sách chuỗi |
| `getString` | mọi trường còn lại (`name`, `author`, `bookUrl`, `content`, …) | một chuỗi |

Bằng chứng cho `getStringList` ở trường "kế tiếp": JS sau rule dùng `result[0]` và `result.length`
(`text.下一@href\n@js:\nif(result){ result=result[0].includes("_")?result:""; }`,
`.page-link@a@href\n@js:\nnext = [];\nurl = result[0];\nlength = result.length;`) `[quan sát]`.
Bằng chứng cho `init` là `getElements`: `init: meta` (9 nguồn), `init: id.maininfo` (8), `init: $.data` (50), và các rule
sau đó đọc tiếp từ phần tử/đối tượng đó (§5.3.1) `[quan sát]`.

**Kiểu của nội dung hiện hành** (content) quyết định chế độ mặc định (§2.4):

| Kiểu | Sinh ra từ |
|---|---|
| HTML (tài liệu hoặc phần tử) | phản hồi không phải JSON; mục của rule danh sách chế độ mặc định/CSS; JS trả phần tử |
| Nút XPath | mục của rule danh sách XPath |
| JSON | phản hồi có thân bắt đầu bằng `{` hoặc `[` và parse được; mục của rule danh sách JSONPath; JS trả object/mảng/chuỗi JSON |
| Nhóm regex | mục của rule danh sách regex `:` (§2.13) |
| Chuỗi | kết quả trung gian của phân đoạn trước (§2.2) |

`[đề xuất]` Chuỗi được chuyển kiểu theo nhu cầu: chế độ JSON gặp chuỗi thì parse JSON (hỏng thì kết quả rỗng),
chế độ HTML/XPath gặp chuỗi thì parse HTML với URL nền hiện hành.

### §2.2 Phân đoạn: rule là một đường ống (pipeline)

Một chuỗi rule có thể xen kẽ **phân đoạn rule** và **phân đoạn JS**; đầu ra của phân đoạn trước là
`result`/nội dung của phân đoạn sau `[quan sát]`:

- `<js>…</js>` (khối JS, có thể nhiều khối): 1584 chuỗi rule có 1 khối, 43 có 2, 10 có 3; 847 chuỗi có rule đứng
  trước `<js>`; **494 chuỗi có chữ sau `</js>`**.
- `@js:` (JS **tới hết chuỗi**): 1161 chuỗi bắt đầu bằng `@js:`, 1116 chuỗi có `@js:` sau một rule.
- Ví dụ thật:
  - `class.book-card__meta@text@js:{ let m = result.match(/作者：(.+?)[分类]/); … }` (rule → JS),
  - `<js>java.put('qm_agent', …); result</js>\n$.data.chapter_lists` (JS → JSONPath),
  - `…</js>\ntag.a` (JS → mặc định),
  - `[property$=description]@content##(^|[。！？]+[”」）】]?)##$1<br><js>result</js>##三秒记住.*com` (rule → JS → regex),
  - `##="newWebView\('([^']+)'##$1###\n<js>java.ajax('https://m.suixkan.com'+result)</js>\nclass.chapter-entrance@text`
    (regex → JS gọi mạng trả HTML → rule trên HTML mới).

**Thuật toán tách** `[đề xuất, khớp mọi mẫu trên]`:

1. Duyệt chuỗi từ trái sang phải. Bỏ qua (không tách) vùng nằm trong `{{…}}` (§2.7).
2. Gặp `<js>` (không phân biệt hoa thường) → kết thúc phân đoạn rule hiện tại; nội dung tới `</js>` đầu tiên là một
   phân đoạn JS. Thiếu `</js>` → JS tới hết chuỗi.
3. Gặp `@js:` (không phân biệt hoa thường) ngoài khối `<js>` → phần còn lại là một phân đoạn JS cuối.
4. Phân đoạn rule chỉ có khoảng trắng bị bỏ.
5. Chạy tuần tự: `c₀` = nội dung hiện hành. Phân đoạn rule dùng `cᵢ` làm nội dung; phân đoạn JS nhận `result = cᵢ`
   (§6.2), kết quả JS thành `cᵢ₊₁`.
6. Mọi phân đoạn rule trung gian được đánh giá **cùng dạng yêu cầu với cả rule** (`getElements` / `getStringList` /
   `getString`), vì JS phía sau dùng `result.toArray()` khi là danh sách
   (`class.cytable@tag.tr[1:20]@tag.a[1]\n<js>list=result.toArray();`) và `result.match(...)` khi là chuỗi `[quan sát]`.
7. Kết quả cuối chuyển về dạng yêu cầu theo §2.14.

Tiền tố `-`/`+` của rule danh sách (§2.13.1) được bóc **trước** bước 1.

### §2.3 Cấu trúc một phân đoạn rule

```
phân đoạn  := biểu-thức
biểu-thức  := lá ( ("||" | "&&" | "%%") lá )*        ; tách theo §2.5
lá         := [@put:{…}]* phần-chọn ["##" regex ["##" thay-thế ["###"]]] [@put:{…}]*
phần-chọn  := [tiền-tố-chế-độ] thân  |  mẫu (template, §2.7)
```

Thứ tự xử lý một **lá** `[đề xuất]`:

1. Bóc mọi `@put:{…}` (§2.10), chạy chúng trên nội dung hiện hành.
2. Tìm `##` đầu tiên ở mức ngoài cùng (ngoài `{{}}`, ngoặc, nháy) → tách phần-chọn và đuôi regex (§2.6).
3. Nếu phần-chọn chứa placeholder (`{{`, `{$.`, `{$[`, `@get:{`) → **chế độ mẫu** (§2.7); ngược lại nhận diện chế độ (§2.4).
   Placeholder chỉ nằm trong đuôi regex → thay chúng trong regex/chuỗi thay thế trước, rồi chạy phần-chọn bình thường.
4. Đánh giá phần-chọn → áp đuôi regex.

### §2.4 Nhận diện chế độ của một lá

Áp lên phần-chọn đã trim, theo đúng thứ tự (so tiền tố không phân biệt hoa thường). Dòng 1, 2, 4, 5, 6, 7 là
`[tài liệu ruleHelp.md]`; phần còn lại `[quan sát]`:

| # | Điều kiện | Chế độ | Bóc tiền tố |
|---|---|---|---|
| 1 | bắt đầu `@@` | mặc định (jsoup) | `@@` |
| 2 | bắt đầu `@xpath:` | XPath | có |
| 3 | bắt đầu `@css:` | CSS | có |
| 4 | bắt đầu `@json:` | JSONPath | có |
| 5 | bắt đầu `//` | XPath | không |
| 6 | bắt đầu `$.` hoặc `$[` | JSONPath | không |
| 7 | bắt đầu `:` **và** đang đánh giá rule danh sách | regex danh sách | `:` |
| 8 | nội dung hiện hành là JSON | JSONPath ngầm (§2.11.1) | không |
| 9 | nội dung là nút XPath **và** bắt đầu bằng `/` | XPath tương đối | không |
| 10 | còn lại | mặc định (jsoup) | không |

Ghi chú bằng chứng:

- Dòng 6 với `$[`: tài liệu chỉ nói `$.`; `$[` là `[đề xuất]` (cùng ngữ pháp JSONPath).
- Dòng 7: `:` ngoài rule danh sách **không** phải regex: `nextContentUrl: :contains(下一页)@href##(^.*_\d+.*$|^)##$1###`
  là bộ chọn giả lớp CSS `[quan sát]`. Corpus có 17 chuỗi rule danh sách bắt đầu bằng `:` (19 nếu tính cả 2 chỗ `:contains` ngoài danh sách).
- Dòng 8: 135 rule con dạng khoá trần dưới danh sách JSON (`📂阿巴小说`: `bookList: $.data`, `name: title`,
  `author: author`), và danh sách JSON không có `$.` (`⚡📂酷我小说`: `bookList: data`, `name: title`;
  `🏷七猫小说`: `bookList: data.books`) `[quan sát]`. Đã curl
  `https://book.washai.net/book/searchByPage?keyword=我的&curr=1&limit=10`: thân là JSON, `data.list[*]` là object có
  khoá `bookName`, `authorName`, khớp rule `name: bookName`, `author: authorName` của `📂书海阁`. Nội dung JSON cũng có
  thể là **trang chính**: `ruleContent.content: data.content`, `data.novel.content` (không `$`).
- Dòng 9: 73 rule con bắt đầu bằng `/` đơn dưới danh sách XPath (`⚡📂飘天文学`: `bookList: //div[@class='hot_sale']`,
  `name: /a/p[1]/text()`, `bookUrl: /a/@href`) `[quan sát]`.
- `@@@css:…` (2 lần, `{{@@@css:p.detail__summary__content@text}}`): sau khi bóc `@@` thì nhận diện lại từ dòng 1 `[đề xuất]`.
- `$1`/`$2` đứng đầu là tham chiếu nhóm regex (§2.13), không phải JSONPath; chỉ có nghĩa khi mục là nhóm regex.

### §2.5 Toán tử `||`, `&&`, `%%`

Tài liệu không mô tả. Tần suất (chuỗi rule loại 0, ngoài `{{}}`/JS): `||` 1864, `&&` 1466, `%%` 11; có cả `&&` lẫn `||`: 18.

**Nghĩa** `[quan sát, suy từ ý đồ tác giả]`:

| Toán tử | Trên danh sách (getElements/getStringList) | Trên chuỗi (getString) |
|---|---|---|
| `A\|\|B` | kết quả của vế đầu tiên **không rỗng** | chuỗi của vế đầu tiên không rỗng (sau trim) |
| `A&&B` | nối tất cả danh sách theo thứ tự | nối chuỗi các vế (bỏ vế rỗng) bằng `\n` |
| `A%%B` | xen kẽ: A₀, B₀, A₁, B₁, … (vế ngắn hết thì bỏ qua) `[UNKNOWN]` | xen kẽ rồi nối `\n` |

- `||` là "thử lần lượt": `img@data-src||img@src`, `option@value||text.下一页@href`, `data.bookList||data.items`.
- `&&` là "gộp": `[property="og:novel:category"]@content&&\n[property="og:novel:status"]@content` (kind),
  `.BookCard&&Data.Books`. Xuống dòng/khoảng trắng quanh toán tử bị bỏ.
- Nối bằng `\n`: tác giả tự thay xuống dòng thành dấu phẩy sau khi gộp: `{{$.multiCategory[*].name&&$.tag##\n##,}}`,
  `{{@@#tags@.tag@text##\n}}` `[quan sát]`.
- `%%`: chỉ thấy `.line_en@text%%.line_cn@title` (song ngữ: dòng tiếng Anh xen bản dịch) và `…@href%%0`. Nghĩa xen kẽ là
  suy đoán từ ví dụ song ngữ → `[UNKNOWN]`; khuyến nghị như bảng.

**Ưu tiên** `[UNKNOWN, khuyến nghị có bằng chứng]`: tách đệ quy, `||` lỏng nhất, rồi `&&`, rồi `%%`. Cả 8 rule có cả hai
toán tử đều chỉ hợp lý với thứ tự này, ví dụ:

- `$.data.result[*].data[*]&&$.data.result.live_user[*]&&$.data.result.live_room[*]||$.data.result[*]` → (A&&B&&C)||D;
- `bookRecommendWords||bookDesc&&copyright_owner` → A||(B&&C);
- `class.author@tag.span.1@text&&class.author@tag.span.2@text##小说||class.cate@text&&class.meta@tag.span.2@text##小说`
  → (A&&B##小说)||(C&&D##小说).

Phương án khác ("toán tử gặp trước quyết định, không tách tiếp") làm hỏng 6/8 rule trên.

**Tokenizer** `[đề xuất]`: quét ký tự, chỉ nhận `||`/`&&`/`%%` ở mức ngoài cùng, **bỏ qua**:

- ký tự ngay sau `\` (thoát): giữ được `##.*更新时间：|\|| |手机阅读.*` và `##作者：(.*?)[\||<]##$1###` `[quan sát]`;
- vùng trong `[…]`, `(…)`, `{…}`, `{{…}}`: giữ được `$.data.data[?(@.volume == false)]`,
  `[property~=update_time|status|category]`, filter JSONPath có `&&`;
- chuỗi nháy `'…'` / `"…"`;
- khối `<js>…</js>` (đã tách ở §2.2).

Toán tử **không** bị chặn bởi `##`: rule `a.author@text||p.info@text##.*作者：([^\s<]+).*##$1||dt@text##\[|\]` cần tách
`||` nằm sau `##` `[quan sát]`. Ngoại lệ đã biết làm hỏng tokenizer này (3 chuỗi, coi là rule lỗi):
`id.nr1@html||.chapter_content@html\n##\&&lt;|&&gt;|/` và hai rule chứa `&&amp;lt;.*?&&amp;gt;`.

### §2.6 Hậu tố regex `##`

Mỗi **lá** có thể mang đuôi regex (gắn với lá, không với cả biểu thức, §2.5) `[quan sát]`: 7126 chuỗi rule có 1 `##`,
1225 có 2, 708 có 3; 623 có `###` (552 kết thúc bằng `###`).

| Dạng | Nghĩa | Bằng chứng |
|---|---|---|
| `sel##R` | xoá **mọi** đoạn khớp `R` | `p.m-book-meta@text##·.*` |
| `sel##R##P` | thay **mọi** đoạn khớp `R` bằng `P` (`$1`… là nhóm) | `id.fmimg@tag.img@data-original##^/##https://www.min-yuan.com/` |
| `sel##R##P###` | tìm **đoạn khớp đầu tiên**; kết quả = `P` khai triển theo nhóm của đoạn khớp đó (phần còn lại của chuỗi **bị bỏ**) | xem dưới |

`###` = "trích khớp đầu", **không** phải "chỉ thay lần đầu" `[quan sát, đã curl]`: nguồn `⚡📂搜小说` có
`tocUrl: .mubtn@a@href##/(\d+)##https://wap.sou78.com/info.php?aid=$1###`. Trang `https://www.sou78.com/book/2/` có
`<p class="mubtn"><a href="/chapter/2/">`. Trích khớp đầu cho `https://wap.sou78.com/info.php?aid=2`; "thay lần đầu" cho
`/chapterhttps://wap.sou78.com/info.php?aid=2/` (URL hỏng). Tương tự `{{baseUrl}}##(\d+)##/txt/$1_1.html###`,
`##作者.([^<]+)##$1###`.

- Không khớp ở chế độ `###` → `[UNKNOWN]`. Bằng chứng yếu cho "giữ nguyên chuỗi": tác giả viết
  `##(^.*_\d+.*$|^)##$1###` (thêm nhánh `|^` luôn khớp rỗng để ép kết quả rỗng), tức là nếu không khớp thì chuỗi gốc
  bị giữ lại. Khuyến nghị: **giữ nguyên chuỗi đầu vào**.
- Đuôi kết thúc bằng `##` (hai dấu, ví dụ `$.bid##(\d+)##https://book.qq.com/book-detail/$1##`) → coi như thay mọi đoạn
  (hai cách cho cùng kết quả trên mọi mẫu gặp) `[đề xuất]`.
- Hơn một cặp `R##P`: không gặp mẫu rõ ràng (các chuỗi có ≥4 `##` đều do JS chen giữa) → bỏ phần dư, ghi log `[UNKNOWN]`.
- Phần-chọn rỗng (`##R…` đứng đầu lá) → áp regex lên **chuỗi của nội dung hiện hành**: phần tử HTML → outer HTML, JSON →
  văn bản JSON, chuỗi → chính nó. Bằng chứng: `kind: ##\[([^]]*)[\s\S]*?_blank">[^>]*>([^<]*)##$1,$2###` khớp thẻ HTML
  `_blank">` nên chuỗi đầu vào phải là HTML của mục `[quan sát]`. 962 chuỗi rule bắt đầu bằng `##`
  (phần lớn là `replaceRegex`, §5.5.3).
- Chuỗi đầu vào: `getString` → nối các giá trị bằng `\n` **rồi** áp regex (rule dùng `(?m)` để khớp từng dòng:
  `##(?m)(?:🏷|📁)\s+|📖$`); `getStringList` → áp từng phần tử `[đề xuất]`.
- Cú pháp regex: tương thích regex kiểu Java; tác giả dùng `(?s)`, `(?m)`, `(?i)`, lookbehind `(?<!…)`, `\uXXXX`, `[^]]`
  `[quan sát]`; `regexHelp.md` mô tả phần cơ bản `[tài liệu]`. Dùng `NSRegularExpression` (ICU); regex không biên dịch
  được → bỏ bước regex, giữ chuỗi, ghi log `[đề xuất]`.
- Placeholder trong regex (`#content@html##{{chapter.title}}`, `##{{book.author}}.*.接着再看更方便`): thay giá trị **thô**
  vào regex. Nếu regex sau khi thay không biên dịch được thì thay lại bằng giá trị đã escape `[đề xuất]`.

### §2.7 Mẫu (template) và placeholder

Ba loại placeholder `[quan sát]`:

1. `{{X}}`: 2829 nguồn loại 0 (83,1%, census). `X` có dấu hiệu chế độ (`@@`, `@css:`, `@xpath:`, `//`, `@json:`, `$.`, `$[`)
   → đánh giá như rule `getString` trên nội dung hiện hành; không có → **JS** `[tài liệu ruleHelp.md]`. Phân loại 4955
   `{{}}` trong rule loại 0: `$.` 2577, JS 1418 (320 là tên biến/thuộc tính trần như `{{book.name}}`, `{{baseUrl}}`),
   `@@` 931, `@css:` 20, `@json:` 6, `//` 3.
2. `{$.path}` / `{$..path}` / `{$[…]}` (một cặp ngoặc): 433 lần, chủ yếu ở trường URL của nguồn JSON
   (`/pc/book/{$.id}/catalog`, `bookId={$.bookId}`) và `@json:{$.classname}&&{$.tag[*]}` → JSONPath `getString` trên nội dung.
3. `@get:{key}`: biến đã lưu (§2.10). Rule chỉ gồm `@get:{n}` (102 lần ở `ruleBookInfo.name`) → giá trị biến.

**Chế độ mẫu**: khi phần-chọn chứa placeholder, kết quả = phần chữ giữ nguyên, placeholder được thay bằng giá trị
(`第{{$.chapterNum}}章`, `http://api.17k.com/book/{{$.id}}/split1/merge?…`, `@get:{l}◎@get:{g}`, `<br>{$.introduction}`).
Đo trên corpus: 1837 chuỗi rule có `{{` trong phần-chọn và **không có trường hợp nào** phần chữ còn lại trông như bộ chọn;
139 chuỗi chỉ có `{{` trong đuôi regex `[quan sát]`. Vì vậy luật "có placeholder trong phần-chọn ⇒ mẫu" an toàn.

Chi tiết `[đề xuất]`:

- Tìm điểm kết thúc `{{…}}`: từ `{{`, theo dõi độ sâu `{`/`}` đơn và chuỗi nháy bên trong; kết thúc ở `}}` đầu tiên khi
  độ sâu bằng 0. Cho phép khoảng trắng quanh nội dung (`{{ URL("/bookcity/…", {…}) }}`).
- Giá trị JS `undefined`/`null` → chuỗi rỗng: `{{cookie.removeCookie(source.getKey())}}/modules/article/search.php` (56 lần
  trong `searchUrl`) dùng JS chỉ để gây tác dụng phụ rồi lấy chuỗi rỗng `[quan sát]`.
- Kết quả danh sách trong placeholder → nối `\n`.
- Mẫu nằm trong một vế `||`: vế được coi là **rỗng** nếu có ít nhất một placeholder cho chuỗi rỗng `[UNKNOWN]`. Lý do:
  `🏷磨铁中文` có `bookList: data.bookList||data.items` và `bookUrl: /pc/book/{$.id}/catalog||/pc/book/{$.bookId}/catalog`;
  mục tìm kiếm có `id`, mục khám phá có `bookId`. Vế đầu phải "thất bại" khi thiếu `id` thì vế sau mới được dùng.
  Ngoài vế `||`, placeholder rỗng chỉ để lại phần chữ xung quanh: `lastChapter: 第{{$.maxChapterId}}章{{$.commentdate}}##第章`
  (tác giả tự xoá phần `第章` còn sót khi `maxChapterId` rỗng) `[quan sát]`.
- Placeholder **trong mã JS** của rule trường (`<js>\n"{{$.chaptertype}}"=='1'?true:false;\n</js>`, hoặc không nháy
  `{{$.chaptertype}}=='1'`) được thay **trước khi** chạy JS `[quan sát]` (169 lần ở `ruleToc`, 104 ở `ruleBookInfo`,
  102 ở `ruleSearch`). Ngoại lệ: rule URL (§3.2) và `exploreUrl` dạng JS (§5.2.3) **không** thay trước.

### §2.8 Chế độ mặc định (phương ngữ kiểu jsoup)

Chế độ phổ biến nhất (53 237 chuỗi rule, census). Cài trên SwiftSoup.

#### §2.8.1 Tách bước

Phần-chọn được tách theo `@` ở mức ngoài cùng (không tách trong `[…]`, `(…)`, nháy) thành các bước.

- `getElements`: **mọi** bước đều là bước chọn phần tử (`ul@li`, `class.chapList@tag.li`, `#allchapter dd`).
- `getString`/`getStringList`: **bước cuối là bước trích** (§2.8.4), các bước trước là bước chọn phần tử. Rule một
  bước như `text`, `href`, `title` là bước trích trên chính mục hiện hành: `chapterName: text`, `chapterUrl: href`
  (`📂篱笆好文学`), `updateTime: title` (`🏷塔读文学`, danh sách `.chapter a`) `[quan sát]`. Đo: 1305 rule một bước `text`,
  1288 `href`, 103 `title` trên nguồn HTML; **không** thấy rule một bước là tên thẻ HTML thông dụng (`h1`, `div`) ở trường
  chuỗi của nguồn HTML.
- Bước rỗng (rule bắt đầu bằng `@`, như `@href`, `@text`, `@tag.td.2@text`) = giữ nguyên mục hiện hành `[quan sát]`
  (81 + 42 chuỗi rule).
- Áp bước chọn: với **từng** phần tử hiện có, chọn con cháu theo bước, nối kết quả theo thứ tự tài liệu, rồi áp chỉ số
  của bước. `[UNKNOWN]` chỉ số áp trên danh sách đã nối hay trên từng nhóm con (khác biệt chỉ xảy ra khi bước trước trả
  nhiều phần tử). Khuyến nghị: áp trên danh sách đã nối.

#### §2.8.2 Bước chọn phần tử

| Dạng | Nghĩa | Bằng chứng `[quan sát]` |
|---|---|---|
| `class.TÊN` | con cháu có class `TÊN`; nếu `TÊN` có dấu cách (`class.pop-books2 clearfix`) thì phải có **đủ mọi class** | 10 096 bước một class, 749 có dấu cách. Đã curl `https://www.xbanxia.cc/modules/article/search_t.php?charset=utf-8&searchkey=我的&Submit=&page=1`: phần tử đích là `class="pop-books2 clearfix"` |
| `tag.TÊN` | con cháu có tên thẻ | `tag.li`, `tag.a` |
| `id.TÊN` | phần tử có id (con cháu) | `id.nr1@html`, `id.linkNext@href` |
| `text.CHUỖI` | con cháu mà **chữ của chính nó** (không tính con) chứa `CHUỖI`, giữ nguyên dấu cách | `text.下一页@href` (415 `nextContentUrl`), `text.查看全部章节 >>@href`. Đã curl `https://m.cuoceng.com/book/chapter/633122f9-be7e-411f-981e-0bd4666d7a8b.html`: `<a … id="linkNext">下一页</a>` là phần tử có chữ riêng chứa `下一` |
| `children` | con trực tiếp | `id.resultDiv@children`, `class.b_bor@children@tr!0:1:2:3@a` (39 lần) |
| khác | **bộ chọn CSS kiểu jsoup** áp lên phần tử (gồm chính nó nếu khớp, như `select` của jsoup) | `.bookbox`, `a.m-book-row`, `meta[property=og:novel:author]@content`, `#catalog ol.mb-catalog li a` |

- Nghĩa "chữ riêng" của `text.`: cả hai nghĩa ("chữ riêng" hay "chữ gồm con cháu") đều cho kết quả đúng với mẫu đã thử,
  vì tổ tiên không có `href`. Chọn "chữ riêng" để `getString` không nối thêm giá trị rỗng của tổ tiên `[UNKNOWN]`.
- Bộ chọn CSS phải là **phương ngữ jsoup**, không phải CSS trình duyệt `[quan sát]`: `:contains(作者)`, `:eq(1)`,
  `:matches(…)` (`a:matches(第二[頁页]|下[一\s]*[頁页])`), `:not(…)`, `:has(…)`, `:nth-child`, `:nth-of-type`, và
  `[attr~=regex]` là **regex** (`[property~=category|status|update_time]`, `[href~=^javascript:|^#]`). SwiftSoup cài đúng
  phương ngữ này.
- Bộ chọn CSS lỗi cú pháp → bước cho danh sách rỗng, ghi log, không ném lỗi lên trên `[đề xuất]` (corpus có rule lỗi như
  `.breadcrumb tag.li:eq(1) a@text`).

#### §2.8.3 Chỉ số

Hai cú pháp, đặt ở **cuối bước** (`class.x.0`, `tag.td.2`, `p.2`, `.fl.0`, `tr!0`, `li[1:]`) `[quan sát]`.

**Kiểu chấm / chấm than** (đếm theo bước): `css/tag .N` 6915, `tag .N` 5745, `class .N` 1380, `!N` 718, `.N:M…` 369,
`!N:M…` 155.

| Cú pháp | Nghĩa | Bằng chứng |
|---|---|---|
| `.N` | giữ phần tử thứ N (đếm từ 0) | `tag.a.0@href`, `class.author.2@text` |
| `.-N` | đếm từ cuối, `-1` là cuối | `span.-1@text` (tác giả ở span cuối), `option.-1@value` |
| `.N:M:K…` | giữ **danh sách** chỉ số, theo thứ tự viết | `tag.p.0:1:2:3:4:5` (tác giả liệt kê từng số), `tag.td.5:4`, `#left@li.3:4:9@text` |
| `!N` | **bỏ** phần tử N | `tr!0` (bỏ hàng tiêu đề), `option!0@value` (bỏ trang hiện tại) |
| `!N:M:K…` | bỏ danh sách chỉ số | `tag.dd!0:1:2:3:4:5:6:7:8` |

Nhận dạng: đuôi bước khớp `[.!]-?\d+(:-?\d+)*$`; `.!` (`tag.tr.!0`, 1 lần) coi như `!`. CSS không có class bắt đầu bằng
chữ số nên `.0` không nhầm với class `[đề xuất]`.

**Kiểu ngoặc vuông** (cuối bước, nội dung chỉ gồm số, `:`, `,`, `!`, `-`; ngoặc khác là bộ chọn thuộc tính CSS):
134 đơn, 58 khoảng, 12 danh sách, 6 loại trừ, 1 có bước.

| Cú pháp | Nghĩa | Bằng chứng |
|---|---|---|
| `[N]`, `[-N]` | một phần tử | `.autor2[0]@text`, `tag.div[-1]` |
| `[a:b]` | khoảng **gồm cả hai đầu**; số âm tính từ cuối; `a > b` → **đảo chiều** | xem dưới |
| `[a:]`, `[:b]` | thiếu đầu = đầu/cuối danh sách | `tag.tr[1:]`, `ul li a[8:]` |
| `[N,M,…]` | danh sách chỉ số | `p[2,3]@span@text`, `td[0,-1,-2]@text` |
| `[!N,…]` | loại trừ | `tag.li[!0]`, `.book_other@span[!1]@text` |
| `[a:b:c]` | `[UNKNOWN]` | `.p2@li[1:2:3]@text##(类型\|状态\|更新)：` (1 lần) |

Bằng chứng "gồm cả hai đầu, cho phép đảo" `[quan sát, đã curl]`: `📂手机看书` có `kind: .autor2[2:1]@text##.*：`. Trang
`https://www.sjks88.com/wuxia/53054.html` có đúng 3 phần tử `.autor2`: [0] `作者：川北之王`, [1] `更新时间：2026-10-21`,
[2] `类别：武侠`. Nghĩa "gồm hai đầu, đảo chiều" cho `武侠` và `2026-10-21` (đúng ý trường kind); nghĩa nửa mở kiểu Python
cho danh sách rỗng. Thêm: `#detail-list-select@li[-1:0]` (đảo cả danh sách), `#content@article[0:-1]`, `p[-2:-3]`.

- `[a:b:c]`: hai khả năng: (1) khoảng a..b bước c (nhất quán với `[a:b]`), (2) danh sách chỉ số như `.a:b:c`. Mẫu duy nhất
  hợp với (2) (regex bóc ba nhãn). Khuyến nghị (1), bộ nghiệm thu đo lại.
- Chỉ số vượt phạm vi → bỏ qua chỉ số đó, không lỗi `[đề xuất]`.

#### §2.8.4 Bước trích (bước cuối)

Đếm bước cuối trong rule chuỗi chế độ mặc định (lần): `text` 21 373, `href` 7177, `content` 3401, `src` 2591, `html` 2024,
`textNodes` 975, `value` 218, `ownText` 212, `data-original` 190, `title` 166, `data-src` 114, `_src` 34, `all` 28, `alt` 21,
`onclick` 20, `rel` 17, `class` 13 `[quan sát]`.

| Từ khoá | Kết quả trên mỗi phần tử | Nhãn |
|---|---|---|
| `text` | chữ của phần tử gồm con cháu, khoảng trắng gộp như `text()` của jsoup | nghĩa `[quan sát]`; chuẩn hoá khoảng trắng `[đề xuất]` |
| `ownText` | chữ riêng, không gồm con | `[quan sát]` |
| `textNodes` | các nút chữ con trực tiếp, mỗi nút trim, bỏ nút rỗng, nối `\n` | chi tiết `[UNKNOWN]`; 486 nguồn dùng cho `content` |
| `html` | HTML của phần tử | `[UNKNOWN]` inner hay outer; khuyến nghị **outer HTML** (JS phía sau đôi khi `Jsoup.parse(result).select('#content p')`, cần thẻ ngoài) |
| `all` | như `html` | `[UNKNOWN]` |
| tên khác | giá trị thuộc tính; không có → rỗng; lỗi gõ (`herf`, `oweText`) → rỗng | `[quan sát]` |

- Nhiều phần tử → `getString` nối `\n`; `getStringList` trả từng giá trị, bỏ giá trị rỗng `[đề xuất]`.
- Không có phần tử nào → rỗng (không lỗi).
- Không tự chuyển URL tương đối thành tuyệt đối ở bước này; việc đó do trường URL làm (§2.15).

### §2.9 Chế độ CSS (`@css:`)

507 lần `@css:` + 34 `@CSS:`. Sau khi bóc tiền tố, tách bước theo `@` như §2.8.1; mỗi bước chọn là **một bộ chọn CSS
jsoup** (không có `class.`/`tag.`/`id.`/`text.`/`children`, không có chỉ số kiểu chấm). Bước cuối là bước trích như §2.8.4
(`@css:.itemtxt p:eq(1) a@text##作者：`, `@css:a[href*="novel-"]@href`) `[quan sát]`.

### §2.10 `@put` và `@get`

- `@put:{k1:"rule1", k2:rule2}`: object lỏng (§1.2.1: khoá/giá trị có hoặc không nháy); **giá trị là rule** (nhận diện chế
  độ như §2.4), đánh giá `getString` trên nội dung hiện hành; lưu vào kho biến (§5.7). Xuất hiện ở đầu (110 lần, chủ yếu
  `init`) hoặc giữa/cuối lá (155 lần): `$.bookName@put:{book:id}`, `a.0@text@put:{u:"a.0@href"}`,
  `@put:{n:"[property$=book_name]@content", a:"[property$=author]@content", …}` `[quan sát]`. Bóc ra khỏi lá trước khi đánh
  giá. Tìm `}` kết thúc theo đếm ngoặc, bỏ qua nháy.
- `@put` trong rule danh sách (`table@tr@td@put:{author:'@@tag.th.0@text',…}`, 3 lần ở `ruleExplore.bookList`):
  `[UNKNOWN]`; khuyến nghị đánh giá trên nội dung **trước** khi lấy danh sách (tức là trang).
- `@get:{key}`: placeholder (§2.7), thay bằng giá trị đã lưu, thiếu → rỗng. 831 lần, nhiều nhất ở `ruleBookInfo`
  (`name: @get:{n}`, `lastChapter: @get:{l}◎@get:{g}`) `[quan sát]`.
- Kho của `@put`/`@get` là **cùng kho** với `java.put`/`java.get(key)` (§6.4) `[UNKNOWN]`: tài liệu chỉ ghi `java.get(key)` /
  `java.put(key, value)` là "truy cập biến" `[tài liệu jsHelp.md]`. Khuyến nghị dùng chung một kho.

### §2.11 JSONPath

Tiền tố: `@json:` (118 lần mọi kiểu hoa thường), `$.`/`$[` (5088 chuỗi rule bắt đầu bằng `$.`), hoặc ngầm (§2.4 dòng 8).

#### §2.11.1 Đường dẫn ngầm

- Phần-chọn không bắt đầu bằng `$` → thêm tiền tố: bắt đầu bằng `.` hoặc `[` thì thêm `$`, còn lại thêm `$.` `[đề xuất]`.
  Ví dụ: `title` → `$.title`, `data.books` → `$.data.books`, `@json:id` → `$.id` (`{{@json:id}}`, 6 lần) `[quan sát]`.
- Trong chế độ JSON, `@` **không** tách bước (filter JSONPath dùng `@`).

#### §2.11.2 Tính năng cần có

Đếm trên mọi chuỗi rule loại 0 (lần): `..` quét sâu 844, `[*]` 610, `[n]` 174, `[-n]` 27, `.*` 56, filter `[?(…)]` 24
(`$.data.data[?(@.volume == false)]`, `$..[?(@.novelName)]`), slice `[:10]` 4, hợp `[0,1]` (`$.Novels[0,1]`) `[quan sát]`.

#### §2.11.3 Chuyển kiểu kết quả `[đề xuất]`

| Giá trị | `getString` | `getElements` |
|---|---|---|
| chuỗi | chính nó | `[chuỗi]` |
| số | thập phân; số nguyên không có `.0`, không dạng mũ | `[số]` |
| bool | `true`/`false` | `[bool]` |
| `null` / không có | rỗng | `[]` |
| object/mảng (một giá trị) | văn bản JSON gọn | mảng → các phần tử; object → `[object]` |
| nhiều kết quả (wildcard/quét sâu/filter) | từng phần tử chuyển như trên, nối `\n` | danh sách |

`getString` trên object cho văn bản JSON vì JS hay viết `JSON.parse(java.getString("$.data"))` `[quan sát]`.

### §2.12 XPath

- Tiền tố `//` (815 chuỗi rule) hoặc `@XPath:`/`@xpath:` (4); dưới danh sách XPath, rule con bắt đầu bằng `/` đơn (§2.4 dòng 9).
- Ngữ pháp và hàm theo XPath 1.0 (trục, vị từ, `text()`, `@attr`, `contains`, `starts-with`, `normalize-space`, `position()`,
  `last()`, `|`, …); không hỗ trợ trục `namespace`; chỉ số bắt đầu từ 1 `[tài liệu xpathHelp.md]`.
- 663 chuỗi rule có `/text()` hoặc `/@attr`. Kết quả là phần tử (`//font[2]` ở `isVip`, `//ul[@class='ullist']//p` trong `{{}}`)
  → `getString` lấy chữ của phần tử `[UNKNOWN]`; `getElements` trả nút.
- `/a/p[1]/text()` dưới mục XPath = đường dẫn **tương đối** tới mục (bước đầu là con), như `./a/p[1]/text()` `[quan sát]`.
- Cài đặt `[đề xuất]`: iOS có sẵn libxml2 (parser HTML + XPath). Mục XPath là nút libxml2; rule con không phải XPath thì
  tuần tự hoá nút thành HTML rồi parse bằng SwiftSoup.

### §2.13 Regex danh sách `:` và tiền tố danh sách

- Chỉ trong `bookList`/`chapterList` (17 lần) `[tài liệu ruleHelp.md]`. `:R` chạy trên **chuỗi nguồn** của nội dung (HTML
  thô); mỗi đoạn khớp là một mục; mục = mảng nhóm `[0..n]` `[quan sát]`: `:<dd><a href="([^"]*)[^>]*>([^<]*)`.
- Rule con dùng `$1`, `$2` theo chế độ mẫu: `chapterName: $2`, `chapterName: $2$3`, `chapterUrl: $1.html`,
  `chapterUrl: $1##章节目录` `[quan sát]`. `$0` = cả đoạn khớp `[đề xuất]`.
- `:R1&&R2` (`:正文卷[\s\S]*?/dl&&href ="([^"]+)">([^<]+)`): `[UNKNOWN]`; khuyến nghị xích: `R1` lấy vùng (khớp đầu), `R2`
  chạy trong vùng đó để lấy mục.
- Cờ nội tuyến (`:(?s)(\d+)" class=…`) giữ nguyên.

#### §2.13.1 Tiền tố `-` và `+` của rule danh sách

- `-` ở đầu rule danh sách: **đảo** danh sách kết quả (50 chuỗi rule danh sách, ví dụ `-class.chapter@tag.li`,
  `-@js:var H='https://www.shenwen.org';…`) `[quan sát]`. Không thấy `-` đầu ở rule không phải danh sách (trừ
  `checkKeyWord` dạng gỡ lỗi `--url`, §5.10).
- `+` ở đầu rule danh sách (41 chuỗi: `+@js:…`, `+<js>…`, `+@css:.bookbox`): `[UNKNOWN]`. Khuyến nghị bóc `+` và giữ thứ tự.

### §2.14 Kết quả JS trong đường ống `[đề xuất]`

| Giá trị JS trả về | Thành nội dung cho phân đoạn sau | Khi là kết quả cuối `getString` | `getElements` / `getStringList` |
|---|---|---|---|
| `undefined` / `null` | rỗng | `""` | `[]` |
| chuỗi | chuỗi (parse lại theo chế độ phân đoạn sau) | chuỗi | chuỗi parse được thành mảng JSON → các phần tử; ngược lại `[chuỗi]` |
| số / bool | chuỗi | chuỗi | `[chuỗi]` |
| mảng JS | danh sách | các phần tử chuyển chuỗi, nối `\n` | các phần tử (object giữ nguyên để rule con dùng JSONPath ngầm) |
| object JS | JSON | văn bản JSON | `[object]` |
| phần tử / danh sách phần tử HTML (shim jsoup, §6.8) | HTML | chữ (`text`) của phần tử | các phần tử |

Bằng chứng: danh sách chương dựng bằng JS trả mảng object
(`+@js:org.jsoup.Jsoup.parse(result).select(' #newlist a').toArray().sort().map(x=>({n:x.text(),u:x.attr('href')}))`, rồi
`chapterUrl: u`) `[quan sát]`; danh sách JS trả `JSON.stringify(json)` rồi `$.[*]` hoặc khoá trần `[quan sát]`.

### §2.15 Trường URL `[đề xuất]`

Trường URL: `bookUrl`, `coverUrl`, `tocUrl`, `chapterUrl`, `nextTocUrl`, `nextContentUrl`, `downloadUrls`; thêm
`java.getString(rule, content, true)` (tham số `isUrl`) `[tài liệu jsHelp.md]`.

1. Lấy chuỗi, trim.
2. Có khối option `,{…}` ở cuối (§3.6) thì chỉ ghép phần trước khối; khối giữ nguyên.
3. Ghép với URL nền = URL **cuối cùng** (sau chuyển hướng) của trang đang phân tích; nội dung JSON/JS dùng URL của request
   sinh ra nội dung đó; không có thì dùng `bookSourceUrl` (§1.4).
4. Không ghép: `data:` (§3.11), `http(s)://…`. `//host/…` → thêm scheme của URL nền.
5. `javascript:…`, `#`, chuỗi rỗng → coi như rỗng.

### §2.16 Ví dụ biên tổng hợp

| Rule | Trường | Nội dung | Kết quả mong đợi |
|---|---|---|---|
| `text` | `chapterName` | `<a href="/1">第1章</a>` | `第1章` |
| `@href` | `bookUrl` | mục `<a class="m-book-row" href="/b/1">` | `https://host/b/1` |
| `img@data-src\|\|img@src` | `coverUrl` | `<img src="/c.jpg">` | `https://host/c.jpg` |
| `tag.td.-1@text` | `author` | hàng 4 ô | chữ ô cuối |
| `tr!0` | `bookList` | bảng 11 hàng | 10 hàng (bỏ hàng đầu) |
| `.autor2[2:1]@text##.*：` | `kind` | 3 phần tử (§2.8.3) | `武侠\n2026-10-21` |
| `.mubtn@a@href##/(\d+)##https://wap.sou78.com/info.php?aid=$1###` | `tocUrl` | `href="/chapter/2/"` | `https://wap.sou78.com/info.php?aid=2` |
| `第{{$.chapterNum}}章` | `lastChapter` | `{"chapterNum":12}` | `第12章` |
| `name` | `name` | mục JSON `{"name":"A"}` | `A` |
| `$.free@js:result?false:true` | `isVip` | `{"free":true}` | `false` (không VIP) |
| `-class.chapter@tag.li` | `chapterList` | 3 `li` | 3 mục, thứ tự đảo |
| `:<dd><a href="([^"]*)[^>]*>([^<]*)` + `$1`/`$2` | `chapterList` | HTML | mỗi `dd` một chương |
| `a.0@text@put:{u:"a.0@href"}` | `name` | mục | tên; biến `u` = href |
| `/pc/book/{$.id}/catalog\|\|/pc/book/{$.bookId}/catalog` | `bookUrl` | `{"bookId":7}` | `https://host/pc/book/7/catalog` |

---

## §3. URL

### §3.1 Nơi dùng "rule URL"

`searchUrl`, từng mục URL của `exploreUrl`, và kết quả các trường URL (§2.15) khi được **gửi đi** (`bookUrl`, `tocUrl`,
`chapterUrl`, `nextTocUrl`, `nextContentUrl`), cùng chuỗi URL truyền vào `java.ajax`/`java.connect`/`java.ajaxAll`
(`java.ajax(url + ',' + JSON.stringify(opts), 15000)`) `[quan sát]`. Mọi nơi dùng chung thuật toán §3.2.

Dạng `searchUrl` trên 3406 nguồn loại 0 (đếm nguồn): URL tuyệt đối 1340, bắt đầu bằng `/` 993, bắt đầu bằng `{{` 163,
tương đối không `/` 164 (`search.html?searchkey={{key}}`), `@js:` 150, `<js>` 58, rỗng 538; có khối option `,{…}` 1009
`[quan sát]`.

### §3.2 Thuật toán dựng request `[đề xuất, thứ tự có bằng chứng ở từng bước]`

Đầu vào: chuỗi URL thô `U`, ngữ cảnh (`key`, `page`, `source`, `book`, `chapter`, `baseUrl`, `result`).

1. **JS sinh URL.** Tách `U` thành phân đoạn như §2.2. Chạy lần lượt: phân đoạn chữ là chuỗi, phân đoạn JS nhận
   `result` = chuỗi tích luỹ trước nó, giá trị trả về thay chuỗi tích luỹ. Placeholder trong **mã JS** không được thay
   trước: `…search.php,{"body": "keyboard={{key}}&show=title…","method": "POST"}\n@js:\nso = String(result).replace("{{key}}", key);`
   cho thấy `result` vẫn còn nguyên `{{key}}` khi JS chạy `[quan sát]`. Mọi `{{…}}` trong mã JS của `searchUrl` mẫu đều
   nằm trong chuỗi ký tự, nên sống sót tới bước 3.
2. **Danh sách trang `<a,b,…>`** (§3.5).
3. **Thay `{{…}}`** trong toàn chuỗi (cả trong khối option), theo §2.7: `{{key}}`, `{{page}}`, biểu thức JS, rule có dấu
   hiệu. Phải thay **trước** khi parse option: option có `"body": "searchkey={{java.put("key",key)}}"` (nháy kép lồng) chỉ
   thành JSON hợp lệ sau khi thay `[quan sát]`.
4. **Tách option.** Tìm `,{` đầu tiên ở mức ngoài cùng sau phần URL; phần sau là object option, parse lenient (§1.2.1).
   Parse hỏng → coi như không có option, cả chuỗi là URL, ghi log.
5. **Chạy option `js`** (§3.6) nếu có.
6. **Ghép URL tuyệt đối** (§3.7), **mã hoá** query/body theo charset (§3.8).
7. **Gộp header** (§3.10) và gửi (§4).

Hệ quả của thứ tự 1 → 3: giá trị thay vào không thể phá cú pháp JS (ví dụ từ khoá có dấu nháy), vì JS đã chạy xong.

### §3.3 JS sinh URL (`@js:` / `<js>` trong rule URL)

- Biến: `key`, `page`, `result`, `baseUrl`, `source`, `java`, `cookie`, `cache`, `book` (nếu có) (§6.2).
- Giá trị trả về là chuỗi URL, có thể kèm `,{…}` dạng chuỗi: `` `${backend}/69/search?key={{key}}&page={{page}}` ``,
  `url + "," + JSON.stringify({"method":"POST","body":…})` `[quan sát]`.
- Mẫu `<js>…</js>` đứng sau phần URL: `https://wap.maxreader.la/search/result.html?searchkey={{key}}<js>…</js>` (JS nhận
  URL trước nó làm `result`).
- JS trả về **object** `{url, method, body}` (`@js:{ … return { method: 'POST', url: …, body: … } }`, nguồn `可乐小说`
  bộ 1298 — ghi chú của nguồn nói "ghép theo giao diện đã thử, hãy kiểm lại", nên đây **không** là bằng chứng về engine
  gốc) → `[đề xuất]` mở rộng: object có khoá `url` thì coi như `url` + option là các khoá còn lại.
- Mã JS có `return` ở cấp cao nhất (`@js:{ … return … }`, 5 chuỗi): JS chuẩn báo lỗi cú pháp. `[đề xuất]` thử lại bằng cách
  bọc thành `(function(){ … })()`.

### §3.4 Placeholder trong URL

| Placeholder | Nghĩa | Bằng chứng |
|---|---|---|
| `{{key}}` | từ khoá tìm kiếm **thô** (chưa mã hoá; mã hoá ở §3.8) | 2606 lần trong `searchUrl` |
| `{{page}}` | số trang, **bắt đầu từ 1** | 527 lần; `{{page-1}}` (32), `{{(page-1)*15}}` (8) cho API đếm từ 0 |
| `{{JS}}` | biểu thức JS | `{{java.encodeURI(key, 'gbk')}}`, `{{(page-1)*20}}`, `{{Date.now()}}`, `{{source.getKey()}}` |
| `{{cookie.removeCookie(…)}}` | tác dụng phụ, cho chuỗi rỗng | 56 + 22 lần |
| `{{$.x}}`, `{$.x}`, `{{@@…}}` | rule trên nội dung hiện hành (ở trường URL lấy từ trang) | `/novel/{{$.novelId}}?isSearch=1` |

`key`/`page` cũng là biến JS trong `{{…}}` và trong JS sinh URL `[tài liệu ruleHelp.md]` (ví dụ dùng `page==1`, `key`).

### §3.5 Danh sách trang `<a,b,…>`

- Cú pháp: `<` mục `,` mục … `>` trong URL; trang `N` dùng mục thứ `N` (đếm từ 1) `[quan sát]`. Gần như mọi mẫu có 2 mục,
  mục đầu rỗng: `/<,page/{{page}}/>?s={{key}}` → trang 1 `/?s=…`, trang 2 `/page/2/?s=…`. Tần suất trong `searchUrl` +
  `exploreUrl` (lần): `<,index_{{page}}.html>` 528, `<,_{{page}}>` 454, `<,{{page}}>` 87, `<,{{page}}.html>` 76,
  `<,-{{page}}>` 48, `<,?page={{page}}>` 41, `<?,index.php?page={{page-1}}>` 18.
- `N` lớn hơn số mục → dùng **mục cuối** `[UNKNOWN]`. Đây là cách duy nhất để mẫu hai mục chạy được từ trang 3 trở đi.
- Nhận dạng: `<…>` chứa ít nhất một `,`, không phải `<js>`/`</js>`, chỉ xét trong rule URL `[đề xuất]`.

### §3.6 Khối option `,{…}`

Đếm khoá option sau `,{` trên mọi trường (lần, nguồn loại 0) `[quan sát]`; nghĩa `[tài liệu]` khi có ghi.

| Khoá | Lần | Giá trị quan sát | Nghĩa | Đợt |
|---|---|---|---|---|
| `method` | 1032 | `POST` 736, `post` 73, `GET` 5, `get` 2 (trong searchUrl) | phương thức, không phân biệt hoa thường; mặc định GET | 1 |
| `body` | 1022 | chuỗi form (`searchkey={{key}}`), chuỗi JSON (`'{"searchTerms":"{{key}}",…}'`), **object** (`{"bookId": {{$.bookId}}}`) | thân request (§3.9) | 1 |
| `charset` | 487 | `gbk` 189, `GBK` 76, `utf-8` 74, `UTF-8` 52, `gb2312` 40, `""` 16, `GB2312` 6, `gb18030` 5, `UTF8`, `utf8` | bảng mã (§3.8, §4.5); rỗng = không đặt | 1 |
| `headers` | 113 | object; hoặc **chuỗi** JSON (`"{os:'pc'}"`, 321 lần `"headers": "`) | header riêng request, đè header nguồn | 1 |
| `webView` | 221 | `true` 38, `false` 1 (searchUrl); `"webView":true` ở `chapterUrl` 85 lần | tải bằng trình duyệt ẩn (§4.4) | 1 |
| `webViewDelayTime` | 2 | `2500` | chờ thêm (ms) sau khi trang tải xong `[quan sát tên]` | 1 (cùng webView) |
| `js` | 16 | `"java.toast('正在加载详情页，请稍等！');"`, `"let v = java.ajax(java.url)…;java.headerMap.put('Cookie', …);java.url"` | JS chạy lúc dựng URL; đọc/sửa `java.url`, `java.headerMap` `[tài liệu ruleHelp.md]` | 1 |
| `type` | ~50 (ngoài `loginUi`) | `"jjwx"`, `"qm"`, `"qingtian3"`, `"maoyankanshu"` | tài liệu: đuôi tệp khi tải tệp (loại 3) `[tài liệu ruleHelp.md]`; ở nguồn chữ là nhãn tự đặt, thường đi với `data:` | lưu, không tác dụng |
| `retry` | 0 | – | `[UNKNOWN]`; chấp nhận số nguyên, số lần thử lại khi lỗi mạng | 1 (nhẹ) |
| `proxy` | – | – | chỉ thấy trong header theo tài liệu (§3.10) | – |

- **Option `js`** `[tài liệu ruleHelp.md]`: chạy khi phân tích URL; JS thêm header bằng `java.headerMap.put(tên, giá trị)` và
  sửa URL bằng cách gán lại `java.url` (corpus: `java.headerMap.put('Cookie', 'is_human='+encryptedCookieValue)`). `[UNKNOWN]` giá trị trả về có thay URL không (mẫu corpus kết thúc bằng `java.url`, và
  `"js":"book?result:toReview(…)"` trả biểu thức). Khuyến nghị: sau khi chạy, nếu giá trị trả về là chuỗi không rỗng thì
  dùng làm URL; ngược lại dùng `java.url`. Trong JS này, `result` = URL hiện tại.
- Khoá lạ → bỏ qua; khoá viết hoa thường lẫn lộn (`Method`) → không gặp; `[đề xuất]` so khoá không phân biệt hoa thường.

### §3.7 URL tương đối và URL nền

- Ghép theo RFC 3986 với URL nền: `searchUrl`/`exploreUrl` → `bookSourceUrl` (fragment bị bỏ, §1.4); trường URL lấy từ
  trang → URL cuối của trang đó (§2.15) `[đề xuất]`.
- Chuỗi không có scheme và không bắt đầu bằng `/` (`search.html?searchkey={{key}}`, `page/{{page}}?s={{key}}`, 164 nguồn) →
  tương đối với thư mục của URL nền (`https://host/` + `search.html…`) `[đề xuất]`.
- `{{source.getKey()}}search/result.html?…` (không `/` giữa) dựa vào việc `bookSourceUrl` kết thúc bằng `/` `[quan sát]`:
  không tự chèn `/`.

### §3.8 Mã hoá query và form theo charset `[UNKNOWN chi tiết, khuyến nghị]`

Bằng chứng: `searchUrl: /modules/article/search.php?keywords=all&searchkey={{key}}&submit=搜索,{"charset":"gbk",…}` có cả
chữ Hán hằng (`搜索`) lẫn `{{key}}` trong query, và tác giả không tự mã hoá → engine phải mã hoá **toàn bộ** query theo
`charset` `[quan sát]`. Ngược lại có tác giả tự mã hoá trước: `{{java.encodeURI(key,'gbk')}}` (5 lần).

Thuật toán khuyến nghị:

1. Charset = option `charset` (không phân biệt hoa thường; `utf8` ≡ `utf-8`; `gb2312`/`gbk` → dùng GB18030 để mã hoá được
   đủ ký tự); không có → UTF-8.
2. Query: tách theo `&`, mỗi phần tách tên/giá trị ở `=` đầu tiên; với tên và giá trị: giữ nguyên chuỗi `%XX` hợp lệ đã có,
   giữ ký tự không cần mã hoá (`A–Z a–z 0–9 - _ . ~` và các ký tự phân cách hợp lệ trong giá trị như `,`, `:`, `/`), còn lại
   mã hoá thành byte theo charset rồi `%XX`. Dấu cách → `%20` trong query.
3. Body form (`application/x-www-form-urlencoded`): như query, dấu cách → `+` `[đề xuất]`.
4. Body JSON: không mã hoá, gửi byte UTF-8 (hoặc charset nếu có).
5. Đường dẫn (path): mã hoá ký tự không phải ASCII theo UTF-8 (`https://www.mingzw.net/mzwlist/{{key}}<,_{{page}}>.html` đặt
   từ khoá trong path).

### §3.9 Thân request và Content-Type

- `body` là object JSON → tuần tự hoá thành JSON `[đề xuất]`.
- `body` là chuỗi: gửi nguyên (sau mã hoá §3.8 nếu là form).
- Content-Type: header (nguồn hoặc option) có thì dùng; corpus có 18 nguồn tự đặt (`application/x-www-form-urlencoded` 38 lần,
  `application/json` 36 lần) `[quan sát]`. Không có: `[UNKNOWN]`. Khuyến nghị: `body` là object → `application/json`;
  chuỗi → `application/x-www-form-urlencoded` kèm `charset` nếu có. (Việc nhiều tác giả tự thêm `application/json` khi body là
  chuỗi JSON gợi ý mặc định gốc không phải JSON.)
- `method` GET mà có `body` → bỏ body `[đề xuất]`. Không gặp `body` mà thiếu `method` trong `searchUrl`; nếu gặp → POST `[đề xuất]`.

### §3.10 Header nguồn

Dạng `header` (nguồn có giá trị, đếm nguồn) `[quan sát]`: JSON object 957 (882 hợp lệ, 75 cần lenient), `@js:` 83, `<js>` 25,
dạng khác 27.

1. `@js:…` / `<js>…</js>`: chạy JS (biến như §6.2), kết quả là chuỗi JSON (`JSON.stringify({...})`) hoặc object → map.
   `@js:wrHeaderJson(source);`, `@js:JSON.stringify(yuluHeaders(java))` gọi hàm trong `jsLib`.
2. JSON (lenient, §1.2.1). Giá trị có thể chứa `{{…}}` (33 nguồn): `"Referer": "{{baseUrl}}"`, `"referer": "{{source.getKey()}}"`,
   `'Cookie': "{{cookie.getCookie(source.getKey())}}"`, `"Referer": "…word={{encodeURIComponent(key)}}&"` → thay theo §2.7
   **tại thời điểm gửi** `[quan sát]`. `baseUrl` trong ngữ cảnh này: `[UNKNOWN]`; khuyến nghị URL nền của ngữ cảnh hiện tại
   (trang đang phân tích; với `searchUrl`/`exploreUrl` là `bookSourceUrl`).
3. Dạng khác: chuỗi UA trần (`Mozilla/5.0 (Windows NT 10.0; …)`, 20 nguồn loại 0), dòng `User-Agent: …` / `Referer: https://www.dushu.com/`,
   `[]`. `[UNKNOWN]` hành vi gốc. Khuyến nghị: dòng `Khoá: Giá trị` → map; chuỗi bắt đầu bằng `Mozilla/` → `User-Agent`;
   còn lại bỏ qua và ghi log.
4. Khoá `proxy` (giá trị dạng `socks5://host:port`, `http://host:port`, có thể kèm `@tên@mật-khẩu`) là cấu hình proxy, không phải header
   `[tài liệu ruleHelp.md]`. Đợt 1: không gửi lên mạng, bỏ qua và ghi log `[đề xuất]`.
5. Tài liệu lưu ý khoá header phân biệt hoa thường và dạng đúng là `User-Agent`, `Referer` `[tài liệu ruleHelp.md]`; corpus vẫn
   có `user-agent` (37), `referer` (21) `[quan sát]`. Khuyến nghị gộp không phân biệt hoa thường (HTTP vốn vậy), ưu tiên theo
   thứ tự: mặc định < header nguồn < `headers` option < `java.headerMap` (option `js`).
6. Không có header nguồn (2454 nguồn loại 0): UA mặc định `[đề xuất]` là UA **Chrome Android di động** (tác giả viết rule
   trên ứng dụng Android; `java.getWebViewUA()` trả UA WebView Android `[tài liệu jsHelp.md]`), không dùng UA Safari iOS
   (trang có thể trả HTML khác).
7. Header nguồn đánh giá **mỗi request** (JS header có thể sinh UUID/thời gian; có nguồn tự cache giá trị bằng `source.put`)
   `[quan sát]`.

### §3.11 URL `data:`

- 34 nguồn loại 0 dùng URL dạng `data:[mime];base64,<b64>[,{option}]` làm `chapterUrl`/`bookUrl` để "chở" dữ liệu không cần
  tải (`data:;base64,${qtcontent},{"type":"qingtian3",…}`, `data:vipContent;base64,…,{"type":"jjwx"}`) `[quan sát]`.
- 28 nguồn trong số đó đọc kết quả bằng `java.hexDecodeToString(result)`, kiểu
  `if (String(baseUrl).startsWith("data:")) { let res = JSON.parse(java.hexDecodeToString(result)); … }` → "thân phản hồi"
  của URL `data:` có vẻ là **chuỗi hex của byte đã giải base64** `[quan sát]`. `[UNKNOWN]`: luôn là hex, hay chỉ khi có option
  `type`.
- Đợt 1: **hoãn**. Khi gặp: không gửi mạng, báo "URL data: chưa hỗ trợ". Đợt 2 cài theo hướng hex và đo bằng bộ nghiệm thu.

---

## §4. Mạng

### §4.1 `concurrentRate`

- Hai dạng `[tài liệu ruleHelp.md]`: `"N"` = khoảng cách tối thiểu N ms giữa hai lần truy cập (`1000` = 1 giây/lần);
  `"N/M"` = tối đa N lần trong M ms (`20/60000`).
- Giá trị gặp (67 nguồn) `[quan sát]`: `5` (12), `1000` (11), `3` (11), `1500` (8), `500` (4), `30/5000` (3), `1/2000`,
  `20/60000`, `10/5000` (2 mỗi loại), `1`, `0`, `3/1`, `3400`, `800`, `3000`, `50`, `2/1000`, `5/1000`, `50/60000`.
  Giá trị nhỏ như `3`, `5` theo tài liệu là 3–5 ms (gần như không giới hạn). Theo tài liệu, không đoán "số luồng".
- Phạm vi: **mỗi nguồn** (mọi request của nguồn đó, gồm `java.ajax` trong JS) `[đề xuất]`.
- `0`, rỗng, không parse được → không giới hạn.
- Ghép với nguyên tắc của FreeBook: tải truyện vẫn tuần tự từng truyện; `concurrentRate` chỉ thêm khoảng chờ.

### §4.2 Cookie và `enabledCookieJar`

- `enabledCookieJar = true` → lưu cookie từ mọi `Set-Cookie` và gửi lại theo tên miền `[tài liệu ruleHelp.md]`. Corpus: 1881 nguồn
  loại 0 bật, 1525 tắt `[quan sát]`.
- Tắt: `[UNKNOWN]` cookie có được gửi không. Khuyến nghị: không tự lưu `Set-Cookie`, nhưng vẫn gửi cookie mà JS đã đặt bằng
  `cookie.setCookie` và cookie đồng bộ từ WebView.
- Kho cookie theo tên miền, dùng chung cho request HTTP, `cookie.*` (§6.7) và WebView ẩn (đồng bộ hai chiều sau mỗi lần tải
  WebView) `[đề xuất]`.
- Header `Cookie` viết tay (nguồn/option) gộp với cookie trong kho, khoá trùng thì bản viết tay thắng `[UNKNOWN]`.

### §4.3 Thử lại, thời gian chờ

- Không có `retry` trong corpus. Mặc định `[đề xuất]`: không tự thử lại request nội dung chính; lỗi mạng tạm thời (timeout,
  mất kết nối) thử lại 1 lần. `retry` trong option (nếu có) → số lần thử lại.
- Timeout `[đề xuất]`: 15 giây kết nối/đọc cho request thường, 30 giây cho WebView. `java.ajax(url, 15000)` có tham số thứ hai
  dạng số (1 lần) → coi là timeout ms `[quan sát]`; `rssRuleHelp.md` cũng có `ajaxAwait(url, callTimeout)` `[tài liệu]`.

### §4.4 WebView (`webView: true`)

- Option `webView: true` → tải URL bằng trình duyệt ẩn thay vì HTTP thường; 97 nguồn loại 0 có `"webView": true` dạng JSON
  (census đếm 165 khi gộp các cách viết) `[quan sát]`. Nguồn thử tay `🎉起点中文网` (bộ 1298) cần nó cho `searchUrl`.
- Hành vi `[UNKNOWN chi tiết, khuyến nghị]`: nạp URL (kèm header, POST body nếu có) → chờ sự kiện tải xong → chờ thêm
  `webViewDelayTime` ms nếu có → nếu là request nội dung chương và `ruleContent.webJs` không rỗng thì chạy `webJs` trong
  trang và lấy giá trị trả về làm thân; ngược lại thân = `document.documentElement.outerHTML` → tiếp tục như phản hồi HTTP.
  `webJs` mẫu: `getDecode();$('#content').html();` (5), IIFE trả `innerText` hoặc `null` (`null` → chờ rồi thử lại tối đa vài
  lần `[đề xuất]`).
- `sourceRegex` (bắt URL tài nguyên trong WebView): đợt 2.
- Nối với FreeBook: tái dùng `WebViewLoader`/`WebContentConfigurator` (đã có cho tiện ích JS). WKWebView chạy trên main thread:
  luồng JS (không phải main) được phép **chờ** kết quả; tuyệt đối không chờ đồng bộ trên main thread (quy ước repo) `[đề xuất]`.

### §4.5 Bảng mã phản hồi `[UNKNOWN, khuyến nghị]`

Thứ tự: `charset` trong header `Content-Type` → option `charset` → BOM → `<meta charset>` / `<meta http-equiv>` trong 2 KB đầu →
UTF-8; giải UTF-8 hỏng thì thử GB18030. Lý do đặt header trước option: option `charset` chủ yếu dùng cho **mã hoá request**
(§3.8); khi server khai bảng mã thì đó là thông tin đáng tin nhất.

### §4.6 Mã lỗi HTTP `[UNKNOWN, khuyến nghị]`

- Luồng chính (tìm, khám phá, thông tin, mục lục, nội dung): `2xx` → xử lý; `3xx` → theo chuyển hướng; `≥ 400` → lỗi có mã
  (`HTTP 403`) và thân giữ lại cho màn gỡ lỗi. Trang xác minh (Cloudflare/captcha) thường là 403/503.
- Trong JS: `java.ajax` trả thân bất kể mã; `java.connect`/`get`/`post`/`head` trả đối tượng phản hồi có mã (§6.4) để JS tự xử lý
  (`if(/^30/.test(response.statusCode()))` `[quan sát]`).

### §4.7 Chuyển hướng và URL nền

- Request luồng chính và `java.ajax`/`java.connect` **đi theo** chuyển hướng; URL nền cho bước sau = URL cuối `[đề xuất]`.
  `java.connect(url).raw().request().url()` lấy URL sau chuyển hướng `[tài liệu ruleHelp.md]`.
- `java.get(url, headers)` / `java.post(url, body, headers)` **không** đi theo chuyển hướng: tài liệu nói chúng "dùng để chặn
  chuyển hướng", ví dụ lấy `header("Location")` `[tài liệu ruleHelp.md]`. Corpus dùng đúng như vậy
  (`response = java.get(url,{…}); if(/^30/.test(response.statusCode())){ source.setVariable(response.header("Location")…`) `[quan sát]`.
- Tìm kiếm bị chuyển thẳng tới trang sách (một kết quả): xem §5.1.4.

### §4.8 `loginCheckJs` và đăng nhập

Đợt 2. Đợt 1 không chạy `loginCheckJs` (nó được thiết kế chạy sau mỗi request) và không gửi header đăng nhập; nguồn có
`loginUrl` vẫn chạy được phần không cần đăng nhập `[đề xuất]`.

---

## §5. Luồng

Tổng quan: **Tìm kiếm / Khám phá** → danh sách "sách tìm thấy" → **Thông tin** (`ruleBookInfo`) → **Mục lục** (`ruleToc`) →
**Nội dung** (`ruleContent`). Mỗi bước tạo một ngữ cảnh JS có `source`, `java`, `cookie`, `cache` và `book`/`chapter` khi có (§6.2).

### §5.1 Tìm kiếm

#### §5.1.1 Thuật toán `[đề xuất]`

1. Dựng request từ `searchUrl` với `key` (từ khoá người dùng, đã trim) và `page` (1, 2, …) theo §3.2.
2. Tải; nội dung = phản hồi (JSON nếu thân là JSON, ngược lại HTML).
3. `bookList` (`getElements`) → các mục. Với mỗi mục, đánh giá `name`, `author`, `kind`, `coverUrl`, `intro`, `lastChapter`,
   `wordCount`, `bookUrl` (`getString`); `bookUrl`, `coverUrl` theo §2.15.
4. Bỏ mục có `name` rỗng **hoặc** `bookUrl` rỗng `[đề xuất]` (4 nguồn có `bookList` mà không có `bookUrl`, `[UNKNOWN]` hành vi
   gốc).
5. Phân trang: trang kế chỉ tải khi người dùng cuộn tới cuối. Dừng khi trang trả 0 mục, hoặc mọi `bookUrl` của trang đã gặp
   (URL không có `{{page}}` sẽ trả lại trang 1), hoặc đạt giới hạn (ví dụ 10 trang) `[đề xuất]`.
6. Không lọc theo độ khớp với từ khoá (tài liệu không nói) `[đề xuất]`; giao diện có thể xếp kết quả khớp tên lên trước.

#### §5.1.2 Trường của "sách tìm thấy"

`name`, `author`, `kind`, `coverUrl`, `intro`, `lastChapter`, `wordCount`, `bookUrl`, cùng nguồn (khoá `bookSourceUrl`) và
kho biến của mục (§5.7). Các tên trường này khớp danh sách thuộc tính sách trong tài liệu (`name`, `author`, `kind`, `coverUrl`,
`intro`, `latestChapterTitle`, `bookUrl`, `tocUrl`, `origin`, `originName`, `variable`…) `[tài liệu jsHelp.md]`.

Làm sạch `[đề xuất]`: trim; gộp khoảng trắng liên tiếp trong `name`/`author`; `intro` đổi `<br>`, `</p>` thành xuống dòng, bỏ
thẻ, giải thực thể HTML; `kind` tách nhãn theo `,`, `，`, `\n`, bỏ rỗng/trùng. Không tự bỏ tiền tố như `作者：` (tác giả tự
viết `##作者：` khi cần `[quan sát]`).

#### §5.1.3 Từ khoá đặc biệt

Một số nguồn tự hiểu tiền tố trong từ khoá (`if (key.startsWith("@") …) // tìm theo tác giả`, `if(/^##/.test(key))`) `[quan sát]`.
Engine truyền nguyên từ khoá, không tự xử lý tiền tố.

#### §5.1.4 Tìm kiếm rơi thẳng vào trang sách `[UNKNOWN]`

Một số trang chuyển hướng thẳng tới trang sách khi chỉ có một kết quả; tài liệu có ví dụ lấy URL sau chuyển hướng bằng
`java.connect(url).raw().request().url()` `[tài liệu ruleHelp.md]`. Khuyến nghị: nếu `bookList` cho 0 mục **và** URL cuối của
phản hồi khớp `bookUrlPattern` (§5.9), coi trang là trang sách: chạy `ruleBookInfo` lên đó để ra đúng một kết quả với
`bookUrl` = URL cuối.

### §5.2 Khám phá

#### §5.2.1 Ba dạng `exploreUrl`

Đếm trên 3406 nguồn loại 0 `[quan sát]`: rỗng 1643; **mảng JSON** 1000 (967 hợp lệ, 33 cần lenient); **văn bản** `tên::url`
499; **JS** `@js:` 218 + `<js>` 46.

1. **Mảng JSON** (khuôn mẫu trong `ruleHelp.md` `[tài liệu]`): phần tử `{"title", "url", "style"}`; 36 228 phần tử đều có
   `title` và `url`, 36 015 có `style` (`layout_flexGrow`, `layout_flexBasisPercent` là tỉ lệ chiều rộng ô, thêm
   `layout_flexShrink`, `layout_alignSelf`, `layout_wrapBefore`) `[quan sát]`. Phần tử có thêm khoá request (`"webView": true`,
   `method`, `body`; 16 phần tử) → `[UNKNOWN]`; khuyến nghị gộp vào option của URL mục đó.
2. **Văn bản**: mỗi mục `tên::url`, phân cách bằng **xuống dòng** (473 nguồn) hoặc `&&` (14) `[quan sát]`, ví dụ corpus
   `玄幻小说::/xuanhuan/{{page}}.html`; `debugHelp.md` cũng dùng dạng `tên::url` cho mục khám phá `[tài liệu]`. Tách tại `::`
   **đầu tiên**; trim tên (có mẫu `百合    ::/shuku/…`). URL của mục có thể là JS: `首页推荐::<js>zzGet(java,cookie,'/')</js>`.
3. **JS**: chạy (biến: `source`, `java`, `cookie`, `cache`, `baseUrl` = `bookSourceUrl`; không có `key`/`page`), kết quả là:
   mảng object như dạng 1 (`result.push({"title": t, "url": u, "style": …})`), chuỗi JSON của mảng đó
   (`JSON.stringify(cats)`), hoặc chuỗi văn bản dạng 2 (`list.join('\n')`) `[quan sát]`. Placeholder `{{page}}` trong chuỗi URL
   do JS sinh ra **không** được thay lúc chạy JS này: `url: host + '/wanjie/{{page == 1 ? "" : page + ".html"}}'` chỉ có
   nghĩa khi đã có `page` (lúc mở mục) `[quan sát]`.

#### §5.2.2 Nhận ra mục không phải URL

| Dấu hiệu | Số lần | Xử lý đợt 1 |
|---|---|---|
| `url` rỗng/`null`/chỉ có khoảng trắng | 1563 (mảng) + 113 (văn bản `tên::`) | **tiêu đề nhóm**, không bấm được |
| dòng văn bản không có `::` (`排行`, `********全部分类********`, `null`) | 43 | tiêu đề nhóm (bỏ dòng `null`) |
| phần tử có `type` khác URL: `"select"` (kèm `chars`, `default`, `action`), `"button"` (kèm `action`) | gặp ở nguồn JS dùng `infoMap` (21 nguồn), `java.refreshExplore()` (24 nguồn) | **ẩn** (đợt 2) |
| `url` bắt đầu bằng `@js:`/`<js>` | 350 | URL do JS sinh lúc mở mục: đợt 1 |

Chiều rộng ô: `layout_flexBasisPercent` (0…1) → tỉ lệ hàng; thiếu → mặc định `[đề xuất]`.

#### §5.2.3 Mở một mục

Dựng request từ `url` của mục như §3.2 với `page` = 1, 2, … (không có `key`) `[đề xuất]`; phân trang như §5.1.1 bước 5.

#### §5.2.4 Rule danh sách của Khám phá

- `ruleExplore` rỗng hoàn toàn nhưng `exploreUrl` có giá trị: **600** nguồn loại 0; tất cả đều có `ruleSearch.bookList` →
  Khám phá **dùng `ruleSearch`** `[quan sát]`.
- 12 nguồn có `ruleExplore.bookList` rỗng nhưng có trường khác (`⚡📂错层小说`: `ruleExplore.author: .author:contains(作者)@text##作者：`,
  không có `bookList`; `ruleSearch.bookList: .bookbox`). Đã curl
  `https://m.cuoceng.com/book/category/6b09b233-4d99-4f8f-aeb0-f9772e107d49/1.html`: trang khám phá có 12 phần tử `.bookbox`
  `[quan sát]`. `[UNKNOWN]` gốc thừa kế cả nhóm hay từng trường. Khuyến nghị **thừa kế từng trường**: trường của `ruleExplore`
  rỗng thì lấy trường cùng tên của `ruleSearch`. Cách này gồm luôn trường hợp 600 nguồn ở trên.
- `enabledExplore = false` → không hiện ở Khám phá.

### §5.3 Thông tin sách

#### §5.3.1 Thuật toán `[đề xuất]`

1. Tải `bookUrl` (option trong URL được tôn trọng).
2. Nếu `init` không rỗng: đánh giá `init` (`getElements`). Kết quả không rỗng → **phần tử/giá trị đầu tiên** thành nội dung hiện
   hành cho mọi trường sau. Bằng chứng `[quan sát]`: `init: $.data` (50 nguồn) rồi `name: $.name`; `init: id.maininfo` (8);
   `init: <js>… var og = …</js>` trả object, rồi rule con là khoá trần (`📂VIP中文`: `author: a`, `intro: i`); `init: @put:{…}`
   (105 lần) chỉ để lưu biến, rồi các trường đọc `@get:{n}`.
   - `init` chỉ gồm `@put:{…}` → không đổi nội dung hiện hành.
3. Đánh giá `name`, `author`, `kind`, `coverUrl`, `intro`, `lastChapter`, `wordCount`, `tocUrl`.
4. **Ghi đè**: giá trị không rỗng của `ruleBookInfo` thay giá trị từ tìm kiếm; rỗng thì giữ giá trị tìm kiếm.
5. `tocUrl` rỗng → mục lục nằm ngay trên trang sách: **dùng lại phản hồi** vừa tải, không tải lại; URL mục lục = URL cuối của
   trang sách. 1742/3004 nguồn loại 0 có nhóm này không có `tocUrl` `[quan sát]`.

#### §5.3.2 Trang sách mở trực tiếp

Sách mở từ URL dán vào (khớp `bookUrlPattern`) hoặc từ kệ: chạy §5.3.1 không có giá trị tìm kiếm.

#### §5.3.3 `canReName`

Giá trị gặp: `1`, `true`, `True` (67 nguồn có giá trị) `[quan sát]`; tài liệu không nói. `[UNKNOWN]` Khuyến nghị: với sách
**đã ở trên kệ**, khi làm mới thông tin chỉ ghi đè `name`/`author` nếu `canReName` truthy (§5.4.3); thêm sách mới thì luôn
dùng giá trị `ruleBookInfo`.

#### §5.3.4 Trường đặc biệt

- `coverUrl` có thể kèm `,{"headers":{…}}` (tài liệu: URL ảnh được nối thêm dấu phẩy và một object JSON có `headers`)
  `[tài liệu ruleHelp.md]` → tải ảnh bìa với header đó.
- `intro` có thể chứa HTML (`<br>{$.introduction}`, `&nbsp;`) và `<useweb>` + khối HTML/CSS (2 nguồn) → đợt 1: chuyển văn bản
  như §5.1.2, bỏ `<useweb>` `[đề xuất]`.
- `downloadUrls`: chỉ cho loại 3 → bỏ.

### §5.4 Mục lục

#### §5.4.1 Thuật toán `[đề xuất]`

1. (Đợt 2) chạy `preUpdateJs` nếu có (12 nguồn loại 0; ví dụ `java.refreshTocUrl()`; tài liệu: `java.reGetBook()`/`java.refreshTocUrl()`
   chỉ dùng được trước khi làm mới mục lục `[tài liệu jsHelp.md]`).
2. Tải trang mục lục (`tocUrl`, hoặc dùng lại trang sách, §5.3.1 bước 5).
3. `chapterList` (`getElements`, kèm `-` đảo, §2.13.1) → mục. Với mỗi mục: `chapterName`, `chapterUrl` (§2.15), `isVolume`, `isVip`,
   `isPay`, `updateTime`.
4. `chapterUrl` rỗng → URL chương = **URL trang mục lục** (truyện một trang: `chapterList: html`/`tag.html`/`title`,
   `chapterName: {{book.name}}`, 39 nguồn) `[quan sát]`.
5. Bỏ mục có `chapterName` **và** `chapterUrl` đều rỗng; mục có tên rỗng nhưng có URL → giữ, hiển thị số thứ tự `[đề xuất]`.
6. Phân trang `nextTocUrl` theo §5.6; chương của các trang nối theo thứ tự tải.
7. Đánh chỉ số `index` 0…n-1 theo thứ tự cuối cùng (dùng cho `chapter.index`, `book.durChapterIndex`).
8. (Đợt 2) `formatJs` (3 nguồn): chạy với `title`, `index` (mẫu `'第' + index + '章 ' + title.replace(…)`), kết quả thay tên
   chương `[quan sát]`; `[UNKNOWN]` `index` đếm từ 0 hay 1.

#### §5.4.2 Thứ tự và trùng lặp

- Giữ đúng thứ tự trang trả về; chỉ đảo khi có `-` (§2.13.1). `book.setReverseToc(...)` (27 lần) → đợt 2.
- **Không tự bỏ chương trùng** `[UNKNOWN]`. Lý do: nhiều trang có khối "chương mới nhất" ở đầu, tác giả tự cắt bằng chỉ số
  (`#list dd[12:-1]`, `tag.dd!0:1:2:3:4:5:6:7:8`) `[quan sát]`; bỏ trùng kiểu "giữ bản đầu" sẽ đẩy khối đó lên đầu mục lục và
  làm sai thứ tự. Bộ nghiệm thu đếm số `chapterUrl` trùng cho từng nguồn để quyết định đợt sau.

#### §5.4.3 Cờ `isVolume`, `isVip`, `isPay` và truthy

Giá trị gặp `[quan sát]`: khoá JSON (`volume`, `isVolume`, `chapterPrice`, `vip`, `isVip`, `$.isFree`, `$.needPay`), rule HTML
(`dt@text##正文`, `i@text`, `img@src`), JS trả bool (`$.free@js:result?false:true`, `<js>"{{$.type}}"=="volume"?true:false</js>`),
mẫu `¥{{$.is_free}}##¥true` (miễn phí → rỗng, còn lại `¥false` → VIP).

Luật truthy `[đề xuất]`: chuỗi kết quả sau trim, so không phân biệt hoa thường; **false** nếu thuộc `""`, `false`, `0`, `null`,
`undefined`, `no`; còn lại **true**. Mẫu `¥false` cho true, đúng ý tác giả.

- `isVolume` true → mục là **tiêu đề quyển**: hiển thị như mục chia nhóm, không tính là chương đọc được `[đề xuất]`.
- `isVip` true và không `isPay` → hiện biểu tượng khoá; vẫn cho mở (nhiều trang vẫn trả phần đọc thử) `[đề xuất]`.
- `updateTime` → chuỗi phụ hiển thị dưới tên chương (thời gian, số chữ: `{{$.words}} 字`) `[quan sát]`.

### §5.5 Nội dung

#### §5.5.1 Thuật toán `[đề xuất]`

1. Tải `chapterUrl` (option, WebView, `webJs` nếu có, §4.4).
2. `content` (`getString`) → chuỗi trang 1.
3. Phân trang `nextContentUrl` theo §5.6, với **URL dừng = URL chương kế tiếp** trong mục lục.
4. Nối nội dung các trang bằng `\n`.
5. Áp `replaceRegex` (§5.5.3) lên chuỗi đã nối.
6. Chuyển sang văn bản (§5.5.2) → đưa vào `ChapterTextNormalizer` của FreeBook (nguồn duy nhất chuẩn hoá văn bản chương).
7. `title` (nếu có) → tên chương lấy từ trang nội dung; chỉ dùng để hiển thị khi tên trong mục lục rỗng `[đề xuất]`.
8. Kết quả rỗng sau mọi bước → lỗi "nội dung rỗng" (không lưu bản rỗng).

Không tự xoá dòng đầu trùng tên chương: tác giả tự viết `##{{chapter.title}}` trong `replaceRegex`/`content` (nhiều mẫu) nên
engine gốc có vẻ không làm việc này `[quan sát]`.

#### §5.5.2 HTML → văn bản `[đề xuất]`

`content` cuối cùng (sau bước 6, 1643 nguồn dùng `@html`, 486 `@textNodes`, 150 `@text`, 403 JS):

1. Chuẩn hoá xuống dòng `\r\n` → `\n`.
2. Nếu có thẻ HTML: `<br>`, `</p>`, `</div>`, `</h1>…</h6>`, `</li>`, `</tr>` → `\n`; bỏ `<script>`, `<style>` cùng nội dung;
   `<img src="…">` → giữ thành một dòng đánh dấu ảnh (đợt 1 có thể bỏ); bỏ mọi thẻ còn lại.
3. Giải thực thể HTML (`&nbsp;` → dấu cách, `&lt;`, `&#x…;`).
4. Trim từng dòng (gồm khoảng trắng toàn góc `　` đầu dòng), bỏ dòng rỗng.

#### §5.5.3 `replaceRegex`

- 729 nguồn loại 0 có giá trị; phần lớn dạng `##R` hoặc `##R##P` (bắt đầu bằng `##`, tức phần-chọn rỗng, §2.6), có placeholder
  (`##{{chapter.title}}|\(第.*页\)`, `##《{{book.name}}》`), có cả JS (`@js:if(java.get("原")==1){result}else{…}`) `[quan sát]`.
- Đánh giá như một rule `getString` với nội dung hiện hành = **chuỗi nội dung** (không phải HTML trang). `[UNKNOWN]` áp trên
  từng trang hay trên chuỗi đã nối; khuyến nghị trên chuỗi đã nối, **trước** bước HTML → văn bản (mẫu có `##<ul class="authi">…`
  nhắm thẻ HTML).
- `imageStyle`: chỉ ảnh hưởng hiển thị ảnh trong nội dung; đợt 1 lưu, không dùng (truyện tranh: §5.12).

### §5.6 Phân trang và chống lặp (`nextTocUrl`, `nextContentUrl`)

Hai kiểu đều gặp `[quan sát]`:

- **Từng trang một**: `text.下一页@href` (162 `nextTocUrl`, 415 `nextContentUrl`), `#linkNext@href`.
- **Tất cả trang một lúc**: `option@value` (77 nguồn, cộng 62 `option@value||text.下一页@href`, 18 `option!0@value`) trả URL
  **mọi** trang gồm cả trang hiện tại; JS dựng sẵn danh sách (`for(i=2;i<=page;i++){list.push(…)}`,
  `Array.from({ length: Number(result[0]) - 1 }, (_, i) => baseUrl.replace(…))`).

Thuật toán thống nhất `[đề xuất]`:

```
visited ← { chuẩnHoá(URL trang đầu) }
hàngĐợi ← [trang đầu]; kếtQuả ← []
lặp khi hàngĐợi khác rỗng và số trang < GIỚI_HẠN:
    trang ← lấy đầu hàngĐợi; tải (trang đầu có thể dùng lại phản hồi đã có)
    phần ← trích (mục lục: các chương; nội dung: chuỗi content)
    nếu phần trùng hệt phần của một trang trước → dừng (trang lờ tham số, trả lại cùng nội dung)
    thêm phần vào kếtQuả
    với mỗi u trong getStringList(ruleKế) theo thứ tự, sau §2.15:
        bỏ nếu rỗng, nếu chuẩnHoá(u) ∈ visited, hoặc nếu u = URL_DỪNG
        thêm chuẩnHoá(u) vào visited; đưa u vào cuối hàngĐợi
trả kếtQuả theo thứ tự tải
```

- **URL dừng (chỉ cho nội dung)** = URL chương kế tiếp trong mục lục; tài liệu có biến `nextChapterUrl` ("url chương tiếp theo")
  `[tài liệu jsHelp.md]`. Bằng chứng `[quan sát, đã curl]`: `⚡📂错层小说` có `nextContentUrl: #linkNext@href`; trang
  `https://m.cuoceng.com/book/633122f9-be7e-411f-981e-0bd4666d7a8b/f5f72556-facb-4cc6-a960-818f6850167f.html` có
  `<a … id="linkNext">下一章</a>` trỏ tới
  `/book/633122f9-be7e-411f-981e-0bd4666d7a8b/29439c3c-545b-4132-9664-4d439eedb230.html`, đúng URL chương 2 trong mục lục. Không
  dừng ở đó thì mỗi chương sẽ kéo theo toàn bộ truyện. Thêm: 76 nguồn có `nextContentUrl: text.下一章@href`.
- `chuẩnHoá`: URL tuyệt đối, bỏ fragment, bỏ khối `,{…}`; so phân biệt hoa thường ở path/query.
- `GIỚI_HẠN`: mục lục 200 trang, nội dung 30 trang `[đề xuất]`; vượt → dừng, ghi log, dùng phần đã có.
- Nhiều URL trong một lượt (kiểu "tất cả trang") được phép tải song song, nhưng vẫn **ghép theo thứ tự danh sách** và tuân
  `concurrentRate` `[đề xuất]`.
- So "trùng hệt": mục lục so danh sách `(tên, URL)`; nội dung so chuỗi đã trim.

### §5.7 Biến và phạm vi sống

| Kho | API | Sống | Bằng chứng |
|---|---|---|---|
| Biến nguồn (một chuỗi) | `source.getVariable()`, `source.setVariable(s)` | lưu bền theo nguồn; người dùng sửa được (gợi ý ở `variableComment`) | `[tài liệu jsHelp.md]`; 67 + 61 nguồn |
| Khoá-giá trị theo nguồn | `source.put(k, v)` (trả `v`), `source.get(k)` | `[UNKNOWN]` bền hay theo phiên; khuyến nghị lưu bền theo nguồn | ví dụ `return source.put('surl', …)` `[tài liệu ruleHelp.md]`; 11 nguồn |
| Biến rule | `java.put(k, v)` (trả `v`), `java.get(k)` (1 tham số), `@put`, `@get` | xem dưới | `[tài liệu jsHelp.md]`; 221/236 nguồn |
| Biến sách | `book.putVariable(k, v)`, `book.getVariable(k)`, thuộc tính `book.variable` (chuỗi) | lưu cùng sách | 19 + 25 nguồn `[quan sát]`; `variable` trong bảng thuộc tính sách `[tài liệu jsHelp.md]` |
| Biến chương | `chapter.putVariable(k, v)`, `chapter.getVariable(k)`, `chapter.variable` | lưu cùng chương | 10 nguồn `[quan sát]` |
| Bộ nhớ đệm | `cache.put/get/delete`, `putFile/getFile`, `putMemory/getFromMemory/deleteMemory` | §6.7 | `[tài liệu jsHelp.md]` |

**Phạm vi của biến rule** `[UNKNOWN]`. Quan sát dòng chảy `put → get` trong cùng nguồn (đếm khoá): cùng `ruleBookInfo` 776;
`ruleBookInfo → ruleToc` 117; `ruleToc → ruleToc` 76; `searchUrl → ruleSearch` 60; `ruleBookInfo → ruleContent` 57;
`ruleSearch → ruleBookInfo` 52; `ruleToc → ruleContent` 31; `ruleSearch → ruleToc` 26; `searchUrl → ruleContent` 22. Ví dụ
`🏷17k小说` đặt `book` ở `ruleSearch` rồi đọc ở `ruleToc`; `⚡📂茄子免费小说` đặt `headers` ở `searchUrl` rồi đọc ở `ruleContent`.
Vậy biến phải **sống từ tìm kiếm qua tới nội dung**.

Khuyến nghị:

1. Có ngữ cảnh sách (mục tìm kiếm/khám phá, thông tin, mục lục, nội dung) → `put` ghi vào **kho của sách** (mục tìm kiếm mang kho
   riêng; khi thêm vào kệ thì kho đi theo sách và được lưu bền).
2. Không có ngữ cảnh sách (đánh giá `searchUrl`/`exploreUrl`, header, `jsLib`) → ghi vào **kho phiên của nguồn**.
3. `get` tìm kho sách trước, rồi tới kho phiên của nguồn; khoá không có → **chuỗi rỗng** cho cả `@get` lẫn `java.get` `[UNKNOWN]`.
   Giá trị lưu luôn là chuỗi: `put(k, v)` lưu `String(v)`, nên `put(k, undefined)` lưu `"undefined"`. Mẫu
   `java.get("uid") != "undefined" ? java.get("uid") : "-1"` cho thấy tác giả từng gặp đúng chuỗi `"undefined"` `[quan sát]`.
4. `book.putVariable`/`getVariable` là API riêng theo tài liệu; `[UNKNOWN]` có chung kho với `java.put` không. Khuyến nghị: kho
   riêng, nhưng `java.get` không thấy khoá ở kho biến rule thì tra tiếp kho `book.getVariable`.
5. Kho phiên của nguồn sống tới khi app thoát; kho sách lưu bền cùng sách `[đề xuất]`.

### §5.8 `jsLib`

- Hai dạng `[tài liệu ruleHelp.md]`: chuỗi mã JS (91 nguồn), hoặc chuỗi JSON object `{tên: url}` (19 nguồn) mà ứng dụng tải
  về và dùng lại bản đã tải. URL thấy: `https://cdn.bootcss.com/crypto-js/3.1.9-1/crypto-js.min.js` (9), `https://qyyuapi.com/sy/js/<tên>/jsLib.js` (10, nguồn tranh) `[quan sát]`.
- Tài liệu cảnh báo: hàm trong `jsLib` có thể bị nhiều luồng gọi cùng lúc, biến toàn cục bị dùng chung; trong hàm không khai
  báo được biến toàn cục mới; biến toàn cục ngoài hàm không gán lại được (đối tượng bị "niêm phong") `[tài liệu ruleHelp.md]`.
- Hàm trong `jsLib` dùng `this.source`, `getConfig.call(this)` và được gọi không kèm `this`
  (`exploreUrl: <js> var host = getServerHost(); …`) → các biến môi trường (`source`, `java`, `cookie`, `cache`, `book`…) phải là
  **thuộc tính của đối tượng toàn cục** của ngữ cảnh JS, không chỉ là biến cục bộ `[quan sát]`.
- Khuyến nghị nạp `[đề xuất]`: mỗi "tác vụ" (một lượt tìm trong một nguồn, một lần lấy mục lục, một chương) tạo một ngữ cảnh JS,
  nạp `jsLib` **một lần** trước rule đầu tiên, dùng lại cho mọi rule của tác vụ. Dạng map: tải mỗi URL một lần, lưu đệm bền theo
  URL, nạp theo thứ tự khoá. Lỗi khi nạp `jsLib` → ghi log, vẫn chạy rule (rule sẽ lỗi ở chỗ gọi hàm thiếu).
- Mã dùng chung còn được nạp bằng `eval(String(source.bookSourceComment))` (110 lần) và `eval(String(source.loginUrl))` (16 lần)
  `[quan sát]`, nên `source.bookSourceComment`/`source.loginUrl` phải trả nguyên văn (§6.5).

### §5.9 `bookUrlPattern`

- Regex nhận diện URL trang sách của nguồn (605 nguồn có giá trị: `https://m\.libahao2\.com/book/\d+_\d+/?`,
  `https?:\/\/(www\.)?(shudugu\.org|sudugu520\.com|suduguu\.com)\/\d+(\/.*)?`) `[quan sát]`. Có giá trị rác (`已校验` ở 20 nguồn,
  `https://www.biquges.com` không phải regex đầy đủ).
- Dùng `[đề xuất]`: (1) mở sách từ URL người dùng dán: chọn nguồn có pattern khớp **toàn chuỗi** (không khớp thì thử khớp một phần);
  (2) §5.1.4. Regex lỗi → bỏ qua pattern.

### §5.10 `checkKeyWord`

- Từ khoá dùng khi **kiểm tra nguồn**: lúc thử tìm kiếm, ứng dụng lấy từ khoá nguồn khai sẵn, nguồn không khai mới dùng từ khoá
  người dùng gõ `[tài liệu SourceMBookHelp.md]`. 520 nguồn loại 0 có giá trị: tên truyện (`剑来` 79, `我的` 74, `深空彼岸` 15) `[quan sát]`.
- Một vài giá trị là lệnh gỡ lỗi kiểu `--https://www.bilinovel.net/novel/2353/83408.html`; `debugHelp.md` mô tả tiền tố `++url`
  (gỡ lỗi mục lục) và `--url` (gỡ lỗi nội dung), URL trần là trang sách, `tên::url` là khám phá, còn lại là từ khoá `[tài liệu]`.
- Đợt 1: bộ nghiệm thu và nút "Kiểm tra nguồn" dùng `checkKeyWord` (hoặc từ khoá mặc định); hiểu các tiền tố trên.

### §5.11 Giá trị trả về của mỗi bước

| Bước | Đầu ra |
|---|---|
| Tìm / khám phá | danh sách `{name, author, kind, coverUrl, intro, lastChapter, wordCount, bookUrl, origin=bookSourceUrl, originName=bookSourceName, variables}` |
| Thông tin | như trên (đã ghi đè) + `tocUrl` (rỗng = dùng lại trang sách) |
| Mục lục | danh sách `{index, title, url, isVolume, isVip, isPay, updateTime(tag), variables}` |
| Nội dung | chuỗi văn bản đã làm sạch (+ `title` nếu rule có) |

Tên thuộc tính khi JS đọc (`book.name`, `book.author`, `book.bookUrl`, `book.tocUrl`, `book.origin`, `book.durChapterIndex`,
`book.durChapterTitle`, `book.totalChapterNum`, `chapter.title`, `chapter.url`, `chapter.index`, `chapter.tag`…) theo bảng thuộc
tính trong `jsHelp.md` `[tài liệu]`, xem §6.6.

### §5.12 Tranh (loại 2) và video (loại 4): những gì ảnh hưởng tới nhập/lưu

Đợt 1 chỉ nhập, lưu nguyên JSON và nhận diện loại (§1.6); không chạy. Ghi lại để đợt sau thiết kế lưu trữ không phải đổi:

- **Tranh** (175 nguồn): `content` trả HTML chứa nhiều `<img src="…">` (120/175 nguồn tự dựng `<img`), mỗi ảnh là một trang `[quan sát]`.
  URL ảnh có thể kèm `,{"headers":{…}}` `[tài liệu ruleHelp.md]`. `imageStyle` (`FULL` hay gặp), `imageDecode` (5 nguồn, đợt 3),
  `nextContentUrl` (11 nguồn) để nối trang ảnh. Đi thẳng vào màn đọc tranh của FreeBook; **không** đi qua `ChapterTextNormalizer`,
  dịch, TTS (quy ước media của repo).
- **Video** (12 nguồn): `content` thường trả URL phát (`result = baseUrl;`, URL `.m3u8`), có `sourceRegex` (2) để bắt URL media trong
  WebView `[quan sát]`. Tiến độ (số giây) lưu như video tiện ích hiện có.
- Tên/nhóm có `漫`/`🎨` nhưng `bookSourceType = 0` (55/13 nguồn) vẫn là **chữ** (§1.6).

---

## §6. JS bridge

### §6.1 Engine và ngữ cảnh

- Ứng dụng gốc dùng Rhino 1.8.0 và cho JS gọi lớp Java `[tài liệu jsHelp.md]`. FreeBook dùng **JavaScriptCore**. Corpus dùng
  nhiều cú pháp ES6+ (đếm nguồn loại 0): mũi tên `=>` 424, template literal 364, `let` 228, `const` 84, `async`/`await` 7
  `[quan sát]`, nên JSC (hỗ trợ đủ) là tập lớn hơn của những gì cần.
- **Đồng bộ**: mọi hàm bridge (`java.ajax`, `java.connect`, `java.webView`, …) trả kết quả **ngay** (chặn luồng JS), đúng chữ ký
  `java.ajax(urlStr): String` `[tài liệu jsHelp.md]`. Các biến thể bất đồng bộ (`ajaxAwait`, …) chỉ có trong JS của trình duyệt
  nguồn đăng ký `[tài liệu rssRuleHelp.md]`, ngoài phạm vi. Hệ quả `[đề xuất]`: JS **không** chạy trên main thread; hàm cần
  WebView thì luồng JS chờ main thread làm xong (quy ước repo cấm chờ đồng bộ **trên** main thread).
- **Giá trị trả về** của một đoạn JS = giá trị hoàn tất (completion value) của câu lệnh biểu thức cuối, như `evaluateScript`.
  Mẫu: `…;\nurl;`, `JSON.stringify(cats);`, `result` `[quan sát]`. Nếu giá trị hoàn tất là `undefined` mà biến toàn cục `result`
  đã bị gán trong đoạn → dùng `result` `[đề xuất]`.
- **Toàn cục**: biến môi trường (§6.2) phải là **thuộc tính của đối tượng toàn cục** (hàm `jsLib` đọc `this.source` khi được gọi
  không kèm `this`, §5.8) `[quan sát]`. Gán lại biến môi trường trong mã (`result = …`, `baseUrl = baseUrl.replace(…)`) là bình
  thường `[quan sát]`.
- **`return` ở cấp cao nhất** (5 chuỗi rule) và `const` trong vòng lặp (tài liệu cảnh báo Rhino không hỗ trợ phạm vi khối cho
  `const` `[tài liệu jsHelp.md]`): JSC theo chuẩn. Lỗi cú pháp vì `return` cấp cao → thử bọc `(function(){…})()` `[đề xuất]`.
- **Một ngữ cảnh mỗi tác vụ** (§5.8). Không dùng ngữ cảnh chung toàn app (đúng quy ước repo: mỗi tác vụ một executor).
- Lỗi JS (ném ngoại lệ) → phân đoạn cho kết quả rỗng, ghi log có tên nguồn, trường và thông báo lỗi; **không** làm hỏng cả
  danh sách (một mục lỗi thì bỏ mục đó) `[đề xuất]`.

### §6.2 Biến môi trường

Danh sách biến theo tài liệu `[tài liệu jsHelp.md]`: `java`, `baseUrl` (URL hiện tại), `result` (kết quả bước trước), `book`,
`rssArticle`, `chapter`, `source`, `cookie`, `cache`, `title` (tên chương hiện tại), `src` (mã nguồn trả về từ request),
`nextChapterUrl`. `key`, `page` dùng trong URL `[tài liệu ruleHelp.md]`.

| Biến | `searchUrl` / mục khám phá | Rule tìm/khám phá | Thông tin | Mục lục | Nội dung, `replaceRegex` | Header, `jsLib` |
|---|---|---|---|---|---|---|
| `java`, `source`, `cookie`, `cache` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `key` | ✓ (rỗng ở khám phá) | ✓ | – | – | – | – |
| `page` | ✓ | ✓ | – | – | – | – |
| `baseUrl` | `bookSourceUrl` | URL trang kết quả | URL trang sách | URL trang mục lục | URL trang chương | `bookSourceUrl` |
| `result` | chuỗi tích luỹ (§3.2) | đầu ra phân đoạn trước | như trên | như trên | như trên | – |
| `src` | – | thân phản hồi thô | như trên | như trên | như trên | – |
| `book` | – | mục đang dựng (§6.6) | sách | sách | sách | sách nếu có |
| `chapter` | – | – | – | mục đang dựng | chương | chương nếu có |
| `title` | – | – | – | – | tên chương | – |
| `nextChapterUrl` | – | – | – | – | URL chương kế | – |

- `src` được dùng ở 333 nguồn loại 0, `baseUrl` 583, `result` 1375, `book` 622 (đếm thô) `[quan sát]`.
- Trong rule tìm/khám phá, `book` là mục đang dựng: `ruleSearch.intro: @put:{bookid:tag.td.0@text}\n《{{book.name}}》…` và
  `ruleExplore.intro: div.0@text##{{book.name}}|{{book.author}}` đọc tên/tác giả đã đánh giá `[quan sát]` → đánh giá trường theo
  thứ tự cố định: `name`, `author`, `kind`, `wordCount`, `lastChapter`, `intro`, `coverUrl`, `bookUrl` `[đề xuất]`.
- `infoMap` (21 nguồn, khám phá có bộ lọc) và `rssArticle`: không cung cấp ở đợt 1.

### §6.3 Quy ước kiểu

- **Thuộc tính kiểu bean**: Rhino cho đọc `getX()` như thuộc tính `x`; corpus dùng cả `source.getKey()` (205 nguồn) lẫn `source.key`
  (116), `book.name` và `book.getVariable(…)` `[quan sát]`. Bridge phải có **cả hai dạng** cho mọi getter được liệt kê ở §6.5–§6.6.
- **Chuỗi**: trả chuỗi JS. Mã hay bọc `String(...)` (623 nguồn) nên không có hại. Phương thức chỉ có ở chuỗi Java: `.length()`
  (3 lần), `.isEmpty()` (2), `.equals(` (hiếm), `.contains(` (21), `.getBytes(` (82 lần/35 nguồn, phần lớn trên
  `Packages.java.lang.String`), `.replaceAll(regexChuỗi, …)` (21; nghĩa regex của Java khác JS) `[quan sát]`.
  `[đề xuất]` thêm polyfill vô hại `String.prototype.contains/equals/isEmpty/getBytes`; không đổi `replaceAll`; chấp nhận `.length()` lỗi.
- **Mảng byte**: `Uint8Array` `[đề xuất]`. Mã kiểu `b[p] & 0xff`, `bytes.length`, `Array.from(bytes)` vẫn chạy.
- **Map Java** (`getLoginInfoMap()`, `headers()` của phản hồi): object JS có thêm phương thức `get(k)` và `put(k, v)` `[đề xuất]`.
- **Danh sách Java** (`ajaxAll`, `getElements`): object giống mảng có `size()`, `get(i)`, `toArray()`, `length`, chỉ số `[i]`,
  `forEach`, và lặp được (`Array.from`, `for…of`) `[đề xuất]`; `[quan sát]` `.size()` 561 lần/51 nguồn, `.get(i)` 267 lần,
  `.toArray()` 107 lần/76 nguồn.

### §6.4 `java.*`: đợt 1

**Ngưỡng** `[đề xuất]`: đợt 1 gồm (a) hàm dùng bởi **≥ 20 nguồn loại 0** và không phải UI/đăng nhập, (b) hàm mà nguồn không đăng
nhập của bộ thử tay `yck_1298` cần, (c) hàm tầm thường (một dòng trên nền tảng có sẵn). Số "lần/nguồn" là trên 3406 nguồn loại 0,
không tính `webJs`.

Bộ 1298 (15 nguồn) cần, ngoài rule: `java.ajax`, `java.encodeURI`, `java.t2s`, `org.jsoup.Jsoup.parse` (shim, §6.8),
`source.getKey`, `source.getVariable`, `chapter.title`, và option `webView` (`🎉起点中文网`) `[quan sát]`. `可乐小说` dùng
`java.util.Base64` và `new java.lang.String` trực tiếp trên `java` (trái tài liệu, §6.9) và `return` cấp cao nhất: coi là nguồn
lỗi, không chặn đợt 1. `69書吧`, `魔丸小说`, `起点小说`, `全本小说网` có đăng nhập.

#### §6.4.1 Mạng

| Hàm | Lần / nguồn | Chữ ký và hành vi | Nhãn |
|---|---|---|---|
| `java.ajax(url)` | 1110 / 463 | GET (hoặc theo option `,{…}` trong `url`, §3) → **chuỗi thân**; đi theo chuyển hướng; lỗi mạng → `""` + log. Tham số 2 dạng số = timeout ms | chữ ký `[tài liệu]`; option trong url, timeout `[quan sát]`; lỗi `[UNKNOWN]` |
| `java.ajaxAll(urls)` | 22 / 16 | mảng URL → danh sách đối tượng phản hồi cùng thứ tự (`responses[i].body()`) | `[tài liệu]` |
| `java.connect(url[, headers])` | 45 / 39 | như `ajax` nhưng trả **đối tượng phản hồi**: `body()`, `code()`, `message()`, `headers()`, `raw()`, `toString()` (= body); `raw().request().url()` = URL cuối. `headers` là chuỗi JSON (`java.connect(book.bookUrl, headerStr)`) | `[tài liệu jsHelp.md, ruleHelp.md]` + `[quan sát]` |
| `java.get(url, headers)` | 52 lần (2 tham số) | GET **không** theo chuyển hướng → đối tượng phản hồi kiểu khác: `body()`, `statusCode()`, `header(name)`, `headers()`, `cookies()`, `url()` | `[tài liệu]`; phương thức `[quan sát]` (`.body` 13, `.headers` 13, `.header` 3, `.cookies` 1) |
| `java.post(url, body, headers)` | 41 / 31 | POST, như `get` (`.body` 21, `.cookies` 5, `.header` 4) | `[tài liệu]` |
| `java.head(url, headers)` | 9 / 4 | HEAD, như `get` | `[tài liệu]` |

**Phân biệt `java.get`** theo số tham số: 1 tham số = đọc biến (878 lần), 2 tham số = HTTP GET (52 lần) `[tài liệu jsHelp.md, ruleHelp.md]`.

#### §6.4.2 Rule và nội dung

| Hàm | Lần / nguồn | Chữ ký và hành vi | Nhãn |
|---|---|---|---|
| `java.getString(rule[, content[, isUrl]])` | 860 / 269 | đánh giá rule `getString` trên `content` (thiếu → nội dung hiện hành); `isUrl` → §2.15 | `[tài liệu]` |
| `java.getStringList(rule[, content[, isUrl]])` | 44 / 21 | như trên, `getStringList` → mảng | `[tài liệu]` |
| `java.getElements(rule)` | 97 / 61 | `getElements` trên nội dung hiện hành → danh sách phần tử shim (§6.8) hoặc giá trị JSON | `[tài liệu]` |
| `java.getElement(rule)` | 53 / 29 | phần tử đầu (hoặc rỗng) | `[tài liệu]` |
| `java.setContent(content[, baseUrl])` | 63 / 42 | đặt nội dung hiện hành cho các lệnh `getString`/`getElements` sau, trong đoạn JS này | `[tài liệu]` |
| `java.put(key, value)` | 930 / 221 | lưu biến rule (§5.7), **trả `value`** (`java.put(...).replace(...)` 9 lần) | `[tài liệu]`; giá trị trả `[quan sát]` |
| `java.get(key)` | 878 lần | đọc biến rule; thiếu → `""` (§5.7) | `[tài liệu]`; giá trị thiếu `[UNKNOWN]` |
| `java.toNumChapter(s)` | 61 / 45 | dùng ở `lastChapter`/`chapterName` (`java.toNumChapter(result))\n##(章)([^\s]+)(\s·)##$1 $2$3`). Tài liệu không có. Khuyến nghị: đổi số Hán trong `第…章/节/回/卷` sang số Ả Rập; không khớp → trả nguyên chuỗi (an toàn) | `[UNKNOWN]` |

#### §6.4.3 Mã hoá, băm, mã hoá đối xứng

| Hàm | Lần / nguồn | Chữ ký và hành vi | Nhãn |
|---|---|---|---|
| `java.md5Encode(s)` | 835 / 110 | MD5 32 hex **thường** (562 lần nối `.toUpperCase()`) | `[tài liệu]` + `[quan sát]` |
| `java.md5Encode16(s)` | 6 / 2 | MD5 16 hex; `[UNKNOWN]` lấy đoạn nào, khuyến nghị ký tự 8…23 của bản 32 | `[tài liệu]` |
| `java.base64Encode(s[, flags])` | 184 / 47 | UTF-8 → base64, mặc định không xuống dòng | `[tài liệu]` |
| `java.base64Decode(s[, charset])` | 144 / 111 | base64 → chuỗi (UTF-8 hoặc `charset`) | `[tài liệu]` |
| `java.base64DecodeToByteArray(s[, flags])` | 40 / 23 | → bytes | `[tài liệu]` |
| `java.hexDecodeToString(hex)` | 69 / 30 | hex → chuỗi UTF-8 | `[tài liệu]` |
| `java.hexDecodeToByteArray(hex)` | 11 / 8 | hex → bytes | `[tài liệu]` |
| `java.hexEncodeToString(s)` | 2 / 2 | UTF-8 → hex | `[tài liệu]` |
| `java.strToBytes(s[, charset])`, `java.bytesToStr(b[, charset])` | 10/8, 3/3 | đổi chuỗi ↔ bytes; nhận tên bảng mã kiểu Java (`ISO8859_1`, `UTF-8`) | `[tài liệu]` |
| `java.encodeURI(s[, enc])` | 45 / 25 | mã hoá phần trăm theo bảng mã (`gbk`, `gb2312`, `utf-8`); `[UNKNOWN]` dấu cách thành `+` hay `%20`, khuyến nghị `%20` | `[tài liệu]` |
| `java.createSymmetricCrypto(transformation, key, iv)` | 84 / 55 | đối tượng có `decrypt(data)`→bytes, `decryptStr(data)`→chuỗi, `encrypt(data)`→bytes, `encryptBase64(data)`, `encryptHex(data)`. `key`/`iv`: bytes hoặc chuỗi UTF-8; `data` giải mã: bytes, chuỗi base64 hoặc hex | `[tài liệu]` |
| `java.aesBase64DecodeToString(data, key, transformation, iv)` | 31 / 29 | = `createSymmetricCrypto(transformation, key, iv).decryptStr(data)` với `data` base64; thứ tự tham số theo mẫu `java.aesBase64DecodeToString(result,"Pxga!h*e4@T8xfOm","AES/CBC/PKCS5Padding","E&z!EHGLd$fli*8R")` | `[quan sát]` |
| `java.digestHex(data, alg)`, `java.digestBase64Str(data, alg)` | 9 / 8 | băm (`SHA-256`, `sha-256`, không phân biệt hoa thường) | `[tài liệu]` |
| `java.HMacHex(data, alg, key)`, `java.HMacBase64(…)` | 33/5, 5/5 | HMAC (`HmacMD5`, `HmacSHA256`) | `[tài liệu]` |

Biến đổi gặp (số lần, mọi loại nguồn) `[quan sát]`: `AES/CBC/PKCS5Padding` 106, `AES/CBC/PKCS7Padding` 20, `DES/ECB/PKCS5Padding` 16,
`DES/CBC/PKCS5Padding` 15, `DESede/CBC/PKCS5Padding` 6, `AES/CBC/ZeroPadding` 6 (có cả `aes/cbc/ZeroPadding`), `AES/ECB/PKCS5Padding`,
`AES/CBC/NoPadding`, `RSA/ECB/PKCS1Padding` (1, đợt 3). Tên biến đổi so không phân biệt hoa thường; PKCS5 ≡ PKCS7. Cài bằng
CommonCrypto `[đề xuất]`. Nhận dạng `data` là hex hay base64 `[UNKNOWN]`: khuyến nghị chuỗi chỉ gồm `[0-9a-fA-F]`, độ dài chẵn
→ hex, còn lại base64.

#### §6.4.4 Tiện ích

| Hàm | Lần / nguồn | Chữ ký và hành vi | Nhãn |
|---|---|---|---|
| `java.log(msg)` | 788 / 209 | ghi log gỡ lỗi nguồn; **trả `msg`** (6 đoạn JS kết thúc bằng `java.log(x)` với ý trả `x`, ví dụ `list;\njava.log(list)`) | `[tài liệu]`; trả về `[quan sát]` |
| `java.logType(v)` | – | log kiểu của giá trị | `[tài liệu]` |
| `java.toast(msg)`, `java.longToast(msg)` | 728/121, 451/59 | thông báo ngắn không chặn; trả `undefined`. FreeBook: phát qua event center (Service không gọi `ToastManager` trực tiếp) + log; giới hạn tần suất (ví dụ ≤ 1/giây/nguồn) | `[tài liệu]` + `[đề xuất]` |
| `java.timeFormat(ms)` | 196 / 115 | số ms (hoặc chuỗi số) → chuỗi ngày giờ địa phương. Mẫu `String(java.timeFormat(…)).replace(/\//g,"-")` và `.slice(0,10)` cho thấy dạng `yyyy/MM/dd HH:mm` | `[tài liệu]`; định dạng `[quan sát]` một phần |
| `java.timeFormatUTC(ms, format, sh)` | 45 / 22 | định dạng theo mẫu kiểu Java (`yyyy-MM-dd HH:mm:ss`) ở múi giờ UTC+`sh` giờ (`…,'yyyy-MM-dd',8)`) | `[tài liệu]` |
| `java.t2s(s)`, `java.s2t(s)` | 89/19, 3/3 | phồn → giản / giản → phồn (ICU `Hant-Hans`) | `[tài liệu]` |
| `java.htmlFormat(s)` | – | HTML → văn bản như §5.5.2 | `[tài liệu]` |
| `java.randomUUID()` | 17 / 14 | UUID ngẫu nhiên | `[tài liệu]` |
| `java.androidId()` | 34 / 14 | id thiết bị ổn định: 16 hex ngẫu nhiên, sinh một lần, lưu bền | `[tài liệu]` + `[đề xuất]`; xem §6.10 |
| `java.getWebViewUA()` | 38 / 17 | UA của WebView (Android di động, §3.10 mục 6) | `[tài liệu]` |
| `java.getCookie(url)` | 38 / 21 | chuỗi cookie của url, như `cookie.getCookie(url)` | `[quan sát]` |
| `java.webView(html, url, js)` | 32 / 28 | tải bằng WebView ẩn (`html` rỗng → tải `url`), chạy `js` nếu có và trả giá trị, không có → trả HTML trang (`java.webView(null, url, null)`) | `[tài liệu]`; **đợt 1 cùng với option `webView`** |
| `java.url`, `java.headerMap` | 4, 2 | chỉ trong option `js` của URL (§3.6) | `[tài liệu ruleHelp.md]` |

### §6.5 `source.*`

| Thành viên | Lần / nguồn | Đợt 1 | Ghi chú |
|---|---|---|---|
| `getKey()` / `key` / `bookSourceUrl` | 278/205, 162/116, 273/51 | ✓ | nguyên chuỗi khoá (§1.4) `[tài liệu]` |
| `bookSourceName`, `bookSourceGroup`, `bookSourceType`, `bookSourceComment`, `loginUrl`, `loginUi`, `header`, `variableComment`, `lastUpdateTime`, `exploreUrl` | 24/9, 2/2, 2/1, 141/31, 16/5, 14/8, 10/9, 3/3, 6/3, 1/1 | ✓ | **chuỗi nguyên văn** từ JSON (`eval(String(source.bookSourceComment))` 110 lần) `[quan sát]` |
| `getVariable()`, `setVariable(s)` | 414/67, 186/61 | ✓ | §5.7 `[tài liệu]` |
| `put(k, v)` (trả `v`), `get(k)` | 47/11, 44/10 | ✓ | §5.7 `[tài liệu ruleHelp.md]` |
| `putVariable(…)` | 6/3 | ✓ | `[UNKNOWN]`; khuyến nghị bí danh `setVariable` |
| `getLoginInfoMap()`, `getLoginInfo()`, `getLoginHeader()`, `getLoginHeaderMap()`, `getHeaderMap(hasLoginHeader)` | 152/45, 9/7, 32/12, 16/4, 2/2 | ✓ (rỗng) | đợt 1 trả map rỗng/`""` để nguồn không vỡ khi chưa đăng nhập; lưu thật ở đợt 2 `[tài liệu]` |
| `putLoginHeader`, `removeLoginHeader`, `putLoginInfo`, `removeLoginInfo`, `login()` | 35/32, 9/7, 17/16, 1/1 | đợt 2 | `[tài liệu]` |
| `refreshExplore()`, `refreshJSLib()`, `putConcurrent(…)`, `getSource()` | 7/6, 3/3, 4/2, 7/2 | đợt 2 (đợt 1 no-op) | `[quan sát]` |

### §6.6 `book.*` và `chapter.*`

Thuộc tính theo `jsHelp.md` `[tài liệu]`. Đọc được qua cả `x` và `getX()` (§6.3).

- `book` đợt 1: `name`, `author`, `kind`, `coverUrl`, `intro`, `bookUrl`, `tocUrl`, `origin` (= `bookSourceUrl`), `originName`,
  `type` (0), `latestChapterTitle`, `durChapterIndex`, `durChapterTitle`, `totalChapterNum`, `customIntro`, `customTag`,
  `customCoverUrl`, `canUpdate`, `order`, `variable` (chuỗi JSON của kho biến sách); phương thức `getVariable(k)`, `putVariable(k, v)`.
  Đếm `[quan sát]`: `name` 136/91, `putVariable` 109/19, `type` 106/23, `getVariable` 68/25, `bookUrl` 58/33, `tocUrl` 57/21,
  `author` 45/25, `durChapterIndex` 40/17, `kind` 33/16, `durChapterTitle` 28/12, `origin` 28/23, `setReverseToc` 27/9.
- Ghi thuộc tính (`book.bookUrl = …` trong `preUpdateJs`, `book.variable = ""`), `setReverseToc`, `setUseReplaceRule`, `setType`:
  đợt 2; đợt 1 cho ghi vào bản sao trong ngữ cảnh, **không** lưu xuống sách `[đề xuất]`.
- `chapter` đợt 1: `title` (103/89), `index` (36/27), `url` (22/12), `baseUrl`, `bookUrl`, `tag`, `isVip`, `isVolume`, `isPay`,
  `variable`; `putVariable`/`getVariable` (19/10) `[tài liệu]` + `[quan sát]`. `resourceUrl`, `start`, `end`: không cần.
- Tên lạ dạng `book.qq`, `book.sfacg`, `book.midukanshu` là **tên miền** (`book.qq.com`) trong chuỗi, không phải thành viên.

### §6.7 `cookie.*` và `cache.*`

| Hàm | Lần / nguồn | Hành vi | Nhãn |
|---|---|---|---|
| `cookie.getCookie(url)` | 166 / 34 | mọi cookie của tên miền dạng `k=v; k2=v2` | `[tài liệu]` |
| `cookie.getKey(url, key)` | 1373 / 26 | giá trị một cookie | `[tài liệu]` |
| `cookie.setCookie(url, cookie)` | 73 / 29 | thêm/ghi đè các cặp trong chuỗi `cookie` | `[tài liệu]`; gộp hay thay `[UNKNOWN]` (khuyến nghị gộp) |
| `cookie.replaceCookie(url, cookie)` | 4 / 4 | thay toàn bộ cookie của tên miền | `[tài liệu]` |
| `cookie.removeCookie(url)` | 300 / 202 | xoá cookie của tên miền; trả `undefined` | `[tài liệu]` |
| `cache.put(key, value[, saveTime])` | 55 / 18 | lưu bền, `saveTime` tính bằng **giây**, bỏ trống = không hết hạn | `[tài liệu]` |
| `cache.get(key)` | 42 / 19 | đọc; thiếu/hết hạn → `null` `[UNKNOWN]` | `[tài liệu]` |
| `cache.delete(key)` | 5 / 3 | xoá | `[tài liệu]` |
| `cache.putFile(key, value[, saveTime])`, `cache.getFile(key)` | 5 / 5 | như `put/get`, dành cho giá trị lớn (lưu tệp) | `[tài liệu]` |
| `cache.putMemory(key, value)`, `cache.getFromMemory(key)`, `cache.deleteMemory(key)` | 31/14, 37/14, 6/3 | bộ nhớ trong phiên, giá trị JS bất kỳ | `[tài liệu]` |

Tài liệu ghi `cache` lưu vào CSDL và tệp đệm (50 MB) `[tài liệu jsHelp.md]`. Phạm vi khoá `[đề xuất]`: **theo nguồn** (khoá thực =
`bookSourceUrl` + `key`) để nguồn không đọc trộm nhau; `[UNKNOWN]` gốc có tách theo nguồn không.

### §6.8 Shim `org.jsoup`

- `org.jsoup.Jsoup.parse(html)` xuất hiện ở **210 nguồn loại 0** (396 lần), ngang các hàm `java.*` hàng đầu `[quan sát]` → **đợt 1**.
  Cũng gặp `Packages.org.jsoup.Jsoup.parse` (11 nguồn), `org.jsoup.Jsoup.connect` (9, đợt 2), `parseBodyFragment` (1).
- Phương thức thấy trong các chuỗi có `Jsoup` (lần): `select` 937, `get` 562, `size` 524, `attr` 445, `text` 409, `first` 154,
  `remove` 91, `map` 61, `forEach` 54, `toArray` 37, `body` 35, `getElementById` 24, `html` 22, `eachText` 9, `ownText` 4,
  `selectFirst` 3, `hasClass`, `last`, `isEmpty`, `eachAttr` `[quan sát]`.
- Đặc tả shim `[đề xuất]` (cài trên SwiftSoup, bộ chọn theo §2.8.2):
  - `Jsoup.parse(html[, baseUri])` → Document.
  - Document/Element: `select(css)` → Elements, `selectFirst(css)`, `text()`, `ownText()`, `html()` (inner), `outerHtml()`, `attr(k)`,
    `attr(k, v)`, `hasAttr(k)`, `absUrl(k)`, `hasClass(c)`, `id()`, `className()`, `tagName()`, `children()`, `child(i)`, `parent()`,
    `nextElementSibling()`, `previousElementSibling()`, `getElementById(id)`, `getElementsByTag(t)`, `getElementsByClass(c)`,
    `remove()`, `body()`, `head()`, `title()`, `toString()` (= `outerHtml()`).
  - Elements: `size()`, `get(i)`, `first()`, `last()`, `isEmpty()`, `text()` (nối bằng dấu cách như jsoup), `html()`, `outerHtml()`,
    `attr(k)` (của phần tử đầu có thuộc tính), `eachText()`, `eachAttr(k)`, `select(css)`, `remove()`, `toArray()` (mảng JS),
    `forEach(fn)`, `length`, chỉ số `[i]`, lặp được.
  - Phần tử từ `java.getElements` và từ `result` của rule danh sách dùng **cùng** shim.

### §6.9 `Packages`, `JavaImporter`, `java.lang`/`java.util`/…

- Tài liệu: biến `java` đã bị ứng dụng thay, muốn gọi gói `java.*` phải viết `Packages.java.*`; có `JavaImporter`, `importClass`,
  `importPackage`; ứng dụng chặn một số lớp vì an toàn `[tài liệu jsHelp.md]`.
- Corpus: `Packages.` 518 lần/92 nguồn, `JavaImporter` 53/41, `importClass` 1 `[quan sát]`. Lớp hay gặp (lần/nguồn):
  `java.lang.String` 36/11 (tạo chuỗi từ bytes theo bảng mã, `.getBytes(cs)`), `javax.crypto(.spec)` 42/30 (`Cipher`,
  `SecretKeySpec`, `IvParameterSpec`: tự giải AES/DES), `java.util` 33/25 (`Base64`, `Arrays`, `HashMap`, `UUID`, `ArrayList`),
  `java.lang.Thread` 16/15 (`Thread.sleep`), `java.io` 20/12 (`ByteArrayOutputStream`/`InputStream`), `java.security(.spec,.interfaces)`
  (`MessageDigest`, khoá RSA), `android.util.Base64` 13/9, `okhttp3.*` 12/6, `org.jsoup.nodes.*` 11/6, `java.util.zip.Inflater` 2/2,
  `java.net.URL`/`Socket` (đo độ trễ tên miền), và lớp nội bộ của ứng dụng gốc (gói `io.legado…`, 4–14 lần) `[quan sát]`.
- Mẫu điển hình: `var javaImport = new JavaImporter(); javaImport.importPackage(Packages.java.lang, Packages.javax.crypto.spec, …);
  with (javaImport) { … }` để giải AES `[quan sát]`.
- **Mâu thuẫn tài liệu/corpus**: tài liệu nói phải qua `Packages`, nhưng 7 nguồn gọi `new java.lang.String(…)` trực tiếp và một
  nguồn bộ 1298 gọi `java.util.Base64.getDecoder()` (nguồn tự ghi "chưa kiểm") `[quan sát]`. Theo tài liệu: các lệnh đó nhiều khả
  năng không chạy trên ứng dụng gốc. Khuyến nghị: cho `java.lang`/`java.util`/… trỏ vào **cùng** bộ giả lập với `Packages` (rẻ,
  không hại), nhưng không coi các nguồn đó là chuẩn.
- Đợt 1 `[đề xuất]`: `Packages`, `JavaImporter` là đối tượng giả: truy cập lớp chưa giả lập → ném `Error("Lớp Java <tên> chưa được
  hỗ trợ")` để rule hỏng rõ ràng. Giả lập sẵn: `java.lang.String(bytes|str[, charset])` + `.getBytes(cs)` + `.toString()`,
  `java.lang.Thread.sleep(ms)` (giới hạn ≤ 5 s), `java.util.Base64`/`android.util.Base64` (`getEncoder().encodeToString`,
  `getDecoder().decode`, `encodeToString(b, flags)`, `decode(s, flags)`), `java.util.UUID.randomUUID()`.
- Đợt 2: `javax.crypto.Cipher` + `SecretKeySpec` + `IvParameterSpec`, `java.security.MessageDigest`, `java.io.ByteArray*Stream`,
  `java.util.HashMap`/`ArrayList`/`Arrays` tối thiểu, `java.util.zip.Inflater`, `java.net.URL`.
- Không giả lập: `okhttp3.*`, `android.*` (trừ `Base64`), `java.net.Socket`, lớp nội bộ ứng dụng gốc, `org.mozilla.javascript.*`.

### §6.10 Mã dò biến thể ứng dụng

Nhiều nguồn dò môi trường bằng cách thử gọi hàm `[quan sát]`:

```
try { java.qread(); device_type = "轻阅读"; } catch { java.deviceID(); device_type = "苹果"; }
… catch (e) { java.androidId(); device_type = "安卓"; }
if (typeof java.reLoginView == 'function') …        if (typeof source.loginUi == 'function') …
function isSourceRead() { return java.getUserAgent() === java.getWebViewUA() }
```

Khuyến nghị `[đề xuất]`: **không** định nghĩa `java.qread`, `java.deviceID`, `java.reLoginView`, `java.getUserAgent`; giữ
`java.androidId`; `source.loginUi` là chuỗi. Khi đó nguồn đi nhánh "ứng dụng Android chính thức", nhánh được thử nhiều nhất.
Ghi chú của một nguồn còn nói bản chính thức không hỗ trợ `a?.b` và tham số mặc định trong hàm `jsLib`; JSC hỗ trợ cả hai nên
không ảnh hưởng.

### §6.11 Hoãn

| Đợt | Hàm / tính năng | Lý do |
|---|---|---|
| 2 | `java.startBrowser` (100/42), `java.startBrowserAwait` (130/37), `java.startBrowserDp`, `java.getVerificationCode` (13/10), `java.reLoginView`, `java.upLoginData`, `java.getStrResponse`, `java.initUrl`, `java.refreshTocUrl` (7/7), `java.reGetBook`, `java.refreshBookUrl`, `source.login`/`putLoginHeader`/`putLoginInfo`, `loginUrl`/`loginUi`/`loginCheckJs` | đăng nhập, xác minh bằng trình duyệt hiện cho người dùng |
| 2 | `java.refreshExplore` (64/24), khám phá có `select`/`button`, `infoMap` | giao diện khám phá động |
| 2 | URL `data:` (§3.11), `sourceRegex`, `preUpdateJs`, `formatJs`, `book.setReverseToc`, ghi thuộc tính `book`, `java.importScript`, `java.cacheFile`, `java.toURL`, `org.jsoup.Jsoup.connect`, giả lập `javax.crypto`… (§6.9) | ít nguồn hoặc cần thiết kế thêm |
| 3 | `java.queryTTF`, `java.queryBase64TTF`, `java.replaceFont` (2/2 mỗi hàm) | phân tích font |
| 3 | `java.downloadFile`, `java.readTxtFile`, `unzipFile`/`unrarFile`/`un7zFile`/`unArchiveFile`, `getTxtInFolder`, `deleteFile`, `java.get*StringContent`/`*ByteArrayContent` (tệp nén) | tệp, loại 3 |
| 3 | `java.createAsymmetricCrypto` (4/4), `java.createSign`, `java.desEncodeToBase64String` (16/4), `java.tripleDESEncodeBase64Str` (6/3) | RSA/ký số, mã hoá hiếm |
| 3 | `java.open` (33/8, chủ yếu trong `callBackJs`), `java.openUrl` (23/10), `java.openVideoPlayer`, `java.showBrowser` (16/11), `java.showReadingBrowser`, `java.copyText`, `java.searchBook`, `java.addBook`, `callBackJs`, `payAction`, `imageDecode`, `coverDecodeJs`, `customButton` | UI ứng dụng gốc |
| – | `java.qread`, `java.deviceID`, `java.getUserAgent` | cố ý không có (§6.10) |

---

## §7. Phụ lục

### §7.1 Đợt 1 phải có / hoãn

| Hạng mục | Đợt 1 | Hoãn |
|---|---|---|
| Nhập | mảng / object đơn / chuỗi escape, BOM, lenient JSON, giữ JSON gốc, trùng khoá (§1.1–§1.2) | định dạng nguồn thế hệ cũ (§1.8) |
| Model | mọi khoá §1.3 được lưu; chạy loại 0; nhận diện loại 2/4 (§1.6) | chạy loại 1/2/3/4 |
| Đường ống rule | phân đoạn `<js>`/`@js:` (§2.2), `-` đảo (§2.13.1) | – |
| Chế độ | mặc định jsoup, `@css:`, XPath, JSONPath (kể cả ngầm), regex danh sách `:` (§2.4) | – |
| Toán tử | `\|\|`, `&&`, `%%` (§2.5) | – |
| Regex | `##`, `##…##…`, `###` (§2.6) | chuỗi nhiều cặp |
| Mẫu | `{{rule}}`, `{{JS}}`, `{$.x}`, `@get:{}`, `$n` (§2.7, §2.13) | – |
| Biến | `@put`, `java.put/get`, `source.get/setVariable`, `source.put/get`, `book/chapter.put/getVariable`, `cache.*` (§5.7, §6.7) | ghi thuộc tính `book` |
| URL | JS sinh URL, `{{key}}`/`{{page}}`, `<,…>`, option `method`/`body`/`charset`/`headers`/`webView`/`webViewDelayTime`/`js`/`retry`, mã hoá theo charset, header nguồn (JSON lenient, JS, mẫu) (§3) | `data:` (§3.11), `proxy` |
| Mạng | `concurrentRate`, cookie jar, chuyển hướng, timeout, WebView ẩn + `webJs` (§4) | `sourceRegex`, `loginCheckJs` |
| Luồng | tìm kiếm, khám phá (mảng JSON / văn bản / JS; tiêu đề nhóm), thông tin (`init`, ghi đè, `tocUrl` rỗng), mục lục (cờ, URL rỗng, phân trang), nội dung (phân trang + URL dừng, `replaceRegex`, HTML → văn bản) (§5) | `preUpdateJs`, `formatJs`, khám phá `select`/`button` |
| `jsLib` | cả hai dạng; nạp một lần mỗi tác vụ (§5.8) | – |
| JS bridge | §6.4 (mạng, rule, mã hoá đối xứng/băm, tiện ích), §6.5–§6.7, shim `org.jsoup` (§6.8), `Packages` tối thiểu (§6.9) | §6.11 |
| Công cụ | bộ nghiệm thu dùng `checkKeyWord`; log gỡ lỗi theo nguồn | màn gỡ lỗi kiểu `debugHelp.md` |

### §7.2 Điểm `[UNKNOWN]` cần bộ chạy nghiệm thu đo

Bộ nghiệm thu = chạy toàn corpus (tìm bằng `checkKeyWord` → trang sách → mục lục → 3 chương đầu) và lưu: số kết quả mỗi bước,
lỗi, thời gian, và các chỉ số riêng dưới đây. Với mỗi điểm, chạy **cả hai phương án** trên các nguồn bị ảnh hưởng rồi so.

| # | Điểm | Khuyến nghị hiện tại | Đo |
|---|---|---|---|
| U1 | Ưu tiên `\|\|`/`&&`/`%%` (§2.5) | đệ quy, `\|\|` lỏng nhất | 18 rule có cả hai toán tử: số giá trị không rỗng mỗi phương án |
| U2 | Phạm vi biến `java.put`/`@put` (§5.7) | kho sách, rồi kho phiên của nguồn | nguồn có dòng `put → get` khác bước (≈ 300 khoá): tỉ lệ `get` ra rỗng |
| U3 | `###` không khớp (§2.6) | giữ nguyên đầu vào | 552 rule `###`: so kết quả "giữ nguyên" và "rỗng" với dữ liệu thật |
| U4 | `html`/`all` inner hay outer; chi tiết `textNodes` (§2.8.4) | outer HTML; nút chữ con trực tiếp | nội dung 1643 nguồn `@html`, 486 `@textNodes`: độ dài và dòng rác |
| U5 | `ruleExplore` thừa kế từng trường hay cả nhóm (§5.2.4) | từng trường | 12 nguồn có `bookList` rỗng nhưng có trường khác |
| U6 | Vế `\|\|` dạng mẫu thất bại khi placeholder rỗng (§2.7) | thất bại nếu có placeholder rỗng | rule URL có `{$.`/`{{` và `\|\|` |
| U7 | Bảng mã phản hồi; mã hoá query/form, dấu cách (§3.8, §4.5) | header > option > BOM > meta > UTF-8; `%20` / `+` | nguồn có `charset` (487 lần): số kết quả tìm kiếm, ký tự lỗi |
| U8 | Content-Type mặc định khi body là chuỗi (§3.9) | form-urlencoded; object → JSON | nguồn có body chuỗi JSON mà không tự đặt Content-Type |
| U9 | Không tự bỏ chương trùng (§5.4.2) | không bỏ | đếm `chapterUrl` trùng mỗi nguồn; nguồn có khối "chương mới nhất" |
| U10 | `java.toNumChapter` (§6.4.2) | đổi số Hán trong `第…章`, không khớp thì giữ | 45 nguồn: so tên chương với trang thật |
| U11 | Option `js` có thay URL bằng giá trị trả về (§3.6) | có, nếu là chuỗi không rỗng | 16 lần trong corpus |
| U12 | `<,…>` khi trang vượt số mục (§3.5) | mục cuối | khám phá trang 3+ của nguồn `<,index_{{page}}.html>` |
| U13 | Chỉ số `[a:b:c]`; chỉ số áp trên danh sách nối (§2.8.1, §2.8.3) | khoảng có bước; danh sách nối | 1 rule `[1:2:3]`; rule nhiều bước có chỉ số ở bước sau |
| U14 | `text.X`: chữ riêng hay gồm con (§2.8.2) | chữ riêng | 1543 bước `text.`: so kết quả |
| U15 | Tiền tố `+` (§2.13.1); regex danh sách `:R1&&R2` (§2.13) | bỏ `+`; xích | 41 + vài rule |
| U16 | `canReName` (§5.3.3) | chỉ đổi tên sách trên kệ khi truthy | 67 nguồn |
| U17 | `replaceRegex` theo trang hay chuỗi nối (§5.5.3) | chuỗi nối, trước HTML → văn bản | nguồn có cả `nextContentUrl` và `replaceRegex` |
| U18 | Mã HTTP ≥ 400 (§4.6); `java.ajax` khi lỗi (§6.4.1) | lỗi ở luồng chính; `ajax` trả `""` | tỉ lệ nguồn có trang lỗi mà vẫn có dữ liệu |
| U19 | `enabledCookieJar = false` có gửi cookie không (§4.2) | chỉ gửi cookie JS/WebView đặt | 1525 nguồn tắt |
| U20 | Header: `baseUrl` trong mẫu; UA trần; mặc định UA Android (§3.10) | xem §3.10 | 33 + 27 nguồn |
| U21 | Tìm kiếm rơi thẳng trang sách (§5.1.4) | dùng `bookUrlPattern` | nguồn có `bookUrlPattern` và tìm theo tên chính xác |
| U22 | `data:` URL: thân là hex (§3.11) | hex | 34 nguồn (đợt 2) |
| U23 | `cache.get` thiếu → `null`, phạm vi theo nguồn; `source.put` bền? (§5.7, §6.7) | `null`; theo nguồn; bền | nguồn dùng `cache.*`/`source.put` |
| U24 | Nhập trùng khoá; trim `bookSourceUrl` (§1.1, §1.4) | ghi đè, giữ trạng thái người dùng; trim khi so | 1074 khoá trùng giữa các bộ |
| U25 | `md5Encode16`, `encodeURI` dấu cách, nhận dạng hex/base64 của `createSymmetricCrypto` (§6.4.3) | ký tự 8…23; `%20`; hex nếu toàn ký tự hex | nguồn dùng các hàm này |
| U26 | XPath trả phần tử trong `getString` (§2.12); `formatJs` `index` từ 0 hay 1 (§5.4.1) | chữ của phần tử; – | ít nguồn |
| U27 | `@put` trong rule danh sách; kho `@put` = kho `java.put` (§2.10) | đánh giá trên trang; chung kho | 3 rule; nguồn trộn `@put` với `java.get` |
| U28 | Mọi `[đề xuất]` làm đổi đầu ra (§0.3): chuyển chuỗi theo chế độ (§2.1), tiền tố JSONPath ngầm `.x` → `$.x` chứ không `$..x` (§2.11.1), chuyển kiểu JSONPath/JS (§2.11.3, §2.14), URL nền và ghép URL (§2.15, §3.7), nối `\n` khi nhiều giá trị (§2.8.4), bỏ mục thiếu tên/URL (§5.1.1, §5.4.1), thứ tự đánh giá trường (§6.2), dự phòng `result` khi giá trị hoàn tất là `undefined` (§6.1), HTML → văn bản (§5.5.2), luật truthy (§5.4.3) | như đã viết ở từng mục | so với trang thật trên mẫu ngẫu nhiên 100 nguồn; ghi nguồn lệch |

### §7.3 Ghi chú tái lập số liệu

Mọi số `[quan sát]` lấy từ script Python chỉ đọc 6 tệp corpus (bỏ trùng theo `bookSourceUrl`, giữ bản gặp trước theo thứ tự
`1315, 1316, 1208, 1158, 1298, 1272`) và từ bảng census chạy sẵn. Phép đếm dùng regex trên chuỗi, nên sai số vài phần trăm (ví dụ
`book.qq` là tên miền). Bộ nghiệm thu nên tự đếm lại các chỉ số mình dùng thay vì tin tuyệt đối vào số ở đây. Các trang đã curl
(khoảng 20 request, ngày 2026-10-21) được ghi tại chỗ dùng; trang có thể đã đổi.
