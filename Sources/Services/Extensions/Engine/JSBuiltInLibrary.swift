import Foundation

/// Thư viện JS đóng gói kèm app cho `load('<tên>')` khi tiện ích **không** mang file cùng tên (file của tiện ích ở gốc
/// hay `src/` luôn thắng — chủ ý khác hợp đồng chuẩn, nơi bản dựng sẵn thắng, để tiện ích đang tự mang thư viện chạy y
/// như cũ). Dùng chung cho `JSExecutor+Load` và hai bộ kiểm tra tĩnh (`ExtensionScriptStaticCheck`,
/// `ExtensionDraftValidator`) để `load('crypto.js')` không bị báo "file không có".
enum JSBuiltInLibrary: String, CaseIterable {
    /// CryptoJS 4.2.0 (MIT, `Docs/ThirdParty/CryptoJS-LICENSE.txt`): `crypto-js.min.js` của cdnjs, giữ nguyên byte.
    case cryptoJS = "crypto.js"

    static func isBuiltIn(_ fileName: String) -> Bool {
        JSBuiltInLibrary(rawValue: fileName) != nil
    }

    /// Nguồn JS, đọc từ bundle một lần mỗi phiên app; `nil` khi resource thiếu (đã log ❌ một lần).
    var source: String? {
        switch self {
        case .cryptoJS: return Self.cryptoJSSource
        }
    }

    private static let cryptoJSSource = bundledScript(named: "crypto-js-4.2.0.min")

    private static func bundledScript(named name: String) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "js"),
              let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty else {
            AppLogger.shared.log("❌ [JSBuiltInLibrary] Thiếu \(name).js trong bundle — tiện ích không mang file sẽ không có bản dựng sẵn")
            return nil
        }
        return text
    }
}
