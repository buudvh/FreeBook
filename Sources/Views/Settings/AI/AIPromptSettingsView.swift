import SwiftUI

/// Màn hình tùy chỉnh System Prompt và Prompt trích xuất tên riêng của AI.
public struct AIPromptSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var systemPromptText: String = ""
    @State private var namePromptText: String = ""

    public init() {}

    public var body: some View {
        Form {
            Section {
                TextEditor(text: $systemPromptText)
                    .frame(minHeight: 140)
                    .font(.subheadline)

                Button("Khôi phục System Prompt mặc định") {
                    systemPromptText = AIConfiguration.defaultSystemPrompt
                    savePrompts()
                }
                .font(.footnote)
                .foregroundColor(.accentColor)
            } header: {
                Text("System Prompt Trò chuyện")
            } footer: {
                Text("Định hình phong cách trả lời, vai trò và quy tắc ứng xử của AI khi bạn trò chuyện trong sách.")
            }

            Section {
                TextEditor(text: $namePromptText)
                    .frame(minHeight: 140)
                    .font(.subheadline)

                Button("Khôi phục Prompt trích xuất mặc định") {
                    namePromptText = AIConfiguration.defaultNameExtractionPrompt
                    savePrompts()
                }
                .font(.footnote)
                .foregroundColor(.accentColor)
            } header: {
                Text("Prompt Trích xuất Tên riêng (Name Extraction)")
            } footer: {
                Text("Chỉ dẫn cho AI cách quét và trích xuất nhân vật, địa danh, công pháp từ văn bản raw tiếng Trung thành mảng JSON.")
            }
        }
        .navigationTitle("Tùy chỉnh Prompt AI")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadPrompts()
        }
        .onChange(of: systemPromptText) { _, _ in
            savePrompts()
        }
        .onChange(of: namePromptText) { _, _ in
            savePrompts()
        }
        .onDisappear {
            savePrompts()
        }
    }

    private func loadPrompts() {
        let config = AISettingsStore.shared.loadConfiguration()
        systemPromptText = config.systemPrompt
        namePromptText = config.nameExtractionPrompt
    }

    private func savePrompts() {
        var config = AISettingsStore.shared.loadConfiguration()
        config.systemPrompt = systemPromptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? AIConfiguration.defaultSystemPrompt
            : systemPromptText
        config.nameExtractionPrompt = namePromptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? AIConfiguration.defaultNameExtractionPrompt
            : namePromptText
        AISettingsStore.shared.saveConfiguration(config)
    }
}
