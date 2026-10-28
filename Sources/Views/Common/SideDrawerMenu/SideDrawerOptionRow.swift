import SwiftUI

/// Hàng chọn một trong nhiều (thay `Picker` / menu con có dấu tích): dấu tích ở cột icon cho lựa chọn hiện tại; bấm ⇒
/// áp dụng ngay, ngăn kéo **vẫn mở** như hàng công tắc (rồi nhờ ngăn kéo vẽ lại để dấu tích theo state mới).
struct SideDrawerOptionRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.sideDrawerMenuDismiss) private var drawer

    init(_ title: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button {
            action()
            drawer.refreshContent()
        } label: {
            SideDrawerMenuRowLabel(
                icon: isSelected ? .system("checkmark") : .blank,
                title: title,
                tint: Color.white
            ) {
                EmptyView()
            }
        }
        .buttonStyle(SideDrawerRowButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
