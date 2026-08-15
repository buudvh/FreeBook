import SwiftUI

/// Dialog chọn chế độ nhập/chia sẻ từ điển dùng chung.
/// `onSelect(false)` = Thay thế hoàn toàn, `onSelect(true)` = Gộp (trùng key thì thay mới).
struct DictionaryImportModeDialogModifier: ViewModifier {
    let isPresented: Binding<Bool>
    let title: String
    let message: String
    let onSelect: (Bool) -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(title, isPresented: isPresented) {
            Button("Thay thế hoàn toàn") {
                onSelect(false)
            }
            Button("Gộp (trùng key thì thay mới)") {
                onSelect(true)
            }
            Button("Hủy", role: .cancel) {}
        } message: {
            Text(message)
        }
    }
}

extension View {
    func dictionaryModeDialog(
        isPresented: Binding<Bool>,
        title: String,
        message: String,
        onSelect: @escaping (Bool) -> Void
    ) -> some View {
        modifier(
            DictionaryImportModeDialogModifier(
                isPresented: isPresented,
                title: title,
                message: message,
                onSelect: onSelect
            )
        )
    }
}
