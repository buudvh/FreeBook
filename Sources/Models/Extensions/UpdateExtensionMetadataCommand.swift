import Foundation

/// Command cập nhật **metadata** của một tiện ích đã cài, phát từ màn Cấu hình tiện ích.
///
/// Chỉ mang các trường **có cột** trong `@Model Extension` (`Extension.swift:6-18`). `regexp` và `language`
/// không có cột nên chỉ ghi xuống `plugin.json` — xem `ExtensionMetadataEditor`.
///
/// ## Vì sao không dùng lại `UpsertExtensionCommand`
/// Nhánh cập nhật của nó (`ExtensionTransactionCoordinator.apply`) gán `existing.version = command.version`
/// **vô điều kiện** và bỏ qua **mọi** giá trị rỗng (`if !command.name.isEmpty`, `if !command.sourceUrl.isEmpty`,
/// …) ⇒ dùng lại là phải truyền kèm `version`/`downloadUrl` hiện tại để khỏi ghi đè, và **không xoá được**
/// `source`/`desc`. Command này chỉ gán đúng 7 trường của nó và cho phép giá trị rỗng.
public struct UpdateExtensionMetadataCommand: Sendable {
    public let packageId: String
    public let name: String
    public let sourceUrl: String
    /// Truyền **giá trị hiện có** nếu màn cấu hình không cho sửa `icon` — command gán thẳng, không guard.
    public let iconUrl: String?
    public let desc: String?
    public let type: String
    public let locale: String

    public init(
        packageId: String,
        name: String,
        sourceUrl: String,
        iconUrl: String?,
        desc: String?,
        type: String,
        locale: String
    ) {
        self.packageId = packageId
        self.name = name
        self.sourceUrl = sourceUrl
        self.iconUrl = iconUrl
        self.desc = desc
        self.type = type
        self.locale = locale
    }
}
