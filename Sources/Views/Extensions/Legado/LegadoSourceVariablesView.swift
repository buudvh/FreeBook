import SwiftUI

/// Màn **Biến của nguồn** (đẩy từ màn chi tiết nguồn Legado): xem/sửa biến cấp nguồn — chuỗi mà JS của nguồn đọc
/// bằng `source.getVariable()` (spec §5.7, §12.5). Phía trên hiện `variableComment` như chữ hướng dẫn (chọn được, rút
/// gọn sau 20 dòng); ghi chú là chuỗi liền dài kiểu mã hoá ⇒ chỉ hiện "(nguồn có dữ liệu cấu hình riêng)".
///
/// Đọc/ghi qua `LegadoSourceCoordinator` (kho trạng thái của engine, khoá = `bookSourceUrl` nguyên văn). Biến chỉ là
/// chuỗi, không kiểm định dạng; không ghi giá trị vào log.
struct LegadoSourceVariablesView: View {
    let sourceName: String
    /// `bookSourceUrl` **nguyên văn** — khoá kho trạng thái của engine.
    let sourceKey: String
    let variableComment: String

    @State private var value = ""
    @State private var savedValue = ""
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var showsFullComment = false

    private static let commentLineLimit = 20

    var body: some View {
        Form {
            commentSection
            Section {
                if isLoading {
                    ProgressView()
                } else {
                    TextEditor(text: $value)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(minHeight: 160)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            } header: {
                Text("Biến nguồn")
            } footer: {
                Text("JS của nguồn đọc giá trị này bằng source.getVariable(). Để trống = không có biến.")
            }
            if !isLoading, !savedValue.isEmpty {
                Section {
                    Button(role: .destructive, action: { save("") }) {
                        Label("Xoá biến", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Biến của nguồn")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(action: { save(value) }) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("Lưu").fontWeight(.bold)
                    }
                }
                .disabled(isLoading || isSaving || value == savedValue)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .task { await load() }
    }

    // MARK: - Ghi chú

    @ViewBuilder
    private var commentSection: some View {
        let comment = variableComment.trimmingCharacters(in: .whitespacesAndNewlines)
        if !comment.isEmpty {
            Section(header: Text("Hướng dẫn của nguồn")) {
                if Self.looksEncoded(comment) {
                    Text("(nguồn có dữ liệu cấu hình riêng)")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } else {
                    Text(comment)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .lineLimit(showsFullComment ? nil : Self.commentLineLimit)
                        .textSelection(.enabled)
                    if comment.components(separatedBy: .newlines).count > Self.commentLineLimit || comment.count > 1200 {
                        Button(showsFullComment ? "Thu gọn" : "Xem thêm") {
                            showsFullComment.toggle()
                        }
                        .font(.footnote)
                    }
                }
            }
        }
    }

    /// Chuỗi liền không khoảng trắng dài > 40 ký tự (kiểu base64 mà `jsLib` tự đọc) — không đổ ra màn hình.
    private static func looksEncoded(_ text: String) -> Bool {
        text.count > 40 && !text.contains(where: { $0.isWhitespace })
    }

    // MARK: - Đọc / ghi

    private func load() async {
        guard isLoading else { return }
        let stored = await LegadoSourceCoordinator.shared.sourceVariable(sourceKey: sourceKey)
        value = stored
        savedValue = stored
        isLoading = false
    }

    private func save(_ newValue: String) {
        guard !isSaving else { return }
        isSaving = true
        let key = sourceKey
        Task { @MainActor in
            await LegadoSourceCoordinator.shared.setSourceVariable(newValue, sourceKey: key)
            value = newValue
            savedValue = newValue
            isSaving = false
            ToastManager.shared.show(message: "Đã lưu biến nguồn", type: .success)
        }
    }
}
