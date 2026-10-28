# CHANGELOG - Nhật ký Thay đổi CodeGraph FreeBook

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **FreeBook**.

## [1.3.640] - 2026-10-28

### fix: độ trong suốt và độ đục của nút nổi, menu áp đúng cài đặt

Người dùng: *"Cài đặt trong suốt không hoạt động. Tôi cài kiểu gì cũng hiển thị giống 2 hình đầu"* (ảnh: nút tai nghe Reader là đĩa xám đặc, ngăn kéo menu xám đều; ô xem trước ở màn Giao diện thì đổi đúng theo thanh kéo).

- **Nguyên nhân (khả năng cao, chưa kiểm được trên máy)**: lớp nhoè `SideDrawerPartialBlurView` (1.3.633) dùng `UIViewPropertyAnimator` dừng giữa chừng để có mức nhoè lưng chừng. Animator dễ bị hệ thống chạy hết (dựng view lần đầu, chuyển màn, app vào nền rồi về) ⇒ kẹt ở mức nhoè **đầy đủ**; ô xem trước trông đúng chỉ vì mỗi lần kéo thanh là animator được dựng lại. Hệ quả: "kính đục vừa" của 1.3.633 nhiều khả năng chưa bao giờ hiện đúng trên máy, và mọi giá trị cài đặt trông như nhau.
- **`FloatingGlassBackground`, `SideDrawerGlassBackground`**: lớp nhoè thay bằng shape tô `.ultraThinMaterial` (ép tông tối/sáng qua `colorScheme`) với `.opacity(frost)` — không có trạng thái nên không kẹt. Lớp màu vẫn `1 − độ trong suốt`, viền giữ nguyên.
- **Đánh đổi** (người dùng đã duyệt): 0% và 100% đúng y cài đặt; mức giữa là nền rõ trộn nền nhoè (hơi có bóng đôi) thay vì nhoè mịn bán kính nhỏ.
- Xoá `SideDrawerPartialBlurView.swift` (chỉ hai chỗ dùng trên); sửa chú thích `GlassChromeSettings`.
- Chuyển entry `[1.3.610]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy — cần thử 0%/100% ở cả ngăn kéo lẫn nút tai nghe, và sau khi cho app vào nền rồi mở lại.

## [1.3.639] - 2026-10-28

### fix: tin dừng lọc name không còn hiện hai lần

Người dùng: *"Đã dừng lọc name ở ch.115: Chương 116: Dò xét động cùng gặp lại U Minh Hà.. tôi bấm dừng lọc name, dòng này xuất hiện 2 lần"*.

- **Nguyên nhân** (lỗi của 1.3.632): `stopActiveTask` thêm tin dừng vào phiên của coordinator qua `updateRun` ⇒ `$runs` phát ⇒ màn AI `mergeRunningSession` đã gộp tin đó vào phiên đang hiện; sau đó `appendStopNote` của màn lại dựng **một tin mới** (khác `id`) từ chuỗi trả về ⇒ hai dòng.
- **`AIRuntimeCoordinator.stopActiveTask`** trả về chính `AIChatMessage` đã thêm (thay cho `String?`); **`ReaderAIFullScreenView.appendStopNote`** chỉ thêm khi phiên đang hiện chưa có tin cùng `id` — đúng dù `$runs` tới trước hay sau.
- **`nameScanStopNote`**: tên chương đã kết bằng `.`/`!`/`?`/`…` thì không thêm dấu chấm (hết "Hà.."); áp cho cả tin dừng tay lẫn dòng đầu tin lỗi khi tự dừng.
- "ch.115" cạnh tên "Chương 116" **không** phải lỗi: số ch. là vị trí trong mục lục (đếm từ 1, `AINameScanTextLoader` lấy `chapter.index`), tên là cách nguồn tự đánh số — giữ nguyên.
- Phiên chat đã lưu trước bản này vẫn giữ hai dòng cũ; chỉ lần dừng sau mới đúng.
- Chuyển entry `[1.3.609]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.638] - 2026-10-28

### feat: xuất TXT cho từ điển chung

Người dùng: *"thêm nút xuất ra txt cho vp,name,phiên âm,… chung"*; chọn "icon trên mỗi thẻ" và "đúng file gốc"; duyệt mockup + plan.

- **Service** `GlobalDictionaryTextExporter` (mới, `Services/Translation/Manager/`): xuất một từ điển chung ra file tạm `VietPhrase_/Name_/PhienAm_/Pronouns_/LuatNhan_<yyyyMMddHHmmss>.txt`. VietPhrase/Name/Pronouns/LuatNhan duyệt ngược cây đang nạp (hoặc mở `.dat`) bằng `allEntries()`, ghi `từ=nghĩa` theo khúc ~1 MB; số entry phải khớp `wordCount`, lệch thì báo lỗi, không xuất file thiếu (cùng chốt chặn với `DictionaryMergeService`). PhienAm (và `.txt` chưa kịp biên dịch) chép nguyên file. Xuất **đúng file gốc** — không kèm từ thêm/xoá ở VP/Name Chung (bản đó đi qua nút Gộp); nhập lại qua chính thẻ cho ra từ điển y như cũ.
- **Cài đặt dịch thuật › Từ điển chung**: icon ↑ cuối mỗi thẻ (`TranslationSettingsView+Export`, phủ `overlay` lên thẻ vì thẻ là nhãn của nút Nhập — lồng nút trong nhãn nút thì chạm lẫn nhau; `DictionaryCard` chừa ô 32×32 qua `reservesExportSlot`). Chạm thẻ vẫn là Nhập. Đang xuất: vòng quay + "Đang xuất...", nút Nhập của thẻ đó khoá; một lượt xuất một lúc; thẻ chưa có dữ liệu thì icon mờ. Xuất chạy `Task.detached` rồi mở bảng chia sẻ; đóng bảng thì xoá file tạm; lỗi ⇒ toast + log `❌`.
- Chuyển entry `[1.3.608]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code + diff; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy. Rủi ro: VietPhrase cỡ trăm nghìn – triệu từ nên xuất mất vài giây và tốn RAM cỡ lúc Gộp.

## [1.3.637] - 2026-10-28

### fix: thanh kéo Giao diện cập nhật ngay, nút + nổi ở Lọc rác

Người dùng: *"cài đặt độ trong suốt và độ đục chưa hoạt động"*, *"nút thêm lọc rác chưa chuẩn hoá"*; duyệt mockup + plan.

- **Khoá cài đặt kính bỏ dấu chấm** (`GlassChromeSettings`): `glassChrome.floatingButton.transparency`… → `glassChromeFloatingTransparency`, `glassChromeFloatingFrost`, `glassChromeDrawerTransparency`, `glassChromeDrawerFrost`. `@AppStorage` nghe thay đổi qua KVO của `UserDefaults`, KVO đọc dấu chấm là key path lồng nhau ⇒ thanh kéo ghi được nhưng nút nổi, ngăn kéo và ô xem trước (mỗi view một `@AppStorage` riêng) không được báo. Mọi khoá `@AppStorage` khác trong app vốn không có dấu chấm. Giá trị đã kéo dưới khoá cũ (chỉ có từ 1.3.636) về mặc định một lần.
- **Ô xem trước** (`AppearanceSettingsView`): nền tối + chữ xám mờ đổi thành dải 5 "bìa" màu (Ch.1–Ch.5) chạy dưới nút và dưới ngăn kéo, cao 112 → 128pt — trên nền tối, lớp màu kính (xám 0.16) và độ nhoè gần như không đổi khi kéo. Mặc định và màu lớp kính giữ nguyên.
- **Lọc rác** (`JunkFilterManagementView`): "Thêm quy tắc" rời ngăn kéo thành nút "+" nổi (`.floatingAddButton`); nút "…" 17pt semibold như các màn danh sách khác; vạch ngăn sau "Sắp xếp lại" chỉ hiện cùng mục đó (đang tìm thì ngăn kéo không mở đầu bằng vạch). Hàng quy tắc giữ nguyên (người dùng loại Lọc rác khỏi đợt đồng bộ hàng ở 1.3.635).
- Chuyển entry `[1.3.607]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code + diff; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy. Nguyên nhân khoá có dấu chấm là suy từ code, chưa tái hiện được trên máy.

## [1.3.636] - 2026-10-28

### feat: màn Giao diện chỉnh nút nổi và menu, nút + nổi, danh sách cuộn vô cực

Người dùng: *"mấy chỗ danh sách lazyload hãy sửa lại thành scroll vô cực"* (chọn cả 4 chỗ), *"đồng bộ UI danh sách khác giống UI của vp/name luôn"*, *"đem hết nút trừ nút quay lại vào dropdown"*, *"đem nút thêm thành nút icon + ra ngoài ... vị trí tương tự nút tai nghe trong reader ... trong suốt. Sửa nút tai nghe trong suốt luôn"*, *"thêm nav giao diện ... gom hết các nav liên quan ... thêm cài đặt giao diện cho menu. có thanh kéo độ trong suốt độ đục"*, gom thêm NSFW; duyệt mockup + plan.

- **Cài đặt › Chung › Giao diện** (`AppearanceSettingsView`, mới): gom "Kiểu hiển thị danh sách", "Nội dung nhạy cảm (NSFW)", "Bàn phím & ô nhập" (bỏ ba dòng đó ở Chung/Thư Viện). Hai nhóm thanh kéo **Độ trong suốt** (lớp màu nền, 1 = không màu) / **Độ đục** (độ nhoè kính) + ô xem trước + "Đặt lại mặc định": **Nút nổi** (mặc định 90% / 0%) và **Menu ba chấm** (mặc định 45% / 60% = đúng "kính đục vừa" 1.3.633). Khoá ở `GlassChromeSettings`.
- **Nền kính dùng chung**: `FloatingGlassBackground` (nút tròn) và `SideDrawerGlassBackground` (ngăn kéo, thay nền gán cứng trong `SideDrawerMenuPanel`) đọc thẳng `@AppStorage` ⇒ kéo là đổi ngay. Nút tai nghe Reader (`readerEdgeButton`) thành nút 52pt nền kính theo cài đặt, tâm giữ đúng chỗ cũ (bỏ nền tối 34% + material + bóng).
- **Nút "+" nổi** (`FloatingAddButton`, `.floatingAddButton(_:action:)` qua `safeAreaInset` để hàng cuối không bị che): thay mục "Thêm…" của ngăn kéo / nút "+" header ở 7 màn — từ điển VP/Name, thay thế TTS, phiên âm NghiTTS, phiên âm VieNeu, công cụ tra cứu, quy tắc mục lục, rule dịch nhanh. Header các màn này chỉ còn nút quay lại + "…" 17pt semibold; "Khôi phục mặc định" của công cụ tra cứu vào ngăn kéo.
- **Hàng kiểu VP/Name** (cụm icon `.subheadline` [Sửa][Chuyển][Tắt/Bật `pause.circle`/`play.circle`][Xoá], giữ vuốt): thay thế TTS (bỏ công tắc; Chuyển chỉ ở tầng riêng), phiên âm NghiTTS (+Xoá), VieNeu (+Sửa/Xoá), công cụ tra cứu (+Sửa/Xoá, xoá theo id), quy tắc mục lục (`TOCRulesConfigView+Row`, bỏ công tắc; rule mặc định Xoá mờ).
- **Cuộn vô cực**: từ điển VP/Name (200/lượt), NghiTTS và VieNeu (100/lượt), rule dịch nhanh (200/lượt, bỏ nút "Xem thêm") nạp lượt kế khi hàng cách cuối 50 hoặc hàng cuối hiện ra; bỏ dòng "Cuộn xuống để tải thêm". **Tin nhắn AI** (`ReaderAIFullScreenView+OlderMessages`): cuộn lên gần đầu tự nạp 20 tin cũ, giữ chỗ bằng `scrollTo` tin đầu cũ; chỉ bật 0,6 s sau khi mở/đổi phiên. **Mục lục nhiều trang** (`BookDetailTOCView+AutoLoad`, lưới video `onReachEnd`): cuộn tới cuối tự tải các trang còn lại **một lần** mỗi lần dựng tab, không tự gọi khi đang báo lỗi (nút "Tải thêm" giữ làm thử lại) và không tự gọi khi đã có mục lục đầy đủ lưu trên máy.
- `CLAUDE.md`/`AGENTS.md`: quy ước màn danh sách (header, nút "+" nổi, hàng VP/Name, nạp trước, `GlassChromeSettings`); đường dẫn NSFW mới.
- Chuyển entry `[1.3.606]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code + diff; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy. Rủi ro cần thử: giữ chỗ khi nạp tin AI cũ (có thể xê dịch ~36pt), mục lục trang 1 ngắn vừa một màn sẽ tự tải ngay khi mở tab, xoá từ ở hai màn phiên âm nạp lại cả từ điển (hành vi cũ, giờ dễ gặp hơn vì icon Xoá một chạm).

## [1.3.635] - 2026-10-28

### fix: thay thế TTS hiện 2 dòng, đồng bộ cỡ chữ danh sách theo VP/Name

Người dùng: *"danh sách thay thế tts: mỗi rule hiển thị 2 dòng, dòng 1 là từ gốc, dòng 2 là mũi tên và từ thay thế. Giảm size chữ lại bằng size của danh sách vp/name. Đồng bộ size chữ các danh sách khác bằng vp/name luôn"*; duyệt mockup, chọn font thường (không monospaced) cho dòng regex, *"chỗ nào chưa hiển thị 2 hàng thì lọc ra chuyển thành 2 hàng luôn"*, *"lọc rác không làm"*.

- **Chuẩn**: hàng VP/Name `DictionaryEntryRow` — dòng khoá `.headline`, dòng giá trị `.subheadline` màu phụ.
- **Thay thế TTS** (`TTSReplacementManagerView+Layer`): `ruleText(for:)` mới dùng chung cho `ruleRow` và `globalRulesSection` — dòng 1 `"gốc"` `.headline` (màu phụ khi rule tắt), dòng 2 `→ "thay thế"` hoặc `→ (rỗng)` `.subheadline`; bỏ `.body` monospaced một dòng. Giữ dấu nháy vì nhiều rule mặc định thay bằng dấu cách. Icon sửa `.subheadline`; công tắc, vuốt "Sang chung", nút "Lấy" giữ nguyên.
- **Từ điển tiếng Nhật VieNeu** (`VieNeuJapaneseDictionaryView.row`): một dòng `khoá … cách đọc` thành hai dòng `.headline` / `.subheadline`, vẫn bấm cả hàng để sửa.
- **Chỉ đổi cỡ chữ**: rule dịch nhanh (`QuickTranslationRuleEntryRow`: pattern `.footnote` monospaced → `.headline`, replacement `.footnote` → `.subheadline`, giữ màu trắng và dòng "dòng N"/badge), công cụ tra cứu (`SearchEnginesConfigView`: URL `.caption` → `.subheadline`), quy tắc mục lục (`TOCRulesConfigView`: tên `.headline`, regex `.caption` monospaced → `.subheadline`, "Ví dụ" giữ `.caption2`), duyệt name AI (`ReaderAINameReviewCardView`: 13/12pt cố định → `.headline`/`.subheadline`, hàng cao hơn, badge giữ cỡ cũ).
- **Không đổi**: lọc rác (người dùng loại), xung đột khi nhập từ điển (bố cục `cũ → mới` cố ý), màn thử rule dịch nhanh, chọn quy tắc mục lục khi nhập truyện.
- Chuyển entry `[1.3.605]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.634] - 2026-10-28

### feat: tải truyện dừng và báo lỗi khi 5 chương liên tiếp tải lỗi

Người dùng: *"nếu tải bị lỗi 5 chương liên tiếp thì dừng lại và thông báo"*; chọn báo lỗi + Thử lại (không thêm trạng thái tạm dừng), áp cho chữ + comic + video, xuất ebook bị dừng thì không ghi file; duyệt plan.

- **`DownloadFailureStreak`** (mới): ngưỡng `limit = 5` (cùng `TTSManager.maxConsecutiveChapterFailures`); chương lỗi ⇒ +1, chương lấy được hoặc đã có sẵn trong máy ⇒ về 0; lời báo *"Đã dừng: 5 chương liên tiếp tải lỗi (ch.12–16). Kiểm tra nguồn rồi bấm Thử lại — chương đã tải không phải tải lại."* (video: "tập").
- **Truyện chữ / xuất ebook** (`DownloadManager+ChapterLanes.runChapterLanes`): đếm ở vòng giao kết quả đã xếp đúng thứ tự mục lục ⇒ "liên tiếp" đúng cả khi chạy 2–3 luồng; `.skippedUncached` ("Chỉ xuất chương đã tải") không tính. Chạm ngưỡng ⇒ `checkCancellation` (đang huỷ thì vẫn báo "Đã hủy") rồi ném `LimitReached` ⇒ nhánh `catch` sẵn có của `executeTask` bỏ file xuất dở + `markFailed`. Trước đây chương lỗi bị bỏ qua tới hết phạm vi.
- **Truyện tranh** (`DownloadManager+Comic`): đếm trong vòng từng chương; chạm ngưỡng ⇒ nhả `ComicImageScriptRunner` + `markFailed`.
- **Video** (`DownloadManager+Video`): đếm theo tập; chạm ngưỡng ⇒ các tập còn chờ thành "Đã huỷ" + `markFailed`, cùng kiểu dừng khi bộ nhớ dưới 1 GB.
- **Thông báo**: dùng `markFailed` sẵn có — toast lỗi, dòng "Thất bại" kèm lý do ở tab Tải và hộp thư Thông báo, nút Thử lại (tải tiếp, chương đã tải bỏ qua nhanh).
- Chuyển entry `[1.3.604]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. CI là cổng biên dịch; chưa thử trên máy.

## [1.3.633] - 2026-10-28

### fix: ngăn kéo menu thành kính đục vừa

Người dùng: *"làm cho menu có một độ đục nhất định. Cho mockup trước"*; duyệt **kiểu 2 — kính đục vừa** (nhoè vừa + tối 55%).

- **`SideDrawerPartialBlurView`** (mới, `Views/Common/SideDrawerMenu/`): nhoè **một phần** — `UIVisualEffectView` với `UIViewPropertyAnimator` chuyển `effect` từ `nil` sang `UIBlurEffect(.systemUltraThinMaterialDark)` rồi dừng ở `intensity` (0,6). Material của SwiftUI chỉ có một mức nhoè, mạnh tới mức nền Kệ đen thành mảng xám đều (lý do 1.3.622–630 bị chê "chẳng trong suốt"). Animator dựng lại khi view vào cửa sổ và khi app trở lại foreground; luôn `stopAnimation(true)` trước khi thả (thả animator đang dừng là crash).
- **`SideDrawerMenuPanel.drawerBackground`**: nhoè 60% + lớp tối `Color(white: 0.16).opacity(0.55)` (thay lớp tối 80% không nhoè của 1.3.632); viền trái và lớp phủ 30% phần màn còn lại giữ nguyên.
- Chuyển entry `[1.3.603]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy — độ nhoè thật trên máy có thể khác mockup, chỉnh `intensity` nếu cần.

## [1.3.632] - 2026-10-28

### fix: bấm dừng lọc name ghi chương đã dừng vào tin AI, ngăn kéo menu tối 80%

Người dùng: *"tôi yêu cầu là bấm dừng thì hiển thị chương đã dừng trong tin nhắn trả lời của ai chứ không phải thông báo. làm lại cho đúng"* — chọn **tin AI riêng ngay sau** tin kết quả; tự dừng *"có, không bỏ toast"*. Thêm: *"độ trong suốt menu thành 80% cho tôi"* — chọn **lớp tối 80%**.

- **Bấm dừng lọc name nhiều chương** (`AIRuntimeCoordinator.stopActiveTask`): bỏ toast "Đã dừng lọc name · …" của 1.3.628; thay bằng **tin AI riêng** ngay sau tin kết quả: `Đã dừng lọc name ở ch.21–30: <tên> → <tên>.` (một chương `ở ch.21: <tên>.`; chưa gửi lượt nào `… khi đang chuẩn bị.`). Danh sách `Tên=Nghĩa` của tin kết quả giữ sạch để sao chép/duyệt. `stopActiveTask` trả về tin đó (`@discardableResult`) để màn AI (`cancelBatchExtraction`, `stopStreaming`) thêm đúng tin ấy vào phiên đang hiện trong `@State`; chat thường không có tiến độ ⇒ không thêm gì.
- **Tự dừng** (lần quét chính và lần thử lại): tin lỗi trong màn AI có thêm dòng đầu `Lọc name tự dừng ở ch.…` trước `Lỗi quét tên riêng: …`; toast "Lọc name tự dừng · ch.…" giữ nguyên.
- Helper mới `nameScanStopNote(_:bookId:)` (`+BatchExtraction`), đọc tiến độ trước khi entry bị dọn.
- **Ngăn kéo menu** (`SideDrawerMenuPanel.drawerBackground`): lớp tối không làm mờ 62% → **80%**.
- Chuyển entry `[1.3.602]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.631] - 2026-10-28

### fix: ngăn kéo menu bỏ lớp kính mờ, nhìn xuyên được nền phía sau

Người dùng (kèm ảnh chụp ngăn kéo Kệ trên máy): *"sao ngăn kéo chẳng trong suốt tí nào"*.

- **Nguyên nhân** (`SideDrawerMenuPanel.drawerBackground`): lớp `.ultraThinMaterial` làm nhoè nền phía sau rất mạnh; nền Kệ gần như toàn đen với chữ nhỏ nên bị nhoè thành một mảng xám đều — nhìn như nền đặc dù lớp tối phía trên đã hạ còn 38% (1.3.626). Mockup đã duyệt vốn không làm mờ.
- **Sửa**: bỏ material, nền ngăn kéo chỉ còn một lớp tối bán trong suốt `Color(white: 0.08).opacity(0.62)` — bìa và chữ của màn bên dưới vẫn nhìn thấy (tối đi), chữ menu trắng vẫn đọc được. Viền trái và lớp phủ 30% phần màn còn lại giữ nguyên.
- Chuyển entry `[1.3.601]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.630] - 2026-10-28

### feat: giữ kết quả AI chưa xem trên nút nổi, bấm để mở thẳng màn AI

Người dùng: *"sau khi chế độ AI chạy xong mà người dùng chưa xem hãy giữ lại để người dùng có thể bấm vào xem trực tiếp"*, *"ý tôi là sau khi chạy xong người dùng chưa đọc thì còn trên widget để người dùng vào xem"*; duyệt mockup, chọn: nút ✨ đứng yên (không nháy), mục mất khi mở màn AI của truyện, giữ qua lần mở app; duyệt plan.

- **Kết quả chưa xem**: lượt chat, quét name nhiều chương hay thử lại lượt lỗi chạy xong (hoặc lỗi) trong lúc màn AI của truyện đó **không** mở ⇒ entry ở lại `AIRuntimeCoordinator.runs` với `isRunning = false` + `unseenOutcome` (`.finished`/`.failed`, `AIBookRunState`). Lối ra hoàn tất/lỗi đi qua `finishRun` (`AIRuntimeCoordinator+UnseenResults`); bấm dừng vẫn gọi thẳng `endRun` nên **không bao giờ** thành kết quả chưa xem. Lượt mới của chính truyện đó (`beginRun`) bỏ kết quả cũ. Toast hoàn tất giữ như cũ.
- **Mất khi xem**: `presentedAIBookId` nhận đúng `bookId` (mọi đường mở màn AI: nút nổi, nút AI trong Reader) ⇒ `markResultSeen` bỏ cờ; entry chỉ còn vì nó thì bỏ luôn entry, còn nút "Thử lại k lượt lỗi" thì giữ entry.
- **Qua lần mở app**: `AIUnseenResultStore` (`Services/AI/`) ghi `applicationSupportDirectory/ai_unseen_results.json` trên queue nền, mỗi truyện một `AIUnseenResult` (`Models/AI/`): tên truyện, xong/lỗi, mốc xong, **phiên chat chứa kết quả**, chương, hai cờ dịch tên chương. Khởi tạo coordinator nạp lại entry, `lastSessionIds` (màn AI mở đúng phiên có kết quả) và `ActiveContext` cho `presentFullScreen`. **Giới hạn**: không lưu nội dung chương ⇒ sau khi mở lại app, màn AI mở từ nút nổi (không qua Reader của chính truyện đó) có `currentChapterRawContent` rỗng — xem kết quả không ảnh hưởng, chỉ lượt chat mới từ màn đó thiếu nội dung chương hiện tại.
- **Nút nổi** (`FloatingHubPresentationReader`): truyện chưa xem vào `aiTasks` sau các truyện đang chạy (xong gần nhất lên đầu). AI chỉ còn kết quả chưa xem ⇒ vẫn là `.ai` trong `runningKinds` (icon ✨, chạm bung menu sang trang AI) nhưng nằm trong `ButtonState.quietKinds` nên **không nháy**, icon màu chữ hệ thống; VoiceOver đọc "Trợ lý AI đã xong, chưa xem".
- **Menu**: dòng Trợ lý AI một truyện ⇒ "Đã xong — bấm để xem" (xanh) / "Lỗi — bấm để xem" (đỏ) (`FloatingHubItem.DetailTone`); nhiều truyện ⇒ "1 đang chạy · 2 chưa xem" / "N truyện chưa xem". Trang danh sách đổi tên **"Tác vụ AI"** (`FloatingHubAITaskListView`): truyện chưa xem có icon ✓ xanh / ! đỏ, không có nút ✕. Chữ giải thích ở Cài đặt › Nội dung nhạy cảm đổi theo tên mới.
- Chưa build tại chỗ (Windows), chưa thử trên máy.

## [1.3.629] - 2026-10-28

### feat: công tắc NSFW ở đầu ngăn kéo menu Khám phá

Người dùng: *"thêm nút bật tắt nfsw vào menu của khám phá"*; duyệt mockup, chọn đặt dòng lên đầu menu.

- **Ngăn kéo "Tuỳ chọn nguồn" của Khám phá** (`DiscoverySourceMenuButton`): thêm dòng công tắc "Nội dung NSFW" (icon `eye`) ở **đầu** ngăn kéo, cùng kiểu dòng của ngăn kéo Kệ (`SideDrawerToggleRow`); chạm cả hàng để đổi, ngăn kéo vẫn mở. Dùng chung khoá NSFW toàn app (`RepositoryFilterPolicy.includeNsfwDefaultsKey`) với Cài đặt › Nội dung nhạy cảm, ngăn kéo Kệ và nút viên thuốc NSFW ở màn chọn nguồn (giữ nguyên). Tắt khi đang xem nguồn NSFW ⇒ Khám phá tự chuyển sang nguồn đầu tiên còn lại như cũ; không còn nguồn nào ⇒ nút menu biến mất và ngăn kéo tự gỡ (`onDisappear` của `sideDrawerMenu`).
- Chuyển entry `[1.3.599]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. CI là cổng biên dịch; chưa thử trên máy.

## [1.3.628] - 2026-10-28

### feat: ngăn kéo menu mở sheet ngay, hiện chương đang lọc name và toast khi dừng

Người dùng: *"Điều tra vì sao chọn option mở sheet, popup, menu phụ từ menu dropdown đều hiển thị lên khá chậm"*; *"ngoài ra tôi muốn bạn thêm tin ngắn ghi tên chương đang lọc name khi dừng lọc name nhiều chương kể cả thủ công lẫn tự dừng"*, *"Hiển thị chương đang lọc trên header luôn"*; duyệt mockup, rồi *"thực hiện hết tất cả yêu cầu của tôi đi"*.

- **Ngăn kéo menu bằng cửa sổ nổi** (`Views/Common/SideDrawerMenu/`): bỏ `fullScreenCover` — khi cover còn mở iOS không cho trình bày cái mới, nên mục mở sheet/hộp thoại phải chờ trượt ra → gỡ cover (UIKit có thể vẫn chạy hiệu ứng dismiss dù đã `disablesAnimations`) → `onDismiss` → một nhịp runloop, rồi sheet mới trượt lên. Nay ngăn kéo nằm trong cửa sổ riêng (`SideDrawerMenuWindowManager`, level `alert - 0.5`: trên ba widget nổi, dưới toast; không bao giờ là key window) và hàng thao tác chạy action **ngay khi ngăn kéo bắt đầu trượt ra** — sheet của màn trượt lên phía dưới cùng lúc. API công khai giữ nguyên, không nơi gọi nào phải sửa.
  - Nội dung: `SideDrawerMenuContentRelay` (view vô hình gắn sau màn) đẩy panel mới nhất sang cửa sổ mỗi lần màn vẽ lại; hàng công tắc/hàng chọn tự gọi vẽ lại sau khi đổi giá trị. Mỗi chỗ gắn có định danh, mỗi lượt mở có mã — callback trễ của lượt cũ bị bỏ.
  - Không có lớp vô hình chặn chạm: bắt đầu đóng là cửa sổ thôi nhận chạm (`SideDrawerMenuOverlayWindow.hitTest` trả `nil`), trượt xong (dự phòng 0,44 s) thì ẩn và gỡ nội dung; màn bị gỡ khi ngăn kéo đang mở ⇒ ẩn ngay.
  - `SideDrawerMenuHostingController` chuyển tiếp thanh trạng thái, home indicator và hướng xoay theo màn đang hiện của cửa sổ chính (Reader, trình phát video khoá xoay).
  - Log `[Drawer]` (khi bật log): mở, chạm hàng, action chạy, cửa sổ ẩn — ms tính từ lúc chạm.
  - Giới hạn mới: nội dung ngăn kéo **không** được chứa view đọc `@Environment`/`@EnvironmentObject`/`@Query` của màn (cửa sổ riêng không thừa hưởng environment).
- **Chương đang lọc name** (`AINameScanProgress`): thêm chương đầu/cuối của lượt đang gửi và tên đã dịch sẵn. Tên gốc lấy lúc dựng lượt (`AINameScanTextLoader`, `title` trim, rỗng thì `titleTrans`), dịch **một lần mỗi lượt** ngoài main thread trong `runTurns` theo cấu hình dịch tên chương của màn AI (`AINameScanChapterTitleStyle`, truyền qua `startBatchExtraction`; nút thử lại dùng lại cấu hình của lần quét gốc).
  - Dải tiến độ (`ReaderAIBatchProgressBannerView`): `Đang quét tên riêng: Batch 3/10 · ch.21–30` + dòng `ch.21 <tên> → ch.30 <tên>` (một dòng, tím nhạt); một chương: `· ch.21: <tên>`; lúc chờ giới hạn Google vẫn hiện dòng chương. Tiêu đề trang "AI đang chạy" thêm ` · ch.21–30`.
  - Toast khi dừng — hiện cả khi màn AI đang mở, màn AI đóng thì kèm tên truyện: bấm Dừng (nút trên dải tiến độ hoặc thanh nhập, chỉ khi đang lọc name) ⇒ `Đã dừng lọc name · ch.21–30: <tên> → <tên>` (`.info`); tự dừng ở lần quét chính hoặc lần thử lại ⇒ `Lọc name tự dừng · …` (`.error`), thay toast "Quét tên riêng bị gián đoạn.". Không toast khi chạy xong bình thường, khi chờ giới hạn Google, khi Gemini Web tạm dừng lúc app ở nền.
  - Lần thử lại tự dừng giờ luôn thêm tin "Lỗi quét tên riêng: …" vào màn AI (trước chỉ khi Google bắt xác minh) — lý do dừng không còn nằm trong toast.
- Chuyển entry `[1.3.598]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code (hai phần làm bởi agent con trong worktree riêng, đã duyệt); `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy. Chỗ dễ lỗi biên dịch nhất: các override `childFor…` / `prefersStatusBarHidden` trên lớp con `UIHostingController`.

## [1.3.627] - 2026-10-28

### feat: icon đã tải ở danh sách chọn chương bắt đầu của sheet tải truyện

Người dùng: *"thêm biểu tượng đã tải vào danh sách chương ở tải truyện nữa"*; duyệt mockup + plan.

- **Màn "Chọn chương bắt đầu"** (`ReaderAINameScanChapterPickerView`): chương đã có trong máy hiện `arrow.down.circle.fill` cỡ caption màu xanh lá bên phải (trước dấu ✓ nếu đang chọn) — cùng kiểu danh sách chương Reader / Chi tiết truyện / mục lục comic.
- **Trạng thái đã tải đọc ngầm** cùng lượt nạp + dịch danh sách (`DownloadStartChapterCatalog`, trong `Task.detached`, không đọc đĩa trong `body`): truyện chữ theo cờ `isCached` + `length > 0` của mục lục `ChapterStore` (cùng điều kiện dòng "Đã tải X/Y"); truyện tranh theo `ComicOfflineStore.downloadedChapterIndexes`, video theo `VideoOfflineStore.downloadedEpisodeIndexes` (manifest, đọc một lần). `pickerChapters` nhận `contentKind` thay cho `skipsSections`; `TaskOptionsSheet.isMediaBook` thành `contentKind`.
- `AINameScanChapter.isCached` (mặc định `false`): sheet quét tên AI không đặt cờ — danh sách ở đó vốn toàn chương đã tải, không hiện icon thừa.
- Chuyển entry `[1.3.597]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. CI là cổng biên dịch; chưa thử trên máy.

## [1.3.626] - 2026-10-28

### fix: ngăn kéo menu trong suốt hơn nữa

Người dùng: *"thêm trong suốt cho menu nữa"*.

- `SideDrawerMenuPanel.drawerBackground`: lớp tối trên lớp `.ultraThinMaterial` hạ tiếp 55% → 38% (`Color(white: 0.12)`); lớp phủ phần màn còn lại giữ 30%.
- Chuyển entry `[1.3.596]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy — độ đọc rõ chữ ở mức 38% cần người dùng xem trên máy.

## [1.3.625] - 2026-10-28

### fix: sheet tải/xuất mở toàn màn, bỏ nửa màn

Người dùng: *"sửa lại sheet tải và xoát thành toàn màn hình đi, bỏ nữa màn hình"*.

- `TaskOptionsSheet`: `.presentationDetents([.medium, .large])` của 1.3.624 thành `[.large]` — mở thẳng toàn màn ở cả 7 chỗ gọi. Sheet nhập kho tiện ích và nhập nguồn Legado từ URL giữ nửa màn (không nằm trong yêu cầu).
- Chuyển entry `[1.3.595]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. CI là cổng biên dịch; chưa thử trên máy.

## [1.3.624] - 2026-10-28

### feat: sheet tải/xuất nửa màn, chọn chương bắt đầu, nghỉ và số luồng tải; nhập kho, Legado URL thành sheet

Người dùng: *"Sửa sheet tải chương, xuất truyện hiện thị giữa màn hình. Bỏ phần giải thích. Thêm vào icon dấu hỏi tương tự thêm rule dịch. Thêm chọn chương bắt đầu tải từ danh sách chương (nhớ dịch danh sách chương, xử lý lấy danh sách ngầm để tránh đơ máy). Thêm mục chọn delay giữa các lần tải, thời gian delay mặc định như hiện tại. mục chọn số luồng tải, mặc định như hiện tại"*; chọn nửa màn, delay thanh kéo 0–10 giây, 1–3 luồng, nhớ theo nguồn. Thêm: *"Làm sheet nhập kho tiện ích hiển thị giữa màn hình, nhập nguồn legado từ url sửa thành sheet luôn, thêm nút clear, paste trên ô nhập"*; duyệt mockup + plan.

- **Sheet tải/xuất** (`TaskOptionsSheet`, tách thêm `+StartChapter`, `+Speed`, `+Help`): `.presentationDetents([.medium, .large])` ngay trong sheet nên cả 7 chỗ mở đều nửa màn. Bỏ footer định dạng và 3 footer giải thích; nội dung chuyển vào nút "?" (`QuickTranslationRuleHelpButton`) ở tiêu đề mục Định dạng bản xuất / Bắt đầu từ / Tùy chọn tác vụ / Tốc độ tải. Giữ dòng "Đã tải X/Y chương".
- **Bắt đầu từ**: công tắc "Tải từ chương đang đọc" thành ba dòng chọn — Chương đang đọc (mặc định, như cũ), Chương đầu tiên, Chọn chương… (video: "tập"). Màn chọn dùng lại `ReaderAINameScanChapterPickerView` (thêm tham số `noun`) với **toàn bộ** mục lục. `DownloadStartChapterCatalog` (mới) đọc `ChapterStore` (fallback bảng SwiftData `Chapter`) và dịch tên theo `TranslationConfigStore` + phồn → giản của truyện, trong hàm `async` không gắn actor (ngoài main thread, huỷ theo `.task`); lúc đang nạp, "Chọn chương…" báo "Đang tải mục lục…" / "Đang dịch danh sách…" và tạm khoá. Một lần đọc mục lục dùng chung cho dòng "Đã tải X/Y".
- **Chương bắt đầu theo tác vụ** (`DownloadStartChapterStore`, mới): sidecar UserDefaults theo `taskId`, ghi **trước** `enqueueTask`, khớp theo `index` chương (không theo vị trí mảng), xoá cùng tác vụ (`deleteTask`, `clearFinishedTasks`) — không thêm cột vào `DownloadTaskModel`. Truyện chữ (`executeTask`) và truyện tranh (`comicChaptersToDownload`) đọc qua `startPosition`; video ghi vào `VideoDownloadRequestStore` sẵn có.
- **Tốc độ tải** (`DownloadSpeedSettings`, mới, nhớ theo `packageId`): nghỉ 0–10 giây bước 0,5 (mặc định **Không** — trước đây không có nghỉ nào) và 1–3 luồng (mặc định **1**, tuần tự như cũ). Truyện chữ có cả hai; truyện tranh chỉ có nghỉ (giữa các chương vừa tải); video ẩn cả mục; nguồn Legado không có số luồng; ẩn khi xuất chỉ chương đã tải. Giới hạn 2 tác vụ chạy cùng lúc giữ nguyên.
- **Đường tải nhiều luồng** (`DownloadManager+ChapterLanes`, mới; vòng lặp chương rời khỏi `executeTask`): task group giữ tối đa N chương đang tải, mỗi luồng một `ExportContentProvider` + `BookDownloadWorker` riêng (không dùng chung `JSExecutor`); worker luồng thêm đăng ký vào `activeWorkers` (giờ là `[UUID: [BookDownloadWorker]]`) để `cancelTask` dừng hết. Kết quả xếp lại đúng thứ tự mục lục trước khi ghi bản xuất / báo tiến độ; chạy trước tối đa 2 × N chương. Luồng vừa tải từ mạng thì nghỉ trước chương kế tiếp của nó — chương đã có trong máy không phải chờ, không nghỉ thừa sau chương cuối. `ExportContentProvider` thành `@unchecked Sendable` (mỗi provider chỉ một luồng dùng), `Tally.add` cộng bộ đếm các luồng. Huỷ lúc các chương cuối còn đang tải vẫn báo "Đã hủy" (chốt `checkCancellation` sau vòng lặp). `BookBinManager.writeChapterContent` là hàm actor đồng bộ (tìm cuối file + ghi không có `await` xen giữa) nên các luồng ghi chung file `.bin` không chồng offset. Mặc định 1 luồng, không nghỉ ⇒ cùng thứ tự thao tác cũ.
- **Nhập kho tiện ích** (`AddRepositoryView`): nửa màn; mỗi ô có nhãn ở trên kèm `TextFieldClipboardButtons` (xoá · sao chép · dán thay cả giá trị).
- **Nhập nguồn Legado từ URL**: alert thành `LegadoURLImportSheet` (mới) — nửa màn, ô URL có nút xoá · sao chép · dán, giải thích trong nút "?". Bấm "Nhập" chỉ đặt cờ `isURLImportPending`; việc nhập chạy ở `onDismiss` của sheet để alert tổng kết không trình bày chồng lúc sheet đang đóng.
- `CLAUDE.md` / `AGENTS.md`: câu "đúng một `BookDownloadWorker` mỗi truyện" sửa thành mặc định một worker, nhiều luồng thì mỗi luồng một worker.
- Rủi ro chưa kiểm trên máy: nguồn chặn khi chạy 2–3 luồng; popover "?" trong header của sheet nửa màn; `.task` bị huỷ khi đẩy màn chọn chương (đã chặn bằng cờ nạp lại); tốc độ dịch tên chương với truyện vài nghìn chương.
- Chuyển entry `[1.3.594]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.623] - 2026-10-28

### fix: ngăn kéo menu trong hơn, trượt vào ra nhanh hơn

Người dùng: *"Menu bạn làm chưa có độ trong suốt, cho hoạt ảnh trượt vào trượt ra nhanh hơn tí"*, rồi *"84% mà tôi không hề thấy trong suốt tí nào"*.

- **Nguyên nhân** (`SideDrawerMenuPanel.drawerBackground`, 1.3.622): lớp tối `Color(white: 0.08).opacity(0.84)` nằm **trên** lớp `.ultraThinMaterial`, nên chỉ ~16% nền mờ lọt qua — nhìn như nền đặc, đậm hơn hẳn mockup đã duyệt.
- **Sửa**: lớp tối còn `Color(white: 0.12).opacity(0.55)`; chữ trắng vẫn đọc rõ nhờ lớp mờ của material. Lớp phủ phần màn còn lại giữ 30%.
- **Hoạt ảnh**: trượt vào 0,26 → 0,18 s, trượt ra 0,2 → 0,14 s.
- Chuyển entry `[1.3.593]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy — mức 55% cần người dùng xem lại trên máy.

## [1.3.622] - 2026-10-28

### feat: menu ba chấm thành ngăn kéo kính mờ, lưu tên AI tự gộp khi không trùng

Người dùng: *"tôi muốn sửa tất cả menu dropdown thành dạng chạy từ bên phải qua"*; chọn kiểu ngăn kéo cao toàn màn, phạm vi *"menu ba chấm và menu ở khám phá cạnh nút search"*, mục bật/tắt là công tắc, *"đừng trong suốt quá, phải nhìn rõ chữ, chữ cố gắng đừng xuống hàng"*, *"bỏ dấu x trên menu đi, bấm ra ngoài menu tắt là được"*; duyệt mockup. Thêm: *"khi bấm lưu ở danh sách name của AI, nếu toàn là từ không có trong danh sách thì không cần hiển thị menu hỏi gộp hay thay thế, luôn chọn gộp"*.

- **Component ngăn kéo** (`Views/Common/SideDrawerMenu/`, 12 file mới): `.sideDrawerMenu(isPresented:title:)`, biến thể `item:` cho menu theo từng hàng danh sách, `SideDrawerMenuButton` cho hàng của view chỉ là một `Section`. Hàng: `SideDrawerActionRow` (đóng ngăn kéo **trước**, action chạy trong `onDismiss` của cover sau một nhịp runloop — sheet/alert/bộ chọn tệp/điều hướng không bị hụt; `role: .destructive` đỏ; `.disabled` tự mờ), `SideDrawerToggleRow` (đổi ngay, ngăn kéo vẫn mở, công tắc `SwitchToggleStyle(tint: Color(white: 0.35))` như cả app), `SideDrawerOptionRow` (hàng chọn có dấu tích), `SideDrawerSectionHeader`, `SideDrawerDivider`.
- **Hình thức**: `fullScreenCover` nền `.clear`, tắt hiệu ứng mặc định, tự trượt vào từ phải; rộng 78% (tối đa 360pt), bo góc trái 16, viền trái trắng 14%; nền `.ultraThinMaterial` chồng lớp tối 84%, ép tông tối để chữ trắng đọc rõ; phần còn lại phủ đen 30%. Đóng bằng chạm ra ngoài hoặc vuốt sang phải — **không** có nút ✕. Chữ một dòng (co tới 80%), hàng cao ≥ 46pt.
- **Ngăn kéo gắn ở thân màn, không trong `ToolbarItem`** (tránh bug màn trắng 1.3.281); nút "…" giữ nguyên hình/cỡ, chỉ đổi từ `Menu` sang `Button`.
- **Các màn đã đổi** (giữ nguyên mục, thứ tự, điều kiện, disabled, destructive): Kệ ("Tuỳ chọn Kệ": nhóm Hiển thị có công tắc **Dịch nghĩa** và **Nội dung NSFW**, nhóm Thao tác), Chi tiết truyện (tiêu đề = tên truyện), Từ điển, Kho tiện ích (tab Tất cả tiện ích — gồm mục **Kiểm tra tiện ích đang hiện** của 1.3.621 — và tab Legado), Trợ lý AI, Reader, Công cụ tra cứu, Lọc rác, Rule nhanh, Quy tắc TOC, TTS thay thế, từ điển TTS (menu con "Xuất từ điển" thành nhóm 3 hàng), VieNeu phiên âm, thư viện giọng VieNeu (menu theo hàng), Sao lưu máy và Google Drive (menu theo hàng), Bộ sưu tập, Thông báo, trình phát video (Khung hình / Server / Chất lượng thành nhóm hàng chọn; menu tốc độ, khung hình, server lúc nằm ngang vẫn là `Menu`), menu nguồn cạnh nút tìm của Khám phá ("Dịch văn bản" có chữ phụ Đang bật/Đang tắt, popover dịch mở sau khi ngăn kéo đóng). "Sắp xếp lại" và "Bật/Tắt tất cả" của Legado giữ là hàng thao tác (chế độ/thao tác hàng loạt, không phải một cờ). Không đổi: menu Lưu trong sheet, `Picker`, `contextMenu`.
- **Lưu tên AI** (`ReaderAINameReviewSheet.requestSave`): không từ đang chọn nào có sẵn trong **từ điển đích** (`hasInBookNames` / `hasInBookVP`) ⇒ gộp luôn, không hỏi; có ít nhất một từ trùng mới hiện hộp Gộp / Thay thế hoàn toàn.
- Rủi ro chưa kiểm trên máy: cover có thật trong suốt với `.presentationBackground(.clear)`; khung hình đầu của hiệu ứng trượt; thanh trạng thái có thể hiện lại ở Reader/video khi ngăn kéo mở; xoay máy khi ngăn kéo mở ở trình phát; bàn phím của ô tìm đang focus đè lên ngăn kéo.
- Chuyển entry `[1.3.592]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code (component + từng màn); `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.621] - 2026-10-28

### feat: bộ kiểm tra tiện ích JS chạy đủ script khai trong plugin.json

Người dùng: *"Thêm bộ kiểm tra nguồn tương tự legado cho các ext. Nó phải kiểm tra đủ script khai báo trong plugin.json"*. Duyệt plan + mockup: kiểm từng tiện ích và hàng loạt (3 tiện ích cùng lúc), từ khoá tìm lấy 3 từ gần nhất trong lịch sử tìm kiếm rồi tên truyện của trang chủ, TTS chỉ chạy `voice`, có nhãn "lỗi do ai", chia sẻ báo cáo và gỡ tiện ích lỗi.

- **Một dòng kết quả cho mỗi khoá script** (khác bộ kiểm Legado dừng ở bước hỏng đầu): lỗi một nhánh không dừng nhánh khác. `ExtensionCheckReport` (mới, `Services/Extensions/Diagnostics/`) — đạt / lỗi / bỏ qua (kèm lý do) / chỉ kiểm tĩnh, thời gian, số mục, kết luận, câu lỗi đã redact; `errorLink` không vào JSON.
- **Tầng tĩnh cho mọi khoá khai báo** (`ExtensionScriptStaticCheck`): tên file hợp lệ, file có ở gốc hoặc `src/` (thứ tự như `getScriptPath`), đọc được UTF-8, đúng cú pháp bằng `JSCheckScriptSyntax` (chỉ phân tích, không chạy code top-level), có `execute`, mọi `load("x")` chữ cố định trỏ tới file có thật. Khoá app không gọi (`config`, `action`, `language`, `model`, `style`, `translate`, `chatStream`, khoá lạ, `track` của tiện ích không phải video, `tts`) chỉ kiểm tĩnh.
- **Chạy thật** (`ExtensionCheckProbe` + `+Entries` + `+Book`, qua `SourceRuntime` / `ExtensionManager` như app): `home` → `explore` → `genre` → `search` độc lập (`home`/`genre` chạy thêm script phụ của mục đầu thành dòng con); truyện thử ưu tiên mục của `search`, rồi `detail`, `page` → `toc` (trang đầu, như `BookDetailLoader.fetchFirstPageTOC`) → `chap` (chữ; tranh: danh sách ảnh + tải ảnh đầu qua `ComicImageLoader`; video: server) → `track` (tải thử 1 KB đầu nguồn `native`). Bước trước không cho dữ liệu ⇒ bước sau "bỏ qua". Trần thời gian mỗi bước dùng lại `LegadoCorpusDeadline`, phân loại lỗi dùng lại `LegadoCorpusErrorClassifier`.
- **Kết luận "lỗi do ai"** (`ExtensionCheckVerdict`, heuristic): captcha/Cloudflare/đăng nhập/HTTP 401 ⇒ cần người dùng; mạng/hết giờ/HTTP/có `fetch` lỗi ⇒ web; trả rỗng ⇒ nguồn lỗi thời; thiếu file/cú pháp/ngoại lệ JS ⇒ lỗi script; còn lại ⇒ chưa rõ. Mỗi dòng lỗi có "Mở link lỗi" (`SourceErrorLink.resolve` ngay trong `catch`); đóng trình duyệt ⇒ chạy lại tiện ích đó.
- **`ExtensionCheckRunner`** (actor): một lượt tại một thời điểm, cửa sổ trượt 3 tiện ích, trong một tiện ích chạy lần lượt; `retry(packageId:)` chạy lại một tiện ích, giữ kết quả các tiện ích khác. Không ghi đĩa, không đụng thư viện. `ExtensionCheckReportShare` ghi JSON vào `tmp/extension_check_share/`.
- **Màn** (`Views/Extensions/Check/`): `ExtensionCheckView` — một tiện ích (nút **Kiểm tra** mới ở thẻ đầu Cấu hình tiện ích, đẩy trong stack) hoặc hàng loạt (menu `⋯` tab Tất cả tiện ích › "Kiểm tra tiện ích (theo danh sách đang hiện)", chỉ tiện ích đã cài): ô Đạt đủ / Có lỗi / Còn lại, chip lọc, chạm dòng ⇒ `ExtensionCheckResultScreen`; nút Dừng, Chạy lại, Gỡ tiện ích lỗi (hỏi xác nhận), chia sẻ. Dòng "bỏ qua" không tính là lỗi khi gỡ. Rời màn / đóng sheet ⇒ dừng lượt.
- Loại tiện ích của bộ kiểm lấy theo `type` của bản ghi đã cài (cùng cách `BookContentDestination` chọn màn đọc); nút Kiểm tra không hiện với nguồn Legado; "Gỡ tiện ích lỗi" bỏ qua tiện ích đang làm giọng đọc TTS (cùng luật nút Gỡ ở Cấu hình tiện ích).
- Menu `⋯` của tab 0 chuyển sang `RepositoryManagerView+SourceCheck` để file legacy `RepositoryManagerView.swift` giảm (605 → 591 dòng).
- Chuyển entry `[1.3.591]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch. **Chưa thử trên máy**: `JSCheckScriptSyntax` với các tiện ích thật, tiện ích có trang chặn Cloudflare (bước có thể chậm), kiểm hàng loạt nhiều tiện ích.

## [1.3.620] - 2026-10-28

### fix: danh sách thay thế TTS chung không còn trống dù đã có rule

Người dùng: *"điều tra thử màn hình danh sách thay thế tts chung bị gì xem không thấy phần tử nào dù nó có"*; duyệt cách sửa.

- **Nguyên nhân**: từ lần tách thay thế TTS thành hai tầng (`4c76df00`, 2026-09-30), `TTSReplacementManagerView.currentRules` đọc qua `TTSReplacementManager.rules(bookId:)` cho **cả hai** tầng. Hàm đó chỉ dành cho tầng riêng và trả `[]` khi `bookId == nil` (`mergedRules` cần đúng hành vi này), nên màn chung luôn hiện "Chưa có quy tắc thay thế nào".
- **Sửa** (`TTSReplacementManagerView+Layer`): tầng chung đọc thẳng `manager.rules`, tầng riêng giữ `rules(bookId:)`. Hàm của manager không đổi.
- Dữ liệu không mất: thêm/sửa/xoá/sắp xếp/nhập file vẫn ghi đúng tầng chung, và TTS vẫn áp rule chung lúc đọc — chỉ màn hình không hiện.
- Chuyển entry `[1.3.590]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.619] - 2026-10-28

### feat: chip nghĩa cho sheet Sửa từ, badge góc chip, NSFW ở menu Kệ

Người dùng: *"sửa sheet sửa từ và thêm từ của vp/name hiển thị giữa màn hình. Hiển thị thanh chip nghĩa như màn hình dịch cho sheet sửa từ giúp tôi. Ngoài ra giúp tôi sửa vị trí badge cho sheet thêm phiên âm, thêm thay thế tts giống màn hình dịch"*, duyệt mockup, rồi thêm *"thêm bật tắt nfsw vào dropdown của tab kệ sách"*.

- **Thanh chip nghĩa dùng chung** (`Views/Common/MeaningSuggestionChipRow`, mới): tách nguyên khối chip của panel Dịch (viền theo nguồn, badge R/C góc trên phải, nhãn trợ năng) ra view riêng; `ReaderDefinitionOverlayView` gọi lại view đó, giao diện panel Dịch không đổi. Nút chip đặt `.buttonStyle(.plain)` để đặt được trong `Form` (nút mặc định trong một hàng `Form` làm cả hàng bấm được).
- **Badge góc chip** (`Views/Common/ChipCornerBadge`, mới): capsule 15pt nhô ra trên/phải 6pt, có `init(scope:)` cho R/C cùng màu ở mọi nơi.
- **Sheet Sửa từ / Thêm từ mới của VP và Names** (`DictEntrySheet`): mở nửa màn, vuốt lên được toàn màn (như sheet phiên âm và thay thế TTS). Chế độ sửa có thanh chip nghĩa ngay dưới ô nghĩa — cùng nguồn và thứ tự với panel Dịch (`ReaderView.buildSuggestionChips`); bấm chip điền nghĩa, đổi từ gốc thì chip tính lại. Chip "(Riêng)" lấy theo truyện: từ điển riêng ⇒ truyện đó, từ điển chung ⇒ truyện đang mở màn Từ điển (`contextBookId`).
- `ReaderView.dictionaryMatches(for:bookId:)` và `buildSuggestionChips(for:bookId:)` nhận `bookId: String?`; `nil` bỏ hai nguồn "(Riêng)" thay vì nạp từ điển của truyện rỗng vào bộ nhớ đệm 3 truyện.
- **Sheet thêm phiên âm** (`AddWordSheet`): badge NGI/VIE/JP/EN chuyển từ trong chip lên góc trên phải (nền trắng, chữ đen); nhấn giữ để xoá và viền chip gợi ý chính giữ nguyên.
- **Sheet thêm thay thế TTS** (`AddTTSReplacementSheet`): badge R/C lên góc trên phải, đổi sang màu của panel Dịch (R đỏ, C xám đậm) thay cho xanh ngọc/xanh dương; chip của rule đang tắt vẫn mờ.
- **Menu ba chấm của tab Kệ**: thêm "Hiện nội dung NSFW" / "Ẩn nội dung NSFW" ngay dưới mục Dịch nghĩa — công tắc NSFW toàn app, chung khoá với Cài đặt và nút NSFW của Khám phá.
- Chuyển entry `[1.3.589]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.618] - 2026-10-27

### fix: rule <vp> tách rời chữ có dấu thành từng mảnh

Người dùng: *"五绝级别 / <vp>级别 / -> Ng ũ tuy ệ t cấp bậc / fix lỗi này"*; duyệt plan.

- **Nguyên nhân**: nghĩa từ điển của 五绝 lưu dạng dấu rời (NFD: "u" + U+0303 thay vì "ũ"). Rule ghép nghĩa vào dòng, rồi dòng được tách token lại bằng `VietPhraseTokenizer`; `isLatinLetterOrNumber` chỉ nhận ký tự đúng **một** scalar, nên chữ có dấu rời rơi xuống nhánh dấu câu và bị chèn dấu cách hai bên.
- **`QuickTranslationCompiledRule.render(captures:)`**: kết quả chuẩn hoá NFC (`precomposedStringWithCanonicalMapping`) — áp cho mọi token `<vp>`, `<ne>`, `<pn>`, `<w>` lẫn chữ gõ trong rule; màn chẩn đoán và thử rule thấy cùng chuỗi.
- **`VietPhraseTokenizer.isLatinLetterOrNumber`**: nhận thêm chữ Latin kèm dấu thuộc khối Combining Diacritical Marks (U+0300–U+036F), vẫn xét theo chữ gốc như cũ; chữ số kèm dấu và emoji nhiều scalar vẫn không phải chữ. Hàm dùng chung với `TranslateUtils.translateAuthorHanViet`, nên tên tác giả có chữ dấu rời cũng không còn bị tách.
- Dữ liệu từ điển trên máy không đổi.
- Chuyển entry `[1.3.588]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.616] - 2026-10-27

### fix: giảm đệm trái phải ba sheet bôi đen, sheet thêm rule mở toàn màn

Người dùng: *"giảm padding của các màn hình dịch, xóa từ rác, copy gốc / bỏ nấc hiển thị giữa màn hình của sheet thêm rule"*, rồi chốt *"giảm padding trái phải thôi"*.

- **Ba sheet bôi đen** (Dịch `ReaderDefinitionOverlayView`, Xoá từ rác `ReaderJunkDeleteOverlayView`, Copy gốc `ReaderCopyOriginalOverlayView`): đệm ngang 16 → 12; đệm trên, dưới và khoảng giãn giữa các hàng giữ nguyên.
- **Sheet thêm/sửa rule** (`QuickTranslationRuleEditorSheet`): bỏ nấc nửa màn của 1.3.613 (`presentationDetents([.medium, .large], selection:)`, state `detent`, tự kéo lên khi chạm ô nhập) — sheet mở toàn màn như trước.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.617] - 2026-10-27

### fix: một provider Chế độ AI chứa nhiều tài khoản Google, xoay vòng trong provider

Người dùng sau `[1.3.615]`: *"bạn đang làm mỗi tài khoản thành 1 provider rồi, tôi muốn là 1 provider gồm nhiều tài khoản xoay tua mà"*. Plan: `Docs/Plans/2026-10-27-plan-google-ai-mode-accounts-in-provider.md`.

- **Mô hình đúng**: `GoogleAccount` (`id`, `profileId`, `label`, `order`, cookie, `sessionFingerprint`) sống **trong** một provider `googleAIMode`; `GoogleAccountStore` giữ một item Keychain **mỗi tài khoản** (khoá `accountId`), thứ tự xoay = `order`. Danh sách profile trong Cấu hình AI trở lại "mỗi provider một dòng".
- **Bỏ mô hình sai của 1.3.615**: xoá `GoogleAccountSnapshot`/`GoogleAccountSnapshotStore` (khoá theo `profileId`), xoá `AIConfiguration.moveGoogleAIModeProfiles` (đổi thứ tự xoay không còn là hoán vị profile).
- **Xoay trong provider**: `GoogleAccountRotation.rotateToNextAccount() -> GoogleAccount?` vòng tròn theo `order` trong provider đang dùng, `limitedAccountIds` thay `limitedProfileIds`; **không** còn `AISettingsStore.setActiveProfile` ⇒ Cài đặt không tự nhảy provider. Fallback giữ nguyên: hết tài khoản → Gemini Web → chờ 1→2→4→8 phút.
- **Quét tên + chat Reader**: tráo `apply(account:)` rồi gửi lại đúng lượt; chat vẫn xoá `mstk` của phiên để mở cuộc chat mới, chỉ tráo khi chưa phát chữ nào.
- **Màn Tài khoản Google**: liệt kê tài khoản **của provider đang chọn** (kèm dòng "Provider: …"), chạm một dòng = tráo phiên sang tài khoản đó, kéo ≡ đổi thứ tự xoay, swipe **Đổi tên** / **Xoá**, "+ Thêm tài khoản Google" hỏi tên rồi đăng nhập (không sinh profile mới); huỷ giữa chừng thì khôi phục phiên cũ.
- **Đăng xuất / xoá**: `signOut` xoá mọi tài khoản cùng phiên (khớp `sessionFingerprint`) ở mọi provider; xoá provider Chế độ AI xoá toàn bộ tài khoản của nó.
- **Di trú (một lần, `FreeBook_GoogleAccountModel_V2`)**: item Keychain kiểu 1.3.615 (khoá `profileId`) → tài khoản của provider đang chọn, nhãn = tên profile cũ, xoá item cũ sau khi ghi; profile thừa **không** bị xoá. Chưa có tài khoản nào mà kho đang đăng nhập ⇒ thêm "Tài khoản 1".
- **Kiểm chứng**: `check_architecture.py` **2 violation nền, 0 mới**. Không build tại chỗ (Windows, không có xcodegen) — CI là cổng biên dịch; **chưa thử trên máy** (cần 2 tài khoản Google thật để thử tráo phiên).

## [1.3.615] - 2026-10-27

### feat: tự xoay tài khoản Google cho Chế độ AI khi bị giới hạn

Người dùng (qua `/grill-me`, 7 câu, mockup B duyệt trong chat): *"giúp tôi làm chức năng tự chuyển profile của provider chế độ AI của google"* → chốt **xoay vòng nhiều tài khoản Google** (đảo ngược quyết định `[1.3.612]` "không đổi cookie/tài khoản"), mỗi profile Chế độ AI là một tài khoản, snapshot phiên trong Keychain, tráo vào kho cookie mặc định, ghi vào Cài đặt, áp dụng cả quét tên lẫn chat Reader. Plan: `Docs/Plans/2026-10-27-plan-google-ai-mode-account-rotation.md`.

- **Vì sao tráo cookie chứ không tách kho**: iOS chỉ có `WKWebsiteDataStore.default()` và `.nonPersistent()` (`forIdentifier:` là API macOS) ⇒ mọi provider Google của app dùng chung một kho; "đổi tài khoản" = thay toàn bộ cookie `*.google.com`. Hệ quả đã chấp nhận: cả app (Chế độ AI, Gemini Web, trình duyệt bypass, captcha) cùng lúc chỉ ở một tài khoản.
- **Mới `Sources/Services/AI/GoogleAccounts/`**: `GoogleAccountSnapshot` (cookie + `sessionFingerprint` băm `__Secure-1PSID`, không đọc email), `GoogleAccountSnapshotStore` (Keychain, một item/profile, `AfterFirstUnlockThisDeviceOnly`), `GoogleSessionSwitcher` (`@MainActor`: capture/apply/restore/adopt/migrate; **bắt buộc** giải phóng WKWebView ẩn + `refreshAfterLogin` trước khi tráo, và kiểm `isSignedIn()` sau khi tráo — sai thì khôi phục phiên cũ), `GoogleAccountRotation` (thay `AINameScanProviderSwitch`: xoay tài khoản Chế độ AI theo thứ tự → Gemini Web → chờ nấc 1→2→4→8 phút).
- **Quét tên** (`AINameExtractionBatchProcessor+RateLimit`): bị giới hạn ⇒ `rotateToNextAccount()` → `apply(profile:)` → ghi `activeProfileId` → `clearRateLimitBlock()` (hạn chờ 60 s của tài khoản cũ không còn nghĩa) → gửi lại đúng lượt đó; hết tài khoản mới rơi về Gemini Web rồi mới chờ.
- **Chat Reader** (mới `AIRuntimeCoordinator+AccountRotation.swift`): lượt bị giới hạn **khi chưa phát chữ nào** ⇒ tráo tài khoản, xoá `mstk` của phiên (`GoogleAIModeConversationStore.delete`) để mở cuộc chat mới với đủ ngữ cảnh, chạy lại đúng lượt đó. Đang có chữ thì không tráo — câu trả lời sẽ đứt rồi viết lại.
- **Snapshot tự tươi**: sau **mỗi lượt thành công** `GoogleAIModeClient.runTurn` dump lại snapshot của profile đang dùng — `__Secure-1PSIDTS` bị Google xoay liên tục, snapshot cũ sẽ chết.
- **UI (mockup B)**: màn mới `GoogleAccountsView` + `+Actions` — mỗi dòng một tài khoản, chip "Đang dùng", dòng cam "Chưa gắn phiên — bấm để đăng nhập", kéo ≡ đổi thứ tự xoay vòng (`AIConfiguration.moveGoogleAIModeProfiles` chỉ hoán vị các profile Chế độ AI), nút "+ Thêm tài khoản Google" (adopt phiên đang có → backup cookie → xoá → đăng nhập → lưu; **huỷ thì khôi phục phiên cũ**). Hàng dẫn vào trong Cấu hình AI; `GoogleAIModeAccountRow` giờ nhận `profile` và dẫn sang màn này khi đã gắn phiên.
- **Đăng xuất / xoá**: `GeminiWebSessionController.signOut` xoá snapshot của **đúng tài khoản** vừa đăng xuất (mọi profile giữ nó), giữ các tài khoản khác; xoá profile Chế độ AI xoá snapshot của nó. Nâng cấp từ 1.3.613: phiên Google sẵn có tự gắn vào profile Chế độ AI đang chọn (cờ `FreeBook_GoogleAccountMigration_V1`, một lần).
- **Khác plan một điểm**: bỏ field `googleAccountLabel` dự kiến thêm vào `AIProviderProfile` — tên tài khoản chính là tên profile (đã sửa được sẵn trong Cấu hình AI), thêm field nữa chỉ tạo dữ liệu trùng. Không đổi `Codable` của profile.
- **Rủi ro đã biết**: Google có thể vô hiệu phiên khi tráo (nhất là `__Secure-1PSIDTS`) ⇒ `apply` kiểm `isSignedIn()` rồi khôi phục; cùng thiết bị nhảy tài khoản nhanh có thể bị gắn cờ/captcha nặng hơn — đánh đổi đã được người dùng chấp nhận, không thêm gì để "giấu" (không đổi UA/IP).
- **Kiểm chứng**: đọc code; `check_architecture.py` **2 violation nền, 0 mới** (JSDom 580/555, TTSManager 3500/3470). Không build tại chỗ (Windows, không có xcodegen) — CI là cổng biên dịch; **chưa thử trên máy** (chưa có 2 tài khoản Google thật để thử tráo phiên).

## [1.3.614] - 2026-10-27

### feat: nút mở link lỗi ở các màn báo lỗi, ghim NE/VP R/C kiểu bìa Kệ

Người dùng (qua `/grill-me`, mockup duyệt trong chat, plan `Docs/Plans/2026-10-27-plan-mo-link-loi.md` duyệt): *"thêm nút mở link lỗi cho những chỗ báo lỗi trên màn hình chi tiết, reader, khám phá, thể loại, ..."*; chốt: mục đích **giải chặn rồi thử lại**, mở **URL fetch lỗi thật** (rồi fetch gần nhất, rồi URL đầu vào), thêm Comic + Video, Tìm kiếm một nguồn, Gợi ý / Bình luận (không Tải truyện), mở bằng `BypassWebView`. Kèm: *"sửa lại icon ghim ở VP/NE R/C của màn hình dịch giống cover ở kệ sách"* — góc trên phải, nghiêng 20°.

- **Mang URL lên màn hình**: `JSExecutor+FetchTrace` ghi URL fetch lỗi / fetch gần nhất của lượt chạy (sau fallback browser ẩn; tên miền chặn sẵn không ghi; xoá ở `beginExecution()` nên executor dùng lại không rò). `ExtensionLoadError` bọc lỗi của 10 hàm chạy script trong `ExtensionManager` (`+Explore`, `+Media`) — chữ lỗi giữ nguyên, không bọc `CancellationError`, không in URL khi nội suy; `unwrapped(_:)` bóc lớp. `SourceErrorLink.resolve(from:fallback(s):host:)` chọn link: fetch lỗi → fetch gần nhất → URL lỗi Legado → URL đầu vào (http(s), `//`, `/` theo host; mẫu `{0}`/từ khoá bị loại ⇒ ẩn nút).
- **UI chung** (`Sources/Views/Common/ErrorLink/`): `ErrorLinkButton` (capsule / viền / icon), `ErrorLinkCaption` (dòng URL xám host+path), `.errorLinkBrowser(link:packageId:onRetry:)` mở `BypassWebView(forcesMobileUserAgent: true)` (UA điện thoại như `fetch`, công tắc máy tính khoá) — đóng ⇒ `WebKitCookieBridge` chép cookie WebKit của tên miền sang `HTTPCookieStorage.shared` và `LegadoCookieJar` (nguồn Legado) ⇒ toast "Đang thử lại…" ⇒ thử lại đúng hành động của màn. Màn bên dưới không tự tải lại khi hiện lại sau trình duyệt.
- **Màn có nút**: Chi tiết (lỗi chi tiết toàn màn + header, mục lục chữ chưa/đã có chương — nút tròn la bàn, mục lục video, Gợi ý, Bình luận, Tất cả bình luận); Reader chữ (URL **chương đích** bị lỗi — sửa luôn chỗ "Mở bằng trình duyệt" mở nhầm chương cũ); Khám phá (danh mục hiện **lỗi thật** thay "Extension thiếu home và genres" khi script có khai mà lỗi, thêm Thử lại; tab home; section explore; tab Legado); Thể loại / Xem thêm (`PaginatedNovelLoader.errorLink`); Comic; Video (server rỗng / link phát / phát lỗi / trang nhúng); Tìm kiếm một nguồn (lỗi tìm + lỗi đổi nguồn, trừ lỗi khác loại nội dung). Không gắn: tab Tải, Tìm mọi nguồn, lỗi chỉ toast, lỗi không do nguồn.
- **Ghim NE/VP R/C**: `CoverPinBadge` thêm `angle` / nhãn trợ năng (Kệ giữ 35°); `dictSegmentButton` bỏ ghim trắng trước chữ, đặt ghim cam ở góc trên phải nút, 20°, đường kính 15; nhóm nút đổi `.cornerRadius` sang nền bo góc để ghim không bị cắt.
- CLAUDE.md + AGENTS.md: đoạn "Nút Mở link lỗi" (cách nối cho màn lỗi mới). Chuyển entry `[1.3.584]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Giới hạn đã biết**: chép cookie có thể chưa đủ để URLSession qua Cloudflare (vân tay kết nối khác Safari) — fallback browser ẩn vẫn dùng cookie WebKit; nguồn Legado gửi UA Chrome Android khác UA iPhone của trình duyệt nên clearance gắn UA có thể không dùng lại được; fetch chạy lúc nạp script không có dấu vết ⇒ rơi về URL đầu vào.
- **Kiểm chứng**: đọc code; hai agent review phản biện (service + UI) không thấy lỗi biên dịch, đã sửa các bug hành vi nêu ra. `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; **chưa thử trên máy** (nhất là `fullScreenCover` có làm màn bên dưới chạy lại `onAppear` hay không, 3 cover nối nhau ở màn Chi tiết, và nguồn Cloudflare thật).

## [1.3.613] - 2026-10-27

### feat: fetch lỗi thử lại bằng browser ẩn, mục lục comic như truyện chữ, badge R/C, hỏi lại bỏ kệ

Người dùng (qua `/grill-me`, 10 mục, mockup duyệt trong chat, *"làm luôn không cần plan"*): badge riêng/chung cho chip nghĩa màn Dịch; *"fetch nếu không fetch được thì tự mở bằng browser (nếu browser cũng lỗi thì hiển thị lỗi fetch)"* + *"log kiểu lỗi 403, đang thử mở browser ẩn…"* + *"cả 2 lỗi thì hiển thị lỗi của cả 2"*; hỏi lại khi xoá khỏi kệ ở sheet nhấn giữ; vuốt âm lượng bỏ tắt tiếng video; Hub từ điển Names trên VietPhrase, bớt giải thích; màn thêm rule có dấu hỏi, nửa màn, nút Lưu như "Thêm từ mới"; dòng tắt tiếng sang màn Nội dung nhạy cảm; mục lục comic giống truyện chữ; cuối chương comic bỏ nút, vuốt ngang chuyển chương.

- **`fetch` lỗi ⇒ browser ẩn** (`JSExecutor+FetchBrowserFallback`, `HiddenBrowserFetch`, `HiddenBrowserFetchScripts`, `WebViewLoader+NavigationResponse`, mới): chỉ khi lỗi mạng / hết giờ / HTTP 403, 429, 503; GET không body, URL http(s); không phải domain bị chặn, không huỷ; executor cho phép (`allowsFetchBrowserFallback`, tắt ở `ExtTTSRuntime` và `ComicImageScriptRunner`); không ở main thread (semaphore + main queue ⇒ deadlock, bỏ qua kèm log) và app không ở nền (WebKit tạm dừng WebContent). Luôn bật, không có cài đặt.
  - Browser ẩn mới mỗi lượt, gắn cửa sổ ẩn, tối đa 3 cái cùng lúc (chờ suất ≤ 3 s), hạn 15 s. Dò DOM mỗi 0,5 s: chờ qua trang chặn Cloudflare (`_cf_chl_opt`, `cf-chl`, `#challenge-form`, title "Just a moment"…) và trang chờ; `WebViewLoader` giờ giữ lỗi điều hướng (`didFail*`) và status/MIME trang chính của lần điều hướng **mới nhất** (`decidePolicyFor navigationResponse`, mô phỏng mặc định WebKit). Thất bại khi: lỗi điều hướng, status ≥ 400, nội dung nhị phân, vẫn trang chặn / trống / hết giờ.
  - Thành công ⇒ 200 + nội dung (HTML lấy `outerHTML`; JSON/text — kể cả bị gắn nhãn HTML — lấy text), `raw` mã hoá theo `characterSet` (họ GBK dùng GB18030). Cả hai lỗi ⇒ giữ response gốc, `statusText` = `"<gốc> | Browser ẩn: <lý do>"`.
  - Log: `❌ [JSFetch] HTTP 403 <host><path> — đang thử mở browser ẩn…`, `✅ … Browser ẩn tải được`, `❌ … Fetch lỗi (…) và browser ẩn cũng lỗi (…)`; không ghi query string. Console debug tiện ích thấy lượt "BROWSER".
  - Kèm: fetch hết giờ giờ trả đúng 408 "Request Timeout" (trước bị callback ghi đè thành 500).
- **Chip nghĩa màn Dịch**: badge `R`/`C` góc trên phải (`SuggestionChip.Scope`), chỉ nguồn Names/VietPhrase; nghĩa có ở bất kỳ nguồn Riêng ⇒ `R`. Phạm vi suy từ hậu tố nhãn "(Riêng)"/"(Chung)" của `dictionaryMatches` (đã chú thích hợp đồng ở `ReaderView+Selection`).
- **Bỏ kệ từ sheet nhấn giữ** (Kệ/Lịch sử, Tìm trên kệ, Bộ sưu tập) hỏi lại bằng đúng hộp của danh sách chương — tách `ShelfRemovalConfirmationModifier` (mới), `ShelfToggleFlowModifier` dùng lại. Hộp bật trong `onDismiss` của sheet nhấn giữ (`queuedShelfRemovalBook`) để không trình bày chồng lúc sheet đang đóng.
- **Video**: bắt đầu vuốt âm lượng (toàn màn) khi đang tắt tiếng ⇒ `setMuted(false)` (dừng TTS đang đọc như bật tiếng bằng nút). Nút âm lượng cứng không đụng; khung dọc không thêm cử chỉ (người dùng bỏ).
- **"Tắt tiếng khi mở phim"** chuyển từ Đọc & Nghe sang Cài đặt › Thư Viện › Nội dung nhạy cảm (section riêng sau công tắc).
- **Hub từ điển**: Names trên VietPhrase ở cả hai section; xoá hai footer giải thích.
- **Sheet thêm/sửa rule**: nút dấu hỏi ở header "Mẫu"/"Bản dịch" mở popover chứa giải thích cũ (`QuickTranslationRuleHelpButton`, mới; câu "Đổi mẫu sẽ thêm rule mới…" của chế độ sửa vào popover "Mẫu"); Lưu = `Menu` đúng hai mục "Lưu vào bộ riêng truyện" / "Lưu vào bộ chung" khi thêm và có truyện (bỏ `confirmationDialog`), còn lại nút thường; sheet mở nửa màn, chạm ô nhập tự lên toàn màn (khôi phục nháp giữa lúc gõ thì mở toàn màn).
- **Mục lục comic** (`ComicChapterListSheet` viết lại + `+Header`, mới): sheet 0.88/large có thanh kéo, bỏ tiêu đề + ✕; header bìa (số chương, chạm mở Chi tiết) / tên / tác giả / nhãn nguồn, nút kệ / tải ảnh offline / đảo thứ tự (giữ trong phiên, `ComicReaderView`); ô tìm; hàng kiểu `ReaderChapterRowView`; tìm hoặc giảm dần ⇒ ẩn dòng nhóm. Metadata thiếu `Book` thì lấy từ `launch`. Không làm: dịch lại tên chương, cập nhật mục lục, tải lẻ.
- **Màn đọc comic**: cuối chương bỏ nút "Chương tiếp", thay dòng "Vuốt sang trái để sang chương tiếp theo"; vuốt ngang mọi chỗ (`DragGesture` simultaneous, |dx| ≥ 80 pt và > 2·|dy|): trái ⇒ chương sau, phải ⇒ chương trước, hết chương thì toast; bỏ qua khi đang nạp / phóng to / mở mục lục.
- CLAUDE.md + AGENTS.md: đoạn fetch → browser ẩn, vị trí `VideoMutePolicy`, màn đọc comic. Chuyển entry `[1.3.583]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Giới hạn đã biết**: cookie `cf_clearance` nằm trong kho WebKit, không sang URLSession ⇒ mỗi fetch sau tới site đó lại 403 rồi mới vào browser (chưa nhớ host bị chặn); lỗi của điều hướng phụ có thể làm browser báo lỗi nhầm; executor dùng lại (`BookDownloadWorker`) bị huỷ thì browser của lượt cũ giữ suất tới hết hạn.
- **Kiểm chứng**: đọc code; hai agent review phản biện (service + UI) không thấy lỗi biên dịch/deadlock, đã sửa các bug hành vi nêu ra. `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; **chưa thử trên máy**, nhất là vuốt ngang trên `ScrollView` của comic (nếu `onEnded` không tới thì chuyển sang `UIPanGestureRecognizer`), popover trong header `Form`, và các dấu hiệu Cloudflare trên site thật.

## [1.3.612] - 2026-10-26

### fix: Chế độ AI hết phí hạn mức khi bị Google giới hạn, tự chuyển Gemini Web hoặc tự chờ

Người dùng: *"provider Chế độ AI của Goôgle dễ bị hạn chê số request quá, tìm cách fix"*; lúc bị chặn app báo "Chế độ AI của Google báo lỗi…", trang Google ghi *"Bạn hiện đã đạt đến giới hạn về số lượng yêu cầu đối với câu trả lời của AI. Hãy thử lại sau giây lát"*, xảy ra sau khi quét được một lúc. Chốt qua chất vấn: tự chờ rồi quét tiếp, giữ 2.500 chữ/lượt, **tự chuyển sang Gemini Web** (ngay khi bị giới hạn). Yêu cầu "lách" giới hạn (đổi cookie/IP/tài khoản, giả trình duyệt) — **không làm**, đã nói lý do. Plan duyệt trong chat.

- **Nguyên nhân**: 1.3.609 không nhận ra câu giới hạn; `generationFailed` được gửi lại ngay, lỗi không dừng quét, cuối lần quét còn tự thử lại một vòng ⇒ đang bị giới hạn vẫn gửi đều mỗi 5 s, giới hạn kéo dài.
- **Nhận ra giới hạn**: `GoogleAIModePageContract.rateLimitText` (trong lượt mới hoặc ngoài mọi khối lượt) ⇒ `GoogleAIModeError.rateLimited(retryAfter:)`; hạn chờ toàn cục 60 s trong `GoogleAIModeTurnQueue` (hai lượt liên tiếp "báo lỗi" ở chat hay quét cũng đặt hạn chờ này) — chat lẫn quét không gửi gì tới hạn đó, chat báo "thử lại sau m:ss"; log `❌` kèm ~160 ký tự quanh câu lỗi của trang. `generationFailed` thôi được gửi lại ngay; runner nền không gửi lại `rateLimited`.
- **Quét**: `AINameScanProviderSwitch` + `AINameExtractionBatchProcessor+RateLimit` — `rateLimited` hoặc 2 lượt `generationFailed` liên tiếp ⇒ có profile Gemini Web thì chuyển ngay, gửi lại đúng lượt đó, phần còn lại (cả vòng tự thử lại) chạy Gemini Web, toast một lần; không có thì chờ 1 → 2 → 4 → 8 phút rồi gửi lại, hết nấc ⇒ dừng (`rateLimitExhausted`) giữ tên + điểm tiếp nối. `runTurns` đọc provider mỗi lượt.
- **UI**: dải tiến độ trạng thái chờ (nền cam, đồng hồ cát, đếm ngược từng giây, "lần chờ i/4"), dòng phụ "Đã chuyển sang … (Chế độ AI bị giới hạn)"; tiêu đề tác vụ "Chờ Google m:ss · Batch N/T"; ghi chú ở `GoogleAIModeAccountRow`.
- **Tên ví dụ của prompt** (thử thật: Chế độ AI trả `何老三=Hà lão tam`, `李掌柜=…` dù văn bản không có): `droppingPromptExamples` bỏ tên trùng ví dụ `X=Y` của prompt mà không có trong văn bản đã gửi — mọi provider.
- `rules.md`: bullet "Giới hạn số câu trả lời AI" + "Tên ví dụ của prompt", sửa bullet retry. Chuyển entry `[1.3.582]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Chạy đúng script `snapshot` mới trên trang Chế độ AI thật (chèn câu giới hạn vào DOM, không gửi gì): trang thường ⇒ không báo; câu ngoài khối lượt ⇒ `limitedPage`; câu trong lượt cũ ⇒ không báo nhầm; câu trong lượt mới nhất ⇒ `limitedNewest`. Không build tại chỗ (Windows) — CI là cổng biên dịch; **chưa thử trên máy** (chưa gặp lại trang giới hạn thật để biết câu nằm đâu trên DOM — log `❌ 🤖 [AIMode]` ghi đoạn chữ lúc phát hiện).

## [1.3.611] - 2026-10-26

### fix: xoá name AI không quay lại qua lượt quét và nút Thử lại

Người dùng: *"Tôi đã yêu cầu nếu bấm xoá name trong danh sách name thì lần sau mở danh sách name này lại thì name bị xoá phải mất và trên chat cũng phải mất. Nhưng bạn chưa làm được"* (phạm vi: chỉ tin đang mở). Plan duyệt trong chat.

- **Nguyên nhân** (1.3.606 chỉ sửa `content` của tin): ba đường của lượt quét dựng lại `content` từ **danh sách tên đầy đủ** — `applyBatchProgress` mỗi lượt đang chạy, `writeNames` lúc xong / dừng vì lỗi, nút "Thử lại k lượt lỗi" (`NameScanRetryContext.names` giữ bản cũ) — nên name vừa xoá quay lại ở cả chat lẫn danh sách. Tin cũ còn `extractedNames` thì `condenseHistoricalMessages` dựng lại `content` từ mảng đó mỗi lần mở màn AI.
- **Sửa** (mới `AIRuntimeCoordinator+NameRemoval.swift`): coordinator nhớ khoá đã xoá **theo tin** (`removedNameKeys`, trong bộ nhớ suốt phiên app); `applyBatchProgress` / `writeNames` lọc qua `keepingUnremovedNames` trước khi ghi; `forgetName` sửa tin trong phiên đang chạy và bỏ name khỏi context "Thử lại" của đúng tin đó. `removeNameLine` gọi qua coordinator, bỏ name khỏi `extractedNames` của tin cũ, lọc `batchExtractedNames` của màn. Hàm tách dòng chuyển sang coordinator (`contentRemovingNameLines`, `nameKey`).
- **Log để chẩn đoán**: xoá được ⇒ log thường (khoá + số dòng bỏ); không thấy dòng nào trùng khoá hoặc tin nguồn không còn ⇒ log `❌` (ghi kể cả khi tắt log).
- Chuyển entry `[1.3.581]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.
