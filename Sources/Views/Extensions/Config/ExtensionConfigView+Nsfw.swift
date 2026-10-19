import SwiftUI

/// Dòng **Nội dung 18+** của nhóm "Duyệt và lịch sử": bộ chọn 3 trạng thái ánh xạ `Extension.nsfwOverride`
/// — "Tự động (Có|Không)" = `nil`, "Có" = `true`, "Không" = `false`.
///
/// Lưu **ngay** qua `ExtensionTransactionCoordinator.setNsfwOverride`. Lựa chọn của người dùng thắng nhận diện tự động
/// và không mất khi cập nhật tiện ích. Đánh dấu kéo theo: ẩn khi công tắc NSFW tắt, nhãn 18+ trên icon, mặc định
/// không lưu lịch sử (nếu chưa tự chọn).
///
/// Nhãn "Tự động (…)" là kết quả **nhận diện tự động** (`ExtensionNsfwClassifier` trên bản sao đã bỏ override), nên
/// người dùng thấy trước bỏ đánh dấu thì tiện ích rơi về trạng thái nào.
extension ExtensionConfigView {
    /// Tag của Picker — enum thay `Bool?` để không vướng bẫy tag `Optional` không khớp kiểu (chọn mà không ăn).
    enum NsfwChoice: Hashable {
        case automatic
        case marked
        case unmarked

        init(overrideValue: Bool?) {
            switch overrideValue {
            case .some(true): self = .marked
            case .some(false): self = .unmarked
            case .none: self = .automatic
            }
        }

        var overrideValue: Bool? {
            switch self {
            case .automatic: return nil
            case .marked: return true
            case .unmarked: return false
            }
        }
    }

    internal var nsfwPicker: some View {
        Picker("Nội dung 18+", selection: nsfwChoiceBinding) {
            Text("Tự động (\(autoDetectedNsfw ? "Có" : "Không"))").tag(NsfwChoice.automatic)
            Text("Có").tag(NsfwChoice.marked)
            Text("Không").tag(NsfwChoice.unmarked)
        }
        .pickerStyle(.menu)
    }

    /// Kết quả nhận diện khi **không** có lựa chọn của người dùng (cờ tiện ích tự khai hoặc tên, mô tả, tên miền).
    private var autoDetectedNsfw: Bool {
        var probe = current
        probe.nsfwOverride = nil
        return ExtensionNsfwClassifier.isNsfw(probe)
    }

    /// Như `savesHistoryBinding`: chụp giá trị trong lượt vẽ, ghi qua `MainActor.assumeIsolated`.
    private var nsfwChoiceBinding: Binding<NsfwChoice> {
        let choice = NsfwChoice(overrideValue: current.nsfwOverride)
        let packageId = ext.packageId
        let name = current.name
        return Binding(
            get: { choice },
            set: { newChoice in
                guard newChoice != choice else { return }
                let overrideValue = newChoice.overrideValue
                MainActor.assumeIsolated { Self.saveNsfwOverride(packageId: packageId, name: name, overrideValue) }
            }
        )
    }

    internal var nsfwFooter: String {
        "Nội dung 18+ «Tự động» theo khai báo của tiện ích hoặc tên, mô tả, tên miền. Tiện ích 18+ bị ẩn khi tắt NSFW "
            + "trong Cài đặt và có nhãn 18+ trên icon."
    }

    @MainActor
    static func saveNsfwOverride(packageId: String, name: String, _ value: Bool?) {
        switch ExtensionTransactionCoordinator.shared.setNsfwOverride(packageId: packageId, value) {
        case .success:
            let note = value.map { $0 ? "đánh dấu 18+" : "bỏ đánh dấu 18+" } ?? "dùng nhận diện tự động"
            AppLogger.shared.log("🔞 [ExtConfig] \(name): \(note)")
        case .failure(let err):
            AppLogger.shared.log("❌ [ExtConfig] Lỗi lưu đánh dấu 18+ của \(name): \(err.localizedDescription)")
            ToastManager.shared.show(message: "Không lưu được đánh dấu 18+: \(err.localizedDescription)", type: .error)
        }
    }
}
