import SwiftUI
import SwiftData

/// Khối **quản lý chính bộ sưu tập** của màn chi tiết: menu `ellipsis.circle` trên toolbar, đổi tên,
/// xoá bộ.
///
/// Tách khỏi `CollectionDetailView.swift` vì file đó đã vượt 400 dòng — trần của
/// `check_architecture.py` cho file mới. Vì `private` trong Swift là phạm vi **file**, các `@State` và
/// `@Environment` mà khối này chạm tới phải là `internal` — cùng khuôn với `ReaderView+Selection` và
/// `QuickTranslationRuleEditorSheet+Editing`.
///
/// Ghi SwiftData vẫn **không** xảy ra ở tầng View: cả đổi tên và xoá đều đi qua
/// `BookCollectionCoordinator` và xử lý `Result` mà nó trả về.
extension CollectionDetailView {

    /// `ellipsis.circle` cho khớp Kệ sách / Reader / Chi tiết truyện (đồng bộ từ 1.3.334). Bộ đã bị xoá
    /// trong lúc màn còn trên stack thì không còn gì để quản lý ⇒ ẩn hẳn menu.
    @ViewBuilder
    var collectionMenu: some View {
        if collection != nil {
            Menu {
                Button {
                    renameText = collection?.name ?? ""
                    showingRenameAlert = true
                } label: {
                    Label("Đổi tên", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Label("Xoá bộ sưu tập", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    func commitRename() {
        // Tên rỗng **không** chặn ở đây: `renameCollection` tự validate và trả lỗi, để người dùng thấy
        // toast thay vì một cú bấm im lặng không có gì xảy ra.
        let res = BookCollectionCoordinator.shared.renameCollection(
            collectionId: collectionId,
            name: renameText,
            in: modelContext
        )
        if case .failure(let err) = res {
            ToastManager.shared.show(message: err.localizedDescription, type: .error)
        }
    }

    /// Xoá xong thì **lùi ra** thay vì để lại màn "Bộ sưu tập không còn tồn tại": người dùng vừa chủ
    /// động xoá, đứng trong một bộ đã chết không nói thêm được gì.
    func commitDelete() {
        let res = BookCollectionCoordinator.shared.deleteCollection(
            collectionId: collectionId,
            in: modelContext
        )
        switch res {
        case .success:
            ToastManager.shared.show(message: "Đã xoá bộ sưu tập", type: .success)
            dismiss()
        case .failure(let err):
            ToastManager.shared.show(message: err.localizedDescription, type: .error)
        }
    }
}
