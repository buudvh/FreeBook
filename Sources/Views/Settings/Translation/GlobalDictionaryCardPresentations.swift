import SwiftUI
import UniformTypeIdentifiers

/// Mọi thứ trình bày của 5 thẻ Từ điển chung, gắn ở **thân** màn Cài đặt dịch thuật (không gắn trong ô lưới của
/// `Form`): bộ chọn file của "Nhập file" + popup chọn cách nhập hiện **sau** khi chọn file, kèm tên file
/// (`dataImportFilePicker`), bảng chia sẻ file xuất (đóng ⇒ xoá file tạm), hộp xác nhận xoá và trang "Sửa"
/// (`navigationDestination(item:)`).
struct GlobalDictionaryCardPresentations: ViewModifier {
    @ObservedObject var controller: GlobalDictionaryCardController

    func body(content: Content) -> some View {
        content
            .dataImportFilePicker(
                isPresented: $controller.showingFilePicker,
                allowedContentTypes: [.plainText, .text],
                title: "Nhập \(controller.importKind.title)"
            ) { url, mode in
                controller.importFile(url, mode: mode)
            }
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

    /// Trang "Sửa": VP / Name ⇒ danh sách từ điển gốc `.dat` với nghĩa hiệu lực (anh Bửu: "Sửa vietphrase thì hiển thị
    /// danh sách của vietphrase.dat chứ không phải custom vietphrase"; danh sách Chung cũ vào từ ngăn kéo "…" của nó);
    /// PhienAm / Pronouns ⇒ danh sách sửa thẳng file gốc; Rule dịch ⇒ danh sách bộ rule chung.
    @ViewBuilder
    private func destination(for kind: GlobalDictionaryCardController.Kind) -> some View {
        switch kind {
        case .vietPhrase:
            GlobalBaseDictionaryListView(type: .vietPhrase)
        case .names:
            GlobalBaseDictionaryListView(type: .names)
        case .rules:
            QuickTranslationRuleListView(scope: .global)
        case .phienAm, .pronouns:
            BaseDictionaryListView(kind: kind)
        }
    }
}
