import Foundation
import Observation

/// Tab nào của tiện ích có bộ lọc (mục `select` / công tắc / `list` trong `config` mà script của tab dùng tới —
/// `ExtensionFilterScope`) và bộ lọc của tab có đang khác mặc định không — cho nút lọc (`ExtensionFilterButton`).
/// Đọc `plugin.json` + quét script ở luồng nền một lần cho mỗi bộ (tiện ích, phiên bản, `configJson`, tab); `body` chỉ
/// tra bảng đã có, chưa có thì trả `nil` (nút ẩn) và vẽ lại khi đọc xong.
@MainActor
@Observable
final class ExtensionFilterCatalog {
    static let shared = ExtensionFilterCatalog()

    struct Info: Equatable {
        let hasFilters: Bool
        /// Ít nhất một mục lọc của tab khác mặc định ⇒ chấm trên nút.
        let isActive: Bool
    }

    private struct Key: Hashable {
        let packageId: String
        let version: Int
        let configJson: String
        let scope: ExtensionFilterScope
    }

    private var infos: [Key: Info] = [:]
    @ObservationIgnored private var pendingKeys = Set<Key>()

    private init() {}

    func info(for ext: Extension, scope: ExtensionFilterScope) -> Info? {
        let key = Key(packageId: ext.packageId, version: ext.version, configJson: ext.configJson, scope: scope)
        if let info = infos[key] { return info }
        // Config vừa đổi (áp dụng bộ lọc, màn Cấu hình tự lưu): trong lúc đọc bộ mới vẫn trả bộ cũ của cùng tab — nút
        // không biến mất một nhịp làm cụm nút header xô lệch.
        let previous = infos.first { $0.key.packageId == ext.packageId && $0.key.scope == scope }?.value
        guard !ext.localPath.isEmpty, pendingKeys.insert(key).inserted else { return previous }
        let (localPath, configJson) = (ext.localPath, ext.configJson)
        Task { @MainActor in
            let info = await Task.detached(priority: .utility) { () -> Info in
                guard let schema = try? ExtensionConfigSchema.load(localPath: localPath) else {
                    return Info(hasFilters: false, isActive: false)
                }
                let keys = schema.tabFilterKeys(for: scope, localPath: localPath)
                let isActive = !keys.isEmpty
                    && schema.hasActiveFilter(values: schema.initialValues(configJson: configJson), keys: keys)
                return Info(hasFilters: !keys.isEmpty, isActive: isActive)
            }.value
            // Bộ của bản / config cũ của cùng tiện ích không còn ai tra ⇒ bỏ (giữ các tab khác của bộ hiện tại), bảng
            // không phình theo số lần lưu.
            infos = infos.filter {
                $0.key.packageId != key.packageId
                    || ($0.key.version == key.version && $0.key.configJson == key.configJson)
            }
            infos[key] = info
            pendingKeys.remove(key)
        }
        return previous
    }
}
