import SwiftUI

/// Nền "kính" của ngăn kéo menu ba chấm: nền phía sau đã làm nhoè + lớp tối + viền mảnh.
///
/// Mức nhoè và lớp tối lấy từ Cài đặt › Giao diện (`GlassChromeSettings`, 1.3.636). Lịch sử: material đầy đủ + lớp tối
/// (1.3.622–626) nhoè nền Kệ đen thành mảng xám đều; bỏ nhoè (1.3.631–632); nhoè một phần bằng animator dừng giữa chừng
/// (1.3.633, kẹt ở mức nhoè đầy đủ trên máy); material + `.opacity(độ đục)` (1.3.640) — nhưng kính iOS chỉ nhoè khi hiện
/// đủ 100%, nên 0–95% thực ra **không nhoè**, chỉ 100% mới nhoè.
///
/// Từ 1.3.645 không dùng kính iOS nữa: nhoè **mịn** bằng SwiftUI `.blur` trên `backdrop` — ảnh chụp màn bên dưới lúc mở
/// ngăn kéo (`SideDrawerMenuWindowManager`) hoặc dải bìa của ô xem trước (`AppearanceSettingsView`). Bán kính =
/// độ đục × `maxBlurRadius`; độ đục 0 hoặc không có `backdrop` ⇒ không vẽ lớp nhoè, nhìn thẳng xuống màn bên dưới.
/// `backdrop` căn góc **trên-phải** (ngăn kéo bám mép phải, tràn vùng an toàn) và dịch `backdropShift` để đứng yên theo
/// màn hình trong lúc ngăn kéo trượt.
struct SideDrawerGlassBackground<Backdrop: View>: View {
    /// Bán kính nhoè ở độ đục 100% (pt).
    static var maxBlurRadius: CGFloat { 28 }

    private let backdrop: Backdrop?
    private let backdropShift: CGFloat

    @AppStorage(GlassChromeSettings.drawerTransparencyKey)
    private var transparency = GlassChromeSettings.defaultDrawerTransparency
    @AppStorage(GlassChromeSettings.drawerFrostKey)
    private var frost = GlassChromeSettings.defaultDrawerFrost

    /// - Parameters:
    ///   - backdropShift: truyền `-offset` của ngăn kéo để nền phía sau không trượt theo ngăn kéo.
    ///   - backdrop: đúng phần màn nằm sau ngăn kéo khi căn góc trên-phải (thường là cả màn).
    init(backdropShift: CGFloat = 0, @ViewBuilder backdrop: () -> Backdrop) {
        self.backdrop = backdrop()
        self.backdropShift = backdropShift
    }

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 16, style: .continuous)
    }

    var body: some View {
        ZStack {
            if frost > 0, let backdrop {
                Color.clear
                    .overlay(alignment: .topTrailing) {
                        backdrop
                            .blur(radius: frost * Self.maxBlurRadius, opaque: true)
                            .offset(x: backdropShift)
                    }
                    // Cắt **sau** khi dịch: ảnh đứng yên theo màn, khung cắt chạy theo ngăn kéo.
                    .clipShape(shape)
            }
            shape.fill(Color(white: 0.16).opacity(1 - transparency))
            shape.stroke(Color.white.opacity(0.14), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }
}

extension SideDrawerGlassBackground where Backdrop == EmptyView {
    /// Không có nền phía sau ⇒ chỉ lớp tối + viền (như độ đục 0).
    init() {
        self.init(backdrop: { EmptyView() })
    }
}
