import SwiftUI
import UniformTypeIdentifiers

/// Menu **Nhập / Xuất / Xoá** cho bộ rule **riêng của một truyện**.
///
/// Bộ chung đã có màn "Quản lý rule dịch" lo việc này; bộ riêng không có màn quản lý riêng nên chỗ
/// tự nhiên nhất là toolbar của danh sách rule riêng. Tách thành View riêng để
/// `QuickTranslationRuleListView` không phải cõng thêm document picker + share sheet + dialog 3 chế độ.
///
/// Ba chế độ nhập dùng đúng `DataImportMode` chung của app, và đi qua đúng `importRules` của store nên
/// vẫn validate-then-swap: file lỗi nặng thì bộ đang chạy không bị thay.
struct QuickTranslationRuleIOMenu: View {
    let bookId: String
    let onChanged: () -> Void

    private struct SharedFile: Identifiable {
        var id: String { url.absoluteString }
        let url: URL
    }

    @ObservedObject private var store = QuickTranslationRuleBookStore.shared

    @State private var showingImporter = false
    @State private var showingImportModes = false
    @State private var showingDeleteConfirm = false
    @State private var pendingImportText: String? = nil
    @State private var pendingPreview: (added: Int, overlapping: Int, machineOnly: Int) = (0, 0, 0)
    @State private var sharedFile: SharedFile? = nil

    var body: some View {
        Menu {
            Button {
                showingImporter = true
            } label: {
                Label("Nhập file rule (.txt)", systemImage: "square.and.arrow.down")
            }

            Button {
                exportRules()
            } label: {
                Label("Xuất bộ rule riêng", systemImage: "square.and.arrow.up")
            }
            .disabled(!store.hasRuleFile(for: bookId))

            Button(role: .destructive) {
                showingDeleteConfirm = true
            } label: {
                Label("Xoá bộ rule riêng", systemImage: "trash")
            }
            .disabled(!store.hasRuleFile(for: bookId))
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .background(
            DocumentPickerPresenter(
                isPresented: $showingImporter,
                allowedContentTypes: [.plainText, .text],
                allowsMultipleSelection: false,
                onPick: { urls in readImport(from: urls.first) },
                onCancel: nil
            )
        )
        .sheet(item: $sharedFile) { file in
            ShareSheet(activityItems: [file.url]) { _, completed, _, error in
                if completed {
                    ToastManager.shared.show(message: "Đã xuất bộ rule riêng.", type: .success)
                } else if let error = error {
                    ToastManager.shared.show(message: "Lỗi chia sẻ: \(error.localizedDescription)", type: .error)
                }
            }
        }
        .confirmationDialog(
            "Nhập bộ rule riêng thế nào?",
            isPresented: $showingImportModes,
            titleVisibility: .visible
        ) {
            ForEach(DataImportMode.allCases, id: \.self) { mode in
                Button(mode.actionTitle, role: mode.isDestructive ? .destructive : nil) {
                    applyImport(mode: mode)
                }
            }
            Button("Hủy", role: .cancel) { pendingImportText = nil }
        } message: {
            Text(
                "File có \(pendingPreview.added + pendingPreview.overlapping) rule:"
                + " \(pendingPreview.overlapping) trùng mẫu với bộ riêng đang có, \(pendingPreview.added) mẫu mới."
                + " Bộ riêng trên máy có \(pendingPreview.machineOnly) mẫu không nằm trong file."
            )
        }
        .confirmationDialog(
            "Xoá bộ rule riêng của truyện?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Xoá bộ rule riêng", role: .destructive) {
                let existed = store.deleteRules(for: bookId)
                ToastManager.shared.show(
                    message: existed ? "Đã xoá bộ rule riêng." : "Truyện này chưa có bộ rule riêng.",
                    type: .info
                )
                onChanged()
            }
            Button("Hủy", role: .cancel) {}
        } message: {
            Text("Truyện này sẽ quay về dùng thuần bộ rule chung. Bộ chung không bị ảnh hưởng.")
        }
    }

    // MARK: - Thao tác

    /// Đọc file rồi **hỏi chế độ trước khi ghi** — chọn file không tự động là "thay thế toàn bộ".
    private func readImport(from url: URL?) {
        guard let url else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            ToastManager.shared.show(message: "Không đọc được file rule (cần UTF-8).", type: .error)
            return
        }

        pendingImportText = text
        pendingPreview = QuickTranslationRuleFileEditor.importPreview(
            current: store.currentSourceText(for: bookId) ?? "",
            imported: text
        )
        showingImportModes = true
    }

    private func applyImport(mode: DataImportMode) {
        guard let text = pendingImportText else { return }
        pendingImportText = nil

        switch store.importRules(text: text, mode: mode, bookId: bookId) {
        case .success(let ruleCount, let warningCount):
            let suffix = warningCount > 0 ? ", \(warningCount) cảnh báo" : ""
            ToastManager.shared.show(
                message: "Đã nhập — bộ riêng hiện có \(ruleCount) rule\(suffix).",
                type: .success
            )
            onChanged()
        case .rejected(let issues):
            let detail = issues.first.map { "dòng \($0.sourceLine) — \($0.code.rawValue)" } ?? "\(issues.count) dòng"
            ToastManager.shared.show(
                message: "File có lỗi nặng (\(detail)) — bộ riêng không đổi.",
                type: .error
            )
        case .failure(let message):
            ToastManager.shared.show(message: message, type: .error)
        }
    }

    private func exportRules() {
        guard let text = store.currentSourceText(for: bookId) else {
            ToastManager.shared.show(message: "Truyện này chưa có bộ rule riêng để xuất.", type: .error)
            return
        }
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(QuickTranslationRuleBookStore.ruleFileName)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            sharedFile = SharedFile(url: url)
        } catch {
            ToastManager.shared.show(message: "Lỗi xuất file: \(error.localizedDescription)", type: .error)
        }
    }
}
