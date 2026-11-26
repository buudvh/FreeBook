import SwiftUI

/// Hộp xác nhận **Xoá token** của token tùy chọn (1.3.1063), dùng chung ở màn Token tùy chọn, màn danh sách từ và menu
/// nhấn giữ của bảng token: xoá cả danh sách từ nên phải hỏi lại (khác xoá một họ / một từ — một chạm). Xoá qua store
/// rồi toast; `onDeleted` để chỗ gắn đọc lại / đóng màn.
struct QuickTranslationCustomTokenDeletionDialog: ViewModifier {
    @Binding var pending: QuickTranslationCustomToken?
    let onDeleted: (QuickTranslationCustomToken) -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            pending.map { "Xoá token \($0.syntax)?" } ?? "",
            isPresented: Binding(
                get: { pending != nil },
                set: { if !$0 { pending = nil } }
            ),
            titleVisibility: .visible,
            presenting: pending
        ) { token in
            Button("Xoá token", role: .destructive) { delete(token) }
            Button("Hủy", role: .cancel) {}
        } message: { token in
            Text(verbatim: "\(token.entries.count) từ của token sẽ mất. Rule có \(token.syntax) vẫn giữ trong file nhưng không khớp nữa.")
        }
    }

    private func delete(_ token: QuickTranslationCustomToken) {
        if let error = QuickTranslationCustomTokenStore.shared.deleteToken(name: token.name) {
            ToastManager.shared.show(message: error, type: .error)
            return
        }
        ToastManager.shared.show(message: "Đã xoá token \(token.syntax)", type: .success)
        onDeleted(token)
    }
}

extension View {
    /// Gắn hộp xác nhận xoá token tùy chọn: đặt `pending` = token cần xoá là hộp hiện.
    func customTokenDeletionDialog(
        pending: Binding<QuickTranslationCustomToken?>,
        onDeleted: @escaping (QuickTranslationCustomToken) -> Void = { _ in }
    ) -> some View {
        modifier(QuickTranslationCustomTokenDeletionDialog(pending: pending, onDeleted: onDeleted))
    }
}
