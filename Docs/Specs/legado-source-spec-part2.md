# Đặc tả hành vi: nguồn truyện JSON kiểu Legado — phần 2 (clean-room)

> Trạng thái: bản 1 (2026-10-21). Nối tiếp `Docs/Specs/legado-source-spec.md` (gọi tắt là **phần 1**). Đánh số mục chạy
> tiếp từ §8 để hai file dùng chung một hệ trích dẫn. Phần này **không** mô tả cách cài đặt của ứng dụng nào; đội triển khai
> viết engine Swift từ đầu dựa trên hai file spec và code FreeBook.

**Mục lục**: §8 Tranh (loại 2) · §9 Video (loại 4) · §10 Đăng nhập và trình duyệt cho người dùng · §11 Khám phá động ·
§12 Quản lý nguồn · §13 Phần đuôi đợt 2 · §14 Đợt 3 (phần hiếm) · §15 Phụ lục (bảng đợt, `[UNKNOWN]` U29–U63, đính chính phần 1
ở §15.3, ghi chú tái lập số liệu).

## Quy ước dùng lại từ phần 1

- **Nhãn**: y như §0.3 phần 1. `[tài liệu X.md]` = tài liệu trợ giúp được phép nói rõ; `[quan sát]` = suy ra từ nguồn trong
  corpus (ghi tên nguồn hoặc rule ngắn) hoặc trang đã curl (ghi URL); `[UNKNOWN]` = thiếu bằng chứng, có khuyến nghị và mã
  `U…` để bộ nghiệm thu đo; `[đề xuất]` = quyết định thiết kế (nếu làm đổi đầu ra của nguồn thì coi như `[UNKNOWN]`, §0.3
  phần 1).
- **Đơn vị**: như §0.5 phần 1. Mặc định đếm trên **3701 nguồn** sau bỏ trùng của 6 bộ `yck_1315, 1316, 1208, 1158, 1298, 1272`.
  "N lần" = số lần xuất hiện; "N nguồn" = số nguồn có ít nhất một lần. Khi chỉ đếm một loại nguồn thì ghi rõ (`loại 2`, `t2`).
  Phép đếm bằng regex trên chuỗi nên có lẫn **chú thích JS** (`// java.ajaxTestAll()`); chỗ nào biết là chú thích thì đã ghi.
- **Bổ sung dữ liệu cho video**: loại 4 chỉ có 12 nguồn trong 3701. Đã tải thêm bộ `yck_1111` (một nguồn video mới:
  `西瓜卡通（优+）`) và chỉ dùng nó làm **mẫu quan sát video**, không cộng vào mẫu số 3701. Chi tiết tải và curl: §15.4.
- Tên khái niệm `getString` / `getStringList` / `getElements`, "nội dung hiện hành", "đường ống phân đoạn" giữ nghĩa §0.6, §2.1,
  §2.2 phần 1.

---

## §8. Tranh (`bookSourceType = 2`)

### §8.1 Phạm vi và số liệu

175 nguồn loại 2 (1315: 75, 1158: 49, 1208: 37, 1272: 9, 1316: 5) `[quan sát]`. Khoá `ruleContent` có giá trị:

| Khoá | Có / có giá trị | Ghi chú |
|---|---|---|
| `content` | 173 / 173 | 2 nguồn rỗng |
| `imageStyle` | 116 / 112 | `FULL` 108, `full` 2, `Full` 1, CSS rác `max-width:100%;height:auto;` 1 |
| `nextContentUrl` | 32 / 11 | §8.8 |
| `replaceRegex` | 9 / 3 | cả 3 là `##.*base64.*` (§8.2) |
| `imageDecode` | 6 / 5 | §8.6 |
| `title` | 6 / 5 | tên chương lấy từ trang nội dung, như §5.5.1 phần 1 |
| `webJs`, `sourceRegex` | 18 / 0, 6 / 0 | luôn rỗng ở loại 2 |
| `subContent` | 1 / 1 | `[UNKNOWN]`, giá trị là một URL host ảnh (`🎨知音漫客`); bỏ qua |

Cấp nguồn (loại 2): `header` 109 nguồn, `enabledCookieJar = true` 116, `loginUrl` 31, `jsLib` 24, `loginUi` 17, `loginCheckJs` 7
(cả 7 là xử lý Cloudflare, §10.7), `concurrentRate` 7, `coverDecodeJs` 2 `[quan sát]`. Mục lục đảo bằng tiền tố `-` (§2.13.1 phần 1):
39/175 nguồn, nhiều hơn hẳn truyện chữ vì trang tranh hay liệt kê chương mới nhất trước.

Hình dạng rule `content` (175 nguồn, một nguồn có thể rơi vào nhiều nhóm) `[quan sát]`:

| Hình dạng | Số nguồn | Ví dụ |
|---|---|---|
| JS tự dựng chuỗi `<img src="…">` | 120 | `result.split("\n").map(x=>'<img src="'+x+'">').join("\n")` |
| … trong đó URL ảnh kèm khối option `,{"headers":…}` | 43 | `'<img src="'+x+','+JSON.stringify(headers)+'">'` |
| Lấy HTML có sẵn bằng `@html` | 38 | `class.article-content@html`, `#imgsec@html`, `class.main-container@li@img@html##data-original##src` |
| JS nạp mã từ máy chủ ngoài qua hàm `Reload(…)` của `jsLib` dạng map | 10 | `eval(String(Reload('https://qyyuapi.com/sy/js/皮皮漫画/ruleContent.js')))` |
| JS trả thẳng đối tượng phần tử | 1 | `🎨笔趣漫画`: sửa `src` rồi trả `imgs` (danh sách phần tử) |
| Gọi mạng thêm trong `content` (`java.ajax`, `java.post`, …) | 7 | ghép nhiều trang ảnh trong JS (§8.8) |
| Thực chất là video/chữ dán nhãn loại 2 | 2 | `盗随动漫（优+）`, `视频🈲💻` gọi `java.startBrowser(url, …)` rồi trả chữ có link (§9.6) |

### §8.2 Từ kết quả `content` ra danh sách ảnh

`content` của tranh là **một chuỗi HTML chứa các thẻ `<img>`**, mỗi thẻ là một trang ảnh, theo thứ tự xuất hiện `[quan sát]` (120
nguồn tự dựng `<img>`, 38 nguồn lấy `@html`). Tài liệu cũng dùng đúng cách dựng thẻ `<img>` bằng chuỗi khi muốn gắn header cho ảnh
`[tài liệu ruleHelp.md]`.

**Thuật toán** `[đề xuất, từng bước có bằng chứng ghi kèm]`:

1. Tải và đánh giá như truyện chữ (§5.5.1 phần 1, bước 1–5): tải `chapterUrl`, `content` (`getString`), phân trang `nextContentUrl` với
   URL dừng là chương kế (§8.8), nối các trang bằng `\n`, áp `replaceRegex`.
   - `replaceRegex` chạy **trên chuỗi HTML**, trước khi tách ảnh: cả 3 nguồn có giá trị dùng `##.*base64.*` để xoá dòng chứa ảnh giữ
     chỗ `data:image/…;base64,…` `[quan sát: 吉站漫画（优+）, 🎨🔞18禁漫辞晨, 🎨🔞18禁漫]`. Điều này chỉ đúng khi mỗi `<img>` nằm một dòng
     (các nguồn đều nối bằng `\n`).
2. **Không** đi qua bước HTML → văn bản (§5.5.2), `ChapterTextNormalizer`, dịch, TTS (quy ước media của repo).
3. Tách ảnh: quét chuỗi, với mỗi thẻ `<img …>` (không phân biệt hoa thường) lấy giá trị thuộc tính `src` bằng **bộ tách khoan dung**
   (§8.2.1). Bỏ thẻ không có `src` hoặc `src` rỗng.
4. Mỗi `src` = `URL[,{option}]`. Tách option như §3.2 bước 4 phần 1 (tìm `,{` ở mức ngoài cùng, phần sau parse lenient §1.2.1).
   Phần URL ghép tuyệt đối theo URL cuối của trang chương (§2.15 phần 1); `//host/…` thêm scheme; `data:` giữ nguyên.
5. Ảnh trùng URL liên tiếp: giữ cả hai `[đề xuất]` (không có bằng chứng tác giả dựa vào việc bỏ trùng; tranh có thể lặp trang).
6. Không có `<img>` nào:
   - nếu chuỗi gồm các dòng mà **mỗi dòng không rỗng là một URL** `http(s)://…` → mỗi dòng một ảnh `[đề xuất]` (FreeBook
     `ComicPageMapper` đã nhận dạng này);
   - ngược lại → chương **không có ảnh**: hiển thị văn bản đã làm sạch (HTML → văn bản như §5.5.2) cùng các link trong đó, để người
     dùng tự mở; không báo lỗi cứng. Lý do: có nguồn loại 2 thực chất trả chữ/link video (§8.1, dòng cuối bảng) `[quan sát]`.

**Thuộc tính ảnh lười (lazy)**: engine đọc **chỉ `src`** là đúng với corpus. Bằng chứng: tác giả tự đổi thuộc tính lười sang `src`
trước khi trả về, theo nhiều cách: `@html##data-original##src`, `result.replace(/data-original/g,"src")`,
`e.attr("src", e.attr("data-original"))` (8 nguồn làm việc này rõ ràng; 39 nguồn có nhắc `data-original`/`data-src`/`lazy` trong
`content`) `[quan sát]`. Nếu engine tự ưu tiên `data-original` thì không ai phải viết các dòng trên. Khuyến nghị: lấy `src`; **chỉ khi**
`src` rỗng hoặc là `data:` ảnh giữ chỗ (dưới 1 KB) mà thẻ có `data-original`/`data-src` thì dùng thuộc tính đó `[đề xuất]`.

**`@html` của phần tử `<img>`** phải là **outer HTML**: rule `class.main-container@li@img@html##data-original##src` (2 nguồn
`爱奇艺漫画$`) chỉ có nghĩa khi `@html` trả cả thẻ `<img …>` (inner HTML của `<img>` luôn rỗng) `[quan sát]`. Đây là bằng chứng mạnh cho
U4 phần 1 (§15.3 mục 1).

**JS trả danh sách phần tử** ở trường `content` (`🎨笔趣漫画`: `imgs.forEach(e => e.attr("src", …)); imgs`): kết quả cuối phải là
**outer HTML các phần tử nối `\n`**, không phải chữ của phần tử (chữ của `<img>` rỗng) `[quan sát]`. Bảng §2.14 phần 1 ghi "chữ" → đính
chính ở §15.3 mục 2.

#### §8.2.1 Bộ tách `src` khoan dung

Cách dựng `'<img src="' + url + ',' + JSON.stringify(opt) + '">'` (43 nguồn tranh, cũng là ví dụ trong `ruleHelp.md`) đặt dấu `"` của JSON
**bên trong** thuộc tính bọc bằng `"`. Parser HTML chuẩn cắt giá trị tại `"` đầu tiên. Thử với `html.parser` của Python
`[quan sát]`:

```
vào:  <img src="https://a.com/1.jpg,{"headers":{"Referer":"https://a.com/"}}">
ra:   src = 'https://a.com/1.jpg,{'   (phần JSON vỡ thành các thuộc tính rác)
```

SwiftSoup cũng là parser HTML chuẩn nên sẽ hỏng y như vậy. Thuật toán `[đề xuất]`:

```
tìm "<img" (không phân biệt hoa thường) → tìm "src" + khoảng trắng tuỳ ý + "=" + khoảng trắng tuỳ ý
q ← ký tự kế ("\"" hoặc "'"); không phải nháy → đọc tới khoảng trắng hoặc ">"
đọc giá trị từng ký tự:
    nếu gặp ",{" và chưa trong khối option → vào khối, đếm độ sâu "{" "}", bỏ qua chuỗi trong nháy kép của JSON
    nếu độ sâu = 0 và gặp q → kết thúc giá trị
giải thực thể HTML trong phần URL (&amp; → &), giữ nguyên khối option
```

Các thuộc tính khác của thẻ (`data-original`, `alt`) đọc bằng parser thường sau khi đã cắt bỏ giá trị `src` khỏi chuỗi thẻ.

### §8.3 Khối option của URL ảnh, header và cookie

- Cú pháp `URL,{"headers":{…}}` cho ảnh có trong tài liệu `[tài liệu ruleHelp.md]`. Khoá gặp trong object được `JSON.stringify` vào
  `src` (mọi loại nguồn) `[quan sát]`: `headers` (57 lần / 44 nguồn), `style` (1 nguồn, giá trị `'FULL'`), `click`, `js`, `type`
  (2 nguồn loại 0, nhánh dò ứng dụng iOS). Trong `headers`: `Referer` (11 nguồn), `User-Agent`, `Cookie` (1). Tài liệu viết `Referrer`
  trong ví dụ; corpus dùng `Referer`. Không tự đổi tên khoá `[đề xuất]`.
- Xử lý `[đề xuất]`: `headers` → header của request ảnh; `style` → `imageStyle` riêng của ảnh đó (§8.5); `click`, `js`, `type` → bỏ qua,
  ghi log (đợt 3, cần UI chạm vào ảnh).
- **Header nguồn có áp cho ảnh không**: `[UNKNOWN]` (U29). Bảng chéo trên 175 nguồn tranh `[quan sát]`:

  | Header nguồn có `Referer` | Ảnh tự gắn `headers` | Số nguồn |
  |---|---|---|
  | không | không | 103 |
  | không | có | 35 |
  | có | không | 29 |
  | có | có | 8 |

  29 nguồn chỉ khai `Referer` ở cấp nguồn gợi ý header nguồn **có** đi theo request ảnh (nếu không, tác giả đã phải gắn riêng như 35
  nguồn kia). Khuyến nghị: header ảnh = header nguồn đã đánh giá (§3.10 phần 1, gồm header đăng nhập §10.6) ⊕ cookie trong kho của
  tên miền ảnh ⊕ `headers` của khối option (khoá trùng thì option thắng, so không phân biệt hoa thường). Không có `Referer` sau khi gộp
  → thêm `Referer` = URL trang chương (hành vi tự nhiên của trình duyệt) `[đề xuất]`.
- Tải ảnh qua **client HTTP của engine Legado** (để có kho cookie, header nguồn, `concurrentRate`) chứ không qua bộ tải ảnh chung của
  app `[đề xuất]`. `concurrentRate` (§4.1 phần 1) với ảnh `[UNKNOWN]` (U30): áp nguyên làm tranh chậm hẳn khi giá trị là `1000`.
  Khuyến nghị: ảnh **không** chịu `concurrentRate`, nhưng giới hạn tối đa 4 ảnh tải song song mỗi nguồn.
- Ảnh bìa (`coverUrl`) cũng có thể mang option: 5 nguồn tranh ở `ruleSearch.coverUrl`, 2 ở `ruleBookInfo.coverUrl` `[quan sát]`. Cùng
  luật gộp header như trên.

### §8.4 Nối với FreeBook

- Loại nội dung: `bookSourceType = 2` → `ExtensionContentKind.comic` (§1.6 phần 1), trừ khi sách có ghi đè `book.type` (§13.6).
- Mỗi ảnh → `ComicPageSource(link: URL đã ghép, headers: header đã gộp, referer: Referer đã gộp)`. Không dùng `script` của
  `ComicPageSource` (đó là cơ chế của tiện ích JS khác); giải mã ảnh của Legado đi qua `imageDecode` (§8.6) `[đề xuất]`.
- Đọc qua router `BookContentDestination` → `ComicReaderView`; tiến độ là chỉ số ảnh trong `Book.currentChapterPage` và ghi qua
  `ReadingProgressStore.checkpoint` (quy ước comic hiện có). Tải offline đi qua `ComicOfflineStore` như comic tiện ích; ảnh đã giải mã
  (§8.6) được lưu ở dạng đã giải mã `[đề xuất]`.
- Kết quả `content` của tranh **không** được cache trong `ChapterContentRepository` (đó là kho văn bản). Nếu cần cache danh sách ảnh
  thì cache riêng theo `(nguồn, chapterUrl)` trong bộ nhớ, sống theo phiên `[đề xuất]`.

### §8.5 `imageStyle`

- Giá trị gặp (mọi loại) `[quan sát]`: loại 2: `FULL` 108, `full` 2, `Full` 1, CSS rác 1; loại 0: `0` 247, `FULL` 104, `full` 20, `TEXT`
  12, `DEFAULT` 2, `0.0` 2, `text`/`Text`/`FULl` mỗi loại 1; loại 1: `0` 13; loại 3: `FULL` 7.
- Nghĩa có tài liệu: khi ảnh trong chương bị thu quá nhỏ, đặt kiểu ảnh là `full` để ảnh chiếm trọn bề ngang `[tài liệu appHelp.md]`.
  So khớp không phân biệt hoa thường `[đề xuất]`.
- `TEXT`: 12 nguồn loại 0, đều là trang có ảnh chen trong chữ (`🏷晋江文学…`, `🔞第一版主` thay chữ bằng ảnh nhỏ) `[quan sát]`.
  `[UNKNOWN]` (U31): có thể là "ảnh hiển thị cùng dòng, cỡ như một ký tự". Các giá trị khác (`0`, `DEFAULT`, CSS) → mặc định.
- Ghi theo sách: `book.imageStyle = 'FULL' | 'TEXT'` trong `content` (6 nguồn loại 0, chọn theo nhánh dò ứng dụng) và option `style`
  theo từng ảnh (§8.3) `[quan sát]`. Thứ tự ưu tiên `[đề xuất]`: `style` của ảnh > `book.imageStyle` > `ruleContent.imageStyle`.
- Áp vào FreeBook `[đề xuất]`:
  - màn tranh: luôn khớp bề ngang (đúng nghĩa `FULL`), không cần đọc giá trị;
  - ảnh trong truyện chữ (đợt sau, §5.5.2 phần 1 đang bỏ ảnh): `FULL` → khối ảnh rộng bằng cột chữ; `TEXT` → ảnh cao bằng một dòng,
    nằm cùng dòng; còn lại → khối ảnh cỡ gốc, thu nhỏ nếu rộng hơn cột chữ.

### §8.6 `imageDecode`

- **Tài liệu** `[tài liệu ruleHelp.md]`: trường chứa mã JS, dùng khi ảnh cần giải mã thêm một lần sau khi tải. Biến: `java` (chỉ các
  hàm tiện ích JS), `result` = **mảng byte** của ảnh vừa tải, `src` = link ảnh. Giá trị trả về = **mảng byte** sau giải mã. Tài liệu có hai
  ví dụ: giải AES bằng `java.createSymmetricCrypto(…).decrypt(result)`, và XOR từng byte qua `Packages.java.io.ByteArrayInputStream` /
  `ByteArrayOutputStream`.
- **Corpus**: 7 nguồn có giá trị (5 loại 2, 2 loại 0) `[quan sát]`:

  | Nguồn | Cách giải | Cần gì |
  |---|---|---|
  | `🎨51漫画` | `java.createSymmetricCrypto("AES/CBC/NoPadding", key, iv).decrypt(result)` | AES không đệm |
  | `🎨漫蛙` | AES `aes/cbc/pkcs7padding`, khoá lấy `cache.get("manwa_aes_key") \|\| "…"` | `cache` trong ngữ cảnh |
  | `🎨🔞（favcomic）喜漫漫画` | `decode(result)` — hàm `decode` nằm trong `jsLib` (mã bị làm rối) | **nạp `jsLib`** trong ngữ cảnh giải mã |
  | `🎨🔞禁漫天堂`, `🔞🎨禁漫天堂API` | xếp lại các dải ngang của ảnh bằng `android.graphics` (`BitmapFactory.decodeByteArray`, `Bitmap.createBitmap`, `Canvas.drawBitmap`, `Rect`, `Paint`, `Bitmap.compress(PNG, 100, out)`), số dải tính từ `java.md5Encode(bookId + imgId)` lấy từ `src` | shim đồ hoạ (đợt 3) |
  | `🎃刺猬猫🎃#2` (loại 0) | `src.split("#")` rồi `BitmapFactory` + `cache.putMemory` | `src` giữ cả phần `#…` |
  | `🏷七猫四合一本地版` (loại 0) | `result` (trả nguyên) | – |

- **Đặc tả** `[đề xuất trừ khi ghi khác]`:
  1. Chạy **sau khi tải xong** từng ảnh của nguồn có `imageDecode` không rỗng, trước khi lưu cache/hiển thị. Áp cho ảnh nội dung chương
     (tranh và ảnh trong truyện chữ); ảnh bìa dùng `coverDecodeJs` (§8.7), không dùng `imageDecode`.
  2. Ngữ cảnh JS: một ngữ cảnh mỗi ảnh (hoặc dùng lại trong một chương, tuần tự), có `java`, `source`, `cookie`, `cache`, `book`,
     `chapter`, `src`, `result`; nạp `jsLib` trước (cần cho favcomic). Hàm mạng (`java.ajax`…) vẫn dùng được nhưng tính vào giới hạn thời
     gian 5 giây/ảnh.
  3. `src` = **chuỗi URL đầy đủ như trong `<img src>`, gồm khối `,{option}` và phần `#…` nếu có** `[quan sát: 刺猬猫 tách theo "#",
     禁漫天堂 tìm "photos/(\d+)/(\d+)" trong src]`. `[UNKNOWN]` (U32): gốc có cắt khối option khỏi `src` không; khuyến nghị **giữ nguyên**
     (regex của các mẫu không bị ảnh hưởng bởi phần đuôi).
  4. `result` = mảng byte (`Uint8Array`, §6.3 phần 1) có thêm `length`, chỉ số `[i]`; cũng nhận được ở chỗ API Java cần mảng byte
     (`decrypt(result)`, `BitmapFactory.decodeByteArray(result, 0, result.length)`).
  5. Giá trị trả về: mảng byte (`Uint8Array`, mảng số, mảng byte của shim Java) → dùng; `undefined`/`null`/chuỗi/rỗng → **dùng byte gốc**
     và ghi log; ném lỗi → byte gốc + log. Nhiều nguồn tự `return result` khi không cần giải (禁漫天堂 với GIF) `[quan sát]`.
  6. Kiểm tra byte trả về có phải ảnh (PNG/JPEG/GIF/WebP theo chữ ký đầu tệp); không phải → byte gốc + log.
- Shim `android.graphics` cho 2–3 nguồn trên: đợt 3, giới hạn đúng các thành viên đã thấy (§14.6). Chưa có shim → JS ném lỗi → ảnh gốc
  (bị xáo dải) hiển thị, kèm log rõ "cần shim đồ hoạ" `[đề xuất]`.

### §8.7 `coverDecodeJs`

- **Tài liệu** `[tài liệu ruleHelp.md]`: giống giải mã ảnh, nhưng `result` là **luồng đọc (input stream)** của ảnh bìa; hai ví dụ: AES
  `decrypt(result)`, và vòng `data.read()` tới `-1` rồi XOR.
- **Corpus**: 249 nguồn có khoá, 2 có giá trị, đều loại 2 `[quan sát]`: `🎨51漫画` (`createSymmetricCrypto("AES/CBC/PKCS5Padding",
  key, iv).decrypt(src)` — đặt tên tham số là `src` nhưng truyền `result`) và favcomic (`decode(result)` từ `jsLib`).
- **Đặc tả** `[đề xuất]`: chạy khi tải ảnh bìa của sách thuộc nguồn này (danh sách tìm kiếm/khám phá, trang sách, kệ). `result` là đối
  tượng **vừa là mảng byte vừa là luồng**: có `length`, `[i]`, và `read()` trả byte kế (0–255) hoặc `-1` khi hết, `read(buf)` điền mảng; mọi
  hàm nhận mảng byte (`decrypt`, `decryptStr`, `java.bytesToStr`…) chấp nhận đối tượng này. `src` = URL bìa (gồm option). Trả về và xử lý
  lỗi như §8.6 bước 5–6. Bìa đã giải mã mới được lưu vào `covers/<sha256(bookId)>.jpg` (đổi định dạng sang JPEG nếu cần).

### §8.8 Phân trang nội dung tranh

- `nextContentUrl` có giá trị ở 11 nguồn tranh `[quan sát]`: `text.下一页@href` (2), `text.下页@href`, `text.下一章@href`,
  `text.末页@href` + JS dựng danh sách trang, `@css:a:contains(下一页), a:contains(下一頁)@href`, `class.view-bottom-bar@li.2@a@href`,
  `class.read-footer@tag.a@href`, JS chọn theo tên miền, và một giá trị rác `mhpic.zymkcdn.com`.
- Dùng đúng thuật toán §5.6 phần 1, **URL dừng = URL chương kế** trong mục lục: `text.下一章@href` của `🎨🔞老司机` là link sang chương
  sau; không dừng thì một chương kéo theo cả bộ truyện `[quan sát]`.
- Ghép: chuỗi HTML các trang nối bằng `\n` **rồi** mới tách ảnh (§8.2) → thứ tự ảnh = thứ tự trang, trong trang theo thứ tự thẻ.
- 7 nguồn tự gọi mạng trong `content` để gom nhiều trang (`Array.from({length:pageSum-1}, (_,i)=>java.ajax(…))`, `java.post(…).body()`)
  `[quan sát]`: không cần gì thêm ngoài §6.4 phần 1.
- Giới hạn 30 trang như văn bản (§5.6 phần 1); ảnh mỗi chương không giới hạn cứng nhưng ghi log khi > 500 `[đề xuất]`.

### §8.9 Hàm bridge hay gặp ở nguồn tranh

Đếm trên 175 nguồn loại 2 (lần) `[quan sát]`: `java.getString` 137, `java.log` 113, `java.toast` 32, `java.longToast` 31, `java.t2s` 30,
`java.getStringList` 21, `java.timeFormat` 21, `java.get`/`java.put` 20, `java.base64Decode` 17, `java.md5Encode` 15, `java.getElements`
14, `cache.put` 13, `java.aesBase64DecodeToString` 12, `java.md5Encode16` 11, `java.connect` 8, `java.startBrowser` 7,
`java.startBrowserAwait` 7, `java.refreshExplore` 6, `java.refreshTocUrl` 5, `java.createSymmetricCrypto` 5.

- Mọi hàm trên đã có ở phần 1 trừ nhóm trình duyệt hiện cho người dùng (§10.8), `refreshExplore` (§11.5), `refreshTocUrl` (§13.3).
- `java.t2s` nhiều vì trang tranh Đài Loan/Hồng Kông dùng chữ phồn thể.
- `Reload(url)` (10 nguồn, cùng một tác giả) **không** phải hàm bridge mà là hàm trong `jsLib` dạng map trỏ tới
  `https://qyyuapi.com/sy/js/<tên>/jsLib.js`; toàn bộ rule tải từ máy chủ đó lúc chạy. Các nguồn này còn để dữ liệu mã hoá trong
  `variableComment` (§12.5) và dùng `preUpdateJs` đổi tên miền (§13.3). Chạy được hay không phụ thuộc máy chủ ngoài; bộ nghiệm thu ghi
  riêng nhóm này `[quan sát]`.

### §8.10 Ví dụ biên

| Đầu vào `content` (sau `replaceRegex`) | Ảnh ra |
|---|---|
| `<img src="/a/1.jpg">\n<img src="/a/2.jpg">` (trang `https://h.com/c/9.html`) | `https://h.com/a/1.jpg`, `https://h.com/a/2.jpg` |
| `<img src="https://i.com/1.jpg,{"headers":{"Referer":"https://h.com/"}}">` | URL `https://i.com/1.jpg`, header `Referer: https://h.com/` |
| `<img class="lazy" data-original="//i.com/1.jpg">` (không có `src`) | `https://i.com/1.jpg` (luật lười, §8.2) |
| `<img src="data:image/gif;base64,R0lG…" data-src="/p/1.webp">` | `https://h.com/p/1.webp` |
| `https://i.com/1.jpg\nhttps://i.com/2.jpg` (không có thẻ) | hai ảnh |
| `【刷新正文】播放\n✅直链:\nhttps://jx.x/?url=…` | không có ảnh → hiện chữ + link (§8.2 bước 6) |
| JS trả danh sách 3 phần tử `<img src="…">` | outer HTML 3 thẻ → 3 ảnh |

---

## §9. Video (`bookSourceType = 4`)

> Tài liệu được phép **không** có mục nào về nguồn sách loại video. Thứ gần nhất là phần "loại nguồn đăng ký" của `rssRuleHelp.md`:
> với nguồn đăng ký kiểu video, link lấy từ rule link hoặc rule nội dung được phát bằng trình phát dựng sẵn `[tài liệu rssRuleHelp.md]`.
> Mọi thứ dưới đây là `[quan sát]` trên **13 nguồn** (12 trong corpus + `西瓜卡通（优+）` của `yck_1111`) hoặc `[UNKNOWN]`. Mẫu nhỏ:
> bộ nghiệm thu phải đo lại trước khi coi là chắc.

### §9.1 Mẫu đã quan sát

| Nguồn (bộ) | Mục lục | `content` | Ghi chú |
|---|---|---|---|
| `🎬非凡资源网`, `🎬量子资源网` (1315) | JS tách `vod_play_url` của API kiểu MacCMS (§9.2) | `result = baseUrl;` (+ `java.toast`) | chương **là** URL `.m3u8` |
| `🎬🔞VirtalTaboo直播` (1315) | `$..item`, `chapterUrl` dựng URL `.m3u8` bằng JS | **rỗng** (`ruleContent: {}`) | phát trực tiếp (live) |
| `🎬GScenes短剧` (1272) | `$.items`, `chapterUrl` = API `…/playback` | `$.play_url` | API JSON |
| `🎬🔞黄豆短剧` ×2 (1315, 1272; hai tên miền) | `a.dm-ep` | JS tìm `data-ep-src` trong HTML theo tham số `ep` | trả URL media |
| `🎬电源先生` (1315), `🎬七猫短剧` (1272) | `class.play-source-content.0@tag.a`, `.pcDrama_catalogItem` | JS parse đối tượng `player_aaaa` trong HTML, trả `data.url` | có `sourceRegex` `.*\.(m3u8\|mp4).*` / `.*\.(m3u8\|mp4\|flv).*` |
| `🎬U酷资源`, `🎬红牛资源` (1315) | `@css:a@text##(.+)\$(.+)##$2` | URL đã là `.m3u8` → dùng luôn; không thì parse trang `/share/…` lấy `url` | dùng `java.htmlFormat` |
| `🎬榴莲影视` (1315) | JS gộp danh sách **mọi tuyến**, ghi tên tuyến vào `updateTime` | ghép URL trang giải mã (`https://jx.…/?url=`) theo tuyến, `java.startBrowser(...)` cho chương đang đọc, trả **chữ** kèm link | §9.6 |
| `🎬艾格动漫` (1315) | tuyến chọn bằng `source.getVariable()` | `java.startBrowser(iframeSrc, title)`, trả **HTML hướng dẫn** | `searchUrl` có `"webview":true` (chữ `v` thường) |
| `西瓜卡通（优+）` (1111) | JS dựng mục lục, tên tuyến là mục `isVolume` | `#video_content@iframe@src` + `java.startBrowser`, trả chữ kèm link | – |

Ngoài loại 4 còn có `[quan sát]`: 2 nguồn **loại 2** thực chất là video (§8.1), và một nguồn loại 0 gộp phim lẫn truyện
(`🎬📷终极全栖接口聚合`) tự đổi loại theo từng sách bằng `book.setType(isArt ? 0 : 4)` (§13.6).

Cấp nguồn: `header` 7/13 (UA ở cả 7, `Referer` ở 3: hai `黄豆短剧`, `GScenes短剧`), `enabledCookieJar = true` 8/13, `sourceRegex` có giá
trị 2/13, `loginUrl` 4/13 (URL trang chủ hoặc JS mở trình duyệt). Hàm bridge trong 12 nguồn loại 4 (lần): `java.getString` 8,
`java.toast` 7, `java.startBrowser` 6, `java.ajax` 5, `java.getStringList` 5, `java.getElements` 3, `java.refreshExplore` 2,
`java.openWeb` 2, `java.htmlFormat` 2 `[quan sát]`.

### §9.2 Danh sách tập và "tuyến" phát

- Danh sách tập **chính là mục lục** (`ruleToc`, §5.4 phần 1), mỗi chương là một tập. Không có khoá rule riêng cho tập `[quan sát]`.
- **Không có khái niệm server/tuyến ở cấp rule** `[quan sát]`. Các nguồn tự trải tuyến vào mục lục theo bốn cách:
  1. chỉ lấy một tuyến cố định: `🎬非凡资源网` lấy phần tử thứ hai sau khi tách `$$$` (`lines.length > 1 ? lines[1] : lines[0]`);
  2. nối mọi tuyến thành một danh sách, tên tuyến đặt ở `updateTime` (`🎬榴莲影视`);
  3. chèn mục `isVolume` mang tên tuyến trước các tập của tuyến đó (`西瓜卡通（优+）`);
  4. chọn tuyến bằng biến nguồn, người dùng sửa biến rồi làm mới (`🎬艾格动漫`, phần giới thiệu in sẵn "源变量：N" cho từng tuyến).
- **Định dạng MacCMS** (đã curl `http://23.225.142.42/api.php/provide/vod/?ac=detail&wd=三体&pg=1`): `vod_play_from` =
  `feifan$$$ffm3u8` (tên tuyến, cách nhau `$$$`); `vod_play_url` gồm các tuyến cách nhau `$$$`, mỗi tuyến là `tên tập$URL` nối bằng `#`.
  Tuyến 1 là trang chia sẻ `https://…/share/<id>`, tuyến 2 là `…/index.m3u8` `[quan sát]`. Trang chia sẻ (đã curl
  `https://vip.ffzy-plays.com/share/fd2c18a27361dd16124f2780015b05f3`) chứa `url = "/…/index.m3u8?sign=…"` — đường dẫn tương đối, có chữ
  ký; khớp cách `🎬U酷资源`/`🎬红牛资源` tự dựng URL `.m3u8` từ trang `/share/`.
- Nối với FreeBook `[đề xuất]`: mỗi chương (không phải `isVolume`) → một `Episode`; mục `isVolume` → tiêu đề nhóm trong lưới tập
  (`BookDetailVideoTOCGrid`), không bấm được; mỗi tập có **đúng một** `VideoServer`. Không cố tách tuyến thành chip server (không có
  dữ liệu cấu trúc để làm việc đó an toàn).

### §9.3 Từ chương ra nguồn phát

**Thuật toán** `[đề xuất, bằng chứng ở từng nhánh]`:

1. **`content` rỗng** → phát thẳng `chapterUrl` (`🎬🔞VirtalTaboo直播`: `ruleContent` rỗng, `chapterUrl` là `.m3u8`) `[quan sát]`.
2. **`chapterUrl` trỏ thẳng tới tệp media** (đường dẫn kết thúc `.m3u8`, `.mp4`, `.flv`, `.m4v`, `.mov`, `.ts`, không phân biệt hoa thường,
   bỏ query): **không tải thân** (tệp có thể rất lớn); chạy `content` với `result = ""`, `src = ""`, `baseUrl = chapterUrl`. Đủ cho
   `result = baseUrl;` (非凡, 量子) và `if(/.*\.m3u8.*/.test(baseUrl)){url=baseUrl}` (U酷, 红牛) `[quan sát]`. `[UNKNOWN]` (U33): gốc có tải
   thân trong trường hợp này không; nếu `content` cần thân thì nguồn sẽ hỏng — bộ nghiệm thu kiểm 13 nguồn.
3. Ngược lại: tải `chapterUrl` như truyện chữ (option, `webView`, §4.4 phần 1; `sourceRegex` §9.4), chạy `content` (`getString`) → chuỗi
   `R`. Không phân trang `nextContentUrl` cho video (không nguồn video nào có) `[đề xuất]`.
4. Diễn giải `R` (trim):
   1. `R` (bỏ khối `,{option}` cuối) là URL tuyệt đối `http(s)://…` duy nhất → **URL phát**; khối option (nếu có) cho `headers`.
      Tương đối (`/…`) → ghép với URL cuối của trang chương (`🎬🔞黄豆短剧` tự ghép, nhưng engine vẫn nên ghép phòng hờ).
   2. `R` là văn bản có lẫn URL (榴莲, 西瓜卡通, 艾格动漫 trả chữ "【刷新正文】播放 ✅直链: <url>") → lấy URL **cuối cùng** trong văn bản
      có đuôi media; không có thì URL `http(s)` cuối cùng; vẫn không có thì dùng URL ứng viên ghi lại từ `java.startBrowser` (§9.6).
      Hiển thị phần chữ (đã làm sạch) dưới trình phát như ghi chú `[đề xuất]`.
   3. Rỗng → lỗi "không lấy được nguồn phát" kèm log.
5. Phân loại URL phát → `VideoTrack` của FreeBook:
   - đuôi media hoặc option khai `type` media → `.native`, `data` = URL, `headers` = §9.5;
   - còn lại (trang nhúng `iframe`, trang giải mã `…/?url=…`, `dplayer`) → `.webview`: nạp trang bằng `VideoMediaSniffer` và lấy URL media
     bắt được; nếu nguồn có `sourceRegex` thì chỉ nhận URL khớp regex đó (§9.4) `[đề xuất]`.

**Không cache, không tải trước** URL phát: URL có chữ ký hết hạn (`?sign=…`, `?pkey=…`) `[quan sát]`. Giải lại mỗi lần bấm phát; không lưu
vào `ChapterContentRepository`; không tải video offline ở đợt này `[đề xuất]`.

### §9.4 `sourceRegex`

- **Tài liệu**: có hàm dùng WebView lấy **URL tài nguyên** khớp một regex: `java.webViewGetSource(html, url, js, sourceRegex)`
  `[tài liệu jsHelp.md]`, bản bất đồng bộ `webViewGetSourceAwait(…, sourceRegex, cacheFirst, delayTime)` `[tài liệu rssRuleHelp.md]`, và
  `getStrResponse(jsStr, sourceRegex)` trong ngữ cảnh kiểm tra đăng nhập `[tài liệu ruleHelp.md]`. Trường `ruleContent.sourceRegex` dùng
  cùng ý: khi nội dung chương tải bằng WebView, request tài nguyên đầu tiên có URL khớp regex trở thành "nội dung" `[quan sát]`.
- **Corpus**: 403 nguồn có khoá, 12 có giá trị. 8 nguồn dùng đúng nghĩa media: 2 video (`.*\.(m3u8|mp4).*`, `.*\.(m3u8|mp4|flv).*`),
  5 audio (`.*\.(mp3|m4a).*`, …; 1 trong số đó là loại 0), 1 nguồn loại 3 (`.*\.(jpg|png).*`). 4 nguồn còn lại là rule đặt nhầm chỗ
  (`#pb_next@href`, `##本页章节列表结束！`) `[quan sát]`.
- **Mẫu audio rõ ý nhất** (`🔊恋听网吧`, `🔊蜻蜓M`): `chapterUrl: tag.a@href@js:result+',{webView:“true”}'` (nháy cong!), `content:
  <js>result</js>`, `sourceRegex: .*\.(mp3|m4a).*` → WebView nạp trang chương, URL media khớp regex thành `result`, `content` trả nguyên nó
  `[quan sát]`.
- **Đặc tả** `[đề xuất]`:
  1. Áp khi request nội dung chương **là request WebView** (option `webView` truthy) **và** `sourceRegex` không rỗng: nạp trang (kèm header,
     body nếu POST), theo dõi mọi URL request của trang và các frame (điều hướng, XHR, fetch, media — FreeBook đã có
     `WebNetworkCaptureScript`/`VideoMediaSniffer`), URL đầu tiên khớp regex (khớp **toàn chuỗi** URL tuyệt đối; regex dạng `.*x.*` cho
     cùng kết quả với khớp một phần) → **thân phản hồi = URL đó**, `baseUrl` giữ là URL trang; dừng nạp.
     Hết thời gian (30 s, §4.3 phần 1) → lỗi "không bắt được tài nguyên".
  2. Request **không** phải WebView: bỏ qua `sourceRegex` ở bước tải. Bằng chứng: `🎬电源先生`, `🎬七猫短剧` có `sourceRegex` nhưng `content`
     parse `player_aaaa` từ HTML tải thường — nếu `sourceRegex` cướp thân thì JS này nhận một URL và trả rỗng `[quan sát]`. `[UNKNOWN]`
     (U34): gốc có tự bật WebView khi có `sourceRegex` không.
  3. Ở bước phát (`.webview`, §9.3 bước 5), `sourceRegex` (nếu có) làm bộ lọc ứng viên cho `VideoMediaSniffer`.
  4. Regex không biên dịch được → bỏ qua, log. Lưu ý mẫu `https?://.*\\.mp3.*` (`🔊🔞有声骚麦`): trong chuỗi JSON đã giải là hai dấu `\`,
     tức regex đòi một dấu `\` thật trong URL → không bao giờ khớp. Nguồn đó không dùng WebView nên vô hại; engine không tự "sửa" regex.

### §9.5 Header khi phát

- Header phát `[đề xuất]` = header nguồn đã đánh giá (§3.10 phần 1, gồm header đăng nhập §10.6) ⊕ cookie của kho cho tên miền media ⊕
  `headers` trong khối option của URL phát (thắng khi trùng). Lý do: `GScenes短剧`, hai `黄豆短剧` khai `Referer` ở header nguồn và
  không gắn ở đâu khác, nên phải đi theo request media mới có ý nghĩa `[quan sát]`.
- Gắn vào `VideoTrack.headers`; FreeBook tự tách `User-Agent` sang `AVURLAssetHTTPUserAgentKey` (`VideoPlaybackSession`). Với `.webview`,
  `VideoMediaSniffer` đặt `Referer` theo frame phát request — giữ nguyên hành vi đó.
- Không có header nguồn: không thêm `Referer` (khác ảnh tranh) `[đề xuất]`: nhiều CDN video chấp nhận request trống `Referer`.

### §9.6 `java.startBrowser` trong `content` video

- 3/13 nguồn video (`🎬榴莲影视`, `🎬艾格动漫`, `西瓜卡通（优+）`) và 2 nguồn loại 2 giả video gọi `java.startBrowser(url, title)`
  trong `content` **chỉ khi** `book.durChapterIndex == chapter.index`,
  tức chỉ cho chương đang mở, không cho chương được tải trước; rồi trả chữ hướng dẫn "【刷新正文】播放" `[quan sát]`. Đây là cách cũ: trình
  duyệt hiện cho người dùng làm trình phát. Ghi chú của `🎬非凡资源网` khuyên xoá dòng `java.startBrowser(...)` "nếu chỉ muốn địa chỉ phát
  mà không muốn trình phát bật ra lặp lại" → ứng dụng mới phát được URL do `content` trả về bằng trình phát riêng `[quan sát]`.
- **Đặc tả** `[đề xuất]`: trong ngữ cảnh `content` của **nguồn/sách loại video**, `java.startBrowser(url, title)` **không** mở trình duyệt;
  ghi `(url, title)` làm "ứng viên phát" (§9.3 bước 4.2), log, trả `undefined`. Ở mọi ngữ cảnh khác giữ đặc tả §10.8.
- `java.openWeb(url)` (2 nguồn video, trong `loginUrl`, luôn bọc `try … catch` rồi rơi về `java.startBrowser`) → **không định nghĩa**
  để nhánh dự phòng chạy `[đề xuất]`.

### §9.7 Nối với FreeBook

- `bookSourceType = 4` → `ExtensionContentKind.video` → `VideoPlayerScreen` qua `BookContentDestination` (§1.6 phần 1).
- Tiến độ: **số giây** trong `Book.currentChapterPage`, ghi bằng `ReadingProgressStore.checkpoint`; trình phát chiếm `AVAudioSession` và
  tạm dừng TTS (quy ước video hiện có).
- Biến `book.durChapterIndex`/`chapter.index` phải đúng chương đang phát khi chạy `content` (nguồn dùng phép so sánh này, §9.6).
- Kiểm tra phát được (bộ nghiệm thu): với mỗi nguồn video, giải URL phát của tập đầu và tải 1 KB đầu; `.m3u8` phải bắt đầu `#EXTM3U`
  `[đề xuất]`.

### §9.8 Chắc chắn và chưa chắc

| Điểm | Mức |
|---|---|
| Danh sách tập = `ruleToc`; tập = chương | `[quan sát]`, 13/13 |
| `content` trả URL phát (9 nguồn) hoặc rỗng = phát `chapterUrl` (1 nguồn) là kiểu mới | `[quan sát]`, 10/13 |
| Không có cấu trúc server/tuyến ở cấp rule | `[quan sát]`, 13/13 |
| `sourceRegex` chỉ có tác dụng với request WebView | `[UNKNOWN]` U34 |
| Không tải thân khi `chapterUrl` là tệp media | `[UNKNOWN]` U33 |
| `content` trả chữ + `startBrowser` nghĩa là "mở trang phát" | `[quan sát]` 3 nguồn loại 4 + 2 loại 2; cách FreeBook xử lý là `[đề xuất]` §9.6 |
| Header nguồn đi theo request media | `[đề xuất]` dựa trên 3 nguồn |

### §9.9 Ví dụ biên

| Chương / `content` | Nguồn phát |
|---|---|
| `chapterUrl = https://v.x/1/index.m3u8`, `content = @js:result = baseUrl;` | native `https://v.x/1/index.m3u8`, không tải thân |
| `content` rỗng, `chapterUrl = https://edge-hls…/master/123_auto.m3u8?pkey=…` | native, phát thẳng |
| `content = $.play_url`, thân `{"play_url":"https://c.x/a.mp4"}` | native `https://c.x/a.mp4` |
| `content` trả `<p>【刷新正文】播放\n✅直链:\nhttps://jx.y/?url=https://c.x/a.m3u8` | URL cuối có đuôi media: `https://c.x/a.m3u8` (native) |
| `content` trả `https://jx.y/dplayer/?url=abc` | webview: sniff trang, nhận URL khớp `sourceRegex` nếu có |
| chapterUrl `…,{webView:“true”}`, `sourceRegex: .*\.(m3u8\|mp4).*`, `content: <js>result</js>` | WebView bắt URL media đầu tiên khớp → native |

---

## §10. Đăng nhập và trình duyệt hiện cho người dùng

### §10.1 Số liệu

`loginUrl` có giá trị ở **494 nguồn** (mọi loại) `[quan sát]`:

| Dạng `loginUrl` | Số nguồn | Ví dụ |
|---|---|---|
| URL tuyệt đối | 279 | `https://www.qidian.com/` |
| JS định nghĩa hàm `login` | 60 | `function login() { … source.getLoginInfoMap() … }` |
| chữ không phải URL/JS (chú thích, ký hiệu) | 54 | `｡◕‿◕｡` (6), `\\目录列表规则处添加账号信息` (6), `coolapk@芜恙` |
| rác `{"url": "null"}` | 46 | – |
| JS không có `login` | 22 | `this.sethost = function() {…}` (hàm dùng chung, nạp bằng `eval(String(source.loginUrl))`, §5.8 phần 1) |
| có tiền tố `@js:` / `<js>` | 19 | `@js:function qsskel(o) {…}` |
| URL tương đối | 14 | `/`, `/login.php`, `login.php?jumpurl=…` |

`loginUi` có giá trị ở **96 nguồn**: 46 là mảng JSON chuẩn, khoảng 27 là mảng JSON "lỏng" (khoá không nháy, phẩy thừa — parser §1.2.1
phần 1 xử lý được), 16 là JS (`@js:`/`<js>`) trả `JSON.stringify([...])`, 7 hỏng cả khi parse lỏng đơn giản `[quan sát]`. 75/96 nguồn có
`loginUrl` định nghĩa `login`. 25/96 chỉ có nút (dùng `loginUi` làm **menu cài đặt** của nguồn: "⚡ 智能换源", "🔄 切换域名"); 65/96 có ô nhập.

`loginCheckJs` có giá trị ở **52 nguồn** (§10.7). Hàm liên quan (lần/nguồn, mọi loại): `source.getLoginInfoMap` 141/50,
`source.putLoginHeader` 39/35, `source.getLoginHeader` 37/14, `source.putLoginInfo` 18/17, `source.getLoginHeaderMap` 16/4,
`source.getLoginInfo` 11/9, `source.removeLoginHeader` 10/8, `java.startBrowser` 113/54, `java.startBrowserAwait` 138/45,
`java.getVerificationCode` 13/10, `java.upLoginData` 9/8, `java.startBrowserDp` 8/7, `java.getStrResponse` 8/6, `java.initUrl` 5/3,
`java.ruleUrl` 7/7 `[quan sát]`. `source.login()` có trong tài liệu nhưng **0** lần trong corpus.

### §10.2 Ba chế độ đăng nhập

Tài liệu: `loginUrl` điền được hoặc một link đăng nhập, hoặc mã JS hiện thực logic cho form `loginUi`; khi có `loginUi` thì không dùng
trang web nhúng để đăng nhập mà dùng JS trong `loginUrl`, có thể kiểm kết quả bằng `loginCheckJs`; từ bản 20221113, nút của form gọi được
hàm trong `loginUrl` và bắt buộc phải có hàm `login` `[tài liệu ruleHelp.md]`.

Phân loại khi người dùng chọn "Đăng nhập" cho một nguồn `[đề xuất, khớp tài liệu]`:

| `loginUi` | `loginUrl` | Hành vi |
|---|---|---|
| rỗng | URL tuyệt đối/tương đối (ghép với `bookSourceUrl`) | **Trình duyệt đăng nhập**: mở trình duyệt hiện cho người dùng (§10.8) tại URL; người dùng đăng nhập trên trang; đóng → đồng bộ cookie của `WKWebsiteDataStore` cho các tên miền đã ghé về kho cookie của nguồn (§4.2 phần 1). Không đọc gì khác |
| có | JS (bỏ tiền tố `@js:`/`<js>…</js>` nếu có) | **Form gốc** (§10.3–§10.4) |
| rỗng | JS có `login` | Form không ô nhập, chỉ nút "Đăng nhập" gọi `login()` `[UNKNOWN]` U35 |
| bất kỳ | rỗng, rác `{"url":"null"}`, chữ không phải URL/JS | Không có đăng nhập: ẩn mục "Đăng nhập" |

Nhận dạng "JS": chuỗi chứa `function`, `=>`, `java.`, `source.`, `eval(`, `var `/`let `/`const ` sau khi bóc tiền tố; "URL": khớp
`^https?://` hoặc `^/` hoặc `^[\w.-]+\.(php|html?|aspx?)` `[đề xuất]`. Chuỗi khác → coi là rỗng, ghi log một lần.

### §10.3 `loginUi`: định dạng form

- **Dạng**: mảng các object; hoặc JS trả mảng/chuỗi JSON của mảng (chạy với `source`, `java`, `cookie`, `cache`, có nạp `jsLib`)
  `[quan sát: 16 nguồn, ví dụ "<js>JSON.stringify([{name:'检查访问状态',type:'button',action:'checkSite()'}])</js>"]`. Parse lỏng §1.2.1.
  Đánh giá lại mỗi lần mở form (form JS có thể phụ thuộc trạng thái, ví dụ hiện "当前：未登录").
- **Khoá của mục** (đếm trên mảng parse được) `[quan sát]`: `name` 803, `type` 803, `action` 633, `style` 579, `default` 32, `chars` 17,
  `viewName` 12, `hint` 2, `placeholder` 2, `variable` 2. Tài liệu chỉ minh hoạ `name`, `type` (`text`, `password`, `button`), `action`,
  `style` `[tài liệu ruleHelp.md]`.
- **Kiểu** (số nguồn có kiểu đó): `button` 79, `text` 65, `password` 48, `select` 5, `toggle` 4, `input` 2, `title` 1 `[quan sát]`.

| `type` | Hiển thị | Giá trị đưa vào thông tin đăng nhập | Nhãn |
|---|---|---|---|
| `text` | ô nhập một dòng; nhãn = `name` | chuỗi người dùng nhập, khoá = `name` | `[tài liệu ruleHelp.md]` |
| `password` | ô nhập che ký tự | như trên | `[tài liệu ruleHelp.md]` |
| `button` | nút; bấm → chạy `action` (§10.4) | **không** lưu | `[tài liệu ruleHelp.md, jsHelp.md]` |
| `select` | danh sách chọn từ `chars` (mảng chuỗi), mặc định `default` | chuỗi đã chọn | `[quan sát]` (`"chars": ["https://www.pilishuwu.com", …], "default": "https://www.pili45.com"`) |
| `toggle` | nút bật tắt hiển thị ký tự hiện tại trong `chars` (`["🔳","✅"]`), bấm → chuyển sang phần tử kế (vòng), rồi chạy `action` nếu có | ký tự hiện tại | `[quan sát]` |
| `title` | nhãn tĩnh | không | `[quan sát]` (`{"name":"用户名","type":"title"}`) |
| `input` | như `text`; `hint`/`placeholder` = chữ mờ | như `text` | `[UNKNOWN]` U36 (2 nguồn, có khoá `variable`) |
| kiểu lạ (`text文字关闭`…) | như `button` nếu có `action`, ngược lại bỏ | – | `[đề xuất]` |

- `viewName`: **biểu thức JS** cho nhãn hiển thị, thường là chuỗi có nháy (`"viewName": "'密码'"`) hoặc IIFE đọc trạng thái
  (`'邮箱/用户名（当前：'+(function(){…source.getLoginHeader()…})()+'）'`) `[quan sát: 12 lần]`. Đánh giá trong ngữ cảnh form; lỗi → dùng
  `name`. `name` luôn là khoá dữ liệu.
- `style`: cùng hệ bố cục flex với khám phá (§11.7).
- `action` (633 mục, phần lớn là `button`, còn lại `toggle`/`select`): gọi hàm không tham số `f()` 304, gọi hàm có tham số 264, URL
  `http(s)` 10, đoạn JS khác 40, rỗng 15 `[quan sát]`. URL → mở trình duyệt hiện cho người dùng tại URL đó (ví dụ trong tài liệu là link trang đăng ký) `[tài liệu ruleHelp.md]`.

### §10.4 Luồng form và hàm `login()`

`[đề xuất, các điểm có nhãn riêng]`:

1. Mở form: dựng mục từ `loginUi`; điền sẵn giá trị đã lưu (`getLoginInfoMap`, §10.5) cho mục cùng `name`; mục chưa có giá trị lấy
   `default`.
2. **Nút trong form** (`button` có `action` không phải URL, và `action` của `toggle`/`select` sau khi đổi giá trị): tạo ngữ cảnh JS mới
   (`java`, `source`, `cookie`, `cache`, nạp `jsLib`), **chạy toàn bộ `loginUrl`** để định nghĩa hàm, đặt `result` = map giá trị **hiện tại**
   trên form (đọc bằng `result.get(k)` lẫn `result[k]`) `[tài liệu ruleHelp.md: ví dụ đọc số điện thoại bằng result.get("telephone")]`, rồi
   chạy `action` như một đoạn JS. Lỗi → toast ngắn "Lỗi: <thông báo>" + log.
3. **Nút "Đăng nhập"** của app (luôn có khi `loginUrl` là JS): gom giá trị mọi mục không phải `button`/`title` thành map, đặt làm thông tin
   đăng nhập **tạm** (để `source.getLoginInfo()`/`getLoginInfoMap()` đọc được), chạy `loginUrl` rồi gọi `login()`.
   - `login()` hoàn tất không ném lỗi và không trả `false` → **thành công**: lưu bền thông tin đăng nhập. Tài liệu nói sau khi đăng nhập
     thành công thì mọi giá trị của form trừ mục `button` được **mã hoá rồi lưu** `[tài liệu jsHelp.md]`.
   - `login()` ném lỗi hoặc trả `false` (mẫu `番茄🍅`: `return false` khi thất bại) → **thất bại**: không lưu, giữ form mở, báo lỗi.
     `[UNKNOWN]` U37: gốc có coi `return false` là thất bại không.
4. `login()` thường: đọc thông tin, gọi `java.ajax`/`java.post` tới API đăng nhập, rồi `source.putLoginHeader(JSON.stringify({token…}))`
   hoặc để cookie tự vào kho; có thể gọi `java.getVerificationCode(urlẢnh)` (§10.8) `[quan sát]`.
5. Hàm phụ trợ của form `[quan sát, chưa có trong tài liệu được phép]`:
   - `java.upLoginData(map)` (8 nguồn): cập nhật giá trị đang hiện trên form theo map `{name: giá trị}` (mẫu ghi log "界面已刷新" = đã làm mới
     giao diện; `java.upLoginData({"账号": 账号, "密码": 密码})`). Gọi không tham số (`java.upLoginData()`, `⚡📂米读小说`) → `[UNKNOWN]`
     U38, khuyến nghị: lưu giá trị đang có trên form làm thông tin đăng nhập. Luôn được gọi trong `try`.
   - `java.reLoginView()` (1 lần gọi thật, `🏷七猫小说`: đổi trang menu rồi gọi): đánh giá lại `loginUi` và dựng lại form.
   - **Xung đột với §6.10 phần 1**: nhiều nguồn dò biến thể ứng dụng bằng `typeof java.reLoginView == 'function'` (nếu có → coi là bản sửa
     đổi và đi nhánh khác). Khuyến nghị: **chỉ định nghĩa** `java.reLoginView` và `java.upLoginData` **trong ngữ cảnh JS của form đăng nhập**
     (bước 2–3); các ngữ cảnh rule khác không có hai hàm này, nên phép dò ở rule vẫn đi nhánh "Android chính thức" `[đề xuất]`.
6. "Đăng xuất" (mục menu của app): `removeLoginInfo` + `removeLoginHeader` + xoá cookie của tên miền `bookSourceUrl` `[đề xuất]`.
7. `source.login()`: tài liệu liệt kê `login()` trong nhóm phương thức đăng nhập của `source` `[tài liệu ruleHelp.md]` và có ví dụ gọi đồng bộ
   `source.login()` `[tài liệu rssRuleHelp.md]`; corpus 0 lần. Đặc tả `[đề xuất]`: đăng nhập **không giao diện** bằng thông tin đã lưu — tạo ngữ cảnh
   như bước 3, chạy `loginUrl`, gọi `login()`, áp luật thành công/thất bại của bước 3 nhưng không đụng form; `loginUrl` là URL → không làm gì, trả
   `undefined`. Chống đệ quy: gọi trong chính `login()` → bỏ qua.

### §10.5 Thông tin đăng nhập (`LoginInfo`)

| API | Hành vi | Nhãn |
|---|---|---|
| `source.getLoginInfo()` | chuỗi JSON của map thông tin; chưa có → `null` `[UNKNOWN]` U39 (khuyến nghị `null`; tác giả quen đề phòng giá trị rỗng kiểu `JSON.parse(source.getLoginHeader()\|\|'{}')`) | `[tài liệu jsHelp.md]` |
| `source.getLoginInfoMap()` | map (đọc `get(k)` và `[k]`, §6.3 phần 1); chưa có → map rỗng (mẫu `info.get?info.get('user_name'):info['user_name']`) | `[tài liệu jsHelp.md]` |
| `source.putLoginInfo(jsonString)` | thay toàn bộ thông tin bằng object trong chuỗi (17 nguồn, `source.putLoginInfo(JSON.stringify({email, password}))`) | `[quan sát]`; chữ ký `[UNKNOWN]` |
| `source.putLoginInfoMap(jsonString)` | 2 nguồn (`猫眼看书`: `source.putLoginInfoMap(JSON.stringify({…}))`); khuyến nghị = `putLoginInfo` | `[UNKNOWN]` U40 |
| `source.removeLoginInfo()` | xoá | `[tài liệu jsHelp.md]` |

- Lưu trữ `[đề xuất]`: **Keychain** (`kSecClassGenericPassword`, service riêng cho thông tin đăng nhập nguồn Legado, account = `bookSourceUrl`
  đã trim), `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (đọc được khi app chạy nền sau lần mở khoá đầu, không đồng bộ iCloud).
- Không đưa vào: xuất nguồn (§12.1), Backup của FreeBook, log, bộ nghiệm thu (bộ nghiệm thu chạy ở trạng thái **chưa đăng nhập**). Xoá
  nguồn → xoá mục Keychain.

### §10.6 Header đăng nhập

| API | Hành vi | Nhãn |
|---|---|---|
| `source.putLoginHeader(header)` | lưu chuỗi header đăng nhập; 39 lần/35 nguồn; tham số là `JSON.stringify({...})` hoặc biến/chuỗi tự ghép | `[tài liệu jsHelp.md, ruleHelp.md]` |
| `source.getLoginHeader()` | chuỗi đã lưu, chưa có → `null` | `[tài liệu]` |
| `source.getLoginHeaderMap()` | map header đã parse (`.get(k)`) | `[tài liệu]` |
| `source.removeLoginHeader()` | xoá | `[tài liệu]` |
| `source.getHeaderMap(hasLoginHeader)` | map header nguồn; tham số `true` → gộp thêm header đăng nhập | `[tài liệu ruleHelp.md]` |

- **Engine tự gắn header đăng nhập vào request**: 18/36 nguồn gọi `putLoginHeader` mà **không bao giờ đọc lại** bằng
  `getLoginHeader*`/`getHeaderMap` ở bất cứ đâu (`⚡📂少年梦阅读`: `source.putLoginHeader(JSON.stringify({logintoken: …}))`) `[quan sát]`; tài
  liệu cũng có lệnh "đặt lại header đăng nhập" `getHeaderMap().putAll(source.getHeaderMap(true))` trong `loginCheckJs` `[tài liệu jsHelp.md]`.
- **Định dạng**: chuỗi JSON object → map header. Không phải JSON (`📂完本神站（登录）`: `source.putLoginHeader(cookieString)`): `[UNKNOWN]` U41.
  Khuyến nghị: dạng `k=v; k2=v2` → header `Cookie`; dạng khác → bỏ qua khi gắn, nhưng `getLoginHeader()` vẫn trả nguyên văn.
- **Thứ tự gộp** `[đề xuất]`: mặc định < header nguồn < **header đăng nhập** < `headers` của option URL < `java.headerMap` (option `js`).
- **Phạm vi gắn** `[UNKNOWN]` U42: mọi request của nguồn, hay chỉ request luồng chính. Khuyến nghị: gắn cho request luồng chính **và**
  `java.ajax`/`connect`/`get`/`post`/`head`, **chỉ khi** tên miền gốc (eTLD+1) của URL đích trùng với `bookSourceUrl` hoặc với URL trang
  đang phân tích — tránh gửi token sang CDN/bên thứ ba. Ghi log mỗi lần bỏ không gắn vì khác tên miền để bộ nghiệm thu đo.
- Lưu bền trong Keychain như §10.5 (token là bí mật).

### §10.7 `loginCheckJs`

- **Tài liệu**: dùng để kiểm kết quả đăng nhập `[tài liệu ruleHelp.md]`; các hàm `java.initUrl()`, `java.getHeaderMap().putAll(…)`,
  `java.getStrResponse(jsStr?, sourceRegex?)`, `java.getResponse()` chỉ có hiệu lực trong `loginCheckJs` `[tài liệu jsHelp.md]`. Tài liệu
  **không** nói khi nào nó chạy (đính chính nhãn ở §15.3 mục 3).
- **Quan sát** (52 nguồn): `result` là **đối tượng phản hồi** của request vừa xong: `result.body()` 27 nguồn, `result.url()` 18,
  `result.code()` 8, `result.headers` 1; 39 nguồn kết thúc bằng `result` (trả lại phản hồi); việc làm phổ biến: vượt Cloudflare (14:
  `Just a moment`, `cf_chl`) bằng `java.startBrowserAwait(url, "验证")` rồi `java.connect(url)`; tải lại khi 503; báo cần đăng nhập
  (`露西弗同人站`); `cookie.removeCookie` (22) `[quan sát]`. Nó chạy **sau mỗi request** của luồng chính (dùng `key` ở 9 nguồn → có lúc
  đang tìm kiếm; dùng `java.ruleUrl` để tải lại đúng request).
- **Đặc tả** `[đề xuất]`:
  1. Chạy sau mỗi request **luồng chính** (tìm, khám phá, thông tin, mục lục, nội dung, gồm từng trang `next*Url`), kể cả request WebView,
     **trước** khi phân tích thân. Không chạy cho `java.ajax`/`connect`… trong JS (tránh đệ quy: chính `loginCheckJs` gọi `java.connect`),
     không chạy cho ảnh/media. `[UNKNOWN]` U43.
  2. Biến: `result` (phản hồi: `body()`, `code()`, `message()`, `headers()`, `url()` = URL cuối, `raw()`, `toString()` = thân — cùng đối
     tượng `java.connect` trả, §6.4.1 phần 1), `java`, `source`, `cookie`, `cache`, `baseUrl` (= URL request), `key`/`page` khi đang tìm,
     `book`/`chapter` khi có. Có thêm `java.ruleUrl`, `java.initUrl()`, `java.getStrResponse()`, `java.getResponse()`, `java.getHeaderMap()`
     (dưới).
  3. Giá trị trả: đối tượng phản hồi → **thay** phản hồi gốc; chuỗi → coi là thân mới (URL giữ nguyên); `undefined`/`null` → giữ phản hồi
     gốc. Lỗi JS → giữ phản hồi gốc + log.
  4. Chống lặp: mỗi request chạy `loginCheckJs` **một lần**; request phát sinh bên trong nó không kích hoạt lại. Thời gian tối đa 120 giây
     (có thể chờ người dùng xác minh).
- **Hàm riêng của ngữ cảnh này**:

  | Hàm | Hành vi | Nhãn |
  |---|---|---|
  | `java.ruleUrl` (thuộc tính) | chuỗi URL của request **như rule viết ra** (có thể tương đối, có thể kèm `,{option}`) — mẫu `u.startsWith("http") ? u : source.key + u`, `java.connect(url + ',{"webView": true}')` | `[quan sát]` 7 nguồn |
  | `java.initUrl()` | dựng lại request từ rule URL (đánh giá lại header nguồn + header đăng nhập + cookie hiện tại) | `[tài liệu jsHelp.md]` |
  | `java.getStrResponse(jsStr?, sourceRegex?)` | gửi lại request đã dựng, trả đối tượng phản hồi; tham số khác `null` → nạp bằng WebView, chạy `jsStr` lấy thân / dùng `sourceRegex` như §9.4 | chữ ký `[tài liệu]`; nghĩa tham số `[UNKNOWN]` U44 |
  | `java.getResponse()` | như `getStrResponse()` không tham số | `[tài liệu]`, 0 lần |
  | `java.getHeaderMap()` | map header của request đang dựng, sửa được (`putAll`) trước `getStrResponse` | `[tài liệu jsHelp.md]` |

- `Packages.io.legado.app.help.http.StrResponse(url, body)` (10 nguồn, ví dụ `📚聚合书库` dựng phản hồi mới sau khi tự giải mã) là lớp nội bộ
  của ứng dụng gốc. §6.9 phần 1 nói không giả lập lớp nội bộ; ngoại lệ đề xuất **riêng hàm dựng này**: trả đối tượng phản hồi với
  `url()` = `url`, `body()` = `body`, `code()` = 200 — rẻ và 10 nguồn cần `[đề xuất]`.

### §10.8 Trình duyệt hiện cho người dùng và nhập mã xác minh

| Hàm | Lần / nguồn | Hành vi | Nhãn |
|---|---|---|---|
| `java.startBrowser(url, title)` | 113 / 54 | mở trình duyệt trong app tại `url`, tiêu đề `title`; **không chờ**: JS chạy tiếp ngay (mẫu gọi rồi `java.toast(...)` liền sau) | chữ ký và mục đích (xem link, tự xác minh trang chống thu thập) `[tài liệu jsHelp.md]`; không chờ `[quan sát]` |
| `java.startBrowserAwait(url, title[, refetchAfterSuccess = true[, html]])` | 138 / 45 | mở trình duyệt, **chặn luồng JS** tới khi người dùng đóng/xác nhận, trả đối tượng phản hồi | chữ ký 3 tham số `[tài liệu jsHelp.md]`; tham số 4 `[quan sát]` |
| `java.startBrowserDp(url, title)` | 8 / 7 | chỉ gặp trong nhánh "轻阅读" (sau `java.qread()`, §6.10 phần 1) → không bao giờ tới; khuyến nghị bí danh của `startBrowser` | `[quan sát]` |
| `java.getVerificationCode(imageUrl)` | 13 / 10 | hiện ảnh mã xác minh + ô nhập, chặn tới khi người dùng xác nhận, trả chuỗi đã nhập | mục đích `[tài liệu jsHelp.md]` |

- **`startBrowserAwait`** `[quan sát + đề xuất]`:
  - `url` có thể là `data:text/html;base64,…`: nguồn tự dựng một trang HTML làm form cài đặt (`🏷晋江文学…`: trang "搜索设置", sau đó đọc
    `body()` để biết mục người dùng đã chọn) → trình duyệt nạp HTML đó.
  - Tham số 3 `false` (nhiều mẫu Cloudflare và form HTML): phản hồi trả về là **trạng thái trang lúc đóng**: `body()` =
    `document.documentElement.outerHTML` hiện tại (晋江 đọc lựa chọn từ DOM), `url()` = URL hiện tại, `code()` = 200.
  - Tham số 3 `true` hoặc vắng: sau khi đóng, đồng bộ cookie rồi **tải lại `url` bằng HTTP** và trả phản hồi đó (tên tham số gợi ý "tải lại
    sau khi thành công") `[UNKNOWN]` U45.
  - Tham số 4 (`微信读书`: HTML tự dựng): nạp chuỗi HTML đó với URL nền = `url` `[UNKNOWN]` U45.
  - Người dùng đóng bằng nút huỷ: vẫn trả trạng thái như trên (nguồn tự kiểm `body()` có còn trang chặn không) `[đề xuất]`.
  - Thanh trên có nút "Xong" (✓): nhiều nguồn nhắc người dùng "xác minh xong thì bấm dấu ✓ góc trên bên phải" (`请完成人机验证后点右上角对勾`)
    `[quan sát]`.
- Mọi trình duyệt hiện cho người dùng: dùng chung kho cookie với request HTTP của nguồn (đồng bộ hai chiều khi mở và khi đóng, §4.2 phần 1),
  UA = UA WebView Android (§3.10 phần 1) hoặc theo cài đặt chế độ máy tính của FreeBook; áp chặn quảng cáo theo `WebContentPolicy` như webview
  tiện ích JS hiện có `[đề xuất]`.
- **Luồng chạy**: JS chạy ngoài main thread và chờ; UI dựng trên main thread (quy ước repo cấm chờ đồng bộ trên main thread, §6.1 phần 1).
- **Ngữ cảnh không có người dùng** (tải truyện nền, tải trước chương, kiểm tra nguồn hàng loạt, bộ nghiệm thu): `startBrowser` → không mở,
  log; `startBrowserAwait` → không mở, trả phản hồi rỗng (`code()` = 0), log "cần xác minh thủ công"; `getVerificationCode` → trả `""`.
  Tầng trên đánh dấu chương/nguồn là "cần xác minh" thay vì "lỗi" `[đề xuất]`.
- **`getVerificationCode(imageUrl)`** `[quan sát + đề xuất]`: `imageUrl` là URL `http(s)` (thường thêm `?`+`Math.random()`) hoặc
  `data:image/svg+xml;base64,…`. Ảnh phải tải bằng **client của nguồn** (cùng kho cookie) vì mã xác minh gắn với phiên: `📂神文小说` lấy mã
  rồi gửi `java.ajax(… "method":"POST" …)` cùng phiên. Người dùng bấm huỷ → `""`.
- Giới hạn: tối đa một trình duyệt/hộp mã xác minh hiện cùng lúc cho toàn app; yêu cầu thứ hai xếp hàng `[đề xuất]`.

### §10.9 Ví dụ biên

| Tình huống | Kết quả |
|---|---|
| `loginUi` rỗng, `loginUrl = https://m.x.com/login` | mở trình duyệt, đóng → cookie của `m.x.com` vào kho |
| `loginUi = [{"name":"账号","type":"text"},{"name":"密码","type":"password"}]`, `loginUrl` có `function login(){ … }` | form 2 ô; "Đăng nhập" → `login()` đọc `source.getLoginInfoMap().get("账号")`; thành công → lưu Keychain |
| nút `{"name":"获取验证码","type":"button","action":"getCode()"}` | chạy `loginUrl` rồi `getCode()` với `result.get("账号")` = ô đang nhập |
| `loginUrl = {"url": "null"}` | không có đăng nhập |
| `putLoginHeader('{"token":"abc"}')`, request tới `https://api.x.com/…` (nguồn `https://www.x.com`) | thêm header `token: abc` |
| cùng trên, `java.ajax("https://cdn.other.net/a.js")` | không gắn `token` (khác tên miền gốc), log |
| `loginCheckJs = if(result.code()==403){java.initUrl(); result=java.getStrResponse()} result` | 403 → gửi lại request với header mới, dùng phản hồi lần hai |

---

## §11. Khám phá động

> Tài liệu chỉ có khuôn mục khám phá `{title, url, style}` với các khoá `layout_*` `[tài liệu ruleHelp.md]`. Các khoá `type`, `action`,
> `chars`, `default`, `viewName`, biến `infoMap`, hàm `refreshExplore` **không** có trong tài liệu được phép (form `loginUi` có `type`/`action`/
> `style` nhưng đó là đăng nhập). Toàn bộ §11 là `[quan sát]` hoặc `[đề xuất]`.

### §11.1 Số liệu

- `exploreUrl` dạng **mảng JSON** (parse chuẩn được): 38 578 mục ở 1054 nguồn, **không mục nào có `type`**; khoá: `title` và `url` ở mọi
  mục, `style` 38 297, `method`/`body` 16, `webView` 14 `[quan sát]`.
- Mục có `type` **chỉ** xuất hiện trong `exploreUrl` dạng **JS** (mảng được JS sinh ra) `[quan sát]`:

  | `type` | Lần / nguồn | Ví dụ |
  |---|---|---|
  | `select` | 52 / 21 | `{"title":"片库","type":"select","chars":["电影片库","剧集片库",…],"default":mainCat,"action":"java.refreshExplore()"}` (`🎬电源先生`) |
  | `button` | 23 / 10 | `{title:'🔍 当前接口搜', type:'button', action:"var k = infoMap['全局关键字']; … java.searchBook(k, source);"}` |
  | `text` | 6 / 6 | `{title:'全局关键字', type:'text', default:''}` |
  | `toggle` | 3 / 1 | – |
  | `title` | 1 / 1 | – |

  Các giá trị `type` khác bắt được (`cate`, `list`, số, `maoyankanshu`) là khoá dữ liệu riêng của nguồn hoặc `type` của option URL, không phải
  kiểu mục.
- `infoMap` xuất hiện ở 30 nguồn: trong `exploreUrl` 24, `jsLib` 8, `loginUrl` 1. `java.refreshExplore()` 74 lần / 32 nguồn (trong
  `exploreUrl` 22 chuỗi, `jsLib` 12, `loginUrl` 5, `loginCheckJs` 3); `source.refreshExplore()` 7 / 6 `[quan sát]`.

### §11.2 Mục và vai trò

| Mục | Hiển thị | Sinh request? |
|---|---|---|
| không `type`, `url` không rỗng | ô bấm mở danh sách sách (§5.2.3 phần 1) | có, khi bấm |
| không `type`, `url` rỗng | tiêu đề nhóm (§5.2.2 phần 1) | không |
| `select` | ô chọn: nhãn `title` (hoặc `viewName`), giá trị hiện tại; danh sách lựa chọn = `chars` | không trực tiếp; chạy `action` sau khi đổi |
| `toggle` | nút hiện phần tử hiện tại của `chars`, bấm → phần tử kế (vòng) | như trên |
| `text` | ô nhập, nhãn `title`, giá trị khởi đầu `default` | không; giá trị dùng khi nút khác chạy |
| `button` | nút, nhãn `title` | không trực tiếp; chạy `action` |
| `title` | nhãn tĩnh | không |

`[đề xuất]`: mục có `type` lạ → hiển thị như mục không `type` (nếu có `url`) hoặc bỏ qua. Khi nguồn không có mục `type` nào, Khám phá chạy y như
đợt 1.

### §11.3 `infoMap` và giá trị người dùng chọn

- `infoMap` là map **`title` → chuỗi giá trị hiện tại** của các mục `select`/`toggle`/`text` `[quan sát]`. Đọc: `infoMap[k]`,
  `infoMap.get(k)` (`infoMap['搜索关键词'] || (infoMap.get && infoMap.get('搜索关键词'))`). Ghi: `infoMap[k] = v`, `infoMap.put(k, v)`, và
  `infoMap.save()` (1 lần) `[quan sát]`.
- Mẫu chuẩn: JS của `exploreUrl` đọc lựa chọn cũ rồi sinh danh sách tương ứng —
  `var mainCat = infoMap["片库"] || "电影片库";` → mục `select` với `"default": mainCat` → các mục URL của đúng "片库" đó. Khi người dùng đổi
  `select`, `action` là `java.refreshExplore()` → chạy lại `exploreUrl` → danh sách mới `[quan sát: 🎬电源先生, 🎬七猫短剧, 🔞夜读集]`.
- **Giá trị đi vào URL bằng cách nào**: chỉ qua JS sinh lại danh sách. Không có placeholder `{{infoMap…}}` trong chuỗi URL nào (0 lần)
  `[quan sát]`. Engine **không** tự chèn giá trị chọn vào URL.
- Đặc tả `[đề xuất]`:
  1. Kho `infoMap` **theo nguồn**, lưu bền (JSON nhỏ trong kho trạng thái Legado), sống qua `refreshExplore` và qua lần mở app sau.
     `[UNKNOWN]` U46: gốc có lưu qua lần mở app không; mẫu `infoMap.save()` gợi ý có thao tác lưu tường minh. Khuyến nghị lưu bền ngay khi đổi
     (vô hại với nguồn không gọi `save`).
  2. Lần đầu (kho rỗng): `infoMap[k]` là `undefined` → nguồn tự rơi về giá trị mặc định (`|| "电影片库"`). Sau khi dựng danh sách, engine ghi
     `default` của các mục `select`/`toggle`/`text` vào `infoMap` **nếu khoá đó chưa có**, để `action` đọc được.
  3. `infoMap` có trong ngữ cảnh JS của `exploreUrl`, của mọi `action` khám phá, và của `jsLib` khi nạp trong hai ngữ cảnh đó. Ngữ cảnh khác
     (rule tìm kiếm, `loginUrl`): `infoMap` là map rỗng chỉ đọc `[đề xuất]` (1 nguồn dùng trong `loginUrl` đều bọc `try`).
  4. Mục `text`: ghi `infoMap[title]` mỗi khi người dùng sửa (debounce 300 ms) — không cần bấm "xong" — vì nút chạy sau đọc thẳng giá trị.

### §11.4 `action`

- `action` là **mã JS** (chuỗi), không phải URL `[quan sát]`. Mẫu: `java.refreshExplore()`; `var k=infoMap['关键字']; if(!k){ java.toast('请输入关键字'); }
  else { java.searchBook(k, source); }`; hàm tự định nghĩa trong `jsLib`; đoạn đổi `source.setVariable(…)` rồi `java.refreshExplore()`.
- Ngữ cảnh `[đề xuất]`: ngữ cảnh JS mới, `java`, `source`, `cookie`, `cache`, `infoMap`, nạp `jsLib`; **không** chạy lại `exploreUrl` trước
  (khác §10.4 với `loginUrl`: hàm của khám phá nằm trong `jsLib`, không trong `exploreUrl`). `[UNKNOWN]` U47: gốc có chạy `exploreUrl` làm
  "thư viện" cho `action` không; khuyến nghị: nếu `action` ném `ReferenceError` (hàm chưa định nghĩa) thì chạy `exploreUrl` trong cùng ngữ
  cảnh rồi thử `action` lần hai.
- Chạy tuần tự theo nguồn; tối đa 15 giây; lỗi → toast + log.

### §11.5 `java.refreshExplore()` / `source.refreshExplore()`

- Nghĩa `[quan sát]`: tính lại danh sách khám phá của **nguồn hiện tại** (chạy lại `exploreUrl`) và vẽ lại; được gọi sau khi đổi lựa chọn
  (`action`), sau khi đổi cài đặt trong form đăng nhập (`loginUrl` 5 chuỗi) hoặc khi `loginCheckJs` phát hiện tên miền đổi.
- Đặc tả `[đề xuất]`: xoá cache danh sách khám phá của nguồn, gom các lệnh gọi trong 300 ms thành một lần, chạy lại ở nền rồi cập nhật UI
  nếu màn khám phá của nguồn đang mở; nguồn có `exploreUrl` tĩnh → chỉ vẽ lại. Hai tên là một hàm. Trả `undefined`.
- Cache danh sách khám phá dạng JS: theo nguồn, sống tới khi `refreshExplore`, sửa nguồn, hoặc người dùng kéo làm mới `[đề xuất]`.

### §11.6 `java.searchBook(key[, scope])`

7 nguồn gọi từ nút khám phá `[quan sát]`; tài liệu chỉ ghi `java.searchBook(bookName)` cho ngữ cảnh nguồn đăng ký `[tài liệu jsHelp.md]`.
Tham số 2 gặp: đối tượng `source`, hoặc chuỗi `` `${source.bookSourceName}::${source.getKey()}` ``. Đặc tả `[đề xuất]`: mở màn Tìm kiếm của
FreeBook với từ khoá `key`; có tham số 2 → giới hạn phạm vi vào nguồn đó (so theo `bookSourceUrl`, phần sau `::` của chuỗi); không có → mọi
nguồn đang bật. Không chặn JS.

### §11.7 Bố cục `style`

- Khoá `layout_*` (đếm mục mảng JSON) `[quan sát]`: `layout_flexGrow` 36 773, `layout_flexBasisPercent` 33 065, `layout_wrapBefore` 337,
  `layout_flexShrink` 308, `layout_alignSelf` 308, viết sai `layout_flexBasisPersent` 14. Khuôn tài liệu có cả năm khoá với giá trị
  `0`, `1`, `"auto"`, `-1`, `false` `[tài liệu ruleHelp.md]`; spec hiểu `layout_flexBasisPercent: -1` của khuôn mẫu là "không đặt"
  `[đề xuất]`.
- Thuật toán bố cục `[đề xuất]` (dùng chung cho khám phá và form `loginUi`), cài bằng SwiftUI `Layout` tự viết:
  1. Xếp các mục theo hàng, từ trái sang phải, chiều rộng khả dụng `W`.
  2. Chiều rộng cơ sở: `0 < p ≤ 1` (`layout_flexBasisPercent`, chấp nhận tên viết sai) → `p·W`; còn lại → chiều rộng nội tại của nhãn + đệm.
  3. `layout_wrapBefore: true` → xuống hàng trước mục. Mục không vừa phần còn lại của hàng → xuống hàng.
  4. Phần dư của hàng chia cho các mục theo `layout_flexGrow` (> 0); `flexShrink` và `alignSelf` bỏ qua.
  5. Mục tiêu đề nhóm (`url` rỗng, §5.2.2 phần 1) luôn chiếm trọn một hàng.
- Mặc định khi không có `style`: ô cỡ nhãn, xếp liên tiếp (giống chip).

### §11.8 Ví dụ biên

| `exploreUrl` JS trả | `infoMap` | Hiển thị / hành vi |
|---|---|---|
| `[{title:"频道",type:"select",chars:["短剧","电影"],default:"短剧",action:"java.refreshExplore()"},{title:"全部",url:"/vodtype/4-{{page}}.html"}]` | `{}` | ô chọn "频道 = 短剧"; ghi `infoMap["频道"]="短剧"`; ô "全部" mở danh sách |
| người dùng chọn "电影" | `{"频道":"电影"}` | chạy `java.refreshExplore()` → JS đọc `infoMap["频道"]` → sinh mục của "电影" |
| `{title:'关键字',type:'text'}` + nút `java.searchBook(infoMap['关键字'], source)` | `{"关键字":"斗罗"}` | mở Tìm kiếm "斗罗" trong nguồn này |
| mục `{title:"——",url:"",style:{layout_flexBasisPercent:1}}` | – | tiêu đề nhóm một hàng |

---

## §12. Quản lý nguồn

### §12.1 Định dạng xuất và chia sẻ

- Tài liệu: màn quản lý cho phép thêm nguồn, nhập từ tệp trên máy, từ địa chỉ mạng hoặc quét QR, và gửi các nguồn đang chọn cho người khác; thao tác
  hàng loạt gồm bật, tắt, gắn hoặc gỡ nhóm, bật/tắt mục khám phá, dời lên đầu hoặc xuống cuối, xuất tệp, kiểm tra `[tài liệu SourceMBookHelp.md]`. Tệp nguồn có đuôi `.txt` hoặc
  `.json`; bản sao lưu của ứng dụng gốc có tệp `myBookSource.json` `[tài liệu appHelp.md]`.
- Định dạng xuất `[đề xuất, khớp §1.1 phần 1]`: **mảng JSON** các object nguồn, UTF-8 không BOM, mỗi object là **JSON gốc đã lưu** (giữ khoá lạ)
  đè lên bằng các trường người dùng đã sửa trong FreeBook (`enabled`, `enabledExplore`, `bookSourceGroup`, `customOrder`, nội dung rule nếu có
  trình sửa). Quan sát: các bộ tải về có khoá **xếp theo thứ tự chữ cái** và nguồn xếp theo `customOrder` tăng dần `[quan sát]`; FreeBook làm
  giống vậy (thụt 2 dấu cách) để so khác biệt dễ.
- **Không** xuất: thông tin/header đăng nhập (§10.5–§10.6), cookie, `cache`, `infoMap`, kho biến phiên. Biến nguồn (`source.setVariable`):
  `[UNKNOWN]` U48 (gốc có xuất không); khuyến nghị **không** xuất mặc định (có thể chứa token người dùng tự dán), có công tắc "kèm biến nguồn".
- Chia sẻ: tệp `.json` qua share sheet; mã QR chỉ cho một nguồn nhỏ (< 2 KB) hoặc cho một URL tải `[đề xuất]`.

### §12.2 Nhập nhanh bằng scheme URL

- Tài liệu được phép **không** mô tả scheme nào `[UNKNOWN]` U49. Corpus có ba dạng (do nguồn tự mở bằng `java.openUrl` hoặc đặt trong HTML)
  `[quan sát]`:

  | Dạng | Lần / nguồn | Ngữ cảnh |
  |---|---|---|
  | `legado://import/importonline?src=<URL tệp nguồn>` | 27 / 5 | nút "cập nhật nguồn" mở link tới tệp `.json` trên CDN |
  | `legado://import/addToBookshelf?src=<URL trang sách>` | 12 / 10 | nút "thêm vào kệ" trong HTML giới thiệu/nội dung |
  | `yuedu://booksource/importonline?src=<URL đã encode>` | 6 / 6 | link trong trang HTML tự dựng |

- Khuyến nghị `[đề xuất]`:
  1. FreeBook đăng ký scheme riêng (ví dụ `freebook://legado/import?src=`) cho chia sẻ ra ngoài.
  2. Nhận thêm ba dạng trên làm **bí danh đầu vào**: khi người dùng mở link (từ trình duyệt, ứng dụng khác) hoặc khi nguồn gọi `java.openUrl` với
     URL có scheme này → xử lý nội bộ, **không** chuyển cho iOS.
  3. `importonline`: tải `src` (giới hạn 20 MB, chỉ `http(s)`), parse như §1.1 phần 1, **hiện màn xác nhận** (số nguồn mới/cập nhật/giống hệt,
     nguồn gửi yêu cầu nếu có) — không bao giờ nhập im lặng. `addToBookshelf`: tìm nguồn có `bookUrlPattern` khớp `src` (§5.9 phần 1), mở trang
     sách để người dùng tự bấm thêm.
  4. Scheme lạ khác trong `java.openUrl` (`mqqapi://…`) → hỏi người dùng trước khi mở ứng dụng ngoài.

### §12.3 Chế độ gỡ lỗi nguồn

- Tài liệu chia ô nhập gỡ lỗi theo dạng chuỗi `[tài liệu debugHelp.md]`:

  | Chuỗi nhập | Bước bắt đầu | Ví dụ trong tài liệu |
  |---|---|---|
  | chữ thường | tìm kiếm với từ khoá đó | một từ khoá |
  | `tên::url` | mở mục khám phá | `月票榜::https://…?page={{page}}` (dạng §5.2.1 phần 1) |
  | URL tuyệt đối | trang thông tin sách | `https://m.qidian.com/book/1015609210` |
  | `++` + URL | trang mục lục | `++https://www.zhaishuyuan.com/read/30394` |
  | `--` + URL | trang nội dung | `--https://www.zhaishuyuan.com/chapter/30394/20940996` |

  Thứ tự nhận dạng `[đề xuất]`: `++` → `--` → có `::` (và phần sau là URL/JS) → bắt đầu `http(s)://` → còn lại là từ khoá. Ô trống → dùng
  `checkKeyWord` của nguồn (§5.10 phần 1), không có thì "我的".
- **Chạy tiếp** `[đề xuất]`: từ bước bắt đầu, đi tiếp chuỗi tìm kiếm/khám phá → mục đầu tiên → thông tin → mục lục → chương đầu tiên có URL
  (bỏ mục `isVolume`). Dừng ở bước đầu tiên ra rỗng hoặc lỗi.
- **Hiển thị mỗi bước** `[đề xuất]`: thời điểm và thời gian (ms); request: phương thức, URL cuối (sau chuyển hướng), mã HTTP, kích thước thân,
  bảng mã đã chọn, có dùng WebView không; header gửi đi **đã che** giá trị `Cookie`, `Authorization`, header đăng nhập; kết quả từng trường rule
  (tên trường → giá trị rút gọn 200 ký tự, hoặc "(rỗng)"); số mục danh sách; các URL `next*`; lỗi kèm tên trường và chuỗi rule; dòng `java.log`
  của nguồn theo thứ tự thời gian. Nút "xem thân phản hồi" mở toàn văn (chỉ trong phiên, không ghi log file).
- FreeBook đã có bộ chạy nghiệm thu qua Debug server (commit `f32e0614`); chế độ gỡ lỗi trong app dùng lại cùng lõi, chỉ khác lối vào và màn
  hiển thị.

### §12.4 Kiểm tra nguồn hàng loạt

- Tài liệu `[tài liệu SourceMBookHelp.md]`: kiểm tra được nhiều nguồn một lúc, kết quả chỉ để tham khảo; "thành công" khi mọi hạng mục đã chọn
  đều qua; phân biệt được các nguyên nhân: tìm kiếm rỗng, khám phá rỗng, mục lục của kết quả tìm kiếm/khám phá rỗng, nội dung rỗng, quá thời
  gian, lỗi JS; nguyên nhân khác xếp vào "trang web hỏng"; từ khoá ưu tiên `checkKeyWord` của nguồn, không có thì dùng từ khoá người dùng nhập;
  kiểm xong có lọc ra các nguồn hỏng. `appHelp.md` nhắc lại: báo hỏng không có nghĩa là nguồn chắc chắn không dùng được `[tài liệu appHelp.md]`.
- Đặc tả `[đề xuất]`:
  - Hạng mục chọn được: tìm kiếm, khám phá (mục URL đầu tiên), thông tin, mục lục, nội dung (chương đầu).
  - Mã kết quả mỗi nguồn: `ok`, `searchEmpty`, `exploreEmpty`, `tocEmpty`, `contentEmpty`, `timeout`, `jsError`, `siteError` (HTTP ≥ 400,
    mạng, parse), `needsVerification` (gặp `startBrowserAwait`/`getVerificationCode`, §10.8), `notRunnable` (thiếu rule tối thiểu §1.9 phần 1,
    loại không hỗ trợ).
  - Thời gian tối đa **180 giây** mỗi nguồn (corpus có 24 nguồn `respondTime = 180000` đúng mức trần này — có vẻ là giá trị ghi khi quá thời
    gian `[UNKNOWN]` U50); chạy song song tối đa 4 nguồn, trong một nguồn tuần tự, vẫn tôn trọng `concurrentRate`.
  - Không mở UI nào (ngữ cảnh không người dùng, §10.8). Không đăng nhập.
  - Lưu kết quả lần kiểm gần nhất theo nguồn (mã, lý do, thời điểm, thời gian) và cập nhật `respondTime` = tổng ms của lượt kiểm thành công
    hoặc 180000 khi quá thời gian. **Không** sửa `bookSourceGroup` (ứng dụng gốc gắn nhóm hay không: `[UNKNOWN]`; corpus có nhóm kiểu
    `🌹已检26.10.15` "đã kiểm ngày…" do người chia sẻ tự đặt). Bộ lọc "nguồn lỗi" đọc từ kết quả đã lưu.

### §12.5 Khoá phụ và trình sửa biến

| Khoá | Quan sát | Dùng trong FreeBook |
|---|---|---|
| `customOrder` | mỗi bộ đã xếp tăng dần theo khoá này; 1315: 0…851 không trùng; 1316: −4312…3186, 1342 giá trị khác nhau / 1378, 4 số âm `[quan sát]` | thứ tự thủ công. "Đưa lên đầu" = min − 1, "xuống cuối" = max + 1 `[đề xuất]`; nhập vào thư viện đã có → giữ thứ tự tương đối, dời ra sau max hiện tại `[đề xuất]` |
| `weight` | 0: 3030 nguồn, 1: 211, 2: 35, −5: 23, 100: 22, 60: 11, 58: 10; 671 nguồn khác 0 `[quan sát]` | nghĩa `[UNKNOWN]` U51 (có thể là ưu tiên khi đổi nguồn). Lưu; chỉ dùng làm tiêu chí phụ khi xếp kết quả tìm kiếm cùng độ khớp (cao trước) `[đề xuất]` |
| `respondTime` | 0: 229, 1: 227, 2: 29, 180000: 24; lớn nhất 360003; trung vị 5771 `[quan sát]` | ms của lần kiểm gần nhất (§12.4); hiện trong danh sách nguồn, cho sắp xếp "nhanh trước"; giá trị ≤ 2 coi như "chưa đo" `[đề xuất]` |
| `lastUpdateTime` | ms từ 1970; 971 nguồn là 0; có giá trị phi lý (năm 2999) `[quan sát]` | thời điểm sửa nguồn; cập nhật khi người dùng sửa; khi nhập trùng hiện "mới hơn/cũ hơn" (§1.1 phần 1); giá trị 0 hoặc > hiện tại + 1 ngày → "không rõ" `[đề xuất]` |
| `variableComment` | 32 nguồn: 21 là hướng dẫn chữ (cách nhập biến nguồn/biến sách, ý nghĩa từng số), 11 là chuỗi mã hoá kiểu base64 mà `jsLib` đọc qua `source.variableComment` (3 nguồn đọc trong mã), có 1 nguồn đặt cả đoạn `@js:` `[quan sát]` | hiện ở trình sửa biến (dưới) |

**Trình sửa biến** `[quan sát + đề xuất]`:

- **Biến nguồn**: một chuỗi (`source.getVariable()`/`setVariable`, §5.7 phần 1). Ghi chú nguồn hướng dẫn người dùng mở "sửa nguồn → menu → đặt
  biến nguồn" (`🔞兽人小说站`) `[quan sát]`. FreeBook: mục "Biến nguồn" trong menu nguồn; ô nhập nhiều dòng; phía trên hiện `variableComment` như
  chữ hướng dẫn (chọn được, cuộn được, rút gọn sau 20 dòng). `variableComment` là chuỗi liền không khoảng trắng dài > 40 ký tự → hiện gọn
  "(nguồn có dữ liệu cấu hình riêng)" thay vì đổ chuỗi mã hoá ra màn hình.
- **Biến sách**: 20 nguồn bảo người dùng "điền vào biến sách ở góc trên bên phải" (`右上角书籍变量填 0-N 刷新切换线路`, `书籍变量（当前书）`) và
  26 nguồn đọc nó bằng `book.getVariable('custom')` `[quan sát]` → trình sửa biến sách ghi vào **khoá `custom`** của kho biến sách (§5.7 phần 1).
  FreeBook: mục "Biến sách" trong menu trang sách/Reader cho sách thuộc nguồn Legado; cùng ô hướng dẫn `variableComment`. Lưu xong → làm mới
  thông tin/mục lục/chương hiện tại theo màn đang mở.
- Biến chỉ là chuỗi; không kiểm tra định dạng. Không ghi giá trị vào log.

---

## §13. Phần đuôi đợt 2

### §13.1 URL `data:`

Bằng chứng ở §3.11 phần 1 (34 nguồn loại 0 dùng `data:` làm `bookUrl`/`chapterUrl`; 28 đọc bằng `java.hexDecodeToString(result)` khi
`String(baseUrl).startsWith("data:")`). Đặc tả đợt 2 `[đề xuất trên nền quan sát đó]`:

1. Nhận dạng: chuỗi URL (sau bước JS/`{{}}` của §3.2 phần 1) bắt đầu bằng `data:` (không phân biệt hoa thường). Tách khối option `,{…}` ở cuối
   như §3.2 bước 4; phần còn lại theo cú pháp `data:[<mime>][;base64],<payload>` (mime có thể là chữ tự đặt như `vipContent`, hoặc rỗng
   `data:;base64,…`) `[quan sát]`.
2. Không gửi mạng, không chạy `loginCheckJs`. Byte = base64-decode `payload` (chấp nhận base64 URL-safe và thiếu `=`); không có `;base64` →
   percent-decode.
3. **Thân phản hồi = chuỗi hex chữ thường của các byte đó** (để `java.hexDecodeToString(result)` ra đúng chuỗi gốc) `[UNKNOWN]` U22 phần 1 vẫn mở;
   `src` = cùng chuỗi hex; `baseUrl` = **nguyên chuỗi URL `data:`** (gồm option) vì nguồn kiểm `startsWith("data:")` và có nguồn tự tách option
   từ `baseUrl` (`JSON.parse(baseUrl.replace(/^.+?,/,''))`, `⚡📂西瓜小说`) `[quan sát]`; URL cuối = `baseUrl`; mã HTTP 200.
4. Option `type` chỉ là nhãn, không tác dụng (§3.6 phần 1); option khác bỏ qua.
5. Bộ nghiệm thu đo U22 bằng cách chạy 34 nguồn với cả hai cách (hex / chuỗi UTF-8 đã giải) và đếm chương ra nội dung.

### §13.2 `sourceRegex`

Xem §9.4 (dùng chung cho video, audio và mọi loại khi request nội dung chương là WebView).

### §13.3 `preUpdateJs`, `java.refreshTocUrl()`, `java.reGetBook()`

- 18 nguồn có giá trị (12 loại 0, 6 loại 2) `[quan sát]`, bốn dạng:

  | Dạng | Số nguồn | Mẫu |
  |---|---|---|
  | chỉ `java.refreshTocUrl()` | 7 | `java.refreshTocUrl()` |
  | đổi tên miền của sách rồi làm mới | 5 | `if (!String(book.bookUrl).includes(Get('url'))) { book.bookUrl = …replace(host…); book.tocUrl = …; java.refreshTocUrl(); }` |
  | đặt lại biến | 4 | `book.variable=""; source.setVariable(39);` |
  | nạp mã từ tệp đã tải rồi `eval` | 1 | `eval(r.ruleToc.preUpdateJs\|\|'')` (§14.2) |
  | rác `{{}}` | 1 | – |

- Tài liệu: `java.reGetBook()` dò lại cuốn sách, `java.refreshTocUrl()` lấy địa chỉ mục lục mới, dành cho nguồn mà đường dẫn sách/mục lục hay
  thay đổi; hai hàm chỉ có tác dụng ở giai đoạn ngay trước khi cập nhật danh sách chương `[tài liệu jsHelp.md]`. Tên `preUpdateJs` + tài liệu → chạy ngay trước mỗi lần lấy mục lục.
- Đặc tả `[đề xuất]`:
  1. Chạy trước bước 2 của §5.4.1 phần 1 mỗi khi lấy mục lục (mở trang sách, làm mới kệ, tải truyện, đổi nguồn). Biến: `book` (**ghi được**,
     §13.5), `source`, `java`, `cookie`, `cache`, `baseUrl` = `book.bookUrl`; không có `result`. Giá trị trả bỏ qua. Lỗi → log, vẫn lấy mục lục.
  2. `java.refreshTocUrl()`: đánh giá lại `ruleBookInfo` trên `book.bookUrl` **hiện tại** (đã có thể bị sửa ở dòng trên), cập nhật `book.tocUrl`
     (và các trường thông tin không rỗng như §5.3.1 bước 4 phần 1). Chạy đồng bộ. Lỗi → giữ `tocUrl` cũ.
  3. `java.reGetBook()` (0 lần trong corpus): tìm lại theo `book.name` (+ `book.author`) **trong cùng nguồn**, chọn kết quả trùng tên và tác giả
     (so sau trim, không phân biệt phồn/giản), cập nhật `book.bookUrl` rồi làm như `refreshTocUrl()`. Không thấy → giữ nguyên.
  4. `java.refreshBookUrl()` (3 nguồn) và `java.refreshBookInfo()` (1 nguồn, chỉ trong `action` của form, nhánh ứng dụng sửa đổi): `[UNKNOWN]`
     U52; khuyến nghị cả hai = `refreshTocUrl()`.
  5. Ngoài `preUpdateJs` (và `ruleBookInfo.init`), gọi `refreshTocUrl`/`reGetBook` → log cảnh báo, không làm gì (theo tài liệu).

### §13.4 `formatJs`

- 11 nguồn có khoá, 3 có giá trị `[quan sát]`: `'第' + index + '章 ' + title.replace(/第(\d+|[零一…万]+)[章页卷回]…/g,'').trim()` (`🔞西瓜书屋`),
  `title.replace(/【\d{6}】$/,'')` (`哔哩哔哩（优+++）`), một IIFE tự đánh số lại (`🔰 玩文学`).
- Đặc tả `[đề xuất]`: sau khi có mục lục đầy đủ (§5.4.1 bước 7 phần 1), với mỗi chương **không phải** `isVolume`, chạy `formatJs` với `title`
  (tên gốc), `index`, `book`, `chapter`, `java`, `source`; kết quả chuỗi không rỗng thay tên hiển thị; lưu cả tên gốc. Chạy một ngữ cảnh cho cả
  mục lục (nhanh), có giới hạn 2 giây tổng.
- `index` **đếm từ 1** `[UNKNOWN]` U26 phần 1, bằng chứng yếu mới: mẫu `'第' + index + '章 '` sẽ ghi "第0章" cho chương đầu nếu đếm từ 0, và tác giả
  không cộng 1 `[quan sát]`. Khuyến nghị: `index` = số thứ tự 1-based trong các chương không phải `isVolume`; `chapter.index` vẫn 0-based.

### §13.5 Ghi thuộc tính `book`/`chapter`

Đếm lệnh gán và setter (lần / nguồn, theo trường rule chứa nó) `[quan sát]`:

| Lệnh | Lần / nguồn | Ở đâu |
|---|---|---|
| `book.type = …` | 104 / 24 | `chapterList` 80, `init` 10, `chapterUrl` 8, `content` 3 → §13.6 |
| `book.setReverseToc(bool)` | 27 / 9 | `ruleBookInfo.name` (bật/tắt theo từ khoá người dùng gõ, ví dụ có chữ "逆") |
| `book.bookUrl = …` | 13 / 11 | `init` 8, `preUpdateJs` 5 |
| `book.imageStyle = …` | 11 / 6 | `content` (§8.5) |
| `book.tocUrl = …` | 10 / 8 | `init` 5, `preUpdateJs` 5 |
| `book.variable = …` | 8 / 4 | `content`, `preUpdateJs` |
| `book.setUseReplaceRule(bool)` | 7 / 7 | `intro` 6, `content` 1 |
| `chapter.url = …` | 6 / 6 | `content` (ký lại URL rồi tải) |
| `book.canUpdate = …` | 5 / 5 | `intro`, `init` |
| `chapter.title = …` | 5 / 4 | `content` |
| `book.setType(n)` | 4 / 1 | §13.6 |
| `book.author = …`, `book.durChapterIndex = …` | 2 / 1, 1 / 1 | – |

Đặc tả `[đề xuất]` (phần 1 §6.6 cho ghi vào bản sao trong ngữ cảnh, không lưu; đợt 2 lưu có chọn lọc):

| Thuộc tính | Lưu bền khi ghi ở | Ghi ở chỗ khác |
|---|---|---|
| `bookUrl`, `tocUrl` | `preUpdateJs`, `ruleBookInfo.init` | chỉ có tác dụng trong lượt đang chạy |
| `variable` (cả chuỗi), `putVariable` (đã có ở phần 1) | mọi chỗ có sách | – |
| `setReverseToc(b)` | mọi chỗ | lưu cờ "đảo mục lục" theo sách; áp ở cuối bước 3 §5.4.1 phần 1 (sau `-` của rule) |
| `canUpdate` | mọi chỗ | `false` → bỏ sách khỏi lượt kiểm chương mới của kệ |
| `imageStyle` | `content` | §8.5 |
| `setUseReplaceRule(b)` | mọi chỗ | `false` → bỏ qua lọc rác của FreeBook (`JunkFilterManager`) cho sách này `[UNKNOWN]` U53 (ở ứng dụng gốc đó là bộ luật người dùng tự đặt để gỡ quảng cáo/chữ lỗi khỏi nội dung, `appHelp.md`; gần nghĩa nhất ở FreeBook là bộ lọc rác) |
| `type`, `setType(n)` | mọi chỗ | §13.6 |
| `name`, `author`, `durChapterIndex`… | không lưu | log cảnh báo |
| `chapter.url`, `chapter.title` | không lưu | dùng trong lượt đang chạy (ví dụ `chapter.url = baseUrl = …` rồi `java.ajax(baseUrl)`) |

Ghi được thực hiện trên bản sao trong ngữ cảnh JS; khi bước kết thúc thành công, engine so bản sao với bản gốc và chỉ đẩy các thuộc tính
"lưu bền" qua kho trạng thái sách Legado (`LegadoBookStateStore`), không ghi thẳng vào `@Model Book` (quy ước ghi SwiftData qua coordinator).

### §13.6 `book.type` và loại theo từng sách

- `jsHelp.md`/`ruleHelp.md` ghi `type` của sách là `0: text, 1: audio` `[tài liệu]`. Corpus cho thấy nguồn **viết** `book.type` theo hai hệ khác
  nhau tuỳ biến thể ứng dụng mà nguồn tự dò (§6.10 phần 1) `[quan sát]`:

  | Nhánh nguồn tự dò | chữ | audio | tranh | video / phim ngắn | tệp |
  |---|---|---|---|---|---|
  | "安卓" (Android chính thức) | `8` | `32` | `64` | `8` (`短剧` vẫn là chữ) | `128` ("已自动开启文件模式") |
  | "苹果"/iOS | `0` | `1` | `2` | `3` (`{audio:1, comic:2, video:3}`) | – |

  Ví dụ: `var typeMap = {audio:32, comic:64}; book.type = … : 8;` cho Android, `{audio:1, comic:2, video:3}` cho iOS (`云端聚合（优）`); `微信读书`
  gán `book.type = 32` khi gặp album audio; `🎨🔞禁漫天堂` gán `8` cho mục truyện chữ và `64` cho mục tranh trong `chapterList`; một nguồn loại 0
  gộp phim gọi `book.setType(isArt ? 0 : 4)`; `哔哩哔哩（优+++）` gán `4` cho chế độ trình phát.
- Nguồn **đọc** `book.type` (ít): `📷🔞HentaiCosplay`, `📷🔞AsianPornImage` (loại 2) kiểm `book.type==64||book.type==1088` → với nguồn tranh,
  `book.type` đọc ra phải là `64` (1088 = 64 + 1024, bit 1024 chưa rõ) `[quan sát]`.
- Vì FreeBook chọn đi nhánh "Android chính thức" (§6.10 phần 1, `java.androidId` có, `java.qread`/`deviceID` không), đặc tả `[đề xuất]`:
  - **Đọc** `book.type`: theo **bitmask** — loại 0 → `8`, loại 1 → `32`, loại 2 → `64`, loại 3 → `128`; loại 4 → `[UNKNOWN]` U54 (không nguồn video
    nào đọc; khuyến nghị `8`, giống nhánh Android coi phim ngắn là chữ, để nguồn dò kiểu "là chữ" không đi sai nhánh). Sách đã có ghi đè → giá trị
    đã ghi. Đính chính §6.6 phần 1 (§15.3 mục 4).
  - **Ghi** `book.type = v` hoặc `book.setType(v)` → ghi đè loại **của sách** (lưu bền, §13.5): `v & 64` → tranh; `v & 32` → audio (không hỗ trợ:
    sách hiện "loại nội dung chưa hỗ trợ"); `v & 128` → tệp (không hỗ trợ); `v & 8` → chữ; `v < 8` → hệ nhỏ: `0` chữ, `1` audio, `2` tranh,
    `4` video, `3` → `[UNKNOWN]` U54 (iOS dùng cho video, `bookSourceType` 3 lại là tệp) → bỏ qua + log.
  - Router `BookContentDestination` chọn reader theo: ghi đè của sách > `bookSourceType` của nguồn. Không thêm trường vào `@Model Book`; ghi
    đè nằm trong kho trạng thái sách Legado (đúng quy ước "loại suy ra lúc chạy" của repo).
  - Ghi trong `chapterList`/`content` (bước sau khi đã mở reader) → áp từ lần mở sau; không chuyển reader giữa chừng.

### §13.7 `java.importScript(pathOrUrl)`

- Tài liệu: đọc tệp JS từ mạng (qua `java.cacheFile`) hoặc tệp cục bộ theo đường dẫn tương đối/tuyệt đối; muốn nạp vào ngữ cảnh thì tự
  `eval(String(...))` `[tài liệu jsHelp.md]` → hàm **trả về mã**, không tự chạy.
- Corpus: 6 lần / 4 nguồn `[quan sát]`: `eval((eval(java.importScript(lycurl)+'')[0].exploreUrl||'')…)` (tệp JSON của chính nguồn trên mạng);
  `{{java.importScript(source.getKey()+"js/cryptojs_min.js")}}` đặt **trong khối `<js>`** — nhờ luật thay placeholder trước khi chạy JS (§2.7 phần 1)
  toàn bộ mã thư viện được chèn vào chỗ đó.
- Đặc tả `[đề xuất]`: `http(s)` → như `java.cacheFile(url)` (§14.2): tải một lần, lưu đệm theo URL, trả chuỗi; đường dẫn → đọc tệp UTF-8 trong
  thư mục tệp của nguồn (§14.2), chặn thoát thư mục. Lỗi → `""` + log.

### §13.8 `java.toURL(url[, baseUrl])`

0 lần trong corpus `[quan sát]`. Tài liệu chỉ nói trả đối tượng `JsURL` `[tài liệu jsHelp.md]`, không liệt kê thành viên → **hoãn hẳn**. Nếu
cần sau này: object kiểu `URL` của trình duyệt (`href`, `protocol`, `host`, `hostname`, `port`, `pathname`, `search`, `hash`, `origin`, ghép
`baseUrl` theo RFC 3986) `[đề xuất]`.

### §13.9 `org.jsoup.Jsoup.connect(url)`

- 9 nguồn; chuỗi gọi gặp: `.get()` 7, `.ignoreContentType(true).ignoreHttpErrors(true).execute().bodyAsBytes()` 2 `[quan sát]`
  (`org.jsoup.Jsoup.connect(url).get()` trong `<js>` rồi rule HTML chạy tiếp trên kết quả; `百度小说` lấy byte rồi giải AES).
- Đặc tả shim (cùng client HTTP của engine: kho cookie, `concurrentRate`; header = UA mặc định §3.10 phần 1, **không** gắn header nguồn —
  `[UNKNOWN]` U55) `[đề xuất]`:

  | Đối tượng | Thành viên | Nhãn |
  |---|---|---|
  | `Connection` (chuỗi được, mỗi setter trả chính nó) | `ignoreContentType(b)`, `ignoreHttpErrors(b)` | `[quan sát]` |
  |  | `header(k, v)`, `headers(map)`, `userAgent(s)`, `referrer(s)`, `cookie(k, v)`, `cookies(map)`, `data(k, v)`, `requestBody(s)`, `method(m)`, `timeout(ms)`, `followRedirects(b)`, `maxBodySize(n)` | `[đề xuất]` |
  |  | `get()` → Document (shim §6.8 phần 1); `post()` → Document; `execute()` → Response | `get`, `execute` `[quan sát]` |
  | `Response` | `bodyAsBytes()` → mảng byte, `body()` → chuỗi, `statusCode()`, `statusMessage()`, `header(k)`, `headers()`, `cookies()`, `url()`, `parse()` → Document | `bodyAsBytes` `[quan sát]` |

- `get()` khi mã ≥ 400 mà không `ignoreHttpErrors(true)` → ném lỗi JS (như jsoup) `[đề xuất]`.

### §13.10 Giả lập `javax.crypto` và họ hàng

Đếm (lần / nguồn; gồm cả cách gọi qua `JavaImporter`) `[quan sát]`: `Cipher.getInstance` 40/34, `Cipher.DECRYPT_MODE` 9/7, `Cipher.ENCRYPT_MODE`
8/4, `new IvParameterSpec` 7/7, `new SecretKeySpec` 5/5 (+ tham chiếu `SecretKeySpec` 6), `Mac.getInstance` 9/3, `MessageDigest.getInstance` 3/3,
`KeyFactory.getInstance` 7/7, `new X509EncodedKeySpec` 3/3, `new PKCS8EncodedKeySpec` 2/2, `Signature.getInstance` 4/4, `GCMParameterSpec` 1/1.

Đặc tả đợt 2 (đối xứng, băm, HMAC) `[đề xuất]`, cài trên cùng lõi CommonCrypto với `java.createSymmetricCrypto` (§6.4.3 phần 1):

| Lớp | Thành viên |
|---|---|
| `javax.crypto.Cipher` | `getInstance(transformation)` (tên không phân biệt hoa thường; `"AES"`/`"DES"` trần = `…/ECB/PKCS5Padding` theo quy ước nền tảng Java), `init(mode, key[, paramSpec])`, `doFinal(bytes)` → bytes, `doFinal()`, `update(bytes)`; hằng `ENCRYPT_MODE = 1`, `DECRYPT_MODE = 2` |
| `javax.crypto.spec.SecretKeySpec` | `new SecretKeySpec(bytes, algorithm)` |
| `javax.crypto.spec.IvParameterSpec` | `new IvParameterSpec(bytes)` |
| `javax.crypto.spec.GCMParameterSpec` | `new GCMParameterSpec(tagBits, iv)` → AES-GCM qua CryptoKit; đợt 3 (1 nguồn) |
| `javax.crypto.Mac` | `getInstance("HmacSHA256"…)`, `init(SecretKeySpec)`, `doFinal(bytes)` → bytes |
| `java.security.MessageDigest` | `getInstance("MD5"\|"SHA-1"\|"SHA-256"…)`, `update(bytes)`, `digest([bytes])` → bytes |
| `KeyFactory`, `X509EncodedKeySpec`, `PKCS8EncodedKeySpec`, `Signature`, `Cipher` RSA | đợt 3, cùng lõi RSA §14.3 |

- Mảng byte Java có dấu (−128…127); shim dùng `Uint8Array` không dấu (§6.3 phần 1). Mã corpus dùng `& 0xff` nên chạy với cả hai; mã so `b < 0`
  sẽ sai — `[UNKNOWN]` U56, bộ nghiệm thu dò chuỗi `< 0` gần biến byte.
- Tham số `bytes` nhận cả chuỗi Java giả lập (`new java.lang.String(…).getBytes(cs)`) và mảng số.

### §13.11 `callBackJs`, `customButton`, `eventListener`

- Tần suất `[quan sát]`: `callBackJs` có giá trị 6 nguồn; `customButton = true` 8; `eventListener = true` 8. Biến `event` mang tên sự kiện:
  `clickCustomButton` 4, `clickAuthor` 3, `longClickAuthor` 3, `clickBookName` 3, `longClickCustomButton`, `startRead`, `clickShareBook`,
  `longClickBookName`, `clickCopyBookUrl` (mỗi cái 1); mã trả `true` khi đã tự xử lý. Hàm UI đi kèm: `java.open("explore", url, title[, source])`
  28 lần, `java.open("login")` 4, `java.open("search")` 1.
- Tần suất thấp, toàn là thao tác UI của ứng dụng gốc → **hoãn hẳn** (không vào đợt 3). Nhập/lưu nguyên khoá; không hiện nút tuỳ biến; không gọi
  `callBackJs`. Nếu làm sau: `event` + `book` + `source` + `java`, trả `true` thì bỏ hành vi mặc định của FreeBook `[đề xuất]`.

---

## §14. Đợt 3 (phần hiếm)

### §14.1 Font chống thu thập: `java.queryTTF`, `java.queryBase64TTF`, `java.replaceFont`

- **Tài liệu** `[tài liệu ruleHelp.md]`: dùng trong rule thay thế nội dung; ý tưởng là lấy dữ liệu hình glyph của font trang (`f1`) để tìm mã ký tự
  có **cùng hình glyph** trong một font chuẩn (`f2`). Ví dụ trong tài liệu: lấy base64 của font nhúng trong CSS (`ttf;base64,…`) bằng regex trên
  `src`, `f1 = java.queryTTF(b64)`, `f2 = java.queryTTF("<URL font Source Han Sans>")`, rồi `java.replaceFont(result, f1, f2)` hoặc thêm tham số
  thứ tư `true` để lọc các glyph mà `f1` không có.
- **Corpus**: 2 nguồn, mỗi hàm 2 lần `[quan sát]`:
  - `🔞爱丽丝书屋` (`content`): `java.replaceFont(ct, java.queryBase64TTF(b[1]), java.queryTTF("https://alanskycn.gitee.io/…/Source Han Sans CN Regular.ttf"), true)`,
    bọc `try`, lỗi thì giữ `ct`.
  - `晋江[网页]` (`replaceRegex` dạng `@js:`): `f1 = java.queryTTF("http:" + urlFontTừCSS)`, `f2 = java.queryBase64TTF("AAEAAAAN…")` (font chuẩn
    nhỏ nhúng thẳng trong nguồn).
- **Chữ ký** `[tài liệu + quan sát]`: `queryTTF(x)` — `x` là URL `http(s)` **hoặc** chuỗi base64 (ví dụ tài liệu truyền base64 vào `queryTTF`);
  `queryBase64TTF(b64)`; cả hai trả "đối tượng font" (mờ với JS) hoặc `null` khi lỗi; `replaceFont(text, f1, f2[, filter = false])` → chuỗi.
  Nhận dạng tham số của `queryTTF` `[đề xuất]`: bắt đầu `http://`/`https://` → tải (qua client của nguồn, lưu đệm bền theo URL); còn lại → base64.
- **Thuật toán** `[đề xuất]`:
  1. Parse font TrueType/OpenType: bảng `cmap` (format 4 và 12), `head.unitsPerEm`, đường viền glyph (`glyf`/`loca`; font CFF → dùng CoreText
     `CTFontCreatePathForGlyph`). Cách đơn giản nhất trên iOS: nạp bằng `CGDataProvider` → `CGFont` → `CTFont`, lấy `CGPath` từng glyph.
  2. "Dấu vân tay" glyph = chuỗi lệnh path (moveTo/lineTo/quadCurveTo/curveTo/close) với toạ độ chuẩn hoá theo `unitsPerEm` và làm tròn tới
     1/1000 em; băm SHA-256. Glyph rỗng (không có lệnh) → vân tay đặc biệt "rỗng".
  3. Với `f2`: dựng bảng `vân tay → mã ký tự` (ưu tiên mã nhỏ nhất trong khối CJK khi trùng). Lưu đệm bảng này trên đĩa theo URL/băm font, vì font
     chuẩn CJK rất lớn (hàng chục nghìn glyph).
  4. Với mỗi ký tự `c` của `text`: tìm glyph của `c` trong `cmap` của `f1`; có → tra vân tay trong bảng của `f2` → thay bằng ký tự tìm được; không
     tìm được → giữ `c`. `c` không có trong `f1` → giữ `c`.
  5. Tham số `filter = true`: `[UNKNOWN]` U57. Hai cách hiểu: (a) bỏ ký tự mà glyph trong `f1` **rỗng** (ký tự mồi vô hình); (b) bỏ mọi ký tự không có
     trong `cmap` của `f1` — cách (b) xoá cả chữ thường không bị làm rối, vô lý với trang trộn chữ thường và chữ mã hoá. Khuyến nghị (a).
- Không tải được font chuẩn (URL `gitee.io` trong corpus nhiều khả năng đã chết) → `queryTTF` trả `null`; `replaceFont` với font `null` → trả
  nguyên `text` + log. Không đóng gói font CJK vào app (dung lượng) `[đề xuất]`.

### §14.2 Tệp: `java.downloadFile`, `readTxtFile`, `deleteFile`, giải nén, `java.cacheFile`

- **Tài liệu** `[tài liệu jsHelp.md]`: mọi thao tác tệp dùng **đường dẫn tương đối** và chỉ chạm được thư mục đệm của ứng dụng;
  `downloadFile(url)` tải tệp, tên tệp sinh từ url, trả đường dẫn; `unArchiveFile`/`unzipFile`/`unrarFile`/`un7zFile(zipPath)` giải nén, trả đường dẫn
  thư mục; `getTxtInFolder(path)` đọc mọi tệp trong thư mục; `readTxtFile(path)`; `deleteFile(path)`; `java.get*StringContent(url, path[, charset])`
  và `java.get*ByteArrayContent(url, path)` lấy một mục trong tệp nén trên mạng (`*` = Zip/Rar/7Z); `java.cacheFile(url[, saveTime])` tải và lưu
  đệm tệp mạng, huỷ đệm bằng `cache.delete(java.md5Encode16(url))`. `ruleHelp.md` thêm: đệm giải nén được xoá ở lần khởi động sau
  `[tài liệu ruleHelp.md]`.
- **Corpus** `[quan sát]`: `downloadFile` 2 nguồn, `readTxtFile` 2 nguồn (5 lần); `deleteFile`, `unzipFile`, `unrarFile`, `un7zFile`,
  `unArchiveFile`, `getTxtInFolder`, `get*StringContent`, `get*ByteArrayContent`, `cacheFile`: **0**.
  - `🔞爱腐文`: `tmpPath = java.downloadFile(keyUrl)` (ảnh khoá `favicon.ico`), rồi `java.readTxtFile(String(tmpPath), 'ISO8859_1')` → chuỗi giữ
    nguyên byte → `java.strToBytes(…, 'ISO8859_1')` → giải mã bằng `android.graphics.BitmapFactory.decodeStream`.
  - `🌈寻欢小说`: `Math.random()<0.3 && java.downloadFile(lycurl)` rồi `java.readTxtFile(java.md5Encode16(lycurl)+'.json')` → **tên tệp tải về =
    `md5Encode16(url)` + đuôi** và tệp **còn lại qua các lần chạy** (chỉ 30% lượt tải lại).
- **Đặc tả** `[đề xuất]`:
  - Thư mục: `Caches/legado_files/<sha256(bookSourceUrl)>/` (hệ điều hành có thể dọn — chấp nhận được); kiểm an toàn đường dẫn (chặn `..`, đường
    dẫn tuyệt đối ngoài thư mục) theo kiểu `validatePathSafety` của repo.
  - `downloadFile(url)`: tải qua client của nguồn; tên = `md5Encode16(url)` + `.` + đuôi lấy từ path URL (nếu có, ≤ 5 ký tự chữ số) hoặc từ
    `Content-Type`; ghi đè; trả **tên tương đối**; lỗi → `""`. Giới hạn 50 MB.
  - `readTxtFile(path[, charset = "UTF-8"])`: đọc tệp, giải theo bảng mã (nhận tên kiểu Java `ISO8859_1`, `GBK`; `ISO8859_1` cho chuỗi một ký tự mỗi
    byte); không có → `""`.
  - `java.readFile`: **không** có trong tài liệu được phép và 0 lần trong corpus `[quan sát]` → không định nghĩa. Nếu sau này gặp nguồn cần, coi là
    bản trả mảng byte của `readTxtFile` `[UNKNOWN]` U63.
  - `deleteFile(path)` → `true`/`false`.
  - `unzipFile`/`unArchiveFile` (chỉ zip, dùng ZIPFoundation đã có trong repo) → giải vào `<tên tệp>_unzip/`, trả đường dẫn tương đối; `unrarFile`,
    `un7zFile`, mục Rar/7Z của `get*Content` → ném lỗi "chưa hỗ trợ" (không có thư viện, 0 lần dùng). Thư mục giải nén xoá khi app khởi động
    (theo tài liệu); tệp `downloadFile` **giữ** (vì `寻欢小说` cần).
  - `getTxtInFolder(path)`: nối nội dung mọi tệp trong thư mục theo tên tăng dần, cách nhau `\n` `[UNKNOWN]` U58.
  - `getZipStringContent(url, path[, charset])` / `getZipByteArrayContent(url, path)`: tải (lưu đệm theo URL), mở zip, đọc mục `path`.
  - `cacheFile(url[, saveTime])`: như `cache.getFile(md5Encode16(url))`, không có thì tải, lưu bằng `cache.putFile(md5Encode16(url), text, saveTime)`,
    trả chuỗi — khớp cách huỷ đệm tài liệu nêu. `saveTime` tính bằng giây như `cache.*` (§6.7 phần 1).

### §14.3 RSA và chữ ký: `java.createAsymmetricCrypto`, `java.createSign`

- **Tài liệu** `[tài liệu jsHelp.md]`: `java.createAsymmetricCrypto(transformation)` → đối tượng có `.setPublicKey(key)`, `.setPrivateKey(key)` (key là
  mảng byte hoặc chuỗi UTF-8); `decrypt(data, usePublicKey = true)` → byte, `decryptStr(data, usePublicKey = true)` → chuỗi; `encrypt`,
  `encryptBase64`, `encryptHex` cùng tham số; `data` nhận mảng byte, chuỗi base64, chuỗi hex hoặc luồng. `java.createSign(algorithm)` →
  `.setPublicKey`/`.setPrivateKey`, `sign(data)` → byte, `signHex(data)` → hex; `data` là byte, luồng hoặc chuỗi.
- **Corpus** `[quan sát]`: `createAsymmetricCrypto` 4 nguồn; `createSign` 0; RSA tự làm qua `Packages` (`KeyFactory`, `X509EncodedKeySpec`,
  `PKCS8EncodedKeySpec`, `Signature`, `Cipher` RSA) khoảng 7 nguồn (§13.10). Mẫu:
  - `🌍🔞爱丽丝书屋`: `rsa = java.createAsymmetricCrypto("RSA/ECB/PKCS1Padding"); rsa.setPrivateKey(java.base64DecodeToByteArray(PRIVATE_KEY));
    rsa.decryptStr(chapterData.aes_key_encrypt, false)` → giải khoá AES bằng **khoá riêng**.
  - `📂乐读小说`: `java.createAsymmetricCrypto("RSA").setPublicKey(key).decryptStr(data)` — khoá công khai dạng base64 kết thúc `…IDAQAB`, tức
    cấu trúc **X.509 SubjectPublicKeyInfo** (DER); và `setPublicKey` trả **chính đối tượng** (gọi nối được).
- **Đặc tả** `[đề xuất]`:
  - Transformation: `RSA` ≡ `RSA/ECB/PKCS1Padding`; `RSA/ECB/OAEP…` → OAEP (SHA-1 mặc định); khác → lỗi.
  - Khoá công khai: DER SubjectPublicKeyInfo (chấp nhận cả PEM có dòng `-----BEGIN`, và PKCS#1 `RSAPublicKey`); khoá riêng: DER PKCS#8, chấp nhận
    PKCS#1 `RSAPrivateKey`. Chuỗi khoá truyền thẳng (không phải byte) → nếu trông như base64 thì giải base64, ngược lại lấy byte UTF-8 (như tài liệu
    nói) `[UNKNOWN]` U59.
  - `usePublicKey = true` với `decrypt*`: phép mũ **khoá công khai** rồi bỏ đệm PKCS#1 v1.5 **kiểu 1** (dữ liệu do bên kia "mã hoá bằng khoá riêng").
    Security.framework không làm phép này → tự cài phép mũ modulo số lớn (thư viện BigInt Swift hoặc tự viết). `usePublicKey = false` → giải
    bằng khoá riêng qua `SecKeyCreateDecryptedData(.rsaEncryptionPKCS1)`.
  - Dữ liệu dài hơn kích thước khoá `k` byte → chia khối `k` byte, giải từng khối rồi nối; mã hoá chia khối `k − 11` byte `[UNKNOWN]` U59.
  - Nhận dạng `data` là base64 hay hex: như U25 phần 1 (toàn ký tự hex, độ dài chẵn → hex).
  - `createSign(algorithm)`: `SHA256withRSA`, `SHA1withRSA`, `MD5withRSA` → `SecKeyCreateSignature(.rsaSignatureMessagePKCS1v15SHA256…)`; thuật toán
    khác → lỗi. Bản bất đồng bộ `createSignHexAwait(algorithm, publicKey, privateKey, data)` chỉ có ở nguồn đăng ký `[tài liệu rssRuleHelp.md]`, ngoài
    phạm vi.

### §14.4 Mã hoá đối xứng còn thiếu so với phần 1

Phần 1 (§6.4.3) đã gồm AES/DES/DESede với CBC/ECB, đệm PKCS5/PKCS7/Zero/No. Phần còn lại trong corpus `[quan sát]`:

| Hàm / biến đổi | Lần / nguồn | Chữ ký quan sát | Đặc tả `[đề xuất]` |
|---|---|---|---|
| `java.desEncodeToBase64String(data, key, transformation, iv)` | 16 / 4 | `java.desEncodeToBase64String("utId=…", "snY%169j", "DES/ECB/PKCS5Padding", "")` | `createSymmetricCrypto(transformation, key, iv).encryptBase64(data)`; `iv` rỗng với ECB → bỏ |
| `java.tripleDESEncodeBase64Str(data, key, mode, padding, iv)` | 6 / 3 | `java.tripleDESEncodeBase64Str(sign, key, "CBC", "PKCS5Padding", iv)` | `createSymmetricCrypto("DESede/" + mode + "/" + padding, key, iv).encryptBase64(data)` |
| `"AES"`, `"DES"` trần | 25 + 25 chuỗi (gồm tên thuật toán của `SecretKeySpec`) | `Cipher.getInstance("AES")` | ECB + PKCS5 (§13.10) |
| AES-GCM qua `GCMParameterSpec` | 1 / 1 | – | CryptoKit `AES.GCM`, thẻ xác thực nằm cuối dữ liệu |
| `ChaCha20` | 1 chuỗi | – | bỏ |
| `java.aesDecodeToString(str, key, transformation, iv)` | 0 (chỉ trong ví dụ của `rssRuleHelp.md`) | – | không cài (không biết `str` là gì) |

### §14.5 Danh sách đầy đủ `java.*` / `source.*` / `cookie.*` / `cache.*` chưa có đặc tả ở phần 1

Lập bằng cách lấy mọi token `java.x`, `source.x`, `cookie.x`, `cache.x` trong corpus (mọi trường, mọi loại) trừ các token đã nhắc trong phần 1.
"Lần / nguồn" trên 3701 nguồn; "t0:… t2:…" = tách theo loại `[quan sát]`. Hàm đã đặc tả ở các mục trước của phần 2 ghi số mục.

**Có lời gọi thật**:

| Thành viên | Lần / nguồn | Chữ ký và nghĩa | Đợt | Nhãn |
|---|---|---|---|---|
| `java.ruleUrl` (thuộc tính) | 7 / 7 (t0 4, t2 3) | URL request như rule viết, trong `loginCheckJs` — §10.7 | 2 | `[quan sát]` |
| `java.webViewUA` (thuộc tính) | 2 / 1 | = `java.getWebViewUA()` (đọc getter như thuộc tính, §6.3 phần 1): `JSON.stringify({"User-Agent": java.webViewUA})` | 2 | `[quan sát]` |
| `java.base64Decoder(s)` | 2 / 2 | không có trong tài liệu; dùng như `base64Decode` (`java.base64Decoder(U(result))`) | 2 | `[UNKNOWN]` U60: khuyến nghị bí danh `base64Decode` |
| `java.clearCookie(url)` | 1 / 1 | xoá cookie tên miền (`clearCookie('https://m.libahao2.com')` rồi toast "Cookie 已清除") = `cookie.removeCookie(url)` | 2 | `[quan sát]` |
| `java.sleep(ms)` | 1 / 1 | chờ trong vòng lặp dò cookie, bọc `try` | 2 | `[đề xuất]`: = `Packages.java.lang.Thread.sleep`, tối đa 5 s/lần |
| `java.getThemeConfig()` | 1 / 1 | nối vào chuỗi toast sau khi đăng nhập thành công (`番茄🍅`); không có → `login()` ném lỗi và bị coi là thất bại | 2 | `[đề xuất]`: định nghĩa, trả `""` |
| `java.refreshBookInfo()` | 1 / 1 | `action` của form (`哔哩哔哩（优+++）`) — §13.3 | 3 | `[UNKNOWN]` U52 |
| `java.openBook(id, name)` | 2 / 1 | trong thuộc tính `onclick` của HTML giới thiệu (`🏷七猫小说`) — không chạy trong engine | bỏ | `[quan sát]` |
| `java.upLoginData`, `java.reLoginView`, `java.startBrowserDp`, `java.getVerificationCode`, `java.startBrowser`, `java.startBrowserAwait` | §10.1 | §10.4, §10.8 | 2 | – |
| `java.initUrl`, `java.getStrResponse`, `java.getResponse`, `java.getHeaderMap` | §10.1 | §10.7 | 2 | – |
| `java.refreshTocUrl`, `java.reGetBook`, `java.refreshBookUrl` | 12/12, 0, 3/3 | §13.3 | 2 | – |
| `java.refreshExplore`, `java.searchBook` | 74/32, 7/7 | §11.5, §11.6 | 2 | – |
| `java.importScript` | 6 / 4 | §13.7 | 2 | – |
| `java.queryTTF`, `java.queryBase64TTF`, `java.replaceFont` | 2/2 mỗi hàm | §14.1 | 3 | – |
| `java.downloadFile`, `java.readTxtFile` | 2/2, 5/2 | §14.2 | 3 | – |
| `java.createAsymmetricCrypto` | 4 / 4 | §14.3 | 3 | – |
| `java.desEncodeToBase64String`, `java.tripleDESEncodeBase64Str` | 16/4, 6/3 | §14.4 | 3 | – |
| `java.openWeb(url)` | 2 / 2 (t4) | §9.6: không định nghĩa | – | `[quan sát]` |
| `java.openUrl(url[, mimeType])` | 23 / 10 | mở link ngoài hoặc scheme của ứng dụng khác `[tài liệu jsHelp.md]`; FreeBook: `legado://`/`yuedu://` → §12.2; `http(s)` → mở trình duyệt trong app; scheme khác → hỏi người dùng rồi `UIApplication.open` | 3 | `[đề xuất]` |
| `java.copyText(text)` | 17 / 4 | chép vào bộ nhớ tạm (`UIPasteboard`), trả `undefined` | 3 | `[quan sát]` nghĩa; cài `[đề xuất]` |
| `java.open(kind, …)` | 33 / 8 | `"explore", url, title[, source]` mở danh sách khám phá với URL; `"login"`; `"search"` — chủ yếu trong `callBackJs` (§13.11) | hoãn hẳn | `[quan sát]` |
| `java.showBrowser(url, html, js)`, `java.showReadingBrowser(url, title)` | 15/10, 9/7 | chỉ ở nhánh "ứng dụng sửa đổi" hoặc trong `try` có dự phòng `startBrowser` | – | không định nghĩa `[đề xuất]` |
| `source.putLoginInfoMap(json)` | 2 / 2 | §10.5 | 2 | `[UNKNOWN]` U40 |
| `cookie.mapToCookie(map)` | 1 / 1 | biến map cookie của phản hồi (`response.cookies()`) thành chuỗi `k=v; k2=v2` | 2 | `[quan sát]` ý đồ; cài `[đề xuất]` |
| `refreshContent()` (chỉ gọi qua bí danh `j = java`) | 1 / 1 | `🏷微信读书二合一本地源`: `try { j.refreshContent(); } catch (…) {}` sau khi lưu cài đặt bình luận, kèm toast "正文已刷新" (nội dung đã làm mới) → nạp lại chương đang đọc | 3 | `[UNKNOWN]` U62; khuyến nghị: yêu cầu Reader nạp lại chương hiện tại (bỏ cache chương đó), không chờ |
| `payAction` (khoá rule, không phải hàm) | 19 / 7 có giá trị (phần 1) | §14.7 | 3 | – |

**Chỉ có trong chú thích hoặc dùng để dò biến thể — không định nghĩa** `[quan sát]`:

| Token | Lần / nguồn | Ngữ cảnh |
|---|---|---|
| `java.ajaxTestAll`, `java.openVideoPlayer`, `cookie.setWebCookie`, `source.refreshJSLib` | 3–6 / 3–4 | chú thích "hàm mới của bản Sigma" trong `loginCheckJs` của `🔞 Linpx`, `🔞兽人小说站`; một lời gọi `openVideoPlayer` bị chú thích (`//java.openVideoPlayer(content, title)`) |
| `java.webview()`, `java.startBrowserAwaitAwait` | 3 / 3 | chú thích "bản X không dùng được hàm này" |
| `java.removeCookie` | 3 / 3 | chú thích `// java.removeCookie("snssdk.com")` |
| `java.redirectUrl` | 1 / 1 | chữ trong `bookSourceComment` |
| `java.readBookConfig`, `java.getAppVariant` | 2 / 1 mỗi cái | `typeof java.readBookConfig == "undefined"`, `!java.getAppVariant` để dò biến thể |
| `source.getTag` | 1 / 1 (t3) | `if(source.getTag)` dò biến thể |
| `java.qread`, `java.deviceID`, `java.getUserAgent`, `java.reLoginView` (ngoài form) | – | §6.10 phần 1, §10.4 |

**Không phải thành viên bridge** `[quan sát]`: `java.lang`, `java.util`, `java.security`, `java.net` (tên gói, §6.9 phần 1); `java.toString()`;
`source.len`/`length`/`indexOf`, `cookie.split` (biến cục bộ tên `source`/`cookie` che biến môi trường); `source.server`, `cache.dev_id`
(thuộc tính tự gán).

**Gọi qua bí danh**: quét thêm `j.x(`, `jv.x(`, `java['x']` (biến cục bộ trỏ tới `java`, hoặc truy cập bằng chuỗi) `[quan sát]`: ngoài
`refreshContent` ở trên, mọi tên gọi qua bí danh đều đã có trong phần 1/phần 2 (`j.upLoginData` 6 lần, `j.showBrowser` 5, `j.startBrowserAwait` 2,
`jv.aesBase64DecodeToString`, `java['ajax']`, `java['toast']`, …). Vì vậy bridge phải là **đối tượng thật** gán được cho biến khác (`const { java } =
this`, `var j = java`), không phải cú pháp đặc biệt. Lời gọi qua tên tính toán (`java[_0x91ccce(0x77)](result)`, mã bị làm rối) không đếm được.

**Có trong tài liệu nhưng 0 lần trong corpus** (cài khi rảnh, theo đặc tả ở mục tương ứng): `java.webViewGetSource`, `java.webViewGetOverrideUrl`
(§14.8), `java.getResponse`, `java.reGetBook`, `java.toURL`, `java.cacheFile`, `java.createSign`, các hàm tệp/giải nén (§14.2), `source.login()`.

### §14.6 Shim `android.graphics` tối thiểu

Chỉ để chạy `imageDecode` của `禁漫天堂` (2 nguồn), `🎃刺猬猫🎃#2` và bước đọc ảnh khoá của `🔞爱腐文` `[quan sát]`. Cài trên CoreGraphics; mọi
thành viên khác → ném lỗi "chưa hỗ trợ" `[đề xuất]`:

| Lớp | Thành viên đã thấy |
|---|---|
| `BitmapFactory` | `decodeByteArray(bytes, offset, length)`, `decodeStream(inputStream)` → `Bitmap` hoặc `null` |
| `Bitmap` | `getWidth()`, `getHeight()`, `createBitmap(src, x, y, w, h)` (cắt), `createBitmap(w, h, Bitmap.Config.ARGB_8888)` (trống), `compress(Bitmap.CompressFormat.PNG\|JPEG, quality, outputStream)` → `true` |
| `Canvas` | `new Canvas(bitmap)`, `drawBitmap(bitmap, left, top, paint)`, `drawBitmap(bitmap, srcRect, dstRect, paint)` |
| `Rect`, `Paint` | `new Rect(l, t, r, b)`; `new Paint()` (bỏ qua mọi thuộc tính) |
| `java.io.ByteArrayOutputStream` / `ByteArrayInputStream` | đã ở đợt 2 (§6.9 phần 1) |

Toạ độ gốc ở góc trên trái, đơn vị pixel (khác CoreGraphics gốc dưới trái — shim phải lật).

### §14.7 `payAction` (mua chương)

- Tài liệu: giá trị là một link hoặc mã JS; nếu kết quả là địa chỉ web thì ứng dụng mở trình duyệt tới đó; nếu JS trả `true` thì ứng dụng nạp lại
  danh sách chương lẫn chương đang đọc `[tài liệu ruleHelp.md]`.
- Corpus: 7 nguồn có giá trị `[quan sát]`: JS gửi POST mua (`天地中文网`, `独阅读网` trả `res.code == "100000" ? true : false`), hoặc chỉ là URL
  (`{{baseUrl}}`, `chapter.url`) để mở trang chương mà mua bằng web.
- Đặc tả `[đề xuất]`: nút "Mua" hiện ở chương `isVip && !isPay` khi nguồn có `payAction`; chạy với `baseUrl` = URL chương, `book`, `chapter`, `source`,
  `java`, `cookie`, `cache`; kết quả là URL `http(s)` → mở trình duyệt hiện cho người dùng (§10.8); `true` → làm mới mục lục + nạp lại chương; khác
  → không làm gì. Không bao giờ tự chạy `payAction` (chỉ khi người dùng bấm, có hộp xác nhận vì có thể trừ tiền tài khoản trên trang).

### §14.8 `java.webViewGetSource` và `java.webViewGetOverrideUrl`

0 lần trong corpus. Tài liệu `[tài liệu jsHelp.md]`: `webViewGetSource(html, url, js, sourceRegex)` dùng WebView lấy URL tài nguyên;
`webViewGetOverrideUrl(html, url, js, overrideUrlRegex)` dùng WebView lấy URL chuyển hướng. Đặc tả `[đề xuất]`: cùng lõi với §9.4 — nạp (`html` không
rỗng thì nạp chuỗi đó với URL nền `url`), chạy `js` sau khi tải xong nếu có; `GetSource` trả URL request tài nguyên đầu tiên khớp regex;
`GetOverrideUrl` trả URL điều hướng đầu tiên (chặn điều hướng đó) khớp regex; hết giờ → `""`.

---

## §15. Phụ lục

### §15.1 Đợt 2 / đợt 3 / bỏ hẳn

| Hạng mục | Đợt 2 | Đợt 3 | Bỏ hẳn |
|---|---|---|---|
| Tranh (§8) | chạy loại 2: `content` → danh sách ảnh, bộ tách `src` khoan dung, option `headers`/`style`, gộp header + `Referer`, luật ảnh lười, phân trang + URL dừng, `replaceRegex` trên HTML, nối `ComicPageSource`/`ComicReaderView`/`ComicOfflineStore`; `imageDecode` và `coverDecodeJs` mức byte (AES, XOR, hàm `jsLib`) — **dời lên từ đợt 3** của phần 1 vì 5/175 nguồn tranh cần | shim `android.graphics` (§14.6); option ảnh `click`/`js`; ảnh trong truyện chữ theo `imageStyle` | – |
| Video (§9) | chạy loại 4: tập = mục lục, giải nguồn phát 4 nhánh, không tải thân media, `sourceRegex` với WebView, header phát, `startBrowser` thành ứng viên phát | – | chip tuyến/server riêng; tải video offline |
| Đăng nhập (§10) | 3 chế độ, form `loginUi` (mọi kiểu đã thấy), `login()`, thông tin + header đăng nhập trong Keychain và tự gắn header, `loginCheckJs` + `ruleUrl`/`initUrl`/`getStrResponse`/`getHeaderMap`, `startBrowser`/`startBrowserAwait`/`getVerificationCode`, `upLoginData`/`reLoginView` trong form, hàm dựng `StrResponse` | `source.login()` không giao diện (0 lần, §10.4 mục 7) | – |
| Khám phá động (§11) | `select`/`toggle`/`text`/`button`/`title`, `infoMap` lưu bền, `action`, `refreshExplore`, `searchBook`, bố cục flex | – | – |
| Quản lý (§12) | xuất mảng JSON, bí danh scheme nhập (có xác nhận), chế độ gỡ lỗi, kiểm tra hàng loạt, `customOrder`/`respondTime`/`lastUpdateTime`, trình sửa biến nguồn/biến sách + `variableComment` | xuất kèm biến nguồn (công tắc) | – |
| Phần đuôi (§13) | URL `data:`, `preUpdateJs` + `refreshTocUrl`/`reGetBook`, `formatJs`, ghi thuộc tính `book` có chọn lọc, `setReverseToc`, `book.type` bitmask + ghi đè loại theo sách, `importScript`, `Jsoup.connect`, `javax.crypto` đối xứng + `Mac` + `MessageDigest` | `GCMParameterSpec`, `setUseReplaceRule` | `callBackJs`, `customButton`, `eventListener`, `java.open`, `java.toURL` |
| Phần hiếm (§14) | `java.webViewUA`, `base64Decoder`, `clearCookie`, `sleep`, `getThemeConfig`, `cookie.mapToCookie`, `source.putLoginInfoMap` | font (§14.1), tệp + zip (§14.2), RSA + chữ ký (§14.3), `desEncodeToBase64String`, `tripleDESEncodeBase64Str`, `payAction`, `openUrl`, `copyText`, `webViewGetSource`/`webViewGetOverrideUrl`, `cacheFile`, `getZip*Content` | Rar/7z, `ChaCha20`, `aesDecodeToString`, `showBrowser`, `showReadingBrowser`, `openWeb`, `openBook`, mọi tên dùng để dò biến thể (§14.5) |

### §15.2 Điểm `[UNKNOWN]` cần bộ nghiệm thu đo (U29–U63)

Nối tiếp §7.2 phần 1, cùng cách đo (chạy cả hai phương án trên các nguồn bị ảnh hưởng, so kết quả).

| # | Điểm | Khuyến nghị hiện tại | Đo |
|---|---|---|---|
| U29 | Header nguồn có áp cho request ảnh (§8.3) | có; gộp với option, thêm `Referer` = URL chương nếu thiếu | 175 nguồn tranh: tỉ lệ ảnh HTTP 403 với/không header nguồn, với/không `Referer` tự thêm |
| U30 | `concurrentRate` có áp cho ảnh (§8.3) | không; tối đa 4 ảnh song song | 7 nguồn tranh có `concurrentRate`: lỗi 429/403 |
| U31 | Nghĩa `imageStyle = TEXT` (§8.5) | ảnh cao một dòng, cùng dòng chữ | 12 nguồn loại 0: chụp màn so với trang gốc |
| U32 | `src` của `imageDecode` có giữ khối option/phần `#` (§8.6) | giữ nguyên | 7 nguồn có `imageDecode` |
| U33 | Không tải thân khi `chapterUrl` là tệp media (§9.3) | không tải | 13 nguồn video: tập đầu ra nguồn phát hay không |
| U34 | `sourceRegex` có tự bật WebView (§9.4) | không; chỉ dùng khi request là WebView và làm bộ lọc sniff | 8 nguồn media có `sourceRegex` |
| U35 | `loginUi` rỗng + `loginUrl` là JS có `login` (§10.2) | form trống + nút gọi `login()` | nguồn thuộc nhóm này: `login()` có chạy được không cần ô nhập |
| U36 | `type: input`, khoá `variable` (§10.3) | như `text` | 2 nguồn |
| U37 | `login()` trả `false` là thất bại (§10.4) | có | nguồn có `return false` trong `login` |
| U38 | `java.upLoginData()` không tham số (§10.4) | lưu giá trị đang có trên form | 1 nguồn |
| U39 | `getLoginInfo()`/`getLoginHeader()` khi chưa có (§10.5–§10.6) | `null` | nguồn đọc hai hàm này khi chưa đăng nhập: lỗi JS |
| U40 | `source.putLoginInfoMap` (§10.5) | = `putLoginInfo` | 2 nguồn |
| U41 | Header đăng nhập không phải JSON (§10.6) | `k=v;…` → `Cookie`; khác → bỏ | nguồn gọi `putLoginHeader` với chuỗi không phải JSON |
| U42 | Phạm vi gắn header đăng nhập (§10.6) | luồng chính + `java.ajax`…, chỉ cùng tên miền gốc | log "bỏ không gắn vì khác tên miền" trên nguồn đã đăng nhập |
| U43 | `loginCheckJs` chạy sau request nào (§10.7) | chỉ request luồng chính | 52 nguồn: so kết quả khi chạy thêm sau `java.ajax` |
| U44 | Nghĩa tham số `getStrResponse(jsStr, sourceRegex)` (§10.7) | khác `null` → WebView | 6 nguồn (đều gọi với `null` hoặc không tham số) |
| U45 | `startBrowserAwait`: tham số 3 vắng/`true` tải lại bằng HTTP; tham số 4 là HTML (§10.8) | như mô tả | 45 nguồn, thử tay một mẫu mỗi dạng |
| U46 | `infoMap` lưu qua lần mở app (§11.3) | lưu bền | 21 nguồn có `select` |
| U47 | `action` khám phá có cần `exploreUrl` làm thư viện (§11.4) | chạy lại khi gặp `ReferenceError` | 10 nguồn có `button` |
| U48 | Xuất nguồn có kèm biến nguồn (§12.1) | không (có công tắc) | – (quyết định sản phẩm) |
| U49 | Scheme nhập nhanh (§12.2) | scheme riêng + bí danh `legado://import/importonline`, `yuedu://booksource/importonline`, có xác nhận | – (không có tài liệu) |
| U50 | `respondTime = 180000` là mức trần thời gian kiểm (§12.4) | trần 180 s | 24 nguồn |
| U51 | Nghĩa `weight` (§12.5) | chỉ tiêu chí phụ khi xếp kết quả | 671 nguồn khác 0 |
| U52 | `java.refreshBookUrl()`, `java.refreshBookInfo()` (§13.3) | = `refreshTocUrl()` | 3 + 1 nguồn |
| U53 | `book.setUseReplaceRule(false)` (§13.5) | bỏ lọc rác của FreeBook cho sách | 7 nguồn: so nội dung có/không lọc |
| U54 | `book.type` đọc ra với nguồn video; giá trị ghi `3` (§13.6) | đọc `8`; bỏ qua `3` | nguồn ghi `book.type` (24) và nguồn video |
| U55 | `Jsoup.connect` có gắn header nguồn (§13.9) | không | 9 nguồn |
| U56 | Byte có dấu/không dấu trong shim Java (§13.10) | `Uint8Array` | dò mã so sánh `< 0` trên biến byte |
| U57 | Nghĩa tham số `filter` của `replaceFont` (§14.1) | bỏ ký tự có glyph rỗng trong `f1` | 2 nguồn |
| U58 | Thứ tự/ngăn cách của `getTxtInFolder` (§14.2) | theo tên, `\n` | 0 nguồn (để sau) |
| U59 | RSA: chuỗi khoá không phải byte; chia khối (§14.3) | base64 nếu trông như base64; chia khối `k`/`k−11` | 4 + 7 nguồn RSA |
| U60 | `java.base64Decoder` (§14.5) | bí danh `base64Decode` | 2 nguồn |
| U61 | JS trả phần tử HTML ở trường **không** phải `content` (§15.3 mục 2) | outer HTML, để bước làm sạch của trường xử lý | rule JS trả `getElement(s)`/`Jsoup…select` không kèm `.text()` |
| U62 | `refreshContent()` (§14.5) | nạp lại chương đang đọc | 1 nguồn |
| U63 | `java.readFile` (§14.2) | không định nghĩa; nếu cần thì trả mảng byte | 0 nguồn |

Điểm phần 1 có bằng chứng mới: **U4** (`html` là outer HTML — §8.2), **U22** (`data:` — §13.1, vẫn mở), **U26** (`formatJs` `index` — §13.4, nghiêng
về đếm từ 1).

### §15.3 Đính chính phần 1

1. **§2.8.4 / U4 — `html` là outer HTML**: phần 1 để `[UNKNOWN]` và khuyến nghị outer. Bằng chứng mới chốt hướng đó: `img@html##data-original##src`
   (2 nguồn tranh) chỉ có nghĩa khi `@html` trả cả thẻ `<img …>` (§8.2). Giữ khuyến nghị, hạ mức rủi ro.
2. **§2.14 — JS trả phần tử/danh sách phần tử, kết quả cuối `getString`**: phần 1 ghi "chữ (`text`) của phần tử". Với `content` điều này sai:
   `🎨笔趣漫画` trả danh sách `<img>` đã sửa `src`, cần **outer HTML nối `\n`** (chữ của `<img>` rỗng). Sửa bảng: kết quả cuối `getString` của phần tử
   = outer HTML (như chuyển đối tượng sang chuỗi); với trường không phải `content` thì bước làm sạch của trường (§5.1.2 phần 1) bỏ thẻ — `[UNKNOWN]` U61.
3. **§1.3 và §4.8 — nhãn của `loginCheckJs`**: phần 1 ghi "kiểm tra sau mỗi request `[tài liệu ruleHelp.md]`". `ruleHelp.md` chỉ nói nó dùng để
   kiểm kết quả đăng nhập; `jsHelp.md` nói vài hàm chỉ có hiệu lực trong nó. "Chạy sau mỗi request" là `[quan sát]` (§10.7) — sửa nhãn, giữ nội dung.
4. **§6.6 — `book.type` = `0`**: corpus cho thấy nguồn đi nhánh "Android chính thức" (chính nhánh FreeBook chọn ở §6.10) dùng **bitmask** `8` chữ /
   `32` audio / `64` tranh / `128` tệp, và nguồn tranh kiểm `book.type == 64`. Đọc `book.type` phải trả theo bitmask (§13.6).
5. **§1.2.1 — JSON lỏng**: thêm hai trường hợp. (a) Nháy cong `“…”` / `‘…’` dùng như nháy thẳng: `',{webView:“true”}'` ở `chapterUrl` của 2 nguồn audio
   (§9.4). (b) Chuỗi `"true"`/`"false"` ở option boolean (`webView: "true"`) → bool (luật truthy §5.4.3 phần 1).
6. **§3.6 — so khoá option không phân biệt hoa thường**: phần 1 để `[đề xuất]`; nay có bằng chứng `"webview":true` (chữ `v` thường) ở `searchUrl` của
   `🎬艾格动漫` → `[quan sát]`.
7. **§6.10 — `java.reLoginView`**: giữ khuyến nghị "không định nghĩa" ở ngữ cảnh rule, nhưng định nghĩa trong ngữ cảnh form đăng nhập (§10.4).
8. **§6.11 — bảng hoãn**: `java.cacheFile`, `unzipFile`, `unrarFile`, `un7zFile`, `unArchiveFile`, `getTxtInFolder`, `java.get*Content`, `java.createSign`,
   `java.reGetBook`, `java.toURL` có **0** lần trong corpus; `java.downloadFile`/`readTxtFile` chỉ 2 nguồn. `imageDecode`/`coverDecodeJs` dời lên đợt 2
   (§15.1). `java.startBrowserDp` chỉ xuất hiện trong nhánh "轻阅读" nên thực tế không bao giờ được gọi.

### §15.4 Ghi chú tái lập số liệu

- Script Python tự viết (chạy `python -I`, chỉ đọc JSON như dữ liệu) dùng lại bộ nạp của phần 1: bỏ trùng theo `bookSourceUrl`, giữ bản gặp trước theo
  thứ tự `1315, 1316, 1208, 1158, 1298, 1272`. Đếm bằng regex nên lẫn chú thích JS và tên miền; lời gọi qua tên tính toán trong mã bị làm rối
  (`java[_0x…(…)]`) không đếm được; số liệu sai lệch vài phần trăm. Bảng tần suất cũ
  (`census_all.txt`) chỉ dùng để đối chiếu nhóm `java.*`.
- **Tải thêm bộ nguồn** (ngày 2026-10-21, `https://www.yckceo.com/yuedu/shuyuans/json/id/<id>.json`): `1061`, `919`, `1111`, `1108`, `987`, `252`,
  `199`, `392`. Chỉ `1111` có nguồn loại 4 mới (`西瓜卡通（优+）`), đã chép vào `D:\1.SOURCE_CODE\legado-corpus\yck_1111.json`; 7 bộ còn lại không có
  video mới, để trong thư mục tạm, không dùng cho số liệu nào. Để tìm id đã đọc khoảng 37 trang danh sách/tìm kiếm của yckceo (tìm theo từ khoá trên
  trang danh sách bộ không trả kết quả). Mẫu video vì thế chỉ có 13 nguồn.
- **Curl trang thật** (3 request): `http://23.225.142.42/api.php/provide/vod/?ac=detail&wd=三体&pg=1` (định dạng MacCMS, §9.2),
  `https://vip.ffzy-plays.com/share/fd2c18a27361dd16124f2780015b05f3` (trang chia sẻ chứa `url = "/…/index.m3u8?sign=…"`), và HEAD một URL `.m3u8`
  (trả 502, không dùng làm bằng chứng). Trang có thể đã đổi.
- Kiểm chứng parser HTML (§8.2.1) bằng `html.parser` của thư viện chuẩn Python.
