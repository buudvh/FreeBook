# CHANGELOG - Nhật ký Thay đổi CodeGraph Tàng Công Các

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **Tàng Công Các**.

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

## [1.3.1112] - 2026-11-28

### feat: lọc name local tách tiền tố hậu tố khỏi tên Latin, luật L16 theo hậu tố khi lõi là tên Latin, thêm tiền tố hậu tố riêng truyện

Plan "Tiền tố hậu tố riêng truyện" (anh Bửu duyệt 2026-11-28, mockup https://claude.ai/artifact/JwiiU3XFYTk7Rz1hAMS7G2)
phần A + B4–B5, chép đúng bản tham chiếu `Docs/Plans/local-name-filter-lac/name_meaning.py` (`latin_affixed`) và
`lacpipe.py` (`latin_core`, L16).

- A1 tên kiểu Latin: `LocalNameFilterProperNames.latinAffixed` (file mới `+Latin`) bỏ tiền tố ở đầu (danh sách Tiền tố,
  mọi loại) và / hoặc hậu tố ở cuối (mọi mục danh sách Hậu tố, kể cả Nhân danh, 1–6 chữ), dài nhất trước, ít nhất một
  phía; lõi ≥ 2 chữ, không dấu ngăn, ra tên Latin qua `latinName(of:)` và khác âm Hán-Việt ⇒ "tiền tố + Latin + hậu tố"
  theo vị trí. `LocalNameFilterMeaningBuilder` gọi ngay sau `nameLike` ở cả hàng bộ luật lẫn hàng phía LAC, mọi loại trừ
  họ tộc; tên người vẫn báo danh xưng. 古赫密斯语 ⇒ "cổ Hermes ngữ", 古弗萨克语 ⇒ "cổ Fusak ngữ", bật Latin: 鲁恩语 ⇒
  "Ruen ngữ", 莫里安语 ⇒ "Morian ngữ". `LocalNameFilterProperNames.init` thêm `affixes:` bắt buộc.
- A2 L16 (`LocalNameFilterLACPipeline+Kind`): LAC bảo người + đuôi yếu + hậu tố địa danh / tổ chức, sau L2 / L1: phần
  trước hậu tố (hoặc nó bỏ một tiền tố của danh sách) có ≥ 1 nghĩa từ điển (tách `/` `|` `;`) là chữ Latin khác âm
  Hán-Việt, khoá có chữ phiên âm ⇒ theo hậu tố (`hasLatinCore`), không theo công tắc Latin. 霍伊河 Nhân danh ⇒ Địa danh
  ("Hoắc Y hà", bật Latin "Khoy hà"), 苏尼亚海 ⇒ Địa danh "Sonia hải". `LocalNameFilterLACPipeline` thêm `properNames`.
- A3 `LocalNameFilterMeaningComposer.rulesVersion = 3` ⇒ mọi gói tạm ghép lại một lần (nghĩa đã sửa tay giữ).
- B4 kho riêng truyện `LocalNameFilterBookAffixStore` (`.suffixes` / `.prefixes`, `UserDefaults`
  `localNameFilterBookSuffixes` / `localNameFilterBookPrefixes` = JSON theo `bookId`, Backup tự gói): thêm / sửa / xoá
  cùng luật khoá + nghĩa với danh sách Chung, trùng khoá trong truyện ⇒ lỗi. Đổi nguồn gộp theo khoá (mục truyện cũ
  thắng), xoá truyện / bản cũ sau mốc chốt xoá theo (`BookSourceMigrator`, `BookStorageManager.deleteBookSideData`).
- B5 danh sách hiệu lực = Riêng + Chung, Riêng thắng cùng chữ: `LocalNameFilterAffixListStore.effective(bookId:)`,
  `LocalNameFilterSuffixStore.allSuffixes(bookId:)`, `LocalNameFilterPrefixStore.allPrefixes(bookId:)`; thao tác theo
  phạm vi R | C + chuyển R ↔ C (`+Scope`: `Scope`, `ScopedKey`, `keyError(_:scope:bookId:original:)`,
  `save(...scope:bookId:original:)`, `delete(key:scope:bookId:)`). Sheet Lọc name local, gói tạm tự cập nhật, dấu gói
  tạm, ghép lại ở màn duyệt đổi sang bản theo truyện; `signature` / composer / `DraftRefresher.Inputs` bỏ mặc định
  `prefixes`. Bộ dò `detectionSuffixes` không đổi; giao diện chưa đổi.

## [1.3.1111] - 2026-11-28

### fix: lọc name local ghép nghĩa bằng hậu tố dài nhất cho cả name của bộ luật, tên kiểu Hán luôn bóc tiền tố hậu tố thay vì lấy nghĩa VP cả cụm

Anh Bửu (2026-11-28, ảnh 瑶池仙阁 "Dao Trì Tiên Các" dù đã có hậu tố 仙阁 = tiên các; "tên không phải la tinh thì dùng tiền
tố hậu tố thôi được rồi sao dùng vp nữa"; duyệt cách 2).
- `LocalNameFilterMeaningBuilder`: hàng bộ luật địa danh / tổ chức lấy hậu tố **dài nhất** của danh sách người dùng khi nó
  dài hơn đuôi đã dò (như hàng phía LAC) — trước đó chỉ lấy đuôi đã dò 阁 nên mục VP 仙阁 "Tiên Các" nuốt cả cụm. Hai
  đường dùng chung `suffixed(_:_:)`.
- `LocalNameFilterProperNames.coverAll` (phủ trọn cả từ bằng mục từ điển, 贝克兰德东区 ⇒ "Backlund Đông Khu"): chỉ còn áp
  cho name có phần tên Latin thật — mục nghĩa chữ Latin và khác âm Hán-Việt của khoá (`isRealLatin`, "Tinh La" của 星罗
  không tính). Tên kiểu Hán luôn bóc hậu tố theo danh sách: 昆仑神宫 ⇒ "Côn Luân Thần cung", 北境五州 ⇒ "Bắc Cảnh Ngũ
  châu". Phần tên vẫn tra VP (玄武 Huyền Vũ, 乾坤 Càn Khôn); name có sẵn cả cụm trong Name / VP giữ nghĩa từ điển.
- Dấu gói tạm có số `rulesVersion` = 2 ⇒ mọi gói tạm ghép lại nghĩa một lần (nghĩa người dùng đã sửa vẫn giữ).
- Bản tham chiếu Python `name_meaning.py` sửa trước; đo 11 truyện (danh sách gốc + 仙阁): 9 hàng mới đổi nghĩa (瑶池仙阁 +
  8 hàng chỉ đổi hậu tố về chữ thường), không thêm / mất / đổi loại hàng nào, tên Latin và name đã có không đổi. Phương án
  bỏ hẳn VP cho tên không Latin đo 410 hàng đổi, hỏng tên Nhật / tây và chữ đa âm (Naruto ⇒ Minh Nhân, Tingen ⇒ Đình Căn,
  Đái Hạo ⇒ Đới Hạo) — không làm.
- `translation.md` cập nhật đoạn Nghĩa và Gói tạm tự cập nhật.
Chưa biên dịch được tại chỗ (Windows); check_architecture chỉ còn violation cũ JSDom.swift.

## [1.3.1110] - 2026-11-28

### docs: ghi chú lọc name local theo hậu tố Nhân danh, tiền tố, họ riêng, luật phân loại mới và độ dài name

Cập nhật `.claude/rules/` cho đợt 1.3.1103–1109 (plan `Docs/Plans/2026-11-27-phan-loai-name.md`).
- `translation.md`: "Đuôi" ⇒ "Hậu tố" (1.299 mục, loại Nhân danh thay Pronouns, chip lọc loại); Tiền tố
  (`LocalNameFilterPrefixStore`, chỉ ghép trước tên Latin); Họ riêng (`QuickTranslationSurnameStore.nameFilter`);
  thứ tự phân loại L11 → L1 / L2 → L3 / L4, L6, lý do bỏ `rank_prefix` / `glued_names` / `length_off`; bản tham chiếu
  11 truyện `run11_phanloai.sh` + `cmp_rules_phanloai.py`; hàng Tiền tố / Hậu tố ở màn duyệt; Độ dài name; popup Lưu;
  đầu thẻ dính; dấu gói tạm tính cả tiền tố.
- `ui-conventions.md`: danh sách áp màn Sửa từ; popup ba cách lưu ở chỗ không phải nhập file.
- `storage.md`: các khoá `UserDefaults` / `@AppStorage` của danh sách lọc name.

## [1.3.1109] - 2026-11-28

### feat: sheet lọc name local có danh sách Tiền tố và Họ, thanh kéo hai đầu chọn độ dài name

Plan 2026-11-27-phan-loai-name L10, L13, L15 (anh Bửu: "Thêm chọn min max số từ ở màn lọc name, dạng kéo", "step min max
1 thôi"), mockup https://claude.ai/artifact/9qgrqxGZpkiCQHQdK4vgbx khung 5.

- Mục "Danh sách": Hậu tố · Tiền tố · Họ (`LocalNameFilterSurnameListView`, số = `QuickTranslationSurnameStore.nameFilter`)
  · Không phải name, số mục kiểu Việt (1.299), đọc lại mỗi lần quay về; giải thích "?" viết lại cho bốn danh sách.
- Mục "Tuỳ chọn": hàng "Độ dài name" dưới "Ít nhất N lần" — thanh kéo hai đầu tự dựng `LocalNameFilterLengthRangeSlider`
  (một `DragGesture`, nấc 1 chữ 2…10, đầu phải 10 = "10+" không giới hạn, hai núm trùng nhau được, chọn núm theo hướng
  kéo khi trùng; mỗi núm là phần tử trợ năng riêng có `accessibilityAdjustableAction`; rung nhẹ mỗi nấc), số bên phải
  "2 – 10+ chữ" / "3 – 6 chữ"; nhớ bằng `@AppStorage` `localNameFilterMinLength` / `localNameFilterMaxLength`.
- "Bắt đầu lọc" truyền `prefixes` (danh sách Tiền tố), `minLength`, `maxLength` (10+ ⇒ `nil`) vào
  `LocalNameFilter.Configuration`; dấu nghĩa của gói tạm tính theo đúng danh sách tiền tố của lượt lọc.

Chưa biên dịch được tại chỗ (Windows); check_architecture chỉ còn violation cũ JSDom.swift.

## [1.3.1108] - 2026-11-28

### feat: màn Sửa từ của màn duyệt lọc name local có hàng Tiền tố và Hậu tố cho mọi name, hiện đủ mục nằm trong cụm

Plan 2026-11-27-phan-loai-name mục 7, 10, L10, L11 (anh Bửu: "Ngoài lựa chọn nhanh hãy hiển thị đủ các hậu tố và tiền tố
nằm trong cụm", "sắp xếp theo thứ tự số từ tăng dần"), mockup https://claude.ai/artifact/9qgrqxGZpkiCQHQdK4vgbx khung 2–3.

- `LocalNameFilterSuffixQuickRow(flavor:)` dùng cho hai hàng "Tiền tố" (trên) và "Hậu tố" (dưới), hiện cho mọi loại name
  kể cả tên người (mục mới mặc định Nhân danh); họ tộc (萧家) vẫn không có.
- Chip ✓ cho mọi mục có sẵn nằm trong cụm, dài 1–6 chữ: hậu tố ở cuối hoặc giữa cụm (东城区血刀帮 ⇒ ✓ 区, ✓ 帮), tiền tố ở
  đầu hoặc giữa cụm; chạm ⇒ sửa mục đó. Dấu ● trên mục đang ghép nghĩa: hậu tố dài nhất ở cuối / tiền tố dài nhất ở đầu,
  cùng nhóm với name như bộ ghép (Nhân danh ⇄ tên người). Chip "+" cho đoạn cuối / đầu 1–3 chữ chưa có; "+ Thêm hậu tố /
  tiền tố" (mở cả cụm) luôn cuối hàng; mọi chip xếp theo số chữ tăng dần (陈太上长老: 老 · 长老 · + 上长老 · ● 太上长老).
- `LocalNameFilterReviewSuffixContext`: `affixKind(for:)` thay `suffixKind` (tên người ⇒ Nhân danh);
  `enqueueRecompose(affixes:flavor:)` ghép lại name kết thúc bằng hậu tố / mở đầu bằng tiền tố vừa lưu, kể cả tên người,
  truyền nghĩa máy ghép lần trước (giữ danh xưng 1 chữ "Lâm ca") và danh sách tiền tố hiện tại.
- Toast "Đã thêm hậu tố / tiền tố X · ghép lại N name".

Chưa biên dịch được tại chỗ (Windows); check_architecture chỉ còn violation cũ JSDom.swift.

## [1.3.1107] - 2026-11-28

### feat: lọc name local đổi Đuôi thành Hậu tố, danh sách hậu tố có chip lọc loại và loại Nhân danh, màn Tiền tố dùng chung màn danh sách

Plan 2026-11-27-phan-loai-name mục 6, 11, L10, L11 (anh Bửu: "Đuôi bây giờ gọi hậu tố đi cho đối xứng tiền tố", "Thêm
tiền tố phải đầy đủ như hậu tố"), mockup https://claude.ai/artifact/9qgrqxGZpkiCQHQdK4vgbx khung 4, 6, 7.

- Mới `LocalNameFilterAffixListFlavor` (`.suffix` / `.prefix`): mọi chỗ khác nhau giữa danh sách "Hậu tố" và "Tiền tố" —
  store (`LocalNameFilterSuffixStore` / `LocalNameFilterPrefixStore`), danh từ trên màn, badge "Hậu tố · chung" /
  "Tiền tố · chung", mặc định mục mới (hậu tố: Địa danh, sau tên; tiền tố: Nhân danh, trước tên), luật "nằm cuối / đầu
  name" khi thêm từ một name, mẫu dòng "Ví dụ", lời giải thích "?". Tên type / file giữ chữ Suffix.
- `LocalNameFilterSuffixListView(flavor:)` dùng cho cả hai danh sách (tiêu đề "Hậu tố" / "Tiền tố"); thanh tab đổi thành
  hàng chip lọc theo loại kèm số (`LocalNameFilterAffixKindFilterBar`: Tất cả 1.299 · Địa danh · Tổ chức · Thuật ngữ ·
  Nhân danh, kiểu chip `ExtensionKindFilterBar`, nền chip thường mờ hợp sheet kính, số kiểu Việt); chỉ hiện loại có mục
  (danh sách tiền tố gốc chỉ có Nhân danh). Thêm mới lấy loại của chip đang chọn.
- `LocalNameFilterSuffixEditorSheet(flavor:)`: màn Sửa từ đủ như hậu tố cho tiền tố (hai cặp ‹ ›, token, ô nghĩa, chip
  nghĩa gợi ý, aa…AA, Loại 4 + Nghĩa đứng + Ví dụ, tra cứu); loại thứ tư Nhân danh (ví dụ 陈 + 长老 → Trần trưởng lão),
  tiền tố ví dụ 老尼尔 → lão Neil; thêm từ một name ⇒ "Thêm" mờ + dòng nhắc khi phần chọn không nằm cuối (hậu tố) / đầu
  (tiền tố) name, chọn cả cụm hoặc dài quá 6 chữ. Sửa lỗi biên dịch: `switch` trên `SuffixKind` thiếu `.person`.
- Mọi chữ "Đuôi" trên màn đổi thành "Hậu tố" (tiêu đề, số mục, ô trống, toast, trợ năng, menu …, hộp khôi phục).

Chưa biên dịch được tại chỗ (Windows); check_architecture chỉ còn violation cũ JSDom.swift.

## [1.3.1106] - 2026-11-27

### feat: bấm Lưu ở màn duyệt name hiện popup ba cách lưu như nhập file, cả luồng AI và lọc name local

Plan 2026-11-27-phan-loai-name mục L16 (anh Bửu: "Bấm lưu sẽ hiển thị màn popup vào hoạt động giống nhập name/vp từ
file. Tất nhiên chỉ có name mới thì nhập thẳng như hiện tại. Làm cho cả AI nhé"), mockup
https://claude.ai/artifact/9qgrqxGZpkiCQHQdK4vgbx khung "Bấm Lưu → chọn cách nhập".

- ReaderAINameReviewSheet (+Save mới): bỏ hộp confirmationDialog "Gộp / Thay thế hoàn toàn". Bấm "Lưu vào Name riêng /
  VP riêng" ⇒ đọc file đích của truyện ngoài main; có name đang chọn đã có trong đó ⇒ popup DataImportModePopup đủ ba
  chế độ (Thay thế toàn bộ / Gộp — chọn sẵn / Chỉ thêm key mới), tiêu đề "Lưu vào Name riêng" / "Lưu vào VP riêng",
  dòng dưới "N name mới · M đã có trong Name riêng" (icon người / sách, không phải icon file), nút "Lưu". Toàn name mới
  ⇒ lưu thẳng bằng Gộp như trước.
- "Đã có" tính theo file Names.txt / VietPhrase.txt riêng của truyện (đích thật của ba chế độ), không theo cờ
  hasInBookNames / hasInBookVP (hai cờ đó gồm cả Name / VP Chung và từ điển gốc). Name chỉ có ở từ điển chung giờ lưu
  thẳng thay vì hỏi — kết quả y như chọn Gộp.
- Lời giải thích ba chế độ theo ngữ cảnh lưu: "Xoá Name riêng cũ của truyện, chỉ giữ các name đang chọn." (VP thì "VP
  riêng"), "Name đã có thì lấy nghĩa mới đè lên; chưa có thì thêm vào.", "Chỉ thêm name chưa có; name đã có giữ nguyên
  nghĩa cũ.". DataImportModePopup / .dataImportModePopup nhận thêm messageSystemImage + explanations (tham số tuỳ chọn,
  mặc định giữ icon file và lời cũ — các chỗ nhập file không đổi).
- Đường lưu nhận DataImportMode thay cho isMerge: onSave của sheet, ReaderAIFullScreenView.saveNamesToDictionary,
  LocalNameFilterSheet.save, AIHarnessService.saveExtractedEntries. Service ghi qua TranslationDictionaryWriter.importRecords
  mới (tách từ importEntries, cùng luật ba chế độ với nhập file); nghĩa chuẩn hoá trước, khoá lặp giữ mục đầu.
- saveExtractedEntries trả ExtractedEntriesSaveResult? (nil = không có mục hợp lệ / ghi lỗi). Toast dùng chung
  ReaderAINameReviewSheet.savedToast: "Đã lưu N mục vào … của truyện" như cũ; Chỉ thêm key mới thêm " · giữ nguyên M mục
  đã có"; mọi name đã có ⇒ "Không có mục mới …" (thông báo, không phải lỗi — lọc name local vẫn xoá gói tạm). Tóm tắt
  trong tin AI ở chế độ Chỉ thêm key mới không khẳng định đã lưu đủ N tên.

Chưa biên dịch được tại chỗ (Windows); check_architecture chỉ còn violation cũ JSDom.swift.

## [1.3.1105] - 2026-11-27

### feat: màn duyệt name giữ đầu thẻ, ô tìm và chip loại dính trên cùng khi cuộn

Plan 2026-11-27-phan-loai-name mục L14 (anh Bửu: "các chip và search hiển thị kiểu sticky để scroll xuống vẫn thấy"),
mockup https://claude.ai/artifact/9qgrqxGZpkiCQHQdK4vgbx khung "Màn duyệt — cuộn xuống".

- ReaderAINameReviewCardView: cả thẻ thành một LazyVStack(pinnedViews: [.sectionHeaders]) với một Section; đầu thẻ
  (Tên riêng (N), menu sắp xếp, Chọn hết / Bỏ chọn) + ô tìm + hàng chip loại là tiêu đề section (stickyHeader), cuộn
  xuống vẫn nằm trên cùng vùng cuộn của sheet. Luồng AI không có chip ⇒ dính đầu thẻ + ô tìm.
- Tiêu đề tô nền đặc bằng nền thẻ (cardBackground, tô sau đệm nên phủ cả dải 12 pt phía trên): hàng cuộn qua bên dưới
  không lộ chữ. Lề trên của thẻ dời vào tiêu đề; không đổ bóng lúc dính (đo vị trí cần onGeometryChange — iOS 18).
- Hành vi lọc / chọn giữ nguyên: ô tìm + chip chỉ ẩn hàng, Chọn hết / Bỏ chọn theo mục đang hiện, Lưu lưu mọi mục đang
  chọn; sheet giữ scrollDismissesKeyboard. Thẻ phải là con trực tiếp của ScrollView của ReaderAINameReviewSheet.

Chưa biên dịch được tại chỗ (Windows); check_architecture chỉ còn violation cũ JSDom.swift.

## [1.3.1104] - 2026-11-27

### feat: lọc name local có danh sách họ riêng, thêm họ 洛 và 玉, chép một lần họ đã sửa ở danh sách họ của rule dịch nhanh

- Danh sách họ riêng của Lọc name local (L13, plan 2026-11-27-phan-loai-name, anh Bửu: "Màn quản lý họ riêng cho lọc luôn"): bộ lọc **chỉ** đọc danh sách mới (`LocalNameFilterDictionaries.capture` ⇒ `QuickTranslationSurnameStore.nameFilter.lookupTable()`, đổi đúng một dòng); token `<ho>` của rule dịch nhanh giữ Danh sách họ cũ ⇒ hai danh sách độc lập, sửa bên nào không đổi bên kia.
- Dùng lại store, không chép code: `QuickTranslationSurnameStore` nhận cấu hình `QuickTranslationSurnameStoreConfiguration` (tên file gốc, khoá `UserDefaults` lớp riêng, nhãn log, có đi vào bộ dịch không, chép một lần từ đâu). Bản gốc thành thuộc tính của từng bản (trước là `static let` dùng chung). `shared` = cấu hình `.quickTranslation` (`ChineseSurnames.txt`, `quickTranslateSurnameOverrides`, ghi vẫn dọn cache dịch + báo rule đổi) — hành vi như cũ. `nameFilter` = `NameFilterSurnames.txt` + khoá `localNameFilterSurnameOverrides` (chữ thường ⇒ `BackupSettingsArchiver` tự gói); ghi **không** dọn cache dịch / không báo rule đổi (danh sách không vào bộ dịch, như `LocalNameFilterSuffixStore`); có hiệu lực từ lần "Bắt đầu lọc" sau.
- File gốc mới `Sources/Resources/Translation/NameFilterSurnames.txt` = bản sao `ChineseSurnames.txt` (683 khoá) + `洛=Lạc`, `玉=Ngọc` cuối mục "Họ đơn bổ sung" ⇒ 685 khoá (585 đơn, 100 kép); chú thích đầu file ghi đúng vai trò. 洛 / 玉 không thuộc tập hư từ bộ lọc tự bỏ.
- Chép một lần (anh chọn "chép họ đã sửa"): lần đầu bản `nameFilter` được tạo (mở màn Họ hoặc lượt lọc đầu), nếu cờ `localNameFilterSurnameSeeded` chưa có ⇒ đặt cờ (cả khi không có gì để chép — "Khôi phục mặc định" sau này không làm chép lại); khoá lớp riêng của bộ lọc chưa có và lớp riêng của `<ho>` có ⇒ chép sang, áp lại lên bản gốc mới (`QuickTranslationSurnameOverrides.rebased(onto:)`: họ tự thêm trùng âm với bản gốc mới như 洛=Lạc không còn tính là phần sửa). Đặt trong `init` của store thay cho bootstrap lúc mở app: `static let` bảo đảm chạy một lần, an toàn luồng, trước mọi lượt đọc (kể cả từ task nền của bộ lọc), không đụng `FreeBookApp` / `MainTabView`. Cờ chữ thường ⇒ Backup gói cùng lớp riêng. Log `📋 [NameFilterSurname]`.
- Màn quản lý: `QuickTranslationSurnameListView` nhận `Context` (store, tiêu đề, tên file xuất, dòng "?", chữ khi trống; mặc định `.quickTranslation` ⇒ hai chỗ mở cũ không đổi); `QuickTranslationSurnameEditorSheet` nhận `store` (trùng khoá xét đúng danh sách đang sửa). View mới `LocalNameFilterSurnameListView()` (`Views/Reader/NameFilter/Lists/`, tiêu đề "Họ", xuất `NameFilterSurnames.txt`, đủ Sửa từ / nhập file 3 cách / xuất / khôi phục mặc định / tắt / xoá) để session giao diện nối hàng "Họ" vào sheet Lọc name local — sheet chưa có hàng này.
- `check_architecture.py` chỉ còn violation cũ `JSDom.swift`. Chưa biên dịch được tại chỗ (Windows); chưa thử trên máy.

## [1.3.1103] - 2026-11-27

### feat: lọc name local sửa phân loại, hậu tố Nhân danh thay Pronouns, tiền tố cho tên Latin, lọc độ dài name

Phần lõi của plan Docs/Plans/2026-11-27-phan-loai-name.md (anh Bửu duyệt): L1–L6, L7 / L10 (engine + store), L9, L11,
L12 (dữ liệu), L15 (engine). Giao diện (Views) để session sau. Bản tham chiếu Python
Docs/Plans/local-name-filter-lac/lacpipe.py + name_meaning.py sửa trước (bản cũ *_before_phanloai.py), chạy 11 truyện.

Phân loại phía LAC (LocalNameFilterLACPipeline+Kind, file mới):
- L11: hậu tố Nhân danh 2–6 chữ của bản gốc vào bộ dò phía LAC ⇒ name có hậu tố đó là Nhân danh (天元圣女 →
  "Thiên Nguyên thánh nữ"). Luật (e) và bộ luật không dùng hậu tố Nhân danh.
- L1 / L2: LAC bảo người + chữ cuối là đuôi yếu phía LAC (bộ cũ + 卫 泽) ⇒ theo hậu tố khi nhãn thường nhiều hơn nhãn
  thực thể (không mở đầu bằng họ, không danh xưng) hoặc ≥ 3 chữ không mở đầu bằng họ (玄剑峰, 执事堂, 魔渊); 刘云峰,
  楚渊, 王精卫 vẫn là người.
- L3: chữ cuối là loài vật / yêu ma ⇒ Thuật ngữ (蜃龙, 啸月银狼), trừ mở đầu bằng họ / 阿 / 小 / có danh xưng.
- L4: nhãn thường ≥ 2 lần nhãn thực thể, không đuôi ⇒ Thuật ngữ (天君, 虚空乱流), trừ họ / danh xưng / 小 阿 老 đầu /
  儿 子 cuối.
- Bộ gắn nhãn đếm nhãn thường cho mọi từ ≥ 2 chữ có chữ Hán (trước chỉ từ ≥ 3 chữ có chữ cuối là đuôi); bỏ
  suffixLastScalars.
Lọc:
- L5 rank_prefix: số + 阶 / 级 / 品 ở đầu ⇒ bỏ, cả name đã có (九阶) và hàng bộ luật ở bước hợp.
- L9 glued_names: name chưa có = hai hàng Nhân danh khác của danh sách (mỗi phần ≥ 2 chữ) ⇒ bỏ (姬晴苟义).
- L15 length_off: Configuration.minLength (mặc định 2) / maxLength (nil = không giới hạn), đếm code point, không tính
  dấu ·, lọc ở đầu ra cả hai đường.
Bỏ Pronouns: LocalNameFilterDictionaries thôi chụp Pronouns; danh xưng của bộ luật (pronouns / titles) dựng từ hậu tố
Nhân danh của danh sách người dùng (cùng bộ lọc Config); glued_fragment giữ phần thừa là hậu tố ≥ 2 chữ mọi loại
(东阳酒店, 贝克兰德大学 nay được giữ); nghĩa tên người lấy hậu tố Nhân danh dài nhất (LocalNameFilterSetup.personTitle,
陈太上长老 ⇒ 太上长老), 1 chữ vẫn chỉ chữ thân tộc sau ≥ 3 tên. Bỏ hasPronouns, log "chưa nạp Pronouns".
Tiền tố (L7 / L10): LocalNameFilterPrefixStore mới (NameFilterPrefixes.txt: 老=lão, 小=tiểu, khoá
localNameFilterPrefixOverrides), dùng chung bộ máy với danh sách hậu tố qua lớp cha LocalNameFilterAffixListStore (lời
báo theo danh từ "Hậu tố" / "Tiền tố"). LocalNameFilterProperNames: mảnh mở đầu bằng tiền tố cùng nhóm loại, phần sau
ra tên Latin ⇒ "lão Kolle", "lão Wood", "tiểu Etter" (bật Latin); nghĩa cả mảnh "lão Neil" trong từ điển ⇒ nhận; 小鱼
老张 giữ Hán-Việt. Configuration.prefixes (mặc định rỗng — màn hình phải truyền allPrefixes()).
Gói tạm: signature tính cả tiền tố, canRecompose thêm tên người (danh xưng 1 chữ chỉ giữ khi nghĩa máy trước đã dùng),
Inputs.prefixes mặc định = danh sách hiện tại.
Dữ liệu: NameFilterSuffixes.txt thêm 渡 泽 (địa danh), 酒店 大学 司 卫 (tổ chức), 1.190 dòng Nhân danh từ
DuoiNhanDanh.de-xuat.txt; SuffixKind.person ("Nhân danh").

Đo 11 truyện (so với lượt Pronouns của anh): L1 13, L2 4, L5 13 khớp plan; L3 40 (二阶虎妖 nay bị L5 bỏ trước); L4 52
(镇魔司 → L6, 无量天君 → L11, 九阶 → L5, 金仙 mở đầu bằng họ); L6 đúng 6 hàng + bộ luật thêm 7 tổ chức (城卫司 巡检司…);
L9 thêm 唐三海神; L11 lật 26 hàng sang Nhân danh, có hàng nghi sai (新晋真传, 绝顶天骄, 魂斗罗…) — chi tiết ở ghi chú
bàn giao. Chưa biên dịch (Windows); Views còn một switch thiếu case .person (LocalNameFilterSuffixEditorSheet).

## [1.3.1102] - 2026-11-27

### fix: lọc name local không bật lại nhãn đoán, gói tạm chỉ ghép lại nghĩa khi danh sách đuôi đổi, lưu hai đuôi liền nhau không đè nhau

Gộp xong đợt "nghĩa tên tây huyễn" (1.3.1095–1101), rà soát chéo bằng hai agent (phần bộ lọc; màn duyệt + màn Sửa từ dùng chung): không thấy lỗi biên dịch, luồng AI và các chỗ dùng khác của màn Sửa từ giữ nguyên hành vi; sửa các lỗi tìm được.

- **Nhãn "đoán" không bật lại**: xác nhận nghĩa ở màn Sửa từ (bấm Cập nhật, nghĩa không đổi) bỏ cờ, nhưng lần ghép lại sau so cả cờ nên gắn lại nhãn và đếm dư vào toast. Nay màn duyệt (`LocalNameFilterReviewSuffixContext.recompose`) và gói tạm (`LocalNameFilterDraftRefresher`) chỉ đổi khi nghĩa đổi thật.
- **Gói tạm chỉ ghép lại khi có gì đổi**: gói nhớ dấu danh sách đuôi + công tắc Latin của lần ghép gần nhất (`LocalNameFilterDraft.meaningSignature`, `LocalNameFilterMeaningComposer.signature`); trùng dấu ⇒ bỏ qua. Trước đây mỗi lần trang đầu hiện ra, hàng bộ luật địa danh / tổ chức (lúc lọc lấy đúng đuôi đã dò) có thể tự đổi nghĩa theo đường ghép "đuôi dài nhất" dù không ai đổi gì; nay cũng ít khi giữ khoá kho gói lâu.
- **Lưu hai đuôi liền nhau** (nhất là lúc mô hình Latin đang tải lần đầu): các lượt ghép lại ở màn duyệt chạy lần lượt (`enqueueRecompose`), lượt sau đọc danh sách đã áp lượt trước; chỉ gộp khoá vừa đổi vào `autoMeanings`.
- **Đổi chữ của đuôi có sẵn** (chip ✓, 街 ⇒ 兰街): ghép lại cả name mang khoá cũ (`onSaved` báo thêm khoá bị thay).
- Họ tộc (萧家) không có hàng "Đuôi" (đuôi không bao giờ đổi nghĩa họ tộc). Lượt ghép lại xong muộn không ghi vào gói khác đang mở (gắn `draftId`). Thu một đuôi có sẵn thành đuôi mới ⇒ toast "Đã thêm".
- Tải mô hình Latin dùng phiên riêng có hạn tổng 30 s (`timeoutIntervalForResource`) — mạng nhỏ giọt không còn treo ở "Nạp model…".
- Comment: khoá đuôi 1–6 chữ (`LocalNameFilter.Suffix.key`), lúc tải mô hình Latin. Tài liệu `.claude/rules/translation.md` / `storage.md` / `books-sources.md` cập nhật cho cả đợt.
- Ghi nhận, chưa sửa (nhẹ): huỷ lúc đang tải mô hình Latin lần đầu không cắt ngay (cửa nạp là `Task.detached`); dòng "Ví dụ" khi sửa đuôi có sẵn qua chip ✓ dùng mẫu chung.
- `check_architecture.py` chỉ còn violation cũ `JSDom.swift`. Chưa biên dịch được tại chỗ (Windows); chưa thử trên máy.

## [1.3.1101] - 2026-11-27

### feat: thêm đuôi ngay từ màn sửa từ của màn duyệt lọc name local, đuôi dài 1 đến 6 chữ, ghép lại nghĩa ngay

- Đuôi dài 1–6 chữ (anh Bửu: "chọn đuôi thoải mái hơn"): luật khoá `LocalNameFilterSuffixListParser` nới từ 1–2 lên 1–6 chữ Hán cho danh sách người dùng (cả màn danh sách đuôi). Bộ dò cố định (file gốc, cách A) vẫn chỉ dùng đuôi 1–2 chữ. Ghép nghĩa lấy đuôi **dài nhất** khớp cuối name, phần tên riêng còn ≥ 1 chữ (安保公司 thắng 公司) — `LocalNameFilterSetup.meaningSuffix(of:)`, Python `suffix_of`. 10 truyện với danh sách mặc định ra y như trước (tắt và bật Latin).
- Màn Sửa từ mở từ màn duyệt (chỉ luồng Lọc name local, chỉ name không phải tên người) có hàng phụ **"Đuôi"** dưới aa…AA, nút "?" (`LocalNameFilterSuffixQuickRow`, plan 2026-11-27-nghia-ten-tay-huyen mục 7, mockup v4): cuộn ngang, đầu hàng là chip chọn nhanh = đoạn cuối 1, 2, 3 chữ của name (chừa ≥ 1 chữ trước, bỏ đoạn có chữ không phải Hán) `+ 街` `+ 兰街` `+ 特兰街`; đoạn đã là đuôi ⇒ chip "✓ 街 · phố · trước" chạm để sửa; cuối hàng nút "+ Thêm đuôi".
- Chip "+" / "+ Thêm đuôi" ⇒ `LocalNameFilterSuffixEditorSheet` chế độ thêm từ name (`Source`): mở với đúng đoạn đó hoặc **nguyên cụm** name, thu / nới bằng ‹ › của hàng chữ gốc, khoá lưu = phần đang chọn (luôn thêm mới); ô nghĩa = phiên âm viết thường của phần đang chọn, đã gõ thì giữ; Loại = loại của name, "Sau tên"; dòng "Ví dụ" dùng chính name; "Thêm" mờ + dòng nhắc khi chọn cả cụm ("Chừa ít nhất 1 chữ trước đuôi."), phần chọn không nằm cuối name, hoặc dài quá 6 chữ.
- Lưu đuôi (thêm hoặc sửa) ⇒ ghi qua `LocalNameFilterSuffixStore` như cũ ⇒ ghép lại nghĩa ngay các name trong màn duyệt đang mở: không phải người / họ tộc, kết thúc bằng đuôi đó, nghĩa vẫn do máy ghép (`autoMeanings`) — bằng đúng bộ ghép nghĩa của bộ lọc với danh sách đuôi hiện tại + công tắc Latin (`LocalNameFilterReviewSuffixContext`); nghĩa tự sửa giữ nguyên; ô nghĩa của màn Sửa từ theo nếu chưa gõ khác; gói tạm mang nghĩa máy ghép mới; toast "Đã thêm đuôi 街 · ghép lại N name".
- Màn Sửa từ dùng chung (`DictEntryEditSheet`) thêm móc mặc định không đổi hành vi chỗ khác: `initialSelection`, `accessoryRows` (chế độ từ điển), `followsOriginalValue`; `DictEntryEditListMode.addsFromSource` + `suggestedMeaning`. `LocalNameFilterSuffixStore.suggestedMeaning(for:)` = phiên âm viết thường.
- Chưa biên dịch (máy Windows), chưa thử trên máy.

## [1.3.1100] - 2026-11-27

### fix: lọc name local siết luật ghép mảnh từ điển, tập chữ phiên âm đóng trong app dùng ở mọi chế độ

- Mọi mục từ điển dùng làm **một phần** của nghĩa — cả mảnh (phần riêng trước đuôi / danh xưng, mảnh tách theo `·`) và mục ghép khi phủ trọn — chỉ được nhận khi nghĩa chọn là (a) kiểu tên Hán-Việt: không phải chữ Latin, viết hoa chữ đầu mọi từ ("Đông Khu"); hoặc (b) chữ Latin mà khoá có ≥ 1 chữ thuộc tập chữ phiên âm (`LocalNameFilterProperNames.coverEntry` / `hasTranslitChar`). Không đạt ⇒ về Hán-Việt như cũ. Đường "cả từ có trong từ điển" giữ nguyên (图铎 đứng một mình vẫn ra Tudor). Bỏ ca lạ ở truyện Trung: 炎珠草 "Viên viêm châu thảo" ⇒ "Viêm Châu thảo", 黑礁岛 không còn ra "Black Lagoon đảo".
- Ngưỡng (b) là **≥ 1 chữ**, không phải ≥ nửa (session chính chọn): tập 268 chữ thiếu nhiều chữ phiên âm thông dụng như 戴 里 图 铎, ngưỡng ≥ nửa làm hỏng 戴里克 Derrick, 所罗门 Solomon, 查拉图 Zaratul. Chọn nghĩa Latin (`pick`) và đoán tên khi bật "Ưu tiên tên Latin" vẫn dùng ngưỡng ≥ nửa.
- Tập chữ phiên âm đóng trong app: `Sources/Resources/Translation/NameFilterTranslitChars.txt` (268 chữ, đúng `translitChars` của `translit_latin.json` @ HF `0df8c84a`), đọc một lần qua `LocalNameFilterTranslitChars`, dùng ở **mọi** chế độ kể cả tắt Latin (cách C) — giữ được Backlund Đông Khu, Russel đại đế, Derrick Berg khi tắt Latin. `translitChars` trong file mô hình chỉ để đối chiếu: lệch ⇒ log ❌ (`LocalNameFilterLatinModelGate`).
- Python tham chiếu `name_meaning.py` sửa trước (`cover_entry`, `has_translit_char`, `load_translit_chars`); 10 truyện giữ y hàng. Với VP của anh, so với trước, đổi 8 hàng (tắt và bật Latin như nhau): 炎珠草 (sửa đúng), 图铎家族 / 图铎王朝 Tudor ⇒ Đồ Đạc, 水仙花街 "Thủy Tiên Hoa nhai", 沐氏家族 "Mộc Thị gia tộc", 天元圣女 "Thiên Nguyên Thánh Nữ", 天使神神位 "Thiên Sử Thần Thần Vị", 剑道·君亭 "Kiếm Đạo Quân Đình".
- Comment `LocalNameFilter.Suffix`: danh sách đuôi chỉ để ghép nghĩa (không còn "đuôi đang bật").
- Chưa biên dịch (máy Windows), chưa thử trên máy.

## [1.3.1099] - 2026-11-27

### feat: gói name tạm tự cập nhật theo danh sách đuôi và danh sách không phải name

- Gói tạm của Lọc name local nhớ thêm `autoMeanings` (chữ Hán ⇒ nghĩa máy ghép + loại, lúc lọc hoặc lần cập nhật trước; plan 2026-11-27-nghia-ten-tay-huyen mục 6). Trường tuỳ chọn: gói cũ chưa có ⇒ không ghép lại nghĩa. Màn duyệt mang theo qua `ReviewContext` (lọc xong, mở lại gói, ghi gói).
- Mỗi lần trang đầu "Lọc name local" hiện ra (mở sheet, quay lại từ màn danh sách, bấm ‹ ở màn duyệt), `LocalNameFilterDraftRefresher` cập nhật các gói của truyện đang mở ngoài main: bỏ name nằm trong "Không phải name" (xoá cụm khỏi danh sách thì name đã bỏ không quay lại; gói hết name ⇒ xoá gói); địa danh / tổ chức / thuật ngữ mà nghĩa đang có bằng nghĩa máy ghép ⇒ ghép lại bằng đúng bộ ghép nghĩa của bộ lọc với danh sách đuôi hiện tại + công tắc "Ưu tiên tên Latin" của truyện (cập nhật nghĩa, `autoMeanings`, cờ đoán); nghĩa đã tự sửa giữ nguyên; người / họ tộc không ghép lại. Bật Latin mà thiếu mô hình ⇒ lần đó không ghép lại.
- `LocalNameFilterMeaningComposer`: ghép nghĩa một name lẻ (chụp từ điển của truyện) bằng `LocalNameFilterMeaningBuilder` đường hàng LAC. `LocalNameFilterDraftStore.update`: đọc – sửa – ghi trong một lần giữ khoá, không đổi thì không ghi, `savedAt` giữ nguyên.
- Nút "?" của mục "Gói tạm chưa lưu" thêm đoạn giải thích việc tự cập nhật. Log `🔎 [LọcName] Cập nhật gói tạm: bỏ N name…, ghép lại M nghĩa…`.
- Chưa biên dịch (máy Windows), chưa thử trên máy.
