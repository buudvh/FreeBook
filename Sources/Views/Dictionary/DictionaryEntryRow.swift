import SwiftUI

/// Một dòng từ vựng trong `DictionaryListView`, gồm 3 icon hành động cùng cỡ,
/// cùng padding, cùng vùng chạm theo thứ tự cố định: `[Sửa] [Chuyển] [Xóa]`.
///
/// Icon giữa là COPY sang phạm vi còn lại:
/// - Đang ở danh sách **Chung** → menu "Chuyển qua Riêng" (VP riêng / Name riêng),
///   đích luôn là truyện của màn Từ điển đang mở (`contextBookId`), không có
///   danh sách chọn truyện. Không xác định được truyện thì icon mờ và chỉ báo lỗi.
/// - Đang ở danh sách **Riêng** → menu "Chuyển qua Chung" (VP chung custom /
///   Name chung custom), chỉ ghi lớp custom.
struct DictionaryEntryRow: View {
    let entry: DictEntry
    /// `true` khi dòng này thuộc danh sách Chung (đích chuyển là Riêng của truyện hiện tại).
    let isGlobalScope: Bool
    /// bookId của màn Từ điển đang mở; `nil` = không xác định được truyện hiện tại.
    let contextBookId: String?
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onCopy: (DictType, DictionaryTransferTarget) -> Void
    let onMissingContext: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.key)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(entry.value)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            Button {
                onEdit()
            } label: {
                Image(systemName: "pencil")
                    .foregroundColor(.accentColor)
                    .font(.subheadline)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Sửa từ \(entry.key)")

            transferButton

            Button {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.red)
                    .font(.subheadline)
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)
            .accessibilityLabel("Xóa từ \(entry.key)")
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var transferButton: some View {
        if isGlobalScope, contextBookId == nil {
            // Không xác định được truyện hiện tại: giữ đúng layout nhưng vô hiệu hoá,
            // chạm vào chỉ báo lý do, tuyệt đối không copy đi đâu.
            Button {
                onMissingContext()
            } label: {
                transferIcon(color: .secondary)
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)
            .accessibilityLabel("Không xác định được truyện hiện tại để chuyển \(entry.key)")
        } else {
            Menu {
                if isGlobalScope, let bid = contextBookId {
                    Section("Chuyển qua Riêng") {
                        Button {
                            onCopy(.vietPhrase, .privateBook(bookId: bid))
                        } label: {
                            Label("VP riêng", systemImage: "textformat")
                        }
                        Button {
                            onCopy(.names, .privateBook(bookId: bid))
                        } label: {
                            Label("Name riêng", systemImage: "person.text.rectangle")
                        }
                    }
                } else {
                    Section("Chuyển qua Chung") {
                        Button {
                            onCopy(.vietPhrase, .globalCustom)
                        } label: {
                            Label("VP chung custom", systemImage: "textformat")
                        }
                        Button {
                            onCopy(.names, .globalCustom)
                        } label: {
                            Label("Name chung custom", systemImage: "person.text.rectangle")
                        }
                    }
                }
            } label: {
                transferIcon(color: .accentColor)
            }
            .menuStyle(.borderlessButton)
            .padding(.leading, 8)
            .accessibilityLabel(isGlobalScope
                ? "Chuyển \(entry.key) qua từ điển riêng của truyện hiện tại"
                : "Chuyển \(entry.key) qua từ điển chung custom")
        }
    }

    private func transferIcon(color: Color) -> some View {
        Image(systemName: "arrow.left.arrow.right")
            .foregroundColor(color)
            .font(.subheadline)
    }
}
