import Foundation

/// Dựng link chạy **phím tắt bật / tắt VPN 1.1.1.1** (1.3.1059, anh Bửu duyệt mockup
/// https://claude.ai/artifact/NqVsj9fYBpdFUJJfzeZi1k, chỗ đặt A). App chạy trong LiveContainer, không có Network Extension
/// ⇒ không tự bật VPN được; nút chỉ chạy một phím tắt người dùng tạo sẵn trong app Phím tắt (tác vụ "Đặt VPN" › Bật/tắt ›
/// cấu hình 1.1.1.1). App Phím tắt luôn hiện lên giây lát — iOS không có đường chạy ngầm cho app khác.
///
/// Link: `shortcuts://x-callback-url/run-shortcut?name=…&x-success=…&x-cancel=…&x-error=…`. **Link quay về** chỉ gắn khi
/// đang chạy trong LiveContainer (có biến môi trường `LC_HOME_PATH`): `livecontainer://livecontainer-launch?bundle-name=…
/// &container-folder-name=…` với đúng hai giá trị LiveContainer so (`UIKit+GuestHooks.m`, `LCHandleControlAppURL`):
/// `NSBundle.mainBundle.bundlePath.lastPathComponent` và tên thư mục cuối của `HOME`. Trùng app đang chạy ⇒ LiveContainer
/// không làm gì, app chỉ lên trước — **không** mở lại app (TTS / phim đang phát không bị ngắt). Lệch ⇒ LiveContainer đi
/// đường chuyển app (hỏi xác nhận) ⇒ log hai giá trị để tra trên máy. Ngoài LiveContainer không gắn link quay về: người
/// dùng bấm "◀" góc trên trái.
///
/// Chỉ Foundation (luật `SERVICE_SWIFTUI_IMPORT`); mở link + toast lỗi ở `VPNShortcutRunner` (tầng View).
enum VPNShortcutLauncher {
    /// Khoá `@AppStorage` của ô "Tên phím tắt" (Mạng & DNS). Không dấu chấm.
    static let shortcutNameKey = "vpnShortcutName"
    /// Tên mặc định **không dấu**: app Phím tắt tra phím tắt theo chuỗi, tên có dấu dễ lệch dạng Unicode (NFC / NFD) với
    /// tên người dùng gõ.
    static let defaultShortcutName = "VPN 1.1.1.1"
    /// Mở app Phím tắt (nút ở trang hướng dẫn).
    static let shortcutsAppURL = URL(string: "shortcuts://")!

    /// Tên đang cài; ô để trống ⇒ tên mặc định.
    static var currentShortcutName: String {
        let saved = UserDefaults.standard.string(forKey: shortcutNameKey) ?? ""
        let trimmed = saved.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultShortcutName : trimmed
    }

    /// Link chạy phím tắt `currentShortcutName`, kèm link quay về khi đang trong LiveContainer.
    static func runURL() -> URL? {
        let name = currentShortcutName
        var query = "name=\(encode(name))"
        let back = returnURL()
        if let back {
            let encodedBack = encode(back.absoluteString)
            query += "&x-success=\(encodedBack)&x-cancel=\(encodedBack)&x-error=\(encodedBack)"
        }
        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = "x-callback-url"
        components.path = "/run-shortcut"
        components.percentEncodedQuery = query
        let url = components.url
        AppLogger.shared.log("🛡️ [VPNShortcut] Chạy phím tắt \"\(name)\" — quay về: \(back?.absoluteString ?? "không (ngoài LiveContainer)") — link: \(url?.absoluteString ?? "nil")")
        return url
    }

    /// Link LiveContainer trỏ đúng app đang chạy; `nil` khi không ở trong LiveContainer hoặc thiếu giá trị.
    private static func returnURL() -> URL? {
        guard getenv("LC_HOME_PATH") != nil else { return nil }
        let bundleName = (Bundle.main.bundlePath as NSString).lastPathComponent
        guard let homeRaw = getenv("HOME") else {
            AppLogger.shared.log("❌ [VPNShortcut] Trong LiveContainer mà không đọc được HOME ⇒ bỏ link quay về")
            return nil
        }
        let containerFolder = (String(cString: homeRaw) as NSString).lastPathComponent
        guard !bundleName.isEmpty, !containerFolder.isEmpty else {
            AppLogger.shared.log("❌ [VPNShortcut] Thiếu bundle-name (\(bundleName)) hoặc container-folder-name (\(containerFolder)) ⇒ bỏ link quay về")
            return nil
        }
        var components = URLComponents()
        components.scheme = "livecontainer"
        components.host = "livecontainer-launch"
        components.percentEncodedQuery = "bundle-name=\(encode(bundleName))&container-folder-name=\(encode(containerFolder))"
        return components.url
    }

    /// Mã hoá chặt (chỉ chữ số Latin + `-._~`): giá trị lồng một link khác có `?`, `&`, `=` phải thành `%XX`.
    private static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }

    private static let unreserved: CharacterSet = {
        var set = CharacterSet()
        set.insert(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return set
    }()
}
