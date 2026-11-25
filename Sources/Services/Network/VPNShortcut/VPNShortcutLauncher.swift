import Foundation

/// Dựng link chạy **phím tắt bật / tắt VPN 1.1.1.1** (1.3.1059; hai phím tắt riêng từ 1.3.1061, anh Bửu duyệt mockup bản 3
/// https://claude.ai/artifact/NqVsj9fYBpdFUJJfzeZi1k). App chạy trong LiveContainer, không có Network Extension ⇒ không tự
/// bật VPN được; nút chỉ chạy phím tắt người dùng tạo sẵn trong app Phím tắt: phím tắt **bật** = "Đặt VPN" › Kết nối,
/// phím tắt **tắt** = "Đặt VPN" › Ngắt kết nối, cùng cấu hình 1.1.1.1 (anh không tạo được phím tắt "Bật/tắt" chung). App
/// Phím tắt luôn hiện lên giây lát — iOS không có đường chạy ngầm cho app khác.
///
/// Link: `shortcuts://x-callback-url/run-shortcut?name=…&x-success=…&x-cancel=…&x-error=…`. **Link quay về** chỉ gắn khi
/// đang chạy trong LiveContainer (có biến môi trường `LC_HOME_PATH`): `livecontainer://livecontainer-launch?bundle-name=…
/// &container-folder-name=…` với đúng hai giá trị LiveContainer so (`UIKit+GuestHooks.m`, `LCHandleControlAppURL`):
/// `NSBundle.mainBundle.bundlePath.lastPathComponent` và tên thư mục cuối của `HOME`. Trùng app đang chạy ⇒ LiveContainer
/// không làm gì, app chỉ lên trước — **không** mở lại app. Lệch ⇒ LiveContainer đi đường chuyển app (hỏi xác nhận) ⇒ log
/// hai giá trị để tra trên máy. Ngoài LiveContainer không gắn link quay về: người dùng bấm "◀" góc trên trái.
///
/// **Lần chạy cuối** (1.3.1061, anh Bửu báo VPN tự bật lại khi vào app, lúc bị lúc không): mỗi lần iOS nhận mở app Phím
/// tắt, `recordRun` ghi giờ + Bật / Tắt + chỗ bấm vào `UserDefaults` — không phụ thuộc công tắc Ghi log (tắt lại mỗi lần
/// mở app) — để Mạng & DNS hiện "App chạy phím tắt lần cuối". VPN tự bật mà giờ đó cũ hơn ⇒ không phải app bật.
///
/// Chỉ Foundation (luật `SERVICE_SWIFTUI_IMPORT`); mở link + toast lỗi ở `VPNShortcutRunner` (tầng View).
enum VPNShortcutLauncher {
    enum Action {
        case on
        case off

        var title: String {
            switch self {
            case .on: return "Bật"
            case .off: return "Tắt"
            }
        }

        /// Khoá `@AppStorage` của ô tên phím tắt. Bật giữ khoá của 1.3.1059 ⇒ phím tắt đã tạo theo bản đó vẫn chạy.
        var nameKey: String {
            switch self {
            case .on: return "vpnShortcutName"
            case .off: return "vpnShortcutOffName"
            }
        }

        /// Tên mặc định **không dấu**: app Phím tắt tra phím tắt theo chuỗi, tên có dấu dễ lệch dạng Unicode (NFC / NFD)
        /// với tên người dùng gõ.
        var defaultName: String {
            switch self {
            case .on: return "VPN 1.1.1.1"
            case .off: return "Tat VPN 1.1.1.1"
            }
        }
    }

    /// Chỗ bấm, ghi vào "lần chạy cuối".
    enum Source {
        case settings
        case hub

        var title: String {
            switch self {
            case .settings: return "Mạng & DNS"
            case .hub: return "hub"
            }
        }
    }

    /// Khoá "lần chạy cuối": giây Unix (0 = chưa chạy) và chữ "Bật · hub". Không dấu chấm.
    static let lastRunAtKey = "vpnShortcutLastRunAt"
    static let lastRunInfoKey = "vpnShortcutLastRunInfo"
    /// Mở app Phím tắt (nút ở trang hướng dẫn).
    static let shortcutsAppURL = URL(string: "shortcuts://")!

    /// Tên đang cài của phím tắt; ô để trống ⇒ tên mặc định.
    static func shortcutName(for action: Action) -> String {
        let saved = UserDefaults.standard.string(forKey: action.nameKey) ?? ""
        let trimmed = saved.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? action.defaultName : trimmed
    }

    /// Link chạy phím tắt của `action`, kèm link quay về khi đang trong LiveContainer.
    static func runURL(for action: Action) -> URL? {
        let name = shortcutName(for: action)
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
        AppLogger.shared.log("🛡️ [VPNShortcut] \(action.title): chạy phím tắt \"\(name)\" — quay về: \(back?.absoluteString ?? "không (ngoài LiveContainer)") — link: \(url?.absoluteString ?? "nil")")
        return url
    }

    /// Ghi lần chạy cuối — gọi khi iOS đã nhận mở app Phím tắt.
    static func recordRun(_ action: Action, from source: Source) {
        let defaults = UserDefaults.standard
        defaults.set(Date().timeIntervalSince1970, forKey: lastRunAtKey)
        defaults.set("\(action.title) · \(source.title)", forKey: lastRunInfoKey)
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
