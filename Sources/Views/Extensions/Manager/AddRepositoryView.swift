import SwiftUI
import UIKit

/// Sheet "Nhập kho tiện ích". Từ 1.3.624 mở nửa màn (vuốt lên được toàn màn); mỗi ô có nhãn ở trên kèm bộ nút
/// xoá · sao chép · dán (`TextFieldClipboardButtons`, dán thay cả giá trị).
public struct AddRepositoryView: View {
    @Environment(\.dismiss) internal var dismiss
    @State internal var name = ""
    @State internal var url = ""

    public var onAdd: (String, String) -> Void

    public init(onAdd: @escaping (String, String) -> Void) {
        self.onAdd = onAdd
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Thông tin kho mới")) {
                    fieldRow("Tên kho (tuỳ chọn)", placeholder: "Tên kho truyện", text: $name)
                    fieldRow("Link plugin.json", placeholder: "https://…/plugin.json", text: $url, keyboard: .URL)
                }
            }
            .navigationTitle("Nhập Kho Tiện Ích")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Nhập") {
                        onAdd(name, url)
                        dismiss()
                    }
                    .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Nhãn + bộ nút ở trên, ô nhập ở dưới — cùng dáng hàng ở màn "Thông tin plugin.json" (`ExtensionMetadataSection`).
    private func fieldRow(
        _ label: String,
        placeholder: String,
        text: Binding<String>,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer(minLength: 8)
                TextFieldClipboardButtons(text: text)
            }
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
        }
        .padding(.vertical, 4)
    }
}
