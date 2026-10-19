import ObjectiveC
import UIKit

/// Đưa thanh công cụ bàn phím vào ô nhập mà **gán `inputAccessoryView` không ăn**.
///
/// Ô `TextField` / `TextEditor` của SwiftUI là lớp con nội bộ của `UITextField` / `UITextView` và tự quản accessory của
/// nó (phục vụ `.toolbar(placement: .keyboard)`): giá trị gán từ ngoài có thể bị getter override bỏ qua hoặc bị gán đè ở
/// lượt cập nhật sau — thanh không bao giờ hiện (lỗi 1.3.548). Cách làm: giữ thanh trong associated object của **đúng ô**
/// rồi thay getter `inputAccessoryView` của **lớp cụ thể** đó (mỗi lớp một lần) bằng bản trả thanh khi ô có gắn, còn lại
/// gọi getter gốc — ô không gắn (ô mật khẩu, trình sửa Script) giữ nguyên hành vi.
///
/// Không bao giờ thay getter của chính `UITextField` / `UITextView` (lớp gốc của UIKit tôn trọng giá trị gán).
@MainActor
enum KeyboardAccessoryOverride {
    /// Khoá associated object — con trỏ cố định suốt vòng đời app.
    private static let accessoryKey = UnsafeRawPointer(UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1))
    private static var patchedClasses = Set<ObjectIdentifier>()

    /// Lớp có phải lớp nội bộ của SwiftUI không (vd `SwiftUI.UIKitTextField`) — loại này luôn đi đường thay getter.
    static func isSwiftUIClass(_ cls: AnyClass) -> Bool {
        NSStringFromClass(cls).contains("SwiftUI")
    }

    /// Gắn `accessory` cho `view` và bảo đảm getter của lớp `view` trả nó. Trả `false` nếu không tìm được getter để thay.
    @discardableResult
    static func install(_ accessory: UIView, on view: UIView) -> Bool {
        objc_setAssociatedObject(view, accessoryKey, accessory, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        guard let cls = object_getClass(view) else { return false }
        if cls == UITextField.self || cls == UITextView.self { return false }
        if patchedClasses.contains(ObjectIdentifier(cls)) { return true }

        let selector = #selector(getter: UIResponder.inputAccessoryView)
        guard let method = class_getInstanceMethod(cls, selector) else { return false }
        // Getter gốc (của lớp này hoặc thừa kế từ lớp cha) — gọi lại khi ô không gắn thanh.
        typealias Getter = @convention(c) (AnyObject, Selector) -> UIView?
        let original = unsafeBitCast(method_getImplementation(method), to: Getter.self)
        let key = accessoryKey
        let replacement: @convention(block) (AnyObject) -> UIView? = { object in
            if let attached = objc_getAssociatedObject(object, key) as? UIView {
                return attached
            }
            return original(object, selector)
        }
        // `class_replaceMethod` thêm method vào đúng lớp này nếu lớp chỉ thừa kế getter — lớp cha không bị đụng.
        class_replaceMethod(cls, selector, imp_implementationWithBlock(replacement), method_getTypeEncoding(method))
        patchedClasses.insert(ObjectIdentifier(cls))
        return true
    }

    /// Ô đã đi đường thay getter chưa (để không gán/thay hai lần).
    static func isPatched(_ view: UIView) -> Bool {
        guard let cls = object_getClass(view) else { return false }
        return patchedClasses.contains(ObjectIdentifier(cls))
    }
}
