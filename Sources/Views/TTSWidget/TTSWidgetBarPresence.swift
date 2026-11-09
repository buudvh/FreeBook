import Combine
import CoreGraphics
import Foundation

/// Cầu nối nhỏ giữa kiểu **Thanh nghe nhạc** của widget TTS (cửa sổ nổi riêng) và Reader (1.3.806).
///
/// Reader không đọc thẳng `TTSWidgetBarViewModel` (nó thuộc container của cửa sổ, dựng/huỷ theo kiểu widget) cũng không
/// observe `TTSManager` (vẽ lại theo từng đoạn). Type này gộp ba nguồn thành hai cờ chỉ đổi khi thanh thu/bung, widget
/// hiện/ẩn hoặc đổi kiểu:
/// - `showsReaderDisc`: thanh đang **thu gọn** ⇒ trong Reader không có viên nép mép (container ẩn nó), thay bằng nút đĩa
///   TTS ngay trên nút tai nghe (`ReaderTTSDiscButton`), chạm mở `TTSQuickControlSheet`.
/// - `readerBottomInset`: thanh đang **bung** trong Reader (tắt "Thu gọn khi mở Reader") ⇒ thanh nằm sát đáy
///   (`readerBarBottomGap`), Reader chừa đúng chừng này ở đáy để chữ truyện và nút tai nghe đứng trên thanh, không bị che.
///
/// Hai cờ chỉ có nghĩa **khi Reader đang hiện** — ngoài Reader thanh đứng chỗ cũ trên `MainTabBar`, viên nép mép như cũ.
/// `barIsCollapsed` do `TTSWidgetBarViewModel` ghi; kiểu Đĩa nổi (không có view model thanh) ⇒ cả hai cờ tắt nhờ `style`.
@MainActor
final class TTSWidgetBarPresence: ObservableObject {
    static let shared = TTSWidgetBarPresence()

    /// Khe giữa mép dưới thanh và mép dưới vùng an toàn khi thanh bung trong Reader.
    nonisolated static let readerBarBottomGap: CGFloat = 6
    /// Khe giữa mép trên thanh và mép dưới vùng chữ của Reader.
    nonisolated static let readerContentGap: CGFloat = 4

    @Published private(set) var showsReaderDisc = false
    @Published private(set) var readerBottomInset: CGFloat = 0

    private var barIsCollapsed = true
    private var isWidgetVisible = false
    private var isBarStyle = false
    private var cancellables = Set<AnyCancellable>()

    private init() {
        // `@Published` phát ở willSet ⇒ dùng giá trị được phát ra, không đọc lại `shared`.
        TTSFloatingWidgetWindowManager.shared.$isWidgetActuallyVisible
            .removeDuplicates()
            .sink { [weak self] visible in
                self?.isWidgetVisible = visible
                self?.recompute()
            }
            .store(in: &cancellables)
        TTSWidgetPreferences.shared.$style
            .removeDuplicates()
            .sink { [weak self] style in
                self?.isBarStyle = style == .bar
                self?.recompute()
            }
            .store(in: &cancellables)
    }

    /// `TTSWidgetBarViewModel` báo trạng thái thu gọn **hiển thị** (người dùng thu hoặc Reader ép thu).
    func updateBarCollapsed(_ collapsed: Bool) {
        guard barIsCollapsed != collapsed else { return }
        barIsCollapsed = collapsed
        recompute()
    }

    private func recompute() {
        let active = isBarStyle && isWidgetVisible
        let disc = active && barIsCollapsed
        if disc != showsReaderDisc { showsReaderDisc = disc }
        let inset: CGFloat = active && !barIsCollapsed
            ? MiniPlayerBarChrome.height + Self.readerBarBottomGap + Self.readerContentGap
            : 0
        if inset != readerBottomInset { readerBottomInset = inset }
    }
}
