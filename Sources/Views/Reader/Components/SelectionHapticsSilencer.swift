import UIKit
import ObjectiveC.runtime

/// Bộ vô hiệu hoá phản hồi rung (Haptic Feedback) mặc định của iOS khi bôi đen văn bản.
///
/// Mặc định trên iOS, khi người dùng ấn giữ và kéo thanh bôi đen (selection grabbers) trong `UITextView`,
/// UIKit tự động gọi `[UIImpactFeedbackGenerator impactOccurred]` và `[UISelectionFeedbackGenerator selectionChanged]`,
/// gây ra hiện tượng rung nảy khi bắt đầu và rung tê liên tục khi kéo. Lớp này sử dụng Method Swizzling
/// để chuyển hướng toàn bộ các lệnh gọi haptic sang hàm rỗng, giúp quá trình bôi đen hoàn toàn êm ái.
public final class SelectionHapticsSilencer {
    private static var isSwizzled = false

    /// Kích hoạt tắt rung khi bôi đen text. Hàm này là idempotent, gọi nhiều lần an toàn.
    public static func silenceSelectionHaptics() {
        guard !isSwizzled else { return }
        isSwizzled = true

        let noopBlock: @convention(block) (AnyObject) -> Void = { _ in }
        let noopImp = imp_implementationWithBlock(noopBlock)

        let noopWithArgBlock: @convention(block) (AnyObject, AnyObject?) -> Void = { _, _ in }
        let noopWithArgImp = imp_implementationWithBlock(noopWithArgBlock)

        let noopWithFloatBlock: @convention(block) (AnyObject, CGFloat) -> Void = { _, _ in }
        let noopWithFloatImp = imp_implementationWithBlock(noopWithFloatBlock)

        let targets: [AnyClass] = [
            UISelectionFeedbackGenerator.self,
            UIImpactFeedbackGenerator.self,
            UIFeedbackGenerator.self,
            NSClassFromString("_UISelectionFeedbackGenerator"),
            NSClassFromString("_UIImpactFeedbackGenerator"),
            NSClassFromString("_UIFeedbackGenerator")
        ].compactMap { $0 }

        let targetSelectors: [(Selector, IMP)] = [
            (#selector(UISelectionFeedbackGenerator.selectionChanged), noopImp),
            (#selector(UIImpactFeedbackGenerator.impactOccurred as (UIImpactFeedbackGenerator) -> () -> Void), noopImp),
            (#selector(UIImpactFeedbackGenerator.impactOccurred(intensity:) as (UIImpactFeedbackGenerator) -> (CGFloat) -> Void), noopWithFloatImp),
            (#selector(UIFeedbackGenerator.prepare), noopImp),
            (Selector(("userInteractionStarted")), noopImp),
            (Selector(("userInteractionEnded")), noopImp),
            (Selector(("_playFeedback:")), noopWithArgImp),
            (Selector(("_playFeedback:withOptions:")), noopWithArgImp),
            (Selector(("_selectionChanged")), noopImp),
            (Selector(("selectionChangedAt:")), noopWithArgImp)
        ]

        for targetClass in targets {
            for (selector, replacementImp) in targetSelectors {
                if let method = class_getInstanceMethod(targetClass, selector) {
                    method_setImplementation(method, replacementImp)
                }
            }
        }
    }
}
