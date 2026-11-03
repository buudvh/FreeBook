import SwiftUI

/// Sheet "Bộ lọc" của một tiện ích: các mục `select` / công tắc / `list` khai trong `config` của `plugin.json`
/// (`ExtensionConfigSchema.filterKeys`, theo thứ tự trong file), dùng lại dòng của màn Cấu hình (`ExtensionConfigFieldRow`).
///
/// - Sửa trên bản nháp; ↺ đưa bản nháp về mặc định. "Áp dụng" mới ghi — **lưu vĩnh viễn** vào `configJson` qua
///   `ExtensionTransactionCoordinator` (màn Cấu hình thấy cùng giá trị), rồi gọi `onApplied` với chuỗi vừa ghi để màn
///   danh sách tải lại từ trang 1. Không đổi gì ⇒ chỉ đóng.
/// - Khi ghi: đọc lại config **mới nhất** của tiện ích, chỉ thay khoá lọc — các ô khác (`BASE_URL`, cookie…) giữ nguyên.
/// - Vuốt đóng khi bản nháp khác bản đã lưu ⇒ hỏi bỏ thay đổi (`confirmDiscardOnSwipe`).
struct ExtensionFilterSheet: View {
    @Environment(\.dismiss) private var dismiss

    let packageId: String
    var onApplied: (_ configJson: String) -> Void = { _ in }

    @State private var schema = ExtensionConfigSchema()
    @State private var savedValues: [String: String] = [:]
    @State private var draft: [String: String] = [:]
    @State private var isLoaded = false
    @State private var loadError = ""
    @State private var saveError = ""

    private var isDirty: Bool {
        schema.filterKeys.contains { draft[$0] != savedValues[$0] }
    }

    var body: some View {
        NavigationStack {
            content
                .pageTitle("Bộ lọc")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        HStack(spacing: 10) {
                            Button(action: resetToDefaults) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 17, weight: .semibold))
                                    .frame(width: HeaderButtonMetrics.pairIconWidth, height: 36)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityLabel("Đặt lại mặc định")
                            .disabled(schema.filterKeys.isEmpty)

                            Button("Áp dụng", action: apply)
                                .headerTextButton()
                                .disabled(!loadError.isEmpty)
                        }
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .confirmDiscardOnSwipe(isDirty: isDirty)
        .onAppear {
            if !isLoaded { load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if !loadError.isEmpty {
            Text(loadError)
                .font(.subheadline)
                .foregroundColor(.red)
                .multilineTextAlignment(.center)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Form {
                Section {
                    if schema.filterKeys.isEmpty {
                        Text(isLoaded ? "Tiện ích này không có bộ lọc." : "Đang đọc bộ lọc...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(schema.filterKeys, id: \.self) { key in
                            if let item = schema.items[key] {
                                ExtensionConfigFieldRow(key: key, item: item, values: $draft)
                            }
                        }
                    }
                    if !saveError.isEmpty {
                        Text(saveError)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: Color(white: 0.35)))
            .listSectionSpacing(.compact)
        }
    }

    private func load() {
        isLoaded = true
        guard let ext = ExtensionLibraryRepository.shared.installedExtension(packageId: packageId) else {
            loadError = "Tiện ích đã bị gỡ."
            return
        }
        do {
            let loaded = try ExtensionConfigSchema.load(localPath: ext.localPath)
            let values = loaded.initialValues(configJson: ext.configJson)
            schema = loaded
            savedValues = values
            draft = values
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func resetToDefaults() {
        for key in schema.filterKeys {
            draft[key] = schema.items[key]?.default ?? ""
        }
    }

    private func apply() {
        guard isDirty else {
            dismiss()
            return
        }
        guard let ext = ExtensionLibraryRepository.shared.installedExtension(packageId: packageId) else {
            saveError = "Tiện ích đã bị gỡ."
            return
        }
        var values = schema.initialValues(configJson: ext.configJson)
        for key in schema.filterKeys {
            values[key] = draft[key] ?? ""
        }
        do {
            guard let json = try schema.configJsonString(from: values) else { return }
            let command = ExtensionConfigCommand(packageId: packageId, configJson: json)
            switch ExtensionTransactionCoordinator.shared.saveExtensionConfig(command: command) {
            case .success:
                savedValues = draft // hết "chưa lưu" ⇒ lượt đóng dưới đây không bị hỏi
                AppLogger.shared.log("🔎 [ExtFilter] Áp dụng bộ lọc của \(ext.name)")
                onApplied(json)
                dismiss()
            case .failure(let err):
                reportSaveError(err.localizedDescription, name: ext.name)
            }
        } catch {
            reportSaveError(error.localizedDescription, name: ext.name)
        }
    }

    private func reportSaveError(_ message: String, name: String) {
        AppLogger.shared.log("❌ [ExtFilter] Lỗi lưu bộ lọc của \(name): \(message)")
        saveError = "Không lưu được bộ lọc: \(message)"
    }
}
