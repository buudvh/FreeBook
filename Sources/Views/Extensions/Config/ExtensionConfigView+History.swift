import SwiftUI

/// Nhóm **Duyệt và lịch sử** của màn Cấu hình tiện ích: công tắc "Lưu lịch sử đọc/xem" + bộ chọn "Nội dung 18+"
/// (`ExtensionConfigView+Nsfw`).
///
/// Công tắc hiển thị `savesHistory ?? !isNsfw` (đúng luật của `ExtensionHistoryPolicy`, không tự tính lại) và lưu
/// **ngay** khi bấm qua `ExtensionTransactionCoordinator.setSavesHistory` — không đi qua `configJson` (chuỗi đó bị
/// tiêm thành biến global của JS).
///
/// Tắt chỉ chặn **ghi mới** vào Lịch sử: lịch sử cũ giữ nguyên; tiến độ đọc của sách trên kệ vẫn được lưu.
///
/// Chỉ hiện với tiện ích **nội dung** (chữ/tranh/video) đã cài — mockup đã duyệt: tiện ích TTS, dịch… không có nhóm
/// này (không tạo sách nên không có lịch sử). Đánh dấu 18+ cho các tiện ích đó vẫn làm được ở menu nhấn giữ của Kho.
extension ExtensionConfigView {
    @ViewBuilder
    internal var browsingAndHistorySection: some View {
        if current.isInstalled, SearchExtensionScopePolicy.isBrowsable(current) {
            Section {
                Toggle("Lưu lịch sử đọc/xem", isOn: savesHistoryBinding)
                nsfwPicker
            } header: {
                Text("Duyệt và lịch sử")
            } footer: {
                Text(historyFooter + " " + nsfwFooter)
            }
        }
    }

    /// Đọc trạng thái **trong lượt vẽ** (bảng tiện ích là `@Observable` nên ghi xong là vẽ lại); closure chỉ giữ giá
    /// trị đã chụp, không chạm singleton `@MainActor` từ ngữ cảnh không cô lập.
    private var savesHistoryBinding: Binding<Bool> {
        let isOn = ExtensionHistoryPolicy.recordsHistory(for: current)
        let packageId = ext.packageId
        let name = current.name
        return Binding(
            get: { isOn },
            set: { value in
                MainActor.assumeIsolated { Self.saveSavesHistory(packageId: packageId, name: name, value) }
            }
        )
    }

    private var historyFooter: String {
        let defaultNote = ExtensionNsfwClassifier.isNsfw(current)
            ? "Mặc định tắt vì tiện ích là 18+."
            : "Mặc định bật."
        return "Tắt lưu lịch sử thì truyện/phim xem bằng tiện ích này không được ghi mới vào Lịch sử; lịch sử cũ giữ "
            + "nguyên, truyện trên kệ vẫn nhớ vị trí đọc. " + defaultNote
    }

    @MainActor
    private static func saveSavesHistory(packageId: String, name: String, _ value: Bool) {
        switch ExtensionTransactionCoordinator.shared.setSavesHistory(packageId: packageId, value) {
        case .success:
            AppLogger.shared.log("🗂️ [ExtConfig] \(name): \(value ? "bật" : "tắt") lưu lịch sử đọc/xem")
        case .failure(let err):
            AppLogger.shared.log("❌ [ExtConfig] Lỗi lưu công tắc lịch sử của \(name): \(err.localizedDescription)")
            ToastManager.shared.show(message: "Không lưu được công tắc lịch sử: \(err.localizedDescription)", type: .error)
        }
    }
}
