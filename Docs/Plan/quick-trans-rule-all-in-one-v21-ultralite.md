# Kế hoạch: áp dụng Rule All-in-One trước tokenizer Quick Translate

> Trạng thái: đề xuất để Claude triển khai.
>
> Phạm vi đã xác nhận: rule thuộc **Quick Translate nội bộ**, chạy trên text Trung gốc trước `VietPhraseTokenizer`; `Qt.translate` không phải điểm tích hợp và phải được loại trừ khỏi hiệu lực rule.

## Nguồn chuẩn và tham chiếu

- Rule source: `D:\AudioData\[VBOOK BẢN BETA - NO NE_PN] Rule-All-in-One-normalized-v21-ultralite.txt`
- Rule source: 36.608 byte, UTF-8 không BOM/LF, SHA-256 `C4B06D49598D603072DC2A8F42D1CFA5928538582C6D4AE6439AB013A912DD21`.
- Có 633 rule hoạt động; comment và dòng trống được parser bỏ qua.
- Semantic reference: `D:\Study\vbook-toolkit\src\engine\ruleEngine.ts`.
- Validation reference: `D:\Study\vbook-toolkit\src\engine\ruleValidator.ts`.
- Đã audit toàn bộ 11 file dưới `D:\Study\vbook-toolkit\src\engine` (gồm `ruleEngine.ts`, `ruleValidator.ts` và `getNames/**`).
- Filename rule ghi `v21-ultralite`, header lại ghi `V18 COMPACT NUMBERS`: vẫn là **UNKNOWN** cần chủ dự án xác nhận canonical file/hash trước khi commit.

`ruleEngine.ts` là engine tester: nó parse, compile, tìm và chọn match; nó **không** rewrite text đầu vào. FreeBook cần port ngữ nghĩa compiler/priority của nó, sau đó bổ sung bước rewrite an toàn cho pipeline iOS.

## Mục tiêu và ranh giới

Các mẫu số, ngày giờ, đơn vị, cảnh giới và số lớn trúng rule được render thành tiếng Việt trước tokenize. Phần không trúng rule giữ nguyên để VietPhrase/Hán-Việt hiện có xử lý. Vì điểm đặt ở `TranslateUtils`, hiệu lực cần đồng nhất cho Reader, TTS, metadata/TOC, tìm kiếm bản dịch và export có bật dịch.

Không tạo pipeline dịch song song ở View/TTS/extension. Không đưa rule vào `VietPhrase.txt`, `Names.txt`, `DictionaryTextFileStore` hay `JunkFilterManager`: các nơi đó không có ngữ nghĩa capture/template của Rule Quick Translate.

`JSExecutor` hiện vô tình dùng chung `TranslateUtils.translateMeta`/`translateChapterTitle`. Để giữ đúng yêu cầu “không liên quan Qt.translate”, thêm context/flag rõ ràng cho pipeline: consumer Quick Translate nội bộ bật rule; bridge extension truyền explicit `false`. Đây là hàng rào tương thích, không phải tích hợp rule vào Qt.

## Hiện trạng đã xác minh

```text
translateMeta / translateContent
  → textForTranslation (tùy chọn Phồn thể → Giản thể)
  → translateText (cache)
  → performTranslation
       → punctuationMapping
       → VietPhraseTokenizer.tokenize
       → lookup dictionary theo precedence hiện hữu
       → postProcessText
```

- Điểm chèn thực tế là `TranslateUtils.performTranslation` trước `tokenize(...)`.
- `ReaderViewModel+Translation` và `TTSBackgroundProcessor` cùng gọi `translateContentWithMapping`, nên lấy cùng text dịch khi rule nằm ở lõi.
- `translateChapterTitle` vẫn có formatter số/chương riêng; giữ formatter đó trong phase đầu và kiểm tra rule `<L>` không làm double-format.
- `translateContentWithMapping`/`translateChapterTitleWithMapping` hiện suy `TranslationSpan` sau dịch từ token dictionary. Rule có thể đổi độ dài/thứ tự nên spans cũ không đúng khi rule đã áp dụng.
- `ReaderSelectionMapper` đã có fallback cho spans rỗng; Reader/TTS dùng cùng displayed text nên highlight không phụ thuộc span mới.

## DSL và priority phải port từ reference

Parser reference chấp nhận blank/comment (`#`, `//`, `===`), `pattern = replacement`, `pattern=replacement`, dạng quote và dạng tab; nó trim toàn dòng, LHS/RHS, ưu tiên dấu `=` trước tab và giữ `RuleItem.line` **0-based**. FreeBook giữ `sourceOrder0` để sort đúng reference, chỉ hiển thị/log `sourceOrder0 + 1` cho người dùng.

`parseRulesFromText` của tester bỏ im lặng mọi dòng khác blank/comment mà không parse được, nên validator phía sau không nhìn thấy chúng. Loader iOS phải siết hơn: bất kỳ dòng vật lý non-comment/nonblank nào không thuộc format được hỗ trợ là hard `UNPARSEABLE_RULE_LINE`, reject snapshot mới thay vì vô tình nạp một tập rule thiếu. Đây là khác biệt an toàn có chủ ý so với tester.

### Ma trận token DSL — phạm vi bắt buộc cho phase 1

`min-max` là **số ký tự Unicode token được phép nuốt**, không phải khoảng giá trị số; `:n` là độ dài cố định. Đây là độ dài matcher; mọi range đưa sang Reader/TTS vẫn phải là UTF-16. Theo file canonical hiện tại, chỉ ba token số/nhãn bên dưới được phép kích hoạt. Counts là số lần xuất hiện token trong 633 rule hoạt động.

| Cú pháp | Nó capture gì / render ra gì | Có trong file hiện tại | Quyết định phase 1 |
| --- | --- | ---: | --- |
| `<n[:min-max]>` | Chuỗi số Hán hoặc Ả Rập (`〇零一二两兩三四五六七八九十百千万萬亿億兆0-9`), render thành số Ả Rập theo thuật toán số Hán. | 750 | **Hỗ trợ bắt buộc.** Ví dụ `<n:1-3>` có thể nuốt `二十一`, rồi `{0}` thành `21`. |
| `<y[:min-max]>` | Reference match cùng tập ký tự với `<n>`; khi render thì đổi từng digit và để `十百千万萬亿億兆` nguyên văn. Header rule mô tả hẹp hơn (“không nhận 十百千”). | 150 | **Hỗ trợ bắt buộc theo reference.** Dùng cho năm, phần thập phân, mã số; sai lệch header/reference phải được giữ trong UNKNOWN, không tự thu hẹp matcher. |
| `<L>` | Một nhãn `章卷集节節幕回折`, render lần lượt Chương/Quyển/Tập/Tiết/Màn/Hồi/Chiết. | 1 | **Hỗ trợ bắt buộc.** Giữ default range của reference cho tới khi chủ dự án chốt khác. |
| `<ne>` | Một cụm tra trong dictionary Name. | 0 | **Không hỗ trợ ở phase 1.** Nếu rule resource mới chứa token này, reject snapshot mới, giữ snapshot trước/no-rule; không match broad wildcard. |
| `<pn>` | Một cụm tra trong dictionary Pronoun. | 0 | **Không hỗ trợ ở phase 1**, cùng policy reject snapshot. |
| `<vp>` | Một cụm tra trong dictionary VietPhrase. | 0 | **Không hỗ trợ ở phase 1**, cùng policy reject snapshot. |
| `<hv>` | Một ký tự cần render Hán-Việt. | 0 | **Không hỗ trợ ở phase 1**, cùng policy reject snapshot. |
| `<w>` | Viết tắt `<ne|pn|vp>`; phải thử các dictionary đó từ trái sang phải. | 0 | **Không hỗ trợ ở phase 1**, cùng policy reject snapshot. |

`ruleValidator.ts` nhận cả syntax tổ hợp `<a|b>`; `ruleEngine.ts` chỉ có ngữ nghĩa rõ khi toàn bộ lựa chọn là số (`n|y`), nhãn (`L`) hoặc wildcard dictionary approximate. File canonical không dùng tổ hợp token nào. V1 chỉ activate token đơn `<n>`, `<y>`, `<L>`; tổ hợp mới hoặc tổ hợp có dictionary tag là `UNSUPPORTED_TOKEN` làm reject snapshot mới cho tới khi có contract canonical riêng.

Từ điển Name/Pronoun/VietPhrase chỉ tiếp tục xử lý phần CJK **không trúng rule** ở bước tokenizer/lookup hiện hữu. Token `<ne>/<pn>/<vp>/<hv>/<w>` là một cơ chế rule-level khác, nên không được “coi như đã hỗ trợ” chỉ vì app vốn có các dictionary đó.

| Thành phần cấu trúc | Hành vi phải port |
| --- | --- |
| Literal | Escape trước khi tạo regex; `.` và `+` trong file là literal. Mỗi rule phải có ít nhất một literal làm neo. |
| `(a|b)` / `(a|b)?` | Nhóm thay thế non-capture, có/không optional; không có index `{i}` riêng. |
| `{0}`, `{1}`, … | Chỉ tham chiếu các token capture theo thứ tự xuất hiện; literal và nhóm không được đánh số. Validate mọi capture đều được dùng và không có `{i}` vượt phạm vi. |

Chuyển số phải bám `ruleEngine.ts`: chữ số `〇零一二两兩三四五六七八九`, đơn vị `十百千万萬亿億兆`, chữ số Ả Rập. ASCII-only `<n>` giữ nguyên leading zero (`0007` vẫn là `0007`); `<y>` map từng digit. Không dùng nguyên `TranslateUtils.chineseNumberToInt` hiện hữu vì nó chưa phủ đủ contract.

`BigInt` của reference chỉ tránh overflow, **không tự chứng minh ngữ nghĩa số Hán chuẩn**: thuật toán section/large-unit hiện cho `一万亿 → 100010000` và `一亿亿 → 200000000`, không phải diễn giải lũy thừa lớn thông thường. Không được mô tả nó là “chính xác” hoặc tự thay bằng thuật toán khác. Phase triển khai phải chốt một policy: port đúng output reference để parity, hoặc chủ ý sửa số Hán lồng đơn vị và version/fixture rule tương ứng.

Swift không có `BigInt` chuẩn trong Foundation: Claude phải chọn representation decimal arbitrary-precision cục bộ hoặc thuật toán string tương đương cho policy đã chốt; không được rơi về `Int`/`Int64` rồi overflow im lặng.

Bốn điểm lệch giữa comment rule và reference phải được ghi rõ, không tự “sửa cho hợp lý”: reference không có lookaround chặn `<n>/<y>` nuốt một phần số dài, `<y>` match rộng hơn mô tả header, `<L>` mặc định có range `1...12` dù header mô tả một nhãn, và số Hán lồng đơn vị lớn không theo cách hiểu thông thường. Port baseline nên giữ behavior reference; thay đổi boundary/range/class/number semantics chỉ làm sau khi chủ dự án xác nhận đó là hành vi mong muốn.

### Cổng chọn rule hợp lệ từ `ruleValidator.ts`

`ruleValidator.ts` là nguồn cho **việc chấp nhận hoặc loại resource rule**; nó không chọn rule thắng khi nhiều rule cùng match. Rule thắng ở runtime vẫn theo priority của `ruleEngine.ts` ở mục kế tiếp.

| Mức | Tiêu chí phải port | Xử lý snapshot iOS |
| --- | --- | --- |
| Hard error | Dòng non-comment/nonblank không parse được; token không thuộc DSL/project-supported token; giới hạn `:min-max` sai; thiếu `<`/`>`; ngoặc không cân bằng; pattern rỗng; hoặc compiler không instantiate được regex thật. | Reject toàn bộ snapshot mới; giữ snapshot hợp lệ trước hoặc no-rule. |
| Hard error | Không có token wildcard; không có literal anchor; hoặc anchor chỉ gồm các ký tự quá phổ biến (`的了是不存在在上下个個`). | Reject toàn bộ snapshot mới. Không lặng lẽ bỏ riêng rule lỗi. |
| Hard error | RHS có `¦`; placeholder `{i}` vượt capture; hoặc một capture không được dùng. | Reject toàn bộ snapshot mới. |
| Warning | Wildcard dictionary không có range; pattern trùng; hơn 20 rule dùng cùng anchor; hoặc hai wildcard `<…><…>` liên tiếp. | Snapshot vẫn có thể activate; log summary có line/count, không log text chương. Pattern trùng giữ rule line để runtime tiebreak theo thứ tự nguồn. |

`ruleEngine.validateAllRules` chỉ là validator tester yếu (compile string, RHS ref index, wildcard liên tiếp) và tính `validCount` theo số issue hard, không phải số rule hard; không dùng nó làm load gate. Cổng iOS là policy mới có chủ ý: strict parser + `ruleValidator.ts` + instantiate regex thật từ AST.

Trình tự bắt buộc: parse và giữ `sourceOrder0` → reject `UNPARSEABLE_RULE_LINE` → validate toàn bộ theo `ruleValidator.ts` và policy token v1 → compile thật từng rule theo `ruleEngine.ts` → nếu có hard error thì không swap snapshot → nếu chỉ warning thì compile/swap atomically → matcher mới được chạy. `ruleValidator.ts` chưa bắt nesting group nhưng compiler reference chỉ xử lý một cấp; V1 reject group lồng nhau như hard `UNSUPPORTED_NESTED_GROUP` (file canonical không dùng) thay vì diễn giải khác. Port `findAnchor` của validator để áp cùng định nghĩa khi kiểm tra rule và thống kê cảnh báo; không dùng nó như phép cắt/sửa text đầu vào **hay candidate index** vì nó ghép literal qua token/group, không bảo đảm là substring liên tục. Tối ưu sau này chỉ được dùng contiguous required literal do AST chứng minh, kèm fallback không bỏ sót candidate.

Priority đã được reference xác định; loại bỏ UNKNOWN về precedence. Sau khi thu tất cả match hợp lệ, sort và chọn greedy non-overlap theo đúng thứ tự:

1. Vị trí xuất hiện sớm hơn.
2. `literalLength` lớn hơn.
3. `wildcardCapacity` nhỏ hơn.
4. Full match dài hơn.
5. Rule nằm ở dòng sớm hơn.

Chọn match tốt nhất tại vị trí đầu tiên còn lại, rồi dời cursor qua hết match đó. Không dùng “first rule in file” hay “longest match” đơn lẻ.

### Giải quyết tranh chấp rule (overlap, duplicate và cascade)

Candidate được tìm trên **cùng một input chưa rewrite** (sau Phồn → Giản nếu bật, trước punctuation mapping). Không thay text trong lúc đang tìm candidate, vì replacement sớm sẽ làm rule phía sau thấy input khác reference.

Không diễn giải “thu tất cả candidate” theo nghĩa exhaustive: reference chạy **một regex global greedy cho từng rule**, nên mỗi rule chỉ phát các match trái-sang-phải, không overlap của chính nó; nó không thử match ngắn hơn hoặc điểm bắt đầu overlap khác của cùng rule. Sau đó mới gộp candidate của mọi rule để sort. FreeBook phải giữ đúng constraint này để parity; một matcher exhaustive là thay đổi semantics cần được chốt riêng.

| Trường priority | Cách tính phải port | Ý nghĩa khi tranh chấp |
| --- | --- | --- |
| `index` | Offset bắt đầu UTF-16 của match trong input. | Rule bắt đầu sớm hơn luôn được xét trước, kể cả rule bắt đầu sau trông có vẻ cụ thể hơn. |
| `literalLength` | Tổng literal ngoài token tính theo UTF-16 như reference; nhóm `(a|b)` không optional đóng góp độ dài UTF-16 của alternative dài nhất, nhóm optional không đóng góp. | Cùng vị trí: rule có nhiều ngữ cảnh cố định hơn thắng. |
| `wildcardCapacity` | Tổng `max` của mọi token `<…>` trong pattern. | Nếu literal bằng nhau: rule nuốt wildcard hẹp hơn thắng. |
| `fullMatchLength` | Độ dài UTF-16 thật của toàn bộ match. | Chỉ dùng sau hai tiêu chí trên: match dài hơn thắng. |
| `sourceLine` | Thứ tự dòng trong file nguồn. | Chỉ là tiebreak cuối; dòng sớm hơn thắng. |

Thuật toán bắt buộc, tương đương `ruleEngine.ts` nhưng không cần `filter` mảng lặp lại:

1. Với từng compiled rule, scan một pass regex Unicode global greedy trên input, lấy đúng chuỗi candidate non-overlap do regex phát; ngay lúc này lưu range UTF-16 của full match **và từng capture token**, render replacement tạm rồi gộp candidate.
2. Đặt `cursor = 0`; lấy candidate đầu tiên có `start >= cursor`. Vì đã sort, đó là candidate thắng tại vị trí sớm nhất còn lại.
3. Chọn nó, append rewrite atom/trace, rồi đặt `cursor = chosen.startUTF16 + max(1, chosen.matchLengthUTF16)`.
4. Bỏ mọi candidate có `start < cursor`, kể cả candidate bắt đầu trong hoặc bao phủ một phần match đã chọn; lặp tới hết input.

| Tình huống | Kết quả phải có |
| --- | --- |
| Hai rule cùng bắt đầu | So `literalLength` → `wildcardCapacity` → độ dài match → dòng nguồn; không ưu tiên rule viết trước trừ khi hòa mọi tiêu chí trước. |
| Một rule bắt đầu sớm, rule khác cụ thể hơn nhưng bắt đầu muộn trong vùng overlap | Rule bắt đầu sớm thắng; rule kia bị cursor loại. |
| Hai pattern trùng nguyên văn nhưng RHS khác nhau | Đây chỉ là warning `duplicate`; **không dedupe** khi nạp. Dòng nguồn sớm hơn thắng ở runtime, nên thứ tự file là hành vi có chủ ý. |
| Hai match không overlap | Cả hai được rewrite, từ trái sang phải. |
| Replacement vừa sinh lại trúng một rule khác | Không chạy cascade/đệ quy. Rule chỉ chạy một pass trên input Trung gốc; output Việt đi thẳng sang punctuation/tokenizer. |

Hệ quả cho người viết rule: tăng literal context hoặc thu hẹp range token mới tăng ưu tiên thực; chỉ di chuyển rule lên trên file không đủ để thắng rule cùng vị trí có `literalLength`/`wildcardCapacity` tốt hơn. `MatchResult` của reference chỉ giữ full match/index, nên iOS phải bổ sung trace ngay khi matcher còn có capture ranges: `sourceLine`, full `sourceRangeUTF16`, từng `captureSourceRangeUTF16`, `replacementRangeUTF16`, range output của từng `{i}` và các metric đã chọn. Không thể tái dựng chính xác capture mapping sau rewrite mà không có trace này; log debug chỉ ghi metadata, không log nội dung chương.

## Thiết kế triển khai

### 1. Resource, compiler và snapshot

1. Chép nguyên file rule thành bundle resource, ví dụ `Sources/Resources/Translation/QuickTranslateRules-v21.txt`; không hard-code 633 rule và không phụ thuộc runtime vào ổ `D:`.
2. Vì target XcodeGen lấy toàn bộ `Sources`, chạy `xcodegen generate` và xác nhận resource vào Copy Bundle Resources.
3. Parse/validate/compile strict thành snapshot bất biến: áp `ruleValidator.ts`, policy token v1, compiler thực và warning/hard-error policy ở trên trước khi cài. Không dùng `validCount = rules - hard issues` làm số rule hợp lệ vì một rule có thể có nhiều issue; quyết định activation theo có/không hard error.
4. `ruleEngine.ts` compile rule tại mỗi lần test; bản iOS phải compile một lần ngoài MainActor, cache compiled snapshot và swap thread-safe. `TranslateUtils` được gọi ngoài MainActor từ Reader/TTS.
5. Khi lỗi load/compile: `AppLogger` chỉ ghi version, số rule và line lỗi; giữ snapshot hợp lệ trước hoặc fallback no-rule. Không áp dụng một phần file lỗi hay log full chương.

Tách file trong `Sources/Services/Translation/Engine/` đúng 1 primary type/file, tối đa 400 dòng/file, ví dụ:

- `QuickTranslationRuleParser.swift`: format text → AST/compiled rule + validation.
- `QuickTranslationRuleMatcher.swift`: thu match, sort/greedy selection theo reference.
- `QuickTranslationRuleEngine.swift`: rewrite text từ các match đã chọn.
- `QuickTranslationNumberFormatter.swift`: `<n>`/`<y>`/`<L>`.
- `QuickTranslationRuleStore.swift`: resource và snapshot thread-safe.
- `TranslateUtils+QuickTranslationRules.swift`: context, cache metadata và facade nội bộ.

### 2. Rewrite trước tokenizer

Reference dùng `trim()` cho UI tester; production không được trim text vì làm lệch nội dung/range. Nếu cần tái dùng matcher raw, phải rebase match qua leading whitespace; khuyến nghị match trực tiếp chuỗi nguyên vẹn.

Đổi `performTranslation` thành:

```text
input sau textForTranslation (nếu Phồn → Giản)
  → QuickTranslationRuleEngine.rewrite(input)      [chỉ context Quick Translate nội bộ]
  → punctuationMapping hiện hữu
  → VietPhraseTokenizer.tokenize
  → lookup dictionary hiện hữu
  → postProcessText hiện hữu
```

Rule chạy trước `punctuationMapping`: LHS có literal `．`, `.`, quote/dấu câu; normalize punctuation trước có thể đổi literal hoặc chèn space khiến match sai. Đây vẫn đúng yêu cầu “trước tokenize”.

`rewrite` append text nguyên vẹn từ cursor đến match, append template đã render, rồi tiếp tục sau match. Không chạy rule đệ quy trên tiếng Việt vừa render. Text Trung không match đi tiếp vào tokenizer/dictionary cũ; text Việt do rule sinh ra phải được tokenizer giữ nguyên.

Có thể dùng regex **được compiler sinh ra** giống reference, nhưng tuyệt đối không đưa DSL raw trực tiếp cho `NSRegularExpression`: literal phải escape, group phải non-capture và capture/template contract do AST kiểm soát.

Reference chưa enforce hoàn toàn comment rule về việc `<n>`/`<y>` không được nuốt một phần số dài hơn. Không tự bổ sung lookaround trong patch parity; nếu chủ dự án muốn siết boundary, ghi nó thành thay đổi chủ ý, có ví dụ regression và cập nhật version rule.

### 3. Context để loại trừ Qt bridge

Thread một flag rõ ràng, ví dụ `applyingQuickTranslationRules: Bool`, qua `translateMeta`, `translateContent`, hai API `...WithMapping`, `translateChapterTitle`, `translateText` và `performTranslation`:

- Mặc định `true` cho tất cả callsite Quick Translate nội bộ, nên Reader/TTS/export/metadata dùng rule chung.
- `JSExecutor` truyền explicit `false` vào các call hiện có. Khi false, pipeline giữ punctuation/tokenizer/dictionary behavior cũ nhưng bỏ `rewrite` rule.
- Cache key phải chứa flag/context để bản dịch bridge không lẫn với bản dịch app có rule.

Không dùng `Thread.current` hay mutable global để suy context; callsite phải truyền tường minh để an toàn concurrency.

### 4. Cache, invalidation và mapping

`translationCache` hiện chỉ giữ `String`. Đổi entry nội bộ thành kết quả pipeline chứa `text`, context, rule snapshot generation/hash và **rewrite trace**; không chạy engine lần thứ hai chỉ để biết span còn hợp lệ.

`QuickTranslationRuleEngine.rewrite` phải trả các atom/match đã chọn với range UTF-16 của nguồn và range UTF-16 của text sau rewrite. Từ trace đó, pipeline dựng `TranslationSpan` cùng lúc với text cuối:

- Fallback atom: dùng tokenization/dictionary hiện hữu, rebase span về range nguồn tương ứng.
- Rule atom: span của output rule map tối thiểu về **toàn bộ** original match; capture có mapping rõ ràng có thể cho span hẹp hơn, nhưng không được bịa span theo tỉ lệ.
- Không còn gọi `buildTranslationSpans(original: fullOriginal, translated: finalText)` theo heuristic cũ sau khi đã rewrite; nó không biết output rule có reorder/đổi độ dài.
- `getTranslationTokens` và `snapToToken` phải dùng cùng atomization/trace để selection trên một rule được snap về rule source, không về token dictionary đoán lại.

Mục tiêu là span phủ đúng output rule để `ReaderSelectionMapper` và `TTSParagraphBuilder.mapSourceRange` không rơi vào fallback sentence/ratio cho phần đã rewrite. Nếu một atom không thể chứng minh mapping, trả span rỗng **chỉ cho atom đó**, không giả range và không xoá trace hợp lệ của các atom khác.

- Rule snapshot generation phải vào `translationGenerationToken(for:)` và cache key. Khi có reload rule trong tương lai, Reader/TTS snapshot cũ bị loại cùng lúc và chỉ phát **một** `TranslationManager.notifyDictionariesDidUpdate`; không tạo refresh Reader trực tiếp thứ hai.
- Với bundle-only, compile snapshot trước khi `TranslationManager.loadAllDictionaries()` kết thúc để call đầu tiên không chạy snapshot chưa sẵn sàng. Compile fail vẫn phải cho Quick Translate cũ hoạt động.

## Scope UI/persistence

Không thêm toggle: rule tự có hiệu lực khi `isTranslationEnabled` (“Bật dịch Quick Translate”) hiện hữu. Đợt đầu ship resource bundled.

Nếu sau này cần import/replacement như comment file nguồn, làm phase riêng: override `Application Support/translate/`, validate toàn bộ rồi replace atomically, UI, generation/invalidation và backup/restore qua `BackupPaths`, `BackupConfigArchiver`, restore worker. Không gộp vào patch logic nếu chưa được yêu cầu.

## Phần `src/engine/getNames` đã audit — loại khỏi feature này

Chín file `getNames/**` là subsystem web scrape/export Name packages: `urlDetector`/`index` chọn Wikicv, Sangtacviet hoặc Chiasename; các parser và CORS helper tải HTML/JSON; `types`/`textHelper` chuẩn hóa package `Chinese=Vietnamese`; `exportHelper` tải TXT/ZIP. Không file nào import rule engine/validator hay thực hiện runtime matching Quick Translate.

Không tái dùng `getNames/textHelper.parseNameText` cho rule file: nó chỉ hiểu `Chinese=Vietnamese`/tab và comment `#`, không hiểu quote rule, capture, alternative, placeholder, priority hay validator. Cũng không đưa proxy/CORS/DOM scraper vào iOS rule engine.

Đây không phải resolver cho `<ne>/<pn>/<vp>/<hv>/<w>`: Name package không có category, precedence, range hay contract lookup để thực hiện các token đó. Nếu muốn dùng dữ liệu Get Names trong tương lai, làm phase riêng với mapping sang dictionary app, snapshot/version/cache và conflict policy; không piggyback vào parser Rule All-in-One.

## Nghiệm thu thủ công

Không tạo, đọc, sửa hoặc chạy bất kỳ file nào dưới `Tests/`.

| Input Quick Translate nội bộ | Kỳ vọng |
| --- | --- |
| `二零二四年三月二十一日` | `ngày 21 tháng 3 năm 2024`. |
| `百分之三点一四` | `3,14%`. |
| `生命能量+十` | `+` là literal, không bị regex diễn giải. |
| `第一章` và title prefix/suffix | Không hồi quy/double-format formatter title. |
| Names/VietPhrase không trúng rule | Giữ precedence dictionary/Hán-Việt cũ. |
| `万/萬/亿/億/兆`, số quá dài/malformed | Đúng theo policy số Hán đã chốt hoặc fallback nguyên vẹn; không overflow/nuốt token. Bao gồm explicit `一万亿`, `一亿亿` để khóa parity hay correction. |
| Rule đổi thứ tự ngày/tháng/năm | Text đúng, trace/span atom map đúng về source; không dùng ratio fallback cho atom rule. |
| Text dài nhiều rule | Không recompile mỗi call; Reader/TTS có cùng displayed text. |
| Extension gọi Qt bridge | Output giữ đúng behavior cũ, không chịu rule bundled. |

Không dùng `ruleEngine.makeExample` làm bằng chứng nghiệm thu: helper này luôn lấy min token length, alternative đầu tiên, bỏ optional group và không chạy priority/overlap/rewrite. Nếu port, nó chỉ là preview offline cho người viết rule.

Trên macOS: `xcodegen generate` rồi build FreeBook. Trên Windows nêu rõ không thể chạy `xcodebuild` tại chỗ. Trước/sau thay đổi chạy `python Scripts/check_architecture.py` để so baseline; sau source change chạy `python Docs/CodeGraph/validate_links.py --explain`. Không coi `[PASS]` của architecture script là bằng chứng duy nhất.

## UNKNOWN còn lại

1. File/hash V18/V21 ở đầu tài liệu có phải canonical không?
2. Có giữ nguyên bốn behavior reference (không boundary `<n>/<y>`, `<y>` match rộng hơn header, `<L>` mặc định `1...12`, số Hán lồng đơn vị lớn có output khác cách hiểu thông thường) hay coi comment rule là contract mới cần sửa engine? Không thay đổi cho tới khi chủ dự án chốt.
3. `translateChapterTitle` hiện có thể dịch một số unit khác rule source; giữ formatter hiện tại hay cho rule rewrite chạy trước formatter cần được chốt bằng ví dụ output mong muốn.

## CodeGraph và bàn giao khi Claude thực thi

Plan này không sửa CodeGraph hay `CHANGELOG.md`. Khi source thay đổi, Claude phải chạy `validate_links.py --explain`, cập nhật đúng GENERATED vùng của mọi doc stale, `--accept`/`--no-change-needed` từng doc, thêm CHANGELOG version/subject đúng quy ước và chạy validator read-only đến PASS 100%.
