import UIKit

/// **Vùng đứng cố định** của mọi nửa viên dính mép — đĩa nghe, nút hub, nút trình duyệt thu nhỏ (anh Bửu 2026-11-11: "để
/// viên thuốc tự tránh header và thanh tab dù có hay không luôn, tránh nó chạy lên chạy xuống").
///
/// - Mép trên luôn **dưới vùng header**: vùng an toàn trên + 52 (header 44 + 8), kể cả màn không có header.
/// - Mép dưới luôn **trên vùng nút "+" / thanh tab**: vùng an toàn đáy + 76 (= khe 12 + nút "+" 52 + khe 12), kể cả màn không
///   có thanh tab hay nút "+". iPhone 15: viên thuốc ở trong 111…742 pt ⇒ trên thanh tab (769), nút "+" (754), thanh dưới
///   trình duyệt (766), nút tai nghe Reader (750) mà không phải tự đẩy lên.
/// - Vùng cố định ⇒ đổi tab / đẩy trang / mở sheet không làm viên thuốc nhảy. Chỗ người dùng kéo tới vẫn lưu nguyên, vùng chỉ
///   kẹp lúc vẽ và lúc thả.
enum EdgePillZone {
    /// Khoảng chừa dưới vùng an toàn trên (header 44 + 8).
    static let topClearance: CGFloat = 52
    /// Khoảng chừa trên vùng an toàn đáy (khe 12 + nút "+" 52 + khe 12).
    static let bottomClearance: CGFloat = FloatingRoundButton.bottomInset + FloatingRoundButton.size + 12

    /// Mép trên nhỏ nhất của viên thuốc (toạ độ cửa sổ).
    static func minTop(safeInsets: UIEdgeInsets) -> CGFloat {
        safeInsets.top + topClearance
    }

    /// Mép dưới lớn nhất của viên thuốc (toạ độ cửa sổ).
    static func maxBottom(bounds: CGRect, safeInsets: UIEdgeInsets) -> CGFloat {
        bounds.height - safeInsets.bottom - bottomClearance
    }

    /// Dải mép trên được phép của viên cao `height`.
    static func topRange(height: CGFloat, bounds: CGRect, safeInsets: UIEdgeInsets) -> ClosedRange<CGFloat> {
        let lower = minTop(safeInsets: safeInsets)
        return lower...max(lower, maxBottom(bounds: bounds, safeInsets: safeInsets) - height)
    }

    /// Dải tâm Y được phép của viên cao `height`.
    static func centerYRange(height: CGFloat, bounds: CGRect, safeInsets: UIEdgeInsets) -> ClosedRange<CGFloat> {
        let tops = topRange(height: height, bounds: bounds, safeInsets: safeInsets)
        return (tops.lowerBound + height / 2)...(tops.upperBound + height / 2)
    }

    /// Kẹp tâm Y vào vùng.
    static func clampedCenterY(_ value: CGFloat, height: CGFloat, bounds: CGRect, safeInsets: UIEdgeInsets) -> CGFloat {
        let range = centerYRange(height: height, bounds: bounds, safeInsets: safeInsets)
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
