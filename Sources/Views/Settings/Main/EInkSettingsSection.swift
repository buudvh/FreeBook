import SwiftUI

/// Mục Cài đặt cho chế độ E-Ink. Chỉ có **1** type top level (MULTI_PRIMARY_TYPES), không đụng SwiftData
/// (`Services`/`Views` đều cấm), và truyền mọi lượt ghi qua `EInkModeSettings` singleton — cách duy nhất
/// giữ cả hai luồng đọc đồng bộ: `ReaderViewModel`/`ReaderView` đọc singleton, còn `BookCoverView`/
/// `ExtensionIconView` đọc cùng khoá qua `@AppStorage`. Singleton ghi vào `UserDefaults` nên `@AppStorage`
/// tự cập nhật theo, không cần observe riêng.
struct EInkSettingsSection: View {
    @ObservedObject private var eink = EInkModeSettings.shared

    var body: some View {
        Section(header: Text("Chế Độ E-Ink")) {
            Toggle(isOn: Binding(
                get: { eink.isEnabled },
                set: { EInkModeSettings.shared.setEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Chế độ E-Ink")
                        .font(.body)
                        .fontWeight(.medium)
                    Text("Tối ưu cho màn hình giấy điện tử: chỉ đen/trắng, viền thay bóng, lật chương tức thì, bỏ hiệu ứng nền mờ.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if eink.isEnabled {
                Toggle("Bìa sách thang xám", isOn: Binding(
                    get: { eink.monochromeCovers },
                    set: { EInkModeSettings.shared.setMonochromeCovers($0) }
                ))

                Toggle("Ẩn hoàn toàn bìa sách", isOn: Binding(
                    get: { eink.hideCovers },
                    set: { EInkModeSettings.shared.setHideCovers($0) }
                ))

                Toggle("Lật chương tức thì (không animation)", isOn: Binding(
                    get: { eink.instantChapterTurn },
                    set: { EInkModeSettings.shared.setInstantChapterTurn($0) }
                ))

                Toggle("Hiện nút làm mới màn hình", isOn: Binding(
                    get: { eink.showsRefreshButton },
                    set: { EInkModeSettings.shared.setShowsRefreshButton($0) }
                ))

                Button(action: { EInkRefreshOverlay.shared.flash() }) {
                    Label("Làm mới màn hình ngay", systemImage: "arrow.clockwise")
                }

                Text("Đổi chế độ có thể cần mở lại màn hình để thanh điều hướng/tab bar áp diện mạo mới (appearance proxy của UIKit không retroactive).")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}
