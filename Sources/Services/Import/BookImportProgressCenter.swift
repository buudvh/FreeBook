import Combine
import Foundation

/// Tiến độ của **lượt nhập truyện từ file đang chạy** — nguồn sự thật duy nhất cho hai người vẽ: overlay
/// chờ của màn Kệ sách và khối "Đang chạy" của màn Thông báo.
///
/// ## Vì sao không còn là `@State` của `ShelfView`
/// Trước 1.3.557 bốn biến `isImporting` / `importIsIndeterminate` / `importProgress` / `importStatusText`
/// sống trong `ShelfView`, nên chỉ overlay của Kệ sách đọc được. Màn Thông báo (mở cả từ nút chuông lẫn từ
/// hub nổi, là một cửa sổ khác) cần đọc cùng tiến độ đó, nên trạng thái phải ra khỏi View. Đổi lại,
/// `ShelfView` **không** observe lớp này — overlay là struct riêng tự observe — nên cả kệ không vẽ lại theo
/// mỗi nhịp tiến độ.
///
/// ## Chỉ giữ lượt đang chạy
/// Xong hay lỗi thì `entry` về `nil` ngay: kết quả đã có toast ("Đã nhập thành công" / "Lỗi …") và toast tự
/// ghi vào nhật ký của màn Thông báo, nên không cần thêm dòng kết quả với nút "Bỏ qua".
///
/// Lớp này **không** chạy việc nhập (`ShelfView+BookImport.swift` vẫn điều phối) và không hiện toast
/// (luật `SERVICE_TOAST_COUPLING`).
@MainActor
final class BookImportProgressCenter: ObservableObject {
    static let shared = BookImportProgressCenter()

    /// Một lượt nhập. `fraction == nil` nghĩa là chưa biết phần trăm (đang tạo sách, dịch tên chương, ghi
    /// xuống đĩa) — người vẽ hiện thanh/vòng chạy vô định, cùng quy ước `ModelDownloadCenter.Entry`.
    struct Entry: Equatable {
        let title: String
        var message: String
        var fraction: Double?
    }

    @Published private(set) var entry: Entry?

    private init() {}

    var isRunning: Bool { entry != nil }

    func begin(title: String, message: String) {
        entry = Entry(title: title, message: message, fraction: nil)
    }

    /// Không có lượt nào đang chạy thì bỏ qua — tránh một nhịp tiến độ muộn dựng lại dòng đã kết thúc.
    func update(message: String, fraction: Double?) {
        guard var current = entry else { return }
        current.message = message
        current.fraction = fraction
        entry = current
    }

    func end() {
        entry = nil
    }
}
