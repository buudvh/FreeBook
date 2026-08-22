import Combine

/// Cầu quan sát `ReaderViewModel` cho `ReaderView`.
///
/// `ReaderViewModel` là `ObservableObject`, nhưng `ReaderView` phải giữ nó trong `@State`
/// (view model chỉ tồn tại sau khi bootstrap mục lục xong nên không dùng được
/// `@StateObject`). `@State` **không** subscribe `objectWillChange`: nó chỉ giữ tham chiếu.
/// Hệ quả trước 1.3.243: mọi thay đổi `@Published` của view model — kể cả
/// `pendingNavigationIndex` và `navigationCommit`, hai giá trị mà cổng render đọc — **không**
/// làm `ReaderView` dựng lại body. Reader chỉ được vẽ lại nhờ những nguồn invalidate không
/// liên quan (publish của `ttsState`, một `@State` khác đổi, notification, `@Query`), nên
/// khoảng cách giữa cú bấm Next/Prev và frame đầu tiên bằng đúng khoảng chờ tới sự kiện
/// vô can kế tiếp — log thiết bị đo được 0.6–4.3 s, và đó là cảm giác "đơ" người dùng báo.
/// Đường chọn chương từ danh sách không bị vì việc đóng sheet tự tạo ra một chuỗi pass.
///
/// Relay này là `@StateObject` của `ReaderView` và forward `objectWillChange` của view model
/// sang chính nó — đúng cơ chế `@ObservedObject` dùng, chỉ khác là chịu được `nil` và đổi
/// instance. Không lọc theo từng thuộc tính: danh sách `@Published` phải quan tâm là thứ dễ
/// quên khi thêm state mới, mà đó chính là loại bug này.
///
/// Không liên quan tới `ReaderViewModelObserver` (một wrapper view `@ObservedObject` chưa
/// từng có caller, đã xoá ở 1.3.235): nó bọc content nên phải nắm `self` của `ReaderView`
/// trong closure, còn relay này chỉ đứng ngoài phát tín hiệu invalidate.
@available(iOS 17.0, *)
@MainActor
final class ReaderViewModelInvalidationRelay: ObservableObject {
    private var cancellable: AnyCancellable?
    /// So sánh identity để `observe(_:)` idempotent — gọi lại với cùng instance (mỗi lần
    /// bootstrap chạy lại) không tạo thêm subscription.
    private weak var observed: ReaderViewModel?

    func observe(_ viewModel: ReaderViewModel?) {
        guard let viewModel else {
            cancellable = nil
            observed = nil
            return
        }
        guard observed !== viewModel else { return }
        observed = viewModel
        cancellable = viewModel.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }
}
