import SwiftUI

/// Sheet "Bộ lọc" của một tiện ích: các mục `select` / công tắc / `list` khai trong `config` của `plugin.json`
/// (`ExtensionConfigSchema.filterKeys`, theo thứ tự trong file), dùng lại dòng của màn Cấu hình (`ExtensionConfigFieldRow`).
///
/// - Header: "Bộ lọc" + nút "Áp dụng" nhỏ (viên thuốc 28pt, chữ 13pt — người dùng yêu cầu nhỏ hơn nút chữ header chuẩn).
///   ↺ Đặt lại nằm trong khung, cùng hàng tiêu đề mục đầu tiên ("Sắp xếp"); mục đầu không phải ô chọn thì ở đầu khung.
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
    /// Chữ gốc → bản dịch của tiêu đề / dòng phụ / lựa chọn khi nguồn bật dịch (`translateLabels`, 1.3.685). Chỉ để hiện.
    @State private var translations: [String: String] = [:]

    private var isDirty: Bool {
        schema.filterKeys.contains { draft[$0] != savedValues[$0] }
    }

    var body: some View {
        NavigationStack {
            content
                .pageTitle("Bộ lọc")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: apply) {
                            // Kiểu chip đang chọn của `ExtensionKindFilterBar` (màu nhấn người dùng chọn, không tô đặc).
                            Text("Áp dụng")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.accentColor)
                                .padding(.horizontal, 12)
                                .frame(height: 28)
                                .background(Color.accentColor.opacity(0.18), in: Capsule())
                                .overlay(Capsule().stroke(Color.accentColor.opacity(0.6), lineWidth: 1))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(!loadError.isEmpty)
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
            let resetKey = resetRowKey
            Form {
                Section {
                    if schema.filterKeys.isEmpty {
                        Text(isLoaded ? "Tiện ích này không có bộ lọc." : "Đang đọc bộ lọc...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        if resetKey == nil {
                            // Mục đầu là công tắc / danh sách (bên phải dòng đã có điều khiển) ⇒ ↺ đứng riêng ở đầu khung.
                            HStack {
                                Spacer()
                                resetButton
                            }
                        }
                        ForEach(schema.filterKeys, id: \.self) { key in
                            if let item = schema.items[key] {
                                ExtensionConfigFieldRow(
                                    key: key,
                                    item: item,
                                    values: $draft,
                                    labelAccessory: key == resetKey ? AnyView(resetButton) : nil,
                                    displayText: { translations[$0] ?? $0 }
                                )
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
            .listSectionSpacing(.compact)
        }
    }

    /// Mục đầu tiên nếu là ô chọn — ↺ đứng ở đầu phải dòng tiêu đề của nó (cùng hàng "Sắp xếp").
    private var resetRowKey: String? {
        guard let first = schema.filterKeys.first, schema.items[first]?.mode == "select" else { return nil }
        return first
    }

    private var resetButton: some View {
        Button(action: resetToDefaults) {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.primary)
                .frame(width: 32, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Đặt lại mặc định")
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
            translateLabels(of: loaded, isChineseSource: ext.isChineseSource)
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Nguồn bật dịch (cấu hình dịch của nguồn — `TranslationConfigStore`, nguồn tiếng Trung tự bật) ⇒ dịch tiêu đề /
    /// dòng phụ / lựa chọn của các mục lọc **ngoài main** để hiển thị; chưa xong thì dòng hiện chữ gốc. Giá trị lưu vẫn là
    /// chữ gốc (script nhận đúng chuỗi đó). Màn Cấu hình tiện ích không dịch (người dùng chọn).
    private func translateLabels(of loaded: ExtensionConfigSchema, isChineseSource: Bool) {
        guard TranslationConfigStore.shared.isTranslationEnabled(
            bookId: nil,
            packageId: packageId,
            isChineseSourceHint: isChineseSource
        ) else { return }
        var texts = Set<String>()
        for key in loaded.filterKeys {
            guard let item = loaded.items[key] else { continue }
            texts.formUnion([item.title, item.subtitle].compactMap { $0 })
            texts.formUnion(item.values)
        }
        let sources = texts.filter { TranslateUtils.containsChinese($0) }
        guard !sources.isEmpty else { return }
        Task {
            let translated = await Task.detached(priority: .userInitiated) { () -> [String: String] in
                var map: [String: String] = [:]
                for text in sources {
                    let result = TranslateUtils.translateMeta(text).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !result.isEmpty { map[text] = result }
                }
                return map
            }.value
            translations = translated
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
