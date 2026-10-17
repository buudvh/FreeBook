import SwiftUI
import Combine

/// Snapshot "trình duyệt đang thu nhỏ và còn tab" cho widget trình duyệt nổi. Chủ duy nhất là
/// `BrowserFloatingWidgetWindowManager` (1.3.533); chỉ phát khi giá trị **thật sự** đổi, nên số tab hay cờ thu
/// nhỏ không đổi thì widget không vẽ lại theo mỗi `stateDidChangeNotification`.
@MainActor
final class VisibleBrowserPresentationReader: ObservableObject {
    struct Snapshot: Equatable {
        var isHidden = false
        var tabCount = 0
        var showReopenButton = false
    }

    @Published private(set) var snapshot = Snapshot()
    private var cancellable: AnyCancellable?

    init(manager: VisibleBrowserTabManager? = nil) {
        let manager = manager ?? VisibleBrowserTabManager.shared
        snapshot = Self.makeSnapshot(from: manager)
        cancellable = NotificationCenter.default
            .publisher(for: VisibleBrowserTabManager.stateDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refresh(from: manager)
            }
    }

    private func refresh(from manager: VisibleBrowserTabManager) {
        let newSnapshot = Self.makeSnapshot(from: manager)
        guard newSnapshot != snapshot else { return }
        snapshot = newSnapshot
    }

    private static func makeSnapshot(from manager: VisibleBrowserTabManager) -> Snapshot {
        Snapshot(
            isHidden: manager.isHidden,
            tabCount: manager.tabs.count,
            showReopenButton: manager.isHidden && !manager.tabs.isEmpty
        )
    }
}
