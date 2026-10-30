import SwiftUI

/// Chuẩn tiêu đề trang của app (1.3.641, ba kiểu từ 1.3.652): **một** cỡ chữ 22pt đậm, một dòng (thu nhỏ tới 80% rồi
/// cắt đuôi). Tab gốc và sheet: tiêu đề **bên trái** (`.leading`). Trang có nút back: tiêu đề **giữa** (`.centered`).
/// `.hidden` = không hiện tiêu đề nào (Chi tiết truyện).
///
/// - Luôn gắn `.navigationTitle` thật: VoiceOver đọc được tên màn và menu nhấn giữ nút back vẫn liệt kê đúng tên.
/// - Tiêu đề hệ thống (căn giữa, 17pt) bị thay bằng ô `principal` của mình (chữ 22pt ở `.centered`, ô rỗng ở hai kiểu
///   còn lại) nên không bao giờ hiện chồng lên.
/// - Icon header vẫn theo chuẩn `.system(size: 17, weight: .semibold)` ⇒ tiêu đề luôn to và đậm hơn icon.
/// - Trang đẩy vào (`.centered`, `.hidden`) **ẩn thanh tab** dưới đáy (1.3.660): chỉ trang gốc của tab (và gốc sheet —
///   vốn không có thanh tab) giữ nó. Đừng gắn `.toolbar(.hidden, for: .tabBar)` riêng ở từng màn.
///
/// ```swift
/// SettingsList()
///     .pageTitle("Cài đặt")                 // tab gốc / sheet: trái
/// DetailList()
///     .backPageTitle("Giao diện")           // trang đẩy vào, có nút back: giữa
/// TTSSettingsList()
///     .pageTitle("Cài đặt TTS", style: isPresentedAsSheet ? .leading : .centered)   // màn mở được cả hai kiểu
/// ```
struct PageTitleModifier: ViewModifier {
    let title: String
    let style: PageTitleStyle

    static let fontSize: CGFloat = 22

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(style == .leading ? .automatic : .hidden, for: .tabBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if style == .centered {
                        titleText
                    } else {
                        Color.clear
                            .frame(width: 1, height: 1)
                            .accessibilityHidden(true)
                    }
                }
                if style == .leading {
                    ToolbarItem(placement: .topBarLeading) {
                        titleText
                    }
                }
            }
    }

    private var titleText: some View {
        Text(title)
            .font(.system(size: Self.fontSize, weight: .bold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .truncationMode(.tail)
            .accessibilityAddTraits(.isHeader)
    }
}

extension View {
    /// Tiêu đề 22pt đậm. Mặc định `.leading` (tab gốc, gốc sheet); màn mở được cả hai kiểu truyền `style:`.
    func pageTitle(_ title: String, style: PageTitleStyle = .leading) -> some View {
        modifier(PageTitleModifier(title: title, style: style))
    }

    /// Trang đẩy vào (có nút back): tiêu đề 22pt đậm nằm giữa thanh điều hướng.
    func backPageTitle(_ title: String) -> some View {
        modifier(PageTitleModifier(title: title, style: .centered))
    }
}
