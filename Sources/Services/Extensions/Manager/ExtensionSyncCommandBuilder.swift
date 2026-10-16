import Foundation

/// Danh tính `packageId` của tiện ích **cài từ kho**, suy từ tên trong registry.
///
/// Trước khi tiện ích chuyển sang `extension_store/` (JSON), type này còn dựng `UpsertExtensionCommand` cho mọi dòng registry, tải `plugin.json` trên
/// mạng cho từng tiện ích chưa cài (~1 request/tiện ích). Giờ làm mới kho chỉ lưu nguyên văn registry
/// (`ExtensionTransactionCoordinator.saveRegistry`) và danh mục chưa cài được dựng từ cache đó
/// (`ExtensionLibraryRepository.catalog`), nên chỉ còn lại luật đặt tên này.
///
/// Ba đường cài (kho, import zip, Debug server) phải cho **cùng** `packageId` với cùng một tiện ích
/// (`rules.md:439`) — các bản mirror: `ExtensionDraftMetadata`, `ExtensionDebugCommandRouter`.
public struct ExtensionSyncCommandBuilder: Sendable {
    public static func packageId(forName name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
