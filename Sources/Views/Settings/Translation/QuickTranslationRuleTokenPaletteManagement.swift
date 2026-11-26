import SwiftUI

/// Gắn ở `Form` của sheet sửa rule (ngoài hàng lazy của bảng token): biến ý định ghi trong
/// `QuickTranslationRuleTokenPaletteModel` thành đẩy trang (Danh sách họ, Bộ ngoặc, danh sách từ của token tùy chọn),
/// sheet Thêm / Sửa token và hộp xác nhận Xoá token (1.3.1063). Mọi lối về (quay lại, đóng sheet, xoá xong) gọi
/// `refresh()` để bảng token đọc lại dữ liệu.
struct QuickTranslationRuleTokenPaletteManagement: ViewModifier {
    typealias Model = QuickTranslationRuleTokenPaletteModel

    @Bindable var model: Model

    func body(content: Content) -> some View {
        content
            .navigationDestination(item: routeBinding) { route in
                destination(for: route)
            }
            .sheet(isPresented: $model.isCreatingToken, onDismiss: { model.refresh() }) {
                Group {
                    QuickTranslationCustomTokenEditorSheet(original: nil)
                }
                .appGlassSheet()
            }
            .sheet(item: $model.editingToken, onDismiss: { model.refresh() }) { token in
                Group {
                    QuickTranslationCustomTokenEditorSheet(original: token)
                }
                .appGlassSheet()
            }
            .customTokenDeletionDialog(pending: $model.pendingDeletion) { _ in model.refresh() }
    }

    /// Quay lại từ trang danh sách (route về `nil`) ⇒ vẽ lại bảng token: trang đó có thể đã bật / tắt / sửa token.
    private var routeBinding: Binding<Model.Route?> {
        Binding(
            get: { model.route },
            set: { newValue in
                model.route = newValue
                if newValue == nil { model.refresh() }
            }
        )
    }

    @ViewBuilder
    private func destination(for route: Model.Route) -> some View {
        switch route {
        case .surnameList:
            QuickTranslationSurnameListView()
        case .bracketList:
            QuickTranslationRuleBracketListView(scope: .global)
        case .customToken(let name):
            QuickTranslationCustomTokenEntryListView(tokenName: name)
        }
    }
}

extension View {
    /// Gắn đích đẩy trang / sheet / hộp xác nhận cho menu quản lý token của bảng token (xem
    /// `QuickTranslationRuleTokenPaletteManagement`).
    func tokenPaletteManagement(_ model: QuickTranslationRuleTokenPaletteModel) -> some View {
        modifier(QuickTranslationRuleTokenPaletteManagement(model: model))
    }
}
