# CHANGELOG - Nhật ký Thay đổi CodeGraph Tàng Công Các

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **Tàng Công Các**.

## [1.3.1058] - 2026-11-24

### fix: Kệ Sách và sheet "+" Chi tiết bỏ "Ch. N", thẻ ghi tên chương đang đọc

Anh Bửu: không hiển thị chương kiểu "Ch. stt" → duyệt mockup https://claude.ai/artifact/2fREpEgACNQJVkuwVMhyoj (sheet "+" ghi "N chương").

- `BookListRowSize.progressLabel(kind:chapterIndex:chapterTitle:options:)`: truyện chữ / truyện tranh trả **tên chương đã lưu** (`Book.currentChapterTitle`, dịch theo `options`), tên rỗng mới "Chương N"; phim "Tập N", âm thanh "Bài N" giữ nguyên. Dùng chung cho thẻ Kệ kiểu Lưới (dòng "icon · tên chương · ⋮") và Chỉ bìa (dải chữ đáy bìa) — `ShelfBookGridCardView`, dòng gọn nấc 1–2 "tác giả · tên chương" — `BookListItemView` (cũng ở Tìm trên kệ, hai sheet chọn truyện của Từ điển), và dải "Đọc tiếp" (`BookContinueReadingStrip`, trước tự tính riêng). Dòng thường nấc 3+ vẫn "Đang đọc: tên chương" như cũ.
- Sheet "+" của Chi tiết (`BookDetailView+FloatingActions.floatingSheetCaption`): "Ch. N/tổng" ⇒ "N chương" (tổng), đã lưu hay chưa đều vậy; dòng "Đọc tiếp" của sheet đã có tên chương.
- Đánh đổi (đã nêu trong mockup): kiểu Lưới 3 cột chỉ còn ~65 pt cho chữ cạnh ⋮ ⇒ tên chương bị cắt "…"; tên nguồn tự mở đầu "Chương 340: …" thì ô Lưới vẫn chỉ thấy "Chương 34…".
- `ui-conventions.md`: luật "Không hiển thị kiểu Ch. stt" ghi đã xong + hàm dùng chung; luật video / audio ghi rõ anh chỉ yêu cầu context menu.
- **Kiểm**: đọc code + `check_architecture.py` (chỉ còn violation cũ `JSDom.swift`, **0 mới**); **không build tại chỗ (Windows), chưa thử trên máy**.

## [1.3.1057] - 2026-11-24

### fix: mục lục sheet nghe mini — hiện nhanh lại (hàng là struct riêng, bỏ .id, tên chương dịch theo ô đang hiện)

Anh Bửu: "Danh sách chương của sheet nghe truyện mini hiển thị lên quá chậm. Hiển thị chậm do bạn mới fix gần đây" (sau 1.3.1053).

- **Nguyên nhân** (`TTSQuickTimerChapterList`, bản 1.3.1053): mỗi hàng của `ForEach` gắn `.id(chapter.index)` và closure hàng dịch tên chương ngay tại chỗ (`Text(TTSManager.shared.displayTitle(for:))`). `List` duyệt closure của **mọi** chương để lấy danh tính hàng ⇒ dịch cả N tên trên main **trước khung đầu**; `TranslateUtils.chapterTitleCache` chỉ 1024 mục nên mục lục dài hơn bị đẩy cache, mở lần nào cũng dịch lại hết. Bản `LazyVStack` cũ chỉ trả cho hàng 0…k (tới chương đang nghe) và sau khi sheet đã hiện ⇒ 1.3.1053 chậm hơn, nhất là khi đang nghe gần đầu truyện. `TabView(.page)` dựng sẵn trang bên cạnh nên mở ⏱ cũng chịu.
- **Sửa**: hàng tách thành struct `ChapterRow` (đầu vào: chương, đang phát, số chữ số cột thứ tự); tên chương tính trong `body` của hàng ⇒ chỉ ô đang hiện mới dịch. Closure của `ForEach` chỉ dựng struct + ba `listRow*`, bỏ `.id(chapter.index)` — `scrollTo` dùng id của `ForEach` (`\.index`). Mốc `TranslationDisplayRevision` đọc ở `body` của hàng (đọc ở danh sách thì hàng có đầu vào không đổi bỏ qua `body`, tên cũ nằm lại sau khi sửa VP / Name / rule). Giữ `List`, `TTSChapterListReader`, giao diện như 1.3.1053.
- `CHANGELOG.md` dời 1.3.1027 sang `CHANGELOG.archive.md` (giữ 30 entry).
- **Kiểm**: đọc code + `check_architecture.py` (chỉ còn violation cũ `JSDom.swift`, **0 mới**); **không build tại chỗ (Windows), chưa thử trên máy**. Cách thử: bật log; truyện > 1024 chương, bật dịch; thử khi đang nghe chương gần đầu và gần cuối; mở từ Mục lục và từ ⏱ ⇒ danh sách hiện ngay, nằm giữa đúng chương đang nghe; cuộn lúc TTS đang đọc; sửa một mục VP lúc sheet mở ⇒ tên chương đổi.

## [1.3.1056] - 2026-11-24

### fix: sheet tuỳ chọn của video / audio ghi "video" / "audio" thay cho "truyện"

Anh Bửu: "context menu của video, audio thì hiển thị chữ video, audio chứ đừng hiển thị truyện".

- `ExtensionContentKind.shelfItemNoun` (mới): "truyện" (chữ, truyện tranh) / "video" / "audio"; loại suy bằng `BookContentKindResolver.kind` như lối mở nội dung (ghi đè loại của nguồn Legado thắng).
- `BookActionSheet`: tiêu đề phần đầu "Truyện" ⇒ "Video" / "Audio"; chú thích Bộ sưu tập "… không xoá video khỏi kệ sách"; lời nhắc của hộp Bộ sưu tập mới; nhãn trợ năng của ô "Bỏ khỏi bộ sưu tập này". Toast `BookActionRunner.removeFromCollection` "(video vẫn ở trên kệ)".
- Ghi luật vào `ui-conventions.md`. Chỗ khác còn "truyện" chung (thanh chọn nhiều, Kệ, Lịch sử) chưa rà.
- **Kiểm**: đọc code + `check_architecture.py` (chỉ còn violation cũ `JSDom.swift`, **0 mới**; `BookActionSheet.swift` 396/400 dòng); **không build tại chỗ (Windows), chưa thử trên máy**.

## [1.3.1055] - 2026-11-24

### fix: dải "Đọc tiếp" bỏ tiền tố "Ch. N", chỉ ghi tên chương

Anh Bửu: "Bỏ chữ Ch. stt đi, ghi nhớ rule không được hiển thị kiểu Ch. stt".

- **Dòng phụ** của dải "Đọc tiếp" (`BookContinueReadingStrip`, 1.3.1054): truyện chữ / truyện tranh giờ **chỉ ghi tên chương** đã lưu (dịch như tên chương "Đang đọc"), bỏ "Ch. N · " phía trước; tên rỗng mới lùi về "Chương N" như widget TTS (1.3.804). Phim / âm thanh giữ "Tập N · m:ss" / "Bài N · m:ss".
- **Luật mới** ở đầu `.claude/rules/ui-conventions.md`: không hiển thị chương kiểu "Ch. stt" ("Ch. N", "Ch. N/tổng") ở UI mới. Chỗ cũ còn "Ch. N" (thẻ Kệ — `BookListRowSize.progressLabel`, sheet "+" của Chi tiết — "Ch. N/tổng") **chưa đổi**, chờ anh quyết.
- **Kiểm**: đọc code + `check_architecture.py` (chỉ còn violation cũ `JSDom.swift`, **0 mới**); **không build tại chỗ (Windows), chưa thử trên máy**.

## [1.3.1054] - 2026-11-24

### feat: Kệ Sách — nút "Đọc tiếp" ở đầu sheet tuỳ chọn truyện (nhãn theo loại, dòng phụ chương đang đọc)

Anh Bửu: thêm nút "Đọc tiếp" vào đầu menu của mỗi truyện ở Kệ Sách → duyệt mockup https://claude.ai/artifact/KGiBWCBGdKdrc5z7MJ8rWg với các phương án mặc định.

- **Menu là sheet ⋮**: Kệ không có context menu hệ thống (nhấn giữ ở Kệ / Lịch Sử là chọn nhiều, 1.3.1039); menu của một truyện là `BookActionSheet`. Dải mới là **section riêng ngay dưới phần đầu** (phương án A), trên Bộ sưu tập; hiện ở cả bốn nơi mở sheet (Kệ, Lịch Sử, Bộ sưu tập, Tìm trên kệ) và mọi kiểu hiển thị.
- **Nhãn** (`BookContinueReadingStrip`, mới): Đọc (chữ, truyện tranh) / Xem (phim) / Nghe (âm thanh) + "tiếp"; vị trí đang lưu ở đầu chương / tập / bài đầu tiên ⇒ "… ngay" như nút đọc của Chi tiết. Xét theo vị trí, không theo `isHistory` (tiện ích tắt Lưu lịch sử, truyện thêm kệ từ Chi tiết không bật cờ đó). Icon: chữ / truyện tranh `book.fill` ("tiếp") hoặc `play.fill` ("ngay") như Chi tiết, phim `play.fill`, âm thanh `headphones`.
- **Dòng phụ**: "Ch. N · tên chương đã lưu" (dịch như tên chương "Đang đọc") / "Tập N · m:ss" / "Bài N · m:ss"; không có phần trăm vì `Book` không lưu tổng số chương lẫn số đoạn. `BookActionStrip` thêm `subtitle` tuỳ chọn (hai dòng, tên đậm hơn); dải "Đổi nguồn" / "Chuyển sang nguồn …" không đổi.
- **Mở y như chạm thẻ**: `ShelfReaderRoute(resuming:)` (mới, `ShelfReaderRoute+Resume.swift`) dùng chung cho chạm thẻ ở Kệ / Lịch Sử / Bộ sưu tập / Tìm trên kệ và nút mới ⇒ `BookContentDestination` chọn Reader / truyện tranh / màn xem / màn nghe. Lịch Sử vẫn không `markSeen` (`ShelfView.handleBookAction` nhận thêm `mode` của sheet). Route xếp hàng ở `queuedReaderRoute`, mở trong `onDismiss` của sheet như `queuedBrowserBook` (cover bật lên lúc sheet còn trượt xuống thì không hiện).
- `BookSheetAction.continueReading`; ba `switch` (Kệ, Bộ sưu tập, Tìm trên kệ) thêm nhánh. Ghi chú vào `ui-conventions.md`.
- Trường hợp biên giống chạm thẻ: truyện đang tải, truyện mất nguồn (dải "Chuyển sang nguồn …" vẫn ở phần Thao tác), TTS đang đọc truyện khác. TTS đang đọc chính truyện này: dòng phụ có thể chậm một nhịp (tiến độ ghi trễ), mở như chạm thẻ; chưa xác minh Reader có tự theo chương TTS khi lệch.
- `CHANGELOG.md` dời 1.3.1024 sang `CHANGELOG.archive.md` (giữ 30 entry).
- **Kiểm**: đọc code + `check_architecture.py` (chỉ còn violation cũ `JSDom.swift`, **0 mới**); **không build tại chỗ (Windows), chưa thử trên máy**.

## [1.3.1053] - 2026-11-24

### fix: mục lục sheet nghe mini — hết đơ khi truyện nhiều chương (List thay LazyVStack, thôi observe TTSManager)

Anh Bửu: mở mục lục từ sheet nghe mini bị hơi đơ khi truyện có nhiều chương.

- **Nguyên nhân 1 (lúc mở)**: `TTSQuickTimerChapterList` dựng bằng `ScrollView` + `LazyVStack`, 0,1 s sau khi hiện thì `scrollTo` chương đang nghe (giữa màn) ⇒ `LazyVStack` dựng + đo **mọi** hàng phía trước trên main (cùng bài học "neo sâu" của Reader), mỗi hàng còn dịch tên chương (`displayTitle(for:)`) — đang nghe chương 2000 là 2000 hàng một lượt, đúng lúc sheet trượt lên. Mục lục Reader không bị vì dùng `List` (ô tái dùng, nhảy bằng chiều cao ước lượng). Sheet mini **không** dùng chung view với mục lục Reader / Chi tiết / truyện tranh.
- **Nguyên nhân 2 (lúc cuộn)**: sheet Hẹn giờ (`TTSQuickTimerSheet`) và danh sách `@ObservedObject` thẳng `TTSManager` (trái luật View không observe `TTSManager`) ⇒ mỗi câu (chỉ số đoạn, highlight, snapshot), mỗi lần đệm tiếng đổi, mỗi giây hẹn giờ… dựng lại cả sheet và `ForEach` vài nghìn chương.
- **Sửa**:
  - Danh sách → `List(.plain)` như mục lục Reader: nền trong suốt, hàng không vạch, lề hàng 4 / 16 + `contentMargins` dọc 4 ⇒ thẻ, khoảng cách 8, cột số, ô tìm, nút tìm nổi giữ nguyên; vẫn cuộn tới chương đang nghe lúc mở.
  - `TTSChapterListReader` (mới, `Views/TTSWidget/`): chỉ phát `chapters` (`$chaptersQueue`) + `playingChapterIndex`; sheet giữ bằng `@StateObject`, danh sách nhận qua tham số ⇒ nhịp đọc không chạm danh sách. Tên chương vẫn `TTSManager.displayTitle(for:)` (cặp với ô tìm `matchingChapters`); danh sách đọc `TranslationDisplayRevision` để vẽ lại khi từ điển / rule / cấu hình dịch đổi (trước đây nhịp TTS vẽ lại hộ).
  - Sheet Hẹn giờ thôi `@ObservedObject`: hẹn giờ + bìa qua `TTSWidgetStateReader`, tên truyện / chương qua `TTSWidgetBarInfoReader`, số chương qua `TTSChapterListReader`; tác giả / tên nguồn / tiện ích đọc `TTSManager.shared` lúc dựng (chỉ đổi theo truyện); nút ⚙ vẫn qua `TTSSettingsSheetHost`.
  - Log: mở / đóng danh sách gọi `MainThreadHangMonitor.noteScreen("mục lục TTS mini")` + dòng `📑 [TTSTOC] Mở mục lục sheet nghe (N chương, đang nghe chương k)` ⇒ dòng `🐢 [MainHang]` lúc mở ghi kèm bối cảnh này.
- `TabView(.page)` của sheet có thể dựng sẵn trang mục lục bên cạnh ⇒ mở ⏱ Hẹn giờ trước đây cũng có thể khựng — cùng được sửa.
- `CHANGELOG.md` dời 1.3.1023 sang `CHANGELOG.archive.md` (giữ 30 entry).
- **Kiểm**: đọc code + `check_architecture.py` (chỉ còn violation cũ `JSDom.swift`, **0 mới**); **không build tại chỗ (Windows), chưa thử trên máy**. Cách thử: bật log, truyện vài nghìn chương đang nghe chương xa đầu ⇒ chạm đĩa nghe ⇒ Mục lục ⇒ cuộn.

## [1.3.1052] - 2026-11-24

### feat: vtts — giọng nu-10 dùng model mới của tác giả (train giai đoạn cuối 80.000 bước), tài sản theo release v0.11.0

Anh Bửu: "tìm cách khác fix lỗi rè đi" → duyệt phương án: (1) thay nu-10 bằng bản mới của upstream ngay, (2) chạy tiếp Ngọc Huyền + Google Dịch tới 80.000 bước khi GPU Kaggle mở lại 28/11.

- **Phát hiện**: sau commit runtime app đang ghim (`c5c8c00`), upstream `tuanpmt/vtts` đổi công thức chưng cất "trò": giai đoạn joint **80k bước thay 20k** (v0.9.1, 2026-11-20) vì bản 20k kém thầy ~1 điểm UTMOS và có lớp ồn "buzzy"; `nu-10` M đo UTMOS vi / en / trộn 2,73 / 3,44 / 2,70 → **3,11 / 3,87 / 3,12**, CER không đổi. Hai giọng tự train (Ngọc Huyền, Google Dịch) dùng đúng công thức 20k (đo 23/11 trên 2 câu: trò 2,57 / 2,79, thầy Google 3,70).
- **Bản này**: `assets/vtts/vtts-vien-nu10-m-v0.11.q8.vtts` (= model v0.9.1, release `v0.11.0`, SHA256 `89ce7264…`) thay bản v0.4; bản S dự trữ `extra/…nu10-s-v0.11` (= v0.10.2). `nam-1` chưa có model mới — file v0.11 **trùng byte** v0.4.0, chỉ đổi tên để cả 4 file cùng một release. `assets/SHA256SUMS` = 4 dòng vi-en nguyên văn của `SHA256SUMS` release v0.11.0. Id giọng `nu-10` / `nam-1` giữ nguyên ⇒ lựa chọn đã lưu không đổi.
- **Kiểm tại chỗ**: SHA256 khớp release; header file mới trùng bản cũ từng mục (33 dims, 122 tensor: tên / kiểu / shape, 2.580.320 byte, bộ token vi-en) ⇒ runtime ghim đọc cùng đường. Tiếng thật do bước đọc thử của CI kiểm (`check_vtts_assets.sh`).
- Sửa tên file ở `VttsVoice`, `VOICES` của script, bước Package IPA của workflow, `THIRD_PARTY_NOTICES.md`, `Vendor/vtts/README.md` (release gộp nhiều giọng ⇒ chỉ lấy các dòng SHA256 của file mình dùng), `ci-release.md`, `tts.md`.
- Chưa làm: `VttsVoice.nu10.defaultLoudnessGainDb` (10,5, chỉ dùng cho đoạn có tiếng < 0,4 s) đo trên bản v0.4, chưa đo lại. Chưa build được tại chỗ (Windows). Chưa thử máy.

## [1.3.1051] - 2026-11-24

### fix: header trình duyệt và màn Trợ lý AI không còn bị trong suốt

Anh Bửu gửi ảnh: "khi nhấn các button sẽ hiển sheet như cài đặt trình duyệt ở trình duyệt sẽ bị lỗi trong suốt phần header của trình duyệt" (header lộ Kệ Sách phía dưới), rồi "bấm dừng trong AI, header bị trong suốt" (chữ chat hiện xuyên header) → "Tự duyệt đi".

- **Trình duyệt** (`BypassWebView`): `VStack` gốc tự tô `Color(.systemBackground).ignoresSafeArea()` (cách `LegadoBrowserSheet` đã dùng). Trước đó header, dải tab, vạch tiến độ, trang Home không có nền riêng mà trông vào nền của màn che toàn màn; nền đó mất sau khi mở sheet (nghi từ 1.3.873 — sheet kính `presentationBackground`) ⇒ lộ màn phía dưới. Thanh dưới có `barColor` riêng nên không bị. Áp cho mọi lối mở trình duyệt (Kệ, Chi tiết, Reader, Khám phá, Mở link lỗi, tiện ích, Legado, tra từ); lúc bình thường giao diện không đổi.
- **Trợ lý AI** (`ReaderAIFullScreenView`): `.toolbarBackground(.visible, for: .navigationBar)` — nền thanh điều hướng luôn hiện. Trước đó bấm Dừng lúc lọc name nhiều chương ⇒ dải tiến độ trên cùng biến mất, khung chat dâng lên sát header mà thanh không nhận ra có nội dung bên dưới ⇒ giữ nền trong suốt, chữ chat lộ qua tiêu đề. Đổi nhỏ: chat ngắn (chưa có gì dưới header) thì header cũng có nền mờ tối thay cho đen trơn.
- Nguyên nhân suy từ code, chưa kiểm trên máy. Chưa build được tại chỗ (Windows). Cần thử: trình duyệt mở từ Kệ ⇒ mở / đóng Cài đặt trình duyệt, Lịch sử ⇒ header vẫn đặc; Trợ lý AI ⇒ Lọc name nhiều chương ⇒ Dừng ⇒ cuộn chat, chữ không lộ qua header.

## [1.3.1050] - 2026-11-23

### revert: TTS — gỡ hàng Âm lượng theo giọng (1.3.1047–1048), vtts nhỏ đi 3 dB cố định, giữ đọc 1×

Anh Bửu: "bỏ mấy cái sửa sau này đi, đâu fix được đâu" → "lúc trước bị to quá, giảm bớt chút" → hỏi "đọc 1× là sao", nhắc "ko làm 1x vì nó dễ có vụt vụt" → "tạm thời làm đi, tôi sẽ test và nói bạn sau".

- **Chẩn đoán rè đã xong** (2026-11-23, anh nghe tai nghe Bluetooth): Nữ nu-10 / Nam nam-1 rè do vtts **tự đọc nhanh** — hết rè từ 1.3.1049 (đọc 1×). Google Dịch rè **có sẵn trong tiếng Google Dịch gốc** (gốc / thầy / trò "rè như nhau"; anh giữ giọng). Ngọc Huyền: thu âm gốc rè nhẹ, model làm nặng thêm. Âm lượng, bộ ghìm đỉnh, EQ, cắt trên 5 kHz đều không phải nguyên nhân.
- **Gỡ** (đảo 99d493ef + 793a6b08 + phần âm lượng của 47613e05): `TTSVolumeSettings`, `TTSVolumeStage`, `TTSPeakLimiter` (thuật toán về lại `VttsLoudness`), `TTSVolumeRow` ở Cài đặt TTS + màn Giọng dự phòng (kèm nút "?" mới của NghiTTS, đoạn giải thích Âm lượng), mức Google Dịch −3, ghìm đỉnh thêm cho NghiTTS / VieNeu Nano / Turbo / đọc lai, `vol=` trong khoá tổng hợp / snapshot / fingerprint dự phòng / log ⇒ NghiTTS và VieNeu nghe đúng như trước 1.3.1047. Khoá `ttsVolumeOffsets` còn sót trong `UserDefaults` máy đã chạy 1.3.1047–1049, vô hại.
- **vtts nhỏ đi 3 dB, cố định cho mọi giọng**: `VttsLoudness.targetRMSDb` −14 → **−17 dBFS** (≈ −19 LUFS, ngang Google online; mức −17 anh từng nghe trên máy tính không rè). Đoạn ngắn: `VttsVoice.defaultLoudnessGainDb` (đo cho mốc −14) + phần chênh của mốc (`fallbackGainReferenceDb`).
- **Giữ từ 1.3.1049**: "vtts tự đọc nhanh tối đa" mặc định 1,0 (đọc 1×, trình phát kéo cả tốc độ), xoá giá trị đã lưu một lần, "Đặt lại" xoá khoá. Rủi ro "vụt" ở chỗ nối khi trình phát kéo (lý do 1.3.1036 chuyển sang tự đọc nhanh): từ đó đã có phân đoạn 500 + `VttsEdgeFade`; anh sẽ thử — còn "vụt" thì chọn mức giữa (vd 1,2) hoặc làm nhỏ dần đuôi mạnh hơn.
- Cập nhật `.claude/rules/tts.md` (đoạn "Hàng Âm lượng đã gỡ"), `tts-vieneu.md` về như cũ. Chưa build được tại chỗ (Windows). Chưa thử máy.

## [1.3.1049] - 2026-11-23

### fix: vtts — đọc 1× để hết rè (tự đọc nhanh tối đa mặc định 1,0, xoá giá trị 1,4 đã lưu), âm lượng mặc định về như 1.3.1047

Anh Bửu thử 1.3.1048 (mọi giọng vtts −6 dB): "vẫn rè, nghe khó chịu hơn lúc nãy" ⇒ âm lượng / bộ ghìm đỉnh không phải nguyên nhân trên điện thoại → Javis đề xuất cho vtts đọc 1× → "Duyệt, làm đi".

- **Vì sao nghi khâu tự đọc nhanh**: mọi bản anh nghe sạch trên máy tính đều do vtts đọc 1×; trên máy anh nghe 1,8× ⇒ vtts tự đọc 1,4× (`length_scale` 0,71) + trình phát kéo 1,29×. Anh chỉ bắt đầu kêu rè từ 1.3.1036 (bản thêm tự đọc nhanh; ngay sau đó "âm điệu khác", "không rõ lời", và bản thường / bản 4 cùng tự đọc nhanh "nghe như nhau"). Google online — sạch trên cùng máy — cũng tạo tiếng 1× rồi để `AVAudioPlayer` kéo cả 1,8×.
- **`VttsSettings.defaultNativeSpeedMax` 1,4 → 1,0** ⇒ vtts tạo tiếng 1×, trình phát kéo cả tốc độ nghe (như trước 1.3.1036). Rủi ro đã biết: tiếng "vụt" ở chỗ nối từng xuất hiện khi trình phát kéo nhanh — từ đó đã có phân đoạn 500 + `VttsEdgeFade` (lần anh thử 1× / 500 sạch); quay lại thì kéo hàng "vtts tự đọc nhanh tối đa" lên.
- **Xoá giá trị đã lưu một lần** (`VttsSettings.nativeSpeedDefaultMigration`, lần đọc `vttsNativeSpeedMax` đầu tiên, cờ `vttsNativeSpeedMaxResetTo1`, log `🗣️ [Vtts]`): "Đặt lại" trước đây ghi **cứng** 1,4 vào khoá nên mặc định mới không tới được. Nay "Đặt lại" (Cài đặt TTS + màn Giọng dự phòng) **xoá khoá** (`VttsSettings.resetNativeSpeedMax`). Đoạn "?" của hàng: tự đọc nhanh nhiều "dễ rè", mặc định 1,0x = trình phát kéo cả.
- **Âm lượng về như 1.3.1047**: mặc định 0, Google Dịch −3 (bỏ `vttsDefaultOffset` −6 và lượt chuyển của 1.3.1048 — máy đã chạy 1.3.1048 thì các mục vtts to hơn −6 đã bị bỏ, mục dưới −6 giữ). Đoạn "?" Âm lượng bỏ câu "vtts mặc định −6".
- Cập nhật `.claude/rules/tts.md`. Chưa build được tại chỗ (Windows). Chưa thử máy. Vẫn rè ⇒ hỏi loa ngoài hay tai nghe: loa ⇒ cắt trầm mạnh hơn (giọng vtts 40–50% năng lượng < 300 Hz), tai nghe ⇒ bỏ nâng 2,8 kHz.

## [1.3.1048] - 2026-11-23

### fix: vtts — mọi giọng mặc định −6 dB cho hết rè (bộ ghìm đỉnh không phải cắt), mức đã chỉnh to hơn tự về −6

Anh Bửu: "vtts giảm âm lượng vẫn bị rè, tất cả giọng đều có độ rè" → "4 giọng của vtts bị rè hết ấy" → "lười thử quá" ⇒ Javis tự quyết → anh hỏi mức trước khi tăng âm lượng → "Duyệt, làm đi".

- **Nguyên nhân** (đo lại bộ nghe thử 1.3.1047): bản anh nghe rè (−14 dB, có / không lọc) là bản **bộ ghìm đỉnh phải cắt** — đỉnh chạm −1 dBFS; bản −17 / −20 dB không chạm trần (đỉnh −2,6 … −6,4 dBFS), kể cả bản có đủ lọc 150 Hz + nâng 2,8 kHz ⇒ rè đi theo bộ ghìm, không theo EQ (giữ "bản 4"). Log máy anh ở −14 dB ghìm tới −5,5 dB ở đoạn đỉnh cao ⇒ mặc định −3 của Google Dịch chưa đủ, ba giọng kia còn 0.
- **`TTSVolumeSettings.vttsDefaultOffset` = −6** cho mọi giọng vtts (kể cả giọng tự nhập) ⇒ mức đích `VttsLoudness` −20 dBFS: to hơn tiếng gốc model (≈ −7 … −10,5 dB trên thang này), nhỏ hơn Google online (≈ −4 dB) khoảng 2 dB. NghiTTS / VieNeu giữ 0.
- **Chuyển một lần** (`vttsDefaultMigration`, lần đọc bảng đầu tiên, cờ `ttsVolumeOffsetsVttsDefaultMinus6`): mục vtts anh đã chỉnh to hơn −6 bị bỏ ⇒ về mặc định mới, mục nhỏ hơn giữ nguyên; log `🔊 [TTSVolume]`. Mức ≠ 0 ⇒ khoá tổng hợp vtts đổi ⇒ tiếng đã đệm được tạo lại.
- Đoạn giải thích Âm lượng (nút "?") nói rõ ghìm càng nhiều càng rè + vtts mặc định −6. Cập nhật `.claude/rules/tts.md`.
- Chưa build được tại chỗ (Windows). Chưa thử máy. Vẫn rè ⇒ nghi kế tiếp là trình phát kéo nhanh (1,8× ⇒ kéo thêm ~1,29×), rồi mới tới EQ.

## [1.3.1047] - 2026-11-23

### feat: TTS — hàng Âm lượng theo giọng cho vtts, NghiTTS, VieNeu (Google Dịch mặc định −3 dB cho hết rè, ghìm đỉnh mềm)

Anh Bửu: "giọng Google Dịch bị rè quá" → 5 bản xử lý sau đều rè → chẩn đoán từng khâu (Kaggle CPU `vtts-k5-diagnose`): không khâu nào rè ở −20 dB → "có khi nào do tăng âm lượng" → bộ nghe tách yếu tố: cùng câu kéo lên −14 dB (mức app) có / không lọc đều rè, −17 dB không rè ⇒ **app kéo to quá**, model không cần train lại → "thêm config tăng âm lượng" → rà mọi trình đọc → "Làm cho cả ba" → duyệt mockup https://claude.ai/artifact/SiAJyQbt7tgWohnCJesDcg.

- **`TTSVolumeSettings`** (mới, `Services/TTS/Loudness/`): số dB to / nhỏ hơn mức app vẫn kéo (0 = như trước), −12…+4, lưu riêng từng cặp trình đọc + giọng trong một khoá JSON `ttsVolumeOffsets` (chỉ mục khác mặc định). Mặc định 0, riêng vtts Google Dịch −3 (= mức −17 dB anh nghe không rè). Khoá giọng: vtts `VttsVoice.id`, NghiTTS tên giọng, VieNeu `"nano:<tên>"` / `"turbo:<id>"`.
- **Áp vào tiếng**:
  - vtts: mức đích `VttsLoudness` = −14 + dB (mức âm được hạ tới đúng mức đó; 0 dB y như cũ), đoạn ngắn = mức cố định của giọng + dB; log `vol=`.
  - NghiTTS: `PiperTTSService` nhân dB lên WAV + ghìm đỉnh (`TTSVolumeStage.applyToWAV`; 0 dB không đụng).
  - VieNeu Nano (`VieNeuTTSEngine`, sau khi ghép mảnh) và Turbo (`VieNeuTurboTTSService`): nhân dB + **luôn ghìm đỉnh** — trước đây Nano cân mảnh ±4 dB không ghìm, mảnh đỉnh cao bị `WAVEncoder` kẹp cứng (rè).
  - Đọc lai Nano · Turbo: đoạn của model phụ (đọc bằng giọng cặp, khoá riêng) được kéo thêm `mức giọng chính − mức giọng cặp` trước khi khớp RMS ⇒ cả hai model theo mức của giọng đang chọn; `VieNeuHybridLoudness` không kéo đỉnh quá −1 dBFS.
  - Google Cloud / tiện ích / Siri không đổi (phát nguyên).
- **`TTSPeakLimiter`** (mới): bộ ghìm đỉnh mềm −1 dBFS tách từ `VttsLoudness` (cùng thuật toán), dùng chung. **`TTSVolumeStage`** (mới): nhân dB + ghìm, bản cho WAV PCM16.
- **Giao diện**: `TTSVolumeRow` "Âm lượng:" (nút ± và thanh kéo, dòng dưới "<giọng> · mặc định <dB>") cuối "Cấu hình giọng nói", trước Cao độ, ở Cài đặt TTS và màn Giọng dự phòng khi trình đọc là vtts / NghiTTS / VieNeu. Nút "?" thêm đoạn giải thích Âm lượng (NghiTTS được thêm nút "?"); "Đặt lại" đưa giọng đang chọn về mặc định.
- **Làm mới tiếng**: mức nằm trong `TTSSettingsSnapshot` (`volumeOffset`), fingerprint giọng dự phòng và `TTSSynthesisIdentity` (chỉ ghép khi ≠ 0 ⇒ khoá cũ của giọng 0 dB không đổi) + khoá mặc định của từng service ⇒ đổi mức, đóng Cài đặt là dựng lại đoạn; ▶ thử giọng nghe đúng mức. `TTSManager.onlineFallbackVoice` + `effectiveVieNeuVoice` thành `nonisolated` (fingerprint dự phòng gọi ngoài MainActor).
- Cập nhật `.claude/rules/tts.md`, `tts-vieneu.md`. Dọn: entry cũ nhất chuyển sang `CHANGELOG.archive.md`. Chưa build được tại chỗ (Windows); `check_architecture.py` chỉ còn violation cũ `JSDom.swift`. Chưa thử máy.

## [1.3.1046] - 2026-11-23

### feat: vtts — đóng giọng Google Dịch vào app (Có sẵn trong app, cạnh Ngọc Huyền)

Anh Bửu: "thêm giọng google và ipa nữa" — sau khi Javis báo rủi ro (tiếng thầy lấy qua endpoint không chính thức của Google Dịch, repo công khai ⇒ có thể bị yêu cầu gỡ) và đề nghị chỉ đóng Ngọc Huyền.

- **Model**: `Vendor/vtts/assets/vtts/vtts-googledich-m-k4.q8.vtts` (2 580 320 byte) = `M-vocos-p-bi.q8.vtts` của chuỗi `gg` cùng lượt `vtts-k4`: ~42 giờ tiếng Google Dịch (notebook `vtts-gg-data`), lọc ASR còn 16.275 câu (vi 31,1 h, trộn 1,2 h, Anh 3,1 h) ⇒ thầy VITS 20k bước warm-start từ thầy Ngọc Huyền ⇒ chưng cất như Ngọc Huyền. SHA256 `46cbe449…3761d8` ở `assets/LOCAL_SHA256SUMS`. IPA thêm ~2,4 MB (~53 MB ⇒ Telegram nhận tin kèm link tải thay cho file, 1.3.1045).
- **`VttsVoice.googleDich`** (id `google-dich`, "Nữ · Google Dịch"), `bundled = [nu10, nam1, ngocHuyen, googleDich]`; mặc định vẫn `nu-10`. Ghi nguồn "pnnbao-ump · CC BY-NC 4.0" như Ngọc Huyền (thầy kế thừa thầy Ngọc Huyền ⇒ coi là dẫn xuất CC BY-NC). Mức tăng đoạn ngắn 8 dB (6 câu mẫu, −22,3 dBFS sau chỉnh tiếng).
- **CI**: `VOICES` thêm `google-dich`, `assets/vtts/` đúng 5 file.
- **Bản quyền**: `Vendor/vtts/THIRD_PARTY_NOTICES.md` thêm mục Google Dịch (nguồn tiếng không chính thức, không liên kết với Google, câu chữ dùng để đọc); `Vendor/vtts/README.md` ghi cách gỡ nếu bị yêu cầu (xoá file + `VttsVoice.googleDich` + dòng `VOICES` / `LOCAL_SHA256SUMS`, sửa số file mong đợi).
- Ai đã tự nhập `Google Dịch.vtts` (1.3.1043) sẽ thấy hai giọng; xoá bản ở "Giọng của tôi".
- Cập nhật `.claude/rules/tts.md`, `ci-release.md`, comment `project.yml`. Chưa build được tại chỗ (Windows); `check_architecture.py` chỉ còn violation cũ `JSDom.swift`. Chưa thử máy.

## [1.3.1045] - 2026-11-23

### ci: Telegram — IPA quá 50 MB gửi tin kèm link tải ở GitHub Release, bỏ transfer.sh

Anh Bửu: "file realease vượt 50 MB có vấn đề gì ko" → Javis kiểm build 1327 (1.3.1044): IPA 50 417 384 byte vượt ngưỡng 50 000 000 byte của bước gửi Telegram ⇒ workflow đẩy IPA lên transfer.sh, dịch vụ không kết nối được (hết 30 s) ⇒ tin tới Telegram với dòng "Tải IPA tại đây:" **trống**. Release + nguồn LiveContainer vẫn đủ. Plan → "Duyệt, sửa đi".

- **Ngưỡng** = giới hạn thật của Bot API: 50 MiB (52 428 800 byte). Dưới ngưỡng ⇒ `sendDocument` như cũ.
- **Vượt ngưỡng hoặc `sendDocument` hết 3 lượt vẫn lỗi** ⇒ `sendMessage` cùng danh sách commit, tiêu đề ghi lý do ("IPA <cỡ MiB> MB, quá 50 MB của bot" / "gửi file IPA lỗi"), dòng `⬇️ Tải IPA: <link>` = asset của release `build-<số build>` (`RELEASE_IPA_URL`, bước Publish ghi vào `GITHUB_ENV`, cùng tên tag / asset với `publish_altstore_source.py`); không có release (nhánh khác, Publish lỗi) ⇒ link trang lượt build (IPA ở Artifacts). Bỏ hẳn transfer.sh. Trước đây `sendDocument` lỗi chỉ để lại cảnh báo, không có tin nào tới.
- **Package IPA** nén `zip -9`.
- `.claude/rules/ci-release.md`: mục "IPA lớn hơn giới hạn gửi file của bot"; luật "không gửi link release" thêm ngoại lệ này.
- Không đổi code app. Chỉ sửa workflow (không tự kích hoạt build — chạy ở lượt build kế tiếp). Chưa thấy chạy thật.

## [1.3.1044] - 2026-11-23

### feat: vtts — đóng giọng Ngọc Huyền vào app (Có sẵn trong app, ghi nguồn CC BY-NC 4.0)

Anh Bửu: "Sao ko tích hợp trực tiếp vào app, giọng hợp lệ mà" → Javis đọc lại giấy phép (dataset `pnnbao-ump/ngochuyen_voice` CC BY-NC 4.0, card không thêm điều kiện; VoxCPM2 Apache-2.0; Piper vais1000 MIT, dữ liệu VAIS-1000 CC BY 4.0) ⇒ phát hành phi thương mại có ghi nguồn là được phép → plan → "Duyệt, làm đi". Giọng Google Dịch train cùng đợt vẫn chỉ nhập file (dữ liệu lấy qua endpoint không chính thức).

- **Model**: `Vendor/vtts/assets/vtts/vtts-ngochuyen-m-k4.q8.vtts` (2 580 320 byte) = `M-vocos-p-bi.q8.vtts` của lượt chưng cất `vtts-k4` trên Kaggle (thầy VITS 60k bước warm-start Piper vais1000; chưng cất front 10k / dec 30k / joint 20k bước trên 17.670 câu). SHA256 `908684ca…6dc72` ghi ở `assets/LOCAL_SHA256SUMS`. Trainer cùng commit runtime `VTTS_COMMIT.txt` (c5c8c00) ⇒ app đọc được. IPA nặng thêm ~2,6 MB.
- **`VttsVoice`**: thêm `ngocHuyen` (id `ngoc-huyen`, "Nữ · Ngọc Huyền"), `bundled = [nu10, nam1, ngocHuyen]`; mặc định vẫn `nu-10`. Trường mới `credit` (ghi nguồn mà giấy phép bắt buộc) + `bundledRowDetail`: hàng Ngọc Huyền trong sheet chọn giọng ghi "pnnbao-ump · CC BY-NC 4.0" thay "Việt + Anh · 2,6 MB" (dòng phụ chỉ một dòng, nối thêm sẽ bị cắt mất giấy phép). Mức tăng cho đoạn quá ngắn 7,5 dB — đo trên 6 câu mẫu của lượt train (−22,0 dBFS sau bước chỉnh tiếng của `VttsLoudness`), chưa đo trên đoạn truyện dài của CI như hai giọng release.
- **CI** (`Scripts/ci/check_vtts_assets.sh`): `VOICES` thêm `ngoc-huyen` ⇒ đọc thử bằng `vtts_say` + shim ASan/UBSan như hai giọng kia; `assets/vtts/` phải đúng 4 file; SHA256 kiểm qua `LOCAL_SHA256SUMS`.
- **Bản quyền**: `Vendor/vtts/THIRD_PARTY_NOTICES.md` thêm mục Ngọc Huyền (CC BY-NC 4.0, nguồn dữ liệu + link, thay đổi đã làm, VoxCPM2, Piper vais1000; điều kiện phi thương mại — app thu phí / quảng cáo ⇒ phải bỏ giọng này). `Vendor/vtts/README.md` thêm mục "Giọng tự train".
- Ai đã tự nhập `Ngọc Huyền.vtts` (1.3.1043) sẽ thấy hai giọng; xoá bản ở "Giọng của tôi".
- Dọn: entry 1.3.1014 chuyển sang `CHANGELOG.archive.md`. Cập nhật `.claude/rules/tts.md`, `ci-release.md`, comment `project.yml`. Chưa build được tại chỗ (Windows); `check_architecture.py` chỉ còn violation cũ `JSDom.swift`. Chưa thử máy.

## [1.3.1043] - 2026-11-22

### feat: vtts — nhập giọng từ file .vtts (Giọng của tôi), để dùng giọng Ngọc Huyền tự train

Anh Bửu: "Tích hợp giọng ngọc huyền vào app" → plan (giọng train riêng không đóng vào IPA: dữ liệu Ngọc Huyền CC BY-NC, repo công khai, IPA gửi Telegram ⇒ làm chức năng nhập file, giọng chỉ nằm trên máy) → "Javis tự duyệt đi".

- **`VttsVoice`** enum → struct (`id`, `displayName`, `source` = `.bundled(fileName:)` / `.imported(fileName:)`, `defaultLoudnessGainDb`). Id giọng có sẵn giữ `nu-10` / `nam-1` ⇒ lựa chọn đã lưu không mất; giọng tự nhập id `file:<tên file>`, tên hiện = tên file bỏ đuôi. `resolve`: giọng có sẵn ⇒ giọng tự nhập còn file ⇒ mặc định. Đoạn quá ngắn để đo âm lượng: giọng tự nhập tăng 9 dB (giữa hai giọng có sẵn).
- **`VttsImportedVoiceRepository`** (mới, `@MainActor @Observable`, khuôn `NghiVoiceDirectory`): chủ duy nhất của `Application Support/FreeBook/TTS/Vtts/`. Nhập = kiểm cỡ (≤ 64 MB) → chép sang file tạm → **nạp thử + đọc "Xin chào."** bằng runtime vtts của app (`VttsRuntime.validateModel`, handle riêng trên hàng đợi runtime, không vào `handles`) → đặt vào thư mục (trùng tên ⇒ thay) → nhả handle cũ của id đó. File hỏng / không phải vtts / khác phiên bản runtime không bao giờ vào danh sách. Xoá: đúng giọng trình đọc vtts đang dùng ⇒ dừng phiên trước; giọng đang chọn (trình đọc chính hay giọng dự phòng) ⇒ về `nu-10`. Tên file từ id được kiểm (không `/`, `:`, không bắt đầu `.`, đuôi `.vtts`). Không vào Sao lưu.
- **`VttsRuntime`**: handle khoá theo `VttsVoice.id`; `modelURL` theo nguồn (bundle / thư mục giọng tự nhập); `isAvailable` vẫn chỉ xét 2 giọng có sẵn + VLEX (giọng tự nhập cũng dùng VLEX của app); thêm `release(voiceId:)`, `validateModel(at:)`, lỗi `voiceFileMissing` (file tự nhập mất giữa chừng).
- **Sheet chọn giọng vtts** (`VttsVoicePickerList`, chép khuôn sheet NghiTTS): hàng đầu "Nhập giọng từ file .vtts" (`DocumentPickerPresenter` — `.fileImporter` không trả kết quả trong LiveContainer; nhận mọi file, runtime quyết định), "Có sẵn trong app", "Giọng của tôi" (dòng phụ "Tự nhập · X MB", ▶ thử, 🗑 / nhấn giữ ⇒ hỏi "Xoá giọng"), lớp "Đang nhập giọng...", toast kết quả. Màn Giọng dự phòng dùng chung sheet nên có luôn.
- Hàng "Giọng đọc" (`TTSReaderVoiceSummaryRow`): giọng tự nhập ghi "Giọng tự nhập · X MB".
- **Dung lượng**: dòng mới "vtts · N giọng tự nhập" (`StorageUsageDetail.Kind.vttsVoices`, thư mục `TTS/Vtts`); snapshot đo cũ không giải được Kind mới ⇒ màn đo lại (đã chấp nhận ở comment của `StorageUsageDetail`).
- Log: `🗣️ [Vtts] Đã nhập giọng <file>: <Hz>, bộ token …, X MB`, `❌ [Vtts] Nhập giọng …`, `🗑️ [Vtts] Đã xoá giọng tự nhập …`, `🗣️ [Vtts] Đã nhả giọng <id>`.
- Runtime vtts của app (`Vendor/vtts/VTTS_COMMIT.txt` c5c8c00) trùng commit repo dùng train giọng trên Kaggle ⇒ file `.vtts` train ra đọc được. Không đổi CI / `Vendor/vtts` / IPA.
- Dọn: entry 1.3.1013 chuyển sang `CHANGELOG.archive.md`. `.claude/rules/tts.md` + `storage.md` ghi giọng tự nhập. Chưa build được tại chỗ (Windows); `check_architecture.py` chỉ còn violation cũ `JSDom.swift`. Chưa thử máy.

## [1.3.1042] - 2026-11-21

### feat: Màn xem phim — chạm dải Playlist xổ danh sách mục (bìa ngang), chạm hàng phát mục đó

Anh Bửu: "bấm vào phần playlist trong phát video dọc cho xổ ra danh sách video cho tôi, hiển thị kiểu danh sách nhưng cover ngang" → plan + mockup (https://claude.ai/artifact/3vLeRzLdCr1fimJhxu9pFj) → "Duyệt".

- **Dải** `VideoWatchPlaylistBar`: cả dải (trừ nút ⏭) thành nút xổ / thu, thêm mũi `chevron.down` lật lên khi đang xổ; trạng thái xổ là `@State` của dải nên giữ qua lượt đổi phim tại chỗ. ⏭ giữ nguyên việc cũ.
- **Danh sách** `VideoWatchPlaylistQueueList` (mới): mục theo **thứ tự người dùng xếp** (không theo thứ tự xáo — như `AudioPlaylistQueueList`), lấy bản mới nhất của playlist, NSFW ẩn theo công tắc chung, playlist đã xoá ⇒ bản chụp của hàng đợi. Hàng dùng lại `PlaylistItemRow(kind: .video)` (bìa 92×52 bo 8, tên `.headline` 2 dòng, tên phim `.subheadline`; màn xem ép nền tối nên chữ trắng), mục đang phát tô màu nhấn + icon loa theo **id mục**. Thẻ nền trắng 7% bo 12, vạch ngăn mảnh giữa hàng. ≤ 4 mục hiện hết; dài hơn ⇒ khung cao 310 pt (≈ 4,5 hàng) cuộn bên trong, xổ ra / đổi mục thì cuộn tới mục đang phát.
- **Chạm hàng** ⇒ `PlaylistPlaybackCoordinator.jumpVideo(to:)` (mới, `+Video`): `queue.jump(to:)` rồi `playVideoItem` (cùng phim ⇒ chuyển tập trong phiên, phim khác ⇒ màn đổi tại chỗ) — vẫn ở chế độ playlist; không đi `model.play` / `selectEpisode` (lối đó thôi playlist). Chạm đúng mục đang phát ⇒ phim lỗi thì thử lại, đang mở / đang phát thì để yên. Danh sách giữ mở sau khi chạm. Log `🎶 [VideoWatch]` (xổ / thu, chọn mục), `⏭️ [PlaylistPlayback] Chọn mục i/n`.
- Đang xáo: số trên dải ("3/8") theo thứ tự phát, số của hàng theo thứ tự xếp — giống màn nghe nhạc.
- Dọn: entry 1.3.1012 chuyển sang `CHANGELOG.archive.md`. `.claude/rules/comic-video.md` ghi danh sách xổ. Chưa build được tại chỗ (Windows); `check_architecture.py` chỉ còn violation cũ `JSDom.swift`. Chưa thử máy.

## [1.3.1041] - 2026-11-20

### feat: vtts — từ điển phiên âm riêng như VieNeu / NghiTTS, sheet phiên âm khi bôi đen lưu được vào vtts

Anh Bửu: "thêm từ điển phiên âm giống vieneu và pipetts giúp tôi, sheet phiên âm bôi đen có thêm option lưu từ điển vtts" → plan + mockup (https://claude.ai/artifact/8eQ4RX84WY35hc1GABjCxv) → "Duyệt".

- **Kho** `VttsPhoneticDictionary` (actor, mới): `FreeBook/TTS/phien-am-vtts.plist`, khoá hạ chữ thường + NFC, **giữ dấu** (vtts tra mọi token kể cả chữ Việt — gấp dấu như hai từ điển kia thì mục "ban" thay luôn "bàn"). Công tắc `vttsDictionaryEnabled`, mặc định **bật** (từ điển chỉ có mục người dùng tự thêm).
- **Áp khi đọc** — `VttsTextFrontend` (mới): token **từ** của `TTSReplacementTokenizer` (từ nối `Kamar-Taj` là một token) khớp từ điển ⇒ cách đọc đi nguyên văn; phần chữ còn lại mới qua phiên âm tiếng Nhật ⇒ mục người dùng thắng, không phiên âm hai lần. `VttsTTSService` dùng nó cho trình đọc chính, giọng dự phòng, ▶ thử giọng; log `🗣️ [Vtts] Đoạn` thêm `dict=N` / `dict=off`. Công tắc nằm trong `TTSSettingsSnapshot` (`vttsDictionaryEnabled`) + fingerprint giọng dự phòng.
- **Cài đặt**: `VttsReaderManagementRows` (mới) — "Từ điển phiên âm vtts ›" + công tắc "Áp dụng từ điển phiên âm vtts" trên hàng "Phiên âm tiếng Nhật" ở Cài đặt TTS (nhánh vtts đặt **trước** nhánh tiện ích của `TTSSettingsView` — `isExtensionTool` cũng đúng với vtts nên trước đây vtts rơi vào nhánh tiện ích trống) và màn Giọng dự phòng; nút "?" giải thích. Màn `VttsPhoneticDictionaryView` (mới, khuôn màn VieNeu): tìm, nạp 100 từ / lượt, chạm hàng ⇒ `EditWordSheet`, xoá bằng icon / vuốt, "+" nổi ⇒ `AddWordSheet(target: .vtts)`, ngăn kéo "…": Nhập từ file… (`PhoneticDictionaryImporter.importVtts`, 3 chế độ), Xuất .plist / .json, Xoá tất cả. Không có Tải từ điển / Phiên âm lại.
- **Sheet bôi đen › Phiên âm** (`AddWordSheet`): Menu Lưu 4 mục — NghiTTS / VieNeu-TTS / **vtts** / Lưu tất cả (cả ba). `PhoneticDictionaryWriter.Destination` thành `nghiTTS / vieNeu / vtts / all` với cờ viết dương (bản cũ `self != .vieNeu` — thêm đích là cờ cũ đúng cho cả đích mới), `Result` thêm `wroteVtts`, toast liệt kê đúng từ điển đã ghi. Chip gợi ý `VTT` (`TTSPhoneticSuggestion.Origin.vttsLibrary`) ở sheet thêm từ và sheet sửa từ của mọi từ điển, nhấn giữ để xoá khỏi từ điển vtts (tra / xoá bằng khoá của chính vtts).
- **Sao lưu / Dung lượng**: file vào `BackupPaths.ttsDictionaryFiles` (nhóm `.dictCustom`), khôi phục xong nạp lại `VttsPhoneticDictionary`; nhãn Dung lượng "Từ điển phiên âm (NghiTTS, VieNeu, vtts)".
- Dọn: entry 1.3.1011 chuyển sang `CHANGELOG.archive.md`. `.claude/rules/tts.md` ghi từ điển vtts. Chưa build được tại chỗ (Windows); `check_architecture.py` chỉ còn violation cũ `JSDom.swift`. Chưa thử máy.

## [1.3.1040] - 2026-11-20

### feat: Reader — dấu trang chương và ghi chú đoạn (nút trên header, ô ở menu bôi đen, tab Dấu trang / Ghi chú trong mục lục, dấu đoạn có ghi chú)

Anh Bửu: "làm chức năng ghi chú, đánh dấu chương" → mockup → "thêm tab ở ghi chú dấu trang ở mục lục nữa, ngoài ra thêm đánh dấu để biết đoạn nào trong reader được ghi chú; bấm vào ghi chú để đến đoạn ghi chú, bấm vào đánh dấu để đến chương đánh dấu" → bỏ hai hàng ở ngăn kéo ⋯ → "thêm 1 nút dấu trang trên header" → "Duyệt".

- **Dữ liệu** (`Models/Reader/BookAnnotations`, `Services/Books/Annotations/`): mỗi truyện một file `annotations/<sha256(bookId)>.json` (`BookAnnotationStore`, ghi `.atomic`, rỗng ⇒ xoá file, file hỏng ⇒ cất `.broken-…`). Dấu trang theo **chương** (chỉ số + tên lúc tạo + link chương), ghi chú theo **đoạn** (`paragraphIndex` = id dòng thưa như `ParagraphItem.id`, "Đoạn N" để hiện, đoạn chữ đang bôi đen ≤ 300 ký tự). `BookAnnotationRepository` (`@MainActor @Observable`, cache RAM bỏ quan sát + `revision`) là lối của View. Chỉ truyện có bản ghi `Book` mới dùng được (không có ⇒ toast "Thêm truyện vào kệ…").
- **Reader**: nút dấu trang đầu cụm nút phải header (36×38, đặc + màu nhấn khi chương đang hiện có dấu, toast khi bật / tắt); menu bôi đen thêm cột 5 — "Ghi chú" (mở sheet viết với đoạn trích) và "Dấu trang" / "Bỏ dấu" (chương của vùng bôi đen) — bề rộng 275 → 327pt; đoạn có ghi chú có vạch màu nhấn ở lề trái + icon ghi chú ở lề phải (`ReaderNoteMarkerModifier`, gắn ngoài `ParagraphCardView.equatable()`), chạm ⇒ mở ghi chú (nhiều ghi chú ⇒ mở tab Ghi chú). Sheet `ReaderNoteEditorSheet` (kính, "Lưu" chữ ở header, "Xoá ghi chú" khi sửa, vuốt xuống lúc gõ dở ⇒ hỏi bỏ).
- **Mục lục**: chip Mục lục / Dấu trang N / Ghi chú N ở đầu panel (`ReaderChapterListView+Annotations`, kiểu chip `ExtensionKindFilterBar`, màu theo nền đọc). Tab Dấu trang: hàng chương + ngày, chạm ⇒ **đầu chương**. Tab Ghi chú: nhóm theo chương, đoạn trích + nội dung + "Đoạn N · ngày", chạm ⇒ **đúng đoạn**, nhấn giữ ⇒ Sửa / Xoá. 🗑 xoá ở mọi hàng. Hàng chương ở tab Mục lục có icon dấu trang + số ghi chú. Mở chỗ đã lưu: chỉ số không còn trỏ đúng link đã lưu ⇒ tra theo link (mục lục online, rồi `ChapterStore.fetchOrderedTOC`).
- **Đi theo truyện**: xoá truyện (`BookStorageManager.deleteBookSideData` thay cho `deleteLegadoState` ở ba lối xoá — gọi cả hai), đổi nguồn (`BookSourceMigrator` chép gộp theo id / xoá), sao lưu (`BackupAnnotationArchiver`, entry `library/annotations.json` = `[hash(bookId): …]`, đi kèm nhóm `.books`, khôi phục gộp), Dung lượng (loại mới "Ghi chú & dấu trang"), Dọn rác (file của truyện không còn trong thư viện, cùng luật `.bin` / phim / comic).
- Log `🔖 [Annotations]`. `storage.md`: thêm thư mục `annotations/`.
- Kiểm: đọc code + `check_architecture.py` (chỉ còn violation cũ `JSDom.swift`); **không build tại chỗ (Windows), chưa chạy trên máy**. Chưa làm (đã nói trong plan): tô màu chữ đoạn có ghi chú, xuất ghi chú, truyện tranh / phim, xem từ Chi tiết truyện; vân tay sao lưu tự động (`BackupLibraryFingerprint`) chưa tính ghi chú ⇒ chỉ sửa ghi chú thì lượt sao lưu Drive tự động có thể bỏ qua.

## [1.3.1039] - 2026-11-20

### feat: Kệ — nút ⋮ mở tuỳ chọn truyện, nhấn giữ để chọn nhiều (Chọn tất cả, Thêm vào playlist, Thêm vào bộ sưu tập, Xoá)

Anh Bửu: thêm nút ba chấm dọc trên mỗi sách ở Kệ mở menu của sách; nhấn giữ lâu = chọn nhiều sách, có Chọn tất cả / Bỏ chọn tất cả, Xoá, Thêm vào playlist, Thêm vào bộ sưu tập → plan + mockup https://claude.ai/artifact/Es6YfEe94Zyi2uigCzMTPX → "Duyệt" (theo đề xuất: chỉ Kệ Sách + Lịch Sử, thanh thao tác đè thanh tab, Xoá ở Kệ hỏi hai hướng).

- **⋮** (`ShelfBookMoreButton`, mới): kiểu Danh sách cuối hàng sau badge chương mới (17pt, khung 32×44), kiểu Lưới cuối dòng "icon · Ch. N" (15pt), kiểu Chỉ bìa vòng tròn 26 nền đen 50% góc trên phải bìa (badge chương mới lùi sang trái). Bấm ⇒ `BookActionSheet` như nhấn giữ trước đây. Là tham số **opt-in** `onMore` của `ShelfBooksLayoutView`; thẻ lưới nhận `ShelfBookGridCardView.Accessory`.
- **Chọn nhiều** (`ShelfBookSelection` + `ShelfView+Selection`, mới): nhấn giữ (0,25 s, rung) ⇒ vào chế độ, truyện đó chọn sẵn. Header ✕ + "Đã chọn N" (`pageTitle(_:leadingIcon:)`) + "Chọn tất cả" / "Bỏ chọn tất cả" thay cụm 🔍 | …; nút "+" nổi ẩn. Chạm / nhấn giữ = chọn / bỏ, không mở truyện. Vòng chọn `ShelfBookSelectionMark` (mới); hàng đã chọn nền nhấn 18% + viền 60% (`bookListPanel(_:isHighlighted:)`), bìa đã chọn viền nhấn 3pt. Chỉ giữ `bookId`, mọi phép đếm / thao tác giao với danh sách đang hiện của trang (chip loại + NSFW, kể cả phần chưa phân trang tới — "Chọn tất cả" chọn hết). Thoát: ✕, đổi trang, mở Reader (thông báo / đĩa nghe), thao tác xong.
- **Thanh thao tác** `ShelfSelectionActionBar` (mới): cùng khuôn `MainTabBar`, `overlay` đè đúng chỗ thanh tab (không sửa thanh tab dùng chung). Thêm vào playlist · Thêm vào bộ sưu tập · Xoá.
- **Xoá**: Kệ Sách hỏi "Bỏ khỏi kệ (về Lịch sử)" (một lần lưu, `BookTransactionCoordinator+Batch.removeFromShelf(bookIds:)` chép luật bản một truyện) hoặc "Xoá hẳn khỏi máy" (`BookStorageManager.deleteBooksAsync`, lớp chờ "Đang dọn dẹp sách...", toast theo số thật đã xoá — truyện đang nghe TTS được giữ). Lịch Sử hỏi "Xoá N truyện khỏi lịch sử": trên kệ ⇒ `setHistory(bookIds:isHistory: false)`, không ở kệ ⇒ xoá khỏi máy.
- **Thêm vào bộ sưu tập**: sheet kính `CollectionBatchAddSheet` (mới) — chạm một bộ ⇒ `BookCollectionCoordinator.addBooks` (mới, **chỉ thêm**, một lần lưu; truyện ở Lịch sử lên kệ theo bất biến), "Tạo bộ sưu tập mới" tạo xong thêm luôn, toast "Đã thêm N truyện vào …".
- **Thêm vào playlist**: chỉ album âm thanh / phim (`PlaylistKind` qua `BookContentKindResolver`). Không có cuốn nào hợp ⇒ ô mờ + toast; có cả hai loại ⇒ hỏi Nhạc / Video; lấy mục lục **lần lượt** (`PlaylistAlbumItemsLoader.items`, ô hiện "Đang lấy i/N · Huỷ", bấm lại ⇒ huỷ) rồi mở `PlaylistAddSheet` (thêm tham số tuỳ chọn `onAdded`); truyện khác loại / album lỗi mục lục báo gộp một toast.
- Thêm xong (playlist / bộ sưu tập) ⇒ thoát chế độ chọn khi sheet đóng hẳn; vuốt đóng mà chưa thêm ⇒ giữ lựa chọn.
- Bộ sưu tập và Tìm trên kệ giữ nguyên (nhấn giữ vẫn mở sheet, không ⋮). Cụm nút phải header Kệ tách ra `headerTrailingButtons` (ngân sách type-check của `body`).
- `.claude/rules/ui-conventions.md` thêm luật. CHANGELOG: chuyển bản 1.3.1009 sang archive. Kiểm: đọc code + `check_architecture.py` (chỉ còn violation cũ `JSDom.swift`); **chưa build tại chỗ (Windows), chưa thử máy**.

## [1.3.1038] - 2026-11-20

### fix: vtts — phiên âm tiếng Nhật đọc được tên viết hoa, thêm "vtts tự đọc nhanh tối đa" để chỉnh độ rõ lời

Anh Bửu thử 1.3.1036: hết tiếng "vụt" nhưng "âm điệu nghe khác ver trước", "nghe không được rõ lời lắm" (hai file tự đọc nhanh thường / bản 4 "nghe như nhau" ⇒ do tự đọc nhanh, không do bản 4); "tôi bật phiên âm tiếng nhật nhưng không thấy hoạt động". Log máy: `speed=1.80`, `NghiHandoff delayMs` 12–39 ms (đổi file không gây hở tiếng). Anh duyệt plan + mockup.

- **Phiên âm tiếng Nhật**: `TTSJapaneseTextTransliterator` (dùng chung Siri / Google / tiện ích / vtts) chỉ đổi từ `ForeignScriptClassifier` chấm ≥ 4 điểm hoặc có trong `JapaneseLoanwordList` ⇒ "Konoha", "Naruto", "Sasuke" (1 điểm) không bao giờ đổi, vtts đọc tiếng Anh. `spokenForm` nhận thêm luật tên viết hoa của VieNeu (`VieNeuJapaneseNameReader.reads`). Không hạ ngưỡng bộ chấm điểm. vtts đọc kết quả ("Kô nô ha", "Na ru tô") bằng tiếng Việt — đã đối chiếu `word_tag` / `parse_syl` của runtime. Log `🗣️ [Vtts] Đoạn` thêm `jp=off` / `jp=on(N: Konoha→Kô nô ha, …)` (tối đa 2 cặp, `applyReportingChanges`).
- **"vtts tự đọc nhanh tối đa"** (mockup https://claude.ai/artifact/XPxHGwcaoi3ZF9GsC2apAM): `VttsNativeSpeedRow` (mới, `Views/Settings/TTS/`) ngay dưới thanh Tốc độ ở Cài đặt TTS và màn Giọng dự phòng khi chọn vtts, 1,0–2,0 bước 0,1, khoá `vttsNativeSpeedMax` (`@AppStorage`), mặc định 1,4 (ước lượng), dòng số "vtts đọc X · trình phát kéo thêm Y", giải thích sau nút "?" của "Cấu hình giọng nói", "Đặt lại" về mặc định. Thanh Tốc độ giữ nghĩa tốc độ nghe: `TTSManager.vttsNativeSpeed(forListeningSpeed:)` = min(tốc độ, tối đa) kẹp 1,0–2,0; `localPlaybackRate` / `remotePlaybackRate` kéo phần còn lại. Giá trị nằm trong `TTSSettingsSnapshot` (`vttsNativeSpeedMax`) và fingerprint giọng dự phòng ⇒ đóng Cài đặt là dựng lại đoạn như đổi tốc độ.
- Dọn: entry 1.3.1008 chuyển sang `CHANGELOG.archive.md`. `.claude/rules/tts.md` ghi luật tên viết hoa + hàng mới. Chưa build được tại chỗ (Windows); `check_architecture.py` chỉ còn violation cũ `JSDom.swift`. Chưa thử máy.

## [1.3.1037] - 2026-11-20

### fix: Danh sách VietPhrase.dat / Names.dat (thẻ › Sửa) mở và tìm chậm — chỉ mục dựng một lần, trang đầu hiện ngay, tìm trên byte, kết quả hiện dần

Anh Bửu: "vietpharse tìm quá lâu, hiển thị ra cũng lâu, vì sao vậy?" → "tôi đang nói trong danh sách khi nhấn sửa ấy nhé" → plan → "Duyệt".

- **Nguyên nhân**: mở màn duyệt **hết** cây và dựng `String` cho từng khoá (cỡ triệu) rồi mới hiện; mỗi lượt tìm dựng lại bảng con của cây (vài mảng cỡ triệu phần tử) và dựng `String` + `range(of:options: .caseInsensitive)` cho **từng nghĩa** — từ hiếm phải quét hết cây, kết quả chỉ hiện khi quét xong.
- **Chỉ mục** `BaseDictionaryIndex` (`Models/Dictionaries/`, mới): dựng một lần mỗi lần mở màn ở nền — khoá dạng đơn vị UTF-16 nối liền một mảng + vị trí nghĩa trong pool `.dat`, thứ tự tiền thứ tự của cây như cũ. Phép duyệt **chép riêng** cùng phép tính của `walkEntries` (hàm đó giữ nguyên vì nuôi `allEntries` của nhập / gộp); không kiểm UTF-8 nghĩa lúc dựng (nghĩa hỏng hiện rỗng). 200 khoá đầu gửi về màn ngay khi có (`onFirstPage`), phần sau dựng chuỗi theo lượt 200 khi cuộn; tổng số từ lấy số mục chỉ mục (lúc đang dựng: `wordCount` ở đầu file). Lượt dựng không theo huỷ của `.task` (quay về từ "Từ đã sửa / đã xoá" không dựng lại).
- **Tìm** `BaseDictionaryIndexSearch` (mới): lớp sửa đổi (như cũ) ⇒ khoá **bắt đầu bằng** ⇒ khoá **chứa** (quét tuyến tính mảng UTF-16, không dựng chuỗi) ⇒ **nghĩa** chứa, so trên byte bằng `BaseDictionaryMeaningMatcher` (parser UTF-8 của stdlib, hạ thường theo `lowercaseMapping` dưới U+2000, không bỏ dấu, chuỗi tìm NFC; nghĩa có dấu rời / NFD đi đường Foundation cũ), quét theo lượt chia 2–3 luồng (1 luồng khi NghiTTS / VieNeu đang đọc). Kết quả gửi dần qua `AsyncStream` (`BaseDictionaryBrowser.searchUpdates`), dòng tổng ghi "Đang tìm… N kết quả" khi chưa xong; gõ tiếp ⇒ huỷ lượt quét; chỉ mục chưa xong thì lượt tìm chờ rồi tự chạy. Mỗi khoá một lần trong kết quả.
- Bỏ `FrozenTrieDictionary.allKeys()` và `BaseDictionaryBrowser.keys` / `search` cũ (không còn ai gọi). `walkEntries` / `allEntries` không đổi.
- Log `📚 [VPList]` (số mục, ms dựng, ms tới trang đầu) và `🔎 [VPList]` (ms phần khoá / nghĩa, số luồng, số nghĩa phải so bằng Foundation, đối chiếu 1000 nghĩa đầu giữa đường byte và Foundation — số lệch phải là 0) để đo trên máy.
- `translation.md`: sửa câu mô tả danh sách từ điển gốc. CHANGELOG: chuyển bản 1.3.1007 sang archive.
- Kiểm: đọc code + `check_architecture.py` (chỉ còn violation cũ `JSDom.swift`); **không build tại chỗ (Windows), chưa chạy trên máy, chưa đo được nhanh lên bao nhiêu**. Cần thử: bật Ghi log, Cài đặt dịch thuật › thẻ VietPhrase.txt › Sửa — trang đầu phải hiện gần như ngay; tìm một chữ Hán, một chữ Việt hiếm, một chữ Việt thông dụng (vd "của"); gửi log.

## [1.3.1036] - 2026-11-20

### fix: vtts — tự đọc nhanh theo thanh Tốc độ, làm nhỏ dần đuôi cụt, tiếng sáng và to hơn

Anh Bửu nghe 4 bản vtts tạo tiếng nhanh 1,8× ngay từ gốc (CI 1.3.1035, câu "…phiên bản, đem mệnh danh…"): "4 cái đều không có tiếng vụt" ⇒ tiếng "vụt" ở 1,8× là do `AVAudioPlayer` kéo nhanh tiếng vtts. Duyệt plan bước 2 kèm "bản 4" (anh đã chọn trong lượt nghe so âm lượng).

- **Tự đọc nhanh**: `TTSManager.localSynthesisSpeed(forTool: "vtts")` = `vttsSynthesisSpeed` (khoá `vttsRate` kẹp `VttsTTSService.nativeSpeedRange` 1,0–2,0, chung trình đọc chính và giọng dự phòng) ⇒ `VttsTTSService` đưa `length_scale = 1 / tốc độ` vào vtts, khoảng lặng đuôi chia cho tốc độ, khoá tổng hợp mặc định có tốc độ. Trình phát chỉ kéo phần còn lại: `TTSManager.localPlaybackRate` (sửa tại chỗ 2 dòng `NghiAudioPlayerQueue.start` / `updateRate` của `TTSManager.swift`, không thêm dòng) và `remotePlaybackRate` khi vtts là giọng dự phòng. NghiTTS / VieNeu không đổi. Tốc độ chỉ đổi ở sheet Cài đặt TTS, nằm trong `TTSSettingsSnapshot` ⇒ đóng sheet là xoá hết đệm (cả đầu chương kế).
- **Đuôi cụt** — `VttsEdgeFade` (mới): WAV CI cho thấy mảnh vtts kết thúc ở dấu phẩy (vtts tự cắt câu > 40 âm tiết) bị cắt lúc âm còn −36 dBFS rồi rơi thẳng về 0 (cả hai giọng ở 1×). Làm nhỏ dần 20 ms trước mỗi khe số 0 tuyệt đối ≥ 100 ms (khe 150 ms bridge chèn) và ở cuối tiếng, to dần 5 ms sau khe; log `cut=`.
- **Bản 4** — `VttsLoudness.process` (viết lại): lọc thông cao 150 Hz + nâng +6 dB quanh 2,8 kHz (biquad RBJ) → RMS khung 20 ms có tiếng về −14 dBFS (≈ −16 LUFS; trước −16 dBFS), tăng tối đa +18 dB → ghìm đỉnh ≤ −1 dBFS (cực tiểu ±5 ms, trung bình trượt ±5 ms, nhả 80 ms) thay cho cách hạ cả đoạn của 1.3.1033 (cách cũ chặn mức to ~−17,5 LUFS). `VttsVoice.defaultLoudnessGainDb` theo mốc mới (nu-10 +10,5, nam-1 +7 dB). Log `🗣️ [Vtts] Đoạn` thêm `speed=`, `limit=`. Thuật toán trùng bản Python đã dựng 4 file anh nghe (nu-10 tốc độ gốc: +11,6 dB, ghìm −3,8 dB).
- CI: gỡ `render_listening_samples` (tạm của 1.3.1035) — `check_vtts_assets.sh` / `build-ipa.yml` về như trước 1.3.1034.
- Dọn: entry 1.3.1006 chuyển sang `CHANGELOG.archive.md`. `.claude/rules/tts.md` ghi tự đọc nhanh, `VttsEdgeFade`, bản 4. Chưa build được tại chỗ (Windows); `check_architecture.py` chỉ còn violation cũ `JSDom.swift`. Chưa thử máy.

## [1.3.1035] - 2026-11-20

### fix: vtts — độ dài phân đoạn mặc định 500, log độ trễ chuyển đoạn, CI dựng câu nghe thử ở tốc độ gốc

Anh Bửu: "chỗ ngắt đoạn cũ đoạn mới hay có tiếng xoẹt xoẹt hoặc vấp". Anh thử câu "…Thổ Nạp Thuật phiên bản, đem mệnh danh là “Cá Trê Thổ Nạp Thuật”." (lỗi ở dấu phẩy): 1× + phân đoạn 500 sạch, 1× + 150 bị, 1,8× + 150 bị, 1,8× + 500 còn "vụt" nhẹ. vtts không có nhiễu ngẫu nhiên (cùng chữ ⇒ cùng mẫu) và tự cắt câu > 40 âm tiết **đúng dấu phẩy đó** (`MAX_SYL` của `vtts_text.c`; log máy `chars=187 chunks=2`) ⇒ ở 150 tiếng hai nửa câu y hệt, khác duy nhất là app xẻ thành 2 file ⇒ một lần đổi `AVAudioPlayer` giữa câu. Phần "vụt" ở 1,8× + 500 nằm trong một file ⇒ do trình phát kéo nhanh (chưa rõ cơ chế).

- `TTSManager.VttsSettings.defaultChunkLength` 150 → **500**: `NghiUtteranceSegmenter` luôn cắt ở dấu hết câu đầu tiên nên chunk vẫn là từng câu, chỉ câu > 150 ký tự thôi bị xẻ. Máy đã lưu `vttsChunk` giữ giá trị cũ (máy anh đã để 500).
- `NghiAudioPlayerQueue.lastHandoffDelayMs` (mới): ms từ delegate phát xong tới khi `play()` của player kế đã gọi; log `🔊 [TTSPerf] NghiHandoff` thêm `delayMs=` (sửa tại chỗ dòng log trong `TTSManager.swift`, không thêm dòng). Dùng chung NghiTTS / VieNeu / vtts — đo xem chỗ vấp có phải main kẹt lúc bàn giao (log anh có main kẹt 554 / 1045 ms).
- CI (tạm): bỏ phần đo Google (`Scripts/ci/tts_loudness_probe.py` xoá, `build-ipa.yml` thôi đưa `GOOGLE_CLOUD_TTS_API_KEY` vào bước vtts); `check_vtts_assets.sh` › `render_listening_samples` dựng câu của anh bằng 2 giọng: cả câu 1×, cả câu tốc độ gốc 1,8× (`vtts_say --speed 0.5556` — tham số này là `length_scale`), và 2 mảnh như khi cắt ở 150 ⇒ artifact `vtts-samples` để anh nghe so với app. Kết quả đo 1.3.1034: Google readaloud 6 giọng −19,8 LUFS, vtts 1.3.1033 đã ngang / to hơn (nu-10 −19,4, nam-1 −17,8) ⇒ vtts nghe nhỏ là do chất tiếng; bản "sáng và to hơn" anh chọn còn giữ tới khi nghe xong bản tốc độ gốc.
- Dọn: entry 1.3.1005 chuyển sang `CHANGELOG.archive.md`. `.claude/rules/tts.md` ghi lý do mặc định 500 + `delayMs`. Chưa build được tại chỗ (Windows); `check_architecture.py` chỉ còn violation cũ `JSDom.swift`.

## [1.3.1034] - 2026-11-20

### chore: vtts — CI đo tạm mức to Google TTS so với vtts để chọn mốc âm lượng

Anh Bửu: sau 1.3.1033 vtts vẫn "không to bằng google tts". Đo lại 2 WAV mẫu của CI: bản 1.3.1033 chỉ đưa vtts lên ~−17,7 LUFS (nu-10 −26,4 → −17,8; nam-1 −22,4 → −17,6 và đỉnh đã chạm trần −1 dBFS) — giữ đỉnh ≤ −1 dBFS bằng cách hạ **cả đoạn** nên mức to bị chặn, đoạn truyện dài đỉnh cao hơn còn được tăng ít hơn. Mốc −16 dBFS là ước lượng, chưa từng đo Google. Lượt này chỉ đo, chưa đổi app:

- `Scripts/ci/tts_loudness_probe.py` (mới, **tạm thời**, chỉ thư viện chuẩn): gọi Google readaloud đúng body của `GoogleTTSService.makeRequest` với cả 6 giọng (câu thử + một đoạn truyện ~30 s có thoại, câu cảm thán), giải mã bằng `afconvert` (lùi `ffmpeg`), đo LUFS tích hợp BS.1770, RMS lúc có tiếng (đúng cách `VttsLoudness` đo), đỉnh; vtts đọc cùng đoạn dài bằng 2 giọng, đo mức gốc + mô phỏng `VttsLoudness` 1.3.1033. In ra log CI + `loudness.txt` trong artifact `vtts-samples` (kèm WAV đoạn dài của vtts; audio Google không lưu). Không in key, lỗi gì cũng không làm đỏ build.
- `check_vtts_assets.sh`: hàm `probe_loudness` (tạm) chạy sau kiểm shim. `build-ipa.yml`: bước vtts nhận `GOOGLE_CLOUD_TTS_API_KEY` từ secret (tạm).
- Gỡ cả hai ở lượt sửa `VttsLoudness` tiếp theo. Dọn: 3 entry cũ nhất (1.3.1002–1.3.1004) chuyển sang `CHANGELOG.archive.md`.

## [1.3.1033] - 2026-11-20

### fix: vtts — giọng nhỏ, tự kéo âm lượng mỗi đoạn về mức TTS thường

Anh Bửu: "giọng nhỏ quá". Đo WAV đọc thử của CI (run 44685147889): model xuất nhỏ — `nu-10` đỉnh −11,3 dBFS, RMS lúc có tiếng −24,1 dBFS; `nam-1` −5,9 / −19,8 dBFS (TTS thường ~−16…−18 dBFS).

- `VttsLoudness` (mới, `Services/TTS/Vtts/`): đo RMS trên khung 20 ms có tiếng (> −45 dBFS) của **mỗi đoạn**, tăng về −16 dBFS; chỉ tăng 0…+12 dB, giới hạn để đỉnh ≤ −1 dBFS (không để `WAVEncoder` kẹp cứng gây rè); đoạn có tiếng < 0,4 s dùng mức cố định theo giọng (`VttsVoice.defaultLoudnessGainDb`: nu-10 +8, nam-1 +3,5 dB). Dùng Accelerate (`vDSP`).
- `VttsTTSService` gọi trước khi nối khoảng lặng đuôi ⇒ áp cho trình đọc chính, giọng dự phòng và ▶ thử giọng (cùng đi qua service). Log `🗣️ [Vtts] Đoạn` thêm `gain=+X.XdB`.
- Mô phỏng thuật toán trên 2 WAV mẫu: nu-10 +8,6 dB (đỉnh −2,7 dBFS), nam-1 +4,8 dB (đỉnh −1,1 dBFS), cả hai RMS −16 dBFS. Mốc −16 dBFS là ước lượng, chưa so với VieNeu / Google. Không thêm giao diện.
- Chưa thử máy; `.claude/rules/tts.md` ghi thêm.

## [1.3.1032] - 2026-11-20

### fix: vtts — CI dựng vtts_say kèm stub ZH/JA/RU, kiểm tài sản trong IPA, toast lỗi ghi đúng trình đọc

Sửa sau review phản biện (2 agent, chỉ đọc) trước lượt push đầu của vtts:

- **CI sẽ đỏ chắc chắn**: `check_vtts_assets.sh` dựng `vtts_say` với đúng cờ tắt ngôn ngữ của gói SPM, nhưng `vtts_say.c` (upstream) luôn gọi `vtts_zlex_init` / `vtts_jlex_init` / `vtts_rlex_init` — chỉ được định nghĩa trong `#if VTTS_ENABLE_ZH / _JA / _RU` ⇒ `Undefined symbols` lúc link. Thêm `Scripts/ci/vtts_say_lex_stubs.c` (3 hàm trả `-1`, chỉ link vào `vtts_say`), giữ nguyên cờ của app; `build-ipa.yml` thêm file này vào `paths`.
- **Bước Package IPA kiểm `FreeBook.app/vtts/`** có đủ `lex_en.bin` + 2 giọng M (folder reference nằm trong thư mục gói SPM cục bộ — chưa từng build; thiếu thì vtts lỗi ngay đoạn đầu).
- Toast / log lỗi tổng hợp của đường phát local chung ghi tên trình đọc đang dùng (`TTSManager.localReaderLabel`: NghiTTS / VieNeu / vtts) thay cho luôn "NghiTTS" — sửa tại chỗ 2 dòng `TTSManager.swift`, không thêm dòng.
- Dọn: 7 entry cũ nhất (1.3.995–1.3.1001) chuyển sang `CHANGELOG.archive.md` (file chính giữ 30 entry); `AGENTS.md` + `ci-release.md` ghi điều kiện chạy CI mới.
- Review không thấy lỗi biên dịch Swift / C nào khác (đối chiếu code, máy Windows không biên dịch được). Để sau (ghi nhận, chưa sửa): lỗi front-end hiếm của một đoạn vtts làm dừng cả phiên đọc; runtime có thể nạp lại ngay sau khi vừa nhả (chỉ tốn ~4,7 MB, không lỗi).

## [1.3.1031] - 2026-11-20

### feat: vtts — lưu sẵn model, từ điển và công cụ dựng lại trong repo, CI không tải gì từ upstream

Anh Bửu (qua session chính): lưu sẵn toàn bộ dữ liệu vtts trong repo, phòng repo upstream / CMUdict bị xoá — CI và app không phụ thuộc mạng tới `tuanpmt/vtts` hay `cmusphinx`. Thay phần tài sản của 1.3.1028–1029.

- **`Vendor/vtts/assets/`** (commit, `-text` trong `.gitattributes` ⇒ giữ nguyên byte): `vtts/` = **đúng** 3 file đóng vào app (2 giọng M release `v0.4.0` + `lex_en.bin`), `extra/` = 2 bản S dự trữ (không vào app), `cmudict/cmudict.dict` (commit `74790861…`, SHA256 trùng mức `cmudict.py` ghim), `SHA256SUMS` nguyên văn của release (4 model đã kiểm khớp trước khi commit) + `LOCAL_SHA256SUMS` (`lex_en.bin`, `cmudict.dict`). `lex_en.bin` dựng trên máy này bằng `build_lexicon.py` ở commit ghim `c5c8c00` (1 860 736 byte).
- **`Vendor/vtts/tools/`**: công cụ upstream cùng commit, chép nguyên văn (đã so hash git từng file): `scripts/frontend/build_lexicon.py` + 8 module `src/vtts/...` nó import (chỉ thư viện chuẩn), `runtime/tools/vtts_say.c`, `runtime/Makefile`. Nằm ngoài target SPM ⇒ không vào app. **`Vendor/vtts/rebuild_lex_en.sh`** (mới): dựng lại `lex_en.bin` từ `tools/` + `cmudict.dict` trong thư mục tạm, chặn mạng bằng proxy chết, so SHA256 (hoặc `--write` để ghi đè) — đã thử import + đọc CMUdict offline (126 052 từ); lượt dựng đầy đủ trên máy này hết RAM (`MemoryError` ở bước huấn luyện letter-to-sound, máy 8 GB chỉ còn ~0,8 GB trống) nên **chưa đối chiếu lại từng byte**. `Vendor/vtts/README.md` (mới): bố cục + cách dựng lại / nâng runtime / nâng model.
- **`Scripts/ci/check_vtts_assets.sh`** thay `fetch_vtts_assets.sh` (xoá): không mạng, không cache — kiểm SHA256 mọi tài sản + `assets/vtts/` đúng 3 file, dựng `vtts_say` từ mã đã vendor đọc thử câu Việt + Anh bằng từng giọng M (kiểm `token_set vi-en`, `mode auto lex 1`, id < vocab, WAV ≥ 1 s, không im lặng), kiểm thử shim với ASan/UBSan như trước. `build-ipa.yml`: một bước "Check vtts assets + smoke test" thay 4 bước cache / tải / lưu / smoke; `paths` đổi sang `check_vtts_assets.sh`. `project.yml`: folder resource `Vendor/vtts/assets/vtts` (bundle vẫn là `vtts/`, Swift không đổi đường tra). `.gitignore` bỏ `/Vendor/vtts-assets/`.
- Bản quyền: `THIRD_PARTY_NOTICES.md` ghi thêm `tools/`, bản S, CMUdict nguồn trong repo (BSD-2 điều khoản 1) bên cạnh VLEX trong IPA (điều khoản 2). Chú thích `Package.swift`, `VttsVoice`, `VttsRuntime`, `vtts_bridge_smoke.c`, `ci-release.md` cập nhật theo.
- Dung lượng thêm vào git: ~13,1 MB tài sản (4 model 7,57 MB + `lex_en.bin` 1,86 MB + `cmudict.dict` 3,62 MB) + ~85 KB công cụ.
- Kiểm: `bash -n`, thử phần kiểm SHA256 của script mới trên Windows (bắt được file thừa trong `assets/vtts/`), YAML hợp lệ, `check_architecture.py` (chỉ còn violation cũ `JSDom.swift`). **Không biên dịch / chạy `vtts_say` được tại chỗ (Windows)** — chỉ CI.

## [1.3.1030] - 2026-11-20

### chore: Màn tự thử nhịp dọc header (tạm thời), đầu dò header sửa cho iOS 26, mũi back tự dựng trùng chỗ mũi back hệ thống

Anh Bửu chọn mốc B ("đáy thanh +16": nội dung đầu tiên cách đáy thanh tiêu đề / đáy ô tìm 16pt) sau log đo 1.3.1025 (iPhone 11: Form không tiêu đề nhóm 35pt, dưới ô tìm 50pt, List trơn 0pt, panel 4pt; mũi back hệ thống x=12 trong khi nội dung x=20) → duyệt bản đo.

- **Màn "Thử nhịp dọc header"** (tạm thời, Cài đặt › Ghi log hệ thống › Chẩn Đoán; `Views/Settings/Logs/HeaderSpacingLab/`): một nút **Chạy** tự đẩy lần lượt 22 trang mẫu — Form không / có tiêu đề nhóm, Form dưới ô tìm, List trơn (có / không ô tìm), panel ScrollView, header tự dựng — mỗi kiểu với các cách chỉnh khoảng trên (`contentMargins` top 0 / 16, `defaultMinListHeaderHeight` 0, `listSectionSpacing(.compact)`, đệm panel 16). Mỗi trang ~1,7 s: đầu dò UIKit (`HeaderSpacingLabProbe`) chụp đáy thanh, đáy ô tìm, mũi back hệ thống, ô / khung tiêu đề nhóm đầu; `labMeasure` (khung SwiftUI) đo chữ tiêu đề nhóm, chữ hàng đầu, panel đầu, icon "…" phải, mũi back tự dựng. Kết quả hiện trên màn + log `📐 [HeaderLab]` (kèm một lần cây view con của thanh: lớp + khung, để biết iOS 26 dựng ô nút toolbar bằng gì) + nút chia sẻ báo cáo. Gỡ cả thư mục khi đã áp.
- **Đầu dò `📐 [HeaderLayout]`** (`PageHeaderLayoutProbe`, vẫn tạm): iOS 26 không còn lớp "HostingView" trong thanh (1.3.1025 ra `left=- right=-`) ⇒ đo **view lá** nhìn thấy ở hàng nút, chia trái / phải (số mảnh, mép trái nhất – phải nhất); trang có tab vuốt (Kệ, Kho tiện ích) ⇒ đo scroll view dọc trong trang đang hiện; chọn scroll view theo phần **nằm trong cửa sổ**; `note=scrolled / offscreen / nobar` đánh dấu dòng nhiễu.
- **Mũi back tự dựng trùng chỗ mũi back hệ thống**: `HeaderBackButton` lùi `HeaderMetrics.backChevronOutdent` (8pt) ra ngoài lề (bề ngang bố cục 30pt, vùng chạm vẫn 38pt) ⇒ mũi ở `lề − 8` như nút back hệ thống (đo: x=12 khi lề 20). Áp cho trang con trong sheet, sheet hub, Reader, truyện tranh, trang xem phim mở bằng UIKit. Khoảng mũi → chữ tiêu đề giữ ~8pt.
- `ui-conventions.md`: luật nút back tự dựng thêm phần lùi 8pt.
- Kiểm: chỉ đọc code + `check_architecture.py` (chỉ còn violation cũ `JSDom.swift`); **không build tại chỗ (Windows), chưa chạy trên máy**. Cần: mở Cài đặt › Ghi log hệ thống › Thử nhịp dọc header, bấm Chạy, để yên ~50 s, bấm chia sẻ gửi báo cáo; nhìn mũi back ở trang con sheet hub / Reader có thẳng với mũi back của trang Cài đặt không.

## [1.3.1029] - 2026-11-20

### chore: vtts — CI giữ cache từ điển khi build đỏ, kiểm thử shim nhanh hơn

Tiếp 1.3.1028 (rà lại trước khi đẩy; chưa lượt CI nào chạy bản vtts).

- **Cache tài sản vtts tách `actions/cache/restore` + `save`**: `actions/cache` gộp chỉ lưu khi cả job xanh ⇒ lượt đầu mà shim C / code Swift còn lỗi biên dịch sẽ dựng lại VLEX ~8 phút mỗi lần đẩy sửa. Nay `fetch_vtts_assets.sh` có hai bước — `assets` (tải model, dựng VLEX, `vtts_say` đọc thử) rồi lưu cache ngay, sau đó `smoke` (kiểm thử shim) — không tham số vẫn chạy cả hai (build local). Bước `smoke` từ chối chạy khi chưa có tài sản khớp stamp.
- **Kiểm thử shim nhẹ hơn**: bản dựng thử đặt `-DVTTS_BRIDGE_SEGMENT_CP=150` ⇒ đường chia đoạn dài chạy với 8 bản câu thử (~550 code point, 4 phần) thay vì ~60 bản (~4 phút tiếng dưới ASan, mỗi giọng); chỉ giọng đầu chạy đoạn dài (`--long`), vẫn đòi đúng 8 lần tiếng câu thử + khoảng 150 ms. `vtts_bridge.c` thêm `#error` khi `VTTS_BRIDGE_SEGMENT_CP` ra ngoài `[1, VTTS_TEXT_MAX_CP)` ⇒ không phần nào chạm mức 4096 code point mà front-end cắt im lặng. Thêm `-fno-sanitize=function` (Apple clang mới bật nó cho C; tránh báo động nhầm ở callback nội bộ của upstream).
- `ci-release.md`: mục vtts ghi hai bước + cách lưu cache.
- Kiểm: `bash -n`, thử lại các hàm kiểm stamp / WAV của script trên Windows, YAML hợp lệ, `check_architecture.py` (chỉ còn violation cũ `JSDom.swift`). **Không biên dịch được C / Swift tại chỗ (Windows).**

