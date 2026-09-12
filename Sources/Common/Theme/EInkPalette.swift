import SwiftUI
import UIKit

/// Bảng màu của chế độ E-Ink: **chỉ `#000` / `#FFF` cộng đường kẻ đặc**.
///
/// **Vì sao không dùng `opacity` để tạo xám.** Panel e-ink chỉ có vài mức xám (nhiều máy 4 mức), nên
/// `Color.black.opacity(0.1)` render ra gần như trắng và mất hẳn tín hiệu — đó là lý do chế độ này
/// phải thay *cách* mã hoá trạng thái, không chỉ thay *màu*:
///
/// | Nghĩa | Cách mã hoá trên e-ink |
/// |---|---|
/// | mờ / phụ | **viền hairline 1px** hoặc giảm `fontWeight` — không giảm opacity |
/// | đang chọn / hoạt động | **đảo ngược**: nền đen, chữ & icon trắng |
/// | phân loại trung tính | nền trắng + **viền đen 1px** |
/// | lỗi / cảnh báo | **viền nét đứt** kèm tiền tố `!` |
///
/// Không dùng màu nào khác ngoài hai cực: mọi sắc độ trung gian đều phải đi qua viền, độ đậm chữ,
/// hoặc nét đứt.
public enum EInkPalette {
    // MARK: - Hai cực

    /// Nền giấy — **màu tuy chọn** (White / Gray / Warm), đọc từ `EInkModeSettings.shared.paperColor`.
    ///
    /// Là `var` tính toán chứ không phải hằng: đổi màu nền trong Cài đặt phải lập tức lan sang mọi
    /// bề mặt e-ink (panel trình đọc, badge, thanh chọn tab, nav/tab bar qua `EInkAppearance`,
    /// FlashView làm mới). Mặc định Gray #D8D8D2 — xám giấy, dịu mắt nhất. Cả ba tông đều là sáng,
    /// nên `ink` (đen) luôn đọc được trên đó.
    public static var paper: Color {
        switch EInkModeSettings.shared.paperColor {
        case .white: return Color(red: 0xF2 / 255, green: 0xF1 / 255, blue: 0xEC / 255)
        case .gray:  return Color(red: 0xD8 / 255, green: 0xD8 / 255, blue: 0xD2 / 255)
        case .warm:  return Color(red: 0xE5 / 255, green: 0xDE / 255, blue: 0xD0 / 255)
        }
    }

    /// Mực — đen tuyệt đối.
    public static let ink = Color.black

    public static var paperUIColor: UIColor {
        switch EInkModeSettings.shared.paperColor {
        case .white: return UIColor(red: 0xF2 / 255, green: 0xF1 / 255, blue: 0xEC / 255, alpha: 1)
        case .gray:  return UIColor(red: 0xD8 / 255, green: 0xD8 / 255, blue: 0xD2 / 255, alpha: 1)
        case .warm:  return UIColor(red: 0xE5 / 255, green: 0xDE / 255, blue: 0xD0 / 255, alpha: 1)
        }
    }

    public static let inkUIColor = UIColor.black

    // MARK: - Nét

    /// Đường phân tách. Trên e-ink **phải là nét đặc**; nét mờ 15% sẽ biến mất hoàn toàn.
    public static let separator = Color.black
    /// Độ dày đường phân tách — dày hơn 0.5pt của iOS để panel kịp bật hẳn điểm ảnh.
    public static let separatorWidth: CGFloat = 1
    /// Độ dày viền thay cho bóng đổ.
    public static let borderWidth: CGFloat = 1
    /// Viền của trạng thái "đang chọn" — dày hơn để đọc được ngay cả khi không có tương phản màu.
    public static let selectedBorderWidth: CGFloat = 1.5

    // MARK: - Trạng thái

    /// Nền của mục đang chọn (đảo ngược).
    public static let selectedFill = Color.black
    /// Chữ/icon trên nền đang chọn.
    public static let selectedContent = Color.white
    /// Nền của mục chưa chọn.
    public static let normalFill = Color.white
    /// Viền của mục chưa chọn.
    public static let normalBorder = Color.black
}
