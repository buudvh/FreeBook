import SwiftUI

/// Trình bày `HubStyleActionSheet` khi `request` có giá trị (đặt lại `nil` ngay khi nhận):
///
/// - Bình thường qua `OverlaySheetPresenter` ⇒ sheet nằm **trên** mọi viên thuốc (đĩa nghe, hub, nút trình duyệt) — viên
///   thuốc không bị ẩn, chỉ nằm dưới lớp mờ, không bấm được để mở chồng sheet khác.
/// - Không trình bày được (đang có sheet phủ khác / chưa có scene) ⇒ lùi về sheet thường của màn này (nằm dưới viên thuốc).
/// - Chạm một dòng ⇒ đóng sheet **xong** mới chạy `action` của dòng (trình bày từ sheet đang đóng thì UIKit bỏ màn mới).
struct HubStyleActionSheetModifier: ViewModifier {
    @Binding var request: HubStyleActionSheetContent?

    @State private var fallback: HubStyleActionSheetContent?
    @State private var pendingAction: (@MainActor () -> Void)?

    func body(content: Content) -> some View {
        content
            .onChange(of: request?.id) { _, newID in
                guard newID != nil, let sheet = request else { return }
                request = nil
                present(sheet)
            }
            .sheet(item: $fallback, onDismiss: runPendingAction) { sheet in
                HubStyleActionSheet(content: sheet) { item in
                    guard fallback != nil else { return }
                    pendingAction = item.action
                    fallback = nil
                }
            }
    }

    private func present(_ sheet: HubStyleActionSheetContent) {
        let shown = OverlaySheetPresenter.shared.present {
            HubStyleActionSheet(content: sheet) { item in
                OverlaySheetPresenter.shared.dismiss(then: item.action)
            }
        }
        guard !shown else { return }
        AppLogger.shared.log("[HubStyleSheet] Không trình bày được trên viên thuốc — dùng sheet thường: \(sheet.title)")
        pendingAction = nil
        fallback = sheet
    }

    private func runPendingAction() {
        let action = pendingAction
        pendingAction = nil
        action?()
    }
}

extension View {
    /// Gắn sheet hành động kiểu hub: gán `request` ⇒ sheet hiện (xem `HubStyleActionSheetModifier`).
    func hubStyleActionSheet(_ request: Binding<HubStyleActionSheetContent?>) -> some View {
        modifier(HubStyleActionSheetModifier(request: request))
    }
}
