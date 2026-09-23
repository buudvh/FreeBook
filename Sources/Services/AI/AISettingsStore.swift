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

    /// Cập nhật model đang chọn hiện tại.
    public func updateSelectedModel(_ model: String) {
        var config = loadConfiguration()
        config.selectedModel = model
        if !config.availableModels.contains(model) {
            config.availableModels.append(model)
        }
        saveConfiguration(config)
    }

    /// Cập nhật danh sách model khả dụng.
    public func updateAvailableModels(_ models: [String]) {
        var config = loadConfiguration()
        config.availableModels = models
        if !models.contains(config.selectedModel), let first = models.first {
            config.selectedModel = first
        }
        saveConfiguration(config)
    }
}
