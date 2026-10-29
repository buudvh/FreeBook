import SwiftUI

/// Sheet có nội dung chưa lưu: vuốt xuống **không** đóng ngay mà hỏi "Bỏ thay đổi?" (1.3.641). Sheet không còn nút
/// Huỷ/Đóng — vuốt xuống là lối đóng duy nhất, nên đây là chỗ duy nhất người dùng bỏ được bản đang sửa.
///
/// - `isDirty == false` ⇒ vuốt đóng thẳng như mọi sheet khác.
/// - `isDirty == true` ⇒ `interactiveDismissDisabled` chặn vuốt; probe UIKit (`SheetDismissAttemptProbe`) bắt lượt vuốt
///   bị chặn rồi hiện hộp hỏi. "Bỏ thay đổi" ⇒ `onDiscard()` rồi đóng bằng `dismiss` của SwiftUI (đường UIKit
///   `dismiss(animated:)` không báo `presentationControllerDidDismiss` nên binding của sheet sẽ kẹt `true`).
/// - Chỉ chặn vuốt **sau khi** probe đã cài được proxy (`isGuardArmed`): không cài được thì vẫn cho vuốt đóng (mất bản
///   đang sửa) — còn hơn sheet kẹt không có lối ra vì đã bỏ nút Huỷ.
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
    @State private var isGuardArmed = false

    func body(content: Content) -> some View {
        content
            .interactiveDismissDisabled(isDirty && isGuardArmed)
            .background(
                SheetDismissAttemptProbe(
                    onAttempt: { if isDirty { isConfirming = true } },
                    onArmedChange: { armed in
                        if isGuardArmed != armed { isGuardArmed = armed }
                    }
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
    /// Vuốt xuống lúc `isDirty` ⇒ hỏi "Bỏ thay đổi?"; đồng ý ⇒ `onDiscard()` rồi đóng sheet.
    func confirmDiscardOnSwipe(isDirty: Bool, onDiscard: @escaping () -> Void = {}) -> some View {
        modifier(SheetDismissGuardModifier(isDirty: isDirty, onDiscard: onDiscard))
    }
}
