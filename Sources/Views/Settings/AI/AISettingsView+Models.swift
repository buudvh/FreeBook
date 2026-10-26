import SwiftUI

/// Khối quản lý model của profile đang chọn trong màn "Cấu hình AI" — tách khỏi file gốc (1.3.609) để ẩn gọn cả khối
/// với profile Chế độ AI của Google (không có model để chọn).
extension AISettingsView {
    @ViewBuilder
    internal var modelManagementRows: some View {
        // Quản lý model của profile
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Model đang chọn:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(config.activeProfile.selectedModel.isEmpty ? "Chưa chọn" : config.activeProfile.selectedModel)
                    .font(.system(.subheadline, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundColor(.purple)
            }
            Spacer()
            Button(action: fetchModelsFromAPI) {
                HStack(spacing: 4) {
                    if isFetchingModels {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    Text("Load từ API")
                }
                .font(.subheadline)
            }
            .disabled(isFetchingModels || config.activeProfile.baseURL.isEmpty)
        }

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Danh sách Model (\(parsedModelsCount) models):")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                clipboardToolbar(for: $modelsText) {
                    syncModelsFromText(modelsText)
                }
            }
            TextEditor(text: $modelsText)
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: 80)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
                .onChange(of: modelsText) { _, newText in
                    syncModelsFromText(newText)
                }
        }
    }
}
