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
    // MARK: - Hai cực & Hai tầng bảng màu

    /// Nền Canvas (Nền App / Scrim / Bars)
    public static var paperCanvas: Color {
        paperCanvasColor(for: EInkModeSettings.shared.paperColor)
    }

    /// Nền Card (Nền thẻ truyện / Hàng danh sách / Panel Form / Sheet)
    public static var paperCard: Color {
        paperCardColor(for: EInkModeSettings.shared.paperColor)
    }

    /// Alias tương thích ngược: mặc định trỏ về `paperCanvas`.
    public static var paper: Color {
        paperCanvas
    }

    public static func paperCanvasColor(for selection: EInkModeSettings.EInkPaperColor) -> Color {
        switch selection {
        case .kindlePaperwhite: return Color(red: 0xDC / 255, green: 0xDE / 255, blue: 0xDF / 255)
        case .koboComfortLight: return Color(red: 0xDE / 255, green: 0xD6 / 255, blue: 0xC8 / 255)
        case .pureBalanced:     return Color(red: 0xD6 / 255, green: 0xD6 / 255, blue: 0xD6 / 255)
        case .pureDeep:         return Color(red: 0xBC / 255, green: 0xBC / 255, blue: 0xBC / 255)
        }
    }

    public static func paperCardColor(for selection: EInkModeSettings.EInkPaperColor) -> Color {
        switch selection {
        case .kindlePaperwhite: return Color(red: 0xF2 / 255, green: 0xF4 / 255, blue: 0xF5 / 255)
        case .koboComfortLight: return Color(red: 0xF2 / 255, green: 0xEB / 255, blue: 0xE0 / 255)
        case .pureBalanced:     return Color(red: 0xEE / 255, green: 0xEE / 255, blue: 0xEE / 255)
        case .pureDeep:         return Color(red: 0xE4 / 255, green: 0xE4 / 255, blue: 0xE4 / 255)
        }
    }

    public static func paperColor(for selection: EInkModeSettings.EInkPaperColor) -> Color {
        paperCanvasColor(for: selection)
    }

    /// Mực — đen tuyệt đối.
    public static let ink = Color.black

    public static var paperCanvasUIColor: UIColor {
        paperCanvasUIColor(for: EInkModeSettings.shared.paperColor)
    }

    public static var paperCardUIColor: UIColor {
        paperCardUIColor(for: EInkModeSettings.shared.paperColor)
    }

    public static var paperUIColor: UIColor {
        paperCanvasUIColor
    }

    public static func paperCanvasUIColor(for selection: EInkModeSettings.EInkPaperColor) -> UIColor {
        switch selection {
        case .kindlePaperwhite: return UIColor(red: 0xDC / 255, green: 0xDE / 255, blue: 0xDF / 255, alpha: 1)
        case .koboComfortLight: return UIColor(red: 0xDE / 255, green: 0xD6 / 255, blue: 0xC8 / 255, alpha: 1)
        case .pureBalanced:     return UIColor(red: 0xD6 / 255, green: 0xD6 / 255, blue: 0xD6 / 255, alpha: 1)
        case .pureDeep:         return UIColor(red: 0xBC / 255, green: 0xBC / 255, blue: 0xBC / 255, alpha: 1)
        }
    }

    public static func paperCardUIColor(for selection: EInkModeSettings.EInkPaperColor) -> UIColor {
        switch selection {
        case .kindlePaperwhite: return UIColor(red: 0xF2 / 255, green: 0xF4 / 255, blue: 0xF5 / 255, alpha: 1)
        case .koboComfortLight: return UIColor(red: 0xF2 / 255, green: 0xEB / 255, blue: 0xE0 / 255, alpha: 1)
        case .pureBalanced:     return UIColor(red: 0xEE / 255, green: 0xEE / 255, blue: 0xEE / 255, alpha: 1)
        case .pureDeep:         return UIColor(red: 0xE4 / 255, green: 0xE4 / 255, blue: 0xE4 / 255, alpha: 1)
        }
    }

    public static func paperUIColor(for selection: EInkModeSettings.EInkPaperColor) -> UIColor {
        paperCanvasUIColor(for: selection)
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

    // MARK: - Trạng thái & Thang sắc độ xám

    /// Nền của mục đang chọn (đảo ngược).
    public static let selectedFill = Color.black
    /// Chữ/icon trên nền đang chọn.
    public static let selectedContent = Color.white
    /// Nền của mục chưa chọn.
    public static var normalFill: Color { paper }
    /// Viền của mục chưa chọn.
    public static let normalBorder = Color.black

    /// Xám nhạt cho chip cố định, nhãn phụ (#EEEEEE)
    public static let grayLight = Color(red: 0xEE / 255, green: 0xEE / 255, blue: 0xEE / 255)
    /// Xám vừa cho token quy tắc, danh từ chung, tác vụ tải (#C8C8C8)
    public static let grayMedium = Color(red: 0xC8 / 255, green: 0xC8 / 255, blue: 0xC8 / 255)
    /// Xám đậm cho dấu câu, tên riêng, cập nhật chương (#9E9E9E)
    public static let grayDark = Color(red: 0x9E / 255, green: 0x9E / 255, blue: 0x9E / 255)
}
