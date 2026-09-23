import SwiftUI

/// Section dẫn vào màn hình Cấu hình AI từ trang Settings chính.
public struct AISettingsSection: View {
    public init() {}

    public var body: some View {
        Section(header: Text("Trợ Lý AI (Agent Harness)")) {
            NavigationLink(destination: AISettingsView()) {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .foregroundColor(.purple)
                        .font(.system(size: 18))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cấu hình API & Model AI")
                            .font(.body)
                        Text("OpenAI, Gemini, Claude, DeepSeek, Groq...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}
