import Foundation

public enum DownloadPresentationEvent: Sendable, Equatable {
    case showToast(message: String, type: ToastType)
    /// Bản xuất đã hoàn chỉnh trên đĩa và sẵn sàng chia sẻ.
    ///
    /// Tầng Services **không** mở share sheet nữa (trước đây `DownloadManager` tự đi tìm
    /// `rootViewController` và `import UIKit`): nó chỉ phát event này, còn `ExportShareCoordinator` ở tầng
    /// Views quyết định lúc nào presentation là an toàn.
    case exportReady(filePath: String, bookTitle: String)
}
