# Kế hoạch: Rule dịch Quick Translate — engine, màn hình quản lý và công tắc bật/tắt

> **Trạng thái**: bản viết lại, **thay thế** `Docs/Plan/quick-trans-rule-all-in-one-v21-ultralite.md`
> (giữ file cũ để tra cứu phần port DSL/priority, nhưng nguồn rule, chính sách token và scope UI của nó đã lỗi thời).
> **Ngày**: 2026-08-25. **Mức xác minh**: đọc code trong `Sources/`, đọc reference `D:\Study\vbook-toolkit\src\engine\`,
> đo trực tiếp hai file rule bằng script tạm (đã xoá). **Chưa build** — checkout đang ở Windows, `xcodebuild` chỉ chạy trên macOS.

## 1. Ba yêu cầu và deliverable tương ứng

| Yêu cầu chủ dự án | Deliverable |
| --- | --- |
| Áp rule dịch **sau** Phồn thể → Giản thể và **trước** tokenize | `QuickTranslationRuleEngine.rewrite` chèn ở đầu `TranslateUtils.performTranslation`, trước `punctuationMapping` |
| Thêm **màn hình quản lý rule dịch** | `QuickTranslationRulesView` trong `Sources/Views/Settings/Translation/`, link từ section "Dịch Thuật Quick Translate" của `SettingsView` |
| Thêm **công tắc bật/tắt rule** trong Settings | `@AppStorage("isQuickTranslateRuleEnabled")`, mặc định **bật**, vào cache key + generation token |

Ngoài ba việc trên, plan không mở rộng scope: không sửa tokenizer, không sửa từ điển, không đụng `Tests/`.

## 2. Nguồn rule thật (đo trực tiếp, thay thế phần "nguồn chuẩn" của plan cũ)

| | `D:\AudioData\rule-aio.txt` | `D:\AudioData\Rule_new.txt` |
| --- | --- | --- |
| Bytes / dòng vật lý | 65.964 / 1.335 | 689.684 / 17.285 |
| Line ending / BOM | **CRLF** / không | **CRLF** / không |
| Rule parse được | **1.177** | **17.278** |
| `<n>` / `<y>` / `<L>` | 1.269 / 97 / 1 | 355 / 0 / 0 |
| `<vp>` / `<w>` / `<pn>` | 3 / 9 / 0 | 0 / 0 / **16.941** |
| Token không khai range | 1 | **17.278 (toàn bộ)** |
| Group lồng nhau | 15 | 0 |
| LHS chứa `\` | 2 | 0 |
| LHS chứa space | 0 | 166 |

Hệ quả cho lộ trình — **một engine đủ năng lực, phân đợt theo NGUỒN rule, không phân đợt theo loại token**:

- Bản trước của plan này chia đợt theo *loại token* (`<n>/<y>/<L>` trước, token từ điển sau). Chia như vậy sai: nó buộc phải viết matcher regex ở đợt 1 rồi **bỏ đi** ở đợt 2, vì token ràng buộc từ điển không diễn tả được bằng regex (§7.1). Engine viết một lần, hỗ trợ đủ `<n> <y> <L> <ne> <pn> <vp> <hv> <w>`.
- **Nguồn nạp mặc định**: file chuẩn v21 (633 rule) hoặc `rule-aio.txt` (1.177 rule) — quyết định #2 ở §17. Cả hai chạy được ngay.
- **`Rule_new.txt` nhập được bằng cùng engine đó**, nhưng *bật* nó là quyết định riêng, vì phụ thuộc ba điều kiện **ngoài** engine: từ điển `Pronouns` là optional (có thể nil), công tắc `isTranslationPronounsEnabled` mặc định **tắt**, và 161/337 rule `<n>` trong chính file đó đã chết vì literal space (§15).

**File chuẩn v21 đã tìm được và đo lại** (`D:\AudioData\[VBOOK BẢN BETA - NO NE_PN] Rule-All-in-One-normalized-v21-ultralite.txt`): 36.608 bytes, **LF**, không BOM, 676 dòng vật lý, **633 rule** hoạt động — khớp con số plan cũ khai. Đây là nguồn của 11 dòng header đặc tả DSL (dòng 9-19), tức **hợp đồng viết rule** dùng ở §4. Token trong rule hoạt động của nó: `<n:1-6>`×312, `<n:1-2>`×172, `<n:1-3>`×120, `<y:1-4>`×100, `<n:1-8>`×84, `<y:1>`×41, `<n:1-4>`×33, `<n:1>`×16, `<n:1-10>`×13, `<y:3-4>`×5, `<y:1-2>`×4, `<L>`×1 — **không có token từ điển nào**; `<ne>/<pn>/<vp>/<hv>/<w>` chỉ xuất hiện trong header. File này là ứng viên tốt cho resource bundled (ít hơn 544 rule so với aio, nhưng LF sạch và không có dòng lỗi nào thuộc nhóm token từ điển); chọn file nào là quyết định #2 ở §17.

Không hard-code số rule vào code, không phụ thuộc runtime vào ổ `D:`.

> **Cập nhật khi thực thi (1.3.269), theo yêu cầu chủ dự án**: bộ rule **không** đi kèm app. Không có resource bundled nào; file mặc định `QuickTranslateRules.txt` được đưa lên **HuggingFace** cùng dataset với VietPhrase (`datasets/raikiri1498/vietpharse`) và app tải xuống `applicationSupportDirectory/translate/QuickTranslateRules.txt` bằng nút trong màn quản lý. Chưa tải thì `activeSnapshot` là `nil` và pipeline dịch chạy như trước khi có tính năng. Mọi chỗ nói "bundled" ở dưới đọc thành "file mặc định tải từ HuggingFace".

## 3. Hiện trạng pipeline đã xác minh

| Bước | Vị trí | Ghi chú bắt buộc nhớ |
| --- | --- | --- |
| Phồn thể → Giản thể | `TranslateUtils.textForTranslation` (`TranslateUtils.swift:274-280`) | Chỉ chạy khi callsite truyền `shouldConvertTraditionalToSimplified: true`; dùng `applyingTransform` |
| Gate vào dịch | `translateText` (`:382-407`) | `guard containsChinese(text)` (`:384`) và `guard isVietPhraseLoaded` (`:387`) đứng **trước** `performTranslation` |
| Cache dịch | `:391-405` | Key `translate|v3|g:…|b:…|s:…|meta/content|bookId|md5` |
| Punctuation mapping | `performTranslation` (`:512-516`) | Bảng `:60-69` biến `．`→`". "`, `，`→`", "`, `。`→`". "` … |
| Tokenize | `:518` → `VietPhraseTokenizer.tokenize` | |
| Tra từ điển | `:522-525` → `resolveTokenMeaning` → `lookupRawTranslation` (`:409-490`) | Thứ tự 8 tầng: BookNames → CustomNames → Names → Pronouns → LuatNhan → BookVP → CustomVP → VP |
| Ghép + dọn | `:527` `joined(separator: " ")` → `postProcessText` (`:611`) | |

Ba hệ quả phải ghi vào phần nghiệm thu, vì chúng dễ bị hiểu sai thành bug:

1. **Rule không chạy khi chuỗi không có chữ Hán** (gate `:384`) và **không chạy khi từ điển chưa nạp xong** (gate `:387`). 5 rule trong `rule-aio.txt` có LHS thuần Latin (`<n:1-6>( )?m`, `…km`, …) nên chỉ nổ khi câu còn chữ Hán ở chỗ khác. Đây là hành vi chấp nhận được; muốn khác thì phải nới gate và đó là thay đổi riêng.
2. **Output của rule không phải text cuối**: chuỗi Việt do rule sinh ra vẫn đi qua tokenizer rồi bị ghép lại bằng `joined(separator: " ")` (`:527`). `postProcessText` chỉ dọn space trước `,.?!}]>”’):】`. Nên khoảng trắng trong RHS không được coi là bất biến.
3. **Chữ Hán rule không khớp vẫn đi tiếp bằng đường cũ**, nên rewrite chỉ cần lo phần nó thật sự thay.

## 4. DSL: hợp đồng trong header file rule vs ngữ nghĩa thật của reference

Có **hai** nguồn định nghĩa DSL, phải phân biệt:

- **Hợp đồng viết rule** — 11 dòng header của file chuẩn v21 (dòng 9-19). Đây là thứ người viết rule dựa vào.
- **Ngữ nghĩa đã thi hành** — `compile()`/`convert()` của `ruleEngine.ts` (`:218-288`, `:192-209`). Đây là thứ đã chạy thật.

Hai nguồn **lệch nhau ở 3 điểm** (§4.2), và ở cả 3 điểm plan này chọn theo **header**, không theo reference.

### 4.1 Cú pháp và bảng token

Tên token viết **trần**: `<n>`, `<y>`, `<L>`, `<ne>`, `<pn>`, `<vp>`, `<hv>`, `<w>`. Hậu tố `:min-max` (hoặc `:n` cho độ dài cố định) là **tuỳ chọn**, viết liền sau tên trong cùng dấu `<>`: `<n:1-6>`, `<y:1>`, `<n:1-1>`. Nó giới hạn **số ký tự Unicode token được phép nuốt**, không phải khoảng giá trị số. Không có ký hiệu `[...]` nào trong DSL — cách viết `<n[:min-max]>` ở bản plan trước chỉ là lối ghi BNF cho "hậu tố tuỳ chọn" và đã bỏ vì gây hiểu sai.

Hậu tố này là **dùng chung cho mọi loại token**, không riêng token số — đo được:

- File chuẩn v21: **mọi** token số đều khai range; `<L>` xuất hiện **1** lần và **luôn trần** (dòng 90 `第<n:1-6><L> = {1} {0}`); token từ điển xuất hiện **0** lần trong rule hoạt động.
- `rule-aio.txt`: `<L>` cũng trần (dòng 12 `第( )?<n:1-6>( )?<L>`), **nhưng** token từ điển ở đây **có** range: `<w:1-6>`×9, `<vp:1-10>`×3. Nên "token từ điển không nhận range" đúng với file chuẩn, không đúng với `rule-aio.txt`.
- `Rule_new.txt`: **toàn bộ** trần (`<pn>`×16.941, `<n>`×355).

| Token | Header nói | Reference compile ra + `convert` | FreeBook làm |
| --- | --- | --- | --- |
| `<n>` | chuỗi số Hán hoặc Ả Rập, kể cả `十百千万萬亿億`; sinh số Ả Rập | `([〇零一二两兩三四五六七八九十百千万萬亿億兆0-9]{min,max})`; `chineseNumber` cộng dồn section bằng BigInt (`:151-187`) | **Hỗ trợ** |
| `<y>` | đọc **từng chữ số**, **không nhận `十百千`**; dùng cho năm/mã số | **cùng char class với `<n>`** (`:249-251`), rồi map từng ký tự qua `digit` nên `十` giữ nguyên | **Hỗ trợ, theo header** — lệch reference (§4.2 #1) |
| `<L>` | **một** nhãn chương `章卷集节節幕回折` | `([章卷集节節幕回折]{min,max})`, không range ⇒ `{1,12}`; capture ≥ 2 ký tự trả nguyên văn | **Hỗ trợ, cố định `{1,1}`** — lệch reference (§4.2 #2) |
| `<hv>` | **một** ký tự Hán Việt | gộp chung nhóm từ điển: `{1,12}` + trả nguyên văn | **Hỗ trợ**: đúng 1 ký tự, render Hán-Việt qua `PhienAm` |
| `<ne>` `<pn>` `<vp>` | cụm trong từ điển Name / Pronoun / VietPhrase | `([\p{Script=Han}A-Za-z0-9]{min,max})` + cờ `approximate` (`:256-259`); `convert` **trả nguyên văn**, không tra từ điển | **Hỗ trợ, ràng buộc từ điển** (§7.1) — reference sai ở đây, xem §4.3 |
| `<w>`, `<a\|b>` | `<w>` = `<ne\|pn\|vp>`, thử trái→phải | như trên, không phân biệt loại | **Hỗ trợ**: thử lần lượt Name → Pronoun → VietPhrase, nhận kết quả đầu tiên khớp |

Không khai range ⇒ reference dùng `min=1, max=12` (`:238-242`); riêng `<L>`/`<hv>` thì mặc định đó **trái header**, nên FreeBook cố định `{1,1}`. Với token từ điển, range **không** phải cơ chế xác định biên — xem §4.3. Nhóm `(a|b)` và `(a|b)?` là **non-capture**, alternative được escape rồi nối bằng `|` (`:268-280`). Placeholder `{i}` trong RHS **chỉ đánh số token `<…>`**, group và literal không được đánh số. Hai câu cuối header ("mỗi rule phải có ít nhất một ký tự thường làm neo", "phải dùng mọi capture") đã là hard error ở §6. Mọi range trao ra ngoài (Reader/TTS) vẫn phải là UTF-16.

### 4.2 Ba điểm cố ý lệch reference (làm theo header)

| # | Header | Reference | FreeBook làm | Bằng chứng đo được |
| --- | --- | --- | --- | --- |
| 1 | `<y>` không nhận `十百千` | `<y>` dùng chung class với `<n>`, nhận cả `十百千万萬亿億兆` | class riêng `[〇零一二两兩三四五六七八九0-9]` (loại mọi ký tự bậc: `十百千万萬亿億兆`) | 6 rule dòng 131-136 file chuẩn dùng `十` làm **literal**: `十<y:1>级 = cấp 1{0}`, `<y:1>十级 = cấp {0}0`, `<y:1>十<y:1>级 = cấp {0}{1}`. Nếu `<y>` nuốt được `十` thì "十五级" khớp sai nhánh và `<y:1>十级` sinh match rác |
| 2 | `<L>` = **một** nhãn | `{1,12}`, capture ≥ 2 ký tự trả nguyên văn (rác) | `{1,1}` | `<L>` chỉ có 2 usage trong toàn bộ nguồn (chuẩn dòng 90, aio dòng 12), cả hai `第…<L>` một nhãn |
| 3 | engine **tự chặn** `<n>/<y>` nuốt một phần chuỗi số dài hơn | không có lookaround nào | lookaround **có điều kiện**, chi tiết ở §7 | 82 vị trí token trong file chuẩn + 49 trong aio có literal cùng lớp số dán sát token ⇒ bọc vô điều kiện là giết rule (§7) |

Câu cuối header "không tự thêm dấu phân cách số" **trùng** với reference (formatter xuất số trần, không có `toLocaleString`) — giữ nguyên, chỉ ghi lại thành yêu cầu nghiệm thu để không ai "cải tiến" thành `1.000`.

### 4.3 Vì sao token từ điển **không** giải quyết được bằng "lấy range lớn nhất"

Đây là câu hỏi tự nhiên: token không khai range thì cho nó `max` lớn nhất là xong. Nhưng "lấy range lớn nhất" **chính là** thứ reference đang làm (`{1,12}` khi không khai range) và đó là nguyên nhân lỗi, không phải cách sửa:

- Range chỉ giới hạn **độ dài**, không nói **cái gì** được nuốt. `<pn>` biên dịch thành `([\p{Script=Han}A-Za-z0-9]{1,12})` khớp *bất kỳ* 1-12 chữ Hán, không cần là đại từ.
- **15.069/17.278 rule (87%) trong `Rule_new.txt` có LHS bắt đầu bằng token**, tức không có gì chặn biên trái. Với `<pn>一人 = một mình {0}`, câu "众人皆知他一人" khớp từ vị trí 0, capture "众人皆知他" ⇒ ra "một mình 众人皆知他"; phần Hán đó vẫn được tokenizer dịch ở bước sau nên **không lộ chữ Hán**, chỉ ra một câu Việt sai thứ tự và sai nghĩa — lỗi im lặng, khó phát hiện hơn nhiều.
- Giảm `max` không cứu được: `{1,2}` vẫn capture "知他"; `{1,1}` thì giết đại từ 2-3 ký tự (`我们`, `他们`, `自己`) — mà đó là phần lớn từ điển Pronouns.
- Cái thật sự cần là **ràng buộc theo từ điển**: tại vị trí capture, chỉ nhận nếu chuỗi ở đó là một entry của từ điển tương ứng. Range vẫn dùng, nhưng chỉ để **cắt bớt** ứng viên trie (entry dài hơn `max` bị loại) — nó là điều kiện phụ, không phải điều kiện chính.
- Ràng buộc này regex **không** diễn tả được, nên nó quyết định kiến trúc matcher (§7.1) — và đó là lý do thật của việc "phân đợt" ở bản plan trước, chứ không phải chuyện cú pháp range. Vì `TrieDictionary` đã có sẵn `findAllPrefixMatches(text:startIndex:)` (`Sources/Models/Dictionaries/DoubleArrayTrie.swift:5, 164`) — đúng primitive cần cho backtracking — nên chi phí làm ngay từ đầu nhỏ hơn chi phí làm hai lần.

## 5. Ba thứ hai file rule đang dùng mà reference **không hỗ trợ**

`compile()` xử lý mọi ký tự không phải `<` hay `(` bằng đúng một dòng `out += escapeRe(pattern[i])` (`ruleEngine.ts:282`). Suy ra:

1. **`\` không phải escape** — nó thành literal backslash. `\[<n:1-6>\]…` (dòng 9) và `生命能量\+<n:1-8>` (dòng 1048) chỉ khớp khi văn bản thật có dấu `\`. Hai rule này **chết** trên reference.
2. **`<x:1-2>?` không phải optional token** — sau `>` con trỏ nhảy tới `?`, và `?` bị escape thành literal dấu hỏi. 6 rule dòng 30-35 (`%暴击`, `%命中`, `%闪避`, `%暴伤`, `%穿透`, `%格挡`) đòi văn bản có dấu `?`. **Chết.**
3. **Group lồng bị biên dịch sai mà không throw** — nhánh `(` dùng `indexOf(')')`, lấy dấu đóng **đầu tiên** (`:268-270`). `立(方(米|公尺)|米)?` ra `(?:方\(米|公尺)\|米\)\?`, đòi literal `|米)?`. 15 rule trong `rule-aio.txt`.

**Cả ba là bug của reference, không phải quy ước của DSL** — đọc rule thật thì ý người viết rõ ràng và hợp lý:

| Dòng aio | Rule | Ý rõ ràng |
| --- | --- | --- |
| 385 | `<n:1-6>( )?立(方(米\|公尺)\|米)?={0} mét khối` | group lồng: `立方米`, `立方公尺`, `立米`, hoặc `立` trơn |
| 405 | `<n:1-8>( )?(多\|余\|多(长\|高\|远\|長\|遠))公里=hơn {0} ki-lô-mét` | `多公里`, `余公里`, `多长公里`… |
| 30 | `<n:1-3>(点\|點\|.\|．\|,)?<y:1-2>?%暴(击\|擊)={0}{1}% bạo kích` | phần thập phân **có thể vắng**: "50%" và "50.5%" cùng khớp |
| 9 | `\[<n:1-6>\]( )?<vp:1-10>=Chương {0}: {1}` | escape `[` `]` để khớp tiêu đề `[12] 标题` |

Vì FreeBook **tự parse AST** chứ không mượn `compile()` của reference (§7.1), ba tính năng này đúng ra là **rẻ hơn** việc chặn chúng: group lồng là đệ quy tự nhiên của parser, `\x` là một nhánh trong vòng lặp ký tự, `<x>?` là cờ optional trên phần tử AST (capture vắng ⇒ `{i}` render chuỗi rỗng). Nên plan này **hỗ trợ cả ba**, và số dòng phải sửa trong `rule-aio.txt` tụt từ 27 xuống **2**.

Ba lệch còn lại so với reference (§4.2 + §4.3 + phần này) đều theo cùng một nguyên tắc: **lấy ý người viết rule làm chuẩn, không lấy lỗi cài đặt của reference làm chuẩn.** Đổi lại, FreeBook cho kết quả khác vbook-toolkit trên các input biên — cần chủ dự án xác nhận (§17 #4, #6).

## 6. Phân loại lỗi: hard error (chặn snapshot) vs warning (vẫn nạp)

Plan cũ đặt mọi bất thường thành hard error khiến cả file bị loại. Với màn hình quản lý ở §13 thì phân loại lại được, theo tiêu chí: **hard = engine có thể hiểu sai ý người viết; warning = rule chỉ vô hiệu, không làm sai rule khác.**

| Code | Loại | Số dòng trong `rule-aio.txt` | Lý do |
| --- | --- | --- | --- |
| `UNPARSEABLE_RULE_LINE` | **hard** | 0 | Dòng non-comment/non-blank không thuộc format nào. Reference bỏ im lặng (`parseRulesFromText:55-124`); ta siết để không nạp thiếu mà không ai biết |
| `EMPTY_PATTERN` | **hard** | 0 | |
| `UNKNOWN_TOKEN_NAME` | **hard** | 0 | Tên token ngoài `n y L ne pn vp hv w` và tổ hợp `<a\|b>` của chúng |
| `UNBALANCED_PARENS` | **hard** | 1 → dòng 916 `<n:1-2>( )?(阶(之\|以)上实力` thiếu `)` | Lỗi thật trong file nguồn |
| `INVALID_REF_INDEX` (`{i}` vượt số token) | **hard** | 0 | |
| `UNUSED_CAPTURE` | **hard** | 1 → dòng 668 (3 token, RHS chỉ dùng `{0}{1}`) | Header đòi "phải dùng mọi capture"; gần như chắc chắn là rule viết dở (so với dòng 667 `<n:1-3>天<n:1-3>…` thì 668 thiếu chữ `天`) |
| `NO_LITERAL_ANCHOR` | **hard** | 0 | Header đòi mỗi rule có ít nhất một literal làm neo; không có neo thì prefilter §8 cũng vô nghĩa |
| `DICT_TOKEN_WITHOUT_DICTIONARY` | **hard khi nạp** | 12 → dòng 9, 10, 11, 1206-1214 | Rule dùng `<vp>/<w>` mà từ điển tương ứng chưa nạp (Pronouns là optional, có thể nil). Đây là lỗi **trạng thái runtime**, không phải lỗi cú pháp: báo ở màn hình quản lý, rule bị vô hiệu chứ không loại cả file |
| `LITERAL_SPACE_IN_PATTERN` | warning | 0 (nhưng 166 ở `Rule_new.txt`, trong đó 161 rule `<n>`) | Space là literal bắt buộc, văn bản Trung hầu như không có ⇒ rule chết |
| `MULTIPLE_CONSECUTIVE_WILDCARDS` | warning | có (vd dòng 667, 668) | Port từ `ruleValidator.ts:406-416`. Không chặn: 19 rule trong file chuẩn (dòng 90, 490-500) dùng token dán nhau **có chủ ý** |
| `DUPLICATE_PATTERN` | warning | 3 | **Không dedupe**: dòng sớm hơn thắng ở runtime là hành vi có chủ ý |
| `WEAK_ANCHOR` (literal chỉ gồm ký tự cực phổ biến `的了是不存在在上下个個`) | warning | thống kê khi chạy | Chỉ cảnh báo, không chặn |

So với bản trước: `UNSUPPORTED_TOKEN` và `UNSUPPORTED_NESTED_GROUP` **biến mất** (engine hỗ trợ), `LITERAL_BACKSLASH`/`LITERAL_QUESTION_MARK` biến mất (thành cú pháp thật). Số dòng chặn `rule-aio.txt` tụt từ **27** xuống **2** (916 thiếu `)`, 668 thiếu capture) — cả hai đều là lỗi thật của file nguồn, sửa 2 dòng là nạp được toàn bộ 1.175 rule.

**Trình tự bắt buộc**: split `\r?\n` → parse giữ `sourceLine` gốc → validate toàn bộ → compile thật từng rule → nếu có **bất kỳ** hard error thì **không** swap snapshot (giữ snapshot trước, hoặc no-rule nếu chưa có) → nếu chỉ warning thì compile và swap atomically. Không nạp một phần file lỗi. Không dùng `validCount = tổng - hard` làm số rule hợp lệ (một rule có thể có nhiều issue); quyết định theo có/không hard error.

## 7. Matcher, priority và chọn match

### 7.1 Matcher tự viết, **không** dùng `NSRegularExpression`

Reference biên dịch mỗi rule thành một regex rồi chạy global. FreeBook không đi đường đó, vì bốn yêu cầu ở trên đều **không** diễn tả được bằng regex hoặc chỉ diễn tả được rất vụng:

| Yêu cầu | Bằng regex | Bằng AST-walk |
| --- | --- | --- |
| `<pn>/<ne>/<vp>/<w>` ràng buộc từ điển (§4.3) | **không thể** — cần tra trie tại vị trí capture | một lời gọi `findAllPrefixMatches`, thử từ dài đến ngắn |
| Boundary guard có điều kiện cho `<n>/<y>` (§4.2 #3) | lookbehind/lookahead sinh động theo phần tử AST liền kề | so một ký tự ở input, không cần lookaround |
| `<L>`/`<hv>` đúng 1 ký tự, `<y>` bỏ ký tự bậc | được, nhưng phải sinh char class riêng | tham số của phần tử AST |
| Group lồng + `\` escape + `<x>?` (§5) | được, nhưng phải escape đúng và dễ sai | cấu trúc dữ liệu, không escape gì |

Thiết kế matcher:

- AST tuyến tính, mỗi phần tử là `literal(String)` / `charClassToken(class, min, max, kind)` / `dictToken(dicts, min, max)` / `group(alternatives, optional)`, mỗi phần tử có cờ `optional`.
- `matchAt(elementIndex, position) -> [end]` đệ quy có backtracking: token char-class thử độ dài **dài → ngắn** (greedy như regex), token từ điển thử ứng viên trie **dài → ngắn**, group thử alternative theo thứ tự khai báo rồi mới thử nhánh vắng.
- **Chặn nổ**: cap số bước backtracking cho mỗi (rule, vị trí bắt đầu) — vượt cap thì coi như không khớp và ghi warning `RULE_TOO_COMPLEX` ở màn hình quản lý. Pattern thật rất ngắn (≤ 8 phần tử, `max ≤ 12`) nên cap không bao giờ chạm với dữ liệu hiện có; nó chỉ để một rule bệnh lý không treo Reader.
- Mọi vị trí và độ dài đếm theo **UTF-16** để range trao ra ngoài dùng được ngay (§11).
- Lợi thế phụ: không tạo 1.175 (hoặc 17.278) object `NSRegularExpression`, không tốn bridge Swift↔ICU cho mỗi lần scan, và kiểm soát được chính xác chi phí.

### 7.2 Priority — giữ nguyên metric của reference

`executeRules` (`ruleEngine.ts:293-358`) gom mọi candidate rồi sort; FreeBook giữ **đúng** thứ tự so sánh này, chỉ đổi cách sinh candidate:

1. `index` nhỏ hơn (offset UTF-16 bắt đầu match).
2. `literalLength` lớn hơn — tổng literal ngoài token; group **không** optional đóng góp độ dài alternative dài nhất, group optional đóng góp 0 (`:277`).
3. `wildcardCapacity` nhỏ hơn — tổng `max` của mọi token (`:263`). Token từ điển tính `max` là giới hạn khai báo, hoặc **12 như reference** khi không khai (1.3.269: `TrieDictionary` chỉ expose `wordCount`, không expose độ dài entry dài nhất; đây là metric tiebreak nên không đổi điều kiện khớp).
4. Full match dài hơn.
5. `sourceLine` sớm hơn.

Chọn greedy non-overlap: `cursor = 0`; lấy candidate đầu tiên có `start >= cursor`; chọn nó; `cursor = start + max(1, matchLength)`; loại mọi candidate `start < cursor`, kể cả candidate nằm trong hoặc phủ một phần match đã chọn.

### 7.3 Ràng buộc giữ nguyên theo reference

- **Không cascade**: rule chỉ chạy một pass trên input Trung. Chuỗi Việt vừa render **không** được đưa lại cho rule.
- **Không exhaustive match**: mỗi rule chỉ phát match trái-sang-phải, không thử match ngắn hơn hay điểm bắt đầu overlap khác của chính nó.
- **Không `trim()` input**. Reference trim vì nó là UI tester; production trim là lệch range.
- **Không tự thêm dấu phân cách số**: `1000000`, không phải `1.000.000` (header dòng 19, reference cũng vậy).

### 7.4 Boundary guard có điều kiện

Theo header dòng 19 ("engine tự chặn `<n>/<y>` nuốt một phần chuỗi số dài hơn") — reference không có, FreeBook có:

- Với mỗi token số, xét phần tử AST **liền trước** và **liền sau** nó. Nếu phía đó là literal thuộc lớp số của token, hoặc là group mà **mọi** alternative bắt đầu (tương ứng kết thúc) bằng ký tự thuộc lớp số, hoặc là một token số khác ⇒ **không** guard ở phía đó, vì chính pattern đang nối tiếp chuỗi số. Ngược lại ⇒ guard: so ký tự liền kề trong input, thuộc lớp số thì loại match (AST-walk nên không cần lookaround regex).
- Group **mixed** (một số alternative bắt đầu bằng ký tự lớp số, một số không) ⇒ bỏ guard ở phía đó, chọn hướng bảo toàn rule thay vì hướng siết.
- Không được guard vô điều kiện: đo được **82** vị trí token trong file chuẩn v21 và **49** trong `rule-aio.txt` có literal cùng lớp số dán sát token — `<n:1-6>万 = {0}0 nghìn`, `<n:1-8>亿 = {0}00 triệu`, `十<y:1>级 = cấp 1{0}`, `<n:1-3>十<n:1-3>(万|萬) = {0}{1}0 nghìn`, `<n:1>十(万|萬)<n:1>千`. Guard vô điều kiện là giết đúng những rule này.
- 19 rule trong file chuẩn có **hai token dán nhau** (`第<n:1-6><L>` dòng 90, `十<n:1-8><y:1>米多长` dòng 490-500). Chúng dựa vào backtracking để chia chuỗi, nên guard chỉ đặt ở **hai đầu ngoài** của cả cụm, không đặt giữa hai token.
- Vì đây là lệch có chủ ý, phải đi kèm ví dụ nghiệm thu (§16) và ghi vào version bộ rule.

Về cài đặt: `executeRules` gọi `matches.filter(...)` trong vòng `while` (`ruleEngine.ts:345-355`) — bậc hai. Bản iOS phải sort một lần rồi quét một pass tuyến tính, kết quả giống hệt.

## 8. Prefilter theo literal bắt buộc — **điều kiện khả thi, không phải tối ưu**

Reference compile lại toàn bộ rule ở mỗi lần test và chạy 1 regex/rule/chuỗi. Với 1.175 rule × mỗi dòng chương (một chương ~200 dòng ⇒ ~235.000 lần scan) là không dùng được trên máy thật; cache md5 của `translateText` chỉ đỡ lần đọc lại. Với `Rule_new.txt` 17.278 rule thì vô phương.

Thiết kế bắt buộc:

1. Compile **một lần** ngoài MainActor khi nạp snapshot, không compile theo từng lần dịch.
2. Từ AST, mỗi rule khai một **required literal**: chuỗi literal liên tục **dài nhất** nằm ngoài mọi group optional và ngoài mọi token. Nếu AST không chứng minh được literal nào bắt buộc thì rule vào danh sách "always try".
3. Index required literal bằng Aho-Corasick (hoặc trie ký tự đầu + xác nhận substring). Mỗi chuỗi đầu vào: quét một pass để lấy tập rule ứng viên, chỉ chạy matcher cho tập đó cộng danh sách "always try". Thêm một mức nữa: với rule đã trong tập ứng viên, chỉ thử **các vị trí bắt đầu suy ra từ vị trí literal** (offset literal trong pattern trừ tổng `max` của token đứng trước nó), không thử mọi vị trí trong dòng.
4. Chứng minh không bỏ sót: rule chỉ bị loại khi required literal **không xuất hiện** trong input; literal đó là điều kiện cần của mọi match nên loại là an toàn. Phải có ví dụ nghiệm thu so sánh "có prefilter" vs "brute force toàn bộ rule" trên cùng đoạn văn, kết quả phải trùng từng ký tự.

Dữ liệu cho thấy prefilter rất hiệu quả: **0/1.177** rule của `rule-aio.txt` và **0/17.278** rule của `Rule_new.txt` là không có literal. Phân bố literal liên tục dài nhất của `Rule_new.txt`: 1 ký tự **622** rule, 2 ký tự 4.531, 3 ký tự 6.657, 4 ký tự 4.173, 5 ký tự 957, 6 ký tự 138, 7 ký tự 127, 8 ký tự 73 — nghĩa là 96% rule có neo ≥ 2 ký tự, tập ứng viên mỗi dòng rất nhỏ. `rule-aio.txt` có 319 rule neo 1 ký tự.

## 9. File mới và ranh giới tầng

`Scripts/check_architecture.py` enforce: file mới ≤ **400 dòng vật lý**, đúng **1 primary type**/file, `Sources/Services/**` **không** `import SwiftUI` và **không** gọi `ToastManager.shared`, `Sources/Views/**` không mutate SwiftData. Chia file theo đó:

| File | Primary type | Trách nhiệm |
| --- | --- | --- |
| `Sources/Services/Translation/Engine/QuickTranslationRuleParser.swift` | `QuickTranslationRuleParser` | text → AST + issue list (§6). Split `\r?\n`, hỗ trợ `pattern=replacement`, `"pattern"="replacement"`, tab; bỏ dòng `#`, `//`, `===` |
| `…/QuickTranslationRuleCompiler.swift` | `QuickTranslationRuleCompiler` | AST đã validate → dạng thi hành (char class theo `kind`, tham chiếu từ điển, cờ guard hai đầu mỗi token số) + `literalLength`, `wildcardCapacity`, `requiredLiteral`, vị trí literal để suy ra start position |
| `…/QuickTranslationRuleMatcher.swift` | `QuickTranslationRuleMatcher` | AST-walk backtracking (§7.1) + cap số bước; gom candidate + sort + greedy non-overlap (§7.2, §8) |
| `…/QuickTranslationDictionaryToken.swift` | `QuickTranslationDictionaryToken` | ràng buộc `<ne>/<pn>/<vp>/<w>/<hv>` theo `TrieDictionary.findAllPrefixMatches`; đọc trạng thái nạp từ `TranslationManager` và tôn trọng `isTranslationPronounsEnabled` |
| `…/QuickTranslationRuleEngine.swift` | `QuickTranslationRuleEngine` | `rewrite(_:) -> QuickTranslationRewriteResult` (text + atom/trace) |
| `…/QuickTranslationNumberFormatter.swift` | `QuickTranslationNumberFormatter` | `<n>`/`<y>`/`<L>`; số Hán phải dùng số nguyên rộng như BigInt của reference |
| `…/QuickTranslationRuleSnapshot.swift` | `QuickTranslationRuleSnapshot` | struct bất biến: `generation`, `sourceHash`, `ruleCount`, `warnings`, compiled rules, `requiredLiteralIndex` |
| `…/QuickTranslationRuleStore.swift` | `QuickTranslationRuleStore` | `ObservableObject` singleton (Combine, **không** SwiftUI): nạp resource/override, validate-then-swap atomically, đọc công tắc, phát generation |
| `Sources/Services/Translation/Extensions/TranslateUtils+QuickTranslationRules.swift` | extension | facade nội bộ + context flag + metadata cache |
| `Sources/Views/Settings/Translation/QuickTranslationRulesView.swift` | `QuickTranslationRulesView` | màn hình quản lý (§13) |
| `Sources/Views/Settings/Translation/QuickTranslationRuleIssueSheet.swift` | `QuickTranslationRuleIssueSheet` | danh sách lỗi/cảnh báo theo dòng |

Nếu `TranslateUtils.swift` (1.041 dòng, đã trong baseline legacy — **chỉ được giảm**) phình thêm thì đẩy phần mới sang file `TranslateUtils+QuickTranslationRules.swift`.

## 10. Chèn rewrite vào pipeline

```text
input sau textForTranslation (nếu bật Phồn → Giản)
  → QuickTranslationRuleEngine.rewrite(input)     ← MỚI, chỉ khi context nội bộ + công tắc bật
  → punctuationMapping (giữ nguyên)
  → VietPhraseTokenizer.tokenize (giữ nguyên)
  → lookup 8 tầng từ điển (giữ nguyên)
  → postProcessText (giữ nguyên)
```

Phải trước `punctuationMapping` vì LHS có literal `．`, `.`, `,` và dấu ngoặc (vd dòng 30-35 dùng `(点|點|.|．|,)?`); normalize punctuation trước sẽ đổi literal và chèn space làm match sai. Đây vẫn thoả yêu cầu "trước tokenize".

`rewrite` append text nguyên vẹn từ cursor tới match, append template đã render, tiếp tục sau match. Tuyệt đối không đưa DSL raw cho `NSRegularExpression`.

**Context loại trừ Qt bridge**: thread flag tường minh `applyingQuickTranslationRules: Bool` qua `translateMeta`, `translateContent`, `translateContentWithMapping`, `translateChapterTitle`, `translateChapterTitleWithMapping`, `translateText`, `performTranslation`. Mặc định `true`; `JSExecutor` (Qt bridge) truyền explicit `false`. Không suy context bằng `Thread.current` hay biến global. Flag phải nằm trong cache key để bản dịch bridge không lẫn bản dịch app.

## 11. Cache, generation và span/trace

- Rule snapshot `generation` **và** trạng thái công tắc phải vào cache key của `translateText` (`:394`) và vào `translationGenerationToken(for:)` (`:16-23`), để snapshot Reader/TTS cũ bị loại đúng lúc.
- Reload rule (nhập file, đổi công tắc, restore backup) ⇒ gọi `TranslateUtils.clearCache()` (`:960-968`, tự tăng `globalGeneration` + `settingsGeneration` và dọn `translationCache`) và phát **đúng một** `TranslationManager.notifyDictionariesDidUpdate()`. Không tạo đường refresh Reader thứ hai.
- Compile snapshot **trước** khi `TranslationManager.loadAllDictionaries()` kết thúc để lần dịch đầu không chạy vào snapshot chưa sẵn sàng. Compile fail thì Quick Translate cũ vẫn phải hoạt động bình thường.
- `AppLogger` chỉ ghi metadata: version/hash rút gọn, số rule, số warning, `sourceLine` lỗi. **Không** log nội dung chương, không log full payload.

**Span/trace** — đây là phần dễ hỏng nhất, vì rule làm output đổi độ dài và đảo thứ tự:

- `rewrite` trả về các atom đã chọn kèm range UTF-16 **của nguồn** và range UTF-16 **của output**, cộng range output của từng `{i}`.
- Pipeline dựng `TranslationSpan` cùng lúc với text cuối. Atom fallback (phần không match rule) dùng tokenization/dictionary hiện hữu rồi rebase về range nguồn; atom rule map tối thiểu về **toàn bộ** match nguồn; capture có mapping rõ ràng thì được span hẹp hơn.
- **Không** gọi lại `buildTranslationSpans(original:translated:)` (`:971-1009`) sau khi đã rewrite: nó dò token của chuỗi *gốc* trong chuỗi *đã dịch* (`:982-1006`), nên với vùng đã rewrite nó chỉ `continue` và bỏ span — Reader mất tra từ điển đúng ở chính những vùng rule vừa xử lý.
- `getTranslationTokens` và `snapToToken` phải dùng cùng atomization/trace để selection trên một rule snap về nguồn của rule.
- Atom nào không chứng minh được mapping thì trả span rỗng **chỉ cho atom đó**, không bịa range theo tỉ lệ, không xoá trace của atom khác.
- Entry cache nội bộ đổi từ `String` thành kết quả pipeline (text + trace + generation) để không phải chạy engine lần hai chỉ để biết span còn hợp lệ.

## 12. Công tắc bật/tắt trong Settings

| Hạng mục | Quyết định |
| --- | --- |
| Key | `isQuickTranslateRuleEnabled` |
| Mặc định | **bật** |
| Vị trí UI | `SettingsView.swift`, section "Dịch Thuật Quick Translate", trong nhánh `if isTranslationEnabled`, đặt trên hai toggle Pronouns/Luật nhân |
| Nhãn | "Áp dụng rule dịch" + caption "Thay cụm số, đơn vị và mẫu câu theo bộ rule trước khi tách từ. Tắt nếu muốn dịch thuần từ điển." |
| Khi tắt | `rewrite` bị bỏ hoàn toàn; punctuation/tokenizer/dictionary chạy y như hiện tại |
| Khi đổi | `.onChange` → `TranslateUtils.clearCache()` (đúng khuôn ba toggle hiện có ở `SettingsView.swift:36-67`) và bump generation của store |

**Bẫy phải xử lý**: repo **không** có `UserDefaults.register(defaults:)` ở đâu cả (đã grep toàn `Sources/`) — giá trị mặc định chỉ nằm ở tham số `@AppStorage` trong View. Vì vậy `UserDefaults.standard.bool(forKey:)` trong Service trả `false` khi key chưa tồn tại, tức "mặc định bật" sẽ **bị hiểu thành tắt** ở tầng Service cho tới khi người dùng bấm toggle. Store phải đọc bằng:

```swift
// nil = chưa từng set ⇒ mặc định bật
let isEnabled = UserDefaults.standard.object(forKey: "isQuickTranslateRuleEnabled") as? Bool ?? true
```

và `@AppStorage("isQuickTranslateRuleEnabled") private var … = true` ở View. Hai chỗ phải cùng mặc định `true`, nếu không toggle sẽ nhảy trạng thái ở lần mở Settings đầu tiên.

Công tắc **phụ thuộc** `isTranslationEnabled`: tắt Quick Translate thì cả pipeline không chạy, rule cũng không. Không thêm công tắc riêng cho từng nhóm rule.

## 13. Màn hình quản lý rule dịch

Đi theo tiền lệ đang có trong repo: `JunkFilterManager` + `JunkFilterManagementView` (service giữ file trong `applicationSupportDirectory/translate/`, View chỉ gọi hàm và đọc `@Published`) và `TOCRulesConfigView`. Link đặt trong `SettingsView.swift:40-48`, cạnh "Quản lý quy tắc TOC" và "Quản lý lọc rác":

```swift
NavigationLink(destination: QuickTranslationRulesView()) {
    Label("Quản lý rule dịch", systemImage: "text.badge.checkmark")
}
.disabled(!importingTypes.isEmpty)
```

**Persistence** *(đã thực thi khác: chỉ có **một** file `applicationSupportDirectory/translate/QuickTranslateRules.txt`, không có tầng bundled để fallback)*: nguồn là file đó. Nhập file = parse + validate + compile **toàn bộ vào staging**, chỉ khi không có hard error mới `Data.write(to:options:.atomic)` rồi swap snapshot. Có hard error thì file cũ giữ nguyên và trả về danh sách issue — đây chính là lý do chính sách strict ở §6 chấp nhận được: strict chỉ công bằng khi UI chỉ đúng dòng lỗi.

**Nội dung màn hình**:

1. **Thẻ trạng thái**: đang dùng "Bộ mặc định trong app" hay "File đã nhập"; số rule hoạt động; số cảnh báo; `sourceHash` rút gọn; thời điểm nạp. Nếu công tắc §12 đang tắt thì hiện banner "Rule đang tắt trong Cài đặt" để không ai tưởng màn hình này hỏng.
2. **Nhập file** `.txt` bằng `fileImporter`. Thành công → toast + số rule. Thất bại → `QuickTranslationRuleIssueSheet` liệt kê `dòng — code — message — nguyên văn dòng`, nhóm hard/warning, có nút copy toàn bộ để sửa ngoài app.
3. **Tải bộ rule mặc định** từ HuggingFace (nút chính khi máy chưa có bộ rule) và **Xoá bộ rule khỏi máy** có `confirmationDialog` — thay cho "về bundled" vì không còn tầng bundled.
4. **Xuất file**: ghi ra `Documents/Exports/` như đường xuất TXT hiện hữu, để người dùng lấy bộ đang chạy ra sửa.
5. **Danh sách rule**: `LazyVStack` + search + phân trang (bước 200 dòng). **Không** `List` toàn bộ — 17k dòng render một lượt là treo UI. Mỗi dòng hiện `sourceLine`, LHS, RHS, badge cảnh báo.
6. **Ô thử nhanh**: dán một câu Trung → hiện text sau rewrite, kèm bảng "rule nào khớp ở offset nào, capture ra gì". Port `makeExample`/`matchRules` của reference (`ruleEngine.ts:360-362`, `:445-498`). Đây là công cụ debug chính khi rule không nổ như mong đợi, rẻ và không cần dữ liệu thật.

**Ranh giới tầng**: mọi ghi file nằm ở `QuickTranslationRuleStore` (Service, không `import SwiftUI`, không `ToastManager`); View gọi hàm store rồi tự phát toast (View được phép). Không có `@Model` nào liên quan nên không có mutation SwiftData.

Bật/tắt từng rule là **tuỳ chọn, không bắt buộc ở bản đầu**. Nếu làm thì lưu danh sách `sourceLine` bị tắt trong `translate/quick_translate_rules_disabled.json`, tuyệt đối không ghi lại file rule nguồn (ghi lại là mất comment và mất thứ tự dòng — mà thứ tự dòng là tiebreak priority).

## 14. Backup / restore

Thêm vào `BackupPaths.swift` theo đúng khuôn `tocRules`/`searchEngines` (`:61-66`):

```swift
public static let quickTranslateRules = "config/QuickTranslateRules.txt"
public static let quickTranslateRulesFileName = "QuickTranslateRules.txt"
```

- Đi cùng công tắc `restoreSettings` như khối cài đặt, **không** thêm case `BackupScope` mới — comment tại `BackupPaths.swift:55-58` đã nêu lý do: `BackupScope` là `Codable` và rawValue được ghi vào `manifest.scopes`, thêm case làm bản app cũ decode manifest lỗi.
- Công tắc `isQuickTranslateRuleEnabled` nằm trong `UserDefaults` nên đã theo `settings/user_defaults.plist` sẵn, không cần làm gì thêm.
- Sau restore: `BackupRestoreWorker` đã gọi `notifyDictionariesDidUpdate()` (`:273`); thêm một lần nạp lại store trước lời gọi đó để snapshot và thông báo đi cùng nhau.
- Backup file rule trên máy. Vì không còn bundled resource, đây là dữ liệu người dùng thật sự — mất là mất bộ rule cho tới khi tải lại.

## 15. `Rule_new.txt`: engine đã đủ, điều kiện bật nằm ở chỗ khác

Engine ở §7 nhập được `Rule_new.txt` ngay, không cần "đợt 2" về mặt năng lực. Nhưng **bật** nó phụ thuộc bốn thứ ngoài engine, và cả bốn nên chốt trước khi nạp:

1. **Từ điển Pronouns là optional.** `TranslationManager` nạp `Pronouns.dat`/`Pronouns.txt` ở nhánh "Load Pronouns (Optional)" (`TranslationManager.swift:344-365`) và `pronounsDict` có thể là `nil`. Nếu nil thì 16.941 rule `<pn>` vô hiệu — engine phải báo `DICT_TOKEN_WITHOUT_DICTIONARY` ở màn hình quản lý, không âm thầm bỏ qua.
2. ~~**Công tắc đại từ mặc định TẮT.**~~ *(đã bỏ ở 1.3.269: rule `<pn>` không đọc công tắc này nữa — xem §17 #5b.)* `isTranslationPronounsEnabled` khai `= false` ở cả `ReaderView.swift:157` và `SettingsView.swift:9`, và Service đọc bằng `UserDefaults.standard.bool(forKey:)` (`TranslateUtils.swift:410`, `VietPhraseTokenizer.swift:18`) nên key chưa set ⇒ `false`. Với người dùng mặc định, toàn bộ `Rule_new.txt` **không chạy**. Cần quyết định: rule `<pn>` đi theo công tắc này (nhất quán với tra từ điển) hay có công tắc riêng. Mặc định plan chọn **đi theo công tắc hiện có**, và trạng thái công tắc phải vào cache key.
3. **161/337 rule `<n>` trong chính file đó đã chết.** Đo được: 166 rule có literal U+0020 trong LHS (198 lần xuất hiện), trong đó **161 là rule `<n>`** (`<n> 丈余长`, `<n> 世纪`, …) và chỉ 5 là rule `<pn>` (vd dòng 4 `<pn> 们`). Văn bản Trung không có space nên chúng không bao giờ khớp. Đây là lỗi sinh file — cần xác nhận rồi sửa nguồn, không phải việc engine tự đoán và bỏ space.
4. **Chồng lấn với từ điển 8 tầng đang chạy.** `<pn>一半 = một nửa của {0}` cạnh tranh trực tiếp với đường tokenizer + LuatNhan. Rule thắng thì áp thứ tự từ của rule; điều đó là mục đích, nhưng ở quy mô 16.941 rule thì phải đọc thử vài chương thật trước khi bật mặc định.

Chi tiết cài đặt token từ điển (áp cho cả `rule-aio.txt` và `Rule_new.txt`):

- Tại vị trí capture, lấy `findAllPrefixMatches(text:startIndex:)` của từ điển tương ứng, thử ứng viên **dài → ngắn**, loại ứng viên dài hơn `max` hoặc ngắn hơn `min` khi rule có khai range. Không entry nào khớp ⇒ rule không match tại vị trí đó. Không dùng `findLongestMatch` một mình: nếu entry dài nhất làm phần literal sau đó không khớp thì vẫn phải thử entry ngắn hơn.
- `{i}` chèn **nghĩa Việt** lấy từ trie, không giữ chữ Hán — rule quy định thứ tự từ trong câu Việt; để chữ Hán lại cho tokenizer dịch sau sẽ ra thứ tự sai.
- `<w>` thử Name → Pronoun → VietPhrase theo thứ tự khai báo, nhận kết quả đầu tiên khớp. `<hv>` đúng 1 ký tự, render Hán-Việt.
- 12 dòng token từ điển trong `rule-aio.txt` (9, 10, 11, 1206-1214) **có** khai range (`<vp:1-10>`, `<w:1-6>`) nên phần giới hạn độ dài vẫn có tác dụng ở đó.

## 16. Nghiệm thu thủ công

Không dùng `Tests/` (theo `CLAUDE.md`: coi như không tồn tại). Xác minh bằng đọc code + build trên macOS + hai script gate + kịch bản tay:

1. `python Scripts/check_architecture.py` — trước và sau. Baseline hiện tại **14 violation**; chỉ chịu trách nhiệm cho violation mới. Không nới `architecture_allowlist.json`.
2. `python Docs/CodeGraph/validate_links.py --explain` sau khi thêm file Swift mới (thêm file ⇒ doc `staleOn: structure` chắc chắn stale).
3. `xcodegen generate` (bắt buộc vì có file Swift mới **và** resource mới), rồi `xcodebuild build`.
4. Nhập `rule-aio.txt` **chưa sửa** → phải bị từ chối, sheet liệt kê đúng **2** dòng hard error (916 thiếu `)`, 668 thiếu capture), bộ rule đang chạy **không đổi**.
5. Nhập bản đã sửa 2 dòng → nạp 1.175 rule; 12 dòng token từ điển hiện `DICT_TOKEN_WITHOUT_DICTIONARY` nếu Names/VietPhrase/Pronouns chưa nạp, và chạy được khi đã nạp; cảnh báo còn lại đúng số (duplicate, wildcard liền kề, weak anchor).
6. Nhập `Rule_new.txt` → nạp được, không crash, không treo dù file 690 KB; màn hình quản lý cảnh báo **166** dòng literal space và trạng thái công tắc đại từ đang tắt (§15).
7. Bốn rule mà reference biên dịch sai (§5) phải chạy đúng: `500立方米` → "500 mét khối" (group lồng, aio dòng 385), `3多公里` → "hơn 3 ki-lô-mét" (dòng 405), `50%暴击` **và** `50.5%暴击` cùng khớp dòng 30 (token optional), `[12] 标题` khớp dòng 9 (escape `\[`).
8. Đọc một chương có `第一章`, `100平方米`, `3天2小时`, `50%暴击` → so text trước/sau khi tắt công tắc §12; chỉ vùng rule khớp được đổi.
9. Tắt/bật công tắc giữa lúc Reader đang mở → text refresh đúng một lần, không nhân đôi refresh, TTS đang phát không đứt tiếng.
10. Bôi chọn một cụm nằm **trong** vùng rule đã rewrite → tra từ điển phải nhảy đúng chữ Hán nguồn (kiểm tra span/trace §11).
11. Bật TTS trên chương đã rewrite → highlight khớp đúng dòng và chunk (`TTSParagraph.range` là offset UTF-16 trên chuỗi đang hiển thị, tương đối theo dòng cha).
12. Đo thời gian dịch một chương ~5.000 chữ, có prefilter vs brute force: kết quả text phải **trùng từng ký tự**, thời gian phải chấp nhận được trên máy thật. Đo lại với `Rule_new.txt` đã nạp (17.278 rule) để biết giới hạn thật.
13. Token từ điển: `守在他四周` khớp aio dòng 1206 (`<w:1-6>` = 他 qua Pronouns) → "canh giữ xung quanh hắn"; chuỗi không phải entry từ điển ở vị trí đó thì rule **không** khớp (không được nuốt bừa 1-6 chữ Hán như reference).
14. Backup → xoá app → restore → override rule và công tắc trở lại đúng như trước.
15. Bóc tách truyện qua extension (Qt bridge) → xác nhận rule **không** áp vào đường bridge.
16. Ba điểm lệch reference ở §4.2, mỗi điểm một ví dụ cụ thể:
    - `<y>` không nhận `十`: "十五级" → "cấp 15" (rule dòng 131 `十<y:1>级`), và "五十级" → "cấp 50" (rule dòng 133 `<y:1>十级`). Không được ra "cấp 十5" hay khớp chồng.
    - `<L>` đúng 1 ký tự: "第一章" → "Chương 1"; chuỗi bệnh lý "第一章卷" **không** được để `<L>` nuốt "章卷".
    - Boundary guard: "三百五十米" **không** được khớp `<n:1-3>米` ở "五十米" bỏ sót "三百"; nhưng "三万" vẫn phải khớp `<n:1-8>万` (rule aio dòng 45) và "十五级" vẫn phải khớp dòng 131 — tức guard không được giết 82 + 49 vị trí đã đo.
17. Số ra không có dấu phân cách: "一百万" → `1000000`, không phải `1.000.000`.

## 17. Điểm cần chủ dự án chốt

| # | Vấn đề | Mặc định plan này chọn |
| --- | --- | --- |
| 1 | 2 dòng hard error trong `rule-aio.txt` (916, 668) sửa ở đâu | Sửa trong **file nguồn** rồi nhập lại; engine không tự bỏ qua dòng lỗi. Dòng 668 gần như chắc là thiếu chữ `天` so với dòng 667 — cần người viết rule xác nhận, không tự đoán |
| 2 | Nguồn nào thành bộ mặc định | **Đã chốt khác (1.3.269)**: không bundled vào app. Chủ dự án upload `QuickTranslateRules.txt` lên `huggingface.co/datasets/raikiri1498/vietpharse` (cạnh `vietpharse.txt`/`phienam.txt`), app có nút tải. Nội dung đề xuất vẫn là **file chuẩn v21** (633 rule, LF, nhập được ngay); `rule-aio.txt` (1.175 rule sau khi sửa 2 dòng) giàu hơn và cũng dùng được — đổi nội dung trên HuggingFace là đủ, không cần build lại app |
| 3 | Mặc định công tắc | **Bật**. Nếu muốn an toàn hơn (không đổi hành vi khi cập nhật app) thì đổi thành tắt — chỉ cần đổi 2 chỗ ở §12 |
| 4 | Ba điểm lệch reference ở §4.2 (`<y>` bỏ `十百千`, `<L>` = 1 ký tự, boundary guard có điều kiện) | **Làm theo header file rule**, không giữ parity — vì header là hợp đồng người viết rule dựa vào, và có bằng chứng rule thật (dòng 131-136, 90) chỉ đúng khi làm theo header. Cần chủ dự án xác nhận vì nó khiến FreeBook cho kết quả khác vbook-toolkit trên vài input biên |
| 4b | `<y>` có bỏ luôn `万萬亿億兆` không? Header chỉ nói "không nhận `十百千`" | **Bỏ hết ký tự bậc** (`十百千万萬亿億兆`), vì đọc từng chữ số thì không ký tự bậc nào có nghĩa. Đo được: không rule nào trong 3 file cần `<y>` nuốt `万` (rule dòng 496-500 đặt `万` làm literal ngoài token), nên lựa chọn này không đổi kết quả rule hiện có |
| 4c | Phần parity còn giữ | `chineseNumber` cộng dồn section kiểu reference ⇒ `一万亿` = `100010000` (không phải `1000000000000`); không cascade; không exhaustive match; không `trim()`; không dấu phân cách số. Muốn đổi là việc riêng, cần ví dụ regression và tăng version rule |
| 5 | `translateChapterTitle` đã có formatter riêng (`TranslateUtils.swift:290-380`) — rule chạy trước hay sau | **Đã thực thi khác mặc định của plan (1.3.269)**: formatter giữ chủ quyền tiền tố `第<n><L>`, rule chỉ áp cho phần còn lại của tiêu đề (qua `translateMeta` bên trong). Lý do: rule `第<n:1-6><L> = {1} {0}` cho "Chương 1 mở đầu", còn formatter cho "Chương 1: Mở đầu" (có `: ` và bảng `chapterUnitMap`) — chạy rule trước là đổi **mọi** tiêu đề chương ở Kệ/Mục lục/Reader. Muốn theo mặc định cũ thì dời lời gọi `rewrite` lên đầu `translateChapterTitle`, đúng một chỗ sửa |
| 5b | Rule `<pn>` đi theo công tắc `isTranslationPronounsEnabled` (mặc định **tắt**) hay có công tắc riêng | **Đã chốt khác (1.3.269)**: rule `<pn>` **không** phụ thuộc công tắc đó. Công tắc là của đường tra từ điển đại từ theo token ở tokenizer; `<pn>` trong rule là ràng buộc của rule người dùng chủ động viết, im lặng không nổ vì công tắc ở màn khác là hành vi khó hiểu. Hệ quả: `Rule_new.txt` chạy ngay khi nạp nếu máy có `Pronouns` — rủi ro chuyển sang phần chồng lấn với 8 tầng từ điển (§15 mục 4) |
| 6 | Nạp `Rule_new.txt` (17.278 rule) ngay hay chờ | Engine đủ năng lực nên **không còn là việc kỹ thuật**; chờ vì ba lý do dữ liệu: 161 rule `<n>` chết vì literal space, công tắc đại từ mặc định tắt, và cần đọc thử chương thật để đánh giá chồng lấn với từ điển 8 tầng (§15) |

## 18. CodeGraph và bàn giao khi thực thi

Patch này thêm file Swift mới ⇒ workflow bắt buộc, không được bỏ bước nào:

1. `xcodegen generate` (file Swift mới + resource mới).
2. `python Docs/CodeGraph/validate_links.py --explain` để biết doc nào stale. Dự kiến chạm: `00_index` và `02_file_graph` (tập file đổi), `11_subsystems` (phân hệ Dịch thuật + màn hình Settings), `04_call_graph` (chuỗi `performTranslation`), `09_dependency_rules` nếu thêm thư mục mới, `01_project` (số file Swift), `10_risk_report`, và `13_resource_lifecycle` nếu snapshot giữ bộ nhớ đáng kể.
3. Sửa **chỉ trong vùng** `<!-- GENERATED START -->` … `<!-- GENERATED END -->`, ghi nhận từng doc bằng `--accept` (đã sửa) hoặc `--no-change-needed` (đã xem, vẫn đúng).
4. Thêm entry `CHANGELOG.md` với version `[1.3.NNN]`, tiêu đề **trùng subject git commit**; đẩy entry cũ nhất sang `CHANGELOG.archive.md` nếu vượt ~30 entry.
5. Chạy lại validator read-only, phải PASS.
6. Nêu rõ trạng thái build: nếu thực thi trên Windows thì **không** được báo "đã kiểm chứng", chỉ báo đã chạy hai script Python.
7. Kết thúc response bằng `CodeGraph updated.`

Không commit hộ — chủ dự án tự commit.

