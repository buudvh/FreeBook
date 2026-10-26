import SwiftUI

/// Icon dùng chung cho các nút sao chép / dán / sao chép văn bản gốc, và icon bật/tắt dịch.
///
/// `translate` thay SF Symbol `character.bubble` ở mọi nút dịch (1.3.605). Từ 1.3.607 là Material Symbols
/// `g_translate` (Rounded, tô đặc, nét 600 — giấy phép Apache 2.0, `Docs/ThirdParty/MaterialSymbols-LICENSE.txt`),
/// không còn trùng ảnh 文A của `originalText`. Trạng thái bật/tắt chỉ phân biệt bằng màu (hoặc chữ "Bật/Tắt" trong menu).
///
/// Vì sao không dùng SF Symbols: cặp SF Symbol họ `doc.on.*` cũ cho sao chép và dán gần như
/// giống hệt nhau ở cỡ nhỏ, hai nút đứng cạnh nhau là người dùng không phân biệt được. Thay bằng
/// bộ icon Lucide (giấy phép ISC, phiên bản ghim ghi ở `Docs/ThirdParty/Lucide-LICENSE.txt`),
/// đặt trong `Sources/Assets.xcassets/Lucide*.imageset` dạng SVG template.
///
/// Lưu ý khi dùng:
/// - Ảnh asset **không** co giãn theo `.font(...)` như SF Symbol, nên mỗi call site phải truyền
///   `size` tường minh khớp với cỡ đang hiển thị (`.caption` ≈ 13, `.caption2` ≈ 12, `.body` ≈ 17,
///   `.system(size: X)` ⇒ X).
/// - Màu lấy từ `foregroundColor`/`foregroundStyle` của view cha vì ảnh render ở chế độ template.
/// - Trong `contextMenu`/`Menu` (UIKit dựng `UIMenu`, bỏ qua frame tuỳ chỉnh) thì dùng
///   `Label(_:image: AppGlyph.copy.assetName)`.
/// - Không quay lại SF Symbol họ `doc.on.*` cho nút sao chép/dán.
enum AppGlyph {
    /// Sao chép — Lucide `copy`.
    case copy
    /// Dán — Lucide `clipboard-paste`.
    case paste
    /// Sao chép văn bản gốc (chưa dịch) — Lucide `languages`, để không trùng icon "Copy" đứng cạnh.
    case originalText
    /// Bật/tắt dịch, dịch lại — Material Symbols `g_translate`.
    case translate

    /// Tên imageset trong `Sources/Assets.xcassets`.
    var assetName: String {
        switch self {
        case .copy: return "LucideCopy"
        case .paste: return "LucideClipboardPaste"
        case .originalText: return "LucideLanguages"
        case .translate: return "MaterialGTranslate"
        }
    }

    /// Nhãn VoiceOver mặc định — tránh để VoiceOver đọc tên asset ("LucideCopy").
    /// Call site đã có `.accessibilityLabel` riêng thì nhãn đó được ưu tiên.
    var accessibilityName: String {
        switch self {
        case .copy: return "Sao chép"
        case .paste: return "Dán"
        case .originalText: return "Sao chép văn bản gốc"
        case .translate: return "Dịch"
        }
    }

    /// Ảnh template vuông `size × size` pt; đổi màu bằng `foregroundColor` như SF Symbol.
    func image(size: CGFloat) -> some View {
        Image(assetName, label: Text(accessibilityName))
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}
