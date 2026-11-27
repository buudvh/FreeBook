# CHANGELOG - Nhật ký Thay đổi CodeGraph Tàng Công Các

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **Tàng Công Các**.

## [1.3.1082] - 2026-11-27

### refactor: hợp đồng lọc name local có loại Thuật ngữ, bốn nhóm name và cửa vào model LAC

Bước đầu của đợt "Lọc name local bằng LAC" (anh Bửu duyệt 2026-11-27, plan `Docs/Plans/2026-11-27-loc-name-lac.md`, mockup https://claude.ai/artifact/Tx6oQ2Xd7KeaEybnnZ3cQq): chốt kiểu dữ liệu chung trước để ba phần (model LAC, bộ lọc + danh sách, giao diện + gói tạm) làm song song.

- `LocalNameFilter`: `Kind.term` (thuật ngữ); nhóm `Category` (Nhân danh / Địa danh / Tổ chức / Thuật ngữ) — `Kind.category`, `label` theo nhóm (tông môn + họ tộc ⇒ "Tổ chức"); `SuffixKind.term` + `SuffixKind.category`; `Configuration.categories` ("Loại cần tìm", mặc định cả bốn); `Event.preparingModel(fraction:)`; `Snapshot.knownCount` thay `hiddenKnownCount` — name đã có không còn bị ẩn, màn duyệt gắn badge NE / VP và bỏ chọn sẵn như luồng AI.
- `NameFilter/NER/`: `LACToken`, giao thức `LACTagging` (một dòng ⇒ các từ + nhãn, an toàn đa luồng), `LACModelError`, `LACModel.prepare(progress:)` (bản giữ chỗ). Model đã đẩy lên `datasets/raikiri1498/vietpharse` thư mục `lac/`, commit `73bb76d4`.
- Commit này một mình **chưa biên dịch được** (các `switch` trên `Kind` / `SuffixKind` / `Event` chưa có nhánh mới) — các phần sau của đợt bổ sung, chỉ push khi đủ.

## [1.3.1081] - 2026-11-27

### fix: nhận diện chữ Hán gồm cả khối mở rộng để panel Dịch điền đúng nghĩa chữ hiếm như 𫄸 thay vì chữ gốc

Anh Bửu thử 1.3.1080 (hết văng, 𫄸 thành một ô) và gửi ảnh: chọn riêng 𫄸 ⇒ ô nghĩa hiện nguyên "𫄸" trong khi chip có "huân" (VietPhrase Chung).

- **Nguyên nhân**: `TranslateUtils.translateTerm` chỉ tra từ điển khi `containsChinese` đúng, mà hàm này chỉ nhận U+4E00–9FFF ⇒ chữ khối mở rộng C trở đi bị trả nguyên văn (bấm "Cập nhật" lúc đó là lưu nhầm `𫄸=𫄸`). `VietPhraseTokenizer.isChineseCharacter` cũng chỉ có cơ bản + mở rộng A, B.
- **Sửa**: bảng dải chữ Hán dùng chung mới `ChineseCharacterClassifier` (`Services/Translation/Utils/`): cơ bản, mở rộng A, B–F + I, G–H, chữ tương thích (F900–FAFF, 2F800–2FA1F). `containsChinese` và `isChineseCharacter` cùng gọi vào đây.
- **Ảnh hưởng** (22 file gọi hai hàm này): chuỗi đã có chữ Hán cơ bản cho kết quả y như cũ; chỉ chuỗi mà chữ Hán **toàn** thuộc khối mở rộng / tương thích mới đổi từ "để nguyên" sang "được dịch / phiên âm" (chương, TTS, phụ đề, tên truyện…); token một chữ mở rộng không có trong từ điển giờ lùi về phiên âm Hán-Việt như chữ thường.
- `check_architecture.py` chỉ còn violation cũ `JSDom.swift`. Chưa build được tại chỗ (Windows); chưa thử trên máy.
- Dọn: entry 1.3.1051 chuyển sang `CHANGELOG.archive.md`.

## [1.3.1080] - 2026-11-27

### fix: panel Dịch không văng app khi thu hẹp cụm có chữ Hán hiếm như 𫄸, tách từ đếm đúng chữ, nút ‹ › và hàng chữ gốc theo trọn chữ

Anh Bửu: bôi đen 玄𫄸法衣 trong Reader ⇒ Dịch ⇒ bấm "Thu hẹp bên phải" ⇒ văng app. Ba crash log `.ips` cùng một stack: trap Swift trên luồng nền, đúng chỗ `ReaderDefinitionWorker.load` dịch lại cụm sau mỗi lần thu hẹp (bản Release không có dSYM nên kết luận từ đọc code). 𫄸 (U+2B138) nằm ngoài BMP: một chữ nhưng hai đơn vị UTF-16.

- **Nguyên nhân văng** — `VietPhraseTokenizer.tokenizeUncached`: chỉ số là chỉ số `Character` (`Array(text)`) nhưng trie trả độ dài khớp theo UTF-16 ⇒ mục từ điển chứa chữ ngoài BMP làm độ dài dư 1 mỗi chữ, cắt lấn sang chữ sau; cụm ngắn (panel dịch lại cụm đã thu hẹp qua `translateTerm`) thì vượt cuối mảng ⇒ sập. Sửa: chuỗi có ký tự dài ≠ 1 đơn vị thì dựng bảng offset UTF-16 từng ký tự, đổi độ dài trie ⇒ số ký tự (`characterCounts`), bỏ độ dài rơi giữa một ký tự; ngưỡng "cụm VP ≥ 2" tính theo chữ (một chữ ngoài BMP đứng lẻ từng lọt ngưỡng). Chuỗi toàn ký tự 1 đơn vị: kết quả y như cũ. Hệ quả: chương / TTS có chữ ngoài BMP khớp từ điển nay tách đúng (trước nuốt thêm chữ sau ⇒ dịch sai).
- **Token `<hv>`** (`QuickTranslationDictionaryToken.candidates`): chỉ nhận chữ dài đúng 1 đơn vị UTF-16 — chữ ngoài BMP không còn bị capture lấy nửa cặp surrogate.
- **Nút ‹ › nhích trọn chữ**: hàm chung mới `ComposedTextSelection` (`Sources/Common/Utils/`, dựa trên `rangeOfComposedCharacterSequence`) cho Reader (`ReaderView+Selection` — dùng chung panel Dịch / Xoá từ rác / Copy gốc), sheet Dịch truyện tranh (`ComicDefinitionSheet+Selection`) và màn Sửa từ (`DictEntryEditSheet`). Vùng chọn vẫn là `NSRange` UTF-16; chữ 1 đơn vị nhích y như trước.
- **Hàng chữ gốc mỗi chữ một ô** (`ComposedTextSelection.cells`): panel Dịch, Xoá từ rác, Copy gốc, màn Sửa từ — 𫄸 không còn vẽ thành hai ô vỡ; chạm một ô chọn trọn chữ đó.
- Ghi bất biến vào `.claude/rules/reader-text-pipeline.md`. `check_architecture.py` chỉ còn violation cũ `JSDom.swift`. Chưa build được tại chỗ (Windows); chưa thử trên máy.
- Dọn: entry 1.3.1050 chuyển sang `CHANGELOG.archive.md`.

## [1.3.1079] - 2026-11-27

### fix: gạch hàng name AI không mất khi đang có lượt AI chạy, Quản lý nghĩa không ghi lại Pronouns khi không sửa, màn Thêm báo rõ khi chỉ thêm phần đang chọn

Sửa sau lượt rà soát chéo đợt 1.3.1074–1078 (hai agent đọc code, không thấy lỗi biên dịch chắc chắn).

- **Gạch hàng name AI** (`ReaderAIFullScreenView.setNameStruck`): sửa cả bản phiên của lượt AI đang chạy (`AIRuntimeCoordinator.updateMessage`) — lượt đó ghi đè phiên xuống đĩa khi xong / mỗi lượt quét, nên gạch trong lúc đang quét hay chờ AI trả lời từng bị mất khi mở lại.
- Sửa một name thành khoá đang gạch ⇒ tự bỏ gạch khoá đó (`ReaderAINameReviewSheet+Edit`); VoiceOver "Sửa" không mở hàng gạch; gạch hết mọi hàng thì nút đầu thẻ là "Chọn hết" (không còn "Bỏ chọn" bấm không có tác dụng). Sửa comment còn nói "✕ xoá như cũ".
- **Quản lý nghĩa từ**: so bản gốc đã chuẩn hoá y như bản nháp (cùng tách + bỏ trùng) — nghĩa trùng sẵn trong file (vd Pronoun `ta/ta`) làm mở-rồi-đóng cũng ghi lại cả file Pronouns gốc + dựng lại `.dat` + dịch lại Reader.
- **Màn Sửa từ ở chế độ danh sách** (đuôi, "Không phải name", họ, token): chế độ Thêm chọn một phần chữ gốc ⇒ hiện "Chỉ thêm X (phần đang chọn)" thay vì lặng lẽ chỉ thêm phần đó; mở cao hết cỡ (`.large`) như form cũ để bàn phím không che nút "Thêm" và hàng Loại / Nghĩa đứng (VP / Name / Pronouns giữ nấc nửa màn).
- `check_architecture.py` chỉ còn violation cũ `JSDom.swift`. Không build tại chỗ (Windows).
- Dọn: entry cũ nhất chuyển sang `CHANGELOG.archive.md`.

## [1.3.1078] - 2026-11-27

### feat: danh sách duyệt name của AI gạch hàng kèm nút Hoàn tác thay cho xoá hẳn, mở lại vẫn còn gạch

Anh Bửu: "khi xóa từ trong danh sách của AI đừng xóa hẳn, xóa thì gạch hàng đó và chuyển thành nút hoàn tác", rồi chốt "mở lên lại thì vẫn còn gạch hàng + nút hoàn tác, cái bị gạch thì không chọn được". Chỉ màn duyệt của AI (nút xoá ở đó từng xoá hẳn dòng `từ=nghĩa` khỏi tin nhắn — lỡ tay là mất); màn duyệt của lọc name local giữ menu "Bỏ khỏi lần này / Không phải name".

- Thùng rác ⇒ **gạch** hàng: chữ gạch ngang + mờ, ô chọn bỏ chọn và khoá, chạm thân hàng không mở màn Sửa từ, nút thành ↶ Hoàn tác (xanh lá). Bấm ↶ ⇒ bỏ gạch. Đầu thẻ "· đã gạch N"; "Chọn hết / Bỏ chọn" bỏ qua hàng gạch; Lưu lọc bỏ hàng gạch (`ReaderAINameReviewCardView` `struckKeys` + `onToggleStrike`, `ReaderAINameReviewSheet`).
- Trạng thái gạch lưu theo **tin nhắn**: trường mới `AIChatMessage.struckNameKeys` (khoá = vế trái đã trim, optional — lịch sử cũ đọc như chưa gạch), ghi ngay mỗi lần gạch / bỏ gạch qua `AIChatHistoryStore.saveSession` (`ReaderAIFullScreenView.setNameStruck`, thay `removeNameLine`). `content` của tin **không** đổi nên mở lại sheet (kể cả sau khi tắt app) dựng lại danh sách như cũ rồi vẽ hàng gạch. Gạch theo từng tin.
- Không còn đường nào gọi `AIRuntimeCoordinator.forgetName` / `contentRemovingNameLines` từ sheet duyệt (để nguyên trong coordinator).
- `check_architecture.py` chỉ còn violation cũ `JSDom.swift`. Không build tại chỗ (Windows).
- Dọn: entry cũ nhất chuyển sang `CHANGELOG.archive.md`.

## [1.3.1077] - 2026-11-27

### fix: nút NE, VP, PN, R, C ở panel Dịch rộng cố định 30 pt để hàng nút không tràn trên máy 375 pt

Rà lại 1.3.1076 (chưa thử máy): nút loại / phạm vi đặt `minWidth: 30` + `maxWidth: .infinity` trong khi cụm aa…AA cũng giãn vô hạn ⇒ hai cụm hoà về độ co giãn, `HStack` có thể chia đôi cho cụm aa…AA trước ⇒ cụm NE | VP | PN · R | C thiếu ~11 pt ở panel 329 pt (máy 375 pt) và hàng tràn; đặt trần hữu hạn thì `HStack` bên trong lại chia cho cụm R | C trước ⇒ R / C rộng hơn NE / VP / PN.

- `ReaderDefinitionOverlayView+Rows.dictSegmentButton`: `.frame(width: segmentButtonWidth)` = 30 pt cố định — đúng mockup khung 1 anh Bửu chọn ("nút loại còn khoảng 30 pt"). Cụm nút cứng ⇒ đặt trước, cụm aa…AA nhận phần còn lại (~27 pt / nút ở 329 pt, giãn trên máy rộng). Trên máy rộng hơn 375 pt, NE / VP / R / C không còn giãn theo màn (trước 1.3.1076 rộng ~36–47 pt).
- Sửa chữ entry 1.3.1076: lưu PN đổi chip / bảng tra ngay, còn **chữ dịch** chỉ đổi ở chỗ có rule `<pn>` khớp (tách từ không tra Pronouns từ 1.3.1016 — luật đó giữ nguyên).
- Dọn: entry 1.3.1047 chuyển sang `CHANGELOG.archive.md`. Chưa build được tại chỗ (Windows); `check_architecture.py` chỉ còn violation cũ `JSDom.swift`. Bề ngang chưa đo trên máy.

## [1.3.1076] - 2026-11-27

### feat: panel Dịch lưu được vào Pronoun bằng nút PN cạnh NE và VP

Anh Bửu (plan `Docs/Plans/2026-11-27-pronoun-chip-dict-edit.md` ý 6): chọn **cách A** của mockup https://claude.ai/artifact/3LcrV8ViqPyhmg7wSYhE5W khung 1 — giữ một hàng; sau đó chốt "PN không ghim được".

- **Hàng định dạng + nơi lưu** (`ReaderDefinitionOverlayView+Rows`, dùng chung panel Dịch Reader và sheet Dịch của truyện tranh): `[aa Aa¹ Aa² Aa AA] | [NE|VP|PN] [R|C]`. Nút NE / VP / PN / R / C bề ngang tối thiểu 30 pt (máy 375 pt: cụm aa…AA tự co còn ~27 pt / nút, chữ aa…AA co tới 80% nếu thiếu chỗ; máy rộng hơn cả hai cụm giãn như trước).
- **Lựa chọn ba giá trị** `DefinitionSaveTarget` (mới: `.name` / `.vietPhrase` / `.pronoun`) thay `@State saveAsNameType: Bool` ở `ReaderView` và `ComicDefinitionSheet`. Ghim mặc định giữ nguyên `@AppStorage pinnedSaveAsNameType` (`Bool`, NE / VP) — PN không ghim được: `dictSegmentButton` nhận `onPin: nil` ⇒ tắt riêng cử chỉ nhấn giữ (`including: .subviews`), không badge, không rung, không toast. Mở panel / đổi vùng chọn vẫn lấy NE hoặc VP theo ghim (kể cả đang chọn PN mà nới vùng chọn — như NE / VP hiện nay).
- **Chọn PN ⇒ cụm R | C mờ 0,35**, không bấm / không nhấn giữ ghim được (`.disabled` + `.allowsHitTesting(false)`); lựa chọn R / C giữ nguyên, chọn lại NE / VP thì về như cũ.
- **"Cập nhật" với PN** (`DefinitionSaveTarget.save`): nghĩa chuẩn hoá như NE / VP (`DictionaryTextFileStore.normalizeMeaning`) rồi `GlobalDictionaryEditor.save` vào file Pronouns gốc — từ đã có ⇒ thay nghĩa; dựng lại `.dat`, nạp lại riêng Pronouns, xoá cache dịch, báo đổi từ điển (Reader / truyện tranh tra lại chip; chữ dịch chỉ đổi ở chỗ có rule `<pn>` khớp — tách từ không tra Pronouns từ 1.3.1016). Thành công ⇒ đóng panel y NE / VP — NE / VP vốn **không** có toast thành công nên PN cũng không; lỗi ⇒ "Không lưu được định nghĩa (Pronoun): …".
- `.claude/rules/translation.md` thêm phần panel Dịch vào đoạn "Pronoun trên chip nghĩa".
- Dọn: entry 1.3.1046 chuyển sang `CHANGELOG.archive.md`. Chưa build được tại chỗ (Windows); `check_architecture.py` chỉ còn violation cũ `JSDom.swift`. Bề ngang hàng nút chưa đo trên máy.

## [1.3.1075] - 2026-11-27

### feat: đuôi địa danh, Không phải name, Danh sách họ và token tùy chọn sửa bằng màn Sửa từ như từ điển

Anh Bửu (plan `Docs/Plans/2026-11-27-pronoun-chip-dict-edit.md` ý 1, mockup https://claude.ai/artifact/3LcrV8ViqPyhmg7wSYhE5W khung 4): "làm cái gì có vế trái là chữ Hán giống từ điển cũng làm kiểu edit của từ điển" — bốn danh sách `chữ Hán = …` bỏ form hai ô, thêm / sửa một mục mở **chính** màn Sửa từ `DictEntryEditSheet` (hàng chữ gốc chọn được ‹ › | chữ | ‹ ›, hàng token, ô nghĩa, chip nghĩa gợi ý, aa…AA, "Cập nhật", tra cứu ngoài, bút chì đổi chữ gốc).

- **Chế độ danh sách** (`DictEntryEditListMode` mới + `DictEntryEditSheet+List.swift`, tham số `listMode:` cuối init, mặc định `nil` ⇒ VP / Name / Pronouns / name AI chạy y như trước — ba chỗ gọi cũ không sửa): kiểm luật + trùng khoá qua store của từng danh sách, lỗi hiện đỏ ở dòng thông báo (ô trống không tô đỏ); store từ chối khoá đã có nên câu "sẽ bị ghi đè" + cảnh báo cam ẩn đi; lưu trả lỗi ⇒ sheet giữ nguyên. Khoá rỗng = thêm mới: tiêu đề "Thêm từ", ô gõ chữ gốc mở sẵn + focus, nút "Thêm". Chọn cả từ ⇒ cập nhật / đổi chữ gốc (`replacing` = khoá đang sửa); chọn một phần ⇒ thêm mục mới = phần đang chọn, mục đang sửa giữ nguyên ("Lưu thêm X, giữ nguyên Y"). Hàng phụ riêng của danh sách qua `extraRows` (sau aa…AA) + `isExtraDirty` (hỏi "Bỏ thay đổi?"). Không gắn truyện ⇒ không có ⚙ Quản lý nghĩa; chip lấy từ hàm chip dùng chung (có chip Pronoun của 1.3.1074).
- **Đuôi địa danh & tông môn** (`LocalNameFilterSuffixEditorSheet`): badge "Đuôi · Chung", khối **Loại** (Địa danh / Tông môn) + **Nghĩa đứng** (Trước tên / Sau tên, mục mới mặc định Sau tên, loại mặc định theo tab) và dòng "Ví dụ: 江海市 → …" đổi theo lựa chọn; giữ "Nghĩa gốc: …" khi nghĩa khác bản gốc và nút "Về bản gốc: …" cho đuôi gốc đã sửa.
- **Không phải name** (`LocalNameFilterBlocklistEditorSheet`, thay `LocalNameFilterBlocklistAddSheet`): chỉ hàng chữ gốc + hàng token, không ô nghĩa / chip / aa…AA. Hàng của danh sách nay chạm thân hàng = sửa cụm (trước chỉ xoá rồi thêm lại); đổi cụm qua `LocalNameFilterBlocklistStore.replace(_:with:)` mới — giữ chỗ và ngày thêm, trùng cụm khác ⇒ lỗi; cụm giữ nguyên ⇒ không làm gì, không toast.
- **Danh sách họ** (`QuickTranslationSurnameEditorSheet`): badge "Họ · Chung", ô nghĩa = âm Hán-Việt của họ, giữ nút "Về âm gốc: …".
- **Token tùy chọn** (`QuickTranslationCustomTokenEntryEditorSheet`): badge "<@tên> · Chung", ô nghĩa = nghĩa của từ.
- `onSave` của ba sheet đuôi / họ / token thêm tham số `replacing` (màn danh sách thôi tự lấy khoá của mục đang mở). Ghi chú: `.claude/rules/ui-conventions.md` (luật "Danh sách vế trái chữ Hán ⇒ màn Sửa từ"), `translation.md` (đoạn cùng tên + Danh sách họ / Token tùy chọn / Lọc name local).
- Dọn: entry 1.3.1045 chuyển sang `CHANGELOG.archive.md`. Chưa build được tại chỗ (Windows); `check_architecture.py` chỉ còn violation cũ `JSDom.swift`. Chưa thử máy.

## [1.3.1074] - 2026-11-27

### feat: chip nghĩa Pronoun viền tím, nhóm Pronoun trong Quản lý nghĩa từ, tách nghĩa Pronoun bằng | và chuẩn hoá | thành / một lần

Anh Bửu (plan `Docs/Plans/2026-11-27-pronoun-chip-dict-edit.md` ý 2–5, mockup https://claude.ai/artifact/3LcrV8ViqPyhmg7wSYhE5W khung 1–3 / 5): Pronoun thành lớp nghĩa ngang hàng NE / VP ở mọi chỗ tra / sửa nghĩa — đảo quyết định 1.3.721 "chip chỉ Name/VP". Ý 6 (nơi lưu PN ở panel Dịch) chưa làm, chờ anh chọn cách xếp.

- **Chip Pronoun** (`ReaderView.suggestionChips(from:)` — panel Dịch Reader, màn Sửa từ / Thêm từ): nguồn `"Xưng hô (Pronouns)"` của `dictionaryMatches`, nay là hằng `ManageDefinitionsDraft.pronounSource` và là mục thứ năm của `editableSources` ⇒ thứ tự Name Riêng → Name Chung → VP Riêng → VP Chung → **Pronoun** → Phiên âm. Category mới `SuggestionChipCategory.pronoun` viền tím (`rgba(191,90,242,0.7)` như mockup), chữ trắng, không badge R/C; nghĩa trùng chữ với chip đứng trước gộp vào chip đó. Sheet Tra từ điển của trình duyệt thêm nhóm "Pronouns" (chỉ hiện khi có nghĩa riêng của Pronoun). VoiceOver đọc thêm "Pronoun".
- **Tách nghĩa Pronoun thêm bằng `|`** (ngoài `/`, `¦`), chỉ Pronoun: chip và `ManageDefinitionsDraft.splitMeanings(_:source:)` (bản nháp + phép so lúc lưu cùng gọi ⇒ mục `a|b` không đụng tới thì không ghi lại). `<pn>` và danh xưng lọc name local vốn đã nhận `|`.
- **Quản lý nghĩa từ có nhóm "Pronoun · Chung"** sau VP Chung (`ManageDefinitionsView` / `ManageDefinitionGroupView`): thêm / sửa / xoá / đổi chỗ như nhóm khác. Đóng màn ⇒ nhóm đã đổi ghi thẳng file Pronouns gốc qua `GlobalDictionaryEditor` (`save` nối `/`, hết nghĩa ⇒ `delete`) — cùng đường danh sách Pronouns: dựng lại `.dat`, nạp lại riêng Pronouns, xoá cache dịch. Log lỗi lưu của màn này đổi `⚠️` ⇒ `❌`.
- **Chuẩn hoá một lần** (`PronounsSeparatorNormalization`, mới; cờ `pronounsPipeNormalizedV1`): `TranslationManager.init` gọi ngay sau lượt nạp từ điển đầu ⇒ `GlobalDictionaryEditor.normalizePronounSeparators()` (trong hàng đợi ghi) đổi mọi `|` trong nghĩa thành `/`, một ký tự đổi một ký tự — dòng, khoá, chữ nghĩa giữ nguyên; không mục nào có `|` ⇒ không ghi. Chưa có file ⇒ đánh dấu xong; lỗi ⇒ `❌`, lần mở sau thử lại. Log `📚 [Pronouns] Chuẩn hoá một lần | → /: đổi N / tổng` (dòng thường — log tắt lúc mở app nên lần chạy đầu thường không ghi). `GlobalDictionaryEditor` tách phần nạp lại sau khi ghi thành `reloadAfterWrite(type:)` dùng chung.
- Sửa comment / tài liệu cũ nói "Xưng hô không lên chip"; `.claude/rules/translation.md` thêm đoạn "Pronoun trên chip nghĩa + Quản lý nghĩa từ", làm rõ luật "Pronouns chỉ qua `<pn>`" là về đường dịch.
- Dọn: entry 1.3.1044 chuyển sang `CHANGELOG.archive.md`. Chưa build được tại chỗ (Windows); `check_architecture.py` chỉ còn violation cũ `JSDom.swift`. Chưa thử máy.

## [1.3.1073] - 2026-11-27

### fix: nút xoá ở danh sách duyệt name dùng thùng rác đỏ như danh sách từ điển

Anh Bửu (ngay sau 1.3.1072): "đổi thành nút xóa giống danh sách trong từ điển".

- `ReaderAINameReviewCardView.removeIcon`: ✕ tròn xám 22 pt ⇒ `trash` đỏ `.subheadline` y hàng `DictionaryEntryRow`; vẫn giữ vùng chạm 44 × 44 của 1.3.1072. Áp cho cả màn duyệt của AI và của lọc name local (luồng local bấm vẫn ra menu "Bỏ khỏi lần này / Không phải name").
- Không build tại chỗ (Windows).
- Dọn: entry 1.3.1043 chuyển sang `CHANGELOG.archive.md`.

## [1.3.1072] - 2026-11-27

### fix: nút ✕ ở danh sách duyệt name to bằng ô chọn, dễ bấm hơn

Anh Bửu: "danh sách name của AI có nút X nhỏ quá, tăng to lên cho tôi", màn duyệt của lọc name local cũng vậy (dùng chung `ReaderAINameReviewCardView`).

- ✕ mỗi hàng: icon `xmark.circle.fill` 14 pt ⇒ **22 pt** trong vùng chạm **44 × 44** — bằng ô vuông chọn bên trái; một view chung `removeIcon` cho cả nút xoá của luồng AI và menu "Bỏ khỏi lần này / Không phải name" của luồng lọc local (trước đó luồng AI không có khung chạm riêng, luồng local 28 × 36). Nút xoá luồng AI có thêm nhãn trợ năng "Bỏ …".
- Hàng bỏ đệm phải 8 pt: khung 44 pt của ✕ tự chừa lề, hai icon cách mép đều nhau.
- Không build tại chỗ (Windows).
- Dọn: entry 1.3.1042 chuyển sang `CHANGELOG.archive.md`.

## [1.3.1071] - 2026-11-27

### fix: lọc name local ghi rõ "cập nhật sau N chương", báo riêng khi dừng sớm, nạp lại tên chương bị huỷ dở, không lặp log danh sách hỏng

Sửa sau lượt rà soát chéo ba commit lọc name local (1.3.1068–1070; hai agent đọc code, không thấy lỗi biên dịch chắc chắn).

- Màn đang lọc: dòng phụ "cập nhật ở chương X" ⇒ "cập nhật sau X chương" — X là số chương **đã đọc trong lượt**, lọc từ giữa truyện vẫn đếm từ 1 (`LocalNameFilterProgressView`).
- Bấm "Dừng" trước khi đọc xong khối chương đầu ⇒ báo "Đã dừng trước khi đọc xong chương nào" thay cho "Không tìm thấy name mới · ẩn 0 name đã có" (`LocalNameFilterSession`).
- Đẩy màn quản lý danh sách trước khi nạp xong danh sách chương ⇒ task bị huỷ, tên chương chỉ mới phồn → giản chưa dịch; nay bỏ kết quả dở để `.task` nạp lại khi quay về (`LocalNameFilterSheet+Setup`).
- JSON của "Không phải name" / lớp riêng danh sách đuôi hỏng ⇒ dòng `❌` chỉ ghi **một lần** cho mỗi chuỗi hỏng (trước đây ghi mỗi lần đọc, mà sheet thêm / sửa đọc trong `body` ở từng phím gõ) (`LocalNameFilterBlocklistStore`, `LocalNameFilterSuffixStore`).
- `.claude/rules/translation.md`: thêm mục "Lọc name local — bộ lọc + luồng Reader" (đổi luật thì sửa bản Python trước, danh xưng / nghĩa đuôi theo quyết định của anh Bửu, `start` internal, `cancel()` có thể còn sự kiện tới muộn).
- `check_architecture.py` chỉ còn violation cũ `JSDom.swift`. Không build tại chỗ (Windows).
- Dọn: entry 1.3.1041 chuyển sang `CHANGELOG.archive.md`.

## [1.3.1070] - 2026-11-27

### feat: bộ lọc name local tự dò tên người, địa danh, tông môn ngay trên máy

Anh Bửu duyệt plan + mockup "Lọc name local" (2026-11-27). Phần A — bộ lọc (`Sources/Services/Translation/NameFilter/Engine/`, Services, không SwiftUI), kèm hợp đồng chung `LocalNameFilter.swift`; phần B (hai danh sách, 1.3.1068) và phần C (luồng Reader, 1.3.1069) ở hai commit trước.

- **Luật** chép từ bản thử Python `local_name_filter2.py` với `STRICT_TAIL = True`, `GLUE_SUFFIX = True`, `TITLE_MODE = "combine"`: hằng số / tập chữ (`LocalNameFilterRules`, sinh từ file `.py`, đã so số phần tử); sinh ứng viên + lượt 1 (`LocalNameFilterAccumulator`: đếm số lần **sinh** — không gộp lần sinh trùng —, loại `(kind, extra)`, số chương, phần đứng trước danh xưng 1 chữ); lượt 2 (`LocalNameFilterOccurrences`: số lần thật, chữ hai bên, đứng trước động từ nói, dính trái / phải / dính đuôi); `check()` đúng thứ tự luật (`LocalNameFilterRuleChecker`); `decide()` + luật gắn lại Nhân vật + "Không phải name" lọc ở **đầu ra** (`LocalNameFilterEngine`); nghĩa (`LocalNameFilterMeaningBuilder`: tên người viết hoa từng âm, danh xưng lấy nghĩa đầu trong Pronouns giữ nguyên chữ, đuôi theo danh sách đặt trước / sau, họ + 家 / 氏 / 族 âm viết thường). Tên lý do bỏ giữ đúng chuỗi Python (`glue_left`, `dict_common_word`, `user_blocked`…).
- Vòng nóng không dùng `String`: khoá cụm 1–5 chữ Hán `LocalNameFilterTermKey` (hai từ máy, so đúng code point như Python — `String` coi chữ tương thích `U+F900–FAFF` bằng chữ thống nhất), chữ đã đọc là một mảng UTF-16 nối các đoạn Hán bằng `\n` (= `joined` của Python), `text_count` đếm không chồng lấn theo chỉ mục vị trí của chữ đầu (`LocalNameFilterTextCounter`). Đo trên Đấu La (696 chương, 1,8 triệu chữ Hán): ~110 nghìn ứng viên, ~17 nghìn qua ngưỡng lượt 1.
- **Từ điển** chụp một lần lúc bắt đầu (`LocalNameFilterDictionaries`, từ `TranslationManager.shared`): "có trong VP" (luật glue) = khớp trọn ở VP riêng truyện / Chung đã sửa / gốc trừ từ đã xoá; `status` = có trong Name bất kỳ lớp (trừ `deletedNames`) ⇒ đã có, không thì nghĩa VP hiệu lực (riêng > Chung > gốc) có nghĩa đầu viết hoa ⇒ đã có, còn lại ⇒ từ thường; phiên âm `phienAmMap`; họ đang bật (`QuickTranslationSurnameStore.lookupTable`, bỏ họ chứa hư từ); Pronouns (chưa nạp ⇒ bỏ bước danh xưng, log một dòng). Chưa nạp VP gốc ⇒ `.failed("Chưa nạp từ điển VietPhrase — …")`.
- **`LocalNameFilterRun`**: đọc chương theo khối 24 (`LocalNameFilterChapterReader`: `BookBinManager.readChapterContents` một `FileHandle` mỗi khối + `ChineseTextPipeline.normalizeChapter` song song như `AINameScanTextLoader`), `.progress` mỗi khối, `.update` khi từ lần chụp trước đã qua ≥ max(1 s, 2 × thời gian lần đó), khối cuối chỉ chụp một lần ⇒ `.finished`; mỗi lần chụp phân tích lại toàn bộ phần đã đọc, không sửa trạng thái lượt 1 ⇒ kết quả cuối y như chạy một lần. `stop()` thôi đọc rồi phân tích nốt; `cancel()` / bên nghe thôi lặp ⇒ huỷ, không phát `.finished`. Chụp kiểm `Task.isCancelled` định kỳ; mọi việc ngoài main. Log một dòng `🔎 [LọcName] Xong…` (chương, chữ Hán, ms đọc / lượt 1 / lượt 2 / luật, số lần cập nhật, giữ, ẩn, lý do bỏ, số danh xưng); `❌` chỉ khi không đọc được chương.
- Khác hợp đồng: `LocalNameFilterRun.start` là `internal` (không `public`) vì `StoredChapterSnapshot` là kiểu `internal` — nơi gọi không đổi.
- Kiểm: một bản Python chép theo đúng cấu trúc code Swift cho kết quả **trùng từng hàng** (chữ Hán, nghĩa, loại, số lần, số chương, danh xưng, số bỏ theo lý do, số ẩn) với bản thử trên 5 truyện ở 4 chế độ (mặc định, có "Không phải name", ít nhất 2 lần, không có Pronouns). Khác cố ý so với bản thử: `status` dùng nghĩa đầu kiểu app (`TranslateUtils.getFirstMeaning`: tách `/ ¦ |`, mảnh đầu rỗng ⇒ từ thường; Python tách `/ | ;` bỏ mảnh rỗng) và tra thêm Name + từ điển riêng truyện; khoá Pronouns / họ chỉ nhận chữ Hán (khoá khác không bao giờ khớp chữ truyện). `check_architecture.py` chỉ còn violation cũ `JSDom.swift`. **Không build tại chỗ (Windows), chưa chạy trên máy.**
- Dọn: entry 1.3.1040 chuyển sang `CHANGELOG.archive.md`.

## [1.3.1069] - 2026-11-27

### feat: lọc name local trong Reader, hiện name ngay khi lọc và duyệt có "Không phải name"

Anh Bửu duyệt plan + mockup "Lọc name local" (2026-11-27). Phần C — luồng trong Reader (bộ lọc và hai danh sách ở hai commit riêng).

- Ngăn kéo "…" của Reader có hàng **"Lọc name local"** ngay dưới "Từ điển truyện" (cùng điều kiện: truyện đã có trong thư viện) ⇒ sheet kính `LocalNameFilterSheet` (`ReaderView+LocalNameFilter`; `ReaderView.swift` chỉ thêm cờ + một lần gọi).
- **Bước chọn** (`LocalNameFilterSheet+Setup`): phạm vi như "Lọc name nhiều chương" của AI bỏ "Tiếp nối" — chương đang đọc (mặc định; không còn chương đã tải từ đó thì chương đầu tiên) / chương đầu tiên / "Chọn chương…", "Số lượng chương" mặc định Tất cả, dòng "Sẽ lọc N chương đã tải"; ô chương chỉ ghi tên chương. **Không** đọc / ghi mặc định của sheet AI (`AINameScanScopeStore`). "Ít nhất 2 / 3 / 5 / 10 lần" (mặc định 3). Mục "Danh sách": "Đuôi địa danh & tông môn" (số đuôi đang bật) và "Không phải name" (số cụm), đọc lại số khi quay về. "Bắt đầu lọc" chụp cấu hình từ hai danh sách, lấy chương đã tải theo phạm vi (`fetchDownloadedChapters`), cờ phồn → giản của Reader ⇒ `LocalNameFilterRun.start`.
- **Đang lọc** (`LocalNameFilterProgressView` + `LocalNameFilterSession`, `@MainActor @Observable` giữ lượt lọc và vòng nghe sự kiện): "Đọc chương X / N" + thanh; "Name đã thấy (K)" + "cập nhật ở chương X"; danh sách tạm hiện ngay, name vừa vào có vạch + nhãn "mới", name vừa rơi ra gạch mờ — một nhịp tới lần cập nhật kế (`LocalNameFilterLiveRow`). "Dừng" = phân tích nốt phần đã đọc rồi sang màn duyệt; vuốt sheet xuống ở bất kỳ bước nào = huỷ (`onDisappear` ở `ZStack` ngoài cùng). Xong không có name ⇒ về bước chọn, báo "Không tìm thấy name mới · ẩn M name đã có"; `.failed` ⇒ về bước chọn, hiện lỗi.
- **Duyệt**: thay gốc sheet bằng "Duyệt tên riêng & VP" của AI với init mới `ReaderAINameReviewSheet(names:bookId:onSave:onBlockName:)` (danh sách có sẵn, chọn sẵn hết, chỉ tra cờ NE/VP, badge màn Sửa từ "Lọc local · Riêng truyện") + toast "Lọc xong: N name mới · ẩn M name đã có". Card thêm `SortMode.mostFrequent` ("Nhiều lần nhất": số lần giảm dần rồi chữ Hán) + kiểu sắp mặc định; ✕ thành menu "Bỏ khỏi lần này" / "Không phải name" (thêm vào danh sách loại bỏ dùng chung, toast) **chỉ** khi có `onBlock` — luồng AI giữ ✕, menu sắp và mặc định như cũ. Lưu Name riêng / VP riêng (Gộp / Thay thế) thẳng qua `AIHarnessService.saveExtractedEntries`, toast như AI.
- **Kiểm**: đọc code + `check_architecture.py` (không thêm violation); **không build tại chỗ (Windows), chưa thử trên máy**.

## [1.3.1068] - 2026-11-27

### feat: danh sách đuôi địa danh & tông môn và danh sách "Không phải name" cho lọc name local

Phần B của "Lọc name local" (plan 2026-11-27 anh Bửu duyệt; mockup khung 5, 5b, 6). Phần A (bộ lọc) và phần C (sheet Reader, màn duyệt) làm song song — commit này chỉ có store + hai màn quản lý, **chưa nối** vào Reader.

- **Đuôi địa danh & tông môn**: file gốc `Sources/Resources/Translation/NameFilterSuffixes.txt` (app chỉ đọc; dòng `chữ Hán=nghĩa|place/sect|after/before[|off]`; 63 đuôi = 40 địa danh + 23 tông môn, nghĩa Hán-Việt viết thường đặt **sau** tên; 路 区 观 团 tắt sẵn) + lớp riêng `UserDefaults` `localNameFilterSuffixOverrides` (JSON `LocalNameFilterSuffixOverrides`: `entries` đuôi tự thêm / đuôi gốc đã sửa nghĩa · loại · vị trí, `removed`, `enabled` chỉ ghi bật / tắt khác mặc định). `LocalNameFilterSuffixStore`: `enabledSuffixes()` / `enabledCount` cho sheet lọc, thêm / sửa (đổi chữ Hán giữ bật tắt) / bật tắt / xoá / về bản gốc / khôi phục mặc định; luật khoá 1–2 chữ Hán + nghĩa không rỗng, không `=` `|` xuống dòng ở `LocalNameFilterSuffixListParser`. Không dọn cache dịch (đuôi không vào bộ dịch).
- **Không phải name**: `LocalNameFilterBlocklistStore`, `UserDefaults` `localNameFilterBlockedTerms` (JSON `[{term, addedAt}]`), khớp nguyên cụm, trần 5.000 cụm / 20 chữ Hán; `terms()` / `count` / `add(_:)` (trả `nil` khi cụm có trong danh sách sau lệnh — kể cả trùng; chuỗi lỗi khi không thêm) / `remove` / `removeAll`.
- **Màn** (`Views/Reader/NameFilter/Lists/`, `init()` không tham số, `.backPageTitle` — đẩy vào `NavigationStack` của sheet Lọc name local): `LocalNameFilterSuffixListView` (tìm chữ Hán / nghĩa, tab Tất cả / Địa danh / Tông môn, "N đuôi · M đang tắt", hàng "nghĩa · loại · trước tên|sau tên" + tự thêm / đã sửa / đang tắt, ⏸/▶ 🗑, `+` nổi, … "Khôi phục mặc định" hỏi lại) + `LocalNameFilterSuffixEditorSheet` (Chữ Hán, Nghĩa kèm "gốc: …", Loại, Nghĩa đứng Trước tên / Sau tên — mới mặc định Sau tên, dòng "Ví dụ: 江海市 → …" đổi theo, "Về bản gốc"); `LocalNameFilterBlocklistView` (tìm chữ Hán / âm Hán-Việt, "N cụm", hàng "âm Hán-Việt · thêm dd/MM", 🗑, `+` nổi mở sheet một ô, … "Xoá hết" hỏi lại).
- Khoá chữ thường ⇒ Backup tự gói. `translation.md` ghi lại; entry 1.3.1038 chuyển sang `CHANGELOG.archive.md`.
- Biên dịch cần `Sources/Services/Translation/NameFilter/LocalNameFilter.swift` (hợp đồng chung, phần A commit).
- **Kiểm**: đọc code + `check_architecture.py` (vẫn chỉ violation cũ `JSDom.swift`); **không build tại chỗ (Windows), chưa thử trên máy**.

## [1.3.1067] - 2026-11-26

### feat: sửa mục Pronouns dùng màn Sửa từ như VietPhrase

Anh Bửu: "sửa mục pronoun cần giống sửa mục của vp cho tôi" → duyệt plan (chỉ màn Sửa, "+" giữ nguyên).

- Pronouns (Chung) › chạm hàng mở `DictEntryEditSheet` (màn Sửa từ của VietPhrase.dat: chữ gốc chạm từng chữ + nút nới / thu, token đã dịch, ô nghĩa, chip, aa…AA, Cập nhật, tra cứu nhanh) thay form hai ô; badge "Pronouns · Chung", không gắn truyện ⇒ nút ⚙ quản lý nghĩa ẩn (`BaseDictionaryListView.editSheet(for:)`).
- Lưu vẫn qua `GlobalDictionaryEditor` (ghi lại file gốc, dựng lại `.dat`, nạp lại Pronouns, xoá cache dịch): chọn cả từ ⇒ sửa nghĩa; đổi từ gốc (bút chì) ⇒ **bỏ** mục cũ như trước (khác VP — VP chỉ ghi lớp sửa đổi); chọn một phần ⇒ thêm mục mới, mục cũ giữ; từ đích đã có ⇒ màn báo ghi đè.
- Hàng token và nghĩa gợi ý (chọn một phần) ra nghĩa VP/Name vì tách từ không tra Pronouns (1.3.1016) — như panel Dịch của Reader; nghĩa Pronouns hiện ở chip "Xưng hô (Pronouns)".
- Phiên âm giữ form hai ô `BaseDictionaryEntrySheet` (sheet này giờ chỉ còn: thêm mục cả hai, sửa mục Phiên âm). `translation.md` ghi lại; entry 1.3.1037 chuyển sang `CHANGELOG.archive.md`.
- **Kiểm**: đọc code + `check_architecture.py`; **không build tại chỗ (Windows), chưa thử trên máy**.

## [1.3.1066] - 2026-11-26

### fix: sheet có hộp "Bỏ thay đổi?" chạm ra ngoài sheet cũng hỏi như vuốt xuống, không còn đứng im

Anh Bửu: "tiện thể fix luôn các sheet có thông báo bỏ thay đổi/tiếp tục sửa khi bấm ra ngoài sheet không đóng được", "điển hình như sửa từ ở danh sách name của AI" (`DictEntryEditSheet`, nấc `.medium`).

- Nguyên nhân: `SheetDismissGuardModifier` chặn đóng bằng `interactiveDismissDisabled` lúc có nội dung chưa lưu ⇒ `isModalInPresentation`; UIKit khi đó bỏ qua hẳn chạm ra ngoài sheet (không đóng, không báo lượt thử nên không hiện hộp hỏi), chỉ báo lượt vuốt.
- Sửa: bỏ `interactiveDismissDisabled`; `SheetDismissDelegateProxy.presentationControllerShouldDismiss` trả `false` + gọi handler khi `isDirty` (UIKit hỏi hàm này cho cả vuốt lẫn chạm ngoài). Probe truyền `isDirty` thay cho cờ "đã cài" (`onArmedChange` bỏ — chưa cài được proxy thì vốn không chặn được, vẫn cho đóng như trước). Áp cho mọi sheet gắn `.confirmDiscardOnSwipe` (15 file).
- `ui-conventions.md` ghi luật mới.
- **Kiểm**: đọc code + `check_architecture.py`; **không build tại chỗ (Windows), chưa thử trên máy** — nhất là nhịp hiện hộp hỏi khi vừa chạm ngoài / vừa bắt đầu vuốt.

## [1.3.1065] - 2026-11-26

### feat: token tùy chọn <@tên> cho rule dịch nhanh, kèm màn quản lý và menu nhấn giữ ở bảng token

Anh Bửu: "thêm chức năng thêm và sử dụng bộ token tùy chọn" → duyệt plan + mockup https://claude.ai/artifact/EPVM1fC9YrAozdyt1H5NUj, kèm hai ý anh thêm: "thêm nút + ở phần tùy chọn để thêm token mới", "nhấn giữ các token, kể cả token cố định sẽ hiện thị ra các option quản lý danh sách từ (nếu có), bật/tắt token, xóa (đối với token tùy chọn)".

- Cú pháp `<@tên>` (tên `a-z 0-9 _`, bắt đầu bằng chữ, ≤ 20): khớp một từ trong danh sách `chữ gốc=nghĩa` của token, `{i}` = nghĩa, từ dài thử trước (`DictionaryKind.custom` + `QuickTranslationRuleElement.customTokenName`, `QuickTranslationDictionaryToken.candidates`). `<@TÊN>` = viết hoa nghĩa; không nhận `:min-max`, không ghép `|`.
- Parser **không** tra token lúc parse (`QuickTranslationRuleParser+CustomToken`): token chưa có / tắt / đã xoá không biến dòng rule thành lỗi nặng ⇒ `validRecords` không xoá dòng; trạng thái đó báo `DICT_TOKEN_WITHOUT_DICTIONARY` theo từng tên (`QuickTranslationRuleStore+CustomTokenIssues`).
- Lưu `UserDefaults` `quickTranslateCustomTokens` (JSON, `QuickTranslationCustomTokenStore`): Backup tự gói, trần 50 token / 20.000 từ, cache bảng tra chỉ so lại chuỗi thô sau `UserDefaults.didChangeNotification`; mỗi lần ghi dọn cache dịch + phát tín hiệu rule đổi. Luật tên / chữ / nghĩa + bộ đọc file: `QuickTranslationCustomTokenListParser`.
- Màn: hàng "Token tùy chọn" ở Cấu hình token rule ⇒ `QuickTranslationCustomTokenListView` (tìm, tắt / bật, xoá có hỏi lại, + Thêm token) ⇒ `QuickTranslationCustomTokenEntryListView` (tìm, + Thêm từ, ngăn kéo …: Sửa mô tả, Tắt / Bật, Nhập file 3 cách, Xuất file, Xoá token); sheet `QuickTranslationCustomTokenEditorSheet` (tên khoá khi sửa) và `QuickTranslationCustomTokenEntryEditorSheet`.
- Bảng token màn sửa rule: nhóm "Tùy chọn" + chip + (sheet Thêm token); nhấn giữ chip token (`.contextMenu`): Danh sách họ (`<ho>`) / Bộ ngoặc (`<[>` `<]>`) / Danh sách từ, Tắt / Bật (token cố định = công tắc ở Cấu hình token rule), Sửa mô tả + Xoá (token tùy chọn). Ý định ghi vào `QuickTranslationRuleTokenPaletteModel`, đẩy trang / sheet / hỏi xoá ở `QuickTranslationRuleTokenPaletteManagement` gắn ngoài hàng lazy của `Form`. Hàng gợi ý trên bàn phím có `<@tên>` (lọc khi gõ `<@`), không có menu.
- Thanh chỉnh token: `<@tên>` không có thanh độ dài, có "AA hoa nghĩa". Hướng dẫn viết rule thêm mục "Token tùy chọn"; `translation.md`.
- **Kiểm**: đọc code + `check_architecture.py`; **không build tại chỗ (Windows), chưa thử trên máy**.

## [1.3.1064] - 2026-11-26

### fix: đổi nguồn tại chỗ đặt ngay link chương đang đọc theo mục lục mới

Rà lại 1.3.1063 (chưa push): giữ `playingChapterUrl` là link nguồn cũ tới hết chương làm lệch bất biến "link chương đang đọc = link trong `chaptersQueue`" — `BookDetailView` / `VideoWatchModel.activeTTSProtectedChapter` dựng `ProtectedTTSChapter(bookId mới, chỉ số, link cũ)` khi làm mới mục lục truyện mới ⇒ chương TTS đang đọc có thể không được giữ.

- `handOffSession` đặt `playingChapterUrl` = link chương đang đọc trong mục lục mới; link cũ vào `sourceChangeFormerBook` (thêm `chapterUrl`).
- `isPlayingChapterUrl(_:)` (khuôn `isPlayingBook`, khoá theo `sessionID`) thay phép so link ở 4 chỗ kiểm việc đang bay: refill Nghi, nạp trước remote, task phát Nghi chờ tổng hợp, nạp gộp Google. Lượt tổng hợp đang bay mang khoá theo link cũ ⇒ lượt mới cùng đoạn không gộp với nó (vài đoạn quanh lúc chuyển, không sai tiếng).
- `tts.md` sửa câu tương ứng.
- **Kiểm**: đọc code + `check_architecture.py`; **không build tại chỗ (Windows), chưa thử trên máy**.

## [1.3.1063] - 2026-11-26

### fix: đổi nguồn lúc đang nghe đọc hết đoạn đang phát rồi sang đoạn sau của nguồn mới, không ngắt tiếng

Anh Bửu: "khi chuyển nguồn của truyện đang nghe sẽ có bước tắt nghe và mở lại đúng đoạn đang nghe, điều này khiến người nghe có cảm giác gián đoạn, hãy sửa lại chứ để nghe xong đoạn đang phát và phát đoạn tiếp theo (đoạn chứ không phải chunk nhé)" → duyệt plan "Duyệt + cả tạm dừng".

- `TTSManager.continueListeningAfterSourceChange` (1.3.946) thôi `stop()` + `startSpeaking` từ đầu dòng (cắt giữa câu, im 1–3 s, nghe lại cả dòng). Nay trả một Task: chờ lượt dựng chương đang chạy (`awaitChapterBuildsInFlight`, nay `internal`) → `handOffSession` đổi trong một nhịp main truyện đang phát sang truyện mới — `playingBookId`, mục lục mới, tiện ích, tên / bìa / tác giả / link / nguồn, cờ dịch + phồn → giản theo truyện mới, chủ mảng chunk, bỏ đồ chuẩn bị theo truyện cũ (`invalidatePreparedTranslationState`), giành + lưu tiến độ cho truyện mới — **không** đổi `sessionID` / `ttsProcessingGeneration`, không bỏ bộ đệm; rồi nối chữ của nguồn mới từ **dòng sau** dòng đang đọc bằng chính lượt nối của dịch lại (`scheduleChapterRetranslation(reason: "đổi nguồn", evenWithoutTranslation: true, debounceNanoseconds: 0)`). Chương đã tải được chép nguyên văn ⇒ chữ trùng, không bỏ tiếng nào. Áp cả khi **tạm dừng**: giữ đĩa nghe, bấm ▶ đọc tiếp truyện mới đúng chỗ (trước: dừng hẳn + toast "bấm nghe để đọc tiếp").
- Việc đang bay đóng dấu truyện cũ vẫn hợp lệ trong cùng phiên: `isPlayingBook(_:)` (= `playingBookId` hoặc `sourceChangeFormerBook` khoá theo `sessionID`) thay phép so ở `isContextValid` (thiếu ⇒ chunk đang phát xong không gọi đoạn kế), task phát Nghi chờ tổng hợp, refill Nghi, nạp trước remote, nạp gộp Google. `playingChapterUrl` giữ link nguồn cũ tới hết chương (chỗ kiểm + khoá tổng hợp tính theo nó). 7 thuộc tính `@Published` của phiên `private(set)` → `internal(set)` để `+SourceChange` ghi được.
- Lượt nối dựng theo cờ dịch của phiên (`RetranslationInputs.translates`, trước ghi cứng dịch) ⇒ chạy được với truyện tắt dịch; lùi / tua về dòng chữ cũ (`adoptFullRetranslationIfStale`) so cờ này thay vì đòi bật dịch.
- `BookSourceChangeCoordinator.scheduleFinish(after:)` chờ Task chuyển phiên xong rồi mới dọn truyện cũ (`deleteBooksAsync` bỏ qua truyện TTS đang phát ⇒ dọn sớm là giữ lại bản trùng). Nguồn mới không có chương đang đọc ⇒ dừng + toast lỗi như cũ; tải chương nguồn mới lỗi ⇒ đọc nốt chương bằng chữ đang có.
- Giới hạn: NghiTTS / VieNeu đã hẹn giờ chunk đầu của dòng sau ⇒ dòng đó còn chữ cũ, chữ mới từ dòng kế; chương chưa tải ghép dòng theo vị trí (gần đúng như trước).
- `books-sources.md`, `tts.md` ghi phần mới.
- **Kiểm**: đọc code + `check_architecture.py`; **không build tại chỗ (Windows), chưa thử trên máy**.

## [1.3.1062] - 2026-11-25

### feat: rule dịch nhanh có token <ho> khớp họ người Trung Quốc, kèm màn Danh sách họ

Anh Bửu: "thêm token phân loại họ trung quốc", rồi "Thêm quản lý danh sách họ trung quốc nữa" → duyệt plan + mockup https://claude.ai/artifact/1pajdjujzW1qQizNjXCgEY.

- Token `<ho>` (`QuickTranslationRuleTokenSettings.Kind.surname`, nối **cuối** `allCases` ⇒ chữ ký cache dịch đổi một lần; khoá công tắc `quickTranslateRuleTokenSurnameEnabled`, mặc định bật, nhóm Từ điển) = `DictionaryKind.surname`: khớp một họ trong danh sách họ, `{i}` = âm Hán-Việt viết hoa lưu sẵn (`王` → Vương, `欧阳` → Âu Dương). Độ dài cố định 1–2 đơn vị UTF-16 (`DictionaryKind.fixedLengthRange`, parser ép như `<hv>`, không thanh độ dài); `QuickTranslationDictionaryToken.candidates` thử họ kép trước họ đơn, matcher lùi nếu phần sau mẫu không khớp. Có `?`, `|` (`<ne|ho>`); `<HO>` nhận như `<ho>` (âm đã viết hoa). `<w>` không đổi. Name riêng thắng như mọi token (capture không nuốt trọn Name ⇒ bỏ lượt khớp).
- Danh sách gốc `Sources/Resources/Translation/ChineseSurnames.txt` (`chữ Hán=Âm`, `#` ghi chú; app chỉ đọc): Bách gia tính (bản giản thể phổ biến, đối chiếu Wikisource) + 肖 付 覃 冼 邝 / 独孤 太史 完颜 耶律 纳兰, phồn thể viết riêng từng dòng (钟 → 鍾; 于 余 范 沈 谷 后 giữ nguyên; thêm 鬱 麴 甯 雲). 683 khoá = 583 họ đơn + 100 họ kép. Âm theo bảng phiên âm, sửa riêng 曾 Tăng, 晏 Án, 扈 Hỗ, 干 Can, 肖 Tiêu, 佟 Đồng, 万俟 Mặc Kỳ, 尉迟 Uất Trì, 长孙 Trưởng Tôn, 单于 Thiền Vu, 段干 Đoạn Can; viết y: 祁 Kỳ, 纪 Kỷ, 冀 Ký, 暨 Kỵ, 百里 Bách Lý.
- Lớp riêng của người dùng: `UserDefaults` `quickTranslateSurnameOverrides` = JSON `{"entries":{khoá: âm}, "removed":[…], "disabled":[…]}` (`QuickTranslationSurnameOverrides`; vắng = bản gốc; Backup tự gói). Trộn: gốc → áp `entries` → bỏ `removed` → đánh dấu `disabled`; engine chỉ thấy họ đang bật. `QuickTranslationSurnameStore` đọc file gốc một lần, cache bảng tra theo chuỗi JSON thô (như Bộ ngoặc), mọi lần ghi `TranslateUtils.clearCache()` + `notifyRulesDidUpdate()`. Một bộ đọc + một luật kiểm (`QuickTranslationSurnameListParser`: khoá 1–2 chữ Hán, UTF-16 ≤ 2; âm không rỗng, không `=` / xuống dòng) cho file gốc, sheet sửa và nhập file.
- Màn **Danh sách họ** (`QuickTranslationSurnameListView`, hàng `QuickTranslationSurnameRow`, sheet `QuickTranslationSurnameEditorSheet`) mở từ hàng "Danh sách họ" (dòng phụ "683 họ · 1 đang tắt") dưới công tắc `<ho>` ở Cấu hình token rule: ô tìm luôn hiện, hàng kiểu VP/Name (chạm hàng mở sheet sửa, ⏸ / ▶, 🗑, không bút chì), `+` nổi, ngăn kéo "…" Nhập file (`.dataImportFilePicker`; Gộp đè âm + bỏ dấu đã xoá, Chỉ thêm key mới coi họ gốc đã xoá là đã có, Thay thế toàn bộ = đúng nội dung file; file không có dòng hợp lệ ⇒ báo lỗi, không đụng dữ liệu; toast "thêm X, cập nhật Y" + dòng lỗi bỏ qua) / Xuất file (họ đang bật, cùng dạng file gốc) / Khôi phục mặc định. Sửa chữ Hán = xoá khoá cũ + thêm khoá mới; họ gốc đã đổi âm có "Về âm gốc". Chỉ một danh sách chung (công tắc `<ho>` riêng truyện vẫn tự có).
- Chip `<ho>` "họ Trung Quốc" ở bảng token + gợi ý bàn phím, câu "nuốt một họ: 1 hoặc 2 chữ" ở thanh chỉnh token, `QuickTranslationRuleGuide` thêm ý `<ho>` + mục "Danh sách họ" (`HelpSpot.surnameList`), `translation.md` ghi phần mới.
- **Kiểm**: đọc code + `check_architecture.py` (chỉ còn violation cũ `JSDom.swift`, **0 mới**), 683 dòng file gốc qua luật kiểm (mô phỏng Python); **không build tại chỗ (Windows), chưa thử trên máy**.

## [1.3.1061] - 2026-11-25

### fix: VPN 1.1.1.1 tách hai nút Bật / Tắt chạy hai phím tắt, ghi lần app chạy phím tắt cuối

Anh Bửu: "dù đã tắt vpn nhưng vào app vẫn cứ bật lại", "tôi không làm được shortcut bật/tắt vpn, chỉ làm được shortcut bật thôi" → duyệt mockup bản 3 https://claude.ai/artifact/NqVsj9fYBpdFUJJfzeZi1k.

- Hai phím tắt thay cho một phím tắt "Bật/tắt" (`VPNShortcutLauncher.Action`): **bật** = "Đặt VPN" › Kết nối (giữ khoá `vpnShortcutName`, mặc định "VPN 1.1.1.1" ⇒ phím tắt anh đã tạo vẫn chạy), **tắt** = "Đặt VPN" › Ngắt kết nối (khoá mới `vpnShortcutOffName`, mặc định "Tat VPN 1.1.1.1", không dấu). App không dò trạng thái VPN.
- Mạng & DNS: hai nút "Bật VPN 1.1.1.1" / "Tắt VPN 1.1.1.1", hai ô "Phím tắt bật" / "Phím tắt tắt", dòng **"App chạy phím tắt lần cuối"** ("10:42 · Bật · hub", ngày khác "24/11 10:42 · …", chưa chạy "Chưa có"). Câu giải thích đổi "đang nghe / xem thì không bị ngắt" ⇒ "app không bị mở lại" (phim có thể bị iOS tạm dừng khi app Phím tắt hiện lên).
- Lần chạy cuối: iOS nhận mở app Phím tắt ⇒ `VPNShortcutLauncher.recordRun` ghi `vpnShortcutLastRunAt` / `vpnShortcutLastRunInfo` vào UserDefaults — không phụ thuộc công tắc Ghi log (tắt lại mỗi lần mở app). Để bắt vụ VPN tự bật: anh đã kiểm "Kết nối theo yêu cầu" đang tắt, không có Tự động hoá, mở Safari thì không bị; app không dùng `NetworkExtension` ở đâu, đường duy nhất là mở app Phím tắt (luôn hiện lên trước mắt) ⇒ VPN tự bật mà giờ ở dòng này cũ hơn thì không phải app.
- Trang "Cách tạo phím tắt" (`VPNShortcutGuideView`): nhóm bước Phím tắt bật / Phím tắt tắt + mục "VPN tự bật lại".
- Sheet hub: dòng "VPN 1.1.1.1" (`FloatingHubVPNRow`) bỏ mũi ›, thân dòng không bấm; cuối dòng hai nút nhỏ Bật (kiểu chip đang chọn: chữ màu nhấn, nền nhấn 18%, viền 60%) / Tắt (nền trắng 12%), cao 32, chữ 13 nửa đậm; bấm ⇒ `runVPNShortcut(_:)` đóng sheet xong mới chạy.
- `network-dns.md`, `floating-pills.md` ghi phần mới.
- **Kiểm**: đọc code + `check_architecture.py` (chỉ còn violation cũ `JSDom.swift`, **0 mới**); **không build tại chỗ (Windows), chưa thử trên máy**.

## [1.3.1060] - 2026-11-25

### fix: danh sách name AI bỏ ô nhập nghĩa và nút bút chì, chạm hàng mở màn Sửa từ

Anh Bửu: "màn hình danh sách name của AI hãy sửa lại bỏ cho nhập ô nhập nghĩa, bỏ nút edit, tap vào hàng nào thì hiển thị màn hình edit của nghĩa đó" → duyệt mockup https://claude.ai/artifact/3Y5Z8nGN3X5hA17R2Qf7bs.

- Sheet "Duyệt tên riêng & VP" (`ReaderAINameReviewCardView`): dòng 2 của hàng là **chữ** nghĩa (`.subheadline`, màu phụ, một dòng) thay cho ô `TextField`; bỏ nút bút chì. Chạm khối chữ (tên + badge + nghĩa, kéo tới ✕) ⇒ mở màn Sửa từ có sẵn (`DictEntryEditSheet`, badge "AI · Riêng truyện", 1.3.780) theo khuôn `DictionaryEntryRow`: `.contentShape(Rectangle()).onTapGesture`, không bọc cả hàng trong `Button`, thêm `.accessibilityAction(named: "Sửa")`.
- Đổi hành vi: chạm dòng tên trước đây là chọn / bỏ chọn ⇒ nay mở màn sửa; chọn / bỏ chọn chỉ còn ở ô vuông bên trái. Ô vuông và ✕ giữ `.buttonStyle(.plain)` (card nằm trong `ScrollView` + `LazyVStack`, không phải `List`, nên chạm thân hàng không kích hoạt chúng).
- Mọi lần sửa nghĩa giờ đi qua màn Sửa từ ⇒ `onEditName` ghi vào tin nguồn, mở lại sheet vẫn còn (trước đây gõ thẳng vào ô trên hàng thì đóng sheet là mất). Nút bút chì trên header màn Sửa từ (gõ lại từ gốc) giữ nguyên — màn này dùng chung với danh sách VP/Name.
- Kiểm: đọc code + `check_architecture.py` (chỉ còn violation cũ `JSDom.swift`, **0 mới**); **không build tại chỗ (Windows)**, chưa thử trên máy.

## [1.3.1059] - 2026-11-24

### feat: nút bật / tắt VPN 1.1.1.1 qua app Phím tắt ở Mạng & DNS và sheet hub

Anh Bửu: "Thêm nút mở vpn 1.1.1.1 được không, có thể sử dụng shortcut" → duyệt mockup https://claude.ai/artifact/NqVsj9fYBpdFUJJfzeZi1k, chỗ đặt A (dòng ở sheet hub); phần thêm (trạng thái VPN, toast sau khi về) anh không chọn.

- App chạy trong LiveContainer, không có Network Extension ⇒ không tự bật VPN được. Nút chạy **phím tắt người dùng tạo sẵn** (tác vụ "Đặt VPN" › Bật/tắt › cấu hình 1.1.1.1) qua `shortcuts://x-callback-url/run-shortcut?name=…`; app Phím tắt hiện lên giây lát.
- `VPNShortcutLauncher` (`Services/Network/VPNShortcut/`, chỉ Foundation): dựng link, tên phím tắt từ `@AppStorage` `vpnShortcutName` (mặc định "VPN 1.1.1.1", không dấu). **Link quay về** chỉ gắn khi có `LC_HOME_PATH`: `livecontainer://livecontainer-launch?bundle-name=<Bundle.main.bundlePath cuối>&container-folder-name=<HOME cuối>` — đúng hai giá trị LiveContainer so trong `LCHandleControlAppURL` (`UIKit+GuestHooks.m`), trùng app đang chạy ⇒ LiveContainer không làm gì, app chỉ lên trước, không mở lại (TTS / phim không ngắt). Giá trị lồng mã hoá chặt `-._~`. Log `🛡️ [VPNShortcut]` ghi link + link quay về để tra trên máy.
- `VPNShortcutRunner` (View): `UIApplication.open` không qua `canOpenURL` (trong LiveContainer `LSApplicationQueriesSchemes` là của LiveContainer); iOS không nhận ⇒ toast "Không mở được app Phím tắt".
- Mạng & DNS (`NetworkSettingsView`): section "VPN 1.1.1.1" giữa DNS mã hoá và Trình duyệt & phim — nút "Bật / tắt VPN 1.1.1.1", ô "Tên phím tắt", trang "Cách tạo phím tắt" (`VPNShortcutGuideView`, khuôn bước của `SystemDNSGuideView`, nút "Mở app Phím tắt").
- Sheet hub: dòng "VPN 1.1.1.1" (`FloatingHubVPNRow`) ngay dưới bốn dòng cố định, cùng dáng `FloatingHubMenuRow`; là lối tắt hành động nên **không** thuộc `FloatingHubItem.Kind` (không tính đang chạy / nháy nút hub); chạm ⇒ `sheetState.dismiss` xong mới chạy (`runVPNShortcut`).
- `network-dns.md`, `floating-pills.md` ghi phần mới.
- **Kiểm**: đọc code + `check_architecture.py` (chỉ còn violation cũ `JSDom.swift`, **0 mới**); **không build tại chỗ (Windows), chưa thử trên máy** — điểm cần thử: phím tắt có bật / tắt được 1.1.1.1 không, và quay về app có giữ nguyên (không mở lại) không.

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
