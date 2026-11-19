import SwiftUI

/// Chuẩn tiêu đề trang của app (1.3.641, ba kiểu từ 1.3.652, kiểu `.centered` đổi ở 1.3.984): **một** cỡ chữ 22pt đậm,
/// một dòng. Tab gốc và gốc sheet: tiêu đề **bên trái** hàng nút (`.leading`). Trang có nút back (`.centered`): tiêu đề
/// nằm **hàng 2**, sát lề trái, dưới các nút; cuộn lên thì hàng 2 thu lại và tiêu đề nhỏ (17pt nửa đậm) hiện **cạnh nút
/// back** (anh Bửu 2026-11-19: "hiển thị ở lề trái dưới các nút đó", "cuộn lên thì tiêu đề về nằm kế nút bên trái và giảm
/// size lại để đảm bảo chỗ hiển thị"). `.hidden` = không hiện tiêu đề nào (Chi tiết truyện).
///
/// - Luôn gắn `.navigationTitle` thật: VoiceOver đọc được tên màn và menu nhấn giữ nút back vẫn liệt kê đúng tên.
/// - Ô `principal` luôn là ô rỗng ⇒ tiêu đề nhỏ căn giữa của hệ thống không bao giờ hiện.
/// - `.centered` = tiêu đề lớn của iOS (`navigationBarTitleDisplayMode(.large)`), cỡ 22pt đậm đặt toàn app ở
///   `NavigationBarAppearance` (`largeTitleTextAttributes`). Lúc thu: `PageTitleCollapseProbe` dò cây UIKit báo về, ô
///   `topBarLeading` (ngay sau nút back) hiện tiêu đề nhỏ — dò hỏng thì tiêu đề chỉ cuộn đi, không hiện chồng hai bản.
/// - Icon header vẫn theo chuẩn `.system(size: 17, weight: .semibold)` ⇒ tiêu đề luôn to và đậm hơn icon.
/// - Thanh tab **hệ thống** luôn ẩn ở mọi kiểu (1.3.668): thanh thật là `MainTabBar`, chỉ nằm trong trang gốc của tab
///   (`.mainTabBar()`), nên trang đẩy vào phủ lên nó. Ẩn/hiện theo kiểu (bản 1.3.660) làm thanh hiện lại trễ lúc back ⇒
///   trang gốc giật — đừng đổi giá trị này theo trang.
/// - Gắn **nút Home nổi** (`FloatingHomeButtonModifier`) ở mọi kiểu: trang đẩy vào trong tab Kệ / Khám phá / Tiện ích có
///   nút tròn góc dưới phải về trang gốc của tab (trang có nút "+" nổi thì Home nằm trong menu xổ của "+"). Có hiện hay
///   không do cây UIKit quyết định lúc chạy (`FloatingHomePlacement`), không do kiểu tiêu đề.
///
/// ```swift
/// SettingsList()
///     .pageTitle("Cài đặt")                 // tab gốc / sheet: trái, hàng nút
/// DetailList()
///     .backPageTitle("Giao diện")           // trang đẩy vào, có nút back: hàng 2, thu vào cạnh nút back khi cuộn
/// TTSSettingsList()
///     .pageTitle("Cài đặt TTS", style: isPresentedAsSheet ? .leading : .centered)   // màn mở được cả hai kiểu
/// ```
struct PageTitleModifier: ViewModifier {
    let title: String
    let style: PageTitleStyle
    /// Đoạn giải thích sau nút "?" cạnh tiêu đề (1.3.900, sheet "Giọng đọc"); `nil` = không có nút. Chỉ ở kiểu `.leading`.
    var help: [LocalizedStringKey]? = nil

    static let fontSize: CGFloat = 22
    /// Cỡ tiêu đề nhỏ cạnh nút back khi tiêu đề lớn đã thu (kiểu `.centered`).
    static let collapsedFontSize: CGFloat = 17
    /// Trần bề ngang tiêu đề nhỏ — chừa chỗ cho cụm nút bên phải; dài hơn thì cắt đuôi.
    static let collapsedMaxWidth: CGFloat = 230

    /// Tiêu đề lớn ở hàng 2 đã thu (chỉ kiểu `.centered`, do `PageTitleCollapseProbe` báo).
    @State private var isLargeTitleCollapsed = false

    func body(content: Content) -> some View {
        content
            .floatingHomeButton()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(style == .centered ? .large : .inline)
            .toolbar(.hidden, for: .tabBar)
            .background(alignment: .topLeading) {
                if style == .centered {
                    PageTitleCollapseProbe(title: title) { collapsed in
                        guard isLargeTitleCollapsed != collapsed else { return }
                        withAnimation(.easeOut(duration: 0.15)) { isLargeTitleCollapsed = collapsed }
                    }
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Color.clear
                        .frame(width: 1, height: 1)
                        .accessibilityHidden(true)
                }
                if style == .leading {
                    ToolbarItem(placement: .topBarLeading) {
                        if let help {
                            HStack(spacing: 2) {
                                titleText
                                SectionHelpButton(accessibilityLabel: "Giải thích \(title)", paragraphs: help)
                            }
                        } else {
                            titleText
                        }
                    }
                }
                if style == .centered {
                    ToolbarItem(placement: .topBarLeading) {
                        collapsedTitleText
                            .opacity(isLargeTitleCollapsed ? 1 : 0)
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

    /// Tiêu đề nhỏ cạnh nút back khi tiêu đề lớn đã thu. VoiceOver đã có `.navigationTitle` ⇒ ẩn khỏi trợ năng.
    private var collapsedTitleText: some View {
        Text(title)
            .font(.system(size: Self.collapsedFontSize, weight: .semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: Self.collapsedMaxWidth, alignment: .leading)
            .accessibilityHidden(true)
    }
}

extension View {
    /// Tiêu đề 22pt đậm. Mặc định `.leading` (tab gốc, gốc sheet); màn mở được cả hai kiểu truyền `style:`.
    func pageTitle(_ title: String, style: PageTitleStyle = .leading) -> some View {
        modifier(PageTitleModifier(title: title, style: style))
    }

    /// Tiêu đề trái (gốc sheet) kèm nút "?" mở đoạn giải thích — như `SectionHelpHeader` của section.
    func pageTitle(_ title: String, help: [LocalizedStringKey]) -> some View {
        modifier(PageTitleModifier(title: title, style: .leading, help: help))
    }

    /// Trang đẩy vào (có nút back): tiêu đề 22pt đậm ở hàng 2 sát lề trái; cuộn lên thì thu vào cạnh nút back.
    func backPageTitle(_ title: String) -> some View {
        modifier(PageTitleModifier(title: title, style: .centered))
    }
}
