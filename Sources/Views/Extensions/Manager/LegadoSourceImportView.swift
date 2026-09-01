import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Màn hình nhập nguồn truyện JSON của Legado: dán URL, dán JSON, hoặc chọn tệp.
///
/// Ghi DB đi qua `ExtensionTransactionCoordinator` (View không được `modelContext.insert/save` —
/// luật `VIEW_SWIFTDATA_MUTATION`).
struct LegadoSourceImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var urlText = ""
    @State private var jsonText = ""
    @State private var isImporting = false
    @State private var showingFilePicker = false
    @State private var statusMessage = ""
    @State private var isError = false
    @State private var warnings: [String: [String]] = [:]

    var body: some View {
        NavigationStack {
            Form {
                Section("Từ đường dẫn") {
                    TextField("https://…/shuyuan/json/id/1234.json", text: $urlText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button {
                        importFromURL()
                    } label: {
                        Label("Tải và nhập từ URL", systemImage: "arrow.down.circle")
                    }
                    .disabled(isImporting || urlText.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                Section("Từ tệp") {
                    Button {
                        showingFilePicker = true
                    } label: {
                        Label("Chọn tệp JSON nguồn", systemImage: "folder")
                    }
                    .disabled(isImporting)
                }

                Section("Dán trực tiếp") {
                    TextEditor(text: $jsonText)
                        .frame(minHeight: 120)
                        .font(.system(.footnote, design: .monospaced))
                    Button {
                        importFromText()
                    } label: {
                        Label("Nhập từ nội dung đã dán", systemImage: "doc.on.clipboard")
                    }
                    .disabled(isImporting || jsonText.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if isImporting {
                    Section {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Đang xử lý…")
                        }
                    }
                }

                if !statusMessage.isEmpty {
                    Section("Kết quả") {
                        Text(statusMessage)
                            .foregroundStyle(isError ? Color.red : Color.primary)
                            .font(.footnote)
                    }
                }

                if !warnings.isEmpty {
                    Section("Nguồn cần tính năng chưa hỗ trợ") {
                        ForEach(warnings.keys.sorted(), id: \.self) { name in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(name).font(.footnote.weight(.medium))
                                Text((warnings[name] ?? []).joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    Text("""
                    Chỉ nhận nguồn truyện chữ (bookSourceType = 0). Nguồn cần WebView, đăng nhập, \
                    jsLib hay giải mã font sẽ được nhập nhưng báo cảnh báo và có thể không đọc được.
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Nguồn Legado")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Đóng") { dismiss() }
                }
            }
            .background {
                DocumentPickerPresenter(
                    isPresented: $showingFilePicker,
                    allowedContentTypes: [.json, .text],
                    allowsMultipleSelection: false,
                    onPick: { urls in
                        guard let url = urls.first else { return }
                        importFromFile(url)
                    },
                    onCancel: nil
                )
            }
        }
    }

    // MARK: - Hành động

    private func importFromURL() {
        let target = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        run { try await LegadoSourceImporter.shared.importFromURL(target) }
    }

    private func importFromText() {
        let payload = jsonText
        run { try await LegadoSourceImporter.shared.importFromText(payload) }
    }

    private func importFromFile(_ url: URL) {
        run {
            let data = try Data(contentsOf: url)
            return try await LegadoSourceImporter.shared.importFromData(data)
        }
    }

    private func run(_ operation: @escaping () async throws -> LegadoSourceImporter.Outcome) {
        isImporting = true
        statusMessage = ""
        isError = false
        warnings = [:]

        Task {
            do {
                let outcome = try await operation()
                await MainActor.run {
                    apply(outcome)
                }
            } catch {
                await MainActor.run {
                    isImporting = false
                    isError = true
                    statusMessage = "Nhập thất bại: \(error.localizedDescription)"
                }
            }
        }
    }

    @MainActor
    private func apply(_ outcome: LegadoSourceImporter.Outcome) {
        isImporting = false
        warnings = outcome.warnings

        guard !outcome.commands.isEmpty else {
            isError = true
            statusMessage = "Không nhập được nguồn nào (tìm thấy \(outcome.totalFound), "
                + "bỏ \(outcome.skippedNonText) nguồn không phải truyện chữ, "
                + "\(outcome.skippedIncomplete) nguồn thiếu rule)."
            return
        }

        let result = ExtensionTransactionCoordinator.shared.upsertExtensions(
            commands: outcome.commands,
            in: modelContext
        )
        switch result {
        case .success:
            isError = false
            statusMessage = "Đã nhập \(outcome.importedCount) nguồn."
                + (outcome.skippedNonText > 0 ? " Bỏ \(outcome.skippedNonText) nguồn không phải truyện chữ." : "")
                + (outcome.skippedIncomplete > 0 ? " Bỏ \(outcome.skippedIncomplete) nguồn thiếu rule." : "")
        case .failure(let error):
            isError = true
            statusMessage = "Ghi vào thư viện thất bại: \(error.localizedDescription)"
        }
    }
}
