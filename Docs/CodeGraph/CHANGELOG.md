# CHANGELOG - Nhật ký Thay đổi CodeGraph Tàng Công Các

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **Tàng Công Các**.

## [1.3.1142] - 2026-11-28

### feat: mở lại gói tạm của lọc name local thì bỏ tích hết và chỉ tích name chưa có trong Name hoặc VP

- Anh Bửu 2026-11-28: "mỗi lần vào danh sách duyệt hãy bỏ tick và chỉ tick lại các name chưa có trong vp/name riêng chung". Lúc vừa lọc xong app vốn đã làm vậy; nhưng mở lại một gói tạm từ Lịch sử lọc (hoặc bấm ‹ rồi vào lại) thì ô tích giữ y như lúc đóng — name anh đã lưu vào Name sau lần lọc đó vẫn còn tích, nên bấm Lưu / Xuất file là lấy cả name đã có.
- Nay `LocalNameFilterSession.openDraft` đặt lại ô tích trước khi hiện màn duyệt (`resettingSelection`, `LocalNameFilterSession+Drafts`): tích mọi name rồi cho `AIBookDataInspector.decorateExtractedNames` bỏ tích và gắn lại badge NE / VP cho name đã có trong Name hoặc VP (riêng truyện, Chung, gốc) — cùng một luật với lúc vừa lọc xong. Name chưa có trong từ điển được tích lại dù lần trước anh đã bỏ tích. Danh sách, nghĩa đã sửa và loại của gói vẫn giữ nguyên.
- Tra từ điển chạy ngoài main nên `openDraft` thành `async`; `openDraftFromHistory` gọi trong `Task`. Tra xong mà phiên đã rời bước chọn thì thôi.
- `.claude/rules/translation.md`: ghi luật mới ở đoạn gói tạm.
- Chưa build (máy Windows); chưa thử trên máy.

## [1.3.1141] - 2026-11-28

### fix: lọc name local không còn nhận tên người kèm hư từ đứng sau như 穆宣和 là một tên

- Anh Bửu gửi file xuất màn duyệt ở bản 1.3.1139 (truyện Thiết Y Công, 921 dòng = 95 name mới + 826 đã có). Đối chiếu với bản Python mô phỏng máy: khớp — 20 tên "…冥将" ra đúng "… Minh Tướng", các tên từng bị bỏ nhầm (江明月, 柯大力, 田悠悠, 叶瞻, 大力盟, 裴问心) đã có mặt, 临州城 / 东城区 / 老柯 thành "đã có", và 29 cụm của danh sách "Không phải name" không còn hiện sau khi anh nhập lại file (chức năng Nhập file của 1.3.1138 chạy được). Khác biệt còn lại đều do máy có nhiều chương hơn file thử.
- File đó lộ một lỗi của luật hư từ nới ở 1.3.1139: 穆宣和 (= 穆宣 + "và") được giữ vì 和 nằm trong 9 chữ được phép ở tên "họ + tên" 2–3 chữ. Sửa ở `LocalNameFilterLACPipeline.hasFunctionChar`: chữ được phép đứng ở **cuối** cụm 3 chữ không còn được miễn khi hai chữ đầu đã là một thực thể LAC xuất hiện ít nhất bằng chính cụm đó (và đủ "Ít nhất N lần") — khi ấy chữ cuối là hư từ đứng sau tên. 石良才 (24 lần, 石良 chỉ 17 lần) vẫn giữ.
- Bản Python tham chiếu (`lacpipe.py`, khối "Đợt 7") sửa trước; chạy 11 truyện: không hàng nào đổi (file thử chỉ có 穆宣和 một lần nên vốn dưới ngưỡng).
- Rác còn lại trong 95 name mới của file anh gửi: 麾下宗门, 幽碧, 锻岳锤 và vài cụm lưng chừng (祖地俊彦榜, 黄泉地火, 极乐宗府库) — chưa có luật tách được khỏi tên thật.
- `.claude/rules/translation.md`: ghi kết quả kiểm trên máy và đợt 7.
- Chưa build (máy Windows); bản sửa này chưa thử trên máy.

## [1.3.1140] - 2026-11-28

### feat: lọc name local thêm đuôi 堡 vào bộ dò và bỏ cụm kiểu 张开巨口 bị nhận là tên người

- Hai việc nhỏ còn lại của đợt soát "đủ name / hết rác", đều đo trước trên bản Python tham chiếu (11 truyện): thêm 3 hàng (寒冰堡 39 lần, 霜狼古堡, 枫丘城堡), mất 1 hàng (张开巨口 — rác), không name đã có nào bị bỏ.
- Đuôi 堡 = "bảo" (địa danh) vào file gốc `NameFilterSuffixes.txt` (bộ dò cố định của cách A) ⇒ bộ luật sinh được ứng viên "X堡" và luật "từ thường + hậu tố dò" của phía LAC giữ được 寒冰堡 (trước bị `dict_common_head` bỏ vì 寒冰 là từ thường). Danh sách hậu tố của người dùng tự có thêm mục này (mục gốc mới), sửa / xoá được như mọi mục gốc.
- L20 `common_phrase` (`LocalNameFilterJunkRules`): trước chỉ áp cho Nhân danh không mở đầu bằng họ; nay áp cả cho name mở đầu bằng họ khi từ thường đầu tiên của phép phủ là động từ / giới từ… theo LAC (LAC gán đứng riêng ≥ 20 lần, ≥ 60 % nhãn `VERBISH`, chưa từng là thực thể — `isVerbishWord`, tách ra dùng chung với L22 `verb_head`). 张开巨口 (张 là họ, 张开 = "mở ra") bị bỏ; 通天蛤蟆, 金刚巨虎 giữ.
- Đã đo và không làm vì bắt nhầm / kéo về name ghép: giữ "thực thể + cụm chung có hậu tố" ở `glued_fragment` (临济城城卫总司, 郑氏武馆真传弟子宅院 quay lại), bỏ "từ kiểu động từ + danh xưng" (nhầm 离乱天君, 无量天君), thêm đuôi 大道 (truyện tu tiên dùng 大道 cho "đại đạo").
- `.claude/rules/translation.md`: ghi đợt 6, sửa số mục của file hậu tố gốc.
- Chưa build (máy Windows); chưa thử trên máy. Số đo là của bản Python tham chiếu, không phải của app.

## [1.3.1139] - 2026-11-28

### feat: lọc name local trả lại tên thật bị các luật lọc cũ bỏ nhầm như 江明月, 柯大力, 云梦商会, 史莱克城

- Soát "đủ name" trên bản Python tham chiếu: ghi lý do bỏ của mọi thực thể LAC ở bước lọc rồi xem các thực thể có số lần cao trên 11 truyện. Các luật lọc cũ đang bỏ nhầm nhiều tên thật: 江明月 (642 lần), 柯大力 (631 lần), 于斯年 (124), 云梦商会 (124), 大力盟 (87), 史莱克城 (83), 裴问心 (66), 叶瞻 (109), 老尼尔 (182). Hai tên đầu cũng vắng trong file anh Bửu xuất từ màn duyệt. Sửa ở `LocalNameFilterLACPipeline` (chỉ đường có model LAC), chép đúng khối "Đợt 5" của `lacpipe.py`.
- `dict_common_given` (họ + từ thường 2 chữ): không áp khi phần sau họ là hậu tố Nhân danh của danh sách (陈真传, 徐学长, 袁峰主 là họ + danh xưng), và chỉ bỏ khi LAC tách phần sau họ thành từ thường đứng riêng ≥ 3 × số lần của cụm. 江明月, 柯大力, 田悠悠, 钟万里, 蔺如风 giữ; 王余孽, 何强横, 王三家 vẫn bỏ.
- `dict_common_head` (đầu 2 chữ là từ thường): không áp cho cụm có hậu tố dò xuất hiện ≥ 5 lần — từ thường + hậu tố là name (大力盟, 如意坊, 九宝阁, 神龙城, 浩然峰, 铁衣镇, 易筋丹). 倘若镇, 温柔乡 (3 lần) vẫn bỏ.
- `function_char`: không tính 会 ở cuối cụm ≥ 3 chữ (云梦商会, 黑夜女神教会, 冒险家协会), 哈 khi không có 哈哈 (哈迪伯爵, 哈布拉), 地 không ở cuối (遁地兽, 大地母神教会); Nhân danh 2–3 chữ mở đầu bằng họ đơn được chứa 和 连 才 问 有 于 向 能 自 (于斯年, 裴问心, 石良才, 徐天和, 林有余).
- `glued_fragment`: giữ thực thể + đúng một chữ thân tộc ở cuối (林戎兄); thực thể + đúng một chữ đuôi dò ở cuối khi cụm không dính chữ ngay sau ≥ 90 % số lần (史莱克城, 雁平县, 广平县 giữ; 临济城镇 = 临济城 + 镇魔司 vẫn bỏ); 小 / 老 / 阿 + thực thể (小炽翎).
- Mảnh (`fragment`): tên mở đầu bằng họ đơn đứng ở cuối một cụm dài hơn, sau một phần ≥ 2 chữ không phải họ (剑圣|叶瞻, 七爷|范无救) không còn bị coi là mảnh của cụm đó — khi LAC gắn nó là thực thể nhiều hơn nhãn thường và nó không kết thúc bằng 儿 / 子 (成神, 孙儿 không được miễn).
- Từ thường (`dict_common_word`): nghĩa VP đầu viết thường nhưng có từ viết hoa ở giữa ⇒ coi là đã có (老尼尔 = "lão Neil", 临州城 = "thành Lâm Châu", 东城区 — `LocalNameFilterDictionaries.hasInnerCapital`); Nhân danh = họ + hậu tố Nhân danh ≥ 2 chữ của danh sách không bị bỏ vì VP ghi cả cụm viết thường (武师兄).
- Luật rác thêm `count_great`: tổ chức mở đầu bằng chữ số + 大 (七大教会, 八大宗门); tên nhóm người / địa danh (八大天君, 四大圣岛) không tính.
- Số đo trên bản Python (11 truyện, so với 1.3.1137): mất 2 hàng (七大教会, 八大宗门 — rác), thêm 107 hàng; đọc từng hàng thêm: phần lớn là tên thật, còn vài cụm chưa rõ (金魔鸟, 祖地俊彦榜, 黄泉地火). Mô phỏng máy anh (coi 815 name anh đã lưu là đã có): thêm 50 name, trong đó 江明月, 柯大力, 田悠悠, 叶瞻, 大力盟, 裴问心.
- Còn bỏ nhầm, chưa có cách: VP ghi hẳn nghĩa thường cho tên (林三, 苏勒), đuôi không có trong bộ dò (寒冰堡), "họ + 上人" ít lần.
- `.claude/rules/translation.md`: ghi đợt 5 và cách soát.
- Chưa build (máy Windows); chưa thử trên máy. Số đo là của bản Python tham chiếu, không phải của app.

## [1.3.1138] - 2026-11-28

### feat: màn Hậu tố, Tiền tố và Không phải name của lọc name local nhập được danh sách từ file

- Anh Bửu hỏi "sao làm xuất rồi mà không làm nhập" và duyệt plan 2026-11-28: ngăn kéo `…` của ba màn danh sách (Hậu tố, Tiền tố — `LocalNameFilterSuffixListView`; Không phải name — `LocalNameFilterBlocklistView`) có thêm hàng "Nhập file" ngay trên "Xuất file". Chọn file trước, rồi popup ba cách nhập kèm tên file (`.dataImportFilePicker` có sẵn), nhập vào danh sách của chip phạm vi đang chọn (Chung / Riêng truyện); tiêu đề popup ghi rõ đích khi màn có hai phạm vi.
- Định dạng = đúng thứ "Xuất file" ghi nên file app tự xuất nhập lại được: hậu tố / tiền tố mỗi dòng `chữ Hán=nghĩa|loại|vị trí[|off]` (đọc + kiểm bằng `LocalNameFilterSuffixListParser`, cờ `|off` đọc được nhưng bỏ qua), Không phải name mỗi dòng một cụm (`LocalNameFilterBlocklistStore.formatError`); dòng trống, dòng `#`, BOM đầu file bỏ qua; dòng sai bị bỏ và đếm. File không có dòng hợp lệ nào ⇒ báo lỗi, không ghi gì.
- Ba chế độ:
  - Gộp: khoá đã có thì đè nghĩa / loại / vị trí (chỉ tính "cập nhật" khi thực sự khác), khoá mới thì thêm; ở Hậu tố / Tiền tố Chung mục gốc đã xoá mà file có thì hiện lại. Không phải name: cụm đã có giữ nguyên.
  - Chỉ thêm key mới: khoá / cụm đã có giữ nguyên; ở Hậu tố / Tiền tố Chung mục gốc đã xoá trên máy cũng coi là đã có (như Danh sách họ).
  - Thay thế toàn bộ: danh sách thành đúng nội dung file. Hậu tố / Tiền tố Chung (file gốc + lớp sửa đổi): mục gốc vắng trong file vào `removed`, mục trùng y bản gốc không ghi vào `entries` (`LocalNameFilterSuffixOverrides.importLines`). Riêng truyện: thay cả danh sách của truyện. Không phải name: thay cả danh sách, cụm vốn có giữ ngày thêm cũ.
  - Không phải name vượt trần 5.000 cụm sau khi nhập ⇒ báo lỗi, không nhập một phần.
- Tầng Service: `LocalNameFilterListImport` (file mới — kiểu kết quả `Outcome` / `Failure`, đọc file, phép trộn thuần) + `LocalNameFilterAffixListStore+Import`, `LocalNameFilterBookAffixStore+Import`, `LocalNameFilterBlocklistStore+Import`, `LocalNameFilterBookBlocklistStore+Import` (file mới). Mỗi lần nhập ghi `UserDefaults` đúng một lần; store riêng truyện đọc – trộn – ghi dưới `lock` của nó; kết quả trùng y dữ liệu cũ thì không ghi. Vài hàm đọc / ghi nội bộ của bốn store bỏ `private` để file `+Import` dùng.
- Nhập xong màn đọc lại danh sách, toast "Đã nhập: thêm X, cập nhật Y" (thêm ", bỏ N … cũ" khi thay thế, ", bỏ qua Z dòng lỗi" khi có dòng sai; Không phải name không có "cập nhật"); lỗi ⇒ toast lỗi + log `❌ [LọcName]`. Không dọn cache dịch (các danh sách này không vào bộ dịch).
- `.claude/rules/translation.md`: ghi Nhập file; sửa số bản của đợt 4 thành 1.3.1137.
- Chưa build (máy Windows); chưa thử trên máy.

## [1.3.1137] - 2026-11-28

### feat: lọc name local nối lại tên bị LAC cắt cụt, trả lại tên chính bị bỏ nhầm và thêm bảy luật rác theo ngữ cảnh

- Làm sau khi anh Bửu gửi file xuất màn duyệt trên máy (925 dòng) và dặn "phải đảm bảo thuật toán hết rác thì mới tích hợp vào app". Đo trước trên bản tham chiếu Python: coi 815 name anh đã lưu là "đã có" thì Python tái hiện 107 / 110 name mới và đủ 815 name đã lưu của file ⇒ app đang chạy đúng như bản tham chiếu; rác trong 110 name mới chia ba nhóm (LAC cắt cụt, mảnh của name dài hơn, cụm chung chung).
- Nối cụm LAC cắt cụt (`LocalNameFilterLACPipeline+Bound`, file mới; `LocalNameFilterTextCounter.neighbors` đếm chữ Hán đứng ngay trước / sau mỗi lần xuất hiện): cụm sắp thành hàng (chưa có, toàn chữ Hán dải bộ luật, không nằm trong "Không phải name") mà một chữ đứng cạnh ≥ 90 % số lần (cụm ≥ 3 lần) ⇒ nối chữ đó, tối đa 3 chữ mỗi phía. Bên phải chỉ cho Nhân danh (寒尸冥 → 寒尸冥将, 赤瑶 → 赤瑶蚊), bên trái cho mọi nhóm (情谷 → 问情谷, 波特王国 → 费内波特王国).
  - Dừng nối: chữ dính là họ (五鬼老三|范…); ≥ 1/3 số lần dính là một hậu tố ≥ 2 chữ của danh sách bắt đầu ngay sau (穷朔|洞主) hoặc một danh xưng ≥ 2 chữ kết thúc ngay trước (老怪|卞琦); chữ dính + chữ dính kế là một từ của từ điển (无餍|真身, 魁首|厉辉); bên trái còn dừng ở hư từ / chữ thân tộc.
  - Bỏ cả cụm (`bound_glued`): dính hư từ mà cặp "chữ cuối + hư từ" không có trong từ điển và không phải danh xưng suy ra (宝剑锋|从, 艺多|不); lộ tên người mở đầu bằng họ vắt qua chỗ nối (天机阁主|姬长发); lộ thực thể vắt qua chỗ nối bên trái mà phần còn lại không phải hậu tố (熊妖|撼山妖尊, 镇北侯|潘凤 — 考伊姆|公司 thì giữ).
  - Danh xưng suy ra: cặp "chữ cuối + chữ dính" lặp ở ≥ 3 thực thể Nhân danh chưa có (冥将) ⇒ nối dù chữ dính là hư từ.
  - Cụm nối xong: đã là thực thể khác ⇒ `bound_merged`; là từ thường ⇒ `dict_common_word` (洗耳恭 → 洗耳恭听, 梁小丑 → 跳梁小丑); dính thực thể mạnh ⇒ `glued_fragment`. Loại của cụm nối tính bằng số đếm nhãn của cụm gốc (`kind(of:…statsOf:)`).
  - Nghĩa: nối đúng một chữ bên phải mà cặp "chữ cuối + chữ nối" có trong từ điển ⇒ cặp đó là danh xưng của riêng hàng này (`Row.dictionaryTitle`, `LocalNameFilterMeaningBuilder.meaning(…dictionaryTitle:)`) — 寒尸冥将 ra "Hàn Thi Minh Tướng" thay vì "Hàn Thi Minh Tương". `LocalNameFilterMeaningComposer` nhận ra danh xưng đó ở lần ghép lại bằng nghĩa máy lần trước.
- `dict_common_head` (K): "đầu 2 chữ là từ thường đứng riêng nhiều hơn hẳn" nay chỉ tính phần đầu không nằm trong thực thể 3 chữ nào mở đầu bằng nó. Trước đó 沈清瑶 (1.000 lần), 沈清霜 (768 lần), 沈清璇, 铁龙娘 (84 lần), 南城区, 王廷焕 bị bỏ khi chưa lưu name, vì VP có 沈清 = "trầm thanh" và mọi lần 沈清 đều nằm trong 沈清瑶 / 沈清霜.
- Bảy luật rác theo ngữ cảnh (`LocalNameFilterJunkRules.contextReason`, sau L24, chỉ name chưa có, chỉ đường có model LAC): `count_classifier` (chữ số + lượng từ 尊 位 名 个 座 ở đầu: 三尊诡物天尊), `jianghu_tail` (kết thúc bằng 江湖: 武者江湖, 陈诚江湖), `double_suffix` (hai chữ cuối là cùng một chữ đuôi: 紫府府), `small_generic` (địa danh / tổ chức = từ thường + 小 + đuôi 1 chữ: 黑色小湖), `prep_common` (1 chữ giới từ + từ thường: 朝城门, 朝山崖; `PREP_HEAD` thêm 必 ⇒ 必教), `fragment_multi` (≥ 90 % số lần chữ đứng ngay trước + cụm là name đã có hoặc là đuôi của một hàng: 元大陆 ⊂ 天元大陆 + 混元大陆, 山镇 ⊂ 珩琅山镇 + 罗山镇 + 鹤山镇), `demo_left` (địa danh / tổ chức ≥ 60 % số lần đứng ngay sau chữ chỉ định / chữ số: 这方天界, 一方大陆).
- Số đo trên bản Python (11 truyện, so với 1.3.1134): mất 73 hàng, thêm 44 hàng — phần lớn là cụm được nối cho đủ và tên được trả lại; name đã có không bị luật mới bỏ (luật chỉ xét name chưa có; đo thử trên name đã có: `fragment_multi` trúng 剑阁, 爱罗 — đều là mảnh của 洗剑阁, 我爱罗 —, `demo_left` trúng 成都). Danh sách "Không phải name" 137 cụm của anh: 43 / 81 (trước 32). Trên 110 name mới của file anh xuất: 19 tên được nối đủ, 21 cụm rác bị bỏ; rác còn lại là 19 cụm đều nằm trong danh sách chặn của anh (lúc anh lọc, danh sách chặn trên máy không còn các cụm đó) và 麾下宗门, 广派.
- Đã thử và gạt vì nhầm tên thật: nối trái vô điều kiện (厉辉 → 魁首厉辉), bỏ điều kiện họ của L20 (通天蛤蟆), "X小 + đuôi" không xét từ thường (莫尔斯小镇), danh xưng vắt qua cuối cho địa danh (清微洞|主).
- `.claude/rules/translation.md`: ghi đợt 4 và cách đo bằng file xuất của anh.
- Chưa build (máy Windows); chưa thử trên máy. Số đo là của bản Python tham chiếu, không phải của app.

## [1.3.1136] - 2026-11-28

### fix: phiên âm tiếng Nhật đọc được từ có nguyên âm dài như Mangekyō ở vtts, NghiTTS, Siri, Google và tiện ích

- Anh Bửu: "Sao bật phiên âm tiếng nhật rồi mà đọc chữ Mangekyō ko đc" → duyệt plan. Nguyên nhân: `ForeignScriptClassifier` chấm "mangekyo" 2 điểm (cụm `ng` bị trừ −2 như cụm tiếng Anh; `kyo` +2, đuôi nguyên âm +1, `n` riêng +1) < ngưỡng 4; luật tên viết hoa của VieNeu (đường dùng chung của vtts / Siri / Google / tiện ích, 1.3.1037) chỉ nhận chữ Latin không dấu mà `ō` chưa được gấp.
- `ForeignScriptClassifier`: từ có nguyên âm dài ā ī ū ē ō (tiếng Anh, tiếng Việt không có) mà gấp xong cắt hết được thành ≥ 2 âm romaji ⇒ romaji, khỏi chấm điểm (`hasHepburnLongVowel`, tham số `hadLongVowel` cho chỗ đã gấp dấu trước khi hỏi). Từ không có nguyên âm dài giữ nguyên cách chấm cũ.
- NghiTTS (`TextPreprocessor.transliterateToken` gấp dấu làm khoá đệm): truyền `hadLongVowel` của token gốc, khoá đệm thêm tiền tố `ō|` để "mangekyo" và "Mangekyō" không dùng chung kết quả. Chip gợi ý phiên âm (`TTSPhoneticSuggestionBuilder`) cũng xét nguyên âm dài trên từ gốc.
- `TTSJapaneseTextTransliterator` (vtts / Siri / Google / tiện ích): gấp ā ī ū ē ō trước khi hỏi luật tên viết hoa, như đường VieNeu.
- Ví dụ (mô phỏng bằng Python bảng âm tiết của `JapaneseTransliterator`): Mangekyō → "Man ghê kiô", Tōkyō → "Tô kiô", Ryūjin → "Riu gin", Kyūbi → "Kiu bi", Ōsaka → "Ô xa ka". VieNeu không đổi.
- Chưa biên dịch được tại chỗ (Windows), chưa nghe thử trên máy; check_architecture chỉ còn violation cũ JSDom.swift.

## [1.3.1135] - 2026-11-28

### feat: gỡ giọng vtts nam-1 và Google Dịch khỏi app, chỉ còn nu-10 và Ngọc Huyền

- Anh Bửu: "Cải thiện ngọc huyền, bỏ giọng nam và google đi" → duyệt "Cả 2". Danh sách giọng vtts có sẵn chỉ còn `Nữ · nu-10` và `Nữ · Ngọc Huyền` (+ giọng tự nhập). `VttsVoice.bundled = [.nu10, .ngocHuyen]`; bỏ `nam1` / `googleDich`. Ai đang chọn `nam-1` / `google-dich` (cả khi vtts là giọng dự phòng) ⇒ `VttsVoice.resolve` trả `nu-10` như mọi id lạ, không cần chuyển dữ liệu.
- Xoá khỏi repo + IPA: `assets/vtts/vtts-vien-nam1-m-v0.11.q8.vtts`, `assets/extra/vtts-vien-nam1-s-v0.11.q8.vtts`, `assets/vtts/vtts-googledich-m-k6.q8.vtts` (IPA nhẹ đi ~5 MB). Bản sao ở `D:\Documents\vtts-voices\` (`Nam nam-1 (v0.11 M/S).vtts`, `Google Dịch (k6 60k).vtts`) — cần thì nhập lại bằng "Nhập .vtts".
- `assets/SHA256SUMS` còn 2 dòng `nu-10` (nguyên văn release `v0.11.0`), `LOCAL_SHA256SUMS` bỏ dòng Google Dịch; `Scripts/ci/check_vtts_assets.sh`: `VOICES` còn 2 giọng, mong 2 dòng SHA256SUMS và đúng 3 file trong `assets/vtts/`; bước Package IPA của `build-ipa.yml` kiểm `lex_en.bin` + `nu-10` + Ngọc Huyền.
- `Vendor/vtts/README.md`, `THIRD_PARTY_NOTICES.md` (mục Google Dịch giữ để ghi nguồn cho bản 1.3.1046 – 1.3.1134), `.claude/rules/tts.md`, `.claude/rules/ci-release.md` cập nhật theo.
- Chưa biên dịch được tại chỗ (Windows); check_architecture chỉ còn violation cũ JSDom.swift.

## [1.3.1134] - 2026-11-28

### feat: lọc name local thêm luật L23 đến L25 bỏ mảnh cắt ngang từ, tên cắt mất danh xưng và cụm mở đầu bằng lượng từ

- Anh Bửu để Javis tự chọn ("tự chọn đi, cái nào bạn thấy ổn nhất") sau khi trình số đo Python; chọn L23 + L24 + phần lượng từ của L25, bỏ phần "số + 大" vì nó trúng cả tên nhóm (八大天君, 四大圣岛). Chép đúng bản tham chiếu `lacpipe.py` / `local_name_filter2.py`; chỉ đường có model LAC.
- L23 `glue_right_strong` (bộ luật, `LocalNameFilterRuleChecker`, ngay sau `glue_right`, chỉ khi `rulesV3` — đường lùi "chỉ bộ luật" không đổi): địa danh / tổ chức mà chữ cuối dính chữ ngay sau thành từ VP / danh xưng ở ≥ 80 % số lần ⇒ cụm cắt ngang một từ, bỏ dù phần trước đuôi không phải tên đã có — 先生帮 (帮忙), 风暴教 (教会), 周围海 (海边), 临济城城, 极乐宗门 (门下 / 门人), 守关军 (军士 / 军官), 马盛派 (派出).
- L24 `title_fragment` (`LocalNameFilterJunkRules`, xét sau cùng, chỉ name chưa có): Nhân danh `w` có hàng `w + c` xuất hiện ≥ 80 % số lần của `w` mà chữ cuối hoặc hai chữ cuối của `w` + `c` là hậu tố Nhân danh ⇒ tên bị cắt mất danh xưng — 萧太 (萧太上), 离乱天 (离乱天君), 封太 / 贝太 / 钟太 / 冯太 / 葛太 (…太上), 曜古天 (曜古天君); tên đủ đều còn trong danh sách. Tra bằng chỉ mục `w` ⇒ các hàng `w + c` dựng một lần thay vòng quét cả bảng của Python.
- L25 `quantity_head` (`LocalNameFilterJunkRules`, ngay sau L19, chỉ name chưa có): name ≥ 3 chữ mở đầu bằng lượng từ số đông 许多 诸多 众多 一众 无数 各大 所有 一些 这些 那些 其他 其余 — 许多大家族, 诸多大宗门, 一众江湖.
- Tên lý do y Python (`glue_right_strong` vào `luật bỏ […]`, `title_fragment` / `quantity_head` vào `bỏ […]`).
- Bản Python trên 11 truyện: bỏ thêm 30 hàng (đều rác / mảnh), không thêm, không đổi nghĩa; không name đã có nào bị mất. Đo bắt nhầm trên tên đã có: L24 trúng 1 (洪太 — trong truyện là mảnh của 洪太上), L25 trúng 0; L23 trúng 43 ứng viên đã có của bộ luật nhưng gần hết là mảnh đúng ngữ cảnh (柳宗 = 柳宗主, 炼器宗 = 炼器宗师, 林家族 = 林家族人) và hàng đã có của bộ luật vốn không hiện. Danh sách "Không phải name" của anh: 32 / 81 cụm (trước 31); 49 cụm còn lại cùng hình dạng với tên thật — các luật thử thêm đều nhầm tên đã có nên không làm.
- `.claude/rules/translation.md`: ghi đợt 3 và các luật đã thử rồi gạt.
- Chưa build (máy Windows); chưa thử trên máy.

## [1.3.1133] - 2026-11-28

### docs: ghi chú lọc name local cho sáu luật chặn rác L17 đến L22 và lịch sử lọc ghi cả lần không thành

Cập nhật `.claude/rules/translation.md` cho 1.3.1130 và 1.3.1132.
- Luật rác L17–L22 (`LocalNameFilterJunkRules`, sau L9, chỉ name chưa có, thứ tự `junk_reason`): điều kiện, ví dụ bỏ /
  giữ, số đo Python 85 hàng, các luật đã thử và gạt vì bắt nhầm tên thật (để khỏi đề xuất lại); bộ đếm
  `LocalNameFilterLACCounts.verbish`; đường lùi "chỉ bộ luật" không có L17–L22.
- Lịch sử lọc: ghi mục ngay lúc bấm "Bắt đầu lọc" / "Thử lại", bốn kết quả không thành (không ra name, lỗi, đã huỷ, bị ngắt),
  nền sẫm, không mở được, tính vào "N lần".

## [1.3.1132] - 2026-11-28

### feat: lọc name local chặn rác bằng sáu luật L17 đến L22 cho name chưa có ở đường có model LAC

- Sáu luật rác anh Bửu duyệt 2026-11-28 (đo trên danh sách "Không phải name" 137 cụm của anh), chép đúng `junk_reason` của bản tham chiếu `lacpipe.py`: chỉ name chưa có, chỉ đường có model LAC, chạy ngay sau L9 ở `LocalNameFilterOutputBuilder.withLAC` (đường lùi "chỉ bộ luật" không có, như L5 / L9). Bảng tra dựng một lần từ mọi hàng sau L9 (kể cả name đã có); luật đầu tiên khớp quyết lý do, thứ tự L17 → L18 → L19 → L20 → L22 → L21. Lõi ở `LocalNameFilterJunkRules` (file mới).
- L17 `glued_entities` (name ≥ 4 chữ): ghép từ hai name của chính danh sách (mỗi phần ≥ 2 chữ; phần sau có thể là name + hậu tố dò 2 rồi 1 chữ), chỗ tách đầu tiên có phần trước là name quyết — phần sau không phải Nhân danh ⇒ bỏ (中州嵩云宗, 镇魔司紫衣卫), là Nhân danh ⇒ giữ (翎王姬桓).
- L18 `prep_head`: địa danh / tổ chức / thuật ngữ có hậu tố (hàng bộ luật: đuôi đã dò; hàng LAC: hậu tố dò dài nhất) mà phần trước hậu tố đúng 1 chữ giới từ / chữ chỉ số đông `PREP_HEAD` (朝城, 处山脉, 替宗门, 由镇, 众村, 当庄).
- L19 `repeat_or_digit`: một chữ lặp ≥ 3 lần liền, hoặc có chữ số theo `str.isdigit` của Python (Numeric_Type Decimal / Digit: 0–9, ０–９…; chữ số Hán không tính) — 铿铿铿, 小成955/1000.
- L20 `common_phrase`: Nhân danh phía LAC (không phải hàng bộ luật), không mở đầu bằng họ, phủ trọn bằng ≥ 2 từ thường VP mỗi từ ≥ 2 chữ (khớp dài nhất từ trái, tối đa 6 chữ, không lùi), không kết thúc bằng chữ thân tộc `KIN_TAIL` hay hậu tố Nhân danh nào của danh sách hiệu lực — 幽蓝光影, 恐怖若斯, 炽白遁光 bỏ; 黑夜女神, 五鬼老三 giữ.
- L21 `name_fragment`: Nhân danh ≥ 3 chữ = Nhân danh khác của danh sách (≥ 100 lần) + 1 chữ, số lần < 1 % của tên đó, chữ cuối và hai chữ cuối đều không phải hậu tố Nhân danh — 陈诚头, 邓恩先, 宁天俏 bỏ; 王家主 giữ (家主).
- L22 `verb_head`: hàng bộ luật (bước hợp) địa danh / tổ chức có đuôi, < 20 lần, phần trước đuôi ≥ 2 chữ là từ thường VP mà LAC gán đứng riêng ≥ 20 lần, ≥ 60 % nhãn thuộc `VERBISH` (v vd vn p c d ad u xc r), chưa từng có nhãn thực thể (PER LOC ORG nz nw) — 拜入宗门, 赶往宗门, 虽然海, 直奔海 bỏ; 毁灭森林, 极北城, 冶炼司 giữ. `LocalNameFilterLACCounts` thêm bộ đếm `verbish` (số lần từ mang nhãn `VERBISH`, cộng dồn theo chương như `others`, chỉ từ có ít nhất một lần); hàng bộ luật mang thêm độ dài đuôi đã dò (`RuleRow.suffixLength`, chỉ địa danh / tổ chức).
- Tên lý do y Python (`LocalNameFilterRules.Reason`), vào `Snapshot.droppedByReason` và log `bỏ [...]` như các luật khác. `LocalNameFilterSetup` thêm `isPersonSuffix` / `endsWithPersonSuffix` (hậu tố Nhân danh của danh sách người dùng, mọi độ dài kể cả cả từ).
- Bản Python trên 11 truyện: bỏ 85 hàng, đều rác / name ghép; không thêm hàng, không đổi nghĩa hàng nào. Đo trên name đã có: L20 chỉ trùng 六道轮回, 太阳真火, 黑白无常 (3 / ~1.700 — name đã có vẫn giữ), L22 trùng 0.
- Chưa build (máy Windows); chưa thử trên máy.

## [1.3.1131] - 2026-11-28

### feat: giọng vtts Ngọc Huyền đổi sang bản joint 80k và Google Dịch sang mốc joint 60k của lượt train vtts-k6

Hai giọng vtts tự train chạy tiếp từ joint 20k (lượt Kaggle `vtts-k4`) lên joint 80k ở lượt `vtts-k6` (28/11, công thức chưng cất upstream v0.9.1 — cách upstream chữa lớp ồn "buzzy" của `nu-10` ở 1.3.1052; hướng chữa rè anh Bửu duyệt 24/11). Chọn mốc theo luật anh duyệt: **UTMOS tiếng Việt cao nhất** (notebook chấm từng mốc 10k bằng runtime C `vtts_say --lang auto`, 12 câu tiếng Việt kiểu truyện + 4 câu trộn / Anh; điểm = UTMOS tiếng Việt / câu khác / whistle):

- **Ngọc Huyền** (`ngoc-huyen`) ⇒ `Vendor/vtts/assets/vtts/vtts-ngochuyen-m-k6.q8.vtts` = `distill_nh/snapshots/M-vocos-p-bi-joint_0080000.q8.vtts` (trùng byte file cuối của chuỗi): 20k 2,284 / 2,74 / 1,09 → **80k 2,619 / 2,946 / 0,50**. SHA256 `b98851c847965987c985a5c1dbb5e35e13dcee4fe62a8556fbb3e4f95940c014`.
- **Google Dịch** (`google-dich`) ⇒ `vtts-googledich-m-k6.q8.vtts` = `distill_gg/snapshots/M-vocos-p-bi-joint_0060000.q8.vtts` (mốc 60k, **không** phải file cuối 80k): 20k 2,70 / 2,749 / 3,97 → **60k 2,907 / 2,94 / 4,12**; bản 80k 2,665 / 2,716 / 0,75 — ít rít hơn hẳn nhưng UTMOS tiếng Việt thấp hơn cả bản cũ. SHA256 `50843a9eab7b3825e15c7a4edc95d542d97ac44c379db67077b334474743d4ac`.
- Thầy VITS: Ngọc Huyền 3,157, Google Dịch 3,554. Không hứa hết rè: UTMOS không trùng hẳn với "rè" tai nghe, rè của Google Dịch có sẵn trong tiếng Google Dịch gốc.
- Hai file mới 2 580 320 byte như bản k4; header (33 dim, 122 tensor, `token_set` vi-en, cả bảng 10 968 byte đầu) trùng từng byte với bản k4. `git rm` hai file `-k4`; `assets/vtts/` vẫn đúng 5 file.
- `VttsVoice.ngocHuyen` / `.googleDich`: đổi `fileName`, **giữ id** (lựa chọn đã lưu còn nguyên), giữ `defaultLoudnessGainDb` 7,5 / 8 — đo trên bản k4, **chưa đo lại** trên bản k6 (máy Windows không có trình biên dịch C để chạy `vtts_say`).
- `LOCAL_SHA256SUMS`, `VOICES` của `Scripts/ci/check_vtts_assets.sh`, `Vendor/vtts/README.md` (nguồn gốc + bảng điểm từng mốc), `THIRD_PARTY_NOTICES.md` (lượt train; giấy phép giữ CC BY-NC 4.0 — cùng thầy, cùng dữ liệu), `.claude/rules/tts.md`, `ci-release.md`. Bước Package IPA của `build-ipa.yml` chỉ kiểm `lex_en.bin` + hai giọng release ⇒ không đổi.
- Kiểm tại chỗ: phần SHA256 + đếm file của `check_vtts_assets.sh` qua; phần dựng `vtts_say`, đọc thử từng giọng và shim ASan/UBSan **chưa chạy** (không có clang) — CI chạy. `check_architecture.py` chỉ còn violation cũ `JSDom.swift`. Chưa biên dịch, chưa nghe thử trên máy.

## [1.3.1130] - 2026-11-28

### feat: lịch sử lọc name local ghi cả lần không ra name, lỗi, huỷ và lần bị ngắt khi app thoát lúc đang lọc

Lịch sử lọc ghi **mọi** lần bấm "Bắt đầu lọc" (anh Bửu duyệt mockup bản 8, khung H2 có 4 hàng nền sẫm, https://claude.ai/artifact/JwiiU3XFYTk7Rz1hAMS7G2):

- `LocalNameFilterHistoryEntry` thêm `outcome` (`running` / `reviewed` / `noNames` / `failed` / `cancelled`), `failureMessage`, `launchId`; phạm vi, số chương, số lọc được đổi thành `var`. File của bản trước (không có `outcome`) đọc ra `reviewed` (`init(from:)` đọc kiểu "có thì lấy"). `currentLaunchId` = mốc của lần chạy app.
- `LocalNameFilterSession+History`: bấm "Bắt đầu lọc" / "Thử lại" ⇒ ghi ngay mục "đang lọc" kèm mốc lần chạy app; lấy xong danh sách chương ⇒ ghi phạm vi định lọc; kết thúc cập nhật đúng một lần (`endHistory`): ra màn duyệt (id mục = id gói tạm như trước), không ra name nào (kể cả "Dừng" lúc đang lấy chương / chuẩn bị model ⇒ "0 chương (dừng)"), lỗi (lời lỗi đầy đủ, giữ phạm vi định lọc; phạm vi không có chương đã tải ⇒ "0 chương"), đã huỷ (đóng sheet lúc đang lọc, phạm vi = các chương đã đọc tới + "(huỷ)"). `LocalNameFilterHistoryStore.update(id:)` sửa một mục trong một lần giữ khoá.
- `LocalNameFilterHistorySnapshot.Status` thêm `running`, `interrupted` (mục còn "đang lọc" mà mốc khác lần chạy app này ⇒ app thoát / chết lúc đang lọc), `noNames`, `failed`, `cancelled`; `isInactive` cho cả năm. "M chưa lưu" chỉ tính lần ra màn duyệt.
- Trang Lịch sử lọc: hàng "— Không ra name nào", "✕ Lỗi: <lý do ngắn>" (chữ đỏ; phần trước dấu ":" / " — " của lời lỗi, chữ đầu viết thường — vd "không tải được model nhận diện tên"), "⊘ Đã huỷ", "⚠ Bị ngắt — app thoát lúc đang lọc" (cam); nền sẫm (`LocalNameFilterHistoryRow.inactiveFill`, hàng thường đặt lại đúng ô mờ của sheet kính), không chevron, chạm không mở gì, vẫn vuốt xoá / chọn nhiều / dọn dẹp tất cả được (hỏi "Chỉ xoá dòng lịch sử."), tính vào "N lần". Giải thích "?" thêm đoạn về lần không ra màn duyệt.

## [1.3.1129] - 2026-11-28

### feat: danh sách Hậu tố, Tiền tố và Không phải name của lọc name local xuất được ra file để gửi

Anh Bửu (2026-11-28): "thêm chức năng xuất danh sách tiền tố hậu tố và lọc rác tôi gửi cho điều tra", "tôi đã thêm vào danh
sách không phải name nhiều lắm. Mà ko xuất được để gửi bạn".
- Ngăn kéo `…` của ba màn (`LocalNameFilterSuffixListView` cho Hậu tố / Tiền tố, `LocalNameFilterBlocklistView`) có
  "Xuất file" (mờ khi danh sách rỗng): xuất **đúng danh sách của chip phạm vi đang chọn** (Chung hoặc Riêng truyện), không
  theo ô tìm / chip loại; mở bảng chia sẻ hệ thống (`ShareSheet`).
- Định dạng như file gốc để đọc lại được: hậu tố / tiền tố `chữ Hán=nghĩa|loại|vị trí` (như `NameFilterSuffixes.txt`),
  Không phải name mỗi dòng một cụm; dòng đầu `# <danh sách> · <phạm vi> · N mục · xuất <giờ>`. Tên file
  `HauTo|TienTo|KhongPhaiName_<Chung|RiengTruyen>_<yyyyMMddHHmmss>.txt`. Helper mới `LocalNameFilterListExport`.
- Ghi file lỗi ⇒ toast lỗi + log ❌. `translation.md` ghi thêm.
Chưa biên dịch được tại chỗ (Windows); check_architecture chỉ còn violation cũ JSDom.swift.

## [1.3.1128] - 2026-11-28

### docs: ghi chú lọc name local cho lõi Latin tin Name, Nới đoán tên Latin, Không phải name riêng truyện, ghim R C và lịch sử lọc

Cập nhật `.claude/rules/` cho đợt 1.3.1121–1127 (mockup N1–N6, H1–H5 https://claude.ai/artifact/JwiiU3XFYTk7Rz1hAMS7G2).
- `translation.md`: lõi tên Latin tin mục Name / VP riêng (`trustedValue`, `latinCore(of:)`); công tắc Nới đoán tên Latin
  theo truyện + theo name (kèm số đo vì sao mặc định tắt); `rulesVersion` 4; bản tham chiếu `latin_core_of` (env `NAMES`,
  `LOOSE`); Không phải name riêng truyện + thùng rác ba lựa chọn; ghim R | C + badge R / C; Lịch sử lọc thay section gói tạm.
- `ui-conventions.md`: ghim R | C và badge góc của chip ✓.
- `storage.md`: khoá `localNameFilterLooseLatinByBook`, `localNameFilterBookBlockedTerms`, thư mục `name_filter_history/`.
- `books-sources.md`: các kho theo truyện mới trong Đổi nguồn / xoá truyện.

## [1.3.1127] - 2026-11-28

### feat: sheet lọc name local thay gói tạm chưa lưu bằng hàng Lịch sử lọc và trang lịch sử riêng có xoá, dọn dẹp, chọn nhiều

Giao diện Lịch sử lọc theo mockup H1–H5 anh Bửu đã duyệt (https://claude.ai/artifact/JwiiU3XFYTk7Rz1hAMS7G2):

- H1 (`LocalNameFilterSheet+History`, thay `+Drafts`): bỏ section "Gói tạm chưa lưu (N)"; đầu sheet là hàng "Lịch sử lọc ›" — dòng phụ "Lần gần nhất dd/MM HH:mm", bên phải "N lần · M chưa lưu" (M = lần chưa lưu còn gói tạm, màu cam), chưa có ⇒ "Chưa có". Chạm ⇒ đẩy trang lịch sử vào `NavigationStack` của sheet (`navigationDestination(isPresented:)`). Mở lại gói từ trang lịch sử rồi bấm ‹ ở màn duyệt ⇒ về lại trang lịch sử.
- H2 (`History/LocalNameFilterHistoryView`, `LocalNameFilterHistoryRow`): trang `.backPageTitle("Lịch sử lọc")`, nhóm theo ngày ("Hôm nay · 28/11", "27/11"…, giờ 24 giờ cố định), mới nhất trên cùng. Hàng "HH:mm · phạm vi" (lần Dừng có "(dừng)"); dòng 2 "✓ Đã lưu X / Y" (✓ xanh, chỉ xem) / "● Chưa lưu · lọc được Y" (● cam + chevron, chạm ⇒ mở lại màn duyệt như chạm gói tạm trước đây) / "Chưa lưu · lọc được Y · Gói tạm đã bị xoá" (mờ, không mở được). Mỗi lần trang hiện ra gói tạm vẫn tự cập nhật như cũ (`LocalNameFilterDraftRefresher.currentInputs` dùng chung với sheet). Đoạn giải thích cũ của section gói tạm dời vào nút "?" ở nhóm ngày đầu.
- H3: vuốt trái ⇒ Xoá ⇒ hỏi "Xoá lần lọc 10:20?" (ngày khác: "27/11 22:14"); còn gói tạm ⇒ "Gói tạm N name chưa lưu của lần này cũng bị xoá."; đã lưu ⇒ chỉ xoá dòng, name đã lưu giữ nguyên.
- H4 (`+Delete`): ⋯ ⇒ ngăn kéo "Lịch sử lọc · N lần": "Chọn nhiều để xoá", "Dọn dẹp tất cả" (đỏ, dòng phụ "N lần · M gói tạm chưa lưu" — hàng `LocalNameFilterHistoryDrawerRow` vì `SideDrawerActionRow` chỉ có chữ phụ bên phải), hỏi "Xoá N lần lọc?" + số gói tạm bị xoá theo.
- H5: chế độ chọn nhiều kiểu Kệ — header ✕ + "Đã chọn N" + "Chọn tất cả" / "Bỏ chọn tất cả" (một `.pageTitle` đổi tham số, ẩn nút back), chạm hàng để tích (không mở gói, không vuốt), thanh đáy "N lần · M gói tạm chưa lưu" + nút đỏ "Xoá (N)" ⇒ hỏi lại; ✕ hoặc xoá xong ⇒ về như thường. Xoá xong toast "Đã xoá N lần lọc · M gói tạm".

## [1.3.1126] - 2026-11-28

### feat: lọc name local ghi lịch sử lọc theo truyện, mỗi lượt ra màn duyệt một mục, lưu xong đánh dấu đã lưu

Kho Lịch sử lọc của Lọc name local (anh Bửu duyệt mockup + plan "Lịch sử lọc — H1–H5", https://claude.ai/artifact/JwiiU3XFYTk7Rz1hAMS7G2) — phần lõi, chưa có giao diện:

- `LocalNameFilterHistoryEntry` (Services/Translation/NameFilter/History/): giờ bấm "Bắt đầu lọc", phạm vi (`LocalNameFilterDraft.scopeLabel`, lần Dừng là các chương đã đọc tới, cờ `wasStopped` ⇒ "(dừng)"), số chương, số name lọc được, số name thực lưu + lúc lưu. `id` trùng id gói tạm của màn duyệt lượt đó ⇒ gắn gói, đánh dấu đã lưu, tạo mục cho gói cũ đều tra theo id.
- `LocalNameFilterHistoryStore`: mỗi truyện một file `name_filter_history/<sha256(bookId)>.json`, **không giới hạn** số mục, đọc ra mới nhất trước; khoá + ghi `.atomic` + cất bản `.broken-…` như kho gói tạm. Đổi nguồn chép (gộp theo id, đích thắng), xoá truyện / đổi nguồn xong xoá (`BookSourceMigrator`, `BookStorageManager.deleteBookSideData` + hàng đợi xoá lại), Dung lượng chung hàng gói tạm (đổi tên "Lọc name (gói tạm, lịch sử)", giữ rawValue `nameFilterDrafts`), Dọn rác bắt file của truyện không còn trong thư viện (`JunkPaths.nameFilterHistoryRoot` + `allowedRoots`, `JunkScanner`). Sao lưu không gói.
- `LocalNameFilterHistorySnapshot` + `LocalNameFilterHistoryStore.snapshot(bookId:)`: đọc lịch sử + gói tạm cùng lúc; trạng thái **suy ra** — đã lưu / chưa lưu còn gói (mở lại được) / chưa lưu mà gói không còn ("Gói tạm đã bị xoá": bị đẩy ra vì quá 5 gói, bộ cập nhật bỏ hết name…). Gói tạm chưa có mục nào trỏ tới (gói có từ trước bản này) ⇒ tạo mục "chưa lưu" lúc đọc; tra theo id nên không tạo trùng.
- `removeEntries(ids:)`: xoá gói tạm trước rồi mới tới mục; name đã lưu vào Name / VP riêng không bị đụng. `LocalNameFilterDraftStore.delete(ids:)` xoá nhiều gói một lần ghi.
- `LocalNameFilterSession+History`: lượt lọc ra màn duyệt (có name) ghi mục; "Dừng" mà bộ lọc kịp đọc hết phạm vi thì không tính là dừng. Lượt không ra name / lỗi / huỷ không ghi mục.
- `LocalNameFilterSheet.save`: lưu xong ⇒ mục thành "Đã lưu X / Y" (X = `ExtractedEntriesSaveResult.saved`; "Chỉ thêm key mới" chỉ đếm mục mới), mục chưa có thì dựng từ gói của màn duyệt.

## [1.3.1125] - 2026-11-28

### fix: hàng Nới đoán tên Latin ở màn Sửa từ có nhãn vàng đoán khi nghĩa hiện tại của name do máy đoán

Nối tiếp "lọc name local tin Name và VP riêng cho lõi tên Latin, thêm công tắc Nới đoán tên Latin theo truyện và theo name" (mockup https://claude.ai/artifact/JwiiU3XFYTk7Rz1hAMS7G2 khung N6; session chính chốt 2026-11-28).

- Mockup N6 vẽ nhãn "đoán" trong ô nghĩa của màn Sửa từ; vì `DictEntryEditSheet.swift` sát 400 dòng, nhãn vàng "đoán" (cùng kiểu nhãn của hàng màn duyệt `ReaderAINameReviewBadges`: chữ vàng, viền vàng mờ) đặt ở cuối hàng "Nới đoán tên Latin", ngay trước công tắc (`LocalNameFilterReviewLooseRow.isGuessed`), không đụng file gốc của màn Sửa từ.
- Theo cờ `isGuessedMeaning` của name đang sửa (`LocalNameFilterReviewAffixRows.isGuessedMeaning`, `ReaderAINameReviewSheet+Edit` truyền mỗi lần dựng) ⇒ bật / tắt Nới ghép lại ra nghĩa đoán / không đoán thì nhãn hiện / ẩn theo. Nhãn thấp hơn công tắc nên hàng không cao thêm, nấc vừa khít không đổi.

## [1.3.1124] - 2026-11-28

### fix: sửa tiền tố hậu tố có sẵn mà nhấn giữ R hoặc C thì chỉ ghim mặc định, không đổi phạm vi của mục đang sửa

Nối tiếp "màn Sửa từ của lọc name local ghim được R hoặc C làm mặc định khi thêm tiền tố hậu tố" (mockup https://claude.ai/artifact/JwiiU3XFYTk7Rz1hAMS7G2 khung N3; session chính chốt 2026-11-28).

- `DictEntryEditScopeToggle` thêm `selectsOnPin` (mặc định `true`): thêm mới ⇒ nhấn giữ vừa ghim vừa chọn luôn nút đó như trước; `false` ⇒ chỉ ghim mặc định + toast, phạm vi đang chọn giữ nguyên.
- `LocalNameFilterSuffixEditorSheet` truyền `selectsOnPin: original == nil` ⇒ sửa mục có sẵn (màn danh sách, chip ✓, màn Quản lý) nhấn giữ không còn chuyển mục R sang C (đường R → C ghi đè Chung) hay ngược lại; đổi phạm vi của mục chỉ bằng chạm R / C.

## [1.3.1123] - 2026-11-28

### feat: màn Sửa từ của lọc name local ghim được R hoặc C làm mặc định khi thêm tiền tố hậu tố, chip có sẵn mang badge R hoặc C

Đợt bổ sung 28/11 chiều (mockup https://claude.ai/artifact/JwiiU3XFYTk7Rz1hAMS7G2 khung N2, N3; plan "Plan đợt bổ sung", anh Bửu duyệt).

- Ghim R | C (N3): cụm R | C của màn Thêm / Sửa tiền tố, hậu tố (`DictEntryEditScopeToggle`) nhận nhấn giữ 0,4 s như panel Dịch (`dictSegmentButton`): nhấn giữ R hoặc C ⇒ ghim nút đó làm mặc định + chọn luôn + toast "Đã ghim mặc định Phạm vi: Riêng / Chung", ghim cam `CoverPinBadge` ở góc trên phải; nhấn giữ nút đang ghim ⇒ bỏ ghim (toast). Nhớ bằng `@AppStorage` khoá `localNameFilterAffixScopePin` ("" chưa ghim / "book" / "common", chữ thường không dấu chấm). Trợ năng: giá trị "Đang ghim mặc định" + thao tác "Ghim / Bỏ ghim mặc định".
- Ghim chỉ quyết định phạm vi chọn sẵn khi thêm từ chip "+ X" và "+ Thêm tiền tố / hậu tố" ở màn Sửa từ của màn duyệt (`LocalNameFilterSuffixQuickRow`, `DictEntryEditScopeToggle.defaultIsBookScope`); chưa ghim ⇒ R như trước. "+ Thêm" trong nhóm của màn Quản lý tiền tố, hậu tố vẫn theo nhóm, màn danh sách theo chip phạm vi, sửa mục có sẵn theo phạm vi của mục.
- Badge R / C trên chip ✓ (N2): chip mục có sẵn ở hàng Tiền tố / Hậu tố mang badge góc trên phải như chip nghĩa (`ChipCornerBadge(scope:)` — `SuggestionChip.Scope`: R nền đỏ chữ trắng = riêng truyện, C nền xám = chung), theo mục hiệu lực (Riêng thắng Chung cùng chữ); dấu ● giữ. Hàng chip chừa `ChipCornerBadge.inset` trên / phải để badge không bị `ScrollView` cắt — phần chừa nằm trong `accessoryRows` nên nấc vừa khít của màn Sửa từ tự tính.

## [1.3.1122] - 2026-11-28

### feat: lọc name local có danh sách Không phải name riêng truyện, thùng rác ba lựa chọn và chip phạm vi ở màn danh sách

Đợt bổ sung 28/11 chiều (mockup https://claude.ai/artifact/JwiiU3XFYTk7Rz1hAMS7G2 khung N1, N4; plan "Plan đợt bổ sung", anh Bửu duyệt).

- Kho mới `LocalNameFilterBookBlocklistStore` (Services/…/NameFilter/Lists): `UserDefaults` khoá `localNameFilterBookBlockedTerms` = JSON `{bookId: [{term, addedAt}]}` (chữ thường không dấu chấm ⇒ Backup tự gói), cùng luật cụm với danh sách Chung (`LocalNameFilterBlocklistStore.formatError`, nay `internal static`), trần 5.000 cụm mỗi truyện, trùng trong cùng truyện ⇒ không thêm lần nữa. Cùng cụm với danh sách Chung thì được — hai danh sách độc lập (xoá khỏi Chung thì truyện vẫn chặn). Đổi nguồn gộp theo cụm, ngày thêm của truyện cũ thắng (`BookSourceMigrator.copyBookScopedSettings`); xoá truyện / bản cũ xoá (`removeBookScopedSettings`, `BookStorageManager.deleteBookSideData`).
- Bộ lọc của truyện chặn theo Chung + Riêng: `LocalNameFilterBookBlocklistStore.effectiveTerms(bookId:)` cho `Configuration.blockedTerms` lúc bấm "Bắt đầu lọc" và cho gói tạm tự cập nhật (`LocalNameFilterDraftRefresher` bỏ name bị chặn ở cả hai).
- Thùng rác mỗi hàng của màn duyệt luồng lọc local (N1): "Bỏ khỏi lần này" · "Không phải name · riêng truyện" · "Không phải name · mọi truyện" (chữ đỏ). Phạm vi đi qua kiểu công khai mới `LocalNameFilter.BlockScope` (`ReaderAINameReviewCardView.onBlock`, `ReaderAINameReviewSheet.onBlockName` đổi chữ ký — chỉ `LocalNameFilterSheet` dùng); toast "Đã thêm X vào “Không phải name” (riêng truyện / mọi truyện)".
- Màn "Không phải name" (N4): `LocalNameFilterBlocklistView(bookId:)` mở từ sheet Lọc name local có hàng chip phạm vi "Chung N · Riêng truyện N" như màn Hậu tố (M6, `LocalNameFilterAffixKindFilterBar.chip`), mặc định Chung; thêm / sửa / xoá / Xoá hết theo chip đang chọn; màn Sửa từ của danh sách (`LocalNameFilterBlocklistEditorSheet`) có badge "Không phải name · Chung" / "· Riêng truyện" và kiểm trùng ở đúng danh sách (không có cụm R | C). Sheet Lọc name local: hàng "Không phải name" ghi "214 · 3 riêng"; lời "?" của mục Danh sách nói thêm bản riêng.

## [1.3.1121] - 2026-11-28

### feat: lọc name local tin Name và VP riêng cho lõi tên Latin, thêm công tắc Nới đoán tên Latin theo truyện và theo name

Đợt bổ sung 28/11 chiều (mockup https://claude.ai/artifact/JwiiU3XFYTk7Rz1hAMS7G2 khung N2, N5, N6; plan "Plan đợt bổ sung", anh Bửu duyệt). Bản tham chiếu: `latin_core_of` của `Docs/Plans/local-name-filter-lac/name_meaning.py` (tham số `trusted`, `loose`).

- Hướng a — lõi tên kiểu Latin tin mục người dùng đã chốt: `LocalNameFilterProperNames.latinCore(of:)` (file `+Latin`, chỉ `latinAffixed` gọi; tiền tố của mảnh tên `prefixed` vẫn dùng `latinName(of:)` như `latin_of`). Lõi (sau khi bỏ tiền tố / hậu tố) khớp trọn một mục Name (riêng → Chung → gốc trừ đã xoá) hoặc VP riêng của truyện (`LocalNameFilterDictionaries.trustedValue`, không gồm VP Chung / gốc) mà nghĩa chọn bằng `pick` là chữ Latin ⇒ nhận luôn, không xét bộ chữ phiên âm; nghĩa đó không phải chữ Latin ⇒ đi tiếp như cũ. "Khác âm Hán-Việt" vẫn xét ở `latinAffixed`. VP Chung / gốc giữ chốt chữ phiên âm (chặn 黑礁 "Black Lagoon"). 图铎 = Tudor (Name) ⇒ 图铎家族 "Tudor gia tộc". Luật phân loại L16 (`hasLatinCore`) không đổi (Python `latin_core` không dùng `trusted` / `LOOSE`).
- Hướng b — công tắc "Nới đoán tên Latin" (mặc định tắt): bước mô hình đoán của **lõi** nhận lõi có ≥ một nửa số chữ là chữ phiên âm (`looksTransliterated`) thay vì mọi chữ (`LocalNameFilterProperNames.loosensLatinCore`, `Configuration.loosensLatinGuess`). Chỉ có tác dụng cùng "Ưu tiên tên Latin"; mọi chỗ truyền giá trị hiệu lực `LocalNameFilterLatinPreferenceStore.loosensLatin(bookId:)` (Latin và Nới).
- Kho theo truyện: `LocalNameFilterLatinPreferenceStore` thành hai thể hiện `shared` ("Ưu tiên tên Latin", khoá `localNameFilterLatinByBook`) và `loose` (khoá `localNameFilterLooseLatinByBook`, chữ thường không dấu chấm ⇒ Backup tự gói); Đổi nguồn chép (`BookSourceMigrator.copyBookScopedSettings`), xoá truyện / bản cũ xoá (`removeBookScopedSettings`, `BookStorageManager.deleteBookSideData`).
- Sheet Lọc name local (N5): hàng "Nới đoán tên Latin" + `?` + dòng phụ "Lõi chỉ cần ½ số chữ là chữ phiên âm" ngay dưới "Ưu tiên tên Latin"; tắt Latin ⇒ hàng mờ, công tắc khoá (giá trị đã lưu giữ nguyên). Log cuối lượt ghi "Latin bật (nới)".
- Màn Sửa từ của màn duyệt (N6): hàng "Nới đoán tên Latin" + `?` + công tắc ngay dưới hàng Phân loại (`LocalNameFilterReviewLooseRow`), chỉ khi truyện bật "Ưu tiên tên Latin" và name có nghĩa máy ghép (trừ họ tộc). Áp **chỉ cho name đang sửa**: ghi đè nằm ở nghĩa máy ghép của gói tạm (`LocalNameFilterDraft.AutoMeaning.loosensLatin`, trường tuỳ chọn — gói cũ đọc được; init bắt buộc truyền để mọi lần ghép lại giữ ghi đè), `LocalNameFilterReviewSuffixContext.changeLoose` xếp cùng hàng đợi với thêm hậu tố / đổi Phân loại, ghép lại name đó theo công tắc mới; nghĩa máy đổi ⇒ áp lên hàng kể cả nghĩa đã sửa tay (mockup N6), cờ "đoán" theo kết quả, ô nghĩa của màn Sửa từ theo; không đổi ⇒ toast nhắc. Giá trị mở đầu = ghi đè của name, chưa có ⇒ công tắc của truyện.
- Bộ ghép nghĩa: `LocalNameFilterMeaningComposer.init?(…, loosensLatin:)` + `meaning(…, loosensLatin:)` (ghi đè theo name, dựng bộ ghép thứ hai khi cần); dấu gói tạm `signature(…, loosensLatin:)` (bắt buộc, cả ba chỗ tính dấu truyền giá trị hiệu lực của truyện — ghi đè theo name không vào dấu, nó áp lúc ghép lại); gói tạm tự cập nhật / ghép lại sau khi thêm hậu tố / đổi Phân loại đều ghép theo ghi đè của từng name. `rulesVersion = 4` ⇒ mọi gói tạm ghép lại một lần (nghĩa đã sửa tay giữ).
- Nấc vừa khít của màn Sửa từ: hàng Nới nằm trong `accessoryRows` và hiện / ẩn quyết định đồng bộ lúc dựng sheet ⇒ `DictEntryEditSheet+FittedDetent` đo cả hàng ngay lần đầu, không cần sửa cách đo.

## [1.3.1120] - 2026-11-28

### fix: bấm thể loại lúc màn xem đang tải phim sắp tự phát không đóng màn kẻo huỷ lượt phát

Vá 1.3.1119: màn bìa (`!watchOwnsSession`) hiện cả lúc phim đang tải mà "Tự phát" bật (hoặc tự sang phim đề xuất /
mục playlist, hoặc vừa bấm ▶ đang chuẩn bị) — bấm thể loại / Xem thêm lúc đó, lối "đóng màn rồi mở trang" chạy
`watch.cancel()` nên phim chưa kịp phát đã bị huỷ.
- `VideoWatchModel.isAboutToPlay` (`+Playback`): đang chuẩn bị phát, hoặc chưa xét tự phát (`didConsiderAutoplay`) mà
  tự phát / `autoNext` / `playlistStart` sẽ phát khi mục lục sẵn sàng (phim lỗi thì không).
- `VideoPlayerScreen+Exit.openCategory`: chỉ đóng màn bìa khi không `isAboutToPlay`; còn lại giữ trang đè lên màn xem
  như trước 1.3.1119 (phim tải xong vẫn tự phát bên dưới, chọn phim đổi tại chỗ).
- Ghi chú `.claude/rules/comic-video.md`. Chưa build (Windows), chưa thử máy.

## [1.3.1119] - 2026-11-28

### feat: chọn phim trong danh sách thể loại mở từ màn xem phim giữ lại danh sách, thu nhỏ phim là về lại danh sách

Anh Bửu: vào danh sách video từ màn xem phim, bấm một video khác rồi thu nhỏ hay bấm cửa sổ nhỏ thì phải về lại danh sách
vừa mở, không về màn đầu.
- `VideoWatchPagePresenter.openCategory(_:packageId:sourceName:modelContainer:)` (trang mở sau khi màn xem đóng): chọn
  phim ⇒ **không đóng trang** nữa, gọi thẳng `VideoWatchPresenter.present` ⇒ màn xem mới nằm trên trang (dùng lại lối
  "màn xem mở lại từ cửa sổ nhỏ nằm trên trang" đã có từ 1.3.781: hướng xoay, `closeAllPages` trước khi đổi tab).
  Vuốt xuống / ⌄ / nút Cửa sổ nhỏ chỉ đóng màn xem (`dismissCoveringPage` bỏ qua trang không đè lên màn) ⇒ về danh sách.
- `VideoPlayerScreen+Exit.openCategory`: màn đang hiện bìa (phim khác chạy nền) bấm thể loại / Xem thêm ⇒ đóng màn
  (`leave(stopPlayback: false)`, phim nền không bị đụng) rồi mở trang như lúc phim đang phát; `‹` ở trang về màn bên
  dưới, không về lại bìa (anh chọn). Phim nhúng trang (thu nhỏ là trang nhúng chết) giữ trang đè lên màn xem, chọn phim
  đổi tại chỗ.
- Giữ nguyên: `‹` của trang về màn gốc; bấm thể loại khác trong phim mới ⇒ trang mới thay trang cũ; nút Home về Khám phá
  và đóng luôn trang. Màn nghe nhạc không có trang danh sách mở từ trong nó nên không đổi.
- Ghi chú: `.claude/rules/comic-video.md`. Chưa build (Windows), chưa thử máy.

## [1.3.1118] - 2026-11-28

### docs: ghi chú lọc name local cho tiền tố hậu tố riêng truyện, tên kiểu Latin, luật L16, nút ▼ xuất file và hàng Phân loại

Cập nhật `.claude/rules/` cho đợt 1.3.1112–1117 (plan / mockup https://claude.ai/artifact/JwiiU3XFYTk7Rz1hAMS7G2).
- `translation.md`: kho tiền tố / hậu tố riêng truyện (`LocalNameFilterBookAffixStore`, danh sách hiệu lực Riêng + Chung,
  API phạm vi R | C và luật chuyển C → R / R → C); tên kiểu Latin `latinAffixed`; L16; `rulesVersion` 3; bản tham chiếu
  Python `latin_affixed` / `latin_core`; chip phạm vi ở màn danh sách; nút ▼ + Xuất file; màn Quản lý tiền tố, hậu tố;
  hàng Phân loại; sheet Sửa từ vừa khít; cụm R | C ở màn Sửa từ chế độ danh sách.
- `ui-conventions.md`: cụm R | C (`DictEntryEditScopeToggle`, chỗ cắm `caseRowTrailing` / `interceptSave`); tên file xuất
  `DictionaryExportFileName`; nút ▼ của màn duyệt name.
- `storage.md`: khoá `localNameFilterBookSuffixes` / `localNameFilterBookPrefixes`.

## [1.3.1117] - 2026-11-28

### fix: sửa hậu tố tiền tố có sẵn mở màn Sửa từ với cả name, chữ của mục chọn sẵn, chọn chữ khác là đổi chữ của mục

Khớp mockup bản 3 khung M5b (https://claude.ai/artifact/JwiiU3XFYTk7Rz1hAMS7G2, anh Bửu duyệt) — trước đó màn Sửa từ chỉ hiện chữ của mục.

- Chạm chip có sẵn ở màn Quản lý tiền tố, hậu tố và chip ✓ ở hàng Tiền tố / Hậu tố của màn duyệt lọc name local ⇒ màn Sửa từ với **cả name** (古赫密斯语), chữ của mục chọn sẵn (语, phần còn lại mờ), nới / thu bằng ‹ › như khi thêm. Hậu tố ưu tiên lần nằm cuối, tiền tố lần nằm đầu (`LocalNameFilterAffixListFlavor.selection(of:in:)`).
- Lưu: phần chọn là chữ cũ ⇒ cập nhật mục (nghĩa / loại / vị trí / R | C như trước); chữ khác (phải nằm cuối với hậu tố / đầu với tiền tố) ⇒ đổi chữ của mục — thay khoá cũ cùng phạm vi, kiểm trùng như đổi chữ gốc, dòng "Đổi 语 thành 斯语"; "Cập nhật" mờ + dòng nhắc khi không nằm cuối / đầu, chọn cả cụm, quá 6 chữ như M5. Ô nghĩa: chữ cũ ⇒ nghĩa đang lưu, chữ khác ⇒ phiên âm (đã gõ thì giữ). "Về bản gốc" giữ. Đổi chữ chưa lưu ⇒ vuốt đóng hỏi "Bỏ thay đổi?". Lưu xong ghép lại nghĩa cả name mang chữ cũ lẫn chữ mới + toast như trước.
- Màn Sửa từ chế độ danh sách có thêm chỗ cắm `DictEntryEditListMode.sourceEditingKey` (sửa một mục trong cụm nguồn: tiêu đề "Sửa từ", nút "Cập nhật", `replacing` luôn là khoá đó). Các chế độ khác không đổi.
- Chọn một phần của chip ✓ không còn là "thêm mục mới" — thêm mới qua chip "+ X" / "+ Thêm …".

## [1.3.1116] - 2026-11-28

### feat: màn Sửa từ của màn duyệt lọc name local có hàng Phân loại đổi nhóm name, ghép lại nghĩa theo nhóm mới

Plan "Tiền tố hậu tố riêng truyện" mục C11, mockup bản 3 https://claude.ai/artifact/JwiiU3XFYTk7Rz1hAMS7G2 khung M2 (anh Bửu duyệt).

- Hàng **Phân loại** (`LocalNameFilterReviewCategoryRow`) đứng trên hàng Tiền tố trong khối hàng phụ của màn Sửa từ (luồng lọc name local, mọi name trừ họ tộc): nhãn + nút "?", bốn ô Nhân danh / Địa danh / Tổ chức / Thuật ngữ có chấm màu của badge nhóm (`LocalNameFilterCategoryBadge.color(for:)`), bên phải ghi "Lúc lọc: X" khi đã đổi khác nhóm lúc lọc (chỉ nhớ trong lượt duyệt).
- Đổi nhóm ⇒ badge và số trên chip lọc của màn duyệt đổi ngay, hàng Tiền tố / Hậu tố gợi ý loại theo nhóm mới (`affixKind(for:)` nay đọc nhãn badge, chỉ hỏi loại lúc lọc để loại họ tộc). `LocalNameFilterReviewSuffixContext.changeKind` xếp vào cùng hàng đợi với ghép lại sau khi thêm hậu tố: ghi nghĩa máy + loại mới vào gói tạm (`autoMeanings`), ghép lại nghĩa theo nhóm mới chỉ khi nghĩa đang hiện chưa sửa tay (đổi cả cờ "đoán"). Gói cũ không có nghĩa máy ghép ⇒ chỉ đổi nhãn. Không nhớ cho lần lọc sau.
- Phần "lấy mô hình Latin + dựng bộ ghép bằng danh sách hiệu lực của truyện + chạy ngoài main" tách thành `composeMeanings` dùng chung cho ghép lại sau khi thêm hậu tố và đổi phân loại.

## [1.3.1115] - 2026-11-28

### feat: tiền tố hậu tố riêng truyện ở màn Sửa từ có cụm R | C, màn quản lý tiền tố hậu tố của name và chip phạm vi ở danh sách

Giao diện cho kho tiền tố / hậu tố riêng truyện (plan "Tiền tố hậu tố riêng truyện" mục B6, B7, C9; mockup bản 3 https://claude.ai/artifact/JwiiU3XFYTk7Rz1hAMS7G2 khung M2–M6, anh Bửu duyệt). Lõi (kho riêng + API phạm vi) đã có ở commit trước.

- Màn Sửa từ chế độ danh sách có thêm hai chỗ cắm (`DictEntryEditListMode`): `caseRowTrailing` (phần đặt cuối hàng aa…AA) và `interceptSave` (nơi mở nhận việc lưu để hỏi lại trước). Các chế độ khác không đổi.
- Cụm **R | C** `DictEntryEditScopeToggle` (kiểu nút đoạn R | C của panel Dịch Reader, không ghim) ở màn thêm / sửa hậu tố, tiền tố khi mở từ một truyện (`LocalNameFilterSuffixEditorSheet(bookId:)`): thêm mới mặc định R, sửa thì đúng phạm vi của mục; badge còn "Hậu tố" / "Tiền tố". Ghi qua `store.save(...scope:bookId:original:)`: C → R tạo bản riêng (bản chung giữ cho truyện khác), R → C ghi lên chung rồi xoá bản riêng — chung đã có chữ đó ⇒ hộp "Ghi đè hậu tố chung X?" trước khi ghi. "Về bản gốc" / "Nghĩa gốc" chỉ khi đang ở C. Callback lưu đổi thành `SaveRequest` (khoá, nghĩa, loại, vị trí, phạm vi, mục bị thay).
- Hàng Tiền tố / Hậu tố ở màn Sửa từ của màn duyệt đọc danh sách hiệu lực của truyện (riêng rồi chung không trùng chữ, `LocalNameFilterAffixScopedEntry`): chip ✓ mở đúng phạm vi, ● tính trên danh sách hiệu lực, "+ X" / "+ Thêm …" mặc định R. Luật "nằm trong name" dời vào `LocalNameFilterAffixListFlavor.usablePosition` để màn quản lý dùng chung. Không có thao tác nhấn giữ.
- Nút tròn ⚙ (dáng nút Quản lý nghĩa, màu nhấn) cuối dòng "Tiền tố" ⇒ màn **Quản lý tiền tố, hậu tố** (`LocalNameFilterAffixManagerView` + `LocalNameFilterAffixManagerGroupView`): name + âm Hán-Việt, một thẻ bốn nhóm Tiền tố · Riêng truyện / Chung, Hậu tố · Riêng truyện / Chung, chỉ mục nằm trong name (cùng luật chip ✓), nhóm rỗng "Chưa có"; chip chung bị bản riêng che thì mờ + "bị che". Chạm chip ⇒ Sửa từ của mục; ⓧ ⇒ hỏi "Xoá hậu tố X?" (dòng phụ nói phạm vi) rồi xoá; "+ Thêm" ⇒ Thêm từ với cả cụm, R | C theo nhóm. Mỗi thao tác lưu ngay, ghép lại nghĩa các name trong màn duyệt + toast "Đã thêm / Đã lưu / Đã xoá hậu tố X · ghép lại N name". Khối hàng phụ `LocalNameFilterReviewAffixRows` giữ màn quản lý và số `revision` để hai hàng đọc lại sau mỗi lần ghi.
- Màn danh sách Hậu tố / Tiền tố mở từ sheet Lọc name local (`LocalNameFilterSuffixListView(flavor:bookId:)`) có hàng chip phạm vi "Chung N · Riêng truyện N" trên hàng chip loại; Riêng truyện thêm / sửa / xoá trên kho riêng, hàng không ghi "tự thêm"; "Khôi phục mặc định" chỉ cho Chung. Hàng của sheet ghi "1.299 · N riêng" khi truyện có mục riêng.

## [1.3.1114] - 2026-11-28

### feat: màn Sửa từ có hàng Tiền tố, Hậu tố mở vừa khít nội dung thay vì nửa màn

Mockup https://claude.ai/artifact/JwiiU3XFYTk7Rz1hAMS7G2 khung M2, mục C10 (sheet Sửa từ có hai hàng Tiền tố / Hậu tố mở
vừa khít nội dung, tối đa toàn màn; luồng AI và từ điển giữ nửa màn).

- `DictEntryEditSheet` chế độ từ điển có `accessoryRows` (màn duyệt Lọc name local, mọi name trừ họ tộc) ⇒ bộ nấc
  `[.height(vừa khít), .large]` với `presentationDetents(_:selection:)`: mở ở nấc cao đúng từ tiêu đề tới nút Cập nhật +
  hàng tra cứu ngoài, vẫn kéo lên toàn màn được; nội dung dài hơn màn thì hệ thống kẹp ở toàn màn, cuộn như cũ.
- Đo bằng `GeometryReader` + `PreferenceKey` (iOS 17) ở `DictEntryEditSheet+FittedDetent`: sheet mở ở nấc tạm đã biết
  giá trị (420pt) ⇒ số đo vùng cuộn đầu tiên cho phần đầu sheet ngoài vùng cuộn (tính một lần rồi giữ, ngoài 20…140pt ⇒
  56pt); nấc vừa khít = phần đầu + chiều cao tự nhiên của nội dung trong `ScrollView`. Lần khớp đầu lên hoặc xuống, sau
  đó chỉ nâng (chip / token / hàng phụ về muộn), không hạ ⇒ gõ chữ, bàn phím hiện / ẩn không làm sheet giật. Nấc vừa
  khít đổi chỉ dời lựa chọn khi đang ở nấc vừa khít cũ; đã kéo lên `.large` thì giữ.
- Luồng AI, từ điển, Pronouns, chế độ danh sách giữ nguyên bộ nấc cũ (`.medium` + `.large`, danh sách chỉ `.large`).

Chưa biên dịch được tại chỗ (Windows); check_architecture chỉ còn violation cũ JSDom.swift.

## [1.3.1113] - 2026-11-28

### feat: màn duyệt tên riêng có nút ▼ thay chữ Lưu, menu thêm Xuất file các mục đang tích

Mockup https://claude.ai/artifact/JwiiU3XFYTk7Rz1hAMS7G2 khung M1, mục C8 (anh Bửu chốt: nút ▼ thay chữ Lưu, xuất mục
đang tích). Áp cho cả luồng AI và Lọc name local (`ReaderAINameReviewSheet`).

- Góc phải header: icon `arrowtriangle.down.fill` 17pt nửa đậm, khung `HeaderMetrics.iconFrameWidth` ×
  `iconFrameHeight` canh phải (mép icon chạm lề), `ToolbarItem(.topBarTrailing)`, nhãn trợ năng "Lưu hoặc xuất name".
  Menu luôn mở được: "Lưu vào Name riêng" (person.fill) · "Lưu vào VP riêng" (character.book.closed) — giữ y hành vi cũ
  kể cả popup ba cách lưu, mờ khi chưa tích mục nào — · ngăn cách · "Xuất file" (square.and.arrow.up, dòng phụ "N mục
  đang tích"), mờ khi không có dòng nào để xuất.
- Xuất file (`ReaderAINameReviewSheet+Export`): nội dung là **đúng** tập Lưu sẽ ghi — `recordsToSave` mới ở `+Save`
  (mục đang tích, luồng AI bỏ hàng gạch, khoá đã trim, nghĩa `normalizeMeaning`, khoá lặp giữ mục đầu, cùng luật
  `AIHarnessService.saveExtractedEntries`); phép đếm "đã có" của popup Lưu cũng đọc từ đây. Mỗi dòng `chữ Hán=nghĩa`
  UTF-8, file `Name_<tên truyện>_<yyyyMMddHHmmss>.txt` ở thư mục tạm, mở `ShareSheet` (không kính); ghi lỗi ⇒ toast lỗi
  + log ❌; chia sẻ xong toast "Xuất file name thành công!".
- Đặt tên file tách thành `DictionaryExportFileName` (Views/Dictionary) dùng chung với danh sách VP / Name
  (`DictionaryListView.generateExportURL`): tên truyện DB ⇒ tên truyền vào ⇒ `bookId` ⇒ "Chung", luôn dịch qua
  `ChineseTextPipeline.meta` (phồn → giản theo truyện), bỏ ký tự cấm; `exportNameOptions` dời vào đó. Tên file danh sách
  VP / Name không đổi.
- Tên truyện: luồng lọc local tra `Book` theo `bookId` trong `modelContext` (chỉ khi container có `Book` trong schema,
  không thì lùi về `bookId`); luồng AI nhận `exportBookTitle` = tên truyện màn AI đang hiện (màn AI có thể mở bằng
  UIKit, không có `ModelContainer`) nên tên file luồng AI theo tên hiển thị.

Chưa biên dịch được tại chỗ (Windows); check_architecture chỉ còn violation cũ JSDom.swift.
