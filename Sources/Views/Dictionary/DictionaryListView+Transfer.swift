import SwiftUI

extension DictionaryListView {
    /// bookId dùng cho hướng Chung → Riêng.
    ///
    /// Ở danh sách Riêng thì chính là `bookId` của danh sách; ở danh sách Chung
    /// (`bookId == nil`) thì lấy `contextBookId` — truyện của màn Từ điển đang mở,
    /// truyền xuống từ `DictionaryHubView`. Không bao giờ lấy truyện đang phát TTS,
    /// truyện mở gần nhất hay bất kỳ nguồn "current book" toàn cục nào khác.
    var transferContextBookId: String? { bookId ?? contextBookId }

    /// COPY một entry sang phạm vi/loại khác. Nguồn không bị xoá hay sửa;
    /// key trùng ở đích bị ghi đè hoàn toàn (xem `DictionaryEntryTransferAction`).
    func copyEntry(_ entry: DictEntry, to destinationType: DictType, target: DictionaryTransferTarget) {
        Task { @MainActor in
            do {
                try await DictionaryEntryTransferAction.copy(
                    key: entry.key,
                    value: entry.value,
                    destinationType: destinationType,
                    target: target
                )
                let label = DictionaryEntryTransferAction.destinationLabel(
                    destinationType: destinationType,
                    target: target
                )
                ToastManager.shared.show(message: "Đã copy \(entry.key) → \(label)", type: .success)
            } catch {
                ToastManager.shared.show(message: "Lỗi copy: \(error.localizedDescription)", type: .error)
            }
        }
    }

    /// Chạm icon chuyển ở danh sách Chung khi không biết truyện hiện tại: không copy.
    func reportMissingTransferContext() {
        ToastManager.shared.show(
            message: "Không xác định được truyện hiện tại, không thể chuyển qua từ điển riêng",
            type: .error
        )
    }
}
