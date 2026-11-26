import SwiftUI

/// Sheet có nội dung chưa lưu: vuốt xuống **hoặc chạm ra ngoài sheet** không đóng ngay mà hỏi "Bỏ thay đổi?" (1.3.641;
/// chạm ra ngoài từ 1.3.1066). Sheet không còn nút Huỷ/Đóng — vuốt / chạm ngoài là lối đóng duy nhất, nên đây là chỗ
/// duy nhất người dùng bỏ được bản đang sửa.
///
/// - `isDirty == false` ⇒ vuốt / chạm ngoài đóng thẳng như mọi sheet khác.
/// - `isDirty == true` ⇒ delegate trung gian của probe UIKit (`SheetDismissAttemptProbe`) trả `false` ở
///   `presentationControllerShouldDismiss` rồi hiện hộp hỏi. "Bỏ thay đổi" ⇒ `onDiscard()` rồi đóng bằng `dismiss` của
///   SwiftUI (đường UIKit `dismiss(animated:)` không báo `presentationControllerDidDismiss` nên binding của sheet sẽ kẹt
///   `true`).
/// - **Không** dùng `interactiveDismissDisabled` (bản trước 1.3.1066): nó bật `isModalInPresentation`, UIKit khi đó bỏ
///   qua hẳn chạm ngoài sheet (sheet nấc `.medium` như màn Sửa từ đứng im, không hỏi gì) và chỉ báo lượt vuốt.
/// - Chỉ chặn khi probe đã cài được proxy: không cài được thì vẫn cho đóng (mất bản đang sửa) — còn hơn sheet kẹt không
///   có lối ra vì đã bỏ nút Huỷ.
///
/// Gắn ở **gốc** nội dung sheet (thường là `NavigationStack`), không gắn ở màn con được đẩy vào: `dismiss` ở đó là pop.
///
/// ```swift
/// NavigationStack { editor }
///     .confirmDiscardOnSwipe(isDirty: hasChanges)
/// ```
struct SheetDismissGuardModifier: ViewModifier {
    let isDirty: Bool
    let onDiscard: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isConfirming = false

    func body(content: Content) -> some View {
        content
            .background(
                SheetDismissAttemptProbe(
                    isDirty: isDirty,
                    onAttempt: { if isDirty { isConfirming = true } }
                )
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            )
            .alert("Bỏ thay đổi?", isPresented: $isConfirming) {
                Button("Bỏ thay đổi", role: .destructive) {
                    onDiscard()
                    dismiss()
                }
                Button("Tiếp tục sửa", role: .cancel) {}
            } message: {
                Text("Nội dung chưa lưu sẽ mất.")
            }
    }
}

extension View {
    /// Vuốt xuống / chạm ra ngoài sheet lúc `isDirty` ⇒ hỏi "Bỏ thay đổi?"; đồng ý ⇒ `onDiscard()` rồi đóng sheet.
    func confirmDiscardOnSwipe(isDirty: Bool, onDiscard: @escaping () -> Void = {}) -> some View {
        modifier(SheetDismissGuardModifier(isDirty: isDirty, onDiscard: onDiscard))
    }
}
