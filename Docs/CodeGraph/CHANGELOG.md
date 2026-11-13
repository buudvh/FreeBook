# CHANGELOG - Nhật ký Thay đổi CodeGraph Tàng Công Các

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **Tàng Công Các**.

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

## [1.3.912] - 2026-11-13

### feat: Màn thử VieNeu có Đo nạp Core ML để tìm vì sao nạp session lâu và bản biên dịch nặng 4 GB

Anh Bửu gửi kết quả đo tự động 1.3.911 (1249) ở QoS trình đọc. Core ML CPU-only thắng ở trạng thái ổn định:
- RTF 0,14, so với ORT 0,27 (lượt ORT 3, khớp trình đọc 0,28);
- tổng hợp nhanh 2,06×, CPU vòng Euler ít hơn 3,46×;
- CPU mỗi giây tiếng 0,20, so với 0,55;
- hụt tiếng 0, lùi ORT 0/304.

Lượt ORT 1 không dùng làm mốc (pin 25 → 10%, chạy trước lượt 2 khoảng 11 tiếng). Hai chặn còn lại trước khi đưa Core ML vào trình đọc:
- nạp 7 session mất ~110 s mỗi lần (kể cả nạp lại ấm) và làm máy nóng;
- bản biên dịch chiếm 4,16 GB.

Anh duyệt plan P2a: chỉ đo, không đụng đường đọc truyện. Chi tiết ở §12 báo cáo `2026-11-11-vieneu-nano-toi-uu.md`.

- **Mục mới "Đo nạp Core ML (P2a)"** ở màn thử VieNeu Turbo (`VieNeuCoreMLLoadProbe` + `VieNeuCoreMLLoadWorker`, chạy `userInitiated`, giữ màn sáng). Dùng gói + bản biên dịch của Đo tự động, không tải hay biên dịch thêm. Phép đo làm 4 việc:
  1. Dung lượng từng mục cache: phần gói ORT ghi ra, phần `compiled_model.mlmodelc`, các file ≥ 1 MB (`VieNeuCoreMLCacheInventory`), dung lượng ổ trống lúc đầu / cuối.
  2. Băm mọi `weight.bin` để tìm bản trùng byte giữa các bucket.
     - Băm qua ánh xạ file (`.alwaysMapped`), để ~4 GB không dồn RAM.
     - Mỗi file ghi thêm dung lượng thật trên đĩa và mã nội dung APFS: hai bản là clone thì bỏ một bản không lấy lại được chỗ.
  3. Nạp VE và codec bucket nhỏ nhất bằng ba cách, ghi giây + CPU-giây + nhiệt:
     - ORT CPU, không Core ML;
     - **Core ML gốc** (`MLModel(contentsOf:)`, `.cpuOnly`), đọc thẳng bản biên dịch, **kèm một lượt dự đoán input 0 ngay sau khi nạp** (`VieNeuCoreMLNativeLoad`) — Core ML có thể dời việc chuẩn bị sang lần dự đoán đầu, chỉ đo phần nạp thì số sẽ đánh lừa;
     - **ORT + Core ML EP** như lượt đọc, kèm dấu hiệu ORT ghi lại gói.

     Core ML gốc và ORT + Core ML EP mỗi cách 2 lần, xen kẽ.
  4. Thử **bỏ bản trọng số của gói** ở VE bucket nhỏ nhất: đổi tên file, nạp lại, kiểm ORT còn trúng bản lưu và tự kiểm golden vẫn đúng, rồi trả file về.
     - Bị ngắt giữa chừng ⇒ lần chạy sau hoặc lần mở màn thử tự trả file về (`restoreTrimmed`).
- Tách `VieNeuCoreMLPreparer.goldenRequest` (dùng chung với tự kiểm) và `VieNeuCoreMLFlowBackend.coreMLOptions` (một chỗ cho tuỳ chọn Core ML EP, để phép đo trúng đúng bản biên dịch của lượt đọc).
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.911] - 2026-11-12

### fix: Đo tự động chạy Nano ở mức ưu tiên như trình đọc và không xoá nhầm bản biên dịch Core ML đã xong

Anh Bửu gửi kết quả lượt đo 1.3.910 (1248): ORT / Core ML / ORT RTF 0,55 / 0,59 / 0,58, CPU mỗi giây tiếng 0,90 / 0,63 / 0,91, Core ML giữ máy mát cả 15 phút (ORT lên nóng sau 5:00 và 1:50), chạy nền khoá màn được (310 đoạn, không lùi ORT, không bị giết). Anh duyệt plan sửa hai lỗi của màn đo.

- **Mức ưu tiên**: cả ba lượt chạy ở `utility` (lõi tiết kiệm). Lý do: đo tự động lấy `nanoQoS` của "Đọc liên tục", mà mặc định của nó là `utility`. Trình đọc thật chạy ở lõi hiệu năng (RTF 0,28), phép thử P1 tính ở `userInitiated` ⇒ Core ML lượt này chậm ~4 lần P1 (169 so với 43 ms mỗi lượt VE ở T128), không so được với trình đọc.
  - Đo tự động giờ có mục chọn **"QoS tổng hợp"** riêng: "Như trình đọc" (`userInitiated`, mặc định) hoặc "Lõi tiết kiệm".
  - Mức được lưu vào tiến độ (`VieNeuAutoRunProgress.qosRawValue`) nên Chạy tiếp giữ đúng mức của lần đo; tiến độ cũ không có trường này ⇒ `utility`, đúng mức bản 1.3.910 đã chạy.
  - Báo cáo in mức đã chọn ở đầu file, nhật ký từng bước ghi lúc bắt đầu / chạy tiếp.
- **Dọn cache Core ML xoá nhầm** (`VieNeuCoreMLPackage.cleanCacheEntries`, thay `removeIncompleteCacheEntries`).
  - Bản cũ tìm `compiled_model.mlmodelc` ngay trong `<id>_static_mlprogram/`. Nhưng ORT 1.24.2 đặt gói ở `…_mlprogram/model` (`GetModelOutputPath`) và để bản biên dịch **bên trong gói** (`CompileOrReadCachedModel`).
  - Hậu quả: mỗi lần bắt đầu / chạy tiếp xoá cả 10 mục hợp lệ rồi biên dịch lại. Lần chạy tiếp của anh mất 265 s để nạp, đúng bằng thời gian biên dịch lạnh.
  - Giờ tìm ở tầng 1 và tầng 2; báo cáo / nhật ký ghi "giữ N bản biên dịch, dọn M bản dở" kèm một đường dẫn tìm thấy, để lần đo sau kiểm được là đã sửa.
- Màn thử: chú thích dung lượng bản biên dịch sửa từ "khoảng 1 GB" thành "khoảng 4 GB" (đo được 4,16 GB).
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.910] - 2026-11-12

### feat: Đo tự động có Chạy tiếp từ lượt chưa xong sau khi dừng, bị gián đoạn hay app bị tắt

Anh Bửu: *"lần sau nhớ thêm chạy tiếp để lỡ trường hợp có việc thoát ra khỏi chạy từ đầu"*, rồi *"làm luôn Chạy tiếp cho Đo tự động, huỷ CI trước đi"* (đã huỷ lượt build của 1.3.909; lượt này build cả 1.3.909 + 1.3.910).

- **Lưu tiến độ** (`VieNeuAutoRunProgress`, `Results/do-tu-dong-tien-do.json`): chuẩn bị Core ML xong (dòng báo cáo, qua tự kiểm hay không, trần session, RAM ước mỗi session, giọng), mỗi lượt xong / dở, **bản chụp mỗi phút** của lượt đang chạy, và lúc kết thúc. `VieNeuAutoThermalLeg` / `Stats` thành `Codable`; lượt có cờ `interrupted` (bấm Dừng, bị gián đoạn).
- **Màn thử**: lượt đo trước chưa xong mà đã qua bước chuẩn bị ⇒ hai nút **"Chạy tiếp (từ lượt N/3)"** và **"Đo lại từ đầu"** thay cho "Bắt đầu đo tự động".
- **Chạy tiếp** (`VieNeuAutoThermalRun+Resume`): không biên dịch / tự kiểm lại; chạy từ lượt đầu tiên chưa xong êm; lượt dở chạy lại cả bước chờ mát; app bị giết giữa lượt ⇒ bản chụp phút cuối của lượt đó vào báo cáo như lượt dở. Còn lượt Core ML thì **nạp sẵn session ngay lúc bấm** (màn còn sáng), dọn bản biên dịch dở, rồi mới chờ mát. Báo cáo và nhật ký từng bước nối tiếp lần trước (cùng file), có dòng "chạy tiếp HH:mm từ lượt N"; lượt dở ghi "(dở)".
- **Đã xác nhận nguyên nhân sập** bằng file `LiveContainer.cpu_resource_fatal-2026-11-12-144121.ips` anh gửi: *"Action taken: Process killed"*, *"48 seconds cpu time over 54 seconds (90% cpu average), exceeding limit of 80% cpu over 60 seconds"*, *"Non-Frontmost App"*, ngăn xếp CoreML → Espresso → MIL. iOS giết app **chạy nền** dùng CPU quá 80% trong 60 giây; lúc đó app chỉ phát vòng lặng (âm lượng 0), có vẻ không được miễn như khi phát tiếng thật. Biên dịch / nạp model Core ML là việc nặng ⇒ phải làm khi màn còn sáng (1.3.909, và lúc bấm Chạy tiếp).
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.909] - 2026-11-12

### fix: Đo tự động nạp sẵn session Core ML lúc màn còn sáng và giữ tới hết lượt Core ML, không nạp khi khoá màn

Anh Bửu gửi nhật ký từng bước của lượt đo bản 1.3.907 (1244), *"đột nhiên crash"*:

- Bước chuẩn bị (biên dịch 7/7, nạp lại 7/7, tự kiểm) **chạy trọn** khi màn còn sáng; RAM thấp suốt (125–280 MB footprint, trống ~1,8 GB) ⇒ lần này **không** phải hết RAM. Giữ một session Core ML chỉ thêm ~20 MB (trọng số đã biên dịch map từ đĩa).
- Lượt 1 (ORT) chạy xong (máy lên nóng sau ~2 phút đọc).
- App chết **ngay lúc nạp session Core ML đầu tiên cho lượt 2** (`nạp sẵn ve T64`, RAM trống 1,7 GB) — máy đã khoá màn ~17 phút (chờ mát + lượt 1). Khác biệt duy nhất với lúc nạp thành công là app đang ở **nền**. Nghi: Core ML không nạp / biên dịch model được khi app ở nền (chưa có file crash để xác nhận).

Sửa:
- **Nạp sẵn mọi session ở cuối bước chuẩn bị** (`VieNeuCoreMLPreparer`, sau tự kiểm, lúc màn còn sáng) và **giữ** qua lượt 1 tới hết lượt Core ML; bỏ bước nạp sẵn trước lượt Core ML (chạy lúc khoá màn). Sau lượt Core ML vẫn nhả như cũ.
- Trần số session theo RAM thật: sàn RAM ước mỗi session 150 MB ⇒ 40 MB (đo được ~20 MB); lần trước trần ra 6/7, thiếu một bucket phải nạp giữa lượt lúc khoá màn.
- Nhật ký từng bước ghi thêm **app đang mở màn hay nền / khoá màn** ở mỗi dòng của luồng chính; dòng bắt đầu lượt Core ML ghi số session đang giữ.
- Lượt Core ML giờ **chạy Core ML lúc khoá màn** — câu trả lời trực tiếp cho câu hỏi Core ML có dùng được cho trình đọc (nghe khi tắt màn) không: chết ngay đầu lượt 2 ⇒ suy luận Core ML ở nền cũng không được.
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.908] - 2026-11-12

### fix: icon chia sẻ / nhập từ truyện khác của từ điển VP, Name không còn trùng icon xuất / nhập file

Anh Bửu báo: *"icon xuất nhập vp/name bị trùng icon chia sẻ/nhập vp/name từ truyện khác rồi"*.

- Ngăn kéo `…` của từ điển riêng (`DictionaryListView`): "Chia sẻ sang truyện khác" dùng `square.and.arrow.up` và "Nhập từ truyện khác" dùng `square.and.arrow.down`, y icon của "Xuất từ điển" / "Nhập từ điển" (file). Đổi sang cặp `arrowshape.turn.up.right` (gửi sang) / `arrowshape.turn.up.left` (lấy về).
- Cặp `square.and.arrow.down` / `up` từ nay chỉ dành cho nhập / xuất **file** (cả app vốn dùng vậy). Chia sẻ bộ rule riêng sang truyện khác (`QuickTranslationRuleIOMenu`, menu hàng `QuickTranslationRuleEntryRow`) cũng đổi từ `square.and.arrow.up.on.square` sang `arrowshape.turn.up.right` cho cùng một icon ở mọi nơi.

**Kiểm chứng:** chỉ đổi tên SF Symbol (có từ iOS 13). `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Chưa thử máy.

## [1.3.907] - 2026-11-12

### fix: mở Cài đặt TTS từ đĩa nghe luôn dừng đọc, đóng sheet thì đọc tiếp

Anh Bửu báo ở 1.3.905: *"khi tôi mở sheet cài đặt tts sao không pause được"*.

**Nguyên nhân:**
- Sheet Cài đặt TTS có hai lối mở:
  - nút ⚙ của sheet Hẹn giờ, qua `TTSSettingsSheetHost`, có `onDismiss`;
  - nút "Giọng đọc" của sheet điều khiển đĩa nghe (`TTSQuickControlSheet`), dùng `.sheet` riêng, **không** có `onDismiss`.
- Với lối thứ hai, phiên Cài đặt (1.3.897) chỉ còn trông vào `TTSSettingsView.onDisappear` khi `isPresented == false`. Nhưng ở màn gốc của sheet, cờ này không về `false` lúc sheet đóng, nên phiên kẹt ở "đang mở":
  - đóng sheet không đọc tiếp;
  - lần mở sau `begin()` tưởng phiên cũ còn mở nên **không dừng**;
  - về trang gốc Cài đặt thì có thể tự đọc.

**Sửa:**
- Vỏ `TTSSettingsSheet` gọi `finish` ở `onDisappear`. Vỏ chỉ biến mất khi sheet đóng thật (vào trang con thì vỏ còn), và cả hai lối mở đều đi qua vỏ này.
- `TTSSettingsView.onDisappear` giờ chỉ lo dạng **trang** ở tab Cài đặt (`!isPresentedAsSheet && !isPresented`). Các chốt `onAppear` của hub "Nghe truyện (TTS)" và trang gốc Cài đặt giữ nguyên.
- Chốt an toàn: `begin()` thấy phiên "đang mở" mà TTS **đang đọc** thì coi phiên cũ đã đóng mà không ai báo, và mở phiên mới. Nhờ vậy mở Cài đặt là luôn dừng.

**Kiểm chứng:** đọc code + grep chéo (`begin` chỉ gọi ở `TTSSettingsView.onAppear`; `finish` ở vỏ sheet, `onDismiss` của host, `TTSSettingsView` dạng trang, hub và trang gốc Cài đặt). `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Chưa thử máy; log `[TTSSettings]` ghi lối nào đã đóng phiên.

## [1.3.906] - 2026-11-12

### fix: Đo tự động không giữ engine Nano lúc biên dịch Core ML, kiểm RAM trước mỗi bước và ghi nhật ký từng bước

Anh Bửu chạy Đo tự động bản 1.3.890 (1239) thì app sập, *"hình như nó crash ở bước 3,4/7 gì đó khi biên dịch Core ML"* (VE T128 / T160). Không có log (app bị giết, log thường tắt mặc định); nghi phạm chính là **hết RAM** (iOS giết app).

- **Nhả engine Nano trong lúc chuẩn bị Core ML**: bản 1.3.890 nạp engine Nano (ORT 4 graph + bộ phiên âm, ~350 MB) **trước** khi biên dịch, còn phép thử P1 (chạy được) thì nhả nó ra. Giờ nhả (`releaseEngineRuntime`) trước bước biên dịch / nạp lại / tự kiểm, nạp lại sau đó; chế độ `fast` vẫn ghim.
- **Nạp lại (ấm) từng session một rồi nhả**, không giữ cộng dồn tới 7 session như trước. Trần số session giữ lúc đọc tính từ RAM trống lúc nghỉ − engine nạp lại (380 MB) − chừa 600 MB, chia RAM lớn nhất một session đo được; `preload` của lượt Core ML kiểm RAM trống trước mỗi session.
- **`autoreleasepool` quanh mỗi lần tạo session và mỗi lượt chạy** (`VieNeuONNXProbeSession`): bước chuẩn bị là **một** lời gọi đồng bộ dài trên luồng nền, nên mọi đối tượng ObjC autorelease của Core ML EP (MLModel, kết quả biên dịch, NSData, MLMultiArray) sống tới hết 7 lần biên dịch + nạp + tự kiểm — RAM dồn lên qua từng graph, khớp chuyện chết ở bước 3–4 chứ không ở bước 1. Lượt đọc (16 lượt VE mỗi đoạn trong một lời gọi của engine) cũng dọn sau từng lượt.
- **Dọn bản biên dịch dở** (`VieNeuCoreMLPackage.removeIncompleteCacheEntries`): ORT coi graph là đã có bản lưu chỉ cần thư mục gói MLProgram tồn tại (`ModelBuilder`: `FolderExists(model_output_path_)`), mà thư mục đó ghi **trước** khi biên dịch ⇒ app bị giết giữa chừng thì lượt sau dùng lại gói dở. Trước khi biên dịch, xoá mọi mục `*_mlprogram` chưa có `compiled_model.mlmodelc`.
- **Kiểm RAM trước mỗi lần biên dịch**: dưới 1 GB trống ⇒ dừng có báo ("tắt bớt app khác rồi bấm lại") thay vì để iOS giết app.
- **Nhật ký từng bước sống sót khi app bị giết** (`VieNeuAutoRunTrail`, `Results/do-tu-dong-nhat-ky.txt`): ghi **trước** mỗi bước nặng (biên dịch / nạp từng graph, tự kiểm, nạp sẵn, mỗi lượt, mỗi phút) kèm RAM + nhiệt, mỗi dòng ép xuống đĩa. Mở lại màn thử mà lượt trước không có dấu kết thúc ⇒ dòng cam "Lần đo trước dừng đột ngột ở: …" + nút "Chia sẻ nhật ký từng bước"; lượt sau chép dòng đó vào đầu nhật ký mới.
- Bản biên dịch Core ML đã xong ở lượt trước vẫn giữ trong cache ⇒ lượt sau không biên dịch lại các graph đó.
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.905] - 2026-11-12

### fix: nút Mục lục của sheet nghe truyện mở sheet hẹn giờ đúng tab Danh sách chương

Anh Bửu: *"bấm mục lục nó hiển thị lên sheet hẹn giờ là đúng, chỉ sai nhỏ ở chỗ là phải chọn tab con mục lục thay vì tab con hẹn giờ"*.

- **Nguyên nhân**: `TTSQuickControlSheet` gán tab (`timerSheetTab = 1`) rồi bật cờ `showingTimerSheet` trong cùng một lượt; `.sheet(isPresented:)` dựng `TTSQuickTimerSheet(initialTab:)` với giá trị tab cũ (0) nên "Mục lục" mở ra tab Hẹn giờ tắt.
- **Sửa**: thay hai state bằng `.sheet(item:)` với enum `TimerSheetTab` (`timer` / `chapters`): ⏱ ⇒ tab Hẹn giờ tắt, "Mục lục" ⇒ tab Danh sách chương. Sheet Hẹn giờ không đổi.
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.904] - 2026-11-12

### fix: giọng VieNeu giữ phiên âm thanh của truyện khi thử giọng, tải lại không chồng lượt, đổi tên giọng Nano không ghi đè lựa chọn Turbo

Session chính đọc soát nhánh giao diện giọng VieNeu (1.3.898–902) trước khi push, thấy vài lỗi logic; sửa cả đợt.

- **Thử giọng làm mất phiên âm thanh của truyện**: `VieNeuVoicePreviewPlayer.releaseSession` tắt `AVAudioSession` cả khi truyện chỉ đang tạm dừng vì mở Cài đặt TTS. Phiên đó là của `TTSManager` (`isAudioSessionConfigured` vẫn `true`), `resume()` không bật lại ⇒ có thể mất tiếng / mất màn khoá. Nay TTS còn phiên (`playingBookId` khác rỗng hoặc phiên đã cấu hình) thì để nguyên, như clip thử của NghiTTS. `sampleText` khai `nonisolated` vì đọc trong hàm `nonisolated`.
- **Bấm ■ rồi ⬇ ngay là hai lượt cùng ghi `.partial`**: `cancel(id:)` xoá dòng ngay trong khi `Task` cũ còn dừng `URLSession`, mà lượt mới chỉ chờ khi còn dòng đang chạy. Nay lượt mới **luôn** chờ lượt cuối hàng (đã xong thì trả ngay); `isQueued` vẫn theo `isVieNeuBusy`.
- **Tải xong mà model hiệu lực đổi** (lựa chọn đã lưu là Turbo, máy thiếu file nên đang lùi về Nano; tải đủ ⇒ thành Turbo): `selectedVoice` còn tên giọng Nano ⇒ Turbo đọc giọng mặc định. Nay tải xong mà `VieNeuModelChoice.current` đổi và trình đọc là VieNeu ⇒ `applyVieNeuParamsIfNeeded()` + `scheduleNghiWarmUp()`.
- **Sheet nhân bản**:
  - Bỏ sheet lúc đang lưu từng xoá file mẫu tạm trong khi `enrollVoice` / `createVoice(fromFile:)` có thể còn đọc ⇒ nay chỉ xoá sau khi lượt lưu dở dừng hẳn.
  - Huỷ lượt lưu từng huỷ cả lượt tải người dùng tự bấm ở sheet chọn giọng ⇒ `VieNeuClonePackages.ensure` báo riêng đích **do chính lượt lưu khởi tạo** (`Jobs.owned`), chỉ huỷ các đích đó.
  - Nano xong mà Turbo lỗi từng `markSaved()` ⇒ file mẫu tạm không bao giờ bị xoá; nay đóng sheet là xoá (kho Nano / Turbo đã chép mẫu riêng). Sửa chú thích "đang lưu ⇒ không đóng được" cho khớp `confirmDiscardOnSwipe`.
- **Đổi tên / xoá giọng Nano** (`VieNeuCustomVoiceActions.retargetNanoVoice`): lựa chọn đã lưu là Turbo mà đang lùi về Nano bằng giọng đó ⇒ không còn ghi đè mất lựa chọn Turbo, chỉ đổi giọng đang đọc. Đổi tên giọng Nano không đang đọc ⇒ lựa chọn đã lưu / "giọng Nano dùng gần nhất" trỏ tên cũ cũng chuyển sang tên mới. Xoá giọng Turbo tự tạo đang là lựa chọn mà trình đọc không phải VieNeu ⇒ lựa chọn về giọng mặc định. Bỏ `isReaderVoice` (không còn chỗ gọi).
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`. Chưa build (Windows), chưa thử máy.

## [1.3.903] - 2026-11-12

### chore: dời số bản trong chú thích code của đợt nhân bản giọng và giao diện VieNeu sau khi ghép lại

Session Nano đưa P1b ("Đo tự động ORT ↔ Core ML") lên `main` với số **1.3.890** trong lúc đợt này chưa push. Javis ghép lại 12 commit của đợt lên sau commit đó (`a3818664`) và dời mỗi số lên 1:
- lõi nhân bản Turbo: 1.3.890–895 → **1.3.891–896**;
- sửa Cài đặt TTS: 1.3.896 → **1.3.897**;
- giao diện chọn giọng / nhân bản: 1.3.897–901 → **1.3.898–902**.

Entry CHANGELOG đã dời lúc ghép. Commit này chỉ dời số trong **chú thích code**, `CLAUDE.md` / `AGENTS.md` và script của đợt. Dòng nào có y nguyên trong bản `main` thì giữ, ví dụ số 1.3.890 của P1b.

**Kiểm chứng:** so `diff` code giữa bản trước và sau khi ghép: chỉ khác đúng phần P1b mang vào, cộng một dòng `isBusy` của màn thử gộp cả `autoRun` lẫn `cloneTrial`. `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Chưa build.

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
