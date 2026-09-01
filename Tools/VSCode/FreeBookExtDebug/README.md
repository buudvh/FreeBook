# FreeBook Extension Debug — VS Code client

Client của debug server trong app FreeBook (iOS). Cho phép chạy `execute(...)` của VBook extension **trên
thiết bị thật** rồi xem trace console/fetch/exception ngay trong VS Code.

> Chưa publish lên Marketplace và chưa có bước build trong CI của repo. Đây là package nguồn, chạy bằng
> `npm install && npm run compile` rồi F5 trong VS Code.

## Yêu cầu

- VS Code desktop 1.85+, workspace **tin cậy** (`workspace.isTrusted`).
- App FreeBook bản Dev/Ad Hoc, đang **foreground**, cùng mạng LAN.
- Trong app: **Cài Đặt → Nhà Phát Triển → Debug Server (LAN) → Bật server**.

## Ghép nối

1. App hiện QR và một chuỗi `freebook-extdebug://pair?host=…&port=…&service=…&token=…`.
2. VS Code: `FreeBook: Pair with App`, dán chuỗi đó.
3. App hiện tên client và chờ bạn bấm **Cho phép kết nối**. Token đúng chỉ mở cửa xin phép — không tự
   cấp session.

Token được lưu bằng `SecretStorage`, dùng một lần và hết hạn sau 3 phút. Nó không vào settings,
workspace state hay Output Channel.

## Lệnh

| Lệnh | Việc |
| --- | --- |
| `FreeBook: Pair with App` | Ghép nối |
| `FreeBook: Select Extension` | Chọn extension đã cài trên app |
| `FreeBook: Run Current execute` | Chạy entrypoint suy ra từ tên file đang mở (phải nằm trong manifest) |
| `FreeBook: Run Script…` | Chọn entrypoint và nhập input, source `installed` |
| `FreeBook: Run Saved Profile` | Như trên nhưng source `draft` |
| `FreeBook: Stage Workspace Draft` | Gửi snapshot `plugin.json` + `*.js` (gốc và `src/`) lên staging của app |
| `FreeBook: Install Staged Draft` | Ghi đè extension đang cài — **cần bấm đồng ý trên thiết bị** |
| `FreeBook: Rollback Installed Extension` | Trả lại bản trước lần cài gần nhất |
| `FreeBook: Cancel Current Run` | Huỷ run đang chạy |
| `FreeBook: Open Trace` | Mở Output Channel |

## Ranh giới cần biết

- **App là thẩm quyền cuối cùng** về manifest, entrypoint và contract. Client chỉ validate hình dạng để
  báo lỗi sớm; nó không bao giờ gửi filesystem path tuỳ ý hay source raw trong `run.start`.
- **Diagnostic chỉ gắn khi `sourceRevision` khớp** bản đã stage/cài. Event của bản cũ chỉ hiện trong
  trace kèm `(stale)`.
- **Trace đã redact ở phía app**: không có header, cookie, body, nội dung chương; giá trị query trong URL
  hiện dưới dạng `…`.
- Kết nối là `ws` **chưa có TLS** — chỉ dùng trên LAN tin cậy. Chuyển `wss` + fingerprint qua QR là việc
  phải làm trước khi mở cho môi trường rộng hơn.

## Contract

`src/protocol.ts` là mirror của Swift:
`Sources/Services/Extensions/Debug/Server/ExtensionDebugProtocol.swift` và
`Sources/Services/Extensions/Debug/ExtensionDebugEvent.swift`. Sửa một bên phải sửa bên kia cùng lượt.
`timestamp` là số giây theo reference date của Apple (2001-01-01), do `JSONEncoder` mặc định.
