import Combine
import Foundation

/// Cờ nhẹ "màn đọc truyện chữ đang hiện" (1.3.796) — kiểu Thanh nghe nhạc của widget TTS thu gọn khi mở Reader
/// (`TTSWidgetBarViewModel`). `ReaderView.activeBookId` không observe được nên có cờ này.
///
/// Ghi theo `onAppear` / `onDisappear` của `ReaderView`, gọi **trước** mọi `return` sớm ở hai hàm đó: trang đẩy vào trong
/// Reader (Chi tiết, đổi nguồn) hay trình duyệt "Mở link lỗi" che màn đọc đều tính là Reader không hiện. Giữ **tập
/// `bookId`** chứ không đếm: SwiftUI có lúc gọi `onAppear` hai lần không kèm `onDisappear` — đếm thì kẹt ở "đang hiện" tới
/// lúc tắt app; tập thì thêm/bớt lặp vô hại.
@MainActor
final class ReaderPresenceTracker: ObservableObject {
    static let shared = ReaderPresenceTracker()

    @Published private(set) var isReaderVisible = false

    private var visibleBookIds = Set<String>()

    private init() {}

    func readerDidAppear(bookId: String) {
        visibleBookIds.insert(bookId)
        publish()
    }

    func readerDidDisappear(bookId: String) {
        visibleBookIds.remove(bookId)
        publish()
    }

    private func publish() {
        let visible = !visibleBookIds.isEmpty
        guard visible != isReaderVisible else { return }
        isReaderVisible = visible
    }
}
