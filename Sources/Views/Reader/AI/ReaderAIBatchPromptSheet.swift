import SwiftUI

/// Sheet chọn nguồn prompt cho chức năng "Quét tên riêng toàn bộ chương đã tải".
/// Prompt tự nhập chỉ dùng cho MỘT lần quét, không ghi vào Cài đặt.
public struct ReaderAIBatchPromptSheet: View {
    @Environment(\.dismiss) private var dismiss

    public let settingsPrompt: String
    public let onStart: (String) -> Void

    @State private var useCustomPrompt: Bool = false
    @State private var customPrompt: String = ""

    public init(settingsPrompt: String, onStart: @escaping (String) -> Void) {
        self.settingsPrompt = settingsPrompt
        self.onStart = onStart
        self._customPrompt = State(initialValue: settingsPrompt)
    }

    private var trimmedCustomPrompt: String {
        customPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canStart: Bool {
        !useCustomPrompt || !trimmedCustomPrompt.isEmpty
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    sourceRow(
                        title: "Dùng prompt trong Cài đặt",
                        subtitle: "Prompt trích xuất hiện hành",
                        isSelected: !useCustomPrompt
                    ) {
                        useCustomPrompt = false
                    }

                    sourceRow(
                        title: "Tự nhập prompt",
                        subtitle: nil,
                        isSelected: useCustomPrompt
                    ) {
                        useCustomPrompt = true
                    }
                } header: {
                    Text("Nguồn prompt")
                } footer: {
                    Text("Prompt tự nhập chỉ dùng cho lần quét này, không lưu vào Cài đặt.")
                }

                Section {
                    TextEditor(text: useCustomPrompt ? $customPrompt : Binding.constant(settingsPrompt))
                        .frame(minHeight: 180)
                        .font(.footnote)
                        .disabled(!useCustomPrompt)

                    if useCustomPrompt && trimmedCustomPrompt.isEmpty {
                        Text("Nhập prompt trích xuất tên riêng…")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                } header: {
                    Text("Prompt cho lần này")
                }
            }
            .navigationTitle("Quét tên riêng toàn bộ chương đã tải")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    let prompt = useCustomPrompt ? trimmedCustomPrompt : settingsPrompt
                    dismiss()
                    onStart(prompt)
                } label: {
                    Text("Bắt đầu quét")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(!canStart)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.bar)
            }
        }
    }

    @ViewBuilder
    private func sourceRow(
        title: String,
        subtitle: String?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundColor(.primary)
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
        }
        .buttonStyle(.plain)
    }
}
