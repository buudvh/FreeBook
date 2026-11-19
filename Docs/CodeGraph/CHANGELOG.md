# CHANGELOG - Nhật ký Thay đổi CodeGraph Tàng Công Các

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **Tàng Công Các**.

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

## [1.3.986] - 2026-11-19

### feat: Bỏ nút bút chì trên hàng các danh sách TTS và cài đặt — chạm thân hàng là mở màn sửa

Anh Bửu: "các màn hình danh sách ... bỏ nút edit đi mà hãy sửa thành khi click vào hàng mỗi item sẽ hiển thị màn hình edit".

Trước: hàng của 6 màn danh sách có icon bút chì [Sửa] cạnh các icon khác; màn Thay thế ký tự TTS và Lọc rác chỉ mở được sheet sửa qua bút chì (chạm thân hàng không làm gì).
Nay: bỏ bút chì ở cả 6 màn; chạm vào thân hàng (khối chữ, rộng hết phần còn lại của hàng) mở sheet sửa. Các icon còn lại (Chuyển, Tắt/Bật, Xoá) và công tắc của Lọc rác vẫn bấm riêng được — chạm chỉ gắn vào khối chữ, hàng không bọc Button. VoiceOver có thêm thao tác "Sửa" trên hàng (`accessibilityAction(named:)`). Lọc rác đang ở chế độ kéo sắp xếp thì chạm hàng không mở sheet.

Màn đã đụng:
- Phiên âm NghiTTS — `Sources/Views/Settings/TTS/TTSDictionaryEditView.swift` (`wordRow`: chỉ bỏ bút chì, chạm đã có).
- Phiên âm VieNeu — `Sources/Views/Settings/TTS/VieNeuJapaneseDictionaryView.swift` (`row(key:)`; chữ nút "?" bỏ "hoặc icon bút").
- Thay thế ký tự TTS — `Sources/Views/Settings/TTS/TTSReplacementManagerView+Layer.swift` (`ruleRow`: thêm chạm hàng ⇒ `prepareForEdit`, bỏ bút chì ở `ruleActionIcons`).
- Lọc rác — `Sources/Views/Settings/Translation/JunkFilterManagementView.swift` (`ruleRow`: khối chữ rộng hết hàng + chạm mở sheet, bỏ `Spacer` và bút chì, giữ `Toggle`).
- Quy tắc mục lục — `Sources/Views/Settings/Translation/TOCRulesConfigView+Row.swift` (chỉ bỏ bút chì, chạm đã có).
- Công cụ tra cứu — `Sources/Views/Settings/Search/SearchEnginesConfigView.swift` (`engineRow`: chỉ bỏ bút chì, chạm đã có).

Chưa kiểm: không build được (máy Windows), chưa chạy trên máy. `.claude/rules/ui-conventions.md` (mục "Màn danh sách") vẫn ghi cụm icon [Sửa][Chuyển][Tắt/Bật][Xoá] — cần sửa thành "chạm hàng = sửa", session con không sửa file đó.

## [1.3.985] - 2026-11-19

### feat: Bộ lọc NSFW của Kệ đồng bộ công tắc NSFW chung, rời app tắt cả hai

Anh Bửu: "đồng bộ tuỳ chọn nsfw của kệ với những chỗ khác (chỉ nsfw/tất cả = bật)"; khoá màn hình / về màn hình chính thì chọn "Có, tắt cả hai".

- **Trước** (1.3.778): Kệ có bộ lọc riêng ba mức (Không hiển thị NSFW / Tất cả / Chỉ NSFW), độc lập với công tắc NSFW chung (`extFilterIncludeNsfw`) của Khám phá, Bộ sưu tập, Tải, Tìm, Cài đặt… Rời app chỉ Kệ tự về "Không hiển thị"; công tắc chung chỉ tự tắt lúc mở app và khi bấm Home.
- **Nay** (`ShelfNsfwFilterState`):
  - Kệ chọn "Tất cả" / "Chỉ NSFW" ⇒ bật công tắc chung; chọn "Không hiển thị NSFW" ⇒ tắt.
  - Chỗ khác bật công tắc ⇒ Kệ đang "Không hiển thị" chuyển sang "Tất cả"; chỗ khác tắt ⇒ Kệ về "Không hiển thị" (nghe `UserDefaults.didChangeNotification`). "Chỉ NSFW" vẫn chỉ áp cho Kệ.
  - Rời app (vào nền) và bấm Home ⇒ tắt **cả hai** (`resetToHidden` giờ tắt luôn công tắc chung).
  - Trạng thái khởi đầu theo công tắc chung; `MainTabView` tạo singleton lúc hiện để luật vào nền chạy cả khi chưa mở tab Kệ.
  - Log `📚 [ShelfNsfw]` ghi mỗi lần đồng bộ.
- Chú thích `ShelfNsfwFilter`, `RepositoryFilterPolicy.includeNsfwDefaultsKey` cập nhật theo luật mới.
- Kiểm: chỉ đọc code, **không build tại chỗ (Windows), chưa chạy trên máy** — cần thử: bật NSFW ở Khám phá rồi về Kệ, chọn "Chỉ NSFW" ở Kệ rồi sang Khám phá, khoá màn hình lúc đang nghe / xem nội dung 18+.

## [1.3.984] - 2026-11-19

### feat: Tiêu đề trang có nút back nằm hàng 2 sát lề trái, cuộn lên thu vào cạnh nút back

Anh Bửu: "các sheet, màn hình bị hiển thị title giữa do có nút ở góc trái thì bây giờ sửa lại hiển thị ở lề trái dưới các nút đó (nghĩa là sẽ hiển thị hàng thứ 2 của header)" → khi cuộn: "cuộn lên thì tiêu đề về nằm kế nút bên trái và giảm size lại để đảm bảo chỗ hiển thị".

- **Trước**: kiểu `.centered` (mọi `.backPageTitle` — 61 màn — các màn `isPresentedAsSheet ? .leading : .centered` khi được đẩy vào, trang con của sheet kiểu hub) đặt tiêu đề 22pt ở **giữa** thanh (ô `principal`).
- **Nay**: tiêu đề lớn của iOS (`navigationBarTitleDisplayMode(.large)`) ⇒ hàng 2, sát lề trái, dưới nút back / nút phải; cỡ 22pt đậm đặt toàn app ở `NavigationBarAppearance.applyLargeTitleFont` (cả bốn trạng thái thanh). Cuộn lên ⇒ hàng 2 thu lại, tiêu đề nhỏ 17pt nửa đậm hiện ở ô `topBarLeading` ngay cạnh nút back (rộng tối đa 230pt, dài thì cắt đuôi). Ô `principal` luôn rỗng ⇒ không còn tiêu đề giữa ở đâu.
- Mới `PageTitleCollapseProbe` (đầu dò UIKit 0×0 ở nền trang): tìm `UINavigationBar` qua chuỗi responder, theo dõi `frame`/`bounds` của thanh và `contentOffset` của scroll view lớn nhất trong trang; "đã thu" = nhãn tiêu đề lớn (UILabel chữ đúng tiêu đề, cỡ ≥ 20pt) bị ẩn / mờ < 50% / bị thanh cắt quá nửa. Không tìm thấy nhãn ⇒ coi như còn hiện (không bao giờ hiện chồng hai tiêu đề; dò hỏng thì tiêu đề chỉ cuộn đi).
- Kiểu `.leading` (tab gốc, gốc sheet) và `.hidden` không đổi. Cập nhật `ui-conventions.md`.
- Kiểm: chỉ đọc code, **không build tại chỗ (Windows), chưa chạy trên máy** — cần thử: độ cao hàng 2 với chữ 22pt, tiêu đề nhỏ có hiện/ẩn đúng lúc cuộn (List, Form, ScrollView, danh sách có ô tìm luôn hiện), trang con trong sheet kiểu hub (sheet thấp), tiêu đề dài, iOS 18 / 26.

## [1.3.983] - 2026-11-19

### feat: Ô tìm kiếm của các danh sách luôn hiện, cuộn xuống không ẩn

Anh Bửu: "luôn hiển thị ô tìm kiếm ở các danh sách đó dù cuộn xuống".

- `.searchable` của 9 danh sách thêm `placement: .navigationBarDrawer(displayMode: .always)` (trước để mặc định ⇒ iOS giấu ô tìm khi cuộn xuống): VP/Name (cả tab Từ đã xoá) `DictionaryListView`, rule dịch `QuickTranslationRuleListView`, lọc rác `JunkFilterManagementView`, phiên âm NghiTTS `TTSDictionaryEditView`, phiên âm VieNeu `VieNeuJapaneseDictionaryView`, thay thế ký tự TTS `TTSReplacementManagerView`, phiên trò chuyện AI `AIChatAllSessionsManagerView`, xung đột nhập từ điển `DictionaryImportConflictView`. Màn chọn chương quét tên AI vốn đã `.always`.
- Danh sách mới có ô tìm thì dùng cùng `placement` này.
- Kiểm: chỉ đọc code, **không build tại chỗ (Windows), chưa chạy trên máy**.

## [1.3.982] - 2026-11-19

### feat: Popup chọn cách nhập dữ liệu — Thay thế toàn bộ / Gộp / Chỉ thêm key mới, chọn xong mới chọn file

Anh Bửu: "sửa lại nhập luôn có 3 option: thay thế toàn bộ (xoá danh sách cũ và chỉ giữ lại mới), gộp (vế trái trùng thì đè lên, chưa có thì thêm vào), chỉ thêm vào những key chưa có của vế mới — mockup lại màn chọn này thành kiểu popup giữa màn hình, gồm 3 radio cho 3 option, mỗi option có mô tả và cuối cùng là nút nhập file" → duyệt mockup.

- Mới `Sources/Views/Common/DataImportModePopup/`: `DataImportModePopup` (thẻ kính giữa màn: tên + "Chọn cách nhập", ba hàng radio của `DataImportMode` kèm một dòng mô tả, nút đặc `.appFilled` ở cuối) + `.dataImportModePopup(isPresented:title:confirmTitle:confirmSystemImage:modes:initialMode:onConfirm:)`.
  - Trình bày bằng `fullScreenCover` nền trong, mở / đóng không trượt (transaction tắt animation), thẻ hiện mờ dần; lớp tối phủ cả thanh điều hướng, chạm ra ngoài là đóng (không nút Huỷ).
  - `onConfirm(mode)` chạy **sau khi** popup đóng hẳn (`onDismiss`) ⇒ chỗ gọi mở bộ chọn file ngay trong đó được.
  - Mặc định chọn "Gộp"; nút cuối mặc định "Nhập file", chỗ không chọn file (nhập từ truyện khác…) truyền `confirmTitle`.
- `DataImportMode`: tên lựa chọn đổi theo chữ anh — "Thay thế toàn bộ", "Gộp" (= đè key trùng), "Chỉ thêm key mới" — và mô tả một dòng mới. Ba dialog nhập rule cũ đang dùng `actionTitle` thì đổi chữ theo; các màn nhập được nối vào popup ở các commit sau của đợt này.
- Kiểm: chỉ đọc code, **không build tại chỗ (Windows), chưa chạy trên máy**; `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`.

## [1.3.981] - 2026-11-18

### feat: Quản lý nghĩa từ kiểu chip — bốn nhóm trong một thẻ, nút x góc chip để xoá nhanh

Anh Bửu: "mockup lại màn hình quản lý nghĩa từ" → xem bản gọn thì hỏi "còn cách nào gọn hơn không?" → chọn "Làm kiểu A" (chip theo nhóm), rồi thêm: "thêm x trên góc phải bên trên mỗi viên con nhộng để xoá nhanh nghĩa, nếu bị xoá thì thêm nút hoàn tác (dùng icon hết nhé)".

- **Trước**: `List` sáu section — "Từ đang chọn", "Phiên âm", rồi bốn nhóm từ điển; mỗi nghĩa một hàng ô nhập kèm bốn nút icon hẹp 26pt (lên, xuống, chèn ô trống phía trên, xoá); nhóm trống vẫn chiếm hai hàng ("Chưa có định nghĩa nào" + "Thêm nghĩa ở cuối").
- **Nay**: chữ gốc + phiên âm Hán Việt nằm trên một dòng; bốn nhóm (Name / VP × Riêng / Chung) nằm trong **một** thẻ, mỗi nhóm một dòng: nhãn bên trái, các nghĩa là viên con nhộng tràn dòng (`FlowLayout`), chip `+` nét đứt ở cuối. Nhóm trống chỉ còn nhãn + chip `+`.
  - Bấm thân chip ⇒ ô sửa hiện ngay dưới nhóm (tự focus), kèm hai nút icon ← → đổi chỗ; bấm lại chip hoặc phím Xong ⇒ đóng ô sửa.
  - Nút tròn góc trên phải mỗi chip: `xmark` xoá nhanh (xoá mềm, chip gạch ngang), chip đã xoá thì nút đổi thành `arrow.uturn.backward` để hoàn tác; bấm thân chip đã xoá cũng hoàn tác. Cả hai chỉ là icon.
  - Chip đứng đầu nhóm tô màu nhấn (nền mờ 18%, viền 60%): đó là nghĩa được dùng khi dịch (`TranslateUtils.getFirstMeaning`).
  - `+` thêm chip trống ở cuối và mở luôn ô sửa; chip vừa thêm mà bỏ trống thì tự gỡ khi rời nó (bấm x trên chip trống cũng gỡ hẳn, không để lại chip gạch ngang).
  - Chân màn: "Thay đổi được lưu khi đóng" / "Đã sửa N nhóm · lưu khi đóng".
- **Bỏ**: nút "chèn ô trống phía trên" (thêm ở cuối rồi dùng ← → đưa về chỗ cần) ⇒ xoá `ManageDefinitionsDraft.insertEmptyRow` và file `ManageDefinitionRowView.swift`.
- **Không đổi**: cách lưu (ghi đĩa một lần lúc đóng màn, `saveAllChangesToDisk` / `mergedMatches` giữ nguyên), bốn nhóm sửa được và nhãn nguồn, hai chỗ mở màn (panel Dịch của Reader, sheet Sửa từ).
- File: `ManageDefinitionsView.swift` (dựng lại phần giao diện bằng `ScrollView`, thẻ dùng `AppGlassSheetModifier.rowFill`; phiên âm tính một lần lúc mở thay vì mỗi lượt `body`), mới `ManageDefinitionChipView.swift` + `ManageDefinitionGroupView.swift`, `ManageDefinitionsDraft` thêm `removeRow` / `isDiscardableBlank`, `appendEmptyRow` trả `id`. Nút góc nằm **trong** khung layout của chip (chip lùi 6pt) chứ không nhô ra như `ChipCornerBadge`, vì nó bấm được.
- Kiểm: bốn file qua `swiftc -frontend -parse` (chỉ cú pháp); `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. **Không build tại chỗ (Windows), chưa chạy trên máy** — chưa kiểm: chip dài có cắt đuôi ở 240pt không, vùng chạm của nút góc trên chip ngắn, focus ô sửa khi chuyển giữa hai nhóm, bàn phím có che ô sửa của nhóm cuối không.

## [1.3.980] - 2026-11-18

### feat: Tìm trong chương cuộn vô hạn hai đầu — kéo lên tìm chương trước, kéo xuống tìm chương sau

Anh Bửu: "sửa lại tìm trong chương theo ý của tôi đã" — "tìm trong chương hay là load vô hạn 2 đầu, đầu trên sẽ tìm tiếp trang trước, đầu dưới sẽ load trang sau". Hỏi thêm thì chọn: chương chưa tải về máy ⇒ "tải từ nguồn rồi tìm"; mỗi lần kéo tới một đầu ⇒ "đúng 1 chương".

- **Trước**: sheet chỉ tìm trên các chương đang nằm trong RAM của Reader (chương đang đọc + vài chương lân cận), không nạp thêm được.
- **Nay**: mở sheet vẫn tìm ngay trên chương đang đọc + các chương **liền kề** đã dựng trong RAM (không tải gì) và cuộn tới chương đang đọc. Danh sách có hàng ở **hai đầu**: kéo tới đầu trên ⇒ tìm thêm **một** chương liền trước, đầu dưới ⇒ **một** chương liền sau; hàng đó cũng bấm được (chương vừa tìm không có kết quả thì hàng vẫn trên màn ⇒ bấm để tìm tiếp), hiện "Đang tìm <chương>…", lỗi tải thì "Không tải được … · Bấm để thử lại", hết thì "Đầu truyện" / "Hết truyện". Mỗi chương đã tìm có tiêu đề + số kết quả; không có kết quả thì ghi "Không có kết quả trong chương này" để thấy đã tìm tới đâu. Đổi từ khoá chỉ khớp lại các chương đã nạp (ngoài main, chờ 250 ms), không nạp lại.
- **Nạp chương** (`ReaderViewModel.loadChapterForSearch`, file mới `ReaderViewModel+Search.swift`): chương có sẵn trong RAM ⇒ dùng luôn; không thì **cùng đường với Reader** — `ChapterContentRepository.load` (file đã tải, không có thì tải qua tiện ích; tải từ nguồn thì chương được lưu lại và mục lục đánh dấu "đã tải" như lúc đọc) rồi `performChapterTranslationOffMainActor` với đúng cài đặt dịch / phồn → giản / tiêu đề hiện tại ⇒ cùng `ParagraphItem.id`, bấm kết quả nhảy đúng đoạn. **Không** ghi vào cache / cửa sổ trượt của Reader. Để dùng chung, tách `chapterContentRequest(at:forceRefresh:interactive:)` + `noteChapterFetchedFromSource(_:)` khỏi `loadChapterContentFromExtension` và `chapterTitleLayout(bookId:)` (hai cờ `showChapterTitle_` / `removeDuplicatedTitle_`) khỏi `processAndSaveChapter` — hành vi Reader không đổi.
- **Trạng thái** ở `ReaderSearchSession` (`@Observable`, mới): dãy chương đã tìm luôn **liền** `lower...upper`; mỗi đầu một lượt tải tại một thời điểm, hai đầu độc lập; chương nạp xong trong lúc đang khớp lại thì lượt khớp tự khớp thêm. Đóng sheet ⇒ huỷ mọi lượt.
- **Danh sách** đổi từ `List` sang `ScrollView` + `LazyVStack` + `scrollPosition(id:anchor: .top)`: chèn chương lên đầu vẫn giữ nguyên chỗ đang xem (bài học 1.3.822). Hàng hai đầu nạp khi **hiện ra** (`onAppear` trên khung ngoài, danh tính không đổi theo trạng thái) ⇒ không tự nạp liên tục khi hàng còn nằm trên màn — đúng "mỗi lần một chương"; vì vậy không dùng `LoadMoreFooter` (cái đó tự nạp tiếp khi chân còn trên màn).
- Kiểm: các file Swift đã sửa / thêm qua `swiftc -frontend -parse` (chỉ cú pháp); `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. **Không build tại chỗ (Windows), chưa chạy trên máy** — chưa kiểm: vị trí cuộn khi chèn chương lên đầu, hàng đầu trên có tự nạp một chương ngay lúc mở sheet không (khi chương đang đọc ngắn), tốc độ tìm chương phải tải từ nguồn.

## [1.3.979] - 2026-11-18

### fix: CI build lại được — ONNX Runtime chép vào repo, file nhị phân lưu ở repo FreeBook-deps vì repo của Microsoft đã mất

CI của 1.3.978 hỏng ở bước "Resolve and patch Package dependencies", cả lần chạy lại: `xcodebuild -resolvePackageDependencies` không clone được `https://github.com/microsoft/onnxruntime-swift-package-manager.git` (`fatal: could not read Username` — GitHub trả 401 cho repo không tồn tại). Kiểm tra 2026-11-18: cả `microsoft/onnxruntime-swift-package-manager` lẫn `microsoft/onnxruntime` đều trả 404 qua API; có issue công khai báo cùng lúc (onnx/onnx #8842, 2026-11-17). Bước biên dịch chưa chạy tới — code của 1.3.978 chưa được biên dịch.

Anh Bửu: "có thể tải hết file cần thiết về không, tôi sợ repo đó biến mất không có để build tiếp" → chọn "tạo repo mới bỏ lên release repo đó".

- **Mã nguồn gói chép vào repo**: `Vendor/onnxruntime-swift-package-manager/` = gói SPM cục bộ. `objectivec/` chép nguyên văn từ commit `b7fb7f7dea8a2469e6335d95a61b8f36d0dc83b2` ("Update ORT to 1.24.2 (#43)" — commit upstream của người bảo trì ORT, lấy từ bản fork `masicai/onnxruntime-swift-package-manager`), đúng bản 1.24.2 mà các lần CI xanh trước đã resolve; chỉ giữ file target `OnnxRuntimeBindings` cần (gói gốc cũng `exclude` test / tài liệu / training), bỏ product `onnxruntime_extensions` (app không dùng). Kèm `LICENSE` (MIT, Microsoft). `Package.swift` viết lại gọn, ghi nguồn gốc và cách nâng bản.
- **File nhị phân 52 MB** (`pod-archive-onnxruntime-c-1.24.2.zip`) tải từ `download.onnxruntime.ai` của Microsoft, SHA-256 `f7100a99…6e600b54` **trùng** checksum gốc, đưa lên release `onnxruntime-1.24.2` của repo mới **`buudvh/FreeBook-deps`** (public, README ghi nguồn gốc + checksum + "đừng xoá"); đã tải lại ẩn danh qua link release, checksum vẫn khớp. `binaryTarget(url:checksum:)` trỏ tới link đó.
- `project.yml`: `onnxruntime-swift-package-manager` đổi từ gói git sang `path: Vendor/onnxruntime-swift-package-manager`; tên package / product (`onnxruntime`) / target (`OnnxRuntimeBindings`) giữ nguyên ⇒ phần còn lại của `project.yml` và `import OnnxRuntimeBindings` không đổi.
- Kiểm: `Package.swift` qua `swiftc -frontend -parse` (chỉ cú pháp — `swift package dump-package` trên Windows lỗi liên kết của toolchain, không phải lỗi manifest). **Chưa push** (anh Bửu: "fix lỗi nhưng khoan push đã") ⇒ chưa biết CI resolve / biên dịch được không.
- Các package git còn lại (SwiftSoup, ZIPFoundation, espeak-ng-spm, SafariConverterLib) vẫn tải từ repo của bên thứ ba như cũ.

## [1.3.978] - 2026-11-18

### fix: Thay thế từ TTS không phân biệt hoa thường — lúc đọc lẫn chip R/C

Anh Bửu báo chip gợi ý của "Thêm thay thế TTS" sai, rồi tự tìm ra nguyên nhân: "có vẻ do R/C phân biệt hoa thường"; được hỏi sửa tới đâu thì chọn "cả lúc đọc cũng không phân biệt".

- **Trước**: luật chữ khớp token **bằng đúng cả hoa thường** (1.3.940) — rule `sasuke` không thay "Sasuke" đầu câu, và chip R/C của sheet "Thêm thay thế TTS" (lẫn sheet Thêm / Sửa quy tắc) không hiện rule đó khi bôi đen "Sasuke". Chip R/C không bị 1.3.974 đổi — phép lọc `pattern == ` đã có từ trước.
- **Nay**: một khoá khớp duy nhất `TTSReplacementRule.matchKey` (hạ chữ thường, **giữ dấu**: `Hà` vẫn không đụng `Ha` / `Hàn`; chuỗi thay thế giữ nguyên chữ người dùng gõ) dùng cho mọi phép so mẫu:
  - lúc đọc — `TTSReplacementPlan` (luật chữ; luật ký hiệu không có hoa thường);
  - gộp tầng riêng với tầng chung (`mergedRules`: rule riêng — kể cả đang tắt — chặn rule chung cùng mẫu khác hoa thường);
  - `addRule` hai tầng, màn Sửa quy tắc (đè luật trùng), nhập JSON / khôi phục mặc định ở chế độ gộp, khôi phục sao lưu (`BackupDictionaryRestorer`);
  - cảnh báo "trùng mẫu" của `TTSReplacementRuleValidator`, câu mô tả luật chữ, chữ giải thích ở màn Thay thế ký tự TTS;
  - chip R/C (`TTSReplacementSuggestionSection.ruleChips`).
- **Ảnh hưởng tới luật đang có**: luật cho tên riêng giờ thay cả từ thường cùng chữ (rule `Long` thay cả "long") — anh Bửu đã được báo trước khi chọn. Một tầng đang có hai luật chỉ khác hoa thường (`Sasuke`, `sasuke`): lúc đọc luật **đứng trước** thắng, hàng của chúng hiện cảnh báo trùng mẫu; thêm / sửa lần sau sẽ đè nhau như mọi luật trùng. Dữ liệu không tự sửa.
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift` (`TTSReplacementManager.swift` legacy giữ nguyên số dòng). Không build tại chỗ (Windows), chưa chạy trên máy.

## [1.3.977] - 2026-11-17

### feat: Gemini Web chạy được khi chưa đăng nhập Google (chế độ khách)

Anh Bửu: "gemini web cũng có thể hoạt động tốt dù không đăng nhập, làm thêm đi".

- **Hành vi**: profile Gemini Web không còn báo "Chưa đăng nhập Google" khi chat / quét tên riêng / kiểm tra kết nối — chưa đăng nhập thì lượt chạy **chế độ khách**. Đã đăng nhập thì giữ nguyên đường cũ (giao thức `StreamGenerate`, chọn model, lưu lịch sử). Còn cookie Google mà trang vẫn là phiên khách (cookie hết hạn) cũng rẽ sang chế độ khách.
- **Vì sao khách phải điều khiển trang** (thử thật 2026-11-17, Chromium giả lập mobile, chưa đăng nhập, 3 tin): trang khách không có token `SNlM0e`, và sau khi gửi tin **không** gọi `StreamGenerate` — chỉ thấy `batchexecute` cùng `geminiweb-pa.clients6.google.com/v1/processSession` và bước chứng thực `waa-pa…/Waa/Create`. App không dựng lại API đó (là vượt cơ chế chống lạm dụng của Google): app gõ câu hỏi vào ô nhập của trang, bấm gửi, đọc câu trả lời từ DOM — `GeminiWebGuestPageContract`.
- **Dùng lại bộ điều khiển trang của ChatGPT Web**: `ChatGPTWebSessionController` / `ChatGPTWebClient` / `ChatGPTWebTurnQueue` nay nhận một `ChatGPTWebSite` (URL + ba đoạn JS trả cùng khuôn `Snapshot` / `SubmitOutcome`), mỗi trang một WebView ẩn, hàng đợi và client riêng (`.shared` = ChatGPT, `.geminiGuest` = Gemini khách). Hành vi ChatGPT Web không đổi. Lỗi của bộ điều khiển đổi sang `GeminiWebError` ở `GeminiWebClient+Guest` nên luật dừng quét / thông điệp Gemini Web chạy như cũ.
- **Trang khách** (đã thử): ô nhập Quill `rich-textarea .ql-editor` — gán chữ bằng cách dựng thẳng các `<p>` (trang dùng Trusted Types nên không `innerHTML`) + `input`, **không focus** (bài học bàn phím 1.3.976); nút gửi `.send-button` (lớp `submit` / `stop`), bấm bằng `click()` (Enter ở bản mobile chỉ xuống dòng); câu trả lời `model-response` › `message-content .markdown`, xong khi `aria-busy="false"` và `.response-footer.complete`; nạp lại `/app/<id>` bị đưa về `/app` (cuộc chat khách chỉ sống trong trang). Model do trang chọn (lúc thử: Gemini 3.5 Flash-Lite).
- **Khác bản đã đăng nhập**: mỗi lượt là một cuộc chat mới (không nối tiếp được) ⇒ màn AI gửi kèm cửa sổ tin gần nhất kể cả khi bật "Lưu chat vào lịch sử Gemini"; không chọn model; quét tên riêng dùng ~10.000 chữ/lượt và tách chương dài thay cho 40.000. Ba chỗ đó hỏi `GeminiWebGuestMode.isLikelyGuest` (bản ghi nhớ đồng bộ, `GeminiWebClient` cập nhật mỗi lần đọc cookie; màn AI đọc lại khi mở).
- **Bộ đọc chữ câu trả lời dùng chung**: hàm JS `__collectText` tách ra `HiddenWebAnswerTextScript` (ChatGPT ẩn danh, ChatGPT đã đăng nhập, Gemini khách), thêm bỏ phần đầu khối code của Gemini (`.code-block-decoration`).
- **UI**: hàng tài khoản Gemini Web ghi "Chế độ khách (chưa đăng nhập Google)" kèm giải thích; thông điệp `notSignedIn` đổi cho đúng nghĩa mới (Gemini đòi đăng nhập cho việc đang làm). "Load từ API" vẫn cần đăng nhập.
- Kiểm: tám đoạn JS trích từ file Swift qua `node --check`; logic đọc trạng thái + gán chữ + dò nút gửi của bản chính thức chạy trên trang khách thật (nhận ~7.200 ký tự, nút gửi bật, `activeElement` vẫn là `body`); bộ đọc chữ chạy trên ba câu trả lời khách thật (danh sách, khối code, bảng). `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. **Không build tại chỗ (Windows), chưa chạy trên iPhone** — chưa kiểm: UA iPhone có nhận cùng trang khách không, trang hiện gì khi khách hết lượt / bị bắt đăng nhập (chưa gặp ⇒ sẽ ra `timeout` / `protocolChanged` kèm log), giới hạn độ dài câu hỏi của khách. Log: `🤖 [GeminiGuest]`.

## [1.3.976] - 2026-11-17

### fix: ChatGPT Web không còn bật bàn phím mỗi lần WebView ẩn chạy

Anh Bửu báo: "có vẻ mỗi lần mở webview chatgpt web lên đều có bàn phím hiển thị lên".

- **Nguyên nhân**: phần tử trong trang được focus thì WebKit mở phiên nhập cho WKWebView và giành bàn phím của app. Có hai nguồn focus: (1) đoạn JS gán câu hỏi của app tự gọi `focus()` lên ô nhập (cả trang ẩn danh lẫn trang đã đăng nhập); (2) trang đã đăng nhập tự focus vùng soạn thảo của nó. Trang ẩn danh không tự focus (thử thật: sau khi nạp `document.activeElement` là `body`).
- **Sửa**: JS gán chữ không còn gọi `focus()` — thử thật trên cả hai trang: gán `textarea` (setter gốc + `input`) và sự kiện `paste` vào vùng soạn thảo đều nhận chữ khi ô nhập không được focus, trang đã đăng nhập gửi và trả lời bình thường. Thêm `ChatGPTWebPageContract.focusGuardScript`, gắn bằng `WKUserScript` lúc document bắt đầu: `focus()` của trang thành hàm rỗng, phần tử vẫn kịp được focus bằng đường khác thì bị bỏ focus ngay. Lưới an toàn phía UIKit: sau khi gán chữ dự phòng và sau khi gửi, WebView ẩn `endEditing(true)` (chỉ tác động responder bên trong WebView ẩn, ô nhập của app không bị đụng).
- Đường dự phòng `execCommand('insertText')` (chỉ chạy khi sự kiện `paste` không đưa được chữ vào vùng soạn thảo) vẫn cần focus trong tích tắc ⇒ bàn phím có thể nháy ở đúng trường hợp đó; có dòng log riêng.
- `ChatGPTWebPageContract.swift` vượt 400 dòng ⇒ tách phần JavaScript sang `ChatGPTWebPageContract+Scripts.swift` (không đổi nội dung script ngoài các điểm trên).
- Chế độ AI của Google cũng gọi `focus()` trong JS gán chữ của lượt nối tiếp (`GoogleAIModePageContract`) — cùng kiểu lỗi nhưng anh Bửu chưa báo, **chưa sửa**.
- Kiểm: năm đoạn JS trích từ file Swift qua `node --check`; `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. Không build tại chỗ (Windows), **chưa chạy trên iPhone** — chưa xác nhận trên máy là bàn phím hết bật.

## [1.3.975] - 2026-11-17

### fix: Từ điển phiên âm NghiTTS / VieNeu khớp từ có dấu nối - hoặc . theo luật token của thay thế TTS, sheet Thêm từ nhận từ gốc có dấu nối

Anh Bửu: "tôi nhớ rule xác định từ của thêm phiên âm vieneu và nghitts không xác định các từ có nối - hoặc . đúng như thay thế tts đúng không, sửa cho nó áp dụng được".

- **Đúng là lệch, ở ba chỗ** (thay thế từ TTS tách token bằng `TTSReplacementTokenizer` trên chữ gốc của đoạn; từ điển phiên âm thì không):
  - **Lúc nhập** — `AddWordSheet.validateKey` báo "Từ gốc không được chứa dấu câu" cho **mọi** dấu câu, nên gõ `Kamar-Taj`, `S.H.I.E.L.D`, `e-mail` là nút Lưu khoá.
  - **NghiTTS lúc đọc** — `TextPreprocessor.preprocess` đổi mọi `-` không nằm giữa hai chữ số thành dấu cách (`cleanEmojisAndSymbols`) **trước** khi tra từ điển ⇒ mục có `-` không bao giờ khớp, còn mục `Kamar` lại khớp bên trong "Kamar-Taj"; mục có `.` chỉ khớp khi không quá 4 mẩu (bước tra cụm) và không bị bước đọc số làm vỡ.
  - **Cả hai engine lúc đọc** — từ điển tra **sau** `processVietnameseText`, lúc đó số La Mã / số thập phân đã làm vỡ token: `S.H.I.E.L.D` → `S.H.1.E.L.D`, `X-Men` → `10-Men`, `v1.2` → `v một phẩy hai`. (VieNeu vốn tra được cả token có `-` / `.` qua `PreprocessorRegex.token` khi token không bị vỡ: `Kamar-Taj`, `Wi-Fi`, `U.S.A`.)
- **Một bộ tách token cho cả ba nơi** (`TTSPhoneticJoinedWords`, `Services/TTS/Preprocessing/`): từ có nối = token từ của `TTSReplacementTokenizer` có `-` / `.` bên trong (kẹp giữa hai chữ / số, không dấu cách). Lúc đọc, chữ **gốc** của đoạn được cắt quanh các từ nối có trong từ điển: cả token khớp mới áp (mục `Kamar-Taj` thắng mục `Kamar`; `Kamar-Taj-Mahal`, `Kamar- Taj` không khớp mục `Kamar-Taj`), cách đọc đi nguyên văn, phần chữ còn lại đi nguyên đường cũ rồi ghép lại (khoảng trắng ở chỗ nối giữ theo chữ gốc, hai cách đọc không dính liền nhau).
  - **NghiTTS**: `TextPreprocessor.preprocessAroundJoinedWords` (`TextPreprocessor+JoinedWords.swift`), gọi ở đầu `preprocess`; theo công tắc "Sử dụng từ điển" sẵn có; tra khoá hạ chữ thường rồi khoá đã gấp dấu phụ.
  - **VieNeu Nano + Turbo**: `VieNeuJapanesePreprocessor.synthesisText(for:)` (`VieNeuJapanesePreprocessor+JoinedWords.swift`) gói `normalizeVietnameseText` → `applyUsingStoredFlags`; `VieNeuTTSService` và `VieNeuTurboTextFrontend` gọi hàm này thay cho cặp gọi cũ; theo công tắc "Áp dụng từ điển phiên âm VieNeu".
  - **Lúc nhập**: `TTSPhoneticKeyValidator` — `-` / `.` kẹp giữa hai chữ / số được nhận; đứng mép hoặc đứng liền nhau (`Kamar-`, `-Taj`, `a--b`, `U.S.A.`) báo "Dấu - hoặc . chỉ được nằm giữa hai chữ / số, không dấu cách". `AddWordSheet.validateKey` chỉ còn gọi hàm này.
- **Không đổi**: mục không có `-` / `.` (đoạn không có từ nối nào khớp thì không token hoá gì thêm, đi đúng đường cũ; ô Từ gốc không có `-` / `.` báo lỗi y như trước); từ nối **không** có mục riêng vẫn đọc từng phần như cũ ("Sasuke-kun" với mục `Sasuke`, 1.3.960); mục có cách đọc rỗng không được áp (không làm rơi chữ); sheet sửa từ (`EditWordSheet`) chỉ sửa cách đọc nên không có gì để kiểm; từ gốc lấy từ chữ bôi đen ở Reader vẫn không bị kiểm cho tới khi sửa ô.
- **Giới hạn**: gạch ngang dài (`–`, `—`) không phải dấu nối — như thay thế từ TTS; bộ phân loại đọc lai (`VieNeuForeignTextClassifier`) vẫn đếm từng phần của từ nối là tiếng nước ngoài dù từ điển đã có mục cho cả từ; chip gợi ý JP / EN cho từ gốc có dấu nối chưa xét từng phần.
- `.claude/rules/tts.md` ghi luật từ nối của từ điển phiên âm.
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift` (`TextPreprocessor.swift` 1119 / 1121, bốn file mới 26–84 dòng); 8 file Swift đã sửa / thêm qua `swiftc -frontend -parse` (chỉ cú pháp); bộ tách token + cắt + ghép + luật ô Từ gốc mô phỏng bằng bản chép Python trên 9 câu và 13 từ gốc (toolchain Swift trên Windows không biên dịch được). **Không build tại chỗ (Windows), chưa chạy trên máy** — chưa nghe NghiTTS / VieNeu đọc mục có dấu nối, chưa xem câu báo lỗi mới của sheet Thêm từ trên iPhone.

## [1.3.974] - 2026-11-17

### feat: Chip phiên âm Anh / Nhật ở sheet Thêm thay thế TTS, dãy chip gợi ý ở sheet sửa quy tắc thay thế và sửa từ điển phiên âm NghiTTS / VieNeu

Anh Bửu: "thêm phiên âm anh và nhật (nếu có) vào chip gợi ý của thêm thay thế tts, bấm vào thì tự thêm từ vào chuỗi thay thế và bật kích hoạt thay thế"; "thêm chip thay thế vào sửa từ trong từ điển phiên âm của vieneu, nghitts, và danh sách từ thay thế tts".

- **Một section chip dùng chung cho bốn sheet** (`TTSReplacementSuggestionSection`, `Views/Settings/TTS/`): tiêu đề "Gợi ý" + nút "?", chip viền capsule xếp `FlowLayout`, badge góc trên phải, chip vừa bấm viền màu nhấn; không có chip nào thì không vẽ gì.
  - **Reader › Thêm thay thế TTS** (`AddTTSReplacementSheet`): sau chip rule đã có (R / C, rule tắt ⇒ mờ — giữ nguyên luật 2026-09-30) có thêm chip **JP** / **EN** của mẫu đang nhập. Bấm chip phiên âm ⇒ điền chuỗi thay thế **và bật** "Kích hoạt thay thế".
  - **Thay thế ký tự TTS › sheet Thêm / Sửa quy tắc** (`TTSReplacementManagerView`, tầng chung lẫn tầng riêng của truyện): cùng dãy chip — rule trùng mẫu ở cả hai tầng (trừ chính rule đang sửa) + JP / EN; bấm ⇒ điền chuỗi thay thế + đặt công tắc "Kích hoạt quy tắc" (chip phiên âm: bật; chip rule: theo rule đó).
  - **Sửa từ của từ điển phiên âm NghiTTS và VieNeu-TTS** (`EditWordSheet`, tách khỏi `TTSDictionaryEditView.swift` ra file riêng — file legacy đó giảm 596 → 557 dòng): chip **NGI** / **VIE** (cách đọc đang lưu ở hai từ điển, như sheet Thêm từ) + JP / EN; bấm ⇒ điền cách đọc (sheet này không có công tắc). Không có nhấn-giữ-để-xoá; màn VieNeu vẫn có chip EN.
- **Bấm chip là thay nội dung ô, không nối thêm** — như mọi chip sẵn có của app (chip rule R / C, chip gợi ý của sheet Thêm từ).
- **"Nếu có"** (`TTSPhoneticSuggestionBuilder.transliterations(for:)`, mới — không tra từ điển phiên âm): không chip nào khi từ có dấu tiếng Việt (cùng phép thử với `VietnameseTokenGate`, hàm `hasVietnameseDiacritic` bỏ `private`), có số / dấu cách / dấu chấm / chữ Hán, hoặc dưới 2 chữ. Chip JP chỉ hiện khi từ cắt được hết thành âm tiết romaji; kana đổi sang romaji trước và chỉ có chip JP; từ có gạch nối ("Sasuke-kun") xét từng phần; mẫu viết hoa chữ đầu thì chuỗi gợi ý cũng viết hoa chữ đầu ("Sasuke" → "Xa xư kê"). Chip chữ rõ = cách đọc bộ phiên âm sẽ chọn (`ForeignScriptClassifier`), chữ nhạt = cách còn lại. Chip không phụ thuộc công tắc "Phiên âm tiếng Anh" / "Phiên âm tiếng Nhật" của trình đọc (1.3.973) — đây là gợi ý để chọn tay.
- **Nạp ngoài main thread** (`TTSPhoneticSuggestionLoadModifier`, `.phoneticSuggestions(for:mode:into:)` gắn lên `Form`): đường EN gọi `EspeakPhonemizer` (khoá chung với NghiTTS) trong `Task.detached` như `AddWordSheet`; lượt đầu chạy ngay, gõ tiếp thì chờ 0,3 s, `.task(id:)` tự huỷ lượt cũ. Là modifier vì section rỗng không vẽ gì nên không gắn `.task` lên chính nó được.
- `AddWordSheet` (sheet Thêm từ) không đổi. `.claude/rules/tts.md` ghi dãy chip dùng chung.
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift` (3 file mới 56 / 86 / 161 dòng, `TTSReplacementManagerView.swift` 376 / 400); 9 file Swift đã sửa / thêm qua `swiftc -frontend -parse` (chỉ cú pháp). **Không build tại chỗ (Windows), chưa chạy trên máy** — chưa xem dãy chip trên iPhone, chưa nghe thử chuỗi phiên âm do chip điền.

## [1.3.973] - 2026-11-17

### feat: Công tắc Phiên âm tiếng Nhật có ở mọi trình đọc TTS, lưu riêng từng trình đọc

Anh Bửu: "sửa lại nút phiên âm tiếng nhật cho tất cả tts, config lưu riêng mỗi loại tts". Trước đó mỗi trình đọc một kiểu: NghiTTS gộp chung "Phiên âm tiếng Anh/Nhật" (nằm sâu trong Cấu hình tiền xử lý), VieNeu có "Đọc tên Nhật theo âm tiết" (công tắc "Tự động phiên âm tiếng Nhật" đã bỏ ở 1.3.899), còn Siri / Google / tiện ích không có gì.

- **Một công tắc "Phiên âm tiếng Nhật" ở Cài đặt TTS › Quản lý riêng của trình đọc**, hiện với **mọi** trình đọc (`TTSJapaneseTransliterationRow`, `Views/Settings/TTS/`): Siri (thay dòng "không cần cấu hình"), NghiTTS, Google, từng tiện ích TTS; VieNeu qua `VieNeuReaderManagementRows` (thay hàng "Đọc tên Nhật theo âm tiết") nên màn Giọng dự phòng cũng có; mục NghiTTS của màn Giọng dự phòng và "Tiền xử lý text" của Cấu hình NghiTTS có cùng hàng. Tiêu đề mục có nút "?" giải thích công tắc làm gì ở trình đọc đang chọn. Đổi trình đọc ⇒ công tắc hiện đúng giá trị của trình đọc đó.
- **Lưu riêng từng trình đọc** (`TTSJapaneseTransliterationSettings`, khoá `ttsJapaneseTransliterationEnabled.<tool>`: `system`, `nghitts`, `vieneu`, `google`, `packageId` của tiện ích — "mỗi loại TTS" hiểu là **trình đọc**, không phải từng giọng; VieNeu Nano và Turbo chung một khoá như các cờ VieNeu khác). Giữ giá trị đang có: NghiTTS lấy từ `preprocessorTransliterationEnabled`, VieNeu lấy từ `vieneuJapaneseNameSyllablesEnabled`, chép sang khoá mới ở lần đọc đầu (khoá cũ không xoá); Siri / Google / tiện ích **mặc định tắt** — trước giờ không phiên âm, cách đọc không tự đổi.
- **Mỗi đường tổng hợp đọc đúng khoá của mình:**
  - NghiTTS: `PreprocessorRuntimeConfig.japaneseTransliterationEnabled` điều khiển bước kana → romaji và nhánh romaji của `TextPreprocessor.transliterateToken`; công tắc cũ đổi tên thành **"Phiên âm tiếng Anh"** và chỉ còn điều khiển nhánh tiếng Anh (tắt tiếng Nhật thì từ romaji đi theo luật tiếng Anh nếu tiếng Anh bật; tắt tiếng Anh thì chỉ từ romaji được đổi). Khoá đệm phiên âm mang cả hai cờ.
  - VieNeu: `VieNeuJapaneseNameReader.isEnabled` đọc khoá mới ⇒ tiền xử lý Nano / Turbo, bộ phân loại đọc lai và dấu vân tay giọng dự phòng đi theo, không đổi cách đọc.
  - Siri / Google / tiện ích: `TTSJapaneseTextTransliterator` (mới) đổi chữ ở **tầng service** (`SiriTTSService.speak`, `GoogleTTSService.synthesize` + `synthesizeBatch`, `ExtTTSService.synthesizeData` — tra `packageId` theo `localPath`) ⇒ đoạn đang đọc, nạp trước, đệm chương kế, request gộp của Google và "Nghe" đoạn bôi đen cùng một đường; giọng dự phòng nhận chữ gốc và áp cài đặt của chính nó. Cùng luật với nhánh tiếng Nhật của NghiTTS (`ForeignScriptClassifier` sau cổng `VietnameseTokenGate`): "Sakura" → "Xa cư ra", token gạch nối xét từng phần, dãy kana → romaji → âm tiết Việt, chữ Hán giữ nguyên.
- `TTSSettingsSnapshot` thêm `japaneseTransliteration` của trình đọc chính, dấu vân tay giọng dự phòng NghiTTS thêm cờ ⇒ gạt công tắc rồi đóng Cài đặt là dựng lại đoạn, bỏ tiếng đã nạp trước theo cài đặt cũ.
- `.claude/rules/tts.md`, `.claude/rules/tts-vieneu.md` ghi luật mới.
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift` (`TextPreprocessor.swift` 1117 / 1121 dòng, `TTSSettingsView.swift` 327); 15 file Swift đã sửa / thêm qua `swiftc -frontend -parse` (chỉ cú pháp). **Không build tại chỗ (Windows), chưa chạy trên máy** — chưa nghe thử cách Siri / Google / tiện ích đọc chữ đã phiên âm, chưa xem công tắc trên màn thật.

## [1.3.972] - 2026-11-17

### fix: VieNeu Turbo không tự tắt AMX vì app sập chỗ khác, hết lỗi "Chưa nạp model Turbo" khi model vừa bị nhả, xoá dữ liệu và thử giọng trả lại đúng engine

Rà soát phân hệ VieNeu Turbo (code review hai lượt); anh Bửu chọn sửa các mục **đã xác nhận**. Bảy lỗi:

- **Bản vá `capi_abort_file` thay handler `std::terminate` của cả tiến trình rồi `abort()` thẳng.** Sau lần dựng session Turbo đầu tiên, mọi exception chưa bắt của app (NSException của UIKit / SwiftData… không liên quan audio.cpp) bị ghi vào `audiocpp-abort.txt`; lần mở sau `VieNeuTurboCrashGuard.recoverIfNeeded` coi là audio.cpp sập ⇒ tự tắt AMX tới bản build sau (RTF 0,25 → 0,40), và handler cũ (của ggml, rồi libobjc / Foundation — nơi ghi lý do "Terminating app due to uncaught exception" vào `.ips`) không còn được gọi. Nay: dòng của handler mang tiền tố `terminate: `, ghi xong **gọi lại handler đã cài trước** (cài một lần, có chốt chống gọi vòng); `recoverIfNeeded` chỉ tắt AMX khi có dấu "đang thử AMX" hoặc có câu báo của chính ggml — file chỉ có dòng `terminate: ` (và ba dạng chữ của bản vá cũ) thì chỉ ghi `❌` vào log.
- **`release()` chen giữa `prepare` và `synthesize` của runtime ⇒ "Chưa nạp model Turbo".** `VieNeuTurboTTSService.executeInternalSynthesis` gọi `runtime.prepare`, `await` phiên âm rồi mới `runtime.synthesize` — hai block rời trên hàng đợi; một `release()` xếp hàng lúc GGUF đang nạp (đổi sang giọng Nano khác rồi bấm ▶ thử giọng Turbo: lượt nạp sẵn Nano gọi `releaseForNano`; lượt `prepare` đầu của engine đọc lai; xoá dữ liệu Turbo) luôn chạy trước `synthesize`. `VieNeuTurboRuntime.synthesize` nhận thêm `modelURL` / `threads` và tự `prepareLocked` trong cùng block; model + session còn nguyên thì chỉ so vài biến.
- **`freeAll()` đặt lại `codecAMXVerified`** ⇒ dấu canh sập AMX mở lại sau mỗi lần nạp lại model (đổi Nano ↔ Turbo, tạo giọng lúc runtime nguội, xoá dữ liệu), không phải "lượt đầu mỗi lần mở app" như doc; app bị giết trong cửa sổ đó vì lý do khác cũng bị tính là sập do AMX. Bỏ dòng đặt lại.
- **Xoá dữ liệu Turbo không nạp lại tham số trình đọc.** Đang chọn giọng Turbo mà xoá dữ liệu Turbo: model hiệu lực lùi về Nano nhưng `selectedVoice` còn là id giọng Turbo ⇒ hàng giọng hiện "minh_quan_pro · Nano", Nano đọc giọng mặc định thay vì giọng Nano dùng gần nhất, tới khi mở lại app. Hàm của đường tải xong chuyển thành `TTSManager.reapplyVieNeuReaderIfModelChanged(from:reason:)` (`TTSManager+VieNeuVoice`), `deleteTurbo` gọi chung; `stopReaderIfUsing` dừng cả trình đọc đang **đọc lai** (model kia cũng đang được dùng theo đoạn; xoá một giọng Turbo ⇒ xét cả giọng Turbo của cặp); sau khi xoá nhả runtime + bộ phiên âm Turbo lần nữa.
- **`deleteNano` chặn main.** Enum `@MainActor` gọi thẳng `releaseEngineRuntime()` (chờ khoá engine; một chunk Nano đang tổng hợp giữ khoá vài giây, `stop()` không cắt được) ⇒ UI đứng. Nay `await VieNeuTurboTTSService.releaseNanoEngineIfLoaded(reason:)` (chờ trên hàng đợi GCD; thêm tham số `reason` cho dòng log), rồi kiểm lại "đang tải" vì vừa nhường main.
- **Thử giọng lúc trình đọc không phải VieNeu để model nằm lại RAM tới khi tắt app** (Turbo ~200 MB, Nano ~280 MB): `finishSession` chỉ dọn khi `tool == "vieneu"`, mà ngoài `prepare` của VieNeu không ai nhả. Luật gom về `TTSManager.restoreVieNeuEngines(afterUsing:reason:)`: trình đọc là VieNeu ⇒ như cũ (nạp lại engine của trình đọc); không phải ⇒ nhả engine VieNeu, trừ engine đang là giọng dự phòng của trình đọc online. `VieNeuVoiceCopyRunner` (đọc mẫu nhân bản) dùng chung.
- **Engine đọc lai nhớ `preparedBase` cũ.** Rời đọc lai (chọn giọng không cặp) rồi quay lại cùng model chính: `beginPrepare` thấy trùng nên không nhả model phụ, service chính cũng không nhả vì đang đọc lai ⇒ Nano (ORT + Core ML) và Turbo cùng nằm RAM dù máy mát. `prepare` của service Nano / Turbo thường, khi trình đọc không đọc lai, gọi `VieNeuHybridTTSService.readerLeftHybrid()` để quên giá trị đó.

Chưa sửa (mức "có khả năng", chờ anh Bửu quyết): `isReaderUsingTurbo` bỏ sót đọc lai; `sea_g2p.bin` tải về không kiểm dung lượng; `ensureVoice` xoá nhầm mục của lượt tải mới. `.claude/rules/tts-vieneu.md` ghi các điểm mới.

- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`; 10 file Swift đã sửa qua `swiftc -frontend -parse` (chỉ cú pháp); bản vá Python áp thử lên cây nguồn giả có đủ mốc, chạy lại lần hai tự bỏ qua. **Không build tại chỗ (Windows), chưa chạy trên máy**; đoạn C++ của bản vá chưa qua trình biên dịch nào (máy không có thư viện chuẩn C++ đủ mới) — job `audiocpp-ios.yml` sẽ dựng lại framework vì bản vá đổi.

## [1.3.971] - 2026-11-17

### feat: Thêm provider AI ChatGPT Web (không cần key, đăng nhập hay không đều chạy)

Anh Bửu: "thêm provider chế độ AI chatgpt web"; "chatgpt web có thể sử dụng mà không cần đăng nhập, tận dụng cái này để đỡ đăng nhập, hơn nữa tôi phát hiện không đăng nhập sẽ hiển thị ra nhanh hơn"; "tìm xem có hạn chế số câu hỏi hay gì không"; "phục vụ cho cả đăng nhập lẫn không đăng nhập luôn".

- **Provider mới** `apiFormat = "chatgptWeb"` (`AIProviderProfile.defaultChatGPTWeb`, mẫu "ChatGPT Web (không cần key)" trong sheet thêm provider): không key, không chọn model, không temperature. Chưa đăng nhập ChatGPT trong trình duyệt của app ⇒ chạy trang **ẩn danh**; đã đăng nhập ⇒ chạy bằng **tài khoản đó**. Dùng cho chat trong Reader, quét tên riêng (một chương / nhiều chương) và "Kiểm tra kết nối".
- **Cách chạy** (`Sources/Services/AI/ChatGPTWeb/`, 12 file): mở `chatgpt.com/?temporary-chat=true` trong WKWebView ẩn (`ChatGPTWebSessionController`, cùng kho cookie + UA với trình duyệt bypass), gán câu hỏi vào ô nhập, gửi form, đọc DOM theo nhịp (`ChatGPTWebClient+Turn`). Mọi selector + JS của **cả hai kiểu trang** ở `ChatGPTWebPageContract`; hàng đợi tuần tự `ChatGPTWebTurnQueue`; ngân sách prompt 20.000 ký tự `ChatGPTWebPromptBudget`.
- **Thử thật trước khi viết** (2026-11-17):
  - *Trang ẩn danh* (Chromium giả lập mobile, 5 tin): trang server-render riêng (`/unauth-mweb`), ô nhập `textarea[data-mobile-composer-prompt]`, tin `li[data-message-role]` + `data-message-complete`. Tin ngắn xong sau ~2–5 s; prompt 12.166 ký tự chữ Hán gửi được và trả đúng `Tên=Nghĩa`; hỏi tiếp trong cùng trang nhớ ngữ cảnh.
  - *Trang đã đăng nhập* (Chrome máy tính, tài khoản Free, 3 tin chat tạm): app React khác hẳn — ô nhập là vùng soạn thảo `contenteditable`, nút gửi chỉ có khi ô có chữ, mỗi lượt là `[data-talvt-turn-state]` `in_progress` → `complete`, chữ ở `[data-dil-response]`, khối code không phải `<pre>`. Gán chữ bằng sự kiện `paste` tự dựng, gửi bằng `requestSubmit`, hỏi tiếp trong trang đều chạy.
  - Bốn đoạn JS của bản chính thức (đọc trang, gán chữ, gán chữ dự phòng, gửi) được trích từ file Swift, kiểm cú pháp bằng `node --check`; đoạn đọc trang đã chạy nguyên văn trên trang đã đăng nhập thật (đúng trạng thái, khối code, bảng). Trên trang ẩn danh mới chạy bản trước khi gộp (cùng nhánh logic).
- **Ba bẫy thấy khi thử**: (1) trang ẩn danh: nút gửi chỉ bật theo `requestAnimationFrame` — trang không được vẽ thì nút không bao giờ bật ⇒ gửi bằng `form.requestSubmit(nút)`; (2) xuống dòng mềm trong câu trả lời là text node `"\n"` (`white-space: pre-line`) ⇒ bộ đọc chữ không gộp `\n`; (3) trang đã đăng nhập: lượt vừa gửi mang `complete` trong tích tắc khi chưa có phần trợ lý ⇒ chỉ tin `complete` khi lượt đã có vai `assistant`.
- **Chat**: cuộc chat ẩn danh / chat tạm không khôi phục được sau khi nạp lại trang. Nên lượt chat thành công giữ trang 180 s; lượt kế của đúng phiên chat app hỏi tiếp ngay trong trang (chỉ gửi tin mới, đổi chương thì kèm "Cập nhật ngữ cảnh"), không thì mở cuộc chat mới với đủ ngữ cảnh + cửa sổ 6 tin gần nhất. Không nén ngữ cảnh.
- **Đã đăng nhập ⇒ luôn chat tạm**: không lượt nào vào lịch sử ChatGPT của người dùng (quét cả truyện là hàng chục cuộc chat).
- **Quét tên riêng**: mỗi lượt một cuộc chat mới, ~10.000 chữ/lượt (chương dài được tách như Chế độ AI), nghỉ 5 s (giãn theo nhiệt), tạm dừng khi app ở nền.
- **Giới hạn số câu hỏi** (tìm theo yêu cầu) — ẩn danh: (a) mềm — mã của trang có `noAuthSoftRateLimit.triggerMessageCount = 5`, đếm ở `localStorage`; đã thấy thật: sau tin thứ 5 trang mở hộp mời đăng nhập. (b) cứng — máy chủ có cổng `rate_limited` / `force_login` / `forbidden` (kèm `retryAfter`), con số OpenAI không công bố. Đã đăng nhập: hạn mức theo tài khoản, chưa gặp nên chưa biết trang hiện gì. App: gặp cổng ⇒ dừng, báo rõ, `rate_limited` đặt hạn chờ toàn cục; **không** tự đóng hộp mời đăng nhập, **không** xoá cookie / `localStorage` hay đổi danh tính để lách.
- **UI**: `ChatGPTWebInfoRow` (thay ô Base URL / API key): dòng trạng thái tài khoản, nút "Đăng nhập ChatGPT" / "Mở ChatGPT" (mở trong trình duyệt bypass), nút "Đăng xuất" (`ChatGPTWebAccount` — xoá cookie `*.chatgpt.com` / `*.openai.com`, trình duyệt của app cũng mất đăng nhập ChatGPT). Nút "Mở ChatGPT" (`ChatGPTWebOpenButton`) dưới tin lỗi cần người dùng tự xử lý trên trang; `AIWebRecoveryButtons` gộp nút này với "Mở Google để xác minh" (`ReaderAIFullScreenView.swift` giữ 399 dòng). Ô "Định dạng API" (Cấu hình AI, sheet thêm provider) đổi từ thanh phân đoạn sang **menu xổ** vì 5 định dạng không vừa một hàng. `AIProviderProfile.hasFixedWebModel` gom điều kiện ẩn khối model / temperature của Chế độ AI và ChatGPT Web.
- `rules.md`: mục "ChatGPT Web provider invariants (1.3.971)".
- Kiểm: `check_architecture.py` chỉ còn lỗi cũ của `JSDom.swift`. **Không build tại chỗ (Windows), chưa chạy trên máy** — chưa kiểm: UA iPhone có nhận đúng trang ẩn danh mobile không; **trang đã đăng nhập với UA điện thoại** (mới thử Chrome máy tính); `requestSubmit` / sự kiện `paste` tự dựng trong WKWebView iOS; hộp mời đăng nhập có chặn gửi không; chữ / ngưỡng của cổng `rate_limited`; tên cookie phiên (dòng trạng thái ghi "đoán theo cookie" tới khi có lượt thật); banner cookie. Log chẩn đoán: `🤖 [ChatGPTWeb]`, ghi kiểu trang mỗi lượt.

