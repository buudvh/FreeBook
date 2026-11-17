# CHANGELOG - Nhật ký Thay đổi CodeGraph Tàng Công Các

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **Tàng Công Các**.

## [1.3.968] - 2026-11-17

### feat: Sheet quét tên riêng nhớ prompt tự nhập: Gần đây theo truyện, ghim dùng chung

Anh Bửu: "ghi nhớ prompt tự nhập ở AI" — ô "Tự nhập prompt" của sheet "Quét tên riêng theo phạm vi" trước đây chỉ dùng cho một lần quét, mở lại sheet là mất. Plan + mockup phương án B đã duyệt: `Docs/Plans/2026-11-17-plan-name-scan-saved-prompts.md`.

- **Kho mới `AINameScanPromptStore`** (`Services/AI/`, model `AINameScanSavedPrompt`): bấm "Bắt đầu quét" với nguồn Tự nhập ⇒ chữ trong ô "Prompt cho lần này" (cắt khoảng trắng hai đầu, không bao giờ kèm nội dung truyện) vào **Gần đây của truyện** — tối đa 10, dùng gần nhất lên đầu, trùng y nội dung thì đưa lên đầu chứ không thêm bản mới. Prompt trùng prompt Cài đặt hay trùng một bản ghim thì không ghi. **Đã ghim dùng chung mọi truyện** (mới ghim lên đầu, không giới hạn); Gần đây hiện ra lọc bỏ chữ trùng bản ghim. Lưu UserDefaults `aiNameScanPromptRecents` / `aiNameScanPromptPins` (chữ thường đầu ⇒ Sao lưu tự mang theo; khôi phục là ghi đè).
- **Sheet**: mục Nguồn prompt thêm dòng "Chọn prompt đã lưu…" (phụ đề "2 đã ghim · 3 gần đây"; chưa có gì thì mờ, khoá, "Chưa có prompt nào đã lưu", cùng kiểu "Chọn chương…"); lời giải thích "?" đổi theo. Sheet vẫn mở với nguồn "Dùng prompt trong Cài đặt" như cũ.
- **Trang "Prompt đã lưu"** (`ReaderAISavedPromptsView`; dòng vào là `ReaderAISavedPromptsView.EntryRow`): nhóm Đã ghim / Gần đây của truyện này, xem trước 2 dòng + "N dòng" (Gần đây thêm "14:20 hôm nay" / "Hôm qua" / "dd/MM"). Chạm ⇒ chép vào ô, chọn Tự nhập, quay về sheet. Nhấn giữ: Ghim / Bỏ ghim (về đầu Gần đây của truyện đang mở), Xoá; vuốt trái: Xoá (không hỏi lại).
- **Đổi nguồn**: `BookSourceMigrator` chép / xoá Gần đây theo truyện như các kho AI khác; `rules.md` (luật 1.3.669) ghi thêm kho này.
- Không đụng ô chat màn AI, chip hành động nhanh, prompt trong Cài đặt AI. Xoá truyện không dọn Gần đây của truyện đó (như mọi dữ liệu AI theo truyện hiện nay).
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.967] - 2026-11-17

### feat: Sheet hub có mục "Đang chạy" với thanh tiến độ của mọi tác vụ nền

Anh Bửu: "tôi muốn thấy thanh tiến độ ở sheet hub"; duyệt mockup **A · Mục "Đang chạy"** và bỏ giới hạn 3 ô ("lỡ có nhiều hơn thì sao").

- **Mục "Đang chạy"** dưới bốn dòng cố định (`FloatingHubActivitySection`, file mới): mỗi tác vụ nền có thanh tiến độ ở màn Thông báo một ô — icon, tên, chi tiết, thanh — cùng khung với dòng hub (`hubSheetPanelRow`). Dòng đầu "Đang chạy (N) · M đang chờ" (chỉ có tác vụ chờ ⇒ "M tác vụ đang chờ"). Chạm ô ⇒ trang Thông báo trong sheet (nơi có nút Huỷ, chi tiết từng tập). Không giới hạn số ô.
- **Nguồn chung** `FloatingHubActivity` (file mới): `items()` dựng ô theo thứ tự tải / xuất (hàng đợi) → nhập truyện → sao lưu / khôi phục → tải giọng → gộp VietPhrase → phiên âm lại Nghi / VieNeu; `counts()` đếm đang chạy / đang chờ (đang chờ = tác vụ tải / xuất xếp hàng + lượt tải VieNeu chờ lượt khác).
- **Chữ của tác vụ tải / xuất dùng chung** (`DownloadTask+ActivityText`: `activityTitle` / `activityDetail` / `activityFraction`) — dòng ở màn Thông báo (`StoryTaskActivityRow`) chuyển sang dùng, bỏ bản riêng.
- **Đếm thay cho một bit** (`NotificationInboxPresenceReader.Snapshot`: `runningCount` / `pendingCount`, `hasRunningTask` thành tính toán): dòng Thông báo ghi "5 đang chạy · 1 chờ · 2 chưa đọc" (bỏ vế bằng 0; trước đó "N chưa đọc" hoặc "Đang chạy tác vụ"). **Vá sót**: gộp VietPhrase và phiên âm lại trước không được tính là "đang chạy" ⇒ nút hub không nháy dù màn Thông báo có thanh chạy; nay nghe `phase` của hai việc này (rút về một bit, `removeDuplicates`).
- **Đầu sheet "N đang chạy" đếm tác vụ** (`Snapshot.runningTaskCount`: AI đang chạy + tác vụ nền + lượt kiểm tra nguồn đang chạy + video thu nhỏ), không còn đếm loại dòng. Không vào `ButtonState` ⇒ nút hub không vẽ lại theo số này.
- **Sheet cuộn khi dài**: trang nhỏ của sheet (`compactPage`) nằm trong `ScrollView` (`scrollBounceBehavior(.basedOnSize)`): nội dung cao hơn màn thì nấc `.height` bị kẹp ở mức cao nhất và phần dư cuộn; vừa màn thì không nảy.
- Hiệu năng: mục "Đang chạy" tự observe các nguồn (`DownloadManager` phát ~10 lần/giây lúc tải) nên chỉ nó vẽ lại theo nhịp tiến độ, và chỉ khi sheet mở; hub vẫn chỉ đọc số đã gộp + `removeDuplicates`.
- `.claude/rules/floating-pills.md` ghi luật mới.
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.965] - 2026-11-17

### fix: Bớt việc trên main khi tải truyện để mục lục đỡ giật, thêm log đo main thread bị kẹt

Anh Bửu báo mục lục Reader giật khi đang tải truyện; log build 1289 không có dấu vết lúc giao diện khựng (JS của tiện ích chạy ngoài main, `[ReaderEnergy]` không tăng lúc tải) nên chưa xác định chắc nguyên nhân. Đợt này bỏ hai việc thừa trên main đã thấy khi đọc code và thêm bộ đo để lần sau có số liệu.

- **Tiến độ tải không còn fetch SwiftData mỗi chương** (`DownloadManager.updateProgress`): trước đó mỗi chương một lần fetch `#Predicate` trên main + `save()` mỗi giây; mỗi lần lưu có thể đánh thức `@Query` của màn đang mở (Reader giữ `@Query` cả thư viện, Kệ nằm dưới cũng vậy). Nay chỉ ghi CSDL khi đổi trạng thái / bước đầu / bước cuối và mỗi 5 s (`progressPersistInterval`, đếm riêng từng tác vụ — `lastProgressPersistAt`); thanh tiến độ trên màn vẫn ~10 lần/giây như cũ. CSDL chỉ cần tiến độ để hiện lại sau khi app bị tắt giữa chừng.
- **Mục lục của Chi tiết gộp sự kiện "chương vừa tải" tối đa 1 lần/giây** (`BookDetailTOCView.observeChapterDownloads`): mỗi lần ghi `freshlyCachedIndices` (`@State`) là cả `body` dựng lại kèm `ForEach` hàng nghìn chương — kể cả khi Chi tiết đang nằm dưới Reader. Tải 2–3 luồng là vài chương mỗi giây. Icon "đã tải" ở đó trễ tối đa 1 giây.
- **Log đo main kẹt** (`MainThreadHangMonitor`, `Services/Diagnostics/`, khởi động ở `FreeBookApp.init`): chỉ chạy khi bật "Ghi log hệ thống"; mỗi 0,25 s gửi một khối rỗng vào main và đo độ trễ. Kẹt ≥ 500 ms ⇒ một dòng `🐢 [MainHang] Main kẹt N ms`; các lần ≥ 150 ms gộp thành dòng tổng kết mỗi 10 s. Mỗi dòng kèm bối cảnh: số tác vụ tải / xuất đang chạy, Chế độ AI đang chạy lượt (`GoogleAIModeSessionController.isTurnActive`), "mục lục Reader" / "mục lục Chi tiết" đang mở (`noteScreen`), mức nhiệt. Mục lục Reader thêm dòng `📑 [ReaderTOC] Mở / Đóng mục lục`.
- Sheet hub đếm tác vụ: anh Bửu chưa duyệt mockup ⇒ chưa làm.
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.964] - 2026-11-17

### fix: Đĩa nghe không ẩn khi có hộp thoại xác nhận / huỷ, ở lại như nằm dưới hộp

Anh Bửu báo: có thông báo dạng chọn xác nhận / huỷ thì đĩa nghe bị ẩn dù hub không ẩn — "việc ẩn là không cần, chỉ cần để nó nằm dưới các thông báo đó".

- Cửa sổ đĩa (`alert − 1.75`) nằm trên cửa sổ chính, còn hộp thoại SwiftUI (`.alert`, `.confirmationDialog` ⇒ `UIAlertController`) trình bày **trong** cửa sổ chính ⇒ không vẽ đĩa dưới hộp thật được. Thay vì ẩn (`MediaDiscPlacement` luật 1), đĩa giả "nằm dưới":
  - **Né khung hộp**: khung `alert.view` là vật cản (cùng luật "tạm đẩy" của neo lấn vùng), đĩa trượt lên trên nó; không ghi đè chỗ đã nhớ, hộp đóng thì về chỗ cũ. Đẩy tới đỉnh vùng đứng mà vẫn đè khung (bảng chọn cao) ⇒ ẩn như cũ để không che nút của hộp.
  - **Không nhận chạm / kéo** (`isDiscInteractive` = đang hiện và không nằm dưới hộp; đang kéo thì thôi kéo, không lưu), `presentQuickControls` từ chối, VoiceOver ẩn — hộp thoại là modal.
  - **Phủ tối** đúng hình viên một lớp đen 20% (giao diện tối 40%) như lớp mờ của hộp (`MediaDiscFaceButton`, cờ `MediaDiscWindowManager.isDiscUnderModal`); phủ chứ không hạ alpha vì alpha < 1 tắt nhoè kính. Độ tối là ước lượng, chỉnh theo máy nếu lệch.
  - Bật ngay cả khi hộp còn đang trượt lên (đặt trước nhánh chuyển cảnh của `updateDisc`).
- Bảng chia sẻ vẫn ẩn đĩa như trước.
- `.claude/rules/floating-pills.md` ghi luật mới.
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.963] - 2026-11-17

### fix: Google Chế độ AI bớt nóng máy: trang ẩn về trắng sau mỗi lượt, quét đọc trang chậm lại, máy nóng thì giãn nhịp quét

Anh Bửu báo chức năng Google AI dễ làm nóng máy. Chế độ AI chạy trang `google.com/search?udm=50` trong WKWebView ẩn; cửa sổ ẩn (`GeminiWebHiddenWindowHost`) cố ý giữ WebView ở trạng thái "hiển thị" để WebKit không tạm dừng tiến trình web (bài học 1.3.507) ⇒ trang Google chạy và vẽ như trang đang mở. Phần việc này nằm trong tiến trình web nên % CPU của app ở màn Theo dõi nhiệt không thấy.

- **Trang ẩn về trắng sau lượt** (`GoogleAIModeSessionController.schedulePark`): lượt xong 3 s mà không có lượt mới ⇒ `loadHTMLString("")` (cùng cách `abort` đã làm). Trước đó trang Google của lượt cuối nằm nguyên tới 10 phút (hạn giải phóng WebView) với JS, hẹn giờ, hoạt ảnh và con trỏ ô nhập vẫn chạy. Lượt nào cũng điều hướng lại (lượt mới ⇒ URL câu hỏi, nối tiếp ⇒ URL khôi phục `mstk`) nên không mất gì; giữ WebView + tiến trình web để lượt sau không phải dựng lại. Chờ 3 s để request cuối của trang (lưu cuộc chat, xoay cookie) xong; `beginTurn` huỷ lượt chờ.
- **Lượt không phát chữ đọc trang mỗi 1 s** (`readAnswer`, quét tên riêng + "Kiểm tra kết nối"; chat vẫn 0,3 s). Mỗi nhịp đọc gọi `innerText` của cả trang và từng lượt ⇒ WebKit tính lại style + layout. Luật xong (đứng yên 2 s + "sẵn sàng", hoặc đứng yên 8 s) đo bằng giờ thật nên giữ nguyên; nhịp đầu chạy ngay sau commit nên vẫn bắt được trạng thái "chưa sẵn sàng".
- **Máy nóng thì giãn nhịp quét** (`GoogleAIModeTurnQueue.thermalScanGap(_:)`): Ấm ⇒ nghỉ 10 s, Nóng ⇒ 20 s, Rất nóng ⇒ 60 s giữa hai lượt quét (bình thường 5 s); log `🌡️ [AIMode]` chỉ khi mức nhiệt đổi. Mỗi lượt quét là một lần nạp trang Google đầy đủ; quét cả truyện là hàng chục lượt liền. Chat không bị giãn.
- **Bằng chứng từ log build 1289** (anh Bửu gửi sau khi bật log; iPhone 11, TTS Google chỉ bận ~5%, Reader bình thường): 4 lượt quét tên riêng bằng Chế độ AI (89 / 49 / 12 / 64 lượt, ~4 s mỗi lượt, ~9 s một vòng với nghỉ 5 s). Lần nào cũng Mát → Ấm sau ~2 phút quét, → Nóng sau ~5 phút; ngừng quét thì 2–4 phút sau hạ về Ấm (08:51–08:57, 09:00–09:04, 09:15–09:17, 09:26–09:29). Vì vậy giãn nhịp từ mức Ấm chứ không chờ tới Nóng.
- `rules.md` (mục Chế độ AI, hàng đợi) ghi ba luật trên. Đẩy entry 1.3.932 sang `CHANGELOG.archive.md`.
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.962] - 2026-11-17

### fix: Giọng dự phòng nạp sẵn khi TTS online hụt lượt đầu, quay lại online thì bỏ lượt dự phòng chưa xong

Log build 1288 (bản 1.3.961) do anh Bửu gửi; anh Bửu duyệt "Sửa cả hai". Luật thử lại / chuyển / quay lại của 1.3.960 chạy đúng, còn hai chỗ chậm:

- **Nạp sẵn giọng dự phòng khi online có dấu hiệu trục trặc** (`TTSManager.prewarmOnlineFallback`, gọi từ `RemoteTTSAttemptPolicy.run` khi một lượt hụt mà còn lượt thử; mỗi phiên một lần). Trong log, lượt nạp trước của đoạn 56 hụt lần đầu ("Could not connect to the server") 7,4 s trước khi phải chuyển, nhưng VieNeu chỉ được nạp lúc chuyển ⇒ đoạn dự phòng đầu tiên tổng hợp nguội 1,9 s (RTF 0,31, các đoạn sau 0,12), khoảng lặng 2,4 s. Nay engine dự phòng (`prepare` + chạy nháp Core ML) được nạp ngay ở lượt hụt đầu. Không nạp sẵn lúc bắt đầu đọc: VieNeu (~280 MB) chỉ nên chiếm RAM khi online đã trục trặc.
- **Quay lại online thì bỏ lượt nạp trước dự phòng chưa xong** (`returnToOnline`): huỷ các lượt đó (lượt tổng hợp tự huỷ khi không còn ai chờ) rồi nạp lại cửa sổ bằng online; đoạn dự phòng đã nạp xong vẫn phát nốt. Trong log, lượt dự phòng của đoạn 66 bắt đầu 41 ms trước khi online chạy lại, chạy nốt rồi vẫn được phát bằng giọng dự phòng, trong khi online chỉ mất 0,3–0,7 s. Log dòng quay lại ghi số lượt bỏ.
- `.claude/rules/tts.md` ghi hai luật trên.
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.961] - 2026-11-16

### refactor: Cài đặt VieNeu dùng chung một bản cho Cài đặt TTS và Giọng dự phòng, chạy nháp Core ML chờ tín hiệu thay vì hỏi khoá mỗi 10 ms

Nhóm E của lượt rà soát chức năng nghe truyện (anh Bửu: "Làm E rồi push").

- **Một bản cài đặt VieNeu cho hai màn** (`VieNeuReaderManagementRows`, `VieNeuSynthesisSpeedRow` ở `Views/Settings/TTS/`): lối vào Cài đặt VieNeu TTS, công tắc từ điển phiên âm / đọc tên Nhật theo âm tiết, Picker "Đọc chậm đoạn có tên (Nano)", từ điển tiếng Nhật (lối vào hoặc cảnh báo + nút tải) và hàng Tốc độ tổng hợp. Trước đó màn Giọng dự phòng chép riêng một bản ⇒ thêm công tắc mới là phải nhớ thêm cả hai nơi. Khác biệt giữ nguyên qua tham số: màn dự phòng mở Cài đặt VieNeu TTS ở chế độ chỉ lưu lựa chọn giọng; Cài đặt TTS bỏ phần đệm đã tổng hợp khi đổi tốc độ tổng hợp (`onSaved`). Nút "Đặt lại" của Cài đặt TTS chỉ còn đặt giá trị — hàng tự lưu + bỏ phần đệm khi giá trị đổi.
- **Chạy nháp Core ML chờ tín hiệu** (`VieNeuTTSEngine.withSynthesisLock`): `readerWaitLock` thành `NSCondition`, lượt đọc nhả khoá qua `unlockForReader()` thì đánh thức luồng chạy nháp; bên giữ khoá khác không báo nên chờ có hạn 0,1 s. Trước đó luồng chạy nháp hỏi lại mỗi 10 ms — ~100 lần đánh thức CPU mỗi giây trong lúc Nano đọc liên tục. Luật nhường lượt đọc (1.3.955) giữ nguyên.
- `.claude/rules/tts-vieneu.md` ghi hai thay đổi trên.
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.960] - 2026-11-16

### fix: TTS online thử lại đúng một tầng, chậm thì đọc song song bằng giọng dự phòng, cùng các lỗi rà soát chức năng nghe truyện

Rà soát chức năng nghe truyện (13 phát hiện), anh Bửu duyệt sửa nhóm A–D. Giữa chừng anh Bửu báo: có giọng dự phòng thì không thử lại + timeout 3 s nên *"vài trường hợp bị chậm hoặc lỗi chưa kịp thử thì đã tự chuyển sang offline, nhất là khi tải trước"*. Log thật (364 phút đọc Google / `google_tts`, dòng `[TTSEnergy] Summary`): lượt thường 0,2–0,8 s; 5% số phút có lượt > 3 s mà phần lớn vẫn **thành công** (chậm nhất 6,8 s), chỉ 1 lượt > 7 s và lượt đó lỗi thật. Anh Bửu chọn "7 s + thử lại 1 + song song".

- **Thử lại + timeout chỉ còn một tầng** — `RemoteTTSSynthesisCoordinator` chạy job qua `RemoteTTSAttemptPolicy.run` (file mới). Trước đó vòng thử lại nằm trong closure của từng bên gọi ⇒ đoạn đang đọc gộp vào lượt nạp trước cùng khoá (trường hợp "hit_wait" lúc server chậm) chạy theo chính sách của lượt nạp trước: **một** lần, không thử lại ⇒ lỗi một lần là dừng đọc dù đã cài 3 lần. Nay số lượt thử đọc theo mức ưu tiên **hiện tại** của job, hỏi lại sau mỗi lượt hụt; `enqueue` / `promote` nâng cả job **đang chạy**.
- **Bỏ vòng thử riêng 2 lượt của `GoogleTTSService`** — chồng với vòng chung thành tới 8 request một đoạn, im ~30 s rồi mới dừng. Nghe thử giọng (gọi thẳng service) bọc `RemoteTTSAttemptPolicy.withRetry(maxAttempts: 2)` để giữ hành vi cũ; đọc đoạn bôi đen vốn đi qua coordinator nên nay theo cấu hình chung.
- **Không thử lại lỗi chắc chắn lặp lại**: thiếu API key / văn bản trống / URL hỏng, HTTP 400 / 401 / 403 / 404, base64 hỏng của tiện ích, lượt bị app huỷ. `Retry-After` của server được tôn trọng (tối đa 2 s).
- **Có giọng dự phòng** (`TTSOnlineSynthesisSettings`): timeout theo cài đặt (bỏ 3 s cố định), thử lại khoá **1** lần cho **cả** lượt nạp trước; chỉ chuyển cả phiên khi hết lượt thử hoặc mất mạng.
- **Đọc song song** (`TTSManager+OnlineFallbackHedge`, file mới): đoạn đang đọc quá 3 s chưa có tiếng ⇒ giọng dự phòng tổng hợp song song, bên nào xong trước phát bên đó (`TTSOnlineFallbackState.claimDelivery`); online về trước ⇒ huỷ lượt dự phòng; dự phòng phát rồi mà online vẫn thành công ⇒ đoạn sau vẫn đọc online; online hết lượt thử sau khi dự phòng đã phát ⇒ chỉ chuyển phiên, không đọc lại đoạn.
- **Giọng dự phòng huỷ lượt thừa**: lượt tổng hợp dự phòng đếm người chờ, không còn ai chờ (bỏ qua đoạn, tạm dừng, online về trước) ⇒ huỷ và gỡ khỏi `inflight`. Trước đó bấm "đoạn kế" liên tục thì đoạn mới phải chờ sau mọi lượt của các đoạn đã bỏ (hàng đợi chạy theo thứ tự trong cùng mức ưu tiên), tạm dừng thì cả cửa sổ vẫn tổng hợp rồi vứt kết quả.
- **Lượt nạp trước hết lượt thử** ⇒ bật dự phòng, bỏ mọi lượt nạp trước online đang chờ và nạp lại cửa sổ bằng giọng dự phòng **ngay** (như nhánh mất mạng của 1.3.957). Trước đó đoạn vừa hụt không ai nạp lại tới lúc nó thành đoạn đang đọc.
- **Lượt thử online ở nền** đi qua coordinator (mức `nextChapter`, một lượt) — gọi thẳng service thì chạy chồng lượt tiện ích khác trên cùng runtime JS, hết giờ là huỷ luôn lượt kia.
- **Ghi tiếng online luôn xoá dấu "dự phòng"** (`storeOnlineAudio`: nạp trước từng đoạn, nạp gộp Google, lượt thử ở nền) và dấu của chương khác bị bỏ khi lưu lượt mới. Trước đó đường nạp gộp không xoá dấu ⇒ đoạn online phát theo tốc độ giọng dự phòng + hiện badge "Dự phòng". (Chương kế / prefix chương không bị: chúng ghi ngay sau `forgetChunks`.)
- **Khoá tổng hợp của giọng dự phòng** dùng `TTSSynthesisIdentity.computeKey` (SHA-256) thay hàm băm djb2 tự viết.
- **Tên Nhật có gạch nối tra từ điển phiên âm theo từng phần** (`VieNeuJapaneseNameReader.replacement(for:dictionary:)`): trước đó mục "Sasuke" của người dùng áp cho "Sasuke nói" nhưng "Sasuke-kun" vẫn đọc theo âm tiết tự động. Bộ phân loại đọc lai (`readsSuffix(_:afterHead:dictionaryKeys:)`) theo cùng luật.
- **Sheet nghe mini**: tra lại badge khi đoạn thật sự bắt đầu phát (`$playbackSnapshot` thôi "đang chuẩn bị") ⇒ đoạn đọc bằng giọng dự phòng ngay lúc chuyển giờ có badge "Dự phòng" + RTF; RTF chỉ hiện khi tiếng đoạn do engine offline tạo.
- **Đổi nguồn lúc đang nghe**: lượt tự nghe tiếp ở truyện mới chỉ chạy khi phiên chưa đổi trong lúc tải chương — người dùng tự bấm nghe / dừng thì không bị kéo về chương cũ.
- **Mục "TTS online" của Cài đặt TTS**: có giọng dự phòng thì hàng Thử lại khoá ở 1, Timeout vẫn sửa được; chữ giải thích theo luật mới; đọc khoá giọng dự phòng qua `@AppStorage` nên chọn / bỏ giọng dự phòng rồi quay lại là mục vẽ lại ngay. Màn Giọng dự phòng thêm một đoạn giải thích.
- `RemoteTTSSynthesisCoordinator.swift` giữ dưới trần 429 dòng: `energyPrediction` sang `RemoteTTSSynthesisCoordinator+EnergyPrediction.swift`, tên mức nhiệt dùng chung `NghiSynthesisPolicy.thermalStateName`.
- `rules.md` (§5.7.1 + ba luật retry cũ của 1.3.330–1.3.334) và `.claude/rules/tts.md` ghi luật thử lại mới.
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.959] - 2026-11-16

### docs: gọn AGENTS.md thành bản lõi, CLAUDE.md chỉ import @AGENTS.md, ghi chú phân hệ tách sang .claude/rules

Anh Bửu chạy `/doctor`: `/usage` báo `CLAUDE.md` (128.843 ký tự ≈ 32k token) chiếm ~31% lượng dùng vì Claude Code nạp lại nó ở **mọi** request, dù phần lớn chỉ cần khi sửa một phân hệ. Anh Bửu duyệt: "dọn dẹp AGENTS.md như bạn nói, rồi ở CLAUDE.md chỉ cần @AGENTS.md".

- **`AGENTS.md` = bản lõi dùng chung** (~19,7k ký tự): quy trình bắt buộc, thứ tự thẩm quyền, CHANGELOG, lệnh, build / CI / môi trường, luật `check_architecture.py`, ràng buộc runtime chung, quy ước đặt tên, Tests, Bẫy đã xác minh, cộng bảng mục lục `.claude/rules/` và 5 bẫy dùng chung nhiều phân hệ.
- **`CLAUDE.md` chỉ còn `@AGENTS.md`** (Claude Code nạp qua import) — từ nay chỉ sửa `AGENTS.md`, bỏ luật mirror hai file.
- **14 file `.claude/rules/*.md`** chép **nguyên văn** các mục phân hệ (storage, reader-text-pipeline, tts, tts-vieneu, translation, extensions-js, comic-video, audio-playlist, floating-pills, browser, books-sources, network-dns, ci-release, ui-conventions). Mỗi file khai `paths:` nên Claude Code chỉ nạp khi đọc / sửa file khớp; Codex và agent khác đọc theo mục lục. Ghi chú mới của một phân hệ thì thêm vào đúng file đó.
- **Thiết lập codegraph trên máy mới** thành skill `.claude/skills/codegraph-setup/SKILL.md`. `.gitignore` thêm `!.claude/rules/`.
- **Bỏ 6 câu cũ / suy ra được từ code**: câu CHANGELOG lặp, mô tả `codegraph.json`, dòng code signing / iOS 17 / danh sách SPM (đã thiếu gói), "88 entry hết hạn 2026-12-31", "814 file Swift", "(19 file)" + danh sách file `+` (nay 343 file).
- Kiểm: script đối chiếu từng dòng không rỗng của `CLAUDE.md` cũ — mọi dòng (trừ 6 câu trên và tiêu đề mục đổi thành tiêu đề file) có mặt nguyên văn trong bộ file mới. Không đổi code, không build.

## [1.3.958] - 2026-11-16

### fix: RTF trên sheet nghe mini chia cho thời lượng lời đọc, không tính khoảng lặng chèn thêm

Anh Bửu: *"rtf có chính xác không vậy, sao tôi thấy tts engine nào cũng thấp hết vậy"* rồi duyệt "Đổi, bỏ khoảng lặng". Số là số đo thật và thấp là đúng với máy (Nano + Core ML 0,09–0,13 ở log build 1285), nhưng mẫu số từ 1.3.954 là `pcmDuration` — gồm cả khoảng nghỉ giữa các chunk và khoảng lặng đuôi theo ranh giới, là phần không tốn công tổng hợp. Đoạn dài gần như không lệch (7,46 s: 0,097 so với 0,099); đoạn ngắn lệch rõ ("Ninh công tử?" 0,89 s lời + 0,20 s lặng: 0,45 so với 0,56).

- **Một công thức, một chỗ:** `TTSEngineRTFStore.record(text:synthesisMs:speechSeconds:)` tự chia; ba engine chỉ đưa thời gian tổng hợp và thời lượng lời đọc. Lời đọc dưới 0,05 s (đoạn im lặng) thì không ghi ⇒ badge ẩn thay vì hiện "RTF 0.00".
- **Nano:** dùng `output.speechDuration` engine đã tính sẵn.
- **Turbo:** `pcmDuration − pause` — nay khớp với `RTF=` của dòng log `[VieNeuTurbo] Đoạn` (trước đó badge và log của cùng một đoạn ra hai số khác nhau).
- **Piper / NghiTTS:** `ONNXPiperEngine.synthesizeInternal` đếm số mẫu lặng chèn thêm (khoảng nghỉ theo dấu câu giữa các chunk + khoảng lặng đuôi) và trả thêm `speechDuration`; `PiperSynthesisPayload` có thêm trường `speechDuration` (không truyền ⇒ bằng `pcmDuration`), `PiperSynthesisCoordinator` chuyển tiếp.
- **Không đổi:** `rtf=` trong log `[VieNeuPerf]` và `[NghiEnergy]` vẫn chia cho `pcmDuration` (log đã in riêng `speech=`), bộ thích nghi chế độ của Nano cũng vậy. RTF vẫn so với thời lượng tiếng ở tốc độ **tổng hợp**, không nhân tốc độ phát, và chỉ đo lúc engine chạy (không gồm thời gian chờ hàng đợi / chờ khoá).
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), chưa thử trên máy.

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
