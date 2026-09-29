# CHANGELOG - Nhật ký Thay đổi CodeGraph FreeBook

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **FreeBook**.

## [1.3.431] - 2026-09-29

### fix: khop am luong giua chunk va gom nut phat dung vao hang icon

Người dùng: **"chỗ đến năm giảm âm lượng đột ngột"**, **"đọc số năm bị lắp bắp"**, **"đem nút phát, dừng lên chỗ bên phải thanh chứa sao chép, clear, paste (hiển thị icon thôi)"**.

- **Tụt âm lượng ở ranh giới chunk — đã kiểm bản tham chiếu trước khi sửa**: `join_audio_chunks` giữ **nguyên** audio từng chunk rồi chỉ chèn zeros, và `grep` trong `core_utils.py` **không có** hàm `normalize`/`peak`/`rms`/`gain` nào ⇒ chênh mức giữa các chunk là hành vi **cố hữu của bản tham chiếu**, không phải lỗi port. Nguyên nhân hợp lý: model sinh mỗi chunk độc lập nên chunk toàn số đọc đều đều **nhỏ hơn** chunk kể chuyện.
  * **Cách xử lý (mở rộng có chủ ý, dè dặt)**: `joinChunks` kéo mỗi chunk về **trung vị** RMS, kẹp hệ số trong **[0,6 … 1,6]** (±4 dB) — kẹp để **không** san bằng khác biệt có ý nghĩa (câu thì thầm, câu nhấn mạnh).
  * Đã ghi vào `rules.md` rằng đây là **mở rộng**, để sau này không ai "sửa" ngược về cho khớp bản tham chiếu.
- **"Lắp bắp" khi đọc số năm**: phoneme của chunk đó **đúng** (`nˈam mˈo6t̪ ŋˈi2n tʃˈiɜn tʃˈam tʃˈiɜn mˈyəj,` = "năm một nghìn chín trăm chín mươi,") ⇒ đây là **hiện tượng của model** khi gặp chuỗi âm tiết lặp, không phải lỗi tầng chữ. Không sửa được ở tầng này.
- **UI**: nút **Phát / Dừng** chuyển lên **cùng hàng** với xoá–sao chép–dán ở ô nhập chữ, tất cả **chỉ icon**; khối dưới còn trạng thái + nút chia sẻ audio.
- **Tách file**: `VieNeuTTSEngine+Audio.swift` lên **432/400** sau khi thêm khớp âm lượng ⇒ tách theo ranh giới *chữ* vs *mẫu*: phần tách chunk sang `VieNeuTTSEngine+Chunking.swift` (**294**), `+Audio` còn **148**.
- **File sửa**: `VieNeuTTSEngine.swift` **370**, `VieNeuTTSEngine+Chunking.swift` **294** (mới), `VieNeuTTSEngine+Audio.swift` 368 → **148**, `VieNeuTTSTestView+Sections.swift` 210 → **217**.
- **Ràng buộc đã đo**: `check_architecture.py` giữ nguyên **5** violation nền cũ và **0** vi phạm mới; `validate_links.py` PASS. Không build được trên Windows.
- **Tài liệu CodeGraph**: `rules.md` thêm 2 luật (khớp âm lượng là mở rộng có chủ ý; tách `+Audio` theo ranh giới chữ/mẫu); `00_index`, `02_file_graph`, `09_dependency_rules`, `11_subsystems`, `14_complexity_report` cập nhật.

## [1.3.430] - 2026-09-29

### fix: mo rong hang rao con so theo tu dan so

Báo cáo sau 1.3.429 trả lời gọn cả hai câu hỏi.

- **`chậm ở đâu  vector 7,60 s | khác 0,14 s`** trên 28,01 s audio ⇒ **vòng Euler chiếm 98%** thời gian, chi phí cố định theo chunk chỉ 0,14 s ⇒ **giảm số chunk không giúp gì** — loại hẳn một hướng tối ưu tôi định thử.
- **Nâng lên 4 luồng đã có tác dụng**: `RTF thật` 0,37 → **0,29** (−22%). Giữ 4 luồng; đã ghi **kết quả đo** vào doc của `threadCount` để lần sau không đo lại.
- **Còn lại hai đòn bẩy, cả hai đã chạm sàn**: số bước (8 là mức thấp nhất còn dùng được) và CFG (tắt đi thì người dùng nghe "quá dở") ⇒ **engine đã gần mức sàn thực tế**.
- **Lỗi còn lại: "tháng sáu" bị chẻ đôi.** Phoneme từng chunk chỉ ra đúng chỗ: `[0] … tˈaːɜŋ.` rồi `[1] sˈaɜw nˈam …`. Hàng rào của bản tham chiếu chỉ chặn cắt giữa **hai từ số**, mà "tháng" không phải từ số ⇒ lọt. Nay thêm `numberIntroducers` (tháng ngày giờ phút giây tuổi khoảng độ số trang chương phần quyển tập mục điều quãng hồi chặng) chặn cắt **ngay sau** chúng khi từ kế là số.
  * **Đã xác minh**: hàng rào cũ → `…từ khoảng tháng | nghìn chín trăm…`; mới → `…từ khoảng | nghìn chín trăm…` ✓.
  * Đây là **mở rộng** so với bản tham chiếu, nhưng chính nó ghi rằng chặn thừa một chút còn hơn xẻ đôi một năm ⇒ đúng tinh thần của nó.
- **File sửa**: `VieNeuTTSEngine+Audio.swift` 355 → **368**, `VieNeuSynthesisPolicy.swift` **93** (chỉ đổi doc).
- **Ràng buộc đã đo**: `check_architecture.py` giữ nguyên **5** violation nền cũ và **0** vi phạm mới; `validate_links.py` PASS. Không build được trên Windows.
- **Tài liệu CodeGraph**: `rules.md` thêm 2 luật (kết quả đo: Euler 98% ⇒ giảm chunk vô ích, 4 luồng có tác dụng; từ dẫn số cũng chặn cắt); `11_subsystems.md` thêm mục về lượt này.

## [1.3.429] - 2026-09-29

### perf: them so do thoi gian va in phoneme moi chunk

Người dùng: **"Cả đoạn mà phoneme bạn in ra chỉ có 1 câu"** và **"thời gian tổng hợp quá dài: hơn 10s cho 28s audio, cũ là 4s… cần thiết sửa để tăng tốc độ"**.

- **Phoneme in MỌI chunk, mỗi chunk một dòng** (`[0] …`, `[1] …`). Bản trước chỉ in 700 ký tự của chunk 0 — mà chunk 0 chỉ là một câu, nên không soi được chunk nào đọc sai.
- **Số đo tách nhóm việc thay vì đoán**: `VieNeuTTSEngine.Timing` cộng dồn `vectorMs` (vòng Euler) và `otherMs` (phần còn lại của chunk); báo cáo thêm dòng `chậm ở đâu vector X s | khác Y s`. Đây là bước **đo trước khi sửa** — nếu `vector` chiếm gần hết thì đòn bẩy là số bước / CFG / số luồng; nếu `khác` đáng kể thì đó là chi phí cố định theo chunk và cách giảm là giảm số chunk.
  * **Bẫy đã mắc và đã sửa**: bản đầu dùng hai `defer` — cái ngoài đo **cả chunk** (gồm cả vòng lặp) nên phần vector bị **đếm hai lần**. Sửa thành `otherMs += max(0, chunkMs - vectorMs)`. **Số đo sai còn tệ hơn không đo** vì nó đẩy lần sửa sau đi sai hướng.
- **Nâng `threadCount` 2 → 4**: sau khi đã ở 8 bước + CFG thì số luồng là **đòn bẩy còn lại duy nhất**, đổi lại máy nóng hơn. Ghi rõ trong code: nếu lần sau RTF không giảm mà `vector` vẫn chiếm gần hết thì **trả về 2**.
- **Phân tích số của người dùng**: 10,15 s cho 28,13 s audio; `RTF thật` 0,37 so với 0,26–0,30 trước đó ⇒ **chậm đi thật ~25%**, không phải artefact. Phần lớn là do văn bản **dài ra thật** (số được đọc thành chữ: 20,71 → 28,13 s audio) cộng +20% số chunk.
- **`VieNeuTTSEngine` chạm 399/400 dòng** khi thêm số đo ⇒ dời `Chunk`/`Gap` sang `+Audio.swift`, `Timing` sang `+Adaptive.swift` ⇒ engine còn **370**.
- **File sửa**: `VieNeuTTSEngine.swift` 372 → **370**, `VieNeuTTSEngine+Audio.swift` 336 → **355**, `VieNeuTTSEngine+Adaptive.swift` 46 → **56**, `VieNeuTTSService.swift` 272 → **279**, `VieNeuSynthesisPolicy.swift` 87 → **93**, `VieNeuTTSTestView.swift` 290 → **291**.
- **Ràng buộc đã đo**: `check_architecture.py` giữ nguyên **5** violation nền cũ và **0** vi phạm mới; `validate_links.py` PASS. Không build được trên Windows.
- **Tài liệu CodeGraph**: `rules.md` thêm 3 luật (đo trước khi tối ưu và đừng để số đo đếm hai lần; chẩn đoán phải in mọi đơn vị chứ không chỉ cái đầu; nested type nên nằm ở file extension khi file chính chật); `11_subsystems.md` thêm mục về lượt này.

## [1.3.428] - 2026-09-29

### fix: khong cat giua con so va bao cao rtf tru khoang nghi

Người dùng: **"ngắt nghỉ bất thường khi đang đọc số, thời gian"**, **"phoneme nên in đủ đoạn mới thấy được"**, **"xử lý thời gian tăng quá nhiều"**.

- **Lỗi thật: cắt chunk xẻ đôi một con số.** Sau khi bật lớp đọc số (1.3.426), `1990` thành "một nghìn chín trăm chín mươi" — một chuỗi nhiều từ — và bộ cắt theo từ **cắt ngay giữa chuỗi đó** ⇒ nghe thành khoảng nghỉ giữa con số. Bản tham chiếu có sẵn ba bảng: `_NUMBER_WORDS`, `_CONN_WORDS`, `_CONN_PAIRS`; `_balanced_cut` chỉ nhận điểm cắt khi **không** lọt giữa cặp từ nối và **không** nằm giữa hai từ số.
  * Đã port và **xác minh**: văn bản 262 ký tự → 3 mảnh **85/90/85**, **0** chỗ xẻ đôi số, **0** chỗ cắt giữa cặp, nối lại khớp gốc từng ký tự.
- **`_split_long_part` chia ĐỀU** (`k = ceil(rest/max_chars)`, mỗi mảnh nhắm `rest/k`), không greedy — bản tham chiếu ghi rõ greedy để 304 ký tự thành 251 + 53 và điểm cắt "gần trần" trúng chỗ tệ. Thêm `min_left = max_chars // 3` để điểm cắt ở từ nối vẫn phải để lại một mệnh đề thật.
- **"RTF tăng quá nhiều" — một nửa là artefact**: khoảng nghỉ chèn **không tốn** thời gian suy luận nhưng **thổi phồng** `pcmDuration`, nên `synthesisMs/pcmDuration` **thấp giả**, càng nhiều chunk càng thấp giả. Thêm `Output.speechDuration` (audio trừ khoảng nghỉ); báo cáo hiện **cả hai** RTF để tách bạch "engine chậm đi" với "văn bản dài ra".
- **Mẫu phoneme in đủ 700 ký tự** (trước 120) — 120 không đủ thấy chỗ sai ở giữa đoạn.
- **Ghi nhận**: `phoneme bỏ: 3` ở báo cáo người dùng là `[`, `]` (chú thích `[a]`) và `"` — không phải chữ, vô hại; phần chữ số đã hết bị bỏ (trước là 11).
- **File sửa**: `VieNeuTTSEngine+Audio.swift` 252 → **336**, `VieNeuTTSEngine.swift` 363 → **372**, `VieNeuTTSService.swift` 267 → **272**, `VieNeuTTSTestView.swift` 285 → **290**.
- **Ràng buộc đã đo**: `check_architecture.py` giữ nguyên **5** violation nền cũ và **0** vi phạm mới; `validate_links.py` PASS. Không build được trên Windows.
- **Tài liệu CodeGraph**: `rules.md` thêm 3 luật (không xẻ đôi số / không cắt giữa cặp từ nối; chia đều không greedy; RTF phải tính trên audio thật); `11_subsystems.md` thêm mục về lượt này.

## [1.3.427] - 2026-09-29

### fix: tach chunk theo cau nhu ban tham chieu de khong cat giua cau

Người dùng báo **"vẫn còn tình trạng cắt chunk giữa đường gây ngắt nghỉ khó chịu"**. Nguyên nhân: **tôi chưa hề đọc bộ tách chunk của bản tham chiếu mà tự viết** — và đã viết sai hai lần.

- **Bản tham chiếu gói theo CÂU**: `normalize_to_chunks_v3_with_gaps` → `pack_sentences_into_chunks(sentences, max_chars)`, tách câu bằng `RE_SENTENCE_FINDALL = r'[^.!?]+[.!?]*|[.!?]+'`, chia đoạn theo `\n`. Ranh giới chunk vì thế **luôn** rơi vào ranh giới câu; chỉ khi một câu **đơn** dài hơn trần mới phải cắt phụ — **trước theo dấu ngắt trong câu** (`RE_MINOR_PUNCT = r'(?<=[,;:\-–—])\s+'`), sau cùng mới theo từ.
- **Bản 1.3.424 gói theo từ** ⇒ hết chẻ đôi *từ* nhưng vẫn cắt **giữa câu** ⇒ chỗ nối thành khoảng nghỉ giữa câu, đúng lời người dùng.
- **`_classify_gap` phân loại ranh giới theo dấu câu cuối chunk**: `.!?` → `"sentence"`, còn lại (`,;:` hoặc cắt cưỡng bức) → `"minor"`; `"para"` cho ranh giới `\n`. Bản tham chiếu dùng `V3_GAP_SILENCE = {"para": 0.70, "sentence": 0.50, "minor": 0.30}`; FreeBook ánh xạ sang **khoá `UserDefaults` sẵn có** (`paragraphPauseDuration` 0.5 / `sentencePauseDuration` 0.3 / `phrasePauseDuration` 0.15) để một chỗ chỉnh là **cả hai engine** cùng đổi.
- **`_fits` có "tail slack"**: câu vừa trần, **hoặc** ngắn hơn `min(15, max_chars/8)` và tổng vẫn trong `max_chars + slack` — thiếu luật này thì sinh mảnh vụn kiểu `"phương."` đứng riêng rồi bị dán sang câu sau.
- **Đã mô phỏng lại trên đúng đoạn 450 ký tự của người dùng**: 5 chunk, **mọi chỗ cắt đều ở dấu phẩy hoặc hết câu**, nối lại **khớp từng ký tự** với văn bản gốc.
- **Type mới**: `VieNeuTTSEngine.Chunk` + `Chunk.Gap` (`.paragraph` / `.sentence` / `.minor`) — bản port của `_classify_gap`.
- **File sửa**: `VieNeuTTSEngine+Audio.swift` 171 → **252**, `VieNeuTTSEngine.swift` 344 → **363**.
- **Ràng buộc đã đo**: `check_architecture.py` giữ nguyên **5** violation nền cũ và **0** vi phạm mới; `validate_links.py` PASS. Không build được trên Windows.
- **Tài liệu CodeGraph**: `rules.md` thêm 3 luật (gói theo câu; phân loại gap theo dấu câu; tail slack); `11_subsystems.md` thêm mục về lượt này.

## [1.3.426] - 2026-09-29

### fix: doc so va ngay thang cho engine VieNeu bang lop tien xu ly cua app

Người dùng báo **"đọc số và thứ ngày tháng bị nuốt chữ"** kèm `phoneme bỏ: 10` và dòng `phoneme:` (thêm ở 1.3.425 — và nó trả lời được ngay trong một lượt).

- **Nguyên nhân: `sea_g2p.bin` không có chữ số nào.** Tra thẳng từ điển: `8`, `1999`, `74`, `3`, `2002` đều **không có** ⇒ chúng rơi vào đường **đánh vần từng ký tự**, mà vocab của model chỉ có `1 2 4 5 6 7` ⇒ `0 3 8 9` bị nuốt. `8/1999` + `3/11/2002` mất đúng **10** ký tự (7 chữ số + 3 dấu `/`) — khớp chính xác `phoneme bỏ: 10`.
- **Đảo quyết định plan §2** ("không chạy lớp tiền xử lý nào"): thực tế cho thấy bộ G2P của model **không tự lo được số và ngày tháng**. Nay engine gọi `TextPreprocessor.normalizingForVieNeu(text)` **một lần cho cả đoạn, trước khi tách chunk** — phần đọc số làm văn bản dài ra nên phải xong trước khi biết cắt ở đâu.
- **Lớp dùng là `processVietnameseText`, KHÔNG phải `preprocess(_:)`**: hàm sau còn chạy `EnglishTransliterator`/`JapaneseTransliterator`, tức chèn **IPA của espeak** — một bảng ký hiệu khác sẽ bị `encode` bỏ im lặng. Dùng đúng `processVietnameseText` nên vẫn có toàn bộ logic sẵn có: đọc số, ngày tháng, khoảng năm, thời gian, đơn vị, số La Mã, chuẩn hoá NFC, gạch ngang/nháy/ellipsis.
- **Cờ `preprocessorNumericNormalizationEnabled`** (mặc định `true`) được `processVietnameseText` tự kiểm ⇒ tắt "Chuẩn hóa cách đọc số" trong Cấu hình NghiTTS là **cả hai engine** cùng tắt.
- **Bỏ `normalizingPunctuation` tự viết** ở 1.3.425: app đã có `normalizeQuotesAndDashes` làm đúng việc đó (gạch ngang → `-`, và `-` là vocab id 6). Một đường chuẩn hoá thay vì hai.
- **Một thứ KHÔNG phải lỗi**: `sách → sˈe-ɜc`, `giành → zˈe-2ɲ`, `anh → ˈe-ɲ` có dấu `-` **trong chính từ điển**. Đó là dữ liệu upstream, không sửa.
- **Ràng buộc ratchet-down suýt bị vi phạm**: thêm 2 dòng doc vào `TextPreprocessor.swift` (đúng baseline **1121**) đẩy lên 1123 ⇒ violation mới; đã gỡ. Hai khai báo (`PreprocessorRuntimeConfig`, `processVietnameseText`) hạ `private` → `internal` **tại chỗ, không đổi số dòng**; lối vào mới ở `TextPreprocessor+Numbers.swift` **35** dòng.
- **File sửa**: `TextPreprocessor.swift` **1121 → 1121** (không đổi), `VieNeuTTSEngine.swift` 338 → **344**, `VieNeuTTSEngine+Audio.swift` 190 → **171** (bỏ hàm thừa).
- **Ràng buộc đã đo**: `check_architecture.py` giữ nguyên **5** violation nền cũ và **0** vi phạm mới; `validate_links.py` PASS. Không build được trên Windows.
- **Tài liệu CodeGraph**: `rules.md` thêm 3 luật (đọc số trước khi phonemize; không thêm dòng vào `TextPreprocessor.swift`; `-` trong giá trị từ điển là đúng); `11_subsystems.md` thêm mục về lượt này.

## [1.3.425] - 2026-09-29

### fix: khoang nghi theo dau cau va chuan hoa dau cau la

Người dùng báo `phoneme bỏ: 1` và **"ngừng nghỉ chưa hợp lý"**, kèm lo ngại **"RTF tăng đáng kể so với ver trước"**.

- **`phoneme bỏ: 1` = dấu gạch ngang `–` (U+2013).** Vocab `config.json` có `-` ASCII nhưng **không** có `–`/`—`/`“ ”`, và `VieNeuConfig.encode` **bỏ im lặng** ký tự lạ (chỉ đếm vào `droppedScalars`). Nay `normalizingPunctuation` ánh xạ gạch ngang sang **dấu phẩy** — nó mang nghĩa *ngắt ý*, và dấu phẩy thì model biết đọc — và bỏ các dấu nháy trang trí. **Cố ý không đụng `'`/`’`**: tokenizer dùng chúng để ghép từ.
- **"Ngừng nghỉ chưa hợp lý"**: khoảng nghỉ là **hằng số 0,12 s** cho mọi khe, và **dấu phẩy không nằm trong bộ ký tự ranh giới chunk** — mà khoảng lặng chỉ được chèn **giữa** các chunk, nên dấu phẩy nằm *trong* chunk thì mọi chỗ ngắt theo dấu phẩy đều mất. Nay `pauseSeconds(afterChunk:)` đọc **đúng khoá `UserDefaults`** mà đường NghiTTS dùng (`sentencePauseDuration` 0,3 s / `phrasePauseDuration` 0,15 s) ⇒ chỉnh trong Cấu hình NghiTTS là **cả hai engine** cùng đổi. `,` `，` `、` đã vào `chunkBoundaryCharacters`.
- **Về "RTF tăng": đó là artefact của phép đo, không phải engine chậm đi.** `RTF = synthesisMs / audioSeconds`, nên bất cứ gì làm **audio ngắn đi** đều đẩy RTF lên. Hai lần người dùng đo dùng **văn bản khác nhau** (290 vs 285 ký tự) và cho audio 16,88 s vs 15,08 s (−11%) trong khi thời gian tổng hợp chỉ đổi 4376 → 4554 ms (+4%, trong nhiễu nhiệt). Báo cáo nay in thêm **"nhanh hơn N× so với realtime"** (`1/RTF`) để con số đọc trực tiếp. Muốn so chuẩn thì phải **cùng một đoạn văn**.
- **Thêm "mẫu phoneme" vào khối chẩn đoán** (`phoneme: …`, 120 ký tự đầu của chunk đầu): đây là **bằng chứng duy nhất** phân biệt được "từ điển trả phoneme sai" với "phoneme đúng nhưng model đọc phoneme tiếng Anh bằng giọng Việt" — hai nguyên nhân nghe giống hệt nhau. Cần cho ca `Potter` còn treo.
- **File sửa**: `VieNeuTTSEngine+Audio.swift` 126 → **190**, `VieNeuTTSEngine.swift` 330 → **338**, `VieNeuTTSService.swift` 262 → **267**, `VieNeuTTSTestView.swift` 284 → **285**, `+Diagnostics.swift` 40 → **44**.
- **Ràng buộc đã đo**: `check_architecture.py` giữ nguyên **5** violation nền cũ và **0** vi phạm mới; `validate_links.py` PASS. Không build được trên Windows.
- **Tài liệu CodeGraph**: `rules.md` thêm 3 luật (khoảng nghỉ theo dấu câu; chuẩn hoá dấu câu lạ; RTF là tỉ số nên phải so trên cùng văn bản); `11_subsystems.md` thêm mục về lượt này.

## [1.3.424] - 2026-09-29

### fix: khong che doi tu o ranh gioi chunk, sua picker che do, them nut chia se audio

Người dùng thử đoạn khác và báo **"trở" đọc thành "thê giở"**, **"Harry Potter" đọc thành "harry pô ti tờ"** — vài từ sai lẻ trong câu đúng.

- **Nguyên nhân gốc: `splitIntoChunks` cắt cứng ở đúng `limit` ký tự nên chẻ đôi từ.** Đếm vị trí trên đúng câu người dùng gửi: `trở` ở ký tự **[139..141]** còn ranh giới chunk là **140** ⇒ "t" vào chunk 0, "rở" vào chunk 1; `Potter` vắt qua ranh giới 280 ⇒ "Po" + "tter". Hai mảnh không có trong từ điển nên rơi vào **`charFallback` (đánh vần từng ký tự)** và bị đọc thành **tên chữ cái**.
  * Đã kiểm bằng bộ đọc Python trên `sea_g2p.bin` thật: **cả `trở` (`tʃˈəː4`) lẫn `potter` (`<en>pˈɑːɾɚ`) đều CÓ trong từ điển** ⇒ lỗi không phải từ điển mà là ranh giới chunk. (Đây là lần thứ sáu trong engine này lỗi nằm ở chỗ tôi tự tính thay vì hỏi nguồn.)
  * Sửa: `splitIntoChunks` gói theo **từ**, chỉ cắt cứng khi một từ đơn dài hơn `limit`. Đã mô phỏng lại: `trở` nằm trọn trong một chunk, văn bản nối lại khớp gốc từng ký tự.
- **Picker chế độ không đổi ngay khi chọn**: `VieNeuTTSService` là class thường (**không** `@Observable`), nên `Binding` đọc `service.preferredMode` và nhãn đọc `service.currentMode` đều không làm SwiftUI vẽ lại — nhãn chỉ nhảy khi state khác đổi (bấm Phát). Sửa: lựa chọn giữ ở `@State selectedMode`, đẩy xuống service trong `.onChange`, nhãn đọc state trước.
- **Thêm nút "Chia sẻ audio"** (`ShareLink` với file WAV ghi ra thư mục tạm; xoá file của lượt trước để không tích tụ).
- **Thêm 3 nút icon xoá / sao chép / dán** ở ô nhập chữ, kèm `accessibilityLabel`. `.buttonStyle(.borderless)` là bắt buộc: trong một hàng `Form`, mặc định cả hàng là **một** nút nên mọi cú chạm rơi vào nút đầu.
- **Thêm `chunkCount` vào khối chẩn đoán** (`chunk: N`) — chỉ số bắt đúng lỗi ranh giới chunk.
- **File sửa**: `VieNeuTTSEngine+Audio.swift` (viết lại `splitIntoChunks`), `VieNeuTTSEngine` 324 → **330**, `VieNeuTTSService` 256 → **262**, `VieNeuTTSTestView.swift` 260 → **284**, `+Sections.swift` 167 → **210**, `+Diagnostics.swift` 37 → **40**.
- **Ràng buộc đã đo**: `check_architecture.py` giữ nguyên **5** violation nền cũ và **0** vi phạm mới; `validate_links.py` PASS. Không build được trên Windows.
- **Tài liệu CodeGraph**: `rules.md` thêm 2 luật (không chẻ từ ở ranh giới chunk; UI state phải nằm ở `@State` khi service không observable); `11_subsystems.md` thêm mục về lượt này.

## [1.3.423] - 2026-09-29

### fix: bo che do turbo va chi doi toc do phat audio

Người dùng đo trên máy thật: `fast` (8 bước) **RTF 0.26** (16,88 s audio trong 4,38 s), `high` (16 bước) **RTF 0.48** (8,06 s), giọng "khá ổn" ở cả hai — nhưng chế độ **tắt CFG "quá dở, đứt quãng, không rõ tiếng"**.

- **Bỏ hẳn chế độ `turbo` (`cfg = 0`)**: model card cảnh báo thẳng "hurts intelligibility" và tai người dùng xác nhận. Giữ lại một lựa chọn đã bị từ chối chỉ tạo thêm một cái bẫy. Tương thích: `UserDefaults` còn giá trị `"turbo"` thì `Mode(rawValue:)` trả `nil` ⇒ tự rơi về "tự động", **không cần migrate**.
- **Tách tốc độ phát khỏi tốc độ tạo**: engine `speed` chia `exp(log_s)` (`secs = min(exp(log_s)/speed, 15)`) — tức bắt model **sinh audio ngắn/dài hơn**, đẩy nó ra khỏi nhịp được huấn luyện và bắt tổng hợp lại mỗi lần đổi tốc độ. Nay màn thử giọng **luôn tổng hợp ở 1.0×** và áp tốc độ bằng `AVAudioPlayer.rate` (`enableRate = true` phải đặt **trước** `rate`, nếu không iOS bỏ qua). Mục "Tốc độ" đổi thành **"Tốc độ phát"** kèm giải thích.
- **Hệ quả cần nhớ khi nối Reader (increment 2b)**: số RTF đo được **luôn ứng với 1.0×**, và đổi tốc độ **không được** kích hoạt tổng hợp lại.
- **Chế độ còn lại**: `high` (16 bước, "Chất lượng cao") · `fast` (8 bước, "Nhanh") · *Tự động*.
- **File sửa**: `VieNeuSynthesisPolicy` 86 → **87**, `VieNeuTTSTestView.swift` 255 → **260**, `VieNeuTTSTestView+Sections.swift` 164 → **167**.
- **Ràng buộc đã đo**: `check_architecture.py` giữ nguyên **5** violation nền cũ và **0** vi phạm mới; `validate_links.py` PASS. Không build được trên Windows.
- **Tài liệu CodeGraph**: `rules.md` thêm 2 luật (tốc độ thuộc tầng phát; không có chế độ `cfg = 0`); `11_subsystems.md` thêm mục về lượt đo này.

## [1.3.422] - 2026-09-29

### feat: them bo chon toc do tao audio cho engine VieNeu

Người dùng xác nhận engine đã **đọc đúng tiếng Việt** (`phoneme bỏ: 0`, RTF **0.52**) và yêu cầu **nhanh hơn**, kèm ghi nhận máy **nóng** sau khi tạo xong.

- **Bộ chọn tốc độ tạo audio** trong màn thử giọng: `high` (16 bước, CFG bật) · `fast` (8 bước + sway −1) · `turbo` (8 bước, **tắt CFG**) · *Tự động*. Mỗi Euler step là một lượt `vector_estimator` và CFG chạy **thêm một lượt cho mỗi step** ⇒ 16 bước = **32 lượt/đoạn**, 8 bước = 16, `turbo` = **8**. Đây là **đòn bẩy duy nhất** vừa nhanh hơn vừa mát máy hơn (tăng thread thì nhanh hơn nhưng nóng hơn — ngược yêu cầu).
- **Lựa chọn của người dùng tắt hẳn cơ chế thích nghi**: `VieNeuTTSEngine.requestedMode != nil` ⇒ `updateMode` không chạy. Nếu không, bộ thích nghi sẽ tự nâng/hạ và ghi đè đúng thứ người dùng vừa đặt.
- **`turbo` không bao giờ do thích nghi tự đặt**: `nextMode` chỉ đi giữa `high` ↔ `fast`; bỏ CFG halve compute nhưng model card cảnh báo thẳng là **giảm độ rõ**, nên nó chỉ dùng khi người dùng đã nghe và chấp nhận.
- **Lưu lựa chọn trong `UserDefaults`** (`vieneuPreferredMode`), đặt ở tầng `VieNeuTTSService` để màn thử giọng và đường đọc truyện (khi được nối) dùng **cùng một** giá trị.
- **Tách `VieNeuTTSTestView` thành 3 file** vì đã chạm **397/400** dòng: file chính 397 → **255**, thêm `+Sections.swift` **164** (các khối `Form` + bộ chọn tốc độ) và `+Diagnostics.swift` **37** (khối copy). Tách file extension buộc hạ `@State private` → `internal` — **cái giá của việc tách muộn**.
- **Nhãn UI ở tầng View**: `VieNeuSynthesisPolicy.Mode.displayName` là extension trong file View, để policy giữ nguyên tính thuần (không chuỗi UI, không `UserDefaults`).
- **File sửa**: `VieNeuSynthesisPolicy` 81 → **86**, `VieNeuTTSEngine` 302 → **324**, `VieNeuTTSService` 231 → **256**.
- **Ràng buộc đã đo**: `check_architecture.py` giữ nguyên **5** violation nền cũ và **0** vi phạm mới; `validate_links.py` PASS. Không build được trên Windows.
- **Tài liệu CodeGraph**: `00_index.md`, `02_file_graph.md`, `09_dependency_rules.md`, `11_subsystems.md`, `14_complexity_report.md` (`--accept`); `04_call_graph.md`, `10_risk_report.md`, `13_resource_lifecycle.md`, `rules.md` (`--no-change-needed`).

## [1.3.421] - 2026-09-29

### fix: doc dung base 48 cua sea_g2p.bin va thu tu byte UTF-8

Engine đã chạy (**RTF 0.50** ở chế độ `high`, độ dài audio hợp lý) nhưng người dùng báo **"âm thanh không phải tiếng Việt"**. Hai lỗi trong bộ đọc `sea_g2p.bin`:

- **`SeaG2P.getString` hardcode `32 + offset`** — `write_bin_v2` ghi header **48** byte (4 magic + 4 version + 12 count + 12 vị trí + 8 bảng section + 8 reserved) rồi mới tới blob chuỗi. Lệch **16 byte** nghĩa là **mọi** chuỗi đọc ra đều là *đuôi của chuỗi trước + đầu của chuỗi sau* ⇒ phoneme rác ⇒ model đọc ra thứ không phải tiếng Việt, trong khi shape/tensor/độ dài audio đều đúng nên triệu chứng không phải một lỗi mà là "nghe sai tiếng".
  * Đã xác minh trực tiếp trên file thật (62.829.820 byte): base 48 cho `xin → sˈin`, `chào → tʃˈaː2w`, `đây → ɗˈəɪ`, `việt → vˈiɛ6t̪`, `người → ŋˈyə2j`; base 32 **không tra được từ nào**. Nay `stringBase` đọc từ trường version (v2 → 48, v1 → 32) thay vì hardcode.
- **Sai thứ tự so sánh khi tìm nhị phân**: `write_bin_v2` sắp bảng bằng `sorted(..., key=lambda kv: kv[0].encode("utf-8"))` (thứ tự **byte UTF-8**), còn `SeaG2P` dùng `String.<` của Swift (Unicode canonical ordering) ⇒ có thể trượt khoá **có** trong bảng. Nay dùng `utf8Less` với `lhs.utf8.lexicographicallyPrecedes(rhs.utf8)`.
- **Thêm `droppedScalars` vào khối chẩn đoán của màn thử giọng**: `AppLogger` chỉ ghi khi người dùng bật `AppLogger.isLoggingEnabled`, nên một bộ G2P trả ký tự ngoài vocab sẽ hỏng **im lặng**. Đây chính là chỉ số đã thiếu ở lượt này.
- **File sửa**: `SeaG2P.swift` 253 → **273**, `VieNeuTTSEngine.swift` 297 → **302**, `VieNeuTTSService.swift` 225 → **231**, `VieNeuTTSTestView.swift` 392 → **397** (sát trần 400 — mọi thay đổi UI tiếp theo ở màn này **phải** tách file trước).
- **Ràng buộc đã đo**: `check_architecture.py` giữ nguyên **5** violation nền cũ và **0** vi phạm mới; `validate_links.py` PASS. Không build được trên Windows.
- **Tài liệu CodeGraph**: `rules.md` thêm mục **`sea_g2p.bin` Format Invariants** (4 luật); `11_subsystems.md` thêm mục về hai lỗi này.

## [1.3.420] - 2026-09-29

### fix: doc shape ctx tu model va them nut sao chep ket qua

Người dùng báo `Got invalid dimensions for input: ctx ... Got: 512 Expected: 256`. Đây là **lỗi thứ tư cùng một loại** trong engine này: đoán thay vì hỏi model.

- **Nguyên nhân**: bản trước tự dựng shape `ctx` là `[1, L, dim]` với `dim = 512` đọc từ `config.json`. Chiều thật của `ctx` là **`style_dim` = 256**; `dim` phục vụ một chỗ khác của kiến trúc. Ba lần trước cùng loại: tên output ONNX (1.3.419), kích thước entry `.npz` (1.3.419), và giờ là shape.
- **Cách sửa**: `VieNeuORTRunTextEncoder` trả thêm `outShape`/`outRank` (điền từ `GetDimensions` trong `copyFloats`), và `VieNeuORTRunDurationPredictor`/`VieNeuORTRunVectorEstimator` **bắt buộc** nhận lại đúng shape đó — số token suy từ `contextShape[1]`, `mask` phải cùng số token. `VieNeuConfig.dim` **bị xoá** thay vì để lại trường không dùng kèm doc nói sai.
- **Dời màn thử giọng ra tab Cài đặt**: mục "Thử giọng VieNeu-TTS" nay ở `Settings/Main/TTSSettingsSection.swift`, ngang hàng "Cài đặt TTS"/"Quản lý Model", không còn nằm trong `NghiTTSSettingsView` — đây là engine thứ hai, không phải tuỳ chọn của NghiTTS/Piper.
- **Thêm nút "Sao chép kết quả"** trong màn thử giọng: gom thông báo lỗi + số đo RTF + trạng thái model + engine status thành một khối văn bản để dán vào chat thay vì chụp màn hình.
- **File sửa**: `VieNeuONNXBridge.h/.m` (chữ ký shape), `VieNeuONNXRuntime.swift` 175 → **196**, `VieNeuTTSEngine.swift` 299 → **297**, `VieNeuConfig.swift` 163 → **162**, `VieNeuTTSTestView.swift` 346 → **392**, `NghiTTSSettingsView.swift` **158** (bỏ mục "Engine khác"), `TTSSettingsSection.swift` 25 → **30**.
- **Ràng buộc đã đo**: `check_architecture.py` giữ nguyên **5** violation nền cũ và **0** vi phạm mới; `validate_links.py` PASS. Không build được trên Windows.
- **Tài liệu CodeGraph**: `rules.md` bổ sung luật "đừng suy shape từ `config.json`"; `11_subsystems.md` thêm mục về lỗi này.

## [1.3.419] - 2026-09-28

### fix: sua loi doc constants.npz va ten output ONNX cua engine VieNeu

Người dùng cài IPA, bấm "Phát thử" và nhận lỗi `Graph runtime không trả về tensor mong đợi`. Truy ra **ba** nguyên nhân — hai là lỗi thật của lượt 1.3.417:

- **`VieNeuNPZReader` đọc sai kích thước entry** ⇒ `constants.npz` không nạp được. `np.savez` ghi `0xFFFFFFFF` (sentinel ZIP64) vào trường `compressed`/`uncompressed size` của **ZIP local header** và để kích thước thật ở extra field / central directory. Bản đầu tin vào local header nên tính ra `entryEnd = 4.294.967.357` trên file 53.448 byte ⇒ ném `badNPZ("vượt biên file")`. Bản mới **không phụ thuộc kích thước của ZIP**: sau header local, kiểm magic `\x93NUMPY`, đọc header NPY để lấy `shape` + `descr` rồi tự tính `số phần tử × kích thước phần tử`. Đã mô phỏng lại trên `constants.npz` thật: 5 entry, kích thước khớp **chính xác** `zipfile` của Python (896 / 51.328 / 224 / 224 / 132).
- **`VieNeuTTSEngine.prepareLocked()` không nguyên tử**: gán `runtime` trước khi nạp `config`/`catalog`/`phonemizer`, nên khi config ném lỗi thì engine kẹt ở trạng thái nửa vời — `isPrepared` trả `true`, mọi lượt sau nhảy qua bước nạp, và guard tầng dưới báo **sai chỗ** trong khi nguyên nhân thật nằm ở bộ đọc NPZ. Nay dựng hết vào biến cục bộ rồi gán một lần; nhánh null của CFG tách thành `static makeNullBranch(runtime:config:)`. Thông báo đổi từ `badOutput("runtime")` sang `notPrepared` (không nêu tên graph — thiếu cái nào cũng là "chưa nạp xong").
- **Tên output của 4 graph là tên đoán** (`"ctx"`, `"out"`): bản tham chiếu Python lấy output theo **chỉ số** nên không xác nhận được tên, mà `OrtApi::Run` bắt buộc truyền tên ⇒ đoán sai là một lỗi runtime nữa chờ nổ. `VieNeuONNXBridge.m` nay hỏi thẳng session bằng `SessionGetOutputName` ngay sau `CreateSession` và lưu tên thật vào `context->outputNames[4]`; tên do allocator mặc định của ORT cấp phát nên được trả lại bằng `allocator->Free` trong `VieNeuORTDestroy`. Tên **input** giữ nguyên vì bản tham chiếu truyền theo tên (đã xác nhận).
- **File sửa**: `VieNeuNPZReader.swift` 141 → **158**, `VieNeuTTSEngine.swift` 276 → **299**, `VieNeuONNXBridge.m` 327 → **441** (cầu nối C không thuộc trần 400 dòng của Swift).
- **Ràng buộc đã đo**: `check_architecture.py` giữ nguyên **5** violation nền cũ và **0** vi phạm mới; `validate_links.py` PASS. Không build được trên Windows.
- **Tài liệu CodeGraph**: `rules.md` thêm mục **VieNeu-TTS ONNX Bridge Invariants** (7 luật kỹ thuật rút ra từ lượt này); `11_subsystems.md` thêm mục về ba lỗi; `04_call_graph.md`, `10_risk_report.md`, `13_resource_lifecycle.md` `--no-change-needed`.

## [1.3.418] - 2026-09-28

### feat: them man thu giong VieNeu-TTS v3 Nano

Thêm **1** file View mới và sửa **4** file, **không đụng `TTSManager`**:

- **`VieNeuTTSTestView.swift` (346 dòng, `Views/Settings/TTS/`)**: màn thử giọng VieNeu — tải model (tiến độ theo file), xoá model, chọn 1 trong 11 giọng, nhập chữ, chỉnh tốc độ, phát thử, và **hiện số đo hiệu năng**: RTF, chế độ chất lượng đang chạy, thời gian tổng hợp, thời gian chờ hàng đợi, độ dài audio.
- **Vì sao làm màn riêng trước khi nối vào Picker**: engine chỉ dùng được nếu **RTF < 1 trên máy thật**, mà con số 0,11–0,22 của tác giả model là **CPU desktop 6 luồng**, không phải iPhone. Nối vào Reader trước khi đo là làm một việc lớn (hơn 40 điểm chạm `"nghitts"` trong `TTSManager` + `TTSSettingsView`) mà chưa biết có dùng được hay không. Màn này trả lời câu hỏi đó trước — đúng điều kiện tiên quyết đã ghi ở plan §7.
- **`VieNeuTTSService`**: thêm `static let shared` **tạo lười** (dựng `VieNeuModelStore` và engine chỉ khi có người dùng thật; `nil` là trạng thái hợp lệ nếu không dựng được thư mục), cùng ba accessor `modelStore`/`currentMode`/`isPrepared`. Dùng chung **một** thực thể là bắt buộc: mỗi `VieNeuTTSEngine` giữ bốn `ORT` session riêng nên hai service là hai bộ session trong RAM và hai đường suy luận tranh CPU.
- **`VieNeuTTSEngine`**: thêm `isPrepared`.
- **`NghiTTSSettingsView`**: thêm mục "Engine khác" → `VieNeuTTSTestView`, đặt cạnh màn "Thử giọng đọc" sẵn có.
- **Chưa thêm vào Picker "Trình đọc"**: thêm mục vào Picker mà chưa nối tầng tổng hợp thì `tool == "vieneu"` sẽ rơi vào nhánh "là extension tool" (`tool != "system" && tool != "nghitts" && tool != "google"`) và app đi tìm một extension tên `vieneu` rồi báo lỗi khó hiểu. Việc nối vào Reader là lượt riêng.
- **Ràng buộc đã đo**: `check_architecture.py` giữ nguyên **5** violation nền cũ và **0** vi phạm mới; `validate_links.py` PASS. Không build được trên Windows.
- **Tài liệu CodeGraph**: cập nhật `00_index.md`, `02_file_graph.md`, `09_dependency_rules.md`, `11_subsystems.md`, `14_complexity_report.md` (`--accept`); `04_call_graph.md`, `10_risk_report.md`, `13_resource_lifecycle.md`, `rules.md` (`--no-change-needed` — màn thử giọng chưa được nối vào đường đọc truyện).

## [1.3.417] - 2026-09-28

### feat: them engine doc VieNeu-TTS v3 Nano (engine core)

Thêm **13** file Swift (2.228 dòng) + **2 file cầu nối C** (`VieNeuONNXBridge.h/.m`) trong `Sources/Services/TTS/VieNeu/`, và **1 thay đổi `project.yml`** (`SWIFT_OBJC_BRIDGING_HEADER`). **Không sửa file cũ nào** — engine chưa được nối vào `TTSManager`.

- **Bước 0 (cổng cứng của plan) — ĐẠT**: đối chiếu vocab `config.json` của Nano với `sea_g2p.bin` thật (tải 62.829.820 byte): cả **42** ký tự non-ASCII mà model cần đều có trong file nhị phân; 8 ký tự "thiếu" là emotion tag `①`…`⑧` và đi qua `emotion_tags` chứ không qua phonemizer ⇒ `SeaG2P` của repo cũ dùng lại được, **không lệch**. Đồng thời xác minh `constants.npz` là ZIP_STORED / NPY v1.0 `<f4>` (`null_spk (192,)`, `null_style (50,256)`) và `voices_v3_nano.json` (2,3 MB, 11 giọng, mặc định `Minh Quân`, mỗi giọng `speaker_emb` 192 + `style` 50×256).
- **Pipeline flow-matching (`VieNeuTTSEngine.swift`, `+Tensors.swift`, `+Audio.swift`)**: `text_encoder` → `duration_predictor` → vòng Euler có CFG → `codec_decoder`, kèm tách văn bản ≤140 ký tự. Bốn điểm bám sát bản tham chiếu: `t` là `tg[i]` (**thời gian đã warp**, không phải `u[i]`), lưới `tg = u + sway×(cos(π/2·u) − 1 + u)`, nhiễu khởi tạo **chuẩn tắc** (không phải đều — đổi sang đều là tụt chất lượng mà không có lỗi nào báo), và `round()` kiểu Python (`rounded(.toNearestOrEven)`).
- **DSP port nguyên hằng số**: `trim_and_fade`/`edge_silence` với `EDGE_THRESH_DB = −45`, giữ 0,04 s mỗi đầu, fade cosine 0,015 s, cửa sổ 10 ms.
- **Chính sách chất lượng (`VieNeuSynthesisPolicy.swift`)**: `high` = 16 step + `sway 0`, `fast` = 8 step + `sway −1` (cặp không tách rời); đổi chế độ **có trễ** (3 mẫu liên tiếp vượt `0.85` mới hạ, 3 mẫu dưới `0.45` mới nâng); `threadCount = 2` (không 1 như Piper, không 6 như desktop).
- **Cấu hình (`VieNeuConfig.swift`, `VieNeuNPZReader.swift`)**: vocab lưu theo **Unicode scalar** vì bốn dấu tổ hợp `̪ ̩ ̃ ʲ` là entry riêng — duyệt bằng `Character` của Swift sẽ gộp `t`+`̪` thành một ký tự và **nuốt im lặng** phoneme. `NPZReader` đọc thẳng vùng dữ liệu `.npy` (đã kiểm `compress_type = 0`) và đọc số **từng byte** để không rebind con trỏ lệch căn chỉnh — dạng lỗi repo cũ đã crash thật ở `c838327`.
- **Tải model (`VieNeuModelStore.swift`, `VieNeuModelClient.swift`)**: kho riêng, **cố ý tách khỏi `ModelStore` của Piper** (nếu chung thư mục thì `getLocalVoiceIDs()` sẽ nhận 4 graph của Nano thành 4 "giọng Piper"). **Ghim sha cả ba nguồn**: HF `aba295eb96a6fa6003ebe417cc1f2802a7adc1dc`, GitHub `2e982ff857bbe23fffa0c314e0f60da2497e2f4b` (`voices_v3_nano.json`) và `e825173f235d08ea19315b2b279fb11153b44cea` (`sea_g2p.bin`). Resume ở **mức từng file** (file tạm → `moveItem` nguyên cùng thư mục), **không** resume theo byte — **điểm lệch plan**, lý do ghi trong file (API async của `URLSession` không đưa `resumeData`; `bytes(for:)` trả từng byte nên 280 MB là không dùng được).
- **Facade (`VieNeuTTSService.swift`)**: song song `PiperTTSService`, dùng **chung** `PiperSynthesisCoordinator` (4 mức ưu tiên + coalescing + `promote`) và tái dùng `PiperTTSService.isUnspeakable`/`makeSilenceSpec`/`buildSilenceStreamingPayload` với `sampleRate: 24_000` (quên tham số này là mọi khoảng nghỉ ngắn hơn ~8 %). `synthesizeStream` phát **một** chunk cho cả đoạn — model không có streaming cấp frame; hạn chế này ghi rõ trong doc của type.
- **Port G2P (`SeaG2P.swift`, `SeaG2P+Phonemize.swift`)**: mang nguyên từ `VieNeuTTS-Offline` (bản gốc 509 dòng ⇒ buộc tách 2 file theo trần 400 và hạ `private` → `internal` cho thành viên dùng chéo file).
- **Hai lỗi kiến trúc do lượt này gây ra đã sửa trước khi commit**: `VieNeuConfig` bị `MULTI_PRIMARY_TYPES` (tách `NPZReader` ra file riêng — đặt `private` không giải quyết được vì bộ đếm tính type top-level bất kể mức truy cập) và `VieNeuTTSEngine` 472 > 400 (tách `+Tensors` và `+Audio`).
- **BLOCKER đã gặp và đã gỡ — tầng ONNX phải đi bằng C API, không phải lớp ObjC (`VieNeuONNXRuntime.swift`)**: `ctx_mask` của `duration_predictor` và `vector_estimator` khai `elem_type = 9 = BOOL` (đọc trực tiếp protobuf của model), nhưng `ORTTensorElementDataType` của wrapper ObjC **không có case `Bool`** ở **mọi** bản còn dùng được — đã kiểm `ort_enums.h` tại ORT v1.16.0, v1.20.0, v1.24.2 (bản gói SPM `from: 1.16.0` resolve tới) và cả `main` của gói SPM; chỉ `main` của **ORT core** mới có, và nó chưa phát hành. Hàm map `PublicToCAPITensorElementType` dùng bảng tra + throw nên `ORTTensorElementDataType(rawValue: 9)` không lọt, và `ORTValue` không có init nào nhận con trỏ C `OrtValue*` ⇒ không thể tạo tensor bool qua lớp ObjC. C API có `ONNX_TENSOR_ELEMENT_DATA_TYPE_BOOL` từ lâu nên engine chuyển hẳn sang C API — nhưng **phải qua cầu nối C** (`VieNeuONNXBridge.h` + `.m`, thêm `SWIFT_OBJC_BRIDGING_HEADER` vào `project.yml`) vì `import onnxruntime` **không hoạt động**: product SPM `onnxruntime` chỉ trỏ tới target ObjC `OnnxRuntimeBindings`, còn binary target C là dependency nội bộ của target đó và umbrella header `onnxruntime.h` không `#import` header C API ⇒ module C không nằm trong tầm import của target app. Ghi chú kỹ thuật kèm theo: `ORT_API2_STATUS` **không** thêm tham số `const OrtApi*`; các hàm `Release*` trả **`void`** chứ không phải `OrtStatus*`; `CreateTensorWithDataAsOrtValue` **không copy** dữ liệu nên `NSMutableData` của input phải sống tới hết lượt `Run`.
- **Ba lần phải tách file vì trần 400 dòng**: `SeaG2P` (bản gốc 509 ⇒ 2 file), `VieNeuTTSEngine` (bản đầu 472 ⇒ tách `+Audio`), và lượt chuyển C API (tách `+Adaptive`, lớp tensor thành `VieNeuONNXRuntime` 337 dòng).
- **Ràng buộc đã đo**: `check_architecture.py` giữ nguyên **5** violation nền cũ và **0** vi phạm mới; `architecture_allowlist.json` không bị sửa. Không build được trên Windows.
- **Tài liệu CodeGraph**: Cập nhật `00_index.md`, `02_file_graph.md`, `09_dependency_rules.md`, `11_subsystems.md`, `14_complexity_report.md` (`--accept`); `04_call_graph.md`, `10_risk_report.md`, `13_resource_lifecycle.md`, `rules.md` (`--no-change-needed` — engine chưa được gọi nên call graph/risk/lifecycle không đổi).

## [1.3.416] - 2026-09-28

### feat: them token <hn> doc so han thanh phien am han viet va thu hang token lop ky tu

Sửa **11** file và thêm **1** file Swift mới (`QuickTranslationRuleNumeralNarrowness.swift`) trong `Sources/Services/Translation/Engine/`:

- **Token lớp ký tự mới `<hn>` — số Hán đọc Hán-Việt (`QuickTranslationRuleElement.swift`, `QuickTranslationNumberFormatter.swift`, `QuickTranslationRuleParser.swift`)**:
  - `QuickTranslationRuleElement.swift`: Thêm `NumeralKind.hanNumeral = "hn"` với lớp ký tự `〇零一二两兩三四五六七八九十百千万萬亿億兆` (**21** ký tự). Khác `<n>` đúng ở chỗ **không** nhận chữ số `0-9`/`０-９` ⇒ `<hn>` là lớp con thật của `<n>` và là lớp cha của `<h>`.
  - `QuickTranslationNumberFormatter.swift`: Thêm `hanNumeralUnits` và nhánh `units(for: .hanNumeral)`; tập này cũng là tập dùng cho boundary guard hai đầu của matcher.
  - `QuickTranslationRuleParser.swift`: Nhận `"hn"` trong `numeralKinds` và ánh xạ `names[0] == "hn"` sang `.hanNumeral`; giữ nguyên range `:min-max` mặc định `1-12` và thanh điều chỉnh độ dài như mọi token lớp ký tự khác.
- **Render phiên âm Hán-Việt (`QuickTranslationDictionaryToken.swift`, `QuickTranslationRuleMatcher.swift`)**:
  - `QuickTranslationDictionaryToken.swift`: Thêm `hanVietReading(for:)` — tra `phienAm` **từng ký tự** rồi ghép bằng **dấu cách** (`三十` → `tam thập`, `万` → `vạn`); ký tự thiếu trong bảng giữ nguyên ký tự gốc, cùng chính sách của `<hv>`. Đặt ở đây vì đây là nơi duy nhất trong engine giữ `phienAm`, và vì `<hn>` đi qua `walkNumeral` chứ không qua `candidates`.
  - `QuickTranslationRuleMatcher.swift`: `walkNumeral` render `<hn>` qua `dictionaries.hanVietReading(for:)`, và coi `<hn>` là **không khớp** khi bảng phiên âm chưa nạp (không render chuỗi rỗng).
- **Thứ hạng cố định giữa các token lớp ký tự (`QuickTranslationRuleNumeralNarrowness.swift`, `QuickTranslationRuleCompiler.swift`, `QuickTranslationCompiledRule.swift`, `QuickTranslationRuleEngine.swift`)**:
  - `QuickTranslationRuleNumeralNarrowness.swift` (file mới, 61 dòng): Bảng hạng `<h>` 0 < `<d>` 1 < `<hn>` 2 < `<m>` 3 < `<y>` 4 < `<n>` 5 < `<a>` 6 (hạng nhỏ = lớp hẹp = thắng) và bộ so hai vector hạng. Bảng **viết tay** chứ không suy từ `units(for:).count`: nới lớp ký tự của một token (việc đã xảy ra với `<m>` ở 1.3.415) sẽ làm thứ hạng đảo **ngầm** nếu suy tự động, còn `switch` exhaustive bắt lỗi compile ngay khi thêm token mới mà quên khai hạng.
  - `QuickTranslationRuleCompiler.swift`: `numeralNarrownessRanks` duyệt AST (kể cả token trong group) và lưu vector vào `QuickTranslationCompiledRule` — tính một lần lúc compile chứ không đi bộ AST trong comparator chạy O(n log n) lần mỗi dòng văn.
  - `QuickTranslationRuleEngine.swift`: `select` so vector hạng **sau** bốn tiêu chí cấu hình và **trước** `sourceLine`, nên cấu hình Ưu tiên của người dùng cùng quy tắc "bộ riêng truyện thắng" giữ nguyên hiệu lực; hai rule chỉ khác phần token (`<d>天` gặp `<n>天`) không còn để số dòng quyết định. So **lần lượt từng token theo thứ tự xuất hiện**; rule không có token lớp ký tự nào ra vector rỗng ⇒ hoà ⇒ rơi xuống `sourceLine` như trước.
- **Cấu hình runtime & UI (`QuickTranslationRuleTokenSettings.swift`, `QuickTranslationRuleTokenSettingsView.swift`, `QuickTranslationRuleTokenPaletteView.swift`)**:
  - `Kind.hanNumeral` **nối vào cuối** `allCases` (sau `latinLetters`) để chữ ký cache của các token cũ không trượt bit; khoá `quickTranslateRuleTokenHanNumeralEnabled`, mặc định bật, nhãn `<hn> — số Hán đọc Hán-Việt`, xếp vào nhóm lớp ký tự.
  - Thêm công tắc ở màn Cấu hình token + footer giải thích; chip chèn token tự xuất hiện vì palette dựng từ `Kind.allCases` + `isNumeralGroup` (do luật chữ ký nên `<hn>` hiện sau `<a>` trong dải token). Màn đặt riêng theo truyện và `QuickTranslationBookEngineConfigStore` **không** phải sửa — cả hai duyệt `TokenKind.allCases`.
- **Ràng buộc đã đo**: `QuickTranslationRuleEngine.swift` 392 → **398**/400 dòng nên bảng hạng buộc phải ra file riêng. `check_architecture.py` giữ nguyên **5** violation nền cũ (đều ở file lượt này không đụng) và không phát sinh vi phạm mới; `architecture_allowlist.json` không bị sửa. Không build được trên Windows.
- **Tài liệu CodeGraph**: Cập nhật `00_index.md`, `02_file_graph.md`, `07_dataflow.md`, `09_dependency_rules.md`, `11_subsystems.md`, `14_complexity_report.md` (`--accept`).

## [1.3.415] - 2026-09-27

### feat: mo rong token <m> thanh co so 10

Sửa **6** file và thêm **1** file Swift mới (`QuickTranslationMagnitudeFormatter.swift`) trong `Sources/Services/Translation/Engine/`:

- **Mở rộng tập hợp và ánh xạ cơ số 10 cho token `<m>` (`QuickTranslationMagnitudeFormatter.swift`, `QuickTranslationNumberFormatter.swift`)**:
  - `QuickTranslationMagnitudeFormatter.swift`: File mới (126 dòng $\le 400$) quản lý tập ký tự `magnitudeUnits` ("十百千万萬亿億兆廿卅卌一二两兩三四五六七八九") và từ điển ánh xạ toàn diện các cơ số 10 trong tiếng Trung:
    - Bậc cơ sở đơn thuần (không có "10/một" phía trước): `十` -> `mươi`, `百` -> `trăm`, `千` -> `nghìn`, `万` -> `vạn`, `亿` -> `ức`, `兆` -> `triệu`.
    - Chữ số hàng chục cổ: `廿` -> `hai mươi`, `卅` -> `ba mươi`, `卌` -> `bốn mươi`.
    - Hàng chục 20–90: `二十` -> `hai mươi`, `三十` -> `ba mươi` ... `九十` -> `chín mươi`.
    - Hàng trăm/nghìn/vạn ghép số (2–9 / 两): `二百`/`两百` -> `hai trăm`, `二千` -> `hai nghìn`, `二万` -> `hai vạn`...
    - Bậc kép cơ số và ghép số: `十万` -> `chục vạn`, `百万` -> `trăm vạn`, `千万` -> `nghìn vạn`, `二十万` -> `hai mươi vạn`, `两百万` -> `hai trăm vạn`...
  - `QuickTranslationNumberFormatter.swift`: Uỷ quyền toàn bộ `magnitudeUnits` và `renderMagnitude` sang `QuickTranslationMagnitudeFormatter`, giảm file xuống 321 dòng (dưới trần 400 dòng).
- **Nâng cấp Parser & Matcher khớp linh hoạt 1–4 ký tự (`QuickTranslationRuleParser.swift`, `QuickTranslationRuleMatcher.swift`)**:
  - `QuickTranslationRuleParser.swift`: Mở rộng phạm vi độ dài của token `.magnitude` từ cố định 1 ký tự thành `minLength = 1, maxLength = 4` ký tự Hán.
  - `QuickTranslationRuleMatcher.swift`: Kiểm tra `QuickTranslationMagnitudeFormatter.isMagnitudeCandidate(value)` trong vòng lặp candidate để bảo vệ ranh giới số, ngăn ngừa nuốt nửa chừng các số lẻ (như `二十五`).
- **Đồng bộ giao diện cấu hình & tài liệu Token (`QuickTranslationRuleTokenSettings.swift`, `QuickTranslationRuleElement.swift`, `QuickTranslationRuleDraftAnalyzer.swift`)**:
  - Cập nhật mô tả hiển thị của token `<m>` thành cơ số 10 trong cài đặt và engine AST.
- **Tài liệu CodeGraph**: Cập nhật `00_index.md`, `02_file_graph.md`, `11_subsystems.md` (`--accept`); `07_dataflow.md`, `09_dependency_rules.md`, `14_complexity_report.md` (`--no-change-needed`).

## [1.3.414] - 2026-09-27

### feat: them toast thong bao sau khi luu name vp rieng o ai

Sửa **1** file Swift trong `Sources/Views/Reader/AI/`:

- **Thêm Toast thông báo sau khi lưu Name / VietPhrase riêng ở AI (`ReaderAIFullScreenView+Actions.swift`)**:
  - `ReaderAIFullScreenView+Actions.swift`: Cập nhật hàm `saveNamesToDictionary` tiếp nhận kết quả trả về `savedCount` từ `AIHarnessService.shared.saveExtractedEntries`.
  - Hiển thị Toast trên `@MainActor` qua `ToastManager.shared.show`:
    - Nếu thành công (`savedCount > 0`): Toast xanh `type: .success` hiển thị *"Đã lưu X mục vào Name riêng của truyện"* hoặc *"Đã lưu X mục vào VietPhrase riêng của truyện"*.
    - Nếu thất bại (`savedCount == 0`): Toast đỏ `type: .error` hiển thị *"Lưu vào [tên mục tiêu] thất bại"*.
  - Tuân thủ nghiêm ngặt quy tắc kiến trúc `Sources/Views/**` gọi Toast trực tiếp, file đạt 264 dòng vật lý (dưới trần 400 dòng).
- **Tài liệu CodeGraph**: Cập nhật `04_call_graph.md`, `11_subsystems.md` (`--accept`); `13_resource_lifecycle.md` (`--no-change-needed`).

## [1.3.413] - 2026-09-27

### fix: sua loi popup luu name vp, loc name luy tien va on dinh cuon chat ai

Sửa **5** file Swift trong `Sources/Views/Reader/AI/` và `Sources/Services/AI/`:

- **Sửa lỗi Pop-up Bottom Sheet lưu Name/VP bị rỗng và hiển thị Skeleton View (`ReaderAINameReviewSheet.swift`, `ReaderAIFullScreenView.swift`)**:
  - `ReaderAINameReviewSheet.swift`: Định nghĩa lồng `Target: Identifiable, Sendable` và bổ sung delay tối thiểu 250ms trong `loadAndDecorateNames()` để Skeleton view shimmering mượt mà trước khi chuyển sang danh sách thẻ.
  - `ReaderAIFullScreenView.swift`: Chuyển đổi từ `.sheet(isPresented:)` sang `.sheet(item: $nameReviewTarget)` giúp giải quyết triệt để lỗi race condition state rỗng ở lần mở đầu tiên. Mọi context menu mở sheet nhận chính xác 100% nội dung ngay từ lần bấm đầu.
- **Lọc tên riêng 1 chương trực tiếp & loại bỏ chặn từ khoá (`ReaderAIFullScreenView+Actions.swift`)**:
  - Xoá bỏ khối chặn từ khoá `contains("lọc tên riêng")` trong `sendUserMessage`. Bất kể người dùng gõ câu lệnh gì, hệ thống đều gửi cho AI và streaming câu trả lời về bình thường.
  - Sửa tuỳ chọn nhanh `.extractNamesCurrentChapter` gọi trực tiếp `sendUserMessage(promptOverride: "Lọc tên riêng trong chương này")`. Xoá hàm `extractNamesCurrentChapter()` cũ giúp giảm file xuống 255 dòng.
- **Lọc tên riêng cả bộ tải lũy tiến từng batch & gỡ thẻ card inline (`ReaderAIFullScreenView+Actions.swift`, `AIRuntimeCoordinator.swift`, `AINameExtractionBatchProcessor.swift`, `ReaderAIFullScreenView.swift`)**:
  - `ReaderAIFullScreenView+Actions` & `AIRuntimeCoordinator`: Mỗi khi quét xong 1 batch (5 chương), cập nhật ngay danh sách `Tên gốc=Nghĩa` vào tin nhắn Assistant. Các batch sau tự động gộp lũy tiến vào danh sách trước.
  - Người dùng có thể nhấn giữ tin nhắn Assistant bất kỳ lúc nào ngay sau batch 1 để mở menu *"Thêm vào VP / Name riêng"* và lưu ngay lập tức.
  - `AINameExtractionBatchProcessor`: Bổ sung fallback bóc tách danh sách dạng dòng `Từ=Nghĩa` ngoài JSON.
  - `ReaderAIFullScreenView.swift`: Gỡ bỏ hoàn toàn việc render thẻ card inline ở đáy màn hình chat, giảm file xuống 372 dòng (dưới trần 400).
- **Ổn định khung cuộn chat AI (`ReaderAIFullScreenView.swift`)**:
  - Thay `LazyVStack` bằng `VStack` trong ScrollView chat, triệt tiêu hoàn toàn xung đột layout ảo hoá với `.defaultScrollAnchor(.bottom)`, cuộn êm ái và không bị nhảy giật lên xuống.
- **Tài liệu CodeGraph**: Cập nhật `04_call_graph.md`, `11_subsystems.md` (`--accept`); `13_resource_lifecycle.md` (`--no-change-needed`).

## [1.3.412] - 2026-09-27

### feat: them tu dien hang loat tu goc=nghia va them vp name rieng tu ai

Sửa **5** file và thêm **2** file Swift mới (`DictEntrySheet.swift`, `ReaderAINameReviewSheet.swift`) trong `Sources/Views/Dictionary/`, `Sources/Views/Reader/AI/`, `Sources/Services/AI/`:

- **Thêm từ điển hàng loạt dạng `Từ gốc 1=nghĩa 1\nTừ gốc 2=nghĩa 2` (`DictEntrySheet.swift`, `DictionaryListView.swift`)**:
  - `DictEntrySheet.swift`: Tách Sheet thêm/sửa từ mới ra file riêng (212 dòng) hỗ trợ 2 chế độ `.single` và `.batch`. Chế độ `.batch` dùng `TextEditor` nhiều dòng kèm thanh toolbar clipboard 3 nút icon chuẩn: Xoá trắng (`trash`), Copy (`doc.on.doc`), Dán (`doc.on.clipboard`). Tự động parse từng dòng theo dấu `=`, trim khoảng trắng, bỏ qua dòng rỗng hoặc không đúng định dạng.
  - `DictionaryListView.swift`: Thêm hàm `upsertBatchEntries` giao dịch an toàn qua `TranslationDictionaryWriter.shared.mutate`, cập nhật trực tiếp state RAM và hiển thị Toast thông báo chi tiết: thêm mới bao nhiêu từ, cập nhật nghĩa bao nhiêu từ. Giảm từ 682 xuống 669 dòng vật lý (dưới baseline 690).
- **Pop-up Bottom Sheet duyệt và lưu tên riêng / VietPhrase từ tin nhắn AI (`ReaderAINameReviewSheet.swift`, `ReaderAIFullScreenView.swift`, `ReaderAIFullScreenView+Actions.swift`, `AIRuntimeCoordinator.swift`)**:
  - `ReaderAINameReviewSheet.swift`: Pop-up Bottom Sheet chuyên dụng (131 dòng) hiển thị ngay lập tức với hiệu ứng `ReaderAISkeletonView` shimmering khi đang nạp ngầm, sau đó hiển thị thẻ `ReaderAINameReviewCardView` kèm nút Đóng. Task chạy ngầm nạp `[AIExtractedName]` và trang trí nhãn từ điển NE/VP qua `AIBookDataInspector.shared.decorateExtractedNames`.
  - `ReaderAIFullScreenView.swift`: Thêm tuỳ chọn "Thêm vào VP / Name riêng" trong context menu của tin nhắn văn bản khi chứa dạng `Từ=Nghĩa`. Kết nối mở `ReaderAINameReviewSheet`. Loại bỏ logic render inline thẻ duyệt tên riêng cũ, giảm file từ 416 xuống 389 dòng (dưới trần 400 dòng).
  - `AIRuntimeCoordinator.swift` & `ReaderAIFullScreenView+Actions.swift`: Bỏ tự động ép parse JSON array khi stream xong tin nhắn AI, nhận kết quả văn bản danh sách trực tiếp.
- **Cập nhật mẫu nhắc nhở Trí nhớ chung AI (`BookAIMemoryStore.swift`)**:
  - Cập nhật `defaultGlobalMemoryPrompt` theo mẫu lọc tên riêng trả về text trực tiếp dạng `Tên gốc=Nghĩa`, không Markdown, áp dụng quy tắc phiên âm Hán Việt cho tên Trung Quốc, phiên âm ngôn ngữ gốc cho ngoại quốc, và bảo toàn trật tự xưng hô tiếng Việt.
  - Thêm logic tự động di trú prompt trong `loadGlobalMemory()` nếu file cũ vẫn chứa định dạng JSON array.
- **Tài liệu CodeGraph**: Cập nhật `00_index.md`, `02_file_graph.md`, `04_call_graph.md`, `11_subsystems.md` (`--accept`); `09_dependency_rules.md`, `13_resource_lifecycle.md`, `14_complexity_report.md` (`--no-change-needed`).

## [1.3.411] - 2026-09-27

### feat: dong bo header icon 17pt, toggle thay the tts va fix scroll token copy xoa rac

Sửa **20** file Swift trong `Sources/Views/`:

- **Chuẩn hoá kích thước Header, Toolbar Icon và khoảng cách nút bấm**:
  - `ReaderHeaderFooterOverlayView.swift`: Nút quay lại (back) mở rộng hitbox `38x44pt` icon `17pt semibold`; cụm nút công cụ phải tăng khoảng cách `spacing: 6pt`, chuẩn hoá hitbox `36x38pt` icon `17pt semibold`; nút cuộn TTS có nền `34x34pt, r=8`.
  - `DiscoveryView.swift`: Nút chọn nguồn (pill) chuẩn chiều cao `38pt` (`cornerRadius: 19`); 3 nút tròn bên phải (Safari, Dịch thuật, Tìm kiếm) chuẩn khung `38x38pt` icon `17pt semibold`, khoảng cách `spacing: 8pt`.
  - `BookDetailView.swift` & `BookDetailView+Extensions.swift`: Nút Dịch và Menu 3 chấm chuẩn icon `17pt semibold`, frame `36x36pt`, `spacing: 6pt`.
  - `ReaderAIFullScreenView.swift`: Nút đóng và menu 3 chấm chuẩn icon `17pt semibold`, frame `36x36pt`.
  - Đồng bộ `ShelfView.swift`, `RepositoryManagerView.swift`, `NotificationInboxView.swift`, `CollectionDetailView+Manage.swift`, `DictionaryListView.swift`, `AISettingsView.swift`, `AIChatAllSessionsManagerView.swift`, `BypassWebView.swift` về icon `17pt semibold`.
  - `ReaderChapterListView.swift`: Cụm 3 nút mục lục chuẩn icon `14pt semibold`, frame `32x32pt`, `spacing: 4pt`.
  - Ban hành quy chuẩn kỹ thuật bắt buộc vào `Docs/CodeGraph/rules.md` (§5.4 SwiftUI Rules & §7 Checklist) và ánh xạ đồng bộ sang `AGENTS.md`, `CLAUDE.md`, `.agents/AGENTS.md`.
- **Bổ sung Toggle bật/tắt ở màn hình Thêm thay thế TTS (`AddTTSReplacementSheet.swift`, `ReaderView.swift`)**:
  - `AddTTSReplacementSheet.swift`: Thêm `Toggle("Kích hoạt thay thế", isOn: $isEnabled)`. Khi mở, tự động tra cứu danh sách quy tắc sẵn có `existingRules` để hiển thị đúng trạng thái `isEnabled` và `replacement` cũ nếu từ đã tồn tại. Tự động đồng bộ lại nếu người dùng nhập pattern trùng quy tắc có sẵn. Cập nhật closure `onAdd: (String, String, Bool) -> Void`.
  - `ReaderView.swift`: Lưu đúng `isEnabled` vào `TTSReplacementRule`, gọi `TTSReplacementManager.shared.addRule(rule)` và thông báo Toast trạng thái `(Đã tắt)` nếu tắt.
- **Sửa lỗi thanh token dịch không cuộn ở Copy nội dung gốc & Xoá từ rác (`ReaderCopyOriginalOverlayView.swift`, `ReaderJunkDeleteOverlayView.swift`, `ReaderView.swift`, `ReaderView+DefinitionLoading.swift`, `ReaderView+RuleTools.swift`)**:
  - `ReaderCopyOriginalOverlayView.swift`: Bổ sung `ScrollViewReader`, định danh `.id("copy-trans-\(token.id)")`, hàm `scrollToSelectedToken(proxy:animated:)` và các trigger `.onChange(of: selectedWordOffset)`, `.onChange(of: selectedWordLength)`, `.onAppear` (delays 0.15s, 0.35s). Đặt frame cố định `minHeight: 32, maxHeight: 32`.
  - `ReaderJunkDeleteOverlayView.swift`: Chuẩn hoá frame `minHeight: 32, maxHeight: 32` và thêm trigger `.onChange(of: selectedWordLength)`.
  - `ReaderView+DefinitionLoading.swift`: Bổ sung `showingJunkDeleteSheet` vào guard của `loadDefinitionData(preservingMeaning:)`, khắc phục triệt để lỗi không nạp token dịch khi mở trực tiếp màn Xoá từ rác.
  - `ReaderView+RuleTools.swift`: Bổ sung case `.junkDelete` vào enum `SelectionPanel` và hàm `closeOtherSelectionPanels(except:)` để tránh xung đột overlay.
- **Tài liệu CodeGraph**: Cập nhật `rules.md`, `04_call_graph.md`, `11_subsystems.md` (`--accept`); `05_state_graph.md`, `08_lifecycle.md`, `10_risk_report.md`, `12_ownership_graph.md`, `13_resource_lifecycle.md` (`--no-change-needed`).

## [1.3.410] - 2026-09-27

### feat: toi uu mo AI chat luu session doc lap va dong bo token reader

Sửa **10** file và thêm **5** file Swift mới (`AIChatSessionSummary.swift`, `ReaderAISkeletonView.swift`, `AISettingsProfileSectionView.swift`, `AIChatAllSessionsManagerView.swift`, `ReaderAIFullScreenView+SessionLoading.swift`) trong `Sources/Models/AI/`, `Sources/Services/AI/`, `Sources/Views/Reader/` và `Sources/Views/Settings/AI/`.

- **Tối ưu mở AI Chat hiển thị tức thì & loại bỏ khựng lag TTS (`ReaderAIFullScreenView.swift`, `ReaderAISkeletonView.swift`, `ReaderAIFullScreenView+SessionLoading.swift`)**:
  - `ReaderAISkeletonView`: Tích hợp khung xương hiển thị hiệu ứng shimmering tức thì ngay khi mở sheet AI (`isLoadingSession == true`), giải phóng Main Thread và loại bỏ 100% hiện tượng khựng lag âm thanh TTS khi mở trợ lý AI.
  - Chuyển toàn bộ tác vụ nạp phiên chat sang luồng nền (`Task.detached`), nạp xong mới chuyển đổi giao diện sang danh sách tin nhắn.
  - Thu gọn (condense) các tin nhắn chứa danh sách tên riêng đã lưu thành tin nhắn văn bản thuần định dạng `Name gốc 1=nghĩa 1\nName gốc 2=nghĩa 2`, loại bỏ việc render thẻ phức tạp `ReaderAINameReviewCardView` cho các tin nhắn lịch sử.
  - Phân trang lười (Lazy Pagination): Chỉ hiển thị 20 tin nhắn gần nhất (`visibleMessageCount = 20`) và cung cấp nút "Tải thêm tin nhắn cũ hơn..." khi người dùng cuộn lên trên.
- **Lưu trữ phiên chat độc lập theo từng session (`AIChatHistoryStore.swift`, `AIChatSessionSummary.swift`)**:
  - Chuyển đổi mô hình lưu trữ từ file gộp duy nhất sang mô hình file độc lập từng session: `ai_chats/<bookId>/<sessionId>.json`. Quản lý danh mục qua file chỉ mục nhẹ `_index.json` chỉ chứa metadata tóm tắt (`AIChatSessionSummary`), không chứa tin nhắn đầy đủ.
  - Tự động di trú (auto-migration) các file session gộp cũ (`ai_chats/<bookId>.json`) sang cấu trúc thư mục mới ngay khi truy cập.
  - Hỗ trợ tải lẻ từng session (`loadSession(sessionId:in:)`) với độ trễ cực thấp, không nạp toàn bộ lịch sử các session khác lên RAM.
- **Quản lý phiên chat AI trong Cài đặt (`AIChatAllSessionsManagerView.swift`, `AISettingsView.swift`, `AISettingsProfileSectionView.swift`)**:
  - `AIChatAllSessionsManagerView`: Màn hình chuyên dụng xem toàn bộ các phiên trò chuyện xuyên suốt mọi cuốn sách, hỗ trợ tìm kiếm theo tiêu đề/nội dung/tên sách, vuốt để xoá từng phiên và nút xoá toàn bộ.
  - `AISettingsView`: Thêm section "Lịch sử trò chuyện" với nút "Dọn dẹp tất cả phiên chat" (kèm alert xác nhận) và liên kết mở màn hình quản lý tất cả phiên chat.
  - Tách section danh sách profile sang `AISettingsProfileSectionView.swift` để giữ `AISettingsView.swift` dưới trần 400 dòng.
- **Sửa tương phản màu & Đồng bộ Token Reader (`ReaderAISessionListView.swift`, `ReaderDefinitionOverlayView.swift`, `ReaderCopyOriginalOverlayView.swift`, `ReaderJunkDeleteOverlayView.swift`)**:
  - `ReaderAISessionListView`: Sửa màu chữ tiêu đề phiên chat từ màu xanh tối `#242c38` sang `Color.blue` sáng rõ nét trên nền dark mode.
  - Đồng bộ thanh token gốc ở cả 3 overlay ("Dịch", "Copy nội dung gốc", "Xoá từ rác"): nút chevron trắng có viền tròn, token chọn màu trắng, token không chọn màu trắng mờ (`white.opacity(0.45)`).
  - Đồng bộ thanh token dịch: giữ nguyên kiểu gạch chân `.underline()`, chuyển màu chữ được chọn sang trắng (nền `white.opacity(0.15)`), không chọn màu trắng mờ (`white.opacity(0.45)`).
- **Tài liệu CodeGraph**: Cập nhật `00_index.md`, `02_file_graph.md`, `03_type_graph.md`, `04_call_graph.md`, `09_dependency_rules.md`, `11_subsystems.md`, `13_resource_lifecycle.md`, `14_complexity_report.md` (`--accept`).

## [1.3.409] - 2026-09-26

### feat: toi uu man hinh dich reader, sua do ui ai chat va them nhap tu dien tu truyen khac

Sửa **7** file và thêm **1** file Swift mới (`BookImportSourceSheet.swift`) trong `Sources/Services/Translation/`, `Sources/Views/Dictionary/` và `Sources/Views/Reader/AI/`.

- **Tối ưu tra cứu Base Dictionary & Quản lý từ điển (`TranslationManager.swift`, `DictionaryHubView.swift`)**:
  - `TranslationManager.existsInBaseDictionary`: Trả về kết quả ngay lập tức khi `loadedBaseDict` đã có trên RAM, ngăn ngừa trôi xuống nạp lại file `.dat` 30MB từ đĩa khi xoá từ tuỳ chỉnh trong `ManageDefinitionsView` hoặc gắn badge VP/NE.
  - `DictionaryHubView`: Bỏ lệnh `loadAllDictionaries()` trong `.onAppear`, loại bỏ việc nạp lại từ điển khi mở hub.
- **Khắc phục đơ UI / TTS & Tối ưu AI Streaming (`ReaderAIFullScreenView.swift`, `ReaderAIFullScreenView+Actions.swift`, `AIRuntimeCoordinator.swift`)**:
  - `ReaderAIFullScreenView`: Xoá bỏ việc gọi `resolveExtractedNames` trong body/`messageRow`, chuyển sang đọc thuộc tính tĩnh `message.extractedNames`, chấm dứt hoàn toàn vòng lặp re-render liên tục gây lock Main Thread và làm gián đoạn TTS khi mở AI chat session có sẵn tin nhắn.
  - `ReaderAIFullScreenView+Actions`: Thêm migration ngầm `migrateLegacyJSONMessagesIfNeeded()` trong background task (`Task.detached`) khi nạp session để nâng cấp tin nhắn JSON cũ một lần duy nhất mà không ảnh hưởng UI.
  - `AIRuntimeCoordinator`: Áp dụng throttle cập nhật streaming delta ở mức 20 FPS (50ms) thay vì dispatch MainActor trên từng token mạng.
- **Nhập từ điển riêng từ truyện khác (`BookImportSourceSheet.swift`, `DictionaryListView.swift`, `DictionaryListView+Transfer.swift`)**:
  - `BookImportSourceSheet`: Tạo sheet chọn truyện nguồn với giao diện và thành phần đồng bộ 100% với `BookShareTargetSheet`, hỗ trợ tìm kiếm theo tên gốc/tên dịch và dialog xác nhận 2 chế độ Gộp / Thay thế.
  - `DictionaryListView+Transfer`: Tiếp nhận các hàm chuyển giao `shareToBook`, `importFromBook`, `importFile`, đưa `DictionaryListView.swift` về 681 dòng vật lý (dưới baseline 690, giảm 1 vi phạm kiến trúc nền).
- **Lưu trữ Changelog**: Đẩy 9 entry cũ (`[1.3.372]` - `[1.3.380]`) sang `CHANGELOG.archive.md` để giữ `CHANGELOG.md` gọn gàng (27 entry).
- **Tài liệu CodeGraph**: Cập nhật `00_index.md`, `02_file_graph.md`, `04_call_graph.md`, `09_dependency_rules.md`, `11_subsystems.md`, `14_complexity_report.md` (`--accept`); `06_event_graph.md`, `07_dataflow.md`, `08_lifecycle.md`, `13_resource_lifecycle.md` (`--no-change-needed`).

## [1.3.408] - 2026-09-26

### feat: tu dong nhan dien response json ten rieng kich hoat the duyet va tinh chinh icon clipboard

Sửa **5** file Swift trong `Sources/Services/AI/`, `Sources/Views/Reader/AI/`, `Sources/Views/Settings/AI/`:

- **Tự Động Nhận Diện Response JSON Tên Riêng & Kích Hoạt Thẻ Duyệt (`AIRuntimeCoordinator.swift`, `ReaderAIFullScreenView.swift`)**:
  - `AIRuntimeCoordinator`: Sau khi AI hoàn tất streaming hội thoại (`accumulated`), tự động đưa qua `AINameExtractionBatchProcessor.parseNamesFromJSONString`. Nếu là mảng JSON tên riêng, tự động đối chiếu từ điển truyện để trang trí nhãn `VP`/`NE` qua `AIBookDataInspector.decorateExtractedNames`, gán `extractedNames = decorated`, thu gọn tiêu đề thành `"Đã tìm thấy \(decorated.count) tên riêng trong phản hồi:"` và lưu trực tiếp vào `activeSession` cũng như `AIChatHistoryStore`.
  - `ReaderAIFullScreenView`: Bổ sung cơ chế fallback tự động bóc tách on-the-fly trong `messageRow` (`resolveExtractedNames`). Nếu tin nhắn trợ lý chưa có `extractedNames` nhưng nội dung là mảng JSON tên riêng hợp lệ, tự động trang trí nhãn VP/NE và hiển thị ngay `ReaderAINameReviewCardView` kèm tiêu đề tóm tắt (ẩn khối JSON thô dài dòng).
- **Tinh Chỉnh Giao Diện Các Nút Thao Tác Clipboard Tinh Gọn (`AISettingsView+Actions.swift`, `BookAIMemorySheet.swift`)**:
  - Loại bỏ hoàn toàn nhãn chữ (`Xoá`, `Sao chép`/`Copy`, `Dán tiếp`/`Dán`).
  - Chuyển sang hiển thị icon SF Symbols tinh gọn (`trash`, `doc.on.doc`, `doc.on.clipboard`) với khung cố định $28 \times 26\text{ pt}$ có nền bo góc, chống triệt để tình trạng tràn layout hoặc rớt dòng chữ khi đặt cạnh tiêu đề dài.
- **Quy Tắc & Chỉ Dẫn AI Dùng Chung Mặc Định Chuẩn Hoá (`BookAIMemoryStore.swift`)**:
  - Cập nhật hằng số `defaultGlobalMemoryPrompt` theo đúng văn bản định dạng nghiêm ngặt của người dùng, yêu cầu chỉ trả về mảng JSON thuần tuý `[{"original": "...", "suggestedMeaning": "..."}]` không markdown, không code block.

## [1.3.407] - 2026-09-26

### feat: ho tro nhieu api key kem tu dong doi key loi, mac dinh bearer auth cho anthropic, sap xep ten rieng ai va sao luu ai

Sửa **14** file Swift trong `Sources/Models/`, `Sources/Services/`, `Sources/Views/`:

- **Quản Lý Nhiều API Key & Tự Động Failover (`AIProviderProfile.swift`, `AnthropicClient.swift`, `OpenAIClient.swift`)**:
  - `AIProviderProfile`: Thêm `apiKeys: [String] = []`, `anthropicAuthHeader: String = "bearer"` ("bearer" mặc định vs "x-api-key"), và hàm `allEffectiveApiKeys()` gộp danh sách các API key hợp lệ từ mảng và trường đơn cũ.
  - `AnthropicClient`: Sửa `resolveEndpoint` không chèn thừa `/v1`, hỗ trợ chọn Header (`Authorization: Bearer <token>` mặc định, `x-api-key`), tự động failover sang key tiếp theo trong danh sách candidate khi gặp lỗi HTTP 401, 403, 429 hoặc quota. Thêm `testChatPing`.
  - `OpenAIClient`: Bổ sung cơ chế failover tự động qua danh sách API keys khi gặp HTTP 401, 403, 429 hoặc quota, hàm `cleanToken`, và `testChatPing`.
- **Giao Diện Nhập API Keys Đa Dòng & Thanh Clipboard Tiện Ích (`AISettingsView.swift`, `AISettingsView+Actions.swift`)**:
  - Hỗ trợ `TextEditor` nhập danh sách API keys (mỗi dòng 1 key), đếm số key hợp lệ.
  - Bổ sung thanh công cụ clipboard (Xoá, Sao chép, Dán tiếp vào dòng mới không đè nội dung cũ) cho cả API Keys và danh sách Model.
  - Thêm Picker chọn định dạng Header Auth cho Anthropic (`Authorization: Bearer <token>` mặc định).
- **Trí Nhớ AI Toàn Cục & Tự Động Hiển Thị Thẻ Tên Riêng (`BookAIMemoryStore.swift`, `ReaderAIFullScreenView+Actions.swift`, `ReaderAINameReviewCardView.swift`, `BookAIMemorySheet.swift`, `AIPromptSettingsView.swift`)**:
  - `BookAIMemoryStore`: Quản lý file `global_memory.txt` dưới `Application Support/ai_memory/` làm quy tắc lọc tên dùng chung toàn app, tự động tiêm vào `systemInstruction`.
  - `ReaderAIFullScreenView+Actions`: Khi trợ lý AI phản hồi JSON danh sách tên riêng, tự động bóc tách bằng `AINameExtractionBatchProcessor.parseNamesFromJSONString`, trang trí nhãn VP/NE và hiển thị ngay `ReaderAINameReviewCardView`.
  - `ReaderAINameReviewCardView`: Thêm tuỳ chọn sắp xếp `selectedFirst` (mặc định) và `alphabetical`, nút sắp xếp lại bằng tay, không tự động đảo vị trí khi tick checkbox, chống vỡ layout khi tên dài.
  - `BookAIMemorySheet`: Bổ sung Segmented Picker 2 tab ("Truyện này" & "Trí nhớ tổng") kèm thanh clipboard dán nối tiếp dòng.
  - `AIPromptSettingsView`: Bổ sung Section quản lý Trí nhớ AI toàn cục và khôi phục mặc định.
- **Sao Lưu & Khôi Phục Dữ Liệu AI (`BackupSettingsArchiver.swift`, `BackupPaths.swift`, `BackupConfigArchiver.swift`)**:
  - `BackupSettingsArchiver`: Đưa `"FreeBook_AI_Configuration_V1"` vào danh sách khoá được phép xuất trong cài đặt.
  - `BackupPaths` & `BackupConfigArchiver`: Khai báo và sao lưu/khôi phục thư mục `ai_memory/` (chứa `global_memory.txt` và ghi chú từng sách) trong file backup `.fbbackup`.

## [1.3.406] - 2026-09-25

### feat: them dinh dang anthropic claude native api va cap nhat danh sach model

Thêm **2** file Swift mới, sửa **8** file Swift trong `Sources/Models/`, `Sources/Services/`, `Sources/Views/`:

- **Tích Hợp Anthropic Claude Messages API Native (`AnthropicClient.swift`, `AnthropicTypes.swift`)**:
  - `AnthropicClient`: Triển khai singleton actor kết nối API native `/v1/messages` của Anthropic với header xác thực `x-api-key: <token>` và `anthropic-version: 2023-06-01`.
  - Tự động tách `role == "system"` thành trường `system` cấp cao nhất của request JSON, gộp và chuẩn hóa role luân phiên `user`/`assistant`, hỗ trợ cả streaming SSE (`content_block_delta`) và non-streaming response.
  - `AnthropicTypes`: DTO struct `AnthropicMessageRequest`, `Response`, `StreamDelta` lồng nhau đảm bảo đúng 1 primary type top level.
- **Cập Nhật Danh Sách Model Mới Nhất & Cấu Hình Định Dạng API (`AIProviderProfile.swift`, `AIProviderPreset.swift`)**:
  - Bổ sung trường `apiFormat: String` ("openai" hoặc "anthropic") trong `AIProviderProfile`, hỗ trợ giải mã tương thích ngược.
  - Thêm preset `defaultAnthropic` với danh sách model chính thức mới nhất: `claude-3-7-sonnet-latest`, `claude-3-5-sonnet-latest`, `claude-3-5-haiku-latest`, `claude-3-7-sonnet-20250219`, `claude-3-5-sonnet-20241022`, `claude-3-opus-latest`.
  - Cập nhật preset OpenRouter Claude với model mới: `anthropic/claude-3.7-sonnet`, `anthropic/claude-3.7-sonnet:thinking`, `anthropic/claude-3.5-sonnet`, `anthropic/claude-3.5-haiku`, `anthropic/claude-3-opus`.
- **Rẽ Nhánh Điều Phối AI Client Trong Ứng Dụng (`AIRuntimeCoordinator.swift`, `AIContextCompactor.swift`, `AINameExtractionBatchProcessor.swift`)**:
  - `AIRuntimeCoordinator`: Rẽ nhánh streaming gọi `AnthropicClient.shared.sendChatStreaming` khi `activeProfile.apiFormat == "anthropic"`.
  - `AIContextCompactor` & `AINameExtractionBatchProcessor`: Rẽ nhánh gọi `AnthropicClient.shared.sendChat` khi `activeProfile.apiFormat == "anthropic"`.
- **Giao Diện Cài Đặt AI (`AISettingsView.swift`, `AISettingsView+Actions.swift`, `AddProviderProfileSheet.swift`)**:
  - Bổ sung Picker chọn "Định dạng API" (`OpenAI` vs `Anthropic Claude`).
  - Thêm mẫu template "Anthropic Claude (Chính thức)" trong sheet thêm provider mới.
  - Hỗ trợ tải danh sách model từ API và kiểm tra kết nối qua Anthropic Messages API.

## [1.3.405] - 2026-09-25

### fix: xoa provider chatgpt web va openai oauth, space token rule va tien xu ly so 10 1000

Thêm **2** file Swift mới, xoá **5** file Swift, sửa **7** file Swift trong `Sources/Models/`, `Sources/Services/`, `Sources/Views/`:

- **Xoá Hoàn Toàn Provider ChatGPT Web & OpenAI OAuth**:
  - Xoá 5 file: `ChatGPTWebClient.swift`, `ChatGPTWebLoginSheet.swift`, `OpenAIOAuthManager.swift`, `OpenAIOAuthLoginSheet.swift`, `AISettingsView+OAuth.swift`.
  - Dọn sạch logic nhánh `authType == "web"` và `authType == "oauth"` trong `OpenAIClient.swift`, `AISettingsView.swift`, `AISettingsView+Actions.swift`, `AddProviderProfileSheet.swift`, `AIProviderPreset.swift`, `AIProviderProfile.swift`.
  - Khôi phục cấu hình AI về chuẩn API Key thuần tuý, đơn giản hoá và ổn định.
- **Tự Động Khoảng Trắng 2 Bên Token Rule Dịch (`QuickTranslationRuleEngine.swift`)**:
  - Tự động chèn khoảng trắng 2 bên kết quả render của rule dịch (ví dụ câu `我买了四个苹果` với rule `<n>个` -> `我买了 4 cái 苹果`).
  - Gắn khoảng trắng vào `rendered` của rule thay vì passthrough segment, bảo toàn tuyệt đối 1:1 mapping ký tự gốc cho việc tra cứu từ điển và highlight.
- **Tiền Xử Lý Số Rời Rạc TTS (`TTSNumberSeparatorMode.swift`, `TTSReplacementManager.swift`, `TTSSettingsView+NumberPreprocessing.swift`, `TTSSettingsView.swift`)**:
  - `TTSNumberSeparatorMode`: Enum 4 chế độ (`all`, `smart`, `fourDigits`, `off`) dùng regex lookahead `(\d+)(?:\s*[-–—]\s*|\s+)(?=(\d+))` thay thế khoảng cách giữa 2 cụm số (`10 1000`, `10-1000`) thành `, ` (`10, 1000`) giúp TTS không bị đọc gộp số.
  - Tích hợp vào `TTSReplacementManager.applyReplacements(to:)` áp dụng chung cho mọi engine TTS (NghiTTS/Piper, Google TTS, Siri, Extension TTS).
  - Thêm Picker chọn chế độ trong `TTSSettingsView`, giữ file chính an toàn trong baseline (518/519 dòng).

## [1.3.404] - 2026-09-25

### fix: sua scope openai oauth, sua url fetch chatgpt web va tang size icon header len 16pt

Sửa **5** file Swift trong `Sources/Services/AI/` và `Sources/Views/`:

- **Chuẩn Hóa Scope Xác Thực OpenAI OAuth (`OpenAIOAuthManager.swift`)**:
  - Loại bỏ scope `model.request` khỏi `defaultScopes` (chỉ gửi `openid profile email offline_access`), phù hợp với quyền hạn của client ID `app_EMoamEEZ73f0CkXaXp7hrann` của OpenAI, khắc phục lỗi "The OAuth 2.0 Client is not allowed to request scope 'model.request'".
- **Khắc Phục Lỗi Gửi Tin Nhắn ChatGPT Web (`ChatGPTWebClient.swift`)**:
  - Chuyển toàn bộ lời gọi `fetch` trong JavaScript sang URL tuyệt đối `https://chatgpt.com/api/auth/session` và `https://chatgpt.com/backend-api/conversation` kèm `credentials: 'include'`, tránh lỗi "URL is not valid or contains user credentials" khi webview chưa load xong origin.
  - Tăng số lần thử chờ domain từ 10 lên 25 chu kỳ (5s).
- **Tăng Kích Thước Icon Header Lên 16pt (`ReaderHeaderFooterOverlayView.swift`, `BookDetailView.swift`, `BookDetailView+Extensions.swift`)**:
  - Reader Header: Tăng font size của các icon thao tác (`chevron.left`, `magnifyingglass`, `scroll`/`scroll.fill`, `arrow.clockwise`, `sparkles`, `gearshape`, `ellipsis.circle`) từ 13pt lên 16pt (`.font(.system(size: 16, weight: .semibold))`).
  - BookDetail Toolbar: Tăng `iconSize` của `ReaderTranslationScopeMenuView` và font size icon của `ellipsisMenu` từ 13pt lên 16pt, đồng bộ kích thước cân đối trên thanh công cụ.

## [1.3.403] - 2026-09-25

### feat: chuyen theme picker sang thanh ngang, sua chatgpt web, tich hop chatgpt oauth, config cookie ext va sua loi dich so

Thêm **3** file Swift mới, sửa **9** file Swift trong `Sources/Models/`, `Sources/Services/`, `Sources/Views/`:

- **Giao Diện Trình Đọc (`ReaderSettingsView.swift`)**:
  - Chuyển Picker chọn giao diện nền đọc (Theme) từ dạng List/Menu dọc sang dạng thanh ngang `.pickerStyle(.segmented)` với 3 lựa chọn trực quan: Sáng, Trầm ấm, Tối.
- **Sửa Lỗi ChatGPT Web (`ChatGPTWebClient.swift`)**:
  - Khắc phục lỗi "đăng nhập rồi nhưng vẫn báo chưa hoàn tất đăng nhập" bằng cách đọc trực tiếp cookie `__Secure-next-auth.session-token` từ `WKWebsiteDataStore.default().httpCookieStore` và URL tuyệt đối.
  - Sửa lỗi `JavaScript execution returned a result of an unsupported type` bằng cách bọc script async trong IIFE trả về primitive String (`(() => { (async () => { ... })(); return "started"; })()`).
- **Tích Hợp OpenAI ChatGPT OAuth PKCE (`OpenAIOAuthManager.swift`, `OpenAIOAuthLoginSheet.swift`, `AISettingsView.swift`, `AISettingsView+OAuth.swift`, `AISettingsView+Actions.swift`, `AddProviderProfileSheet.swift`, `AIProviderPreset.swift`, `AIProviderProfile.swift`, `OpenAIClient.swift`)**:
  - `OpenAIOAuthManager`: Triển khai chuẩn OAuth 2.0 PKCE với S256 (`code_verifier` và `code_challenge`), sinh URL xác thực với client ID `app_EMoamEEZ73f0CkXaXp7hrann`, trao đổi code lấy access token và refresh token tại `https://auth.openai.com/oauth/token`, tự động làm mới access token khi hết hạn và giải mã JWT payload để lấy email tài khoản.
  - `OpenAIOAuthLoginSheet`: WebView đăng nhập tài khoản OpenAI, tự động chặn redirect `http://localhost:1455/auth/callback` và xác thực state bảo mật CSRF.
  - `OpenAIClient`: Tự động gọi `OpenAIOAuthManager.shared.getValidAccessToken` để lấy token hợp lệ khi gọi API streaming và non-streaming với profile OAuth.
  - `AISettingsView+OAuth`: Tách UI quản lý tài khoản OAuth và logic logout thành file extension riêng, giữ `AISettingsView.swift` dưới 400 dòng vật lý.
- **Cấu Hình Cookie Cho Tiện Ích (`ExtensionConfigView.swift`, `JSExecutor.swift`)**:
  - `ExtensionConfigView`: Bổ sung section "Mạng & Cookie" cho phép người dùng cấu hình bật/tắt `http_should_handle_cookies` cho từng extension (mặc định bật).
  - `JSExecutor`: Đọc cấu hình `http_should_handle_cookies` và gán vào `request.httpShouldHandleCookies`. Khi tắt, `URLSession` không đính kèm cookie hệ thống, ngăn chặn triệt để lỗi HTTP 400 do dính Google Login Cookies.
- **Khắc Phục Lỗi Dịch Số Dính Liền (`QuickTranslationRuleMatcher.swift`, `QuickTranslationRuleEngine.swift`)**:
  - `QuickTranslationRuleMatcher`: Trong `walkNumeral`, phân tách hoàn toàn giữa chữ số ASCII/Full-width (`0-9`, `０-９`) và chữ số Hán (`〇-九`, `十百千万...`), ngăn việc gộp nhầm `1` và `四` thành `14` trong `<n>个`.
  - `QuickTranslationRuleEngine`: Trong `appendPassthrough(upTo:)`, thêm kiểm tra `needsSeparator(between: output, and: piece)` để chèn dấu cách ngăn cách giữa kết quả dịch của rule và số/chữ passthrough kế tiếp (khắc phục lỗi dính liền `"4 cái"` và `"0"` thành `"4 cái0"`).

## [1.3.402] - 2026-09-25

### feat: tich hop provider chatgpt web khong gioi han quota qua wkwebview

Thêm **2** file Swift mới, sửa **4** file Swift trong `Sources/Models/`, `Sources/Services/`, `Sources/Views/`:

- **Giao Tiếp ChatGPT Web Ngầm (`ChatGPTWebClient.swift`, `OpenAIClient.swift`)**:
  - `ChatGPTWebClient`: Singleton điều phối một `WKWebView` chạy ngầm chia sẻ `WKWebsiteDataStore.default()`, kiểm tra trạng thái phiên qua `/api/auth/session` và gửi request tới `/backend-api/conversation`.
  - Tích hợp Temporary Chat (`history_and_training_disabled: true`), không lưu lại lịch sử hội thoại trên web của người dùng và không huấn luyện model.
  - Streaming SSE: Bộ đọc stream trong JavaScript trích xuất nội dung delta và truyền qua `WKScriptMessageHandler` về Swift dạng `AsyncThrowingStream<String, Error>`.
  - `OpenAIClient`: Kiểm tra `authType == "web"`, tự động điều hướng `sendChat` và `sendChatStreaming` sang `ChatGPTWebClient`.
- **Giao Diện Đăng Nhập & Cài Đặt (`ChatGPTWebLoginSheet.swift`, `AISettingsView.swift`, `AddProviderProfileSheet.swift`, `AIProviderPreset.swift`, `AIProviderProfile.swift`)**:
  - `ChatGPTWebLoginSheet`: Sheet mở trang web `https://chatgpt.com` để người dùng đăng nhập tài khoản, kiểm tra trạng thái phiên trực tiếp.
  - `AISettingsView`: Hiển thị nút "Đăng nhập / Quản lý ChatGPT Web" thay cho trường API Key khi profile có `authType == "web"`. Nút "Kiểm tra kết nối" kiểm tra phiên đăng nhập web thay vì gọi `/models`.
  - `AddProviderProfileSheet`: Bổ sung mẫu `ChatGPT Web (Không lo hết quota)` với danh sách model mặc định `auto`, `gpt-4o`, `gpt-4o-mini`, `o3-mini`.
  - `AIProviderProfile`: Mở rộng thuộc tính `authType: String = "apiKey"` hỗ trợ tương thích ngược.

## [1.3.401] - 2026-09-25

### feat: tai va hien thi icon extension tren home trinh duyet bypass

Sửa **1** file Swift trong `Sources/Views/Common/`:

- **Hiển Thị Icon Extension Cục Bộ Trên Home Trình Duyệt Bypass (`BypassBrowserHomeView.swift`)**:
  - Mở rộng struct `QuickShortcut` với `extLocalPath: String?` và `extIconUrl: String?`.
  - Trong `allShortcuts`, truyền đường dẫn cài đặt cục bộ và URL ảnh trực tuyến cho từng extension đã cài đặt.
  - Sử dụng [`ExtensionIconView`](../../Sources/Views/Common/ExtensionIconView.swift) size 30 đặt gọn trong ô card 50x50, đọc ảnh `icon.png` trực tiếp qua bộ nhớ đệm [`ExtensionIconImageCache`](../../Sources/Views/Common/ExtensionIconImageCache.swift), giữ nguyên fallback SF Symbol cho các phím tắt trang mặc định.

## [1.3.400] - 2026-09-25

### feat: tuy bien size nut dich va thu gon khoang cach icon danh sach chuong va header reader

Sửa **5** file Swift trong `Sources/Views/Reader/` và `Sources/Views/BookDetail/`:

- **Tùy Biến Size Nút Dịch & Tối Ưu Chấm Trạng Thái (`ReaderTranslationScopeMenuView.swift`, `BookDetailView.swift`, `BookDetailView+Extensions.swift`)**:
  - `ReaderTranslationScopeMenuView`: Bổ sung tùy chọn `iconSize`, `frameWidth`, `frameHeight` với giá trị mặc định là 19pt và khung 44x52/36; tối ưu hóa dấu chấm override khi không có khung nền gắn trực tiếp vào góc icon qua `.overlay(alignment: .topTrailing)`.
  - `BookDetailView`: Đồng bộ nút dịch trên Toolbar Trailing sang `iconSize: 13, frameWidth: 32, frameHeight: 32` tương đồng chuẩn xác với nút dropdown `ellipsisMenu` bên cạnh. Loại bỏ sub-menu dịch trùng lặp trong `ellipsisMenu` (`BookDetailView+Extensions.swift`) và xóa computed property `translationStatus` thừa.
- **Thu Nhỏ & Gom Gần Nút Icon Danh Sách Chương (`ReaderChapterListView.swift`)**:
  - Đưa 3 nút icon (`character.bubble`, `arrow.clockwise`, `arrow.up.arrow.down`) về font size 13pt, giảm khung xuống 30x30 và gom trong `HStack(spacing: 2)`.
- **Thu Hẹp Khoảng Cách Cụm Icon Header Reader (`ReaderHeaderFooterOverlayView.swift`)**:
  - Gom các nút thao tác bên phải vào `HStack(spacing: 2)` với khung gọn 30x36 (hoặc 30x30), giảm khoảng cách giữa chúng, giúp thanh điều hướng thoáng đãng và liền mạch.

## [1.3.399] - 2026-09-25

### feat: sua loi cuon den man hinh ai va tang tuong phan nut badge the ten rieng

Sửa **2** file Swift trong `Sources/Views/Reader/AI/`:

- **Khắc Phục Lỗi Cuộn Đen Màn Hình AI (`ReaderAIFullScreenView.swift`)**:
  - Chuyển `LazyVStack` sang `VStack` để tính toán chiều cao tin nhắn tất định, loại bỏ lỗi vỡ toạ độ khi gửi tin nhắn mới.
  - Bổ sung modifier `.defaultScrollAnchor(.bottom)` của iOS 17 và thêm delay 0.08s trước khi cuộn tới ID tin nhắn cuối cùng để chờ keyboard và bubble hoàn tất layout.
- **Tăng Tương Phản Thẻ Tên Riêng Dark Mode (`ReaderAINameReviewCardView.swift`)**:
  - Nút "Lưu Name riêng" và "Lưu VP riêng" đổi nền sang `#374357` (`Color(red: 55/255.0, green: 67/255.0, blue: 87/255.0)`) với viền sáng `stroke(Color.white.opacity(0.18))` và chữ trắng đậm.
  - Badge Category chuyển sang nền xám đậm `Color(white: 0.25)` chữ trắng.
  - Badge NE và VP tăng độ mờ nền `opacity(0.25)`, chữ trắng kèm viền stroke rõ nét đồng bộ với suggest chip của Reader.
  - Checkbox chọn và icon `tag.fill` đổi sang màu xanh sáng rõ nét `Color(red: 90/255.0, green: 170/255.0, blue: 255/255.0)`.

## [1.3.398] - 2026-09-25

### feat: nang cap toan dien giao dien ai, giu chuong da tai va session khi doi nguon, ghim khong dong sheet va toi uu icon header

Thêm **4** file Swift mới, sửa **18** file Swift trong `Sources/Models/`, `Sources/Services/`, `Sources/Views/`, `Sources/Common/`:

- **Di Trú Dữ Liệu Đổi Nguồn Sách (`BookSourceMigrator.swift`, `SearchView.swift`, `AIChatHistoryStore.swift`, `BookAIMemoryStore.swift`, `TranslationManager+BookScopedFiles.swift`)**:
  - Tạo actor `BookSourceMigrator`: sao chép toàn bộ chương đã tải (`BookBinManager` + `ChapterStore`), chuyển lịch sử chat AI (`AIChatHistoryStore.migrateSessions`), chuyển bộ nhớ AI (`BookAIMemoryStore.migrateMemory`), copy cấu hình dịch (`TranslationConfigStore.setBookOverride`), và dọn dẹp an toàn file `.bin` cũ nếu không phát TTS.
  - Bổ sung `QuickTranslateEngineConfig.json` vào `bookScopedMigrationFiles`.
  - Giảm kích thước `SearchView.swift` từ 868 xuống 858 dòng (dưới baseline 872).
- **Tái Cấu Trúc Toàn Diện Giao Diện AI (`ReaderAIFullScreenView.swift`, `ReaderAIInputBarView.swift`, `ReaderAINameReviewCardView.swift`, `ReaderAISessionListView.swift`, `AIBookDataInspector.swift`, `AIHarnessMode.swift`)**:
  - Header: nút back tròn `chevron.down`, tiêu đề hiển thị tên session 1 dòng dưới "Trợ lý AI", menu dropdown `ellipsis.circle` gom các nút tính năng.
  - Đổi màu chủ đạo phân hệ AI sang tone slate navy `#242c38`.
  - Tin nhắn AI loại bỏ icon sparkles, text căn lề trái. Thanh nhập gom mode 1 hàng (`Manual`, `Plan`, `Bypass`) và phóng to nút gửi 36x36.
  - Thẻ trích xuất tên riêng kiểm tra chéo cả từ điển riêng và chung (`Names.dat`, `VietPhrase.dat`), tự động bỏ chọn mặc định nếu đã có từ trước, đồng bộ màu badge NE (đỏ) và VP (xanh nhạt), nút lưu 1 hàng không icon tone `#242c38`.
- **Mở Rộng Bộ Nhớ Truyện AI (`BookAIMemory.swift`, `BookAIMemoryStore.swift`, `BookAIMemorySheet.swift`, `ReaderAIFullScreenView+Actions.swift`)**:
  - Hỗ trợ lưu trữ nhân vật/bối cảnh, tóm tắt cốt truyện, snapshot từ điển và ghi chú riêng. Tự động đồng bộ thầm lặng khi khởi tạo phiên chat.
- **Trang Chủ Bypass WebView & Quản Lý Lịch Sử Duyệt Web (`BypassBrowserHomeView.swift`, `BrowserHistoryStore.swift`, `BrowserHistorySheetView.swift`, `BypassBrowserTabStore.swift`, `BypassWebView.swift`)**:
  - Trang chủ dark theme native dạng lưới 4x3 phân trang cho domain phổ biến, kèm 10 mục lịch sử gần đây và sheet quản lý/tìm kiếm lịch sử.
- **Tối Ưu Kệ Sách & Danh Sách Chương Reader (`BookActionSheet.swift`, `BookActionRunner.swift`, `ReaderChapterListView.swift`, `ReaderChapterListStore.swift`, `ReaderHeaderFooterOverlayView.swift`, `BookDetailView+Extensions.swift`, `ReaderView.swift`)**:
  - Giữ mở context menu sau khi ghim truyện ở Kệ sách.
  - Tự động làm mới danh sách chương trong Reader khi hoàn tất dịch lại tiêu đề.
  - Thu nhỏ icon header về 13pt (chỉ thu nhỏ hàng trên cùng cùng hàng nút back ở Reader).
  - Sửa vòng lặp loading vô hạn khi ấn Back từ màn hình Đổi nguồn Reader mà không chọn nguồn mới.

## [1.3.397] - 2026-09-24

### fix: sua loi reader load lai khi dong ai va mat tin nhan khi mo lai tu widget

Sửa **5** file Swift trong `Sources/Views/Reader/AI/`, `Sources/Views/Reader/Extensions/`, `Sources/Views/Reader/`:

- **Khôi Phục Toàn Màn Hình Native Trong Reader & Bảo Toàn Skeleton Handshake (`ReaderView.swift`, `ReaderView+AI.swift`, `AIRuntimeCoordinator.swift`)**:
  - Khôi phục `.fullScreenCover(isPresented: $showingAIFullScreen)` của SwiftUI ngay tại `ReaderView` thay cho modal UIKit `.fullScreen`. Cây view `ReaderView` không bị unmount khỏi Window, không bị trigger lại lifecycle, bảo toàn cổng handshake skeleton loading (`isChapterSubtreeRenderable`) $\rightarrow$ text hiển thị tức thì, không kẹt skeleton loading hay reload lại khi đóng AI.
  - Quản lý cờ `isReaderActive` trong `onAppear`/`onDisappear` của `ReaderView`. Khi người dùng ở trong Reader mà bấm mở lại từ Floating Widget thu nhỏ, `AIRuntimeCoordinator` phát notification `reopenReaderAI` để `ReaderView` mở lại qua `.fullScreenCover`. Khi mở từ ngoài Reader (Kệ sách, Khám phá), Coordinator dùng `modalPresentationStyle = .overFullScreen` để không làm mất ViewController bên dưới.
- **Lưu Đĩa Tức Thì & Nguồn Sự Thật Duy Nhất Cho Chat AI (`AIRuntimeCoordinator.swift`, `ReaderAIFullScreenView.swift`, `ReaderAIFullScreenView+Actions.swift`)**:
  - Ghi đĩa tức thì qua `AIChatHistoryStore.shared.saveSession` ngay tại khoảnh khắc khởi tạo tin nhắn người dùng và tin nhắn chờ của AI (áp dụng cho gõ tay, chip Tóm tắt, Bối cảnh, Dịch mượt, Lọc name chương, Quét batch).
  - Quản lý `activeSession: AIChatSession?` làm Source of Truth trong `AIRuntimeCoordinator.shared`. Tích luỹ token stream và kết quả trích xuất vào `activeSession` xuyên suốt quá trình chạy ngầm.
  - Khi mở lại AI từ widget, `initializeSession()` ưu tiên nạp ngay `activeSession` của Coordinator (nếu trùng `bookId`), đồng thời đồng bộ reactive các token delta và tiến trình batch qua Combine `$activeSession`, `$isRunning`, `$batchProgress`.

## [1.3.396] - 2026-09-24

### feat: dong bo ai dang suy nghi, chay ngam toan app va floating widget thu nho

Thêm **5** file Swift mới, sửa **5** file Swift trong `Sources/Views/Reader/AI/`, `Sources/Views/Reader/Extensions/`, `Sources/Views/Reader/`, `Sources/App/`:

- **Điều Phối Vòng Đời Tác Vụ Ngầm & Toast Hoàn Thành (`AIRuntimeCoordinator.swift`)**:
  - Tạo `AIRuntimeCoordinator` quản lý `Task` chạy ngầm độc lập khỏi vòng đời View cho streaming chat, lọc name chương hiện tại và quét batch các chương đã tải.
  - Tự động nạp/lưu phiên chat vào `AIChatHistoryStore` và phát thông báo Toast qua `ToastManager.shared.show(..., type: .success)` khi tác vụ hoàn tất ở trạng thái ngầm (khi màn hình AI đang đóng).
  - Cung cấp cơ chế `presentFullScreen(context:)` thông qua việc tìm `findTopViewController()` ở tầng window `.normal`, cho phép mở lại màn hình AI toàn màn hình từ bất kỳ đâu (Shelf, Reader, BookDetail, Settings) mà không phụ thuộc vào `ReaderView` và không bị xung đột modal.
- **Cửa Sổ & Widget Nổi Toàn Ứng Dụng (`AIFloatingWidgetWindowManager.swift`, `AIFloatingWidgetUIWindow.swift`, `AIFloatingWidgetContainerViewController.swift`, `AIFloatingWidgetView.swift`)**:
  - `AIFloatingWidgetUIWindow`: `UIWindow` riêng biệt có windowLevel `alert - 3` (thấp hơn TTS `alert - 1` và Browser `alert - 2` một bậc để tránh tranh chấp hit-testing, đảm bảo chạm vào TTS widget luôn được ưu tiên).
  - Passthrough touch chuẩn xác cho các điểm chạm ngoài viên pill để không chặn thao tác giao diện bên dưới.
  - `AIFloatingWidgetContainerViewController`: Quản lý cử chỉ `UIPanGestureRecognizer` và `UITapGestureRecognizer`, snap mượt mà vào mép màn hình bằng `FloatingWidgetGeometry` và lưu vị trí người dùng kéo vào `UserDefaults`. Chạm vào widget kích hoạt mở lại toàn màn hình AI.
  - `AIFloatingWidgetView`: Viên pill mờ (`.ultraThinMaterial`) với viền tím tinh tế, icon `sparkles` tím animated, text trạng thái tiến trình và nút tròn `xmark` huỷ tác vụ nhanh.
- **Đồng Bộ Chỉ Báo "AI đang suy nghĩ" & Đóng An Toàn Khi TTS Điều Hướng (`ReaderAIFullScreenView.swift`, `ReaderAIFullScreenView+Actions.swift`, `ReaderView.swift`, `ReaderView+AI.swift`)**:
  - Khởi tạo tin nhắn phản hồi với `content: ""` và `isStreaming: true` cho mọi thao tác (gõ tay, chip Tóm tắt, Bối cảnh, Dịch mượt, Lọc name chương, Lọc name cả bộ tải) -> luôn hiển thị động `ReaderAIThinkingIndicatorView` với text đồng nhất `"AI đang suy nghĩ"`.
  - Lắng nghe sự kiện điều hướng từ TTS Widget (`openCurrentlyPlayingReader`, `navigateReaderToPlayingChapter`) để tự động đóng màn hình AI an toàn, nhường quyền điều hướng cho Reader mà không làm gián đoạn tác vụ AI đang chạy ngầm.
  - Chuyển `onOpenAI` trong `ReaderView` sang `openAIFromReader()`, loại bỏ modal `.fullScreenCover` cục bộ giúp giảm dòng code trong `ReaderView.swift` (từ 2049 xuống 2042 dòng, dưới baseline 2053).

## [1.3.395] - 2026-09-24

### feat: sua loi nut dich kham pha khi chuyen nguon trung viet

Sửa **4** file Swift trong `Sources/Services/Translation/Utils/`, `Sources/Views/Reader/`, `Sources/Views/Discovery/`, `Sources/Views/BookDetail/`:

- **Khắc Phục Vòng Đời Nút Dịch Khám Phá (`ReaderTranslationScopeMenuView.swift`, `DiscoveryView.swift`, `BookDetailView.swift`)**:
  - `ReaderTranslationScopeMenuView`: Bổ sung tham số `isChineseSourceHint: Bool?` và hai bộ lắng nghe `.onChange(of: packageId)`, `.onChange(of: bookId)` để kích hoạt `refreshStatus()` ngay khi nguồn hoặc truyện thay đổi.
  - `DiscoveryView`: Gán `.id("discovery-translate-\(selectedExtensionId)")` cho nút dịch trên toolbar để SwiftUI tái khởi tạo view tương ứng với nguồn mới; truyền `isChineseSourceHint: selectedExtension?.isChineseSource`.
  - `BookDetailView`: Đồng bộ truyền `isChineseSourceHint: ext?.isChineseSource` vào `ReaderTranslationScopeMenuView` và các lời gọi `isTranslationEnabled`.
- **Nâng Cấp Cache & Cơ Chế Dò Nguồn Tiếng Trung (`TranslationConfigStore.swift`)**:
  - Thêm bộ nhớ đệm `sourceIsChineseMap` cùng phương thức `registerSource(packageId:isChinese:)` giúp tra cứu trạng thái nguồn O(1).
  - Tối ưu hàm `isChineseSource`: tìm kiếm đệ quy thư mục con cấp 1 trong thư mục extension khi file zip giải nén vào folder con lồng nhau; hỗ trợ trích xuất `type`, `locale`, `language` từ cả đối tượng `metadata` lẫn root `plugin.json`.
- **Cập Nhật Tức Thì Trạng Thái Dịch Thẻ Truyện (`DiscoveryView.swift`)**:
  - Cập nhật cờ `isTranslationEnabled` ngay khi đổi nguồn hoặc nhận thông báo cấu hình dịch thay đổi, giúp các thẻ truyện hiển thị tên dịch tức thì mà không cần tải lại mạng.

## [1.3.394] - 2026-09-24

### feat: dong bo popup dich mau trang, toi uu danh sach chuong va do mo chuong da doc

Sửa **9** file Swift trong `Sources/Models/Database/`, `Sources/Services/Translation/Utils/`, `Sources/Views/Reader/`, `Sources/Views/BookDetail/`, `Sources/Views/Discovery/`:

- **Popover Cấu hình Dịch Thuật Tone Trắng Tối Giản (`ReaderTranslationScopeMenuView.swift`, `DiscoveryView.swift`, `BookDetailView.swift`)**:
  - Viết lại nút dịch thành Popover nhỏ gọn với `.presentationCompactAdaptation(.popover)`, giao diện `.preferredColorScheme(.dark)`.
  - Thay đổi toàn bộ nút điều khiển sang tone màu TRẮNG (`.white`), toggle switch sử dụng `.tint(.white)`, nút Lưu lại viền trắng tối giản thay cho màu xanh primary mặc định.
  - Tích hợp đồng nhất Popover dịch tại thanh công cụ của Reader, Chi tiết truyện (`BookDetailView`) và màn hình Khám phá (`DiscoveryView`).
- **Tối ưu Danh Sách Chương & Độ Mờ Chương Đã Đọc (`ReaderChapterListView.swift`, `ReaderChapterListView+List.swift`, `ReaderChapterRowView.swift`, `BookDetailTOCView.swift`)**:
  - Tách huy hiệu nguồn/extension (`Local` / `Extension`) thành một hàng riêng biệt phía trên số chương trong danh sách chương Reader.
  - Thêm nút icon chuyên dụng "Dịch lại chương" (`character.bubble` màu trắng) trên Header cạnh nút đảo chiều để dịch lại toàn bộ tiêu đề chương và xóa cache hiển thị khi người dùng yêu cầu.
  - Làm mờ tiêu đề các chương đã đọc (`logicalIndex < currentChapterIndex` hoặc `chap.index < currentIdx`) với độ mờ `opacity: 0.40` ở cả danh sách chương Reader và Chi tiết truyện.
- **Tối ưu Hiển Thị Khi Bật Tắt Dịch Trong Reader (`ReaderView.swift`)**:
  - Bỏ việc kích hoạt `scheduleCoalescedTranslationRefresh` và `retranslateChapterTitles` trong sự kiện `.onChange(of: isTranslationEnabled)` giúp chuyển đổi hiển thị bản dịch tức thì 0ms, không gây reload hay chớp giật.
  - Đồng bộ trạng thái dịch tự động thông qua `NotificationCenter` từ `TranslationConfigStore.didChangeNotification`.
- **Mặc Định Bật Dịch Cho Nguồn Tiếng Trung (`Extension.swift`, `TranslationConfigStore.swift`)**:
  - Thêm computed property `Extension.isChineseSource` nhận diện các nguồn truyện Trung Quốc (`chinese_novel` hoặc locale chứa `zh`/`cn`).
  - `TranslationConfigStore.resolveStatus` tự động mặc định Bật dịch cho nguồn tiếng Trung khi chưa có cấu hình override, các nguồn khác mặc định Tắt dịch.

## [1.3.393] - 2026-09-24

### feat: cau hinh bat tat dich phan cap truyen nguon va toan cuc

Thêm **3** file Swift mới và sửa **8** file Swift trong `Sources/Services/Translation/`, `Sources/Services/TTS/`, `Sources/Views/Reader/`, `Sources/Views/BookDetail/`, `Sources/Views/Settings/`:

- **Quản lý cấu hình dịch phân cấp 3 mức (`TranslationConfigStore.swift`, `TranslateUtils.swift`)**:
  - `TranslationConfigStore`: Quản lý phân cấp 3 tầng rõ ràng: Truyện (`bookOverrides`) > Nguồn truyện (`sourceOverrides`) > Toàn cục (`globalEnabled`). Lưu trữ an toàn trong `UserDefaults` bằng từ điển JSON, không can thiệp schema SwiftData `@Model`.
  - Phân giải ưu tiên `resolveStatus(bookId:packageId:)`: Truyện đặt Bật/Tắt -> Áp dụng cấu hình Truyện; Truyện để Mặc định -> Áp dụng cấu hình Nguồn; Nguồn để Mặc định -> Áp dụng cấu hình Toàn cục.
  - Hỗ trợ thông báo reactive qua `TranslationConfigStore.didChangeNotification`.
- **Menu xổ xuống 1 chạm trên Header Reader & BookDetail (`ReaderTranslationScopeMenuView.swift`, `ReaderHeaderFooterOverlayView.swift`, `BookDetailView.swift`, `BookDetailView+Extensions.swift`)**:
  - Nút Menu Dịch (`character.bubble`) trên Header Reader và Toolbar Chi tiết truyện hiển thị nguồn gốc quyết định (`Truyện này`, `Nguồn này`, `Toàn cục`) kèm chấm tròn chỉ thị màu khi có cấu hình riêng.
  - Chạm mở ngay menu xổ xuống trực quan với 3 sections: Truyện này (Mặc định / Luôn Bật / Luôn Tắt), Nguồn này (Mặc định / Luôn Bật / Luôn Tắt), Toàn cục (Bật / Tắt).
- **Bộ điều khiển 3 mức trong Sheet Cài đặt đọc (`ReaderSettingsView.swift`)**:
  - Bổ sung nhóm điều khiển phân cấp trong mục Cấu hình Dịch Thuật: Picker cho Truyện này, Picker cho Nguồn này, Toggle Toàn cục.
- **Màn hình Quản lý Tập trung cấu hình dịch riêng (`TranslationScopeManagementView.swift`, `SettingsView.swift`)**:
  - Màn hình quản lý danh sách tập trung các nguồn và truyện đã override, cho phép chuyển đổi trạng thái, vuốt xoá từng mục hoặc đặt lại tất cả về mặc định.
  - Tích hợp đường dẫn `NavigationLink` trong Section Dịch Thuật Quick Translate của `SettingsView`.
- **Đồng bộ phân cấp Dịch sang TTS (`TTSManager.swift`)**:
  - Tự động nạp cờ dịch theo phân cấp của cuốn sách đang phát khi khởi chạy phiên đọc (`startWithContent` / `start`) thông qua `TranslationConfigStore.shared.isTranslationEnabled(bookId:packageId:)`.

## [1.3.392] - 2026-09-24

### feat: badge vp ne tu dong bo chon ten da co tu dong luu ai va tat auto sang chuong reader

Sửa **7** file Swift trong `Sources/Models/AI/`, `Sources/Services/AI/`, `Sources/Views/Reader/`, `Sources/Views/Settings/AI/`:

- **Badge VP / NE & Bỏ chọn mặc định tên riêng đã có (`AIExtractedName.swift`, `AIBookDataInspector.swift`, `ReaderAINameReviewCardView.swift`, `ReaderAIFullScreenView+Actions.swift`, `AINameExtractionBatchProcessor.swift`)**:
  - `AIExtractedName`: Thêm hai thuộc tính `hasInBookNames: Bool` và `hasInBookVP: Bool`, kèm bộ giải mã tùy biến an toàn tương thích ngược các file JSON chat cũ.
  - `AIBookDataInspector`: Thêm hàm `fetchBookDictionarySets` và `decorateExtractedNames`, đối chiếu với `Names.txt` và `VietPhrase.txt` của cuốn truyện đang đọc để tự động gắn cờ và đặt `isSelected = false` (bỏ chọn mặc định) cho các tên riêng đã tồn tại.
  - `ReaderAINameReviewCardView`: Hiển thị badge `NE` (tím) và `VP` (cam) trên từng hàng tên riêng để người dùng nhận diện trực quan từ nào đã có trong từ điển truyện.
  - `AINameExtractionBatchProcessor`: Không loại bỏ các từ đã có trong từ điển ở tầng xử lý batch để toàn bộ tên trích xuất đều được gắn badge đầy đủ.
- **Tự động lưu Cấu hình AI & Prompt (`AISettingsView.swift`, `AISettingsView+Actions.swift`, `AIPromptSettingsView.swift`)**:
  - Bỏ nút "Lưu" thủ công trên toolbar của `AISettingsView` và `AIPromptSettingsView`.
  - Tự động lưu cấu hình và prompt ngay lập tức khi thay đổi qua `.onChange`, khi đổi/thêm/xóa profile và khi thoát màn hình qua `.onDisappear`.
- **Tắt tự động sang chương của Reader khi tắt cuộn theo Highlight (`ReaderView.swift`)**:
  - Thêm điều kiện `guard !isAutoScrollDisabled else { return }` vào bộ nhận sự kiện `ttsDidAdvanceToNextChapter`.
  - Khi người dùng đã tắt chức năng cuộn theo highlight của TTS, Reader sẽ giữ nguyên chương và vị trí đang đọc thay vì tự ý nhảy sang chương mới theo TTS.

## [1.3.391] - 2026-09-23

### fix: sua loi parse json trich xuat ten rieng ai luon tra ve 0 ket qua

Sửa **2** file Swift trong `Sources/Models/AI/` và `Sources/Services/AI/`:

- **Nâng cấp Resilient JSON Parser trích xuất tên riêng (`AINameExtractionBatchProcessor.swift`)**:
  - Khắc phục lỗi kiểm tra cứng trường `dict["meaning"]` trong khi cấu hình AI yêu cầu `suggestedMeaning` dẫn đến kết quả luôn bị bỏ qua thành rỗng.
  - Bổ sung cơ chế bóc tách JSON đa tầng: bóc tách markdown code fence (`extractMarkdownBlock`) kể cả khi có văn bản phụ bao quanh; fallback cắt lát dải JSON substring mảng `[...]` hoặc object `{...}` qua chỉ số mở/đóng đầu tiên và cuối cùng.
  - Hỗ trợ làm sạch dấu phẩy thừa (trailing commas trước `}` và `]`) thông qua Regex `cleanTrailingCommas`.
  - Mở rộng hỗ trợ đa dạng tên trường (multi-key fallback): từ gốc Hán tự (`original`, `name`, `word`, `hanzi`, `raw`, `chinese`, `text`), nghĩa dịch Hán Việt (`suggestedMeaning`, `meaning`, `translation`, `vietnamese`, `hvdic`, `hanviet`, `viet`, `val`, `value`), phân loại (`category`, `type`, `tag`, `role`) và số lần xuất hiện (`occurrenceCount`, `count`, `occurrences`, `frequency`).
  - Tự động khử trùng lặp và cộng dồn số lần xuất hiện theo từ gốc tiếng Trung.
- **Chuẩn hóa Prompt trích xuất tên riêng (`AIConfiguration.swift`)**:
  - Bổ sung trường mẫu `category` trong `defaultNameExtractionPrompt` để hỗ trợ AI phân loại chính xác các thực thể trích xuất.

## [1.3.390] - 2026-09-23

### feat: nang cap toan dien ai harness tri nho truyen compact va luu tu dien

Thêm **6** file Swift mới và sửa **8** file Swift trong `Sources/Models/AI/`, `Sources/Services/AI/`, `Sources/Views/Reader/`, `Sources/Views/Settings/AI/`:

- **Trí nhớ dài hạn theo truyện & Tự động nạp từ điển (`BookAIMemory.swift`, `BookAIMemoryStore.swift`, `AIBookDataInspector.swift`, `BookAIMemorySheet.swift`)**:
  - Tạo model và store `BookAIMemory` lưu ghi chú bối cảnh, nhân vật của từng cuốn truyện tại `applicationSupportDirectory/ai_memory/`.
  - Tự động nạp các mục từ điển `Names.txt` và `VietPhrase.txt` của cuốn truyện vào System Context, lọc thông minh theo nội dung raw chương hiện tại.
  - Cung cấp sheet `BookAIMemorySheet` để xem và chỉnh sửa nhanh trí nhớ truyện.
- **Tự động compact ngữ cảnh phiên chat (`AIContextCompactor.swift`, `AIChatSession.swift`)**:
  - Tự động tóm tắt các tin nhắn cũ khi session vượt quá 12 tin nhắn thành `contextSummary`, chỉ gửi tóm tắt + 6 tin nhắn mới nhất để tối ưu token và chống tràn context window.
- **Nâng cấp Lưu Từ điển Name riêng & VP riêng (`ReaderAINameReviewCardView.swift`, `AIHarnessService.swift`, `ReaderAIFullScreenView+Actions.swift`)**:
  - Bổ sung 2 nút bấm riêng biệt: `Lưu Name riêng` và `Lưu VP riêng`.
  - Hộp thoại xác nhận 2 chế độ: *Gộp (trùng từ thì thay mới)* và *Thay thế hoàn toàn*.
  - Chuyển đổi nút Lưu thành banner xác nhận màu xanh sau khi lưu thành công, kèm Toast thông báo (sửa cú pháp `ToastManager.shared.show(message:type:)`).
  - Thêm nút xóa từng mục và sửa liên kết hai chiều (binding) bỏ chọn tên riêng trực tiếp vào session messages.
- **Cải tiến giao diện & trải nghiệm AI (`AIMarkdownMessageView.swift`, `ReaderAIThinkingIndicatorView.swift`, `ReaderAIFullScreenView.swift`, `ReaderAIInputBarView.swift`)**:
  - Render phản hồi AI chuẩn Markdown với khối code monospaced có nút chép, tiêu đề và gạch đầu dòng.
  - Animation 3 chấm nảy phát sáng và con trỏ nhấp nháy khi AI đang suy nghĩ.
  - Mốc neo cuộn `bottomScrollAnchor` và tương tác bàn phím chống lỗi cuộn đen màn hình.
  - Menu ngữ cảnh sao chép tin nhắn khi bấm giữ.
  - Tự động nhận diện câu lệnh lọc tên riêng khi người dùng tự gõ.
  - Tự động đóng tab AI khi bấm nhảy chương từ widget TTS (`ReaderView.swift`).
- **Màn hình Tùy chỉnh Prompt AI & Đồng bộ Profile (`AIPromptSettingsView.swift`, `AISettingsView.swift`, `AISettingsView+Actions.swift`, `AISettingsStore.swift`)**:
  - Màn hình tùy chỉnh System Prompt chat và Name extraction prompt.
  - Tinh gọn Profile: chỉ lưu các profile người dùng thực sự thêm hoặc đã nhập API key.
  - Đồng bộ thời gian thực danh sách Profile giữa Cài đặt và Reader AI qua `didChangeNotification`.

## [1.3.389] - 2026-09-23

### feat: quan ly provider profiles doc lap, picker chon mau va sua loi hien thi ai

Thêm **2** file Swift mới và sửa **5** file Swift trong `Sources/Models/AI/`, `Sources/Services/AI/`, `Sources/Views/Reader/`, `Sources/Views/Settings/AI/`:

- **Quản lý Provider Profile độc lập (`AIProviderProfile.swift`, `AIConfiguration.swift`, `AISettingsStore.swift`)**:
  - Tạo struct `AIProviderProfile` lưu trữ cấu hình riêng biệt của từng Provider (`id`, `name`, `baseURL`, `apiKey`, `selectedModel`, `availableModels`, `temperature`, `isCustom`).
  - Nâng cấp `AIConfiguration` chứa mảng `profiles` và `activeProfileId`, tự động di trú dữ liệu legacy không mất cấu hình.
  - Bổ sung các phương thức `saveProfile`, `deleteProfile`, `setActiveProfile` trong `AISettingsStore`.
- **Sheet Thêm Mới Option Provider dạng Picker (`AddProviderProfileSheet.swift`, `AISettingsView.swift`)**:
  - Thay thế thanh chọn nhanh bằng Menu Picker phân nhóm chuẩn iOS (`.pickerStyle(.menu)`) gồm Mẫu có sẵn (Gemini, OpenAI, DeepSeek, OpenRouter, Groq, Ollama), Nhân bản từ Profile đã lưu, và Tuỳ chỉnh trống.
  - Tích hợp nút "⚡ Load từ API" gọi `OpenAIClient.fetchAvailableModels` để tự động tải danh sách models.
  - Giữ duy nhất 1 nút icon `+` trên thanh Navigation bar của `AISettingsView` để thêm Profile mới.
- **Sửa lỗi hiển thị toàn màn hình AI (`ReaderView.swift`, `ReaderView+AI.swift`)**:
  - Chuyển `.fullScreenCover` sang gắn trực tiếp trên `readerSheetLayer` (neo vào UIHostingController chính) thay vì gắn vào `EmptyView` trong ZStack.

## [1.3.388] - 2026-09-23

### fix: chuyen aibookdatainspector sang internal de fix loi bien dich

Sửa access level trong `Sources/Services/AI/Harness/AIBookDataInspector.swift`:

- **Khắc phục lỗi biên dịch dùng kiểu internal trong public API (`AIBookDataInspector.swift`)**:
  - Chuyển `AIBookDataInspector` và các phương thức `fetchDownloadedChapters`, `readRawChapterContent` từ `public` sang `internal` nhằm tương thích với kiểu `StoredChapterSnapshot` (được định nghĩa `internal`).


### fix: nang cap chan doan ci va tranh xung dot type trong ai harness

Cải thiện workflow CI và refactor kiểu dữ liệu trong `Sources/Services/AI/`:

- **Đổi tên kiểu AnyCodable (`OpenAITypes.swift`)**:
  - Đổi tên `OpenAIChatRequest.AnyCodable` thành `OpenAIChatAnyCodable` và bổ sung typealias tương thích ngược nhằm phòng tránh xung đột định danh tiềm ẩn.
- **Nâng cấp công cụ chẩn đoán lỗi CI (`.github/workflows/build-ipa.yml`)**:
  - Bổ sung bước đọc trực tiếp `build_error.log` và trích xuất toàn bộ chuỗi thông báo lỗi/note từ các file serialized diagnostics (`.dia`) để hiển thị tường minh nguyên nhân thất bại trên GitHub Actions.


### fix: sua cac loi bien dich trong phan he ai harness

Sửa **4** file Swift trong `Sources/Services/AI/` và `Sources/Views/Reader/Extensions/`.

- **Sửa API nạp tên riêng trong truyện (`AIBookDataInspector.swift`)**:
  - Đọc danh sách từ/tên riêng từ `Names.txt` qua `DictionaryTextFileStore.loadEntries(from: txtUrl)` thay vì gọi `allWords()` không tồn tại trên `TrieDictionary`.
- **Sửa gọi thêm quy tắc lọc rác (`AIHarnessService.swift`)**:
  - Sử dụng `JunkFilterManager.shared.addRule(pattern:)` trên `MainActor` thay vì `addPattern`.
- **Sửa nạp nội dung chương cho Reader AI (`ReaderView+AI.swift`)**:
  - Truy xuất chương đang đọc qua `viewModel?.cache.get(readerPresentedChapterIndex)` thay vì `cachedChapters`.
- **Loại bỏ non-sendable stored property (`AIChatHistoryStore.swift`)**:
  - Dùng trực tiếp `FileManager.default` trong các hàm thay vì lưu trữ thuộc tính `private let fileManager`, tương thích hoàn toàn với chế độ Swift 6.

## [1.3.385] - 2026-09-23

### feat: them che do ai agent harness toan man hinh o reader voi 3 mode ask plan bypass

Thêm **24** file Swift mới và sửa **3** file Swift trong `Sources/Views/Reader/` và `Sources/Views/Settings/`.

- **Màn hình AI Agent Harness toàn màn hình (`ReaderAIFullScreenView.swift`, `ReaderView+AI.swift`)**:
  - Mở dạng `.fullScreenCover` từ nút icon `sparkles` trên Header và Action Menu của Reader.
  - Hỗ trợ streaming SSE phản hồi theo thời gian thực từ bất kỳ endpoint nào tương thích OpenAI API (Gemini, OpenAI, Claude/OpenRouter, DeepSeek, Groq, Ollama, Custom).
  - Tách `ReaderAIFullScreenView+Actions.swift` giữ cả 2 file dưới trần 400 dòng vật lý.
- **3 chế độ Harness ngay trên khung chat (`ReaderAIInputBarView.swift`, `AIHarnessMode.swift`)**:
  - `Manual (Ask)`: Tạo ActionPlan và hỏi người dùng trước khi áp dụng thay đổi vào dữ liệu truyện.
  - `Plan`: Lập kế hoạch chi tiết các bước, người dùng ấn "Duyệt kế hoạch" mới thực thi.
  - `Bypass permissions`: Tự động thực thi ngay lập tức.
  - Menu chuyển đổi mode dạng Pill Menu ngay trên Input Bar, kèm Model Picker Menu tức thì.
- **Quản lý cấu hình & Model trong Cài đặt (`AISettingsView.swift`, `AISettingsStore.swift`)**:
  - Hỗ trợ preset cho các nhà cung cấp phổ biến kèm cấu hình tùy chỉnh endpoint / API key / timeout.
  - Nút "Load danh sách từ API" (`GET /models`) và TextEditor nhập danh sách model thủ công (mỗi model một dòng).
  - `AISettingsSection.swift` giúp `SettingsView.swift` giảm dòng và loại bỏ khỏi baseline vi phạm kiến trúc.
- **Phân tích raw chapter & Trích xuất tên riêng (`AIBookDataInspector.swift`, `AINameExtractionBatchProcessor.swift`)**:
  - Sử dụng văn bản gốc Hán tự (raw text) từ `ChapterStore` / `BookBinManager` để LLM phân tích chính xác tên riêng, nhân vật, địa danh.
  - Quét batch offline các chương đã tải theo lô 5 chương kèm thanh tiến trình và nút Dừng.
  - Thẻ `ReaderAINameReviewCardView` cho phép duyệt, tick chọn, sửa nghĩa và lưu thẳng vào từ điển truyện (`TranslationManager.shared.saveCustomEntry(..., isName: true, bookId:)`), tự động kích hoạt bảo vệ Name riêng trước Rule dịch.
- **Lưu trữ phiên trò chuyện (`AIChatHistoryStore.swift`, `ReaderAISessionListView.swift`)**:
  - Tự động lưu session chat theo từng truyện dưới `Application Support/ai_chats/<sha256(bookId)>.json`.
  - Hỗ trợ New Chat (`+ Mới`), xem danh sách session cũ và xóa từng session hoặc xóa tất cả.
- **Tài liệu CodeGraph**: Cập nhật `00_index.md`, `02_file_graph.md`, `03_type_graph.md`, `04_call_graph.md`, `05_state_graph.md`, `08_lifecycle.md`, `09_dependency_rules.md`, `10_risk_report.md`, `11_subsystems.md`, `13_resource_lifecycle.md`, `14_complexity_report.md`, `rules.md` và `CHANGELOG.md`.

