# CHANGELOG - Nhật ký Thay đổi CodeGraph Tàng Công Các

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **Tàng Công Các**.

## [1.3.957] - 2026-11-16

### fix: Giọng dự phòng tổng hợp các đoạn đúng thứ tự và bật ngay khi lượt nạp trước lỗi vì mất mạng

Log build 1285 (bản 1.3.956, chương 24): không còn dòng `Nạp sẵn + chạy nháp` nào và đoạn dự phòng thứ 2 trễ **459 ms** thay cho 5178 ms của build 1283 — nhưng vẫn trễ. Dựng lại theo số byte của từng lượt phát: đoạn 21 phát lúc 13:13:04.15, ba lượt nạp trước 22 / 23 / 24 được tạo cùng lúc, và hàng đợi tổng hợp chạy **23 → 22 → 24**. Đoạn 23 (9,5 s tiếng, session Core ML còn nguội) mất 2,8 s; đoạn 22 chỉ bắt đầu lúc 07.02 trong khi cần lúc 07.22.

- **Nguyên nhân:** mỗi lượt dự phòng phải qua `service.prepare` (nhiều điểm chờ: nhả Turbo, `Task.detached`, khoá engine) rồi mới vào `PiperSynthesisCoordinator`, nên trong ba lượt tạo cùng lúc lượt nào tới trước là ngẫu nhiên; hàng đợi đang rảnh thì chạy luôn lượt tới trước và không ngắt giữa chừng. Việc nâng mức ưu tiên của 1.3.955 chỉ xếp lại lượt **đang chờ**, không cứu được trường hợp này.
- **Sửa:** lượt nạp trước nối đuôi lượt nạp trước tạo ngay trước nó (`TTSOnlineFallbackState.prefetchTail`) — chờ lượt đó xong rồi mới `prepare` và vào hàng đợi, nên thứ tự tổng hợp luôn là thứ tự tạo (đoạn gần trước). Đoạn **đang đọc** không nối đuôi: đi thẳng; nếu lượt nạp trước của chính nó còn xếp hàng (`hasStarted == false`) thì bỏ lượt đó và tạo lượt mới, đã rời hàng thì dùng chung + `promote` như cũ. Tập `demanded` / `isDemanded` của 1.3.955 thay bằng `started` / `hasStarted`.
- Với thứ tự đúng, ở log này đoạn 22 (cùng cỡ khung với đoạn 21 vừa chạy) xong sau ~0,65 s, sớm hơn lúc cần ~2,3 s.
- **Bật dự phòng sớm khi mất mạng** (anh Bửu duyệt: "Thêm bật dự phòng sớm"). Cùng log: đoạn dự phòng **đầu tiên** trễ ~1,9 s (`RemoteHandoff index=21 gapMs=1918`) vì chỉ bắt đầu tổng hợp khi tiếng online đã nạp phát hết, dù mạng mất từ 13:12:51 — 11 s trước đó — và các lượt nạp trước online lỗi liên tục. `handleOnlinePrefetchFailure` (1.3.953) chỉ bật dự phòng khi lỗi là hết giờ; nay bật cả khi lượt nạp trước lỗi lúc `TTSNetworkReachability` báo máy không có mạng (và đang đọc): bỏ các lượt nạp trước online đang chờ rồi `updatePrefetchWindow()` ⇒ các đoạn còn thiếu trong cửa sổ được tổng hợp bằng giọng dự phòng ngay trong lúc tiếng online đã nạp còn phát. Tiếng online đã nạp giữ nguyên; lỗi nội dung lúc vẫn có mạng thì im như cũ.
  - Hệ quả thấy được: toast "Mất mạng — đọc bằng giọng dự phòng" hiện sớm hơn (lúc lượt nạp trước đầu tiên lỗi, không phải lúc hết tiếng online); mạng có lại trong vài giây đó thì các đoạn đã nạp bằng giọng dự phòng vẫn phát hết rồi mới về online (luật cũ của 1.3.945).
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.956] - 2026-11-16

### fix: VieNeu Nano đọc đúng hậu tố xưng hô, thêm khoảng dẫn cho dòng thoại, không cắt chunk giữa tên và các lỗi rà soát khác

Sửa tiếp các phát hiện của lượt rà soát mã VieNeu Nano (cùng ngày với 1.3.955).

- **Hậu tố `kun` / `san` / `chan` / `tan` / `chin` giờ được đọc theo âm tiết.** `VieNeuRomajiSyllabifier.syllables(of:)` trả `nil` cho từ dưới 2 âm tiết nên 5/10 mục của `honorifics` là mục chết — "Sasuke-kun" chỉ đổi "Sasuke", còn "kun" đi vào `SeaG2P` đọc kiểu tiếng Anh. Thêm tham số `minimumSyllables` (mặc định 2, luật nhận tên không đổi); `VieNeuJapaneseNameReader.honorificPhonemes` gọi với 1 ⇒ `kˈun`, `sˈaːn`, `tʃˈaːn`… đúng các luật phiên âm đã duyệt. Bản chép Python của bộ cắt (`Scripts/gen_vieneu_romaji_english_lookalikes.py`) chỉ dùng mặc định nên không phải sửa.
- **Đọc lai không còn chuyển sang Turbo vì hậu tố.** `VieNeuForeignTextClassifier` tách token ở gạch nối nên "sensei" / "senpai" / "sama" của "Kakashi-sensei" bị tính là tiếng nước ngoài dù bộ tiền xử lý đã đọc chúng theo âm tiết. Giờ bộ phân loại theo dõi phần đầu của cụm gạch nối và hỏi `VieNeuJapaneseNameReader.readsSuffix(_:afterHead:)`.
- **Khoảng dẫn cho đoạn mở đầu bằng dấu mà vocab không có.** `withLeadIn` xét theo ký hiệu đầu tiên **có trong vocab**: dấu nháy mở của dòng thoại (`normalizeVietnameseText` giữ lại, `encode` bỏ đi) trước đây làm chunk bị coi là "đã mở đầu bằng dấu câu" nên không có khoảng dẫn. Phần bị bỏ ở đầu được cắt khỏi chuỗi (ids không đổi; chỉ không còn đếm vào `dropped=`). Dấu có trong vocab đứng đầu thì như cũ. Log build 1283 cho thấy dấu hai chấm không có trong vocab; dấu nháy có hay không thì **chưa xác minh** được từ repo.
- **Cắt chunk không tính ký hiệu bọc phiên âm và không cắt giữa tên.** `VieNeuTTSEngine+Chunking` đo độ dài bằng `length(_:)` (bỏ `SeaG2P.rawPhonemeOpen` / `Close`) — trước đó "Sasuke" 6 chữ thành 18 ký tự nên đoạn nhiều tên bị tách chunk sớm; `balancedCut` có thêm luật chặn `splitsName` (hai âm tiết bọc đứng liền nhau).
- **Khung "miễn phí" chỉ có khi chunk chạy được bằng Core ML.** `runChunk` hỏi `canRun` trước khi hỏi trần cỡ khung: chunk sẽ lùi ORT vì chuỗi token dài hơn graph / giọng khác dạng thì không còn được thêm tới +30% khung như thể miễn phí (ORT ⇒ đúng `minimumBoost`, chế độ Miễn phí ⇒ không thêm).
- **`coreMLChunks` đếm sau khi codec xong** (`VieNeuCoreMLFlowBackend.decode`): codec lỗi rồi chạy lại ORT không còn bị tính là chunk Core ML (badge "Nano · Core ML" sai).
- **Dọn mã chết của màn thử đã bỏ (1.3.919):** `lastDroppedScalars` / `lastChunkCount` / `lastPhonemeSample` / `lastSpeechDuration` / `lastTiming` / `lastVectorMs` / `lastOtherMs` của `VieNeuTTSService`, `Output.phonemeSample` của engine (mỗi lượt ghép chuỗi phoneme mọi chunk cho không ai đọc), `Timing.vectorMs` / `otherMs`.
- **Chưa sửa, chờ anh Bửu quyết:** luật 2 của `VieNeuNameFrameBoost.isNameChunk` nhận nhầm cặp Hán Việt thanh ngang ("Tu La", "Ma Tu", "Hư Vô") là tên phiên âm — luật do anh nghe và duyệt. RTF trên badge vẫn chia cho `pcmDuration` (gồm khoảng lặng) — công thức anh đã duyệt ở 1.3.954 và dùng chung với Piper.
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.955] - 2026-11-16

### fix: Giọng dự phòng VieNeu không còn hụt đoạn offline thứ 2 do chạy nháp Core ML lặp lại ở mỗi đoạn

Anh Bửu: *"tắt mạng sau khi đọc xong cache audio online thì phát được ngay giọng offline nhưng lại hụt đoạn offline thứ 2"*. Log build 1283 (chương 7, giọng dự phòng VieNeu Nano): tiêu đề phát sau 1,7 s, đoạn kế trễ **5,18 s** (`RemoteHandoff index=1 gapMs=5178`), các đoạn sau 30–40 ms. Ba nguyên nhân chồng nhau:

- **Chạy nháp Core ML lặp lại ở mỗi đoạn.** `TTSManager.onlineFallbackAudio` gọi `service.prepare` cho **từng** đoạn dự phòng, mà `VieNeuTTSService.prepare` lần nào cũng bắn `warmUpCoreMLForReader()`; `warmUpIfReady` chỉ chặn hai lượt chạy cùng lúc, không chặn lượt lặp ⇒ 4 lượt chạy nháp trong 20 s (5493 / 3150 / 1583 / 5800 ms). Sửa: `VieNeuCoreMLFlowBackend.isWarm(kind:bucket:)` (session đang nạp **và** đã chạy lượt đầu) + `VieNeuCoreMLReaderRoute.pendingWarmUp` — chỉ chạy nháp khung còn thiếu, đủ rồi thì thoát ngay (không đọc gói, không log). `releaseSessions()` (máy báo thiếu RAM) quên luôn `firstRunDone` ⇒ lần `prepare` sau chạy nháp lại đúng các khung đã nhả.
- **Lượt chạy nháp giữ khoá tổng hợp liền cả 5 khung.** `NSLock` không xếp hàng công bằng: luồng chạy nháp nhả khoá rồi lấy lại ngay ở khung kế nên thắng luồng đang chờ — trong log, từ 11:19:11.53 tới 15.51 không lượt tổng hợp nào chen vào được. Sửa: `VieNeuTTSEngine.lockForReader()` (dùng ở `synthesize` và `prepare`) đếm lượt đọc đang xếp hàng; `withSynthesisLock` chỉ lấy khoá khi khoá rảnh và không ai xếp hàng (`lock.try()`, hỏi lại mỗi 10 ms). Lượt đọc tới giữa một khung chỉ chờ hết khung đó — có tác dụng cả ở lần chạy nháp đầu tiên (engine Nano vừa nạp lúc giọng dự phòng bật).
- **Đoạn đang chờ phát bị xếp sau các đoạn nạp trước.** Ba lượt nạp trước cùng mức `.immediateSuccessor`, kẹt ở `prepare` (chờ khoá engine) rồi vào hàng đợi theo thứ tự ngẫu nhiên: log tổng hợp đoạn 3 → 2 → 1 trong lúc đoạn 1 đang chờ để phát. Sửa: lượt dự phòng mang khoá tổng hợp (`onlineFallbackSynthesisKey`: engine + giọng + tốc độ + ranh giới + chữ); đoạn đang đọc dùng chung lượt nạp trước đang chạy thì `PiperSynthesisCoordinator.promote(…, to: .demand)`, và lượt chưa kịp vào hàng đợi đọc `TTSOnlineFallbackState.isDemanded` để xếp thẳng ở mức `.demand`.
- Đoạn 66 ký tự mà phiên WorkBuddy gọi là "mồ côi, không bao giờ phát" thật ra là **đoạn 3** (`bytes=192044` = 4,00 s, phát lúc 11:19:28) — không có tiếng nào bị bỏ.
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử trên máy. Thử: tắt mạng giữa chừng, nghe ≥ 5 đoạn offline; log không còn dòng `Nạp sẵn + chạy nháp` lặp lại và `RemoteHandoff … gapMs` của đoạn 1 về cỡ vài chục ms (lần đầu engine Nano còn nguội có thể vẫn chờ nạp session).

## [1.3.954] - 2026-11-16

### feat: hiển thị RTF của VieNeu và Piper trên sheet điều khiển nhanh TTS

Anh Bửu yêu cầu mockup "hiển thị thêm badge rtf của vieneu" rồi bổ sung *"hiển thị rtf cho có pipetts luôn nhé"*. RTF = thời gian tổng hợp ÷ thời lượng audio (0,32 = nhanh ~3× thời gian thực, > 1 = chậm hơn thời gian thực) — số **đo trong engine**, không ước lượng.

- **`TTSEngineRTFStore`** (mới, `Services/TTS/`): kho RTF theo **chữ đã nói** (cùng khoá với `VieNeuEngineBadgeStore`, capacity 64) — ghi từ cả VieNeu (Nano/Turbo) và Piper/NghiTTS. Số đo lấy trong engine, không lẫn thời gian chờ hàng đợi (`queueWaitMs` của Piper bị loại).
- **`TTSRTFBadge`** (mới, `Views/TTSWidget/`): viên nhỏ kiểu `TTSEngineBadge` — icon `gauge.with.dots.needle.50percent` + `"RTF 0.32"` (`monospacedDigit`), nền capsule 18%. Màu theo ngưỡng: ≤ 0,5 xanh · 0,5–1,0 vàng · > 1,0 đỏ.
- **Ghi số:** Nano tại chỗ ghi badge cũ (`VieNeuTTSService` — có sẵn `output.synthesisMs` + `output.pcmDuration`); Turbo **dời** lệnh ghi badge xuống sau khi tính `synthesisMs`/`pcmDuration`; Piper ghi trong `PiperTTSService.synthesizeWithDuration` (trả sẵn `payload.synthesisMs`/`payload.pcmDuration`).
- **Hiện:** `TTSQuickControlSheet.NowReadingBlock` thêm viên RTF ngay sau badge "Turbo · AMX"; `TTSQuickControlNowReading.Snapshot` thêm `rtf`, tách `spoken` (chữ đã áp quy tắc thay thế) khỏi nhánh VieNeu để tra cho mọi engine. Đoạn chưa tổng hợp xong (chưa có số đo) ⇒ viên ẩn.
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.953] - 2026-11-16

### feat: TTS online có cấu hình timeout và số lần thử lại, có giọng dự phòng thì chuyển offline sau 3 giây

Anh Bửu: *"giảm thời gian timeout của các ext tts online khi có giọng offline backup"* ⇒ hỏi từng nhánh (grill-me) rồi mới code. Trước đây mỗi engine tự quyết: `ExtTTSService` retry cứng 2 lượt, Google TTS không retry, và **không** có giới hạn thời gian chờ (fetch của extension mặc định 15 s, script tự đặt tới 120 s) ⇒ đoạn đang đọc có thể im lặng ~30 s trước khi giọng dự phòng lên tiếng.

- **Hai cấu hình ở Cài đặt TTS › mục "TTS online"** (chỉ hiện khi trình đọc chính là online — Google Cloud TTS / TTS tiện ích; mỗi hàng có nút "?" giải thích):
  - **Số lần thử lại**: 0–5, mặc định **3** (= số lần *thử lại*; 0 = chỉ thử một lần). Retry **mọi lỗi** (trừ `CancellationError`).
  - **Timeout mỗi lượt thử**: 5–20 s, mặc định **7 s**.
  - Đã chọn giọng dự phòng offline ⇒ hai hàng **tự khoá**: hiện **0** lần thử lại và **3 giây** timeout (cứng) — lúc đó có tiếng thay thế nên không cần chờ thử lại.
- **Một chỗ điều khiển** — `TTSAudioSynthesisWorker.synthesizeParagraph` (điểm chặn duy nhất của mọi lượt tổng hợp online: playback, nạp trước, prefix chương kế):
  - `withTimeout` huỷ **thật** khi hết giờ: huỷ Task con ⇒ `JSExecutor.callAsync` gọi `cancelCurrentExecution()` (`JSExecutor.swift:949`) huỷ `URLSessionDataTask` đang chờ; Google thì `URLSession` bị huỷ theo Task ⇒ không rò tiến trình.
  - `withRetry` **bên trong** closure của `RemoteTTSSynthesisCoordinator` ⇒ đoạn đang đọc giữ slot liền mạch. (Đặt *ngoài* coordinator thì tệ hơn: lúc một lượt thử hụt, `complete()` gọi `startNextIfNeeded()` ngay trong cùng lượt actor ⇒ lượt nạp trước chiếm slot trước khi lượt retry kịp xếp lại ⇒ đoạn đang đọc nhận lỗi muộn ~33 s thay vì ~22 s.)
  - Retry chỉ cho **đoạn đang đọc** (`priority == .current`); lượt nạp trước thử **một** lần rồi bỏ (server chết thì thử lại vô ích mà lại tốn slot hàng đợi).
- **Gỡ retry khỏi `ExtTTSService`** (tránh nhân đôi 4 × 2 = 8 lượt); xem thử giọng trong sheet (`TTSVoicePreviewPlayer`) gọi thẳng service nên tự thử lại 2 lượt như cũ.
- **Lượt nạp trước hụt timeout ⇒ bật giọng dự phòng ngay** (`TTSManager+OnlineFallbackPrefetch`): trước đây lỗi nạp trước chỉ được log ⇒ app phát nốt tiếng cache tới hết cửa sổ nạp trước (~10–30 s) mới chuyển offline. Chỉ **lỗi timeout** mới kích hoạt (triệu chứng server chết chung); lỗi nội dung (voice sai, base64 hỏng) thì im như cũ, chờ đoạn đang đọc quyết định. Khi bật theo đường này: **không** huỷ lượt đang đọc, **không** huỷ lượt nạp trước khác, **không** xoá tiếng đã nạp — chỉ các đoạn từ đoạn lỗi trở đi mới chuyển sang giọng dự phòng.
- **Sửa race:** lượt đang đọc đang bay lỗi *sau khi* giọng dự phòng đã bật ⇒ `switchToOnlineFallback` trước đây trả `false` ⇒ dừng đọc + báo lỗi; nay đọc lại đoạn đó bằng giọng dự phòng.
- **Lượt thử của probe** (quay về online) cũng gói timeout 3 s để kết luận nhanh khi server chậm; nhịp probe 15 s → ×2 → trần 120 s giữ nguyên.
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.952] - 2026-11-15

### feat: Nano đọc chậm đoạn có tên phiên âm để không nuốt chữ, dùng phần khung Core ML tính sẵn nên gần như không tốn thêm pin

Anh Bửu: *"vẫn có mất chữ … mất giữa đoạn chứ không ở chỗ dấu"*, *"Chữ Goku rất hay mất chữ"* (nghe thành "gu"). Anh nghe 12 file riêng (bám chữ CFG 3 / 4,5 / 6 × 4 lượt): lượt nào mất thì mất ở **mọi** mức ⇒ nhiễu khởi đầu quyết định, bám chữ không chữa. Đo 30 lượt trên PC cùng câu "Son Gô Cu cười trả lời…": CFG, biên độ nhiễu, CFG chỉ theo chữ, sway, 16 bước, cách viết phiên âm đều không giảm (5–11/30 so với 8/30); chỉ **số khung** giảm đều theo nấc — 62 khung 8/30 → +4% 5 → +9% 3 → +14% 2 → +20% 1 → +29% 0. Anh hỏi ảnh hưởng nhiệt trước khi làm ⇒ tìm ra phần miễn phí: Core ML tính trọn cỡ khung cố định nên khung thêm tới trần cỡ đang dùng không tốn phép tính. Anh chọn **"Miễn phí + tối thiểu 10%"**.

- **`VieNeuNameFrameBoost`** (mới, `Services/TTS/VieNeu/Names/`): `isNameChunk` nhận đoạn có tên phiên âm theo âm tiết — ≥ 2 âm tiết do `VieNeuJapaneseNameReader` sinh (đếm `SeaG2P.rawPhonemeOpen`) **hoặc** ≥ 2 chữ viết hoa liền nhau là âm tiết mở không dấu thanh ("Gô Cu", "Na Ru Tô"; dấu câu cắt chuỗi; tên Hán Việt không dính). `frames(base:mode:limit:freeCeiling:)`: đích +30%; `free` = dừng ở trần cỡ khung đang dùng; `freeWithMinimum` (mặc định) = chưa đủ +10% thì nhảy lên cỡ lớn hơn rồi dùng luôn phần trống của cỡ đó, không nhảy khi vượt cỡ lớn nhất (Core ML sẽ lùi ORT); chạy ORT thì thêm đúng +10%. Khoá `vieneuNameFrameBoostMode`.
- **`VieNeuFlowBackend.freeFrameCeiling(for:)`** (mặc định `nil`); `VieNeuCoreMLFlowBackend` trả cỡ nhỏ hơn giữa cỡ vòng Euler và cỡ codec.
- **`VieNeuTTSEngine.runChunk`** nhận `nameBoost`, tính `frames` từ `baseFrames`; `Timing.nameBoostChunks` / `nameBoostFrames` ⇒ log `[VieNeuPerf] … nameBoost=<số chunk>/+<số khung>`.
- **Cài đặt**: hàng chọn "Đọc chậm đoạn có tên (Nano)" (Tắt / Miễn phí / Ít nhất 10%) ở Cài đặt TTS (mục Quản lý riêng của VieNeu) và màn Giọng dự phòng, cùng `VieNeuJapaneseFlags.nameFrameBoost`; giải thích sau nút "?" (`nameFrameBoostHelp`). Fingerprint giọng dự phòng thêm chế độ này. Trình đọc chính: theo luật `TTSSettingsSnapshot` (không gồm `vieneu*`), đoạn đã nạp trước giữ cài đặt cũ.
- **Số ước trên chương Dragon Ball của log build 1280** (bản chép Python của luật, cỡ khung giả định 64/96/128/160): 19/48 đoạn có tên; "Miễn phí" thêm khung trung vị +29% (thấp nhất +3%), phép tính Core ML +0%; "Ít nhất 10%" thêm trung vị +30% (thấp nhất +12%), phép tính cả chương +2,9%, tiếng cả chương dài thêm ~13% (đoạn có tên đọc chậm đi đúng mức thêm, không bù ở tốc độ phát).
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử máy — phần tiếng chờ anh nghe trên iPhone.

## [1.3.951] - 2026-11-15

### fix: Màn Giọng dự phòng có thêm công tắc Đọc tên Nhật theo âm tiết

Anh Bửu: "giọng dự phòng thiếu config phiên âm mới". Màn Giọng dự phòng (`TTSFallbackVoiceSettingsView`) tự dựng mục Quản lý riêng của VieNeu nên không có hàng mới của 1.3.950.

- Thêm `Toggle("Đọc tên Nhật theo âm tiết")` ngay dưới "Áp dụng từ điển phiên âm VieNeu", cùng `VieNeuJapaneseFlags.nameSyllablesEnabled` (một khoá `vieneuJapaneseNameSyllablesEnabled` cho cả trình đọc chính lẫn giọng dự phòng — như công tắc từ điển).
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử máy.

## [1.3.950] - 2026-11-15

### feat: VieNeu đọc tên riêng kiểu Nhật theo âm tiết thay vì theo luật chính tả tiếng Anh

Anh Bửu: Nano "hay bị mất chữ" ở tên riêng. Đo: bản Swift của sea-g2p không chép sai (172 tên: 141 có trong từ điển 1,16 triệu mục; 31 từ lạ thì 25 trùng bản gốc Rust 0.9.1), không ký hiệu nào rơi khỏi vocab — nhưng từ điển đọc mọi chữ Latin không dấu theo luật **tiếng Anh** nên tên Nhật mất chữ ngay ở bước phiên âm ("Sasuke" → `sˈæsuːk`, "Takemichi" → `tˈeɪk mˈɪtʃaɪ`, "Akame" → `ˈækeɪm`). Anh nghe mẫu rồi chốt từng nhóm âm (mẫu C, E, F cách A).

- **`VieNeuRomajiSyllabifier`** (mới, `Services/TTS/VieNeu/Names/`): gộp trường âm (`ou`, `uu`, `oo`, `ei`, `ii`, `aa`, `ee`, `oh` cuối âm tiết; `oue` giữ `u` — "Inoue"), cắt âm tiết chặt (n / m cuối âm tiết, âm ngắt, âm ghép) rồi **sinh thẳng phiên âm**: âm tiết thường = phụ âm đầu + `ˈ` + nguyên âm (`sˈaː sˈu kˈe`); `ji` → `zˈi`, `tsu` → `sˈu`; hàng y dùng `j`; âm ghép theo cách A (`kyo` → `kˈi ˈo`, `ryu` → `ɹˈiw`, không dùng cụm `kj` / `ɹj` / `ts` — Nano đọc không ra); `ai / oi / ui` → đuôi `j`; âm ngắt → `ɜ` + phụ âm cuối (`hˈaːɜt̪ t̪ˈo ɹˈi`). Không đi qua chính tả Việt: bảng `romajiToViSyllable` cho "gi", "ic ki", "hôc", hàng y = "da / du / dô" mà `SeaG2P` đọc sai.
- **`VieNeuJapaneseNameReader`** (mới): từ được đổi khi (1) viết hoa chữ đầu, toàn Latin không dấu, ≥ 4 chữ — xét sau khi `foldMacrons` đã gấp ā ī ū ē ō, gấp thêm `û` / `î`; (2) cắt được hết thành âm tiết romaji; (3) không phải âm tiết Việt không dấu (`VietnameseWordChecker`); (4) không thuộc `VieNeuRomajiEnglishLookalikes`. Token có gạch nối xét từng phần, hậu tố xưng hô sau tên (kun, san, chan, sama, senpai, sensei…) đọc theo âm tiết; dấu nháy sau "n" ("Jun'ichi") ghép hai token. Công tắc `vieneuJapaneseNameSyllablesEnabled` (chưa có khoá = bật).
- **`VieNeuRomajiEnglishLookalikes`** (mới, file sinh): 507 từ tiếng Anh thông dụng cắt được thành âm tiết romaji (game, time, date, kate, mike, tomato…) — giao của 10.000 từ phổ biến nhất (`top_words.rs` của sea-g2p, Apache-2.0) với bộ cắt âm tiết; từ gốc Nhật (tokyo, toyota, suzuki…) để ngoài danh sách. Script `Scripts/gen_vieneu_romaji_english_lookalikes.py` giữ bản chép Python của bộ cắt + `--selftest` 48 ca đối chiếu đúng các chuỗi anh đã nghe.
- **`SeaG2P`**: cặp ký hiệu `rawPhonemeOpen` / `rawPhonemeClose` (U+E000 / U+E001) bọc phiên âm có sẵn; `reToken` thêm nhóm 3 (trước nhóm dấu câu, nay là nhóm 4), `phonemize` chuyển nguyên văn với ngôn ngữ "vi". Mỗi âm tiết bọc riêng, cách nhau dấu cách thường ⇒ bộ cắt chunk không đổi.
- **`VieNeuJapanesePreprocessor`** (Nano và Turbo dùng chung): thứ tự mỗi token = từ điển người dùng → tên kiểu Nhật → đường romaji cũ (vẫn tắt); bảng từ điển rỗng thì không chuẩn hoá khoá nữa (bước này chạy cho mọi token của mọi đoạn — chi phí chỉ còn một lượt regex tách token).
- **Đọc lai**: `VieNeuForeignTextClassifier` không tính tên đã đổi là tiếng nước ngoài ⇒ đoạn ở lại Nano; cờ nằm trong khoá đệm.
- **Cài đặt TTS › Quản lý riêng của trình đọc**: công tắc "Đọc tên Nhật theo âm tiết" dưới "Áp dụng từ điển phiên âm VieNeu" (`VieNeuJapaneseFlags.nameSyllablesEnabled`); cờ vào `TTSOnlineFallbackSettings.fingerprint`.
- Giới hạn: tên pinyin / Hàn / Âu Mỹ đọc như cũ; tên 3 chữ và chữ có mũ ô / â / ê không tự đổi; từ tiếng Anh hiếm viết hoa có dạng romaji ngoài danh sách có thể bị đọc theo âm tiết (thêm vào từ điển hoặc tắt công tắc).
- Kiểm: `--selftest` đạt 48/48; `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử máy.

## [1.3.949] - 2026-11-15

### fix: Nano chừa khoảng lặng dẫn đầu mỗi đoạn để không mất phụ âm đầu câu, không tốn thêm phép tính

Anh Bửu: tên riêng đứng đầu câu hay bị mất chữ ("Kazuto gặp Asuna" nghe thành "aruto"). Đo trên PC bằng đúng model của app: Nano hay bắt đầu tiếng ngay mẫu 0, không chừa khoảng lặng nào (câu "ca du tô…" 3/3 seed; câu tiếng Việt bắt đầu bằng c / t 3/9 seed) ⇒ phụ âm tắc đầu đoạn không có chỗ cho khoảng ngậm; `trimAndFade` còn làm mờ 15 ms đầu mọi đoạn nên ăn tiếp vào phụ âm đầu. Anh nghe mẫu có khoảng dẫn: "Rõ rồi".

- **Ký hiệu dẫn** `VieNeuTTSEngine.leadInPhonemes` = phẩy + cách, thêm vào **đầu chuỗi phiên âm** của mỗi chunk Nano (`withLeadIn`, bỏ qua chunk đã mở đầu bằng dấu câu / dấu cách). Đo ở tốc độ tổng hợp 1,15× (8 câu × 2 seed, số lượt có ≥ 20 ms lặng đầu): không dẫn 4/16 · dấu cách 7/16 · **phẩy + cách 13/16** (1,0×: 16/16). Lặng thừa bị `trimAndFade` cắt còn 40 ms.
- **Không tốn thêm phép tính** (anh Bửu: "ảnh hưởng hiệu năng thì không làm" — Nano là trình đọc chính vì ít tốn pin): ký hiệu dẫn làm `duration_predictor` cộng ~1,8 khung mỗi chunk (115 đoạn truyện thật: +3,3% khung) ⇒ `runChunk` trả lại `leadInFrameCredit` = 2 khung (chunk < 32 khung trả 1, < 16 khung không trả). Đo 12 câu × 2 seed: 810 khung so với 818 khi không dẫn, khoảng dẫn vẫn có ở 23/24 lượt. Đánh đổi: lời đọc trong chunk nhanh hơn ~3% (khoảng dẫn lấy chỗ trong cùng số khung).
- **`trimAndFade`** trả thêm `hadLeadIn`; đoạn model vẫn không chừa lặng đầu thì chỉ fade **2 ms** thay vì 15 ms — lệch có chủ ý so với `trim_and_fade` của bản tham chiếu, ghi trong code.
- **Log** `[VieNeuPerf]` thêm `lead0=` = số chunk của lượt không có khoảng lặng đầu (`Timing.chunksWithoutLeadIn`).
- Không đụng Turbo (chưa biết Turbo có lỗi này không), bộ phiên âm, đường Core ML.
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử máy.

## [1.3.948] - 2026-11-14

### feat: Log lưu bằng SQLite theo từng lần mở app, có bản build, máy, nhiệt, TTS và đánh dấu phiên chết đột ngột

Anh Bửu: "tôi muốn thay đổi cách lưu log ổn hơn" — grill-me chốt: SQLite, mỗi lần mở app một phiên, giữ 20 phiên / 30 MB, chọn phiên ⇒ một file .txt, trong app chỉ có danh sách phiên, file .txt cũ xoá ngay, đầu phiên ghi version + build + máy + iOS + phiên trước chết đột ngột + nhiệt / RAM / ổ trống + trình đọc TTS; công tắc log giữ như cũ (tự tắt mỗi lần mở app). Trước đây mọi lần mở app dồn chung `app_logs.txt` (xoay 2 MB × 5), không biết dòng nào thuộc bản build nào.

- **Kho** `AppLogDatabase` (mới): `applicationSupport/app_logs.sqlite`, sqlite3 thô (WAL, `synchronous=NORMAL`, `auto_vacuum=INCREMENTAL`), mở một lần; bảng `sessions` (thông tin đầu phiên, trạng thái cuối, số dòng / lỗi, `prev_end`) + `lines`. `prune`: giữ 20 phiên mới nhất, bỏ phiên cũ nhất tới dưới 30 MB, không bao giờ bỏ phiên đang ghi (một mình vượt thì bỏ 20% dòng cũ nhất). Tiền tố `app_logs` ⇒ màn Dung lượng vẫn đếm ở "Nhật ký".
- **Đầu phiên** `AppLogSessionInfo` (mới): version / build (`AppVersionInfo`), mã máy (`utsname`), iOS, nhiệt, RAM trống (`ProcessMemoryProbe`), ổ trống, trình đọc + giọng (đọc thẳng `UserDefaults`, không chạm `TTSManager`).
- **`AppLogger`**: API ghi không đổi (`log` / `logAlways` / `logTTSVerbose`), vẫn `print`, công tắc vẫn tự tắt, dòng ❌ vẫn luôn ghi. Ghi theo lô (64 dòng / 0,5 s, dòng ❌ ghi ngay); vào nền / bị đóng ⇒ ghi nốt **đồng bộ** + đánh dấu trạng thái phiên (không giữ transaction lúc app bị treo); phiên cũ còn `foreground` lúc mở app ⇒ phiên mới ghi "chết đột ngột lúc … — dòng cuối: …". LiveContainer chuyển app (`LiveContainerSwitchPreparer`) gọi `markSessionEnded` để khỏi báo nhầm. Kho chưa mở được (cạn fd) ⇒ giữ tối đa 2.000 dòng chờ, thử mở lại sau 30 s. Bỏ `AppLogFiles` + các hàm đọc file cũ; `app_logs*.txt` cũ xoá ở lần mở đầu.
- **Xuất** (`AppLogger+Sessions`, mới): danh sách phiên, xoá phiên, xuất các phiên đã chọn (cũ → mới) thành **một** `Caches/log-exports/TangCongCac-log-<build>-<ngày giờ>.txt` — mỗi phiên mở đầu bằng khối `===== Phiên … =====` (app, máy, iOS, nhiệt, RAM, ổ trống, TTS, phiên trước, trạng thái cuối) rồi các dòng `[yyyy-MM-dd HH:mm:ss.SSS] …`; đọc bằng kết nối riêng ngoài queue ghi.
- **Màn Ghi log hệ thống**: mục "File Log" + "Thao Tác" thay bằng **Phiên** (giờ · bản build · số dòng · số lỗi, badge đỏ "Chết đột ngột", chọn sẵn phiên đang ghi) + "Xuất N phiên (.txt)" (bảng chia sẻ) / "Xoá N phiên" / "Xoá tất cả". Bỏ nút sao chép file mới nhất.
- Ghi chú ở CLAUDE.md / AGENTS.md (gạch Logging, danh sách thư mục).
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử máy.

## [1.3.947] - 2026-11-14

### feat: Trình duyệt ẩn của tiện ích có thêm browser.loadHtml theo hợp đồng chuẩn

Log 22 (anh Bửu duyệt): thử giọng tiện ích ChillAudio TTS lỗi `browser.loadHtml is not a function`. Hợp đồng tiện ích chuẩn có `browser.loadHtml(url, html)` — nạp HTML có sẵn với URL gốc rồi chờ trang chạy xong — mà `Engine.newBrowser()` của app chưa có.

- **JS** (`JSEngineBootstrapScript`): `loadHtml(a, b, timeout)` — nhận cả thứ tự của hợp đồng `(url, html)` lẫn thứ tự ngược `(html, url)` mà ChillAudio đang gọi (tham số nào bắt đầu bằng `http://` / `https://` là URL gốc); chờ mặc định 15 s; trả DOM như `launch`.
- **Native**: cầu `_nativeBrowserLoadHtml` (`JSExecutor`, cùng khuôn `_nativeBrowserLaunch`) → `WebViewLoader.loadHtml` (`WebViewLoader+LoadHtml`, file mới): xoá danh sách URL đã bắt (`urls()` / `waitUrl` tính từ lượt nạp này), `loadHTMLString(html, baseURL:)`, trả DOM ở `didFinish`, hết giờ thì trả DOM đang có.
- Chưa có cho trình duyệt hiện (`newVisibleBrowser`) — hợp đồng chỉ khai cho trình duyệt ẩn. Chưa biết bước sau `loadHtml` của ChillAudio có cần thêm lệnh nào khác.
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử máy.

## [1.3.946] - 2026-11-14

### fix: Đổi nguồn lúc đang nghe truyện thì nghe tiếp ở truyện mới và không còn mất VP riêng

Anh Bửu: "đang nghe truyện mà chuyển nguồn thì truyện nguồn mới bị mất vp riêng" — chọn "tự chuyển nghe sang truyện mới". Hai đường làm mất (đối chiếu code):

- **Đang nghe ⇒ giữ cả hai truyện**: lượt đổi nguồn giữ truyện cũ khi TTS còn phiên của nó (`keepsOldBook`), TTS vẫn đọc truyện cũ, mở Reader từ đĩa nghe / sheet nghe / hẹn giờ là mở truyện cũ ⇒ VP / Name "Riêng" lưu lúc đó vào truyện cũ. Nay bỏ việc giữ: ngay sau mốc chốt `BookSourceChangeCoordinator` gọi `TTSManager.continueListeningAfterSourceChange` (`TTSManager+SourceChange`, file mới) — dừng phiên cũ (để `BookStorageManager` xoá được truyện cũ), tải chương cùng chỉ số ở truyện mới (chép chương theo vị trí) rồi đọc tiếp từ đầu dòng đang đọc, tên / bìa / tiện ích / bộ dịch của nguồn mới. Đang tạm dừng ⇒ chỉ dừng hẳn + toast "bấm nghe để đọc tiếp"; nguồn mới thiếu chương / tải lỗi ⇒ dừng + toast. Truyện cũ dọn như thường (còn giữ khi có chương chép lỗi). Áp cho cả Đổi nguồn ở màn Tìm lẫn "Chuyển sang nguồn …" của truyện mất nguồn (`Request.keepsOldBook` bỏ, tải của truyện cũ luôn huỷ).
- **Truyện đích đã có từ điển ⇒ bỏ qua**: `BookSourceMigrator.copyTranslationFiles` chỉ chép file khi truyện đích chưa có, nên dùng lại truyện có sẵn / đổi nguồn lần hai thì VP riêng của truyện cũ bị bỏ rồi xoá cùng nó. Nay `VietPhrase.txt` / `Names.txt` đã có thì **gộp** qua `TranslationDictionaryWriter.importEntries(isMerge: true)` (mục truyện cũ thắng khi trùng từ; xoá bộ đệm + báo từ điển đổi); file khác giữ "đã có thì giữ". `copyBookScopedSettings` thành `async`. Lùi lại trước mốc chốt với truyện dùng lại thì mục đã gộp ở lại truyện đó (chỉ là mục của cùng truyện).
- Ghi chú ở CLAUDE.md / AGENTS.md (gạch Đổi nguồn).
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử máy.

## [1.3.945] - 2026-11-14

### feat: Giọng dự phòng offline khi TTS online lỗi hoặc mất mạng, tự quay lại giọng online khi hết lỗi

Anh Bửu: "Thêm chức năng cho phép chọn giọng offline thay thế khi giọng online gặp lỗi" — duyệt mockup: một hàng ở Cài đặt TTS dẫn tới màn giống Cài đặt TTS khi chọn VieNeu / NghiTTS; tự quay lại khi online hết lỗi. Trước đây Google TTS / TTS tiện ích lỗi (sau 2 lượt thử lại) là tạm dừng đọc.

- **Cài đặt**: Cài đặt TTS (trình đọc Google / tiện ích) có mục "Khi giọng online lỗi" (nút "?") với một hàng "Giọng dự phòng" (`TTSFallbackVoiceSection`, chữ phụ "VieNeu · Mai Anh" / "Không dùng") ⇒ màn **"Giọng dự phòng"** (`TTSFallbackVoiceSettingsView`): Picker trình đọc (Không dùng / NghiTTS (Piper Offline) / VieNeu-TTS v3 (Offline)), "Giọng đọc" (cùng hàng + sheet chọn giọng của engine), "Quản lý riêng của trình đọc" (VieNeu: Cài đặt VieNeu TTS, từ điển phiên âm VieNeu, từ điển tiếng Nhật; NghiTTS: Cài đặt NghiTTS, tiền xử lý & ngắt nghỉ, từ điển phiên âm cá nhân), "Cấu hình giọng nói" (Tốc độ; Nano thêm Tốc độ tổng hợp). Không có Tải trước (theo trình đọc online), Cao độ, Đọc lai.
- **Lưu**: chỉ trình đọc nào (`TTSOnlineFallbackSettings`, khoá `ttsOnlineFallbackTool`, mặc định Không dùng). Giọng / tốc độ / tốc độ tổng hợp / từ điển là cài đặt của chính engine (chung với lúc engine đó là trình đọc chính). Sheet chọn giọng VieNeu + trang Cài đặt VieNeu TTS mở từ đây (`selectsForFallback`) chỉ lưu lựa chọn, không chuyển trình đọc chính sang VieNeu, không có hàng nhân bản.
- **Lõi** (`TTSManager+OnlineFallback`, `TTSOnlineFallbackState`): thay engine **theo đoạn ở tầng tổng hợp**, không đổi `tool` ⇒ đoạn giữ cách chia của trình đọc online, highlight đúng, không ghi đè `ttsTool`. Tổng hợp online của đoạn đang đọc lỗi (sau lượt thử lại của `RemoteTTSSynthesisCoordinator`, không thêm vòng nào) hoặc máy mất mạng (`TTSNetworkReachability`, `NWPathMonitor`) ⇒ bật dự phòng cho phiên, bỏ lượt nạp trước online đang chờ, toast. Đoạn đang đọc + nạp trước tổng hợp bằng NghiTTS / VieNeu Nano / Turbo, gọi thẳng service (lượt online treo không chặn), dùng chung một lượt cho cùng đoạn; phát qua `AVAudioPlayer` của đường remote ở tốc độ engine dự phòng (`remotePlaybackRate`). Giọng dự phòng cũng lỗi ⇒ dừng + báo như cũ.
- **Tự quay lại** (`TTSManager+OnlineFallbackProbe`): vòng nền thử online một đoạn sắp đọc sau 15 s → 30 s → 1 phút → tối đa 2 phút, gọi thẳng service; mất mạng thì chờ, mạng có lại ⇒ thử ngay; tạm dừng thì chờ. Được ⇒ giữ tiếng online cho đoạn đó, tắt dự phòng, toast "… hoạt động lại"; đoạn dự phòng đã nạp phát nốt.
- Lúc đang dùng dự phòng: nạp trước gộp nhiều đoạn của Google (`dispatchRemotePrefetch`) tắt để mỗi đoạn đi nhánh dự phòng; sang chương kế không chờ lượt online đang chạy của chương đó (`claimedSynthesisTask`, có thể treo tới hết giờ) mà đọc đoạn đầu bằng dự phòng ngay.
- **Sheet nghe mini**: badge cam "Dự phòng" (`TTSFallbackBadge`; NghiTTS ghi "Dự phòng · NghiTTS", VieNeu kèm badge model · tăng tốc).
- `TTSSettingsSnapshot` thêm `onlineFallback` (dấu cài đặt dự phòng) ⇒ đổi giọng / tốc độ dự phòng thì đóng Cài đặt là dựng lại đoạn. Ghi chú ở CLAUDE.md / AGENTS.md.
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử máy.

## [1.3.944] - 2026-11-14

### feat: Bấm nghe trong Reader hoặc Nghe đoạn bôi đen thì tự mở sheet nghe mini

Anh Bửu: "Khi bấm nút nghe ở reader hoặc bôi đen nghe hãy mở sheet nghe mini". Sau khi bắt đầu / tiếp tục đọc, sheet điều khiển nhanh TTS (`TTSQuickControlSheet`, như chạm đĩa nghe) tự mở.

- **`MediaDiscWindowManager.presentQuickControlsWhenReady()`**: ghi một yêu cầu chờ (hết hạn sau 5 s), mở sheet khi đĩa là TTS, phiên có mặt (`showFloatingWidget`) và cửa sổ đĩa đang hiện; thử lại sau mỗi `refreshState()` (TTS bật / tắt phiên). Mở trễ 0,4 s để `MediaDiscSheetHost` của cửa sổ vừa dựng kịp gắn (token tăng trước lần vẽ đầu thì `onChange` không chạy) và phiên cũ vừa dừng (nút tai nghe dừng phiên rồi đọc lại) kịp về `nil` — không mở sheet của phiên sắp tắt.
- **Reader** (`openTTSQuickControlsAfterListen`, `ReaderView+TTSSameChapterPrompt`): nút tai nghe — phát tiếp tại chỗ, đọc từ đoạn đang xem, và sau khi chọn ở sheet "đang đọc chương này" (cả ba lựa chọn, cả đường lùi sheet thường) — và nút "Nghe" của bong bóng bôi đen.
- Ghi chú ở CLAUDE.md / AGENTS.md (gạch đĩa nghe).
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử máy.

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
