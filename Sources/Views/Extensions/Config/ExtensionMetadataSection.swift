import SwiftData
import SwiftUI
import UIKit

/// Khối **Metadata** của màn Cấu hình tiện ích: 9 trường đọc từ `plugin.json`, **tự lưu** khi sửa.
///
/// ## Vì sao là View riêng chứ không nhét vào `ExtensionConfigView`
/// `ExtensionConfigView` đang 278 dòng và màn này sát trần 400; khối metadata một mình đã ~9 hàng có trạng
/// thái riêng. Tách ra thì file chính chỉ thêm **một dòng** trong `Form`, và ba section cũ của màn giữ nguyên.
///
/// ## Sáu trường sửa được, ba trường chỉ đọc
/// Sửa: `name`, `source`, `regexp`, `description`, `locale`, `type`. Chỉ đọc: `author`, `version`, `language`
/// (chủ dự án chốt 2026-10-07 — ba trường này thuộc về tác giả tiện ích, không phải thứ người dùng nên đổi).
///
/// ## "Áp dụng ngay" gồm ba việc, không chỉ một
/// 1. Ghi `plugin.json` — nguồn sự thật; lượt đồng bộ kho sau đó đọc lại **đúng** bản đã sửa
///    (`ExtensionSyncCommandBuilder` ưu tiên `plugin.json` cục bộ).
/// 2. Cập nhật hàng `Extension` — để lưới home của trình duyệt (`ext.sourceUrl`), danh sách Tiện Ích và bộ
///    lọc đổi ngay mà không cần khởi động lại.
/// 3. Xoá `BypassWebView.regexpCache` khi `regexp` đổi — không có bước này thì regexp cũ còn sống tới lần mở
///    lại app.
///
/// ## Vì sao ô chữ lưu sau 0,4 giây mà Picker lưu ngay
/// Ghi `plugin.json` mỗi phím gõ là I/O đĩa trên luồng chính từng ký tự, và một lượt chạy JS xen vào sẽ đọc
/// phải giá trị đang gõ dở. 0,4 giây sau phím cuối vẫn là "ngay" với người dùng mà không có hai cái giá đó.
/// Picker là thay đổi rời rạc nên lưu thẳng.
///
/// ## Chỉ ghi khi giá trị **thật sự** khác bản đã nạp
/// `load()` gán `@State` nên `onChange` có bắn; so với `loaded` để một lần gán lúc nạp **không** sinh lượt ghi
/// giả. Quan trọng với `locale`: `read` có nhánh dự phòng `metadata.language` (đúng luật 4 reader khác), nên
/// không so sánh là lượt ghi giả sẽ biến `language: "javascript"` thành `locale: "javascript"` trong file.
struct ExtensionMetadataSection: View {
    @Environment(\.modelContext) private var modelContext

    let ext: Extension

    /// Bản đã nạp từ file — mốc so sánh để biết trường nào **thật sự** đổi.
    @State private var loaded = ExtensionMetadataEditor.Metadata()

    @State private var name = ""
    @State private var source = ""
    @State private var regexp = ""
    @State private var descText = ""
    @State private var locale = ""
    @State private var type = ""

    @State private var isLoading = true
    @State private var statusText = ""
    @State private var errorText = ""
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        Section {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else {
                textFieldRow("name", text: $name)
                textFieldRow("source", text: $source, keyboard: .URL)
                regexpRow
                descriptionRow

                Picker("locale", selection: $locale) {
                    ForEach(ExtensionDisplayCatalog.options(including: locale, from: ExtensionDisplayCatalog.localeOptions), id: \.self) { value in
                        Text(ExtensionDisplayCatalog.label(forLocale: value)).tag(value)
                    }
                }
                .pickerStyle(.menu)

                Picker("type", selection: $type) {
                    ForEach(ExtensionDisplayCatalog.options(including: type, from: ExtensionDisplayCatalog.typeOptions), id: \.self) { value in
                        Text(ExtensionDisplayCatalog.label(forType: value)).tag(value)
                    }
                }
                .pickerStyle(.menu)

                readOnlyRow("author", loaded.author)
                readOnlyRow("version", loaded.version)
                readOnlyRow("language", loaded.language)

                if !errorText.isEmpty {
                    Text(errorText)
                        .font(.caption)
                        .foregroundColor(.red)
                } else if !statusText.isEmpty {
                    Text(statusText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        } header: {
            Text("Metadata (plugin.json)")
        } footer: {
            Text("Sửa là tự lưu và áp dụng ngay. `regexp` quyết định tiện ích nào xử lý URL đang mở trong trình duyệt; `source` là link mà lưới home của trình duyệt mở ra. `name` để trống sẽ giữ nguyên tên cũ.")
        }
        .onAppear { load() }
        .onDisappear { saveTask?.cancel() }
        .onChange(of: name) { _, _ in scheduleSave() }
        .onChange(of: source) { _, _ in scheduleSave() }
        .onChange(of: regexp) { _, _ in scheduleSave() }
        .onChange(of: description) { _, _ in scheduleSave() }
        .onChange(of: locale) { _, _ in saveNow() }
        .onChange(of: type) { _, _ in saveNow() }
    }

    // MARK: - Hàng

    /// Cùng dáng với hàng cấu hình cũ của màn này (`ExtensionConfigView`: nhãn trên, ô nhập dưới).
    private func textFieldRow(_ key: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(key)
                .font(.subheadline)
                .fontWeight(.semibold)
            TextField("", text: text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
        }
        .padding(.vertical, 4)
    }

    /// `regexp` là biểu thức chính quy — hiện bằng chữ đều để đọc được ký tự đặc biệt.
    private var regexpRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("regexp")
                .font(.subheadline)
                .fontWeight(.semibold)
            TextField("", text: $regexp)
                .font(.system(.footnote, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
        }
        .padding(.vertical, 4)
    }

    /// Ô mô tả cho **rộng, nhiều dòng** theo yêu cầu — `axis: .vertical` (iOS 16+, target của app là 17).
    private var descriptionRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("description")
                .font(.subheadline)
                .fontWeight(.semibold)
            TextField("", text: $descText, axis: .vertical)
                .lineLimit(3...8)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
        }
        .padding(.vertical, 4)
    }

    private func readOnlyRow(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer(minLength: 12)
            Text(value.isEmpty ? "—" : value)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Nạp & lưu

    private func load() {
        guard !ext.localPath.isEmpty else {
            errorText = "Tiện ích chưa được cài đặt cục bộ."
            isLoading = false
            return
        }
        do {
            let metadata = try ExtensionMetadataEditor.read(localPath: ext.localPath)
            loaded = metadata
            name = metadata.name
            source = metadata.source
            regexp = metadata.regexp
            descText = metadata.description
            locale = metadata.locale
            type = metadata.type
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    /// Gộp nhiều phím gõ thành **một** lượt ghi.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            performSave()
        }
    }

    private func saveNow() {
        saveTask?.cancel()
        performSave()
    }

    /// Chỉ những trường **khác bản đã nạp**. Rỗng ⇒ không ghi gì (lượt `onChange` do `load()` bắn ra rơi vào
    /// đây và dừng lại, không sinh lượt ghi giả).
    private func changedFields() -> [String: String] {
        var changes: [String: String] = [:]
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // Tên rỗng bị bỏ qua: một tiện ích không tên là tiện ích hỏng trong danh sách, và `name` cũng là
        // nguồn suy `packageId` khi cài mới.
        let loadedName = loaded.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty, trimmedName != loadedName { changes["name"] = trimmedName }
        if source != loaded.source { changes["source"] = source }
        if regexp != loaded.regexp { changes["regexp"] = regexp }
        if descText != loaded.description { changes["description"] = descText }
        if locale != loaded.locale { changes["locale"] = locale }
        if type != loaded.type { changes["type"] = type }
        return changes
    }

    private func performSave() {
        let changes = changedFields()
        guard !changes.isEmpty else { return }

        do {
            let changed = try ExtensionMetadataEditor.write(changes: changes, localPath: ext.localPath)
            guard !changed.isEmpty else { return }

            // 2. Hàng `Extension` — chỉ các trường có cột. `icon` không nằm trong màn này nên truyền lại giá
            // trị hiện có (command gán thẳng, không guard).
            let command = UpdateExtensionMetadataCommand(
                packageId: ext.packageId,
                name: changes["name"] ?? ext.name,
                sourceUrl: source,
                iconUrl: ext.iconUrl,
                desc: descText.isEmpty ? nil : descText,
                type: type,
                locale: locale
            )
            if case .failure(let error) = ExtensionTransactionCoordinator.shared.updateExtensionMetadata(
                command: command,
                in: modelContext
            ) {
                errorText = error.localizedDescription
                return
            }

            // 3. `regexp` được `BypassWebView` cache tĩnh theo `localPath` — không xoá thì bản mới không có
            // hiệu lực cho tới lần mở lại app.
            if changed.contains("regexp") {
                BypassWebView.invalidateRegexpCache(localPath: ext.localPath)
            }

            loaded = snapshotOfCurrentValues()
            errorText = ""
            statusText = "Đã lưu \(Self.timeText())"
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Bản ghi 6 trường đang hiển thị, giữ nguyên `author`/`version`/`language` đã nạp.
    private func snapshotOfCurrentValues() -> ExtensionMetadataEditor.Metadata {
        var snapshot = loaded
        snapshot.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        snapshot.source = source
        snapshot.regexp = regexp
        snapshot.description = descText
        snapshot.locale = locale
        snapshot.type = type
        return snapshot
    }

    private static func timeText() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }
}
