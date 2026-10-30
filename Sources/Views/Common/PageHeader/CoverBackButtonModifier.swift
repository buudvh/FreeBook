import SwiftUI

/// Nút quay lại cho màn là gốc `NavigationStack` bên trong `fullScreenCover` — gốc stack không có nút back hệ thống và
/// cover không vuốt xuống đóng được. Trông như nút back khi màn được đẩy từ màn khác (icon `chevron.left`, không kèm chữ).
///
/// - Gắn lên view gốc **bên trong** `NavigationStack` của cover: `dismiss` ở đó đóng chính cover.
/// - Icon header 17pt nửa đậm, hitbox 38 × 44pt (chuẩn nút Quay lại).
///
/// ```swift
/// .fullScreenCover(isPresented: $showingBookDetail) {
///     NavigationStack {
///         BookDetailView(...)
///             .coverBackButton()
///     }
/// }
/// ```
struct CoverBackButtonModifier: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 38, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Quay lại")
            }
        }
    }
}

extension View {
    /// Nút quay lại đóng `fullScreenCover` cho màn gốc của cover.
    func coverBackButton() -> some View {
        modifier(CoverBackButtonModifier())
    }
}
