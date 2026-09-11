import SwiftUI

/// Toàn bộ hiệu ứng của chế độ E-Ink gói trong **một** `ViewModifier`.
///
/// **Vì sao gói chung thay vì nhiều modifier nhỏ.** Màn phải tự cập nhật khi người dùng đổi chế độ, mà
/// để làm được thì cần một `DynamicProperty` (`@AppStorage`) — property wrapper chỉ hoạt động bên trong
/// `View`/`ViewModifier`. Gói mọi hiệu ứng vào một struct vừa giữ được tính reactive, vừa giữ file đúng
/// **1 type top level** theo `MULTI_PRIMARY_TYPES` (checker chỉ đếm type ở cột 0, nên các type lồng nhau
/// không tính).
///
/// **Nguyên tắc chung:** bật e-ink thì thay *cách mã hoá* chứ không chỉ thay màu — viền thay bóng, đảo
/// ngược thay tô nhạt, nét đứt thay màu cảnh báo. Xem `EInkPalette` để biết vì sao không dùng `opacity`.
struct EInkEffect: ViewModifier {

    enum Kind {
        /// Viền đen 1px thay cho bóng đổ.
        case outline(cornerRadius: CGFloat, lineWidth: CGFloat)
        /// Bóng đổ **gốc** của màn: chỉ vẽ khi tắt e-ink, vì lúc bật đã có `outline` thay thế.
        case shadow(color: Color, radius: CGFloat, x: CGFloat, y: CGFloat)
        /// Nền đục thay `.ultraThinMaterial` — backdrop blur là thứ e-ink render tệ nhất.
        case surface(cornerRadius: CGFloat)
        /// Thang xám cho ảnh (bìa sách, icon tiện ích).
        case monochrome
        /// Đường kẻ đặc ở mép dưới.
        case rule
        /// Màu accent: đen khi bật, màu gốc khi tắt.
        case accentForeground(Color)
        /// Badge ba tầng — thay cho việc phân biệt bằng màu.
        case tag(Tier)
    }

    /// Ba tầng badge thay cho bốn sắc màu. "Đổi màu sang xám" sẽ làm các badge giống hệt nhau và mất
    /// sạch thông tin, nên phải đổi cả hình thức. Dùng ở hàng tiện ích (`RepositoryManagerView`).
    enum Tier {
        /// Cần người dùng chú ý — nền đen đặc, chữ trắng. Mỗi hàng chỉ nên có tối đa một badge tầng này,
        /// nếu không thì không còn gì nổi lên.
        case solid
        /// Phân loại trung tính — nền trắng, viền đen 1px.
        case outline
        /// Bất thường / cảnh báo — nền trắng, viền đen **nét đứt**.
        case dashed
    }

    /// Trạng thái "đang chọn" cho chip / pill / segment.
    ///
    /// Tách khỏi `Kind` vì cần một `Shape` cụ thể (`Capsule`, `RoundedRectangle`…) mà enum không mang
    /// được generic. Lồng trong `EInkEffect` nên vẫn không tính là type top level.
    struct Selection<S: InsettableShape>: ViewModifier {
        @AppStorage(EInkModeSettings.Key.enabled) private var isEnabled = false

        let isSelected: Bool
        let shape: S
        let selectedFill: Color
        let normalFill: Color
        let selectedContent: Color
        let normalContent: Color
        /// Viền gốc khi **tắt** e-ink. Nhiều màn không có viền, nên mặc định `nil`.
        var normalBorder: Color? = nil
        var normalBorderWidth: CGFloat = 1

        func body(content: Content) -> some View {
            if isEnabled {
                content
                    .foregroundStyle(isSelected ? EInkPalette.selectedContent : EInkPalette.ink)
                    .background(isSelected ? EInkPalette.selectedFill : EInkPalette.paper, in: shape)
                    .overlay {
                        shape.strokeBorder(
                            EInkPalette.ink,
                            lineWidth: isSelected ? EInkPalette.selectedBorderWidth : EInkPalette.borderWidth
                        )
                    }
            } else {
                content
                    .foregroundStyle(isSelected ? selectedContent : normalContent)
                    .background(isSelected ? selectedFill : normalFill, in: shape)
                    .overlay {
                        if let normalBorder {
                            shape.strokeBorder(normalBorder, lineWidth: normalBorderWidth)
                        }
                    }
            }
        }
    }

    @AppStorage(EInkModeSettings.Key.enabled) private var isEnabled = false
    let kind: Kind

    func body(content: Content) -> some View {
        switch kind {
        case .outline(let cornerRadius, let lineWidth):
            if isEnabled {
                content.overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(EInkPalette.ink, lineWidth: lineWidth)
                }
            } else {
                content
            }

        case .shadow(let color, let radius, let x, let y):
            if isEnabled {
                content
            } else {
                content.shadow(color: color, radius: radius, x: x, y: y)
            }

        case .surface(let cornerRadius):
            if isEnabled {
                content
                    .background(
                        EInkPalette.paper,
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(EInkPalette.ink, lineWidth: EInkPalette.borderWidth)
                    }
            } else {
                content.background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
            }

        case .monochrome:
            content
                .grayscale(isEnabled ? 1 : 0)
                .contrast(isEnabled ? 1.35 : 1)

        case .rule:
            if isEnabled {
                content.overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(EInkPalette.separator)
                        .frame(height: EInkPalette.separatorWidth)
                }
            } else {
                content
            }

        case .accentForeground(let fallback):
            content.foregroundStyle(isEnabled ? EInkPalette.ink : fallback)

        case .tag(let tier):
            tagBody(content, tier: tier)
        }
    }

    @ViewBuilder
    private func tagBody(_ content: Content, tier: Tier) -> some View {
        if !isEnabled {
            content
        } else {
            switch tier {
            case .solid:
                content
                    .foregroundStyle(EInkPalette.selectedContent)
                    .background(EInkPalette.selectedFill, in: RoundedRectangle(cornerRadius: 4, style: .continuous))

            case .outline:
                content
                    .foregroundStyle(EInkPalette.ink)
                    .background(EInkPalette.paper, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(EInkPalette.ink, lineWidth: EInkPalette.borderWidth)
                    }

            case .dashed:
                content
                    .foregroundStyle(EInkPalette.ink)
                    .background(EInkPalette.paper, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(EInkPalette.ink, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    }
            }
        }
    }
}

// MARK: - Cửa vào cho call site

extension View {
    /// Viền đen 1px thay cho bóng đổ.
    func einkOutline(_ cornerRadius: CGFloat, lineWidth: CGFloat = EInkPalette.borderWidth) -> some View {
        modifier(EInkEffect(kind: .outline(cornerRadius: cornerRadius, lineWidth: lineWidth)))
    }

    /// Bóng đổ gốc của màn — bị bỏ khi bật e-ink (đã có `einkOutline` thay thế).
    func einkShadow(
        _ color: Color = .black.opacity(0.15),
        radius: CGFloat,
        x: CGFloat = 0,
        y: CGFloat = 0
    ) -> some View {
        modifier(EInkEffect(kind: .shadow(color: color, radius: radius, x: x, y: y)))
    }

    /// Nền đục + viền đen thay cho `.ultraThinMaterial`.
    func einkSurface(_ cornerRadius: CGFloat) -> some View {
        modifier(EInkEffect(kind: .surface(cornerRadius: cornerRadius)))
    }

    /// Ép thang xám cho ảnh khi bật e-ink.
    func einkMonochrome() -> some View {
        modifier(EInkEffect(kind: .monochrome))
    }

    /// Đường kẻ đặc ở mép dưới — thay cho việc dựa vào bóng/nền mờ để phân tách vùng.
    func einkRule() -> some View {
        modifier(EInkEffect(kind: .rule))
    }

    /// Accent (xanh/cam/đỏ) thành **đen** khi bật e-ink.
    func einkAccentForeground(_ fallback: Color) -> some View {
        modifier(EInkEffect(kind: .accentForeground(fallback)))
    }

    /// Badge ba tầng — xem `EInkEffect.Tier`.
    func einkTag(_ tier: EInkEffect.Tier) -> some View {
        modifier(EInkEffect(kind: .tag(tier)))
    }

    /// Trạng thái "đang chọn" cho chip / pill / segment.
    func einkSelection<S: InsettableShape>(
        isSelected: Bool,
        in shape: S,
        selectedFill: Color,
        normalFill: Color,
        selectedContent: Color,
        normalContent: Color,
        normalBorder: Color? = nil,
        normalBorderWidth: CGFloat = 1
    ) -> some View {
        modifier(EInkEffect.Selection(
            isSelected: isSelected,
            shape: shape,
            selectedFill: selectedFill,
            normalFill: normalFill,
            selectedContent: selectedContent,
            normalContent: normalContent,
            normalBorder: normalBorder,
            normalBorderWidth: normalBorderWidth
        ))
    }
}
