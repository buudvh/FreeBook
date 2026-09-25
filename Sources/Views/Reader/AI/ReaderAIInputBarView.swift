import SwiftUI

/// Thanh nhập tin nhắn tích hợp Menu chọn chế độ (Ask, Plan, Bypass) và Menu chọn Model.
public struct ReaderAIInputBarView: View {
    @Binding public var inputText: String
    @Binding public var selectedMode: AIHarnessMode
    @Binding public var selectedProfileId: String
    @Binding public var selectedModel: String
    public let availableProfiles: [AIProviderProfile]
    public let availableModels: [String]
    public let isStreaming: Bool
    public let onProfileChanged: ((String) -> Void)?
    public let onSend: () -> Void
    public let onStop: () -> Void

    public init(
        inputText: Binding<String>,
        selectedMode: Binding<AIHarnessMode>,
        selectedProfileId: Binding<String>,
        selectedModel: Binding<String>,
        availableProfiles: [AIProviderProfile] = [],
        availableModels: [String],
        isStreaming: Bool,
        onProfileChanged: ((String) -> Void)? = nil,
        onSend: @escaping () -> Void,
        onStop: @escaping () -> Void
    ) {
        self._inputText = inputText
        self._selectedMode = selectedMode
        self._selectedProfileId = selectedProfileId
        self._selectedModel = selectedModel
        self.availableProfiles = availableProfiles
        self.availableModels = availableModels
        self.isStreaming = isStreaming
        self.onProfileChanged = onProfileChanged
        self.onSend = onSend
        self.onStop = onStop
    }

    public var body: some View {
        VStack(spacing: 8) {
            // Khung nhập text
            TextField("Hỏi AI hoặc yêu cầu thao tác dữ liệu truyện...", text: $inputText, axis: .vertical)
                .lineLimit(1...5)
                .font(.system(size: 14))
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            // Thanh công cụ bên trong khung chat (Mode Pill + Model Picker + Send Button)
            HStack(spacing: 8) {
                // Menu chọn chế độ làm việc (Ask, Plan, Bypass)
                Menu {
                    ForEach(AIHarnessMode.allCases) { mode in
                        Button(action: { selectedMode = mode }) {
                            HStack {
                                Text("\(mode.title): \(mode.description)")
                                if selectedMode == mode {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text(selectedMode.shortDisplayTitle)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8))
                    }
                    .foregroundColor(.purple)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.purple.opacity(0.12))
                    .cornerRadius(8)
                }

                Spacer()

                // Menu chọn Provider
                if !availableProfiles.isEmpty {
                    Menu {
                        ForEach(availableProfiles) { profile in
                            Button(action: {
                                selectedProfileId = profile.id
                                onProfileChanged?(profile.id)
                            }) {
                                HStack {
                                    Text(profile.name)
                                    if selectedProfileId == profile.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "cpu")
                                .font(.system(size: 9))
                            Text(currentProfileName)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8))
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 5)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                    }
                }

                // Menu chọn Model AI
                Menu {
                    ForEach(availableModels, id: \.self) { model in
                        Button(action: { selectedModel = model }) {
                            HStack {
                                Text(model)
                                if selectedModel == model {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(selectedModel.isEmpty ? "Chọn model" : selectedModel)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                }

                // Nút Gửi hoặc Dừng (to 36x36 nổi bật)
                if isStreaming {
                    Button(action: onStop) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.red)
                            .clipShape(Circle())
                    }
                } else {
                    Button(action: onSend) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray.opacity(0.5) : Color(red: 36/255.0, green: 44/255.0, blue: 56/255.0))
                            .clipShape(Circle())
                    }
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var currentProfileName: String {
        availableProfiles.first(where: { $0.id == selectedProfileId })?.name ?? "Provider"
    }

    private var modeColor: Color {
        switch selectedMode {
        case .ask: return .orange
        case .plan: return .purple
        case .bypass: return .green
        }
    }
}
