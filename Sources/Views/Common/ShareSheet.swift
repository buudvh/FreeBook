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
        controller.completionWithItemsHandler = { activityType, completed, returnedItems, activityError in
            onComplete?(activityType, completed, returnedItems, activityError)
        }
        return controller
    }

    public func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
