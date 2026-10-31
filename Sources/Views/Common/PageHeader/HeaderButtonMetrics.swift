import SwiftUI

/// Kích thước cho **cụm nút đứng liền nhau** trên header (1.3.664): "…" | Xong, 🔍 | …, ↻ | +…
///
/// - Gộp cả cụm vào **một** `ToolbarItem` chứa `HStack(spacing: pairSpacing)`. Để mỗi nút một `ToolbarItem` (hoặc
///   một `ToolbarItemGroup`) thì iOS tự giãn cách giữa các mục, không chỉnh được.
/// - Icon giữ 17pt nửa đậm, chỉ khung hẹp lại còn `pairIconWidth` (chiều cao giữ như file đang dùng: 36 hoặc 38).
/// - Nút tròn có nền 38×38 giữ nguyên cỡ, chỉ thu khoảng cách còn `pairCircleSpacing`.
/// - Nút đứng một mình vẫn theo chuẩn cũ: khung tối thiểu 36×36 (khuyến nghị 36×38).
enum HeaderButtonMetrics {
    static let pairSpacing: CGFloat = 2
    static let pairIconWidth: CGFloat = 32
    static let pairCircleSpacing: CGFloat = 4
}
