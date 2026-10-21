import SwiftUI

/// Nút 🗑 34×34 nền đỏ nhạt ở cuối dòng của màn Kho Tiện Ích — dùng chung cho dòng tiện ích (tab "Tất cả tiện ích")
/// và dòng nguồn Legado để hai tab giống hệt nhau.
struct ExtensionRowTrashButton: View {
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "trash")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.red)
                .frame(width: 34, height: 34)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}
