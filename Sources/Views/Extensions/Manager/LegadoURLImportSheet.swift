import SwiftUI

/// Sheet "Nhập nguồn từ URL" của tab Nguồn Legado (1.3.624, thay alert có ô nhập).
///
/// - Mở nửa màn, vuốt lên được toàn màn.
/// - Ô URL có bộ nút xoá · sao chép · dán ở trên (`TextFieldClipboardButtons`).
/// - Giải thích nằm trong nút "?" của tiêu đề.
///
/// Sheet chỉ sửa `url` (`LegadoSourceTabState.urlInput`), bấm "Nhập" thì gọi `onConfirm` rồi tự đóng. Việc tải và
/// nhập do `RepositoryManagerView+LegadoMenu` chạy ở `onDismiss` của sheet, qua `LegadoSourceCoordinator` như thời còn
/// alert.
struct LegadoURLImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var url: String
    let onConfirm: () -> Void

    private var trimmedURL: String {
        url.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .center, spacing: 8) {
                            Text("URL")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Spacer(minLength: 8)
                            TextFieldClipboardButtons(text: $url)
                        }
                        TextField("https://…/nguon.json", text: $url)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(.vertical, 4)
                } header: {
                    SectionHelpHeader(
                        "Tệp JSON nguồn",
                        paragraphs: ["URL của tệp JSON chứa **một nguồn** hoặc **mảng nguồn** Legado."]
                    )
                }
            }
            .pageTitle("Nhập nguồn từ URL")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Nhập") {
                        onConfirm()
                        dismiss()
                    }
                    .headerTextButton()
                    .disabled(trimmedURL.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
