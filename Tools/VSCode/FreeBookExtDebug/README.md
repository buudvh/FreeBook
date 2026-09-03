# FreeBook Extension Debug — VS Code client

Client của debug server trong app FreeBook (iOS). Cho phép chạy `execute(...)` của VBook extension **trên
thiết bị thật** rồi xem trace console/fetch/exception ngay trong VS Code.

> Chưa publish lên Marketplace và chưa có bước build trong CI của repo. Đây là package nguồn, chạy bằng
> `npm install && npm run compile` rồi F5 trong VS Code.

## Yêu cầu

- VS Code desktop 1.85+, workspace **tin cậy** (`workspace.isTrusted`).
- App FreeBook bản Dev/Ad Hoc, đang **foreground**, cùng mạng LAN.
- Trong app: **Cài Đặt → Nhà Phát Triển → Debug Server (LAN) → Bật server**.

## Kết nối

**Không có bước ghép nối** (bỏ từ 1.3.305): server bật là nối được, đúng như một server API trên LAN.

1. App hiện địa chỉ `ws://<ip>:<port>` trong **Cài Đặt → Nhà Phát Triển → Debug Server (LAN)**.
2. VS Code: `FreeBook: Connect to App` (hoặc ô địa chỉ trong Sidebar), dán `ws://ip:port`. Địa chỉ được
   ghi vào `workspaceState` nên lần sau mở lại đúng nó.
3. App hiện tên client trong danh sách kết nối. Không có token, không có bước bấm "Cho phép kết nối".

`parseTarget` nhận cả `192.168.1.5:17772` (tự thêm `ws://`) và chuỗi `freebook-extdebug://pair?host=…&port=…`
kiểu cũ — `token`/`service` trong chuỗi đó bị **bỏ qua**, chỉ `host` + `port` được dùng.

Client nối **trực tiếp theo IP:port**, không cần Bonjour. Bonjour chỉ là tuỳ chọn để thiết bị tự hiện ra;
nếu hệ thống từ chối đăng ký mDNS (hay gặp khi app chạy qua LiveContainer: `NWError -65555 NoAuth`),
server tự chạy tiếp mà không quảng bá.

> Không còn TLS lẫn xác thực nào ở tầng kết nối, nên chốt an toàn duy nhất còn lại là **bấm trên thiết
> bị** cho `Install Staged Draft` / `Rollback`. Chỉ bật server trên mạng bạn tin.

## Lệnh

| Lệnh | Việc |
| --- | --- |
| `FreeBook: Connect to App` | Nhập `ws://ip:port` và kết nối |
| `FreeBook: Select Extension` | Chọn extension trong workspace (có `plugin.json`) hoặc extension đã cài trên app |
| `FreeBook: Browse Extension Folder…` | Chọn tay một thư mục chứa `plugin.json` (kể cả ngoài workspace) |
| `FreeBook: Refresh Workspace Extensions` | Quét lại `**/plugin.json` trong workspace |
| `FreeBook: Run Current execute` | Chạy entrypoint suy ra từ tên file đang mở; tên không thuộc sáu entrypoint chuẩn thì chạy dạng `custom` |
| `FreeBook: Run Script…` | Chọn entrypoint và nhập input, source `installed` |
| `FreeBook: Run Saved Profile` | Như trên nhưng source `draft` — chạy được cả extension **chưa** cài trên app |
| `FreeBook: Stage Workspace Draft` | Gửi snapshot `plugin.json` + `*.js` (gốc và `src/`) lên staging của app; không cần extension đã cài |
| `FreeBook: Install Staged Draft` | Ghi đè extension đang cài, hoặc **cài mới** nếu app chưa có — **cần bấm đồng ý trên thiết bị** |
| `FreeBook: Rollback Installed Extension` | Trả lại bản trước lần cài gần nhất |
| `FreeBook: Cancel Current Run` | Huỷ run đang chạy |
| `FreeBook: Open Trace` | Mở Output Channel |

## Chạy script mà không cần cài

Được — đây là đường mặc định khi phát triển, không phải trường hợp đặc biệt:

1. `FreeBook: Select Extension` → chọn thư mục trong workspace (hoặc `Browse Extension Folder…`).
2. `FreeBook: Stage Workspace Draft` → app nhận snapshot vào `extension-drafts/<packageId>/<revision>/`,
   kiểm size + SHA-256 từng file rồi validate.
3. `FreeBook: Run Saved Profile` → `run.start` với `sourceMode: "draft"`, chạy **thẳng từ thư mục
   staging**. Extension không cần có trên app, thư viện không bị chạm.

Sửa file thì stage lại (revision là hash nội dung nên nó tự đổi) rồi chạy tiếp. Chỉ bấm
`Install Staged Draft` khi muốn bản đó vào thư viện thật.

Hai giới hạn của cách này: `Run Script…` (source `installed`) vẫn đòi extension đã cài, và vùng staging
**bị xoá sạch** khi tắt server hoặc mở lại app — mở app lại thì phải stage lại.

## Ranh giới cần biết

- **App là thẩm quyền cuối cùng** về manifest, entrypoint và contract. Client chỉ validate hình dạng để
  báo lỗi sớm; nó không bao giờ gửi filesystem path tuỳ ý hay source raw trong `run.start`.
- **`packageId` cũng do app quyết.** Client đối chiếu extension trong workspace với `extensions.list`
  trước khi gửi lệnh (id, slug tên, tên rút gọn), vì app sinh id theo ba luật khác nhau tuỳ đường cài.
  Không khớp thì đó là extension chưa có trên app: stage + run `draft` vẫn chạy, còn `Install Staged
  Draft` sẽ đi đường **cài mới**.
- **Cài mới ghi vào thư viện.** Lệnh đó tạo thư mục trong `extensions/` và thêm một bản ghi
  `Extension` — nhiều hơn hẳn so với đường ghi đè (chỉ đổi file). Vẫn phải bấm đồng ý trên thiết bị, và
  màn xác nhận nói rõ đây là "Cài MỚI" kèm tên đọc từ `plugin.json`.
- **Diagnostic chỉ gắn khi `sourceRevision` khớp** bản đã stage/cài. Event của bản cũ chỉ hiện trong
  trace kèm `(stale)`.
- **Trace đã redact ở phía app**: không có header, cookie, body, nội dung chương; giá trị query trong URL
  hiện dưới dạng `…`.
- Kết nối là `ws` **chưa có TLS** và không có xác thực nào ở tầng kết nối — chỉ dùng trên LAN tin cậy.
  Chuyển sang `wss` + kiểm fingerprint là việc phải làm trước khi mở cho môi trường rộng hơn.

## Contract

`src/protocol.ts` là mirror của Swift:
`Sources/Services/Extensions/Debug/Server/ExtensionDebugProtocol.swift` và
`Sources/Services/Extensions/Debug/ExtensionDebugEvent.swift`. Sửa một bên phải sửa bên kia cùng lượt.
`timestamp` là số giây theo reference date của Apple (2001-01-01), do `JSONEncoder` mặc định.
