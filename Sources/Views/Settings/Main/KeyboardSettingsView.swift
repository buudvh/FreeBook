import SwiftUI

/// Cài đặt → Chung → Giao diện → **Bàn phím & ô nhập**: chọn có tự tắt bàn phím khi chạm ra ngoài ô nhập hay không. Cùng tuỳ chọn
/// với menu khi **giữ** nút đóng bàn phím ở thanh công cụ trên bàn phím; ghi qua `KeyboardDismissPreference` để có
/// hiệu lực ngay.
struct KeyboardSettingsView: View {
    @AppStorage(KeyboardDismissPreference.tapOutsideDismissesKey) private var tapOutsideDismisses = true

    var body: some View {
        Form {
            Section {
                optionRow("Tự tắt bàn phím", isSelected: tapOutsideDismisses) {
                    KeyboardDismissPreference.setTapOutsideDismisses(true)
                }
                optionRow("Không tắt bàn phím", isSelected: !tapOutsideDismisses) {
                    KeyboardDismissPreference.setTapOutsideDismisses(false)
                }
            } header: {
                SectionHelpHeader("Khi chạm ra ngoài ô nhập", paragraphs: ["Nút đóng bàn phím nằm ngoài cùng bên trái thanh công cụ trên bàn phím. Giữ nút đó để đổi nhanh lựa chọn này. Phím Return của ô một dòng và thao tác kéo danh sách vẫn tắt bàn phím như thường."])
            }
        }
        .backPageTitle("Bàn phím & ô nhập")
    }

    private func optionRow(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundColor(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
    }
}
