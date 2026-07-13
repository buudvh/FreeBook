import Foundation
import SwiftData

@Model
public final class DownloadTaskModel {
    @Attribute(.unique) public var id: UUID
    public var bookId: String
    public var bookTitle: String
    public var bookCoverUrl: String
    public var taskTypeRaw: String
    public var statusRaw: String
    public var progressCount: Int
    public var totalCount: Int
    public var errorMessage: String?
    public var isCancelled: Bool
    
    public var extensionPackageId: String
    public var detailUrl: String
    public var startFromCurrent: Bool
    public var limitRaw: Int
    public var translate: Bool
    public var onlyExportCached: Bool
    public var createdAt: Date

    public init(
        id: UUID,
        bookId: String,
        bookTitle: String,
        bookCoverUrl: String,
        taskTypeRaw: String,
        statusRaw: String,
        progressCount: Int,
        totalCount: Int,
        errorMessage: String? = nil,
        isCancelled: Bool = false,
        extensionPackageId: String,
        detailUrl: String,
        startFromCurrent: Bool,
        limitRaw: Int,
        translate: Bool,
        onlyExportCached: Bool,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.bookId = bookId
        self.bookTitle = bookTitle
        self.bookCoverUrl = bookCoverUrl
        self.taskTypeRaw = taskTypeRaw
        self.statusRaw = statusRaw
        self.progressCount = progressCount
        self.totalCount = totalCount
        self.errorMessage = errorMessage
        self.isCancelled = isCancelled
        self.extensionPackageId = extensionPackageId
        self.detailUrl = detailUrl
        self.startFromCurrent = startFromCurrent
        self.limitRaw = limitRaw
        self.translate = translate
        self.onlyExportCached = onlyExportCached
        self.createdAt = createdAt
    }
}
