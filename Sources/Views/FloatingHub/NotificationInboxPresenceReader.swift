import Combine
import Foundation

/// Nguồn của mục **"Thông báo"** trên nút hub nổi (`FloatingHubPresentationReader`): số thông báo chưa đọc
/// và số tác vụ nền đang chạy / đang chờ. Trước 1.3.524 lớp này là presentation reader của widget thông báo nổi
/// riêng; logic giữ nguyên, chỉ đổi tên theo chủ mới.
///
/// ## Vì sao phải có lớp đọc riêng
/// Hub là một `UIWindow` sống suốt phiên. Nếu cửa sổ đó observe thẳng `NotificationInboxManager`,
/// `NewChapterInboxManager`, `BackupCoordinator`, `ModelDownloadCenter`, `DownloadManager`,
/// `BookImportProgressCenter`, `DictionaryMergeTask` và `RephoneticizeTask` thì **mỗi nhịp tiến độ** đều kéo cả cây
/// view của hub vẽ lại — trong khi thứ hub quan tâm chỉ là **số** tác vụ, đổi vài lần mỗi lượt. Lớp này gộp các nguồn
/// thành **một** snapshot và chỉ phát khi giá trị **thật sự** đổi (cùng khuôn `VisibleBrowserPresentationReader`,
/// `TTSPlayStateReader`). Thanh tiến độ ở sheet hub do `FloatingHubActivitySection` tự observe, chỉ lúc sheet mở.
///
/// ## Quy tắc có mục (người dùng chốt 2026-10-07)
/// Có mục khi **có thông báo chưa đọc** *hoặc* **đang có tác vụ chạy / chờ** (sao lưu / khôi phục / tải model /
/// tải, xuất, nhập truyện — ba việc sau thêm ở 1.3.557; gộp VietPhrase / phiên âm lại thêm ở 1.3.967).
/// Vế thứ hai có lý do rõ ràng: màn Thông báo là nơi xem đủ thanh tiến độ, nên nếu mục chỉ có theo số chưa đọc thì
/// một lượt khôi phục dài chạy nền sẽ không có lối vào nào.
@MainActor
final class NotificationInboxPresenceReader: ObservableObject {
    struct Snapshot: Equatable {
        var unreadCount = 0
        /// Tác vụ nền đang chạy / đang chờ (`FloatingHubActivity.counts()`, 1.3.967).
        var runningCount = 0
        var pendingCount = 0

        var hasRunningTask: Bool { runningCount + pendingCount > 0 }
        var shouldShowWidget: Bool { unreadCount > 0 || hasRunningTask }
    }

    @Published private(set) var snapshot = Snapshot()

    private var cancellables = Set<AnyCancellable>()

    init() {
        snapshot = Self.makeSnapshot()

        let inbox = NotificationInboxManager.shared
        let chapters = NewChapterInboxManager.shared
        let backup = BackupCoordinator.shared
        let downloads = ModelDownloadCenter.shared

        inbox.$records
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        chapters.$records
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        backup.$progress
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        downloads.$entries
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        // `$tasks` phát ~10 lần/giây mỗi tác vụ đang chạy: rút về số đang chạy / đang chờ rồi `removeDuplicates` trước khi
        // sink, để `refresh()` chỉ chạy lúc chuyển trạng thái. Vẫn `receive(on:)` vì `@Published` phát ở willSet —
        // `makeSnapshot()` đọc đồng bộ thì còn thấy giá trị cũ.
        DownloadManager.shared.$tasks
            .map { tasks in
                [tasks.filter { $0.status == .running }.count, tasks.filter { $0.status == .pending }.count]
            }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        BookImportProgressCenter.shared.$entry
            .map { $0 != nil }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        // Gộp VietPhrase / phiên âm lại (1.3.967): `phase` đổi theo từng % ⇒ rút về một bit "đang chạy".
        Publishers.Merge3(
            DictionaryMergeTask.shared.$phase
                .map { phase -> Bool in
                    if case .running = phase { return true }
                    return false
                }
                .removeDuplicates(),
            RephoneticizeTask.nghiTTS.$phase
                .map { phase -> Bool in
                    if case .running = phase { return true }
                    return false
                }
                .removeDuplicates(),
            RephoneticizeTask.vieNeu.$phase
                .map { phase -> Bool in
                    if case .running = phase { return true }
                    return false
                }
                .removeDuplicates()
        )
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
    }

    private func refresh() {
        let updated = Self.makeSnapshot()
        guard updated != snapshot else { return }
        snapshot = updated
    }

    private static func makeSnapshot() -> Snapshot {
        let counts = FloatingHubActivity.counts()
        return Snapshot(
            unreadCount: NotificationInboxManager.shared.unreadCount
                + NewChapterInboxManager.shared.totalNewBooks,
            runningCount: counts.running,
            pendingCount: counts.pending
        )
    }
}
