import SwiftUI

/// Một thẻ Từ điển chung = **`Menu` hệ thống thả xuống** (anh Bửu duyệt mockup: "đừng mở ngăn kéo, mockup lại kiểu
/// dropdown" — ngoại lệ có chủ ý so với luật "menu ba chấm = ngăn kéo"). Nhãn là `DictionaryCard` (icon `ellipsis` dọc
/// cuối thẻ); mục: Sửa, Nhập file, Xuất file, Làm mới dữ liệu, và nhóm riêng Xoá (`role: .destructive`).
///
/// `.menuStyle(.borderlessButton)` như nút Chuyển của hàng danh sách: hai thẻ cùng một hàng `Form` vẫn nhận chạm riêng.
struct GlobalDictionaryCardMenu: View {
    let kind: GlobalDictionaryCardController.Kind
    let statusText: String
    let isSet: Bool
    @ObservedObject var controller: GlobalDictionaryCardController

    var body: some View {
        let isBusy = controller.isBusy(kind)
        Menu {
            if kind.hasEditor {
                Button {
                    controller.editKind = kind
                } label: {
                    Label("Sửa", systemImage: "pencil")
                }
            }
            Button {
                controller.requestImport(kind)
            } label: {
                Label("Nhập file", systemImage: "square.and.arrow.down")
            }
            Button {
                controller.export(kind)
            } label: {
                Label("Xuất file", systemImage: "square.and.arrow.up")
            }
            .disabled(!isSet)
            Button {
                controller.refreshTranslationData()
            } label: {
                Label("Làm mới dữ liệu", systemImage: "arrow.clockwise")
            }
            Section {
                Button(role: .destructive) {
                    controller.deleteKind = kind
                } label: {
                    Label("Xoá", systemImage: "trash")
                }
                .disabled(!isSet)
            }
        } label: {
            DictionaryCard(
                title: kind.title,
                statusText: statusText,
                isSet: isSet,
                isLoading: isBusy
            )
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .disabled(isBusy || controller.isLocked)
        .accessibilityLabel("\(kind.title), \(statusText)")
        .accessibilityHint("Mở menu Sửa, Nhập, Xuất, Làm mới, Xoá")
    }
}
