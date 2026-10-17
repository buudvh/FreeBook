import Foundation

/// Một section (một hàng trên màn hình) của trang Khám phá do script `explore` trả về, theo hợp đồng extension
/// (extension-api.md). Parser: `ExtensionManager+Explore.swift`.
struct ExploreSection: Identifiable, Hashable, Sendable {
    /// Kiểu bố cục (`type` của section, không phân biệt hoa thường). Rỗng/lạ ⇒ parser bỏ cả section.
    enum Kind: String, Hashable, Sendable {
        /// Carousel ảnh tràn ngang.
        case banner
        /// Hàng thẻ cuộn ngang.
        case horizontalList = "horizontal_list"
        /// Lưới nhiều cột.
        case grid
        /// Danh sách dọc.
        case list
        /// Danh sách dọc có đánh số thứ hạng.
        case ranking
        /// Hàng chip/thẻ chữ.
        case chip
    }

    /// Hình dạng thẻ của các item. Thiếu/lạ ⇒ `book`.
    enum Shape: String, Hashable, Sendable {
        /// 2:3
        case book
        /// 1:1
        case square
        /// Tròn
        case circle
        /// 16:9
        case movie
        /// 9:16
        case short
    }

    /// `id` của script; rỗng ⇒ `<type>_<vị trí>`; trùng ⇒ parser thêm hậu tố để `ForEach` không vỡ.
    let id: String
    let title: String
    let subtitle: String
    let kind: Kind
    let shape: Shape
    let items: [ExploreItem]
    /// "Xem thêm" ở header section — thường là action `list`.
    let more: ExploreAction?
}
