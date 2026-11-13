import Foundation
import Observation
import SwiftData

/// Nguồn sự thật **duy nhất** cho số liệu màn Dung lượng (1.3.730).
///
/// - Giữ lần đo gần nhất, lưu xuống máy (`UserDefaults` `storageUsageLastSnapshot`). Mở màn là hiện ngay số cũ kèm giờ
///   đo, rồi đo lại ngầm; chỉ lần đầu tiên (chưa có số cũ) mới phải chờ.
/// - Lượt đo là `Task` của repository, **không** gắn vòng đời màn: thoát màn giữa chừng vẫn đo tiếp và lưu kết quả,
///   lần vào sau thấy số mới. Đang đo thì gọi `refresh()` thêm là bỏ qua (không đo chồng).
/// - Xoá xong (`refreshAfterChange()`) thì chờ lượt đang chạy rồi đo thêm một lượt mới, để số sau khi xoá là số thật.
/// - Mỗi lượt đo gồm cả lượt quét rác (`JunkScanner`, trạng thái bận chụp trên main + `bookId` đọc từ `container` ngoài
///   main) ⇒ dòng "Dọn rác" và dòng "Không còn dùng" của loại TTS cùng số với trang Dọn rác.
@MainActor
@Observable
final class StorageUsageRepository {
    static let shared = StorageUsageRepository()

    private static let defaultsKey = "storageUsageLastSnapshot"

    /// Lần đo gần nhất (có thể từ lần chạy app trước); `nil` ⇒ chưa đo lần nào.
    private(set) var snapshot: StorageUsageSnapshot? = nil
    private(set) var isScanning = false
    @ObservationIgnored private var scanTask: Task<Void, Never>? = nil
    /// Container của thư viện (màn truyền vào) — để quét "dữ liệu của truyện đã xoá"; chưa có ⇒ bỏ nhóm đó.
    @ObservationIgnored private var container: ModelContainer? = nil

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey) {
            snapshot = try? JSONDecoder().decode(StorageUsageSnapshot.self, from: data)
        }
    }

    /// Đo lại ngầm (nhớ `container` cho các lượt sau). Gọi khi mở màn và khi bấm ↻.
    func refresh(container: ModelContainer) {
        self.container = container
        refresh()
    }

    /// Đo lại ngầm nếu chưa có lượt nào đang chạy.
    func refresh() {
        guard scanTask == nil else { return }
        isScanning = true
        let container = self.container
        scanTask = Task { [weak self] in
            let inputs = await JunkCleanupCoordinator.captureInputs(container: container)
            let result = await Task.detached(priority: .utility) {
                StorageUsageScanner.scan(junk: JunkScanner.scan(inputs))
            }.value
            self?.apply(result)
        }
    }

    /// Sau khi xoá: chờ lượt đang chạy (nó có thể đã đo trước lúc xoá) rồi đo một lượt mới và chờ xong.
    func refreshAfterChange() async {
        await scanTask?.value
        refresh()
        await scanTask?.value
    }

    private func apply(_ result: StorageUsageSnapshot) {
        snapshot = result
        isScanning = false
        scanTask = nil
        if let data = try? JSONEncoder().encode(result) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}
