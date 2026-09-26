import SwiftUI

/// Màn hình tùy chỉnh System Prompt, Prompt trích xuất tên riêng và Trí nhớ AI toàn cục.
public struct AIPromptSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var systemPromptText: String = ""
    @State private var namePromptText: String = ""
    @State private var globalMemoryText: String = ""

    public init() {}

    public var body: some View {
        Form {
            Section {
                TextEditor(text: $systemPromptText)
                    .frame(minHeight: 120)
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
                    .frame(minHeight: 120)
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

            Section {
                TextEditor(text: $globalMemoryText)
                    .frame(minHeight: 140)
                    .font(.subheadline)

                HStack {
                    Button("Khôi phục mặc định") {
                        globalMemoryText = BookAIMemoryStore.shared.resetGlobalMemoryToDefault()
                    }
                    .font(.footnote)
                    .foregroundColor(.accentColor)

                    Spacer()

                    Button("Lưu trí nhớ") {
                        BookAIMemoryStore.shared.saveGlobalMemory(globalMemoryText)
                    }
                    .font(.footnote.bold())
                    .foregroundColor(.accentColor)
                }
            } header: {
                Text("Trí Nhớ AI Toàn Cục (Global Memory)")
            } footer: {
                Text("Quy tắc lọc tên riêng và ghi chú áp dụng chung cho mọi tác vụ AI trên toàn app.")
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
        .onChange(of: globalMemoryText) { _, newMem in
            BookAIMemoryStore.shared.saveGlobalMemory(newMem)
        }
        .onDisappear {
            savePrompts()
        }
    }

    private func loadPrompts() {
        let config = AISettingsStore.shared.loadConfiguration()
        systemPromptText = config.systemPrompt
        namePromptText = config.nameExtractionPrompt
        globalMemoryText = BookAIMemoryStore.shared.loadGlobalMemory()
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
        BookAIMemoryStore.shared.saveGlobalMemory(globalMemoryText)
    }
}
