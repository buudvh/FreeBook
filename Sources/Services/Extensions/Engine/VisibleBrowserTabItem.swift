import Foundation
import UIKit

// MARK: - Visible Browser Tab Item Model
@MainActor
public struct VisibleBrowserTabItem: Identifiable {
    public let id: String
    public let rawTitle: String
    public var displayTitle: String
    public let loader: VisibleWebViewLoader

    public init(id: String, rawTitle: String, displayTitle: String, loader: VisibleWebViewLoader) {
        self.id = id
        self.rawTitle = rawTitle
        self.displayTitle = displayTitle
        self.loader = loader
    }
}
