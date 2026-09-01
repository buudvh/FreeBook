# CHANGELOG - Nhật ký Thay đổi CodeGraph FreeBook

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **FreeBook**.

> Chỉ giữ các version gần đây. Lịch sử cũ hơn (≤ 1.3.272) nằm ở [CHANGELOG.archive.md](CHANGELOG.archive.md).

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

## [1.3.295] - 2026-08-31

### Revert toàn bộ engine VieNeu-TTS

Revert ba commit `1.3.292`–`1.3.294` (25 file mới, 8 file sửa). Cây code trở lại đúng trạng thái `1.3.291`: 423 file Swift, `check_architecture.py` 14 violation nền, `validate_links.py` PASS. Không xoá bằng `reset --hard` mà bằng `git revert` nên lịch sử vẫn tra cứu được nếu muốn làm lại.

**Lý do**: audio trên iPhone 11 ra nhiễu và không giống tiếng Việt, app dễ crash, khoảng cách giữa hai chunk lớn. Sau khi đối chiếu số học với engine tham chiếu Python thì lỗi nằm ở **bản port Swift**, không ở model — nhưng chưa khoanh được tầng nào, và chi phí giữ một engine chưa dùng được trong cây code cao hơn giá trị của nó.

**Giữ lại ở đây những gì đã kiểm chứng được, để lần sau không phải làm lại:**

* **Bộ `onnx_int8` không hỏng.** Engine tham chiếu Python chạy trên đúng bộ đó cho 4.56 s audio, peak 0.58, rms 0.12 — tỉ lệ rms/peak 0.21 là đặc trưng tiếng nói (ồn trắng cho 0.5–0.7).
* **Thuật toán speaker anchor đúng**: GEMV `NoTrans` trên `xvec_w` (768,192) rồi LayerNorm phương sai **toàn phần** cho `max|Δ| = 7.45e-09` so với `_speaker_anchor`.
* **Layout npz**: `text_emb` (419,768) fp32, `audio_emb` (16,1024,768) fp32, C-contiguous, npz **stored** (không nén) ⇒ chỉ số phẳng `(ch*1024 + code)*768 + h` là đúng.
* **Tokenizer**: id của **mọi** phoneme giống nhau giữa `tokenizer.json` gốc và bản `onnx_int8`; chỉ 30 nhãn `<|reserved_N|>` bị đổi số. `<|unk|>` = 43, vocab phoneme bắt đầu ở 44 ở cả hai.
* **Token dẫn đầu prompt = 16 là đúng, nhưng vì lý do khác 1.3.292 ghi**: trong tokenizer của `onnx_int8`, id 16 là `<|style_0|>` — token **thật, đã train** — và ô dự trữ bắt đầu ở **26**, không phải 13. Ghi chú `reserved_token_start = 13` trong `config.json` mô tả cách đánh số của bộ **gốc**.
* **`ORTSessionOptions.addConfigEntry(withKey:value:)` có** trong binding ObjC của phiên bản ORT đang pin; contrib op int8 biên dịch được. Hai rủi ro build đó không còn phải lo nếu làm lại.
* **Số đo trên iPhone 11 (bộ fp32, 84 frame = 6.72 s audio)**: decode step 19.92 ms/frame ≈ **20.8 GB/s** — thuần bị chặn băng thông; acoustic 7.93 ms/frame; lấy mẫu 2.86 ms/frame; prefill 0.461 s; codec 1.342 s. Vòng AR 31.25 ms/frame ≈ 2.6× realtime, nhưng `thermal=serious` và `[NghiEnergy] Underrun` xuất hiện chỉ 3 giây sau khi bắt đầu phát.
* **Bản port Swift chưa từng được chứng minh là cho ra audio đúng.** Bản thử nghiệm chạy `active_vq = 8`, thứ làm tiếng đục vì codec là RVQ residual.

**Chưa khoanh được**: lỗi ở đâu trong cơ chế Swift (xử lý `ORTValue`, tuổi thọ buffer, hay vòng `VieNeuDecodeLoop`). Nếu làm lại thì bước đầu tiên là dựng lại bộ tự kiểm greedy 1 frame và so 16 code của frame đầu với giá trị tham chiếu — code khớp thì lỗi ở codec/hậu xử lý, code lệch thì lỗi ở vòng sinh.

## [1.3.291] - 2026-08-31

### Chống mất chữ khi phiên âm, trường âm Nhật đọc như âm ngắn, xoá tất cả phiên âm

- **Sửa lỗi đọc mất chữ.** Truy ra **5 chỗ bỏ chữ im lặng**: `ONNXPiperEngine` bỏ mọi unicode scalar không có trong `phoneme_id_map` (chỉ log); `IPAToVietnameseMapper` bỏ ký hiệu IPA lạ, xoá âm tiết không dựng được, giữ **một** phụ âm mỗi đầu cụm; bộ luật chính tả cắt phụ âm cuối; **không có chốt chống rỗng ở mức token** (`PiperTTSService.isUnspeakable` chỉ chặn cả chunk); và cổng ngữ cảnh của 1.3.290 đẩy cả từ tiếng Việt vào đường tiếng Anh. Bất biến mới: **không bộ phiên âm nào được trả rỗng**, rỗng thì trả nguyên văn token — áp cho cả ba đường.
- **Cụm phụ âm tách thành âm tiết đệm thay vì bị cắt.** `assemble` trả `[String]`: cụm đầu thành các âm tiết `+ "ơ"` ("street" → "xơ-tơ-rít", trước là "trít" mất /s/), phụ âm cuối thừa thành **một** âm tiết đệm ("text" → "tếc-xơ"). Đây là cách người Việt thật sự đọc từ nước ngoài, và nó bỏ hẳn lý do phải bỏ âm để hợp chuẩn chính tả.
- **Siết cổng ngữ cảnh của 1.3.290**: âm tiết Việt mơ hồ ("man", "song", "nam") chỉ được phiên âm khi **kẹp giữa** từ lạ ở *cả hai* phía, thay vì chỉ cần một láng giềng lạ — trước đây "anh Nam gọi taxi" có thể làm "nam" bị phiên âm oan. `VietnameseTokenGate` trả `(before, after)`.
- **Trường âm tiếng Nhật đọc như âm ngắn — đảo lại quyết định của 1.3.290.** `ー` bị bỏ ("ラーメン" → "ra-mên") vì tiếng Việt không có nguyên âm dài: nhân đôi nguyên âm làm Piper đọc thành **hai âm tiết rời** có ngắt thanh hầu, nghe như nói lắp. Cùng nguyên tắc, thêm `ou → ô` và `ei → ê` ("arigatou" → "a-ri-ga-tô", trước sinh thêm một âm tiết "ư" thừa). Ghi rõ trong code + bộ ca kiểm rằng đây là **lựa chọn nghe**, không phải chuẩn Hepburn.
- **Thêm "Xoá tất cả phiên âm"** ở màn Từ điển TTS: `TextPreprocessor.deleteAllWords()` (file mới `TextPreprocessor+Bulk.swift`) dọn `wordMap` + ghi plist **rỗng** + xoá LRU cache trong một lượt; UI là `TTSDictionaryBulkActionsModifier` (`@MainActor ViewModifier`, đúng khuôn `QuickTranslationRuleIOMenu`). Ghi file rỗng chứ không xoá file — "chưa tải từ điển" và "người dùng muốn trống" là hai trạng thái khác nhau. Cảnh báo của nút "Tải lại từ điển gốc" sửa lại cho khớp hành vi **trộn** từ 1.3.290 (câu cũ nói sẽ ghi đè, đã sai).
- Sửa kỳ vọng bộ ca kiểm: ラーメン → "ra-mên", ジェット → "giêt-tô" (sokuon gắn vào âm tiết **trước**, tôi đặt sai ở 1.3.290), thêm ca `arigatou`, `street`, `text`.
- 2 file Swift mới (421 → **423**). `TextPreprocessor.swift` giữ **đúng** 1121 dòng (chỉ đổi 4 từ khoá truy cập vì `private` là phạm vi file), `TTSDictionaryEditView.swift` **giảm** 706 → 705. `check_architecture.py` giữ 14 violation nền.
- **Chưa làm trong lượt này**: Phase 0 (đo `phoneme_id_map` của model), Phase 2 (map âm vị tiếng Anh **trong** inventory của model để bỏ hẳn khâu chính tả), Phase 3 (để espeak tự chuyển ngôn ngữ), Phase 4 (kana → IPA trực tiếp).

## [1.3.290] - 2026-08-30

### NghiTTS: phiên âm tiếng Anh qua IPA của espeak, bỏ blacklist tiếng Nhật

- **Bộ luật tiếng Anh tự huỷ lẫn nhau.** `sRules` chạy trước `rRules` trên cùng chuỗi nên `ck → c` và `sh → s` xoá cụm trước khi các luật đuôi kịp thấy ⇒ 10 luật chết (`ack$/eck$/ick$/ock$/uck$`, `ash$/esh$/ish$/osh$/ush$`). Dời hai luật đó xuống đầu `tRules`: "back" → "bác" thay vì "bac", "duck" → "đúc" thay vì "đuc".
- **Ba luật khớp giữa từ vì thiếu ngoặc**: `"\bcr|pr|gr|dr|fr"` là `(\bcr)|(pr)|…` nên `pr/gr/dr/fr` đổi ở mọi vị trí ("april" → "ail", "hydro" → "hyro"). Nay `\b(?:…)`; cùng nhóm `\b(?:sc|sk)` và `\b(?:bl|cl|sl|pl)`.
- **Mọi từ mở đầu bằng "y" đọc thành /d/**: hai `if` nối tiếp, câu sau đọc chuỗi vừa bị `y → d` rồi đổi tiếp thành `đ` ("yes" → "đet"). Nay `else if`, và tiền tố `y` map sang `i` vì "d" tiếng Việt đọc /z/ trong khi "y" đầu từ là bán nguyên âm /j/.
- **Đường chính của tiếng Anh không còn đoán theo chính tả.** `EnglishPhonemeTransliterator` hỏi espeak-ng giọng `en-us` lấy **IPA thật**, `IPAToVietnameseMapper` dựng âm tiết Việt hợp lệ (onset/nucleus/coda + chuẩn hoá `c/k/g/gh/ngh`); bộ luật cũ tụt xuống dự phòng. Không thêm dependency: `build-ipa.yml` khi dọn dữ liệu espeak vẫn giữ `en_dict` + `voices/en`, chỉ có code là chưa bao giờ đổi giọng. `EspeakPhonemizer` tách `initializeIfNeeded`/`textToPhonemes`, thêm `phonemizeEnglish` (đặt `en-us`, trả `vi` trong `defer` — Piper luôn cần giọng `vi`) và `probeVoices`.
- **Phân loại Nhật/Anh bỏ blacklist tay.** Xoá `englishBlacklist` ~420 từ (vá theo từng ca, có cả "ee", "san"); `ForeignScriptClassifier` chấm điểm dấu hiệu — romaji hợp lệ chỉ còn là *điều kiện cần*. Phải đổi kiến trúc vì "tomato", "potato", "sonata" đều cắt được thành âm romaji: tập từ tiếng Anh cần loại trừ là vô hạn.
- **Bảng romaji→Việt**: `ya/yu/yo` từ `da/du/dô` (đọc /za/) thành `ia/iu/iô`. `za/zi/zu` **giữ nguyên** `da/di/dư` vì "d" tiếng Việt vốn đọc /z/, khớp /dz/ tiếng Nhật — đây là chỗ tôi nói sai ở lượt khảo sát trước.
- **Trường âm `ー` không còn bị xoá**: `convertToRomaji` nhân đôi nguyên âm trước ("ラーメン" → "raamen") và bảng nhận thêm `aa/ii/uu/ee/oo` để `greedySegment` không vỡ. Thêm katakana hiện đại: ヴ, ファ/フィ/フェ/フォ, ティ/ディ, ウィ/ウェ/ウォ, ジェ/シェ/チェ.
- **Cổng "là từ tiếng Việt" xét ngữ cảnh.** `VietnameseTokenGate`: token có dấu → giữ; không phải âm tiết Việt → phiên âm; ~700 âm tiết **mơ hồ** ("man", "can", "song", "tin", "phim") → chỉ phiên âm khi có láng giềng lạ trong cửa sổ ±2 token, chặn ở dấu kết câu.
- **Tải lại từ điển không còn xoá phiên âm tự thêm**: `downloadDictionaries` **trộn** với bản dưới máy (mục dưới máy thắng) thay vì ghi đè `non-vietnamese-words.plist` — file mà `updateWord` cũng ghi.
- **Thước đo nằm trong app**: màn **Thử phiên âm** (Cấu hình NghiTTS) kiểm giọng espeak có thật không, soi đường đi của một từ (từ điển → phân loại → IPA → kết quả), và chạy `TransliterationGoldenSet` ~55 ca. Vì `Tests/` bị coi như không tồn tại và máy chạy qua LiveContainer không đính được debugger.
- 6 file Swift mới (415 → **421**), tất cả ≤ 400 dòng; `TextPreprocessor.swift` giữ **đúng** 1121 dòng (bằng baseline), `JapaneseTransliterator.swift` **giảm** 411 → 320. `check_architecture.py` giữ 14 violation nền.

## [1.3.289] - 2026-08-30

### Rule editor: chèn token tại con trỏ của ô nhập mẫu

- **Nút token luôn chèn vào cuối mẫu.** Ở 1.3.288 con trỏ duy nhất là vạch 2pt giữa hai chip của dải mẫu, nên trừ khi bấm đúng vạch đó, mọi lần chèn đều rơi xuống cuối chuỗi. Sửa bằng `QuickTranslationRulePatternField` — `UIViewRepresentable` bọc `UITextView` để đọc/ghi **con trỏ thật**: `textViewDidChangeSelection` báo lên `selectionStart`/`selectionLength`, `updateUIView` áp ngược lại khi dải chip hoặc nút token đặt vùng chọn mới. Phải bọc UIKit vì iOS 17 không cho SwiftUI đọc vùng chọn của `TextField` (`TextSelection` là iOS 18). Bấm token giờ chèn tại con trỏ, hoặc **thay** đoạn đang bôi đen.
- Quy đổi đơn vị đặt đúng ở biên UIKit: model đếm theo **ký tự** (`Array(pattern)`), `UITextView` dùng `NSRange` UTF-16, hai chiều đổi qua `String.Index`. Hai chốt chống vòng lặp cập nhật: `isApplying` (không báo lên khi tự áp xuống) và `lastReportedRange` (không áp lại range vừa báo lên — cần khi chuỗi có ký tự ngoài BMP).
- Thanh `:min-max` nay mở theo **con trỏ** chứ không chỉ theo vùng chọn khít: token có `start < caret ≤ end` là mở. Vừa chèn `<n>` xong là chỉnh được độ dài ngay, và chạm vào giữa `<n:1-6>` trong ô nhập cũng mở đúng token đó.
- Bỏ cờ `isProgrammaticPatternEdit` và heuristic "gõ tay ⇒ con trỏ về cuối" của 1.3.288: chúng chỉ tồn tại vì trước đó không đọc được con trỏ thật, giữ lại là hai nguồn tranh nhau quyết định con trỏ ở đâu. `reconcileSelection` giờ chỉ kẹp biên.
- `@FocusState` chỉ còn cho ô Bản dịch; ô Mẫu tự `becomeFirstResponder()` một lần trong `makeUIView` khi bản nháp nói nó đang được gõ, và báo focus ra ngoài bằng `onFocusChange`. `focusedField` đổi từ `@FocusState` sang `@State` thường vì nó là *dữ liệu của bản nháp*, không phải cái điều khiển focus.
- 2 file Swift mới (413 → **415**), nhưng `QuickTranslationRuleEditorSheet.swift` **giảm** 374 → 319 dòng nhờ dời 6 hàm biên tập sang `QuickTranslationRuleEditorSheet+Editing.swift`; các `@State` liên quan chuyển sang `internal` (đúng khuôn `ReaderView` + `ReaderView+Selection`). `check_architecture.py` giữ 14 violation nền.

## [1.3.288] - 2026-08-30

### Rule editor: giữ bản nháp, bảng token, thanh min-max, chip {i}

- **Mất sạch chữ đang gõ ở màn thêm/sửa rule khi TTS tự chuyển chương.** Sheet **vẫn mở** mà mọi ô về giá trị seed ⇒ SwiftUI dựng lại content của sheet, `init` chạy lại. Sửa bằng `QuickTranslationRuleDraftStore` (1 slot theo `Mode.id`, sống ngoài cây view, không `ObservableObject`): `init` seed `@State` từ slot, mọi thay đổi mirror ngược lại, `@FocusState` khôi phục ở `onAppear`. Draft chỉ xoá khi **lưu thành công** hoặc bấm **Hủy** — cố ý không xoá ở `onDisappear` vì chính lượt dựng lại có thể kèm một lần disappear. Không hoist lên `@State` của `ReaderView` được: `@State` không khai được trong extension và `ReaderView.swift` đang vượt baseline (2076 > 2053) nên chỉ được giảm dòng. Fix áp cho **cả hai** call site mà không sửa call site nào.
- **Bảng nút token** (`QuickTranslationRuleTokenPaletteView`): 10 token dựng từ `QuickTranslationRuleTokenSettings.Kind.allCases` + 4 nút cú pháp nhóm; chạm là chèn tại con trỏ hoặc **thay** vùng đang chọn. Token đang tắt ở Cấu hình token rule hiện mờ kèm cảnh báo. Kèm `QuickTranslationRulePatternStripView` — dải chip của mẫu (một token là **một** chip) cấp con trỏ và vùng chọn, vì iOS 17 không cho SwiftUI đọc vị trí con trỏ của `TextField` mà luồng chính (nút `+` của Check rule) cần **thay** một đoạn chữ Trung thành token.
- **Thanh min–max bước 1, `[−]`/`[+]` hai bên** (`QuickTranslationRuleTokenLengthBar`) cho token đang chọn, kèm công tắc `?`. Biên lấy từ parser chứ không đặt lại: `min ≥ 1`, `max ≥ min`, trần 20; token không khai `:min-max` nghĩa là `1...12` nên về mặc định thì xuất token **trần**, `min == max` xuất `:N`. `<L>`/`<hv>` không có thanh vì parser ép chúng về đúng 1 ký tự.
- **Chip `{0}/{1}/{2}` theo số token của mẫu** (`QuickTranslationRuleCaptureChipsView`) để chèn vào bản dịch, chip chưa dùng tô đỏ, cộng section **Kiểm tra** (`QuickTranslationRuleDraftIssuesView`) hiện **mọi** issue ngay khi gõ thay vì một issue sau khi bấm Lưu. Verdict do `QuickTranslationRuleDraftAnalyzer` cấp: dựng đúng dòng store sẽ ghi (`RecordStore.serialize`) rồi chạy lại `parse` → `compile`, nên không có trạng thái "ở đây xanh mà lưu vẫn đỏ". `QuickTranslationRuleCompiler.parseTemplate` mở `private` → `internal` để không có bản quét `{…}` thứ hai.
- Sheet hướng dẫn Check rule dời từ ZStack của `ruleToolsOverlay` xuống chính panel Check rule: một view chỉ có một chỗ trình bày.
- 7 file Swift mới (406 → **413**), tất cả ≤ 400 dòng và 1 primary type top-level; `ReaderView.swift` không thêm dòng nào. `check_architecture.py` giữ **14 violation nền**, không violation mới. Host Windows không build được — tính đúng đắn biên dịch do CI xác nhận.
- Đẩy 10 entry cũ nhất (1.3.249–1.3.258) sang `CHANGELOG.archive.md` để file chính về 30 entry theo quy ước.

## [1.3.287] - 2026-08-28

### Add `<h>` (Chinese digits) and `<d>` (ASCII + fullwidth digits) numeral tokens

- `QuickTranslationRuleElement.NumeralKind` thay cho trạng thái `isDigitwise: Bool`: `<n>` = `.chinese`, `<y>` = `.digitwise`, `<h>` = `.hanDigits`, `<d>` = `.asciiDigits`.
- `<h>` chỉ nuốt chữ số Hán `〇零一二两兩三四五六七八九`; `<d>` chỉ nuốt `0123456789` ASCII + full-width `０..９` (U+FF10-FF19), render full-width về ASCII. `<n>/<y>` cũng nhận full-width giờ.
- `QuickTranslationNumberFormatter` thêm `hanDigitsUnits`/`asciiDigitsUnits`, `units(for:)`, `renderHanDigits`/`renderAsciiDigits`; `digitMap` thêm full-width. Matcher/Compiler dùng `units(for:)` cho boundary guard và render theo loại.
- `QuickTranslationRuleTokenSettings` tăng 8 → **10** token (thêm `h`/`d` + 2 khoá UserDefaults lower-camel-case); `QuickTranslationRuleTokenSettingsView` thêm 2 Toggle ở nhóm "Token số và nhãn". `|` giữa các token số vẫn được parse theo loại đầu tiên để giữ tương thích `<n|y>` cũ.
- Mọi file sửa vẫn ≤ 400 dòng; không thêm file mới.

## [1.3.286] - 2026-08-28

### Merge Quick Translation rule action menus

- `QuickTranslationRuleListView` chỉ còn một dropdown `quickTranslationRuleIOMenu(scope:showingDisabled:)`; tab Đang bật hiện nhập/xuất/xoá bộ rule, tab Đã tắt hiện nhập/xuất/bật lại/xoá danh sách rule tắt.
- Xoá modifier riêng `QuickTranslationRuleDisableIOMenu`, chuyển các thao tác rule tắt sang `QuickTranslationRuleIOMenu+DisabledActions.swift` để vẫn giữ mỗi file dưới 400 dòng.
- Giữ `DocumentPickerPresenter`/`ShareSheet` gắn trên body chính, không đưa presenter vào toolbar.

## [1.3.285] - 2026-08-28

### Fix: Correct disabled rule import API label

- Sửa chữ ký `QuickTranslationRuleDisableStore.importPatterns(imported:mode:scope:)` khớp call site nhập danh sách rule tắt, tránh lỗi compile do label `imported:`.
- Tách scope mặc định của `QuickTranslationRuleEditorSheet` trong Reader thành helper rõ ràng, giữ nguyên hành vi sửa/thêm rule theo đúng scope.

## [1.3.282] - 2026-08-28

### Fix Check rule edit, add disable rules import/export

- Màn Check rule: popup ấn giữ chip thêm nút **"Sửa rule"** (mở `QuickTranslationRuleEditorSheet` chế độ `.edit` với scope đúng của rule — riêng/chung). Sheet dùng `updateRule(oldPattern:)` đúng ngữ nghĩa: đổi mẫu = thêm rule mới, giữ rule cũ.
- `QuickTranslationRuleEditorSheet.Mode.edit` thêm associated value `scope: QuickTranslationRuleScope` — mode tự chứa, mọi đường mở sheet đều biết sửa bộ nào.
- Xuất/nhập/bật lại/xoá **rule tắt riêng & chung**: thêm ViewModifier `QuickTranslationRuleDisableIOMenu` gắn vào List (file mới < 400 dòng). Menu có 4 mục: Nhập (.txt, 3 chế độ `DataImportMode`), Xuất, Bật lại tất cả, Xoá tất cả rule đã tắt (destructive, xoá hẳn rule khỏi file + dọn danh sách tắt). Nhập dùng đủ 3 mode chuẩn app (2 mode đè/giữ đồng nghĩa với tập mẫu — ghi chú trong code).
- `QuickTranslationRuleDisableStore`: thêm `importPatterns(_:mode:scope:)` (luôn notifyChange) + `clearDisabled(scope:)`.
- `QuickTranslationRuleStore+Editing` / `QuickTranslationRuleBookStore`: thêm bulk `deleteRules(patterns:)` / `deleteRules(patterns:bookId:)` — filter records rồi ghi lại; không fail khi có mẫu stale.
- Cập nhật accessibility/hướng dẫn: "Ấn giữ: sửa / bật / tắt / xoá".

## [1.3.283] - 2026-08-28

### Fix: Remove @ObservedObject from QuickTranslationRuleIOMenu

- Gỡ `@ObservedObject` khỏi `QuickTranslationRuleIOMenu`, vì `ViewModifier` dùng trực tiếp các singleton store giống modifier danh sách rule tắt.
- Giữ nguyên hành vi đọc, nhập, xuất và xoá rule theo phạm vi chung/riêng.

## [1.3.284] - 2026-08-28

### Fix: Isolate Quick Translation rule modifiers on MainActor

- Đánh dấu hai `ViewModifier` quản lý rule dịch là `@MainActor` để truy cập singleton store có trạng thái UI an toàn khi build với Swift concurrency hiện hành.

## [1.3.281] - 2026-08-28

### Fix rule list back bug, add rule set import/export

- Chuyển `QuickTranslationRuleIOMenu` từ View nhúng toolbar sang **ViewModifier** áp lên `List`, gỡ bug SwiftUI: `DocumentPickerPresenter` (UIViewControllerRepresentable) đặt trong toolbar gây kẹt transition khi pop trong sheet → màn trắng (bug 1.3.281). Giống `DictionaryListView`, mọi presenter/presentation giờ gắn lên body chính.
- Menu Nhập/Xuất/Xoá hiện cho **cả rule riêng và chung** (trước chỉ riêng).
- Route import/export/xoá theo `scope`: `QuickTranslationRuleBookStore` (riêng) / `QuickTranslationRuleStore` (chung).
- Giữ `.searchable` (bằng chứng: Rule Chung back bình thường → `.searchable` không phải thủ phạm).

## [1.3.280] - 2026-08-26

### Canonicalize Quick Translation rule storage

Sửa lỗi build CI của hai API xoá rule sau khi chuyển sang closure `withMutationLock`.

* Thêm `return withMutationLock { ... }` cho `deleteRule(pattern:)` ở store chung và riêng.
* Giữ nguyên commit subject cho lần push sửa CI.

## [1.3.279] - 2026-08-26

### Canonicalize Quick Translation rule storage

Quick Translation Rule chung và riêng theo truyện nay dùng cùng ngữ nghĩa TXT như VP/Name custom: thao tác theo key `pattern`, duplicate giữ dòng đầu, dòng hỏng bị bỏ qua và mọi lần ghi sinh lại file canonical `.txt`.

* Thay `QuickTranslationRuleFileEditor` bằng `QuickTranslationRuleRecordStore` cho parse/merge/upsert/delete/serialize records.
* `QuickTranslationRuleStore` và `QuickTranslationRuleBookStore` đều thêm/sửa/xoá theo `pattern`; không dùng UUID/sourceLine/sourceRevision cho nghiệp vụ.
* Snapshot và trace bỏ `rowID`; UI list dùng `pattern` làm identity sau canonical first-wins và đảo thứ tự file để rule cuối file lên đầu.
* Import preview và import 3 chế độ tính theo key hợp lệ; comments/header/dòng lỗi rơi khỏi file sau lần ghi đầu.
* Windows không có `xcodebuild`/`xcodegen`; đã chạy validator tĩnh, build Swift cần xác nhận trên macOS/CI.

## [1.3.278] - 2026-08-26

### Match preparing TTS highlight color to config

Preparing highlight của đoạn sắp nghe nay dùng đúng màu highlight đã cấu hình, trùng với active TTS highlight.

* `ReaderTextView` bỏ alpha riêng `0.28` cho preparing highlight; background luôn là `theme.highlightUIColor`.
* Preparing highlight cũng áp `theme.highlightTextUIColor` nếu theme/config có màu chữ highlight, giống active highlight.
* `highlightIsPreparing` vẫn giữ vai trò diff/repaint khi chuyển preparing → active, nhưng không còn tạo palette riêng.
* Không đổi state TTS, progress, Now Playing, prefetch hay thứ tự ưu tiên active → preparing → search.

## [1.3.277] - 2026-08-26

### Reveal TTS widget when starting from Reader

Khi bấm nút nghe trong Reader hoặc bôi đen rồi bấm "Nghe", widget TTS mở ở dạng capsule ban đầu thay vì peeking. Không đổi `TTSManager.startSpeaking`, không đổi `WidgetMode`, không thêm notification/event center.

* `TTSFloatingWidgetWindowManager` thêm request một lượt `requestRevealOnNextShow()` với cờ pending `shouldRevealOnNextShow`, consume khi container sẵn sàng hoặc reveal ngay nếu widget đã tồn tại.
* `FloatingWidgetContainerViewController` expose `reveal(animated:)`, dùng lại `FloatingWidgetViewModel.reveal()` nên auto-hide 3 giây và layout/snap hiện có giữ nguyên.
* `ReaderView.startTTS(...)` gọi request reveal ngay trước `ttsManager.startSpeaking(...)`; đây là điểm chung của nút headphones và menu bôi đen "Nghe".
* Giữ ranh giới kiến trúc: `Services/TTS` không biết widget UI; request nằm ở tầng View.

## [1.3.276] - 2026-08-26

### Show preparing TTS highlight before audio starts

Thêm state highlight chuẩn bị để Reader tô đoạn sắp nghe ngay khi bấm phát, trước khi engine TTS tổng hợp/phát audio thật. Không thêm file Swift, không đổi `@Model`, không thêm notification/event center mới.

* `TTSPlaybackSnapshot` thêm `preparingParentParagraphIndex` và `preparingHighlightRange`; `TTSManager.speakCurrent()` publish hai field này trước khi dispatch engine, còn `commitAudibleParagraphState(index:)` vẫn là cửa duy nhất publish active `highlightRange` khi audio bắt đầu.
* Reader projection (`ReaderTTSStateReader`) truyền state chuẩn bị chỉ cho đúng sách đang phát. `ReaderView` chọn highlight theo thứ tự active TTS → preparing TTS → search, và `ParagraphCardView`/`ReaderTextView` render vệt chuẩn bị bằng `highlightIsPreparing`.
* State chuẩn bị chỉ là presentation state: không lưu tiến độ, không update Now Playing, không claim `ReadingProgressStore`, không đổi prefetch/cache audio và không dùng mapper highlight.
* Windows không có `xcodebuild`; đã chạy kiểm tra tĩnh cục bộ, build Swift cần xác nhận trên macOS/CI.

## [1.3.275] - 2026-08-26

### Fix Reader lookup route visibility for CI build

Sửa access control của `ReaderLookupRoute` để extension `ReaderView+Selection` có thể khởi tạo route tra cứu ngoài. Không đổi hành vi UI, navigation hay dữ liệu.

* `ReaderLookupRoute` chuyển từ `private` thành internal để phù hợp với `ReaderView.lookupRoute` và call site ở file extension.
* Sửa lỗi archive CI: `cannot find 'ReaderLookupRoute' in scope` và `property must be declared fileprivate because its type uses a private type`.
* Windows không có `xcodebuild`; đã chạy kiểm tra tĩnh và sẽ xác nhận bằng CI macOS.

## [1.3.274] - 2026-08-26

### Rule dịch: trace lý do match, bật/tắt từng rule, bộ rule riêng theo truyện, overlay xem bản gốc

Thêm **17** file Swift, sửa **17** file Swift, không xoá file, không đổi shape `@Model`, **không** thêm resource bundled (bộ riêng là dữ liệu người dùng, nằm ở `translate/books/<bookId>/`). **Chưa biên dịch** (viết trên Windows, không có `xcodebuild`); có file Swift mới nên khi lên macOS phải `xcodegen generate`.

* **Hai bộ rule thật — bộ riêng theo truyện**: `QuickTranslationRuleScope` (Models, `enum { global, book(String) }`, `rank` 0 riêng / 1 chung) và `QuickTranslationRuleBookStore` (chủ `translate/books/<bookId>/QuickTranslateRules.txt`, LRU cap **3** truyện, compile lazy, cùng hợp đồng validate-then-swap, dùng lại Parser/Compiler/FileEditor/`rowIDs` của bộ chung). Engine trộn hai bộ trong cùng một lượt rewrite (hai lần `collectFound` + `select` **một** lần trên tập hợp nhất); `scopeRank` là tiêu chí ưu tiên **thứ 5**, đứng ngay trước `sourceLine`, nên trong một bộ đơn lẻ thứ tự cũ không đổi — rule riêng thắng rule chung khi trùng mọi tiêu chí khác. Đường dịch không có `bookId` (meta/global, `Qt` bridge) chỉ thấy bộ chung — đúng thiết kế.
* **Bật/tắt từng rule bằng FILE, không sửa file rule**: `QuickTranslationRuleDisableFile` (hàm thuần trên `String`, không chạm `FileManager`) + `QuickTranslationRuleDisableStore` (chủ hai file `QuickTranslateRulesDisabled.txt` chung/riêng). Rule đang tắt **vẫn nằm** trong `snapshot.rules` (bật lại được, giữ `sourceLine`/`rowIDs`); khoá là **mẫu** chứ không phải `sourceLine`; `Snapshot.isDisabled(pattern:scopeRank:)` là toàn bộ ngữ nghĩa — tắt ở bộ chung là tắt cho **mọi** truyện, muốn dùng lại ở một truyện thì thêm mẫu vào bộ rule riêng. Ghi file thất bại ⇒ không bump, không notify — `Toggle` quay về trạng thái cũ. Mọi invalidation gói vào đúng một `notifyDictionariesDidUpdate(bookId:scope: .config(bookId:))`, không thêm notification mới.
* **Màn Check rule ở Reader xem "vì sao thắng/thua/tắt"**: `QuickTranslationRuleDiagnostics` (Service) soi cả đoạn và giữ **cả** rule thua chồng lấn + rule đang tắt, bắt buộc dùng lại `collectFound` (`includesDisabled: true`) + `select` của engine — thay đổi visibility `private` → `internal` duy nhất ở engine — và không ghi trạng thái (`notesComplexRules: false`). DTO `QuickTranslationRuleTrace` (Models) mang `rowID` (handle xoá, không dùng `sourceLine` — lý do crash đã sửa 1.3.271), `scope`, `sourceRange`, `captures` và `Status` 6 case; `id` xác định theo `rowID#location`. `QuickTranslationRuleMatcher.Capture` gộp `text` + `sourceRange?` thành **một** mảng (rollback `let saved = captures` ở 5 chỗ) để hiện được chữ gốc từng token.
* **Hai công cụ mới trong menu bôi đen (2 hàng × 4 cột, thêm "Gốc" và "Rule")**: panel "Copy nội dung gốc" (`ReaderCopyOriginalOverlayView` — **mọi** đường đóng đều copy, không có nút Hủy; chọn lại cụm trên text gốc vì map ngược qua `ReaderSelectionMapper` khi bật dịch có thể lệch ở vùng rule vừa rewrite) và màn Check rule (`ReaderRuleTraceOverlayView` — thanh gốc → nghĩa rule → nghĩa token → dải chip; bấm ký tự snap vào cụm rule; ấn giữ chip ra popup Bật/Tắt/Xoá; nút `+` thêm rule từ cụm đang chọn; chip 3 mức màu `ReaderRuleChipStyle`; `ReaderRuleTraceGuideSheet` cho nút `?`). Khối biên tập vùng chọn dời sang `ReaderView+Selection.swift` (bốn panel Dịch/Xoá từ rác/Copy gốc/Check rule dùng chung); `ReaderView.swift` 2286 → **2076** (−210) nhờ dời 179 dòng + xoá 73 dòng code chết, nhiều `@State` bỏ `private` thành `internal` (phạm vi file).
* **Danh sách rule theo phạm vi, 2 tab Đang bật / Đã tắt**: hàng `[Sửa][Chuyển][Tắt][Xoá]` (`QuickTranslationRuleEntryRow`, mirror `DictionaryEntryRow`); Chuyển là **COPY** qua `QuickTranslationRuleTransfer` (nguồn giữ nguyên; ở danh sách Chung không biết truyện đang mở thì mờ + báo lý do); bộ riêng có menu Nhập (3 chế độ qua `DataImportMode`)/Xuất/Xoá cả bộ (`QuickTranslationRuleIOMenu`); hub Từ điển thêm section **Rule Dịch** với subtitle "N đang bật • M đã tắt"; swipe Sửa/Xoá bị bỏ. Ô Thử nhanh và màn Quản lý giờ **tôn trọng file tắt**; `menuWidth` của bong bóng suy ra từ hằng thành phần (bug tràn mép khi hard-code).
* **Backup liên quan**: tên file riêng truyện gom về **một** nguồn (`TranslationManager+BookScopedFiles` — `BackupPaths.bookDictionaryFiles`/`bookRuleFiles` và luồng đổi nguồn của `SearchView` đều đọc từ đó, hết nhân bản ở hai chỗ); bộ rule riêng + file tắt riêng đi theo scope `.dictBooks` nhưng **tách vòng lặp** khỏi từ điển riêng (vòng cũ trộn bằng `parseRecords` — bỏ dòng không có `=` và sinh lại `key=value`, làm mất comment + thứ tự dòng là tie-break cuối của priority), chiều khôi phục dùng `importRules(.overwriteExisting)` + `DisableStore.merge`; file tắt **chung** vào `config/QuickTranslateRulesDisabled.txt` (`BackupConfigArchiver`), khôi phục **hợp tập** — "khôi phục chỉ thêm, không xoá".
* **Xác minh** (không dùng `Tests/`): 17 file mới đều ≤ 400 dòng (lớn nhất `ReaderRuleTraceOverlayView` 383) và đúng 1 type top level ⇒ không cần entry `architecture_allowlist.json`; tổng file Swift 388 → **405**. `validate_links.py` PASS sau khi cập nhật toàn bộ 13 doc CodeGraph bị stale (7 doc đã sửa vùng GENERATED từ trước + 6 doc sửa/ghi nhận trong lượt này). `check_architecture.py` đã chạy và giữ nguyên **14 violation** baseline (cùng một tập, `ReaderView.swift` 2076 dòng) — không có violation mới; host là Windows nên không build được tại chỗ; CI xanh mới chứng minh *biên dịch được*.

## [1.3.273] - 2026-08-25

### Rule dịch: sửa build token

Sửa lỗi biên dịch SwiftUI ở màn **Cấu hình token rule**.

* Đổi hai `Section` sang initializer `content/header/footer` tương thích với toolchain CI; giao diện và logic bật/tắt token không đổi.
* Đã rà lại `11_subsystems.md` và ghi nhận `--no-change-needed`; CI macOS sẽ xác nhận build archive.
