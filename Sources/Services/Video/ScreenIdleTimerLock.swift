import UIKit

/// Khoá "giữ màn hình sáng" (`UIApplication.isIdleTimerDisabled`) dùng chung cho nhiều chủ: trình phát video
/// (`VideoPlaybackSession`) và màn đọc truyện tranh (`ComicReaderView`).
///
/// Mỗi chủ chỉ bật/tắt phần của mình. Giá trị gốc chụp khi chủ **đầu tiên** bật và chỉ trả lại khi chủ **cuối cùng**
/// tắt ⇒ chủ này rời màn không làm màn tự tắt giữa lúc chủ kia còn cần, cũng không chụp nhầm giá trị "đang bật" của
/// chủ kia làm gốc rồi trả sai về sau. Bật/tắt lặp lại với cùng một chủ là an toàn (idempotent).
@MainActor
enum ScreenIdleTimerLock {
    private static var owners = Set<ObjectIdentifier>()
    private static var baseline: Bool?

    static func acquire(_ owner: ObjectIdentifier) {
        guard owners.insert(owner).inserted else { return }
        if owners.count == 1 {
            baseline = UIApplication.shared.isIdleTimerDisabled
        }
        if !UIApplication.shared.isIdleTimerDisabled {
            UIApplication.shared.isIdleTimerDisabled = true
        }
    }

    static func release(_ owner: ObjectIdentifier) {
        guard owners.remove(owner) != nil, owners.isEmpty else { return }
        UIApplication.shared.isIdleTimerDisabled = baseline ?? false
        baseline = nil
    }
}
