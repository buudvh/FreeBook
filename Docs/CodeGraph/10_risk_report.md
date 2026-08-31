---
generated_by: Antigravity
generator_version: 1.0
generated_at: 2026-08-21T10:30:00+07:00
git_commit: UNKNOWN
source_files: 230
document_version: 4
---

# Báo cáo Rủi ro Kỹ thuật (Technical Risk Report)

Tài liệu này báo cáo chi tiết các rủi ro kỹ thuật tiềm ẩn hoặc hiện hữu được phát hiện trong mã nguồn dự án FreeBook, phân loại theo mức độ nghiêm trọng (Severity) và khả năng xảy ra (Likelihood), đi kèm với nguyên nhân và giải pháp khắc phục.

## Ghi chú thủ công (Human Notes)
*Ghi chú thủ công của con người.*

<!-- GENERATED START -->
## Đã loại được rủi ro nào của VieNeu, và còn lại gì (1.3.294)

**Ba rủi ro build của 1.3.292 đều đã loại** — CI của 1.3.293 xanh: selector
`ORTSessionOptions.addConfigEntry(withKey:value:)` **có** trong binding ObjC đang pin, contrib op int8
biên dịch được, và 25 file mới chỉ có **một** lỗi (closure bắt `self` trước khi `channels` khởi tạo).

**Bộ `onnx_int8` không hỏng.** Chạy engine tham chiếu Python trên **đúng** bộ int8 đó (local dir,
`temperature = 0`) cho 4.56 s audio, peak 0.58, rms 0.12 — tỉ lệ rms/peak 0.21 là đặc trưng tiếng nói,
tiếng ồn trắng cho 0.5–0.7. Nghĩa là nếu thiết bị cho ra nhiễu thì lỗi nằm ở **bản port Swift**, không
ở export.

**Bốn thành phần đã đối chiếu số học với bản tham chiếu và khớp:**

* **Speaker anchor** — thuật toán của bản Swift (GEMV `NoTrans` trên `xvec_w` (768,192), rồi LayerNorm
  phương sai **toàn phần**) cho `max|Δ| = 7.45e-09` so với `_speaker_anchor`. Đúng.
* **Bảng npz** — `text_emb` (419,768) fp32, `audio_emb` (16,1024,768) fp32, cả hai C-contiguous, npz
  **stored** (không nén). Chỉ số phẳng `(ch * 1024 + code) * 768 + h` của bản Swift là đúng.
* **Tokenizer** — id của **mọi** phoneme giống nhau giữa `tokenizer.json` gốc và bản `onnx_int8`; chỉ 30
  nhãn `<|reserved_N|>` bị đổi số. `<|unk|>` = 43, vocab phoneme bắt đầu ở 44 ở cả hai.
* **Style token 16 là token thật, không phải ô random-init.** Trong tokenizer của `onnx_int8`, id 16 là
  `<|style_0|>`; ô dự trữ bắt đầu ở **26**, không phải 13. Ghi chú `reserved_token_start = 13` trong
  `config.json` mô tả cách đánh số của bộ **gốc**. Kết luận "dùng 16" vẫn đúng, nhưng lý do thì khác
  với những gì 1.3.292 ghi.

**`SeaG2P` khớp cho văn xuôi tiếng Việt, lệch ở chữ số và gạch nối.** Cùng một câu tiếng Việt thuần,
bản Swift cho chuỗi phoneme **giống hệt** sea-g2p thật. Nhưng "VieNeu-TTS v3" thì sea-g2p thật cho
`vˈaɪ nˈuː tˈiː tˈiː ˈɛs vˈe bˈaː` (tách ở gạch nối, đọc từng chữ cái, `v3` → "vê ba") còn bản Swift cho
`vˈiːnuː - tˌiːtˌiːˈɛs vˈiː3` (giữ gạch nối làm token, dính chữ cái, **để nguyên chữ số 3**). Chữ số
trong ký hiệu này là **dấu thanh** nên đó là lỗi thật — nhưng trong FreeBook nó đã được
`TextPreprocessor` chặn trước, và nó **không** giải thích được tiếng ồn.

**Còn lại, chưa loại được:**

* Lỗi nằm đâu đó trong cơ chế Swift mà không đọc code ra được: xử lý `ORTValue`, tuổi thọ buffer, hoặc
  vòng `VieNeuDecodeLoop`. `ONNXVieNeuEngine+SelfCheck` được thêm chính để bisect chỗ này bằng **một**
  lần chạy trên máy.
* **Không có bằng chứng nào cho thấy bản port Swift từng cho ra audio đúng.** Bản thử nghiệm chạy với
  `active_vq = 8` — thứ mà 1.3.292 đã xác định là làm tiếng đục — nên "chậm nhưng nghe được" chưa bao
  giờ được kiểm chứng. Lỗi có thể có từ đầu và nằm trong phần code dùng chung.
* RAM và throttle nhiệt vẫn chưa đo. Log thiết bị cho `thermal=serious` và `[NghiEnergy] Underrun` chỉ
  3 giây sau khi bắt đầu phát, khớp với "khoảng cách giữa 2 chunk lớn".

## Rủi ro của engine VieNeu-TTS (1.3.292)

**Chưa được kiểm chứng trên thiết bị.** Toàn bộ phân hệ này được viết trên Windows, chưa biên dịch và chưa chạy lần nào. Ba điểm phải kiểm ngay ở lần build/chạy đầu:

* **`ORTSessionOptions.addConfigEntry(withKey:value:)`** — dùng để tắt spin-wait của threadpool. Nếu binding ObjC của phiên bản ORT đang pin không có selector này thì đây là **lỗi biên dịch**, không phải lỗi runtime; bỏ dòng đó là xong.
* **ORT có mmap chung `vieneu_backbone_shared.data` cho hai session hay không.** Nếu nó copy thì RAM là 208 MB thay vì 104 MB, cộng heads 52 MB và codec 44 MB — trên iPhone 11 4 GB chạy qua LiveContainer, cùng lúc có Reader và WKWebView của extension, đó là mức đáng lo cho jetsam.
* **Contrib op int8** (`DynamicQuantizeMatMul`/`MatMulIntegerToFloat`) có trong bản SPM hay không. Thiếu thì đường lùi là bộ `onnx` fp32: chạy được nhưng chậm hơn ~4× ở hạng mục chiếm 64% vòng lặp.

**Rủi ro chất lượng đặc thù của model tự hồi quy** — Piper không có nhóm này:

* **Ảo giác, lặp vòng, bỏ chữ, EOS sớm.** Ba lá chắn đã có: trần frame theo độ dài phoneme (`24 + 2.0 × len`), repetition penalty cửa sổ trượt 64 frame cho **mọi** codebook, và chốt dấu câu cuối chunk (`punc_norm`). Đọc truyện hàng giờ vẫn là điều kiện chưa được thử.
* **Không tất định.** `temperature = 0.8` nên cùng một chunk cho audio khác nhau mỗi lần. Muốn đối chiếu với bản Python thì phải đặt `temperature = 0` (đường argmax) — chỉ khi đó kết quả mới so sánh được.
* **Ngữ điệu nhảy giữa các chunk.** `referenceCodes` giữ **danh tính** giọng ổn định nhưng đường cao độ/năng lượng reset mỗi chunk. Bản tham chiếu chống bằng cách gộp chunk ngắn hơn 20 ký tự; `TTSParagraphBuilder` của FreeBook **chưa** làm điều đó.
* **Mẫu NaN/Inf** đưa thẳng vào `AVAudioPlayer` là tiếng nổ. `normalise` lọc và đếm chúng vào log.

**Rủi ro hiệu năng và điện năng.** Vòng AR đo được 31.25 ms/frame trên iPhone 11 với bộ **fp32**; dự phóng ~17 ms/frame với bộ int8, tức ~4.7× realtime. Cộng codec (1.34 s cho 6.72 s audio, chỉ có bản fp32 nên là sàn không giảm được), RTF tổng dự kiến ~0.44. Đủ cho watermark 8 giây của `NghiSynthesisPolicy` nhưng **mỏng hơn Piper rõ rệt**: throttle nhiệt sau 20–30 phút có thể đẩy RTF qua 1.0, và khi đó là đứt tiếng chứ không phải chậm hơn. `ProcessInfo.thermalState` hiện **chỉ là telemetry**, không chặn hay điều tiết refill — với Piper vô hại, với VieNeu thì không còn vô hại.

**Rủi ro tải model.** 274 MB qua 11 file. Đã có: resume bằng HTTP Range, ngưỡng cỡ tối thiểu cho từng file (chống trang lỗi HTTP 200), và nguyên tử ở mức cả bộ (staging → kiểm đủ → đổi tên). Chưa có: kiểm SHA-256. Một file tải đủ cỡ nhưng hỏng nội dung sẽ hiện ra dưới dạng lỗi nạp ORT mù mờ.

**Rủi ro không streaming.** Codec chạy một lần cho cả chunk (`decode_full`), nên chunk đầu sau khi bấm Play phải chờ sinh xong toàn bộ. Prefetch của FreeBook che được phần lớn vì chunk ở đây cỡ câu, nhưng chunk đầu tiên vẫn cảm nhận được. `decode_step` + state streaming để lại cho lượt sau.

## Rủi ro sau lượt chống mất chữ (1.3.291)

* **Chỗ mất chữ sâu nhất vẫn còn**: `ONNXPiperEngine` bỏ im lặng mọi unicode scalar không có trong `phoneme_id_map` của model (chỉ log). Lượt này chỉ bịt các tầng trên; bịt hẳn cần map âm vị **trong** inventory của model — việc của Phase 2, **chưa làm**.
* **Cụm phụ âm thành âm tiết đệm làm câu dài hơn**: "street" 3 âm tiết, "text" 2. Đọc đúng hơn nhưng nhịp chậm hơn; `trailingFiller` cố ý chỉ lấy **một** phụ âm thừa vì quá một là nghe rời rạc. Đánh đổi, không phải giới hạn kỹ thuật.
* **Cổng ngữ cảnh siết lại bỏ sót chiều ngược**: "man" ở **đầu** một cụm tiếng Anh ("man of steel") không còn láng giềng lạ bên trái ⇒ giữ nguyên. Chọn bỏ sót thay vì đọc oan từ tiếng Việt.
* **Xoá tất cả phiên âm không hoàn tác được** và không có sao lưu tự động; chỉ có hộp xác nhận nêu rõ hậu quả. Ai đã xuất từ điển thì nhập lại được.
* **`deleteAllWords` ghi file rỗng thay vì xoá file** — cố ý: `loadResourcesFromDisk` coi file không tồn tại là "chưa tải từ điển", khác với "người dùng muốn trống".

## Rủi ro của lượt đổi phiên âm Anh/Nhật (1.3.290)

* **Phụ thuộc vào bộ dữ liệu espeak trong bản build.** Đường tiếng Anh mới chỉ chạy khi `voices/en` + `en_dict` có thật trong `espeak-ng-data` đã đóng gói. `build-ipa.yml` hiện giữ chúng, nhưng bước dọn dữ liệu đó là **xoá theo danh sách trắng** — sửa nó mà quên `en_dict` là cả tính năng âm thầm rơi về bộ luật cũ, không có lỗi nào nổ. Bù lại: `probeVoices` ở màn Thử phiên âm báo đỏ ngay, và `phonemizeEnglish` ghi `AppLogger` khi đặt giọng thất bại.
* **Đổi giọng espeak là trạng thái toàn cục.** `phonemizeEnglish` đặt `en-us` rồi trả `vi` trong `defer`, tất cả bên trong cùng `NSLock` mà `ONNXPiperEngine` dùng. Nếu sau này có ai gọi espeak **ngoài** `EspeakPhonemizer`, hoặc thêm một lối vào không trả giọng, thì Piper sẽ tổng hợp bằng âm vị tiếng Anh — sai giọng toàn bộ, và triệu chứng sẽ xuất hiện *muộn* sau một lần phiên âm.
* **Chất lượng bảng IPA→Việt chưa được kiểm trên máy thật.** Bảng phủ nguyên âm/phụ âm phổ thông cộng vài ký hiệu riêng của espeak (`ɐ ᵻ ɚ ɫ ɾ`); âm vị lạ bị `tokenize` bỏ qua, nên trường hợp xấu là mất một âm chứ không phải crash. Nhưng "mất một âm" khó phát hiện bằng mắt — đó là việc của bộ ca kiểm.
* **Bộ phân loại mới đổi hành vi trên *tập từ vô hạn*.** Bỏ blacklist là bỏ một danh sách chắc chắn đúng (~420 từ đã được xác nhận bằng tay) để đổi lấy một hàm chấm điểm tổng quát. Ngưỡng `japaneseThreshold = 2` là con số **chưa được hiệu chỉnh trên dữ liệu thật**, chỉ trên ~24 ca kiểm; rất có thể phải điều chỉnh sau khi đọc thực tế.
* **Cổng ngữ cảnh có thể phiên âm oan từ tiếng Việt.** Điều kiện "có láng giềng lạ trong ±2 token" sai khi một câu tiếng Việt không dấu chen từ tiếng Anh: "anh Nam gọi taxi" có thể làm "nam" bị phiên âm. Giảm thiểu bằng cửa sổ hẹp + chặn ở dấu kết câu, và bằng việc tiếng Việt viết có dấu dày đặc. Không có cách nào đúng 100% mà không có bộ phân loại ngôn ngữ mức câu.
* **Trộn từ điển đánh đổi có chủ ý**: mục dưới máy **thắng** bản tải về, nên một chỉnh sai của người dùng sẽ không bị bản cập nhật từ máy chủ sửa lại. Chọn hướng này vì mất một bản cập nhật nhẹ hơn mất dữ liệu người dùng — và trước 1.3.290 thì bản tải về xoá sạch chỉnh tay.
* **Không có rủi ro âm thanh cũ**: PCM chỉ nằm trong RAM theo phiên nên đổi phiên âm không để lại audio sai trên đĩa. `transliterationCache` bị xoá mỗi khi từ điển đổi.

## Rủi ro mở rộng widget TTS từ Reader (1.3.277)

* **Rủi ro chính là đặt request ở sai tầng.** Nếu đưa vào `TTSManager.startSpeaking`, tầng Service sẽ biết widget UI và phá ranh giới kiến trúc. Bản này giữ request trong `ReaderView.startTTS(...)`, caller duy nhất của startSpeaking trong `Sources/`.
* **Không đổi default mode của widget.** Đổi `FloatingWidgetViewModel.init()` sang `.revealed` sẽ làm mọi lần tạo widget mở rộng, kể cả ngoài yêu cầu Reader. Bản này dùng cờ một lượt `shouldRevealOnNextShow` nên phạm vi đúng với hành động người dùng.
* **Auto-hide vẫn chạy.** "Mở rộng ban đầu" không có nghĩa là ghim mở rộng vô hạn; nếu muốn giữ mở lâu hơn thì phải là yêu cầu UI riêng, vì hiện tại nó dùng timer reveal 3 giây sẵn có.

## Rủi ro highlight chuẩn bị TTS (1.3.276)

* **Chưa biên dịch trên host hiện tại.** Thay đổi chạm chữ ký view (`ReaderTextView`, `ParagraphCardView`) và shape snapshot TTS, nên lỗi compiler còn có thể chỉ lộ trên macOS/CI. Windows không có `xcodebuild`; xác minh cục bộ chỉ là đọc code, `validate_links.py`, `check_architecture.py` và `git diff --check`.
* **Rủi ro hành vi chính là tô sớm nhưng không được commit sớm.** Nếu ai sau này dùng `preparingHighlightRange` như `highlightRange` active để lưu tiến độ/Now Playing/prefetch, bug ban đầu quay lại ở dạng mới: đoạn chưa nghe đã được coi là đã nghe. Bất biến: preparing chỉ là presentation state.
* **Dedupe snapshot là bẫy.** Không được thay `publishPreparingParagraphState` bằng publish active `highlightRange` sớm; khi audio thật bắt đầu, snapshot active có thể không đổi và `commitAudibleParagraphState` sẽ skip side effects.
* **Range chuẩn bị dùng cùng hệ toạ độ với active highlight.** Không thêm mapper; thêm mapper sẽ tái tạo nhóm lỗi đã xoá ở 1.3.81.

## Rủi ro của hai bộ rule, tắt-by-file, Check rule/Copy gốc và backup (1.3.274)

* **Chưa biên dịch — 17 file Swift mới nên bắt buộc `xcodegen generate` rồi mới build trên macOS/CI.** Viết trên Windows nên không build tại chỗ và chưa kiểm trên máy thật. `check_architecture.py` không chạy được ở đây; kiểm tra bằng mắt: 17 file mới đều ≤ 400 dòng (lớn nhất 383) và đúng 1 type top-level, không file Service nào `import SwiftUI` hay gọi `ToastManager.shared`. CI xanh chỉ chứng minh *biên dịch được*.
* **Rủi ro dữ liệu đáng kể nhất: khôi phục backup "chỉ thêm, không xoá" làm **sống lại lựa chọn cũ**.** Cả hai chiều khôi phục rule đều gộp chứ không ghi đè — hợp tập mẫu cho file tắt (`merge`), `importRules(.overwriteExisting)` cho bộ riêng (đè vế phải của mẫu trùng). Khôi phục từ bản sao lưu **cũ hơn** vì vậy có thể tắt lại một rule người dùng vừa bật, hoặc hồi phục nghĩa cũ của một mẫu đã sửa. Đây là đánh đổi có chủ ý (ghi đè sẽ xoá trắng các mẫu chỉ có ở máy đang phục hồi; bật lại một rule rẻ hơn nhập lại cả danh sách) nhưng là hành vi người dùng có thể ngạc nhiên khi restore bản cũ.
* **LRU cap 3 của `QuickTranslationRuleBookStore` không còn làm đổi handle xoá**: thao tác từ màn Check rule dùng `pattern`, không dùng UUID snapshot. Rủi ro còn lại là tên rule đã được sửa/xoá ở nơi khác trước khi người dùng bấm hành động; store sẽ tìm theo pattern hiện tại và trả lỗi nếu không còn key đó trong file canonical.
* **Panel Copy gốc không có nút Hủy — mọi đường đóng đều copy** (chốt chủ dự án). Rủi ro là quấy rối chứ không phải mất dữ liệu: vô tình đóng panel (kéo xuống, tap ra ngoài) là dính clipboard nội dung đoạn đang chọn, và không có cách nào "chưa copy". Đã giảm bằng cách đóng → `showingCopyOriginalSheet = false` trước khi đọc `originalSentence` (không bao giờ copy khi panel đã đóng vì lý do khác) và pasteboard chỉ chứa xâu gốc.
* **Hiệu năng màn Check rule là ca đắt nhất của tính năng rule**: `diagnose` chạy matcher trên **cả đoạn** với cả hai bộ và `includesDisabled: true` — tức mọi rule đang tắt/bị token tắt cũng được thử, đắt hơn lượt rewrite thật (rewrite loại ngay trước matcher). Với bộ 17.278 rule chi phí vẫn theo quy luật ứng viên/dòng (tỉ lệ với chữ, không tỉ lệ với số rule) nhưng gấp ~2 lần rewrite; không khuyến nghị mở màn này trên đoạn cực dài. Giảm thiểu hiện có: bộ riêng thường vài chục rule, và màn chỉ mở khi người dùng bôi đen (đoạn ngắn).
* **Một nguồn khai tên file riêng truyện là quy ước mới phải giữ**: thêm một file riêng truyện (ví dụ từ điển mới) mà khai tên ở nơi khác không phải `TranslationManager+BookScopedFiles.swift` thì file đó âm thầm không vào backup và không đi theo truyện khi đổi nguồn — đúng loại bug im lặng mà lượt này vừa dọn khỏi hai chỗ đã biết (BackupPaths + SearchView). Kiểm bằng grep khi thêm file mới.
* **Đổi nguồn truyện trong `SearchView` phải `invalidate` đủ 4 chỗ** (BookStore × {bookId cũ, mới} + DisableStore × {cũ, mới}) — bỏ sót một phía là truyện mới đọc phải nguồn mới nhưng vẫn thấy bộ rule/tập tắt của nguồn cũ. Đã làm đủ 4 lời gọi; đây là chỗ dễ sót nhất khi người khác sửa sau này, nên được ghi lại thay vì để tự suy ra.
* **Ô Thử nhanh và màn Check rule giờ phụ thuộc file tắt** — người dùng sửa rule ở màn quản lý mà bối rối "sao không khớp" có thể đang bị file tắt chặn; đã giảm bằng dòng chú thích trong UI và badge "ĐÃ TẮT" trên hàng. Đây là thay đổi hành vi có chủ ý (trước đây ô thử bỏ qua mọi thứ trừ công tắc tổng/token) — màn soi phải nói đúng kết quả đọc thật.

## Rule dịch Quick Translate: engine, màn hình quản lý và công tắc (1.3.269)

* **Rủi ro cao nhất không nằm ở engine mà ở chỗ engine im lặng làm sai.** Rule sinh chuỗi Việt, phần Hán không khớp đi tiếp bằng đường cũ, nên một rule tồi cho ra **câu Việt sai nghĩa mà không lộ chữ Hán** — không có dấu hiệu nào để người dùng biết. Ba lớp chắn: token từ điển phải khớp entry thật (không nuốt bừa 1-12 chữ Hán như reference), boundary guard có điều kiện cho `<n>/<y>`, và ô thử nhanh ở màn quản lý (`QuickTranslationRuleTesterView`) để soi "rule nào khớp ở offset nào" trước khi tin.
* **Chưa biên dịch, và không có test nào phủ engine.** Toàn bộ xác minh lượt này là (a) đọc code, (b) hai script gate Python, (c) một bản **mirror thuật toán bằng Python** (script tạm, đã xoá) chạy trên ba bộ rule thật. Mirror chứng minh *thuật toán* đúng trên dữ liệu thật (633 / 1.175 / 17.278 rule, các ví dụ biên `三百五十米`, `十五级`, `第一章卷`, `一万亿`, group lồng, escape, token optional) nhưng **không** chứng minh bản Swift biên dịch được. Việc đầu tiên khi lên macOS: `xcodegen generate` + `xcodebuild build`.
* **Bẫy layout đã trả giá bằng crash thật (1.3.269, 5 file `.ips` giống hệt nhau): không bọc lazy container trong một hàng `List`.** `List` của iOS 16+ chạy trên `UICollectionView` + `UICollectionViewCompositionalLayout`; `LazyVStack`/`LazyHStack` bên trong một cell làm layout tự vô hiệu ngay giữa lượt cập nhật cell ⇒ `-[UICollectionView _updateVisibleCellsNow:]` đệ quy 7 lần rồi trap `EXC_BREAKPOINT` ở `_assertionFailure` trong `CA::Transaction::commit`. Muốn chặn danh sách dài thì **cắt dữ liệu** (`prefix(visibleLimit)`), đừng đổi kiểu container. Không cổng tĩnh nào bắt được lỗi này — `check_architecture.py` và `validate_links.py` đều không biết gì về layout.

* **Cap backtracking là lưới an toàn, không phải bảo đảm.** `QuickTranslationRuleMatcher.stepCap = 4.000` cho mỗi cặp (rule, vị trí bắt đầu). Với dữ liệu hiện có cap không bao giờ chạm (pattern ≤ 8 phần tử, `max ≤ 12`), nhưng một rule bệnh lý nhập từ ngoài vẫn có thể làm chậm — khi đó rule bị coi là không khớp và dòng của nó hiện ở `status.complexRuleLines`. Nếu thấy dòng nào ở đó, đọc lại rule chứ đừng nâng cap.
* **Lệch có chủ ý so với plan, cần chủ dự án biết**: plan §17 #5 chọn "rule chạy **trước** formatter tiêu đề chương". Bản này giữ formatter (`translateChapterTitle`) làm chủ tiền tố `第<n><L>` và chỉ áp rule cho phần còn lại của tiêu đề, vì rule `第<n:1-6><L> = {1} {0}` cho "Chương 1 mở đầu" trong khi formatter cho "Chương 1: Mở đầu" (có dấu hai chấm, có bảng đơn vị `chapterUnitMap`) — đổi thứ tự là đổi mọi tiêu đề chương ở Kệ/Mục lục/Reader. Muốn theo plan thì chuyển lời gọi `rewrite` lên đầu `translateChapterTitle`; đây là một chỗ sửa.
* **`wildcardCapacity` của token từ điển không khai range dùng 12 (như reference) chứ không dùng "độ dài entry dài nhất của từ điển"** như plan §7.2 mô tả: `TrieDictionary` chỉ expose `wordCount`, không expose độ dài entry lớn nhất. Đây là metric **tiebreak ưu tiên**, không phải điều kiện khớp, nên ảnh hưởng chỉ là thứ tự chọn giữa hai rule cùng `index` và cùng `literalLength`.
* **Nguy cơ hiệu năng còn mở**: chưa đo trên máy thật với bộ 17.278 rule. Số ứng viên/dòng đo được (18,0) nói tập ứng viên không tỉ lệ với số rule, nhưng chi phí dựng `QuickTranslationLiteralIndex.candidates` vẫn là O(số ký tự × kích thước bucket) cho **mỗi** chuỗi dịch, và `QuickTranslationDictionaryToken.resolve` gọi `TranslationManager.getBookDictionaries` mỗi lượt rewrite. Cần đo trước khi khuyến nghị nạp bộ 17k.
* **Rule `<pn>` KHÔNG đi theo công tắc `isTranslationPronounsEnabled`** (quyết định chủ dự án, đổi so với plan §17 #5b). Công tắc đó điều khiển việc *tra từ điển đại từ cho từng token* ở tokenizer; còn `<pn>` trong rule là ràng buộc của một rule người dùng chủ động viết, để nó im lặng không nổ vì một công tắc ở màn khác là hành vi khó hiểu. Hệ quả: bộ `Rule_new.txt` (16.941 rule `<pn>`) chạy **ngay khi nạp**, miễn `Pronouns.dat`/`.txt` có trên máy — rủi ro chuyển từ "không chạy gì" thành "chạy 16.941 rule chồng lấn với 8 tầng từ điển", nên vẫn cần đọc thử vài chương thật trước khi bật bộ đó. Từ điển `Pronouns` là optional nên `pronounsDict == nil` vẫn cho `DICT_TOKEN_WITHOUT_DICTIONARY` (mức `disabling`, không chặn nạp file).

## Rủi ro của lời nhắc chưa-đăng-nhập và của số đếm truyện đã xoá (1.3.268)

* **Chưa biên dịch, chưa kiểm trên máy thật**: viết trên Windows, không có `xcodebuild` lẫn `xcodegen` — nhưng lượt này **không thêm file Swift nào** nên không cần `xcodegen generate`. `check_architecture.py` giữ đúng **14 violation** (tập y hệt), `validate_links.py` PASS. Không dùng `Tests/` làm bằng chứng. CI xanh chỉ chứng minh *biên dịch được*.
* **Rủi ro chính của lượt này là quấy rối, không phải mất dữ liệu**: toast mới ở `.skipped(.driveNotLinked)` bắn **mà không ai bấm gì**, 25 giây sau khi mở app, và `ToastManager.show` ghi mọi toast vào hộp thư thông báo ⇒ mỗi lời nhắc còn để lại một badge chưa đọc. Giảm thiểu: chỉ bắn khi người dùng đã **tự bật** tự động sao lưu, và cửa `linkWarningCooldown = 24 h` đè lên số lần mở app. Ca xấu nhất còn lại: cài đè app/xoá `UserDefaults` làm mốc nhắc mất ⇒ nhắc lại một lần. Chấp nhận.
* **`GoogleDriveConfiguration.isConfigured == false` vẫn im lặng có chủ ý** (trả `.skipped(.notDue)`): build không nhúng client id là chuyện của người build, người dùng bấm gì cũng không sửa được — nhắc chỉ gây nhiễu. Hệ quả cần biết: trên bản build thiếu key, bật tự động sao lưu là **hoàn toàn** không có phản hồi nào.
* **Mốc nhắc và mốc sao lưu là hai khoá riêng** — nếu ai đó "gộp cho gọn" bằng cách gọi `markRun()` ở nhánh chưa-đăng-nhập, lỗi sinh ra rất khó thấy: đăng nhập xong vẫn không có bản sao lưu nào cho tới hết cooldown. Ghi lại vì đây là chỗ dễ refactor sai.
* **`pruneIncomplete` chỉ hạ mức toast, không làm lượt thất bại**: bản vừa upload luôn còn nguyên, nên `.succeeded` là đúng. Nhưng hệ quả tích tụ vẫn thật — Drive có thể vượt `maxVersions` bản tự động nếu `listBackups()` hoặc `delete(fileId:)` lỗi nhiều lượt liền, và **không có** cơ chế dọn bù nào ngoài lượt kế tiếp.
* **Số đếm truyện đã xoá giờ đúng, nhưng con số trong Cài đặt vẫn là ước lượng**: hàng "Sẽ bị xoá nếu dọn ngay" đọc `previewStaleCount` ở thời điểm khác với lúc xoá, nên nó có thể lớn hơn số thật (TTS bắt đầu phát giữa hai mốc). Toast sau lượt xoá mới là số chốt. Trước 1.3.268, `staleIds.count` bị dùng làm số báo và có thể nói "đã xoá N truyện" khi thật ra xoá ít hơn — nay không còn.
* **Vẫn còn một khoảng im lặng đã biết, cố ý không sửa lượt này**: xoá file vật lý (`.bin`, ChapterStore, cover) chạy trong `Task.detached` fire-and-forget; thất bại chỉ vào `failed_file_deletions_queue` và `drainRetryQueue` bỏ hẳn sau 3 lần, **không** báo gì. Nghĩa là truyện có thể mất khỏi DB mà file vẫn chiếm chỗ, không ai biết. Muốn báo được thì phải thêm một kênh báo cáo ra khỏi task nền — thay đổi lớn hơn phạm vi lượt này, nên chỉ ghi nhận.

## Rủi ro của lượt tự xoá truyện, sentinel số chương và backup từ điển TTS (1.3.263)

* **Chưa biên dịch, chưa kiểm trên máy thật**: viết trên Windows, không có `xcodebuild` lẫn `xcodegen` — **bốn file Swift mới nên bắt buộc chạy `xcodegen generate` trên macOS/CI trước khi build**. `check_architecture.py` giữ đúng **14 violation** (tập y hệt), `validate_links.py` PASS. Không dùng `Tests/` làm bằng chứng. CI xanh chỉ chứng minh *biên dịch được*.
* **Rủi ro nặng nhất của lượt này: xoá truyện là không hoàn tác được.** Không có thùng rác, không có tombstone — `BookStorageManager` xoá bản ghi DB, file `books/<sha>.bin`, mục lục trong `chapter_store.sqlite` và ảnh bìa. Bốn chốt độc lập chặn xoá oan: cờ bật/tắt **mặc định tắt** (khác hai policy nền kia, nên nâng cấp app không tự bật); truyện `isLocalBook` **luôn** được loại (không tải lại được từ mạng); truyện đang phát TTS / đang có widget nổi và truyện có task tải `.pending`/`.running` bị loại qua `protectedBookIds()`; và mốc so sánh là `Book.lastReadDate` chứ không phải ngày thêm vào tủ.
* **Chốt yếu nhất còn lại: `lastReadDate` của truyện chưa từng mở.** Nếu một truyện được thêm vào tủ mà chưa đọc dòng nào và `lastReadDate` mang ngày thêm (hoặc mốc rất cũ), nó **sẽ** bị coi là bỏ quên sau đúng ngưỡng ngày. Người dùng "tích truyện để dành" là ca gặp thật. Giảm thiểu hiện có: mặc định tắt, ngưỡng kẹp `7...365` ngày, số truyện sẽ bị xoá hiện ngay trong Cài đặt khi kéo thanh trượt, và `confirmationDialog` cho lượt bấm tay. Đây là điểm dừng thiết kế được báo lại, **không** tự thêm whitelist.
* **`markRun()` chạy trước phần việc** nên một lượt chết giữa đường (app bị kill, `deleteBooksAsync` throw) vẫn tiêu nhịp của ngày đó. Hướng lệch là "xoá ít hơn dự kiến" — cố ý, vì lệch ngược lại (xoá hai lượt liền) tệ hơn nhiều.
* **Thứ tự 25 s (sao lưu) trước 40 s (dọn) là giảm thiểu chứ không phải bảo đảm**: hai `.task` chạy song song, nên nếu lượt sao lưu kéo dài quá 15 giây thì việc xoá có thể bắt đầu khi bản sao lưu **chưa xong**. Truyện bị xoá lúc đó có thể thiếu trong archive của lượt ấy. Chấp nhận vì lượt sao lưu kế tiếp sẽ phản ánh đúng trạng thái, và truyện bị xoá vốn là truyện người dùng đã đồng ý bỏ.
* **`ChapterLimitOption` từ enum sang struct: mất tính vét cạn của `switch`.** Trước đây thêm case là compiler bắt mọi `switch`; giờ `rawValue` nhận **mọi** `Int` nên giá trị lạ trong DB không còn bị bắt lúc biên dịch. Bù lại: `limitValue` là cửa ra duy nhất và coi mọi `rawValue <= 0` là "không giới hạn", nên `-1` (sentinel `.custom`) hay số âm rác đều suy về hành vi `.all` an toàn. Đã kiểm bằng đọc: `-1` không bao giờ vào `enqueueTask` vì `startTask()` quy đổi trước, và `DownloadManager+TaskStore` bỏ được `?? .all` vì init không thất bại.
* **Từ điển phiên âm TTS phục hồi theo kiểu trộn, không ghi đè** (`mergeStringPlist`, `mergeReplacementRules`), nên **không có tombstone**: một mục người dùng đã xoá trên máy A sẽ **sống lại** sau khi khôi phục từ bản sao lưu cũ. Cùng hạn chế đã biết của các từ điển plist/JSON khác. Chọn trộn vì mất mục do ghi đè tệ hơn.
* **Ước tính dung lượng nhóm `.content` báo thiếu**: khi người dùng tắt `.content`, nội dung truyện local vẫn được sao lưu nhưng `BackupSizeEstimator` không có cách rẻ nào biết truyện nào là local (tên file là `sha256(bookId)`, phải mở SwiftData mới biết) nên con số hiện ra nhỏ hơn archive thật. `manifest.scopes` cũng không ghi `.content` trong ca này — khôi phục vẫn đúng vì `BackupRestoreWorker` quyết định theo `book.isLocalBook`, không theo scope. Hạn chế được ghi nhận, không sửa.


## Rủi ro của lượt dọn kho tiện ích, đầu dò cuộn và vệt tô tìm kiếm (1.3.261)

* **Chưa biên dịch, chưa kiểm trên máy thật**: viết trên Windows, không có `xcodebuild` lẫn `xcodegen` — **hai file Swift mới nên bắt buộc chạy `xcodegen generate` trên macOS/CI trước khi build**. `check_architecture.py` giữ đúng **14 violation** (tập y hệt), `validate_links.py` PASS. Không dùng `Tests/` làm bằng chứng. CI xanh chỉ chứng minh *biên dịch được*.
* **Rủi ro nặng nhất: lượt dọn xoá oan bản ghi tiện ích** — một lần fetch registry lỗi (mạng trả file trắng, kho đổi cấu trúc `plugin.json`) mà vẫn được coi là "kho đã gỡ hết" sẽ quét sạch danh sách của kho đó. Ba chốt độc lập chặn việc này: `syncExtensions` thoát sớm khi `items.isEmpty`; `pruneRepositoryExtensions` trả `.success(0)` khi `keepPackageIds` rỗng; và prune **chỉ** chạy khi upsert trả `.success`. Chốt yếu nhất còn lại: registry trả về **một phần** (ví dụ 3/40 `plugin.json` tải được) thì 37 bản ghi chưa cài **sẽ** bị xoá. Đánh đổi cố ý — bản ghi chưa cài chỉ là dòng danh sách, đồng bộ lại là có lại; nhưng nếu người dùng báo "tiện ích trong kho tự biến mất" thì đây là chỗ phải xem trước.
* **Tiện ích đã cài không bao giờ bị xoá** (`localPath` khác rỗng bị loại ở bộ lọc), nên không có đường nào làm truyện trong tủ mất nguồn. Rủi ro ngược lại là **rác**: tiện ích đã cài mà kho đã gỡ vẫn nằm trong danh sách mãi, không có dấu hiệu nào cho người dùng biết nó đã bị tác giả kho bỏ. Đây là điểm dừng thiết kế được báo lại, không tự cài.
* **Đầu dò cuộn có thể tắt cuộn-theo-highlight ngoài ý muốn** nếu recognizer nổ vì một cú kéo không phải "cuộn đọc" — nới vùng bôi đen là ca thật, đã chặn bằng `guard !showingFloatingMenu`. Ba guard còn lại (`!isAutoScrollDisabled`, `isTTSPlayingThisBook`, `!isRestoringReaderPosition`) chặn các ca máy-cuộn. Cờ chỉ có phạm vi phiên và bật lại được bằng một lần bấm ở header, nên hậu quả tệ nhất là một lần bấm — không mất dữ liệu.
* **Chiều rủi ro ngược của đầu dò: recognizer rò.** `UIScrollView` giữ recognizer strong và sống lâu hơn subtree chương, nên nếu `dismantleUIView` không chạy thì mỗi lần đổi chương để lại một recognizer chết. Giảm thiểu: `attach(to:)` idempotent theo identity + tự `detach()` trước khi gắn mới, cộng `deinit` làm lưới cuối. Chưa xác nhận bằng Instruments — chỉ bằng đọc code.
* **Vệt tô tìm kiếm có thể không hiện** khi chuỗi hiển thị không chứa truy vấn (bật/tắt dịch giữa lúc nhảy tới kết quả, hoặc `translated` chưa dựng xong). Đây là **chế độ suy giảm có chủ ý**: `searchHighlightRange(...)` trả `nil` và trang vẫn nhảy đúng đoạn. Rủi ro đã tránh được là nghiêm trọng hơn nhiều — cache `NSRange` vào state sẽ tô sai ký tự thay vì không tô.


## Rủi ro của bốn bộ ghi định dạng nhị phân (1.3.253)

* **Chưa biên dịch, chưa kiểm trên máy thật**: viết trên Windows, không có `xcodebuild` lẫn `xcodegen`. `check_architecture.py` giữ đúng **14 violation** (tập y hệt), `validate_links.py` PASS. Không dùng `Tests/` làm bằng chứng. CI xanh chỉ chứng minh *biên dịch được* — **không** chứng minh 3 file nhị phân mở được trên máy đọc thật.
* **Rủi ro cao nhất: MOBI.** Đây là format duy nhất trong đợt này phải tự dựng header nhị phân với offset tuyệt đối. Ba điểm dễ vỡ: (1) tổng độ dài MOBI header phải đúng **232 byte** — lệch một byte là `fullNameOffset = 16 + 232 + exth.count` trỏ sai và máy đọc hiện tên rác; (2) `filepos` của mục lục MOBI6 là **offset byte tuyệt đối trong toàn văn**, được đặt bằng chỗ trống 10 chữ số rồi vá tại chỗ khi copy — nếu độ dài chuỗi vá khác 10 thì mọi `filepos` sau nó lệch; (3) record cuối có thể ngắn hơn 4096 byte và `recordCount` (UInt16) chỉ tới 65535 nên sách > ~268 MB text bị `throw .sizeLimitExceeded` thay vì tạo file hỏng. Số học byte đã được kiểm tay, **chưa** được máy đọc nào xác nhận. Ghi **không nén** (`compression = 1`) là chọn có chủ ý: file to hơn nhưng bỏ được cả lớp lỗi LZ77/trailing-entry.
* **EPUB: ZIP tự viết là bề mặt rủi ro thứ hai.** `ZipStoreWriter` chỉ hỗ trợ stored (method 0) và **không** ZIP64 ⇒ vượt `UInt32.max` thì `throw .archiveTooLarge`. Ba chỗ phải khớp nhau tuyệt đối: CRC-32 mỗi entry, `localHeaderOffset` trong central directory, và số entry trong EOCD. Sai bất kỳ chỗ nào cho ra file mà một số máy đọc mở được và một số thì không — dạng lỗi khó chẩn đoán nhất, và không có test tự động nào (theo yêu cầu) để chặn.
* **Chính sách "xuất những gì có" là đổi hành vi có chủ ý, có thể gây bất ngờ.** Trước đây một chương lỗi là bỏ cả bản xuất; nay > 0 chương ⇒ `.completed` + dòng tổng kết `"Đã xuất X/Y chương (thiếu M, lỗi F)"`. Rủi ro: người dùng bỏ qua dòng cam và tưởng file đủ chương. Giảm thiểu: dòng tổng kết hiện **cả** trên tracker **và** trong toast, và bản xuất đủ chương thì không có dòng nào (nên sự xuất hiện của nó tự mang nghĩa cảnh báo).
* **`.exportReady` có thể tới lúc app ở background** ⇒ share sheet không trình bày được. Giảm thiểu: giữ pending + flush ở `scenePhase == .active`. Rủi ro còn lại: chỉ giữ **một** yêu cầu, nên hai bản xuất xong liên tiếp trong lúc app ở background thì chỉ bản sau được mở share sheet — file bản trước **không mất**, vẫn chia sẻ lại được từ tracker.
* **Không đổi schema là để tránh rủi ro lớn hơn.** Định dạng bền hoá bằng raw value mới của `TaskType` trong cột `taskTypeRaw` sẵn có. Đánh đổi đã biết: `exportStage`/`exportSummary` **mất** khi app khởi động lại (chỉ ở RAM) — tác vụ đã hoàn thành vẫn giữ `exportFilePath` nên nút chia sẻ lại còn hoạt động, chỉ dòng tổng kết thiếu chương là không còn. Thêm field cho việc này là **điểm dừng thiết kế được báo lại**, không tự cài, vì app không có `VersionedSchema`/`SchemaMigrationPlan` — chỉ lightweight migration ngầm.
* **Rác đĩa**: `.part` của mọi định dạng và file text tạm của MOBI. Cả hai có đường dọn tường minh (`discard()` ở mọi nhánh thoát, `defer` cho file tạm MOBI), và `ExportStagingFile.init` xoá `.part` sót lại trước khi tạo mới. Trường hợp bị kill giữa tác vụ: còn `.part`, **không bao giờ** còn một file ebook dở dang trông như hợp lệ.

## Rủi ro sau khi tối ưu xuất TXT, mục lục và từ điển (1.3.250)

* **Chưa biên dịch, chưa xác nhận runtime**: viết trên Windows, không có `xcodebuild` và không có `xcodegen`. `check_architecture.py` **16 → 14 violation** (tập con thật sự), `validate_links.py` PASS. Không dùng `Tests/` làm bằng chứng. CI xanh chỉ chứng minh *biên dịch được*.
* **Rủi ro nặng nhất: diff mục lục kết luận sai chiều "không đổi"** ⇒ chương mới không được lưu, người dùng mất chương. `ChapterTOCDiff.plan` vì vậy viết theo hướng bảo thủ: `incoming.count < existing.count` ⇒ `.full`; lệch bất kỳ field nào trong `(index, url, title, host)` ⇒ `.full`; `titleTrans` mới khác rỗng mà khác bản đang lưu ⇒ `.full`. Chỉ khi **mọi** hàng đầu trùng khớp mới trả `.unchanged`/`.appendOnly`. Hệ quả cần biết: nguồn đổi tiêu đề chương thành **chuỗi rỗng** hoặc `titleTrans` bị **xoá** ở phía online sẽ không được coi là thay đổi — đánh đổi cố ý, vì coi mất-dữ-liệu-phía-nguồn là thay đổi sẽ làm mọi lần refresh ghi lại toàn bộ.
* **Chương TTS được bảo vệ**: nếu `protectedTTS.bookId` khớp truyện đang lưu mà TOC mới không chứa chương đó (so theo `index` và `url` khi `url` khác rỗng), `plan` ép `.full` để đường xoá stale cũ chạy đúng logic bảo vệ sẵn có. Không có nhánh nào trong `.unchanged`/`.appendOnly` xoá hàng, nên chương đang phát không thể bị xoá ở hai nhánh đó.
* **Nhánh `.unchanged` không bump `updatedAt`** của hàng mục lục. Cột này chỉ được backup export/restore đọc, không ảnh hưởng đọc truyện — nhưng nghĩa là "lần cuối kiểm tra mục lục" không còn được ghi khi không có gì đổi.
* **Bỏ `fetchOrderedTOC` lần hai làm mất một lớp tự kiểm tra sau ghi.** `countChapters(bookId:)` giữ lại phần quan trọng nhất (đúng số hàng, O(1)) nhưng không còn đối chiếu từng field sau transaction. Checksum xác định (`computeDeterministicChecksum`) bị xoá hẳn: nó băm cả `id`/`isCached`/`offset`/`length` nên chưa bao giờ dùng lại được để so với TOC online, và không caller nào ngoài chính hàm đó đọc.
* **Coalesce `save()` của task**: nếu app bị kill giữa một tác vụ, `progressCount` trong DB lùi lại tối đa một cửa sổ coalesce. Không đổi hành vi resume/retry — `initialize(container:)` vẫn đánh mọi task `running`/`pending` thành `failed` khi khởi động lại. Throttle `@Published tasks` ~10 lần/giây làm counter nhảy bậc; giá trị cuối, bước đầu và mọi thay đổi trạng thái luôn được phát.
* **Ghi dần file TXT**: rủi ro để lại file dở trong `Documents/Exports/` nếu một nhánh lỗi nào bị bỏ sót. Giảm thiểu bằng cách chỉ ghi `<tên>.txt.part` và chỉ rename ở `finish()`, cộng `discard()` ở mọi nhánh huỷ/lỗi — trường hợp xấu nhất là còn một `.part`, không phải một `.txt` rỗng mà người dùng tưởng là bản xuất hợp lệ.
* **Bỏ hop MainActor kiểm cancel** chỉ đúng vì `activeTasks[taskId]` được gán ngay sau `Task.detached` và mọi đường huỷ đều gọi `handle.cancel()` trên MainActor ⇒ `Task.isCancelled` là đủ. Đây là **lệch có chủ ý so với plan**: plan dự tính đọc thêm một snapshot `Set<UUID>` của `cancelledTaskIds`, nhưng đọc `Set` đó từ task nền là truy cập không đồng bộ hoá — thêm rủi ro race để đổi lấy một tín hiệu đã có sẵn.
* **`BookBinManager` được cache đường dẫn thay vì mở sẵn handle** — cũng là lệch có chủ ý: một handle mang `FileHandle` không `Sendable` nên không đi qua ranh giới actor được. Cache `resolvedBinURLs` cho đúng phần tiết kiệm (một `sha256Hex` + một `validatePathSafety` + một kiểm migrate legacy cho mỗi truyện mỗi phiên) và có lợi cho **mọi** caller. Rủi ro: nếu file `.bin` bị xoá ngoài `deleteBinFile` thì cache giữ URL cũ — hiện `BookStorageManager` là điều phối viên duy nhất và nó đi qua `deleteBinFile`.
* **Bỏ `loadAllDictionaries()` khỏi đường sửa một từ**: an toàn vì `saveCustomEntry`/`deleteCustomEntry` chỉ ghi file TXT custom, không đụng `.dat`. Nhưng nếu sau này có thao tác nào **vừa** sửa custom TXT **vừa** thay `.dat` thì nó phải tự gọi `loadAllDictionaries()` — `reloadCustomDictionary` cố ý không chạm `.dat` lẫn `phienAmMap`. Race sẵn có không đổi: `TranslationManager` là `final class ObservableObject` thường và các dict bị ghi từ context ngoài main; bỏ reload dư **thu nhỏ** cửa sổ race chứ không mở rộng, và không sửa gốc trong phạm vi này.
* **Bỏ lần dịch lại tức thời ở `saveDefinition`** làm bản dịch cập nhật muộn hơn ~150 ms (debounce). Nếu một đường nào làm deferral bị kẹt thì chương sẽ **không** đổi — đã kiểm mọi cờ overlay đều có `onChange(false)` gọi `checkAndReleaseDeferredTranslationRefresh`, và `saveDefinition` cũng tự gọi ở cuối. Dấu hiệu hồi quy khi kiểm máy thật: `[ReaderPerf] TranslationRefresh … outcome=completed` phải xuất hiện **đúng một** lần cho mỗi lần bấm "Cập nhật".
* **`suggestionChips` thành `@State`** ⇒ phải được làm mới theo cả `bookId` và chuỗi chọn, nếu không sẽ hiện gợi ý của từ trước. Mọi điểm ghi đều truyền từ hiện tại và ghi đè toàn bộ mảng.
* **Tách file bằng `sed` là thao tác cơ học, không có bộ dịch để chặn lỗi**: `ShelfView+TXTImport.swift` được cắt nguyên khối rồi kiểm đối xứng dấu ngoặc so với `HEAD` (tổng của hai file bằng đúng của file gốc). Bốn hàm được gọi từ `ShelfView.swift` đã nâng lên `internal` vì `private` trong Swift là file-scoped — đây là loại lỗi mà chỉ bộ dịch mới bắt chắc chắn, nên CI là mắt kiểm tra thật sự.

## Rủi ro sau khi sửa mở thu nhỏ, nháy đỏ và tap mở lại (1.3.245)

* **Chưa biên dịch, chưa xác nhận runtime**: viết trên Windows, không có `xcodebuild`. `check_architecture.py` giữ đúng **18 violation** cũ, `validate_links.py` PASS. Không dùng `Tests/` làm bằng chứng.
* **Nguyên nhân lỗi "bấm widget thì widget mất mà trình duyệt không mở" chỉ được chẩn đoán bằng đọc code, và có nhiều hơn một nghi phạm.** Triệu chứng chỉ xảy ra được khi `isHidden` đã bị đặt `false` (widget hết điều kiện hiển thị) mà sheet không xuất hiện. Hai đường có thể dẫn tới đó đều đã bị bịt: (a) `findTopViewController()` nhặt window overlay của chính widget (`alert - 2`) hoặc của TTS (`alert - 1`) rồi present sheet vào đó, để `notifyStateChanged()` ngay sau đó ẩn window ⇒ nay chỉ nhận window `windowLevel == .normal`, ưu tiên window `isKeyWindow`; (b) `container` còn mắc parent là một `UINavigationController` bị bỏ dở nên nav mới không bọc lại được ⇒ `navigationController(wrapping:)` tái dùng nav cũ hoặc `removeFromParent()` trước khi bọc. Nếu trên máy thật vẫn còn lỗi thì nguyên nhân là đường thứ ba chưa biết — khi đó `verifyReopenPresented` đảm bảo người dùng vẫn còn widget để bấm lại, tức lỗi thoái hoá thành "bấm không ăn" thay vì "mất hết".
* **Lưới an toàn 1.2 s là hẹn giờ dựa trên thời gian, không phải tín hiệu UIKit**: nếu một ngày present pageSheet chậm hơn 1.2 s *và* `presentingViewController` chưa được gán (hiện UIKit gán ngay lúc gọi `present`, nên chưa có kịch bản nào như vậy), rollback sẽ ẩn oan trình duyệt vừa mở. Guard `self.navController === nav` chặn được trường hợp trạng thái đã đổi, không chặn được trường hợp giả định này.
* **`findTopViewController()` nay có thể trả `nil` ở nhiều tình huống hơn trước**: nếu scene không có window level `.normal` nào (chưa gặp — kể cả khi chạy qua LiveContainer, window chủ của app ở `.normal`), tap widget sẽ **không làm gì** thay vì present sai chỗ. Fallback cuối vẫn quét window `.normal` đang `isHidden` để không đóng cứng đường mở. Đây là đánh đổi cố ý: thà không mở còn hơn present vào window sẽ bị ẩn.
* **Khi cài đặt bật, tab nạp trong khi container chưa bao giờ được present.** Trước 1.3.245 lỗi bug-1 vô tình khiến container luôn được present, nên đường "webview off-window" chưa từng chạy thật. `webView.load` không cần window, nhưng WKWebView ngoài window có thể bị hệ thống điều tiết timer/JS, và các trang cần tương tác (captcha, Cloudflare) chỉ giải được sau khi người dùng bấm widget để mở lại. **Chưa xác minh runtime** — nếu extension nào phụ thuộc bypass tự động thì nên để cài đặt này **tắt** (mặc định vẫn tắt).
* **Đường lập trình không còn tự bung trình duyệt khi cài đặt bật**: extension gọi `load` lần thứ n trên loader đã có tab sẽ chỉ đổi tab đang hoạt động. Nếu extension nào dựa vào việc trình duyệt tự hiện lên để người dùng thao tác, hành vi đó nay biến mất — có ý (đúng đặc tả cài đặt), nhưng là thay đổi hành vi thật đối với extension.
* **Nháy đỏ đổi ngữ nghĩa thị giác**: viên pill nay đỏ đặc (alpha 1) khi có tab mở ≥ 10 s. Không còn dùng `opacity` nên `hitTest`/alpha của view container không đổi theo nhịp nháy; đổi lại màu đỏ dễ bị hiểu là "lỗi" chứ không phải "đang chạy". Đây là yêu cầu tường minh của người dùng.
* Các rủi ro của 1.3.244 còn nguyên hiệu lực, trừ mục nói nhịp nháy dùng `opacity`.

## Rủi ro của copy từ điển và widget trình duyệt kéo được (1.3.244)

* **Chưa biên dịch**: viết trên Windows, không có `xcodebuild`. Hai cổng tĩnh giữ nguyên (`check_architecture.py`: đúng 18 violation cũ; `validate_links.py`: PASS). CI xanh chỉ chứng minh *biên dịch được*. Không dùng `Tests/` làm bằng chứng cho bất cứ điều gì ở đây.
* **Copy là ghi đè trọn giá trị, không có undo**: `upsertEntry`/`saveCustomEntry` xoá key cũ rồi chèn key mới ở đầu file. Người dùng copy sai chiều sẽ **mất giá trị custom cũ ở đích** mà không có bước xác nhận nào (Menu chọn đích rồi thực thi ngay). Đây là hành vi được yêu cầu tường minh, nhưng nó là rủi ro dữ liệu thật — nếu sau này thêm cảnh báo thì đặt ở `DictionaryListView+Transfer.swift`, đừng đổi hai API ghi (chúng còn phục vụ đường thêm/sửa của `DictionaryListView`).
* **Ngữ cảnh sách phụ thuộc đúng một điểm truyền tham số**: `DictionaryHubView` là nơi duy nhất truyền `contextBookId`. Dựng `DictionaryListView(type:bookId: nil)` ở một call site mới mà quên `contextBookId` sẽ khiến icon chuyển ở danh sách chung im lặng chuyển sang trạng thái "không xác định được sách" (toast lỗi, không copy). Đó là fail-safe đúng hướng, nhưng là mắt yếu nhất của tính năng — hiện `DictionaryHubView` và `BookDictionaryView` vẫn là hai call site duy nhất.
* **Trình duyệt mở thu nhỏ ⇒ tab tải trong khi người dùng có thể không biết**: nhánh `prepareContainerMinimized()` attach `WKWebView` và bắt đầu tải mà không present. Rủi ro là dữ liệu/nền tiêu thụ mà không có UI đang hiển thị. Nút "N tab" và nhịp nháy là tín hiệu duy nhất; nếu tab đó cần tương tác (captcha, Cloudflare) người dùng phải tự mở lại. Cân nhắc nếu sau này bật cài đặt này làm mặc định — hiện mặc định là **tắt**.
* **Hai `UIWindow` overlay cùng lúc**: TTS widget ở `alert - 1`, trình duyệt ở `alert - 2`. Chỗ hai viên pill chồng nhau, TTS thắng hit-testing. Cả hai `hitTest` đều trả `nil` ngoài viên pill nên app bên dưới không bị chặn — nhưng đây là bất biến **phải giữ**: bất kỳ thay đổi nào làm `hitTest` trả `super.hitTest` cho toàn bộ bounds sẽ khoá cả app. `BrowserFloatingWidgetUIWindow` cố ý **không** có nhánh `presentedViewController != nil` như TTS (widget này không present gì); thêm `present` từ window đó về sau mà không thêm nhánh ấy là bug chờ sẵn.
* **Nhịp nháy dựa vào `createdAt` chứ không phải "tab chưa xem"**: một tab mở 30 s rồi thu nhỏ sẽ nháy ngay lúc thu nhỏ. Đúng đặc tả ("tính lại từ tuổi thật"), nhưng có thể gây cảm giác nháy dai nếu người dùng thu nhỏ/mở rộng liên tục — không có trạng thái "đã xem, thôi nháy".
* **`Timer.scheduledTimer` không chạy khi app ở background**: nếu ngưỡng 10 s trôi qua trong lúc app nền, timer nổ trễ khi run loop hoạt động lại. Chấp nhận được cho một hiệu ứng thị giác, nhưng đừng dùng monitor này cho việc gì cần độ chính xác thời gian.
* **`Views/Common/SizeReader.swift` nay là code chết** (consumer duy nhất là viên pill SwiftUI cũ). Giữ lại vì xoá nằm ngoài phạm vi yêu cầu; nó là ứng viên dọn ở lần sau.
* **Chưa xác nhận trên máy thật**: 16 test case người dùng nêu (4 tổ hợp mỗi chiều copy, chuỗi bật/tắt cài đặt thu nhỏ, ngưỡng nháy, kéo/snap/tap/passthrough, không hồi quy TTS widget) chỉ được kiểm bằng **đọc code**, không bằng chạy máy. Đặc biệt chưa xác nhận được bằng mắt: thứ tự z của hai window khi cả hai widget hiển thị cùng lúc, và cảm giác trễ khi kéo.

## Rủi ro của việc trả lại quan sát view model cho Reader (1.3.243)

* **Chưa biên dịch**: viết trên Windows, không có `xcodebuild`. Hai cổng tĩnh giữ nguyên (`check_architecture.py`: đúng 18 violation cũ, `ReaderView.swift` 2263 → 2268 vẫn là violation cũ; `validate_links.py`: PASS). CI xanh chỉ chứng minh *biên dịch được*.
* **Tăng số update pass của một view 2268 dòng**: từ nay **mọi** `@Published` của `ReaderViewModel` đều invalidate `ReaderView`, kể cả `currentProgress` (ghi mỗi 0.2 s khi cuộn) và `currentRevision`. Trước đây phần lớn thay đổi này im lặng — con số `updateUIView=151`/`contentSizeInvalidation=252` trong `[ReaderEnergy] Summary` gần như chắc chắn sẽ tăng. Đây là đánh đổi có chủ ý: lọc theo danh sách `@Published` là đúng loại bug vừa sửa (thêm state mới mà quên khai). Nếu cuộn bị giật sau thay đổi này, hướng xử lý là giảm nhịp ghi `currentProgress`, **không** phải bỏ relay.
* **Nguy cơ vòng lặp invalidate**: relay chỉ forward `objectWillChange`, không đọc/ghi state của view. Nếu ai đó ghi `@Published` của view model **trong** body hoặc trong `updateUIView` thì sẽ thành vòng lặp — trước 1.3.243 việc đó im lặng vô hại, nay thành vòng lặp thật. Không có điểm ghi nào như vậy hiện tại.
* **`observe(_:)` phải được gọi lại nếu `viewModel` bị dựng lại**: hiện chỉ có đúng một điểm gán (`ensureViewModel`), và relay so identity nên gọi lặp là vô hại. Thêm điểm gán `viewModel = …` ở nơi khác mà quên gọi `observe(_:)` là tái tạo lại đúng bug này — đây là mắt yếu nhất.
* **Chưa xác nhận trên máy thật**: giả thuyết được suy ra từ đường code cộng log thiết bị 2026-08-22 (khoảng lặng 0.6–4.3 s không có dòng log nào của Reader, trong khi TTS vẫn log và app vẫn nhận tap — tức main thread *không* bị chiếm). Cần một lượt log mới để chốt.
* **Chưa xử lý**: `prediction=reader_layout_churn_likely` và chi phí thật của một pass dựng subtree chương (`RepoLoad origin=extensionFetch ms=5051.59` là đường mạng, khác chuyện này).

## Rủi ro của cổng bắt tay skeleton (1.3.242)

* **Chưa biên dịch**: viết trên Windows, không có `xcodebuild`. Hai cổng tĩnh giữ nguyên (`check_architecture.py`: đúng 18 violation cũ; `validate_links.py`: PASS). CI xanh chỉ chứng minh *biên dịch được*.
* **Nguy cơ treo cổng nếu `onAppear` của skeleton không nổ**: cổng chỉ mở khi `skeletonHandshakeIndex == N`. Nếu skeleton đang hiển thị mà người dùng bấm tiếp sang chương khác, SwiftUI sẽ **không** chạy lại `onAppear` cho cùng một view — vì vậy nhánh skeleton mang `.id("chapter-skeleton-\(presentationIndex)")` để đổi chương là đổi identity. Đây là mắt yếu nhất của thiết kế: bỏ `.id` đó là mở lại đường treo ở chương cũ.
* **Thêm một frame trễ**: mỗi lượt đổi chương nay tốn thêm đúng một update pass (~16 ms) cho skeleton, cộng với nhịp 32 ms sẵn có. Đánh đổi có chủ ý: đổi tổng thời gian dài hơn một chút để lấy phản hồi tức thì.
* **Chỉ chữa cảm giác đơ, không chữa nguyên nhân của pass gộp**: chưa xác định được vì sao một pass vừa tháo vừa dựng hai subtree TextKit-1 lại tốn 1.6–3.5 s (giả thuyết: hai cây `UITextView` cùng sống trong một transition `.opacity` bọc bởi `withAnimation(.easeOut(0.12))`, cùng `contentSizeInvalidation=174`/`sizeInvalidationRPM=498.6` trong `[ReaderEnergy] Summary`). 1.3.242 chỉ bảo đảm pass gộp đó không còn xảy ra. `prediction=reader_layout_churn_likely` vẫn đúng và vẫn chưa xử lý.
* **Không đụng prefetch khi TTS sở hữu sách**: `setSpeculativePrefetchEnabled(false)` vẫn tắt N+1 của Reader, nên lượt tải lạnh thật (log có `RepoLoad origin=extensionFetch ms=2041`) vẫn dài như trước — chỉ khác là có skeleton suốt thời gian đó.

## Rủi ro còn lại sau lần sửa hạ cánh hai pha (1.3.241)

* **Chưa biên dịch**: thay đổi 1.3.241 viết trên Windows, không có `xcodebuild`. Chỉ hai cổng tĩnh chạy được (`check_architecture.py` giữ đúng 18 violation cũ, `validate_links.py`). CI xanh cũng chỉ chứng minh *biên dịch được*.
* **Giả định về timer 0.15 s**: pha hai (cuộn tới đoạn TTS) dựa vào việc `DispatchQueue.main.asyncAfter` không thể nổ khi main thread còn bận, nên nó luôn chạy *sau* khi chương đã present. Nếu một lượt dựng chương nào đó dài hơn và `onAppear` chưa kịp tiêu thụ target đầu chương, target sâu sẽ ghi đè và neo sâu lại được giải trong cùng layout pass — đúng hành vi cũ, không tệ hơn, nhưng cũng không được lợi.
* **Cửa sổ nhả cờ chồng nhau**: cú cuộn pha một hẹn nhả `isRestoringReaderPosition` sau 0.25 s, pha hai đặt lại cờ ở 0.15 s rồi hẹn nhả tiếp. Có ~0.1 s cờ bị nhả sớm giữa hai cú cuộn; hệ quả xấu nhất là một tick auto-scroll TTS trỏ đúng vào đoạn đang được cuộn tới, tức vô hại.
* **Chi phí cố định 32 ms/lượt điều hướng** (nhịp chờ frame) — đánh đổi lấy việc skeleton chắc chắn được present.
* **Không sửa nguyên nhân thời gian tải thật**: khi TTS sở hữu sách, `setSpeculativePrefetchEnabled(false)` tắt prefetch N+1 của Reader, nên Next/Prev lúc đang phát gần như luôn đi đường worker qua `ChapterContentRepository` (actor dùng chung với TTS). 1.3.241 làm chờ đợi đó *có phản hồi* (skeleton), **không** làm nó ngắn hơn. Nới điều kiện prefetch khi đang phát là quyết định năng lượng, chưa làm.

## Rủi ro của lần sửa đơ Next/Prev khi TTS đang phát (1.3.240)

* **Đã sửa, là bug thật chứ không phải tối ưu**: `restoreReaderPositionIfNeeded` thoát sớm mà không nhả `isRestoringReaderPosition`, khiến auto-scroll TTS và lưu tiến độ theo cuộn có thể chết im lặng tới hết session. Dạng lỗi không log, không crash, chỉ "tự nhiên không chạy nữa".
* **Rủi ro mới, mức thấp**: nay có thêm một frame skeleton chen giữa mọi lượt Next/Prev, kể cả khi nội dung đã ở RAM. Khi người dùng bấm rất nhanh, mỗi cú bấm huỷ `memoryCommitTask` trước đó nên chỉ chương cuối được commit — hành vi này dựa vào guard `request.generation == navigationGeneration`; sai guard là quay lại cảnh commit chồng.
* **Rủi ro còn nguyên, chỉ được đo chứ chưa sửa**: `ChapterContentRepository.shared` là một actor dùng chung giữa Reader và TTS, nên khi chương đích chưa cache, `load` của Reader có thể xếp hàng sau một lượt fetch chương của TTS. Log `[ReaderPerf] RepoLoad` thêm vào để lượng hoá đúng đường này; đường đó **có** skeleton nên nó không phải triệu chứng đang báo.
* **Không đo được tại chỗ**: host là Windows, `xcodebuild` chỉ chạy trên macOS. Mọi kết luận ở trên là đọc code cộng `check_architecture.py` (giữ đúng 18 violation, tập vi phạm y hệt), không phải profiling.

## Rủi ro của phép tách file (1.3.236)

| Rủi ro | Severity | Likelihood | Ghi chú |
|---|---|---|---|
| Type `private` rời file gốc làm rộng phạm vi truy cập ngoài dự kiến | Low | — | Chỉ 2 trường hợp (`SizeReader`, `BookTitleTranslationBackfill`), cả hai lên internal (trong module) chứ không public. Không có consumer mới nào được thêm. |
| Tách sai biên khối làm mất/nhân đôi code | High | **Low** | Cắt bằng brace-matching có bỏ qua string/comment, sau đó đối chiếu cân bằng ngoặc của 10 file gốc với `HEAD`: giống nhau tuyệt đối. 14 file mới đều cân bằng 0. |
| Line-ending sai ở file mới | Medium | — | **Đã xảy ra và đã sửa**: lần ghi đầu dùng `newline=CRLF` trên nội dung vốn đã CRLF nên thành `\r\r\n`, khiến gate đọc `TabbedVisibleBrowserViewController.swift` thành 402 dòng (gấp đôi 201). Đã chuẩn hoá toàn bộ 14 file về LF cho khớp phần còn lại của repo. |
| Còn 16 `LINE_LIMIT_EXCEEDED` chưa xử lý | Medium | — | Không giải được bằng tách type (các file này chỉ có 1 type); cần tách **thành viên** sang file `X+Feature.swift`. Nợ lớn nhất: `TTSManager.swift` (4003, cần ≤3470), `JSExecutor.swift` (1514, cần ≤1066), `ReaderView.swift` (2250, cần ≤2053). |
| 2 `VIEW_SWIFTDATA_MUTATION` thật vẫn còn | Medium | — | `DiscoveryView.swift`, `ReaderView.swift`. Sửa đúng cách phải chuyển ghi qua `BookTransactionCoordinator`/`ExtensionTransactionCoordinator` — đổi quyền sở hữu transaction, không phải dọn dẹp cơ học, nên tách thành quyết định riêng. |
| Chưa biên dịch cục bộ | Medium | — | Máy Windows; xác minh compile dựa vào CI trên macOS. 14 file mới + 10 file sửa đều chưa qua compiler tại thời điểm commit. |

## Rủi ro của lần dọn code chết (1.3.235)

| Rủi ro | Severity | Likelihood | Ghi chú |
|---|---|---|---|
| Xoá symbol mà một đường gọi động (JS bridge, `#selector`, delegate) vẫn cần | High | Low | Đã loại trừ có phương pháp: bỏ qua toàn bộ `Services/Extensions/Engine/JS*` (API mà extension JavaScript gọi theo tên), bỏ qua conformance delegate, và đếm tham chiếu theo **tên trần** nên hàm truyền dạng closure/`#selector` vẫn được tính. Đã kiểm tra không symbol nào là protocol requirement. |
| Mất vĩnh viễn 20 file test | Medium | — | Xoá bằng `git rm` nên phục hồi được từ git history; đây là quyết định trực tiếp của người dùng, không phải suy đoán. |
| Còn code chết dây chuyền sau khi xoá | Low | Low | Đã quét lại sau khi dọn: 0 hàm `public`/`internal` không tham chiếu (đợt hai đã xoá thêm `ModelStore.readCachedVoices`/`writeCachedVoices`/`voicesCacheURL` vốn chỉ phục vụ hàm vừa xoá). Type duy nhất còn báo là `FreeBookApp` (`@main`, false positive). |
| Chưa kiểm chứng bằng biên dịch | **High** | — | Đây là lần thay đổi rộng nhất (5 file xoá, 1 đổi tên, ~30 symbol, 20 file source đụng tới) và vẫn **chưa build được** vì máy là Windows. Bắt buộc `xcodegen generate` + build trên macOS trước khi coi là xong. |

## Next-chapter prefix audio risks (1.3.234)

| Rủi ro | Severity | Likelihood | Ghi chú |
|---|---|---|---|
| Lệch index giữa chunk prefix và `paragraphs` ⇒ audio và highlight desync | High | **Very Low** | Chặn hai lớp: `consume(matching:)` yêu cầu key trùng tuyệt đối, **và** `mergeNextChapterPrefixAudio` so `PreparedChunk.finalText` với `applyReplacements(paragraphs[index].text)`. Không khớp ⇒ **bỏ** chunk (log `textMismatch=M`) chứ không bao giờ phát sai đoạn. Lớp thứ hai phủ cả trường hợp DTO bị dựng lại với key không đổi (fallback load / force-refresh nội dung chương kế). |
| Tổng hợp đầu cơ tốn request/pin khi người dùng dừng ngay sau đó | Medium | Medium | Prefix luôn ở mức ưu tiên thấp nhất, tuần tự 1 operation; `pause()` hủy phần đang bay, `stop` giải phóng toàn bộ. Với `googlePrefetchCount` lớn (tối đa 10), capacity ở chunk cuối chương có thể lên tới `count - 1` request. |
| Chunk prefix cũ lưu lại sau khi đổi `pitch` của Google (đường `pitch.didSet` không gọi `clearPrefetchCache`) | Low | Medium | Chỉ là RAM tạm (tối đa `count - 1` payload); dữ liệu bị loại ở `request` kế tiếp hoặc `consume` do key khác. Không có nguy cơ phát sai pitch. |
| NghiTTS đếm payload thiên về bảo thủ (`preloadedData.count + hasPreparedNext + reservesNghiAudioSlot`) nên có thể đếm trùng một payload và cấp capacity nhỏ hơn thực tế | Low | Medium | Cố ý: sai theo chiều **không vượt** `maxTotalAudioPayloads = 5`. Hệ quả xấu nhất là prefix ít hơn 1 chunk ở một vài nhịp; watermark tự đánh giá lại ở sự kiện kế tiếp. |
| Watermark 8s có thể vẫn không đạt nếu trần 5 payload hết chỗ (chunk quá ngắn) | Low | Low | Đây là giới hạn thiết kế đã chọn (không nới trần RAM). Muốn đảm bảo đủ 8s trong mọi trường hợp thì phải nâng `NghiSynthesisPolicy.maxTotalAudioPayloads` — là thay đổi quy chuẩn, cần quyết định riêng. |
| Prefix của NghiTTS xếp hàng nhiều task cùng lúc (tối đa `capacity`), khác `canScheduleNghiRefill` "một refill in-flight" của cửa sổ đoạn văn | Low | Medium | **Sai lệch có chủ ý**: `PiperSynthesisCoordinator` vẫn chỉ chạy 1 inference tại một thời điểm và prefix ở mức `.optionalReserve` (thấp nhất), nên đây là độ sâu hàng đợi chứ không phải song song hoá. Đổi sang 1-in-flight sẽ khiến buffer chỉ lấp được 1 chunk mỗi nhịp chuyển đoạn — quá chậm ở 1-2 chunk cuối chương. |
| `sessionID`/`ttsProcessingGeneration` không nằm trong identity của prefix (chỉ có `TTSPreparedNextChapterKey`) | Low | Low | **Tính chất dùng chung với `TTSChapterPrefetcher`** (chunk 0 cũng vậy) nên không phải sai lệch riêng của thay đổi này. Cùng book/chapter/url/cấu hình ⇒ audio giống nhau, và `stopPlayback`/đổi engine/đổi giọng đều đi qua `clearAllTTSCaches`. Muốn siết thì phải siết cả hai owner cùng lúc — chưa làm. |
| Chưa kiểm chứng bằng biên dịch | Medium | — | Thay đổi được viết trên Windows; `xcodebuild` chỉ chạy trên macOS. Cần build + kịch bản nghe qua biên chương trên máy thật trước khi coi là đã xác minh. |

## Search-history live-suggestion risks (1.3.191)

* **Residual - UI only, no logic change:** the live-filtered history suggestions reuse the existing history row UI in `ShelfSearchView`/`SearchView`; no shared-store or search logic changed, so risk is limited to layout. In `ShelfSearchView` the suggestion block is capped at 220pt to avoid starving the results list height.
* **Residual - Windows cannot build/test at the moment; iOS build and XCTest verification happens via CI or a Mac.**

## Shelf search & title-translation backfill/refresh risks (1.3.190)

* **Mitigated - stale/empty translated names:** `Book.titleTrans`/`authorTrans` are backfilled at app launch once dictionaries are loaded and refreshed every time a book is opened (`ReaderView` bootstrap and `BookDetailView` `.task`); per-session additions and dictionary/custom-dict changes reach the DB without waiting for the next launch, and refresh only writes when the value changes (no redundant save churn).
* **Residual - dictionaries not ready at launch:** `runIfNeeded` guards on `TranslationManager.shared.isVietPhraseLoaded` and skips silently when dictionaries are not yet loaded; the refresh-on-open path covers those books when first opened, and the backfill retries on the next launch.
* **Residual - Windows cannot build/test at the moment; iOS build and XCTest verification happens via CI or a Mac.**

## removeDuplicatedTitle config risks mitigated in 1.3.189

* **Mitigated - Reader/TTS drift on duplicated chapter title:** per-book toggle `removeDuplicatedTitle_<bookId>` (default ON, shared by Reader + TTS) drops the first content line only when it matches an active TOC rule via the same `TranslateUtils.isChapterHeaderLine` used by TXT import; both sides keep the same stable line IDs after the drop so highlight/TTS sync stays aligned.
* **Residual - detection depends on active TOC rules:** if no TOC rule matches (or rules are disabled), the duplicated title is kept; the toggle is a display convenience, not a guaranteed dedupe.
* **Residual - Windows cannot build/test at the moment; iOS build and XCTest verification happens via CI or a Mac.**

## AVAudioSession -50 (BadParam) resolved in 1.3.180

* **Resolved - invalid category/option combination:** `TTSAudioSessionController.configureAudioSession()` called `setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .allowBluetooth, .allowBluetoothA2DP])`. `.allowBluetooth` (HFP) is documented valid only with `.record`/`.playAndRecord`/`.multiRoute`, so `setCategory` threw `OSStatus -50` (`AVAudioSessionErrorCodeBadParam`). The subsequent `setActive(true)` in the same `do` block never ran, `isAudioSessionConfigured` stayed `false`, and the error was re-logged on every paragraph/chapter play (observed during Google TTS auto-advance to chapter 2).
* **Fix:** removed `.allowBluetooth`, keeping `.duckOthers` + `.allowBluetoothA2DP` (both valid with `.playback`). The log now also records the underlying OSStatus code for future diagnosis.
* **Residual:** playback still worked while the bug existed because `AVAudioPlayer.play()` implicitly activates the session, but the intended `.playback`/`.spokenAudio` configuration (background playback, ducking, Bluetooth A2DP routing) was not applied.

## NghiTTS chapter-transition crash risks mitigated in 1.3.147

* **Mitigated - empty preprocessor output:** Piper kiểm tra cả input và output tiền xử lý; output không thể đọc được chuyển thành WAV khoảng lặng hợp lệ thay vì làm eSpeak/ONNX ném lỗi.
* **Mitigated - refill failure feedback loop:** failure state được khóa theo session/chapter/paragraph, tối đa hai attempt và cooldown 1 giây; scheduler không thể thử lại sớm qua callback khác.
* **Mitigated - stale cancellation state:** cancellation tách khỏi generic failure path, context/generation được kiểm tra trước mutation và reset hủy retry task nên task cũ không thể hồi sinh state đã xóa.
* **Residual risk:** Windows chỉ xác nhận parser/static checks; iOS build và XCTest đầy đủ vẫn cần macOS/Xcode hoặc CI trước khi phát hành.

## NghiTTS safeCachedTimeThreshold prefetch risks mitigated in 1.3.141

* **Mitigated - cancel/re-synthesize feedback loop:** `PiperSynthesisCoordinator` deduplicates exact `synthesisKey` requests and appends waiters. Detaching one waiter or pausing does not cancel an active ONNX inference.
* **Mitigated - non-contiguous cache undercount:** `calculateNghiCachedTime()` measures contiguous playable duration stopping at the first missing gap, preventing excess synthesis while correctly accounting for prepared $N+1$ items.
* **Mitigated - Settings resume work loss:** opening/closing Settings with snapshot equality (`onlyThresholdChanged = true`) resumes playback without stopping or clearing valid preloaded audio.
* **Mitigated - thermal prefetch cancellation:** thermal state remains diagnostic/logging telemetry only and does not cancel audio refills.

## Chapter memory and obsolete-work risks mitigated in 1.3.114

* **Mitigated - app-lifetime normalized chapter growth:** shared repository RAM is bounded by both 12 entries and 12 MiB estimated cost, with immediate memory-warning trimming and oversized-document bypass.
* **Mitigated - cancellation-insensitive shared waiters:** Reader/TTS retain per-consumer continuations. Canceling one no longer blocks that caller until unrelated shared work completes, while final-subscriber cancellation reaches the extension task.
* **Mitigated - orphaned fallback auto-advance:** TTS now owns and generation-guards the load/process task; stop/session replacement/newer advance cancels it and cancellation cannot be misreported as a fatal playback load error.

## TTS foreground energy risks mitigated in 1.3.112

* **Mitigated - widget display-rate work:** the global floating cover no longer drives a 30 FPS SwiftUI timeline while playback continues across Reader/Discovery/Shelf.
* **Mitigated - broad TTS view invalidation:** app root, Shelf, widget, and Reader no longer observe every published manager field. Deduplicated projections suppress unrelated paragraph/highlight/download/timer updates; another book's highlights cannot invalidate the visible Reader.
* **Mitigated - repeated Lock Screen static work:** translated titles, local cover decode, and artwork construction are cached per static identity and coalesced behind one cancelable task. Paragraph transitions update only dynamic timeline fields.
* **Mitigated - unconditional Nghi warm-up:** Siri/Google/Ext app launches no longer prepare the Piper model; Nghi selection owns the lazy warm-up lifecycle.

## Web-extension engine risks mitigated in 1.3.39

* **Deadlock mitigation**: The `waitForReady` JS bridge checks `Thread.isMainThread` and returns a failed JSON readiness DTO immediately instead of waiting on the semaphore, preventing application deadlock.
* **WKWebView Cookie privacy limitation**: Since WKWebView Loader uses the default configuration, cookies are persistent and shared within the app's default WKWebsiteDataStore, representing a privacy constraint due to lack of per-extension/session isolation.

## Reader risks mitigated in 1.3.10

* **Mitigated - stale rendered window:** the vertical reader now advances `stableIndexes` together with the active chapter window, preventing a permanent stop at the initial `n+2` boundary.
* **Mitigated - extension fetch overlap:** `ReaderPrefetchGate` enforces one global two-request cap across Reader instances. Repository waiters now leave immediately on cancellation and cancel the underlying extension task when no Reader/TTS consumer remains, while a still-shared operation retains its gate slot until completion.
* **Mitigated - hidden overlay work:** chapter-list queries and eager full-list title translation no longer run throughout ordinary reading and TTS updates. TTS full-queue metadata refresh is owned by `TTSManager` and uses background SwiftData for local books.
* **Mitigated - large TOC jump latency:** opening the chapter list positions directly at the current row without animating through all preceding chapters and reuses Reader-owned SwiftData objects.
* **Mitigated - shelf/discovery tab swipe jank:** Shelf rows no longer scan chapter relationships while rendering, and Discovery keeps only the selected category page plus adjacent pages fully mounted during horizontal paging.
* **Mitigated - anti-bot request burst:** a jump loads only its target; speculative next-chapter loading waits for target completion and a stable selection. Rapid updates coalesce pending chapters.

## 1. Bảng Tổng hợp Rủi ro (Risk Summary Table)

| ID | Loại Rủi ro | Vị trí (Source File) | Severity | Likelihood | Related Documents |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **R-01** | **Deadlock cứng hệ thống** | [JSExecutor.swift](../../Sources/Services/Extensions/Engine/JSExecutor.swift#L442-L458) | **Critical** | **Medium** | [13_resource_lifecycle.md](13_resource_lifecycle.md), [11_subsystems.md](11_subsystems.md) |
| **R-02** | **Rò rỉ tài nguyên ngầm** | [JSExecutor.swift](../../Sources/Services/Extensions/Engine/JSExecutor.swift#L9) | **High** | **High** | [12_ownership_graph.md](12_ownership_graph.md), [13_resource_lifecycle.md](13_resource_lifecycle.md) |
| **R-03** | **Lỗi Concurrency SwiftData** | Các ViewModel & Manager | **High** | **Medium** | [09_dependency_rules.md](09_dependency_rules.md), [13_resource_lifecycle.md](13_resource_lifecycle.md) |
| **R-04** | **Lỗi hồi phục AVAudioSession** | [TTSManager.swift](../../Sources/Services/TTS/TTSManager.swift#L3939) | **Medium** | **Medium** | [13_resource_lifecycle.md](13_resource_lifecycle.md), [11_subsystems.md](11_subsystems.md) |
| **R-05** | **Strong Reference Cycle trong callback AVAudioPlayer** | [TTSManager.swift](../../Sources/Services/TTS/TTSManager.swift#L986) | **Medium** | **Low** | [12_ownership_graph.md](12_ownership_graph.md), [04_call_graph.md](04_call_graph.md) |
| **R-06** | **Rò rỉ subscription cảnh báo** | [ReaderViewModel.swift](../../Sources/Views/Reader/ReaderViewModel.swift#L125) | **Low** | **Low** | [08_lifecycle.md](08_lifecycle.md) |
| **R-07** | **Race Condition xử lý nền TTS** | [TTSBackgroundProcessor.swift](../../Sources/Services/TTS/TTSBackgroundProcessor.swift#L13) | **Medium** | **Low** | [05_state_graph.md](05_state_graph.md), [07_dataflow.md](07_dataflow.md) |

---

## 2. Chi tiết các Rủi ro kỹ thuật

### R-01: Nguy cơ Deadlock hệ thống khi khởi chạy Trình duyệt ngầm
*   **Vị trí**: [JSExecutor.swift](../../Sources/Services/Extensions/Engine/JSExecutor.swift#L442-L458) bên trong `browserLaunchBlock`.
*   **Mức độ nghiêm trọng (Severity)**: **Critical** (Khiến ứng dụng bị đóng băng hoàn toàn và bị hệ điều hành iOS kill sau vài giây).
*   **Khả năng xảy ra (Likelihood)**: **Medium** (Xảy ra bất cứ khi nào mã JavaScript của Extension gọi phương thức `Engine.newBrowser().launch(...)` trên Main Thread).
*   **Nguyên nhân**:
    *   `browserLaunchBlock` sử dụng `DispatchSemaphore` để chặn luồng hiện tại và chờ kết quả tải trang HTML.
    *   Đồng thời, nó đẩy tác vụ tải trang WebView lên Main Thread bằng `DispatchQueue.main.async`.
    *   Nếu bản thân khối `browserLaunchBlock` được gọi từ Main Thread, Main Thread sẽ bị Semaphore khóa cứng. Khi đó, khối load WebView trong `DispatchQueue.main.async` không bao giờ được thực thi, dẫn đến hiện tượng **Deadlock vĩnh viễn**.
*   **Giải pháp (Mitigation)**:
    *   Không được dùng `DispatchQueue.main.async` kết hợp chặn đồng bộ bằng Semaphore.
    *   Chuyển hoàn toàn việc tương tác này sang cơ chế `async/await` phi chặn (non-blocking) bằng cách chạy JS Engine trên một background thread chuyên biệt hoặc sử dụng `withCheckedContinuation` không dùng Semaphore.

---

### R-02: Rò rỉ bộ nhớ WKWebView (Resource Leak) do JavaScript crash
*   **Vị trí**: Từ điển `activeBrowsers` trong [JSExecutor.swift](../../Sources/Services/Extensions/Engine/JSExecutor.swift#L9).
*   **Mức độ nghiêm trọng (Severity)**: **High** (WKWebView tiêu tốn rất nhiều tài nguyên RAM, gây crash app do cạn bộ nhớ - Out Of Memory).
*   **Khả năng xảy ra (Likelihood)**: **High** (Do các Extension JS của bên thứ ba viết thường phát sinh lỗi ngoại lệ hoặc crash giữa chừng và không gọi hàm `close()`).
*   **Nguyên nhân**:
    *   Khi JS khởi tạo browser qua `Engine.newBrowser()`, một `WebViewLoader` được lưu vào từ điển `activeBrowsers`.
    *   Nếu đoạn mã JavaScript gặp lỗi giữa chừng và dừng thực thi trước khi gọi `browser.close()`, phần tử trong `activeBrowsers` sẽ không bao giờ được xóa, khiến thực thể `WKWebView` bị treo vĩnh viễn trong RAM.
*   **Giải pháp (Mitigation)**:
    *   Bổ sung cơ chế tự hủy (Timeout) cho `WebViewLoader`. Nếu sau một khoảng thời gian (ví dụ: 60 giây) không có hoạt động, tự động đóng và giải phóng WebView.
    *   Đảm bảo giải phóng toàn bộ `activeBrowsers` trong hàm `deinit` của `JSExecutor`.

---

### R-03: Tranh chấp dữ liệu (Data Race) & Lỗi Context của SwiftData
*   **Vị trí**: Tiến trình ghi đĩa đồng thời trong `DownloadManager` và `ReaderViewModel`.
*   **Mức độ nghiêm trọng (Severity)**: **High** (Gây crash ứng dụng khi ghi đĩa hoặc đọc thực thể từ thread sai).
*   **Khả năng xảy ra (Likelihood)**: **Medium**.
*   **Nguyên nhân**:
    *   SwiftData yêu cầu các thực thể `@Model` (như `Book`, `Chapter`) chỉ được truy cập trên đúng luồng của `ModelContext` đã fetch chúng.
    *   Nếu background thread của `DownloadManager` tải truyện xong và lưu vào DB, nhưng Main Thread cùng lúc đang đọc để hiển thị, hoặc nếu ta truyền thực thể `@Model` qua lại giữa các luồng, SwiftData sẽ ném ngoại lệ crash.
*   **Giải pháp (Mitigation)**:
    *   Luôn tạo `ModelContext` riêng cho background thread.
    *   Khi cần truyền thực thể, chỉ truyền `bookId` hoặc `chapterId` (PersistentIdentifier) và fetch lại trên thread đích, tuyệt đối không truyền instance thực thể.

---

### R-04: Thất bại khi kích hoạt lại AVAudioSession sau cuộc gọi (Interruption)
*   **Vị trí**: Lắng nghe sự kiện ngắt tại [TTSManager.swift](../../Sources/Services/TTS/TTSManager.swift#L3939) (`setupInterruptionObserver`).
*   **Mức độ nghiêm trọng (Severity)**: **Medium** (Giao diện hiển thị đang phát nhưng không có tiếng ra loa).
*   **Khả năng xảy ra (Likelihood)**: **Medium** (Phổ biến khi người dùng nghe truyện bằng tai nghe Bluetooth và nhận cuộc gọi).
*   **Nguyên nhân**:
    *   Khi cuộc gọi kết thúc, hệ thống gửi thông báo kết thúc ngắt (`.ended`). Tuy nhiên, tại thời điểm này, hệ điều hành iOS có thể chưa hoàn toàn trả lại tài nguyên âm thanh.
    *   Việc gọi ngay lập tức `AVAudioSession.sharedInstance().setActive(true)` có thể thất bại, khiến AudioEngine không thể start lại.
*   **Giải pháp (Mitigation)**:
    *   Thực hiện thử lại (Retry) với độ trễ ngắn (ví dụ: trì hoãn 0.5 giây trước khi setActive lại).
    *   Kiểm tra kỹ kết quả trả về của hàm `setActive`.

---

### R-05: Strong Reference Cycle trong callback của AVAudioPlayer
*   **Vị trí**: Wiring callback phát audio [TTSManager.swift](../../Sources/Services/TTS/TTSManager.swift#L986) (`configureNghiAudioPlayerQueueCallbacks`) và delegate `audioPlayerDidFinishPlaying`.
*   **Mức độ nghiêm trọng (Severity)**: **Medium** (Rò rỉ bộ nhớ của TTSManager).
*   **Khả năng xảy ra (Likelihood)**: **Low** (Do đã được giảm thiểu).
*   **Ghi chú cập nhật**: Đường phát **không** dùng `AVAudioPlayerNode.scheduleBuffer` — repo hiện không có lệnh `scheduleBuffer` nào và `TTSAudioEngineController.play()` không có caller. Rủi ro retain cycle thực tế nằm ở các closure callback của `AVAudioPlayer`/`NghiAudioPlayerQueue` và block `DispatchQueue.main.async` lồng bên trong.
*   **Nguyên nhân**:
    *   Callback hoàn tất phát (`audioPlayerDidFinishPlaying`) và các completion closure của `NghiAudioPlayerQueue` chạy ngoài Main Actor.
    *   Nếu closure lồng `DispatchQueue.main.async` mà không capture lại `[weak self]`, có thể vô tình giữ chặt `self` trong Main Queue khi manager/session bị thay thế.
*   **Giải pháp (Mitigation)**:
    *   Đảm bảo capture `[weak self]` ở cả callback ngoài lẫn block `DispatchQueue.main.async` lồng bên trong; giải phóng `audioPlayer = nil` khi stop.

### R-07: Race Condition khi xử lý chuẩn hóa và dịch văn bản chạy nền
*   **Vị trí**: [TTSBackgroundProcessor.swift](../../Sources/Services/TTS/TTSBackgroundProcessor.swift#L13), [TTSManager.swift](../../Sources/Services/TTS/TTSManager.swift#L318)
*   **Mức độ nghiêm trọng (Severity)**: **Medium** (Có thể phát sai chương hoặc lỗi hiển thị).
*   **Khả năng xảy ra (Likelihood)**: **Low** (Do đã được giảm thiểu).
*   **Nguyên nhân**:
    *   Các tác vụ CPU-heavy (dịch Vietphrase, tách đoạn) được đẩy xuống actor chạy nền `TTSBackgroundProcessor` bất đồng bộ.
    *   Prewarm và thao tác Start có thể chồng lấp nếu người dùng bấm phát đúng lúc Reader đang chuẩn bị nội dung.
    *   Tác vụ cũ hoàn thành trễ hơn có thể đè đè dữ liệu mới nếu không được kiểm tra.
*   **Giải pháp (Mitigation)**:
    *   Mỗi request dùng một processor riêng thay vì chờ hàng đợi actor singleton; task cũ được hủy và processor kiểm tra cancellation giữa các giai đoạn.
    *   Cache prewarm có key gồm sách, chương, nội dung, chunk length và cấu hình tiêu đề; kết quả stale bị loại bằng generation/session guard.

---

#### Reader/TTS unified pipeline (2026-07)

- `ChapterTextNormalizer` is the single source for LF newlines, trimmed non-empty lines, **sparse paragraph IDs (`ChapterTextLine.id` is the raw line index and counts blank lines, so IDs are not array offsets and must be looked up by `id`, never used as an array index)**, and UTF-16 ranges. Because those ranges are computed before blank lines are dropped, `ChapterTextLine.utf16Range` must not be used to slice `NormalizedChapterText.content`. `ChapterContentRepository` produces one normalized `ChapterDocument` for both Reader and TTS.
- Reader uses `ReaderLoadState` with bootstrap retry/clamping, typed failures, generation checks, cache-first rendering, and a short opacity crossfade only for newly fetched content. `ReaderRoute.chapterIndex` preserves the selected TOC index through navigation.
- `TTSParagraphBuilder` chunks normalized lines without renumbering parent paragraph IDs; replacement output is checked before synthesis. TTS asynchronous work is guarded by session identity and TTS owns progress while playing.
- `ReadingProgressStore` coalesces RAM snapshots in an actor and flushes from background contexts on checkpoints, dismissal, and app backgrounding. Legacy window/tab Reader, duplicate progress repository, and `TTSSession` mirror are removed.
- **R-08: Main Thread Deadlock in WebView Native Bridge**: If browser wait/load operations are called on the Main Actor, `semaphore.wait()` blocks the Main Thread, preventing WKWebView from executing scripts and causing an instant deadlock. Mitigated by fail-fast thread check (`Thread.isMainThread`) returning a failed JSON readiness DTO immediately, exclusively on the new `waitForReady` bridge, while legacy synchronous `launch`/`callJs` API bridges remain unmitigated.
- **R-09: WKWebView Shared Cookie Persistence Limitation**: Default `WKWebViewConfiguration` shares cookie persistence via the default data store at the application configuration level (WKWebsiteDataStore persistence), which remains a limitation with no per-extension or per-session isolation; the `waitForReady` DTO design only limits what readiness data crosses the bridge and is unrelated to cookie isolation.

- **R-10: Remote TTS thermal/CPU burst (Partially mitigated)**: A depth-three window previously created independent Google/Ext tasks with no concurrency cap and nested retry. Mitigation is one priority coordinator (`RemoteTTSSynthesisCoordinator`), service-owned retry capped at two attempts, and delayed next-chapter audio. Thermal state is telemetry-only, so heat is **not** actively throttled — sustained remote synthesis on a warm device remains a residual risk.
- **R-11: Persistent Ext TTS JS state (Mitigated)**: Reusing JavaScriptCore can retain extension globals. The runtime is isolated to TTS, serialized, keyed by exact script/config identity, reset on error/full cache teardown, and never shared with search/detail/toc/chap execution.
- **R-12: Sustained NghiTTS on-device inference heat (Unmitigated for heat)**: Piper remains one-worker and serialized; the prefetch window keeps `N` + mandatory `N+1` plus up to two optional reserve items from `N+2` gated by the cached-time watermark, and matching in-flight work is reused to prevent duplicate synthesis. There is **no** thermal gating: `.serious`/`.critical` are logged only and never cancel or throttle refill, and there is no cooldown throttle. Very long sessions and measured RTF >= 1 therefore still generate unbounded heat and require a lighter model or another engine for guaranteed gapless playback.
- **Residual risk**: The VBook-compatible synchronous `fetch` API still waits on a worker semaphore. Registered URLSession tasks are now cancellable and binary payload text decoding is skipped, but changing the public JS API to mandatory Promise semantics remains incompatible with existing extensions.

<!-- GENERATED END -->
