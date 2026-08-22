import Foundation

/// Cấu hình OAuth cho Google Drive. Client id **không** nhúng trong repo: nó đi từ GitHub secret
/// `GOOGLE_DRIVE_CLIENT_ID` → build setting → `Info.plist`, đúng đường mà `GOOGLE_CLOUD_TTS_API_KEY`
/// đang đi. Build local không có secret thì chuỗi `$(GOOGLE_DRIVE_CLIENT_ID)` **nằm nguyên văn**
/// trong Info.plist, nên phải chặn bằng cả ba điều kiện dưới đây.
///
/// Client id của app iOS không phải secret (ai cũng moi được từ IPA). Rào bảo mật thật là PKCE,
/// scope `drive.file` và việc không có client_secret.
public enum GoogleDriveConfiguration {
    /// Ô dán tay trong màn Sao lưu — dành cho build không có secret.
    public static let clientIdOverrideKey = "googleDriveClientId"

    /// Chỉ file do app tạo. Scope này **không** sensitive nên Google không bắt qua vòng review.
    public static let scope = "https://www.googleapis.com/auth/drive.file"

    public static let folderName = "FreeBookBackups"
    public static let authorizationEndpoint = "https://accounts.google.com/o/oauth2/v2/auth"
    public static let tokenEndpoint = "https://oauth2.googleapis.com/token"
    public static let filesEndpoint = "https://www.googleapis.com/drive/v3/files"
    public static let uploadEndpoint = "https://www.googleapis.com/upload/drive/v3/files"

    public static var clientId: String {
        // 1. Client id người dùng tự dán trong Cài đặt.
        if let custom = UserDefaults.standard.string(forKey: clientIdOverrideKey),
           !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return custom.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // 2. Client id hệ thống nhúng trong Info.plist (từ GitHub Secret).
        if let bundleValue = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_DRIVE_CLIENT_ID") as? String,
           !bundleValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           bundleValue != "$(GOOGLE_DRIVE_CLIENT_ID)",
           !bundleValue.contains("$(") {
            return bundleValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    public static var isConfigured: Bool { !clientId.isEmpty }

    /// Client iOS dùng redirect dạng **reversed client id**, suy ra tại runtime nên không phải
    /// nhúng thêm chuỗi nào và không cần khai `CFBundleURLTypes`
    /// (`ASWebAuthenticationSession` tự bắt callback theo scheme).
    public static var redirectScheme: String {
        let id = clientId
        guard let range = id.range(of: ".apps.googleusercontent.com") else { return "" }
        return "com.googleusercontent.apps." + String(id[id.startIndex..<range.lowerBound])
    }

    public static var redirectURI: String {
        let scheme = redirectScheme
        return scheme.isEmpty ? "" : "\(scheme):/oauth2redirect"
    }

    public static func saveClientIdOverride(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: clientIdOverrideKey)
        } else {
            UserDefaults.standard.set(trimmed, forKey: clientIdOverrideKey)
        }
    }
}
