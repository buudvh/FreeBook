import Foundation

/// Quản lý lưu trữ và nạp cấu hình AI từ UserDefaults.
public final class AISettingsStore: Sendable {
    public static let shared = AISettingsStore()

    private let userDefaultsKey = "FreeBook_AI_Configuration_V1"

    private init() {}

    /// Tải cấu hình đã lưu, hoặc trả về cấu hình mặc định.
    public func loadConfiguration() -> AIConfiguration {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let config = try? JSONDecoder().decode(AIConfiguration.self, from: data) else {
            return AIConfiguration.default
        }
        return config
    }

    /// Lưu cấu hình mới.
    public func saveConfiguration(_ config: AIConfiguration) {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }

    /// Cập nhật hoặc lưu một Profile.
    public func saveProfile(_ profile: AIProviderProfile) {
        var config = loadConfiguration()
        config.updateActiveProfile(profile)
        saveConfiguration(config)
    }

    /// Xóa một profile theo ID.
    public func deleteProfile(id: String) {
        var config = loadConfiguration()
        config.deleteProfile(id: id)
        saveConfiguration(config)
    }

    /// Kích hoạt một profile theo ID.
    public func setActiveProfile(id: String) {
        var config = loadConfiguration()
        if config.profiles.contains(where: { $0.id == id }) {
            config.activeProfileId = id
            saveConfiguration(config)
        }
    }

    /// Cập nhật model đang chọn hiện tại của profile active.
    public func updateSelectedModel(_ model: String) {
        var config = loadConfiguration()
        var p = config.activeProfile
        p.selectedModel = model
        if !p.availableModels.contains(model) {
            p.availableModels.append(model)
        }
        config.updateActiveProfile(p)
        saveConfiguration(config)
    }

    /// Cập nhật danh sách model khả dụng của profile active.
    public func updateAvailableModels(_ models: [String]) {
        var config = loadConfiguration()
        var p = config.activeProfile
        p.availableModels = models
        if !models.contains(p.selectedModel), let first = models.first {
            p.selectedModel = first
        }
        config.updateActiveProfile(p)
        saveConfiguration(config)
    }
}
