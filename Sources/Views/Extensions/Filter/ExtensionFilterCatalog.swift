import Foundation
import Observation

/// Tiện ích nào có bộ lọc (mục `select` / công tắc / `list` trong `config`) và bộ lọc có đang khác mặc định không — cho
/// nút lọc (`ExtensionFilterButton`). Đọc `plugin.json` ở luồng nền một lần cho mỗi bộ (tiện ích, phiên bản,
/// `configJson`); `body` chỉ tra bảng đã có, chưa có thì trả `nil` (nút ẩn) và vẽ lại khi đọc xong.
@MainActor
@Observable
final class ExtensionFilterCatalog {
    static let shared = ExtensionFilterCatalog()

    struct Info: Equatable {
        let hasFilters: Bool
        /// Ít nhất một mục lọc khác mặc định ⇒ chấm trắng trên nút.
        let isActive: Bool
    }

    private var infos: [String: Info] = [:]
    @ObservationIgnored private var pendingKeys = Set<String>()

    private init() {}

    func info(for ext: Extension) -> Info? {
        let key = "\(ext.packageId)|\(ext.version)|\(ext.configJson)"
        if let info = infos[key] { return info }
        // Config vừa đổi (áp dụng bộ lọc, màn Cấu hình tự lưu): trong lúc đọc bộ mới vẫn trả bộ cũ của tiện ích — nút
        // không biến mất một nhịp làm cụm nút header xô lệch.
        let previous = infos.first { $0.key.hasPrefix("\(ext.packageId)|") }?.value
        guard !ext.localPath.isEmpty, pendingKeys.insert(key).inserted else { return previous }
        let (localPath, configJson, packageId) = (ext.localPath, ext.configJson, ext.packageId)
        Task { @MainActor in
            let info = await Task.detached(priority: .utility) { () -> Info in
                guard let schema = try? ExtensionConfigSchema.load(localPath: localPath) else {
                    return Info(hasFilters: false, isActive: false)
                }
                let hasFilters = !schema.filterKeys.isEmpty
                let isActive = hasFilters && schema.hasActiveFilter(values: schema.initialValues(configJson: configJson))
                return Info(hasFilters: hasFilters, isActive: isActive)
            }.value
            // Bộ cũ của cùng tiện ích (config vừa đổi) không còn ai tra ⇒ bỏ, bảng không phình theo số lần lưu.
            infos = infos.filter { !$0.key.hasPrefix("\(packageId)|") }
            infos[key] = info
            pendingKeys.remove(key)
        }
        return previous
    }
}
