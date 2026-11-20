import SwiftUI

/// Chuẩn tiêu đề trang của app (1.3.641, ba kiểu từ 1.3.652; 1.3.1018 bỏ tiêu đề hàng 2): **một hàng, một cỡ** — 22pt đậm,
/// một dòng, không co chữ (dài thì cắt đuôi).
/// - Tab gốc và gốc sheet (`.leading`): tiêu đề **bên trái** hàng nút.
/// - Trang có nút trái (`.centered` — trang đẩy vào có nút back, trang con trong sheet có nút ‹): tiêu đề luôn nằm **ngay
///   cạnh nút trái** ở hàng nút (anh Bửu 2026-11-20: "đừng hiện tiêu đề 2 hàng nữa, để nó luôn hiển thị cạnh nút trái nếu
///   có nút trái"). 1.3.984–1.3.1017 dùng tiêu đề lớn của iOS ở hàng 2 (thu vào cạnh nút back khi cuộn) — đã bỏ, cùng đầu
///   dò `PageTitleCollapseProbe`.
/// - `.hidden` = không hiện tiêu đề nào (Chi tiết truyện).
///
/// - Luôn gắn `.navigationTitle` thật: VoiceOver đọc được tên màn và menu nhấn giữ nút back vẫn liệt kê đúng tên.
/// - Ô `principal` luôn là ô rỗng ⇒ tiêu đề nhỏ căn giữa của hệ thống không bao giờ hiện.
/// - Trang con trong sheet (`\.sheetPageBack` có giá trị): nút ‹ (`HeaderBackButton`) và tiêu đề dựng **chung một**
///   `ToolbarItem` để thứ tự luôn là ‹ rồi chữ (hai mục `topBarLeading` riêng thì iOS tự xếp / giãn cách).
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
///     .backPageTitle("Giao diện")           // trang có nút back: tiêu đề cạnh nút back
/// TTSSettingsList()
///     .pageTitle("Cài đặt TTS", style: isPresentedAsSheet ? .leading : .centered)   // màn mở được cả hai kiểu
/// ```
struct PageTitleModifier: ViewModifier {
    let title: String
    let style: PageTitleStyle
    /// Đoạn giải thích sau nút "?" cạnh tiêu đề (1.3.900, sheet "Giọng đọc"); `nil` = không có nút. Chỉ ở kiểu `.leading`.
    var help: [LocalizedStringKey]? = nil

    static let fontSize: CGFloat = HeaderMetrics.rowTitleFontSize
    /// Khoảng chữ lùi về phía nút ‹ tự dựng (khung 38pt, mũi ~13pt canh trái) ⇒ mũi cách chữ ~8pt như nút back hệ thống.
    private static let sheetBackTitleOverlap: CGFloat = 17

    @Environment(\.sheetPageBack) private var sheetPageBack

    func body(content: Content) -> some View {
        content
            .floatingHomeButton()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
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
                // `.hidden`: không dựng ô nào — ô rỗng vẫn chiếm chỗ góc trái, đẩy các nút của trang.
                if style == .centered {
                    ToolbarItem(placement: .topBarLeading) {
                        if let sheetPageBack {
                            HStack(spacing: 0) {
                                HeaderBackButton(action: sheetPageBack)
                                titleText
                                    .padding(.leading, -Self.sheetBackTitleOverlap)
                                    .allowsHitTesting(false)
                            }
                        } else {
                            titleText
                        }
                    }
                }
            }
    }

    /// Tiêu đề hàng nút. Kiểu `.centered` có trần bề ngang (chừa chỗ cho nút back + cụm nút phải); dài hơn thì cắt đuôi.
    private var titleText: some View {
        Text(title)
            .font(.system(size: Self.fontSize, weight: .bold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: style == .centered ? HeaderMetrics.besideLeftButtonTitleMaxWidth : nil, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
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

    /// Trang có nút back: tiêu đề 22pt đậm ngay cạnh nút back.
    func backPageTitle(_ title: String) -> some View {
        modifier(PageTitleModifier(title: title, style: .centered))
    }
}
