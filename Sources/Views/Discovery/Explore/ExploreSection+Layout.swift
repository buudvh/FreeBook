import SwiftUI

/// Kích thước thẻ theo `shape` của section Khám phá. Đặt ở tầng View để model (`ExploreSection`) không phụ thuộc UI.
extension ExploreSection.Shape {
    /// Tỉ lệ rộng : cao của bìa.
    var aspectRatio: CGFloat {
        switch self {
        case .book: return 2.0 / 3.0
        case .square, .circle: return 1
        case .movie: return 16.0 / 9.0
        case .short: return 9.0 / 16.0
        }
    }

    /// Số cột của section `grid`.
    var gridColumnCount: Int {
        switch self {
        case .movie: return 2
        case .circle: return 4
        case .book, .square, .short: return 3
        }
    }

    /// Bề rộng thẻ ở section `horizontal_list`.
    var rowCardWidth: CGFloat {
        switch self {
        case .book: return 108
        case .square: return 120
        case .circle: return 80
        case .movie: return 220
        case .short: return 118
        }
    }

    /// Bề rộng ảnh nhỏ ở dòng `list` / `ranking`.
    var thumbnailWidth: CGFloat {
        switch self {
        case .movie: return 112
        case .square, .circle: return 60
        case .book, .short: return 54
        }
    }
}
