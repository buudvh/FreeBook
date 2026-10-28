import SwiftUI
import UIKit

/// View UIKit vô hình `SideDrawerMenuModifier` gắn sau màn trong lúc ngăn kéo mở: mỗi lần màn vẽ lại, SwiftUI gọi
/// `updateUIView` (struct chứa closure nên luôn bị coi là đã đổi) ⇒ `onUpdate` đẩy nội dung mới nhất sang cửa sổ ngăn
/// kéo. Nhờ vậy công tắc / dấu chọn trong ngăn kéo đổi theo state của màn dù ngăn kéo nằm ở cửa sổ khác.
struct SideDrawerMenuContentRelay: UIViewRepresentable {
    let onUpdate: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.isHidden = true
        view.isAccessibilityElement = false
        view.accessibilityElementsHidden = true
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        onUpdate()
    }
}
