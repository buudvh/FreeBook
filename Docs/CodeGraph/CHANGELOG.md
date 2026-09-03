# CHANGELOG - Nhật ký Thay đổi CodeGraph FreeBook

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **FreeBook**.

> Chỉ giữ các version gần đây. Lịch sử cũ hơn (≤ 1.3.295) nằm ở [CHANGELOG.archive.md](CHANGELOG.archive.md).

## [1.3.330] - 2026-09-03

### Cache script Ext TTS, cooldown làm mới kho, cache icon tiện ích

Thêm **3** file Swift (471 → **474**), sửa **8**. Đợt 1 của loạt tối ưu Google TTS / Ext TTS / tab Tiện Ích.

- **Ext TTS: mỗi đoạn văn từ 6 lần I/O xuống 2 lần `stat()`.** Trước lượt này, cứ 2–4 giây một lần suốt cả truyện, `ExtensionManager.ttsGenerate` **và** `getTTSRuntimeFingerprint` cộng lại làm **4 lần đọc `plugin.json` + 2 lần đọc trọn `tts.js` + 4 lần parse JSON + 2 lần serialize** — tất cả cho ra cùng một kết quả. `getTTSRuntimeFingerprint` cũ còn đọc script **trước** khi tra cache nên cache chỉ tiết kiệm SHA256, không tiết kiệm I/O. File mới [`ExtTTSScriptCache`](../../Sources/Services/TTS/Ext/ExtTTSScriptCache.swift) (128 dòng) giữ `scriptContent` + config đã trộn + fingerprint, hết hạn theo `(configJson, modDate của plugin.json, modDate của script)`. Phải canh cả `plugin.json` vì nó quyết định *tên* file script.
- **`ExtTTSRuntime.Identity` so fingerprint thay vì so cả chuỗi script.** Cùng độ phân giải (fingerprint băm script + config + đường dẫn) nhưng bỏ được phép so O(len(script)) mỗi đoạn. `resetTTSRuntime()` gọi `invalidateAll()` **trước** `ttsRuntime.reset()` — đảo lại là để hở khe dựng executor mới bằng payload cũ.
- **Bỏ khe hở lệch fingerprint/nội dung**: hai lối vào đọc đĩa riêng nghĩa là một lần cài lại đúng giữa hai lần đọc sẽ tạo `synthesisKey` của bản cũ nhưng chạy bản mới, tức audio sai bị cache dưới khoá đúng. Giờ cả hai lấy từ một `Payload`.
- **Xoá đường PCM chết của Ext TTS** — `ExtTTSService.swift` **230 → 65** dòng. `synthesize(...targetFormat:)` (102 dòng), `preprocessBufferForExtTTS` (45) và bộ theo dõi file tạm (`activeTempFiles`/`tempFileLock`/`cleanupTempFile`/`cleanupAllTempFiles`) **không có caller nào** trong `Sources/` — đã grep toàn cây. Bản cũ còn mang lỗi thật: `preprocessBufferForExtTTS` chạy **hai lần** trên cùng buffer (input block của converter rồi output), tức chuẩn hoá biên độ và fade áp đôi. Kéo theo `TTSManager.cleanUpTempFile()` (hàm **rỗng** còn được gọi ở 3 chỗ) và nhánh gọi `cleanupAllTempFiles()` ở `TTSManager+PrefetchCache`. Ext TTS giờ không tạo file nào, `@unchecked Sendable` → `Sendable`.
- **Tab Tiện Ích không còn quét mạng mỗi lần mở.** `.onAppear` gọi `refreshAllRepositories()` vô điều kiện, mà một lượt làm mới là 1 request registry cho **mỗi kho** cộng một request `plugin.json` cho **mỗi tiện ích chưa cài** (`ExtensionSyncCommandBuilder`, 6 luồng, timeout 10 s) — kho 100 tiện ích mà máy cài 5 là ~95 request. File mới [`RepositoryRefreshPolicy`](../../Sources/Services/Extensions/Manager/RepositoryRefreshPolicy.swift) (cooldown mặc định 6 giờ, `UserDefaults`) chặn lượt **tự động**; nút refresh trên toolbar gọi `force: true` nên **không** qua cửa. `markRefreshed()` chỉ ghi khi ≥ 1 kho cập nhật được — một lượt trắng vì mất mạng không khoá 6 giờ tiếp theo.
- **`filteredExtensions` tính một lần mỗi lượt vẽ thay vì 3 lần.** Thanh đếm, nhánh `isEmpty` và `List` trước đây gọi riêng, mỗi lần là 4 vòng `filter` + một `sorted` dùng `localizedCompare` (so sánh chuỗi đắt nhất trong Foundation) — nhân với **từng ký tự** gõ vào ô tìm kiếm. `filterStatusBar` đổi thành `filterStatusBar(count:)`.
- **Icon extension có cache** — file mới [`ExtensionIconImageCache`](../../Sources/Views/Common/ExtensionIconImageCache.swift), khoá `(đường dẫn icon.png, modDate)`, **ghi nhớ cả trường hợp không có ảnh**. `UIImage(contentsOfFile:)` không dùng cache dùng chung của UIKit (chỉ `UIImage(named:)` có), nên mỗi lượt SwiftUI dựng lại một dòng là một lần đọc đĩa + giải mã PNG — và `ExtensionIconView` nằm trong **mọi** dòng Kệ sách, Khám phá, mục lục Reader. Đây là phần lan ra ngoài tab Tiện Ích.
- **Hàng ở tab Tiện Ích đổi `AsyncImage` → `ExtensionIconView`**: đọc `icon.png` cục bộ trước rồi mới ra mạng, nên tiện ích đã cài không tải icon lần nào và hiện đúng cả khi offline. Giữ nguyên fallback theo loại (`waveform` cho TTS, `book.closed` cho truyện) cho hàng không có cả `localPath` lẫn `iconUrl`.
- **Google TTS**: `validVoiceIds` và key nhúng trong `Info.plist` thành `static let` (trước đây mỗi lượt tổng hợp dựng lại `Set` và tra `Bundle`). Key **cá nhân** của người dùng vẫn đọc `UserDefaults` mỗi lần vì đổi được ngay trong Cài đặt.
- Gate: `check_architecture.py` **13 → 12 violation** — `ExtensionManager.swift` 1049 → **1015** ≤ baseline 1022 nhờ dời phần băm sang cache, không violation mới nào. `validate_links.py` PASS (16 doc, 474 file) sau khi cập nhật 11 doc và ghi `--no-change-needed` cho 2 doc. **Chưa biên dịch, chưa nghe thử** — host là Windows; có **3 file Swift mới** nên khi lên macOS **phải** chạy `xcodegen generate`. Việc gộp nhiều đoạn vào một request Google (đã đo được 5–13× trên máy này) để **đợt 2**.


## [1.3.329] - 2026-09-03

### Thông báo chương mới không mất khi đánh dấu đã đọc, ẩn nút tải rule mặc định khi đã có rule

Sửa **5** file Swift; không thêm/xoá file nào.

- **Nguyên nhân dòng thông báo biến mất: "có chương mới" và "dòng trong Trung tâm thông báo" dùng chung một con số.** `NewChapterRecord.markSeen()` đưa `newChapterCount` về 0 và `firstFoundAt` về `nil`, còn `NotificationInboxView` lọc dòng bằng `hasNew` ⇒ bấm vào dòng (hoặc mở truyện từ kệ) là dòng mất. Giữ lại con số cũ cũng không đủ: `NewChapterProbe.applyDiff` **luôn** ghi lại `newChapterCount` ở mọi lượt dò, nên lượt kiểm tra kế tiếp sẽ xoá nó lần nữa.
- **Tách hai thứ ra**: [`NewChapterRecord`](../../Sources/Services/NewChapters/NewChapterRecord.swift) thêm nhóm `announced*` (`announcedChapterCount`, `announcedIsCountExact`, `announcedAt`, `announcementReadAt`) là **thông báo đã phát**, sống độc lập với `newChapterCount` là **trạng thái badge**. Probe gọi `announceCurrentFinding()` khi tìm ra chương mới; `markSeen()` cố ý **không** đụng nhóm này, chỉ thêm `markAnnouncementRead()`.
- **Badge giữ nguyên hành vi**: `hasNew`, `totalNewBooks`, `NewChapterBadgeView` vẫn đọc `newChapterCount` nên badge kệ sách và badge chuông vẫn tắt ngay khi đánh dấu đã đọc — không call site nào ở tầng View phải sửa. Đây là lý do chọn thêm field thay vì đổi nghĩa `hasNew`.
- **Luật một đợt thông báo**: đợt mới (chưa có thông báo, hoặc thông báo trước **đã đọc**) mở một dòng chưa đọc lấy mốc `firstFoundAt`; đợt đang chờ đọc mà dò thêm được chương thì chỉ cập nhật con số và giữ nguyên mốc phát hiện đầu tiên. Đọc rồi mà có thêm chương ⇒ nổi lên lại như thông báo mới; ba lượt kiểm tra trong cùng một đợt ⇒ vẫn một dòng.
- **Trung tâm thông báo đối xử hai loại nội dung như nhau**: dòng chương mới có dấu chấm chưa đọc, icon đổi `bell.badge.fill` → `bell` khi đã đọc, swipe để xoá, và "Xoá thông báo đã đọc" nay dọn **cả** toast lẫn dòng chương mới. Xoá một dòng chỉ gọi `clearAnnouncement()` chứ **không** xoá record — record giữ mốc `seen*`, xoá nó là lượt dò sau báo lại từ đầu như truyện mới.
- **Vá dữ liệu của bản cũ**: `loadIfNeeded()` chạy `backfillAnnouncements()` dựng thông báo từ `newChapterCount` đã lưu, nếu không thì người vừa cập nhật thấy badge sáng mà Trung tâm thông báo trống. Chạy được vì `NewChapterRecord.init(from:)` vốn `decodeIfPresent` mọi khoá.
- **`markAllAnnouncementsRead()` gộp một lần ghi đĩa** thay cho vòng lặp gọi `markSeen` từng truyện của "Đánh dấu đã đọc hết" (trước đây là N lần ghi file). Vòng lặp chụp `Array(records.values)` trước khi sửa dictionary.
- **Ẩn nút "Tải bộ rule mặc định" khi `ruleCount > 0`** ([`QuickTranslationRulesView`](../../Sources/Views/Settings/Translation/QuickTranslationRulesView.swift)). Nút đó ghi **đè** bộ đang chạy và màn này không có undo, nên với người đã sửa/nhập bộ riêng thì đó là một cú mất dữ liệu cách đúng một lần bấm. Không tạo đường cụt: "Xoá bộ rule khỏi máy" đưa `ruleCount` về 0 và nút hiện lại, "Nhập file rule (.txt)" vẫn luôn có, footer đổi chữ để nói rõ vì sao nút biến mất. Điều kiện là `ruleCount == 0` chứ không phải `!isLoaded` — `makeStatus` đặt `isLoaded = true` cho mọi snapshot kể cả file phân tích ra 0 rule, đúng lúc người dùng cần tải lại nhất.
- Gate: `check_architecture.py` giữ **13 violation** (cùng một tập, không có mục nào mới); `validate_links.py` PASS sau khi cập nhật `11_subsystems.md`. **Chưa biên dịch** — host là Windows, không có `xcodebuild`; không file Swift nào được thêm/xoá nên **không** cần `xcodegen generate`.


## [1.3.328] - 2026-09-03

### Bộ sưu tập sách, ghim truyện lên đầu kệ, bỏ màn Thử phiên âm, phiên âm Nhật đọc "u"

Thêm **11** file Swift (462 → **471**), xoá **2**, sửa **20**. Hai thư mục mới (`Sources/Views/Shelf/BookActions/`, `Sources/Views/Shelf/Collections/`).

- **`@Model` thứ 6: [`BookCollection`](../../Sources/Models/Database/BookCollection.swift), quan hệ N-N với `Book`.** Tên type cố ý **không** phải `Collection` — một `Collection` ở phạm vi module sẽ che `Swift.Collection` và làm mọi generic constraint viết sau này hiểu sai. `FreeBookApp.init()` vẫn là chỗ duy nhất khai schema. `Book` thêm `isPinned: Bool = false` và `collections: [BookCollection] = []`; tất cả đều additive + có mặc định vì repo không có `SchemaMigrationPlan` và `ModelContainer` init lỗi là `fatalError` (⇒ app không mở được). Chiều nghịch `@Relationship(inverse:)` khai đúng **một** đầu (`BookCollection.books`), giống cặp `Repository.extensions` ⇄ `Extension.repository`.
- **`deleteRule: .nullify` là bất biến ngữ nghĩa, không phải mặc định tình cờ.** Xoá bộ sưu tập chỉ tháo liên kết; `.cascade` ở đây nghĩa là xoá truyện thật khỏi kệ. `deleteCollection` còn dọn tay `books = []` trước `context.delete` cho rõ ý.
- **Bất biến "trong bộ sưu tập ⇒ trên kệ" được cưỡng chế ở coordinator, không ở call site.** [`BookCollectionCoordinator`](../../Sources/Services/Books/BookCollectionCoordinator.swift) (151 dòng, chủ transaction mới) bật `isOnShelf` ở mọi đường thêm; ngược lại `BookTransactionCoordinator.removeFromShelf` / `setOnShelf(false)` / `addBookToShelf(isOnShelf: false)` dọn `collections` + `isPinned` trong cùng `save()`. Bỏ truyện khỏi bộ sưu tập **không** đưa nó khỏi kệ — đúng yêu cầu.
- **Kệ sách có 4 tab**: Downloads (0), Kệ Sách (1), **Bộ Sưu Tập (2)**, Lịch Sử (**3**). Số tab là hợp đồng liên màn: `SearchView` gửi nó qua `userInfo["shelfTab"]` của notification `sourceChangedNavigateToShelf` — cả tên notification lẫn giá trị đều là literal trần, nên `SearchView.swift` được sửa cùng lượt (`2 → 3`). `selectedTab` là `@State` chứ không `@AppStorage` nên đánh số lại không phá trạng thái đã lưu.
- **Nhấn giữ một cuốn sách nay mở [`BookActionSheet`](../../Sources/Views/Shelf/BookActions/BookActionSheet.swift), không còn `.contextMenu`.** Menu ngữ cảnh của SwiftUI chỉ nhận `Button`/`Link` nên không dựng được phần đầu (bìa + tên + tác giả) lẫn danh sách bộ sưu tập bấm thêm/bớt tại chỗ với dấu **"+" ở cuối danh sách**. **Toàn bộ mục cũ giữ nguyên chữ và thứ tự**, thêm Ghim/Bỏ ghim và (khi mở từ trong một bộ) "Bỏ khỏi bộ sưu tập này". Dòng truyện đổi từ `Button { } label: { }` sang `onTapGesture` + `onLongPressGesture`: bọc trong `Button` thì cú nhả tay sau khi giữ vẫn kích hoạt action, mở luôn Reader phía sau sheet.
- **Ba màn dùng chung một bộ hành động** qua [`BookActionRunner`](../../Sources/Views/Shelf/BookActions/BookActionRunner.swift): Kệ sách, Lịch sử và [`CollectionDetailView`](../../Sources/Views/Shelf/Collections/CollectionDetailView.swift) cùng phát `BookSheetAction`, thân việc nằm một chỗ. Đó là cách "truyện trong bộ sưu tập có mọi hành động như trên kệ" đúng theo cấu trúc, không nhờ hai bản copy. `newChapterTarget`/`checkNewChapters`/`showNewChapterSummary` cũng dời vào đây (`ShelfView+NewChapters.swift` 127 → **57**), badge chương mới tách thành `NewChapterBadgeView`, dòng truyện tách thành `ShelfBookRowView`.
- **Ghim là thứ tự hiển thị, không phải nhóm dữ liệu** — cùng ngữ nghĩa `Extension.isPinned`. Sắp xếp làm trên RAM vì `@Query` sort theo `lastReadDate` được tab Lịch sử dùng chung, và **ghim-trước làm bằng hai lượt `filter`** (`pinned + unpinned`) chứ không một `sorted` hai khoá: `sorted(by:)` của Swift không ổn định nên sẽ trộn thứ tự trong cùng nhóm.
- **Chọn bộ sưu tập khi thêm vào kệ là tuỳ chọn**: [`CollectionPickerSheet`](../../Sources/Views/Shelf/Collections/CollectionPickerSheet.swift) hiện sau khi truyện lên kệ ở màn Chi tiết, có mục tạo bộ mới, bỏ qua cũng được. Để làm việc này mà không làm `BookDetailView.swift` phình thêm, `addToShelf` được dời sang file mới `BookDetailView+ShelfPlacement.swift` — nhờ vậy file đó **1207 → 1197**, lần đầu **về dưới** baseline 1201.
- **Tab Bộ sưu tập ([`CollectionsTabView`](../../Sources/Views/Shelf/Collections/CollectionsTabView.swift))**: tạo/đổi tên/xoá (kèm cảnh báo "truyện vẫn ở trên kệ"), kéo-thả thứ tự, đếm số truyện. Trùng tên (không phân biệt hoa/thường) bị chặn ở coordinator. Lọc/so tên làm **trên RAM** vì predicate lọc chuỗi của SwiftData iOS 17 dịch sai sang SQLite. `CollectionDetailView` nhận `collectionId` chứ không nhận đối tượng — bộ bị xoá trong lúc màn còn trên stack chỉ dẫn tới trạng thái rỗng có thông báo.
- **Sao lưu mở rộng mà không thêm `BackupScope`**: `library/collections.json` + `BookRecord.isPinned` đi kèm nhóm bắt buộc `.books` (thêm case `BackupScope` sẽ làm bản app cũ decode `manifest.scopes` lỗi — luật đã ghi hai lần trong `BackupPaths.swift`). `BookRecord.isPinned` phải là `Bool?`: `init(from:)` tổng hợp của Swift **không** dùng giá trị mặc định nên một khoá không-optional mới sẽ làm **mọi** `.fbbackup` cũ decode lỗi. `Counts.collections` an toàn nhờ `init(from:)` viết tay sẵn có. Khôi phục là **gộp**: bộ trùng tên dùng lại bộ đang có, thành viên chỉ gắn khi truyện có mặt trong máy, và cờ ghim chỉ áp cho truyện **mới thêm**.
- **Xoá màn "Thử phiên âm" theo yêu cầu** (`TTSTransliterationTesterView.swift` 277 dòng) cùng mọi thứ chỉ nó dùng: `TransliterationGoldenSet.swift` (128), `EspeakPhonemizer.probeVoices`, `VietnameseTokenGate.explain`. Nói thẳng hệ quả: phân hệ tiền xử lý TTS **không còn thước đo có hệ thống** — `Tests/` bị coi như không tồn tại, LiveContainer không đính được debugger, nên từ nay chỉ còn **nghe thử** ở "Thử giọng đọc". `rules.md` (mục 1.3.290 nói việc kiểm chứng nằm ở màn đó) và `10_risk_report`/`04_call_graph`/`13_resource_lifecycle` đã được ghi rõ là **không còn đúng**. Công tắc `EnglishPhonemeTransliterator.useEspeakKey` mất chỗ ở nên **chuyển** sang `NghiTTSSettingsView` — bỏ luôn thì đường IPA của espeak bật vĩnh viễn, không có đường thoát.
- **Phiên âm Nhật: hàng `u` đọc là `u`, không phải `ư`.** 15 giá trị trong `romajiToViSyllable` đổi tại chỗ (`ku su tsu tu nu hu fu mu ru gu zu du bu pu` và `u` trơ). `ư` là /ɨ/ không tròn môi, espeak-vi đọc ra âm khác hẳn ("Naruto" → *na-rư-tô*, "sushi" → *xư-si*). Trùng **giá trị** sinh ra (`tsu`/`tu` → `chu`, `zu` → `du` như `yu`) là vô hại — chỉ **khoá** của dictionary literal cần khác nhau. `collapseLongVowels`, `ー` → `""` và `sokuonCoda` **không** bị chạm nên hồi quy "arigatou → a-ri-ga-tô-ư" không quay lại.
- **Trả nợ một vi phạm kiến trúc cũ**: `ShelfView.removeFromHistory` từng gán `book.isHistory` rồi `try? modelContext.save()` ngay trong View (regex của gate không bắt vì `isHistory` không nằm trong danh sách thuộc tính bị canh); nay đi qua `BookTransactionCoordinator.setHistory`. Cùng lượt xoá `clearReaderFallback` trong `ShelfView` — hàm chết, `BookStorageManager` có bản riêng của nó. `ShelfView.swift` **910 → 780** (baseline 942).
- Gate: `check_architecture.py` **14 → 13 violation** (tập cũ trừ `BookDetailView`); không violation mới. `validate_links.py` PASS sau khi cập nhật 14 doc. **Chưa biên dịch** — host là Windows, không có `xcodebuild`; có **11 file Swift mới** nên khi lên macOS **phải** chạy `xcodegen generate`. **Chưa nghe thử** thay đổi phiên âm Nhật, và từ lượt này không còn bộ ca kiểm nào để chạy.


## [1.3.327] - 2026-09-03

### Gom nút của hai màn quản lý quy tắc vào một dropdown thế chỗ nút Edit

Sửa **2** file Swift ([`JunkFilterManagementView.swift`](../../Sources/Views/Settings/Translation/JunkFilterManagementView.swift) 369 → **378**, [`TTSReplacementManagerView.swift`](../../Sources/Views/Settings/TTS/TTSReplacementManagerView.swift) 379 → **390**).

- **Từ ba điểm điều khiển về một.** Trước đây mỗi màn có `EditButton()` ở `.navigationBarTrailing`, `Menu` "Tùy chọn" và nút `+` ở `.bottomBar`. Nay chỉ còn một `ToolbarItem(placement: .topBarTrailing)` — đúng chỗ `EditButton` cũ — chứa tất cả: Thêm quy tắc → Sắp xếp lại → Nhập/Xuất JSON → Xoá tất cả (lọc rác) hoặc Khôi phục mặc định (TTS). Thanh đáy biến mất hẳn, nhường chỗ cho danh sách.
- **`EditButton()` thay bằng `@State editMode` + `.environment(\.editMode, $editMode)`** — không phải để cho đẹp: `EditButton` tự quản trạng thái nên `Menu` không đọc được để đổi nhãn, và nhãn của nó do hệ thống dịch nên lệch với chữ tiếng Việt hardcode ở hai màn. Mục menu giờ đổi giữa "Sắp xếp lại" và "Xong sắp xếp" kèm icon tương ứng.
- **Thêm một chốt mới đi kèm việc tự quản `editMode`**: `.onChange(of: isSearching)` đưa `editMode` về `.inactive` khi bắt đầu tìm kiếm. Mục sắp xếp vẫn bị ẩn khi đang lọc (như cũ, vì `onMove` chỉ gắn ở nhánh không lọc) — không có chốt này thì List kẹt ở edit mode trong khi mục thoát duy nhất đã bị ẩn khỏi menu.
- Thứ tự trong menu theo quy ước iOS: hành động chính trước, hành động phá huỷ cuối và cách bằng `Divider`. Toàn bộ đường dữ liệu (`onDelete`/`onMove`/`swipeActions`, hai `confirmationDialog`, `DocumentPickerPresenter`, `ShareSheet`) không đổi.
- Gate: `check_architecture.py` giữ đúng **14 violation** (cùng một tập). Lưu ý headroom: `TTSReplacementManagerView.swift` còn **10 dòng** là tới trần 400 — lần sửa sau ở file này nên tách bớt thay vì thêm. **Chưa biên dịch** — host là Windows, không có `xcodebuild`; không file Swift nào được thêm/xoá nên **không** cần `xcodegen generate`.

## [1.3.326] - 2026-09-03

### Dọn tài liệu ghép nối đã bị bỏ của VS Code extension

Sửa **3** file của `Tools/VSCode/FreeBookExtDebug` (`README.md`, `src/protocol.ts`, `package.json`); **không** file Swift nào.

- **README bỏ toàn bộ mục "Ghép nối"** — nó vẫn mô tả `FreeBook: Pair with App`, chuỗi `freebook-extdebug://pair?…&token=…`, bước bấm "Cho phép kết nối" và token lưu bằng `SecretStorage` hết hạn 3 phút. Pairing bị bỏ từ **1.3.305**; không còn lệnh, token hay `SecretStorage` nào trong code (đã grep `src/` và `package.json` để chắc — chỉ còn đúng comment trong Swift ghi nhận việc đã bỏ). Thay bằng mục "Kết nối" nói đúng ba bước hiện tại và nhấn rằng chốt an toàn duy nhất còn lại là bấm trên thiết bị cho `Install Staged Draft`/`Rollback`.
- **Bảng lệnh khớp lại `package.json`**: bỏ dòng `Pair with App` (lệnh không tồn tại), thêm `Connect to App`, `Browse Extension Folder…`, `Refresh Workspace Extensions` — ba lệnh có thật mà README chưa hề liệt kê.
- **`freebook.extdebug.cancelRun` được khai trong `contributes.commands`.** Nó vốn `registerCommand` trong `extension.ts` và có nút ở Sidebar, nhưng thiếu khai báo nên **không** hiện trong Command Palette; README thì vẫn liệt kê nó. Tiêu đề `installDraft` đổi thành "(overwrite or new install, needs device approval)" cho khớp hai nhánh của 1.3.325.
- **`protocol.ts`**: comment của `Envelope.type` bỏ `paired` khỏi danh sách kiểu server trả về — server không còn phát kiểu đó. `parseTarget` **giữ nguyên** khả năng nhận chuỗi `freebook-extdebug://pair?host=…&port=…` kiểu cũ (bỏ qua `token`/`service`), và điều đó nay được ghi rõ trong README thay vì để người đọc tưởng pairing còn sống.
- **README thêm mục "Chạy script mà không cần cài"** — trả lời đúng câu hỏi hay gặp: `Select Extension` → `Stage Workspace Draft` → `Run Saved Profile` (`sourceMode: "draft"`) chạy thẳng từ `extension-drafts/`, không chạm thư viện. Kèm hai giới hạn: `Run Script…` (source `installed`) vẫn đòi extension đã cài, và staging bị xoá sạch khi tắt server hoặc mở lại app.
- Gate: `tsc -p ./` **PASS**. Không sửa `Sources/**` nên `validate_links.py` không doc nào stale (`Tools/**` ngoài phạm vi manifest) và `check_architecture.py` giữ nguyên **14 violation**.

## [1.3.325] - 2026-09-03

### Cài mới extension từ VS Code, không chỉ ghi đè bản đã có

Thêm **1** file Swift (461 → **462**), sửa **5** file Swift và **3** file của `Tools/VSCode/FreeBookExtDebug`.

- **`draft.install` có hai nhánh, không thêm lệnh mới vào protocol.** Router tra thư viện bằng **cả hai** id (id client gửi và id app suy ra từ `plugin.json`): khớp ⇒ `installOverExisting` ghi đè file như trước; không khớp ⇒ `installAsNew` dựng `extensions/<packageId>/` từ thư mục staging rồi ghi hàng `Extension` qua `ExtensionTransactionCoordinator`. Đây là chỗ **duy nhất** trong phân hệ debug ghi SwiftData.
- **File mới [`ExtensionDraftMetadata.swift`](../../Sources/Services/Extensions/Debug/Staging/ExtensionDraftMetadata.swift) (136 dòng)** đọc `plugin.json` của bản nháp theo **đúng** luật của `ExtensionManager.installFromLocalZip` (`metadata.packageId` thắng, thiếu thì `name.lowercased()` thay dấu cách bằng `_`) và dựng `UpsertExtensionCommand`. Cố ý **không** tin `packageId` của client: nhờ vậy client gửi `Truyen Full` khi app đang có `truyen_full` vẫn rơi vào nhánh *cập nhật*, không sinh hàng SwiftData thứ hai.
- **Thứ tự file → bản ghi là bất biến an toàn, không phải chi tiết triển khai.** Bản ghi trỏ vào thư mục không tồn tại là lỗi im lặng ở mọi màn `@Query`; ngược lại chỉ là thư mục mồ côi mà `ExtensionInstallAudit` phát hiện được. Ghi bản ghi thất bại thì client nhận `INTERNAL_ERROR` nói rõ "đã copy file nhưng không ghi được thư viện".
- **`writeLibraryRow` hop sang `MainActor` với `ModelContext(container)` riêng** (coordinator là `@MainActor`, còn luật repo cấm dùng chung context của MainActor cho tác vụ nền); chỉ một `String?` băng qua ranh giới isolation. Phát `"extensionDidUpdate"` cùng khuôn với `BackupRestoreWorker` để màn Khám Phá thấy extension mới mà không cần mở lại app.
- **`installNew` copy chứ không move thư mục staging** — `run.start` với cùng revision phải còn chạy được sau khi cài, và vùng staging vẫn do `ExtensionDraftStagingStore` sở hữu. Thư mục đích đã tồn tại mà chưa có hàng nào trỏ tới (lần cài trước chết giữa đường) đi đúng đường của `install`: sao lưu `.backup/<packageId>/` rồi `replaceItemAt`. Đoạn sao lưu được tách thành `backup(installedUrl:packageId:)` dùng chung cho hai đường.
- **`run.start` với `sourceMode: "draft"` không còn đòi extension đã cài** — cách thử một extension mới trước khi thêm vào thư viện. Thiếu bản đã cài thì `downloadUrl`/`configJson` rỗng và `host` lấy `metadata.source` của bản nháp; `getCombinedConfigs` vẫn nạp mặc định từ khoá `config` trong `plugin.json`. Hai nguồn cùng đi qua một hàm `startRun(...)` để không lệch nhau.
- **`draft.stage` bỏ chốt "phải đã cài".** Chốt thật của vùng staging vốn là trần `ExtensionDraftManifest` (200 file / 1 MiB mỗi file / 4 MiB tổng), kiểm tra containment từng path, và việc staging bị xoá sạch khi tắt server hoặc mở lại app.
- **Cửa xác nhận vật lý nói đúng việc sắp làm**: `ExtensionDebugInstallGate.Kind` thêm `.installNew`, `Request` mang `displayName` đọc từ `plugin.json`, `summary` ba nhánh. Màn Debug Server đổi nhãn "Đồng ý cài mới", header "Yêu cầu thêm extension mới", footer cảnh báo app sẽ tạo thư mục + bản ghi mới, và bullet "Giới hạn đã biết" tách riêng hai nhánh.
- **Client**: `resolvePackageId({ allowNew })` cho phép stage/install/run-draft chạy với extension chưa có trên app (vẫn chặn `sourceMode: installed`); sau khi cài thì nạp lại `extensions.list` và nhận `packageId` thật từ reply. README cập nhật bảng lệnh + hai ranh giới mới.
- Gate: `tsc -p ./` (`npm run compile`) **PASS**. `check_architecture.py` giữ đúng **14 violation** (cùng một tập; file mới 136 dòng ≤ 400 và đúng 1 type top level). **Chưa biên dịch Swift** — host là Windows, không có `xcodebuild`; có **1 file Swift mới** nên khi lên macOS **phải** chạy `xcodegen generate`.

## [1.3.324] - 2026-09-03

### Sửa lệch packageId giữa VS Code và app, Run Current File thiếu tham số

Sửa **2** file Swift ([`ExtensionDebugCommandRouter.swift`](../../Sources/Services/Extensions/Debug/Server/ExtensionDebugCommandRouter.swift) 239 → **262**, [`+Draft.swift`](../../Sources/Services/Extensions/Debug/Server/ExtensionDebugCommandRouter+Draft.swift) 183 → **204**) và **2** file TypeScript của `Tools/VSCode/FreeBookExtDebug`.

- **Nguyên nhân "cài bản nháp / test script đều lỗi": hai bên không cùng một luật sinh `packageId`.** Client lấy `metadata.packageId || json.packageId || metadata.name || json.name || folderName` **thô** từ `plugin.json`, còn app sinh id theo ba luật khác nhau tuỳ đường cài: repo sync dùng `ExtensionSyncCommandBuilder.packageId(forName:)` = `name.lowercased()` + thay dấu cách bằng `_`; import zip dùng `metadata.packageId` hoặc `name.lowercased()` **không** thay dấu cách; restore backup giữ nguyên id đã lưu. Một extension tên "Truyen Full" vì vậy là `truyen_full` trên app nhưng `Truyen Full` ở client ⇒ **mọi** lệnh có `packageId` (`run.start` cả hai `sourceMode`, `draft.stage`, `draft.install`, `draft.rollback`) bị trả `UNKNOWN_EXTENSION` kể cả khi extension đang có trên app.
- **Sửa ở client, vì app là thẩm quyền cuối cùng về danh tính.** `resolvePackageId()` đối chiếu lựa chọn hiện tại với `extensions.list` theo bốn bước (id trùng khít → id trùng slug tên → slug tên trùng slug tên → tên rút gọn bỏ dấu trùng nhau) rồi mới gửi; không khớp thì báo rõ kèm danh sách id app đang có. `stagedRevisions` cũng khoá theo id đã resolve nên id lúc stage và lúc install luôn là một. Chưa kết nối thì giữ id đoán để hành vi offline không đổi.
- **"Run Current File" gửi run trắng nên luôn lỗi.** Nó lấy tên file làm entrypoint mà **không** hỏi tham số, trong khi `ExtensionDebugCommandRouter.entrypoint(from:)` trả `nil` nếu `search` thiếu `keyword` hoặc `detail`/`toc`/`chap` thiếu `url` ⇒ `UNKNOWN_ENTRYPOINT`; chỉ `genre`/`home` chạy được. Nay `collectEntrypointParams` (dùng chung với Run Script/Run Profile) hỏi trước khi gửi.
- **Điều kiện rẽ nhánh `custom` sai đối tượng**: cũ so tên file với khoá `script` trong `plugin.json` (tên script của extension), nay so với **sáu entrypoint chuẩn** của server — `list.js` khai trong `script` vẫn phải đi đường `custom` kèm `scriptFileName`.
- **`getActiveFolderUri()` gói nhầm thư mục** khi người dùng chọn extension từ danh sách "Trên App": nó rơi thẳng về `workspaceFolders[0]`. Nay tìm thư mục workspace cùng danh tính trước.
- **Phía app: lỗi `UNKNOWN_EXTENSION` nay nói ra id đang có** (`unknownExtensionMessage(requested:installed:)`, dùng chung cho bốn lệnh). Không lộ gì mới vì `extensions.list` vốn trả đúng tập id đó. Thiếu `packageId`/`sourceRevision` của `draft.install`/`draft.rollback` đổi sang `MALFORMED_MESSAGE` cho đúng bản chất; client chỉ in `[code] message` nên không phá tương thích.
- **Giới hạn chưa đổi (chủ ý, không phải bug)**: `draft.stage`/`run.start`/`draft.install` vẫn bắt buộc extension **đã có** trên app — `ExtensionDraftInstaller` chỉ thay file trong `snapshot.localPath` và không ghi SwiftData, nên chưa có đường cài một extension hoàn toàn mới từ VS Code.
- Gate: `tsc -p ./` (`npm run compile`) **PASS**, đây là lần đầu có bằng chứng biên dịch thật trong một lượt sửa phân hệ này. `check_architecture.py` giữ đúng **14 violation** (cùng một tập; hai file router 262/204 dòng đều ≤ 400). **Chưa biên dịch Swift** — host là Windows, không có `xcodebuild`; không file Swift nào được thêm/xoá nên **không** cần `xcodegen generate`.

## [1.3.323] - 2026-09-03

### Gỡ tap tắt bàn phím khi bàn phím đóng để không mất vùng bôi đen

Sửa **1** file Swift ([`KeyboardDismissGesture.swift`](../../Sources/Common/Utils/KeyboardDismissGesture.swift), 112 → **149**).

- **Nguyên nhân (người dùng xác nhận trên máy thật: chưa mở bàn phím thì không bao giờ bị).** `KeyboardDismissGesture` cài `UITapGestureRecognizer` lên `UIWindow` ở lần bàn phím hiện **đầu tiên** rồi để nằm đó suốt phiên. Handler gọi `endEditing(true)`, mà lệnh đó buộc **first responder bất kỳ** trong window resign — kể cả `ReaderUITextView` chỉ đọc đang giữ vùng bôi đen, hoặc `WKContentView` của web view tra cứu (công cụ tìm kiếm mở qua `ReaderLookupRoute`). Vì `cancelsTouchesInView = false` và recognizer nhận diện đồng thời, nó không chặn cú long-press chọn chữ — nó chỉ âm thầm xoá vùng chọn ở đúng nhịp thả tay, rồi `textViewDidChangeSelection` bắn `length == 0` và `ReaderView` tắt `FloatingSelectionMenu`.
- **Vì sao vùng bôi ngắn hay bị nhất**: `UITapGestureRecognizer` fail khi ngón **di chuyển** quá ngưỡng, không phải khi giữ lâu. Kéo một vệt dài thì tap tự fail nên vùng chọn sống; chọn một từ thì ngón gần như không di chuyển nên tap nhận diện và xoá.
- **Cách sửa**: recognizer chỉ sống trong quãng bàn phím đang hiện. `activate()` đăng ký thêm `keyboardWillHideNotification` → `keyboardWillHide()` → `uninstall()` gỡ recognizer khỏi **mọi** window theo `UIGestureRecognizer.name`. Cố ý **không lọc** `windowLevel == .normal && !isHidden` như `installIfNeeded()`: bộ lọc chỉ hợp lý khi chọn nơi cài, còn lúc gỡ mà lọc thì window đã bị ẩn giữa hai lần bàn phím sẽ giữ lại một recognizer mồ côi vẫn gọi `endEditing`.
- **Hành vi "bấm ra ngoài ô nhập là tắt bàn phím" không đổi**: đúng lúc có bàn phím để tắt thì recognizer luôn có mặt. Ba thiết lập bắt buộc của recognizer (`cancelsTouchesInView = false`, `shouldRecognizeSimultaneouslyWith → true`, `shouldReceive` bỏ qua ô đang nhập được) giữ nguyên vì không cái nào là nguyên nhân. `Sources/Views/Reader/**` không bị chạm một dòng nào — kể cả overlay "bắt tap ra ngoài" của `FloatingSelectionMenu`, thứ từng là nghi phạm thứ hai nhưng bị loại vì không mở bàn phím thì không bao giờ mất vùng bôi.
- **Khe hẹp cố ý để lại**: nếu bàn phím **đang** hiện đúng lúc người dùng bôi đen (ví dụ ô nhập trong trang web vẫn giữ tiêu điểm), cú tap đó vẫn vừa tắt bàn phím vừa xoá vùng chọn; recognizer biến mất ngay sau đó nên lần bôi kế tiếp bình thường.
- Gate: `check_architecture.py` giữ đúng **14 violation** (cùng một tập; file 149 dòng vẫn ≤ 400 và đúng 1 type top level). **Chưa biên dịch** — host là Windows, không có `xcodebuild`; không file Swift nào được thêm/xoá/đổi tên nên **không** cần `xcodegen generate`.

## [1.3.322] - 2026-09-02

### Viết hoa sau dấu hai chấm và tiền tố thoại trong Reader

Sửa **1** file Swift ([`TranslateUtils.swift`](../../Sources/Services/Translation/Utils/TranslateUtils.swift)).

- **`TranslateUtils.postProcessText`:** Cập nhật `capitalizeRegex` mở rộng `[.!?:]+` (gồm `:` và `：`) và bổ sung các loại gạch ngang đầu dòng (`-`, `—`, `–`). Tự động viết hoa chữ cái đầu câu thoại/trích dẫn sau dấu hai chấm, kể cả khi có dấu ngoặc (`"`, `“`, `‘`, `(`, `[`, `{`, `【`) hoặc gạch đầu dòng bao bọc.
- Kiểm thử: 18/18 test cases đạt 100% PASS.

## [1.3.321] - 2026-09-02

### Debug Extension: trả đầy đủ JSON Response.success/error và format Beautified JSON

Sửa **5** file Swift, khôi phục và nâng cấp **VS Code Extension** (`Tools/VSCode/FreeBookExtDebug`).

- **`ExtensionDebugRunner` trả JSON đầy đủ:** Đổi từ `manager.compactRepresentation(clean)` sang `manager.stringify(clean)` khi emit event `.responseValidated`. Không còn tóm tắt thành `[Array: N items]` hay `[Object: N keys]`.
- **`ExtensionDebugRedactor` nâng trần payload phản hồi lên 128 KB:** Thêm hàm `responsePayload(_:)` giữ nguyên toàn bộ định dạng JSON và ngắt dòng, không bị `collapseWhitespace` hay cắt ở 600 ký tự như `message(_:)`. `ExtensionDebugSession` định tuyến `.responseValidated` và `.responseError` qua hàm này.
- **VS Code Extension nâng cấp:**
  - Khôi phục giao diện **Sidebar Webview Panel** (`src/sidebarView.ts`) trên Activity Bar với các tính năng: kết nối LAN `ws://ip:port`, chọn extension, stage bản nháp, cài đặt/rollback, điều khiển Run/Cancel, và Live Trace.
  - Tự động parse và in Beautified JSON (`null, 2`) cho `Response.success` và `Response.error` trên cả Output Channel và Live Trace.

## [1.3.320] - 2026-09-02

### Sửa stall nạp trước NghiTTS, hủy thật inference, và bốn lượt tối ưu tiền xử lý

Xoá **3** file (464 → **461**), sửa **6** file. Bốn việc chạy bằng subagent song song, mỗi diff được tôi đọc lại và kiểm chứng trước khi nhận.

- **Nạp trước không còn tê liệt vì một đoạn rỗng.** `TTSManager.scheduleNghiRefill` gặp đoạn có text rỗng sau khi áp quy tắc thay thế thì `return` — không sinh tác vụ nào **và** không duyệt tiếp sang đoạn sau. Log thực tế của `Docs/Reports/2026-09-02-investigation-nghitts-underrun-stall.md`: 8 giây liền không có lần nạp trước nào, rồi `Underrun` liên tiếp ở 96/98/100. Nay đoạn rỗng được đánh dấu vào một `Set<Int>` riêng và vòng tìm bước qua nó (chặn trên 8 đoạn) để tới đoạn **sẽ thực sự được đọc**. Cố ý **không** dùng `preloadedData[i] = Data()` như tài liệu gợi ý: `prepareNextNghiAudioIfPossible` chỉ kiểm `!= nil` rồi đẩy vào `AVAudioPlayer(data:)`, mà data rỗng thì khởi tạo throw, catch xoá khỏi cache, index đó lại được xếp hàng lại ⇒ churn.
- **Hủy giờ dừng thật tác vụ đang chạy.** `PiperSynthesisCoordinator` giữ handle `Task` của request đang chạy; khi hết waiter (hoặc `cancelAll`, hoặc đợt hủy reserve lúc tạm dừng) thì cancel handle đó ⇒ `try Task.checkCancellation()` giữa các chunk trong `ONNXPiperEngine.synthesizeInternal` ném lỗi, engine dừng ở chunk kế tiếp thay vì chạy hết đoạn chắc chắn bị bỏ. Trước đây vòng xử lý vẫn `await work()` tới hết, nên pause/skip vẫn tốn ONNX và vì vòng là tuần tự nên request `.demand` mới phải xếp sau ⇒ khựng tiếng. Vòng xử lý **vẫn chờ** task chết hẳn (cancel của Swift là hợp tác, `ORTSession.run` của chunk hiện tại luôn chạy xong) để giữ bất biến "chỉ một operation tổng hợp tại một thời điểm".
- **`synthesisKey` có bản mặc định** nên dedup thật sự hoạt động. Đường stream được đánh dấu `allowsCoalescing: false` và bộ lọc dedup chặn **hai chiều**, vì `onChunkPayload` bị bắt trong closure của waiter đầu tiên nên mọi hình thức chia sẻ đều làm waiter thứ hai không được gọi callback.
- **`processUnits`: 102 → 4 lượt quét toàn văn bản.** 51 đơn vị trước đây mỗi đơn vị một cặp regex; nay gộp thành hai alternation (nhóm nhiều ký tự, nhóm một ký tự) với nhánh dài xếp trước, giữ đúng hai hậu tố lookahead khác nhau của bản cũ. Nhánh "số viết bằng chữ" có tiền kiểm rẻ nên chỉ còn 2 lượt khi văn bản không có từ số đếm. Tương đương hành vi được kiểm bằng cách port cả hai bản sang Python rồi so từng ký tự: 95 ca chọn tay + 1 995 ca targeted + 12 000 câu văn xuôi → 0 khác biệt. Fuzz thô cho 0,53% khác biệt, tất cả thuộc một lớp duy nhất — token đơn vị dán liền nhau không dấu phân cách (`km3mg`) — là hệ quả không tránh được của "một lượt trái→phải" thay cho "51 lượt độc lập".
- **`processCurrency` / `processPercentages` bỏ 7 vòng `while firstMatch`** vốn quét lại từ đầu chuỗi sau mỗi lần thay (O(k×N) mỗi vòng), giờ mỗi pattern một lượt `matches(in:)`. An toàn vì `VietnameseNumberSpeller.spell` không bao giờ trả về chữ số và cả 7 pattern đều bắt buộc có `\d`.
- **`applyReplacements`: 95 → 6 lượt quét.** 91 trong 95 rule chỉ thay **một ký tự**, nên các dãy rule một ký tự liền nhau được gộp thành một bảng `[Character: String]` quét một lượt. Cố ý **không** dùng regex alternation cho nhóm nhiều ký tự: alternation đổi thứ tự ưu tiên từ "theo thứ tự rule" sang "theo vị trí trái nhất" (`[bc→Y, ab→X]` trên `abc`: cũ ra `aY`, alternation ra `Xc`), mà rule người dùng tự thêm rất dễ rơi vào đó. Cache bị dựng lại qua `didSet` của `rules` nên phủ mọi đường ghi.
- **`replaceDictionaryWords` bỏ ~40 000 lời gọi regex mỗi chương.** Trường `WordToken.text` cấp phát một chuỗi `.lowercased()` cho **mọi** token rồi không bao giờ được đọc — xoá hẳn. Và `whitespaceCollapse` + `trimmingCharacters` (tới 4 lần mỗi token, nhân 2 lượt acronym/word) giờ chỉ chạy sau một vị từ duyệt `unicodeScalars` không cấp phát.
- **Viết hoa sau dấu ngoặc** (thay đổi của người dùng, tôi review và đưa vào): bỏ `“‘”’[【` khỏi lớp ký tự mở câu nên `“từ này” không phải` không còn bị viết hoa chữ giữa câu, mà vẫn viết hoa đầu dòng và sau `.!?` kể cả khi có ngoặc bọc ngoài.
- **Xoá hub từ điển tham chiếu** (phiên âm/đại từ/luật nhân) theo yêu cầu: 3 file cùng section và hàm đếm trong `DictionaryHubView`.
- Chưa build được (máy Windows). `check_architecture.py` giữ **14** violation, không thêm cái nào: `TTSManager.swift` 4023 → **4022**, `TextPreprocessor.swift` giữ đúng **1121** = baseline (bù bằng cách xoá 17 dòng log đã comment-out).

## [1.3.319] - 2026-09-02

### Thử giọng đọc NghiTTS, hub từ điển tham chiếu, đồng bộ hai danh sách quản lý

Thêm **4** file Swift (460 → **464**), sửa **4** file.

- **Thử giọng đọc NghiTTS** (`NghiTTSTextToolView`): ô nhập chữ, chọn giọng từ danh sách model đã tải, thanh tốc độ 0.5–2.0×, nút phát thử và nút dừng, kèm số liệu (kích thước, thời gian tổng hợp, độ dài clip). Dùng lại **đúng** `PiperTTSService` của `TTSManager` chứ không tạo service riêng — một service mới nghĩa là một `ORTSession` thứ hai trong RAM và một đường tổng hợp không đi qua `PiperSynthesisCoordinator`, trái bất biến "chỉ một operation tổng hợp tại một thời điểm". Nút phát bị chặn khi TTS đang đọc truyện, và chốt lại một lần nữa ngay lúc bấm vì view không observe `TTSManager` theo luật repo.
- **Hub từ điển tham chiếu** cho phiên âm / đại từ / luật nhân, vào từ màn Từ Điển. Danh sách có tìm kiếm, dòng đếm và tải thêm theo trang — cùng khuôn với `DictionaryListView`. **Không** nhồi ba bộ này vào `DictType`: chúng không có bản riêng theo truyện, không đi qua đường CRUD một-từ, và thêm case sẽ buộc **17** điểm `switch` trong module (kể cả token của rule dịch nhanh) xử lý hai case vô nghĩa.
- **Không có thêm/sửa/xoá ở hub tham chiếu**, có lý do: `TranslationManager` không ghi vào các file `.dat` và `ChinesePhienAmWords.txt`, nên một nút Lưu ở đây sẽ không có tác dụng thật. Bộ nào chỉ có bản `.dat` thì hiện số mục đang hoạt động kèm lý do không liệt kê được (`DoubleArrayTrie` chỉ có `wordCount` + tra cứu, không liệt kê entry).
- **Đồng bộ hai danh sách quản lý** (thay thế ký tự TTS, lọc rác) với các list khác: thêm tìm kiếm và dòng đếm cho danh sách thay thế, chuẩn hoá câu chữ dòng đếm cho cả hai.
- **Sửa một lỗi thật phát hiện khi làm việc đó**: cả hai danh sách render mảng **đã lọc** nhưng wire `onMove` vào `manager.moveRules`, mà `IndexSet` của `onMove` trỏ vào mảng đã lọc — kéo-thả trong lúc tìm kiếm sẽ đổi chỗ sai rule, và thứ tự ở hai danh sách này **chính là** thứ tự áp dụng. Nay trong lúc tìm: kéo-thả bị chặn, `EditButton` ẩn, xoá đổi sang theo `id`.
- Chưa build được (máy Windows). `check_architecture.py` giữ **14** violation nền.

## [1.3.318] - 2026-09-02

### Điều chỉnh quy tắc viết hoa sau dấu câu trong TranslateUtils: bỏ tự viết hoa sau ngoặc, chỉ viết hoa khi có dấu kết thúc câu

Sửa **1** file Swift (`TranslateUtils.swift`).

- **Bỏ tự động viết hoa đơn lẻ sau dấu ngoặc kép/đơn cong và ngoặc vuông.** Trước đây pattern `[.!?“‘”’\[【]` tự động viết hoa ký tự tiếp theo sau bất kỳ dấu ngoặc nào, khiến các từ đặt trong ngoặc ở giữa câu khi kết thúc ngoặc đóng (`”`, `]`) bị viết hoa từ tiếp theo (`“từ này” không phải` $\rightarrow$ `“Từ này” Không phải`).
- **Chỉ viết hoa sau dấu đóng ngoặc khi có dấu kết thúc câu đứng liền trước.** Biểu thức mới `(^\s*[“‘"'\(\[\{【]?\s*|[.!?]+[”’"'\)\]\}】]*\s*[“‘"'\(\[\{【]?\s*)(\p{Ll})` áp dụng viết hoa chuẩn xác cho:
  - Đầu dòng / đầu đoạn (hỗ trợ cả trường hợp mở ngoặc ở đầu dòng như `“Hôm nay`, `[Chương 1`).
  - Sau dấu kết thúc câu thông thường (`.`, `!`, `?`).
  - Sau dấu đóng ngoặc có dấu kết thúc câu đi trước (`.” `, `!” `, `?” `, `.] `).
  - Không viết hoa sau dấu đóng ngoặc giữa câu nếu không có dấu kết thúc câu đi trước (`“bán-thần” dùng...`, `[ghi chú] trong...`).
- Chưa build được (máy Windows). `check_architecture.py` giữ đúng **14** violation nền.

## [1.3.317] - 2026-09-02

### Gợi ý phiên âm đi đúng đường của pipeline, có badge JP/EN; bỏ chunk không có chữ; xoá dụng cụ đo IPA

Xoá **3** file, thêm **2** file (461 → **460**), sửa **5** file.

- **Gợi ý phiên âm trước đây dùng một đường KHÁC với lúc đọc thật.** Nó gọi `EnglishTransliterator` (bộ luật chính tả) trong khi pipeline gọi `EnglishPhonemeTransliterator` (espeak IPA), và gọi `transliterateRomaji` **vô điều kiện** thay vì qua cổng `ForeignScriptClassifier`. Hệ quả: với gần như mọi từ tiếng Anh chip gợi ý khác hẳn chuỗi TTS thực đọc; còn với từ Anh cắt được kiểu romaji (`sonata`, `tomato`) nó hiện một cách đọc Nhật mà pipeline không bao giờ chọn. `TTSPhoneticSuggestionBuilder` (mới) làm lại theo đúng thứ tự của `TextPreprocessor.transliterateToken`.
- **Khoá tra từ điển giờ gấp dấu phụ** (`folding(.diacriticInsensitive).lowercased()`) giống lúc đọc; bản cũ chỉ `lowercased()` nên khoá có dấu không bao giờ khớp.
- **Mỗi gợi ý có badge nguồn** `TĐ`/`JP`/`EN` với màu riêng, và chip mà pipeline **thật sự** sẽ chọn được làm nổi (viền dày hơn, chữ đậm màu hơn) — trả lời đúng câu "đâu là phiên âm Nhật, đâu là Anh". Kèm `accessibilityLabel` nói rõ lý do của từng gợi ý.
- **Bỏ dấu `-` trong gợi ý** (`xơ-trít` → `xơ trít`). Chỉ bỏ ở gợi ý, **không** bỏ trong engine: dấu đó là cách transliterator đánh dấu ranh giới âm tiết và golden set đang ghi dạng có `-`; nhưng khi nó được lưu vào từ điển thì thành ký tự thật và đi tiếp vào espeak, nên giá trị người dùng lưu phải sạch.
- **Chunk không có chữ/số bị bỏ ở `TTSParagraphBuilder`**, không còn đi xuống engine. Trước đây nó vẫn thành một item phát: service nhận ra không đọc được rồi trả một WAV im lặng dài bằng khoảng nghỉ, nên người nghe gặp một khoảng ngắt vô nghĩa và hàng đợi vẫn phải dựng rồi huỷ một `AVAudioPlayer`. Bỏ ở builder là chỗ sớm nhất còn biết ngữ cảnh chunk, và `paragraphIndex` của các chunk còn lại không đổi vì nó là id dòng gốc.
- **Xoá `TTSIPAProbeSection`** cùng hai file engine chỉ nó dùng (`ONNXPiperEngine+Phonemes`, `PiperPhonemeInventory`). Khảo sát cho thấy nó **vẫn truy cập được trong bản release** bằng 3 lần chạm, không có cờ DEBUG — nhưng nó là dụng cụ đo một lần cho thí nghiệm E1, kết quả đã ghi trong CHANGELOG và lấy lại được từ git history nếu làm E1 vòng 2. Màn "Thử phiên âm" **vẫn còn**.
- **Widget trình duyệt thu nhỏ** cao **38** = 2/3 chiều cao widget nghe truyện (56), `minWidth` 74, icon `safari`, cỡ chữ 14/12.
- Chưa build được (máy Windows). `check_architecture.py` giữ **14** violation nền; `TTSDictionaryEditView.swift` **giảm** 705 → 702 dòng dù thêm badge.

## [1.3.316] - 2026-09-02

### Tối ưu NghiTTS và tiền xử lý text; chia sẻ cả bộ rule riêng; widget trình duyệt; ẩn nút tải từ điển

Sửa **9** file Swift (vẫn **461**). Bốn khảo sát chạy bằng subagent song song; mỗi phát hiện đều được kiểm chứng lại trong code trước khi sửa.

- **Cổng chặn theo chữ số ở tiền xử lý TTS.** ~24 lượt quét toàn văn bản (`formatNumbers`, ngày, giờ, tiền, phần trăm, điện thoại, thập phân, `processDigits`) đều **bắt buộc** có `\d` mới khớp được gì, nhưng vẫn chạy đủ trên đoạn văn xuôi không có chữ số nào. Hai bước cố ý **nằm ngoài** cổng: `processRomanNumerals` làm việc trên chữ — và vì nó *sinh ra* chữ số (`III` → `3`) nên cờ được tính lại ngay sau nó; `processUnits` có nhánh đọc số viết bằng chữ ("hai mươi km").
- **`replaceMatches` cộng dồn một chiều vào một buffer** thay vì `replacingCharacters` cho từng match (mỗi lần copy lại cả chuỗi ⇒ O(M×N)). Đây là đường chung của hơn 30 điểm gọi nên chi phí nhân theo cả pipeline.
- **`NghiAudioPlayerQueue.updateRate` có cửa no-op.** Kéo slider tốc độ bắn nhiều event cùng giá trị sau clamp; trước đây mỗi event đều `stop()` + `prepareToPlay()` + schedule lại `nextPlayer` **giữa lúc đang phát** — đúng loại việc gây giật ở biên đoạn.
- **Payload im lặng được cache** theo `(sampleRate, số sample)`, tối đa 12 entry. Mọi sample đều là 0 nên `[Float]` và WAV là hằng; trước đây mỗi khoảng nghỉ đều cấp phát lại và encode WAV lại, một chương dài có hàng nghìn khoảng nghỉ. Cache chính xác tuyệt đối, không đổi hành vi.
- **Log trên đường bàn giao đoạn được bọc `isLoggingEnabled`** (hàm bị gọi lại mỗi lần `prepareNext`/`resume`/`updateRate`, mà log mặc định đang tắt), và **xoá biến chết `nextData`** — nó giữ sống toàn bộ buffer WAV của đoạn kế tiếp mà không ai đọc.
- **Chia sẻ cả bộ rule riêng có điểm vào ngang hàng với Xuất/Xoá**: nút trong menu `ellipsis.circle`. Trước đó chức năng đã tồn tại nhưng chỉ nằm trong menu của **từng hàng** rule nên gần như không tìm ra được, và mất hẳn khi bộ riêng chưa có rule nào. Mục cũ được giữ nhưng đổi nhãn cho rõ là **cả bộ**, kèm sửa `accessibilityLabel` vốn không hề nhắc tới nó.
- **Widget trình duyệt thu nhỏ** cao 36 → **56** cho khớp widget nghe truyện, `minWidth` 90 → 110, icon `globe` → **`safari`**.
- **Ẩn nút tải từ điển mặc định khi đã có VietPhrase.** Trước đây nút luôn hiện và chỉ đổi nhãn thành "Tải lại"; việc nạp lại đã có nút "Làm mới dữ liệu dịch" ngay dưới lo.
- Chưa build được (máy Windows). `check_architecture.py` giữ **14** violation nền — `TextPreprocessor.swift` giữ đúng 1 121 dòng (bằng baseline) sau khi dọn các dòng log đã comment trong hàm pipeline.

## [1.3.315] - 2026-09-02

### Chọn bộ riêng/chung ngay lúc bấm Lưu thay vì bằng ô chọn trong form

Sửa **1** file Swift (vẫn **461**).

- **Bỏ `scopeSection`** — ô chọn "Bộ riêng truyện / Bộ chung" nằm sẵn trong form của màn thêm/sửa rule. Thay bằng `confirmationDialog` nổ ra khi bấm **Lưu**, nên phạm vi được quyết định lúc rule đã viết xong chứ không phải trước đó.
- Popup chỉ hiện ở chế độ **thêm** và khi đang có truyện mở — đúng đúng điều kiện mà ô chọn cũ dùng để hiện ra. Không có truyện nào mở thì chỉ còn bộ chung nên lưu thẳng, không hỏi. Chế độ **sửa** vẫn ghi vào đúng phạm vi của rule đó và hiện phạm vi ở dòng thông tin, không hỏi lại — hỏi ở đây sẽ ghi bản sao sang bộ kia mà vẫn để lại rule cũ.
- `submit()` tách thành `submit()` (quyết định có hỏi hay không) và `performSubmit(scope:)` (ghi thật). `saveToBook` vẫn được cập nhật theo lựa chọn trong popup để bản nháp khôi phục đúng.
- **Không sửa gì cho hai yêu cầu "vế trái đã có thì đè vế phải, chưa có thì thêm mới"**: cả hai bộ đã làm đúng vậy từ trước qua `QuickTranslationRuleRecordStore.upsert` — trùng mẫu thì thay vế phải tại đúng vị trí dòng, không trùng thì thêm vào cuối; dùng chung cho `addOrOverwriteRule`, `updateRule` của cả bộ chung và bộ riêng.
- Chưa build được (máy Windows). `check_architecture.py` giữ **14** violation nền.

## [1.3.314] - 2026-09-02

### Số Hán viết dính nhau đọc thành danh sách, gộp về một luật duy nhất

Sửa **1** file Swift (vẫn **461**).

- **Gộp `approximateRange` + `enumeratedDigits` thành một hàm `enumeratedNumbers`.** Trước đó dãy **hai** chữ số ra khoảng (`四五` → "4 đến 5") còn dãy **ba** chữ số trở lên ra danh sách — hai luật cho cùng một hiện tượng. Nay mọi dãy chữ số Hán trần liền nhau đều ra **danh sách ngăn bằng `, `**: `二三级` → `2, 3 cấp`, `一二三级` → `1, 2, 3 cấp`. Đổi hành vi so với 1.3.301: `四五` giờ là `4, 5` chứ không còn `4 đến 5`.
- **Số nhiều chữ số tính đúng nhờ thay từng chữ số vào cả chuỗi** rồi đọc như một số thường, nên bậc đứng trước, đứng sau, hay cả hai phía đều ra đúng: `十三四岁` → `13, 14 tuổi`, `二三十` → `20, 30`, `三四百` → `300, 400`, `三百四五十` → `340, 350`.
- **Số ghép thật vẫn chính xác**: `三百二十级` → `320 cấp` (không có dãy chữ số trần nào dài ≥ 2), `一百二十三` → `123`, `二零二五` → `2025` (chứa `零` nên là số đọc theo vị trí), `五三七` → `537` (không tăng liền bậc nên là mã số).
- Chuỗi có **hai dãy rời** (`二三十四五`) vẫn đọc như một số, vì không suy được cách ghép bậc theo cụm nào — giữ nguyên hành vi cũ, có ghi trong doc comment.
- Chưa build được (máy Windows); đã mô phỏng lại thuật toán ngoài Swift và đối chiếu 15 ca gồm mọi ca người dùng nêu. `check_architecture.py` giữ **14** violation nền.

## [1.3.313] - 2026-09-02

### Năm lỗi đọc/dịch/TTS: viết hoa sau gạch nối, số Hán liền nhau, số thứ tự, dính chữ giữa hai rule, ext mồ côi

Thêm **2** file Swift (459 → **461**), sửa **7** file. Số phiên bản nhảy từ 1.3.307 lên 1.3.313 để không đụng 1.3.308–312 đã dùng trên nhánh `legado_source`.

- **Reader không còn viết hoa chữ sau dấu `-`.** Lớp ký tự "mở câu mới" của `TranslateUtils.postProcessText` có cả `-`, nên `bán-thần` thành `bán-Thần`. `-` là gạch nối từ ghép và gạch đầu dòng hội thoại, không phải dấu kết câu — đã bỏ khỏi lớp đó.
- **`一二三级` giờ ra `1, 2, 3 cấp`** thay vì `123 cấp`. Dãy từ **ba** chữ số Hán trần tăng liền bậc là một **danh sách** số viết dính nhau, không phải số ghép: tiếng Trung viết 123 là `一百二十三`. Cùng tiền đề với khoảng xấp xỉ hai chữ số (`四五` → "4 đến 5") đã có từ 1.3.301. Ba cửa hẹp giữ hành vi cũ: phải toàn chữ số Hán trần (có bậc thì đọc thành một số), **không** chứa `零`/`〇` (nên `二零二五` vẫn là `2025`), và tăng **đúng một** mỗi bước (nên mã số `五三七` vẫn là `537`).
- **`thứ 1` được NghiTTS đọc là "thứ nhất".** `VietnameseOrdinalSpeller` (file mới) chạy **trước** `processDigits` — sau bước đó mọi chữ số đã thành số đếm nên không còn dấu vết để nhận ra số thứ tự. Chỉ hai giá trị bất quy tắc (`1` → nhất, `4` → tư); `thứ 21` để nguyên cho số đếm để không sinh ra "thứ hai mươi nhất". Áp cho cả `hạng`.
- **Hai rule dịch khớp liền kề không còn dính chữ.** `十年第一魂技` ra `10 nămHồn kỹ thứ 1` vì `assemble` nối hai bản dịch khi không còn ký tự gốc nào ở giữa, và tokenizer VietPhrase coi cả cụm Latin là **một** token nên chỗ dính sống tới output cuối. Chèn một khoảng trắng khi hai đầu đều là chữ/số, và tính nó vào `outputRange` của đoạn hiện tại để mảng segment vẫn phủ liền mạch — span dịch được dựng từ đó.
- **Tiện ích import từ zip mất file thì xoá hẳn khỏi DB.** Trước đây gỡ tiện ích chỉ xoá `localPath` và giữ hàng để tải lại; đúng cho tiện ích của kho nhưng tiện ích import zip không thuộc kho nào và không có `downloadUrl`, nên hàng còn lại chỉ hiện một nút Tải về **báo lỗi**. `ExtensionInstallAudit` (file mới) đối chiếu DB với đĩa (`plugin.json` còn hay không) rồi: mất file + không có nguồn tải lại → xoá hàng; mất file nhưng thuộc kho → chỉ xoá `localPath`. Chạy lúc mở màn hình quản lý, trước khi làm mới kho; xoá thẳng và ghi `AppLogger`, không hỏi xác nhận. Gỡ tiện ích import zip cũng xoá hàng luôn thay vì để lại.
- Chưa build được (máy Windows). `check_architecture.py` giữ **14** violation nền, không thêm cái nào — `TextPreprocessor.swift` giữ đúng 1 121 dòng (bằng baseline) bằng cách bỏ một dòng log đã comment, `TranslateUtils.swift` giữ đúng 1 023 dòng như trước lượt sửa.

## [1.3.307] - 2026-09-01

### Khám Phá giữ vị trí cuộn từng tab; khoảng độ dài token có thêm thanh kéo

Thêm **1** file Swift (458 → **459**), sửa **2** file.

- **Đổi tab ở Khám Phá rồi về tab cũ không còn nhảy về đầu.** Nguyên nhân không phải mất dữ liệu: `TabView(.page)` do `UIPageViewController` dựng nên trang rời vùng lân cận bị dỡ, và cửa sổ ±3 tab của `DiscoveryView` còn xoá hẳn tab xa hơn — cả hai đều làm `List` mất offset dù `PaginatedNovelLoader` vẫn còn dữ liệu. `DiscoveryScrollAnchorStore` (mới) ghi nhớ **`link` của truyện đang ở trên cùng** của từng tab; tab chốt neo lúc rời (`onDisappear` + `onChange(of: selectedCategoryId)`) và `scrollTo(anchor: .top)` lúc quay lại. Neo **không** dùng `CGFloat` offset (chiều cao hàng phụ thuộc bìa/tên nên offset không tái lập được sau một lượt dựng lại) và **không** dùng `ExtensionItemResult.id` — id đó là `UUID()` mới mỗi lần bóc tách, nên với tab xa (> ±3, loader bị xoá và dữ liệu nạp lại) neo theo id sẽ không bao giờ khớp. `link` là định danh nội dung nên khôi phục được cả trong ca đó.
  - Chi phí được giữ ở mức thấp có chủ ý: từng hàng chỉ ghi `setVisible` vào một `Set` trong một `class` giữ ở `@State` (không `@Published`, đúng khuôn `ParagraphTracker`), nên cuộn **không** invalidate body; phép quét tìm hàng trên cùng chỉ chạy một lần mỗi lượt đổi tab.
  - Khôi phục có hai nhịp vì dữ liệu có thể chưa nạp xong lúc tab xuất hiện: lúc `onAppear` (trễ 0.2 s cho `List` dựng xong) và lúc `novels.count` từ 0 lên. `pendingRestoreAnchor` bị xoá ngay sau lượt áp nên `loadMore` sau đó không kéo người dùng về chỗ cũ. Neo bị xoá sạch ở `loadDiscoveryData()`.
- **Khoảng độ dài token ở màn thêm/sửa rule có thêm thanh kéo**, mỗi đầu một hàng `[−] thanh-kéo giá trị [+]`. Hai nút `+/−` **giữ nguyên** ở hai bên theo yêu cầu; `stepper` (VStack, hai cột cạnh nhau) đổi thành `lengthRow` (HStack full-width) vì thanh kéo cần chiều rộng. Thanh kéo và hai nút đi qua **cùng một** `adjust`, nên `TokenSpec.clamp()` vẫn là chỗ duy nhất quyết định vùng hợp lệ — kéo `Tối đa` xuống dưới `Tối thiểu` thì nó dừng ở `Tối thiểu`, không tạo ra khoảng ngược.

`check_architecture.py` giữ **14** violation nền, không violation mới. CodeGraph: cập nhật `00`, `02`, `09`, `11`, `12`, `14`. Chưa biên dịch tại chỗ (Windows) — và hành vi cuộn phải thử tay trên máy thật vì nó phụ thuộc lúc nào `UIPageViewController` dỡ trang.

## [1.3.306] - 2026-09-01

### Debug server bỏ hẳn ghép nối: bật là lắng nghe, cổng được ghi nhớ, rời màn hình hay minimize không tắt

Xoá **2** file Swift, thêm **1** file (459 → **458**), sửa **8** file Swift + **1** README.

**Lỗi gốc:** `NWError -65555 (NoAuth)` khi bật server. `NWListener.service` đòi Bonjour được hệ thống cấp cho *chính bundle đang chạy*, mà app chạy qua LiveContainer nên đăng ký mDNS bị từ chối — và vì service gắn vào listener, thất bại đó kéo cả listener sang `.failed`. Bonjour đã bị **bỏ hoàn toàn** (kể cả `NSBonjourServices` trong `project.yml`); đường kết nối là `ws://<ip>:<port>` như một server API thường.

- **Bỏ hẳn tầng ghép nối** theo yêu cầu ("kết nối quá phức tạp"): xoá `ExtensionDebugPairingAuthority` (token 256-bit một lần, hết hạn 3 phút, so sánh hằng thời gian) và `ExtensionDebugPairingQRView` (QR). Giao thức mất lệnh `pair` + 3 mã lỗi pairing; router mất cửa "chưa pair thì không được gì". Đổi lại: khi server bật, **bất kỳ** máy nào cùng Wi-Fi nối được và chạy được script — đã ghi rõ ở mục "Giới hạn đã biết" trên màn hình. Chốt còn lại là `ExtensionDebugInstallGate`: mọi lệnh ghi đè extension vẫn phải bấm trên thiết bị và người bấm thấy trước danh sách `+/~/-` từng file.
- **Cổng cố định + ghi nhớ** (`extDebugServerPort`, mặc định 17772 — tránh 17771 của LocalTTS): lần bật sau mở lại đúng URL cũ nếu cổng còn rảnh. `allowLocalEndpointReuse = true` nên tắt rồi bật lại ngay không bị "address in use". Ba bậc xử lý khi mở thất bại, đúng thứ tự: cổng ghi nhớ đang bận → mở cổng bất kỳ (một lần) → thử lại cùng cổng (≤ 3 lần) → mới báo `.failed`.
- **Vòng đời rời khỏi màn hình và `scenePhase`**: công tắc là `@AppStorage("extDebugServerEnabled")`, chủ sở hữu là `ExtensionDebugServerLauncher` (file mới, 22 dòng). `MainTabView.onChange(scenePhase)` **không** còn gọi `stop()`, và `onAppear` gọi `restoreIfEnabled(container:)` nên mở lại app là server bật lại theo lựa chọn cũ.
- **Không có keep-alive.** Đã cân nhắc cách của `LocalTTS/Services/BackgroundKeepAlive.swift` (vòng lặp gần-im-lặng + `AVAudioSession`) rồi bỏ theo yêu cầu "đừng đụng tới TTS": nó buộc phải sửa đường audio của `TTSManager` (`stopPlayback` gọi `setActive(false)` sẽ tắt session của keep-alive). **Hệ quả phải chấp nhận**: rời màn hình hay minimize thì app không tắt server, nhưng khi iOS treo tiến trình ở nền thì socket ngừng nhận và nhận lại khi app trở lại foreground.
- **Mô hình tham khảo là `LocalHTTPServer` của LocalTTS** (cổng cố định + reuse + tự thử lại), lệch một chỗ có chủ ý: LocalTTS ràng buộc `requiredLocalEndpoint` về `127.0.0.1` vì nó phục vụ app khác trên cùng máy; ở đây client là máy tính khác nên phải nghe trên mọi interface.
- **UI gọn lại** (`ExtensionDebugServerView` 223 → 133 dòng): một `Toggle` bật/tắt, địa chỉ `ws://ip:port` kèm nút sao chép, tên client, và cửa xác nhận cài. Không còn QR, đếm ngược token, hay hàng Bonjour.
- **Client VS Code**: `extension.ts`/`client.ts`/`protocol.ts` đã ở dạng không ghép nối từ trước (`parseTarget` nhận `ws://ip:port`, `ip:port`, và URI cũ — token nếu có thì bỏ qua); lượt này chỉ xoá hằng `SECRET_KEY` chết và sửa lại doc. **Chưa dọn** `transport.ts`/`webSocketTransport.ts`/`mockTransport.ts`/`sidebarView.ts` — chúng còn `pair()` và nút "Pair App" nhưng không nằm trên đường `extension.ts` đang dùng; package TypeScript không được CI biên dịch nên tôi không nửa-refactor 3.900 dòng không build được tại chỗ.

`check_architecture.py` giữ **14** violation nền, không violation mới (mọi file debug ≤ 260 dòng). CodeGraph: cập nhật `02`, `06`, `07`, `08`, `09`, `11`, `13`; `01` ghi nhận `--no-change-needed`. Chưa biên dịch tại chỗ (Windows) — dựa vào CI; và **toàn bộ đường mạng phải xác minh trên máy thật**.

## [1.3.305] - 2026-09-01

### Phiên âm TTS: ép âm tiết tiếng Việt hợp lệ, `j`/`ya` đọc `d`, bỏ âm gió cuối

Sửa **3** file Swift trong `Sources/Services/TTS/Preprocessing/`, không thêm/xoá file. Chưa biên dịch tại chỗ (Windows) — dựa vào CI.

**Lỗi gốc là một chỗ thiếu kiểm tra, không phải mấy ca lẻ.** `IPAToVietnameseMapper.assemble` tra nucleus ở bảng nguyên âm và coda ở bảng coda **độc lập nhau**, nên nó ghép ra được rime không tồn tại trong tiếng Việt. Ba hệ quả đo được: `ơng` ("young" → `dơng`), `âyp` ("april" → `âyp-rơn`), và **mọi** âm tiết đóng bằng `p t c ch` đều không dấu (`trit`, `tat`, `det`) — tiếng Việt không có âm tiết nào vừa đóng bằng phụ âm tắc vừa không dấu. Đầu ra này lại được espeak giọng `vi` phiên âm tiếp cho Piper, nên chuỗi ngoài tiếng Việt bị đọc phẳng hoặc bỏ qua.

- **Dấu thanh** (`stopCodas` + `acuteVowels`): coda ∈ `p t c ch` ⇒ dấu sắc. "street" → `xơ-trít`, "task" → `tát`, "back" → `bác`. Chỉ cần bảng **một ký tự** vì luật nguyên âm đôi bên dưới bảo đảm nucleus của âm tiết có coda luôn là nguyên âm đơn.
- **Nguyên âm đôi không nhận phụ âm cuối** (`diphthongs` = `ây ai oi ao ia ua iu`): `split` đẩy **toàn bộ** cụm phụ âm sang âm tiết sau thay vì đúng một phụ âm, nên "april" ra `ây-pơ-rồ` và "hydro" ra `hai-đơ-rô`. Ở cuối từ (hết âm tiết để đẩy) thì bỏ coda: "email" → `i-mây`, mất `/l/`.
- **`/əl/` ⇒ `ồ`, `/ən/` ⇒ `ình`** (`reducedRimes`, mang dấu huyền): "google" → `gu-gồ`, "colonel" → `cơ-nồ`, "station" → `xơ-tây-sình`. Khoá là **ký hiệu IPA** chứ không phải coda đã map, vì `l`, `ɫ`, `n` đều cho coda `"n"`. Áp cho *mọi* `/ən/` theo yêu cầu người dùng, kể cả ngoài đuôi `-tion`.
- **`/ʌ/` đổi `ơ` → `â`**: `âng âp ât âc âm ân` đều hợp lệ, `ơng` thì không. "young" → `dâng`, "duck" → `đấc`. Nhánh `ă/â → ơ` khi coda rỗng trong `normalize` từ **code chết** thành cần thiết — `â` đứng một mình không phải âm tiết.
- **Bỏ `trailingFiller`**: phụ âm thừa ở cuối bị bỏ chứ không đọc thành âm tiết đệm. "task" → `tát` (không phải `tat-cơ`), "text" → `téc` (không phải `tếc-xơ`). Đảo lại quyết định của 1.3.291 theo yêu cầu người dùng — đánh đổi: mất phụ âm cuối, đổi lấy nhịp đọc không có tiếng lạ.
- **`/j/` ở phụ âm đầu ⇒ `d`** (hàng `j` của bảng **coda** vẫn là `i`, ở đó nó là bán nguyên âm của `ai`/`ây`). Cùng lựa chọn cho `ya/yi/yu/ye/yo` ⇒ `da/di/du/dê/dô` ở `JapaneseTransliterator`. Tiếng Việt không có chữ nào đọc /j/ ở phụ âm đầu; viết `i` thì espeak-vi đọc thành nguyên âm đôi /iə/ nên "yes" và "Yamato" tách thêm một âm tiết. `d` đọc /z/ ở giọng Bắc — sai một phụ âm nhẹ hơn sai số âm tiết.
- **`normalize` xét nguyên âm trước/sau trên chữ đã bỏ dấu thanh.** So trực tiếp với `"iêe"` như bản cũ thì `ế`, `í` trượt luật `k`/`gh`/`ngh` ngay khi bắt đầu có dấu.

**Tiếng Nhật:**

- **Gộp trường âm phải xảy ra trước khi cắt âm tiết** (`collapseLongVowels` trong `normalizeRomaji`). `greedySegment` khớp dài nhất *tại từng vị trí*, nên ở "arigatou" nó ăn `to` rồi bỏ lại `u` thành một âm tiết `ư` thừa — khoá `"ou"`/`"uu"` mà 1.3.291 thêm vào `romajiToViSyllable` **không bao giờ có cơ hội khớp**. Trước lượt này "arigatou" ra `a-ri-ga-tô-ư`, "ryuu" ra `riu-ư`, "shoujo" ra `sô-ư-giô`, "sensei" ra `xên-xê-i`. 7 khoá trường âm đã bị xoá khỏi bảng đọc; `longVowelForms` cố ý **không** chứa `ai/oi/ui/au` vì đó là nguyên âm đôi thật.
- **`i` sau nguyên âm nhập thành rime**: "senpai" → `xên-pai`, "aikido" → `ai-ki-đô`, "sui" → `xưi` (u Nhật là /ɯ/ nên `ưi`, không phải `ui`). Chỉ nhập vào âm tiết kết thúc bằng nguyên âm khác `i`/`y`.
- **`findMergedIndex` bị thay bằng `mergedIndexOfSyllable`** dựng một lần trong vòng nhập. Vị trí sokuon tính trên mảng âm tiết *romaji* còn coda phải gắn vào ô của mảng *đã nhập*; hàm cũ tự suy lại ánh xạ và chỉ biết luật `"n"`, nên có luật nhập thứ hai là sokuon gắn lệch âm tiết.

**Bộ ca kiểm** (`TransliterationGoldenSet`): thêm 7 ca Nhật (`ryuu`, `sensei`, `shoujo`, `senpai`, `aikido`, `kouhai`, `sui`), sửa kỳ vọng 13 ca theo các quyết định trên. Ba ca **để đỏ có chủ ý**, ghi rõ `ĐỎ` kèm lý do: `/w/` ở phụ âm đầu map thành `o` nên "one"/"wish" ra `oân`/`oích` (không phải tiếng Việt), và `/ð/` map thành `đ` nên "though" ra `đô` — chưa có quyết định về đích.

**Chưa đối chiếu chuỗi IPA thật của espeak.** Mọi luật ở lượt này thiết kế trên IPA en-us chuẩn (`ˈeɪpɹəl`, `tæsk`, `stˈeɪʃən`). Hai luật nhạy cảm nhất với chuyện espeak viết gì là `/əl/` và `/ən/`: nếu espeak phát ra phụ âm âm tiết tính (`l̩`, `n̩`) thì `stressMarks` xoá dấu `̩` và cả hai luật trượt — "google" sẽ ra `gúc`. Màn **Thử phiên âm** là chỗ phát hiện ngay lượt chạy đầu.

`check_architecture.py` giữ **14** violation nền, không violation mới; ba file sửa đều dưới trần 400 (`IPAToVietnameseMapper` 210 → 271, `JapaneseTransliterator` 311 → 341, `TransliterationGoldenSet` 117 → 128). Đầu ra của cả 12 ca Nhật và 22 ca Anh đã đối chiếu bằng mô phỏng thuật toán trên **chính** các bảng trong file (không gõ lại bảng), nhưng **chưa** nghe thử trên máy thật.

Nhân tiện sửa bốn chỗ doc đã trôi so với code: `04` ghi `ー → nhân đôi nguyên âm` (sai từ 1.3.291) và ngưỡng phân loại `≥ 2` (thật là 4), `10` cũng ghi `japaneseThreshold = 2`, và `00`/`04`/`10` đều lấy "street" → `xơ-tơ-rít` làm ví dụ — sai ngay từ 1.3.291 vì `legalDoubleOnsets` vốn đã giữ `tr` liền.

CodeGraph: cập nhật `00`, `04`, `10`, `14`; `11`, `13`, `rules` ghi nhận `--no-change-needed`. Validator **chưa PASS** vì `01`, `02`, `06`, `07`, `08`, `09` còn stale do phần debug server chưa commit trong cây (`ExtensionDebugServerLauncher.swift` chưa được tài liệu nào nhắc; `02`/`09` còn link tới `ExtensionDebugPairingAuthority.swift` và `ExtensionDebugPairingQRView.swift` đã xoá) — không thuộc lượt này.

## [1.3.304] - 2026-09-01

### Debug server: Bonjour thành tuỳ chọn, kết nối thẳng ws://ip:port như một server API thường

Sửa **3** file Swift, **1** README.

- **Bật server báo `NWError -65555 (NoAuth)` rồi chết**: `NWListener.service` đòi Info.plist/entitlement được hệ thống cấp cho *chính bundle đang chạy*, mà app chạy qua LiveContainer nên đăng ký mDNS bị từ chối. Vì service gắn vào listener, thất bại đó kéo cả listener sang `.failed` — **server chết dù cổng TCP đã mở xong** (đúng như ảnh: có cổng 53351 nhưng trạng thái Lỗi).
- **Bonjour hạ xuống tuỳ chọn, mặc định tắt** (`@AppStorage("extDebugAdvertiseBonjour")`). Đường kết nối chính là `ws://<ip>:<port>`: máy tính cùng Wi-Fi nối thẳng vào, không cần mDNS.
- **Thất bại Bonjour không còn là lỗi chí mạng**: `handleListenerState` bắt `.failed` khi đang quảng bá rồi **dựng lại listener không Bonjour**, giữ nguyên token đang hiện trên QR, và báo bằng `bonjourNote` (ghi chú) thay vì `failureMessage`. `didFallbackFromBonjour` chặn vòng lặp — fallback đúng một lần.
- **UI hiện địa chỉ kết nối** (`ExtensionDebugServerStatus.websocketEndpoint`) kèm nút sao chép; hàng Bonjour chỉ hiện khi listener **thật sự** đang quảng bá.

Giao thức, pairing và cửa xác nhận **không đổi**: vẫn WebSocket `freebook-extdebug.v1`, token một lần + phải bấm đồng ý trên thiết bị. Bỏ Bonjour chỉ bỏ bước *tìm thấy nhau*, không bỏ bước *được phép*.

`check_architecture.py` giữ **14** violation nền, không violation mới. CodeGraph: cập nhật `11`, `13`; `07` ghi nhận `--no-change-needed`. Chưa biên dịch tại chỗ (Windows) — dựa vào CI.

## [1.3.303] - 2026-09-01

### Debug extension Phase 2–4: server LAN có pairing, snapshot nháp, cài + rollback, và client VS Code

Thêm **18** file Swift mới (441 → **459**), sửa **3** file, thêm **1** package VS Code (`Tools/VSCode/FreeBookExtDebug`, TypeScript — ngoài target iOS, **không** được CI biên dịch). Hoàn tất Phase 2, 3, 4 của `Docs/Plans/2026-08-23-plan-debug-ext-app-server.md`.

**Phase 2 — app server trên LAN:**
- `ExtensionDebugServer` (actor): `NWListener` + `NWProtocolWebSocket` + Bonjour `_freebook-extdebug._tcp`, **port ngẫu nhiên**, **tối đa một client**, bật/tắt bằng tay ở Cài Đặt → Nhà Phát Triển → Debug Server (LAN). `MainTabView` tắt hẳn khi app rời foreground.
- `ExtensionDebugPairingAuthority`: token 256-bit **dùng một lần**, hết hạn 3 phút, so sánh hằng thời gian. Token đúng **chỉ mở cửa xin phép** — phải bấm "Cho phép kết nối" trên thiết bị mới có session.
- `ExtensionDebugCommandRouter` (+`+Draft`): chỗ **duy nhất** cưỡng chế "chưa pair thì không được gì". Thực thi `hello`, `pair`, `extensions.list`, `run.start`, `run.cancel`, `run.get`, `events.subscribe`.
- `ExtensionDebugProtocol`: envelope v1 + 13 `CommandType` + 13 `ErrorCode`, payload phẳng `Codable` (không `[String: Any]`).
- UI: `ExtensionDebugServerView` (trạng thái, cổng, Bonjour, QR + chuỗi pairing, approve/reject, Stop), `ExtensionDebugServerReader`, `ExtensionDebugPairingQRView`.
- `project.yml`: thêm `NSLocalNetworkUsageDescription` + `NSBonjourServices`.

**Phase 3 — snapshot nháp:**
- `draft.stage` (manifest khai trước path/size/sha256) → nhiều `draft.chunk` → `draft.finish` (đối chiếu checksum, rồi `ExtensionDraftValidator` kiểm `plugin.json`, containment script, `load(...)`, cú pháp). Chỉ revision đã qua `finish` mới chạy được với `sourceMode: "draft"`.
- `ExtensionDraftStagingStore` (actor) sở hữu `applicationSupportDirectory/extension-drafts/` — **ngoài** `extensions/`, xoá sạch lúc khởi động app và lúc tắt server. Hai lớp kiểm path (`pathIssue` + containment sau `standardizedFileURL`); không giải nén archive nào nên không có symlink/zip bomb.
- Storage/cookie/localStorage của bản nháp **tự** tách khỏi production: `JSExecutor` dùng tiền tố `vbook_ext_storage_<md5(localPath)>_`.

**Phase 4 — cài bản staged và rollback:**
- `draft.install`/`draft.rollback` **treo** ở `ExtensionDebugInstallGate` cho tới khi người dùng bấm trên thiết bị, và người bấm thấy trước danh sách `+/~/-` từng file (`ExtensionDraftInstaller.changeSummary`).
- Bản cũ được copy sang `.backup/<packageId>/` **trước** khi thay; thay bằng `FileManager.replaceItemAt` (nguyên tử, cùng volume). Không auto-commit khi VS Code save.

**Client VS Code**: 10 command, OutputChannel làm trace, `DiagnosticCollection` chỉ gắn khi `sourceRevision` còn khớp (không khớp thì ghi `(stale)`), token chỉ ở `SecretStorage`, `src/protocol.ts` là mirror của Swift.

**Hai chỗ lệch chốt Phase 0, đã ghi rõ**: pairing URI **có thêm `host`** (IP nội bộ) để client chỉ cần một thư viện WebSocket thay vì dependency mDNS — IP không phải bí mật, token vẫn là thứ được bảo vệ; và unsaved-overlay của Phase 3 **chưa làm** (chỉ có saved snapshot).

`check_architecture.py` giữ **14** violation nền, **không violation mới**: 18 file mới đều ≤ 400 dòng và một primary type (router phải tách `+Draft` để không chạm trần). CodeGraph: cập nhật `00`, `01`, `02`, `03`, `04`, `06`, `07`, `08`, `09`, `10`, `11`, `13`, `14`, `rules`. Chưa biên dịch tại chỗ (Windows) — dựa vào CI; và toàn bộ đường mạng/Bonjour/permission **phải xác minh trên máy thật**, simulator không đại diện.

## [1.3.302] - 2026-09-01

### Debug extension Phase 0–1: structured trace nội bộ và runner execute(...), chưa mở server

Thêm **13** file Swift mới (428 → **441**), sửa **2** file hiện có. Triển khai Phase 0–1 của `Docs/Plans/2026-08-23-plan-debug-ext-app-server.md`; Phase 2–4 (NWListener, Bonjour, WebSocket, VS Code client, draft snapshot) **chưa làm**.

**Phase 0 — đã chốt và ghi vào plan**: 7 entrypoint được phép (`search`/`detail`/`toc`/`chap`/`genre`/`home`/`custom`; `page` và TTS ngoài MVP), schema event v1, chính sách redact allowlist, quota 600 event/run + 2000/hub, command IDs + vị trí package VS Code, policy `ws` vs `wss`, và xác nhận Phase 1 **không** cần thêm khoá `Info.plist`/`project.yml`.

**Phase 1 — tầng Services (9 file)**:
- `ExtensionDebugEvent` (contract v1, `Codable`), `ExtensionDebugSourceLocation` (script path **tương đối** + line/column + revision), `ExtensionDebugEventSink` (protocol đồng bộ), `ExtensionDebugRedactor`, `ExtensionDebugEventHub` (actor: ring buffer + quota + `AsyncStream`), `ExtensionDebugSession` (sink của một run), `ExtensionDebugEntrypoint` (typed arguments), `ExtensionDebugRunner` (actor: chạy/huỷ), `JSExecutor+Debug` (5 điểm phát).
- `JSExecutor` nhận `debugSink: ExtensionDebugEventSink?` mặc định `nil`; hook ở console, exception handler, compile fail, cancel, native fetch (start/finish/fail + status/duration/bytes). Mọi điểm phát `guard let sink else { return }` nên đường production chỉ trả thêm một phép so `nil`.
- **`ExtensionManager.swift` không đổi một dòng nào**: runner gọi lại `getScriptPath` / `getCombinedConfigs` / `verifyJSResponse` / `compactRepresentation` (`internal`, cùng module). Summary kết quả dùng `compactRepresentation` chứ không `stringify` để nội dung chương không vào trace.

**Phase 1 — tầng Views (4 file)**: `ExtensionDebugConsoleView` (chọn extension/entrypoint/input, chạy, huỷ, xem trace), `ExtensionDebugTraceReader` (projection reader đọc hub), `ExtensionDebugEventRow`, `DeveloperSettingsSection`. Vào từ **Cài Đặt → Nhà Phát Triển → Debug Extension**. Trace **không** phụ thuộc `AppLogger.isLoggingEnabled`.

**Ba chỗ cố ý lệch plan** (ghi rõ trong plan + `11_subsystems`): `ExtensionDebugSession` là `final class` chứ không `actor` (sink bị gọi đồng bộ trong `@convention(block)` của JSC và callback `URLSession`); `ExtensionManager` không nhận tham số sink; `runStarted`/`runFinished` do runner phát chứ không phải executor.

`check_architecture.py` giữ **14** violation nền, **không violation mới**: 13 file mới đều ≤ 400 dòng và một primary type; `JSExecutor.swift` 1516 → 1553 (violation cũ, không loại mới); `SettingsView.swift` 447 → 450 vẫn dưới baseline 453 nhờ tách `DeveloperSettingsSection.swift`. CodeGraph: cập nhật `00`, `02`, `07`, `09`, `10`, `11`, `13`, `14`, `rules`. Chưa biên dịch tại chỗ (Windows) — dựa vào CI.

## [1.3.301] - 2026-09-01

### Rule dịch số: cặp chữ số Hán trần là khoảng "từ mấy đến mấy", không phải số ghép

Sửa **1** file Swift.

- **`四五岁` bị dịch thành `45 tuổi` thay vì `4 đến 5 tuổi`**: token `<n>` gặp chuỗi không có ký tự bậc thì rơi xuống `renderDigitwise`, tức nối chữ số lại (`四五` → `45`). Nhưng tiếng Trung viết 45 là `四十五`, nên **hai chữ số Hán trần liền nhau luôn là idiom khoảng xấp xỉ**. Thêm nhánh `approximateRange` trong `renderNumeral`: thay cặp đó lần lượt bằng từng chữ số rồi đọc cả chuỗi như một số thường, nên một nhánh phủ mọi vị trí của cặp số — `四五` → `4 đến 5`, `十七八` → `17 đến 18`, `三十四五` → `34 đến 35`, `二三十` → `20 đến 30`, `三四百` → `300 đến 400`.

**Ba cửa hẹp giữ hành vi cũ** (cố ý bảo thủ, sai sót nghiêng về "giữ nguyên như trước"):
- Phải có **đúng một** dãy chữ số Hán trần, dãy dài **đúng hai**, và hai chữ số **tăng liền bậc**. Nhờ vậy `二零二五` → `2025` (dãy 4 chữ số, đọc từng chữ), `零五` → `05` và `一〇` → `10` (không liền bậc) không đổi.
- Chuỗi digit ASCII/full-width thoát ở nhánh đầu của `renderNumeral`, nên `"45"` gõ tay không bao giờ bị đổi thành khoảng.
- `<y>`, `<h>`, `<d>` là các token *đọc từng chữ số* theo đặc tả nên **không** đổi; chỉ `<n>` đổi.

Dọn theo: phần đọc số Hán tách ra `parseChineseNumeral(_:) -> Int?` để `renderNumeral` và `approximateRange` dùng chung một bản; ngữ nghĩa cộng dồn theo section (`一万亿` = `100010000`) và hành vi trả nguyên văn khi tràn giữ nguyên.

Không thêm token, không thêm khoá cấu hình, `Configuration.signature` không đổi nên snapshot/cache rule không bị vô hiệu. `check_architecture.py` giữ **14** violation (file này 161 → 226 dòng, vẫn dưới trần 400). CodeGraph: cập nhật `07`, `11`. Chưa biên dịch tại chỗ (Windows) — dựa vào CI.

## [1.3.300] - 2026-09-01

### Hẹn giờ tắt TTS: pause chỉ tạm dừng bộ đếm, phát lại thì đếm tiếp thay vì đếm lại từ đầu

Sửa **1** file Swift.

- **Pause rồi phát lại thì hẹn giờ đếm lại từ đầu**: `restartSleepTimerIfNeeded()` gọi thẳng `startTimerCountdown(minutes:)`, mà hàm này nạp `sleepTimerRemainingSeconds = minutes * 60`. Nay hàm phân ba ca — đang chạy thì không làm gì, còn giây dư thì `resumeTimerCountdown()` đếm tiếp, hết giờ rồi (remaining == 0, mode vẫn còn) mới nạp một vòng mới. Phần schedule `Timer` tách ra `scheduleSleepTimerTick()` để hai đường dùng chung.

**Hai lỗi cùng đường tìm thấy khi sửa:**
- **`stopPlayback()` không dừng bộ đếm**: dừng phát hoàn toàn rồi `Timer` vẫn tick tới 0 và bắn toast "đã tự động tạm dừng đọc" trong lúc không có gì phát. Thêm `stopTimerCountdown(keepMode: true)` — giữ `timerMode` + số giây còn lại để lượt phát sau đếm tiếp, cùng luật với `pause()`.
- **Badge hẹn giờ trống khi tạm dừng**: `sleepTimerBadgeText` đòi `isTimerRunning`, mà `pause()` đặt cờ đó về `false`, nên hẹn giờ trông như đã bị huỷ. Điều kiện hiển thị đổi thành `sleepTimerRemainingSeconds > 0` — chỉ `cancelSleepTimer`/`setStopAtEndOfChapter` mới đưa số này về 0.

`check_architecture.py` giữ **14** violation (`TTSManager.swift` 4001 → 4023, vẫn là violation cũ, không phát sinh loại mới). CodeGraph: cập nhật `05`, `06`, `13`; `04`, `08`, `10`, `11`, `rules` ghi nhận `--no-change-needed`. Chưa biên dịch tại chỗ (Windows) — dựa vào CI.

## [1.3.299] - 2026-09-01

### Sửa 4 lỗi còn lại của cài đặt trình đọc: chiều cao sheet, 2 toggle tiêu đề chương, mở tab Cài Đặt, kiểu chữ 1 dòng

Sửa **4** file Swift. Chưa biên dịch (viết trên Windows — không có macOS).

**Sửa lỗi do 1.3.298 để lại:**
- **Cây làm việc của 1.3.298 không biên dịch được**: `ReaderView` vẫn truyền `onToggleChapterTitle:` / `onToggleRemoveDuplicatedTitle:` cho `ReaderHeaderFooterOverlayView` sau khi hai tham số đó đã bị xoá khỏi overlay. Đã gỡ ở call site.
- **Hai toggle tiêu đề chương không có tác dụng**: `ReaderSettingsView` bind thẳng vào `@State` của `ReaderView`, nhưng nguồn sự thật lúc dựng đoạn là `UserDefaults` (`processAndSaveChapter` đọc `showChapterTitle_<bookId>` / `removeDuplicatedTitle_<bookId>`). Nay `Toggle` dùng `Binding` tự dựng: setter ghi `@State` rồi gọi `onShowChapterTitleChanged` / `onRemoveDuplicatedTitleChanged` → `ReaderView+Controls.applyShowChapterTitle` / `applyRemoveDuplicatedTitle` (lưu khoá + dựng lại đoạn). Hai hàm `toggleChapterTitleVisibility` / `toggleRemoveDuplicatedTitle` được thay bằng hai hàm `apply…` nhận giá trị mới, vì việc flip giờ thuộc setter của binding.
- **"Mở Cài đặt" trong dropdown không hoạt động**: observer `navigateToSettingsTab` ở `MainTabView` vẫn đúng, nhưng Reader nằm trong `fullScreenCover` nên tab đổi *bên dưới* cover. Thêm `dismiss()` trước khi phát notification.
- **Bảng cài đặt bị cắt hàng cuối**: `ScrollView` + `.presentationDetents([.fraction(0.75), .large])` thay chiều cao cố định `.height(500)`/`.height(600)` — nội dung co giãn theo việc bật dịch (3 hàng phụ) nên mọi con số cố định đều cắt ở một cấu hình nào đó. Thêm `presentationDragIndicator(.visible)`.
- **Kiểu chữ vẫn xuống 2 dòng**: nhãn thu gọn của `Picker(.menu)` do hệ thống dựng nên không nhận chắc `lineLimit`. Đổi sang `Menu` chứa `Picker`, nhãn tự dựng (`Text(fontFamily.rawValue).lineLimit(1).truncationMode(.tail)` + `chevron.up.chevron.down`).

**Dọn theo:**
- `ReaderViewModel.invalidateParagraphLayoutForCachedChapters()` (mới, `ReaderViewModel+Translation`): hạ `translationToken = 0` cho mọi chương khác rồi `refreshParagraphItems()`, để chương đã cache không giữ `paragraphItems` dựng theo cờ cũ. Cùng cơ chế `updateCachedTranslatedContent` dùng cho đổi từ điển.
- Xoá `@State showingTOCRules` / `showingJunkFilterManagerSheet` và hai `.sheet` tương ứng khỏi `ReaderView` (1.3.298 gỡ hai mục menu nhưng để lại state không còn lối phát); xoá 4 `@Binding` chết khỏi `ReaderHeaderFooterOverlayView`. `TOCRulesConfigView` / `JunkFilterManagementView` vẫn vào được từ tab Cài Đặt.

`check_architecture.py`: **15 → 14** violation (`ReaderView.swift` 2079 → 2051, về dưới baseline 2053). Không violation mới. CodeGraph: cập nhật `04`, `05`, `08`, `10`, `11`, `13`; `07`, `rules` ghi nhận `--no-change-needed`.

## [1.3.298] - 2026-09-01

### Fix sleep timer khi pause TTS, cải tiến UI trình đọc, cache chi tiết truyện & Discovery tabs

Thêm **1** file Swift mới (`BookDetailCacheManager`), sửa **7** file Swift hiện có.

**Fix lỗi:**
- **Sleep timer vẫn đếm ngược khi pause TTS**: Thêm `stopTimerCountdown(keepMode: true)` vào `TTSManager.pause()` để tạm dừng bộ đếm khi người dùng tạm dừng đọc; `resume()` đã có `restartSleepTimerIfNeeded()` sẽ tự tiếp tục.

**Cải tiến UI Trình đọc (Reader):**
- **Nút cài đặt ra khỏi dropdown**: Thêm nút `gearshape` (44×44) đứng giữa nút `reload` và dropdown `ellipsis` trên header.
- **Chuyển 2 toggle vào cài đặt**: "Hiển thị tên chương trong nội dung" và "Loại bỏ tiêu đề chương trùng trong nội dung" từ menu `ellipsis` chuyển vào `ReaderSettingsView` thành 2 `Toggle` trực tiếp.
- **Font picker limit 1 dòng**: Thêm `.lineLimit(1)` cho text trong picker chọn kiểu chữ.
- **Bỏ "Quản lý lọc rác" khỏi cài đặt trình đọc**: Xoá button mở `JunkFilterManagementView` khỏi `ReaderSettingsView`.
- **Dropdown menu**: Xoá "Quy tắc mục lục (TOC)" và "Quản lý lọc rác"; thêm "Mở Cài đặt" → điều hướng đến tab Settings (index 3) qua `NotificationCenter`.

**Cache hiệu năng:**
- **BookDetailView**: Thêm `BookDetailCacheManager` cache in-memory (TTL 5 phút) cho dữ liệu chi tiết truyện (title, author, cover, desc, detail, genres, suggests, comments, host). Quay lại từ genres/comments không tải lại.
- **DiscoveryView**: Mở rộng `shouldRenderCategoryTab` từ ±1 tab sang **±3 tab** (giữ 7 tab cùng lúc) để cache nhiều tab hơn mà không quá tốn bộ nhớ.

`check_architecture.py` giữ **15 violation** (baseline cũ). CodeGraph: cập nhật `00`, `02`, `03`, `06`, `08`, `09`, `11`, `12`, `14`; `04`, `05`, `10`, `13`, `rules` ghi nhận `--no-change-needed`.

## [1.3.297] - 2026-08-31

### Kết quả E1, và bộ phân loại Nhật/Anh quay về whitelist

Thêm **1** file Swift (426 → 427), sửa 2 file. Chưa biên dịch (viết trên Windows).

**Kết quả E1 trên iPhone 11:**

* **Phủ âm vị: 0 scalar ngoài từ vựng.** espeak `en-us` trên 24 từ không sinh ký hiệu nào ngoài 161 ký hiệu của model ⇒ **tầng tra id không mất chữ**, toàn bộ hiện tượng "mất chữ nhiều" nằm bên trong `IPAToVietnameseMapper`.
* **Nghe thử: `θˈɪŋk` đúng, `ðˈɪs` và `kˈæt` sai.** Xác nhận đúng cái bẫy đã nêu ở 1.3.296: có mặt trong từ vựng không đồng nghĩa với đã được train. Hướng đi vì vậy là **hybrid** — đưa IPA thẳng vào model nhưng thay ký hiệu chưa train bằng ký hiệu gần nhất đã train (`ð → z`, `æ → ɛ`), không phải passthrough toàn bộ.
* **Ca đối chứng của tôi sai, không phải dụng cụ sai.** `sˈaːw` không phải IPA của "sao" nên nghe ra "chao" là đúng với chuỗi đã đưa vào. Thêm nút lấy IPA **thật** từ espeak `vi` rồi tổng hợp lại chính chuỗi đó — đối chứng tự kiểm chứng thay vì tự đoán.
* Thêm phép **so bộ ký hiệu `vi` vs `en-us`**: model là Piper tiếng Việt nên tập âm vị đã train chính là tập espeak `vi` sinh ra; ký hiệu chỉ có ở `en-us` là ứng viên chưa train. Một lần bấm thay cho nghe thử từng ký hiệu.

**Bộ phân loại Nhật/Anh — 8/24 ca sai, và đó là giới hạn của phương pháp:**

* `sakura`/`sonata`, `kimono`/`tomato`, `karate`/`potato`, `nakama`/`banana` giống nhau trên **mọi** dấu hiệu bề mặt: 6 chữ, CVCVCV, kết thúc nguyên âm, không cụm phụ âm Anh, không âm đặc trưng Nhật. Không hàm chấm điểm nào tách được chúng; mọi ngưỡng đều sai một phía.
* 1.3.290 bỏ `englishBlacklist` với lý do **đúng** ("tập từ tiếng Anh cần loại trừ là vô hạn") nhưng kết luận **sai**. Điều nó bỏ sót: **hướng** của danh sách quan trọng hơn sự tồn tại của nó. Tập từ gốc Nhật xuất hiện trong truyện tiếng Việt là **hữu hạn và nhỏ**. Nay `JapaneseLoanwordList` (~200 từ) là lớp quyết định thứ nhất; hàm chấm điểm chỉ xử lý từ lạ.
* **Hai lỗi chấm điểm đo được, đã sửa**: (1) `ou`/`ai`/`ei`/`oi` nằm trong `englishClusters` và **bị trừ** 2 điểm dù chúng là dãy nguyên âm romaji hoàn toàn hợp lệ — đó chính là lý do `arigatou`, `senpai`, `hokkaido`, `shoujo` bị xếp sai thành tiếng Anh; nay chúng **cộng** 2 điểm. (2) Bỏ luật "từ dài mà không có cụm phụ âm Anh (+1)": mọi từ gốc Latin trong tiếng Anh (tomato, potato, sonata, banana, camera, opera, pasta) đều là CVCVCV không cụm phụ âm, nên luật đó cộng điểm cho đúng nhóm cần loại.
* Ngưỡng 2 → **4**: whitelist đã gánh ca phổ biến nên hàm chấm điểm được phép bảo thủ và nghiêng về tiếng Anh. Trong truyện dịch, từ tiếng Anh nhiều hơn từ Nhật cả bậc; đọc một từ Nhật lạ theo luật Anh là sai nhẹ hơn chiều ngược lại.

**Cố ý chưa sửa**: thiếu dấu thanh trong `IPAToVietnameseMapper` (bộ ca kiểm cho "bac"/"xit-tơm"/"iet"/"tec-xơ" — âm tiết Việt kết thúc bằng `-c`/`-t` mà không có thanh là sai phonotactics) và `arigatou → a-ri-ga-tô-ư`. Cả hai chỉ còn quan trọng nếu E1 vòng 2 kết luận phải giữ đường phiên âm sang chữ Việt.

`check_architecture.py` giữ **14 violation** đúng cùng một tập. CodeGraph: cập nhật `00`, `02`, `04`, `10`, `14`; `09`, `11`, `13`, `rules` ghi nhận `--no-change-needed`.

## [1.3.296] - 2026-08-31

### Dụng cụ đo cho phiên âm: nghe IPA thô và đếm ký hiệu ngoài từ vựng model

Thêm **3** file Swift (423 → 426), sửa 2 file. **Không** đổi đường tổng hợp đang chạy — lượt này ship *thước đo*, chưa phải bản sửa. Chưa biên dịch (viết trên Windows).

* **Phát hiện đảo ngược giả định của cả 1.3.290 và 1.3.291.** Tải `phoneme_id_map` của model đang dùng (`raikiri1498/nghitts/models/ngoc_huyen_moi.onnx.json`) và đếm: **161 ký hiệu, và nó là bộ IPA đầy đủ**, không phải bộ âm vị tiếng Việt. Có đủ mọi ký hiệu espeak `en-us` sinh ra (`æ ð θ ŋ ɑ ɔ ɛ ə ɚ ɜ ɝ ɪ ʊ ʌ ʃ ʒ ɹ ɫ ɾ ᵻ ɐ ˈ ˌ ː`; `tʃ`/`dʒ` là hai scalar rời nên cũng đủ) và mọi ký hiệu tiếng Nhật cần (`ɕ ʑ ɸ ɲ ŋ ɾ ː`). Nghĩa là **đưa IPA tiếng Anh thẳng vào chuỗi phoneme là hợp lệ về từ vựng**, và cả vòng "IPA → chữ Việt → text → phiên âm lại" — nguồn của cả sai lệch lẫn mất chữ — có thể bỏ được.
* **Nhưng có mặt trong từ vựng không có nghĩa là đã được train**, nên không refactor gì trong lượt này. 161 ký hiệu là bảng chuẩn Piper phát cho *mọi* giọng, không phải bằng chứng dữ liệu huấn luyện tiếng Việt từng chứa `θ`, `ð`, `æ`. Đây đúng là cái bẫy đã gặp ở lượt VieNeu (`style token 18` có tên `doc_truyen` nhưng nằm trong vùng random-init). Phải **nghe** trước.
* **`PiperPhonemeInventory`**: đọc `phoneme_id_map` từ `<giọng>.onnx.json`, `missingScalars(in:)` đếm scalar ngoài từ vựng kèm tần suất, và bảng `downgrade` hạ cấp ký hiệu không có về ký hiệu có (`ɴ→n`, `ʧ→tʃ`, `ʨ→tɕ`, tie bar → bỏ có chủ ý, `|→_`). Bảng này được **gieo từ chính phép đo inventory**, không phải đoán; ký hiệu chưa biết trả `nil` để bị **đếm** thay vì bỏ im lặng.
* **`ONNXPiperEngine+Phonemes`**: `synthesizeRawPhonemes(_:)` chạy model trên **đúng** chuỗi IPA cho trước, không chunk, không phiên âm, không chuẩn hoá âm lượng theo chuỗi. Đây là điểm cốt lõi của phép đo: mọi đường hiện có đều đi qua `IPAToVietnameseMapper` nên **không tách được** lỗi của model khỏi lỗi của tầng phiên âm. Là file riêng vì `ONNXPiperEngine.swift` đang ở **đúng** baseline 469 dòng và chỉ được phép giảm; `CachedRuntime`/`getRuntime` đổi `private` → internal bằng cách đổi từ khoá, **không thêm dòng**.
* **`TTSIPAProbeSection`** ở màn Thử phiên âm: ô nhập IPA thô kèm 7 nút preset (`həlˈoʊ`, `stɹˈiːt`, `θˈɪŋk`, `ðˈɪs`, `kˈæt`, `ɾaːmen`, và một ca tiếng Việt đối chứng), phát ngay qua `AVAudioPlayer`; cộng bảng phủ âm vị chạy espeak `en-us` trên 24 từ rồi liệt kê scalar nào ngoài từ vựng. Là `View` riêng chứ không phải extension vì state của `TTSTransliterationTesterView` là `private`. Engine giữ trong `@State` để không dựng `ORTSession` mới mỗi lần bấm; 24 lượt espeak nằm trong `Task.detached` vì đó là lời gọi C có khoá.
* **Cổng quyết định cho lượt sau**: nghe được tiếng Anh ⇒ chuyển quyết định ngôn ngữ xuống **tầng phoneme** (`TTSPhonemeStreamBuilder` tách span, phiên âm từng span bằng đúng giọng, ghép IPA; `JapaneseRomajiIPA` cho tiếng Nhật, đảo lại quyết định bỏ `ー` của 1.3.291 vì `ː` có trong từ vựng). `θ ð æ` ra tiếng lạ ⇒ giữ hướng phiên âm sang âm Việt nhưng dùng bảng đếm để bổ sung `IPAToVietnameseMapper` cho đúng chỗ đang bị bỏ.
* `check_architecture.py` giữ **14 violation** đúng cùng một tập; 3 file mới đều ≤ 400 dòng và đúng 1 type top level. CodeGraph: cập nhật `00`, `02`, `04`, `10`, `14`; `09`, `11`, `13`, `rules` ghi nhận `--no-change-needed`.

