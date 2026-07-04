import Foundation
#if os(iOS)
import UIKit
#endif

struct BackgroundTaskSession {
    #if os(iOS)
    private let taskId: UIBackgroundTaskIdentifier
    
    init(taskId: UIBackgroundTaskIdentifier) {
        self.taskId = taskId
    }
    #else
    init() {}
    #endif
    
    static func begin(name: String) -> BackgroundTaskSession {
        #if os(iOS)
        let id = UIApplication.shared.beginBackgroundTask(withName: name) {
            appLog("⚠️ Background task '\(name)' expired.")
        }
        return BackgroundTaskSession(taskId: id)
        #else
        return BackgroundTaskSession()
        #endif
    }
    
    func end() {
        #if os(iOS)
        if taskId != .invalid {
            UIApplication.shared.endBackgroundTask(taskId)
        }
        #endif
    }
}
