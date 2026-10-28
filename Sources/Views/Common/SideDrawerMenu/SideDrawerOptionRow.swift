import SwiftUI

/// Hàng chọn một trong nhiều (thay `Picker` / menu con có dấu tích): dấu tích ở cột icon cho lựa chọn hiện tại; bấm ⇒
/// áp dụng ngay, ngăn kéo **vẫn mở** như hàng công tắc.
struct SideDrawerOptionRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    init(_ title: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
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
