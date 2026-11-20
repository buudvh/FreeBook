# CHANGELOG - Nhật ký Thay đổi CodeGraph Tàng Công Các

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **Tàng Công Các**.

## [1.3.1018] - 2026-11-20

### feat: Tiêu đề trang có nút trái luôn nằm cạnh nút trái, bỏ tiêu đề hàng 2

Anh Bửu (sau khi duyệt cỡ 28 cho hàng 2): "tôi đổi ý, đừng hiện tiêu đề 2 hàng nữa, để nó luôn hiển thị cạnh nút trái nếu có nút trái".

- **Trang có nút back** (`.backPageTitle` / `PageTitleStyle.centered`, ~64 trang): bỏ tiêu đề lớn hàng 2 của iOS (1.3.984–1.3.1017) ⇒ `navigationBarTitleDisplayMode(.inline)`, tiêu đề **22pt đậm** (cùng cỡ tiêu đề tab gốc / gốc sheet) ở ô `topBarLeading` ngay cạnh nút back, một dòng, không co chữ, trần bề ngang `HeaderMetrics.besideLeftButtonTitleMaxWidth` (rộng màn − 150, chừa nút back + cụm hai nút phải), dài thì cắt đuôi. Hết cảnh khoảng hở giữa hàng nút và hàng tiêu đề mỗi trang một khác, hết tiêu đề thu / bung khi cuộn.
- Bỏ đầu dò `PageTitleCollapseProbe` (dò nhãn tiêu đề lớn để hiện tiêu đề nhỏ khi thu) và cỡ tiêu đề lớn ở `NavigationBarAppearance` (`applyLargeTitleFont`); `HeaderMetrics` bỏ `largeTitleFontSize` / `inlineTitleFontSize` — tiêu đề trang còn **một cỡ** `rowTitleFontSize` 22.
- **Trang con trong sheet** (sheet hub: Thông báo, màn kiểm tra của một lượt; sheet kiểu hub: "Từ URL"…): nút ‹ (`HeaderBackButton`) và tiêu đề do `PageTitleModifier` dựng **chung một** `ToolbarItem` khi có `\.sheetPageBack` ⇒ thứ tự luôn ‹ rồi chữ, mũi cách chữ ~8pt. Bỏ `.sheetPageBackButton()` (mục toolbar riêng — hai mục `topBarLeading` thì iOS tự xếp); `SheetPageBackButtonModifier.swift` → `SheetPageBackEnvironment.swift` chỉ còn khoá environment.
- `ui-conventions.md`, `floating-pills.md` cập nhật theo.
- Kiểm: chỉ đọc code + `check_architecture.py` (chỉ còn violation cũ `JSDom.swift`); **không build tại chỗ (Windows), chưa chạy trên máy**. Cần thử: trang có nút back (tiêu đề cạnh nút back, tên dài cắt đuôi, không đè nút phải), cuộn không còn thu / bung, trang con trong sheet hub và sheet "+" của Kệ ("Từ URL"): nút ‹ đứng trước tiêu đề, bấm về trang chính.

## [1.3.1017] - 2026-11-20

### feat: Header thống nhất — bộ số chung HeaderMetrics, tiêu đề hàng 2 28pt, tiêu đề hàng 1 không co chữ, nút back trang con trong sheet chạm lề

Anh Bửu: "hàng 1 và hàng 2 header nhiều chỗ margin không giống nhau", "icon nhiều chỗ nhìn size cũng không giống nhau, title lớn chưa đủ to", "các header custom cho cảm giác logic thiết kế không giống" → mockup so sánh trước / sau (lề 16pt chung, 6 header tự dựng, nhịp dọc) → "Duyệt, cỡ 28".

- **Bộ số chung** `HeaderMetrics` (`Sources/Common/Utils/`): lề ngang = lề thanh hệ thống (16pt, máy ≥ 414pt 20pt), hàng 44, icon SF 17 / icon tài sản `AppGlyph` 20, khung 36×38 / back 38×44, tiêu đề hàng 1 22 / hàng 2 28 / cạnh nút back 17 / khối tiêu đề màn đọc-xem-nghe 16 + 13. Luật: mép vật nhìn thấy ngoài cùng chạm lề, nút ngoài cùng canh icon vào lề trong khung thay vì canh giữa.
- **Thành phần dùng chung** (`Views/Common/PageHeader/`): `HeaderBackButton` (`chevron.backward` 17pt nửa đậm cỡ ảnh lớn như mũi back hệ thống, khung 38×44, mũi canh trái) và `HeaderTitleBlock` (dòng 1 16pt nửa đậm, dòng 2 13pt màu phụ) — header tự dựng chuyển sang ở các bản sau.
- **Tiêu đề lớn hàng 2: 22 → 28pt đậm** (`NavigationBarAppearance.applyLargeTitleFont` đọc `HeaderMetrics.largeTitleFontSize`). Trước 22pt bằng tiêu đề hàng 1, nằm lọt thỏm trong ô iOS dựng cho chữ 34pt. Đầu dò thu tiêu đề (`PageTitleCollapseProbe`, ngưỡng ≥ 20pt) không đổi.
- **Tiêu đề hàng 1 không co chữ** (`PageTitleModifier`: bỏ `.minimumScaleFactor(0.8)`) — trước đây tên dài co còn 17,6pt nên mỗi trang một cỡ; nay dài thì cắt đuôi.
- **Nút ‹ của trang con trong sheet** (`SheetPageBackButtonModifier`: sheet hub, sheet kiểu hub, Thông báo, kiểm tra nguồn) dùng `HeaderBackButton`: trước là `chevron.left` nhỏ hơn mũi hệ thống, nằm giữa khung 38pt ⇒ mũi lùi vào ~30pt trong khi tiêu đề hàng 2 ở 16pt.
- `ui-conventions.md`: thêm mục "Lưới header chung".
- Kiểm: chỉ đọc code + `check_architecture.py` (chỉ còn violation cũ `JSDom.swift`); **không build tại chỗ (Windows), chưa chạy trên máy**. Cần thử: tiêu đề hàng 2 các trang có nút back (cỡ, thu vào cạnh nút back khi cuộn), trang con trong sheet hub (mũi ‹ thẳng hàng tiêu đề).

## [1.3.1016] - 2026-11-20

### feat: Cài đặt dịch thuật — hàng con hiện theo công tắc QT / Áp dụng rule dịch, bỏ công tắc Dịch đại từ

Anh Bửu: "Bật dịch quick trans mới hiển thị các nav con", "bỏ config dịch đại từ đi vì nó trùng với cấu hình token rule <pn>", "quản lý rule dịch … là con của áp dụng rule dịch", "nav cấu hình dịch theo nguồn và truyện đổi thành cấu hình dịch riêng biệt" → qua 3 bản mockup: TOC / Lọc rác / Riêng biệt "luôn hiện và nằm panel khác", "từ điển chung phải cùng panel với Dịch Thuật Quick Translate", đại từ "tắt hẳn" → duyệt.

- **Màn Cài đặt dịch thuật** (`TranslationSettingsView`):
  - Panel "Dịch Thuật Quick Translate": công tắc QT; **chỉ khi bật** mới hiện các hàng con thụt 16pt — "Áp dụng rule dịch" ⇒ (chỉ khi công tắc này bật) "Quản lý rule dịch" thụt 32pt (`QuickTranslateRuleSettingsRows`, bỏ tham số `isTranslationEnabled`; chữ công tắc lên `.body` vì trước nhỏ hơn chính hàng con của nó), rồi **Từ điển chung** gộp vào cùng panel (nhãn "Từ điển chung" + lưới 5 thẻ, Tải từ điển mặc định / tiến độ, Làm mới dữ liệu dịch, Cấu hình công cụ tra cứu — `globalDictionaryRows`), trước là section riêng.
  - Panel riêng không tiêu đề, **luôn hiện**: Quản lý quy tắc TOC, Quản lý lọc rác, **Cấu hình dịch riêng biệt** (đổi tên từ "Cấu hình dịch theo Nguồn & Truyện"; tiêu đề trang đích vốn đã là tên này) — ba thứ vẫn có tác dụng khi tắt QT.
- **Bỏ công tắc "Dịch Đại từ (Pronouns)" ở cả 3 chỗ**: Cài đặt dịch thuật, Cài đặt trình đọc (`ReaderSettingsView` mất binding `isPronounsEnabled`, `ReaderView` mất `@AppStorage` + `onChange`), sheet Cài đặt dịch truyện tranh (`ComicTranslationSettingsSheet`, bỏ cả dòng giải thích + `notifyEngineSettingChanged` hết người gọi).
- **Engine — cố định tắt**: tách từ (`VietPhraseTokenizer`) và `TranslateUtils.lookupRawTranslation` **không** tra Pronouns nữa (thứ tự còn Name ⇒ VietPhrase); bỏ `TranslationReadContext.pronounsEnabled` và cờ đại từ trong khoá `TokenizeMemo` / `mappingMemo`. Đại từ chỉ dịch qua rule `<pn>` (`QuickTranslationDictionaryToken`, vốn đã bỏ qua công tắc). Pronouns.txt vẫn nạp cho `<pn>`, thẻ Pronouns.txt, panel tra từ. Không còn ai đọc khoá `isTranslationPronounsEnabled` (giá trị cũ trong UserDefaults / bản sao lưu vô hại).
- Câu hướng dẫn của panel rule ở Reader (`ReaderDefinitionOverlayView+Rules`) thêm bước "bật Áp dụng rule dịch".
- `CHANGELOG.md` dời 1.3.971–986 sang `CHANGELOG.archive.md` (giữ ~30 entry).
- Kiểm: chỉ đọc code + `check_architecture.py` (chỉ còn violation cũ `JSDom.swift`); **không build tại chỗ (Windows), chưa chạy trên máy**. Cần thử: bật/tắt hai công tắc ở Cài đặt dịch thuật (hàng hiện/ẩn, thụt lề, vạch ngăn), thẻ Từ điển chung trong panel QT (menu thẻ, nhập / xuất). Nếu máy đang bật Dịch đại từ: chữ ngoài rule đổi sang nghĩa VP; tên chương đã lưu (`title_trans`) giữ bản cũ tới khi "Dịch lại tên chương".

## [1.3.1015] - 2026-11-20

### feat: Nhấn giữ một phiên log ⇒ Xem log / Xuất log / Xoá log, màn Xem log ngay trong app

Anh Bửu: "làm thêm option xem log nữa" → "Màn Ghi log hệ thống — nhấn giữ một phiên sẽ hiển thị các option xem log, xoá log, xuất log" → duyệt mockup; push chung với lưới sheet nhấn giữ (1.3.1014).

- **Trước**: màn Ghi log hệ thống chỉ chọn phiên (nhiều) rồi Xuất `.txt` / Xoá; muốn đọc log phải xuất ra file.
- **Nay**:
  - `LogSettingsView`: nhấn giữ một phiên ⇒ menu Xem log / Xuất log (.txt) / Xoá log (đỏ, hỏi lại; phiên đang ghi không có). Danh sách chọn nhiều + các nút cũ giữ nguyên.
  - Mới `LogSessionViewerView` (trang đẩy vào): thẻ đầu = khối đầu phiên như file xuất (bản app, máy, iOS, nhiệt / RAM / ổ trống, TTS, trạng thái cuối); chip "Tất cả / Chỉ lỗi (N)" + chip đảo "Mới nhất trước / Cũ nhất trước"; ô lọc chữ luôn hiện (300 ms); mỗi dòng `HH:mm:ss.SSS` + nội dung chữ đơn cách 11pt, dòng ❌ chữ đỏ nền đỏ mờ; nhấn giữ dòng ⇒ "Sao chép dòng" (`ClipboardCopier`, có toast); nạp 500 dòng mỗi lượt, tới chân thì nạp tiếp (`LoadMoreFooter` id cố định); nút chia sẻ góc phải xuất cả phiên.
  - Mới `AppLogger+Browse` (`loadLines`, `loadSessionHeader`): ghi nốt dòng chờ trên `queue` rồi đọc bằng kết nối riêng như đường xuất (không chặn ghi log); `AppLogDatabase.lines(sessionId:cursor:limit:newestFirst:onlyErrors:contains:)` — phân trang theo id, lọc lỗi + `LIKE` ở SQLite, tham số gắn bằng `bind` (thoát `%` `_` `\`). `SessionSummary` thêm `Hashable`; `header(for:)` dùng chung.
- Kiểm: chỉ đọc code, **không build tại chỗ (Windows), chưa chạy trên máy** — cần thử: menu nhấn giữ phiên (có lẫn với chạm chọn phiên không), phiên lớn cuộn nạp tiếp, lọc chữ tiếng Việt (LIKE chỉ không phân biệt hoa thường với chữ ASCII), đảo thứ tự, xuất từ màn xem.

## [1.3.1014] - 2026-11-20

### feat: Sheet nhấn giữ truyện — thao tác dưới Bộ sưu tập thành lưới 4 cột, Đổi nguồn thành dải dài

Anh Bửu: "sửa các option phía dưới bộ sưu tập của context menu thành dạng lưới, cho tôi mockup" → "nếu nút không đủ hàng 4 cái thì căn cho chúng được nằm giữa" → "để nút đổi nguồn giống 'Chuyển sang nguồn …' trong mockup" → duyệt mockup bản 3.

- **Trước**: phần dưới "Bộ sưu tập" của `BookActionSheet` là các hàng "icon + chữ" của `List` (Chuyển sang nguồn …, Đổi nguồn, Mở trong trình duyệt, Tải, Xuất, Dịch lại tên chương, Thêm cả phim / album vào playlist, Bỏ khỏi bộ sưu tập này, Xoá bản tải, Đánh dấu NSFW, Xoá / Xóa lịch sử).
- **Nay** (section "Thao tác", một hàng `List` không nền, không lề):
  - Dải dài viền màu nhấn (`BookActionStrip`, nền nhấn 16%, viền 55%): "Chuyển sang nguồn …" (chỉ truyện mất nguồn, `MissingSourceRebindActionRows`) rồi "Đổi nguồn" (truyện không phải nhập từ file).
  - Lưới 4 cột (`BookActionTileGrid` — `Layout` riêng: cột bằng nhau, cách 8, hàng cuối không đủ 4 ô thì ô giữ bề rộng và nằm giữa; hàng cao bằng ô cao nhất): ô `BookActionTile` = icon 22pt màu nhấn trên, chữ 2 dòng dưới, nền `AppGlassSheetModifier.rowFill`, bo 12. Thứ tự: Mở trình duyệt, Tải, Xuất, Dịch lại tên chương, Thêm cả phim / album vào playlist (vòng xoay thay icon khi tải mục lục), Bỏ khỏi bộ sưu tập này, Đánh dấu NSFW, rồi ô đỏ: Xoá bản tải (dòng phụ "5 tập · 2,3 GB", vẫn hỏi xác nhận), Xoá / Xoá lịch sử.
  - Ô "Xoá bản tải" chỉ thêm vào lưới khi phim còn file tải (kiểm ở sheet) để lưới không giữ chỗ trống. Điều kiện hiện từng ô giữ nguyên như trước.
- `PlaylistAddBookActionRow`, `VideoDownloadsActionRow` vẽ thành ô; `MissingSourceRebindActionRows` vẽ thành dải. Phần Truyện (bìa, tên, nút sửa / kệ) và Bộ sưu tập không đổi.
- Kiểm: chỉ đọc code, **không build tại chỗ (Windows), chưa chạy trên máy** — cần thử: chạm từng ô có đúng ô đó (không kích hoạt cả hàng), sheet chọn playlist / hộp xác nhận xoá bản tải mở từ ô, hàng cuối căn giữa, chữ dài 2 dòng.

## [1.3.1013] - 2026-11-19

### feat: Nhập từ điển và rule dịch — chọn file trước, popup chọn cách nhập hiện sau kèm tên file

Trước: mọi chỗ nhập file của phân hệ dịch hiện popup 3 cách nhập (Thay thế toàn bộ / Gộp / Chỉ thêm key mới) **trước**, chọn xong mới mở bộ chọn file; popup không biết file nào sẽ được nhập. Hai sheet chọn truyện ("Nhập từ truyện khác" / "Chia sẻ sang truyện khác") đã chọn truyện trước nhưng tên truyện nằm lẫn trong tiêu đề popup.
Nay (anh Bửu: "popup option nhập file hiển thị sau khi nhập file, hiển thị tên file nhập ở phần mô tả dưới tiêu đề nhập"): dùng khung chung `.dataImportFilePicker` (1ea15164) — hàng "Nhập file…" chỉ mở bộ chọn file; chọn xong mới hiện popup chọn cách nhập, tên file ở dòng dưới tiêu đề, nút "Nhập"; huỷ chọn file / chạm ra ngoài popup ⇒ không nhập. Logic 3 chế độ, toast "thêm X, cập nhật Y", chặn lúc đang nhập và loại file cho phép giữ nguyên:
- 5 thẻ Từ điển chung (GlobalDictionaryCardPresentations + GlobalDictionaryCardController: requestImport chỉ mở bộ chọn file, importFile(url, mode:) thay handlePickedFile / confirmImportMode / pendingMode).
- Danh sách VP / Name (DictionaryListView, Nhập từ điển — .plainText như cũ).
- Danh sách Phiên âm / Pronouns (BaseDictionaryListView; importFile(url, mode:) thêm chặn khi đang nhập).
- Danh sách rule 3 bộ: Nhập file rule và Nhập file rule tắt (QuickTranslationRuleIOMenu + DisabledActions: readImport / readDisabledImport nhận url + mode).
- Bỏ các .dataImportModePopup + DocumentPickerPresenter riêng + state chế độ chờ cũ ở những chỗ trên.
- BookImportSourceSheet / BookShareTargetSheet (không qua file, vẫn chọn truyện trước): popup tiêu đề "Nhập từ truyện khác" / "Chia sẻ sang truyện khác", tên truyện đã chọn ở dòng dưới tiêu đề (message:).
Danh sách VietPhrase.dat / Names.dat không có nhập nên không đổi.

File: Views/Settings/Translation/{GlobalDictionaryCardPresentations, GlobalDictionaryCardController, QuickTranslationRuleIOMenu, QuickTranslationRuleIOMenu+DisabledActions}, Views/Dictionary/{DictionaryListView, DictionaryListView+Transfer (chỉ comment), BaseDictionaryListView, BookImportSourceSheet, BookShareTargetSheet}, .claude/rules/translation.md.

Chưa kiểm: chưa build (máy Windows), chưa chạy máy — cần thử popup hiện đúng sau khi bộ chọn file đóng ở cả màn đẩy (Cài đặt, danh sách) lẫn danh sách mở trong sheet (hub Từ điển của Reader), và hai bộ chọn file của menu rule (rule / rule tắt) gắn cùng một view không lẫn nhau.

## [1.3.1012] - 2026-11-19

### feat: Nhập phiên âm, thay thế TTS, quy tắc mục lục, công cụ tra cứu — chọn file trước, popup chọn cách nhập hiện sau kèm tên file

Anh Bửu: "Hiện tại popup option nhập file hiển thị trước khi nhập file, sửa lại hiển thị sau khi nhập file. Hiển thị tên file nhập ở phần mô tả dưới tiêu đề nhập."

Trước: hàng "Nhập…" trong ngăn kéo … mở popup chọn cách nhập (`.dataImportModePopup`) trước, bấm "Nhập file" mới mở bộ chọn file; chế độ đã chọn giữ tạm ở `pendingImportMode` chờ file.
Nay: 5 màn chuyển sang khung chung `.dataImportFilePicker` (commit 1ea15164): hàng "Nhập…" chỉ mở bộ chọn file; chọn xong mới hiện popup Thay thế toàn bộ / Gộp / Chỉ thêm key mới với tên file ở dòng dưới tiêu đề, nút "Nhập"; bấm "Nhập" ⇒ gọi đúng hàm nhập cũ với file + chế độ (giữ nguyên logic 3 chế độ, khoá so trùng và toast "thêm X, cập nhật Y"). Huỷ chọn file ⇒ không có popup; chạm ra ngoài popup ⇒ bỏ file, không nhập. Giữ nguyên loại file cho phép của từng màn (NghiTTS .plist / .json / .csv / .txt, VieNeu .plist / .json, ba màn còn lại .json) và câu báo khi đuôi file sai (nay báo sau khi bấm "Nhập"). Bỏ state `showingImportModes` / `pendingImportMode`, `DocumentPicker` dạng sheet (hai màn phiên âm) và `DocumentPickerPresenter` riêng của từng màn. Lọc rác không đổi (không popup, chỉ thêm mẫu chưa có).

File đã đụng:
- `Sources/Views/Settings/TTS/TTSDictionaryEditView.swift` (phiên âm NghiTTS)
- `Sources/Views/Settings/TTS/VieNeuJapaneseDictionaryView.swift` (phiên âm VieNeu)
- `Sources/Views/Settings/TTS/TTSReplacementManagerView.swift` (thay thế ký tự TTS, cả tầng chung lẫn tầng riêng của truyện)
- `Sources/Views/Settings/Translation/TOCRulesConfigView.swift` (quy tắc mục lục)
- `Sources/Views/Settings/Search/SearchEnginesConfigView.swift` (công cụ tra cứu)

Chưa kiểm: không build được (máy Windows) — chỉ đọc code + `check_architecture.py` (không lỗi mới); chưa chạy trên máy, nhất là hai màn phiên âm (trước dùng `DocumentPicker` dạng sheet, nay bộ chọn bản sao `asCopy` của khung chung — file nằm ở thư mục tạm, đọc trong `Task` sau khi popup đóng) và màn mở dạng sheet (Thay thế TTS từ Cài đặt TTS / hub truyện, Công cụ tra cứu từ Reader).

## [1.3.1011] - 2026-11-20

### feat: Khung nhập file mới — chọn file trước, popup chọn cách nhập hiện sau kèm tên file

Anh Bửu: "Hiện tại popup option nhập file hiển thị trước khi nhập file, sửa lại hiển thị sau khi nhập file. Hiển thị tên file nhập ở phần mô tả dưới tiêu đề nhập."

- Mới `DataImportFilePickerModifier` (`.dataImportFilePicker(isPresented:allowedContentTypes:title:modes:initialMode:onImport:)`, `Views/Common/DataImportModePopup/`): gộp `DocumentPickerPresenter` + popup chọn cách nhập. Mở bộ chọn file trước; chọn xong, **chờ bộ chọn đóng hẳn** (`isPresented` về `false` sau `onFinished` của host) rồi mới hiện popup — trình bày cover khi host còn đang đóng thì UIKit bỏ qua. Huỷ chọn file ⇒ không popup; chạm ra ngoài popup ⇒ bỏ file. `onImport(url, mode)` chạy sau khi popup đóng hẳn; `url` là bản sao trong thư mục tạm (`asCopy`) nên đọc sau vẫn được.
- `DataImportModePopup` / `.dataImportModePopup`: thêm `message` — dòng dưới tiêu đề hiện **tên file** (icon tài liệu, dài thì cắt giữa để thấy đuôi file); không có ⇒ "Chọn cách nhập" như cũ. Nút cuối mặc định đổi "Nhập file" ⇒ "Nhập".
- Các màn nhập chuyển sang khung mới ở các commit kế tiếp của đợt này. `ui-conventions.md` cập nhật.
- Kiểm: chỉ đọc code, **không build tại chỗ (Windows), chưa chạy trên máy**.

## [1.3.1010] - 2026-11-19

### fix: Import truyện từ trình duyệt không còn báo "Không tìm thấy tiện ích bóc tách" khi tiện ích tra được trễ — Chi tiết chờ một lát và tự nạp lại

Trước (anh Bửu báo): Import từ trình duyệt thỉnh thoảng hiện "Không tìm thấy tiện ích bóc tách của truyện này!", bấm "Thử
lại" thì được. Màn Chi tiết tra tiện ích (ext = danh mục tiện ích theo extensionPackageId) đúng một lần lúc hiện
(loadBookData ⇒ loadBookDetailOnly / loadTOCDataOnly), không thấy là báo lỗi ngay và không tự thử lại; "Thử lại" chạy
đúng hàm đó và thành công ⇒ lúc màn vừa hiện tiện ích chưa tra được, lát sau mới có — màn dựng trước khi mã tiện ích của
lượt Import kịp tới, hoặc danh mục tiện ích đang dựng lại đúng lúc đó (log cũ không ghi mã tiện ích nên chưa phân biệt).

Nay (BookDetailView+ExtensionWait, mới):
- Nhánh "không có ext" của chi tiết / mục lục gọi waitForExtension: giữ vòng xoay đang tải, chờ tối đa 1,5 s; hết giờ mới
  báo lỗi như cũ, kèm log ❌ [BookDetail] (packageId, số tiện ích đã cài / trong danh mục, có trong đã cài hay không).
- BookDetailView có .onChange(of: ext?.localPath): tiện ích vừa tra được (mã tiện ích của màn đổi hoặc danh mục có thêm)
  ⇒ nạp ngay phần đang chờ, hoặc phần đã báo lỗi "không tìm thấy" — khỏi bấm "Thử lại". Log ℹ️ [BookDetail].
- BookDetailView.swift: isLoadingDetail / isLoadingTOC private ⇒ internal, thêm @State extensionWaitTargets, thay hai chỗ
  báo lỗi (số dòng không đổi). Không đụng trình duyệt / Kệ / Khám phá.
- Đánh đổi: tiện ích thật sự đã gỡ thì lỗi hiện chậm ~1,5 s.

Chưa kiểm: máy Windows — chưa build, chưa chạy trên máy; nguyên nhân gốc chưa có log xác nhận (nếu còn gặp, log ❌
[BookDetail] cho biết mã tiện ích nhận được); check_architecture.py chỉ còn vi phạm có sẵn (JSDom.swift).

## [1.3.1009] - 2026-11-19

### fix: Sửa VP / Name / rule lúc đang nghe — Reader hiện bản dịch mới cho mọi đoạn như cũ, chỉ tiếng TTS giữ chữ cũ ở đoạn đang đọc và đoạn đó được tô cả đoạn

Trước (bản đã build): Reader ghim chữ TTS cho các dòng ≤ mốc nối — anh Bửu báo các đoạn trước đoạn đang nghe không hiển
thị đúng nghĩa đã cập nhật. Anh chốt: "Hiển thị phải thay đổi cho đúng (như cũ …). Việc để nguyên đoạn trước khi nghe chỉ
nên làm với nghe chứ không phải làm với đọc" + chọn "Tô cả đoạn".

Nay:
- Reader dựng lại bản dịch như trước tính năng (bản mới cho mọi đoạn, vẫn hoãn khi panel / menu chọn chữ mở). Gỡ hẳn phần
  ghim chữ: ReaderViewModel+TTSRetranslation (alignedWithTTSAnchor / chờ mốc 3 s / nắn lại cache / trả bản gốc), lượt chờ
  trong processAndSaveChapter, giữ lượt nối khi panel mở (setReaderHold), trường ghim của CachedChapter
  (ttsAnchorStamp / unalignedParagraphItems, ttsSnapshot*), getPretranslatedSnapshot về lại paragraphItems.
- TTS giữ cơ chế nối: chunk của dòng ≤ L (dòng đang đọc + chunk đã xếp sẵn hàng đợi NghiTTS / VieNeu) đọc chữ cũ, dòng sau
  đọc bản mới, tiếng không cắt; không còn chờ Reader. TTSRetranslationCoordinator gọn lại: bỏ mốc / pending / hold / người
  chờ, còn staleLineIds (dòng ≤ L có chữ TTS khác bản mới, cả dòng đã nghe qua, tên chương = -1) + FullRetranslation (bản
  mới đầy đủ), xoá khi chapterContent đổi (didSet) — TTS đọc lại / chuyển chương / thay cả chương.
- Highlight "tô cả đoạn": ReaderTTSHighlightReader lấy chữ TTS đang đọc của dòng đang đọc / đang chuẩn bị qua
  TTSManager.spokenLineText(lineId:) (tra normalizedChapterText — chữ trộn sau lượt nối; tên chương = chapterTitle);
  ReaderTTSHighlightBinder so với ParagraphCardView.displayText: khác ⇒ tô cả đoạn bằng kiểu vệt chuẩn bị (nhạt hơn),
  trùng ⇒ vệt câu như thường. ReaderView chỉ đổi tham số truyền vào binder (không thêm dòng).
- Lùi / tua về dòng mà từ đó còn dòng chunk chữ cũ (TTSManager+RetranslationRewind, mới): adoptFullRetranslationIfStale thay
  cả chương bằng bản mới đầy đủ (bỏ tiếng nạp trước) rồi đọc từ đầu dòng đích — cắt tiếng như mọi lần tua. Gọi ở
  seekToParagraph (vạch tua sheet nghe mini) và skipBackward (sheet, màn khoá; đổi đúng một dòng gán chỉ số). Đổi độ dài
  chunk / hiện tên chương sau lượt nối ⇒ chia lại từ chữ bản mới như resumeAfterSettings; bản mới đã cũ (token / cấu hình
  đổi) ⇒ đọc chunk hiện có + log. "Nghe từ đây" / nút tai nghe Reader dựng lại phiên bằng bản dịch sẵn của Reader (đã là
  bản mới) nên không cần lối này.
- Ghi chú luật: .claude/rules/tts.md, .claude/rules/reader-text-pipeline.md.

Khác gợi ý của spec: binder so thẳng chữ TTS đang đọc với chữ đang hiện thay vì chỉ dựa vào tập dòng chữ cũ — phủ cả lúc panel
đang mở (Reader chưa dựng lại, TTS đã đọc bản mới) và khoảng trước khi TTS kịp nối. Hệ quả: mọi lệch chữ TTS ↔ Reader có sẵn
(bộ dịch tiện ích ra chữ khác, bật / tắt dịch lúc đang tạm dừng…) nay hiện tô cả đoạn thay vì vệt câu lệch chỗ.

Chưa đồng bộ (biết, chưa sửa): bong bóng / dòng trích của vạch tua sheet nghe mini lấy chữ chunk TTS, kéo lùi qua dòng chữ cũ
vẫn xem trước câu cũ; thả tay thì TTS thay chương và đọc bản mới.

Chưa kiểm: máy Windows — chưa build, chưa chạy trên máy; check_architecture.py chỉ còn vi phạm có sẵn (JSDom.swift);
TTSManager.swift 3413 dòng, ReaderView.swift 1924 dòng (không tăng).

## [1.3.1008] - 2026-11-19

### fix: Danh sách VietPhrase.dat / Names.dat — thêm nhiều từ một lượt ghi lớp sửa đổi, không dịch lại N lần

Thuộc commit trước (danh sách từ điển gốc VietPhrase.dat / Names.dat).
Trước: nút "+" dán N dòng gọi DictionaryCache.upsertEntry N lần ⇒ ghi lại CustomVietPhrase.txt / CustomNames.txt N lần và phát N thông báo đổi từ điển (Reader / TTS — kể cả dịch lại từ đoạn sau khi đang nghe — chạy N lượt); hỏng giữa chừng thì ghi dở một nửa.
Nay: nhiều dòng ⇒ **một** TranslationDictionaryWriter.mutate(isName:bookId: nil) (mục mới / đè lên đầu, mục cũ cùng khoá bỏ) rồi DictionaryCache.refreshFromPublishedState — một lượt ghi, một thông báo, như danh sách Chung (DictionaryListView). Một dòng vẫn đi đường .term thường (saveCustomEntry).

File: Views/Dictionary/GlobalBaseDictionaryListView.

Chưa kiểm: chưa build, chưa chạy máy.

## [1.3.1007] - 2026-11-19

### feat: Thẻ VietPhrase.txt / Name.txt › Sửa mở danh sách từ điển gốc VietPhrase.dat / Names.dat, nghĩa hiệu lực kèm lớp sửa đổi

Trước: Cài đặt dịch thuật › thẻ VietPhrase.txt / Name.txt › Sửa mở danh sách Chung cũ (DictionaryListView) — chỉ thấy lớp sửa đổi (CustomVietPhrase.txt / CustomNames.txt), không thấy từ nào của VietPhrase.dat / Names.dat.
Nay (anh Bửu: "Sửa vietphrase thì hiển thị danh sách của vietphrase.dat chứ không phải custom vietphrase nhé"; chọn "Lớp sửa đổi, hiện chung", Name cũng vậy):
- GlobalBaseDictionaryListView (mới): danh sách từ điển gốc với **nghĩa hiệu lực** = .dat + lớp sửa đổi Chung — từ đã sửa hiện nghĩa mới + nhãn "đã sửa"; từ đã xoá (tombstone) ẩn; từ chỉ có ở lớp sửa đổi (tự thêm) đứng đầu, nhãn "đã thêm". Kiểu hàng VP/Name (.headline khoá, .subheadline nghĩa màu phụ), chạm thân hàng ⇒ DictEntrySheet chế độ sửa (như DictionaryListView), icon Xoá, "+" nổi thêm từ, .backPageTitle("VietPhrase.dat" / "Names.dat"), .searchable(..., placement: .navigationBarDrawer(displayMode: .always), prompt:). Ngăn kéo "…" có "Từ đã sửa / đã xoá" ⇒ đẩy DictionaryListView Chung cũ (xem / khôi phục).
- Lưu / xoá / thêm **chỉ** ghi lớp sửa đổi Chung qua đường có sẵn DictionaryCache.upsertEntry / deleteEntry ⇒ TranslationManager.saveCustomEntry / deleteCustomEntry (scope .term ⇒ Reader / TTS dịch lại); không ghi lại .dat. Xoá một từ gốc = tombstone (ẩn khỏi danh sách), xoá từ tự thêm = bỏ hẳn.
- Hiệu năng (VietPhrase cỡ triệu mục): mở màn đọc **mảng khoá** một lần ở nền (vòng quay "Đang đọc VietPhrase.dat…") từ cây đã nạp — FrozenTrieDictionary+Walk (mới): walkEntries duyệt cây tiền thứ tự chỉ giữ đường đi hiện tại (bộ nhớ O(độ sâu)) và allKeys() không giữ nghĩa; allEntries() cũng chuyển sang walkEntries (cùng tập entry, thứ tự nay là tiền thứ tự của cây — khoá cha trước khoá con; bớt các mảng nút cỡ triệu phần tử khi xuất / gộp). Nghĩa của hàng tra lúc hàng hiện (lớp sửa đổi trước, rồi cây). Danh sách hiện theo lượt 200 hàng (nạp sớm khi còn 50). Tìm theo từ gốc **và** nghĩa (BaseDictionaryBrowser.search, Service mới): chạy nền, chờ 300 ms sau phím cuối, gõ tiếp thì huỷ lượt cũ (huỷ cả task nền đang duyệt cây), dừng ở 500 kết quả — dòng tổng ghi "500 kết quả đầu".
- Danh sách VP / Name Chung cũ vẫn mở từ Từ điển của truyện như trước; Nhập / Xuất / Xoá của thẻ không đổi.

File: Models/Dictionaries/{FrozenTrieDictionary, FrozenTrieDictionary+Walk (mới)}, Services/Translation/Manager/BaseDictionaryBrowser (mới), Views/Dictionary/GlobalBaseDictionaryListView (mới), Views/Settings/Translation/{GlobalDictionaryCardPresentations, GlobalDictionaryCardController (chỉ comment)}, .claude/rules/translation.md.

Chưa kiểm: chưa build (máy Windows), chưa chạy máy — cần đo trên máy thời gian / RAM khi đọc mảng khoá VietPhrase cỡ triệu mục và tốc độ tìm theo nghĩa. Thứ tự hàng là thứ tự cây (gần theo chữ, không sắp xếp lại). File .txt xuất từ thẻ (GlobalDictionaryTextExporter) nay ra theo thứ tự cây mới — cùng nội dung, khác thứ tự dòng.

## [1.3.1006] - 2026-11-19

### fix: Danh sách tab danh mục ở Khám phá không còn tự kéo lệch khi quay về từ Chi tiết / tab khác

Anh Bửu: "khi scroll list ở Khám phá rồi chuyển tab khác hoặc vào chi tiết rồi trở về thì danh sách có cảm giác bị chạy đi" → "tra xong nguyên nhân thì fix rồi push luôn".

- **Nguyên nhân** (`DiscoveryCategoryTabView`, tab `home` kiểu cũ — kiểu Danh sách lẫn Lưới): mỗi lần nội dung tab hiện lại (back từ Chi tiết, đổi tab chính rồi về, quay về tab danh mục kề bên), `.onAppear` lấy neo của `DiscoveryScrollAnchorStore` (link hàng trên cùng lúc rời) và 0,2 s sau `scrollTo(neo, .top)` — kể cả khi trang **không** bị dỡ và `UIScrollView` vẫn giữ đúng chỗ cuộn. Hàng neo thường đang bị che một phần ⇒ cả danh sách bị kéo lệch; neo không bao giờ xoá nên lần nào về cũng nhảy. Biến thể nhảy xa: lúc đẩy Chi tiết các hàng có thể báo tắt trước tab ⇒ không chốt neo mới ⇒ về lại thì kéo tới neo cũ từ lần đổi tab trước.
- **Sửa**: lượt khôi phục từ `.onAppear` chỉ chạy khi **hàng đầu tiên đang hiện** (danh sách đang ở đầu = trang vừa bị `TabView(.page)` dỡ / ra ngoài cửa sổ ±3 tab) — kiểm lúc cuộn, sau 0,2 s; trang còn giữ chỗ cuộn thì để nguyên. Lượt khôi phục khi danh sách vừa nạp xong hàng đầu (từ 0 mục) giữ như cũ.
- Chưa sửa (ghi nhận từ lúc tra): bộ dịch tiện ích thay bản QT có thể đổi số dòng tên / mô tả của hàng phía trên ⇒ lệch nhẹ; tiêu đề lớn mới (1.3.984) của Thể loại / Xem thêm có thể bung / thu khi back — cần thử trên máy.
- Kiểm: chỉ đọc code, **không build tại chỗ (Windows), chưa chạy trên máy**.

## [1.3.1005] - 2026-11-19

### fix: Kệ ở "Chỉ NSFW" vẫn có thanh chip Tất cả / Truyện chữ / Truyện tranh / Phim / Âm thanh

Anh Bửu: "chỉ nsfw của tab kệ sách thiếu chip tất cả/truyện chữ/truyện tranh/phim/âm thanh" → duyệt plan.

- **Trước**: thanh chip loại của Kệ + Lịch sử chỉ hiện khi danh sách **đã lọc NSFW** có từ 2 loại trở lên (`ShelfKindFilter.showsFilterBar`) ⇒ ở "Chỉ NSFW", truyện NSFW cùng một loại là mất cả thanh chip, trong khi "Tất cả" vẫn có.
- **Nay**: số loại đếm trên kệ ∪ lịch sử **chưa** lọc NSFW (`ShelfKindFilter(_:kindFilter:kindSource:)`, `ShelfView` truyền thêm một `ShelfBookPartition(allBooks)` khi bộ lọc NSFW không phải "Tất cả") ⇒ thanh chip hiện như nhau ở cả ba chế độ. Chọn loại không có truyện nào sau lọc NSFW ⇒ màn rỗng "Chưa có … trên kệ" sẵn có, thanh chip vẫn ở trên. Thanh chip luôn đủ 5 chip cố định nên không lộ loại của truyện NSFW đang ẩn.
- Kiểm: chỉ đọc code, **không build tại chỗ (Windows), chưa chạy trên máy**.

## [1.3.1004] - 2026-11-19

### fix: Từ điển gốc xếp hàng mọi lượt ghi, thay file .dat an toàn; toast nhập rule đếm đúng "cập nhật"

Ba lỗi review phản biện tìm ra ở việc 6–8 (thẻ Từ điển chung, danh sách Phiên âm / Pronouns, nhập rule):
1. Mất dữ liệu khi sửa trong lúc nhập — Trước: nhập ở danh sách Phiên âm / Pronouns (và ở thẻ) chạy ngoài actor GlobalDictionaryEditor; trong vài giây importer nạp lại (loadAllDictionaries), sửa / xoá một hàng đọc phienAmMap / cây Pronouns còn bản cũ trong RAM rồi ghi đè file ⇒ mất mọi mục vừa nhập (toast vẫn báo thêm X); Pronouns còn dùng chung file tạm Pronouns.dat.importing giữa hai đường. Nay: GlobalDictionaryEditor là hàng đợi duy nhất cho mọi lượt ghi từ điển gốc (nhập ở thẻ, nhập ở danh sách, sửa / xoá hàng, xoá cả từ điển) — chuỗi `serialized`: lượt sau chờ lượt trước ghi **và nạp lại** xong (actor thường cho lượt khác chen ở mỗi await). GlobalDictionaryImporter luôn đọc từ điển gốc **trên đĩa** (bỏ nhánh đọc bản RAM), vẫn so số mục với wordCount. BaseDictionaryListView khoá "+", chạm hàng, nút xoá và thao tác trợ năng "Sửa" trong lúc đang nhập.
2. Thay file không an toàn — Trước: GlobalDictionaryImporter.write xoá .dat đích rồi mới moveItem file tạm (app bị tắt giữa hai bước ⇒ mất VietPhrase / Names / Pronouns); "Thay thế toàn bộ" qua TranslationManager.importDictionary cũng xoá đích trước rồi dựng thẳng vào đích. Nay: mọi đường (gộp, chỉ thêm, thay thế toàn bộ, sửa hàng) dựng / chép vào file tạm cùng thư mục tên duy nhất `<tên>.importing-<UUID>` rồi FileManager.replaceItemAt (đích chưa có ⇒ moveItem); lỗi giữa chừng ⇒ xoá file tạm, bản cũ còn nguyên. File tạm sót của lượt bị tắt được dọn ở lượt ghi kế tiếp. "Thay thế toàn bộ" giữ đúng ngữ nghĩa cũ (dựng .dat từ file nhập bằng DoubleArrayTrieBuilder.build(fromTxtFile:), PhienAm chép nguyên file).
3. Toast nhập rule đếm sai "cập nhật" — Trước: thẻ Rule dịch, ngăn kéo "…" của danh sách rule và chia sẻ bộ rule riêng lấy số mẫu trùng (importPreview.overlapping) làm "cập nhật", nên nhập lại đúng file vừa xuất vẫn báo "cập nhật N". Nay: QuickTranslationRuleRecordStore.importCounts(current:imported:mode:) chỉ đếm mẫu có vế phải thực sự đổi, và chỉ ở "Gộp" ("Chỉ thêm key mới" ⇒ cập nhật 0); QuickTranslationRuleTransfer.sharePreview đổi thành shareCounts(from:to:mode:).

File: Services/Translation/Manager/{GlobalDictionaryEditor, GlobalDictionaryImporter}, Services/Translation/Engine/{QuickTranslationRuleRecordStore, QuickTranslationRuleTransfer}, Views/Dictionary/BaseDictionaryListView, Views/Settings/Translation/{GlobalDictionaryCardController, QuickTranslationRuleIOMenu, QuickTranslationRuleListView}, .claude/rules/translation.md.

Chưa kiểm: chưa build, chưa chạy máy. Ngoài hàng đợi vẫn còn hai đường ghi VietPhrase.dat có sẵn từ trước, không đổi ở đây: "Tải từ điển mặc định" (downloadDefaultDictionaries) và gộp lớp custom vào VietPhrase (DictionaryMergeTask ⇒ TranslationManager.importDictionary, vẫn xoá đích trước rồi dựng).

## [1.3.1003] - 2026-11-19

### feat: Thử rule ở danh sách rule chung / tên chương mở từ Reader kèm bộ rule riêng của truyện đang đọc

Trước: sheet "Thử rule" ở danh sách rule chung / tên chương luôn chỉ áp bộ chung (+ bộ tên chương), kể cả khi danh sách mở từ hub Từ điển của Reader — rule riêng của truyện đang đọc không được tính, kết quả khác lúc đọc.
Nay (anh Bửu chốt "Kèm bộ riêng"): danh sách mở từ Reader (có contextBookId) thử như lúc đọc truyện đó — QuickTranslationRuleEngine.preview(_:scope:contextBookId:mode:) thêm bộ riêng của truyện và dùng bookId của nó (file tắt riêng, công tắc token, thứ tự ưu tiên, bộ ngoặc, Name riêng); danh sách tên chương áp riêng + tên chương + chung, danh sách chung áp riêng + chung. Mẫu rule đã khớp tra theo cặp (bộ, dòng) gồm cả bộ riêng ⇒ hiện đúng bộ ("bộ riêng" / "bộ tên chương" / "bộ chung"). Nút "?" của ô nhập nói rõ đang kèm bộ riêng. Mở từ Cài đặt (không có truyện) giữ như cũ.

File: Services/Translation/Engine/QuickTranslationRuleEngine+Preview, Views/Settings/Translation/{QuickTranslationRuleTesterPanel, QuickTranslationRuleTesterSheet, QuickTranslationRuleListView}, .claude/rules/translation.md.

Chưa kiểm: chưa build, chưa chạy máy.

## [1.3.1002] - 2026-11-19

### fix: Reader bỏ chữ ghim khi mốc dịch lại của TTS hết hiệu lực, tua đoạn chặn lúc đang dựng chương, vạch tua không giữ danh sách đoạn cũ

Vá các lỗi review phản biện tìm ra ở ba commit dịch lại khi đang nghe + tua theo đoạn:

1. Reader giữ chữ cũ của dòng ≤ mốc sau khi mốc hết hiệu lực ⇒ lệch highlight. Trước: Reader ghi chữ TTS vào cache
   cho dòng ≤ L kèm token hiện hành; TTS dựng lại chương (chương trước → chương kế, nghe tiếp từ chương trước tự sang,
   jumpToChapter không truyền snapshot) thì mốc chết nhưng isTranslationFresh vẫn đúng ⇒ Reader không dựng lại, TTS
   đọc bản mới từ dòng 0 còn Reader hiện chữ cũ dòng 0…L; bấm Nghe từ Reader còn đưa chữ ghim làm snapshot ⇒ dòng ≤ L
   đọc bản dịch cũ mãi. Nay:
   - CachedChapter lưu ttsAnchorStamp + unalignedParagraphItems (bản dựng gốc) khi ghim (ChapterCache.swift).
   - TTSManager.chapterContent có didSet ⇒ TTSRetranslationCoordinator.ttsTextRevision; Reader nghe nó và trả chương
     đang ghim về bản gốc ngay khi mốc không còn sống (restoreChaptersWithDeadTTSAnchor).
   - Mốc còn hiệu lực phải khớp cả cờ phồn → giản + vân tay bộ dịch của phiên TTS (Anchor.convertsTraditional /
     engineFingerprint) và công tắc dịch + phồn → giản của bản Reader dựng.
   - getPretranslatedSnapshot (ReaderView.swift) dùng CachedChapter.ttsSnapshotParagraphItems / ttsSnapshotTitle — luôn
     bản gốc, không chữ ghim.
2. Danh sách đầu đoạn của vạch tua có thể cũ khi chương mới cùng số chunk (startSpeaking đổi chương trước khi gán chunk).
   Nay TTSManager.paragraphs có didSet ⇒ layoutRevision tăng mỗi lần gán mảng chunk (khoá outline đã có layoutRevision).
3. Tua trong lúc startSpeaking đang dựng chương ⇒ phát nhầm chunk chương cũ, lưu sai tiến độ, lượt dựng xong đè mất chỗ
   tua. Nay didSet của paragraphs ghi chủ mảng chunk (phiên / truyện / chương); seekToParagraph và lượt nối bản dịch bỏ
   qua khi chủ lệch phiên / chương đang phát (isChunkLayoutCurrent).
4. Hàng rào refill NghiTTS so cả struct chunk (range / sourceRange) trong khi tiêu chí "đổi" của lượt nối chỉ so chữ +
   kiểu ranh giới ⇒ chunk cùng chữ dời range bị bỏ kết quả. Nay cùng so chữ + boundaryKind.
5. Reader chờ mốc bằng continuation không nghe huỷ ⇒ lượt dựng đã huỷ chặn lượt mới (refreshParagraphItems await lượt
   cũ) tới 3 s. Nay waitForAnchor bọc withTaskCancellationHandler, huỷ là thôi chờ ngay.

File: TTSRetranslationCoordinator.swift, TTSManager.swift (didSet paragraphs / chapterContent, hàng rào refill),
TTSManager+Retranslation.swift, TTSManager+RetranslationSplice.swift, TTSManager+ParagraphSeek.swift,
ReaderViewModel+TTSRetranslation.swift, ReaderViewModel+TranslationPresentation.swift, ReaderViewModel+Translation.swift,
ReaderTranslationPresentation.swift, ChapterCache.swift, CachedChapter+TranslationFreshness.swift, ReaderView.swift
(getPretranslatedSnapshot), .claude/rules/tts.md, .claude/rules/reader-text-pipeline.md.

Chưa kiểm: máy Windows — chưa build, chưa chạy trên máy; check_architecture.py chỉ còn vi phạm có sẵn (JSDom.swift).

## [1.3.1001] - 2026-11-19

### fix: NSFW chỉ tắt công tắc chung khi mở lại app, chặn nhập file quy tắc mục lục rỗng, ô tiêu đề thu gọn không chiếm chỗ

Sửa theo review phản biện của đợt 1.3.982–1.3.1000.

- **NSFW khi rời app** (anh Bửu chọn "Tắt khi mở lại app"): bản 1.3.985 tắt công tắc NSFW chung ngay lúc vào nền ⇒ khoá máy lúc đang xem phim 18+ thì phim tắt tiếng + thu vào hub (guard NSFW của phiên phim), playlist toàn mục 18+ dừng sau bài hiện tại, Reader truyện nguồn 18+ bị đóng (Chi tiết có `closesWhenNsfwHidden`), và tranh thứ tự với luồng rời app của `VideoLeaveToHubCoordinator`. Nay `ShelfNsfwFilterState`: vào nền ⇒ chỉ Kệ về "Không hiển thị NSFW" ngay (ảnh màn chuyển app không lộ); `willEnterForeground` ⇒ mới tắt công tắc chung; trong lúc ở nền ngưng đồng bộ từ công tắc chung. Nút Home vẫn tắt cả hai ngay.
- **Quy tắc mục lục**: nhập file `[]` bị chặn (toast lỗi) — "Thay thế toàn bộ" không còn thêm lại quy tắc mặc định (1.3.988) nên file rỗng sẽ xoá sạch quy tắc, nhập truyện TXT không tách được chương (`TOCRulesConfigView`).
- **Tiêu đề thu gọn** (1.3.984): ô `topBarLeading` chỉ dựng khi tiêu đề lớn đã thu — trước đó chữ trong suốt rộng tới 230pt luôn chiếm góc trái, có thể đẩy nút back tự dựng của trang con trong sheet (`HubStyleActionSheet`, `NotificationInboxView`) và chen cụm nút phải trên máy hẹp.
- Tài liệu: `ui-conventions.md` mục Màn danh sách (bỏ bút chì, chạm hàng = sửa; nhập dữ liệu qua `.dataImportModePopup`, ngoại lệ lọc rác); chú thích popup bỏ "lọc rác" khỏi danh sách màn dùng popup; 19 entry CHANGELOG cũ nhất (1.3.951–1.3.970) chuyển sang `CHANGELOG.archive.md`.
- Kiểm: chỉ đọc code, **không build tại chỗ (Windows), chưa chạy trên máy**.

## [1.3.1000] - 2026-11-19

### fix: Dịch lại khi đang nghe chờ lượt dựng chương đang chạy, tua đoạn huỷ lượt chuyển chương, Reader không rơi bản dựng chờ mốc

Vá ba khe hở của hai commit trước (rà lại sau khi viết, chưa gặp trên máy):
- TTSManager+Retranslation: chỉ chờ startSpeakingTask / chapterAdvanceTask trước khi dịch lại ⇒ người dùng đọc lại
  chương ("Nghe từ đây", bật/tắt dịch, rereadCurrentChapter) trong lúc tải / dịch / chờ panel thì lượt nối chèn vào
  mảng chunk sắp bị thay, tiếng nạp trước theo phiên mới có thể sống sót với chữ sai. Nay chờ lượt dựng đang chạy
  (awaitChapterBuildsInFlight, lặp nếu có lượt mới chen vào) cả trước khi dịch lẫn ngay trước khi nối.
- TTSManager+ParagraphSeek: tua lúc vừa đọc hết chunk cuối và chương kế đang tải / tổng hợp ⇒ lượt chuyển chương vẫn
  qua mọi kiểm tra rồi nhảy sang chương sau giữa đoạn vừa tua tới. Nay seekToParagraph huỷ lượt chuyển chương
  (cancelChapterAdvanceTask — private ⇒ internal) + đóng đo AutoAdvance như pause().
- ReaderViewModel+TranslationPresentation: nhả panel mà TTS đang nối ⇒ bản dựng chờ mốc tối đa 3 s; panel mở lại
  trong lúc chờ thì bản dựng bị bỏ và không ai dựng lại (ReaderView đã thôi hoãn) ⇒ chương kẹt chữ cũ. Nay trả bản
  dựng về hàng chờ (translationPresentation.pending) để lần đóng panel sau áp.

Chưa kiểm: máy Windows — chưa build, chưa chạy trên máy; check_architecture.py chỉ còn vi phạm có sẵn (JSDom.swift).

## [1.3.999] - 2026-11-19

### feat: Sheet nghe mini kéo vạch tiến độ để tua theo đoạn, số N/M đếm theo đoạn

Trước: vạch tiến độ của sheet điều khiển nhanh TTS chỉ để xem (ProgressView), "N/M" đếm chunk
(currentParagraphIndex + 1 / paragraphs.count — tính cả chunk tên chương và chunk con của NghiTTS / VieNeu).

Nay (anh Bửu: "cho thanh tiến độ đọc trên sheet nghe truyện mini có thể kéo để tua được, không tua thời gian mà
tua theo đoạn", duyệt mockup):
- TTSQuickControlNowReading: "N/M" theo đoạn = dòng cha (M = số paragraphIndex ≥ 0 khác nhau, N = thứ tự dòng
  đang đọc; đang đọc tên chương ⇒ 0/M). Danh sách đầu đoạn (outline: id dòng + câu chunk đầu) dựng lại theo
  phiên / chương / số chunk / layoutRevision của lượt nối bản dịch — kéo không đọc TTSManager mỗi nhịp.
- TTSParagraphSeekBar (mới): cử chỉ theo mẫu VideoSeekBar (chạm là nhảy núm, kéo theo tay, thả mới báo), màu
  như vạch cũ (phần đã đọc theo màu nhấn, núm trắng), bong bóng "Đoạn N/M" trên núm lúc kéo.
- TTSQuickControlNowReadingBlock (mới, tách khỏi TTSQuickControlSheet): lúc kéo câu đầu của đoạn đích thay dòng
  trích; thả tay ⇒ seek; thả lại đúng đoạn đang đọc ⇒ không làm gì. Dưới vạch giữ badge nhiệt / dự phòng / engine
  / RTF bên trái, "N/M" bên phải.
- TTSManager+ParagraphSeek (mới): seekToParagraph(lineId:) nhảy tới chunk đầu của dòng, khuôn skipForward nhưng
  chạy cả khi tạm dừng: dừng phát hiện tại, huỷ task phát Nghi / remote + lượt đọc song song dự phòng (để
  resume không chờ task chết), NghiTTS / VieNeu huỷ refill ngoài cửa sổ (cancelNghiRefill) và bỏ tiếng đã nạp
  ngoài cửa sổ; đặt chỉ số, highlightRange = nil, checkpointProgress; đang phát ⇒ speakCurrent, đang dừng ⇒
  publishLifecycleState + Now Playing, không tự phát. Log ⏩ [TTSSeek]. Màn khoá không đổi.
- TTSManager.checkpointProgress() private ⇒ internal (file mới gọi).
- Ghi chú luật: .claude/rules/tts.md (mục widget TTS).

Chưa kiểm: máy Windows — chưa build, chưa chạy trên máy (cử chỉ kéo trong sheet có tranh với vuốt đóng sheet
không, vị trí bong bóng ở hai đầu vạch); check_architecture.py chỉ còn vi phạm có sẵn (JSDom.swift).

## [1.3.998] - 2026-11-19

### feat: Sửa rule / VP / Name lúc đang nghe ⇒ TTS đọc bản dịch mới từ đoạn sau đoạn đang đọc, highlight không lệch

Trước: sửa từ điển (VP / Name…) hay rule dịch lúc truyện đang nghe thì TTS chỉ bỏ bản chuẩn bị sẵn
(invalidatePreparedTranslationState) — phần còn lại của chương vẫn đọc bản cũ, trong khi Reader dựng lại cả
chương theo bản mới ⇒ chữ TTS đọc khác chữ Reader hiện, vệt highlight lệch tới hết chương.

Nay (anh Bửu: "áp dụng bản dịch mới từ đoạn sau của đoạn đang nghe — đoạn sau không phải chunk sau; highlight
phải đúng"):
- TTS (TTSManager+Retranslation): hai observer cũ ở init chuyển ra installTranslationChangeObservers() (vẫn bỏ
  bản chuẩn bị sẵn ngay). Có phiên (đang phát hoặc tạm dừng) + truyện bật dịch ⇒ gộp sự kiện 400 ms (rule riêng
  truyện bắn cả hai thông báo), chờ startSpeakingTask / chapterAdvanceTask đang chạy, tải chương thô qua
  ChapterContentRepository rồi dựng lại bằng cùng processChapterWithEngine với cờ của phiên (bộ dịch tiện ích
  chạy lại qua cache RAM).
- Nối trong một nhịp main (TTSManager+RetranslationSplice): mốc L = dòng của chunk xa nhất đã cam kết tiếng
  (chunk đang đọc / đang chuẩn bị; NghiTTS / VieNeu thêm currentItem + nextItem của hàng đợi — chunk kế đã hẹn
  giờ phát trên phần cứng, huỷ là cắt tiếng). Chunk của dòng ≤ L giữ nguyên ⇒ currentParagraphIndex không đổi,
  tiếng không cắt; chunk dòng > L lấy từ bản mới (cùng NghiUtteranceSegmenter.expand). Tiếng nạp trước chỉ bỏ ở
  chỉ số có chữ / kiểu ranh giới đổi (preloadedData, task nạp trước — task gộp Google phủ chỉ số đổi thì huỷ cả
  task —, lượt / dấu dự phòng qua TTSOnlineFallbackState.forgetChunks(_:session:chapterIndex:) mới, refill Nghi
  ⇒ cancelNghiRefill nếu dính chỉ số đổi) rồi updatePrefetchWindow. Không đổi sessionID /
  ttsProcessingGeneration, không xoá cả bộ đệm.
- Hàng rào so chữ chunk trước khi ghi tiếng nạp trước: startPrefetchTask, nạp gộp Google (rawTexts), lượt thử
  online của giọng dự phòng, refill NghiTTS — vì speakCurrent đọc preloadedData[index] không kiểm chữ.
- chapterContent / normalizedChapterText thành bản trộn (dòng ≤ L chữ đang đọc, sau đó chữ mới) để
  resumeAfterSettings không đưa bản cũ quay lại; chapterTitle giữ (chunk tiêu đề không bị thay).
- Mốc TTSRetranslationCoordinator (Services/TTS/Retranslation, mới): token, L, các dòng ≤ L mà chữ TTS khác
  bản mới, contentStamp (TTS dựng lại chương ⇒ mốc hết hiệu lực), layoutRevision cho sheet nghe mini.
- Reader (ReaderViewModel+TTSRetranslation, mới): applyPreparedTranslation áp mốc cùng token — dòng ≤ L hiện
  đúng chữ TTS đọc (giữ đoạn đang hiện nếu trùng, không thì dựng từ chữ TTS, span rỗng), dòng sau dùng bản mới.
  processAndSaveChapter chờ mốc tối đa 3 s khi TTS đang dịch lại đúng chương; mốc tới muộn ⇒ nắn lại cache.
  Panel / menu chọn chữ đang mở (Reader hoãn dựng lại, còn chữ cũ) ⇒ setTranslationRefreshDeferred giữ lượt nối
  của TTS tới khi đóng.
- Sheet nghe mini làm mới "N/M" khi chương được nối lại.
- Log: 🔁 [TTSRetranslate] (L, splice, số chunk cũ / mới / đổi, số dòng giữ chữ cũ, ms).
- Ghi chú luật: .claude/rules/tts.md, .claude/rules/reader-text-pipeline.md.

Khác thiết kế đã duyệt: mốc tính cả chunk đã xếp sẵn trong hàng đợi Nghi (có thể thuộc dòng kế) ⇒ với
NghiTTS / VieNeu bản mới có thể áp từ dòng sau nữa; Reader dùng chữ TTS cho dòng ≤ L thay vì luôn giữ đoạn cũ
(đúng cả khi Reader bỏ lỡ một lượt sửa); panel đang mở thì TTS chờ đóng mới nối.

Chưa kiểm: máy Windows — chưa build, chưa chạy trên máy; check_architecture.py chỉ còn vi phạm có sẵn
(JSDom.swift).

## [1.3.997] - 2026-11-19

### fix: Gộp / sửa thẳng từ điển gốc dừng lại khi đọc từ điển cũ không trọn — không ghi đè làm mất mục

Thuộc việc 6–7 (thẻ Từ điển chung "Gộp" / "Chỉ thêm key mới", danh sách Phiên âm / Pronouns sửa thẳng).
Trước (hai commit vừa rồi): GlobalDictionaryImporter đọc từ điển gốc đang có bằng allEntries() mà không so với wordCount, và nếu VietPhrase.dat / Names.dat / Pronouns.dat có trên máy nhưng không mở được thì lùi sang .txt hoặc danh sách rỗng — rồi ghi lại **cả** từ điển gốc từ danh sách đó ⇒ có thể mất mục (mỗi lần lưu ở danh sách Pronouns lại ghi lại cả Pronouns.dat).
Nay: như GlobalDictionaryTextExporter, số mục duyệt được phải khớp wordCount (cả cây đã nạp lẫn .dat đọc từ đĩa), lệch ⇒ báo lỗi enumerationMismatch, không ghi; .dat có mà không mở được ⇒ lỗi unreadableBase, không lùi sang .txt / rỗng. Toast lỗi ở thẻ / danh sách như các lỗi nhập khác.

File: Services/Translation/Manager/GlobalDictionaryImporter.

Chưa kiểm: chưa build, chưa chạy máy.

## [1.3.996] - 2026-11-19

### feat: Nhập từ điển và rule dịch luôn chọn 3 cách qua popup — Thay thế toàn bộ / Gộp / Chỉ thêm key mới

Trước: danh sách VP / Name (Chung + Riêng) nhập file rồi mới hỏi 2 lựa chọn (Thay thế / Gộp) bằng hộp thoại dictionaryModeDialog; "Nhập từ truyện khác" / "Chia sẻ sang truyện khác" (từ điển và bộ rule riêng) cũng chỉ 2 lựa chọn (callback isMerge); danh sách rule 3 bộ và nhập danh sách rule tắt chọn file trước rồi mới hỏi chế độ bằng confirmationDialog; không có "Chỉ thêm key mới" cho từ điển.
Nay: mọi chỗ nhập dùng popup chung `.dataImportModePopup` (hợp đồng d0929e34) — chọn 1 trong 3 chế độ **trước**, nút cuối mở bộ chọn file (onConfirm chạy sau khi popup đóng hẳn):
- Danh sách VP / Name: Nhập file; "Nhập từ truyện khác" (confirmTitle "Nhập") và "Chia sẻ sang truyện khác" (confirmTitle "Chia sẻ") — BookImportSourceSheet / BookShareTargetSheet trả DataImportMode thay cho isMerge, popup hiện sau khi chọn truyện.
- TranslationDictionaryWriter.importEntries(mode:) (thay isMerge), trả ImportCounts (thêm / cập nhật). Thêm "Chỉ thêm key mới" (.keepExisting): riêng truyện ⇒ mục chưa có lên đầu, mục cũ giữ nguyên; lớp Chung ⇒ tombstone (`từ=`) coi là khoá đã có — từ đã xoá trên máy vẫn xoá dù file có nghĩa, tombstone của file chỉ thêm khi máy chưa có khoá đó. "Gộp" giữ đúng luật cũ (Chung: mục sống của file khôi phục từ đã xoá). DictionaryCache.importEntries(mode:) trả số liệu; BookSourceMigrator (Đổi nguồn) đổi isMerge: true ⇒ mode: .overwriteExisting, hành vi không đổi.
- Danh sách rule (chung / tên chương / riêng): Nhập file rule và Nhập file rule tắt đều popup trước; bỏ hai confirmationDialog chọn chế độ. Chia sẻ bộ rule riêng nhận đủ 3 chế độ (trước chỉ Thay thế / Gộp).
- Toast sau khi nhập ở tầng View: "thêm X, cập nhật Y" (Thay thế toàn bộ ⇒ số mục mới / "thay toàn bộ"); số liệu rule lấy từ importPreview trước khi ghi (QuickTranslationRuleTransfer.sharePreview mới cho chia sẻ bộ riêng). Danh sách rule tắt chỉ có khoá: "Gộp" và "Chỉ thêm key mới" cùng kết quả, vẫn hiện đủ 3.
- Bỏ DictionaryImportModeDialog.swift (dictionaryModeDialog) — đã grep, không còn ai dùng. Chỗ "Lưu tên AI" (ReaderAINameReviewSheet) không phải nhập — giữ nguyên.
(5 thẻ Từ điển chung và hai danh sách Phiên âm / Pronouns đã dùng popup từ hai commit trước.)

File: Services/Translation/Manager/TranslationDictionaryWriter, Services/Translation/Utils/DictionaryCache, Services/Translation/Engine/QuickTranslationRuleTransfer, Services/Download/BookSourceMigrator (chỉ đổi tham số, ngoài phân hệ dịch), Views/Dictionary/{DictionaryListView, DictionaryListView+Transfer, BookImportSourceSheet, BookShareTargetSheet, DictionaryImportModeDialog (xoá)}, Views/Settings/Translation/{QuickTranslationRuleIOMenu, QuickTranslationRuleIOMenu+DisabledActions, QuickTranslationRuleListView}, .claude/rules/translation.md.

Chưa kiểm: chưa build, chưa chạy máy — cần thử popup (fullScreenCover) mở đúng từ trong sheet chọn truyện và từ ngăn kéo, rồi bộ chọn file mở sau khi popup đóng. Không đọc / chạy Tests/ nên chưa biết test nào còn gọi importEntries(isMerge:).

## [1.3.995] - 2026-11-19

### feat: Danh sách Phiên âm và Pronouns — sửa thẳng từ điển gốc từ thẻ PhienAm.txt / Pronouns.txt

Trước: PhienAm (ChinesePhienAmWords.txt) và Pronouns (Pronouns.dat) chỉ thay được bằng cách nhập cả file; không xem / sửa / xoá được từng mục; thẻ của hai từ điển này không có mục Sửa.
Nay:
- Thẻ PhienAm.txt / Pronouns.txt › Sửa ⇒ BaseDictionaryListView (mới), kiểu hàng VP/Name: dòng 1 .headline từ gốc, dòng 2 .subheadline nghĩa màu phụ, icon [Xoá]; chạm thân hàng ⇒ sheet sửa (BaseDictionaryEntrySheet mới: Từ gốc + Nghĩa, nút Lưu chữ ở header, vuốt xuống hỏi bỏ thay đổi, nền kính); "+" nổi .floatingAddButton thêm mục; ngăn kéo "…" có Nhập file (popup 3 cách nhập ⇒ GlobalDictionaryImporter) / Xuất file (GlobalDictionaryTextExporter); .backPageTitle; ô tìm .searchable(..., placement: .navigationBarDrawer(displayMode: .always), prompt:).
- Lưu / xoá sửa thẳng cả file: actor GlobalDictionaryEditor (mới) đọc từ điển gốc, đổi, ghi lại qua GlobalDictionaryImporter.writeBase (Pronouns dựng lại .dat vì .txt đã bị xoá sau lần nạp đầu; PhienAm ghi lại file text), nạp lại **riêng** từ điển đó (TranslationManager+BaseDictionaryReload mới: reloadPronounsDictionary / reloadPhienAmMap — không nạp lại cả bộ), rồi TranslateUtils.clearCache + notifyDictionariesDidUpdate để Reader / TTS dịch lại.
- PhienAm vài chục nghìn dòng: nạp một lần sắp theo khoá, lọc trên RAM, List hiện theo lượt 200 hàng (nạp sớm khi còn 50 hàng).
- GlobalDictionaryImporter tách phần ghi thành writeBase / baseEntries dùng chung; TranslationManager.loadPhoneticMap thành internal.

File: Services/Translation/Manager/{GlobalDictionaryEditor (mới), TranslationManager+BaseDictionaryReload (mới), GlobalDictionaryImporter, TranslationManager}, Views/Dictionary/{BaseDictionaryListView (mới), BaseDictionaryEntrySheet (mới)}, Views/Settings/Translation/{GlobalDictionaryCardController, GlobalDictionaryCardPresentations}, .claude/rules/translation.md.

Chưa kiểm: chưa build, chưa chạy máy. Mỗi lần lưu PhienAm ghi lại cả file (~vài chục nghìn dòng) — chưa đo thời gian trên máy. Ghi lại PhienAm sắp theo khoá nên comment / thứ tự dòng của file gốc không giữ.

## [1.3.994] - 2026-11-19

### feat: Thẻ Từ điển chung dạng menu thả xuống — Sửa / Nhập / Xuất / Làm mới / Xoá, thêm thẻ Rule dịch

Trước: Cài đặt dịch thuật › Từ điển chung có 4 thẻ (sau khi gỡ LuatNhan): chạm thẻ = nhập ghi đè thẳng (chọn file là thay toàn bộ), icon ↑ phủ cuối thẻ = xuất TXT; nút "Làm mới dữ liệu dịch" riêng ở dưới; không xoá được từ điển gốc, không có thẻ cho rule dịch.
Nay:
- 5 thẻ VietPhrase.txt / Name.txt / PhienAm.txt / Pronouns.txt / Rule dịch (ô thứ 5 thay ô LuatNhan; trạng thái "N rule"). Icon cuối thẻ là ellipsis dọc; cả thẻ là Menu hệ thống thả xuống (anh Bửu: "đừng mở ngăn kéo, mockup lại kiểu dropdown" — ngoại lệ có chủ ý so với luật menu ba chấm = ngăn kéo): Sửa, Nhập file, Xuất file, Làm mới dữ liệu, nhóm riêng Xoá (destructive).
- Sửa: VietPhrase / Name ⇒ đẩy DictionaryListView Chung tương ứng; Rule dịch ⇒ đẩy QuickTranslationRuleListView bộ chung (navigationDestination(item:)). PhienAm / Pronouns chưa có mục Sửa (commit sau).
- Nhập: popup 3 cách (dataImportModePopup) rồi mới mở bộ chọn file. Từ điển: "Thay thế toàn bộ" = đường cũ TranslationManager.importDictionary; "Gộp" (trùng lấy mới) / "Chỉ thêm key mới" (trùng giữ cũ) = GlobalDictionaryImporter (Service mới): đọc từ điển gốc đang có (cây đã nạp ⇒ .dat ⇒ .txt; PhienAm: bản đồ đã nạp ⇒ ChinesePhienAmWords.txt), trộn, dựng .dat mới bằng DoubleArrayTrieBuilder.build(fromEntries:) vào file tạm rồi thay file cũ (xoá .txt cùng tên nếu còn), PhienAm ghi lại file text (sắp theo khoá, sau thắng như loadPhoneticMap); chạy nền, thẻ hiện vòng quay, xong nạp lại + báo đổi từ điển. Rule dịch: QuickTranslationRuleStore.importRules(text:mode:). Toast "thêm X, cập nhật Y" (thay toàn bộ ⇒ số mục mới).
- Xuất: từ điển như cũ (GlobalDictionaryTextExporter); Rule dịch = một file đã bỏ rule tắt (QuickTranslationRuleExporter, bộ chung).
- Làm mới dữ liệu: một hàm refreshTranslationData dùng chung cho mục của mọi thẻ và nút "Làm mới dữ liệu dịch".
- Xoá: hộp xác nhận nói rõ xoá gì — file gốc (.txt + .dat) của từ điển đó, các từ đã sửa ở VP / Name Chung giữ; Rule dịch = xoá bộ rule chung (deleteRules()).
- Bỏ TranslationSettingsView+Export (thay bằng GlobalDictionaryCardController); DictionaryCard bỏ reservesExportSlot / isExporting.

File: Services/Translation/Manager/GlobalDictionaryImporter (mới), Views/Settings/Translation/{GlobalDictionaryCardController, GlobalDictionaryCardMenu, GlobalDictionaryCardPresentations (mới), DictionaryCard, TranslationSettingsView, TranslationSettingsView+Export (xoá)}, .claude/rules/translation.md.

Chưa kiểm: chưa build, chưa chạy máy. Cần thử trên máy: hai Menu trong cùng một hàng lưới Form nhận chạm riêng; gộp VietPhrase cỡ triệu mục (RAM + thời gian dựng .dat); popup → bộ chọn file mở đúng sau khi popup đóng.
Khác spec: bước "ghi .txt" khi gộp từ điển .dat được thay bằng dựng .dat thẳng từ danh sách đã trộn (không để .txt nằm cạnh .dat — loader chỉ xoá .txt khi tự biên dịch).

## [1.3.993] - 2026-11-19

### feat: Nút Thử rule ở đầu danh sách rule — sheet thử một câu áp đúng bộ đang xem, sửa thử bộ tên chương và bộ riêng

Trước: ô thử rule chỉ có ở trang "Thử nhanh một câu" (Quản lý rule dịch › Công cụ) và luôn chỉ áp bộ rule chung. QuickTranslationRuleEngine.preview không có bộ tên chương; mẫu của từng hit tra theo sourceLine **chỉ** trong bộ chung nên hit của bộ riêng hiện sai mẫu hoặc trống.
Nay:
- Danh sách rule (cả ba phạm vi: chung / tên chương / riêng truyện) có hàng pill "Thử rule" ở đầu (icon testtube.2, chữ màu nhấn, nền nhấn mờ 18%, viền 60%, chevron phải — kiểu chip ExtensionKindFilterBar). Chạm ⇒ sheet "Thử rule" (tiêu đề trái, detent 60% / lớn, thanh kéo, nền kính .appGlassSheet() ở chỗ trình bày): ô nhập câu + Chạy thử, KẾT QUẢ, RULE ĐÃ KHỚP (dòng · offset · bộ, mẫu, nguồn → kết quả).
- Ruột tách thành QuickTranslationRuleTesterPanel, dùng chung cho sheet mới và trang đẩy cũ (giữ link "Thử nhanh một câu"; trang này vẫn có chọn chế độ token). Chữ giải thích phạm vi + chế độ token chuyển vào nút "?" của tiêu đề section, đổi theo phạm vi.
- Sửa lỗi 1: preview(_:scope:mode:) (dời sang QuickTranslationRuleEngine+Preview; execute / nonEmpty thành internal) — danh sách tên chương thử với bộ tên chương + bộ chung như khi dịch tên chương thật.
- Sửa lỗi 2: danh sách riêng truyện thử với bookId của truyện (bộ riêng + chung, file tắt / token / thứ tự ưu tiên / bộ ngoặc của truyện), và QuickTranslationRewriteResult.Segment có thêm scopeRank (mặc định nil, engine gán ở assemble) ⇒ hit tra mẫu theo cặp (bộ, dòng), hiện đúng mẫu.

File: Services/Translation/Engine/{QuickTranslationRuleEngine, QuickTranslationRuleEngine+Preview (mới), QuickTranslationRewriteResult}, Views/Settings/Translation/{QuickTranslationRuleTesterPanel (mới), QuickTranslationRuleTesterSheet (mới), QuickTranslationRuleTesterPill (mới), QuickTranslationRuleTesterView, QuickTranslationRuleListView}, .claude/rules/translation.md.

Chưa kiểm: chưa build, chưa chạy máy. Danh sách tên chương / chung mở từ Reader (có contextBookId) vẫn thử không kèm bộ riêng của truyện đó — chỉ danh sách riêng truyện mới truyền bookId (UNKNOWN: anh Bửu có muốn thử ở danh sách tên chương mở từ Reader cũng kèm bộ riêng không).

## [1.3.992] - 2026-11-19

### feat: Hàng VP/Name, rule dịch, bộ ngoặc — bỏ icon bút chì, chạm thân hàng mở màn sửa

Trước: muốn sửa một mục ở danh sách VietPhrase / Names (Chung và Riêng), danh sách rule (chung / tên chương / riêng truyện) và danh sách Bộ ngoặc phải chạm icon bút chì nhỏ ở cụm icon cuối hàng; chạm thân hàng không làm gì.
Nay: chạm thân hàng (chữ + khoảng trống tới cụm icon) mở đúng màn sửa cũ (DictEntrySheet / QuickTranslationRuleEditorSheet / sheet sửa cặp ngoặc); icon bút chì bỏ. Vùng nội dung dùng .contentShape(Rectangle()).onTapGesture, không bọc cả hàng trong Button; các icon còn lại (Chuyển, Tắt/Bật, Xoá) chuyển sang .buttonStyle(.borderless), Menu "Chuyển" giữ .menuStyle(.borderlessButton) — chạm icon không mở màn sửa. Trợ năng: thêm thao tác "Sửa" (accessibilityAction) cho cả ba loại hàng. Hàng bộ ngoặc chỉ xem (truyện đang theo bộ chung) chạm không làm gì, không có thao tác Sửa.

File: Views/Dictionary/DictionaryEntryRow, Views/Settings/Translation/{QuickTranslationRuleEntryRow, QuickTranslationRuleBracketRow}.

Ngoài phạm vi (chưa sửa, theo dặn): .claude/rules/ui-conventions.md mục "Màn danh sách" vẫn ghi cụm icon [Sửa][Chuyển][Tắt/Bật][Xoá] — session chính cập nhật nếu muốn.
Chưa kiểm: chưa build, chưa chạy máy — cần thử chạm icon Chuyển/Xoá không lọt xuống màn sửa và cuộn danh sách không mở nhầm.

## [1.3.991] - 2026-11-19

### feat: Xuất rule dịch thành một file bỏ rule đang tắt — bỏ xuất danh sách tắt, gọn màn Quản lý rule dịch

Trước: "Xuất bộ rule" chép nguyên file rule (kể cả rule đang tắt) và tab Đã tắt có thêm "Xuất danh sách rule tắt" (file thứ hai); "Chia sẻ bộ rule riêng sang truyện khác" chép cả rule đang tắt; màn Quản lý rule dịch có section "Bộ rule" với ba nút Nhập file / Xuất bộ đang chạy / Xoá bộ rule khỏi máy (+ hộp chọn chế độ nhập, hộp xác nhận xoá).
Nay:
- QuickTranslationRuleExporter (Service mới): văn bản bộ rule của một phạm vi đã bỏ dòng có mẫu nằm trong file tắt của chính bộ đó (chung ⇒ file tắt chung, tên chương ⇒ file tắt tên chương, riêng ⇒ file tắt của truyện). Lọc từng dòng nên comment / thứ tự dòng giữ nguyên; mẫu lấy bằng QuickTranslationRuleParser.splitRuleLine rồi chuẩn hoá bằng QuickTranslationRuleDisableFile.normalizedPattern (hàm mới, chính là bước trim + bỏ nháy kép mà parse của file tắt vẫn dùng). Mọi rule đều tắt ⇒ không xuất file rỗng, báo toast.
- Ngăn kéo "…" của danh sách rule (cả ba bộ) xuất qua exporter; "Chia sẻ bộ rule riêng" (QuickTranslationRuleTransfer.shareBookRules) cũng chia sẻ bản đã lọc. Thẻ Rule dịch ở Cài đặt dịch thuật (commit sau) dùng chung hàm này.
- Bỏ mục "Xuất danh sách rule tắt" (tab Đã tắt còn: nhập file rule tắt, bật lại tất cả, xoá tất cả rule đã tắt).
- Màn Quản lý rule dịch: bỏ ba nút Nhập / Xuất / Xoá cùng importer, hộp chọn chế độ, hộp xác nhận xoá và hàm đi kèm; nút "Tải bộ rule mặc định" (chỉ hiện khi máy chưa có rule) và chữ giải thích của nó gộp vào section Trạng thái, không còn section "Bộ rule". Chữ "Cần tải lại thì xoá bộ rule…" và chữ trống của danh sách rule chung trỏ sang menu … của danh sách.

File: Services/Translation/Engine/{QuickTranslationRuleExporter (mới), QuickTranslationRuleDisableFile, QuickTranslationRuleTransfer}, Views/Settings/Translation/{QuickTranslationRuleIOMenu, QuickTranslationRuleIOMenu+DisabledActions, QuickTranslationRulesView, QuickTranslationRuleListView}, .claude/rules/translation.md.

Chưa kiểm: chưa build, chưa chạy máy. Mẫu trong file rule viết dạng có nháy kép bao ngoài mà không theo đúng regex `"mẫu" = "nghĩa"` của parser có thể cho khoá khác với khoá engine dùng — trường hợp hiếm, chưa thử.

## [1.3.990] - 2026-11-19

### feat: Cài đặt dịch thuật — giải thích của công tắc Quick Translate và Áp dụng rule dịch vào nút "?" cạnh tên

Trước: dưới tên "Bật dịch Quick Translate" và "Áp dụng rule dịch" luôn có một dòng chữ phụ giải thích (công tắc "Dịch Luật nhân hóa" đã bỏ ở commit trước).
Nay: dòng giải thích chuyển vào nút "?" (SectionHelpButton, popover) đứng ngay cạnh tên công tắc. Hàng dựng bằng HelpLabeledToggle (mới): HStack [tên][?] … [Toggle ẩn nhãn] — cố ý không đặt nút "?" trong nhãn của Toggle để chạm "?" không bật/tắt công tắc; nhãn trợ năng của công tắc vẫn là tên. Hàng "Áp dụng rule dịch" giữ thụt lề 16 như cũ.

File: Views/Settings/Translation/{HelpLabeledToggle (mới), TranslationSettingsView}, Views/Settings/Main/QuickTranslateRuleSettingsRows.

Chưa kiểm: chưa build, chưa chạy máy — cần xem trên máy popover "?" mở đúng trong hàng Form và chạm "?" không đổi công tắc.

## [1.3.989] - 2026-11-19

### feat: Gỡ từ điển LuatNhan khỏi dịch QT — bỏ công tắc Dịch Luật nhân hóa, tự dọn file và khoá cũ

Trước: dịch QT có thêm từ điển LuatNhan (Luật nhân hoá, mặc định tắt) — công tắc ở Cài đặt dịch thuật, Cài đặt trình đọc, Cài đặt dịch truyện tranh; thẻ LuatNhan.txt ở Từ điển chung; tải mặc định kèm luatnhan.txt; tra từ bôi đen trong Reader hiện dòng "Luật nhân"; sao lưu nhóm Từ điển chung gói LuatNhan.dat/.txt.
Nay: engine (VietPhraseTokenizer, TranslateUtils.lookupRawTranslation, TokenizeMemo, mapping memo, TranslationReadContext) không còn tra LuatNhan; ba công tắc, thẻ, mục tải mặc định, dòng tra từ và hai tên file trong sao lưu đều bỏ. Người chưa bật (mặc định) dịch y như cũ; khoá memo đổi dạng nên cache dịch cũ tự rụng.
Dọn sót: LuatNhanRetirement.removeLeftovers chạy đầu TranslationManager.loadAllDictionaries — còn translate/LuatNhan.dat / .txt hay khoá isTranslationLuatNhanEnabled thì xoá và ghi log "🧹 [LuatNhan]" (chỉ thấy khi đang bật ghi log; lỗi xoá file ghi ❌). Kiểm mỗi lần nạp nên không cần cờ "đã chạy". Khôi phục bản sao lưu cũ có LuatNhan ⇒ BackupDictionaryRestorer.restoreShared bỏ qua hai file đó, không báo lỗi; BackupSettingsArchiver chặn khoá cũ ở cả hai chiều.

File: Services/Translation/Manager/{LuatNhanRetirement (mới), TranslationManager, TranslationDictionaryState, TranslationReadContext, GlobalDictionaryTextExporter}, Services/Translation/Engine/VietPhraseTokenizer, Services/Translation/Utils/{TranslateUtils, TokenizeMemo}, Services/Translation/Extensions/TranslateUtils+MappingMemo, Services/Backup/{BackupPaths, BackupScope, BackupDictionaryRestorer, BackupSettingsArchiver}, Views/Settings/Translation/TranslationSettingsView, Views/Reader/{ReaderView, ReaderSettingsView, Extensions/ReaderView+Selection, Extensions/ReaderView+Suggestions (chỉ comment)}, Views/ComicReader/ComicTranslationSettingsSheet, Views/Dictionary/{ManageDefinitionsDraft, ManageDefinitionsView} (chỉ comment), .claude/rules/translation.md.

Chưa kiểm: chưa build (máy Windows), chưa chạy trên máy; không đọc / chạy Tests/ nên chưa biết test nào còn gọi API đã bỏ (isLuatNhanEnabled của TokenizeMemo, luatNhanDict…).

## [1.3.988] - 2026-11-19

### fix: Nhập quy tắc mục lục Thay thế toàn bộ không thêm lại quy tắc mặc định, công cụ tra cứu so trùng theo URL, lọc rác chỉ thêm mẫu mới không hỏi

Anh Bửu chốt 3 điểm còn ngỏ của commit nhập 3 lựa chọn: "Quy tắc mục lục không được thêm quy tắc mặc định khi Thay thế toàn bộ", "khoá Công cụ tra cứu là URL", "Lọc rác thì không có option như vậy, chỉ cần thêm từ không có vào thôi, phân hoa thường", "thay thế tts thì không phân hoa thường, key là từ gốc".

Trước (commit 159b5f17):
- Quy tắc mục lục — Thay thế toàn bộ dùng `TranslateUtils.replaceTOCRules`: thay bằng file rồi tự thêm lại quy tắc mặc định bị thiếu.
- Công cụ tra cứu — khoá so trùng là tên công cụ (không phân biệt hoa thường).
- Lọc rác — có popup 3 lựa chọn.
Nay:
- Quy tắc mục lục — Thay thế toàn bộ chỉ còn đúng danh sách trong file (`mergeTOCRules` lên danh sách rỗng, chỉ để chuẩn hoá chữ), không thêm lại quy tắc mặc định; muốn có lại thì dùng "Khôi phục mặc định". Nạp / lưu `toc_rules.json` không tự chèn mặc định khi file đã có (chỉ khi chưa có file), nên danh sách nhập giữ nguyên.
- Công cụ tra cứu — khoá so trùng là mẫu URL (bỏ khoảng trắng hai đầu, so đúng từng chữ), tên là giá trị: Gộp = cùng URL thì lấy tên trong file; Chỉ thêm key mới = cùng URL thì giữ tên cũ.
- Lọc rác — bỏ popup: "Nhập cấu hình (JSON)" mở bộ chọn file luôn, nhập chỉ thêm quy tắc có mẫu chưa có (so đúng từng chữ, phân biệt hoa thường), mẫu đã có giữ nguyên bản trên máy; toast "Đã nhập: thêm X, bỏ qua Y key đã có.". `JunkFilterManager.importRules(fromJSONString:)` bỏ tham số `mode`. Không còn cách ghi đè toàn bộ danh sách lọc rác bằng file.
- Thay thế ký tự TTS — giữ như 159b5f17: khoá là từ gốc (`TTSReplacementRule.matchKey`, không phân biệt hoa thường, giữ dấu).

File đã đụng: `Sources/Services/DataImport/TOCRuleImporter.swift`, `Sources/Models/Dictionaries/SearchEngineTransfer.swift`, `Sources/Views/Settings/Search/SearchEnginesConfigView.swift` (chú thích), `Sources/Services/ChapterText/JunkFilterManager.swift`, `Sources/Views/Settings/Translation/JunkFilterManagementView.swift`.

Chưa kiểm: không build được (máy Windows), chưa chạy trên máy. Chú thích của `DataImportModePopupModifier` (khung chung) còn kể "lọc rác" trong danh sách màn dùng popup — file của session chính, chưa sửa.

## [1.3.987] - 2026-11-19

### feat: Nhập dữ liệu ở 6 màn TTS và cài đặt luôn có 3 lựa chọn — Thay thế toàn bộ, Gộp, Chỉ thêm key mới

Anh Bửu: "nhập luôn có 3 option: thay thế toàn bộ (xoá danh sách cũ và chỉ giữ lại mới), gộp (vế trái trùng thì đè lên, chưa có thì thêm vào), chỉ thêm vào những key chưa có của vế mới" — popup giữa màn, 3 radio có mô tả, cuối là nút "Nhập file" (đã duyệt mockup).

Trước: mỗi màn nhập một kiểu — phiên âm NghiTTS luôn ghi đè toàn bộ không hỏi; phiên âm VieNeu luôn trộn không hỏi; thay thế ký tự TTS, lọc rác, quy tắc mục lục, công cụ tra cứu chọn file trước rồi hỏi Gộp / Ghi đè bằng confirmationDialog (có đoạn xem trước số đếm), và chữ "Gộp" mang hai nghĩa ngược nhau tuỳ màn (lọc rác, mục lục = đè key trùng; thay thế TTS, công cụ tra cứu = giữ bản cũ).
Nay: hàng "Nhập…" trong ngăn kéo … mở popup `.dataImportModePopup` (khung của commit d0929e34, mặc định chọn Gộp) ⇒ bấm "Nhập file" ⇒ chọn file ⇒ nhập theo chế độ đã chọn ⇒ toast số đếm ("Đã nhập: thêm X, cập nhật Y[, Z mục trùng y hệt]" / "Đã nhập: thêm X, bỏ qua Y key đã có" / "Đã thay thế toàn bộ: N mục (trước có M)"). Bỏ các confirmationDialog Gộp / Ghi đè và phần xem trước số đếm (chọn chế độ trước nên số đếm chuyển sang toast). File sai định dạng vẫn báo như cũ (toast hoặc hộp thoại của từng màn).

Luật chung cho cả 6 màn (`KeyedImportMerger`, `Sources/Models/Dictionaries/KeyedImportMerger.swift` + `KeyedImportSummary.swift`, hàm thuần):
- Thay thế toàn bộ = chỉ còn các mục của file; Gộp = khoá trùng lấy giá trị mới (thay tại chỗ, giữ vị trí + id cũ), khoá mới nối cuối, khoá chỉ có trên máy giữ; Chỉ thêm key mới = khoá trùng giữ bản cũ, chỉ nối khoá mới.
- Khoá lặp trong file: bản đứng sau cùng thắng. Mục mang id trùng mục khác ⇒ cấp id mới (danh sách có id).

Khoá từng loại:
- Phiên âm NghiTTS: từ gốc bỏ khoảng trắng hai đầu + chữ thường (như `TextPreprocessor.updateWord`; trước đây nhập .plist / .json giữ nguyên khoá có chữ hoa ⇒ mục chết). Ghi qua `TextPreprocessor.replaceAllWords` (xoá luôn cache phiên âm — đường cũ ghi plist rồi `loadResources()` không xoá cache). File rỗng / không có khoá hợp lệ ⇒ báo lỗi, không còn xoá trắng từ điển.
- Phiên âm VieNeu: `VieNeuJapaneseDictionary.normalizedKey` (gấp dấu phụ + chữ thường), bỏ mục khoá hoặc cách đọc rỗng. Ghi qua `replaceAll`.
- Thay thế ký tự TTS: `TTSReplacementRule.matchKey` (mẫu chữ thường, giữ dấu). Áp cho tầng đang mở (chung hoặc riêng của truyện), ghi qua `importRules(fromJSONString:mode: .overwrite, bookId:)` sau khi gộp. "Khôi phục mặc định" giữ nguyên hộp thoại hai lựa chọn cũ.
- Lọc rác: `pattern` đúng từng chữ (như `addRule`), bỏ mẫu rỗng. `JunkFilterManager.importRules` nhận `DataImportMode`, trả `KeyedImportSummary?`; bỏ enum `JunkFilterImportMode`. Sửa kèm: bản Gộp cũ sắp lại danh sách theo ABC (thứ tự là thứ tự áp dụng ⇒ đổi kết quả lọc) và dựng `Dictionary(uniqueKeysWithValues:)` ⇒ sập khi danh sách sẵn có mẫu trùng — nay giữ thứ tự, không sập.
- Quy tắc mục lục: `id` (bỏ khoảng trắng). Thay thế toàn bộ = `TranslateUtils.replaceTOCRules` — vẫn **tự thêm lại quy tắc mặc định bị thiếu** như "Thay thế toàn bộ" cũ (quy tắc mặc định không xoá được ở màn này); Gộp = `mergeTOCRules` (= "Gộp theo ID" cũ); Chỉ thêm key mới = `mergeTOCRules` với các quy tắc có id chưa có. Logic ở `TOCRuleImporter`.
- Công cụ tra cứu: tên công cụ (bỏ khoảng trắng, không phân biệt hoa thường), mẫu URL là giá trị — trước đây "Gộp" so cặp tên + mẫu URL và giữ bản cũ, nên khoá cũ khiến Gộp và Chỉ thêm key mới gần như trùng nhau. `SearchEngineTransfer.imported(current:imported:mode:)`; `merged` giữ nguyên cho khôi phục sao lưu (`BackupConfigArchiver`); bỏ `newCount` (chỉ hộp thoại cũ dùng).

File đã đụng:
- Mới: `Sources/Models/Dictionaries/KeyedImportMerger.swift`, `Sources/Models/Dictionaries/KeyedImportSummary.swift`, `Sources/Services/DataImport/PhoneticDictionaryImporter.swift`, `Sources/Services/DataImport/TTSReplacementRuleImporter.swift`, `Sources/Services/DataImport/TOCRuleImporter.swift` (thư mục `Services/DataImport/` để không đụng `Services/TTS/**`, `Services/Translation/**` — chỉ gọi API công khai có sẵn).
- Sửa: `Sources/Services/ChapterText/JunkFilterManager.swift`, `Sources/Models/Dictionaries/SearchEngineTransfer.swift`, `Sources/Views/Settings/TTS/TTSDictionaryEditView.swift`, `Sources/Views/Settings/TTS/VieNeuJapaneseDictionaryView.swift`, `Sources/Views/Settings/TTS/TTSReplacementManagerView.swift`, `Sources/Views/Settings/TTS/TTSReplacementManagerView+Layer.swift`, `Sources/Views/Settings/Translation/JunkFilterManagementView.swift`, `Sources/Views/Settings/Translation/TOCRulesConfigView.swift`, `Sources/Views/Settings/Search/SearchEnginesConfigView.swift`.

Chưa kiểm: không build được (máy Windows) — chỉ đọc code + `check_architecture.py`; chưa chạy trên máy (popup mở từ ngăn kéo rồi bộ chọn file, nhất là ở màn mở dạng sheet: Thay thế TTS từ Cài đặt TTS / hub truyện, Công cụ tra cứu từ Reader). Cần chạy `xcodegen generate` vì có file / thư mục mới. Chưa đo nhập từ điển NghiTTS lớn (~30k mục) theo chế độ Gộp (gộp trên RAM rồi ghi một lần như đường cũ).
