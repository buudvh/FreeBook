import Foundation
import UIKit

// MARK: - Visible Browser Tab Item Model
@MainActor
public struct VisibleBrowserTabItem: Identifiable {
    public let id: String
    public let rawTitle: String
    public var displayTitle: String
    public let loader: VisibleWebViewLoader
    /// Thời điểm tab được tạo, dùng để biết tab đã mở đủ lâu (≥ 10s) cho nhịp nháy
    /// của widget trình duyệt khi đang thu nhỏ.
    public let createdAt: Date

    public init(
        id: String,
        rawTitle: String,
        displayTitle: String,
        loader: VisibleWebViewLoader,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.rawTitle = rawTitle
        self.displayTitle = displayTitle
        self.loader = loader
        self.createdAt = createdAt
    }
}
