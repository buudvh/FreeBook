# CHANGELOG - Nhật ký Thay đổi CodeGraph Tàng Công Các

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **Tàng Công Các**.

## [1.3.902] - 2026-11-12

### fix: sheet giọng VieNeu nạp lại engine trình đọc sau khi thử giọng model khác, nhân bản huỷ được lúc tải gói và kiểm tên trước

Rà soát lại sheet chọn giọng / nhân bản (1.3.900–900) trước khi gộp — sửa các chỗ đọc code thấy sai.

- **Thử giọng model khác rồi đóng sheet**: thử giọng Turbo khi trình đọc là Nano (hay ngược lại) làm engine kia nhả model của trình đọc. Đọc tiếp vẫn chạy (engine tự nạp lại ở đoạn đầu) nhưng chờ nạp model, và thử Nano khi đang đọc Turbo để hai model cùng nằm trong RAM. Nay đóng sheet ⇒ `VieNeuVoicePreviewPlayer.finishSession()` nạp sẵn lại engine của trình đọc (`TTSManager.scheduleNghiWarmUp`, bỏ `private`).
- **Sheet nhân bản đang tải gói không huỷ được**: thêm nút "Huỷ tải" khi đang tải (`cancelSave()` huỷ các lượt tải + lượt lưu, giữ mẫu để Lưu lại). Bỏ `interactiveDismissDisabled` chồng lên `confirmDiscardOnSwipe` (hai cơ chế cùng chặn vuốt) — có mẫu (kể cả lúc đang lưu) ⇒ hỏi "Bỏ thay đổi?", bỏ ⇒ huỷ lượt lưu. Đang tạo giọng mà bỏ thì lượt ORT / audio.cpp dở chạy nốt, giọng vẫn lưu nhưng không được chọn.
- **Bản build không có audio.cpp**: "Turbo" / "Cả hai" và "Tạo bản Turbo" chặn ngay (trước đây tải ~320 MB rồi mới lỗi).
- **Trùng tên**: kiểm tên với giọng Nano / Turbo tự tạo **trước** khi tải / tạo ("Cả hai" từng tạo xong Nano rồi mới lỗi trùng tên Turbo).
- **Đọc đĩa trên main mỗi nhịp tiến độ**: sheet nhân bản không đọc đĩa trong `init` (SwiftUI dựng lại `init` mỗi lần màn cha vẽ) mà ở `onAppear`; sheet chọn giọng tính giọng của trình đọc một lần mỗi lượt vẽ thay vì từng hàng (`VieNeuModelChoice.current` kiểm file GGUF).
- Hàng "Giọng đọc" không nháy cảnh báo cam "Chưa tải dữ liệu giọng" ở lần vẽ đầu trước khi đọc đĩa xong; bỏ key path phần tử tuple ở `VieNeuClonePackages`.
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`. Chưa build (Windows), chưa thử máy.

## [1.3.901] - 2026-11-12

### feat: sheet nhân bản giọng VieNeu tạo giọng Nano, Turbo hoặc cả hai, thêm nút tạo bản Turbo cho giọng Nano

Theo mockup anh Bửu duyệt: nhân bản giọng ngay trong sheet chọn giọng, tạo được giọng Nano, giọng Turbo hoặc cả hai từ cùng một mẫu.

- **Hàng đầu sheet "Giọng đọc"**: "Nhân bản giọng đọc" (đũa thần, chữ màu nhấn, chevron) ⇒ `VieNeuVoiceCloneSheet`.
- **Sheet "Nhân bản giọng"** (nút chữ "Lưu" bên phải, vuốt xuống đóng, có mẫu chưa lưu ⇒ hỏi bỏ, đang lưu ⇒ không đóng được):
  - Segmented "Thu âm" | "Chọn file". Thu âm: nút tròn lớn mic ↔ stop, đồng hồ "5,2 s / 8 s", thanh mức âm, **tự dừng ở 8 s** (`VieNeuVoiceRecorder`); chọn file qua `DocumentPickerPresenter` gắn gốc màn.
  - Section "Mẫu giọng" (có "?"): khối thu / chọn file, "Nghe lại mẫu", "Tên giọng". Section "Dùng cho" (có "?"): chip Nano | Turbo | Cả hai (mặc định model đang đọc), "Khử nhiễu mẫu (Turbo)" (mặc định bật, chỉ hiện khi có Turbo), số liệu "Cần tải … MB" khi còn thiếu.
  - Lưu (`VieNeuVoiceCloneFlow` + `+Save`): tải gói thiếu có % (`VieNeuClonePackages`: Nano = model + gói nhân bản Nano; Turbo = model Turbo + gói nhân bản Turbo; file dùng chung tính một lần) → đường Nano **giữ nguyên** (`VieNeuTTSService.enrollVoice`, không khử nhiễu, lưu vào kho Nano, nạp lại catalog) → đường Turbo (`VieNeuTurboVoiceCloneCoordinator`; "Cả hai" tạo từ mẫu Nano vừa lưu ⇒ liên kết `sourceNanoVoiceId`). Tiến trình từng bước hiện ngay trong sheet. Xong ⇒ chọn giọng vừa tạo ("Cả hai" ưu tiên model đang đọc), đọc thử câu mẫu, đóng sheet. Một bản lỗi thì bản đã tạo vẫn giữ và được chọn, sheet báo lỗi.
  - Không dừng hẳn TTS khi thu: chỉ tạm dừng nếu truyện thật sự đang phát (Cài đặt TTS đã dừng sẵn; `stop()` làm mất lượt đọc tiếp khi đóng Cài đặt).
- **"Tạo bản Turbo"**: giọng Nano tự tạo chưa có bản Turbo hiện trong "Giọng của tôi" của chip Turbo (`VieNeuTurboCopyRow`); bấm ⇒ tải gói Turbo nếu thiếu (có %) rồi tạo từ mẫu Nano đã lưu (`VieNeuTurboCopyRunner`), xong báo toast.
- `CLAUDE.md` / `AGENTS.md`: viết lại mục "VieNeu: hai model Nano / Turbo" theo thiết kế mới (model đi theo giọng, sheet chọn giọng, tải theo giọng, nhân bản).
- **Kiểm chứng:** đọc code + grep chéo; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`. Chưa build (Windows), chưa thử máy (thu âm, tải, tạo giọng, toast).

## [1.3.900] - 2026-11-12

### feat: sheet chọn giọng VieNeu gộp Nano và Turbo, tải theo từng giọng tính theo byte và huỷ được

Theo mockup anh Bửu duyệt: chọn giọng VieNeu ở **một sheet** gộp hai model, model đi theo giọng; không còn hàng tải model riêng, mỗi giọng có nút tải của nó.

- **Cài đặt TTS › Giọng đọc** (VieNeu): một hàng `VieNeuVoiceSummaryRow` — vòng tròn icon, tên giọng đang đọc + nhãn "Nano" / "Turbo", dòng phụ (vd "Nữ · Bắc · tin tức"), badge Nhẹ / Vừa / Nặng, chevron; chưa tải dữ liệu ⇒ dòng phụ cam. Bấm ⇒ sheet. Bỏ Picker giọng tạm, hàng tải Nano (link màn thử) / Turbo (188 MB) và link "Giọng của tôi" (màn đó vẫn vào được từ màn thử Nano).
- **Sheet "Giọng đọc"** (`VieNeuVoicePickerSheet`, tiêu đề trái có "?" — `pageTitle(_:help:)` mới): chip "Nano | Turbo" (mở ra chọn sẵn model đang dùng); Nano: "Giọng của tôi" + "Giọng có sẵn"; Turbo: "Giọng của tôi" + "Tuyển chọn" (⭐) + "Giọng khác".
  - Hàng (`VieNeuVoiceListRow`): nút tròn ▶ thử / ■ đang thử hoặc đang tải (bấm = huỷ) / ⬇ thiếu dữ liệu; tên; dòng phụ + " · cần tải N MB", đang tải ⇒ "Đang tải 37% · 93 / 251 MB" + thanh mảnh; ✓ giọng đang đọc; badge Nhẹ (Nano, xanh lá) / Vừa (Turbo, cam hổ phách) / Nặng (Turbo `frames` ≥ 85, san hô; giọng tự tạo theo số khung của nó). Chạm thân hàng = chọn (khi đã tải đủ).
  - Nhấn giữ giọng nhân bản ⇒ Đổi tên / Xoá (`VieNeuCustomVoiceActions`: nạp lại catalog Nano, giọng đang đọc đi theo tên mới / về giọng mặc định).
  - Thử giọng (`VieNeuVoicePreviewPlayer`): tổng hợp câu mẫu bằng đúng engine của giọng rồi phát; chặn + toast khi truyện **đang phát** (không chặn khi chỉ còn widget vì Cài đặt đã tạm dừng); sheet đóng ⇒ dừng.
- **Danh sách giọng trước khi tải** (`VieNeuVoiceDirectory`, đọc đĩa ngoài main): file trên máy nếu có, không thì `VieNeuBuiltinVoiceList` (11 giọng Nano + 25 giọng Turbo chép từ kho mirror @ revision đang ghim — đổi revision thì chép lại).
- **Tải** (`ModelDownloadCenter+VieNeu`):
  - Nano tải chung một lượt (8 file, 346.903.105 byte ≈ 347 MB): mọi hàng Nano cùng hiện %. Turbo: bấm ⬇ giọng nào thì tải model nếu thiếu (manifest + `sea_g2p.bin` 63 MB + GGUF 188 MB) rồi file của giọng đó — % chỉ ở hàng đó.
  - % **theo byte** cộng dồn mọi file còn thiếu: `VieNeuModelClient` chuyển sang `VieNeuTurboModelClient.transfer` (KVO tiến độ, ghi `.partial` rồi đổi tên nguyên tử), bảng dung lượng `VieNeuModelStore.fileByteCounts` đo từ kho mirror.
  - Chạy ngoài main; các lượt VieNeu **lần lượt** (xếp hàng "Đang chờ lượt tải khác…") vì cùng ghi `sea_g2p.bin` / `speaker_encoder.onnx` / GGUF; màn thử Turbo và sheet không tải chồng nhau.
  - ■ = huỷ (`cancel(id:)`), không toast lỗi. `ModelDownloadCenter.Entry` thêm `completedBytes` / `totalBytes` / `isQueued`.
- **Kiểm chứng:** đọc code + grep chéo `ModelDownloadCenter` / `VieNeuModelClient.prefetch*`; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`. Chưa build (Windows), chưa thử máy.

## [1.3.899] - 2026-11-12

### refactor: Cài đặt TTS rút gọn phần VieNeu, bỏ tiết kiệm pin, số luồng, spin và tự phiên âm tiếng Nhật

Theo mockup anh Bửu duyệt: Cài đặt TTS khi trình đọc là VieNeu chỉ giữ thứ người dùng thật sự chỉnh, giải thích dời vào nút "?" cạnh tiêu đề section.

- **"Quản lý riêng của trình đọc"** (có "?": Nano luôn Cân bằng 8 bước + 2 luồng, không chờ bận; Turbo luôn 2 luồng trên lõi hiệu năng) chỉ còn công tắc "Áp dụng từ điển phiên âm VieNeu" + lối vào / nút tải "Từ điển phiên âm tiếng Nhật".
- **Bỏ**, giá trị cũ đã lưu giữ nguyên nhưng không đọc nữa:
  - "Tiết kiệm pin", "Chế độ tạo audio", "Số luồng tổng hợp": `VieNeuSynthesisPolicy.isPowerSaving` luôn `true` ⇒ Nano luôn `fast` + 2 luồng (`vieneuPowerSaving`, `vieneuPreferredMode`, `vieneuThreadCount` bỏ qua). Màn thử Nano vẫn đặt chế độ tạm tới lượt `prepare` kế.
  - "Luồng tổng hợp chờ bận (spin)": `allowSpinning` luôn `false` (`vieneuOrtAllowSpinning` bỏ qua); xoá `VieNeuOrtSpinToggle`.
  - "Tự động phiên âm tiếng Nhật": `VieNeuJapanesePreprocessor.applyUsingStoredFlags` luôn tắt romaji cho cả Nano lẫn Turbo (`vieneuJapaneseTransliterationEnabled` bỏ qua); bỏ dòng trạng thái ở màn từ điển.
  - Hàng "Tổng hợp Turbo" + chú thích Turbo.
- **"Cấu hình giọng nói"** có "?" khi trình đọc là VieNeu (Turbo tổng hợp ở tốc độ gốc, theo kịp tới ~2,0×; Nano có Tốc độ tổng hợp, 1,15× ít lặp chữ nhất). Giọng Turbo chỉ còn cảnh báo cam khi tốc độ > 2,0×; hàng "Tốc độ tổng hợp (VieNeu)" của Nano bỏ chú thích dài.
- **Kiểm chứng:** đọc code + grep chéo các khoá / hàm đã đổi; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, `TTSSettingsView.swift` giảm 449 → 440 dòng. Chưa build (Windows), chưa thử máy.

## [1.3.898] - 2026-11-12

### feat: VieNeu chọn Nano hay Turbo theo giọng đang chọn, gộp thành một trình đọc

Anh Bửu duyệt: VieNeu chỉ còn **một** trình đọc, giọng nào thì model nấy (giọng Nano ⇒ Nano, giọng Turbo ⇒ Turbo). Không gộp đường xử lý chữ / sea-g2p, không đổi đường nhân bản Nano.

- **`VieNeuVoiceSelection`** (mới, `Services/TTS/VieNeu/`): một khoá `vieneuSelectedVoice` = `"nano:<tên giọng>"` / `"turbo:<id>"`; `VieNeuModelChoice.stored` đọc từ đây, `current` / `localEngine` / khoá tổng hợp / `TTSSettingsSnapshot` giữ nguyên cách tính.
  - Chuyển một lần từ khoá cũ `vieneuModel` + `vieneuVoice` + `vieneuTurboVoice`; khoá cũ giữ nguyên, không xoá.
  - `vieneuVoice` từ nay là "giọng Nano dùng gần nhất": Turbo thiếu file ⇒ trình đọc lùi về Nano bằng giọng này.
  - Lùi về Nano **không** ghi đè lựa chọn Turbo: `persistVoice` chỉ ghi khi model hiệu lực trùng model đã lưu (`recordReaderVoice`).
- **`TTSManager.selectVieNeuVoice`** (`TTSManager+VieNeuVoice`): cùng model ⇒ chỉ đổi `selectedVoice`; khác model ⇒ ghi lựa chọn rồi gán `tool = "vieneu"` (nạp lại tham số, bỏ đệm, `scheduleNghiWarmUp` nạp đúng engine, engine kia nhả trong `prepare`). Đổi giọng ⇒ ảnh chụp cấu hình khác ⇒ đóng Cài đặt TTS là dựng lại đoạn.
- Cài đặt TTS: Picker "Trình đọc" còn một mục "VieNeu-TTS v3 (Offline)" (luôn hiện); Picker giọng tạm gộp hai nhóm Nano / Turbo (sheet chọn giọng thay ở bản sau). Bỏ `VieNeuModelChoice.store` / `pickerTag` / `voiceDefaultsKey`.
- Màn thử Turbo "Xoá model" ⇒ về giọng Nano dùng gần nhất.
- **Kiểm chứng:** đọc code + grep chéo `VieNeuModelChoice` / khoá giọng; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`. Chưa build (Windows), chưa thử máy.

## [1.3.897] - 2026-11-12

### fix: Cài đặt TTS chỉ đọc tiếp khi đóng hẳn, không tự đọc khi mở trang con hay đổi tab

Anh Bửu báo: *"nếu như từ cài đặt tts tôi chưa đóng sheet hoặc thoát màn hình đó mà sang màn hình khác mà bấm và nav qua màn khác thì sẽ xảy ra lỗi tts tự phát như đóng sheet"*.

**Nguyên nhân.** `TTSSettingsView.onDisappear` gọi thẳng `resumeAfterSettings()`. `onDisappear` chạy cả khi một trang con được đẩy lên trên (Cài đặt VieNeu, NghiTTS, từ điển…) và khi chuyển tab. Vì vậy TTS đọc lại dù sheet / trang vẫn mở.

Khi hiện lại, màn gọi `prepareForSettings()` lần hai, ghi đè ảnh chụp cấu hình lúc mở. Hệ quả: thay đổi làm trước khi vào trang con bị bỏ qua lúc đóng (không dựng lại đoạn, có thể đọc tiếp audio của cấu hình cũ).

**Sửa.**
- `TTSSettingsPauseSession` (mới, `Views/TTSWidget/`) giữ một cờ chung, gọi nhiều lần cũng như một.
  - `begin()`: chỉ lần mở đầu mới dừng + chụp cấu hình.
  - `finish(caller:)`: chỉ ở lối **đóng thật**:
    - `onDisappear` khi `@Environment(\.isPresented)` = `false`; còn `true` nghĩa là chỉ bị che;
    - `onDismiss` của sheet (`TTSSettingsSheetHost`), phòng khi sheet đóng lúc đang ở trang con;
    - `onAppear` của `TTSSettingsHubView` và trang gốc Cài đặt, phòng khi bị pop thẳng về gốc.
- Nếu trong lúc màn còn mở người dùng đã bật đọc truyện / chương khác, `finish()` chỉ khép phiên. Không "đọc tiếp đoạn đã lưu", vì sẽ nhảy về vị trí của phiên cũ.
- Lưu cấu hình tiện ích TTS trước khi đọc tiếp: chuyển từ `onDisappear` vào `finish()`.
- Log `[TTSSettings]` ghi `isPresented` ở `onDisappear` và ai gọi `begin` / `finish`, để kiểm trên máy.
- **Kiểm chứng:** đọc code + grep chéo (`prepareForSettings` / `resumeAfterSettings` chỉ còn gọi qua `TTSSettingsPauseSession`); `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Chưa build (Windows), chưa thử máy. Hành vi `isPresented` khi màn gốc của sheet bị trang con che là điểm chưa chắc: log trên máy sẽ cho biết.

## [1.3.896] - 2026-11-12

### fix: tạo giọng Turbo giữ đoạn mẫu đã cắt thay vì cả file, thử lại mã hoá một lần, bộ chọn file gắn gốc màn

Rà lại 1.3.891–893 trước khi bàn giao:

- **Giữ mẫu**: `VieNeuTurboCustomVoiceStore` trước chép **cả file** người dùng chọn vào `CustomVoices/<id>/`. File ghi âm dài hàng chục phút thì mỗi giọng tốn hàng trăm MB, trong khi chỉ 8 giây đầu (sau cắt im lặng) được dùng.
  - Nay ghi `sample.wav` = đúng đoạn đã cắt (tần số gốc, trước khử nhiễu, WAV 16-bit), đủ để tạo lại giọng.
  - `copySample` thay bằng `writeSample`; coordinator xin preparer trả đoạn đã cắt khi `keepsSample`.
- **Mã hoá audio.cpp không cần chữ**: đọc thêm `build_preparation_request` (`framework/runtime/session.cpp:432`, v0.9.4) — nó chỉ chép `text_input` (optional), không đọc.
  - Vì chưa chạy trên máy, nhánh dự phòng nới ra: lỗi lượt đầu không phải lỗi cấp phát ⇒ ghi `❌`, đặt chữ giả (nhánh mã hoá không đọc chữ), thử lại **một** lần.
  - Bản trước chỉ thử lại khi chữ lỗi có "text input", nên một lỗi khác chữ sẽ không có lần thử lại nào. Hỏng cả hai lần thì báo cả hai lỗi.
- **Bộ chọn file** của mục "Tạo giọng Turbo từ file" gắn ở **gốc Form** (`VieNeuTurboLabView.background(cloneFilePicker)`), như `VieNeuVoiceCreatorView` — cách đã chạy được trong LiveContainer. Bản trước gắn vào một hàng của Form.
- `VieNeuTurboCloneTrial.denoise` bỏ `didSet` (repo chưa có lớp `@Observable` nào dùng `didSet`): Toggle gọi `refreshReadiness()` qua `.onChange`.
- **Kiểm chứng:** `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. **Chưa build** (Windows), chưa chạy trên máy.

## [1.3.895] - 2026-11-12

### chore: script Python đối chứng nhân bản giọng VieNeu Turbo với pipeline gốc

Phần năm (khuyến khích) của đợt nhân bản giọng Turbo: kiểm bản Swift của bước chuẩn bị mẫu trên PC, và để anh Bửu so file app chia sẻ với bản gốc.

- **`Scripts/vieneu_turbo_clone_reference.py`** chép nguyên văn thuật toán của `pnnbao97/VieNeu-TTS`: `onnx_denoiser.py`, `speaker/` (soxr + kaldi-native-fbank), `_encode_ref_wav`, trim bằng librosa (kể cả bước ghi PCM_16 rồi đọc lại). Không cài cả gói `vieneu`.
  - `reference WAV`: cả pipeline ⇒ `speaker.emb.txt`, `ref_codes.txt` (khi có MOSS encoder ONNX của upstream, ~45 MB), `trimmed.wav`, `denoised.wav`, `info.json`.
  - `denoise` / `embed`: chạy riêng một bước trên WAV trung gian app chia sẻ, để tách sai lệch từng bước.
  - `compare`: cosine embedding, % mã trùng (cả khung, codebook 0), SNR / tương quan hai WAV.
- **Kết quả đo** trên PC (một mẫu giọng sạch 8 s; thuật toán bản Swift mô phỏng bằng numpy):
  - Cắt im lặng (`VieNeuSilenceTrimmer`) ra **đúng** mẫu đầu / cuối như librosa 1.0.
  - Khử nhiễu (DFT ma trận float32) so bản gốc: SNR 77,5 dB, embedding cosine 0,999998.
  - Mã tham chiếu rất nhạy: chỉ khác có / không khử nhiễu ⇒ codebook 0 trùng 83 %, đủ 16 mã 8 % khung. Mã của app (audio.cpp lấy lại tần số bằng sinc, upstream dùng soxr) sẽ không trùng từng số; xem codebook 0 + cosine rồi nghe.
- Cách cài thư viện và cách đọc kết quả ghi ở đầu script.
- **Không** chạm code app. Chưa so được với file app thật (cần chạy trên máy).

## [1.3.894] - 2026-11-12

### feat: màn thử VieNeu Turbo có mục tạo giọng Turbo từ file

Phần bốn: chỗ thử lõi nhân bản giọng Turbo (1.3.891–892) trên máy thật. Không phải màn tạo / chọn giọng cho người dùng cuối, màn đó làm sau theo mockup.

- **Mục "Tạo giọng Turbo từ file"** (`VieNeuTurboLabView+Clone`, logic ở `VieNeuTurboCloneTrial`):
  - Hàng gói nhân bản (`VieNeuTurboClonePackRow`): trạng thái, nút tải ~71 MB qua `ModelDownloadCenter`, tiến độ, nút xoá.
  - Chọn file bằng `DocumentPickerPresenter` (không dùng `.fileImporter`, vì nó không trả kết quả khi chạy trong LiveContainer), ô tên giọng, công tắc khử nhiễu (mặc định bật). Thiếu audio.cpp / model / gói thì hiện lý do.
  - Báo cáo: độ dài và tần số mẫu, giây cắt đầu / cuối, độ dài dùng, số khung; thời gian đọc file / cắt / nạp graph / khử nhiễu / embedding / mã hoá audio.cpp (kèm nạp model, dựng lại session hay nhả model) / tổng.
  - RAM ở 5 mốc (đầu lượt, sau ORT, trước mã hoá, sau mã hoá, sau dọn), nhiệt, bản audio.cpp.
  - Chia sẻ: file số đo `.txt` (`VieNeuTurboReportFile` thêm loại `.clone`), `ref_codes.txt`, `speaker.emb.txt`, WAV sau cắt (trước khử nhiễu) và WAV đưa vào audio.cpp. Hai WAV đều 16-bit, để so với script Python chạy bản gốc.
  - "Đọc thử câu mẫu bằng giọng này": chọn giọng vừa tạo rồi chạy "Đọc thử một lần" sẵn có.
- **Danh sách "Giọng" của màn thử** có thêm mục "Giọng tự tạo" (`VieNeuTurboCustomVoiceRepository.voices`). `reloadVoices` giữ lựa chọn giọng tự tạo khi cặp file còn.
  - Cài đặt TTS của trình đọc **chưa** hiện giọng tự tạo (UI người dùng cuối làm sau). Id `custom_…` gán vào `vieneuTurboVoice` thì trình đọc đã đọc được.
- `VieNeuTurboLab.isBusy` tính cả lượt tạo giọng: không đọc thử, đọc liên tục hay xoá model chồng lên lượt đang dùng runtime.
- **Kiểm chứng:**
  - `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**.
  - **Chưa build** (Windows), chưa chạy trên máy.
  - Cần đo trên máy: thời gian khử nhiễu (DFT ma trận + UNet), đỉnh RAM lúc mã hoá (ước tính +200–250 MB trên model 188 MB), chất lượng giọng có / không khử nhiễu.

## [1.3.893] - 2026-11-12

### feat: tải gói nhân bản giọng VieNeu Turbo (speaker_encoder + denoiser) từ kho mirror

Phần ba của lõi nhân bản giọng Turbo: hai graph ORT mà bước chuẩn bị mẫu (1.3.891) cần giờ tải được trong app.

- **Gói nhân bản Turbo** = `speaker_encoder.onnx` + `denoiser.onnx`, dung lượng hằng **70.964.837 byte** (28.303.423 + 42.661.414, HF API `blobs=true` của kho mirror @ `3486d7da`).
  - Tải từ `common/` của `raikiri1498/VieNeu-TTS` (`VieNeuModelMirror.nanoStorePath` đã trỏ hai tên này về đó), cất chung `VieNeuModelStore` (`Models/`) như `sea_g2p.bin`.
  - `speaker_encoder.onnx` dùng chung với gói clone của Nano: có rồi thì không tải lại.
- **`VieNeuModelStore`**: `turboCloneGraphNames`, `turboCloneByteCount`, `hasTurboCloneGraphs`, `missingTurboCloneGraphNames`, `turboCloneTotalBytes`, `deleteTurboCloneGraphs()`.
  - Xoá model Nano khi máy còn model Turbo ⇒ **giữ** cả hai file (cùng chỗ giữ `sea_g2p.bin`). Không còn Turbo ⇒ xoá luôn `denoiser.onnx`, không để 42 MB mồ côi.
  - Xoá gói clone Nano khi gói Turbo còn (`denoiser.onnx` trên đĩa) ⇒ giữ `speaker_encoder.onnx`.
  - Xoá gói Turbo khi gói clone Nano còn graph khác ⇒ giữ `speaker_encoder.onnx`.
- **`VieNeuModelClient`**: `turboCloneSources()` + `prefetchTurboCloneGraphs(progressHandler:)`, cùng khuôn tải từng file (file tạm `.partial` → `moveItem` nguyên tử).
- **`ModelDownloadCenter`**: đích `vieNeu-turbo-clone` + `startVieNeuTurboClonePack()` ⇒ tiến độ sống qua việc rời màn, toast ở `MainTabView` như các gói khác.
- **API cho UI**: `VieNeuTurboClonePack` — `byteCount`, `isReady`, `missingNames`, `bytesOnDisk`, `download()`, `isDownloading`, `delete()`, `downloadTarget`.
  - `VieNeuTurboVoiceCloneCoordinator.readinessError` đọc tên file từ `turboCloneGraphNames`; tắt khử nhiễu thì chỉ cần `speaker_encoder.onnx`.
- **Kiểm chứng:**
  - Số byte lấy từ HF API, khớp file đã tải ở `D:\1.SOURCE_CODE\VieNeu-TTS\common`.
  - Grep chéo mọi chỗ gọi `deleteAll()` / `deleteCloneGraphs()` của model store.
  - `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**.
  - **Chưa build** (Windows), chưa thử tải trong app.

## [1.3.892] - 2026-11-12

### feat: VieNeu Turbo mã hoá mẫu giọng bằng audio.cpp và lưu giọng tự tạo

Phần hai của lõi nhân bản giọng Turbo (anh Bửu đã duyệt plan). Chưa có giao diện người dùng cuối; API để sẵn cho màn chọn giọng / tạo giọng làm theo mockup sau.

- **`VieNeuTurboRuntime.encodeReference`** (file mới `VieNeuTurboRuntime+Encode`):
  - Gọi audio.cpp với `audiocpp_request_set_voice_audio` + option `encode_reference_only = true`, đọc artifact `ACOUSTIC_TOKENS` id `vieneu_v3_turbo.reference_codes`.
  - Chép đủ `payload_bytes` (con trỏ mượn) trước khi `audiocpp_result_free`. Kiểm 16 số 0…1023 mỗi dòng, 1…100 dòng (25 giọng đóng gói: 12…98 khung, mã 0…1023).
  - Truyền `speaker_embedding_file` của chính giọng đang tạo: audio.cpp khỏi tự chạy speaker encoder của GGUF (nếu có), và file đi qua bộ đọc của audio.cpp một lần trước khi lưu.
  - Chạy trên hàng đợi runtime, QoS `.userInitiated`, không chạy chồng lượt tổng hợp. Lỗi cấp phát ⇒ dựng lại session, thử lại một lần.
  - **UNKNOWN**: framework có đòi chữ khi chỉ mã hoá không. Đọc code v0.9.4 thì không; nếu máy báo lỗi "text input" thì ghi `❌`, đặt chữ giả rồi thử lại.
  - Xong lượt: model đã nạp sẵn thì **dựng lại session** cùng số luồng (trả vùng encoder + cache prompt); nạp riêng cho lượt này thì **nhả hết**. Kể cả khi lượt hỏng.
  - `queue`, `model`, `session`, `sessionThreads`, `loadedModelPath`, `perform`, `prepareLocked`, `createSessionLocked`, `freeAll`, `check`, `elapsedMs`, `isAllocationFailure` hạ từ `private` xuống `internal` vì file `+Encode` dùng (tách file vì trần 400 dòng).
- **Kho giọng tự tạo** `VieNeuTurboCustomVoiceStore`:
  - Bố cục: `VieNeuTurbo/CustomVoices/<id>/{ref_codes.txt, speaker.emb.txt, sample.<đuôi>?}` + `voices_custom.json` (tên, ngày tạo, số khung, đã khử nhiễu chưa, độ dài mẫu, mẫu gốc nếu giữ, giọng Nano nguồn nếu có).
  - Tách khỏi `Voices/` tải về; `VieNeuTurboModelStore.deleteAll` không chạm tới.
  - Id `custom_<12 hex>` ngẫu nhiên, không dùng lại (khoá cache tổng hợp băm theo id giọng).
  - Ghi vào `.staging-<id>/` rồi chuyển cả thư mục vào chỗ, sau đó mới ghi index (`.tmp` → `replaceItemAt`). Thư mục dở do app chết giữa chừng được dọn khi nạp danh sách.
- **Đọc giọng tự tạo**:
  - `VieNeuTurboModelStore.voiceDirectory(voiceId:)` định tuyến id `custom_…` sang `CustomVoices/`, nên `referenceCodesURL` / `speakerEmbeddingURL` / `hasVoice` dùng chung cho cả hai loại.
  - `VieNeuTurboTTSService.resolveVoiceId` giữ id tự tạo khi cặp file còn, đã xoá thì về giọng mặc định.
  - `VieNeuTurboModelClient.downloadVoice` không bao giờ tải id tự tạo: thiếu file ⇒ báo rõ "không còn trên máy" thay vì HTTP 404.
- **API cho UI sau này:**
  - `VieNeuTurboCustomVoiceRepository` (`@MainActor @Observable`, `shared`): `voices`, `loadError`, `reload()`, `voice(id:)`, `rename(id:to:)`, `delete(id:)`, `voiceFiles(id:)`, `sampleURL(id:)`.
  - `VieNeuTurboVoiceCloneCoordinator` (`shared`): `createVoice(fromFile:name:denoise:keepsSample:keepsIntermediate:)`, `createVoice(fromNanoVoiceId:name:denoise:)` (dùng mẫu gốc ở `VieNeu/CustomVoices/samples/`), `isRunning`, `stage`, `readinessError(denoise:)`, `isReaderUsingTurbo`.
  - Trình đọc đang đọc bằng Turbo ⇒ báo lỗi rõ, không chạy.
  - Thứ tự giữ đỉnh RAM thấp: ORT (khử nhiễu + embedding) nhả xong mới chạy encoder audio.cpp.
- `VieNeuTurboReferencePreparer.minimumSeconds` hạ 2 → **1 giây**: giọng đóng gói ngắn nhất chỉ 12 khung (~0,96 s).
- **Kiểm chứng:**
  - Đọc code audio.cpp v0.9.4: `session.cpp` (nhánh `encode_reference_only`, `parse_speaker_embedding_file`), `prompt_tts_voice_clone.cpp` (cắt 8 s, bỏ khung thừa), `capi/audiocpp.cpp` (artifact, payload mượn).
  - `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**.
  - **Chưa build** (Windows), chưa chạy trên máy: ánh xạ kiểu C → Swift của `audiocpp_result_artifact` / `audiocpp_artifact_kind` chưa qua trình biên dịch.

## [1.3.891] - 2026-11-12

### feat: lõi xử lý mẫu giọng cho nhân bản VieNeu Turbo: cắt im lặng, khử nhiễu, speaker embedding

Anh Bửu duyệt plan nhân bản giọng cho VieNeu Turbo. Đợt này chỉ làm lõi (chưa có giao diện người dùng cuối). Phần này chép bước chuẩn bị mẫu của upstream (`pnnbao97/VieNeu-TTS`: `v3turbo.py` `_preclean_reference_audio`, `onnx_runtime_lite.py` `prepare_reference`, `onnx_denoiser.py`).

- **`VieNeuTurboReferencePreparer`** (thư mục mới `Services/TTS/VieNeuClone/`):
  - Pipeline: đọc → mono → cắt im lặng → tối đa 8 giây → khử nhiễu (tham số, mặc định bật) → speaker embedding 192 số.
  - Embedding và buffer đưa cho audio.cpp ra từ **cùng một** buffer: 44,1 kHz khi khử nhiễu, tần số gốc khi tắt (như upstream).
  - Sàn 2 giây sau khi cắt im lặng. Chỉ giải mã 60 giây đầu file (`VieNeuAudioResampler.loadMono(url:maxSeconds:)`, tham số mới, mặc định đọc cả file như cũ).
  - Ngữ cảnh ORT nhả khi hàm trả về, trước bước audio.cpp, để hai đỉnh bộ nhớ không chồng nhau.
- **`VieNeuSilenceTrimmer`** chép `librosa.effects.trim(top_db=30)`:
  - RMS khung 2048 / hop 512, đệm 0 hai đầu, so với khung mạnh nhất, sàn `amin`.
  - librosa nằm trong `dependencies` lõi của upstream, nên người dùng upstream chạy nhánh này chứ không phải nhánh dự phòng `|x| > 1e-5`.
- **`VieNeuReferenceDenoiser`** chép `OnnxDenoiser.denoise`:
  - Lên 44,1 kHz, chia đỉnh, đệm 441 mẫu 0, chuẩn hoá lần hai như `_forward`.
  - STFT → `denoiser.onnx` → iSTFT, cắt về độ dài cũ, nhân lại đỉnh.
- **`VieNeuDenoiserSTFT`**: n_fft 1680 / hop 420, Hann tuần hoàn, đệm reflect, bỏ khung cuối; iSTFT lặp khung cuối, chia Σw².
  - 1680 có thừa số 7 nên FFT radix-2 của app và `vDSP_DFT` không dùng được. DFT làm bằng **nhân ma trận** (`vDSP_mmul`) với bảng cos/sin 841 × 1680 tính trước.
  - Bin biên độ 0 cho cos 1 / sin 0 như `np.angle`, không chia cho 0.
- **Cầu nối ORT** (`VieNeuONNXBridge`):
  - `VieNeuORTCreateTurboClone` chỉ nạp `speaker_encoder` (+ `denoiser` khi bật), không nạp 3 graph clone của Nano.
  - `VieNeuORTRunDenoiser`: 3 input / 3 output, tên đọc từ session và xếp theo **tên**.
  - `VieNeuORTRunSpeakerEncoder` chỉ còn đòi session `speaker_encoder` (ngữ cảnh clone của Nano vẫn nạp đủ 3 nên không đổi gì cho Nano).
  - Swift: `VieNeuONNXRuntime(turboCloneModelStore:threadCount:loadsDenoiser:)` và `+Denoiser`.
- **Kiểm chứng:**
  - Đối chiếu bằng numpy (cùng thuật toán, float32) với `_stft` / `_istft` gốc trên tín hiệu ngẫu nhiên 3 giây: phổ lệch ≤ 1,5e-5 (biên độ tới ~26), iSTFT lệch ≤ 5e-7.
  - Chữ ký `denoiser.onnx` / `speaker_encoder.onnx` đọc bằng onnxruntime trên file của kho mirror.
  - `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**.
  - **Chưa build** (Windows), chưa chạy trên máy.

## [1.3.890] - 2026-11-12

### feat: màn thử VieNeu có Đo tự động ORT ↔ Core ML bằng một nút, chia sẻ kết quả bằng file thật

Anh Bửu duyệt P1b sau kết quả So EP trên máy (Core ML CPU-only fp32: VE 43 ms so với ORT 109 ms cùng bucket, tiếng giữ nguyên — báo cáo `Docs/Reports/2026-11-11-vieneu-nano-toi-uu.md` §9), kèm yêu cầu *"chạy từ khi mát đến khi nóng chạy thêm vài đoạn rồi dừng sau đó đợi khi mát tự chạy lại luôn, như vậy tôi chỉ cần nhấn nút 1 lần"*, tốc độ phát 1,5×, tốc độ tạo 1,15, giọng Mai Anh. Vẫn **chỉ ở màn thử** — trình đọc không đổi.

- **Gói Core ML đọc truyện thật** (`Scripts/vieneu_nano_coreml_export.py`, dùng lại các bước mổ graph của P1; đăng ở `raikiri1498/VieNeu-TTS/nano-coreml/`, commit HF `ef20eb2f`):
  - VE bucket `64 / 96 / 128 / 160`, codec `64 / 128 / 160`, L = 256; trọng số **một bản** (`ve_main.weights` 153 MB, `codec.weights` 99 MB), cả gói 267 MB.
  - `COREML_CACHE_KEY` trong metadata = tên + băm nội dung (mặc định ORT băm **đường dẫn** — thay file cùng tên là dùng nhầm bản biên dịch cũ).
  - Tự kiểm mọi bucket vừa với từng đoạn golden (PC, ORT CPU, nạp lại từ đĩa): v bước 0 ≥ 121 dB, latent ≥ 102 dB, sóng âm ≥ 91 dB so với graph gốc.
  - Bản không cố định độ dài **không làm**: graph T động có 67 phép tính theo shape + tensor int64 / bool — đúng loại làm Core ML hỏng tháng 10.
- **Né lỗi Core ML EP của ORT 1.24.2** (H1 của P1 lỗi "Not a directory"): `TensorProtoWithExternalDataToTensorProto` nhận đường dẫn file model làm thư mục. Cầu C `VieNeuORTProbeCreate` thêm tham số file trọng số ⇒ `mmap` + `AddExternalInitializersFromFilesInMemory` (ORT chép vào graph trước khi Core ML dựng model). Kiểm trên PC: kết quả trùng từng bit với đọc file thường.
- **Backend vòng Euler + codec theo từng lượt gọi** (`VieNeuFlowBackend`, `VieNeuTTSEngine+Flow`): `VieNeuTTSService.synthesizeWithDuration(…, flowBackend:)` mặc định `nil` = đường ORT cũ, nguyên văn (vòng Euler chuyển sang `+Flow`). Không gắn backend vào engine (singleton của trình đọc) ⇒ đoạn của trình đọc / hub / màn khoá không bao giờ đi nhầm Core ML.
- **`VieNeuCoreMLFlowBackend`** (`Services/TTS/VieNeu/CoreML/`): chọn bucket nhỏ nhất ≥ T riêng cho VE và codec, đệm cuối rồi cắt; prep chạy ORT CPU, main + codec chạy Core ML `CPUOnly` + `ModelCacheDirectory`; T > 160 / L > 256 lùi về ORT và được đếm. Session dựng lười, giữ tối đa N session (N do bước chuẩn bị đo RAM đặt); dựng session **ngoài** khoá để màn thử không treo khi Core ML biên dịch.
- **`VieNeuCoreMLPreparer`**: biên dịch lạnh từng graph (ms, RAM khi giữ session, số partition Core ML từ log ORT) → nạp lại từ bản biên dịch (ms, RAM cộng dồn, trần N theo RAM trống ≥ 700 MB) → tự kiểm golden mọi bucket (cổng latent ≥ 40 dB, sóng âm ≥ 30 dB, không NaN — rác kiểu tháng 10 thì bỏ lượt Core ML).
- **`VieNeuAutoThermalRun`** (`Services/TTS/VieNeuTurbo/AutoRun/`) — mục **"Đo tự động ORT ↔ Core ML (P1b)"** ở màn thử, một nút:
  - tải gói (lần đầu), kiểm chỗ trống, chuẩn bị Core ML (giữ sáng màn), rồi **3 lượt A-B-A: ORT → Core ML → ORT**;
  - ghim chế độ `fast` cho cả lượt đo (`VieNeuTTSService.setLabModeOverride`, không ghi cài đặt — Core ML nhanh sẽ làm bộ tự thích nghi nâng lên `high` 16 bước giữa lượt); báo cáo ghi chế độ đầu / cuối mỗi lượt;
  - nạp sẵn session Core ML **trước** lúc chờ mát của lượt Core ML (chi phí nạp không rơi vào số đo), nhả sau lượt đó để lượt ORT cuối bắt đầu cùng trạng thái RAM như lượt đầu;
  - trước **mỗi** lượt chờ `nominal` giữ liền 10 phút (tối đa 45 phút rồi chạy luôn, có ghi chú);
  - mỗi lượt đọc liên tục cùng văn bản bằng giọng Mai Anh, tổng hợp 1,15, phát 1,5× (`VieNeuTurboSoakRunner` thêm `playbackRate`), tới khi lên "nóng" thì đọc thêm 5 đoạn rồi dừng; "rất nóng" dừng ngay; tối đa 15 phút;
  - khoá máy / rời màn vẫn chạy (vòng lặng giữ app sống lúc chờ; `leaveScreen` không dừng khi đang đo); TTS / nhạc / phim khác phát ⇒ dừng cả lượt ("bị gián đoạn");
  - báo cáo một file, ghi lại sau mỗi bước **và mỗi phút trong lượt** (app bị tắt giữa lượt vẫn còn số của lượt dở): bảng so 3 lượt (ấm sau / nóng sau, RTF, CPU/tiếng, bận %, hụt tiếng, phần lùi ORT), bước chuẩn bị, điều kiện máy mỗi phút (nhiệt, mở / khoá màn, sạc, pin, RAM), nguyên văn số đo từng phút + từng đoạn.
- **Chia sẻ bằng file thật**: anh báo chia sẻ file kết quả So EP qua Nicegram "gửi xong mà không có file". Nút cũ dùng `ShareLink` + `DataRepresentation` (chữ dựng lúc bấm, không phải file). Mọi nút chia sẻ của màn thử (đọc thử, đọc liên tục, So EP, WAV, đo tự động) giờ ghi file `.txt` thật (`VieNeuTurboReportFile.writeTemporaryFile`) rồi mở `ShareSheet` như sao lưu / xuất từ điển. Chưa thử trên máy.
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.889] - 2026-11-12

### feat: màn thử VieNeu có phép thử So EP cho Nano (Core ML, Neural Engine, XNNPACK) với graph tĩnh

Anh Bửu duyệt P1 của báo cáo tối ưu Nano (`Docs/Reports/2026-11-11-vieneu-nano-toi-uu.md` §8): *"làm đi"*. Chỉ thêm phép thử ở màn thử VieNeu Turbo — **đường đọc truyện không đổi** (vẫn ORT CPU, cùng tiếng).

- **Script xuất graph tĩnh** `Scripts/vieneu_nano_static_export.py`:
  - Đọc model `pnnbao-ump/VieNeu-TTS-v3-Nano` rev `aba295eb` (Apache-2.0). Trọng số giữ nguyên, chỉ sửa graph.
  - `vector_estimator`:
    - mở mask khung `/ConstantOfShape` thành input `frame_mask` ⇒ chạy ở T đệm mà trùng kết quả T thật;
    - đóng băng T + L = 200, gấp hằng (ORT BASIC);
    - đổi `Where(mask, −FLT_MAX)` thành `Add(bias)`;
    - tách **prep** (chạy CPU; hai mask nhận float rồi tự `Cast`) và **main** (0 op ngoài danh sách Core ML EP, 0 tensor bool / int).
  - `codec_decoder` nhân quả ⇒ đệm cuối rồi cắt là trùng bit. Gộp `Pad` vào `Conv.pads`, đổi BatchNorm thành Mul + Add.
  - Gói P1 (10 file, ~417 MB):
    - VE + codec T128 nhúng trọng số;
    - VE T234 / T256 dùng chung `ve_main.weights` (external data) để đối chứng H1 (lỗi T234 tháng 10);
    - `golden.npz`: 5 đoạn đã qua phonemizer / text_encoder / duration + tham chiếu của graph gốc;
    - `manifest.json` (sha256), `NOTICE.txt`.
  - **Tự kiểm** nạp lại từ đĩa và so với graph gốc: v bước 0 ≥ 110 dB, latent ≥ 100 dB, sóng âm ≥ 90 dB (theo sàn fp32 khác kernel). Rớt thì không ghi manifest.
- **Gói đặt ở kho HF `raikiri1498/VieNeu-TTS`, thư mục `nano-static/`** (anh chọn; cùng kho với model, `VieNeuModelMirror`):
  - App đọc `resolve/main/nano-static/` — gói mới chưa có commit để ghim như `VieNeuModelMirror.revision`; mọi file kiểm sha256 theo `manifest.json` tải cùng lượt.
  - Workflow chạy tay `.github/workflows/vieneu-nano-static.yml`: ghim `onnx` / `onnxruntime 1.24.2`, xuất + tự kiểm, rồi `hf upload` bằng **Trusted Publisher** (OIDC, không secret).
  - Một lần, anh thêm Trusted Publisher ở trang cài đặt của kho HF: Provider GitHub Actions; claim `repository = buudvh/FreeBook`, `branch = main`, `workflow = vieneu-nano-static.yml`.
- **Cầu nối C tổng quát** `VieNeuONNXProbeBridge.h/.m` (thêm vào `FreeBookBridgingHeader.h`):
  - Chỉ float32. Session CPU / `CoreML` / `XNNPACK` qua `SessionOptionsAppendExecutionProvider`, chạy theo tên, trả cả shape output.
  - Bắt stderr lúc tạo session vào file để đọc bảng partition của EP (chẩn đoán, có thể rỗng).
  - Cầu nối cũ `VieNeuONNXBridge` không đổi.
- **Phép thử** (`Services/TTS/VieNeu/Probe/`):
  - `VieNeuNanoStaticPackage`: tải theo manifest, kiểm dung lượng + sha256, cất ở `FreeBook/TTS/VieNeu/Static/` (thuộc loại TTS của màn Dung lượng). `VieNeuTurboModelClient.transfer` hạ `private` thành `internal` để dùng chung.
  - `VieNeuNanoGolden` đọc golden bằng `NPZReader`.
  - `VieNeuNanoEPWorker` chạy lần lượt ORT CPU (tham chiếu trên máy) → Core ML CPU-only → GPU → Neural Engine → XNNPACK:
    - mỗi cấu hình một lượt, nhả session trước khi sang cấu hình kế;
    - **không** đặt `ModelCacheDirectory`: mỗi lượt chỉ dựng một session mỗi graph; giữ bản biên dịch fp32 của 4 graph × 3 compute unit tốn hơn 1,5 GB đĩa; thư mục tạm của ORT tự xoá; không cache cũng loại hẳn chuyện ANE dùng lại bản biên dịch cho CPU-only (khoá cache của EP chỉ là hash model);
    - Core ML CPU-only dưới 60 dB ở v bước 0 / có NaN / lỗi ⇒ **tự bỏ qua GPU + ANE**;
    - ghi ms + CPU-ms mỗi lượt VE và codec, SNR v0 / latent / sóng âm, NaN;
    - H1: main T234 so với T256.
  - `VieNeuGEMMBench` đo Accelerate `cblas_sgemm` (kiểm AMX).
- **Màn thử** — mục "So EP cho Nano (P1)":
  - Tải / xoá gói (xoá cả WAV + log), chạy / dừng, dòng tóm tắt từng cấu hình.
  - Chia sẻ báo cáo `.txt` (`VieNeuTurboReportFile.Kind.epProbe`) và WAV tham chiếu / từng cấu hình.
  - Trước khi chạy: dừng TTS, nhả Turbo + engine Nano (`startEPProbe`).
  - Màn hình không tự tắt khi đang chạy (rời màn thì trả lại ở `onDisappear`). Rời màn là dừng. `isBusy` tính cả phép thử.
- **Kiểm chứng:**
  - Script chạy trên PC: tự kiểm đạt (v0 121–124 dB, latent 111–116 dB, sóng âm 96–109 dB, T234 / T256 123,7 dB).
  - `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**.
  - Không build tại chỗ (Windows), chưa thử máy. Gói chưa đăng (cần Trusted Publisher + chạy workflow từ `main`).

## [1.3.888] - 2026-11-12

### feat: VieNeu Nano và Turbo tải model từ kho raikiri1498/VieNeu-TTS

Anh Bửu tạo kho Hugging Face riêng `raikiri1498/VieNeu-TTS` và dặn: *"thêm tải các model và dữ liệu cho turbo và nano và push vào folder này cho tôi, nhớ ghi nguồn giúp tôi"*, *"NHỚ ĐỔI LINK DOWNLOAD TRONG APP"*.

- **Kho mirror** (commit `3486d7da`), chép **nguyên văn từng byte** đúng các revision app đã ghim. Đối chiếu sha256 với số Hugging Face công bố; file từ GitHub đối chiếu theo kích thước. Tắt đổi xuống dòng (`core.autocrlf false`) vì `config.json`, `manifest.json`, `ref_codes.txt` gốc dùng CRLF; blob trùng blob id của kho gốc.
  - `common/` (dùng chung, anh Bửu: *"file nào dùng chung thì để ở common"*): `sea_g2p.bin` của `pnnbao97/sea-g2p` @ `e825173f`, `speaker_encoder.onnx` + `denoiser.onnx` (có ở cả kho Nano lẫn Turbo, trùng sha256).
  - `nano/`: 8 file còn lại của `pnnbao-ump/VieNeu-TTS-v3-Nano` @ `aba295eb` (4 graph đọc, `codec_encoder` + `reference_encoder` để nhân bản giọng, `config.json`, `constants.npz`), cộng `voices_v3_nano.json` của `pnnbao97/VieNeu-TTS` @ `2e982ff8`.
  - `turbo/gguf/`: GGUF q8_0 và 25 giọng + `manifest.json` của `pnnbao-ump/VieNeu-TTS-v3-Turbo` @ `61b85e3d`.
  - README ghi nguồn, revision, giấy phép (cả bốn nguồn đều Apache-2.0), lý do bỏ bf16 / ONNX / safetensors. Kèm `LICENSE`, `SHA256SUMS` và model card gốc (`UPSTREAM_README.md`).
- **App**: `VieNeuModelMirror` (mới, `Services/TTS/VieNeu/`) giữ tên kho + commit ghim + `url(path:)` + `commonFileNames` / `nanoStorePath` (file dùng chung ⇒ `common/`).
  - `VieNeuModelClient` (4 graph, cấu hình, 3 graph clone, giọng, `sea_g2p.bin`) và `VieNeuTurboModelStore.remoteURL` (GGUF, manifest, file giọng) tải từ đó.
  - Bỏ các hằng revision cũ; nguồn gốc ghi lại trong doc.
  - Nội dung trùng từng byte ⇒ file đã tải trên máy dùng tiếp, `modelByteCount` không đổi.
- Chữ ở Cài đặt VieNeu (gói Nano) và màn thử Turbo ghi nguồn mới kèm tác giả gốc.
- **Kiểm chứng:** tải thử từng URL mới của kho (HTTP 200, đúng kích thước); đọc code + grep chéo (không còn `pnnbao-ump/…/resolve` hay `raw.githubusercontent.com/pnnbao97` trong `Sources/`); `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Chưa thử tải trong app.

## [1.3.887] - 2026-11-12

### merge: đưa VieNeu Turbo GGUF vào main

Anh Bửu: *"vì turbo chạy cũng ổn rồi nên tôi nghĩ bạn nên merge turbo vào nhánh main"*. Merge `origin/main` (tới 1.3.873) vào `feature/vieneu-turbo-gguf` rồi đẩy lên `main`.

- **Đánh lại số**: 13 bản của nhánh (trước là 1.3.845–857, trùng số với main) thành **1.3.874–886**, giữ thứ tự và tiêu đề. Đổi cả tham chiếu trong thân entry và trong chú thích code của nhánh; dòng nào có y nguyên trong bản main thì giữ (là số của main). 14 entry cũ nhất của main (1.3.844–857) chuyển sang `CHANGELOG.archive.md`.
- Xung đột chỉ ở hai file CHANGELOG. Ba view cùng sửa (`TTSSettingsHubView`, `VieNeuTTSTestView`, `TTSSettingsView`) tự gộp: hàng / section Turbo nằm trong `Group { … }.glassSheetRows()` của 1.3.873. Màn thử Turbo (`VieNeuTurboLabView`) bọc theo cùng kiểu cho khớp.
- `audiocpp-ios.yml` chạy cả trên `main`. Cache `AudioCpp.xcframework` tạo trên nhánh không dùng được ở `main` ⇒ lượt build `main` đầu tiên dựng lại audio.cpp (lâu hơn vài phút), các lượt sau lấy từ cache.
- `CLAUDE.md` / `AGENTS.md`: thêm mục "VieNeu: hai model Nano / Turbo" ở phần TTS và bước dựng AudioCpp ở đoạn CI.
- **Kiểm chứng:** đọc lại phần tự gộp của ba view; grep không còn số 1.3.845–857 của nhánh trong file nhánh sửa; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows), CI build `main` sẽ là lần biên dịch đầu tiên của bản gộp.

## [1.3.886] - 2026-11-12

### revert: Nano đọc truyện bỏ ép QoS userInitiated, về như cũ vì đo trên máy không nhanh hơn

Anh Bửu nghe Nano trong trình đọc ở cùng cài đặt (Mai Anh, phát 1,5×, tổng hợp 1,15×, 2 luồng, ~5–6 phút mỗi bản), so bản cũ (trước 1.3.884) với 1.3.884:

| | Bản cũ | 1.3.884 |
|---|---|---|
| RTF | 0,28 | 0,28 |
| CPU-s / giây tiếng | 0,54 | 0,54 |
| CPU-s / 1.000 ký tự | 28,7 | 28,9 |
| Máy bận tổng hợp | ~40% | ~40% |
| Nhiệt | "nóng" sau ~4 phút | "nóng" sau ~4 phút |

Trình đọc Nano vốn đã chạy nhanh (bản cũ dùng ~2 lõi mỗi đoạn); con số "utility RTF 0,55" chỉ có ở màn thử vì màn thử ép utility. Ép `.userInitiated` không đổi gì ⇒ anh yêu cầu trả Nano về code cũ.

- `VieNeuTTSService`, `VieNeuTTSEngine+Reload`, `VieNeuTurboLab+Nano` về đúng bản trước 1.3.884: bỏ `readerPriority`, `setLabSynthesisPriority` và `Task.detached` bọc lượt tổng hợp; `prepare(voice:)` lại dựng session ở `.utility`.
- Giữ phần đo P0 (1.3.881: `vectorMs` / `codecMs` / `textMs`, `cpuSplit`, `qos=`) — cần cho việc tối ưu Nano tiếp.
- Màn thử: QoS mặc định của lượt Nano về `utility` như trước; sửa chú thích còn nói trình đọc Nano chạy userInitiated. Turbo giữ nguyên 1.3.885 (trình đọc Turbo thật sự bị runtime ép `.utility` nên đổi có tác dụng).
- **Kiểm chứng:** đọc code + grep chéo (`readerPriority`, `setLabSynthesisPriority` không còn chỗ gọi); `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Chưa thử máy.

## [1.3.885] - 2026-11-12

### perf: Turbo đọc truyện chạy lõi hiệu năng (userInitiated), nhanh gấp đôi và mát hơn

Anh Bửu đo Turbo ở màn thử › Đọc liên tục (1.3.884, iPhone 11, 2 luồng, cùng văn bản, mỗi lượt ~3 phút), đúng điều kiện của plan đã duyệt (bước 2 chỉ làm khi RTF ≲ 0,55):

| Giọng · QoS | RTF | CPU-s / giây tiếng | CPU-s / 1.000 ký tự | Nhiệt |
|---|---|---|---|---|
| Minh Quân Pro · utility | 0,71 | 1,35 | 71,8 | "nóng" từ ~2:30 |
| Minh Quân Pro · userInitiated | **0,35** | **0,70** | 37,0 | vẫn "ấm" |
| Mai Anh · utility | 0,73 | 1,36 | 82,6 | "nóng" từ ~2:00, có đoạn vọt RTF 1,17 |
| Mai Anh · userInitiated | **0,36** | **0,71** | 42,9 | vẫn "ấm", đoạn chậm nhất 0,41 |

Giống Nano (1.3.884): lõi hiệu năng nhanh gấp đôi và tốn ít CPU hơn ~48% (lõi tiết kiệm phải chạy gấp đôi thời gian). Âm thanh không đổi — chỉ đổi lõi chạy.

- `VieNeuTurboTTSService.readerQoS = .userInitiated`, truyền vào `VieNeuTurboRuntime.synthesize(…, qos:)` ⇒ cả luồng ggml của lượt chạy lõi hiệu năng. Nạp model / dựng session / nhả vẫn ở hàng đợi `.utility`.
- `realtimeSpeedLimit` 1,4 → **2,0** (RTF phải dưới 0,5; đo được 0,36, chậm nhất 0,41 ⇒ chừa khoảng cho máy nóng khi nghe lâu và giọng chưa đo là Adam bựa). Màn Cài đặt TTS cảnh báo khi tốc độ phát vượt mức này.
- Dòng log mỗi đoạn `[VieNeuTurbo] Đoạn:` thêm `qos=` (QoS **đo được**) để kiểm khi khoá màn / chạy nền iOS có giữ lõi hiệu năng không.
- Màn thử: QoS mặc định của lượt Nano và Turbo thành `userInitiated` (= trình đọc), vẫn chọn `utility` để so; "Đọc thử một lần" ghi QoS đo được thay vì chữ "utility" cố định (bỏ `VieNeuTurboRuntime.qosName`); sửa các chú thích còn nói trình đọc chạy utility.
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Mới đo ở màn thử, chưa thử trong trình đọc khi khoá màn.

## [1.3.884] - 2026-11-11

### perf: Nano đọc truyện chạy lõi hiệu năng (userInitiated), nhanh gấp đôi và tốn ít CPU hơn

Anh Bửu đo P0 trên iPhone 11 (màn thử › Đọc liên tục › Nano, 2 luồng, giọng Minh Quân, cùng văn bản, 1.3.882) rồi duyệt *"làm Nano trước đi"*:

| | userInitiated | utility (cũ) |
|---|---|---|
| RTF | **0,28** | 0,55 |
| CPU-s / giây tiếng | **0,56** | 0,88 |
| CPU-s / 1.000 ký tự | **30,9** | 48,6 |
| Nhiệt | 3:45 vẫn "ấm" | "nóng" ở phút 4 |

Lõi hiệu năng vừa nhanh gấp đôi vừa tốn ít CPU hơn ~36% và mát hơn (mỗi cấu hình đo một lượt). Âm thanh giống hệt từng bit — chỉ đổi lõi chạy.

- `VieNeuTTSService.readerPriority = .userInitiated`: `prepare(voice:)` dựng session ORT ở mức này (luồng phụ của pool sinh ra lúc dựng); trước đó `.utility`.
- Lượt tổng hợp chạy ORT trong `Task.detached(priority:)` ở mức cố định đó, thay vì mức của tác vụ nào xếp hàng trước trong `PiperSynthesisCoordinator` (phần lớn `.utility`). Lệnh huỷ được chuyển xuống task con (`withTaskCancellationHandler`) vì engine kiểm `Task.checkCancellation()` giữa các chunk / bước Euler.
- Màn thử vẫn đo A/B được: `setLabSynthesisPriority` ghi đè mức tổng hợp trong lúc đo, `endNanoOverride` trả về. Dòng `[VieNeuPerf]` (1.3.881) có `qos=` / `sessionQos=` để kiểm trên máy.
- Turbo **chưa đổi** (vẫn `.utility`), chờ đo ở màn thử (1.3.883).
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Chưa thử máy.

## [1.3.883] - 2026-11-11

### feat: màn thử Turbo chọn QoS (utility / userInitiated) để đo lõi hiệu năng

Anh Bửu nghe Turbo trên truyện thật ở tốc độ phát **1,4×**: Minh Quân Pro hụt ít, Mai Anh và Adam bựa hụt nhiều. Ở 1,4× cần RTF < 0,714, Turbo đang ~0,70 (QoS utility) ⇒ sát mép. Anh duyệt plan: đo QoS cao hơn ở màn thử trước, đạt RTF ≲ 0,55 mới đưa vào trình đọc. Lượt này chỉ là phần đo; **trình đọc không đổi** (vẫn utility).

- `VieNeuTurboRuntime.synthesize(…, qos:)` (mặc định `.utility`): mỗi lượt chạy trên hàng đợi tuần tự với QoS riêng (`async(qos:flags: .enforceQoS)`). Không OpenMP ⇒ ggml tạo luồng tính mới mỗi lượt từ chính luồng gọi, luồng mới mang QoS của nó ⇒ nâng QoS một lượt là cả lượt chạy ở mức đó. `Output.qosName` = QoS **đo được** (`qos_class_self()`).
- Màn thử › Đọc liên tục (Turbo): Picker QoS utility / userInitiated (`VieNeuTurboLab.turboQoS`, chỉ cho lượt đo); "Đọc thử một lần" cũng theo lựa chọn này. Mỗi dòng đoạn ghi "QoS tổng hợp …" đo được; mô tả engine ghi QoS đã chọn; chú thích "Nghe ở 1,4× cần RTF dưới 0,71".
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Chưa thử máy.

## [1.3.882] - 2026-11-11

### fix: xoá model Nano không làm hỏng Turbo, màn thử hết đua khi đổi Nano/Turbo

Rà soát độc lập (agent) cả đợt 1.3.878–1.3.881 trước khi build lần đầu: không thấy lỗi biên dịch chắc chắn, có 4 lỗi logic — sửa cả 4.

- **Xoá model Nano xoá luôn `sea_g2p.bin`** — bộ phiên âm dùng chung với Turbo ⇒ model hiệu lực lật về Nano (vừa bị xoá), trình đọc đang chọn Turbo hỏng ngầm, mỗi đoạn lỗi thiếu model. `VieNeuModelStore.deleteAll` nay giữ `sea_g2p.bin` khi máy còn model Turbo.
- **Đua ở màn thử**: lượt trả engine Nano về cấu hình người dùng (`endNanoOverride`) chạy Task không giữ lại, có thể chặn vài giây rồi nhả Turbo / xoá ghi đè luồng chen vào lượt "Đọc thử" hay "Đọc liên tục" vừa bấm. Nay giữ ở `nanoRestoreTask`, hai lượt đó chờ nó xong mới chạy.
- **Số đo Nano cộng trùng ở đoạn im lặng**: đường im lặng của `VieNeuTTSService` không chạy engine nhưng để nguyên `lastTiming` của đoạn trước ⇒ màn thử cộng lại lần nữa. Nay xoá `lastTiming` trên đường đó.
- **"Xoá model" Turbo ở màn thử** đưa trình đọc về `"vieneu"` cả khi máy chưa có model Nano ⇒ trình đọc trỏ vào engine thiếu model. Nay chưa có Nano thì về Siri (`"system"`, mặc định của app).
- Bỏ cảnh báo kết quả không dùng (`_ = await Task.detached { … }.value`).
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Lượt CI kế tiếp là lần biên dịch đầu của cả đợt; chưa thử máy.

## [1.3.881] - 2026-11-11

### feat: Nano đo riêng vòng Euler, codec, text; màn thử chọn luồng/QoS cho Nano và chia sẻ file kết quả

Anh Bửu duyệt P0 của báo cáo tối ưu Nano (`Docs/Reports/2026-11-11-vieneu-nano-toi-uu.md`): *"làm trước P0 đi"* + *"cho sửa thành share file luôn, copy gửi cực quá"*. Không đổi cách tổng hợp — tiếng ra giữ nguyên.

- **Sửa phép đo engine Nano**: `runChunk` chốt `vectorMs` **sau** `codec_decoder` ⇒ số "vòng Euler 98%" thật ra gồm cả codec (đo PC: Euler ~81%, codec ~17%). Nay `StageClock` (`VieNeuTTSEngine+Timing`, mới) bấm giờ nối tiếp ba giai đoạn text (text_encoder + duration + nhiễu) / vòng Euler / codec, mỗi giai đoạn cả thời gian tường lẫn CPU-time. `Timing` có `text` / `vector` / `codec`; `vectorMs` chỉ còn vòng Euler, `otherMs` = text + codec (màn Nghe thử giữ "vector | khác"). `[VieNeuPerf]` thêm `codecMs= textMs= cpuSplit=text/vector/codec qos= sessionQos=` (QoS **đo được** của luồng tổng hợp và của luồng dựng session — `Timing.synthesisQoS`, `VieNeuONNXRuntime.buildQoS`); dòng "Nạp xong engine" thêm `qos=`. `VieNeuTTSService.lastTiming` cho màn thử đọc.
- **Ghi đè số luồng cho màn thử** (`VieNeuTTSEngine+Reload`): `setLabThreadOverride` (không ghi vào cài đặt) buộc dựng lại session; `VieNeuTTSService.prepare(voice:priority:)` (hàm riêng — `LocalTTSEngine` đòi đúng `prepare(voice:)`) dựng ở QoS chọn vì luồng phụ của pool ORT sinh ra lúc dựng session. Ghi đè chạy ở luồng nền (khoá tổng hợp có thể đang giữ bởi đoạn chạy dở).
- **Màn thử VieNeu Turbo** — lượt Nano của "Đọc liên tục" (`VieNeuTurboLab+Nano`, tách khỏi `+Run`): chọn **số luồng ORT** (2/3/4) và **QoS** (utility / userInitiated), dựng lại session ở đúng mức đó rồi tổng hợp ở cùng mức; dừng / rời màn / nạp lỗi ⇒ bỏ ghi đè rồi: trình đọc đang ở Nano thì dựng lại ở `.utility` như lúc app nạp engine, đang ở Turbo thì **nhả** Nano (`releaseEngineRuntime`) — hai model không cùng nằm trong RAM. Đoạn nhả Turbo của `prepare` nằm trong `prepare(voice:priority:)` nên đường của màn thử cũng nhả. Mỗi đoạn ghi "Euler / codec / text" (giây tường + CPU-s) và "QoS tổng hợp X · session Y" đo được, tổng kết thêm **phân rã** theo thời gian và theo CPU. QoS tới được luồng tổng hợp vì `PiperSynthesisCoordinator` chạy việc trong `Task` lồng — kế thừa priority của task gọi; dòng QoS đo được là bằng chứng trên máy.
- **Chia sẻ file thay sao chép**: hai nút "Sao chép số đo" / "Sao chép kết quả đọc liên tục" ⇒ **"Chia sẻ file … (.txt)"** (`VieNeuTurboReportFile`, dựng lúc bấm như `ThermalCSVExport`): đầu file có bản app, mã máy, giờ, nhiệt; file đọc liên tục có tổng kết + mọi phút + **mọi** đoạn (màn chỉ hiện 40 đoạn gần nhất).
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows), chưa thử máy.

## [1.3.880] - 2026-11-11

### fix: màn thử Turbo dừng trình đọc đang dùng Turbo trước khi xoá model

- Màn thử Turbo và trình đọc dùng chung runtime: "Xoá model" lúc trình đọc đang đọc bằng Turbo nay dừng TTS trước (như khi màn thử giành âm thanh), thay vì nhả runtime + xoá file dưới chân trình đọc đang phát.

## [1.3.879] - 2026-11-11

### feat: VieNeu Turbo thành trình đọc cạnh Nano trong Cài đặt TTS

Phần giao diện của đợt B, đúng mockup anh Bửu đã duyệt.

- Picker "Trình đọc" có "VieNeu-TTS v3 Turbo (Offline)" ngay dưới Nano (dòng phụ "Hay hơn Nano, tốn CPU khoảng 1,5 lần"), chỉ hiện khi đã tải model Turbo. Picker dùng binding riêng: hai mục VieNeu cùng ánh xạ về `tool = "vieneu"` + model; ghi model trước rồi gán `tool` ⇒ đổi model đi đúng luồng đổi engine (nạp tham số + giọng của model, bỏ phần đệm, nạp sẵn engine).
- Chưa tải Turbo ⇒ hàng "Tải model VieNeu Turbo (188 MB)" dưới Picker, bấm là tải tại chỗ (dùng lượt tải của màn thử Turbo): "Đang tải model VieNeu Turbo" + "74 / 188 MB" + thanh tiến độ; lỗi hiện dưới nút. Trong lúc tải trình đọc đang chọn vẫn đọc bình thường.
- "Giọng đọc VieNeu" khi chọn Turbo: 25 giọng của manifest, nhóm "Tuyển chọn" (10 giọng ⭐, bỏ ⭐) rồi "Giọng khác"; mỗi mục tên + dòng phụ "Nam · Bắc · tự nhiên" (+ "mặc định"). Chọn giọng chưa có file ⇒ tải ngay vài KB.
- "Quản lý riêng của trình đọc" khi chọn Turbo: hàng "Tổng hợp Turbo — 2 luồng, cố định" thay Tiết kiệm pin / Chế độ tạo audio / Số luồng / spin ORT; giữ hai công tắc tiếng Nhật + từ điển tiếng Nhật; ẩn "Giọng của tôi", thay bằng chú thích về 2 lõi hiệu năng, máy ấm và giọng nhân bản chỉ dùng với Nano.
- "Cấu hình giọng nói" khi chọn Turbo: ẩn "Tốc độ tổng hợp (VieNeu)", thay chú thích "Turbo luôn tổng hợp ở tốc độ gốc…"; Tốc độ > 1,4× ⇒ cảnh báo cam "Turbo theo kịp tới khoảng 1,4×. Ở 1,6× có thể hụt tiếng…" (ngưỡng `VieNeuTurboTTSService.realtimeSpeedLimit`, từ RTF ~0,70 đo trên máy). "Đặt lại" không đụng tốc độ tổng hợp của Nano khi đang chọn Turbo.
- "Tải trước dữ liệu" giữ nguyên, dùng chung cho hai model. Dòng "Nghe truyện (TTS)" ở Cài đặt ghi "VieNeu Turbo" khi đang chọn Turbo.

## [1.3.878] - 2026-11-11

### feat: engine VieNeu Turbo cho trình đọc truyện (chọn model Nano/Turbo, khoá cache theo model, nhả model không dùng)

Đợt B của Turbo GGUF (anh Bửu duyệt mockup, artifact "VieNeu Turbo trong Cài đặt TTS"). Phần engine; giao diện ở 1.3.879. Viết ở session con, cherry-pick sang `feature/vieneu-turbo-gguf`.

- `tool` vẫn là `"vieneu"` (không thêm chuỗi engine mới); model lưu ở khoá `vieneuModel` qua `VieNeuModelChoice`. Model hiệu lực chỉ là Turbo khi bản build có audio.cpp và máy đủ GGUF + manifest giọng + `sea_g2p.bin`, thiếu thì trình đọc rơi về Nano.
- `VieNeuTurboTTSService` (mới, `LocalTTSEngine`): `TTSManager.localEngine` trả nó khi chọn Turbo. Đi qua `PiperSynthesisCoordinator` như Nano; tiền xử lý bằng `VieNeuTurboTextFrontend` (số/ngày, tiếng Nhật theo cờ VieNeu, sea-g2p); `VieNeuTurboRuntime` CPU 2 luồng cố định; trả WAV mono 48 kHz + khoảng lặng đuôi theo ranh giới (1×) + `pcmDuration` + `synthesisMs`. Không có tốc độ tổng hợp (luôn 1×). Đoạn không đọc được / phiên âm rỗng ⇒ im lặng 48 kHz. Kiểm huỷ trước lượt audio.cpp (không huỷ được giữa chừng). Giọng chưa có file thì tải cặp file vài KB (gộp lượt tải trùng).
- Màn thử giọng Nano, thư viện giọng nhân bản và lượt Nano của màn thử Turbo vẫn gọi thẳng `VieNeuTTSService` ⇒ luôn là Nano.
- Khoá tổng hợp gồm model: `TTSSynthesisIdentity.computeKey` gắn `vieneu.turbo` cho Turbo (Nano giữ `vieneu`, khoá cũ không đổi) ⇒ đổi model không phát lại audio của model kia; `localSynthesisSpeed` trả 1× cho Turbo; `TTSSettingsSnapshot` có `vieneuModel` ⇒ đổi model trong Cài đặt TTS dựng lại đoạn như đổi engine.
- Giọng nhớ riêng theo model: Nano khoá `vieneuVoice`, Turbo khoá `vieneuTurboVoice` (mặc định `minh_quan_pro`, giọng không còn trong manifest ⇒ mặc định).
- Bộ nhớ: Turbo chuẩn bị / tổng hợp ⇒ nhả engine Nano nếu đang nạp (`VieNeuTTSEngine.releaseRuntime`: 4 session ORT + bộ phiên âm); trình đọc về Nano ⇒ nhả model Turbo + bộ phiên âm Turbo. Trình đọc và màn thử Turbo dùng chung `VieNeuTurboRuntime.shared` + `VieNeuTurboTextFrontend.shared` (một model 188 MB trong RAM); rời màn thử không nhả khi trình đọc đang chọn Turbo; "Xoá model" ở màn thử đưa trình đọc về Nano.
- `[VieNeuTurbo] Đoạn:` mỗi đoạn: ms phiên âm / audio.cpp / tổng hợp, giây tiếng, RTF, CPU/tiếng, nhiệt, RAM. Dòng ❌ khi lỗi cấp phát ghi rõ "đang dựng lại session và thử lại đoạn này"; lỗi khác giữ như cũ.
- Màn thử Turbo có thêm số byte đang tải + lỗi tải riêng (cho hàng tải ở Cài đặt TTS).

## [1.3.877] - 2026-11-11

### fix: Turbo GGUF hết lỗi thiếu bộ nhớ khi nạp prompt (vá audio.cpp tái sử dụng bộ nhớ, tự thử lại)

Anh Bửu đo 1.3.876 trên máy: Turbo 2 luồng RTF 0,71, không hụt tiếng, nghe hay hơn Nano — nhưng đoạn thứ 36 lỗi `audiocpp_session_run lỗi: runtime error — failed to allocate VieNeu-TTS talker prefill graph`. Anh duyệt: *"sửa A trước rồi đo lại lần nữa"*.

- **Nguyên nhân** (đọc mã audio.cpp `v0.9.4`, `talker.cpp:1212`): `TalkerPrefillGraph` — bước nạp prompt (phiên âm + mã giọng tham chiếu) qua 12 lớp — gọi `ggml_backend_alloc_ctx_tensors`, tức cấp phát **riêng** cho mọi tensor trung gian của cả 12 lớp (điểm attention S×S, MLP…), không tái sử dụng; graph dựng lại mỗi khi độ dài prompt đổi (gần như mỗi đoạn). Đoạn hỏng chính là đoạn đầu của vòng 2 — vòng 1 vẫn chạy được ⇒ không phải đoạn quá dài mà lúc đó app còn ít bộ nhớ trống.
- **Vá audio.cpp lúc build** (`Scripts/ci/audiocpp_patches/vieneu_prefill_gallocr.py`, gọi từ `build_audiocpp_ios.sh`; sửa theo mốc chuỗi cố định, mốc lệch ⇒ build đỏ): đầu vào + K/V từng lớp + hidden + logits nằm ở context nhỏ riêng cấp phát cố định (kết quả được `ggml_cpy` sang), mọi tensor trung gian còn lại do `ggml_gallocr` cấp phát có tái sử dụng. Phép tính giữ nguyên.
- **Kiểm không đổi tiếng** (`Scripts/ci/audiocpp_parity_macos.sh`, job `parity` của `audiocpp-ios.yml`): build `audiocpp_cli` macOS bản gốc + bản vá, đọc câu ngắn và câu dài ~4 lần bằng greedy (`do_sample=false`, seed 1, tắt babble guard), so mã âm thanh + WAV từng byte, in RAM tối đa của mỗi bản. Tag audio.cpp tách ra `Scripts/ci/audiocpp_ref.txt`; khoá cache framework (cả `build-ipa.yml`) gồm script + tag + bản vá.
- **Tự cứu trong app** (`VieNeuTurboRuntime`): `audiocpp_session_run` lỗi cấp phát (`AUDIOCPP_ERR_OUT_OF_MEMORY` hoặc "allocate") ⇒ nhả session (graph + bộ đệm của nó), dựng lại cùng số luồng, đọc lại đúng đoạn đó **một** lần; lỗi khác thì báo như cũ. Thời gian / CPU đo gồm cả lần hỏng.
- **Đo bộ nhớ**: `ProcessMemoryProbe` (mới, `Services/Diagnostics/`) — `phys_footprint` (số iOS dùng để giết app) + `os_proc_available_memory()`. Mỗi dòng đoạn của "Đọc liên tục" (màn + log) thêm "RAM … MB · trống … MB"; lỗi, dựng session, thử lại đều ghi kèm. audio.cpp `v0.9.4` (ABI 0.2) chưa có `audiocpp_log_set` nên chưa lấy được log của ggml.
- **Kiểm chứng:** script vá chạy thử trên bản audio.cpp `v0.9.4` tải về (mốc khớp, chạy lần hai tự bỏ qua); `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**; job parity trên CI là bằng chứng không đổi tiếng. Chưa thử máy.

## [1.3.876] - 2026-11-11

### fix: màn thử VieNeu Turbo đo Turbo và Nano cùng mức ưu tiên luồng, dừng khi bị ngắt âm thanh

- Turbo (hàng đợi audio.cpp + luồng ggml) và lượt Nano của chế độ đọc liên tục cùng chạy ở QoS `utility` — cùng mức session ORT của Nano được dựng; QoS quyết chuyện lõi hiệu năng hay lõi tiết kiệm nên hai engine phải chung một mức. Mô tả engine, số đo đọc thử và log ghi rõ QoS.
- Đo Nano thì nhả Turbo trước (model ~188 MB + `sea_g2p.bin` của Turbo) để bớt áp lực bộ nhớ và cửa sổ CPU của Nano không lẫn Turbo; lượt Nano dùng khoá tổng hợp ngẫu nhiên nên vòng lặp sau không dùng lại kết quả vòng trước.
- Cuộc gọi / Siri ngắt âm thanh ⇒ dừng hẳn lượt đọc liên tục (trước đó trình phát đứng im mà đồng hồ vẫn chạy).
- Thêm chỉ số **CPU/1k ký tự** (mỗi phút và tổng kết) — không lệ thuộc giọng nói nhanh hay chậm, so hai engine công bằng hơn CPU/tiếng.
- `build-ipa.yml` build IPA cho nhánh `feature/vieneu-turbo-gguf` (IPA chỉ gửi Telegram; nguồn LiveContainer vẫn chỉ lấy từ `main`).
- **Kiểm chứng:** đọc code; `check_architecture.py` **0 mới**. Lượt CI của nhánh là lần biên dịch đầu; chưa thử máy.

## [1.3.875] - 2026-11-11

### feat: màn thử VieNeu Turbo GGUF qua audio.cpp (đo RTF, CPU, nhiệt)

Phần Swift của bước thử Turbo GGUF (anh Bửu duyệt "làm thử trên nhánh mới"), dùng `AudioCpp.xcframework` của 1.3.874. Viết ở session con, cherry-pick sang nhánh `feature/vieneu-turbo-gguf`.

- Màn **Thử VieNeu Turbo (GGUF)** mở từ Cài đặt VieNeu TTS (hàng "Thử VieNeu Turbo (GGUF) — thử nghiệm", không cần model Nano): tải model GGUF q8_0 chính thức (`pnnbao-ump/VieNeu-TTS-v3-Turbo`, ghim revision `61b85e3d`, đúng 187.917.664 byte, tiến độ theo byte) + manifest 25 giọng + cặp file của giọng (`ref_codes.txt`, `speaker.emb.txt`, tải khi dùng lần đầu). `sea_g2p.bin` dùng chung với Nano; máy chưa có thì tải đúng nguồn ghim sha của `VieNeuModelClient`. Thư mục riêng `Application Support/FreeBook/TTS/VieNeuTurbo/` (màn Dung lượng đã tính trong "Giọng đọc & từ điển TTS"). Nút xoá model Turbo giữ `sea_g2p.bin`.
- `VieNeuTurboRuntime` bọc C API audio.cpp (`import AudioCpp`, header tag `v0.9.4` — ABI 0.2.0): registry → model (`family_hint = vieneu_v3_turbo`) → session CPU N luồng; mọi lời gọi trên một hàng đợi tuần tự, `audiocpp_last_error` đọc ngay trên cùng luồng; nạp model một lần, đổi số luồng chỉ dựng lại session; nhả khi rời màn. Bản build thiếu framework ⇒ `#if canImport(AudioCpp)` ném "Bản build này chưa có audio.cpp".
- Chữ → phiên âm đi đúng đường Nano: thay thế ký tự → `normalizeVietnameseText` → tiền xử lý tiếng Nhật của VieNeu → `SeaG2P.phonemizeTextWithEmotions` (thực thể riêng). Tiếng stereo 48 kHz trộn về mono, WAV 16-bit 48 kHz.
- **Đọc thử một lần**: thời gian nạp model / dựng session, phiên âm, audio.cpp, độ dài tiếng, RTF, CPU-s mỗi giây tiếng (`ProcessCPUClock`), % một lõi, nhiệt trước → sau; chia sẻ WAV, sao chép số đo.
- **Đọc liên tục (đo nhiệt)**: lặp văn bản dài (mẫu ~2.600 chữ tự viết, hoặc dán), cắt ≤ 150 ký tự bằng `NghiUtteranceSegmenter`, tổng hợp trước tối đa 2 đoạn, phát nối tiếp (lúc hụt tiếng phát vòng lặng để khoá màn vẫn chạy); ghi từng đoạn + tổng kết mỗi phút (giây tiếng, CPU-s, CPU/tiếng, số lần hụt, nhiệt) lên màn và log `🎙️ [VieNeuTurbo]`. Chọn được **Nano** (qua `VieNeuTTSService.synthesizeWithDuration`, tốc độ 1×, không sửa engine) để so cùng văn bản, cùng máy. Bắt đầu đọc thì dừng TTS chính, giành `AVAudioSession` `.playback`.
- **Kiểm chứng:** đọc code — mọi chỗ gọi C API khớp `audiocpp.h` tag `v0.9.4` (handle `OpaquePointer`, `audiocpp_status`, struct cấu hình dựng trong `withCString`, con trỏ kết quả mượn được chép trước khi free); chữ ký các API sẵn có (`VieNeuTTSService.synthesizeWithDuration`, `NghiUtteranceSegmenter.expand`, `SeaG2P(binURL:)`, `VieNeuJapanesePreprocessor.applyUsingStoredFlags`, `TTSManager.stop()`) khớp; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Chưa biên dịch tại chỗ (Windows), chưa thử máy.

## [1.3.874] - 2026-11-11

### ci: dựng audio.cpp cho iOS thành AudioCpp.xcframework để thử VieNeu Turbo GGUF

Anh Bửu duyệt bước thử chạy VieNeu-TTS **v3 Turbo** bằng file GGUF q8_0 chính thức qua **audio.cpp** (ggml, Apache-2.0) trên nhánh `feature/vieneu-turbo-gguf` — sau khi thấy một app đọc truyện khác chạy Turbo bằng GGUF mà không nóng máy. Lượt này chỉ là phần build; màn thử Swift đi ở commit sau.

- **`Scripts/ci/build_audiocpp_ios.sh`** (mới): clone audio.cpp tag `v0.9.4`, cross-compile cho iOS 17 arm64 chỉ family `vieneu_v3_turbo`, chỉ CPU (iOS không cho app chạy nền dùng GPU, mà TTS phải đọc khi khoá màn hình), tắt OpenMP (Apple clang không có), kernel ggml `-march=armv8.2-a+dotprod+fp16` (**A13 trở lên**; A12 sẽ lỗi lệnh khi chạy Turbo). sentencepiece (vendored) gọi macro `set_xcode_property` chỉ có trong bộ toolchain iOS riêng của nó ⇒ script khai macro rỗng qua `CMAKE_PROJECT_INCLUDE`. Đóng gói target C API (SHARED, chỉ xuất `audiocpp_*` nên ggml / sentencepiece không đụng symbol của app) thành `AudioCpp.framework` có module map ⇒ Swift `import AudioCpp`; kiểm phụ thuộc chỉ còn thư viện hệ thống, biên dịch thử một file Swift gọi `audiocpp_abi_version()` cho iOS, rồi `xcodebuild -create-xcframework` ra `Vendor/AudioCpp/` (gitignore).
- **`build-ipa.yml`**: cache `Vendor/AudioCpp` theo hash của script, thiếu thì chạy script trước `xcodegen generate`. **`audiocpp-ios.yml`** (mới, chỉ nhánh thử + chạy tay): dựng riêng framework, không build app, không gửi Telegram — để sửa script nhanh; chung khoá cache.
- **`project.yml`**: link + embed `Vendor/AudioCpp/AudioCpp.xcframework`. Trên Mac muốn generate project thì chạy script trước.
- **Kiểm chứng:** chưa — Windows không build được; lượt CI `audiocpp-ios.yml` là lần biên dịch đầu.

## [1.3.873] - 2026-11-11

### feat: mọi sheet và popup dùng nền kính, ô mờ như sheet hub, độ đục thấp nhất 20%

Anh Bửu: "sửa nền các loại sheet như các sheet gần đây", "như hub, nút + kệ sách… hạn chế mức thấp nhất độ đục là 20% nhé", "mấy pop up như bật tắt dịch cũng vậy nhé" (đã duyệt mockup + plan).

- **Modifier dùng chung** (mới, `Views/Common/GlassChrome/AppGlassSheetModifier.swift`): `.appGlassSheet()` (sheet — nền `DrawerGlassSheetBackground`, bo 16), `.appGlassPopover()` (popup), `.appGlassUIKitSheet()` (sheet trình bày bằng UIKit — kính vẽ bằng `.background`); cả ba ẩn nền danh sách, tông tối, đặt environment `isGlassSheet`. `.glassSheetRows()` cho ô danh sách mờ `Color.primary.opacity(0.08)` (màu dòng của sheet hub) — chỉ có tác dụng trong sheet kính (ngoài sheet kính không ghi `listRowBackground` nào, kể cả `nil`) nên trang thường dùng chung view giữ y nguyên, kể cả dòng tự đặt nền riêng; `.glassAwareBackground(_:)` cho nền đặc tự tô trong view dùng chung (thanh tìm của `SearchView`).
- **122 chỗ mở sheet** (khoảng 60 loại) bọc `Group { … }.appGlassSheet()` bằng script có kiểm cân bằng ngoặc. Không gắn: sheet chia sẻ / chọn file của hệ thống, bảng mục lục / cài đặt / tra từ / tìm của Reader và truyện tranh (theo nền đọc), trang đăng nhập web, sheet đã có nền riêng (sheet hub, sheet nghe / TTS, sheet kiểu hub, sheet "đang đọc chương này").
- **114 `List` / `Form`** bọc `Group { … }.glassSheetRows()` dạng gọn (`List { Group {` … `}.glassSheetRows() }`, không thêm dòng — giữ baseline dòng của file legacy). CI lượt đầu đỏ ở hai `List(…) { _, result in` (tham số hai tên nằm dòng dưới `{`, script đặt `Group {` trước tham số) ⇒ sửa tay ở `LegadoCheckReportContent` và `LegadoSourceCheckView`. Bỏ nền đặc tự tô ở `MediaSleepTimerSheet`, `TTSQuickTimerSheet`, `FilterSheet`; ô thông tin `AppUpdateSheet`, thẻ `TTSQuickTimerSheet` và dòng chưa chọn của `DictionaryImportConflictView` dùng màu ô mờ khi ở sheet kính.
- **5 popup** gắn `.appGlassPopover()`: bật tắt dịch (Reader / truyện tranh, Khám phá), "?" giải thích, bảng khiên và bảng chọn tiện ích của nút "Nhập" ở trình duyệt.
- **Màn kiểm tra nguồn mở lại bằng UIKit** (`MinimizedSourceCheckCoordinator.reopen`): kính `.appGlassUIKitSheet()`, hosting trong suốt, bo 16.
- **Độ đục thấp nhất 20%** (`GlassChromeSettings.minimumDrawerFrost` / `effectiveDrawerFrost`): thanh "Độ đục" của Menu ba chấm bắt đầu từ 20%; nền sheet / popup, ngăn kéo `…` và thanh kính trình duyệt kẹp giá trị cũ dưới 20% lên 20%. Giải thích của mục Menu ba chấm ghi rõ mọi sheet / popup dùng chung nền này.
- `CLAUDE.md` / `AGENTS.md`: luật nền kính cho sheet / popup mới.
- **Kiểm chứng:**
  - Đọc code + script kiểm cân bằng ngoặc mọi file sửa. `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 lỗi mới**.
  - **Chưa build** (máy Windows) — CI sẽ biên dịch. **Chưa thử trên máy.**
  - Cần thử: mở các sheet hay dùng (nhấn giữ truyện, tải / xuất, kiểu hiển thị, bộ sưu tập, playlist, bộ lọc tiện ích, cập nhật app, từ điển, cài đặt TTS, hẹn giờ) ⇒ nền kính bo 16, ô mờ, chữ đọc rõ; popup dịch / "?" ⇒ nền kính; Cài đặt › Giao diện › Menu ba chấm › Độ đục thấp nhất 20%; trang Cài đặt thường, Kệ, Playlist, Dung lượng (không phải sheet) giữ y nền cũ — có đổi là lỗi; nền ô có tới được dòng nằm trong `Section` không (không tới ⇒ ô vẫn xám đặc, chỉ là thẩm mỹ).
