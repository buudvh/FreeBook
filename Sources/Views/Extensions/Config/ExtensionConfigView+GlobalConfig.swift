import SwiftUI

/// Hai nhóm **"Cài đặt của tiện ích"** (biến `config` của `plugin.json`) và **"Mạng"** (cookie hệ thống) — tự lưu.
///
/// ## Một chuỗi `configJson` cho cả hai nhóm
/// Cả biến cấu hình lẫn `http_should_handle_cookies` nằm chung trong `Extension.configJson` (chuỗi này bị tiêm
/// thành biến global của JS). Mỗi lượt ghi dựng lại **toàn bộ** dict từ `userValues` — đúng luật của nút "Lưu"
/// cũ (`ExtensionConfigSchema.configJsonString`) — và ghi **im lặng** qua
/// `ExtensionTransactionCoordinator.saveExtensionConfig`: không toast, không đóng màn; lỗi hiện thành dòng chữ đỏ
/// trong nhóm + log `❌`. Dáng từng dòng ở `ExtensionConfigFieldRow` (dùng chung với sheet Bộ lọc).
///
/// ## Khi nào ghi
/// - Công tắc (biến `boolean`/`toggle`, cookie) và ô chọn (`select`): ghi ngay.
/// - Ô chữ/số: ghi sau 0,4 s kể từ phím cuối (như `ExtensionMetadataSection`) — tránh I/O mỗi phím và tránh một
///   lượt chạy JS đọc phải giá trị đang gõ dở.
/// - Màn đóng: **flush** lượt đang chờ (ghi ngay), không bỏ.
/// - Chỉ ghi khi `userValues` khác `persistedConfigValues` (bản vừa nạp/vừa ghi) ⇒ lần gán lúc nạp không sinh
///   lượt ghi giả.
extension ExtensionConfigView {
    // MARK: - Nhóm "Cài đặt của tiện ích"

    @ViewBuilder
    internal var globalConfigSection: some View {
        Section {
            if configSchema.keys.isEmpty {
                Text("Tiện ích này không có cài đặt riêng.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(configSchema.keys, id: \.self) { key in
                    if let item = configSchema.items[key] {
                        ExtensionConfigFieldRow(key: key, item: item, values: $userValues)
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
        let key = ExtensionConfigSchema.cookieKey
        return Section {
            Toggle("Xử lý cookie hệ thống", isOn: Binding(
                get: { (userValues[key] ?? "true") == "true" },
                set: { userValues[key] = $0 ? "true" : "false" }
            ))
            // DNS mã hoá riêng của tiện ích (1.3.831) — lưu ngay qua coordinator, không qua `configJson`.
            if current.isInstalled {
                ExtensionEncryptedDNSToggle(packageId: ext.packageId)
            }
            configSaveErrorRow
        } header: {
            SectionHelpHeader("Mạng", paragraphs: [
                "Xử lý cookie hệ thống: mặc định bật. Tắt tính năng này nếu tiện ích bị lỗi HTTP 400 do dính cookie đăng nhập Google/hệ thống (ví dụ: Google TTS).",
                "DNS mã hoá (DoH): mọi request trong script của tiện ích này tra tên miền qua máy chủ DNS mã hoá, để vào được trang bị nhà mạng chặn theo tên miền. Không áp cho trình duyệt, webview và trình phát phim/nhạc. Máy chủ chọn ở Cài đặt › Mạng & DNS; máy chủ không tới được thì tự đi DNS thường."
            ])
        } footer: {
            if current.isInstalled {
                ExtensionEncryptedDNSToggle.Footnote(packageId: ext.packageId)
            }
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

    // MARK: - Lưu

    /// Công tắc / ô chọn đổi ⇒ ghi ngay; chỉ ô chữ/số/danh sách đổi ⇒ chờ 0,4 s.
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
            key == ExtensionConfigSchema.cookieKey
                || configSchema.items[key].map { $0.isToggle || $0.mode == "select" } == true
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
            guard let jsonString = try configSchema.configJsonString(from: values) else { return }
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
}
