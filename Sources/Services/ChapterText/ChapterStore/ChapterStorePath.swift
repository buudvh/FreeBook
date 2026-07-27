import Foundation

internal enum ChapterStoreError: LocalizedError {
    case unavailable
    case databaseError(code: Int32)
    case invalidContent
    case canonicalPathViolation

    internal var errorDescription: String? {
        switch self {
        case .unavailable:
            return "CSDL ChapterStore không khả dụng"
        case .databaseError(let code):
            return "Lỗi CSDL SQLite (mã: \(code))"
        case .invalidContent:
            return "Nội dung chương không hợp lệ"
        case .canonicalPathViolation:
            return "Vi phạm đường dẫn Sandbox"
        }
    }
}

internal enum ChapterStorePath {
    internal static func makeDatabaseURL(fileManager: FileManager = .default) throws -> URL {
        let appSupport = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let chaptersDir = appSupport.appendingPathComponent("chapters", isDirectory: true)
        if !fileManager.fileExists(atPath: chaptersDir.path) {
            try fileManager.createDirectory(
                at: chaptersDir,
                withIntermediateDirectories: true,
                attributes: [FileAttributeKey.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )
        }
        let dbURL = chaptersDir.appendingPathComponent("chapter_store.sqlite")
        let canonicalRoot = appSupport.standardized.resolvingSymlinksInPath()
        let canonicalDir = chaptersDir.standardized.resolvingSymlinksInPath()
        let canonicalDB = dbURL.standardized.resolvingSymlinksInPath()

        guard canonicalDir.pathComponents.starts(with: canonicalRoot.pathComponents),
              canonicalDB.pathComponents.starts(with: canonicalRoot.pathComponents) else {
            throw ChapterStoreError.canonicalPathViolation
        }

        // Apply completeUntilFirstUserAuthentication to existing DB & sidecars (-wal, -shm)
        let dbPath = dbURL.path
        let walPath = "\(dbPath)-wal"
        let shmPath = "\(dbPath)-shm"
        let attr = [FileAttributeKey.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]

        try? fileManager.setAttributes(attr, ofItemAtPath: dbPath)
        if fileManager.fileExists(atPath: walPath) {
            try? fileManager.setAttributes(attr, ofItemAtPath: walPath)
        }
        if fileManager.fileExists(atPath: shmPath) {
            try? fileManager.setAttributes(attr, ofItemAtPath: shmPath)
        }

        return dbURL
    }
}
