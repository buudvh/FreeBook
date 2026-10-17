import Combine
import Foundation

/// Gộp ba nguồn (AI, thông báo, video phát nền) thành **một** snapshot cho nút hub nổi (1.3.524; 1.3.533 bỏ
/// trình duyệt, thêm Video).
///
/// ## Tập dòng cố định
/// `snapshot.items` **luôn** có đủ `FloatingHubItem.Kind.allCases`, đúng thứ tự. Điều kiện từng có/vắng của
/// một mục nay thành `isEnabled` (sáng/xám). Menu nhờ vậy không bao giờ thêm/bớt dòng — xem bất biến "hub
/// không vẽ lại" của plan đợt 2.
///
/// ## Một reader duy nhất
/// `FloatingHubWindowManager` sở hữu đúng **một** instance và tiêm vào container.
///
/// ## Hai tầng chống vẽ lại
/// - `Snapshot` chỉ phát khi giá trị **thật sự** đổi (`guard updated != snapshot`).
/// - Nút chỉ vẽ lại theo `ButtonState` (các mục đang hoạt động + số chưa đọc), **không** theo chữ hay trạng
///   thái phát của dòng. Tiêu đề AI đổi theo từng batch ("Đang quét: Batch N/T") chỉ chạm tới menu, và menu
///   chỉ vẽ khi đang mở.
///
/// ## Không observe cả `AIRuntimeCoordinator`
/// Coordinator ghi `activeSession` mỗi ≥ 50 ms khi stream. Observe cả object là kéo hub vẽ lại theo nhịp đó
/// (đúng lỗi của view widget AI cũ, xoá ở 1.3.524). Ở đây chỉ nghe đúng ba publisher cần. Video cũng vậy: chỉ
/// đọc cầu nối `VideoMiniPlayerState` (`ObservableObject`), không đọc session `@Observable` giữ `AVPlayer`.
@MainActor
final class FloatingHubPresentationReader: ObservableObject {
    /// Phần trạng thái mà **nút** cần. Cố ý không chứa chữ hay trạng thái phát của dòng.
    struct ButtonState: Equatable {
        /// Các mục đang hoạt động, theo thứ tự cố định. Số phần tử là badge của nút hub.
        var activeKinds: [FloatingHubItem.Kind] = []
        /// Số chưa đọc — bằng 0 khi mục Thông báo đang xám. Chỉ để chọn glyph chuông và đọc VoiceOver.
        var unreadCount = 0

        var activeCount: Int { activeKinds.count }
    }

    struct Snapshot: Equatable {
        /// Luôn đủ `Kind.allCases`, theo thứ tự hiển thị cố định.
        var items: [FloatingHubItem] = FloatingHubItem.Kind.allCases.map { FloatingHubItem(kind: $0) }
        /// Bằng 0 khi mục Thông báo đang xám.
        var unreadCount = 0

        var button: ButtonState {
            ButtonState(activeKinds: items.filter(\.isActive).map(\.kind), unreadCount: unreadCount)
        }
    }

    /// Trạng thái AI lấy từ **giá trị được phát ra** của ba publisher, không đọc lại property của coordinator.
    private struct AIState: Equatable {
        var isRunning = false
        var isFullScreenPresented = false
        var title = ""
    }

    /// Trạng thái video nền, cũng lấy từ giá trị được phát ra: `@Published` phát ở willSet nên đọc lại
    /// `VideoMiniPlayerState.shared` ngay trong sink là đọc giá trị **cũ**.
    private struct VideoState: Equatable {
        var isActive = false
        var title = ""
        var subtitle = ""
        var isPlaying = false
    }

    @Published private(set) var snapshot = Snapshot()

    private let inboxReader = NotificationInboxPresenceReader()
    private var aiState = AIState()
    private var videoState = VideoState()
    /// Tab Kệ Sách là tab 0 của `MainTabView`; mặc định `true` vì app luôn khởi động ở tab đó. Tab Kệ đã có
    /// nút chuông trên toolbar nên mục Thông báo **xám** ở đó (trước 1.3.533 là vắng hẳn).
    private var isShelfTabActive = true
    private var cancellables = Set<AnyCancellable>()

    init() {
        let coordinator = AIRuntimeCoordinator.shared
        aiState = AIState(
            isRunning: coordinator.isRunning,
            isFullScreenPresented: coordinator.isFullScreenPresented,
            title: coordinator.activeTaskTitle
        )
        let video = VideoMiniPlayerState.shared
        videoState = VideoState(
            isActive: video.isActive,
            title: video.title,
            subtitle: video.subtitle,
            isPlaying: video.isPlaying
        )
        snapshot = makeSnapshot()

        // `@Published` phát ở willSet ⇒ mọi sink đi qua `receive(on:)` rồi mới tính lại. Nhánh AI và Video dùng
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

        Publishers.CombineLatest4(video.$isActive, video.$title, video.$subtitle, video.$isPlaying)
            .receive(on: RunLoop.main)
            .sink { [weak self] isActive, title, subtitle, isPlaying in
                guard let self else { return }
                self.videoState = VideoState(
                    isActive: isActive,
                    title: title,
                    subtitle: subtitle,
                    isPlaying: isPlaying
                )
                self.refresh()
            }
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

    /// Dựng đủ ba dòng theo `Kind.allCases` — không nhánh nào được bỏ qua một loại.
    private func makeSnapshot() -> Snapshot {
        let inbox = inboxReader.snapshot
        // Thông báo **luôn** chạm được (mở sheet thông báo) và luôn có chấm đỏ khi còn tin chưa đọc. Chỉ việc tính
        // vào badge số của nút hub mới bỏ qua tab Kệ Sách (tab đó đã có nút chuông riêng).
        let notificationsActive = inbox.shouldShowWidget && !isShelfTabActive
        let unreadCount = notificationsActive ? inbox.unreadCount : 0

        let items = FloatingHubItem.Kind.allCases.map { kind -> FloatingHubItem in
            switch kind {
            case .ai:
                return aiItem()
            case .notifications:
                return FloatingHubItem(
                    kind: .notifications,
                    isEnabled: true,
                    detail: notificationDetail(inbox: inbox),
                    badgeCount: inbox.unreadCount,
                    isActive: notificationsActive
                )
            case .video:
                return videoItem()
            }
        }
        return Snapshot(items: items, unreadCount: unreadCount)
    }

    /// Trợ lý AI dùng được khi đang chạy **và** màn AI đang đóng — đúng điều kiện có mục trước đây.
    private func aiItem() -> FloatingHubItem {
        let title = aiState.title.isEmpty ? "Đang chạy" : aiState.title
        let usable = aiState.isRunning && !aiState.isFullScreenPresented
        return FloatingHubItem(
            kind: .ai,
            isEnabled: usable,
            detail: aiState.isRunning ? title : "Không có tác vụ",
            isActive: usable
        )
    }

    /// Video dùng được khi trình phát đã thu nhỏ mà vẫn còn phiên (`VideoMiniPlayerState.isActive`).
    private func videoItem() -> FloatingHubItem {
        guard videoState.isActive else {
            return FloatingHubItem(kind: .video, detail: "Không có video đang phát")
        }
        let fallback = videoState.isPlaying ? "Đang phát" : "Đã dừng"
        return FloatingHubItem(
            kind: .video,
            isEnabled: true,
            headline: videoState.title,
            detail: videoState.subtitle.isEmpty ? fallback : videoState.subtitle,
            isPlaying: videoState.isPlaying,
            isActive: true
        )
    }

    /// Có chưa đọc thì ưu tiên con số (kể cả khi đồng thời có tác vụ chạy); không thì báo đang chạy tác vụ; không có
    /// gì thì nói rõ là trống.
    private func notificationDetail(inbox: NotificationInboxPresenceReader.Snapshot) -> String {
        if inbox.unreadCount > 0 {
            let count = inbox.unreadCount > 99 ? "99+" : "\(inbox.unreadCount)"
            return "\(count) chưa đọc"
        }
        return inbox.hasRunningTask ? "Đang chạy tác vụ" : "Không có thông báo mới"
    }
}
