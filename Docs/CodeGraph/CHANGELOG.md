# CHANGELOG - Nhật ký Thay đổi CodeGraph FreeBook

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **FreeBook**.

## [1.3.459] - 2026-10-01

### feat: tu dien phien am tieng Nhat rieng cho VieNeu-TTS va hub Cai dat NghiTTS

Người dùng: *"VieNeu-TTS đọc tiếng Nhật nhiều từ chưa chính xác lắm"* ⇒ thêm **từ điển phiên âm riêng cho VieNeu** (hoạt động như từ điển của NghiTTS), đổi nút "Lưu" ở Reader thành 2 mục, thêm nav ở 2 màn TTS, và gom nav NghiTTS ở tab Cài đặt thành một hub.

- **⭐ Gốc rễ không phải "từ điển sai" mà là VieNeu CHƯA TỪNG có đường tra nào.** `TextPreprocessor.preprocess` (`:1037`, nơi tra từ điển ở `:990`) **chỉ** được gọi bởi NghiTTS (`PiperTTSService.swift:195`, `:341`); VieNeu chỉ gọi `TextPreprocessor.normalizeVietnameseText` (số/ngày, không espeak) ở `VieNeuTTSService.swift:301`/`:346`. Vì vậy tính năng **phải** gồm cả việc đưa từ điển **vào** đường tổng hợp, không chỉ dựng màn quản lý.
- **Từ điển độc lập hoàn toàn**: `actor VieNeuJapaneseDictionary`, file `FreeBook/TTS/phien-am-tieng-nhat.plist`. **Không** nằm trong `TextPreprocessor` vì file đó ở **1120/1121 dòng** (trần cứng) và vì hai từ điển phải độc lập (user chốt) — VieNeu **không** rơi về từ điển của NghiTTS và ngược lại.
- **`VieNeuJapanesePreprocessor`** (enum thuần, tầng service): **gấp macron LUÔN** (`ā ī ū ē ō` → ASCII) rồi, khi cờ bật, tra từ điển và/hoặc phiên âm romaji Nhật. Gấp macron **an toàn tuyệt đối** nên **không cần cổng chặn tiếng Việt**: 5 ký tự này không tồn tại trong bảng chữ tiếng Việt (đã cân nhắc "gấp mọi dấu phụ Latin + cổng chặn" và **loại** vì `.folding(.diacriticInsensitive)` ăn cả dấu tiếng Việt ⇒ "đàn" thành "dan").
- **Ràng buộc cứng — KHÔNG có nhánh tiếng Anh**: không gọi `EnglishPhonemeTransliterator`, không gọi `EspeakPhonemizer`, **không đọc `PreprocessorRuntimeConfig`** (2 khoá đó là của NghiTTS và sẽ kéo theo nhánh Anh/IPA). Token không phải Nhật và không khớp từ điển ⇒ giữ nguyên. Vì vậy cũng **không** tranh `NSLock` espeak với đường đọc NghiTTS.
- **Hai công tắc riêng của VieNeu**, cả hai **mặc định TẮT**, khoá **riêng** (`vieneuDictionaryEnabled`, `vieneuJapaneseTransliterationEnabled`) — **không** dùng `PreprocessorSettingKey` của NghiTTS. Đặt **chỉ** ở *Cài đặt TTS → Quản lý riêng của trình đọc*.
- **Reader**: nút "Lưu" ở sheet "Thêm từ mới" thành `Menu("Lưu")` 2 mục (*Lưu vào NghiTTS* / *Lưu vào VieNeu-TTS*), đúng khuôn `AddTTSReplacementSheet.swift:108-115`. Chip gợi ý tra đúng từ điển của đích, và **bỏ hẳn chip EN** khi đích là VieNeu (`TTSPhoneticSuggestionBuilder.suggestions(includeEnglish:)`).
- **Nav**: `TTSSettingsView` (nhánh VieNeu) và `VieNeuTTSTestView` — **đã tải ⇒ lối vào; chưa tải ⇒ cảnh báo + nút tải**.
- **Hub NghiTTS**: 3 nav rời ở tab Cài đặt gom thành **1 nav "Cài đặt NghiTTS"** → màn hub mới, **nhúng thẳng phần thử giọng** (trước đây là nav riêng trong "Cấu hình NghiTTS") ⇒ **xoá `NghiTTSTextToolView.swift`**. Lý do kỹ thuật bắt buộc: view cũ bọc **cả một `Form`**, mà `Form` **không lồng được trong `Form`** — nội dung phải chuyển thành các `Section` rời (`NghiTTSSettingsHubView+Sections.swift`).
- **Dữ liệu ban đầu**: script mới `Scripts/rebuild_vieneu_japanese_dictionary.py` (port `ForeignScriptClassifier` + `JapaneseTransliterator`, **bảng đọc trực tiếp từ file Swift**) dựng lại `phien-am-tieng-nhat.plist`: **gấp macron ở khoá** 30.565 → **30.377** → lọc classifier → **412** → phiên âm lại `transliterateRomaji` → **405** → 4 mục đặt tay (`chakra`/`matcha`/`sempai`/`tempura`) + xoá 3 (`chain`/`cosplay`/`kun`) ⇒ **409 mục**. **Gấp macron ở khoá là bắt buộc**: app tra bằng khoá **đã gấp dấu** nên khoá còn macron là **mục chết**, và classifier đòi **toàn ASCII** nên không gấp thì **571 từ Nhật** (`danzō`, `ryū`, `jōnin`, `yōkai`, `kaijū`…) bị loại oan. Bộ lọc loại **92/95 mục người dùng đã sửa tay** (kể cả từ Nhật thật như `jiraiya`, `ikari`, `izakaya`) — **đã chấp nhận có ý thức**, bù bằng cách thêm tay trong app.
- **Backup**: `BackupPaths.ttsDictionaryFiles` thêm `VieNeuJapaneseDictionary.fileName` ⇒ đi kèm nhóm `.dictCustom`; Archiver/Restorer/SizeEstimator đã lặp theo danh sách nên không phải sửa.
- **File**: thêm **6** (`VieNeuJapaneseDictionary.swift` **110**, `+Download.swift` **50**, `VieNeuJapanesePreprocessor.swift` **106**, `VieNeuJapaneseDictionaryView.swift` **358**, `NghiTTSSettingsHubView.swift` **57**, `+Sections.swift` **186**), xoá **1** (`NghiTTSTextToolView.swift`). Sửa: `VieNeuTTSService.swift` 389 → **398**, `TTSSettingsView.swift` 516 → **519** (chạm trần allowlist), `TTSSettingsView+VieNeu.swift` 206 → **277**, `VieNeuTTSTestView.swift` 377 → **385**, `VieNeuTTSTestView+Sections.swift` 224 → **270**, `AddWordSheet.swift` 200 → **253**, `NghiTTSSettingsView.swift` 158 → **155**, `TTSSettingsSection.swift` 36 → **28**, `ReaderView.swift` 2042 → **2049**, `BackupPaths.swift`, `TTSDictionaryEditView.swift`, `TTSPhoneticSuggestionBuilder.swift`.
- **Ràng buộc đã đo**: `check_architecture.py` **5 violation nền / 0 mới** (lượt đầu có **1 vi phạm mới** `ReaderView.swift` 2054 > 2053 — đã nén lại còn **2049**); `validate_links.py` **PASS 100% (16 doc, 629 file Swift)**.
- **Tài liệu CodeGraph**: `00_index`, `02_file_graph`, `03_type_graph`, `04_call_graph`, `05_state_graph`, `11_subsystems`, `14_complexity_report`, `rules`, `09_dependency_rules` **accept**; `08_lifecycle`, `10_risk_report`, `13_resource_lifecycle` **no-change-needed**. Sửa luôn 2 **link chết** trỏ tới file đã xoá (`00_index.md`, `02_file_graph.md`) — validator bắt được.
- **Kèm theo (công cụ, không phải mã app)**: 2 bản skill `push-ci-monitor` được repo track (`.workbuddy/skills/`, `.agents/skills/`) sửa lại phần theo dõi CI — bản cũ dạy dùng công cụ `schedule`/`DurationSeconds` của **Antigravity** (không tồn tại trên WorkBuddy); nay ghi đúng cách đã kiểm chứng: `gh run watch <id> --exit-status` chạy nền + `TaskOutput block=true`, và `gh` đã đăng nhập sẵn nên bỏ bước trích `GH_TOKEN`.

---

## [1.3.458] - 2026-10-01

### fix: bao toast khi nut tao giong bi chan boi phat lai, sap xep lai muc Tu Dien

Sửa lỗi UX người dùng báo: *"bấm vào nút tạo giọng nói nó không hoạt động, không mở ra được màn hình tạo giọng nói"*. Đã xác nhận bằng thực nghiệm — **dừng phát truyện thì bấm được** ⇒ thủ phạm là cổng `isBlockedByPlayback`, không phải lỗi điều hướng/sheet.

- **Nguyên nhân**: `creationSection` khoá nút bằng `.disabled(!isModelReady || !hasCloneGraphs || isBlockedByPlayback)` nhưng footer **chỉ có nhánh cho 2 điều kiện đầu** ⇒ khi bị khoá vì đang phát, footer rơi vào `else` và hiện câu hướng dẫn bình thường. Thêm nữa `.tint(.white)` toàn cục làm nút disabled trông y hệt nút thường ⇒ "nút bình thường, bấm không phản hồi".
- **Ràng buộc kỹ thuật quyết định cách sửa**: nút `.disabled` **không** phát sinh sự kiện ⇒ muốn báo bằng toast thì buộc phải **bỏ `isBlockedByPlayback` khỏi `.disabled`** rồi kiểm trong action.
- **Sửa**: thêm `playbackBlockReason(action:)` (`VieNeuVoiceLibraryView.swift`) tách **đúng nguyên nhân** (`isPlaying` = đang đọc truyện; chỉ `showFloatingWidget` = trình phát hiện nhưng có thể đã tạm dừng — nói "đang phát truyện" khi chỉ mở trình phát là sai). Hai nút bỏ cổng khỏi `.disabled`, toast `ToastManager.shared.show(message:type: .info)` thay vì mở sheet. Áp cho cả **"Tạo giọng mới"** lẫn nút **nghe thử** ở `voiceRow` (cùng lớp lỗi, `+Sections.swift:127`); nút nghe thử vẫn cho **dừng** bản nghe thử của chính nó.
- **Không đổi**: `isBlockedByPlayback` giữ nguyên định nghĩa và vẫn là cổng trong `enroll`/`playPreview`; không đụng `TTSManager`/`VieNeuTTSService`/`VieNeuTTSEngine`; không đổi `.sheet`.
- **Kèm theo (thay đổi có sẵn trong cây làm việc)**: `DictionaryHubView.swift` — dời mục **"Thay thế từ (TTS)"** xuống **cuối** danh sách (sau nhóm "Rule Dịch"), không đổi nội dung/đích điều hướng; `ttsReplacementStatusText` giữ nguyên.
- **File sửa**: `VieNeuVoiceLibraryView.swift` 372 → **385**; `VieNeuVoiceLibraryView+Sections.swift` 201 → **208** (cả hai < 400); `DictionaryHubView.swift` **199 → 199** (chỉ đổi thứ tự khối).
- **Ràng buộc đã đo**: `check_architecture.py` **5 violation nền / 0 mới**; `validate_links.py` **PASS 100%**.
- **Tài liệu CodeGraph**: `11_subsystems.md` **accept** (thêm mục 1.3.458).

---

## [1.3.457] - 2026-10-01

### fix: ep che do cao cho giong clone va sua cai dat TTS luon hien mac dinh

Sửa lỗi biên dịch CI của lượt `[1.3.456]` — **giữ nguyên commit subject cho lần push sửa CI**.

- **Đúng một lỗi thật trong log CI** (`Build and Archive App (Unsigned)`, exit 65): `VieNeuVoiceCatalog.swift:32:45: error: type 'VieNeuVoiceCatalog.Preset' has no member 'customGender'`.
- **Nguyên nhân**: `var isCloned` nằm **trong** `struct Preset` lồng nhau, nên `Self` = `Preset` — mà `customGender` là hằng của `VieNeuVoiceCatalog` (type ngoài). Phải viết tường minh `VieNeuVoiceCatalog.customGender`. Đây là bẫy `Self` trong type lồng nhau, **không** liên quan đến giới hạn `private` theo file.
- **Sửa**: đúng một dòng. `VieNeuVoiceCatalog.swift` **153 → 153** (không đổi số dòng).
- **Ràng buộc đã đo**: `check_architecture.py` **5 violation nền / 0 mới**; `validate_links.py` **PASS 100% (16 doc, 624 file Swift)**.
- **Tài liệu CodeGraph**: sửa cơ học ⇒ `04_call_graph`, `10_risk_report`, `11_subsystems`, `13_resource_lifecycle`, `rules` **no-change-needed** (mô tả trong doc vẫn đúng).

---

## [1.3.456] - 2026-10-01

### fix: ep che do cao cho giong clone va sua cai dat TTS luon hien mac dinh

Hai việc: (1) người dùng thử **16 bước** và báo *"khá hơn chút"* nhưng *"âm sắc vẫn chưa giống lắm"* ⇒ yêu cầu phần clone **luôn** dùng chất lượng cao bất kể cài đặt; (2) vào Cài đặt TTS từ tab Cài đặt **luôn hiện giá trị mặc định** (bật Tiết kiệm pin) dù đã đổi.

- **⭐ Đối chiếu nguyên văn với upstream — pipeline nhân bản KHÔNG có lỗi.** Đã tải mã nguồn thật ở revision đã ghim (`v3nano.py`, `fbank.py`, `onnx_extractor.py`, `audio_utils.py`) và `config.json`: `_load_mono` (mean kênh) · fbank 80-mel 16 kHz `mean_norm` · `_group_latent` · cắt `min(int(5×15,625), 140)` · `ref_mask` toàn 1 — **khớp hoàn toàn**. `speaker_encoder.embed` cũng đúng (không L2-normalize, không chia đoạn). `config.json` thật: `steps_default = 16`, `cfg_default = 3,0`, `ref_max_frames = 140`, `latent_scale = 0,25`. Vòng tổng hợp (`infer`) cũng khớp từng dòng, kể cả `max_chars = 140` / `max_seconds = 15` / `min_frames = 2`. Denoiser của upstream là **tuỳ chọn** (`None` ⇒ vẫn nhân bản được) nên việc app bỏ qua không phải lỗi.
- **Vậy thủ phạm là số bước Euler**: "Tiết kiệm pin" **mặc định BẬT** (`isPowerSaving`: khoá absent ⇒ `true`) và `VieNeuTTSService.swift:138` ép `.fast` (8 bước / `sway = -1`) bất kể người dùng chọn `.high`; có `requestedMode != nil` thì engine còn **không tự thích nghi**. Vòng Euler là nơi áp dụng **toàn bộ điều kiện hoá** (x-vector + `style`) nên 8 bước làm âm sắc không bám mẫu.
- **Sửa 1**: `VieNeuSynthesisPolicy.effectiveMode(requested:current:isClonedVoice:)` — giọng clone (`Preset.isCloned`) trả **`.high`** (16 bước / `sway = 0` / `cfg = 3,0` = đúng mặc định của model). Gọi ở `VieNeuTTSEngine.swift:216` ⇒ phủ cả "Nghe thử" lẫn đọc truyện. Đánh đổi: gấp đôi tính toán ⇒ máy nóng hơn — có chủ ý.
- **Sửa 2 (lỗi UI)**: `TTSSettingsView` giữ `vieNeuPowerSaving` / `vieNeuThreadCount` trong `@State` khởi tạo **một lần** lúc View dựng, mà lúc đó `VieNeuTTSService.shared` có thể chưa tồn tại ⇒ `?? true` rơi về mặc định; và **không bao giờ** được làm mới (trước đây chỉ `vieNeuSelectedMode` được làm mới trong `.onChange(of: ttsManager.tool)`). Thêm `refreshVieNeuSettings()` (`TTSSettingsView+VieNeu.swift`) đọc thẳng `UserDefaults` trong `.onAppear`.
- **Chuyển khoá** `vieneuPreferredMode` từ `VieNeuTTSService` sang `VieNeuSynthesisPolicy` (cùng chỗ với `powerSavingKey`/`threadCountKey`) để màn Cài đặt đọc được **không cần service**.
- **File sửa**: `VieNeuTTSEngine.swift` **400 → 400** (đổi đúng 1 dòng), `VieNeuTTSService.swift` 394 → **389**, `VieNeuSynthesisPolicy.swift` 126 → **149**, `VieNeuVoiceCatalog.swift` 148 → **153**, `TTSSettingsView+VieNeu.swift` 189 → **206**, `TTSSettingsView.swift` 513 → **516** (trần 519).
- **Ràng buộc đã đo**: `check_architecture.py` **5 violation nền / 0 mới**; `validate_links.py` **PASS 100% (16 doc, 624 file Swift)**.
- **Tài liệu CodeGraph**: `11_subsystems.md` + `rules.md` **accept** (thêm Luật 10/11/12); `03_type_graph`, `04_call_graph`, `05_state_graph`, `10_risk_report`, `13_resource_lifecycle` **no-change-needed** (sửa cơ học, mô tả vẫn đúng).

---

## [1.3.455] - 2026-09-30

### fix: sua luong nhan ban giong VieNeu (chon file, giong moi toi engine, tien do)

Người dùng thử trên máy thật (IPA cài qua **LiveContainer**) và báo **ba** lỗi mà đọc code **không** thấy: không chọn được file audio, bấm "Tạo giọng" **chờ lâu**, và — nặng nhất — **giọng mới đọc ra y như giọng mặc định `minh quân`**, tắt app mở lại mới đúng âm sắc.

- **Lỗi nặng nhất — giọng mới không bao giờ tới được engine, và im lặng.** `VieNeuTTSEngine.prepareLocked` có `guard runtime == nil else { return }` (`VieNeuTTSEngine.swift:150`) nên `catalog` chỉ được nạp **một lần**; engine sống suốt vòng đời app. `synthesize` chọn giọng bằng `catalog.preset(named:) ?? catalog.defaultPreset` (`:212`) ⇒ tên giọng chưa có trong catalog **rơi về giọng mặc định — không lỗi, không log**. Triệu chứng *"tắt máy mở lại thì đúng âm sắc"* là **chữ ký chính xác** của cơ chế này: mở lại app ⇒ `prepareLocked` nạp lại catalog ⇒ thấy giọng mới.
- **Sửa**: [`VieNeuTTSEngine+Catalog.swift`](../../Sources/Services/TTS/VieNeu/VieNeuTTSEngine+Catalog.swift) (**34**) — `refreshVoiceCatalog()` nạp lại catalog dưới `lock`; `VieNeuTTSService.refreshVoiceCatalog()` uỷ quyền; `VieNeuVoiceLibraryView` gọi sau **mọi** thay đổi kho giọng (`enroll`, `delete`, `commitRename`, và ngay sau `reload()`). Đặt ở **file mới** vì `VieNeuTTSEngine.swift` đã ở **đúng 400/400** — chỉ hạ `store`/`lock`/`catalog` từ `private` → `internal` **tại chỗ, không đổi số dòng**.
- **Chọn file**: `VieNeuVoiceCreatorView` bỏ `.fileImporter` (picker **mở** nhưng completion **không bao giờ chạy** khi app chạy trong LiveContainer) → dùng `DocumentPickerPresenter` của repo ([`DocumentPicker.swift`](../../Sources/Views/Common/DocumentPicker.swift) `:80-133`), mở với `asCopy: true` (`:36`) nên URL trả về **đã nằm trong sandbox app**, không cần security-scope.
- **`discardSample` có thể xoá file gốc của người dùng**: nay chỉ xoá khi URL nằm trong `FileManager.default.temporaryDirectory` (trước đây xoá vô điều kiện).
- **Tốc độ**: `enroll` **bỏ** bước `service.prepare()` thừa — nó nạp 4 graph chính + `sea_g2p.bin` (62,8 MB) trong khi `enrollVoice` chỉ cần `store` + `VieNeuVoiceCloner`. Cũng bỏ việc đặt `_currentVoice` ở đường tạo giọng.
- **Tiến trình**: thêm `enum VieNeuVoiceCloner.Stage` + callback `@Sendable` (`decoding` → `features` → `loadingGraphs` → `speaker` → `codec` → `style`); `VieNeuVoiceLibraryView+Sections` hiện nhãn từng bước (`EnrollProgress` box + `Task { @MainActor }`) thay vì một `ProgressView` xoay vô định. `.loadingGraphs` đặt ngay trước `VieNeuONNXRuntime(cloneOnlyModelStore:)` — bước chậm nhất.
- **Nút Lưu khoá mà không nói vì sao**: `saveBlockReason` trả lý do cụ thể (đang dò file / đang thu / chưa có mẫu / chưa nhập tên), render thành một mục trong Form; `canSave = saveBlockReason == nil`.
- **File mới**: `VieNeuTTSEngine+Catalog.swift` **34**. **File sửa**: `VieNeuTTSEngine.swift` **400 → 400** (không đổi), `VieNeuTTSService.swift` 376 → **394**, `VieNeuVoiceCloner.swift` 270 → **294**, `VieNeuVoiceCreatorView.swift` 329 → **365**, `VieNeuVoiceLibraryView.swift` 346 → **372**, `VieNeuVoiceLibraryView+Sections.swift` 171 → **201**.
- **Ràng buộc đã đo**: `check_architecture.py` giữ nguyên **5** violation nền cũ và **0** vi phạm mới; `validate_links.py` **PASS 100%**. **Không build trên Windows** ⇒ CI (`Build Unsigned IPA`) là nơi xác nhận biên dịch.
- **Tài liệu CodeGraph**: cập nhật **9** doc (`00_index`, `02_file_graph`, `04_call_graph`, `09_dependency_rules`, `10_risk_report`, `11_subsystems`, `13_resource_lifecycle`, `14_complexity_report`, `rules.md`) — 8 doc stale do **thêm file mới** (đổi *cấu trúc*), 4 trong đó còn stale do **đổi nội dung**.
- **Chưa kiểm chứng trên máy thật**: bước 4 của plan — nghe **đúng** giọng vừa tạo **trong cùng phiên** — là phép thử bắt buộc và **chỉ** chạy được trên thiết bị.

---

## [1.3.454] - 2026-09-30

### feat: nhan ban giong VieNeu tu audio mau (voice cloning)

Sửa lỗi biên dịch CI của lượt `[1.3.453]` — **giữ nguyên commit subject cho lần push sửa CI**.

- **Lỗi thật duy nhất trong log CI** (`Build and Archive App (Unsigned)`, exit 65): `VieNeuAudioResampler.swift:121:50: error: cannot find 'AVSampleRateConverterAlgorithm' in scope`.
- **Nguyên nhân**: `AVAudioConverter.sampleRateConverterAlgorithm` có kiểu `String?`, còn các hằng thuật toán là **biến toàn cục kiểu `String`** (`AVSampleRateConverterAlgorithm_Mastering`) — tên `AVSampleRateConverterAlgorithm` **không tồn tại** trong Swift, nên `.mastering` là sai. Không phải case của một enum nào.
- **Sửa**: dùng `AVSampleRateConverterAlgorithm_Mastering` + 2 dòng comment tại chỗ nêu rõ lý do, để không ai viết lại `.mastering`.
- **Xác minh API**: tra Apple docs JSON — `avaudioconverter/samplerateconverteralgorithm.json` cho `var sampleRateConverterAlgorithm: String?`; `avsamplerateconverteralgorithm_mastering.json` cho `let AVSampleRateConverterAlgorithm_Mastering: String`, `roleHeading = Global Variable`. Máy Windows **không** có SDK nên đây là nguồn đối chiếu duy nhất.
- **File sửa**: `VieNeuAudioResampler.swift` 192 → **194**, `rules.md` (+ **Luật 9**).
- **Ràng buộc đã đo**: `check_architecture.py` **5** violation nền cũ / **0** vi phạm mới; `validate_links.py` **PASS 100%** (16 doc, 623 file Swift).
- **Tài liệu CodeGraph**: `rules.md` **accept** (thêm Luật 9 về hằng `NS_TYPED_ENUM`); `04_call_graph`, `10_risk_report`, `11_subsystems`, `13_resource_lifecycle` **no-change-needed** — sửa cơ học, mô tả trong doc vẫn đúng.

---

## [1.3.453] - 2026-09-30

### feat: nhan ban giong VieNeu tu audio mau (voice cloning)

Người dùng yêu cầu tạo **giọng đọc riêng** từ audio mẫu. Chốt nguyên lý **trước** khi viết code: một "giọng" trong VieNeu-TTS v3 Nano **chỉ là 2 mảng float** — `speakerEmbedding` (192) + `style` (50×256) — không có model riêng cho từng giọng và **không** fine-tune. Nhân bản = chạy **3 graph clone** để sinh 2 mảng đó.

- **Pipeline** (port `prepare_reference` của bản tham chiếu): cắt ≤30 s → fbank 80-mel 16 kHz → mean-normalize → `speaker_encoder`; resample 24 kHz lấy 5 s đầu → `codec_encoder` → chuẩn hoá `(mu − latent_mean) / latent_std × latent_scale` → `groupLatent` (24 kênh × 6 = **144**, 468 → **78** frame) → `reference_encoder` (kèm `ref_mask` toàn 1) → `style`. Đầu ra được kiểm `spk.count == 192`, `style.count == 12 800`, và mọi giá trị hữu hạn.
- **Bẫy lớn nhất — `groupLatent` không phải concat kênh liền kề**: `out[c*g + slot][block] = zpad[c][block*g + slot]`. Viết sai (duỗi thẳng kênh liền kề) vẫn ra **đúng shape (50, 256)** nên **không** có lỗi nào nổi lên — chỉ giọng khác đi. Đã chứng minh bit-exact với biểu thức numpy (`max|d| = 0.000e+00`).
- **`speaker_encoder` ăn fbank, không ăn waveform** — truyền PCM thô sẽ ra embedding 192 số vô nghĩa mà **không** báo lỗi. Vì vậy `VieNeuVoiceCloner` chỉ có **một** đường gọi fbank.
- **Cầu C mở ngữ cảnh ORT riêng, chỉ 3 graph clone**: `VieNeuORTCreateCloneOnly` (+ `createBaseContext` tách ra từ `VieNeuORTCreate`, `loadCloneGraphsWithOptions`, `createCloneSession` đọc **mọi** tên input bằng `SessionGetInputName` theo kiểu all-or-nothing). Lý do: engine chính không được sửa, mà dùng lại ngữ cảnh của nó thì phải nạp thêm **~280 MB** graph chính — trong khi gói clone chỉ **95 500 985 B** (~91 MiB).
- **Sửa một lỗi biên dịch thật do chính lượt này**: đổi `copyFloatsInto`'s `outCount` sang `int64_t *` khiến hai caller cũ ghi **8 byte vào ô 4 byte** (hỏng heap, `check_architecture.py` **không** thấy). Đã trả về `int32_t *`.
- **Gói clone là tuỳ chọn**: `VieNeuModelStore.cloneGraphNames` **không** nằm trong `requiredNames` — điều kiện `store.missingNames.isEmpty` ở `VieNeuTTSEngine.swift:151` không bị đụng, nên người dùng chưa tải gói clone vẫn đọc truyện bình thường.
- **`VieNeuTTSEngine.swift` giữ đúng 400/400** (không sửa): giọng custom hoà vào danh sách giọng qua `VieNeuVoiceCatalog.load(modelStore:customStore:)`, custom xếp **trước** preset.
- **`VieNeuCustomVoiceStore.init` không chạm đĩa** — nó được gọi trên đường **đọc** (`VieNeuVoiceCatalog.load` ← `VieNeuTTSEngine.prepareLocked`); tạo thư mục trong `init` là ghi đĩa mỗi lượt tổng hợp. Thư mục chỉ tạo trong `add`/`save`.
- **Thu âm**: `VieNeuVoiceRecorder` đổi phiên âm thanh `.playback` → `.playAndRecord` rồi **khôi phục** qua `TTSAudioSessionController` — quên khôi phục thì TTS mất tiếng ở **mọi** lượt phát sau, một lỗi nằm khác chỗ với nguyên nhân. Thêm `NSMicrophoneUsageDescription` vào `project.yml`: thiếu nó thì iOS **kill app** ngay khi phiên âm thanh chạm tới input, không phải trả `false`.
- **File mới**: `VieNeuVoiceCloner.swift` **270**, `VieNeuCustomVoiceStore.swift` **226**, `VieNeuAudioResampler.swift` **192**, `VieNeuVoiceRecorder.swift` **148**, `VieNeuONNXRuntime+Clone.swift` **141**, `VieNeuVoiceLibraryView.swift` **346** + `+Sections.swift` **171**, `VieNeuVoiceCreatorView.swift` **329**.
- **File sửa**: `VieNeuONNXBridge.h` 121 → **181**, `VieNeuONNXBridge.m` 726 → **1155**, `VieNeuONNXRuntime.swift` 289 → **316**, `VieNeuModelStore.swift` 91 → **149**, `VieNeuModelClient.swift` 128 → **162**, `VieNeuVoiceCatalog.swift` 103 → **148**, `VieNeuTTSService.swift` 349 → **376**, `VieNeuConfig.swift` → **200**, `TTSSettingsView+VieNeu.swift` 179 → **189**, `VieNeuTTSTestView+Sections.swift` 218 → **224**, `project.yml`.
- **Hạ `private` → `internal`** (bẫy lặp lại lần thứ tư trong repo): `VieNeuONNXRuntime.handle` / `.maximumRank` / `.consume(_:fallback:)` — Swift giới hạn `private` theo file.
- **Ràng buộc đã đo**: `check_architecture.py` giữ nguyên **5** violation nền cũ và **0** vi phạm mới; `validate_links.py` **PASS 100% (16 doc, 623 file Swift)**. **Không build trên Windows** ⇒ CI xác nhận biên dịch.
- **Tài liệu CodeGraph**: cập nhật **12** doc (`00_index`, `01_project`, `02_file_graph`, `03_type_graph`, `04_call_graph`, `05_state_graph`, `09_dependency_rules`, `10_risk_report`, `11_subsystems`, `13_resource_lifecycle`, `14_complexity_report`, `rules.md`) — trong đó có cả nợ tài liệu của `[1.3.451]`/`[1.3.452]`.

---

## [1.3.452] - 2026-09-30

### ci: fbank-gate kich hoat bang push theo path thay vi chi workflow_dispatch

- **Trước**: cổng số chỉ chạy tay (`workflow_dispatch`) — mà `workflow_dispatch` chỉ hiện khi file đã có trên nhánh mặc định, nên trên nhánh làm việc thì **không bấm được**. Thêm `on.push.paths`: `Scripts/FbankGate/**`, `Sources/Services/TTS/VieNeu/VieNeuFbank.swift`, `.github/workflows/fbank-gate.yml`.
- **Hệ quả**: cổng trở thành **chống hồi quy** thật — sửa fbank là CI chạy lại và so với numpy ngay.
- **File sửa**: `.github/workflows/fbank-gate.yml` (+8/−2).
- **Tài liệu CodeGraph**: ghi nhận ở lượt `[1.3.453]`.

---

## [1.3.451] - 2026-09-30

### feat: VieNeuFbank fbank 80-mel Kaldi thuan Swift va cong kiem chung so

Tiền đề của nhân bản giọng: `speaker_encoder` cần **fbank 80-mel kiểu Kaldi**, không phải waveform. Viết thuần Swift rồi kiểm bằng **số** trước khi ghép vào pipeline.

- **`VieNeuFbank.swift`** **293** — `melSpectrogram(samples:sampleRate:)` + `meanNormalized(_:)`, 16 kHz, 80 bin, `snip_edges = true` (không đệm đầu/cuối). Cố ý **không** dùng Accelerate/vDSP để file biên dịch được bằng `swiftc` trần.
- **Cổng kiểm chứng số** — `Scripts/FbankGate/main.swift` **115** + `Scripts/FbankGate/gate.py` **210**: `gate.py probe` sinh WAV tất định, `gate.py golden` tính fbank bằng **numpy độc lập**, `swiftc -O VieNeuFbank.swift main.swift` biên dịch **chính file production**, rồi `gate.py compare` so từng ô. Kết quả: **RAW MAE = 0.000e+00** (bit-exact).
- **Vì sao cần cổng này**: máy phát triển là Windows **không có Swift toolchain**, nên tại chỗ chỉ chạy được bản **dịch Python** của cùng thuật toán — tự kiểm bằng bản dịch là lập luận vòng tròn. Đây là chỗ **duy nhất** mã Swift thật được thi hành trong CI ngoài `build-ipa.yml`.
- **File mới**: `VieNeuFbank.swift` **293**, `Scripts/FbankGate/main.swift` **115**, `Scripts/FbankGate/gate.py` **210**, `.github/workflows/fbank-gate.yml`.
- **Ràng buộc đã đo**: `check_architecture.py` **5** violation nền / **0** mới. **Không build trên Windows**.
- **Tài liệu CodeGraph**: ghi nhận ở lượt `[1.3.453]`.

---

## [1.3.450] - 2026-09-30

### feat: bo mode Thap, giam churn ONNX va them log chan doan tang nhiet

Sửa **12** file (9 Swift + 2 C/header bridge + 1 doc-mirror):

- **Bỏ hẳn mode "Thấp" (`.low`, 4 bước)**: người dùng nghe và chốt *"low tạo âm thanh quá kém, không rõ tiếng"*. `VieNeuSynthesisPolicy.Mode` quay lại **hai** chế độ `high`/`fast`; `tuning(for:)` bỏ `Tuning(steps: 4, …)`; `nextMode` bỏ nhánh `case .low: return nil`. Sàn `steps` là **8** — ghi thành **bài học bắt buộc** trong `enum Mode` để không ai thử 5/6/7 (giữ CFG không bù được sai số tích phân vòng Euler). Giá trị `"low"`/`"turbo"` cũ trong `UserDefaults` tự rơi về "tự động" vì `Mode(rawValue:)` trả `nil` — **không cần migrate**.
- **UI theo sau**: `displayName` bỏ `case .low` (còn Tự động / Chất lượng cao / Cân bằng); footer `VieNeuTTSTestView+Sections` còn hai mức; `TTSSettingsView+VieNeu` bỏ câu mô tả chế độ "Thấp". Cả hai Picker dùng `ForEach(Mode.allCases)` nên **không sửa vòng lặp**.
- **A2a — gỡ một tầng copy**: `VieNeuORTRunVectorEstimatorInto` (C) ghi thẳng vào buffer Swift cấp (`float *outBuffer, int32_t outCapacity`, trả `-1` nếu buffer nhỏ thay vì tràn) — Swift dùng một mảng `Float` zeroed bằng `repeating: 0, count: capacity` + `withUnsafeMutableBufferPointer`, bỏ `malloc`+`memcpy` phía C **và** `Array(UnsafeBufferPointer)` phía Swift. Hàm cũ `VieNeuORTRunVectorEstimator` giữ làm wrapper mỏng cho tương thích.
- **A2b — đệm `OrtValue` nhánh vô điều kiện**: `VieNeuORTRunVectorEstimatorUnconditionedInto` cache 4 tensor bất biến (`nullContext`/`nullMask`/`nullSpeaker`/`nullStyle`) **dựng từ buffer null thật** (không phải buffer `x`) và tái dùng suốt vòng lặp Euler, thay vì `makeTensor` lại mỗi bước. An toàn vì `VieNeuTTSEngine` **không có `unload`** ⇒ 4 buffer nguồn bất biến suốt vòng đời engine. Thêm `VieNeuORTResetVectorCache`; `VieNeuORTDestroy` giải phóng cache trước khi huỷ runtime. Comment bất biến ở `VieNeuONNXBridge.m:11-12` sửa để nêu ngoại lệ có kiểm soát.
- **L2 — đo churn**: `struct VieNeuORT` thêm `tensorCreates`/`tensorReleases`/`copiedBytes` + `makeTensorCounted`; mặt C `VieNeuORTChurnSnapshot`/`VieNeuORTResetChurnCounters`; `VieNeuONNXRuntime` thêm `churnSnapshot` (tuple 3 phần tử)/`resetChurnCounters`/`resetVectorCache`; `VieNeuTTSEngine.Timing` thêm 3 trường; `[VieNeuPerf]` in `churn=creates/releases/copiedBytes`.
- **L1 — đo busy/preload**: `NghiEnergyAccumulator` thêm `maxPreloadGapMs`/`lastPlaybackSubmitAt`; `[NghiEnergy] Summary` in thêm `busyPct=`/`preloadGapMs=`.
- **L3 — cầu Service → View**: `TTSManager.recordNghiSynthesis` phát `Notification.Name.nghiLocalSynthesisDidComplete` (không gọi thẳng singleton UI) ⇒ `ReaderEnergyDiagnostics` đọc `lastLocalSynthAgoMs` in trong `[ReaderEnergy] Summary`. **Đây là nguyên nhân gốc của việc thiếu `[TTSEnergy] Summary` cho đường local**: `RemoteTTSSynthesisCoordinator` chỉ phục vụ engine **remote**, engine local (vieneu/nghitts) đi qua `PiperSynthesisCoordinator` ⇒ không Summary nào chạy.
- **Cố ý không làm (GĐ2 huỷ)**: **không** cắt `maxConcurrentNghiRefills` 3→1–2, **không** cắt `optionalCap` 4→2, **không** đổi cửa sổ 12s — chờ log IPA mới để quyết, tránh mở lại lỗi đứt đoạn ngắn đã sửa ở 1.3.438.
- **Giới hạn dòng**: `VieNeuTTSEngine.swift` giữ **đúng 400/400** (nén comment + gộp tham số); `TTSManager.swift` **3957 → 3970** (baseline 3470 — vi phạm nền, không loại mới).
- **Sửa lỗi biên dịch đầu tiên (CI run `36722575609`)**: khi nén comment để giữ trần 400, một dòng trong `prepareLocked` bị mất ký tự xuống dòng ⇒ `VieNeuTTSEngine.swift:172:44: error: consecutive statements on a line must be separated by ';'` (`nullContextShape = nullBranch.shape        nullMask = nullBranch.mask`). Tách lại thành hai dòng và bù bằng cách gộp hai dòng comment liền kề ⇒ vẫn **đúng 400**. Không có lỗi nào khác (bridge C `.m` biên dịch sạch).
- Cổng: `check_architecture.py` **5 violation nền / 0 mới**; `validate_links.py` **PASS 100% (16 doc, 614 file Swift)**. **Không build trên Windows** ⇒ CI xác nhận biên dịch.

---

## [1.3.449] - 2026-09-30

### feat: VieNeu thêm chế độ "Thấp" (4 bước) giảm nhiệt

Sửa **5** file (4 Swift + 1 plan):

- **Đòn bẩy thật là SỐ BƯỚC, không phải độ lớn CFG**: `VieNeuTTSEngine.runChunk` hỏi `if tuning.cfg > 0` — **điều kiện nhị phân**, không theo tỉ lệ ⇒ `cfg = 3.0 → 1.5` tiết kiệm **0%**. Mỗi bước vẫn gọi `vector_estimator` **2 lần** khi có CFG ⇒ số lượt/đoạn: `.high` **32**, `.fast` **16**, `.low` **8**. Vòng Euler chiếm ~98% thời gian (`vector 7,60 s | khác 0,14 s` trên 28,01 s audio).
- **`VieNeuSynthesisPolicy`** (122 → **137**): `Mode` thêm case `low`; `tuning(for:)` thêm `Tuning(steps: 4, sway: -1.0, cfg: 3.0)`; `nextMode` thêm `case .low: return nil` (giữ hợp đồng "switch không có `default`", chặn bộ thích nghi tự nâng lên). Doc đầu file "hai chế độ" → "ba chế độ".
- **`VieNeuTTSTestView+Sections`** (218 → **222**): `displayName` thêm `case .low: return "Thấp"`; sửa footer lỗi thời (nêu đủ 32/16/8 lượt, **bỏ** câu về mục "Nhanh nhất" đã bị gỡ từ lâu).
- **`TTSSettingsView+VieNeu`** (179): dòng giải thích thêm một câu về chế độ "Thấp". Picker "Chế độ tạo audio" **không sửa vòng lặp** — `ForEach(Mode.allCases)` tự có case mới.
- **Sửa 3 comment sai `12 → 10`** (việc sửa tài liệu, **không** đổi hành vi): `TTSManager.swift:742`, `TTSManager+NghiPrefetchConcurrency.swift:15`, `Docs/Plans/2026-09-30-plan-tts-stutter-overlap-battery.md:47`. Giá trị 12 chỉ là **placeholder khởi tạo**, bị `applyVieNeuParamsIfNeeded` ghi đè bằng `bufferedSecondsTarget` = **10.0** khi khởi động.
- **Cố ý không làm**: **không** cắt `maxConcurrentNghiRefills` 3→1–2, **không** cắt `optionalCap` 4→2 (hai số này sinh từ chính báo cáo lỗi "đoạn 1→2→3 phải chờ" của người dùng ở `[1.3.438]` — cắt là mở lại lỗi cũ); **không** đụng `VieNeuTTSEngine.swift` (đang đúng trần **400/400**). Toggle "Tiết kiệm pin" giữ nguyên (vẫn ép `.fast`).
- Cổng: `check_architecture.py` **5 violation nền/0 mới**; `validate_links.py` **PASS 100% (16 doc, 614 file Swift)**. **Không build trên Windows** ⇒ CI xác nhận biên dịch.

---

## [1.3.448] - 2026-09-30

### fix: gộp VietPhrase ghi số liệu ra file meta kèm theo, không đọc lại file gộp

Sửa **3** file Swift:

- **Nguyên nhân**: mục gộp ở màn Thông báo đọc `DictionaryMergeTask.resultRecordCount` + `displayDate` **trực tiếp trong `body`**. Sau restart (`lastOutcome` chỉ sống trong RAM), `resultRecordCount` rơi xuống `DictionaryTextFileStore.loadCount(from:)` → `parseRecords` — **đọc cả `VietPhraseMerged.txt` (~1,4 triệu dòng) thành `String`, cắt mảng, dựng `Set<String>`** chỉ để lấy `.count`, **trên main thread** ⇒ đơ app, nghẽn luôn TTS (TTS cần main thread cập nhật highlight). `DictionaryMergeTask.init()` → `refreshFromDisk()` chặn main **ngay lúc mở app**.
- **`DictionaryMergeService`** (123 → **210**): thêm `Meta` (`Codable`, `version` + 4 số + `createdAt`), `mergedMetaFileName` (dẫn xuất từ `mergedFileName`), `mergedMetaURL()`, `writeMeta(_:)` / `loadMeta()` / `deleteMeta()`. `merge(progress:)` ghi meta **sau** khi ghi `.txt`, cùng khuôn nguyên tử `tmp` + `replaceItemAt`. `loadMeta` trả `nil` khi thiếu file / decode lỗi / `version` lạ.
- **`DictionaryMergeTask`** (236 → **216**): thêm `@Published private(set) var meta` + `isMetaMissing`. `summaryCounts`/`resultRecordCount`/`displayDate` nay **thuần RAM** (bỏ hẳn `loadCount` và `attributesOfItem`). `refreshFromDisk` chỉ `loadMeta()` ⇒ chạy thẳng trên `MainActor` an toàn. `finish` đọc lại meta. `applyToVietPhrase` + `discardResult` gọi `deleteMeta()` cùng lượt. **Xoá** `MergeSummary`, `summaryKey`, `persistSummary`, `clearSummary` (bản 1.3.446) + dọn khoá `UserDefaults` cũ trong `init`.
- **`NotificationInboxView+Merge`** (186 → **188**): thêm nhánh `isMetaMissing` hiện *"Số liệu chưa có — gộp lại để cập nhật."* khi có file `.txt` nhưng không có meta (file sinh từ bản app cũ) — **không** parse bù.
- **Cố ý không làm**: cache `hasResult` khỏi `fileExists` — chỉ là syscall `stat` cỡ µs, không phải nguyên nhân, mà cache đòi tự cập nhật ở 5 nơi.
- Cổng: `check_architecture.py` **5 violation nền/0 mới**; `validate_links.py` **PASS 100% (16 doc, 614 file Swift)**. **Không build trên Windows** ⇒ CI xác nhận biên dịch.

---

## [1.3.447] - 2026-09-30

### fix: nút "Nhập vào VietPhrase" mất chữ ở dark mode

Sửa **1** file Swift (`Sources/Views/Shelf/ShelfMain/NotificationInboxView+Merge.swift`):

- **Nguyên nhân**: lượt `1.3.446` để nút ở `.buttonStyle(.borderedProminent)` + `.tint(Color.primary)`. `borderedProminent` **không** tự đảo màu chữ theo tint — nó lấy nền từ tint và luôn đặt chữ theo một sắc sáng cố định (giả định tint là màu đậm/bão hoà). `Color.primary` ở **dark mode** = trắng ⇒ nền trắng + chữ sáng ⇒ **nút rỗng** (ảnh user gửi). `.foregroundStyle(Color(uiColor: .systemBackground))` đặt *bên trong* label không cứu được vì `.buttonStyle` ở ngoài ghi đè.
- **Không thể** chỉ gỡ `.tint(Color.primary)`: `MainTabView` đặt `.tint(.white)` toàn cục nên tint mặc định cũng là trắng, vẫn trắng-trên-trắng.
- **Cách sửa**: bỏ cả hai modifier sai, dùng `.tint` **xanh lá đậm literal** (`Color(red: 0.204, green: 0.780, blue: 0.349)`) + chữ `.foregroundColor(.white)` — theo khuôn tint đậm có sẵn trong repo (`ReaderAINameReviewCardView.swift`), đọc được ở mọi theme, không phụ thuộc tint hệ thống.

---

## [1.3.446] - 2026-09-30

### feat: TTS thay thế từ có tầng riêng theo truyện + làm lại UI mục gộp VietPhrase

Thêm **4** file Swift mới, sửa **17** file Swift trong `Sources/Services/` và `Sources/Views/`:

- **Tầng rule thay thế TTS riêng theo truyện** (`translate/books/<bookId>/character_replacements.json`):
  - **Luật gộp**: rule riêng **đè** rule chung theo `pattern` và đứng trước; rule riêng đang **tắt** vẫn **chặn** rule chung cùng `pattern` (kiểu tombstone) ⇒ tập `pattern` để chặn tính trên **toàn bộ** rule riêng, còn `compile` vẫn lọc `isEnabled`.
  - `applyReplacements(to:bookId:)` — `bookId` có default `nil` nên 8 call site cũ vẫn biên dịch; đã truyền `bookId` thật ở **cả 8** (`playingBookId` cho `TTSManager*`, `key.bookId` cho `TTSChapterPrefetcher` / `TTSNextChapterPrefixCache` / `+GoogleBatch`). `VieNeuTTSTestView` cố ý để `nil` (màn thử không có ngữ cảnh truyện).
  - **Tách file vì trần dòng**: `TTSReplacementManager.swift` 391 → **352** (đưa `compile`/`compileCharacterRun` sang `+PlanCompile.swift`, tầng riêng sang `+BookScope.swift`); `TTSReplacementManagerView.swift` 390 → **362** (đưa định tuyến theo tầng + `ruleRow` sang `+Layer.swift`). Hạ `private` → `internal` cho `ReplacementStep`, `planLock`, `compile`, `ruleRow`, `alertMessage`, `prepareForEdit`.
  - **Cache**: `bookRulesCache` (lock riêng) + `bookPlansCache` (dùng chung `planLock`); đổi rule **chung** ⇒ `rebuildReplacementPlan` gọi `invalidateBookPlans()` để mọi kế hoạch theo truyện dựng lại.
  - **UI**: `TTSReplacementManagerView` nhận `bookId`/`bookName`, tầng riêng **ẩn** "Khôi phục mặc định", thêm section **"Rule chung — lấy vào riêng"** + vuốt "Sang chung"; hub theo truyện thêm section **"Thay thế từ (TTS)"** (mở từ BookDetail và Reader).
  - **Backup/đổi nguồn**: `bookScopedTTSFiles` vào `bookScopedMigrationFiles` (đi theo truyện khi đổi nguồn); `BackupPaths.bookTTSFiles` đi cùng nhóm `dict/books/<slug>/`; khôi phục **tái dùng** `mergeReplacementRules` (hàm gộp JSON đã có). **Không** thêm `BackupScope`.
- **Sheet "Thêm thay thế TTS" khi bôi đen** (`AddTTSReplacementSheet.swift` 79 → **184**):
  - Ô **chuỗi thay thế luôn rỗng** khi mở — bỏ auto-fill ở `init` **và** `onChange(of: pattern)` (đổi hành vi cũ: trước đây điền sẵn từ rule trùng).
  - **Chip gợi ý** cho đúng chuỗi gốc, lấy từ **cả 2 tầng**, badge **R**/**C**, tầng riêng trước; bấm chip ⇒ nhập chuỗi thay thế + đặt công tắc theo rule đó; rule đang **tắt** ⇒ chip **mờ**.
  - **Lưu** = menu **2 mục** (riêng truyện / chung). Closure xử lý đặt ở `ReaderView+RuleTools.swift` vì `ReaderView.swift` ở đúng baseline **2053**.
- **Mục gộp VietPhrase ở màn Thông báo** làm lại theo mockup: nút **Nhập vào VietPhrase** full-width nổi bật, **Xuất file** / **Bỏ qua** ngang hàng, **3 chip** `gốc/sửa/xoá`, giờ ở góc phải, chú thích dài gộp còn 1 dòng; số liệu lưu `UserDefaults` (`vietPhraseMergeSummary`) để chip còn sau khi khởi động lại. `timeLabel` ở `NotificationInboxView` hạ `private` → `internal`.
- Cổng: `check_architecture.py` **5 violation nền/0 mới** (đã bắt 1 violation mới ở `ReaderView.swift` và sửa bằng cách rút closure ra extension); `validate_links.py` **PASS**. **Không build trên Windows** ⇒ CI xác nhận biên dịch.
- Đồng bộ tài liệu cho commit `e85b0b4` trước đó (`DictionaryMergeTask.swift`, `NotificationInboxView.swift`) mà CodeGraph chưa accept.

---

## [1.3.445] - 2026-09-30

### feat: gộp VietPhrase ra file text mới rồi nhập/xuất theo lựa chọn

Thêm **3** file Swift mới, sửa **5** file Swift trong `Sources/Models/`, `Sources/Services/`, `Sources/Views/`:

- **API duyệt từ điển (`TrieDictionary.allEntries()`, `FrozenTrieDictionary.swift` 86 → 183)**:
  - `VietPhrase.dat` là DoubleArrayTrie nhị phân và `TranslationManager.loadAllDictionaries` **xoá** `VietPhrase.txt` sau lần biên dịch đầu ⇒ không còn nguồn text nào để đọc từ điển gốc. Thêm `allEntries()`, khai ở **cả 3** conformer.
  - Kho `.dat` duyệt DFS theo **đúng** phép tính chỉ số của `trieMatches` nhưng chiều ngược; chỉ mục con dựng **một lượt** (gom slot theo `check[slot] > 0`) vì quét `charMap` mỗi nút là O(nút × số ký tự). Slot kết thúc có `code == 0` nên bị loại tự nhiên (mã ký tự bắt đầu từ 1).
- **Gộp ra file text mới (`DictionaryMergeService.swift`, file mới 123 dòng)**:
  - `VietPhrase.dat` + `CustomVietPhrase.txt` (áp tombstone) → **`VietPhraseMerged.txt`**, ghi qua `.tmp` + `replaceItemAt`. **Không** đụng từ điển gốc ⇒ một lỗi ở bước gộp chỉ tạo file sai mà người dùng vẫn xem được trước khi áp.
  - **Tự kiểm** `allEntries().count == wordCount`; lệch ⇒ `enumerationMismatch`, dừng và **không** tạo file.
- **Mục thông báo ghim (`DictionaryMergeTask.swift` 183 dòng + `NotificationInboxView+Merge.swift` 127 dòng)**:
  - Trạng thái lấy từ **file trên đĩa** ⇒ mục còn nguyên sau khi tắt app. Icon `symbolEffect(.pulse, options: .repeating)` khi đang gộp.
  - 3 hành động khi xong: **Nhập vào VietPhrase** (sao lưu `.dat` → `VietPhrase.dat.bak-merge` → `importDictionary` → xoá custom + tombstone), **Xuất file** (`ShareLink`), **Bỏ qua**.
  - Mục **ghim**: không thuộc `NotificationInboxManager` lẫn `NewChapterInboxManager` nên hai hành động toolbar ("Đánh dấu đã đọc hết" / "Xoá thông báo đã đọc") **không** xoá được nó.
- Cổng: `check_architecture.py` **5 violation nền/0 mới**; `validate_links.py` **PASS**. **Không build trên Windows** ⇒ CI xác nhận biên dịch.
- Đồng bộ tài liệu cho commit "Tiết kiệm pin" trước đó (`TTSSettingsView+VieNeu.swift`, `TTSSettingsView.swift`) mà CodeGraph chưa accept.

---

## [1.3.444] - 2026-09-30

### fix: rule dịch hán tự thuần không tự gắn space + màn thử VieNeu đi cùng đường Reader

Thêm **1** file Swift mới, sửa **5** file Swift trong `Sources/Services/` và `Sources/Views/`:

- **Rule dịch không tự gắn khoảng trắng cho hán tự thuần (`QuickTranslationRuleEngine.swift`)**:
  - `assemble` miễn auto-space 2 bên khi `rendered` là **hán tự thuần** (`!rendered.isEmpty && rendered.allSatisfy(VietPhraseTokenizer.isChineseCharacter)`). Rule dạng `唐三=唐三` cho ra đúng `唐三`, không còn ` 唐三 `.
  - Hán tự lẫn dấu câu/space/số/latin ⇒ **vẫn** chèn như cũ, nên `我买了四个苹果` + rule `<n>个 = 4 cái` giữ nguyên `我买了 4 cái 苹果`.
  - File **398 → 399/400** dòng (không có trong `architecture_allowlist.json`) — chỉ còn **1** dòng headroom.
- **Màn thử VieNeu đi cùng đường Reader (`VieNeuTTSTestView.swift` + 2 file extension + `TTSManager+VieNeu.swift`)**:
  - `playSample()` nay chạy đủ ba bước của Reader: `TTSReplacementManager.applyReplacements` → `NghiUtteranceSegmenter.expand(…, maximumLength:)` → `synthesizeWithDuration(boundaryKind:)` cho **từng** đoạn (trước đây gọi một lượt cho cả ô chữ với `boundaryKind` mặc định).
  - `TTSManager.vieNeuChunkLength` (mới, `nonisolated static`): đọc khoá `vieneuChunk` (mặc định 100) — cố ý **không** dùng `shared.chunkLength` vì đó là giá trị của engine đang chọn.
  - Báo cáo RTF **cộng dồn** qua các đoạn; chẩn đoán tách `đoạn` (NghiUtteranceSegmenter) khỏi `chunk engine` (`lastChunkCount`).
  - Footer mục "Kết quả" sửa lại cho đúng đường đi (trước đây mô tả sai).
- **Ghép WAV (`WAVConcatenator.swift`, file mới 56 dòng)**: nối N file WAV PCM16 cùng định dạng thành một file — cắt 44 byte header, nối payload, dựng lại header; kiểm 4 mốc `RIFF`/`WAVE`/`fmt `/`data` và trả `nil` khi lệch khuôn.
- Cổng: `check_architecture.py` **5 violation nền/0 mới**; `validate_links.py` **PASS**. **Không build trên Windows** ⇒ CI xác nhận biên dịch.
- Đồng bộ tài liệu cho thay đổi UI TTS của commit trước (`AISettingsSection.swift`, `TTSSettingsSection.swift`) mà CodeGraph chưa accept.

---

## [1.3.443] - 2026-09-30

### feat: đổi tên "Cài đặt VieNeu TTS" + xoá màn Debug Extension

- **Đổi tên**: nav row ở tab Cài đặt (`TTSSettingsSection.swift`) "Thử giọng VieNeu-TTS" → **"Cài đặt VieNeu TTS"**; `navigationTitle` của `VieNeuTTSTestView` cũng → **"Cài đặt VieNeu TTS"**.
- **Xoá màn Debug Extension**: gỡ nav row (`DeveloperSettingsSection.swift`); xoá **3 file** `ExtensionDebugConsoleView.swift` + `ExtensionDebugEventRow.swift` + `ExtensionDebugTraceReader.swift` (chỉ console dùng). **Giữ** `ExtensionDebugServerView` (row riêng) + `ExtensionDebugEventHub`/`ExtensionDebugEvent` (còn dùng bởi `JSExecutor` + editor toolbar).
- Cập nhật footer Section "Nhà Phát Triển" (bỏ tham chiếu console).
- Cổng: `check_architecture.py` **5 violation nền/0 mới**; `validate_links.py` **PASS**. **Không build trên Windows** ⇒ CI xác nhận biên dịch.

---

## [1.3.442] - 2026-09-30

### feat: mặc định Tiết kiệm pin + đổi tên mode/nhãn UI + gỡ máy móc pre-schedule (B)

Theo yêu cầu user (config hiện tại làm mặc định + sửa UI + làm "B").

### 1) Mặc định mới cho VieNeu
- Ngưỡng nạp bộ đệm **12 → 10 s** (`VieNeuSynthesisPolicy.bufferedSecondsTarget`).
- Số luồng ORT **4 → 2** (`VieNeuSynthesisPolicy.defaultThreadCount`).
- Độ dài phân đoạn **200 → 100 ký tự** (`applyVieNeuParamsIfNeeded` + `resetPrefetchSettings`).
- Số đoạn tải trước giữ 3; chế độ mặc định `.fast`.

### 2) "Tiết kiệm pin" thành overlay + mặc định BẬT
- `VieNeuSynthesisPolicy.isPowerSaving` mặc định **true** khi chưa có khoá; thêm `effectiveThreadCount(from:)` (ON ⇒ 2 luồng).
- ON ⇒ `engine.setRequestedMode(.fast)` + khoá 2 picker; OFF ⇒ `setRequestedMode(nil)` ("Tự động"). Không ghi đè `vieneuPreferredMode`/`vieneuThreadCount`.
- UI `vieNeuReaderSection`: Toggle **lên trên** → Picker **"Chế độ tạo audio"** → Picker **"Số luồng tổng hợp" (2/3/4, không ngoặc)** → dòng giải thích **luôn hiển thị** (kèm thuyết minh khi bật).

### 3) Đổi tên mode
`VieNeuTTSTestView+Sections.swift` `displayName`: **Tự động / Chất lượng cao / Cân bằng** (bỏ "· 16/8 bước").

### 4) Làm "B" — gỡ cụm máy móc pre-schedule
- Queue: xoá `.scheduled`, `getScheduledStatus`, `ScheduledStatus`, `onScheduleHandoff`.
- `TTSManager`: xoá wiring `onScheduleHandoff`, `handleNghiScheduledHandoff`, `nghiScheduledHandoffTask`.
- `TTSManager.swift` **4024 → 3957**; `NghiAudioPlayerQueue.swift` **324 → 288**.

### Số dòng & cổng
`TTSManager.swift` 3957; `NghiAudioPlayerQueue.swift` 288; `VieNeuTTSEngine.swift` 400/400; `TTSSettingsView.swift` 513/519; `VieNeuSynthesisPolicy.swift` ~118.
Cổng: `check_architecture.py` **5 violation nền, 0 mới**; `validate_links.py` **PASS** (04/10/11/rules `--accept`; 03/05/06/08/13 `--no-change-needed`). **Không build trên Windows** ⇒ CI xác nhận biên dịch.

**Còn sót nhỏ**: cờ `nextIsScheduled` trong `NghiAudioPlayerQueue` (luôn `false`) — dọn ở lượt sau nếu cần.

---

## [1.3.441] - 2026-09-30

### feat: bỏ pre-schedule hết chồng tiếng/nói lắp + log phoneme + ưu tiên fast/tiết kiệm pin

Ba lỗi TTS (grill-me chốt phương án): (1) nói lắp "chân tướng" → "chân chân tướng"; (2) chồng tiếng (2 đoạn song song); (3) VieNeu nóng máy/nhanh hết pin.

### 1) Bỏ pre-schedule `play(atTime:)` — hết chồng tiếng + nói lắp
- **Root cause**: `NghiAudioPlayerQueue.scheduleNextIfPossible` lập lịch đoạn kế bằng `nextPlayer.play(atTime: deviceCurrentTime + (duration - currentTime)/rate)`. `duration`/`deviceCurrentTime` ước lượng lệch ⇒ đoạn kế chạy **sớm**, đuôi âm tiết cuối chồng lên đầu đoạn kế.
- **Mô phỏng xác nhận**: cắt chunk **không** nhân đôi text (biên rơi giữa "chân" và "tướng" nhưng tái dựng khớp 100%) ⇒ lỗi ở **tầng phát audio tại biên**.
- **Sửa**: `scheduleNextIfPossible` → rỗng; giữ `nextPlayer` ở `prepareToPlay()`, bàn giao qua `audioPlayerDidFinishPlaying` → `promoteNextAfterCurrentFinished` → `play()`. `NghiAudioPlayerQueue` **368 → 324** dòng. (Cụm `.scheduled`/`onScheduleHandoff`/`handleNghiScheduledHandoff` là dead code — gỡ ở lượt "B", chưa làm.)

### 2) Log chẩn đoán
- `handleNghiAudioTransition`: `[TTSPerf] NghiHandoff prevTail=… nextHead=…` (text ở biên).
- `VieNeuTTSEngine.synthesize` → `logChunkPhonemes` (ở `+Adaptive`): `[VieNeuChunk] i=… text=… phonemes=…` (đường Reader trước đây không log phoneme).

### 3) VieNeu nóng máy/pin
- **Ưu tiên `fast`**: `VieNeuTTSEngine.mode` mặc định `.high` → `.fast`; `upshiftRTF` 0.45 → 0.30 (giảm ~2× tính toán ⇒ mát/pin hơn, chất lượng thấp hơn).
- **"Tiết kiệm pin" (opt-in)** + **số luồng ORT**: `VieNeuTTSService.powerSaving`/`threadCount`; `VieNeuSynthesisPolicy.threadCount(from:)` (giữ type thuần); UI toggle + Picker ở `vieNeuReaderSection` kèm hướng dẫn. `threadCount` áp dụng sau khi **nạp lại engine**.

### Số dòng & cổng
`NghiAudioPlayerQueue.swift` 368 → 324; `TTSManager.swift` net 0 (4024); `VieNeuTTSEngine.swift` 400/400 (đúng trần); `VieNeuSynthesisPolicy.swift` 94 → 114; `VieNeuTTSService.swift` 345; `TTSSettingsView.swift` 513/519.
Cổng: `check_architecture.py` **5 violation nền, 0 mới**; `validate_links.py` **PASS** (04/10/11/rules `--accept`; 03/05/06/08/13 `--no-change-needed`). **Không build trên Windows** ⇒ CI xác nhận biên dịch.

**Cần kiểm chứng máy thật (IPA):** hết chồng tiếng; 1→2→3 liền mạch; gap do bỏ pre-schedule không đáng kể; "Tiết kiệm pin" mát hơn rõ rệt. **Còn nợ "B"**: gỡ cụm `.scheduled`.

---

## [1.3.440] - 2026-09-29

### fix: bump generation mỗi lần schedule làm vô hiệu hoá task nạp trước cùng batch

Người dùng báo 1.3.439 **không sửa được** 2 lỗi: (a) đầu phát chờ giữa đoạn 1→2→3; (b) sang chương chờ giữa tên chương và đoạn 1 (kèm báo thêm: 2 đoạn phát song song).

### Root cause (bug logic xác định, không phải timing)
`scheduleNghiRefill()` bump `nghiRefillGeneration &+= 1` **mỗi lần** gọi (`TTSManager.swift:2835`), nhưng guard `isValidNghiRefillContext` đòi `nghiRefillGeneration == refillGeneration` **bằng ĐÚNG** (`:2745`). `fillNghiRefillUpToCapacity()` lập **3 task cùng batch** (`N+1`, `N+2`, `N+3`) → gen `G+1/G+2/G+3`. Khi task chạy, gen hiện tại đã là `G+3` ⇒ **2 task đầu bị vô hiệu** (guard fail ngay trước bước tổng hợp), chỉ task cuối sống. Tệ hơn, `defer` chỉ dọn khi gen khớp (`:2855`) nên 2 task bị vô hiệu **rò rỉ** trong `nghiRefillTasks`/`nghiRefillInFlightIndices` ⇒ `fillNghiRefillUpToCapacity` dần hết chỗ ⇒ **pool nạp trước nghẽn rồi tắt**. Đây là lý do đệm nóng 1.3.439 (dựa vào pool) không có tác dụng: pool không chạy thật.

Bug lộ ra từ 1.3.438: lượt đó thêm pool đa luồng nhưng để lại bump per-schedule — vốn vô hại khi chỉ có **1** refill (`nghiRefillTask: Task?`), nhưng phá khi có **nhiều** task cùng batch.

### Sửa
Bỏ `nghiRefillGeneration &+= 1` khỏi `scheduleNghiRefill()`. Chỉ `cancelNghiRefill()` (đổi chương/session/seek/engine — gọi từ `clearCurrentParagraphPrefetchCache`) mới bump. Cả batch dùng chung gen ⇒ 3 task đều sống + `defer` dọn đúng ⇒ pool hoạt động.

### Số dòng & cổng
`TTSManager.swift` **4024 → 4024** (net 0: bỏ 1 dòng bump, thêm 1 dòng comment).
Cổng: `check_architecture.py` **5 violation nền, 0 mới**; `validate_links.py` **PASS** (04/10/11/rules `--accept`, 05/06/08/13 `--no-change-needed`). **Không build được trên Windows** ⇒ CI xác nhận biên dịch.

**Cần kiểm chứng lúc chạy:** đầu phát 1→2→3 liền mạch; biên chương tên chương → đoạn 1 liền mạch; chồng tiếng (nếu còn → cần log `[NghiAudioPlayerQueue] schedule` từ máy thật).

---

## [1.3.439] - 2026-09-29

### fix: đọc số thập phân/0 đầu, đệm nóng đầu phát & biên chương, tách speed khỏi prefetch

Bốn lỗi TTS người dùng báo, đã grill-me chốt phương án trước khi code: (A) `0.001` đọc thành `1`, `001` cần đọc `không không một`, `0, 001` (có space) ≠ `0,001`; (B) bắt đầu nghe / giữa đoạn 1→2→3 bị chờ; (C) sang chương mới tên chương đọc ngay nhưng gap trước đoạn đầu; (D) đổi tốc độ phát lại "tạo âm thanh lại".

### 1) Đọc số thập phân & số có số 0 đầu (`TextPreprocessor.swift`)
- **Root cause `0.001` → `1`**: `formatNumbers` dùng `thousandsSeparatedNumber = (\d{1,3}(?:\.\d{3})+)` để xóa dấu chấm (ngăn cách nghìn) ⇒ `"0.001"` khớp → `"0001"` → `spell` → `"1"`. Nay **chỉ xóa chấm khi phần nguyên trước chấm đầu ≠ `0`**; `"0.xxx"` giữ nguyên để rơi vào `processDecimals`.
- Regex `decimal` và `percentageDecimal`: thay dấu phẩy cố định bằng lớp ký tự chấm-hoặc-phẩy để nhận **cả chấm và phẩy**; vẫn space-sensitive ⇒ `"0, 001"` không khớp (giữ thành danh sách).
- `processDecimals` / `processPercentages`: bỏ cắt `^0+` ở phần thập phân, đọc **từng chữ số giữ số 0** ⇒ `"0,001"` → "không phẩy không không một".
- `processDigits`: số có số 0 đầu (vd `"001"`) đọc từng chữ số → "không không một". **Cố ý KHÔNG đặt ở `VietnameseNumberSpeller.spell`** vì `processDates` gọi `spell("01")` cho ngày ⇒ `"01/02"` sẽ thành "không một tháng hai".

### 2) Đệm nóng đầu phát & biên chương
- Thêm `warmNghiRefillForPlaybackStart()` (`TTSManager+NghiPrefetchConcurrency.swift`, ratchet-down) gọi `fillNghiRefillUpToCapacity()`; chèn 1 dòng tại `continueStartSpeaking` (`TTSManager.swift`).
- `continueStartSpeaking` là điểm vào **chung** của fresh start (`startSpeaking`) lẫn sang chương mới (`applyNextChapter`) ⇒ một call site phủ cả hai: tổng hợp trước `N+1..N+3` song song với đoạn hiện tại (đoạn đầu thường lạnh) ⇒ 1→2→3 liền mạch, hết gap ở đầu phát và ở biên chương.

### 3) Tách tốc độ khỏi nạp trước
- Điều tra **cả 4 engine**: **không engine nào tái tổng hợp audio đang phát khi đổi tốc độ** — nghitts/vieneu `updateRate` playback-only (tổng hợp x1.0); system per-utterance; google tổng hợp `speed: 1.0` (`TTSManager+Playback.swift:58`); extension synthesisKey không chứa speed.
- Điểm thừa duy nhất: `updatePlaybackParams` (`:1122`) mỗi nấc kéo slider còn gọi `cancelNghiWakeTask()` + `updateNghiPrefetchWindow()` ⇒ kích tổng hợp đoạn kế + chương sau. Nay nhánh local **chỉ** `nghiAudioPlayerQueue.updateRate(speed)`; vòng `nghiWakeTask` tự hiệu chỉnh đệm theo tốc độ mới.

### 4) Pitch local (task #9) — bỏ
Quyết định grill: giữ **no-op** cho engine local (không thêm `AVAudioUnitTimePitch` vào `NghiAudioPlayerQueue`), giữ `disablePitch` trong UI. Không code.

### Số dòng & cổng
`TextPreprocessor.swift` **1121 → 1120** (net −1: viết lại 4 hàm gọn + ternary 1 dòng để không vượt baseline 1121); `TTSManager.swift` **4024 → 4024** (net 0: +1 call site warmup, −1 dòng ở `updatePlaybackParams`); `TTSManager+NghiPrefetchConcurrency.swift` 46 → 58 (thêm `warmNghiRefillForPlaybackStart`).
Cổng: `check_architecture.py` **5 violation nền, 0 mới**; `validate_links.py` **PASS** (04/10/11/rules `--accept`, 05/06/08/13 `--no-change-needed`). **Không build được trên Windows** ⇒ CI xác nhận biên dịch.

**Cần kiểm chứng lúc chạy (IPA máy thật):** đệm nóng D/F thực sự liền mạch và không trùng tiếng; đổi tốc độ không kích tổng hợp.

---

## [1.3.438] - 2026-09-29

### fix: nạp trước đồng thời VieNeu + safe-window 150ms (chống đứt đoạn ngắn / chồng tiếng)

Người dùng báo: **đoạn văn ngắn đọc xong → đoạn kế không kịp tổng hợp → phải chờ lâu mới nghe tiếp**. Nguyên nhân gốc nằm ở cơ chế nạp trước, không phải engine.

### 1) Đứt đoạn ngắn — root cause: nạp trước BẮT BUỘC tuần tự 1 đoạn
`canScheduleNghiRefill(hasRefillTask:hasRetryTask:)` trả `!hasRefillTask && !hasRetryTask` ⇒ **chỉ 1 lượt refill được phép bay cùng lúc** — nghiêm ngặt tuần tự. VieNeu tổng hợp đắt (`VieNeuSynthesisPolicy.bufferedSecondsTarget = 12`, RTF ~0,29 + chi phí cố định theo chunk) nên một lần nạp trước tuần tự **không bao giờ đi trước kịp** một đoạn ngắn có thời lượng audio ≤ 1 lần tổng hợp ⇒ đúng lỗi người dùng báo. NghiTTS (Piper) tổng hợp gần tức thì nên giữ 1 luồng.

**Sửa (chung cho đường local NghiTTS/VieNeu):**
- Đổi stored prop đơn thành **pool**: `nghiRefillTask: Task?` → `nghiRefillTasks: [Int: Task]`; `nghiRefillInFlightIndex: Int?` → `nghiRefillInFlightIndices: Set<Int>`. `cancelNghiRefill()` lặp huỷ mọi task + xoá cả hai tập.
- `maxConcurrentNghiRefills`: **3** cho `vieneu`, **1** cho `nghitts` (giữ nguyên behaviour Piper).
- File mới **`TTSManager+NghiPrefetchConcurrency.swift`** (46 dòng, ratchet-down): `fillNghiRefillUpToCapacity()` lập lịch tới khi đầy luồng hoặc hết ứng viên (safety counter 32, mỗi task xong `defer` gọi lại `updateNghiPrefetchWindow` nên pipeline tự duy trì).
- `nghiRefillCandidate` thêm bỏ qua chỉ mục **đang bay** (`!nghiRefillInFlightIndices.contains(...)`) + cap optional reserve **4 (vieu) / 2 (nghitts)**.
- Xoá `static func canScheduleNghiRefill` cũ. `scheduleNghiRefill()` → `internal func scheduleNghiRefill() -> Bool` có guard `nghiRefillRetryTask == nil` + in-flight + `nghiRefillTasks.count < maxConcurrentNghiRefills`; đường reuse trong `playNghiTTS` dùng `nghiRefillTasks[index]`.
- `updateNghiPrefetchWindow()` thay khối "nạp 1 rồi return" bằng `fillNghiRefillUpToCapacity()` (cả nhánh đầu và nhánh `cachedTime < threshold`).

### 2) Nâng ngưỡng mặc định VieNeu 8s → 12s
`vieneuSafeCachedTimeThreshold` default `NghiSynthesisPolicy.defaultSafeCachedTimeThreshold` (8) → **12.0**; `applyVieNeuParamsIfNeeded()` fallback khi chưa có `UserDefaults` cũng về `VieNeuSynthesisPolicy.bufferedSecondsTarget` (12) thay vì 8. (Ngưỡng này đã có nơi đọc từ 1.3.435 qua `currentSafeCachedTimeThreshold`.)

### 3) Safe-window 50 → 150ms (chống chồng tiếng)
`NghiAudioPlayerQueue.prepareNextNghiAudioIfPossible` (task #8): `guard wallClockRemaining > 0.050` → `> 0.150`. Lý do: `AVAudioPlayer.duration` có thể ước lượng ngắn hơn thực tế vài ms ⇒ một `startTime` tính sát đích rất dễ rơi **trước** khi đoạn hiện tại kết thúc ⇒ hai đoạn phát song song. Đánh đổi một khoảng nghỉ cực nhỏ lấy việc chắc chắn không bao giờ schedule sớm.

### Số dòng & cổng
`TTSManager.swift` **4028 → 4024** (net −4, nhờ xoá `canScheduleNghiRefill` + gom comment); file mới `TTSManager+NghiPrefetchConcurrency.swift` (46); `TTSManager+VieNeu.swift` (fallback 12s); `NghiAudioPlayerQueue.swift` (comment + guard, ~+2 dòng).
Cổng: `check_architecture.py` **5 violation nền, 0 mới** (`TTSManager` giảm 4 dòng ⇒ an toàn); `validate_links.py` **PASS 16 documents / 609 Swift files** (13 doc được `--accept` bắt kịp luôn nợ cũ từ 1.3.437). **Không build được trên Windows** ⇒ CI xác nhận biên dịch.

**Còn lại (treo):** `vieneuPitch` vẫn no-op — `NghiAudioPlayerQueue` chỉ có `updateRate`, chưa có `AVAudioUnitTimePitch` (task #9); clone giọng (overlay `VieNeuVoiceCatalog` + script Python trích `speaker_encoder/codec_encoder/reference_encoder`, task #10/#11).

---

## [1.3.437] - 2026-09-29

### refactor: gom tien xu ly so VieNeu len service chung

Theo ý người dùng "chỉ dùng tiền xử lý chung (thay thế ký tự Tts)", chuyển mở rộng số/ngày/tháng của VieNeu từ engine lên tầng service để đồng nhất với NghiTTS (Piper).

- **Phát hiện**: cả Piper và VieNeu đều xử lý số qua cùng hàm chung `TextPreprocessor.processVietnameseText`. Piper gọi nó bên trong `preprocess` (tại `PiperTTSService.synthesize`, :195/:341); VieNeu gọi bản mỏng `normalizingForVieNeu` (= `processVietnameseText`, bỏ espeak vì `sea_g2p.bin` không có IPA) ngay trong `VieNeuTTSEngine.synthesize`. `applyReplacements` (thay thế ký tự chung) không xử lý số.
- **Đổi**: xoá lớp gọi riêng trong engine; gọi `TextPreprocessor.normalizeVietnameseText` (đổi tên trung lập, vẫn = `processVietnameseText` không espeak) tại `VieNeuTTSService.executeInternalSynthesis` và `…Stream`. Mọi đường (Reader, prefetch, next-chapter-prefix, thử giọng) đều qua `VieNeuTTSService.shared` nên bao phủ đủ.
- **Tác dụng**: engine VieNeu không còn tự tiền xử lý, đồng nhất với Piper; số/ngày vẫn đọc đúng (bắt buộc vì vocab thiếu chữ số).
- **File**: `TextPreprocessor+Numbers.swift` (đổi tên hàm), `VieNeuTTSEngine.swift` (xoá gọi, net ~-5 dòng, trần 400 an toàn), `VieNeuTTSService.swift` (thêm gọi 2 chỗ).

## [1.3.436] - 2026-09-29

### fix: VieNeu ton trong boundaryKind + sua 4 loi hau kiem dinh

Người dùng cài IPA của 1.3.435 và xác nhận **đã có âm thanh** (hai nguyên nhân gốc đã đúng), rồi báo tiếp 4 vấn đề.

- **"Chọn tốc độ tạo audio không đổi ngay" — lỗi UI, không phải engine.** `Picker` buộc vào một `Binding` đọc thẳng `VieNeuTTSService.preferredMode`; `VieNeuTTSService` là class thường (**không** `@Observable`) nên SwiftUI **không thấy** nó đổi. Setter của `preferredMode` **đã** gọi `engine.setRequestedMode(...)` từ trước, tức engine luôn đúng — chỉ UI stale. Đây là **lần thứ hai** đúng lỗi này (lần đầu ở `VieNeuTTSTestView`, đã ghi vào `rules.md` ở 1.3.421). Sửa theo khuôn đã ghi: `@State var vieNeuSelectedMode` khai ở `TTSSettingsView` (extension không thêm được stored property) + `.onChange` đẩy xuống service; xoá `vieNeuModeBinding`.
- **"Âm thanh đọc dễ mất chữ" — VieNeu bỏ qua `boundaryKind`.** `ONNXPiperEngine` **có** `pauseDuration(for:)` và nối khoảng lặng đuôi vào cuối mỗi utterance (`:436`). `VieNeuTTSService` nhận `boundaryKind` trong chữ ký (`:137`, `:156`) nhưng **chưa bao giờ dùng**. Mà `joinChunks` chỉ chèn khoảng lặng **giữa các chunk nội bộ**, **không bao giờ** cho chunk cuối; mỗi payload lại đã bị `trimAndFade` cắt còn ~40 ms đệm ⇒ phoneme cuối utterance N dính thẳng vào phoneme đầu utterance N+1 ⇒ nghe như **mất chữ**.
  * Thêm `VieNeuTTSEngine.pauseSeconds(for boundaryKind:)` — **bản sao ánh xạ của Piper, đọc cùng khoá `UserDefaults`** (`paragraphPauseDuration` / `sentencePauseDuration` / `phrasePauseDuration` / `bracketPauseDuration` / `newlinePauseDuration`) nên một cài đặt điều khiển cả hai engine.
  * Khoảng lặng chèn thêm **không phải lời đọc** ⇒ cộng vào `insertedPauseSeconds`, nếu không `speechDuration` bị thổi lên và RTF theo lời nói sai.
  * `boundaryKind` cũng vào `makeDefaultSynthesisKey`: nó đổi audio, nên hai lượt cùng văn bản khác ranh giới **không được** gộp (`PiperSynthesisCoordinator` coalesce theo khoá; Piper cũng đưa `boundary=` vào khoá).
  * **Vì sao không lộ ở màn thử giọng**: màn đó đưa **cả đoạn** vào một lượt gọi nên `joinChunks` tự chèn khoảng lặng theo dấu câu. Chỉ đường Reader (cắt trước rồi gọi từng mảnh) mới lộ — đúng lý do người dùng thấy "chất lượng kém hơn hẳn".
- **"Chất lượng kém hơn hẳn màn thử giọng" — nay có số để trả lời, trước đó thì không.** Màn thử giọng hiện mode/chunk/dropped **trên UI**; đường Reader **không có gì** — engine chỉ log **lúc đổi** chế độ và **một lần cho cả vòng đời** cho phoneme bị bỏ. Thêm `logSynthesisPerf` (`+Adaptive`, để `VieNeuTTSEngine.swift` không vượt trần 400) ghi **mỗi lượt**: `mode`, `chunks`, `dropped`, `chars`, `pcm`, `speech`, `synth`, `rtf`, `boundary`. Hai giả thuyết cần số này phân định: (a) bộ thích nghi **hạ xuống `fast`** vì đường Reader có nhiều payload nhỏ ⇒ RTF cao hơn; (b) **cắt hai tầng** — engine tự cắt ở `VieNeuConfig.maxChunkCharacters` = **140**, Reader cắt trước ở `vieneuChunk` (mặc định 200).
- **"Đoạn này chưa đọc xong thì đoạn khác đã đọc song song" — thêm chẩn đoán, KHÔNG đoán bừa.** Cơ chế `play(atTime:)` + `deviceCurrentTime` của `NghiAudioPlayerQueue` rất nhạy thời điểm và **không thể suy ra nguyên nhân chỉ bằng đọc mã**. Lượt này cố ý không đổi hành vi: thêm log `[NghiAudioPlayerQueue] schedule next=… cur=… mediaRemaining=… rate=… wallRemaining=… duration=… currentTime=…` (đủ để thấy `wallRemaining` có bị tính nhỏ đi không ⇒ `nextPlayer` bắt đầu trước khi `currentPlayer` kết thúc), cộng **một chốt an toàn** trong `prepareNextNghiAudioIfPossible`: không nạp lại đoạn mà queue **đang phát** (`currentItem`), vì `currentParagraphIndex` có thể chưa kịp nhảy do bàn giao chạy nền ⇒ `nextIndex` trỏ vào chính đoạn đang phát ⇒ đoạn đó phát **lần thứ hai**.
- **File**: `VieNeuTTSEngine.swift` 370 → **395**, `VieNeuTTSEngine+Chunking.swift` 294 → **323**, `VieNeuTTSEngine+Adaptive.swift` 56 → **84**, `VieNeuTTSService.swift` 282 → **319**, `NghiAudioPlayerQueue.swift` 351 → **364**, `TTSSettingsView.swift` 502 → **509**, `TTSSettingsView+VieNeu.swift` 157 → **151** (xoá `vieNeuModeBinding`), `TTSManager.swift` **4028** (net 0).
- **Ràng buộc đã đo**: `check_architecture.py` giữ nguyên **5** violation nền và **0** vi phạm mới; `validate_links.py` PASS. Không build được trên Windows.
- **Còn lại**: nguyên nhân **chồng tiếng** chưa xác định — cần log từ máy thật. `vieneuPitch` vẫn chưa nghe thấy (queue không có pitch).

## [1.3.435] - 2026-09-29

### fix: mo gate engine local + sua 2 nguyen nhan goc lam VieNeu khong ra tieng

Người dùng báo *"VieNeu tts vẫn không tạo được âm thanh, tôi thấy nó hoàn toàn không tạo ra được wav"* kèm log `app_logs (54).txt`, và ba câu hỏi về UI (2 chỗ config số đoạn tải trước; thời gian dãn tiến trình nạp trước có dùng không; độ dài đoạn văn có dùng không / vì sao hiển thị ra đây).

- **Log là bằng chứng quyết định**: có `[NghiEnergy] Underrun chapter=124 index=12` (chứng tỏ **đã vào** `playNghiTTS`) nhưng **không có** dòng `[TTSRoute] playAudioData …` nào ⇒ audio bị vứt bỏ **sau khi tổng hợp xong**, không lỗi, không toast.
- **Nguyên nhân gốc A — guard danh tính sai.** `isIdentityValid()` trong `playNghiTTS` (`TTSManager.swift:3638`) kết bằng `self.tool == "nghitts"`. Với VieNeu, `service.synthesizeWithDuration(...)` chạy **thật** (vài giây CPU, máy nóng) rồi `guard isIdentityValid() else { return }` (`:3659`) trả `false` ⇒ **vứt bỏ audio vừa tổng hợp**. Sửa: `TTSManager.isLocalEngine(self.tool)`.
- **Nguyên nhân gốc B — context so với literal.** `isContextValid` (`:3120`) đòi `tool == context.engine`, nhưng context dựng bằng `engine: "nghitts"` hardcode ở `:3191` và `:3348` ⇒ luôn `false` với VieNeu. Sửa: `engine: tool` ở cả hai chỗ, và `TTSManager.isLocalEngine(context.engine)` cho nhánh kiểm tra thành viên hàng đợi (`:3124`).
- **Mở ~28 gate `tool == "nghitts"` còn lại sang `isLocalEngine`.** Đáng chú ý:
  * `:99` (`tool.didSet`) — VieNeu **không bao giờ được warm-up** vì nhánh `else` huỷ task trước khi `scheduleNghiWarmUp()` kịp tự guard.
  * `:1448` / `:1481` / `:1525` — `pause()`/`resume()` không tác động lên `nghiAudioPlayerQueue` mà VieNeu đang phát.
  * `:1762` / `:1810` — `nextParagraph`/`previousParagraph` nhảy theo **đoạn văn cha** (`paragraphs[i].paragraphIndex`), không phải utterance; VieNeu cũng đi qua `NghiUtteranceSegmenter` nên cần đúng quy tắc này.
  * `:2491` — `updatePrefetchWindow()` đẩy VieNeu sang **đường remote** (`dispatchRemotePrefetch`).
  * `:3338` — `handleNghiAudioTransition` khi guard sai còn gọi `nghiAudioPlayerQueue.stop()` ⇒ **cắt tiếng giữa chừng** (guard có tác dụng phụ phá hoại).
  * `:2592` `calculateNghiCachedTime`, `:2648` `updateNghiPrefetchWindow`, `:2731`/`:2803`/`:2860`/`:2865`/`:2963`/`:2987` (refill), `:3190` handoff, `:3248` `prepareNextNghiAudioIfPossible`, `:3358` `handleNghiAudioFinished`.
- **Ngưỡng nạp bộ đệm theo engine nay CÓ nơi đọc.** Thêm computed `currentSafeCachedTimeThreshold`, dùng ở `:2674`, `:2714`, `TTSManager+NextChapterPrefix.swift:73`. ⇒ `vieneuSafeCachedTimeThreshold` **có hiệu lực thật** (trước 1.3.435 chỉ được lưu/hiển thị).
- **Synthesis key hardcode `engine: "nghitts"`** ở `:2840` và `:3606` → `engine: tool`. Trước đó khoá tổng hợp của VieNeu và NghiTTS **giống hệt nhau** nếu cùng chương/đoạn/giọng, mà `PiperSynthesisCoordinator` gộp request theo khoá.
- **`TTSManager+NextChapterPrefix.swift`**: `nextChapterPrefixContext()` phải cho **mọi** engine local đi qua `NghiUtteranceSegmenter.expand(..., maximumLength: chunkLength)` — trước đó VieNeu **không** expand nên **lệch chỉ số đoạn văn** giữa chương hiện tại và prefix chương kế; `requestRemoteNextChapterPrefixIfNeeded` phải **loại** engine local (VieNeu từng lọt vào đường remote); `requestNghiNextChapterPrefixIfNeeded` 1 gate. Thêm 1 gate ở `TTSNextChapterPrefixSynthesizer` và 1 ở `TTSNextChapterPrefixCache`.
- **Tham số lúc khởi động**: `TTSManager.init` nạp tham số **trước `super.init()`** (`:953`) nên không gọi được instance method, và chuỗi `if/else` ở đó **thiếu nhánh `vieneu`** ⇒ khởi động app khi đang chọn VieNeu nạp nhầm `extRate_vieneu`/`extPitch_vieneu`/`extVoice_vieneu`. Sửa bằng **một dòng** `applyVieNeuParamsIfNeeded()` trong `initialize(container:)` (gọi từ `MainTabView.swift:57`, trước mọi lượt đọc) — dùng lại **một nguồn sự thật** thay vì chép danh sách khoá lần thứ ba.
- **`TTSManager+TranslationIdentity.swift:8`**: `tool == "system" || tool == "nghitts" || tool == "google"` là **cùng loại bug "phủ định 3 nhánh"** như `isExtensionTool` — VieNeu bị tính `extFingerprint` từ extension rỗng. Sửa thành `!TTSManager.isExtensionTool(tool)`.
- **UI — Picker**: VieNeu lên **vị trí thứ 3** (Siri → NghiTTS → **VieNeu** → Google → extension).
- **UI — hết trùng lặp "số đoạn tải trước"**: Section 3 (`vieNeuReaderSection`) nay **chỉ còn chế độ chất lượng**; số đoạn tải trước / độ dài phân đoạn / ngưỡng nạp bộ đệm dồn về Section 5 qua `vieNeuPrefetchSection`. Trước đó số đoạn tải trước có ở **2 chỗ**, và chỗ ở Section 5 trỏ nhầm `extPrefetchCount` với nhãn *"(Extension TTS)"* vì VieNeu rơi vào nhánh `else` (nhánh extension).
- **UI — trả lời "độ dài đoạn văn có dùng không"**: **CÓ**. `TTSManager.playbackParagraphs` cho `vieneu` đi qua `NghiUtteranceSegmenter.expand(baseParagraphs, maximumLength: chunkLength)` giống Piper; nay nhãn đúng *"Độ dài phân đoạn (VieNeu)"* và khoá `vieneuChunk`.
- **UI — trả lời "thời gian dãn tiến trình nạp trước có dùng không"**: **KHÔNG** với engine local. `prefetchDelayMs` chỉ được tiêu thụ ở `TTSAudioSynthesisWorker` (đường Google/extension); `TTSNextChapterPrefixSynthesizer.one` trả sớm cho engine local bằng `localService.synthesize(...)` **không truyền** tham số này. Stepper nay **ẩn với engine local** (nó đã chết với NghiTTS từ trước).
- **UI — pitch**: engine local phát qua `NghiAudioPlayerQueue` chỉ có `updateRate(_:)`, không có `AVAudioUnitTimePitch` ⇒ pitch là **no-op** với cả NghiTTS và VieNeu. `disablePitch` nay phủ cả VieNeu kèm dòng giải thích (trước đó VieNeu hiện slider bật nhưng bấm không có tác dụng và **không có** dòng giải thích nào).
- **UI — nút "Đặt lại"**: chuỗi `if/else` cũ **thiếu nhánh `vieneu`** nên bấm khi đang chọn VieNeu sẽ ghi vào `extPrefetchCount` và `nghittsPrefetchDelay`. Gom thành `TTSManager.resetPrefetchSettings()`.
- **File**: `TTSManager.swift` 4025 → **4028**, `TTSSettingsView.swift` 517 → **502**, `TTSManager+VieNeu.swift` 183 → **227**, `TTSSettingsView+VieNeu.swift` 128 → **157**, `TTSManager+NextChapterPrefix.swift` 130 (không đổi), `TTSNextChapterPrefixSynthesizer.swift` 113 (không đổi), `TTSNextChapterPrefixCache.swift` 339 (không đổi), `TTSManager+TranslationIdentity.swift` 26 (không đổi).
- **Ràng buộc đã đo**: `check_architecture.py` giữ nguyên **5** violation nền và **0** vi phạm mới; `validate_links.py` PASS. Không build được trên Windows — CI sẽ xác nhận biên dịch.
- **Hạn chế còn lại**: `vieneuPitch` vẫn chưa nghe thấy (queue không có pitch). **Chưa kiểm chứng hành vi lúc chạy** — toàn bộ ~28 gate vừa mở dựa trên suy luận từ việc đọc `nghiAudioPlayerQueue`/`preloadedData` là tài nguyên dùng chung; cần cài IPA lên máy thật để xác nhận audio phát, tự chuyển đoạn, và NghiTTS không hồi quy.

## [1.3.434] - 2026-09-29

### fix: noi VieNeu vao duong phat local + tach khoa tham so theo engine

Người dùng báo *"ipa mới chọn vieneu nhưng nó không hoạt động, không tạo ra được âm thanh. Phần quản lý riêng của trình đọc không có gì cả"*, kèm hai yêu cầu: *"config cao độ, tốc độ, tải trước dữ liệu phải lưu key khác nghitts"* và *"thiếu config fast và high"*.

- **Lỗi mất tiếng — định tuyến phát.** `playAudioData` chỉ định tuyến `tool == "nghitts"` sang `playNghiAudioData`; VieNeu rơi xuống nhánh `AVAudioPlayer` chung, trong khi `updatePlaybackParams()` đặt `rate` lên `nghiAudioPlayerQueue`. Hai bên lệch nhau nên **không có tiếng** và **không có lỗi nào được ném ra**.
  * Sửa: thêm `TTSManager.isLocalEngine(_:)` (`nghitts || vieneu`) và thay **9** predicate trong `TTSManager.swift` + **2** trong `TTSChapterPrefetcher.swift`.
  * **Quy ước mới**: hỏi *"engine local?"* → `isLocalEngine`; hỏi *"Piper?"* (`chunkLength`, `NghiUtteranceSegmenter`) → **giữ** `== "nghitts"`. `isLocalEngine` và `isExtensionTool` là cặp sinh đôi, **không** gộp.
- **Lỗi tham số bị ghi đè im lặng.** `loadParamsForCurrentTool()` gọi `applyVieNeuParamsIfNeeded()` ở **dòng đầu** nhánh `else` (nhánh extension) rồi **ghi đè ngay** `speed`/`pitch`/`selectedVoice` bằng `extRate_vieneu`/`extPitch_vieneu`/`extVoice_vieneu`. Sửa: nhánh `else if tool == "vieneu"` riêng.
- **Lỗi giọng không nhớ.** `selectedVoice.didSet` ghi `extVoice_vieneu` nhưng loader **đọc** `vieneuVoice` ⇒ chọn giọng xong thoát ra vào lại là mất. Sửa: `persistVoice(_:)` dùng **cùng** khoá mà loader đọc.
- **Khoá `vieneu*` tách hẳn `nghitts*`** (yêu cầu trực tiếp của người dùng): `vieneuVoice`, `vieneuRate`, `vieneuPitch`, `vieneuPrefetchCount`, `vieneuSafeCachedTimeThreshold`. `vieneuPrefetchCount`/`vieneuSafeCachedTimeThreshold` trước đây là `@Published` trần **không lưu gì** ⇒ nay có `didSet` / `setVieNeuSafeCachedTimeThreshold(_:)` (clamp 4…20, dựng lại cửa sổ tải trước khi đang phát). Lý do tách: VieNeu cần đệm sâu hơn (`bufferedSecondsTarget` 12 s so với 8 s của Piper) nên dùng chung ngưỡng là sai cho cả hai.
- **Giữ ratchet-down — gom `didSet` ra extension.** `TTSManager.swift` ở **4029/3470** nên không được dài thêm. Ba chuỗi `if/else` trong `didSet` của `speed`/`pitch`/`selectedVoice` được gom thành `persistSpeed(_:)`/`persistPitch(_:)`/`persistVoice(_:)` trong `TTSManager+VieNeu.swift` ⇒ thêm **1 engine + 6 khoá** mà file legacy **ngắn hơn 4 dòng**. Lưu ý: extension **không** thêm được stored property nên khai báo `vieneu*` vẫn phải nằm ở file legacy.
- **Thiếu config fast/high — nay có.** `vieNeuReaderSection` (`TTSSettingsView+VieNeu.swift`): Picker chế độ `Tự động (theo tốc độ máy)` / `Chất lượng cao · 16 bước` / `Nhanh · 8 bước`, Stepper số đoạn tải trước (2…10), Stepper ngưỡng nạp bộ đệm (4…20). Nối bằng `vieNeuModeBinding` đọc/ghi thẳng `VieNeuTTSService.preferredMode` (không dùng `@AppStorage` được vì extension không thêm được stored property) — dùng **chung** khoá `vieneuPreferredMode` với màn thử giọng.
- **Thêm `persistChunkLength(_:)`** và **nạp `chunkLength` cho VieNeu**. Đây là chỗ sửa một khẳng định **sai** của lượt trước: comment cũ ghi *"VieNeu không dùng chunkLength của Piper"*, nhưng `TTSManager.playbackParagraphs` (`:801-803`) cho `vieneu` đi qua `NghiUtteranceSegmenter.expand(baseParagraphs, maximumLength: chunkLength)` giống Piper ⇒ VieNeu **có** dùng `chunkLength`, và trước lượt này nó thừa hưởng giá trị còn sót của engine trước đó. Nay nạp từ khoá riêng `vieneuChunk` (khai báo trong `VieNeuSettingsKey.chunk`).
- **Sửa một hồi quy tự gây ra trong lúc làm.** Ban đầu tôi đổi cả `prefetchDelayMs.didSet` sang `isLocalEngine`, nhưng nhánh đó ghi khoá **của Piper** (`nghittsPrefetchDelay`). Vì `applyVieNeuParamsIfNeeded()` luôn đặt `prefetchDelayMs = 500`, mỗi lần chuyển sang VieNeu sẽ ghi đè `nghittsPrefetchDelay` bằng 500 ⇒ người dùng **mất độ trễ đã chỉnh cho NghiTTS**. Đã trả về `== "nghitts"` kèm comment giải thích.
- **Thêm log `[TTSRoute]`** (`AppLogger.shared.log`): đổi engine, nạp tham số VieNeu, và **đường phát được chọn** (hàng đợi local vs `AVAudioPlayer`). Đây chính là thứ lẽ ra đã chỉ ra lỗi mất tiếng ngay từ đầu. `persistSpeed`/`persistPitch`/`persistVoice`/`persistChunkLength` dùng `logTTSVerbose` để slider không làm ngập log.
- **File sửa**: `TTSManager.swift` 4029 → **4025** (giảm 4 dòng so với đầu lượt nhờ thêm `persistChunkLength`), `TTSManager+VieNeu.swift` 67 → **183**, `TTSSettingsView+VieNeu.swift` 73 → **128**, `TTSSettingsView.swift` 519 → **517** (gộp hai khối `Image`+`Text` thành `Label` để lấy lại dòng), `TTSChapterPrefetcher.swift` **375** (đổi predicate, không đổi số dòng).
- **Hạn chế đã biết (CHƯA sửa — quan trọng)**: **hai Stepper mới chưa có tác dụng thật.** Toàn bộ máy nạp lại / cửa sổ wake của NghiTTS vẫn gate bằng `tool == "nghitts"` ở **~15 chỗ** — `updateNghiPrefetchWindow` (`:2652`), `prepareNextNghiAudioIfPossible` (`:3252`), `calculateNghiCachedTime` (`:2596`), `handleNghiAudioFinished` (`:3362`), `startPrefetchTask(for:)` (`:2991`), `handleNghiScheduledHandoff` (`:3194`)… Hệ quả: `calculateNghiCachedTime()` trả **0.0** cho VieNeu nên `vieneuSafeCachedTimeThreshold` **không bao giờ được đọc** (các nơi tiêu thụ — `TTSManager+NextChapterPrefix.swift:73`, `TTSManager.swift:2674`, `:2714` — đều đọc `nghittsSafeCachedTimeThreshold` và nằm trong code đã gate); `vieneuPrefetchCount` chỉ được đọc ở `currentPrefetchCount` mà nơi dùng duy nhất là `updatePrefetchWindow()` (`:2488`) — đường **remote**. Hai giá trị vẫn được lưu/nạp đúng (đúng yêu cầu "lưu key khác nghitts") và sẽ có tác dụng ngay khi mở máy nạp lại cho engine local, nhưng **hiện tại chỉnh không thấy khác gì**. Chế độ `fast`/`high` **có** tác dụng thật vì nó đi thẳng vào engine.
- **Hạn chế đã biết (chưa sửa)**: `NghiAudioPlayerQueue` chỉ có `updateRate(_:)`, **không** có pitch; `AVAudioUnitTimePitch` chỉ nằm trên đường `AVAudioEngine`. Nên `vieneuPitch` **được lưu/nạp nhưng chưa nghe thấy được** — muốn có pitch thật phải thêm xử lý pitch vào queue (việc riêng).
- **Ràng buộc đã đo**: `check_architecture.py` giữ nguyên **5** violation nền cũ và **0** vi phạm mới (so trước/sau bằng `git stash`); `validate_links.py` PASS (16 documents, 608 Swift files). Không build được trên Windows.
- **Tài liệu CodeGraph**: `rules.md` thêm mục **TTS Engine Routing Invariants** (9 luật); `11_subsystems.md`, `03_type_graph.md`, `04_call_graph.md`, `05_state_graph.md`, `06_event_graph.md`, `08_lifecycle.md`, `10_risk_report.md`, `13_resource_lifecycle.md` mỗi file thêm mục 1.3.434; sửa một khẳng định **sai** trong `06_event_graph.md` (tài liệu cũ nói `didSet` của `speed`/`pitch` cập nhật `AVAudioUnitTimePitch`, nhưng engine local không đi đường đó).

## [1.3.433] - 2026-09-29

### fix: hien danh sach giong dung theo engine dang chon

Người dùng cài IPA và báo **hai** lỗi liên quan, cùng một gốc là "engine thứ hai dùng chung đường với NghiTTS".

- **Lỗi 1 — VieNeu bị xếp nhầm vào nhánh extension.** Picker đã có mục "VieNeu-TTS v3 Nano (Offline)" ✓ nhưng mục **GIỌNG ĐỌC** hiện "Không có giọng đọc nào" ✗, kèm dòng *"Extension TTS không hỗ trợ chỉnh cao độ"*.
  * Predicate nhận diện extension — `tool != "system" && tool != "nghitts" && tool != "google"` — nằm ở **6 chỗ** (**4** trong `TTSSettingsView`, **2** trong `TTSManager`). Thêm `vieneu` mà không sửa cả 6 ⇒ VieNeu rơi vào nhánh **extension** ⇒ màn Cài đặt dùng `extensionVoices` (rỗng) thay vì `availableVoices`.
  * `loadExtensionVoices(packageId: "vieneu")` **thoát sớm** vì không có extension trùng tên, nên nó không xoá `availableVoices` — lỗi nằm ở **UI chọn nhánh**, không phải ở dữ liệu.
  * Sửa: gom thành **một** `TTSManager.isExtensionTool(_:)` (static) và thay cả 6 chỗ ⇒ **net 0 dòng**. Thêm nhánh `vieNeuVoicePicker` (đặt trong `TTSSettingsView+VieNeu.swift` để không vượt baseline **519**).
  * Nhánh giọng của VieNeu **cố ý không lọc `isModelDownloaded`** như NghiTTS: 11 giọng nằm chung trong `voices_v3_nano.json`, không phải file rời từng giọng.
- **Lỗi 2 — đổi từ VieNeu sang NghiTTS thì NghiTTS báo "chưa tải model".** Gốc: `onChange(of: ttsManager.tool)` **không** nạp lại giọng cho engine có sẵn. Lỗi **có sẵn từ trước** nhưng chỉ lộ ra khi có engine thứ hai cùng dùng `availableVoices`: đổi engine giữ nguyên tên giọng của engine cũ, rồi nhánh NghiTTS lọc `isModelDownloaded` trên **tên giọng của VieNeu** ⇒ "Chưa tải giọng đọc NghiTTS nào" dù model đã có. Sửa: `Task { await loadVoicesForCurrentTool() }` trong nhánh `else` của `onChange` (**+1 dòng**).
- **File sửa**: `TTSSettingsView.swift` **519** (đúng baseline), `TTSSettingsView+VieNeu.swift` 47 → **77**, `TTSManager+VieNeu.swift` 55 → **67**, `TTSManager.swift` **4029** (không đổi).
- **Ràng buộc đã đo**: `check_architecture.py` giữ nguyên **5** violation nền cũ và **0** vi phạm mới; `validate_links.py` PASS. Không build được trên Windows.
- **Tài liệu CodeGraph**: `rules.md` thêm 2 luật (predicate `isExtensionTool` ở 6 chỗ; engine có sẵn cần nhánh giọng riêng); `11_subsystems.md` thêm mục về hai lỗi này.

## [1.3.432] - 2026-09-29

### feat: noi engine VieNeu-TTS vao Picker Trinh doc

Thực thi plan 2b đã duyệt (phiên grill-me). **Phần lõi xong**; màn cấu hình riêng cho VieNeu còn lại.

- **`LocalTTSEngine.swift` (mới, 52 dòng)** — protocol chung cho hai engine local. `PiperTTSService` và `VieNeuTTSService` cùng conform; VieNeu được thêm `boundaryKind` cho khớp chữ ký nhưng **bỏ qua** (nó tự phân loại ranh giới theo dấu câu).
- **`TTSManager+VieNeu.swift` (mới, 60 dòng)** — computed `localEngine` trả `nghiTTSService` cho **mọi** tool trừ `vieneu` ⇒ **đường NghiTTS không đổi một bit nào**; cùng `applyVieNeuParamsIfNeeded` và khoá `vieneu*`.
- **`TTSSettingsView+VieNeu.swift` (mới, 47 dòng)** — mục Picker của VieNeu **chỉ hiện khi model đã tải** (quyết định grill #2: chặn ở Picker), lối tải model khi còn thiếu, và nạp giọng theo engine.
- **Sửa `TTSManager.swift`**: dispatch `:2453` và guard warm-up `:779` thêm `vieneu`; `playbackParagraphs:807` cũng thêm (quyết định grill #3 — chia nhỏ đơn vị đọc); `updatePlaybackParams:1133` thêm `vieneu` vào nhánh áp tốc độ tay; 5 call site đổi `nghiTTSService` → `localEngine`.
- **Đổi kiểu tham số prefetch** `nghiService: PiperTTSService?` → `localService: (any LocalTTSEngine)?` ở **6 file** — plan chỉ liệt kê 3, thực tế còn `TTSNextChapterPrefixCache` (+ extension GoogleBatch) và `TTSManager+NextChapterPrefix`.
- **Hai kết luận từ đọc code làm giảm công việc so với plan**: (1) `VieNeuTTSService` **đã** đi qua `PiperSynthesisCoordinator.shared` ⇒ rủi ro "tải trước chặn phát" trong plan §6 **không tồn tại**; (2) kiến trúc app **đã** làm "tổng hợp ở 1.0, tốc độ ở tầng phát" (cả hai call site NghiTTS truyền `speed: 1.0`) ⇒ không cần sửa khoá cache.
- **Lệch so với plan**: `TTSManager.swift` **4026 → 4029** (+3), plan ghi "+1 dòng". Hai stored property cho thông số đệm bắt buộc ở file chính (extension không thêm được stored property); đã cắt hết comment để giảm từ +7 xuống +3. `check_architecture.py` vẫn **5** vi phạm nền, **0** mới.
- **Ràng buộc đã đo**: `check_architecture.py` giữ nguyên **5** violation nền cũ và **0** vi phạm mới; `validate_links.py` PASS. Không build được trên Windows.
- **CÒN LẠI của 2b**: màn cấu hình riêng cho VieNeu (quyết định grill #4) và cho logic đệm đọc đúng khoá `vieneu*` theo tool.

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
