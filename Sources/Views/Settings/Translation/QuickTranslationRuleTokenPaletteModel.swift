import SwiftUI

/// Trạng thái của **thao tác quản lý token** mở từ bảng token ở màn sửa rule (1.3.1063, anh Bửu: "thêm nút + ở phần tùy
/// chọn để thêm token mới", "nhấn giữ các token, kể cả token cố định sẽ hiện thị ra các option quản lý danh sách từ (nếu
/// có), bật/tắt token, xóa (đối với token tùy chọn)").
///
/// Bảng token nằm **trong một hàng `Form`** (lazy) nên không tự gắn được `navigationDestination` / `sheet` một cách chắc
/// chắn; nó chỉ ghi ý định vào đây, còn `QuickTranslationRuleTokenPaletteManagement` gắn ở `Form` của sheet sửa rule
/// mới đẩy trang / mở sheet / hỏi xoá. `revision` tăng sau mọi thay đổi (bật / tắt, thêm, xoá, quay về từ trang danh
/// sách) — bảng token đọc nó trong `body` để vẽ lại, vì hai store token không phát thay đổi.
@MainActor
@Observable
final class QuickTranslationRuleTokenPaletteModel {
    /// Trang danh sách mở từ menu nhấn giữ — đẩy trong `NavigationStack` của sheet sửa rule.
    enum Route: Hashable {
        case surnameList
        case bracketList
        case customToken(String)
    }

    var route: Route?
    /// Sheet "Thêm token" (chip `+` của nhóm Tùy chọn).
    var isCreatingToken = false
    /// Sheet "Sửa token" (menu "Sửa mô tả").
    var editingToken: QuickTranslationCustomToken?
    /// Hộp xác nhận "Xoá token".
    var pendingDeletion: QuickTranslationCustomToken?
    private(set) var revision = 0

    func refresh() {
        revision += 1
    }

    /// Bật / tắt một token cố định = đúng công tắc ở Cấu hình token rule (cùng khoá `UserDefaults`), nên tắt ở đây là tắt
    /// token đó cho **mọi** rule.
    func toggle(_ kind: QuickTranslationRuleTokenSettings.Kind) {
        let isEnabled = QuickTranslationRuleTokenSettings.isEnabled(kind)
        UserDefaults.standard.set(!isEnabled, forKey: kind.userDefaultsKey)
        TranslateUtils.clearCache()
        TranslationManager.shared.notifyRulesDidUpdate()
        ToastManager.shared.show(message: isEnabled ? "Đã tắt \(kind.syntax)" : "Đã bật \(kind.syntax)", type: .success)
        refresh()
    }

    func toggle(_ token: QuickTranslationCustomToken) {
        if let error = QuickTranslationCustomTokenStore.shared.setEnabled(!token.isEnabled, name: token.name) {
            ToastManager.shared.show(message: error, type: .error)
        } else {
            ToastManager.shared.show(message: token.isEnabled ? "Đã tắt \(token.syntax)" : "Đã bật \(token.syntax)", type: .success)
        }
        refresh()
    }
}
