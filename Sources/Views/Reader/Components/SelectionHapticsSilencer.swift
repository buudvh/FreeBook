import UIKit

/// Bộ vô hiệu hoá phản hồi rung (Haptic Feedback) mặc định của iOS khi bôi đen văn bản.
///
/// Mặc định trên iOS, khi người dùng kéo thanh bôi đen (selection grabbers) trong `UITextView`,
/// UIKit tự động gọi `[UISelectionFeedbackGenerator selectionChanged]` liên tục trên từng ký tự/từ,
/// gây ra hiện tượng rung tê liên tục ở máy. Lớp này sử dụng Method Swizzling để chuyển hướng lệnh gọi
/// sang hàm rỗng, giúp quá trình bôi đen hoàn toàn êm ái.
public final class SelectionHapticsSilencer {
    private static var isSwizzled = false

    /// Kích hoạt tắt rung khi bôi đen text. Hàm này là idempotent, gọi nhiều lần an toàn.
    public static func silenceSelectionHaptics() {
        guard !isSwizzled else { return }
        isSwizzled = true

        let originalSelector = #selector(UISelectionFeedbackGenerator.selectionChanged)
        let swizzledSelector = #selector(UISelectionFeedbackGenerator.fb_silencedSelectionChanged)

        guard let originalMethod = class_getInstanceMethod(UISelectionFeedbackGenerator.self, originalSelector),
              let swizzledMethod = class_getInstanceMethod(UISelectionFeedbackGenerator.self, swizzledSelector) else {
            return
        }

        method_exchangeImplementations(originalMethod, swizzledMethod)
    }
}

extension UISelectionFeedbackGenerator {
    @objc fileprivate func fb_silencedSelectionChanged() {
        // Không làm gì cả: triệt tiêu hoàn toàn lệnh rung Taptic Engine từ UIKit khi bôi đen text
    }
}
