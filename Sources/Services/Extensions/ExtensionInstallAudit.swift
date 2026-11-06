import Foundation

/// Đối chiếu index tiện ích **đã cài** (`installed.json`) với **thực tế trên đĩa**, rồi nói cần dọn gì.
///
/// Từ khi index chỉ giữ tiện ích đã cài và lưu vị trí **tương đối** (`Extension.folder`), không còn nhánh
/// "tìm lại path hỏng" (relocation) hay "đưa về chưa cài": bản ghi đã cài mà gói không còn trên đĩa thì
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
        /// Bản ghi cần xoá: đã cài nhưng gói không còn trên đĩa.
        public let deletePackageIds: [String]
        /// Tên tiện ích bị xoá, dùng cho log.
        public let deletedNames: [String]

        public var isEmpty: Bool { deletePackageIds.isEmpty }

        public init(deletePackageIds: [String], deletedNames: [String]) {
            self.deletePackageIds = deletePackageIds
            self.deletedNames = deletedNames
        }
    }

    /// Gói còn sống theo `ExtensionPackageReader.isPresent`: file `js|legado/<id>.json` tồn tại, hoặc thư mục cũ có
    /// `plugin.json`.
    ///
    /// Thư mục cũ không chỉ kiểm tra tồn tại: sau một lượt giải nén dở dang, thư mục có thể còn mà manifest không có —
    /// lúc đó mọi lời gọi bóc tách đều lỗi, coi như chưa cài mới đúng. File gói hỏng vẫn tính là còn (không xoá bản
    /// ghi — phía an toàn).
    public static func isInstalled(localPath: String) -> Bool {
        ExtensionPackageReader.isPresent(localPath: localPath)
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
