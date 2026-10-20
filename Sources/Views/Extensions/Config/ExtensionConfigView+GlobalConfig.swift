import SwiftUI

/// Hai nhóm **"Cài đặt của tiện ích"** (biến `config` của `plugin.json`) và **"Mạng"** (cookie hệ thống) — tự lưu.
///
/// ## Một chuỗi `configJson` cho cả hai nhóm
/// Cả biến cấu hình lẫn `http_should_handle_cookies` nằm chung trong `Extension.configJson` (chuỗi này bị tiêm
/// thành biến global của JS). Mỗi lượt ghi dựng lại **toàn bộ** dict từ `userValues` — đúng luật của nút "Lưu"
/// cũ — và ghi **im lặng** qua `ExtensionTransactionCoordinator.saveExtensionConfig`: không toast, không đóng màn;
/// lỗi hiện thành dòng chữ đỏ trong nhóm + log `❌`.
///
/// ## Khi nào ghi
/// - Công tắc (biến `boolean`/`toggle`, cookie): ghi ngay.
/// - Ô chữ/số: ghi sau 0,4 s kể từ phím cuối (như `ExtensionMetadataSection`) — tránh I/O mỗi phím và tránh một
///   lượt chạy JS đọc phải giá trị đang gõ dở.
/// - Màn đóng: **flush** lượt đang chờ (ghi ngay), không bỏ.
/// - Chỉ ghi khi `userValues` khác `persistedConfigValues` (bản vừa nạp/vừa ghi) ⇒ lần gán lúc nạp không sinh
///   lượt ghi giả.
extension ExtensionConfigView {
    static let cookieKey = "http_should_handle_cookies"

    // MARK: - Nhóm "Cài đặt của tiện ích"

    @ViewBuilder
    internal var globalConfigSection: some View {
        Section {
            if configDefinitions.isEmpty {
                Text("Tiện ích này không có cài đặt riêng.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(configDefinitions.keys.sorted(), id: \.self) { key in
                    if let definition = configDefinitions[key] {
                        configRow(key: key, definition: definition)
                    }
                }
            }
            configSaveErrorRow
        } header: {
            Text("Cài đặt của tiện ích")
        }
    }

    // MARK: - Nhóm "Mạng"

    internal var networkSection: some View {
        let key = Self.cookieKey
        return Section {
            Toggle("Xử lý cookie hệ thống", isOn: Binding(
                get: { (userValues[key] ?? "true") == "true" },
                set: { userValues[key] = $0 ? "true" : "false" }
            ))
            configSaveErrorRow
        } header: {
            Text("Mạng")
        } footer: {
            Text("Mặc định bật. Tắt tính năng này nếu tiện ích bị lỗi HTTP 400 do dính cookie đăng nhập Google/hệ thống (ví dụ: Google TTS).")
        }
    }

    // MARK: - Dòng

    @ViewBuilder
    private var configSaveErrorRow: some View {
        if !configSaveError.isEmpty {
            Text(configSaveError)
                .font(.caption)
                .foregroundColor(.red)
        }
    }

    /// Ba dáng dòng:
    /// - công tắc: tiêu đề + khoá bên trái, `Toggle` bên phải;
    /// - số: ô gọn bên phải (giá trị ngắn);
    /// - chữ (thường là URL dài): tiêu đề + khoá, bộ nút ↺ · xoá · sao chép · dán bên phải, ô nhập **rộng hết dòng**
    ///   ở dưới — để bên phải thì URL bị cắt chỉ còn vài ký tự. Giá trị mặc định là chữ mờ trong ô khi ô trống.
    @ViewBuilder
    private func configRow(key: String, definition: ConfigItem) -> some View {
        if Self.isToggle(definition) {
            Toggle(isOn: Binding(
                get: { (userValues[key] ?? definition.default ?? "false") == "true" },
                set: { userValues[key] = $0 ? "true" : "false" }
            )) {
                configRowLabel(key: key, definition: definition)
            }
        } else if definition.format == "number" {
            HStack(spacing: 12) {
                configRowLabel(key: key, definition: definition)
                Spacer(minLength: 8)
                TextField(definition.default ?? "", text: configTextBinding(key))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .font(.callout.monospacedDigit())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .frame(width: 90)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        } else {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .top, spacing: 8) {
                    configRowLabel(key: key, definition: definition)
                    Spacer(minLength: 8)
                    TextFieldClipboardButtons(text: configTextBinding(key), defaultValue: definition.default)
                }
                TextField(definition.default ?? "", text: configTextBinding(key))
                    .font(.footnote)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .lineLimit(1)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .padding(.vertical, 2)
        }
    }

    private func configTextBinding(_ key: String) -> Binding<String> {
        Binding(
            get: { userValues[key] ?? "" },
            set: { userValues[key] = $0 }
        )
    }

    /// Tiêu đề + dòng phụ là **khoá** (chữ đều, một dòng). Không ghi "mặc định X" ở đây: mặc định thường là URL dài,
    /// kéo dòng phụ xuống 3–4 dòng; nó đã là chữ mờ trong ô và là đích của nút ↺.
    private func configRowLabel(key: String, definition: ConfigItem) -> some View {
        let title = definition.title ?? key
        return VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline)
            if title != key {
                Text(key)
                    .font(.caption2.monospaced())
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    nonisolated private static func isToggle(_ definition: ConfigItem) -> Bool {
        definition.format == "boolean" || definition.mode == "toggle"
    }

    // MARK: - Lưu

    /// Công tắc đổi ⇒ ghi ngay; chỉ ô chữ/số đổi ⇒ chờ 0,4 s.
    internal func handleConfigChange(from oldValues: [String: String], to newValues: [String: String]) {
        guard !isLoading, errorMessage.isEmpty else { return }
        guard newValues != persistedConfigValues else {
            // Gõ rồi xoá về đúng giá trị đã lưu: bỏ lượt đang chờ, không có gì để ghi.
            configSaveTask?.cancel()
            configSaveTask = nil
            return
        }
        let changedKeys = Set(oldValues.keys).union(newValues.keys).filter { oldValues[$0] != newValues[$0] }
        let hasDiscreteChange = changedKeys.contains { key in
            key == Self.cookieKey || configDefinitions[key].map { Self.isToggle($0) } == true
        }
        if hasDiscreteChange {
            configSaveTask?.cancel()
            configSaveTask = nil
            persistConfigIfChanged()
        } else {
            scheduleConfigSave()
        }
    }

    private func scheduleConfigSave() {
        configSaveTask?.cancel()
        configSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            persistConfigIfChanged()
        }
    }

    /// Gọi khi màn đóng: ghi ngay lượt đang chờ. Bỏ qua khi tiện ích vừa bị gỡ (không còn bản ghi để lưu).
    internal func flushPendingConfigSave() {
        configSaveTask?.cancel()
        configSaveTask = nil
        guard !isLoading, errorMessage.isEmpty,
              ExtensionLibraryRepository.shared.installedExtension(packageId: ext.packageId) != nil else { return }
        persistConfigIfChanged()
    }

    private func persistConfigIfChanged() {
        configSaveTask = nil
        let values = userValues
        guard values != persistedConfigValues else { return }
        do {
            guard let jsonString = try Self.configJsonString(from: values, definitions: configDefinitions) else { return }
            let cmd = ExtensionConfigCommand(packageId: ext.packageId, configJson: jsonString)
            switch ExtensionTransactionCoordinator.shared.saveExtensionConfig(command: cmd) {
            case .success:
                persistedConfigValues = values
                configSaveError = ""
            case .failure(let err):
                reportConfigSaveError(err.localizedDescription)
            }
        } catch {
            reportConfigSaveError(error.localizedDescription)
        }
    }

    private func reportConfigSaveError(_ message: String) {
        AppLogger.shared.log("❌ [ExtConfig] Lỗi lưu cấu hình của \(current.name): \(message)")
        configSaveError = "Không lưu được cấu hình: \(message)"
    }

    /// Dựng `configJson` — giữ nguyên luật của `saveConfig()` cũ: bỏ giá trị rỗng, cookie luôn là bool, `boolean`
    /// ⇒ bool, `number` ⇒ Int/Double (không parse được thì giữ chuỗi), còn lại là chuỗi.
    private static func configJsonString(from values: [String: String], definitions: [String: ConfigItem]) throws -> String? {
        var typedDict: [String: Any] = [:]
        for (key, strVal) in values {
            guard !strVal.isEmpty else { continue }
            if key == cookieKey {
                typedDict[key] = (strVal.lowercased() == "true")
                continue
            }
            let fmt = definitions[key]?.format
            if fmt == "boolean" {
                typedDict[key] = (strVal.lowercased() == "true")
            } else if fmt == "number" {
                if let iVal = Int(strVal) {
                    typedDict[key] = iVal
                } else if let dVal = Double(strVal) {
                    typedDict[key] = dVal
                } else {
                    typedDict[key] = strVal
                }
            } else {
                typedDict[key] = strVal
            }
        }
        if typedDict[cookieKey] == nil {
            typedDict[cookieKey] = (values[cookieKey]?.lowercased() != "false")
        }

        let data = try JSONSerialization.data(withJSONObject: typedDict, options: [])
        return String(data: data, encoding: .utf8)
    }
}
