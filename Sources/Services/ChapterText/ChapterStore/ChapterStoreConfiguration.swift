import Foundation

internal struct ChapterStoreConfiguration {
    internal static let enableChapterStoreRead: Bool = true
    internal static let enableChapterStoreCleanup: Bool = true
    internal static let enableChapterStoreMigration: Bool = true
    internal static let enableSwiftDataTOCWrite: Bool = false
    internal static let enableChapterStorePrimaryWriteNewBook: Bool = true
    internal static let enableChapterStorePrimaryWriteExistingBook: Bool = true
    internal static let enableDualWriteNewBook: Bool = false
    internal static let enableDualWriteExistingBook: Bool = false
    internal static let enableDualWriteCacheMetadata: Bool = false
}
