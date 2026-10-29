import SwiftUI

/// Màn **Sửa JSON nguồn** (sheet từ màn chi tiết nguồn Legado): dùng lại trình soạn mã của tiện ích JS
/// (`HighlightingCodeEditor`, cùng cỡ chữ `scriptEditorFontSize`), thanh dưới "N dòng · M ký tự", A-/A+, **Cú pháp**,
/// **Định dạng**, **Tải lại**; toolbar chỉ còn Lưu — đóng bằng vuốt xuống, đang có thay đổi chưa lưu thì hỏi
/// "Bỏ thay đổi?" (`confirmDiscardOnSwipe`).
///
/// - Chỉ lưu khi JSON hợp lệ và đúng là một nguồn nhận được (`LegadoSourceJSONValidator`); lỗi báo theo dòng khi trình
///   phân tích chỉ ra được.
/// - Ghi qua `LegadoSourceCoordinator.saveEditedJSON` (View không ghi file). Đổi `bookSourceUrl` ⇒ là **nguồn khác**
///   (`packageId` khác): hỏi lại — nhập thành nguồn mới (giữ bản cũ) hoặc nhập mới rồi xoá bản cũ.
struct LegadoSourceJSONEditorView: View {
    enum Outcome {
        case saved
        case movedToNewSource(deletedOld: Bool)
    }

    private struct Banner: Equatable {
        let message: String
        let isValid: Bool
    }

    @Environment(\.dismiss) private var dismiss

    let packageId: String
    let sourceName: String
    let onFinish: (Outcome) -> Void

    @State private var text = ""
    @State private var originalText = ""
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var banner: Banner?
    @State private var isSaving = false
    @State private var pendingNewPackageId: String?
    /// Cùng khoá với trình soạn script của tiện ích JS — đổi cỡ chữ ở một nơi là hai nơi cùng theo.
    @AppStorage("scriptEditorFontSize") private var fontSize: Double = 11.0

    private let editorBackground = Color(red: 24 / 255, green: 24 / 255, blue: 37 / 255)

    private var hasChanges: Bool { text != originalText }

    var body: some View {
        NavigationStack {
            editorContent
                .pageTitle("Sửa JSON nguồn")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(action: save) {
                            if isSaving {
                                ProgressView()
                            } else {
                                Text("Lưu").fontWeight(.bold)
                            }
                        }
                        .disabled(!hasChanges || isSaving || isLoading)
                    }
                }
                .confirmationDialog(
                    "bookSourceUrl đã đổi",
                    isPresented: Binding(
                        get: { pendingNewPackageId != nil },
                        set: { if !$0 { pendingNewPackageId = nil } }
                    ),
                    titleVisibility: .visible
                ) {
                    Button("Nhập thành nguồn mới (giữ nguồn cũ)") { importAsNew(deleteOld: false) }
                    Button("Nhập mới và xoá nguồn cũ", role: .destructive) { importAsNew(deleteOld: true) }
                    Button("Huỷ", role: .cancel) {}
                } message: {
                    Text("URL nguồn là khoá nhận diện, nên đây là một nguồn khác. Sách đã lưu của nguồn cũ chỉ đọc tiếp được khi giữ nguồn cũ.")
                }
        }
        .confirmDiscardOnSwipe(isDirty: hasChanges)
        .presentationDragIndicator(.visible)
        .task { await load() }
    }

    @ViewBuilder
    private var editorContent: some View {
        if isLoading {
            ProgressView("Đang đọc source.json…")
        } else if let loadError {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundColor(.orange)
                Text(loadError)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        } else {
            VStack(spacing: 0) {
                if let banner {
                    bannerView(banner)
                }
                HighlightingCodeEditor(text: $text, fontSize: CGFloat(fontSize))
                    .background(editorBackground)
                footer
                    .contentShape(Rectangle())
                    .onTapGesture { KeyboardDismissPreference.dismissOnTapOutsideIfEnabled() }
            }
        }
    }

    private func bannerView(_ banner: Banner) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: banner.isValid ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .foregroundColor(banner.isValid ? .green : .red)
            Text(banner.message)
                .font(.caption.weight(.medium))
                .foregroundColor(banner.isValid ? .green : .red)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(banner.isValid ? Color.green.opacity(0.12) : Color.red.opacity(0.12))
    }

    // MARK: - Thanh dưới

    private var footer: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Text("\(text.components(separatedBy: .newlines).count) dòng · \(text.count) ký tự")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                fontSizeControls
            }
            HStack(spacing: 8) {
                footerButton("Cú pháp", systemImage: "checkmark.shield", action: checkSyntax)
                footerButton("Định dạng", systemImage: "text.alignleft", action: formatText)
                footerButton("Tải lại", systemImage: "arrow.uturn.backward", action: revert)
                    .disabled(!hasChanges)
                Spacer()
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    private func footerButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.caption)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var fontSizeControls: some View {
        HStack(spacing: 4) {
            Button(action: { if fontSize > 9 { fontSize -= 1 } }) {
                Text("A-").font(.caption2).fontWeight(.bold)
            }
            .disabled(fontSize <= 9)
            Text("\(Int(fontSize))pt")
                .font(.caption2)
                .foregroundColor(.secondary)
            Button(action: { if fontSize < 22 { fontSize += 1 } }) {
                Text("A+").font(.caption2).fontWeight(.bold)
            }
            .disabled(fontSize >= 22)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color(uiColor: .tertiarySystemFill))
        .cornerRadius(6)
    }

    // MARK: - Hành động

    private func load() async {
        guard isLoading else { return }
        switch await LegadoSourceCoordinator.shared.loadSource(packageId: packageId) {
        case .success(let source):
            let pretty = LegadoSourceJSONValidator.prettyText(fromData: source.rawJSON)
            text = pretty
            originalText = pretty
        case .failure(let error):
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private func checkSyntax() {
        switch LegadoSourceJSONValidator.validate(text) {
        case .success: banner = Banner(message: "JSON hợp lệ, nguồn nhận được.", isValid: true)
        case .failure(let issue): banner = Banner(message: issue.displayText, isValid: false)
        }
    }

    private func formatText() {
        guard let pretty = LegadoSourceJSONValidator.prettyText(fromText: text) else {
            checkSyntax()
            return
        }
        text = pretty
        banner = Banner(message: "Đã định dạng lại (khoá sắp xếp, thụt 2 dấu cách).", isValid: true)
    }

    private func revert() {
        text = originalText
        banner = nil
    }

    private func save() {
        if case .failure(let issue) = LegadoSourceJSONValidator.validate(text) {
            banner = Banner(message: issue.displayText, isValid: false)
            return
        }
        isSaving = true
        let snapshot = text
        let id = packageId
        Task { @MainActor in
            let outcome = await LegadoSourceCoordinator.shared.saveEditedJSON(snapshot, packageId: id)
            isSaving = false
            handle(outcome, deletedOld: nil)
        }
    }

    private func importAsNew(deleteOld: Bool) {
        isSaving = true
        let snapshot = text
        let oldId = deleteOld ? packageId : nil
        Task { @MainActor in
            let outcome = await LegadoSourceCoordinator.shared.importEditedAsNew(snapshot, replacing: oldId)
            isSaving = false
            handle(outcome, deletedOld: deleteOld)
        }
    }

    /// `deletedOld == nil` ⇒ lượt lưu thường (cùng nguồn).
    private func handle(_ outcome: LegadoSourceCoordinator.JSONSaveOutcome, deletedOld: Bool?) {
        switch outcome {
        case .saved:
            originalText = text
            if let deletedOld {
                ToastManager.shared.show(message: "Đã nhập thành nguồn mới", type: .success)
                onFinish(.movedToNewSource(deletedOld: deletedOld))
            } else {
                ToastManager.shared.show(message: "Đã lưu nguồn", type: .success)
                onFinish(.saved)
            }
            dismiss()
        case .unchanged:
            originalText = text
            banner = Banner(message: "Không có thay đổi so với bản đang lưu.", isValid: true)
        case .sourceURLChanged(let newPackageId):
            pendingNewPackageId = newPackageId
        case .invalid(let issue):
            banner = Banner(message: issue.displayText, isValid: false)
        case .failed(let message):
            banner = Banner(message: message, isValid: false)
        }
    }
}
