# CHANGELOG - Nhật ký Thay đổi CodeGraph Tàng Công Các

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **Tàng Công Các**.

## [1.3.943] - 2026-11-14

### feat: Hai công tắc đọc lai Nano · Turbo chuyển ra màn Cài đặt TTS, ngay dưới hàng chọn giọng

Anh Bửu: "Đem 2 nút ra màn hình cài đặt tts đi". Mục **"Đọc lai Nano · Turbo"** (`VieNeuHybridSettingsSection`: "Tiếng nước ngoài đọc bằng Turbo", "Máy nóng thì đọc bằng Nano", dòng trạng thái cặp giọng + các hàng tự tạo bản cặp, nút "?") rời trang Cài đặt VieNeu TTS, sang **Cài đặt TTS** (`TTSSettingsView` — mở từ Cài đặt › Nghe truyện (TTS) lẫn sheet Cài đặt của Reader) ngay sau mục "Giọng đọc", chỉ hiện khi trình đọc là VieNeu.

- `TTSSettingsView`: `vieNeuHybridRefreshToken` tăng khi sheet chọn giọng VieNeu đóng ⇒ mục đọc lại trạng thái cặp của giọng mới chọn (như `selectionToken` của trang cũ). Khoá, mặc định, logic công tắc và tự tạo bản cặp không đổi.
- `VieNeuTTSSettingsView`: bỏ mục; `selectionToken` vẫn dùng cho hàng giọng đang dùng.
- Sửa chú thích nơi đặt công tắc (`VieNeuHybridSettingsSection`, `VieNeuHybridSettings`, `TTSManager+VieNeu`) + gạch "Đọc lai Nano · Turbo" ở CLAUDE.md / AGENTS.md.
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử máy.

## [1.3.942] - 2026-11-14

### feat: Sheet điều khiển nhanh TTS có badge model đang đọc kèm AMX hoặc Core ML

Anh Bửu muốn tiện theo dõi tăng tốc (nếu không ảnh hưởng hiệu năng); duyệt mockup. Badge đặt cạnh badge nhiệt dưới vạch tiến độ chương, ghi **model + cách tăng tốc của đoạn đang phát**: "Turbo · AMX", "Nano · Core ML" (lam, `bolt.fill`) khi đang tăng tốc; "Turbo · CPU" / "Nano · CPU" (xám, `cpu`) khi AMX tự tắt hoặc Core ML chưa sẵn / lùi ORT. Đọc lai Nano · Turbo ⇒ badge đổi theo từng đoạn — nhìn thấy lúc app chuyển model.

- **`VieNeuEngineBadgeStore`** (`Services/TTS/VieNeu/`): bảng nhãn theo chữ đoạn engine nhận (đã áp từ điển thay thế), giữ 64 đoạn gần nhất, khoá `NSLock`. Ghi ở engine Turbo (`VieNeuTurboTTSService`, theo `codecAMXRequested` của session) và Nano (`VieNeuTTSService.executeInternalSynthesis`, chênh `VieNeuCoreMLReaderRoute.counters()` trước / sau lượt: có đoạn Core ML và không đoạn lùi ⇒ "Core ML") — đọc lai đi qua chính hai engine này.
- **`TTSQuickControlNowReading`**: `Snapshot.engineLabel` — trình đọc là VieNeu thì áp `TTSReplacementManager.applyReplacements` cho đoạn đang phát rồi tra bảng (một lần mỗi đoạn, chỉ lúc sheet mở); tra lại khi bắt đầu phát (`$isPlaying`) vì đoạn đầu có chỉ số trước khi tổng hợp xong.
- **`TTSEngineBadge`** (`Views/TTSWidget/`, file mới) + `TTSQuickControlSheet.NowReadingBlock` đặt sau `TTSThermalBadge`. Không phải VieNeu / đoạn im lặng ⇒ không hiện.
- Hiệu năng: mỗi lượt tổng hợp thêm một lần ghi từ điển; sheet thêm một lần thay thế chữ + tra mỗi đoạn. Không thêm vào `TTSWidgetSnapshot` (mặt đĩa không vẽ lại).
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử máy.

## [1.3.941] - 2026-11-14

### fix: Đọc lai Nano · Turbo và nhân bản chéo không còn làm app chết, Turbo bớt giữ chỗ 4,5 GB bộ nhớ ảo

Build 1270 (log 20–21): bật "Tiếng nước ngoài đọc bằng Turbo" với Mai Anh · Nano, hoặc tạo bản chéo rồi nghe thử ⇒ app chết sau vài đoạn với `GGML_ASSERT(ctx->mem_buffer != NULL)` (ggml.c:1699), lần mở sau Core ML của Nano lỗi "mmap file trọng số thất bại"; tắt đọc lai thì không chết. Lớp chống sập hiểu nhầm là lỗi AMX ⇒ tự tắt AMX cho build 1270 (bản build mới tự bật lại).

Nguyên nhân: các ngữ cảnh **chỉ chứa mô tả tensor** (`no_alloc`) của audio.cpp vẫn `malloc` đủ cỡ khai báo — mặc định talker constants **4096 MB**, code predictor constants **1536 MB** (`ConstantTensorCache` tự co còn ¼ RAM trống), codec decoder + encoder weights **1536 MB × 2** (`BackendWeightStore`, không co) — trong khi dùng thật ~0,05 MB mỗi cái. Một mình Turbo còn lọt; giữ thêm Nano (ORT + Core ML map trọng số) thì hết **địa chỉ ảo** của iOS.

- `VieNeuTurboRuntime.descriptorContextOptions` (`+Session`): session Turbo **luôn** dựng với `vieneu_v3_turbo.talker_constant_context_mb=64`, `code_predictor_constant_context_mb=64`, `speech_decoder_constant_context_mb=64` (64 MB = mức sàn audio.cpp tự đặt, ~160 nghìn tensor), kể cả khi AMX tắt — `createSessionLocked` nay luôn tạo bộ tuỳ chọn.
- Đo CI (nhánh đo `claude/turbo-tp-profile`, run 43577447546; báo cáo tối ưu Turbo mục 19): cấu hình app ± ba option ⇒ mã + WAV **trùng từng byte** 6/6 (2 giọng × 3 độ dài), RSS như cũ; giữ chỗ 4,7 GB → 256 MB.
- Cổng parity (`audiocpp_parity_macos.sh`): `APP_OPTS` thêm ba option để các phép so pool / repack chạy đúng cấu hình app.
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử máy.

## [1.3.940] - 2026-11-14

### feat: Thay thế từ TTS chỉ khớp nguyên token, ký hiệu ưu tiên mẫu dài hơn, kiểm tra luật khi nhập

Anh Bửu chốt qua phỏng vấn (grill-me) sau lượt điều tra logic thay thế TTS: trước đây mỗi luật là một lượt `replacingOccurrences` theo thứ tự danh sách ⇒ khớp chuỗi con (`Hà`→`Ha` biến "Hàn Lập" thành "Han Lập"), luật mới nằm cuối danh sách có thể không bao giờ chạy vì luật mặc định phía trên đã thay mất ký hiệu của nó, `....` thua `...`.

- **Tách token** (`TTSReplacementTokenizer`, mới):
  - token **từ** = chữ / số liền nhau; một `-` hoặc `.` kẹp giữa hai chữ / số (không dấu cách) vẫn thuộc từ — `Kamar-Taj`, `S.H.I.E.L.D`, `3.14`;
  - token **ký hiệu** = dãy ký tự không phải chữ / số / khoảng trắng liền nhau — `,`, `..!?`, `.”`.
- **Thay hai lượt** (`TTSReplacementPlan`, mới — thay `ReplacementStep` + `TTSReplacementManager+PlanCompile.swift` đã xoá):
  1. token từ **bằng đúng** mẫu một luật chữ ⇒ thay cả token, vẫn phân biệt hoa thường;
  2. token hoá **lại** kết quả lượt 1, luật ký hiệu chỉ thay **bên trong token ký hiệu**, mỗi vị trí chọn mẫu **dài nhất** (`....!?` → `…!?`).
  - Từ — kể cả từ lượt 1 vừa sinh ra (`Kamar-Taj` → `Ca-ma Tát`) — không bao giờ bị luật ký hiệu thay mất `-` / `.`; ký hiệu do luật chữ sinh ra vẫn được luật ký hiệu dọn.
  - Thứ tự danh sách không còn ảnh hưởng. Giữ nguyên: công tắc bật / tắt, gộp tầng riêng / chung (riêng đè chung theo mẫu, riêng tắt vẫn chặn chung), định dạng file JSON, bước tách cặp số `TTSNumberSeparatorMode` chạy sau như cũ.
- **Luật sai** = mẫu không phải đúng một token (`Hàn Lập`, `Taj,`, `Kamar-`, có dấu cách / xuống dòng) ⇒ bị bỏ qua lúc đọc. Dữ liệu đang lưu không tự sửa.
- **Kiểm tra luật** (`TTSReplacementRuleValidator`, mới — một nguồn cho mọi chỗ):
  - lỗi đỏ chặn Lưu: `EMPTY_PATTERN`, `NOT_SINGLE_TOKEN` (nói rõ mẫu tách thành gì);
  - cảnh báo cam: `DUPLICATE_PATTERN` (trùng mẫu cùng tầng — Lưu sẽ đè), `NO_OP` (thay bằng chính nó);
  - mục **Kiểm tra** hiện ngay khi gõ ở sheet Thêm / Sửa của Cài đặt và sheet "Thêm thay thế TTS" của Reader (`TTSReplacementRuleIssuesView`, mới; dòng xanh nói rõ luật chữ hay luật ký hiệu);
  - huy hiệu đỏ / cam cạnh mẫu trên hàng danh sách (cả danh sách "Rule chung — lấy vào riêng").
- **Màn quản lý luật**: bỏ kéo sắp xếp (mục "Sắp xếp lại", `moveRules` của manager hai tầng); dòng "áp dụng tuần tự từ trên xuống" thay bằng nút "?" giải thích cách khớp; sheet Sửa đổi mẫu trùng luật khác cùng tầng ⇒ đè luật đó (như `addRule`); sheet mở nửa màn, vuốt lên được.
- **Sheet "Thêm thay thế TTS" (Reader)**: cắt dấu cách ở mép vùng bôi đen; menu Lưu tắt khi mẫu sai. Không xét trùng mẫu ở đây — chip R / C đã hiện luật trùng của cả hai tầng.
- Kiểm: mô phỏng thuật toán (bản Python tương đương) khớp mọi ví dụ đã chốt; `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.939] - 2026-11-14

### docs: CLAUDE.md ghi chế độ đọc lai Nano · Turbo và ngoại lệ luật nhiệt

Session làm đọc lai (1.3.934) không được tự sửa CLAUDE.md theo yêu cầu từ session khác nên để đoạn đề xuất trong ghi chú bàn giao; session tối ưu Turbo áp vào lúc gộp các nhánh 1.3.933–1.3.938 để push một lần (anh Bửu: "Gộp và push").

- `CLAUDE.md` + `AGENTS.md` (mirror): thêm gạch **"Đọc lai Nano · Turbo"** dưới mục TTS › VieNeu (cặp giọng `VieNeuVoicePairing`, `VieNeuHybridTTSService` / `VieNeuHybridRouting`, phân loại tiếng nước ngoài, `VieNeuThermalGovernor`, hai công tắc mặc định bật, nhân tốc độ + khớp âm lượng đoạn model phụ); câu "thermal chỉ là telemetry" ở gạch `NghiSynthesisPolicy` ghi rõ ngoại lệ duy nhất là chọn model đọc lai (khớp dòng ngoại lệ đã thêm vào `rules.md` ở 1.3.934).
- Không đổi code.

## [1.3.938] - 2026-11-14

### feat: Bật đọc lai VieNeu mà giọng chưa có cặp thì app tự tạo bản Nano hoặc Turbo cho giọng đó

Anh Bửu (qua session tối ưu Turbo, *"oke cứ làm như vậy"*, rồi duyệt plan ở đây): bật đọc lai mà giọng đang chọn chưa có cặp ⇒ tự tạo bản nhân bản chéo (1.3.937) rồi đọc lai chạy luôn.

- **`VieNeuHybridPairProvisioner`** (mới, `Services/TTS/VieNeu/Hybrid/`, `@MainActor @Observable`): chỉ xét **công tắc dùng tới cặp** — giọng Nano ⇒ A "Tiếng nước ngoài đọc bằng Turbo" (cần bản Turbo), giọng Turbo ⇒ B "Máy nóng thì đọc bằng Nano" (cần bản Nano); hai trường hợp còn lại cặp không bao giờ được dùng ⇒ không tạo.
- **Lúc kích hoạt**: gạt công tắc dùng tới cặp sang bật (`switchChanged(_:isOn:)` từ `VieNeuHybridSettingsSection`; gạt công tắc kia không tính), hoặc người dùng chọn giọng ở sheet chọn giọng lúc công tắc bật (`voiceSelectedByUser()` từ `VieNeuVoicePickerSheet.select`, xét sau 0,8 s). Giọng do app tự đổi (mở app, lùi model khi thiếu file, xoá giọng, chọn giọng vừa nhân bản) **không** tính — nên không theo `TTSManager.$selectedVoice`. Danh sách giọng chưa đọc đĩa ⇒ đọc rồi xét lại.
- **Thiếu file của model kia**: gạt công tắc ⇒ dòng hỏi "… chưa có bản Turbo · cần tải N MB" + "Tải và tạo bản …" / "Bỏ qua giọng này"; chỉ chọn giọng (công tắc bật sẵn) ⇒ không hỏi, chỉ log. Không tự tải ngầm.
- **Một lần mỗi giọng** (`vieneuHybridAutoPairTried`): bắt đầu tạo / bấm Bỏ qua ⇒ nhớ; chọn lại giọng đó không tự thử lại. Gạt công tắc (thao tác chủ động) xét lại; dòng lỗi có "Thử lại".
- **Chỉ tiền cảnh, không giành tiếng**: app ở nền / truyện đang đọc / đang có lượt tạo khác ⇒ chờ, chạy khi truyện dừng (`$isPlaying`) hoặc app mở lại (`didBecomeActive`) nếu giọng vẫn là giọng đó. `VieNeuVoiceCopyRunner.run` thêm `canContinue` (kiểm trước bước đọc mẫu và bước tạo giọng; sai ⇒ tạm dừng, không toast, không tính đã thử) và `onFinish`.
- **Xong** ⇒ `TTSManager.vieNeuHybridSettingsDidChange()` (bỏ đệm cặp, bỏ audio nạp trước, chuẩn bị lại engine ⇒ đoạn kế tiếp đọc lai); toast "Đã tạo bản … — đọc lai đã bật". Log `🔀 [VieNeuHybrid]` mỗi lúc bắt đầu / chờ / bỏ qua / thiếu file / xong / lỗi.
- **Mục "Đọc lai Nano · Turbo"**: dòng trạng thái thay theo việc tự tạo (đang tạo · bước + thanh mảnh / đang chờ / hỏi tải / lỗi + Thử lại); thêm đoạn giải thích sau nút "?". `MainTabView` gọi `start()` cạnh `TTSManager.initialize`.
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.937] - 2026-11-14

### feat: Tạo bản Nano và Turbo cho mọi giọng VieNeu, giọng không có mẫu thì nhân bản từ tiếng máy đọc, bản mới tự ghép cặp đọc lai

Anh Bửu giao qua session tối ưu Turbo: nhân bản chéo Nano ↔ Turbo, kể cả giọng không có mẫu gốc; bản mới phải được đọc lai (1.3.934) nhận là cặp. Anh duyệt plan + mockup.

- **Lối vào** (sheet chọn giọng): nhấn giữ một giọng chưa có bản ở model kia ⇒ "Tạo bản Turbo" / "Tạo bản Nano" (`VieNeuVoiceRowMenu`, giọng có sẵn lẫn giọng tự tạo; giọng tự tạo vẫn có Đổi tên / Xoá). Giọng tự tạo chưa có bản ở model kia hiện trong "Giọng của tôi" của chip đích với nút (`VieNeuVoiceCopyRow`, thay `VieNeuTurboCopyRow`; chip Nano nay cũng có hàng "Tạo bản Nano" cho giọng Turbo tự tạo). Bắt đầu ⇒ sheet sang chip đích; lượt của giọng có sẵn hiện tạm một hàng tiến độ ở đó (tải gói %, "Đang cho giọng … đọc mẫu…", bước tạo giọng).
- **`VieNeuVoiceCopyRunner`** (thay `VieNeuTurboCopyRunner`, hai chiều, mỗi lúc một lượt): tải gói của model đích nếu thiếu (`VieNeuClonePackages`) → mẫu → tạo. Mẫu: giọng Nano tự tạo còn file mẫu, giọng Turbo tự tạo còn `sample.wav` ≥ 3 s ⇒ dùng mẫu gốc; còn lại (giọng có sẵn, Turbo cũ không giữ mẫu, mẫu Turbo < 3 s, Nano mất file mẫu) ⇒ **`VieNeuVoiceSampleSpeaker`** cho chính giọng đó đọc đoạn văn cố định 4 câu (~15 s, đủ 6 thanh) bằng đúng engine của giọng, nối thành WAV tạm. Đường tiếng máy đọc: hỏi trước ("có thể kém giống hơn"), chặn khi truyện đang phát, Turbo không khử nhiễu; đọc bằng model khác model trình đọc ⇒ `scheduleNghiWarmUp()` như thử giọng.
- **Tạo**: Turbo qua `VieNeuTurboVoiceCloneCoordinator` (giọng Nano tự tạo còn mẫu ⇒ `createVoice(fromNanoVoiceId:)` như cũ; còn lại `createVoice(fromFile:…sourceNanoVoiceId:sourceNanoPresetName:)`), Nano qua **`VieNeuNanoVoiceCreator`** (mới — bước tạo giọng Nano của sheet nhân bản tách ra dùng chung, đường Nano không đổi). Bản mới cùng tên giọng nguồn; trùng tên ở model đích (kể cả giọng Nano có sẵn) ⇒ báo, không tạo.
- **Ghép cặp**: thêm `VieNeuTurboCustomVoiceStore.Record.sourceNanoPresetName` (Turbo tạo từ giọng Nano có sẵn) và `VieNeuCustomVoiceStore.Record.sourceTurboVoiceId` (Nano tạo từ giọng Turbo có sẵn / tự tạo); JSON cũ đọc được (trường tuỳ chọn). `VieNeuVoicePairing.resolve(model:voice:nanoCustom:turboCustom:)` (hàm thuần) nhận thêm hai liên kết này, giữ thứ tự tra cũ; `VieNeuVoiceDirectory` dùng chính hàm đó tính `pairedKeys` / `nanoWithoutTurbo` / `turboWithoutNano` / `copySource(for:)` ⇒ menu và đọc lai không lệch luật. Tạo xong ⇒ `VieNeuVoicePairing.invalidate()` (đọc lai nhận ngay, không chờ đệm 30 s).
- **Báo**: toast kết quả qua `TTSPresentationEventCenter` (kèm "từ tiếng máy đọc", "dùng … s đầu của mẫu" khi Turbo cắt mẫu); sheet chọn giọng bỏ toast riêng của runner cũ. Log `🎙️ [VieNeuCopy]`. Nút "?" của sheet chọn giọng giải thích.
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử trên máy; RAM lúc đọc mẫu rồi nhân bản chưa đo; độ giống của bản tạo từ tiếng máy đọc chưa nghe.

## [1.3.936] - 2026-11-14

### feat: Nhân bản giọng VieNeu không còn giới hạn độ dài mẫu, mẫu dài tự cắt ở chỗ ngắt hơi

Anh Bửu: mẫu dài quá giới hạn thì app phải tự cắt thay vì báo lỗi; *"bỏ giới hạn luôn được chứ, ghi âm cũng bị hạn chế tối đa 8 s … cho tôi tối thiểu thôi"* — chỉ còn giới hạn tối thiểu.

- **Giới hạn thật** (đọc code): Nano — graph không giới hạn (`speaker_encoder` nhận chuỗi fbank dài tuỳ ý, `codec_encoder` chỉ dùng 5 s đầu); 30 s là `_MAX_REF_SECONDS` của upstream, upstream chỉ cắt `wav[:30*sr]` còn app tự **chặn** ở `saveBlockReason` + `VieNeuVoiceCloner.enroll`. Turbo — audio.cpp tự cắt 8 s, mã tham chiếu ≤ 100 khung; app vốn không lỗi với mẫu dài nhưng cắt cứng đúng 8,000 s (dễ đứt giữa chữ).
- **`VieNeuCloneSampleCutter`** (mới, `Services/TTS/VieNeuClone/`): điểm cắt = khung 20 ms (bước 10 ms) lặng nhất trong cửa sổ trước mốc, ưu tiên khung muộn nhất ồn hơn tối đa 3 dB; cắt giữa khung, làm nhỏ dần 10 ms cuối. Mẫu không dài hơn mốc giữ nguyên.
- **Nano**: mẫu > 30 s (file hay thu âm) cắt **ngay khi nhận** ở chỗ ngắt hơi trong 26,5–29,5 s: chỉ đọc 30 s đầu file (file dài hàng giờ không giải mã hết vào RAM), ghi WAV 16-bit mono vào thư mục tạm, bỏ file tạm gốc ⇒ nghe lại mẫu, `enrollVoice`, kho Nano, "Cả hai", "Tạo bản Turbo" đều dùng bản đã cắt. Bỏ dòng chặn "> 30 giây" ở `saveBlockReason` (giữ sàn 3 s); `VieNeuVoiceCloner` không đổi (guard 30 s ở đó thành lưới an toàn). Lượt cắt về muộn sau khi mẫu đã đổi tự huỷ (`sampleGeneration`).
- **Turbo** (`VieNeuTurboReferencePreparer`): tiếng nói (sau cắt im lặng) dài hơn 7,9 s ⇒ cắt ở chỗ ngắt hơi trong 6,4–7,9 s thay cho `prefix(8 s)`; mốc chừa 0,1 s để audio.cpp không cắt lần nữa sau khi lên 48 kHz. `Prepared.speechSeconds` = độ dài trước khi cắt. Áp cho mọi lối Turbo (file, thu âm, Cả hai, Tạo bản Turbo).
- **Thu âm**: bỏ tự dừng 8 s — người dùng tự dừng, chốt an toàn 5 phút (`recordSafetyLimitSeconds`); đồng hồ chỉ còn "12,3 s". Nút thu khoá trong lúc đang chuẩn bị mẫu.
- **Báo**: sheet nhân bản có hàng "Đã cắt 29,3 / 45,2 s" khi mẫu bị cắt; giải thích sau nút "?" của "Mẫu giọng". Log `✂️ [VieNeuClone] Mẫu … ⇒ Nano giữ … s đầu (chỗ lặng … dB …)` và `✂️ [VieNeuTurboClone] Tiếng nói … ⇒ dùng … s`.
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.934] - 2026-11-14

### feat: VieNeu đọc lai Nano và Turbo, tiếng nước ngoài đọc Turbo, máy nóng thì đọc Nano rồi mát lại về Turbo

Anh Bửu duyệt cả hai phương án của báo cáo `Docs/Reports/2026-11-14-vieneu-nano-turbo-theo-ngon-ngu.md` ("Làm A và B luôn rồi build 1 lượt"). Chỉ áp cho giọng có **cặp** Nano ↔ Turbo: giọng có sẵn trùng tên đúng từng chữ (Adam, Mai Anh, Trúc Ly, Anh Khôi, Mạnh Dũng, Mỹ Duyên, Đức Trí — "Minh Quân" ≠ "Minh Quân Pro") hoặc giọng nhân bản "Cả hai" (`sourceNanoVoiceId`); cần đủ Nano, Turbo và file giọng Turbo của cặp. Giọng không có cặp đọc như cũ.

- **A — tiếng nước ngoài đọc Turbo** (giọng Nano): `VieNeuForeignTextClassifier` xét từng chunk (sau `normalizeVietnameseText` + gấp macron): token chỉ chữ ASCII, ≥ 2 chữ, không phải âm tiết Việt không dấu, không phải tiếng kêu / viết tắt IN HOA ≤ 3 chữ / vài từ mượn đọc kiểu Việt / từ trong từ điển phiên âm tiếng Nhật đang bật. Đoạn sang Turbo khi có ≥ 2 token lạ hoặc 1 token ≥ 5 chữ; có chữ Hán / kana ⇒ luôn Nano (không model nào đọc được, Turbo có thể ra tiếng lạ). Đo trên 200 chương truyện dịch Trung: 2 / 22.317 đoạn sang Turbo.
- **B — máy nóng đọc Nano** (giọng Turbo): `VieNeuThermalGovernor` vào "nóng" khi `thermalState` ≥ `serious` giữ 60 s (hoặc `critical` ngay), ra khi đã nóng ≥ 10 phút **và** `nominal` giữ 3 phút; theo `thermalStateDidChangeNotification`. **A nhường B**: B bật và máy nóng ⇒ tiếng nước ngoài cũng đọc Nano.
- **Ngoại lệ luật nhiệt** (anh duyệt): thêm một dòng ở `rules.md` mục TTS — nhiệt được dùng **chỉ** để chọn model; cấm huỷ / điều tiết refill, prefetch, audio chương kế vẫn giữ.
- **Một chỗ nối**: `TTSManager.localEngine` trả `VieNeuHybridTTSService` khi `VieNeuHybridRouting.context` có (mọi lối tổng hợp của trình đọc đi qua đó; `TTSManager.swift` không đổi). Engine bọc quyết model từng lượt, đổi sang giọng cặp, gọi đúng service (cùng `PiperSynthesisCoordinator`, mỗi lúc một lượt), log một dòng `🔀 [VieNeuHybrid] Đổi model … (lý do: tiếng nước ngoài: … / máy nóng / máy mát / đoạn tiếng Việt)`; governor log `🌡️ [VieNeuHybrid] Máy nóng / Máy đã mát …`.
- **Khoá tổng hợp**: `VieNeuModelChoice.synthesisEngineIdentity(forEngine:voice:text:)` ⇒ `vieneu.hybrid.<model của đoạn>` khi đọc lai (quyết theo chữ đoạn — tất định), khác `vieneu` / `vieneu.turbo` ⇒ bật / tắt không phát nhầm audio. Đổi công tắc ⇒ `TTSManager.vieNeuHybridSettingsDidChange()`: phát nốt đoạn đang đọc, bỏ audio nạp trước + prefix chương kế (khoá `TTSPreparedNextChapterKey` không có model), chuẩn bị lại engine (dùng chung `discardVieNeuAudioAfterCurrent` với đổi tốc độ tổng hợp).
- **Hai model trong RAM**: khi đọc lai, Turbo không còn tự nhả Nano trước mỗi lượt và Nano không nhả Turbo lúc khởi động (`VieNeuHybridRouting.readerContext`); engine bọc nhả model phụ chỉ khi model chính đổi, model phụ nạp lười ở đoạn đầu cần nó rồi giữ. Nano nạp lười lúc giọng Turbo đọc lai vẫn chạy nháp Core ML nếu gói đã tự kiểm, nhưng **không** tải / biên dịch gói (biên dịch ở nền từng làm iOS giết app). Đổi giọng cùng model ⇒ `scheduleNghiWarmUp()` để engine đổi đúng (bọc ↔ thường).
- **Nối tiếng**: mỗi đoạn vẫn là một WAV + `AVAudioPlayer` riêng ⇒ 24 kHz và 48 kHz phát xen nhau được. Tốc độ: giọng Nano (A) ⇒ đoạn Turbo (48 kHz) phát nhân "Tốc độ tổng hợp" của Nano (`NghiAudioPlayerQueue.rate(for:)`, `VieNeuHybridRouting.playbackRateFactor`); giọng Turbo (B) ⇒ đoạn Nano tổng hợp 1×. Âm lượng: `VieNeuHybridLoudness` kéo đoạn của model phụ về mức RMS trung bình trượt của model chính (kẹp ±4 dB), đoạn model chính giữ nguyên.
- **Cài đặt VieNeu TTS**: mục "Đọc lai Nano · Turbo" (`VieNeuHybridSettingsSection`) dưới hàng giọng đọc — công tắc "Tiếng nước ngoài đọc bằng Turbo" (`vieneuHybridLanguageEnabled`) và "Máy nóng thì đọc bằng Nano" (`vieneuHybridThermalEnabled`), mặc định bật; giải thích sau nút "?", một dòng trạng thái cặp giọng.
- **Chưa kiểm**: chưa build (Windows), chưa thử máy. RAM khi giữ cả hai model chưa đo (ước 1,1–1,3 GB / ~2,1 GB của iPhone 11); thời gian nạp lười Turbo / Nano lúc khoá màn chưa đo; ước đệm (cached time) hơi cao với đoạn Turbo phát nhanh hơn thời lượng WAV; ngưỡng nhiệt là giá trị khởi điểm. `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`.
- **Sửa biên dịch khi gộp** (CI run 43574639399): trong `NghiAudioPlayerQueue.updateRate(_ rate:)` tham số `rate` che hàm `rate(for:)` mới ⇒ gọi `self.rate(for:)`.

## [1.3.933] - 2026-11-14

### chore: Gỡ màn đo tạm codec Turbo, codec ONNX chậm hơn AMX và Neural Engine làm app chết lúc biên dịch

Kết quả màn đo 1.3.932 trên iPhone 11 (log 19, hai lượt; báo cáo tối ưu Turbo §18.3): cùng mã âm thanh, codec ONNX chính thức qua **ORT CPU 112–140** và **Core ML CPU 140–147** ms mỗi giây tiếng — **chậm hơn AMX hiện tại (46–61) khoảng 2,4–3×**, dù tiếng đúng (SNR 58 dB); trên iPhone Core ML chia graph thành 38 mảnh (máy ảo 14). **Core ML + Neural Engine làm app chết lúc dựng session** bucket 64 ở cả hai lượt (không có .ips ⇒ nghi bị hệ điều hành giết vì RAM khi biên dịch cho ANE). Đi tiếp phải sửa graph (gấp hằng mặt nạ, tách graph) với lợi tối đa ~20% RTF (codec chiếm ~20% thời gian) và rủi ro fp16 ⇒ anh Bửu chốt **dừng hướng 3, gỡ màn đo**.

- Xoá `Services/TTS/VieNeuTurbo/CodecBench/` (bridge `TurboCodecProbeBridge`, `TurboCodecProbeSession`, runner, assets, report), `Views/Settings/TTS/TurboCodecBenchView.swift`, dòng trong `FreeBookBridgingHeader.h`, hàng "Đo codec" ở mục Turbo của Cài đặt VieNeu TTS, tham số `extraRequestOptions` của `VieNeuTurboRuntime.synthesize` (không còn ai dùng) — mã về đúng như 1.3.931.
- Dọn thư mục `Caches/turbo-codec-bench/` (~45 MB ONNX + cache Core ML) còn lại trên máy đã chạy màn đo: `VieNeuTurboRuntime.createSessionLocked` xoá nó mỗi lần dựng session Turbo (không có thì thôi); bỏ dòng này sau vài bản.
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`.

## [1.3.932] - 2026-11-14

### feat: Màn đo tạm so codec Turbo chạy AMX với Core ML và Neural Engine trên cùng mã âm thanh

Hướng 3 của báo cáo tối ưu Turbo (§18, anh Bửu duyệt): xem codec MOSS chạy Core ML / Neural Engine có nhanh hơn AMX (đường đang dùng) không trước khi đầu tư sửa graph. Bước thử trên CI (nhánh đo `claude/turbo-tp-profile`): graph ONNX chính thức `OpenMOSS-Team/MOSS-Audio-Tokenizer-Nano-ONNX` ra đúng tiếng (SNR ~60 dB so với codec audio.cpp — GGUF lưu codec F16, ONNX fp32 gốc), độn khung tới bucket giữ nguyên tiếng, cố định chiều động lúc tạo session (`AddFreeDimensionOverrideByName`) cho Core ML nhận 714/907 node trong 14 mảnh (op rơi về CPU: Gather, Less, Unsqueeze, Reshape… của mặt nạ / chỉ số). Máy ảo CI không có Neural Engine ⇒ tốc độ phải đo trên máy. Màn **tạm**, gỡ khi có kết luận.

- **Cài đặt VieNeu TTS › Turbo › "Đo codec: AMX vs Neural Engine (tạm)"** (`Views/Settings/TTS/TurboCodecBenchView.swift`): một nút chạy, dòng tiến độ, báo cáo Markdown hiện tại chỗ + "Chia sẻ báo cáo" (`ShareSheet`). Giữ màn hình sáng trong lúc đo; đang đọc truyện thì từ chối.
- **`TurboCodecBenchRunner`** (`Services/TTS/VieNeuTurbo/CodecBench/`): tổng hợp 3 câu phiên âm cố định (32 / 64 / ~123 khung) × 3 vòng bằng `VieNeuTurboRuntime` với giọng Turbo đang chọn (hoặc giọng Turbo đầu tiên đã tải) — `codes_dump_file` lấy mã, `text_chunk_size=1000` một lượt sinh mỗi câu, `babble_retries=0` (có sinh lại thì mã ghi ra khác tiếng trả về), bộ đếm giờ audio.cpp cho thời gian codec AMX (log app bật suốt lượt đo rồi trả về như cũ; kết quả từng cấu hình ghi log `🧪 [TurboCodecBench]` ngay khi xong). Nhả model Turbo trước khi biên dịch Core ML (bớt ~188 MB RAM). Rồi giải mã đúng mã đó bằng **ORT CPU** (shape động), **Core ML CPU** (fp32) và **Core ML + Neural Engine** (`MLComputeUnits = CPUAndNeuralEngine`; bucket 64 / 128 / 192 khung, mẫu vượt bucket ghi lỗi; độn mã + `audio_code_lengths` thật; cache biên dịch **mỗi bucket một thư mục** `Caches/turbo-codec-bench/coreml-cache/T<bucket>/` — cùng một file model, khoá cache của Core ML EP có thể không tính shape đã cố định — xoá đầu mỗi lượt đo), mỗi lúc một session; ghi mức nhiệt lúc bắt đầu mỗi cấu hình và WAV nghe thử (vòng 1 câu 2) của AMX + từng cấu hình để nghe so (Neural Engine tính fp16). Báo cáo: ms giải mã mỗi giây tiếng (trung vị), so với AMX, SNR so với tiếng audio.cpp, thời gian dựng session / lượt đầu, số node Core ML nhận (đọc log ORT), nhiệt đầu / cuối, theo từng câu.
- **`TurboCodecBenchAssets`**: tải `moss_audio_tokenizer_decode_full.onnx` + `moss_audio_tokenizer_decode_shared.data` (~45 MB, revision ghim `ceff0d07`, kiểm đúng cỡ byte) vào `Caches/turbo-codec-bench/` (hệ điều hành được xoá).
- **`TurboCodecProbeBridge.h/.m`** (thêm vào `FreeBookBridgingHeader.h`): cầu C API ONNX Runtime cho graph codec — vào int32 (`audio_codes [1, T, 16]`, `audio_code_lengths`), ra audio theo kênh cắt theo `audio_lengths`; trọng số nạp từ bộ nhớ (`AddExternalInitializersFromFilesInMemory`, né lỗi external data của Core ML EP ORT 1.24.2); cố định `batch` / `code_length` bằng free dimension override. Bọc Swift `TurboCodecProbeSession` (khuôn `VieNeuONNXProbeSession`, `autoreleasepool`).
- **`VieNeuTurboRuntime.synthesize(…, extraRequestOptions:)`**: tuỳ chọn request phụ (mặc định rỗng ⇒ trình đọc không đổi).
- Gỡ màn đo = xoá `CodecBench/`, `TurboCodecBenchView.swift`, dòng trong bridging header, hàng ở `VieNeuTTSSettingsView+Sections`, tham số `extraRequestOptions` nếu không ai dùng, `Caches/turbo-codec-bench/`.
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa chạy trên máy.

## [1.3.931] - 2026-11-14

### feat: Sheet điều khiển nhanh TTS có badge nhiệt độ máy Mát / Ấm / Nóng / Rất nóng

Anh Bửu muốn thấy máy đang mát hay nóng ngay ở sheet đọc truyện (đo Turbo trên máy thì mức nhiệt quyết định số đo — log 17 nóng "serious" suốt nên không so được với lượt mát). Duyệt mockup.

- **`TTSThermalBadge`** (file mới `Sources/Views/TTSWidget/TTSThermalBadge.swift`): viên nhỏ icon `thermometer.medium` + "Mát" / "Ấm" / "Nóng" / "Rất nóng", chữ xanh / vàng / cam / đỏ trên nền cùng màu 18%, `caption2` nửa đậm. Đọc `ProcessInfo.thermalState` (iOS không cho đọc °C — chỉ 4 mức nominal / fair / serious / critical, cùng nguồn với trường `thermal=` của log TTS), đổi ngay khi iOS báo `thermalStateDidChangeNotification` (nhận trên main). Không bấm được; VoiceOver đọc "Nhiệt độ máy: …".
- **`TTSQuickControlSheet`**: badge nằm bên trái "N/M" ở dòng dưới vạch tiến độ chương (`NowReadingBlock`, chỗ trước đây để trống). Hiện với mọi trình đọc.
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử máy.

## [1.3.930] - 2026-11-14

### perf: Turbo xếp lại trọng số bộ giải mã âm học cho kernel dotprod, phần âm học nhanh hơn khoảng 14%, tiếng không đổi

Mỗi khung 80 ms bộ giải mã âm học (1 lớp: qkv 768→2304, o 768², MLP 2048) chạy 16 bước tuần tự, mỗi bước nhân ma trận × vectơ trên ~7,5 MB trọng số q8_0. ggml có sẵn bố cục xen kẽ `q8_0_4x4` (kernel NEON dotprod — đúng cờ `armv8.2-a+dotprod` của bản iOS; chọn lúc biên dịch nên A15+ có i8mm cũng không rơi vào kernel C) nhưng audio.cpp chỉ bật cho lfm2_audio. Đo trên CI (nhánh đo `claude/turbo-tp-profile`, run 43551654007 + 43552141772, so với cấu hình app 1.3.929; báo cáo tối ưu Turbo mục 16): âm học 56 → 48 / 74 → 63 ms mỗi giây tiếng (**−14…−15%**), RTF −2…−4%, CPU không đổi; mã greedy + WAV **trùng** 8/8 lượt (câu lặp, chia đoạn mặc định). Logit trùng từng bit ở 54% bước, lệch lớn nhất 1,1·10⁻² — thứ tự cộng khác làm activation đổi nấc lượng tử q8 ở ma trận kế, cùng cỡ nhiễu q8 sẵn có; greedy trùng hết 237 khung. Anh Bửu duyệt plan.

- **Bản vá mới** `Scripts/ci/audiocpp_patches/vieneu_acoustic_repack.py` (chạy sau `vieneu_threadpool`): session option `vieneu_v3_turbo.acoustic_repack` (mặc định tắt = như upstream). Bật + backend CPU + kiểu lưu `Native` ⇒ `load_talker_weights` dựng thêm một `BackendWeightStore` trên bộ đệm phụ `CPU_REPACK` (`core::cpu_extra_buffer_types`) và nạp vào đó 5 ma trận q8_0 của mỗi lớp âm học (`attn.qkv`, `attn.o_proj`, `ff_gate`, `ff_up`, `ff_down`) khi `core::buffer_type_supports_matmul_weight` nhận. Head F16 (`audio_embeddings.N`), `codec_head`, backbone giữ chỗ cũ (backbone còn phải đi Accelerate ở bước nạp prompt — ggml-blas chỉ đọc bộ đệm host thường). Chỉ chuyển chỗ ⇒ RAM không đổi (7,17 MB). Graph nạp + 16 graph bước kiểm bằng `validate_backend_graph_with_cpu_extra_buffers` (dùng sai trọng số repack ⇒ lỗi lúc dựng session, không ra tiếng sai). Log `vieneu_v3_turbo.talker.acoustic_repack.weights` lúc nạp và mỗi lượt nạp prompt.
- **Build iOS** chạy bản vá; **cổng parity**: cấu hình app 1.3.929 thêm `acoustic_repack=true` ⇒ log phải báo đủ 5 ma trận trong `CPU_REPACK`, và logit bộ giải mã âm học (`VIENEU_LOGITS_DUMP`) phải nằm trong nhiễu lượng tử q8 so với khi tắt — `Scripts/ci/audiocpp_acoustic_check.py`: sai số tương đối ≤ 3·10⁻² mỗi bước trước chỗ rẽ, greedy chỉ được rẽ ở chỗ gần hoà (top1 − top2 ≤ 0,25), so ít nhất một khung. Lượt đầu đòi mã trùng từng byte thì đỏ: câu dài một đoạn + giọng Minh Quân rẽ greedy (CI run 43553143111) — đúng loại lệch đã đo, nên đổi cổng; `audiocpp-ios.yml` theo dõi thêm file chấm.
- **App**: `VieNeuTurboAcceleration.acousticRepackOption`, `createSessionLocked` truyền cùng cờ AMX (lối tự tắt khi sập theo số build tắt cả repack). Dòng `[VieNeuTurbo] Đoạn` thêm `repack=N` (`VieNeuTurboTimingLog.Timings.acousticRepackWeights`; 5 = đủ, 0 = audio.cpp không repack).
- Ước trên máy: âm học (~36% thời gian) −14% ⇒ RTF thêm ~−4%. Chưa đo trên máy.
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows).

## [1.3.929] - 2026-11-14

### perf: Turbo giữ một pool luồng suốt phiên đọc thay vì tạo luồng mới ở mỗi lượt tính, nhanh hơn và ít tốn CPU hơn

audio.cpp build không OpenMP nên mỗi lượt tính của ggml tạo rồi huỷ một bộ luồng; Turbo có ~17 lượt tính mỗi khung 80 ms (1 backbone + 16 bước bộ giải mã âm học) ⇒ ~210 lần tạo / join luồng mỗi giây tiếng. Đo trên CI (nhánh đo `claude/turbo-tp-profile`, run 43545030992, máy ảo M1, cấu hình như app 1.3.928, 2 giọng × 3 lần lặp xen kẽ; báo cáo tối ưu Turbo mục 15): RTF 0,368 → **0,352 (−4%)**, âm học 83 → 74 ms mỗi giây tiếng, CPU 0,69 → **0,67** CPU-giây mỗi giây tiếng; mã + WAV **trùng từng byte** 6/6. poll 10 / 50 nhanh thêm ~2% nhưng luồng quay chờ đốt CPU (0,71 / 0,78) và tranh lõi với Accelerate (nạp prompt 93 → 100) ⇒ không chọn. Anh Bửu duyệt plan.

- **Bản vá mới** `Scripts/ci/audiocpp_patches/vieneu_threadpool.py` (chạy sau `vieneu_prefill_blas`): session option `vieneu_v3_turbo.threadpool_poll` (0…100; không có = như upstream). Ở lượt `run` đầu, `ggml_threadpool_new` (số luồng của talker) rồi gắn vào backend CPU của talker **và** của session (codec, kể cả phần CPU trong scheduler BLAS). Lớp weights runtime chỉ khai báo trước với session ⇒ thêm hàm tự do `freebook_talker_backend` / `freebook_talker_threads` trong talker.cpp. Luồng mang QoS của người gọi; người gọi đổi QoS (nghe thử giọng `.utility` ↔ trình đọc `.userInitiated`) ⇒ nhả pool cũ, tạo pool mới (`qos_class_self` qua `sys/qos.h` — `pthread/qos.h` bị chặn bởi `__DARWIN_C_LEVEL`). Thành viên khai báo cuối lớp ⇒ nhả trước backend. Log `vieneu_v3_turbo.threadpool_poll` / `threadpool_qos` khi tạo pool.
- **Build iOS** (`build_audiocpp_ios.sh`) chạy bản vá; khoá cache AudioCpp đổi theo bản vá nên CI dựng lại framework.
- **Cổng parity** (`audiocpp_parity_macos.sh`): cấu hình app (codec_blas + prefill_blas) có và không có `threadpool_poll=0` trên câu dài ⇒ mã + WAV phải trùng từng byte, log phải báo đã tạo pool.
- **App**: `VieNeuTurboAcceleration.threadpoolPollOption` / `threadpoolPoll = "0"`; `VieNeuTurboRuntime+Session.createSessionLocked` truyền thêm option khi AMX bật — đi chung cờ nên lối tự tắt khi sập (`VieNeuTurboCrashGuard`, theo số build) tắt cả pool. Log dựng session: "AMX (codec + nạp prompt) + pool luồng giữ lâu bật".
- Ước lượng trên máy: âm học chiếm ~36% thời gian ở 1.3.927 ⇒ RTF ~0,250 → ~0,24. Chưa đo trên máy; không cần tải dữ liệu mới, tiếng không đổi.
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows).

## [1.3.928] - 2026-11-14

### feat: Turbo luôn chạy Tăng tốc AMX, nhanh hơn khoảng 37%, bỏ công tắc thử nghiệm

Đo 1.3.927 trên iPhone 11 (log 16, 61 đoạn, không sập; báo cáo mục 14), so cùng mức nhiệt "fair" với lượt tắt (log 13): RTF 0,400 → **0,250**; nạp prompt 84 → 44 ms mỗi giây tiếng (1,9×), codec 158 → 48 (3,3×); backbone / âm học không đổi. CI 1.3.927: codec bật vẫn trùng mã, WAV ~98 dB; bước nạp qua BLAS lệch fp32 1,7·10⁻⁶ (đường q8 cũ 8,1·10⁻³). Anh Bửu chốt "Bật, bỏ công tắc".

- **AMX luôn bật** (`VieNeuTurboAcceleration.isAMXEnabled`): session Turbo luôn dựng với `vieneu_v3_turbo.codec_blas` + `vieneu_v3_turbo.prefill_blas`. Khoá cũ của công tắc (`vieneuTurboCodecAMX`, `vieneuTurboCodecAMXAutoDisabled`) bỏ qua.
- **Lối thoát khi sập** (không còn công tắc): `VieNeuTurboCrashGuard` thấy lần trước app chết giữa lượt AMX đầu tiên, hoặc audio.cpp ghi câu báo dừng ⇒ ghi số build đang chạy vào `vieneuTurboAMXDisabledBuild` ⇒ AMX tắt **cho tới khi cài bản build khác**, log `❌ … đã tự tắt "Tăng tốc bằng AMX" cho bản build N`.
- **Cài đặt VieNeu TTS › Turbo**: công tắc thành dòng **"Tăng tốc AMX: Đang dùng"** (hoặc "Đã tự tắt tới bản sau"); giải thích sau nút "?" ghi mức nhanh hơn đo được.
- Log đoạn giữ `amx=bật / lùi:codec / lùi:prefill / tắt`.
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không đổi bản vá audio.cpp. Không build tại chỗ (Windows).

## [1.3.927] - 2026-11-13

### feat: Công tắc Tăng tốc bằng AMX của Turbo đưa thêm bước nạp prompt và phép Q·Kᵀ của codec sang Accelerate

Đo 1.3.926 trên máy (báo cáo mục 13): codec qua AMX nhanh ~1,26× (155 → 123 ms mỗi giây tiếng), RTF tổng chỉ −3% vì chỉ ~205/700 node của codec vào BLAS. Anh Bửu chọn làm tiếp "AMX cho nạp prompt + attention" và bảo làm thẳng, không cần plan.

- **Bước nạp prompt qua Accelerate** — bản vá mới `vieneu_prefill_blas.py` (chạy sau `vieneu_prefill_gallocr` + `vieneu_codec_blas`):
  - session option `vieneu_v3_turbo.prefill_blas` (mặc định tắt) ⇒ `VieNeuTalkerWeightsRuntime` giữ một backend BLAS;
  - `TalkerPrefillGraph` cấp phát + chạy qua `ggml_backend_sched` [BLAS, CPU], cỡ = 2 × số tensor graph dùng + 1024 (truyền sức chứa 65536 sẽ xin ~1,3 GB, đúng lỗi đã làm sập codec ở 1.3.924);
  - reserve hỏng ⇒ lùi gallocr; alloc hỏng sau reserve ⇒ ném lỗi cho đoạn đó;
  - trọng số q8_0 được ggml-blas giải lượng tử ra F32 rồi `cblas_sgemm` với activation F32 — **không** lượng tử hoá activation về q8 như đường CPU ⇒ gần bản fp32 gốc hơn, không trùng từng byte với đường cũ;
  - log `vieneu_v3_turbo.talker.prefill.blas_active / graph_nodes / sched_context_mb`.
- **Q·Kᵀ của attention codec** (`vieneu_codec_blas.py`): ggml-blas từ chối src1 là view hoán vị ⇒ khi dựng graph cho scheduler BLAS, attention chép Q thành tensor liền (`ggml_cont`) để phép này cũng chạy Accelerate (phép A·V vốn đã vào được). Cờ `thread_local` chỉ bật trong `prepare_graph` của decoder khi có backend BLAS ⇒ công tắc tắt / encoder / giải mã từng khung: graph y hệt cũ.
- **Job parity**: tắt vẫn phải trùng từng byte bản gốc; codec BLAS vẫn mã trùng + WAV ≥ 90 dB + vùng scheduler ≤ 512 MB. Thêm cổng nạp prompt (`audiocpp_prefill_check.py`): vector ẩn cuối của bước nạp (dòng `prefill_hidden` đầu tiên của `VIENEU_LOGITS_DUMP`) của đường BLAS phải gần đáp án fp32 (`weight_type=f32`) hơn đường q8 đang chạy và sai số < 1e-3; scheduler của bước nạp ≤ 512 MB; log phải báo `prefill.blas_active 1`.
- **App**: một công tắc **"Tăng tốc bằng AMX (thử nghiệm)"** (khoá giữ nguyên `vieneuTurboCodecAMX`, mặc định tắt) bật cả hai option. Log đoạn: `amx=bật` khi codec và nạp prompt đều chạy BLAS, `amx=lùi:codec` / `lùi:prefill` khi audio.cpp lùi về CPU ở phần đó.
- Kiểm: các bản vá thử áp trên PC theo đúng thứ tự (khớp mốc, áp lại tự bỏ qua, ngoặc cân); `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.926] - 2026-11-13

### fix: Tăng tốc codec bằng AMX của Turbo không còn làm app chết, bộ chia việc chỉ xin bộ nhớ đúng cỡ graph

Anh Bửu thử 1.3.925 trên iPhone 11 (iOS 26.3.1): app vẫn chết ở lượt đầu khi bật công tắc, nhưng lần này lớp chống sập của 1.3.925 làm đúng việc — lần mở sau tự tắt công tắc và log ghi `ggml.c:1699: GGML_ASSERT(ctx->mem_buffer != NULL) failed`. File `.ips` (AudioCpp UUID `1a370fa8…` = đúng bản 1.3.925): `SIGABRT`, luồng `VieNeuTurboRuntime`, không frame nào của Accelerate. Dịch ngược AudioCpp (capstone, chuỗi ADRP/ADD) ⇒ lời gọi `ggml_init` hỏng nằm trong `ggml_backend_sched_split_graph` (`ggml-backend.cpp`).

- **Nguyên nhân**: `ggml_backend_sched_new` dành sẵn `graph_size × 30 × 2 × sizeof(ggml_tensor)` byte (mỗi node một split). Bản vá `vieneu_codec_blas` (1.3.924) truyền **sức chứa** của graph codec (131072 node) ⇒ một lần `malloc` ~**2,6 GB**. Máy ảo macOS cho qua (bộ nhớ ảo dư) nên job parity và cả lượt tái hiện 1.3.925 đều không thấy; trên iPhone `malloc` trả NULL ⇒ `ggml_init` xin lại cũng hỏng ⇒ `GGML_ASSERT` ⇒ app chết.
- **Sửa** (bản vá `vieneu_codec_blas.py`): truyền `2 × số tensor graph thật sự dùng (node + nguồn) + 1024` — vài nghìn thay vì 131072 ⇒ vùng dành sẵn cỡ vài chục tới vài trăm MB (ảo, chỉ chạm phần dùng). Log thêm `moss.audio_tokenizer.decode.graph_nodes / sched_graph_size / sched_context_mb`.
- **Chốt CI** (`audiocpp_parity_macos.sh`): bật `codec_blas` mà `sched_context_mb` > 512 hoặc không đọc được ⇒ đỏ — lỗi kiểu này không còn lọt qua máy ảo.
- Công tắc vẫn **thử nghiệm, mặc định tắt**; 1.3.925 đã tự tắt nó trên máy anh (Cài đặt VieNeu TTS hiện dòng "Đã tự tắt…"). Bật lại để thử; lớp chống sập + ghi lý do vẫn giữ.
- Kiểm: bản vá thử áp trên PC (khớp mốc, áp lại tự bỏ qua, ngoặc cân); `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.925] - 2026-11-13

### fix: Turbo tự tắt Tăng tốc codec bằng AMX khi lần trước app dừng giữa lượt đầu, ghi lý do audio.cpp dừng vào log

Anh Bửu thử 1.3.924 trên iPhone 11: công tắc tắt thì Turbo chạy đều (48 đoạn, RTF 0,40; codec 39%, âm học 23%, nạp prompt 21%, backbone 16% — khớp CI). Bật công tắc ⇒ dựng session có AMX xong (1248 ms) rồi **app chết ngay lượt tổng hợp đầu tiên**, log không có dòng lỗi, và công tắc vẫn bật nên lần đọc Turbo sau chết tiếp.

- **Tái hiện trên CI không ra** (nhánh chẩn đoán `claude/turbo-amx-repro`, không gộp, run 43445448000): build audio.cpp đúng cờ CPU bản iOS (`armv8.2-a+dotprod+fp16`) kèm ggml-blas + C API, gọi C API y như app ở luồng chính / hàng đợi GCD QoS userInitiated / pthread stack 512 KB, lấy mẫu như trình đọc, đoạn tới 13 s, 3 giọng — mọi ca chạy hết. ⇒ Nguyên nhân chỉ có trên máy thật (nghi nhất: Accelerate dùng AMX của A13; máy ảo CI không có AMX). Cần câu báo / file `.ips` từ máy.
- **Chống sập lặp lại** (`VieNeuTurboCrashGuard`): trước lượt Turbo đầu tiên có codec AMX của mỗi lần mở app ghi dấu (file nhỏ ở `Library/Caches`, mang mã tiến trình), lượt đó kết thúc thì xoá. Lần mở sau mà dấu còn (của tiến trình khác) ⇒ tự tắt công tắc, ghi `❌` vào log, Cài đặt VieNeu TTS hiện dòng "Đã tự tắt vì lần trước app dừng…" (bật lại công tắc thì dòng này mất). Kiểm ở lúc dựng session Turbo (trước khi đọc công tắc) và khi mở Cài đặt VieNeu TTS.
- **Ghi lý do dừng**: bản vá audio.cpp mới `capi_abort_file.py` — hàm C `audiocpp_set_abort_file(path)` cài `ggml_set_abort_callback` + `std::terminate` handler, ghi câu báo `GGML_ASSERT` / exception chưa bắt ra `Library/Caches/audiocpp-abort.txt` trước khi `abort()`. Lần mở sau app đưa câu đó vào dòng `❌ [VieNeuTurbo] Lần trước …` (công tắc đang bật thì cũng tự tắt). Không bắt được truy cập bộ nhớ sai — khi đó cần file `.ips`.
- Build iOS chặn nếu thiếu symbol `audiocpp_set_abort_file`; job parity áp cả bản vá mới (không đổi phép tính).
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`; bản vá thử áp trên PC (khớp mốc, áp lại tự bỏ qua) và đã build + chạy thật trên CI nhánh chẩn đoán. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.924] - 2026-11-13

### feat: Turbo có công tắc thử Tăng tốc codec bằng AMX, log tách thời gian nạp prompt, backbone, âm học và codec

Báo cáo tối ưu Turbo (`Docs/Reports/2026-11-13-vieneu-turbo-toi-uu.md`, gitignored), P0a đo trên CI (nhánh thử `claude/turbo-p0a-profile`, không gộp): codec MOSS chiếm **37–51%** thời gian một đoạn Turbo và chạy fp32 NEON; backbone q8 không còn nghẽn băng thông. iPhone 11 đo `cblas_sgemm` 388 GFLOPS (AMX) so với ~37 GFLOPS mỗi lõi NEON. Anh Bửu chọn hướng "codec qua AMX (máy)" và duyệt plan.

- **Bản vá audio.cpp mới** (`Scripts/ci/audiocpp_patches/`, mốc chuỗi khớp đúng một lần, lệch là build đỏ):
  - `vieneu_codec_blas.py`: session option `vieneu_v3_turbo.codec_blas` (mặc định tắt) ⇒ codec giải mã cả đoạn qua `ggml_backend_sched` [BLAS, CPU] (khuôn `moonshine_asr` của audio.cpp). Dựng scheduler hỏng ⇒ bỏ BLAS, dựng lại graph sạch trên đường cũ. Không đụng talker, giải mã từng khung, encoder nhân bản giọng. Log `moss.audio_tokenizer.decode.blas_active / blas_nodes / sched_splits`.
  - `capi_log_file.py`: hàm C `audiocpp_set_log_file(path)` bật bộ đếm giờ có sẵn của audio.cpp (symbol tự xuất theo `_audiocpp_*`).
- **Build iOS** (`build_audiocpp_ios.sh`): `GGML_BLAS=ON`, nhà cung cấp Apple (Accelerate, framework hệ thống); chặn build nếu thiếu symbol `audiocpp_set_log_file`. Khoá cache đổi ⇒ dựng lại framework một lần.
- **Job parity** (`audiocpp_parity_macos.sh` + `audiocpp_wav_snr.py`): bản vá (công tắc tắt, có ggml-blas) vẫn phải trùng từng byte bản gốc; bật `codec_blas` thì mã âm thanh phải trùng, WAV ≥ 90 dB so với khi tắt, và log phải báo codec thật sự chạy BLAS. Runner là máy ảo không có AMX ⇒ chỉ kiểm đúng số, không kiểm tốc độ.
- **App**:
  - Cài đặt › Nghe truyện › Cài đặt VieNeu TTS › mục Turbo: công tắc **"Tăng tốc codec bằng AMX (thử nghiệm)"** (`VieNeuTurboAcceleration`, khoá `vieneuTurboCodecAMX`, mặc định tắt), giải thích sau nút "?".
  - `VieNeuTurboRuntime`: dựng session kèm option khi bật (`+Session`, tách khỏi file gốc); gạt công tắc ⇒ đoạn tổng hợp kế tiếp tự dựng lại session, không nạp lại model.
  - Log bật ⇒ dòng `[VieNeuTurbo] Đoạn` thêm `prefillMs stepMs acousticMs codecMs gens amx=tắt/bật/lùi` (`VieNeuTurboTimingLog`: mỗi lượt mở file tạm sạch, đọc xong xoá). Log tắt ⇒ audio.cpp không ghi gì.
- Cách đo trên máy: bật log, nghe Turbo vài phút tắt công tắc rồi vài phút bật, so `codecMs` mỗi giây tiếng và RTF. AMX không được đếm đủ vào CPU-time ⇒ đừng so `cpuPerAudio`.
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`; bản vá thử áp lên audio.cpp v0.9.4 trên PC (khớp mốc, áp lại tự bỏ qua). Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.923] - 2026-11-13

### feat: Xoá được Bộ đệm hệ thống và xem thư mục Không rõ chủ ở màn Dung lượng, thêm nút xoá giọng đã tải và Xoá tất cả dữ liệu

Anh Bửu chụp màn Dung lượng 1.3.920: "Khác" 8,31 GB (Bộ đệm hệ thống 7,05 GB, Không rõ chủ 1,24 GB) mà Dọn rác báo "Không có" — đúng luật (bộ đệm không phải dữ liệu "không còn dùng"). Anh duyệt plan dọn bộ đệm và mockup nút xoá.

- **Bộ đệm hệ thống (Library/Caches) mở ra được** thành 4 nhóm lớn nhất + "Khác" (`SystemCacheTally`): Core ML của hệ thống (`com.apple.e5rt*` …), bộ đệm mạng (URLCache), bộ đệm web (WebKit), ảnh bìa tạm, ảnh đa nhiệm của hệ thống; còn lại theo tên thư mục.
- **Nút "Xoá" Bộ đệm hệ thống** (`SystemCacheCleaner`, hỏi lại):
  - Từ chối khi đang đọc truyện / Core ML đang chuẩn bị / đang có lượt xoá khác.
  - Thứ tự: nhả backend Core ML của trình đọc → `URLCache.removeAllCachedResponses` → `WKWebsiteDataStore` chỉ các loại bộ đệm (cookie / đăng nhập giữ nguyên) → xoá mọi mục trong `Library/Caches`.
  - Giữ thư mục của mục khác (`comic_images`, `comic_ocr`); `cover_images` chỉ làm trống.
  - Kiểm đường dẫn (không thoát qua symlink). Mục lỗi gom một dòng `❌ [SystemCache]`.
  - Trình đọc đang là VieNeu và gói Core ML đã qua tự kiểm ⇒ nạp sẵn lại Core ML ở nền.
- **"Không rõ chủ" hiện 4 thư mục lớn nhất** (đường dẫn so với thư mục nhà) + "Còn lại", ngay dưới dòng đó. Log `[StorageUsage]` thêm 10 đường dẫn lớn nhất trong "Khác của TTS". Snapshot cũ vẫn đọc được (trường mới optional).
- **Nút 🗑 cuối hàng** (`TTSVoiceDeleteButton`) ở sheet chọn giọng:
  - Giọng NghiTTS đã tải (kể cả giọng nhập từ file).
  - Giọng VieNeu Turbo đã tải, không phải giọng nhân bản: xoá riêng `Voices/<id>/` (`VieNeuTurboModelStore.deleteDownloadedVoice`), model giữ lại.
  - Giọng Nano không có (dùng chung một gói).
  - Hỏi lại; đang đọc đúng giọng đó ⇒ dừng phiên trước.
- **"Xoá tất cả dữ liệu"** ở trang cài đặt, có dung lượng, ẩn khi chưa tải gì:
  - **Cài đặt VieNeu TTS:** "Xoá tất cả dữ liệu Nano" (gói Nano + gói nhân bản + Tăng tốc Core ML) và "Xoá tất cả dữ liệu Turbo" (model + mọi giọng tải về).
  - **Cài đặt NghiTTS:** "Xoá tất cả giọng NghiTTS" (`NghiVoiceDirectory.deleteAll`; giữ thư viện phiên âm).
- Bỏ mục nhấn giữ "Xoá dữ liệu Nano / Turbo" trên giọng có sẵn (1.3.919) — thay bằng hai nút trên. Giọng nhân bản vẫn nhấn giữ để đổi tên / xoá.
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.922] - 2026-11-13

### feat: Tải giọng NghiTTS hiện tiến độ theo từng byte và huỷ được giữa chừng

Anh Bửu thử 1.3.921: tiến độ tải giọng NghiTTS nhảy theo file (0 → 50 → 100%) và không huỷ được.

- **Tiến độ theo byte:** `NghiTTSClient.prefetchModels(…, byteProgress:)` tải file `.onnx` (~61 MB, file lớn duy nhất của giọng) bằng đường tải theo byte của VieNeu (`VieNeuTurboModelClient.transfer`: `session.download(for:delegate:)` + quan sát `task.progress`, báo theo phần nghìn).
  - Ghi qua `<file>.partial` rồi mới đổi tên ⇒ file dở không mang tên thật.
  - `ModelDownloadCenter.updateBytes` ghi `completedBytes` / `totalBytes`. Sheet chọn giọng NghiTTS hiện "Đang tải 37% · 23 / 61 MB" + thanh mảnh, như hàng VieNeu.
- **Huỷ giữa chừng:** đang tải ⇒ nút tròn thành ■, bấm = `ModelDownloadCenter.cancel(id:)` (giờ dùng chung cho đích NghiTTS).
  - Huỷ `Task` ⇒ `URLSession` dừng ngay. Lỗi huỷ không thành thông báo "Tải … thất bại".
  - `TTSVoiceListRow` bỏ trạng thái "vòng xoay, nút tắt".
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.921] - 2026-11-13

### feat: Siri, NghiTTS, Google TTS và tiện ích chọn giọng bằng sheet giống VieNeu, có tìm, thử giọng và tải ngay tại chỗ

Phần 3 của plan anh Bửu duyệt (§18.2 báo cáo `2026-11-11-vieneu-nano-toi-uu.md`, mockup "Chọn giọng"). Kèm ô tìm theo tên giọng anh xin thêm.

- **Cài đặt TTS — mục "Giọng đọc"**: Siri / NghiTTS / Google / tiện ích bỏ `Picker` menu, thay bằng **một hàng** kiểu `VieNeuVoiceSummaryRow` (`TTSReaderVoiceSummaryRow` / `TTSVoiceSummaryRow`) ⇒ sheet chọn giọng.
  - Dòng phụ theo trình đọc:
    - Siri: "Tiếng Việt · Nâng cao / Mặc định / Premium";
    - NghiTTS: dung lượng, hoặc cam "Chưa tải dữ liệu giọng · chạm để tải";
    - Google: mô tả giọng;
    - tiện ích: ngôn ngữ.
  - Badge "Nhẹ" (Siri, NghiTTS) / "Online" (Google, tiện ích). `TTSVoiceBadge` dùng chung với badge Nhẹ / Vừa / Nặng của VieNeu.
- **Sheet chọn giọng chung** (`TTSVoicePickerSheet`, `Views/Settings/TTS/Voices/`): cùng khung với sheet VieNeu — tiêu đề "Giọng đọc" + "?", ô "Tìm theo tên giọng" (`VoiceNameSearch`), hàng ▶ / ⬇ / ✓ / badge.
  - **Siri:** giọng tiếng Việt trên máy (`SiriVoiceList`, đọc ngoài main); ▶ đọc câu thử bằng `AVSpeechSynthesizer` riêng.
  - **NghiTTS** — thay màn "Quản lý Model giọng đọc" (`TTSModelManagerView` đã xoá):
    - hàng "Nhập giọng từ file .onnx" (`NghiVoiceImporter`, chép file ngoài main);
    - nhóm Giọng đặc sắc / Giọng khác / Giọng của tôi (`NghiVoiceDirectory`);
    - ⬇ tải qua `ModelDownloadCenter.startNghiVoiceDownloads`, kèm **thư viện phiên âm** nếu còn thiếu (`ModelDownloadCenter+NghiDictionary`);
    - nhấn giữ ⇒ "Xoá giọng". Giọng đang đọc (kể cả đang tạm dừng) ⇒ dừng phiên trước khi xoá;
    - ▶ đi qua `nghiTTSService` / `PiperSynthesisCoordinator`, không mở session ORT thứ hai; thử giọng khác giọng trình đọc ⇒ đóng sheet thì nạp lại giọng trình đọc.
  - **Google:** nhóm Giọng nữ / Giọng nam; ▶ qua `GoogleTTSService`; không có API key ⇒ báo, không gọi mạng.
  - **Tiện ích:** giọng do tiện ích trả về (`ExtensionTTSVoiceList`, bỏ giọng thiếu `id` / trùng `id`); ▶ qua `extService.synthesizeData`.
  - Thử giọng dùng chung `TTSVoicePreviewPlayer`: mỗi lúc một câu, đóng sheet thì dừng, chặn khi truyện đang phát (như VieNeu).
- **"Quản lý riêng của trình đọc"**:
  - NghiTTS: bỏ cảnh báo thiếu giọng / thư viện phiên âm và lối "Quản lý Model giọng đọc"; còn "Cài đặt NghiTTS", "Cấu hình tiền xử lý & ngắt nghỉ", "Từ điển phiên âm cá nhân".
  - VieNeu: thêm lối "Cài đặt VieNeu TTS" ở đầu.
- **Cài đặt NghiTTS**: hàng đầu "Giọng đọc NghiTTS" ⇒ sheet chọn giọng NghiTTS. Chọn ở đây khi trình đọc đang là engine khác thì chỉ lưu giọng NghiTTS, không đổi trình đọc.
- `TTSSettingsView.swift` 442 → 312 dòng (danh sách giọng Siri / tiện ích chuyển ra `SiriVoiceList` / `ExtensionTTSVoiceList`). Bỏ entry allowlist của `TTSModelManagerView`.
- Còn nguyên từ trước:
  - giọng nhập có `-` trong id không đọc được (đổi id thành `_`);
  - tiến độ tải giọng NghiTTS nhảy theo file (0 → 50 → 100%).
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.920] - 2026-11-13

### feat: Màn Dung lượng tách rõ từng loại TTS và có Dọn rác theo luật dữ liệu đang dùng

Phần 4 của plan anh Bửu duyệt (§18.2 báo cáo `2026-11-11-vieneu-nano-toi-uu.md`, mockup màn Dung lượng + Dọn rác). Anh chốt luật: *"rác chắc chắn là thứ app không còn sử dụng"* — app biết dữ liệu nào đang dùng nên không đoán.

- **Mục "Giọng đọc & từ điển TTS" mở ra từng loại** (`StorageUsageTTSBreakdown`, một lượt duyệt `FreeBook/`, mỗi file vào đúng một dòng ⇒ cộng lại đúng bằng dòng cha):
  - VieNeu Nano · model + N giọng;
  - VieNeu Nano · Tăng tốc Core ML;
  - VieNeu Turbo · model + N giọng;
  - Giọng nhân bản;
  - NghiTTS · N giọng Piper;
  - Từ điển phiên âm;
  - "Không còn dùng · dọn ở Dọn rác" (cam);
  - Khác của TTS.
- **Mục "Khác" mở ra theo thư mục** (`StorageUsageHomeBreakdown`): file tạm, bộ đệm hệ thống, dữ liệu web (đăng nhập, cookie), "Không rõ chủ · chỉ hiện, không tự xoá".
  - Mỗi lần đo ghi một dòng `[StorageUsage]` với 10 đường dẫn không rõ chủ lớn nhất, để phân loại sau.
- **Hàng "Dọn rác"** dưới "Tự động dọn" ⇒ trang `JunkCleanupView`: tổng dọn được, nhóm + dung lượng, nút "Dọn …" (hỏi lại), giải thích sau nút "?".
- **Luật** (`Services/Storage/Junk/`): mỗi chủ dữ liệu biết đúng file đang dùng; rác = file trong thư mục của nó mà ngoài danh sách đó.
  1. **Core ML cũ:**
     - `Cache-noopt/`;
     - `Cache/` khi dấu tự kiểm không khớp hoặc còn file `.fbtrim` (dấu hợp lệ ⇒ giữ nguyên cả `Cache/`, vì không biết chắc khúc nào đang dùng);
     - file trong `Package/` ngoài manifest.
     - Bỏ qua khi Core ML đang chuẩn bị.
  2. **Dữ liệu màn thử:** `VieNeu/Static/`, báo cáo trong `CoreML/Results/` (giữ `reader-verified.json`).
  3. **File tải dở `.partial`** khi không có lượt tải nào.
  4. **File tạm** quá 1 giờ khi không có sao lưu / tải / xuất nào chạy.
  5. **Dữ liệu của truyện đã xoá:** `books/` / `comics/` / `videos/` không còn `Book`.
     - Tên đúng 64 ký tự hex, quá 10 phút.
     - Bỏ qua khi đang sao lưu / đổi nguồn / tải; fetch SwiftData lỗi ⇒ bỏ cả nhóm.
  6. **Bản chép thư viện tiện ích cũ** `extension_store/legacy/` khi index ghi đã chuyển xong.
- **Không đụng:** giọng nhân bản, dữ liệu AI, đăng nhập / token, WebKit, sao lưu, file xuất, file cứu hộ `*.corrupt-*` / `*.broken-*`.
- **Dọn an toàn:** quét lại, chỉ xoá mục có ở cả lượt quét người dùng thấy lẫn lượt mới. Kiểm lại từng mục ngay trước khi xoá: đúng thư mục cho phép, ngoài danh sách cấm, không thoát qua symlink.
- Snapshot đã lưu trên máy vẫn đọc được (hai trường mới là optional).
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.919] - 2026-11-13

### feat: Tăng tốc Core ML luôn bật, bỏ màn thử và Nghe thử, không còn cắt chữ ở dấu chấm dính liền như S.H.I.E.L.D

Anh Bửu duyệt plan gộp (§18.2 báo cáo `2026-11-11-vieneu-nano-toi-uu.md`, mockup 7 màn) và luật cắt dấu câu. Phần sheet chọn giọng chung cho Siri / NghiTTS / Google / tiện ích và phần Dung lượng + Dọn rác đi ở bản sau.

- **Tăng tốc Core ML luôn bật** — bỏ công tắc và khoá `vieneuCoreMLEnabled`.
  - `VieNeuCoreMLAccelerator.prepareIfNeeded` tự tải + biên dịch + tự kiểm khi:
    - tải xong gói Nano (`ModelDownloadCenter`);
    - engine Nano khởi động mà gói chưa qua tự kiểm (`VieNeuCoreMLReaderRoute.warmUpIfReady`).
  - Lượt tự chuẩn bị lỗi ⇒ không tự thử lại tới lần mở app sau. Biên dịch / tự kiểm lỗi ⇒ xoá bản biên dịch dở, giữ gói đã tải.
  - Hàng giọng Nano của sheet chọn giọng và hàng "Giọng đọc" của Cài đặt TTS hiện bước đang chạy (`stageText` + thanh mảnh): "Tăng tốc Core ML · tải 52% · 139 / 267 MB", "· biên dịch 3/7", "· tự kiểm chất lượng".
  - "Cần tải" của giọng Nano cộng cả gói Core ML.
- **Bỏ màn thử VieNeu** (`VieNeuTurboLabView`: Đọc liên tục, Đo tự động, Đo nạp Core ML, So EP, Tạo giọng Turbo từ file) và mọi thứ chỉ nó dùng — 42 file, ~6.800 dòng.
  - Đã gỡ:
    - probe Core ML / EP, gói `Static/`;
    - API `setLab*` của engine / service, `preload` / `setSessionCap` của backend Core ML, `Preparer.prepare`, `deleteAll` / `cleanCacheEntries` của gói;
    - khối `fb.graph_optimization` trong bridge.
  - Hàm phần đọc thật còn dùng được chuyển chỗ:
    - SNR / định dạng dB / CFG của golden → `VieNeuCoreMLPreparer`;
    - `sha256` → `VieNeuCoreMLPackage`;
    - chữ bước nhân bản → `VieNeuCloneStageText`.
- **Bỏ phần Nghe thử** của Cài đặt VieNeu TTS và Cài đặt NghiTTS, bỏ màn "Giọng của tôi" cũ (`VieNeuVoiceLibraryView`, `VieNeuVoiceCreatorView`).
- **Cài đặt VieNeu TTS** (`VieNeuTTSSettingsView`, thay `VieNeuTTSTestView`) chỉ hiện thông tin, đọc dung lượng ngoài main:
  - hàng "Giọng đọc VieNeu" ⇒ sheet chọn giọng;
  - Nano: trạng thái, dung lượng, số giọng, gói nhân bản;
  - Tăng tốc Core ML: trạng thái / bước đang chạy, gói, bản biên dịch, phiên bản gói;
  - Turbo: model, giọng đã tải, gói nhân bản;
  - Giọng nhân bản;
  - Tiếng Nhật.
- **Cài đặt NghiTTS** hiện engine, số giọng + dung lượng, thư viện phiên âm, danh sách giọng đã tải và lối vào quản lý.
- **Xoá dữ liệu Nano / Turbo** = nhấn giữ một giọng có sẵn đã tải ở sheet chọn giọng (`VieNeuModelDataRemover`).
  - Dừng trình đọc nếu đang dùng đúng model đó, nhả engine, rồi xoá.
  - Nano xoá cả gói + bản biên dịch Core ML. Giọng nhân bản giữ nguyên.
- **Ô tìm theo tên giọng** ở sheet chọn giọng VieNeu (`VoiceNameSearch`: bỏ dấu, "đ" = "d").
  - Lọc trong chip đang chọn.
  - Đang tìm thì ẩn "Nhân bản giọng đọc"; nhóm không còn giọng khớp thì ẩn cả nhóm.
- **Cắt chữ ở dấu câu** (`TTSPunctuationBoundary`): dấu câu chỉ là chỗ cắt khi theo sau là khoảng trắng / dấu đóng / dấu mở (`.“Đi`) / dấu hết câu khác / hết chuỗi (dấu CJK luôn cắt).
  - Áp ở 4 chỗ: bước cắt chung (`TTSParagraphBuilder`), lớp tách câu của NghiTTS + VieNeu (`NghiUtteranceSegmenter`), bộ tách câu của VieNeu, regex của Piper.
  - Trước đây "Nguyên lai là S.H.I.E.L.D đặc công…" bị NghiTTS / VieNeu xẻ thành sáu lượt "S." / "H." / … rồi đọc ngắt sau từng chữ cái; Google nhận nguyên câu.
  - VieNeu: đoạn ≤ 140 ký tự đi **nguyên văn** một chunk. Bản tham chiếu tách câu theo `[^.!?]+[.!?]*` rồi ghép bằng dấu cách ⇒ "S. H. I. E. L. D".
  - Piper vẫn cắt ở dấu có khoảng trắng phía sau để chèn khoảng lặng (espeak bỏ dấu câu khi phiên âm).
  - Số thập phân vẫn đọc "phẩy" như cũ (đổi số sang chữ chạy trước bước cắt trong engine).
- Dữ liệu cũ màn thử để lại trên máy (`VieNeu/Static/`, báo cáo trong `CoreML/Results/`) sẽ dọn ở Dọn rác (bản sau).
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`; `TTSManager.swift` giữ 3425 dòng; grep chéo mọi type / member đã xoá. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.918] - 2026-11-13

### fix: Bắt đầu đọc tổng hợp đúng đoạn cần nghe trước, tiếng đầu Core ML nhanh hơn khoảng 0,6 s

Log anh Bửu gửi (1.3.917 bật Tăng tốc Core ML, 13:42):
- Tiếng đầu 1,12 s, so với 1,59 s của bản cũ chạy ORT.
- Nhưng trước khi phát app tổng hợp **hai** lượt: đoạn kế tiếp N+1 (656 ms) rồi mới tới đoạn cần nghe N (412 ms).
- Log bản cũ lại chạy N trước ⇒ thứ tự phụ thuộc cuộc đua. Chi tiết ở §17.2 báo cáo `2026-11-11-vieneu-nano-toi-uu.md`.

- **Nguyên nhân (có từ trước P2c, mọi engine local):**
  - `continueStartSpeaking` gọi `warmNghiRefillForPlaybackStart()` (tạo task nạp trước N+1…N+3) **trước** `speakCurrent()` → `playNghiTTS` (task của N).
  - Task nào tới `PiperSynthesisCoordinator` trước thì chạy trước, và bộ điều phối không cắt ngang lượt đang chạy.
- **Sửa** (`TTSManager+NghiPrefetchConcurrency`):
  - Đoạn N chưa có audio và không lượt nạp trước nào đang làm nó ⇒ lúc bắt đầu đọc không nạp trước.
  - `scheduleNghiRefill()` không lập lịch trong lúc `playNghiTTS` đang tổng hợp N theo yêu cầu (`isAwaitingCurrentNghiSynthesis`) ⇒ bảo đảm theo cấu trúc, mọi đường gọi nạp trước đều theo.
  - N có audio thì `playNghiTTS` gọi `updatePrefetchWindow()` như cũ ⇒ nạp trước N+1… bắt đầu ngay.
  - Engine vốn tổng hợp tuần tự nên N+1 không chậm hơn.
  - Sang chương mà đoạn đầu đã tải sẵn ⇒ giữ như cũ.
  - Áp cho NghiTTS, VieNeu Nano (ORT / Core ML) và Turbo.
- **Nút Chuẩn bị của Tăng tốc Core ML** xong ⇒ chạy nạp sẵn + chạy nháp như khi bật công tắc lúc gói đã sẵn.
  - Trước đây chỉ gắn backend, nên các khung chưa được đánh dấu là đã chạy nháp.
  - Giờ log có dòng "Nạp sẵn + chạy nháp".
- **Log `[NghiEnergy]`:** mọi chỗ mở cửa sổ 60 s đi qua `openWindowIfNeeded` (chụp mốc CPU + mốc Core ML).
  - Trước đây `recordUnderrun` mở cửa sổ mà không chụp mốc Core ML.
  - Lượt đọc nào cũng bắt đầu bằng hụt đoạn, nên Summary đầu cộng cả các đoạn Core ML trước đó (`coreMLChunks=37`, `synth=23`).
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`; `TTSManager.swift` giữ 3425 dòng. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.917] - 2026-11-13

### feat: Trình đọc Nano có công tắc Tăng tốc Core ML, nhanh gấp đôi và mát hơn, tự lùi về ORT khi cần

Anh Bửu gửi kết quả Đo tự động chạy một mạch trên gói định dạng 3 (1.3.915 (1252)):
- ORT / Core ML / ORT: RTF 0,27 / 0,14 / 0,27; CPU tiến trình 672 / 243 / 672 s.
- Core ML mát suốt 15 phút (ORT lên ấm sau 1:11 và 5:16); pin tụt 10 / 5 / 10%.
- Hụt tiếng 0, lùi ORT 0/304 đoạn.

Anh duyệt plan P2c (cách B: chờ Core ML nạp đúng khung đoạn đầu cần rồi đọc luôn, khung khác nạp dần). Chi tiết ở §16 báo cáo `2026-11-11-vieneu-nano-toi-uu.md`.

- **Công tắc "Tăng tốc Core ML (thử nghiệm)"**, mặc định tắt, ở Cài đặt VieNeu TTS (`VieNeuTTSTestView+CoreML`). Chỉ áp cho model Nano. Nút "Tải & chuẩn bị":
  - tải gói (theo sha256);
  - biên dịch 7 graph;
  - **tự kiểm golden** (`VieNeuCoreMLPreparer.verify`) — qua mới gắn cho trình đọc;
  - ghi dấu `Results/reader-verified.json` (commit + sha manifest + số bản biên dịch).

  Màn này còn có trạng thái, nút Dừng và nút Xoá (giữ báo cáo của màn thử). Logic ở `VieNeuCoreMLAccelerator`.
- **Gói ghim commit HF** `0d5d13ce` (`VieNeuCoreMLPackage.revision`): thử nghiệm sau ghi đè `nano-coreml/` trên `main` không làm hỏng trình đọc.
- **Chỗ nối** (`VieNeuCoreMLReaderRoute`, gọi được từ mọi luồng):
  - Hàm `synthesizeWithDuration` đúng chữ ký `LocalTTSEngine` (trình đọc, Nghe thử, nghe thử giọng) lấy backend Core ML của trình đọc.
  - Hàm có `flowBackend:` của màn thử dùng đúng giá trị truyền vào (`nil` = ORT), nên lượt ORT của Đo tự động không lẫn Core ML.
- **Nạp sẵn + chạy nháp**: engine Nano khởi động (`VieNeuTTSService.prepare`) ⇒ nền, không chờ, nạp + chạy một lượt input 0 cho VE T64 / T96 / T128, codec T64 / T128.
  - Mỗi khung một lần giữ khoá tổng hợp (`VieNeuTTSEngine.withSynthesisLock`), nên không chồng lên lượt đọc.
  - Khung khác nạp khi gặp.
  - Không biên dịch lúc này: thiếu bản biên dịch ⇒ ORT, Cài đặt báo "Cần chuẩn bị".
  - Bật lại công tắc khi đã sẵn ⇒ nạp ngay.
- **Lùi ORT**:
  - đoạn vượt bucket hoặc giọng khác dạng (thêm kiểm style 50 × 256, speaker 192 trong `canRun`);
  - Core ML lỗi một chunk ⇒ engine chạy lại chunk đó bằng ORT (`VieNeuFlowBackend.fallsBackToORTOnError`, chỉ backend của trình đọc). Lỗi 3 lần ⇒ thôi dùng tới lần mở app sau.
  - Máy báo thiếu RAM ⇒ nhả session, lượt sau nạp lại lười.
  - Nhả engine Nano / chuyển Turbo ⇒ nhả backend.
- **Màn thử dùng chung gói** ⇒ Đo tự động (lúc bắt đầu) và nút Xoá của màn thử nhả backend của trình đọc trước. Nút đổi tên "… (cả của trình đọc)"; xoá cache là xoá dấu tự kiểm.
- **Log để so bật / tắt**:
  - `🎙️ [TTSStart] Tiếng đầu sau X ms · engine · flow` (mốc `startSpeaking` → lần đưa tiếng đầu lên hàng phát);
  - `[NghiEnergy] Summary` thêm `coreMLChunks` / `coreMLFallbacks` của cửa sổ;
  - `[VieNeuPerf]` mỗi lượt thêm `backend=coreml|ort` (đã có sẵn `qos=` của luồng tổng hợp);
  - `[VieNeuCoreML]`: chuẩn bị, tự kiểm, nạp sẵn + chạy nháp, lượt đầu mỗi session, lỗi.
- Để sau: mặc định bật, bỏ nạp ORT VE / codec khi bật, gộp trọng số trùng giữa các bucket, Neural Engine.
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.916] - 2026-11-13

### perf: CI build Release biên dịch từng file song song và bỏ dSYM, bước archive còn khoảng một nửa

Anh Bửu hỏi vì sao CI build càng ngày càng lâu. Bước `Build and Archive App (Unsigned)` chiếm ~90% job, phổ biến 1000–1560 s.

**Nguyên nhân** (41 lượt xanh 10–13/11 + 2 vòng đo trên nhánh thử `exp/ci-timing`):
- Mã Swift `Sources/` tăng 2,5× từ 1/10 (4,5 MB) tới 13/11 (11,5 MB); riêng 10/11 → 13/11 thêm 10%.
- Release biên dịch cả module FreeBook trong **một** tiến trình (`-O -whole-module-optimization -g`). Bộ đếm của frontend (1174 s): tối ưu SIL 607 s (52%, gần như một luồng), type-check 165 s, IRGen 133 s, LLVM 128 s. RAM lên ~5 GB trên runner 7 GB ⇒ swap 0,5–0,7 GB.
- Runner dùng chung lệch tới ~2×: lượt 562 s ngày 10/11 là gặp máy nhanh — lượt ngay sau chỉ thêm 1 file mất 1241 s.

**Đo cặp cùng máy** (mỗi runner chạy 2 cách nối tiếp; số là thời gian `xcodebuild archive`, s):

| Cách | Archive | Cặp cùng máy | Binary |
|---|---|---|---|
| WMO `-O -g` (cũ) | 1137–1330 | — | 54,24 MB |
| WMO, bỏ debug info | 804–1158 | 1216 → 804 | 54,08 MB |
| `singlefile` `-O -g` | 499–719 | 1224 → 706, 1330 → 499, 1310 → 719 | 52,34 MB |
| `singlefile`, bỏ debug info (**chọn**) | 490–619 | 1137 → 490 | 52,17 MB |

App nén ~41,0 MB (IPA cũ 42,2 MB, dưới giới hạn 50 MB của Telegram).

**Thay đổi** — `project.yml`, target FreeBook, `settings.configs.Release` (gói SPM giữ mặc định):
- `SWIFT_COMPILATION_MODE: singlefile` — biên dịch từng file, batch mode 3 luồng.
- `DEBUG_INFORMATION_FORMAT: dwarf` + `GCC_GENERATE_DEBUGGING_SYMBOLS: NO` — không `-g`, không sinh dSYM (188 MB mỗi lượt, không ai dùng: archive không tải lên, binary đã strip).

**Đánh đổi** (anh Bửu duyệt mức 1 + 2): mất tối ưu xuyên file (inline / specialize / suy `final`) ⇒ code Swift tính nặng (khử nhiễu STFT, fbank, tách từ VietPhrase, chuẩn hoá chữ) có thể chậm hơn chút — chưa đo trên máy. ORT / Core ML / audio.cpp không đổi. So RTF với bản trước 1.3.916 thì nhớ điều này.

**Chưa làm**: tách các view type-check chậm (58 thân hàm > 200 ms, cộng 63 s; nặng nhất `ReaderView.readerObserverLayer` 13,3 s, `ReaderAINameReviewCardView.body` 4,4 s, `DiscoveryView.body` 3,3 s) — chỉ lợi vài phần trăm; cache gói SPM — lợi ~30–50 s, thêm rủi ro cache cũ.

`CLAUDE.md` + `AGENTS.md`: thêm đoạn "Chế độ biên dịch Release".

## [1.3.915] - 2026-11-13

### feat: Gói Core ML Nano định dạng 3 lưu trọng số Gemm chuyển vị để Core ML không ghi trọng số thành chữ trong model

Anh Bửu gửi kết quả P2b-0 của bản 1.3.913 (1251):
- Tắt tối ưu ORT lúc chạy không đổi được gì: bản mới trùng bit bản cũ (∞ dB), `model.mil` vẫn 549 MB.
- 5 dòng dài nhất của `model.mil` đều là hằng `linear_onnx__MatMul_…_t` — đúng tên Gemm builder của Core ML EP đặt khi chuyển vị B.
- Nguyên nhân: `ort_basic` của script xuất chạy ORT mức BASIC trên PC và lưu graph đã tối ưu, nên `Gemm(transB=0)` đã gộp sẵn **trong file ONNX**.

Anh duyệt plan P2b-1. Chi tiết ở §14 báo cáo `2026-11-11-vieneu-nano-toi-uu.md`.

- **Script xuất** `Scripts/vieneu_nano_coreml_export.py`, định dạng 3:
  - `gemm_weights_to_transb`: mỗi Gemm `transB=0` có B là initializer ⇒ lưu Bᵀ, đặt `transB=1`. Làm trước khi tách file trọng số dùng chung. Đã đổi VE 80 node / bucket, codec 20 node / bucket.
  - Kiểm không còn Gemm `transB=0` nào có B là initializer.
  - Với `transB=1`, Core ML EP (`gemm_op_builder.cc`) tham chiếu initializer theo tên ⇒ trọng số vào `weight.bin`. Op `linear` và giá trị trọng số không đổi.
- **Kiểm trên PC**, gói mới so với gói định dạng 2:
  - tự kiểm golden 14 dòng giống hệt;
  - ORT CPU với input ngẫu nhiên: mọi graph VE / codec trùng từng bit;
  - `ve_main.weights` / `codec.weights` **cùng số byte**, khác sha; mỗi graph vẫn chỉ trỏ một file trọng số dùng chung;
  - khoá cache Core ML đổi theo graph.
- **Đã tải lên kho HF** `raikiri1498/VieNeu-TTS/nano-coreml/` (commit `0d5d13ce`); tải ẩn danh khớp sha256.
- **App** `VieNeuCoreMLPackage`:
  - `supportedFormat = 3`.
  - `download()` giữ một file chỉ khi **đúng dung lượng và đúng sha256**: sha lấy từ manifest cũ trên máy, khác hoặc chưa có thì băm file. Lý do: file trọng số chuyển vị cùng số byte, so dung lượng thì giữ trọng số cũ đi với graph mới ⇒ ra sai mà không báo lỗi.
  - Manifest mới chỉ ghi đè bản cũ sau khi đủ file.
  - Trả `DownloadResult` (số file tải, có xoá cache không).
  - Có file mới ⇒ xoá cả `Cache/` (4 GB cũ) lẫn `Cache-noopt/` còn lại của 1.3.913.
- **"Đo nạp Core ML" đổi sang P2b-1** (`VieNeuCoreMLGraphCheck`, `VieNeuCoreMLGoldenSpeedCheck`):
  1. tự làm mới gói trước (không cần chạy Đo tự động trước);
  2. dựng session lần đầu VE T64 + codec T64, ghi số partition;
  3. đo dung lượng và dòng dài nhất `model.mil`;
  4. nạp Core ML gốc + ORT, mỗi cách 2 lần;
  5. golden dB so với số của định dạng 2 (latent 102,5 / 106,3, sóng âm 85,7 / 101,4 — báo "trùng số cũ");
  6. tốc độ mỗi lượt so với 42,4 ms/lượt VE và 99 ms codec, ±10% là "như cũ".
- Bỏ phép thử tắt tối ưu của 1.3.913: `VieNeuCoreMLNoOptTrial` / `Comparison`, cờ `disablesGraphOptimization` của backend. Khoá `fb.graph_optimization` của bridge giữ lại (vô hại).
- App cũ (gói định dạng 2) gặp gói mới thì báo "định dạng 3 — app này chỉ hiểu 2", không trộn file.
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.914] - 2026-11-13

### chore: Giữ mọi release build trên GitHub, nguồn LiveContainer vẫn liệt kê 5 bản mới nhất

Anh Bửu: *"vì github đâu giới hạn số lần realease nên bỏ giới hạn 5 realease được nhỉ"*. Anh duyệt plan.

- `Scripts/ci/publish_altstore_source.py`: bỏ `prune_releases`, nên không xoá release `build-*` cũ hay tag của nó nữa.
  - GitHub không giới hạn số release hay tổng dung lượng file đính kèm; mỗi file chỉ phải dưới 2 GiB. Mỗi IPA hiện ~42 MB.
  - Chạy lại một lượt build cùng số vẫn xoá rồi tạo lại đúng release đó, như cũ.
- `apps.json` (nhánh `source`) vẫn chỉ liệt kê `--keep 5` bản mới nhất, để file nguồn mà LiveContainer và app đọc thường xuyên không phình theo số bản build. Bản cũ hơn tải được ở trang Releases.
- Cập nhật chú thích bước đăng ở `build-ipa.yml`, và đoạn "Nguồn cập nhật LiveContainer" trong `CLAUDE.md` + `AGENTS.md`.
- Có hiệu lực từ lượt build kế tiếp có đổi `Sources/**` hoặc `project.yml`. Lượt build 1.3.913 đang chạy vẫn dùng script cũ, nên còn xoá bản cũ nhất một lần.

## [1.3.913] - 2026-11-13

### feat: Đo nạp Core ML thử bản tắt tối ưu đồ thị ORT để trọng số không còn bị ghi thành chữ trong model

Anh Bửu gửi kết quả Đo nạp Core ML 1.3.912 (1250):
- Nạp chậm là của chính Core ML: Core ML gốc nạp VE T64 mất 18–20 s, gần bằng ORT + Core ML EP (20–21 s), trong khi ORT CPU chỉ 0,6 s.
- Nguyên nhân: trọng số nằm **trong chữ** `model.mil` (VE 549 MB, codec 323 MB), còn `weight.bin` chỉ 10–15 MB. Đây cũng là 4,16 GB cache.
- Đã xác minh trong mã ORT 1.24.2:
  - `MatMulAddFusion` chạy ở mức 1 cho mọi EP và gộp MatMul + Add thành `Gemm(transB=0)`;
  - Core ML EP chuyển vị B của Gemm thành hằng immediate (`AddConstant` → `CreateTensorValue`).

Anh duyệt plan P2b-0: chỉ đo, không đụng đường đọc truyện. Chi tiết ở §13 báo cáo `2026-11-11-vieneu-nano-toi-uu.md`.

- **Bridge** `VieNeuONNXProbeBridge.m`: khoá riêng `fb.graph_optimization` (`disable` / `basic` / `extended`). Bridge bóc khoá ra trước khi đưa tuỳ chọn cho EP, rồi đặt mức tối ưu đồ thị của session.
- **Bản tắt tối ưu**:
  - `VieNeuCoreMLFlowBackend` có thêm `disablesGraphOptimization`, và `coreMLOptions(package:disablesGraphOptimization:)` thêm khoá trên + đổi cache sang `Cache-noopt/`.
  - Thư mục riêng vì khoá cache lấy từ metadata graph; dùng chung thư mục là nạp lại bản cũ.
  - Lượt đọc và đo tự động không đổi.
  - Tải lại gói / Xoá thì dọn cả hai thư mục cache.
- **"Đo nạp Core ML" chạy phép thử P2b-0** (`VieNeuCoreMLLoadWorker`, `VieNeuCoreMLNoOptTrial`, `VieNeuCoreMLNoOptComparison`):
  1. kiểm kê bản biên dịch hiện tại;
  2. đọc lướt `model.mil` hiện tại (VE / codec bucket nhỏ nhất), liệt kê dòng dài nhất kèm tên + kiểu hằng (`VieNeuCoreMLMilScan`, khối 4 MB + `memchr`);
  3. biên dịch VE + codec bucket nhỏ nhất ở bản tắt tối ưu: thời gian, số partition, dung lượng;
  4. nạp bằng Core ML gốc (kèm lượt đoán đầu) và ORT + Core ML EP, mỗi cách 2 lần;
  5. cùng đoạn golden qua hai bản: dB so tham chiếu PC, dB giữa hai bản, trung vị thời gian mỗi quỹ đạo VE / mỗi lượt VE / mỗi lần codec.
- Phát hiện biên dịch lại nay dựa vào thời gian + ngày sửa `model.mil`; bỏ dòng partition trong log và `weight.bin`. Đính chính §13: cờ "ORT ghi lại gói" của 1.3.912 là báo nhầm (log INFO in partition mọi lần, ORT tạo lại `weight.bin` rỗng mỗi lần dựng session).
- Bỏ bước băm trọng số và thử bỏ bản thừa của 1.3.912 (đã có câu trả lời: hai bản `weight.bin` là clone APFS).
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử trên máy.
