import Foundation

/// Đường dẫn & cấu hình của **TTS tiện ích** suy từ `packageId` (`tool`) qua `ExtensionLibraryRepository`.
///
/// Trước 1.3.530, `extensionLocalPath` được lưu nguyên đường dẫn **tuyệt đối** vào `UserDefaults`
/// (`ttsExtensionLocalPath`): gốc thư mục dữ liệu đổi (LiveContainer, lỗi 1.3.523) là TTS tiện ích trỏ vào
/// thư mục chết cho tới khi người dùng mở màn Cài đặt TTS, và `localStorage` của nó rơi vào namespace
/// `"path:" + md5` thay vì `packageId` (`JSExecutor`). Restore cài đặt cũng vậy: `ttsTool` về nhưng khoá
/// đường dẫn bị `BackupSettingsArchiver` chặn ⇒ đường dẫn rỗng. Giờ đường dẫn luôn tính lại từ index tiện
/// ích (lưu `folder` tương đối); khoá cũ chỉ còn được đọc một lần để dọn.
///
/// Tách file vì `TTSManager.swift` vượt baseline dòng. Hai hàm đọc là `nonisolated static` để `init` (chạy
/// trước `super.init()`, chưa gọi được instance method) dùng được.
extension TTSManager {
    private nonisolated static let legacyExtensionLocalPathKey = "ttsExtensionLocalPath"

    /// `localPath` của tiện ích đang chọn làm TTS, hoặc `""` khi `tool` không phải tiện ích / chưa cài.
    nonisolated static func libraryExtensionLocalPath(tool: String) -> String {
        guard isExtensionTool(tool) else { return "" }
        return ExtensionLibraryRepository.snapshot(packageId: tool)?.localPath ?? ""
    }

    /// `configJson` thật của tiện ích — index là nguồn sự thật. `nil` ⇒ caller dùng bản sao `ttsExtensionConfigJson`.
    nonisolated static func libraryExtensionConfigJson(tool: String) -> String? {
        guard isExtensionTool(tool) else { return nil }
        return ExtensionLibraryRepository.snapshot(packageId: tool)?.configJson
    }

    /// Tính lại từ index sau khi library đã nạp (gọi ở `initialize(container:)`). Chỉ gán khi khác: `didSet` của
    /// hai thuộc tính xoá cache prefetch, còn `extensionConfigJson` nạp lại tham số tool.
    func refreshExtensionPathFromLibrary() {
        Self.migrateLegacyExtensionLocalPath(tool: tool)
        let path = Self.libraryExtensionLocalPath(tool: tool)
        if extensionLocalPath != path {
            extensionLocalPath = path
        }
        if let config = Self.libraryExtensionConfigJson(tool: tool), extensionConfigJson != config {
            extensionConfigJson = config
        }
    }

    /// Dọn khoá `ttsExtensionLocalPath` cũ đúng một lần. Với đường dẫn cũ đã hỏng, 1.3.529 ghi `localStorage`
    /// của TTS tiện ích vào namespace `"path:" + md5(đường dẫn cũ)` (không khớp tiện ích nào) ⇒ chuyển sang
    /// namespace `packageId` nếu namespace đó còn trống, rồi xoá namespace cũ và khoá.
    private nonisolated static func migrateLegacyExtensionLocalPath(tool: String) {
        let defaults = UserDefaults.standard
        guard let stalePath = defaults.string(forKey: legacyExtensionLocalPathKey) else { return }
        defaults.removeObject(forKey: legacyExtensionLocalPathKey)
        guard !stalePath.isEmpty, isExtensionTool(tool),
              ExtensionLibraryRepository.snapshot(packageId: tool) != nil else { return }

        let legacyNamespace = "path:" + stalePath.md5()
        let store = ExtensionLocalStorageStore.shared
        let snapshot = store.snapshot()
        guard let rescued = snapshot[legacyNamespace], !rescued.isEmpty else { return }
        if snapshot[tool]?.isEmpty ?? true {
            store.merge([tool: rescued])
            AppLogger.shared.log("ℹ️ [TTSExt] Chuyển \(rescued.count) khoá localStorage của \(tool) từ namespace đường dẫn cũ sang packageId")
        }
        store.removeAll(namespace: legacyNamespace)
    }
}
