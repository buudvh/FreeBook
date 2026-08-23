import Foundation

/// Chủ sở hữu **duy nhất** đường dẫn và quyền bảo vệ file của chỉ mục tìm toàn văn.
///
/// Đi theo đúng tiền lệ của `ChapterStorePath`: tạo thư mục với
/// `FileProtectionType.completeUntilFirstUserAuthentication`, áp cùng thuộc tính đó cho file DB
/// lẫn hai sidecar `-wal` / `-shm`, và tự kiểm tra đường dẫn canonical vẫn nằm trong
/// Application Support trước khi trả về. Chỉ mục là dữ liệu **dựng lại được**, nên nằm ở
/// `search/chapter_search.sqlite` tách hẳn khỏi `chapters/chapter_store.sqlite` — xoá nó không
/// bao giờ làm mất mục lục hay nội dung chương.
internal enum ChapterSearchIndexPath {
    internal enum IndexError: LocalizedError {
        case unavailable
        case databaseError(code: Int32)
        case canonicalPathViolation

        internal var errorDescription: String? {
            switch self {
            case .unavailable:
                return "Chỉ mục tìm toàn văn không khả dụng"
            case .databaseError(let code):
                return "Lỗi CSDL chỉ mục tìm kiếm (mã: \(code))"
            case .canonicalPathViolation:
                return "Vi phạm đường dẫn Sandbox"
            }
        }
    }

    internal static let directoryName = "search"
    internal static let fileName = "chapter_search.sqlite"

    internal static func makeDatabaseURL(fileManager: FileManager = .default) throws -> URL {
        let appSupport = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let searchDir = appSupport.appendingPathComponent(directoryName, isDirectory: true)
        if !fileManager.fileExists(atPath: searchDir.path) {
            try fileManager.createDirectory(
                at: searchDir,
                withIntermediateDirectories: true,
                attributes: [FileAttributeKey.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )
        }
        let dbURL = searchDir.appendingPathComponent(fileName)
        let canonicalRoot = appSupport.standardized.resolvingSymlinksInPath()
        let canonicalDir = searchDir.standardized.resolvingSymlinksInPath()
        let canonicalDB = dbURL.standardized.resolvingSymlinksInPath()

        guard canonicalDir.pathComponents.starts(with: canonicalRoot.pathComponents),
              canonicalDB.pathComponents.starts(with: canonicalRoot.pathComponents) else {
            throw IndexError.canonicalPathViolation
        }

        applyProtection(to: dbURL, fileManager: fileManager)
        return dbURL
    }

    /// Áp `completeUntilFirstUserAuthentication` cho DB và sidecar nếu đã tồn tại.
    internal static func applyProtection(to dbURL: URL, fileManager: FileManager = .default) {
        let attr = [FileAttributeKey.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        let dbPath = dbURL.path
        try? fileManager.setAttributes(attr, ofItemAtPath: dbPath)
        for suffix in ["-wal", "-shm"] {
            let sidecar = "\(dbPath)\(suffix)"
            if fileManager.fileExists(atPath: sidecar) {
                try? fileManager.setAttributes(attr, ofItemAtPath: sidecar)
            }
        }
    }

    /// Tổng dung lượng chỉ mục (DB + sidecar) tính theo byte, dùng để hiện cho người dùng biết
    /// giá phải trả của tokenizer `trigram`.
    internal static func totalByteSize(fileManager: FileManager = .default) -> Int64 {
        guard let dbURL = try? makeDatabaseURL(fileManager: fileManager) else { return 0 }
        var total: Int64 = 0
        for suffix in ["", "-wal", "-shm"] {
            let path = "\(dbURL.path)\(suffix)"
            if let attrs = try? fileManager.attributesOfItem(atPath: path),
               let size = attrs[.size] as? NSNumber {
                total += size.int64Value
            }
        }
        return total
    }
}
