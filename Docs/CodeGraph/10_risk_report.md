---
generated_by: Antigravity
generator_version: 1.0
generated_at: 2026-08-21T10:30:00+07:00
git_commit: UNKNOWN
source_files: 230
document_version: 4
---

# Báo cáo Rủi ro Kỹ thuật (Technical Risk Report)

Tài liệu này báo cáo chi tiết các rủi ro kỹ thuật tiềm ẩn hoặc hiện hữu được phát hiện trong mã nguồn dự án FreeBook, phân loại theo mức độ nghiêm trọng (Severity) và khả năng xảy ra (Likelihood), đi kèm với nguyên nhân và giải pháp khắc phục.

## Ghi chú thủ công (Human Notes)
*Ghi chú thủ công của con người.*

<!-- GENERATED START -->
## Ngân sách type-check của `ReaderView` là một rủi ro có thật, đã nổ một lần (1.3.335)

* **Rủi ro đã hiện thực hoá.** Mục 1.3.334 ngay dưới nói "lượt này chưa được biên dịch — host là Windows"; CI sau đó **đỏ** với đúng một lỗi: `Sources/Views/Reader/ReaderView.swift:350:9: error: the compiler is unable to type-check this expression in reasonable time`. Nguyên nhân là thêm `definitionPanelOverlay(in: geometry)` vào một biểu thức đã dài **330 dòng** (`GeometryReader` + `ZStack` 7 con + 21 modifier). Không phải lỗi logic — nhưng là lỗi chặn toàn bộ build, và **không** gate local nào bắt được: `check_architecture.py` chỉ đếm dòng vật lý, `validate_links.py` chỉ so hash.
* **Rủi ro còn lại — mỗi lần thêm view con vào `ReaderView` là một lần tiến gần trần trở lại.** Sau khi tách 8 tầng, tầng lớn nhất còn `readerPresentationNavigationLayer` (~90 dòng, có closure `let browserUrl: String = { … }()` lồng trong `fullScreenCover`). Dấu hiệu sớm duy nhất là thời gian biên dịch file này; không có cảnh báo nào trước khi nó chuyển thành lỗi cứng.
* **Rủi ro thấp nhưng cần biết — tách tầng không phải phép biến đổi trung tính về mặt SwiftUI nếu làm sai thứ tự.** Ở lượt này thứ tự modifier được giữ đúng từng bước (`toolbar` → 4 `sheet` → 10 `onChange` + `onReceive` → 2 `sheet` + 2 `fullScreenCover` → `background`), nên cây view sinh ra giống hệt. Đổi thứ tự khi tách (ví dụ đẩy `background` lên trước `sheet`) sẽ đổi vùng an toàn và ngữ cảnh trình bày mà **không** có lỗi biên dịch nào báo.
* **Chưa biên dịch tại chỗ.** Host vẫn là Windows, `xcodebuild` không chạy được: bằng chứng duy nhất cho lượt sửa này là đọc code + `check_architecture.py` (vẫn **8** violation cũ, `ReaderView.swift` 1997/2053 dòng) + `validate_links.py`. CI xanh — nếu xanh — chỉ chứng minh **biên dịch được**.

## Rủi ro của gộp tiền tố chương sau, tải lẻ chương, và panel Dịch gánh Check rule (1.3.334)

* **Rủi ro nặng nhất — lệch chỉ số ⇄ audio, lần này ở tiền tố chương sau.** Cùng lớp rủi ro với 1.3.332 nhưng ở `TTSNextChapterPrefixCache`, nơi audio được nhồi vào `preloadedData` theo index tuyệt đối. Ba lớp chặn: chunk rỗng (sau `applyReplacements` + trim) **bị loại khỏi lượt gộp** và không được cấp slot nào; `TTSNextChapterPrefixSynthesizer.googleBatch` throw nếu `audios.count != texts.count`; `offset = batchIndices[0]` chỉ dùng để dựng khoá, còn việc gán vẫn đi qua `batchIndices[i]` chứ không phải `offset + i`. Đây là chỗ phải nghe thử đầu tiên: **mở chương mới ngay sau khi tiền tố nạp xong** và kiểm câu đầu chương có đúng câu đầu không.
* **Rủi ro đã biết — một `503` làm mất cả tiền tố.** Giống 1.3.332: gộp đổi độ bền lấy số request. Giảm thiểu hai tầng: `RemoteTTSSynthesisCoordinator` retry 2 lượt *bên trong* (và `TTSManager` **không** được bọc thêm vòng retry), rồi `recoverBatchFailure` xếp lại **từng** chunk qua đường một-request. Điều kiện `batchIndices.count >= 2` khiến trường hợp thiếu một chunk lẻ không đi đường gộp — không có lợi mà thêm một điểm hỏng.
* **Rủi ro đã chặn — huỷ nhầm/nhận nhầm kết quả cũ.** Lượt gộp phát **một** `nextTaskToken` gán cho **mọi** index nó phục vụ, nên khi cửa sổ trượt hoặc chương đổi, mọi index của lượt đó cùng mất hiệu lực một lúc — không còn trạng thái nửa vời "một nửa lượt gộp còn được nhận". `CancellationError` `return` thẳng, **không** tính là synthesis failure và **không** kích `recoverBatchFailure`.
* **Rủi ro đã biết — nút tải lẻ chương không huỷ được.** `downloadChapter` không giữ handle của `Task`, nên đóng danh sách chương (hay đóng Reader) **không** dừng lượt tải: repository vẫn ghi cache và toast vẫn hiện sau đó. Chủ ý, đúng luật "nội dung đã qua checkpoint cancel cuối thì lệnh ghi nền không được cancel", nhưng hệ quả nhìn thấy được là toast "mồ côi". Bấm nhiều chương liên tiếp là **nhiều task song song** — không có hàng đợi, không giới hạn số lượt; ai muốn tải cả truyện phải dùng `DownloadManager`, không phải nút này.
* **Rủi ro đã biết — nút tải lẻ đi đường riêng, không dùng `ReaderViewModel.loadChapterContentFromExtension`.** Nó gọi thẳng `ChapterContentRepository.load(forceRefresh: false)` để **không** kéo theo bước dịch + dựng `[ParagraphItem]`. Đánh đổi: nếu sau này khâu nạp chương thêm một bước hậu xử lý ở `ReaderViewModel`, nút này sẽ **không** thừa hưởng. Header comment của `ReaderChapterListView+Download.swift` ghi rõ điều đó.
* **Rủi ro đã biết — `host` của chương chưa có trong `ChapterStore`.** `downloadChapter` lấy `row?.host` và fallback về host của truyện. Nếu truyện có chương đến từ host khác mà hàng chưa được ghi, lượt tải sẽ hỏi sai host và thất bại (toast lỗi), **không** làm bẩn cache — repository chỉ ghi khi nạp được.
* **Rủi ro đã biết — panel Dịch chẩn đoán đoạn, không chẩn đoán vùng bôi đen.** `focusedRuleRange` = `trace.sourceRange` của chip đang chọn, tức phạm vi *rule chạm được*, không phải phần người dùng bôi đen. Khác biệt duy nhất so với màn Check rule cũ, và là chỗ dễ bị báo là bug: bôi một từ nhưng chip lại tô cả cụm dài hơn. Không snap về selection là chủ ý — snap sẽ làm mất ngữ cảnh mà rule thực sự khớp.
* **Rủi ro đã biết — `.presentationDetents([.height(660), .large])` là số cứng.** 660pt vừa đủ cho ô nghĩa dịch + ô nghĩa rule + dải chip trên máy thường; trên iPhone SE hoặc khi bật cỡ chữ trợ năng lớn, panel sẽ chạm trần và phải kéo lên `.large`. Không có phép đo động nào ở đây.
* **Rủi ro trình bày — không rule nào chạm đoạn thì panel không được im lặng.** `ruleNoticeText` phân biệt ba nguyên nhân bằng ba câu khác nhau ("Máy chưa có bộ rule nào…", "Công tắc rule dịch đang TẮT…", "Không rule nào chạm đoạn này."). Gộp lại một câu là đẩy người dùng đi tìm bug ở chỗ không có bug.
* **Không có gate tự động nào bắt được hồi quy của lượt này**, và **lượt này chưa được biên dịch** — host là Windows nên `xcodebuild` không chạy được. `check_architecture.py` (12 → 8) chỉ đếm dòng/regex, `validate_links.py` chỉ so hash, tầng `Tests/` bị coi như không tồn tại. CI xanh chỉ chứng minh **biên dịch được**.

## Rủi ro của việc gộp request Google TTS (1.3.332)

* **Rủi ro nặng nhất — lệch chỉ số đoạn ⇄ audio.** API **bỏ im lặng** part rỗng, nên gửi 5 part mà một part rỗng thì nhận 4 audio và mọi đoạn từ đó trở đi nghe sai đoạn. Đã chặn ba lớp: `makeGoogleBatch` loại text rỗng **trước** khi gửi (và những index đó đi đường một-đoạn), `synthesizeBatch` từ chối part rỗng ở đầu vào, và **bắt buộc** `audios.count == parts.count` — không khớp thì `throw`, không gán bừa. Đây là chỗ phải nghe thử đầu tiên trên máy thật.
* **Rủi ro đã biết — một lỗi mạng làm mất cả cửa sổ thay vì một đoạn.** Lượt đo thử API gặp một `503 UNAVAILABLE` thật, nên chuyện này sẽ xảy ra. Giảm thiểu: `withRetry` 2 lượt trong `GoogleTTSService`, và `fallbackToPerParagraphPrefetch` xếp lại từng đoạn cho đúng những index đã hỏng. Bù lại: gộp làm **số request giảm 5–10 lần**, tức số lần có cơ hội gặp 503 cũng giảm.
* **Rủi ro đã chặn — cửa sổ trượt huỷ mất lượt gộp còn dùng được.** Một task gộp được ghi vào `prefetchTasks` cho **mọi** index nó phục vụ; nếu vẫn huỷ theo index như trước thì đúng một nhịp sau khi phát, index cũ nhất rơi khỏi cửa sổ và task bị huỷ, kéo theo cả những đoạn còn cần. `pruneRemotePrefetchTasks(keeping:)` so **định danh task**, chỉ huỷ task không còn phục vụ index nào trong cửa sổ.
* **Rủi ro đã biết — bộ nhớ của một lượt gộp.** 20 part trả ~615 KB base64 → ~380 KB mp3, và toàn bộ phản hồi được `JSONSerialization` một lần. Cửa sổ hiện tại là `clamp(currentPrefetchCount, 1, 10)` nên thực tế tối đa 10 part; nếu ai nâng trần cửa sổ thì phải xem lại đỉnh bộ nhớ của lượt parse.
* **Không mở đường vòng nào quanh coordinator.** Lượt gộp vẫn là **một** job của `RemoteTTSSynthesisCoordinator` nên bất biến "một lượt tổng hợp remote tại một thời điểm" giữ nguyên; telemetry năng lượng vẫn đếm đúng (`textChars` là tổng, `audioBytes` là tổng của lượt).
* **Rủi ro đã biết — `moveScope` không nguyên tử.** Chuyển phạm vi rule là hai lần ghi file (`copy` rồi `delete`). Ghi ở đích **trước** để lỗi giữa đường không làm mất rule người dùng tự viết; nếu xoá thất bại thì rule tồn tại ở **cả hai** phạm vi và toast nói đúng điều đó. Không có transaction nào phủ hai file, và làm một cái ở đây là quá tay.
* **Rủi ro đã biết — đảo thứ tự tab đổi nghĩa payload `shelfTab`.** Bản app cũ (nếu chạy song song bằng cách nào đó) gửi số theo bảng cũ; `ShelfView` nay ép qua `ShelfTab(rawValue:)` và **bỏ qua** số lạ thay vì kẹt tab sai. `selectedTab` là `@State` nên không có trạng thái đã lưu nào bị hỏng vì việc đánh số lại.

## Rủi ro của đợt tối ưu 1: cache cũ và kho không tự cập nhật (1.3.330)

* **Rủi ro chính — cache script phục vụ bản `tts.js` cũ.** `ExtTTSScriptCache` hết hạn theo **mốc sửa** của `plugin.json` và của file script. Ba đường làm mới đều đã nối: sửa cấu hình (`configJson` vào khoá), cài lại / sửa script trong app (file đổi mốc), `resetTTSRuntime()` (`invalidateAll`). Đường **chưa** phủ: một file bị thay mà mốc sửa **không đổi** (chép bằng công cụ giữ nguyên timestamp). Triệu chứng sẽ là "sửa script mà giọng đọc không đổi" cho tới khi tắt/mở lại app — không mất dữ liệu, nhưng khó truy nếu không đọc mục này.
* **Rủi ro đã chặn — fingerprint và nội dung script lệch nhau.** Trước lượt này `getTTSRuntimeFingerprint` và `ttsGenerate` đọc đĩa **riêng**, nên một lần cài lại đúng giữa hai lần đọc sẽ tạo `synthesisKey` của bản cũ nhưng chạy bản mới (audio sai bị cache dưới khoá đúng). Giờ cả hai lấy từ **một** `Payload`.
* **Rủi ro đã biết — kho không tự cập nhật trong 6 giờ.** `RepositoryRefreshPolicy` mặc định `cooldownHours = 6`; người dùng mở tab Tiện Ích ngay sau khi tác giả kho đẩy bản mới sẽ **không** thấy cập nhật cho tới khi bấm nút refresh. Đây là đánh đổi có chủ ý (đổi độ mới lấy ~95 request mỗi lần mở tab), và nút refresh tay vẫn bỏ qua cửa. `markRefreshed()` chỉ chạy khi ≥ 1 kho cập nhật được nên mất mạng không khoá cửa.
* **Rủi ro đã biết — icon sai sau khi cài lại extension.** `ExtensionIconImageCache` khoá theo `(đường dẫn, modDate)`, nên `icon.png` mới sẽ có khoá mới. Trường hợp hở giống rủi ro đầu: ghi đè icon mà giữ nguyên timestamp. Hệ quả chỉ là một ảnh cũ, không ảnh hưởng dữ liệu.
* **Rủi ro đã chặn — mất fallback icon theo loại.** Hàng ở tab Tiện Ích đổi sang `ExtensionIconView`, nhưng chỉ khi có `localPath` **hoặc** `iconUrl`; không có gì cả thì vẫn dùng icon theo loại (`waveform` cho TTS, `book.closed` cho truyện) như trước.
* **Không có gate tự động nào bắt được hồi quy của lượt này.** `check_architecture.py` chỉ đếm dòng và `validate_links.py` chỉ so hash; không có test (tầng `Tests/` bị coi như không tồn tại). Xác minh phải bằng nghe thử Ext TTS trên máy thật và mở tab Tiện Ích hai lần liên tiếp để thấy lượt thứ hai không còn request. **Lượt này chưa được biên dịch hay nghe thử** — host là Windows.

## Rủi ro của `@Model` thứ 6 và của việc mất thước đo phiên âm (1.3.328)

* **Rủi ro nặng nhất lượt này: schema.** Thêm `BookCollection` và hai field vào `Book` đi qua **lightweight migration** của SwiftData, không có `SchemaMigrationPlan` nào để tự kiểm soát. `ModelContainer` init lỗi là `fatalError` ⇒ triệu chứng là **app không mở được**, trên máy có sẵn `library.db` cũ. Giảm thiểu: mọi thay đổi đều additive + có mặc định, không đổi tên/kiểu/xoá field. **Chưa xác minh trên máy thật** — máy phát triển đang là Windows, không `xcodebuild` được, và điều này phải được kiểm ngay lần build đầu trên macOS với một `library.db` sinh từ bản trước.
* **Rủi ro đã chặn — xoá bộ sưu tập kéo theo sách.** `deleteRule: .nullify` ở cả hai đầu quan hệ N-N, cộng việc `deleteCollection` dọn tay `books = []` trước `context.delete`. `.cascade` ở đây là mất truyện thật; đây là lý do bất biến được ghi ở cả code, `rules.md` và `12_ownership_graph`.
* **Rủi ro đã chặn — trạng thái "trong bộ sưu tập mà không trên kệ".** Ba đường hạ `isOnShelf` (`removeFromShelf`, `setOnShelf(false)`, `addBookToShelf(isOnShelf: false)`) đều dọn `collections` + `isPinned` trong cùng `save()`. Đường xoá truyện hẳn không cần dọn tay: SwiftData tự tháo liên kết.
* **Rủi ro đã biết — số tab là hợp đồng bằng số nguyên trần.** Lịch Sử chuyển 2 → 3; `SearchView` là bên gửi duy nhất (`userInfo["shelfTab"]`). Đổi một đầu mà quên đầu kia ⇒ sau khi đổi nguồn, app nhảy sang tab Bộ Sưu Tập thay vì Lịch Sử, **không lỗi nào nổ**. Cả tên notification lẫn giá trị đều không có hằng số kiểu bảo vệ.
* **Rủi ro đã biết — nhấn giữ trên `List` là cử chỉ tự lắp.** Dòng truyện đổi từ `Button` sang `onTapGesture` + `onLongPressGesture`, nên mất hiệu ứng nhấn của button và mất luôn peek/preview của `contextMenu`. Đổi lại: `contextMenu` chỉ nhận `Button`/`Link` nên không dựng được sheet có bìa + danh sách bộ sưu tập bấm được. Nếu bọc `Button` **và** gắn long-press thì nhả tay sau khi giữ mở luôn Reader phía sau sheet — đó là lý do không làm cách đó.
* **Rủi ro backup — khoá mới trong bản ghi Codable.** `BookRecord.isPinned` là `Bool?` vì `init(from:)` tổng hợp của Swift **không** dùng giá trị mặc định: một khoá không-optional mới sẽ làm **mọi** `.fbbackup` cũ decode lỗi, tức mất luôn đường khôi phục. `Counts.collections` an toàn nhờ `init(from:)` viết tay sẵn có. Không thêm `BackupScope` nào ⇒ bản app cũ vẫn decode được `manifest.scopes` của archive mới.
* **Rủi ro đã biết — khôi phục gộp theo tên bộ.** Máy đích đã có bộ "Đang đọc" thì bộ cùng tên trong archive **nhập vào bộ đó**, không tạo bộ thứ hai. Đó là lựa chọn có chủ ý (tránh danh sách nhân đôi), nhưng nghĩa là hai bộ khác nhau vô tình cùng tên sẽ bị trộn — không có `collectionId` nào được đối chiếu.
* **Phân hệ tiền xử lý TTS mất thước đo duy nhất.** Xoá màn Thử phiên âm + `TransliterationGoldenSet` theo yêu cầu. **Phát biểu "thước đo duy nhất là `TransliterationGoldenSet` chạy ở màn Thử phiên âm" ở mục 1.3.30x bên dưới không còn đúng** — từ nay chỉ còn nghe thử ở "Thử giọng đọc", và `probeVoices` (chốt phát hiện `espeak-ng-data` thiếu `voices/en`/`en_dict`) cũng mất, nên trường hợp đó giờ chỉ còn dấu vết ở `AppLogger` khi `phonemizeEnglish` đặt giọng thất bại. Rủi ro thực tế: một lượt dọn `espeak-ng-data` trong `build-ipa.yml` làm rơi tiếng Anh mà **không** còn báo đỏ nào trong app.
* **Đổi 15 giá trị bảng phiên âm Nhật (`ư` → `u`) chưa được nghe thử** — đúng theo hệ quả ở trên. Rủi ro giới hạn ở chất lượng đọc, không ảnh hưởng dữ liệu; `collapseLongVowels`, `ー` → `""` và `sokuonCoda` không bị chạm nên không có hồi quy "arigatou → a-ri-ga-tô-ư" quay lại.

## Rủi ro mới: lệnh từ LAN nay thêm được extension vào thư viện (1.3.325)

* **Bề mặt rủi ro tăng thật, không phải tăng trên giấy.** Trước 1.3.325, tệ nhất mà một client LAN làm được là ghi đè file của extension **người dùng đã tự cài**. Nay nó xin được cả việc *thêm* một extension mới: thư mục `extensions/<packageId>/` + một hàng `Extension` trong thư viện. Mọi extension trong thư viện đều chạy JS được, nên đây là đường ngắn nhất từ "một máy trong cùng Wi-Fi" tới "app chạy code của máy đó ở lượt đọc truyện sau".
* **Chốt duy nhất vẫn là một lần bấm trên thiết bị**, và nó được làm rõ đúng chỗ đáng lo: `Kind.installNew` khiến màn xác nhận hiện "Cài MỚI extension \<tên\> → \<packageId\>", nhãn nút đổi thành "Đồng ý cài mới", footer nói thẳng app sẽ **tạo thư mục và thêm bản ghi**, kèm "chỉ đồng ý nếu bạn biết máy nào đang gửi". Tên hiển thị đọc từ `plugin.json` vì `packageId` một mình không cho người bấm biết họ đang nhận cái gì.
* **Sửa lại phát biểu "cài bản nháp chỉ đổi file" ở mục 1.3.303 bên dưới**: nay chỉ đúng cho nhánh **ghi đè**. Nhánh cài mới ghi hàng `Extension` (name/version/type/locale/source đọc từ `plugin.json`) — nhưng vẫn **không** ghi `configJson` (để coordinator đặt `"{}"`) và **không** gán `repositoryUrl`, nên lượt đồng bộ kho sau đó không coi nó là bản lạc để prune.
* **Rủi ro đã chặn — ghi nửa vời vào thư viện.** Thứ tự file → bản ghi là bắt buộc: copy file thất bại thì không có bản ghi nào được tạo; bản ghi thất bại thì client nhận `INTERNAL_ERROR` nói rõ "đã copy file nhưng không ghi được thư viện", và thứ còn lại chỉ là thư mục mồ côi mà `ExtensionInstallAudit` phát hiện được.
* **Rủi ro đã biết — `packageId` trùng của một extension khác.** Hai extension khác nhau cùng khai một `metadata.name` (hoặc cùng `metadata.packageId`) sẽ dùng cùng thư mục: lượt cài thứ hai bị nhận diện là *cập nhật* và ghi đè lượt đầu. Bản cũ vào `.backup/` nên rollback được, nhưng app **không** có cách nào biết đó là hai extension khác nhau — đúng giới hạn mà đường import zip vốn đã có.
* **`draft.stage` không còn đòi extension đã cài**, nên một client LAN ghi được vào `extension-drafts/` cho bất kỳ `packageId` an toàn nào. Trần vẫn là 200 file / 1 MiB mỗi file / 4 MiB tổng mỗi revision, path bị kiểm containment hai lần, và cả vùng bị xoá sạch khi tắt server hoặc mở lại app. Chưa có trần **số revision** cho mỗi phiên — dung lượng tối đa bị chặn bởi việc client phải stage tuần tự, không bởi một hằng số.

## Rui ro cua debug server LAN (1.3.303)

* **Da chan - server mo im lang.** Mac dinh tat, chi bat bang thao tac trong Cai Dat, va `MainTabView` tat han khi app roi foreground. Khong co `UIBackgroundModes` nao cho no song tiep, nen khong co ca "quen tat roi de mo ca ngay".
* **Da chan - mot may trong cung LAN doc lom token.** Token dung dung **chi mo cua xin phep**; phai bam "Cho phep ket noi" tren thiet bi moi co session. Token 256-bit, mot lan, het han 3 phut, khong vao Bonjour TXT record, khong vao log, khong vao `ExtensionDebugEvent`. So sanh token bang thuat toan hang thoi gian.
* **Da chan - client thu hai chen vao.** `newConnectionHandler` `cancel()` ngay ket noi thu hai; khong xep hang. Client roi di thi cap **token moi**, khong dung lai token cu.
* **Da chan - lenh tu mang chi dinh cho ghi file.** `run.start` khong co field path; `draft.chunk` chi nhan `relativePath` da khai trong manifest, di qua `pathIssue` roi kiem containment lan hai sau `standardizedFileURL`. Khong giai nen archive nen khong co symlink/zip bomb.
* **Da chan - ghi de extension khong ai biet.** `draft.install`/`draft.rollback` treo o `ExtensionDebugInstallGate` cho toi khi nguoi dung bam, va nguoi bam thay truoc danh sach `+/~/-` tung file. Ban cu duoc copy sang `.backup/` **truoc** khi thay; thay bang `replaceItemAt` (nguyen tu).
* **Con ho, co y - `ws` chua co TLS.** Ai o cung LAN va nghe duoc goi tin se doc duoc trace va lenh (khong doc duoc token neu ho khong thay QR, nhung doc duoc noi dung phien sau khi da pair). Chap nhan cho MVP tren LAN tin cay; chuyen `wss` + fingerprint qua QR la viec bat buoc truoc khi mo cho moi truong rong hon. Da ghi o Phase 0 cua plan.
* **Con ho, co y - IP trong pairing URI.** Chot Phase 0 noi URI chi chua service/port/token; ban trien khai them `host`. IP noi bo khong phai bi mat va no bo duoc dependency mDNS cho client tren Windows/Linux - nhung day la mot lech chot da co y, khong phai sot.
* **Rui ro da biet - cai ban nhap chi doi file.** Hang `Extension` trong SwiftData (`version`, `name`, `configJson`) **khong** duoc cap nhat, vi ghi SwiftData phai qua `ExtensionTransactionCoordinator` va mot ban dang thu khong nen doi metadata thu vien. He qua: sau `draft.install`, `plugin.json` tren dia co the khai version khac voi version trong thu vien. Rollback dua file ve dung ban cu nen do lech nay tu het.
* **Rui ro da biet - `.backup/` chi giu mot the he.** Cai hai lan lien tiep thi ban goc bi mat: lan cai thu hai sao luu chinh ban vua cai. Ai muon quay ve ban goc phai cai lai extension tu kho.
* **Chua lam - unsaved overlay cua Phase 3.** Chi co saved snapshot; document dang mo chua luu thi khong duoc gui. Do la buoc ke tiep trong plan, khong phai sot.

## Rủi ro của trace debug extension (1.3.302)

* **Đã chặn — rò bí mật qua trace.** Redaction nằm ở phía *tạo* event, không ở phía gửi, nên không có đường nào để event chưa sạch lọt ra khi Phase 2 gắn socket. `ExtensionDebugRedactor` cố ý **không có hàm nhận header hay body**: thiếu hàm là chốt rẻ nhất. URL giữ scheme/host/path và thay **mọi** giá trị query bằng `…`; user/password/fragment bị bỏ. Summary kết quả dùng `compactRepresentation` (`[Array: 20 items]`) nên nội dung chương không bao giờ vào trace.
* **Đã chặn — path tuyệt đối trong sandbox.** `ExtensionDebugSourceLocation.script` luôn là path **tương đối** so với gốc extension, và stack bị bỏ phần thư mục. Client Phase 2 chỉ được biết path có khai trong manifest.
* **Đã chặn — script chạy tràn làm treo UI.** Quota 600 event/run + 2000 toàn hub; vượt trần run thì bỏ event **mới** và chèn một `eventsDropped`, nên `console.log` trong vòng `while` không làm hub phình vô hạn. `emit` không blocking nên quota không bao giờ chặn JS.
* **Còn hở, có chủ ý — trace là plaintext trong RAM.** Hub sống trong process, không ghi đĩa, mất khi app tắt. Không có mã hoá; ai xem được màn hình thì xem được trace. Chấp nhận vì màn này chỉ vào được bằng thao tác người dùng trong Cài Đặt và không phát ra mạng.
* **Còn hở, có chủ ý — debug run có side effect thật.** Nó gọi network thật của extension, ghi `localStorage`/`cacheStorage`/cookie của **đúng package đó** (namespace `vbook_ext_storage_<md5(localPath)>_`). Phase 1 cố ý chạy source **installed** để chứng minh runtime thật; tách storage cho bản nháp là việc của Phase 3.
* **Rủi ro đã biết — `ExtensionManager` và `ExtensionDebugEntrypoint` là hai bản của cùng một contract.** Đánh đổi để manager không phải đổi chữ ký. Nếu sau này `search` đổi `page` từ `String` sang `Int` mà chỉ sửa một bên, màn debug sẽ chạy đúng nhưng production sai (hoặc ngược lại) — và triệu chứng xuất hiện ở chỗ khác. Doc ở đầu `ExtensionDebugEntrypoint` ghi rõ nghĩa vụ này.
* **Không phải rủi ro — đường production.** Mọi call site cũ truyền `debugSink = nil` và mọi điểm phát `guard let sink else { return }` ngay đầu, nên đường đọc/tải chỉ trả thêm một phép kiểm tra `nil`; không cấp phát, không format chuỗi.

## Đổi cấu hình dựng đoạn làm cache chương khác lỗi thời (1.3.299)

* **Đã chặn**: bật/tắt "hiện tên chương" hoặc "bỏ tiêu đề trùng" mà chỉ dựng lại chương đang hiển thị thì các chương còn trong `ChapterCache` vẫn giữ `paragraphItems` dựng theo cờ **cũ**, và cấu hình mới trông như chỉ áp cho một chương. `ReaderViewModel.invalidateParagraphLayoutForCachedChapters` hạ `translationToken = 0` cho mọi chương khác để worker điều hướng dựng lại khi người dùng tới — cùng cơ chế `updateCachedTranslatedContent` đang dùng cho đổi từ điển.
* **Còn hở, có chủ ý**: hai cờ chỉ được đọc lại lúc dựng đoạn, nên TTS đang phát **không** dựng lại chunk giữa chương; chương kế tiếp mới theo cờ mới. Đây là hành vi từ 1.3.189, lượt này không đổi.
* **Rủi ro đã gặp thật, đã sửa**: `ReaderSettingsView` dùng chiều cao sheet cố định (`.height(500)` rồi `.height(600)`) trong khi nội dung co giãn — 3 hàng phụ chỉ xuất hiện khi bật dịch — nên hàng cuối bị cắt. Nay là `ScrollView` + `.presentationDetents([.fraction(0.75), .large])`: không cấu hình nào của nội dung cắt được hàng nào.

## Kết quả E1 và rủi ro còn lại (1.3.297)

**E1 đạt một phần.** `θˈɪŋk` đọc đúng; `ðˈɪs` và `kˈæt` sai. Xác nhận đúng cái bẫy đã nêu: **có mặt
trong từ vựng không đồng nghĩa với đã được train**. Hệ quả cho thiết kế: hướng đi là **hybrid** — đưa
IPA thẳng vào model, nhưng thay ký hiệu chưa train bằng ký hiệu gần nhất đã train (`ð → z`, `æ → ɛ` là
hai ứng viên đầu, cần xác nhận bằng phép so bộ ký hiệu). Không phải passthrough toàn bộ, cũng không
phải phiên âm sang chữ Việt toàn bộ.

**Phủ âm vị: 0 scalar ngoài từ vựng.** Đây là kết quả quan trọng thứ hai: espeak `en-us` trên 24 từ
không sinh ra ký hiệu nào ngoài 161 ký hiệu của model. Nghĩa là **tầng tra id không mất chữ**, và toàn
bộ hiện tượng "mất chữ nhiều" nằm bên trong `IPAToVietnameseMapper`. Bảng `downgrade` của
`PiperPhonemeInventory` vì vậy chưa có việc gì làm với tiếng Anh; nó vẫn cần cho tiếng Nhật (`ɴ`).

**Ca đối chứng cũ của tôi sai, và đó là một rủi ro về phương pháp.** `sˈaːw` không phải IPA của "sao";
nghe ra "chao" là đúng với chuỗi đã đưa vào, không phải lỗi model. Chuỗi đối chứng tự đoán có thể dẫn
tới kết luận ngược hẳn. Nay ca đối chứng lấy IPA **thật** từ espeak `vi` rồi tổng hợp lại chính chuỗi
đó, nên nó tự kiểm chứng.

**Bộ phân loại: 8/24 ca sai, và đây là giới hạn của phương pháp chứ không phải lỗi hiệu chỉnh.**
`sakura`/`sonata`, `kimono`/`tomato`, `karate`/`potato`, `nakama`/`banana` giống nhau trên mọi dấu hiệu
bề mặt (6 chữ, CVCVCV, kết thúc nguyên âm, không cụm phụ âm Anh, không âm đặc trưng Nhật). Không ngưỡng
nào tách được chúng — mọi lựa chọn đều sai một phía. Rủi ro còn lại sau khi thêm whitelist: từ gốc Nhật
**không** có trong danh sách sẽ bị đọc theo luật tiếng Anh (ngưỡng 4 cố ý bảo thủ). Đây là đánh đổi có
chủ ý, vì trong truyện dịch từ tiếng Anh nhiều hơn cả bậc.

**Chưa sửa, và cố ý chưa sửa:** thiếu dấu thanh trong `IPAToVietnameseMapper` (bộ ca kiểm cho thấy
"bac"/"xit-tơm"/"iet"/"tec-xơ" — âm tiết Việt kết thúc bằng `-c`/`-t` mà không có thanh là **sai
phonotactics**, espeak `vi` sẽ xử lý không đoán được), và `arigatou → a-ri-ga-tô-ư` (luật `ou → ô`
không nổ). Cả hai chỉ còn quan trọng nếu E1 vòng 2 kết luận phải giữ đường phiên âm sang chữ Việt; đầu
tư vào chúng trước khi biết điều đó là làm việc có thể phải bỏ.

## Rủi ro của hướng đưa IPA thẳng vào model (1.3.296)

**Rủi ro chính, và là lý do lượt này chỉ ship dụng cụ đo chứ chưa sửa: ký hiệu có trong từ vựng nhưng có thể chưa được train.** `phoneme_id_map` 161 ký hiệu là bảng IPA chuẩn Piper phát cho **mọi** giọng — nó nói lên model *nhận* được `θ ð æ`, không nói lên dữ liệu huấn luyện tiếng Việt từng chứa chúng. Embedding chưa train sẽ đọc ra tiếng lạ hoặc im lặng. Đây đúng là cái bẫy của lượt VieNeu (`style token 18` có tên `doc_truyen` nhưng nằm trong vùng random-init). Vì vậy thứ tự bắt buộc là **nghe trước, refactor sau**.

* **Nếu E1 đạt**, rủi ro tiếp theo là ngữ điệu: model tiếng Việt đọc IPA tiếng Anh vẫn sẽ mang thanh điệu và nhịp Việt, nghe "lơ lớ". Vẫn khá hơn hai lần chuyển đổi hiện tại, nhưng phải nghe A/B trên cùng một đoạn mới biết khá hơn bao nhiêu.
* **Nếu E1 thất bại**, đường lùi (P5) là giữ hướng phiên âm sang âm Việt nhưng dùng bảng đếm của E1 để bổ sung `IPAToVietnameseMapper` cho **đúng** những âm vị đang bị bỏ, thay vì đoán như hai lượt trước.

**Bảng hạ cấp của `PiperPhonemeInventory` là phỏng đoán có căn cứ, chưa phải đo.** Nó được gieo từ chính phép đo inventory (`ɴ→n`, `ʧ→tʃ`, tie bar → bỏ, `|→_`), nhưng danh sách ký hiệu espeak *thật sự* sinh ra chỉ biết được sau khi chạy bảng phủ âm vị trên máy. `downgrade` trả `nil` cho ký hiệu chưa biết, và `synthesizeRawPhonemes` **đếm** chúng thay vì bỏ im lặng — đó là cách để lần sau bổ sung đúng chỗ.

**Rủi ro của chính dụng cụ đo**: `TTSIPAProbeSection` dựng một `ONNXPiperEngine` **thứ hai** (giữ trong `@State` nên chỉ một lần cho mỗi lần mở màn), tức nạp thêm một bản model vào RAM cạnh bản đang phát. Với model Piper cỡ 60 MB trên máy 4 GB thì chấp nhận được, nhưng đừng mở màn này giữa lúc đang nghe truyện.

**Chưa chạm đường tổng hợp đang chạy.** `synthesizeRawPhonemes` là đường song song; `ONNXPiperEngine.synthesizeInternal` chưa bị sửa dòng nào, nên lượt này không thể làm hỏng chất lượng hiện tại.

## Rủi ro sau lượt chống mất chữ (1.3.291)

* **Chỗ mất chữ sâu nhất vẫn còn**: `ONNXPiperEngine` bỏ im lặng mọi unicode scalar không có trong `phoneme_id_map` của model (chỉ log). Lượt này chỉ bịt các tầng trên; bịt hẳn cần map âm vị **trong** inventory của model — việc của Phase 2, **chưa làm**.
* **Cụm phụ âm thành âm tiết đệm làm câu dài hơn**: "street" 2 âm tiết. Đọc đúng hơn nhưng nhịp chậm hơn. *(Phần "phụ âm cuối thừa thành một âm tiết đệm" của mục này đã bị 1.3.305 đảo lại — `trailingFiller` không còn.)*
* **Cổng ngữ cảnh siết lại bỏ sót chiều ngược**: "man" ở **đầu** một cụm tiếng Anh ("man of steel") không còn láng giềng lạ bên trái ⇒ giữ nguyên. Chọn bỏ sót thay vì đọc oan từ tiếng Việt.
* **Xoá tất cả phiên âm không hoàn tác được** và không có sao lưu tự động; chỉ có hộp xác nhận nêu rõ hậu quả. Ai đã xuất từ điển thì nhập lại được.
* **`deleteAllWords` ghi file rỗng thay vì xoá file** — cố ý: `loadResourcesFromDisk` coi file không tồn tại là "chưa tải từ điển", khác với "người dùng muốn trống".

## Rủi ro của lượt đổi phiên âm Anh/Nhật (1.3.290)

* **Phụ thuộc vào bộ dữ liệu espeak trong bản build.** Đường tiếng Anh mới chỉ chạy khi `voices/en` + `en_dict` có thật trong `espeak-ng-data` đã đóng gói. `build-ipa.yml` hiện giữ chúng, nhưng bước dọn dữ liệu đó là **xoá theo danh sách trắng** — sửa nó mà quên `en_dict` là cả tính năng âm thầm rơi về bộ luật cũ, không có lỗi nào nổ. Bù lại: `probeVoices` ở màn Thử phiên âm báo đỏ ngay, và `phonemizeEnglish` ghi `AppLogger` khi đặt giọng thất bại.
* **Đổi giọng espeak là trạng thái toàn cục.** `phonemizeEnglish` đặt `en-us` rồi trả `vi` trong `defer`, tất cả bên trong cùng `NSLock` mà `ONNXPiperEngine` dùng. Nếu sau này có ai gọi espeak **ngoài** `EspeakPhonemizer`, hoặc thêm một lối vào không trả giọng, thì Piper sẽ tổng hợp bằng âm vị tiếng Anh — sai giọng toàn bộ, và triệu chứng sẽ xuất hiện *muộn* sau một lần phiên âm.
* **Chất lượng bảng IPA→Việt chưa được kiểm trên máy thật.** Bảng phủ nguyên âm/phụ âm phổ thông cộng vài ký hiệu riêng của espeak (`ɐ ᵻ ɚ ɫ ɾ`); âm vị lạ bị `tokenize` bỏ qua, nên trường hợp xấu là mất một âm chứ không phải crash. Nhưng "mất một âm" khó phát hiện bằng mắt — đó là việc của bộ ca kiểm.
* **Bộ phân loại mới đổi hành vi trên *tập từ vô hạn*.** Bỏ blacklist là bỏ một danh sách chắc chắn đúng (~420 từ đã được xác nhận bằng tay) để đổi lấy một hàm chấm điểm tổng quát. Ngưỡng `japaneseThreshold` (hiện `4`) là con số **chưa được hiệu chỉnh trên dữ liệu thật**, chỉ trên ~24 ca kiểm; rất có thể phải điều chỉnh sau khi đọc thực tế.
* **Cổng ngữ cảnh có thể phiên âm oan từ tiếng Việt.** Điều kiện "có láng giềng lạ trong ±2 token" sai khi một câu tiếng Việt không dấu chen từ tiếng Anh: "anh Nam gọi taxi" có thể làm "nam" bị phiên âm. Giảm thiểu bằng cửa sổ hẹp + chặn ở dấu kết câu, và bằng việc tiếng Việt viết có dấu dày đặc. Không có cách nào đúng 100% mà không có bộ phân loại ngôn ngữ mức câu.
* **Trộn từ điển đánh đổi có chủ ý**: mục dưới máy **thắng** bản tải về, nên một chỉnh sai của người dùng sẽ không bị bản cập nhật từ máy chủ sửa lại. Chọn hướng này vì mất một bản cập nhật nhẹ hơn mất dữ liệu người dùng — và trước 1.3.290 thì bản tải về xoá sạch chỉnh tay.
* **Không có rủi ro âm thanh cũ**: PCM chỉ nằm trong RAM theo phiên nên đổi phiên âm không để lại audio sai trên đĩa. `transliterationCache` bị xoá mỗi khi từ điển đổi.

## Rủi ro của lượt ép âm tiết hợp lệ (1.3.305)

* **Bỏ phụ âm cuối thừa là mất thông tin, theo yêu cầu người dùng.** "text" → `téc` mất cả `/s/` và `/t/`; "task" → `tát` mất `/k/`. Bản 1.3.291 thêm `trailingFiller` chính là để không mất — đây là đảo lại có chủ ý, đổi "đủ âm" lấy "không có tiếng lạ". Nếu sau này thấy nhầm từ vì mất đuôi, đường lùi là bật lại `trailingFiller` cho **riêng** coda xuýt (`s`, `z`), không bật lại toàn bộ.
* **Nguyên âm đôi bỏ coda ở cuối từ cũng là mất âm.** "email" → `i-mây` mất `/l/`. `split` chỉ đẩy được cụm phụ âm sang âm tiết sau khi **còn** âm tiết sau; ở cuối từ thì không còn. Cách đúng hơn là biến `/l/` cuối thành bán nguyên âm (`i-mêu`), nhưng đó là một bảng rime mới, chưa làm.
* **`/ən/` → `ình` áp cho *mọi* `/ən/`, không riêng đuôi `-tion`.** Đây là lựa chọn tường minh của người dùng sau khi được nêu rõ hệ quả: "London" ra `lân-đình`, "seven" ra `xé-vình`. Nếu nghe sai nhiều thì siết lại bằng cách yêu cầu phụ âm đầu là `/ʃ/`/`/ʒ/`.
* **Luật dấu sắc dựa vào một giả định về `acute`**: nucleus của âm tiết có coda tắc **luôn** là nguyên âm đơn. Giả định này đúng *chỉ vì* luật "nguyên âm đôi không nhận coda" chạy trước. Bỏ hoặc nới luật kia mà không mở rộng `acuteVowels` là dấu thanh im lặng không được thêm — `acute` trả về nguyên chuỗi khi `count != 1`.
* **Chuỗi IPA thật của espeak chưa được đối chiếu trên máy.** Mọi luật mới ở lượt này được thiết kế trên IPA en-us *chuẩn* (`ˈeɪpɹəl`, `tæsk`, `stˈeɪʃən`). Hai luật nhạy cảm nhất với chuyện espeak viết gì: `/əl/` và `/ən/` — nếu espeak phát ra phụ âm âm tiết tính (`l̩`, `n̩`) thay vì `əl`/`ən` thì `stressMarks` xoá dấu `̩` và cả hai luật **trượt**, "google" sẽ ra `gúc` thay vì `gu-gồ`. Bộ ca kiểm ở màn Thử phiên âm là chỗ phát hiện chuyện đó ngay lượt chạy đầu.

## Rủi ro của lượt sửa đọc romaji Nhật (1.3.305)

* **`ya/yu/yo` → `da/du/dô` trùng đầu ra với hàng `za/zu/zo`.** Đây là hệ quả biết trước, không phải sót: tiếng Việt không có chữ nào đọc /j/ ở phụ âm đầu, nên hai âm Nhật khác nhau phải dùng chung một chữ. Ở giọng espeak `vi` mặc định (Bắc) `d` đọc /z/ nên `ya` nghe thành /za/; ở giọng Nam thì đúng /ja/. Lựa chọn của người dùng: sai một phụ âm nhẹ hơn sai **số âm tiết** — bản 1.3.290 viết `ia` và espeak-vi đọc thành nguyên âm đôi /iə/, "Yamato" ra "i-a-ma-tô".
* **Gộp trường âm là phép biến đổi *mất thông tin*, chạy trên mọi token đi đường Nhật.** `collapseLongVowels` không phân biệt trường âm với hai nguyên âm giống nhau tình cờ nằm cạnh nhau. Trong romaji Nhật hai thứ đó không phân biệt được bằng chính tả, nên đây là đúng; nhưng nếu sau này đường Nhật nhận chuỗi *không phải* romaji Nhật (ví dụ một tên riêng phương Tây bị bộ phân loại xếp sai phe) thì nó sẽ bị gộp nguyên âm oan. Bộ phân loại là lớp chắn duy nhất.
* **`longVowelForms` là danh sách phải giữ đúng chiều.** Thêm `ai`/`oi`/`ui`/`au` vào đó là mất âm ở "senpai", "kaze", "kouhai". Ngược lại, bỏ `ou`/`ei` ra là quay về cảnh "arigatou" đọc thành "a-ri-ga-tô-**ư**".
* **Không có gate tự động nào bắt được hồi quy ở đây.** Bảng đọc romaji không có ràng buộc tĩnh nào (`check_architecture.py` chỉ đếm dòng; `validate_links.py` chỉ đối chiếu hash). Thước đo duy nhất là `TransliterationGoldenSet` chạy ở màn Thử phiên âm — đổi bảng mà không mở màn đó là đổi mù.

## Rủi ro mở rộng widget TTS từ Reader (1.3.277)

* **Rủi ro chính là đặt request ở sai tầng.** Nếu đưa vào `TTSManager.startSpeaking`, tầng Service sẽ biết widget UI và phá ranh giới kiến trúc. Bản này giữ request trong `ReaderView.startTTS(...)`, caller duy nhất của startSpeaking trong `Sources/`.
* **Không đổi default mode của widget.** Đổi `FloatingWidgetViewModel.init()` sang `.revealed` sẽ làm mọi lần tạo widget mở rộng, kể cả ngoài yêu cầu Reader. Bản này dùng cờ một lượt `shouldRevealOnNextShow` nên phạm vi đúng với hành động người dùng.
* **Auto-hide vẫn chạy.** "Mở rộng ban đầu" không có nghĩa là ghim mở rộng vô hạn; nếu muốn giữ mở lâu hơn thì phải là yêu cầu UI riêng, vì hiện tại nó dùng timer reveal 3 giây sẵn có.

## Rủi ro highlight chuẩn bị TTS (1.3.276)

* **Chưa biên dịch trên host hiện tại.** Thay đổi chạm chữ ký view (`ReaderTextView`, `ParagraphCardView`) và shape snapshot TTS, nên lỗi compiler còn có thể chỉ lộ trên macOS/CI. Windows không có `xcodebuild`; xác minh cục bộ chỉ là đọc code, `validate_links.py`, `check_architecture.py` và `git diff --check`.
* **Rủi ro hành vi chính là tô sớm nhưng không được commit sớm.** Nếu ai sau này dùng `preparingHighlightRange` như `highlightRange` active để lưu tiến độ/Now Playing/prefetch, bug ban đầu quay lại ở dạng mới: đoạn chưa nghe đã được coi là đã nghe. Bất biến: preparing chỉ là presentation state.
* **Dedupe snapshot là bẫy.** Không được thay `publishPreparingParagraphState` bằng publish active `highlightRange` sớm; khi audio thật bắt đầu, snapshot active có thể không đổi và `commitAudibleParagraphState` sẽ skip side effects.
* **Range chuẩn bị dùng cùng hệ toạ độ với active highlight.** Không thêm mapper; thêm mapper sẽ tái tạo nhóm lỗi đã xoá ở 1.3.81.

## Rủi ro của hai bộ rule, tắt-by-file, Check rule/Copy gốc và backup (1.3.274)

* **Chưa biên dịch — 17 file Swift mới nên bắt buộc `xcodegen generate` rồi mới build trên macOS/CI.** Viết trên Windows nên không build tại chỗ và chưa kiểm trên máy thật. `check_architecture.py` không chạy được ở đây; kiểm tra bằng mắt: 17 file mới đều ≤ 400 dòng (lớn nhất 383) và đúng 1 type top-level, không file Service nào `import SwiftUI` hay gọi `ToastManager.shared`. CI xanh chỉ chứng minh *biên dịch được*.
* **Rủi ro dữ liệu đáng kể nhất: khôi phục backup "chỉ thêm, không xoá" làm **sống lại lựa chọn cũ**.** Cả hai chiều khôi phục rule đều gộp chứ không ghi đè — hợp tập mẫu cho file tắt (`merge`), `importRules(.overwriteExisting)` cho bộ riêng (đè vế phải của mẫu trùng). Khôi phục từ bản sao lưu **cũ hơn** vì vậy có thể tắt lại một rule người dùng vừa bật, hoặc hồi phục nghĩa cũ của một mẫu đã sửa. Đây là đánh đổi có chủ ý (ghi đè sẽ xoá trắng các mẫu chỉ có ở máy đang phục hồi; bật lại một rule rẻ hơn nhập lại cả danh sách) nhưng là hành vi người dùng có thể ngạc nhiên khi restore bản cũ.
* **LRU cap 3 của `QuickTranslationRuleBookStore` không còn làm đổi handle xoá**: thao tác từ màn Check rule dùng `pattern`, không dùng UUID snapshot. Rủi ro còn lại là tên rule đã được sửa/xoá ở nơi khác trước khi người dùng bấm hành động; store sẽ tìm theo pattern hiện tại và trả lỗi nếu không còn key đó trong file canonical.
* **Panel Copy gốc không có nút Hủy — mọi đường đóng đều copy** (chốt chủ dự án). Rủi ro là quấy rối chứ không phải mất dữ liệu: vô tình đóng panel (kéo xuống, tap ra ngoài) là dính clipboard nội dung đoạn đang chọn, và không có cách nào "chưa copy". Đã giảm bằng cách đóng → `showingCopyOriginalSheet = false` trước khi đọc `originalSentence` (không bao giờ copy khi panel đã đóng vì lý do khác) và pasteboard chỉ chứa xâu gốc.
* **Hiệu năng màn Check rule là ca đắt nhất của tính năng rule**: `diagnose` chạy matcher trên **cả đoạn** với cả hai bộ và `includesDisabled: true` — tức mọi rule đang tắt/bị token tắt cũng được thử, đắt hơn lượt rewrite thật (rewrite loại ngay trước matcher). Với bộ 17.278 rule chi phí vẫn theo quy luật ứng viên/dòng (tỉ lệ với chữ, không tỉ lệ với số rule) nhưng gấp ~2 lần rewrite; không khuyến nghị mở màn này trên đoạn cực dài. Giảm thiểu hiện có: bộ riêng thường vài chục rule, và màn chỉ mở khi người dùng bôi đen (đoạn ngắn).
* **Một nguồn khai tên file riêng truyện là quy ước mới phải giữ**: thêm một file riêng truyện (ví dụ từ điển mới) mà khai tên ở nơi khác không phải `TranslationManager+BookScopedFiles.swift` thì file đó âm thầm không vào backup và không đi theo truyện khi đổi nguồn — đúng loại bug im lặng mà lượt này vừa dọn khỏi hai chỗ đã biết (BackupPaths + SearchView). Kiểm bằng grep khi thêm file mới.
* **Đổi nguồn truyện trong `SearchView` phải `invalidate` đủ 4 chỗ** (BookStore × {bookId cũ, mới} + DisableStore × {cũ, mới}) — bỏ sót một phía là truyện mới đọc phải nguồn mới nhưng vẫn thấy bộ rule/tập tắt của nguồn cũ. Đã làm đủ 4 lời gọi; đây là chỗ dễ sót nhất khi người khác sửa sau này, nên được ghi lại thay vì để tự suy ra.
* **Ô Thử nhanh và màn Check rule giờ phụ thuộc file tắt** — người dùng sửa rule ở màn quản lý mà bối rối "sao không khớp" có thể đang bị file tắt chặn; đã giảm bằng dòng chú thích trong UI và badge "ĐÃ TẮT" trên hàng. Đây là thay đổi hành vi có chủ ý (trước đây ô thử bỏ qua mọi thứ trừ công tắc tổng/token) — màn soi phải nói đúng kết quả đọc thật.

## Rule dịch Quick Translate: engine, màn hình quản lý và công tắc (1.3.269)

* **Rủi ro cao nhất không nằm ở engine mà ở chỗ engine im lặng làm sai.** Rule sinh chuỗi Việt, phần Hán không khớp đi tiếp bằng đường cũ, nên một rule tồi cho ra **câu Việt sai nghĩa mà không lộ chữ Hán** — không có dấu hiệu nào để người dùng biết. Ba lớp chắn: token từ điển phải khớp entry thật (không nuốt bừa 1-12 chữ Hán như reference), boundary guard có điều kiện cho `<n>/<y>`, và ô thử nhanh ở màn quản lý (`QuickTranslationRuleTesterView`) để soi "rule nào khớp ở offset nào" trước khi tin.
* **Chưa biên dịch, và không có test nào phủ engine.** Toàn bộ xác minh lượt này là (a) đọc code, (b) hai script gate Python, (c) một bản **mirror thuật toán bằng Python** (script tạm, đã xoá) chạy trên ba bộ rule thật. Mirror chứng minh *thuật toán* đúng trên dữ liệu thật (633 / 1.175 / 17.278 rule, các ví dụ biên `三百五十米`, `十五级`, `第一章卷`, `一万亿`, group lồng, escape, token optional) nhưng **không** chứng minh bản Swift biên dịch được. Việc đầu tiên khi lên macOS: `xcodegen generate` + `xcodebuild build`.
* **Bẫy layout đã trả giá bằng crash thật (1.3.269, 5 file `.ips` giống hệt nhau): không bọc lazy container trong một hàng `List`.** `List` của iOS 16+ chạy trên `UICollectionView` + `UICollectionViewCompositionalLayout`; `LazyVStack`/`LazyHStack` bên trong một cell làm layout tự vô hiệu ngay giữa lượt cập nhật cell ⇒ `-[UICollectionView _updateVisibleCellsNow:]` đệ quy 7 lần rồi trap `EXC_BREAKPOINT` ở `_assertionFailure` trong `CA::Transaction::commit`. Muốn chặn danh sách dài thì **cắt dữ liệu** (`prefix(visibleLimit)`), đừng đổi kiểu container. Không cổng tĩnh nào bắt được lỗi này — `check_architecture.py` và `validate_links.py` đều không biết gì về layout.

* **Cap backtracking là lưới an toàn, không phải bảo đảm.** `QuickTranslationRuleMatcher.stepCap = 4.000` cho mỗi cặp (rule, vị trí bắt đầu). Với dữ liệu hiện có cap không bao giờ chạm (pattern ≤ 8 phần tử, `max ≤ 12`), nhưng một rule bệnh lý nhập từ ngoài vẫn có thể làm chậm — khi đó rule bị coi là không khớp và dòng của nó hiện ở `status.complexRuleLines`. Nếu thấy dòng nào ở đó, đọc lại rule chứ đừng nâng cap.
* **Lệch có chủ ý so với plan, cần chủ dự án biết**: plan §17 #5 chọn "rule chạy **trước** formatter tiêu đề chương". Bản này giữ formatter (`translateChapterTitle`) làm chủ tiền tố `第<n><L>` và chỉ áp rule cho phần còn lại của tiêu đề, vì rule `第<n:1-6><L> = {1} {0}` cho "Chương 1 mở đầu" trong khi formatter cho "Chương 1: Mở đầu" (có dấu hai chấm, có bảng đơn vị `chapterUnitMap`) — đổi thứ tự là đổi mọi tiêu đề chương ở Kệ/Mục lục/Reader. Muốn theo plan thì chuyển lời gọi `rewrite` lên đầu `translateChapterTitle`; đây là một chỗ sửa.
* **`wildcardCapacity` của token từ điển không khai range dùng 12 (như reference) chứ không dùng "độ dài entry dài nhất của từ điển"** như plan §7.2 mô tả: `TrieDictionary` chỉ expose `wordCount`, không expose độ dài entry lớn nhất. Đây là metric **tiebreak ưu tiên**, không phải điều kiện khớp, nên ảnh hưởng chỉ là thứ tự chọn giữa hai rule cùng `index` và cùng `literalLength`.
* **Nguy cơ hiệu năng còn mở**: chưa đo trên máy thật với bộ 17.278 rule. Số ứng viên/dòng đo được (18,0) nói tập ứng viên không tỉ lệ với số rule, nhưng chi phí dựng `QuickTranslationLiteralIndex.candidates` vẫn là O(số ký tự × kích thước bucket) cho **mỗi** chuỗi dịch, và `QuickTranslationDictionaryToken.resolve` gọi `TranslationManager.getBookDictionaries` mỗi lượt rewrite. Cần đo trước khi khuyến nghị nạp bộ 17k.
* **Rule `<pn>` KHÔNG đi theo công tắc `isTranslationPronounsEnabled`** (quyết định chủ dự án, đổi so với plan §17 #5b). Công tắc đó điều khiển việc *tra từ điển đại từ cho từng token* ở tokenizer; còn `<pn>` trong rule là ràng buộc của một rule người dùng chủ động viết, để nó im lặng không nổ vì một công tắc ở màn khác là hành vi khó hiểu. Hệ quả: bộ `Rule_new.txt` (16.941 rule `<pn>`) chạy **ngay khi nạp**, miễn `Pronouns.dat`/`.txt` có trên máy — rủi ro chuyển từ "không chạy gì" thành "chạy 16.941 rule chồng lấn với 8 tầng từ điển", nên vẫn cần đọc thử vài chương thật trước khi bật bộ đó. Từ điển `Pronouns` là optional nên `pronounsDict == nil` vẫn cho `DICT_TOKEN_WITHOUT_DICTIONARY` (mức `disabling`, không chặn nạp file).

## Rủi ro của lời nhắc chưa-đăng-nhập và của số đếm truyện đã xoá (1.3.268)

* **Chưa biên dịch, chưa kiểm trên máy thật**: viết trên Windows, không có `xcodebuild` lẫn `xcodegen` — nhưng lượt này **không thêm file Swift nào** nên không cần `xcodegen generate`. `check_architecture.py` giữ đúng **14 violation** (tập y hệt), `validate_links.py` PASS. Không dùng `Tests/` làm bằng chứng. CI xanh chỉ chứng minh *biên dịch được*.
* **Rủi ro chính của lượt này là quấy rối, không phải mất dữ liệu**: toast mới ở `.skipped(.driveNotLinked)` bắn **mà không ai bấm gì**, 25 giây sau khi mở app, và `ToastManager.show` ghi mọi toast vào hộp thư thông báo ⇒ mỗi lời nhắc còn để lại một badge chưa đọc. Giảm thiểu: chỉ bắn khi người dùng đã **tự bật** tự động sao lưu, và cửa `linkWarningCooldown = 24 h` đè lên số lần mở app. Ca xấu nhất còn lại: cài đè app/xoá `UserDefaults` làm mốc nhắc mất ⇒ nhắc lại một lần. Chấp nhận.
* **`GoogleDriveConfiguration.isConfigured == false` vẫn im lặng có chủ ý** (trả `.skipped(.notDue)`): build không nhúng client id là chuyện của người build, người dùng bấm gì cũng không sửa được — nhắc chỉ gây nhiễu. Hệ quả cần biết: trên bản build thiếu key, bật tự động sao lưu là **hoàn toàn** không có phản hồi nào.
* **Mốc nhắc và mốc sao lưu là hai khoá riêng** — nếu ai đó "gộp cho gọn" bằng cách gọi `markRun()` ở nhánh chưa-đăng-nhập, lỗi sinh ra rất khó thấy: đăng nhập xong vẫn không có bản sao lưu nào cho tới hết cooldown. Ghi lại vì đây là chỗ dễ refactor sai.
* **`pruneIncomplete` chỉ hạ mức toast, không làm lượt thất bại**: bản vừa upload luôn còn nguyên, nên `.succeeded` là đúng. Nhưng hệ quả tích tụ vẫn thật — Drive có thể vượt `maxVersions` bản tự động nếu `listBackups()` hoặc `delete(fileId:)` lỗi nhiều lượt liền, và **không có** cơ chế dọn bù nào ngoài lượt kế tiếp.
* **Số đếm truyện đã xoá giờ đúng, nhưng con số trong Cài đặt vẫn là ước lượng**: hàng "Sẽ bị xoá nếu dọn ngay" đọc `previewStaleCount` ở thời điểm khác với lúc xoá, nên nó có thể lớn hơn số thật (TTS bắt đầu phát giữa hai mốc). Toast sau lượt xoá mới là số chốt. Trước 1.3.268, `staleIds.count` bị dùng làm số báo và có thể nói "đã xoá N truyện" khi thật ra xoá ít hơn — nay không còn.
* **Vẫn còn một khoảng im lặng đã biết, cố ý không sửa lượt này**: xoá file vật lý (`.bin`, ChapterStore, cover) chạy trong `Task.detached` fire-and-forget; thất bại chỉ vào `failed_file_deletions_queue` và `drainRetryQueue` bỏ hẳn sau 3 lần, **không** báo gì. Nghĩa là truyện có thể mất khỏi DB mà file vẫn chiếm chỗ, không ai biết. Muốn báo được thì phải thêm một kênh báo cáo ra khỏi task nền — thay đổi lớn hơn phạm vi lượt này, nên chỉ ghi nhận.

## Rủi ro của lượt tự xoá truyện, sentinel số chương và backup từ điển TTS (1.3.263)

* **Chưa biên dịch, chưa kiểm trên máy thật**: viết trên Windows, không có `xcodebuild` lẫn `xcodegen` — **bốn file Swift mới nên bắt buộc chạy `xcodegen generate` trên macOS/CI trước khi build**. `check_architecture.py` giữ đúng **14 violation** (tập y hệt), `validate_links.py` PASS. Không dùng `Tests/` làm bằng chứng. CI xanh chỉ chứng minh *biên dịch được*.
* **Rủi ro nặng nhất của lượt này: xoá truyện là không hoàn tác được.** Không có thùng rác, không có tombstone — `BookStorageManager` xoá bản ghi DB, file `books/<sha>.bin`, mục lục trong `chapter_store.sqlite` và ảnh bìa. Bốn chốt độc lập chặn xoá oan: cờ bật/tắt **mặc định tắt** (khác hai policy nền kia, nên nâng cấp app không tự bật); truyện `isLocalBook` **luôn** được loại (không tải lại được từ mạng); truyện đang phát TTS / đang có widget nổi và truyện có task tải `.pending`/`.running` bị loại qua `protectedBookIds()`; và mốc so sánh là `Book.lastReadDate` chứ không phải ngày thêm vào tủ.
* **Chốt yếu nhất còn lại: `lastReadDate` của truyện chưa từng mở.** Nếu một truyện được thêm vào tủ mà chưa đọc dòng nào và `lastReadDate` mang ngày thêm (hoặc mốc rất cũ), nó **sẽ** bị coi là bỏ quên sau đúng ngưỡng ngày. Người dùng "tích truyện để dành" là ca gặp thật. Giảm thiểu hiện có: mặc định tắt, ngưỡng kẹp `7...365` ngày, số truyện sẽ bị xoá hiện ngay trong Cài đặt khi kéo thanh trượt, và `confirmationDialog` cho lượt bấm tay. Đây là điểm dừng thiết kế được báo lại, **không** tự thêm whitelist.
* **`markRun()` chạy trước phần việc** nên một lượt chết giữa đường (app bị kill, `deleteBooksAsync` throw) vẫn tiêu nhịp của ngày đó. Hướng lệch là "xoá ít hơn dự kiến" — cố ý, vì lệch ngược lại (xoá hai lượt liền) tệ hơn nhiều.
* **Thứ tự 25 s (sao lưu) trước 40 s (dọn) là giảm thiểu chứ không phải bảo đảm**: hai `.task` chạy song song, nên nếu lượt sao lưu kéo dài quá 15 giây thì việc xoá có thể bắt đầu khi bản sao lưu **chưa xong**. Truyện bị xoá lúc đó có thể thiếu trong archive của lượt ấy. Chấp nhận vì lượt sao lưu kế tiếp sẽ phản ánh đúng trạng thái, và truyện bị xoá vốn là truyện người dùng đã đồng ý bỏ.
* **`ChapterLimitOption` từ enum sang struct: mất tính vét cạn của `switch`.** Trước đây thêm case là compiler bắt mọi `switch`; giờ `rawValue` nhận **mọi** `Int` nên giá trị lạ trong DB không còn bị bắt lúc biên dịch. Bù lại: `limitValue` là cửa ra duy nhất và coi mọi `rawValue <= 0` là "không giới hạn", nên `-1` (sentinel `.custom`) hay số âm rác đều suy về hành vi `.all` an toàn. Đã kiểm bằng đọc: `-1` không bao giờ vào `enqueueTask` vì `startTask()` quy đổi trước, và `DownloadManager+TaskStore` bỏ được `?? .all` vì init không thất bại.
* **Từ điển phiên âm TTS phục hồi theo kiểu trộn, không ghi đè** (`mergeStringPlist`, `mergeReplacementRules`), nên **không có tombstone**: một mục người dùng đã xoá trên máy A sẽ **sống lại** sau khi khôi phục từ bản sao lưu cũ. Cùng hạn chế đã biết của các từ điển plist/JSON khác. Chọn trộn vì mất mục do ghi đè tệ hơn.
* **Ước tính dung lượng nhóm `.content` báo thiếu**: khi người dùng tắt `.content`, nội dung truyện local vẫn được sao lưu nhưng `BackupSizeEstimator` không có cách rẻ nào biết truyện nào là local (tên file là `sha256(bookId)`, phải mở SwiftData mới biết) nên con số hiện ra nhỏ hơn archive thật. `manifest.scopes` cũng không ghi `.content` trong ca này — khôi phục vẫn đúng vì `BackupRestoreWorker` quyết định theo `book.isLocalBook`, không theo scope. Hạn chế được ghi nhận, không sửa.


## Rủi ro của lượt dọn kho tiện ích, đầu dò cuộn và vệt tô tìm kiếm (1.3.261)

* **Chưa biên dịch, chưa kiểm trên máy thật**: viết trên Windows, không có `xcodebuild` lẫn `xcodegen` — **hai file Swift mới nên bắt buộc chạy `xcodegen generate` trên macOS/CI trước khi build**. `check_architecture.py` giữ đúng **14 violation** (tập y hệt), `validate_links.py` PASS. Không dùng `Tests/` làm bằng chứng. CI xanh chỉ chứng minh *biên dịch được*.
* **Rủi ro nặng nhất: lượt dọn xoá oan bản ghi tiện ích** — một lần fetch registry lỗi (mạng trả file trắng, kho đổi cấu trúc `plugin.json`) mà vẫn được coi là "kho đã gỡ hết" sẽ quét sạch danh sách của kho đó. Ba chốt độc lập chặn việc này: `syncExtensions` thoát sớm khi `items.isEmpty`; `pruneRepositoryExtensions` trả `.success(0)` khi `keepPackageIds` rỗng; và prune **chỉ** chạy khi upsert trả `.success`. Chốt yếu nhất còn lại: registry trả về **một phần** (ví dụ 3/40 `plugin.json` tải được) thì 37 bản ghi chưa cài **sẽ** bị xoá. Đánh đổi cố ý — bản ghi chưa cài chỉ là dòng danh sách, đồng bộ lại là có lại; nhưng nếu người dùng báo "tiện ích trong kho tự biến mất" thì đây là chỗ phải xem trước.
* **Tiện ích đã cài không bao giờ bị xoá** (`localPath` khác rỗng bị loại ở bộ lọc), nên không có đường nào làm truyện trong tủ mất nguồn. Rủi ro ngược lại là **rác**: tiện ích đã cài mà kho đã gỡ vẫn nằm trong danh sách mãi, không có dấu hiệu nào cho người dùng biết nó đã bị tác giả kho bỏ. Đây là điểm dừng thiết kế được báo lại, không tự cài.
* **Đầu dò cuộn có thể tắt cuộn-theo-highlight ngoài ý muốn** nếu recognizer nổ vì một cú kéo không phải "cuộn đọc" — nới vùng bôi đen là ca thật, đã chặn bằng `guard !showingFloatingMenu`. Ba guard còn lại (`!isAutoScrollDisabled`, `isTTSPlayingThisBook`, `!isRestoringReaderPosition`) chặn các ca máy-cuộn. Cờ chỉ có phạm vi phiên và bật lại được bằng một lần bấm ở header, nên hậu quả tệ nhất là một lần bấm — không mất dữ liệu.
* **Chiều rủi ro ngược của đầu dò: recognizer rò.** `UIScrollView` giữ recognizer strong và sống lâu hơn subtree chương, nên nếu `dismantleUIView` không chạy thì mỗi lần đổi chương để lại một recognizer chết. Giảm thiểu: `attach(to:)` idempotent theo identity + tự `detach()` trước khi gắn mới, cộng `deinit` làm lưới cuối. Chưa xác nhận bằng Instruments — chỉ bằng đọc code.
* **Vệt tô tìm kiếm có thể không hiện** khi chuỗi hiển thị không chứa truy vấn (bật/tắt dịch giữa lúc nhảy tới kết quả, hoặc `translated` chưa dựng xong). Đây là **chế độ suy giảm có chủ ý**: `searchHighlightRange(...)` trả `nil` và trang vẫn nhảy đúng đoạn. Rủi ro đã tránh được là nghiêm trọng hơn nhiều — cache `NSRange` vào state sẽ tô sai ký tự thay vì không tô.


## Rủi ro của bốn bộ ghi định dạng nhị phân (1.3.253)

* **Chưa biên dịch, chưa kiểm trên máy thật**: viết trên Windows, không có `xcodebuild` lẫn `xcodegen`. `check_architecture.py` giữ đúng **14 violation** (tập y hệt), `validate_links.py` PASS. Không dùng `Tests/` làm bằng chứng. CI xanh chỉ chứng minh *biên dịch được* — **không** chứng minh 3 file nhị phân mở được trên máy đọc thật.
* **Rủi ro cao nhất: MOBI.** Đây là format duy nhất trong đợt này phải tự dựng header nhị phân với offset tuyệt đối. Ba điểm dễ vỡ: (1) tổng độ dài MOBI header phải đúng **232 byte** — lệch một byte là `fullNameOffset = 16 + 232 + exth.count` trỏ sai và máy đọc hiện tên rác; (2) `filepos` của mục lục MOBI6 là **offset byte tuyệt đối trong toàn văn**, được đặt bằng chỗ trống 10 chữ số rồi vá tại chỗ khi copy — nếu độ dài chuỗi vá khác 10 thì mọi `filepos` sau nó lệch; (3) record cuối có thể ngắn hơn 4096 byte và `recordCount` (UInt16) chỉ tới 65535 nên sách > ~268 MB text bị `throw .sizeLimitExceeded` thay vì tạo file hỏng. Số học byte đã được kiểm tay, **chưa** được máy đọc nào xác nhận. Ghi **không nén** (`compression = 1`) là chọn có chủ ý: file to hơn nhưng bỏ được cả lớp lỗi LZ77/trailing-entry.
* **EPUB: ZIP tự viết là bề mặt rủi ro thứ hai.** `ZipStoreWriter` chỉ hỗ trợ stored (method 0) và **không** ZIP64 ⇒ vượt `UInt32.max` thì `throw .archiveTooLarge`. Ba chỗ phải khớp nhau tuyệt đối: CRC-32 mỗi entry, `localHeaderOffset` trong central directory, và số entry trong EOCD. Sai bất kỳ chỗ nào cho ra file mà một số máy đọc mở được và một số thì không — dạng lỗi khó chẩn đoán nhất, và không có test tự động nào (theo yêu cầu) để chặn.
* **Chính sách "xuất những gì có" là đổi hành vi có chủ ý, có thể gây bất ngờ.** Trước đây một chương lỗi là bỏ cả bản xuất; nay > 0 chương ⇒ `.completed` + dòng tổng kết `"Đã xuất X/Y chương (thiếu M, lỗi F)"`. Rủi ro: người dùng bỏ qua dòng cam và tưởng file đủ chương. Giảm thiểu: dòng tổng kết hiện **cả** trên tracker **và** trong toast, và bản xuất đủ chương thì không có dòng nào (nên sự xuất hiện của nó tự mang nghĩa cảnh báo).
* **`.exportReady` có thể tới lúc app ở background** ⇒ share sheet không trình bày được. Giảm thiểu: giữ pending + flush ở `scenePhase == .active`. Rủi ro còn lại: chỉ giữ **một** yêu cầu, nên hai bản xuất xong liên tiếp trong lúc app ở background thì chỉ bản sau được mở share sheet — file bản trước **không mất**, vẫn chia sẻ lại được từ tracker.
* **Không đổi schema là để tránh rủi ro lớn hơn.** Định dạng bền hoá bằng raw value mới của `TaskType` trong cột `taskTypeRaw` sẵn có. Đánh đổi đã biết: `exportStage`/`exportSummary` **mất** khi app khởi động lại (chỉ ở RAM) — tác vụ đã hoàn thành vẫn giữ `exportFilePath` nên nút chia sẻ lại còn hoạt động, chỉ dòng tổng kết thiếu chương là không còn. Thêm field cho việc này là **điểm dừng thiết kế được báo lại**, không tự cài, vì app không có `VersionedSchema`/`SchemaMigrationPlan` — chỉ lightweight migration ngầm.
* **Rác đĩa**: `.part` của mọi định dạng và file text tạm của MOBI. Cả hai có đường dọn tường minh (`discard()` ở mọi nhánh thoát, `defer` cho file tạm MOBI), và `ExportStagingFile.init` xoá `.part` sót lại trước khi tạo mới. Trường hợp bị kill giữa tác vụ: còn `.part`, **không bao giờ** còn một file ebook dở dang trông như hợp lệ.

## Rủi ro sau khi tối ưu xuất TXT, mục lục và từ điển (1.3.250)

* **Chưa biên dịch, chưa xác nhận runtime**: viết trên Windows, không có `xcodebuild` và không có `xcodegen`. `check_architecture.py` **16 → 14 violation** (tập con thật sự), `validate_links.py` PASS. Không dùng `Tests/` làm bằng chứng. CI xanh chỉ chứng minh *biên dịch được*.
* **Rủi ro nặng nhất: diff mục lục kết luận sai chiều "không đổi"** ⇒ chương mới không được lưu, người dùng mất chương. `ChapterTOCDiff.plan` vì vậy viết theo hướng bảo thủ: `incoming.count < existing.count` ⇒ `.full`; lệch bất kỳ field nào trong `(index, url, title, host)` ⇒ `.full`; `titleTrans` mới khác rỗng mà khác bản đang lưu ⇒ `.full`. Chỉ khi **mọi** hàng đầu trùng khớp mới trả `.unchanged`/`.appendOnly`. Hệ quả cần biết: nguồn đổi tiêu đề chương thành **chuỗi rỗng** hoặc `titleTrans` bị **xoá** ở phía online sẽ không được coi là thay đổi — đánh đổi cố ý, vì coi mất-dữ-liệu-phía-nguồn là thay đổi sẽ làm mọi lần refresh ghi lại toàn bộ.
* **Chương TTS được bảo vệ**: nếu `protectedTTS.bookId` khớp truyện đang lưu mà TOC mới không chứa chương đó (so theo `index` và `url` khi `url` khác rỗng), `plan` ép `.full` để đường xoá stale cũ chạy đúng logic bảo vệ sẵn có. Không có nhánh nào trong `.unchanged`/`.appendOnly` xoá hàng, nên chương đang phát không thể bị xoá ở hai nhánh đó.
* **Nhánh `.unchanged` không bump `updatedAt`** của hàng mục lục. Cột này chỉ được backup export/restore đọc, không ảnh hưởng đọc truyện — nhưng nghĩa là "lần cuối kiểm tra mục lục" không còn được ghi khi không có gì đổi.
* **Bỏ `fetchOrderedTOC` lần hai làm mất một lớp tự kiểm tra sau ghi.** `countChapters(bookId:)` giữ lại phần quan trọng nhất (đúng số hàng, O(1)) nhưng không còn đối chiếu từng field sau transaction. Checksum xác định (`computeDeterministicChecksum`) bị xoá hẳn: nó băm cả `id`/`isCached`/`offset`/`length` nên chưa bao giờ dùng lại được để so với TOC online, và không caller nào ngoài chính hàm đó đọc.
* **Coalesce `save()` của task**: nếu app bị kill giữa một tác vụ, `progressCount` trong DB lùi lại tối đa một cửa sổ coalesce. Không đổi hành vi resume/retry — `initialize(container:)` vẫn đánh mọi task `running`/`pending` thành `failed` khi khởi động lại. Throttle `@Published tasks` ~10 lần/giây làm counter nhảy bậc; giá trị cuối, bước đầu và mọi thay đổi trạng thái luôn được phát.
* **Ghi dần file TXT**: rủi ro để lại file dở trong `Documents/Exports/` nếu một nhánh lỗi nào bị bỏ sót. Giảm thiểu bằng cách chỉ ghi `<tên>.txt.part` và chỉ rename ở `finish()`, cộng `discard()` ở mọi nhánh huỷ/lỗi — trường hợp xấu nhất là còn một `.part`, không phải một `.txt` rỗng mà người dùng tưởng là bản xuất hợp lệ.
* **Bỏ hop MainActor kiểm cancel** chỉ đúng vì `activeTasks[taskId]` được gán ngay sau `Task.detached` và mọi đường huỷ đều gọi `handle.cancel()` trên MainActor ⇒ `Task.isCancelled` là đủ. Đây là **lệch có chủ ý so với plan**: plan dự tính đọc thêm một snapshot `Set<UUID>` của `cancelledTaskIds`, nhưng đọc `Set` đó từ task nền là truy cập không đồng bộ hoá — thêm rủi ro race để đổi lấy một tín hiệu đã có sẵn.
* **`BookBinManager` được cache đường dẫn thay vì mở sẵn handle** — cũng là lệch có chủ ý: một handle mang `FileHandle` không `Sendable` nên không đi qua ranh giới actor được. Cache `resolvedBinURLs` cho đúng phần tiết kiệm (một `sha256Hex` + một `validatePathSafety` + một kiểm migrate legacy cho mỗi truyện mỗi phiên) và có lợi cho **mọi** caller. Rủi ro: nếu file `.bin` bị xoá ngoài `deleteBinFile` thì cache giữ URL cũ — hiện `BookStorageManager` là điều phối viên duy nhất và nó đi qua `deleteBinFile`.
* **Bỏ `loadAllDictionaries()` khỏi đường sửa một từ**: an toàn vì `saveCustomEntry`/`deleteCustomEntry` chỉ ghi file TXT custom, không đụng `.dat`. Nhưng nếu sau này có thao tác nào **vừa** sửa custom TXT **vừa** thay `.dat` thì nó phải tự gọi `loadAllDictionaries()` — `reloadCustomDictionary` cố ý không chạm `.dat` lẫn `phienAmMap`. Race sẵn có không đổi: `TranslationManager` là `final class ObservableObject` thường và các dict bị ghi từ context ngoài main; bỏ reload dư **thu nhỏ** cửa sổ race chứ không mở rộng, và không sửa gốc trong phạm vi này.
* **Bỏ lần dịch lại tức thời ở `saveDefinition`** làm bản dịch cập nhật muộn hơn ~150 ms (debounce). Nếu một đường nào làm deferral bị kẹt thì chương sẽ **không** đổi — đã kiểm mọi cờ overlay đều có `onChange(false)` gọi `checkAndReleaseDeferredTranslationRefresh`, và `saveDefinition` cũng tự gọi ở cuối. Dấu hiệu hồi quy khi kiểm máy thật: `[ReaderPerf] TranslationRefresh … outcome=completed` phải xuất hiện **đúng một** lần cho mỗi lần bấm "Cập nhật".
* **`suggestionChips` thành `@State`** ⇒ phải được làm mới theo cả `bookId` và chuỗi chọn, nếu không sẽ hiện gợi ý của từ trước. Mọi điểm ghi đều truyền từ hiện tại và ghi đè toàn bộ mảng.
* **Tách file bằng `sed` là thao tác cơ học, không có bộ dịch để chặn lỗi**: `ShelfView+TXTImport.swift` được cắt nguyên khối rồi kiểm đối xứng dấu ngoặc so với `HEAD` (tổng của hai file bằng đúng của file gốc). Bốn hàm được gọi từ `ShelfView.swift` đã nâng lên `internal` vì `private` trong Swift là file-scoped — đây là loại lỗi mà chỉ bộ dịch mới bắt chắc chắn, nên CI là mắt kiểm tra thật sự.

## Rủi ro sau khi sửa mở thu nhỏ, nháy đỏ và tap mở lại (1.3.245)

* **Chưa biên dịch, chưa xác nhận runtime**: viết trên Windows, không có `xcodebuild`. `check_architecture.py` giữ đúng **18 violation** cũ, `validate_links.py` PASS. Không dùng `Tests/` làm bằng chứng.
* **Nguyên nhân lỗi "bấm widget thì widget mất mà trình duyệt không mở" chỉ được chẩn đoán bằng đọc code, và có nhiều hơn một nghi phạm.** Triệu chứng chỉ xảy ra được khi `isHidden` đã bị đặt `false` (widget hết điều kiện hiển thị) mà sheet không xuất hiện. Hai đường có thể dẫn tới đó đều đã bị bịt: (a) `findTopViewController()` nhặt window overlay của chính widget (`alert - 2`) hoặc của TTS (`alert - 1`) rồi present sheet vào đó, để `notifyStateChanged()` ngay sau đó ẩn window ⇒ nay chỉ nhận window `windowLevel == .normal`, ưu tiên window `isKeyWindow`; (b) `container` còn mắc parent là một `UINavigationController` bị bỏ dở nên nav mới không bọc lại được ⇒ `navigationController(wrapping:)` tái dùng nav cũ hoặc `removeFromParent()` trước khi bọc. Nếu trên máy thật vẫn còn lỗi thì nguyên nhân là đường thứ ba chưa biết — khi đó `verifyReopenPresented` đảm bảo người dùng vẫn còn widget để bấm lại, tức lỗi thoái hoá thành "bấm không ăn" thay vì "mất hết".
* **Lưới an toàn 1.2 s là hẹn giờ dựa trên thời gian, không phải tín hiệu UIKit**: nếu một ngày present pageSheet chậm hơn 1.2 s *và* `presentingViewController` chưa được gán (hiện UIKit gán ngay lúc gọi `present`, nên chưa có kịch bản nào như vậy), rollback sẽ ẩn oan trình duyệt vừa mở. Guard `self.navController === nav` chặn được trường hợp trạng thái đã đổi, không chặn được trường hợp giả định này.
* **`findTopViewController()` nay có thể trả `nil` ở nhiều tình huống hơn trước**: nếu scene không có window level `.normal` nào (chưa gặp — kể cả khi chạy qua LiveContainer, window chủ của app ở `.normal`), tap widget sẽ **không làm gì** thay vì present sai chỗ. Fallback cuối vẫn quét window `.normal` đang `isHidden` để không đóng cứng đường mở. Đây là đánh đổi cố ý: thà không mở còn hơn present vào window sẽ bị ẩn.
* **Khi cài đặt bật, tab nạp trong khi container chưa bao giờ được present.** Trước 1.3.245 lỗi bug-1 vô tình khiến container luôn được present, nên đường "webview off-window" chưa từng chạy thật. `webView.load` không cần window, nhưng WKWebView ngoài window có thể bị hệ thống điều tiết timer/JS, và các trang cần tương tác (captcha, Cloudflare) chỉ giải được sau khi người dùng bấm widget để mở lại. **Chưa xác minh runtime** — nếu extension nào phụ thuộc bypass tự động thì nên để cài đặt này **tắt** (mặc định vẫn tắt).
* **Đường lập trình không còn tự bung trình duyệt khi cài đặt bật**: extension gọi `load` lần thứ n trên loader đã có tab sẽ chỉ đổi tab đang hoạt động. Nếu extension nào dựa vào việc trình duyệt tự hiện lên để người dùng thao tác, hành vi đó nay biến mất — có ý (đúng đặc tả cài đặt), nhưng là thay đổi hành vi thật đối với extension.
* **Nháy đỏ đổi ngữ nghĩa thị giác**: viên pill nay đỏ đặc (alpha 1) khi có tab mở ≥ 10 s. Không còn dùng `opacity` nên `hitTest`/alpha của view container không đổi theo nhịp nháy; đổi lại màu đỏ dễ bị hiểu là "lỗi" chứ không phải "đang chạy". Đây là yêu cầu tường minh của người dùng.
* Các rủi ro của 1.3.244 còn nguyên hiệu lực, trừ mục nói nhịp nháy dùng `opacity`.

## Rủi ro của copy từ điển và widget trình duyệt kéo được (1.3.244)

* **Chưa biên dịch**: viết trên Windows, không có `xcodebuild`. Hai cổng tĩnh giữ nguyên (`check_architecture.py`: đúng 18 violation cũ; `validate_links.py`: PASS). CI xanh chỉ chứng minh *biên dịch được*. Không dùng `Tests/` làm bằng chứng cho bất cứ điều gì ở đây.
* **Copy là ghi đè trọn giá trị, không có undo**: `upsertEntry`/`saveCustomEntry` xoá key cũ rồi chèn key mới ở đầu file. Người dùng copy sai chiều sẽ **mất giá trị custom cũ ở đích** mà không có bước xác nhận nào (Menu chọn đích rồi thực thi ngay). Đây là hành vi được yêu cầu tường minh, nhưng nó là rủi ro dữ liệu thật — nếu sau này thêm cảnh báo thì đặt ở `DictionaryListView+Transfer.swift`, đừng đổi hai API ghi (chúng còn phục vụ đường thêm/sửa của `DictionaryListView`).
* **Ngữ cảnh sách phụ thuộc đúng một điểm truyền tham số**: `DictionaryHubView` là nơi duy nhất truyền `contextBookId`. Dựng `DictionaryListView(type:bookId: nil)` ở một call site mới mà quên `contextBookId` sẽ khiến icon chuyển ở danh sách chung im lặng chuyển sang trạng thái "không xác định được sách" (toast lỗi, không copy). Đó là fail-safe đúng hướng, nhưng là mắt yếu nhất của tính năng — hiện `DictionaryHubView` và `BookDictionaryView` vẫn là hai call site duy nhất.
* **Trình duyệt mở thu nhỏ ⇒ tab tải trong khi người dùng có thể không biết**: nhánh `prepareContainerMinimized()` attach `WKWebView` và bắt đầu tải mà không present. Rủi ro là dữ liệu/nền tiêu thụ mà không có UI đang hiển thị. Nút "N tab" và nhịp nháy là tín hiệu duy nhất; nếu tab đó cần tương tác (captcha, Cloudflare) người dùng phải tự mở lại. Cân nhắc nếu sau này bật cài đặt này làm mặc định — hiện mặc định là **tắt**.
* **Hai `UIWindow` overlay cùng lúc**: TTS widget ở `alert - 1`, trình duyệt ở `alert - 2`. Chỗ hai viên pill chồng nhau, TTS thắng hit-testing. Cả hai `hitTest` đều trả `nil` ngoài viên pill nên app bên dưới không bị chặn — nhưng đây là bất biến **phải giữ**: bất kỳ thay đổi nào làm `hitTest` trả `super.hitTest` cho toàn bộ bounds sẽ khoá cả app. `BrowserFloatingWidgetUIWindow` cố ý **không** có nhánh `presentedViewController != nil` như TTS (widget này không present gì); thêm `present` từ window đó về sau mà không thêm nhánh ấy là bug chờ sẵn.
* **Nhịp nháy dựa vào `createdAt` chứ không phải "tab chưa xem"**: một tab mở 30 s rồi thu nhỏ sẽ nháy ngay lúc thu nhỏ. Đúng đặc tả ("tính lại từ tuổi thật"), nhưng có thể gây cảm giác nháy dai nếu người dùng thu nhỏ/mở rộng liên tục — không có trạng thái "đã xem, thôi nháy".
* **`Timer.scheduledTimer` không chạy khi app ở background**: nếu ngưỡng 10 s trôi qua trong lúc app nền, timer nổ trễ khi run loop hoạt động lại. Chấp nhận được cho một hiệu ứng thị giác, nhưng đừng dùng monitor này cho việc gì cần độ chính xác thời gian.
* **`Views/Common/SizeReader.swift` nay là code chết** (consumer duy nhất là viên pill SwiftUI cũ). Giữ lại vì xoá nằm ngoài phạm vi yêu cầu; nó là ứng viên dọn ở lần sau.
* **Chưa xác nhận trên máy thật**: 16 test case người dùng nêu (4 tổ hợp mỗi chiều copy, chuỗi bật/tắt cài đặt thu nhỏ, ngưỡng nháy, kéo/snap/tap/passthrough, không hồi quy TTS widget) chỉ được kiểm bằng **đọc code**, không bằng chạy máy. Đặc biệt chưa xác nhận được bằng mắt: thứ tự z của hai window khi cả hai widget hiển thị cùng lúc, và cảm giác trễ khi kéo.

## Rủi ro của việc trả lại quan sát view model cho Reader (1.3.243)

* **Chưa biên dịch**: viết trên Windows, không có `xcodebuild`. Hai cổng tĩnh giữ nguyên (`check_architecture.py`: đúng 18 violation cũ, `ReaderView.swift` 2263 → 2268 vẫn là violation cũ; `validate_links.py`: PASS). CI xanh chỉ chứng minh *biên dịch được*.
* **Tăng số update pass của một view 2268 dòng**: từ nay **mọi** `@Published` của `ReaderViewModel` đều invalidate `ReaderView`, kể cả `currentProgress` (ghi mỗi 0.2 s khi cuộn) và `currentRevision`. Trước đây phần lớn thay đổi này im lặng — con số `updateUIView=151`/`contentSizeInvalidation=252` trong `[ReaderEnergy] Summary` gần như chắc chắn sẽ tăng. Đây là đánh đổi có chủ ý: lọc theo danh sách `@Published` là đúng loại bug vừa sửa (thêm state mới mà quên khai). Nếu cuộn bị giật sau thay đổi này, hướng xử lý là giảm nhịp ghi `currentProgress`, **không** phải bỏ relay.
* **Nguy cơ vòng lặp invalidate**: relay chỉ forward `objectWillChange`, không đọc/ghi state của view. Nếu ai đó ghi `@Published` của view model **trong** body hoặc trong `updateUIView` thì sẽ thành vòng lặp — trước 1.3.243 việc đó im lặng vô hại, nay thành vòng lặp thật. Không có điểm ghi nào như vậy hiện tại.
* **`observe(_:)` phải được gọi lại nếu `viewModel` bị dựng lại**: hiện chỉ có đúng một điểm gán (`ensureViewModel`), và relay so identity nên gọi lặp là vô hại. Thêm điểm gán `viewModel = …` ở nơi khác mà quên gọi `observe(_:)` là tái tạo lại đúng bug này — đây là mắt yếu nhất.
* **Chưa xác nhận trên máy thật**: giả thuyết được suy ra từ đường code cộng log thiết bị 2026-08-22 (khoảng lặng 0.6–4.3 s không có dòng log nào của Reader, trong khi TTS vẫn log và app vẫn nhận tap — tức main thread *không* bị chiếm). Cần một lượt log mới để chốt.
* **Chưa xử lý**: `prediction=reader_layout_churn_likely` và chi phí thật của một pass dựng subtree chương (`RepoLoad origin=extensionFetch ms=5051.59` là đường mạng, khác chuyện này).

## Rủi ro của cổng bắt tay skeleton (1.3.242)

* **Chưa biên dịch**: viết trên Windows, không có `xcodebuild`. Hai cổng tĩnh giữ nguyên (`check_architecture.py`: đúng 18 violation cũ; `validate_links.py`: PASS). CI xanh chỉ chứng minh *biên dịch được*.
* **Nguy cơ treo cổng nếu `onAppear` của skeleton không nổ**: cổng chỉ mở khi `skeletonHandshakeIndex == N`. Nếu skeleton đang hiển thị mà người dùng bấm tiếp sang chương khác, SwiftUI sẽ **không** chạy lại `onAppear` cho cùng một view — vì vậy nhánh skeleton mang `.id("chapter-skeleton-\(presentationIndex)")` để đổi chương là đổi identity. Đây là mắt yếu nhất của thiết kế: bỏ `.id` đó là mở lại đường treo ở chương cũ.
* **Thêm một frame trễ**: mỗi lượt đổi chương nay tốn thêm đúng một update pass (~16 ms) cho skeleton, cộng với nhịp 32 ms sẵn có. Đánh đổi có chủ ý: đổi tổng thời gian dài hơn một chút để lấy phản hồi tức thì.
* **Chỉ chữa cảm giác đơ, không chữa nguyên nhân của pass gộp**: chưa xác định được vì sao một pass vừa tháo vừa dựng hai subtree TextKit-1 lại tốn 1.6–3.5 s (giả thuyết: hai cây `UITextView` cùng sống trong một transition `.opacity` bọc bởi `withAnimation(.easeOut(0.12))`, cùng `contentSizeInvalidation=174`/`sizeInvalidationRPM=498.6` trong `[ReaderEnergy] Summary`). 1.3.242 chỉ bảo đảm pass gộp đó không còn xảy ra. `prediction=reader_layout_churn_likely` vẫn đúng và vẫn chưa xử lý.
* **Không đụng prefetch khi TTS sở hữu sách**: `setSpeculativePrefetchEnabled(false)` vẫn tắt N+1 của Reader, nên lượt tải lạnh thật (log có `RepoLoad origin=extensionFetch ms=2041`) vẫn dài như trước — chỉ khác là có skeleton suốt thời gian đó.

## Rủi ro còn lại sau lần sửa hạ cánh hai pha (1.3.241)

* **Chưa biên dịch**: thay đổi 1.3.241 viết trên Windows, không có `xcodebuild`. Chỉ hai cổng tĩnh chạy được (`check_architecture.py` giữ đúng 18 violation cũ, `validate_links.py`). CI xanh cũng chỉ chứng minh *biên dịch được*.
* **Giả định về timer 0.15 s**: pha hai (cuộn tới đoạn TTS) dựa vào việc `DispatchQueue.main.asyncAfter` không thể nổ khi main thread còn bận, nên nó luôn chạy *sau* khi chương đã present. Nếu một lượt dựng chương nào đó dài hơn và `onAppear` chưa kịp tiêu thụ target đầu chương, target sâu sẽ ghi đè và neo sâu lại được giải trong cùng layout pass — đúng hành vi cũ, không tệ hơn, nhưng cũng không được lợi.
* **Cửa sổ nhả cờ chồng nhau**: cú cuộn pha một hẹn nhả `isRestoringReaderPosition` sau 0.25 s, pha hai đặt lại cờ ở 0.15 s rồi hẹn nhả tiếp. Có ~0.1 s cờ bị nhả sớm giữa hai cú cuộn; hệ quả xấu nhất là một tick auto-scroll TTS trỏ đúng vào đoạn đang được cuộn tới, tức vô hại.
* **Chi phí cố định 32 ms/lượt điều hướng** (nhịp chờ frame) — đánh đổi lấy việc skeleton chắc chắn được present.
* **Không sửa nguyên nhân thời gian tải thật**: khi TTS sở hữu sách, `setSpeculativePrefetchEnabled(false)` tắt prefetch N+1 của Reader, nên Next/Prev lúc đang phát gần như luôn đi đường worker qua `ChapterContentRepository` (actor dùng chung với TTS). 1.3.241 làm chờ đợi đó *có phản hồi* (skeleton), **không** làm nó ngắn hơn. Nới điều kiện prefetch khi đang phát là quyết định năng lượng, chưa làm.

## Rủi ro của lần sửa đơ Next/Prev khi TTS đang phát (1.3.240)

* **Đã sửa, là bug thật chứ không phải tối ưu**: `restoreReaderPositionIfNeeded` thoát sớm mà không nhả `isRestoringReaderPosition`, khiến auto-scroll TTS và lưu tiến độ theo cuộn có thể chết im lặng tới hết session. Dạng lỗi không log, không crash, chỉ "tự nhiên không chạy nữa".
* **Rủi ro mới, mức thấp**: nay có thêm một frame skeleton chen giữa mọi lượt Next/Prev, kể cả khi nội dung đã ở RAM. Khi người dùng bấm rất nhanh, mỗi cú bấm huỷ `memoryCommitTask` trước đó nên chỉ chương cuối được commit — hành vi này dựa vào guard `request.generation == navigationGeneration`; sai guard là quay lại cảnh commit chồng.
* **Rủi ro còn nguyên, chỉ được đo chứ chưa sửa**: `ChapterContentRepository.shared` là một actor dùng chung giữa Reader và TTS, nên khi chương đích chưa cache, `load` của Reader có thể xếp hàng sau một lượt fetch chương của TTS. Log `[ReaderPerf] RepoLoad` thêm vào để lượng hoá đúng đường này; đường đó **có** skeleton nên nó không phải triệu chứng đang báo.
* **Không đo được tại chỗ**: host là Windows, `xcodebuild` chỉ chạy trên macOS. Mọi kết luận ở trên là đọc code cộng `check_architecture.py` (giữ đúng 18 violation, tập vi phạm y hệt), không phải profiling.

## Rủi ro của phép tách file (1.3.236)

| Rủi ro | Severity | Likelihood | Ghi chú |
|---|---|---|---|
| Type `private` rời file gốc làm rộng phạm vi truy cập ngoài dự kiến | Low | — | Chỉ 2 trường hợp (`SizeReader`, `BookTitleTranslationBackfill`), cả hai lên internal (trong module) chứ không public. Không có consumer mới nào được thêm. |
| Tách sai biên khối làm mất/nhân đôi code | High | **Low** | Cắt bằng brace-matching có bỏ qua string/comment, sau đó đối chiếu cân bằng ngoặc của 10 file gốc với `HEAD`: giống nhau tuyệt đối. 14 file mới đều cân bằng 0. |
| Line-ending sai ở file mới | Medium | — | **Đã xảy ra và đã sửa**: lần ghi đầu dùng `newline=CRLF` trên nội dung vốn đã CRLF nên thành `\r\r\n`, khiến gate đọc `TabbedVisibleBrowserViewController.swift` thành 402 dòng (gấp đôi 201). Đã chuẩn hoá toàn bộ 14 file về LF cho khớp phần còn lại của repo. |
| Còn 16 `LINE_LIMIT_EXCEEDED` chưa xử lý | Medium | — | Không giải được bằng tách type (các file này chỉ có 1 type); cần tách **thành viên** sang file `X+Feature.swift`. Nợ lớn nhất: `TTSManager.swift` (4003, cần ≤3470), `JSExecutor.swift` (1514, cần ≤1066), `ReaderView.swift` (2250, cần ≤2053). |
| 2 `VIEW_SWIFTDATA_MUTATION` thật vẫn còn | Medium | — | `DiscoveryView.swift`, `ReaderView.swift`. Sửa đúng cách phải chuyển ghi qua `BookTransactionCoordinator`/`ExtensionTransactionCoordinator` — đổi quyền sở hữu transaction, không phải dọn dẹp cơ học, nên tách thành quyết định riêng. |
| Chưa biên dịch cục bộ | Medium | — | Máy Windows; xác minh compile dựa vào CI trên macOS. 14 file mới + 10 file sửa đều chưa qua compiler tại thời điểm commit. |

## Rủi ro của lần dọn code chết (1.3.235)

| Rủi ro | Severity | Likelihood | Ghi chú |
|---|---|---|---|
| Xoá symbol mà một đường gọi động (JS bridge, `#selector`, delegate) vẫn cần | High | Low | Đã loại trừ có phương pháp: bỏ qua toàn bộ `Services/Extensions/Engine/JS*` (API mà extension JavaScript gọi theo tên), bỏ qua conformance delegate, và đếm tham chiếu theo **tên trần** nên hàm truyền dạng closure/`#selector` vẫn được tính. Đã kiểm tra không symbol nào là protocol requirement. |
| Mất vĩnh viễn 20 file test | Medium | — | Xoá bằng `git rm` nên phục hồi được từ git history; đây là quyết định trực tiếp của người dùng, không phải suy đoán. |
| Còn code chết dây chuyền sau khi xoá | Low | Low | Đã quét lại sau khi dọn: 0 hàm `public`/`internal` không tham chiếu (đợt hai đã xoá thêm `ModelStore.readCachedVoices`/`writeCachedVoices`/`voicesCacheURL` vốn chỉ phục vụ hàm vừa xoá). Type duy nhất còn báo là `FreeBookApp` (`@main`, false positive). |
| Chưa kiểm chứng bằng biên dịch | **High** | — | Đây là lần thay đổi rộng nhất (5 file xoá, 1 đổi tên, ~30 symbol, 20 file source đụng tới) và vẫn **chưa build được** vì máy là Windows. Bắt buộc `xcodegen generate` + build trên macOS trước khi coi là xong. |

## Next-chapter prefix audio risks (1.3.234)

| Rủi ro | Severity | Likelihood | Ghi chú |
|---|---|---|---|
| Lệch index giữa chunk prefix và `paragraphs` ⇒ audio và highlight desync | High | **Very Low** | Chặn hai lớp: `consume(matching:)` yêu cầu key trùng tuyệt đối, **và** `mergeNextChapterPrefixAudio` so `PreparedChunk.finalText` với `applyReplacements(paragraphs[index].text)`. Không khớp ⇒ **bỏ** chunk (log `textMismatch=M`) chứ không bao giờ phát sai đoạn. Lớp thứ hai phủ cả trường hợp DTO bị dựng lại với key không đổi (fallback load / force-refresh nội dung chương kế). |
| Tổng hợp đầu cơ tốn request/pin khi người dùng dừng ngay sau đó | Medium | Medium | Prefix luôn ở mức ưu tiên thấp nhất, tuần tự 1 operation; `pause()` hủy phần đang bay, `stop` giải phóng toàn bộ. Với `googlePrefetchCount` lớn (tối đa 10), capacity ở chunk cuối chương có thể lên tới `count - 1` request. |
| Chunk prefix cũ lưu lại sau khi đổi `pitch` của Google (đường `pitch.didSet` không gọi `clearPrefetchCache`) | Low | Medium | Chỉ là RAM tạm (tối đa `count - 1` payload); dữ liệu bị loại ở `request` kế tiếp hoặc `consume` do key khác. Không có nguy cơ phát sai pitch. |
| NghiTTS đếm payload thiên về bảo thủ (`preloadedData.count + hasPreparedNext + reservesNghiAudioSlot`) nên có thể đếm trùng một payload và cấp capacity nhỏ hơn thực tế | Low | Medium | Cố ý: sai theo chiều **không vượt** `maxTotalAudioPayloads = 5`. Hệ quả xấu nhất là prefix ít hơn 1 chunk ở một vài nhịp; watermark tự đánh giá lại ở sự kiện kế tiếp. |
| Watermark 8s có thể vẫn không đạt nếu trần 5 payload hết chỗ (chunk quá ngắn) | Low | Low | Đây là giới hạn thiết kế đã chọn (không nới trần RAM). Muốn đảm bảo đủ 8s trong mọi trường hợp thì phải nâng `NghiSynthesisPolicy.maxTotalAudioPayloads` — là thay đổi quy chuẩn, cần quyết định riêng. |
| Prefix của NghiTTS xếp hàng nhiều task cùng lúc (tối đa `capacity`), khác `canScheduleNghiRefill` "một refill in-flight" của cửa sổ đoạn văn | Low | Medium | **Sai lệch có chủ ý**: `PiperSynthesisCoordinator` vẫn chỉ chạy 1 inference tại một thời điểm và prefix ở mức `.optionalReserve` (thấp nhất), nên đây là độ sâu hàng đợi chứ không phải song song hoá. Đổi sang 1-in-flight sẽ khiến buffer chỉ lấp được 1 chunk mỗi nhịp chuyển đoạn — quá chậm ở 1-2 chunk cuối chương. |
| `sessionID`/`ttsProcessingGeneration` không nằm trong identity của prefix (chỉ có `TTSPreparedNextChapterKey`) | Low | Low | **Tính chất dùng chung với `TTSChapterPrefetcher`** (chunk 0 cũng vậy) nên không phải sai lệch riêng của thay đổi này. Cùng book/chapter/url/cấu hình ⇒ audio giống nhau, và `stopPlayback`/đổi engine/đổi giọng đều đi qua `clearAllTTSCaches`. Muốn siết thì phải siết cả hai owner cùng lúc — chưa làm. |
| Chưa kiểm chứng bằng biên dịch | Medium | — | Thay đổi được viết trên Windows; `xcodebuild` chỉ chạy trên macOS. Cần build + kịch bản nghe qua biên chương trên máy thật trước khi coi là đã xác minh. |

## Search-history live-suggestion risks (1.3.191)

* **Residual - UI only, no logic change:** the live-filtered history suggestions reuse the existing history row UI in `ShelfSearchView`/`SearchView`; no shared-store or search logic changed, so risk is limited to layout. In `ShelfSearchView` the suggestion block is capped at 220pt to avoid starving the results list height.
* **Residual - Windows cannot build/test at the moment; iOS build and XCTest verification happens via CI or a Mac.**

## Shelf search & title-translation backfill/refresh risks (1.3.190)

* **Mitigated - stale/empty translated names:** `Book.titleTrans`/`authorTrans` are backfilled at app launch once dictionaries are loaded and refreshed every time a book is opened (`ReaderView` bootstrap and `BookDetailView` `.task`); per-session additions and dictionary/custom-dict changes reach the DB without waiting for the next launch, and refresh only writes when the value changes (no redundant save churn).
* **Residual - dictionaries not ready at launch:** `runIfNeeded` guards on `TranslationManager.shared.isVietPhraseLoaded` and skips silently when dictionaries are not yet loaded; the refresh-on-open path covers those books when first opened, and the backfill retries on the next launch.
* **Residual - Windows cannot build/test at the moment; iOS build and XCTest verification happens via CI or a Mac.**

## removeDuplicatedTitle config risks mitigated in 1.3.189

* **Mitigated - Reader/TTS drift on duplicated chapter title:** per-book toggle `removeDuplicatedTitle_<bookId>` (default ON, shared by Reader + TTS) drops the first content line only when it matches an active TOC rule via the same `TranslateUtils.isChapterHeaderLine` used by TXT import; both sides keep the same stable line IDs after the drop so highlight/TTS sync stays aligned.
* **Residual - detection depends on active TOC rules:** if no TOC rule matches (or rules are disabled), the duplicated title is kept; the toggle is a display convenience, not a guaranteed dedupe.
* **Residual - Windows cannot build/test at the moment; iOS build and XCTest verification happens via CI or a Mac.**

## AVAudioSession -50 (BadParam) resolved in 1.3.180

* **Resolved - invalid category/option combination:** `TTSAudioSessionController.configureAudioSession()` called `setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .allowBluetooth, .allowBluetoothA2DP])`. `.allowBluetooth` (HFP) is documented valid only with `.record`/`.playAndRecord`/`.multiRoute`, so `setCategory` threw `OSStatus -50` (`AVAudioSessionErrorCodeBadParam`). The subsequent `setActive(true)` in the same `do` block never ran, `isAudioSessionConfigured` stayed `false`, and the error was re-logged on every paragraph/chapter play (observed during Google TTS auto-advance to chapter 2).
* **Fix:** removed `.allowBluetooth`, keeping `.duckOthers` + `.allowBluetoothA2DP` (both valid with `.playback`). The log now also records the underlying OSStatus code for future diagnosis.
* **Residual:** playback still worked while the bug existed because `AVAudioPlayer.play()` implicitly activates the session, but the intended `.playback`/`.spokenAudio` configuration (background playback, ducking, Bluetooth A2DP routing) was not applied.

## NghiTTS chapter-transition crash risks mitigated in 1.3.147

* **Mitigated - empty preprocessor output:** Piper kiểm tra cả input và output tiền xử lý; output không thể đọc được chuyển thành WAV khoảng lặng hợp lệ thay vì làm eSpeak/ONNX ném lỗi.
* **Mitigated - refill failure feedback loop:** failure state được khóa theo session/chapter/paragraph, tối đa hai attempt và cooldown 1 giây; scheduler không thể thử lại sớm qua callback khác.
* **Mitigated - stale cancellation state:** cancellation tách khỏi generic failure path, context/generation được kiểm tra trước mutation và reset hủy retry task nên task cũ không thể hồi sinh state đã xóa.
* **Residual risk:** Windows chỉ xác nhận parser/static checks; iOS build và XCTest đầy đủ vẫn cần macOS/Xcode hoặc CI trước khi phát hành.

## NghiTTS safeCachedTimeThreshold prefetch risks mitigated in 1.3.141

* **Mitigated - cancel/re-synthesize feedback loop:** `PiperSynthesisCoordinator` deduplicates exact `synthesisKey` requests and appends waiters. Detaching one waiter or pausing does not cancel an active ONNX inference.
* **Mitigated - non-contiguous cache undercount:** `calculateNghiCachedTime()` measures contiguous playable duration stopping at the first missing gap, preventing excess synthesis while correctly accounting for prepared $N+1$ items.
* **Mitigated - Settings resume work loss:** opening/closing Settings with snapshot equality (`onlyThresholdChanged = true`) resumes playback without stopping or clearing valid preloaded audio.
* **Mitigated - thermal prefetch cancellation:** thermal state remains diagnostic/logging telemetry only and does not cancel audio refills.

## Chapter memory and obsolete-work risks mitigated in 1.3.114

* **Mitigated - app-lifetime normalized chapter growth:** shared repository RAM is bounded by both 12 entries and 12 MiB estimated cost, with immediate memory-warning trimming and oversized-document bypass.
* **Mitigated - cancellation-insensitive shared waiters:** Reader/TTS retain per-consumer continuations. Canceling one no longer blocks that caller until unrelated shared work completes, while final-subscriber cancellation reaches the extension task.
* **Mitigated - orphaned fallback auto-advance:** TTS now owns and generation-guards the load/process task; stop/session replacement/newer advance cancels it and cancellation cannot be misreported as a fatal playback load error.

## TTS foreground energy risks mitigated in 1.3.112

* **Mitigated - widget display-rate work:** the global floating cover no longer drives a 30 FPS SwiftUI timeline while playback continues across Reader/Discovery/Shelf.
* **Mitigated - broad TTS view invalidation:** app root, Shelf, widget, and Reader no longer observe every published manager field. Deduplicated projections suppress unrelated paragraph/highlight/download/timer updates; another book's highlights cannot invalidate the visible Reader.
* **Mitigated - repeated Lock Screen static work:** translated titles, local cover decode, and artwork construction are cached per static identity and coalesced behind one cancelable task. Paragraph transitions update only dynamic timeline fields.
* **Mitigated - unconditional Nghi warm-up:** Siri/Google/Ext app launches no longer prepare the Piper model; Nghi selection owns the lazy warm-up lifecycle.

## Web-extension engine risks mitigated in 1.3.39

* **Deadlock mitigation**: The `waitForReady` JS bridge checks `Thread.isMainThread` and returns a failed JSON readiness DTO immediately instead of waiting on the semaphore, preventing application deadlock.
* **WKWebView Cookie privacy limitation**: Since WKWebView Loader uses the default configuration, cookies are persistent and shared within the app's default WKWebsiteDataStore, representing a privacy constraint due to lack of per-extension/session isolation.

## Reader risks mitigated in 1.3.10

* **Mitigated - stale rendered window:** the vertical reader now advances `stableIndexes` together with the active chapter window, preventing a permanent stop at the initial `n+2` boundary.
* **Mitigated - extension fetch overlap:** `ReaderPrefetchGate` enforces one global two-request cap across Reader instances. Repository waiters now leave immediately on cancellation and cancel the underlying extension task when no Reader/TTS consumer remains, while a still-shared operation retains its gate slot until completion.
* **Mitigated - hidden overlay work:** chapter-list queries and eager full-list title translation no longer run throughout ordinary reading and TTS updates. TTS full-queue metadata refresh is owned by `TTSManager` and uses background SwiftData for local books.
* **Mitigated - large TOC jump latency:** opening the chapter list positions directly at the current row without animating through all preceding chapters and reuses Reader-owned SwiftData objects.
* **Mitigated - shelf/discovery tab swipe jank:** Shelf rows no longer scan chapter relationships while rendering, and Discovery keeps only the selected category page plus adjacent pages fully mounted during horizontal paging.
* **Mitigated - anti-bot request burst:** a jump loads only its target; speculative next-chapter loading waits for target completion and a stable selection. Rapid updates coalesce pending chapters.

## 1. Bảng Tổng hợp Rủi ro (Risk Summary Table)

| ID | Loại Rủi ro | Vị trí (Source File) | Severity | Likelihood | Related Documents |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **R-01** | **Deadlock cứng hệ thống** | [JSExecutor.swift](../../Sources/Services/Extensions/Engine/JSExecutor.swift#L442-L458) | **Critical** | **Medium** | [13_resource_lifecycle.md](13_resource_lifecycle.md), [11_subsystems.md](11_subsystems.md) |
| **R-02** | **Rò rỉ tài nguyên ngầm** | [JSExecutor.swift](../../Sources/Services/Extensions/Engine/JSExecutor.swift#L9) | **High** | **High** | [12_ownership_graph.md](12_ownership_graph.md), [13_resource_lifecycle.md](13_resource_lifecycle.md) |
| **R-03** | **Lỗi Concurrency SwiftData** | Các ViewModel & Manager | **High** | **Medium** | [09_dependency_rules.md](09_dependency_rules.md), [13_resource_lifecycle.md](13_resource_lifecycle.md) |
| **R-04** | **Lỗi hồi phục AVAudioSession** | [TTSManager.swift](../../Sources/Services/TTS/TTSManager.swift#L3939) | **Medium** | **Medium** | [13_resource_lifecycle.md](13_resource_lifecycle.md), [11_subsystems.md](11_subsystems.md) |
| **R-05** | **Strong Reference Cycle trong callback AVAudioPlayer** | [TTSManager.swift](../../Sources/Services/TTS/TTSManager.swift#L986) | **Medium** | **Low** | [12_ownership_graph.md](12_ownership_graph.md), [04_call_graph.md](04_call_graph.md) |
| **R-06** | **Rò rỉ subscription cảnh báo** | [ReaderViewModel.swift](../../Sources/Views/Reader/ReaderViewModel.swift#L125) | **Low** | **Low** | [08_lifecycle.md](08_lifecycle.md) |
| **R-07** | **Race Condition xử lý nền TTS** | [TTSBackgroundProcessor.swift](../../Sources/Services/TTS/TTSBackgroundProcessor.swift#L13) | **Medium** | **Low** | [05_state_graph.md](05_state_graph.md), [07_dataflow.md](07_dataflow.md) |

---

## 2. Chi tiết các Rủi ro kỹ thuật

### R-01: Nguy cơ Deadlock hệ thống khi khởi chạy Trình duyệt ngầm
*   **Vị trí**: [JSExecutor.swift](../../Sources/Services/Extensions/Engine/JSExecutor.swift#L442-L458) bên trong `browserLaunchBlock`.
*   **Mức độ nghiêm trọng (Severity)**: **Critical** (Khiến ứng dụng bị đóng băng hoàn toàn và bị hệ điều hành iOS kill sau vài giây).
*   **Khả năng xảy ra (Likelihood)**: **Medium** (Xảy ra bất cứ khi nào mã JavaScript của Extension gọi phương thức `Engine.newBrowser().launch(...)` trên Main Thread).
*   **Nguyên nhân**:
    *   `browserLaunchBlock` sử dụng `DispatchSemaphore` để chặn luồng hiện tại và chờ kết quả tải trang HTML.
    *   Đồng thời, nó đẩy tác vụ tải trang WebView lên Main Thread bằng `DispatchQueue.main.async`.
    *   Nếu bản thân khối `browserLaunchBlock` được gọi từ Main Thread, Main Thread sẽ bị Semaphore khóa cứng. Khi đó, khối load WebView trong `DispatchQueue.main.async` không bao giờ được thực thi, dẫn đến hiện tượng **Deadlock vĩnh viễn**.
*   **Giải pháp (Mitigation)**:
    *   Không được dùng `DispatchQueue.main.async` kết hợp chặn đồng bộ bằng Semaphore.
    *   Chuyển hoàn toàn việc tương tác này sang cơ chế `async/await` phi chặn (non-blocking) bằng cách chạy JS Engine trên một background thread chuyên biệt hoặc sử dụng `withCheckedContinuation` không dùng Semaphore.

---

### R-02: Rò rỉ bộ nhớ WKWebView (Resource Leak) do JavaScript crash
*   **Vị trí**: Từ điển `activeBrowsers` trong [JSExecutor.swift](../../Sources/Services/Extensions/Engine/JSExecutor.swift#L9).
*   **Mức độ nghiêm trọng (Severity)**: **High** (WKWebView tiêu tốn rất nhiều tài nguyên RAM, gây crash app do cạn bộ nhớ - Out Of Memory).
*   **Khả năng xảy ra (Likelihood)**: **High** (Do các Extension JS của bên thứ ba viết thường phát sinh lỗi ngoại lệ hoặc crash giữa chừng và không gọi hàm `close()`).
*   **Nguyên nhân**:
    *   Khi JS khởi tạo browser qua `Engine.newBrowser()`, một `WebViewLoader` được lưu vào từ điển `activeBrowsers`.
    *   Nếu đoạn mã JavaScript gặp lỗi giữa chừng và dừng thực thi trước khi gọi `browser.close()`, phần tử trong `activeBrowsers` sẽ không bao giờ được xóa, khiến thực thể `WKWebView` bị treo vĩnh viễn trong RAM.
*   **Giải pháp (Mitigation)**:
    *   Bổ sung cơ chế tự hủy (Timeout) cho `WebViewLoader`. Nếu sau một khoảng thời gian (ví dụ: 60 giây) không có hoạt động, tự động đóng và giải phóng WebView.
    *   Đảm bảo giải phóng toàn bộ `activeBrowsers` trong hàm `deinit` của `JSExecutor`.

---

### R-03: Tranh chấp dữ liệu (Data Race) & Lỗi Context của SwiftData
*   **Vị trí**: Tiến trình ghi đĩa đồng thời trong `DownloadManager` và `ReaderViewModel`.
*   **Mức độ nghiêm trọng (Severity)**: **High** (Gây crash ứng dụng khi ghi đĩa hoặc đọc thực thể từ thread sai).
*   **Khả năng xảy ra (Likelihood)**: **Medium**.
*   **Nguyên nhân**:
    *   SwiftData yêu cầu các thực thể `@Model` (như `Book`, `Chapter`) chỉ được truy cập trên đúng luồng của `ModelContext` đã fetch chúng.
    *   Nếu background thread của `DownloadManager` tải truyện xong và lưu vào DB, nhưng Main Thread cùng lúc đang đọc để hiển thị, hoặc nếu ta truyền thực thể `@Model` qua lại giữa các luồng, SwiftData sẽ ném ngoại lệ crash.
*   **Giải pháp (Mitigation)**:
    *   Luôn tạo `ModelContext` riêng cho background thread.
    *   Khi cần truyền thực thể, chỉ truyền `bookId` hoặc `chapterId` (PersistentIdentifier) và fetch lại trên thread đích, tuyệt đối không truyền instance thực thể.

---

### R-04: Thất bại khi kích hoạt lại AVAudioSession sau cuộc gọi (Interruption)
*   **Vị trí**: Lắng nghe sự kiện ngắt tại [TTSManager.swift](../../Sources/Services/TTS/TTSManager.swift#L3939) (`setupInterruptionObserver`).
*   **Mức độ nghiêm trọng (Severity)**: **Medium** (Giao diện hiển thị đang phát nhưng không có tiếng ra loa).
*   **Khả năng xảy ra (Likelihood)**: **Medium** (Phổ biến khi người dùng nghe truyện bằng tai nghe Bluetooth và nhận cuộc gọi).
*   **Nguyên nhân**:
    *   Khi cuộc gọi kết thúc, hệ thống gửi thông báo kết thúc ngắt (`.ended`). Tuy nhiên, tại thời điểm này, hệ điều hành iOS có thể chưa hoàn toàn trả lại tài nguyên âm thanh.
    *   Việc gọi ngay lập tức `AVAudioSession.sharedInstance().setActive(true)` có thể thất bại, khiến AudioEngine không thể start lại.
*   **Giải pháp (Mitigation)**:
    *   Thực hiện thử lại (Retry) với độ trễ ngắn (ví dụ: trì hoãn 0.5 giây trước khi setActive lại).
    *   Kiểm tra kỹ kết quả trả về của hàm `setActive`.

---

### R-05: Strong Reference Cycle trong callback của AVAudioPlayer
*   **Vị trí**: Wiring callback phát audio [TTSManager.swift](../../Sources/Services/TTS/TTSManager.swift#L986) (`configureNghiAudioPlayerQueueCallbacks`) và delegate `audioPlayerDidFinishPlaying`.
*   **Mức độ nghiêm trọng (Severity)**: **Medium** (Rò rỉ bộ nhớ của TTSManager).
*   **Khả năng xảy ra (Likelihood)**: **Low** (Do đã được giảm thiểu).
*   **Ghi chú cập nhật**: Đường phát **không** dùng `AVAudioPlayerNode.scheduleBuffer` — repo hiện không có lệnh `scheduleBuffer` nào và `TTSAudioEngineController.play()` không có caller. Rủi ro retain cycle thực tế nằm ở các closure callback của `AVAudioPlayer`/`NghiAudioPlayerQueue` và block `DispatchQueue.main.async` lồng bên trong.
*   **Nguyên nhân**:
    *   Callback hoàn tất phát (`audioPlayerDidFinishPlaying`) và các completion closure của `NghiAudioPlayerQueue` chạy ngoài Main Actor.
    *   Nếu closure lồng `DispatchQueue.main.async` mà không capture lại `[weak self]`, có thể vô tình giữ chặt `self` trong Main Queue khi manager/session bị thay thế.
*   **Giải pháp (Mitigation)**:
    *   Đảm bảo capture `[weak self]` ở cả callback ngoài lẫn block `DispatchQueue.main.async` lồng bên trong; giải phóng `audioPlayer = nil` khi stop.

### R-07: Race Condition khi xử lý chuẩn hóa và dịch văn bản chạy nền
*   **Vị trí**: [TTSBackgroundProcessor.swift](../../Sources/Services/TTS/TTSBackgroundProcessor.swift#L13), [TTSManager.swift](../../Sources/Services/TTS/TTSManager.swift#L318)
*   **Mức độ nghiêm trọng (Severity)**: **Medium** (Có thể phát sai chương hoặc lỗi hiển thị).
*   **Khả năng xảy ra (Likelihood)**: **Low** (Do đã được giảm thiểu).
*   **Nguyên nhân**:
    *   Các tác vụ CPU-heavy (dịch Vietphrase, tách đoạn) được đẩy xuống actor chạy nền `TTSBackgroundProcessor` bất đồng bộ.
    *   Prewarm và thao tác Start có thể chồng lấp nếu người dùng bấm phát đúng lúc Reader đang chuẩn bị nội dung.
    *   Tác vụ cũ hoàn thành trễ hơn có thể đè đè dữ liệu mới nếu không được kiểm tra.
*   **Giải pháp (Mitigation)**:
    *   Mỗi request dùng một processor riêng thay vì chờ hàng đợi actor singleton; task cũ được hủy và processor kiểm tra cancellation giữa các giai đoạn.
    *   Cache prewarm có key gồm sách, chương, nội dung, chunk length và cấu hình tiêu đề; kết quả stale bị loại bằng generation/session guard.

---

#### Reader/TTS unified pipeline (2026-07)

- `ChapterTextNormalizer` is the single source for LF newlines, trimmed non-empty lines, **sparse paragraph IDs (`ChapterTextLine.id` is the raw line index and counts blank lines, so IDs are not array offsets and must be looked up by `id`, never used as an array index)**, and UTF-16 ranges. Because those ranges are computed before blank lines are dropped, `ChapterTextLine.utf16Range` must not be used to slice `NormalizedChapterText.content`. `ChapterContentRepository` produces one normalized `ChapterDocument` for both Reader and TTS.
- Reader uses `ReaderLoadState` with bootstrap retry/clamping, typed failures, generation checks, cache-first rendering, and a short opacity crossfade only for newly fetched content. `ReaderRoute.chapterIndex` preserves the selected TOC index through navigation.
- `TTSParagraphBuilder` chunks normalized lines without renumbering parent paragraph IDs; replacement output is checked before synthesis. TTS asynchronous work is guarded by session identity and TTS owns progress while playing.
- `ReadingProgressStore` coalesces RAM snapshots in an actor and flushes from background contexts on checkpoints, dismissal, and app backgrounding. Legacy window/tab Reader, duplicate progress repository, and `TTSSession` mirror are removed.
- **R-08: Main Thread Deadlock in WebView Native Bridge**: If browser wait/load operations are called on the Main Actor, `semaphore.wait()` blocks the Main Thread, preventing WKWebView from executing scripts and causing an instant deadlock. Mitigated by fail-fast thread check (`Thread.isMainThread`) returning a failed JSON readiness DTO immediately, exclusively on the new `waitForReady` bridge, while legacy synchronous `launch`/`callJs` API bridges remain unmitigated.
- **R-09: WKWebView Shared Cookie Persistence Limitation**: Default `WKWebViewConfiguration` shares cookie persistence via the default data store at the application configuration level (WKWebsiteDataStore persistence), which remains a limitation with no per-extension or per-session isolation; the `waitForReady` DTO design only limits what readiness data crosses the bridge and is unrelated to cookie isolation.

- **R-10: Remote TTS thermal/CPU burst (Partially mitigated)**: A depth-three window previously created independent Google/Ext tasks with no concurrency cap and nested retry. Mitigation is one priority coordinator (`RemoteTTSSynthesisCoordinator`), service-owned retry capped at two attempts, and delayed next-chapter audio. Thermal state is telemetry-only, so heat is **not** actively throttled — sustained remote synthesis on a warm device remains a residual risk.
- **R-11: Persistent Ext TTS JS state (Mitigated)**: Reusing JavaScriptCore can retain extension globals. The runtime is isolated to TTS, serialized, keyed by exact script/config identity, reset on error/full cache teardown, and never shared with search/detail/toc/chap execution.
- **R-12: Sustained NghiTTS on-device inference heat (Unmitigated for heat)**: Piper remains one-worker and serialized; the prefetch window keeps `N` + mandatory `N+1` plus up to two optional reserve items from `N+2` gated by the cached-time watermark, and matching in-flight work is reused to prevent duplicate synthesis. There is **no** thermal gating: `.serious`/`.critical` are logged only and never cancel or throttle refill, and there is no cooldown throttle. Very long sessions and measured RTF >= 1 therefore still generate unbounded heat and require a lighter model or another engine for guaranteed gapless playback.
- **Residual risk**: The VBook-compatible synchronous `fetch` API still waits on a worker semaphore. Registered URLSession tasks are now cancellable and binary payload text decoding is skipped, but changing the public JS API to mandatory Promise semantics remains incompatible with existing extensions.

<!-- GENERATED END -->
