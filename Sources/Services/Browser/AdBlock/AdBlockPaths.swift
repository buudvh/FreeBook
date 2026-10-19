import Foundation

/// Đường dẫn của phân hệ chặn quảng cáo — mọi thứ nằm dưới `applicationSupportDirectory/adblock/`:
///
/// - `filters/<id>.txt` — bộ lọc đã tải (raw AdGuard).
/// - `filters_meta.json` — meta từng bộ (chủ duy nhất: `AdBlockUpdateWorker`).
/// - `compiled/` — thư mục của `WKContentRuleListStore(url:)` (WebKit tự quản file bên trong).
/// - `site_preferences.json` — chỉnh riêng theo tên miền (chủ duy nhất: `BrowserSitePreferenceStore`).
///
/// Tên file chỉ dựng từ `AdBlockFilter.id: Int` — không nhận input người dùng nên không cần kiểm path traversal.
/// Backup **không** gói thư mục này (tải lại được).
enum AdBlockPaths {
    static var rootDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("adblock", isDirectory: true)
    }

    static var filtersDirectory: URL {
        rootDirectory.appendingPathComponent("filters", isDirectory: true)
    }

    static func filterFile(id: Int) -> URL {
        filtersDirectory.appendingPathComponent("\(id).txt", isDirectory: false)
    }

    static var metaFile: URL {
        rootDirectory.appendingPathComponent("filters_meta.json", isDirectory: false)
    }

    static var compiledDirectory: URL {
        rootDirectory.appendingPathComponent("compiled", isDirectory: true)
    }

    static var sitePreferencesFile: URL {
        rootDirectory.appendingPathComponent("site_preferences.json", isDirectory: false)
    }

    /// Tạo thư mục (kể cả cha) nếu chưa có. Lỗi ⇒ `false` + log `❌`; caller tự quyết bỏ qua thao tác ghi.
    @discardableResult
    static func ensureDirectory(_ url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return true
        } catch {
            AppLogger.shared.log("❌ 🛡️ [AdBlock] Không tạo được thư mục \(url.lastPathComponent): \(error.localizedDescription)")
            return false
        }
    }
}
