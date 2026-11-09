import Combine
import Foundation

/// Trạng thái kiểu **Thanh nghe nhạc** của widget TTS (1.3.796): thu gọn hay bung và các nút điều khiển. Container
/// (`TTSWidgetBarContainerViewController`) đặt khung theo `isCollapsed`; vị trí **cố định** (1.3.799 — không kéo dọc, không
/// lưu chỗ; khoá cũ `ttsWidgetBarBottomGap` / `ttsWidgetBarPillBottomGap` bỏ qua).
///
/// ## Thu gọn
/// - Hiển thị thu gọn = người dùng chọn thu (`userCollapsed`, **nhớ** qua khoá `ttsWidgetBarCollapsed`) **hoặc** Reader đang
///   hiện mà bật "Thu gọn khi mở Reader" (`readerForcedCollapse`, **không** nhớ). Ra khỏi Reader thì cờ Reader tắt ⇒ về lại
///   đúng lựa chọn trước đó (đang bung thì bung lại). Trong Reader không có viên (1.3.806): thu gọn = nút đĩa TTS của Reader
///   (chạm mở sheet điều khiển nhanh, không bung thanh); bấm tai nghe bắt đầu đọc cũng giữ thu gọn (`revealRequested`).
/// - "Tự thu gọn sau 5 giây": đang bung mà 5 giây không chạm nút nào / không vuốt ⇒ thu (tính như người dùng thu). Đang mở
///   sheet Hẹn giờ thì không đếm, đóng sheet đếm lại từ đầu.
@MainActor
final class TTSWidgetBarViewModel: ObservableObject {
    nonisolated static let collapsedKey = "ttsWidgetBarCollapsed"
    nonisolated static let autoCollapseDelay: UInt64 = 5_000_000_000

    @Published private(set) var isCollapsed: Bool {
        didSet { TTSWidgetBarPresence.shared.updateBarCollapsed(isCollapsed) }
    }
    /// Reader đang hiện (1.3.806): thu gọn thì container **ẩn** viên nép mép (Reader có nút đĩa TTS thay), bung thì thanh hạ
    /// xuống sát đáy (Reader chừa chỗ theo `TTSWidgetBarPresence.readerBottomInset`).
    @Published private(set) var isReaderVisible: Bool
    /// Sheet Hẹn giờ (`TTSQuickTimerSheet`) — gắn ở gốc nội dung nên thu/bung không làm mất sheet.
    @Published var isTimerSheetPresented = false {
        didSet {
            guard oldValue != isTimerSheetPresented else { return }
            if isTimerSheetPresented {
                autoCollapseTask?.cancel()
            } else {
                restartAutoCollapseTimer()
            }
        }
    }

    /// Đang vuốt ngang thanh (container không đặt lại khung, không đếm 5 giây).
    private(set) var isDragging = false

    private var userCollapsed: Bool
    private var readerForcedCollapse = false
    private var autoCollapseTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private let preferences = TTSWidgetPreferences.shared
    private let ttsManager = TTSManager.shared

    init() {
        let defaults = UserDefaults.standard
        let collapsed = defaults.bool(forKey: Self.collapsedKey)
        // Đọc cờ Reader ngay (không chờ lượt phát của publisher) — widget thường được dựng lúc bấm nghe **trong** Reader,
        // chờ thì thanh hiện bung rồi mới co lại.
        let readerVisible = ReaderPresenceTracker.shared.isReaderVisible
        let forced = readerVisible && TTSWidgetPreferences.shared.collapsesInReader
        userCollapsed = collapsed
        readerForcedCollapse = forced
        isCollapsed = collapsed || forced
        isReaderVisible = readerVisible
        // `didSet` không chạy trong `init` ⇒ báo cầu nối lần đầu bằng tay.
        TTSWidgetBarPresence.shared.updateBarCollapsed(collapsed || forced)

        // `@Published` phát ở willSet ⇒ dùng giá trị được phát ra.
        ReaderPresenceTracker.shared.$isReaderVisible
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] visible in
                self?.handleReaderVisibility(visible)
            }
            .store(in: &cancellables)

        preferences.$collapsesInReader
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                guard let self, !enabled, self.readerForcedCollapse else { return }
                self.readerForcedCollapse = false
                self.publishCollapsed()
            }
            .store(in: &cancellables)

        preferences.$autoCollapse
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.restartAutoCollapseTimer()
            }
            .store(in: &cancellables)

        restartAutoCollapseTimer()
    }

    // MARK: - Thu gọn / bung

    /// Nút », vuốt thanh sang ngang, hoặc hết 5 giây không chạm.
    func collapseByUser() {
        autoCollapseTask?.cancel()
        setUserCollapsed(true)
    }

    /// Window manager yêu cầu mở rộng (Reader bấm tai nghe bắt đầu đọc — `requestRevealOnNextShow`). Đang trong Reader mà
    /// bật "Thu gọn khi mở Reader" ⇒ giữ thu gọn (Reader hiện nút đĩa TTS); còn lại bung như chạm đĩa của viên.
    func revealRequested() {
        if isReaderVisible, preferences.collapsesInReader {
            restartAutoCollapseTimer()
            return
        }
        expandByUser()
    }

    /// Chạm đĩa của viên thu gọn (ngoài Reader). Trong Reader thì bỏ cờ thu gọn của Reader tới khi rời Reader.
    func expandByUser() {
        readerForcedCollapse = false
        setUserCollapsed(false)
        restartAutoCollapseTimer()
    }

    private func setUserCollapsed(_ collapsed: Bool) {
        if userCollapsed != collapsed {
            userCollapsed = collapsed
            UserDefaults.standard.set(collapsed, forKey: Self.collapsedKey)
        }
        publishCollapsed()
    }

    private func handleReaderVisibility(_ visible: Bool) {
        if visible != isReaderVisible { isReaderVisible = visible }
        let forced = visible && preferences.collapsesInReader
        guard forced != readerForcedCollapse else { return }
        readerForcedCollapse = forced
        publishCollapsed()
        restartAutoCollapseTimer()
    }

    private func publishCollapsed() {
        let collapsed = userCollapsed || readerForcedCollapse
        guard collapsed != isCollapsed else { return }
        isCollapsed = collapsed
        if collapsed { autoCollapseTask?.cancel() }
    }

    // MARK: - Tự thu gọn sau 5 giây

    /// Mọi lần chạm nút / kéo thả trên thanh: đếm lại 5 giây.
    func noteInteraction() {
        restartAutoCollapseTimer()
    }

    private func restartAutoCollapseTimer() {
        autoCollapseTask?.cancel()
        autoCollapseTask = nil
        guard preferences.autoCollapse, !isCollapsed, !isDragging, !isTimerSheetPresented else { return }
        autoCollapseTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.autoCollapseDelay)
            guard !Task.isCancelled, let self else { return }
            guard !self.isCollapsed, !self.isDragging, !self.isTimerSheetPresented,
                  self.preferences.autoCollapse else { return }
            self.collapseByUser()
        }
    }

    // MARK: - Vuốt ngang để thu gọn

    func beginDrag() {
        isDragging = true
        autoCollapseTask?.cancel()
    }

    /// Thả tay sau khi vuốt ngang (container tự quyết thu gọn hay trượt về).
    func endDrag() {
        isDragging = false
        restartAutoCollapseTimer()
    }

    // MARK: - Điều khiển TTS

    func togglePlayback() {
        if ttsManager.isPlaying {
            ttsManager.pause()
        } else {
            ttsManager.resume()
        }
        noteInteraction()
    }

    /// ⏭ = sang đoạn kế (như capsule của kiểu Đĩa nổi).
    func skipForward() {
        ttsManager.skipForward()
        noteInteraction()
    }

    func presentTimerSheet() {
        isTimerSheetPresented = true
    }

    func stop() {
        autoCollapseTask?.cancel()
        ttsManager.stop()
    }

    /// Chạm bìa / chữ của thanh ⇒ mở chương đang đọc (cùng kênh với bìa capsule và sheet Hẹn giờ).
    func openCurrentChapter() {
        noteInteraction()
        NotificationCenter.default.post(name: NSNotification.Name("openCurrentlyPlayingReader"), object: nil)
    }
}
