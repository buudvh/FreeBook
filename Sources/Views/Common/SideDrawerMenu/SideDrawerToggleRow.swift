import SwiftUI

/// Hàng công tắc của ngăn kéo: chạm bất kỳ đâu trên hàng ⇒ đổi giá trị ngay, ngăn kéo **vẫn mở**.
///
/// Công tắc cùng kiểu với phần còn lại của app (`SwitchToggleStyle(tint: Color(white: 0.35))`); nó chỉ để hiển thị,
/// cú chạm do cả hàng nhận. VoiceOver thấy cả hàng như một `Toggle` chuẩn.
struct SideDrawerToggleRow: View {
    let title: String
    let icon: SideDrawerMenuIcon
    @Binding var isOn: Bool

    init(_ title: String, systemImage: String, isOn: Binding<Bool>) {
        self.title = title
        self.icon = .system(systemImage)
        self._isOn = isOn
    }

    /// Icon là `AppGlyph` (asset template) thay vì SF Symbol.
    init(_ title: String, glyph: AppGlyph, isOn: Binding<Bool>) {
        self.title = title
        self.icon = .asset(glyph.assetName)
        self._isOn = isOn
    }

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            SideDrawerMenuRowLabel(icon: icon, title: title, tint: Color.white) {
                Toggle(title, isOn: $isOn)
                    .labelsHidden()
                    .toggleStyle(SwitchToggleStyle(tint: Color(white: 0.35)))
                    .allowsHitTesting(false)
            }
        }
        .buttonStyle(SideDrawerRowButtonStyle())
        .accessibilityRepresentation {
            Toggle(title, isOn: $isOn)
        }
    }
}
