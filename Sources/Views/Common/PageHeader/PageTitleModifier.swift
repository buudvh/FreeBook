import SwiftUI

/// Chuẩn tiêu đề trang của app (1.3.641): **một** cỡ cho mọi tab gốc và sheet — chữ 22pt đậm, nằm **bên trái**
/// thanh điều hướng, một dòng (thu nhỏ tới 80% rồi cắt đuôi). Trang có nút back thì **không** hiện tiêu đề.
///
/// - Luôn gắn `.navigationTitle` thật: VoiceOver đọc được tên màn và menu nhấn giữ nút back vẫn liệt kê đúng tên.
/// - Tiêu đề hệ thống (căn giữa, 17pt) bị thay bằng một ô `principal` rỗng nên không bao giờ hiện chồng lên.
/// - Icon header vẫn theo chuẩn `.system(size: 17, weight: .semibold)` ⇒ tiêu đề luôn to và đậm hơn icon.
///
/// ```swift
/// SettingsList()
///     .pageTitle("Cài đặt")                 // tab gốc / sheet
/// DetailList()
///     .backPageTitle("Giao diện")           // trang đẩy vào, có nút back
/// TTSSettingsList()
///     .pageTitle("Cài đặt TTS", isVisible: isPresentedAsSheet)   // màn mở được cả hai kiểu
/// ```
struct PageTitleModifier: ViewModifier {
    let title: String
    let isVisible: Bool

    static let fontSize: CGFloat = 22

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Color.clear
                        .frame(width: 1, height: 1)
                        .accessibilityHidden(true)
                }
                if isVisible {
                    ToolbarItem(placement: .topBarLeading) {
                        Text(title)
                            .font(.system(size: Self.fontSize, weight: .bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .truncationMode(.tail)
                            .accessibilityAddTraits(.isHeader)
                    }
                }
            }
    }
}

extension View {
    /// Tiêu đề trái 22pt đậm cho tab gốc và sheet. `isVisible: false` = trang có nút back (chỉ giữ `navigationTitle`).
    func pageTitle(_ title: String, isVisible: Bool = true) -> some View {
        modifier(PageTitleModifier(title: title, isVisible: isVisible))
    }

    /// Trang đẩy vào (có nút back): không hiện tiêu đề, vẫn giữ `navigationTitle` cho VoiceOver và menu nút back.
    func backPageTitle(_ title: String) -> some View {
        modifier(PageTitleModifier(title: title, isVisible: false))
    }
}
