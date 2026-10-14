import Combine
import Foundation

/// Gộp ba nguồn (AI, trình duyệt thu nhỏ, thông báo) thành **một** snapshot cho nút hub nổi (1.3.524).
///
/// ## Một reader duy nhất
/// `FloatingHubWindowManager` sở hữu đúng **một** instance và tiêm vào container. Widget thông báo cũ tạo
/// hai reader giống hệt nhau (một ở manager, một ở container) — tức hai bộ subscription cho cùng dữ liệu.
///
/// ## Hai tầng chống vẽ lại
/// - `Snapshot` chỉ phát khi giá trị **thật sự** đổi (`guard updated != snapshot`).
/// - Nút chỉ vẽ lại theo `ButtonState` (loại mục + số chưa đọc), **không** theo `detail`. Tiêu đề AI đổi theo
///   từng batch ("Đang quét: Batch N/T") chỉ chạm tới menu, và menu chỉ vẽ khi đang mở.
///
/// ## Không observe cả `AIRuntimeCoordinator`
/// Coordinator ghi `activeSession` mỗi ≥ 50 ms khi stream. Observe cả object là kéo hub vẽ lại theo nhịp đó
/// (đúng lỗi của view widget AI cũ, xoá ở 1.3.524). Ở đây chỉ nghe đúng ba publisher cần.
@MainActor
final class FloatingHubPresentationReader: ObservableObject {
    /// Phần trạng thái mà **nút** cần. Cố ý không chứa `detail` của mục.
    struct ButtonState: Equatable {
        var kinds: [FloatingHubItem.Kind] = []
        /// Bằng 0 khi mục Thông báo vắng (ví dụ đang ở tab Kệ Sách) — khi đó hub không có chỉ báo chưa đọc.
        var unreadCount = 0
    }

    struct Snapshot: Equatable {
        /// Theo thứ tự hiển thị cố định của `FloatingHubItem.Kind`.
        var items: [FloatingHubItem] = []
        /// Bằng 0 khi mục Thông báo vắng.
        var unreadCount = 0

        var button: ButtonState {
            ButtonState(kinds: items.map(\.kind), unreadCount: unreadCount)
        }
    }

    /// Trạng thái AI lấy từ **giá trị được phát ra** của ba publisher, không đọc lại property của coordinator.
    private struct AIState: Equatable {
        var isRunning = false
        var isFullScreenPresented = false
        var title = ""
    }

    @Published private(set) var snapshot = Snapshot()

    private let browserReader = VisibleBrowserPresentationReader()
    private let inboxReader = NotificationInboxPresenceReader()
    private var aiState = AIState()
    /// Tab Kệ Sách là tab 0 của `MainTabView`; mặc định `true` vì app luôn khởi động ở tab đó. Tab Kệ đã có
    /// nút chuông trên toolbar nên mục Thông báo vắng ở đó.
    private var isShelfTabActive = true
    private var cancellables = Set<AnyCancellable>()

    init() {
        let coordinator = AIRuntimeCoordinator.shared
        aiState = AIState(
            isRunning: coordinator.isRunning,
            isFullScreenPresented: coordinator.isFullScreenPresented,
            title: coordinator.activeTaskTitle
        )
        snapshot = makeSnapshot()

        // `@Published` phát ở willSet ⇒ mọi sink đi qua `receive(on:)` rồi mới tính lại. Nhánh AI dùng
        // thẳng giá trị được phát ra (khuôn của window manager widget AI cũ).
        Publishers.CombineLatest3(
            coordinator.$isRunning,
            coordinator.$isFullScreenPresented,
            coordinator.$activeTaskTitle
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] isRunning, isFullScreenPresented, title in
            guard let self else { return }
            self.aiState = AIState(
                isRunning: isRunning,
                isFullScreenPresented: isFullScreenPresented,
                title: title
            )
            self.refresh()
        }
        .store(in: &cancellables)

        browserReader.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        inboxReader.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        // `selectedTab` của `MainTabView` là `@State` cục bộ nên chỉ đọc được qua notification này.
        NotificationCenter.default
            .publisher(for: .appTabDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self else { return }
                guard let index = notification.userInfo?[FloatingHubWindowManager.tabIndexUserInfoKey] as? Int else {
                    return
                }
                self.isShelfTabActive = (index == 0)
                self.refresh()
            }
            .store(in: &cancellables)
    }

    private func refresh() {
        let updated = makeSnapshot()
        guard updated != snapshot else { return }
        snapshot = updated
    }

    private func makeSnapshot() -> Snapshot {
        var items: [FloatingHubItem] = []

        // Trợ lý AI: đang chạy **và** màn AI đang đóng — đúng điều kiện widget AI cũ.
        if aiState.isRunning && !aiState.isFullScreenPresented {
            items.append(FloatingHubItem(kind: .ai, detail: aiState.title))
        }

        // Trình duyệt: đang thu nhỏ và còn tab. Không badge số tab trên nút (người dùng chốt).
        let browser = browserReader.snapshot
        if browser.showReopenButton {
            items.append(FloatingHubItem(kind: .browser, detail: "\(browser.tabCount) tab"))
        }

        // Thông báo: có chưa đọc hoặc có tác vụ chạy, **và** không ở tab Kệ Sách.
        let inbox = inboxReader.snapshot
        var unreadCount = 0
        if inbox.shouldShowWidget && !isShelfTabActive {
            unreadCount = inbox.unreadCount
            items.append(FloatingHubItem(kind: .notifications, detail: Self.notificationDetail(unreadCount: unreadCount)))
        }

        return Snapshot(items: items, unreadCount: unreadCount)
    }

    /// Có chưa đọc thì ưu tiên con số (kể cả khi đồng thời có tác vụ chạy); không thì báo đang chạy tác vụ.
    private static func notificationDetail(unreadCount: Int) -> String {
        guard unreadCount > 0 else { return "Đang chạy tác vụ" }
        let count = unreadCount > 99 ? "99+" : "\(unreadCount)"
        return "\(count) chưa đọc"
    }
}
