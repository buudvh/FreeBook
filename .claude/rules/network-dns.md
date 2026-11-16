---
paths:
  - "Sources/Services/Network/**"
  - "Sources/Views/Settings/Network/**"
  - "Sources/Services/LegadoSource/Net/**"
  - "Sources/Services/Extensions/Engine/JSExecutor*.swift"
---

# DNS mã hoá (DoH) & proxy

> Tách từ `AGENTS.md` (1.3.959). Claude Code tự nạp file này khi đọc / sửa file khớp `paths`; agent khác phải tự đọc trước khi sửa phân hệ này.

- **DNS mã hoá (DoH)** (1.3.825; mặc định tắt 1.3.828; bật riêng từng nguồn 1.3.831 — Cài đặt › Chung › Mạng & DNS): hai cách bật, cùng **một** máy chủ chọn ở Mạng & DNS (anh chọn, không cho chọn riêng theo nguồn). (1) **"Bật cho cả app"** (`EncryptedDNSPolicy`, mặc định tắt): `EncryptedDNSRepository` đặt `NWParameters.PrivacyContext.default.requireEncryptedNameResolution` ⇒ mọi kết nối **trong tiến trình** (URLSession). (2) **Cờ riêng** `Extension.encryptedDNSEnabled` (công tắc ở mục Mạng của Cấu hình tiện ích + mục Hoạt động của Chi tiết nguồn Legado, `ExtensionEncryptedDNSToggle`; tắt ghi `nil`; có backup): Apple không có DoH theo từng URLSession ⇒ proxy HTTP CONNECT nội bộ **127.0.0.1** (`EncryptedDNSRelay` + `EncryptedDNSRelayTunnel`: CONNECT + `GET http://` tuyệt đối, ra ngoài bằng `NWConnection` với privacy context riêng bắt buộc DoH; hạn kết nối 10 s, đứng yên 60 s, một bên đóng ⇒ đóng cả hai; log `[DNS-Relay] → host:port`). `EncryptedDNSSessionRouter` chọn session: `fetch` của `JSExecutor` (`session(forExtensionPath:)`) và `LegadoHTTPClient` (`proxyConfigurations(forPackageId:)`, đọc cờ lúc mở phiên engine); ảnh bìa / ảnh tải thẳng không theo cờ. Bản chụp cho thread nền ở `EncryptedDNSRouting` (chỉ repository ghi). WebView (tiến trình WebKit) và AVPlayer **không** ăn cả hai ⇒ trang `SystemDNSGuideView` hướng dẫn đổi DNS cả máy (app 1.1.1.1 / profile AdGuard DNS) và đổi IP bằng WARP. Dò (`EncryptedDNSProbe`, context riêng) lỗi ⇒ lùi về DNS thường cho cả hai + log ❌, lần mở sau dò trước rồi mới bật. `EncryptedDNSRepository.start()` gọi ở `FreeBookApp.init` **sau** `ExtensionLibraryRepository.shared.load()`. Tên máy LAN có thể không tra được khi bật cho cả app. **Proxy ra ngoài chưa làm** — hướng đã chốt: HTTP CONNECT / SOCKS5 qua `proxyConfigurations` (iOS 17), áp theo tiện ích JS / nguồn Legado + theo tên miền ở trình duyệt, phủ fetch + ảnh, WebView, phim; **không** cho Google Drive / Telegram / Google TTS / kiểm bản mới / Gemini đi proxy; chừa 127.0.0.1; header `proxy` của Legado (`LegadoEngineSession+Fetch`) đang bị bỏ — có proxy thì cho chạy. VPN thật (Network Extension) không làm được trong LiveContainer.
