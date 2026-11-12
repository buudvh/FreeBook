# CHANGELOG - Nhật ký Thay đổi CodeGraph Tàng Công Các

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **Tàng Công Các**.

## [1.3.856] - 2026-11-12

### perf: Turbo đọc truyện chạy lõi hiệu năng (userInitiated), nhanh gấp đôi và mát hơn

Anh Bửu đo Turbo ở màn thử › Đọc liên tục (1.3.855, iPhone 11, 2 luồng, cùng văn bản, mỗi lượt ~3 phút), đúng điều kiện của plan đã duyệt (bước 2 chỉ làm khi RTF ≲ 0,55):

| Giọng · QoS | RTF | CPU-s / giây tiếng | CPU-s / 1.000 ký tự | Nhiệt |
|---|---|---|---|---|
| Minh Quân Pro · utility | 0,71 | 1,35 | 71,8 | "nóng" từ ~2:30 |
| Minh Quân Pro · userInitiated | **0,35** | **0,70** | 37,0 | vẫn "ấm" |
| Mai Anh · utility | 0,73 | 1,36 | 82,6 | "nóng" từ ~2:00, có đoạn vọt RTF 1,17 |
| Mai Anh · userInitiated | **0,36** | **0,71** | 42,9 | vẫn "ấm", đoạn chậm nhất 0,41 |

Giống Nano (1.3.855): lõi hiệu năng nhanh gấp đôi và tốn ít CPU hơn ~48% (lõi tiết kiệm phải chạy gấp đôi thời gian). Âm thanh không đổi — chỉ đổi lõi chạy.

- `VieNeuTurboTTSService.readerQoS = .userInitiated`, truyền vào `VieNeuTurboRuntime.synthesize(…, qos:)` ⇒ cả luồng ggml của lượt chạy lõi hiệu năng. Nạp model / dựng session / nhả vẫn ở hàng đợi `.utility`.
- `realtimeSpeedLimit` 1,4 → **2,0** (RTF phải dưới 0,5; đo được 0,36, chậm nhất 0,41 ⇒ chừa khoảng cho máy nóng khi nghe lâu và giọng chưa đo là Adam bựa). Màn Cài đặt TTS cảnh báo khi tốc độ phát vượt mức này.
- Dòng log mỗi đoạn `[VieNeuTurbo] Đoạn:` thêm `qos=` (QoS **đo được**) để kiểm khi khoá màn / chạy nền iOS có giữ lõi hiệu năng không.
- Màn thử: QoS mặc định của lượt Nano và Turbo thành `userInitiated` (= trình đọc), vẫn chọn `utility` để so; "Đọc thử một lần" ghi QoS đo được thay vì chữ "utility" cố định (bỏ `VieNeuTurboRuntime.qosName`); sửa các chú thích còn nói trình đọc chạy utility.
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Mới đo ở màn thử, chưa thử trong trình đọc khi khoá màn.

## [1.3.855] - 2026-11-11

### perf: Nano đọc truyện chạy lõi hiệu năng (userInitiated), nhanh gấp đôi và tốn ít CPU hơn

Anh Bửu đo P0 trên iPhone 11 (màn thử › Đọc liên tục › Nano, 2 luồng, giọng Minh Quân, cùng văn bản, 1.3.853) rồi duyệt *"làm Nano trước đi"*:

| | userInitiated | utility (cũ) |
|---|---|---|
| RTF | **0,28** | 0,55 |
| CPU-s / giây tiếng | **0,56** | 0,88 |
| CPU-s / 1.000 ký tự | **30,9** | 48,6 |
| Nhiệt | 3:45 vẫn "ấm" | "nóng" ở phút 4 |

Lõi hiệu năng vừa nhanh gấp đôi vừa tốn ít CPU hơn ~36% và mát hơn (mỗi cấu hình đo một lượt). Âm thanh giống hệt từng bit — chỉ đổi lõi chạy.

- `VieNeuTTSService.readerPriority = .userInitiated`: `prepare(voice:)` dựng session ORT ở mức này (luồng phụ của pool sinh ra lúc dựng); trước đó `.utility`.
- Lượt tổng hợp chạy ORT trong `Task.detached(priority:)` ở mức cố định đó, thay vì mức của tác vụ nào xếp hàng trước trong `PiperSynthesisCoordinator` (phần lớn `.utility`). Lệnh huỷ được chuyển xuống task con (`withTaskCancellationHandler`) vì engine kiểm `Task.checkCancellation()` giữa các chunk / bước Euler.
- Màn thử vẫn đo A/B được: `setLabSynthesisPriority` ghi đè mức tổng hợp trong lúc đo, `endNanoOverride` trả về. Dòng `[VieNeuPerf]` (1.3.852) có `qos=` / `sessionQos=` để kiểm trên máy.
- Turbo **chưa đổi** (vẫn `.utility`), chờ đo ở màn thử (1.3.854).
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Chưa thử máy.

## [1.3.854] - 2026-11-11

### feat: màn thử Turbo chọn QoS (utility / userInitiated) để đo lõi hiệu năng

Anh Bửu nghe Turbo trên truyện thật ở tốc độ phát **1,4×**: Minh Quân Pro hụt ít, Mai Anh và Adam bựa hụt nhiều. Ở 1,4× cần RTF < 0,714, Turbo đang ~0,70 (QoS utility) ⇒ sát mép. Anh duyệt plan: đo QoS cao hơn ở màn thử trước, đạt RTF ≲ 0,55 mới đưa vào trình đọc. Lượt này chỉ là phần đo; **trình đọc không đổi** (vẫn utility).

- `VieNeuTurboRuntime.synthesize(…, qos:)` (mặc định `.utility`): mỗi lượt chạy trên hàng đợi tuần tự với QoS riêng (`async(qos:flags: .enforceQoS)`). Không OpenMP ⇒ ggml tạo luồng tính mới mỗi lượt từ chính luồng gọi, luồng mới mang QoS của nó ⇒ nâng QoS một lượt là cả lượt chạy ở mức đó. `Output.qosName` = QoS **đo được** (`qos_class_self()`).
- Màn thử › Đọc liên tục (Turbo): Picker QoS utility / userInitiated (`VieNeuTurboLab.turboQoS`, chỉ cho lượt đo); "Đọc thử một lần" cũng theo lựa chọn này. Mỗi dòng đoạn ghi "QoS tổng hợp …" đo được; mô tả engine ghi QoS đã chọn; chú thích "Nghe ở 1,4× cần RTF dưới 0,71".
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Chưa thử máy.

## [1.3.853] - 2026-11-11

### fix: xoá model Nano không làm hỏng Turbo, màn thử hết đua khi đổi Nano/Turbo

Rà soát độc lập (agent) cả đợt 1.3.849–1.3.852 trước khi build lần đầu: không thấy lỗi biên dịch chắc chắn, có 4 lỗi logic — sửa cả 4.

- **Xoá model Nano xoá luôn `sea_g2p.bin`** — bộ phiên âm dùng chung với Turbo ⇒ model hiệu lực lật về Nano (vừa bị xoá), trình đọc đang chọn Turbo hỏng ngầm, mỗi đoạn lỗi thiếu model. `VieNeuModelStore.deleteAll` nay giữ `sea_g2p.bin` khi máy còn model Turbo.
- **Đua ở màn thử**: lượt trả engine Nano về cấu hình người dùng (`endNanoOverride`) chạy Task không giữ lại, có thể chặn vài giây rồi nhả Turbo / xoá ghi đè luồng chen vào lượt "Đọc thử" hay "Đọc liên tục" vừa bấm. Nay giữ ở `nanoRestoreTask`, hai lượt đó chờ nó xong mới chạy.
- **Số đo Nano cộng trùng ở đoạn im lặng**: đường im lặng của `VieNeuTTSService` không chạy engine nhưng để nguyên `lastTiming` của đoạn trước ⇒ màn thử cộng lại lần nữa. Nay xoá `lastTiming` trên đường đó.
- **"Xoá model" Turbo ở màn thử** đưa trình đọc về `"vieneu"` cả khi máy chưa có model Nano ⇒ trình đọc trỏ vào engine thiếu model. Nay chưa có Nano thì về Siri (`"system"`, mặc định của app).
- Bỏ cảnh báo kết quả không dùng (`_ = await Task.detached { … }.value`).
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Lượt CI kế tiếp là lần biên dịch đầu của cả đợt; chưa thử máy.

## [1.3.852] - 2026-11-11

### feat: Nano đo riêng vòng Euler, codec, text; màn thử chọn luồng/QoS cho Nano và chia sẻ file kết quả

Anh Bửu duyệt P0 của báo cáo tối ưu Nano (`Docs/Reports/2026-11-11-vieneu-nano-toi-uu.md`): *"làm trước P0 đi"* + *"cho sửa thành share file luôn, copy gửi cực quá"*. Không đổi cách tổng hợp — tiếng ra giữ nguyên.

- **Sửa phép đo engine Nano**: `runChunk` chốt `vectorMs` **sau** `codec_decoder` ⇒ số "vòng Euler 98%" thật ra gồm cả codec (đo PC: Euler ~81%, codec ~17%). Nay `StageClock` (`VieNeuTTSEngine+Timing`, mới) bấm giờ nối tiếp ba giai đoạn text (text_encoder + duration + nhiễu) / vòng Euler / codec, mỗi giai đoạn cả thời gian tường lẫn CPU-time. `Timing` có `text` / `vector` / `codec`; `vectorMs` chỉ còn vòng Euler, `otherMs` = text + codec (màn Nghe thử giữ "vector | khác"). `[VieNeuPerf]` thêm `codecMs= textMs= cpuSplit=text/vector/codec qos= sessionQos=` (QoS **đo được** của luồng tổng hợp và của luồng dựng session — `Timing.synthesisQoS`, `VieNeuONNXRuntime.buildQoS`); dòng "Nạp xong engine" thêm `qos=`. `VieNeuTTSService.lastTiming` cho màn thử đọc.
- **Ghi đè số luồng cho màn thử** (`VieNeuTTSEngine+Reload`): `setLabThreadOverride` (không ghi vào cài đặt) buộc dựng lại session; `VieNeuTTSService.prepare(voice:priority:)` (hàm riêng — `LocalTTSEngine` đòi đúng `prepare(voice:)`) dựng ở QoS chọn vì luồng phụ của pool ORT sinh ra lúc dựng session. Ghi đè chạy ở luồng nền (khoá tổng hợp có thể đang giữ bởi đoạn chạy dở).
- **Màn thử VieNeu Turbo** — lượt Nano của "Đọc liên tục" (`VieNeuTurboLab+Nano`, tách khỏi `+Run`): chọn **số luồng ORT** (2/3/4) và **QoS** (utility / userInitiated), dựng lại session ở đúng mức đó rồi tổng hợp ở cùng mức; dừng / rời màn / nạp lỗi ⇒ bỏ ghi đè rồi: trình đọc đang ở Nano thì dựng lại ở `.utility` như lúc app nạp engine, đang ở Turbo thì **nhả** Nano (`releaseEngineRuntime`) — hai model không cùng nằm trong RAM. Đoạn nhả Turbo của `prepare` nằm trong `prepare(voice:priority:)` nên đường của màn thử cũng nhả. Mỗi đoạn ghi "Euler / codec / text" (giây tường + CPU-s) và "QoS tổng hợp X · session Y" đo được, tổng kết thêm **phân rã** theo thời gian và theo CPU. QoS tới được luồng tổng hợp vì `PiperSynthesisCoordinator` chạy việc trong `Task` lồng — kế thừa priority của task gọi; dòng QoS đo được là bằng chứng trên máy.
- **Chia sẻ file thay sao chép**: hai nút "Sao chép số đo" / "Sao chép kết quả đọc liên tục" ⇒ **"Chia sẻ file … (.txt)"** (`VieNeuTurboReportFile`, dựng lúc bấm như `ThermalCSVExport`): đầu file có bản app, mã máy, giờ, nhiệt; file đọc liên tục có tổng kết + mọi phút + **mọi** đoạn (màn chỉ hiện 40 đoạn gần nhất).
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows), chưa thử máy.

## [1.3.851] - 2026-11-11

### fix: màn thử Turbo dừng trình đọc đang dùng Turbo trước khi xoá model

- Màn thử Turbo và trình đọc dùng chung runtime: "Xoá model" lúc trình đọc đang đọc bằng Turbo nay dừng TTS trước (như khi màn thử giành âm thanh), thay vì nhả runtime + xoá file dưới chân trình đọc đang phát.

## [1.3.850] - 2026-11-11

### feat: VieNeu Turbo thành trình đọc cạnh Nano trong Cài đặt TTS

Phần giao diện của đợt B, đúng mockup anh Bửu đã duyệt.

- Picker "Trình đọc" có "VieNeu-TTS v3 Turbo (Offline)" ngay dưới Nano (dòng phụ "Hay hơn Nano, tốn CPU khoảng 1,5 lần"), chỉ hiện khi đã tải model Turbo. Picker dùng binding riêng: hai mục VieNeu cùng ánh xạ về `tool = "vieneu"` + model; ghi model trước rồi gán `tool` ⇒ đổi model đi đúng luồng đổi engine (nạp tham số + giọng của model, bỏ phần đệm, nạp sẵn engine).
- Chưa tải Turbo ⇒ hàng "Tải model VieNeu Turbo (188 MB)" dưới Picker, bấm là tải tại chỗ (dùng lượt tải của màn thử Turbo): "Đang tải model VieNeu Turbo" + "74 / 188 MB" + thanh tiến độ; lỗi hiện dưới nút. Trong lúc tải trình đọc đang chọn vẫn đọc bình thường.
- "Giọng đọc VieNeu" khi chọn Turbo: 25 giọng của manifest, nhóm "Tuyển chọn" (10 giọng ⭐, bỏ ⭐) rồi "Giọng khác"; mỗi mục tên + dòng phụ "Nam · Bắc · tự nhiên" (+ "mặc định"). Chọn giọng chưa có file ⇒ tải ngay vài KB.
- "Quản lý riêng của trình đọc" khi chọn Turbo: hàng "Tổng hợp Turbo — 2 luồng, cố định" thay Tiết kiệm pin / Chế độ tạo audio / Số luồng / spin ORT; giữ hai công tắc tiếng Nhật + từ điển tiếng Nhật; ẩn "Giọng của tôi", thay bằng chú thích về 2 lõi hiệu năng, máy ấm và giọng nhân bản chỉ dùng với Nano.
- "Cấu hình giọng nói" khi chọn Turbo: ẩn "Tốc độ tổng hợp (VieNeu)", thay chú thích "Turbo luôn tổng hợp ở tốc độ gốc…"; Tốc độ > 1,4× ⇒ cảnh báo cam "Turbo theo kịp tới khoảng 1,4×. Ở 1,6× có thể hụt tiếng…" (ngưỡng `VieNeuTurboTTSService.realtimeSpeedLimit`, từ RTF ~0,70 đo trên máy). "Đặt lại" không đụng tốc độ tổng hợp của Nano khi đang chọn Turbo.
- "Tải trước dữ liệu" giữ nguyên, dùng chung cho hai model. Dòng "Nghe truyện (TTS)" ở Cài đặt ghi "VieNeu Turbo" khi đang chọn Turbo.

## [1.3.849] - 2026-11-11

### feat: engine VieNeu Turbo cho trình đọc truyện (chọn model Nano/Turbo, khoá cache theo model, nhả model không dùng)

Đợt B của Turbo GGUF (anh Bửu duyệt mockup, artifact "VieNeu Turbo trong Cài đặt TTS"). Phần engine; giao diện ở 1.3.850. Viết ở session con, cherry-pick sang `feature/vieneu-turbo-gguf`.

- `tool` vẫn là `"vieneu"` (không thêm chuỗi engine mới); model lưu ở khoá `vieneuModel` qua `VieNeuModelChoice`. Model hiệu lực chỉ là Turbo khi bản build có audio.cpp và máy đủ GGUF + manifest giọng + `sea_g2p.bin`, thiếu thì trình đọc rơi về Nano.
- `VieNeuTurboTTSService` (mới, `LocalTTSEngine`): `TTSManager.localEngine` trả nó khi chọn Turbo. Đi qua `PiperSynthesisCoordinator` như Nano; tiền xử lý bằng `VieNeuTurboTextFrontend` (số/ngày, tiếng Nhật theo cờ VieNeu, sea-g2p); `VieNeuTurboRuntime` CPU 2 luồng cố định; trả WAV mono 48 kHz + khoảng lặng đuôi theo ranh giới (1×) + `pcmDuration` + `synthesisMs`. Không có tốc độ tổng hợp (luôn 1×). Đoạn không đọc được / phiên âm rỗng ⇒ im lặng 48 kHz. Kiểm huỷ trước lượt audio.cpp (không huỷ được giữa chừng). Giọng chưa có file thì tải cặp file vài KB (gộp lượt tải trùng).
- Màn thử giọng Nano, thư viện giọng nhân bản và lượt Nano của màn thử Turbo vẫn gọi thẳng `VieNeuTTSService` ⇒ luôn là Nano.
- Khoá tổng hợp gồm model: `TTSSynthesisIdentity.computeKey` gắn `vieneu.turbo` cho Turbo (Nano giữ `vieneu`, khoá cũ không đổi) ⇒ đổi model không phát lại audio của model kia; `localSynthesisSpeed` trả 1× cho Turbo; `TTSSettingsSnapshot` có `vieneuModel` ⇒ đổi model trong Cài đặt TTS dựng lại đoạn như đổi engine.
- Giọng nhớ riêng theo model: Nano khoá `vieneuVoice`, Turbo khoá `vieneuTurboVoice` (mặc định `minh_quan_pro`, giọng không còn trong manifest ⇒ mặc định).
- Bộ nhớ: Turbo chuẩn bị / tổng hợp ⇒ nhả engine Nano nếu đang nạp (`VieNeuTTSEngine.releaseRuntime`: 4 session ORT + bộ phiên âm); trình đọc về Nano ⇒ nhả model Turbo + bộ phiên âm Turbo. Trình đọc và màn thử Turbo dùng chung `VieNeuTurboRuntime.shared` + `VieNeuTurboTextFrontend.shared` (một model 188 MB trong RAM); rời màn thử không nhả khi trình đọc đang chọn Turbo; "Xoá model" ở màn thử đưa trình đọc về Nano.
- `[VieNeuTurbo] Đoạn:` mỗi đoạn: ms phiên âm / audio.cpp / tổng hợp, giây tiếng, RTF, CPU/tiếng, nhiệt, RAM. Dòng ❌ khi lỗi cấp phát ghi rõ "đang dựng lại session và thử lại đoạn này"; lỗi khác giữ như cũ.
- Màn thử Turbo có thêm số byte đang tải + lỗi tải riêng (cho hàng tải ở Cài đặt TTS).

## [1.3.848] - 2026-11-11

### fix: Turbo GGUF hết lỗi thiếu bộ nhớ khi nạp prompt (vá audio.cpp tái sử dụng bộ nhớ, tự thử lại)

Anh Bửu đo 1.3.847 trên máy: Turbo 2 luồng RTF 0,71, không hụt tiếng, nghe hay hơn Nano — nhưng đoạn thứ 36 lỗi `audiocpp_session_run lỗi: runtime error — failed to allocate VieNeu-TTS talker prefill graph`. Anh duyệt: *"sửa A trước rồi đo lại lần nữa"*.

- **Nguyên nhân** (đọc mã audio.cpp `v0.9.4`, `talker.cpp:1212`): `TalkerPrefillGraph` — bước nạp prompt (phiên âm + mã giọng tham chiếu) qua 12 lớp — gọi `ggml_backend_alloc_ctx_tensors`, tức cấp phát **riêng** cho mọi tensor trung gian của cả 12 lớp (điểm attention S×S, MLP…), không tái sử dụng; graph dựng lại mỗi khi độ dài prompt đổi (gần như mỗi đoạn). Đoạn hỏng chính là đoạn đầu của vòng 2 — vòng 1 vẫn chạy được ⇒ không phải đoạn quá dài mà lúc đó app còn ít bộ nhớ trống.
- **Vá audio.cpp lúc build** (`Scripts/ci/audiocpp_patches/vieneu_prefill_gallocr.py`, gọi từ `build_audiocpp_ios.sh`; sửa theo mốc chuỗi cố định, mốc lệch ⇒ build đỏ): đầu vào + K/V từng lớp + hidden + logits nằm ở context nhỏ riêng cấp phát cố định (kết quả được `ggml_cpy` sang), mọi tensor trung gian còn lại do `ggml_gallocr` cấp phát có tái sử dụng. Phép tính giữ nguyên.
- **Kiểm không đổi tiếng** (`Scripts/ci/audiocpp_parity_macos.sh`, job `parity` của `audiocpp-ios.yml`): build `audiocpp_cli` macOS bản gốc + bản vá, đọc câu ngắn và câu dài ~4 lần bằng greedy (`do_sample=false`, seed 1, tắt babble guard), so mã âm thanh + WAV từng byte, in RAM tối đa của mỗi bản. Tag audio.cpp tách ra `Scripts/ci/audiocpp_ref.txt`; khoá cache framework (cả `build-ipa.yml`) gồm script + tag + bản vá.
- **Tự cứu trong app** (`VieNeuTurboRuntime`): `audiocpp_session_run` lỗi cấp phát (`AUDIOCPP_ERR_OUT_OF_MEMORY` hoặc "allocate") ⇒ nhả session (graph + bộ đệm của nó), dựng lại cùng số luồng, đọc lại đúng đoạn đó **một** lần; lỗi khác thì báo như cũ. Thời gian / CPU đo gồm cả lần hỏng.
- **Đo bộ nhớ**: `ProcessMemoryProbe` (mới, `Services/Diagnostics/`) — `phys_footprint` (số iOS dùng để giết app) + `os_proc_available_memory()`. Mỗi dòng đoạn của "Đọc liên tục" (màn + log) thêm "RAM … MB · trống … MB"; lỗi, dựng session, thử lại đều ghi kèm. audio.cpp `v0.9.4` (ABI 0.2) chưa có `audiocpp_log_set` nên chưa lấy được log của ggml.
- **Kiểm chứng:** script vá chạy thử trên bản audio.cpp `v0.9.4` tải về (mốc khớp, chạy lần hai tự bỏ qua); `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**; job parity trên CI là bằng chứng không đổi tiếng. Chưa thử máy.

## [1.3.847] - 2026-11-11

### fix: màn thử VieNeu Turbo đo Turbo và Nano cùng mức ưu tiên luồng, dừng khi bị ngắt âm thanh

- Turbo (hàng đợi audio.cpp + luồng ggml) và lượt Nano của chế độ đọc liên tục cùng chạy ở QoS `utility` — cùng mức session ORT của Nano được dựng; QoS quyết chuyện lõi hiệu năng hay lõi tiết kiệm nên hai engine phải chung một mức. Mô tả engine, số đo đọc thử và log ghi rõ QoS.
- Đo Nano thì nhả Turbo trước (model ~188 MB + `sea_g2p.bin` của Turbo) để bớt áp lực bộ nhớ và cửa sổ CPU của Nano không lẫn Turbo; lượt Nano dùng khoá tổng hợp ngẫu nhiên nên vòng lặp sau không dùng lại kết quả vòng trước.
- Cuộc gọi / Siri ngắt âm thanh ⇒ dừng hẳn lượt đọc liên tục (trước đó trình phát đứng im mà đồng hồ vẫn chạy).
- Thêm chỉ số **CPU/1k ký tự** (mỗi phút và tổng kết) — không lệ thuộc giọng nói nhanh hay chậm, so hai engine công bằng hơn CPU/tiếng.
- `build-ipa.yml` build IPA cho nhánh `feature/vieneu-turbo-gguf` (IPA chỉ gửi Telegram; nguồn LiveContainer vẫn chỉ lấy từ `main`).
- **Kiểm chứng:** đọc code; `check_architecture.py` **0 mới**. Lượt CI của nhánh là lần biên dịch đầu; chưa thử máy.

## [1.3.846] - 2026-11-11

### feat: màn thử VieNeu Turbo GGUF qua audio.cpp (đo RTF, CPU, nhiệt)

Phần Swift của bước thử Turbo GGUF (anh Bửu duyệt "làm thử trên nhánh mới"), dùng `AudioCpp.xcframework` của 1.3.845. Viết ở session con, cherry-pick sang nhánh `feature/vieneu-turbo-gguf`.

- Màn **Thử VieNeu Turbo (GGUF)** mở từ Cài đặt VieNeu TTS (hàng "Thử VieNeu Turbo (GGUF) — thử nghiệm", không cần model Nano): tải model GGUF q8_0 chính thức (`pnnbao-ump/VieNeu-TTS-v3-Turbo`, ghim revision `61b85e3d`, đúng 187.917.664 byte, tiến độ theo byte) + manifest 25 giọng + cặp file của giọng (`ref_codes.txt`, `speaker.emb.txt`, tải khi dùng lần đầu). `sea_g2p.bin` dùng chung với Nano; máy chưa có thì tải đúng nguồn ghim sha của `VieNeuModelClient`. Thư mục riêng `Application Support/FreeBook/TTS/VieNeuTurbo/` (màn Dung lượng đã tính trong "Giọng đọc & từ điển TTS"). Nút xoá model Turbo giữ `sea_g2p.bin`.
- `VieNeuTurboRuntime` bọc C API audio.cpp (`import AudioCpp`, header tag `v0.9.4` — ABI 0.2.0): registry → model (`family_hint = vieneu_v3_turbo`) → session CPU N luồng; mọi lời gọi trên một hàng đợi tuần tự, `audiocpp_last_error` đọc ngay trên cùng luồng; nạp model một lần, đổi số luồng chỉ dựng lại session; nhả khi rời màn. Bản build thiếu framework ⇒ `#if canImport(AudioCpp)` ném "Bản build này chưa có audio.cpp".
- Chữ → phiên âm đi đúng đường Nano: thay thế ký tự → `normalizeVietnameseText` → tiền xử lý tiếng Nhật của VieNeu → `SeaG2P.phonemizeTextWithEmotions` (thực thể riêng). Tiếng stereo 48 kHz trộn về mono, WAV 16-bit 48 kHz.
- **Đọc thử một lần**: thời gian nạp model / dựng session, phiên âm, audio.cpp, độ dài tiếng, RTF, CPU-s mỗi giây tiếng (`ProcessCPUClock`), % một lõi, nhiệt trước → sau; chia sẻ WAV, sao chép số đo.
- **Đọc liên tục (đo nhiệt)**: lặp văn bản dài (mẫu ~2.600 chữ tự viết, hoặc dán), cắt ≤ 150 ký tự bằng `NghiUtteranceSegmenter`, tổng hợp trước tối đa 2 đoạn, phát nối tiếp (lúc hụt tiếng phát vòng lặng để khoá màn vẫn chạy); ghi từng đoạn + tổng kết mỗi phút (giây tiếng, CPU-s, CPU/tiếng, số lần hụt, nhiệt) lên màn và log `🎙️ [VieNeuTurbo]`. Chọn được **Nano** (qua `VieNeuTTSService.synthesizeWithDuration`, tốc độ 1×, không sửa engine) để so cùng văn bản, cùng máy. Bắt đầu đọc thì dừng TTS chính, giành `AVAudioSession` `.playback`.
- **Kiểm chứng:** đọc code — mọi chỗ gọi C API khớp `audiocpp.h` tag `v0.9.4` (handle `OpaquePointer`, `audiocpp_status`, struct cấu hình dựng trong `withCString`, con trỏ kết quả mượn được chép trước khi free); chữ ký các API sẵn có (`VieNeuTTSService.synthesizeWithDuration`, `NghiUtteranceSegmenter.expand`, `SeaG2P(binURL:)`, `VieNeuJapanesePreprocessor.applyUsingStoredFlags`, `TTSManager.stop()`) khớp; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Chưa biên dịch tại chỗ (Windows), chưa thử máy.

## [1.3.845] - 2026-11-11

### ci: dựng audio.cpp cho iOS thành AudioCpp.xcframework để thử VieNeu Turbo GGUF

Anh Bửu duyệt bước thử chạy VieNeu-TTS **v3 Turbo** bằng file GGUF q8_0 chính thức qua **audio.cpp** (ggml, Apache-2.0) trên nhánh `feature/vieneu-turbo-gguf` — sau khi thấy một app đọc truyện khác chạy Turbo bằng GGUF mà không nóng máy. Lượt này chỉ là phần build; màn thử Swift đi ở commit sau.

- **`Scripts/ci/build_audiocpp_ios.sh`** (mới): clone audio.cpp tag `v0.9.4`, cross-compile cho iOS 17 arm64 chỉ family `vieneu_v3_turbo`, chỉ CPU (iOS không cho app chạy nền dùng GPU, mà TTS phải đọc khi khoá màn hình), tắt OpenMP (Apple clang không có), kernel ggml `-march=armv8.2-a+dotprod+fp16` (**A13 trở lên**; A12 sẽ lỗi lệnh khi chạy Turbo). sentencepiece (vendored) gọi macro `set_xcode_property` chỉ có trong bộ toolchain iOS riêng của nó ⇒ script khai macro rỗng qua `CMAKE_PROJECT_INCLUDE`. Đóng gói target C API (SHARED, chỉ xuất `audiocpp_*` nên ggml / sentencepiece không đụng symbol của app) thành `AudioCpp.framework` có module map ⇒ Swift `import AudioCpp`; kiểm phụ thuộc chỉ còn thư viện hệ thống, biên dịch thử một file Swift gọi `audiocpp_abi_version()` cho iOS, rồi `xcodebuild -create-xcframework` ra `Vendor/AudioCpp/` (gitignore).
- **`build-ipa.yml`**: cache `Vendor/AudioCpp` theo hash của script, thiếu thì chạy script trước `xcodegen generate`. **`audiocpp-ios.yml`** (mới, chỉ nhánh thử + chạy tay): dựng riêng framework, không build app, không gửi Telegram — để sửa script nhanh; chung khoá cache.
- **`project.yml`**: link + embed `Vendor/AudioCpp/AudioCpp.xcframework`. Trên Mac muốn generate project thì chạy script trước.
- **Kiểm chứng:** chưa — Windows không build được; lượt CI `audiocpp-ios.yml` là lần biên dịch đầu.

## [1.3.844] - 2026-11-11

### feat: mục lục truyện tranh có nút dịch lại tên chương như Reader

Anh Bửu: *"nếu dùng title_trans thì nên thêm nút dịch lại tên chương như reader"*.

- Nút **Dịch lại tên chương** (icon dịch 14 pt, khung 32×32, cạnh nút kệ / tải — như mục lục Reader) ở header mục lục truyện tranh; chỉ khi truyện đã lưu (có `Book`, mục lục nằm trong `ChapterStore`) — truyện chưa lưu không có `title_trans`, tên chương vốn dịch thẳng.
- Bấm ⇒ đúng hàm của Reader / Kệ: `BookActionRunner.retranslateChapterTitles(for:)` (từ điển chưa nạp ⇒ báo lỗi; dịch lại mọi tên chương kể cả dòng nhóm bằng `translateChapterTitle`, ghi `title_trans`, toast).
- Xong ⇒ thông báo `chapterTitlesDidRetranslate` (đã có) ⇒ `ComicReaderView` gọi `ComicReaderViewModel.reloadStoredTitleTranslations()` (mới, file `+TitleTranslation`: nạp lại `titleTrans` từ `ChapterStore`, bỏ tên dịch cũ) rồi dịch lại tên đang hiện ⇒ mục lục và thanh trên đổi ngay.
- `CLAUDE.md` / `AGENTS.md`: mục màn đọc comic (mục lục 1.3.843–844).
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows), chưa thử máy. Cần thử: sửa một name có trong tên chương ⇒ bấm Dịch lại tên chương ⇒ toast xong, mục lục + tên chương ở thanh trên đổi theo.

## [1.3.843] - 2026-11-11

### perf: mục lục truyện tranh dựng hàng một lần và giữ dòng nhóm khi tìm hay đảo thứ tự

Anh Bửu: *"vì sao mở danh sách chương ở commic hiển thị lâu vậy?"*, *"xem cách hiển thị khác gì danh sách chương của reader"*, *"nếu có group thì vẫn nên để group"*.

- **Nguyên nhân có khả năng (đọc code, so với mục lục Reader; chưa đo trên máy):** mỗi lượt vẽ, `ComicChapterListSheet` lọc / đảo / đánh số **cả** mục lục trên main; mỗi hàng bọc `Group { if dòng nhóm … else hàng chương … }` (Reader ghi rõ kiểu bọc này có thể buộc `List` dựng mọi hàng để đếm); không có vỏ chặn vẽ lại nên mỗi lượt vẽ của màn đọc (ảnh tải xong, dịch xong tên chương…) kéo cả mục lục tính lại; tìm thì lọc toàn bộ trên main mỗi phím.
- `ComicChapterListRows` (mới, hàm thuần): dựng hàng + số thứ tự **một lần** mỗi khi mục lục / ô tìm / thứ tự / công tắc "Hiện số thứ tự" đổi (`.task(id:)`); mục lục > 400 dòng dựng ngoài main kèm vòng xoay, lượt mới huỷ lượt cũ.
- **Dòng nhóm luôn giữ** (trước đây ẩn khi tìm hoặc xếp giảm dần): mục lục chia nhóm theo thứ tự gốc; giảm dần ⇒ đảo thứ tự nhóm và chương trong nhóm, tiêu đề vẫn trên chương của nó; tìm ⇒ giữ tiêu đề trên các chương khớp của nhóm (tiêu đề tự khớp ⇒ giữ cả nhóm, nhóm không còn gì ⇒ ẩn). Số thứ tự vẫn theo mục lục đầy đủ.
- `ComicChapterListRow` (mới): một kiểu hàng cho mọi phần tử (dòng nhóm hoặc chương, cùng dáng như trước); nền hàng / màu vạch gắn ở `List`.
- `ComicChapterListHost` (mới): vỏ không trạng thái `.equatable()` như `ReaderChapterListHost` (`==` so mục lục, chương đang đọc, chương đã tải, bật dịch, `Book` theo identity, launch, thứ tự).
- Log `📚 [ComicTOC] Mở mục lục N dòng (M hiện): có hàng sau X ms` (bật log) để đo trên máy.
- `ComicTranslationStatus` nhận thêm `sourceName` / `definitionRequest` (chuyển từ `ComicReaderView`, giữ file đó dưới 400 dòng).
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows), chưa thử máy. Cần thử: (1) mở mục lục truyện dài — xem log `📚 [ComicTOC]`; (2) truyện có nhóm: đảo thứ tự, tìm — tiêu đề nhóm vẫn đúng chỗ; (3) gõ tìm liên tục không giật; (4) cuộn tới đúng chương đang đọc khi mở.

## [1.3.842] - 2026-11-11

### fix: đọc lại từ đầu chương thì trang cũng về đầu chương và tự cuộn theo

Rà lại 1.3.841 trước khi đẩy: người bấm nút tai nghe giữa lúc nghe thường đang ở giữa chương, hay đã tự kéo trang (kéo trang lúc TTS đọc ⇒ tắt tự cuộn theo highlight, chỉ lệnh nhảy của widget bật lại). Chọn "Đọc lại từ đầu chương" khi đó thì tiếng đọc về tên chương nhưng trang đứng yên giữa chương và không đi theo nữa.

- `ReaderView+TTSSameChapterPrompt`: sau khi đọc lại từ đầu chương ⇒ bật lại tự cuộn (`reenableTTSAutoScrollFromWidgetJump`) rồi cuộn tới đầu chương (`ScrollTarget` đoạn -1 ⇒ `ReaderScrollCoordinator` cuộn tới mốc `chapter-N`; tên chương không có highlight nên tự cuộn không tự kéo tới). Reader đã sang chương khác trong lúc sheet mở ⇒ mở lại chương được hỏi.
- "Đọc từ đoạn đang xem" giữ đúng hành vi cũ (đoạn đó đang trên màn hình).
- Nhãn trợ năng của nút tai nghe: bỏ "Dừng đọc thành tiếng" (nút không dừng đọc, giờ mở sheet hỏi) ⇒ luôn "Đọc thành tiếng". Chuyển `[1.3.812]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows), chưa thử máy. Cần thử: đang nghe giữa chương, kéo trang đi, bấm tai nghe → "Đọc lại từ đầu chương" ⇒ trang về đầu chương và cuộn theo đoạn đang đọc.

## [1.3.841] - 2026-11-11

### feat: bấm nút tai nghe trúng chương đang phát thì hỏi đọc tiếp, đọc từ đoạn đang xem hay đọc lại từ đầu chương

Anh Bửu: *"nếu như bấm nút nghe truyện mà chương được bấm nghe cũng đang phát thì hãy hiển thị message hỏi"*; chê hộp thoại giữa màn của iOS (*"màn hỏi hơi xấu"*), chọn kiểu sheet kính.

- **Trước đây**: nút tai nghe nổi của Reader, khi TTS đang phát đúng chương đó, dừng phiên rồi đọc lại từ **đoạn trên cùng màn hình** ⇒ bấm nhầm là mất chỗ đang nghe.
- **Giờ**: TTS **đang phát** đúng truyện + đúng chương mà nút sắp đọc (chương của đoạn trên cùng màn hình, tính như cũ) ⇒ mở sheet `ReaderTTSSameChapterSheet` (mới), chưa đụng phiên TTS. Khuôn `TTSQuickControlSheet`: nền kính ngăn kéo, cao vừa nội dung, vuốt xuống để đóng (không nút Huỷ). Hàng đầu: đĩa bìa xoay + tên truyện + tên chương + nhãn "Đang đọc" / "Tạm dừng". Ba hàng:
  - **Đọc tiếp chỗ đang đọc** — không dựng lại phiên; trang về đoạn đang đọc + bật lại tự cuộn (cùng đường nhảy của widget, tách thành `jumpToPlayingTTSPosition` dùng chung với `navigateReaderToPlayingChapter`); tạm dừng giữa lúc sheet mở ⇒ phát tiếp; phiên đã tắt ⇒ đọc từ đoạn đang xem.
  - **Đọc từ đoạn đang xem** — đúng hành vi cũ (đoạn chụp lúc bấm, vì TTS vẫn đọc và trang vẫn tự cuộn khi sheet mở).
  - **Đọc lại từ đầu chương** — chunk đầu (tên chương nếu TTS đọc tên chương).
- **Không đổi**: tạm dừng mà đoạn đang dừng còn trên màn hình ⇒ phát tiếp ngay; tạm dừng đã kéo trang đi / chương khác / truyện khác ⇒ đọc từ đoạn trên cùng màn hình; "Nghe" của menu bôi đen đọc ngay chỗ đã bôi. Ngoài Reader không có lối nào bắt đầu đọc một chương (Chi tiết, Kệ, widget, hub chỉ phát tiếp / dừng / mở Reader).
- Sheet gắn neo `.blocker` ⇒ đĩa nghe góc dưới ẩn trong lúc sheet mở (không thì đè lên hàng cuối). Đĩa nổi (cửa sổ riêng) vẫn có thể che sheet như mọi sheet khác của Reader.
- Logic nút tai nghe chuyển từ `ReaderView+Controls` sang `ReaderView+TTSSameChapterPrompt` (mới); `ReaderView` thêm 2 `@State` (yêu cầu đang hỏi + chiều cao sheet đo được) và gắn sheet ở tầng sheet gốc. Chuyển `[1.3.811]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows), chưa thử máy. Cần thử: (1) đang nghe, bấm tai nghe ở chương đang đọc ⇒ hiện sheet, ba lựa chọn làm đúng; (2) kéo trang đi rồi chọn "Đọc tiếp" ⇒ trang về đoạn đang đọc và tự cuộn lại; (3) chương khác / đang tạm dừng ⇒ không hỏi như cũ; (4) kiểu widget Đĩa góc dưới ⇒ đĩa ẩn khi sheet mở, hiện lại khi đóng.

## [1.3.840] - 2026-11-11

### fix: phụ đề cứng ghép chữ đúng kiểu phụ đề Trung, dịch theo công tắc dịch của phim, thêm Từ điển truyện vào trình phát

Anh Bửu thử 1.3.830: *"Dịch phụ đề cứng … ra nghĩa gì tầm bậy nhìn không hiểu"*, *"vì sao cùng OCR mà commic đúng còn video sai?"*, rồi *"áp dụng bật tắt dịch và từ điển như truyện tranh và truyện chữ luôn nhé"*; chốt **giữ công tắc "Đọc phụ đề cứng"**, còn dịch thì theo bật/tắt dịch.

- **Nguyên nhân dịch tầm bậy** (cùng Vision + VietPhrase với truyện tranh, khác ở khâu ghép chữ trước khi dịch): (1) xoá mọi khoảng trắng, trong khi phụ đề Trung dùng **dấu cách thay dấu phẩy** ⇒ hai vế dính nhau; (2) mảnh cùng hàng xếp theo chiều dọc và chỉ giữ 2 mảnh cuối ⇒ đảo vế / rơi vế; (3) dịch từng hàng thay vì cả câu. `VideoHardSubtitleRecognizer` giờ: khoảng trắng giữa hai chữ Hán ⇒ `，` (cạnh dấu câu toàn khổ ⇒ nối liền, chữ Latin ⇒ dấu cách); mảnh gom theo hàng (chồng dọc ≥ 50% mảnh thấp hơn), trong hàng xếp trái → phải; bỏ mảnh sát mép (tâm ngang ngoài 5–95%) và mảnh không có chữ Hán; hàng cần ≥ 2 chữ Hán, tâm 15–85%; hàng dưới cùng + hàng gần nhất ngay trên nối thành **một câu**, hàng bắt đầu bằng gạch ngang (thoại hai người) giữ xuống dòng.
- **Dịch theo công tắc dịch của phim** như truyện chữ / truyện tranh / phụ đề mềm: `VideoHardSubtitleEngine+Translation` (mới) dùng `MediaCaptionTranslator.prepare` (phim này > nguồn > nguồn tự khai tiếng Trung > toàn cục; phồn→giản theo phim / nguồn — bỏ "luôn phồn→giản" của 1.3.830) + `MediaCaptionTranslator.translate`. Phim tắt dịch hoặc kiểu "Gốc" ⇒ engine ngưng đọc (không có gì để phủ, đỡ pin), lớp phủ không vẽ, phụ đề mềm hiện lại (`VideoPlayerStage` chỉ ẩn phụ đề mềm khi đang đọc **và** đang dịch). Đổi cấu hình dịch / từ điển / rule (ba thông báo có sẵn: `TranslationConfigStore.didChangeNotification`, `.translationDictionariesDidUpdate`, `.quickTranslationRulesDidUpdate`) ⇒ dựng lại `Pass`, xoá đệm, dịch lại câu đang hiện. Engine tách phần dịch sang file `+Translation` để file chính dưới 400 dòng.
- **Ngăn kéo `⋯`** của trình phát: công tắc đổi tên **"Đọc phụ đề cứng"** (khoá cũ `videoHardSubtitleOCRByPackage` giữ nguyên). Đang đọc ⇒ hàng "Phim đang tắt dịch" (khi phim tắt dịch, mở sheet "Dịch phụ đề") + lưới **Gốc / Bản dịch / Song ngữ** (cùng khoá `videoSubtitleDisplayMode` với phụ đề mềm; Song ngữ = bản dịch + chữ Trung OCR nhỏ bên dưới để đối chiếu). Hàng "Dịch phụ đề" hiện cả khi chỉ đọc phụ đề cứng; thêm **"Từ điển truyện"** (`VideoBookDictionarySheetModifier` mới, `BookDictionaryView` dạng sheet theo `bookId` của phim — phim đang phát luôn có `Book` ẩn; đóng ⇒ dịch lại phụ đề mềm).
- Lớp phủ (`VideoHardSubtitleOverlay`) vẽ theo kiểu hiển thị, câu không có bản dịch ⇒ không vẽ. Log mỗi câu mới `🔤 [VideoOCR] «chữ Trung» ⇒ «bản dịch»` (theo công tắc log).
- Chưa làm: chạm phụ đề mở màn Dịch (dùng lại sheet của truyện tranh, để sau); giảm trễ / nhớ câu theo thời điểm / quét trước tập đã tải (chờ anh chốt). Không đọc trước được khung của luồng đang phát.
- `CLAUDE.md` / `AGENTS.md`: viết lại gạch "Đọc phụ đề cứng (OCR)". Chuyển `[1.3.810]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới** (`VideoHardSubtitleEngine.swift` 361 dòng, `VideoPlayerScreen.swift` 385, `VideoPlayerTopBar.swift` 356). Không build tại chỗ (Windows), chưa thử máy. Cần thử: (1) phim có phụ đề Trung tách vế bằng dấu cách — bản dịch đọc hiểu được, đặt Song ngữ để so chữ Trung OCR với chữ trong phim; (2) tắt dịch ở sheet "Dịch phụ đề" ⇒ lớp dịch biến mất, phụ đề mềm (nếu có) hiện lại, bật lại ⇒ dịch ngay; (3) thêm name ở "Từ điển truyện" ⇒ câu đang hiện đổi theo; (4) gửi log `🔤 [VideoOCR]`.

## [1.3.839] - 2026-11-11

### feat: chọn bộ dịch tiện ích và ngôn ngữ trong popup dịch, màn cấu hình tiện ích dịch có model, kiểu dịch, dịch thử

Phần C (giao diện) của plan tiện ích dịch truyện, gộp commit gốc và bản sửa theo review phản biện. Bộ dịch chỉ chọn ở popup dịch, không thêm vào Cài đặt (anh Bửu chốt).

**Popup dịch** (`TranslationScopePopupView`: header Reader, Chi tiết, menu Khám phá). Thứ tự: Dịch văn bản → PHẠM VI ÁP DỤNG → **BỘ DỊCH** → **NGÔN NGỮ** → hàng báo QT thay thế → Lưu lại.
- **Bộ dịch** (`TranslationEnginePickerSection`, mới):
  - Danh sách xổ tại chỗ, có icon. Không dùng `Menu` hệ thống vì iOS đặt ảnh cuối dòng và tô một màu.
  - Thứ tự: "Theo cấp trên (…)" (chỉ ở phạm vi Truyện này / Nguồn này; tiện ích cấp trên đã gỡ ⇒ ghi "đã gỡ — đang dùng QT") → "QT (VietPhrase, có sẵn)" với icon app → tiện ích dịch đã cài.
  - Chưa cài tiện ích dịch nào ⇒ dòng "Chưa cài tiện ích dịch nào".
- **Ngôn ngữ** (`TranslationLanguagePickerRow`, mới):
  - Ô Dịch từ → Dịch sang theo `language.js`, có "Tự nhận" nếu tiện ích hỗ trợ. Dòng phụ ghi model · kiểu dịch.
  - Đang đọc ⇒ vòng xoay; lỗi ⇒ chữ đỏ + "Thử lại".
  - QT ⇒ hai ô mờ, ghi "QT chỉ dịch Trung → Việt".
- **Bản nháp** (`TranslationEngineDraft`, mới): mỗi phạm vi một bản nháp, nhớ cặp ngôn ngữ theo từng tiện ích. Chọn tiện ích mới ⇒ cặp mặc định (Trung → Việt nếu có).
- **Lưu lại**:
  - Chỉ ghi bộ dịch khi nó thật sự đổi.
  - Chỉ ghi công tắc bật/tắt khi người dùng gạt nó. Trước bản sửa: đổi phạm vi sang "Nguồn này" để chọn bộ dịch rồi Lưu là tắt dịch cả nguồn.
  - Khoá khi tiện ích vừa chọn chưa có cặp ngôn ngữ (đang đọc hoặc đọc lỗi).
- **Báo QT thay thế** (`TranslationFallbackNoticeRow`, mới): dùng chung chữ với dải báo đầu chương, có nút "Thử lại".
- **Ẩn ở truyện tranh**: tham số `showsEngineSection`; `ComicReaderChromeView` truyền `false` vì bộ dịch tiện ích không áp cho truyện tranh.

**Nút dịch** (`ReaderTranslationScopeMenuView`): nhận `chapterIndex`. Chương đang hiện có báo QT thay thế ⇒ chấm cam "!" ở góc dưới phải (chấm xanh/đỏ góc trên giữ nguyên).

**Màn Cấu hình tiện ích loại `translate`** (`ExtensionConfigView+TranslateEngine`, mới):
- Ẩn nút Trình duyệt / Kiểm tra, mục Duyệt và lịch sử, chặn quảng cáo / chế độ máy tính.
- Mục **Bộ dịch**: Model / Kiểu dịch, đầu danh sách là "Mặc định của tiện ích"; ghi ngay qua `TranslationExtensionSettingsStore`.
- Mục **Dịch thử**:
  - Ngôn ngữ chỉ dùng để thử, không lưu.
  - Ô nhập (để trống ⇒ dịch câu mẫu).
  - Nút "Dịch thử" luôn gọi script (`bypassCache`).
  - Ghi config đang chờ (khoá API) trước khi chạy.

**Tài liệu**: `CLAUDE.md` / `AGENTS.md` thêm đoạn "Bộ dịch bằng tiện ích loại `translate`" ở mục Dịch thuật.

**Kiểm chứng:**
- Đọc code + 2 agent review phản biện.
- `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 lỗi mới**. 5 file mới; `TranslationScopePopupView` 387 dòng.
- Không build tại chỗ (Windows), chưa thử máy.
- Cần thử:
  1. Xổ / thu danh sách bộ dịch: popover có giãn theo nội dung không.
  2. Chọn tiện ích ⇒ ngôn ngữ mặc định. Đổi phạm vi ⇒ nạp đúng lựa chọn đã lưu.
  3. Truyện tắt dịch riêng ⇒ chọn bộ dịch ở "Nguồn này" ⇒ nguồn vẫn bật dịch.
  4. Chấm cam + hàng báo + Thử lại.
  5. Dịch thử ngay sau khi nhập khoá API.

## [1.3.838] - 2026-11-11

### feat: dịch nội dung chương bằng tiện ích dịch trong Reader và TTS, báo khi dùng QT thay thế

Phần B của plan tiện ích dịch truyện (lõi 1.3.832 / 1.3.836). Gộp commit gốc và bản sửa theo review phản biện. Bộ dịch là tiện ích ⇒ nội dung chương truyện chữ và tên chương ở header Reader / TTS được dịch bằng tiện ích. Mục lục, Chi tiết, Khám phá, xuất TXT vẫn QT. Phần chọn bộ dịch ở popup là phần C (bản kế).

**Reader**
- Khi dịch bật và bộ dịch của truyện là tiện ích, `ReaderViewModel+ExtensionTranslation` (mới) gọi `TranslationExtensionChapterTranslator` với đúng các dòng sẽ dựng đoạn và tên chương. Bộ dịch tra lại mỗi lượt dựng qua `TranslationEngineStore.resolve` với `extensionPackageId`.
- `buildCancellable` nhận bản dịch sẵn theo `line.id`; không có thì chạy QT như cũ. Bản dịch của tiện ích không có span.
- Bỏ tên chương trùng gom về **một** hàm, `ChapterTextNormalizer.contentLines(of:removingDuplicatedTitle:)` (mới), dùng chung cho Reader, `TTSBackgroundProcessor` và lượt dịch bằng tiện ích. `getTTSChapterContent` trả nội dung chưa bỏ tên trùng, nên không còn bỏ hai lần.
- **Báo QT thay thế:**
  - Mỗi lần áp bản dựng, `applyPreparedTranslation` ghi `TranslationFallbackStatusStore`.
  - Dải báo đầu chương `ReaderTranslationFallbackBanner` (mới): nền cam 14%, icon tam giác, "Đang dịch bằng QT thay thế" + "<tiện ích> lỗi: <lỗi> · N/M đoạn", nút "Thử lại".
  - Dải vẽ trong `ParagraphCardView` của mục đầu chương (`chapterIndex` + `isChapterStart`). `ReaderView.swift` chỉ sửa tại chỗ.
- `ReaderExtensionTranslationObserver` (mới):
  - Đổi bộ dịch / ngôn ngữ / model / kiểu ⇒ chương đang hiện dựng lại.
  - "Thử lại" ⇒ dựng lại dù generation không đổi.
- `requestRetry` xoá cache dịch của truyện (cả lỗi đã nhớ) **ngay lúc xin**, để Reader và TTS dịch lại cùng một lượt. "Tải lại chương" cũng xoá cache dịch của truyện.
- `ParagraphCardView.displayText` hiện `translated` cả với dòng không có chữ Hán: tiện ích dịch được cả truyện tiếng Anh, và TTS đọc đúng chữ đó. Đường QT không đổi vì dòng không có chữ Hán có `translated == original`.

**TTS**
- 4 chỗ gọi `processChapter` đi qua `TTSExtensionTranslationPreparer.processChapterWithEngine` (mới).
  - Có snapshot hợp lệ của Reader thì dùng y, kể cả tên chương (`TTSPretranslatedSnapshot.originalTitle` / `translatedTitle`).
  - Không có thì dịch bằng translator rồi dựng snapshot.
  - Lượt chuẩn bị sẵn không bao giờ tự gọi tiện ích.
- TTS tra bộ dịch và công tắc dịch theo đúng `packageId` của Reader (`translationPackageId`; TXT tự nhập là `"local"`). Giá trị này đi theo khoá nạp trước chương kế.
- `TTSExtensionTranslationObserver` (mới):
  - Đổi bộ dịch của truyện đang phát (vân tay: tiện ích + ngôn ngữ + model + kiểu) ⇒ bỏ bản chuẩn bị sẵn, đọc lại chương đang phát từ đầu đoạn đang đọc.
  - "Thử lại" đúng chương đang đọc cũng vậy (`TTSManager+ExtensionTranslation`, khuôn `updateTranslationSetting`).
- `TTSTranslationFallbackNotifier` (mới):
  - TTS phải đọc bản QT ⇒ toast "<tiện ích> lỗi, TTS đọc bản QT thay thế", một lần mỗi chương, **chỉ lúc bắt đầu đọc chương đó** qua `TTSPresentationEventCenter`.
  - Ẩn khi Reader đã báo cho chương.
- `TTSPreparedChapter.chapterTitle`: bắt đầu đọc từ bản chuẩn bị sẵn thì không dịch QT lại tên chương.

**Kiểm chứng:**
- Đọc code, có 2 agent review phản biện. `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 lỗi mới**: 8 file mới, `TTSManager.swift` 3467 ⇒ 3458, `ReaderView.swift` 1957 ⇒ 1952.
- Không build tại chỗ (Windows), chưa thử máy.
- Cần thử:
  1. Bộ dịch là tiện ích ⇒ chương hiện bản tiện ích, header đúng tên chương.
  2. Tiện ích lỗi (sai khoá / tắt mạng) ⇒ dải báo; Thử lại khi TTS đang đọc ⇒ Reader và TTS cùng đổi, vệt khớp.
  3. Đổi model / ngôn ngữ khi đang nghe ⇒ TTS đọc lại từ đoạn đang đọc.
  4. TTS tự sang chương khi Reader đóng mà tiện ích lỗi ⇒ toast một lần.
  5. Truyện tiếng Anh dịch sang Việt ⇒ vệt highlight khớp cả dòng không có chữ Hán.
- Rủi ro còn lại:
  - Tiện ích treo thì Reader kẹt ở khung chờ.
  - Thử lại xoá cache dịch cả truyện.

## [1.3.837] - 2026-11-11

### feat: chạm khối dịch trong truyện tranh mở màn Dịch của Reader với chữ Trung gốc đã nhận

Anh Bửu: *"khi tôi nhấn vào vùng dịch trong trang đọc commic hãy hiển thị màn hình giống màn hình dịch của reader, đầu vào là đoạn tiếng trung gốc đã OCR"*.

- **Chạm một khối dịch** (trên trang và trong trình xem phóng to) ⇒ sheet **Dịch** = nguyên `ReaderDefinitionOverlayView` của Reader (nền xám đậm, cao vừa nội dung `fittedSheetDetent`, vuốt xuống để đóng), câu gốc = chữ Trung OCR của khối, lúc mở chọn sẵn cả câu. Đủ như Reader: chạm chữ / mũi tên nới thu vùng chọn, nghĩa VP / Hán-Việt, chip gợi ý, ⚙ quản lý nghĩa, lưu Name / VP riêng / chung kèm ghim mặc định (cùng khoá `@AppStorage` với Reader), chip rule + bật tắt / sửa / xoá / chuyển rule, nút `+` thêm rule, tra nhanh bằng công cụ tìm. **Nhấn giữ** khối ⇒ đổi gốc ↔ dịch (chức năng chạm cũ).
- `ComicDefinitionSheet` (mới, `Views/ComicReader/Definition/`, + `+Selection`, `+Rules`): giữ trạng thái như `ReaderView` và **chép** phần ráp nối của Reader (`ReaderView+Selection` / `+RuleTools` / `+DefinitionLoading` / `+SelectionSheets`, gắn chặt vào trạng thái của `ReaderView`); lõi dùng lại nguyên `ReaderDefinitionOverlayView`, `ReaderDefinitionWorker`, `ReaderDefinitionSession`, `QuickTranslationRuleEditorSheet`, `QuickTranslationRuleMutation`, `TranslationManager.saveCustomEntry`. **Không sửa `ReaderView`.** Câu gốc là bong bóng nên không soi bộ rule tên chương.
- Trên trang: `ComicTranslationOverlay` chạm ⇒ `onOpenDefinition`, nhấn giữ 0,4 s ⇒ đổi gốc / dịch; sheet gắn ở `ComicTranslationToolsModifier` (`definitionRequest`), mọi sheet của nó đóng ⇒ dịch lại bong bóng + tên chương.
- Trình xem phóng to: cover giờ là `ComicZoomScreen` (mới) = `ComicZoomViewer` + sheet Dịch của chính nó (sheet phải gắn trong cover). `ComicZoomTranslationLayer`: chạm ⇒ `onTapBlock`, nhấn giữ ⇒ đổi gốc / dịch. Đóng sheet Dịch ⇒ `revision` mới ⇒ trình xem dịch lại lớp của nó (giữ khối cũ tới khi có bản mới).
- `CLAUDE.md` / `AGENTS.md`: mục dịch ảnh.
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới** (`ComicReaderView.swift` 395 dòng). Không build tại chỗ (Windows), chưa thử máy. Cần thử: (1) chạm bong bóng ⇒ màn Dịch đúng câu gốc; (2) chạm một chữ / mũi tên đổi cụm, nghĩa đổi theo; (3) lưu một name ⇒ sheet đóng, bong bóng đang hiện đổi theo (cả trong trình xem phóng to); (4) nhấn giữ đổi gốc ↔ dịch, chạm ngoài khối vẫn bật / tắt thanh, chạm đúp vẫn phóng to.

## [1.3.836] - 2026-11-11

### fix: dịch bằng tiện ích gộp lượt trùng giữa Reader và TTS, nhớ lỗi gần đây, đổi nguồn mang theo bộ dịch

Sửa lõi phần A (1.3.832) theo review phản biện, trước khi nối vào Reader / TTS / giao diện.

- **Gộp lượt trùng** (`TranslationExtensionInflight`, mới). Reader và TTS (hoặc hai lượt nạp trước chương kế) xin dịch cùng các dòng với cùng cấu hình thì chỉ một lượt gọi tiện ích chạy, mọi bên nhận cùng kết quả.
  - Trước đây hai bên cùng trượt cache, gọi tiện ích hai lần. Với máy dịch kiểu AI, hai lần ra hai chữ khác nhau nên vệt highlight lệch.
  - Lượt chạy là `Task` riêng: bên cuối cùng rời đi vì huỷ thì lượt bị huỷ theo.
- **Nhớ lỗi gần đây** (`TranslationExtensionLineCache`, 90 s). Dòng vừa lỗi ở Reader thì TTS cũng lùi QT, không gọi lại rồi ra chữ khác. Đang bị giới hạn lượt thì không gọi dồn. "Thử lại" / tải lại chương xoá luôn phần này.
- **Thế hệ cache theo từng truyện**: xoá cache của truyện A không còn làm rơi lượt ghi đang chạy của truyện B.
- **Chia lô**:
  - Lỗi ở nửa sau không còn làm mất bản dịch của nửa đầu.
  - `max_length ≤ 0` (hợp đồng: không chia gì) ⇒ lệch số dòng thì cả lô tính lỗi, không chia đôi.
  - Gặp lỗi gọi tiện ích (không phải lệch dòng) ⇒ dừng gọi tiếp.
- **Tên chương**:
  - `title_trans` (bản QT tiếng Việt) chỉ dùng khi tiện ích dịch sang tiếng Việt. Dịch sang ngôn ngữ khác thì hiện tên tiếng Việt là sai.
  - Nội dung vừa gặp lỗi gọi tiện ích ⇒ tên chương lùi QT luôn, không tốn thêm một lượt gọi.
- `translateText(_:job:bypassCache:)`: ô Dịch thử luôn gọi script. Lỗi của tên chương cũng được nhớ.
- `BookSourceMigrator`: Đổi nguồn chép bộ dịch riêng của truyện sang truyện mới và xoá bản của truyện cũ (luật "thêm kho theo `bookId` ⇒ thêm vào cả hai hàm").
- **Kiểm chứng:**
  - Đọc code + 2 agent review.
  - `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 lỗi mới**.
  - Không build tại chỗ (Windows), chưa thử máy.

## [1.3.835] - 2026-11-11

### fix: chạm đúp xem ảnh truyện tranh lần đầu không còn mở rồi tự đóng

Anh Bửu: *"phần đọc commic lần đầu tap đúp xem ảnh bị lỗi mở rồi tự đóng màn xem ảnh full"*.

- **Nguyên nhân (đọc code, chưa thử máy):** trình xem phóng to mở bằng `fullScreenCover(isPresented:)` còn ảnh nằm ở `@State` riêng (`zoomImage`). Lần đầu, SwiftUI dựng nội dung cover bằng giá trị cũ của biến ảnh (vẫn `nil`, vì thân `ComicReaderView` không đọc biến đó) ⇒ rơi vào nhánh dự phòng `Color.black.onAppear { isZoomPresented = false }` ⇒ cover tự đóng. Lỗi có từ khi làm màn đọc truyện tranh, không do 1.3.833 / 1.3.834.
- **Sửa:** `ComicReaderView` trình bày bằng `fullScreenCover(item:)` với `ComicZoomViewer.Target` (ảnh + yêu cầu ảnh của trang) ⇒ cover nhận đúng ảnh ngay lần đầu; bỏ nhánh tự đóng và hai biến `zoomImage` / `zoomRequest` / `isZoomPresented`. "Đang xem phóng to thì không dọn dẹp màn đọc" (`handleDisappear`) giờ kiểm `zoomTarget != nil`.
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows), chưa thử máy. Cần thử: chạm đúp ảnh ngay sau khi mở truyện ⇒ trình xem ở lại; đóng rồi mở lại vẫn được; đang xem phóng to, màn đọc không bị ghi tiến độ / giải phóng giữa chừng.

## [1.3.834] - 2026-11-11

### feat: dịch tên truyện trên thanh trên và chữ trong trình xem phóng to của màn đọc truyện tranh

Anh Bửu hỏi màn đọc truyện tranh đã dịch hết các mục khi bật dịch chưa. Javis rà thì còn hai chỗ: tên truyện ở thanh trên hiện nguyên văn, trình xem phóng to không có lớp dịch. Anh chọn sửa cả hai.

- **Tên truyện ở thanh trên** (`ComicReaderChromeView`): dịch bằng `BookDisplayTranslation.title` theo công tắc dịch của truyện — như đầu mục lục truyện tranh và tên truyện ở header Reader.
- **Trình xem phóng to** (`ComicZoomViewer`): truyện đang bật dịch ⇒ có lớp dịch như trên trang. View được zoom đổi từ `imageView` sang `contentView` (chứa ảnh + lớp dịch, cùng khung) ⇒ khối phóng / cuộn theo ảnh. Khối lấy từ `ComicPageTextRepository` theo yêu cầu ảnh của trang vừa chạm đúp (trúng RAM, không nhận chữ lại) rồi dịch như trên trang; task huỷ khi đóng trình xem.
- `ComicZoomTranslationLayer` (mới, UIKit): khối = nền + `UILabel`, cỡ chữ đo một lần ở 1× (thu nhỏ dần tới khi vừa khung); zoom xong đặt `contentScaleFactor` của chữ theo mức zoom để vẽ lại sắc nét (trong lúc chụm hai ngón hơi mờ). Chạm khối ⇒ lộ chữ gốc (viền nét đứt màu nhấn), chạm lại ⇒ dịch; chạm khối chờ chạm đúp phóng to thất bại; vùng trống không nhận chạm.
- `ComicTranslationLayout` (mới): khung, cỡ chữ, màu của lớp dịch — một nguồn cho `ComicTranslationOverlay` (SwiftUI, trên trang) và lớp UIKit của trình xem.
- `ComicTranslationStatus` (mới): cách tính bật dịch y Chi tiết, chuyển từ `ComicReaderView` ra (file đó về 392 dòng).
- `CLAUDE.md` / `AGENTS.md`: mục dịch ảnh bỏ câu "trình xem phóng to chưa có lớp dịch".
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows), chưa thử máy. Cần thử: (1) chạm đúp một trang đã dịch ⇒ trình xem có đúng các khối, đúng chỗ; (2) phóng 2,5× / 4× chữ có sắc lại sau khi buông tay; (3) chạm khối đổi gốc ↔ dịch, chạm đúp vẫn phóng / thu; (4) tên truyện ở thanh trên đổi khi bật / tắt dịch.

## [1.3.833] - 2026-11-11

### feat: dịch ảnh truyện tranh theo công tắc dịch của truyện, thêm nút dịch, Cài đặt dịch và Từ điển truyện vào màn đọc

Anh Bửu: *"thêm màn hình dịch và từ điển riêng cho truyện giống reader, ngoài ra hãy xác định có bật dịch hay không tương tự như truyện chữ nữa cho dịch OCR"* — bật/tắt dịch ở trang Chi tiết của truyện tranh đã đúng, còn dịch ảnh (1.3.826) thì chưa.

- **Dịch ảnh theo đúng công tắc dịch của truyện:** chạy khi và chỉ khi truyện đang bật dịch — cùng `TranslationConfigStore` với trang Chi tiết và tên chương (truyện này > nguồn > nguồn tự khai tiếng Trung > toàn cục). `ComicReaderView` giờ tính y như `BookDetailView` (kèm `isChineseSourceHint` = `isChineseSource` của bản ghi tiện ích) ⇒ hai nơi luôn khớp. Bỏ `ComicImageTranslationPolicy` (công tắc theo tiện ích của 1.3.826) cùng nút "Dịch ảnh" và toast; khoá cũ `comicImageTranslate_*` không đọc nữa (không dọn). Hệ quả: nguồn tự khai tiếng Trung ⇒ mở là dịch cả ảnh; nguồn khác mặc định không; truyện tranh nhập từ file theo công tắc Mặc định toàn cục.
- **Thanh trên** (`ComicReaderChromeView`): nút dịch = nguyên `ReaderTranslationScopeMenuView` của Reader / Chi tiết (bảng "Dịch văn bản" + phạm vi + Lưu lại; icon 17, khung 36×38, không nền), rồi ☰, rồi `⋯` mới. Neo `.mediaDiscAnchor(.headerTrailing)` ở nút dịch (nút trái nhất của cụm phải).
- **Ngăn kéo `⋯`** "Tuỳ chọn truyện tranh" (`ComicTranslationToolsModifier`, file mới; giữ `ComicReaderView` dưới 400 dòng): "Cài đặt dịch" (chữ phụ Đang bật / Đang tắt) và "Từ điển truyện" (`BookDictionaryView` dạng sheet, chỉ khi truyện có `Book` — như Reader). Chỉ có mục dịch, không có gì đổi chương (ngăn kéo cũ đã bỏ ở 1.3.667).
- **Sheet "Cài đặt dịch"** (`ComicTranslationSettingsSheet`, file mới) bám mục "Dịch thuật Quick Translate" của `ReaderSettingsView`: Hiện tại; Truyện này (Theo nguồn / Bật / Tắt), Nguồn (Toàn cục / Bật / Tắt), Mặc định toàn cục; khi đang bật: văn bản trước khi dịch (Giữ nguyên / Phồn → giản, khoá theo truyện như Reader, ghi qua `setTraditionalOverride` để có thông báo), dịch đại từ / luật nhân hoá (khoá chung của app như Reader, đổi ⇒ `notifyDictionariesDidUpdate`), Thứ tự ưu tiên rule, Token rule của truyện (mở lại `ReaderBookRulePriorityView` / `ReaderBookTokenSettingsView`). Form + `.pageTitle` + nút "?", vuốt xuống để đóng. Không sửa `ReaderSettingsView` / `TranslationScopePopupView` (lặp vài picker là chủ ý).
- **Dịch lại khi đổi:** cấu hình dịch (`TranslationConfigStore.didChangeNotification` mà bật/tắt không đổi — vd phồn → giản), từ điển (`.translationDictionariesDidUpdate`, chỉ khi không ghi `bookId` hoặc đúng truyện này), rule (`.quickTranslationRulesDidUpdate`), đóng sheet Cài đặt dịch ⇒ dịch lại tên chương **và** ảnh đang hiện (`refreshTranslations`; chữ đã nhận lấy từ RAM). Trước đó tên chương chỉ dịch lại khi bật/tắt dịch.
- `CLAUDE.md` / `AGENTS.md`: mục dịch ảnh + câu "thanh trên chỉ còn ☰" của mục màn đọc comic.
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới** (`ComicReaderView.swift` 399 dòng — sát giới hạn, việc sau nên thêm vào file riêng). Không build tại chỗ (Windows), chưa thử máy. Cần thử: (1) bật/tắt ở Chi tiết, ở nút dịch thanh trên và ở Cài đặt dịch đều bật/tắt dịch ảnh + tên chương ngay; (2) nguồn manhua tự khai tiếng Trung mở là dịch ảnh; (3) thêm name ở Từ điển truyện ⇒ bong bóng đang hiện đổi theo; (4) đĩa nghe nhấn giữ đậu trái nút dịch.

## [1.3.832] - 2026-11-11

### feat: lõi dịch truyện bằng tiện ích loại translate

Anh Bửu duyệt plan "tiện ích dịch truyện" theo `extension-api.md` của Darkrai9x (loại `translate`). Đây là phần A: lõi Services, **chưa nối** vào Reader, TTS hay giao diện (phần B và C ở các commit sau), nên bản này chưa đổi gì người dùng thấy.

- `Services/Translation/Engine/` (mới):
  - `TranslationEngineSelection`: QT, hoặc một tiện ích kèm ngôn ngữ nguồn → đích.
  - `TranslationEngineStore`: 3 cấp Truyện > Nguồn > Toàn cục như `TranslationConfigStore`, độc lập với công tắc bật/tắt dịch, lưu JSON trong `UserDefaults`. Tiện ích đã gỡ ⇒ `resolve` lùi về QT. Đổi lựa chọn ⇒ `TranslateUtils.invalidateCache` + `didChangeNotification`.
  - `TranslationExtensionSettingsStore`: model / kiểu dịch theo từng tiện ích.
  - `TranslationFallbackStatus` + `TranslationFallbackStatusStore` (`@MainActor @Observable`): báo "đang dịch bằng QT thay thế" theo từng chương, cộng yêu cầu Thử lại.
- `Services/Translation/Engine/Extension/` (mới):
  - `TranslationExtensionContext`: đọc một lần mỗi lượt — config đã trộn, ba khoá thô `support_auto_detect` / `max_line` / `max_length`, model / kiểu, dấu vân tay.
  - `TranslationExtensionRunner`: một `JSExecutor` mỗi lượt; lô tuần tự nối bằng `\n`; lệch số dòng ⇒ chia đôi tới mức từng dòng; lô lỗi ⇒ dừng gọi tiếp; chỉ ném `CancellationError`.
  - `TranslationExtensionBatchPlanner`, `TranslationExtensionResultParser` (nhận chuỗi hoặc `{ text }`; `segments` chưa dùng).
  - `TranslationExtensionLineCache`: chỉ RAM; khoá gồm tiện ích + phiên bản/config + ngôn ngữ + model + kiểu + `source` + truyện + dòng; chỉ lưu bản dịch khác rỗng.
  - `TranslationExtensionCatalog` (actor): chạy `language.js` / `model.js` / `style.js`, nhớ theo dấu vân tay; mặc định Trung → Việt.
  - `TranslationExtensionChapterTranslator`: điểm vào chung của Reader và TTS. Dòng lỗi có chữ Hán ⇒ QT, không có ⇒ giữ chữ gốc. Tên chương: `title_trans` ⇒ tiện ích (`tableOfContent`) ⇒ QT. Phồn → giản áp trước khi gửi.
- Không giữ executor lâu dài (không thêm ngoại lệ cạnh `ExtTTSRuntime`). Không sửa `TranslateUtils.swift` (đang chạm baseline dòng).
- Chưa làm (đúng plan): `localBook`, các khoá `localConfig` dành riêng (`translate_model`…), `segments`, Kiểm tra tiện ích cho loại này.
- Chuyển `[1.3.802]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng:** đọc code. `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 lỗi mới** (17 file mới, lớn nhất 194 dòng, mỗi file một type chính). Không build tại chỗ (Windows), chưa thử máy.

## [1.3.831] - 2026-11-11

### feat: bật DNS mã hoá riêng từng tiện ích và nguồn Legado

Anh Bửu: *"mặc định tắt DNS, cho bật tắt DNS cho mỗi ext, thêm vào cấu hình ext"* — chốt thêm: giữ công tắc chung (mặc định tắt, 1.3.828), nguồn Legado cũng có công tắc, phạm vi = request trong script / engine của nguồn, một máy chủ chung cho mọi nguồn.

- `Extension.encryptedDNSEnabled` (tắt ghi `nil`) + `ExtensionTransactionCoordinator.setEncryptedDNSEnabled`; cập nhật tiện ích giữ cờ; backup (`BackupPayload` / Writer / Reader / Fingerprint) như `adBlockOverride`.
- Apple không có DoH theo từng `URLSession` ⇒ **proxy HTTP CONNECT nội bộ 127.0.0.1**: `EncryptedDNSRelay` (listener loopback, cổng ngẫu nhiên, khuôn `VideoOfflineHTTPServer`) + `EncryptedDNSRelayTunnel` (CONNECT và `GET http://` tuyệt đối — viết lại dòng đầu, ép `Connection: close`; ra ngoài bằng `NWConnection` với privacy context riêng bắt buộc DoH, dùng lại theo máy chủ; hạn kết nối 10 s, `.waiting` = 502/504; đứng yên 60 s; một bên đóng ⇒ đóng cả hai; log `[DNS-Relay] → host:port`, lỗi `❌`).
- `EncryptedDNSSessionRouter`: `JSExecutor` `fetch` đổi `URLSession.shared` ⇒ `session(forExtensionPath:)` (session `.default` + `proxyConfigurations`, chung cookie/cache); `LegadoHTTPClient(cancellation:proxyConfigurations:)` qua `LegadoEngineSource.packageId` (đặt ở `LegadoSourceRuntime.Target`). Không ai bật cờ / đang lùi / đang bật cho cả app / proxy chưa sẵn ⇒ đi thẳng như cũ. Bản chụp cho thread nền: `EncryptedDNSRouting`.
- `EncryptedDNSRepository`: cần DNS ⇔ công tắc chung **hoặc** có nguồn bật cờ; chỉ công tắc chung đụng context mặc định; có nguồn bật cờ ⇒ bật proxy ngay; `sourcesDidChange()` / `refreshSourceCount()`. `FreeBookApp.init` gọi `start()` **sau** khi nạp bảng tiện ích.
- Giao diện (theo mockup): công tắc "DNS mã hoá (DoH)" trong mục **Mạng** của Cấu hình tiện ích (dưới "Xử lý cookie hệ thống", chân mục theo trạng thái) và mục **Hoạt động** của Chi tiết nguồn Legado (`ExtensionEncryptedDNSToggle`); đang bật cho cả app ⇒ bật + mờ. Mạng & DNS: "Bật cho cả app", máy chủ luôn hiện, dòng "Bật riêng: N tiện ích / nguồn", trạng thái khi có ai cần.
- `CLAUDE.md` / `AGENTS.md`: viết lại mục DNS mã hoá.
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows), chưa thử máy. Cần thử: (1) bật cờ cho tiện ích có nguồn bị nhà mạng chặn ⇒ tải được **và** log có `[DNS-Relay] → <host của nguồn>` (thiếu ⇒ request vòng qua proxy, vd QUIC); tắt ⇒ lại bị chặn; tiện ích khác không đổi; (2) như trên với nguồn Legado; (3) nguồn `http://`; (4) bật chung ⇒ công tắc riêng mờ, tắt chung ⇒ cờ riêng vẫn chạy.

## [1.3.830] - 2026-11-11

### feat: dịch phụ đề cứng trong phim bằng nhận chữ trên máy, phủ bản dịch lên đúng chỗ chữ gốc

Anh Bửu duyệt plan OCR phụ đề cứng (chọn thay Whisper vì nhẹ hơn: không model, không tải lại đoạn HLS): phim Trung in sẵn phụ đề trong hình ⇒ đọc bằng Vision, dịch VietPhrase, che chữ gốc. Hai mặc định đã chốt: nhớ bật **theo tiện ích**, **chỉ hiện bản dịch** (che chữ gốc).

- Công tắc **"Dịch phụ đề cứng"** ở ngăn kéo `⋯` của trình phát (`VideoHardSubtitleDrawerRow`, ngay dưới "Dịch phụ đề" của phụ đề mềm; ẩn khi nhúng trang), nhớ theo tiện ích (`VideoHardSubtitlePreferenceStore`, khoá `videoHardSubtitleOCRByPackage`, thiếu = tắt) — không theo phim để khỏi đụng Đổi nguồn. Bật ⇒ phụ đề mềm của tiện ích nhường chỗ (`VideoPlayerStage`).
- `Services/Video/HardSubtitle/` (mới): `VideoHardSubtitleEngine` (`@MainActor @Observable`, singleton) chạy **chỉ** khi lớp phủ của màn xem to đang hiện (`screenDidAppear` / `screenDidDisappear` đếm màn), tự KVO `player.currentItem` — không sửa `VideoPlaybackSession` (`stop()` thay item bằng `nil` ⇒ tự gỡ); mỗi item một `generation` để kết quả về muộn của tập trước bị bỏ. Nhịp 0,5 s (timer ở run loop `.common`), bỏ qua khi nhúng trang / chỉ còn cửa sổ nhỏ / app ở nền / tạm dừng mà khung đã đọc. `VideoHardSubtitleFrameSampler` gắn `AVPlayerItemVideoOutput` (4:2:0 full range; chạy cả HLS).
- Một lượt (`VideoHardSubtitleFrameJob`, hàng đợi nền tuần tự, lượt trước chưa xong thì bỏ nhịp): `VideoHardSubtitleBrightMask` (lưới 128×32 điểm trên mặt phẳng độ sáng của dải dưới 30%, ngưỡng theo full / video range) giống lần Vision trước (Jaccard ≥ 0,9) ⇒ giữ nguyên, quá 4 s vẫn đọc lại; rỗng ⇒ coi như không có chữ, trừ khi quá 3 s (dò thưa) hoặc item này từng có chữ mà mặt nạ không thấy (chữ màu nhạt ⇒ Vision mỗi nhịp); còn lại ⇒ `VideoHardSubtitleRecognizer`: cắt dải dưới **trước** rồi đưa vào `VNRecognizeTextRequest` (`.accurate`, `zh-Hans` + `zh-Hant`, chữ cao ≥ 8% dải), giữ dòng ≥ 2 chữ Hán có tâm ngang trong 15–85% (bỏ logo góc), khối = dòng thấp nhất + tối đa một dòng ngay trên.
- `VideoHardSubtitleCueTracker`: giống ≥ 75% (Levenshtein, bỏ dấu câu) = cùng câu, giữ câu cũ (bản mới nhiều chữ Hán hơn thì thay); trống 2 lượt liên tiếp mới xoá. Dịch `TranslateUtils.translateContent` **từng dòng** ngoài main, Name/VP riêng của phim (`bookId`), **luôn** phồn→giản, không theo cổng dịch của phim; đệm 200 câu, đổi phim thì xoá đệm.
- `VideoHardSubtitleOverlay` (mới): cùng `ignoresSafeArea` với `VideoPlayerSurfaceView`; vùng hình tự tính theo Vừa / Lấp đầy / Phóng từ cỡ khung (không đọc `AVPlayerLayer.videoRect`); dải che + nền chữ dịch vẽ chung một lớp (`compositingGroup`, mờ 0,86) nên chỗ chồng không đậm hơn; chữ 13–22 pt theo chiều cao dòng gốc, ép vào vùng nhìn thấy. Dòng báo "Không đọc được hình của nguồn này" (đang phát mà 5 s không có khung — nguồn DRM) / "Máy chưa hỗ trợ nhận chữ Trung", tự ẩn sau 4 s.
- Log `🔤 [VideoOCR]`: bật / tắt, bắt đầu, tóm tắt mỗi 30 s (số lượt, số lần Vision + ms trung bình, bỏ qua giống / rỗng / đang bận, số câu); lỗi có `❌`. Không tự giảm nhịp theo nhiệt — đo trên máy rồi quyết.
- Chưa làm: lưu câu xuống đĩa (xem lại phải đọc lại), hiện hai dòng gốc / dịch, quét trước tập đã tải, Whisper. Rủi ro đã biết: biển hiệu / thẻ tên ở dải dưới bị dịch nhầm thành phụ đề; HLS tự hạ 360p đọc kém; video có thông tin xoay (quay dọc bằng điện thoại) buffer chưa xoay.
- `CLAUDE.md` / `AGENTS.md`: thêm gạch đầu dòng ở mục Comic & Video. Chuyển `[1.3.800]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới** (9 file mới, lớn nhất 364 dòng, mỗi file một type chính; `VideoPlayerTopBar.swift` 352 dòng). Không build tại chỗ (Windows), chưa thử máy. Cần thử: (1) phim Trung có phụ đề trắng in sẵn — bản dịch che đúng chỗ ở màn dọc và toàn màn, đổi Vừa / Phóng; (2) bật log, xem dòng `🔤 [VideoOCR]` (ms Vision, tỉ lệ bỏ qua) và máy có nóng không; (3) phụ đề vàng / màu nhạt; (4) tạm dừng, tua, đổi tập, thu cửa sổ nhỏ rồi mở lại.

## [1.3.829] - 2026-11-11

### feat: gợi ý chữ Hán khi tìm truyện bằng tiếng Việt

Anh Bửu duyệt ý 7 của plan `Docs/Plans/2026-11-11-dich-phu-de-loi-va-tim-ca-truyen.md`: gõ tên truyện bằng âm Hán Việt ở màn Tìm, app gợi ý dạng chữ Hán để chọn khi nguồn Trung chỉ tìm được bằng chữ Hán; chip **tự hiện khi gõ**.

- `SearchChineseSuggestionBar` (mới) ngay dưới ô tìm của `SearchView` (tìm một nguồn và mọi nguồn; `SearchView` chỉ chèn một dòng): hàng **"Chữ Hán:"** tối đa 6 chip cuộn ngang, kiểu chip nhấn như `ExtensionKindFilterBar` (chữ màu nhấn, nền nhấn 18%, viền 60%). Bấm Tìm vẫn tìm đúng chữ đã gõ; chạm chip ⇒ tắt bàn phím, ô tìm thành chữ Hán đó và tìm ngay (lịch sử lưu chữ Hán). Tính sau khi ngừng gõ 300 ms, ngoài main (`Task.detached`), gõ tiếp ⇒ `.task(id:)` huỷ lượt cũ, kết quả muộn bị bỏ; truy vấn chắc chắn không gợi ý được (rỗng, có chữ Hán, 1 hoặc hơn 8 âm tiết, có số…) ⇒ ẩn ngay, không chờ.
- `Services/Translation/Reverse/` (mới): `HanVietReverseIndex` = bảng `phienAm` đảo ngược (âm ⇒ chữ; chỉ khoá đúng một chữ Hán BMP; một chữ nhiều âm ngăn `/` `,` `;` `|`), hai bảng có dấu / bỏ dấu, nhớ theo `TranslationDictionaryState.revision()`. Chuẩn hoá âm: không tính vị trí dấu thanh (`hoà` = `hòa`), `đ` bỏ dấu là `d`, `y` đứng một mình sau phụ âm = `i` (`lý` = `lí`, `quý` = `quí`). Xét từng âm tiết: âm có dấu ⇒ khớp đúng dấu (không ra chữ thì lùi về bỏ dấu), âm không dấu ⇒ khớp bỏ dấu — gõ dấu một phần vẫn ra.
- `ChineseQuerySuggester` (mới): mỗi vị trí bắt đầu hỏi Name (tuỳ chỉnh, chung) + VietPhrase (tuỳ chỉnh, chung) các khoá có thật dài tới 6 chữ; bỏ khoá đã xoá của từ điển chung như `VietPhraseTokenizer`; không dùng từ điển riêng truyện. Quy hoạch động giữ 16 đường mỗi vị trí, xếp: ít đoạn ⇒ ít đoạn một chữ ⇒ Name trước VietPhrase ⇒ giản thể trước phồn thể (ICU `Traditional-Simplified`) ⇒ thứ tự mã. Bỏ đường trộn giản + phồn, đường có quá nửa số âm tiết là đoạn một chữ (chỉ là đoán chữ đồng âm), đường nhiều hơn đường tốt nhất quá một đoạn. Log `🔎 [HanSuggest]` (số âm tiết / cạnh / kết quả / ms; không log từ khoá).
- `FrozenTrieDictionary.keys(matchingCharacterSets:limit:)` (mới): đi cây đôi theo đúng phép tính của `trieTerminals`, mỗi độ sâu thử mọi chữ của tập, nhánh không có con thì dừng ⇒ chỉ đi qua tiền tố có thật, không gọi `allEntries()`; trần 200 000 cạnh thử; kho `entries` (từ điển tuỳ chỉnh) lọc khoá đúng độ dài.
- Giới hạn: chỉ màn Tìm Kiếm (ô tìm nhanh của Khám phá chưa có); chữ Việt thuần không phải âm Hán Việt không ra gợi ý; thứ tự là đoán theo từ điển (không có tần suất); chạm một chip xong ô tìm là chữ Hán ⇒ hàng chip ẩn, muốn thử cách viết khác phải gõ lại âm Việt.
- Chuyển `[1.3.799]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng:** đọc code + review phản biện bằng agent; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới** (file mới ≤ 400 dòng, một type chính; `SearchView.swift` 701 dòng ≤ baseline 872). Không build tại chỗ (Windows), chưa thử máy. Cần thử: (1) `đấu phá thương khung` và `dau pha thuong khung` ra chip hợp lý; (2) log `🔎 [HanSuggest]` (bật log) xem ms — lần đầu sau khi từ điển đổi có thêm bước dựng bảng đảo; (3) gõ nhanh không giật, không bấm nhầm chip cũ.

## [1.3.828] - 2026-11-11

### fix: DNS mã hoá cho cả app mặc định tắt

Anh Bửu (sau 1.3.825): *"sai ý tôi rồi, mặc định tắt DNS, cho bật tắt DNS cho mỗi ext, thêm vào cấu hình ext"*. Bước 0 của plan: tắt ngay mặc định đang bật sẵn cho mọi người dùng nguồn LiveContainer; công tắc riêng từng tiện ích / nguồn Legado làm ở bản kế.

- `EncryptedDNSPolicy.defaultEnabled = false`. Máy chưa từng bật tay ⇒ tắt (khoá chưa ghi); ai đã bật tay ở Mạng & DNS thì giữ.
- `CLAUDE.md` / `AGENTS.md`: mục DNS mã hoá ghi mặc định tắt.
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows), chưa thử máy.

## [1.3.827] - 2026-11-11

### feat: dịch phụ đề phim và lời bài hát tiếng Trung

Anh Bửu duyệt Ý 6 của plan `Docs/Plans/2026-11-11-dich-phu-de-loi-va-tim-ca-truyen.md`: cổng bật dịch **giống truyện chữ**, kiểu hiển thị mặc định **Bản dịch**, phồn→giản phạm vi **A** (chỉ phim/nhạc).

- `Services/Media/Captions/` (mới): `MediaCaptionTranslator` — `prepare(bookId:packageId:)` (cổng `isTranslationEnabled(bookId:packageId:)` + phồn→giản + chụp `TranslationReadContext` **một lần** cho cả lượt, ngoài main) và `translate(_:pass:)` (bọc `TranslationReadContext.$current.withValue`, dòng nhiều hàng tách `\n` dịch từng hàng bằng `translateContent`, dòng không có chữ Hán / dịch ra y nguyên ⇒ `nil`, kiểm huỷ mỗi 20 dòng, huỷ giữa chừng ⇒ trả `nil` cả lô). Gọi từ **trong** task sẵn có của session, không `Task.detached`. `MediaCaptionDisplayMode` (Gốc / Bản dịch / Song ngữ; khoá `@AppStorage` `videoSubtitleDisplayMode`, `audioLyricsDisplayMode`; mặc định Bản dịch).
- Phép dịch **chỉ để hiển thị, chạy sau parse**: `VideoSubtitleCue.translation`, `AudioLyricLine.translation` (mặc định `nil`, init cũ giữ nguyên — `AudioLyricParser` vẫn dựng như trước); `AudioLyrics.hasTranslation` + `withTranslations(_:)`. `track.subtitles[].data` và nguồn lời giữ nguyên văn, không qua `ChapterTextNormalizer` / JunkFilter / bin / TTS.
- `TranslationConfigStore`: `convertsTraditionalToSimplified(bookId:packageId:)` = phim/album này (khoá sẵn có `convertTraditionalToSimplified_<bookId>` đọc **ba trạng thái** — vắng = theo nguồn) ⇒ nguồn (khoá mới `FreeBook_Translation_Source_TraditionalToSimplified_V1`) ⇒ tắt; kèm `traditionalOverride` / `setTraditionalOverride` / `sourceConvertsTraditional` / `setSourceConvertsTraditional`. Chỉ phụ đề, lời và tên nhóm tập phim (`translateSectionTitles`) dùng; Reader, TTS, truyện tranh, xuất, AI giữ `convertsTraditionalToSimplified(bookId:)`.
- **Phim**: `toggleSubtitles` + `loadSubtitles` dời từ `VideoPlaybackSession+Playback` (392 → 372 dòng) sang `VideoPlaybackSession+Subtitles` (mới): sau `cues = loaded` dịch trong **cùng** `subtitleTask`, lô 50 dòng bắt đầu từ dòng đang chiếu rồi quay về đầu, mỗi lô công bố ngay (`updateCue` gán cả `currentCueTranslation`); sau mỗi `await` kiểm `isCurrent(generation)` (gồm cờ huỷ). `currentCueTranslation`, `hasTranslatedSubtitles` reset ở `prepareForNewLoad` / `stop()`. `setSubtitlesEnabled(_:)`. `VideoSubtitleOverlay` vẽ theo kiểu (song ngữ: dòng dịch to, dòng gốc nhỏ mờ bên dưới; chưa có bản dịch ⇒ nguyên văn). `VideoPlayerTopBar`: nút phụ đề thành `Menu` Tắt phụ đề · Gốc · Bản dịch · Song ngữ khi `hasTranslatedSubtitles` (chọn kiểu là bật lại phụ đề), còn lại giữ nút bật/tắt; ngăn kéo `⋯` thêm hàng "Dịch phụ đề" (Đang bật / Đang tắt; chỉ khi phim có phụ đề).
- **Nhạc**: `applyLyrics` ⇒ `translateLyrics` trong task riêng `lyricsTranslationTask` (gác `lyricsGeneration` + cờ huỷ + lời không đổi; huỷ ở `resetLyrics` / `loadLyrics`), xong gán `lyrics` mới có bản dịch. `AudioLyricsScrollView` (song ngữ: bản dịch dưới mỗi dòng gốc), `AudioCurrentLyricLine` (trang Đĩa + sheet điều khiển nhanh: bản dịch khi kiểu ≠ Gốc), `AudioPlayerDrawerMenu` thêm mục "Lời bài hát" (chỉ khi lời có bản dịch) + hàng "Dịch lời" (khi bài có nguồn lời).
- Sheet chung `MediaCaptionTranslationSheet` (`Views/Common/MediaCaption/`, bám mục dịch của `ReaderSettingsView`, picker phân đoạn, `.pageTitle`, vuốt xuống để đóng, tự gắn `.preferredColorScheme(.dark)` + `.appAccentTint()` vì hai màn trình bày bằng UIKit): Dịch · Phim/album này (Theo nguồn / Bật / Tắt) + · Nguồn (Toàn cục / Bật / Tắt); Phồn → giản · Phim/album này (Theo nguồn / Bật / Tắt) + · Nguồn (Tắt / Bật). Mở từ hai hàng mới theo đường của "Hẹn giờ tắt" (`VideoPlayerController.showsCaptionTranslationSheet` ⇒ `VideoPlayerScreen`; `AudioPlayerScreen` từ callback ngăn kéo). Đóng mà kết quả (bật dịch, phồn→giản) khác lúc mở ⇒ `retranslateSubtitles()` / `retranslateLyrics()`: bỏ bản dịch cũ rồi dịch lại phụ đề / lời đã nạp, không nạp lại phim / bài; phụ đề / lời chưa nạp xong thì không đụng lượt nạp.
- Sửa tiếp sau review (cùng tiêu đề): sheet đánh dấu "đã đổi" ở mỗi lựa chọn thay vì so cấu hình lúc mở — màn cha vẽ lại (xoay máy, hết bài, kéo Trung tâm điều khiển) là `init` chạy lại ⇒ mất mốc so, tắt / bật dịch không có tác dụng tới tập / bài sau; chụp `bookId` / `packageId` vào `@State` một lần ⇒ phim / album tự sang lúc sheet đang mở thì lựa chọn vẫn ghi cho đúng mục đang hiện trên sheet.
- Giới hạn giữ nguyên: chỉ `track.subtitles.first`; tập tải offline và phim nhúng trang không có phụ đề; sửa từ điển giữa chừng áp từ tập / bài sau.
- `CLAUDE.md` / `AGENTS.md`: mục Comic & Video thêm một gạch đầu dòng. Chuyển `[1.3.797]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng:** đọc code + grep chéo chữ ký (`VideoSubtitleCue`, `AudioLyricLine`, `updateCue`, `loadSubtitles`, `AudioPlayerDrawerMenu`); `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới** (file mới ≤ 400 dòng, một type chính; `AudioPlaybackSession.swift` 391, `VideoPlayerScreen.swift` 384, `VideoPlaybackSession.swift` 377). Không build tại chỗ (Windows), chưa thử máy. Cần thử: (1) phim có phụ đề tiếng Trung từ nguồn khai zh: bản dịch hiện gần như ngay ở dòng đang chiếu, menu phụ đề đổi kiểu tức thì; (2) nguồn không khai zh: mặc định không dịch, bật ở "Dịch phụ đề" ⇒ đóng sheet là dịch; tắt ⇒ về nguyên văn, menu về nút bật/tắt; (3) lời LRC tiếng Trung: trang Lời song ngữ, dòng ở trang Đĩa, mục "Lời bài hát" ở ngăn kéo; (4) phồn→giản theo phim / nguồn.
