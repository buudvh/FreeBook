import SwiftUI
import UniformTypeIdentifiers

/// Màn **danh sách từ** của một token tùy chọn `<@tên>` (1.3.1063) — mở từ màn Token tùy chọn hoặc từ menu nhấn giữ của
/// bảng token ở màn sửa rule (đẩy trang trong sheet). Kiểu màn danh sách 1.3.636 như `QuickTranslationSurnameListView`:
/// header nút quay lại + `…` (`.sideDrawerMenu`: Sửa mô tả, Tắt / Bật token, Nhập file, Xuất file, Xoá token), ô tìm luôn
/// hiện, nút `+` nổi "Thêm từ", hàng `QuickTranslationCustomTokenEntryRow` (chạm thân hàng mở sheet sửa, `[Xoá]`).
///
/// Store không phát thay đổi ⇒ giữ bản chụp ở `@State`, đọc lại sau mọi lần ghi và ở `onAppear`. Xoá token ở ngăn kéo
/// ⇒ màn tự quay lại; token đã mất vì lý do khác thì tiêu đề section ghi "Token không còn".
struct QuickTranslationCustomTokenEntryListView: View {
    typealias Token = QuickTranslationCustomToken
    typealias Entry = QuickTranslationCustomToken.Entry
    typealias Store = QuickTranslationCustomTokenStore

    /// Đích của sheet sửa; `entry == nil` = thêm từ mới.
    private struct EditorTarget: Identifiable {
        let id = UUID()
        let entry: Entry?
    }

    private struct SharedExport: Identifiable {
        let url: URL
        var id: String { url.absoluteString }
    }

    let tokenName: String

    @Environment(\.dismiss) private var dismiss
    @State private var token: Token?
    @State private var searchText = ""
    @State private var editorTarget: EditorTarget?
    @State private var editingToken: Token?
    @State private var showingMenu = false
    @State private var showingFilePicker = false
    @State private var pendingDeletion: Token?
    @State private var sharedExport: SharedExport?

    init(tokenName: String) {
        self.tokenName = tokenName
        _token = State(initialValue: Store.shared.token(named: tokenName))
    }

    private var syntax: String { "<@\(tokenName)>" }
    private var entries: [Entry] { token?.entries ?? [] }
    private var exportFileName: String { "\(tokenName).txt" }

    private var matchedEntries: [Entry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return entries }
        return entries.filter { $0.key.contains(query) || $0.meaning.lowercased().contains(query) }
    }

    private var sectionTitle: String {
        guard let token else { return "Token không còn" }
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var parts = [token.displayTitle, "\(token.entries.count) từ"]
            if !token.isEnabled { parts.append("đang tắt") }
            return parts.joined(separator: " · ")
        }
        return "\(matchedEntries.count) kết quả cho \"\(searchText)\""
    }

    var body: some View {
        List { Group {
            Section {
                let matched = matchedEntries
                if matched.isEmpty {
                    Text(verbatim: entries.isEmpty ? "Chưa có từ nào: \(syntax) sẽ không khớp gì. Bấm + để thêm." : "Không có từ nào khớp.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                ForEach(matched) { entry in
                    QuickTranslationCustomTokenEntryRow(
                        entry: entry,
                        onEdit: { editorTarget = EditorTarget(entry: entry) },
                        onDelete: { delete(entry) }
                    )
                }
            } header: {
                SectionHelpHeader(sectionTitle, texts: QuickTranslationRuleGuide.helpTexts(for: .customTokenEntries))
            }
        }.glassSheetRows() }
        .listStyle(.plain)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Tìm chữ gốc hoặc nghĩa")
        .backPageTitle(syntax)
        .floatingAddButton("Thêm từ") {
            editorTarget = EditorTarget(entry: nil)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingMenu = true
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: HeaderMetrics.iconFontSize, weight: .semibold))
                        .frame(width: HeaderMetrics.iconFrameWidth, height: HeaderMetrics.iconFrameHeight, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Tuỳ chọn token \(syntax)")
                .disabled(token == nil)
            }
        }
        .sideDrawerMenu(isPresented: $showingMenu, title: syntax) {
            SideDrawerActionRow("Sửa mô tả", systemImage: "pencil") { editingToken = token }
            SideDrawerActionRow(
                token?.isEnabled == false ? "Bật token" : "Tắt token",
                systemImage: token?.isEnabled == false ? "play.circle" : "pause.circle"
            ) { toggleToken() }
            SideDrawerActionRow("Nhập file", systemImage: "square.and.arrow.down") { showingFilePicker = true }
            SideDrawerActionRow("Xuất file", systemImage: "square.and.arrow.up") { exportFile() }
                .disabled(entries.isEmpty)
            SideDrawerActionRow("Xoá token", systemImage: "trash", role: .destructive) { pendingDeletion = token }
        }
        .sheet(item: $editorTarget) { target in
            Group {
                QuickTranslationCustomTokenEntryEditorSheet(tokenName: tokenName, original: target.entry) { key, meaning in
                    save(key: key, meaning: meaning, replacing: target.entry?.key)
                }
            }
            .appGlassSheet()
        }
        .sheet(item: $editingToken, onDismiss: reload) { token in
            Group {
                QuickTranslationCustomTokenEditorSheet(original: token)
            }
            .appGlassSheet()
        }
        .sheet(item: $sharedExport, onDismiss: { cleanUpExport() }) { export in
            ShareSheet(activityItems: [export.url]) { _, completed, _, error in
                if completed {
                    ToastManager.shared.show(message: "Đã xuất \(syntax)", type: .success)
                } else if let error {
                    ToastManager.shared.show(message: "Lỗi chia sẻ: \(error.localizedDescription)", type: .error)
                }
            }
        }
        .dataImportFilePicker(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.plainText, .text],
            title: "Nhập từ cho \(syntax)"
        ) { url, mode in
            importFile(url, mode: mode)
        }
        .customTokenDeletionDialog(pending: $pendingDeletion) { _ in dismiss() }
        .onAppear { reload() }
    }

    // MARK: - Thao tác

    private func reload() {
        token = Store.shared.token(named: tokenName)
    }

    /// Lưu từ sheet: store kiểm lại luật + trùng chữ trên dữ liệu mới nhất. `nil` = đã lưu; chuỗi = lỗi để sheet hiện.
    private func save(key: String, meaning: String, replacing originalKey: String?) -> String? {
        let error = Store.shared.saveEntry(key: key, meaning: meaning, in: tokenName, replacing: originalKey)
        reload()
        if error == nil {
            ToastManager.shared.show(message: originalKey == nil ? "Đã thêm \(key)" : "Đã lưu \(key)", type: .success)
        }
        return error
    }

    private func delete(_ entry: Entry) {
        report(Store.shared.deleteEntry(key: entry.key, in: tokenName), success: "Đã xoá \(entry.key)")
    }

    private func toggleToken() {
        guard let token else { return }
        report(Store.shared.setEnabled(!token.isEnabled, name: tokenName),
               success: token.isEnabled ? "Đã tắt \(syntax)" : "Đã bật \(syntax)")
    }

    private func report(_ error: String?, success: String) {
        reload()
        if let error {
            ToastManager.shared.show(message: error, type: .error)
        } else {
            ToastManager.shared.show(message: success, type: .success)
        }
    }

    /// File + cách nhập đã chọn (popup hiện sau bộ chọn file, chạy khi popup đóng hẳn). File nhỏ ⇒ đọc ngay trên main.
    private func importFile(_ url: URL, mode: DataImportMode) {
        do {
            let outcome = try Store.shared.importFile(at: url, into: tokenName, mode: mode)
            reload()
            var message = "Đã nhập: thêm \(outcome.added), cập nhật \(outcome.updated)"
            if outcome.removed > 0 { message += ", bỏ \(outcome.removed) từ cũ" }
            if outcome.skipped > 0 { message += ", bỏ qua \(outcome.skipped) dòng lỗi" }
            ToastManager.shared.show(message: message, type: .success)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            ToastManager.shared.show(message: "Lỗi nhập \(syntax): \(message)", type: .error)
        }
    }

    private func exportFile() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(exportFileName)
        do {
            try Store.shared.exportText(of: tokenName).write(to: url, atomically: true, encoding: .utf8)
            sharedExport = SharedExport(url: url)
        } catch {
            ToastManager.shared.show(message: "Lỗi xuất \(syntax): \(error.localizedDescription)", type: .error)
        }
    }

    /// `sheet(item:)` đặt `nil` trước `onDismiss` ⇒ xoá file xuất tạm.
    private func cleanUpExport() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(exportFileName)
        try? FileManager.default.removeItem(at: url)
    }
}
