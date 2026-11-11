import CoreGraphics
import Foundation

/// Cài đặt riêng của **từng viên thuốc nổi** (Cài đặt › Chung › Giao diện › Viên thuốc nổi, anh Bửu duyệt mockup
/// 2026-11-11): đĩa nghe, nút hub, nút trình duyệt thu nhỏ — mỗi viên có **độ trong suốt**, **độ đục** (6 nấc kính
/// `GlassFrostLevel`) và **độ nhô** (chiều rộng phần nhô ra khỏi mép) của riêng nó, độc lập với "Nút nổi" (`GlassChromeSettings`).
///
/// - Độ nhô tối thiểu = nửa chiều cao ⇒ viên thành **hình bán nguyệt**; chiều cao không đổi (52 / 36). Bìa / icon luôn cách
///   đầu bo như cũ nên viên càng hẹp càng lọt ra ngoài mép (bán nguyệt ⇒ thấy nửa bìa / icon).
/// - Độ trong suốt áp cho lớp màu của kính, bìa / icon (`1 − trong suốt`, không sàn) **và** màu nháy đỏ của viên đó.
/// - Khoá **không có dấu chấm** (luật 1.3.637 của `GlassChromeSettings`: `@AppStorage` nghe qua KVO). Chưa có khoá ⇒ mặc định.
enum EdgePillSettings {
    /// Một loại viên thuốc.
    enum Kind: String, CaseIterable, Identifiable {
        case disc
        case hub
        case browser

        var id: String { rawValue }

        var title: String {
            switch self {
            case .disc: return "Đĩa nghe"
            case .hub: return "Hub"
            case .browser: return "Trình duyệt"
            }
        }

        /// Chiều cao cố định (đĩa = nút "+" 52; hub / trình duyệt = 36) — cũng là đường kính lúc đang kéo.
        var height: CGFloat {
            self == .disc ? 52 : 36
        }

        /// Độ nhô mặc định: đĩa 68 = lề 16 + nút "+" 52 (bìa thẳng cột icon "+"); hub / trình duyệt 38.
        var defaultWidth: Double {
            self == .disc ? 68 : 38
        }

        /// Từ bán nguyệt (nửa chiều cao) tới tối đa.
        var widthRange: ClosedRange<Double> {
            Double(height / 2)...(self == .disc ? 84 : 50)
        }

        var transparencyKey: String { "edgePill\(keyName)Transparency" }
        var frostKey: String { "edgePill\(keyName)Frost" }
        var widthKey: String { "edgePill\(keyName)Width" }

        private var keyName: String {
            switch self {
            case .disc: return "Disc"
            case .hub: return "Hub"
            case .browser: return "Browser"
            }
        }
    }

    static let defaultTransparency = 0.9
    static let defaultFrost = 0.0
    /// Bước của thanh kéo độ nhô (pt).
    static let widthStep = 2.0

    /// Độ nhô hiện tại của `kind` (đã kẹp trong `widthRange`).
    static func width(of kind: Kind) -> CGFloat {
        let stored = UserDefaults.standard.object(forKey: kind.widthKey) as? Double ?? kind.defaultWidth
        return CGFloat(clampedWidth(stored, for: kind))
    }

    /// Cỡ nửa viên lúc dính mép.
    static func size(of kind: Kind) -> CGSize {
        CGSize(width: width(of: kind), height: kind.height)
    }

    static func clampedWidth(_ value: Double, for kind: Kind) -> Double {
        min(max(value, kind.widthRange.lowerBound), kind.widthRange.upperBound)
    }

    /// "Đặt lại" một viên: xoá cả ba khoá ⇒ về mặc định.
    static func reset(_ kind: Kind) {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: kind.transparencyKey)
        defaults.removeObject(forKey: kind.frostKey)
        defaults.removeObject(forKey: kind.widthKey)
    }
}
