import Foundation

/// Bản chụp cỡ của cả bốn bố cục trang Khám phá cho **một** loại nguồn. `ExploreSectionsView` đọc từ
/// `ExploreLayoutSizePreferences` trong `body` rồi truyền xuống các section qua `ExploreRenderContext`.
struct ExploreLayoutSizes: Equatable {
    var grid: ExploreLayoutSize = .default
    var horizontalList: ExploreLayoutSize = .default
    /// Dùng chung cho section `list` và `ranking`.
    var list: ExploreLayoutSize = .default
    var banner: ExploreLayoutSize = .default

    static let `default` = ExploreLayoutSizes()

    subscript(kind: ExploreLayoutSizeKind) -> ExploreLayoutSize {
        get {
            switch kind {
            case .grid: return grid
            case .horizontalList: return horizontalList
            case .list: return list
            case .banner: return banner
            }
        }
        set {
            switch kind {
            case .grid: grid = newValue
            case .horizontalList: horizontalList = newValue
            case .list: list = newValue
            case .banner: banner = newValue
            }
        }
    }
}
