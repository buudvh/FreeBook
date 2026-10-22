import SwiftUI
import UIKit

public struct ShareSheet: UIViewControllerRepresentable {
    public let activityItems: [Any]
    public var applicationActivities: [UIActivity]? = nil
    public var onComplete: ((UIActivity.ActivityType?, Bool, [Any]?, Error?) -> Void)? = nil

    public init(
        activityItems: [Any],
        applicationActivities: [UIActivity]? = nil,
        onComplete: ((UIActivity.ActivityType?, Bool, [Any]?, Error?) -> Void)? = nil
    ) {
        self.activityItems = activityItems
        self.applicationActivities = applicationActivities
        self.onComplete = onComplete
    }

    public func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        // Bảng chia sẻ tự đóng khi xong (chia sẻ hoặc huỷ) mà SwiftUI **không** biết ⇒ cờ/`item` của `.sheet` kẹt ở
        // trạng thái "đang mở" và lần bấm sau không hiện gì. Gọi `dismiss` của chính sheet để SwiftUI hạ trạng thái.
        let dismiss = context.environment.dismiss
        controller.completionWithItemsHandler = { activityType, completed, returnedItems, activityError in
            onComplete?(activityType, completed, returnedItems, activityError)
            Task { @MainActor in dismiss() }
        }
        return controller
    }

    public func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
