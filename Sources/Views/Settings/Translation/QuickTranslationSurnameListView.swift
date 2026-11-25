import SwiftUI
import UniformTypeIdentifiers

/// Màn **Danh sách họ** của token `<ho>` (1.3.1062) — mở từ hàng "Danh sách họ" ở Cấu hình token rule › Token từ điển,
/// cạnh hàng "Bộ ngoặc". Kiểu màn danh sách 1.3.636: header chỉ có nút quay lại + `…` (`.sideDrawerMenu`: Nhập file,
/// Xuất file, Khôi phục mặc định), ô tìm luôn hiện, nút `+` nổi, hàng `QuickTranslationSurnameRow` (chạm thân hàng mở
/// sheet sửa, `[Tắt/Bật] [Xoá]`).
///
/// Bản gốc 683 họ đóng trong app; mọi thao tác ở đây chỉ ghi lớp riêng (`QuickTranslationSurnameStore`). Store không phát
/// thay đổi ⇒ màn giữ bản chụp ở `@State`, đọc lại sau **mọi** lần ghi và ở `onAppear` (như `QuickTranslationRuleBracketListView`).
/// Chỉ có một danh sách chung, không có bản riêng từng truyện. Toast ở đây (Service không gọi `ToastManager`).
struct QuickTranslationSurnameListView: View {
    typealias Entry = QuickTranslationSurnameEntry
    typealias Store = QuickTranslationSurnameStore

    /// Đích của sheet sửa; `entry == nil` = thêm họ mới.
    private struct EditorTarget: Identifiable {
        let id = UUID()
        let entry: Entry?
    }

    private struct SharedExport: Identifiable {
        let url: URL
        var id: String { url.absoluteString }
    }

    private static let exportFileName = "ChineseSurnames.txt"

    @State private var entries: [Entry] = Store.shared.entries()
    @State private var isCustomized = Store.shared.isCustomized
    @State private var searchText = ""
    @State private var editorTarget: EditorTarget?
    @State private var showingMenu = false
    @State private var showingFilePicker = false
    @State private var confirmingReset = false
    @State private var sharedExport: SharedExport?

    /// "683 họ · 1 đang tắt" — dùng chung cho tiêu đề section ở đây và dòng phụ hàng "Danh sách họ".
    static func summaryText(total: Int, disabled: Int) -> String {
        disabled > 0 ? "\(total) họ · \(disabled) đang tắt" : "\(total) họ"
    }

    private var matchedEntries: [Entry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return entries }
        return entries.filter { $0.key.contains(query) || $0.reading.lowercased().contains(query) }
    }

    private var sectionTitle: String {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Self.summaryText(total: entries.count, disabled: entries.filter { !$0.isEnabled }.count)
        }
        return "\(matchedEntries.count) kết quả cho \"\(searchText)\""
    }

    var body: some View {
        List { Group {
            Section {
                let matched = matchedEntries
                if matched.isEmpty {
                    Text(verbatim: entries.isEmpty ? "Danh sách họ đang trống: <ho> sẽ không khớp gì. Bấm + để thêm."
                                                   : "Không có họ nào khớp.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                ForEach(matched) { entry in
                    QuickTranslationSurnameRow(
                        entry: entry,
                        onEdit: { editorTarget = EditorTarget(entry: entry) },
                        onToggle: { toggle(entry) },
                        onDelete: { delete(entry) }
                    )
                }
            } header: {
                SectionHelpHeader(sectionTitle, texts: QuickTranslationRuleGuide.helpTexts(for: .surnameList))
            }
        }.glassSheetRows() }
        .listStyle(.plain)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Tìm chữ Hán hoặc âm đọc")
        .backPageTitle("Danh sách họ")
        .floatingAddButton("Thêm họ") {
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
                .accessibilityLabel("Tuỳ chọn danh sách họ")
            }
        }
        .sideDrawerMenu(isPresented: $showingMenu, title: "Danh sách họ") {
            SideDrawerActionRow("Nhập file", systemImage: "square.and.arrow.down") { showingFilePicker = true }
            SideDrawerActionRow("Xuất file", systemImage: "square.and.arrow.up") { exportFile() }
                .disabled(!entries.contains(where: \.isEnabled))
            SideDrawerActionRow("Khôi phục mặc định", systemImage: "arrow.counterclockwise", role: .destructive) {
                confirmingReset = true
            }
            .disabled(!isCustomized)
        }
        .sheet(item: $editorTarget) { target in
            Group {
                QuickTranslationSurnameEditorSheet(
                    original: target.entry,
                    onSave: { key, reading in save(key: key, reading: reading, replacing: target.entry?.key) },
                    onRestoreBundledReading: { restoreBundledReading(of: target.entry) }
                )
            }
            .appGlassSheet()
        }
        .sheet(item: $sharedExport, onDismiss: { cleanUpExport() }) { export in
            ShareSheet(activityItems: [export.url]) { _, completed, _, error in
                if completed {
                    ToastManager.shared.show(message: "Đã xuất danh sách họ", type: .success)
                } else if let error {
                    ToastManager.shared.show(message: "Lỗi chia sẻ: \(error.localizedDescription)", type: .error)
                }
            }
        }
        .dataImportFilePicker(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.plainText, .text],
            title: "Nhập danh sách họ"
        ) { url, mode in
            importFile(url, mode: mode)
        }
        .confirmationDialog("Khôi phục danh sách họ mặc định?", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Khôi phục mặc định", role: .destructive) { resetToDefaults() }
            Button("Hủy", role: .cancel) {}
        } message: {
            Text("Mọi họ đã thêm, sửa, xoá hoặc tắt sẽ mất.")
        }
        .onAppear { reload() }
    }

    // MARK: - Thao tác

    private func reload() {
        entries = Store.shared.entries()
        isCustomized = Store.shared.isCustomized
    }

    /// Lưu từ sheet: store kiểm lại luật + trùng khoá trên dữ liệu mới nhất. `nil` = đã lưu; chuỗi = lỗi để sheet hiện.
    private func save(key: String, reading: String, replacing originalKey: String?) -> String? {
        if let error = Store.shared.save(key: key, reading: reading, replacing: originalKey) {
            reload()
            return error
        }
        reload()
        ToastManager.shared.show(message: originalKey == nil ? "Đã thêm họ \(key)" : "Đã lưu họ \(key)", type: .success)
        return nil
    }

    private func toggle(_ entry: Entry) {
        report(Store.shared.setEnabled(!entry.isEnabled, key: entry.key),
               success: entry.isEnabled ? "Đã tắt họ \(entry.key)" : "Đã bật họ \(entry.key)")
    }

    /// Xoá một chạm như các danh sách rule / từ điển; họ gốc đã xoá thêm lại được, hoặc "Khôi phục mặc định".
    private func delete(_ entry: Entry) {
        report(Store.shared.delete(key: entry.key), success: "Đã xoá họ \(entry.key)")
    }

    private func restoreBundledReading(of entry: Entry?) {
        guard let entry, let bundled = entry.bundledReading else { return }
        report(Store.shared.restoreBundledReading(key: entry.key), success: "Đã về âm gốc \(bundled)")
    }

    private func resetToDefaults() {
        Store.shared.resetToDefaults()
        reload()
        ToastManager.shared.show(message: "Đã khôi phục danh sách họ mặc định", type: .success)
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
            let outcome = try Store.shared.importFile(at: url, mode: mode)
            reload()
            var message = "Đã nhập: thêm \(outcome.added), cập nhật \(outcome.updated)"
            if outcome.removed > 0 { message += ", bỏ \(outcome.removed) họ cũ" }
            if outcome.skipped > 0 { message += ", bỏ qua \(outcome.skipped) dòng lỗi" }
            ToastManager.shared.show(message: message, type: .success)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            ToastManager.shared.show(message: "Lỗi nhập danh sách họ: \(message)", type: .error)
        }
    }

    private func exportFile() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(Self.exportFileName)
        do {
            try Store.shared.exportText().write(to: url, atomically: true, encoding: .utf8)
            sharedExport = SharedExport(url: url)
        } catch {
            ToastManager.shared.show(message: "Lỗi xuất danh sách họ: \(error.localizedDescription)", type: .error)
        }
    }

    /// `sheet(item:)` đặt `nil` trước `onDismiss` ⇒ xoá file xuất tạm.
    private func cleanUpExport() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(Self.exportFileName)
        try? FileManager.default.removeItem(at: url)
    }
}
