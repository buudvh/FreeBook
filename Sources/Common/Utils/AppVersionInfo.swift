import Foundation

/// Version của bản app đang chạy, đọc từ `Info.plist`.
///
/// CI (`build-ipa.yml`) chèn hai giá trị lúc build: `CFBundleShortVersionString` = số bản đầu
/// `Docs/CodeGraph/CHANGELOG.md` (vd `1.3.723`), `CFBundleVersion` = số lượt chạy workflow. Bản build tay mang giá trị
/// mặc định trong `project.yml` (`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`).
public enum AppVersionInfo {
    /// `CFBundleShortVersionString`, vd `1.3.723`.
    public static var shortVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    /// `CFBundleVersion`, vd `412`.
    public static var buildNumber: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }

    /// Dạng hiển thị `1.3.723 (412)`; thiếu một phần thì chỉ phần còn lại, thiếu cả hai ⇒ `unknown`.
    public static var display: String {
        switch (shortVersion, buildNumber) {
        case let (version?, build?): return "\(version) (\(build))"
        case let (version?, nil): return version
        case let (nil, build?): return build
        default: return "unknown"
        }
    }
}
