import SwiftUI

/// Xuất TXT từng từ điển chung (1.3.638): icon ↑ phủ lên cuối thẻ (chạm thẻ vẫn là Nhập), xuất ở luồng nền qua
/// `GlobalDictionaryTextExporter` rồi mở bảng chia sẻ; đóng bảng thì xoá file tạm.
extension TranslationSettingsView {
    /// File tạm chờ chia sẻ — bọc `Identifiable` cho `sheet(item:)`.
    struct DictionaryTextExport: Identifiable {
        let url: URL
        let title: String
        var id: String { url.absoluteString }
    }

    /// Icon xuất phủ lên chỗ `DictionaryCard(reservesExportSlot: true)` chừa sẵn. Ẩn khi thẻ đang nhập/xuất (thẻ tự
    /// hiện vòng quay); mờ và không bấm được khi từ điển chưa có dữ liệu hoặc đang có lượt xuất khác.
    @ViewBuilder
    func dictionaryExportButton(type: String, title: String, isSet: Bool) -> some View {
        if !importingTypes.contains(type) && exportingDictionaryType != type {
            let isEnabled = isSet && exportingDictionaryType == nil
            Button {
                exportDictionary(type: type, title: title)
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isEnabled ? 1 : 0.3)
            .disabled(!isEnabled)
            .padding(.trailing, 10)
            .accessibilityLabel("Xuất \(title)")
        }
    }

    func dictionaryShareSheet(_ export: DictionaryTextExport) -> some View {
        ShareSheet(activityItems: [export.url]) { _, completed, _, error in
            if completed {
                ToastManager.shared.show(message: "Đã xuất \(export.title)", type: .success)
            } else if let error = error {
                ToastManager.shared.show(message: "Lỗi chia sẻ: \(error.localizedDescription)", type: .error)
            }
        }
    }

    func cleanUpDictionaryExport() {
        guard let url = dictionaryExportURL else { return }
        try? FileManager.default.removeItem(at: url)
        dictionaryExportURL = nil
    }

    private func exportDictionary(type: String, title: String) {
        guard exportingDictionaryType == nil, !importingTypes.contains(type) else { return }
        exportingDictionaryType = type
        Task {
            // Duyệt cây VietPhrase (trăm nghìn – triệu từ) mất vài giây ⇒ ra khỏi main thread.
            let result = await Task.detached(priority: .userInitiated) {
                Result { try GlobalDictionaryTextExporter.export(type: type) }
            }.value
            await MainActor.run {
                exportingDictionaryType = nil
                switch result {
                case .success(let url):
                    cleanUpDictionaryExport()
                    dictionaryExportURL = url
                    dictionaryExport = DictionaryTextExport(url: url, title: title)
                case .failure(let error):
                    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    AppLogger.shared.log("❌ Lỗi xuất \(title): \(message)")
                    ToastManager.shared.show(message: "Lỗi xuất \(title): \(message)", type: .error)
                }
            }
        }
    }
}
