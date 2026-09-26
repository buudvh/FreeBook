# CHANGELOG - Nhật ký Thay đổi CodeGraph FreeBook

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **FreeBook**.

## [1.3.409] - 2026-09-26

### feat: toi uu man hinh dich reader, sua do ui ai chat va them nhap tu dien tu truyen khac

Sửa **7** file và thêm **1** file Swift mới (`BookImportSourceSheet.swift`) trong `Sources/Services/Translation/`, `Sources/Views/Dictionary/` và `Sources/Views/Reader/AI/`.

- **Tối ưu tra cứu Base Dictionary & Quản lý từ điển (`TranslationManager.swift`, `DictionaryHubView.swift`)**:
  - `TranslationManager.existsInBaseDictionary`: Trả về kết quả ngay lập tức khi `loadedBaseDict` đã có trên RAM, ngăn ngừa trôi xuống nạp lại file `.dat` 30MB từ đĩa khi xoá từ tuỳ chỉnh trong `ManageDefinitionsView` hoặc gắn badge VP/NE.
  - `DictionaryHubView`: Bỏ lệnh `loadAllDictionaries()` trong `.onAppear`, loại bỏ việc nạp lại từ điển khi mở hub.
- **Khắc phục đơ UI / TTS & Tối ưu AI Streaming (`ReaderAIFullScreenView.swift`, `ReaderAIFullScreenView+Actions.swift`, `AIRuntimeCoordinator.swift`)**:
  - `ReaderAIFullScreenView`: Xoá bỏ việc gọi `resolveExtractedNames` trong body/`messageRow`, chuyển sang đọc thuộc tính tĩnh `message.extractedNames`, chấm dứt hoàn toàn vòng lặp re-render liên tục gây lock Main Thread và làm gián đoạn TTS khi mở AI chat session có sẵn tin nhắn.
  - `ReaderAIFullScreenView+Actions`: Thêm migration ngầm `migrateLegacyJSONMessagesIfNeeded()` trong background task (`Task.detached`) khi nạp session để nâng cấp tin nhắn JSON cũ một lần duy nhất mà không ảnh hưởng UI.
  - `AIRuntimeCoordinator`: Áp dụng throttle cập nhật streaming delta ở mức 20 FPS (50ms) thay vì dispatch MainActor trên từng token mạng.
- **Nhập từ điển riêng từ truyện khác (`BookImportSourceSheet.swift`, `DictionaryListView.swift`, `DictionaryListView+Transfer.swift`)**:
  - `BookImportSourceSheet`: Tạo sheet chọn truyện nguồn với giao diện và thành phần đồng bộ 100% với `BookShareTargetSheet`, hỗ trợ tìm kiếm theo tên gốc/tên dịch và dialog xác nhận 2 chế độ Gộp / Thay thế.
  - `DictionaryListView+Transfer`: Tiếp nhận các hàm chuyển giao `shareToBook`, `importFromBook`, `importFile`, đưa `DictionaryListView.swift` về 681 dòng vật lý (dưới baseline 690, giảm 1 vi phạm kiến trúc nền).
- **Lưu trữ Changelog**: Đẩy 9 entry cũ (`[1.3.372]` - `[1.3.380]`) sang `CHANGELOG.archive.md` để giữ `CHANGELOG.md` gọn gàng (27 entry).
- **Tài liệu CodeGraph**: Cập nhật `00_index.md`, `02_file_graph.md`, `04_call_graph.md`, `09_dependency_rules.md`, `11_subsystems.md`, `14_complexity_report.md` (`--accept`); `06_event_graph.md`, `07_dataflow.md`, `08_lifecycle.md`, `13_resource_lifecycle.md` (`--no-change-needed`).

## [1.3.408] - 2026-09-26

### feat: tu dong nhan dien response json ten rieng kich hoat the duyet va tinh chinh icon clipboard

Sửa **5** file Swift trong `Sources/Services/AI/`, `Sources/Views/Reader/AI/`, `Sources/Views/Settings/AI/`:

- **Tự Động Nhận Diện Response JSON Tên Riêng & Kích Hoạt Thẻ Duyệt (`AIRuntimeCoordinator.swift`, `ReaderAIFullScreenView.swift`)**:
  - `AIRuntimeCoordinator`: Sau khi AI hoàn tất streaming hội thoại (`accumulated`), tự động đưa qua `AINameExtractionBatchProcessor.parseNamesFromJSONString`. Nếu là mảng JSON tên riêng, tự động đối chiếu từ điển truyện để trang trí nhãn `VP`/`NE` qua `AIBookDataInspector.decorateExtractedNames`, gán `extractedNames = decorated`, thu gọn tiêu đề thành `"Đã tìm thấy \(decorated.count) tên riêng trong phản hồi:"` và lưu trực tiếp vào `activeSession` cũng như `AIChatHistoryStore`.
  - `ReaderAIFullScreenView`: Bổ sung cơ chế fallback tự động bóc tách on-the-fly trong `messageRow` (`resolveExtractedNames`). Nếu tin nhắn trợ lý chưa có `extractedNames` nhưng nội dung là mảng JSON tên riêng hợp lệ, tự động trang trí nhãn VP/NE và hiển thị ngay `ReaderAINameReviewCardView` kèm tiêu đề tóm tắt (ẩn khối JSON thô dài dòng).
- **Tinh Chỉnh Giao Diện Các Nút Thao Tác Clipboard Tinh Gọn (`AISettingsView+Actions.swift`, `BookAIMemorySheet.swift`)**:
  - Loại bỏ hoàn toàn nhãn chữ (`Xoá`, `Sao chép`/`Copy`, `Dán tiếp`/`Dán`).
  - Chuyển sang hiển thị icon SF Symbols tinh gọn (`trash`, `doc.on.doc`, `doc.on.clipboard`) với khung cố định $28 \times 26\text{ pt}$ có nền bo góc, chống triệt để tình trạng tràn layout hoặc rớt dòng chữ khi đặt cạnh tiêu đề dài.
- **Quy Tắc & Chỉ Dẫn AI Dùng Chung Mặc Định Chuẩn Hoá (`BookAIMemoryStore.swift`)**:
  - Cập nhật hằng số `defaultGlobalMemoryPrompt` theo đúng văn bản định dạng nghiêm ngặt của người dùng, yêu cầu chỉ trả về mảng JSON thuần tuý `[{"original": "...", "suggestedMeaning": "..."}]` không markdown, không code block.

## [1.3.407] - 2026-09-26

### feat: ho tro nhieu api key kem tu dong doi key loi, mac dinh bearer auth cho anthropic, sap xep ten rieng ai va sao luu ai

Sửa **14** file Swift trong `Sources/Models/`, `Sources/Services/`, `Sources/Views/`:

- **Quản Lý Nhiều API Key & Tự Động Failover (`AIProviderProfile.swift`, `AnthropicClient.swift`, `OpenAIClient.swift`)**:
  - `AIProviderProfile`: Thêm `apiKeys: [String] = []`, `anthropicAuthHeader: String = "bearer"` ("bearer" mặc định vs "x-api-key"), và hàm `allEffectiveApiKeys()` gộp danh sách các API key hợp lệ từ mảng và trường đơn cũ.
  - `AnthropicClient`: Sửa `resolveEndpoint` không chèn thừa `/v1`, hỗ trợ chọn Header (`Authorization: Bearer <token>` mặc định, `x-api-key`), tự động failover sang key tiếp theo trong danh sách candidate khi gặp lỗi HTTP 401, 403, 429 hoặc quota. Thêm `testChatPing`.
  - `OpenAIClient`: Bổ sung cơ chế failover tự động qua danh sách API keys khi gặp HTTP 401, 403, 429 hoặc quota, hàm `cleanToken`, và `testChatPing`.
- **Giao Diện Nhập API Keys Đa Dòng & Thanh Clipboard Tiện Ích (`AISettingsView.swift`, `AISettingsView+Actions.swift`)**:
  - Hỗ trợ `TextEditor` nhập danh sách API keys (mỗi dòng 1 key), đếm số key hợp lệ.
  - Bổ sung thanh công cụ clipboard (Xoá, Sao chép, Dán tiếp vào dòng mới không đè nội dung cũ) cho cả API Keys và danh sách Model.
  - Thêm Picker chọn định dạng Header Auth cho Anthropic (`Authorization: Bearer <token>` mặc định).
- **Trí Nhớ AI Toàn Cục & Tự Động Hiển Thị Thẻ Tên Riêng (`BookAIMemoryStore.swift`, `ReaderAIFullScreenView+Actions.swift`, `ReaderAINameReviewCardView.swift`, `BookAIMemorySheet.swift`, `AIPromptSettingsView.swift`)**:
  - `BookAIMemoryStore`: Quản lý file `global_memory.txt` dưới `Application Support/ai_memory/` làm quy tắc lọc tên dùng chung toàn app, tự động tiêm vào `systemInstruction`.
  - `ReaderAIFullScreenView+Actions`: Khi trợ lý AI phản hồi JSON danh sách tên riêng, tự động bóc tách bằng `AINameExtractionBatchProcessor.parseNamesFromJSONString`, trang trí nhãn VP/NE và hiển thị ngay `ReaderAINameReviewCardView`.
  - `ReaderAINameReviewCardView`: Thêm tuỳ chọn sắp xếp `selectedFirst` (mặc định) và `alphabetical`, nút sắp xếp lại bằng tay, không tự động đảo vị trí khi tick checkbox, chống vỡ layout khi tên dài.
  - `BookAIMemorySheet`: Bổ sung Segmented Picker 2 tab ("Truyện này" & "Trí nhớ tổng") kèm thanh clipboard dán nối tiếp dòng.
  - `AIPromptSettingsView`: Bổ sung Section quản lý Trí nhớ AI toàn cục và khôi phục mặc định.
- **Sao Lưu & Khôi Phục Dữ Liệu AI (`BackupSettingsArchiver.swift`, `BackupPaths.swift`, `BackupConfigArchiver.swift`)**:
  - `BackupSettingsArchiver`: Đưa `"FreeBook_AI_Configuration_V1"` vào danh sách khoá được phép xuất trong cài đặt.
  - `BackupPaths` & `BackupConfigArchiver`: Khai báo và sao lưu/khôi phục thư mục `ai_memory/` (chứa `global_memory.txt` và ghi chú từng sách) trong file backup `.fbbackup`.

## [1.3.406] - 2026-09-25

### feat: them dinh dang anthropic claude native api va cap nhat danh sach model

Thêm **2** file Swift mới, sửa **8** file Swift trong `Sources/Models/`, `Sources/Services/`, `Sources/Views/`:

- **Tích Hợp Anthropic Claude Messages API Native (`AnthropicClient.swift`, `AnthropicTypes.swift`)**:
  - `AnthropicClient`: Triển khai singleton actor kết nối API native `/v1/messages` của Anthropic với header xác thực `x-api-key: <token>` và `anthropic-version: 2023-06-01`.
  - Tự động tách `role == "system"` thành trường `system` cấp cao nhất của request JSON, gộp và chuẩn hóa role luân phiên `user`/`assistant`, hỗ trợ cả streaming SSE (`content_block_delta`) và non-streaming response.
  - `AnthropicTypes`: DTO struct `AnthropicMessageRequest`, `Response`, `StreamDelta` lồng nhau đảm bảo đúng 1 primary type top level.
- **Cập Nhật Danh Sách Model Mới Nhất & Cấu Hình Định Dạng API (`AIProviderProfile.swift`, `AIProviderPreset.swift`)**:
  - Bổ sung trường `apiFormat: String` ("openai" hoặc "anthropic") trong `AIProviderProfile`, hỗ trợ giải mã tương thích ngược.
  - Thêm preset `defaultAnthropic` với danh sách model chính thức mới nhất: `claude-3-7-sonnet-latest`, `claude-3-5-sonnet-latest`, `claude-3-5-haiku-latest`, `claude-3-7-sonnet-20250219`, `claude-3-5-sonnet-20241022`, `claude-3-opus-latest`.
  - Cập nhật preset OpenRouter Claude với model mới: `anthropic/claude-3.7-sonnet`, `anthropic/claude-3.7-sonnet:thinking`, `anthropic/claude-3.5-sonnet`, `anthropic/claude-3.5-haiku`, `anthropic/claude-3-opus`.
- **Rẽ Nhánh Điều Phối AI Client Trong Ứng Dụng (`AIRuntimeCoordinator.swift`, `AIContextCompactor.swift`, `AINameExtractionBatchProcessor.swift`)**:
  - `AIRuntimeCoordinator`: Rẽ nhánh streaming gọi `AnthropicClient.shared.sendChatStreaming` khi `activeProfile.apiFormat == "anthropic"`.
  - `AIContextCompactor` & `AINameExtractionBatchProcessor`: Rẽ nhánh gọi `AnthropicClient.shared.sendChat` khi `activeProfile.apiFormat == "anthropic"`.
- **Giao Diện Cài Đặt AI (`AISettingsView.swift`, `AISettingsView+Actions.swift`, `AddProviderProfileSheet.swift`)**:
  - Bổ sung Picker chọn "Định dạng API" (`OpenAI` vs `Anthropic Claude`).
  - Thêm mẫu template "Anthropic Claude (Chính thức)" trong sheet thêm provider mới.
  - Hỗ trợ tải danh sách model từ API và kiểm tra kết nối qua Anthropic Messages API.

## [1.3.405] - 2026-09-25

### fix: xoa provider chatgpt web va openai oauth, space token rule va tien xu ly so 10 1000

Thêm **2** file Swift mới, xoá **5** file Swift, sửa **7** file Swift trong `Sources/Models/`, `Sources/Services/`, `Sources/Views/`:

- **Xoá Hoàn Toàn Provider ChatGPT Web & OpenAI OAuth**:
  - Xoá 5 file: `ChatGPTWebClient.swift`, `ChatGPTWebLoginSheet.swift`, `OpenAIOAuthManager.swift`, `OpenAIOAuthLoginSheet.swift`, `AISettingsView+OAuth.swift`.
  - Dọn sạch logic nhánh `authType == "web"` và `authType == "oauth"` trong `OpenAIClient.swift`, `AISettingsView.swift`, `AISettingsView+Actions.swift`, `AddProviderProfileSheet.swift`, `AIProviderPreset.swift`, `AIProviderProfile.swift`.
  - Khôi phục cấu hình AI về chuẩn API Key thuần tuý, đơn giản hoá và ổn định.
- **Tự Động Khoảng Trắng 2 Bên Token Rule Dịch (`QuickTranslationRuleEngine.swift`)**:
  - Tự động chèn khoảng trắng 2 bên kết quả render của rule dịch (ví dụ câu `我买了四个苹果` với rule `<n>个` -> `我买了 4 cái 苹果`).
  - Gắn khoảng trắng vào `rendered` của rule thay vì passthrough segment, bảo toàn tuyệt đối 1:1 mapping ký tự gốc cho việc tra cứu từ điển và highlight.
- **Tiền Xử Lý Số Rời Rạc TTS (`TTSNumberSeparatorMode.swift`, `TTSReplacementManager.swift`, `TTSSettingsView+NumberPreprocessing.swift`, `TTSSettingsView.swift`)**:
  - `TTSNumberSeparatorMode`: Enum 4 chế độ (`all`, `smart`, `fourDigits`, `off`) dùng regex lookahead `(\d+)(?:\s*[-–—]\s*|\s+)(?=(\d+))` thay thế khoảng cách giữa 2 cụm số (`10 1000`, `10-1000`) thành `, ` (`10, 1000`) giúp TTS không bị đọc gộp số.
  - Tích hợp vào `TTSReplacementManager.applyReplacements(to:)` áp dụng chung cho mọi engine TTS (NghiTTS/Piper, Google TTS, Siri, Extension TTS).
  - Thêm Picker chọn chế độ trong `TTSSettingsView`, giữ file chính an toàn trong baseline (518/519 dòng).

## [1.3.404] - 2026-09-25

### fix: sua scope openai oauth, sua url fetch chatgpt web va tang size icon header len 16pt

Sửa **5** file Swift trong `Sources/Services/AI/` và `Sources/Views/`:

- **Chuẩn Hóa Scope Xác Thực OpenAI OAuth (`OpenAIOAuthManager.swift`)**:
  - Loại bỏ scope `model.request` khỏi `defaultScopes` (chỉ gửi `openid profile email offline_access`), phù hợp với quyền hạn của client ID `app_EMoamEEZ73f0CkXaXp7hrann` của OpenAI, khắc phục lỗi "The OAuth 2.0 Client is not allowed to request scope 'model.request'".
- **Khắc Phục Lỗi Gửi Tin Nhắn ChatGPT Web (`ChatGPTWebClient.swift`)**:
  - Chuyển toàn bộ lời gọi `fetch` trong JavaScript sang URL tuyệt đối `https://chatgpt.com/api/auth/session` và `https://chatgpt.com/backend-api/conversation` kèm `credentials: 'include'`, tránh lỗi "URL is not valid or contains user credentials" khi webview chưa load xong origin.
  - Tăng số lần thử chờ domain từ 10 lên 25 chu kỳ (5s).
- **Tăng Kích Thước Icon Header Lên 16pt (`ReaderHeaderFooterOverlayView.swift`, `BookDetailView.swift`, `BookDetailView+Extensions.swift`)**:
  - Reader Header: Tăng font size của các icon thao tác (`chevron.left`, `magnifyingglass`, `scroll`/`scroll.fill`, `arrow.clockwise`, `sparkles`, `gearshape`, `ellipsis.circle`) từ 13pt lên 16pt (`.font(.system(size: 16, weight: .semibold))`).
  - BookDetail Toolbar: Tăng `iconSize` của `ReaderTranslationScopeMenuView` và font size icon của `ellipsisMenu` từ 13pt lên 16pt, đồng bộ kích thước cân đối trên thanh công cụ.

## [1.3.403] - 2026-09-25

### feat: chuyen theme picker sang thanh ngang, sua chatgpt web, tich hop chatgpt oauth, config cookie ext va sua loi dich so

Thêm **3** file Swift mới, sửa **9** file Swift trong `Sources/Models/`, `Sources/Services/`, `Sources/Views/`:

- **Giao Diện Trình Đọc (`ReaderSettingsView.swift`)**:
  - Chuyển Picker chọn giao diện nền đọc (Theme) từ dạng List/Menu dọc sang dạng thanh ngang `.pickerStyle(.segmented)` với 3 lựa chọn trực quan: Sáng, Trầm ấm, Tối.
- **Sửa Lỗi ChatGPT Web (`ChatGPTWebClient.swift`)**:
  - Khắc phục lỗi "đăng nhập rồi nhưng vẫn báo chưa hoàn tất đăng nhập" bằng cách đọc trực tiếp cookie `__Secure-next-auth.session-token` từ `WKWebsiteDataStore.default().httpCookieStore` và URL tuyệt đối.
  - Sửa lỗi `JavaScript execution returned a result of an unsupported type` bằng cách bọc script async trong IIFE trả về primitive String (`(() => { (async () => { ... })(); return "started"; })()`).
- **Tích Hợp OpenAI ChatGPT OAuth PKCE (`OpenAIOAuthManager.swift`, `OpenAIOAuthLoginSheet.swift`, `AISettingsView.swift`, `AISettingsView+OAuth.swift`, `AISettingsView+Actions.swift`, `AddProviderProfileSheet.swift`, `AIProviderPreset.swift`, `AIProviderProfile.swift`, `OpenAIClient.swift`)**:
  - `OpenAIOAuthManager`: Triển khai chuẩn OAuth 2.0 PKCE với S256 (`code_verifier` và `code_challenge`), sinh URL xác thực với client ID `app_EMoamEEZ73f0CkXaXp7hrann`, trao đổi code lấy access token và refresh token tại `https://auth.openai.com/oauth/token`, tự động làm mới access token khi hết hạn và giải mã JWT payload để lấy email tài khoản.
  - `OpenAIOAuthLoginSheet`: WebView đăng nhập tài khoản OpenAI, tự động chặn redirect `http://localhost:1455/auth/callback` và xác thực state bảo mật CSRF.
  - `OpenAIClient`: Tự động gọi `OpenAIOAuthManager.shared.getValidAccessToken` để lấy token hợp lệ khi gọi API streaming và non-streaming với profile OAuth.
  - `AISettingsView+OAuth`: Tách UI quản lý tài khoản OAuth và logic logout thành file extension riêng, giữ `AISettingsView.swift` dưới 400 dòng vật lý.
- **Cấu Hình Cookie Cho Tiện Ích (`ExtensionConfigView.swift`, `JSExecutor.swift`)**:
  - `ExtensionConfigView`: Bổ sung section "Mạng & Cookie" cho phép người dùng cấu hình bật/tắt `http_should_handle_cookies` cho từng extension (mặc định bật).
  - `JSExecutor`: Đọc cấu hình `http_should_handle_cookies` và gán vào `request.httpShouldHandleCookies`. Khi tắt, `URLSession` không đính kèm cookie hệ thống, ngăn chặn triệt để lỗi HTTP 400 do dính Google Login Cookies.
- **Khắc Phục Lỗi Dịch Số Dính Liền (`QuickTranslationRuleMatcher.swift`, `QuickTranslationRuleEngine.swift`)**:
  - `QuickTranslationRuleMatcher`: Trong `walkNumeral`, phân tách hoàn toàn giữa chữ số ASCII/Full-width (`0-9`, `０-９`) và chữ số Hán (`〇-九`, `十百千万...`), ngăn việc gộp nhầm `1` và `四` thành `14` trong `<n>个`.
  - `QuickTranslationRuleEngine`: Trong `appendPassthrough(upTo:)`, thêm kiểm tra `needsSeparator(between: output, and: piece)` để chèn dấu cách ngăn cách giữa kết quả dịch của rule và số/chữ passthrough kế tiếp (khắc phục lỗi dính liền `"4 cái"` và `"0"` thành `"4 cái0"`).

## [1.3.402] - 2026-09-25

### feat: tich hop provider chatgpt web khong gioi han quota qua wkwebview

Thêm **2** file Swift mới, sửa **4** file Swift trong `Sources/Models/`, `Sources/Services/`, `Sources/Views/`:

- **Giao Tiếp ChatGPT Web Ngầm (`ChatGPTWebClient.swift`, `OpenAIClient.swift`)**:
  - `ChatGPTWebClient`: Singleton điều phối một `WKWebView` chạy ngầm chia sẻ `WKWebsiteDataStore.default()`, kiểm tra trạng thái phiên qua `/api/auth/session` và gửi request tới `/backend-api/conversation`.
  - Tích hợp Temporary Chat (`history_and_training_disabled: true`), không lưu lại lịch sử hội thoại trên web của người dùng và không huấn luyện model.
  - Streaming SSE: Bộ đọc stream trong JavaScript trích xuất nội dung delta và truyền qua `WKScriptMessageHandler` về Swift dạng `AsyncThrowingStream<String, Error>`.
  - `OpenAIClient`: Kiểm tra `authType == "web"`, tự động điều hướng `sendChat` và `sendChatStreaming` sang `ChatGPTWebClient`.
- **Giao Diện Đăng Nhập & Cài Đặt (`ChatGPTWebLoginSheet.swift`, `AISettingsView.swift`, `AddProviderProfileSheet.swift`, `AIProviderPreset.swift`, `AIProviderProfile.swift`)**:
  - `ChatGPTWebLoginSheet`: Sheet mở trang web `https://chatgpt.com` để người dùng đăng nhập tài khoản, kiểm tra trạng thái phiên trực tiếp.
  - `AISettingsView`: Hiển thị nút "Đăng nhập / Quản lý ChatGPT Web" thay cho trường API Key khi profile có `authType == "web"`. Nút "Kiểm tra kết nối" kiểm tra phiên đăng nhập web thay vì gọi `/models`.
  - `AddProviderProfileSheet`: Bổ sung mẫu `ChatGPT Web (Không lo hết quota)` với danh sách model mặc định `auto`, `gpt-4o`, `gpt-4o-mini`, `o3-mini`.
  - `AIProviderProfile`: Mở rộng thuộc tính `authType: String = "apiKey"` hỗ trợ tương thích ngược.

## [1.3.401] - 2026-09-25

### feat: tai va hien thi icon extension tren home trinh duyet bypass

Sửa **1** file Swift trong `Sources/Views/Common/`:

- **Hiển Thị Icon Extension Cục Bộ Trên Home Trình Duyệt Bypass (`BypassBrowserHomeView.swift`)**:
  - Mở rộng struct `QuickShortcut` với `extLocalPath: String?` và `extIconUrl: String?`.
  - Trong `allShortcuts`, truyền đường dẫn cài đặt cục bộ và URL ảnh trực tuyến cho từng extension đã cài đặt.
  - Sử dụng [`ExtensionIconView`](../../Sources/Views/Common/ExtensionIconView.swift) size 30 đặt gọn trong ô card 50x50, đọc ảnh `icon.png` trực tiếp qua bộ nhớ đệm [`ExtensionIconImageCache`](../../Sources/Views/Common/ExtensionIconImageCache.swift), giữ nguyên fallback SF Symbol cho các phím tắt trang mặc định.

## [1.3.400] - 2026-09-25

### feat: tuy bien size nut dich va thu gon khoang cach icon danh sach chuong va header reader

Sửa **5** file Swift trong `Sources/Views/Reader/` và `Sources/Views/BookDetail/`:

- **Tùy Biến Size Nút Dịch & Tối Ưu Chấm Trạng Thái (`ReaderTranslationScopeMenuView.swift`, `BookDetailView.swift`, `BookDetailView+Extensions.swift`)**:
  - `ReaderTranslationScopeMenuView`: Bổ sung tùy chọn `iconSize`, `frameWidth`, `frameHeight` với giá trị mặc định là 19pt và khung 44x52/36; tối ưu hóa dấu chấm override khi không có khung nền gắn trực tiếp vào góc icon qua `.overlay(alignment: .topTrailing)`.
  - `BookDetailView`: Đồng bộ nút dịch trên Toolbar Trailing sang `iconSize: 13, frameWidth: 32, frameHeight: 32` tương đồng chuẩn xác với nút dropdown `ellipsisMenu` bên cạnh. Loại bỏ sub-menu dịch trùng lặp trong `ellipsisMenu` (`BookDetailView+Extensions.swift`) và xóa computed property `translationStatus` thừa.
- **Thu Nhỏ & Gom Gần Nút Icon Danh Sách Chương (`ReaderChapterListView.swift`)**:
  - Đưa 3 nút icon (`character.bubble`, `arrow.clockwise`, `arrow.up.arrow.down`) về font size 13pt, giảm khung xuống 30x30 và gom trong `HStack(spacing: 2)`.
- **Thu Hẹp Khoảng Cách Cụm Icon Header Reader (`ReaderHeaderFooterOverlayView.swift`)**:
  - Gom các nút thao tác bên phải vào `HStack(spacing: 2)` với khung gọn 30x36 (hoặc 30x30), giảm khoảng cách giữa chúng, giúp thanh điều hướng thoáng đãng và liền mạch.

## [1.3.399] - 2026-09-25

### feat: sua loi cuon den man hinh ai va tang tuong phan nut badge the ten rieng

Sửa **2** file Swift trong `Sources/Views/Reader/AI/`:

- **Khắc Phục Lỗi Cuộn Đen Màn Hình AI (`ReaderAIFullScreenView.swift`)**:
  - Chuyển `LazyVStack` sang `VStack` để tính toán chiều cao tin nhắn tất định, loại bỏ lỗi vỡ toạ độ khi gửi tin nhắn mới.
  - Bổ sung modifier `.defaultScrollAnchor(.bottom)` của iOS 17 và thêm delay 0.08s trước khi cuộn tới ID tin nhắn cuối cùng để chờ keyboard và bubble hoàn tất layout.
- **Tăng Tương Phản Thẻ Tên Riêng Dark Mode (`ReaderAINameReviewCardView.swift`)**:
  - Nút "Lưu Name riêng" và "Lưu VP riêng" đổi nền sang `#374357` (`Color(red: 55/255.0, green: 67/255.0, blue: 87/255.0)`) với viền sáng `stroke(Color.white.opacity(0.18))` và chữ trắng đậm.
  - Badge Category chuyển sang nền xám đậm `Color(white: 0.25)` chữ trắng.
  - Badge NE và VP tăng độ mờ nền `opacity(0.25)`, chữ trắng kèm viền stroke rõ nét đồng bộ với suggest chip của Reader.
  - Checkbox chọn và icon `tag.fill` đổi sang màu xanh sáng rõ nét `Color(red: 90/255.0, green: 170/255.0, blue: 255/255.0)`.

## [1.3.398] - 2026-09-25

### feat: nang cap toan dien giao dien ai, giu chuong da tai va session khi doi nguon, ghim khong dong sheet va toi uu icon header

Thêm **4** file Swift mới, sửa **18** file Swift trong `Sources/Models/`, `Sources/Services/`, `Sources/Views/`, `Sources/Common/`:

- **Di Trú Dữ Liệu Đổi Nguồn Sách (`BookSourceMigrator.swift`, `SearchView.swift`, `AIChatHistoryStore.swift`, `BookAIMemoryStore.swift`, `TranslationManager+BookScopedFiles.swift`)**:
  - Tạo actor `BookSourceMigrator`: sao chép toàn bộ chương đã tải (`BookBinManager` + `ChapterStore`), chuyển lịch sử chat AI (`AIChatHistoryStore.migrateSessions`), chuyển bộ nhớ AI (`BookAIMemoryStore.migrateMemory`), copy cấu hình dịch (`TranslationConfigStore.setBookOverride`), và dọn dẹp an toàn file `.bin` cũ nếu không phát TTS.
  - Bổ sung `QuickTranslateEngineConfig.json` vào `bookScopedMigrationFiles`.
  - Giảm kích thước `SearchView.swift` từ 868 xuống 858 dòng (dưới baseline 872).
- **Tái Cấu Trúc Toàn Diện Giao Diện AI (`ReaderAIFullScreenView.swift`, `ReaderAIInputBarView.swift`, `ReaderAINameReviewCardView.swift`, `ReaderAISessionListView.swift`, `AIBookDataInspector.swift`, `AIHarnessMode.swift`)**:
  - Header: nút back tròn `chevron.down`, tiêu đề hiển thị tên session 1 dòng dưới "Trợ lý AI", menu dropdown `ellipsis.circle` gom các nút tính năng.
  - Đổi màu chủ đạo phân hệ AI sang tone slate navy `#242c38`.
  - Tin nhắn AI loại bỏ icon sparkles, text căn lề trái. Thanh nhập gom mode 1 hàng (`Manual`, `Plan`, `Bypass`) và phóng to nút gửi 36x36.
  - Thẻ trích xuất tên riêng kiểm tra chéo cả từ điển riêng và chung (`Names.dat`, `VietPhrase.dat`), tự động bỏ chọn mặc định nếu đã có từ trước, đồng bộ màu badge NE (đỏ) và VP (xanh nhạt), nút lưu 1 hàng không icon tone `#242c38`.
- **Mở Rộng Bộ Nhớ Truyện AI (`BookAIMemory.swift`, `BookAIMemoryStore.swift`, `BookAIMemorySheet.swift`, `ReaderAIFullScreenView+Actions.swift`)**:
  - Hỗ trợ lưu trữ nhân vật/bối cảnh, tóm tắt cốt truyện, snapshot từ điển và ghi chú riêng. Tự động đồng bộ thầm lặng khi khởi tạo phiên chat.
- **Trang Chủ Bypass WebView & Quản Lý Lịch Sử Duyệt Web (`BypassBrowserHomeView.swift`, `BrowserHistoryStore.swift`, `BrowserHistorySheetView.swift`, `BypassBrowserTabStore.swift`, `BypassWebView.swift`)**:
  - Trang chủ dark theme native dạng lưới 4x3 phân trang cho domain phổ biến, kèm 10 mục lịch sử gần đây và sheet quản lý/tìm kiếm lịch sử.
- **Tối Ưu Kệ Sách & Danh Sách Chương Reader (`BookActionSheet.swift`, `BookActionRunner.swift`, `ReaderChapterListView.swift`, `ReaderChapterListStore.swift`, `ReaderHeaderFooterOverlayView.swift`, `BookDetailView+Extensions.swift`, `ReaderView.swift`)**:
  - Giữ mở context menu sau khi ghim truyện ở Kệ sách.
  - Tự động làm mới danh sách chương trong Reader khi hoàn tất dịch lại tiêu đề.
  - Thu nhỏ icon header về 13pt (chỉ thu nhỏ hàng trên cùng cùng hàng nút back ở Reader).
  - Sửa vòng lặp loading vô hạn khi ấn Back từ màn hình Đổi nguồn Reader mà không chọn nguồn mới.

## [1.3.397] - 2026-09-24

### fix: sua loi reader load lai khi dong ai va mat tin nhan khi mo lai tu widget

Sửa **5** file Swift trong `Sources/Views/Reader/AI/`, `Sources/Views/Reader/Extensions/`, `Sources/Views/Reader/`:

- **Khôi Phục Toàn Màn Hình Native Trong Reader & Bảo Toàn Skeleton Handshake (`ReaderView.swift`, `ReaderView+AI.swift`, `AIRuntimeCoordinator.swift`)**:
  - Khôi phục `.fullScreenCover(isPresented: $showingAIFullScreen)` của SwiftUI ngay tại `ReaderView` thay cho modal UIKit `.fullScreen`. Cây view `ReaderView` không bị unmount khỏi Window, không bị trigger lại lifecycle, bảo toàn cổng handshake skeleton loading (`isChapterSubtreeRenderable`) $\rightarrow$ text hiển thị tức thì, không kẹt skeleton loading hay reload lại khi đóng AI.
  - Quản lý cờ `isReaderActive` trong `onAppear`/`onDisappear` của `ReaderView`. Khi người dùng ở trong Reader mà bấm mở lại từ Floating Widget thu nhỏ, `AIRuntimeCoordinator` phát notification `reopenReaderAI` để `ReaderView` mở lại qua `.fullScreenCover`. Khi mở từ ngoài Reader (Kệ sách, Khám phá), Coordinator dùng `modalPresentationStyle = .overFullScreen` để không làm mất ViewController bên dưới.
- **Lưu Đĩa Tức Thì & Nguồn Sự Thật Duy Nhất Cho Chat AI (`AIRuntimeCoordinator.swift`, `ReaderAIFullScreenView.swift`, `ReaderAIFullScreenView+Actions.swift`)**:
  - Ghi đĩa tức thì qua `AIChatHistoryStore.shared.saveSession` ngay tại khoảnh khắc khởi tạo tin nhắn người dùng và tin nhắn chờ của AI (áp dụng cho gõ tay, chip Tóm tắt, Bối cảnh, Dịch mượt, Lọc name chương, Quét batch).
  - Quản lý `activeSession: AIChatSession?` làm Source of Truth trong `AIRuntimeCoordinator.shared`. Tích luỹ token stream và kết quả trích xuất vào `activeSession` xuyên suốt quá trình chạy ngầm.
  - Khi mở lại AI từ widget, `initializeSession()` ưu tiên nạp ngay `activeSession` của Coordinator (nếu trùng `bookId`), đồng thời đồng bộ reactive các token delta và tiến trình batch qua Combine `$activeSession`, `$isRunning`, `$batchProgress`.

## [1.3.396] - 2026-09-24

### feat: dong bo ai dang suy nghi, chay ngam toan app va floating widget thu nho

Thêm **5** file Swift mới, sửa **5** file Swift trong `Sources/Views/Reader/AI/`, `Sources/Views/Reader/Extensions/`, `Sources/Views/Reader/`, `Sources/App/`:

- **Điều Phối Vòng Đời Tác Vụ Ngầm & Toast Hoàn Thành (`AIRuntimeCoordinator.swift`)**:
  - Tạo `AIRuntimeCoordinator` quản lý `Task` chạy ngầm độc lập khỏi vòng đời View cho streaming chat, lọc name chương hiện tại và quét batch các chương đã tải.
  - Tự động nạp/lưu phiên chat vào `AIChatHistoryStore` và phát thông báo Toast qua `ToastManager.shared.show(..., type: .success)` khi tác vụ hoàn tất ở trạng thái ngầm (khi màn hình AI đang đóng).
  - Cung cấp cơ chế `presentFullScreen(context:)` thông qua việc tìm `findTopViewController()` ở tầng window `.normal`, cho phép mở lại màn hình AI toàn màn hình từ bất kỳ đâu (Shelf, Reader, BookDetail, Settings) mà không phụ thuộc vào `ReaderView` và không bị xung đột modal.
- **Cửa Sổ & Widget Nổi Toàn Ứng Dụng (`AIFloatingWidgetWindowManager.swift`, `AIFloatingWidgetUIWindow.swift`, `AIFloatingWidgetContainerViewController.swift`, `AIFloatingWidgetView.swift`)**:
  - `AIFloatingWidgetUIWindow`: `UIWindow` riêng biệt có windowLevel `alert - 3` (thấp hơn TTS `alert - 1` và Browser `alert - 2` một bậc để tránh tranh chấp hit-testing, đảm bảo chạm vào TTS widget luôn được ưu tiên).
  - Passthrough touch chuẩn xác cho các điểm chạm ngoài viên pill để không chặn thao tác giao diện bên dưới.
  - `AIFloatingWidgetContainerViewController`: Quản lý cử chỉ `UIPanGestureRecognizer` và `UITapGestureRecognizer`, snap mượt mà vào mép màn hình bằng `FloatingWidgetGeometry` và lưu vị trí người dùng kéo vào `UserDefaults`. Chạm vào widget kích hoạt mở lại toàn màn hình AI.
  - `AIFloatingWidgetView`: Viên pill mờ (`.ultraThinMaterial`) với viền tím tinh tế, icon `sparkles` tím animated, text trạng thái tiến trình và nút tròn `xmark` huỷ tác vụ nhanh.
- **Đồng Bộ Chỉ Báo "AI đang suy nghĩ" & Đóng An Toàn Khi TTS Điều Hướng (`ReaderAIFullScreenView.swift`, `ReaderAIFullScreenView+Actions.swift`, `ReaderView.swift`, `ReaderView+AI.swift`)**:
  - Khởi tạo tin nhắn phản hồi với `content: ""` và `isStreaming: true` cho mọi thao tác (gõ tay, chip Tóm tắt, Bối cảnh, Dịch mượt, Lọc name chương, Lọc name cả bộ tải) -> luôn hiển thị động `ReaderAIThinkingIndicatorView` với text đồng nhất `"AI đang suy nghĩ"`.
  - Lắng nghe sự kiện điều hướng từ TTS Widget (`openCurrentlyPlayingReader`, `navigateReaderToPlayingChapter`) để tự động đóng màn hình AI an toàn, nhường quyền điều hướng cho Reader mà không làm gián đoạn tác vụ AI đang chạy ngầm.
  - Chuyển `onOpenAI` trong `ReaderView` sang `openAIFromReader()`, loại bỏ modal `.fullScreenCover` cục bộ giúp giảm dòng code trong `ReaderView.swift` (từ 2049 xuống 2042 dòng, dưới baseline 2053).

## [1.3.395] - 2026-09-24

### feat: sua loi nut dich kham pha khi chuyen nguon trung viet

Sửa **4** file Swift trong `Sources/Services/Translation/Utils/`, `Sources/Views/Reader/`, `Sources/Views/Discovery/`, `Sources/Views/BookDetail/`:

- **Khắc Phục Vòng Đời Nút Dịch Khám Phá (`ReaderTranslationScopeMenuView.swift`, `DiscoveryView.swift`, `BookDetailView.swift`)**:
  - `ReaderTranslationScopeMenuView`: Bổ sung tham số `isChineseSourceHint: Bool?` và hai bộ lắng nghe `.onChange(of: packageId)`, `.onChange(of: bookId)` để kích hoạt `refreshStatus()` ngay khi nguồn hoặc truyện thay đổi.
  - `DiscoveryView`: Gán `.id("discovery-translate-\(selectedExtensionId)")` cho nút dịch trên toolbar để SwiftUI tái khởi tạo view tương ứng với nguồn mới; truyền `isChineseSourceHint: selectedExtension?.isChineseSource`.
  - `BookDetailView`: Đồng bộ truyền `isChineseSourceHint: ext?.isChineseSource` vào `ReaderTranslationScopeMenuView` và các lời gọi `isTranslationEnabled`.
- **Nâng Cấp Cache & Cơ Chế Dò Nguồn Tiếng Trung (`TranslationConfigStore.swift`)**:
  - Thêm bộ nhớ đệm `sourceIsChineseMap` cùng phương thức `registerSource(packageId:isChinese:)` giúp tra cứu trạng thái nguồn O(1).
  - Tối ưu hàm `isChineseSource`: tìm kiếm đệ quy thư mục con cấp 1 trong thư mục extension khi file zip giải nén vào folder con lồng nhau; hỗ trợ trích xuất `type`, `locale`, `language` từ cả đối tượng `metadata` lẫn root `plugin.json`.
- **Cập Nhật Tức Thì Trạng Thái Dịch Thẻ Truyện (`DiscoveryView.swift`)**:
  - Cập nhật cờ `isTranslationEnabled` ngay khi đổi nguồn hoặc nhận thông báo cấu hình dịch thay đổi, giúp các thẻ truyện hiển thị tên dịch tức thì mà không cần tải lại mạng.

## [1.3.394] - 2026-09-24

### feat: dong bo popup dich mau trang, toi uu danh sach chuong va do mo chuong da doc

Sửa **9** file Swift trong `Sources/Models/Database/`, `Sources/Services/Translation/Utils/`, `Sources/Views/Reader/`, `Sources/Views/BookDetail/`, `Sources/Views/Discovery/`:

- **Popover Cấu hình Dịch Thuật Tone Trắng Tối Giản (`ReaderTranslationScopeMenuView.swift`, `DiscoveryView.swift`, `BookDetailView.swift`)**:
  - Viết lại nút dịch thành Popover nhỏ gọn với `.presentationCompactAdaptation(.popover)`, giao diện `.preferredColorScheme(.dark)`.
  - Thay đổi toàn bộ nút điều khiển sang tone màu TRẮNG (`.white`), toggle switch sử dụng `.tint(.white)`, nút Lưu lại viền trắng tối giản thay cho màu xanh primary mặc định.
  - Tích hợp đồng nhất Popover dịch tại thanh công cụ của Reader, Chi tiết truyện (`BookDetailView`) và màn hình Khám phá (`DiscoveryView`).
- **Tối ưu Danh Sách Chương & Độ Mờ Chương Đã Đọc (`ReaderChapterListView.swift`, `ReaderChapterListView+List.swift`, `ReaderChapterRowView.swift`, `BookDetailTOCView.swift`)**:
  - Tách huy hiệu nguồn/extension (`Local` / `Extension`) thành một hàng riêng biệt phía trên số chương trong danh sách chương Reader.
  - Thêm nút icon chuyên dụng "Dịch lại chương" (`character.bubble` màu trắng) trên Header cạnh nút đảo chiều để dịch lại toàn bộ tiêu đề chương và xóa cache hiển thị khi người dùng yêu cầu.
  - Làm mờ tiêu đề các chương đã đọc (`logicalIndex < currentChapterIndex` hoặc `chap.index < currentIdx`) với độ mờ `opacity: 0.40` ở cả danh sách chương Reader và Chi tiết truyện.
- **Tối ưu Hiển Thị Khi Bật Tắt Dịch Trong Reader (`ReaderView.swift`)**:
  - Bỏ việc kích hoạt `scheduleCoalescedTranslationRefresh` và `retranslateChapterTitles` trong sự kiện `.onChange(of: isTranslationEnabled)` giúp chuyển đổi hiển thị bản dịch tức thì 0ms, không gây reload hay chớp giật.
  - Đồng bộ trạng thái dịch tự động thông qua `NotificationCenter` từ `TranslationConfigStore.didChangeNotification`.
- **Mặc Định Bật Dịch Cho Nguồn Tiếng Trung (`Extension.swift`, `TranslationConfigStore.swift`)**:
  - Thêm computed property `Extension.isChineseSource` nhận diện các nguồn truyện Trung Quốc (`chinese_novel` hoặc locale chứa `zh`/`cn`).
  - `TranslationConfigStore.resolveStatus` tự động mặc định Bật dịch cho nguồn tiếng Trung khi chưa có cấu hình override, các nguồn khác mặc định Tắt dịch.

## [1.3.393] - 2026-09-24

### feat: cau hinh bat tat dich phan cap truyen nguon va toan cuc

Thêm **3** file Swift mới và sửa **8** file Swift trong `Sources/Services/Translation/`, `Sources/Services/TTS/`, `Sources/Views/Reader/`, `Sources/Views/BookDetail/`, `Sources/Views/Settings/`:

- **Quản lý cấu hình dịch phân cấp 3 mức (`TranslationConfigStore.swift`, `TranslateUtils.swift`)**:
  - `TranslationConfigStore`: Quản lý phân cấp 3 tầng rõ ràng: Truyện (`bookOverrides`) > Nguồn truyện (`sourceOverrides`) > Toàn cục (`globalEnabled`). Lưu trữ an toàn trong `UserDefaults` bằng từ điển JSON, không can thiệp schema SwiftData `@Model`.
  - Phân giải ưu tiên `resolveStatus(bookId:packageId:)`: Truyện đặt Bật/Tắt -> Áp dụng cấu hình Truyện; Truyện để Mặc định -> Áp dụng cấu hình Nguồn; Nguồn để Mặc định -> Áp dụng cấu hình Toàn cục.
  - Hỗ trợ thông báo reactive qua `TranslationConfigStore.didChangeNotification`.
- **Menu xổ xuống 1 chạm trên Header Reader & BookDetail (`ReaderTranslationScopeMenuView.swift`, `ReaderHeaderFooterOverlayView.swift`, `BookDetailView.swift`, `BookDetailView+Extensions.swift`)**:
  - Nút Menu Dịch (`character.bubble`) trên Header Reader và Toolbar Chi tiết truyện hiển thị nguồn gốc quyết định (`Truyện này`, `Nguồn này`, `Toàn cục`) kèm chấm tròn chỉ thị màu khi có cấu hình riêng.
  - Chạm mở ngay menu xổ xuống trực quan với 3 sections: Truyện này (Mặc định / Luôn Bật / Luôn Tắt), Nguồn này (Mặc định / Luôn Bật / Luôn Tắt), Toàn cục (Bật / Tắt).
- **Bộ điều khiển 3 mức trong Sheet Cài đặt đọc (`ReaderSettingsView.swift`)**:
  - Bổ sung nhóm điều khiển phân cấp trong mục Cấu hình Dịch Thuật: Picker cho Truyện này, Picker cho Nguồn này, Toggle Toàn cục.
- **Màn hình Quản lý Tập trung cấu hình dịch riêng (`TranslationScopeManagementView.swift`, `SettingsView.swift`)**:
  - Màn hình quản lý danh sách tập trung các nguồn và truyện đã override, cho phép chuyển đổi trạng thái, vuốt xoá từng mục hoặc đặt lại tất cả về mặc định.
  - Tích hợp đường dẫn `NavigationLink` trong Section Dịch Thuật Quick Translate của `SettingsView`.
- **Đồng bộ phân cấp Dịch sang TTS (`TTSManager.swift`)**:
  - Tự động nạp cờ dịch theo phân cấp của cuốn sách đang phát khi khởi chạy phiên đọc (`startWithContent` / `start`) thông qua `TranslationConfigStore.shared.isTranslationEnabled(bookId:packageId:)`.

## [1.3.392] - 2026-09-24

### feat: badge vp ne tu dong bo chon ten da co tu dong luu ai va tat auto sang chuong reader

Sửa **7** file Swift trong `Sources/Models/AI/`, `Sources/Services/AI/`, `Sources/Views/Reader/`, `Sources/Views/Settings/AI/`:

- **Badge VP / NE & Bỏ chọn mặc định tên riêng đã có (`AIExtractedName.swift`, `AIBookDataInspector.swift`, `ReaderAINameReviewCardView.swift`, `ReaderAIFullScreenView+Actions.swift`, `AINameExtractionBatchProcessor.swift`)**:
  - `AIExtractedName`: Thêm hai thuộc tính `hasInBookNames: Bool` và `hasInBookVP: Bool`, kèm bộ giải mã tùy biến an toàn tương thích ngược các file JSON chat cũ.
  - `AIBookDataInspector`: Thêm hàm `fetchBookDictionarySets` và `decorateExtractedNames`, đối chiếu với `Names.txt` và `VietPhrase.txt` của cuốn truyện đang đọc để tự động gắn cờ và đặt `isSelected = false` (bỏ chọn mặc định) cho các tên riêng đã tồn tại.
  - `ReaderAINameReviewCardView`: Hiển thị badge `NE` (tím) và `VP` (cam) trên từng hàng tên riêng để người dùng nhận diện trực quan từ nào đã có trong từ điển truyện.
  - `AINameExtractionBatchProcessor`: Không loại bỏ các từ đã có trong từ điển ở tầng xử lý batch để toàn bộ tên trích xuất đều được gắn badge đầy đủ.
- **Tự động lưu Cấu hình AI & Prompt (`AISettingsView.swift`, `AISettingsView+Actions.swift`, `AIPromptSettingsView.swift`)**:
  - Bỏ nút "Lưu" thủ công trên toolbar của `AISettingsView` và `AIPromptSettingsView`.
  - Tự động lưu cấu hình và prompt ngay lập tức khi thay đổi qua `.onChange`, khi đổi/thêm/xóa profile và khi thoát màn hình qua `.onDisappear`.
- **Tắt tự động sang chương của Reader khi tắt cuộn theo Highlight (`ReaderView.swift`)**:
  - Thêm điều kiện `guard !isAutoScrollDisabled else { return }` vào bộ nhận sự kiện `ttsDidAdvanceToNextChapter`.
  - Khi người dùng đã tắt chức năng cuộn theo highlight của TTS, Reader sẽ giữ nguyên chương và vị trí đang đọc thay vì tự ý nhảy sang chương mới theo TTS.

## [1.3.391] - 2026-09-23

### fix: sua loi parse json trich xuat ten rieng ai luon tra ve 0 ket qua

Sửa **2** file Swift trong `Sources/Models/AI/` và `Sources/Services/AI/`:

- **Nâng cấp Resilient JSON Parser trích xuất tên riêng (`AINameExtractionBatchProcessor.swift`)**:
  - Khắc phục lỗi kiểm tra cứng trường `dict["meaning"]` trong khi cấu hình AI yêu cầu `suggestedMeaning` dẫn đến kết quả luôn bị bỏ qua thành rỗng.
  - Bổ sung cơ chế bóc tách JSON đa tầng: bóc tách markdown code fence (`extractMarkdownBlock`) kể cả khi có văn bản phụ bao quanh; fallback cắt lát dải JSON substring mảng `[...]` hoặc object `{...}` qua chỉ số mở/đóng đầu tiên và cuối cùng.
  - Hỗ trợ làm sạch dấu phẩy thừa (trailing commas trước `}` và `]`) thông qua Regex `cleanTrailingCommas`.
  - Mở rộng hỗ trợ đa dạng tên trường (multi-key fallback): từ gốc Hán tự (`original`, `name`, `word`, `hanzi`, `raw`, `chinese`, `text`), nghĩa dịch Hán Việt (`suggestedMeaning`, `meaning`, `translation`, `vietnamese`, `hvdic`, `hanviet`, `viet`, `val`, `value`), phân loại (`category`, `type`, `tag`, `role`) và số lần xuất hiện (`occurrenceCount`, `count`, `occurrences`, `frequency`).
  - Tự động khử trùng lặp và cộng dồn số lần xuất hiện theo từ gốc tiếng Trung.
- **Chuẩn hóa Prompt trích xuất tên riêng (`AIConfiguration.swift`)**:
  - Bổ sung trường mẫu `category` trong `defaultNameExtractionPrompt` để hỗ trợ AI phân loại chính xác các thực thể trích xuất.

## [1.3.390] - 2026-09-23

### feat: nang cap toan dien ai harness tri nho truyen compact va luu tu dien

Thêm **6** file Swift mới và sửa **8** file Swift trong `Sources/Models/AI/`, `Sources/Services/AI/`, `Sources/Views/Reader/`, `Sources/Views/Settings/AI/`:

- **Trí nhớ dài hạn theo truyện & Tự động nạp từ điển (`BookAIMemory.swift`, `BookAIMemoryStore.swift`, `AIBookDataInspector.swift`, `BookAIMemorySheet.swift`)**:
  - Tạo model và store `BookAIMemory` lưu ghi chú bối cảnh, nhân vật của từng cuốn truyện tại `applicationSupportDirectory/ai_memory/`.
  - Tự động nạp các mục từ điển `Names.txt` và `VietPhrase.txt` của cuốn truyện vào System Context, lọc thông minh theo nội dung raw chương hiện tại.
  - Cung cấp sheet `BookAIMemorySheet` để xem và chỉnh sửa nhanh trí nhớ truyện.
- **Tự động compact ngữ cảnh phiên chat (`AIContextCompactor.swift`, `AIChatSession.swift`)**:
  - Tự động tóm tắt các tin nhắn cũ khi session vượt quá 12 tin nhắn thành `contextSummary`, chỉ gửi tóm tắt + 6 tin nhắn mới nhất để tối ưu token và chống tràn context window.
- **Nâng cấp Lưu Từ điển Name riêng & VP riêng (`ReaderAINameReviewCardView.swift`, `AIHarnessService.swift`, `ReaderAIFullScreenView+Actions.swift`)**:
  - Bổ sung 2 nút bấm riêng biệt: `Lưu Name riêng` và `Lưu VP riêng`.
  - Hộp thoại xác nhận 2 chế độ: *Gộp (trùng từ thì thay mới)* và *Thay thế hoàn toàn*.
  - Chuyển đổi nút Lưu thành banner xác nhận màu xanh sau khi lưu thành công, kèm Toast thông báo (sửa cú pháp `ToastManager.shared.show(message:type:)`).
  - Thêm nút xóa từng mục và sửa liên kết hai chiều (binding) bỏ chọn tên riêng trực tiếp vào session messages.
- **Cải tiến giao diện & trải nghiệm AI (`AIMarkdownMessageView.swift`, `ReaderAIThinkingIndicatorView.swift`, `ReaderAIFullScreenView.swift`, `ReaderAIInputBarView.swift`)**:
  - Render phản hồi AI chuẩn Markdown với khối code monospaced có nút chép, tiêu đề và gạch đầu dòng.
  - Animation 3 chấm nảy phát sáng và con trỏ nhấp nháy khi AI đang suy nghĩ.
  - Mốc neo cuộn `bottomScrollAnchor` và tương tác bàn phím chống lỗi cuộn đen màn hình.
  - Menu ngữ cảnh sao chép tin nhắn khi bấm giữ.
  - Tự động nhận diện câu lệnh lọc tên riêng khi người dùng tự gõ.
  - Tự động đóng tab AI khi bấm nhảy chương từ widget TTS (`ReaderView.swift`).
- **Màn hình Tùy chỉnh Prompt AI & Đồng bộ Profile (`AIPromptSettingsView.swift`, `AISettingsView.swift`, `AISettingsView+Actions.swift`, `AISettingsStore.swift`)**:
  - Màn hình tùy chỉnh System Prompt chat và Name extraction prompt.
  - Tinh gọn Profile: chỉ lưu các profile người dùng thực sự thêm hoặc đã nhập API key.
  - Đồng bộ thời gian thực danh sách Profile giữa Cài đặt và Reader AI qua `didChangeNotification`.

## [1.3.389] - 2026-09-23

### feat: quan ly provider profiles doc lap, picker chon mau va sua loi hien thi ai

Thêm **2** file Swift mới và sửa **5** file Swift trong `Sources/Models/AI/`, `Sources/Services/AI/`, `Sources/Views/Reader/`, `Sources/Views/Settings/AI/`:

- **Quản lý Provider Profile độc lập (`AIProviderProfile.swift`, `AIConfiguration.swift`, `AISettingsStore.swift`)**:
  - Tạo struct `AIProviderProfile` lưu trữ cấu hình riêng biệt của từng Provider (`id`, `name`, `baseURL`, `apiKey`, `selectedModel`, `availableModels`, `temperature`, `isCustom`).
  - Nâng cấp `AIConfiguration` chứa mảng `profiles` và `activeProfileId`, tự động di trú dữ liệu legacy không mất cấu hình.
  - Bổ sung các phương thức `saveProfile`, `deleteProfile`, `setActiveProfile` trong `AISettingsStore`.
- **Sheet Thêm Mới Option Provider dạng Picker (`AddProviderProfileSheet.swift`, `AISettingsView.swift`)**:
  - Thay thế thanh chọn nhanh bằng Menu Picker phân nhóm chuẩn iOS (`.pickerStyle(.menu)`) gồm Mẫu có sẵn (Gemini, OpenAI, DeepSeek, OpenRouter, Groq, Ollama), Nhân bản từ Profile đã lưu, và Tuỳ chỉnh trống.
  - Tích hợp nút "⚡ Load từ API" gọi `OpenAIClient.fetchAvailableModels` để tự động tải danh sách models.
  - Giữ duy nhất 1 nút icon `+` trên thanh Navigation bar của `AISettingsView` để thêm Profile mới.
- **Sửa lỗi hiển thị toàn màn hình AI (`ReaderView.swift`, `ReaderView+AI.swift`)**:
  - Chuyển `.fullScreenCover` sang gắn trực tiếp trên `readerSheetLayer` (neo vào UIHostingController chính) thay vì gắn vào `EmptyView` trong ZStack.

## [1.3.388] - 2026-09-23

### fix: chuyen aibookdatainspector sang internal de fix loi bien dich

Sửa access level trong `Sources/Services/AI/Harness/AIBookDataInspector.swift`:

- **Khắc phục lỗi biên dịch dùng kiểu internal trong public API (`AIBookDataInspector.swift`)**:
  - Chuyển `AIBookDataInspector` và các phương thức `fetchDownloadedChapters`, `readRawChapterContent` từ `public` sang `internal` nhằm tương thích với kiểu `StoredChapterSnapshot` (được định nghĩa `internal`).


### fix: nang cap chan doan ci va tranh xung dot type trong ai harness

Cải thiện workflow CI và refactor kiểu dữ liệu trong `Sources/Services/AI/`:

- **Đổi tên kiểu AnyCodable (`OpenAITypes.swift`)**:
  - Đổi tên `OpenAIChatRequest.AnyCodable` thành `OpenAIChatAnyCodable` và bổ sung typealias tương thích ngược nhằm phòng tránh xung đột định danh tiềm ẩn.
- **Nâng cấp công cụ chẩn đoán lỗi CI (`.github/workflows/build-ipa.yml`)**:
  - Bổ sung bước đọc trực tiếp `build_error.log` và trích xuất toàn bộ chuỗi thông báo lỗi/note từ các file serialized diagnostics (`.dia`) để hiển thị tường minh nguyên nhân thất bại trên GitHub Actions.


### fix: sua cac loi bien dich trong phan he ai harness

Sửa **4** file Swift trong `Sources/Services/AI/` và `Sources/Views/Reader/Extensions/`.

- **Sửa API nạp tên riêng trong truyện (`AIBookDataInspector.swift`)**:
  - Đọc danh sách từ/tên riêng từ `Names.txt` qua `DictionaryTextFileStore.loadEntries(from: txtUrl)` thay vì gọi `allWords()` không tồn tại trên `TrieDictionary`.
- **Sửa gọi thêm quy tắc lọc rác (`AIHarnessService.swift`)**:
  - Sử dụng `JunkFilterManager.shared.addRule(pattern:)` trên `MainActor` thay vì `addPattern`.
- **Sửa nạp nội dung chương cho Reader AI (`ReaderView+AI.swift`)**:
  - Truy xuất chương đang đọc qua `viewModel?.cache.get(readerPresentedChapterIndex)` thay vì `cachedChapters`.
- **Loại bỏ non-sendable stored property (`AIChatHistoryStore.swift`)**:
  - Dùng trực tiếp `FileManager.default` trong các hàm thay vì lưu trữ thuộc tính `private let fileManager`, tương thích hoàn toàn với chế độ Swift 6.

## [1.3.385] - 2026-09-23

### feat: them che do ai agent harness toan man hinh o reader voi 3 mode ask plan bypass

Thêm **24** file Swift mới và sửa **3** file Swift trong `Sources/Views/Reader/` và `Sources/Views/Settings/`.

- **Màn hình AI Agent Harness toàn màn hình (`ReaderAIFullScreenView.swift`, `ReaderView+AI.swift`)**:
  - Mở dạng `.fullScreenCover` từ nút icon `sparkles` trên Header và Action Menu của Reader.
  - Hỗ trợ streaming SSE phản hồi theo thời gian thực từ bất kỳ endpoint nào tương thích OpenAI API (Gemini, OpenAI, Claude/OpenRouter, DeepSeek, Groq, Ollama, Custom).
  - Tách `ReaderAIFullScreenView+Actions.swift` giữ cả 2 file dưới trần 400 dòng vật lý.
- **3 chế độ Harness ngay trên khung chat (`ReaderAIInputBarView.swift`, `AIHarnessMode.swift`)**:
  - `Manual (Ask)`: Tạo ActionPlan và hỏi người dùng trước khi áp dụng thay đổi vào dữ liệu truyện.
  - `Plan`: Lập kế hoạch chi tiết các bước, người dùng ấn "Duyệt kế hoạch" mới thực thi.
  - `Bypass permissions`: Tự động thực thi ngay lập tức.
  - Menu chuyển đổi mode dạng Pill Menu ngay trên Input Bar, kèm Model Picker Menu tức thì.
- **Quản lý cấu hình & Model trong Cài đặt (`AISettingsView.swift`, `AISettingsStore.swift`)**:
  - Hỗ trợ preset cho các nhà cung cấp phổ biến kèm cấu hình tùy chỉnh endpoint / API key / timeout.
  - Nút "Load danh sách từ API" (`GET /models`) và TextEditor nhập danh sách model thủ công (mỗi model một dòng).
  - `AISettingsSection.swift` giúp `SettingsView.swift` giảm dòng và loại bỏ khỏi baseline vi phạm kiến trúc.
- **Phân tích raw chapter & Trích xuất tên riêng (`AIBookDataInspector.swift`, `AINameExtractionBatchProcessor.swift`)**:
  - Sử dụng văn bản gốc Hán tự (raw text) từ `ChapterStore` / `BookBinManager` để LLM phân tích chính xác tên riêng, nhân vật, địa danh.
  - Quét batch offline các chương đã tải theo lô 5 chương kèm thanh tiến trình và nút Dừng.
  - Thẻ `ReaderAINameReviewCardView` cho phép duyệt, tick chọn, sửa nghĩa và lưu thẳng vào từ điển truyện (`TranslationManager.shared.saveCustomEntry(..., isName: true, bookId:)`), tự động kích hoạt bảo vệ Name riêng trước Rule dịch.
- **Lưu trữ phiên trò chuyện (`AIChatHistoryStore.swift`, `ReaderAISessionListView.swift`)**:
  - Tự động lưu session chat theo từng truyện dưới `Application Support/ai_chats/<sha256(bookId)>.json`.
  - Hỗ trợ New Chat (`+ Mới`), xem danh sách session cũ và xóa từng session hoặc xóa tất cả.
- **Tài liệu CodeGraph**: Cập nhật `00_index.md`, `02_file_graph.md`, `03_type_graph.md`, `04_call_graph.md`, `05_state_graph.md`, `08_lifecycle.md`, `09_dependency_rules.md`, `10_risk_report.md`, `11_subsystems.md`, `13_resource_lifecycle.md`, `14_complexity_report.md`, `rules.md` và `CHANGELOG.md`.

## [1.3.384] - 2026-09-18

### feat: dua rule tranh chap name rieng len thanh chip o trang thai thua

Sửa **2** file Swift trong `Sources/Services/Translation/Engine/`.

- **Thu thập đầy đủ Rule tranh chấp Name riêng vào thanh chip (`QuickTranslationRuleMatcher.swift`, `QuickTranslationRuleEngine.swift`)**:
  - `QuickTranslationRuleMatcher.walkNumeral`: Đếm `run` số tự nhiên (không ngắt sớm tại ký tự Name riêng) để matcher nhận diện được đầy đủ cụm khớp quét qua Name.
  - `QuickTranslationRuleEngine.collectFound`: Khi `hasConflict == true` ở chế độ `includesDisabled: true`, match tranh chấp vẫn được đưa vào `found` và dịch `cursor = match.start + 1` để không bỏ sót các lượt thử hợp lệ tiếp theo (như `start = 3` ngay sau Name riêng).
  - `QuickTranslationRuleDiagnostics.diagnose`: Match tranh chấp Name riêng không được vào `winners`, tự động nhận `status = .lostOverlap` và hiển thị trên thanh chip ở trạng thái tranh chấp thua (chip mờ).
- **Tài liệu CodeGraph**: Cập nhật `07_dataflow.md`, `11_subsystems.md` và `CHANGELOG.md`.

## [1.3.383] - 2026-09-18

### feat: bao ve name rieng truoc rule dich va co dinh nghia rule panel dich

Sửa **4** file Swift trong `Sources/Services/Translation/Engine/`, `Sources/Views/Reader/` và thêm **1** file Swift mới trong `Sources/Services/Translation/Extensions/`.

- **Cố định ô "Nghĩa rule" trong panel Dịch (`ReaderView+DefinitionPanel.swift`)**:
  - `isLoadingRules` chỉ theo dõi `definitionSession.loadingRules` (bỏ `definitionSession.loading`), giữ nguyên nội dung nghĩa rule khi tra từ điển lúc nới/thu token, loại bỏ triệt để hiện tượng chớp giật.
- **Bảo vệ Name riêng trước Rule dịch (`QuickTranslationRuleMatcher.swift`, `QuickTranslationRuleEngine.swift`, `QuickTranslationRuleEngine+NameProtection.swift`, `QuickTranslationRuleDiagnostics.swift`)**:
  - Thêm `scanBookNameOccupiedIndices(text:bookId:)` quét cây Double Array Trie `bookNames` của truyện để tạo bản đồ `bookNameRanges` và tập hợp `bookNameOccupiedIndices`.
  - `QuickTranslationRuleMatcher.walkNumeral`: Coi ranh giới Name riêng là ranh giới số hợp lệ (bỏ qua chặn `guardsLeft` nếu ký tự liền kề thuộc Name riêng), cho phép các token số (`<n>`, `<y>`, `<h>`, `<d>`) khớp độc lập ngay sát cạnh Name riêng (ví dụ `比唐三六个月` -> `唐三` giữ nguyên "Đường Tam", `六个月` khớp "6 tháng" -> "hơn Đường Tam 6 tháng").
  - `ruleMatchConflictsWithBookNames`: Bất kỳ rule nào cắt ngang hoặc nuốt một phần Name riêng đều bị loại trừ khỏi danh sách trúng tuyển trong cả dịch thật lẫn chẩn đoán (`.lostOverlap`).
  - Tách `QuickTranslationRuleEngine+NameProtection.swift` (50 dòng) để `QuickTranslationRuleEngine.swift` giảm về 372 dòng (< 400 dòng trần kiến trúc).
- **Tài liệu CodeGraph**: Cập nhật `00_index.md`, `02_file_graph.md`, `04_call_graph.md`, `07_dataflow.md`, `09_dependency_rules.md`, `11_subsystems.md`, `14_complexity_report.md` và `CHANGELOG.md`.

## [1.3.382] - 2026-09-18

### feat: tu dong cuon va chon token khi bam chip rule trong panel dich

Sửa **2** file Swift trong `Sources/Views/Reader/`.

- **Tự động chọn token của rule (`ReaderDefinitionOverlayView+Rules.swift`)**:
  - Khi người dùng bấm vào chip rule trên thanh chip rule, gán `selectedWordOffset` và `selectedWordLength` theo `trace.sourceRange`, đồng thời gọi `onUpdateEditorFromSelection()`.
  - Tự động bôi chọn các ký tự câu gốc và token tương ứng, đồng thời nạp nghĩa từ điển và gợi ý cho cụm từ khớp với rule.
- **Tự động cuộn đến vị trí token tương ứng (`ReaderDefinitionOverlayView.swift`)**:
  - Bổ sung `@State internal var ruleScrollTrigger: Int = 0` được tăng mỗi lần bấm chip.
  - Cả hàng ký tự gốc (`originalSentenceRowView`) và hàng token dịch (`translatedTokensRowView`) đều lắng nghe `ruleScrollTrigger` để kích hoạt cuộn mượt (animated) về vị trí ký tự / token tương ứng ở tâm màn hình.
- **Tài liệu CodeGraph**: Cập nhật `04_call_graph.md`, `11_subsystems.md` và `CHANGELOG.md`.

## [1.3.381] - 2026-09-18

### fix: cap nhat rule trace khi mo panel dich va loc signal theo truyen

Sửa **5** file Swift trong `Sources/Services/Translation/Engine/`, `Sources/Views/Reader/` và `Sources/Views/Reader/Extensions/`.

- **Cập nhật rule traces khi mở panel Dịch (`ReaderView+RuleTools.swift`, `ReaderView.swift`)**:
  - Gọi `refreshRuleTraces()` trong `openDefinitionPanel()` và trong `.onChange(of: showingDefinitionSheet)` (khi `newValue == true`) để thanh chip rule nạp dữ liệu chẩn đoán của cả đoạn văn ngay khi mở.
- **Chống reload dải chip khi nới/thu token (`ReaderView+DefinitionLoading.swift`, `ReaderView+DefinitionPanel.swift`)**:
  - `refreshDefinitionRules()` chuyển sang kiểm tra theo đoạn văn gốc `originalSentence == text` và `definitionSession.identity == sessionID`, bỏ phụ thuộc vào selection `range`/`word` của `currentDefinitionSnapshot()`.
  - Khi mở rộng / thu hẹp vùng chọn token trong câu, editor chỉ gọi `loadDefinitionData()` để cập nhật nghĩa từ điển, thanh chip rule giữ nguyên trạng thái hiển thị.
- **Phát và lọc sự kiện rule theo truyện (`QuickTranslationRuleBookStore.swift`, `ReaderView.swift`)**:
  - `QuickTranslationRuleBookStore.notifyChange(bookId:)` gọi thêm `TranslationManager.shared.notifyRulesDidUpdate(bookId: bookId)`.
  - `ReaderView` đăng ký nhận `.quickTranslationRulesDidUpdate` và chỉ reload bản dịch / thanh chip rule khi `targetBookId == nil` (rule chung) hoặc `targetBookId == bookId` (rule riêng đang đọc). Bỏ qua hoàn toàn nếu là thay đổi rule riêng của truyện khác.
- **Tài liệu CodeGraph**: Cập nhật `00_index.md`, `04_call_graph.md`, `05_state_graph.md`, `06_event_graph.md`, `07_dataflow.md`, `11_subsystems.md`, `rules.md` và `CHANGELOG.md`.
