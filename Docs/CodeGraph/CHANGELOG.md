# CHANGELOG - Nhật ký Thay đổi CodeGraph Tàng Công Các

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **Tàng Công Các**.

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

## [1.3.872] - 2026-11-11

### feat: Từ URL, Thông báo và Kiểm tra nguồn chuyển trang ngay trong sheet như Tác vụ AI

Anh Bửu: "làm cho sheet import từ URL cũng chuyển sheet giống sheet hub vào sheet tác vụ AI", "màn hình thông báo vào kiểm tra nguồn cũng chuyển giống vậy được chứ" (đã duyệt mockup bấm thử + plan).

- **Trang con cho sheet kiểu hub** (`HubStyleActionSheet`): dòng có `page` (`HubStyleActionSheetContent.Page`) ⇒ chạm chuyển trang ngay trong sheet, sheet lên nấc large, tiêu đề giữa + nút ‹ về trang chính (về lại chiều cao vừa nội dung). Đường đóng chung `CloseSheet` (đóng xong mới làm) thay `onSelect`, dùng được cho cả sheet nằm trên viên thuốc lẫn sheet lùi.
- **Nút ‹ trang con dùng chung** (mới, `SheetPageBackButtonModifier`): environment `sheetPageBack` + `.sheetPageBackButton()` gắn bên trong `NavigationStack` của trang; không có hành động ⇒ không có nút (màn dùng chung mở ở chỗ khác vẫn như cũ).
- **Kệ › nút "+" › Từ URL** là trang con trong sheet "Nhập truyện" (`ShelfImportURLStep`, ô link tự focus sau 0,35 s). Chọn tiện ích / mở link trong trình duyệt ⇒ sheet đóng xong mới làm (`ShelfView.runImportChoice`). Bỏ sheet "Nhập từ URL" riêng (`ShelfImportSheet`, `showingImportSheet`, `queuedImportChoice`); lựa chọn tách thành `ShelfImportChoice`.
- **Cửa sổ sheet nhận bàn phím**: `OverlaySheetPresenter` cho cửa sổ phủ nhận key trong lúc có sheet (trước đó không bao giờ key) và trả key cho cửa sổ cũ / cửa sổ chính **trước** khi chạy việc kèm theo. Cửa sổ hub cũng nhận key trong lúc trình bày sheet hub (`FloatingHubWindowManager.setSheetPresented`) để ô nhập / bảng chia sẻ / trình duyệt mở từ trang con nằm đúng cửa sổ.
- **Hub › Thông báo** là trang con lớn của sheet hub (`FloatingHubSheet.Page.notifications`): `NotificationInboxView` + `.modelContainer`, tiêu đề giữa + nút ‹ khi nằm trong sheet. Chạm một truyện ⇒ sheet đóng rồi mở Reader (`openInboxBook`). Bỏ sheet UIKit riêng `presentInbox` / `openReader` / delegate vuốt-để-đóng. "Mở thẳng khi chỉ có 1 tác vụ" lúc 0 tác vụ ⇒ sheet mở ở trang Thông báo.
- **Hub › Kiểm tra nguồn** (một lượt, hoặc chọn một trong hai lượt) là trang con lớn (`.sourceCheck`): màn kiểm tra gắn vào lượt đang thu nhỏ dựng qua `MinimizedSourceCheckCoordinator.embeddedPage` / `embeddedScreen`, tiêu đề giữa; nút ‹ thay ⌄ (`SourceCheckHeaderButtons` thôi vẽ ⌄ trong trang con) ⇒ `screenDidClose` rồi về trang chính; vuốt đóng sheet khi đang ở trang này cũng thu nhỏ lượt (`FloatingHubSheetState.didDismiss`). Lượt vẫn chạy nền như trước.
- `CLAUDE.md` / `AGENTS.md` + `rules.md` (hub (b), (f), luật 25, cửa sổ sheet phủ): luật mới về trang con và nhận key.
- **Kiểm chứng:**
  - Đọc code. `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 lỗi mới**.
  - **Chưa build** (máy Windows) — CI sẽ biên dịch. **Chưa thử trên máy.**
  - Cần thử: Kệ › "+" › Từ URL ⇒ sheet lớn lên, bàn phím hiện, gõ / dán link, chọn tiện ích ⇒ mở Chi tiết; ‹ về ba dòng. Hub › Thông báo ⇒ trang lớn, ‹ về, chạm truyện ⇒ mở Reader, ngăn kéo … của trang vẫn chạy. Hub › Kiểm tra nguồn khi đang có lượt chạy ⇒ trang lớn theo dõi tiến độ, ‹ về thì dòng hub vẫn "đang chạy", vuốt đóng sheet cũng vậy, Dừng vẫn dừng; mở link lỗi / chia sẻ báo cáo từ trang này hiện trên sheet.

## [1.3.871] - 2026-11-11

### feat: mỗi viên thuốc nổi có độ trong suốt, độ đục và độ nhô riêng, nhô tối thiểu còn bán nguyệt

Anh Bửu: "thêm config độ nhô ra các loại viên thuốc", "làm độ trong suốt riêng luôn", "độ đục riêng luôn", "mỗi viên thuốc có độ trong suốt và đục riêng, nhấp nháy cũng theo trong suốt và đục. Cho độ rộng tối thiểu còn hình bán nguyệt" (đã duyệt mockup kéo thử + plan).

- **Cài đặt riêng từng viên** (mới, `Views/Common/GlassChrome/EdgePillSettings.swift`): đĩa nghe, hub, nút trình duyệt thu nhỏ — mỗi viên ba khoá `edgePill<Disc|Hub|Browser><Transparency|Frost|Width>` (không dấu chấm): độ trong suốt (mặc định 90%), độ đục (6 nấc `GlassFrostLevel`, mặc định không nhoè), độ nhô (đĩa 26–84 pt mặc định 68; hub / trình duyệt 18–50 pt mặc định 38; bước 2; tối thiểu = nửa chiều cao ⇒ bán nguyệt). Độc lập với "Nút nổi" (nút "+", tai nghe Reader giữ nguyên). Ai đã chỉnh "Nút nổi" khác mặc định thì viên thuốc về mặc định tới khi chỉnh ở mục mới.
- **Cài đặt › Chung › Giao diện › Viên thuốc nổi** (`EdgePillSettingsSection`, ngay dưới "Nút nổi"): thanh phân đoạn Đĩa nghe / Hub / Trình duyệt, ba thanh kéo của viên đang chọn, "Đặt lại <viên>", công tắc "Xem thử nháy đỏ" và ô xem trước vẽ cả ba viên.
- **Hình** `EdgePillShape`: vẽ tay bằng cung tiếp tuyến, bán kính = nửa chiều cao ⇒ đúng tới bán nguyệt (bỏ `UnevenRoundedRectangle` và hai hằng `largeSize` / `smallSize`; `contentInset(height:content:)`, `contentPadding(for:)`). Bìa / icon gắn bằng `overlay` đồng tâm đầu bo ⇒ viên hẹp thì lọt ra ngoài mép, không đẩy khung kính.
- **Kính + độ mờ**: `FloatingGlassBackground(shape:pill:)` và `.floatingIconTransparency(pill:)` đọc khoá của viên; `MediaDiscFaceButton`, `FloatingHubButton`, `VisibleBrowserReopenButton` dùng cài đặt riêng của mình.
- **Nháy đỏ theo trong suốt + đục**: màu nháy có alpha `1 − trong suốt` của viên, nằm trên lớp kính (độ đục) — hub (`FloatingHubPulseView`: alpha của màu trong `CABasicAnimation`, đổi alpha ⇒ gắn lại cùng pha; layer nháy cắt bằng mặt nạ `EdgePillShape` thay `cornerRadius`) và nút trình duyệt. Không đổi opacity của view. Số tab của nút trình duyệt vẫn rõ.
- **Đổi ngay khi kéo**: độ nhô đọc lúc chạy (`EdgePillSettings.size(of:)`); container đĩa / hub / trình duyệt nghe `UserDefaults.didChangeNotification` ⇒ tính lại khung (đang kéo bằng tay thì để lượt thả tự đặt).
- `CLAUDE.md` / `AGENTS.md` + `rules.md` (hub (a): luật mới thay "nền nháy giữ rõ"; sửa câu cũ "sheet hub mở thì nút đã giấu" — từ 1.3.866 nút vẫn hiện).
- **Kiểm chứng:**
  - Đọc code. `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 lỗi mới**.
  - **Chưa build** (máy Windows) — CI sẽ biên dịch. **Chưa thử trên máy.**
  - Cần thử: Giao diện › Viên thuốc nổi, kéo từng thanh của từng viên ⇒ viên thật (đang hiện) và ô xem trước đổi ngay; độ nhô nhỏ nhất ⇒ bán nguyệt, bìa / icon ló nửa; kéo / thả viên vẫn bám mép đúng; hub đang nháy ⇒ đỏ mờ theo trong suốt, thấy nhoè khi tăng độ đục; "Đặt lại" chỉ đặt lại viên đang chọn.

## [1.3.870] - 2026-11-11

### feat: nút + của Kệ sách mở sheet Nhập truyện kiểu hub, Từ URL thành sheet riêng

Anh Bửu: "sửa sheet nút + của kệ cũng giống hub luôn, hiện tại chưa giống" (đã duyệt mockup + plan).

- **Sheet "Nhập truyện" kiểu hub** (`ShelfView.presentImportSheet`, dùng `.hubStyleActionSheet` của 1.3.869) cho nút "+" nổi tab Kệ sách và hàng "Nhập truyện" của ngăn kéo: ba dòng dạng ô có `›` — Từ URL ("Dán link, chọn nguồn khớp"), Mở trình duyệt ("Trang chủ trình duyệt"), Từ file ("txt, epub, cbz, mp4…"). Nằm trên mọi viên thuốc; chạm dòng ⇒ sheet đóng xong mới làm. Thay danh sách `insetGrouped` cũ (nấc 300 / large).
- **"Từ URL"** ⇒ sheet **"Nhập từ URL"** riêng ở cửa sổ chính (`ShelfImportSheet` giờ chỉ bọc `ShelfImportURLStep`, nấc large, tiêu đề trái) — cửa sổ sheet phủ không bao giờ key nên không đặt ô nhập chữ ở đó. Dò ra tiện ích / mở link trong trình duyệt vẫn qua `queuedImportChoice` + `onDismiss` như cũ. Bỏ lựa chọn `pickFile` (Từ file chạy thẳng từ sheet kiểu hub).
- `CLAUDE.md` / `AGENTS.md`: luật sheet trên viên thuốc ghi thêm sheet của Kệ. `rules.md` (mục hub + luật 25): thêm cửa sổ `OverlaySheetWindow` (`alert - 1.6`) và sửa câu cũ "`alert - 3` không còn cửa sổ nào dùng" (nút trình duyệt thu nhỏ vẫn ở level này).
- **Kiểm chứng:**
  - Đọc code. `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 lỗi mới**.
  - **Chưa build** (máy Windows) — CI sẽ biên dịch. **Chưa thử trên máy.**
  - Cần thử: tab Kệ sách ⇒ "+" ⇒ sheet ba dòng nằm trên đĩa nghe / hub; Từ URL ⇒ sheet "Nhập từ URL" lên, gõ được (bàn phím hiện), dán link ⇒ mở Chi tiết; Mở trình duyệt ⇒ trang chủ trình duyệt; Từ file ⇒ bộ chọn file; ngăn kéo … › Nhập truyện ⇒ cùng sheet.

## [1.3.869] - 2026-11-11

### feat: nút + của Chi tiết truyện mở sheet kiểu hub thay cho cụm pill xổ lên

Anh Bửu: "để cho nút + ở chi tiết sẽ mở ra sheet như sheet hub vậy" (đã duyệt mockup + plan).

- **Sheet hành động kiểu hub** dùng chung (mới, `Views/Common/HubStyleSheet/`): `HubStyleActionSheetContent` (tiêu đề + chú thích phải + các dòng: icon, tên, dòng phụ, màu icon, `›`, việc làm), `HubStyleActionSheet` (khuôn sheet hub: nền kính ngăn kéo, bo 16, cao vừa nội dung, vuốt xuống để đóng, nền tối), `HubStyleActionSheetRow` (khuôn dòng của sheet hub: ô bo góc `hubSheetPanelRow`, cao 56) và `.hubStyleActionSheet(_:)` — trình bày qua `OverlaySheetPresenter` ⇒ nằm **trên** mọi viên thuốc; chạm dòng ⇒ sheet đóng xong mới làm việc; không trình bày được ⇒ lùi về sheet thường của màn (log `[HubStyleSheet]`).
- **Chi tiết truyện** (`BookDetailFloatingActions`): nút "+" là nút tròn thường, chạm ⇒ sheet: dòng đầu tên truyện (bản đang hiện) + "Ch. N/tổng" (truyện chưa lưu ⇒ "N chương"); Đọc ngay / Đọc tiếp (Đọc tiếp kèm tên chương sẽ mở, cùng luật tên chương của tab Mục lục), Thêm vào kệ / Đã ở kệ (icon xanh, "Chạm để bỏ khỏi kệ"), Tải, Xuất, "Về trang gốc" dưới cùng khi trang có Home. Thuộc tính `floatingActionButton` chuyển sang `BookDetailView+FloatingActions` (file legacy ngắn đi 23 dòng).
- `OverlaySheetPresenter.dismiss(then:)`: chạm dòng thứ hai lúc sheet đang trượt xuống ⇒ bỏ qua (trước đó việc chạy luôn ⇒ hai lần). Việc kèm theo khai `@MainActor () -> Void` (cùng kiểu `action` của dòng — tránh lỗi đổi hàm mất actor khi biên dịch); `HubStyleActionSheetModifier` gắn `@MainActor`.
- `CLAUDE.md` / `AGENTS.md`: mục Nút Home nổi + luật sheet trên viên thuốc.
- **Kiểm chứng:**
  - Đọc code. `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 lỗi mới**.
  - **Chưa build** (máy Windows) — CI sẽ biên dịch. **Chưa thử trên máy.**
  - Cần thử: Chi tiết truyện đã lưu ⇒ "+" ⇒ sheet có tên + "Ch. N/tổng", "Đọc tiếp" có tên chương; chạm từng dòng (đọc, bỏ / thêm kệ, tải, xuất, về trang gốc) ⇒ sheet đóng rồi làm đúng việc; đĩa nghe / hub vẫn thấy dưới lớp tối của sheet; truyện chưa lưu ⇒ "N chương", "Đọc ngay"; Chi tiết mở trong Reader ⇒ không có dòng "Về trang gốc".

## [1.3.868] - 2026-11-11

### feat: sheet đang đọc chương này nằm trên mọi viên thuốc thay vì ẩn đĩa nghe

Anh Bửu: "Sheet 'đang đọc chương này' hiển thị đừng có ẩn nửa viên thuốc, cho nó dưới sheet thôi, cho luôn nửa viên thuốc hub ở dưới sheet luôn… mọi sheet mở ra từ viên thuốc đều không ẩn các viên thuốc mà chỉ hiển thị cao hơn viên thuốc thôi, tránh trường hợp mở sheet từ viên thuốc rồi lại mở sheet mới khác từ viên thuốc đè lên" (đã duyệt mockup + plan).

- **Cửa sổ sheet phủ** (mới, `Views/Common/OverlaySheet/`): `OverlaySheetPresenter` + `OverlaySheetWindow` (level `alert − 1.6`: trên đĩa nghe `− 1.75`, hub `− 2` / `− 1.7`, nút trình duyệt `− 3`; dưới ngăn kéo `…` `− 1.5` và toast) + `OverlaySheetHost` (view 1×1 giữ `.sheet`, khuôn `MediaDiscSheetHost`). Cửa sổ chỉ hiện lúc có sheet, không bao giờ key, hit-test chỉ nhận chạm khi đang trình bày (luật 25); `onDismiss` là đường đóng chung (luật 26); `dismiss(then:)` đóng sheet **xong** mới chạy việc kèm theo. Sheet của cửa sổ chính luôn nằm dưới các cửa sổ viên thuốc nên đây là cách duy nhất để một sheet che được chúng.
- **Sheet "đang đọc chương này" của Reader** trình bày qua cửa sổ này (vỏ `ReaderTTSSameChapterPromptHost`: tự giữ chiều cao + tự đọc "đang phát" qua `TTSWidgetStateReader`) ⇒ đĩa nghe, hub, nút trình duyệt, cửa sổ phim nhỏ nằm dưới lớp mờ của sheet, **không bị ẩn**, không bấm được để mở chồng sheet. Bỏ neo `.blocker` của sheet này. Không trình bày được (đang có sheet phủ khác / chưa có scene) ⇒ lùi về sheet thường của Reader như cũ.
- Sheet của chính đĩa nghe và sheet hub / màn Thông báo vốn đã nằm trên mọi viên thuốc (cửa sổ của chúng) — giữ nguyên.
- `CLAUDE.md` / `AGENTS.md`: đoạn đĩa nghe thêm luật "sheet nằm trên mọi viên thuốc".
- **Kiểm chứng:**
  - Đọc code. `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 lỗi mới**.
  - **Chưa build** (máy Windows) — CI sẽ biên dịch. **Chưa thử trên máy.**
  - Cần thử: đang nghe truyện, bấm tai nghe trúng chương đang đọc ⇒ sheet hiện, đĩa nghe + hub vẫn thấy mờ dưới lớp tối; chọn "Đọc tiếp chỗ đang đọc" / "Đọc từ đoạn đang xem" / "Đọc lại từ đầu chương" ⇒ Reader làm đúng như cũ; vuốt sheet xuống ⇒ không làm gì, đĩa vẫn ở đó.

## [1.3.867] - 2026-11-11

### feat: viên thuốc nổi đứng trong vùng cố định, luôn tránh header và thanh tab để không nhảy khi đổi màn

Anh Bửu: "để cho viên thuốc tự tránh header và thanh tab dù có hay không luôn, tránh nó chạy lên chạy xuống" (đã duyệt mockup + plan). Áp cho cả ba viên: đĩa nghe, nút hub, nút trình duyệt thu nhỏ.

- `EdgePillZone` (mới, `Views/Common/GlassChrome/`): vùng đứng cố định — mép trên ≥ vùng an toàn trên + 52 (header 44 + 8), mép dưới ≤ vùng an toàn đáy − 76 (= khe 12 + nút "+" 52 + khe 12). iPhone 15: 111…742 pt ⇒ luôn trên thanh tab (769), nút "+" (754), thanh dưới trình duyệt (766), nút tai nghe Reader (750) — **kể cả màn không có chúng**, nên đổi tab / đẩy trang / mở sheet không làm viên thuốc lên xuống. Chỗ người dùng kéo tới vẫn lưu nguyên; vùng chỉ kẹp lúc vẽ và lúc thả.
- **Đĩa nghe** (`MediaDiscPlacement`): dải dọc lấy từ `EdgePillZone`; chỉ neo / cửa sổ phim nhỏ **lấn vào vùng** (mép trên cao hơn đáy vùng — cụm pill của menu "+" đang xổ ở màn danh sách có Home, cửa sổ phim nhỏ kéo lên) chồng cột mới tạm đẩy đĩa lên. Nút "+", Home, tai nghe, thanh tab, thanh dưới không còn đẩy đĩa (trước đây đẩy theo từng màn ⇒ nhảy).
- **Nút hub, nút trình duyệt**: lề trên / dưới đổi từ 12 pt quanh vùng an toàn sang `EdgePillZone` (kẹp lúc vẽ, lúc giữ chỗ với widget khác, lúc thả tay) ⇒ không còn kéo lên được header hay xuống đè thanh tab / thanh dưới. Bỏ hằng `verticalMargin`.
- `CLAUDE.md` / `AGENTS.md`: câu chỗ đứng của đĩa, câu thanh tab 4 ô, câu "Cùng khuôn" của hub / trình duyệt.
- **Kiểm chứng:**
  - Đọc code. `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 lỗi mới**.
  - **Chưa build** (máy Windows) — CI sẽ biên dịch. **Chưa thử trên máy.**
  - Cần thử: đang nghe, đi qua lại trang gốc Kệ (thanh tab + "+") ⇄ trang đẩy vào (không thanh tab) ⇄ Reader ⇒ đĩa đứng yên một chỗ. Kéo hub / nút trình duyệt lên sát đỉnh ⇒ dừng dưới header; kéo xuống đáy ⇒ dừng trên thanh tab. Ở màn danh sách có "+" kèm Home, bấm "+" xổ menu ⇒ đĩa mép phải né lên, đóng menu ⇒ về chỗ.

## [1.3.866] - 2026-11-11

### feat: mở sheet hub không ẩn nút hub, giống đĩa nghe mở sheet nghe

Anh Bửu: "Khi mở sheet mở rộng từ widget hub thì đừng ẩn các widget khác (làm giống như widget đĩa mở sheet nghe nhạc/nghe truyện mini)" (đã duyệt).

- Kiểm lúc sheet hub / màn Thông báo mở (sau 1.3.865): nửa viên đĩa nghe, nút trình duyệt thu nhỏ, cửa sổ phim nhỏ đều vẫn hiện; **chỉ nút hub** bị giấu (`setSheetPresented(true)` đặt `widgetContainerView.isHidden = true`, `refreshState` giữ giấu suốt lúc sheet mở).
- `FloatingHubWindowManager`: thôi giấu nút khi sheet mở — nút nằm yên dưới sheet (sheet trình bày trong cùng cửa sổ hub, đè lên nút; lớp mờ của sheet chặn chạm), y như đĩa nghe dưới sheet điều khiển nhanh của nó. Vẫn giữ: phim toàn màn mà sheet còn mở ⇒ giữ cửa sổ, chỉ giấu nút (`hideWidget()` sẽ cuốn mất sheet). Level cửa sổ hub lúc trình bày sheet giữ như 1.3.865 (`alert − 1.7`, trên cửa sổ đĩa).
- `rules.md` luật hub (b), `CLAUDE.md` / `AGENTS.md` đoạn đĩa nghe: ghi nút hub không ẩn lúc sheet hub mở.
- **Kiểm chứng:**
  - Đọc code. `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 lỗi mới**.
  - **Chưa build** (máy Windows) — CI sẽ biên dịch. **Chưa thử trên máy.**
  - Cần thử: chạm hub ⇒ sheet hub mở, nút hub (và nửa viên, nút trình duyệt nếu có) vẫn thấy mờ phía sau lớp tối; chạm vùng tối ⇒ sheet đóng, không mở lại hub; chạm Thông báo ⇒ màn Thông báo, đóng ⇒ nút hub vẫn đúng chỗ.

## [1.3.865] - 2026-11-11

### feat: bỏ ô đĩa giữa thanh tab, nửa viên đĩa nghe hiện ở mọi màn và sheet

Anh Bửu: "Bỏ luôn tab thứ 5 hiển thị đĩa đi, mọi màn hình, sheet đều hiển thị viên thuốc cho tôi" (đã duyệt plan; sheet "đang đọc chương này" của Reader anh chọn giữ ẩn đĩa như cũ).

- **Thanh tab 4 ô** (`MainTabBar`): Kệ Sách · Khám Phá · Tiện Ích · Cài Đặt. Xoá `MediaDiscTabBarSlot`, `MediaDiscIdleFace` (đĩa xám), kiểu `.tabBar` của `MediaDiscFaceButton` (nay chỉ còn mặt nửa viên, `MediaDiscFaceButton()`), vai neo `.hostsDisc`.
- **Trang gốc các tab có nửa viên**: thanh tab là neo `.bar` (`MainTabBarModifier`) ⇒ nửa viên đè lên thanh thì tự đứng trên nó 12 pt.
- **Đổi màn ⇒ đĩa đứng yên**: bỏ luật "trang đổi ⇒ thu đĩa tại chỗ, hiện lại sau 0,3 s" (1.3.820, theo `MediaDiscScreenContext.page`). Đang chuyển cảnh vẫn đứng yên; hết chuyển cảnh mà màn mới có neo cần né thì trượt tới chỗ mới. Đĩa đang ẩn (bàn phím, phim…) vẫn chỉ hiện lại khi điều kiện giữ đủ 0,3 s.
- **Sheet hub / màn Thông báo không ẩn đĩa nữa** (thay cách ẩn của 1.3.864): `FloatingHubWindowManager.setSheetPresented` nâng cửa sổ hub từ `alert − 2` lên `alert − 1.7` (trên cửa sổ đĩa `alert − 1.75`) lúc trình bày sheet ⇒ sheet đè lên nửa viên như sheet của chính đĩa; đóng sheet thì hạ về để nút hub nằm dưới sheet điều khiển nhanh của đĩa.
- **Vẫn ẩn đĩa** khi: không có gì đang phát, bàn phím hiện, màn nghe nhạc mở, phim toàn màn / màn xem phim, hộp thoại / bảng chọn / bảng chia sẻ, sheet "đang đọc chương này" của Reader (`ReaderTTSSameChapterSheet`, neo `.blocker`). Mọi sheet khác của cửa sổ chính nằm dưới nửa viên (đĩa có thể che mép hàng của sheet — kéo đi chỗ khác).
- `CLAUDE.md` / `AGENTS.md`: đoạn "Hai chỗ đặt đĩa" ⇒ "Một chỗ đặt đĩa", đoạn đĩa nghe (neo `.bar` ở thanh tab, sheet hub). `rules.md`: level cửa sổ hub, luật widget TTS bỏ "ô giữa thanh tab".
- **Kiểm chứng:**
  - Đọc code + grep chéo `MediaDiscTabBarSlot` / `MediaDiscIdleFace` / `hostsDisc` / `MediaDiscFaceButton(style:` (không còn chỗ gọi). `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 lỗi mới**.
  - **Chưa build** (máy Windows) — CI sẽ biên dịch. **Chưa thử trên máy.**
  - Cần thử:
    1. Thanh tab còn 4 ô, chia đều. Đang nghe ⇒ ở trang gốc Kệ Sách có nửa viên, đứng trên thanh tab (và trên nút "+" nếu có).
    2. Đẩy trang / mở Reader / quay lại ⇒ nửa viên không thu lại rồi hiện lại; chỉ trượt khi phải né nút.
    3. Chạm hub ⇒ sheet hub đè lên nửa viên, bấm được mọi dòng; đóng sheet ⇒ nửa viên vẫn ở đó.
    4. Mở một sheet bất kỳ (Cài đặt Reader, mục lục…) ⇒ nửa viên vẫn hiện trên sheet.
    5. Bấm tai nghe trúng chương đang đọc ⇒ sheet "đang đọc chương này" hiện, nửa viên ẩn như cũ.

## [1.3.864] - 2026-11-11

### fix: ẩn đĩa nghe khi sheet hub hoặc màn Thông báo của hub đang mở

Rà lại đợt nút nổi nửa viên (1.3.858–863) thấy: cửa sổ hub ở `alert − 2`, **thấp hơn** cửa sổ đĩa nghe (`alert − 1.75`). Sheet hub (1.3.862) và màn Thông báo trình bày từ cửa sổ hub nên nằm **dưới** nửa viên đĩa nghe — đĩa đè lên mấy dòng cuối của sheet và cướp chạm (đúng chỗ ⏸ / ✕ của dòng Video khi đĩa ở chỗ mặc định). `MediaDiscPlacement` chỉ xét tầng trên cùng của cửa sổ **chính** nên không thấy sheet đó. Màn Thông báo vốn đã bị vậy; sheet hub làm nó xảy ra mỗi lần chạm hub.

- `MediaDiscWindowManager.isDiscAllowed` thêm điều kiện `!FloatingHubWindowManager.shared.isSheetPresented` ⇒ sheet hub / màn Thông báo mở thì đĩa thu lại, đóng thì hiện lại (luồng hiện chậm 0,3 s như cũ).
- `FloatingHubWindowManager.setSheetPresented` gọi `MediaDiscWindowManager.shared.refreshState()` ⇒ đĩa thu ngay, không chờ lượt hỏi 0,4 s.
- Ô đĩa ở giữa thanh tab (cửa sổ chính) không đổi — nó nằm dưới cửa sổ hub nên sheet tự che.
- `CLAUDE.md` / `AGENTS.md`: thêm điều kiện ẩn này vào đoạn đĩa nghe.
- **Kiểm chứng:**
  - Đọc code. `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 lỗi mới**.
  - **Chưa build** (máy Windows). **Chưa thử trên máy.**
  - Cần thử: đang nghe nhạc (nửa viên ở mép phải) ⇒ chạm hub ⇒ nửa viên thu lại, bấm được ⏸ / ✕ dòng Video; vuốt sheet xuống ⇒ nửa viên hiện lại. Tương tự với màn Thông báo.
