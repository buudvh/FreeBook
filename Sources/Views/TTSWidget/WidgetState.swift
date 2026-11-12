import Foundation

/// Mép mà widget nổi đang dính (nút hub, nút trình duyệt thu nhỏ, nửa viên đĩa nghe). `WidgetMode` (nép mép / bung) bỏ ở
/// 2026-11-11: mọi nút nổi giờ là nửa viên luôn dính mép.
public enum EdgeDirection: String, Codable {
    case left
    case right
}
