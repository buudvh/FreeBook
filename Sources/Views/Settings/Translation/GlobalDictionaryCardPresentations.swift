import SwiftUI
import UniformTypeIdentifiers

/// Mọi thứ trình bày của 5 thẻ Từ điển chung, gắn ở **thân** màn Cài đặt dịch thuật (không gắn trong ô lưới của
/// `Form`): popup chọn cách nhập (3 lựa chọn, `dataImportModePopup` — xong mới mở bộ chọn file), bộ chọn file, bảng chia
/// sẻ file xuất (đóng ⇒ xoá file tạm), hộp xác nhận xoá và trang "Sửa" (`navigationDestination(item:)`).
struct GlobalDictionaryCardPresentations: ViewModifier {
    @ObservedObject var controller: GlobalDictionaryCardController

    func body(content: Content) -> some View {
        content
            .dataImportModePopup(
                isPresented: $controller.showingImportModes,
                title: "Nhập \(controller.importKind.title)"
            ) { mode in
                controller.confirmImportMode(mode)
            }
            .background(
                DocumentPickerPresenter(
                    isPresented: $controller.showingFilePicker,
                    allowedContentTypes: [.plainText, .text],
                    allowsMultipleSelection: false,
                    onPick: { urls in controller.handlePickedFile(urls.first) },
                    onCancel: nil
                )
            )
            .sheet(item: $controller.sharedExport, onDismiss: { controller.cleanUpSharedExport() }) { export in
                ShareSheet(activityItems: [export.url]) { _, completed, _, error in
                    if completed {
                        ToastManager.shared.show(message: "Đã xuất \(export.title)", type: .success)
                    } else if let error {
                        ToastManager.shared.show(message: "Lỗi chia sẻ: \(error.localizedDescription)", type: .error)
                    }
                }
            }
            .confirmationDialog(
                "Xoá \(controller.deleteKind?.title ?? "")?",
                isPresented: deleteBinding,
                titleVisibility: .visible,
                presenting: controller.deleteKind
            ) { kind in
                Button("Xoá \(kind.title)", role: .destructive) {
                    controller.confirmDelete(kind)
                }
                Button("Hủy", role: .cancel) {}
            } message: { kind in
                Text(GlobalDictionaryCardController.deleteMessage(for: kind))
            }
            .navigationDestination(item: $controller.editKind) { kind in
                destination(for: kind)
            }
    }

    private var deleteBinding: Binding<Bool> {
        Binding(
            get: { controller.deleteKind != nil },
            set: { if !$0 { controller.deleteKind = nil } }
        )
    }

    /// Trang "Sửa": VP / Name ⇒ danh sách Chung (lớp từ đã sửa); Rule dịch ⇒ danh sách bộ rule chung.
    @ViewBuilder
    private func destination(for kind: GlobalDictionaryCardController.Kind) -> some View {
        switch kind {
        case .vietPhrase:
            DictionaryListView(type: .vietPhrase, bookId: nil)
        case .names:
            DictionaryListView(type: .names, bookId: nil)
        case .rules:
            QuickTranslationRuleListView(scope: .global)
        case .phienAm, .pronouns:
            EmptyView()
        }
    }
}
