import Foundation

/// Đối chiếu danh sách tiện ích trong DB với **thực tế trên đĩa**, rồi nói cần dọn gì.
///
/// Lý do cần bước này: `uninstallExtension` chỉ xoá thư mục và **để lại** hàng trong DB với
/// `localPath` rỗng, để tiện ích của kho có thể tải lại. Nhưng tiện ích **import từ zip** không thuộc
/// kho nào và không có `downloadUrl`, nên hàng còn lại chỉ hiện một nút Tải về không bao giờ chạy được.
/// Với chúng, mất file nghĩa là mất hẳn — phải xoá luôn hàng.
///
/// Bước kiểm tra file nằm ở đây (Services) chứ không ở View, và việc ghi DB do
/// `ExtensionTransactionCoordinator` làm — View chỉ chuyển kế hoạch giữa hai bên.
public enum ExtensionInstallAudit {

    /// Ảnh chụp một tiện ích, đủ để quyết định mà không cần chạm `@Model` ngoài MainActor.
    public struct Entry: Sendable {
        public let packageId: String
        public let name: String
        public let localPath: String
        /// Có nguồn để tải lại hay không: thuộc một kho, hoặc có `downloadUrl` riêng.
        public let isRegistered: Bool

        public init(packageId: String, name: String, localPath: String, isRegistered: Bool) {
            self.packageId = packageId
            self.name = name
            self.localPath = localPath
            self.isRegistered = isRegistered
        }
    }

    public struct Plan: Sendable {
        /// Xoá hẳn hàng: tiện ích không có nguồn tải lại mà file đã mất.
        public let deletePackageIds: [String]
        /// Chỉ xoá `localPath`: tiện ích của kho, file mất nhưng vẫn tải lại được.
        public let clearFolderPackageIds: [String]
        /// Tên tiện ích bị xoá, dùng cho log.
        public let deletedNames: [String]

        public var isEmpty: Bool {
            deletePackageIds.isEmpty && clearFolderPackageIds.isEmpty
        }
    }

    /// Một thư mục extension được coi là còn sống khi có `plugin.json` đọc được.
    ///
    /// Không chỉ kiểm tra thư mục tồn tại: sau một lượt giải nén dở dang, thư mục có thể còn mà manifest
    /// không có — lúc đó mọi lời gọi bóc tách đều lỗi, coi như chưa cài mới đúng.
    public static func isInstalled(localPath: String) -> Bool {
        let trimmed = localPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let manifest = URL(fileURLWithPath: trimmed).appendingPathComponent("plugin.json")
        return FileManager.default.fileExists(atPath: manifest.path)
    }

    public static func plan(for entries: [Entry]) -> Plan {
        var deleteIds: [String] = []
        var deletedNames: [String] = []
        var clearIds: [String] = []

        for entry in entries {
            let hasFolderRecorded = !entry.localPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let alive = isInstalled(localPath: entry.localPath)

            if entry.isRegistered {
                // Tiện ích của kho: chỉ cần đưa `localPath` về rỗng để UI hiện đúng nút Tải về.
                if hasFolderRecorded && !alive {
                    clearIds.append(entry.packageId)
                }
                continue
            }

            // Không có nguồn tải lại: chỉ giữ hàng khi file thật sự còn.
            if !alive {
                deleteIds.append(entry.packageId)
                deletedNames.append(entry.name)
            }
        }

        return Plan(
            deletePackageIds: deleteIds,
            clearFolderPackageIds: clearIds,
            deletedNames: deletedNames
        )
    }
}
