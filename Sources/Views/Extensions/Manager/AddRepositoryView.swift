import SwiftUI

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
                    TextField("Tên kho truyện (Tùy chọn)", text: $name)
                    TextField("Link plugin.json của kho truyện", text: $url)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.none)
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
    }
}
