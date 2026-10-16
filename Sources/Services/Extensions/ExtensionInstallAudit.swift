import Foundation

/// Đối chiếu index tiện ích **đã cài** (`installed.json`) với **thực tế trên đĩa**, rồi nói cần dọn gì.
///
/// Từ khi index chỉ giữ tiện ích đã cài và lưu thư mục **tương đối** (`Extension.folder`), không còn nhánh
/// "tìm lại path hỏng" (relocation) hay "đưa về chưa cài": bản ghi đã cài mà thư mục mất `plugin.json` thì
/// xoá bản ghi — mục đó (nếu thuộc kho) tự hiện lại ở catalog như chưa cài, nhờ cache registry.
///
/// Bước kiểm tra file nằm ở đây (Services); việc xoá bản ghi do `ExtensionTransactionCoordinator` làm.
public enum ExtensionInstallAudit {

    /// Ảnh chụp một tiện ích, đủ để quyết định mà không cần chạm repository.
    public struct Entry: Sendable {
        public let packageId: String
        public let name: String
        public let localPath: String

        public init(packageId: String, name: String, localPath: String) {
            self.packageId = packageId
            self.name = name
            self.localPath = localPath
        }
    }

    public struct Plan: Sendable {
        /// Bản ghi cần xoá: đã cài nhưng thư mục không còn `plugin.json`.
        public let deletePackageIds: [String]
        /// Tên tiện ích bị xoá, dùng cho log.
        public let deletedNames: [String]

        public var isEmpty: Bool { deletePackageIds.isEmpty }

        public init(deletePackageIds: [String], deletedNames: [String]) {
            self.deletePackageIds = deletePackageIds
            self.deletedNames = deletedNames
        }
    }

    /// Một thư mục extension được coi là còn sống khi có `plugin.json`.
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
        for entry in entries where !isInstalled(localPath: entry.localPath) {
            deleteIds.append(entry.packageId)
            deletedNames.append(entry.name)
        }
        return Plan(deletePackageIds: deleteIds, deletedNames: deletedNames)
    }
}
