# CHANGELOG - Nhật ký Thay đổi CodeGraph Tàng Công Các

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **Tàng Công Các**.

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

## [1.3.826] - 2026-11-11

### feat: dịch ảnh truyện tranh raw bằng nhận chữ trên máy, phủ bản dịch lên bong bóng

Anh Bửu chọn ý "dịch ảnh truyện tranh raw ngay trên ảnh" trong năm ý tưởng chức năng mới, duyệt plan, công tắc nhớ **theo tiện ích**.

- Nút **Dịch ảnh** (`character.bubble`, bật ⇒ `.fill` trên nền trắng 18%) ở thanh trên màn đọc truyện tranh, ngay trái ☰; bấm ⇒ toast "Đã bật dịch ảnh cho nguồn này" / "Đã tắt dịch ảnh". Nhớ theo tiện ích (`ComicImageTranslationPolicy`, khoá `comicImageTranslate_<packageId>`, mặc định tắt) ⇒ Đổi nguồn / xoá truyện không phải chép hay dọn gì; độc lập công tắc dịch tên chương. Neo `.mediaDiscAnchor(.headerTrailing)` dời từ ☰ sang nút mới (nút trái nhất của cụm phải), kẻo đĩa nghe vào header đè lên nó. Trạng thái giữ ở `ComicReaderView`, không ở `ComicReaderViewModel` (397 dòng).
- `Services/Comic/ImageText/` (mới): `ComicTextRecognizer` (actor; Vision `VNRecognizeTextRequest` accurate, `zh-Hans`/`zh-Hant`, `minimumTextHeight` đặt tường minh; ảnh dài cắt lát cao ≤ 1,5× bề ngang chồng 12%, dòng chỉ giữ ở lát có tâm dòng trong "lõi" ⇒ không trùng; mỗi lúc một ảnh, hàng rời màn ⇒ rời hàng chờ / `cancel()` request; log một lần ngôn ngữ Vision có trên máy) → `ComicTextBlockGrouper` (gom dòng cùng bong bóng: cao gần bằng, khe dọc ≤ 0,8 dòng, chồng ngang ≥ 30%; ghép chữ Hán liền; đo nền tối/sáng trên 8×8 điểm) → `ComicPageTextRepository` (RAM → `Caches/comic_ocr/` JSON `ComicTextPage` có `schemaVersion` → nhận chữ; khoá = `ComicImageRequest.cacheKey`; giới hạn 30 MB; ảnh không chữ cũng lưu) → `ComicPageTextTranslator` (VietPhrase **từng khối** ngoài main theo `bookId` + phồn→giản của truyện, bỏ khối không có chữ Hán; **không** lưu bản dịch ⇒ sửa name thấy ngay).
- `ComicTranslationOverlay` (mới) phủ lên `Image` đã `scaledToFit` của `ComicPageView` (tham số `translation: ComicImageTranslationContext?`): khung chữ gốc nở ngang 15%, nền trắng 95% chữ đen (nền tối ⇒ đen 85% chữ trắng), cỡ chữ theo dòng gốc (9–22 pt) tự thu tới 40%; chạm khối ⇒ ẩn bản dịch, lộ chữ gốc (viền nét đứt màu nhấn), chạm lại ⇒ dịch; chạm ngoài khối vẫn bật/tắt thanh; viên "Đang nhận chữ" khi quá 0,6 s. Từ điển (`.translationDictionariesDidUpdate`), rule (`.quickTranslationRulesDidUpdate`), cấu hình dịch đổi ⇒ ảnh đang hiện dịch lại (`revision`), không nhận chữ lại.
- `ComicImageDiskCache`: `init(directoryName:byteLimit:)` (mặc định giữ `comic_images` / 400 MB; `byteLimit` / `trimTarget` thành thuộc tính) để dùng lại cho `comic_ocr`. Màn Dung lượng: `comic_ocr` thuộc "Cache ảnh truyện tranh" (`StorageUsageCategory`), nút "Xoá" và lịch tự dọn xoá cả hai (`StorageUsageCleaner` → `ComicPageTextRepository.clearAll`).
- Chưa làm ở v1: trình xem phóng to, nhận chữ trước lúc tải offline, chữ dọc, tiếng Nhật/Hàn (VietPhrase chỉ dịch tiếng Trung), sửa name từ khối.
- `CLAUDE.md` / `AGENTS.md`: mục Comic & Video.
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới** (file mới đều ≤ 400 dòng, một type chính; `ComicReaderView.swift` 377 dòng). Không build tại chỗ (Windows), chưa thử máy. Cần thử: (1) manhua chữ ngang nhận đủ, bản dịch nằm đúng bong bóng; (2) chữ nhỏ trên dải webtoon cao, chữ dọc — hằng ở `ComicTextRecognizer`, chỉnh xong tăng `ComicTextPage.currentSchemaVersion`; (3) log `🈶 [ComicOCR]` (bật log) thời gian mỗi ảnh + ngôn ngữ Vision có trên máy; (4) chạm khối không bật/tắt thanh, chạm đúp ngoài khối vẫn phóng to.

## [1.3.825] - 2026-11-11

### feat: DNS mã hoá trong app chống nhà mạng chặn tên miền

Anh Bửu: *"tôi muốn thêm dns, proxy, vpn hay gì đó để tránh trường hợp bị web chặn"* — phỏng vấn /grill-me chốt: đợt này chỉ chống **nhà mạng chặn tên miền** (anh chưa có proxy); bị trang nguồn chặn IP thì thử WARP; proxy để sau (hướng đã chốt, ghi ở `CLAUDE.md`). VPN thật (Network Extension) không làm được vì app không ký, chạy trong LiveContainer.

- `Services/Network/EncryptedDNS/` (mới): `EncryptedDNSRepository` (`@MainActor @Observable`) đặt `NWParameters.PrivacyContext.default.requireEncryptedNameResolution` ⇒ phủ mọi kết nối **trong tiến trình** (URLSession: fetch của tiện ích JS, Legado, ảnh bìa, ảnh truyện tranh, tải phim offline); WebView (tiến trình WebKit) và AVPlayer **không** ăn. Mặc định bật, Cloudflare (`EncryptedDNSPolicy`); 4 máy chủ kèm IP khởi động (`EncryptedDNSResolver`: Cloudflare, Google, AdGuard không lọc, Quad9).
- `EncryptedDNSProbe`: `NWConnection` TCP tới `captive.apple.com:80` với privacy context **riêng** bắt buộc DoH, hết giờ 6 s. Lỗi ⇒ lùi về DNS thường, log `❌ [DNS]`, nhớ lại để lần mở app sau dò trước rồi mới bật (bình thường thì bật ngay lúc mở app rồi mới dò). Dò lại khi đổi đường mạng (`NWPathMonitor`, giãn 2 s), đổi cài đặt, bấm "Kiểm tra lại"; mất mạng thì chờ, không lùi.
- `FreeBookApp.init` gọi `EncryptedDNSRepository.shared.start()` ngay sau `WebContentSettings.registerDefaults()`.
- Cài đặt › Chung › **Mạng & DNS** (`NetworkSettingsView`): công tắc, máy chủ, dòng trạng thái ("Máy chủ DoH tới được" — lượt dò không chứng minh URLSession thật sự theo context mặc định nên không ghi "đang dùng"), "Kiểm tra lại", nút "?" nói rõ phạm vi + bật rồi vẫn bị chặn là chặn theo SNI/IP. Trang `SystemDNSGuideView`: đổi DNS cho cả máy (app 1.1.1.1 của Cloudflare, profile của AdGuard DNS — đều chính chủ) và đổi IP bằng chế độ WARP khi bị chặn IP.
- `CLAUDE.md` / `AGENTS.md`: mục DNS mã hoá ở "Ràng buộc runtime cần nhớ".
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows), chưa thử máy. Cần thử: (1) nguồn bị nhà mạng chặn tải được qua `fetch`, tắt công tắc + mở lại app thì lại bị chặn; (2) mạng chặn 1.1.1.1 ⇒ lùi, fetch / bìa **vẫn tải được**; (3) phim từ tên miền bị chặn có phát được không.

## [1.3.824] - 2026-11-10

### fix: bấm Mở LiveContainer lúc đang nghe thì dừng nghe trước để LiveContainer mở lại được

Anh Bửu: có bản cập nhật, bấm "Mở LiveContainer" lúc đang nghe truyện / nhạc thì app chỉ tắt, không mở lại LiveContainer.

- **Nguyên nhân (đọc mã LiveContainer `UIKit+GuestHooks.m` / `LCSharedUtils.m`, chưa thử máy):** link `livecontainer-launch?bundle-name=ui` ⇒ hộp xác nhận ⇒ `launchToGuestAppWithClassicMode` xin `LSApplicationWorkspace` mở lại chính LiveContainer **hai lần**, lần trả lời đầu thì tự `SIGKILL`, trông vào yêu cầu thứ hai để iOS dựng app lại. App đang giữ phiên âm thanh nền ⇒ iOS còn coi tiến trình đang chạy ⇒ yêu cầu thứ hai coi như xong ⇒ app chết, không ai mở lại.
- `LiveContainerSwitchPreparer` (file mới, `Services/AppUpdate/`): trước khi mở link, dừng TTS (`TTSManager.stop()` khi đang đọc / có widget), nhạc (`AudioPlaybackSession.stop()` khi `AudioMiniPlayerState.isActive`), phim (`VideoPlaybackSession.stop()` khi có phim) — chỉ chạm phiên nhạc / phim khi có, tránh dựng `AVPlayer` — rồi `AVAudioSession.setActive(false)` và chờ 0,4 s; không phát gì ⇒ mở ngay. Log `📲 [AppUpdate] Dừng … trước khi mở LiveContainer`.
- `AppUpdateSheet`: nút "Mở LiveContainer" chờ bước trên rồi mới `openURL`. Bấm Huỷ ở hộp xác nhận của LiveContainer thì việc nghe vẫn đã dừng (anh duyệt).
- `CLAUDE.md` / `AGENTS.md` mục báo bản mới.
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows), chưa thử máy.

## [1.3.823] - 2026-11-10

### feat: sheet Kiểu hiển thị ở Khám phá chọn bố cục bằng hàng chọn, chỉ hiện một thanh cỡ

Anh Bửu: phần "Trang Khám phá" của sheet "Kiểu hiển thị" làm giống phần Danh sách / Lưới / Chỉ bìa (duyệt mockup).

- `ExploreLayoutSizePicker` (file mới, chỉ dùng ở `BookListLayoutSheet(showsExploreSizes: true)`): **hàng chọn bố cục** Lưới · Hàng ngang · Danh sách · Banner dáng y `Picker(.segmented)` ở trên (tự vẽ: nền `tertiarySystemFill`, ô chọn trắng / `systemGray2`, chữ 13 pt) + **một** thanh cỡ của bố cục đang chọn + dòng ghi chú — thay bốn thanh xếp chồng (sheet nửa màn phải cuộn). Tên thanh theo bố cục: Lưới / Hàng ngang "Cỡ thẻ", Danh sách "Cỡ dòng" (áp cả mục Xếp hạng), Banner "Chiều cao". Bố cục đang khác mặc định có **chấm màu nhấn** ở góc ô (thanh của nó đang ẩn); VoiceOver đọc tên đầy đủ + "Khác mặc định".
- `ExploreLayoutSizeKind`: thêm `shortLabel`, `sliderTitle`, `sliderNote`. Màn Cài đặt › Kiểu hiển thị giữ bốn thanh (`ExploreLayoutSizeControls`, đủ chỗ).
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows), chưa thử máy.

## [1.3.822] - 2026-11-10

### fix: danh sách tải vô hạn không còn nhảy lên khi nối trang

Anh Bửu thử 1.3.819: hết trắng xoá nhưng danh sách (kiểu Danh sách) vẫn **nhảy lên khi nối trang**; đổi cùng danh sách sang kiểu **Lưới thì không nhảy** ⇒ lỗi ở `List`.

- **Nguyên nhân:** hàng kiểu Danh sách cao thấp khác nhau (tên / mô tả 1–2 dòng). `List` (UICollectionView tự đo) chỉ **ước chừng** chiều cao hàng đã cuộn qua, mỗi lần chèn trang mới nó tính lại và chỉnh vị trí cuộn ⇒ nội dung đang xem bị đẩy lên ~1 hàng. Lưới (`ScrollView` + `LazyVGrid`) giữ chiều cao thật của ô đã dựng nên không bị.
- Đổi kiểu Danh sách sang **`ScrollView` + `LazyVStack`** như lưới ở: `DiscoveryNovelsLayoutView` (Khám phá / Thể loại / Xem thêm), `SearchSingleSourceResultsView` (Tìm trong một nguồn), `AllCommentsView` (Tất cả bình luận). Giữ y giao diện: panel bo góc, cách nhau 8 pt (`BookListPanelModifier.stackSpacing`), lề 16 / 4 (`bookListPanelStackPadding()`), kéo làm mới, `ScrollViewReader` theo `link`, chân `LoadMoreFooter` id cố định + tải trước.
- Tìm trong một nguồn: bỏ mẹo `NavigationLink` ẩn dưới panel (chỉ cần trong `List` để không có mũi tên `>`); hàng dùng `tappable` như lưới (`ContentDetailLink` / nút đổi nguồn), ⋮ playlist như cũ.
- Kệ / Lịch sử giữ `List` (vuốt ngang, tiêu đề nhóm dính; nạp trên máy 50 truyện mỗi lượt).
- `BookListPanelModifier` / `CLAUDE.md` / `AGENTS.md`: luật danh sách tải vô hạn không dùng `List`.
- **Kiểm chứng:** đọc code + anh thử kiểu Lưới (không nhảy); `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows), chưa thử máy. Đánh đổi: `LazyVStack` không tái dùng ô như `List` ⇒ danh sách rất dài tốn bộ nhớ hơn chút (như kiểu lưới hiện nay).

## [1.3.821] - 2026-11-10

### feat: ô giữa thanh tab có đĩa xám đứng yên khi không nghe gì

Anh Bửu: *"mặc định không có nghe truyện/nhạc thì để hình cd dừng ở tab"* — chọn kiểu **đĩa xám mờ**, **chạm không làm gì**.

- `MediaDiscIdleFace` (file mới): đĩa than 44 pt đứng yên — nền + 3 vòng rãnh + nhãn giữa theo tông `systemGray4` / `systemGray3` / `systemGray2` (như icon tab chưa chọn, tự đổi theo nền sáng / tối), lỗ giữa, viền mảnh như đĩa đang nghe. Không nhận chạm, VoiceOver bỏ qua.
- `MediaDiscTabBarSlot`: gờ nền 52 pt **luôn có** (thanh tab không đổi dáng khi bật / tắt nghe); không có nguồn ⇒ đĩa xám, có nguồn ⇒ `MediaDiscFaceButton(.tabBar)` như cũ; đổi qua lại bằng mờ chéo 0,2 s (bỏ hiệu ứng phóng vì gờ luôn đứng đó).
- Comment `MainTabBar` / `MediaDiscWindowManager`, `CLAUDE.md` / `AGENTS.md`: "ô giữa trống" ⇒ "đĩa xám đứng yên".
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows), chưa thử máy.

## [1.3.820] - 2026-11-10

### fix: đĩa góc thu tại chỗ khi đổi màn rồi hiện thẳng ở chỗ mới, không trượt ngang qua màn

Anh Bửu: Chi tiết → "+" → "Đọc" ⇒ đĩa (đang đứng cao trên cụm pill của menu xổ) hiện giữa Reader rồi trượt xuống trên nút tai nghe; mở trang không có thanh tab từ trang có thanh tab cũng giật.

- **Nguyên nhân:** `MediaDiscContainerViewController.updateDisc` thấy chỗ mới khác chỗ cũ ⇒ trượt đĩa (lò xo) kể cả khi đó là **màn khác**, và tính chỗ cả lúc màn còn đang chuyển cảnh (khung neo đang chạy).
- `MediaDiscScreenContext` (file mới): "trang đang hiện" = trang trên cùng của `UINavigationController` đầu tiên đang hiện trong tầng trình bày trên cùng (không có nav ⇒ chính tầng đó; chỉ đi cây VC, không quét view) + cờ đang chuyển cảnh (`isBeingPresented` / `isBeingDismissed` trong chuỗi trình bày, `transitionCoordinator` của tầng hoặc nav — kể cả vuốt back).
- Container: trang khác trang lúc đĩa hiện ⇒ **thu ngay tại chỗ**; đang chuyển cảnh ⇒ đĩa đang ẩn thì chưa đếm 0,3 s (hỏi lại mỗi 0,1 s), đĩa đang hiện cùng màn thì đứng yên; hết chuyển cảnh + giữ yên 0,3 s ⇒ phóng ra đúng chỗ mới. Trong cùng trang (menu "+" bung / thu, Home hiện muộn) vẫn trượt như cũ. Đang nằm trong header (nhấn giữ) mà đổi màn ⇒ cũng thu rồi hiện trong header màn mới.
- `CLAUDE.md` / `AGENTS.md` mục đĩa nghe.
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows), chưa thử máy — rủi ro: NavigationStack của SwiftUI không lộ `UINavigationController` ở chỗ dò ⇒ đẩy trang không được coi là đổi màn (đĩa trượt như cũ, chỉ mở Reader / sheet là thu).

## [1.3.819] - 2026-11-10

### fix: danh sách tải vô hạn không còn trắng xoá và nhảy khi nối trang

Anh Bửu (video Khám phá › qidian, kiểu Danh sách): kéo tới cuối, lúc tải trang kế cả danh sách trắng xoá ~0,2–0,3 s rồi hiện lại ở chỗ khác (bìa xám tải lại), nối mục mới thì nhảy lên ~1 hàng; xảy ra ở mọi danh sách tải vô hạn.

- **Nguyên nhân (đọc code + video, chưa thử máy):** mọi nơi dùng `LoadMoreFooter` gắn `.id(số mục)` cho hàng chân (mẹo 1.3.679 để vòng xoay không đứng hình) ⇒ mỗi trang về, hàng chân **đang hiện** bị xoá + hàng id mới chèn cùng N hàng mới phía trên ⇒ `List` nạp lại cả bảng. Lại chỉ tải khi chạm chân ⇒ lần nối nào cũng rơi đúng lúc đang nhìn đáy.
- `LoadMoreFooter`: thêm `token` (số mục) — vòng xoay mới bằng `.id(token)` **chỉ trên `ProgressView`**, kích hoạt tải bằng `.task(id:)` theo `token` (chân còn trên màn sau khi nối ⇒ tự tải tiếp, thay mẹo đổi id). Không ghi state.
- Hàng chân **id cố định** ở `DiscoveryNovelsLayoutView` (Khám phá / Thể loại / Xem thêm, danh sách + lưới), `SearchSingleSourceResultsView` (danh sách + lưới), `AllCommentsView`, `ShelfBooksLayoutView` (Kệ / Lịch sử, danh sách + lưới).
- **Tải trước:** Khám phá / Thể loại tải trang kế khi một trong 5 mục cuối hiện ra; Tất cả bình luận cũng vậy (trước: đúng bình luận cuối). Tìm đã có sẵn.
- Danh sách Khám phá: `ForEach(loader.novels, id: \.link)` như lưới (id `UUID()` đổi mỗi lần nạp lại ⇒ kéo làm mới dựng lại mọi bìa).
- Tất cả bình luận: đặt cờ đang tải **trước** điểm chờ đầu tiên ⇒ hai lần kích hoạt cùng khung không nối một trang hai lần. (Không lọc trùng theo `id`: id bình luận là `UUID()` mỗi lần bóc tách, lọc không có tác dụng.)
- Phim đề xuất (`VideoWatchSuggestSection`): hàng vòng xoay giữ 44 pt suốt lúc còn trang (ẩn / hiện bằng độ mờ) ⇒ chiều cao không đổi mỗi lượt; tải trước khi một trong 3 thẻ cuối hiện ra.
- `CLAUDE.md` / `AGENTS.md`: luật hàng chân id cố định + `token`.
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows), chưa thử máy.

## [1.3.818] - 2026-11-10

### feat: nút Hủy hẹn giờ cạnh đồng hồ trong sheet nghe nhạc, nút Dừng đỏ ở cả hai sheet

Anh Bửu: *"bạn chưa thêm nút huỷ cho AudioQuickControlSheet à"* + tự sửa hàng dưới của hai sheet điều khiển nhanh, Javis rà + commit chung.

- `AudioQuickControlSheet` (sheet nghe nhạc mở từ đĩa nghe): đang hẹn giờ tắt ⇒ viên **"Hủy"** đỏ ngay cạnh ⏱ + thời gian còn lại (khe 4 pt), cùng kiểu viên của sheet nghe truyện (1.3.816); chạm ⇒ rung nhẹ + `MediaSleepTimer.cancel()`. Không hẹn ⇒ không có viên.
- Sửa của anh: nút cuối hàng dưới đổi **"Tắt nhạc" / "Tắt đọc" ⇒ "Dừng"** chữ đỏ ở cả hai sheet; sheet nhạc truyền `tint` cho từng nút như sheet nghe truyện. `actionButton` của sheet nhạc chưa có tham số `tint` (sẽ lỗi biên dịch) ⇒ Javis thêm, chữ + icon theo `tint`.
- Comment `TTSQuickControlSheet` / `AudioQuickControlSheet` / `MediaDiscSheetHost` theo chữ "Dừng".
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows), chưa thử máy.

## [1.3.817] - 2026-11-10

### fix: vạch tiến độ trong sheet nghe truyện chỉ ghi N/M đoạn ở bên phải

Anh Bửu tự sửa `TTSQuickControlSheet` (`NowReadingBlock`), Javis rà + commit.

- Dưới vạch tiến độ chương: bỏ "Đoạn N" bên trái (giữ `Text(" ")` làm chỗ), bên phải đổi "M đoạn" ⇒ **"N/M"**, chỉ hiện khi có cả vị trí lẫn tổng (> 0), không thì trống. Comment đầu file theo chữ mới.
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows), chưa thử máy.

## [1.3.816] - 2026-11-10

### feat: nút Hủy hẹn giờ ngay cạnh đồng hồ đếm giờ trong sheet nghe truyện

Anh Bửu: *"thêm nút huỷ ngay bên cạnh đếm giờ của sheet nghe truyện"*.

- `TTSQuickControlSheet` (sheet điều khiển nhanh mở từ đĩa nghe TTS): đang hẹn giờ tắt ⇒ viên **"Hủy"** đỏ ngay cạnh ⏱ + thời gian còn lại (khe 4 pt), cùng kiểu viên "Hủy" của `TTSQuickTimerHeader`; chạm ⇒ rung nhẹ + `TTSManager.cancelSleepTimer()`, viên thu lại. Không hẹn ⇒ không có viên. Vùng chạm cao 44 pt; VoiceOver "Hủy hẹn giờ tắt".
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows), chưa thử máy.

## [1.3.815] - 2026-11-10

### fix: đĩa góc giống y nút +, bìa mờ đúng theo độ trong suốt, nhấn giữ thì đĩa nằm trong header như một nút header

Anh Bửu thử 1.3.814: (1) đĩa góc "độ trong suốt chưa đúng" — phải **giống y như các nút +**, bìa cũng theo trong suốt, **bỏ sàn 45%**; (2) nhấn giữ thì đĩa 52 pt đè nút ⋯ và tràn xuống dưới header — phải **nằm trong header, như một nút header** (anh duyệt mockup).

- **Đĩa góc** (`MediaDiscFaceButton(.corner)`): nền kính `FloatingGlassBackground` 52 pt y nút "+" (Độ trong suốt + Độ đục); bìa thu còn **32 pt** nằm trong như icon, hiện `1 − độ trong suốt` (không sàn: mặc định 90% ⇒ 10%, 100% ⇒ trong hẳn). Mờ gắn lên lớp bìa, không lên lớp cha của kính.
- **Nhấn giữ ⇒ vào header** (`MediaDiscHeaderSlot`, file mới): bìa 32 pt giữa hàng nút, ngay trái cụm nút phải, dò theo thứ tự: neo mới `.headerTrailing` (cụm nút phải của header tự dựng: Reader, nút ☰ màn truyện tranh; khe 6 pt) → `UINavigationBar` đang hiện của tầng trên cùng (mép trái nhỏ nhất của các view nằm hẳn ở nửa phải thanh, khe 2 pt; chỉ đọc khung + cờ hiện, không dựa tên lớp riêng của iOS) → góc phải dải 44 pt dưới thanh trạng thái. Kính tan dần + bìa rõ hẳn + viền mảnh như đĩa thanh tab (`MediaDiscWindowManager.isDiscElevated`); vùng chạm chỉ còn tròn 38 pt (`MediaDiscWindow.hitTest`) để không lấn nút header bên cạnh. Log ghi nguồn chỗ đã dùng. Bỏ `MediaDiscPlacement.elevatedFrame`; `mainWindow` / `topLayer` / `validFrame` mở cho `MediaDiscHeaderSlot` dùng chung; neo `.headerTrailing` không dự phần chỗ ở góc dưới.
- `CLAUDE.md` / `AGENTS.md` theo dáng + chỗ mới.
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows), chưa thử máy — phần đo nút trên `UINavigationBar` là rủi ro chính (đo hỏng ⇒ đĩa về góc phải vùng header).

## [1.3.814] - 2026-11-10

### fix: nhấn giữ đĩa góc lên header được, bìa đĩa góc mờ theo nút nổi, đĩa thanh tab 44 pt có gờ, đĩa không đè menu xổ

Anh Bửu thử 1.3.813 (build 1190): nhấn giữ đĩa góc không có tác dụng; đĩa góc không theo cài đặt nút nổi; muốn đĩa ở thanh tab to bằng đĩa góc; bấm "+" ở Chi tiết thì đĩa đè lên cụm pill một lúc rồi mới chạy lên.

- **Nhấn giữ:** `UILongPressGestureRecognizer` gắn trên `discView` của `MediaDiscContainerViewController` không bao giờ chạy vì nút SwiftUI bên trong bắt chạm ngay lúc chạm xuống. Bỏ nó; `MediaDiscFaceButton(.corner)` tự lo bằng **một** cử chỉ ghép `LongPressGesture(minimumDuration: 0.4).exclusively(before: TapGesture())` — nhấn giữ được ưu tiên ⇒ `onLongPress` ⇒ `beginElevation()` (rung nhẹ, lên header 5 giây), thả tay không mở sheet; thả sớm ⇒ chạm mở sheet. VoiceOver: thao tác mặc định mở điều khiển + thao tác "Đưa đĩa lên trên".
- **Đĩa góc theo nút nổi (kiểu C anh chọn):** vòng kính vẫn theo Độ trong suốt / Độ đục; **bìa** (cả nền tối dưới bìa) hiện `0,45 + 0,55 × (1 − độ trong suốt)` ⇒ đổi đều trên cả thanh trượt, mặc định 90% ⇒ ~50%, 100% ⇒ 45%. Mờ gắn lên lớp bìa, không lên lớp cha của kính.
- **Đĩa thanh tab:** bìa 44 pt (bằng bìa đĩa góc, `MediaDiscFaceButton.coverSize`), mép dưới ngang chân chữ của các tab (42,5 pt dưới mép trên thanh), giữa vòng nền 52 pt `.bar` + viền vạch ngăn — chỉ vẽ phần nhô ~5,5 pt trên thanh (`MediaDiscTabBarSlot`). Vùng chạm 52 pt phủ cả gờ. Không nghe ⇒ ô trống như cũ.
- **Menu xổ (`FloatingActionMenu`, FAB Chi tiết + nút "+" có Home):** neo đĩa gắn lên cụm pill đang phóng từ 40% ⇒ đầu dò đo khung nhỏ, đĩa đè pill tới lần đo lại sau 0,35 s. Nay neo gắn lên **bản ẩn** của cụm (cùng bố cục, không vẽ, không chạm, không VoiceOver, không chuyển cảnh) ⇒ đĩa chạy lên cùng lúc pill bung ra, về cùng lúc pill thu lại.
- `CLAUDE.md` / `AGENTS.md` + comment các file đĩa theo cỡ và cử chỉ mới.
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows), chưa thử máy.

## [1.3.813] - 2026-11-09

### fix: đĩa nghe góc dưới giống nút nổi khác, vòng kính theo độ trong suốt và độ đục, bìa luôn rõ

Anh Bửu: *"áp dụng theo cài độ trong suốt, độ đục như nút khác"*. Bản 1.3.812 cho cả **bìa** mờ theo "Độ trong suốt" (bìa hiện `1 − độ trong suốt`) ⇒ ở mức mặc định 90% bìa chỉ còn thấy ~10%, gần như tàng hình.

- `MediaDiscFaceButton(.corner)`: bỏ lớp mờ của bìa. Vòng kính `FloatingGlassBackground` vẫn theo "Độ trong suốt" + "Độ đục" của nút nổi (Cài đặt › Chung › Giao diện); bìa luôn rõ như icon của nút "+" / Home.
- `CLAUDE.md` / `AGENTS.md`: sửa câu mô tả độ trong suốt của đĩa góc.
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows), chưa thử máy.

## [1.3.812] - 2026-11-09

### feat: đĩa nghe ở ô giữa thanh tab, đĩa góc chỉ hiện ở màn không có thanh tab, nhấn giữ đĩa góc tạm lên header 5 giây

Plan anh Bửu đã duyệt (thay bản "đĩa trên header" đã bỏ): đĩa nghe nằm ở ô giữa thanh tab ở trang gốc các tab; mọi màn khác giữ đĩa góc dưới phải; nhấn giữ đĩa góc để tạm đưa nó lên header 5 giây.

- **Thanh tab luôn 5 ô** (`MainTabBar`): Kệ Sách · Khám Phá · [giữa] · Tiện Ích · Cài Đặt. Ô giữa (`MediaDiscTabBarSlot`, mới) = đĩa 32 pt gọn trong chiều cao thanh khi có nhạc / TTS kiểu "Đĩa góc dưới", trống và không bấm được khi không nghe — icon tab không đổi chỗ. Có đĩa hay không đọc `MediaDiscWindowManager.kind` ⇒ đúng ngay từ khung đầu.
- **Đĩa góc chỉ ở màn không có thanh tab**: thanh tab là neo `.hostsDisc` (vai mới của `MediaDiscAnchorRegistry`) ⇒ màn trên cùng có thanh tab thì đĩa góc ẩn **ngay**; đĩa đang ẩn chỉ hiện lại khi điều kiện đã giữ đủ 0,3 s (đẩy trang không làm đĩa lóe). Bàn phím, màn nghe, phim, hộp thoại vẫn ẩn như 1.3.808.
- **Nút đĩa dùng chung** `MediaDiscFaceButton` (`.corner` / `.tabBar`, mới) cho cả hai chỗ; chạm ⇒ `MediaDiscWindowManager.presentQuickControls()` ⇒ sheet điều khiển nhanh luôn trình bày từ cửa sổ của đĩa qua `MediaDiscSheetHost` (mới, tách từ `MediaDiscContentView` — đã xoá). Chạm đầu sheet giữ như cũ (nhạc ⇒ màn nghe; TTS ⇒ Reader đúng chương, Reader của truyện đang mở thì `navigateReaderToPlayingChapter`).
- **Bìa đĩa góc mờ theo "Độ trong suốt" của nút nổi**: bìa hiện `1 − độ trong suốt`, đúng như lớp màu của vòng kính; "Độ đục" vẫn là nhoè của vòng kính. Mờ gắn lên lớp bìa, không lên lớp cha của kính.
- **Nhấn giữ đĩa góc 0,4 s** ⇒ rung nhẹ, trượt lò xo mềm lên góc phải vùng header (mép trên ngay dưới thanh trạng thái, lề phải 16 pt — `MediaDiscPlacement.elevatedFrame`) 5 giây rồi về chỗ; trong lúc đó chạm vẫn mở sheet, đóng sheet ⇒ về ngay, đổi màn ⇒ giữ đủ 5 giây. Chỉ dời khung trong cửa sổ đĩa, không đụng layout app. Thanh tab không có cử chỉ này.
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows), chưa thử máy.

## [1.3.811] - 2026-11-09

### fix: nút ⋮ thêm playlist trong hàng danh sách không nhận chạm của cả hàng

Rà commit 1.3.810 trước khi push:

- `PlaylistListItemMenu` gắn `.menuStyle(.borderlessButton)` như menu chuyển từ của `DictionaryEntryRow` / `QuickTranslationRuleEntryRow`: ở kiểu Danh sách của Khám phá / Thể loại và Tìm một nguồn, ⋮ đè lên nút mở item **trong hàng `List`** — Menu kiểu mặc định có thể nhận chạm của cả hàng (chạm item lại mở ⋮). Lưới, Trang chủ Khám phá, Tìm nhiều nguồn không nằm trong `List`, không đổi gì.
- Comment của `PlaylistAddRequest` / `PlaylistAddSheet` hết ghi "ba lối" — liệt kê thêm icon cuối hàng và ⋮ / icon của item danh sách chưa mở.
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi có sẵn `JSDom.swift`, **0 mới**. Không build tại chỗ (Windows), chưa thử máy.
