# CHANGELOG - Nhật ký Thay đổi CodeGraph FreeBook

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **FreeBook**.

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

## [1.3.610] - 2026-10-26

### feat: nút tắt tiếng video, video tắt tiếng không dừng TTS, sheet thêm từ nửa màn, sửa header sheet nhấn giữ

Người dùng: *"Thêm nút tắt tiếng player video"* (thanh dưới; *"hiển thị nút tắt tiếng ở player full và player nhỏ"* = khung phim nhỏ màn dọc), *"có config trong tab cài đặt nhưng với nguồn 18+, mặc định tắt tiếng"* (chọn 3 mức), *"Nếu đang nghe truyện mà mở video bị tắt tiếng thì đừng tạm dừng tts"* (bật tiếng lại thì dừng TTS), *"Sheet thêm từ mới, thêm thay thế tts quá cao, cho cao nửa màn hình thôi"* (kéo lên được), *"chia lại layout header của menu context cho đúng. Phần tên truyện và tác giả bị mất góc bên phải"*, *"bấm nút thêm vào kệ ở lịch sử thiếu hiển thị sheet chọn bộ sưu tập"*. Plan duyệt trong chat.

- **Nút tắt tiếng** (`VideoPlayerBottomBar`, ngay sau nút khoá cảm ứng — thanh này dùng chung cho khung phim nhỏ màn dọc và toàn màn): `speaker.wave.2.fill` ↔ `speaker.slash.fill` (`isActive`). `VideoPlaybackSession.isMuted` + `setMuted(_:)` (`+Transport`) ghi `player.isMuted` ⇒ đổi tập vẫn giữ. Phim nhúng trang không có thanh dưới.
- **Tuỳ chọn "Tắt tiếng khi mở phim"** (mới `VideoMutePolicy`, khoá `videoMuteOnOpenPolicy`; Cài đặt › Đọc & Nghe, `Picker` `.navigationLink`): Không / **Chỉ nguồn 18+** (mặc định, `RepositoryFilterPolicy.isNsfwSource`) / Mọi phim. Chỉ áp ở `open()` khi mở phim khác — mở lại từ hub/PiP, cùng phim, đổi tập giữ trạng thái hiện tại.
- **Video tắt tiếng không giành âm thanh của TTS** (`isEffectivelyMuted = isMuted && embedContent == nil`): `prepareAudioForPlayback` không dừng TTS / không đổi `AVAudioSession` / không giành màn khoá khi TTS đang đọc; `beginUserRequestedPlayback` không dừng TTS; `readyToPlay` tự phát dù TTS đang đọc; `pauseForTTS` không dừng video (`yieldToTTS` vẫn trả màn khoá cho TTS). Bật tiếng lại khi đang phát ⇒ `prepareAudioForPlayback()` (dừng TTS, lấy lại session + màn khoá); đang đệm ⇒ dừng TTS để tự phát có tiếng. Tắt tiếng không tự cho TTS đọc tiếp. `CLAUDE.md`/`AGENTS.md` cập nhật dòng "Trình phát video … tạm dừng TTS".
- **Sheet "Thêm từ mới" / "Thêm thay thế TTS"** (`AddWordSheet`, `AddTTSReplacementSheet`): `.presentationDetents([.medium, .large])` — áp mọi chỗ mở (menu bôi đen Reader, từ điển phiên âm NghiTTS, từ điển tiếng Nhật VieNeu).
- **Header sheet nhấn giữ** (`BookActionSheet`): cột 2 nút bên phải cao bằng bìa chiếm cả dải phải ⇒ tên/tác giả bị ép xuống dòng sớm. Nay `ZStack(.bottomTrailing)`: khối bìa + tên/tác giả (chiếm hết bề ngang, chừa `actionRowHeight` 32 ở đáy) và hàng 2 nút là hai lớp sibling — nút không lồng trong vùng chạm/nhấn giữ.
- **Thêm vào kệ ở Kệ/Lịch sử/Tìm trên kệ mở sheet chọn bộ sưu tập** (`ShelfView`, `ShelfSearchView` + `+Actions`): như Chi tiết/Reader; sheet nhấn giữ đã đóng trước (`BookActionSheet.emit`) như đường Sửa thông tin.
- Chuyển entry `[1.3.580]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới** (`+Playback.swift` 386/400). Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy (video tắt tiếng phát cùng TTS khi app vào nền chưa kiểm).

## [1.3.609] - 2026-10-26

### feat: thêm provider Chế độ AI của Google cho chat và quét tên riêng

Người dùng: thêm provider dùng **chế độ AI của Google** (`google.com/search?udm=50`) vào màn AI của Reader như các provider hiện có. Qua `/grill-me` chốt: chat + quét tên, **khoá Dịch mượt** (thử thật: AI Mode tóm lược cả khi dặn không); dùng chung đăng nhập Google với Gemini Web; chat nối tiếp một cuộc chat theo phiên; mỗi lượt quét một cuộc chat mới, ~2.500 chữ/lượt, nghỉ 5 s; captcha thì dừng + nút "Mở Google để xác minh". Mockup 3 màn và plan duyệt trong chat.

- **Provider mới** `googleAIMode` (`AIProviderProfile.defaultGoogleAIMode`, `isGoogleAIMode`), code ở `Services/AI/GoogleAIMode/`: WKWebView ẩn riêng đọc **DOM** của trang (không có API — phản hồi là HTML server-render), mọi selector/chuỗi/JS gom ở `GoogleAIModePageContract`, một hàng đợi tuần tự cho mọi lượt mọi truyện (`GoogleAIModeTurnQueue`, nghỉ 5 s toàn cục trước lượt quét), ngân sách độ dài theo byte URL (`GoogleAIModePromptBudget`: thử thật 413 ở ~71 KB; `q` ≤ 48.000 byte, ô nhập ≤ 8.000 ký tự, cắt đuôi ngữ cảnh), retry một lần ở client khi chưa phát chữ.
- **Chat**: mở lại cuộc chat bằng `mstk` mới nhất rồi gửi qua ô nhập (đã thử trên Chrome), `mstk` lưu theo phiên (`GoogleAIModeConversationStore`); không mở lại được thì mở cuộc chat mới đủ ngữ cảnh. Màn AI chỉ gửi [system, tin hiện tại] như Gemini Web bật lưu lịch sử; không nén ngữ cảnh.
- **Quét tên riêng**: chế độ chia lượt `.googleAIMode` tách chương dài ở dòng → dấu câu → cắt cứng, mảnh dở có `lastChapterIndex = k − 1`; chặn trích nhầm câu hỏi (nhãn prompt ⇒ `protocolChanged`). `shouldStopBatch(on: Error)` dừng cả lần quét khi captcha / prompt quá dài; `runTurns` bắt bằng `catch where` thay vì chỉ `GeminiWebError`.
- **Chạy ở nền dùng chung**: vòng chờ/gửi lại của Gemini Web 1.3.602 chuyển nguyên văn sang `HiddenWebForegroundRunner`, Gemini Web gọi với đúng tham số cũ (hành vi không đổi).
- **UI**: mẫu "Google Chế độ AI (không cần key)", segmented 4 ô (rút "Anthropic Claude" → "Anthropic"), hàng `GoogleAIModeAccountRow` thay URL/key, ẩn khối model (tách `AISettingsView+Models.swift`) và temperature; chip "Dịch mượt raw" mờ + ổ khoá (`disabledActions`); tin lỗi captcha nền đỏ nhạt + `GoogleAIModeVerifyButton` (cả kết quả kiểm tra kết nối và lần "Thử lại k lượt lỗi").
- `rules.md`: mục mới "Google AI Mode provider invariants (1.3.609)"; bullet Gemini Web 1.3.602 trỏ sang runner dùng chung. Chuyển entry `[1.3.579]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code, grep chéo mọi chỗ rẽ nhánh provider; `check_architecture.py` 2 violation nền, **0 mới**. Chạy đúng các script `snapshot`/điền ô nhập/Enter của app trên trang Chế độ AI thật (Chrome desktop và giả lập Android, chưa đăng nhập): đọc đúng số lượt, chữ trả lời, `mstk`; khôi phục bằng `mstk` rồi gửi tiếp được và đọc ra lượt mới — lần thử đầu lộ lỗi bỏ `[role="button"]` làm mất tên thực thể ("Paris"), đã sửa. Rà soát còn sửa: phần đã phát kết thúc bằng xuống dòng làm bản cuối (đã bỏ câu gợi ý) không nối tiếp ⇒ câu trả lời bị nối đôi; ô nhập nhận theo `getClientRects` (khối nhập của bản mobile là `position: fixed`); lượt chưa có khối trả lời thì coi là chưa có chữ (không đọc cả lượt — dính câu hỏi); log luật kết thúc lượt. Không build tại chỗ (Windows) — CI là cổng biên dịch; **chưa thử trên máy** (trang trong WKWebView iOS, khi đã đăng nhập, ngưỡng captcha là UNKNOWN — chỉnh theo log `🤖 [AIMode]`).

## [1.3.608] - 2026-10-26

### fix: ba sheet bôi đen kéo lên được, nền đồng bộ, bỏ nút ✕, tiêu đề to hơn

Người dùng (sau 1.3.606): *"lỗi ba panel bôi đen không kéo được lên trên nữa"*, *"màu phần padding và màu background chưa đồng bộ"* (chọn B — xám đậm), *"bỏ luôn nút x trên 3 màn"*, *"tăng size tên sheet và chiều cao sheet do tăng size tên sheet"* (chọn 20 bold). Plan duyệt trong chat.

- **Kéo lên được** (`FittedSheetDetentModifier`): nấc `[.height(đo được), .large]` (chưa đo: `[.medium, .large]`) — mở vẫn cao vừa nội dung, vuốt lên giãn toàn màn. 1.3.606 chỉ có một nấc nên vuốt lên chỉ nảy lại.
- **Nền đồng bộ**: nền sheet cố định `#1F1F24` (0.12/0.12/0.14) cho mọi theme (`ReaderView+SelectionSheets.selectionSheetBackground`, bỏ nhánh trắng của Sáng/Trầm ấm); ba view nội dung bỏ `systemBackground` (đen) — trước đó viền trắng/xám bao khối đen. Panel Dịch và Xoá rác giữ chạm nền để tắt bàn phím (`Color.clear` + `contentShape`).
- **Bỏ nút ✕ ở tiêu đề** cả ba sheet: đóng bằng vuốt xuống / chạm vùng mờ (Copy gốc vẫn copy ở `onDismiss`; Xoá rác còn nút "Huỷ"). Giữ ⓧ xoá chữ trong ô nhập. Xoá `ReaderView.closeDefinitionPanel()` (không còn caller nào trong `Sources/`).
- **Tiêu đề 20pt bold** (trước `.headline`); sheet đo chiều cao theo nội dung nên tự cao theo.
- `rules.md`: bullet ba panel bôi đen cập nhật nấc/nền/không ✕. Chuyển entry `[1.3.578]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.607] - 2026-10-26

### feat: ghim chéo trên bìa ở Kệ, icon dịch kiểu Google, nhớ nội dung Tìm trong chương

Người dùng: *"tăng size cover ở sheet contextmenu ở kệ sách/lịch sử"*, *"để icon ghim ở góc trên bên trái của cover (icon chéo một chút), bỏ icon ghim cũ và dòng đã ghim lên kệ"*, *"bỏ icon thông tin"*, *"Đổi icon ghim lên cover đối với truyện trong kệ luôn"*, *"icon dịch xấu quá, đổi icon khác đi"* (chọn Material `g_translate` sau hai lượt mockup), *"sửa icon mở trình duyệt ở kệ sách cho đồng bộ"* (chỉ các nút mở), *"mở tìm trong chương lại hãy nhớ nội dung vừa tìm"* (trong lượt đọc). Plan duyệt trong chat.

- **Ghim chéo trên bìa** (mới `CoverPinBadge`): `pin.fill` cam xoay 35° trên nền tròn tối, dùng chung cho dòng danh sách Kệ (`ShelfBookRowView` — bỏ ghim bên phải dòng, ghim nhô nhẹ ra ngoài góc bìa, cỡ theo `BookListRowSize.coverWidth` trong 14…20pt), ô lưới/chỉ bìa (`ShelfBookGridCardView.pinBadge` — trong góc) và sheet nhấn giữ. Áp cho Kệ, Lịch sử, Bộ sưu tập, Tìm trên kệ.
- **Sheet nhấn giữ** (`BookActionSheet`): bìa 60×84 → 86×120 (cột nút `minHeight` theo), ghim lên góc bìa thay dòng "Đang ghim đầu kệ" (VoiceOver vẫn đọc qua `accessibilityValue`), bỏ icon ⓘ trang trí.
- **Icon dịch** (`AppGlyph.translate`): asset mới `MaterialGTranslate` = Material Symbols `g_translate` Rounded, tô đặc, nét 600 (Apache 2.0, `Docs/ThirdParty/MaterialSymbols-LICENSE.txt`; `viewBox` đổi về gốc 0 bằng `translate`). Sáu chỗ của 1.3.605 tự đổi theo; nút "Gốc" ở menu chọn chữ giữ 文A (`originalText`) — hai icon không còn trùng.
- **Icon mở trình duyệt**: `globe` → `safari` ở menu Kệ "Mở trình duyệt web" và "Đăng nhập trên web" (`LegadoLoginView`, lệch với nút "Mở trang đăng nhập" ngay trên). Dòng "Trình duyệt" của Cài đặt và dòng NSFW giữ `globe` (tab Khám phá đã là `safari.fill`).
- **Tìm trong chương nhớ truy vấn** (`ReaderSearchView` `initialQuery`/`onQueryChange`, `ReaderView.readerSearchQuery`): đóng sheet thì báo truy vấn cuối về Reader; mở lại thì điền sẵn và tìm lại ngay. Nhớ trong lượt đọc (đóng Reader là mất). Không nối `Binding` thẳng vào `@State` của Reader để phím gõ không vẽ lại cả thân Reader.
- Chuyển entry `[1.3.577]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy (asset SVG `g_translate` hiển thị đúng chưa kiểm).

## [1.3.606] - 2026-10-26

### feat: ba panel bôi đen thành sheet kéo được, ✕ xoá hẳn name AI, thẻ đầu tiện ích kiểu avatar

Người dùng: *"sửa lại các sheet khác thủ công ở màn hình dịch luôn"* (chọn cả 3 panel; *"độ cao của 3 sheet phải bằng độ cao hiện tại"*), *"phần ai, danh sách name nếu bấm x thì xoá luôn đi, tôi không muốn lần sau vào thấy lại nữa"* (chọn xoá dòng khỏi tin nhắn), *"sửa lại phần cấu hình tiện ích để cover của ext ở giữa, kiểu như avatar"* (PA2 bo góc; *"ngôn ngữ, tên tác giả, loại tiện ích, version hiển thị badge trên 1 hàng"*, *"ngôn ngữ dùng cờ đi"*), *"script editor path của script hiển thị sai: chữ private dính vào chữ sau, không có dấu /"*. Plan duyệt: `Docs/Plans/2026-10-26-plan-reader-panels-ai-names-ext-header-script-path.md`.

- **Panel Dịch / Xoá từ rác / Copy nội dung gốc là sheet gốc** (mới `ReaderView+SelectionSheets.swift`, `FittedSheetDetentModifier`; xoá `ReaderView+DefinitionPanel.swift`, `junkDeleteOverlay`, `ruleToolsOverlay`/`bottomPanel`): thanh kéo hệ thống, kéo bám ngón tay, chạm vùng mờ là đóng. **Một nấc** cao đúng bằng nội dung (`.fixedSize` rồi đo bằng `GeometryReader` + `PreferenceKey`, chiều cao giữ ở `@State` của `ReaderView` để lần mở sau không nháy `.medium`); padding trên = chỗ capsule giả cũ nên cao như panel trước. Bỏ capsule giả và `.presentationDetents([.height(660), .large])` thừa trong `ReaderDefinitionOverlayView`. Copy gốc: `onDismiss` là đường **duy nhất** copy (nút Copy/✕ chỉ hạ cờ) ⇒ mọi đường đóng copy đúng một lần (toast hiện sau khi sheet đóng). Presentation con của panel Dịch (sửa/thêm rule, cấu hình công cụ tìm, cover tra cứu nhanh) dời **vào trong** sheet Dịch; `performQuickLookup` đi `definitionLookupRoute` khi sheet Dịch mở, nút "Tìm" vẫn `lookupRoute`. `handleDefinitionPanelClosed` trả các cờ con về. Hậu xử lý khi đóng giữ ở `.onChange` sẵn có. Panel Dịch từng là `.sheet` trước 2026-07-18 (`de6f4432` chuyển sang overlay, không ghi lý do) — cần thử máy. `ReaderView.swift` 2020 → 1957.
- **✕ xoá hẳn name** (mới `ReaderAIFullScreenView+NameDeletion.swift`): `ReaderAINameReviewSheet.Target` thêm `messageId`, sheet thêm `onDeleteName`; ✕ bỏ **mọi** dòng `khoá=…` trùng khoá khỏi tin nguồn rồi lưu phiên, và sửa luôn tin trong phiên đang chạy của coordinator (`updateMessage`) để `mergeRunningSession` không chép ngược. `ReaderAINameReviewCardView.deleteItem` báo nơi dùng trước khi tự xoá.
- **Thẻ đầu Cấu hình tiện ích** (`ExtensionConfigHeaderCard`): icon bo góc 84pt ở giữa, tên căn giữa, một hàng badge cờ ngôn ngữ (`ExtensionFilterGroups.localeGroupFlag`, VoiceOver đọc tên ngôn ngữ) · tác giả (co "…") · loại · `vN`; bỏ dòng "tác giả · Phiên bản N".
- **Script editor** (`ExtensionScriptEditorView.loadScriptFiles`): `/var` là symlink tới `/private/var` — giải symlink thư mục lẫn từng file rồi cắt theo tiền tố (trước `replacingOccurrences` để sót `/private` ⇒ "/privatesrc/chap.js"). `fileUrl` nay cùng dạng `ext.localPath` nên phép so script chuẩn ở `+Toolbars` khớp lại.
- `rules.md`: bullet ba panel bôi đen là sheet gốc + presentation con gắn trong sheet Dịch + đường copy duy nhất. Chuyển entry `[1.3.576]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy (bàn phím trong sheet cố định chiều cao chưa kiểm chứng).

## [1.3.605] - 2026-10-26

### feat: nút dịch dùng icon Lucide languages thay character.bubble

Người dùng: *"Tôi muốn đổi icon nút dịch thành icon ngoài"* → chọn Lucide `languages` (文A), đổi ở **tất cả** nút dịch. Plan duyệt trong chat.

- **`AppGlyph.translate`** (mới): asset `LucideLanguages` sẵn có (cùng ảnh với `originalText`), nhãn VoiceOver "Dịch". Icon ngoài không có bản "fill" ⇒ bật/tắt chỉ khác màu (nút header Reader vốn đổi màu theo trạng thái; menu có chữ "Bật/Tắt").
- Thay `character.bubble`/`character.bubble.fill` ở: nút dịch header Reader + màn Chi tiết (`ReaderTranslationScopeMenuView`, 2 nhánh), hàng "Dịch văn bản" của popup dịch (`TranslationScopePopupView`), nút "Dịch lại chương và mục lục" (`ReaderChapterListView`), mục "Bật/Tắt Dịch Nghĩa" menu Kệ (`ShelfView`, `Label(_:image:)`), mục "Dịch văn bản" menu Khám phá (`DiscoverySourceMenuButton`).
- **Không đổi**: icon dự phòng nhóm tiện ích "Dịch thuật" (`ExtensionFilterGroups.typeGroupSymbol`, API chỉ nhận SF Symbol, không phải nút dịch). Nút "Gốc" của menu chọn chữ (`FloatingSelectionMenu`) vốn dùng cùng ảnh 文A — giữ nguyên theo plan; nay 文A vừa là bật/tắt dịch vừa là "Gốc" ở menu chọn chữ.
- Chuyển entry `[1.3.575]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.604] - 2026-10-26

### feat: danh sách chương Reader kéo được như Hẹn giờ, thêm nút kệ, chữ trên bìa rõ hơn

Người dùng: *"Sửa lại sheet danh sách truyện của reader, hiện tại sheet này kéo không được để nó kéo được như sheet hẹn giờ"*, *"Thêm nút thêm vào kệ vào sheet danh sách truyện của reader"*, *"Bỏ phần số thứ tự ở danh sách chương của màn hình hẹn giờ"*, *"số lượng chương trên cover giống hiển thị chỉ bìa … Tăng cover danh sách chương của reader lên chút"*, *"điều chỉnh luôn kiểu chỉ bìa của danh sách truyện để phần chữ ghi trên cover nhìn rõ hơn"*. Plan duyệt: `Docs/Plans/2026-10-26-plan-reader-toc-sheet-shelf-toggle.md` (mockup duyệt trong chat).

- **Danh sách chương Reader chữ là sheet gốc** (`ReaderView.readerChapterListSheet`, thay overlay `readerChapterListOverlay`): `.presentationDetents([.fraction(0.88), .large])` + thanh kéo hệ thống như `TTSQuickTimerSheet`, kéo theo ngón tay, kéo xuống/chạm ngoài để đóng. Bỏ `Capsule` giả và `dismissGesture` ở header. Chọn chương: đóng sheet trước, `selectChapter` ở lượt main kế tiếp. Không mở sheet khi store chưa dựng được. Sheet dựng lại view mỗi lần mở nên ô tìm lấy lại truy vấn từ store (`ReaderChapterListStore.activeSearchQuery`, mới) và nút sắp xếp đọc thẳng `store.isAscending` (bỏ `@State isAscending` vốn lệch với store khi mở lại). `ReaderChapterListHost` + `.equatable()` giữ nguyên (doc comment cập nhật). Lần thử cùng hướng ngày 19/8 (`716ae779`) bị revert không rõ lý do — cần thử trên máy.
- **Nút thêm/bỏ kệ chỉ có icon** (mới `ShelfToggleFlowModifier`, `ReaderChapterListView+Shelf.swift`): đầu hàng nút header danh sách chương Reader chữ và cạnh nút tải ở `ComicChapterListSheet`. `bookmark.fill` (chưa ở kệ) / `bookmark.slash.fill` đỏ (đã ở kệ) — cặp icon của `BookActionSheet`. Thêm ⇒ `BookActionRunner.addToShelf` rồi mở `CollectionPickerSheet`; bỏ ⇒ hộp xác nhận rồi `BookActionRunner.removeFromShelfOnly` (giữ file/tiến độ, về Lịch sử). **Không** dùng `BookDetailView.removeFromShelf` — đường đó xoá hẳn truyện. Chưa có bản ghi `Book` ⇒ ẩn nút. Hộp xác nhận/sheet chọn bộ sưu tập gắn ở gốc view, không trong `ToolbarItem`; tên trong hộp là tên đang hiển thị (đã dịch).
- **Header danh sách chương**: bìa 72×100 → 86×120; "N chương" chuyển từ hàng nút xuống dải đáy bìa; hàng nút dồn phải sát đáy bìa.
- **Chữ trên bìa kiểu "Chỉ bìa" rõ hơn** (mới `CoverCaptionStrip`, dùng ở `ShelfBookGridCardView`, `DiscoveryNovelGridCardView` và header trên): nền trong suốt → đen 75% trên đoạn chuyển phía trên chữ → 95% ở đáy, phần chuyển không chiếm chỗ bố cục (hàng badge tag/loại ở Kệ giữ vị trí, `zIndex(1)` để vẽ đè); tên 13pt bold, dòng phụ 11pt semibold trắng 100%, bóng chữ nhẹ trên từng `Text`; bìa 16:9 dùng đoạn chuyển thấp. Trước đó Kệ dùng nền đặc 60% (dòng "Ch. N" 10pt trắng 85%), Khám phá dùng dải chuyển 0 → 75% chỉ cao 14pt. Vẫn không dùng `.ultraThinMaterial`.
- **Sheet Hẹn giờ** (`TTSQuickTimerSheet.chapterRow`): bỏ cột số thứ tự; chương đang phát giữ icon loa.
- `rules.md`: bullet luật công tắc kệ trong Reader. Chuyển entry `[1.3.574]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới** (`ReaderView.swift` 2034 → 2020). Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.603] - 2026-10-26

### fix: quét tên coi Không có name là lượt hợp lệ, tên chương dịch theo cấu hình

Người dùng (sau 1.3.602): *"coi câu trả lời đúng "Không có name" là lượt hợp lệ: không gửi lại, không tính lỗi, không chặn Tiếp nối"* → sửa lại *""Không có name" là lượt hợp lệ nhưng vẫn phải thử lại nhé"*; *"tên chương cần được dịch theo config"*.

- **"Không có name"** (`AINameExtractionBatchProcessor.extractNamesFromText` trả thêm `saidNoNames`; `+Turns`): lượt không có tên vẫn được gửi lại một lần như 1.3.602; vẫn rỗng mà một trong hai lần AI trả lời đúng câu "Không có name" (prompt mặc định dặn câu này; so khớp bỏ hoa thường, code fence, dấu chấm cuối) ⇒ **lượt hợp lệ**: không tính lỗi, không vào danh sách "Thử lại", không chặn điểm tiếp nối (log thường, không ❌). Trả lời từ chối/sai định dạng khác giữ luật cũ (vẫn rỗng ⇒ lượt lỗi).
- **Tên chương dịch theo cấu hình** (`ReaderAIBatchPromptSheet`, `ReaderAINameScanChapterPickerView`, `AIBookDataInspector.nameScanChapters`): khi Reader đang bật dịch cho truyện, tên chương ở 4 dòng chọn chương bắt đầu, tóm tắt và màn "Chọn chương…" hiện bản dịch — đúng luật danh sách chương Reader (`TranslateUtils.translateChapterTitle` khi còn chữ Hán, kèm chuyển phồn → giản của truyện). Cấu hình đi từ `ReaderView` qua `AIRuntimeCoordinator.ActiveContext` / `ReaderAIFullScreenView` (tham số mới `translatesChapterTitles`, `convertsTraditionalToSimplified`, mặc định `false`) — màn AI không tự resolve vì không biết nguồn của truyện (bật dịch quyết theo truyện → nguồn → chung). Dịch lúc nạp danh sách, ngoài main thread; ô tìm khớp cả tên dịch lẫn tên gốc (`AINameScanChapter.rawTitle`).
- `rules.md`: bullet quét tên 1.3.602 thêm hai luật trên. Chuyển entry `[1.3.573]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.602] - 2026-10-26

### feat: quét tên chọn chương bắt đầu, chuẩn bị nhanh hơn, Gemini Web bớt lỗi

Người dùng: *"sửa lại app phần lọc name nhiều chương cho phép chọn chương bắt đầu lọc"*, *"tối ưu quét nội dung chương, hiện tại tôi thấy khá chậm"* (chậm ở bước "Đang chuẩn bị quét…", không gửi song song lượt API), *"Gemini Web dễ lỗi quá … dù tôi chỉ quét name 1 truyện vẫn lỗi"*, *"comment lại log [FD] đi"*, *"check vế phải của name để bỏ các trường hợp vế phải lộn tiếng trung"*, *"các trường hợp không trả về name hãy thử lại"*. Plan duyệt trong chat (1097 ⇒ mở chat mới; điểm tiếp nối dừng trước lượt lỗi; giữ `[FD] FAILURE`).

- **Chọn chương bắt đầu** (`ReaderAIBatchPromptSheet`, mới `ReaderAINameScanChapterPickerView`, `AINameScanChapter`): bỏ công tắc "Từ chương đang đọc", thay bằng 4 lựa chọn *Chương đang đọc* / *Tiếp nối lần quét trước* / *Chương đầu tiên* / *Chọn chương…* (danh sách chương **đã tải**, tìm theo số hoặc tên, tự cuộn tới chương đang chọn). Số chương hiện 1-based (trước hiện `ch.\(chapterIndex)` 0-based, lệch 1). Tóm tắt "Sẽ quét K chương: ch.a → ch.b". `onStart` → `(prompt, fromChapterIndex, limit)`; nhãn tin người dùng ghi đúng chương bắt đầu.
- **Điểm tiếp nối** (`AINameScanScopeStore` key `FreeBook_AI_NameScanResume_V1`, `AINameScanResumeTracker`): chương cuối của dãy lượt liên tiếp từ lượt 1 đều thành công — lượt lỗi chặn, lượt chưa gửi không tính, chỉ tính chương nằm trọn trong phần thật sự gửi (cắt 15.000/40.000 ký tự). Mở sheet mặc định chọn *Tiếp nối* khi còn chương sau điểm đó. Coordinator ghi điểm **sau** khi lưu phiên chứa tên của chính lượt đó; nút "Thử lại k lượt lỗi" đẩy điểm đi tiếp, context thử lại đồng bộ sau từng lượt (`syncNameScanRetry`). Dừng vì hạn mức/tài khoản: tên đã quét ở lại tin kết quả, lỗi thành tin riêng.
- **Bước chuẩn bị nhanh hơn** (mới `AINameScanTextLoader`, `BookBinManager.readChapterContents`): đọc khối 48 chương bằng **một** `FileHandle` mỗi lần gọi actor (trước: mỗi chương một lần nhảy actor + `fileExists` + mở/đóng file), chuẩn hoá song song tối đa 4 luồng qua `ChapterTextNormalizer.normalize`, giữ thứ tự; `makeBatches` đếm ký tự cộng dồn thay vì gọi `current.count` mỗi vòng (O(n²) grapheme). Dải tiến độ hiện "Đã đọc k/N chương"; log thường ghi ms đọc/chuẩn hoá/chia lượt. Ngữ nghĩa chia lượt không đổi.
- **Lọc name**: bỏ dòng có vế phải lẫn chữ Hán (`TranslateUtils.containsChinese`) ở `parseNamesFromText` và sheet "Thêm vào VP-Name" (`ReaderAINameReviewSheet`). Lượt không trả về name ⇒ nghỉ (Gemini Web 2 s, API 1 s) rồi gửi lại đúng lượt đó một lần, vẫn rỗng tính là lượt lỗi (vào vòng tự thử lại và nút Thử lại). `runTurns` tách sang `AINameExtractionBatchProcessor+Turns.swift` (file gốc 391 → 313 dòng).
- **Gemini Web — lượt quét tạm dừng khi app ở nền** (mới `GeminiWebForegroundGate`, `GeminiWebClient+NameScan`): log `app_logs (117)` (21–26/10) có ~30 lượt `StreamGenerate lỗi sau ~150 000 ms, chunk=0`, **tất cả** lúc app ở nền (iOS treo tiến trình web của WKWebView ẩn dù TTS giữ app sống). Nay lượt chờ app về trước (nghỉ 2 s), đang chạy mà app vào nền thì huỷ cả fetch trong trang rồi gửi lại đúng lượt khi mở lại app (tối đa 3 lần, không tính là lỗi, không nổi lên `CancellationError`; nút Dừng vẫn dừng ngay; lỗi tài khoản/hạn mức không gửi lại). Chỉ `didEnterBackground` tính là vào nền.
- **Gemini Web — 1097 ⇒ mở cuộc chat mới**: ~40 lượt `mã lỗi server 1097`, đều ở lượt nối tiếp lúc app đang mở; chat đã dính thì mọi lượt sau (kể cả thử lại sau 5 s) đều dính, mà luật 1.3.527 cấm lượt quét mở chat mới. Case mới `GeminiWebError.conversationBroken`; lượt quét bỏ lần chờ 5 s, mở chat mới với đủ ngữ cảnh và ghi nhớ cho phiên (chính lượt đó lỗi thì ném, không lặp). Google không công bố nghĩa 1097; cách khắc phục cộng đồng hay nêu là mở chat mới.
- **Gemini Web — fetch mồ côi**: huỷ `fetch` trong trang ở mọi lần stream kết thúc (trước đó watchdog timeout bỏ qua); `fetchStream` gắn `onTermination` ngay lúc tạo stream (`GeminiWebStreamTermination`) để lượt bị huỷ sớm không còn chạy fetch; `consumeGeneration` ném `CancellationError` khi bị huỷ (trước đó thành `protocolChanged` "không có ứng viên", bị coi như Google từ chối). Các dòng ❌ của luồng ghi kèm `(app ở nền)`/`(app đang mở)`.
- **Tắt log `[FD]`** (`FileDescriptorCensus`, `FileDescriptorStepProbe`, `FileDescriptorSweeper`): comment các dòng định kỳ (launch, chương, nền/active, `chunks=`, `step`, `tick`, `sweep`) và phần đếm chỉ phục vụ chúng. Giữ: nâng giới hạn fd, tự dọn fd mồ côi, `openCount()` cho màn log, `[FD] FAILURE` + bảng chụp lúc lỗi.
- `rules.md`: bullet mới về chọn chương/điểm tiếp nối và tạm dừng khi nền; luật 1.3.527 thêm ngoại lệ 1097. Chuyển entry `[1.3.572]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code + 2 agent review phản biện (đã sửa 5 điểm: điểm tiếp nối vượt tên đã giữ khi thử lại bị dừng, đuôi lượt API bị cắt vẫn tính là đã quét, sheet nạp lại mục lục, fetch mồ côi khi huỷ sớm, lỗi tài khoản bị gửi lại); `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy. Còn để ngỏ: lượt bị huỷ vì vào nền vẫn giữ metadata dở (`rememberPartial`) nên lượt gửi lại có thể dính 1097 rồi tự mở chat mới.

## [1.3.601] - 2026-10-25

### fix: chip gợi ý màn Dịch hiện đủ nghĩa như màn quản lý, hoàn tác 1.3.600

Người dùng: *"lỗi là lỗi thỉnh thoảng có token dù có nghĩa vp/name nhưng chip chỉ hiển thị hán việt"*, *"màn quản lý nghĩa hiển thị được đầy đủ, chỉ chip thiếu"* → *"dựng thẳng từ đúng danh sách mà màn quản lý đang dùng"*; chọn hoàn tác 1.3.600.

- **Nguyên nhân**: thanh chip gợi ý (viền đỏ/xanh/xám, cạnh nút ⚙) tự tra lại từ điển bằng `buildSuggestionChips`, lệch với `dictionaryMatches` mà màn quản lý định nghĩa dùng ở hai chỗ: bỏ **cả mục** VietPhrase chung khi nghĩa dài ≥ 100 ký tự (giới hạn có từ bản đầu, không ghi lý do — từ thông dụng nhiều nghĩa rất hay vượt), và không tra Xưng hô / Luật nhân ⇒ thanh chỉ còn chip Hán-Việt.
- **Sửa** (`ReaderView+Suggestions`): chip dựng thẳng từ `dictionaryMatches` — `suggestionChips(from:)` tách mỗi nguồn theo `/` và `¦`, bỏ nghĩa trùng, giữ thứ tự nguồn; nhãn "Names (…)" viền đỏ, "Phiên âm" viền xám (chữ thường như cũ), còn lại viền xanh. `ReaderDefinitionWorker` dùng **chính** mảng `matches` vừa tính cho màn quản lý; `buildSuggestionChips` còn là lớp bọc (bỏ khoảng trắng hai đầu rồi gọi `dictionaryMatches`).
- **Hoàn tác code của 1.3.600**: chẩn đoán "rule dịch" ở 1.3.600 không phải nguyên nhân của báo lỗi này (người dùng xác nhận từ lỗi không nằm trong rule, và thanh lỗi là thanh chip gợi ý chứ không phải hàng token gạch chân). `getRuleAwareTokens`, `Segment.captures` và lời gọi trong worker trở về như trước 1.3.600; entry 1.3.600 giữ nguyên làm lịch sử.
- Đánh đổi: từ nhiều nghĩa ra nhiều chip (thanh cuộn ngang); Xưng hô / Luật nhân hiện cả khi công tắc tắt — giống màn quản lý.
- Chuyển entry `[1.3.571]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. CI là cổng biên dịch; chưa thử trên máy — chạm lại token từng lỗi, thanh chip phải có chip xanh/đỏ bên cạnh chip xám.

## [1.3.600] - 2026-10-25

### fix: chip token ở màn Dịch tách từ theo rule dịch giống trang đọc

Người dùng: *"bị lỗi ở màn hình dịch của reader, thỉnh thoảng xuất hiện vài token thanh chip không có nghĩa, mặc dù sự thật chúng có nghĩa ở vp, name"* — chip hiện Hán-Việt, trang đọc dịch đúng, truyện không bật Phồn → Giản; duyệt phương án "mỗi từ một chip".

- **Nguyên nhân**: trang đọc (`performTranslation`) áp rule dịch (bật sẵn) **trước** khi tách token — rule tự bắt từ VP/Names (thử mọi độ dài, quay lui) rồi thay cả cụm bằng nghĩa. Thanh token của panel Dịch (`ReaderDefinitionWorker` → `getTranslationTokens`) tách thẳng chữ gốc, không qua rule: ở cụm rule đã xử lý, tokenizer chọn mục dài nhất toàn cục có thể vớ một mục VP vắt qua ranh giới token của rule và bỏ lại chữ lẻ không có mục riêng ⇒ chip hiện Hán-Việt. Đoạn không có rule khớp thì hai bên tách giống hệt — vì vậy chỉ "thỉnh thoảng".
- **Sửa**: `TranslateUtils.getRuleAwareTokens(for:bookId:)` (mới, `TranslateUtils+Tokenization`) — không có rule khớp ⇒ trả nguyên `getTranslationTokens`; đoạn đi qua ⇒ tách từ điển trên khúc gốc rồi dời offset; cụm rule ⇒ mỗi token rule một chip mang đúng nghĩa trang đang hiện, chữ giữa các token (literal của mẫu) tách từ điển; token rỗng/còn chữ Hán ⇒ tách chữ gốc; rule không có token ⇒ một chip cho cả cụm với kết quả rule. `QuickTranslationRewriteResult.Segment` thêm `captures` (mặc định `[]`), `QuickTranslationRuleEngine.assemble` ghi `match.captures` vào đoạn rule. `ReaderDefinitionWorker` gọi hàm mới ⇒ áp cho cả panel Dịch, Copy nội dung gốc, Xoá từ rác.
- **Không đổi**: `getTranslationTokens` (span, `mapSelection`, `snapToToken` vẫn tách thô); chip chưa áp Phồn → Giản (trang có áp).
- Chuyển entry `[1.3.570]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới** (`QuickTranslationRuleEngine.swift` giữ 399 dòng). CI là cổng biên dịch; chưa thử trên máy — mở lại đoạn từng lỗi, chip ở chỗ rule khớp phải hiện đúng nghĩa như trang.

## [1.3.599] - 2026-10-25

### feat: tab Chi tiết bìa lớn, cỡ dòng danh sách 7 nấc, tên phim hiện đầy đủ

Người dùng: *"mockup lại UI của tab 1 trên màn chi tiết tương tự hình này"* (chọn phương án A qua 4 bản mockup), *"làm thêm phần điều chỉnh kích thước đối với kiểu hiển thị danh sách nữa"* → *"nhiều cỡ lên"* (7 nấc), *"tên video trong phần phát hãy hiển thị đầy đủ thay vì chỉ 2 hàng"*.

- **Tab Chi tiết** (`BookDetailHeaderView`): khối đầu mới `BookDetailHeroView` — nền là bìa làm mờ nhạt dần về màu nền, bìa lớn ở giữa, tên 22pt căn giữa, chip tác giả, chip nguồn (icon tiện ích + tên miền của host sách, không có thì tên tiện ích). Bìa dọc 150×210 hay ngang gần hết bề ngang theo **tỉ lệ thật của ảnh** (`BookCoverView.onImageSize` mới, thumbnail giữ tỉ lệ gốc; ≥ 1,15 là ngang, tối đa 2,4); chưa có ảnh thì video đoán ngang 16:9. Thông tin (`detail`), Thể loại, Giới thiệu thành thẻ bo góc `BookDetailSectionCard` (tiêu đề xanh nhạt). Đề xuất, bình luận, nút "+" và thanh tab Chi tiết/Mục lục giữ nguyên; thẻ Giới thiệu chỉ hiện khi có mô tả.
- **Thanh điều hướng màn Chi tiết**: bỏ chữ "Chi Tiết Truyện" (mục `.principal` rỗng; `navigationTitle` giữ làm nhãn quay lại của màn con), nút quay lại chỉ còn icon (`.toolbarRole(.editor)`). Nút dịch và ⋮ giữ nguyên.
- **Cỡ dòng kiểu Danh sách** (`BookListRowSize`, mới): 7 nấc, nấc 4 = cỡ cũ (bìa 50×70, tên 14.5pt) và là mặc định — ở nấc này mọi dòng dùng đúng font cũ. Nấc 1–2 là dòng gọn (tên 1 dòng, dòng phụ "tác giả · Ch./Tập N" hoặc mô tả 1 dòng). Lưu theo scope ở `bookListLayout.rowSize.<scope>` (sao lưu tự gói, "Đặt lại mặc định" xoá luôn). Sheet "Kiểu hiển thị" và màn Cài đặt có thanh trượt "Cỡ dòng" khi chọn Danh sách (sheet cao 240 → 268). Áp cho Kệ/Lịch sử/Bộ sưu tập (`ShelfBookRowView` → `BookListItemView`), Tìm trên kệ, tab Khám phá và màn Thể loại (`DiscoveryNovelRowView`), kết quả tìm trong một nguồn. `BookListItemView` thay `coverWidth`/`coverHeight` bằng `rowSize` (không caller nào truyền hai tham số cũ).
- **Màn phát video** (`VideoPlayerDetailsView`): tên phim và tên tập bỏ giới hạn 2 dòng.
- Chuyển entry `[1.3.569]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. CI là cổng biên dịch; chưa thử trên máy (đặc biệt: `.principal` rỗng có ẩn hẳn tiêu đề không, nền mờ khi kéo làm mới, chuyển bìa dọc → ngang khi ảnh về).

## [1.3.598] - 2026-10-25

### fix: tạm dừng rồi tiếp tục TTS không còn lùi lại vài đoạn

Người dùng: *"có lỗi tạm dừng tts rồi tiếp tục lại không phát tiếp tục mà lui lại vài đoạn"* (tiếp tục từ màn khoá/tai nghe); duyệt phương án A.

- **Nguyên nhân**: `ReaderView.updateScrollReadingProgress` (chạy mỗi lần một đoạn hiện/khuất, kể cả do TTS tự cuộn) hẹn 1,5 s sau gọi `TTSManager.updateParagraphPositionWithoutPlaying(đoạn trên cùng màn hình)` khi `isPlaying || showFloatingWidget`. Lúc phát thì hàm bỏ qua, nhưng đã tạm dừng thì nó kéo `currentParagraphIndex` về chunk đầu của đoạn trên cùng màn hình — thường ở trên đoạn đang đọc vài đoạn, vì TTS chỉ tự cuộn khi vệt đọc ra khỏi vùng an toàn. Audio đang dừng không được giải phóng nên Google/tiện ích phát nốt chunk cũ rồi `nextParagraph()` nhảy về "đoạn trên cùng + 1", NghiTTS nạp tiếp "đoạn trên cùng + 1".
- **Sửa**: cuộn trang không còn dời con trỏ TTS (xoá khối đồng bộ, `updateTTSPositionWorkItem`, `updateParagraphPositionWithoutPlaying`). Tiếp tục từ widget, màn khoá, tai nghe, sau cuộc gọi đều phát tiếp đúng chunk đang dừng.
- **Nút tai nghe trong Reader**: đang tạm dừng truyện này, cùng chương, đoạn đang dừng còn trong vùng an toàn của màn hình (`ParagraphTracker.isParagraphInsideSafeViewport`, cùng điều kiện tự cuộn) ⇒ `resume()`; đã kéo đi chỗ khác ⇒ giữ như cũ (dừng rồi đọc từ đoạn trên cùng). Muốn nghe chỗ khác vẫn có bôi đen → "Nghe".
- **Siri (`system`)**: `pause()` không tăng `audibleHandoffGeneration` cho Siri nữa — trước đây `onFinish` của utterance được `continueSpeaking()` bị `isContextValid` loại nên đọc xong chunk là im. Stop/skip vẫn tăng qua `stopCurrentPlayback()`.
- Đánh đổi: mất kiểu "dừng → kéo trang → tiếp tục ở widget/màn khoá thì đọc từ chỗ mới" (có từ 07/2026). `TTSChunkPositionMapper.indexForParagraphPosition` không còn caller trong `Sources/` nhưng giữ nguyên.
- Chuyển entry `[1.3.568]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới** (`TTSManager.swift` 3510 → 3500 dòng). CI là cổng biên dịch; chưa thử trên máy.

## [1.3.597] - 2026-10-25

### feat: kết quả tìm trong một nguồn theo kiểu hiển thị của loại nguồn

Người dùng: *"màn hình search chưa theo config layout, video, truyện, commic đang chỉ 1 kiểu, tôi đang nói search 1 nguồn"*.

- **Tìm trong một nguồn** (`SearchSingleSourceResultsView`, mới): dựng theo `BookListLayout` của loại nguồn đang tìm — `BookListLayoutScope(kind: SearchExtensionScopePolicy.kind(of:))`, cùng phạm vi với Khám phá của nguồn đó. Kiểu Danh sách giữ nguyên dòng cũ (bìa 50×70, mô tả → nội dung → tác giả, chip tên nguồn); kiểu Lưới / Chỉ bìa dùng `ScrollView` + `LazyVGrid` của `DiscoveryNovelGridCardView` (video bìa ngang 16:9, số cột theo cài đặt). Đang đổi nguồn thì chạm vẫn hỏi xác nhận; còn lại mở Chi tiết truyện, `bookId` giữ dạng cũ.
- **`SearchView`**: nút "Kiểu hiển thị" (icon theo kiểu đang chọn, 17pt semibold) ở góc phải thanh điều hướng, chỉ hiện khi tìm trong một nguồn (kể cả trước khi có kết quả), mở `BookListLayoutSheet`; đang tìm ở kiểu lưới thì hiện khung chờ dạng lưới (`DiscoverySkeletonGridView`). `searchResultCover` thành `static` để view mới dùng chung.
- Không đổi: tìm trên mọi nguồn (dải bìa ngang theo nguồn), chỉ tải trang 1, công tắc dịch của màn Tìm kiếm.
- Chuyển entry `[1.3.567]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. CI là cổng biên dịch; chưa thử trên máy.

## [1.3.596] - 2026-10-24

### feat: màn Thông báo hiện phần trăm từng tập khi tải video

Người dùng: *"Cho màn hình thông báo cũng xem được phần trăm tải của từng tập"*.

- **Màn Thông báo** (`NotificationInboxView+StoryTasks`, hàng tác vụ đang chạy): tác vụ tải video ghi "Tải video · 3/10 tập · 34%" (trước là "Tải truyện · … chương"), thanh tiến độ chạy mượt theo phần trăm tập đang tải, thêm dòng "Tập 4: 45% · 210 MB" và nút **"Chi tiết tập (N)"** dùng chung `VideoEpisodeProgressList` với tab Tải. Tác vụ truyện/xuất ebook giữ nguyên.
- `DownloadTask.smoothProgressCount` / `videoProgressPercent` (mới, cạnh `VideoEpisodeProgress`): một chỗ tính tiến độ mượt + phần trăm cho cả tab Tải lẫn màn Thông báo.
- Chuyển entry `[1.3.566]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. CI là cổng biên dịch; chưa thử trên máy.

## [1.3.595] - 2026-10-24

### feat: tab Tải hiện phần trăm từng tập của tác vụ tải video

Người dùng: *"vì tải video khả năng sẽ tốn khá nhiều thời gian, do đó đối với video tôi cần xem được phần trăm tải của từng video"*; chọn hiện ở **tab Tải** (không thêm gì lên ô tập trong trình phát), mockup đã duyệt.

- **`VideoEpisodeProgress`** (mới, `Services/Download`): trạng thái một tập — chờ / đang tải (phần trăm + byte) / xong (byte) / có sẵn / lỗi / đã huỷ. **`DownloadTask.videoEpisodes`**: trạng thái tạm, không lưu CSDL (không đổi `DownloadTaskModel`); app khởi động lại thì mất, thử lại tác vụ dựng lại.
- **`DownloadManager+Video`**: dựng danh sách lúc bắt đầu (tất cả "Chờ"), tập bỏ qua ⇒ "Có sẵn", bắt đầu ⇒ "Đang tải 0%", xong ⇒ "Xong" kèm dung lượng từ manifest, lỗi ⇒ lý do, huỷ ⇒ tập đang tải và các tập còn chờ thành "Đã huỷ". `VideoDownloadDetailReporter` (≤ 1 lần/giây) cập nhật trạng thái tập **và** dòng `mediaDetail` trong một lần ghi `tasks` (`updateVideoEpisode`; thay `updateMediaDetail`); nhịp đến muộn không kéo tập đã xong về "đang tải".
- **Tab Tải** (`DownloadTrackerView`): tác vụ video có thanh tiến độ chạy mượt trong tập (`progressCount` + phần trăm tập đang tải) và chữ "Tiến độ: 3/10 tập · 34%"; nút **"Chi tiết tập (N)"** (`VideoEpisodeProgressList`, mới) mở/thu danh sách "✓ Xong · 480 MB", "✓ Có sẵn", "↓ 45% · 210 MB", "Chờ", "✕ Lỗi: …", "Đã huỷ" — hiện ở mọi trạng thái tác vụ khi có danh sách. Trên 60 tập thì chỉ hiện mọi tập lỗi (tối đa 50), 10 tập xong gần nhất, tập đang tải, 5 tập chờ kế tiếp, kèm dòng đếm "Xong · Đang tải · Lỗi · Chờ · Đã huỷ".
- Chuyển entry `[1.3.565]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. CI là cổng biên dịch; chưa thử trên máy.

## [1.3.594] - 2026-10-24

### feat: bấm PiP thì trình phát tự thu nhỏ về màn trước

Người dùng: *"khi nhấn video sang pip hãy tự trở về màn hình trước khi vào màn hình phát"*.

- `VideoPictureInPictureCoordinator.onDidStart` (mới) báo khi PiP **đã bật xong**; `VideoPlaybackSession.pictureInPictureStartCount` tăng mỗi lần. `VideoPlayerScreen` nghe số này: PiP đang bật và app đang `.active` (tức người dùng bấm nút PiP) ⇒ `leave(stopPlayback: false)` — thu nhỏ như vuốt xuống, phim chạy tiếp trong cửa sổ PiP, hub hiện mục Video; khôi phục từ PiP mở lại màn qua `requestScreen` như cũ.
- Chờ `didStart` chứ không rời màn ở `willStart`: gỡ layer khỏi cửa sổ lúc PiP đang bật dở có thể làm PiP hỏng. PiP **tự bật khi rời app** (app không còn `.active`) giữ nguyên màn như trước.
- Chuyển entry `[1.3.564]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. CI là cổng biên dịch; chưa thử trên máy (PiP chạy tiếp khi màn đóng, nút khôi phục mở lại đúng màn).

## [1.3.593] - 2026-10-24

### fix: bản tải video phát lại được sau khi app ra nền, ẩn nút xoá khi đã hết bản tải

Rà lại sau 1.3.592 (chưa thử máy), ba lỗi trong code mới:

- **Phát bản tải sau khi app bị treo nền**: listener 127.0.0.1 có thể đã chết nhưng URL item vẫn trỏ cổng cũ, và lượt tự nạp lại chỉ được **một lần mỗi tập** ⇒ tạm dừng / khoá máy lần hai trên cùng tập là báo lỗi, "Tải lại" cũng dùng lại cổng cũ. Nay mỗi lượt nạp HLS bản tải bật server mới (`VideoOfflineHTTPServer.stop()` trước `url(forRelativePath:)`, queue nối tiếp nên tắt xong mới bật); tự nạp lại sau lỗi tối đa một lần mỗi 20 giây (`offlineRetryWindow`, thay `offlineRetriedEpisodeIndex` bằng `offlineLastRetryUptime`).
- **Server không sẵn sàng**: `ensureRunning()` không có hạn chót — listener kẹt ở `.setup`/`.waiting` làm tập quay mãi ở "đang phân giải". Nay quá 3 giây chưa `.ready` ⇒ log ❌, tắt, trả `nil` ⇒ trình phát chuyển sang trực tuyến.
- **Nút "Xoá bản tải" còn hiện khi đã hết bản tải**: xoá dần từng tập / huỷ tập duy nhất để lại thư mục sách rỗng ⇒ `summary.hasFiles` vẫn `true`, nút hiện "0 byte". Nay `hasFiles` chỉ đúng khi còn tập trọn vẹn hoặc còn byte; xoá tập / bỏ bản dở thì dọn luôn thư mục sách rỗng.
- Chuyển entry `[1.3.563]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. CI là cổng biên dịch; vẫn chưa thử trên máy.

## [1.3.592] - 2026-10-24

### feat: tải video về máy để xem offline

Người dùng: *"làm thêm chức năng tải video nữa"*; chốt qua grill-me + mockup (plan `Docs/Plans/2026-10-24-plan-tai-video-offline.md`), rồi *"tự làm đi không cần hỏi nữa"*. Quyết định: tự tải từng đoạn + server nội bộ phát lại; chất lượng mặc định tối đa 720p (chọn lại trong sheet, nhớ cho lần sau); server đã nhớ trước, lỗi thì thử server khác; lối vào ở trang chi tiết + nhấn giữ trên kệ, menu `⋯` trình phát, nhấn giữ ô tập (không có dấu đã tải trên ô); mở tập đã tải phát bản tải + chip "Trực tuyến"; có nút xoá hết bản tải kèm dung lượng.

- **Lưu trữ** (`Services/Video/Offline/`): `VideoOfflineStore` — `videos/<sha256(bookId)>/<episodeIndex>/`, `manifest.json` (`VideoEpisodeManifest`) ghi **sau cùng**, `partial.json` = chữ ký nguồn bỏ query để tải tiếp bản dở, `validatePathSafety` riêng, `videos/` đặt `isExcludedFromBackup`; Backup không gói. `VideoDownloadQuality` (Cao nhất / Tối đa 1080p / 720p / 480p, UserDefaults `videoDownloadQuality`), `VideoDownloadRequestStore` (sidecar tập bắt đầu của "Tải tập này" theo `taskId` — không đổi `DownloadTaskModel`).
- **Bộ tải**: `VideoHLSOfflinePlanner` (thuần: biến thể + rendition của playlist gốc, playlist con ⇒ danh sách khoá/init/đoạn + playlist local URI tương đối; byterange tách file; giữ `MEDIA-SEQUENCE` cho IV AES-128; từ chối `SAMPLE-AES`/`skd://`/live), `VideoHLSDownloader` (chọn mức theo chất lượng, kèm luồng tiếng `EXT-X-MEDIA TYPE=AUDIO` của nhóm, playlist `fbhls://` ghép tiếng đọc từ `subPlaylists`), `VideoFileDownloader` (mp4 ghi luồng ra đĩa, tải tiếp bằng `Range`), `VideoOfflineHTTPClient` (header tiện ích, thử lại 3 lượt; 401/403/404/410 ⇒ phân giải lại link một lần). Tất cả **tuần tự**.
- **Tác vụ** (`DownloadManager+Video`, `VideoEpisodeDownloadPipeline`): nhánh video của `executeMediaTaskIfNeeded` không còn báo "không hỗ trợ"; server → track → `VideoSourceResolver` (bỏ `.embed`) → bộ tải → phụ đề đầu tiên → manifest; `isInteractive: false`. Bỏ qua tập đã có manifest cùng URL tập; còn dưới 1 GB trống ⇒ dừng; huỷ ⇒ bỏ bản dở của tập đang tải, lỗi/khởi động lại ⇒ giữ để tải tiếp. Mỗi phim chỉ một tác vụ video chạy một lúc (`runNextTasksIfNeeded`); "Tải tập này" trùng tập đang chờ/đang tải thì không thêm. `DownloadTask.mediaDetail` (tạm) = "Tập 4: 45% · 210 MB"; `displayTypeName` = "Tải video" (rawValue "Tải truyện" giữ nguyên vì được lưu bền).
- **Phát bản tải** (`VideoPlaybackSession+Offline`): `runEpisodeLoad` thử bản tải **trước** khi tra tiện ích ⇒ xem được khi không mạng / tiện ích đã gỡ. HLS qua `VideoOfflineHTTPServer` + `VideoOfflineHTTPResponder` (`NWListener` **chỉ 127.0.0.1**, cổng + token ngẫu nhiên, chỉ file dưới `videos/`, `GET`/`HEAD` + `Range`), mp4 phát `file://`; phụ đề + mốc "Bỏ qua" từ manifest. Bản tải không kiểm tiếng; item lỗi ⇒ bật lại server, nạp lại một lần. Chip "Bản tải" / "Trực tuyến" ở hàng server và menu server.
- **UI**: `VideoOfflineLibrary` (`@MainActor @Observable`) là nguồn trạng thái đã tải/đang tải/dung lượng cho View. Menu `⋯`: "Tải tập này" / "Xoá bản tải tập này" + "Tải nhiều tập…" (`TaskOptionsSheet`). Nhấn giữ ô tập: "Tải tập này" / "Xoá bản tải". Trang chi tiết: "Tải video offline" + "Xoá bản tải · N tập · X GB" (`VideoDownloadsDeletePill`). Nhấn giữ trên kệ: "Tải video offline" + "Xoá bản tải (…)" (`VideoDownloadsActionRow`, xử lý ngay trong sheet). `TaskOptionsSheet` chế độ video ("Tải từ tập đang xem", "Số lượng tập", "Chất lượng"). Tab Tải: "Tải video", "x/y tập", dòng phần trăm trong tập.
- **Xoá**: `BookStorageManager` (cả 3 đường xoá) và `BookSourceMigrator` xoá `videos/<sha256(bookId)>`; `BookContentDestination` mở phim đã tải bằng trình phát khi tiện ích đã gỡ.
- Tài liệu: `rules.md` mục "Tải video offline (1.3.592)"; `CLAUDE.md`/`AGENTS.md` thêm `videos/` vào danh sách lưu trữ + mục Comic & Video. Chuyển entry `[1.3.562]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code + agent soát lỗi biên dịch; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch. **Chưa thử trên máy**: AVPlayer phát HLS qua `http://127.0.0.1` trong LiveContainer, `NWListener` loopback (có hỏi quyền Mạng cục bộ không), khoá AES-128, nguồn ngụy trang đoạn `.jpg/.png`, tải tiếp sau khi app ra nền. Thử lần đầu: bật log, tải 1 tập từ menu `⋯` → tab Tải có % → bật chế độ máy bay → mở tập (chip "Bản tải") → tua, phụ đề; lỗi thì gửi `app_logs.txt` (dòng `[VideoOffline]`, `[VideoOfflineServer]`).

## [1.3.591] - 2026-10-24

### feat: tắt NSFW ẩn khỏi Kệ/Bộ sưu tập/Tải/hub/phạm vi dịch, video trình duyệt phát tại chỗ, player chọn chất lượng

Người dùng: *"khi tắt nfsw thì cũng phải ẩn ở kệ sách nữa"*, *"nói chung tắt nfsw thì mọi danh sách phim, comic, truyện đều phải ẩn. liệt kê ra chỗ còn sót rồi tôi sẽ duyệt"*; *"browser của app khi click vào video luôn tự mở rồi phóng to lên…"*; *"thêm mục chọn chất lượng cho player nếu được"*. Duyệt: Kệ sách, Bộ sưu tập, tab Tải, hub nổi, phạm vi dịch + plan video trình duyệt + chất lượng; **không** lọc Thông báo (chương mới) và thứ đang phát (widget TTS, màn khoá, PiP). Tải video tách sang phiên riêng.

- **`RepositoryFilterPolicy.excludingNsfwSources(_:includeNsfw:packageId:)`** (mới, generic): bỏ phần tử của nguồn NSFW, giữ thứ tự, mỗi `packageId` tra một lần — dùng chung cho các danh sách dưới đây. Chỉ ẩn hiển thị, dữ liệu giữ nguyên.
- **Kệ sách** (`ShelfBookPartition(hidesNsfw:)`, đổi từ `hidesNsfwHistory`): tắt NSFW bỏ **mọi** sách của nguồn NSFW, cả ghim/chưa ghim lẫn lịch sử (chip loại suy ra từ partition nên tự theo). **Tìm trong Kệ** quan sát công tắc, bỏ cả sách trên kệ.
- **Bộ sưu tập**: danh sách trong bộ (`CollectionDetailView`), 3 bìa xem trước + số truyện của thẻ (`CollectionGridCardView.visibleBooks(of:includeNsfw:)`), số truyện ở màn sắp xếp bộ.
- **Tab Tải** (`DownloadTrackerView`): ẩn tác vụ tải/xuất của truyện nguồn NSFW (tác vụ vẫn chạy).
- **Hub nổi** (`FloatingHubPresentationReader`): "AI đang chạy" bỏ truyện của nguồn NSFW — run AI không lưu `packageId` nên suy từ tiền tố `bookId` (`BookIdUtils.make` = `<packageId viết thường>_<16 hex>`), không khớp tiện ích nào thì không ẩn; mục Video coi phim NSFW thu nhỏ như không có video (nút hub không nháy vì nó). `VideoMiniPlayerState.packageId` (mới, ghi trước `isActive`). Công tắc theo dõi qua `UserDefaults.didChangeNotification` rút về một bit.
- **Quản lý phạm vi dịch** (`TranslationScopeManagementView`): không liệt kê nguồn NSFW và truyện của nguồn NSFW (truyện đã xoá khỏi thư viện thì không biết nguồn ⇒ vẫn liệt kê); cấu hình vẫn có hiệu lực, "Đặt lại tất cả" vẫn xoá cả mục bị ẩn.
- **Video trong trình duyệt phát tại chỗ**: `BypassBrowserTabStore` bật `allowsInlineMediaPlayback`; **`InlineMediaScript`** (mới, `Services/Browser`) gắn `playsinline`/`webkit-playsinline` cho mọi `<video>` ở mọi frame (quét DOM, `MutationObserver`, `loadstart` + chạm ở pha capture — không sửa prototype). Tab mở từ link dùng config WebKit chép từ tab mẹ nên cũng có. Nút toàn màn hình của trang vẫn dùng được.
- **Chất lượng** (`VideoPlaybackSession+Quality`, `VideoQualityOption` — mới): sau mỗi item đọc `AVAsset.variants`, mỗi độ phân giải giữ biến thể bitrate cao nhất, bỏ biến thể chỉ tiếng; từ 2 mức ⇒ menu `⋯` có "Chất lượng · <mức>" (Tự động + 1080p/720p…). Chọn = **trần** (`preferredPeakBitRate` + `preferredMaximumResolution`) — mạng yếu vẫn có thể thấp hơn. Lựa chọn giữ qua các tập (áp mức cao nhất không vượt lựa chọn), `stop()` về Tự động. `refreshBandwidthLimit` gộp: đang ẩn ⇒ thấp nhất, hiện ⇒ trần đã chọn hoặc không giới hạn. mp4 / HLS một mức / playlist ghép hình + tiếng ⇒ không có mục.
- Cài đặt › Nội dung nhạy cảm: dòng Kệ đổi thành danh sách các chỗ ẩn mới.
- Chuyển entry `[1.3.561]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy (đặc biệt: `variants` với asset qua resource loader `fbhls://`, `playsinline` trên các trang thật).

## [1.3.590] - 2026-10-24

### feat: Google/Bing/Baidu lên đầu, tắt NSFW giữa lượt tìm bỏ nguồn NSFW, player ẩn điều khiển khi vuốt và hạ chất lượng khi phát ẩn

Người dùng: *"để google, bing, baidu lên đầu danh sách. khi tìm tất cả nếu tắt nsfw thì không tìm các nguồn nsfw. ở phần player, nếu vuốt tua nhanh, tăng giảm sáng, tăng giảm âm lượng hãy tự ẩn phần đường timeline và các nút tua 10s. nếu được thì khi video phát ở chế độ ẩn thì hãy phát audio của nó thôi để giảm lưu lượng tốn"*; duyệt plan (ẩn **cả** lớp điều khiển khi vuốt; **giữ** ngoại lệ đổi nguồn cho truyện NSFW — *"bật nsfw mới xem được nsfw"*).

- **Truy cập nhanh** (`BypassBrowserHomeView`): Google, Bing, Baidu đứng đầu rồi mới tới tiện ích; tiện ích trùng đúng URL của một trong ba thì bỏ ô trùng.
- **Tìm mọi nguồn**: tắt NSFW từ trước thì vốn đã không tìm nguồn NSFW (`searchableExtensions` → `applyNsfwFilter`). Sửa ca **tắt giữa lượt tìm**: `SearchView.dropHiddenNsfwSources` gỡ nguồn NSFW khỏi `sourceStates` (số "Tìm thấy N", trạng thái rỗng, vòng "đang tìm" tính lại), kết quả về muộn của khoá đã gỡ bị bỏ; `LegadoSearchScheduler.searchAll(shouldStart:)` xét lại nguồn Legado **đang xếp hàng** lúc tới lượt — NSFW mà công tắc đã tắt thì không chạy (báo `nil`). Request của tiện ích JS đã gửi thì không thu hồi được. Ngoại lệ đổi nguồn cho sách của nguồn NSFW giữ nguyên, tách thành `SearchExtensionScopePolicy.keepsNsfw` dùng chung cho cả lọc lẫn bộ lập lịch.
- **Player — vuốt** (`VideoPlayerController.handlePanBegan`): bắt đầu vuốt tua / độ sáng / âm lượng ⇒ ẩn **cả** lớp điều khiển (kiểu YouTube), nhả tay vẫn ẩn, chạm để hiện lại; vuốt xuống thu nhỏ không đổi.
- **Player — phát ẩn** (`VideoPlaybackSession.refreshBandwidthLimit`): khi đã tách hình (thu nhỏ / nền không PiP — vốn đã chỉ phát tiếng) đặt `preferredPeakBitRate = 1` ⇒ HLS xuống biến thể thấp nhất; gắn lại hình ⇒ `0`. Gọi ở `refreshLayerAttachment` và sau `replaceCurrentItem` (tập kế tự phát lúc đang ẩn). Chỉ đỡ dữ liệu với HLS **nhiều** mức chất lượng; mp4, playlist một mức, playlist ghép hình + tiếng (`VideoAudioRenditionComposer`) không giảm được; không đổi sang luồng chỉ tiếng (thay item lúc PiP/nền/thu nhỏ làm hỏng các ca đó). Về lại màn hình thì vài giây đầu hình còn mờ.
- Chuyển entry `[1.3.560]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.589] - 2026-10-24

### feat: tắt NSFW tự đóng màn của nguồn NSFW, Home trình duyệt chỉ giữ Google/Bing/Baidu

Người dùng: *"khi tôi xem các màn khác của nguồn nfsw mà nếu sau đó tôi tắt nfsw đi thì hãy tự tắt các màn đó đi giúp tôi, phím tắt nhanh ở home ngoài các tiện ích ra hãy chỉ giữ lại google, bing, baidu thôi"*; duyệt plan (đóng cả màn của truyện trên Kệ, làm luôn vuốt lùi về Home hết ẩn danh).

- **`NsfwSourceScreenGuard`** (mới, `Views/Common`, `.closesWhenNsfwHidden(packageId:isEnabled:)`): màn của một nguồn tự `dismiss` khi công tắc NSFW toàn app bị tắt mà màn đã **thấy NSFW bật** lúc đang mở (bật lúc mở hoặc bật trong lúc mở) — màn mở khi NSFW đang tắt (sách NSFW trên Kệ) không bị đụng. `packageId` chụp ở lần xuất hiện đầu: Khám phá đổi nguồn khi NSFW tắt và dựng lại màn thể loại đang mở với nguồn **mới**, đọc giá trị sống thì không bao giờ đóng. Xét cả ở `onAppear` (màn ở tab khác / dưới stack có thể chưa nhận `onChange` tới khi hiện lại); `dismiss()` chạy ở lượt main kế tiếp; log không ghi tên nguồn.
- Gắn vào **Chi tiết truyện** (`BookDetailView` — mọi lối vào, kể cả truyện trên Kệ), **danh sách thể loại / xem thêm** (`CategoryNovelsListView`), **tìm trong một nguồn** (`SearchView` ở chế độ một nguồn, không phải đổi nguồn — `isEnabled` đọc sống theo công tắc "tìm mọi nguồn"). Tìm mọi nguồn: `SearchView` quan sát công tắc NSFW và truyền thẳng vào `searchableExtensions` ⇒ nhóm kết quả của nguồn NSFW biến mất ngay; dòng "Tìm thấy N truyện" giữ số cũ tới lượt tìm sau.
- Không cần guard: Reader / truyện tranh / video / trình duyệt (toàn màn hình) và cấu hình tiện ích / chi tiết nguồn Legado (sheet) — lúc chúng mở không với tới công tắc NSFW. TTS đang đọc truyện NSFW và widget nổi **không** bị dừng.
- **Home trình duyệt**: Truy cập nhanh ngoài ô tiện ích chỉ còn Google, Bing, Baidu (bỏ YouTube, Bilibili, Weibo, Zhihu, Wikipedia, Dịch GG, Tangthuvien, Qidian, 69shu).
- **Ẩn danh**: lùi/tiến về Home (`about:blank` của khung chính, `navigationType == .backForward`) cũng tắt `isIncognito` như nút Home; cửa sổ mới mở trống (cũng `about:blank`, loại `.other`) giữ ẩn danh thừa hưởng. **Chưa kiểm trên máy** việc WebKit có gọi `decidePolicyFor` cho trang lấy từ bộ đệm lùi/tiến hay không.
- Cài đặt › Nội dung nhạy cảm thêm dòng giải thích màn tự đóng.
- Chuyển entry `[1.3.559]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.
